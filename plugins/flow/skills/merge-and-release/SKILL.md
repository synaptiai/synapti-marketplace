---
name: merge-and-release
description: "Reference document describing merge prerequisites (approval, CI checks, mergeable, conversations resolved, stale approval), release versioning (semantic semver), and changelog generation. Explains why Tier 3 confirmation is structural: merge and release cost is borne by downstream people. Reference only (`disable-model-invocation: true`); consumed by `/flow:merge` and `/flow:release`."
allowed-tools: Read
agent: Explore
disable-model-invocation: true
---

# Merge and Release

Policy reference for `/flow:merge` and `/flow:release`; the runnable bash lives in `commands/merge.md` and `commands/release.md`.

## Contract

Iron law: **merge is irreversible in practice — every prerequisite is verified with fresh evidence, never memory, and merge and release are Tier 3 (explicit human confirmation, even in autonomous mode).** Consumed by `/flow:merge` Phase 1 (five-check gate plus finding-ledger check), Phase 2 (Merge Assessment), Phase 3 (confirm and execute), Phase 4 (post-merge), and by `/flow:release` Phases 2–5 (version and version files, changelog, assessment and publish, post-release). Returns the checks, stop conditions, settings, and execution sequence those commands apply. Permitted skips: none — a failed prerequisite stops the command without asking "merge anyway?"; an override happens only by the human acting outside the command.

## Five-Check Gate (`/flow:merge` Phase 1)

| # | Check | Requirement |
|---|-------|-------------|
| 1 | Approval | At least one approval, no outstanding requested changes |
| 2 | CI checks | `statusCheckRollup` all success |
| 3 | Mergeable | `mergeable == "MERGEABLE"` |
| 4 | Conversations | Unresolved review threads == 0 (GraphQL `reviewThreads`; the REST field is incomplete) |
| 5 | Stale approval | No commits after the last approval timestamp |

Plus the `pr-lifecycle` finding-ledger check: non-empty `ESCALATED` or unmatched `FINDINGS` blocks.

**Stale approval**: compare the latest `submittedAt` among reviews with `state == "APPROVED"` against the `committedDate` of the newest commit. Commits after approval: warn "Approval may be stale", request re-review, do not merge — the approver has not seen what would be merged.

## Stop Conditions

Any prerequisite fails, stale approval, unresolved conversations > 0, unfinished checks, or ledger gate fails: stop. No "override the gate" option exists in autonomous mode. Never `--auto`: it waits only for *required* checks (`commands/merge.md`).

## Merge Execution (Phases 2–4)

Display the Merge Assessment table (each prerequisite's status, strategy, branch-delete decision) as text, then run the merge. The confirmation is the `tier-gate.sh` hook's permission prompt on the `gh pr merge` command (`tiers.merge` is always `confirm`), which shows that command; do not ask a separate yes/no question first. A merge declined at the prompt stops the command.

- `merge.strategy`: `squash` | `merge` | `rebase` (default `squash`)
- `merge.deleteBranch`: default `true`; `--delete-branch` is part of the command the prompt shows
- `merge.markerTrust.allowedAssociations`: default `["OWNER","MEMBER","COLLABORATOR"]`; filters whose ledger markers are honored, pinned to the plugin tier rather than the settings cascade (`references/finding-ledger-parser.md`)

Post-merge: `gh pr view $PR_NUM --json state` must return `MERGED`; then suggest switching to the default branch and pulling.

## Release (`/flow:release`)

**Two runs.** A release reaches the default branch only through a release pull request. The first run bumps the version files and the changelog on a release branch (`conventions.branchPatterns.release`, default `chore/release-{version}`) and opens that pull request; the second run, after it is merged, tags the merge commit and publishes the GitHub release. Phase 2 tells the runs apart from the repository's state: whether the current version is tagged, and whether a release pull request for the version is open or merged.

**Version** (Phase 2): tag = `release.tagPrefix` (default `v`) + version; in a plugin marketplace the version is the marketplace's `metadata.version`, bumped by minor for a minor or major plugin release and by patch for a patch unless a type is named. `bin/flow-release-versions.sh --plan` lists the version files to bump (`package.json`, `pyproject.toml`, `Cargo.toml`, `.claude-plugin/plugin.json`, or a named plugin's `plugin.json`, its `marketplace.json` entry and the marketplace's `metadata.version`) and the files it skips with the reason; files that disagree on the current version stop the release.

| Bump | Format | When |
|------|--------|------|
| `patch` | 0.0.X+1 | Bug fixes only, no behavior change |
| `minor` | 0.X+1.0 | New features, no breaking changes |
| `major` | X+1.0.0 | Breaking changes |

No version file and no prior tag: first release is `v1.0.0`.

**Changelog** (Phase 3): merged PRs since the last tag, grouped by conventional prefix — Features (`feat:`), Bug Fixes (`fix:`), Other Changes (`docs:`, `chore:`, …) — each with PR number and author, plus a "Full Changelog" compare link `{prev}...{new}`.

**Execute** (Phase 4): show the Release Preview (version, previous tag, PR count, version files, changelog) as text. First run: create the release branch, commit only the bumped files and the changelog, push the branch and open the release pull request (`chore(release): <plugin> <version>, marketplace <version>` in a marketplace, `chore(release): <tag>` otherwise); nothing is pushed to the default branch. Second run: `git tag -a` on the merge commit, `git push origin <tag>`, then `gh release create <tag> --verify-tag`; flow's tier hook asks for confirmation before the tag is pushed. The runnable sequence is in `commands/release.md`.

**Post-release** (Phase 5, second run): `gh release view "$TAG"` must succeed; the summary lists every version file bumped and every file skipped.

## Why Tier 3 Is Structural

An unwanted merge or release is paid for by people outside this conversation; only the human in the loop can speak for them.

## Keeping Policy and Bash Aligned

Merge prerequisites and execution: `commands/merge.md`. Version, tagging, GitHub release: `commands/release.md`. A new prerequisite, strategy, or versioning rule changes the command and this reference together.
