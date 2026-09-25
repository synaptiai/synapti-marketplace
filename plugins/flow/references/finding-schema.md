# Finding Schema (canonical reviewer output)

Reference document. The canonical shape every reviewer agent emits, and the canonical row shape that flows into `FLOW_REVIEW_CYCLE` markers. Synthesis across the four reviewer agents (`code-reviewer`, `error-handler-inspector`, `security-reviewer`, `integration-verifier`) is a structured operation against this schema: same column set per facet, same ID grammar, same priority/category/confidence vocabulary.

`convention-checker` is intentionally NOT migrated to this schema. Convention findings (commit-message format, branch-name pattern, PR template adherence) have a different shape than file:line code findings — they are rule-vs-artifact comparisons, not bugs in code. `convention-checker` keeps its own per-rule output, and the orchestrator either surfaces convention violations separately or maps them into the canonical schema with `category=conventions` and `location=<commit-sha>` / `location=<branch-name>` when they need to live in the same finding ledger as code findings.

## Required fields

Every finding emitted by a reviewer agent MUST include these seven fields:

| Field | Type | Description |
|---|---|---|
| `id` | string | Stable identifier matching `^[A-Za-z][A-Za-z0-9_-]*$`. The agent assigns it (e.g., `F1`, `F2`, `SEC-1`). The pattern is enforced by `commands/review.md` A.1 post-condition; non-conforming IDs are rejected at A.2 with a `LEDGER_WARN`. |
| `priority` | enum | `P1` (Critical, blocks merge) \| `P2` (Should Fix) \| `P3` (Consider) |
| `category` | string | Domain tag — see "Category vocabulary" below |
| `location` | string | `file:line` or `file:line-range` (e.g., `src/auth.ts:42` or `src/auth.ts:42-56`). For file-level findings (e.g., "this file lacks a README"), use `file` with no `:N` suffix. |
| `problem` | string | One-line description of the issue. Concrete enough that a reader can locate the defect without reading the full review. |
| `suggested_fix` | string | One-line proposed fix. May be empty (`—`) when the fix is non-obvious; in that case the agent should append a paragraph below the table explaining the trade-offs. |
| `confidence` | enum | `HIGH` \| `MEDIUM` \| `LOW`, assigned under the three-tier rule in "Confidence guidance" below and rendered as a trailing `_(HIGH)_` suffix on the Finding cell. Confidence decides what a finding may demand (`skills/code-review-methodology/SKILL.md` § Confidence and signal); it never changes `priority`. |

## Absent or invalid confidence

A finding whose confidence is missing, or is anything other than HIGH, MEDIUM or LOW in any letter case, is treated as MEDIUM: never LOW, which would silently drop it from the review decision, and never HIGH. `bin/flow-finding-route.sh` applies the rule and prints one warning per finding on stderr:

```
LEDGER_WARN: PR#<N> finding '<id>' from <agent> has no confidence — treated as MEDIUM
LEDGER_WARN: PR#<N> finding '<id>' from <agent> has invalid confidence '<value>' — treated as MEDIUM
```

Findings from producers outside this schema (holdout-validation, and convention-checker or test-runner rows mapped into the ledger) are stamped MEDIUM by the orchestrator before routing when they carry no confidence of their own, so the warning names only a schema agent that left out confidence. A confidence Path A's consolidation assigned, such as HIGH for a holdout finding both lenses raised, is kept. The orchestrator may still change an agent's confidence when it consolidates paired reviewers: Path A A.4 assigns confidence from the consolidation table.

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

This is the same field order as the table columns above (id, priority, category, location, status, confidence, disposition), so the same row reads consistently in both presentations. In a marker row, `category` and `location` are percent-encoded outside `[A-Za-z0-9._~/:@+= -]`, so `app/[id]/page.tsx:4` is written `app/%5Bid%5D/page.tsx:4`; a comma, `]`, `|` or `>` would otherwise split the row or end the marker. The rendered tables keep the original text.

## Grounding (added by the grounding pass, when `review.groundingCritic` is `on`)

| Field | Type | Description |
|---|---|---|
| `grounding` | enum | `agreed` (the `finding-critic` answered `AGREE`) \| `cited` (the critic disagreed and the originating reviewer answered with a `file:line` that holds) |

A `cited` finding is stamped confidence HIGH: the critic disagreed, and the reviewer answered
with a citation that holds. An `agreed` finding keeps the confidence synthesis gave it,
because `AGREE` is the critic's default verdict and means "the finding is right, **or** I
could not refute it" — an unrefuted LOW pattern-match must not become a merge blocker on the
strength of silence. A finding the critic never reached, or answered off-grammar, carries no
`grounding` at all and also keeps the confidence synthesis gave it — absence means "not
audited", never "failed the audit". Findings the reviewer could not defend with a citation are not stamped: they are
dropped, and journaled as `dropped-finding` with `reason=critic-evidence` or
`reason=critic-unrefuted-concern` (`references/decision-journal-schema.md`).

