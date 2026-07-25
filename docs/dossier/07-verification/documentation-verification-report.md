---
dossier-header: internal-v1
title: Documentation Verification Report
purpose: Tells a reader how much this package's own claims are worth, by recording what was checked, what was found, and what could not be established.
audience: Reviewer, Maintainer
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: d0fa737
last-verified: 2026-07-26
review-trigger: Any re-run of the verification passes, or any correction applied to a document after this report was written
related: [00-control/evidence-ledger.md, 00-control/assumptions-questions-and-contradictions.md, 00-control/claim-and-disclosure-register.md, 05-due-diligence/technical-due-diligence-report.md]
---
# Documentation Verification Report
<!-- contract: references/package-contract-07-verification.md#documentation-verification-report -->

## Scope

| Field | Value |
|---|---|
| Package version verified | 1.0.0 |
| Project version or commit | `d0fa737` on `feature/dossier-documentation-plugin` |
| Evidence cutoff | 2026-07-26 |
| Verification date | 2026-07-26 |
| Documents in scope | All 23 canonical files |
| Documents out of scope and why | None. This report verifies itself only for mechanics — a pass cannot audit its own findings |
| Round | 1 |

## Reviewer-pass independence method

| Field | Value |
|---|---|
| Passes run | A, B, C |
| Execution mode | **single context with reset frames** |
| Model per pass | Identical. All three passes ran on the same model, in the same session, with the same context |
| Did any pass read another pass's findings before producing its own | **Yes, unavoidably.** All three ran in one context. Pass B could see Pass A's output, and Pass C could see both |
| External audit performed | no |
| Residual correlation risk | **High, and this is the largest single weakness of this verification.** The dossier plugin's design makes independence architectural — separate agent dispatches, `memory: none`, a skill firewall keeping reconciliation logic out of every verifier's context, single-message dispatch, and per-pass model configuration. **None of those mechanisms was used here.** This run was performed inline, so the three passes share priors completely. A blind spot in one is a blind spot in all three, and the mutual confirmation between passes carries close to zero information |

Model diversity: none. All passes used the session model.

Stating this plainly rather than describing three passes as if they were independent is the point of the section. What the passes did achieve is *method* diversity — Pass A checked referential integrity mechanically, Pass B re-derived every headline number from the filesystem without consulting the ledger, and Pass C compared repeated facts across documents. Those are genuinely different procedures, and Pass B's re-derivation is what caught the one substantive defect. What they did not achieve is *reviewer* independence.

## Checks performed

| Check | Method | Scope | Result | Evidence |
|---|---|---|---|---|
| Canonical file presence | `dossier-package-check.sh` | 23 files | pass — 23 of 23 present | `CHECK_FILES_PRESENT=23` |
| Header completeness | Same, shell frontmatter parser | 23 files | pass after correction — 21 of 23 complete at first run, both gaps filled | `CHECK_HEADERS_OK` |
| Contract pointer resolution | Same — body line 2 resolved to a real anchor in a real reference | 23 files | pass — 23 of 23 | `CHECK_POINTERS_CHECKED=23` |
| Internal link resolution | `test -f` on every package-relative path named in prose, plus every `related:` entry | 23 files | pass — 0 dangling of both kinds | Pass C |
| Diagram syntax | Python parse of every mermaid block: header form, bracket and quote balance, parentheses inside node labels | 3 blocks | pass | Pass C |
| Diagram versus inventory agreement | Every edge in the context diagram mapped to a row in the accompanying table | 3 blocks, 7 edges | pass | Pass C |
| Evidence citation coverage | Set difference between `EV-####` defined in the ledger and referenced anywhere | 54 IDs | pass — 0 dangling, 0 orphaned | Pass A |
| Register referential integrity | Same for `AQ`, `CT`, `CL`, `TM` | 10 / 4 / 19 / 25 | pass — 0 dangling in all four | Pass A |
| Ledger locator resolution | `dossier-ledger-lint.sh` — 13-column shape, ID uniqueness, state and authority enums, locator resolution at authority 1–3, public-use gating | 54 rows | pass after correction — 82 errors at first run, 0 now | See F-06, F-07 |
| Public claim mapping | `dossier-claim-scan.sh` against the approved register | 2 public files | **findings — 52 unregistered sentences** | See F-03 |
| Secret and sensitive-material scan | Same tool: 12 credential pattern classes plus internal locators | 2 public files | pass after correction — 34 leaks found and fixed | See F-02 |
| Command and example execution | Every command in the package executed and its real output recorded | 26 of 28 | pass — the 2 unexecuted are named with reasons | Ledger executed-checks table |
| Terminology consistency | Every entity named in prose checked against the terminology register | 25 `TM-` entries | pass | Pass C |
| Cross-document fact agreement | Every repeated number grepped across all 23 files and its occurrences counted | 12 recurring figures | **1 finding, corrected** | See F-01 |
| Headline-number re-derivation | Every count re-derived from the filesystem **without consulting the ledger** | 16 figures | **1 falsified, corrected** | See F-01 |
| Claim sample — 100% categories | Security, compliance, and licence claims re-verified against live sources | 12 rows | pass — all 12 confirmed on re-check | Pass A |

