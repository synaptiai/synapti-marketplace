---
description: "Universal workflow entry point. Use /flow <verb> <target> for skill-driven GitHub development. Verbs: start, commit, pr, review, address, merge, resolve, release, status, learn, setup, explain, debug, design, brainstorm, issue."
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

## Required Skills

_None — dispatcher only. Sub-commands declare their own Required Skills (see Skill Manifests below)._

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
| resolve | merge-conflict-resolution, capability-discovery | /flow:resolve |
| release | merge-and-release | /flow:release |
| status | (none — read-only) | /flow:status |
| learn | (none — analysis only) | /flow:learn |
| setup | capability-discovery | /flow:setup |
| explain | (none — read-only) | /flow:explain |
| debug | debugging-patterns, change-classification | /flow:debug |
| design | architecture-patterns, capability-discovery | /flow:design |
| brainstorm | brainstorming, capability-discovery | /flow:brainstorm |
| issue | issue-crafting | /flow:issue |

## Routing Logic

Parse `$ARGUMENTS` to extract verb and target:

1. **Extract verb**: First word of arguments (start, commit, pr, review, address, merge, resolve, release, status, learn, setup, explain, debug, design, brainstorm, issue)
2. **Extract target**: Remaining arguments (issue number, PR number, version type, etc.)
3. **Route**: Invoke the corresponding sub-command via Skill tool with the target as arguments

### Examples

- `/flow:start 42` → Skill: flow:start, args: "42"
- `/flow:commit` → Skill: flow:commit
- `/flow:pr` → Skill: flow:pr
- `/flow:review 15` → Skill: flow:review, args: "15"
- `/flow:merge 15` → Skill: flow:merge, args: "15"
- `/flow:resolve 15` → Skill: flow:resolve, args: "15"
- `/flow:release patch` → Skill: flow:release, args: "patch"
- `/flow:debug "TypeError in auth module"` → Skill: flow:debug, args: "TypeError in auth module"
- `/flow:design 42` → Skill: flow:design, args: "42"
- `/flow:brainstorm "caching strategy"` → Skill: flow:brainstorm, args: "caching strategy"
- `/flow:issue "password reset fails for SSO users"` → Skill: flow:issue, args: "password reset fails for SSO users"

## Bare `/flow` (No Arguments)

When invoked without arguments, show help and current status:

1. Display available verbs with one-line descriptions
2. Pre-executed at command load (`!` prefix) — quick state queries reach the agent as prompt context:

```!
# Parallel: current state queries. Bare `/flow` runs in any CWD, including
# non-repos and offline shells, so stderr from gh is suppressed (otherwise
# "could not determine repository" leaks into the prompt as data).
git branch --show-current
gh issue list --assignee @me --state open --limit 5 2>/dev/null
gh pr list --author @me --state open --limit 5 2>/dev/null

true
```

3. Suggest next action based on state:
   - On default branch with no open PRs → "Try `/flow:start <issue>`"
   - On feature branch with uncommitted changes → "Try `/flow:commit`"
   - On feature branch with commits ahead → "Try `/flow:pr`"
   - On feature branch with merge conflicts → "Try `/flow:resolve`"
   - With open PRs needing review → "Try `/flow:review <pr>`"

## Natural Language Fallback

If the verb doesn't match any known command, attempt to infer intent:

- "create an issue about..." → route to issue
- "what's happening" → route to status
- "ship it" → route to pr
- "something is broken" / "why is this failing" → route to debug
- "fix conflicts" / "resolve conflicts" / "there are merge conflicts" → route to resolve
- "how should we build" / "what approach" → route to brainstorm
- "design this" / "architecture" → route to design

Use the AskUserQuestion tool with contextual options to confirm: "I understood your request as '{inferred verb}'. Is that correct?"

## Foundation Skills

All flow commands operate under three always-loaded foundation skills:
- **evidence-based-development**: Show evidence, cite file:line, P1/P2/P3
- **autonomous-workflow**: Explore>Plan>Code>Verify, Task tools, three-tier safety
- **code-quality-principles**: Surgical changes, no secrets, atomic commits

## Tier Classification

`/flow:flow` is a dispatcher — it routes the user to a specific subcommand. Tier classification is **deferred to the dispatched subcommand**. See each subcommand's `## Tier Classification` section for its specific actions and tiers (e.g., `/flow:start` is mostly Tier 1 with Tier 2 push; `/flow:merge` is Tier 3; `/flow:release` is Tier 3).
