# Decision Journal — Issue #55

**Title:** flow: log-commits.sh PostToolUse hook leaves worktree permanently dirty (off-by-one append)
**Branch:** fix/issue-55-log-commits-loop
**Started:** 2026-05-05

## Specification

### Acceptance Criteria
1. Hook does not append to journal when last commit message contains `auto-log` or starts with `chore(decisions):`
2. Hook does not append to journal when the most recent commit only modified the journal file itself
3. Hook continues to append for normal commits (existing behavior preserved)

### Non-Goals
- Implementing a prepare-commit-msg or `git commit --amend` strategy to bundle the auto-log line with the original commit
- Restructuring how the journal file is selected (branch-name-based logic stays)
- Addressing the secondary "stale branch keeps polluting closed issue's journal" concern (separate scope)

### Failure Modes
- **jq unavailable** → exit 0 (preserved from existing graceful skip)
- **No journal file / dir** → exit 0 (preserved)
- **Guard pattern misfires on edge cases** → still exit 0; never block a commit
- **Empty git history (no HEAD)** → `git diff-tree` fails → script must still exit 0
- **Branch with no issue number** → uses session journal; same guards apply

### Interface Contract
- **Input:** JSON on stdin with `.tool_input.command` field (PostToolUse hook contract)
- **Trigger filter:** only acts on commands matching `git\s+commit`
- **Output:** none (silent on success)
- **Exit code:** always 0 (graceful degradation; never blocks tool execution)
- **Side effect:** append two lines (`""` + `<!-- auto-log: ... -->`) to journal file, OR no-op

## Stranger Test
PASS — single-task plan: apply two-guard fix to `plugins/flow/hooks/scripts/log-commits.sh`, verify by simulating hook stdin against three scenarios.

## Plan
Single atomic task — see TaskList.

<!-- auto-log: 2026-05-05 15:19 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-55.md -->

<!-- auto-log: 2026-05-05 15:19 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/log-commits.sh -->

<!-- auto-log: 2026-05-05 15:19 commit "chore: bump marketplace to 4.1.1" -->

<!-- auto-log: 2026-05-05 15:20 commit "fix(flow): prevent log-commits.sh PostToolUse infinite append loop" -->
