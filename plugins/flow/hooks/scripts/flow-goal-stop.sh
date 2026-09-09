#!/usr/bin/env bash
# [flow] Stop hook: FlowGoal enforcement.
#
# Fires after every conversation turn. Three modes (read from cascade key
# flow.goals.stopHookEnforcement; default: warn):
#
#   warn (default)   — the stop is ALWAYS allowed. When the active goal lacks
#                      evidence the hook emits {"decision":"approve"} whose
#                      reason starts with "FLOW_GOAL_INCOMPLETE — stop ALLOWED
#                      (stopHookEnforcement=warn)" and prints the same text to
#                      stderr so the user sees it. Zero LLM cost.
#   block            — same deterministic check, but emits {"decision":"block"}
#                      so the reason is injected as the next-turn prompt and the
#                      agent keeps working. Blocks on failing ACs, path
#                      violations, and ACs with no verification_command.
#                      Verification commands execute only when the goal is
#                      trusted (bin/flow-goal-trust.sh) or
#                      flow.goals.executeVerificationCommands is true; an
#                      untrusted goal's not-executed ACs are reported but never
#                      block on their own (that would be a permanent block).
#                      Consecutive blocks for one (session, goal) are capped at
#                      flow.goals.failAfterStuckTurns (default 3): once the cap
#                      is reached the stop is approved with FLOW_GOAL_BLOCK_CAP.
#   evaluator-loop   — delegate to flow-goal-evaluator.sh which spawns a
#                      Haiku subprocess to judge progress. Opt-in; ~$0.001/turn.
#
# The Stop hook is NOT a full reasoning engine. It checks file-backed state
# and emits structured JSON. The active reasoning happens in /flow:goal
# evaluate (manual) or in flow-goal-evaluator.sh (opt-in evaluator-loop).
#
# Stop hook input (stdin JSON): session_id, transcript_path, stop_hook_active,
# cwd. session_id keys the block counter; stop_hook_active (true when a Stop
# hook already blocked this turn) tells the counter whether a block is
# consecutive.
#
# Block counter state: ${FLOW_STATE_DIR:-$HOME/.claude/flow-state}/sessions/
# <session_id>/stop-blocks.json — {"goal_id","count","updated_at"}.

set -uo pipefail
export PYTHONSAFEPATH=1

# Graceful degradation. Without these tools, we can't safely evaluate the
# state — exit 0 with a no-op decision so the stop completes normally. Emit
# a one-line stderr notice on first miss per session so users aren't blind to
# the degradation (silent skip masks misconfigured environments).
_flow_warned_once() {
  local sentinel="${HOME}/.claude/flow-degraded-${1}"
  [ -e "$sentinel" ] && return 0
  mkdir -p "$(dirname "$sentinel")" 2>/dev/null && : > "$sentinel" 2>/dev/null
  return 1
}
command -v jq      >/dev/null 2>&1 || { _flow_warned_once jq      || echo "flow: jq unavailable — FlowGoal enforcement disabled" >&2; echo '{"decision":"approve","reason":"jq unavailable"}'; exit 0; }
command -v python3 >/dev/null 2>&1 || { _flow_warned_once python3 || echo "flow: python3 unavailable — FlowGoal enforcement disabled" >&2; echo '{"decision":"approve","reason":"python3 unavailable"}'; exit 0; }
python3 -c "import yaml" >/dev/null 2>&1 || { _flow_warned_once pyyaml || echo "flow: PyYAML unavailable (pip install pyyaml) — FlowGoal enforcement disabled" >&2; echo '{"decision":"approve","reason":"PyYAML unavailable"}'; exit 0; }

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
STOP_ACTIVE=$(echo "$EVENT" | jq -r '.stop_hook_active // false' 2>/dev/null)
SESSION_ID=$(echo "$EVENT" | jq -r '.session_id // "unknown"' 2>/dev/null)
# Sanitize SESSION_ID before it becomes a path segment: [A-Za-z0-9_-], max 64.
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9_-' | head -c 64)
[ -z "$SESSION_ID" ] && SESSION_ID="anon"

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

GOAL_NAME=$(basename "${ACTIVE_GOAL}" .goal.yaml)

# ---------------------------------------------------------------------------
# Consecutive-block counter (block mode only). One file per session; the
# goal id is stored inside so a goal switch resets the count.
STATE_DIR="${FLOW_STATE_DIR:-${HOME}/.claude/flow-state}"
BLOCKS_DIR="${STATE_DIR}/sessions/${SESSION_ID}"
BLOCKS_FILE="${BLOCKS_DIR}/stop-blocks.json"

