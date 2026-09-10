---
dossier-header: internal-v1
title: Technical Due Diligence Report
purpose: Gives the decision-maker a ranked, evidenced verdict on whether this project is fit to be recommended, adopted, or depended on.
audience: Reviewer, Maintainer
confidentiality: Internal
owner: Daniel Bentes
status: partially verified
project-version: 7ee4923
last-verified: 2026-09-10
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
| The three facts that drive it | **(1)** Both shipped test suites pass, on macOS at `af6e632` and on Linux CI. flow reports 2336 assertions and 0 failures [EV-0098]. dossier reports 1951 and 0 [EV-0107]. Every Actions run across this range concluded success on `ubuntu-latest` [EV-0126]. **(2)** No dependency-vulnerability scan output exists anywhere in the repository [EV-0121]. **(3)** One commit identity owns every commit on every ref, 370 of them when counted on 2026-07-26 [EV-0035]. No component has a backup owner |
| Conditions | **(1)** Run a dependency-vulnerability scan and retain its output. The project has never had one [EV-0121]. **(2)** Enable branch protection on `main` requiring both test workflows. **(3)** Publish a security contact. **(4)** Do not describe dossier's post-merge automation as working until it has been observed working once (AQ-0002) |

The shape of the verdict is unusual and worth stating plainly. **This project's engineering verification is strong and its governance is close to absent.**
Both suites pass at `af6e632` [EV-0098], [EV-0107]. The two external plugin sources are pinned to shas [EV-0058].

A manifest version check runs in CI [EV-0081] and passes at `af6e632` [EV-0127].
Each open condition is a settings change or a single file, and each has stayed undone. That persistence is the finding, not the difficulty.

## Decision context

| Field | Value |
|---|---|
| Decision being supported | Whether the marketplace is fit to be recommended to operators, adopted as a dependency, or held out as production-ready |
| Decision maker | Daniel Bentes, as owner and sole maintainer |
| Project stage | Production for 8 published plugin entries [EV-0057] |
| Materiality threshold | Anything an installing operator would be misled by, or harmed by, on their own machine |
| Risk appetite | Not stated by the owner. This assessment treats operator-machine harm and rights ambiguity as material at any likelihood. Both are unbounded in blast radius and cheap to remedy |
| Time horizon | Immediate. The assessment supports a decision available today |

Transaction-specific acceptance criteria were not supplied. This is a general technical and product readiness assessment, and none have been invented to fill that gap.

## Scope and limitations

| Field | Value |
|---|---|
| Diligence date | 2026-09-10, refreshing an assessment first made 2026-07-26 |
| Project version assessed | `691bcdb` on branch `docs/dossier-refresh`, **not `main`** (AQ-0010). The prior HEAD `15bcb24` is not an ancestor of this branch [EV-0118], so rows pinned there are cited as recorded rather than as reachable history |
| Sources inspected | The 6 in-tree plugin trees, the manifest and every in-tree `plugin.json`, all 5 tracked workflows, `scripts/check-plugin-versions.sh`, the flow and dossier test suites executed locally, and the registers of this package |
| Sources unavailable | The `prompt-decorators` source tree (AQ-0005), upstream `agent-capability-standard` history past the pinned sha (AQ-0006), install telemetry, which does not exist (AQ-0004), and any Windows environment (AQ-0008) |
| Access limitations | The resolved action ceiling sets `runTests` true and `runBuild`, `networkAccess`, `runSecurityScan`, `runCodeQualityScan`, `readSecrets` and `writeOutsideOutputRoot` all false [EV-0077] |
| Evidence obtained outside that ceiling | Two rows rest on GitHub reads the ceiling forbids the agent to make. The session operator ran them directly: Linux CI results [EV-0126] and the manifest version check [EV-0127]. This is recorded as AQ-0012 and is not presented as agent-collected |
| Checks not executed | No dependency-vulnerability or code-quality scan ran, because both switches resolve false [EV-0073], [EV-0077]. The `agent-capability-standard` Python suite was not run (AQ-0001). dossier's post-merge workflow was not run end to end (AQ-0002) |
| Claims carried forward without re-checking | Live GitHub settings, README drift, open issues, and the client install state were last observed 2026-07-26. Their rows are cited with that date in place, and the assessment does not treat them as current |
| Package self-assessment status | This package's own verification report records a score of 87 against a configured minimum of 95 and a gate result of FAIL on two conditions [EV-0089]. No verification round has been recorded since 2026-07-26 [EV-0090] |
| What this assessment cannot establish | **Whether any plugin helps anyone in production use.** There is no install telemetry and no user research (AQ-0004). One offline evaluation harness exists for flow and is described below, and it measures model behaviour on 4 authored cases rather than user outcome |

