# gh-workflow

Generic GitHub workflow commands for Claude Code. Provides a complete development workflow from issue creation through release.

## Features

- **Zero Configuration**: Commands auto-detect repository settings (default branch, labels, etc.)
- **Interactive**: Uses the AskUserQuestion tool for guided workflows
- **Portable**: Works with any GitHub repository without hardcoding
- **Customizable**: `/gh-setup` generates project-specific configurations

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

## License

MIT