# Prints the count recorded for the active goal (0 when absent, malformed,
# a symlink, or recorded for another goal).
_read_block_count() {
  local count
  if [ -L "$BLOCKS_FILE" ] || [ ! -f "$BLOCKS_FILE" ]; then
    echo 0
    return
  fi
  count=$(jq -r --arg g "$GOAL_NAME" 'if .goal_id == $g then (.count // 0) else 0 end' "$BLOCKS_FILE" 2>/dev/null)
  case "$count" in ''|*[!0-9]*) count=0 ;; esac
  echo "$count"
}

# Writes the count for the active goal. Best-effort: a failed write leaves
# the previous count in place, which only means the cap fires later.
_write_block_count() {
  local count="$1" tmp
  if [ -L "$BLOCKS_FILE" ]; then
    echo "flow-goal-stop: refusing — $BLOCKS_FILE is a symlink (block counter not updated)" >&2
    return
  fi
  mkdir -p "$BLOCKS_DIR" 2>/dev/null && chmod 0700 "$STATE_DIR" "$BLOCKS_DIR" 2>/dev/null
  tmp=$(mktemp "${BLOCKS_DIR}/.stop-blocks.XXXXXX" 2>/dev/null) || return
  if jq -nc --arg g "$GOAL_NAME" --argjson c "$count" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '{goal_id:$g, count:$c, updated_at:$t}' > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$BLOCKS_FILE" 2>/dev/null || rm -f "$tmp"
  else
    rm -f "$tmp"
  fi
}

# ---------------------------------------------------------------------------
# Deterministic report. Shared by warn, block, and the unknown-mode fallback.
_run_report() {
  REPORT=$("${PLUGIN_ROOT}/hooks/scripts/flow-run-deterministic-checks.sh" "${ACTIVE_GOAL}" 2>/dev/null || echo '{}')
  INCOMPLETE=$(echo "$REPORT" | jq -r '.incomplete_acs[]?' 2>/dev/null | head -5)
  FAILING=$(echo "$REPORT"    | jq -r '.failing[]?'        2>/dev/null | head -5)
  PATH_VIOLATIONS=$(echo "$REPORT" | jq -r '.path_violations[]?' 2>/dev/null | head -5)
  NOT_EXECUTED_COUNT=$(echo "$REPORT" | jq -r '.not_executed | length' 2>/dev/null)
  case "$NOT_EXECUTED_COUNT" in ''|*[!0-9]*) NOT_EXECUTED_COUNT=0 ;; esac
  # Incomplete ACs that are NOT merely "not executed": no verification_command
  # at all, or the command could not be launched. These block in block mode.
  BLOCKING_INCOMPLETE=$(echo "$REPORT" | jq -r '(.not_executed // []) as $ne | .incomplete_acs[]? | select(. as $id | $ne | index($id) | not)' 2>/dev/null | head -5)
  TRUSTED=$(echo "$REPORT" | jq -r '.trusted // false' 2>/dev/null)
}

# Composes the multi-line reason. Every attacker-influenceable value
# (GOAL_NAME from the filename, AC ids from the goal YAML, filenames from
# `git diff --name-only`) is passed via argv — NEVER interpolated into the
# Python source — so quote characters in an AC id cannot inject code.
#   $1 header line, $2 incomplete ids, $3 failing ids, $4 path violations,
#   $5 not-executed count, $6 trusted (true|false), $7 trailing sentence
_compose_reason() {
  python3 - "$GOAL_NAME" "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$ACTIVE_GOAL" "$PLUGIN_ROOT" <<'PYEOF'
import sys
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
goal_name, header, inc, fail, viol, ne_count, trusted, trailer, goal_path, plugin_root = sys.argv[1:11]
inc, fail, viol = inc.strip(), fail.strip(), viol.strip()
parts = [header, f'Active goal: {goal_name}']
if inc:
    parts.append('Missing evidence for: ' + ', '.join(inc.split()))
if fail:
    parts.append('Failing acceptance criteria: ' + ', '.join(fail.split()))
if viol:
    parts.append('Path-boundary violations: ' + ', '.join(viol.splitlines()))
if ne_count.isdigit() and int(ne_count) > 0 and trusted != 'true':
    parts.append(
        f'{ne_count} acceptance criteria not executed because goal {goal_name} is not trusted '
        f'(flow.goals.executeVerificationCommands is false). To trust it: '
        f'{plugin_root}/bin/flow-goal-trust.sh record --goal-file {goal_path}'
    )
parts.append(f'Next action: /flow:goal evaluate {goal_name}')
if trailer:
    parts.append(trailer)
print('\n'.join(parts))
PYEOF
}

ENFORCE_HINT='To enforce, set flow.goals.stopHookEnforcement to block.'