## Product and technology fit

| Aspect | Assessment | Evidence | State |
|---|---|---|---|
| Problem-solution fit | Plausible and unmeasured in the field. The problem of operators rebuilding the same harnesses privately is observable. Whether these harnesses solve it for anyone is unknown | AQ-0004 | I |
| Technology choice | Well-matched. Markdown, JSON and shell are the medium the client loads as text, and the execution surface is readable before install | [EV-0044] | V |
| Platform dependency | Total and unhedgeable. Nothing functions without the Claude Code client, whose contracts are external | [EV-0043] | I |
| Differentiation | Restrictive hooks. flow ships blocking hooks including `block-secrets.sh`, `block-destructive.sh` and `block-force-push.sh` [EV-0038]. dossier ships hooks enforcing output-root containment and the action ceiling [EV-0039] | [EV-0038], [EV-0039] | V |
| Breadth versus depth | 8 published entries [EV-0057], of which 2 carry an executed shell test suite [EV-0098], [EV-0107]. The collection is broader than its verification | [EV-0057], [EV-0098], [EV-0107] | V |

## Lifecycle and maturity

| Dimension | Assessment | Evidence | State |
|---|---|---|---|
| Product maturity | **Low-to-moderate.** Releases v4.9.0 and v4.10.0 published 2026-09-10, against no measurement of use and no recorded roadmap | [EV-0066], AQ-0004 | V |
| Engineering maturity | **High where it exists, absent where it does not.** 4287 passing assertions across two plugins, confirmed green on Linux CI. The other four in-tree plugins have no suite | [EV-0098], [EV-0107], [EV-0126] | V |
| Operational maturity | **Low, and largely not applicable.** The project operates no service, so most of the absence is correct. What is not correct is the missing disclosure channel and the missing merge gate | [EV-0044], [EV-0036] | V |
| Security maturity | **Mixed, and the mix is the finding.** Restrictive hooks, permission-scoped workflows and an all-false action ceiling sit beside an unscanned dependency surface and an ungated default branch | [EV-0121], [EV-0016], [EV-0038], [EV-0077] | V |

## Architecture and codebase assessment

| Aspect | Finding | Evidence | State |
|---|---|---|---|
| Runtime | There is none. Every shipped artifact executes inside the operator's own Claude Code session | [EV-0044] | V |
| Tracked artifact surface | 71 `SKILL.md` files, 61 command definitions, 29 agent definitions, 37 plugin `bin/` scripts, 2 `hooks.json` manifests | [EV-0093] | V |
| Largest components | flow ships 32 skills, 23 commands, 9 agents and 14 hook scripts. dossier ships 10 skills, 9 commands, 6 agents, 5 hook scripts and 20 `bin/` scripts | [EV-0129] | V |
| Vendoring model | 6 entries are repository-relative paths. `agent-capability-standard` is a `github` source pinned to sha `9e2f65b`. `prompt-decorators` is a `git-subdir` source pinned to sha `9c792fe` | [EV-0058] | V |
| Submodule removal | No `.gitmodules` exists in the tracked tree [EV-0059]. A populated `plugins/agent-capability-standard/` directory on the assessment machine is untracked working-tree residue [EV-0060]. Any file count taken on that machine without `git ls-files` silently includes it | [EV-0059], [EV-0060] | V |
| Static analysis coverage | CodeQL runs, and shell is outside its language set. The whole operator-facing shell surface has no automated security analysis | [EV-0123], [EV-0093] | I |

