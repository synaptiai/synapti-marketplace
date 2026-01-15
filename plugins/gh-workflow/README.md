# gh-workflow

Generic GitHub workflow commands for Claude Code. Provides a complete development workflow from issue creation through release.

---

## Why gh-workflow?

### The Problem with Hardcoded Workflows

Most GitHub automation tools embed assumptions about your repository:
- Branch names like `main` or `master` are hardcoded
- Labels are assumed to exist
- PR templates are project-specific
- Commands break when you customize your workflow

This creates fragile automation that works in demos but fails in real projects with real conventions.

### What gh-workflow Does Differently

Every command **discovers your repository's actual configuration at runtime**:
- Default branch? Detected via `gh repo view`
- Available labels? Fetched via `gh label list`
- Repository name? Queried, not assumed

This means the same commands work across all your repositories without modification.

### The Solution-Agnostic Philosophy

Traditional issue tracking often fails because issues describe **how** to implement something rather than **what** needs to be achieved:

| Brittle Issue | Solution-Agnostic Issue |
|---------------|------------------------|
| "Add DateFilter component to src/components/views/" | "Users can filter results by date" |
| "Refactor UserService to use dependency injection" | "Authentication should be testable in isolation" |
| "Update the onClick handler in Button.tsx" | "Click actions should provide feedback" |

**Why this matters:** When you refactor your codebase, solution-agnostic issues remain valid. Issues that specify file paths become obsolete the moment code moves.

gh-workflow's `/gh-issue` command guides you toward solution-agnostic issue creation, ensuring your backlog survives refactoring.

---

## Design Philosophy

### Interactive at Decision Points

Every command uses the **AskUserQuestion tool** at moments where your input matters:
- Which branch type? (feature vs fix vs docs)
- Which labels to apply?
- Ready to create this PR?

This isn't just confirmation prompts — it's structured decision-making that prevents mistakes while keeping you in control.

### Complete Lifecycle Coverage

Rather than a collection of unrelated commands, gh-workflow provides an integrated workflow:

```
Issue → Branch → Implementation → PR → Review → Merge → Release
```

Each step knows about the others. `/gh-start` reads the issue you're implementing. `/gh-review` knows what the PR is supposed to accomplish. This context-awareness improves quality at every stage.

### Safety Without Friction

Irreversible actions (force push, branch deletion, release creation) require explicit approval. But routine operations flow smoothly with sensible defaults.

---

## Features

- **Zero Configuration**: Commands auto-detect repository settings (default branch, labels, etc.)
- **Interactive**: Uses the AskUserQuestion tool for guided workflows
- **Portable**: Works with any GitHub repository without hardcoding
- **Customizable**: `/gh-setup` generates project-specific configurations
- **Quality Checks**: Detects tech stack and runs appropriate lint/test commands
- **Safety Hooks**: Prevents irreversible actions without explicit user approval

## Commands

| Command | Description |
|---------|-------------|
| `/gh-workflow:gh-issue` | Create a new GitHub issue with solution-agnostic principles |
| `/gh-workflow:gh-start <N>` | Start work on issue #N (branch, implement, PR) |
| `/gh-workflow:gh-review <N>` | Review PR #N with checklist and feedback |
| `/gh-workflow:gh-address <N>` | Address review comments on PR #N |
| `/gh-workflow:gh-merge <N>` | Merge approved PR #N |
| `/gh-workflow:gh-release [type]` | Create a release (patch/minor/major) |
| `/gh-workflow:gh-setup` | Analyze repo and generate workflow configuration |

### Command Benefits

#### `/gh-issue` — Create Issues

**What's Good About /gh-issue:**
1. **Duplicate detection** — Searches existing issues before creating, preventing redundant work
2. **Solution-agnostic enforcement** — Guides you away from implementation details that become stale
3. **Structured templates** — Consistent format (Context, Objective, Acceptance Criteria) across all issues
4. **Label validation** — Fetches actual available labels, prevents typos and missing labels

#### `/gh-start` — Start Work