| Check not executed | Why | What it would have established |
|---|---|---|
| Independent verification by a different model | The passes were run inline in one context rather than as separate agent dispatches | Whether the findings survive a reviewer who does not share this one's priors — the single largest gap in this verification |
| `pytest` on the `agent-capability-standard` submodule | `engagement.allowedActions.runBuild` is `false` | Whether the only dependency-bearing plugin's tests pass (AQ-0001) |
| End-to-end execution of the dossier post-merge workflow | Requires a scratch repository, an API-key secret, and a merged pull request | Whether the plugin's headline capability works (AQ-0002) |
| A clean-profile marketplace install | `engagement.allowedActions.networkAccess` is `false` | Whether a first-time install succeeds (AQ-0003) |

## Claim sample

| Field | Value |
|---|---|
| Claim categories audited at 100% | security, compliance, licence. Financial, performance, and customer-reference were searched for and **none exists in the package** — there are no commercial or benchmark claims to audit |
| Sampling method for remaining claims | Census rather than sample. Every one of the 54 evidence rows was re-checked, because the population is small enough that sampling would have been a weaker method for no saving |
| Sample size | 54 |
| Population size | 54 |
| Defect rate found in the sample | 1 of 54 rows falsified — 1.9% (EV-0046, see F-01) |
| What the sample can and cannot detect | A census over the ledger detects rows that are *wrong*. It cannot detect a claim that is **missing** from the ledger entirely, nor a fact that is true at `d0fa737` and false on `main`. Both remain open exposures (AQ-0010) |

## Scorecard

| Dimension | Weight | Score | Percent of available | Deductions cite |
|---|---|---|---|---|
| Evidence grounding and freshness | 18 | 17 | 94% | Two planned checks unexecuted (AQ-0001, AQ-0002), so two claims rest on structure rather than observation |
| Coverage and completeness | 12 | 11 | 92% | `prompt-decorators` never inspected (AQ-0005); submodule history past the pin never read (AQ-0006) |
| Technical correctness | 15 | 13 | 87% | F-01 (a falsified count that had propagated to 7 documents) and F-02 (34 internal-identifier leaks in the public documents) |
| Cross-document consistency | 10 | 9 | 90% | F-01 propagated to 7 documents before correction — the drift mechanism worked exactly as the package warns about elsewhere |
| Due-diligence decision value | 10 | 10 | 100% | — |
| Onboarding and operability | 10 | 9 | 90% | Every command was executed and its output recorded, but no route has ever been walked by anyone other than the maintainer (AQ-0007) |
| Security, privacy, and disclosure safety | 10 | 8 | 80% | F-03 — 52 unregistered sentences remain in the public documents |
| Reliability and verification depth | 5 | 3 | 60% | **The three passes were not independent.** Same model, same context, shared priors |
| Public usefulness and claim integrity | 5 | 4 | 80% | F-03; the qualifications are present and adjacent, but the prose exceeds the registered wordings |
| Clarity and maintainability | 5 | 5 | 100% | — |

