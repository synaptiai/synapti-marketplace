# Tests for plugins/flow/hooks/scripts/flow-goal-stop.sh (warn mode default).
#
# Contract:
#   - When .flow/goals/ does not exist: emit {"decision":"approve","reason":"no active flow goal"}
#   - When .flow/goals/ exists but no goal has lifecycle.status==active: same
#   - When active goal exists and all ACs pass: emit "evidence complete; ready for /flow:goal evaluate"
#   - When active goal has a failing AC: emit FLOW_GOAL_INCOMPLETE warning
#   - mode=block uses decision:block instead of decision:approve
#   - mode=evaluator-loop delegates to flow-goal-evaluator.sh (smoke check only;
#     the active-mode tests live separately because they require `claude` CLI)
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
mkdir -p "$DIR/.flow/goals"
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
mkdir -p "$DIR/.flow/goals"
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
