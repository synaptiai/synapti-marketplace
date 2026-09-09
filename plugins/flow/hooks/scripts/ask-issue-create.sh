#!/usr/bin/env bash
# [flow] PreToolUse hook (matcher: Bash): ask before `gh issue create` while a
# FlowGoal is active.
#
# Why: flow's operator rule (skills/llm-operator-principles) is that findings
# are fixed in the current PR. Follow-up issues are legitimate only under
# `minimalScope: true` or for a genuine product decision. The only moment a
# hook can observe an agent filing a follow-up issue mid-goal is the
# `gh issue create` call, so this hook turns that call into a permission
# prompt (permissionDecision "ask") that names the active goal and the rule.
# It never denies on its own; the person decides.
#
# Decision table:
#   jq missing                              -> exit 0, silent (cannot parse the payload)
#   command is not a `gh issue create`      -> exit 0, no output
#   minimalScope resolves to true           -> exit 0, no output (follow-ups are legitimate)
#   no active goal (helper exit 1)          -> exit 0, no output
#   helper cannot determine (exit 2 or 3)   -> exit 0, no output, one stderr line
#   active goal found                       -> exit 0, stdout JSON with permissionDecision "ask"
#
# Command-position rule: `gh issue create` must be the command word of a
# simple command — at the start of the whole command or right after `;`, `&&`,
# `||`, `|`, `(`, `$(`, a backtick or a newline — optionally preceded by
# VAR=value assignments, and the `gh` may carry a path (`/usr/bin/gh`). Text
# that merely contains the words is an argument to another command and does
# not prompt: `echo gh issue create` and `git commit -m "gh issue create
# later"` both pass. Shell quoting cannot put quoted text into command
# position, so quoted occurrences never prompt without any quote parsing.
#
# Goal selection is --branch-strict: only a goal that owns the current branch
# (or, when the branch is unknown, the most recently modified active goal)
# prompts. An active goal parked on another branch is not evidence that work
# on this branch is mid-goal.
#
# Hook input (stdin JSON): session_id, transcript_path, cwd, permission_mode,
# hook_event_name, tool_name, tool_input.command. Only tool_input.command is
# read.

set -uo pipefail
export PYTHONSAFEPATH=1

command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/../..}"
# cascade-resolve.sh locates the plugin-default settings.json through
# CLAUDE_PLUGIN_ROOT (falling back to the repo-relative plugins/flow, which is
# wrong from any other cwd), so publish the resolved root to it.
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

INPUT=$(cat 2>/dev/null || echo '{}')
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -z "$COMMAND" ] && exit 0

# Split into simple commands, then test each for `gh issue create` in command
# position. Separators: ; | & ( ) backtick newline. `$(` becomes `$` + `(`.
IS_ISSUE_CREATE=0
while IFS= read -r SEG; do
  [ -z "$SEG" ] && continue
  if printf '%s\n' "$SEG" | grep -qE '^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*([^[:space:]]*/)?gh[[:space:]]+issue[[:space:]]+create([[:space:]]|$)'; then
    IS_ISSUE_CREATE=1
    break
  fi
done < <(printf '%s\n' "$COMMAND" | tr ';|&()`' '\n')
[ "$IS_ISSUE_CREATE" = "1" ] || exit 0

# minimalScope: true restores the follow-up-issue workflow, so there is
# nothing to ask about. The expression is a bare `.minimalScope`, not
# `.minimalScope // null`: jq's `//` treats false like null, so an explicit
# project-level false would collapse to null, be skipped by the cascade, and
# let a user-global true win. A missing key yields null, which the cascade
# already treats as not-found.
MINIMAL_SCOPE=$("${PLUGIN_ROOT}/bin/cascade-resolve.sh" --default false '.minimalScope' 2>/dev/null)
[ "$MINIMAL_SCOPE" = "true" ] && exit 0

# Active goal for the current branch. Exit codes (bin/flow-active-goal.sh):
# 0 found, 1 none, 2 infrastructure (python3/PyYAML/symlink), 3 degenerate.
GOAL_ID=$("${PLUGIN_ROOT}/bin/flow-active-goal.sh" --id --branch-strict 2>/dev/null)
GOAL_RC=$?
case "$GOAL_RC" in
  0) ;;
  1) exit 0 ;;
  *)
    echo "flow: ask-issue-create — cannot determine the active FlowGoal (flow-active-goal.sh exit $GOAL_RC); allowing gh issue create without a prompt" >&2
    exit 0
    ;;
esac
# metadata.id comes from user-editable YAML: collapse it to one line and pass
# it to jq via --arg, never by string concatenation.
GOAL_ID=$(printf '%s' "$GOAL_ID" | tr '\n' ' ' | sed -E 's/[[:space:]]+$//')
[ -z "$GOAL_ID" ] && GOAL_ID="(unnamed)"

REASON="An active FlowGoal (${GOAL_ID}) is in progress. Flow's rule is to fix findings in this PR rather than file follow-up issues. Approve only if this issue is a genuine product decision or work outside the goal's scope; otherwise deny and fix it here. Set minimalScope: true in .claude/settings.flow.json to stop this prompt."

jq -nc --arg r "$REASON" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
exit 0
