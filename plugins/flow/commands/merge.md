---
description: "Merge an approved pull request. Verifies prerequisites (approval, checks, conversations), displays assessment, and requires explicit human confirmation. Tier 3 — never autonomous."
argument-hint: <pr-number> [free-form context]
allowed-tools: Bash, Read, AskUserQuestion, Skill
---

# Merge PR #$ARGUMENTS

Tier 3 operation — **always requires human confirmation**. This is non-negotiable even in autonomous mode.

## Required Skills

- `llm-operator-principles` — foundational operator stance: convergence = zero findings, in-PR fixes by default, no calendar-time estimates, narrow escalation triggers. MUST be consulted before any other phase
- `merge-and-release` — prerequisite verification, merge execution

## References

- [`references/escalation-format.md`](../references/escalation-format.md) — canonical six-field structure used by Phase 2's conflict-resolution escalation and Phase 3's merge-confirm prompt

## Phase 1: Verify Prerequisites

```!
# Take the first whitespace-separated token; accept only if it is all digits.
# Trailing context (e.g., "104 (verify ledger gate)") is fine — first-token
# extraction handles it. A non-numeric token (e.g., "foo42" or "evil;rm") is
# rejected with empty PR_NUM so it never reaches the prompt context or any
# downstream shell. Matches the pattern in brainstorm.md / design.md.
#
# Output: `###`-headed sections + KEY=value per
# `references/command-output-format.md`. STATE=blocked on bad input;
# downstream Phase 2 reads each named field directly.
_RAW="$ARGUMENTS"  # Claude Code substitutes the bare arg token, not bash parameter-expansion
ARG1="${_RAW%% *}"
case "$ARG1" in
  ''|*[!0-9]*) PR_NUM="" ;;
  *) PR_NUM="$ARG1" ;;
esac

echo "### PR Reference"
if [ -z "$PR_NUM" ]; then
  echo "STATE=blocked"
  echo "ERROR=PR number required (all-digit). Usage: /flow:merge <pr-number>"
