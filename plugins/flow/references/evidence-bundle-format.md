# Evidence Bundle Format (verdict-judge input contract)

Reference document. The canonical markdown shape that `agents/verdict-judge.md` consumes when evaluating whether an implementation satisfies the issue's acceptance criteria. Producers (`commands/start.md` Phase 4, the `criterion-verification-map` skill) and the consumer (`verdict-judge`) both cite this document so the auto-FAIL rules ("missing `Does NOT promise` field" → FAIL, "missing one of three completeness subsections" → FAIL) check against a published schema rather than an implicit convention.

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
```

## Mandatory subsections

The verdict-judge's auto-FAIL rules check for these subsections by exact heading text. Producers MUST emit them with this casing and punctuation:

| Heading | Required? | Verdict-judge check |
|---|---|---|
| `### Verification command` | yes (informational) | Used to identify what the evidence comes from; not an auto-FAIL trigger |
| `### Output` | yes (informational) | Used as the actual evidence; not an auto-FAIL trigger |
| `### Does NOT promise` | **YES (auto-FAIL if missing)** | Verdict-judge Step 1 rule: "missing-non-goals" |
| `### What was tested` | yes (informational) | Used during per-criterion evaluation |
| `### What was NOT tested` | **YES (auto-FAIL if missing)** | Verdict-judge Step 1 rule: "missing-completeness-subsection" |
| `### Known limitations of this evidence` | **YES (auto-FAIL if missing)** | Verdict-judge Step 1 rule: "missing-completeness-subsection" |
| `### Negative/adversarial cases covered` | **YES (auto-FAIL if missing)** | Verdict-judge Step 1 rule: "missing-completeness-subsection" |

The four MANDATORY subsections (`Does NOT promise` plus the three completeness subsections) MUST be present even when their content is "none". The point of the format is to force the producer to make an explicit positive statement about scope and limitations rather than leaving the reader to guess. A blank section is treated identically to a missing one and triggers auto-FAIL.

## "None" is a valid answer

Each of the four mandatory subsections accepts `none` as a complete answer when the producer can affirmatively say there is nothing to disclose. The verdict-judge treats `none` as a positive statement, not a missing field. Examples:

- A config-only criterion: `### Negative/adversarial cases covered\n\nnone — this criterion is a config schema change with no defined adversarial surface.`
- A pure happy-path API addition with no failure mode in scope: `### What was NOT tested\n\nnone known — every scenario implied by the criterion was exercised by the verification command.`

The producer SHOULD include a one-clause justification for `none`. Bare `none.` is permitted but reduces auditability — a future reader cannot tell whether the producer thought about the question and concluded `none`, or skipped the question.

## Sample bundle

A complete evidence bundle for a two-criterion issue (illustrating both a code criterion with adversarial coverage and a config criterion with `none`-only completeness):

```markdown
# Evidence Bundle — Issue #142

**Branch:** feature/issue-142-rate-limit-login
**Generated:** 2026-05-06T14:22:00Z
**Acceptance criteria source:** issue #142 body, ## Acceptance Criteria section
**Total criteria:** 2

## Criterion 1: Login endpoint rejects requests after 5 failures within 60 seconds with HTTP 429

### Verification command

```bash
npm test -- --grep "rate limit login"
```

### Output

```
PASS  src/auth/__tests__/rate-limit.test.ts (3 tests, 1.4s)
  ✓ allows 5 login attempts within 60s
  ✓ rejects 6th attempt with 429 and Retry-After: 60
  ✓ resets counter after 60s elapses
```

### Does NOT promise

- Does NOT rate-limit by IP (limit is per-account)
- Does NOT rate-limit other auth endpoints (signup, password reset)

### What was tested

- 5 successful attempts within window pass through
- 6th attempt returns HTTP 429 with `Retry-After: 60` header
- Counter resets after the 60-second window elapses

### What was NOT tested

- Behavior under clock skew between application servers (multi-instance setup)
- Behavior when the rate-limit store (Redis) is unreachable

### Known limitations of this evidence

- Tests run against an in-memory rate-limit store, not the production Redis cluster. The store interface is the same but Redis-specific failure modes (TTL drift, connection pool exhaustion) are not exercised.

### Negative/adversarial cases covered

- Repeated requests with the same body (replay test): all counted toward the limit
- Concurrent requests from same account: counter increments atomically
- Header injection in Retry-After (would-be SSRF surface): tested with malformed input

## Criterion 2: New `auth.rateLimit.windowSeconds` config key is documented and validated

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
```

## Producer responsibilities

`commands/start.md` Phase 4 step 5 is responsible for assembling the bundle. The producer MUST:

1. Iterate the acceptance criteria in issue order
2. Run the verification command from the Spec Validation Gate (Phase 1) for each criterion
3. Capture stdout/stderr verbatim into `### Output`
4. Pull `### Does NOT promise` content from the specification capture in Phase 1 (the per-task `Non-goals touched` field set by `implementation-planner`)
5. Author the four completeness subsections during Phase 4, asking the user via `AskUserQuestion` (six-field escalation per `references/escalation-format.md`) when content cannot be derived from existing artifacts
6. Validate the bundle against this schema (every mandatory subsection present, `none` permitted) BEFORE dispatching `Agent(verdict-judge)` — invalid bundles are the producer's bug, not the judge's
7. Pass the validated bundle as the `Evidence Bundle` parameter in the verdict-judge dispatch (see `commands/start.md` Phase 4 step 6)

The producer never silently ships an incomplete bundle. If a mandatory subsection cannot be filled, the producer escalates per `references/escalation-format.md` rather than emitting a blank field — the auto-FAIL triggered by a blank field would surface the same gap downstream, but the escalation surfaces it earlier and with better context.

## Consumer (verdict-judge) responsibilities

`agents/verdict-judge.md` Step 1 (Missing-Criterion Scan) is the canonical consumer. The judge:

1. Parses the bundle by the `## Criterion {N}: ...` headings
2. Cross-references heading text against the acceptance criteria list (the missing-criterion scan)
3. For each criterion, checks the four mandatory subsections by exact heading match
4. Applies auto-FAIL rules per the table above
5. Carries the auto-FAIL outcome into Step 2 — locked-in FAILs are not re-evaluated for PASS

The judge does NOT receive the diff, decision journal, planning rationale, or self-review findings. The bundle is the entire universe of evidence the judge sees. This isolation is the independence contract — see `agents/verdict-judge.md` "Independence Protocol".

## Compatibility with `criterion-verification-map` skill

The `criterion-verification-map` skill (`plugins/flow/skills/criterion-verification-map/SKILL.md`) describes the per-criterion classification and command-generation that happens at PLAN time. This document describes the bundle that gets assembled at VERIFY time from the per-criterion artifacts the skill produced.

The skill's plan-time output (verification command, expected evidence shape, classification) is the input to the bundle producer. The bundle's structure is what the skill's prose described informally; this document makes it normative so producers and the verdict-judge cannot drift.
