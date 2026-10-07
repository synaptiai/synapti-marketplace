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
- `ITEM_REF` is required and must have the shape `flow-s1.sh --ref` takes; missing or malformed is `STATE=blocked`, since a record that cannot be matched to its item cannot be judged in the comparison.
- The state is built in the block with jq from the environment; the #266 helper builds a code window for a GitHub comment, which this question does not use.

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
- Invalid input (category outside P1|P2|P3|Question|Resolved, empty text, missing or malformed ITEM_REF, malformed ITEM_LINE or RUN_ID): `STATE=blocked`, `ERROR=`, exit 1, no request.
- flow-s1.sh not found, jq missing, mktemp failing: the session's category, one warning on stderr.
- Plugin inside the repository: the probe skips that copy, and with no other install prints nothing.
- Partial failure across items: each item is its own call.

### Interface contracts
- `S1_CATEGORY_MODE_BLOCK` (in the same `!` fence as the #266 probe): prints `S1_CATEGORY=shadow|on` or nothing.
- `COMMENT_CATEGORY_BLOCK` input (environment): `SESSION_CATEGORY`, `ITEM_FILE` (a file from `mktemp` holding the item text, written with the Write tool; the block reads it and removes it before any check), `ITEM_REF`, optional `ITEM_PATH`, `ITEM_LINE` (digits), `RUN_ID`. A missing or empty item file: `STATE=blocked`, exit 1.
- Output: exactly `CATEGORY=<category>`; only in `on` mode with a confident answer that ranks higher, a second line `CATEGORY_RAISED_FROM=<session category>`. Off, provider none, shadow and every no-answer reason give the same bytes.
- Client call: `flow-s1.sh ask --site address.category --state-file <tmp> --state-format json --current <session> --ref <ITEM_REF> [--run-id <RUN_ID>]`.
- State: `{"comment":{"text","path","line"}}`.
- Records: `site=address.category`, `question=category`, `current=<session category>`, `ref=<ITEM_REF>`.
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
| Injection through the item text | text substituted into the fence | `$(touch pwned)`, backticks, quotes, newline: no file, stub receives the text verbatim |
| Item file left behind | the file is removed by a step after the block, which the block's `exit` skips | after an answer, no answer, and a blocked call, the item file is gone |

## Shadow comparison

- 2026-10-07. Written from the replay records only, as the user decided on 2026-10-07 for every site of epic #258: 200 records sent to TypeSafe jev-1.13.0 on 2026-10-07 (refs `replay:pr-finding:*`), joined by ref to the priority each reviewing session recorded (27 P1, 75 P2, 98 P3, 0 Question). That priority is also the decision Flow takes, so there is one agreement figure. No live records.
- Result: the model agrees with the reviewer on 44 of 200 and chose P1 for 134; at 0.8 it would raise 96 items (78 of them to P1). Choosing a threshold needs the user's ruling on whether each raise was right, which the replay does not have. The threshold stays 0.8, provisional; questions.yaml is unchanged; the site stays off.
- The comparison is in references/system-one.md under `address.category`; per-item data, with an empty `ruling` field per item, in evals/results-2026-10-07-address-s1/address-category.jsonl.
