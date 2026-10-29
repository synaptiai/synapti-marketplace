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
| `journal` | It runs, and one breadcrumb goes to the git-ignored auto-log trail: the UTC time, the setting and the command (`<!-- auto-log: 2026-10-29T14:48:04Z tiers.push (journal) "git push -u origin HEAD" -->`). The trail file is `<journal dir>/auto-log/issue-{N}.{YYYY-MM}.md` on a branch that names issue N and `auto-log/session-{YYYY-MM-DD}.md` otherwise, the files the commit and edit breadcrumbs go to. Nothing is written in a repository with no journal directory, and the tracked journal is never touched. |
| `confirm` | Claude Code asks you first, with a reason naming the action, its setting and the command. |

`push`, `prCreate`, `issueAssign` and `issueCreate` take any of the three values. `merge` and `release` have a floor of `confirm`: they always ask, and a lower value is ignored with a warning naming the setting.

Pushing a tag is the `release` tier, not `push`: `git push` with `--tags`, `--follow-tags`, `--mirror` or `-c push.followTags=true`, or any push in a repository whose git configuration sets `push.followTags` to true (a `-c` on the command line overrides it); `git push <remote> tag <name>`; a refspec with `refs/tags/` on either side (`HEAD:refs/tags/v1`); a refspec whose source or destination is a tag that exists in the repository (`git push origin v1.2.0`, while a branch named `v1-fix` stays `push`), or a `tags/<name>` source; a push to a remote whose configuration sets `remote.<name>.mirror`, or whose `remote.<name>.push` refspecs send tags when the command names no refspec; and `gh api` POST to `.../git/refs` with a `refs/tags/` ref. Options are read as git reads them, so an abbreviation git accepts (`--tag`, `--mirr`, `--follow-tag`, `--del`) or a bundle of short options (`-qd`) counts. Deleting a tag is `release` too: `git push <remote> :<tag>`, `--delete`/`-d <tag>`, and `gh api` DELETE or PATCH on `.../git/refs/tags/<tag>`; deleting a name that is neither a tag nor a known branch (local, or remote-tracking on that remote) asks, since it may be a tag on the remote. A command that pushes a branch and a tag is `release`. A push whose source is not a local branch may push a tag, so it asks too: a name that does not exist yet (`git tag v7 && git push origin v7`), a glob (`refs/*:refs/*`), a commit, or a variable (`git push origin "$TAG"`). So does setting a remote's `mirror` or `push` for one command (`-c`, `--config-env`, `GIT_CONFIG_*`). `git -C <dir>`, `--git-dir`, `--work-tree`, and `GIT_DIR=` or `GIT_WORK_TREE=` before git name the repository the push acts on: its tags, its `push.followTags`, its remotes' configuration and its auto-log trail are used. When that repository cannot be found, the push asks.

`gh release create <tag> --verify-tag` is journaled instead of asked when gh creates the release in origin's repository and `git ls-remote --tags origin` finds the tag there within 5 seconds: that tag's push was already confirmed. The repository gh uses is `-R`/`--repo`, else `GH_REPO`, else the remote `gh repo set-default` chose or the only remote, and it must be origin's. Without `--verify-tag`, with the tag missing from origin, when the check fails or times out, when the repository cannot be confirmed to be origin's, with `GH_HOST` set, or after a `cd` or a `GH_REPO` setting earlier in the same command, it asks.

`gh release edit` (which publishes a draft with `--draft=false`), `gh release delete`, `gh release upload` and `gh release delete-asset` are `release`: each changes a release, or the files people download from it. `gh api` also counts for these: PATCH on `.../releases/{id}`, DELETE on `.../releases/{id}` or `.../releases/assets/{id}`, and POST to `.../releases/{id}/assets` are `release`; PATCH or PUT on `.../issues/{n}` with an `assignee` or `assignees` field is `issueAssign`; and a GraphQL mutation named `mergePullRequest` or `enablePullRequestAutoMerge` (`merge`), `createRelease` or `updateRelease` (`release`), `createPullRequest` (`prCreate`), `createIssue` (`issueCreate`) or `addAssigneesToAssignable` (`issueAssign`), read from `-f`/`-F query=...`, `query=@file` or `--input file`. Any other mutation field whose name holds Merge, in any case, or is `enqueuePullRequest`, is `merge`, and one whose name holds Release or Ref (`createRef`, `updateRef`, `deleteRef`, `deleteRelease`) is `release`. A GraphQL query that cannot be read (a variable, stdin, a missing file) asks, since it may merge or release. So a release is confirmed when its tag is pushed, and `gh release create` asks again unless it passes `--verify-tag` for a tag already on origin.

