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

## Phase 2: Generate Settings

Based on detection, create `.claude/settings.flow.json` (project-shared, committed with team) with sensible defaults:

```bash
mkdir -p .claude
```

**Ensure `.claude/settings.flow.local.json` is gitignored** (idempotent — adds the line only if missing). Without this, a downstream user creating a personal-pin file as documented in Phase 6 below would commit it accidentally, leaking their machine-local preferences and weakening the project-local override layer:

Also ignore `.claude/*.lock` — `flow-migrate-settings.sh` (and other writers) create a transient `<file>.lock` beside the settings file; the trap removes it, but a hard kill (SIGKILL) could leave one behind, and it must never be committed.

```bash
for IGNORE in '.claude/settings.flow.local.json' '.claude/*.lock'; do
  if [ -f .gitignore ]; then
    grep -qxF "$IGNORE" .gitignore || echo "$IGNORE" >> .gitignore
  else
    echo "$IGNORE" > .gitignore
  fi
done
```

Flow settings follow the standard Claude Code cascade — `local > project > user > plugin default`. Setup writes the project-shared file, which gives the whole team a baseline. Any user can then override locally via `.claude/settings.flow.local.json` (gitignored), set cross-project preferences in `$HOME/.claude/settings.flow.json`, or rely on the plugin's bundled defaults.

**Before writing**, read `$HOME/.claude/settings.flow.json` (if present) and skip writing any key that the user has already set there with a non-default value. Under the unified cascade, project-shared overrides user-global, so writing a key that matches the plugin default would silently override a user's existing personal preference for it. The intent of `/flow:setup` is to establish a team baseline, not to override individual user choices. Use `AskUserQuestion` if any conflict is detected:

> Your `$HOME/.claude/settings.flow.json` already sets `{key}` to `{user-value}`. The team baseline would set it to `{baseline-value}`, which would override your user-global preference because the project-shared tier wins.
>
> Options:
> 1. Skip this key in the project-shared file (your user-global preference remains active here too) — Recommended
> 2. Write the team baseline anyway (overrides your user-global preference for this repo only; you can re-override locally via `.claude/settings.flow.local.json`)
> 3. Cancel — let me edit my user-global file first

Write `.claude/settings.flow.json` with:

- Quality commands discovered from tech stack (`qualityCheckMaxIterations`, `closedLoop.*`, etc.)
- `conventions.branchPatterns` and `conventions.commitTypes` matching existing repository conventions
- `agentTeams: false` (paired-reviewer mode opt-in; users enable per their preference, also requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var)
- `merge.markerTrust.allowedAssociations` at the secure default `["OWNER","MEMBER","COLLABORATOR"]`
- `learning.enabled: true`, `learning.proposalDir` (default `~/.claude/flow-proposals`)
- `journal.dir` (default `.decisions`)
- LSP settings (`lsp.enabled: true`, `lsp.timeout: 5000`, `lsp.diagnosticsAsQuality: true`)
- Tier classification (`tiers.*`), timeouts, debugging settings, verdict settings, testing settings, visualVerification settings

**On re-run** (existing settings detected): Read current settings and merge — preserve user customizations, only add new keys that don't exist yet.

The v3 runtime settings (`flow.goals`, `flow.runtime`, `flow.workflows`, `flow.triggers`) are intentionally **not** written into the team file — they are governed by the plugin defaults via the cascade, so the committed file stays lean. The one thing setup actively does for them is upgrade **deprecated** keys (next step).

### Upgrade deprecated settings (re-run only)

When existing settings are detected, check whether the committed `.claude/settings.flow.json` carries any deprecated keys and offer to upgrade it to the current schema. The runtime already honors deprecated keys read-only (via `cascade-resolve`), so this is a **hygiene upgrade — nothing breaks if declined**. Current migrations: `flow.goals.requireGoalForStart` → `flow.goals.goalCreation` (`true`→`always`, `false`→`off`).

```!
SETTINGS=".claude/settings.flow.json"
MIGRATOR="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/flow-migrate-settings.sh"
if [ -f "$SETTINGS" ] && [ -x "$MIGRATOR" ]; then
  "$MIGRATOR" "$SETTINGS"   # dry-run — emits MIGRATE=... lines (MIGRATE=none when clean)
else
  echo "MIGRATE=skip (no committed settings or migrator unavailable)"
fi
true
```

If the output is `MIGRATE=none` or `MIGRATE=skip`, there is nothing to upgrade — proceed silently. Otherwise it reports the pending change(s) (`MIGRATE_FROM=...` / `MIGRATE_TO=...`). Surface them and use `AskUserQuestion`:

> Your committed `.claude/settings.flow.json` uses deprecated settings keys that can be upgraded to the current schema:
> {the `MIGRATE_FROM` → `MIGRATE_TO` lines}
>
> The runtime already honors the old keys read-only, so this is optional cleanup.
>
> Options:
> 1. **Upgrade now (Recommended)** — rewrite the committed file in place (atomic; every other key preserved)
> 2. **Leave as-is** — the read-only migration keeps it working; the deprecated key stays in version control

On **Upgrade now**, apply the rewrite. This block re-resolves the helper path inline — shell variables from the detection `!`-block above do NOT persist into a separately-executed `bash` block:

```bash
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/flow-migrate-settings.sh" --apply ".claude/settings.flow.json"
```

It writes atomically and preserves all other keys. Note the change in the Phase 6 summary so the user reviews the one-line diff before committing.

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

**Project-shared** (`.claude/settings.flow.json` — committed with team):
- Tech stack: {detected}
- Quality commands: {lint}, {test}, {typecheck}
- Branch patterns, commit types, tiers, timeouts, LSP, learning, journal, etc.
- Agent teams: disabled. To enable paired review, set `agentTeams: true` (in this file for team-wide, or in `.claude/settings.flow.local.json` for personal-pin) AND `export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in your shell.

**Override layers** (standard Claude Code cascade — highest precedence first):
1. `.claude/settings.flow.local.json` — gitignored, your machine-local pin
2. `.claude/settings.flow.json` — committed, team-shared (the file just written)
3. `$HOME/.claude/settings.flow.json` — your cross-project default
4. Plugin default — bundled in flow

Any key set at a higher layer overrides lower layers. See [`references/gate-configuration.md`](../references/gate-configuration.md) for the per-key reference.

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
| Write `.claude/settings.flow.json` (project-shared settings) | 1 | Autonomous, project file |
| Upgrade deprecated keys in an existing `.claude/settings.flow.json` (`flow-migrate-settings.sh --apply`) | 2 | AskUserQuestion before rewriting the committed file; atomic, preserves other keys |
| Write `.claude/CLAUDE.md` flow integration block | 1 | Autonomous, project file |
| Install LSP servers (when user opts in) | 2 | Journal-and-proceed (touches user environment outside repo) |
| `mkdir -p .decisions/` | 1 | Autonomous |