| Field | Value |
|---|---|
| Score before corrections | 82 |
| Score after corrections | **89** |

## Release gate

| Condition | Result | Evidence |
|---|---|---|
| Total score at least the configured minimum | **FAIL** | 89 against a configured minimum of 95 |
| Every dimension at or above its minimum percent | **FAIL** | Reliability and verification depth at 60% against a minimum of 80% |
| No unresolved critical or high finding | PASS | No Critical found; both High findings (F-01, F-02) were corrected and re-checked |
| No unsupported or unapproved public claim | **FAIL** | 52 unregistered sentences in `06-public/**` (F-03) |
| Every required human approval recorded | PASS | All 19 claims approved by the named approver on 2026-07-26; the posture claims were presented separately and approved explicitly |
| No secret, credential, personal data, or prohibited disclosure present | PASS | `CLAIM_SCAN_LEAKS=0` after F-02 was corrected; 0 prohibited vocabulary |
| No contradiction that could materially mislead a decision | **FAIL** | CT-0001 — the README asserts MIT and no `LICENSE` file exists. This materially misleads anyone who installs or forks |
| Canonical document and section coverage complete, including justified `N/A` | PASS | 23 of 23 files; every `N/A` carries a stated reason |
| Every material internal claim has a state and a locator | PASS | 54 rows, each with a state and a `file:`, `cmd:`, or `api:` locator |
| Every public claim maps to approved `V` or `C` evidence | PASS | 19 of 19 approved claims rest on `V` rows; 0 rest on any weaker state |
| Internal links, paths, and diagram syntax validate | PASS | 0 dangling links, 0 dangling `related:` entries, 3 of 3 diagrams parse |
| Commands and examples executed or marked not executed | PASS | 26 executed with retained output; 2 marked not executed with reasons |
| Planned behaviour not presented as implemented | PASS | dossier's post-merge automation is labelled "built, never executed" in every document that mentions it, and the claim asserting otherwise was rejected as CL-R02 |
| Targets not presented as measured results | PASS | The current-versus-target table marks every row "not committed"; three performance assumptions are labelled unverified rather than stated as measurements |
| Policies not presented as implemented controls | PASS | The control-state summary separates 7 implemented from 3 policy-only, and names the 3 |
| Unresolved uncertainty and source limitations visible | PASS | 9 open register items, 5 unavailable-evidence rows, and a scope section naming what the assessment cannot establish |
| Reviewer-pass independence method disclosed | PASS | Disclosed above, including that independence was **not** achieved |

**GATE RESULT: NOT-RELEASABLE.** Four of seventeen conditions fail. The gate is conjunctive, so the score is not the operative fact — even at 100 the package would fail on CT-0001 alone.

## Findings

