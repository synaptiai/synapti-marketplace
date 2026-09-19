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
- type: evidence-captured
  captured_at: '2026-09-19T21:14:12Z'
  evidence_id: evidence-ac1-5-guard-suite-turn2
  goal_id: issue-239
  proves:
  - AC1
  - AC2
  - AC3
  - AC4
  - AC5
- type: evidence-captured
  captured_at: '2026-09-19T21:42:47Z'
  evidence_id: evidence-ac1-5-guard-suite-turn3
  goal_id: issue-239
  proves:
  - AC1
  - AC2
  - AC3
  - AC4
  - AC5
---

# Issue 239 — the force-push guard reads the whole shell line

## Specification

_Captured by specification-capture skill on 2026-09-19. Source: extracted-from-issue._

### Non-goals

- Not a change of policy. `--force` and `-f` on a push stay blocked; `--force-with-lease` alone stays allowed. What changes is which text the guard examines.
- Not a shell parser, and not a list of wrappers. The guard names only the commands that *cannot* execute their arguments; every other command word is treated as one that might, so a wrapper nobody enumerated blocks rather than allows. That makes the list of gaps safe instead of dangerous, at the cost of refusing a text command it has not been taught.
- Not a decoder for expansions the guard cannot read. ANSI-C quoting and brace expansion are not decoded, so a line carrying one blocks rather than being guessed at.
- Not a change to any other hook. `block-destructive.sh` keeps its own rules. `block-secrets.sh` shares this defect class and is untouched here, filed as #241.

### Failure modes

- **Timeouts** — the scan is per-character, so its cost grows faster than the input. A command over `MAX_BYTES` (131072, counted in bytes because awk walks bytes and a multi-byte command costs more than its character count suggests) is refused rather than truncated: truncating and scanning the head would drop whatever the tail contained, and a dropped tail is the direction that lets a force-push through. Measured: 100 KB about 0.7 s, 131 KB about 1.0 s, 131072 CJK characters refuse in 73 ms, and a long chain of `eval` words — 18 s before this design — now takes about 1.1 s.
- **Partial failures** — every tool the decision passes through is required, and a missing one blocks: `jq` parses the payload, `awk` decides, `cat` reads stdin, `grep` computes the floor. A missing binary would otherwise exit 127, which the harness reads as an allow.
- **Invalid input** — anything that exits non-zero, or yields an empty or unexpected verdict, is converted into a refusal: a crash is not a block, and the harness reads a non-2 exit as permission. Input that ends mid-construct — an unclosed quote, a heredoc with no terminator — blocks, and a payload carrying no command *string* blocks rather than being read as an empty, and therefore allowed, command. A 3000-input fuzz sample produced only exits 0 and 2.
- **Missing context** — the hook consults no git state and no repository, so an unusual working directory changes nothing.

### Interface contracts

- Hook protocol: reads `{"tool_input":{"command":"..."}}` as JSON on stdin; exit 0 allows, exit 2 blocks with the message on stderr.
- The block message keeps its three lines verbatim: the operator reads them, and the third names `--force-with-lease` as the safe alternative.
- `git push --force`, `git push -f`, `cmd && git push --force`, `{ git push --force; }` -> blocked.
- `git push --force-with-lease` -> allowed. `git push --force-with-lease --force` -> blocked.
- Any `-f` or `--force` belonging to another command on the same line -> allowed, whichever command that is, as long as the command cannot execute its arguments.
- A force flag reaching git through *any* other command — a wrapper, a path, a shell's `-c` payload, `eval` — -> blocked, whether or not the guard names that command.
- A substitution anywhere on a line that also carries a push and a force flag -> blocked.
- A command over `MAX_BYTES`, one that ends mid-construct, or one whose payload carries no command string -> blocked.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| splitting the line into commands | splits on separators without respecting quotes, so a separator inside a quoted string yields a segment that looks like a push | `grep -q 'x ; git push --force' file` -> right: allowed (no push is invoked); wrong: blocked |
| where a push own arguments end | reads the rest of the segment, so a flag belonging to a later command counts | `git push origin main && pgrep -f x` -> right: allowed (the reported case); wrong: blocked |
| the `-f` word boundary | matches `-f` inside a longer word | `git push --force-with-lease` -> right: allowed; wrong: blocked |
| a heredoc body | treats every body as text, so a shell fed the body runs the push unexamined | `cat > f <<EOF` writing the flags -> right: allowed; `bash <<EOF` with a push inside -> right: blocked |
| `-f` as another command flag | treats any `-f` after a push on the line as the push own | `git status && pgrep -f x` -> right: allowed (the reported case); wrong: blocked |
| which commands can execute their arguments | treats an unknown command word as harmless, so a wrapper hides the push | `caffeinate git push --force`, `timeout 10 git push --force` -> right: blocked; wrong: allowed |
| a substitution inside double quotes | treats a quoted string as always text, so a substitution in one reads as an echo | `echo "$(git push --force)"` -> right: blocked; wrong: allowed |
| a force flag inside a quoted span | word-splits only, so a flag grouped into one quoted word is never seen | `gh issue create --body 'git push --force'` -> right: allowed, and `git push '--force'` -> right: blocked |
| detecting the floor | computes it against the command as read rather than as the shell would, so a construct hides the push from it | `echo $((1<<2))` then a push then `2` -> right: blocked; wrong: allowed |
| the exit contract | lets a failed scan fall through to the shell own status, which is not 2 | a stubbed `awk` exiting 1 while the command force-pushes -> right: blocked; wrong: allowed |

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