`grounding` is **not** a marker field. The `FLOW_REVIEW_CYCLE` row keeps its seven fields and
the rendered Finding cell keeps its two-term `_(CONFIDENCE · disposition)_` suffix, because
`bin/flow-finding-route.sh`, `commands/merge.md` and `commands/status.md` parse both. The
field lives in the consolidated finding set during the review and in the decision journal
afterwards. P3 findings never enter the critic, so they never carry it. The pass itself is
`commands/review.md` Phase 4 and `commands/pr.md` Phase 4; Path A's challenge round is
unchanged and produces `disposition`, not `grounding`.

## Category vocabulary

Reviewers should pick from this controlled list when possible. Free-form categories are permitted but reduce searchability across the finding ledger.

| Category | Owner | Examples |
|---|---|---|
| `security` | security-reviewer | OWASP Top 10, secrets in diff, auth bypass, IDOR, missing CSRF |
| `dependency` | security-reviewer | A package this change adds or bumps: a critical or high advisory with a fix available, a license the project's declared license cannot include, an install hook, a name within edit distance 2 of an existing dependency, or a package nothing imports. The location is where `bin/flow-dep-diff.sh` printed it: the manifest `file:line` for a line-oriented manifest, and the file alone for a TOML one, whose parser returns values without the lines they came from. |
| `correctness` | code-reviewer | Logic errors, off-by-one, null deref, wrong condition |
| `edge-case` | code-reviewer / error-handler-inspector | Empty input not handled, boundary value, race condition |
| `error-handling` | error-handler-inspector | Empty catch block, swallowed exception, missing fallback, generic error message |
| `performance` | code-reviewer | N+1 query, O(n²) in hot path, blocking I/O on event loop |
| `tests` | test-runner / code-reviewer | Missing test, weak assertion, brittle test, mocked thing-under-test |
| `runtime` | integration-verifier | Build failure, server startup failure, smoke-test failure, console error |
| `visual` | integration-verifier (when visual-verification ran) | Render-blocking error, layout break at viewport, missing content |
| `breaking-change` | code-reviewer | A changed contract — exported signature, schema, migration, OpenAPI, GraphQL, protobuf, or a symbol in the goal's interface contracts — with a consumer this pull request does not update. The finding cites the consumer's `file:line`, not the contract's. Cross-repository consumers are out of scope. |
| `duplication` | code-reviewer | A block this change introduced that already exists elsewhere in the repository, found verbatim by `bin/flow-clone-scan.sh`, or a new symbol that reimplements behaviour an existing one already provides, found by the reviewer's Reuse check. The location is the **added** side — the block whose author can act on it — and the problem text names the existing block. P2 when the duplicated code already existed, P3 when both copies are inside this change. A verbatim match is a fact, so Layer A findings are HIGH; a judged reimplementation is MEDIUM and carries `candidates examined: N`. |
| `scope` | code-reviewer | A change that implements something the specification lists as a non-goal, or a pull request that weakens the goal it is being reviewed against. The finding cites the change, and names the non-goal or the criterion it contradicts. |
| `conventions` | convention-checker (when surfaced into ledger) | Non-conforming commit format, branch-name pattern violation |
| `claim-verification` | holdout-validation | Self-review claim contradicted by file state |

## Output format (per reviewer agent)

Findings are rendered as a **two-column table** so they stay legible in GitHub's narrow PR-comment
column. Previously a 6-column table (`ID | Category | Location | Problem | Suggested Fix | Confidence`) collapsed
on GitHub: each prose cell wraps one word — sometimes one character — per line, stacking `category`
vertically and breaking `location` mid-path. Two columns give each prose column ~half the width, so
the short metadata (id, category, location, confidence, disposition) is packed into the first cell and
the two prose fields (problem, suggested_fix) each get a full column.

This is a **rendering** decision only. The data model is the fields above, and the `FLOW_REVIEW_CYCLE`
marker is pipe-delimited 7-field rows on both review paths (parsers still accept legacy 5-field rows —
see `references/finding-ledger-parser.md`). Do not confuse the rendered table's two columns with the
marker's field count; they are independent.

Every reviewer agent's output section uses three priority-ordered tables plus a summary:

