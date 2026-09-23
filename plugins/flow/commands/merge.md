---
description: "Merge an approved pull request. Verifies prerequisites (approval, checks, conversations), displays assessment, and requires explicit human confirmation. Tier 3 — never autonomous."
argument-hint: <pr-number> [free-form context]
allowed-tools: Bash, Read, AskUserQuestion, Skill
---

# Merge PR #$ARGUMENTS

Tier 3 operation — **always requires human confirmation**. This is non-negotiable even in autonomous mode.

## Required Skills

- `llm-operator-principles` — operator stance (inlined above): convergence is zero findings, fix in this PR, no calendar-time estimates, escalate only for true decisions
- `merge-and-release` — prerequisite verification, merge execution
- `run-state-management` — FlowRun/FlowActivity records at phase boundaries (v3 runtime)

```!
# Inline the Required Skills above so their rules are in context before the
# first phase runs (commands cannot preload skills from frontmatter). Ambient
# skills load whole; dispatched skills (context: fork / agent:) load their
# `## Contract` section and run in full when this command invokes
# Skill(<name>). Output per `references/command-output-format.md`.
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-load-skills.sh" llm-operator-principles merge-and-release run-state-management

true
```

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

printf '%s\n' "### PR Reference"
if [ -z "$PR_NUM" ]; then
  printf '%s\n' "STATE=blocked"
  printf '%s\n' "ERROR=PR number required (all-digit). Usage: /flow:merge <pr-number>"
else
  printf '%s\n' "STATE=ok"
  printf '%s\n' "PR_NUM=$PR_NUM"

  # Section: Repository — resolved once here, printed, and pinned onto every gh
  # call below. Without the pin each call resolves against whatever repository
  # gh picks for the invoking shell, and a wrong answer does not look wrong: it
  # is the same TITLE=/REVIEW_COUNT= shape either way. In a workspace holding
  # sibling checkouts that is how a preflight reported zero reviews on a pull
  # request that had three, and reported another repository pull request
  # under the number it was asked about.
  #
  # The cross-check parses `git remote get-url origin` independently rather than
  # reading `gh repo view` twice — two readings of one source can never disagree.
  printf '%s\n' ""
  printf '%s\n' "### Repository"
  REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null); GH_EXIT=$?
  GIT_REPO=$(git remote get-url origin 2>/dev/null | sed -E -e 's#\.git$##' -e 's#^.*[:/]([^/]+/[^/]+)$#\1#')
  if [ $GH_EXIT -ne 0 ] || [ -z "$REPO" ]; then
    printf '%s\n' "REPO="
    printf '%s\n' "REPO_STATE=unavailable"
    printf '%s\n' "ERROR=could not resolve the repository (gh repo view failed); every field below would be unattributable"
  else
    printf '%s\n' "REPO=$REPO"
    if [ -z "$GIT_REPO" ]; then
      printf '%s\n' "REPO_CROSSCHECK=unavailable"
      printf '%s\n' "REPO_CROSSCHECK_DETAIL=no origin remote to compare against"
    elif [ "$(printf '%s' "$GIT_REPO" | tr 'A-Z' 'a-z')" = "$(printf '%s' "$REPO" | tr 'A-Z' 'a-z')" ]; then
      printf '%s\n' "REPO_CROSSCHECK=ok"
    else
      printf '%s\n' "REPO_CROSSCHECK=mismatch"
      printf '%s\n' "REPO_CROSSCHECK_DETAIL=git origin is $GIT_REPO but gh resolved $REPO"
      printf '%s\n' "REPO_STATE=blocked"
    fi
  fi

  # Section: PR Status
  printf '%s\n' ""
  printf '%s\n' "### PR Status"
  gh pr view "$PR_NUM" --repo "$REPO" --json reviewDecision,statusCheckRollup,mergeable,mergeStateStatus,title,headRefName --jq '
    [.statusCheckRollup[]? | select(.__typename == "CheckRun")] as $checks |
    (if (.reviewDecision // "") == "" then "(none)" else .reviewDecision end) as $review |
    "TITLE=\"\(.title)\"\nHEAD_BRANCH=\(.headRefName)\nMERGEABLE=\(.mergeable)\nMERGE_STATE_STATUS=\(.mergeStateStatus)\nREVIEW_DECISION=\($review)\nCHECKS_PASSED=\($checks | map(select(.conclusion == "SUCCESS")) | length)\nCHECKS_FAILED=\($checks | map(select(.conclusion == "FAILURE")) | length)\nCHECKS_TOTAL=\($checks | length)"
  ' 2>/dev/null

  # Section: Reviews — one labeled line per review
  printf '%s\n' ""
  printf '%s\n' "### Reviews"
  # Capture gh exit separately; gh failure must surface as STATE=unavailable
  # rather than collapse to STATE=empty (the merge gate must close, not open,
  # when reviews cannot be read).
  REVIEWS_JSON=$(gh pr view "$PR_NUM" --repo "$REPO" --json reviews --jq '.reviews' 2>/dev/null); GH_EXIT=$?
  if [ $GH_EXIT -ne 0 ]; then
    printf '%s\n' "REVIEW_COUNT=0"
    printf '%s\n' "STATE=unavailable"
  else
    REVIEW_COUNT=$(printf '%s\n' "$REVIEWS_JSON" | jq 'length' 2>/dev/null)
    [ -z "$REVIEW_COUNT" ] && REVIEW_COUNT=0
    printf '%s\n' "REVIEW_COUNT=$REVIEW_COUNT"
    if [ "$REVIEW_COUNT" = "0" ]; then
      printf '%s\n' "STATE=empty"
    else
      printf '%s\n' "$REVIEWS_JSON" | jq -r '.[] | "REVIEW=state=\(.state) author=@\(.author.login) at=\(.submittedAt)"' 2>/dev/null
    fi
  fi

  # Section: Unresolved Conversations (GraphQL — reviewThreads not in REST)
  printf '%s\n' ""
  printf '%s\n' "### Unresolved Conversations"
  OWNER=$(printf '%s\n' "$REPO" | cut -d/ -f1)
  NAME=$(printf '%s\n' "$REPO" | cut -d/ -f2)
  UNRESOLVED_COUNT=$(gh api graphql -f query="query { repository(owner: \"$OWNER\", name: \"$NAME\") { pullRequest(number: $PR_NUM) { reviewThreads(first: 100) { nodes { isResolved } } } } }" --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length' 2>/dev/null); GH_EXIT=$?
  # Closed-vocab contract: emit STATE=unavailable as a separate sentinel rather
  # than encoding unavailability as the value of UNRESOLVED_COUNT.
  if [ $GH_EXIT -ne 0 ] || [ -z "$UNRESOLVED_COUNT" ]; then
    printf '%s\n' "UNRESOLVED_COUNT=0"
    printf '%s\n' "STATE=unavailable"
  else
    printf '%s\n' "UNRESOLVED_COUNT=$UNRESOLVED_COUNT"
  fi

  # Section: Stale Approval Check
  printf '%s\n' ""
  printf '%s\n' "### Stale Approval Check"
  gh pr view "$PR_NUM" --repo "$REPO" --json reviews,commits --jq '
    ([.reviews[] | select(.state == "APPROVED")] | sort_by(.submittedAt) | last | .submittedAt // "none") as $la |
    (.commits | last | .committedDate) as $lc |
    "LAST_APPROVAL=\($la)\nLAST_COMMIT=\($lc)\nSTALE=\(if $la == "none" then "n/a" elif $la < $lc then "true" else "false" end)"
  ' 2>/dev/null

  # Section: Finding-ledger seed (full gate runs in next ! block)
  printf '%s\n' ""
  printf '%s\n' "### Finding-Ledger Seed"
  # DIAGNOSTIC PREVIEW ONLY — the authoritative gate runs in the next ! block and
  # scans both streams with trust filtering. This seed exists so the assessment can
  # report what markers are reachable before the gate runs.
  #
  # Markers live on TWO different GitHub objects (see references/finding-ledger-parser.md):
  #   - FLOW_REVIEW_CYCLE     → PR review bodies     (repos/.../pulls/N/reviews)
  #   - FLOW_RESOLUTION_CYCLE → PR/issue comments    (repos/.../issues/N/comments)
  # A seed that scans only one stream undercounts: a PR whose only marker is a
  # FLOW_REVIEW_CYCLE in a review body would report SEED_MARKER_COUNT=0 even though the
  # gate would find it. Scan both and union the hits.
  #
  # The select requires a digit after the colon (FLOW_*_CYCLE:[0-9]) so a "marker" is, by
  # definition, NAME:<cycle-number>. This excludes both bare prose mentions of the marker
  # NAME and unsubstituted-placeholder prose like `FLOW_REVIEW_CYCLE:{N}` (the form the
  # reference documentation uses), so neither inflates the
  # count nor produces a spurious diagnostic. The seed is intentionally a touch stricter
  # than the gate `test("FLOW_*_CYCLE:")` select — the gate tolerates prose by extracting
  # an empty FINDINGS list, whereas a human-facing preview should only count real markers.
  #
  # Capture gh exit separately per endpoint. Same reason as the Reviews section: the
  # merge gate must close (STATE=unavailable) rather than open (STATE=empty) when
  # markers cannot be read.
  SEED_COMMENTS=$(gh api "repos/$REPO/issues/$PR_NUM/comments" --jq '[.[] | select(.body | test("<!-- FLOW_RESOLUTION_CYCLE:[0-9]+ |<!-- FLOW_REVIEW_CYCLE:[0-9]+ ")) | {id, body, surface: "issue-comments"}]' 2>/dev/null); GH_EXIT_C=$?
  SEED_REVIEWS=$(gh api "repos/$REPO/pulls/$PR_NUM/reviews" --jq '[.[] | select(.body | test("<!-- FLOW_RESOLUTION_CYCLE:[0-9]+ |<!-- FLOW_REVIEW_CYCLE:[0-9]+ ")) | {id, body, surface: "reviews"}]' 2>/dev/null); GH_EXIT_R=$?
  printf '%s\n' "SEED_SCANNED=reviews,issue-comments"
  if [ $GH_EXIT_C -ne 0 ] || [ $GH_EXIT_R -ne 0 ]; then
    printf '%s\n' "SEED_MARKER_COUNT=0"
    printf '%s\n' "STATE=unavailable"
    printf '%s\n' "SEED_UNAVAILABLE=comments_exit=$GH_EXIT_C reviews_exit=$GH_EXIT_R"
  else
    # Union both streams into one array for counting + per-marker emission. Capture jq
    # exit so a malformed-JSON operand fails CLOSED (STATE=unavailable) rather than open:
    # without this, a jq error swallowed by 2>/dev/null leaves SEED_JSON empty and the
    # block would mislabel a real marker stream as STATE=empty ("no markers"). Mirrors the
    # per-endpoint fail-closed posture above. `add // []` still tolerates an empty/null
    # operand (the normal "one stream has no markers" case) without erroring.
    SEED_JSON=$(printf '%s\n%s\n' "$SEED_COMMENTS" "$SEED_REVIEWS" | jq -s 'add // []' 2>/dev/null); SEED_JQ_EXIT=$?
    if [ $SEED_JQ_EXIT -ne 0 ]; then
      printf '%s\n' "SEED_MARKER_COUNT=0"
      printf '%s\n' "STATE=unavailable"
      printf '%s\n' "SEED_UNAVAILABLE=union_jq_exit=$SEED_JQ_EXIT"
    else
      # Capture the count jq exit too, for the same fail-closed reason — a length()
      # failure must not collapse to a false STATE=empty.
      SEED_COUNT=$(printf '%s\n' "$SEED_JSON" | jq 'length' 2>/dev/null); SEED_COUNT_EXIT=$?
      if [ $SEED_COUNT_EXIT -ne 0 ]; then
        printf '%s\n' "SEED_MARKER_COUNT=0"
        printf '%s\n' "STATE=unavailable"
        printf '%s\n' "SEED_UNAVAILABLE=count_jq_exit=$SEED_COUNT_EXIT"
      else
        [ -z "$SEED_COUNT" ] && SEED_COUNT=0
        printf '%s\n' "SEED_MARKER_COUNT=$SEED_COUNT"
        if [ "$SEED_COUNT" = "0" ]; then
          # Genuinely absent on both surfaces (no NAME:<digits> marker reachable).
          printf '%s\n' "STATE=empty"
        else
          # The select guarantees every row has FLOW_*_CYCLE:<digits>, so scan always
          # matches; `last` takes the real marker (typically the end-of-body HTML comment)
          # when a body also carries prose references earlier.
          printf '%s\n' "$SEED_JSON" | jq -r '.[] |
            ([.body | scan("FLOW_(RESOLUTION|REVIEW)_CYCLE:([0-9]+)")] | last) as $last |
            "SEED=id=\(.id) surface=\(.surface) kind=\($last[0]) cycle=\($last[1])"
          ' 2>/dev/null
        fi
      fi
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