The submodule finding matters beyond its own scope. `02-architecture/components-and-codebase.md` still described that path as a submodule regenerated with `git submodule update --remote` (CT-0005). That description is wrong at this HEAD, and this report does not carry it forward.

## Data and AI assessment

| Question | Finding | Evidence | State |
|---|---|---|---|
| Does the project store persistent data? | No datastore and no runtime exist. State lives in the operator's own repository and session files | [EV-0044] | V |
| Does the project train or host a model? | No. The artifacts are prompts and shell that the operator's client executes against a model the project does not run | [EV-0043], [EV-0044] | I |
| Training-data or model-provenance exposure | Not applicable. No dataset and no model weights are held, so no training-data rights question arises | [EV-0044] | N/A |
| Is prompt behaviour evaluated? | Partly. `plugins/flow/evals/` holds a correctness harness with 4 cases, hidden per-case tests and trap variants, across 82 tracked files | [EV-0095] | V |
| What did that evaluation report? | Reported: the retained summary records 105 runs across 2 models, 7 arms and 4 cases at a total cost of $184.65, with a `keep-enforce` verdict for both models | [EV-0096, R] | R |
| Coverage of that evaluation | Unknown: no evaluation harness exists for dossier or for any other entry, and 4 authored cases do not establish behaviour across 71 skills. No register row yet — an AQ row is requested in this draft's handback | [EV-0095], [EV-0093] | U |

## Infrastructure, deployment, reliability and operations

| Aspect | Finding | Evidence | State |
|---|---|---|---|
| Deployment mechanism | Distribution is a git read performed by the client, not a registry publish | [EV-0043] | I |
| CI surface | 5 tracked workflows: codeql, dossier-tests, flow-tests, marketplace-manifest, release-desktop-skills | [EV-0123] | V |
| CI health | Every commit this range added to `main` is green on Linux, across both test workflows, the manifest check and CodeQL | [EV-0126] | V |
| Merge gating | `main` carried no branch protection and no rulesets when last observed on 2026-07-26 [EV-0016], [EV-0017]. Both CI results are therefore advisory. Not re-checked in this refresh, because `networkAccess` is false [EV-0077] | [EV-0016], [EV-0017] | V |
| Documentation automation | No dossier docs-refresh workflow is installed in this repository | [EV-0123] | V |
| Operational load | Nothing is operated and no on-call rotation exists. This is a property of the architecture, not a gap | [EV-0044] | V |
| Config drift | `.claude/settings.dossier.json` sets `dossier.ci.expectedPluginVersion` to "1.0.0" while the plugin is at 1.2.0 | [EV-0085] | V |

## Security, privacy and compliance assessment

| Control area | Finding | Evidence | State |
|---|---|---|---|
| Dependency vulnerability scanning | **None exists.** No `.dossier/scan/` directory is present and no SARIF, osv-scanner or Dependabot artifact is tracked [EV-0121]. `runSecurityScan` resolves false, so `dossier-scan-security.sh` emits `disabled` and invokes nothing [EV-0073]. This is the absence of a scan, not a clean result | [EV-0121], [EV-0073] | V |
| Dependency surface | **Undeclared, not absent.** No dependency manifest of any kind is tracked [EV-0186]. PyYAML is a hard runtime requirement of the flow plugin's Python entrypoints, declared nowhere an operator would see [EV-0187], [EV-0189]. `plugins/flow/bin/_journal_atomic.py:51` imports it at module scope, unguarded. Several `bin/` scripts and the `SessionEnd` hook `session-end-state.sh` reach that import [EV-0189]. The only pin is `pyyaml==6.0.2` in the two CI workflows, which govern CI and not an install [EV-0187]. CT-0025 records the correction. CL-0048 replaces the public claim and is pending approval | [EV-0186], [EV-0187], [EV-0189] | V |
| Third-party CI actions | 2 action sources, `actions/checkout@v4` and `github/codeql-action@v3`, pinned by major tag rather than by sha | [EV-0042] | V |
| Supply-chain pinning of plugin sources | Both external sources now carry a sha [EV-0058], and both pinned trees report their advertised versions [EV-0127] | [EV-0058], [EV-0127] | V |
| Credential exposure | No credential matching the project's own detector pattern set appears in tracked files, as observed 2026-07-26 | [EV-0037] | V |
| Vulnerability disclosure | No `SECURITY.md`, `CONTRIBUTING.md`, `CODEOWNERS`, `dependabot.yml` or templates existed when last observed 2026-07-26 | [EV-0036] | V |
| Workflow injection | `release-desktop-skills.yml` interpolates `${{ github.event.release.tag_name }}` inside a `run:` body, which the project's own shipped rule forbids (CT-0004) | [EV-0015] | V |
| Personal data | The project holds none. It has no accounts, no tenants and no server-side identity | [EV-0044] | V |
| Compliance regime | Unknown: no compliance obligation has been asserted by the owner and none was identified in the sources inspected. No register row yet — an AQ row is requested in this draft's handback | — | U |