else
  echo "STATE=ok"
  echo "PR_NUM=$PR_NUM"

  # Section: PR Status
  echo ""
  echo "### PR Status"
  gh pr view "$PR_NUM" --json reviewDecision,statusCheckRollup,mergeable,mergeStateStatus,title,headRefName --jq '
    [.statusCheckRollup[]? | select(.__typename == "CheckRun")] as $checks |
    (if (.reviewDecision // "") == "" then "(none)" else .reviewDecision end) as $review |
    "TITLE=\"\(.title)\"\nHEAD_BRANCH=\(.headRefName)\nMERGEABLE=\(.mergeable)\nMERGE_STATE_STATUS=\(.mergeStateStatus)\nREVIEW_DECISION=\($review)\nCHECKS_PASSED=\($checks | map(select(.conclusion == "SUCCESS")) | length)\nCHECKS_FAILED=\($checks | map(select(.conclusion == "FAILURE")) | length)\nCHECKS_TOTAL=\($checks | length)"
  ' 2>/dev/null

  # Section: Reviews — one labeled line per review
  echo ""
  echo "### Reviews"
  # Capture gh exit separately; gh failure must surface as STATE=unavailable
  # rather than collapse to STATE=empty (the merge gate must close, not open,
  # when reviews can't be read).
  REVIEWS_JSON=$(gh pr view "$PR_NUM" --json reviews --jq '.reviews' 2>/dev/null); GH_EXIT=$?
  if [ $GH_EXIT -ne 0 ]; then
    echo "REVIEW_COUNT=0"
    echo "STATE=unavailable"
  else
    REVIEW_COUNT=$(echo "$REVIEWS_JSON" | jq 'length' 2>/dev/null)
    [ -z "$REVIEW_COUNT" ] && REVIEW_COUNT=0
    echo "REVIEW_COUNT=$REVIEW_COUNT"
    if [ "$REVIEW_COUNT" = "0" ]; then
      echo "STATE=empty"
    else
      echo "$REVIEWS_JSON" | jq -r '.[] | "REVIEW=state=\(.state) author=@\(.author.login) at=\(.submittedAt)"' 2>/dev/null
    fi
  fi

  # Section: Unresolved Conversations (GraphQL — reviewThreads not in REST)
  echo ""
  echo "### Unresolved Conversations"
  REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
  OWNER=$(echo "$REPO" | cut -d/ -f1)
  NAME=$(echo "$REPO" | cut -d/ -f2)
  UNRESOLVED_COUNT=$(gh api graphql -f query="query { repository(owner: \"$OWNER\", name: \"$NAME\") { pullRequest(number: $PR_NUM) { reviewThreads(first: 100) { nodes { isResolved } } } } }" --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length' 2>/dev/null); GH_EXIT=$?
  # Closed-vocab contract: emit STATE=unavailable as a separate sentinel rather
  # than encoding unavailability as the value of UNRESOLVED_COUNT.
  if [ $GH_EXIT -ne 0 ] || [ -z "$UNRESOLVED_COUNT" ]; then
    echo "UNRESOLVED_COUNT=0"
    echo "STATE=unavailable"
  else
    echo "UNRESOLVED_COUNT=$UNRESOLVED_COUNT"
  fi

  # Section: Stale Approval Check
  echo ""
  echo "### Stale Approval Check"
  gh pr view "$PR_NUM" --json reviews,commits --jq '
    ([.reviews[] | select(.state == "APPROVED")] | sort_by(.submittedAt) | last | .submittedAt // "none") as $la |
    (.commits | last | .committedDate) as $lc |
    "LAST_APPROVAL=\($la)\nLAST_COMMIT=\($lc)\nSTALE=\(if $la == "none" then "n/a" elif $la < $lc then "true" else "false" end)"
  ' 2>/dev/null

  # Section: Finding-ledger seed (full gate runs in next ! block)
  echo ""
  echo "### Finding-Ledger Seed"
  # Capture gh exit separately. Same reason as the Reviews section: the merge
  # gate must close (STATE=unavailable) rather than open (STATE=empty) when
  # markers can't be read.
  SEED_JSON=$(gh api "repos/$REPO/issues/$PR_NUM/comments" --jq '[.[] | select(.body | test("FLOW_RESOLUTION_CYCLE|FLOW_REVIEW_CYCLE")) | {id, body}]' 2>/dev/null); GH_EXIT=$?
  if [ $GH_EXIT -ne 0 ]; then
    echo "SEED_MARKER_COUNT=0"
    echo "STATE=unavailable"
  else
    SEED_COUNT=$(echo "$SEED_JSON" | jq 'length' 2>/dev/null)
    [ -z "$SEED_COUNT" ] && SEED_COUNT=0
    echo "SEED_MARKER_COUNT=$SEED_COUNT"
    if [ "$SEED_COUNT" = "0" ]; then
      echo "STATE=empty"
    else
      # `scan` is a generator that yields each match; wrap in `[...]` to collect
      # all matches into an array, then take `last` (the actual marker —
      # typically in an HTML comment at end-of-body — earlier occurrences are
      # usually prose references). Two capture groups (kind, cycle) so each
      # element is `[kind, cycle]`.
      echo "$SEED_JSON" | jq -r '.[] | (
        ([.body | scan("FLOW_(RESOLUTION|REVIEW)_CYCLE:([0-9]+)")] | last // ["?","?"]) as $last |
        "SEED=id=\(.id) kind=\($last[0]) cycle=\($last[1])"
      )' 2>/dev/null
    fi
  fi
fi

true
```

### Finding-Ledger Check

Parse the latest `FLOW_RESOLUTION_CYCLE` and `FLOW_REVIEW_CYCLE` comments to verify all findings are resolved before merge. Marker schemas and the canonical extraction queries are documented in [`references/finding-ledger-parser.md`](../references/finding-ledger-parser.md); this command applies the merge-blocking subset (ESCALATED non-empty, FINDINGS without matching RESOLVED).

```!
# Extract the latest FLOW_RESOLUTION_CYCLE comment (issue/PR conversation).
# Capture gh exit code: a silent gh failure (auth, network) must fail the gate
# CLOSED, not pass it open. PR_NUM is digit-validated (matches Phase 1 block);
# a non-digit token rejects rather than reaching downstream shell or echo.
_RAW="$ARGUMENTS"  # Claude Code substitutes the bare arg token, not bash parameter-expansion
ARG1="${_RAW%% *}"
case "$ARG1" in
  ''|*[!0-9]*) PR_NUM="" ;;
  *) PR_NUM="$ARG1" ;;
esac

echo "### Finding-Ledger Gate"
if [ -z "$PR_NUM" ]; then
  echo "LEDGER_GATE_STATE=blocked"
  echo "FINDING_LEDGER_BLOCK: PR number required (all-digit)"
else

# Tracks whether any FINDING_LEDGER_BLOCK has been emitted. Final
# LEDGER_GATE_STATE is decided after all gate checks have run.
LEDGER_GATE_BLOCKED=0
emit_block() { LEDGER_GATE_BLOCKED=1; echo "FINDING_LEDGER_BLOCK: $1"; }

REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)

# MARKERTRUST_GATE_BEGIN
# Resolve trust list from the standard Claude Code settings cascade.
# Precedence (highest first — first valid value wins):
#   1. .claude/settings.flow.local.json — project-local; gitignored
#   2. .claude/settings.flow.json — project-shared; committed (visible in PR review)
#   3. $HOME/.claude/settings.flow.json — user-global default
#   4. ${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json — plugin default
# Reviewers of a fork PR will see any change to .claude/settings.flow.json in
# the diff like any other repo file; defense moves from "plugin refuses to
# read" to "maintainer review notices the change."
TRUST_DEFAULT='["OWNER","MEMBER","COLLABORATOR"]'
TRUST_LIST="$TRUST_DEFAULT"
LOCAL_SETTINGS=".claude/settings.flow.local.json"
PROJECT_SETTINGS=".claude/settings.flow.json"
USER_SETTINGS="${HOME:-/nonexistent}/.claude/settings.flow.json"
PLUGIN_SETTINGS="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/settings.json"
for SETTINGS_PATH in "$LOCAL_SETTINGS" "$PROJECT_SETTINGS" "$USER_SETTINGS" "$PLUGIN_SETTINGS"; do
  [ -f "$SETTINGS_PATH" ] || continue
  # Capture jq stderr/exit so a parse error in $HOME does not silently mask
  # a typo as "fall through to plugin default" — same pattern as the
  # agentTeams gate in commands/review.md.
  CONFIGURED=$(jq -c '.merge.markerTrust.allowedAssociations // empty' "$SETTINGS_PATH" 2>&1)
  JQ_EXIT=$?
  if [ $JQ_EXIT -ne 0 ]; then
    JQ_ERR=$(printf '%s' "$CONFIGURED" | tr '\n' ' ' | cut -c1-200)
    echo "WARN: failed to parse $SETTINGS_PATH (jq exit=$JQ_EXIT, error: $JQ_ERR); skipping this source" >&2
    continue
  fi
  [ -z "$CONFIGURED" ] && continue
  if echo "$CONFIGURED" | jq -e '. | type == "array" and length > 0 and all(.[]; type == "string")' >/dev/null 2>&1; then
    # Warn (don't block) when an element falls outside the known GitHub
    # `author_association` vocabulary. A typo such as `"owner"` (lowercase)
    # or `"MAINTAINER"` (not a real value) passes the type check above but
    # would match no real author, silently disabling trust for the typo'd
    # entry. Use the same WARN-and-continue pattern as the HIGH_RISK check
    # below — the gate already fails closed via the "untrusted-only"
    # branch when nothing matches.
    UNKNOWN_VALUES=$(echo "$CONFIGURED" | jq -r '.[] | select(. != "OWNER" and . != "MEMBER" and . != "COLLABORATOR" and . != "CONTRIBUTOR" and . != "FIRST_TIME_CONTRIBUTOR" and . != "FIRST_TIMER" and . != "MANNEQUIN" and . != "NONE")' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    if [ -n "$UNKNOWN_VALUES" ]; then
      echo "LEDGER_WARN: markerTrust in $SETTINGS_PATH contains values [$UNKNOWN_VALUES] not in the GitHub author_association vocabulary (OWNER, MEMBER, COLLABORATOR, CONTRIBUTOR, FIRST_TIME_CONTRIBUTOR, FIRST_TIMER, MANNEQUIN, NONE). These elements will match no authors — check for typos." >&2
    fi
    TRUST_LIST="$CONFIGURED"
    TRUST_SOURCE="$SETTINGS_PATH"
    break
  else
    # Fall through to next source. Emit on stderr (NOT stdout) so the
    # downstream "If the finding-ledger check fails" gate that scans stdout
    # for FINDING_LEDGER_BLOCK does not treat this as a block — a typo at
    # one tier should not block merge when a lower tier resolves correctly.
    # If no tier resolves, TRUST_LIST stays at TRUST_DEFAULT (initialized
    # above), which is the safe minimum trust list.
    echo "LEDGER_WARN: invalid markerTrust configuration in $SETTINGS_PATH (must be non-empty JSON array of strings); falling through" >&2
  fi
done

# Defense-in-depth: warn (not block) when the resolved trust list contains
# high-risk values that would let a forked-PR author forge their own resolution
# markers. The cascade visibility (settings changes appear in PR diffs) is the
# primary defense; this WARN raises the signal at every merge attempt so a
# maintainer cannot accidentally miss it during a quick diff scan.
if [ -n "${TRUST_SOURCE:-}" ]; then
  HIGH_RISK=$(echo "$TRUST_LIST" | jq -r '.[] | select(. == "NONE" or . == "FIRST_TIMER" or . == "FIRST_TIME_CONTRIBUTOR" or . == "MANNEQUIN")' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  if [ -n "$HIGH_RISK" ]; then
    echo "LEDGER_WARN: trust list (from $TRUST_SOURCE) includes high-risk values [$HIGH_RISK]. Forked-PR contributors with these author_associations could forge FLOW_RESOLUTION_CYCLE markers. Verify this is intentional before merging." >&2
  fi
fi
# MARKERTRUST_GATE_END

# Trust filter applied via jq's `index()` exact-match (no regex surface).
# `--paginate` keeps fetching pages so a noisy thread can't hide forgeries.
#
# Fetch each endpoint once; reuse the cached JSON for both filter passes
# (trusted + untrusted-counting). Capturing `gh`'s exit code via `$?` directly
# after the command substitution is the only reliable way to detect a silent
# gh failure: `VAR=$(gh ... | jq ...)` then `${PIPESTATUS[0]}` does NOT capture
# gh's inner exit — bash resets PIPESTATUS to reflect only the outer assignment
# (verified: `X=$(false | true); echo ${PIPESTATUS[0]}` → 0). Without the cache
# split, a gh stderr-only failure with empty stdout would let `jq -s 'add //
# empty'` succeed on null input and the gate would pass open.
GH_RES_RAW=$(gh api --paginate "repos/$REPO/issues/$PR_NUM/comments" 2>/dev/null)
GH_EXIT_RES=$?
RESOLUTION_BODY=$(printf '%s' "$GH_RES_RAW" | jq -s -r --argjson trust "$TRUST_LIST" \
    'add | [.[] | select((.author_association as $a | $trust | index($a)) and (.body | test("FLOW_RESOLUTION_CYCLE:")))] | last | .body // ""')
RES_UNTRUSTED=$(printf '%s' "$GH_RES_RAW" | jq -s -r --argjson trust "$TRUST_LIST" \
    'add | [.[] | select((.author_association as $a | $trust | index($a) | not) and (.body | test("FLOW_RESOLUTION_CYCLE:")))] | length')

# Extract ESCALATED array contents (portable POSIX grep+sed; BSD grep has no -P).
# Strip whitespace so reviewer-edited arrays like `[F1, F2]` still match.
ESCALATED=$(echo "$RESOLUTION_BODY" | grep -o 'ESCALATED:\[[^]]*\]' | sed 's/^ESCALATED:\[//;s/\]$//' | tr -d ' ')

# Extract the latest FLOW_REVIEW_CYCLE — emitted in PR review bodies, not issue comments
GH_REV_RAW=$(gh api --paginate "repos/$REPO/pulls/$PR_NUM/reviews" 2>/dev/null)
GH_EXIT_REV=$?
REVIEW_BODY=$(printf '%s' "$GH_REV_RAW" | jq -s -r --argjson trust "$TRUST_LIST" \
    'add | [.[] | select((.author_association as $a | $trust | index($a)) and (.body | test("FLOW_REVIEW_CYCLE:")))] | last | .body // ""')
REV_UNTRUSTED=$(printf '%s' "$GH_REV_RAW" | jq -s -r --argjson trust "$TRUST_LIST" \
    'add | [.[] | select((.author_association as $a | $trust | index($a) | not) and (.body | test("FLOW_REVIEW_CYCLE:")))] | length')

# Fail closed if either gh call failed — better to block a legitimate merge
# than silently let a regression through when the gate state is unknowable.
# Both `_UNTRUSTED` counting calls share the same gh exit code as their primary
# (they re-filter the cached JSON), so a single per-endpoint exit check covers
# all four filter passes.
if [ $GH_EXIT_RES -ne 0 ] || [ $GH_EXIT_REV -ne 0 ]; then
  emit_block "gh API unavailable — cannot verify finding ledger (resolution exit=$GH_EXIT_RES, review exit=$GH_EXIT_REV)"
fi

# Surface "untrusted-only" markers as a block reason rather than silently
# treating them as no markers at all. This is the #92 forgery defense.
# Render the trust list as a comma-separated string for the user-facing
# message — the `$TRUST_REGEX` variable used to appear here was a leftover
# from PR #93 and never assigned, producing the empty-parens string
# "trusted authors ()" in messages or aborting under `set -u`.
#
# Derive the fallback from $TRUST_DEFAULT rather than hard-coding the value:
# if $TRUST_DEFAULT changes (e.g., adding CONTRIBUTOR), the display string
# stays in lockstep instead of silently lying.
TRUST_LIST_DISPLAY=$(echo "$TRUST_LIST" | jq -r 'join(",")' 2>/dev/null)
if [ -z "$TRUST_LIST_DISPLAY" ]; then
  TRUST_LIST_DISPLAY=$(echo "$TRUST_DEFAULT" | jq -r 'join(",")' 2>/dev/null)
fi
if [ -z "$RESOLUTION_BODY" ] && [ "${RES_UNTRUSTED:-0}" != "0" ]; then
  emit_block "$RES_UNTRUSTED FLOW_RESOLUTION_CYCLE marker(s) found but none from trusted authors ($TRUST_LIST_DISPLAY)"
fi
if [ -z "$REVIEW_BODY" ] && [ "${REV_UNTRUSTED:-0}" != "0" ]; then
  emit_block "$REV_UNTRUSTED FLOW_REVIEW_CYCLE marker(s) found but none from trusted authors ($TRUST_LIST_DISPLAY)"
fi

# Extract all finding IDs from FINDINGS array (comma-separated, pipe-delimited fields, first field is the ID)
REVIEW_FINDINGS=$(echo "$REVIEW_BODY" | grep -o 'FINDINGS:\[[^]]*\]' | sed 's/^FINDINGS:\[//;s/\]$//' | tr ',' '\n' | sed 's/|.*//' | tr -d ' ' | sort)

# Extract RESOLVED finding IDs from resolution comment
RESOLVED_FINDINGS=$(echo "$RESOLUTION_BODY" | grep -o 'RESOLVED:\[[^]]*\]' | sed 's/^RESOLVED:\[//;s/\]$//' | tr ',' '\n' | tr -d ' ' | sort)

# Check 1: ESCALATED must be empty
if [ -n "$ESCALATED" ]; then
  emit_block "ESCALATED array is non-empty: [$ESCALATED]"
fi

# Check 2: Every finding in REVIEW_FINDINGS must have a matching RESOLVED entry
UNRESOLVED=$(comm -23 <(echo "$REVIEW_FINDINGS") <(echo "$RESOLVED_FINDINGS") | grep -v '^$' || true)
if [ -n "$UNRESOLVED" ]; then
  emit_block "Unresolved findings: $UNRESOLVED"
fi

# Emit the final gate state sentinel. The agent dispatches off this:
#   ok      → proceed to Phase 2 Display Assessment
#   blocked → halt, render the "BLOCKED: Unresolved Findings" template
#             (one FINDING_LEDGER_BLOCK line per reason was emitted above)
if [ $LEDGER_GATE_BLOCKED -eq 1 ]; then
  echo "LEDGER_GATE_STATE=blocked"
else
  echo "LEDGER_GATE_STATE=ok"
fi

fi  # /if [ -z "$PR_NUM" ]

true
```

### FlowGoal Gate (v3)

Independent of the finding-ledger gate, the FlowGoal gate **gates on goal existence** (#111 D-GATE): when an active goal exists for this branch it must have reached `lifecycle.status == achieved` to merge; when **no** active goal exists the gate is **not applicable** and merge proceeds (a PR without a FlowGoal is not blocked). The gate is disabled entirely when `flow.goals.enabled` is `false` or `flow.goals.goalCreation` is `off` — preserving the v2 `requireGoalForStart: false` UX (no merge gating).

```!
HELPER="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/cascade-resolve.sh"
# Migration-aware (#111 AC-1): goalCreation wins; else map legacy
# requireGoalForStart (true→always, false→off); else null → cascade default auto.
GOAL_MODE=$("$HELPER" --default "auto" '.flow.goals.goalCreation // (if .flow.goals.requireGoalForStart == true then "always" elif .flow.goals.requireGoalForStart == false then "off" else null end)' 2>/dev/null)
case "$GOAL_MODE" in auto|always|off) ;; *) GOAL_MODE="auto" ;; esac
ENABLED=$("$HELPER" --default "true" '.flow.goals.enabled' 2>/dev/null)

echo "### FlowGoal Gate"
if [ "$ENABLED" != "true" ] || [ "$GOAL_MODE" = "off" ]; then
  echo "FLOW_GOAL_GATE_STATE=disabled"
else
  ACTIVE_GOAL_HELPER="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/flow-active-goal.sh"
  if [ ! -x "$ACTIVE_GOAL_HELPER" ]; then
    echo "FLOW_GOAL_GATE_STATE=blocked"
    echo "FLOW_GOAL_BLOCK_REASON=flow-active-goal.sh missing or non-executable"
  else
    GOAL_STATUS=$("$ACTIVE_GOAL_HELPER" --status 2>/dev/null); GOAL_EXIT=$?
    case "$GOAL_EXIT" in
      0)
        GOAL_ID=$("$ACTIVE_GOAL_HELPER" --id 2>/dev/null)
        echo "FLOW_GOAL_ID=$GOAL_ID"
        echo "FLOW_GOAL_LIFECYCLE=$GOAL_STATUS"
        if [ "$GOAL_STATUS" = "achieved" ]; then
          echo "FLOW_GOAL_GATE_STATE=ok"
        else
          # Active goal exists but is not achieved — fail closed.
          # The "no incomplete shipments" hard boundary applies: merging a
          # PR whose own contract reports incomplete is exactly what F1 is
          # designed to prevent.
          echo "FLOW_GOAL_GATE_STATE=blocked"
          echo "FLOW_GOAL_BLOCK_REASON=FlowGoal $GOAL_ID lifecycle is '$GOAL_STATUS' — run /flow:goal evaluate $GOAL_ID to advance"
        fi
        ;;
      1)
        # No active goal on this branch — gate not applicable (#111 D-GATE:
        # gate on existence). A PR without a FlowGoal is not blocked; the PR's
        # own review state remains the durable record. This intentionally
        # replaces the prior fail-closed so default installs (goalCreation:auto)
        # do not start blocking goal-less merges.
        echo "FLOW_GOAL_GATE_STATE=ok"
        echo "FLOW_GOAL_GATE_NOTE=no active FlowGoal for this branch — gate not applicable"
        ;;
      3)
        # >1 active goal on the current branch (after #111 AC-4 branch-scoping).
        echo "FLOW_GOAL_GATE_STATE=blocked"
        echo "FLOW_GOAL_BLOCK_REASON=degenerate state — multiple active FlowGoals on the current branch"
        ;;
      *)
        echo "FLOW_GOAL_GATE_STATE=blocked"
        echo "FLOW_GOAL_BLOCK_REASON=flow-active-goal.sh exited $GOAL_EXIT"
        ;;
    esac
  fi
