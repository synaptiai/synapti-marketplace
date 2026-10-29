---
description: "Create a release in two runs: open a release pull request that bumps the version files and changelog, then, once it is merged, tag the merge commit and publish the GitHub release. Tier 3 — never autonomous."
argument-hint: <patch|minor|major> [plugin-name] [marketplace-bump]
allowed-tools: Bash, Read, AskUserQuestion
---

# Create Release v$ARGUMENTS

Tier 3 operation — **always requires human confirmation**. The version bump reaches the default branch only through a release pull request; flow's tier hook asks before the tag is pushed, and nothing is published until you accept that prompt.

Arguments: the bump type (`patch`, `minor` or `major`) and, in a plugin marketplace, the name of the plugin to release and optionally the marketplace's bump type (`/flow:release minor flow`).

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
    # Titles and labels are JSON-quoted (@json), so a quote or a line break
    # in one stays inside its value and cannot print a line of its own.
    printf '%s\n' "$MERGED_JSON" | jq -r '.[] | "MERGED_PR=number=\(.number) labels=\([.labels[].name] | join(",") | @json) title=\(.title | @json)"' 2>/dev/null
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

When `FLOW_RUN_STATE=create`, invoke `Skill(run-state-management)` to create `.flow/runs/$RUN_ID/run.yaml` (workflow=`release`, goal=`null` — a release is not goal-bound; it verifies the goals of *included* PRs in Phase 4), initial phase `preflight`. The release is not issue-scoped, so the `workflow-run` journal artifact is best-effort: emit it only if a single issue can be inferred from the included PRs; otherwise the `run.yaml` is the durable record. A release takes two runs of `/flow:release`, matching `workflows/release.workflow.yaml`: phase order `preflight → bump → release_pr` on the first run, which opens the release pull request, and `preflight → tag` on the second, after that pull request is merged.

## Phase 2: Release State and Version

The first word of `$ARGUMENTS` is the bump type. In a plugin marketplace, the second names the plugin to release, and an optional third the bump type for the marketplace's own version (by default minor for a minor or major plugin release, patch for a patch).

The block below works out which run this is, from the state of the repository and its pull requests. It never writes:

- `RELEASE_RUN=pr` — the current version is released (its tag is on origin and GitHub has a release for it), so this run plans the next one: it bumps the version files on a release branch and opens the release pull request.
- `RELEASE_RUN=waiting` — the release pull request for the next version is open. Nothing to do until it is merged; show `RELEASE_PR` and stop.
- `RELEASE_RUN=tag` — the default branch carries a version that has no tag, and its release pull request is merged: this run tags that merge commit (`TAG_COMMIT`) and publishes the GitHub release. With no version file at all, it tags the default branch's head with the last tag's version bumped.
- `RELEASE_RUN=untagged` — the default branch carries a version that has no tag and no merged release pull request (a version bumped by hand, or a first release).
- `RELEASE_RUN=publish` — the current version's tag (`TAG`) is on origin but GitHub has no release for it, as when an earlier run pushed the tag and the release was not created. This run creates only the GitHub release, unless you choose to skip it and plan the next version (see the question after the block).

The run stops with `STATE=blocked` when the current version's tag is in this clone but not on origin (a tag push that did not finish): `LOCAL_TAG` names it. Show the user both ways forward: push it with `git push origin <tag>`, after which the next run publishes it, or delete it with `git tag -d <tag>`. It stops the same way when a release branch is left in this clone from an earlier run with no pull request: `LOCAL_BRANCH` names it, to be pushed with `git push -u origin <branch>` and given its pull request with `gh pr create --base <default branch> --head <branch>`, or deleted with `git branch -D <branch>`. It stops the same way when GitHub has only a draft release for the tag: `DRAFT_RELEASE` names the tag, to be published with `gh release edit <tag> --draft=false` or deleted with `gh release delete <tag>` (flow's tier hook asks before either runs); deleting keeps the tag, so the next run creates the release. `STATE=unavailable` means origin or GitHub did not answer, and the run cannot tell what is released.

The version files are the repository's own (`package.json`, `pyproject.toml`, `Cargo.toml`, `.claude-plugin/plugin.json`) or, with a plugin named, that plugin's `plugin.json`, its entry in `.claude-plugin/marketplace.json`, and the marketplace's `metadata.version`. Every file is listed as `bump` (current and new version) or `skip` (with the reason: a file flow does not edit, such as `setup.py`, a lockfile, or a dynamic version). The tag is `TAG_PREFIX` + `TAG_VERSION`: the marketplace version in a marketplace, the version otherwise. The release branch is `conventions.branchPatterns.release` with `{version}` replaced by `TAG_VERSION` (default `chore/release-{version}`).