## Engineering organization, ownership and delivery capability

| Aspect | Finding | Evidence | State |
|---|---|---|---|
| Contributor concentration | One author identity across every ref, 370 commits when counted on 2026-07-26 | [EV-0035] | V |
| Ownership coverage | Every component has an owner. Every component has the same owner, and no component has a backup owner | [EV-0035] | V |
| Escalation | 6 of 6 decision domains have no recorded escalation path, and security disclosure handling is `unassigned` | [EV-0036], [EV-0035] | V |
| Review capability | With no branch protection [EV-0016] and one identity [EV-0035], no change in the inspected history was gated on a second reviewer | [EV-0016], [EV-0035] | I |
| Contribution path | No external contribution has been exercised, and no guidance, CODEOWNERS or template exists | [EV-0036], AQ-0007 | V |
| Delivery throughput | Two releases were published on 2026-09-10, and both plugin versions moved with them | [EV-0066], [EV-0065] | V |

Bus factor is assessed here as knowledge and authority concentration across roles. It is not an assessment of any individual's performance.

## Product delivery and evidence of product behaviour

| Question a decision maker asks | What the evidence supports | Evidence | State |
|---|---|---|---|
| Do the shipped artifacts do what their tests assert? | Yes, for flow and dossier, on macOS at `af6e632` and on Linux CI | [EV-0098], [EV-0107], [EV-0126] | V |
| Do the other entries do what they claim? | Unknown: the four in-tree entries with no executable suite are unverified, and the two external sources were not exercised | [EV-0010], AQ-0005, AQ-0001 | U |
| Does dossier's headline capability work? | Unverified. Its parts are unit-tested, the whole has never run end to end in a live repository, and no docs-refresh workflow is installed here | AQ-0002, [EV-0045], [EV-0123] | U |
| Does any prompt improve model behaviour? | Reported for flow only, from the retained eval summary, on 4 authored cases | [EV-0096, R] | R |
| Does anyone install and use these? | Unknown: no install telemetry exists for plugin marketplaces | AQ-0004 | U |

A passing suite proves what it asserts and nothing wider. The 4287 assertions are strong evidence about artifact structure and script behaviour. They are not evidence that dossier refreshes documentation after a merge, and this report does not let one stand in for the other.

## Scalability, performance, unit cost and vendor lock-in

| Aspect | Finding | Evidence | State |
|---|---|---|---|
| Scaling surface | There is nothing to scale. Every execution happens on an operator machine the project does not run | [EV-0044] | V |
| Unit cost to the project | Distribution cost is a git read and GitHub Actions minutes for 5 workflows | [EV-0043], [EV-0123] | I |
| Unit cost to the operator | Borne by the operator as model tokens. One retained evaluation run cost $184.65 across 105 runs, which indicates the order of magnitude for evaluation work rather than for normal use | [EV-0096, R] | R |
| Vendor lock-in | Total to one vendor. The client resolves, loads and executes everything, and the project does not control that contract | [EV-0043] | I |
| Exit path | Unknown: no evidence establishes whether these artifacts would function under any other agent client. No register row yet — an AQ row is requested in this draft's handback | — | U |

## Intellectual property, licensing and provenance

