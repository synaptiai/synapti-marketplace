# Tests for plugins/flow/hooks/scripts/flow-goal-stop.sh (warn mode default).
#
# Contract:
#   - When .flow/goals/ does not exist: emit {"decision":"approve","reason":"no active flow goal"}
#   - When .flow/goals/ exists but no goal has lifecycle.status==active: same
#   - When active goal exists and all ACs pass: emit "evidence complete; ready for /flow:goal evaluate"
#   - When active goal has a failing AC in warn mode: emit an HONEST approve —
#     reason starts "FLOW_GOAL_INCOMPLETE — stop ALLOWED (stopHookEnforcement=warn)",
#     ends with the enforce hint, and the same text is printed to stderr
#   - mode=block: verification commands run when the goal is trusted (ledger)
#     or executeVerificationCommands is true; blocks on failing ACs, path
#     violations, and ACs with no command; an untrusted goal's not-executed
#     ACs never block on their own; consecutive blocks for one (session, goal)
#     are capped at flow.goals.failAfterStuckTurns → FLOW_GOAL_BLOCK_CAP approve
#   - mode=evaluator-loop delegates to flow-goal-evaluator.sh (smoke check only;
#     full active-mode coverage lives in flow-goal-evaluator.test.sh, which
#     stubs `claude --print` via tests/lib/mock-claude.sh)
#
# The Stop hook reads stdin (Stop event JSON). We feed it via _run_hook helper.

HOOK="$REPO_ROOT/plugins/flow/hooks/scripts/flow-goal-stop.sh"
DETERMINISTIC="$REPO_ROOT/plugins/flow/hooks/scripts/flow-run-deterministic-checks.sh"

# Reuse the cleanup pattern.
FGS_CLEANUP_PATHS=()
_fgs_cleanup() {
  local p
  for p in "${FGS_CLEANUP_PATHS[@]:-}"; do
    [ -n "$p" ] && rm -rf "$p" 2>/dev/null
  done
}
trap _fgs_cleanup EXIT

_fgs_mktemp_dir() {
  local out
  out=$(mktemp -d -t flow-goal-stop.tests.XXXXXX 2>/dev/null)
  if [ -z "$out" ] || [ ! -d "$out" ]; then
    echo "flow-goal-stop.test.sh: mktemp -d failed" >&2
    kill -INT $$ 2>/dev/null
    exit 2
  fi
  FGS_CLEANUP_PATHS+=("$out")
  printf '%s' "$out"
}

