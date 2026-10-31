# Merge and Release Detail

Detail for `skills/merge-and-release/SKILL.md`, the policy `/flow:merge` and `/flow:release` apply. The runnable bash is in `commands/merge.md` and `commands/release.md`.

## Stale approval

Compare the latest `submittedAt` among reviews with `state == "APPROVED"` against the `committedDate` of the newest commit; a later commit makes the approval stale.

## Merge Assessment

The table `/flow:merge` shows before it merges: each prerequisite's status, the strategy, and whether the branch is deleted.

## Which run this is

Phase 2 tells the two runs apart from the repository's state: whether the current version is tagged, and whether a release pull request for the version is open or merged.

## Version files

`bin/flow-release-versions.sh --plan` lists the version files to bump and the files it skips, each with the reason. It recognises `package.json`, `pyproject.toml`, `Cargo.toml` and `.claude-plugin/plugin.json` at the repository root, and, for a named plugin in a marketplace, that plugin's `plugin.json`, its entry in `.claude-plugin/marketplace.json` and the marketplace's `metadata.version`.

## Version bump

| Bump | Format | When |
|------|--------|------|
| `patch` | 0.0.X+1 | Bug fixes only, no behavior change |
| `minor` | 0.X+1.0 | New features, no breaking changes |
| `major` | X+1.0.0 | Breaking changes |

## Changelog

Merged pull requests since the last tag, grouped by conventional prefix — Features (`feat:`), Bug Fixes (`fix:`), Other Changes (`docs:`, `chore:`, …) — each with its number and author, then a "Full Changelog" compare link `{prev}...{new}`.

## Release execution

The release branch is named by `conventions.branchPatterns.release`, default `chore/release-{version}`.

The Release Preview, shown as text, lists the version, the previous tag, the pull request count, the version files and the changelog.

- **First run**: create the release branch, commit only the bumped files and the changelog, push the branch and open the release pull request, titled `chore(release): <plugin> <version>, marketplace <version>` in a marketplace and `chore(release): <tag>` otherwise. Nothing is pushed to the default branch.
- **Second run**: `git tag -a` on the merge commit, `git push origin <tag>`, then `gh release create <tag> --verify-tag`. `/flow:release` confirms via `AskUserQuestion` before this step, and again before it creates the release for a tag already on origin. The tag push and the release run as one command, and flow's tier hook asks again before it runs.

## Why Tier 3 is structural

An unwanted merge or release is paid for by people outside this conversation; only the human in the loop can speak for them.

## Keeping policy and bash aligned

Merge prerequisites and execution: `commands/merge.md`. Version, tagging, GitHub release: `commands/release.md`. A new prerequisite, strategy, or versioning rule changes the command, the skill and this reference together.
