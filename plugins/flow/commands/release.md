---
description: "Create a release with changelog generation from merged PRs. Calculates the semantic version, bumps the version files, and publishes after the tier hook asks for confirmation. Tier 3 — never autonomous."
argument-hint: <patch|minor|major> [plugin-name]
allowed-tools: Bash, Read, AskUserQuestion
---

# Create Release v$ARGUMENTS

Tier 3 operation — **always requires human confirmation**. flow's tier hook asks before `gh release create` runs; nothing is tagged or published until you accept that prompt.

Arguments: the bump type (`patch`, `minor` or `major`) and, in a plugin marketplace, the name of the plugin to release (`/flow:release minor flow`).

## Required Skills

- `merge-and-release` — version calculation, changelog generation
- `run-state-management` — FlowRun/FlowActivity records at phase boundaries (v3 runtime)

```!
# Inline the Required Skills above so their rules are in context before the
# first phase runs (commands cannot preload skills from frontmatter). Ambient
# skills load whole; dispatched skills (context: fork / agent:) load their
# `## Contract` section and run in full when this command invokes
# Skill(<name>). Output per `references/command-output-format.md`.
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-load-skills.sh" merge-and-release run-state-management

true
```

## Phase 1: Gather Context

Phase 4 publish steps stay inline (they run after the assessment is shown).

```!
# Output: `###`-headed sections + KEY=value per
# `references/command-output-format.md`.

printf '%s\n' "### Current Version"
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || printf '%s\n' "none")
printf '%s\n' "LAST_TAG=$LAST_TAG"
printf '%s\n' "TAG_PREFIX=v"   # default; settings.release.tagPrefix may override at Phase 2

printf '%s\n' ""
printf '%s\n' "### Merged PRs Since Last Release"
if [ "$LAST_TAG" != "none" ]; then
  SINCE=$(git log -1 --format=%aI "$LAST_TAG" 2>/dev/null)
  MERGED_JSON=$(gh pr list --state merged --search "merged:>=$SINCE" --json number,title,labels --limit 50 2>/dev/null); GH_EXIT=$?
  printf '%s\n' "SINCE=$SINCE"
else
  MERGED_JSON=$(gh pr list --state merged --json number,title,labels --limit 20 2>/dev/null); GH_EXIT=$?
  # Quote: value contains parens, whitespace, em-dash (rule 2 of
  # references/command-output-format.md).
  printf '%s\n' "SINCE=\"(first release — using 20 most recent merged PRs)\""
fi
if [ $GH_EXIT -ne 0 ]; then
  printf '%s\n' "MERGED_PR_COUNT=0"
  printf '%s\n' "STATE=unavailable"
else
  MERGED_COUNT=$(printf '%s\n' "$MERGED_JSON" | jq 'length' 2>/dev/null)
  [ -z "$MERGED_COUNT" ] && MERGED_COUNT=0
  printf '%s\n' "MERGED_PR_COUNT=$MERGED_COUNT"
  if [ "$MERGED_COUNT" = "0" ]; then
    printf '%s\n' "STATE=empty"
  else
    printf '%s\n' "$MERGED_JSON" | jq -r '.[] | "MERGED_PR=number=\(.number) labels=\"\([.labels[].name] | join(","))\" title=\"\(.title)\""' 2>/dev/null
  fi
fi

printf '%s\n' ""
printf '%s\n' "### Commits Since Last Release"
# Capture so an empty range (right after a release) emits STATE=empty
# rather than a silent heading.
if [ "$LAST_TAG" != "none" ]; then
  COMMITS_RANGE=$(git log --oneline "$LAST_TAG"..HEAD 2>/dev/null)
else
  COMMITS_RANGE=$(git log --oneline -20 2>/dev/null)
fi
if [ -z "$COMMITS_RANGE" ]; then
  printf '%s\n' "STATE=empty"
else
  printf '%s\n' "$COMMITS_RANGE" | sed 's/^/COMMIT=/'
fi

