---
name: capability-discovery
description: "[flow] Discovers available agents, skills, quality commands (lint, test, typecheck), and tech stack in the project environment. Use when starting implementation, creating PRs, reviewing PRs, or addressing feedback to determine which agents to dispatch and which quality commands to run."
allowed-tools: Bash, Read, Glob, Grep
context: fork
agent: Explore
---

# Capability Discovery

Discovers available capabilities in the user's environment for dynamic workflow adaptation.

## Iron Law

**DISCOVER BEFORE ASSUMING. Never hardcode tool availability. Always scan the environment first.**

Assuming a tool exists leads to runtime failures. Assuming it doesn't leads to missing capabilities.

## Discovery Process

Steps 1-5 are independent — execute ALL simultaneously with parallel tool calls.

### Step 1: Scan Agents

Use Glob to find agent files, then Grep to extract descriptions:

- `Glob: ".claude/agents/*.md"` — project agents
- `Glob: "plugins/*/agents/*.md"` — plugin agents

Parse: source, name (filename without .md), description (from frontmatter).

### Step 2: Scan Skills

- `Glob: ".claude/skills/*/SKILL.md"` — project skills
- `Glob: "plugins/*/skills/*/SKILL.md"` — plugin skills

Parse: source, name (parent directory), description (from frontmatter).

### Step 3: Scan Commands

- `Glob: ".claude/commands/*.md"` — project commands
- `Glob: "plugins/*/commands/*.md"` — plugin commands

Parse: source, name (filename without .md), description (from frontmatter).

### Step 4: Parse CLAUDE.md for Quality Commands

```bash
CLAUDE_MD=""
[ -f ".claude/CLAUDE.md" ] && CLAUDE_MD=".claude/CLAUDE.md"
[ -z "$CLAUDE_MD" ] && [ -f "CLAUDE.md" ] && CLAUDE_MD="CLAUDE.md"
[ -n "$CLAUDE_MD" ] && grep -E "(npm|pnpm|yarn|bun|ruff|pytest|go |cargo |make )" "$CLAUDE_MD" 2>/dev/null
```

### Step 5: Detect Tech Stack

```bash
[ -f "package.json" ] && echo "node"
[ -f "tsconfig.json" ] && echo "typescript"
[ -f "pyproject.toml" ] && echo "python"
[ -f "Gemfile" ] && echo "ruby"
[ -f "go.mod" ] && echo "go"
[ -f "Cargo.toml" ] && echo "rust"
[ -f "Makefile" ] && echo "makefile"
```

### Early Exit: Markdown-Only

If no tech stack files found and no quality commands in CLAUDE.md, report:
- Quality Commands: "No code-related quality commands applicable"
- Tech Stack: "Markdown-only project"
- Skip Step 6

### Step 6: Discover Verification Capabilities

```bash
ls verify.sh scripts/verify* playwright.config.* cypress.config.* 2>/dev/null
```

## Output Format

```markdown
### Agents Available
| Agent | Source | Description |
|-------|--------|-------------|

### Skills Available
| Skill | Source | Description |
|-------|--------|-------------|

### Quality Commands
| Command | Purpose | Source |
|---------|---------|--------|

### Tech Stack
- {language} ({indicator file})

### Verification Capabilities
| Capability | Command | Source |
|-----------|---------|--------|
```

## Graceful Degradation

| Missing | Fallback |
|---------|----------|
| No agents | Use built-in review checklist |
| No CLAUDE.md commands | Detect from tech stack |
| No tech stack | Ask user for commands |

## Caching

This skill runs in a forked context. The calling command must store the output for use in later phases — do not re-invoke within the same command execution.