| Item | Finding | Evidence | State |
|---|---|---|---|
| Repository licence | A root `LICENSE` file carries the canonical Apache-2.0 text, and the same blob is on the remote | [EV-0019] | C |
| Declaration consistency | All in-tree `plugin.json` files and all marketplace entries declared Apache-2.0 when last checked | [EV-0021] | V |
| Public licence detection | GitHub's repository-level detection reported `null` on 2026-07-26, because it is computed from the default branch (AQ-0011) | [EV-0018] | V |
| Pre-2026-07-26 copies | The repository published no `LICENSE` while the README asserted MIT (CT-0001). What governs a copy taken before that date is a question for qualified legal review | [EV-0019], [EV-0020] | V |
| External source provenance | Both external entries are pinned to shas and report their advertised versions [EV-0127]. What separates `9e2f65b` from upstream tag `v1.2.0` is still unexamined | [EV-0058], [EV-0127], AQ-0006 | V |
| Third-party contents | Unknown: the `prompt-decorators` tree has not been inspected from here | AQ-0005 | U |

No legal conclusion is drawn from any row above. A licence file establishes what text is in the repository and nothing further. The pre-licence period and the external-source provenance are flagged for qualified review.

## Maintainability and changeability

| Aspect | Finding | Evidence | State |
|---|---|---|---|
| Change safety for the two tested plugins | High. 4287 assertions run locally and on Linux CI | [EV-0098], [EV-0107], [EV-0126] | V |
| Change safety elsewhere | Low. Four in-tree entries have no suite, so a structural break in them would reach installers unchecked | [EV-0010], [EV-0058] | I |
| Manifest change safety | This row corrects CT-0006. `scripts/check-plugin-versions.sh` compares every entry against its source and fails on a missing external `sha` [EV-0080]. It runs on manifest pull requests, weekly and on demand [EV-0081], and passes at HEAD [EV-0127] | [EV-0080], [EV-0081], [EV-0127] | V |
| Readability of the change surface | Every executable file is plain shell, and every artifact is text the operator can read before install | [EV-0044], [EV-0093] | V |
| Documentation drift | The README misstated the plugin count, two versions, and omitted a plugin when observed on 2026-07-26. Those rows were not re-checked in this refresh | [EV-0022], [EV-0023], [EV-0024], [EV-0025] | V |

Inferred: four of the six in-tree entries have no shell test suite, reasoned from EV-0010's count of 2 of 7 at `06b1586` and the removal of the submodule entry since [EV-0058], [EV-0059]. No count of test suites was executed at this HEAD.

## Material strengths

| Strength | Why it is defensible or valuable | Evidence | State |
|---|---|---|---|
| Both maintained suites pass on two platforms | 2336 flow assertions and 1951 dossier assertions, 0 failures, confirmed green on `ubuntu-latest` | [EV-0098], [EV-0107], [EV-0126] | V |
| Auditable execution surface | 37 plugin `bin/` scripts, all plain shell, with no binaries or bundles. An installer can read what will run before trusting it | [EV-0093], [EV-0044] | V |
| Restrictive-by-default safety model | Blocking hooks for secrets, destructive commands and force-push, plus an action ceiling whose capabilities default to false | [EV-0038], [EV-0039], [EV-0077] | V |
| Supply chain pinned and checked | Both external sources carry shas, both match their advertised versions, and a CI check enforces the pairing | [EV-0058], [EV-0080], [EV-0081], [EV-0127] | V |
| A real evaluation harness exists for flow | 4 cases with hidden tests and trap variants, driven by a runner and 82 tracked files. Rare in a prompt-shipping project | [EV-0095] | V |
| The project's own tooling finds its own defects | This refresh, produced by the plugin under review, corrected a submodule description (CT-0005) and a claim that nothing validates the manifest (CT-0006) | [EV-0059], [EV-0080] | V |

## Material weaknesses and hidden liabilities

