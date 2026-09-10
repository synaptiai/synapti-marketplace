---
dossier-header: internal-v1
title: Decisions, Technical Debt, and Risks
purpose: Gives a decision-maker the ranked list of what could go wrong, what it would cost to fix, and what was never decided in the first place.
audience: Maintainer, Reviewer
confidentiality: Internal
owner: Daniel Bentes
status: partially verified
project-version: d3fc744
last-verified: 2026-09-10
review-trigger: A risk changes state; a debt item is remediated; a decision is made, reversed, or recorded
related: [01-project/executive-project-brief.md, 03-assurance/security-privacy-and-compliance.md, 05-due-diligence/technical-due-diligence-report.md, 00-control/assumptions-questions-and-contradictions.md]
---
# Decisions, Technical Debt, and Risks
<!-- contract: references/package-contract-04-operating.md#decisions-technical-debt-and-risks -->

## How to read the dates in this document

Rows carrying a 2026-09-10 evidence pin were re-checked against the tree at `d3fc744`. Rows marked `(2026-07-26, not re-checked)` rest on the July assessment only. AQ-0022 records that gap as open.

## Decision log

| ID | Decision | Date | Status | Record | Rationale state | Evidence |
|---|---|---|---|---|---|---|
| D-01 | Distribute through the Claude Code plugin client rather than a package registry | unknown | in force | none | Inferred: from the absence of a registry manifest and of any publish step. No record states it | [EV-0043, I] |
| D-02 | Ship `flow` alongside `gh-workflow` rather than deprecating the older one | unknown | in force | `.claude/CLAUDE.md` names hook conflicts as the reason for enabling only one | reported, not a decision record | [EV-0004] |
| D-03 | Source `agent-capability-standard` as a git submodule | unknown | **reversed 2026-09-10** | `.gitmodules`, removed by commit `efb4f75` | unrecorded when taken. The reversal's rationale is recorded [EV-0167] | [EV-0031], [EV-0059], [EV-0167] |
| D-09 | Replace the submodule with a `github` marketplace source pinned to sha `9e2f65b` | 2026-09-10 | in force | Commit `efb4f75` body, with a per-plugin file-count table | recorded, with the reason and the measurement behind it [EV-0167] | [EV-0058], [EV-0059], [EV-0060], [EV-0167] |
| D-04 | Source `prompt-decorators` as a `git-subdir` at the floating ref `main` | unknown | superseded by D-10 | the manifest entry only | unrecorded | [EV-0030] |
| D-10 | Pin `prompt-decorators` to sha `9c792fe` | between 2026-07-26 and 2026-09-10 [EV-0030], [EV-0058] | in force | the manifest entry [EV-0058], and the manifest check that fails any external source carrying no `sha` [EV-0080] | Unknown: no record states why this sha was chosen. No AQ row covers it yet — one is requested in this draft's report | [EV-0058], [EV-0127] |
| D-05 | Keep a separate `cascade-resolve.sh` in dossier rather than sharing flow's | 2026-07 | in force | The dossier plan document | reported — plugins install independently, so a runtime dependency cannot be assumed | [EV-0007], [EV-0142] |
| D-06 | Put conditional config rules in a validator script rather than in `schema.json` | 2026-07 | in force | `schema.json` comments and dossier's own tests | recorded, with the reason: the documented fallback validator ignores `if`/`then` when `jsonschema` is absent | [EV-0009] |
| D-07 | Make dossier's verification-pass independence architectural rather than instructed | 2026-07 | in force | `agent-independence.test.sh` | recorded, enforced by test | [EV-0009] |
| D-08 | Require bash 3.2 compatibility across all shipped scripts | unknown | in force | Both suites assert it, and both were executed under `/bin/bash` 3.2.57 on 2026-09-10 | recorded by test. Rationale unstated but evident — macOS ships bash 3.2 | [EV-0098], [EV-0107] |

