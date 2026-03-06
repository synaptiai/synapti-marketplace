---
description: Use to get a quick overview of assigned issues, open PRs, and pending review requests
allowed-tools: Bash
context: fork
agent: Explore
---

# Workflow Status

Quick overview of current GitHub workflow state.

## Contract

**GOAL**: Accurate, current read-only status overview of issues, PRs, and review requests. Testable: output shows categorized items with correct status indicators.

**CONSTRAINTS**:
- This command is strictly read-only (no modifications)
- Always fetch live data from GitHub (never use cached/stale data)

**FORMAT**: Grouped output by category (assigned issues, open PRs, awaiting review, needs attention) with status indicators.

**FAILURE CONDITIONS** (output is unacceptable if any apply):
- Stale or cached data shown instead of live GitHub data
- API errors silently swallowed (show errors instead of empty sections)
- Items from wrong user shown

## Process

1. **Show assigned issues**:
   ```bash
   gh issue list --assignee @me --state open --json number,title,labels
   ```

2. **Show your open PRs**:
   ```bash
   gh pr list --author @me --state open --json number,title,reviewDecision,statusCheckRollup
   ```

3. **Show PRs awaiting your review**:
   ```bash
   gh pr list --search "review-requested:@me" --json number,title,author
   ```

4. **Show PRs with unaddressed feedback** (your PRs with changes requested):
   ```bash
   gh pr list --author @me --search "review:changes_requested" --json number,title
   ```

5. **Show comprehension health** for your open PRs:
   ```bash
   # For each open PR, check comprehension report and decision journal status
   gh pr list --author @me --state open --json number,title,body,headRefName --jq '.[] | {number, title, has_report: (.body | test("## Comprehension Report")), headRefName}'
   ```

   Read `journal-dir` from settings (default `.decisions`):
   ```bash
   # Read journal directory from settings (local > project > user > default)
   JOURNAL_DIR=$(jq -r '.journal.dir // empty' .claude/settings.gh-workflow.local.json 2>/dev/null)
   [ -z "$JOURNAL_DIR" ] && JOURNAL_DIR=$(jq -r '.journal.dir // empty' .claude/settings.gh-workflow.json 2>/dev/null)
   [ -z "$JOURNAL_DIR" ] && JOURNAL_DIR=$(jq -r '.journal.dir // empty' "$HOME/.claude/settings.gh-workflow.json" 2>/dev/null)
   [ -z "$JOURNAL_DIR" ] && JOURNAL_DIR=".decisions"
   ```

   For each open PR:
   - Check if PR body contains `## Comprehension Report` section
   - Check for decision journal entries: `git log --all --oneline -- "$JOURNAL_DIR/issue-*.md" | head -1` on the PR branch
   - Count journal entries: `git show {headRefName}:"$JOURNAL_DIR/issue-"*.md 2>/dev/null | grep -c "^### "` (use `git show` to read from PR branch without checkout)
   - Detect stale reports: compare the PR body's report generation timestamp against the latest commit date on the branch

## Output Format

```
## Workflow Status

### Your Assigned Issues (N)
- #12 Issue title [bug]
- #15 Another issue [enhancement]

### Your Open PRs (N)
- #20 PR title - Approved, checks passing
- #22 PR title - Changes requested

### Awaiting Your Review (N)
- #18 PR title by @author

### Needs Attention (N)
- #22 Has unaddressed review feedback

### Comprehension Health
- #20 Feature title — Report: yes, Decisions: 5 entries, Gates: 2/2 approved
- #22 Fix title — Report: MISSING, Decisions: none
- #25 Feature title — Report: yes (STALE — updated after report), Decisions: 8 entries
```

## Status Indicators

| Status | Meaning |
|--------|---------|
| Approved | PR has been approved by reviewers |
| Changes requested | PR needs updates based on review feedback |
| Checks passing | All CI checks are green |
| Checks failing | One or more CI checks failed |
| Awaiting review | PR is waiting for review |

## Usage

```bash
# Show workflow status
/gh-workflow:gh-status
```

## Rules

- This command is read-only (no modifications)
- Shows only items relevant to the current user
- Highlights items that need attention
- Groups information by category for quick scanning
