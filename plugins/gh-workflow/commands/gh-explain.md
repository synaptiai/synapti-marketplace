---
description: Explore what AI built — loads decision journal, diff, and issue context for interactive Q&A
argument-hint: [issue-or-pr-number]
allowed-tools: Bash, Read, Grep, Glob, AskUserQuestion
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations (reads, API calls),
invoke ALL relevant tools simultaneously in a single message rather than sequentially.
Err on the side of maximizing parallel tool calls.
-->

# Explain: What Did AI Build?

Context loader for interactive Q&A about what AI built on your behalf. Loads the decision journal, diff, issue context, and source files so you can ask questions grounded in evidence.

**Tool Usage**: This command uses the **AskUserQuestion tool** for session save decisions.

## Contract

**GOAL**: Load all available context about an issue/PR and present a comprehension brief, then enable conversational Q&A. Testable: user can ask questions and get answers grounded in actual code, decisions, and issue context.

**CONSTRAINTS**:
- Never fabricate decisions or rationale not present in the journal or diff
- Always distinguish between journal-recorded decisions and inferred decisions
- If context is incomplete, state what's missing rather than guessing

**FORMAT**: Comprehension brief displayed first, then open-ended conversation.

**FAILURE CONDITIONS** (output is unacceptable if any apply):
- Claims about decisions that aren't in the journal or diff
- Answers not grounded in loaded context
- Context loading fails silently (must report what's missing)

## Phase 1: Context Loading

### Step 1.1: Determine Target

If `$ARGUMENTS` is provided, use it as the issue or PR number. Otherwise, detect from current branch:

```bash
BRANCH=$(git branch --show-current)
ISSUE_NUM=$(echo "$BRANCH" | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+')
```

If no issue number found from branch or arguments, ask via **AskUserQuestion tool**:
- "Which issue or PR would you like to explore?"

### Step 1.2: Load Context (Parallel)

**Execute in parallel** (single message, multiple tool calls):

1. **Read decision journal**:
   ```bash
   cat .decisions/issue-"$ISSUE_NUM".md 2>/dev/null
   ```

2. **Read issue details**:
   ```bash
   gh issue view "$ISSUE_NUM" --json title,body,labels,comments 2>/dev/null
   ```

3. **Read diff** (check `explain-include-diff` config, default: `true`):
   ```bash
   DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
   git diff "$DEFAULT_BRANCH"...HEAD --stat
   git diff --name-only "$DEFAULT_BRANCH"...HEAD
   ```

4. **Check for PR**:
   ```bash
   BRANCH=$(git branch --show-current)
   gh pr list --head "$BRANCH" --json number,title,body,url --jq '.[0]'
   ```

5. **Check for Q&A session history**:
   ```bash
   ls .decisions/explain-issue-"$ISSUE_NUM"-*.md 2>/dev/null
   ```

### Step 1.3: Read Key Source Files

From the diff file list, read the most significant source files (prioritize by lines changed). For large diffs (>20 files), read the top 10 by additions.

## Phase 2: Comprehension Brief

Generate and display a brief summary:

```markdown
## Comprehension Brief: Issue #{N} — {title}

### What Was Built
{2-3 sentence summary of the changes, written for someone who hasn't seen the code}

### Key Decisions
{From decision journal, list significant decisions with rationale. If no journal: "No decision journal found — analysis based on diff only."}

| # | Category | Decision | Risk |
|---|----------|----------|------|
| 1 | {category} | {decision title} | {risk} |

### Requirements Status
{From comprehension report in PR body, or generate ad-hoc from diff vs. issue criteria}

| Criterion | Status |
|-----------|--------|
| {criterion} | {Met/Interpreted/Partial/Not Addressed} |

### Areas of Note
{Highlight anything that might need human attention: interpreted requirements, high-risk decisions, first-touch files, large single-commit additions}

### Context Loaded
- Decision journal: {Yes ({N} entries) / No (not found)}
- Issue context: {Yes / No (fetch failed)}
- Diff: {N} files, {M} lines changed
- PR: {#{number} / No PR found}
- Previous Q&A sessions: {N found / None}
```

## Phase 3: Conversational Mode

After displaying the brief:

> "Ask me anything about this work. I have the decision journal, full diff, and issue context loaded. Type your questions — I'll answer grounded in the actual code and decisions."

Let Claude's natural conversational ability handle the Q&A. The command's value is **context loading**, not Q&A orchestration.

**Grounding rules for answers:**
- Cite specific files and line numbers when referencing code
- Quote decision journal entries when explaining rationale
- Distinguish "the journal says..." from "based on the diff, it appears..."
- If asked about something not in the loaded context, say so explicitly

## Phase 4: Session Save

**Check configuration** — read `explain-session-save` from CLAUDE.md. Default: `ask`.

| Config | Behavior |
|--------|----------|
| `always` | Auto-save session transcript |
| `ask` | Use **AskUserQuestion tool**: "Save this Q&A session?" with options: "Yes" / "No" |
| `never` | Skip save |

Save location: `.decisions/explain-issue-{N}-{YYYYMMDD-HHMM}.md`

The saved file is a free-form markdown transcript of the Q&A, not a structured journal entry.

## Graceful Degradation

| Missing Capability | Fallback |
|-------------------|----------|
| No decision journal | Proceed with diff + issue context. Note: "No decision journal found — analysis based on diff and issue only." |
| No issue context (gh issue view fails) | Proceed with diff + journal. Note: "Could not fetch issue — using branch context only." |
| No diff (clean working tree, no branch divergence) | Check for PR diff via `gh pr diff`. If no PR: "No changes to analyze." |
| No PR found | Proceed without PR context |
| Branch has no issue number | Ask user for issue/PR number |

## Arguments

- `$ARGUMENTS`: Optional issue or PR number
  - If omitted, detected from current branch name
  - Example: `/gh-explain 42`
