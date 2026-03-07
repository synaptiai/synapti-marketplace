---
name: issue-crafting
description: "[flow] Use when creating GitHub issues. Guides solution-agnostic requirements gathering, duplicate detection, label discovery, and acceptance criteria that describe observable behavior — not implementation details."
allowed-tools: Bash, Read, AskUserQuestion
context: fork
agent: Explore
---

# Issue Crafting

Domain skill for creating high-quality GitHub issues that describe what should happen without prescribing how.

## Solution-Agnostic Principles

Issues must describe outcomes, not implementations:

- **Good**: "Users can reset their password via email"
- **Bad**: "Add a reset_password method to UserController that sends a Postmark email"

Acceptance criteria must be verifiable without knowing the code:

- **Good**: "Resetting a password with a valid token changes the stored password"
- **Bad**: "The `reset!` method updates the `password_digest` column"

## Requirements Gathering

Collect these four elements. Use AskUserQuestion for any gaps:

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
