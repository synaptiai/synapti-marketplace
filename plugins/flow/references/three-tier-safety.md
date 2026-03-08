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
| PR comment | Visible, deletable | Delete comment |

### Tier 3: Confirm-Before-Execute

Hard to reverse or high-impact. Always require human confirmation.

| Action | Rationale | Recovery Difficulty |
|--------|-----------|-------------------|
| PR merge | Changes default branch | Revert commit |
| Release creation | Public artifact | Delete release + tag |
| Force push (`--force`) | Overwrites remote | Very difficult |
| Force push (`--force-with-lease`) | Safe remote-aware push | Tier 2 (journal) — not blocked |
| Branch deletion (force) | Loses unmerged work | Reflog only |

## Configuration

Tiers are configurable in `settings.json` under `tiers`:

```json
{
  "tiers": {
    "push": "journal",
    "prCreate": "journal",
    "issueAssign": "journal",
    "merge": "confirm",
    "release": "confirm"
  }
}
```

### Promotion Rules

Actions can be **promoted** (more restrictive) but never **demoted**:

- `autonomous` → `journal` → `confirm` (allowed)
- `confirm` → `journal` → `autonomous` (NEVER allowed)

This ensures safety is never accidentally reduced.

## Hook Enforcement

Hooks provide structural enforcement for dangerous operations:

| Hook | Action | Behavior |
|------|--------|----------|
| `block-force-push.sh` | `git push --force` | Exit 2 (block) |
| `block-destructive.sh` | `rm -rf`, `git reset --hard` | Exit 2 (block) |
| `block-secrets.sh` | Inline credentials | Exit 2 (block) |

Merge and release confirmation is handled at the command level via AskUserQuestion (see `/flow:merge` and `/flow:release`).

## Decision Journal Integration

Tier 2 actions automatically log to the decision journal via PostToolUse hooks:
- `log-file-changes.sh`: Logs Edit/Write operations
- `log-commits.sh`: Logs git commit operations

This creates an audit trail of all team-visible actions.
