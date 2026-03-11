---
description: Use to set up or update gh-workflow in a repository - analyzes tech stack, detects conventions, generates workflow configuration, and upgrades existing installations to latest version
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion
---

# Setup / Update GitHub Workflow

Analyze the current repository and generate customized GitHub workflow configuration. If gh-workflow is already configured, detect the existing version and offer to update it with new commands and features while preserving customizations.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** extensively to gather preferences, confirm detected conventions, and approve generated configurations.

## Contract

**GOAL**: Project-specific workflow configuration generated, applied, or updated based on detected tech stack and conventions. Testable: `.claude/CLAUDE.md` contains workflow section with correct branch/commit conventions, all current gh-workflow commands listed, and version marker reflecting current plugin version (`$PLUGIN_VERSION` from `plugin.json`).

**CONSTRAINTS**:
- Never overwrite existing CLAUDE.md - merge or append the workflow section
- Always create backup before modifying existing files
- Always confirm detected patterns with user before applying

**FORMAT**: Generated CLAUDE.md workflow section with branching strategy, commit conventions, commands table, and tech-stack-specific quality checklist.

**FAILURE CONDITIONS** (output is unacceptable if any apply):
- Existing CLAUDE.md overwritten without backup
- Wrong tech stack detected (e.g., Python project identified as Go)
- Configuration applied without user preview and approval
- Generated conventions conflict with existing project conventions
- Existing customizations lost during update (branch naming, labels, checklists)

## Purpose

This command analyzes your codebase and generates:
1. A `.claude/CLAUDE.md` section with GitHub workflow documentation
2. Optionally, local command overrides for project-specific customizations
3. Recommendations for labels to create

## Phase 0: Installation Detection

Before performing any analysis, read the plugin version and detect whether gh-workflow is already configured.

0. **Read plugin version** (single source of truth):
   ```bash
   # Try known plugin locations (marketplace source, then cache, then local dev)
   PLUGIN_VERSION=""
   # Marketplace source (unversioned, always matches installed version)
   for MARKET in "$HOME/.claude/plugins/marketplaces"/*/plugins/gh-workflow/.claude-plugin/plugin.json; do
     [ -f "$MARKET" ] && { PLUGIN_VERSION=$(jq -r '.version' "$MARKET"); break; }
   done
   # Cache (versioned dirs — take the latest)
   if [ -z "$PLUGIN_VERSION" ]; then
     LATEST=$(ls -d "$HOME/.claude/plugins/cache"/*/gh-workflow/*/.claude-plugin/plugin.json 2>/dev/null | sort -V | tail -1)
     [ -n "$LATEST" ] && PLUGIN_VERSION=$(jq -r '.version' "$LATEST")
   fi
   # Local development (running from marketplace repo)
   [ -z "$PLUGIN_VERSION" ] && [ -f "plugins/gh-workflow/.claude-plugin/plugin.json" ] && \
     PLUGIN_VERSION=$(jq -r '.version' "plugins/gh-workflow/.claude-plugin/plugin.json")
   [ -z "$PLUGIN_VERSION" ] && PLUGIN_VERSION="unknown"
   echo "gh-workflow version: $PLUGIN_VERSION"
   ```

   Use `$PLUGIN_VERSION` for all version references in the steps below.

1. **Check for existing gh-workflow configuration**:
   ```bash
   # Look for gh-workflow version marker
   grep '<!-- gh-workflow:' .claude/CLAUDE.md 2>/dev/null || echo "No version marker found"

   # Look for gh-workflow command table
   grep 'gh-workflow:gh-' .claude/CLAUDE.md 2>/dev/null || echo "No gh-workflow commands found"

   # Look for workflow section header
   grep '## GitHub Workflow Commands' .claude/CLAUDE.md 2>/dev/null || echo "No workflow section found"
   ```

2. **Determine mode**:
   - **Fresh install**: No CLAUDE.md exists, or it exists but contains no gh-workflow section → proceed to Phase 1
   - **Update needed**: gh-workflow section exists → enter Phase 1U (Update Flow)
   - **Already current**: Version marker shows current version (`$PLUGIN_VERSION`) → inform user, ask if they want to re-run anyway

3. **If update detected, extract existing version**:
   ```bash
   # Extract version from marker comment (portable)
   sed -n 's/<!-- gh-workflow: \(.*\) -->/\1/p' .claude/CLAUDE.md 2>/dev/null || echo "pre-1.4.0"
   ```

