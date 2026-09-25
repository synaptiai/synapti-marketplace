# Bash assertions for plugins/dossier/tests.
#
# Each assertion emits PASS/FAIL to stdout with a file:line citation derived
# from the caller's BASH_SOURCE/LINENO, and returns 0/1 so a calling script
# can decide whether to keep going or abort. The runner aggregates pass/fail
# counts via the DOSSIER_TEST_PASS / DOSSIER_TEST_FAIL counters maintained here.
#
# Conventions:
#   - All assertions read DOSSIER_TEST_CURRENT (the current test name) to label
#     output. Tests call _dossier_test_begin "name" before assertions.
#   - Assertions write to stdout (captured by run.sh); diagnostic detail goes
#     to the same line so a tail of the output reads like a checklist.
#   - No external dependencies beyond standard POSIX utilities.

# Counters live in the test process. run.sh re-sources this file per test
# file (each test runs in a fresh subshell), so the counters reset between
# files but accumulate within a file.
: "${DOSSIER_TEST_PASS:=0}"
: "${DOSSIER_TEST_FAIL:=0}"
: "${DOSSIER_TEST_CURRENT:=<unset>}"

_dossier_test_begin() {
  DOSSIER_TEST_CURRENT="$1"
}

# _dossier_safe_mktemp_dir <prefix> — the only sanctioned way for a test
# fixture to create a git-fixture directory. Bare `mktemp -d "$RUN_TMPDIR/…"`
# followed by `cd "$VAR" || exit 1` fails open: if RUN_TMPDIR is unset/empty
# (invoking a test file directly, bypassing run.sh) or mktemp itself fails,
# `$VAR` is empty, and `cd ""` returns 0 in bash — a silent no-op that leaves
# every subsequent command running in the real caller's directory instead of
# aborting. This happened for real during development: a fixture's git
# init/commit/checkout/merge and `rm -rf .claude` ran against this actual
# repository, deleting the tracked .claude/ directory and polluting main with
# fixture commits. Exits 2 (a runner-level failure, not a test failure) rather
# than returning empty, so a caller relying on `$(...)` cannot receive "" and
# proceed regardless.
_dossier_safe_mktemp_dir() {
  # `_dir` is local defensively: this function is currently always invoked
  # via `$(...)` (which subshell-isolates it regardless), but that isolation
  # is an accident of every current caller's shape, not a documented
  # invariant of this function itself — see _dossier_require_mktemp_dir's
  # docstring, which actively tells future contributors to convert
  # stdout-returning helpers like this one to a plain-statement out-param
  # call. `local` here means that conversion can never silently clobber a
  # caller's own `_dir` (e.g. no_gh_path's `for _dir in $PATH` loop
  # variable), regardless of what shape a future caller takes.
  local _dir
  if [ -z "${RUN_TMPDIR:-}" ] || [ ! -d "$RUN_TMPDIR" ]; then
    echo "FATAL: RUN_TMPDIR is unset or not a directory — this test file must be run via tests/run.sh, not invoked directly" >&2
    exit 2
  fi
  _dir=$(mktemp -d "$RUN_TMPDIR/${1:-fixture}.XXXXXX") || {
    echo "FATAL: mktemp -d under RUN_TMPDIR failed" >&2
    exit 2
  }
  if [ -z "$_dir" ] || [ ! -d "$_dir" ]; then
    echo "FATAL: mktemp -d returned an unusable path: '$_dir'" >&2
    exit 2
  fi
  printf '%s\n' "$_dir"
}