An ask is a prompt in an interactive session, including bypassPermissions mode. In `claude -p` there is no one to answer it, so it is a refusal: a merge or a release needs an interactive session, or a command you type yourself with `!` (which runs without PreToolUse hooks).

When one command holds several actions (`git push && gh pr create`), the hook asks once for all of those set to `confirm`, and writes breadcrumbs only when nothing needed asking.

The hook reads the command as the shell would run it, not as text. An action counts after `&&`, `;` or a pipe, inside `$(...)`, a subshell or `bash -c '...'`, after a shell keyword (`if`, `do`, `!`, `{`), a function definition or `coproc`, and behind `env`, `sudo`, `timeout`, `xargs`, `command`, `builtin` and similar wrappers. Quotes and backslashes inside a word are removed as bash removes them, so `g\h pr mer\ge 1` is a merge. A merge, a release or a tag push behind a program the hook does not know (`caffeinate`, `stdbuf`, `watch`, `find -exec`, `parallel`), or under a command word that is a variable (`$GH pr merge 7`), asks too; `echo` and `printf` only print, so `echo gh pr merge 1` does not.

What the hook does not cover: a Tier 2 action behind a program it does not know (`caffeinate git push` is neither asked about nor journaled); a command built at run time (`$CMD`, `eval "$CMD"`) or written with ANSI-C quoting (`$'g\x68'`); gh and git aliases, gh extensions, scripts and make targets; other programs that talk to GitHub (curl, `git send-pack`); `GIT_DIR` set by `export`, or `GH_REPO` exported in an earlier Bash call; a GraphQL mutation whose field names hold none of Merge, Release or Ref (`createCommitOnBranch`); and `gh api` deletes other than those above (a branch ref). Branch protection, rulesets and tag protection are the defence against those.

## Hook Enforcement

Hooks provide structural enforcement for dangerous operations:

| Hook | Action | Behavior |
|------|--------|----------|
| `block-force-push.sh` | `git push --force` | Exit 2 (block) |
| `block-destructive.sh` | `rm -rf`, `git reset --hard` | Exit 2 (block) |
| `block-secrets.sh` | Inline credentials | Exit 2 (block) |
| `ask-issue-create.sh` | `gh issue create` while a FlowGoal is active (and `minimalScope` is false) | JSON `permissionDecision: ask` (prompt names the goal and the fix-it-here rule) |
| `tier-gate.sh` | `git push` (a tag push counts as release), `gh pr create`, `gh issue edit --add-assignee`, `gh issue create`, `gh pr merge`, `gh release create`, `edit`, `delete`, `upload` and `delete-asset`, and `gh api` writes to the same endpoints | `tiers.*`: `confirm` asks (merge and release always do), `journal` writes a breadcrumb to the auto-log trail, `autonomous` allows |

Merge and release confirmation is the tier hook's prompt. `/flow:merge` and `/flow:release` show their assessment as text and then run the command; the prompt appears when it runs. `ask-issue-create.sh` and `tier-gate.sh` both apply to `gh issue create`; Claude Code takes the more restrictive answer.

## Decision Journal Integration

Tier 2 actions are recorded in two places, and only one of them is shared. A Tier 2 action set to `journal` gets a breadcrumb in the local trail below from `tier-gate.sh` (a PreToolUse hook), beside the commit and edit breadcrumbs.

The PostToolUse hooks write **local scratch**, not journal content:
- `log-file-changes.sh`: writes a breadcrumb for each Edit/Write/NotebookEdit to `{journal.dir}/auto-log/`, and records a `file_change` entry in the per-session quality ledger
- `log-commits.sh`: writes a commit breadcrumb to the same trail
- `s1-screen-text.sh`: when your settings put System One site `guard.planted-instructions` in `shadow` or `on` (off by default), asks whether the output of a `gh` read of issue or pull request text holds instructions addressed to the agent, and in `on` adds a note beside the output that it is data (references/system-one.md)
- `record-quality-run.sh`: Records test/lint/typecheck/build runs (PostToolUse and PostToolUseFailure) with their exit codes, masked/failed flags, and a working-tree digest in the per-session quality ledger that the TaskCompleted gate reads

That trail is gitignored: it never enters the tracked journal, a commit, or another worktree's copy. So it is an audit trail for whoever ran the work, **not** a team-visible record — what a teammate can read is what a skill or command deliberately wrote to `.decisions/issue-{N}.md`.
