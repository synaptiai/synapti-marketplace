---
dossier-header: internal-v1
title: Documentation Verification Report
purpose: Tells a reader how much this package's own claims are worth, by recording what was checked, what was found, and what could not be established.
audience: Reviewer, Maintainer
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: 06b1586
last-verified: 2026-07-26
review-trigger: Any re-run of the verification passes, or any correction applied to a document after this report was written
related: [00-control/evidence-ledger.md, 00-control/assumptions-questions-and-contradictions.md, 00-control/claim-and-disclosure-register.md, 05-due-diligence/technical-due-diligence-report.md]
---
# Documentation Verification Report
<!-- contract: references/package-contract-07-verification.md#documentation-verification-report -->

## Scope

| Field | Value |
|---|---|
| Package version verified | 1.0.4 |
| Project version or commit | `06b1586` on `fix/gate-verdict-integrity` |
| Evidence cutoff | 2026-07-26 |
| Verification date | 2026-07-26 (rounds 1 through 3, same day; round 4 is a fix cycle — see below) |
| Documents in scope | All 23 canonical files |
| Documents out of scope and why | None. This report verifies itself only for mechanics — a pass cannot audit its own findings |
| Round | 6 |

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

Stating this plainly rather than describing three passes as if they were independent is the point of the section. What the passes did achieve is *method* diversity — Pass A checked referential integrity mechanically, Pass B re-derived every headline number from the filesystem without consulting the ledger, and Pass C compared repeated facts across documents. Those are genuinely different procedures, and Pass B's re-derivation is what caught the first substantive defect. What they did not achieve is *reviewer* independence.

Round 3 is the evidence for how much that costs. It re-derived every headline figure from the commit under review rather than from the ledger, and found five defects the first two rounds had passed over — including a pinned commit at which the licence this package reports as present did not exist, and three of six contract-mandated diagrams silently absent. Rounds 1 and 2 had declared cross-document consistency clean. A third look at the same package, by the same reviewer, with a different starting point, was enough to falsify that. The correlation risk above is not theoretical, and the score moved down rather than up because of it.

## Checks performed

| Check | Method | Scope | Result | Evidence |
|---|---|---|---|---|
| Canonical file presence | `dossier-package-check.sh` | 23 files | pass — 23 of 23 present | `CHECK_FILES_PRESENT=23` |
| Header completeness | Same, shell frontmatter parser | 23 files | pass after correction — 21 of 23 complete at first run, both gaps filled | `CHECK_HEADERS_OK` |
| Contract pointer resolution | Same — body line 2 resolved to a real anchor in a real reference | 23 files | pass — 23 of 23 | `CHECK_POINTERS_CHECKED=23` |
| Internal link resolution | `test -f` on every package-relative path named in prose, plus every `related:` entry | 23 files | pass — 0 dangling of both kinds | Pass C |
| Diagram syntax | Python parse of every mermaid block: header form, bracket and quote balance, parentheses inside node labels | 6 blocks | pass | Pass C, re-run in round 3 |
| Diagram versus inventory agreement | Every node and edge mapped to a row in the accompanying table | 6 blocks | pass | Pass C, re-run in round 3 |
| Evidence citation coverage | Set difference between `EV-####` defined in the ledger and referenced anywhere | 56 IDs | pass — 0 dangling, 0 orphaned | Pass A |
| Register referential integrity | Same for `AQ`, `CT`, `CL`, `TM` | 11 / 4 / 35 / 25 | pass — 0 dangling in all four | Pass A |
| Ledger locator resolution | `dossier-ledger-lint.sh` — 13-column shape, ID uniqueness, state and authority enums, locator resolution at authority 1–3, public-use gating | 56 rows | pass after correction — 82 errors at first run, 0 now | See F-06, F-07 |
| Public claim mapping | `dossier-claim-scan.sh` against the approved register | 2 public files | pass after correction — 52 unregistered in round 1, **0 now** | See F-03, F-08 |
| Secret and sensitive-material scan | Same tool: 12 credential pattern classes plus internal locators | 2 public files | pass after correction — 34 leaks found and fixed | See F-02 |
| Command and example execution | Every command in the package executed and its real output recorded | 30 of 32 | pass — the 2 unexecuted are named with reasons | Ledger executed-checks table |
| Terminology consistency | Every entity named in prose checked against the terminology register | 25 `TM-` entries | pass | Pass C |
| Cross-document fact agreement | Every repeated number grepped across all 23 files and its occurrences counted | 12 recurring figures | **1 finding in round 1, corrected; 1 more in round 3** | See F-01, F-14 |
| Headline-number re-derivation | Every count re-derived from the filesystem **without consulting the ledger** | 16 figures in round 1; 21 re-run in round 3 against the pinned commit | **1 falsified in round 1; 6 stale in round 3, all corrected** | See F-01, F-11 |
| Pin-versus-evidence agreement | Every fact the package reports as current tested against the commit named in `project-version` | 23 headers, 3 post-pin corrections | **fail, then pass** — the pin named a commit at which the licence did not exist | See F-11 |
| Diagram coverage | Each template's mermaid prompts counted against the diagrams the document actually carries | 23 template/document pairs | **fail, then pass** — 3 of 6 requested diagrams were absent | See F-13 |
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
| Sampling method for remaining claims | Census rather than sample. Every one of the 56 evidence rows was re-checked, because the population is small enough that sampling would have been a weaker method for no saving |
| Sample size | 56 |
| Population size | 56 |
| Defect rate found in the sample | 1 of 56 rows falsified — 1.8% (EV-0046, see F-01) |
| What the sample can and cannot detect | A census over the ledger detects rows that are *wrong*. It cannot detect a claim that is **missing** from the ledger entirely, nor a fact that is true at `06b1586` and false on `main`. Both remain open exposures (AQ-0010) |