printf '%s\n' "### Finding-Ledger Gate"
if [ -z "$PR_NUM" ]; then
  printf '%s\n' "LEDGER_GATE_STATE=blocked"
  printf '%s\n' "FINDING_LEDGER_BLOCK: PR number required (all-digit)"
else

# Tracks whether any FINDING_LEDGER_BLOCK has been emitted. Final
# LEDGER_GATE_STATE is decided after all gate checks have run.
LEDGER_GATE_BLOCKED=0
emit_block() { LEDGER_GATE_BLOCKED=1; printf '%s\n' "FINDING_LEDGER_BLOCK: $1"; }

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
PLUGIN_SETTINGS="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/settings.json"
# The user tier is the file cascade-resolve.sh names: FLOW_USER_SETTINGS when it
# names a file, otherwise the one above. One place decides which file that is;
# an older helper without the flag leaves the one above in place.
__us=$("${PLUGIN_SETTINGS%/settings.json}/bin/cascade-resolve.sh" --user-settings-path 2>/dev/null) && USER_SETTINGS="$__us"
for SETTINGS_PATH in "$LOCAL_SETTINGS" "$PROJECT_SETTINGS" "$USER_SETTINGS" "$PLUGIN_SETTINGS"; do
  [ -f "$SETTINGS_PATH" ] || continue
  # Capture jq stderr/exit so a parse error in $HOME does not silently mask
  # a typo as "fall through to plugin default" — same pattern as the
  # agentTeams gate in commands/review.md.
  CONFIGURED=$(jq -c '.merge.markerTrust.allowedAssociations // empty' "$SETTINGS_PATH" 2>&1)
  JQ_EXIT=$?
  if [ $JQ_EXIT -ne 0 ]; then
    JQ_ERR=$(printf '%s' "$CONFIGURED" | tr '\n' ' ' | cut -c1-200)
    printf '%s\n' "WARN: failed to parse $SETTINGS_PATH (jq exit=$JQ_EXIT, error: $JQ_ERR); skipping this source" >&2
    continue
  fi
  [ -z "$CONFIGURED" ] && continue
  if printf '%s\n' "$CONFIGURED" | jq -e '. | type == "array" and length > 0 and all(.[]; type == "string")' >/dev/null 2>&1; then
    # Warn (do not block) when an element falls outside the known GitHub
    # `author_association` vocabulary. A typo such as `"owner"` (lowercase)
    # or `"MAINTAINER"` (not a real value) passes the type check above but
    # would match no real author, silently disabling trust for the mistyped
    # entry. Use the same WARN-and-continue pattern as the HIGH_RISK check
    # below — the gate already fails closed via the "untrusted-only"
    # branch when nothing matches.
    UNKNOWN_VALUES=$(printf '%s\n' "$CONFIGURED" | jq -r '.[] | select(. != "OWNER" and . != "MEMBER" and . != "COLLABORATOR" and . != "CONTRIBUTOR" and . != "FIRST_TIME_CONTRIBUTOR" and . != "FIRST_TIMER" and . != "MANNEQUIN" and . != "NONE")' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    if [ -n "$UNKNOWN_VALUES" ]; then
      printf '%s\n' "LEDGER_WARN: markerTrust in $SETTINGS_PATH contains values [$UNKNOWN_VALUES] not in the GitHub author_association vocabulary (OWNER, MEMBER, COLLABORATOR, CONTRIBUTOR, FIRST_TIME_CONTRIBUTOR, FIRST_TIMER, MANNEQUIN, NONE). These elements will match no authors — check for typos." >&2
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
    printf '%s\n' "LEDGER_WARN: invalid markerTrust configuration in $SETTINGS_PATH (must be non-empty JSON array of strings); falling through" >&2
  fi
done

# Defense-in-depth: warn (not block) when the resolved trust list contains
# high-risk values that would let a forked-PR author forge their own resolution
# markers. The cascade visibility (settings changes appear in PR diffs) is the
# primary defense; this WARN raises the signal at every merge attempt so a
# maintainer cannot accidentally miss it during a quick diff scan.
if [ -n "${TRUST_SOURCE:-}" ]; then
  HIGH_RISK=$(printf '%s\n' "$TRUST_LIST" | jq -r '.[] | select(. == "NONE" or . == "FIRST_TIMER" or . == "FIRST_TIME_CONTRIBUTOR" or . == "MANNEQUIN")' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  if [ -n "$HIGH_RISK" ]; then
    printf '%s\n' "LEDGER_WARN: trust list (from $TRUST_SOURCE) includes high-risk values [$HIGH_RISK]. Forked-PR contributors with these author_associations could forge FLOW_RESOLUTION_CYCLE markers. Verify this is intentional before merging." >&2
  fi
fi
# MARKERTRUST_GATE_END

# Trust filter applied via jq `index()` exact-match (no regex surface).
# `--paginate` keeps fetching pages so a noisy thread cannot hide forgeries.
#
# Fetch each endpoint once; reuse the cached JSON for both filter passes
# (trusted + untrusted-counting). Capturing the gh exit code via `$?` directly
# after the command substitution is the only reliable way to detect a silent
# gh failure: `VAR=$(gh ... | jq ...)` then `${PIPESTATUS[0]}` does NOT capture
# gh inner exit — bash resets PIPESTATUS to reflect only the outer assignment
# (verified: `X=$(false | true); echo ${PIPESTATUS[0]}` → 0). Without the cache
# split, a gh stderr-only failure with empty stdout would let the jq add-or-empty
# reduction succeed on null input and the gate would pass open.
GH_RES_RAW=$(gh api --paginate "repos/$REPO/issues/$PR_NUM/comments" 2>/dev/null)
GH_EXIT_RES=$?
RESOLUTION_BODY=$(printf '%s' "$GH_RES_RAW" | jq -s -r --argjson trust "$TRUST_LIST" \
    'add | [.[] | select((.author_association as $a | $trust | index($a)) and (.body | test("<!-- FLOW_RESOLUTION_CYCLE:[0-9]+ ")))] | last | .body // ""'); JQ_EXIT_RES=$?
RES_UNTRUSTED=$(printf '%s' "$GH_RES_RAW" | jq -s -r --argjson trust "$TRUST_LIST" \
    'add | [.[] | select((.author_association as $a | $trust | index($a) | not) and (.body | test("<!-- FLOW_RESOLUTION_CYCLE:[0-9]+ ")))] | length'); JQ_EXIT_RES_U=$?

# Extract ESCALATED array contents (portable POSIX grep+sed; BSD grep has no -P).
# Strip whitespace so reviewer-edited arrays like `[F1, F2]` still match.
ESCALATED=$(printf '%s\n' "$RESOLUTION_BODY" | grep -o 'ESCALATED:\[[^]]*\]' | sed 's/^ESCALATED:\[//;s/\]$//' | tr -d ' ')

# Extract the latest FLOW_REVIEW_CYCLE — emitted in PR review bodies, not issue comments
GH_REV_RAW=$(gh api --paginate "repos/$REPO/pulls/$PR_NUM/reviews" 2>/dev/null)
GH_EXIT_REV=$?
REVIEW_BODY=$(printf '%s' "$GH_REV_RAW" | jq -s -r --argjson trust "$TRUST_LIST" \
    'add | [.[] | select((.author_association as $a | $trust | index($a)) and (.body | test("<!-- FLOW_REVIEW_CYCLE:[0-9]+ ")))] | last | .body // ""'); JQ_EXIT_REV=$?
REV_UNTRUSTED=$(printf '%s' "$GH_REV_RAW" | jq -s -r --argjson trust "$TRUST_LIST" \
    'add | [.[] | select((.author_association as $a | $trust | index($a) | not) and (.body | test("<!-- FLOW_REVIEW_CYCLE:[0-9]+ ")))] | length'); JQ_EXIT_REV_U=$?

# Fail closed if either gh call failed — better to block a legitimate merge
# than silently let a regression through when the gate state is unknowable.
if [ $GH_EXIT_RES -ne 0 ] || [ $GH_EXIT_REV -ne 0 ]; then
  emit_block "gh API unavailable — cannot verify finding ledger (resolution exit=$GH_EXIT_RES, review exit=$GH_EXIT_REV)"
fi

# And fail closed if any of the four filter passes failed. gh exiting 0 does not
# mean the filter ran: one comment with a null body aborts `.body | test(...)`
# with jq exit 5, leaving RESOLUTION_BODY empty and RES_UNTRUSTED empty — which
# reads downstream as "no findings and nothing untrusted", the answer that opens
# the gate. Each pass is checked separately because each can fail alone. This is
# the posture the seed block above already takes for the same reason.
if [ $JQ_EXIT_RES -ne 0 ] || [ $JQ_EXIT_RES_U -ne 0 ] || [ $JQ_EXIT_REV -ne 0 ] || [ $JQ_EXIT_REV_U -ne 0 ]; then
  emit_block "finding-ledger markers could not be parsed — cannot verify finding ledger (jq exits: resolution=$JQ_EXIT_RES/$JQ_EXIT_RES_U, review=$JQ_EXIT_REV/$JQ_EXIT_REV_U)"
fi

# Surface "untrusted-only" markers as a block reason rather than silently
# treating them as no markers at all. This is the marker-forgery defense.
# Render the trust list as a comma-separated string for the user-facing
# message — the `$TRUST_REGEX` variable used to appear here was a leftover
# from an earlier revision and never assigned, producing the empty-parens string
# "trusted authors ()" in messages or aborting under `set -u`.
#
# Derive the fallback from $TRUST_DEFAULT rather than hard-coding the value:
# if $TRUST_DEFAULT changes (e.g., adding CONTRIBUTOR), the display string
# stays in lockstep instead of silently lying.
TRUST_LIST_DISPLAY=$(printf '%s\n' "$TRUST_LIST" | jq -r 'join(",")' 2>/dev/null)
if [ -z "$TRUST_LIST_DISPLAY" ]; then
  TRUST_LIST_DISPLAY=$(printf '%s\n' "$TRUST_DEFAULT" | jq -r 'join(",")' 2>/dev/null)
fi
if [ -z "$RESOLUTION_BODY" ] && [ "${RES_UNTRUSTED:-0}" != "0" ]; then
  emit_block "$RES_UNTRUSTED FLOW_RESOLUTION_CYCLE marker(s) found but none from trusted authors ($TRUST_LIST_DISPLAY)"
fi
if [ -z "$REVIEW_BODY" ] && [ "${REV_UNTRUSTED:-0}" != "0" ]; then
  emit_block "$REV_UNTRUSTED FLOW_REVIEW_CYCLE marker(s) found but none from trusted authors ($TRUST_LIST_DISPLAY)"
fi

# Extract all finding IDs from FINDINGS array (comma-separated, pipe-delimited fields, first field is the ID)
REVIEW_FINDINGS=$(printf '%s\n' "$REVIEW_BODY" | grep -o 'FINDINGS:\[[^]]*\]' | sed 's/^FINDINGS:\[//;s/\]$//' | tr ',' '\n' | sed 's/|.*//' | tr -d ' ' | sort)

# Extract RESOLVED finding IDs from resolution comment
RESOLVED_FINDINGS=$(printf '%s\n' "$RESOLUTION_BODY" | grep -o 'RESOLVED:\[[^]]*\]' | sed 's/^RESOLVED:\[//;s/\]$//' | tr ',' '\n' | tr -d ' ' | sort)

# Check 1: ESCALATED must be empty
if [ -n "$ESCALATED" ]; then
  emit_block "ESCALATED array is non-empty: [$ESCALATED]"
fi

# Check 2: Every finding in REVIEW_FINDINGS must have a matching RESOLVED entry
UNRESOLVED=$(comm -23 <(printf '%s\n' "$REVIEW_FINDINGS") <(printf '%s\n' "$RESOLVED_FINDINGS") | grep -v '^$' || true)
if [ -n "$UNRESOLVED" ]; then
  emit_block "Unresolved findings: $UNRESOLVED"
fi

# Emit the final gate state sentinel. The agent dispatches off this:
#   ok      → proceed to Phase 2 Display Assessment
#   blocked → halt, render the "BLOCKED: Unresolved Findings" template
#             (one FINDING_LEDGER_BLOCK line per reason was emitted above)
if [ $LEDGER_GATE_BLOCKED -eq 1 ]; then
  printf '%s\n' "LEDGER_GATE_STATE=blocked"
else
  printf '%s\n' "LEDGER_GATE_STATE=ok"
fi

fi  # /if [ -z "$PR_NUM" ]

true
```

### FlowGoal Gate (v3)

Independent of the finding-ledger gate, the FlowGoal gate **gates on goal existence**: when an active goal exists for this branch it must have reached `lifecycle.status == achieved` to merge; when **no** active goal exists the gate is **not applicable** and merge proceeds (a PR without a FlowGoal is not blocked). The gate is disabled entirely when `flow.goals.enabled` is `false` or `flow.goals.goalCreation` is `off` — preserving the v2 `requireGoalForStart: false` UX (no merge gating).

```!
HELPER="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/cascade-resolve.sh"
# Migration-aware: goalCreation wins; else map legacy requireGoalForStart
# (true->always, false->off); else null so the cascade default (auto) applies.
GOAL_MODE=$("$HELPER" --default "auto" '.flow.goals.goalCreation // (if .flow.goals.requireGoalForStart == true then "always" elif .flow.goals.requireGoalForStart == false then "off" else null end)' 2>/dev/null)
case "$GOAL_MODE" in auto|always|off) ;; *) GOAL_MODE="auto" ;; esac
ENABLED=$("$HELPER" --default "true" '.flow.goals.enabled' 2>/dev/null)
# Empty means cascade-resolve itself failed (missing/non-exec) — honor the
# enabled-by-default intent rather than fail-open to a silently disabled gate.
[ -z "$ENABLED" ] && ENABLED="true"

