---
description: Analyze repository and generate workflow configuration
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion
---

# Setup GitHub Workflow

Analyze the current repository and generate customized GitHub workflow configuration.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** extensively to gather preferences, confirm detected conventions, and approve generated configurations.

## Purpose

This command analyzes your codebase and generates:
1. A `.claude/CLAUDE.md` section with GitHub workflow documentation
2. Optionally, local command overrides for project-specific customizations
3. Recommendations for labels to create

## Phase 1: Repository Analysis

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
| `/gh-workflow:gh-start <issue>` | Start work on an issue |
| `/gh-workflow:gh-review <pr>` | Review a pull request |
| `/gh-workflow:gh-address <pr>` | Address PR review comments |
| `/gh-workflow:gh-merge <pr>` | Merge an approved pull request |
| `/gh-workflow:gh-release <type>` | Create a release (patch/minor/major) |

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

## Phase 4: Apply Configuration

1. **Preview generated content**:
   Show the CLAUDE.md section that will be added/updated

2. **Use the AskUserQuestion tool** for approval:
   - **Option 1**: "Apply this configuration" (Recommended)
   - **Option 2**: "Edit configuration first"
   - **Option 3**: "Cancel setup"

3. **Apply changes**:
   - Create `.claude/` directory if needed
   - Add/update CLAUDE.md with workflow section
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
   ```

2. **Test a command**:
   Suggest user run `/gh-workflow:gh-issue` to verify setup

3. **Report completion**:
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
**Labels:** [Created N new labels / Using existing labels]
**Local Commands:** [None / Created in .claude/commands/]

### Detected Conventions
- Branch naming: {pattern}
- Commit convention: {convention}
- Default branch: {branch}

### Next Steps
1. Review the CLAUDE.md workflow section
2. Try `/gh-workflow:gh-status` to view your current workflow state
3. Try `/gh-workflow:gh-issue` to create your first issue
4. Customize `.claude/CLAUDE.md` as needed for your project

### Available Commands
- `/gh-workflow:gh-status` - View workflow status
- `/gh-workflow:gh-issue` - Create issues
- `/gh-workflow:gh-start <N>` - Start work on issue N
- `/gh-workflow:gh-review <N>` - Review PR N
- `/gh-workflow:gh-address <N>` - Address PR N comments
- `/gh-workflow:gh-merge <N>` - Merge PR N
- `/gh-workflow:gh-release [patch|minor|major]` - Create release
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
- **Use the AskUserQuestion tool** at every decision point:
  - Branch naming convention
  - Commit convention
  - Label configuration
  - Local command creation
  - Final approval

## Success Criteria

Before completing, verify:
- [ ] Repository analyzed successfully
- [ ] Conventions detected and confirmed with user
- [ ] Configuration generated and approved
- [ ] CLAUDE.md updated with workflow section
- [ ] Labels created (if requested)
- [ ] Local commands created (if requested)
- [ ] User informed of next steps