```markdown
## {Reviewer} Findings

### P1 — Critical (Blocks Merge)
| Finding | Suggested Fix |
|---------|---------------|
| **F1 · security · `src/auth.ts:42`**<br>SQL injection via string interpolation. _(HIGH)_ | Use parameterized query (`$1`, `$2`). |

### P2 — Should Fix
| Finding | Suggested Fix |
|---------|---------------|

### P3 — Consider
| Finding | Suggested Fix |
|---------|---------------|

### Summary
- Files reviewed: {N}
- Total findings: P1: {X}, P2: {Y}, P3: {Z}
- Recommendation: APPROVE | COMMENT | REQUEST_CHANGES
```

Cell construction:
- **Finding cell, line 1 (bold):** `{ID} · {category} · `{location}``. Priority is NOT repeated in
  the cell — the `### P1/P2/P3` section header already carries it.
- **Finding cell, line 2** (after `<br>`): the `problem` prose.
- **Confidence + disposition:** agents end the Finding cell with `_(HIGH)_`, `_(MEDIUM)_` or `_(LOW)_`.
  The posted review renders `_(HIGH · consensus)_` on both paths; Path B's disposition is `unchallenged`.
  On someone else's pull request a LOW finding is not rendered in the priority tables: it is listed
  under `Needs investigation` (`commands/review.md` Phase 4 step 6). (These replace the old
  `Confidence` and `Disposition` columns.)
- **Needs investigation entry:** `- **{ID} · {priority} · {category} · `{location}`** — {problem}`,
  with the routed priority in the second position and no confidence suffix. A counted finding, in a
  table or a P3 bullet, opens `**{ID} · {category} · ` instead. The two shapes are what the posting
  block checks: a LOW id appears exactly once, in the entry shape at its routed priority, and no
  line in the body carries a `_(LOW` suffix.
- **Suggested Fix cell:** the `suggested_fix` prose, or `—` when non-obvious (then append a
  `**{ID} context:** …` paragraph below the table explaining the trade-off, as before).

**Pipe escaping (required):** any literal `|` inside a cell MUST be written `\|` or kept inside a code
span. Findings routinely quote shell pipes (`grep \| head`); an unescaped `|` silently breaks the row
into extra columns.

Empty priority sections SHOULD be retained as-is (just the header + the `| Finding | Suggested Fix |`
header row) so consumers can tell "no findings at this priority" apart from "this priority section was
forgotten". The summary line counts MUST match the row counts in the tables — this is the cheapest
invariant to spot-check during synthesis.

## ID grammar

IDs are reviewer-assigned and MUST match `^[A-Za-z][A-Za-z0-9_-]*$`. Recommended conventions:

| Reviewer | Prefix | Example |
|---|---|---|
| code-reviewer | `F` | `F1`, `F2`, `F3` |
| security-reviewer | `SEC-` | `SEC-1`, `SEC-2` |
| security-reviewer (dependency judgment) | `DEP-` | `DEP-1`, `DEP-2` |
| code-reviewer (duplication) | `DUP-` | `DUP-1`, `DUP-2` |
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
| Pattern-match only (looks like a bug, fits a known anti-pattern) | LOW, at any priority: listed under Needs investigation and never decides the review |
| Style preference, naming, formatting | N/A — only as P3, never blocks merge |

How confidence enters the review decision: `skills/code-review-methodology/SKILL.md` § Review decision. HIGH and MEDIUM findings decide at their priority; LOW findings never do.

## What this schema does NOT cover

- **Verdict output** — `verdict-judge` produces verdicts (PASS/FAIL/NEEDS-HUMAN-REVIEW) per acceptance criterion, not findings. See `references/evidence-bundle-format.md` for the verdict-judge input contract.
- **Convention violations as their own surface** — `convention-checker` may emit per-rule output (commit-format pass/fail, branch-name match) that does not naturally map to `file:line`. When such violations need to enter the finding ledger, the orchestrator wraps them with `category=conventions` and a synthetic `location` (commit SHA, branch name).
- **Cross-cycle resolution state** — that lives in `FLOW_RESOLUTION_CYCLE` markers, parsed per `references/finding-ledger-parser.md`. The `status` field on a finding row is a pointer into the resolution-cycle ledger, not a substitute for it.

## Compatibility

- The `FLOW_REVIEW_CYCLE` marker schema (`references/finding-ledger-parser.md`) tolerates 5-field (legacy) and 7-field (with confidence + disposition) rows. Both review paths write 7-field rows through `bin/flow-finding-route.sh`; Path B rows carry disposition `unchallenged`, and no LOW row is written. This schema is the normative reference for which fields are which.
- Existing `tests/issue-86/markers/*.txt` fixtures continue to parse without changes — the schema documented here matches the fixture shapes and the parsers in `commands/merge.md` and `commands/status.md`.
