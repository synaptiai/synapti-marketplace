---
issue: 239
created: '2026-09-19T19:25:00Z'
artifacts:
- type: specification
  captured_at: '2026-09-19T19:21:58Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: stranger-test
  captured_at: '2026-09-19T19:21:58Z'
  result: PASS
  task_count: 3
- type: workflow-run
  captured_at: '2026-09-19T19:22:09Z'
  workflow: start-issue
  run_id: 2026-09-19T192103Z-issue-239
  status: active
---

# Issue 239 — the force-push guard reads the whole shell line

## Specification

_Captured by specification-capture skill on 2026-09-19. Source: extracted-from-issue._

### Non-goals

- Not a change of policy. `--force` and `-f` on a push stay blocked; `--force-with-lease` alone stays allowed. Only *which text* the guard examines changes.
- Not a shell parser. The guard decides on the push invocation's own arguments; it does not model expansion, aliases, functions or `eval`.
- Not a change to any other hook. `block-destructive.sh` keeps its own force-delete and force-create rules, and `block-secrets.sh` is untouched.
- Not a relaxation. Every command the guard blocks today because a push really carries a force flag stays blocked.

### Failure modes

- **Timeouts** — none. The hook reads stdin, decides, and exits; it makes no network or subprocess call beyond `jq` and POSIX text tools.
- **Partial failures** — `jq` missing still fails closed, unchanged: the hook blocks rather than allowing an uninspected command.
- **Invalid input** — an unbalanced quote, a heredoc, a multi-line command or a NUL-free but malformed line must not crash the hook. A crash is not a block: `set -euo pipefail` with a failing `grep` exits non-zero, and the harness reads a non-2 exit as an allow, so any parse path that can error must be written so it cannot.
- **Missing context** — the hook consults no git state and no repository, so an unusual working directory changes nothing.

### Interface contracts

- Hook protocol: reads `{"tool_input":{"command":"..."}}` as JSON on stdin; exit 0 allows, exit 2 blocks with the message on stderr.
- The block message keeps its three lines verbatim: the operator reads them, and the third names `--force-with-lease` as the safe alternative.
- `git push --force`, `git push -f`, `cmd && git push --force`, `{ git push --force; }` → blocked.
- `git push --force-with-lease` → allowed. `git push --force-with-lease --force` → blocked.
- Any `-f` or `--force` belonging to another command on the same line → allowed.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| splitting the line into commands | splits on `;`, `&&`, `\|` without respecting quotes, so a separator inside a quoted string yields a segment that looks like a push | `grep -q 'x ; git push --force' file` → right: allowed (no push is invoked); wrong: blocked |
| where a push's own arguments end | reads the rest of the segment, so a flag belonging to a later command inside the same segment counts | `git push origin main && true` with a trailing comment carrying `-f` → right: allowed; wrong: blocked |
| the `-f` word boundary | matches `-f` inside a longer word (`-force`, `--force-with-lease`) | `git push --force-with-lease` → right: allowed; wrong: blocked |
| a heredoc body | scans the whole command string, including text being written to a file | a command that writes `git push --force` into a file → right: allowed; wrong: blocked |
| `-f` as another command's flag | treats any `-f` after `git push` on the line as the push's own | `git status && pgrep -f x` → right: allowed (the reported case); wrong: blocked |

## Stranger Test

PASS — 3 tasks reviewed.

<!-- auto-log: 2026-09-19 21:21 Write /Users/danielbentes/synapti-marketplace/.flow/goals/issue-239.goal.yaml -->

<!-- auto-log: 2026-09-19 21:21 Edit /Users/danielbentes/synapti-marketplace/.flow/goals/issue-239.goal.yaml -->

<!-- auto-log: 2026-09-19 21:22 Write /Users/danielbentes/synapti-marketplace/plugins/flow/tests/block-force-push.test.sh -->

<!-- auto-log: 2026-09-19 21:22 Write /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 21:23 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/block-force-push.test.sh -->

<!-- auto-log: 2026-09-19 21:23 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/block-force-push.test.sh -->

<!-- auto-log: 2026-09-19 21:24 Write /tmp/msg239-synapti-forcepush.txt -->

<!-- auto-log: 2026-09-19 21:24 commit "fix(flow): the force-push guard decides on the push's own arguments" -->

<!-- auto-log: 2026-09-19 21:24 Write /tmp/probe239-synapti-cases.txt -->

<!-- auto-log: 2026-09-19 21:25 Write /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 21:25 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/block-force-push.test.sh -->

<!-- auto-log: 2026-09-19 21:25 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/block-force-push.test.sh -->

<!-- auto-log: 2026-09-19 21:26 Write /tmp/msg239-synapti-v2.txt -->
