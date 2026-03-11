---
description: "Create a well-crafted GitHub issue. Guides solution-agnostic requirements gathering, duplicate detection, label discovery, and verifiable acceptance criteria."
argument-hint: [description-or-topic]
allowed-tools: Bash, Read, Agent, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, Skill, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations, invoke ALL relevant tools
simultaneously in a single message rather than sequentially.
-->

# Create Issue: $ARGUMENTS

Skill-driven issue creation. Follows the Explore > Plan > Code > Verify loop with issue-crafting skill knowledge.

## Required Skills

- `issue-crafting` — solution-agnostic issues, duplicate detection, label discovery

## Phase 1: EXPLORE

Gather context before formulating the issue.

**Parallel Bash calls:**

```bash
# 1. Repo info
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
echo "REPO=$REPO"

# 2. Current git state (branch context for cross-references)
git branch --show-current
git status --short
```

**Branch context extraction**: If on a feature branch matching `feature/issue-{N}-*` or `fix/issue-{N}-*`, extract the issue number — the new issue may be related.

**Requirements gathering** from `$ARGUMENTS`:

If `$ARGUMENTS` provides a description, parse it for initial context. For each missing element, use the AskUserQuestion tool with contextual options:

1. **Context**: "What's the background/motivation for this issue?"
2. **Current State**: "What's happening now? What's the problem or gap?"
3. **Objective**: "What should be achieved? Describe the desired outcome."
4. **Acceptance Criteria**: "What observable behaviors prove this is complete?"

If `$ARGUMENTS` is empty, walk through all four elements interactively.

**Iron law enforcement**: If any gathered element contains file paths, function names, class names, or implementation details — rewrite it to describe outcomes instead. Example:
- Bad: "Add a reset_password method to UserController"
- Good: "Users can reset their password via email"

## Phase 2: PLAN

Formulate the issue with safety checks.

```
TaskCreate("Duplicate detection", "Search open and closed issues for potential duplicates")
TaskCreate("Label discovery", "Fetch repo labels and select appropriate ones")
TaskCreate("Milestone check", "Check for active milestones")
TaskCreate("Compose issue", "Build issue body from gathered requirements")
TaskCreate("Create and verify", "Create issue via gh and verify fields")
```

**Duplicate detection** (from issue-crafting skill):

```bash
# Extract keywords from the issue title/description
# Search open issues
gh issue list --state open --search "KEYWORDS" --limit 10
# Search closed issues (might already be solved)
gh issue list --state closed --search "KEYWORDS" --limit 5
```

If matches found, present them to the user via AskUserQuestion: "These existing issues look related. Should we proceed with creating a new issue, or does one of these cover your need?"

TaskUpdate duplicate detection to completed.

**Label discovery** (parallel with milestone check):

```bash
gh label list --json name,description --limit 50
```

Select labels based on issue content. Common mappings:
- Bug reports → `bug`
- New features → `enhancement`
- Documentation → `documentation`
- Security issues → `security`

TaskUpdate label discovery to completed.

**Milestone check:**

```bash
gh api repos/$REPO/milestones --jq '.[] | "\(.number): \(.title)"'
```

Offer milestone assignment if milestones exist.

TaskUpdate milestone check to completed.

## Phase 3: CODE

Compose and create the issue.

TaskUpdate compose issue to in_progress.

**Build issue body** using the template structure from `templates/issue-body.md`:

```markdown
## Context
{gathered context — background and motivation}

## Current State
{gathered current state — observable behavior, not implementation details}

## Objective
{gathered objective — outcomes, not methods}

## Acceptance Criteria
- [ ] {Observable behavior 1 — verifiable without knowing the implementation}
- [ ] {Observable behavior 2}
- [ ] {Observable behavior 3}
```

**Final iron law check**: Scan the composed body for file paths, function names, class names, or implementation prescriptions. If found, rewrite to be solution-agnostic.

TaskUpdate compose issue to completed.

**Create the issue** (Tier 2: journal-and-proceed):

```bash
gh issue create --title "{title}" --body "{body}" --label "{labels}" [--milestone "{milestone}"]
```

TaskUpdate create and verify to in_progress.

## Phase 4: VERIFY

Confirm the issue was created correctly.

```bash
gh issue view <N> --json number,title,state,labels,body
```

Verification checklist:
- Has a clear, searchable title
- Contains no file paths or implementation details in the body
- Has acceptance criteria that describe what, not how
- Has appropriate labels from the repository's label set

TaskUpdate create and verify to completed.
TaskList — confirm all tasks completed.

Display summary:

```markdown
## Issue Created

- **Issue**: #N — {title}
- **Labels**: {labels}
- **URL**: {url}
```

## Completion

Present next steps:

- `/flow:start <N>` — begin working on this issue
- `/flow:issue` — create another issue
- Return to current work

## Tier Classification

| Action | Tier | Behavior |
|--------|------|----------|
| Codebase search | 1 | Autonomous |
| Duplicate search | 1 | Autonomous (read-only) |
| Issue creation | 2 | Journal-and-proceed |
