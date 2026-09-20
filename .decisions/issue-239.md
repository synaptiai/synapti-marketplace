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
- type: evidence-captured
  captured_at: '2026-09-19T22:01:34Z'
  evidence_id: evidence-ac1-5-guard-suite-turn4
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
| whether the accounting runs at all | gates it behind the whole-line pattern, so it is inert on a line the pattern misses — which is what an expansion or a redirect produces | `$(echo git) push --force origin main` -> right: blocked; wrong: allowed |
| a flag the line assigns | reads only literal flag words, so a variable holding the flag hides it | `F=--force; git push --force $F origin main` -> right: blocked; wrong: allowed, and `F=main; git push --force $F origin main` right: allowed |
| a redirect beside the command word | splits on whitespace only, so `push>log` is one word and no push is seen | `git push>log --force origin main` -> right: blocked; wrong: allowed |
| which command reads a heredoc body | judges by the opener first word, so a body piped into a shell reads as text | `cat <<EOF \| bash` with a push in the body -> right: blocked; wrong: allowed |
| a flag and a push in different commands | accounts each segment alone, so a flag piped into `xargs` has no push beside it | `echo --force \| xargs git push` -> right: blocked; wrong: allowed, while `xargs git push origin main` stays allowed |
| a command that runs its argument as a shell | treats `gh` as one that cannot, but `gh alias set --shell` makes one | `gh alias set --shell pp 'git push --force'` -> right: blocked; wrong: allowed |
| a flag that forces nothing | matches `--force` inside `--force-if-includes` | `git push --force-if-includes origin main` -> right: allowed; wrong: blocked |
| a harmless flag on an unlisted command | blocks it whenever a push shares the line, so a text command the list does not name is refused | accepted cost: `git push origin main && sort -f file` -> right: blocked (the safe direction); the price is a refused command |

## Stranger Test

PASS — 3 tasks reviewed.