| Decision | Chosen because | Alternatives considered | Why rejected | Evidence |
|---|---|---|---|---|
| D-09 | The gitlink resolved to zero entries in a plain clone, so the advertised plugin could not install at all. The pin was also 17 commits and 74 files behind upstream while both trees reported version 1.2.0 | Keep the submodule and move its pointer | A submodule pointer is not fetched by the plugin client's clone, so moving it would not have fixed installation | [EV-0167] |
| D-05 | Plugins install independently, so a shared library plugin could not be assumed present at runtime | A shared library plugin | Unresolvable at the installed-plugin level | [EV-0007] |
| D-06 | A schema conditional would validate successfully and enforce nothing on exactly the machines lacking the optional dependency | `if`/`then` in the schema | Silent non-enforcement is worse than no rule | [EV-0009] |
| D-07 | Instructed independence drifts toward consensus. Separate dispatches, `memory: none`, and a skill firewall make it structural | Instructing the passes to stay independent | Correlated review error is the failure mode the design exists to prevent | [EV-0009] |

| Decision | What is visible | What is unknown | Risk of reversing blind |
|---|---|---|---|
| D-01 | The manifest, the client's resolution behaviour, the absence of any publish step | Whether a registry was ever considered, and whether the client supports one | Low — reversal would be additive |
| D-02 | Both plugins ship, and `.claude/CLAUDE.md` warns about hook conflicts | Whether `gh-workflow` has users, and whether deprecating it would break anyone (AQ-0004) | **Medium** — removing a published plugin breaks every installer of it, and there is no way to count them or tell them |
| D-09 | The source kind, the sha, the removed `.gitmodules`, the gitignored path, and the commit body's reasoning | What separates sha `9e2f65b` from upstream tag `v1.2.0` (AQ-0006) | **High** — reverting to a submodule reintroduces a zero-file install [EV-0167] |
| D-10 | The pinned sha, and the CI check that requires a sha on every external source | Why this sha, and whether the pinned tree matches the entry's description (AQ-0005) | Medium — moving or removing the pin changes what installers receive, silently |
| D-08 | The assertions, and two executed suite runs under bash 3.2.57 | Whether any operator actually runs bash 3.2, or whether this is precaution | Low |

Ten decisions are recorded here. Eight are in force, one was reversed and one superseded. D-01, D-04 and D-10 have no recorded rationale, and D-01 is inference rather than record.

Unknown: whether any of the 21 tracked decision records [EV-0169] documents these decisions was not re-derived at `d3fc744`. The July finding that 11 records covered none of them no longer describes the tree. No AQ row covers this yet — one is requested in this draft's report.

## Unresolved decisions

| ID | Decision needed | Options | Blocked by | Decides | Deadline | Consequence of not deciding |
|---|---|---|---|---|---|---|
| U-01 | ~~Add a `LICENSE` file, and which licence it states~~ | — | — | Daniel Bentes | — | **Decided 2026-07-26: Apache-2.0.** File added and every declaration aligned. GitHub's derived field now reports `Apache-2.0` [EV-0132] |
| U-02 | Whether dossier's post-merge automation may be described as working | Run it once and claim it · ship it undescribed · withhold the plugin | An end-to-end run | Daniel Bentes | before dossier is announced | The plugin's headline capability rests on unit tests of its parts (AQ-0002). No docs-refresh workflow is installed here [EV-0123] |
| U-03 | Windows support policy | Support and test it · declare it unsupported in the README · leave silent | nothing | Daniel Bentes | issues #100 and #130 have been open without resolution | Operators discover non-support by failing, having been told nothing [EV-0049] (2026-07-26, not re-checked), AQ-0008 |
| U-04 | Whether to deprecate `gh-workflow` | Deprecate with notice · keep both · merge them | AQ-0004 — no usage signal exists | Daniel Bentes | none | Two overlapping workflow plugins with conflicting hooks continue to ship with no guidance beyond a `CLAUDE.md` line |
| U-05 | Whether to name a backup maintainer, or to state single-maintainer status publicly | Name one · state it in the README · neither | nothing | Daniel Bentes | none | 8 published plugins have one maintainer across all 214 commits on `main`, and installers cannot weigh that [EV-0163] |
| U-06 | Whether to make CI blocking | Require the suites in branch protection · leave advisory | nothing | Daniel Bentes | none | 4287 executed assertions remain information rather than enforcement [EV-0098], [EV-0107], and `main` still carries no protection and no rulesets [EV-0131] |