**What's Good About /gh-start:**
1. **Complete workflow** — One command handles: assign issue, pull latest main, create branch, implement, create PR
2. **Branch naming conventions** — Enforces consistent naming (feature/issue-N, fix/issue-N, docs/issue-N)
3. **PR auto-linking** — Automatically links PR to issue with `fixes #N` for auto-close on merge
4. **Preview before creation** — Shows PR preview and requires explicit approval before creating

#### `/gh-review` — Review PRs

**What's Good About /gh-review:**
1. **Context-aware** — Reads the linked issue to understand what the PR should accomplish
2. **Structured checklist** — Systematic review categories prevent overlooking important aspects
3. **Interactive feedback** — Guides through approval, request changes, or comment-only decisions
4. **Quality gates** — Detects tech stack and suggests appropriate lint/test commands to run

#### `/gh-address` — Address Comments

**What's Good About /gh-address:**
1. **Comment aggregation** — Pulls all review comments into a single actionable list
2. **Systematic resolution** — Track which comments have been addressed
3. **Conversation continuity** — Maintains context of the review discussion

#### `/gh-merge` — Merge PRs

**What's Good About /gh-merge:**
1. **Safety checks** — Verifies PR is approved and checks are passing
2. **Branch cleanup** — Optionally deletes feature branch after merge
3. **Merge strategy selection** — Choose squash, merge commit, or rebase based on preference

#### `/gh-release` — Create Releases

**What's Good About /gh-release:**
1. **Semantic versioning** — Guided selection of patch/minor/major increment
2. **Automatic changelog** — Generates release notes from merged PRs since last release
3. **Tag creation** — Creates git tag and GitHub release in one step
4. **Version consistency** — Updates version numbers in project files if detected

#### `/gh-setup` — Configure Workflow

**What's Good About /gh-setup:**
1. **One-time setup** — Analyzes your repo and generates project-specific configuration
2. **Tech stack detection** — Identifies Python, TypeScript, Go, Ruby and configures appropriate quality commands
3. **Template generation** — Creates customized issue/PR templates based on your conventions
4. **Non-destructive** — Shows preview of changes before writing any files

## Quick Start

### 1. Run Setup (Recommended)

```
/gh-workflow:gh-setup
```

This analyzes your repository and generates a customized workflow configuration in your `.claude/CLAUDE.md`.

### 2. Or Use Directly

Commands work without setup by auto-detecting your repository's settings:

```
/gh-workflow:gh-issue Add user authentication
```

## Workflow Overview

```
┌─────────────────┐
│  /gh-issue      │ Create issue with context, objectives, criteria
└────────┬────────┘
         ▼
┌─────────────────┐
│  /gh-start N    │ Assign issue, create branch, implement, create PR
└────────┬────────┘
         ▼
┌─────────────────┐
│  /gh-review N   │ Review PR, provide feedback
└────────┬────────┘
         ▼
┌─────────────────┐
│  /gh-address N  │ Address review comments (if any)
└────────┬────────┘
         ▼
┌─────────────────┐
│  /gh-merge N    │ Merge approved PR, delete branch
└────────┬────────┘
         ▼
┌─────────────────┐
│  /gh-release    │ Create release with changelog
└─────────────────┘
```

## Key Principles

### Dynamic Configuration

Commands never hardcode values. Instead, they detect:
- **Default branch**: `gh repo view --json defaultBranchRef`
- **Repository name**: `gh repo view --json nameWithOwner`
- **Available labels**: `gh label list`

### Solution-Agnostic Issues

Issues describe WHAT, not HOW:
- ✅ "User can filter results by date"
- ❌ "Add DateFilter component to src/components/"

This ensures issues remain valid even when implementation details change.

### Interactive Workflows

Every command uses the **AskUserQuestion tool** at decision points:
- Label selection
- Branch type choice
- PR approval
- Review decisions

## Customization

### Project-Specific Overrides

After running `/gh-setup`, you can customize:

1. **CLAUDE.md**: Edit the workflow section for project-specific conventions
2. **Local commands**: Copy commands to `.claude/commands/` for customization
3. **Labels**: Create additional labels specific to your project

### Templates