printf '%s\n' "### FlowGoal Gate"
if [ "$ENABLED" != "true" ] || [ "$GOAL_MODE" = "off" ]; then
  printf '%s\n' "FLOW_GOAL_GATE_STATE=disabled"
else
  ACTIVE_GOAL_HELPER="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-active-goal.sh"
  if [ ! -x "$ACTIVE_GOAL_HELPER" ]; then
    printf '%s\n' "FLOW_GOAL_GATE_STATE=blocked"
    printf '%s\n' "FLOW_GOAL_BLOCK_REASON=flow-active-goal.sh missing or non-executable"
  else
    # --allow-terminal: surface a goal that already reached `achieved` so the
    # success branch below is reachable (without it the helper is active-only,
    # exits 1, and an achieved goal is mislabeled "no active FlowGoal").
    # --branch-strict: resolve ONLY a goal owning the current branch — never a
    # stale active goal on another branch, which would falsely block this merge.
    GOAL_STATUS=$("$ACTIVE_GOAL_HELPER" --status --allow-terminal --branch-strict 2>/dev/null); GOAL_EXIT=$?
    case "$GOAL_EXIT" in
      0)
        GOAL_ID=$("$ACTIVE_GOAL_HELPER" --id --allow-terminal --branch-strict 2>/dev/null)
        printf '%s\n' "FLOW_GOAL_ID=$GOAL_ID"
        printf '%s\n' "FLOW_GOAL_LIFECYCLE=$GOAL_STATUS"
        if [ "$GOAL_STATUS" = "achieved" ]; then
          printf '%s\n' "FLOW_GOAL_GATE_STATE=ok"
        else
          # Active goal exists but is not achieved — fail closed.
          # The "no incomplete shipments" hard boundary applies: merging a
          # PR whose own contract reports incomplete is exactly what the
          # "no incomplete shipments" boundary is designed to prevent.
          printf '%s\n' "FLOW_GOAL_GATE_STATE=blocked"
          printf '%s\n' "FLOW_GOAL_BLOCK_REASON=FlowGoal $GOAL_ID lifecycle is '$GOAL_STATUS' — run /flow:goal evaluate $GOAL_ID to advance"
        fi
        ;;
      1)
        # No active goal on this branch — gate not applicable: the gate keys
        # on goal existence. A PR without a FlowGoal is not blocked; the PR
        # own review state remains the durable record. This intentionally
        # replaces the prior fail-closed so default installs (goalCreation:auto)
        # do not start blocking goal-less merges.
        printf '%s\n' "FLOW_GOAL_GATE_STATE=ok"
        printf '%s\n' "FLOW_GOAL_GATE_NOTE=no active FlowGoal for this branch — gate not applicable"
        ;;
      3)
        # >1 active goal on the current branch (after branch-scoping).
        printf '%s\n' "FLOW_GOAL_GATE_STATE=blocked"
        printf '%s\n' "FLOW_GOAL_BLOCK_REASON=degenerate state — multiple active FlowGoals on the current branch"
        ;;
      *)
        printf '%s\n' "FLOW_GOAL_GATE_STATE=blocked"
        printf '%s\n' "FLOW_GOAL_BLOCK_REASON=flow-active-goal.sh exited $GOAL_EXIT"
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
CASCADE="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/cascade-resolve.sh"
if [ ! -x "$CASCADE" ]; then
  printf '%s\n' "FLOW_RUN_STATE=blocked"
  printf '%s\n' "FLOW_RUN_ERROR=cascade-resolve.sh missing or non-executable at $CASCADE"
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
  printf '%s\n' "FLOW_RUN_STATE=skip"
  printf '%s\n' "FLOW_RUN_REASON=flow.runtime.enabled is not true (v2 mode)"
