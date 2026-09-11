# Tests for hooks/scripts/block-unchecked-merge.sh (issue #170).
#
# Contract: a `gh pr merge` is refused while any check is unfinished or failing,
# and `--auto` is refused on a base branch that requires no status checks —
# because GitHub's auto-merge waits for REQUIRED checks, so where none are
# required it merges at once, which is the opposite of what --auto is reached
# for. A fully green pull request merges by any route.
#
# `gh` is stubbed so the scenarios are exact and offline: each case writes a
# small script named `gh` onto PATH that answers the three calls the hook makes
# (repo view, pr view --json, api). The rollup shapes are the ones GitHub
# actually returns, including a legacy StatusContext, which carries `state`
# rather than `status`/`conclusion` and was invisible to a check that counted
# only CheckRun entries.
#
# Prereq: jq. SKIPS gracefully otherwise.

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"; _flow_assert_pass "SKIP: jq not installed"; return 0
fi

HOOK="$REPO_ROOT/plugins/flow/hooks/scripts/block-unchecked-merge.sh"

BUM_CLEANUP=()
_bum_cleanup() {
  local p
  for p in "${BUM_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done
}
trap _bum_cleanup EXIT

# _bum_stub <rollup-json> <protection-json> <rules-json>
# Builds a directory holding a `gh` stub and prints its path.
_bum_stub() {
  local rollup="$1" prot="$2" rules="$3" d
  d=$(mktemp -d -t flow-bum.XXXXXX 2>/dev/null) || { printf ''; return 1; }
  BUM_CLEANUP+=("$d")
  printf '%s' "$rollup" > "$d/rollup.json"
  printf '%s' "$prot"   > "$d/prot.json"
  printf '%s' "$rules"  > "$d/rules.json"
  cat > "$d/gh" <<'STUB'
#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
case "$1 $2" in
  "repo view") echo "acme/widgets"; exit 0 ;;
  "pr view")   cat "$D/rollup.json"; exit 0 ;;