| Finding ID | Severity | Pass | Audience affected | File and section | Problem | Evidence | Why it matters | Required correction | Evidence still needed | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| F-01 | High | B | Reviewer, Maintainer | 7 documents citing EV-0046 | The evidence ledger recorded 11 tracked decision records; `git ls-files .decisions/` returns 10. The eleventh file exists in the working tree but is untracked | `git ls-files .decisions/ \| wc -l` → 10 | A single wrong number in the ledger propagated verbatim into 7 documents. This is the exact cross-document drift the package criticizes the repository's README for, reproduced inside the package itself within one drafting session | Correct EV-0046 and all 7 citing documents | none | **corrected** |
| F-02 | High | C | Every public reader | `06-public/**` | Both public documents carried inline `[CL-####]` citations — 34 occurrences. The plugin's own rule is that `EV`, `AQ`, `CT`, `CL`, and `TM` identifiers must never appear publicly: they expose the internal register structure and are useless to a reader | `CLAIM_SCAN_LEAKS=34` | Traceability belongs in the claim register's mapping table, which already carried it. The public documents leaked internal structure for no reader benefit | Remove every inline identifier from `06-public/**` | none | **corrected** — `CLAIM_SCAN_LEAKS=0` |
| F-03 | Medium | C | Every public reader | `06-public/**` | 52 sentences in the public documents do not match an approved claim's wording verbatim. They are qualifications, scope statements, and connective prose rather than new claims — but the disclosure rule admits no such category | `CLAIM_SCAN_UNREGISTERED_SENTENCES=52` | The rule exists so that no public sentence escapes review. Prose that merely explains an approved claim still reaches a reader unreviewed, and the scanner cannot distinguish explanation from assertion | Either register the connective prose as claims, or narrow the public documents to registered wordings | A decision on which of the two, from the claim approver | **open** |
| F-04 | Medium | A | Maintainer | `plugins/dossier/bin/dossier-claim-scan.sh` | The scanner read YAML frontmatter as prose, so `title:` and `audience:` were reported as unregistered claims in every public document — 4 findings no drafter could ever resolve | 56 unregistered before the fix, 52 after | A check that emits irreducible noise trains its reader to skip its output, which is how the real findings get missed | Skip the header block; add regression tests | none | **corrected** — fixed in the plugin with 3 regression tests |
| F-05 | Low | A | Reviewer | This report | The three verification passes ran in one context on one model, so their agreement carries almost no independent information | The independence section above | The package's own standard treats correlated review error as the failure mode the three-pass design exists to prevent. This run did not meet that standard | Re-run the passes as separate agent dispatches, or via `--external` against a different model | An independent run | **open** |
| F-06 | High | gate | Every future dossier user | `plugins/dossier/bin/dossier-gate.sh`, `templates/package/07-verification/…` | Gate condition G17 greps the verification report for `## Reviewer-pass independence method` and a `Model diversity:` line. The shipped template carried neither — its heading was `## Independence method` and it never prompted for the line | G17 failed on a report drafted faithfully from the template | **Every package would fail G17, always, with nothing in the template explaining why.** The condition was added without aligning the artifact it grades | Rename the template heading to match the gate and the contract reference; add the `Model diversity:` prompt | none | **corrected** |
| F-07 | High | gate | Every future dossier user | `plugins/dossier/bin/dossier-ledger-lint.sh` | Two defects in one check. The linter compared the `Source ref` cell against the filesystem verbatim, but `references/evidence-ledger-schema.md` writes every one of its own examples as a Markdown code span — so the documented form failed the lint. Separately, the multi-locator loop this fix required ran in a pipe, so `emit` incremented a counter in a subshell and the linter printed findings under `LEDGER_ERRORS=0` | 82 errors at first run, of which 53 were the backtick form; the subshell defect was introduced by the first fix and caught by its own regression test | A linter that rejects the documented style trains everyone to ignore it; a linter that reports findings and a zero count is worse — a caller checking only the count sees a clean ledger | Strip code spans before classifying a locator; validate each span; iterate without a pipe. Add `derived:` as a locator form, which the method allowed and the schema table never named | none | **corrected** |

| Severity | Found | Corrected | Open | Accepted | Blocked |
|---|---|---|---|---|---|
| Critical | 0 | 0 | 0 | 0 | 0 |
| High | 4 | 4 | 0 | 0 | 0 |
| Medium | 2 | 1 | 1 | 0 | 0 |
| Low | 1 | 0 | 1 | 0 | 0 |

Four of the seven findings — F-04, F-06, F-07, and the ledger-shape errors folded into F-07 — are defects **in the dossier plugin itself**, surfaced only because the plugin was pointed at a real project for the first time. Its 1034 assertions had never caught any of them, because each is a disagreement between two artifacts that no single test compared: a gate against its template, a linter against its reference, a scanner against a document's header. Each now has a regression test that fails if the pair drifts again.

## Corrections applied

