#!/usr/bin/env bash
# fixture-isolation.test.sh — issue #252: running the dossier suites from a
# linked worktree of some repository must leave that repository exactly as it
# was: same configuration, remotes, branches, HEADs and working tree, and
# nothing pushed to its remotes.
#
# On 2026-09-24 rotation-check.test.sh, run from a worktree of this
# repository, switched that worktree to a new docs/dossier branch, wrote
# user.name/user.email and two fake origin URLs into the shared config, and
# pushed docs/dossier to the real origin five times. The suite had been run
# without the shared library, so no fixture variable was ever assigned, and
# every `( cd "$Fn" || exit 1; git ... )` step ran `cd ""` — a successful
# no-op — and then acted on the caller's repository.
#
# This file builds throwaway "caller" repositories (a bare origin that logs
# and refuses every push, a main clone carrying a copy of this plugin, and a
# linked worktree), runs the dossier suites from the worktree, and compares a
# snapshot of the caller taken before and after:
#   A. every suite through run.sh                                   (AC1)
#   B. the same, with review-session git settings in the environment  (AC2)
#   C. the git-fixture suites through run.sh with every `git init` and
#      `git clone` failing, and the nested temp directory inside the
#      caller's worktree, so a broken fixture sits inside the caller     (AC3)
#   D. each git-fixture suite invoked directly, without run.sh — the
#      2026-09-24 incident                                              (AC3)
# plus direct checks of the fixture guard itself (AC3): empty, missing,
# foreign and unbuilt fixtures, and every kind of outside destination a git
# command can name (a push or fetch target, a remote's URL, a clone source, a
# worktree, a separate git directory); a probe run through run.sh that pins
# the discovery ceiling for scripts under test; and static checks that every
# suite carries the one-line preamble that refuses a direct run.
#
# Cost: A and B each run the whole suite once more. They run in parallel, so
# this file takes about as long as one full run. They are killed and reported
# as failures if A, B and C together take longer than
# DOSSIER_FIXTURE_ISOLATION_TIMEOUT seconds (default 1200).
# DOSSIER_FIXTURE_ISOLATION_SUITES (space-separated file names) narrows A and
# B for local iteration only.

# Refuse to run without the shared library: its fixture guard is what keeps
# this file's git commands inside its own fixtures (issue #252).
declare -F _dossier_in_fixture >/dev/null 2>&1 || { echo "FATAL: ${BASH_SOURCE[0]##*/} must be run through plugins/dossier/tests/run.sh, which loads the fixture guard" >&2; exit 2; }

_dossier_test_begin "fixture-isolation"

# The nested runs below carry a copy of this file; it must not recurse.
if [ -n "${DOSSIER_FIXTURE_ISOLATION_NESTED:-}" ]; then
  _dossier_assert_pass "nested run: the isolation suite does not run itself again"
  return 0 2>/dev/null || exit 0
fi

ISO_REPO_ROOT=$(pwd -P)
ISO_TESTS_DIR="$ISO_REPO_ROOT/plugins/dossier/tests"
ISO_SELF="fixture-isolation.test.sh"
# SHA-1 of the empty tree; the caller repositories below are SHA-1.
ISO_EMPTY_TREE=4b825dc642cb6eb9a060e54bf8d69288fbee4904

# The preamble every suite must start with (first line that is not blank or a
# comment). Without the shared library loaded, a suite's fixture variables are
# never assigned; this line stops it before any fixture step runs.
ISO_PREAMBLE='declare -F _dossier_in_fixture >/dev/null 2>&1 || { echo "FATAL: ${BASH_SOURCE[0]##*/} must be run through plugins/dossier/tests/run.sh, which loads the fixture guard" >&2; exit 2; }'

# Suites that build git fixtures, chosen at run time so a new one is covered
# without editing this file.
ISO_GIT_SUITES=""
for _iso_f in "$ISO_TESTS_DIR"/*.test.sh; do
  _iso_b=${_iso_f##*/}
  [ "$_iso_b" = "$ISO_SELF" ] && continue
  if grep -qE 'git( -C [^ ]+)? (init|clone)([[:space:]]|$)' "$_iso_f"; then
    ISO_GIT_SUITES="$ISO_GIT_SUITES $_iso_b"
  fi
done

ISO_ALL_SUITES=""
if [ -n "${DOSSIER_FIXTURE_ISOLATION_SUITES:-}" ]; then
  ISO_ALL_SUITES="$DOSSIER_FIXTURE_ISOLATION_SUITES"
else
  for _iso_f in "$ISO_TESTS_DIR"/*.test.sh; do
    _iso_b=${_iso_f##*/}
    [ "$_iso_b" = "$ISO_SELF" ] && continue
    ISO_ALL_SUITES="$ISO_ALL_SUITES $_iso_b"
  done
fi