# _dossier_require_mktemp_dir <varname> <prefix> — the sanctioned way for a
# call site to consume _dossier_safe_mktemp_dir's output. A bare
# `VAR=$(_dossier_safe_mktemp_dir ...)` reopens the exact risk that function
# was hardened against: its `exit 2` only terminates the `$(...)` subshell,
# so a caller that doesn't check the assignment's own exit status proceeds
# with VAR="" — and `cd ""` returns 0 in bash, silently no-oping instead of
# aborting (issue #149; this happened for real to local-merge-hook.test.sh).
# This helper does the capture-and-check exactly once, as a plain function
# call (not itself wrapped in `$(...)`), so an internal failure's `exit 2`
# propagates all the way up through the caller's shell rather than being
# swallowed by another layer of subshell.
#
# That guarantee is only as good as every caller in the chain: if you write
# a function that calls this helper internally and then hands its result
# back to ITS OWN caller via stdout (`printf '%s' "$var"`, meant to be
# consumed as `X=$(your_function)`), you have reintroduced the exact bug
# this helper exists to close, one level up — `$(...)` forks a subshell for
# your_function's entire body, so this helper's `exit 2` again only kills
# that subshell. Give your function an <outvar> parameter and assign into
# it via `_dossier_assign_outvar` (below) instead, and call it as a plain
# statement, the same way this helper itself must be called. See
# `no_gh_path`/`setup_fixture` in rotation-check.test.sh and
# staleness-trigger.test.sh for the pattern, and mktemp-guard.test.sh
# scenario 4 for the regression test.
#
# Callers of your <outvar> function must also avoid naming their outvar
# argument the same as any of the function's own `local` variables (a
# collision silently assigns the function's local shadow instead of the
# caller's variable, since bash resolves `printf -v` by innermost scope) —
# see `no_gh_path`/`setup_fixture`'s own local declarations for the names
# already in use.
_dossier_require_mktemp_dir() {
  local __dossier_mktemp_varname="$1" __dossier_mktemp_prefix="$2" __dossier_mktemp_dir
  __dossier_mktemp_dir=$(_dossier_safe_mktemp_dir "$__dossier_mktemp_prefix") || exit 2
  if [ -z "$__dossier_mktemp_dir" ] || [ ! -d "$__dossier_mktemp_dir" ]; then
    echo "FATAL: _dossier_safe_mktemp_dir(\"$__dossier_mktemp_prefix\") returned an unusable path for \$$__dossier_mktemp_varname: '$__dossier_mktemp_dir'" >&2
    exit 2
  fi
  _dossier_assign_outvar "$__dossier_mktemp_varname" "$__dossier_mktemp_dir"
}

# _dossier_assign_outvar <varname> <value> — the one guarded way to assign
# into a caller-named "out parameter" via `printf -v`, used both by
# _dossier_require_mktemp_dir above and by any wrapper function that
# re-exposes its own result through an outvar (see that function's
# docstring for why stdout+$(...) is unsafe here). A bare `printf -v` can
# fail silently (invalid identifier, readonly/array-name collision) and
# return non-zero with no message — under this suite's `set -uo pipefail`
# (no `-e`), that failure would otherwise be swallowed exactly like the
# bug this file exists to close. Centralized here so the guard can't be
# dropped on the next copy-paste of the out-parameter pattern.
_dossier_assign_outvar() {
  local __dossier_assign_varname="$1" __dossier_assign_value="$2"
  printf -v "$__dossier_assign_varname" '%s' "$__dossier_assign_value" || {
    echo "FATAL: printf -v failed to assign \$$__dossier_assign_varname (invalid identifier?)" >&2
    exit 2
  }
}

