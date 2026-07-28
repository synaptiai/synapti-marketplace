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

<!-- auto-log: 2026-07-28 15:49 Write /Users/danielbentes/synapti-marketplace/.flow/runs/2026-07-28T132544Z-issue-136/run.yaml -->

<!-- auto-log: 2026-07-28 15:49 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/002-fetch_issue_context.yaml -->

<!-- auto-log: 2026-07-28 15:49 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/003-specification_capture.yaml -->

<!-- auto-log: 2026-07-28 15:49 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/004-spec_validation_gate.yaml -->

<!-- auto-log: 2026-07-28 15:49 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/005-issue_assignment.yaml -->

<!-- auto-log: 2026-07-28 15:50 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/006-goal_creation.yaml -->

<!-- auto-log: 2026-07-28 15:50 Edit /Users/danielbentes/synapti-marketplace/.flow/runs/2026-07-28T132544Z-issue-136/run.yaml -->

<!-- auto-log: 2026-07-28 15:50 Edit /Users/danielbentes/synapti-marketplace/.flow/runs/2026-07-28T132544Z-issue-136/run.yaml -->

<!-- auto-log: 2026-07-28 15:52 Edit /Users/danielbentes/synapti-marketplace/.flow/runs/2026-07-28T132544Z-issue-136/run.yaml -->

<!-- auto-log: 2026-07-28 15:57 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-136.md -->

<!-- auto-log: 2026-07-28 15:59 Write /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-evidence-gate.test.sh -->

<!-- auto-log: 2026-07-28 16:00 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-evidence-gate.test.sh -->

<!-- auto-log: 2026-07-28 16:02 Write /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-vuln-evidence.sh -->

<!-- auto-log: 2026-07-28 16:02 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-07-28 16:03 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/references/evidence-ledger-schema.md -->

<!-- auto-log: 2026-07-28 16:03 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/skills/evidence-ledger/SKILL.md -->

<!-- auto-log: 2026-07-28 16:06 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/commit-15.txt -->

<!-- auto-log: 2026-07-28 16:06 commit "feat(dossier): ingest existing vulnerability-scan output as cited evidence" -->

<!-- auto-log: 2026-07-28 16:08 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-gate.sh -->

<!-- auto-log: 2026-07-28 16:08 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-gate.sh -->

<!-- auto-log: 2026-07-28 16:08 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-gate.sh -->

<!-- auto-log: 2026-07-28 16:09 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-gate.sh -->

<!-- auto-log: 2026-07-28 16:09 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-evidence-gate.test.sh -->

<!-- auto-log: 2026-07-28 16:09 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/references/release-gate-conditions.md -->

<!-- auto-log: 2026-07-28 16:09 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/references/release-gate-conditions.md -->

<!-- auto-log: 2026-07-28 16:10 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/references/release-gate-conditions.md -->

<!-- auto-log: 2026-07-28 16:10 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/references/release-gate-conditions.md -->

<!-- auto-log: 2026-07-28 16:10 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/references/release-gate-conditions.md -->

<!-- auto-log: 2026-07-28 16:11 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-07-28 16:11 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/CHANGELOG.md -->

<!-- auto-log: 2026-07-28 16:12 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/CHANGELOG.md -->

<!-- auto-log: 2026-07-28 16:15 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/commit-16.txt -->

<!-- auto-log: 2026-07-28 16:15 commit "feat(dossier): add G19 release-gate condition for unresolved vulnerabilities" -->

<!-- auto-log: 2026-07-28 16:15 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-evidence-gate.test.sh -->

<!-- auto-log: 2026-07-28 16:15 commit "test(dossier): cover G19 PASS path — Accepted risks, Risk register, clean scan, rollover-date rejection" -->

<!-- auto-log: 2026-07-28 16:16 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-evidence-gate.test.sh -->

<!-- auto-log: 2026-07-28 16:19 commit "test(dossier): cover G19 INCONCLUSIVE path — no evidence, parse-error, this repo's own package" -->

