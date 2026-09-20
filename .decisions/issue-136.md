---
issue: 136
created: '2026-07-28T13:42:28Z'
artifacts:
- type: specification
  captured_at: '2026-07-28T13:42:28Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
- type: goal-created
  captured_at: '2026-07-28T13:44:15Z'
  goal_id: issue-136
  source: github_issue
- type: goal-created
  captured_at: '2026-07-28T13:44:47Z'
  goal_id: issue-136
  source: github_issue:136
- type: workflow-run
  captured_at: '2026-07-28T13:49:15Z'
  workflow: start-issue
  run_id: 2026-07-28T132544Z-issue-136
  status: active
- type: stranger-test
  captured_at: '2026-07-28T13:56:59Z'
  result: PASS
  task_count: 6
- type: workflow-run
  captured_at: '2026-07-28T15:35:27Z'
  workflow: start-issue
  run_id: 2026-07-28T132544Z-issue-136
  status: completed
- type: goal-evaluation
  captured_at: '2026-07-28T15:42:44Z'
  goal_id: issue-136
  result: achieved
  evidence_bundle: .flow/runs/2026-07-28T132544Z-issue-136
  failures: none
- type: review-cycle
  captured_at: '2026-07-28T16:06:09Z'
  cycle: 1
  path: B
  findings_count: 17
  pr: 141
- type: workflow-run
  captured_at: '2026-07-28T16:08:21Z'
  workflow: review-pr
  run_id: 2026-07-28T160627Z-review
  status: active
- type: review-cycle
  captured_at: '2026-07-28T17:00:16Z'
  cycle: 1
  path: A
  findings_count: 17
  pr: 141
- type: resolution-cycle
  captured_at: '2026-07-28T17:00:16Z'
  cycle: 1
  resolved_count: 17
  escalated_count: 0
  disputed_count: 0
  pr: 141
- type: workflow-run
  captured_at: '2026-07-28T17:09:54Z'
  workflow: merge-pr
  run_id: 2026-07-28T170210Z-merge-pr-141
  status: completed
  pr: 141
  merge_commit: 2982034
---
# Decision Journal — Issue #136

**Title**: dossier: ingest known dependency vulnerabilities as cited evidence, with a release-gate condition for unresolved severe findings
**Branch**: feature/issue-136-vulnerability-evidence-gate
**Started**: 2026-07-28

