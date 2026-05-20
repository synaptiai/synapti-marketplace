#!/usr/bin/env bash
# [flow] Stop hook: FlowGoal enforcement.
#
# Fires after every conversation turn. Three modes (read from cascade key
# flow.goals.stopHookEnforcement; default: warn):
#
#   warn (default)   — emit JSON {"decision":"approve","reason":"..."} with a
#                      FLOW_GOAL_INCOMPLETE warning when the active goal lacks
#                      evidence. Zero LLM cost; deterministic.
#   block            — same check, but emit {"decision":"block"} so the warning
#                      is injected as the next-turn user prompt. Stricter UX —
#                      blocks every stop until evidence is captured.
#   evaluator-loop   — delegate to flow-goal-evaluator.sh which spawns a
#                      Haiku subprocess to judge progress. Opt-in; ~$0.001/turn.
#
# The Stop hook is NOT a full reasoning engine. It checks file-backed state
# and emits structured JSON. The active reasoning happens in /flow:goal
# evaluate (manual) or in flow-goal-evaluator.sh (opt-in evaluator-loop).
#
# Stop hook input (stdin JSON): session_id, transcript_path, stop_hook_active,
# cwd. We use session_id and transcript_path; the rest informs throttling
# in the active-mode variant.

set -uo pipefail
export PYTHONSAFEPATH=1

# Graceful degradation. Without these tools, we can't safely evaluate the
# state — exit 0 with a no-op decision so the stop completes normally.
command -v jq      >/dev/null 2>&1 || { echo '{"decision":"approve","reason":"jq unavailable"}'; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo '{"decision":"approve","reason":"python3 unavailable"}'; exit 0; }
python3 -c "import yaml" >/dev/null 2>&1 || { echo '{"decision":"approve","reason":"PyYAML unavailable"}'; exit 0; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/../..}"

# Recursion guard — short-circuit when this hook fires inside the
# evaluator-loop's judge subprocess. The active-mode script sets this env
# var before invoking `claude --print`; without this guard we'd fork-bomb
# (judge → its Stop hook → judge → ...).
if [ "${CLAUDE_HOOK_GOAL_JUDGE_MODE:-}" = "true" ]; then
  echo '{"decision":"approve","reason":"judge mode"}'
  exit 0
fi

# Resolve mode from settings cascade.
MODE=$("${PLUGIN_ROOT}/bin/cascade-resolve.sh" --default "warn" '.flow.goals.stopHookEnforcement // empty' 2>/dev/null)
[ -z "$MODE" ] && MODE="warn"

# Read Stop event payload. We tolerate missing fields — the hook fires in
# many shapes (compact replays, harness tests, etc.).
EVENT=$(cat 2>/dev/null || echo '{}')
TRANSCRIPT=$(echo "$EVENT" | jq -r '.transcript_path // ""')
STOP_ACTIVE=$(echo "$EVENT" | jq -r '.stop_hook_active // false')
SESSION_ID=$(echo "$EVENT" | jq -r '.session_id // "unknown"')

# Find the active goal (lifecycle.status == active) for the current repo
# state. We iterate over .flow/goals/*.goal.yaml and take the first match.
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

# Fast-path: no .flow/goals or no active goal — be silent.
if [ -z "${ACTIVE_GOAL}" ]; then
  echo '{"decision":"approve","reason":"no active flow goal"}'
  exit 0
fi

case "${MODE}" in
  warn|block)
    # Deterministic checks only — no LLM call.
    REPORT=$("${PLUGIN_ROOT}/hooks/scripts/flow-run-deterministic-checks.sh" "${ACTIVE_GOAL}" 2>/dev/null || echo '{}')
    GOAL_NAME=$(basename "${ACTIVE_GOAL}" .goal.yaml)

    # Extract structured fields from the report.
    INCOMPLETE=$(echo "$REPORT" | jq -r '.incomplete_acs[]?' 2>/dev/null | head -5)
    FAILING=$(echo "$REPORT"   | jq -r '.failing[]?'       2>/dev/null | head -5)
    PATH_VIOLATIONS=$(echo "$REPORT" | jq -r '.path_violations[]?' 2>/dev/null | head -5)

    if [ -n "${INCOMPLETE}" ] || [ -n "${FAILING}" ] || [ -n "${PATH_VIOLATIONS}" ]; then
      # Compose a multi-line warning. The format is intentionally similar
      # to the existing flow stderr patterns (FLOW_REVIEW_CYCLE markers etc.)
      # so users recognize it as flow-emitted.
      REASON=$(python3 -c "
import sys
parts = ['FLOW_GOAL_INCOMPLETE']
parts.append('Active goal: ${GOAL_NAME}')
inc = '''${INCOMPLETE}'''.strip()
fail = '''${FAILING}'''.strip()
viol = '''${PATH_VIOLATIONS}'''.strip()
if inc:
    parts.append('Missing evidence for: ' + ', '.join(inc.split()))
if fail:
    parts.append('Failing acceptance criteria: ' + ', '.join(fail.split()))
if viol:
    parts.append('Path-boundary violations: ' + ', '.join(viol.splitlines()))
parts.append('Next action: /flow:goal evaluate ${GOAL_NAME}')
print('\\n'.join(parts))
")
      DECISION="approve"
      [ "$MODE" = "block" ] && DECISION="block"
      jq -nc --arg r "$REASON" --arg d "$DECISION" '{decision:$d, reason:$r}'
    else
      echo '{"decision":"approve","reason":"goal evidence complete; ready for /flow:goal evaluate"}'
    fi
    exit 0
    ;;
  evaluator-loop)
    # Delegate to the active-mode script. It owns recursion guarding,
    # throttling, budget enforcement, and judge subprocess invocation.
    if [ ! -x "${PLUGIN_ROOT}/hooks/scripts/flow-goal-evaluator.sh" ]; then
      echo '{"decision":"approve","reason":"evaluator-loop mode requested but flow-goal-evaluator.sh is not executable"}'
      exit 0
    fi
    # Pass the original stdin event by piping the captured EVENT back in.
    printf '%s' "$EVENT" | exec "${PLUGIN_ROOT}/hooks/scripts/flow-goal-evaluator.sh"
    ;;
  *)
    echo "{\"decision\":\"approve\",\"reason\":\"unknown stopHookEnforcement value: ${MODE}\"}"
    exit 0
    ;;
esac