# iso_make_caller <outvar> <label> — a caller repository: origin.git (bare,
# logs then refuses every push), main (a clone carrying this plugin), and wt
# (a linked worktree of main on branch "review").
iso_make_caller() {
  local __outvar="$1" __label="$2" __root
  _dossier_require_mktemp_dir __root "isolation-caller-$__label"
  git init -q --bare "$__root/origin.git"
  git init -q "$__root/main"
  git -C "$__root/main" symbolic-ref HEAD refs/heads/main
  # The plugin plus the repository-root files its suites read (the marketplace
  # manifest, the licence, the project's dossier settings, and this
  # repository's own documentation package). A suite that starts reading
  # another root file fails in A and B, which names it.
  mkdir -p "$__root/main/plugins" "$__root/main/docs" "$__root/main/.claude"
  cp -R "$ISO_REPO_ROOT/plugins/dossier" "$__root/main/plugins/dossier"
  cp -R "$ISO_REPO_ROOT/.claude-plugin" "$__root/main/.claude-plugin"
  cp -R "$ISO_REPO_ROOT/docs/dossier" "$__root/main/docs/dossier"
  cp "$ISO_REPO_ROOT/LICENSE" "$__root/main/LICENSE"
  cp "$ISO_REPO_ROOT/.claude/settings.dossier.json" "$__root/main/.claude/settings.dossier.json"
  git -C "$__root/main" config user.email caller@example.invalid
  git -C "$__root/main" config user.name "Caller"
  git -C "$__root/main" add -A
  git -C "$__root/main" commit -q -m "caller"
  git -C "$__root/main" remote add origin "$__root/origin.git"
  git -C "$__root/main" push -q origin main 2>/dev/null
  git -C "$__root/main" worktree add -q -b review "$__root/wt" main 2>/dev/null
  printf '/.nested-tmp/\n' >> "$__root/main/.git/info/exclude"
  cat > "$__root/origin.git/hooks/pre-receive" <<HOOK
#!/bin/sh
while read old new ref; do echo "push \$ref \$new" >> "$__root/push-attempts.log"; done
exit 1
HOOK
  chmod +x "$__root/origin.git/hooks/pre-receive"
  _dossier_assign_outvar "$__outvar" "$__root"
}

# iso_git_files <git-dir> — every file inside a git directory except the
# object store, index files and lock files, with a checksum, so a write to a
# hook, info/, logs/ or any other file there shows up.
iso_git_files() {
  ( builtin cd "$1" 2>/dev/null || exit 0
    find . -type f ! -path './objects/*' ! -name index ! -name '*.lock' | LC_ALL=C sort \
      | while IFS= read -r _iso_gf; do cksum "$_iso_gf"; done )
}

# iso_snapshot <caller-root> — everything the issue says must not change.
iso_snapshot() {
  local r="$1"
  echo "## config (shared)"
  git -C "$r/main" config --local --list | sort
  echo "## refs"
  git -C "$r/main" for-each-ref --format='%(refname) %(objectname)'
  echo "## worktrees"
  git -C "$r/main" worktree list --porcelain
  echo "## main HEAD"
  git -C "$r/main" symbolic-ref -q HEAD
  git -C "$r/main" rev-parse HEAD
  echo "## main status"
  git -C "$r/main" status --porcelain --untracked-files=all --ignored
  echo "## wt HEAD"
  git -C "$r/wt" symbolic-ref -q HEAD
  git -C "$r/wt" rev-parse HEAD
  echo "## wt status"
  git -C "$r/wt" status --porcelain --untracked-files=all --ignored
  echo "## origin refs"
  git -C "$r/origin.git" for-each-ref --format='%(refname) %(objectname)'
  echo "## push attempts"
  cat "$r/push-attempts.log" 2>/dev/null
  echo "## files in main/.git"
  iso_git_files "$r/main/.git"
  echo "## files in origin.git"
  iso_git_files "$r/origin.git"
}

# iso_assert_unchanged <caller-root> <before-file> <label>
iso_assert_unchanged() {
  local r="$1" before="$2" label="$3" delta
  iso_snapshot "$r" > "$r/snapshot.after" 2>&1
  delta=$(diff "$before" "$r/snapshot.after")
  assert_equal "" "$delta" "$label: the caller's config, remotes, branches, HEADs, working tree and origin are unchanged, and nothing was pushed"
}

# iso_kill_tree <pid> — stops <pid>, kills its descendants, then kills it.
# A nested run is a subshell running run.sh running a suite running scripts;
# job control is off here, so there is no process group to signal, and
# killing only the subshell would leave the rest running. Stopping first keeps
# a looping parent from starting new children while its tree is walked.
iso_kill_tree() {
  local __p="$1" __k
  kill -STOP "$__p" 2>/dev/null
  for __k in $(ps -A -o pid= -o ppid= 2>/dev/null | awk -v p="$__p" '$2 == p { print $1 }'); do
    iso_kill_tree "$__k"
  done
  kill -KILL "$__p" 2>/dev/null
}

# iso_await <deadline-epoch> <pid> — waits for a background run until the
# deadline. Returns 0 when it ended on its own; otherwise kills its whole tree
# and returns 1. A nested run that hangs (a stub that execs itself, a script
# waiting on input) must fail this file with a named cause, not run into the
# CI job's timeout with nothing printed after the file's header.
iso_await() {
  local __deadline="$1" __p="$2"
  while kill -0 "$__p" 2>/dev/null; do
    if [ "$(date +%s)" -ge "$__deadline" ]; then
      iso_kill_tree "$__p"
      wait "$__p" 2>/dev/null
      return 1
    fi
    sleep 2
  done
  wait "$__p" 2>/dev/null
  return 0
}

# Seconds A, B and C together may take. A and B each run the whole suite, in
# parallel; the CI job allows 30 minutes for this file plus every other suite.
ISO_DEADLINE_SECS=${DOSSIER_FIXTURE_ISOLATION_TIMEOUT:-1200}

# =============================================================================
# Static: every suite starts with the preamble that refuses a direct run.
# =============================================================================
ISO_STATIC_OK=1
ISO_MISSING_PREAMBLE=""
for _iso_f in "$ISO_TESTS_DIR"/*.test.sh; do
  _iso_first=$(awk '/^[[:space:]]*(#|$)/{next} {print; exit}' "$_iso_f")
  if [ "$_iso_first" != "$ISO_PREAMBLE" ]; then
    ISO_MISSING_PREAMBLE="$ISO_MISSING_PREAMBLE ${_iso_f##*/}"
  fi
