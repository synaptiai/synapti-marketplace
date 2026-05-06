# Finding Schema (canonical reviewer output)

Reference document. The canonical shape every reviewer agent emits, and the canonical row shape that flows into `FLOW_REVIEW_CYCLE` markers. Synthesis across the four reviewer agents (`code-reviewer`, `error-handler-inspector`, `security-reviewer`, `integration-verifier`) is a structured operation against this schema: same column set per facet, same ID grammar, same priority/category/confidence vocabulary.

`convention-checker` is intentionally NOT migrated to this schema. Convention findings (commit-message format, branch-name pattern, PR template adherence) have a different shape than file:line code findings — they are rule-vs-artifact comparisons, not bugs in code. `convention-checker` keeps its own per-rule output, and the orchestrator either surfaces convention violations separately or maps them into the canonical schema with `category=conventions` and `location=<commit-sha>` / `location=<branch-name>` when they need to live in the same finding ledger as code findings.

## Required fields

Every finding emitted by a reviewer agent MUST include these six fields:

| Field | Type | Description |
|---|---|---|
| `id` | string | Stable identifier matching `^[A-Za-z][A-Za-z0-9_-]*$`. The agent assigns it (e.g., `F1`, `F2`, `SEC-1`). The pattern is enforced by `commands/review.md` A.1 post-condition; non-conforming IDs are rejected at A.2 with a `LEDGER_WARN`. |
| `priority` | enum | `P1` (Critical, blocks merge) \| `P2` (Should Fix) \| `P3` (Consider) |
| `category` | string | Domain tag — see "Category vocabulary" below |
| `location` | string | `file:line` or `file:line-range` (e.g., `src/auth.ts:42` or `src/auth.ts:42-56`). For file-level findings (e.g., "this file lacks a README"), use `file` with no `:N` suffix. |
| `problem` | string | One-line description of the issue. Concrete enough that a reader can locate the defect without reading the full review. |
| `suggested_fix` | string | One-line proposed fix. May be empty (`—`) when the fix is non-obvious; in that case the agent should append a paragraph below the table explaining the trade-offs. |

## Optional field (added by orchestrator, not agent)

| Field | Type | Description |
|---|---|---|
| `confidence` | enum | `HIGH` (verified by running code/test, or LSP-confirmed) \| `MEDIUM` (verified by reading the code path) \| `LOW` (pattern-match only — needs investigation). Agents SHOULD assign `confidence` when they can; the orchestrator may override when consolidating across paired reviewers (Path A A.4 sets `confidence` based on the consolidation table). |

## Marker-only fields (added by `commands/review.md` Phase 4 step 7)

These two fields are NOT emitted by reviewer agents. They are stamped onto each row when the consolidated finding set is serialized into the `FLOW_REVIEW_CYCLE` marker:

| Field | Type | Description |
|---|---|---|
| `status` | enum | `open` (default — finding awaits resolution) \| `resolved` (closed in `FLOW_RESOLUTION_CYCLE` with the same ID) \| `escalated` (deferred via Proactive-Autonomy escalation) \| `disputed` (author pushed back; see resolution comment) |
| `disposition` | enum | `consensus` (both Path A lenses raised independently) \| `validated` (one raised, other AGREE'd) \| `refined` (one raised, other REFINE'd priority/category) \| `kept` (one raised, other DISAGREE'd) \| `unchallenged` (no second opinion obtained — single-session Path B, holdout-validation lens-asymmetric, or challenger errored). See `skills/team-coordination/SKILL.md` Phase 4. |

The marker pipe-separated form follows `references/finding-ledger-parser.md`:

```
F1|P1|security|src/auth.ts:42|open|HIGH|consensus
```

This is the same field order as the table columns above (id, priority, category, location, status, confidence, disposition), so the same row reads consistently in both presentations.

## Category vocabulary

Reviewers should pick from this controlled list when possible. Free-form categories are permitted but reduce searchability across the finding ledger.

| Category | Owner | Examples |
|---|---|---|
| `security` | security-reviewer | OWASP Top 10, secrets in diff, auth bypass, IDOR, missing CSRF |
| `correctness` | code-reviewer | Logic errors, off-by-one, null deref, wrong condition |
| `edge-case` | code-reviewer / error-handler-inspector | Empty input not handled, boundary value, race condition |
| `error-handling` | error-handler-inspector | Empty catch block, swallowed exception, missing fallback, generic error message |
| `performance` | code-reviewer | N+1 query, O(n²) in hot path, blocking I/O on event loop |
| `tests` | test-runner / code-reviewer | Missing test, weak assertion, brittle test, mocked thing-under-test |
| `runtime` | integration-verifier | Build failure, server startup failure, smoke-test failure, console error |
| `visual` | integration-verifier (when visual-verification ran) | Render-blocking error, layout break at viewport, missing content |
| `conventions` | convention-checker (when surfaced into ledger) | Non-conforming commit format, branch-name pattern violation |
| `claim-verification` | holdout-validation | Self-review claim contradicted by file state |

## Output format (per reviewer agent)

Every reviewer agent's output section uses three priority-ordered tables plus a summary:

```markdown
## {Reviewer} Findings

### P1 — Critical (Blocks Merge)
| ID | Category | Location | Problem | Suggested Fix | Confidence |
|----|----------|----------|---------|---------------|------------|
| F1 | security | src/auth.ts:42 | SQL injection via string interpolation | Use parameterized query (`$1`, `$2`) | HIGH |

### P2 — Should Fix
| ID | Category | Location | Problem | Suggested Fix | Confidence |
|----|----------|----------|---------|---------------|------------|

### P3 — Consider
| ID | Category | Location | Problem | Suggested Fix | Confidence |
|----|----------|----------|---------|---------------|------------|

### Summary
- Files reviewed: {N}
- Total findings: P1: {X}, P2: {Y}, P3: {Z}
- Recommendation: APPROVE | COMMENT | REQUEST_CHANGES
```

Empty priority sections SHOULD be retained as-is (just the header + table header) so consumers can tell "no findings at this priority" apart from "this priority section was forgotten". The summary line counts MUST match the row counts in the tables — this is the cheapest invariant to spot-check during synthesis.

## ID grammar

IDs are reviewer-assigned and MUST match `^[A-Za-z][A-Za-z0-9_-]*$`. Recommended conventions:

| Reviewer | Prefix | Example |
|---|---|---|
| code-reviewer | `F` | `F1`, `F2`, `F3` |
| security-reviewer | `SEC-` | `SEC-1`, `SEC-2` |
| error-handler-inspector | `ERR-` | `ERR-1`, `ERR-2` |
| integration-verifier | `INT-` | `INT-1`, `INT-2` |

Prefixes are optional but help downstream readers identify provenance from the ID alone. The orchestrator does NOT renumber IDs across reviewers — collisions across reviewers (e.g., both code-reviewer and security-reviewer assigning `F1`) must be disambiguated by the orchestrator at synthesis time, ideally by prefixing the reviewer's first-letter (`C-F1`, `S-F1`).

## Confidence guidance

Reviewers assign confidence based on the strength of their signal:

| Signal type | Confidence |
|---|---|
| Verified by running code/test that exercises the defect | HIGH |
| LSP diagnostic (error/warning from language server) | HIGH |
| LSP `findReferences` confirmed all callers are or are not handled | HIGH |
| Verified by reading the full code path | MEDIUM |
| Pattern-match only (looks like a bug, fits a known anti-pattern) | LOW (only flag at P1 with explicit `needs investigation` note) |
| Style preference, naming, formatting | N/A — only as P3, never blocks merge |

Per `skills/code-review-methodology/SKILL.md`: only P1 findings with HIGH confidence should block merge.

## What this schema does NOT cover

- **Verdict output** — `verdict-judge` produces verdicts (PASS/FAIL/NEEDS-HUMAN-REVIEW) per acceptance criterion, not findings. See `references/evidence-bundle-format.md` for the verdict-judge input contract.
- **Convention violations as their own surface** — `convention-checker` may emit per-rule output (commit-format pass/fail, branch-name match) that does not naturally map to `file:line`. When such violations need to enter the finding ledger, the orchestrator wraps them with `category=conventions` and a synthetic `location` (commit SHA, branch name).
- **Cross-cycle resolution state** — that lives in `FLOW_RESOLUTION_CYCLE` markers, parsed per `references/finding-ledger-parser.md`. The `status` field on a finding row is a pointer into the resolution-cycle ledger, not a substitute for it.

## Compatibility

- The `FLOW_REVIEW_CYCLE` marker schema (`references/finding-ledger-parser.md`) tolerates 5-field (legacy) and 7-field (with confidence + disposition) rows. Path B emits 5-field; Path A emits uniformly 7-field. This schema is the normative reference for which fields are which.
- Existing `tests/issue-86/markers/*.txt` fixtures continue to parse without changes — the schema documented here matches the fixture shapes and the parsers in `commands/merge.md` and `commands/status.md`.
