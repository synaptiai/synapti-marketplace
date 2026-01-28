---
name: capability-discovery
description: Use before workflow execution to discover available agents, skills, and quality commands in the project environment. Use when adapting gh-workflow commands to project-specific tooling.
allowed-tools: Bash, Read, Glob, Grep
context: fork
agent: Explore
---

# Capability Discovery

This skill discovers available capabilities (skills, agents, commands) in the user's environment to enable dynamic workflow adaptation.

## Purpose

Before executing workflows, discover what tools are available so commands can:
- Invoke specialized agents if available
- Use custom skills instead of defaults
- Apply project-specific quality commands
- Gracefully fall back when capabilities are missing

## Discovery Process

### Step 1: Scan for Custom Agents

```bash
# Project-level agents
ls .claude/agents/*.md 2>/dev/null | xargs -I {} basename {} .md

# Plugin agents
ls plugins/*/agents/*.md 2>/dev/null | while read f; do
  plugin=$(echo $f | cut -d'/' -f2)
  agent=$(basename $f .md)
  echo "$plugin:$agent"
done
```

### Step 2: Scan for Custom Skills

```bash
# Project-level skills
ls .claude/skills/*/SKILL.md 2>/dev/null | while read f; do
  skill=$(dirname $f | xargs basename)
  echo "$skill"
done

# Plugin skills
ls plugins/*/skills/*/SKILL.md 2>/dev/null | while read f; do
  plugin=$(echo $f | cut -d'/' -f2)
  skill=$(dirname $f | xargs basename)
  echo "$plugin:$skill"
done
```

### Step 3: Scan for Custom Commands

```bash
# Project-level commands
ls .claude/commands/*.md 2>/dev/null | xargs -I {} basename {} .md

# Plugin commands
ls plugins/*/commands/*.md 2>/dev/null | while read f; do
  plugin=$(echo $f | cut -d'/' -f2)
  cmd=$(basename $f .md)
  echo "$plugin:$cmd"
done
```

### Step 4: Parse CLAUDE.md for Quality Commands

```bash
# Look for explicit quality command definitions
grep -E "^(lint|test|check|format|typecheck|build):" .claude/CLAUDE.md 2>/dev/null

# Look for npm scripts references
grep -E "npm run (lint|test|check|format|build)" .claude/CLAUDE.md 2>/dev/null

# Look for Python tool references
grep -E "(ruff|pytest|mypy|pyright|black|isort)" .claude/CLAUDE.md 2>/dev/null

# Look for Go tool references
grep -E "(go vet|go test|golangci-lint)" .claude/CLAUDE.md 2>/dev/null
```

### Step 5: Detect Tech Stack

```bash
# Check for common project files
[ -f "pyproject.toml" ] && echo "python"
[ -f "package.json" ] && echo "node"
[ -f "tsconfig.json" ] && echo "typescript"
[ -f "go.mod" ] && echo "go"
[ -f "Cargo.toml" ] && echo "rust"
[ -f "Gemfile" ] && echo "ruby"
```

## Output Format

Report discovered capabilities in structured format:

```markdown
## Discovered Capabilities

### Agents Available
| Agent | Source | Description |
|-------|--------|-------------|
| code-reviewer | gh-workflow | Code quality analysis |
| convention-checker | gh-workflow | Git convention validation |
| test-runner | gh-workflow | Quality command execution |
| custom-agent | project | [from agent description] |

### Skills Available
| Skill | Source | Description |
|-------|--------|-------------|
| repo-config | gh-workflow | Dynamic repo configuration |
| capability-discovery | gh-workflow | This skill |
| lint | project | Custom lint configuration |

### Quality Commands (from CLAUDE.md)
| Command | Purpose |
|---------|---------|
| `ruff check .` | Python linting |
| `pytest` | Python tests |
| `npm run lint` | JavaScript linting |

### Tech Stack Detected
- Python (pyproject.toml found)
- TypeScript (tsconfig.json found)

### Recommended Workflow
Based on capabilities:
1. Use `code-reviewer` agent for code analysis
2. Use `convention-checker` for Git validation
3. Run `ruff check .` then `pytest` for quality
4. Invoke `lint` skill if project-specific
```

## Usage in Commands

### In gh-start

```markdown
## Phase 1.5: Capability Discovery

Before implementation:
1. Invoke capability-discovery skill
2. Note available agents for later review phases
3. Note quality commands for Phase 3
4. Store tech stack for appropriate tooling
```

### In gh-review

```markdown
## Phase 1.5: Review Capability Discovery

Before detailed review:
1. Check for review-specific agents (code-reviewer, convention-checker)
2. Check for quality skills (lint, test)
3. Plan review facets based on available capabilities
```

## Graceful Degradation

When capabilities are not found:

| Missing Capability | Fallback |
|-------------------|----------|
| No custom agents | Use built-in review checklist |
| No lint skill | Detect from tech stack |
| No CLAUDE.md commands | Use standard tools for detected stack |
| No tech stack detected | Ask user for commands |

## Integration Points

This skill is invoked by:
- `gh-start` - Before implementation
- `gh-review` - Before code review
- `gh-address` - Before addressing feedback

Results inform:
- Which agents to delegate to
- Which quality commands to run
- How to adapt workflow to project

## Best Practices

1. **Cache results** - Don't re-scan within same session
2. **Prefer explicit** - CLAUDE.md commands over detected ones
3. **Report clearly** - Show what was found and what wasn't
4. **Enable fallbacks** - Never block workflow due to missing capabilities