done
assert_equal "" "$ISO_MISSING_PREAMBLE" "every suite's first command is the preamble that refuses to run without the shared library" || ISO_STATIC_OK=0

# `git` is a shell function in the suites, so `command -v git` names the
# function, not the binary; a stub that execs it re-runs itself forever.
ISO_GIT_LOOKUPS=$(grep -nE '(command -v|which) git([^A-Za-z0-9_-]|$)' "$ISO_TESTS_DIR"/*.test.sh \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -v "ISO_GIT_LOOKUPS")
assert_equal "" "$ISO_GIT_LOOKUPS" "no suite resolves the git binary with 'command -v git' (it names the guard function); use 'type -P git'" || ISO_STATIC_OK=0

# A fixture that could not be built must be marked with
# _dossier_fixture_unbuilt, not emptied: an empty variable turns a later
# `mkdir -p "$WORK/src"` into `mkdir -p /src`.
ISO_EMPTIED=$(grep -nE '_dossier_fixture_ready .*\|\|[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' "$ISO_TESTS_DIR"/*.test.sh \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -v "ISO_EMPTIED")
assert_equal "" "$ISO_EMPTIED" "no suite empties a fixture variable when its fixture could not be built; each uses _dossier_fixture_unbuilt"

# =============================================================================
# Build the callers.
# =============================================================================
iso_make_caller ISO_A "a"
iso_make_caller ISO_B "b"
iso_make_caller ISO_C "c"
iso_make_caller ISO_D "d"
iso_make_caller ISO_U "u"
# Temp directories inside a caller's worktree (git-excluded) exist before the
# snapshot, so the snapshot compares only what the runs leave behind.
mkdir -p "$ISO_C/wt/.nested-tmp" "$ISO_D/wt/.nested-tmp" "$ISO_U/wt/.nested-tmp"
for _iso_r in "$ISO_A" "$ISO_B" "$ISO_C" "$ISO_D" "$ISO_U"; do
  iso_snapshot "$_iso_r" > "$_iso_r/snapshot.before" 2>&1
done

ISO_COMMON_A=$(git -C "$ISO_A/wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
ISO_COMMON_A=$( builtin cd "${ISO_COMMON_A:-/nonexistent}" 2>/dev/null && pwd -P )
ISO_MAIN_GIT_A=$( builtin cd "$ISO_A/main/.git" 2>/dev/null && pwd -P )
if [ -f "$ISO_A/wt/.git" ] && [ -n "$ISO_COMMON_A" ] && [ "$ISO_COMMON_A" = "$ISO_MAIN_GIT_A" ]; then
  _dossier_assert_pass "fixture setup: the caller's wt is a linked worktree of main"
else
  _dossier_assert_fail "fixture setup: the caller's wt is not a linked worktree of main (common dir '$ISO_COMMON_A')"
fi

# =============================================================================
# A, B and C run in the background, only when the static checks passed: a
# suite that resolves git with `command -v git` makes its stub exec itself
# forever, and the nested runs would hang instead of failing.
# =============================================================================
if [ "$ISO_STATIC_OK" = 1 ]; then
  _dossier_require_mktemp_dir ISO_TMP_A "isolation-nested-tmp-a"
  _dossier_require_mktemp_dir ISO_TMP_B "isolation-nested-tmp-b"

  # A stand-in git for scenario C that fails every `git init` and `git clone`
  # (so no fixture repository can be created) and passes everything else on.
  _dossier_require_mktemp_dir ISO_STUB "isolation-git-stub"
  ISO_REAL_GIT=$(type -P git)
  cat > "$ISO_STUB/git" <<STUB
#!/usr/bin/env bash
sub=""
skip=0
for a in "\$@"; do
  if [ "\$skip" = 1 ]; then skip=0; continue; fi
  case "\$a" in
    -C|-c) skip=1 ;;
    -*) ;;
    *) sub="\$a"; break ;;
  esac
done
case "\$sub" in
  init|clone) echo "git \$sub: refused by the fixture-isolation fault stub" >&2; exit 1 ;;
esac
exec "$ISO_REAL_GIT" "\$@"
STUB
  chmod +x "$ISO_STUB/git"

  ISO_DEADLINE=$(( $(date +%s) + ISO_DEADLINE_SECS ))
  # shellcheck disable=SC2086 # the suite lists are deliberately word-split
  ( builtin cd "$ISO_A/wt" && env DOSSIER_FIXTURE_ISOLATION_NESTED=1 TMPDIR="$ISO_TMP_A" \
      bash plugins/dossier/tests/run.sh $ISO_ALL_SUITES > "$ISO_A/nested.log" 2>&1
    echo "$?" > "$ISO_A/nested.rc" ) &
  ISO_PID_A=$!
  # shellcheck disable=SC2086
  ( builtin cd "$ISO_B/wt" && env DOSSIER_FIXTURE_ISOLATION_NESTED=1 TMPDIR="$ISO_TMP_B" \
      GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=explicit \
      GIT_ATTR_SOURCE="$ISO_EMPTY_TREE" \
      bash plugins/dossier/tests/run.sh $ISO_ALL_SUITES > "$ISO_B/nested.log" 2>&1
    echo "$?" > "$ISO_B/nested.rc" ) &
  ISO_PID_B=$!
  # shellcheck disable=SC2086
  ( builtin cd "$ISO_C/wt" && env DOSSIER_FIXTURE_ISOLATION_NESTED=1 TMPDIR="$ISO_C/wt/.nested-tmp" \
      PATH="$ISO_STUB:$PATH" \
      bash plugins/dossier/tests/run.sh $ISO_GIT_SUITES > "$ISO_C/nested.log" 2>&1
    echo "$?" > "$ISO_C/nested.rc" ) &
  ISO_PID_C=$!
else
  _dossier_assert_fail "A, B and C were not run: a static check above failed, and the nested runs cannot be trusted to finish"
fi

# =============================================================================
# D. Each git-fixture suite run directly, from the worktree, without run.sh.
# =============================================================================
for _iso_s in $ISO_GIT_SUITES; do
  _iso_out=$(builtin cd "$ISO_D/wt" && env -u RUN_TMPDIR DOSSIER_FIXTURE_ISOLATION_NESTED=1 \
      TMPDIR="$ISO_D/wt/.nested-tmp" bash "plugins/dossier/tests/$_iso_s" 2>&1)
  _iso_rc=$?
  assert_equal "2" "$_iso_rc" "direct run of $_iso_s: refuses with exit 2"
  assert_contains "must be run through plugins/dossier/tests/run.sh" "$_iso_out" "direct run of $_iso_s: says how to run it"
done
iso_assert_unchanged "$ISO_D" "$ISO_D/snapshot.before" "direct runs of the git-fixture suites from a linked worktree"

# =============================================================================
# The guard itself: empty, missing, foreign and half-built fixtures are
# refused with a message naming the fixture, and no git command reaches the
# caller. Runs in a child bash with its own RUN_TMPDIR, from the caller's
# worktree, so the caller is outside that RUN_TMPDIR exactly as the real
# repository is outside a real run's.
# =============================================================================
_dossier_require_mktemp_dir ISO_UNIT_TMP "isolation-unit-run"
ISO_LIB="$ISO_TESTS_DIR/lib/assert.sh"
ISO_UNIT_OUT=$(builtin cd "$ISO_U/wt" && RUN_TMPDIR="$ISO_UNIT_TMP" bash -c '
  set -uo pipefail
  source "$1"
  _dossier_test_begin unit
  F_EMPTY=""
  F_GONE="$RUN_TMPDIR/never-created"
  F_FOREIGN=$(pwd -P)
  mkdir -p "$RUN_TMPDIR/plain"
  ( _dossier_in_fixture F_EMPTY || exit 1; git config user.name EscapedEmpty; git commit -q --allow-empty -m escaped ) >/dev/null 2>&1
  ( _dossier_in_fixture F_GONE || exit 1; git config user.name EscapedGone ) >/dev/null 2>&1
  ( _dossier_in_fixture F_FOREIGN || exit 1; git config user.name EscapedForeign ) >/dev/null 2>&1
  ( cd "$F_EMPTY" || exit 1; git config user.name EscapedRawCd ) >/dev/null 2>&1
  ( cd "$F_GONE" && git config user.name EscapedAndAnd; git config user.name EscapedAfterSemicolon ) >/dev/null 2>&1
  git -C "$F_EMPTY" config user.name EscapedDashC >/dev/null 2>&1
  git config user.name EscapedBare >/dev/null 2>&1
  git -C "$F_FOREIGN" push -q origin HEAD:refs/heads/escaped >/dev/null 2>&1
  git -C "$RUN_TMPDIR/plain" config user.name EscapedByDiscovery >/dev/null 2>&1
  _dossier_fixture_ready F_PLAIN "$RUN_TMPDIR/plain" 2>/dev/null
  echo "READY_RC=$?"
  # A fixture that could not be built: plain writes through its variable fail
  # instead of landing at the root of the file system.
  _dossier_fixture_unbuilt F_BROKEN
  mkdir -p "$F_BROKEN/src" 2>/dev/null
  echo "UNBUILT_MKDIR_RC=$?"
  printf "x\n" 2>/dev/null > "$F_BROKEN/app.ts"
  echo "UNBUILT_WRITE_RC=$?"
  ( _dossier_in_fixture F_BROKEN || exit 1; git config user.name EscapedUnbuilt ) >/dev/null 2>&1
  _dossier_test_summary
' _ "$ISO_LIB" 2>&1)
assert_contains "fixture F_EMPTY is empty" "$ISO_UNIT_OUT" "an empty fixture variable is refused with a message naming it"
assert_contains "fixture F_GONE does not exist" "$ISO_UNIT_OUT" "a fixture path that does not exist is refused with a message naming it"
assert_contains "fixture F_FOREIGN is outside this run's temp directory" "$ISO_UNIT_OUT" "a fixture path outside the run's temp directory is refused with a message naming it"
assert_contains "fixture F_PLAIN could not be created" "$ISO_UNIT_OUT" "a fixture directory that is not a repository of its own is reported as not created, by name"
assert_contains "READY_RC=1" "$ISO_UNIT_OUT" "_dossier_fixture_ready returns non-zero for a half-built fixture"
assert_contains "cd was given an empty path" "$ISO_UNIT_OUT" "a raw cd to an empty path is refused rather than staying in the caller's directory"
assert_contains "git -C was given an empty path" "$ISO_UNIT_OUT" "git -C with an empty path is refused rather than acting on the caller's directory"
assert_match "FAIL unit — fixture isolation: fixture F_EMPTY is empty" "$ISO_UNIT_OUT" "refusals inside redirected subshells still surface as FAIL lines in the test summary"
assert_not_contains "SUMMARY pass=0 fail=0" "$ISO_UNIT_OUT" "the refusals make the test fail rather than pass silently"
assert_not_contains "UNBUILT_MKDIR_RC=0" "$ISO_UNIT_OUT" "mkdir -p through an unbuilt fixture's variable fails"
assert_not_contains "UNBUILT_WRITE_RC=0" "$ISO_UNIT_OUT" "a file write through an unbuilt fixture's variable fails"
assert_contains "fixture F_BROKEN was not created" "$ISO_UNIT_OUT" "a step naming an unbuilt fixture is refused with a message naming it"
if [ -e "$ISO_UNIT_TMP/.dossier-unbuilt-fixture/F_BROKEN" ]; then
  _dossier_assert_fail "an unbuilt fixture's path was created"
else
  _dossier_assert_pass "an unbuilt fixture's path was not created"
fi

# -----------------------------------------------------------------------------
# Where git sends data or creates files. From a real fixture inside the child
# RUN_TMPDIR, every command below would reach outside it: to victim.git (a
# bare repository beside the caller), or to a new path next to it. Most cases
# reach outside through `out`, a symbolic link inside the fixture that points
# at the caller's directory, so the operand is a plain relative word and only
# the check for that kind of operand can refuse it. Others set configuration
# that redirects git: through the environment, an alias, a URL rewrite written
# straight into the fixture's config file, or a relative core.worktree that
# git resolves against the git directory. Must-pass cases are the shapes the
# suites use, and text that only looks like a path (a commit message). Each
# case prints "CASE <name> rc=<rc> refused=<n>", where <n> counts the guard's
# own refusals, so a must-fail case cannot pass because git failed for some
# other reason.
# -----------------------------------------------------------------------------
git init -q --bare "$ISO_U/victim.git"
_dossier_require_mktemp_dir ISO_DEST_TMP "isolation-dest-run"
ISO_DEST_OUT=$(builtin cd "$ISO_U/wt" && RUN_TMPDIR="$ISO_DEST_TMP" bash -c '
  set -uo pipefail
  source "$1"
  U="$2"
  R="$RUN_TMPDIR"
  _dossier_test_begin dest
  # --global must not reach the real user configuration if the guard lets it by.
  export GIT_CONFIG_GLOBAL="$R/global-config"
  V="$R/.dossier-fixture-violations"
  : > "$V"
  c() {
    local __n="$1" __b __a __rc
    shift
    __b=$(wc -l < "$V")
    ( "$@" ) >/dev/null 2>&1
    __rc=$?
    __a=$(wc -l < "$V")
    echo "CASE $__n rc=$__rc refused=$((__a - __b))"
    # Each case starts from the same fixture: a case that got through must not
    # leave a remote pointing outside for the next case to be refused by.
    command git -C "$R/fx" remote set-url origin "$R/origin.git" 2>/dev/null
    command git -C "$R/fx" remote remove victim 2>/dev/null
    command git -C "$R/fx" config --unset-all remote.origin.pushurl 2>/dev/null
    command git -C "$R/fx" config --unset-all core.worktree 2>/dev/null
    command git -C "$R/fx" config --remove-section alias 2>/dev/null
    command git -C "$R/fx" config --remove-section "url.$U/victim.git" 2>/dev/null
  }
  command git init -q --bare "$R/origin.git"
  command git init -q "$R/fx"
  printf "tracked\n" > "$R/fx/f.txt"
  command git -C "$R/fx" add f.txt
  command git -C "$R/fx" -c user.name=t -c user.email=t@example.invalid commit -q -m f
  command git -C "$R/fx" remote add origin "$R/origin.git"
  ln -s "$U" "$R/fx/out"
  # A symbolic link to a file that does not exist yet, outside: writing
  # through it creates that file.
  ln -s "$U/escaped-dangling.tar" "$R/fx/dangling.tar"
  mkdir -p "$R/fx/a/b"
  in_fx() { builtin cd "$R/fx" && "$@"; }
  # Configuration given through the environment rather than on the command line.
  export DOSSIER_ISO_EVIL="$U/victim.git" DOSSIER_ISO_OK="$R/origin.git"
  # core.worktree is resolved by git against the git directory, not the
  # directory the config command ran in: set from $R/fx/a/b, this value names
  # $R/<caller>/wt-rel-target to a reader of the command line, and
  # $U/wt-rel-target to git. Setting it is allowed; using it is refused.
  mkdir -p "$U/wt-rel-target"
  worktree_rel() {
    git -C "$R/fx/a/b" config core.worktree "../../../${U##*/}/wt-rel-target" || return 0
    git -C "$R/fx" checkout -q -f HEAD -- f.txt
  }
  # URL rewrites and aliases already in a configuration file the guard never
  # saw being written (the realistic source is the user configuration in ~/.gitconfig).
  insteadof_file() {
    printf "[url \"%s/victim.git\"]\n\tinsteadOf = https://rw.example.invalid/\n" "$U" >> "$R/fx/.git/config"
    git -C "$R/fx" push -q https://rw.example.invalid/ HEAD:refs/heads/escaped
  }
  pushinsteadof_file() {
    printf "[url \"%s/victim.git\"]\n\tpushInsteadOf = https://rw.example.invalid/\n" "$U" >> "$R/fx/.git/config"
    git -C "$R/fx" push -q https://rw.example.invalid/ HEAD:refs/heads/escaped
  }
  alias_file() {
    printf "[alias]\n\tpp = push %s/victim.git HEAD:refs/heads/escaped\n" "$U" >> "$R/fx/.git/config"
    git -C "$R/fx" pp
  }

  c push-abs              git -C "$R/fx" push -q "$U/victim.git" HEAD:refs/heads/escaped
  c push-file-url         git -C "$R/fx" push -q "file://$U/victim.git" HEAD:refs/heads/escaped
  c push-dotdot           git -C "$R/fx" push -q ../../u-victim HEAD:refs/heads/escaped
  c push-link             git -C "$R/fx" push -q out/victim.git HEAD:refs/heads/escaped
  c fetch-link            git -C "$R/fx" fetch -q out/victim.git
  c pull-link             git -C "$R/fx" pull -q out/victim.git
  c ls-remote-link        git -C "$R/fx" ls-remote out/victim.git
  c remote-add-link       git -C "$R/fx" remote add victim out/victim.git
  c remote-set-url-link   git -C "$R/fx" remote set-url origin out/victim.git
  c config-url-link       git -C "$R/fx" config remote.origin.url out/victim.git
  c dash-c-url-link       git -C "$R/fx" -c remote.origin.url=out/victim.git push -q origin HEAD:refs/heads/escaped
  c dash-c-insteadof      git -C "$R/fx" -c "url.$U/victim.git.insteadOf=https://rewrite.example.invalid/" push -q https://rewrite.example.invalid/ HEAD:refs/heads/escaped
  command git -C "$R/fx" remote add stored "$U/victim.git"
  c stored-remote         git -C "$R/fx" push -q stored HEAD:refs/heads/escaped
  c stored-remote-other   git -C "$R/fx" push -q origin HEAD:refs/heads/escaped
  command git -C "$R/fx" remote remove stored
  c clone-source-link     in_fx git clone -q out/victim.git cl-escaped
  c worktree-abs          git -C "$R/fx" worktree add -q "$U/escaped-wt-abs"
  c worktree-link         git -C "$R/fx" worktree add -q out/escaped-wt-link
  c core-worktree         git -C "$R/fx" config core.worktree "$U/escaped-core-wt"
  c config-file           git -C "$R/fx" config -f "$U/escaped.cfg" a.b c
  c config-global         git -C "$R/fx" config --global user.name Escaped
  c init-dotdot           git init -q "$R/nx/../../escaped-dotdot"
  c init-sep-link         in_fx git init -q --separate-git-dir out/escaped-sep newrepo
  c namespace-init-link   in_fx git --namespace ns init -q out/escaped-ns
  c config-env-push       git -C "$R/fx" --config-env=remote.origin.url=DOSSIER_ISO_EVIL push -q origin HEAD:refs/heads/escaped
  c config-env-pushurl    git -C "$R/fx" --config-env remote.origin.pushurl=DOSSIER_ISO_EVIL push -q origin HEAD:refs/heads/escaped
  c config-env-bad-name   git -C "$R/fx" --config-env=user.name=not-a-name status
  c dash-c-alias-shell    git -C "$R/fx" -c "alias.pp=!git push -q $U/victim.git HEAD:refs/heads/escaped" pp
  c dash-c-alias-git      git -C "$R/fx" -c "alias.pp=push $U/victim.git HEAD:refs/heads/escaped" pp
  c config-alias          git -C "$R/fx" config alias.pp "push $U/victim.git HEAD:refs/heads/escaped"
  c alias-in-file         alias_file
  c config-file-link      git -C "$R/fx" config -f out/escaped.cfg a.b c
  c archive-link          git -C "$R/fx" archive -o out/escaped.tar HEAD
  c archive-attached-link git -C "$R/fx" archive -oout/escaped-attached.tar HEAD
  c archive-dangling-link git -C "$R/fx" archive -o dangling.tar HEAD
  c bundle-link           git -C "$R/fx" bundle create out/escaped.bundle HEAD
  c format-patch-link     git -C "$R/fx" format-patch -q -o out/escaped-patches -1 HEAD
  c checkout-index-link   git -C "$R/fx" checkout-index -a --prefix=out/escaped-prefix/
  c clone-config-eq       in_fx git clone -q "--config=remote.origin.pushurl=$U/victim.git" "$R/origin.git" cl-config
  c worktree-rel          worktree_rel
  c insteadof-file        insteadof_file
  c pushinsteadof-file    pushinsteadof_file

  c ok-push-origin        git -C "$R/fx" push -q origin HEAD:refs/heads/ok
  c ok-push-delete        git -C "$R/fx" push -q origin :refs/heads/ok
  c ok-fetch-origin       git -C "$R/fx" fetch -q origin
  c ok-set-url-https      git -C "$R/fx" remote set-url origin https://github.example.invalid/test/rotation-fixture.git
  c ok-set-url-scp        git -C "$R/fx" remote set-url origin git@github.example.invalid:test/rotation-fixture.git
  c ok-set-url-missing    git -C "$R/fx" remote set-url origin "$R/nonexistent/path/that/does/not/exist.git"
  c ok-worktree-add       git -C "$R/fx" worktree add -q -b review "$R/wt-ok"
  c ok-clone              git clone -q "$R/origin.git" "$R/cl-ok"
  c ok-init-template      git init -q --template= "$R/tpl-ok"
  c ok-config             git -C "$R/fx" config user.name T
  c ok-range              git -C "$R/fx" log --oneline HEAD..HEAD
  c ok-commit-slash-message git -C "$R/fx" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m "/usr/bin is mentioned"
  c ok-commit-am-dotdot   git -C "$R/fx" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -am "see ../../elsewhere"
  c ok-log-grep-slash     git -C "$R/fx" log --oneline --grep=/usr HEAD
  c ok-archive-inside     git -C "$R/fx" archive -o inside.tar HEAD
  c ok-config-env-inside  git -C "$R/fx" --config-env=remote.origin.url=DOSSIER_ISO_OK push -q origin HEAD:refs/heads/ok-env
  c ok-bare-repository    git -C "$R/origin.git" for-each-ref
  c ok-in-git-directory   git -C "$R/fx/.git" rev-parse --git-dir
  # git ignores an alias named like one of its own commands, so a user
  # configuration with such an alias must not make the suites fail.
  shadowed_alias() {
    command git -C "$R/fx" config alias.status "push $U/victim.git HEAD:refs/heads/escaped"
    git -C "$R/fx" status --short
  }
  c ok-shadowed-alias     shadowed_alias
  _dossier_test_summary
