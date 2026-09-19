---
description: "Universal workflow entry point. Use /flow <verb> <target> for skill-driven GitHub development. Verbs: start, commit, pr, review, address, merge, resolve, release, status, learn, setup, explain, debug, design, brainstorm, issue."
argument-hint: <verb> [target]
allowed-tools: Bash, Read, Write, Edit, Agent, Skill, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, TaskGet, Grep, Glob
---

# Flow: Skill-Driven Workflow

Universal dispatcher for the flow plugin. Parses intent from `$ARGUMENTS` and routes to the appropriate sub-command with required skills.

## Required Skills

_None — dispatcher only. Sub-commands declare their own Required Skills (see Skill Manifests below)._

## Skill Manifests

Each verb requires specific domain skills. The dispatcher invokes these deterministically:

`references/skill-manifests.md` is the authority: it is generated from the loader and drift-tested. Each command also lists its own skills under `## Required Skills`.

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
2. Quick state queries (read-only):

```!
# Output: `###`-headed sections + KEY=value per
# `references/command-output-format.md`. Bare `/flow` runs in any CWD,
# including non-repos / offline shells, so gh stderr is suppressed.

printf '%s\n' "### Branch"
printf '%s\n' "BRANCH=$(git branch --show-current 2>/dev/null)"

printf '%s\n' ""
printf '%s\n' "### Assigned Issues"
# Capture gh exit code separately: gh success with no records returns `[]` exit 0;
# gh failure (auth, network, non-repo CWD) returns "" with non-zero exit and jq
# 1.8 on empty input produces NO output and exits 0 — so `|| echo 0` does not
# fire and COUNT stays empty, leaking a bare `ASSIGNED_COUNT=` line.
ASSIGNED_JSON=$(gh issue list --assignee @me --state open --limit 5 --json number,title 2>/dev/null); GH_EXIT=$?
if [ $GH_EXIT -ne 0 ]; then
  printf '%s\n' "ASSIGNED_COUNT=0"
  printf '%s\n' "STATE=unavailable"
else
  ASSIGNED_COUNT=$(printf '%s\n' "$ASSIGNED_JSON" | jq 'length' 2>/dev/null)
  [ -z "$ASSIGNED_COUNT" ] && ASSIGNED_COUNT=0
  printf '%s\n' "ASSIGNED_COUNT=$ASSIGNED_COUNT"
  if [ "$ASSIGNED_COUNT" = "0" ]; then
    printf '%s\n' "STATE=empty"
  else
    printf '%s\n' "$ASSIGNED_JSON" | jq -r '.[] | "ISSUE=\(.number) title=\"\(.title)\""' 2>/dev/null
  fi
fi

printf '%s\n' ""
printf '%s\n' "### My PRs"
AUTHORED_JSON=$(gh pr list --author @me --state open --limit 5 --json number,title 2>/dev/null); GH_EXIT=$?
if [ $GH_EXIT -ne 0 ]; then
  printf '%s\n' "AUTHORED_COUNT=0"
  printf '%s\n' "STATE=unavailable"
else
  AUTHORED_COUNT=$(printf '%s\n' "$AUTHORED_JSON" | jq 'length' 2>/dev/null)
  [ -z "$AUTHORED_COUNT" ] && AUTHORED_COUNT=0
  printf '%s\n' "AUTHORED_COUNT=$AUTHORED_COUNT"
  if [ "$AUTHORED_COUNT" = "0" ]; then
    printf '%s\n' "STATE=empty"
  else
    printf '%s\n' "$AUTHORED_JSON" | jq -r '.[] | "PR=\(.number) title=\"\(.title)\""' 2>/dev/null
  fi
fi

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

## Tier Classification

`/flow:flow` is a dispatcher — it routes the user to a specific subcommand. Tier classification is **deferred to the dispatched subcommand**. See each subcommand's `## Tier Classification` section for its specific actions and tiers (e.g., `/flow:start` is mostly Tier 1 with Tier 2 push; `/flow:merge` is Tier 3; `/flow:release` is Tier 3).
