---
issue: 295
created: '2026-10-12T06:32:00Z'
artifacts:
- type: specification
  captured_at: '2026-10-12T06:32:00Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: goal-created
  captured_at: '2026-10-12T06:33:05Z'
  goal_id: issue-295
  source: github_issue
- type: workflow-run
  captured_at: '2026-10-12T06:33:29Z'
  workflow: start-issue
  run_id: 2026-10-12T061533Z-issue-295
  status: active
- type: stranger-test
  captured_at: '2026-10-12T06:41:38Z'
  result: PASS
  task_count: 8
---

## Specification

_Captured by specification-capture skill on 2026-10-12. Source: user-confirmed._

One request per stop or review instead of one per item, for goal.judge, goal.warn-evidence and review.confidence. The TypeSafe API takes one state per request with any number of questions (HTTP API page, read 2026-10-12); Jev 1.13 allows 32k tokens for the state plus the longest question and 64k for the state plus all questions (Models page, read 2026-10-12). The Jev 1.13 jaggedness page lists indirection and large states with unrelated detail as causes of lower accuracy, which is why the batched answers are compared with answers given alone before batching becomes a default.

### Non-goals

- review.challenge, review.dedup, the two /flow:address questions, learn.correction, classify.serves-issue and quality.tests-ran keep one request per item.
- No two decision points share a request: each request belongs to one site, with that site's mode and threshold.
- No mode or threshold changes; every site stays off by default.
- The question wording changes only by the words that point it at its item; no other rewording.
- A batched state is never shortened: an item that does not fit goes on today's single path.
- No work for Python 3.9.

### Failure modes

- **Timeouts** — a request that times out gives every item in it `timeout`, and each caller does what it does today for a failed call (goal: Haiku decides the turn; review: no demotion, and two such requests in a row stop asking).
- **Partial failures** — a missing, abstained, malformed or below-threshold answer affects only its own item; the other items keep their answers.
- **Invalid input** — an item whose state cannot be read or sent as JSON is refused alone (`state-invalid`) and the rest are asked; a bad items file is a usage error (exit 2).
- **Missing context** — no provider, mode off, or batching off gives today's behaviour: one request per item, or none.

### Interface contracts

- `flow-s1.sh ask-many --site S --items-file F [--run-id ID]`. F: `{"items": [{"key", "state_file", "current", "ref"}]}`. Stdout: one JSON line per item, in input order: `{key, result, answer|null, model, truncated, batch}`.
- Two layouts, chosen by the user setting `systemOne.batch` (`off` | `items-in-state` | `items-in-questions`; read from user settings and the plugin default only), whose default is set by the measurement:
  - `items-in-state`: state `{"items": {key: item state}}`; one question per item, whose instructions start "This question is about `items.<key>` only ..." followed by the site's instructions.
  - `items-in-questions`: state `{"items": [keys]}`; each question's instructions are an object `{question: <site instructions>, item: <item state>}`.
- Packing: items in input order, at most 10 per request, total under the client's cap (stateTokenCap x 4 characters); an item over the cap on its own goes through `ask` as today.
- Records: one per item with today's fields; `question` is the site's question id; `state_sha256` is the digest of the item's state file; plus `batch: {id, size, index, layout}`.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Answer to item | answers attached by position, not by key | items AC3, AC1 with stub p 0.9 for AC3 and 0.1 for AC1 → right: AC3=0.9, AC1=0.1; wrong: swapped |
| Packing bound | `>` for `>=` at the cap, or 11 items in one request | two items summing exactly to the cap → right: 1 request, one character more → 2; 11 small items → right: 2 requests; wrong: 1 |
| Per-item fallback | the first failure fails the whole batch | item 2 malformed of 3 → right: items 1 and 3 answered, 2 malformed; wrong: all three no answer |
| Record join | the batch's digest written as state_sha256 | right: the record's digest equals sha256 of the item's state file; wrong: the batch hash |
| Threshold lookup | threshold keyed by the item key instead of the site question | goal.warn-evidence on jev-1.13.0 (threshold 0.6), p 0.79 → right: below-threshold, p 0.81 → answered; wrong: default 0.9 applied, or an error |

## Pre-registration

_Written 2026-10-12, before any provider call for this issue._

**Sets.**
- Goal set: the 178 items of the 2026-10-07 goal replay (`~/flow-s1-work/replay/A/items.jsonl`, 13 goals, 72 labelled supported and 106 not), asked at site `goal.judge` (question `supported`; `goal.warn-evidence` asks the same question about the same states). Items are grouped by goal, in the order of the items file.
- Review set: the 134 `review.confidence` states kept in `plugins/flow/evals/results-2026-09-25-review/replay/shadow/base/` (78 runs), grouped by run. 41 runs have one finding and 37 have two to five (93 findings). On 2026-10-04, 131 of the 134 answers had p >= 0.5, so agreement on the side of 0.5 says little about this set; it is held to the p-difference bar and the crossings below, never to an agreement figure alone.