```!
# Output: `###`-headed sections + KEY=value per
# `references/command-output-format.md`.
# RELEASE_PLAN_BLOCK_BEGIN
printf '%s\n' "### Release State"
_RAW="$ARGUMENTS"  # Claude Code substitutes the bare arg token, not bash parameter-expansion
RELEASE_ARGS=$(printf '%s' "$_RAW" | tr -s ' \t' '  ' | sed 's/^ //; s/ $//')
RELEASE_TYPE=${RELEASE_ARGS%% *}
RELEASE_REST=""
case "$RELEASE_ARGS" in *" "*) RELEASE_REST=${RELEASE_ARGS#* } ;; esac
RELEASE_PLUGIN=${RELEASE_REST%% *}
MARKET_TYPE=""
case "$RELEASE_REST" in *" "*) MARKET_TYPE=${RELEASE_REST#* } ;; esac
PLAN_ERROR=""
case "$RELEASE_TYPE" in
  patch|minor|major) ;;
  *) PLAN_ERROR="the first argument must be patch, minor or major" ;;
esac
case "$RELEASE_PLUGIN" in
  '') ;;
  [a-z0-9]*) case "$RELEASE_PLUGIN" in *[!a-z0-9._-]*) PLAN_ERROR="the plugin name may hold only a-z, 0-9, '.', '_' and '-'" ;; esac ;;
  *) PLAN_ERROR="the plugin name must start with a-z or 0-9" ;;
esac
case "$MARKET_TYPE" in
  ''|patch|minor|major) ;;
  *) PLAN_ERROR="the marketplace bump type must be patch, minor or major" ;;
esac
FLOW_ROOT="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")"
VERSIONS="$FLOW_ROOT/bin/flow-release-versions.sh"
CASCADE="$FLOW_ROOT/bin/cascade-resolve.sh"
if [ -z "$PLAN_ERROR" ] && { [ ! -x "$VERSIONS" ] || [ ! -x "$CASCADE" ]; }; then
  PLAN_ERROR="flow's bin/ helpers are missing at $FLOW_ROOT — reinstall or upgrade the flow plugin"
fi
DEFAULT_BRANCH=""
if [ -z "$PLAN_ERROR" ]; then
  if ! DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name) || [ -z "$DEFAULT_BRANCH" ]; then
    PLAN_ERROR="gh could not name the default branch"
  elif ! git fetch -q --tags origin; then
    PLAN_ERROR="git fetch origin failed"
  elif [ "$(git branch --show-current)" != "$DEFAULT_BRANCH" ] \
       || [ "$(git rev-parse HEAD)" != "$(git rev-parse -q --verify "refs/remotes/origin/$DEFAULT_BRANCH")" ]; then
    PLAN_ERROR="check out $DEFAULT_BRANCH at origin/$DEFAULT_BRANCH (git switch $DEFAULT_BRANCH && git pull --ff-only), then run /flow:release again"
  fi
fi
if [ -n "$PLAN_ERROR" ]; then
  printf '%s\n' "STATE=blocked"
  printf '%s\n' "ERROR=\"$PLAN_ERROR\""
