---
dossier-header: internal-v1
title: Technical Due Diligence Report
purpose: Gives the decision-maker a ranked, evidenced verdict on whether this project is fit to be recommended, adopted, or depended on.
audience: Reviewer, Maintainer
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: fd884b2
last-verified: 2026-07-26
review-trigger: Any red flag changes state; a release is cut; the maintainer count changes
related: [01-project/executive-project-brief.md, 04-operating/decisions-technical-debt-and-risks.md, 05-due-diligence/assets-dependencies-and-licenses.md, 07-verification/documentation-verification-report.md]
---
# Technical Due Diligence Report
<!-- contract: references/package-contract-05-due-diligence.md#technical-due-diligence-report -->

## Executive verdict

| Field | Value |
|---|---|
| Verdict | **proceed with conditions** |
| Confidence | **high** on the artifacts, **low** on outcomes |
| Basis for the confidence rating | 56 evidence rows, 55 of them `V` or `C` and 1 `I` with its chain stated; 30 of 32 planned checks executed with retained output, and the 2 unexecuted ones named with their reason. That supports high confidence about *what the project is*. It supports none at all about *whether it works for anyone*: there is no telemetry, no evaluation suite, and no user research, and that limitation is structural rather than an omission (AQ-0004) |
| Conditions, if any | Three remain, all cheap. **(1)** Enable branch protection on `main` requiring both test workflows — today any change reaches every installer's machine as executable code with no check having to pass. **(2)** Publish a security contact — the project ships hooks that run on other people's machines and has no private disclosure channel. **(3)** Do not describe dossier's post-merge automation as working until it has been observed working once (AQ-0002). A fourth condition, the missing licence, was **discharged on 2026-07-26**: Apache-2.0 was chosen, the file added, and every declaration aligned to it |

The shape of the verdict is worth stating plainly, because it is unusual. **This project's engineering quality is high and its governance is absent.** The two test suites, the restrictive-by-default hooks, the single dependency, and the readable-plain-text execution surface are all genuinely good. Every one of the four conditions above is a settings change or a single file — and every one has stayed undone, which is itself the finding: a project with one maintainer produces good artifacts and no process.

## Decision context

| Field | Value |
|---|---|
| Decision being supported | Whether the marketplace is fit to be recommended to operators, adopted as a dependency, or held out as production-ready |
| Decision maker | Daniel Bentes, as owner and sole maintainer |
| Project stage | Production for 7 published plugins; pre-production for the 8th |
| Materiality threshold | Anything an installing operator would be misled by, or harmed by, on their own machine |
| Risk appetite | Not stated by the owner. This assessment treats operator-machine harm and rights ambiguity as material at any likelihood, because both are unbounded in blast radius and cheap to remedy |
| Time horizon | Immediate — the assessment supports a decision available today |

## Scope and limitations

| Field | Value |
|---|---|
| Diligence date | 2026-07-26 |
| Project version assessed | `fd884b2` on `fix/issue-131-round-5-containment` — **not `main`** (AQ-0010) |
| Sources inspected | All 6 in-tree plugin trees; the checked-out `agent-capability-standard` submodule; all 4 workflows; the manifest and all 7 plugin manifests; `README.md` in full; live GitHub settings, releases, issues, and Actions history; the Claude Code client's own install-state files |
| Sources unavailable | `prompt-decorators` source (AQ-0005); upstream submodule history past the pinned commit (AQ-0006); install telemetry, which does not exist (AQ-0004); any Windows environment (AQ-0008) |
| Checks executed | 30 of 32, each with output retained in the evidence ledger |
| Checks not executed | The submodule's Python suite (AQ-0001); dossier's post-merge workflow end to end (AQ-0002). A third, a clean-profile install (AQ-0003), was partially substituted by observing an existing resolved install |
| Access limitations | `engagement.allowedActions` set `runBuild` and `networkAccess` to `false` for this run, which is what prevented AQ-0001 and AQ-0003 |
| What this assessment cannot establish | **Whether any plugin helps anyone.** There is no usage signal, no behavioural evaluation of any prompt, and no user research. Every quality statement in this package is a property of the code, never of its effect. A reader who treats artifact quality as evidence of outcome is over-reading this report |

## Product and technology fit

