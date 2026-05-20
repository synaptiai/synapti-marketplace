#!/usr/bin/env bash
# [flow] Stop hook — active evaluator-loop mode (opt-in).
#
# Gated by flow.goals.stopHookEnforcement=evaluator-loop. Replicates the
# Claude Code /goal UX as a plugin: after every turn, evaluate whether the
# active FlowGoal has been achieved; if not, block-stop with a continuation
# prompt so the agent keeps working.
#
# Design constraints:
#   - Must NOT fork-bomb. The judge subprocess invocation sets
#     CLAUDE_HOOK_GOAL_JUDGE_MODE=true; flow-goal-stop.sh checks this
#     env var at the top and short-circuits.
#   - Must NOT run unbounded. Throttle at 3 continuations per 5-min window
#     per session via /tmp/.flow-goal-throttle-${SESSION_ID}.
#   - Must NOT enforce a Tier 3 (merge/release) action — block-stop only
#     blocks the agent's TURN, never enforces a higher-tier decision.
#   - Cost discipline: Haiku by default (~$0.001/eval); model configurable
#     via flow.goals.judge.model cascade key.
#
# Stdin: same Stop event payload that flow-goal-stop.sh received.

set -uo pipefail
export PYTHONSAFEPATH=1

command -v jq      >/dev/null 2>&1 || { echo '{"decision":"approve","reason":"jq unavailable"}'; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo '{"decision":"approve","reason":"python3 unavailable"}'; exit 0; }
command -v claude  >/dev/null 2>&1 || { echo '{"decision":"approve","reason":"claude CLI unavailable; evaluator-loop requires it"}'; exit 0; }
python3 -c "import yaml" >/dev/null 2>&1 || { echo '{"decision":"approve","reason":"PyYAML unavailable"}'; exit 0; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/../..}"

# Recursion guard (mirrors flow-goal-stop.sh). The judge subprocess sets
# this env var; if we see it, we're inside the judge and the parent flow-
# goal-stop.sh already handled the short-circuit. This is belt-and-
# suspenders — flow-goal-stop.sh delegates to us only when env var is unset.
if [ "${CLAUDE_HOOK_GOAL_JUDGE_MODE:-}" = "true" ]; then
  echo '{"decision":"approve","reason":"judge mode"}'
  exit 0
fi

EVENT=$(cat 2>/dev/null || echo '{}')
SESSION_ID=$(echo "$EVENT" | jq -r '.session_id // "unknown"')
TRANSCRIPT=$(echo "$EVENT" | jq -r '.transcript_path // ""')
STOP_ACTIVE=$(echo "$EVENT" | jq -r '.stop_hook_active // false')

# Resolve config from cascade.
JUDGE_MODEL=$("${PLUGIN_ROOT}/bin/cascade-resolve.sh" --default "haiku" '.flow.goals.judge.model // empty' 2>/dev/null)
[ -z "$JUDGE_MODEL" ] && JUDGE_MODEL="haiku"
JUDGE_TIMEOUT=$("${PLUGIN_ROOT}/bin/cascade-resolve.sh" --default "60" '.flow.goals.judge.timeoutSeconds // empty' 2>/dev/null)
[ -z "$JUDGE_TIMEOUT" ] && JUDGE_TIMEOUT="60"

# Throttle. Three continuations per 5-minute window per session. After that,
# force-approve and reset — protects against runaway loops.
THROTTLE_FILE="/tmp/.flow-goal-throttle-$(echo "$SESSION_ID" | tr '/' '_')"
NOW=$(date +%s)
CONTINUE_COUNT=0
LAST_TIME=0
if [ "$STOP_ACTIVE" = "true" ] && [ -f "$THROTTLE_FILE" ]; then
  THROTTLE_DATA=$(cat "$THROTTLE_FILE" 2>/dev/null)
  CONTINUE_COUNT=$(echo "$THROTTLE_DATA" | cut -d: -f1)
  LAST_TIME=$(echo "$THROTTLE_DATA" | cut -d: -f2)
  SINCE=$((NOW - LAST_TIME))
  # Reset if more than 5 minutes since last continuation.
  [ "$SINCE" -gt 300 ] && CONTINUE_COUNT=0
  if [ "$CONTINUE_COUNT" -ge 3 ] && [ "$SINCE" -lt 300 ]; then
    rm -f "$THROTTLE_FILE"
    echo '{"decision":"approve","reason":"evaluator-loop throttled: 3 continuations in 5min — forcing stop"}'
    exit 0
  fi
