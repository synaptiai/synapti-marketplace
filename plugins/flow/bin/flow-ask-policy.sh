#!/usr/bin/env bash
# [flow] Print the ask policy: whether flow asks a person for a default, or
# takes its recommendation and records it.
#
#   attended    the default: every question flow's commands may ask is asked
#   autonomous  `autonomous: true` in the settings cascade: a question that
#               only asks for a default is not asked; the agent takes its
#               recommendation and records it (references/ask-policy.md).
#               Questions only a person can answer, a product or scope
#               decision or a permission, are still asked.
#
# Read by the preflight of /flow:start, /flow:pr, /flow:address, /flow:review,
# /flow:commit and /flow:resolve (ASK_POLICY=...) and by the PreToolUse hook
# on AskUserQuestion (hooks/scripts/ask-policy.sh), so both read one rule.
#
# Usage: flow-ask-policy.sh
# Output: attended | autonomous, one line
# Exit: 0 printed; 2 the settings could not be read (cascade-resolve.sh missing
#       or failing), with the reason on stderr and nothing on stdout. A caller
#       that asks a person treats that as attended: someone is there to answer.

set -uo pipefail
unset CDPATH

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CASCADE="$SCRIPT_DIR/cascade-resolve.sh"
if [ ! -x "$CASCADE" ]; then
  echo "flow-ask-policy.sh: cascade-resolve.sh missing or not executable at $CASCADE" >&2
  exit 2
fi
# A bare `.autonomous`, not `// false`: jq's `//` reads false as null, so an
# explicit project-level false would fall through to a user-level true.
VALUE=$("$CASCADE" --default false '.autonomous' 2>/dev/null); rc=$?
if [ "$rc" -ne 0 ]; then
  echo "flow-ask-policy.sh: the settings could not be read (cascade-resolve.sh exited $rc)" >&2
  exit 2
fi
case "$VALUE" in
  true) printf '%s\n' autonomous ;;
  *) printf '%s\n' attended ;;
esac