fi

true
```

**If either the finding-ledger check or the FlowGoal gate fails**, stop immediately and display:

```markdown
## BLOCKED: Merge Prerequisites Not Met

PR #$PR_NUM cannot be merged — one or more gates report unresolved items.

| Gate | Issue | Details |
|------|-------|---------|
| Finding ledger | gh API unavailable | {if either GH_EXIT_RES or GH_EXIT_REV is non-zero, list both exit codes; else "N/A"} |
| Finding ledger | Untrusted markers only | {if RES_UNTRUSTED or REV_UNTRUSTED is non-zero AND no trusted markers found, list counts} |
| Finding ledger | Non-empty ESCALATED | {list of escalated finding IDs, if any} |
| Finding ledger | Unmatched FINDINGS | {list of finding IDs with no RESOLVED entry, if any} |
| FlowGoal | Not achieved | {if FLOW_GOAL_GATE_STATE=blocked, show FLOW_GOAL_ID + FLOW_GOAL_LIFECYCLE + FLOW_GOAL_BLOCK_REASON} |

### Remediation

1. Run `/flow:address $PR_NUM` to resolve remaining findings
2. Ensure every finding in `FLOW_REVIEW_CYCLE:FINDINGS` has a matching `RESOLVED` entry in `FLOW_RESOLUTION_CYCLE`
3. Ensure `ESCALATED:[]` is empty (all escalated items must be resolved or have explicit human override)
4. If the FlowGoal gate blocks, run `/flow:goal evaluate $FLOW_GOAL_ID` and verify the verdict reaches `achieved`
5. Re-run `/flow:merge $PR_NUM`