## Technical debt register

| ID | Debt | Location | Why it exists | Interest paid today | Remediation | Effort basis | Status and what paid it | Owner | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| TD-01 | No validation of `marketplace.json` | `.github/workflows/` | The manifest was never treated as code | None. The check runs on manifest changes, weekly, and on demand, and passed at HEAD with 8 entries and 0 failures | Residual only: the check reads manifests and not prose, and a pin that is stale but self-consistent is reported rather than failed | — | **closed — observed 2026-09-10** by TM-0033, the marketplace manifest check [EV-0080], [EV-0081], [EV-0127], green on Linux [EV-0126] | Daniel Bentes | [EV-0080], [EV-0081], [EV-0127] |
| TD-02 | README drifts from the manifest | `README.md` | Prose and manifest are edited in different commits | None at `d3fc744`. The badge reads 8, flow reads 3.3.0, prompt-decorators 0.1.1, dossier is present | Generate the plugin table, or extend the CI check to prose | one script change, half a day at most, assuming the table stays hand-written | **closed at `7ee4923` and `d3fc744`** [EV-0170], [EV-0171], [EV-0179]. Residual: recurrence, because TM-0033 reads manifests and not prose [EV-0080] | Daniel Bentes | [EV-0170], [EV-0171], [EV-0179] |
| TD-03 | Most in-tree plugins have no tests | `plugins/{gh-workflow,decipon,context-ledger,ai-first-org-design-kit}` | Suites were written for the two plugins under active development | Any change to those four is unverified, including structural validity | One structural suite per plugin | The dossier and flow harnesses are copyable. The assertions are the work — days per plugin | **open.** The denominator moved from 5 of 7 to 4 of 6 when `agent-capability-standard` left the tree (CT-0022) | Daniel Bentes | [EV-0010] (2026-07-26), [EV-0058], [EV-0059], CT-0022 |
| TD-04 | Shell static analysis covers dossier only | `.github/workflows/dossier-tests.yml` | shellcheck was added with the dossier suite and not extended | flow's scripts and its 14 hook scripts are unanalysed, and those hooks run as blocking `PreToolUse` calls on contributor machines [EV-0172] | Add the same shellcheck step to `flow-tests.yml` | one workflow step plus whatever it surfaces | **partially paid.** shellcheck v0.11.0 runs over dossier's `bin/`, hooks and tests [EV-0165]. CodeQL now also scans flow's Python [EV-0176] | Daniel Bentes | [EV-0165], [EV-0175], [EV-0162], [EV-0176], AQ-0019 |
| TD-05 | `cascade-resolve.sh` exists twice and has diverged | `plugins/{flow,dossier}/bin/` | 2026-07 copy (D-05), then fixed on one side only | The two files differ by 66 lines, including a guard only dossier has. dossier's header calls its copy a byte-for-byte twin of flow's | Port the differences, or correct both headers to describe the divergence | one function plus two header edits | **open**, and now measured (CT-0007) | Daniel Bentes | [EV-0142], CT-0007 |
| TD-06 | `prompt-decorators` pinned to a floating ref | `.claude-plugin/marketplace.json` | No pinning decision was recorded (D-04) | None. The entry is pinned to sha `9c792fe` and resolves to a tree reporting the advertised 0.1.1 | Residual only: the pinned tree's contents are still unverified from here (AQ-0005) | — | **closed** by D-10 [EV-0058], [EV-0127] | Daniel Bentes | [EV-0058], [EV-0127] |
| TD-07 | Submodule pointer past its advertised tag | `.gitmodules` | Manual step with no check | None. There is no submodule. The July framing understated the gap — the pin was 17 commits and 74 files behind upstream, not 2 commits past a tag | Residual only: the distance between sha `9e2f65b` and upstream `v1.2.0` is unexamined (AQ-0006) | — | **superseded** by D-09 [EV-0059], [EV-0167]. The advertised version now matches the pinned tree [EV-0127] | Daniel Bentes | [EV-0031], [EV-0059], [EV-0127], [EV-0167] |
| TD-08 | Third-party actions pinned by major tag | `.github/workflows/` | Convention | A moved tag executes in CI, including in the `contents: write` release job [EV-0133] | Pin to commit SHAs | three lines | **open** (2026-07-26, not re-checked — AQ-0022) | Daniel Bentes | [EV-0042], [EV-0133] |
| TD-09 | `codeql.yml` has no top-level `permissions` | `.github/workflows/codeql.yml` | Omission | The workflow falls back to the repository-default token scope. The `analyze` job does declare its own three scopes, so the exposure is narrower than the July row implied | Add a top-level `permissions:` block | one line | **open**, re-confirmed at `e104483` [EV-0134] | Daniel Bentes | [EV-0134] |
| TD-10 | `release-desktop-skills.yml` interpolates event data into a `run:` body | `.github/workflows/release-desktop-skills.yml` | The injection rule was written for the artifact shipped to others, never applied here | The repository fails a rule it publishes and tests. Exploitation needs release-publishing access, so severity is low. The inconsistency is not | Bind to `env:` and reference `"$TAG"` | two lines | **open.** The workflow still carries `permissions: contents: write` at `e104483` [EV-0133]. The scanner was not re-run (CT-0004) | Daniel Bentes | [EV-0015] (2026-07-26), [EV-0133], CT-0004 |
| TD-11 | Behavioural evaluation covers one plugin and gates nothing | `plugins/flow/evals/` | The harness was built for flow's correctness work | Nothing in CI runs the harness that exists. Unknown: whether any plugin other than flow has behavioural evaluation (AQ-0024) | Gate the harness in CI, then add cases for other plugins | The harness exists. One retained round cost $184.65 across 105 runs, which is the only cost basis available | **partially paid.** TM-0035 holds 4 cases and 82 tracked files [EV-0095]. Its retained summary is the harness's own report [EV-0096, R] | Daniel Bentes | [EV-0095], [EV-0096, R], AQ-0024 |
| TD-12 | Two install-time flags have no removal condition | `plugins/dossier/settings.json` | Flags added without sunset criteria | Configuration surface grows and never shrinks | State a removal condition, or accept them as permanent | one line each | **open** (2026-07-26, not re-checked — AQ-0022) | Daniel Bentes | [EV-0045] |
| TD-13 | Repository dossier config pinned an expected plugin version by hand | `.claude/settings.dossier.json` | The pin is set once and never revisited | None. It was corrected to 1.2.0 in commit `d5a5166` | Residual only: `bin/dossier-validate-config.sh` reports the file valid either way, because schema validity and semantic currency are different questions | — | **closed at `d5a5166`** [EV-0139] | Daniel Bentes | [EV-0085], [EV-0086], [EV-0139] |
| TD-14 | The flow test suite writes into the repository it runs in | `plugins/flow/tests/` | Test isolation was never enforced at the git level | Two branches and 3 commits authored by a fixture identity reached this repository. They were deleted on the maintainer's instruction. The suite defect is not fixed [EV-0164] | Make the suite run against a scratch clone, or assert cleanup | one fixture change plus an assertion | **open.** The leaked branches were deleted and the suite defect is not fixed [EV-0164] | Daniel Bentes | [EV-0164] |
| TD-15 | `block-destructive.sh` matches raw command text rather than parsed shell grammar | `plugins/flow/hooks/scripts/` | Pattern matching was the tractable implementation | Three legitimate Bash calls were refused during this refresh, all false positives of the same kind | Parse the command's shell grammar, or narrow the match to argument positions | one function, with a test per refused shape | **open** (AQ-0026) | Daniel Bentes | [EV-0172], [EV-0173], AQ-0026 |
| TD-16 | The documentation package has no project-model artifact | `docs/dossier/00-control/` | The model stayed implicit in `terminology-and-ownership.md` | `.project-model.json` has never existed, while the drafter agent names it as a required input. Separately, the blast radius could not route to this document, because its trigger map keys on source paths this repository does not use | Write the model artifact, or amend the skill to name the terminology register as the model | one file, or one skill edit | **open** (AQ-0014, AQ-0015) | Daniel Bentes | [EV-0130], AQ-0014, AQ-0015 |
| TD-17 | The dependency surface is unscanned | repository-wide | No scanner was ever configured | No SARIF, osv-scanner or Dependabot artifact exists, and there is no `dependabot.yml`. Nothing establishes whether a known vulnerability is present | Add a scheduled dependency scan and record its output | one workflow | **open.** This is the absence of a scan, not a clean result | Daniel Bentes | [EV-0121], [EV-0036] (2026-07-26) |