# Warn-mode body, parameterised by the header so the unknown-mode fallback
# can reuse it. The stop is always allowed; the text goes to stdout JSON
# AND stderr (the JSON reason alone never reaches the user's terminal).
_warn_mode() {
  local header="$1"
  _run_report
  if [ -n "${INCOMPLETE}" ] || [ -n "${FAILING}" ] || [ -n "${PATH_VIOLATIONS}" ]; then
    REASON=$(_compose_reason "$header" "$INCOMPLETE" "$FAILING" "$PATH_VIOLATIONS" "$NOT_EXECUTED_COUNT" "$TRUSTED" "$ENFORCE_HINT")
    printf '%s\n' "$REASON" >&2
    jq -nc --arg r "$REASON" '{decision:"approve", reason:$r}'
  else
    echo '{"decision":"approve","reason":"goal evidence complete; ready for /flow:goal evaluate"}'
  fi
}

case "${MODE}" in
  warn)
    _warn_mode 'FLOW_GOAL_INCOMPLETE — stop ALLOWED (stopHookEnforcement=warn)'
    exit 0
    ;;
  block)
    _run_report
    CAP=$("${PLUGIN_ROOT}/bin/cascade-resolve.sh" --default "3" '.flow.goals.failAfterStuckTurns // empty' 2>/dev/null)
    case "$CAP" in ''|*[!0-9]*|0) CAP=3 ;; esac

    if [ -n "${FAILING}" ] || [ -n "${PATH_VIOLATIONS}" ] || [ -n "${BLOCKING_INCOMPLETE}" ]; then
      # A block is consecutive only when Claude Code tells us a Stop hook
      # already blocked this turn; otherwise the chain restarts at zero.
      PRIOR=0
      [ "$STOP_ACTIVE" = "true" ] && PRIOR=$(_read_block_count)
      if [ "$PRIOR" -ge "$CAP" ]; then
        REASON="FLOW_GOAL_BLOCK_CAP — stop ALLOWED after ${PRIOR} consecutive blocks; run /flow:goal evaluate ${GOAL_NAME}"
        printf '%s\n' "$REASON" >&2
        _write_block_count 0
        jq -nc --arg r "$REASON" '{decision:"approve", reason:$r}'
        exit 0
      fi
      COUNT=$((PRIOR + 1))
      REASON=$(_compose_reason "FLOW_GOAL_INCOMPLETE — stop BLOCKED (stopHookEnforcement=block; block ${COUNT} of ${CAP})" \
        "$BLOCKING_INCOMPLETE" "$FAILING" "$PATH_VIOLATIONS" "$NOT_EXECUTED_COUNT" "$TRUSTED" "")
      printf '%s\n' "$REASON" >&2
      _write_block_count "$COUNT"
      jq -nc --arg r "$REASON" '{decision:"block", reason:$r}'
      exit 0
    fi

    # Nothing blockable. Any approve breaks the consecutive chain.
    _write_block_count 0
    if [ "$NOT_EXECUTED_COUNT" -gt 0 ]; then
      REASON=$(_compose_reason "FLOW_GOAL_UNVERIFIED — stop ALLOWED (stopHookEnforcement=block; untrusted goal, verification commands not executed)" \
        "" "" "" "$NOT_EXECUTED_COUNT" "$TRUSTED" "")
      printf '%s\n' "$REASON" >&2
      jq -nc --arg r "$REASON" '{decision:"approve", reason:$r}'
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
    # Invoke without `exec` inside the pipe — `exec` on the right side of a
    # pipe runs in a subshell and is a no-op; if the evaluator fails to start
    # or crashes before emitting JSON, capture the failure and emit a safe
    # approve with a diagnostic reason rather than silently exiting empty.
    EVAL_OUTPUT=$(printf '%s' "$EVENT" | "${PLUGIN_ROOT}/hooks/scripts/flow-goal-evaluator.sh" 2>&1)
    EVAL_RC=$?
    if [ $EVAL_RC -ne 0 ] || [ -z "$EVAL_OUTPUT" ]; then
      jq -nc --arg r "evaluator-loop hook failed (rc=$EVAL_RC): $EVAL_OUTPUT" '{decision:"approve",reason:$r}'
      exit 0
    fi
    printf '%s' "$EVAL_OUTPUT"
    exit 0
    ;;
  *)
    # Fail-loud-but-not-fatal: emit stderr diagnostic AND fall through to
    # warn mode so a single-character typo in settings doesn't silently
    # disable enforcement. The header keeps the FLOW_GOAL_CONFIG_FALLBACK_WARN
    # marker and is as honest as warn mode: the stop is allowed.
    echo "flow-goal-stop: unknown stopHookEnforcement value '${MODE}' — valid: warn|block|evaluator-loop. Falling back to 'warn' mode." >&2
    _warn_mode 'FLOW_GOAL_INCOMPLETE — stop ALLOWED (stopHookEnforcement=warn; FLOW_GOAL_CONFIG_FALLBACK_WARN: unknown value treated as warn)'
    exit 0
    ;;
esac