else
  SLUG="${PR_NUM:-nonum}"
  RUN_ID="$(date -u +%Y-%m-%dT%H%M%SZ)-merge-pr-${SLUG}"
  printf '%s\n' "FLOW_RUN_STATE=create"
  printf '%s\n' "RUN_ID=$RUN_ID"
  printf '%s\n' "WORKFLOW=merge-pr"
  printf '%s\n' "INITIAL_PHASE=preflight"
fi
# FLOW_RUN_BLOCK_END
true
```

When `FLOW_RUN_STATE=create`, invoke `Skill(run-state-management)` to create `.flow/runs/$RUN_ID/run.yaml` (workflow=`merge-pr`, goal=`null` — the merge reads the linked FlowGoal for the gate below but the run itself is not goal-owned), initial phase `preflight`. Phase order: `preflight → verify → confirm → merge`. Write a FlowActivity at each boundary (verify, confirm, merge).

**Linked-run completion check** (Phase 2 / verify): before allowing merge, verify that every FlowRun linked to this PR's branch (the `start-issue` run and any `address-pr` / `review-pr` runs) has reached `state.status: completed`. If any linked run is still `active`, refuse the merge — this is Tier 3, so there is **no override** beyond the standard merge confirmation. Surface the still-active run id and point to `/flow:resume`.

### Merge Settings

The strategy and branch deletion the confirmation names, and the merge in Phase 3 uses. Read here so both come from the settings rather than from a default the model assumes.

```!
# MERGE_SETTINGS_BLOCK_BEGIN
printf '%s\n' "### Merge Settings"
CASCADE="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/cascade-resolve.sh"
if [ ! -x "$CASCADE" ]; then
  printf '%s\n' "MERGE_SETTINGS_STATE=blocked"
  printf '%s\n' "ERROR=cascade-resolve.sh missing or non-executable at $CASCADE; the merge settings cannot be read"
  true; exit 0