This gate enforces the "no incomplete shipments" hard boundary.
```

Do NOT proceed to Phase 2. Exit here.

### FlowRun (v3 runtime)

`/flow:merge` runs the `merge-pr` workflow, so it gets a durable FlowRun. Runs are gated by `flow.runtime.enabled` (default `true`); v2 projects that opted out see `FLOW_RUN_STATE=skip` and the wiring is a no-op.

```!
# FLOW_RUN_BLOCK_BEGIN
CASCADE="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/cascade-resolve.sh"
if [ ! -x "$CASCADE" ]; then
  echo "FLOW_RUN_STATE=blocked"
  echo "FLOW_RUN_ERROR=cascade-resolve.sh missing or non-executable at $CASCADE"
  true; exit 0
fi
RUNTIME_ENABLED=$("$CASCADE" --default "true" '.flow.runtime.enabled' 2>/dev/null)
_RAW="$ARGUMENTS"  # Claude Code substitutes the bare arg token, not bash parameter-expansion
ARG1="${_RAW%% *}"
case "$ARG1" in
  ''|*[!0-9]*) PR_NUM="" ;;
  *) PR_NUM="$ARG1" ;;
esac
if [ "$RUNTIME_ENABLED" != "true" ]; then
  echo "FLOW_RUN_STATE=skip"
  echo "FLOW_RUN_REASON=flow.runtime.enabled is not true (v2 mode)"