## Scorecard

| Dimension | Weight | Score | Percent of available | Deductions cite |
|---|---|---|---|---|
| Evidence grounding and freshness | 18 | 16 | 89% | Two planned checks unexecuted (AQ-0001, AQ-0002), so two claims rest on structure rather than observation. F-11: the package's own pin disagreed with the evidence it reported, and six figures were stale at the commit under review |
| Coverage and completeness | 12 | 10 | 83% | `prompt-decorators` never inspected (AQ-0005); submodule history past the pin never read (AQ-0006). F-13: 3 of 6 contract-requested diagrams were absent |
| Technical correctness | 15 | 13 | 87% | F-01 (a falsified count that had propagated to 7 documents) and F-02 (34 internal-identifier leaks in the public documents). Both corrected in round 1; the deduction stands because they were present in a drafted package |
| Cross-document consistency | 10 | 8 | 80% | F-01 propagated to 7 documents before correction. F-14: the ledger contradicted itself between an evidence row and the check that row cites. F-11: six subjects disagreed in round 3 after two rounds reported this section clean |
| Due-diligence decision value | 10 | 9 | 90% | F-15: a cleared risk was deleted rather than renumbered, leaving both ranked tables starting at 2 and a horizon reference pointing at a rank that no longer existed |
| Onboarding and operability | 10 | 9 | 90% | Every command was executed and its output recorded, but no route has ever been walked by anyone other than the maintainer (AQ-0007) |
| Security, privacy, and disclosure safety | 10 | 10 | 100% | Round 1 deducted 2 for F-03; the scan now reports 0 leaks, 0 prohibited vocabulary, and 0 unregistered sentences |
| Reliability and verification depth | 5 | 3 | 60% | **The passes were not independent, across all three rounds.** Same model, same context, shared priors |
| Public usefulness and claim integrity | 5 | 5 | 100% | Every sentence in both public documents maps to an approved claim or a mandated qualification. Two sentences drafted in round 3 matched no approved claim and were removed rather than self-approved |
| Clarity and maintainability | 5 | 4 | 80% | F-12: the package shipped with no entry point at its own root — a reader browsing it reached eight numbered directories and no index |

| Field | Value |
|---|---|
| Score before corrections | 82 |
| Score after round 1 corrections | 89 |
| Score after round 2 corrections | 92 |
| Score after round 3 corrections | **87** |

The score fell. That is not a regression in the package, which is strictly better than it was at 92 — it is a correction to a number that was too high because two rounds had not looked hard enough. Round 3 found five defects in a package twice declared consistent, so the earlier scores were measuring the reviewer's thoroughness as much as the package's quality. A verification that cannot move its own score downward is not a verification.

## Release gate