fi
# Resolved WITHOUT --default, deliberately. A setting that is ABSENT should fall
# back to squash/true; a setting that could not be READ — cascade-resolve.sh
# refuses a value carrying a control character, exit 2 — must not, or this gate
# prints MERGE_SETTINGS_STATE=ok for a settings file it could not read, which is
# the same answer it prints for a valid one. That is the defect class this whole
# change is about, so the two are told apart here: exit 2 is blocked, empty is
# absent.
# stderr is CAPTURED, not discarded. cascade-resolve.sh has three ways to fail to
# hand back a value, and only one of them is an exit code: a refusal exits 2, but
# a settings file that cannot be opened or cannot be PARSED is skipped with a
# warning on stderr and exit 0, leaving empty output that reads exactly like an
# absent key. Both are "this block could not read your settings" and neither may
# look like "you did not set it". For an irreversible merge, any warning is
# treated as unreadable.
#
# No temp file: `rm` is a destructive verb and this repository forbids those
# inside an inline-bang block, with a test that enforces it. Merging the streams
# is enough because the two are disjoint — a clean resolve prints the value and
# nothing else, and every warning cascade-resolve emits is prefixed with its own
# name, which no value accepted below can contain.
MERGE_OUT=$("$CASCADE" '.merge.strategy' 2>&1); RC_STRATEGY=$?
# Collapsed to one line: cascade-resolve emits one warning per source it had to
# skip, so this is multi-line as soon as two are unreadable, and a multi-line
# value here re-opens through the error path exactly the forgery this block was
# hardened against.
MERGE_OUT=$(printf '%s' "$MERGE_OUT" | tr '\n\r' '  ')
case "$MERGE_OUT" in
  *cascade-resolve:*)
    printf '%s\n' "MERGE_SETTINGS_STATE=blocked"
    printf '%s\n' "ERROR=merge.strategy could not be read (cascade-resolve.sh exit $RC_STRATEGY): $MERGE_OUT; refusing to guess a strategy for an irreversible merge"
    true; exit 0 ;;
