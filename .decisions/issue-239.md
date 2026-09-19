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
---

# Issue 239 — the force-push guard reads the whole shell line

## Specification

_Captured by specification-capture skill on 2026-09-19. Source: extracted-from-issue._

### Non-goals

- Not a change of policy. `--force` and `-f` on a push stay blocked; `--force-with-lease` alone stays allowed. Only *which text* the guard examines changes.
- Not a shell. Variable expansion, command substitution and aliases are not modelled, so a force flag assembled at run time — `F=--force; git push $F` — is invisible to the guard, as it was before.
- Not a change to any other hook. `block-destructive.sh` keeps its own force-delete and force-create rules. `block-secrets.sh` shares this defect class and is untouched here: narrowing a secrets guard's false-positive policy is a security decision with a different blast radius, filed as #241 rather than folded into a push fix.
- Not a relaxation. Every command the guard blocks today because a push really carries a force flag stays blocked. Where a wrapper could hide a push, the guard errs toward blocking.

### Failure modes

- **Timeouts** — the scan walks the command a character at a time, so its cost grows faster than the input. A command longer than `MAX_CHARS` (131072) is refused rather than truncated: truncating and scanning the head would drop whatever the tail contained, and a dropped tail is the direction that lets a force-push through. Measured on this machine's awk across two runs, a 100 KB command takes 0.7-0.8 s and one at the cap 1.0-1.1 s.
- **Partial failures** — `jq` or `awk` missing fails closed: the hook blocks rather than allowing an uninspected command. Both are required because the parse now depends on `awk` as well as `jq`; without the check a missing `awk` would exit 127, which the harness reads as an allow.
- **Invalid input** — a crash is not a block: `set -euo pipefail` with a failing command exits non-zero, and the harness reads a non-2 exit as an allow, so any parse path that can error must be written so it cannot. Input that ends mid-construct — an unclosed quote, a heredoc with no terminator — is not vouched for and blocks. A payload `jq` cannot parse also blocks, rather than falling through on jq's own exit status. A 3000-input fuzz sample and a targeted pathological set produced only exits 0 and 2.
- **Missing context** — the hook consults no git state and no repository, so an unusual working directory changes nothing.

### Interface contracts

- Hook protocol: reads `{"tool_input":{"command":"..."}}` as JSON on stdin; exit 0 allows, exit 2 blocks with the message on stderr.
- The block message keeps its three lines verbatim: the operator reads them, and the third names `--force-with-lease` as the safe alternative.
- `git push --force`, `git push -f`, `cmd && git push --force`, `{ git push --force; }` → blocked.
- `git push --force-with-lease` → allowed. `git push --force-with-lease --force` → blocked.
- Any `-f` or `--force` belonging to another command on the same line → allowed.
- A push written through quoting, a launcher, a path, a shell's `-c` payload or `eval` → blocked. A path or a launcher does not stop it being a push.
- A command longer than `MAX_CHARS`, or one that ends mid-construct → blocked.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| splitting the line into commands | splits on `;`, `&&`, `\|` without respecting quotes, so a separator inside a quoted string yields a segment that looks like a push | `grep -q 'x ; git push --force' file` → right: allowed (no push is invoked); wrong: blocked |
| where a push's own arguments end | reads the rest of the segment, so a flag belonging to a later command inside the same segment counts | `git push origin main && pgrep -f x` → right: allowed (the reported case); wrong: blocked |
| the `-f` word boundary | matches `-f` inside a longer word (`-force`, `--force-with-lease`) | `git push --force-with-lease` → right: allowed; wrong: blocked |
| a heredoc body | scans the whole command string, including text being written to a file, or desyncs from the shell and skips a line that is a command | `cat > notes.md <<'EOF'` writing `git push --force` → right: allowed; wrong: blocked. `read -r x <<< hi` then `git push --force` → right: blocked; wrong: allowed |
| `-f` as another command's flag | treats any `-f` after `git push` on the line as the push's own | `git status && pgrep -f x` → right: allowed (the reported case); wrong: blocked |
| advancing past a separator | consumes two characters for a one-character separator, dropping the first letter of the next command word | `true;git push --force` → right: blocked; wrong: allowed |
| a launcher's own options | leaves the launcher's option word where the command word belongs, or stops at it | `sudo -u root git push --force`, `timeout 10 git push --force` → right: blocked; wrong: allowed |
| finding the command word | stops at a path-qualified or quoted command word | `/usr/bin/git push --force`, `bash -c "git push --force"` → right: blocked; wrong: allowed |
| command position | grows tolerant wrappers by scanning for `git` anywhere, so text reads as a command | `echo git push --force` → right: allowed; wrong: blocked |

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