# -----------------------------------------------------------------------------
# Fixture isolation (issue #252)
#
# A test's git commands must only ever act on repositories the test built
# under this run's temp directory (RUN_TMPDIR). Before this section existed, a
# fixture step was `( cd "$F" || exit 1; git config ...; git commit; git push
# origin ...; git remote set-url ... )`, and every one of those steps trusted
# `$F`. When `$F` was empty, `cd ""` succeeded as a no-op and the whole step
# ran in whatever repository the suite was started from: running
# rotation-check.test.sh directly (without this library, so setup_fixture
# never assigned F1..F22) switched the caller's worktree to a new
# docs/dossier branch, wrote user.name/user.email and a fake
# remote.origin.url into its shared config, and pushed docs/dossier to its
# real origin five times.
#
# The guarantees below hold by default, without any call site remembering
# them:
#   - `git` is a shell function that refuses to run unless the directory it
#     would act in, and the repository it would find there, are inside
#     RUN_TMPDIR. Test bodies cannot reach the caller's repository through git,
#     whatever `cd` did before.
#   - `cd` refuses an empty operand instead of silently staying put.
#   - run.sh clears inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG_* and friends
#     and sets GIT_CEILING_DIRECTORIES to RUN_TMPDIR, so the scripts under test
#     (separate processes, which these functions cannot reach) cannot walk up
#     out of a broken fixture into an enclosing repository either.
#   - Every refusal is recorded under RUN_TMPDIR and turned into a FAIL by
#     _dossier_test_summary, so it fails the test even when it happened inside
#     a subshell whose output was sent to /dev/null.
# _dossier_in_fixture and _dossier_fixture_ready add a message that names the
# fixture variable, which is what a reader needs to find the broken setup.
# -----------------------------------------------------------------------------

# Canonical physical path of an existing directory, or nothing.
_dossier_real_dir() {
  ( builtin cd -- "$1" 2>/dev/null && pwd -P )
}

# Canonical path of $1 (relative paths resolve against $2, default $PWD),
# whether or not it exists yet: the nearest existing ancestor is resolved and
# the missing tail is appended. `git init <dir>` and `git clone <src> <dir>`
# name directories that do not exist yet.
_dossier_real_path() {
  local __p="$1" __base="${2:-$PWD}" __tail="" __real
  case "$__p" in
    /*) ;;
    *) __p="$__base/$__p" ;;
  esac
  while [ ! -d "$__p" ]; do
    case "$__p" in
      /|"") break ;;
    esac
    __tail="/${__p##*/}$__tail"
    __p=$(dirname -- "$__p")
  done
  __real=$(_dossier_real_dir "$__p") || return 1
  [ -n "$__real" ] || return 1
  printf '%s%s\n' "${__real%/}" "$__tail"
}

# Succeeds when $1 (resolved against $2) lies strictly inside RUN_TMPDIR.
_dossier_path_in_run_tmpdir() {
  local __root __real
  [ -n "${RUN_TMPDIR:-}" ] && [ -d "$RUN_TMPDIR" ] || return 1
  __root=$(_dossier_real_dir "$RUN_TMPDIR") || return 1
  [ -n "$__root" ] || return 1
  __real=$(_dossier_real_path "$1" "${2:-$PWD}") || return 1
  case "$__real" in
    "$__root"/?*) return 0 ;;
  esac
  return 1
}

_dossier_fixture_violation() {
  printf 'FIXTURE-GUARD: %s\n' "$1" >&2
  if [ -n "${RUN_TMPDIR:-}" ] && [ -d "$RUN_TMPDIR" ]; then
    printf '%s\n' "$1" | tr '\n' ' ' >> "$RUN_TMPDIR/.dossier-fixture-violations"
    printf '\n' >> "$RUN_TMPDIR/.dossier-fixture-violations"
  fi
}

# _dossier_in_fixture <VARNAME> [<label>] — the way a fixture step enters its
# fixture: `( _dossier_in_fixture F6 || exit 1; git ... )` or
# `OUT=$(_dossier_in_fixture F6 && "$SCRIPT")`. Takes the variable's NAME so a
# failure can say which fixture was missing. Refuses (returns 1, records a
# violation) when the variable is unset or empty, names something that is not
# a directory, or points outside RUN_TMPDIR; otherwise changes into it.
_dossier_in_fixture() {
  local __name="$1" __label="${2:-$1}" __dir
  case "$__name" in
    ''|[0-9]*|*[!A-Za-z0-9_]*)
      _dossier_fixture_violation "_dossier_in_fixture: '$__name' is not a variable name"
      return 1 ;;
  esac
  __dir="${!__name:-}"
  if [ -z "$__dir" ]; then
    _dossier_fixture_violation "fixture $__label is empty: its setup did not run or did not succeed, so the step was refused instead of running in $(pwd -P)"
    return 1
  fi
  if [ ! -d "$__dir" ]; then
    _dossier_fixture_violation "fixture $__label does not exist: '$__dir'"
    return 1
  fi
  if ! _dossier_path_in_run_tmpdir "$__dir"; then
    _dossier_fixture_violation "fixture $__label is outside this run's temp directory: '$__dir'"
    return 1
  fi
  builtin cd -- "$__dir" || {
    _dossier_fixture_violation "fixture $__label cannot be entered: '$__dir'"
    return 1
  }
}

