#!/usr/bin/env bash
# aggregate-findings-ledger.sh — aggregate review findings across the user's
# open PRs (author OR assignee) using the FLOW_REVIEW_CYCLE / FLOW_RESOLUTION_CYCLE
# marker schemas defined in plugins/flow/references/finding-ledger-parser.md.
#
# Used by /flow:status (`commands/status.md`) to render the Findings Ledger.
#
# Trust model:
#   The author_association of the review/comment author must be in the trust
#   list (default: ["OWNER","MEMBER","COLLABORATOR"]). The trust list is
#   resolved via the standard Claude Code settings cascade (mirrors the
#   /flow:merge gate); see commands/merge.md for the full rationale.
#
# Output (stdout):
#   Tally rows in the form `   <count> <PRIORITY>|<STATE>`, e.g.
#     2 P1|in_fix_forward
#     1 P2|escalated
#     3 P3|in_fix_forward
#   plus one control line:
#     LEDGER: unavailable (gh API failed)         — when gh enumeration fails
#
# Output (stderr):
#   LEDGER_WARN messages for non-conforming finding IDs/priorities (cap 64 chars,
#   non-printable bytes stripped, to neutralize attacker-controlled review bodies).
#
# Exit:
#   0 — always (errors are surfaced via LEDGER: unavailable on stdout or
#       LEDGER_WARN on stderr; this is an aggregator and must not break
#       /flow:status when one source is bad).

set -uo pipefail

ME=$(gh api user --jq '.login' 2>/dev/null)
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)

if [ -z "$ME" ] || [ -z "$REPO" ]; then
  echo "LEDGER: unavailable (gh API failed)"
  exit 0
fi

# MARKERTRUST_GATE_BEGIN
# Resolve trust list from the standard Claude Code settings cascade — same
# precedence as /flow:merge. See commands/merge.md for the full rationale.
TRUST_DEFAULT='["OWNER","MEMBER","COLLABORATOR"]'
TRUST_LIST="$TRUST_DEFAULT"
LOCAL_SETTINGS=".claude/settings.flow.local.json"
PROJECT_SETTINGS=".claude/settings.flow.json"
USER_SETTINGS="${HOME:-/nonexistent}/.claude/settings.flow.json"
PLUGIN_SETTINGS="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json"
for SETTINGS_PATH in "$LOCAL_SETTINGS" "$PROJECT_SETTINGS" "$USER_SETTINGS" "$PLUGIN_SETTINGS"; do
  [ -f "$SETTINGS_PATH" ] || continue
  CONFIGURED=$(jq -c '.merge.markerTrust.allowedAssociations // empty' "$SETTINGS_PATH" 2>&1)
  JQ_EXIT=$?
  if [ $JQ_EXIT -ne 0 ]; then
    JQ_ERR=$(printf '%s' "$CONFIGURED" | tr '\n' ' ' | cut -c1-200)
    echo "WARN: failed to parse $SETTINGS_PATH (jq exit=$JQ_EXIT, error: $JQ_ERR); skipping this source" >&2
    continue
  fi
  [ -z "$CONFIGURED" ] && continue
  if echo "$CONFIGURED" | jq -e '. | type == "array" and length > 0 and all(.[]; type == "string")' >/dev/null 2>&1; then
    TRUST_LIST="$CONFIGURED"
    break
  fi
  # Invalid (non-array, empty array, non-string elements) — fall through to
  # next source rather than block /flow:status (an aggregator command). The
  # /flow:merge gate is the authoritative validator and emits FINDING_LEDGER_BLOCK
  # for the same input, so the user sees the right error in the right place.
done
# MARKERTRUST_GATE_END

# Enumerate PRs (author OR assignee). Capture gh exit code separately so a
# silent gh failure (auth, network) doesn't masquerade as "no PRs".
LEDGER_PRS_RAW=$(gh pr list --state open --limit 100 --json number,author,assignees 2>/dev/null)
GH_EXIT=$?
if [ $GH_EXIT -ne 0 ] || [ -z "$LEDGER_PRS_RAW" ]; then
  LEDGER_PRS="LEDGER_UNAVAILABLE"
else
  LEDGER_PRS=$(echo "$LEDGER_PRS_RAW" | jq -r --arg me "$ME" \
    '[.[] | select(.author.login == $me or (.assignees[].login? == $me))] | .[].number' 2>/dev/null || echo "LEDGER_UNAVAILABLE")
