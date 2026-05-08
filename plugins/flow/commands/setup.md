---
description: "Initialize flow for a repository. Detects tech stack, generates settings, configures LSP servers, optionally adds CLAUDE.md sections, and warns about plugin coexistence."
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion, Skill, Glob, Grep, LSP
---

# Setup Flow

Initialize the flow plugin for the current repository. On re-run, detects changes and offers to update settings and install missing LSP servers.

## Required Skills

- `capability-discovery` — detect tech stack, quality commands, existing agents/skills, and LSP capabilities (Phase 1)

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

**Skill(capability-discovery)**: Detect tech stack, quality commands, existing agents/skills, and LSP capabilities.

## Phase 2: Generate Project-Tier Settings

Based on detection, create `.claude/settings.flow.json` (project-tier, shared with team via git) with sensible defaults:

```bash
mkdir -p .claude
```

Write `.claude/settings.flow.json` with **only** the keys that read from the project-tier source. Trimmed-cascade keys (see Phase 2.5) MUST NOT be written here — they would be silently ignored by their consumers and mislead the user into thinking the setting is active. Allowed project-tier keys for setup to write:

- Quality commands discovered from tech stack (`qualityCheckMaxIterations`, `closedLoop.*`, etc.)
- `conventions.branchPatterns` matching existing repository conventions (note: `conventions.commitTypes` is trimmed-cascade — see Phase 2.5)
- `learning.enabled: true` (note: `learning.proposalDir` is trimmed-cascade — see Phase 2.5)
- LSP settings (`lsp.enabled: true`, `lsp.timeout: 5000`, `lsp.diagnosticsAsQuality: true`)
- Tier classification (`tiers.*`), timeouts, debugging settings, verdict settings, testing settings, visualVerification settings

Do NOT write `agentTeams`, `merge.markerTrust.*`, `conventions.commitTypes`, `journal.dir`, or `learning.proposalDir` to this file. They live in `$HOME/.claude/settings.flow.json` per Phase 2.5.

**On re-run** (existing settings detected): Read current settings and merge — preserve user customizations, only add new keys that don't exist yet. If the existing project-tier file contains any trimmed-cascade keys (an artifact of pre-issue-#101 setup runs), surface them to the user via `AskUserQuestion`:

> Found trimmed-cascade keys in `.claude/settings.flow.json` that are silently ignored: `{list}`. These belong in `$HOME/.claude/settings.flow.json` (Phase 2.5).
>
> Options:
> 1. Migrate them to `$HOME/.claude/settings.flow.json` (Recommended)
> 2. Leave as-is (they will continue to be ignored)
> 3. Delete them from project-tier (clean state, re-add via Phase 2.5)

## Phase 2.5: Generate User-Tier Settings (Trimmed-Cascade Keys)

Some flow settings are read from a **trimmed cascade** — `$HOME/.claude/settings.flow.json` (user-tier override) and `${CLAUDE_PLUGIN_ROOT}/settings.json` (plugin default) only. They intentionally exclude project-tier files because a hostile fork PR could otherwise commit `.claude/settings.flow.json` / `.local.json` and bypass the relevant security gate after `gh pr checkout`. See [`references/gate-configuration.md`](../references/gate-configuration.md) for the full threat model.

Trimmed-cascade keys:

| Key | Used by | Default | Why trimmed |
|-----|---------|---------|-------------|
| `agentTeams` | `commands/review.md` Path A gate | `false` | Cost amplification — a hostile fork enabling paired review fans out reviewers and inflates token cost |
| `merge.markerTrust.allowedAssociations` | `commands/{merge,status}.md` | `["OWNER","MEMBER","COLLABORATOR"]` | A permissive list lets a forked-PR author forge their own resolution markers and bypass the merge gate |
| `conventions.commitTypes` | `agents/convention-checker.md` | `["feat","fix","docs","style","refactor","test","chore","perf","ci","build","revert","improve"]` | A relaxed list (e.g. `[".*"]`) defeats commit-message validation in PR review |
| `journal.dir` | `bin/journal-record.sh` + several hooks | `.decisions` | Redirects every journal/hook write to an attacker-controlled path |
| `learning.proposalDir` | `commands/learn.md` | `~/.claude/flow-proposals` | Redirects `/flow:learn` proposals; subsequent `bin/promote-proposal.sh` could promote attacker content as a "learned skill" |

### Step 2.5.1: Check existing user-tier file

```bash
USER_SETTINGS="${HOME:-/nonexistent}/.claude/settings.flow.json"
[ -f "$USER_SETTINGS" ] && echo "USER_SETTINGS_EXISTS=true" || echo "USER_SETTINGS_EXISTS=false"
```

### Step 2.5.2: Offer to create or update

Use `AskUserQuestion` (3 options):

> Configure user-tier flow settings at `$HOME/.claude/settings.flow.json`?
>
> This file persists across plugin upgrades and is the supported location for the trimmed-cascade keys above.
>
> Options:
> 1. Create with minimal opt-in surface — just `agentTeams: false` and `merge.markerTrust.allowedAssociations` defaults documented (Recommended for new installs; you can edit `agentTeams: true` later when you want paired review)
> 2. Create with all five trimmed-cascade keys at their defaults — explicit baseline you can edit
> 3. Skip — you'll create or edit the file manually later

