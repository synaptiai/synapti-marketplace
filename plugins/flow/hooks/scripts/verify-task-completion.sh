#!/bin/bash
# [flow] TaskCompleted hook: mechanical quality gate.
#
# A task cannot be marked complete while files changed in this session after
# the last PASSING quality-command run. The evidence is the per-session
# ledger written by log-file-changes.sh (file_change entries, PostToolUse
# Edit|Write|NotebookEdit) and record-quality-run.sh (quality_run entries,
# PostToolUse and PostToolUseFailure Bash); bin/flow-quality-ledger.sh
# `status` folds it into clean/dirty. This gate runs in every session, with
# or without a FlowGoal.
#
# "Passing" means exit_code 0, not masked (`|| true`), not failed (recorded
# from PostToolUseFailure), and no output_check (System One, switched on,
# found that no test ran or every test was skipped). Two signals make the ledger dirty:
#   1. a file_change entry after the last passing run (Edit/Write/NotebookEdit);
#   2. the working tree digest differs from the one that run recorded — the
#      helper recomputes `digest` for the payload cwd (passed as --cwd), so
#      edits made through Bash (sed -i, heredocs, git apply, mv) and
#      checkouts that change contents are caught even though no file-tool
#      hook saw them. The digest hashes contents, not HEAD, so committing
#      the edits a passing run already tested does not dirty the gate.
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
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH

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
fi
case "$MODE" in
  off) exit 0 ;;
  warn) ;;
  block) ;;
  *) MODE="block" ;;   # unknown value: keep the safe default
esac
# The journal directory as every journal writer resolves it.
if [ -x "${PLUGIN_ROOT}/bin/journal-dir.sh" ]; then
  JOURNAL_DIR=$("${PLUGIN_ROOT}/bin/journal-dir.sh" 2>/dev/null)
fi
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

STATUS=$("$LEDGER_HELPER" status --session "$SESSION_ID" --cwd "$CWD" \
  --ignore-prefix "$(_abs "$JOURNAL_DIR")" \
  --ignore-prefix "$(_abs ".flow")" \
  --ignore-prefix "$(_abs ".screenshots")" 2>/dev/null) || exit 0

STATE=""
LAST_PASSING_RUN="none"
LAST_RUN_EXIT="none"
LAST_RUN_MASKED="false"
LAST_RUN_FAILED="false"
LAST_RUN_OUTPUT_CHECK=""
WORKTREE="unknown"
CHANGED_SINCE=0
CHANGED_FILES=()
while IFS= read -r line; do
  case "$line" in
    STATE=*) STATE="${line#STATE=}" ;;
    LAST_PASSING_RUN=*) LAST_PASSING_RUN="${line#LAST_PASSING_RUN=}" ;;
    LAST_RUN_EXIT=*) LAST_RUN_EXIT="${line#LAST_RUN_EXIT=}" ;;
    LAST_RUN_MASKED=*) LAST_RUN_MASKED="${line#LAST_RUN_MASKED=}" ;;
    LAST_RUN_FAILED=*) LAST_RUN_FAILED="${line#LAST_RUN_FAILED=}" ;;
    LAST_RUN_OUTPUT_CHECK=*) LAST_RUN_OUTPUT_CHECK="${line#LAST_RUN_OUTPUT_CHECK=}" ;;
    WORKTREE=*) WORKTREE="${line#WORKTREE=}" ;;
    CHANGED_SINCE=*) CHANGED_SINCE="${line#CHANGED_SINCE=}" ;;
    CHANGED_FILE=*) CHANGED_FILES+=("${line#CHANGED_FILE=}") ;;
  esac
done <<<"$STATUS"

[ "$STATE" = "dirty" ] || exit 0

# Why the most recent quality run did not pass, or empty when it passed or
# there is none. Said whether or not an earlier run passed, so a re-run that
# keeps failing the same way is told why.
LAST_RUN_REASON=""
if [ "$LAST_RUN_MASKED" = "true" ] && [ "$LAST_RUN_EXIT" = "null" ]; then
  LAST_RUN_REASON="the last quality run's exit code was masked (|| true)"
elif [ "$LAST_RUN_MASKED" = "true" ]; then
  LAST_RUN_REASON="the last quality run exited $LAST_RUN_EXIT but its exit code was masked (|| true)"
elif [ "$LAST_RUN_FAILED" = "true" ]; then
  LAST_RUN_REASON="the last quality run failed (tool error, exit $LAST_RUN_EXIT)"
elif [ "$LAST_RUN_OUTPUT_CHECK" = "none_ran" ]; then
  LAST_RUN_REASON="the last quality run exited $LAST_RUN_EXIT but its output showed no tests ran"
elif [ "$LAST_RUN_OUTPUT_CHECK" = "all_skipped" ]; then
  LAST_RUN_REASON="the last quality run exited $LAST_RUN_EXIT but its output showed every test was skipped"
elif [ "$LAST_RUN_EXIT" = "null" ]; then
  LAST_RUN_REASON="the last quality run's exit code is not known: it timed out, ran in the background, or its command had a shape whose status need not be the test command's. A test command counts only when it runs in the foreground, finishes, and runs on its own, after nothing but cd <dir> &&, variable assignments or a leading set line; the prefixes env, time, nice and timeout, a pipe, a chain, a subshell or substitution, a heredoc, or a background & leave the exit code unknown"
elif [ "$LAST_RUN_EXIT" != "none" ] && [ "$LAST_RUN_EXIT" != "0" ]; then
  LAST_RUN_REASON="the last quality run exited $LAST_RUN_EXIT"
fi

if [ "$LAST_PASSING_RUN" != "none" ]; then
  RUN_TEXT="last passing run at $LAST_PASSING_RUN"
  [ -z "$LAST_RUN_REASON" ] || RUN_TEXT="$RUN_TEXT; since then, $LAST_RUN_REASON"
elif [ -n "$LAST_RUN_REASON" ]; then
  RUN_TEXT="$LAST_RUN_REASON; no passing run this session"
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

if [ "$CHANGED_SINCE" -eq 0 ] 2>/dev/null && [ "$WORKTREE" = "changed" ]; then
  # Digest moved but git status lists nothing outside the ignore prefixes:
  # edits made after the run were committed, or a checkout, reset, or stash
  # replaced the tested contents.
  MESSAGE="Task '$TASK_SUBJECT' cannot be completed: the working tree contents differ from what the last passing quality run tested ($RUN_TEXT) — edits committed after that run, a checkout, a reset, a stash, or an edit made outside the Edit tool. Run the project's test/lint command and complete the task once it passes. Set testing.taskCompletionGate to warn or off to change this."
else
  MESSAGE="Task '$TASK_SUBJECT' cannot be completed: $CHANGED_SINCE file(s) changed since the last passing quality run ($RUN_TEXT). Changed: $CHANGED_TEXT. Run the project's test/lint command and complete the task once it passes. Set testing.taskCompletionGate to warn or off to change this."
fi

if [ "$MODE" = "warn" ]; then
  echo "WARNING (stop allowed): $MESSAGE" >&2
  exit 0
fi
echo "$MESSAGE" >&2
exit 2