**Sends**, all to TypeSafe jev-1.13.0 in `shadow` mode, in one session, at the shipped `timeoutMs` (3000 ms), through the client on this branch:
- A1 and A2: every item alone (`flow-s1.sh ask`), twice. A2 against A1 measures how much two sends of the same item alone disagree.
- S: `items-in-state`; Q: `items-in-questions`, both packed by the shipped rule (input order, at most 10 items, under the cap) within each goal or run.
- Per group the four sends run one after another, the order rotating from group to group (A1 S A2 Q, then S A2 Q A1, ...), so that drift over the session falls on every send alike.

**Measures.** For send X and line t, crossings C(X, t) = items answered in both X and A1 whose p falls on different sides of t (p >= t against p < t). Lines: goal set 0.5, 0.75 (`goal.judge` decides supported at confidence >= 0.5, p >= 0.75) and 0.8 (`goal.warn-evidence` on jev-1.13.0, confidence >= 0.6); review set 0.5 and 0.05 (`review.confidence` demotes at confidence >= 0.9 with p < 0.5, so p <= 0.05).

**Bars**, each layout separately; a layout passes only when all hold:
1. Goal set, at each of 0.5, 0.75 and 0.8: C(X, t) <= C(A2, t) + 3.
2. Goal set: items whose p >= 0.5 matches the label, in X, at least A1's count minus 3.
3. Review set, at 0.5 and 0.05: C(X, t) <= C(A2, t) + 2.
4. Per set: at most 2 items answered in A1 and not answered in X (a timeout, a malformed or abstained answer, or any other no-answer; below-threshold counts as answered, since its p is recorded).
5. Per set: the median of |p_X - p_A1| at most the median of |p_A2 - p_A1| plus 0.02.

**Default.** `systemOne.batch` ships as the layout that passes. If both pass, the one with fewer crossings at 0.5 over both sets; on a tie, `items-in-questions` (each question sees only its own item). If neither passes, it ships `off`, the code stays, and the reference reports why.

**Reported, not barred:** requests per set for A1, S and Q; time per request (median and 95th percentile) and timeouts per send; crossings at 0.5 by position in the request.

## Plan

_Written 2026-10-12, before any provider call._

**Layout wording, fixed before any send** (the Interface contracts above, made exact):
- `items-in-state`: state `{"items": {<key>: <item state>, ...}}`. Each item's question has the item's key as its id, and its instructions are the text "This question is about `items.<key>` only. Every field named below is a field of `items.<key>`. " followed by the site's instructions.
- `items-in-questions`: state `{"items": [<key>, ...]}`. Each item's question has the item's key as its id, and its instructions are the object `{"question": "The item to judge is `item`, given here, not in the state. Every field named below is a field of `item`. " + the site's instructions, "item": <item state>}`.
- Keys: the finding id for `review.confidence`; `c<n>` (the manifest row) for the goal sites.
- Size: `len(json.dumps(state, ensure_ascii=False)) + len(json.dumps(questions, ensure_ascii=False)) <= cap * 4`, the serializer the client's `size()` uses.
- `ask-many` refuses, with exit 2, a site other than `goal.judge`, `goal.warn-evidence` and `review.confidence`, and exits 4 when `systemOne.batch` is `off`; the caller then takes today's path unchanged.

**Tasks**, in order:
1. Client: `flow-s1.sh ask-many`, packing, per-item results and records, the `systemOne.batch` setting (all five risk rows tested here).
2. Goal Stop hooks ask through `ask-many`, writing the `<n>.out`/`<n>.rc` files `_goal_s1_results` already reads; exit 4 runs today's loop.
3. `review.confidence` collects its eligible findings, then asks through `ask-many`; exit 4 runs today's loop; the provider-down rule counts requests.
4. Harness `evals/results-2026-10-12-s1-batch/` (`run.sh`, `summarize.py`, README) with a stub-backed test of the bars at their bounds and the default rule.
5. The provider run, as pre-registered.
6. AC4: the per-item sites stay per item (tested by request count) and the reference says why.
7. The measured default in `settings.json`, the reference and the CHANGELOG.
8. Quality checks, self-review, holdout validation, verdict.

## Stranger Test

PASS — 8 tasks reviewed. Each names its files, contract, tests with sourced expected values, and verification command; the planner's open questions were settled above.