' _ "$ISO_LIB" "$ISO_U" 2>&1)
for _iso_case in push-abs push-file-url push-dotdot push-link fetch-link pull-link ls-remote-link \
    remote-add-link remote-set-url-link config-url-link dash-c-url-link dash-c-insteadof \
    stored-remote stored-remote-other clone-source-link worktree-abs worktree-link core-worktree \
    config-file config-global init-dotdot init-sep-link namespace-init-link \
    config-env-push config-env-pushurl config-env-bad-name dash-c-alias-shell dash-c-alias-git \
    config-alias alias-in-file config-file-link archive-link archive-attached-link \
    archive-dangling-link bundle-link format-patch-link checkout-index-link clone-config-eq \
    worktree-rel insteadof-file pushinsteadof-file; do
  if grep -qE "^CASE $_iso_case rc=[1-9][0-9]* refused=[1-9]" <<<"$ISO_DEST_OUT"; then
    _dossier_assert_pass "guard refuses $_iso_case"
  else
    _dossier_assert_fail "guard did not refuse $_iso_case ($(grep -E "^CASE $_iso_case " <<<"$ISO_DEST_OUT"))"
  fi
done
for _iso_case in ok-push-origin ok-push-delete ok-fetch-origin ok-set-url-https ok-set-url-scp \
    ok-set-url-missing ok-worktree-add ok-clone ok-init-template ok-config ok-range \
    ok-commit-slash-message ok-commit-am-dotdot ok-log-grep-slash ok-archive-inside \
    ok-config-env-inside ok-bare-repository ok-in-git-directory ok-shadowed-alias; do
  assert_contains "CASE $_iso_case rc=0 refused=0" "$ISO_DEST_OUT" "guard allows $_iso_case"
