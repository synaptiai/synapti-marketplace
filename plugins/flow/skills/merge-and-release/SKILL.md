---
name: merge-and-release
description: "Reference for the merge and release policy: prerequisite checklist (approval, checks, mergeable, conversations, stale approval), Tier 3 confirmation requirement, semantic versioning rules, and changelog generation. Use to understand why merges and releases are non-autonomous."
allowed-tools: Read
context: fork
agent: Explore
disable-model-invocation: true
---

# Merge and Release

Reference document for merge and release policy. The executable bash lives in `plugins/flow/commands/merge.md` and `plugins/flow/commands/release.md`. This skill describes **what those commands enforce and why**.

Both merge and release are **Tier 3** — they always require explicit human confirmation, even in autonomous mode. This is non-negotiable.

## Iron Law

**MERGE IS IRREVERSIBLE IN PRACTICE. Treat every merge as permanent. Every prerequisite must be verified with fresh evidence, not memory.**

Reverting a merge is technically possible in git but disruptive in practice — downstream branches rebase off the merge, deploys propagate it, and history grows confusing. Prevention is the only reliable strategy. The Tier 3 confirmation requirement is the structural expression of that fact.

## Merge Prerequisites — The Five-Check Gate

Before a merge proceeds, all five checks must pass. The runnable verification is in `plugins/flow/commands/merge.md` Phase 1.

| # | Check | Requirement | What it protects against |
|---|-------|-------------|--------------------------|
| 1 | Approval | At least one approval, no outstanding requested changes | Merging code that no human has signed off on |
| 2 | CI Checks | All status checks pass (`statusCheckRollup` all success) | Merging code that fails the project's automated tests |
| 3 | Mergeable | No merge conflicts (`mergeable == "MERGEABLE"`) | Merging a PR whose content cannot cleanly land on the base branch |
| 4 | Conversations | All review threads resolved (unresolved count == 0) | Closing reviewer concerns by ignoring them |
| 5 | Stale approval | No commits after the last approval timestamp | Merging code that was approved before the latest changes existed |

The conversation-resolution check requires GitHub's GraphQL API (the REST `reviewThreads` field is incomplete). The exact GraphQL query used is in `plugins/flow/commands/merge.md`.

## Stop Conditions — Non-Negotiable

When any of these conditions is detected, the command **stops without asking "merge anyway?"**:

- ANY of the five prerequisites fails
- Stale approval detected — request re-review, do not merge
- Unresolved conversations > 0 — resolve first, do not merge
- Finding-ledger check fails (see `pr-lifecycle` skill for details)

There is no "override the gate" option in autonomous mode. Overrides require the human user to take the action themselves outside the command.

## Stale Approval Detection

A "stale" approval is one that predates the most recent commit on the PR. The check compares:

- The latest `submittedAt` timestamp among reviews where `state == "APPROVED"`
- The `committedDate` of the most recent commit on the PR

If commits exist after the last approval, the command warns: "Approval may be stale." Stale approvals are a stop condition because the approver has not actually seen what is being merged.

## Merge Execution

After all prerequisites pass, the command displays a **Merge Assessment** table and explicitly asks the user to confirm. Only after a clear "yes" does the merge proceed:

- Strategy is read from settings (`squash` | `merge` | `rebase`, default `squash`)
- Branch deletion is read from settings (default `true`)
- The `gh pr merge` invocation is in `plugins/flow/commands/merge.md` Phase 3

The user-visible assessment lists every prerequisite's status, the chosen strategy, and the branch-delete decision so the human can verify before approving.

## Release Process

Releases follow the same Tier 3 confirmation discipline as merges. The runnable bash is in `plugins/flow/commands/release.md`.

### Version Calculation

| Bump type | Format | When to use |
|-----------|--------|-------------|
| `patch` | 0.0.X+1 | Bug fixes only, no behavior change |
| `minor` | 0.X+1.0 | New features, no breaking changes |
| `major` | X+1.0.0 | Breaking changes |

The first release defaults to `v1.0.0` if no prior tag exists.

### Changelog Generation

The changelog is built from merged PRs since the last release tag, categorized by conventional commit prefix:

- **Features** — `feat:` PRs
- **Bug Fixes** — `fix:` PRs
- **Other Changes** — `docs:`, `chore:`, etc.

Each entry includes the PR number and author. A "Full Changelog" link compares the previous tag to the new one.

### Release Execution

After the changelog and version are displayed, the command asks the user to confirm. Only after explicit confirmation:

1. Create annotated tag: `git tag -a "$TAG" -m "Release $TAG"`
2. Push tag: `git push origin "$TAG"`
3. Create GitHub release: `gh release create "$TAG" --title "$TAG" --notes "$CHANGELOG"`

These three operations together are the release. They are not split across multiple agent turns — the user confirms once and the command performs them in sequence.

## Post-Merge / Post-Release

After either operation completes, the command verifies state:

- Merge: `gh pr view $PR_NUM --json state` should return `MERGED`
- Release: `gh release view $TAG` should succeed

The command then suggests cleanup: switch to the default branch, pull latest, and (for releases) update plugin version files if applicable.

## Why Tier 3 Is Structural, Not Optional

Merges and releases produce visible, durable artifacts: a merge commit on `main`, a published tag, a GitHub release page that subscribers may receive notifications for. The cost of an unwanted merge or release is paid by everyone downstream — other developers rebasing, users seeing a notification for a release that was a mistake, package managers fetching the new version.

Tier 3 is not gatekeeping for its own sake. It is the structural expression of: **the cost of an unwanted action is borne by people who are not in this conversation.** The human in the loop is the only person who can speak for those downstream people.

## Where the Bash Lives

This skill is reference-only. The runnable implementations are:

- **Merge prerequisites + execution**: `plugins/flow/commands/merge.md`
- **Release version calculation + tagging + GitHub release creation**: `plugins/flow/commands/release.md`

When the policy needs to evolve — a new prerequisite, a new release strategy, a different versioning scheme — update the command and update this reference together. The bash is the runtime; this document is the rationale.
