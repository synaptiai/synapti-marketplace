---
description: "Initialize flow for a repository. Detects tech stack, generates settings, configures LSP servers, warns about plugin coexistence, offers GitHub rulesets for the default branch and tags, and optionally adds CLAUDE.md sections."
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion, Skill, Glob, Grep, LSP
---

# Setup Flow

Initialize the flow plugin for the current repository. On re-run, detects changes and offers to update settings and install missing LSP servers.

## Required Skills

- `capability-discovery` — detect tech stack, quality commands, existing agents/skills, and LSP capabilities (Phase 1)

```!
# Inline the Required Skills above so their rules are in context before the
# first phase runs (commands cannot preload skills from frontmatter). Ambient
# skills load whole; dispatched skills (context: fork / agent:) load their
# `## Contract` section and run in full when this command invokes
# Skill(<name>). Output per `references/command-output-format.md`.
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-load-skills.sh" capability-discovery

true
```

## Phase 1: Detect Environment

**Parallel operations:**

```bash
# 1. Check for existing flow settings
[ -f ".claude/settings.flow.json" ] && printf '%s\n' "EXISTING_SETTINGS=true" || printf '%s\n' "EXISTING_SETTINGS=false"

# 2. Check for gh-workflow: prints the line only when this repository holds
# both plugins/gh-workflow/.claude-plugin/plugin.json and
# .claude/settings.gh-workflow.json (an in-repo copy of the plugin with its
# settings file); an installed gh-workflow plugin is not detected
ls plugins/gh-workflow/.claude-plugin/plugin.json .claude/settings.gh-workflow.json 2>/dev/null && printf '%s\n' "GH_WORKFLOW_DETECTED=true"

# 3. Check CLAUDE.md
[ -f ".claude/CLAUDE.md" ] && printf '%s\n' "CLAUDE_MD=.claude/CLAUDE.md"
[ -f "CLAUDE.md" ] && printf '%s\n' "CLAUDE_MD=CLAUDE.md"

# 4. Git remote
git remote -v | head -2
gh auth status 2>&1 | head -3

# 5. timeout(1) or gtimeout (GNU coreutils), which the verdict judge
# (/flow:start Phase 4) and the goal judge run under; stock macOS has neither
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  printf '%s\n' "TIMEOUT_BIN=found"
else
  printf '%s\n' "TIMEOUT_BIN=missing — the verdict judge and the goal judge need timeout(1) or gtimeout (install GNU coreutils; on macOS: brew install coreutils)"