esac
if [ "$RC_STRATEGY" -ne 0 ]; then
  printf '%s\n' "MERGE_SETTINGS_STATE=blocked"
  printf '%s\n' "ERROR=merge.strategy could not be read (cascade-resolve.sh exit $RC_STRATEGY); refusing to guess a strategy for an irreversible merge"
  true; exit 0
fi
MERGE_STRATEGY="$MERGE_OUT"
[ -n "$MERGE_STRATEGY" ] || MERGE_STRATEGY="squash"
MERGE_OUT=$("$CASCADE" '.merge.deleteBranch' 2>&1); RC_DELETE=$?
MERGE_OUT=$(printf '%s' "$MERGE_OUT" | tr '\n\r' '  ')
case "$MERGE_OUT" in
  *cascade-resolve:*)
    printf '%s\n' "MERGE_SETTINGS_STATE=blocked"
    printf '%s\n' "ERROR=merge.deleteBranch could not be read (cascade-resolve.sh exit $RC_DELETE): $MERGE_OUT; refusing to guess whether the branch is deleted"
    true; exit 0 ;;
esac
if [ "$RC_DELETE" -ne 0 ]; then
  printf '%s\n' "MERGE_SETTINGS_STATE=blocked"
  printf '%s\n' "ERROR=merge.deleteBranch could not be read (cascade-resolve.sh exit $RC_DELETE); refusing to guess whether the branch is deleted"
  true; exit 0
