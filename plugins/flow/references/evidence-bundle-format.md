# Evidence Bundle Format (verdict-judge input contract)

Reference document. The canonical markdown shape that `agents/verdict-judge.md` consumes when evaluating whether an implementation satisfies the issue's acceptance criteria. Producers (`commands/start.md` Phase 4, the `criterion-verification-map` skill) and the consumer (`verdict-judge`) both cite this document so the auto-FAIL rules ("missing `Does NOT promise` field" → FAIL, "missing one of five completeness subsections" → FAIL) check against a published schema rather than an implicit convention.

## Shape

The evidence bundle is one markdown document per branch. Each acceptance criterion gets one second-level section (`## Criterion {N}: ...`). Criteria appear in the same order as the issue body — the verdict-judge cross-references the bundle headings to the issue criteria during the missing-criterion scan.

### Top of file (preamble)

```markdown
# Evidence Bundle — Issue #{N}

**Branch:** {branch-name}
**Generated:** {ISO-8601 timestamp}
**Acceptance criteria source:** issue #{N} body, ## Acceptance Criteria section
**Total criteria:** {N}

```

The preamble is metadata, not evaluated by the judge. The judge keys off the `## Criterion {N}: ...` headings.

### Per-criterion section

Each criterion section MUST follow this exact subsection structure:

```markdown
## Criterion {N}: {exact criterion text from the issue}

### Type

{behavioral | api | ui | error | performance | config | data | contract}

### Verification command

```bash
{the exact bash command from the Spec Validation Gate}
```

### Output

```
{the captured stdout/stderr from running the verification command}
```

### Does NOT promise

- {non-goal 1 — what this criterion explicitly does not cover}
- {non-goal 2}

(or: "none — this criterion has no scope-narrowing non-goals")

### What was tested

- {scenario 1 covered by the verification command}
- {scenario 2}

### What was NOT tested

- {gap 1 — explicit untested case the reader should know about}
- {gap 2}

(or: "none known — every scenario implied by the criterion was exercised")

### Known limitations of this evidence

- {limitation 1 — e.g., test runs against an in-memory database, not the prod schema}
- {limitation 2}

(or: "none — the verification command exercises the production code path with production-equivalent dependencies")

### Negative/adversarial cases covered

- {adversarial scenario 1 — malformed input, hostile timing, exhausted resources}
- {adversarial scenario 2}

(or: "none — this criterion describes a happy-path behavior with no defined adversarial surface")

### Test inputs and expected values

| Test | Input | Expected | Source of expected |
|---|---|---|---|
| {test name as it appears in the test source} | {the concrete input the test feeds in} | {the concrete value or observable outcome the test asserts} | {spec/criterion text | reference implementation | hand computation | existing fixture | external standard} |

(or, ONLY when `### Type` is `ui` or `config`: "none — {reason}")

### Risk map coverage