else
  SLUG="${PR_NUM:-nonum}"
  RUN_ID="$(date -u +%Y-%m-%dT%H%M%SZ)-merge-pr-${SLUG}"
  echo "FLOW_RUN_STATE=create"
  echo "RUN_ID=$RUN_ID"
  echo "WORKFLOW=merge-pr"
  echo "INITIAL_PHASE=preflight"
fi
# FLOW_RUN_BLOCK_END
true
```

When `FLOW_RUN_STATE=create`, invoke `Skill(run-state-management)` to create `.flow/runs/$RUN_ID/run.yaml` (workflow=`merge-pr`, goal=`null` — the merge reads the linked FlowGoal for the gate below but the run itself is not goal-owned), initial phase `preflight`. Phase order: `preflight → verify → confirm → merge`. Write a FlowActivity at each boundary (verify, confirm, merge).

**Linked-run completion check** (Phase 2 / verify): before allowing merge, verify that every FlowRun linked to this PR's branch (the `start-issue` run and any `address-pr` / `review-pr` runs) has reached `state.status: completed`. If any linked run is still `active`, refuse the merge — this is Tier 3, so there is **no override** beyond the standard merge confirmation. Surface the still-active run id and point to `/flow:resume`.

## Phase 2: Display Assessment

```markdown
## Merge Assessment for PR #$PR_NUM

