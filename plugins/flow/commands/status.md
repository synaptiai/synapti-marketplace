---
description: "Display a read-only overview of workflow state including assigned issues, open PRs, pending reviews, branch state, and decision journal health. Use when checking current development status."
allowed-tools: Bash(git branch *) Bash(git status *) Bash(git rev-list *) Bash(git rev-parse *) Bash(gh repo view *) Bash(gh issue list *) Bash(gh pr list *) Bash(gh api repos/*) Bash(gh auth *) Bash(ls *) Bash(cat *) Bash(bash plugins/flow/bin/*) Bash(jq *) Read
---

# Workflow Status

Read-only overview of the current development state. No skills needed — pure observation.

## Required Skills

_None — read-only status command. No skill invocations._

## Gather State

Pre-executed at command load (`!` prefix injects output before the LLM reads
the prompt — no Bash tool round-trip required).

```!
# 1. Current branch and uncommitted changes
git branch --show-current
git status --short | head -20

# 2. Commits ahead of default branch. Distinguish "0 commits ahead" from
#    "default branch not locally fetched" (false-negative 0 was confusing
#    offline contributors). Probe with rev-parse first; emit `unknown` if
#    the branch ref is missing rather than collapsing to 0.
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
echo "DEFAULT_BRANCH=$DEFAULT_BRANCH"
if git rev-parse --verify "$DEFAULT_BRANCH" >/dev/null 2>&1; then
  echo "COMMITS_AHEAD=$(git rev-list --count "$DEFAULT_BRANCH"..HEAD 2>/dev/null || echo 0)"
else
  echo "COMMITS_AHEAD=unknown ($DEFAULT_BRANCH not fetched locally)"
fi

# 3. Assigned issues
gh issue list --assignee @me --state open --limit 10 --json number,title,labels

# 4. Open PRs (authored)
gh pr list --author @me --state open --json number,title,state,reviewDecision,statusCheckRollup

# 5. PRs needing my review
gh pr list --search "review-requested:@me" --state open --json number,title,author

# 6. Decision journal health. Resolved via bin/cascade-resolve.sh.
HELPER="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh"
JOURNAL_DIR=".decisions"
[ -x "$HELPER" ] && JOURNAL_DIR=$("$HELPER" --default ".decisions" '.journal.dir // empty')
[ -d "$JOURNAL_DIR" ] && ls -la "$JOURNAL_DIR"/*.md 2>/dev/null | wc -l || echo "0"

# 7. Learning pending
[ -f "$HOME/.claude/flow-learn-pending" ] && echo "LEARNING PENDING: $(cat $HOME/.claude/flow-learn-pending)" || echo "No pending learning"
```

## Gather Findings Ledger

Aggregate review findings across the user's open PRs (author OR assignee). See
[`references/finding-ledger-parser.md`](../references/finding-ledger-parser.md)
for the canonical marker schemas, queries, and state classification.

The aggregation logic — settings cascade for the trust list, PR enumeration,
review/comment fetch, marker parsing, attacker-input sanitization, state
precedence — lives in
[`bin/aggregate-findings-ledger.sh`](../bin/aggregate-findings-ledger.sh).
It is invoked at command load via the `!` prefix; output (tally rows or a
`LEDGER: unavailable` control line) is injected into the prompt directly.

!`bash "${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/aggregate-findings-ledger.sh"`

The script's output is a tally like:

```
   2 P1|in_fix_forward
   1 P2|escalated
   3 P3|in_fix_forward
```

Use this to render the Findings Ledger line per priority. If the script
produces no tally rows AND no `LEDGER:` control line, the user either has
no open PRs or has open PRs without review markers yet — in both cases
render `No open findings`.

## Display

```markdown
## Flow Status

### Current Branch
- **Branch**: {branch name}
- **Commits ahead**: {N} ahead of {default branch}, OR `unknown ({default-branch} not fetched locally)` when the COMMITS_AHEAD value emitted by the `!` block starts with `unknown`
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

Edge cases (based on what the script emits):

- No tally rows and no `LEDGER:` line (user has no open PRs, OR has PRs but
  no review markers yet) → `No open findings.`
- `LEDGER: unavailable (gh API failed)` line emitted → `Findings Ledger unavailable — gh API failed.` (one-line cause).

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
