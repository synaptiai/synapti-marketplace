#!/bin/bash
# [flow] SessionEnd hook: Flag pending learning analysis
# Lightweight — only marks pending, does NOT run full analysis (too slow for session end).
#
# Two signals set the flag:
#   1. Journal activity — a `.decisions/*.md` modified in the last 24 hours.
#      Detected by file mtime rather than grepping for today's date string.
#      The previous grep approach false-matched dates that appeared inside
#      journal *content* (e.g. due-date references in older entries) rather
#      than only matching entries actually written today. `find -mtime -1` is
#      portable across BSD (macOS) and GNU find.
#   2. Transcript corrections — the session that just ended contains at least
#      one candidate user correction per bin/flow-mine-corrections.sh (only
#      when learning.sources includes "transcripts"). The transcript is the
#      one named by the SessionEnd payload's transcript_path; when that is
#      absent, the miner falls back to the newest transcript in the project's
#      ~/.claude/projects/<slug>/ dir.
#
# SessionEnd hooks have a ~1.5 s budget. The transcript scan is capped with
# `timeout 1` when coreutils timeout is available and is skipped silently on
# timeout or any error — this hook never blocks session end.

set -euo pipefail
export PYTHONSAFEPATH=1

# Graceful: if jq unavailable, skip learning
command -v jq &>/dev/null || exit 0

# Read the SessionEnd payload (JSON on stdin). transcript_path is the only
# field consumed; reading the whole payload also prevents SIGPIPE on the
# writer side.
INPUT=$(cat)
: "${INPUT:=}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/../..}"

# Determine journal directory + learning.* via bin/cascade-resolve.sh.
# Gracefully fall back to defaults when the helper is unreachable.
HELPER="${PLUGIN_ROOT}/bin/cascade-resolve.sh"
MINER="${PLUGIN_ROOT}/bin/flow-mine-corrections.sh"
JOURNAL_DIR=".decisions"
LEARNING_ENABLED="true"
LEARN_SOURCES='["journal","transcripts"]'
TRANSCRIPT_DIR_SETTING=""
if [ -x "$HELPER" ]; then
  JOURNAL_DIR=$("$HELPER" --default ".decisions" '.journal.dir // empty' 2>/dev/null)
  LEARNING_ENABLED=$("$HELPER" --default "true" '.learning.enabled // empty' 2>/dev/null)
  LEARN_SOURCES=$("$HELPER" --compact --default '["journal","transcripts"]' '.learning.sources // empty' 2>/dev/null)
  TRANSCRIPT_DIR_SETTING=$("$HELPER" --default "" '.learning.transcriptDir // empty' 2>/dev/null)
fi

[ "$LEARNING_ENABLED" != "true" ] && exit 0

PENDING=0

# Signal 1: journal activity. Using mtime rather than content-grep avoids
# false positives on dates appearing in journal *content* (due-date
# references, links, etc.) and avoids false negatives on entries written
# without a date header.
if [ -d "$JOURNAL_DIR" ] && [ -n "$(find "$JOURNAL_DIR" -maxdepth 1 -name '*.md' -mtime -1 -print -quit 2>/dev/null)" ]; then
  PENDING=1
fi

# Signal 2: the ended session's transcript contains a candidate correction.
_transcripts_enabled() {
  printf '%s' "$LEARN_SOURCES" | jq -e 'type == "array" and any(.[]; . == "transcripts")' >/dev/null 2>&1
}
_run_miner() {
  # `timeout 1` keeps the scan inside the SessionEnd budget; exit 124 (timed
  # out) and any other failure collapse to "no candidate" via the caller's
  # `|| true`. `head -c 1` stops at the first emitted candidate.
  if command -v timeout >/dev/null 2>&1; then
    timeout 1 "$MINER" "$@" 2>/dev/null
  else
    "$MINER" "$@" 2>/dev/null
  fi
}
if [ "$PENDING" = "0" ] && [ -x "$MINER" ] && _transcripts_enabled; then
  TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
  TRANSCRIPT_DIR_SETTING="${TRANSCRIPT_DIR_SETTING/#\~/$HOME}"
  FOUND=""
  if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    FOUND=$(_run_miner --format jsonl --max-sessions 1 --file "$TRANSCRIPT_PATH" | head -c 1 || true)
  elif [ -n "$TRANSCRIPT_DIR_SETTING" ]; then
    FOUND=$(_run_miner --format jsonl --max-sessions 1 --transcript-dir "$TRANSCRIPT_DIR_SETTING" | head -c 1 || true)
  else
    FOUND=$(_run_miner --format jsonl --max-sessions 1 | head -c 1 || true)
  fi
  [ -n "$FOUND" ] && PENDING=1
fi

if [ "$PENDING" = "1" ]; then
  PENDING_DIR="${HOME}/.claude"
  mkdir -p "$PENDING_DIR"
  date +%Y-%m-%d > "$PENDING_DIR/flow-learn-pending"
fi

exit 0