| Condition | Result | Evidence |
|---|---|---|
| Total score at least the configured minimum | **FAIL** | 87 against a configured minimum of 95 |
| Every dimension at or above its minimum percent | **FAIL** | Reliability and verification depth at 60% against a minimum of 80% |
| No unresolved critical or high finding | PASS | No Critical found; all 8 High findings were corrected and re-checked |
| No unsupported or unapproved public claim | **PASS** | `CLAIM_SCAN_UNREGISTERED_SENTENCES=0`. 35 approved claims and 5 mandated qualifications cover every sentence in both public documents |
| Every required human approval recorded | PASS | All 35 claims approved by the named approver on 2026-07-26. The 19 original claims were presented with the posture set separated and approved explicitly; the 16 added in round 2 are qualifications and scope statements on claims already approved |
| No secret, credential, personal data, or prohibited disclosure present | PASS | `CLAIM_SCAN_LEAKS=0` after F-02 was corrected; 0 prohibited vocabulary |
| No contradiction that could materially mislead a decision | **PASS** | CT-0001 resolved by evidence: an Apache-2.0 `LICENSE` file is at the repository root and all 15 declarations across the repository match it. CT-0002 to CT-0004 remain, none of which could mislead a decision |
| Canonical document and section coverage complete, including justified `N/A` | PASS | 23 of 23 files; every `N/A` carries a stated reason |
| Every material internal claim has a state and a locator | PASS | 56 rows, each with a state and a locator in a documented form — a path, `cmd:`, `derived:`, or `inference:` |
| Every public claim maps to approved `V` or `C` evidence | PASS | Every approved claim rests on a `V` row; 0 rest on any weaker state. Two sentences drafted in round 3 matched no approved claim and were removed rather than approved by their author |
| Internal links, paths, and diagram syntax validate | PASS | 0 dangling links, 0 dangling `related:` entries, 6 of 6 diagrams parse, and every diagram the templates request is present |
| Commands and examples executed or marked not executed | PASS | 30 executed with retained output; 2 marked not executed with reasons |
| Planned behaviour not presented as implemented | PASS | dossier's post-merge automation is labelled "built, never executed" in every document that mentions it, and the claim asserting otherwise was rejected as CL-R02 |
| Targets not presented as measured results | PASS | The current-versus-target table marks every row "not committed"; three performance assumptions are labelled unverified rather than stated as measurements |
| Policies not presented as implemented controls | PASS | The control-state summary separates 7 implemented from 3 policy-only, and names the 3 |
| Unresolved uncertainty and source limitations visible | PASS | 9 open register items, 5 unavailable-evidence rows, and a scope section naming what the assessment cannot establish |
| Reviewer-pass independence method disclosed | PASS | Disclosed above, including that independence was **not** achieved |

**GATE RESULT: NOT-RELEASABLE.** Two of seventeen conditions fail, unchanged from round 2 and down from four in round 1. Both are score conditions: the total is 87 against a minimum of 95, and verification depth is 60% against an 80% floor. Both trace to the same cause — the verification passes were not independent (F-05) — and neither can be closed by editing the package. Only a genuinely independent re-run closes them. Round 3 is the demonstration: a third look at a twice-certified package found five more defects, so the deficit the gate is naming is real rather than procedural.

## Round 4 — a fix cycle, not a verification pass

Round 4 was driven by an external review of the **plugin**, not by a pass over
this package. Five containment defects were found in the code these documents
describe: the output-root hook admitted a path traversal, three security hooks
no-opped when `jq` was absent, the action ceiling was defeated by one layer of
shell indirection, the disclosure hook was missing a class its own policy
reference assigns it, and the patch validator checked path strings but not file
mode. A sixth — the validator accepting a traversal path — was found by a test
written during that cycle rather than by a reader.

Two consequences for this package, and only two:

- **The pin moved** from `fbeb1ee` to `06b1586`, and every figure that moves with a
  commit was re-derived from it: the dossier assertion count (1076 → 1241), the
  combined count (2,098 → 2,263), commits on the assessed branch (198 → 193),
  commits across all refs (355 → 370), and tracked files (570 → 572). This is F-11's
  rule applied again: figures and pin must name the same commit, or the package is
  simultaneously pinned and current and cannot be both.

  The branch commit count went **down**, which looks wrong and is not. Round 4
  was squash-merged, so the assessed branch is now a short branch off `main`
  rather than the long feature branch — 193 commits reaching `HEAD` instead of
  203. The figure moved because what it measures moved, and a reader comparing
  the two rounds would otherwise read a smaller number as an error.

  One label was wrong rather than stale. CHK-16 runs `git rev-list --count HEAD`,
  which counts the assessed branch, but five documents reported the result as the
  commit count of `main`. `main` has 189. The figure was right and the noun was
  wrong, which is the harder version of the same defect: nothing about the number
  looked incorrect.
- **Nothing else changed.** No claim was re-verified, no finding was re-opened or
  closed, and the gate verdict is unmoved.

What round 4 did **not** do is verify anything. No pass A, B, or C ran against
`06b1586`. The scorecard, the release gate, and every claim state below describe
the package as it stood at round 3 and are carried forward unchanged. A reader
weighing this report should read the round-3 evidence as the most recent
verification of record.

### Round 6 — the gate's own integrity

The reviewer assigned error-handling in rounds 4 and 5 reported nothing both
times; its findings never reached the orchestrator. In round 5 that gap was
covered by re-deriving its scope directly, which found the cursor defect. It did
not find the other four, and the release went out before the reviewer's own
answer arrived.