| Finding ID | Document | Change made | Re-checked | Result |
|---|---|---|---|---|
| F-01 | `00-control/evidence-ledger.md` and 6 others | 11 → 10 tracked decision records, everywhere the figure appeared | `grep -rn '11 tracked decision\|11 decision records\|11 records'` | 0 remaining |
| F-02 | `06-public/technical-partner-guide.md`, `06-public/customer-product-and-trust-guide.md` | All 34 inline `[CL-####]` citations removed; traceability retained in the register's mapping table | `dossier-claim-scan.sh` | `CLAIM_SCAN_LEAKS=0` |
| F-04 | `plugins/dossier/bin/dossier-claim-scan.sh`, `plugins/dossier/tests/disclosure-gate.test.sh` | Header block skipped; 3 regression tests — header fields not reported, a body sentence still reported, a headerless document scanned in full | `plugins/dossier/tests/run.sh` | pass |
| F-06 | `plugins/dossier/templates/package/07-verification/documentation-verification-report.md`, `plugins/dossier/tests/package-contract.test.sh` | Heading renamed to match the gate and the contract reference; `Model diversity:` prompt added; a test now reads G17's expected heading **out of the gate script** and asserts the template carries it, so renaming either alone fails | `plugins/dossier/tests/run.sh` | pass |
| F-07 | `plugins/dossier/bin/dossier-ledger-lint.sh`, `plugins/dossier/references/evidence-ledger-schema.md`, `plugins/dossier/tests/ledger-lint.test.sh` | Code spans stripped before locator classification; every span in a cell validated; loop de-piped so the counter moves with the findings; `derived:` added to the accepted forms and documented in the schema table; 5 regression tests | `dossier-ledger-lint.sh`, `plugins/dossier/tests/run.sh` | `LEDGER_ERRORS=0`; suite pass |
| — | `00-control/evidence-ledger.md` | Locators normalized to the documented forms; an escaped pipe removed from a Notes cell, which had made one row parse as 15 columns; `Public use` set to `no` on the 27 rows no approved claim rests on | `dossier-ledger-lint.sh` | `LEDGER_ERRORS=0 LEDGER_ROWS=54` |
| — | `07-verification/documentation-verification-report.md`, `00-control/documentation-index.md` | Headers completed; both were the 2 files reported incomplete by the first package check | `dossier-package-check.sh` | headers complete |

## Unresolved findings

| Finding ID | Severity | Why it remains open | What would close it | Owner |
|---|---|---|---|---|
| F-03 | Medium | Closing it requires a decision the package cannot make for itself: either register roughly fifty explanatory sentences as claims, or strip the public documents back to registered wordings and lose the qualifications that make them honest. Registering them purely to clear the count would be gaming the check | The approver's decision on which path, then the corresponding edit | Daniel Bentes |
| F-05 | Low | Independent passes were not available in this run. Recording the limitation is the correct response; asserting independence that did not occur would be the failure mode | One re-run as separate agent dispatches, or an external audit against a different model | Daniel Bentes |

## Cross-document consistency

| Subject checked | Documents compared | Agreed | Discrepancy | Resolution |
|---|---|---|---|---|
| Test assertion counts (1022, 1034, 2,056) | 18, 18, and 15 occurrences across the package | yes | none | — |
| Artifact counts (112 skills, 61 commands, 29 agents, 16 hooks) | 8, 9, 8, and 11 occurrences | yes | none | — |
| Repository history (194 commits, 351 across all refs) | 8 and 7 occurrences | yes | none | — |
| Decision records | 7 documents | **no** | Ledger said 11; filesystem says 10 | F-01, corrected in all 7 |
| Plugin count (8 published, 7 on `main`) | 6 documents | yes | none — every mention carries the branch qualification | — |
| Licence state | 5 documents | yes | none | — |
| Terminology | All 23 files against 25 `TM-` entries | yes | none | — |

## Disclosure and secret safety

