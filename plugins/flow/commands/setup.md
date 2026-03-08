---
description: "[flow] Initialize flow for a repository. Detects tech stack, generates settings, optionally adds CLAUDE.md sections, and warns about plugin coexistence."
allowed-tools: Bash, Read, Write, AskUserQuestion, Skill, Glob, Grep
---

# Setup Flow

Initialize the flow plugin for the current repository.

## Phase 1: Detect Environment

**Parallel operations:**

```bash
# 1. Check for existing flow settings
[ -f ".claude/settings.flow.json" ] && echo "EXISTING_SETTINGS=true" || echo "EXISTING_SETTINGS=false"

# 2. Check for gh-workflow installation
ls plugins/gh-workflow/.claude-plugin/plugin.json .claude/settings.gh-workflow.json 2>/dev/null && echo "GH_WORKFLOW_DETECTED=true"

# 3. Check CLAUDE.md
[ -f ".claude/CLAUDE.md" ] && echo "CLAUDE_MD=.claude/CLAUDE.md"
[ -f "CLAUDE.md" ] && echo "CLAUDE_MD=CLAUDE.md"

# 4. Git remote
git remote -v | head -2
gh auth status 2>&1 | head -3
```

**Skill(capability-discovery)**: Detect tech stack, quality commands, existing agents/skills.

## Phase 2: Generate Settings

Based on detection, create `settings.flow.json` with sensible defaults:

```bash
mkdir -p .claude
```

Write `.claude/settings.flow.json` with:
- Quality commands discovered from tech stack
- Branch patterns matching existing repository conventions
- Commit types matching existing commit history
- Agent teams disabled by default
- Learning enabled by default

## Phase 3: Coexistence Warning

If gh-workflow is detected:

```markdown
**Note**: gh-workflow plugin detected in this repository.

The flow plugin can coexist alongside gh-workflow, but you should only
enable one at a time to avoid hook conflicts.

Commands use different prefixes:
- gh-workflow: `/gh-start`, `/gh-commit`, `/gh-pr`
- flow: `/flow:start`, `/flow:commit`, `/flow:pr`
```

## Phase 4: CLAUDE.md Integration

Use the AskUserQuestion tool with contextual options to ask: "Add flow workflow section to CLAUDE.md?"

If yes, append the workflow section from `templates/CLAUDE-flow.md` to the existing CLAUDE.md.

## Phase 5: Summary

```markdown
## Flow Setup Complete

### Settings
- File: `.claude/settings.flow.json`
- Tech stack: {detected}
- Quality commands: {lint}, {test}, {typecheck}
- Agent teams: disabled (enable with `agentTeams: true`)
- Learning: enabled

### Commands Available
| Command | Purpose |
|---------|---------|
| `/flow:start <issue>` | Start work on an issue |
| `/flow:commit` | Classify and commit changes |
| `/flow:pr` | Create pull request |
| `/flow:review <pr>` | Review a pull request |
| `/flow:address <pr>` | Address review feedback |
| `/flow:merge <pr>` | Merge approved PR |
| `/flow:release <type>` | Create release |
| `/flow:status` | Workflow overview |
| `/flow:learn` | Analyze patterns |

### Next Steps
- Assign an issue and run `/flow:start <number>`
- Or run `/flow:status` to see current state
```
