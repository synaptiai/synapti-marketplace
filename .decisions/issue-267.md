---
issue: 267
created: '2026-10-01T15:37:42Z'
artifacts:
- type: specification
  captured_at: '2026-10-01T15:37:42Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
---

## Specification

System One decision point `address.category`: in `/flow:address` Phase 2, after the session has chosen a category for a feedback item, the model is asked which of P1, P2, P3 or Question it belongs to. Ships `off`.

Decisions (user, 2026-10-01, epic #258): rank P1 > P2 > P3 > Question; the model can raise a Question to a fix, never lower a fix to a reply. A repository's settings may only lower a site's mode. Every call passes `--ref`.

Corrections to the accepted spec, made against the code at 85b63bc4:
- The spec's "mode is read from every tier, the repository included" predates #278. A repository can only lower the user's mode (`bin/flow-s1-mode.sh`); the repository scenarios are: user unset or `off`, repository `shadow`: probe prints nothing and nothing is sent; and user `shadow`, repository `on` with its own `baseUrl` at a second stub. The user's stub gets the one request, the second stub none, the record's mode is `shadow`, and no raise is printed.
- The block runs only when the `!` probe prints `S1_CATEGORY=shadow|on`, so with the site off the session makes no extra tool call per item. Run directly with the site off, the block still prints exactly `CATEGORY=<session category>`.
- The item's reference is built by the block from `PR_NUM`, `ITEM_KIND` and `ITEM_ID` (integers checked in the block) and, for a finding row, the finding id read from the item file: `pr:<PR>/inline:<id>`, `pr:<PR>/review:<id>[/<finding id>]`, `pr:<PR>/comment:<id>`. A record that cannot be matched to its item cannot be judged in the comparison, so a missing or malformed part is `STATE=blocked`.
- The state is built in the block with jq from the item file; the #266 helper builds a code window for a GitHub comment, which this question does not use.

### Non-goals
- Never lowers a category, never moves an item to Question or Resolved.
- Does not judge whether a comment still applies (#266); Resolved items are not asked about.
- Does not change Pushback, the resolution marker format or the merge gate.
- Does not decide which items are addressed; every item listed today is still listed.
- One item per request; no batching.
- Does not change the client.
- Does not switch the site on by default.

### Failure modes
- Timeout, HTTP error, redirect, connection, malformed, abstained, missing answer, below threshold, usage error, any exit other than 0: the session's category, stdout identical to off mode; the client's stderr line passes through.
- Exit 0 with a choice outside P1, P2, P3, Question, or output jq cannot read: treated as no answer.
- Invalid input (category outside P1|P2|P3|Question|Resolved; an item file that is missing, not JSON, or has empty text, a line that is not digits, or a finding id outside the ledger's shape; `PR_NUM`, `ITEM_KIND` or `ITEM_ID` missing or malformed; a `RUN_ID` that `flow-s1.sh` refuses): `STATE=blocked`, `ERROR=`, exit 1, no request.
- An item file the session did not make (outside `$TMPDIR`, a symlink, a relative path): `STATE=blocked`, exit 1, not read and not removed.
- An answer about an item the client had to shorten: the session's category, with a warning on stderr.
- flow-s1.sh not found, jq missing, mktemp failing: the session's category, one warning on stderr.
- Plugin inside the repository: the probe skips that copy, and with no other install prints nothing.
- Partial failure across items: each item is its own call.

### Interface contracts
- `S1_CATEGORY_MODE_BLOCK` (in the same `!` fence as the #266 probe): prints `S1_CATEGORY=shadow|on` or nothing.
- `COMMENT_CATEGORY_BLOCK` input (environment): `SESSION_CATEGORY`, `PR_NUM`, `ITEM_KIND` (`inline`, `review` or `comment`), `ITEM_ID` (integer), `ITEM_FILE`, optional `RUN_ID`. `ITEM_FILE` is a file from `mktemp`, directly in `$TMPDIR`, written with the Write tool, holding `{"text", "path", "line", "finding"}`; the block reads it and removes it before any other check. No value taken from the item is on the command line.
- Output: exactly `CATEGORY=<category>`; only in `on` mode with a confident answer that ranks higher, a second line `CATEGORY_RAISED_FROM=<session category>`. Off, provider none, shadow and every no-answer reason give the same bytes.
- Client call: `flow-s1.sh ask --site address.category --state-file <tmp> --state-format json --current <session> --ref <the built reference> [--run-id <RUN_ID>]`.
- State: `{"comment":{"text","path","line"}}`.
- Records: `site=address.category`, `question=category`, `current=<session category>`, `ref=<the built reference>`.
- Phase 2 display of a raised row: `**P1 · Must fix (raised from P3) · <path>**`.
- Threshold `0.8` in `system-one/questions.yaml` is provisional.

### Risk map
| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Direction of the comparison | the model's choice taken whenever it differs | session P1, model P3 at 0.97: `CATEGORY=P1`, no raise; session P3, model P1: `CATEGORY=P1`, `CATEGORY_RAISED_FROM=P3`; mutant taking the model's choice fails |
| Shadow leaks into output | stdout read before the exit status | shadow with model P1 at 0.97: stdout byte-equal to off; record holds `current=P3`, `answer.choice=P1` |
| Off path does work | the stub reached or a state built in off mode | off and provider none: 0 requests, no records, no gh call |
| Resolved reaches the model | a Resolved item is asked and raised | on, Resolved, model P1: `CATEGORY=Resolved`, 0 requests |
| Threshold not applied | answers read after exit 3 | on, model P1 at confidence 0.33: session category, record `below-threshold` |
| Injection through the item | text, path or finding id on the command line, where `$(...)` runs before the block | text with `$(touch pwned)`, backticks, quotes, newline and a final newline, and a path with `$(touch PWNED)` and a quote, all in the JSON file: no file, stub receives text and path verbatim |
| A file the session did not make | a misled call names `~/.ssh/id_ed25519`, which is sent and deleted | a file outside `$TMPDIR`, a symlink in it, a relative path: blocked, not read, not removed, 0 requests |
| Item file left behind | the file is removed by a step after the block, which the block's `exit` skips | after an answer, no answer, and a blocked call, the item file is gone |


### Mutation runs

Run on 2026-10-07 on copies of the committed plugin, one mutant at a time; each failed the scenario named, for the reason given.

| Mutant | Scenario that failed | Why it failed |
|---|---|---|
| the model's choice taken whenever it is a category | cc-on-never-lowers | session P1 printed `CATEGORY=P3` |
| exit status not checked | cc-no-answer-with-stdout | a client that printed a P1 answer and exited 3 raised the item to P1 |
| Resolved sent | cc-resolved-not-asked | `CATEGORY=P1` and two requests |
| threshold not applied (client) | cc-on-below-threshold | confidence 0.33 raised the item to P1 |
| P1 and P2 ranks swapped | cc-on-adjacent-ranks | session P2, model P1: not raised |
| a session Question ranked as P3 | cc-on-adjacent-ranks | session Question, model P3: not raised |
| a model Question ranked as P3 | cc-on-adjacent-ranks | session Question, model Question: `CATEGORY_RAISED_FROM=Question` printed |
| shortened item acted on | cc-truncated | `CATEGORY=P1` with no warning |
| item file not checked against TMPDIR | cc-item-file-outside-tmp | a file outside TMPDIR was sent to the stub and deleted |
| the finding id left out of the ref | cc-review-finding-ref | ref `pr:7/review:55`, not `pr:7/review:55/SEC-2` |
| the item's path not sent | cc-text-is-data | the state's path was empty |
| flow-s1.sh exit 2 not reported as blocked | cc-invalid-input | exit 0 for `RUN_ID=../R1` |

## Shadow comparison

- 2026-10-07. Written from the replay records only, as the user decided on 2026-10-07 for every site of epic #258: 200 records sent to TypeSafe jev-1.13.0 on 2026-10-07 (refs `replay:pr-finding:*`), joined by ref to the priority each reviewing session recorded (27 P1, 75 P2, 98 P3, 0 Question). That priority is also the decision Flow takes, so there is one agreement figure. No live records.
- Result: the model agrees with the reviewer on 44 of 200 and chose P1 for 134; at 0.8 it would raise 96 items (78 of them to P1). On this model the question over-raises to P1 (22% agreement, 48% of items raised at 0.8). No threshold is set: 0.8 stays the provisional default, questions.yaml is unchanged, and the site ships off (user, 2026-10-07). Choosing a threshold needs a ruling on whether each raise was right, which the replay does not have, and a reworded question needs a new measurement.
- The comparison is in references/system-one.md under `address.category`; per-item data, with an empty `ruling` field per item, in evals/results-2026-10-07-address-s1/address-category.jsonl.