## Risk register

| ID | Risk | Category | Likelihood | Impact | Detectability | Urgency | Evidence | Mitigation | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| R-01 | ~~No licence file~~ | licensing | resolved | was High | — | — | [EV-0019], [EV-0020], [EV-0021], [EV-0132] | Apache-2.0 file added, every declaration aligned, and GitHub's derived field now reports `Apache-2.0`. Residual: copies taken before 2026-07-26 | Daniel Bentes | **closed** |
| R-02 | Nothing gates `main`: any change reaches every installer as executable code with no check having to pass | security | Medium | **High** | low — nothing would detect it | **immediate** | [EV-0131] | Branch protection requiring the test workflows | Daniel Bentes | open |
| R-03 | No security disclosure channel for code that runs on other people's machines | security | Medium | High | none | **immediate** | [EV-0036] (2026-07-26, not re-checked — AQ-0022) | `SECURITY.md` with one contact | Daniel Bentes | open |
| R-04 | One maintainer across 8 published plugins | staffing | Certain — it is the current state | High | high | high | [EV-0163] | Name a backup, or disclose single-maintainer status | Daniel Bentes | open |
| R-05 | dossier's headline capability has never executed | product | Certain | Medium-High | high, once run | high | AQ-0002, [EV-0123] | One end-to-end run in a scratch repository | Daniel Bentes | open |
| R-06 | Windows operators cannot use the plugins and were never told | product | Certain for affected operators | Medium | Only when an operator reports it — two have | high | [EV-0049] (2026-07-26, not re-checked), AQ-0008 | Support and test it, or state non-support | Daniel Bentes | open |
| R-16 | Both published releases ship pre-fix flow runtime scripts | delivery | Certain — it is the current published state | Medium-High | high, once compared | **immediate** | [EV-0144] | Cut a patch release carrying commit `16b4dc4` | Daniel Bentes | open |
| R-07 | flow's scripts and hooks are unanalysed, and its hooks are the ones that block on contributor machines | security | Medium | Medium | low | medium | TD-04, [EV-0165], [EV-0172] | Extend shellcheck to `flow-tests.yml` | Daniel Bentes | open, reduced |
| R-17 | A flow hook refuses legitimate commands on a contributor's machine | reliability | Certain — three refusals observed in this run | Medium | high, because the refusal is visible | medium | [EV-0172], [EV-0173], AQ-0026 | Parse shell grammar rather than raw text | Daniel Bentes | open |
| R-08 | A malformed or unresolvable manifest entry breaks or redirects all 8 plugins | delivery | Low | High | medium — version and sha disagreement is now caught in CI | medium | TD-01, [EV-0127] | Residual: whether an unresolvable entry is caught before publication is untested (AQ-0020) | Daniel Bentes | open, mitigated |
| R-18 | An installed dependency carries a known vulnerability that nothing here would surface | dependency | Unknown | Medium | none | medium | [EV-0121], [EV-0036] | A scheduled dependency scan | Daniel Bentes | open |
| R-11 | Four of six in-tree plugins are entirely unverified | delivery | Certain | Medium | low | medium | TD-03, CT-0022 | One structural suite each | Daniel Bentes | open |
| R-19 | The flow test suite writes branches and commits into the repository it runs in | delivery | Certain — observed once | Low-Medium | high, on inspection | medium | [EV-0164] | Run the suite against a scratch clone | Daniel Bentes | open |
| R-12 | A moved third-party action tag executes in CI, including in a `contents: write` job | dependency | Low | Medium | low | low | TD-08, [EV-0133] | SHA pinning | Daniel Bentes | open |
| R-13 | Prompt efficacy is measured for flow and gates nothing | AI | Certain | Medium | Unknown for the other plugins (AQ-0024) | low | TD-11, [EV-0095], AQ-0024 | Gate the existing harness, then extend it | Daniel Bentes | open, reduced |
| R-15 | The divergent `cascade-resolve.sh` copies disagree by 66 lines while one calls itself a twin of the other | architecture | Certain | Low-Medium | low | low | TD-05, [EV-0142], CT-0007 | Port the differences, or correct both headers | Daniel Bentes | open |
| R-20 | A documentation refresh cannot route its own blast radius, so corrected facts reach some documents and not others | architecture | Certain — this document is an instance | Medium | low | low | AQ-0015, [EV-0130] | Fix the trigger map, and write the project model | Daniel Bentes | open |
| R-09 | ~~Upstream `prompt-decorators` changes what installers receive, invisibly~~ | dependency | resolved | was Medium | — | — | [EV-0058], [EV-0127] | Pinned to sha `9c792fe`, which resolves to a tree reporting the advertised version. Residual: contents unverified (AQ-0005) | Daniel Bentes | **closed** |
| R-10 | ~~The README misleads a prospective operator on first read~~ | product | resolved | was Medium | — | — | [EV-0170], [EV-0171], [EV-0179] | Every advertised figure matches the tree at `d3fc744`. Residual: drift recurs, because the CI check reads manifests and not prose | Daniel Bentes | **closed** |
| R-14 | The project cannot tell whether it has users, so quality decisions are made blind | product | Certain | Medium | none | low | AQ-0004 | **Unresolvable.** Accept it and stop treating artifact quality as a proxy for outcome | Daniel Bentes | accepted |