| Aspect | Assessment | Evidence | State |
|---|---|---|---|
| Problem-solution fit | Plausible and unmeasured. The problem — operators rebuilding the same harnesses privately — is real and observable; whether these harnesses solve it for anyone is unknown | AQ-0004 | I |
| Technology choice | Well-matched. Markdown and shell are the right medium for a product the client loads as text, and they make the execution surface auditable before install | [EV-0007], [EV-0044] | V |
| Platform dependency | Total and unhedgeable. Nothing functions without the Claude Code client, whose contracts are external and can change without notice | [EV-0043] | V |
| Differentiation | The safety rails. flow's hooks block destructive commands, force-pushes, and secret writes; dossier's action ceiling defaults every capability to `false` except reading source. Few plugin collections ship restrictive hooks | [EV-0038], [EV-0039] | V |
| Breadth versus depth | 8 plugins, of which 2 carry test suites and 5 carry none. The collection is broader than its verification | [EV-0010] | V |

## Lifecycle and maturity

| Dimension | Assessment | Evidence | State |
|---|---|---|---|
| Product maturity | **Low-to-moderate.** 57 releases over ~7 months and 8 published plugins, against zero measurement of use and no roadmap, milestone, or forward-looking plan of any kind | [EV-0032], [EV-0046], AQ-0004 | V |
| Engineering maturity | **Moderate-to-high where it exists, absent where it does not.** 2,249 passing assertions with genuinely sophisticated tests — cross-artifact invariants, portability constraints, an anti-self-certification assertion — covering 2 of 7 in-tree plugins | [EV-0008], [EV-0009], [EV-0010] | V |
| Operational maturity | **Low, and largely N/A.** Nothing is operated, so most of the absence is correct. What is not correct: no runbook for any of six identified failure modes, no incident process, and no way to reach installers when something breaks them | [EV-0044], [EV-0036] | V |
| Security maturity | **Mixed, and the mix is the finding.** Real controls exist — restrictive hooks, permission-scoped workflows, no credentials anywhere, an all-false action ceiling. Real gaps sit alongside them: nothing gates `main`, shell is unanalysed, and there is no disclosure channel for code that runs on other people's machines | [EV-0016], [EV-0036], [EV-0037], [EV-0038] | V |

## Material strengths

| Strength | Why it is defensible or valuable | Evidence | State |
|---|---|---|---|
| Auditable execution surface | 42 executable files, all plain shell, no binaries or bundles. An installer can read everything that will run on their machine before trusting it — which matters more here than usual, because hooks run unprompted | [EV-0007], [EV-0040] | V |
| Substantial and unusual testing where it exists | 2,249 assertions covering frontmatter shape, cross-reference resolution, bash 3.2 portability, cross-artifact invariants, and an assertion that the documentation gate cannot certify itself | [EV-0008], [EV-0009] | V |
| Tests that catch real defects | The destructive-command hook blocked two `rm -rf` invocations during this project's own development; dossier's suite surfaced a settings-cascade defect before release | [EV-0038], [EV-0009] | V |
| Restrictive-by-default safety model | Tiered actions with merge and release requiring explicit confirmation; an action ceiling whose every capability defaults to `false` except reading source | [EV-0038], [EV-0039] | V |
| Minimal supply chain | One declared third-party runtime dependency in the whole repository | [EV-0041] | V |
| No credentials anywhere | Verified with the project's own detector pattern set across all tracked files | [EV-0037] | V |
| Machine-readable consistency holds | All 7 in-tree plugins agree with their manifest entries | [EV-0026] | V |
| The project's own tooling found its own defects | This assessment was produced by the plugin under review, running against its own repository, and surfaced 4 stale README facts, a pointer drift, a workflow-injection inconsistency, and a missing licence | [EV-0047], [EV-0048] | V |

## Material weaknesses and hidden liabilities

| Weakness | Why it is material | How it would surface | Evidence | State |
|---|---|---|---|---|
| Copies taken before 2026-07-26 carry no licence | The repository published no `LICENSE` file until that date while the README asserted MIT. The licence now governs every copy taken from then on; what governs an earlier one is a question of law | Only if someone who forked earlier relies on the earlier state | [EV-0019], [EV-0020] | V |
| Nothing gates `main` | Any change — mistaken or malicious — reaches every installer's machine as executable code with no check having to pass, and `autoUpdate` is on by default | A bad commit, or one compromised account | [EV-0016], [EV-0017], [EV-0051] | V |
| No security disclosure channel | The project ships hooks that execute on other people's machines and offers no private way to report a flaw in them | The first researcher who finds something | [EV-0036] | V |
| Bus factor of one | 8 published plugins; one identity across all 364 commits; no component has a backup owner; no succession path | Any absence of one person | [EV-0035] | V |
| Shell is unanalysed while CodeQL runs | The entire executable surface on operator machines has no automated security analysis, and CodeQL's presence makes the gap easy to miss | A defect that `shellcheck` would have caught | [EV-0012], [EV-0007] | V |
| Five of seven in-tree plugins are untested | 34 commands, 14 agents, and 29 skills with no verification of even structural validity | A change to any of them | [EV-0010] | V |
| dossier's headline capability has never executed | A published plugin whose central claim rests on unit tests of its parts | The first time someone runs it | AQ-0002, [EV-0045] | V |
| The manifest has no validation | The highest-blast-radius file in the repository is checked by nothing | A malformed edit breaking all 8 plugins at once | [EV-0026] | V |
| Prose contradicts the machine-readable source in six places | The README misstates the plugin count and two versions and omits a plugin; two plugin descriptions misstate their own skill counts | Already surfaced — by this assessment | [EV-0022]–[EV-0028] | V |
| No measurement of outcome | Every quality decision is made without any signal about whether the product helps anyone | Structurally invisible; it cannot surface | AQ-0004 | V |

