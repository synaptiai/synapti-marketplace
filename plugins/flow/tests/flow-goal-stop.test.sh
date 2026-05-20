# Tests for plugins/flow/hooks/scripts/flow-goal-stop.sh (warn mode default).
#
# Contract:
#   - When .flow/goals/ does not exist: emit {"decision":"approve","reason":"no active flow goal"}
#   - When .flow/goals/ exists but no goal has lifecycle.status==active: same
#   - When active goal exists and all ACs pass: emit "evidence complete; ready for /flow:goal evaluate"
#   - When active goal has a failing AC: emit FLOW_GOAL_INCOMPLETE warning
#   - mode=block uses decision:block instead of decision:approve
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

_run_hook() {
  local dir="$1"; shift
  local stdin="${1:-{\}}"
  (cd "$dir" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" printf '%s' "$stdin" | "$HOOK")
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
OUT=$(_run_hook "$DIR" '{"session_id":"test"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$DECISION" "warn mode: decision is approve"
assert_contains "FLOW_GOAL_INCOMPLETE" "$REASON" "warn reason names incompleteness"
assert_contains "AC1" "$REASON" "warn reason names failing AC"

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
OUT=$(_run_hook "$DIR" '{"session_id":"test"}' 2>/dev/null)
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$DECISION" "unknown mode: decision is approve (warn fallback)"
assert_contains "FALLBACK_WARN" "$REASON" "reason signals fallback (not silent)"
