# Verdict Output Format (verdict-judge return contract)

Reference document. The exact markdown the `agents/verdict-judge.md` agent returns to `commands/start.md` Phase 4 step 6. The command parses the `### Overall:` line to route (all PASS → completion gate; any FAIL → fix-forward; NEEDS-HUMAN-REVIEW → escalation), so the headings and the verdict vocabulary are load-bearing. The input the judge evaluates is shaped by `references/evidence-bundle-format.md`.

## Shape

The coverage scan comes FIRST, then the per-criterion verdicts, then the overall verdict and the follow-up sections.

```markdown
## Verification Verdict

### Coverage Scan

| # | Criterion | Evidence Entry Present? | "Does NOT promise" Present? | Completeness Subsections Present? | Holdout Validation Status |
|---|-----------|-------------------------|-----------------------------|-----------------------------------|---------------------------|
| 1 | {criterion text} | Yes / NO | Yes / NO | Yes / NO ({which of the five are missing}) | PASS / CONFLICT / N/A |

Orphan evidence entries (evidence with no matching criterion): {list or "none"}

### Per-Criterion Verdict

| # | Criterion | Verdict | Evidence Used | Rationale |
|---|-----------|---------|---------------|-----------|
| 1 | {criterion text} | PASS | {which evidence} | {why it proves the criterion} |
| 2 | {criterion text} | FAIL | {which evidence or "No evidence — missing-criterion scan"} | {what's wrong or missing} |
| 3 | {criterion text} | NEEDS-HUMAN-REVIEW | {which evidence} | {what's ambiguous} |

### Overall: {PASS | FAIL | NEEDS-HUMAN-REVIEW}

### Failures (if any)

{For each FAIL verdict: what specific evidence would be needed to turn this into a PASS}

### Human Review Required (if any)

{For each NEEDS-HUMAN-REVIEW: the six-field escalation — Situation / What I tried / Options / My recommendation / Blocking? / Risk if wrong — per `references/escalation-format.md`}
```

## Column semantics

| Column | Values | Meaning |
|---|---|---|
| Evidence Entry Present? | `Yes` / `NO` | A `## Criterion {N}: ...` section exists whose text matches this criterion |
| "Does NOT promise" Present? | `Yes` / `NO` | `### Does NOT promise` is present and non-blank (`none` counts as present) |
| Completeness Subsections Present? | `Yes` / `NO ({missing})` | All five of `### What was NOT tested`, `### Known limitations of this evidence`, `### Negative/adversarial cases covered`, `### Test inputs and expected values`, `### Risk map coverage` are present and non-blank; when `NO`, name the absent ones |
| Holdout Validation Status | `PASS` / `CONFLICT` / `N/A` | Whether the holdout-validation output reports a P1/P2 for this criterion (`CONFLICT`), reports nothing (`PASS`), or had no scenario for this criterion type (`N/A`) |

## Overall verdict rule

| Per-criterion verdicts | Overall |
|---|---|
| Every criterion PASS | `PASS` |
| One or more FAIL | `FAIL` |
| No FAIL, one or more NEEDS-HUMAN-REVIEW | `NEEDS-HUMAN-REVIEW` |

## Rationale vocabulary

The Rationale column uses these fixed phrases so `commands/start.md` and `/flow:status` can group failures without parsing prose. Free text follows the phrase after an em dash.

| Rationale phrase | Emitted by |
|---|---|
| `no evidence — missing-criterion scan` | Step 1: no evidence entry |
| `incomplete evidence — missing non-goals field ('Does NOT promise')` | Step 1: `### Does NOT promise` absent or blank |
| `incomplete evidence — missing {subsections}` | Step 1: one or more of the five completeness subsections absent or blank |
| `no test inputs recorded for a testable criterion` | Step 1: `### Test inputs and expected values` is `none` on a criterion whose type is not `ui` or `config` |
| `holdout-validation conflict — {finding summary}` | Step 1: P1/P2 conflict |
| `self-referential oracle` | Step 2 rule (a): expected values come from the implementation's own output or from a source the judge cannot tie to spec, reference, or hand computation |
| `degenerate inputs` | Step 2 rule (b): inputs cannot distinguish the criterion's order/position/value sensitivity |
| `risk map uncovered` | Step 2 rule (c): `### Risk map coverage` is `none` (not the disabled marker) on a behavioral/error/data/api criterion, or a mapped test's input does not distinguish the row's plausible wrong version |
| `producer non-conforming — {what deviates}` | Any step: the bundle does not follow `references/evidence-bundle-format.md`; recorded alongside the verdict so the producer bug is visible |
