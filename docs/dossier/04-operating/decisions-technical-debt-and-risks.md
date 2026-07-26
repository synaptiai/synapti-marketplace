---
dossier-header: internal-v1
title: Decisions, Technical Debt, and Risks
purpose: Gives a decision-maker the ranked list of what could go wrong, what it would cost to fix, and what was never decided in the first place.
audience: Maintainer, Reviewer
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: 06b1586
last-verified: 2026-07-26
review-trigger: A risk changes state; a debt item is remediated; a decision is made or recorded
related: [01-project/executive-project-brief.md, 03-assurance/security-privacy-and-compliance.md, 05-due-diligence/technical-due-diligence-report.md, 00-control/assumptions-questions-and-contradictions.md]
---
# Decisions, Technical Debt, and Risks
<!-- contract: references/package-contract-04-operating.md#decisions-technical-debt-and-risks -->

## Decision log

| ID | Decision | Date | Status | Record | Rationale state | Evidence |
|---|---|---|---|---|---|---|
| D-01 | Distribute through the Claude Code plugin client rather than a package registry | unknown | in force | none | **unrecorded** — inferred from the absence of any registry manifest or publish step | [EV-0043] |
| D-02 | Ship `flow` alongside `gh-workflow` rather than deprecating the older one | unknown | in force | `.claude/CLAUDE.md` states hook conflicts as the reason for enabling only one | reported, not a decision record | [EV-0004] |
| D-03 | Source `agent-capability-standard` as a git submodule | unknown | in force | `.gitmodules` only | unrecorded | [EV-0031] |
| D-04 | Source `prompt-decorators` as a `git-subdir` at the floating ref `main` | unknown | in force | the manifest entry only | unrecorded | [EV-0030] |
| D-05 | Copy `cascade-resolve.sh` and the test harness into dossier rather than sharing them | 2026-07 | in force | The dossier plan document | reported — plugins install independently, so a runtime dependency cannot be assumed | [EV-0007] |
| D-06 | Put conditional config rules in a validator script rather than in `schema.json` | 2026-07 | in force | `schema.json` comments and dossier's own tests | recorded, with the reason: the documented fallback validator ignores `if`/`then` when `jsonschema` is absent | [EV-0009] |
| D-07 | Make dossier's verification-pass independence architectural rather than instructed | 2026-07 | in force | `agent-independence.test.sh` | recorded, enforced by test | [EV-0009] |
| D-08 | Require bash 3.2 compatibility across all shipped scripts | unknown | in force | Both test suites assert it | recorded by test, rationale unstated but evident — macOS ships bash 3.2 | [EV-0008], [EV-0009] |

| Decision | Chosen because | Alternatives considered | Why rejected | Evidence |
|---|---|---|---|---|
| D-05 | Plugins install independently; a shared library plugin could not be assumed present at runtime | A shared library plugin | Unresolvable at the installed-plugin level | [EV-0007] |
| D-06 | A schema conditional would validate successfully and enforce nothing on exactly the machines lacking the optional dependency | `if`/`then` in the schema | Silent non-enforcement is worse than no rule | [EV-0009] |
| D-07 | Instructed independence drifts toward consensus; separate dispatches, `memory: none`, and a skill firewall make it structural | Instructing the passes to stay independent | Correlated review error is the failure mode the design exists to prevent | [EV-0009] |

| Decision | What is visible | What is unknown | Risk of reversing blind |
|---|---|---|---|
| D-01 | The manifest, the client's resolution behaviour, the absence of any publish step | Whether a registry was ever considered, and whether the client supports one | Low — reversal would be additive |
| D-02 | Both plugins ship; `.claude/CLAUDE.md` warns about hook conflicts | Whether `gh-workflow` has users, and whether deprecating it would break anyone (AQ-0004) | **Medium** — removing a published plugin breaks every installer of it, and there is no way to count them or tell them |
| D-03, D-04 | The source kinds and their pinning | Why one is pinned to a commit and the other floats on `main` | Medium for D-04 — pinning would change what installers receive, silently, in whichever direction |
| D-08 | The assertions | Whether any operator actually runs bash 3.2, or whether this is precaution | Low |

Eight decisions in force; **three have no recorded rationale at all**, and the repository's 11 decision records cover none of them [EV-0046]. The three unrecorded ones are the architectural ones.

## Unresolved decisions

