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

# Probe for jq before we depend on it — every cascade and parse path below
# uses jq. Without this probe, missing jq leaks raw `command not found` lines
# into /flow:status output (cascade-resolve.sh follows the same pattern).
if ! command -v jq >/dev/null 2>&1; then
  echo "LEDGER: unavailable (jq not installed)"
  exit 0
fi

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
TRUST_SOURCE=""
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
    echo "LEDGER_WARN: failed to parse $SETTINGS_PATH (jq exit=$JQ_EXIT, error: $JQ_ERR); skipping this source" >&2
    continue
  fi
  [ -z "$CONFIGURED" ] && continue
  if echo "$CONFIGURED" | jq -e '. | type == "array" and length > 0 and all(.[]; type == "string")' >/dev/null 2>&1; then
    TRUST_LIST="$CONFIGURED"
    TRUST_SOURCE="$SETTINGS_PATH"
    break
  fi
  # Invalid (non-array, empty array, non-string elements) — fall through to
  # next source rather than block /flow:status (an aggregator command). The
  # /flow:merge gate is the authoritative validator and emits FINDING_LEDGER_BLOCK
  # for the same input, so the user sees the right error in the right place.
done

# Defense-in-depth: warn (not block) when the resolved trust list contains
# high-risk values that would let a forked-PR author forge resolution markers.
# Parity with commands/merge.md HIGH_RISK detection (lines 101-111). The
# cascade visibility (settings changes appear in PR diffs) is the primary
# defense; this WARN raises the signal at every /flow:status invocation so
# a permissive setting doesn't silently shape the Findings Ledger.
if [ -n "$TRUST_SOURCE" ]; then
  HIGH_RISK=$(echo "$TRUST_LIST" | jq -r '.[] | select(. == "NONE" or . == "FIRST_TIMER" or . == "FIRST_TIME_CONTRIBUTOR" or . == "MANNEQUIN")' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  if [ -n "$HIGH_RISK" ]; then
    echo "LEDGER_WARN: trust list (from $TRUST_SOURCE) includes high-risk values [$HIGH_RISK]. Forked-PR contributors with these author_associations could forge FLOW_RESOLUTION_CYCLE markers. Verify this is intentional." >&2
  fi
fi
# MARKERTRUST_GATE_END

# Enumerate PRs (author OR assignee). Capture gh exit code separately so a
# silent gh failure (auth, network) doesn't masquerade as "no PRs". jq is a
# distinct failure mode — a valid empty array from gh produces empty output
# from jq with exit 0, which falls through to the loop iterating 0 times
# (the documented "no findings" path).
LEDGER_PRS_RAW=$(gh pr list --state open --limit 100 --json number,author,assignees 2>/dev/null)
GH_EXIT=$?
if [ $GH_EXIT -ne 0 ] || [ -z "$LEDGER_PRS_RAW" ]; then
  echo "LEDGER: unavailable (gh API failed)"
  exit 0
fi
LEDGER_PRS=$(echo "$LEDGER_PRS_RAW" | jq -r --arg me "$ME" \
  '[.[] | select(.author.login == $me or (.assignees[].login? == $me))] | .[].number' 2>/dev/null)

# Track per-PR fetch failures so the ledger can flag partial state. A silent
# per-PR failure (rate limit, transient network) used to vanish into "no
# findings"; surface it as LEDGER: partial so /flow:status renders the right
# caveat instead of a falsely-clean ledger.
#
# Implementation note: the `for PR_NUM ...` loop runs in a subshell (left
# side of the pipe to `sort | uniq -c` below), so a regular shell variable
# cannot propagate the partial-flag out. Use a sentinel file in /tmp.
PARTIAL_FLAG="/tmp/flow-ledger-partial.$$"
rm -f "$PARTIAL_FLAG" 2>/dev/null
# Cleanup on exit so a failed run doesn't leave the sentinel for the next.
trap 'rm -f "$PARTIAL_FLAG" 2>/dev/null' EXIT

# Sanitize attacker-controlled fields before display/echo: cap length and
# strip non-printable bytes AND shell metacharacters (backticks, $, \) so a
# hostile review-body can't inject ANSI escapes into LEDGER_WARN output or
# slip syntactic surface into any future consumer that re-evaluates the
# warning text. Defined once for the whole loop.
safe() { printf '%s' "$1" | tr -cd '[:print:]' | tr -d '`$\\' | cut -c1-64; }

for PR_NUM in $LEDGER_PRS; do
  REVIEW_RAW=$(gh api --paginate "repos/$REPO/pulls/$PR_NUM/reviews" 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "LEDGER_WARN: PR#$PR_NUM reviews fetch failed (gh API error)" >&2
    : > "$PARTIAL_FLAG"
    continue
  fi
  REVIEW_BODY=$(printf '%s' "$REVIEW_RAW" | jq -s -r --argjson trust "$TRUST_LIST" \
        'add | [.[] | select((.author_association as $a | $trust | index($a)) and (.body | test("FLOW_REVIEW_CYCLE:")))] | last | .body // ""' 2>/dev/null)
  FINDINGS_RAW=$(echo "$REVIEW_BODY" | grep -o 'FINDINGS:\[[^]]*\]' | sed 's/^FINDINGS:\[//;s/\]$//')
  [ -z "$FINDINGS_RAW" ] && continue

  RESOLUTION_RAW=$(gh api --paginate "repos/$REPO/issues/$PR_NUM/comments" 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "LEDGER_WARN: PR#$PR_NUM comments fetch failed (gh API error)" >&2
    : > "$PARTIAL_FLAG"
    # Continue with empty RESOLUTION_BODY so findings still tally as in_fix_forward
    RESOLUTION_BODY=""
  else
    RESOLUTION_BODY=$(printf '%s' "$RESOLUTION_RAW" | jq -s -r --argjson trust "$TRUST_LIST" \
        'add | [.[] | select((.author_association as $a | $trust | index($a)) and (.body | test("FLOW_RESOLUTION_CYCLE:")))] | last | .body // ""' 2>/dev/null)
  fi
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

# Surface partial-fetch state so /flow:status renders the right caveat
# instead of presenting incomplete findings as authoritative. The sentinel
# file is set by the per-PR loop above (which runs in a pipe-induced
# subshell where shell-variable updates cannot propagate). Cleanup is
# handled by the EXIT trap.
[ -f "$PARTIAL_FLAG" ] && \
  echo "LEDGER: partial (some PRs unavailable — see LEDGER_WARN on stderr)"

exit 0