| Weakness | Why it is material | How it would surface | Evidence | State |
|---|---|---|---|---|
| The dependency surface has never been scanned | A diligence reader cannot be told anything about this project's vulnerability status, in either direction | The first advisory against any shipped or pinned dependency | [EV-0121], [EV-0073] | V |
| A hard runtime dependency is declared nowhere | No manifest is tracked [EV-0186], and flow's Python entrypoints require PyYAML at runtime [EV-0187], [EV-0189]. No file declares the requirement to an operator installing the plugin [EV-0187] | An import failure on an operator machine without PyYAML, including from the `SessionEnd` hook, with no operator action | [EV-0186], [EV-0187], [EV-0189] | V |
| Nothing gates `main` | Any change reaches every installer's machine as executable code with no check having to pass, and `autoUpdate` was on by default when last observed | A mistaken commit, or one compromised account | [EV-0016], [EV-0017], [EV-0051] | V |
| No security disclosure channel | The project ships hooks that execute on other machines and offers no private reporting route | The first researcher who finds something | [EV-0036] | V |
| Bus factor of one | One identity across every ref, no backup owner on any component, no escalation path | Any absence of one person | [EV-0035] | V |
| Shell is unanalysed while CodeQL runs | The operator-facing execution surface has no automated security analysis, and CodeQL's presence makes the gap easy to miss | A defect that a shell linter would have caught | [EV-0123], [EV-0093] | I |
| Four in-tree entries are untested | Structural validity of most of the collection is unverified | A change to any of them | [EV-0010], [EV-0058] | I |
| dossier's headline capability has never executed | A published plugin whose central claim rests on unit tests of its parts | The first time someone runs it | AQ-0002, [EV-0045], [EV-0123] | U |
| Own-workflow rule violation | The repository's shipped rule against event interpolation in a `run:` body is broken by its own release workflow | A crafted release tag name | [EV-0015] | V |
| Documented facts contradicted by source | README drift observed 2026-07-26 was not re-checked here, so the current drift extent is itself unknown | Already surfaced once by this package | [EV-0022], [EV-0023] | V |
| No measurement of outcome | Quality decisions are made with no signal about whether the product helps anyone | Structurally invisible. It cannot surface | AQ-0004 | U |

## Evidence groupings

The four registers are kept separate here on purpose. Collapsing them is what makes a summary misleading.

### Verified and corroborated facts

Both suite results and their Linux confirmation [EV-0098], [EV-0107], [EV-0126]. The tracked artifact inventory [EV-0093], [EV-0129]. Marketplace shape and source pinning [EV-0057], [EV-0058], [EV-0059], [EV-0060].

The manifest version check and its passing result [EV-0080], [EV-0081], [EV-0127]. The workflow set [EV-0123]. Licence text and declarations [EV-0019], [EV-0021]. The absence of any scan artifact [EV-0121], [EV-0073]. The action ceiling [EV-0077]. The absence of any tracked dependency manifest, and PyYAML as an undeclared runtime requirement of flow [EV-0186], [EV-0187], [EV-0189].

### Reported, not independently verified

The flow evaluation summary and its `keep-enforce` verdict [EV-0096, R]. The `prompt-decorators` entry's description of its own contents (AQ-0005). The Windows failure reports in issues #100 and #130, read but not reproduced (AQ-0008).

### Inferences, with the chain stated

That distribution is a git read rather than a registry publish [EV-0043]. That four of six in-tree entries carry no suite, from EV-0010 plus the submodule removal. That shell has no automated security analysis, from the workflow set [EV-0123] and the shell surface [EV-0093]. That no change was gated on a second reviewer, from the absence of protection [EV-0016] and the single identity [EV-0035].

### Unknowns

Whether the dependency surface holds any known vulnerability [EV-0121]. Whether dossier's automation works end to end (AQ-0002). Whether the pinned external trees differ materially from their tags (AQ-0006, AQ-0005). Whether branch protection changed since 2026-07-26 [EV-0016]. Whether anyone installs and uses the product (AQ-0004). Whether the Python suite in the external source passes (AQ-0001).

## Red flags and potential deal-breakers

