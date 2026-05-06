---
name: capability-discovery
description: "Discover available agents, skills, quality commands (lint, test, typecheck), tech stack, verification capabilities, and LSP code intelligence features via parallel environment scanning. Use when starting implementation, creating PRs, reviewing PRs, or addressing feedback. This skill MUST be consulted because assuming tools exist causes runtime failures, and assuming they do not causes missing capabilities."
allowed-tools: Bash, Read, Glob, Grep, LSP
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

### Step 7: Discover LSP Capabilities

**Pre-check**: Read `lsp.enabled` from settings (default `true`). If `false`, skip this step and report all LSP features as "Disabled" in the output table.

Probe for available LSP code intelligence features. Find a representative source file in the project (use the first file matching the detected tech stack — e.g., `.ts`, `.py`, `.go`, `.rs`, `.rb`), then test each LSP operation against it.

**LSP feature probes** (run each, catch failures individually):

| Operation | Test | Capability |
|-----------|------|-----------|
| `documentSymbol` | List symbols in the file | Symbol navigation |
| `hover` | Hover on first symbol (line 1, char 1) | Type info / docs |
| `goToDefinition` | Definition lookup on an import or reference | Definition tracing |
| `findReferences` | Find references to a symbol | Impact analysis |
| `goToImplementation` | Find implementations | Interface resolution |

**Diagnostics inference**: LSP diagnostics are not a discrete operation to probe — they are reported by the language server when it processes a file. If `documentSymbol` succeeds, the LSP server is active and diagnostics are available. Record diagnostics as "Available" when `documentSymbol` succeeds, "Unavailable" otherwise.

**Process:**

1. Find a representative source file using Glob (consistent with Steps 1-3):
   - `Glob: "**/*.ts"` or `"**/*.py"` or `"**/*.go"` or `"**/*.rs"` or `"**/*.rb"` (match detected tech stack)
   - Use the first result as the probe target

2. For each operation, attempt an LSP call against the file. Record success or failure:
   - Success → feature is available
   - Error "no LSP server" → LSP not configured for this file type
   - Error/timeout → feature not supported by this server

3. Read `lsp.timeout` from settings (default 5000ms). If an operation doesn't respond within this timeout, mark it as unavailable.

4. Report results in the LSP Capabilities output table.

**Graceful degradation**: If no source files exist (markdown-only project) or no LSP server is configured, report "No LSP server available — using CLI-only analysis" and skip. This is not an error.

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

### LSP Capabilities
| Feature | Status | Use Case |
|---------|--------|----------|
| documentSymbol | {Available/Unavailable} | Symbol navigation in files |
| hover | {Available/Unavailable} | Type info and documentation during CODE phase |
| goToDefinition | {Available/Unavailable} | Trace code paths during EXPLORE phase |
| findReferences | {Available/Unavailable} | Impact analysis during EXPLORE, caller verification during REVIEW |
| goToImplementation | {Available/Unavailable} | Interface resolution |
| diagnostics | {Available/Unavailable} | Quality signal during VERIFY phase (errors→P1, warnings→P2) |
```

## Graceful Degradation

| Missing | Fallback |
|---------|----------|
| No agents | Use built-in review checklist |
| No CLAUDE.md commands | Detect from tech stack |
| No tech stack | Ask user for commands |
| No LSP server | CLI-only analysis (grep/glob for references, CLI tools for diagnostics) |

## Caching

This skill runs in a forked context. The calling command must store the output for use in later phases — do not re-invoke within the same command execution.