done
assert_equal "" "$(git -C "$ISO_U/victim.git" for-each-ref)" "nothing was pushed to the repository beside the caller"
# shellcheck disable=SC2012 # names only, for the message
assert_equal "" "$(ls -A "$ISO_U/wt-rel-target" 2>&1)" "nothing was checked out into a work tree that core.worktree placed outside the run's temp directory"
# shellcheck disable=SC2012 # names only, for the message
ISO_ESCAPED=$( { ls -d "$ISO_U"/escaped* "$ISO_DEST_TMP"/../escaped-dotdot; } 2>/dev/null)
assert_equal "" "$ISO_ESCAPED" "no file or directory was created outside the run's temp directory"

# -----------------------------------------------------------------------------
# The ceiling: run.sh's GIT_CEILING_DIRECTORIES is the only thing that keeps a
# script under test (a separate process the guard cannot see) from walking up
# out of a plain-directory fixture into an enclosing repository. A probe suite
# runs through the caller's own copy of run.sh with the run's temp directory
# inside the caller's worktree; a child process in a plain fixture must find
# no repository, and must not be able to write the caller's configuration.
# -----------------------------------------------------------------------------
mkdir -p "$ISO_U/probe"
cat > "$ISO_U/probe/ceiling-probe.test.sh" <<'PROBE'
declare -F _dossier_in_fixture >/dev/null 2>&1 || { echo "FATAL: must be run through run.sh" >&2; exit 2; }
_dossier_test_begin "ceiling-probe"
_dossier_require_mktemp_dir PLAIN "ceiling-plain"
PROBE_OUT=$(_dossier_in_fixture PLAIN && bash -c 'git rev-parse --git-dir 2>&1; git config user.name EscapedViaChild 2>&1')
assert_contains "not a git repository" "$PROBE_OUT" "a child process in a plain fixture finds no repository above the run's temp directory"
PROBE
ISO_CEIL_OUT=$(builtin cd "$ISO_U/wt" && env DOSSIER_FIXTURE_ISOLATION_NESTED=1 TMPDIR="$ISO_U/wt/.nested-tmp" \
    bash plugins/dossier/tests/run.sh "$ISO_U/probe/ceiling-probe.test.sh" 2>&1)
