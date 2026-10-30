---
name: merge-and-release
description: "Reference document describing merge prerequisites (approval, CI checks, mergeable, conversations resolved, stale approval), release versioning (semantic semver), and changelog generation. Explains why Tier 3 confirmation is structural: merge and release cost is borne by downstream people. Reference only (`disable-model-invocation: true`); consumed by `/flow:merge` and `/flow:release`."
allowed-tools: Read
agent: Explore
disable-model-invocation: true
---

# Merge and Release

Policy reference for `/flow:merge` and `/flow:release`; the runnable bash lives in `commands/merge.md` and `commands/release.md`, and the detail in `references/merge-and-release.md`.

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

**Stale approval** (compared as in `references/merge-and-release.md`): commits after approval: warn "Approval may be stale", request re-review, do not merge — the approver has not seen what would be merged.

## Stop Conditions

Any prerequisite fails, stale approval, unresolved conversations > 0, unfinished checks, or ledger gate fails: stop. No "override the gate" option exists in autonomous mode. Never `--auto`: it waits only for *required* checks (`commands/merge.md`).

## Merge Execution (Phases 2–4)

Display the Merge Assessment table as text, then confirm via `AskUserQuestion`, naming the strategy and whether the branch is deleted, and run the merge only after the user confirms. The `tier-gate.sh` hook asks again when the `gh pr merge` command runs (`tiers.merge` is always `confirm`), showing that command; the user may see two prompts for one merge. A merge cancelled at the question or declined at the prompt stops the command.

- `merge.strategy`: `squash` | `merge` | `rebase` (default `squash`)
- `merge.deleteBranch`: default `true`; named in the merge question, and `--delete-branch` is part of the command the hook's prompt shows
- `merge.markerTrust.allowedAssociations`: whose ledger markers are honored; read from the plugin tier only, never the settings cascade (`references/finding-ledger-parser.md`)

Post-merge: `gh pr view $PR_NUM --json state` must return `MERGED`; then suggest switching to the default branch and pulling.

## Release (`/flow:release`)

**Two runs.** A release reaches the default branch only through a release pull request: the first run bumps the version files and the changelog on a release branch and opens that pull request; the second, after it is merged, tags the merge commit and publishes the GitHub release.

**Version** (Phase 2): tag = `release.tagPrefix` (default `v`) + version, bumped by semver (`patch`, `minor`, `major`). In a plugin marketplace the version is the marketplace's `metadata.version`, bumped by minor for a minor or major plugin release and by patch for a patch unless a type is named. `bin/flow-release-versions.sh --plan` lists the version files to bump and the files it skips; files that disagree on the current version stop the release. No version file and no prior tag: first release is `v1.0.0`.

**Changelog** (Phase 3) and **Execute** (Phase 4): show the Release Preview as text. The first run commits only the bumped files and the changelog and pushes nothing to the default branch, and asks no question. The second run confirms via `AskUserQuestion` before it tags, pushes the tag and creates the GitHub release, and before it creates the release for a tag already on origin; flow's tier hook asks again when the tag push or the release command runs.

**Post-release** (Phase 5, second run): `gh release view "$TAG"` must succeed; the summary lists every version file bumped and every file skipped.