Part 2 of 4 in the dossier post-merge/investor-doc-gap initiative (plan: `the-dossier-plugin-is-federated-toucan`). Part 1 (#135, PR #139) is shipped and released as v4.8.0. Epics 3-4 (#137, #138) are separate, sequential work.

## Specification

_Captured by specification-capture skill on 2026-07-28. Source: user-confirmed (design resolved by reading `dossier-gate.sh`, `release-gate-conditions.md`, `finding-schema.md`, and the existing package templates directly, then confirmed with the user via AskUserQuestion on the one materially ambiguous point)._

### Non-goals

- Scanner execution (`osv-scanner`, `pyscn`, or any other tool) — entirely out of scope; that's issue #137. This issue ingests only pre-existing scan output already present in the target project, via the `Read` tool.
- Regulatory-compliance checklists (SOC2/GDPR/ISO27001) — dropped from the whole 4-part initiative, not deferred to this issue.
- Any change to G01–G18's existing logic, order, or the FAIL > INCONCLUSIVE > PASS precedence computation in `dossier-gate.sh` — G19 is purely additive.
- Any new package-level table in the 23 canonical documents — this issue only adds fill-instructions to existing tables (05-due-diligence's Vulnerability evidence table, 03-assurance's Dependency scanning rows) and reuses the existing Risk register / Accepted risks tables in `04-operating/decisions-technical-debt-and-risks.md`.
- Reusing G03/`findings.md` for vulnerability findings — architecturally wrong per `finding-schema.md`'s explicit rule that a project defect ("A finding about a project defect rather than a documentation defect is out of scope for every pass") belongs in the risk register, not the finding ledger.
- Rotation/telemetry (issue #138) — untouched.
- Widening `engagement.allowedActions` — no new action class; ingestion is Read-tool only, no network access.
- Exploit-chain detail, affected-version specifics beyond package+version+severity, or any content the existing "Vulnerability evidence" table's hard rule already prohibits ("Counts and severities only; detail lives with the security owner").

### Failure modes

- **Timeouts** — none: this issue performs no network calls or long-running scans (Read-tool only, on files already present in the working tree).
- **Partial failures** — a scan artifact that parses partially (some records malformed) must record what parsed as evidence and flag the unparsed portion in the evidence ledger's existing "Unavailable evidence" section — never silently drop it or treat partial parse as complete coverage.
- **Invalid input** — a scan-artifact parse failure (malformed JSON/SARIF, unsupported format) must produce an explicit "could not parse" signal that flows to G19 as `INCONCLUSIVE` (or an evidence-ledger `U`-row), never as "zero findings therefore clean" — mirrors the ERR-3 fix pattern already shipped this session in `dossier-policy.sh`/`dossier-evidence.sh` (a delegate failure must never masquerade as a clean result).
- **Missing context** —
  (a) No scan artifact present at all: G19 reports `INCONCLUSIVE` (confirmed design decision below), and the evidence ledger records this via its existing "Unavailable evidence" section, never simply omitted.
  (b) A target/review date field in the Risk register or Accepted risks table that is calendar-invalid or a rollover date (e.g. `2026-06-31`) must be rejected/flagged, not silently normalized to a nearby valid date — reuse `validate_calendar_date()` from `dossier-staleness-check.sh` rather than reimplementing.
  (c) A scan artifact read from repository content is untrusted input (a fork PR could plant a forged file). This issue's scope is drafting-time use (interactive `/dossier:refresh` or `/dossier:baseline`), not an unattended CI path, so full untrusted-content manifest marking (as `dossier-evidence.sh` already does for repository-sourced content) is a documented constraint for whoever later wires any CI-facing consumer, not an implementation requirement of this issue.

### Interface contracts

- **`dossier-gate.sh`**: gains a `G19` mechanical condition appended to the existing sequential mechanical-checks block, using the exact `record G19 mechanical <PASS|FAIL|INCONCLUSIVE> script "<evidence>"` call already used by every other mechanical condition. `JUDGMENT_IDS` (currently `G01 G02 G04 G07 G13 G14 G15`) is unchanged — G19 is mechanical, not judgment. `release-gate-conditions.md`'s condition-count prose ("Eleven conditions are mechanical; seven are judgment", "eighteen conditions") and its conditions table both need updating to twelve mechanical / nineteen total.
- **`00-control/evidence-ledger.md`**: vulnerability findings are ordinary `EV-####` rows in the existing Evidence table — no schema change. One row for what was scanned (scope/tool/date), one row per material (Critical/High) finding — never force-collapsed into a single aggregate row. Medium/Low findings and scan-coverage summaries may be aggregated. Convention: the `Notes` column carries a machine-parseable tag for vulnerability rows so G19 can find them without misclassifying ordinary claims (exact tag grammar decided during PLAN/CODE; constraint is "grep-able, unambiguous, documented in `evidence-ledger-schema.md`").
- **`04-operating/decisions-technical-debt-and-risks.md`**: vulnerability disposition uses the existing Risk register (`Category` = `dependency` or `security`) and Accepted risks table, unmodified schema. G19 cross-references a vulnerability `EV-####` row's disposition by locating a Risk register or Accepted risks row that cites it via the existing `Evidence` column's `[EV-####]` citation convention.
- **New ingestion entry point**: a script (exact name decided during PLAN, e.g. `dossier-vuln-evidence.sh`) that reads a scan artifact path, detects its format (SARIF / osv-scanner JSON / Dependabot export), and emits normalized evidence rows — Read-tool-only, no scanner execution, no network access.
- **`05-due-diligence/assets-dependencies-and-licenses.md`**'s Vulnerability evidence table and **`03-assurance/security-privacy-and-compliance.md`** + **`03-assurance/testing-quality-and-delivery.md`**'s Dependency scanning rows: fill-instruction updates only (guidance in the corresponding `references/package-contract-*.md` files on how to fill the existing cells given the new ingestion path), zero column/table changes.
- **`release-gate-conditions.md`**: gains a `### G19` section following the exact prose contract shape of G03/G06 (Tag, Check, Evidence that satisfies it, Fails when).

### Resolved design decision: G19's no-evidence state

Confirmed with the user via `AskUserQuestion` on 2026-07-28: when a package has **zero vulnerability-evidence `EV-####` rows at all**, G19 reports **`INCONCLUSIVE`**, never `PASS`. This matches commit `525cca5` ("#133")'s established precedent that an unevaluated condition must never read as assent, and mirrors G06's own INCONCLUSIVE-on-could-not-run behavior. This is a **deliberate, confirmed deviation** from the original plan document's text ("existing installations are unaffected... condition has nothing to evaluate"), accepted knowing it changes gate status — to `not ready` — for every existing dossier package (including this repo's own `docs/dossier`) until vulnerability evidence is ingested. The overall `GATE_RESULT` computation already treats `INCONCLUSIVE` as blocking (`STATUS=not ready`) exactly like every other uncovered condition today; no change needed to that precedence logic.

### Resolved design decisions: PR #141 review cycle (2026-07-28)

`/flow:review`'s Path A paired-reviewer protocol (10 agents + 2 holdout lenses) surfaced three points this journal had not explicitly resolved during specification — resolved here rather than deferred, per self-review mode's fix-forward mandate:

- **Unresolved severity now factors into the FAIL/PASS/INCONCLUSIVE decision, not just PASS/FAIL.** The original interface contract (above) only specified disposition-checking for confirmed `Critical`/`High` rows; it did not say what a `vuln-finding-unresolved` row (severity undeterminable) should do to the result when zero confirmed rows exist alongside it. Three independent reviewers (code-reviewer-verifier, security-reviewer-skeptic, security-reviewer-verifier) reproduced a scan that parsed cleanly (`status=parsed`, not `partial`) but whose one finding had unresolved severity, and zero confirmed Critical/High rows — G19 reported a vacuous `PASS`. Resolved: `INCONCLUSIVE`, same "materiality unknown must never read as assent" principle already governing the no-evidence and parse-error branches. `references/evidence-ledger-schema.md` and `references/release-gate-conditions.md` updated in the same commit as the code fix.
- **A `Status: accepted` disposition in the Risk register alone no longer qualifies — it must go through the Accepted risks table.** This is a genuine, deliberate contract change, not a bug fix: the Risk register's `Status` column has always documented `accepted` as a valid enum value (`templates/package/04-operating/decisions-technical-debt-and-risks.md`), so a package filled exactly as previously documented will now `FAIL` where it previously `PASS`ed. Made anyway because the template's own Accepted-risks section states "acceptance requires a named human with the authority to accept" — a bare `Owner` cell in the Risk register does not establish that authority, only that someone is tracking the item. Single-sourced by code-reviewer-verifier (F3); taken as the right call because it closes a real accountability gap the Status-allowlist fix (below) would otherwise have left open, and because the template's own stated rule already implied it. Template guidance and `release-gate-conditions.md` updated in the same commit.
- **An Accepted-risks `Review date` must not have elapsed, not merely be calendar-valid.** The original failure-mode note (above) only specified rejecting a calendar-invalid or rollover date; it did not address a calendar-valid date from years in the past. Two independent reviewers (security-reviewer-verifier, error-handler-inspector-skeptic) reproduced a 2020 review date still disposing a Critical finding today. This journal's silence on the elapsed case was an oversight, not a considered exclusion — resolved by requiring `Review date >= today`, matching this project's own established staleness-enforcement philosophy (`dossier-staleness-check.sh`) rather than inventing a new one.

Also fixed in the same review cycle, without a design-decision-level resolution needed (implementation bugs, not contract questions): a jq optional-index operator silently discarding a whole finding record instead of throwing (F1/ERR-1, five agents); a Risk register `Status` denylist of the single string `"open"` instead of an allowlist against the documented enum, letting case variants and unfilled `{fill}` placeholders through as false dispositions (F2, five agents); `Category`/`Status` case-sensitivity (F5/SEC-4); unfilled `{fill}` placeholders accepted in Accepted-risks `Accepted by`/`Basis for acceptance` cells (F4); a citation-range regex that misread the schema-legal comma-separated list form as an inclusive range (ERR-2); a `vuln-finding` row whose tag formatting drifted beyond mere case going completely unevaluated instead of flagged (ERR-3); and an unreadable (vs. absent) risk register file reading as an ordinary `FAIL` instead of a distinct `INCONCLUSIVE` (ERR-6).

## Stranger Test

**PASS — 6 tasks reviewed.**

Tasks #15-#20, one per acceptance criterion (AC3 and AC4's gate half are test-only tasks against G19's shared implementation, per the issue's explicit "atomic unit per AC, shared code via `addBlockedBy`" instruction; AC4 is split into a gate half (#18) and a template half (#19), each with an explicit cross-reference to the other so neither silently assumes the other's coverage):

| # | Task | Blocked by |
|---|---|---|
| #15 | Ingestion script + evidence-row emission + skill wiring (AC1) | — |
| #16 | G19 mechanical condition, full FAIL/PASS/INCONCLUSIVE logic + doc/count sweep (AC2) | #15 |
| #17 | G19 PASS-path tests (AC3) | #16 |
| #18 | G19 INCONCLUSIVE-path tests, gate half of AC4 | #17 |
| #19 | Template fill-instructions, template half of AC4 | #15 |
| #20 | Full-suite regression + planted-vulnerability end-to-end scenario (AC5) | #15, #16, #17, #18, #19 |

Each task description was checked for: every file path confirmed present by direct read this session (no inferred paths); every interface contract specified rather than deferred (the Notes-column tag grammar, the G19 four-branch decision table, and the disposition-lookup rule are given verbatim, not left to the implementer to re-derive); every verification method is a runnable `bash plugins/dossier/tests/run.sh <file>` command, not a judgment call (task #19's verification was tightened from a soft "note if not covered" to two concrete `grep`-based assertions after advisor review); and known non-obvious blockers this session's own reading surfaced are named explicitly rather than left for the implementer to rediscover — the `bin-scripts.test.sh` hardcoded `"18"` condition count, the `CHANGELOG.md` historical "eighteen conditions" phrase that trips the automated count-consistency check unless reworded to the digit form, and the pre-existing stale "sixteen other conditions" phrase in G17's own section.

Accepted consequence, worth surfacing here rather than only in the resolved-design-decision section above: once #16 lands, `docs/dossier` (this repo's own generated package, confirmed present at `/Users/danielbentes/synapti-marketplace/docs/dossier/`) goes to gate status `not ready` on G19 and stays there until someone ingests vulnerability evidence into it. This is the correct, honest behavior per the confirmed design decision, not a regression to fix within this issue.