If user chooses option 1 or 2, merge the chosen keys into the existing file (or create it). Do NOT overwrite an existing user-tier file blindly — read it first, write only keys that are missing, and surface any conflicts via `AskUserQuestion`.

For `agentTeams: true` specifically, also remind the user that they need `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in their shell environment for Path A to activate (two-key gate). Setup does NOT modify the user's shell profile — it only documents the requirement.

### Step 2.5.3: Verify

```bash
if [ -f "$USER_SETTINGS" ] && jq -e '.' "$USER_SETTINGS" >/dev/null 2>&1; then
  echo "USER_SETTINGS: ready ($USER_SETTINGS)"
else
  echo "USER_SETTINGS: not configured"
fi
```

## Phase 3: LSP Server Setup

Configure Language Server Protocol servers for the detected tech stack. LSP provides code intelligence (go-to-definition, find-references, hover, diagnostics) that flow uses in EXPLORE, CODE, VERIFY, and REVIEW phases.

### Step 3.1: Check LSP Prerequisites

```bash
# Check if ENABLE_LSP_TOOL is set
echo "${ENABLE_LSP_TOOL:-not_set}"

# Check for installed LSP plugins
claude plugins list 2>/dev/null | grep -i lsp || echo "NO_LSP_PLUGINS"
```

### Step 3.2: Map Tech Stack to LSP Servers

Based on the tech stack detected in Phase 1, determine which LSP servers are needed:

| Tech Stack | LSP Server | Plugin Name | Binary Install | Verify |
|------------|-----------|-------------|----------------|--------|
| TypeScript/JavaScript | vtsls | vtsls | `npm i -g @vtsls/language-server typescript` | `npx @vtsls/language-server --version` |
| Python | pyright | pyright | `npm i -g pyright` | `pyright --version` |
| Go | gopls | gopls | `go install golang.org/x/tools/gopls@latest` | `gopls version` |
| Rust | rust-analyzer | rust-analyzer | `rustup component add rust-analyzer` | `rust-analyzer --version` |
| Ruby | ruby-lsp | ruby-lsp | `gem install ruby-lsp` | `ruby-lsp --version` |
| Java | jdtls | jdtls | `brew install jdtls` | `jdtls --version` |
| C/C++ | clangd | clangd | `brew install llvm` | `clangd --version` |
| HTML/CSS | vscode-langservers | vscode-html-css | `npm i -g vscode-langservers-extracted` | `vscode-html-language-server --version` |

### Step 3.3: Check Existing LSP Installation

For each language in the detected tech stack, check if the binary is already installed:

```bash
# Check each relevant binary (only for detected languages)
command -v typescript-language-server 2>/dev/null && echo "VTSLS: installed" || echo "VTSLS: missing"
command -v pyright 2>/dev/null && echo "PYRIGHT: installed" || echo "PYRIGHT: missing"
command -v gopls 2>/dev/null && echo "GOPLS: installed" || echo "GOPLS: missing"
command -v rust-analyzer 2>/dev/null && echo "RUST-ANALYZER: installed" || echo "RUST-ANALYZER: missing"
command -v ruby-lsp 2>/dev/null && echo "RUBY-LSP: installed" || echo "RUBY-LSP: missing"
```

### Step 3.4: Present LSP Setup Plan

Use the **AskUserQuestion tool** to present the LSP installation plan:

> "Flow uses LSP code intelligence for semantic code understanding across workflow phases. Here's what's needed for your tech stack:"

Show a summary table of:
- Detected languages
- Which LSP servers are already installed (binary found)
- Which are missing

**Options:**
1. "Install all missing LSP servers (Recommended)" — Install all missing binaries and register the LSP plugin marketplace
2. "Choose which to install" — Select specific languages
3. "Skip LSP setup" — Use CLI-only analysis (grep/glob fallback)

### Step 3.5: Install LSP Servers

If the user chooses to install:

**1. Enable LSP tool** (if not already set):

Check `~/.claude/settings.json` for `ENABLE_LSP_TOOL`. If missing, inform the user:

```markdown
**LSP Tool Activation Required**

Add to your shell profile (`~/.zshrc` or `~/.bashrc`):
```bash
export ENABLE_LSP_TOOL=1
```

Or add to `~/.claude/settings.json`:
```json
{
  "env": {
    "ENABLE_LSP_TOOL": "1"
  }
}
```

Then restart Claude Code for the change to take effect.
```

**2. Register LSP plugin marketplace** (if not already registered):

```bash
# Check if an LSP marketplace is already registered
claude plugins list 2>/dev/null | grep -i "claude-code-lsps" || echo "NO_LSP_MARKETPLACE"
```

If no LSP marketplace found, register one. Use the **AskUserQuestion tool**:

**Options:**
1. "Piebald-AI/claude-code-lsps (Recommended)" — Comprehensive marketplace with 20+ languages
2. "Skip marketplace — install binaries only" — Manual LSP server management

If marketplace selected:
```bash
claude plugin marketplace add Piebald-AI/claude-code-lsps
```

**3. Install language server binaries:**

For each missing server the user approved, run the install command:

```bash
# TypeScript/JavaScript
npm i -g @vtsls/language-server typescript

