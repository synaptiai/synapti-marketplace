---
description: Create a release with automatic changelog generation
argument-hint: [patch|minor|major]
allowed-tools: Bash, AskUserQuestion
---

# Create Release v$ARGUMENTS

Create a new release with changelog generation.

**Tool Usage**: This workflow uses the **AskUserQuestion tool** extensively to determine release type, confirm version bumps, and get explicit approval before creating irreversible releases.

## Arguments

- `$ARGUMENTS`: Version bump type - `patch`, `minor`, or `major`
  - `patch` (1.2.0 → 1.2.1): Bug fixes only
  - `minor` (1.2.0 → 1.3.0): New features
  - `major` (1.2.0 → 2.0.0): Breaking changes

If no argument provided, analyze commits to suggest the appropriate bump type.

## Phase 1: Preparation

1. **Get default branch and ensure on latest**:
   ```bash
   DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
   git checkout $DEFAULT_BRANCH && git pull origin $DEFAULT_BRANCH
   ```

2. **Get latest tag and check what's changed**:
   ```bash
   # Get latest tag
   git describe --tags --abbrev=0 2>/dev/null || echo "No previous tags"

   # List commits since last release
   git log $(git describe --tags --abbrev=0 2>/dev/null || echo "HEAD~20")..HEAD --oneline
   ```

3. **If no argument provided, use the AskUserQuestion tool** to determine release type:

   Analyze commits and present recommendation:
   - **Option 1**: "patch (X.Y.Z → X.Y.Z+1)" - Bug fixes only (Recommended if all fix: commits)
   - **Option 2**: "minor (X.Y.Z → X.Y+1.0)" - New features (Recommended if feat: commits)
   - **Option 3**: "major (X.Y.Z → X+1.0.0)" - Breaking changes

## Phase 2: Version Calculation

1. **Get current version** from latest tag:
   ```bash
   CURRENT_VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0")
   ```

2. **Calculate new version** based on bump type:
   - Parse CURRENT_VERSION into MAJOR.MINOR.PATCH
   - Apply bump: patch → PATCH+1, minor → MINOR+1 (PATCH=0), major → MAJOR+1 (MINOR=0, PATCH=0)

## Phase 3: Impact Assessment & Approval

Before making any changes, present a complete impact assessment, then **use the AskUserQuestion tool** to get explicit approval:

First, display the assessment:
```
**Release Impact Assessment**

Release type: [patch/minor/major]
Current version: vX.Y.Z
New version: vX.Y.Z (calculated)

**Commits included in this release:**
- abc1234 feat: add new capability
- def5678 fix: correct issue
- ghi9012 docs: update README

**Breaking changes:** None / [list if any]
```

Then **invoke the AskUserQuestion tool** with these options:
- **Option 1**: "Proceed with release" (Recommended)
- **Option 2**: "Change release type (patch/minor/major)"
- **Option 3**: "Cancel release"

**Do not proceed without explicit approval via the AskUserQuestion tool.**

## Phase 4: Create Tag & Release

1. **Create git tag**:
   ```bash
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   git push origin vX.Y.Z
   ```

2. **Generate release notes** from commits:

   Categorize commits by type:
   - `feat:` → New Features
   - `fix:` → Bug Fixes
   - `docs:` → Documentation
   - `refactor:` → Refactoring
   - `chore:` → Maintenance
   - Breaking changes (if any)

3. **Create GitHub Release**:
   ```bash
   gh release create vX.Y.Z --title "vX.Y.Z" --notes "RELEASE_NOTES"
   ```

## Release Notes Format

```markdown
## What's Changed

### New Features
- Description of feature (#PR)

### Bug Fixes
- Description of fix (#PR)

### Documentation
- Description of docs change (#PR)

### Other Changes
- Description (#PR)

**Full Changelog**: https://github.com/{owner}/{repo}/compare/vPREVIOUS...vX.Y.Z
```

## Phase 5: Verification

After release creation, verify everything completed successfully:

1. **Check tag exists**:
   ```bash
   git tag -l "vX.Y.Z"
   ```

2. **Check GitHub Release exists**:
   ```bash
   gh release view vX.Y.Z --json tagName,name,publishedAt
   ```

3. **Verify checklist**:
   - [ ] Git tag created and pushed
   - [ ] GitHub Release published
   - [ ] Release notes accurate

4. **If verification fails**, report specific issue and remediation steps

## Output Format

### Success
```
## Released vX.Y.Z

**Previous version:** vX.Y.Z-1
**New version:** vX.Y.Z
**Release type:** [patch/minor/major]

**Release URL:** https://github.com/{owner}/{repo}/releases/tag/vX.Y.Z

### What's Included
- N commits
- N new features
- N bug fixes

### Next Steps
- Announce the release
- Update any dependent projects
```

### Failure
```
## Release Failed

**Reason:** {specific reason}

### How to Fix
{actionable steps}

### Cleanup (if partial failure)
- Delete tag: `git tag -d vX.Y.Z && git push origin :refs/tags/vX.Y.Z`
```

## Rules

- Tag format: `vX.Y.Z` (with 'v' prefix)
- Always show impact assessment before making changes
- Always verify release after creation
- Generate changelog automatically from commits
- **Always detect default branch dynamically** - never assume `main` or `master`
- **Use the AskUserQuestion tool** for:
  - Release type selection (when not specified)
  - Impact assessment approval (required before proceeding)

## Success Criteria

Before completing, verify:
- [ ] Commits since last release analyzed
- [ ] Impact assessment shown and user approved
- [ ] Git tag created and pushed
- [ ] GitHub Release created with changelog
- [ ] All verifications passed
- [ ] User informed of release URL