## Evidence grouping

| Grouping | Contents |
|---|---|
| Verified facts | 55 of 56 rows. Artifact counts; both test results; all 4 workflow definitions and their permission scoping; live branch protection, rulesets, and licence detection; release and tag history; contributor count; the full dependency surface; the client's install state; version agreement across 7 plugins; the credential scan; the workflow-injection scan |
| Reported assertions, not independently verified | The `prompt-decorators` entry's description of its own contents (AQ-0005); the `agent-capability-standard` version label, where the pinned tree is 2 commits past the tag it advertises (AQ-0006); the Windows failure reports in issues #100 and #130, which were read but not reproduced (AQ-0008) |
| Inferences | One: that distribution is a git read rather than a registry publish [EV-0043], reasoned from the absence of any registry manifest and any publish step in the 4 workflows, with the chain stated in the row |
| Unknowns | Whether anyone uses the product; whether dossier's automation works; whether a clean-profile install succeeds; whether the submodule's Python suite passes; the Windows portability scope; whether any prompt improves model behaviour |

## Red flags and potential deal-breakers

| Flag | Severity | Why it could be decisive | Evidence | What would clear it |
|---|---|---|---|---|
| ~~No licence file while claiming MIT~~ | **Cleared** | Was a hard stop for any fork, vendoring, or corporate adoption. Apache-2.0 chosen; the file is at the repository root and every declaration matches it | [EV-0019], [EV-0021] | Cleared 2026-07-26. GitHub's derived licence field updates on merge (AQ-0011) |
| Ungated `main` on a distribution channel that auto-updates | **High** | The combination is what makes it decisive: no check has to pass, and `autoUpdate: true` means installers receive whatever lands without acting. A single compromised account reaches every operator's machine | [EV-0016], [EV-0017], [EV-0051] | Branch protection requiring both test workflows and one review |
| No disclosure channel for code that runs on user machines | **High** | It converts every security finding into a public one, and signals that vulnerability reports were not planned for | [EV-0036] | `SECURITY.md` with one contact address |
| Bus factor of one | Medium-High | 8 published plugins freeze on any absence of one person, and no installer can weigh this because it is not disclosed | [EV-0035] | Name a backup maintainer, or state single-maintainer status in the README |
| A published plugin whose headline capability has never run | Medium | It is the exact failure the plugin itself exists to prevent, in the repository that ships it | AQ-0002 | One end-to-end run with the run URL recorded |
| Six documented facts contradicted by the source | Medium | Not decisive alone, but it establishes that this project's prose drifts systematically — which is the reason to weight *this* package's own claims by their evidence rows rather than by its prose | [EV-0022]–[EV-0028] | The CI check that compares prose facts to the manifest |

## Risk register ranked by decision impact

| Rank | Risk | Decision impact | Likelihood | Detectability | Evidence | Mitigation | Owner |
|---:|---|---|---|---|---|---|---|
| 1 | Ungated `main` feeding an auto-updating channel | Any adopter inherits an unbounded supply-chain exposure | medium | **none — nothing would detect it** | [EV-0016], [EV-0017] | Branch protection | Daniel Bentes |
| 2 | No security disclosure path | Guarantees that the first real finding is public | medium | none | [EV-0036] | `SECURITY.md` | Daniel Bentes |
| 3 | Bus factor of one | Continuity risk across all 8 plugins | certain | high | [EV-0035] | Backup maintainer, or disclosure | Daniel Bentes |
| 4 | Unexecuted headline capability | The plugin's central claim is unverified | certain | high once run | AQ-0002 | One end-to-end run | Daniel Bentes |
| 5 | Shell unanalysed | The whole operator-facing execution surface has no automated analysis | medium | low | [EV-0012] | `shellcheck` in CI | Daniel Bentes |
| 6 | 5 plugins unverified | Changes to most of the collection are unchecked | certain | low | [EV-0010] | One structural suite each | Daniel Bentes |
| 7 | No manifest validation | A single malformed edit breaks all 8 plugins | low | none | [EV-0026] | One CI step | Daniel Bentes |
| 8 | Windows unsupported and undisclosed | An unknown share of operators cannot use the product | certain for those operators | only by report | [EV-0049] | Support it, or say so | Daniel Bentes |
| 9 | Floating ref on an external plugin source | Installers receive unreviewed upstream content under this marketplace's name | medium | none | [EV-0030] | Pin the ref | Daniel Bentes |