# Python
npm i -g pyright

# Go
go install golang.org/x/tools/gopls@latest

# Rust
rustup component add rust-analyzer

# Ruby
gem install ruby-lsp
```

**4. Install LSP plugins** (if marketplace was registered):

```bash
# Install plugins for each detected language
# e.g., for a TypeScript + Python project:
claude plugin install vtsls@claude-code-lsps
claude plugin install pyright@claude-code-lsps
```

### Step 3.6: Verify Installation

After installation, verify each server is accessible:

```bash
# Re-check binaries
command -v typescript-language-server 2>/dev/null && echo "vtsls: OK"
command -v pyright 2>/dev/null && echo "pyright: OK"
command -v gopls 2>/dev/null && echo "gopls: OK"
command -v rust-analyzer 2>/dev/null && echo "rust-analyzer: OK"
command -v ruby-lsp 2>/dev/null && echo "ruby-lsp: OK"
```

If any server fails to verify, report it in the summary with the manual install command.

### Step 3.7: Probe LSP Capabilities

After installation, use the LSP tool to probe a representative source file and confirm the language server is responding:

```
LSP(documentSymbol) on a project source file
```

Record which capabilities are confirmed working. If the LSP tool returns an error (e.g., Claude Code restart needed), note this in the summary.

### Re-run Behavior

On re-run (`EXISTING_SETTINGS=true`), Phase 3 adapts:

1. **Detect new languages** — Compare current tech stack against previously configured LSP servers. If new languages appeared (e.g., added Python to a TypeScript project), offer to install their LSP servers.
2. **Verify existing servers** — Check that previously installed binaries are still accessible. Report any that have gone missing.
3. **Skip if fully configured** — If all detected languages have working LSP servers, report "LSP: all servers operational" and skip the installation prompts.

## Phase 4: Coexistence Warning

If gh-workflow is detected:

```markdown
**Note**: gh-workflow plugin detected in this repository.

The flow plugin can coexist alongside gh-workflow, but you should only
enable one at a time to avoid hook conflicts.

Commands use different prefixes:
- gh-workflow: `/gh-start`, `/gh-commit`, `/gh-pr`
- flow: `/flow:start`, `/flow:commit`, `/flow:pr`
```

## Phase 5: CLAUDE.md Integration

Use the AskUserQuestion tool with contextual options to ask: "Add flow workflow section to CLAUDE.md?"

If yes, append the workflow section from `templates/CLAUDE-flow.md` to the existing CLAUDE.md.

## Phase 6: Summary

```markdown
## Flow Setup Complete

### Settings

**Project-tier** (`.claude/settings.flow.json` — shared with team):
- Tech stack: {detected}
- Quality commands: {lint}, {test}, {typecheck}
- Branch patterns, tiers, timeouts, LSP, learning.enabled, etc.

**User-tier** (`$HOME/.claude/settings.flow.json` — trimmed-cascade keys):
{If Phase 2.5 ran:}
- Status: configured
- agentTeams: {value} — to enable paired review, set `agentTeams: true` here AND `export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in your shell (two-key gate)
- merge.markerTrust.allowedAssociations: {value}
- conventions.commitTypes, journal.dir, learning.proposalDir: {value or "default"}

{If user skipped Phase 2.5:}
- Status: not configured. To enable trimmed-cascade keys (agentTeams, merge.markerTrust, etc.), re-run `/flow:setup` or create the file manually. See [`references/gate-configuration.md`](../references/gate-configuration.md).

### LSP Code Intelligence
| Language | Server | Status | Capabilities |
|----------|--------|--------|-------------|
| {language} | {server} | {Installed/Missing/Skipped} | {available features} |

{If any servers need manual steps:}
### Manual Steps Required
- [ ] Add `export ENABLE_LSP_TOOL=1` to shell profile and restart Claude Code
- [ ] Run `{install command}` to install {server}
- [ ] Restart Claude Code after plugin installation

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

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Detect environment, tech stack, build commands | 1 | Autonomous, read-only |
| Probe LSP capabilities | 1 | Autonomous, read-only |
| Write `.claude/settings.flow.json` (project settings) | 1 | Autonomous, project file |
| Write `$HOME/.claude/settings.flow.json` (user-tier trimmed-cascade keys, Phase 2.5) | 2 | Asks via `AskUserQuestion` first; touches user environment outside repo |
| Migrate trimmed-cascade keys out of project-tier (Phase 2 re-run path) | 2 | Asks via `AskUserQuestion`; deletes/relocates only with confirmation |
| Write `.claude/CLAUDE.md` flow integration block | 1 | Autonomous, project file |
| Install LSP servers (when user opts in) | 2 | Journal-and-proceed (touches user environment outside repo) |
| `mkdir -p .decisions/` | 1 | Autonomous |