ISO_CEIL_RC=$?
assert_equal "0" "$ISO_CEIL_RC" "ceiling: the probe passes through run.sh ($(grep -E '^(FAIL|TOTAL)' <<<"$ISO_CEIL_OUT" | tr '\n' ' '))"

# -----------------------------------------------------------------------------
# Attribution: a suite that exits before its summary must not leave its
# refusals to be reported as the next suite's failures. The first probe makes
# a refused git call in the caller's directory and exits; the second is clean.
# -----------------------------------------------------------------------------
cat > "$ISO_U/probe/attr-first.test.sh" <<'PROBE'
declare -F _dossier_in_fixture >/dev/null 2>&1 || { echo "FATAL: must be run through run.sh" >&2; exit 2; }
_dossier_test_begin "attr-first"
git config user.name EscapedFromAttrFirst >/dev/null 2>&1
exit 3
PROBE
cat > "$ISO_U/probe/attr-second.test.sh" <<'PROBE'
declare -F _dossier_in_fixture >/dev/null 2>&1 || { echo "FATAL: must be run through run.sh" >&2; exit 2; }
_dossier_test_begin "attr-second"
_dossier_assert_pass "the second probe ran"
PROBE
ISO_ATTR_OUT=$(builtin cd "$ISO_U/wt" && env DOSSIER_FIXTURE_ISOLATION_NESTED=1 TMPDIR="$ISO_U/wt/.nested-tmp" \
    bash plugins/dossier/tests/run.sh "$ISO_U/probe/attr-first.test.sh" "$ISO_U/probe/attr-second.test.sh" 2>&1)