true
```

### FlowRun (v3 runtime)

A release is a long-running workflow, so it gets a durable FlowRun. Runs are gated by `flow.runtime.enabled` (default `true`); v2 projects that opted out see `FLOW_RUN_STATE=skip` and the wiring is a no-op.

```!
# FLOW_RUN_BLOCK_BEGIN
CASCADE="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/cascade-resolve.sh"
if [ ! -x "$CASCADE" ]; then
  printf '%s\n' "FLOW_RUN_STATE=blocked"
  printf '%s\n' "FLOW_RUN_ERROR=cascade-resolve.sh missing or non-executable at $CASCADE"
  true; exit 0
fi
RUNTIME_ENABLED=$("$CASCADE" --default "true" '.flow.runtime.enabled' 2>/dev/null)
if [ "$RUNTIME_ENABLED" != "true" ]; then
  printf '%s\n' "FLOW_RUN_STATE=skip"
  printf '%s\n' "FLOW_RUN_REASON=flow.runtime.enabled is not true (v2 mode)"
else
  RUN_ID="$(date -u +%Y-%m-%dT%H%M%SZ)-release"
  printf '%s\n' "FLOW_RUN_STATE=create"
  printf '%s\n' "RUN_ID=$RUN_ID"
  printf '%s\n' "WORKFLOW=release"
  printf '%s\n' "INITIAL_PHASE=preflight"
fi
# FLOW_RUN_BLOCK_END
true
```

When `FLOW_RUN_STATE=create`, invoke `Skill(run-state-management)` to create `.flow/runs/$RUN_ID/run.yaml` (workflow=`release`, goal=`null` — a release is not goal-bound; it verifies the goals of *included* PRs in Phase 4), initial phase `preflight`. The release is not issue-scoped, so the `workflow-run` journal artifact is best-effort: emit it only if a single issue can be inferred from the included PRs; otherwise the `run.yaml` is the durable record. Phase order: `preflight → bump → confirm → tag` (matching `workflows/release.workflow.yaml`; `gh release create`, which creates the tag, is the step inside the `tag` phase).

## Phase 2: Calculate Version

The bump type is the first word of `$ARGUMENTS`; a second word names the plugin to release from a marketplace. The block below finds the version files and plans the bump without writing anything:

- the repository's own files: `package.json`, `pyproject.toml`, `Cargo.toml`, `.claude-plugin/plugin.json`;
- with a plugin name: that plugin's `plugin.json` and its entry in `.claude-plugin/marketplace.json` (the marketplace's own `metadata.version` is left alone).

Every file is listed as `bump` (with its current and new version) or `skip` (with the reason — a file flow does not edit, such as `setup.py`, a lockfile, or a dynamic version). When the files to bump disagree on the current version, the plan stops with `VERSIONS_STATE=mismatch` and nothing is released until they agree.

```!
# Output: `###`-headed sections + KEY=value per
# `references/command-output-format.md`.
# RELEASE_PLAN_BLOCK_BEGIN
printf '%s\n' "### Version Files"
_RAW="$ARGUMENTS"  # Claude Code substitutes the bare arg token, not bash parameter-expansion
RELEASE_ARGS=$(printf '%s' "$_RAW" | tr -s ' \t' '  ' | sed 's/^ //; s/ $//')
RELEASE_TYPE=${RELEASE_ARGS%% *}
RELEASE_PLUGIN=""
case "$RELEASE_ARGS" in *" "*) RELEASE_PLUGIN=${RELEASE_ARGS#* } ;; esac
case "$RELEASE_TYPE" in
  patch|minor|major) ;;
  *)
    printf '%s\n' "STATE=blocked"
    printf '%s\n' "ERROR=\"the first argument must be patch, minor or major\""
    RELEASE_TYPE="" ;;
esac
case "$RELEASE_PLUGIN" in
  '') ;;
  [a-z0-9]*)
    case "$RELEASE_PLUGIN" in
      *[!a-z0-9._-]*)
        printf '%s\n' "STATE=blocked"
        printf '%s\n' "ERROR=\"the plugin name may hold only a-z, 0-9, '.', '_' and '-'\""
        RELEASE_TYPE="" ;;
    esac ;;
  *)
    printf '%s\n' "STATE=blocked"
    printf '%s\n' "ERROR=\"the plugin name must start with a-z or 0-9\""
    RELEASE_TYPE="" ;;
