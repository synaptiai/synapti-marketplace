---
description: "Display a read-only overview of workflow state including assigned issues, open PRs, pending reviews, branch state, and decision journal health. Use when checking current development status."
allowed-tools: Bash, Read
---

# Workflow Status

Read-only overview of the current development state. No skills needed — pure observation.

## Required Skills

_None — read-only status command. No skill invocations._

## Gather State

Execute all queries in parallel:

```bash
# 1. Current branch and uncommitted changes
git branch --show-current
git status --short | head -20

# 2. Commits ahead of default branch
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
git rev-list --count "$DEFAULT_BRANCH"..HEAD 2>/dev/null || echo "0"

# 3. Assigned issues
gh issue list --assignee @me --state open --limit 10 --json number,title,labels

# 4. Open PRs (authored)
gh pr list --author @me --state open --json number,title,state,reviewDecision,statusCheckRollup

# 5. PRs needing my review
gh pr list --search "review-requested:@me" --state open --json number,title,author

# 6. Decision journal health
JOURNAL_DIR=".decisions"
[ -d "$JOURNAL_DIR" ] && ls -la "$JOURNAL_DIR"/*.md 2>/dev/null | wc -l || echo "0"

# 7. Learning pending
[ -f "$HOME/.claude/flow-learn-pending" ] && echo "LEARNING PENDING: $(cat $HOME/.claude/flow-learn-pending)" || echo "No pending learning"
```

## Gather Findings Ledger

Aggregate review findings across the user's open PRs (author OR assignee). See [`references/finding-ledger-parser.md`](../references/finding-ledger-parser.md) for the canonical marker schemas, queries, and state classification — the bash below applies that contract.

```bash
ME=$(gh api user --jq '.login')
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')

# Enumerate PRs (author OR assignee)
LEDGER_PRS=$(gh pr list --state open --limit 100 --json number,author,assignees 2>/dev/null \
  | jq -r --arg me "$ME" \
      '[.[] | select(.author.login == $me or (.assignees[].login? == $me))] | .[].number' \
  2>/dev/null || echo "LEDGER_UNAVAILABLE")

if [ "$LEDGER_PRS" = "LEDGER_UNAVAILABLE" ]; then
  echo "LEDGER: unavailable (gh API failed)"
else
  # Counters keyed by priority (P1/P2/P3) and state (in_fix_forward/escalated/disputed)
  declare -A LEDGER
  TOTAL_FINDINGS=0
  for PR_NUM in $LEDGER_PRS; do
    REVIEW_BODY=$(gh api "repos/$REPO/pulls/$PR_NUM/reviews" \
      --jq '[.[] | select(.body | test("FLOW_REVIEW_CYCLE:"))] | last | .body // ""' 2>/dev/null)
    FINDINGS_RAW=$(echo "$REVIEW_BODY" | grep -o 'FINDINGS:\[[^]]*\]' | sed 's/^FINDINGS:\[//;s/\]$//' || echo "")
    [ -z "$FINDINGS_RAW" ] && continue

    RESOLUTION_BODY=$(gh api "repos/$REPO/issues/$PR_NUM/comments" \
      --jq '[.[] | select(.body | test("FLOW_RESOLUTION_CYCLE:"))] | last | .body // ""' 2>/dev/null)
    RESOLVED=$(echo "$RESOLUTION_BODY" | grep -o 'RESOLVED:\[[^]]*\]' | sed 's/^RESOLVED:\[//;s/\]$//' || echo "")
    ESCALATED=$(echo "$RESOLUTION_BODY" | grep -o 'ESCALATED:\[[^]]*\]' | sed 's/^ESCALATED:\[//;s/\]$//' || echo "")
    DISPUTED=$(echo "$RESOLUTION_BODY" | grep -o 'DISPUTED:\[[^]]*\]' | sed 's/^DISPUTED:\[//;s/\]$//' || echo "")

    echo "$FINDINGS_RAW" | tr ',' '\n' | while IFS='|' read -r ID PRIORITY CAT LOC STATUS; do
      [ -z "$ID" ] && continue
      # Defensive: skip entries that don't conform to ID|P[1-3]|... schema
      case "$PRIORITY" in P1|P2|P3) ;; *) continue ;; esac
      case ",$RESOLVED," in *",$ID,"*) continue ;; esac
      case ",$ESCALATED," in *",$ID,"*) STATE=escalated ;;
        *) case ",$DISPUTED," in *",$ID,"*) STATE=disputed ;;
             *) STATE=in_fix_forward ;; esac ;;
      esac
      echo "${PRIORITY}|${STATE}"
    done
  done | sort | uniq -c
fi
```

The output of the loop is a tally like:

```
   2 P1|in_fix_forward
   1 P2|escalated
   3 P3|in_fix_forward
```

Use this to render the Findings Ledger line per priority. If the loop produces no rows AND `LEDGER_PRS` was non-empty, the user has open PRs but no review markers yet — render `No open findings`.

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
{single line: `P1: {n}    P2: {n} (annotation)    P3: {n} (annotation)` — see render rules below}

### Suggested Next Action
{Based on state, suggest the most useful /flow command}
```

## Render Rules — Findings Ledger

Convert the `PRIORITY|STATE` tally from the gather step into one line. Per-priority rules:

- `0` findings at this priority → `P{n}: 0` (bare).
- All findings at this priority share one state → `P{n}: K (state-label)`.
- Multiple states at this priority → `P{n}: K (a STATE_A; b STATE_B)`.

State labels:

| State | Label |
|-------|-------|
| `in_fix_forward` | `in fix-forward` |
| `escalated` | `ESCALATED` |
| `disputed` | `DISPUTED` |

Edge cases:

- `LEDGER_PRS` empty (no open PRs for user) → `No open findings.`
- `LEDGER_PRS` non-empty but tally empty (no markers yet) → `No open findings.`
- `LEDGER_UNAVAILABLE` (gh API failed) → `Findings Ledger unavailable — gh API failed.` (one-line cause).

Format matches the workshop slide mockup at `docs/flow-team-session/slides.md` lines 802-810.

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