ISO_ATTR_SECOND=$(awk '/^=== attr-second.test.sh ===/{s=1} s' <<<"$ISO_ATTR_OUT")
assert_contains "SUMMARY pass=1 fail=0" "$ISO_ATTR_SECOND" "attribution: a clean suite after one that exited early reports no failures of its own"
assert_not_contains "FAIL attr-second" "$ISO_ATTR_OUT" "attribution: the early-exiting suite's refusals are not reported under the next suite's name"
assert_contains "attr-first.test.sh: git config refused" "$ISO_ATTR_OUT" "attribution: the early-exiting suite's refusals are reported under its own name"
assert_contains "no SUMMARY line from attr-first.test.sh" "$ISO_ATTR_OUT" "attribution: the early-exiting suite still fails the run"
iso_assert_unchanged "$ISO_U" "$ISO_U/snapshot.before" "guard checks and the ceiling probe run from a linked worktree"

# -----------------------------------------------------------------------------
# The watchdog: a background run that does not end by the deadline is killed
# with everything it started.
# -----------------------------------------------------------------------------
_dossier_require_mktemp_dir ISO_WD "isolation-watchdog"
# The trailing `true` keeps the subshell from exec-ing bash in its place, so
# the sleep really is a grandchild of the job the watchdog is given.
( bash -c 'echo $$ > "$1/grandchild.pid"; exec sleep 300' _ "$ISO_WD"; true ) &
ISO_WD_PID=$!
ISO_WD_START=$(date +%s)
if iso_await $(( ISO_WD_START + 3 )) "$ISO_WD_PID"; then
  _dossier_assert_fail "watchdog: a run past its deadline was reported as finished"
