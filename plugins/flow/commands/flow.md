---
description: "[flow] Universal workflow entry point. Use /flow <verb> <target> for skill-driven GitHub development. Verbs: start, commit, pr, review, address, merge, release, status, learn, setup, explain."
argument-hint: <verb> [target]
allowed-tools: Bash, Read, Write, Edit, Agent, Skill, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, TaskGet, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations, invoke ALL relevant tools
simultaneously in a single message rather than sequentially.
-->

# Flow: Skill-Driven Workflow

Universal dispatcher for the flow plugin. Parses intent from `$ARGUMENTS` and routes to the appropriate sub-command with required skills.

## Skill Manifests

Each verb requires specific domain skills. The dispatcher invokes these deterministically:

| Verb | Required Skills | Command |
|------|----------------|---------|
| start | branch-and-task-management, change-classification, capability-discovery | /flow:start |
| commit | change-classification, convention-enforcement | /flow:commit |
| pr | pr-lifecycle, code-review-methodology, capability-discovery | /flow:pr |
| review | code-review-methodology | /flow:review |
| address | feedback-resolution, change-classification, capability-discovery | /flow:address |
| merge | merge-and-release | /flow:merge |
| release | merge-and-release | /flow:release |
| status | (none — read-only) | /flow:status |
| learn | (none — analysis only) | /flow:learn |
| setup | capability-discovery | /flow:setup |
| explain | (none — read-only) | /flow:explain |

## Routing Logic

Parse `$ARGUMENTS` to extract verb and target:

1. **Extract verb**: First word of arguments (start, commit, pr, review, address, merge, release, status, learn, setup, explain)
2. **Extract target**: Remaining arguments (issue number, PR number, version type, etc.)
3. **Route**: Invoke the corresponding sub-command via Skill tool with the target as arguments

### Examples

- `/flow start 42` → Skill: flow:start, args: "42"
- `/flow commit` → Skill: flow:commit
- `/flow pr` → Skill: flow:pr
- `/flow review 15` → Skill: flow:review, args: "15"
- `/flow merge 15` → Skill: flow:merge, args: "15"
- `/flow release patch` → Skill: flow:release, args: "patch"

## Bare `/flow` (No Arguments)

When invoked without arguments, show help and current status:

1. Display available verbs with one-line descriptions
2. Run a quick status check:

```bash
# Parallel: current state queries
git branch --show-current
gh issue list --assignee @me --state open --limit 5
gh pr list --author @me --state open --limit 5
```

3. Suggest next action based on state:
   - On default branch with no open PRs → "Try `/flow start <issue>`"
   - On feature branch with uncommitted changes → "Try `/flow commit`"
   - On feature branch with commits ahead → "Try `/flow pr`"
   - With open PRs needing review → "Try `/flow review <pr>`"

## Natural Language Fallback

If the verb doesn't match any known command, attempt to infer intent:

- "create an issue about..." → route to start (after issue creation)
- "what's happening" → route to status
- "ship it" → route to pr

Confirm the inferred intent with the user before executing.

## Foundation Skills

All flow commands operate under three always-loaded foundation skills:
- **evidence-based-development**: Show evidence, cite file:line, P1/P2/P3
- **autonomous-workflow**: Explore>Plan>Code>Verify, Task tools, three-tier safety
- **code-quality-principles**: Surgical changes, no secrets, atomic commits