## Remediation estimates

| Item | Effort range | Assumptions the range rests on | What would narrow it | Confidence |
|---|---|---|---|---|
| ~~Add `LICENSE`~~ | done | — | — | **Completed 2026-07-26** — Apache-2.0, with all 15 declarations aligned |
| Enable branch protection | one settings change | Both workflows already exist and pass | — | high |
| Add `SECURITY.md` | one file | A contact address exists | — | high |
| Fix the 4 stale README facts | one edit | The correct values are in the manifest | — | high |
| Manifest and README validation in CI | one workflow step | dossier already ships this check scoped to itself; generalizing it is the work | Reading that existing check | high |
| `shellcheck` in CI | one step, plus unknown fixes | The fix volume is unknown until it runs once | Running it once | **low on the fix volume** |
| One end-to-end run of dossier's workflow | one scratch repository, one API key, one merged pull request | The workflow behaves as its structural tests suggest | Running it | medium |
| Structural suites for 5 plugins | copyable harness, per-plugin assertions | The harness transfers; the assertions are per-plugin work | Writing the first one | medium |
| A behavioural evaluation harness | unknown | **Nothing comparable exists in the repository to estimate from** | A prototype | **low** |

Seven of nine items are a single file, setting, or step. That concentration is the report's most actionable finding: **the highest-ranked risks are also the cheapest to remove**, and their persistence reflects a governance gap rather than a technical one.

## Questions and evidence requests for management

| Rank | Question | Why it matters to the decision | Smallest sufficient evidence | Register ID |
|---:|---|---|---|---|
| 1 | Will `main` be gated before the next release? | Determines whether an adopter inherits an unbounded supply-chain exposure | A `200` from the branch-protection endpoint | R-02 |
| 2 | Where should a researcher report a vulnerability privately? | Determines whether the first finding is public | `SECURITY.md` | R-03 |
| 3 | Has dossier's post-merge workflow ever run end to end? | Determines whether its headline capability may be claimed | One Actions run URL and the documentation pull request it opened | AQ-0002 |
| 4 | Is there a second person who can release, merge, and respond to a security report? | Continuity across 8 published plugins | A named backup, or a public statement that there is none | R-04 |
| 5 | Is Windows supported? | An unknown share of operators is affected and has been told nothing | A stated policy, or a passing `windows-latest` CI leg | AQ-0008 |
| 6 | Does the `prompt-decorators` entry describe its actual contents? | It is published to installers from this manifest | A file listing and its `plugin.json` | AQ-0005 |

## 30 / 60 / 90-day priorities

| Horizon | Priority | Addresses | Why now | Owner |
|---|---|---|---|---|
| 30 days | Add `SECURITY.md`; enable branch protection | Ranks 1–2 | Two edits close the two highest-severity remaining security gaps. Nothing here needs design work. `LICENSE` and the 4 stale README facts were done on 2026-07-26 | Daniel Bentes |
| 30 days | Run dossier's post-merge workflow once and record the run | Rank 4, AQ-0002 | Its release is pending; the claim cannot be made without it | Daniel Bentes |
| 60 days | One CI step validating the manifest, the version pairs, and the README facts | Ranks 7, R-10, TD-01, TD-02 | Converts four recurring manual gates — three of which have already failed — into a check | Daniel Bentes |
| 60 days | `shellcheck` in both test workflows; pin the actions to SHAs; pin `prompt-decorators`; move the submodule pointer to its tag | Ranks 5, 9, TD-07, TD-08 | Closes the supply-chain and analysis gaps while the surface is still small enough to fix cheaply | Daniel Bentes |
| 60 days | Decide and state the Windows policy | Rank 8 | Issue #100 has been open without resolution, and operators keep discovering non-support by failing | Daniel Bentes |
| 90 days | Structural suites for the 5 untested plugins | Rank 6 | Brings verification up to the breadth of the collection | Daniel Bentes |
| 90 days | Decide on a backup maintainer, or disclose single-maintainer status | Rank 3 | The only item here that is a choice about the project rather than a task within it | Daniel Bentes |
| 90 days | Prototype a behavioural evaluation for one skill | R-13, TD-11 | The product's core value proposition has no evidence either way, and this is the only item that would change that | Daniel Bentes |