Three of those four attacked this gate's central claim. The most serious: the
verdict-file silence check and the result extraction used different predicates,
so a verdict naming a condition twice — an empty summary row, then a detail row
with the real word — satisfied the check on one line and was parsed from the
other. The condition was recorded nowhere and counted in neither the failure nor
the inconclusive tally. Sixteen of seventeen conditions reported, one simply
gone. A dropped condition is worse than a silent one, because silence is at
least counted.

That is a fourth instance of the shape below, and the first to land on the gate
itself rather than on the package or the tests.

### Round 5 — the same shape, one level down

Two reviewers reported after round 4 was merged and tagged, and both found real
defects. One was in a fix round 4 had just shipped: the action-ceiling repair
stripped a wrapper token plus one optional flag, which left `timeout 30 curl …`
passing the entire deny list. `timeout N cmd` is the ordinary way to bound a
command, so the bypass was the modal case rather than an exotic one, and it
shipped green because every wrapper exercised by the new tests happened to take
no argument.

That is worth recording rather than quietly correcting, because it is the third
instance in this package's history of the same shape: a check that was believed
to hold, had a test, and did not hold. Round 3 found a package pinned to a commit
where its own claims were false. Round 4 found a regression test reporting a pass
on the file that carried the defect it was written to pin. Round 5 found a
security fix whose tests covered only the cases the fix happened to handle.

None of the three was caught by a verification pass over this package. All three
were caught by someone reading the plugin afterwards. That is the strongest
available evidence for F-05, and it is why the finding stays open.

That the defects were found by a reviewer reading the plugin, and not by three
passes over the package that documents it, is itself the point F-05 makes: the
passes were not independent, and a non-independent pass is weak evidence. Round 3
demonstrated it by finding five defects a twice-certified package had passed;
round 4 demonstrates it again from the outside.

## Findings

| Finding ID | Severity | Pass | Audience affected | File and section | Problem | Evidence | Why it matters | Required correction | Evidence still needed | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| F-01 | High | B | Reviewer, Maintainer | 7 documents citing EV-0046 | The evidence ledger recorded 11 tracked decision records; `git ls-files .decisions/` returns 10. The eleventh file exists in the working tree but is untracked | `git ls-files .decisions/ \| wc -l` → 10 | A single wrong number in the ledger propagated verbatim into 7 documents. This is the exact cross-document drift the package criticizes the repository's README for, reproduced inside the package itself within one drafting session | Correct EV-0046 and all 7 citing documents | none | **corrected** |
| F-02 | High | C | Every public reader | `06-public/**` | Both public documents carried inline `[CL-####]` citations — 34 occurrences. The plugin's own rule is that `EV`, `AQ`, `CT`, `CL`, and `TM` identifiers must never appear publicly: they expose the internal register structure and are useless to a reader | `CLAIM_SCAN_LEAKS=34` | Traceability belongs in the claim register's mapping table, which already carried it. The public documents leaked internal structure for no reader benefit | Remove every inline identifier from `06-public/**` | none | **corrected** — `CLAIM_SCAN_LEAKS=0` |
| F-03 | Medium | C | Every public reader | `06-public/**` | 52 sentences in the public documents did not match an approved claim's wording verbatim | `CLAIM_SCAN_UNREGISTERED_SENTENCES=52` | The rule exists so that no public sentence escapes review. Prose that merely explains an approved claim still reaches a reader unreviewed | Resolved three ways, none of them by loosening the check: 16 sentences that genuinely assert something were registered as claims and approved; 5 near-misses were made verbatim matches of claims already approved; the remainder was editorial glue asserting nothing about the product and was cut. Two further causes were plugin defects — see F-08 | none | **corrected** — `CLAIM_SCAN_UNREGISTERED_SENTENCES=0` |
| F-04 | Medium | A | Maintainer | `plugins/dossier/bin/dossier-claim-scan.sh` | The scanner read YAML frontmatter as prose, so `title:` and `audience:` were reported as unregistered claims in every public document — 4 findings no drafter could ever resolve | 56 unregistered before the fix, 52 after | A check that emits irreducible noise trains its reader to skip its output, which is how the real findings get missed | Skip the header block; add regression tests | none | **corrected** — fixed in the plugin with 3 regression tests |
| F-05 | Low | A | Reviewer | This report | The three verification passes ran in one context on one model, so their agreement carries almost no independent information | The independence section above | The package's own standard treats correlated review error as the failure mode the three-pass design exists to prevent. This run did not meet that standard | Re-run the passes as separate agent dispatches, or via `--external` against a different model | An independent run | **open** |
| F-06 | High | gate | Every future dossier user | `plugins/dossier/bin/dossier-gate.sh`, `templates/package/07-verification/…` | Gate condition G17 greps the verification report for `## Reviewer-pass independence method` and a `Model diversity:` line. The shipped template carried neither — its heading was `## Independence method` and it never prompted for the line | G17 failed on a report drafted faithfully from the template | **Every package would fail G17, always, with nothing in the template explaining why.** The condition was added without aligning the artifact it grades | Rename the template heading to match the gate and the contract reference; add the `Model diversity:` prompt | none | **corrected** |
| F-07 | High | gate | Every future dossier user | `plugins/dossier/bin/dossier-ledger-lint.sh` | Two defects in one check. The linter compared the `Source ref` cell against the filesystem verbatim, but `references/evidence-ledger-schema.md` writes every one of its own examples as a Markdown code span — so the documented form failed the lint. Separately, the multi-locator loop this fix required ran in a pipe, so `emit` incremented a counter in a subshell and the linter printed findings under `LEDGER_ERRORS=0` | 82 errors at first run, of which 53 were the backtick form; the subshell defect was introduced by the first fix and caught by its own regression test | A linter that rejects the documented style trains everyone to ignore it; a linter that reports findings and a zero count is worse — a caller checking only the count sees a clean ledger | Strip code spans before classifying a locator; validate each span; iterate without a pipe. Add `derived:` as a locator form, which the method allowed and the schema table never named | none | **corrected** |