4. **Use the AskUserQuestion tool** if existing installation detected:
   - **Option 1**: "Update existing configuration to v$PLUGIN_VERSION" (Recommended)
   - **Option 2**: "Re-run full setup (preserves existing, generates fresh)"
   - **Option 3**: "Cancel - keep existing configuration"

## Phase 1U: Update Flow (Existing Installation)

When an existing gh-workflow section is detected, perform a targeted update instead of full setup.

1. **Parse existing configuration**:
   ```bash
   # Read the full CLAUDE.md to understand current state
   cat .claude/CLAUDE.md
   ```

   Identify and note:
   - Existing command table entries
   - Custom branch naming (may differ from defaults)
   - Custom labels (user may have added project-specific ones)
   - Custom checklist items (user may have added project-specific items)
   - Any sections that appear to be user-customized vs. template-generated

2. **Compute diff between existing and current**:

   Compare existing commands against the full v$PLUGIN_VERSION command list:
   | Command | Check |
   |---------|-------|
   | `/gh-workflow:gh-status` | Present? |
   | `/gh-workflow:gh-issue` | Present? |
   | `/gh-workflow:gh-start <issue>` | Present? |
   | `/gh-workflow:gh-start-auto <issue>` | NEW - likely missing |
   | `/gh-workflow:gh-commit` | NEW - likely missing |
   | `/gh-workflow:gh-pr` | NEW - likely missing |
   | `/gh-workflow:gh-review <pr>` | Present? |
   | `/gh-workflow:gh-address <pr>` | Present? |
   | `/gh-workflow:gh-merge <pr>` | Present? |
   | `/gh-workflow:gh-release <type>` | Present? |
   | `/gh-workflow:gh-explain <issue>` | NEW - likely missing |
   | `/gh-workflow:gh-security-review` | NEW - likely missing |
   | `/gh-workflow:gh-setup` | NEW - likely missing |

   Also check for missing sections:
   - Plugin Capabilities (Agents, Skills, Safety Hooks)
   - Version marker

3. **Show update summary to user**:
   Display what will change:
   - New commands being added
   - New sections being added (Plugin Capabilities)
   - Version marker being added/updated
   - Sections that will NOT be modified (preserved customizations)

4. **Use the AskUserQuestion tool** for approval:
   - **Option 1**: "Apply all updates" (Recommended)
   - **Option 2**: "Select which updates to apply"
   - **Option 3**: "Preview the full updated section first"
   - **Option 4**: "Cancel update"

5. **Create backup before modifying**:
   ```bash
   cp .claude/CLAUDE.md ".claude/CLAUDE.md.backup.$(date +%Y%m%d%H%M%S)"
   ```

6. **Apply updates**:
   - Replace the command table with the full 13-command table
   - Add Plugin Capabilities section (Agents, Skills, Safety Hooks) if not present
   - Add or update the version marker comment (`<!-- gh-workflow: $PLUGIN_VERSION -->`)
   - Preserve all user-customized sections (branch naming, labels, checklists)

7. **Proceed to Phase 5 (Verification)** — skip Phases 1-4 since conventions are already configured.

## Phase 1: Repository Analysis (Fresh Install)

> **Note**: This phase runs for fresh installations. For updates to existing installations, see Phase 1U above.

1. **Verify GitHub repository**:
   ```bash
   # Check if git repo
   git rev-parse --git-dir 2>/dev/null || echo "Not a git repository"

   # Check if has GitHub remote
   gh repo view --json nameWithOwner 2>/dev/null || echo "No GitHub repository found"
   ```

2. **Gather repository info**:
   ```bash
   # Repository details
   gh repo view --json nameWithOwner,defaultBranchRef,description,url

   # Available labels
   gh label list
   ```

3. **Analyze existing conventions**:
   ```bash
   # Check for existing .claude folder
   ls -la .claude/ 2>/dev/null

   # Analyze branch naming patterns
   git branch -r --list 'origin/*' | head -20

   # Analyze commit message patterns
   git log --oneline -30
   ```

## Phase 2: Detect Tech Stack & Conventions

### Tech Stack Detection

Analyze the codebase to detect languages and frameworks:

```bash
# Detect Python
ls -la pyproject.toml setup.py requirements.txt 2>/dev/null
ls -la ruff.toml .ruff.toml 2>/dev/null  # Linting
ls -la pytest.ini pyproject.toml 2>/dev/null  # Testing

# Detect TypeScript/JavaScript
ls -la package.json tsconfig.json 2>/dev/null
cat package.json 2>/dev/null | grep -E '"(eslint|prettier|jest|vitest)"'

# Detect Go
ls -la go.mod go.sum 2>/dev/null

# Detect Rust
ls -la Cargo.toml 2>/dev/null

# Detect Ruby
ls -la Gemfile .rubocop.yml 2>/dev/null

# Detect existing CLAUDE.md for patterns
cat .claude/CLAUDE.md 2>/dev/null | head -100
```

Based on detected stack, generate **project-specific review checklists** (see Phase 3).

### Branch Naming
Analyze existing branches to detect patterns:

```bash
# Count branches matching common patterns
git branch -r | grep -c 'feature/' || echo "0"
git branch -r | grep -c 'fix/' || echo "0"
git branch -r | grep -c 'bugfix/' || echo "0"
git branch -r | grep -c 'hotfix/' || echo "0"
```

**Use the AskUserQuestion tool** to confirm detected pattern or choose:
- **Option 1**: "feature/fix/docs pattern" (Recommended if detected)
- **Option 2**: "feat/bugfix/hotfix pattern"
- **Option 3**: "Custom pattern - let me specify"
- **Option 4**: "No specific pattern - freeform branches"

### Commit Convention
Analyze recent commits:

```bash
# Check for conventional commits
git log --oneline -30 | grep -E '^[a-f0-9]+ (feat|fix|docs|refactor|test|chore):' | wc -l
```

**Use the AskUserQuestion tool** to confirm:
- **Option 1**: "Conventional commits (feat:, fix:, docs:, etc.)" (Recommended)
- **Option 2**: "No specific convention"
- **Option 3**: "Custom convention - let me specify"

### Labels
Check existing labels:

```bash
gh label list --json name,description
```

**Use the AskUserQuestion tool** to offer label recommendations:
- **Option 1**: "Use existing labels as-is"
- **Option 2**: "Add recommended labels (bug, enhancement, documentation)"
- **Option 3**: "Let me customize labels"

## Phase 3: Generate Configuration

### CLAUDE.md Section

Generate a workflow section for the project's CLAUDE.md:

```markdown
<!-- gh-workflow: {PLUGIN_VERSION} -->

## Git Workflow

### Branching Strategy

```
{default-branch} (production/releases)
  ↑
  └── Feature PR (feature/* → {default-branch})

{branch-patterns}
```

### Commit Conventions

{commit-convention-description}

### Branch Naming

- `feature/issue-{number}-{short-description}` - New features
- `fix/issue-{number}-{short-description}` - Bug fixes
- `docs/issue-{number}-{short-description}` - Documentation

## GitHub Workflow Commands

This project uses the gh-workflow plugin. Available commands:

| Command | Purpose |
|---------|---------|
| `/gh-workflow:gh-status` | View workflow status (issues, PRs, reviews) |
| `/gh-workflow:gh-issue` | Create a new GitHub issue |
| `/gh-workflow:gh-start <issue>` | Start work on an issue (branch, implement, track) |
| `/gh-workflow:gh-start-auto <issue>` | Autonomous issue-to-PR pipeline with iterative review-fix loops |
| `/gh-workflow:gh-commit` | Context-aware commits with change classification |
| `/gh-workflow:gh-pr` | Create PR with full review and reviewer suggestions |
| `/gh-workflow:gh-review <pr>` | Review a pull request with prioritized findings |
| `/gh-workflow:gh-address <pr>` | Address PR review comments |
| `/gh-workflow:gh-merge <pr>` | Merge an approved pull request |
| `/gh-workflow:gh-release <type>` | Create a release (patch/minor/major) |
| `/gh-workflow:gh-explain <issue>` | Explore issue context with interactive Q&A |
| `/gh-workflow:gh-security-review` | Security review of branch changes |
| `/gh-workflow:gh-setup` | Set up or update workflow configuration |

## Plugin Capabilities

### Agents
The gh-workflow plugin includes specialized agents that are invoked automatically by commands:
- **code-reviewer** - Code quality analysis with P1/P2/P3 prioritized findings
- **convention-checker** - Validates commit messages, branch naming, PR format
- **test-runner** - Discovers and runs project-specific lint/test/typecheck commands
- **implementation-planner** - Creates task breakdowns from issue acceptance criteria

### Skills
Commands use these skills for dynamic adaptation:
- **repo-config** - Auto-detects default branch, labels, and repository settings
- **capability-discovery** - Discovers available agents, skills, and quality commands
- **runtime-verification** - Verifies implementation works at runtime (dev server, API, E2E)
- **suggest-users** - Suggests reviewers/assignees based on CODEOWNERS and activity

### Safety Hooks
The plugin includes safety hooks that activate automatically:
- Pre-push verification before irreversible git operations
- Pre-release verification before creating GitHub releases
- Destructive operation guards (force push, hard reset, branch deletion)
- Repository target verification before creating issues or PRs
- Post-edit test file reminders
- Workflow completion checks

### Advanced Features
- **Task-based tracking**: Implementation and review progress tracked via tasks
- **Verification loops**: Self-review gates before PR creation (max 3 iterations)
- **Parallel execution**: Commands maximize efficiency with parallel API calls
- **Runtime verification**: Verifies implementation works when running (not just compiles)

## Labels

Available labels for this repository:
{label-list}

## Code Quality Checklist

Use this checklist when reviewing PRs or before creating PRs.

### General
- [ ] Logic is correct and handles edge cases
- [ ] No obvious bugs or security vulnerabilities
- [ ] Code style consistent with project conventions
- [ ] No hardcoded secrets or credentials

{tech-stack-specific-checklist}

### Testing
- [ ] Tests pass
- [ ] New functionality has tests
- [ ] Edge cases considered

### Documentation
- [ ] PR description is complete and accurate
- [ ] Code comments where logic isn't self-evident
```

### Tech Stack Specific Checklists

Generate the `{tech-stack-specific-checklist}` based on detected stack:

**If Python detected:**
```markdown
### Python
- [ ] Follows PEP 8 style (use `ruff check`)
- [ ] Type hints properly defined
- [ ] Async/await used correctly (if applicable)
- [ ] No N+1 query issues (if using ORM)
- [ ] `ruff check src/` passes
- [ ] `pytest` passes
```

**If TypeScript/JavaScript detected:**
```markdown
### TypeScript
- [ ] Types properly defined (no `any` unless justified)
- [ ] ESLint/Prettier passes
- [ ] React hooks follow rules (if React)
- [ ] No memory leaks in useEffect cleanup
- [ ] `npm run lint` passes
- [ ] `npm test` passes
```

**If Go detected:**
```markdown
### Go
- [ ] Error handling follows conventions
- [ ] No data races (use `go vet -race`)
- [ ] Context properly propagated
- [ ] `go vet ./...` passes
- [ ] `go test ./...` passes
```

**If Ruby detected:**
```markdown
### Ruby
- [ ] Follows Ruby style guide
- [ ] RuboCop passes
- [ ] Rails conventions followed (if Rails)
- [ ] `bundle exec rubocop` passes
- [ ] `bundle exec rspec` passes
```

### Local Command Overrides (Optional)

**Use the AskUserQuestion tool** to ask if user wants local overrides:
- **Option 1**: "Use plugin commands directly" (Recommended for most projects)
- **Option 2**: "Create local command copies for customization"
- **Option 3**: "Create local commands with project-specific additions"

If user chooses option 2 or 3, create `.claude/commands/` with customized versions.

## Phase 3b: Generate Comprehension Layer Config

Generate `.claude/settings.gh-workflow.json` with schema defaults:

```bash
# Check if config file already exists
[ -f ".claude/settings.gh-workflow.json" ] && echo "Config file exists" || echo "No config file"
```

If no config file exists, generate one with all defaults:

```json
{
  "$schema": "https://raw.githubusercontent.com/synaptiai/synapti-marketplace/main/plugins/gh-workflow/schema.json",
  "gates": {
    "newDependencies": "on",
    "securityChanges": "on",
    "schemaChanges": "on",
    "apiSurfaceChanges": "on",
    "scopeDeviations": "on",
    "ambiguousRequirements": "on",
    "customTriggers": [],
    "customTriggersMode": "on"
  },
  "journal": {
    "dir": ".decisions",
    "sensitivityDefault": "public"
  },
  "report": {
    "thresholdFull": 100
  },
  "explain": {
    "sessionSave": "ask",
    "includeDiff": true
  },
  "commands": {
    "ghStartFamiliarityPrompt": true,
    "ghCommitFirstTouch": true,
    "ghPrComprehensionReport": true,
    "ghPrDecisionSummary": true,
    "ghReviewComprehensionCheck": true,
    "ghMergeKnowledgeCheckpoint": true
  },
  "merge": {
    "strategy": "squash",
    "deleteBranch": true
  },
  "conventions": {
    "commitTypes": ["feat", "fix", "docs", "style", "refactor", "test", "chore", "perf", "ci", "build", "revert"],
    "branchPatterns": {
      "feature": "feature/issue-{N}-{desc}",
      "fix": "fix/issue-{N}-{desc}",
      "docs": "docs/issue-{N}-{desc}"
    },
    "additionalBranchTypes": {}
  },
  "release": {
    "tagPrefix": "v"
  },
  "timeouts": {
    "devServerStartup": 30,
    "e2eTest": 120,
    "verificationScript": 180,
    "qualityCheckMaxIterations": 3
  },
  "review": {
    "firstTouchLineThreshold": 50,
    "activityLookbackDays": 30,
    "activityFallbackDays": 90
  },
  "automation": {
    "maxReviewIterations": 5
  }
}
```

**Use the AskUserQuestion tool** for gate preferences:
- **Option 1**: "All gates on (interactive development)" (Recommended)
- **Option 2**: "CI mode — only security gates pause, others log"
- **Option 3**: "Minimal — only security and schema gates"
- **Option 4**: "Custom — let me choose per gate"

Adjust gate values in the generated config based on user choice.

**Use the AskUserQuestion tool** for merge strategy:
- **Option 1**: "Squash merge (single commit per PR)" (Recommended)
- **Option 2**: "Merge commit (preserve full history)"
- **Option 3**: "Rebase (linear history)"

Adjust `merge.strategy` based on user choice.

**Use the AskUserQuestion tool** for branch naming:
- **Option 1**: "Use default patterns (feature/issue-{N}-{desc})" (Recommended)
- **Option 2**: "Customize branch patterns" — ask for feature, fix, and docs patterns
- **Option 3**: "Add extra branch types" — ask for additional types (refactor, chore, etc.)

Adjust `conventions.branchPatterns` and `conventions.additionalBranchTypes` based on user choice.

Ensure `.claude/settings.gh-workflow.local.json` is in `.gitignore`:

```bash
# Add local config to .gitignore if not already present
grep -qF 'settings.gh-workflow.local.json' .gitignore 2>/dev/null || echo '.claude/settings.gh-workflow.local.json' >> .gitignore
```

If config file already exists, show the user the current values and ask if they want to reset to defaults or keep as-is.

## Phase 4: Apply Configuration

1. **Preview generated content**:
   Show the CLAUDE.md section and the settings.gh-workflow.json that will be created/updated

2. **Use the AskUserQuestion tool** for approval:
   - **Option 1**: "Apply this configuration" (Recommended)
   - **Option 2**: "Edit configuration first"
   - **Option 3**: "Cancel setup"

3. **Apply changes**:
   - Create `.claude/` directory if needed
   - Add/update CLAUDE.md with workflow section
   - Write `.claude/settings.gh-workflow.json` with comprehension layer config
   - Create local command files if requested
   - Optionally create recommended labels

4. **Create labels** (if approved):
   ```bash
   gh label create "bug" --description "Something isn't working" --color "d73a4a" 2>/dev/null || echo "Label exists"
   gh label create "enhancement" --description "New feature or request" --color "a2eeef" 2>/dev/null || echo "Label exists"
   gh label create "documentation" --description "Documentation improvements" --color "0075ca" 2>/dev/null || echo "Label exists"
   ```

## Phase 5: Verification

1. **Verify .claude structure**:
   ```bash
   ls -la .claude/
   cat .claude/CLAUDE.md | head -50
   cat .claude/settings.gh-workflow.json 2>/dev/null
   ```

2. **Validate config against schema** (if jq available):
   ```bash
   jq . .claude/settings.gh-workflow.json >/dev/null 2>&1 && echo "Valid JSON" || echo "Invalid JSON"
   ```

3. **Test a command**:
   Suggest user run `/gh-workflow:gh-issue` to verify setup

4. **Report completion**:
   - List what was created/updated
   - Provide next steps

## Output Format

### Success
```
## GitHub Workflow Setup Complete

**Repository:** {owner}/{repo}
**Default Branch:** {branch}

### Configuration Applied

**CLAUDE.md:** Updated with workflow section
**Settings:** `.claude/settings.gh-workflow.json` generated with comprehension layer config
**Labels:** [Created N new labels / Using existing labels]
**Local Commands:** [None / Created in .claude/commands/]

### Detected Conventions
- Branch naming: {pattern}
- Commit convention: {convention}
- Default branch: {branch}

### Next Steps
1. Review the CLAUDE.md workflow section
2. Review `.claude/settings.gh-workflow.json` for gate and comprehension settings
3. Try `/gh-workflow:gh-status` to view your current workflow state
4. Try `/gh-workflow:gh-issue` to create your first issue
5. Use `/gh-workflow:gh-commit` for context-aware commits
6. Use `/gh-workflow:gh-pr` to create PRs with full review
7. Customize settings as needed for your project
8. Run `/gh-workflow:gh-setup` again after plugin updates to get new features

### Available Commands
- `/gh-workflow:gh-status` - View workflow status
- `/gh-workflow:gh-issue` - Create issues
- `/gh-workflow:gh-start <N>` - Start work on issue N
- `/gh-workflow:gh-start-auto <N>` - Autonomous issue-to-PR pipeline
- `/gh-workflow:gh-commit` - Context-aware commits
- `/gh-workflow:gh-pr` - Create PR with review
- `/gh-workflow:gh-review <N>` - Review PR N
- `/gh-workflow:gh-address <N>` - Address PR N comments
- `/gh-workflow:gh-merge <N>` - Merge PR N
- `/gh-workflow:gh-release [patch|minor|major]` - Create release
- `/gh-workflow:gh-explain <N>` - Explore issue context with Q&A
- `/gh-workflow:gh-security-review` - Security review
- `/gh-workflow:gh-setup` - Re-run setup or update
```

### Update Success
```
## GitHub Workflow Updated

**Repository:** {owner}/{repo}
**Previous Version:** {old_version}
**Updated Version:** {PLUGIN_VERSION}

### Changes Applied
- **New commands added:** {list of new commands}
- **New sections added:** {Plugin Capabilities / Safety Hooks / etc.}
- **Version marker:** Added/updated

### Preserved
- Branch naming conventions
- Commit conventions
- Labels
- Code quality checklists
- Custom project-specific additions

### Available Commands
- `/gh-workflow:gh-status` - View workflow status
- `/gh-workflow:gh-issue` - Create issues
- `/gh-workflow:gh-start <N>` - Start work on issue N
- `/gh-workflow:gh-start-auto <N>` - Autonomous issue-to-PR pipeline
- `/gh-workflow:gh-commit` - Context-aware commits
- `/gh-workflow:gh-pr` - Create PR with review
- `/gh-workflow:gh-review <N>` - Review PR N
- `/gh-workflow:gh-address <N>` - Address PR N comments
- `/gh-workflow:gh-merge <N>` - Merge PR N
- `/gh-workflow:gh-release [patch|minor|major]` - Create release
- `/gh-workflow:gh-explain <N>` - Explore issue context with Q&A
- `/gh-workflow:gh-security-review` - Security review
- `/gh-workflow:gh-setup` - Re-run setup or update
```

### Not a Git Repository
```
## Setup Failed

**Reason:** This directory is not a Git repository or doesn't have a GitHub remote.

### How to Fix
1. Initialize a git repository: `git init`
2. Add a GitHub remote: `git remote add origin https://github.com/owner/repo.git`
3. Run `/gh-workflow:gh-setup` again
```

## Rules

- Always analyze before assuming conventions
- Always confirm detected patterns with user
- Never overwrite existing CLAUDE.md - merge or append
- Create backups before modifying existing files
- Always include version marker (`<!-- gh-workflow: $PLUGIN_VERSION -->`) in generated output
- When updating, preserve user customizations (branch naming, labels, checklists)
- When updating, show what's new before applying changes
- **Use the AskUserQuestion tool** at every decision point:
  - Fresh install vs. update mode selection
  - Branch naming convention
  - Commit convention
  - Label configuration
  - Local command creation
  - Final approval

## Success Criteria

Before completing, verify:
- [ ] Repository analyzed successfully (or existing config detected)
- [ ] Conventions detected and confirmed with user (fresh) OR preserved (update)
- [ ] Configuration generated and approved
- [ ] CLAUDE.md updated with workflow section
- [ ] `.claude/settings.gh-workflow.json` generated with valid JSON
- [ ] All 13 commands listed in command table
- [ ] Version marker present (`<!-- gh-workflow: $PLUGIN_VERSION -->`)
- [ ] Plugin Capabilities section present (Agents, Skills, Safety Hooks)
- [ ] Labels created (if requested)
- [ ] Local commands created (if requested)
- [ ] `.gitignore` includes `settings.gh-workflow.local.json`
- [ ] User informed of next steps
- [ ] If update: backup created before modifications
- [ ] If update: customizations preserved