# Every invocation gets a FLOW_STATE_DIR under the test dir so the trust
# ledger and the block counter never touch the developer's real state. The
# variables are exported inside the subshell — an assignment prefix on a
# pipeline would apply to `printf` only, not to the hook.
_run_hook() {
  local dir="$1"; shift
  local stdin="${1:-{\}}"
  (cd "$dir" && export CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" FLOW_STATE_DIR="$dir/.flow-state" && printf '%s' "$stdin" | "$HOOK")
}

# Same, but stderr goes to $FGS_ERRFILE; read it with $(_fgs_err). (A variable
# set inside the function would be lost — callers run it in a $(...) subshell.)
FGS_ERRFILE=$(mktemp -t flow-goal-stop.err.XXXXXX)
FGS_CLEANUP_PATHS+=("$FGS_ERRFILE")
_run_hook_err() {
  local dir="$1"; shift
  local stdin="${1:-{\}}"
  (cd "$dir" && export CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" FLOW_STATE_DIR="$dir/.flow-state" && printf '%s' "$stdin" | "$HOOK" 2>"$FGS_ERRFILE")
}
_fgs_err() { cat "$FGS_ERRFILE"; }

# Trust a goal in the test dir's ledger (what flow-goal-record.sh --create does).
_trust_goal() {
  local dir="$1" goal="$2"
  (cd "$dir" && FLOW_STATE_DIR="$dir/.flow-state" "$REPO_ROOT/plugins/flow/bin/flow-goal-trust.sh" record --goal-file "$goal" >/dev/null 2>&1)
}

# Minimal active goal writer: $1 dir, $2 id, $3.. AC lines (already indented).
_write_goal() {
  local dir="$1" id="$2"; shift 2
  mkdir -p "$dir/.flow/goals"
  {
    printf 'apiVersion: flow.synapti.ai/v1\nkind: FlowGoal\nmetadata:\n  id: %s\n  created_at: %s\nscope: {repo: test/test, branch: test}\nobjective:\n  outcome: test\n  acceptance_criteria:\n' "$id" "'2026-05-20T14:30:00Z'"
    printf '%s\n' "$@"
    printf 'evaluator:\n  type: flow_verdict_judge\nlifecycle:\n  status: active\n'
  } > "$dir/.flow/goals/$id.goal.yaml"
}

_block_count() {
  local dir="$1" sid="$2"
  jq -r '.count' "$dir/.flow-state/sessions/$sid/stop-blocks.json" 2>/dev/null
}

# Prerequisites.
if ! command -v python3 >/dev/null 2>&1; then
  _flow_test_begin "python3 prerequisite"
  _flow_assert_pass "SKIP: python3 not installed"
  return 0
fi
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_test_begin "PyYAML prerequisite"
  _flow_assert_pass "SKIP: PyYAML not installed"
  return 0
fi
if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi

# --- Test 1: no .flow/ directory → silent approve
_flow_test_begin "no .flow/ directory → approve (silent)"
DIR=$(_fgs_mktemp_dir)
OUT=$(_run_hook "$DIR" '{"session_id":"test","transcript_path":""}')
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$DECISION" "decision is approve"
assert_contains "no active flow goal" "$REASON" "reason names absence"

# --- Test 2: .flow/goals/ exists but empty → approve
_flow_test_begin ".flow/goals/ empty → approve"
DIR=$(_fgs_mktemp_dir)
mkdir -p "$DIR/.flow/goals"
OUT=$(_run_hook "$DIR" '{"session_id":"test"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
assert_equal "approve" "$DECISION" "decision is approve"
assert_contains "no active flow goal" "$(echo "$OUT" | jq -r '.reason')" "reason names absence"

# --- Test 3: goal exists but status is terminal (cancelled) → approve
_flow_test_begin "goal exists but status cancelled → approve"
DIR=$(_fgs_mktemp_dir)
mkdir -p "$DIR/.flow/goals"
cat > "$DIR/.flow/goals/old-goal.goal.yaml" <<'YML'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: old-goal
  created_at: '2026-05-20T14:30:00Z'
scope:
  repo: test/test
  branch: test
objective:
  outcome: test
  acceptance_criteria:
    - id: AC1
      text: test
      status: pending
evaluator:
  type: flow_verdict_judge
lifecycle:
  status: cancelled
YML
OUT=$(_run_hook "$DIR" '{"session_id":"test"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
assert_equal "approve" "$DECISION" "decision is approve"

# --- Test 4: active goal with passing AC (verification_command exits 0)
_flow_test_begin "active goal, AC verification_command exits 0 → approve (evidence complete)"
DIR=$(_fgs_mktemp_dir)
mkdir -p "$DIR/.claude" "$DIR/.flow/goals"
# Opt in to verification_command execution. Default is false (security gate).
cat > "$DIR/.claude/settings.flow.json" <<'JSON'
{"flow":{"goals":{"executeVerificationCommands":true}}}
JSON
cat > "$DIR/.flow/goals/pass.goal.yaml" <<'YML'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: pass
  created_at: '2026-05-20T14:30:00Z'
scope:
  repo: test/test
  branch: test
objective:
  outcome: test
  acceptance_criteria:
    - id: AC1
      text: test
      verification_command: 'true'
      must_pass: true
      status: pending
evaluator:
  type: flow_verdict_judge
lifecycle:
  status: active
YML
OUT=$(_run_hook "$DIR" '{"session_id":"test"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$DECISION" "decision is approve"
assert_contains "evidence complete" "$REASON" "reason names evidence-complete state"

# --- Test 5: active goal with failing AC → warn (still approve)
_flow_test_begin "active goal, AC verification_command exits non-zero → warn approve"
DIR=$(_fgs_mktemp_dir)
mkdir -p "$DIR/.claude" "$DIR/.flow/goals"
cat > "$DIR/.claude/settings.flow.json" <<'JSON'
{"flow":{"goals":{"executeVerificationCommands":true}}}
JSON
cat > "$DIR/.flow/goals/fail.goal.yaml" <<'YML'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: fail
  created_at: '2026-05-20T14:30:00Z'
scope:
  repo: test/test
  branch: test
objective:
  outcome: test
  acceptance_criteria:
    - id: AC1
      text: test
      verification_command: 'false'
      must_pass: true
      status: pending
evaluator:
  type: flow_verdict_judge
lifecycle:
  status: active
YML
OUT=$(_run_hook_err "$DIR" '{"session_id":"test"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$DECISION" "warn mode: decision is approve"
assert_match '^FLOW_GOAL_INCOMPLETE — stop ALLOWED \(stopHookEnforcement=warn\)' "$REASON" "warn reason opens by saying the stop is allowed"
assert_contains "Failing acceptance criteria: AC1" "$REASON" "warn reason names failing AC"
assert_match 'set flow.goals.stopHookEnforcement to block\.$' "$REASON" "warn reason ends with the enforce hint"
assert_contains "FLOW_GOAL_INCOMPLETE — stop ALLOWED (stopHookEnforcement=warn)" "$(_fgs_err)" "same text reaches stderr (the terminal)"
assert_contains "Failing acceptance criteria: AC1" "$(_fgs_err)" "stderr carries the details"

# --- Test 6: judge mode env guard → silent approve (recursion protection)
_flow_test_begin "CLAUDE_HOOK_GOAL_JUDGE_MODE=true → silent approve (recursion guard)"
DIR=$(_fgs_mktemp_dir)
mkdir -p "$DIR/.flow/goals"
cat > "$DIR/.flow/goals/any.goal.yaml" <<'YML'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: any
  created_at: '2026-05-20T14:30:00Z'
scope: {repo: test/test, branch: test}
objective:
  outcome: test
  acceptance_criteria:
    - {id: AC1, text: test, status: pending}
evaluator:
  type: flow_verdict_judge
lifecycle:
  status: active
YML
OUT=$(cd "$DIR" && printf '{"session_id":"test"}' | \
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" CLAUDE_HOOK_GOAL_JUDGE_MODE=true "$HOOK")
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$DECISION" "judge mode short-circuits to approve"
assert_contains "judge mode" "$REASON" "reason confirms recursion guard"

# --- Test 7: Python source-injection defense (hostile AC ID with quote chars)
# An AC with id containing triple-quotes used to escape the Python heredoc and
# execute arbitrary Python in flow-goal-stop.sh. Argv-passing prevents this.
_flow_test_begin "warn mode tolerates hostile AC IDs with quote characters"
DIR=$(_fgs_mktemp_dir)
mkdir -p "$DIR/.flow/goals"
cat > "$DIR/.flow/goals/hostile.goal.yaml" <<'YML'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: hostile
  created_at: '2026-05-20T14:30:00Z'
scope: {repo: test/test, branch: test}
objective:
  outcome: test
  acceptance_criteria:
    - id: "AC1'''; __import__('os').system('touch /tmp/flow-injection-pwn'); '''"
      text: hostile AC id with triple-quote injection attempt
      status: pending
evaluator:
  type: flow_verdict_judge
lifecycle:
  status: active
YML
rm -f /tmp/flow-injection-pwn 2>/dev/null
OUT=$(_run_hook "$DIR" '{"session_id":"test"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
assert_equal "approve" "$DECISION" "warn mode survives hostile AC ID (no crash)"
if [ -e /tmp/flow-injection-pwn ]; then
  _flow_assert_fail "RCE via hostile AC ID — file /tmp/flow-injection-pwn was created"
  rm -f /tmp/flow-injection-pwn
else
  _flow_assert_pass "no RCE via hostile AC ID"
fi

# --- Test 8b: executeVerificationCommands default false → no auto-exec
# Default-deny security gate: a goal with verification_command MUST NOT run
# its command unless the user opts in. Drop a sentinel marker; if the command
# ran, the file appears; assert it does NOT.
_flow_test_begin "executeVerificationCommands defaults false → verification_command NOT executed"
DIR=$(_fgs_mktemp_dir)
mkdir -p "$DIR/.flow/goals"
SENTINEL="$DIR/should-not-exist"
cat > "$DIR/.flow/goals/exec-test.goal.yaml" <<YML
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: exec-test
  created_at: '2026-05-20T14:30:00Z'
scope: {repo: test/test, branch: test}
objective:
  outcome: security gate test
  acceptance_criteria:
    - id: AC1
      text: should not execute
      verification_command: 'touch ${SENTINEL}'
      must_pass: true
      status: pending
evaluator:
  type: flow_verdict_judge
lifecycle:
  status: active
YML
OUT=$(_run_hook "$DIR" '{"session_id":"test"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$DECISION" "default-deny: decision is approve"
if [ -e "$SENTINEL" ]; then
  _flow_assert_fail "SECURITY GATE BREACH: verification_command ran without opt-in (sentinel exists)"
  rm -f "$SENTINEL"
else
  _flow_assert_pass "verification_command not executed without opt-in"
fi
assert_contains "FLOW_GOAL_INCOMPLETE" "$REASON" "AC reported as incomplete when not executed"
assert_contains "1 acceptance criteria not executed because goal exec-test is not trusted" "$REASON" "reason explains the untrusted goal"
assert_contains "flow-goal-trust.sh record --goal-file .flow/goals/exec-test.goal.yaml" "$REASON" "reason gives the record command"
DET=$(cd "$DIR" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" FLOW_STATE_DIR="$DIR/.flow-state" "$DETERMINISTIC" .flow/goals/exec-test.goal.yaml 2>/dev/null)
assert_equal "false" "$(echo "$DET" | jq -r '.trusted')" "report.trusted is false for an unrecorded goal"
assert_equal "AC1" "$(echo "$DET" | jq -r '.not_executed[0]')" "report.not_executed lists the skipped AC"
assert_contains "not_executed (goal not trusted; flow.goals.executeVerificationCommands is false)" "$(echo "$DET" | jq -r '.checked[0].reason')" "checked[].reason names both gates"

# --- Test 8: Unknown stopHookEnforcement value falls through to warn (not silent approve)
_flow_test_begin "unknown stopHookEnforcement value → falls back to warn (not silent)"
DIR=$(_fgs_mktemp_dir)
mkdir -p "$DIR/.claude" "$DIR/.flow/goals"
cat > "$DIR/.claude/settings.flow.json" <<'JSON'
{"flow":{"goals":{"stopHookEnforcement":"warning"}}}
JSON
cat > "$DIR/.flow/goals/any.goal.yaml" <<'YML'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: any
  created_at: '2026-05-20T14:30:00Z'
scope: {repo: test/test, branch: test}
objective:
  outcome: test
  acceptance_criteria:
    - {id: AC1, text: failing, status: pending, verification_command: "false", must_pass: true}
evaluator:
  type: flow_verdict_judge
lifecycle:
  status: active
YML
OUT=$(_run_hook_err "$DIR" '{"session_id":"test"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$DECISION" "unknown mode: decision is approve (warn fallback)"
assert_contains "FALLBACK_WARN" "$REASON" "reason signals fallback (not silent)"
assert_match '^FLOW_GOAL_INCOMPLETE — stop ALLOWED \(stopHookEnforcement=warn' "$REASON" "fallback is as honest as warn: stop allowed"
assert_match 'set flow.goals.stopHookEnforcement to block\.$' "$REASON" "fallback ends with the enforce hint"
assert_contains "unknown stopHookEnforcement value 'warning'" "$(_fgs_err)" "stderr names the bad value"
assert_contains "stop ALLOWED" "$(_fgs_err)" "stderr carries the warning text"

# ===========================================================================
# block mode
# ===========================================================================

# --- Test 9: trusted goal in block mode executes commands without the exec flag
_flow_test_begin "block mode: trusted goal executes verification_command and approves when passing"
DIR=$(_fgs_mktemp_dir)
mkdir -p "$DIR/.claude"
cat > "$DIR/.claude/settings.flow.json" <<'JSON'
{"flow":{"goals":{"stopHookEnforcement":"block"}}}
JSON
SENTINEL="$DIR/ran-because-trusted"
_write_goal "$DIR" trusted-pass \
  "    - {id: AC1, text: passes, status: pending, must_pass: true, verification_command: 'touch $SENTINEL'}"
_trust_goal "$DIR" .flow/goals/trusted-pass.goal.yaml
DET=$(cd "$DIR" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" FLOW_STATE_DIR="$DIR/.flow-state" "$DETERMINISTIC" .flow/goals/trusted-pass.goal.yaml 2>/dev/null)
assert_equal "true" "$(echo "$DET" | jq -r '.trusted')" "report.trusted is true after record"
OUT=$(_run_hook "$DIR" '{"session_id":"blk","stop_hook_active":false}')
assert_equal "approve" "$(echo "$OUT" | jq -r '.decision')" "passing trusted goal approves"
assert_contains "evidence complete" "$(echo "$OUT" | jq -r '.reason')" "reason names evidence-complete state"
assert_file_exists "$SENTINEL" "verification_command actually ran (no executeVerificationCommands flag set)"

# --- Test 10: trusted goal with a failing command blocks
_flow_test_begin "block mode: trusted goal with failing verification_command → block"
DIR=$(_fgs_mktemp_dir)
mkdir -p "$DIR/.claude"
cat > "$DIR/.claude/settings.flow.json" <<'JSON'
{"flow":{"goals":{"stopHookEnforcement":"block"}}}
JSON
_write_goal "$DIR" trusted-fail \
  "    - {id: AC1, text: fails, status: pending, must_pass: true, verification_command: 'false'}"
_trust_goal "$DIR" .flow/goals/trusted-fail.goal.yaml
OUT=$(_run_hook_err "$DIR" '{"session_id":"blk","stop_hook_active":false}')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "block" "$(echo "$OUT" | jq -r '.decision')" "failing trusted goal blocks"
assert_match '^FLOW_GOAL_INCOMPLETE — stop BLOCKED \(stopHookEnforcement=block; block 1 of 3\)' "$REASON" "reason says BLOCKED with the block count"
assert_contains "Failing acceptance criteria: AC1" "$REASON" "reason names the failing AC"
assert_not_contains "not trusted" "$REASON" "trusted goal gets no trust hint"
assert_contains "stop BLOCKED" "$(_fgs_err)" "block text reaches stderr"
assert_equal "1" "$(_block_count "$DIR" blk)" "counter records block 1"

# --- Test 11: untrusted goal — a no-command AC blocks; not-executed ACs are explained
_flow_test_begin "block mode: untrusted goal with a no-command AC → block, not-executed ACs explained"
DIR=$(_fgs_mktemp_dir)
mkdir -p "$DIR/.claude"
cat > "$DIR/.claude/settings.flow.json" <<'JSON'
{"flow":{"goals":{"stopHookEnforcement":"block"}}}
JSON
SENTINEL="$DIR/must-not-run"
_write_goal "$DIR" untrusted-mixed \
  "    - {id: AC1, text: fuzzy, status: pending}" \
  "    - {id: AC2, text: has command, status: pending, must_pass: true, verification_command: 'touch $SENTINEL'}"
OUT=$(_run_hook "$DIR" '{"session_id":"blk","stop_hook_active":false}')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "block" "$(echo "$OUT" | jq -r '.decision')" "no-command AC blocks"
assert_contains "Missing evidence for: AC1" "$REASON" "reason names the no-command AC only"
assert_not_contains "Missing evidence for: AC1, AC2" "$REASON" "not-executed AC is not listed as missing evidence"
assert_contains "1 acceptance criteria not executed because goal untrusted-mixed is not trusted" "$REASON" "reason explains the untrusted goal"
assert_contains "flow-goal-trust.sh record --goal-file .flow/goals/untrusted-mixed.goal.yaml" "$REASON" "reason gives the record command"
if [ -e "$SENTINEL" ]; then
  _flow_assert_fail "untrusted goal's verification_command ran in block mode"
else
  _flow_assert_pass "untrusted goal's verification_command did not run"
fi

# --- Test 12: untrusted goal whose only gaps are not-executed ACs → approve (never a permanent block)
_flow_test_begin "block mode: untrusted goal with only not-executed ACs → approve FLOW_GOAL_UNVERIFIED"
DIR=$(_fgs_mktemp_dir)
mkdir -p "$DIR/.claude"
cat > "$DIR/.claude/settings.flow.json" <<'JSON'
{"flow":{"goals":{"stopHookEnforcement":"block"}}}
JSON
_write_goal "$DIR" untrusted-only \
  "    - {id: AC1, text: has command, status: pending, must_pass: true, verification_command: 'false'}"
OUT=$(_run_hook_err "$DIR" '{"session_id":"blk","stop_hook_active":true}')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$(echo "$OUT" | jq -r '.decision')" "not-executed ACs alone do not block"
assert_match '^FLOW_GOAL_UNVERIFIED — stop ALLOWED \(stopHookEnforcement=block' "$REASON" "reason says the stop is allowed and why"
assert_contains "not trusted" "$REASON" "reason explains the untrusted goal"
assert_contains "FLOW_GOAL_UNVERIFIED" "$(_fgs_err)" "text reaches stderr"

# --- Test 13: consecutive-block cap → FLOW_GOAL_BLOCK_CAP approve, counter reset
_flow_test_begin "block mode: cap reached after failAfterStuckTurns consecutive blocks → approve + reset"
DIR=$(_fgs_mktemp_dir)
mkdir -p "$DIR/.claude"
cat > "$DIR/.claude/settings.flow.json" <<'JSON'
{"flow":{"goals":{"stopHookEnforcement":"block","failAfterStuckTurns":2}}}
JSON
_write_goal "$DIR" capped "    - {id: AC1, text: fuzzy, status: pending}"
OUT=$(_run_hook "$DIR" '{"session_id":"cap","stop_hook_active":false}')
assert_equal "block" "$(echo "$OUT" | jq -r '.decision')" "first stop blocks"
assert_contains "block 1 of 2" "$(echo "$OUT" | jq -r '.reason')" "first block is 1 of 2"
OUT=$(_run_hook "$DIR" '{"session_id":"cap","stop_hook_active":true}')
assert_equal "block" "$(echo "$OUT" | jq -r '.decision')" "second consecutive stop blocks"
assert_contains "block 2 of 2" "$(echo "$OUT" | jq -r '.reason')" "second block is 2 of 2"
assert_equal "2" "$(_block_count "$DIR" cap)" "counter is 2"
OUT=$(_run_hook_err "$DIR" '{"session_id":"cap","stop_hook_active":true}')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$(echo "$OUT" | jq -r '.decision')" "third consecutive stop is approved"
assert_equal "FLOW_GOAL_BLOCK_CAP — stop ALLOWED after 2 consecutive blocks; run /flow:goal evaluate capped" "$REASON" "cap reason is exact"
assert_contains "FLOW_GOAL_BLOCK_CAP" "$(_fgs_err)" "cap text reaches stderr"
assert_equal "0" "$(_block_count "$DIR" cap)" "counter reset after the cap"
OUT=$(_run_hook "$DIR" '{"session_id":"cap","stop_hook_active":true}')
assert_contains "block 1 of 2" "$(echo "$OUT" | jq -r '.reason')" "chain restarts at 1 after the cap"

# --- Test 14: stop_hook_active=false restarts the chain; other sessions are independent
_flow_test_begin "block mode: stop_hook_active=false restarts the count; sessions are independent"
OUT=$(_run_hook "$DIR" '{"session_id":"cap","stop_hook_active":false}')
assert_contains "block 1 of 2" "$(echo "$OUT" | jq -r '.reason')" "a non-continuation stop restarts at 1"
OUT=$(_run_hook "$DIR" '{"session_id":"other","stop_hook_active":true}')
assert_contains "block 1 of 2" "$(echo "$OUT" | jq -r '.reason')" "another session starts its own count"
assert_equal "1" "$(_block_count "$DIR" other)" "per-session counter file"

# --- Test 15: complete evidence resets the counter
_flow_test_begin "block mode: evidence complete resets the block counter"
DIR=$(_fgs_mktemp_dir)
mkdir -p "$DIR/.claude"
cat > "$DIR/.claude/settings.flow.json" <<'JSON'
{"flow":{"goals":{"stopHookEnforcement":"block","failAfterStuckTurns":3}}}
JSON
_write_goal "$DIR" resets "    - {id: AC1, text: fuzzy, status: pending}"
_run_hook "$DIR" '{"session_id":"rs","stop_hook_active":false}' >/dev/null
_run_hook "$DIR" '{"session_id":"rs","stop_hook_active":true}' >/dev/null
assert_equal "2" "$(_block_count "$DIR" rs)" "two consecutive blocks recorded"
# The AC gains a passing command; the goal is recorded (trusted) as flow would.
_write_goal "$DIR" resets "    - {id: AC1, text: now verifiable, status: pending, must_pass: true, verification_command: 'true'}"
_trust_goal "$DIR" .flow/goals/resets.goal.yaml
OUT=$(_run_hook "$DIR" '{"session_id":"rs","stop_hook_active":true}')
assert_equal "approve" "$(echo "$OUT" | jq -r '.decision')" "complete evidence approves"
assert_contains "evidence complete" "$(echo "$OUT" | jq -r '.reason')" "reason names evidence-complete"
assert_equal "0" "$(_block_count "$DIR" rs)" "counter reset to 0 on complete evidence"

# --- Test 16: symlinked counter file is never followed
_flow_test_begin "block mode: symlinked stop-blocks.json is refused and treated as 0"
DIR=$(_fgs_mktemp_dir)
mkdir -p "$DIR/.claude" "$DIR/.flow-state/sessions/sym"
cat > "$DIR/.claude/settings.flow.json" <<'JSON'
{"flow":{"goals":{"stopHookEnforcement":"block"}}}
JSON
echo '{"goal_id":"symgoal","count":99}' > "$DIR/victim.json"
ln -s "$DIR/victim.json" "$DIR/.flow-state/sessions/sym/stop-blocks.json"
_write_goal "$DIR" symgoal "    - {id: AC1, text: fuzzy, status: pending}"
OUT=$(_run_hook_err "$DIR" '{"session_id":"sym","stop_hook_active":true}')
assert_equal "block" "$(echo "$OUT" | jq -r '.decision')" "symlinked counter does not trigger the cap"
assert_contains "block 1 of 3" "$(echo "$OUT" | jq -r '.reason')" "count restarts at 1"
assert_contains "symlink" "$(_fgs_err)" "stderr names the symlink refusal"
assert_equal "99" "$(jq -r '.count' "$DIR/victim.json")" "symlink target untouched"

# --- Test 17: hostile session_id is sanitized before it becomes a path
_flow_test_begin "block mode: hostile session_id cannot escape the sessions dir"
DIR=$(_fgs_mktemp_dir)
mkdir -p "$DIR/.claude"
cat > "$DIR/.claude/settings.flow.json" <<'JSON'
{"flow":{"goals":{"stopHookEnforcement":"block"}}}
JSON
_write_goal "$DIR" hostile-sid "    - {id: AC1, text: fuzzy, status: pending}"
OUT=$(_run_hook "$DIR" '{"session_id":"../../escape","stop_hook_active":false}')
assert_equal "block" "$(echo "$OUT" | jq -r '.decision')" "hook still decides"
assert_file_exists "$DIR/.flow-state/sessions/escape/stop-blocks.json" "path components stripped to [A-Za-z0-9_-]"
if [ -e "$DIR/escape/stop-blocks.json" ] || [ -e "$DIR/.flow-state/escape/stop-blocks.json" ]; then
  _flow_assert_fail "session_id traversal escaped the sessions dir"
else
  _flow_assert_pass "no traversal outside sessions dir"
fi
