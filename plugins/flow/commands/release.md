---
description: "Create a release with changelog generation from merged PRs. Calculates semantic version, requires human confirmation. Tier 3 — never autonomous."
argument-hint: <patch|minor|major>
allowed-tools: Bash(git describe *) Bash(git log *) Bash(git tag *) Bash(git push *) Bash(gh pr list *) Bash(gh release create *) Bash(gh release view *) Read AskUserQuestion
disable-model-invocation: true
---

<!--
TIER 3 — `disable-model-invocation: true` prevents the Claude Code
`SlashCommand` tool from programmatically invoking this command. The
AskUserQuestion gate at Phase 4 is the human-confirmation contract for
typed-in invocations; this frontmatter field is the equivalent contract
against autonomous agents. See `plugins/flow/references/command-patterns.md`
§Decision: disable-model-invocation for the full rationale.
-->
<!-- Authoring patterns: plugins/flow/references/command-patterns.md -->


<!--
EXECUTION MODEL:
Phase 1 context-gathering bash is pre-executed via the `!` prefix at command
load — no Bash tool round-trip. Phase 4 publish actions (tag, push tag,
gh release create) and Phase 5 verification stay inline because they require
explicit user confirmation via AskUserQuestion (Tier 3) and depend on
LLM-computed values.
-->

# Create Release v$ARGUMENTS

Tier 3 operation — **always requires human confirmation**.

## Required Skills

- `merge-and-release` — version calculation, changelog generation

## Phase 1: Gather Context

Pre-executed at command load (`!` prefix injects output before the LLM reads
the prompt — no Bash tool round-trip required).

```!
# 1. Current version (latest tag).
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "none")
echo "Current version: $LAST_TAG"

# 2. Release tag prefix from settings.
TAG_PREFIX="v"  # default, read from settings.release.tagPrefix

# 3. Ancestry sanity check. If LAST_TAG isn't an ancestor of HEAD (e.g.,
#    LAST_TAG was placed on a divergent hotfix branch), `$LAST_TAG..HEAD`
#    produces misleading output — `git log` shows commits unique to HEAD
#    only, omitting anything on the LAST_TAG branch the user might also
#    want released. Surface the divergence as TAG_ANCESTOR=no so the
#    LLM (and the user) know not to trust the changelog without manual
#    review of the ancestry.
if [ "$LAST_TAG" != "none" ]; then
  if git merge-base --is-ancestor "$LAST_TAG" HEAD 2>/dev/null; then
    echo "TAG_ANCESTOR=yes"
  else
    echo "TAG_ANCESTOR=no ($LAST_TAG is not in HEAD's ancestry — changelog may be incomplete)"
  fi
fi

# 4. Merged PRs since last release.
if [ "$LAST_TAG" != "none" ]; then
  SINCE=$(git log -1 --format=%aI "$LAST_TAG")
  gh pr list --state merged --search "merged:>=$SINCE" --json number,title,labels --limit 50
else
  gh pr list --state merged --json number,title,labels --limit 20
fi

# 5. Commits since last release.
if [ "$LAST_TAG" != "none" ]; then
  git log --oneline "$LAST_TAG"..HEAD
else
  git log --oneline -20
fi

true  # explicit success
```

**If `TAG_ANCESTOR=no`** appears, halt and surface a six-field
Proactive-Autonomy escalation (see `references/escalation-format.md`)
before computing the version bump — the changelog will not faithfully
represent what's between the prior tag and HEAD.

**If Phase 1 output is empty or contains `gh` auth errors, halt before
Phase 2** — without a current-version baseline and merged-PR list, version
calculation and changelog generation cannot be trusted.

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

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read git history / merged PRs / current version | 1 | Autonomous, read-only |
| Calculate next version | 1 | Autonomous |
| Generate changelog from PR titles | 1 | Autonomous |
| `git tag -a <tag> -m <msg>` | 3 | **Confirm** — bundled into release prompt |
| `git push origin <tag>` | 3 | **Confirm** — bundled into release prompt |
| `gh release create <tag>` | 3 | **Confirm** — bundled into release prompt |
| Post-release verification (`gh release view`) | 1 | Autonomous |

`/flow:release` is **fully Tier 3** for the publish path: tag, push tag, and `gh release create` are non-negotiably gated behind a single `AskUserQuestion` confirmation. The cost of an unwanted release (downstream consumers pulling a broken version, false notifications) is borne by people downstream, which is the Tier 3 criterion.