| F-08 | High | gate | Every future dossier user | `plugins/dossier/bin/dossier-claim-scan.sh` | Two more defects in the registration check. Approved wordings were lowercased but not normalized while document sentences were fully normalized, so markdown survived on one side only and any claim containing a code span could never match its own approved row. Separately, sentences were split on a bare `.`, cutting inside `SKILL.md`, `plugin.json`, and version numbers | 56 unregistered before the fixes, 46 after normalization, 41 after the split fix | **The registration check could not pass for a realistic claim.** Any wording containing a code span was permanently unregisterable, and the split produced fragments no drafter could resolve | Normalize both sides identically; strip code spans before splitting | none | **corrected** |
| F-09 | High | gate | Every future dossier user | `plugins/dossier/bin/dossier-claim-scan.sh` | The contract **mandates** that a required qualification appear in the public document beside the claim it qualifies. Qualification rows carry no `approved` cell, so the scan matched only claim rows and reported every mandated qualification as an unregistered sentence | The last 2 unregistered sentences were both mandated qualifications | The register required a sentence that the scan then reported as a violation — two rules the plugin ships, contradicting each other, with no way for a drafter to satisfy both | Treat the qualification column of the Required qualifications section as approved text, scoped to that section only | none | **corrected** |
| F-10 | Medium | gate | Every future dossier user | `plugins/dossier/tests/plugin-manifest.test.sh` | The licence assertion was a hard-coded `MIT` constant. A constant passes while the file it names says something else — which is how this repository came to advertise a licence it did not carry | Failed when the repository moved to Apache-2.0 | A test that asserts a constant verifies nothing about the pair it is supposed to hold together | Read the SPDX identifier from the `LICENSE` file and assert the manifest matches it; fail loudly when no `LICENSE` exists | none | **corrected** |
| F-11 | High | round 3 | Reviewer, every public reader | All 23 headers; 6 figures across ~60 occurrences | The package pinned itself to a commit that predates facts it reports as true. Every header named `d0fa737`, at which no `LICENSE` file exists — yet the package asserted the licence present and CT-0001 resolved by evidence. Six figures had also drifted after the evidence was gathered, three of them moved by this package's own correction commits: the dossier assertion count, the combined count, commits on the branch, commits across all refs, tracked files, and the decision-record count corrected by F-01 | `git cat-file -e d0fa737:LICENSE` fails; `git ls-files .decisions/` returns 11, not the 10 F-01 corrected to | A reader checking out the named commit finds the licence absent and the counts wrong. The package was simultaneously pinned and current, and could not be both. It is the refresh problem the plugin exists to solve, occurring inside the package before the plugin's refresh path had ever run | Re-pin every header to `fbeb1ee` — the last commit that changed the subject — and re-derive all six figures from it | none | **corrected** |
| F-12 | Medium | round 3 | Every reader | `bin/dossier-scaffold.sh` | The scaffold wrote 23 documents into a directory and no way into it. A reader browsing the output root sees eight numbered folders; the index that routes them is three clicks in and named like a register | The output root contained no `README.md` | An index nobody finds routes nobody. The package's own contract calls the index the entry point, and the entry point was not where readers enter | Scaffold a `README.md` signpost at the output root from `templates/package-readme.md`. It asserts no fact, so it cannot go stale | none | **corrected** — with tests, including one comparing its directory table against the scaffold's canonical list |
| F-13 | High | round 3 | Reviewer, partner, contributor | `02-architecture/data-and-ai.md`, `02-architecture/infrastructure-and-deployment.md`, `06-public/technical-partner-guide.md`, `bin/dossier-gate.sh` | Four templates open a mermaid fence to request a diagram — six in total. Three were never drawn, and nothing noticed. G11 counts fences and checks the ones present are balanced, which grades what somebody drew and is silent about what they skipped | `CHECK_DIAGRAMS_EXPECTED=6`, `CHECK_DIAGRAMS_PRESENT=3` | The logical data model, the deployment topology, and the partner integration view were each requested by the contract and silently omitted. A drafter could skip every prompt and still see a clean diagram check | Draw the three; add `CHECK_DIAGRAMS_EXPECTED`/`_PRESENT` to the package check and record a finding when a document the contract wants illustrated ships with none | none | **corrected** |
| F-14 | Medium | round 3 | Reviewer, Maintainer | `00-control/evidence-ledger.md` | The ledger contradicted itself inside one file, from the commit it was first written in. `EV-0046` recorded 10 decision records; `CHK-23` — the executed check that row cites, two sections below — recorded 11. The F-01 correction reached the evidence row and 7 citing documents and stopped short of the check result underneath it | Both values present in the same file at `6686713` | An evidence row and the check it cites are the one pair that must agree, and the correction that was this package's headline catch left them disagreeing | Set both to the observed value; the underlying count had since changed again, which is F-11 | A check comparing each row's stated value against the result of the `cmd:` it cites — not built | **corrected** |
| F-15 | Low | round 3 | Reviewer | `05-due-diligence/technical-due-diligence-report.md` | The licence risk was cleared and its row deleted rather than renumbered, leaving the risk register running 2–10, the management questions running 2–7, and the 30/60/90 table pointing at a "Ranks 1–2" that no longer existed | Both tables' leading cells | A ranked register whose top rank is missing reads as a truncation, and a cross-reference to a rank that does not exist cannot be followed | Renumber both tables from 1 and remap every horizon reference | none | **corrected** |

