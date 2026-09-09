#!/bin/bash
# [flow] TaskCompleted hook: mechanical quality gate.
#
# A task cannot be marked complete while files changed in this session after
# the last PASSING quality-command run. The evidence is the per-session
# ledger written by log-file-changes.sh (file_change entries) and
# record-quality-run.sh (quality_run entries); bin/flow-quality-ledger.sh
# `status` folds it into clean/dirty. This gate runs in every session, with
# or without a FlowGoal.
#
# Mode (cascade key testing.taskCompletionGate, default block):
#   block — STATE=dirty: plain-sentence explanation on stderr, exit 2
#           (Claude Code refuses the completion and feeds stderr back).
#   warn  — same text prefixed "WARNING (stop allowed)", exit 0.
#   off   — exit 0 without evaluating.
#
# Silent exit 0 when: STATE is clean, empty (nothing recorded), or
# unavailable (python3 missing); jq is missing; the payload has no session_id
# (agent-team teammates report through their own session and are not gated
# on the leader's ledger); the helper cannot be reached.
#
# Payload (stdin JSON, Claude Code v2.1.33+): session_id, cwd, task_id,
# task_subject, task_description, teammate_name, team_name. Older payloads
# nested the task as .task.subject / .task.description; both shapes are read.
#
# Ignored paths (never dirty the gate): the decision journal directory
# (cascade key journal.dir, default .decisions), .flow/, .screenshots/ —
# each resolved against the payload cwd.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null || echo '{}')
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/../..}"
LEDGER_HELPER="${PLUGIN_ROOT}/bin/flow-quality-ledger.sh"
CASCADE="${PLUGIN_ROOT}/bin/cascade-resolve.sh"
[ -x "$LEDGER_HELPER" ] || exit 0

MODE="block"
JOURNAL_DIR=".decisions"
if [ -x "$CASCADE" ]; then
  MODE=$("$CASCADE" --default "block" '.testing.taskCompletionGate // empty' 2>/dev/null)
  JOURNAL_DIR=$("$CASCADE" --default ".decisions" '.journal.dir // empty' 2>/dev/null)
fi
case "$MODE" in
  off) exit 0 ;;
  warn) ;;
  block) ;;
  *) MODE="block" ;;   # unknown value: keep the safe default
esac
[ -n "$JOURNAL_DIR" ] || JOURNAL_DIR=".decisions"

TASK_SUBJECT=$(printf '%s' "$INPUT" | jq -r '.task_subject // .task.subject // empty' 2>/dev/null)
[ -n "$TASK_SUBJECT" ] || TASK_SUBJECT="(untitled)"

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] || CWD="$PWD"
_abs() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *) printf '%s' "${CWD%/}/$1" ;;
  esac
}

STATUS=$("$LEDGER_HELPER" status --session "$SESSION_ID" \
  --ignore-prefix "$(_abs "$JOURNAL_DIR")" \
  --ignore-prefix "$(_abs ".flow")" \
  --ignore-prefix "$(_abs ".screenshots")" 2>/dev/null) || exit 0

STATE=""
LAST_PASSING_RUN="none"
LAST_RUN_EXIT="none"
CHANGED_SINCE=0
CHANGED_FILES=()
while IFS= read -r line; do
  case "$line" in
    STATE=*) STATE="${line#STATE=}" ;;
    LAST_PASSING_RUN=*) LAST_PASSING_RUN="${line#LAST_PASSING_RUN=}" ;;
    LAST_RUN_EXIT=*) LAST_RUN_EXIT="${line#LAST_RUN_EXIT=}" ;;
    CHANGED_SINCE=*) CHANGED_SINCE="${line#CHANGED_SINCE=}" ;;
    CHANGED_FILE=*) CHANGED_FILES+=("${line#CHANGED_FILE=}") ;;
  esac
done <<<"$STATUS"

[ "$STATE" = "dirty" ] || exit 0

if [ "$LAST_PASSING_RUN" != "none" ]; then
  RUN_TEXT="last passing run at $LAST_PASSING_RUN"
elif [ "$LAST_RUN_EXIT" != "none" ]; then
  RUN_TEXT="the last quality run exited $LAST_RUN_EXIT; no passing run this session"
else
  RUN_TEXT="no quality command has run this session"
fi

CHANGED_TEXT=""
for f in "${CHANGED_FILES[@]+"${CHANGED_FILES[@]}"}"; do
  CHANGED_TEXT="${CHANGED_TEXT:+$CHANGED_TEXT, }$f"
done
if [ "$CHANGED_SINCE" -gt "${#CHANGED_FILES[@]}" ] 2>/dev/null; then
  CHANGED_TEXT="$CHANGED_TEXT, and $((CHANGED_SINCE - ${#CHANGED_FILES[@]})) more"
fi

MESSAGE="Task '$TASK_SUBJECT' cannot be completed: $CHANGED_SINCE file(s) changed since the last passing quality run ($RUN_TEXT). Changed: $CHANGED_TEXT. Run the project's test/lint command and complete the task once it passes. Set testing.taskCompletionGate to warn or off to change this."

if [ "$MODE" = "warn" ]; then
  echo "WARNING (stop allowed): $MESSAGE" >&2
  exit 0
fi
echo "$MESSAGE" >&2
exit 2
