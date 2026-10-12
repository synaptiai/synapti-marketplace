#!/bin/bash
# [flow] PreToolUse hook (Bash): System One site guard.command-intent.
#
# Asks the configured System One provider whether a command could destroy
# data that is hard to recover, next to the pattern checks (block-*.sh). Off
# by default; with no provider, or the site off, only the mode check runs.
#
# It never lets a command through: Claude Code runs every matching PreToolUse
# hook in parallel and takes deny > defer > ask > allow, with exit 2 counting
# as deny (https://code.claude.com/docs/en/hooks, read 2026-10-12), and this
# hook never prints allow, defer or deny and always exits 0. In on mode it
# asks the user to confirm a command the pattern checks allowed when the
# answer is p >= 0.5 at or above the site threshold. In shadow mode the call
# runs in a new session after the hook has returned, so the command does not
# wait for it, and only its record is kept.
#
# Not sent: a command the cheap check in lib/s1-guard.sh rules out, and a
# command block-secrets.sh refuses. The value of every NAME=value assignment
# is sent as ***. The record's current is block when block-destructive.sh,
# block-force-push.sh or block-unchecked-merge.sh refuses the same payload,
# unknown when one of them could not run, and allow otherwise.
# references/system-one.md has the site.

set -uo pipefail
unset CDPATH

SITE="guard.command-intent"
command -v jq >/dev/null 2>&1 || exit 0
# In shadow mode the hook hands its payload to a copy of itself in a new
# session (the end of this file), which reads it from this file.
DETACHED=0
if [ -n "${FLOW_S1_GUARD_PAYLOAD:-}" ]; then
  # Only a file this hook wrote: in TMPDIR, named by its mktemp pattern,
  # a regular file owned by this user.
  _pd="${FLOW_S1_GUARD_PAYLOAD%/*}"; _td="${TMPDIR:-/tmp}"
  while [ "${_pd%/}" != "$_pd" ]; do _pd="${_pd%/}"; done
  while [ "${_td%/}" != "$_td" ]; do _td="${_td%/}"; done
  [ "$_pd" = "$_td" ] || exit 0
  case "${FLOW_S1_GUARD_PAYLOAD##*/}" in flow-s1-guard.??????) ;; *) exit 0 ;; esac
  [ -f "$FLOW_S1_GUARD_PAYLOAD" ] && [ ! -L "$FLOW_S1_GUARD_PAYLOAD" ] && [ -O "$FLOW_S1_GUARD_PAYLOAD" ] || exit 0
  DETACHED=1
  INPUT=$(cat -- "$FLOW_S1_GUARD_PAYLOAD" 2>/dev/null) || exit 0
else
  INPUT=$(cat) || exit 0