fi
DELETE_BRANCH="$MERGE_OUT"
[ -n "$DELETE_BRANCH" ] || DELETE_BRANCH="true"
case "$MERGE_STRATEGY" in
  squash|merge|rebase) ;;
  *)
    # Safe to quote because cascade-resolve.sh refuses a value carrying a
    # control character by default, so this can only ever be a single line.
    printf '%s\n' "MERGE_SETTINGS_STATE=blocked"
    printf '%s\n' "ERROR=merge.strategy is '$MERGE_STRATEGY'; it must be squash, merge or rebase"
    true; exit 0 ;;
esac
case "$DELETE_BRANCH" in
  true|false) ;;
  *)
    printf '%s\n' "MERGE_SETTINGS_STATE=blocked"
    printf '%s\n' "ERROR=merge.deleteBranch is '$DELETE_BRANCH'; it must be true or false"
    true; exit 0 ;;
esac
printf '%s\n' "MERGE_SETTINGS_STATE=ok"
printf '%s\n' "MERGE_STRATEGY=$MERGE_STRATEGY"
printf '%s\n' "DELETE_BRANCH=$DELETE_BRANCH"
# MERGE_SETTINGS_BLOCK_END
true
```

On `MERGE_SETTINGS_STATE=blocked`, report the error and stop: a merge whose strategy is unknown cannot be confirmed.

## Phase 2: Display Assessment

```markdown
## Merge Assessment for PR #$PR_NUM

| Check | Status | Details |
|-------|--------|---------|
| Repository | {Pass/Fail} | {owner/name, cross-check ok / mismatch} |
| Approval | {Pass/Fail} | {N approvals, latest by @X} |
| CI Checks | {Pass/Fail} | {N passed, M failed, K unfinished} |
| Required Checks | {Yes/None} | {required contexts, or "none required on `<base>`"} |
| Mergeable | {Pass/Fail} | {No conflicts / Has conflicts} |
| Conversations | {Pass/Fail} | {All resolved / N unresolved} |
| Stale Approval | {OK/Warning} | {Fresh / Commits after approval} |
| Finding Ledger | {Pass/Fail} | {All resolved / N unresolved, M escalated} |

**Merge strategy**: {MERGE_STRATEGY from Merge Settings}
**Delete branch**: {DELETE_BRANCH from Merge Settings}
```

The Repository row exists because every field above it was read from one
repository, and until it is named nobody can tell which. `REPO_CROSSCHECK` in
the preflight compares what `gh` resolved against what `git remote get-url
origin` says; on `mismatch` the preflight sets `REPO_STATE=blocked` and this
command stops rather than reporting a well-formed answer about a different
repository.

### Why `--auto` is not a way to wait

GitHub auto-merge waits for **required** status checks. On a repository with no
branch protection and no ruleset requiring one, nothing is required, so
`gh pr merge --auto` merges immediately. That is the opposite of what the flag
is usually reached for.

Either confirm the checks have finished — `gh pr checks <N> --watch` — and merge
without the flag, or require the checks on the base branch so the flag has
something to wait for. Whether a repository configures required checks is the
repository's decision; the point is not to mistake their absence for a passing
gate.

The `block-unchecked-merge.sh` PreToolUse hook enforces both halves for merges
that do not come through this command: it refuses a `gh pr merge` while any
check is queued, running or failed, and refuses `--auto` on a base branch that
requires nothing. It reads the command as text, so it checks a merge only in
one shape — `gh pr merge <number> --repo owner/name --squash|--merge|--rebase`
with long options and literal values — and refuses any other. The merge in
Phase 3 is written in that shape.

The Required Checks row is not decoration. "All checks passed" and "no checks
are required here" are different facts, and only the first is a gate. Where the
base branch requires nothing, say so — and never reach for `--auto` there,
because auto-merge waits for required checks and merges at once when there are
none.

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

Stop here, without asking, unless the preflight printed `REPO_CROSSCHECK=ok`
and Merge Settings printed `MERGE_SETTINGS_STATE=ok`.
`REPO_STATE=unavailable` means no repository was resolved, `REPO_STATE=blocked`
means `gh` and `git` named different ones, and `REPO_CROSSCHECK=unavailable`
means there was no origin remote to verify against. In each case the merge
below would have to name a repository nobody verified. Report the state and
what the user can do about it.

Use the AskUserQuestion tool with contextual options to confirm, naming what
will actually run: "PR #{PR_NUMBER} in {OWNER/NAME} is ready to merge. Proceed
with a {strategy} merge{, deleting the branch}?" — the strategy and the branch
clause come from `MERGE_STRATEGY` and `DELETE_BRANCH` in Merge Settings, so the
user approves the same merge that runs.

Only after the user confirms via the tool, run the merge with every value
written literally. Replace each `{…}` below before running:

- `{PR_NUMBER}` — the PR number from the report
- `{OWNER/NAME}` — the report's Repository row
- `{STRATEGY}` — `MERGE_STRATEGY` from Merge Settings
- `{DELETE_BRANCH}` — `--delete-branch` when `DELETE_BRANCH=true`; remove it
  when false

If the merge is refused — by the hook, or by GitHub — stop and report the
refusal as it was printed. Do not run Phase 4, and do not retry the merge in
another form.

```bash
# Literal values, not $PR_NUM or $REPO. block-unchecked-merge.sh reads this
# command as text and cannot expand a variable, so a variable (or a {…} left
# unfilled) is refused. --repo pins the merge to the repository the preflight
# read. No --auto: it waits for REQUIRED checks, so on a repository that
# requires none it merges immediately; the gate above is what establishes the
# checks have finished.
gh pr merge {PR_NUMBER} --repo {OWNER/NAME} --{STRATEGY} {DELETE_BRANCH}
```

## Phase 4: Post-Merge

```bash
# $REPO does not survive from the preflight block: each fence is its own
# shell. Resolved again here, because `gh --repo ""` falls back to the default
# resolution of gh without complaining — an unset REPO reads as pinned and behaves
# as unpinned, which is the failure this pinning exists to prevent.
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
[ -n "$REPO" ] || { printf '%s\n' "ERROR: cannot resolve the repository; refusing to act on an unattributable pull request" >&2; exit 1; }
# PR_NUM does not survive either. Without it `gh pr view ""` resolves the
# current branch and reports on a different pull request, or on none.
_RAW="$ARGUMENTS"  # Claude Code substitutes the bare arg token, not bash parameter-expansion
ARG1="${_RAW%% *}"
case "$ARG1" in
  ''|*[!0-9]*) printf '%s\n' "ERROR: PR number required (all-digit)" >&2; exit 1 ;;
  *) PR_NUM="$ARG1" ;;