fi
```

On `TIMEOUT_BIN=missing`, add the coreutils install to **Manual Steps Required** in the Phase 7 summary: without it the verdict judge and the goal judge report that they could not start (exit 4).

**Skill(capability-discovery)**: Detect tech stack, quality commands, existing agents/skills, and LSP capabilities.

## Phase 2: Generate Settings

Based on detection, create `.claude/settings.flow.json` (project-shared, committed with team) with sensible defaults:

```bash
mkdir -p .claude
```

**Ensure `.claude/settings.flow.local.json` is gitignored** (idempotent — adds the line only if missing). Without this, a downstream user creating a personal-pin file as documented in Phase 7 below would commit it accidentally, leaking their machine-local preferences and weakening the project-local override layer:

Also ignore `.claude/*.lock` — `flow-migrate-settings.sh` (and other writers) create a transient `<file>.lock` beside the settings file; the trap removes it, but a hard kill (SIGKILL) could leave one behind, and it must never be committed.

Also ignore the auto-log trail, `<journal.dir>/auto-log/`. The PostToolUse hooks write a breadcrumb there after every edit and commit; it is local scratch, not journal content, and an unignored directory would leave the working tree permanently dirty. The hooks also drop a self-ignoring `.gitignore` inside that directory, so this line is belt-and-braces rather than the only defense — but a project should not depend on a hook having run to keep its own tree clean.

Also ignore `<runtime dir>/watch/` (the runtime directory, `flow.runtime.stateDir`, default `.flow`, as `bin/flow-runtime-dir.sh` resolves it), where `/flow:watch issue <N>` keeps the issue snapshot of each loop iteration. It is local state; `/flow:watch` also writes a `.gitignore` of `*` inside it.

```bash
JOURNAL_DIR=".decisions"
RESOLVER="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/cascade-resolve.sh"
[ -x "$RESOLVER" ] && JOURNAL_DIR=$("${RESOLVER%/cascade-resolve.sh}/journal-dir.sh" 2>/dev/null)
[ -n "$JOURNAL_DIR" ] || JOURNAL_DIR=".decisions"
RUNTIME_DIR=".flow"
[ -x "$RESOLVER" ] && RUNTIME_DIR=$("${RESOLVER%/cascade-resolve.sh}/flow-runtime-dir.sh")
RUNTIME_DIR=${RUNTIME_DIR#./}
[ -n "$RUNTIME_DIR" ] || RUNTIME_DIR=".flow"
for IGNORE in '.claude/settings.flow.local.json' '.claude/*.lock' "$RUNTIME_DIR/watch/" "$JOURNAL_DIR/auto-log/"; do
  if [ -f .gitignore ]; then
    grep -qxF "$IGNORE" .gitignore || printf '%s\n' "$IGNORE" >> .gitignore
  else
    printf '%s\n' "$IGNORE" > .gitignore
  fi
done
```

Flow settings follow the standard Claude Code cascade — `local > project > user > plugin default`. Setup writes the project-shared file, which gives the whole team a baseline. Any user can then override locally via `.claude/settings.flow.local.json` (gitignored), set cross-project preferences in `$HOME/.claude/settings.flow.json`, or rely on the plugin's bundled defaults.

**Before writing**, read your user settings file — the file `bin/cascade-resolve.sh --user-settings-path` prints: `$FLOW_USER_SETTINGS` when you set it (a value inside the repository or set by it is ignored), otherwise `$HOME/.claude/settings.flow.json` — (if present) and skip writing any key that the user has already set there with a non-default value. Under the unified cascade, project-shared overrides user-global, so writing a key that matches the plugin default would silently override a user's existing personal preference for it. The intent of `/flow:setup` is to establish a team baseline, not to override individual user choices. Use `AskUserQuestion` if any conflict is detected:

> Your user settings file (`{user-settings-path}`: `$FLOW_USER_SETTINGS` when you set it, otherwise `$HOME/.claude/settings.flow.json`) already sets `{key}` to `{user-value}`. The team baseline would set it to `{baseline-value}`, which would override your user-global preference because the project-shared tier wins.
>
> Options:
> 1. Skip this key in the project-shared file (your user-global preference remains active here too) — Recommended
> 2. Write the team baseline anyway (overrides your user-global preference for this repo only; you can re-override locally via `.claude/settings.flow.local.json`)
> 3. Cancel — let me edit my user-global file first

Write `.claude/settings.flow.json` with:

- Quality commands discovered from tech stack (`timeouts.qualityCheckMaxIterations`, `closedLoop.*`, etc.)
- `conventions.branchPatterns` and `conventions.commitTypes` matching existing repository conventions
- `agentTeams: false` (paired-reviewer mode opt-in; users enable per their preference, also requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var)
- `merge.markerTrust.allowedAssociations` at the secure default `["OWNER","MEMBER","COLLABORATOR"]`
- `learning.enabled: true`. Not `learning.proposalDir` or `learning.transcriptDir`: Flow reads those from the user settings file only, so a value written here would be ignored
- `journal.dir` (default `.decisions`). Written here it is a repository setting, so it must resolve inside the repository; a directory outside the checkout belongs in the user's own `~/.claude/settings.flow.json`
- LSP settings (`lsp.enabled: true`, `lsp.timeout: 5000`, `lsp.diagnosticsAsQuality: true`)
- Tier classification (`tiers.*`), timeouts, debugging settings, verdict settings, testing settings, visualVerification settings. The `tier-gate.sh` hook applies `tiers.*` to every Bash command: `push`, `prCreate`, `issueAssign` and `issueCreate` take `autonomous`, `journal` or `confirm`; `merge` and `release` (which includes pushing a tag) are always `confirm`, and a lower value there is ignored with a warning

**On re-run** (existing settings detected): Read current settings and merge — preserve user customizations, only add new keys that don't exist yet.

The runtime settings (`flow.goals`, `flow.runtime`, `flow.workflows`, `flow.triggers`) are intentionally **not** written into the team file — they are governed by the plugin defaults via the cascade, so the committed file stays lean. The one thing setup actively does for them is upgrade **deprecated** keys (next step).

### Upgrade deprecated settings (re-run only)

When existing settings are detected, check whether the committed `.claude/settings.flow.json` carries any deprecated keys and offer to upgrade it to the current schema. The runtime already honors deprecated keys read-only (via `cascade-resolve`), so this is a **hygiene upgrade — nothing breaks if declined**. Current migrations: `flow.goals.requireGoalForStart` → `flow.goals.goalCreation` (`true`→`always`, `false`→`off`).

```!
SETTINGS=".claude/settings.flow.json"
MIGRATOR="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-migrate-settings.sh"
if [ -f "$SETTINGS" ] && [ -x "$MIGRATOR" ]; then
  "$MIGRATOR" "$SETTINGS"   # dry-run — emits MIGRATE=... lines (MIGRATE=none when clean)
else
  printf '%s\n' "MIGRATE=skip (no committed settings or migrator unavailable)"
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
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-migrate-settings.sh" --apply ".claude/settings.flow.json"
```

It writes atomically and preserves all other keys. Note the change in the Phase 7 summary so the user reviews the one-line diff before committing.

### Strip legacy auto-log lines (re-run only)

Before the breadcrumbs moved to the gitignored trail, the hooks appended them to the tracked journal, so a repository that has been using flow carries them in version control. This offers to remove them. Like the settings migration this is a **hygiene upgrade — nothing breaks if declined**; the journals keep working, they just keep showing the residue in diffs.

Only the emitter lines are removed, and only outside fenced code blocks, so prose that mentions the format and quoted schema examples are untouched. A re-run reports `none`.

```!
STRIPPER="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-strip-auto-log.sh"
if [ -x "$STRIPPER" ]; then
  "$STRIPPER"   # dry-run — emits STRIP_AUTO_LOG=... lines
else
  printf '%s\n' "STRIP_AUTO_LOG=skip (stripper unavailable)"
fi
true
```

If the output is `STRIP_AUTO_LOG=none` or `STRIP_AUTO_LOG=skip`, there is nothing to strip — proceed silently. Otherwise it reports the pending change (`STRIP_AUTO_LOG_FILE=` per file, then `STRIP_AUTO_LOG=<n> files, <m> lines`).

**A `STRIP_AUTO_LOG_WARN=` line is not part of that count and must be surfaced separately.** It names a journal left partially stripped because it ends inside an unbalanced code fence, and a run can emit it with `0 files, 0 lines` — so an operator shown only the FILE lines would be told nothing about the journal that needs a manual look. When it appears, name the journal and say it was left as-is.

Surface the pending changes and use `AskUserQuestion`:

> Your tracked decision journals carry {m} auto-log lines written by the hooks before they were moved to a local, gitignored trail:
> {the STRIP_AUTO_LOG_FILE lines}
>
> The hooks no longer write there, so this is a one-time cleanup of residue already committed.
>
> Options:
> 1. **Strip them now (Recommended)** — rewrite those journals in place (atomic; every decision entry, specification section and manifest key preserved)
> 2. **Leave as-is** — the journals keep working; the breadcrumbs stay in version control and in every future diff of those files

On **Strip them now**, apply the rewrite. As with the migration above, this block re-resolves the helper path inline — shell variables from the detection `!`-block do NOT persist into a separately-executed `bash` block:

```bash
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-strip-auto-log.sh" --apply
```

This rewrites tracked files, so note it in the Phase 7 summary — the user reviews the deletions before committing, and a large diff here is expected on a first run.

## Phase 3: LSP Server Setup

Configure Language Server Protocol servers for the detected tech stack. LSP provides code intelligence (go-to-definition, find-references, hover, diagnostics) that flow uses in EXPLORE, CODE, VERIFY, and REVIEW phases.

### Step 3.1: Check LSP Prerequisites

```bash
# Check if ENABLE_LSP_TOOL is set
printf '%s\n' "${ENABLE_LSP_TOOL:-not_set}"

# Check for installed LSP plugins
claude plugins list 2>/dev/null | grep -i lsp || printf '%s\n' "NO_LSP_PLUGINS"
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
command -v vtsls 2>/dev/null && printf '%s\n' "VTSLS: installed" || printf '%s\n' "VTSLS: missing"
command -v pyright 2>/dev/null && printf '%s\n' "PYRIGHT: installed" || printf '%s\n' "PYRIGHT: missing"
command -v gopls 2>/dev/null && printf '%s\n' "GOPLS: installed" || printf '%s\n' "GOPLS: missing"
command -v rust-analyzer 2>/dev/null && printf '%s\n' "RUST-ANALYZER: installed" || printf '%s\n' "RUST-ANALYZER: missing"
command -v ruby-lsp 2>/dev/null && printf '%s\n' "RUBY-LSP: installed" || printf '%s\n' "RUBY-LSP: missing"
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
claude plugins list 2>/dev/null | grep -i "claude-code-lsps" || printf '%s\n' "NO_LSP_MARKETPLACE"
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
command -v vtsls 2>/dev/null && printf '%s\n' "vtsls: OK"
command -v pyright 2>/dev/null && printf '%s\n' "pyright: OK"
command -v gopls 2>/dev/null && printf '%s\n' "gopls: OK"
command -v rust-analyzer 2>/dev/null && printf '%s\n' "rust-analyzer: OK"
command -v ruby-lsp 2>/dev/null && printf '%s\n' "ruby-lsp: OK"
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

The flow plugin can be installed alongside gh-workflow. The two provide
similar commands for the same steps (start, commit, PR, review, address,
merge, release), and both keep the decision journal for an issue in
`.decisions/issue-{N}.md` by default, so use one plugin's commands for a
given issue.

Commands use different prefixes:
- gh-workflow: `/gh-start`, `/gh-commit`, `/gh-pr`
- flow: `/flow:start`, `/flow:commit`, `/flow:pr`
```

## Phase 5: GitHub Rulesets

flow's tier checks (the `tier-gate.sh` hook and the `git` and `gh` wrappers) run on this machine and are best-effort: a program other than git or gh, git run by its full path, or a login shell gets past them (`references/three-tier-safety.md`). Rules on GitHub apply to every push and merge, from any machine or tool. Offer them here; skip this phase in a repository with no GitHub remote.

Read what the repository has. The block prints `RULESETS=` one of `none`, `flow` (both of flow's rulesets exist), `other` (the repository has rulesets, not both of flow's), `unavailable` (GitHub refused: a private repository on the free plan, or no admin rights), `unreadable` (any other failure) or `noremote` (no git remote; skip this phase), and `REPO=owner/name`:

```bash
# SETUP_RULESETS_BEGIN
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || REPO=""
if ! git remote 2>/dev/null | grep -q .; then
  printf '%s\n' "RULESETS=noremote"
  printf '%s\n' "REPO="
elif [ -z "$REPO" ]; then
  printf '%s\n' "RULESETS=unreadable"
  printf '%s\n' "REPO="
else
  printf '%s\n' "REPO=$REPO"
  if ! OUT=$(gh api --paginate "repos/$REPO/rulesets" --jq '.[].name' 2>&1); then
    case "$OUT" in
      *"HTTP 403"*|*"HTTP 404"*|*"Upgrade to GitHub Pro"*) printf '%s\n' "RULESETS=unavailable" ;;
      *) printf '%s\n' "RULESETS=unreadable" ;;
    esac
  elif printf '%s\n' "$OUT" | grep -qx 'flow: default branch' && printf '%s\n' "$OUT" | grep -qx 'flow: tags'; then
    printf '%s\n' "RULESETS=flow"
  elif [ -n "$OUT" ]; then
    printf '%s\n' "RULESETS=other"
  else
    printf '%s\n' "RULESETS=none"
  fi
fi
# SETUP_RULESETS_END
```

On `flow`, report that flow's rulesets are in place and go on. On `unavailable` or `unreadable`, add a line to **Manual Steps Required** in the Phase 7 summary: rulesets could not be read or created here, and an owner of the repository can add them under Settings → Rules. On `noremote`, skip this phase. Otherwise (`none` or `other`, naming the existing rulesets on `other`; a flow ruleset that already exists is reported as `FAILED=` with GitHub's message when created again), use the AskUserQuestion tool, saying what each choice does on GitHub and what it does not:

- **Protect the default branch and tags** (recommended): the default branch accepts changes only through a pull request and cannot be force-pushed or deleted; a tag cannot be moved or deleted once it is on GitHub. Merging a pull request and creating a new tag or release still need only write access.
- **The same, and require one approving review**: a pull request also needs an approving review from someone other than its author, given after its last push, before it can be merged; a push after the approval dismisses it. This is the setting that stops a merge made with your own credentials, by you or by an agent. A maintainer who works alone cannot then merge their own pull requests.
- **Skip**: create nothing.

Only after the user picks one of the first two, run the block below with `REPO` from the block above and `APPROVALS` set to `0` for the first choice or `1` for the second. If the user skips, create nothing. Each ruleset's result is printed as `CREATED=<name>` or `FAILED=<name>: <GitHub's message>`:

```bash
# SETUP_RULESETS_CREATE_BEGIN
if [ -z "${REPO:-}" ] || ! printf '%s' "${APPROVALS:-}" | grep -qx '[01]'; then
  printf '%s\n' "FAILED=all: REPO and APPROVALS (0 or 1) must be set"
else
  BODY=$(mktemp "${TMPDIR:-/tmp}/flow-ruleset.XXXXXX") || BODY=""
  if [ -z "$BODY" ]; then
    printf '%s\n' "FAILED=all: could not create a temporary file"
  else
    jq -n --argjson n "$APPROVALS" '{
      name: "flow: default branch", target: "branch", enforcement: "active",
      conditions: {ref_name: {include: ["~DEFAULT_BRANCH"], exclude: []}},
      rules: [
        {type: "deletion"}, {type: "non_fast_forward"},
        {type: "pull_request", parameters: {
          required_approving_review_count: $n, dismiss_stale_reviews_on_push: ($n > 0),
          require_code_owner_review: false, require_last_push_approval: ($n > 0),
          required_review_thread_resolution: false}}]}' > "$BODY"
    if ERR=$(gh api -X POST "repos/$REPO/rulesets" --input "$BODY" 2>&1 >/dev/null); then
      printf '%s\n' "CREATED=flow: default branch"
    else
      printf '%s\n' "FAILED=flow: default branch: $(printf '%s' "$ERR" | head -n 1)"
    fi
    jq -n '{
      name: "flow: tags", target: "tag", enforcement: "active",
      conditions: {ref_name: {include: ["~ALL"], exclude: []}},
      rules: [{type: "deletion"}, {type: "non_fast_forward"},
              {type: "update", parameters: {update_allows_fetch_and_merge: false}}]}' > "$BODY"
    if ERR=$(gh api -X POST "repos/$REPO/rulesets" --input "$BODY" 2>&1 >/dev/null); then
      printf '%s\n' "CREATED=flow: tags"
    else
      printf '%s\n' "FAILED=flow: tags: $(printf '%s' "$ERR" | head -n 1)"
    fi
    rm -f "$BODY"
  fi
fi
# SETUP_RULESETS_CREATE_END
```

Report each line in the Phase 7 summary. A `FAILED=` line goes under **Manual Steps Required** with GitHub's message.

## Phase 6: CLAUDE.md Integration

Use the AskUserQuestion tool with contextual options to ask: "Add flow workflow section to CLAUDE.md?"

If yes, append the workflow section from `templates/CLAUDE-flow.md` to the existing CLAUDE.md.

## Phase 7: Summary

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
3. `$HOME/.claude/settings.flow.json` (or `$FLOW_USER_SETTINGS`) — your cross-project default
4. Plugin default — bundled in flow

Any key set at a higher layer overrides lower layers. See [`references/gate-configuration.md`](../references/gate-configuration.md) for the per-key reference.

### LSP Code Intelligence
| Language | Server | Status | Capabilities |
|----------|--------|--------|-------------|
| {language} | {server} | {Installed/Missing/Skipped} | {available features} |

### GitHub Rulesets
{One of: each CREATED= and FAILED= line from Phase 5; "flow's rulesets are already in place"; "skipped by the user"; "no git remote"; or "could not be read or created ({RULESETS value})"}

{If Phase 2 upgraded deprecated settings keys or stripped auto-log lines:}
### Files to Review Before Committing
- `.claude/settings.flow.json` — deprecated keys upgraded
- {each journal STRIP_AUTO_LOG_FILE named} — auto-log lines removed

{If any servers need manual steps, Phase 1 printed TIMEOUT_BIN=missing, or Phase 5 printed RULESETS=unavailable, RULESETS=unreadable or a FAILED= line:}
### Manual Steps Required
- [ ] {TIMEOUT_BIN=missing only} Install GNU coreutils (`brew install coreutils` on macOS) so the verdict judge and the goal judge can run
- [ ] Add `export ENABLE_LSP_TOOL=1` to shell profile and restart Claude Code
- [ ] Run `{install command}` to install {server}
- [ ] Restart Claude Code after plugin installation
- [ ] {Phase 5 unavailable, unreadable or FAILED only} Ask an owner of the repository to add the rulesets under Settings → Rules{: GitHub's message for each FAILED= line}

### Commands Available
| Command | Purpose |
|---------|---------|
| `/flow <verb> <target>` | Entry point that routes a verb to the command below |
| `/flow:start <issue>` | Start work on an issue |
| `/flow:commit` | Classify and commit changes |
| `/flow:pr` | Create pull request |
| `/flow:review <pr>` | Review a pull request |
| `/flow:address <pr>` | Address review feedback |
| `/flow:merge <pr>` | Merge approved PR |
| `/flow:release <type>` | Create release |
| `/flow:resolve [pr-or-branch]` | Resolve merge conflicts |
| `/flow:status` | Workflow overview |
| `/flow:learn` | Analyze patterns |
| `/flow:setup` | Initialize flow for a repository |
| `/flow:explain` | Questions about decisions on this branch |
| `/flow:issue [topic]` | Create a GitHub issue |
| `/flow:brainstorm [topic]` | Explore approaches before implementation |
| `/flow:debug [error]` | Structured debugging |
| `/flow:design [feature]` | Architecture and design review |
| `/flow:goal` | Create, inspect and evaluate FlowGoals |
| `/flow:resume` | Propose the next safe action for an interrupted run |
| `/flow:workflow` | Inspect workflow definitions |
| `/flow:trigger` | Manage FlowTriggers |
| `/flow:run trigger <id>` | Run one FlowTrigger's target once |
| `/flow:watch` | Generate a `/loop` prompt for hands-off iteration |

### Next Steps
- Assign an issue and run `/flow:start <number>`
- Or run `/flow:status` to see current state
```

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Detect environment, tech stack, build commands | 1 | Autonomous, read-only |
| Probe LSP capabilities | 1 | Autonomous, read-only |
| `mkdir -p .claude` | 1 | Autonomous |
| Add flow's entries to `.gitignore` | 1 | Autonomous, project file; adds only missing lines |
| Write `.claude/settings.flow.json` (project-shared settings) | 1 | Autonomous, project file |
| Upgrade deprecated keys in an existing `.claude/settings.flow.json` (`flow-migrate-settings.sh --apply`) | 1 | Local file rewrite, run only after AskUserQuestion (optional cleanup); atomic, preserves other keys |
| Strip auto-log lines from tracked journals (`flow-strip-auto-log.sh --apply`) | 1 | Local file rewrite, run only after AskUserQuestion (optional cleanup); atomic |
| Append the flow section to CLAUDE.md (`.claude/CLAUDE.md` or `CLAUDE.md`) | 1 | Local file, run only after AskUserQuestion |
| Install LSP server binaries; `claude plugin marketplace add` and `claude plugin install` | 2 | Changes the user's environment outside the repository; run only after the user picks an install option in Step 3.4. No tier setting applies and no breadcrumb is written |
| Read the repository's GitHub rulesets | 1 | Autonomous, read-only |
| Create flow's GitHub rulesets (default branch, tags) | 3 | **Confirm**: this command asks with AskUserQuestion first, naming what each choice does and does not stop; nothing is created on Skip. The `tier-gate.sh` hook does not cover ruleset changes, so this question is the only one |