else
  TAG_PREFIX=$("$CASCADE" --default "v" '.release.tagPrefix' 2>/dev/null) || TAG_PREFIX="v"
  BRANCH_PATTERN=$("$CASCADE" --default "chore/release-{version}" '.conventions.branchPatterns.release' 2>/dev/null) \
    || BRANCH_PATTERN="chore/release-{version}"
  printf '%s\n' "RELEASE_TYPE=$RELEASE_TYPE"
  [ -n "$RELEASE_PLUGIN" ] && printf '%s\n' "RELEASE_PLUGIN=$RELEASE_PLUGIN"
  printf '%s\n' "DEFAULT_BRANCH=$DEFAULT_BRANCH"
  printf '%s\n' "TAG_PREFIX=$TAG_PREFIX"
  if [ -n "$RELEASE_PLUGIN" ]; then
    CUR_OUT=$("$VERSIONS" --plan --plugin "$RELEASE_PLUGIN")
  else
    CUR_OUT=$("$VERSIONS" --plan)
  fi
  CUR_STATE=$(printf '%s\n' "$CUR_OUT" | sed -n 's/^VERSIONS_STATE=//p')
  CUR_TAG_VERSION=$(printf '%s\n' "$CUR_OUT" | sed -n 's/^CURRENT_TAG_VERSION=//p')
  ORIGIN_HEAD=$(git rev-parse "refs/remotes/origin/$DEFAULT_BRANCH")
  # _flow_tag_state: where the tag CHECK_TAG is. TAG_WHERE is remote (on
  # origin), local (in this clone only), absent, or error (origin did not
  # answer); with remote, GH_RELEASE is yes (published), draft, no or error.
  # A tag in this clone alone does not make a release: a tag push that failed
  # leaves one, and so does a GitHub release that was never created.
  _flow_tag_state() {
    TAG_WHERE=absent
    GH_RELEASE=""
    git ls-remote --exit-code --tags origin "refs/tags/$CHECK_TAG" >/dev/null 2>&1
    _ls_rc=$?
    if [ "$_ls_rc" -eq 0 ]; then
      TAG_WHERE=remote
      # FLOW_RELEASE_SKIP_PUBLISH names a tag on origin the user chose not
      # to make a GitHub release for: it counts as released.
      if [ -n "${FLOW_RELEASE_SKIP_PUBLISH:-}" ] && [ "$CHECK_TAG" = "$FLOW_RELEASE_SKIP_PUBLISH" ]; then
        GH_RELEASE=yes
      elif _gh_err=$(gh api "repos/{owner}/{repo}/releases/tags/$CHECK_TAG" --jq .tag_name 2>&1 >/dev/null); then
        GH_RELEASE=yes
      else
        case "$_gh_err" in *"(HTTP 404)"*) GH_RELEASE=no ;; *) GH_RELEASE=error ;; esac
      fi
      # The lookup by tag finds published releases only. A draft for the tag
      # is in the release list; creating a release beside it would make two.
      # The tag is compared in the shell, not in the jq text, so nothing in
      # the tag prefix from settings is read as jq.
      if [ "$GH_RELEASE" = no ]; then
        if _drafts=$(gh api --paginate "repos/{owner}/{repo}/releases?per_page=100" --jq '.[] | select(.draft) | .tag_name'); then
          if printf '%s\n' "$_drafts" | grep -qxF -- "$CHECK_TAG"; then
            GH_RELEASE=draft
          fi
        else
          GH_RELEASE=error
        fi
      fi
    elif [ "$_ls_rc" -ne 2 ]; then
      TAG_WHERE=error
    elif git rev-parse -q --verify "refs/tags/$CHECK_TAG" >/dev/null; then
      TAG_WHERE=local
    fi
  }
  # _flow_tag_done: when CHECK_TAG is not a published release and that decides
  # this run, print the state and set TAG_DONE=1: publish the tag that is on
  # origin, or stop.
  _flow_tag_done() {
    TAG_DONE=1
    if [ "$TAG_WHERE" = error ]; then
      printf '%s\n' "STATE=unavailable"
      printf '%s\n' "ERROR=\"git could not list the tags on origin\""
    elif [ "$TAG_WHERE" = local ]; then
      printf '%s\n' "STATE=blocked"
      printf '%s\n' "LOCAL_TAG=$CHECK_TAG"
      printf '%s\n' "ERROR=\"the tag $CHECK_TAG is in this clone but not on origin; push it to publish it, or delete it, then run /flow:release again\""
    elif [ "$GH_RELEASE" = error ]; then
      printf '%s\n' "STATE=unavailable"
      printf '%s\n' "ERROR=\"gh could not say whether GitHub has a release for $CHECK_TAG\""
    elif [ "$GH_RELEASE" = draft ]; then
      printf '%s\n' "STATE=blocked"
      printf '%s\n' "DRAFT_RELEASE=$CHECK_TAG"
      printf '%s\n' "ERROR=\"GitHub has a draft release for $CHECK_TAG; publish it (gh release edit $CHECK_TAG --draft=false) or delete it (gh release delete $CHECK_TAG), then run /flow:release again\""
    elif [ "$GH_RELEASE" = no ]; then
      printf '%s\n' "RELEASE_RUN=publish"
      printf '%s\n' "TAG=$CHECK_TAG"
    else
      TAG_DONE=0
    fi
  }
  TAG_DONE=0
  UNTAGGED=0
  if [ "$CUR_STATE" = "mismatch" ] || [ "$CUR_STATE" = "refused" ]; then
    printf '%s\n' "$CUR_OUT"
    printf '%s\n' "STATE=blocked"
    printf '%s\n' "ERROR=\"the version files cannot be bumped consistently; see REFUSED\""
  elif [ "$CUR_STATE" = "none" ]; then
    # No version file: a tag-only release of the head of the default branch.
    printf '%s\n' "$CUR_OUT"
    LAST=$(git describe --tags --abbrev=0 "$ORIGIN_HEAD" 2>/dev/null)
    if [ -n "$LAST" ]; then
      CHECK_TAG="$LAST"
      _flow_tag_state
      _flow_tag_done
    fi
    LAST_V=${LAST#"$TAG_PREFIX"}
    case "$LAST_V" in
      '') NEXT_V="1.0.0" ;;
      *[!0-9.]*|*.*.*.*) NEXT_V="" ;;
      *.*.*)
        MA=${LAST_V%%.*}; MI=${LAST_V#*.}; MI=${MI%%.*}; PA=${LAST_V##*.}
        case "$RELEASE_TYPE" in
          major) NEXT_V="$((MA + 1)).0.0" ;;
          minor) NEXT_V="$MA.$((MI + 1)).0" ;;
          *) NEXT_V="$MA.$MI.$((PA + 1))" ;;
        esac ;;
      *) NEXT_V="" ;;
    esac
    if [ "$TAG_DONE" = 1 ]; then
      :
    elif [ -z "$NEXT_V" ]; then
      printf '%s\n' "STATE=blocked"
      printf '%s\n' "ERROR=\"the last tag $LAST is not $TAG_PREFIX + MAJOR.MINOR.PATCH\""
    else
      printf '%s\n' "RELEASE_RUN=tag"
      printf '%s\n' "TAG=$TAG_PREFIX$NEXT_V"
      printf '%s\n' "TAG_COMMIT=$ORIGIN_HEAD"
    fi
  else
    CHECK_TAG="$TAG_PREFIX$CUR_TAG_VERSION"
    _flow_tag_state
    if [ "$TAG_WHERE" = remote ] && [ "$GH_RELEASE" = yes ]; then
      # The current version is released: plan the next one.
      if [ -n "$RELEASE_PLUGIN" ] && [ -n "$MARKET_TYPE" ]; then
        PLAN_OUT=$("$VERSIONS" --plan --bump "$RELEASE_TYPE" --plugin "$RELEASE_PLUGIN" --market-bump "$MARKET_TYPE")
      elif [ -n "$RELEASE_PLUGIN" ]; then
        PLAN_OUT=$("$VERSIONS" --plan --bump "$RELEASE_TYPE" --plugin "$RELEASE_PLUGIN")
      else
        PLAN_OUT=$("$VERSIONS" --plan --bump "$RELEASE_TYPE")
      fi
      PLAN_RC=$?
      printf '%s\n' "$PLAN_OUT"
      LOOKUP_VERSION=$(printf '%s\n' "$PLAN_OUT" | sed -n 's/^TAG_VERSION=//p')
      [ "$PLAN_RC" -eq 0 ] || LOOKUP_VERSION=""
    else
      printf '%s\n' "$CUR_OUT"
      _flow_tag_done
      LOOKUP_VERSION="$CUR_TAG_VERSION"
      UNTAGGED=1
    fi
    # The script prints only semantic versions; this keeps any other value
    # out of the tag and branch names below.
    case "$LOOKUP_VERSION" in
      *[!0-9A-Za-z.+-]*) LOOKUP_VERSION="" ;;
    esac
    # The branch pattern comes from settings; {version} is replaced by
    # parameter expansion, which reads nothing in the version as syntax.
    RELEASE_BRANCH=${BRANCH_PATTERN//\{version\}/$LOOKUP_VERSION}
    if [ "$TAG_DONE" = 1 ]; then
      :
    elif [ -z "$LOOKUP_VERSION" ]; then
      printf '%s\n' "STATE=blocked"
      printf '%s\n' "ERROR=\"the next version cannot be worked out; see REFUSED\""
    elif ! git check-ref-format --branch "$RELEASE_BRANCH" >/dev/null 2>&1; then
      printf '%s\n' "STATE=blocked"
      printf '%s\n' "ERROR=\"conventions.branchPatterns.release, with {version} replaced, is not a valid branch name\""
    else
      printf '%s\n' "TAG=$TAG_PREFIX$LOOKUP_VERSION"
      printf '%s\n' "RELEASE_BRANCH=$RELEASE_BRANCH"
      if ! PR_LINE=$(gh pr list --state all --head "$RELEASE_BRANCH" --base "$DEFAULT_BRANCH" \
            --json number,state,url,mergeCommit \
            --jq 'map(select(.state != "CLOSED")) | .[0] // empty | "\(.state) \(.mergeCommit.oid // "-") \(.url)"'); then
        printf '%s\n' "STATE=unavailable"
        printf '%s\n' "ERROR=\"gh could not list the release pull requests\""
      else
        PR_STATE=${PR_LINE%% *}
        PR_REST=${PR_LINE#* }
        PR_URL=${PR_REST#* }
        [ -n "$PR_LINE" ] && printf '%s\n' "RELEASE_PR=$PR_URL"
        if [ "$UNTAGGED" = 1 ]; then
          if [ "$PR_STATE" = "MERGED" ]; then
            printf '%s\n' "RELEASE_RUN=tag"
            printf '%s\n' "TAG_COMMIT=${PR_REST%% *}"
          else
            printf '%s\n' "RELEASE_RUN=untagged"
            printf '%s\n' "TAG_COMMIT=$ORIGIN_HEAD"
          fi
        elif [ "$PR_STATE" = "OPEN" ]; then
          printf '%s\n' "RELEASE_RUN=waiting"
        elif [ "$PR_STATE" = "MERGED" ]; then
          printf '%s\n' "STATE=blocked"
          printf '%s\n' "ERROR=\"the release pull request is merged but origin/$DEFAULT_BRANCH does not carry its version; pull and run /flow:release again\""
        elif git ls-remote --exit-code --heads origin "$RELEASE_BRANCH" >/dev/null 2>&1; then
          printf '%s\n' "STATE=blocked"
          printf '%s\n' "ERROR=\"origin already has $RELEASE_BRANCH with no open pull request; open one for it or delete the branch\""
        elif git rev-parse -q --verify "refs/heads/$RELEASE_BRANCH" >/dev/null; then
          printf '%s\n' "STATE=blocked"
          printf '%s\n' "LOCAL_BRANCH=$RELEASE_BRANCH"
          printf '%s\n' "ERROR=\"the local branch $RELEASE_BRANCH is left from an earlier run; push it and open its pull request, or delete it, then run /flow:release again\""
        else
          printf '%s\n' "RELEASE_RUN=pr"
        fi
      fi
    fi
  fi
fi
# RELEASE_PLAN_BLOCK_END

true
```

With `STATE=blocked`, stop and show `ERROR` (and the `REFUSED` reason when the version files disagree or cannot be edited). With `RELEASE_RUN=untagged`, ask with AskUserQuestion which to do, recommending the first when the version files were bumped on purpose:

1. Tag the default branch's head (`TAG_COMMIT`) as `TAG` and publish it: continue as `RELEASE_RUN=tag`.
2. Stop, so the version on the default branch can be checked or corrected first.

With `RELEASE_RUN=publish`, ask with AskUserQuestion which to do. A repository that pushes tags but does not use GitHub releases lands here on every run, so the second choice is how it plans its next version:

1. Publish a GitHub release for `TAG` (Recommended): continue as `RELEASE_RUN=publish`.
2. Skip it and plan the next version: run the block below with `TAG` from Phase 2. It runs this phase again with `TAG` counted as released and prints a new release state; continue from that output as from the first (usually `RELEASE_RUN=pr`).
3. Stop.

```bash
if [ -z "${TAG:-}" ]; then
  printf '%s\n' "STATE=blocked"
  printf '%s\n' "ERROR=\"set TAG to the tag whose release is skipped\""
  exit 1
fi
RELEASE_MD="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/commands/release.md"
# The Phase 2 block, between its marker lines. The patterns match whole
# lines, so this line, which holds the marker names inside other text, is
# not read as a marker.
PLAN_SCRIPT=$(sed -n '/^[[:space:]]*# RELEASE_PLAN_BLOCK_BEGIN[[:space:]]*$/,/^[[:space:]]*# RELEASE_PLAN_BLOCK_END[[:space:]]*$/p' "$RELEASE_MD" 2>/dev/null)
if [ -z "$PLAN_SCRIPT" ]; then
  printf '%s\n' "STATE=blocked"
  printf '%s\n' "ERROR=\"cannot read the Phase 2 block from $RELEASE_MD — reinstall or upgrade the flow plugin\""
  exit 1
fi
# The block reads the arguments from $ARGUMENTS, which Claude Code fills in
# here as it did when it ran the block the first time.
FLOW_RELEASE_SKIP_PUBLISH="$TAG" ARGUMENTS="$ARGUMENTS" bash -c "$PLAN_SCRIPT"
```

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

On `RELEASE_RUN=pr`, when the repository keeps a changelog file (the plugin's `CHANGELOG.md` in a marketplace, otherwise `CHANGELOG.md` at the root), add this release's section to it in the file's own format before Phase 4; the release pull request carries it.

## Phase 4: Show the Assessment and Act

Show the assessment as text — this is not a question:

```markdown
## Release Preview

**Run**: {release pull request | tag and publish | publish the existing tag}
**Version**: {tag}  {plugin and its version, in a marketplace}
**Previous**: {last_tag}
**PRs included**: {N}

**Version files**:
- bump {path} {current} → {new}
- skip {path} — {reason}

{generated changelog}
```

### `RELEASE_RUN=pr`: open the release pull request

Run the block below with `RELEASE_BRANCH`, `DEFAULT_BRANCH` and `TAG_PREFIX` from Phase 2, `VERSION` set to `NEW_VERSION`, `PLUGIN` to the plugin name and `MARKET_VERSION` to `NEW_MARKETPLACE_VERSION` (both empty outside a marketplace), `CHANGELOG_FILE` to the changelog file you edited (empty when none), and `CHANGELOG` to the generated changelog. It creates the release branch from the commit checked out (the default branch, which Phase 2 requires), writes the bump, commits only the bumped files and the changelog file, pushes the branch and opens the pull request. Nothing is pushed to the default branch.

It stops before creating anything when the release branch already exists in this clone (`PR_ERROR` names both ways forward) or when a version file it would bump has uncommitted changes of its own. When the bump, the commit or the push fails, it puts the repository back as it found it: the version files restored, the branch or commit it started on checked out again, the release branch deleted, and the changelog edit and anything staged before kept as they were (a changelog you had staged stays staged). `PR_CLEANUP` says what it did, or what it could not undo.

The pull request title (also the commit subject) is `chore(release): <plugin> <version>, marketplace <marketplace version>` in a marketplace and `chore(release): <tag>` otherwise.

```bash
# RELEASE_PR_BLOCK_BEGIN
if [ -z "${RELEASE_BRANCH:-}" ] || [ -z "${DEFAULT_BRANCH:-}" ] || [ -z "${VERSION:-}" ]; then
  printf '%s\n' "PR_STATE=blocked"
  printf '%s\n' "PR_ERROR=\"set RELEASE_BRANCH, DEFAULT_BRANCH and VERSION from Phase 2\""
  exit 1
fi
if [ -n "${PLUGIN:-}" ] && [ -n "${MARKET_VERSION:-}" ]; then
  PR_TITLE="chore(release): $PLUGIN $VERSION, marketplace $MARKET_VERSION"
elif [ -n "${PLUGIN:-}" ]; then
  PR_TITLE="chore(release): $PLUGIN $VERSION"
else
  PR_TITLE="chore(release): ${TAG_PREFIX:-v}$VERSION"
fi
VERSIONS="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-release-versions.sh"
if [ ! -x "$VERSIONS" ]; then
  printf '%s\n' "PR_STATE=blocked"
  printf '%s\n' "PR_ERROR=\"flow-release-versions.sh missing or non-executable at $VERSIONS\""
  exit 1
fi
if git rev-parse -q --verify "refs/heads/$RELEASE_BRANCH" >/dev/null; then
  printf '%s\n' "PR_STATE=blocked"
  printf '%s\n' "PR_ERROR=\"the local branch $RELEASE_BRANCH is left from an earlier run; push it and open its pull request (git push -u origin $RELEASE_BRANCH, then gh pr create --base $DEFAULT_BRANCH --head $RELEASE_BRANCH), or delete it (git branch -D $RELEASE_BRANCH), then run /flow:release again\""
  exit 1
fi
# The files the bump writes, from a plan with the same arguments. None may
# hold a change of its own: the bump commit would carry it, and a failure
# below restores these files from the last commit.
if [ -n "${PLUGIN:-}" ] && [ -n "${MARKET_VERSION:-}" ]; then
  PLAN_OUT=$("$VERSIONS" --plan --to "$VERSION" --plugin "$PLUGIN" --market-to "$MARKET_VERSION")
elif [ -n "${PLUGIN:-}" ]; then
  PLAN_OUT=$("$VERSIONS" --plan --to "$VERSION" --plugin "$PLUGIN")
else
  PLAN_OUT=$("$VERSIONS" --plan --to "$VERSION")
fi
# The script names only paths without spaces or quotes, one per line.
VERSION_PATHS=$(printf '%s\n' "$PLAN_OUT" | sed -n 's/^VERSION_FILE=bump path=\([^ ]*\) .*/\1/p' | sort -u)
DIRTY=""
while IFS= read -r _p; do
  [ -n "$_p" ] || continue
  [ -z "$(git status --porcelain -- "$_p")" ] || DIRTY="$DIRTY $_p"
done <<EOF
$VERSION_PATHS
EOF
if [ -n "$DIRTY" ]; then
  printf '%s\n' "PR_STATE=blocked"
  printf '%s\n' "PR_ERROR=\"these version files have uncommitted changes of their own:$DIRTY; commit or stash them, then run /flow:release again\""
  exit 1
fi
# What was checked out, to return to on a failure: a branch, or the commit
# of a detached HEAD.
START_BRANCH=$(git symbolic-ref -q --short HEAD)
START_COMMIT=$(git rev-parse HEAD)
if [ -n "$START_BRANCH" ]; then
  START_NAME="$START_BRANCH"
  START_SWITCH="git switch $START_BRANCH"
else
  START_NAME="the detached commit $START_COMMIT"
  START_SWITCH="git switch --detach $START_COMMIT"
fi
# The changelog's index entry before this block stages it: mode and blob,
# empty when git does not track the file. A failure puts it back, so a
# changelog the user had staged stays staged as they staged it.
CL_MODE=""
CL_BLOB=""
if [ -n "${CHANGELOG_FILE:-}" ]; then
  read -r CL_MODE CL_BLOB _cl_rest <<EOF
$(git ls-files -s -- "$CHANGELOG_FILE" | head -n 1)
EOF
fi
# _flow_undo: put the repository back as this block found it, and print
# PR_CLEANUP with what it did or could not do. The version files go back to
# the last commit (they were clean before the bump); the changelog edit and
# anything staged before this block stay as they were.
COMMITTED=0
_flow_undo() {
  _left=""
  if [ "$COMMITTED" = 1 ] && ! git reset -q --soft HEAD~1; then
    _left="$_left; the bump commit is still on $RELEASE_BRANCH"
  fi
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    git reset -q -- "$_p" >/dev/null 2>&1
    git checkout -q -- "$_p" || _left="$_left; $_p still holds the new version"
  done <<EOF
$VERSION_PATHS
EOF
  if [ -n "${CHANGELOG_FILE:-}" ]; then
    if [ -n "$CL_BLOB" ]; then
      git update-index --cacheinfo "$CL_MODE,$CL_BLOB,$CHANGELOG_FILE" \
        || _left="$_left; the staged $CHANGELOG_FILE is the release's version, not yours"
    else
      git reset -q -- "$CHANGELOG_FILE" >/dev/null 2>&1
    fi
  fi
  _back=0
  if [ -n "$START_BRANCH" ]; then
    git switch -q "$START_BRANCH" && _back=1
  else
    git switch -q --detach "$START_COMMIT" && _back=1
  fi
  if [ "$_back" = 1 ]; then
    git branch -q -D "$RELEASE_BRANCH" || _left="$_left; the local branch $RELEASE_BRANCH is still there (git branch -D $RELEASE_BRANCH)"
  else
    _left="$_left; still on $RELEASE_BRANCH ($START_SWITCH, then git branch -D $RELEASE_BRANCH)"
  fi
  if [ -z "$_left" ]; then
    printf '%s\n' "PR_CLEANUP=\"the version files are restored, $START_NAME is checked out and the local $RELEASE_BRANCH is deleted; the changelog edit and anything staged before are kept\""
  else
    printf '%s\n' "PR_CLEANUP=\"cleanup incomplete$_left\""
  fi
}
if ! git switch -q -c "$RELEASE_BRANCH"; then
  printf '%s\n' "PR_STATE=blocked"
  printf '%s\n' "PR_ERROR=\"cannot create the branch $RELEASE_BRANCH\""
  exit 1
fi
if [ -n "${PLUGIN:-}" ] && [ -n "${MARKET_VERSION:-}" ]; then
  BUMP_OUT=$("$VERSIONS" --write --to "$VERSION" --plugin "$PLUGIN" --market-to "$MARKET_VERSION"); BUMP_RC=$?
elif [ -n "${PLUGIN:-}" ]; then
  BUMP_OUT=$("$VERSIONS" --write --to "$VERSION" --plugin "$PLUGIN"); BUMP_RC=$?
else
  BUMP_OUT=$("$VERSIONS" --write --to "$VERSION"); BUMP_RC=$?
fi
printf '%s\n' "$BUMP_OUT"
if [ "$BUMP_RC" -ne 0 ] || ! printf '%s\n' "$BUMP_OUT" | grep -qx 'VERSIONS_STATE=written'; then
  # The script writes every file or none, and names any it could not put
  # back on a WRITTEN_PATH line; the undo restores them all either way.
  _flow_undo
  printf '%s\n' "PR_STATE=blocked"
  printf '%s\n' "PR_ERROR=\"the version files were not bumped; see VERSIONS_STATE\""
  exit 1
fi
COMMIT_FILES=$(printf '%s\n' "$BUMP_OUT" | sed -n 's/^VERSION_FILE=bump path=\([^ ]*\) .*/\1/p' | sort -u)
if [ -n "${CHANGELOG_FILE:-}" ]; then
  if git diff --quiet -- "$CHANGELOG_FILE" 2>/dev/null && ! git ls-files --others --exclude-standard -- "$CHANGELOG_FILE" | grep -q .; then
    printf '%s\n' "PR_WARN=\"$CHANGELOG_FILE has no change; the release pull request carries no changelog entry\""
  else
    COMMIT_FILES=$(printf '%s\n%s\n' "$COMMIT_FILES" "$CHANGELOG_FILE")
  fi
fi
# git add first: git commit's paths match only files git already knows, so a
# changelog file written for the first time would fail the commit. Paths
# given to git commit commit those files alone, whatever else is staged.
set --
ADD_OK=1
while IFS= read -r _p; do
  [ -n "$_p" ] || continue
  git add -- "$_p" || ADD_OK=0
  set -- "$@" "$_p"
done <<EOF
$COMMIT_FILES
EOF
if [ "$ADD_OK" = 1 ] && git commit -q -m "$PR_TITLE" -- "$@"; then
  COMMITTED=1
else
  _flow_undo
  printf '%s\n' "PR_STATE=blocked"
  printf '%s\n' "PR_ERROR=\"git add or git commit failed on $RELEASE_BRANCH, so nothing was committed; see the git output above\""
  exit 1
fi
if ! git push -q -u origin "$RELEASE_BRANCH"; then
  _flow_undo
  printf '%s\n' "PR_STATE=blocked"
  printf '%s\n' "PR_ERROR=\"git push of $RELEASE_BRANCH failed, so the bump commit was undone; check that origin is reachable, then run /flow:release again\""
  exit 1
fi
printf '%s\n' "PR_STATE=pushed"
printf '%s\n' "PR_TITLE=\"$PR_TITLE\""
# RELEASE_PR_BLOCK_END
gh pr create --base "$DEFAULT_BRANCH" --head "$RELEASE_BRANCH" --title "$PR_TITLE" --body "$CHANGELOG"
```

Show the pull request's URL. The release continues when it is merged: run `/flow:release` again, on the default branch, with the same arguments.

### `RELEASE_RUN=tag`: tag the merge commit and publish

The release title names the tag and, in a marketplace, the plugin and its version with a one-line summary: `v4.17.0 — flow 3.10.0: <summary>`. Outside a marketplace it is the tag.

Run the block below with `TAG`, `TAG_COMMIT` and `DEFAULT_BRANCH` from Phase 2, `TITLE` set to the release title, and `CHANGELOG` to the generated changelog. It creates an annotated tag on `TAG_COMMIT`, then pushes it and creates the GitHub release from it. The whole block is one call, and flow's tier hook, which treats the tag push as a release, asks for your confirmation before any of it runs; if you decline, nothing runs and no tag is created. If the push fails after the tag is created, the tag is in your clone only, and `TAG_ERROR` says how to push or delete it. If the release is not created after the push, run `/flow:release` again: it finds the tag on origin and creates only the release.

```bash
# RELEASE_TAG_BLOCK_BEGIN
if [ -z "${TAG:-}" ] || [ -z "${TAG_COMMIT:-}" ] || [ -z "${DEFAULT_BRANCH:-}" ]; then
  printf '%s\n' "TAG_STATE=blocked"
  printf '%s\n' "TAG_ERROR=\"set TAG, TAG_COMMIT and DEFAULT_BRANCH from Phase 2\""
  exit 1
fi
TITLE="${TITLE:-$TAG}"
if ! git cat-file -e "$TAG_COMMIT^{commit}" 2>/dev/null \
   || ! git merge-base --is-ancestor "$TAG_COMMIT" "refs/remotes/origin/$DEFAULT_BRANCH" 2>/dev/null; then
  printf '%s\n' "TAG_STATE=blocked"
  printf '%s\n' "TAG_ERROR=\"$TAG_COMMIT is not a commit on origin/$DEFAULT_BRANCH\""
  exit 1
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  printf '%s\n' "TAG_STATE=blocked"
  printf '%s\n' "TAG_ERROR=\"the tag $TAG already exists\""
  exit 1
fi
if ! git tag -a "$TAG" -m "$TITLE" "$TAG_COMMIT"; then
  printf '%s\n' "TAG_STATE=blocked"
  printf '%s\n' "TAG_ERROR=\"git tag failed\""
  exit 1
fi
printf '%s\n' "TAG_STATE=created"
# RELEASE_TAG_BLOCK_END
if ! git push origin "$TAG"; then
  printf '%s\n' "TAG_ERROR=\"git push of $TAG failed; the tag is in this clone only: push it (git push origin $TAG) or delete it (git tag -d $TAG)\""
  exit 1
fi
gh release create "$TAG" --verify-tag --title "$TITLE" --notes "$CHANGELOG" \
  || { printf '%s\n' "TAG_ERROR=\"$TAG is on origin but the GitHub release was not created; run /flow:release again to create it\""; exit 1; }
```

### `RELEASE_RUN=publish`: create the release for a tag already on origin

The tag is already on origin, so nothing is tagged or pushed. Generate the changelog from the pull requests merged between the tag before `TAG` and `TAG` (Phase 1 counted from `TAG` itself, so its list is empty), set `TITLE` as for `RELEASE_RUN=tag`, and run the block below. flow's tier hook finds the tag on origin and writes a line to flow's auto-log trail instead of asking: the tag push it confirms has already happened.

```bash
if [ -z "${TAG:-}" ]; then
  printf '%s\n' "TAG_ERROR=\"set TAG from Phase 2\""
  exit 1
fi
gh release create "$TAG" --verify-tag --title "${TITLE:-$TAG}" --notes "$CHANGELOG"
```

**FlowActivity writes** (when `FLOW_RUN_STATE=create`): invoke `Skill(run-state-management)` to record one FlowActivity per phase boundary as it completes. First run: `preflight` (`RELEASE_RUN=pr`), `bump` (version files bumped and committed on the release branch, changelog written), `release_pr` (branch pushed, pull request opened). Second run: `preflight` (`RELEASE_RUN=tag`), `tag` (annotated tag created, pushed after the tier prompt, GitHub release created). A run with `RELEASE_RUN=publish` records `preflight` and `tag` (GitHub release created for the tag already on origin). Each write advances `state.current_phase` in that order.

## Phase 5: Post-Release

On the second run:

```bash
# Verify
gh release view "$TAG"
```

**FlowRun terminal transition** (when `FLOW_RUN_STATE=create`): when the run's last phase succeeds — the release pull request opened on the first run, the release published on the second — invoke `Skill(run-state-management)` to transition the FlowRun to `state.status: completed`. If a `workflow-run` journal artifact was emitted at entry, update it to `status=completed` via a second `bin/journal-record.sh` call. If the run stopped (`STATE=blocked`, `RELEASE_RUN=waiting`, a declined prompt) or failed, transition to `state.status: cancelled` (with `blocked_reason`) instead so `/flow:resume` does not treat it as resumable.

Display the pull request or release URL and a summary that lists every version file bumped and every file skipped with its reason.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read git history / merged PRs / release pull requests / current version / tags on origin / GitHub releases | 1 | Autonomous, read-only |
| Calculate next version, plan the version-file bump | 1 | Autonomous, read-only |
| Generate changelog from PR titles | 1 | Autonomous |
| Create the release branch, write the bump and changelog, commit | 1 | Autonomous, local |
| `git push -u origin <release branch>` | 2 | Per `tiers.push` |
| `gh pr create` (the release pull request) | 2 | Per `tiers.prCreate` |
| `git tag -a <tag> <merge commit>` | 1 | Autonomous, local |
| `git push origin <tag>` | 3 | **Confirm** — the tier hook asks before it runs |
| `gh release create <tag> --verify-tag` | 3 | **Confirm** — asked with the tag push in the same call; with the tag already on origin (`RELEASE_RUN=publish`), the tier hook journals it, since the tag push it confirms has already happened |
| Post-release verification (`gh release view`) | 1 | Autonomous |

`/flow:release` is **Tier 3** for the publish path: nothing reaches the default branch except through the release pull request, and the tag push, with the GitHub release created in the same call, needs your confirmation at flow's tier hook, whatever `tiers.release` says. Creating the release for a tag already on origin is not asked again. The cost of an unwanted release (downstream consumers pulling a broken version, false notifications) is borne by people downstream, which is the Tier 3 criterion.
