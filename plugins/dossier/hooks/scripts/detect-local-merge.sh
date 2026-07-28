#!/bin/bash
# [dossier] PostToolUse hook: suggest (or prompt for) a documentation refresh
# after a local merge to the repository's default branch — regardless of
# which plugin or human ran the merging command. See dossier.local.onLocalMerge.
#
# Fully self-contained: this hook never reads another plugin's settings,
# state, or presence, and it works identically whether or not any other
# plugin is installed. It watches for merge-shaped Bash commands directly,
# not for a specific other plugin's command having run.
#
# Advisory only — never blocks. jq missing means the command/config cannot be
# read, so this fails OPEN (silent no-op), unlike enforce-allowed-actions.sh's
# fail-closed posture for its security ceiling: a suggestion feature that
# blocks a shell command because it could not parse its own input would be a
# correctness regression with no compensating safety benefit.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$COMMAND" ] || exit 0

RESOLVER="${CLAUDE_PLUGIN_ROOT:-plugins/dossier}/bin/dossier-resolve-config.sh"
MODE="suggest"
[ -x "$RESOLVER" ] && MODE=$("$RESOLVER" --default "suggest" dossier.local.onLocalMerge 2>/dev/null)
[ "$MODE" = "off" ] && exit 0

# Anchored the same way enforce-allowed-actions.sh anchors its command-class
# checks: start of line, or after a pipe/semicolon/&&/subshell open, so that
# `grep "git merge" README.md` — reading about a merge — is not mistaken for
# performing one.
BOUND='(^|[;&|(]|^[[:space:]]*)[[:space:]]*([A-Za-z0-9_.-]*/)*'

CHECK_MERGE_COMMIT=0
if printf '%s' "$COMMAND" | grep -qE "${BOUND}git[[:space:]]+merge\b"; then
  CHECK_MERGE_COMMIT=1
elif printf '%s' "$COMMAND" | grep -qE "${BOUND}git[[:space:]]+pull\b"; then
  CHECK_MERGE_COMMIT=1
elif printf '%s' "$COMMAND" | grep -qE "${BOUND}gh[[:space:]]+pr[[:space:]]+merge\b"; then
  :
else
  exit 0
fi

# A `git merge`/`git pull` only counts when THIS command actually produced a
# new merge commit — two checks, both required:
#
# 1. HEAD^2 exists: this really is a merge commit, not a fast-forward pull.
#
# 2. HEAD's most recent reflog move happened essentially now, not at some
#    earlier point in history. This is the one that actually matters: once
#    any real merge has ever landed, HEAD stays a two-parent commit until the
#    next ordinary commit, so check 1 alone would re-fire on every later
#    command that merely matches the regex — including a genuinely no-op
#    `git pull` (verified: a no-op pull writes no new reflog entry, so
#    comparing HEAD@{1} to HEAD does NOT distinguish "just happened" from
#    "happened a while ago and nothing has moved since" — the reflog position
#    is identical in both cases). A hook has no persisted state from a prior
#    invocation to compare against, so elapsed-time-since-last-move is the
#    only stateless signal available. This also naturally excludes `git merge
#    --abort`/`--quit`/`--no-commit`: none of them move HEAD, so its last real
#    move stays whatever it was before this command ran.
if [ "$CHECK_MERGE_COMMIT" -eq 1 ]; then
  git rev-parse --verify --quiet HEAD^2 >/dev/null 2>&1 || exit 0
  REFLOG_TIME=$(git log -g -1 --format=%cd --date=unix HEAD 2>/dev/null)
  NOW=$(date +%s)
  case "$REFLOG_TIME" in
    ''|*[!0-9]*) exit 0 ;;
  esac
  # Overridable only for tests, which cannot wait out a real freshness window
  # to prove the "stale merge does not re-fire" case deterministically and
  # fast — real usage always gets the 15s default.
  [ $((NOW - REFLOG_TIME)) -le "${DOSSIER_MERGE_FRESHNESS_SECONDS:-15}" ] || exit 0
fi

# Best-effort default-branch check. An unresolvable default branch degrades to
# "treat any merge-shaped command as landing on the default branch" — an
# acceptable false positive for a suggestion feature (see issue #135's
# documented failure modes), not a reason to fail closed.
DEFAULT_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
if [ -n "$DEFAULT_BRANCH" ]; then
  CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
  [ "$CURRENT_BRANCH" = "$DEFAULT_BRANCH" ] || exit 0
fi

# additionalContext is the only mechanism a PostToolUse hook has to put text
# where the agent will actually see and can act on it — stderr alone is
# surfaced to a human watching the transcript, not reliably injected into the
# agent's own context the way stale-header-stamp.sh's human-facing warning
# doesn't need to be. "run" and "suggest" differ only in phrasing; a hook has
# no mechanism to invoke a slash command directly, only to ask.
case "$MODE" in
  run)
    MESSAGE="[dossier] A merge just landed on the default branch. Run /dossier:refresh now to keep the documentation package current."
    ;;
  *)
    MESSAGE="[dossier] A merge just landed on the default branch. Consider running /dossier:refresh to keep the documentation package current (set dossier.local.onLocalMerge to 'off' to stop seeing this, or 'run' for a stronger prompt)."
    ;;
esac

jq -cn --arg msg "$MESSAGE" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'

exit 0