<!-- auto-log: 2026-09-19 21:30 Write /tmp/probe239-synapti-crash.sh -->

<!-- auto-log: 2026-09-19 21:31 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/block-force-push.test.sh -->

<!-- auto-log: 2026-09-19 21:31 commit "test(flow): pin the force-push guard's two documented exits" -->

<!-- auto-log: 2026-09-19 21:32 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-239-evidence.md -->

<!-- auto-log: 2026-09-19 21:33 Write /tmp/mutate239-synapti.sh -->

<!-- auto-log: 2026-09-19 21:34 Write /tmp/mutate239b-synapti.sh -->

<!-- auto-log: 2026-09-19 21:35 Write /tmp/mut239-synapti.py -->

<!-- auto-log: 2026-09-19 21:35 Write /tmp/mut239-run-synapti.sh -->

<!-- auto-log: 2026-09-19 21:36 Edit /tmp/mut239-synapti.py -->

<!-- auto-log: 2026-09-19 21:37 Edit /tmp/mut239-synapti.py -->

<!-- auto-log: 2026-09-19 21:37 Edit /tmp/mut239-run-synapti.sh -->

<!-- auto-log: 2026-09-19 21:37 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-239-evidence.md -->

<!-- auto-log: 2026-09-19 21:37 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-239-evidence.md -->

<!-- auto-log: 2026-09-19 21:38 Write /tmp/xcheck239-synapti.py -->

<!-- auto-log: 2026-09-19 21:38 Write /tmp/xcheck239-synapti.py -->

<!-- auto-log: 2026-09-19 21:39 Write /tmp/secrets-probe-synapti.sh -->

<!-- auto-log: 2026-09-19 22:05 Write /tmp/f1-probe-synapti.sh -->

<!-- auto-log: 2026-09-19 22:06 Write /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 22:06 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 22:06 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 22:06 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 22:07 Write /Users/danielbentes/synapti-marketplace/plugins/flow/tests/block-force-push.test.sh -->

<!-- auto-log: 2026-09-19 22:07 Write /tmp/verify239-synapti.sh -->

<!-- auto-log: 2026-09-19 22:07 Write /tmp/perf239-synapti.sh -->

<!-- auto-log: 2026-09-19 22:08 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 22:09 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 22:09 Write /tmp/mut239-synapti.py -->

<!-- auto-log: 2026-09-19 22:09 Write /tmp/mut239-run-synapti.sh -->

<!-- auto-log: 2026-09-19 22:10 Write /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 22:10 Edit /tmp/mut239-run-synapti.sh -->

<!-- auto-log: 2026-09-19 22:10 Write /tmp/mut239-run-synapti.sh -->

<!-- auto-log: 2026-09-19 22:10 Write /tmp/e-probe-synapti.sh -->

<!-- auto-log: 2026-09-19 22:11 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/block-force-push.test.sh -->

<!-- auto-log: 2026-09-19 22:11 Write /tmp/fuzz239-synapti.py -->

<!-- auto-log: 2026-09-19 22:12 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-239.md -->

<!-- auto-log: 2026-09-19 22:13 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-239-evidence.md -->

<!-- auto-log: 2026-09-19 22:14 Write /tmp/holdout239-synapti.sh -->

<!-- auto-log: 2026-09-19 22:14 Write /tmp/dbg239-synapti.sh -->

<!-- auto-log: 2026-09-19 22:14 Write /tmp/holdout239b-synapti.sh -->

<!-- auto-log: 2026-09-19 22:14 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-239-evidence.md -->

<!-- auto-log: 2026-09-19 22:14 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-239.md -->

<!-- auto-log: 2026-09-19 22:26 Edit /Users/danielbentes/synapti-marketplace/.flow/goals/issue-239.goal.yaml -->

<!-- auto-log: 2026-09-19 22:26 Edit /Users/danielbentes/synapti-marketplace/.flow/goals/issue-239.goal.yaml -->

<!-- auto-log: 2026-09-19 22:26 Write /tmp/msg239-synapti-commit-final.txt -->

