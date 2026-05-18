---
description: "Display a read-only overview of workflow state including assigned issues, open PRs, pending reviews, branch state, and decision journal health. Use when checking current development status."
allowed-tools: Bash, Read
---

# Workflow Status

Read-only overview of the current development state. No skills needed — pure observation.

## Required Skills

_None — read-only status command. No skill invocations._

## Gather State

```!
# Output contract: `###`-headed sections mirroring the Display template below
# (Current Branch / My Issues (Open) / My PRs / Awaiting My Review /
# Decision Journal). Scalars use KEY=value; records use one labeled line per
# entity (ISSUE=… / PR=…). Empty list-sections emit `STATE=empty` as a
# positive sentinel — the agent matches a closed vocabulary, not silence.
# See `references/command-output-format.md` for the canonical pattern.

# Section: Current Branch
echo "### Current Branch"
BRANCH=$(git branch --show-current 2>/dev/null)
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
COMMITS_AHEAD=$(git rev-list --count "$DEFAULT_BRANCH"..HEAD 2>/dev/null || echo "0")
UNCOMMITTED_COUNT=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
echo "BRANCH=$BRANCH"
echo "DEFAULT_BRANCH=$DEFAULT_BRANCH"
echo "COMMITS_AHEAD=$COMMITS_AHEAD"
echo "UNCOMMITTED_COUNT=$UNCOMMITTED_COUNT"
[ "$UNCOMMITTED_COUNT" != "0" ] && git status --short 2>/dev/null | head -20 | sed 's/^/UNCOMMITTED_LINE=/'

# Section: My Issues (Open)
# Capture gh exit separately across all three sections below: gh failure
# (auth, network, non-repo CWD) returns "" with non-zero exit; jq on empty
# input produces no output + exit 0 (jq 1.8), so `|| echo "0"` doesn't fire
# and the section silently leaks `<KEY>_COUNT=` (bare empty). Distinguish
# `STATE=unavailable` (gh failed) from `STATE=empty` (gh ok, no records) per
# `references/command-output-format.md` closed-vocab contract.
echo ""
echo "### My Issues (Open)"
ASSIGNED_JSON=$(gh issue list --assignee @me --state open --limit 10 --json number,title,labels 2>/dev/null); GH_EXIT=$?
if [ $GH_EXIT -ne 0 ]; then
  echo "ASSIGNED_COUNT=0"
  echo "STATE=unavailable"
else
  ASSIGNED_COUNT=$(echo "$ASSIGNED_JSON" | jq 'length' 2>/dev/null)
  [ -z "$ASSIGNED_COUNT" ] && ASSIGNED_COUNT=0
  echo "ASSIGNED_COUNT=$ASSIGNED_COUNT"
  if [ "$ASSIGNED_COUNT" = "0" ]; then
    echo "STATE=empty"
  else
    echo "$ASSIGNED_JSON" | jq -r '.[] | "ISSUE=\(.number) labels=\"\([.labels[].name] | join(","))\" title=\"\(.title)\""' 2>/dev/null
  fi
fi

# Section: My PRs (authored)
echo ""
echo "### My PRs"
AUTHORED_JSON=$(gh pr list --author @me --state open --json number,title,state,reviewDecision,statusCheckRollup 2>/dev/null); GH_EXIT=$?
if [ $GH_EXIT -ne 0 ]; then
  echo "AUTHORED_COUNT=0"
  echo "STATE=unavailable"