fi

# Find active goal (same logic as flow-goal-stop.sh).
ACTIVE_GOAL=$(python3 - <<'PYEOF' 2>/dev/null
import os, glob, sys, yaml
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
if not os.path.isdir(".flow/goals"):
    sys.exit(0)
for path in sorted(glob.glob(".flow/goals/*.goal.yaml")):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
        if data.get("lifecycle", {}).get("status") == "active":
            print(path)
            sys.exit(0)
    except Exception:
        continue
PYEOF
)
[ -z "$ACTIVE_GOAL" ] && { echo '{"decision":"approve","reason":"no active flow goal"}'; exit 0; }

# Budget check. Read turns_evaluated and max_iterations; transition to
# failed if exceeded.
BUDGET_REMAINING=$(python3 - "$ACTIVE_GOAL" <<'PYEOF' 2>/dev/null
import sys, yaml
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}
lifecycle = data.get("lifecycle") or {}
continuation = data.get("continuation") or {}
turns = int(lifecycle.get("turns_evaluated") or 0)
max_iter = int(continuation.get("max_iterations") or 20)
print(max(0, max_iter - turns))
PYEOF
)
[ -z "$BUDGET_REMAINING" ] && BUDGET_REMAINING="0"

if [ "$BUDGET_REMAINING" -le 0 ]; then
  echo '{"decision":"approve","reason":"goal budget exhausted; transitioning to failed (see /flow:goal inspect)"}'
  exit 0
fi

# Run deterministic checks.
REPORT=$("${PLUGIN_ROOT}/hooks/scripts/flow-run-deterministic-checks.sh" "${ACTIVE_GOAL}" 2>/dev/null || echo '{}')
GOAL_NAME=$(basename "${ACTIVE_GOAL}" .goal.yaml)
FAILING=$(echo "$REPORT"   | jq -r '.failing[]?'       2>/dev/null)
INCOMPLETE=$(echo "$REPORT" | jq -r '.incomplete_acs[]?' 2>/dev/null)
VIOLATIONS=$(echo "$REPORT" | jq -r '.path_violations[]?' 2>/dev/null)

