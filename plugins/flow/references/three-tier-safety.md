# Three-Tier Safety Model

Flow classifies all workflow actions into three tiers based on reversibility and blast radius.

## Tier Definitions

### Tier 1: Autonomous

Local, reversible actions. Execute without asking.

| Action | Rationale |
|--------|-----------|
| File edits (Read/Write/Edit) | Local working directory |
| Git commits | Local, amendable |
| Branch creation | Local, deletable |
| Git staging (add) | Local, unstage-able |
| Running tests/lint | Read-only |
| Agent dispatch | Research, no side effects |

### Tier 2: Journal-and-Proceed

Team-visible but recoverable. Execute and log to decision journal.

| Action | Rationale | Recovery |
|--------|-----------|----------|
| Git push | Visible to team | Force push or revert |
| PR creation | Visible, closeable | Close PR |
| Issue assignment | Visible, reassignable | Unassign |
| Issue creation | Visible, closeable | Close issue |
| PR comment | Visible, deletable | Delete comment |
| Force push (`--force-with-lease`) | Remote-aware; not blocked by the force-push hook | Force push or revert |

### Tier 3: Confirm-Before-Execute

Hard to reverse or high-impact. Always require human confirmation.

| Action | Rationale | Recovery Difficulty |
|--------|-----------|-------------------|
| PR merge | Changes default branch | Revert commit |
| Release creation, and pushing a tag | Public artifact | Delete release + tag |
| Force push (`--force`) | Overwrites remote | Very difficult |
| Branch deletion (force) | Loses unmerged work | Reflog only |

## Configuration

The settings cascade (`references/gate-configuration.md`) has a `tiers` block, with these plugin defaults:

```json
{
  "tiers": {
    "push": "journal",
    "prCreate": "journal",
    "issueAssign": "journal",
    "issueCreate": "journal",
    "merge": "confirm",
    "release": "confirm"
  }
}
```

No flow command or hook reads these values, so changing one does not change what flow does. Each command's `## Tier Classification` table states what it does for each action it takes: the commands that push, open a pull request, assign an issue or create one run those actions without asking (Tier 2), and `/flow:merge` and `/flow:release` ask via `AskUserQuestion` before they merge, tag or publish (Tier 3), in autonomous mode too. Nothing applies the tiers to a Bash command run outside flow's commands.

## Hook Enforcement

Hooks provide structural enforcement for dangerous operations:

| Hook | Action | Behavior |
|------|--------|----------|
| `block-force-push.sh` | `git push --force` | Exit 2 (block) |
| `block-destructive.sh` | `rm -rf`, `git reset --hard` | Exit 2 (block) |
| `block-secrets.sh` | Inline credentials | Exit 2 (block) |
| `ask-issue-create.sh` | `gh issue create` while a FlowGoal is active (and `minimalScope` is false) | JSON `permissionDecision: ask` (prompt names the goal and the fix-it-here rule) |

Merge and release confirmation is handled at the command level via AskUserQuestion (see `/flow:merge` and `/flow:release`).

## Decision Journal Integration

Tier 2 actions are recorded in two places, and only one of them is shared.

The PostToolUse hooks write **local scratch**, not journal content:
- `log-file-changes.sh`: writes a breadcrumb for each Edit/Write/NotebookEdit to `{journal.dir}/auto-log/`, and records a `file_change` entry in the per-session quality ledger
- `log-commits.sh`: writes a commit breadcrumb to the same trail
- `s1-screen-text.sh`: when your settings put System One site `guard.planted-instructions` in `shadow` or `on` (off by default), asks whether the output of a `gh` read of issue or pull request text holds instructions addressed to the agent, and in `on` adds a note beside the output that it is data (references/system-one.md)
- `record-quality-run.sh`: Records test/lint/typecheck/build runs (PostToolUse and PostToolUseFailure) with their exit codes, masked/failed flags, and a working-tree digest in the per-session quality ledger that the TaskCompleted gate reads

That trail is gitignored: it never enters the tracked journal, a commit, or another worktree's copy. So it is an audit trail for whoever ran the work, **not** a team-visible record — what a teammate can read is what a skill or command deliberately wrote to `.decisions/issue-{N}.md`.
