---
description: "Display a read-only overview of workflow state including assigned issues, open PRs, pending reviews, branch state, and decision journal health. Use when checking current development status."
allowed-tools: Bash(git branch *) Bash(git status *) Bash(git rev-list *) Bash(git rev-parse *) Bash(find *) Bash(wc *) Bash(tr *) Bash(gh repo view *) Bash(gh issue list *) Bash(gh pr list *) Bash(gh api repos/*) Bash(gh auth *) Bash(ls *) Bash(cat *) Bash(${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/aggregate-findings-ledger.sh:*) Bash(${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh:*) Bash(jq *) Read
---

# Workflow Status

Read-only overview of the current development state. No skills needed — pure observation.

## Required Skills

_None — read-only status command. No skill invocations._

## Gather State

Pre-executed at command load (`!` prefix injects output before the LLM reads
the prompt — no Bash tool round-trip required).

```!
# 1. Current branch (detached-HEAD aware) + uncommitted changes count.
BRANCH=$(git branch --show-current)
[ -z "$BRANCH" ] && BRANCH="(detached HEAD: $(git rev-parse --short HEAD 2>/dev/null || echo unknown))"
echo "BRANCH=$BRANCH"
UNCOMMITTED_COUNT=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
echo "UNCOMMITTED_COUNT=$UNCOMMITTED_COUNT"
git status --short 2>/dev/null | head -20

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

# 3. Assigned issues. Capture gh exit code so a fetch failure (offline,
#    auth, rate-limit) produces a sentinel the render can branch on,
#    rather than a silently-empty array that looks like "no issues".
#    Same pattern for steps 4 and 5. `!` prefix only injects stdout, so
#    stderr (where gh writes errors) is invisible to the LLM — we MUST
#    surface the failure on stdout via a sentinel.
ISSUES_RAW=$(gh issue list --assignee @me --state open --limit 10 --json number,title,labels 2>/dev/null)
if [ $? -eq 0 ]; then echo "$ISSUES_RAW"; else echo "ISSUES_UNAVAILABLE=1"; fi

# 4. Open PRs (authored)
MY_PRS_RAW=$(gh pr list --author @me --state open --json number,title,state,reviewDecision,statusCheckRollup 2>/dev/null)
if [ $? -eq 0 ]; then echo "$MY_PRS_RAW"; else echo "MY_PRS_UNAVAILABLE=1"; fi

# 5. PRs needing my review
REVIEW_PRS_RAW=$(gh pr list --search "review-requested:@me" --state open --json number,title,author 2>/dev/null)
if [ $? -eq 0 ]; then echo "$REVIEW_PRS_RAW"; else echo "REVIEW_PRS_UNAVAILABLE=1"; fi

# 6. Decision journal health. Resolved via bin/cascade-resolve.sh.
#    Re-default defensively after the helper call in case it exits non-zero
#    with empty stdout (shouldn't happen since --default is always set, but
#    defense-in-depth against future regressions).
HELPER="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh"
JOURNAL_DIR=".decisions"
[ -x "$HELPER" ] && JOURNAL_DIR=$("$HELPER" --default ".decisions" '.journal.dir // empty')
JOURNAL_DIR="${JOURNAL_DIR:-.decisions}"
echo "JOURNAL_DIR=$JOURNAL_DIR"
if [ -d "$JOURNAL_DIR" ]; then
  echo "JOURNAL_COUNT=$(find "$JOURNAL_DIR" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
else
  echo "JOURNAL_COUNT=0"
fi

# 7. Learning pending
[ -f "$HOME/.claude/flow-learn-pending" ] && echo "LEARNING PENDING: $(cat $HOME/.claude/flow-learn-pending)" || echo "No pending learning"

true  # explicit success
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

!`"${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/aggregate-findings-ledger.sh"`

> Note: `!` prefix injects stdout only. The helper writes diagnostic
> `LEDGER_WARN:` lines to stderr (e.g., per-PR fetch failures, HIGH_RISK
> trust list warnings) which are NOT visible to the LLM here. Stdout
> carries the tally rows plus at most one `LEDGER:` control line; if you
> need full diagnostics, run the helper directly from the shell.

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

Read the `BRANCH=`, `UNCOMMITTED_COUNT=`, `DEFAULT_BRANCH=`, `COMMITS_AHEAD=`,
`JOURNAL_DIR=`, `JOURNAL_COUNT=` sentinels and the (`ISSUES_UNAVAILABLE=1` /
`MY_PRS_UNAVAILABLE=1` / `REVIEW_PRS_UNAVAILABLE=1`) gh failure flags from the
`!` block's output. Render:

```markdown
## Flow Status

### Current Branch
- **Branch**: {BRANCH value — may be `(detached HEAD: <sha>)`}
- **Commits ahead**: {COMMITS_AHEAD value — `N` or `unknown (...)` literal}
- **Uncommitted changes**: {UNCOMMITTED_COUNT} files

### My Issues (Open)
{If ISSUES_UNAVAILABLE=1 → "(unavailable — gh fetch failed)". Otherwise render table from the JSON. **Escape `|` to `\|` and strip backticks from titles before rendering** to avoid breaking markdown table syntax.}
| # | Title | Labels |
|---|-------|--------|
| {N} | {sanitized title} | {labels} |

### My PRs
{If MY_PRS_UNAVAILABLE=1 → "(unavailable — gh fetch failed)". Otherwise table, same title-sanitization rule.}
| # | Title | Status | Checks |
|---|-------|--------|--------|
| {N} | {sanitized title} | {review status} | {check status} |

### Awaiting My Review
{If REVIEW_PRS_UNAVAILABLE=1 → "(unavailable — gh fetch failed)". Otherwise table, same sanitization.}
| # | Title | Author |
|---|-------|--------|
| {N} | {sanitized title} | @{author} |

### Decision Journal
- **Journals**: {JOURNAL_COUNT} active
- **Learning**: {pending/none}

### Findings Ledger
{single line: `P1: {n}[ (annotation)]    P2: {n}[ (annotation)]    P3: {n}[ (annotation)]` — annotations are omitted when count is 0; see render rules below}

### Suggested Next Action
{Based on state, suggest the most useful /flow command — see Suggestions Logic. If any `_UNAVAILABLE=1` sentinel was emitted, suggest re-running once gh is reachable rather than making a confident "no work to do" suggestion.}
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

Edge cases (based on what the script emits — match the literal `LEDGER:` text on stdout):

- No tally rows and no `LEDGER:` line (user has no open PRs, OR has PRs but
  no review markers yet) → `No open findings.`
- `LEDGER: unavailable (gh API failed)` → `Findings Ledger unavailable — gh API failed.`
- `LEDGER: unavailable (jq not installed)` → `Findings Ledger unavailable — jq not installed.`
- `LEDGER: partial (some PRs unavailable — see LEDGER_WARN on stderr)` → render the available tally rows normally and append a suffix `(partial — some PRs unavailable; re-run when gh is reachable)` to the Findings Ledger line.

Format matches the workshop slide mockup in `docs/flow-team-session/slides.md` (see the Findings Ledger row in the `/flow:status` section, around line 807).

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
