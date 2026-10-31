#!/usr/bin/env bash
# [flow] SessionStart hook: set up the run-time tier check for the session's
# Bash commands.
#
# Claude Code runs the file named by CLAUDE_ENV_FILE as shell code before each
# Bash command of the session. This hook adds lines to it that
#
#   - put flow's hooks/shims directory first on PATH, so that a git or gh the
#     command runs by name starts in flow's wrapper (lib/tier-runtime.sh)
#     with the arguments the program gets;
#   - set FLOW_TIER_DIR to this session's directory under flow's state
#     directory (cascade-resolve.sh --state-dir), sessions/<id>/tier;
#   - move the record tier-gate.sh wrote for this Bash call (a directory
#     FLOW_TIER_DIR/pending.*: the actions it asked about, and so the person
#     approved, and the ones it journaled) to call.<pid>, named by
#     FLOW_TIER_CALL, so no other call can use it. The record is this call's
#     when the command it holds, as Claude Code passes it (inside `eval
#     '...'`, each ' written '"'"'), followed by the closing quote and a space
#     or the end, is in the text the shell was started with
#     (ZSH_EXECUTION_STRING or BASH_EXECUTION_STRING), right after `eval '`.
#     Both texts are compared with every `rtk ` removed: the rtk hook puts
#     it in front of each command it rewrites. Another hook that rewrites the
#     command makes its approved merges, releases and tag pushes refused when
#     they run. Two calls that run at the same time each take
#     their own; the record of a call the person refused stays unused, and
#     tier-gate.sh removes it after a day. If Claude Code passed the command
#     some other way, no record would be taken, and a merge, release or tag
#     push would be refused when it runs even after the person approved it.
#
# Exit 0 always; nothing on stdout. Without CLAUDE_ENV_FILE (an older Claude
# Code, or PowerShell, which reads only variable assignments from that file),
# jq, a session id, or a state directory, it sets nothing up, and the text
# check in tier-gate.sh is the only one.
set -u
unset CDPATH

INPUT=$(cat 2>/dev/null) || INPUT=""
[ -n "${CLAUDE_ENV_FILE:-}" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
case "$SID" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/../..}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

_ts_note() { printf 'flow: tier check — %s\n' "$1" >&2; }

STATE=$("${BASH:-bash}" "$PLUGIN_ROOT/bin/cascade-resolve.sh" --state-dir 2>/dev/null) || STATE=""
[ -n "$STATE" ] || { _ts_note "no state directory; the run-time check is off for this session"; exit 0; }
DIR="$STATE/sessions/$SID/tier"
if [ -L "$DIR" ] || ! mkdir -p "$DIR" 2>/dev/null; then
  _ts_note "could not create $DIR; the run-time check is off for this session"
  exit 0
fi
chmod 700 "$DIR" 2>/dev/null
# Records of calls that ended long ago.
find "$DIR" -maxdepth 1 \( -name 'call.*' -o -name 'pending.*' \) -mtime +0 -exec rm -r {} + 2>/dev/null

SHIMS=$(cd "$PLUGIN_ROOT/hooks/shims" 2>/dev/null && pwd -P) || SHIMS=""
[ -n "$SHIMS" ] && [ -x "$SHIMS/git" ] && [ -x "$SHIMS/gh" ] || {
  _ts_note "the wrappers in hooks/shims are missing; the run-time check is off for this session"
  exit 0
}
# The lines below quote both paths in single quotes.
case "$SHIMS$DIR" in
  *"'"*|*$'\n'*|*:*)
    _ts_note "a path holds a quote, a line end or a colon; the run-time check is off for this session"
    exit 0 ;;
esac

MARK="# flow tier check: $DIR"
# A session that starts again (resume, clear, compact) keeps one copy.
grep -qxF "$MARK" "$CLAUDE_ENV_FILE" 2>/dev/null && exit 0
{
  printf '%s\n' "$MARK"
  printf "case \":\$PATH:\" in *':%s:'*) ;; *) PATH='%s':\"\$PATH\"; export PATH ;; esac\n" "$SHIMS" "$SHIMS"
  printf "FLOW_TIER_DIR='%s'; export FLOW_TIER_DIR\n" "$DIR"
  printf '%s\n' 'unset FLOW_TIER_CALL'
  # No glob: zsh stops the command on a pattern that matches nothing.
  cat <<'LINES'
_ftc_x="${ZSH_EXECUTION_STRING:-${BASH_EXECUTION_STRING:-}}"; _ftc_x=${_ftc_x//rtk /}
if [ -n "$_ftc_x" ]; then for _ftc_n in $(command ls "$FLOW_TIER_DIR" 2>/dev/null); do case "$_ftc_n" in pending.*) _ftc_c=$(cat "$FLOW_TIER_DIR/$_ftc_n/cmdq" 2>/dev/null; printf x); _ftc_c=${_ftc_c%x}; if [ -n "$_ftc_c" ]; then case "$_ftc_x" in *"eval '$_ftc_c' "*|*"eval '$_ftc_c'") _ftc_d="$FLOW_TIER_DIR/call.${_ftc_n#pending.}.$$"; if [ ! -e "$_ftc_d" ] && mv "$FLOW_TIER_DIR/$_ftc_n" "$_ftc_d" 2>/dev/null; then FLOW_TIER_CALL=$_ftc_d; export FLOW_TIER_CALL; break; fi ;; esac; fi ;; esac; done; fi
unset _ftc_x _ftc_n _ftc_c _ftc_d
LINES
} >> "$CLAUDE_ENV_FILE" 2>/dev/null || _ts_note "could not write to CLAUDE_ENV_FILE; the run-time check is off for this session"
exit 0
