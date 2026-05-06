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
#     --time-sensitivity "blocking|urgent|low|deadline:YYYY-MM-DD" \
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
         --time-sensitivity TEXT \
         --risk TEXT

All six fields are required. Options are semicolon-separated (each `<n>: <text>`).
See plugins/flow/references/escalation-format.md for field semantics.
USAGE
}

SITUATION=""
TRIED=""
OPTIONS=""
RECOMMENDATION=""
TIME_SENSITIVITY=""
RISK=""

while [ $# -gt 0 ]; do
  case "$1" in
    --situation)         SITUATION="${2:-}"; shift 2 ;;
    --tried)             TRIED="${2:-}"; shift 2 ;;
    --options)           OPTIONS="${2:-}"; shift 2 ;;
    --recommendation)    RECOMMENDATION="${2:-}"; shift 2 ;;
    --time-sensitivity)  TIME_SENSITIVITY="${2:-}"; shift 2 ;;
    --risk)              RISK="${2:-}"; shift 2 ;;
    -h|--help)           usage; exit 0 ;;
    *)                   echo "flow-escalate.sh: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

# Required-field check
MISSING=()
[ -z "$SITUATION" ]        && MISSING+=("--situation")
[ -z "$TRIED" ]            && MISSING+=("--tried")
[ -z "$OPTIONS" ]          && MISSING+=("--options")
[ -z "$RECOMMENDATION" ]   && MISSING+=("--recommendation")
[ -z "$TIME_SENSITIVITY" ] && MISSING+=("--time-sensitivity")
[ -z "$RISK" ]             && MISSING+=("--risk")

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "flow-escalate.sh: missing required fields: ${MISSING[*]}" >&2
  usage
  exit 1
fi

# Format options (semicolon-separated → numbered markdown list)
# Each item in OPTIONS is `N: text`. Validate that each non-empty entry has the
# `N: text` shape; reject empty/malformed items rather than render placeholders.
OPTIONS_BLOCK=""
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
  OPTIONS_BLOCK="${OPTIONS_BLOCK}${option}"$'\n'
done

if [ -z "$OPTIONS_BLOCK" ]; then
  echo "flow-escalate.sh: --options expanded to zero items" >&2
  exit 2
fi

# Render the canonical six-field body. The output is plain markdown so the
# caller can pass it as-is to AskUserQuestion's `question:` parameter. The
# headings match references/escalation-format.md exactly.
cat <<BODY
**Situation** — $SITUATION

**What I tried** — $TRIED

**Options**:
$(printf '%s' "$OPTIONS_BLOCK" | awk 'NF { print "- " $0 }')

**Recommendation** — $RECOMMENDATION

**Time sensitivity** — $TIME_SENSITIVITY

**Risk** — $RISK
BODY