| Check | Status | Details |
|-------|--------|---------|
| Approval | {Pass/Fail} | {N approvals, latest by @X} |
| CI Checks | {Pass/Fail} | {N passed, M failed} |
| Mergeable | {Pass/Fail} | {No conflicts / Has conflicts} |
| Conversations | {Pass/Fail} | {All resolved / N unresolved} |
| Stale Approval | {OK/Warning} | {Fresh / Commits after approval} |
| Finding Ledger | {Pass/Fail} | {All resolved / N unresolved, M escalated} |

**Merge strategy**: {from settings.merge.strategy, default: squash}
**Delete branch**: {from settings.merge.deleteBranch, default: true}
```

If any check fails, explain what needs to be fixed and suggest actions.

### Conflict Resolution Path

If the Mergeable check fails (has conflicts):

Use the AskUserQuestion tool with a Proactive-Autonomy escalation:

> **Situation** — PR #$PR_NUM has merge conflicts that prevent merging.
>
> **What I tried** — Checked mergeable status via `gh pr view`. Conflicts exist between the PR branch and the base branch.
>
> **Options**:
> 1. Resolve conflicts now — invokes `Skill(flow:resolve)` with $PR_NUM (Recommended)
> 2. Cancel merge — address conflicts manually or rebase first
>
> **Recommendation** — Option 1. Automated conflict resolution handles most cases and re-verifies after resolution.
>
> **Blocking?** — Yes. Blocks merge; the workflow cannot proceed until conflicts resolve.
>
> **Risk** — Option 1 may produce incorrect resolution for semantic conflicts (caught by post-resolution verification). Option 2 delays merge.

If Option 1: after resolution completes, re-run Phase 1 to verify PR is now mergeable.

## Phase 3: Confirm and Execute

Use the AskUserQuestion tool with contextual options to confirm: "PR #$PR_NUM is ready to merge. Proceed with squash merge and branch deletion?"

Only after the user confirms via the tool:

```bash
# Read merge settings
STRATEGY="squash"  # or from settings
DELETE_FLAG="--delete-branch"  # or from settings