The `templates/` directory contains:
- `CLAUDE-workflow.md` - Workflow section template
- `issue-template.md` - Issue body structure
- `pr-template.md` - PR body structure

## Requirements

- GitHub CLI (`gh`) installed and authenticated
- Git repository with GitHub remote
- Claude Code with plugin support

## Skills

### repo-config

Provides dynamic repository configuration detection. Used internally by all commands to:
- Detect default branch
- Get repository info for API calls
- Fetch available labels

## Hooks

The plugin includes safety hooks that:
- **Pre-push verification**: Ensures user approval before irreversible git operations
- **Post-commit reminders**: Reminds about running quality checks after commits

## Tech Stack Detection

The `/gh-setup` command detects your project's tech stack and generates appropriate quality checklists:

| Stack | Detection | Quality Commands |
|-------|-----------|-----------------|
| Python | `pyproject.toml`, `ruff.toml` | `ruff check`, `pytest` |
| TypeScript | `package.json`, `tsconfig.json` | `npm run lint`, `npm test` |
| Go | `go.mod` | `go vet`, `go test` |
| Ruby | `Gemfile`, `.rubocop.yml` | `rubocop`, `rspec` |

## Examples

### Create an Issue

```
/gh-workflow:gh-issue Add dark mode support to the dashboard
```

### Start Work on an Issue

```
/gh-workflow:gh-start 42
```

### Review a PR

```
/gh-workflow:gh-review 15
```

### Create a Release

```
/gh-workflow:gh-release minor
```

---

## Real-World Scenarios

### Scenario 1: Feature Development Cycle

**Situation:** You have a feature request from a stakeholder.

```bash
# 1. Create a well-structured issue
/gh-workflow:gh-issue Users need to export their data as CSV

# 2. Start work (assigns issue, creates branch, begins implementation)
/gh-workflow:gh-start 42

# 3. After implementation, PR is created automatically
# ... implementation happens ...
# PR created: feature/issue-42-csv-export → main

# 4. Request review
# (reviewer uses /gh-review 15)

# 5. Address any feedback
/gh-workflow:gh-address 15

# 6. Merge when approved
/gh-workflow:gh-merge 15
```

**Result:** Complete audit trail from stakeholder request to merged code, with consistent structure at every step.

### Scenario 2: Bug Fix with Urgency

**Situation:** Production bug reported, needs quick turnaround.

```bash
# 1. Create issue (duplicate check ensures we're not re-solving old bugs)
/gh-workflow:gh-issue Users see error when clicking submit button

# 2. Branch type selection guides toward fix/ prefix
/gh-workflow:gh-start 43
# → Creates: fix/issue-43-submit-error

# 3. Fast implementation, PR created
# → PR title includes "fixes #43" for auto-close

# 4. Emergency merge (after quick review)
/gh-workflow:gh-merge 16
```

**Result:** Bug fix with proper tracking, even under time pressure.

### Scenario 3: Release Preparation

**Situation:** Sprint complete, time to release.

```bash
/gh-workflow:gh-release minor
```

**What happens:**
1. Detects last release tag
2. Collects all merged PRs since then
3. Generates changelog from PR titles/descriptions
4. Prompts for version confirmation (1.2.0 → 1.3.0)
5. Creates git tag and GitHub release

**Result:** Professional release notes without manual changelog maintenance.

---

## Team Workflow Benefits

### For Individual Developers

- **Less context switching** — One command handles the full workflow instead of multiple manual git/gh operations
- **Consistent quality** — Templates and checklists ensure nothing is forgotten
- **Fewer mistakes** — Interactive prompts catch issues before they become problems

### For Teams

- **Uniform issue quality** — Every issue follows the same structure
- **Predictable branches** — Naming conventions make branch purpose clear
- **Traceable history** — PRs link to issues, releases link to PRs
- **Onboarding efficiency** — New team members follow the same guided workflow

### For Projects

- **Refactoring-safe backlog** — Solution-agnostic issues remain valid when code moves
- **Audit compliance** — Complete trail from requirement to release
- **Reduced friction** — Less time on process, more time on implementation

## License

MIT