# _dossier_fixture_ready <label> <path> [bare] — after building a fixture
# repository, confirms it really is one, rooted exactly at <path> (a failed
# init/clone leaves a plain directory, or none). Records a violation naming
# <label> and returns 1 otherwise; callers then leave the fixture variable
# empty so every later step that names it is refused too.
_dossier_fixture_ready() {
  local __label="$1" __path="$2" __kind="${3:-worktree}" __want __got
  if [ -z "$__path" ] || [ ! -d "$__path" ]; then
    _dossier_fixture_violation "fixture $__label could not be created: '$__path' does not exist"
    return 1
  fi
  __want=$(_dossier_real_dir "$__path")
  if [ "$__kind" = "bare" ]; then
    __got=$(command git -C "$__path" rev-parse --absolute-git-dir 2>/dev/null)
    [ -n "$__got" ] && __got=$(_dossier_real_dir "$__got")
  else
    __got=$(command git -C "$__path" rev-parse --show-toplevel 2>/dev/null)
    [ -n "$__got" ] && __got=$(_dossier_real_dir "$__got")
  fi
  if [ -z "$__got" ] || [ "$__got" != "$__want" ]; then
    _dossier_fixture_violation "fixture $__label could not be created: '$__path' is not a git repository of its own${__got:+ (git resolves it to $__got)}"
    return 1
  fi
}

# cd with an empty operand is a successful no-op in bash; in a fixture step
# that means "run the rest of this step in the caller's repository". Refuse it.
cd() {
  local __a __seen=0
  for __a in "$@"; do
    case "$__a" in
      -L|-P|-e|-@|--) continue ;;
    esac
    __seen=1
    if [ -z "$__a" ]; then
      _dossier_fixture_violation "cd was given an empty path (in $(pwd -P)); a fixture variable is empty"
      return 1
    fi
  done
  if [ "$__seen" = "0" ]; then
    _dossier_fixture_violation "cd without a directory (in $(pwd -P)) would move to \$HOME"
    return 1
  fi
  builtin cd "$@" || return
}