else
  _dossier_assert_pass "watchdog: a run past its deadline is reported as timed out"
fi
ISO_WD_GRANDCHILD=$(cat "$ISO_WD/grandchild.pid" 2>/dev/null)
# A killed child can linger briefly as a zombie until it is reaped; that is
# not a running process.
iso_running() {
  kill -0 "$1" 2>/dev/null || return 1
  case "$(ps -o stat= -p "$1" 2>/dev/null)" in
    *Z*) return 1 ;;
  esac
  return 0
}
_iso_try=0
while [ -n "$ISO_WD_GRANDCHILD" ] && iso_running "$ISO_WD_GRANDCHILD" && [ "$_iso_try" -lt 10 ]; do
  sleep 1
  _iso_try=$((_iso_try + 1))
done
if [ -n "$ISO_WD_GRANDCHILD" ] && ! iso_running "$ISO_WD_GRANDCHILD"; then
  _dossier_assert_pass "watchdog: the timed-out run's child processes were killed too"
else
  _dossier_assert_fail "watchdog: the timed-out run's child process '${ISO_WD_GRANDCHILD}' is still running"
  [ -n "$ISO_WD_GRANDCHILD" ] && kill -KILL "$ISO_WD_GRANDCHILD" 2>/dev/null
fi

# =============================================================================
# Collect A, B and C.
# =============================================================================
if [ "$ISO_STATIC_OK" = 1 ]; then
  # iso_collect <label> <pid> <caller-root>
  iso_collect() {
    if ! iso_await "$ISO_DEADLINE" "$2"; then
      _dossier_assert_fail "$1. did not finish within ${ISO_DEADLINE_SECS}s and was killed; last lines of its log: $(tail -5 "$3/nested.log" 2>/dev/null | tr '\n' ' ')"
    fi
  }
  iso_collect A "$ISO_PID_A" "$ISO_A"
  iso_collect B "$ISO_PID_B" "$ISO_B"
  iso_collect C "$ISO_PID_C" "$ISO_C"

  ISO_RC_A=$(cat "$ISO_A/nested.rc" 2>/dev/null)
  ISO_RC_B=$(cat "$ISO_B/nested.rc" 2>/dev/null)
  ISO_RC_C=$(cat "$ISO_C/nested.rc" 2>/dev/null)

  iso_assert_unchanged "$ISO_A" "$ISO_A/snapshot.before" "A. every suite through run.sh from a linked worktree"
  assert_equal "0" "$ISO_RC_A" "A. every suite passes when run from a linked worktree ($(grep -E '^(TOTAL|FAILED)' "$ISO_A/nested.log" | tr '\n' ' '))"

  iso_assert_unchanged "$ISO_B" "$ISO_B/snapshot.before" "B. every suite with safe.bareRepository=explicit and an empty-tree GIT_ATTR_SOURCE"
  assert_equal "0" "$ISO_RC_B" "B. every suite passes under review-session git settings ($(grep -E '^(TOTAL|FAILED)' "$ISO_B/nested.log" | tr '\n' ' '))"

  iso_assert_unchanged "$ISO_C" "$ISO_C/snapshot.before" "C. git-fixture suites with every fixture build failing, temp directory inside the caller"
  if [ -n "$ISO_RC_C" ] && [ "$ISO_RC_C" != "0" ]; then
    _dossier_assert_pass "C. a run whose fixtures cannot be created fails (exit $ISO_RC_C)"
  else
    _dossier_assert_fail "C. a run whose fixtures cannot be created did not fail (exit '$ISO_RC_C')"
  fi
  ISO_LOG_C=$(cat "$ISO_C/nested.log" 2>/dev/null)
  assert_contains "fixture F1 could not be created" "$ISO_LOG_C" "C. rotation-check names the fixture it could not create (F1)"
  assert_match "FAIL [a-z-]+ — fixture isolation: " "$ISO_LOG_C" "C. the refusals are reported as test failures"
fi