### Risk category coverage

| Category | Represented by | Note |
|---|---|---|
| product | R-05, R-06, R-10, R-14 | |
| architecture | R-15, R-20 | |
| delivery | R-08, R-11, R-16, R-19 | |
| security | R-02, R-03, R-07 | |
| privacy | **N/A** | The project operates no service and receives no operator data. Shipped artifacts are Markdown, JSON and shell executed inside the operator's own session [EV-0044] |
| reliability | R-17 | Reliability here means a shipped hook's behaviour on an operator machine, not service uptime [EV-0044] |
| data | **N/A** | The project stores no data of its own. There is no runtime process and no persistent store [EV-0044] |
| AI | R-13 | |
| dependency | R-09, R-12, R-18 | |
| cost | **N/A** | The project runs no infrastructure. Its only execution environment is GitHub Actions on a public repository [EV-0044], [EV-0123], [EV-0132] |
| licensing | R-01 | |
| staffing | R-04 | |
| operational | **N/A** | There is nothing to operate and no on-call rotation, because every artifact executes inside the operator's own session [EV-0044] |

Each `N/A` above rests on the absence of a runtime, which is an examined design fact rather than an uninspected area [EV-0044].

## Risk dependencies

| Risk | Depends on or amplified by | Combined effect |
|---|---|---|
| R-02 (no merge gate) | R-04 (one maintainer) | A single compromised account is enough to reach every installer's machine, and no second reviewer exists at any point |
| R-02 | R-07 (flow unanalysed), R-11 (four plugins untested) | Where a check exists it is advisory, and where it would matter most it does not exist |
| R-03 (no disclosure channel) | R-02 | A researcher who finds the flaw R-02 lets through has no private channel, so the fastest fix path is also the most public one |
| R-16 (releases carry pre-fix scripts) | R-02 | The fix is on `main` and the published tags are not, and nothing forces a release to follow a merge |
| R-04 (one maintainer) | R-05, R-06, R-11, R-16 | Every open item has the same owner. The remediation list is not parallelizable, which is why it has stayed open |
| R-14 (no usage signal) | R-06, U-04 | Without knowing who uses what, deprecating a plugin and prioritizing Windows are decisions made blind |
| R-20 (routing failure) | R-10, R-11 | Corrections landed in some documents and not others. The AQ register records the same defect behind most of its open contradictions |