| Check | Scope | Result | Detail |
|---|---|---|---|
| Secret patterns in the package | 23 files, 12 pattern classes | pass | 0 matches. The only credential-shaped strings in the repository are synthetic fixtures inside the plugin's own detector tests, which is exactly the exclusion EV-0037 states |
| Internal identifiers in `06-public/**` | 2 files | **fail, then pass** | 34 `[CL-####]` citations found and removed (F-02) |
| Internal paths or names in `06-public/**` | 2 files | pass | 0 matches. No absolute path, no home directory, no hostname |
| Unapproved claims in `06-public/**` | 2 files | **fail** | 52 unregistered sentences (F-03) |
| Prohibited words used without scope | 2 files | pass | `CLAIM_SCAN_PROHIBITED_VOCABULARY=0`. No absolute security or reliability language appears |
| Vulnerability or exploit detail | 23 files | pass | Gaps are named at the level of what is missing — no exploitation path, no proof of concept, no attack recipe |

## Mechanics validation

| Item | Checked | Passed | Failed | Detail |
|---|---|---|---|---|
| Internal links | 23 files | 23 | 0 | Every package-relative path named in prose exists |
| Contract pointers | 23 | 23 | 0 | Each resolves to a real anchor in a real reference file |
| Commands | 28 | 26 | 0 | 26 executed with output retained; 2 marked not executed with reasons |
| Examples | 6 | 6 | 0 | Every code block is either a real command that was run or a verbatim excerpt of a real file |
| Diagrams | 3 | 3 | 0 | Header form, bracket balance, quote balance, and node-label parentheses all validate |

## Residual uncertainty

| Uncertainty | Affects | Why it could not be resolved | Consequence of relying on the package anyway |
|---|---|---|---|
| Verification-pass independence | Every finding in this report | The passes ran inline in one context rather than as separate dispatches | A blind spot shared by all three would go undetected. Treat the *mechanical* findings — which are reproducible by re-running the commands — as strong, and the *judgment* findings as one reviewer's opinion |
| Whether the product helps anyone | Every quality statement in the package | No telemetry exists for plugin marketplaces and the plugins emit none (AQ-0004) | A reader could mistake artifact quality for user outcome. The package says so repeatedly for this reason |
| `main` versus the assessed branch | Every claim | The assessment ran at `d0fa737` on an unmerged branch (AQ-0010) | A claim true here may be false on `main`. Version 4.7.0 and the entire dossier plugin exist only on this branch |
| `prompt-decorators` contents | Its rows in the architecture and due-diligence documents | The source is in another repository (AQ-0005) | One published plugin is described from its manifest alone |
| Windows behaviour | The portability claims | No Windows environment was available (AQ-0008) | The scope of two reported defects is unmeasured |

## Package status

| Field | Value |
|---|---|
| Status | **not ready** |
| Blockers, if any | Four gate conditions fail. **CT-0001** — the README asserts MIT with no `LICENSE` file, which materially misleads any installer or forker. **AQ-0002** — dossier's post-merge automation has never executed, and it is an open blocking item. **F-03** — 52 unregistered sentences in the public documents. **Score and dimension minima** — 89 against 95, with verification depth at 60% against an 80% floor |

The verdict is the package working as designed, not a defect in it. Three of the four blockers are properties of the project being documented rather than of the documentation, and the fourth is an honest record of how this verification was run. A package that reported RELEASABLE under these conditions would be the failure this standard exists to prevent.

## Next actions

| Rank | Action | Owner | Evidence required | Unblocks |
|---:|---|---|---|---|
| 1 | Add a `LICENSE` file to the repository root | Daniel Bentes | `.license` non-null from the GitHub API | CT-0001, and the no-misleading-contradiction gate condition |
| 2 | Decide F-03: register the connective prose, or narrow the public documents to registered wordings | Daniel Bentes | `CLAIM_SCAN_UNREGISTERED_SENTENCES=0` | The unapproved-public-claim condition, and 3 scorecard points |
| 3 | Run dossier's post-merge workflow once, end to end | Daniel Bentes | An Actions run URL and the documentation pull request it opened | AQ-0002, and 1 scorecard point |
| 4 | Re-run verification as three separate agent dispatches, or `--external` against a different model | Daniel Bentes | Three pass outputs that are materially different from one another | F-05, and 2 scorecard points — enough to clear the dimension floor |
| 5 | Fix the four stale README facts | Daniel Bentes | README matching the manifest | Not gate-blocking, but it is the defect this package was produced to demonstrate |