fi

if [ "$LEDGER_PRS" = "LEDGER_UNAVAILABLE" ]; then
  echo "LEDGER: unavailable (gh API failed)"
  exit 0
fi

# Sanitize attacker-controlled fields before display/echo: cap length and
# strip non-printable bytes so a hostile review-body can't inject ANSI
# escapes into LEDGER_WARN output. Defined once for the whole loop.
safe() { printf '%s' "$1" | tr -cd '[:print:]' | cut -c1-64; }

for PR_NUM in $LEDGER_PRS; do
  REVIEW_BODY=$(gh api --paginate "repos/$REPO/pulls/$PR_NUM/reviews" 2>/dev/null \
    | jq -s -r --argjson trust "$TRUST_LIST" \
        'add | [.[] | select((.author_association as $a | $trust | index($a)) and (.body | test("FLOW_REVIEW_CYCLE:")))] | last | .body // ""')
  FINDINGS_RAW=$(echo "$REVIEW_BODY" | grep -o 'FINDINGS:\[[^]]*\]' | sed 's/^FINDINGS:\[//;s/\]$//')
  [ -z "$FINDINGS_RAW" ] && continue

  RESOLUTION_BODY=$(gh api --paginate "repos/$REPO/issues/$PR_NUM/comments" 2>/dev/null \
    | jq -s -r --argjson trust "$TRUST_LIST" \
        'add | [.[] | select((.author_association as $a | $trust | index($a)) and (.body | test("FLOW_RESOLUTION_CYCLE:")))] | last | .body // ""')
  # Strip whitespace so reviewer-edited arrays like `[F1, F2]` still match.
  RESOLVED=$(echo "$RESOLUTION_BODY"  | grep -o 'RESOLVED:\[[^]]*\]'  | sed 's/^RESOLVED:\[//;s/\]$//'  | tr -d ' ')
  ESCALATED=$(echo "$RESOLUTION_BODY" | grep -o 'ESCALATED:\[[^]]*\]' | sed 's/^ESCALATED:\[//;s/\]$//' | tr -d ' ')
  DISPUTED=$(echo "$RESOLUTION_BODY"  | grep -o 'DISPUTED:\[[^]]*\]'  | sed 's/^DISPUTED:\[//;s/\]$//'  | tr -d ' ')

  echo "$FINDINGS_RAW" | tr ',' '\n' | while IFS='|' read -r ID PRIORITY CAT LOC STATUS; do
    [ -z "$ID" ] && continue
    # Reject IDs containing case-glob metacharacters (`*`, `?`, `[`, `]`) —
    # IDs are template-issued and should match [A-Za-z][A-Za-z0-9_-]*.
    # Without this, a hostile finding ID of `*` would always match the
    # `case ",$RESOLVED," in *",$ID,"*)` containment check and silently
    # disappear from the tally.
    case "$ID" in
      [A-Za-z]*) ;;
      *) echo "LEDGER_WARN: PR#$PR_NUM finding '$(safe "$ID")' rejected (non-conforming ID)" >&2; continue ;;
    esac
    case "$ID" in *[!A-Za-z0-9_-]*)
      echo "LEDGER_WARN: PR#$PR_NUM finding '$(safe "$ID")' rejected (non-conforming ID)" >&2
      continue ;;
    esac
    # Defensive: surface non-conforming priority rows to stderr (visible
    # without breaking the tally), then skip. Older marker formats produced
    # findings without P{1-3} priority fields.
    case "$PRIORITY" in
      P1|P2|P3) ;;
      *) echo "LEDGER_WARN: PR#$PR_NUM finding '$(safe "$ID")' has malformed priority '$(safe "$PRIORITY")'" >&2; continue ;;
    esac
    # Precedence: RESOLVED > ESCALATED > DISPUTED > in_fix_forward.
    case ",$RESOLVED," in *",$ID,"*) continue ;; esac
    case ",$ESCALATED," in *",$ID,"*) STATE=escalated ;;
      *) case ",$DISPUTED," in *",$ID,"*) STATE=disputed ;;
           *) STATE=in_fix_forward ;; esac ;;
    esac
    echo "${PRIORITY}|${STATE}"
  done
done | sort | uniq -c

exit 0