# The git guard. Resolves where git would act — the working directory after
# every -C, any --git-dir/--work-tree, the target directory of init/clone,
# and the repository git would discover there — and refuses unless all of it
# is inside RUN_TMPDIR.
_dossier_git_guard() {
  local __dir="$PWD" __sub="" __a __gd __what __n
  if [ -z "${RUN_TMPDIR:-}" ] || [ ! -d "$RUN_TMPDIR" ]; then
    _dossier_fixture_violation "git $* refused: RUN_TMPDIR is unset, so there is no fixture area (run the suite through tests/run.sh)"
    return 1
  fi
  for __n in GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY; do
    __a="${!__n:-}"
    if [ -n "$__a" ] && ! _dossier_path_in_run_tmpdir "$__a" "$__dir"; then
      _dossier_fixture_violation "git $* refused: $__n points outside the fixture area ($__a)"
      return 1
    fi
  done
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -C)
        if [ -z "${2:-}" ]; then
          _dossier_fixture_violation "git -C was given an empty path (in $__dir); a fixture variable is empty"
          return 1
        fi
        case "$2" in
          /*) __dir="$2" ;;
          *) __dir="$__dir/$2" ;;
        esac
        shift 2 ;;
      --git-dir=*|--work-tree=*)
        __a="${1#*=}"
        if [ -z "$__a" ] || ! _dossier_path_in_run_tmpdir "$__a" "$__dir"; then
          _dossier_fixture_violation "git $1 refused: outside the fixture area"
          return 1
        fi
        shift ;;
      --git-dir|--work-tree)
        if [ -z "${2:-}" ] || ! _dossier_path_in_run_tmpdir "$2" "$__dir"; then
          _dossier_fixture_violation "git $1 '${2:-}' refused: outside the fixture area"
          return 1
        fi
        shift 2 ;;
      -c) shift; [ "$#" -gt 0 ] && shift ;;
      -*) shift ;;
      *) __sub="$1"; shift; break ;;
    esac
  done
  case "$__sub" in
    init|clone)
      # The last positional argument is the directory being created; options
      # that take a separate value are skipped with it.
      local __target="" __pos=0
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -b|--branch|-o|--origin|-c|--config|--depth|--reference|--reference-if-able|-u|--upload-pack|--template|--separate-git-dir|-j|--jobs|--filter|--object-format|--ref-format|--initial-branch|--shallow-since|--shallow-exclude|--server-option|--bundle-uri)
            shift; [ "$#" -gt 0 ] && shift; continue ;;
          --separate-git-dir=*)
            if ! _dossier_path_in_run_tmpdir "${1#*=}" "$__dir"; then
              _dossier_fixture_violation "git $__sub $1 refused: outside the fixture area"
              return 1
            fi
            shift; continue ;;
          --) shift; continue ;;
          -*) shift; continue ;;
        esac
        __pos=$((__pos + 1))
        __target="$1"
        shift
      done
      # With no target directory, init/clone create in the working directory.
      if [ "$__sub" = "clone" ] && [ "$__pos" -lt 2 ]; then
        __target="."
      fi
      [ -n "$__target" ] || __target="."
      if ! _dossier_path_in_run_tmpdir "$__target" "$__dir"; then
        _dossier_fixture_violation "git $__sub refused: it would create '$__target' in $__dir, outside this run's temp directory"
        return 1
      fi
      return 0 ;;
  esac
  if ! _dossier_path_in_run_tmpdir "$__dir"; then
    _dossier_fixture_violation "git ${__sub:-} refused in $__dir: outside this run's temp directory"
    return 1
  fi
  __gd=$(command git -C "$__dir" rev-parse --absolute-git-dir 2>/dev/null) || __gd=""
  if [ -n "$__gd" ] && ! _dossier_path_in_run_tmpdir "$__gd"; then
    __what="${__sub:-git}"
    _dossier_fixture_violation "git $__what refused in $__dir: it would act on $__gd, outside this run's temp directory"
    return 1
  fi
  return 0
}

# Because `git` is a function here, `command -v git` prints the word "git",
# not a path. A stub that records `REAL_GIT=$(command -v git)` and later runs
# `exec "$REAL_GIT"` would find itself first on PATH and loop forever; resolve
# the binary with `type -P git` instead (fixture-isolation.test.sh checks).
git() {
  _dossier_git_guard "$@" || return 128
  command git "$@"
}

# Turns every recorded refusal into a FAIL line. Called by
# _dossier_test_summary, so it runs once per test file whatever the file did.
_dossier_fixture_drain_violations() {
  local __f __line
  [ -n "${RUN_TMPDIR:-}" ] || return 0
  __f="$RUN_TMPDIR/.dossier-fixture-violations"
  [ -s "$__f" ] || return 0
  while IFS= read -r __line || [ -n "$__line" ]; do
    [ -n "$__line" ] || continue
    DOSSIER_TEST_FAIL=$((DOSSIER_TEST_FAIL + 1))
    printf 'FAIL %s — fixture isolation: %s [fixture guard]\n' "$DOSSIER_TEST_CURRENT" "$__line"
  done < "$__f"
  : > "$__f"
}

_dossier_assert_pass() {
  DOSSIER_TEST_PASS=$((DOSSIER_TEST_PASS + 1))
  printf 'PASS %s — %s\n' "$DOSSIER_TEST_CURRENT" "$1"
}

_dossier_assert_fail() {
  DOSSIER_TEST_FAIL=$((DOSSIER_TEST_FAIL + 1))
  # Depth-aware citation. Two call shapes exist:
  #   (a) assert_equal/match/contains/... wraps _dossier_assert_fail
  #       → BASH_SOURCE[2] is the test file (one wrapper between us and caller)
  #   (b) test body calls _dossier_assert_fail directly (used by the static
  #       lints in command-frontmatter.test.sh)
  #       → BASH_SOURCE[1] is the test file (no wrapper)
  # Picking the wrong depth produces citations like [run.sh:80] — the line
  # in run.sh that sourced the test, not the assertion line. Detect by
  # checking whether [1] is assert.sh.
  local where
  if [ "${BASH_SOURCE[1]##*/}" = "assert.sh" ]; then
    where="${BASH_SOURCE[2]##*/}:${BASH_LINENO[1]}"
  else
    where="${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}"
  fi
  printf 'FAIL %s — %s [%s]\n' "$DOSSIER_TEST_CURRENT" "$1" "$where"
}

