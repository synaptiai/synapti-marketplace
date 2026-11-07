#!/usr/bin/env bash
# [flow] PreToolUse hook (matcher: AskUserQuestion): in autonomous mode, a
# question that only asks for a default does not reach the person.
#
# `autonomous: true` used to be prose that no script read: whether it applied
# depended on the model remembering the setting (#339). This hook applies it.
# A question declares its class in the tool input's metadata, which the
# person does not see:
#
#   metadata.source "flow:decision"    a product or scope decision only a
#                                      person can make
#   metadata.source "flow:permission"  a Tier 3 action, or a skip outside the
#                                      runtime-verification list
#
# Every call site in flow's commands and skills carries its class as a tag
# ([ask: decision], [ask: permission], [ask: default]); references/ask-policy.md
# has the rule. A [ask: default] site under the autonomous policy takes its
# recommendation and records it instead of asking.
#
# Decision table:
#   payload not readable (jq missing, not JSON)  -> exit 0, no output (allow)
#   ask policy cannot be read (bin/flow-ask-policy.sh exit != 0)
#                                                -> exit 0, no output (allow:
#                                                   a person is there to answer)
#   policy attended                              -> exit 0, no output (allow)
#   policy autonomous, source flow:decision or flow:permission
#                                                -> exit 0, no output (allow)
#   policy autonomous, any other question        -> exit 0, stdout JSON with
#                                                   permissionDecision "deny"
#                                                   and what to do instead
#
# Verified on Claude Code 2.1.319 before it was built on: a deny-only
# PreToolUse hook on AskUserQuestion takes effect, no permission request
# reaches the host, the agent receives the reason as the tool result, and the
# hook's payload carries tool_input.metadata.source as the agent wrote it
# (references/ask-policy.md, "How the hook was checked").

set -uo pipefail
unset CDPATH

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null) || exit 0
SOURCE=$(printf '%s' "$INPUT" | jq -r '.tool_input.metadata.source // empty' 2>/dev/null) || exit 0
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || CWD=""

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$HOOK_DIR/../.." && pwd)}"
[ -x "$PLUGIN_ROOT/bin/flow-ask-policy.sh" ] || PLUGIN_ROOT="$(cd "$HOOK_DIR/../.." && pwd)"

if [ -n "$CWD" ] && [ -d "$CWD" ]; then
  POLICY=$(cd "$CWD" && "$PLUGIN_ROOT/bin/flow-ask-policy.sh" 2>/dev/null) || exit 0
else
  POLICY=$("$PLUGIN_ROOT/bin/flow-ask-policy.sh" 2>/dev/null) || exit 0
fi

[ "$POLICY" = autonomous ] || exit 0
case "$SOURCE" in
  flow:decision|flow:permission) exit 0 ;;
esac

REASON='flow ask policy: autonomous (autonomous: true). This question only asks for a default, so it is not shown to the person. Take your recommended option, record it in the decision journal with bin/journal-record.sh --type default-taken (references/ask-policy.md), say so in your summary, and continue. A question only a person can answer is asked with metadata {"source":"flow:decision"} (a product or scope decision) or {"source":"flow:permission"} (a Tier 3 action, or a skip outside the runtime-verification list).'
jq -nc --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