gh pr merge "$PR_NUM" --$STRATEGY $DELETE_FLAG
```

## Phase 4: Post-Merge

```bash
# Verify merge
gh pr view "$PR_NUM" --json state --jq '.state'

# Switch to default branch
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
git checkout $DEFAULT_BRANCH
git pull origin $DEFAULT_BRANCH
```

**FlowRun terminal transition** (when `FLOW_RUN_STATE=create`): after a successful merge, invoke `Skill(run-state-management)` to transition the `merge-pr` FlowRun to `state.status: completed` and update its `workflow-run` journal artifact to `status=completed`. Then transition the linked FlowGoal to a terminal status if it is not already — the merge itself is the achievement signal. If the merge was cancelled, transition the run to `cancelled` (with `blocked_reason`) so it is not treated as resumable.

**Manifest emit** — if this merge resolved any escalations (a Proactive-Autonomy escalation surfaced via `AskUserQuestion` during Phase 1's finding-ledger check, Phase 2's stale-approval warning, or the conflict-resolution path closed because the user provided one of the six canonical fields), record an `escalation-resolved` artifact for each:

```bash
ISSUE=$(gh pr view "$PR_NUM" --json body --jq '.body' | grep -oE '#[0-9]+' | head -1 | tr -d '#')
if [ -n "$ISSUE" ]; then
  # Repeat once per escalation that closed during this merge run.
  "$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/journal-record.sh" \
    --issue $ISSUE \
    --type escalation-resolved \
    --metadata escalation_field={situation|tried|options|recommendation|blocking|risk} \
    --metadata outcome="$USER_RESPONSE_SUMMARY"