else
  AUTHORED_COUNT=$(echo "$AUTHORED_JSON" | jq 'length' 2>/dev/null)
  [ -z "$AUTHORED_COUNT" ] && AUTHORED_COUNT=0
  echo "AUTHORED_COUNT=$AUTHORED_COUNT"
  if [ "$AUTHORED_COUNT" = "0" ]; then
    echo "STATE=empty"
  else
    echo "$AUTHORED_JSON" | jq -r '.[] | (
      [.statusCheckRollup[]? | select(.__typename == "CheckRun")] as $checks |
      (if (.reviewDecision // "") == "" then "(none)" else .reviewDecision end) as $review |
      "PR=\(.number) state=\(.state) review=\($review) checks=\($checks | map(select(.conclusion == "SUCCESS")) | length)/\($checks | length) title=\"\(.title)\""
    )' 2>/dev/null
  fi
fi

# Section: Awaiting My Review
echo ""
echo "### Awaiting My Review"
REVIEW_JSON=$(gh pr list --search "review-requested:@me" --state open --json number,title,author 2>/dev/null); GH_EXIT=$?
if [ $GH_EXIT -ne 0 ]; then
  echo "REVIEW_REQUESTED_COUNT=0"
  echo "STATE=unavailable"
else
  REVIEW_REQUESTED_COUNT=$(echo "$REVIEW_JSON" | jq 'length' 2>/dev/null)
  [ -z "$REVIEW_REQUESTED_COUNT" ] && REVIEW_REQUESTED_COUNT=0
  echo "REVIEW_REQUESTED_COUNT=$REVIEW_REQUESTED_COUNT"
  if [ "$REVIEW_REQUESTED_COUNT" = "0" ]; then
    echo "STATE=empty"
  else
    echo "$REVIEW_JSON" | jq -r '.[] | "PR=\(.number) author=@\(.author.login) title=\"\(.title)\""' 2>/dev/null
  fi
fi

# Section: Decision Journal + Learning state
# `JOURNAL_DIR` is resolved via the standard settings cascade (bin/cascade-resolve.sh).
echo ""
echo "### Decision Journal"
HELPER="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh"
JOURNAL_DIR=".decisions"
[ -x "$HELPER" ] && JOURNAL_DIR=$("$HELPER" --default ".decisions" '.journal.dir // empty')
JOURNAL_FILES=0
[ -d "$JOURNAL_DIR" ] && JOURNAL_FILES=$(ls "$JOURNAL_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
echo "JOURNAL_DIR=$JOURNAL_DIR"
echo "JOURNAL_FILES=$JOURNAL_FILES"
if [ -f "$HOME/.claude/flow-learn-pending" ]; then
  echo "LEARNING_PENDING=$(cat "$HOME/.claude/flow-learn-pending")"
else
  echo "LEARNING_PENDING=none"
fi

true
```

## Gather Findings Ledger

Aggregate review findings across the user's open PRs (author OR assignee). See [`references/finding-ledger-parser.md`](../references/finding-ledger-parser.md) for the canonical marker schemas, queries, and state classification — the bash below applies that contract.

```!
ME=$(gh api user --jq '.login' 2>/dev/null)
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)

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
    # Warn (don't block) when an element falls outside the known GitHub
    # `author_association` vocabulary — same defense-in-depth check as
    # commands/merge.md, mirrored here so a typo surfaces during the
    # aggregator pass too (matches the /flow:status read-only contract).
    UNKNOWN_VALUES=$(echo "$CONFIGURED" | jq -r '.[] | select(. != "OWNER" and . != "MEMBER" and . != "COLLABORATOR" and . != "CONTRIBUTOR" and . != "FIRST_TIME_CONTRIBUTOR" and . != "FIRST_TIMER" and . != "MANNEQUIN" and . != "NONE")' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    if [ -n "$UNKNOWN_VALUES" ]; then
      echo "LEDGER_WARN: markerTrust in $SETTINGS_PATH contains values [$UNKNOWN_VALUES] not in the GitHub author_association vocabulary (OWNER, MEMBER, COLLABORATOR, CONTRIBUTOR, FIRST_TIME_CONTRIBUTOR, FIRST_TIMER, MANNEQUIN, NONE). These elements will match no authors — check for typos." >&2
    fi
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

echo "### Findings Ledger"
if [ "$LEDGER_PRS" = "LEDGER_UNAVAILABLE" ]; then
  echo "LEDGER_STATE=unavailable"
elif [ -z "$LEDGER_PRS" ]; then
  echo "LEDGER_STATE=no_open_prs"
else
  # Sanitize attacker-controlled fields before display/echo: cap length and
  # strip non-printable bytes so a hostile review-body can't inject ANSI
  # escapes into LEDGER_WARN output. Defined once for the whole loop.
  safe() { printf '%s' "$1" | tr -cd '[:print:]' | cut -c1-64; }
  # Generate the PRIORITY|STATE tally to a variable so we can distinguish
  # "no markers" (empty TALLY) from "findings present" (non-empty) and emit
  # the right LEDGER_STATE sentinel for each.
  #
  # Wrapped in a function because bash's `$(...)` paren-matching collides
  # with the `*)` patterns in the nested `case` statements below — the outer
  # substitution would close on the first case-arm paren. Function isolation
  # gives the case statements their own parse scope.
  _collect_tally() {
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

    # CAT and LOC are parsed but unused inside this loop — drop them with `_`
    # so future code additions can't accidentally interpolate attacker-controlled
    # fields without first applying `safe()` sanitization. If a future change
    # needs them, replace `_ _` with named vars AND wrap each use with `safe()`.
    echo "$FINDINGS_RAW" | tr ',' '\n' | while IFS='|' read -r ID PRIORITY _ _ STATUS; do
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
  }
  TALLY=$(_collect_tally)

  if [ -z "$TALLY" ]; then
    echo "LEDGER_STATE=no_markers"
  else
    echo "LEDGER_STATE=findings"
    # Emit one TALLY_<PRIORITY>_<STATE>=COUNT line per row. The agent sums
    # across STATE for each priority to render the Findings Ledger line per
    # the rules in `## Render Rules` below.
    echo "$TALLY" | while read -r count rest; do
      ROW_PRIORITY="${rest%%|*}"
      ROW_STATE="${rest#*|}"
      echo "TALLY_${ROW_PRIORITY}_${ROW_STATE}=$count"
    done
  fi
fi

true
```

The block emits one of four `LEDGER_STATE=` values, followed (only when `LEDGER_STATE=findings`) by one `TALLY_<PRIORITY>_<STATE>=<count>` line per `(priority, state)` row in the tally:

```
### Findings Ledger
LEDGER_STATE=findings
TALLY_P1_in_fix_forward=2
TALLY_P2_escalated=1
TALLY_P3_in_fix_forward=3
```

State values: `unavailable` (gh API failed) | `no_open_prs` (user has no open PRs) | `no_markers` (open PRs exist but no review markers parsed) | `findings` (at least one tally row follows). Render rules below convert the `TALLY_` lines into the single-line Findings Ledger output.

## Display

```markdown
## Flow Status

### Current Branch
- **Branch**: {branch name}
- **Commits ahead**: {N} ahead of {default branch}
- **Uncommitted changes**: {count} files

### My Issues (Open)
| # | Title | Labels |
|---|-------|--------|
| {N} | {title} | {labels} |

### My PRs
| # | Title | Status | Checks |
|---|-------|--------|--------|
| {N} | {title} | {review status} | {check status} |

### Awaiting My Review
| # | Title | Author |
|---|-------|--------|
| {N} | {title} | @{author} |

### Decision Journal
- **Journals**: {N} active
- **Learning**: {pending/none}

### Findings Ledger
{single line: `P1: {n}[ (annotation)]    P2: {n}[ (annotation)]    P3: {n}[ (annotation)]` — annotations are omitted when count is 0; see render rules below}

### Suggested Next Action
{Based on state, suggest the most useful /flow command}
```

## Render Rules — Findings Ledger

Convert the `TALLY_<PRIORITY>_<STATE>=<count>` lines from the gather step into one Findings Ledger line. For each priority P1, P2, P3:

1. Sum all `TALLY_P{n}_*` counts. Call this `K`.
2. `K == 0` → emit `P{n}: 0` (bare).
3. `K > 0` and only one `TALLY_P{n}_*` row present → emit `P{n}: K (state-label)`.
4. `K > 0` and multiple `TALLY_P{n}_*` rows → emit `P{n}: K (a STATE_A; b STATE_B)`, where `a, b` are the per-state counts.

State labels (the `STATE` portion of the `TALLY_` key, mapped to a human-readable label):

| State (key suffix) | Label |
|-------|-------|
| `in_fix_forward` | `in fix-forward` |
| `escalated` | `ESCALATED` |
| `disputed` | `DISPUTED` |

Edge cases (driven by `LEDGER_STATE=`, NOT by silence):

- `LEDGER_STATE=unavailable` → `Findings Ledger unavailable — gh API failed.`
- `LEDGER_STATE=no_open_prs` → `No open findings.`
- `LEDGER_STATE=no_markers` → `No open findings.`
- `LEDGER_STATE=findings` → apply the per-priority rules above.

Format matches the workshop slide mockup in `docs/flow-team-session/slides.md` (`/flow:status — what to expect` section, Findings Ledger row).

## Suggestions Logic

| State | Suggestion |
|-------|-----------|
| On default branch, no assigned issues | "Assign an issue or `/flow:start <N>`" |
| On default branch, has assigned issue | "`/flow:start {first-issue-number}`" |
| On feature branch, uncommitted changes | "`/flow:commit`" |
| On feature branch, commits ahead, no PR | "`/flow:pr`" |
| Has PR with review comments | "`/flow:address {pr-number}`" |
| Has PR approved | "`/flow:merge {pr-number}`" |
| PRs awaiting review | "`/flow:review {first-pr-number}`" |
| Learning pending | "`/flow:learn`" |

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read git state / branch / commits-ahead | 1 | Autonomous, read-only |
| `gh issue list` / `gh pr list` (assigned + reviewing) | 1 | Autonomous, read-only |
| Read `.decisions/` journal directory | 1 | Autonomous, read-only |
| Read `~/.claude/flow-learn-pending` flag | 1 | Autonomous, read-only |
| Findings-ledger aggregation across open PRs (`gh api` paginated) | 1 | Autonomous, read-only |
| Render status tables | 1 | Autonomous, output-only |

`/flow:status` makes **zero mutations**. It cannot create branches, commit files, push, post comments, create issues, or change settings. Every action is a read; every output is a render.
