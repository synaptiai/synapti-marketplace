---
name: issue-crafting
description: "Craft well-structured GitHub issues with solution-agnostic outcomes, duplicate detection (open and closed), dynamically-discovered labels, and acceptance criteria describing observable behavior without implementation details. Use when creating new GitHub issues. Proactively suggest when an issue prescribes a method instead of describing an outcome."
allowed-tools: Bash, Read, AskUserQuestion
agent: Explore
---

# Issue Crafting

Domain skill for creating high-quality GitHub issues that describe what should happen without prescribing how.

## Iron Law

**ISSUES DESCRIBE OUTCOMES, NEVER IMPLEMENTATIONS. If the issue says "how," rewrite it.**

The moment an issue prescribes a method, it constrains the solution space and biases the implementer.

## Solution-Agnostic Principles

Issues must describe outcomes, not implementations:

- **Good**: "Users can reset their password via email"
- **Bad**: "Add a reset_password method to UserController that sends a Postmark email"

Acceptance criteria must be verifiable without knowing the code:

- **Good**: "Resetting a password with a valid token changes the stored password"
- **Bad**: "The `reset!` method updates the `password_digest` column"

## Anti-Patterns in Issue Writing

Do NOT:
- Include file paths, function names, or class names in acceptance criteria
- Write acceptance criteria that can only be verified by reading code
- Create issues without checking for duplicates first
- Use vague criteria like "improve performance" or "make it better"
- Bundle unrelated changes into a single issue

## Requirements Gathering

Collect these four elements. For any missing context, use the AskUserQuestion tool with contextual options to ask about the specific gap (e.g., "What's the current behavior?").

1. **Context**: Background and motivation — why is this needed?
2. **Current State**: What's happening now? What's the problem?
3. **Objective**: What should be achieved? Describe the outcome.
4. **Acceptance Criteria**: Observable behaviors that prove completeness.

## Duplicate Detection

Always search before creating:

```bash
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
# Search open issues
gh issue list --state open --search "KEYWORDS" --limit 10
# Search closed issues (might already be solved)
gh issue list --state closed --search "KEYWORDS" --limit 5
```

If matches found, present them to the user before proceeding.

## Label Discovery

Never hardcode labels — fetch dynamically:

```bash
gh label list --json name,description --limit 50
```

Select labels based on issue content. Common mappings:
- Bug reports → `bug`
- New features → `enhancement`
- Documentation → `documentation`
- Security issues → `security`

## Milestone Check

```bash
gh api repos/$REPO/milestones --jq '.[] | "\(.number): \(.title)"'
```

Offer milestone assignment if milestones exist.

## Issue Body Structure

```markdown
## Context
{Background and motivation}

## Current State
{What's happening now — observable behavior}

## Objective
{What should be achieved — outcomes, not methods}

## Acceptance Criteria
- [ ] {Observable behavior 1}
- [ ] {Observable behavior 2}
- [ ] {Observable behavior 3}
```

## Verification

After creation, verify: `gh issue view <N> --json number,title,state,labels`

The issue should:
- Have a clear, searchable title
- Contain no file paths or implementation details in the body
- Have acceptance criteria that describe what, not how
- Have appropriate labels from the repository's label set