esac
if [ "$1" = "api" ]; then
  case "$2" in
    *protection/required_status_checks)
      [ -s "$D/prot.json" ] && cat "$D/prot.json" && exit 0
      echo "gh: Branch not protected (HTTP 404)" >&2; exit 1 ;;
    *rules/branches/*)
      [ -s "$D/rules.json" ] && cat "$D/rules.json" && exit 0
      echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  esac
fi
exit 1
STUB
  chmod +x "$d/gh"
  printf '%s' "$d"
}

_bum_run() {
  local stub="$1" cmd="$2" json
  json=$(printf '%s' "$cmd" | jq -Rs .)
  printf '{"tool_input":{"command":%s}}' "$json" \
    | PATH="$stub:$PATH" bash "$HOOK" >/dev/null 2>&1
}

_bum_stderr() {
  local stub="$1" cmd="$2" json
  json=$(printf '%s' "$cmd" | jq -Rs .)
  printf '{"tool_input":{"command":%s}}' "$json" \
    | PATH="$stub:$PATH" bash "$HOOK" 2>&1 >/dev/null
}

GREEN='{"number":7,"baseRefName":"main","statusCheckRollup":[
  {"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"SUCCESS"},
  {"__typename":"CheckRun","name":"lint","status":"COMPLETED","conclusion":"SUCCESS"}]}'
QUEUED='{"number":7,"baseRefName":"main","statusCheckRollup":[
  {"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"SUCCESS"},
  {"__typename":"CheckRun","name":"build","status":"QUEUED","conclusion":null}]}'
RUNNING='{"number":7,"baseRefName":"main","statusCheckRollup":[
  {"__typename":"CheckRun","name":"e2e","status":"IN_PROGRESS","conclusion":null}]}'
FAILING='{"number":7,"baseRefName":"main","statusCheckRollup":[
  {"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"FAILURE"}]}'
LEGACY_PENDING='{"number":7,"baseRefName":"main","statusCheckRollup":[
  {"__typename":"StatusContext","context":"ci/jenkins","state":"PENDING"}]}'
NO_CHECKS='{"number":7,"baseRefName":"main","statusCheckRollup":[]}'
PROT='{"contexts":["test"]}'
RULES='[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"test"}]}}]'

# --- the case that prompted the issue -----------------------------------------
_flow_test_begin "a merge is refused while a check is queued"
S=$(_bum_stub "$QUEUED" "" "")
_bum_run "$S" "gh pr merge 7 --squash"
assert_exit 2 "$?" "queued check blocks the merge"
ERR=$(_bum_stderr "$S" "gh pr merge 7 --squash")
assert_contains "build" "$ERR" "the message names the unfinished check"
assert_contains "queued" "$ERR" "and says what state it is in"

_flow_test_begin "a merge is refused while a check is running"
S=$(_bum_stub "$RUNNING" "" "")
_bum_run "$S" "gh pr merge 7 --squash"
assert_exit 2 "$?" "in-progress check blocks the merge"

_flow_test_begin "a merge is refused when a check failed"
S=$(_bum_stub "$FAILING" "" "")
_bum_run "$S" "gh pr merge 7 --squash"
assert_exit 2 "$?" "failing check blocks the merge"
ERR=$(_bum_stderr "$S" "gh pr merge 7 --squash")
assert_contains "did not pass" "$ERR" "the message says the check did not pass"

# A legacy StatusContext carries `state`, not `status`/`conclusion`. A rollup
# reader that selects only CheckRun sees an empty list here and calls it green.
_flow_test_begin "a pending legacy status is not invisible"
S=$(_bum_stub "$LEGACY_PENDING" "" "")
_bum_run "$S" "gh pr merge 7 --squash"
assert_exit 2 "$?" "pending StatusContext blocks the merge"
ERR=$(_bum_stderr "$S" "gh pr merge 7 --squash")
assert_contains "ci/jenkins" "$ERR" "the message names it"

# --- green passes, by any route -----------------------------------------------
_flow_test_begin "a fully green pull request merges"
S=$(_bum_stub "$GREEN" "" "")
_bum_run "$S" "gh pr merge 7 --squash --delete-branch"
assert_exit 0 "$?" "green merge allowed"
_bum_run "$S" "gh pr merge --squash"
assert_exit 0 "$?" "green merge with no explicit number allowed"
_bum_run "$S" "gh pr merge 7 --merge"
assert_exit 0 "$?" "strategy does not matter"

# --- --auto, with and without required checks ---------------------------------
_flow_test_begin "--auto is refused where nothing is required"
S=$(_bum_stub "$GREEN" "" "")
_bum_run "$S" "gh pr merge 7 --auto --squash"
assert_exit 2 "$?" "--auto blocked when the base requires no checks"
ERR=$(_bum_stderr "$S" "gh pr merge 7 --auto --squash")
assert_contains "requires no status checks" "$ERR" "the message says that is why"
assert_contains "merges immediately" "$ERR" "and what --auto would actually do"

_flow_test_begin "--auto is allowed where branch protection requires checks"
S=$(_bum_stub "$GREEN" "$PROT" "")
_bum_run "$S" "gh pr merge 7 --auto --squash"
assert_exit 0 "$?" "--auto allowed with required checks from branch protection"

# Branch protection is not the only way to require a check. Asking only the
# protection endpoint reports "none required" on a repository that requires
# plenty through a ruleset.
_flow_test_begin "--auto is allowed where a ruleset requires checks"
S=$(_bum_stub "$GREEN" "" "$RULES")
_bum_run "$S" "gh pr merge 7 --auto --squash"
assert_exit 0 "$?" "--auto allowed with required checks from a ruleset"

_flow_test_begin "a pull request with no checks at all is not called green"
S=$(_bum_stub "$NO_CHECKS" "" "")
_bum_run "$S" "gh pr merge 7 --squash"
assert_exit 0 "$?" "no checks is not a failure — nothing is pending"
_bum_run "$S" "gh pr merge 7 --auto --squash"
assert_exit 2 "$?" "but --auto still has nothing to wait for"

# --- the hook reads commands, not text ----------------------------------------
_flow_test_begin "text that names a merge but runs none is allowed"
S=$(_bum_stub "$QUEUED" "" "")
_bum_run "$S" 'echo "gh pr merge 7 --auto"'
assert_exit 0 "$?" "quoting the command is not running it"
_bum_run "$S" "# gh pr merge 7"
assert_exit 0 "$?" "a comment naming it is not running it"
_bum_run "$S" "npm run merge-check"
assert_exit 0 "$?" "a script whose name contains merge is not gh pr merge"
_bum_run "$S" "git merge --no-ff feature/x"
assert_exit 0 "$?" "git merge is a different command and not this gate"
_bum_run "$S" "gh pr view 7"
assert_exit 0 "$?" "another gh subcommand is untouched"

_flow_test_begin "a merge inside a compound command is still examined"
S=$(_bum_stub "$QUEUED" "" "")
_bum_run "$S" "git fetch && gh pr merge 7 --squash"
assert_exit 2 "$?" "after && the merge is still found"
_bum_run "$S" "/usr/bin/gh pr merge 7 --squash"
assert_exit 2 "$?" "an absolute gh path is still gh"

# --- it refuses rather than guessing ------------------------------------------
_flow_test_begin "a gate that cannot see refuses"
S=$(_bum_stub "" "" "")
_bum_run "$S" "gh pr merge 7 --squash"
assert_exit 2 "$?" "an unreadable rollup blocks rather than allowing"
ERR=$(_bum_stderr "$S" "gh pr merge 7 --squash")
assert_contains "cannot see must not open" "$ERR" "and says why"

# --- registered where it will actually run ------------------------------------
_flow_test_begin "the hook is registered on PreToolUse for Bash"
HOOKS_JSON="$REPO_ROOT/plugins/flow/hooks/hooks.json"
if command -v python3 >/dev/null 2>&1; then
  REGISTERED=$(python3 -c "
import json,sys
d=json.load(open('$HOOKS_JSON'))
pre=d.get('hooks',{}).get('PreToolUse',[])
print(sum(1 for m in pre if m.get('matcher')=='Bash'
          for h in m.get('hooks',[]) if 'block-unchecked-merge.sh' in h.get('command','')))
" 2>/dev/null)
  if [ "${REGISTERED:-0}" = "1" ]; then
    _flow_assert_pass "hooks.json runs it on PreToolUse/Bash"
  else
    _flow_assert_fail "block-unchecked-merge.sh is not registered in hooks.json — it would never run"
  fi
else
  if grep -q 'block-unchecked-merge.sh' "$HOOKS_JSON"; then
    _flow_assert_pass "hooks.json names it (python3 unavailable for a structural check)"
  else
    _flow_assert_fail "block-unchecked-merge.sh is not named in hooks.json"
  fi
fi

_flow_test_begin "the hook is executable"
if [ -x "$HOOK" ]; then
  _flow_assert_pass "mode allows execution"
else
  _flow_assert_fail "$HOOK is not executable, so the hook runner cannot start it"
fi

# --- the bypass matrix --------------------------------------------------------
# Twenty-seven commands that two reviewers constructed against an earlier
# version of this hook, each of which let a merge through. They live in a
# python fixture rather than here because each needs a gh stub that answers
# differently per selector and LOGS ITS ARGV — the discriminating input this
# file could not see, because the stub above matches on "$1 $2" and ignores
# everything after it. That is why a green run of this file was not evidence.
_flow_test_begin "every known bypass is closed"
MATRIX="$REPO_ROOT/plugins/flow/tests/fixtures/merge-bypass-matrix.py"
if ! command -v python3 >/dev/null 2>&1; then
  _flow_assert_pass "SKIP: python3 unavailable"
elif [ ! -f "$MATRIX" ]; then
  _flow_assert_fail "the bypass matrix is missing at $MATRIX"
else
  MOUT=$(python3 "$MATRIX" "$HOOK" 2>&1); MRC=$?
  MCOUNT=$(printf '%s' "$MOUT" | sed -n 's/^\([0-9]*\) bypass cases.*/\1/p')
  if [ "$MRC" -eq 0 ] && [ "${MCOUNT:-0}" -ge 25 ]; then
    _flow_assert_pass "$MCOUNT bypass cases, all correct"
  else
    _flow_assert_fail "bypass matrix failed (exit $MRC, ${MCOUNT:-0} cases):
$(printf '%s' "$MOUT" | grep -E '^  BAD|wrong$' | head -12)"
  fi
fi
