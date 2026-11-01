---
description: "Universal workflow entry point. Use /flow <verb> <target> for skill-driven GitHub development. Verbs: start, commit, pr, review, address, merge, resolve, release, status, learn, setup, explain, debug, design, brainstorm, issue, goal, resume, run, trigger, watch, workflow."
argument-hint: <verb> [target]
allowed-tools: Bash, Read, Write, Edit, Agent, Skill, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, TaskGet, Grep, Glob
---

# Flow: Skill-Driven Workflow

Universal dispatcher for the flow plugin. Parses intent from `$ARGUMENTS` and routes to the appropriate sub-command with required skills.

## Required Skills

_None — dispatcher only. Sub-commands declare their own Required Skills (see Skill Manifests below)._

## Skill Manifests

`references/skill-manifests.md` is the authority: it is generated from the loader and drift-tested. Each command also lists its own skills under `## Required Skills`.

## Routing Logic

Parse `$ARGUMENTS` to extract verb and target:

1. **Extract verb**: First word of arguments (start, commit, pr, review, address, merge, resolve, release, status, learn, setup, explain, debug, design, brainstorm, issue, goal, resume, run, trigger, watch, workflow)
2. **Extract target**: Remaining arguments (issue number, PR number, version type, etc.)
3. **Route**: Invoke the corresponding sub-command via Skill tool with the target as arguments

### Examples

- `/flow start 42` → Skill: flow:start, args: "42"
- `/flow commit` → Skill: flow:commit
- `/flow pr` → Skill: flow:pr
- `/flow review 15` → Skill: flow:review, args: "15"
- `/flow merge 15` → Skill: flow:merge, args: "15"
- `/flow resolve 15` → Skill: flow:resolve, args: "15"
- `/flow release patch` → Skill: flow:release, args: "patch"
- `/flow debug "TypeError in auth module"` → Skill: flow:debug, args: "TypeError in auth module"
- `/flow design 42` → Skill: flow:design, args: "42"
- `/flow brainstorm "caching strategy"` → Skill: flow:brainstorm, args: "caching strategy"
- `/flow issue "password reset fails for SSO users"` → Skill: flow:issue, args: "password reset fails for SSO users"
- `/flow goal status` → Skill: flow:goal, args: "status"
- `/flow resume` → Skill: flow:resume
- `/flow run trigger pr-15-watch` → Skill: flow:run, args: "trigger pr-15-watch"
- `/flow trigger list` → Skill: flow:trigger, args: "list"
- `/flow watch pr 15` → Skill: flow:watch, args: "pr 15"
- `/flow workflow list` → Skill: flow:workflow, args: "list"

### Verbs

| Verb | What it does |
|------|--------------|
| `start` | Start work on a GitHub issue: assign it, create the branch, break the acceptance criteria into tasks, implement |
| `commit` | Classify changes and create atomic conventional commits |
| `pr` | Review the branch and create a pull request |
| `review` | Review a pull request |
| `address` | Address review feedback on a pull request |
| `merge` | Merge an approved pull request, after confirmation |
| `resolve` | Resolve merge conflicts on the branch or for a pull request |
| `release` | Create a release in two runs: a release pull request, then the tag and GitHub release after it is merged |
| `status` | Read-only overview of issues, pull requests, branch and journal |
| `learn` | Find recurring patterns in the journal and transcripts and write skill proposals |
| `setup` | Initialize flow for a repository |
| `explain` | Answer questions about decisions made on the branch |
| `debug` | Root-cause analysis of a failure |
| `design` | Design or review architecture |
| `brainstorm` | Compare approaches before implementing |
| `issue` | Create a well-crafted GitHub issue |
| `goal` | Create, inspect, evaluate, pause, resume or clear a FlowGoal |
| `resume` | Show where an interrupted FlowRun stopped and the next safe action |
| `run` | Run a FlowTrigger's target once |
| `trigger` | List, inspect, enable, disable, run or delete FlowTriggers |
| `watch` | Create a watch trigger (pr, ci, issue, branch) and, for loops, the `/loop` prompt |
| `workflow` | List, inspect, validate or graph FlowWorkflow YAMLs |

## Bare `/flow` (No Arguments)

When invoked without arguments, show help and current status:

1. Display the verbs with their one-line descriptions from the **Verbs** table above
2. Quick state queries (read-only):

```!
# Output: `###`-headed sections + KEY=value per
# `references/command-output-format.md`. Bare `/flow` runs in any CWD,
# including non-repos / offline shells, so gh stderr is suppressed.

printf '%s\n' "### Branch"
printf '%s\n' "BRANCH=$(git branch --show-current 2>/dev/null)"

printf '%s\n' ""
printf '%s\n' "### Working Tree"
# Read-only git only, so the section works offline. UNCOMMITTED counts every
# `git status --porcelain` line (staged, unstaged, untracked and conflicted).
# CONFLICTS is yes while any path is unmerged. AHEAD counts the commits on HEAD
# that the default branch lacks: the remote's default branch (origin/HEAD) when
# it is known, else a local main or master; with neither it is unknown, not 0.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  printf '%s\n' "STATE=unavailable"
  printf '%s\n' "REASON=not in a git repository"
else
  if PORCELAIN=$(git status --porcelain 2>/dev/null); then
    UNCOMMITTED=$(printf '%s' "$PORCELAIN" | grep -c '^' 2>/dev/null)
    [ -z "$UNCOMMITTED" ] && UNCOMMITTED=0
  else
    UNCOMMITTED=unknown
  fi
  printf '%s\n' "UNCOMMITTED=$UNCOMMITTED"
  if UNMERGED=$(git diff --name-only --diff-filter=U 2>/dev/null); then
    if [ -n "$UNMERGED" ]; then CONFLICTS=yes; else CONFLICTS=no; fi
  else
    CONFLICTS=unknown
  fi
  printf '%s\n' "CONFLICTS=$CONFLICTS"
  DEFAULT_REF=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  if [ -z "$DEFAULT_REF" ]; then
    if git show-ref --verify --quiet refs/heads/main; then DEFAULT_REF=main
    elif git show-ref --verify --quiet refs/heads/master; then DEFAULT_REF=master
    fi
  fi
  AHEAD=""
  [ -n "$DEFAULT_REF" ] && AHEAD=$(git rev-list --count "$DEFAULT_REF..HEAD" 2>/dev/null)
  printf '%s\n' "DEFAULT_BRANCH=${DEFAULT_REF:-unknown}"
  printf '%s\n' "AHEAD=${AHEAD:-unknown}"
fi

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

3. Suggest the next action from the lines the block printed. The first rule that matches wins:
   - `CONFLICTS=yes` → "Try `/flow:resolve`"
   - On a feature branch (`BRANCH` is neither the branch named by `DEFAULT_BRANCH`, without an `origin/` prefix, nor empty) with `UNCOMMITTED` above 0 → "Try `/flow:commit`"
   - On a feature branch with `AHEAD` above 0 → "Try `/flow:pr`"
   - On the default branch with `AUTHORED_COUNT=0` → "Try `/flow:start <issue>`", naming an `ISSUE=` number when there is one
   - With open pull requests of yours (`PR=` lines) → "Try `/flow:review <pr>`"

   When the Working Tree section prints `STATE=unavailable`, or a value is `unknown`, skip the rules that need it and say which state could not be read.

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