## Accepted risks

| Risk ID | Accepted by | Date | Basis for acceptance | Review date | Evidence of the acceptance |
|---|---|---|---|---|---|
| R-14 | Daniel Bentes | 2026-07-26 | Unresolvable from this repository. GitHub exposes no install telemetry for plugin marketplaces, and the plugins emit none by design. Accepted so that no document silently assumes a user base | when telemetry becomes available, if ever | Recorded as AQ-0004 and approved for publication as part of this package's claim set |

One accepted risk. Every other open row has no formal acceptance and no committed remediation date.

## Remediation roadmap

Horizons are ordering, not calendar commitments. Effort bases assume the current single maintainer and no external review step.

| Horizon | Item | Addresses | Kind | Effort basis | Owner | Status |
|---|---|---|---|---|---|---|
| Immediate | Cut a patch release carrying commit `16b4dc4` | R-16 | risk reduction | one release run, assuming the release workflow behaves as at `e104483` [EV-0133] | Daniel Bentes | not done [EV-0144] |
| Immediate | Enable branch protection on `main` requiring both test workflows | R-02, R-11 | risk reduction | one settings change, minutes, assuming admin access | Daniel Bentes | not done [EV-0131] |
| Immediate | Add `SECURITY.md` with a contact address | R-03 | risk reduction | one file, under an hour | Daniel Bentes | not done (2026-07-26, not re-checked — AQ-0022) |
| Immediate | ~~Fix the stale README facts~~ | R-10 | risk reduction | — | Daniel Bentes | **done** at `7ee4923` and `d3fc744` [EV-0170], [EV-0179] |
| Near-term | ~~One CI step validating the manifest~~ | R-08, TD-01, TD-02 | risk reduction | — | Daniel Bentes | **done.** TM-0033 runs and passes [EV-0080], [EV-0081], [EV-0127] |
| Near-term | ~~Pin both external marketplace sources~~ | R-09, TD-06, TD-07 | risk reduction | — | Daniel Bentes | **done** at `9e2f65b` and `9c792fe` [EV-0058], [EV-0127] |
| Near-term | Extend the shellcheck step to `flow-tests.yml` | R-07, TD-04 | risk reduction | one step plus whatever it surfaces, hours to days | Daniel Bentes | not done [EV-0165], AQ-0019 |
| Near-term | Make `block-destructive.sh` parse shell grammar | R-17, TD-15 | risk reduction | one function plus a test per refused shape, one to two days | Daniel Bentes | not done, AQ-0026 |
| Near-term | Make the flow suite run against a scratch clone | R-19, TD-14 | risk reduction | one fixture change plus an assertion, hours | Daniel Bentes | not done [EV-0164] |
| Near-term | Add a scheduled dependency scan and retain its output | R-18, TD-17 | risk reduction | one workflow, hours | Daniel Bentes | not done [EV-0121] |
| Near-term | Run dossier's post-merge workflow once, end to end, and record the run URL | R-05, AQ-0002 | capability investment | one scratch repository, one day | Daniel Bentes | not done [EV-0123] |
| Near-term | Decide and state the Windows policy, and add a `windows-latest` leg if supporting it | R-06, U-03 | risk reduction | one decision plus one CI leg, days if defects surface | Daniel Bentes | not done |
| Near-term | Write the package's project-model artifact, and fix the blast-radius trigger map | R-20, TD-16 | capability investment | one file plus one skill edit, days | Daniel Bentes | not done, AQ-0014, AQ-0015 |
| Strategic | A structural test suite for each of the four untested plugins | R-11, TD-03 | capability investment | harness is copyable, assertions are the work — days per plugin | Daniel Bentes | not done |
| Strategic | Gate the existing evaluation harness in CI, then extend it beyond flow | R-13, TD-11 | capability investment | one retained round cost $184.65 across 105 runs [EV-0096, R] | Daniel Bentes | not done |
| Strategic | Name a backup maintainer, or disclose single-maintainer status in the README | R-04, U-05 | risk reduction | one decision | Daniel Bentes | not done |
| Strategic | Reconcile the two `cascade-resolve.sh` copies, or correct both headers | R-15, TD-05 | optional improvement | one function plus two header edits, hours | Daniel Bentes | not done, CT-0007 |

The immediate horizon holds four items. Three are still open, and the cheapest of them, branch protection, also closes the highest-rated security risk in the register.

## Recommendations

Recommendation: cut the patch release before the next feature merge, so the published tags and `main` stop disagreeing about flow's runtime scripts [EV-0144].
