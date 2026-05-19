#!/usr/bin/env bash
# [flow] Canonical six-field Proactive-Autonomy escalation formatter
#
# CLI utility for ad-hoc human use. Formats the six-field structure documented
# in `plugins/flow/references/escalation-format.md` as a markdown prompt body
# suitable for use as the `question:` field of `AskUserQuestion`. The script
# does NOT call AskUserQuestion itself — that is an LLM-side tool.
#
# Pipeline integration status: commands currently inline the escalation prose
# so the structure stays inspectable in each command body. This script is
# available for hand-running (terminal use, scripted previews, format checks)
# and lets reviewers verify the canonical shape mechanically without parsing
# command-specific text.
#
# Usage:
#   flow-escalate.sh \
#     --situation "..." \
#     --tried "..." \
#     --options "1: First option;2: Second option;3: Third option" \
#     --recommendation "..." \
#     --blocking "yes|soft|no" \
#     --risk "..."
#
# Options are semicolon-separated to keep the CLI single-shot. Each option
# is `<n>: <text>` where <n> is the option number. The script renders them
# as a numbered markdown list.
#
# Exits:
#   0 — printed the formatted body to stdout
#   1 — missing required field; usage printed to stderr
#   2 — invalid input (e.g., empty option text); error printed to stderr

set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage: flow-escalate.sh \
         --situation TEXT \
         --tried TEXT \
         --options "1: A;2: B[;3: C]" \
         --recommendation TEXT \
         --blocking TEXT \
         --risk TEXT

All six fields are required. Options are semicolon-separated (each `<n>: <text>`).
The --blocking flag should be "yes", "soft", or "no" (no calendar-time language).
See plugins/flow/references/escalation-format.md for field semantics.
USAGE
}

SITUATION=""
TRIED=""
OPTIONS=""
RECOMMENDATION=""
BLOCKING=""
RISK=""

# Distinguishes "flag passed without a value" (e.g., trailing `--blocking`) from
# "flag absent." Without this guard, a trailing flag consumes its own slot via
# `${2:-}` and the user gets a misleading "missing required fields" message.
require_value() {
  if [ "$2" -lt 2 ]; then
    echo "flow-escalate.sh: $1 requires a value" >&2
    exit 1
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --situation)      require_value "$1" "$#"; SITUATION="$2"; shift 2 ;;
    --tried)          require_value "$1" "$#"; TRIED="$2"; shift 2 ;;
    --options)        require_value "$1" "$#"; OPTIONS="$2"; shift 2 ;;
    --recommendation) require_value "$1" "$#"; RECOMMENDATION="$2"; shift 2 ;;
    --blocking)       require_value "$1" "$#"; BLOCKING="$2"; shift 2 ;;
    --risk)           require_value "$1" "$#"; RISK="$2"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *)                echo "flow-escalate.sh: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

# Required-field check
MISSING=()
[ -z "$SITUATION" ]      && MISSING+=("--situation")
[ -z "$TRIED" ]          && MISSING+=("--tried")
[ -z "$OPTIONS" ]        && MISSING+=("--options")
[ -z "$RECOMMENDATION" ] && MISSING+=("--recommendation")
[ -z "$BLOCKING" ]       && MISSING+=("--blocking")
[ -z "$RISK" ]           && MISSING+=("--risk")

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "flow-escalate.sh: missing required fields: ${MISSING[*]}" >&2
  usage
  exit 1
fi

# Value-space validation for --blocking: the rename from --time-sensitivity
# only matters if the actual values are constrained. Without this check, a
# caller passing `--blocking "by Friday"` defeats the calendar-time framing
# the rename was designed to eliminate. Case-insensitive on input so canonical
# prose examples ("Yes."/"Soft."/"No.") work without normalization, normalized
# to lowercase on render. See references/escalation-format.md.
case "$BLOCKING" in
  yes|Yes|YES) BLOCKING="yes" ;;
  soft|Soft|SOFT) BLOCKING="soft" ;;
  no|No|NO) BLOCKING="no" ;;
  *)
    echo "flow-escalate.sh: --blocking must be 'yes', 'soft', or 'no' (case-insensitive; got: '$BLOCKING')" >&2
    exit 2
    ;;
esac

# Format options (semicolon-separated → numbered markdown list).
# Each item in OPTIONS is `N: text`. Validate that each non-empty entry has the
# `N: text` shape; reject empty/malformed items rather than render placeholders.
# We strip the user-supplied `<n>:` prefix and re-number sequentially with
# Markdown's `N.` syntax so the rendered output is a real numbered list rather
# than a bullet whose label happens to start with a digit.
OPTIONS_BLOCK=""
SEEN_NUMS=""
IFS=';' read -r -a OPTION_ARRAY <<< "$OPTIONS"
for option in "${OPTION_ARRAY[@]}"; do
  # Trim leading/trailing whitespace
  option="${option#"${option%%[![:space:]]*}"}"
  option="${option%"${option##*[![:space:]]}"}"
  [ -z "$option" ] && continue
  if ! echo "$option" | grep -qE '^[0-9]+:[[:space:]]*.+'; then
    echo "flow-escalate.sh: malformed option '$option' — must match '<n>: <text>'" >&2
    exit 2
  fi
  # Reject duplicate option numbers — `1: A;1: B` is almost always a typo
  # and renders confusingly even with the `N.` re-numbering below.
  NUM=$(echo "$option" | grep -oE '^[0-9]+')
  case " $SEEN_NUMS " in
    *" $NUM "*)
      echo "flow-escalate.sh: duplicate option number '$NUM' — each option must be unique" >&2
      exit 2
      ;;
  esac
  SEEN_NUMS="$SEEN_NUMS $NUM"
  OPTIONS_BLOCK="${OPTIONS_BLOCK}${option}"$'\n'
done

if [ -z "$OPTIONS_BLOCK" ]; then
  echo "flow-escalate.sh: --options expanded to zero items" >&2
  exit 2
fi

# Render the canonical six-field body. The output is plain markdown so the
# caller can pass it as-is to AskUserQuestion's `question:` parameter. The
# headings match references/escalation-format.md exactly. Options are rendered
# as a real Markdown numbered list (`1. ...`) — preserving the user-supplied
# `<n>:` would have produced a bullet with the digit embedded in the text and
# rendered identically regardless of count.
cat <<BODY
**Situation** — $SITUATION

**What I tried** — $TRIED

**Options**:
$(printf '%s' "$OPTIONS_BLOCK" | awk 'NF { sub(/^[0-9]+:[[:space:]]*/, ""); print NR ". " $0 }')

**Recommendation** — $RECOMMENDATION

**Blocking?** — $BLOCKING

**Risk** — $RISK
BODY