- {risk-map area} → {test file:line of the test whose input is that row's discriminating check}
- {risk-map area} → {test file:line}

(or: "none — {reason}"; or, when `specFirst.riskMap` is `false`: "none — risk map disabled (specFirst.riskMap=false)")
```

`### Type` carries the classification from the `criterion-verification-map` skill's classification table. The judge reads it to decide whether the `none` exemption on `### Test inputs and expected values` applies and whether the criterion is order-, position-, or value-sensitive.

## Mandatory subsections

The verdict-judge's auto-FAIL rules check for these subsections by exact heading text. Producers MUST emit them with this casing and punctuation:

| Heading | Required? | Verdict-judge check |
|---|---|---|
| `### Type` | yes (informational) | Used to apply type-conditional rules; a missing `### Type` is treated as `behavioral` (the strictest case) |
| `### Verification command` | yes (informational) | Used to identify what the evidence comes from; not an auto-FAIL trigger |
| `### Output` | yes (informational) | Used as the actual evidence; not an auto-FAIL trigger |
| `### Does NOT promise` | **YES (auto-FAIL if missing)** | Verdict-judge Step 1 rule: "missing-non-goals" |
| `### What was tested` | yes (informational) | Used during per-criterion evaluation |
| `### What was NOT tested` | **YES (auto-FAIL if missing)** | Verdict-judge Step 1 rule: "missing-completeness-subsection" |
| `### Known limitations of this evidence` | **YES (auto-FAIL if missing)** | Verdict-judge Step 1 rule: "missing-completeness-subsection" |
| `### Negative/adversarial cases covered` | **YES (auto-FAIL if missing)** | Verdict-judge Step 1 rule: "missing-completeness-subsection" |
| `### Test inputs and expected values` | **YES (auto-FAIL if missing)** | Verdict-judge Step 1 rule: "missing-completeness-subsection"; Step 2 rules "self-referential oracle" and "degenerate input" read its rows |
| `### Risk map coverage` | **YES (auto-FAIL if missing)** | Verdict-judge Step 1 rule: "missing-completeness-subsection"; Step 2 rule "risk map uncovered" reads its lines |

The six MANDATORY subsections (`Does NOT promise` plus the five completeness subsections: `What was NOT tested`, `Known limitations of this evidence`, `Negative/adversarial cases covered`, `Test inputs and expected values`, `Risk map coverage`) MUST be present even when their content is "none". The point of the format is to force the producer to make an explicit positive statement about scope and limitations rather than leaving the reader to guess. A blank section is treated identically to a missing one and triggers auto-FAIL.

## "None" is a valid answer

Each mandatory subsection accepts `none` as a complete answer when the producer can affirmatively say there is nothing to disclose. The verdict-judge treats `none` as a positive statement, not a missing field. Examples:

- A config-only criterion: `### Negative/adversarial cases covered\n\nnone — this criterion is a config schema change with no defined adversarial surface.`
- A pure happy-path API addition with no failure mode in scope: `### What was NOT tested\n\nnone known — every scenario implied by the criterion was exercised by the verification command.`

The producer SHOULD include a one-clause justification for `none`. Bare `none.` is permitted but reduces auditability — a future reader cannot tell whether the producer thought about the question and concluded `none`, or skipped the question.

Two subsections restrict when `none` is acceptable:

- `### Test inputs and expected values` accepts `none — {reason}` ONLY when `### Type` is `ui` or `config`. For every other type (`behavioral`, `api`, `error`, `performance`, `data`, `contract`) the verification evidence comes from tests, and tests have inputs and expected values; `none` on those types is an auto-FAIL ("no test inputs recorded for a testable criterion").
- `### Risk map coverage` accepts two forms of `none`:
  - `none — risk map disabled (specFirst.riskMap=false)` — the disabled marker. Not an auto-FAIL on any criterion type. Emitted only when the journal's `### Risk map` is `disabled — specFirst.riskMap=false`.
  - `none — {reason}` — no risk-map row maps to this criterion. Accepted on `ui`, `config`, `performance`, and `contract` criteria. On `behavioral`, `error`, `data`, and `api` criteria the judge FAILs it (Step 2 rule "risk map uncovered") unless the reason states that the risk map has no row in this criterion's area AND the judge can confirm that from the row areas cited elsewhere in the bundle — a risk map with rows that nobody mapped is the failure the subsection exists to catch.

## Sample bundle

A complete evidence bundle for a two-criterion issue (illustrating both a behavioral criterion with adversarial coverage, real test-input rows, and risk-map coverage, and a config criterion with `none`-only completeness):

```markdown
# Evidence Bundle — Issue #142

**Branch:** feature/issue-142-rate-limit-login
**Generated:** 2026-05-06T14:22:00Z
**Acceptance criteria source:** issue #142 body, ## Acceptance Criteria section
**Total criteria:** 2

## Criterion 1: Login endpoint rejects requests after 5 failures within 60 seconds with HTTP 429

### Type

behavioral

### Verification command

```bash
npm test -- --grep "rate limit login"
```

### Output

```
PASS  src/auth/__tests__/rate-limit.test.ts (6 tests, 1.6s)
  ✓ allows 5 login attempts within 60s
  ✓ rejects 6th attempt with 429 and Retry-After: 60
  ✓ resets counter after 60s elapses
  ✓ 5th failure is not rejected (threshold is strictly more than 5)
  ✓ attempt at exactly t=60s starts a new window
  ✓ two accounts behind one IP are limited independently
```

### Does NOT promise

- Does NOT rate-limit by IP (limit is per-account)
- Does NOT rate-limit other auth endpoints (signup, password reset)

### What was tested

- 5 successful attempts within window pass through
- 6th attempt returns HTTP 429 with `Retry-After: 60` header
- Counter resets after the 60-second window elapses
- Threshold, window-boundary, and counter-key discriminating cases from the risk map

### What was NOT tested

- Behavior under clock skew between application servers (multi-instance setup)
- Behavior when the rate-limit store (Redis) is unreachable

### Known limitations of this evidence

- Tests run against an in-memory rate-limit store, not the production Redis cluster. The store interface is the same but Redis-specific failure modes (TTL drift, connection pool exhaustion) are not exercised.
- Time is advanced with a fake clock; real-clock jitter around the 60s boundary is not exercised.

### Negative/adversarial cases covered

- Repeated requests with the same body (replay test): all counted toward the limit
- Concurrent requests from same account: counter increments atomically
- Header injection in Retry-After (would-be SSRF surface): tested with malformed input

### Test inputs and expected values

| Test | Input | Expected | Source of expected |
|---|---|---|---|
| allows 5 login attempts within 60s | 5 POSTs /login, wrong password, account A, t=0..4s | 5 × 401, no Retry-After header | criterion text ("after 5 failures") |
| rejects 6th attempt with 429 and Retry-After: 60 | 6 POSTs within 60s from account A | 6th → 429 + `Retry-After: 60` | criterion text |
| resets counter after 60s elapses | 5 failures at t=0s, clock advanced to t=61s, 1 POST | 401 (not 429) | criterion text ("within 60 seconds") |
| 5th failure is not rejected | exactly 5 failures from account A | 5th → 401 | hand computation (5 failures is the allowed maximum; rejection begins at the 6th) |
| attempt at exactly t=60s starts a new window | 5 failures at t=0s, 6th POST at t=60.000s | 401, counter = 1 | hand computation (window is [t, t+60); 60.000 is outside) |
| two accounts behind one IP are limited independently | 3 failures from A, 3 failures from B, same X-Forwarded-For | next attempt from A → 401, from B → 401 | spec `### Non-goals` ("does NOT rate-limit by IP") |

### Risk map coverage

- threshold comparison → src/auth/__tests__/rate-limit.test.ts:28
- window boundary → src/auth/__tests__/rate-limit.test.ts:41
- counter key → src/auth/__tests__/rate-limit.test.ts:57

## Criterion 2: New `auth.rateLimit.windowSeconds` config key is documented and validated

### Type

config

### Verification command

```bash
npm test -- --grep "config validation rate limit"
```

### Output

```
PASS  src/config/__tests__/rate-limit.test.ts (2 tests, 0.3s)
  ✓ accepts integer values >= 10
  ✓ rejects values < 10 with descriptive error
PASS  docs/api/__tests__/config-coverage.test.ts
  ✓ auth.rateLimit.windowSeconds appears in CONFIG.md
```

### Does NOT promise

- Does NOT change the default value
- Does NOT migrate existing config files

### What was tested

- Schema validation accepts integer >= 10
- Schema validation rejects values < 10 with the documented error message
- Documentation coverage test confirms the key appears in `CONFIG.md`

### What was NOT tested

- none known — config-only criterion; no runtime path beyond the schema validator was added

### Known limitations of this evidence

- none — the schema validator is the production code path; tests exercise it directly

### Negative/adversarial cases covered

- none — config schema validation has no defined adversarial surface beyond malformed input, which the standard validator tests cover

### Test inputs and expected values

| Test | Input | Expected | Source of expected |
|---|---|---|---|
| accepts integer values >= 10 | `{ auth: { rateLimit: { windowSeconds: 10 } } }` | validator returns ok | issue body (`windowSeconds` minimum 10) |
| rejects values < 10 with descriptive error | `{ auth: { rateLimit: { windowSeconds: 9 } } }` | error `auth.rateLimit.windowSeconds must be >= 10` | issue body |

### Risk map coverage

- none — no risk-map row names config validation; the three rows (threshold comparison, window boundary, counter key) are all mapped under Criterion 1
```

The config criterion could have used `none — config criterion` for `### Test inputs and expected values`; recording the two rows anyway is preferred because the tests exist and the rows cost nothing.

## Producer responsibilities

`commands/start.md` Phase 4 step 5 is responsible for assembling the bundle. The producer MUST:

1. Iterate the acceptance criteria in issue order
2. Run the verification command from the Spec Validation Gate (Phase 1) for each criterion
3. Capture stdout/stderr verbatim into `### Output`, and emit `### Type` from the task's `Verification type:` field
3b. **Record test inputs and expected values from test source.** Open every test file cited by the verification command or named in `### Output` for this criterion. For each test that the output shows ran, write one `| Test | Input | Expected | Source of expected |` row taken from the test's source (the literal input it constructs, the literal value or outcome it asserts). Name the source of the expected value as one of: spec/criterion text, reference implementation, hand computation, existing fixture, external standard. If the expected value was captured from the implementation's own output (a snapshot, a "golden" file generated by running the code, a value pasted from a debug run), write `implementation output` — do not disguise it; the judge FAILs it and the fix is to re-derive the expected value independently. `none — {reason}` is permitted only when `### Type` is `ui` or `config`.
3c. **Map risk-map rows to tests.** Read the journal's `### Risk map` (shape in `references/specification-journal-format.md`) and the task's `Risk areas:` field. For each row whose area this criterion's task touches, find the test whose input is that row's discriminating check and write `<area> → <test file:line>` (line of the test's declaration). A row with no such test is NOT written as `none` — it is a gap: add the test (Phase 3 is not finished) or escalate. Write `none — {reason}` only when no row maps to this criterion, and `none — risk map disabled (specFirst.riskMap=false)` only when the journal subsection is the disabled marker.
4. Pull `### Does NOT promise` content from the specification capture in Phase 1 (the per-task `Non-goals touched` field set by `implementation-planner`)
5. Author the remaining completeness subsections (`What was NOT tested`, `Known limitations of this evidence`, `Negative/adversarial cases covered`) during Phase 4, asking the user via `AskUserQuestion` (six-field escalation per `references/escalation-format.md`) when content cannot be derived from existing artifacts
6. Validate the bundle against this schema (every mandatory subsection present, `none` permitted only where this document allows it) BEFORE dispatching `Agent(verdict-judge)` — invalid bundles are the producer's bug, not the judge's
7. Pass the validated bundle as the `Evidence Bundle` parameter in the verdict-judge dispatch (see `commands/start.md` Phase 4 step 6)

The producer never silently ships an incomplete bundle. If a mandatory subsection cannot be filled, the producer escalates per `references/escalation-format.md` rather than emitting a blank field — the auto-FAIL triggered by a blank field would surface the same gap downstream, but the escalation surfaces it earlier and with better context.

## Consumer (verdict-judge) responsibilities

`agents/verdict-judge.md` Step 1 (Missing-Criterion Scan) is the canonical consumer. The judge:

1. Parses the bundle by the `## Criterion {N}: ...` headings
2. Cross-references heading text against the acceptance criteria list (the missing-criterion scan)
3. For each criterion, checks the six mandatory subsections by exact heading match (`Does NOT promise` in its own coverage-table column; the five completeness subsections in the "Completeness Subsections Present?" column)
4. Applies auto-FAIL rules per the table above, including the type-conditional `none` restrictions
5. In Step 2, reads the `### Test inputs and expected values` rows to apply the self-referential-oracle and degenerate-input rules, and the `### Risk map coverage` lines to apply the risk-map-uncovered rule — the judge never opens test files; the rows are the only view of test inputs it has
6. Carries the auto-FAIL outcome into Step 2 — locked-in FAILs are not re-evaluated for PASS

The judge does NOT receive the diff, decision journal, planning rationale, self-review findings, or test source. The bundle is the entire universe of evidence the judge sees. This isolation is the independence contract — see `agents/verdict-judge.md` "Independence Protocol". The verdict the judge returns follows `references/verdict-output-format.md`.

## Compatibility with `criterion-verification-map` skill

The `criterion-verification-map` skill (`plugins/flow/skills/criterion-verification-map/SKILL.md`) describes the per-criterion classification and command-generation that happens at PLAN time, and the verify-time protocol that produces the two test-derived subsections. This document describes the bundle that gets assembled at VERIFY time from the per-criterion artifacts the skill produced.

The skill's plan-time output (verification type, verification command, expected evidence shape, `Does NOT promise`, `Risk areas`) is the input to the bundle producer. This document is the normative shape; the skill links here rather than restating it, so producers and the verdict-judge cannot drift.