fi
```

The emit is conditional — most merges run cleanly without escalations, in which case skip this step. When it does fire, the manifest captures both *that* an escalation closed and *which canonical field* was the gate, enabling `/flow:learn` to detect recurring escalation patterns (e.g., the same field gating multiple merges → process or tooling improvement opportunity).

Suggest: `/flow:release {type}` if this completes a milestone.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read PR status / reviews / comments / threads | 1 | Autonomous |
| Finding-ledger gate check (parses `FLOW_REVIEW_CYCLE` / `FLOW_RESOLUTION_CYCLE`) | 1 | Autonomous; blocks on failure |
| FlowGoal gate check (v3 opt-in; reads `.flow/goals/*.goal.yaml`) | 1 | Autonomous; blocks on `lifecycle.status != achieved` |
| Stale-approval check | 1 | Autonomous; warns on stale |
| Conflict-resolution escalation (`Skill(flow:resolve)` invocation) | 2 | Journal-and-proceed if user accepts; otherwise blocked |
| `gh pr merge` | 3 | **Confirm** — always asks via `AskUserQuestion` |
| Branch deletion (per `merge.deleteBranch` setting, default `true`) | 3 | **Confirm** — bundled into the merge prompt |
| `git checkout <default-branch> && git pull` (post-merge cleanup) | 1 | Autonomous |