# Deterministic gate: any must_pass FAIL with no recoverable path → BLOCK.
HAS_MUST_PASS_FAIL=$(echo "$REPORT" | jq -r '
  .checked[]? | select((.must_pass // true) == true and (.exit_code // 1) != 0) | .id
' 2>/dev/null | head -1)

if [ -n "$HAS_MUST_PASS_FAIL" ] || [ -n "$VIOLATIONS" ]; then
  # Compose continuation prompt. Iteration policy comes from the goal YAML.
  REASON=$(python3 - "$ACTIVE_GOAL" "$REPORT" <<'PYEOF' 2>/dev/null
import sys, json, yaml
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
goal_path, report_json = sys.argv[1:3]
with open(goal_path, "r", encoding="utf-8") as f:
    goal = yaml.safe_load(f) or {}
report = json.loads(report_json) if report_json else {}
parts = ["FLOW_GOAL_CONTINUATION", f"Goal: {goal.get('metadata', {}).get('id', '?')}"]
failing = report.get("failing") or []
if failing:
    parts.append(f"Failing must_pass criteria: {', '.join(failing)}")
violations = report.get("path_violations") or []
if violations:
    parts.append(f"Path boundary violations: {', '.join(violations[:5])}")
# Inject iteration policy from goal contract if present.
constraints = goal.get("constraints") or {}
if constraints.get("denied_paths"):
    parts.append(f"Denied paths: {', '.join(constraints['denied_paths'])}")
parts.append("Iteration policy: smallest change first; re-run narrowest validation; do not edit files outside allowed_paths.")
parts.append(f"Budget remaining: {sys.argv[3] if len(sys.argv) > 3 else '?'} turns.")
print("\n".join(parts))
PYEOF
)
  jq -nc --arg r "$REASON" '{decision:"block", reason:$r}'

  # Update throttle.
  echo "$((CONTINUE_COUNT + 1)):$NOW" > "$THROTTLE_FILE"
  exit 0
fi

# Deterministic all-pass AND no fuzzy criteria → achieved.
if [ -z "$INCOMPLETE" ] && [ -z "$FAILING" ]; then
  # Transition to achieved via the lifecycle skill (the lifecycle write
  # happens via /flow:goal evaluate; this hook just approves the stop with
  # a notice so the user can see the achievement on their next /flow:goal
  # status).
  echo '{"decision":"approve","reason":"goal evidence complete and all deterministic checks pass; run /flow:goal evaluate to finalize the achieved verdict"}'
  rm -f "$THROTTLE_FILE"
  exit 0
fi

# Hybrid path: deterministic OK but fuzzy criteria remain. Spawn judge.
EVAL_DIR="${HOME:-/tmp}/.claude/flow-goal-judge"
mkdir -p "$EVAL_DIR" 2>/dev/null || EVAL_DIR="/tmp"

PROMPT_FILE="${EVAL_DIR}/prompt-${SESSION_ID}-${NOW}.txt"
{
  echo "## Goal contract"
  cat "$ACTIVE_GOAL"
  echo
  echo "## Deterministic check report"
  printf '%s' "$REPORT"
  echo
  echo "## Recent transcript (last 4 messages, capped 32KB)"
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    tail -n 4 "$TRANSCRIPT" 2>/dev/null | jq -s '.' 2>/dev/null | head -c 32000
  else
    echo "(transcript unavailable)"
  fi
} > "$PROMPT_FILE"

# JSON schema for the judge's output (matches goal-evaluator-judge.md).
SCHEMA='{
  "type": "object",
  "required": ["verdict", "confidence", "delta", "next_step_hint", "reason"],
  "properties": {
    "verdict": {"enum": ["achieved", "not_achieved", "blocked", "needs_human_review"]},
    "confidence": {"type": "number", "minimum": 0, "maximum": 1},
    "delta": {"enum": ["made_progress", "unchanged", "regressed"]},
    "next_step_hint": {"type": "string"},
    "blocker_type": {"enum": ["missing_dep", "missing_approval", "ambiguous_requirement", "external_service", "scope_violation", "none"]},
    "criterion_results": {"type": "array"},
    "reason": {"type": "string"}
  }
}'

# Spawn the judge subprocess.
SYSTEM_PROMPT="You are flow goal-evaluator-judge. Output structured JSON only matching the provided schema. Apply the Independence Protocol — judge based on evidence in the goal contract and the deterministic report; do NOT read code files. Use 'blocked' only with a specific blocker_type."

RESP=$(cd "$EVAL_DIR" && CLAUDE_HOOK_GOAL_JUDGE_MODE=true timeout "$JUDGE_TIMEOUT" claude --print \
  --model "$JUDGE_MODEL" \
  --output-format json \
  --json-schema "$SCHEMA" \
  --system-prompt "$SYSTEM_PROMPT" \
  --disallowedTools '*' < "$PROMPT_FILE" 2>/dev/null) || RESP=""

# Parse verdict. Tolerate parse failures with a safe fallback.
VERDICT=$(echo "$RESP" | jq -r '.structured_output.verdict // "needs_human_review"' 2>/dev/null)
REASON_TXT=$(echo "$RESP" | jq -r '.structured_output.reason // "judge unavailable or output unparseable"' 2>/dev/null)
HINT=$(echo "$RESP" | jq -r '.structured_output.next_step_hint // ""' 2>/dev/null)

case "$VERDICT" in
  achieved)
    rm -f "$THROTTLE_FILE"
    echo '{"decision":"approve","reason":"judge verdict: achieved — run /flow:goal evaluate to finalize"}'
    ;;
  blocked|needs_human_review)
    rm -f "$THROTTLE_FILE"
    jq -nc --arg r "Goal $VERDICT: $REASON_TXT" '{decision:"approve", reason:$r}'
    ;;
  not_achieved|*)
    echo "$((CONTINUE_COUNT + 1)):$NOW" > "$THROTTLE_FILE"
    jq -nc --arg r "FLOW_GOAL_CONTINUATION ($VERDICT): $REASON_TXT. Next: $HINT" '{decision:"block", reason:$r}'
    ;;
esac
exit 0