esac
# Verify merge. Switching branches after a merge that did not happen would
# leave the work checked out nowhere useful and report success anyway.
STATE=$(gh pr view "$PR_NUM" --repo "$REPO" --json state --jq '.state' 2>/dev/null)
[ "$STATE" = "MERGED" ] || { printf '%s\n' "ERROR: PR #$PR_NUM in $REPO is '${STATE:-unreadable}', not MERGED; stopping before any checkout" >&2; exit 1; }

# Switch to default branch
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || printf '%s\n' "main")
git checkout $DEFAULT_BRANCH
git pull origin $DEFAULT_BRANCH
```

**FlowRun terminal transition** (when `FLOW_RUN_STATE=create`): after a successful merge, invoke `Skill(run-state-management)` to transition the `merge-pr` FlowRun to `state.status: completed` and update its `workflow-run` journal artifact to `status=completed`. Then transition the linked FlowGoal to a terminal status if it is not already — the merge itself is the achievement signal. If the merge was cancelled, transition the run to `cancelled` (with `blocked_reason`) so it is not treated as resumable.

**Manifest emit** — if this merge resolved any escalations (a Proactive-Autonomy escalation surfaced via `AskUserQuestion` during Phase 1's finding-ledger check, Phase 2's stale-approval warning, or the conflict-resolution path closed because the user provided one of the six canonical fields), record an `escalation-resolved` artifact for each:

```bash
# ESCALATION_RESOLVED_BLOCK_BEGIN
# $REPO does not survive from the preflight block: each fence is its own
# shell. Resolved again here, because `gh --repo ""` falls back to the default
# resolution of gh without complaining — an unset REPO reads as pinned and behaves
# as unpinned, which is the failure this pinning exists to prevent.
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
[ -n "$REPO" ] || { printf '%s\n' "ERROR: cannot resolve the repository; refusing to act on an unattributable pull request" >&2; exit 1; }
# PR_NUM does not survive from earlier blocks either.
_RAW="$ARGUMENTS"  # Claude Code substitutes the bare arg token, not bash parameter-expansion
ARG1="${_RAW%% *}"
case "$ARG1" in
  ''|*[!0-9]*) printf '%s\n' "ERROR: PR number required (all-digit)" >&2; exit 1 ;;
  *) PR_NUM="$ARG1" ;;
esac
# The issue GitHub lists the pull request as closing (the lowest when there
# are several), never the first #N in the body.
FLOW_ROOT="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")"
ISSUE=$("$FLOW_ROOT/bin/flow-pr-linked-issue.sh" --pr "$PR_NUM" --repo "$REPO") || { printf '%s\n' "ERROR: cannot read the issues pull request $PR_NUM closes; refusing to guess its linked issue" >&2; exit 1; }
if [ -z "$ISSUE" ]; then
  printf '%s\n' "ESCALATION_RECORD=skipped (GitHub lists no issue this pull request closes, so there is no journal to record it in)"
else
  # Repeat once per escalation that closed during this merge run. Set
  # ESCALATION_FIELD to the one canonical field that gated it and OUTCOME to a
  # one-line summary of the user's answer; they are values this block
  # validates, not placeholders to edit in place, so an unsubstituted one
  # cannot be recorded as the field name.
  case "${ESCALATION_FIELD:-}" in
    situation|tried|options|recommendation|blocking|risk) ;;
    *) printf '%s\n' "ERROR: ESCALATION_FIELD must be one of situation, tried, options, recommendation, blocking, risk; got '${ESCALATION_FIELD:-}'" >&2; exit 1 ;;
  esac
  case "${OUTCOME:-}" in
    ''|*'{'*|*'}'*) printf '%s\n' "ERROR: OUTCOME must be a one-line summary of the user's answer, got '${OUTCOME:-}'" >&2; exit 1 ;;
  esac
  "$FLOW_ROOT/bin/journal-record.sh" \
    --issue "$ISSUE" \
    --type escalation-resolved \
    --metadata "escalation_field=$ESCALATION_FIELD" \
    --metadata "outcome=$OUTCOME"
fi
# ESCALATION_RESOLVED_BLOCK_END
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