esac
if [ -n "$RELEASE_TYPE" ]; then
  printf '%s\n' "RELEASE_TYPE=$RELEASE_TYPE"
  [ -n "$RELEASE_PLUGIN" ] && printf '%s\n' "RELEASE_PLUGIN=$RELEASE_PLUGIN"
  VERSIONS="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-release-versions.sh"
  if [ ! -x "$VERSIONS" ]; then
    printf '%s\n' "STATE=unavailable"
    printf '%s\n' "ERROR=\"flow-release-versions.sh missing or non-executable at $VERSIONS — reinstall or upgrade the flow plugin\""
  elif [ -n "$RELEASE_PLUGIN" ]; then
    "$VERSIONS" --plan --bump "$RELEASE_TYPE" --plugin "$RELEASE_PLUGIN"
  else
    "$VERSIONS" --plan --bump "$RELEASE_TYPE"
  fi
fi
# RELEASE_PLAN_BLOCK_END

true
```

The new version is `NEW_VERSION` when the plan has one. With `VERSIONS_STATE=none` (no version file to bump), it is the last tag's version bumped by the type:

| Argument | Bump | Example |
|----------|------|---------|
| patch | 0.0.X+1 | 1.2.3 → 1.2.4 |
| minor | 0.X+1.0 | 1.2.3 → 1.3.0 |
| major | X+1.0.0 | 1.2.3 → 2.0.0 |

If no previous tag exists, start at v1.0.0 (or appropriate based on argument).

When no plugin is named and both a version file and a previous tag exist, compare `CURRENT_VERSION` with `LAST_TAG` without its prefix. If they differ, the repository's files and its tags disagree about what was released last; ask with AskUserQuestion which to build on, offering: bump from the version files (`NEW_VERSION`), bump from the last tag (and write that version into the files), or stop. Recommend the version files when the tag is older, since a later release was likely tagged elsewhere. With a plugin named, the tags belong to the marketplace and are not compared.

With `VERSIONS_STATE=mismatch` or `VERSIONS_STATE=refused`, stop and show the `REFUSED` reason: the release cannot write its version consistently.

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

## Phase 4: Show the Assessment and Publish

Show the assessment as text — this is not a question; the tier hook asks for confirmation when `gh release create` runs:

```markdown
## Release Preview

**Version**: {tag_prefix}{new_version}
**Previous**: {last_tag}
**PRs included**: {N}

**Version files**:
- bump {path} {current} → {new}
- skip {path} — {reason}

{generated changelog}

Publishing commits the version bump, pushes it, then creates the tag and the GitHub release at that commit. flow's tier hook asks before `gh release create` runs.
```

Then run the block below with `VERSION` set to the new version, `PLUGIN` to the plugin name (empty when none was given), `TAG_PREFIX` to the tag prefix, and `CHANGELOG` to the generated changelog. It writes the planned bump and commits only those files; when there is nothing to bump it commits nothing.

```bash
# RELEASE_BUMP_BLOCK_BEGIN
TAG="${TAG_PREFIX:-v}${VERSION:-}"
if [ -z "${VERSION:-}" ]; then
  printf '%s\n' "BUMP_STATE=blocked"
  printf '%s\n' "BUMP_ERROR=\"VERSION is not set; set it to the version Phase 2 calculated\""
  exit 1
fi
VERSIONS="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-release-versions.sh"
if [ ! -x "$VERSIONS" ]; then
  printf '%s\n' "BUMP_STATE=blocked"
  printf '%s\n' "BUMP_ERROR=\"flow-release-versions.sh missing or non-executable at $VERSIONS\""
  exit 1
fi
if [ -n "${PLUGIN:-}" ]; then
  BUMP_OUT=$("$VERSIONS" --write --to "$VERSION" --plugin "$PLUGIN"); BUMP_RC=$?
else
  BUMP_OUT=$("$VERSIONS" --write --to "$VERSION"); BUMP_RC=$?