| Severity | Found | Corrected | Open | Accepted | Blocked |
|---|---|---|---|---|---|
| Critical | 0 | 0 | 0 | 0 | 0 |
| High | 8 | 8 | 0 | 0 | 0 |
| Medium | 5 | 5 | 0 | 0 | 0 |
| Low | 2 | 1 | 1 | 0 | 0 |

Eight of the fifteen findings — F-04, F-06 through F-10, F-12, F-13 — are defects **in the dossier plugin itself**, surfaced only because the plugin was pointed at a real project for the first time. Its original 1034 assertions had never caught any of them, because each is a disagreement between two artifacts that no single test compared: a gate against its template, a linter against its reference, a scanner against a document's header, a normalization applied to one side of a comparison, a rule that mandates text another rule forbids, a test asserting a constant instead of a pair, a scaffold that built a package with no way into it, and a diagram check that graded what was drawn and never asked what was skipped. Each now has a regression test that fails if the pair drifts again — 1241 assertions, up from 1034.

## Corrections applied

| Finding ID | Document | Change made | Re-checked | Result |
|---|---|---|---|---|
| F-01 | `00-control/evidence-ledger.md` and 6 others | 11 → 11 tracked decision records, everywhere the figure appeared | `grep -rn '11 tracked decision\|11 decision records\|11 records'` | 0 remaining |
| F-02 | `06-public/technical-partner-guide.md`, `06-public/customer-product-and-trust-guide.md` | All 34 inline `[CL-####]` citations removed; traceability retained in the register's mapping table | `dossier-claim-scan.sh` | `CLAIM_SCAN_LEAKS=0` |
| F-04 | `plugins/dossier/bin/dossier-claim-scan.sh`, `plugins/dossier/tests/disclosure-gate.test.sh` | Header block skipped; 3 regression tests — header fields not reported, a body sentence still reported, a headerless document scanned in full | `plugins/dossier/tests/run.sh` | pass |
| F-06 | `plugins/dossier/templates/package/07-verification/documentation-verification-report.md`, `plugins/dossier/tests/package-contract.test.sh` | Heading renamed to match the gate and the contract reference; `Model diversity:` prompt added; a test now reads G17's expected heading **out of the gate script** and asserts the template carries it, so renaming either alone fails | `plugins/dossier/tests/run.sh` | pass |
| F-07 | `plugins/dossier/bin/dossier-ledger-lint.sh`, `plugins/dossier/references/evidence-ledger-schema.md`, `plugins/dossier/tests/ledger-lint.test.sh` | Code spans stripped before locator classification; every span in a cell validated; loop de-piped so the counter moves with the findings; `derived:` added to the accepted forms and documented in the schema table; 5 regression tests | `dossier-ledger-lint.sh`, `plugins/dossier/tests/run.sh` | `LEDGER_ERRORS=0`; suite pass |
| F-03 | `06-public/**`, `00-control/claim-and-disclosure-register.md` | 16 sentences registered as claims and approved; 5 near-misses made verbatim; editorial glue cut. Register grew from 19 approved claims to 35 | `dossier-claim-scan.sh` | `CLAIM_SCAN_UNREGISTERED_SENTENCES=0` |
| F-08 | `plugins/dossier/bin/dossier-claim-scan.sh`, `plugins/dossier/tests/disclosure-gate.test.sh` | Approved wordings normalized identically to document sentences; code spans stripped before the sentence split; 4 regression tests including one asserting a real second sentence on the same line is still found | `plugins/dossier/tests/run.sh` | pass |
| F-09 | `plugins/dossier/bin/dossier-claim-scan.sh`, `plugins/dossier/tests/disclosure-gate.test.sh` | Required qualifications treated as approved text, scoped to that section only; 2 regression tests, one asserting a rejected wording in a later table is still not approved | `dossier-claim-scan.sh`, suite | `CLAIM_SCAN_UNREGISTERED_SENTENCES=0`; suite pass |
| F-10 | `plugins/dossier/tests/plugin-manifest.test.sh` | Hard-coded licence constant replaced by a check that the declared identifier matches the LICENSE file's text, and a loud failure when no LICENSE exists | `plugins/dossier/tests/run.sh` | pass |
| CT-0001 | `LICENSE`, 7 plugin manifests, 8 marketplace entries, `README.md`, 5 plugin READMEs, `.claude/CLAUDE.md` | Apache-2.0 chosen by the owner; canonical text added at the repository root; every declaration aligned to it | `cmd:CHK-07`, `cmd:CHK-08`, `cmd:CHK-29` | Present and consistent; 15 declarations agree |
| — | `00-control/evidence-ledger.md` | Locators normalized to the documented forms; an escaped pipe removed from a Notes cell, which had made one row parse as 15 columns; `Public use` set to `no` on the 27 rows no approved claim rests on | `dossier-ledger-lint.sh` | `LEDGER_ERRORS=0 LEDGER_ROWS=54` |
| — | `07-verification/documentation-verification-report.md`, `00-control/documentation-index.md` | Headers completed; both were the 2 files reported incomplete by the first package check | `dossier-package-check.sh` | headers complete |
| F-11 | All 23 documents | Re-pinned from `d0fa737` to `fbeb1ee`; the dossier assertion count, the combined count, commits on the branch, commits across all refs, tracked files, repository size, and the decision-record count all re-derived from the pinned commit | Each figure's own command, re-executed | 0 stale figures remaining |
| F-12 | `plugins/dossier/templates/package-readme.md`, `bin/dossier-scaffold.sh`, `bin/dossier-package-check.sh`, `skills/doc-package-contract/SKILL.md`, `tests/bin-scripts.test.sh`, `tests/references-integrity.test.sh` | Signpost template added and scaffolded to the output root; never overwritten; excluded from the canonical count; its links validated against the canonical package layout rather than the plugin tree it is stored in | `plugins/dossier/tests/run.sh` | pass |
| F-13 | `02-architecture/data-and-ai.md`, `02-architecture/infrastructure-and-deployment.md`, `06-public/technical-partner-guide.md`, `bin/dossier-package-check.sh`, `tests/bin-scripts.test.sh` | Logical data model, deployment topology, and partner integration diagrams drawn; coverage check added comparing each template's prompts against the document's diagrams | `dossier-package-check.sh` | `CHECK_DIAGRAMS_EXPECTED=6 CHECK_DIAGRAMS_PRESENT=6` |
| F-14 | `00-control/evidence-ledger.md` | `EV-0046` and `CHK-23` set to the same observed value | `git ls-files .decisions/` | both read 11 |
| F-15 | `05-due-diligence/technical-due-diligence-report.md` | Risk register and management questions renumbered from 1; all 7 horizon references remapped | Leading-cell sequence in both tables | 1–9 and 1–6, no gaps |

