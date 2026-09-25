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
# plus direct checks of the fixture guard itself (AC3), and a static check
# that every suite carries the one-line preamble that refuses a direct run.
#
# Cost: A and B each run the whole suite once more. They run in parallel, so
# this file takes about as long as one full run. DOSSIER_FIXTURE_ISOLATION_SUITES
# (space-separated file names) narrows A and B for local iteration only.

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
  git -C "$r/main" status --porcelain --untracked-files=all
  echo "## wt HEAD"
  git -C "$r/wt" symbolic-ref -q HEAD
  git -C "$r/wt" rev-parse HEAD
  echo "## wt status"
  git -C "$r/wt" status --porcelain --untracked-files=all
  echo "## origin refs"
  git -C "$r/origin.git" for-each-ref --format='%(refname) %(objectname)'
  echo "## push attempts"
  cat "$r/push-attempts.log" 2>/dev/null
}

# iso_assert_unchanged <caller-root> <before-file> <label>
iso_assert_unchanged() {
  local r="$1" before="$2" label="$3" delta
  iso_snapshot "$r" > "$r/snapshot.after" 2>&1
  delta=$(diff "$before" "$r/snapshot.after")
  assert_equal "" "$delta" "$label: the caller's config, remotes, branches, HEADs, working tree and origin are unchanged, and nothing was pushed"
}

# =============================================================================
# Static: every suite starts with the preamble that refuses a direct run.
# =============================================================================
ISO_MISSING_PREAMBLE=""
for _iso_f in "$ISO_TESTS_DIR"/*.test.sh; do
  _iso_first=$(awk '/^[[:space:]]*(#|$)/{next} {print; exit}' "$_iso_f")
  if [ "$_iso_first" != "$ISO_PREAMBLE" ]; then
    ISO_MISSING_PREAMBLE="$ISO_MISSING_PREAMBLE ${_iso_f##*/}"
  fi
done
assert_equal "" "$ISO_MISSING_PREAMBLE" "every suite's first command is the preamble that refuses to run without the shared library"

# `git` is a shell function in the suites, so `command -v git` names the
# function, not the binary; a stub that execs it re-runs itself forever.
ISO_GIT_LOOKUPS=$(grep -nE '(command -v|which) git([^A-Za-z0-9_-]|$)' "$ISO_TESTS_DIR"/*.test.sh \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -v "ISO_GIT_LOOKUPS")
assert_equal "" "$ISO_GIT_LOOKUPS" "no suite resolves the git binary with 'command -v git' (it names the guard function); use 'type -P git'"

# =============================================================================
# Build the callers, then run A, B and C in parallel.
# =============================================================================
iso_make_caller ISO_A "a"
iso_make_caller ISO_B "b"
iso_make_caller ISO_C "c"
iso_make_caller ISO_D "d"
iso_make_caller ISO_U "u"
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

_dossier_require_mktemp_dir ISO_TMP_A "isolation-nested-tmp-a"
_dossier_require_mktemp_dir ISO_TMP_B "isolation-nested-tmp-b"
mkdir -p "$ISO_C/wt/.nested-tmp"

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

# =============================================================================
# D. Each git-fixture suite run directly, from the worktree, without run.sh.
# =============================================================================
mkdir -p "$ISO_D/wt/.nested-tmp"
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
iso_assert_unchanged "$ISO_U" "$ISO_U/snapshot.before" "guard checks run from a linked worktree"

# =============================================================================
# Collect A, B and C.
# =============================================================================
wait "$ISO_PID_A"
wait "$ISO_PID_B"
wait "$ISO_PID_C"

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