<!-- auto-log: 2026-09-19 22:26 commit "fix(flow): the force-push guard decides on the invocation, not the whole line" -->

<!-- auto-log: 2026-09-19 22:27 Write /tmp/issue-secrets-synapti.md -->

<!-- auto-log: 2026-09-19 22:29 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-239-evidence.md -->

<!-- auto-log: 2026-09-19 22:29 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-239-evidence.md -->

<!-- auto-log: 2026-09-19 22:30 Write /tmp/pr239-synapti-force-push-guard.md -->

<!-- auto-log: 2026-09-19 22:30 Write /tmp/neg239-synapti.sh -->

<!-- auto-log: 2026-09-19 22:46 Write /tmp/ev239-synapti-sidecar.yaml -->

<!-- auto-log: 2026-09-19 22:47 Edit /tmp/ev239-synapti-sidecar.yaml -->

<!-- auto-log: 2026-09-19 23:16 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/goal.md -->

<!-- auto-log: 2026-09-19 23:16 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/goal.md -->

<!-- auto-log: 2026-09-19 23:19 Write /tmp/flow-sec-probe/probe-underblock.sh -->

<!-- auto-log: 2026-09-19 23:20 Write /tmp/flow-sec-probe/probe-timing.sh -->

<!-- auto-log: 2026-09-19 23:21 Write /tmp/flow-sec-probe/probe-timing2.sh -->

<!-- auto-log: 2026-09-19 23:21 Write /tmp/flow-sec-probe/probe-regress.sh -->

<!-- auto-log: 2026-09-19 23:22 Write /tmp/flow-sec-probe/probe-mechanisms.sh -->

<!-- auto-log: 2026-09-19 23:22 commit "improve(flow): correct the lifecycle-write template the goal command documents" -->

<!-- auto-log: 2026-09-19 23:22 Write /tmp/flow-sec-probe/probe-close.sh -->

<!-- auto-log: 2026-09-19 23:22 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 23:22 commit "improve(flow): state the guard's cost where a reader can reproduce it" -->

<!-- auto-log: 2026-09-19 23:23 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 23:23 commit "improve(flow): align the guard's in-file cost figures with the measured range" -->

<!-- auto-log: 2026-09-19 23:23 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-security-reviewer/project_block_force_push_guard_scanner_regressions.md -->

<!-- auto-log: 2026-09-19 23:23 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-security-reviewer/MEMORY.md -->

<!-- auto-log: 2026-09-19 23:23 Write /tmp/flow-sec-probe/probe-final.sh -->

<!-- auto-log: 2026-09-19 23:24 Write /tmp/sec239-synapti.sh -->

<!-- auto-log: 2026-09-19 23:28 Write /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 23:28 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 23:29 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 23:29 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 23:29 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 23:29 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 23:29 Write /tmp/dbg2-synapti.sh -->

<!-- auto-log: 2026-09-19 23:30 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 23:30 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 23:31 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 23:31 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 23:33 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/block-force-push.test.sh -->

<!-- auto-log: 2026-09-19 23:33 Write /tmp/mut239-synapti.py -->

<!-- auto-log: 2026-09-19 23:34 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 23:36 Write /tmp/qsub239-synapti.sh -->

<!-- auto-log: 2026-09-19 23:36 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/block-force-push.test.sh -->

<!-- auto-log: 2026-09-19 23:37 Write /tmp/err5-239-synapti.sh -->

<!-- auto-log: 2026-09-19 23:37 Write /tmp/spec239-synapti.py -->

<!-- auto-log: 2026-09-19 23:38 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-239-evidence.md -->

<!-- auto-log: 2026-09-19 23:38 Write /tmp/hostile239-synapti.sh -->

<!-- auto-log: 2026-09-19 23:38 commit "fix(flow): the force-push guard blocks by default and allows only what it can account for" -->

<!-- auto-log: 2026-09-19 23:39 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 23:39 Write /tmp/missing239-synapti.py -->

<!-- auto-log: 2026-09-19 23:39 commit "fix(flow): check every tool the guard's shell part runs, not just four" -->

<!-- auto-log: 2026-09-19 23:42 Write /tmp/ev239b-synapti-sidecar.yaml -->

<!-- auto-log: 2026-09-19 23:44 Write /tmp/sort239-synapti.sh -->

<!-- auto-log: 2026-09-19 23:44 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/hooks/scripts/block-force-push.sh -->

<!-- auto-log: 2026-09-19 23:45 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/block-force-push.test.sh -->

<!-- auto-log: 2026-09-19 23:47 Write /tmp/bundle239-nums-synapti.py -->

<!-- auto-log: 2026-09-19 23:47 commit "fix(flow): drop sort from the cannot-execute list, and state what earns a place on it" -->