## Unresolved findings

| Finding ID | Severity | Why it remains open | What would close it | Owner |
|---|---|---|---|---|
| F-05 | Low | Independent passes were not available in this run. Recording the limitation is the correct response; asserting independence that did not occur would be the failure mode | One re-run as separate agent dispatches, or an external audit against a different model | Daniel Bentes |

## Cross-document consistency

| Subject checked | Documents compared | Agreed | Discrepancy | Resolution |
|---|---|---|---|---|
| Test assertion counts (1022, 1190, 2,212) | 18, 18, and 15 occurrences across the package | **no, in round 3** | Every occurrence read 1034 and 2,056 — true at the old pin, stale at the commit under review | F-11, re-derived in all 33 |
| Artifact counts (112 skills, 61 commands, 29 agents, 16 hooks) | 8, 9, 8, and 11 occurrences | yes | none — unchanged across all three rounds | — |
| Repository history (198 commits, 355 across all refs) | 8 and 7 occurrences | **no, in round 3** | Read 194 and 351; three commits had landed since the evidence was gathered | F-11, re-derived |
| Decision records | 7 documents plus the ledger's own check row | **no, twice** | Round 1: ledger said 11, filesystem said 10. Round 3: the correction had reached the evidence row and not the check result beside it, and the underlying count had moved back to 11 | F-01, then F-14 |
| Repository size and file count | 6 occurrences | **no, in round 3** | Read 541 files and ~3.5 MB against 570 and ~3.0 MB | F-11, re-derived |
| Pin versus reported state | All 23 headers | **no, in round 3** | Headers named a commit at which the licence they report as present does not exist | F-11, re-pinned |
| Plugin count (8 published, 7 on `main`) | 6 documents | yes | none — every mention carries the branch qualification | — |
| Licence state | 5 documents | yes | none | — |
| Terminology | All 23 files against 25 `TM-` entries | yes | none | — |
| Diagram coverage | 23 template/document pairs | **no, in round 3** | 3 of 6 contract-requested diagrams absent | F-13, all three drawn |