fi
printf '%s\n' "$BUMP_OUT"
if [ "$BUMP_RC" -ne 0 ]; then
  printf '%s\n' "BUMP_STATE=blocked"
  exit 1
fi
# The script names only paths without spaces or quotes, one per line.
BUMP_FILES=$(printf '%s\n' "$BUMP_OUT" | sed -n 's/^VERSION_FILE=bump path=\([^ ]*\) .*/\1/p')
if printf '%s\n' "$BUMP_OUT" | grep -qx 'VERSIONS_STATE=unchanged'; then
  # A re-run after the bump commit: the files already hold VERSION.
  printf '%s\n' "BUMP_STATE=unchanged"
elif ! printf '%s\n' "$BUMP_OUT" | grep -qx 'VERSIONS_STATE=written' || [ -z "$BUMP_FILES" ]; then
  printf '%s\n' "BUMP_STATE=none"
else
  # Paths given to git commit commit those files alone, whatever else is staged.
  if printf '%s\n' "$BUMP_FILES" | xargs git commit -q -m "chore(release): $TAG" --; then
    printf '%s\n' "BUMP_STATE=committed"
  else
    printf '%s\n' "BUMP_STATE=blocked"
    printf '%s\n' "BUMP_ERROR=\"git commit failed; the bumped files are left in the working tree\""
    exit 1
  fi
fi
# RELEASE_BUMP_BLOCK_END
# The tag is created on GitHub by gh release create, at the commit just pushed,
# so no tag exists anywhere until the tier prompt is accepted: a tag pushed
# earlier would start any workflow that publishes on a tag.
git push origin HEAD &&
  gh release create "$TAG" --target "$(git rev-parse HEAD)" --title "$TAG" --notes "$CHANGELOG" &&
  git fetch origin "refs/tags/$TAG:refs/tags/$TAG"
```

If you decline the tier prompt, the bump commit is already pushed and no tag or release exists. A later `/flow:release` reads the bumped version as current, so give Phase 4 the version you meant to release rather than bumping a second time: the block then reports `BUMP_STATE=unchanged` and commits nothing.

**FlowActivity writes** (when `FLOW_RUN_STATE=create`): invoke `Skill(run-state-management)` to record one FlowActivity per phase boundary as it completes — `bump` (version calculated, version files bumped and committed, changelog generated), `confirm` (the tier prompt before `gh release create` was accepted), and `tag` (`gh release create` created the tag and the release, and the tag was fetched). Each write advances `state.current_phase` per the `preflight → bump → confirm → tag` order.

## Phase 5: Post-Release

```bash
# Verify
gh release view "$TAG"
```

**FlowRun terminal transition** (when `FLOW_RUN_STATE=create`): after the release publishes successfully, invoke `Skill(run-state-management)` to transition the FlowRun to `state.status: completed`. If a `workflow-run` journal artifact was emitted at entry, update it to `status=completed` via a second `bin/journal-record.sh` call. If the release failed or was cancelled, transition to `state.status: cancelled` (with `blocked_reason`) instead so `/flow:resume` does not treat it as resumable.

Display the release URL and a summary that lists every version file bumped and every file skipped with its reason.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read git history / merged PRs / current version | 1 | Autonomous, read-only |
| Calculate next version | 1 | Autonomous |
| Generate changelog from PR titles | 1 | Autonomous |
| Plan the version-file bump (`flow-release-versions.sh --plan`) | 1 | Autonomous, read-only |
| Write the bump and commit those files | 1 | Autonomous, local |
| `git push origin HEAD` (the bump commit) | 2 | Per `flow.tiers.push` |
| `gh release create <tag> --target <sha>` (creates the tag and the release) | 3 | **Confirm** — the tier hook asks before it runs |
| Post-release verification (`gh release view`) | 1 | Autonomous |

`/flow:release` is **Tier 3** for the publish path: the tag and the release are created together by `gh release create`, which flow's tier hook does not let run without your confirmation, whatever `flow.tiers.release` says. The cost of an unwanted release (downstream consumers pulling a broken version, false notifications) is borne by people downstream, which is the Tier 3 criterion.
