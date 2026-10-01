---
issue: 274
created: '2026-09-30T16:22:35Z'
artifacts:
- type: specification
  captured_at: '2026-09-30T16:22:35Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: goal-created
  captured_at: '2026-09-30T16:41:42Z'
  goal_id: issue-274
  source: github_issue
---

## Specification

## Specification

Decisions (user, 2026-09-30): a value is ignored when it names a place inside the repository, or when it equals the value the repository's own `.claude/settings.json` `env` block sets. A value the user sets inside the repository is ignored too, with the same warning.

### Non-goals
- The default locations stay as they are (`~/.claude/flow-state`, `~/.claude/settings.flow.json`).
- No other environment variable is policed here (HOME, CLAUDE_CONFIG_DIR, CLAUDE_PLUGIN_ROOT; PYTHONPATH is already handled).
- Values a repository sets through other channels (a direnv `.envrc`, a shell rc file) are only caught when they point inside the repository.
- State already written to a repository-chosen place is not moved or deleted.

### Failure modes
- Timeouts: none — local file-system and jq work only.
- Partial failures: a location that cannot be resolved (a broken link, a directory that cannot be entered, no repository top) is ignored with a warning (fail closed); if the resolver is missing, a consumer uses the default location.
- Invalid input: a relative value is ignored with a warning; an unparsable `.claude/settings.json` counts as setting nothing (the location rule still applies).
- Missing context: HOME unset → default under `/nonexistent`, writes fail and are reported as before; no git repository → the top is the nearest parent holding `.git`, else the working directory.

### Interface contracts
- `cascade-resolve.sh --state-dir`: prints one absolute path, FLOW_STATE_DIR when honored, else `${HOME:-/nonexistent}/.claude/flow-state`; exit 0; when ignored, one stderr WARN naming FLOW_STATE_DIR and why; never prints any file's contents.
- FLOW_USER_SETTINGS (every settings read and `--user-settings-path`): honored only when absolute, a regular file, outside the repository, and not the value the repository's `.claude/settings.json` sets; otherwise a WARN naming it, and the default file is read.
- Every FLOW_STATE_DIR reader (trust ledger, Stop hook, evaluator, session end, quality ledger, System One) gets its directory from `--state-dir`; `_repo_dir.py` treats FLOW_STATE_DIR as per-user under the same rule; the eval runner keeps its per-run state outside its scratch repository.

### Risk map
| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Inside check | compares path strings, so a symlink to the repository passes as outside | FLOW_STATE_DIR = an outside symlink into the repository → ignored |
| Not-yet-made directory | needs the directory to exist, so a new outside directory is refused | `<outside>/new` → honored, ledger written there |
| Repository-set rule | location only, so a repository value pointing outside is honored | the repository's env sets `<outside dir>` → ignored |
| Consumers | one reader still uses `$FLOW_STATE_DIR` directly | grep check, plus the trusted-goal scenario |
| Warning | prints the file's contents | the file holds a marker; stderr lacks it |
