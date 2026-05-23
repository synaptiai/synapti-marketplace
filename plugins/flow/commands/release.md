---
description: "Create a release with changelog generation from merged PRs. Calculates semantic version, requires human confirmation. Tier 3 — never autonomous."
argument-hint: <patch|minor|major>
allowed-tools: Bash, Read, AskUserQuestion
---

# Create Release v$ARGUMENTS

Tier 3 operation — **always requires human confirmation**.

## Required Skills

- `merge-and-release` — version calculation, changelog generation

## Phase 1: Gather Context

Phase 2 version calculation and Phase 4 publish steps stay inline (they depend on $ARGUMENTS classification and user confirmation).

```!
# Output: `###`-headed sections + KEY=value per
# `references/command-output-format.md`.

echo "### Current Version"
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "none")
echo "LAST_TAG=$LAST_TAG"
echo "TAG_PREFIX=v"   # default; settings.release.tagPrefix may override at Phase 2

echo ""
echo "### Merged PRs Since Last Release"
if [ "$LAST_TAG" != "none" ]; then
  SINCE=$(git log -1 --format=%aI "$LAST_TAG" 2>/dev/null)
  MERGED_JSON=$(gh pr list --state merged --search "merged:>=$SINCE" --json number,title,labels --limit 50 2>/dev/null); GH_EXIT=$?
  echo "SINCE=$SINCE"
else
  MERGED_JSON=$(gh pr list --state merged --json number,title,labels --limit 20 2>/dev/null); GH_EXIT=$?
  # Quote: value contains parens, whitespace, em-dash (rule 2 of
  # references/command-output-format.md).
  echo "SINCE=\"(first release — using 20 most recent merged PRs)\""
fi
if [ $GH_EXIT -ne 0 ]; then
  echo "MERGED_PR_COUNT=0"
  echo "STATE=unavailable"
else
  MERGED_COUNT=$(echo "$MERGED_JSON" | jq 'length' 2>/dev/null)
  [ -z "$MERGED_COUNT" ] && MERGED_COUNT=0
  echo "MERGED_PR_COUNT=$MERGED_COUNT"
  if [ "$MERGED_COUNT" = "0" ]; then
    echo "STATE=empty"
  else
    echo "$MERGED_JSON" | jq -r '.[] | "MERGED_PR=number=\(.number) labels=\"\([.labels[].name] | join(","))\" title=\"\(.title)\""' 2>/dev/null
  fi
fi

echo ""
echo "### Commits Since Last Release"
# Capture so an empty range (right after a release) emits STATE=empty
# rather than a silent heading.
if [ "$LAST_TAG" != "none" ]; then
  COMMITS_RANGE=$(git log --oneline "$LAST_TAG"..HEAD 2>/dev/null)
else
  COMMITS_RANGE=$(git log --oneline -20 2>/dev/null)
fi
if [ -z "$COMMITS_RANGE" ]; then
  echo "STATE=empty"
else
  printf '%s\n' "$COMMITS_RANGE" | sed 's/^/COMMIT=/'
fi

true
```

### FlowRun (v3 runtime)

A release is a long-running workflow, so it gets a durable FlowRun. Runs are gated by `flow.runtime.enabled` (default `true`); v2 projects that opted out see `FLOW_RUN_STATE=skip` and the wiring is a no-op.

```!
# FLOW_RUN_BLOCK_BEGIN
CASCADE="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh"
if [ ! -x "$CASCADE" ]; then
  echo "FLOW_RUN_STATE=blocked"
  echo "FLOW_RUN_ERROR=cascade-resolve.sh missing or non-executable at $CASCADE"
  true; exit 0
fi
RUNTIME_ENABLED=$("$CASCADE" --default "true" '.flow.runtime.enabled' 2>/dev/null)
if [ "$RUNTIME_ENABLED" != "true" ]; then
  echo "FLOW_RUN_STATE=skip"
  echo "FLOW_RUN_REASON=flow.runtime.enabled is not true (v2 mode)"
else
  RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-release"
  echo "FLOW_RUN_STATE=create"
  echo "RUN_ID=$RUN_ID"
  echo "WORKFLOW=release"
  echo "INITIAL_PHASE=preflight"
fi
# FLOW_RUN_BLOCK_END
true
```

When `FLOW_RUN_STATE=create`, invoke `Skill(run-state-management)` to create `.flow/runs/$RUN_ID/run.yaml` (workflow=`release`, goal=`null` — a release is not goal-bound; it verifies the goals of *included* PRs in Phase 4), initial phase `preflight`. The release is not issue-scoped, so the `workflow-run` journal artifact is best-effort: emit it only if a single issue can be inferred from the included PRs; otherwise the `run.yaml` is the durable record. Phase order: `preflight → bump → tag → push`.

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

**FlowActivity writes** (when `FLOW_RUN_STATE=create`): invoke `Skill(run-state-management)` to record one FlowActivity per phase boundary as it completes — `bump` (version calculated, phase `bump`), `tag` (`git tag` succeeded, phase `tag`), and `push` (`git push` + `gh release create` succeeded, phase `push`). Each write advances `state.current_phase` per the `preflight → bump → tag → push` order.

## Phase 5: Post-Release

```bash
# Verify
gh release view "$TAG"
```

**FlowRun terminal transition** (when `FLOW_RUN_STATE=create`): after the release publishes successfully, invoke `Skill(run-state-management)` to transition the FlowRun to `state.status: completed`. If a `workflow-run` journal artifact was emitted at entry, update it to `status=completed` via a second `bin/journal-record.sh` call. If the release failed or was cancelled, transition to `state.status: cancelled` (with `blocked_reason`) instead so `/flow:resume` does not treat it as resumable.

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