| ID | Decision needed | Options | Blocked by | Decides | Deadline | Consequence of not deciding |
|---|---|---|---|---|---|---|
| U-01 | ~~Add a `LICENSE` file, and which licence it states~~ | — | — | Daniel Bentes | — | **Decided 2026-07-26: Apache-2.0.** File added; 7 plugin manifests, 8 marketplace entries, the README, 5 plugin READMEs, and the project instructions aligned to it |
| U-02 | Whether dossier's post-merge automation may be described as working | Run it once and claim it · ship it undescribed · withhold the plugin | An end-to-end run | Daniel Bentes | before dossier is announced | The plugin's headline capability rests on unit tests of its parts (AQ-0002) |
| U-03 | Windows support policy | Support and test it · declare it unsupported in the README · leave silent | nothing | Daniel Bentes | issue #100 has been open without resolution | Operators discover non-support by failing, having been told nothing |
| U-04 | Whether to deprecate `gh-workflow` | Deprecate with notice · keep both · merge them | AQ-0004 — no usage signal exists | Daniel Bentes | none | Two overlapping workflow plugins with conflicting hooks continue to ship with no guidance beyond a `CLAUDE.md` line |
| U-05 | Whether to name a backup maintainer, or to state single-maintainer status publicly | Name one · state it in the README · neither | nothing | Daniel Bentes | none | 8 published plugins have a bus factor of one and installers cannot weigh it |
| U-06 | Whether to make CI blocking | Require both suites in branch protection · leave advisory | nothing | Daniel Bentes | none | 2,263 assertions remain information rather than enforcement |

## Technical debt register

| ID | Debt | Location | Introduced | Why it exists | Interest paid | Remediation | Effort basis | Owner | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| TD-01 | No validation of `marketplace.json` | `.github/workflows/` | always | The manifest was never treated as code | The highest-blast-radius file has no check. Version agreement was verified by hand during this assessment | One CI step: parse, resolve each source, compare versions to each `plugin.json` | dossier already ships this check scoped to itself; generalizing it is the work | Daniel Bentes | [EV-0026] |
| TD-02 | README drifts from the manifest | `README.md` | ongoing | Prose and manifest are edited in different commits | **Four wrong facts live today**: badge says 6 plugins where 8 exist, flow 3.2.0 vs 3.2.2, prompt-decorators 0.1.0 vs 0.1.1, dossier absent | Generate the plugin table, or check it in CI | Same CI step as TD-01 | Daniel Bentes | [EV-0022]–[EV-0025] |
| TD-03 | 5 of 7 in-tree plugins have no tests | `plugins/{gh-workflow,decipon,context-ledger,ai-first-org-design-kit}` | as each was added | Suites were written for the two plugins under active development | Any change to those five is unverified, including structural validity. `ai-first-org-design-kit`'s own off-by-one description would have been caught by a structural test | One structural suite per plugin | The dossier and flow harnesses are copyable; the assertions are the work | Daniel Bentes | [EV-0010], [EV-0027] |
| TD-04 | Shell is not statically analysed | `.github/workflows/codeql.yml` | always | CodeQL covers `actions` and `python`; the project's executable surface is shell | 42 scripts that run on operator machines have no automated security analysis, while CodeQL's presence reads as coverage | Add `shellcheck` to both test workflows | one workflow step plus whatever it surfaces | Daniel Bentes | [EV-0012], [EV-0007] |
| TD-05 | `cascade-resolve.sh` exists twice and has diverged | `plugins/{flow,dossier}/bin/` | 2026-07 | Deliberate copy (D-05); the copy was then fixed and the original was not | dossier's copy decides absence with `jq -e`; flow's does not. **The same class of defect may still be live in flow**, and neither file records that the other exists | Port the fix, or note the divergence in both | one function | Daniel Bentes | [EV-0007] |
| TD-06 | `prompt-decorators` pinned to a floating ref | `.claude-plugin/marketplace.json` | at entry creation | No pinning decision was recorded (D-04) | Installs are not reproducible; content reaches installers under this marketplace's name with no record here | Pin `source.ref` to a tag | one field | Daniel Bentes | [EV-0030] |
| TD-07 | Submodule pointer past its advertised tag | `.gitmodules` | when the pointer last moved | Manual step with no check | The marketplace advertises 1.2.0 and ships a tree 2 commits past `v1.2.0` | Move the pointer to the tag, or re-tag upstream | one command | Daniel Bentes | [EV-0031] |
| TD-08 | Third-party actions pinned by major tag | `.github/workflows/` | always | Convention | A moved tag executes in CI, including in the `contents: write` release job | Pin to commit SHAs | three lines | Daniel Bentes | [EV-0042] |
| TD-09 | `codeql.yml` has no top-level `permissions` | `.github/workflows/codeql.yml` | always | Omission | Falls back to the repository default token scope instead of least privilege | Add a `permissions:` block | one line | Daniel Bentes | [EV-0014] |
| TD-10 | `release-desktop-skills.yml` interpolates event data into a `run:` body | `.github/workflows/release-desktop-skills.yml` line 24 | always | The injection rule was written for the artifact shipped to others, never applied here | The repository fails a rule it publishes and tests. Exploitation needs release-publishing access, so severity is low — the inconsistency is not | Bind to `env:` and reference `"$TAG"` | two lines | Daniel Bentes | [EV-0015], CT-0004 |
| TD-11 | No behavioural evaluation of any prompt | everywhere | always | Structural testing was the tractable thing | This is a prompt-engineering product with no measurement of whether its prompts help. A skill can pass every assertion and make a model worse | One evaluation harness, then per-skill cases | Unknown — nothing comparable exists in the repository | Daniel Bentes | [EV-0008], [EV-0009] |
| TD-12 | Two install-time flags have no removal condition | `plugins/dossier/settings.json` | 2026-07 | Flags added without sunset criteria | Configuration surface grows and never shrinks | State a removal condition, or accept them as permanent | one line each | Daniel Bentes | [EV-0045] |