| Flag | Severity | Why it could be decisive | Evidence | What would clear it |
|---|---|---|---|---|
| Dependency surface never scanned | **High** | A buyer or adopter cannot be given any statement about vulnerability exposure, and the absence has persisted across two assessment rounds | [EV-0121], [EV-0078] | One scan with retained output in the ledger |
| Ungated `main` on an auto-updating channel | **High** | No check has to pass, and installers receive whatever lands without acting. One compromised account reaches every operator machine | [EV-0016], [EV-0017], [EV-0051] | Branch protection requiring both test workflows and one review |
| No disclosure channel for code that runs on user machines | **High** | It converts every security finding into a public one | [EV-0036] | `SECURITY.md` with one contact address |
| Bus factor of one | Medium-High | 8 published entries freeze on any absence of one person, and no installer can weigh this because it is not disclosed | [EV-0035] | A named backup maintainer, or a stated single-maintainer status |
| A published plugin whose headline capability has never run | Medium | It is the exact failure the plugin exists to prevent, in the repository that ships it | AQ-0002, [EV-0123] | One end-to-end run with the run URL recorded |
| ~~Floating ref on an external plugin source~~ | **Cleared** | Installers previously received unreviewed upstream content under this marketplace's name | [EV-0058], [EV-0127] | Cleared by sha pinning plus the CI version check |
| ~~No manifest validation~~ | **Cleared** | A malformed edit could break all 8 entries at once | [EV-0080], [EV-0081], [EV-0127] | Cleared by `scripts/check-plugin-versions.sh` in CI |
| ~~No licence file while claiming MIT~~ | **Cleared** | Was a hard stop for any fork, vendoring or corporate adoption | [EV-0019], [EV-0021] | Cleared 2026-07-26. Public detection resolves on merge to `main` (AQ-0011) |

This table lists the flags found in the sources inspected. It does not state that no others exist. The unscanned dependency surface is the clearest reason that caveat carries weight here.

## Risk register ranked by decision impact

| Rank | Risk | Decision impact | Likelihood | Detectability | Evidence | Mitigation | Owner |
|---:|---|---|---|---|---|---|---|
| 1 | Unscanned dependency and artifact surface | No vulnerability statement can be made to any adopter | certain | none today | [EV-0121], [EV-0073] | Run and retain one scan | Daniel Bentes |
| 2 | Ungated `main` feeding an auto-updating channel | Any adopter inherits an unbounded supply-chain exposure | medium | none | [EV-0016], [EV-0017] | Branch protection | Daniel Bentes |
| 3 | No security disclosure path | The first real finding becomes public | medium | none | [EV-0036] | `SECURITY.md` | Daniel Bentes |
| 4 | Bus factor of one | Continuity risk across all 8 entries | certain | high | [EV-0035] | Backup maintainer, or disclosure | Daniel Bentes |
| 5 | Unexecuted headline capability | The plugin's central claim is unverified | certain | high once run | AQ-0002, [EV-0123] | One end-to-end run | Daniel Bentes |
| 6 | Shell unanalysed | The operator-facing execution surface has no automated analysis | medium | low | [EV-0123] | A shell linter in CI | Daniel Bentes |
| 7 | Four in-tree entries unverified | Changes to most of the collection are unchecked | certain | low | [EV-0010] | One structural suite each | Daniel Bentes |
| 8 | Windows support unstated | An unknown share of operators cannot use the product | certain for those operators | only by report | [EV-0049], AQ-0008 | Support it, or state the policy | Daniel Bentes |
| 9 | Own release workflow interpolates event data | A crafted tag name reaches a shell body | low | none | [EV-0015] | Move the value to `env:` | Daniel Bentes |
| 10 | CI actions pinned by major tag | An upstream tag move changes CI behaviour silently | low | none | [EV-0042] | Pin to shas | Daniel Bentes |

## Remediation estimates

Ranges, with the assumption each rests on. No calendar dates are attached, because these horizons are an ordering and not a commitment.

| Item | Effort range | Assumptions the range rests on | What would narrow it | Confidence |
|---|---|---|---|---|
| One dependency-vulnerability scan | one CI job, plus unknown remediation | The scan itself is a job. The fix volume is unknown until it runs once | Running it once | **low on the fix volume** |
| Enable branch protection | one settings change | Both test workflows exist and are green [EV-0126] | — | high |
| Add `SECURITY.md` | one file | A contact address exists | — | high |
| A shell linter in CI | one step, plus unknown fixes | The fix volume across 37 scripts is unknown until it runs | Running it once | **low on the fix volume** |
| One end-to-end run of dossier's refresh | one scratch repository, one API-key secret, one merged pull request | The workflow behaves as its structural tests suggest | Running it | medium |
| Structural suites for four entries | copyable harness, per-entry assertions | The harness transfers. The assertions are per-entry work | Writing the first one | medium |
| Pin CI actions to shas | one edit per workflow | 2 action sources only [EV-0042] | — | high |
| Extend evaluation beyond flow | unknown | One harness exists to copy from [EV-0095]. Case authoring is the cost | A second plugin's first case | **low** |