fi

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P) || exit 0
BIN=$(cd "$HERE/../../bin" 2>/dev/null && pwd -P) || exit 0
[ -x "$BIN/flow-s1-mode.sh" ] && [ -x "$BIN/flow-s1.sh" ] && [ -x "$BIN/cascade-resolve.sh" ] || exit 0
# shellcheck source=lib/s1-guard.sh
. "$HERE/lib/s1-guard.sh" 2>/dev/null || exit 0
# Every Bash call reaches this line: unless the user's own settings put the
# site in shadow or on, nothing more starts.
_g_user_wants "$BIN" "$SITE" || exit 0
# The user's mode is shadow: hand the payload to a copy of this hook in a new
# session at once, so the command waits for none of what follows, the full
# mode check included (a repository can still lower it to off there).
if [ "$G_USER_MODE" = shadow ] && [ "$DETACHED" = 0 ]; then
  PF=$(mktemp "${TMPDIR:-/tmp}/flow-s1-guard.XXXXXX" 2>/dev/null) || exit 0
  case "$PF" in /*) ;; *) rm -f "$PF"; exit 0 ;; esac
  if ! printf '%s' "$INPUT" > "$PF" || ! FLOW_S1_GUARD_PAYLOAD="$PF" _g_detach "$PF" "$HERE/s1-command-intent.sh"; then
    rm -f "$PF"
  fi
  exit 0
fi

CMD=""; CWD=""; TID=""
FIELDS=$(printf '%s' "$INPUT" | jq -r '[.tool_input.command, .cwd, .tool_use_id]
  | map(if type == "string" then . else "" end) | @sh "CMD=\(.[0]) CWD=\(.[1]) TID=\(.[2])"' 2>/dev/null) || exit 0
eval "$FIELDS"
[ -n "${CMD//[[:space:]]/}" ] || exit 0
[ -n "$CWD" ] || CWD=$PWD

# The mode as the client resolves it, read in the payload's cwd so the
# settings are that repository's: a repository can only lower the user's mode.
MODE=$(cd "$CWD" 2>/dev/null && "$BIN/flow-s1-mode.sh" "$SITE" 2>/dev/null) || MODE=""
case "$MODE" in shadow|on) ;; *) exit 0 ;; esac
_g_ruled_out "$CMD" && exit 0

# A command the secrets check refuses, or that it could not check, is not sent.
[ -x "$HERE/block-secrets.sh" ] || exit 0
(cd "$CWD" 2>/dev/null; exec "$HERE/block-secrets.sh") <<<"$INPUT" >/dev/null 2>&1 || exit 0

# What the pattern checks decide for the same payload, run in parallel.
CURRENT=allow
PIDS=()
for h in block-destructive block-force-push block-unchecked-merge; do
  if [ ! -x "$HERE/$h.sh" ]; then CURRENT=unknown; continue; fi
  (cd "$CWD" 2>/dev/null; exec "$HERE/$h.sh") <<<"$INPUT" >/dev/null 2>&1 &
  PIDS+=("$!")
done
BLOCKED=0
for p in "${PIDS[@]+"${PIDS[@]}"}"; do
  wait "$p"
  case "$?" in
    0) ;;
    2) BLOCKED=1 ;;
    *) CURRENT=unknown ;;
  esac
done
[ "$BLOCKED" = 1 ] && CURRENT=block

REF="bash:unknown"
_g_ref_ok "bash:$TID" && [ -n "$TID" ] && REF="bash:$TID"

# State files left by a hook that was killed: this user's, older than 10
# minutes, well past the longest wait (timeoutMs is at most 30 s).
find "${TMPDIR:-/tmp}/" -maxdepth 1 -type f -name 'flow-s1-guard.*' -user "$(id -u)" -mmin +10 \
  -exec rm -f {} + >/dev/null 2>&1 || true
TEMP_DIR=$(cd "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P) || TEMP_DIR="${TMPDIR:-/tmp}"
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || ROOT=""
STATE=$(mktemp "${TMPDIR:-/tmp}/flow-s1-guard.XXXXXX" 2>/dev/null) || exit 0
case "$STATE" in /*) ;; *) rm -f "$STATE"; exit 0 ;; esac
trap 'rm -f "$STATE"' EXIT
trap 'rm -f "$STATE"; exit 0' INT TERM HUP
_g_command_state "$CMD" "$CWD" "$TEMP_DIR" "$ROOT" > "$STATE" 2>/dev/null || exit 0
[ -s "$STATE" ] || exit 0

ARGS=(ask --site "$SITE" --state-file "$STATE" --state-format json --current "$CURRENT" --ref "$REF")

# Shadow: only the record is kept. This runs in the detached copy, or in the
# hook itself when the user's mode is on and a repository lowered it to
# shadow, the one shadow path the command waits for.
if [ "$MODE" = shadow ]; then
  (cd "$CWD" 2>/dev/null && "$BIN/flow-s1.sh" "${ARGS[@]}") >/dev/null 2>&1
  exit 0
fi

OUT=$(cd "$CWD" 2>/dev/null && "$BIN/flow-s1.sh" "${ARGS[@]}" 2>/dev/null) || exit 0
# A command a pattern check refuses gets no ask. When a pattern check could
# not run (unknown) it refused nothing, so the answer still asks.
[ "$CURRENT" = block ] && exit 0
printf '%s' "$OUT" | jq -ce --arg site "$SITE" '
  (.answers.destructive | select(type == "object" and (.p | type) == "number" and .p >= 0.5)) as $a
  | {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask",
      permissionDecisionReason: ("Flow System One (site \($site), model \(.model // "unknown")) judged that this command could destroy data that is hard to recover, p = \($a.p). The pattern checks did not refuse it. Confirm only if you intend it.")}}' 2>/dev/null || true
exit 0
