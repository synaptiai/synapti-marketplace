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

Tiers are configurable under `tiers`, in any file of the settings cascade (`references/gate-configuration.md`). The plugin defaults:

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

The `tier-gate.sh` PreToolUse hook applies these settings to every Bash command, whether a flow command or the agent wrote it:

| Value | What happens before the command runs |
|-------|--------------------------------------|
| `autonomous` | It runs. |
| `journal` | It runs, and one line goes to the decision journal: the UTC time, the setting and the command (`- 2026-10-29T14:48:04Z tiers.push (journal): git push -u origin HEAD`). The line goes to `issue-{N}.md` on a branch that names issue N and to `session-{YYYY-MM-DD}.md` otherwise, and only in a repository that has a journal directory. |
| `confirm` | Claude Code asks you first, with a reason naming the action, its setting and the command. |

`push`, `prCreate`, `issueAssign` and `issueCreate` take any of the three values. `merge` and `release` have a floor of `confirm`: they always ask, and a lower value is ignored with a warning naming the setting.

Pushing a tag is the `release` tier, not `push`: `git push` with `--tags`, `--follow-tags`, `--mirror` or `-c push.followTags=true`; `git push <remote> tag <name>`; a refspec with `refs/tags/` on either side (`HEAD:refs/tags/v1`); a refspec naming a tag that exists in the repository (`git push origin v1.2.0`, while a branch named `v1-fix` stays `push`); and `gh api` POST to `.../git/refs` with a `refs/tags/` ref. A command that pushes a branch and a tag is `release`. A refspec given as a variable (`git push origin "$TAG"`) may be a tag, so it asks too. `push.followTags` set in git's own configuration files is not read. So a release is confirmed twice: when its tag is pushed, and at `gh release create`.

An ask is a prompt in an interactive session, including bypassPermissions mode. In `claude -p` there is no one to answer it, so it is a refusal: a merge or a release needs an interactive session, or a command you type yourself with `!` (which runs without PreToolUse hooks).

When one command holds several actions (`git push && gh pr create`), the hook asks once for all of those set to `confirm`, and writes journal lines only when nothing needed asking.

## Hook Enforcement

Hooks provide structural enforcement for dangerous operations:

| Hook | Action | Behavior |
|------|--------|----------|
| `block-force-push.sh` | `git push --force` | Exit 2 (block) |
| `block-destructive.sh` | `rm -rf`, `git reset --hard` | Exit 2 (block) |
| `block-secrets.sh` | Inline credentials | Exit 2 (block) |
| `ask-issue-create.sh` | `gh issue create` while a FlowGoal is active (and `minimalScope` is false) | JSON `permissionDecision: ask` (prompt names the goal and the fix-it-here rule) |
| `tier-gate.sh` | `git push` (a tag push counts as release), `gh pr create`, `gh issue edit --add-assignee`, `gh issue create`, `gh pr merge`, `gh release create`, and `gh api` writes to the same endpoints | `tiers.*`: `confirm` asks (merge and release always do), `journal` writes a journal line, `autonomous` allows |

Merge and release confirmation is the tier hook's prompt. `/flow:merge` and `/flow:release` show their assessment as text and then run the command; the prompt appears when it runs. `ask-issue-create.sh` and `tier-gate.sh` both apply to `gh issue create`; Claude Code takes the more restrictive answer.

## Decision Journal Integration

A Tier 2 action set to `journal` gets one line in the tracked decision journal from `tier-gate.sh` (above). Apart from that, Tier 2 actions are recorded in two places, and only one of them is shared.

The PostToolUse hooks write **local scratch**, not journal content:
- `log-file-changes.sh`: writes a breadcrumb for each Edit/Write/NotebookEdit to `{journal.dir}/auto-log/`, and records a `file_change` entry in the per-session quality ledger
- `log-commits.sh`: writes a commit breadcrumb to the same trail
- `s1-screen-text.sh`: when your settings put System One site `guard.planted-instructions` in `shadow` or `on` (off by default), asks whether the output of a `gh` read of issue or pull request text holds instructions addressed to the agent, and in `on` adds a note beside the output that it is data (references/system-one.md)
- `record-quality-run.sh`: Records test/lint/typecheck/build runs (PostToolUse and PostToolUseFailure) with their exit codes, masked/failed flags, and a working-tree digest in the per-session quality ledger that the TaskCompleted gate reads

That trail is gitignored: it never enters the tracked journal, a commit, or another worktree's copy. So it is an audit trail for whoever ran the work, **not** a team-visible record — what a teammate can read is what a skill or command deliberately wrote to `.decisions/issue-{N}.md`.