Rounds 1 and 2 reported this section clean. Round 3 found six subjects that disagreed, five of them because the repository moved after the evidence was gathered and nothing re-checked. That is the finding behind the finding: a consistency pass run once, at drafting time, certifies a package that is already going stale.

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
| Diagrams | 6 | 6 | 0 | Header form, bracket balance, quote balance, and node-label parentheses all validate. Every diagram the templates request is present |

## Residual uncertainty

| Uncertainty | Affects | Why it could not be resolved | Consequence of relying on the package anyway |
|---|---|---|---|
| Verification-pass independence | Every finding in this report | The passes ran inline in one context rather than as separate dispatches | A blind spot shared by all three would go undetected. Treat the *mechanical* findings — which are reproducible by re-running the commands — as strong, and the *judgment* findings as one reviewer's opinion |
| Whether the product helps anyone | Every quality statement in the package | No telemetry exists for plugin marketplaces and the plugins emit none (AQ-0004) | A reader could mistake artifact quality for user outcome. The package says so repeatedly for this reason |
| `main` versus the assessed branch | Every claim | The assessment ran at `06b1586` on an unmerged branch (AQ-0010) | A claim true here may be false on `main`. Version 4.7.0 and the entire dossier plugin exist only on this branch |
| `prompt-decorators` contents | Its rows in the architecture and due-diligence documents | The source is in another repository (AQ-0005) | One published plugin is described from its manifest alone |
| Windows behaviour | The portability claims | No Windows environment was available (AQ-0008) | The scope of two reported defects is unmeasured |

## Package status

| Field | Value |
|---|---|
| Status | **not ready** |
| Blockers, if any | Two gate conditions fail, both on score: 87 against a minimum of 95, and verification depth at 60% against an 80% floor. Both trace to F-05 — the passes were not independent — and neither is closable by editing the package. AQ-0002 remains open and blocking as a project item: dossier's post-merge automation has never executed. CT-0001 and F-03 were blockers in round 1 and are now resolved |

The verdict is the package working as designed, not a defect in it. Three of the four blockers are properties of the project being documented rather than of the documentation, and the fourth is an honest record of how this verification was run. A package that reported RELEASABLE under these conditions would be the failure this standard exists to prevent.

Round 3 sharpens that. It found five defects in a package two rounds had certified consistent, which means the gap the gate keeps naming is a real deficit in assurance rather than a procedural technicality. The remedy is unchanged and unchangeable by editing: a reviewer who does not share this one's priors.

## Next actions

| Rank | Action | Owner | Evidence required | Unblocks |
|---:|---|---|---|---|
| 1 | Re-run verification as three separate agent dispatches, or `--external` against a different model | Daniel Bentes | Three pass outputs that are materially different from one another | F-05, and the only two conditions still failing. Round 3 raised the expected yield: a same-reviewer re-look found 5 defects, so an independent one should be assumed to find more |
| 2 | Run dossier's post-merge workflow once, end to end | Daniel Bentes | An Actions run URL and the documentation pull request it opened | AQ-0002, and 1 scorecard point |
| 3 | Confirm GitHub reports the licence after merge | Daniel Bentes | `gh api repos/… --jq .license` returning `apache-2.0` | AQ-0011 |
