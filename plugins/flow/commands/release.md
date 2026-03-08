---
description: "[flow] Create a release with changelog generation from merged PRs. Calculates semantic version, requires human confirmation. Tier 3 — never autonomous."
argument-hint: <patch|minor|major>
allowed-tools: Bash, Read, AskUserQuestion
---

# Create Release v$ARGUMENTS

Tier 3 operation — **always requires human confirmation**.

## Required Skills

- `merge-and-release` — version calculation, changelog generation

## Phase 1: Gather Context

**Parallel operations:**

```bash
# 1. Current version (latest tag)
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "none")
echo "Current version: $LAST_TAG"

# 2. Release tag prefix from settings
TAG_PREFIX="v"  # default, read from settings.release.tagPrefix

# 3. Merged PRs since last release
if [ "$LAST_TAG" != "none" ]; then
  SINCE=$(git log -1 --format=%aI "$LAST_TAG")
  gh pr list --state merged --search "merged:>=$SINCE" --json number,title,labels --limit 50
else
  gh pr list --state merged --json number,title,labels --limit 20
fi

# 4. Commits since last release
if [ "$LAST_TAG" != "none" ]; then
  git log --oneline "$LAST_TAG"..HEAD
else
  git log --oneline -20
fi
```

## Phase 2: Calculate Version

Parse `$ARGUMENTS` for version bump type:

| Argument | Bump | Example |
|----------|------|---------|
| patch | 0.0.X+1 | 1.2.3 → 1.2.4 |
| minor | 0.X+1.0 | 1.2.3 → 1.3.0 |
| major | X+1.0.0 | 1.2.3 → 2.0.0 |

If no previous tag exists, start at v1.0.0 (or appropriate based on argument).

## Phase 3: Generate Changelog

Categorize merged PRs by conventional commit prefix:

```markdown
## What's Changed

### Features
- feat: Add user authentication (#42) @author
- feat: Add search functionality (#45) @author

### Bug Fixes
- fix: Correct cart calculation (#43) @author

### Other Changes
- docs: Update README (#44) @author
- chore: Upgrade dependencies (#46) @author

**Full Changelog**: https://github.com/{owner}/{repo}/compare/{prev}...{new}
```

## Phase 4: Confirm and Execute

Display:

```markdown
## Release Preview

**Version**: {tag_prefix}{new_version}
**Previous**: {last_tag}
**PRs included**: {N}

{generated changelog}
```

Use the AskUserQuestion tool with contextual options to confirm: "Create release {tag}? This will create a git tag and GitHub release."

Only after the user confirms via the tool:

```bash
TAG="${TAG_PREFIX}${VERSION}"
git tag -a "$TAG" -m "Release $TAG"
git push origin "$TAG"
gh release create "$TAG" --title "$TAG" --notes "$CHANGELOG"
```

## Phase 5: Post-Release

```bash
# Verify
gh release view "$TAG"
```

Display release URL and summary.

If plugin version files need updating (plugin.json, marketplace.json), note them as follow-up tasks.