# assert_equal <expected> <actual> [<label>]
assert_equal() {
  local expected="$1" actual="$2" label="${3:-equal}"
  if [ "$expected" = "$actual" ]; then
    _dossier_assert_pass "$label"
    return 0
  fi
  _dossier_assert_fail "$label: expected '$expected', got '$actual'"
  return 1
}

# assert_match <regex> <actual> [<label>]
# Uses grep -E so the regex is ERE — same flavor the test bodies already use.
# A here-string (not `printf ... | grep`) feeds the haystack: with a pipe,
# `grep -q` exits at the first match and closes the pipe, so printf is killed by
# SIGPIPE (141) and — under the runner's `set -o pipefail` — the pipeline
# reports non-zero even though the match succeeded. That produced nondeterministic
# false failures on large haystacks (the match position races the pipe buffer).
# A here-string has no pipeline, so pipefail/SIGPIPE cannot corrupt the result.
assert_match() {
  local pattern="$1" actual="$2" label="${3:-match}"
  if grep -qE "$pattern" <<<"$actual"; then
    _dossier_assert_pass "$label"
    return 0
  fi
  _dossier_assert_fail "$label: '$actual' does not match /$pattern/"
  return 1
}

# assert_contains <needle> <haystack> [<label>]
# Literal substring match (no regex). Useful for asserting on multi-line
# stderr where a regex special would need escaping.
assert_contains() {
  local needle="$1" haystack="$2" label="${3:-contains}"
  case "$haystack" in
    *"$needle"*)
      _dossier_assert_pass "$label"
      return 0
      ;;
  esac
  _dossier_assert_fail "$label: missing '$needle'"
  return 1
}

# assert_not_contains <needle> <haystack> [<label>]
assert_not_contains() {
  local needle="$1" haystack="$2" label="${3:-not-contains}"
  case "$haystack" in
    *"$needle"*)
      _dossier_assert_fail "$label: unexpectedly contains '$needle'"
      return 1
      ;;
  esac
  _dossier_assert_pass "$label"
  return 0
}

# assert_exit <expected> <actual> [<label>]
assert_exit() {
  local expected="$1" actual="$2" label="${3:-exit}"
  if [ "$expected" = "$actual" ]; then
    _dossier_assert_pass "$label"
    return 0
  fi
  _dossier_assert_fail "$label: expected exit $expected, got $actual"
  return 1
}

# assert_file_exists <path> [<label>]
assert_file_exists() {
  local path="$1" label="${2:-file-exists}"
  if [ -f "$path" ]; then
    _dossier_assert_pass "$label"
    return 0
  fi
  _dossier_assert_fail "$label: $path missing"
  return 1
}

# Print summary; called by run.sh after each test file completes. Fixture
# refusals recorded anywhere in the file (including subshells whose output
# went to /dev/null) are counted as failures first.
_dossier_test_summary() {
  _dossier_fixture_drain_violations
  printf 'SUMMARY pass=%d fail=%d\n' "$DOSSIER_TEST_PASS" "$DOSSIER_TEST_FAIL"
}