## Risk register

| ID | Risk | Category | Likelihood | Impact | Detectability | Urgency | Evidence | Mitigation | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| R-01 | ~~No licence file~~ | legal | resolved | was High | — | — | [EV-0019], [EV-0020], [EV-0021] | Apache-2.0 licence file added and every declaration aligned. Residual: copies taken before 2026-07-26, and GitHub's derived field which updates on merge (AQ-0011) | Daniel Bentes | **closed** |
| R-02 | Nothing gates `main`: any change reaches every installer as executable code with no check having to pass | security | Medium | **High** | low — nothing would detect it | **immediate** | [EV-0016], [EV-0017] | Branch protection requiring both suites | Daniel Bentes | open |
| R-03 | No security disclosure channel for code that runs on other people's machines | security | Medium | High | none | **immediate** | [EV-0036] | `SECURITY.md` with one contact | Daniel Bentes | open |
| R-04 | Bus factor of one across 8 published plugins | organizational | Certain — it is the current state | High | high | high | [EV-0035] | Name a backup, or disclose single-maintainer status | Daniel Bentes | open |
| R-05 | dossier's headline capability has never executed | product | Certain | Medium-High | high, once run | high | AQ-0002, [EV-0045] | One end-to-end run in a scratch repository | Daniel Bentes | open |
| R-06 | Windows operators cannot use the plugins and were never told | product | Certain for affected operators | Medium | Only when an operator reports it — two have | high | [EV-0049] | Support and test it, or state non-support | Daniel Bentes | open |
| R-07 | Shell — the whole executable surface — is unanalysed | security | Medium | Medium | low | medium | TD-04 | `shellcheck` in CI | Daniel Bentes | open |
| R-08 | A malformed or tampered manifest breaks or redirects all 8 plugins | availability | Low | High | **none — nothing checks it** | medium | TD-01 | One CI step | Daniel Bentes | open |
| R-09 | Upstream `prompt-decorators` changes what installers receive, invisibly | supply chain | Medium | Medium | none | medium | TD-06 | Pin the ref | Daniel Bentes | open |
| R-10 | The README misleads a prospective operator on first read | product | Certain — four facts wrong now | Medium | high, once compared | medium | TD-02 | Fix, then check in CI | Daniel Bentes | open |
| R-11 | Five plugins are entirely unverified | quality | Certain | Medium | low | medium | TD-03 | One structural suite each | Daniel Bentes | open |
| R-12 | A moved third-party action tag executes in CI, including in a `contents: write` job | supply chain | Low | Medium | low | low | TD-08 | SHA pinning | Daniel Bentes | open |
| R-13 | Prompt efficacy is unmeasured — the product's core value has no evidence either way | product | Certain | Medium | none | low | TD-11 | An evaluation harness | Daniel Bentes | open |
| R-14 | The project cannot tell whether it has users, so quality decisions are made blind | product | Certain | Medium | none | low | AQ-0004 | **Unresolvable.** Accept it and stop treating artifact quality as a proxy for outcome | — | accepted |
| R-15 | The divergent `cascade-resolve.sh` copy means a fixed defect may still be live in flow | correctness | Medium | Low-Medium | low | low | TD-05 | Port the fix or note the divergence | Daniel Bentes | open |