Six of eight items are a single file, setting, or step. The highest-ranked risks remain among the cheapest to remove, which points at a governance gap rather than a technical one.

## Questions and evidence requests for management

| Rank | Question | Why it matters to the decision | Smallest sufficient evidence | Register ID |
|---:|---|---|---|---|
| 1 | When will a dependency-vulnerability scan run, and where will its output live? | No statement about vulnerability exposure can be made until it does | One scan artifact cited by an evidence row | [EV-0121] |
| 2 | Will `main` be gated before the next release? | Determines whether an adopter inherits an unbounded supply-chain exposure | A `200` from the branch-protection endpoint | [EV-0016] |
| 3 | Where should a researcher report a vulnerability privately? | Determines whether the first finding is public | `SECURITY.md` | [EV-0036] |
| 4 | Has dossier's post-merge workflow ever run end to end? | Determines whether its headline capability may be claimed | One Actions run URL and the pull request it opened | AQ-0002 |
| 5 | Is there a second person who can release, merge and answer a security report? | Continuity across 8 published entries | A named backup, or a public statement that there is none | [EV-0035] |
| 6 | Is Windows supported? | An unknown share of operators is affected and has been told nothing | A stated policy, or a passing `windows-latest` CI leg | AQ-0008 |
| 7 | What separates pinned sha `9e2f65b` from upstream tag `v1.2.0`? | The manifest advertises a version the pinned tree matches, from a revision that is not the tag | One upstream commit range listing | AQ-0006 |

## 30 / 60 / 90 priorities

Recommendation: the ordering below is proposed, not adopted. Nothing in it describes work that has been done.

| Horizon | Priority | Addresses | Why in this position | Owner |
|---|---|---|---|---|
| 30 | Run one dependency-vulnerability scan and retain its output | Rank 1 | It is the only open item that blocks every statement about vulnerability exposure | Daniel Bentes |
| 30 | Add `SECURITY.md` and enable branch protection on `main` | Ranks 2, 3 | Two edits close the two highest remaining governance gaps. Both test workflows are already green on Linux [EV-0126] | Daniel Bentes |
| 30 | Run dossier's post-merge refresh once and record the run | Rank 5, AQ-0002 | The capability is published and its central claim is unverified | Daniel Bentes |
| 60 | Add a shell linter to both test workflows and pin the CI actions to shas | Ranks 6, 10 | Closes the analysis and supply-chain gaps while the surface is 37 scripts | Daniel Bentes |
| 60 | Decide and state the Windows policy | Rank 8 | Operators keep discovering non-support by failing | Daniel Bentes |
| 60 | Correct the release workflow's event interpolation | Rank 9 | The project's own shipped rule already forbids it (CT-0004) | Daniel Bentes |
| 90 | Structural suites for the four untested in-tree entries | Rank 7 | Brings verification up to the breadth of the collection | Daniel Bentes |
| 90 | Decide on a backup maintainer, or disclose single-maintainer status | Rank 4 | The only item here that is a choice about the project rather than a task within it | Daniel Bentes |
| 90 | Extend the evaluation harness beyond flow | [EV-0095] | The product's core value proposition has evidence for one plugin only | Daniel Bentes |

## Recommendation

Recommendation: **proceed with conditions**. The four conditions in the executive verdict are the acceptance criteria this assessment proposes. Three of them are a single file or setting. The fourth is a restraint on what may be claimed about dossier's automation until it has been observed working once.

Recommendation: a reader weighing adoption should treat the two tested plugins and the other six entries as different propositions. The first pair carries 4287 assertions and green Linux CI [EV-0098], [EV-0107], [EV-0126]. The rest carry structural checking of their manifest entries [EV-0127] and nothing else.