<!-- auto-log: 2026-07-28 16:19 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/references/package-contract-05-due-diligence.md -->

<!-- auto-log: 2026-07-28 16:20 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/package/05-due-diligence/assets-dependencies-and-licenses.md -->

<!-- auto-log: 2026-07-28 16:20 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/package/03-assurance/security-privacy-and-compliance.md -->

<!-- auto-log: 2026-07-28 16:20 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/package/03-assurance/testing-quality-and-delivery.md -->

<!-- auto-log: 2026-07-28 16:20 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-evidence-gate.test.sh -->

<!-- auto-log: 2026-07-28 16:21 commit "docs(dossier): require the honest no-scan-found fallback in vulnerability templates" -->

<!-- auto-log: 2026-07-28 16:22 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-evidence-gate.test.sh -->

<!-- auto-log: 2026-07-28 16:27 commit "test(dossier): end-to-end scenario proving a planted vulnerability is caught" -->

<!-- auto-log: 2026-07-28 16:43 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-gate.sh -->

<!-- auto-log: 2026-07-28 16:44 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-gate.sh -->

<!-- auto-log: 2026-07-28 16:44 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-vuln-evidence.sh -->

<!-- auto-log: 2026-07-28 16:44 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-vuln-evidence.sh -->

<!-- auto-log: 2026-07-28 16:44 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-vuln-evidence.sh -->

<!-- auto-log: 2026-07-28 16:45 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/package/04-operating/decisions-technical-debt-and-risks.md -->

<!-- auto-log: 2026-07-28 16:45 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/templates/package/04-operating/decisions-technical-debt-and-risks.md -->

<!-- auto-log: 2026-07-28 16:45 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/references/release-gate-conditions.md -->

<!-- auto-log: 2026-07-28 16:47 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-evidence-gate.test.sh -->

<!-- auto-log: 2026-07-28 16:53 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/okf-issue-body.md -->

<!-- auto-log: 2026-07-28 16:53 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/commit-review-fixes.txt -->

<!-- auto-log: 2026-07-28 16:54 commit "fix(dossier): close G19 self-review findings (F1-F7)" -->

<!-- auto-log: 2026-07-28 16:56 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-vuln-evidence.sh -->

<!-- auto-log: 2026-07-28 16:57 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-vuln-evidence.sh -->

<!-- auto-log: 2026-07-28 16:57 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/skills/evidence-ledger/SKILL.md -->

<!-- auto-log: 2026-07-28 16:58 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/references/evidence-ledger-schema.md -->

<!-- auto-log: 2026-07-28 16:58 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/skills/evidence-ledger/SKILL.md -->

<!-- auto-log: 2026-07-28 16:59 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-evidence-gate.test.sh -->

<!-- auto-log: 2026-07-28 16:59 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-evidence-gate.test.sh -->

<!-- auto-log: 2026-07-28 17:02 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/commit-holdout-fixes.txt -->

<!-- auto-log: 2026-07-28 17:02 commit "fix(dossier): close holdout-validation findings (H1-H4)" -->

<!-- auto-log: 2026-07-28 17:10 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-vuln-evidence.sh -->

<!-- auto-log: 2026-07-28 17:10 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-vuln-evidence.sh -->

<!-- auto-log: 2026-07-28 17:12 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-evidence-gate.test.sh -->

<!-- auto-log: 2026-07-28 17:15 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/8c76ed85-3c0c-4a32-8924-be0cf2c7bc2d/scratchpad/commit-independent-revalidation.txt -->

<!-- auto-log: 2026-07-28 17:15 commit "fix(dossier): fault-isolate every generator stage in vuln-evidence extraction" -->

<!-- auto-log: 2026-07-28 17:20 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/vuln-evidence-gate.test.sh -->

<!-- auto-log: 2026-07-28 17:21 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-vuln-evidence.sh -->

<!-- auto-log: 2026-07-28 17:23 commit "fix(dossier): fault-isolate Dependabot format detection itself" -->