## Risk dependencies

| Risk | Depends on / amplified by | Combined effect |
|---|---|---|
| R-02 (no merge gate) | R-04 (bus factor of one) | A single compromised account is sufficient to reach every installer's machine, and there is no second reviewer at any point in the chain |
| R-02 | R-07 (shell unanalysed), R-11 (5 plugins untested) | Even where a check exists it is advisory, and where it would matter most — shell, and five plugins — it does not exist |
| R-03 (no disclosure channel) | R-02 | A researcher who finds the flaw that R-02 lets through has no way to report it privately, so the fastest fix path is also the most public one |
| R-04 (bus factor) | R-05, R-06, R-10, R-11 | Every open item has the same owner. The remediation list is not parallelizable, which is why it has stayed open |
| R-14 (no usage signal) | R-06, R-10, U-04 | Without knowing who uses what, deprecating a plugin, prioritizing Windows, and judging README harm are all decisions made blind |
| R-01 (resolved) | R-14 | While it was open, the project could not tell whether the missing licence affected everyone or nobody. That is the general shape of every risk here: no usage signal means no way to size the blast radius of anything |

## Accepted risks

| Risk ID | Accepted by | Date | Basis for acceptance | Review date | Evidence of the acceptance |
|---|---|---|---|---|---|
| R-14 | Daniel Bentes | 2026-07-26 | Unresolvable from this repository. GitHub exposes no install telemetry for plugin marketplaces, and the plugins emit none by design. Accepted so that no document silently assumes a user base | when telemetry becomes available, if ever | Recorded as AQ-0004 and approved for publication as part of this package's claim set |

One accepted risk. Every other row is open, none has been formally accepted, and none has a committed remediation date.

## Remediation roadmap

| Horizon | Item | Addresses | Kind | Effort basis | Owner |
|---|---|---|---|---|---|
| Immediate | Enable branch protection on `main` requiring both test workflows | R-02, R-11 | risk reduction | one settings change | Daniel Bentes |
| Immediate | Add `SECURITY.md` with a contact address | R-03 | risk reduction | one file | Daniel Bentes |
| Immediate | Fix the four stale README facts | R-10 | risk reduction | one edit | Daniel Bentes |
| Near-term | One CI step validating the manifest: parse, resolve each source, compare every version to its `plugin.json`, compare README facts | R-08, R-10, TD-01, TD-02 | risk reduction | dossier ships this check scoped to itself; generalizing it is the work | Daniel Bentes |
| Near-term | Add `shellcheck` to both test workflows | R-07, TD-04 | risk reduction | one step plus fixes | Daniel Bentes |
| Near-term | Run dossier's post-merge workflow once, end to end, and record the run URL | R-05, AQ-0002 | capability investment | one scratch repository | Daniel Bentes |
| Near-term | Pin `prompt-decorators` to a tag; move the submodule pointer to `v1.2.0` | R-09, TD-06, TD-07 | risk reduction | two edits | Daniel Bentes |
| Near-term | Decide and state the Windows policy; add a `windows-latest` leg if supporting it | R-06, U-03 | risk reduction | one decision, one CI leg | Daniel Bentes |
| Strategic | A structural test suite for each of the 5 untested plugins | R-11, TD-03 | capability investment | harness is copyable; assertions are the work | Daniel Bentes |
| Strategic | A behavioural evaluation harness for skills | R-13, TD-11 | capability investment | nothing comparable exists in the repository to estimate from | Daniel Bentes |
| Strategic | Name a backup maintainer, or disclose single-maintainer status in the README | R-04, U-05 | risk reduction | one decision | Daniel Bentes |

The immediate row is four items, none taking more than an edit, and together they close the two gate-blocking conditions and the two highest-severity security gaps. That concentration is the most actionable fact in this package: **the project's worst-rated risks are also its cheapest to fix.**
