---
dossier-header: internal-v1
title: Security, Privacy, and Compliance
purpose: Lets a reviewer decide whether to install software that will execute on their machine, by naming what protects them and what does not.
audience: Reviewer, Installing operator, Maintainer
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: 06b1586
last-verified: 2026-07-26
review-trigger: A hook is added or changed; repository access controls change; a dependency or third-party action is added
related: [02-architecture/system-architecture.md, 02-architecture/data-and-ai.md, 05-due-diligence/assets-dependencies-and-licenses.md, 00-control/evidence-ledger.md]
---
# Security, Privacy, and Compliance
<!-- contract: references/package-contract-03-assurance.md#security-privacy-and-compliance -->

The security question for this project is not the usual one. There is no server to attack, no database to exfiltrate, and no session to hijack [EV-0044]. There is exactly one thing worth an attacker's attention: **this repository ships shell scripts that a Claude Code client will execute on other people's machines, at lifecycle points those people did not invoke** [EV-0040]. Everything below is organized around that.

## Scope

| Field | Value |
|---|---|
| Systems in scope | This repository at `06b1586`, its 4 GitHub Actions workflows, its live GitHub settings, and the 7 in-tree plugin trees including the checked-out submodule |
| Systems explicitly out of scope | The Claude Code client (not built or controlled here); the Anthropic API; `synaptiai/prompt-decorators`, whose contents are not present in this repository (AQ-0005); the upstream history of `agent-capability-standard` beyond the pinned commit (AQ-0006) |
| Evidence classes inspected | Tracked source, hook and `bin/` scripts, workflow definitions, dependency manifests, live repository settings via the GitHub API, and both plugin test suites executed |
| Evidence classes unavailable | Windows execution results (AQ-0008); GitHub audit logs; any runtime observation of a hook executing on an operator's machine; install telemetry (AQ-0004) |
| Assessment date | 2026-07-26 |
| Assessed against project version | `06b1586` on `fix/gate-verdict-integrity`, not `main` (AQ-0010) |

## Assets, actors, and trust boundaries

| Asset | Value to an attacker | Where it lives | Protected by | Evidence |
|---|---|---|---|---|
| Write access to `main` | Total. Anything pushed here reaches every installer's machine on their next client sync, as executable code | GitHub | A GitHub account with write access. **Nothing else — no branch protection, no rulesets, no required review, no required checks** | [EV-0016], [EV-0017], [EV-0051] |
| The 16 hook scripts | High. They execute on operator machines with the operator's full privileges, without being invoked | `plugins/{flow,dossier,agent-capability-standard}/hooks/` | Being readable plain text before install; 2,263 assertions over 2 of the 3 plugins | [EV-0038], [EV-0039], [EV-0040] |
| The 26 `bin/` scripts | Medium. Executed when a command calls them, on the operator's machine | `plugins/*/bin/` | Same as above | [EV-0007] |
| `marketplace.json` | High. It controls what every installer resolves and from where | the repository | Nothing. **No validation exists anywhere** | [EV-0026] |
| `synaptiai/prompt-decorators` `main` | High. It reaches installers under this marketplace's name with no commit here | an external repository | Whatever protects that repository — not visible from here | [EV-0030] |
| The `v4` tag of `actions/checkout` | Medium. It executes in this repository's CI, including in the `contents: write` release job | GitHub, third-party | GitHub's tag protections for that org. Pinned by major tag, **not by commit SHA** | [EV-0042] |
| Release assets | Low. Desktop skill ZIPs downloaded by Claude Desktop users | GitHub Releases | Write access; `--clobber` allows silent replacement | [EV-0012] |
| Credentials | none exist in the repository | — | — | [EV-0037] |

| Actor | Motivation | Access they start with | Capability assumed | Evidence |
|---|---|---|---|---|
| External researcher | Disclosure | Public read | Can read everything; **has no private channel to report through** | [EV-0036] |
| Opportunistic supply-chain attacker | Reach operator machines through a trusted-looking plugin | Public read | Could open a pull request; could not merge it without write access | [EV-0016] |
| Compromised maintainer account | Total control | Write access to `main` | Push directly, bypassing every check, reaching every installer | [EV-0016], [EV-0035] |
| Compromised upstream — `prompt-decorators` or the `checkout` action | Reach installers or CI | Write to a different repository | Change what installers of one plugin receive; execute in this repository's CI | [EV-0030], [EV-0042] |
| Malicious content in a repository a plugin reads | Prompt injection against an operator's session | Ability to get text into an issue, pull request, or file the operator's agent reads | Influence model behaviour inside the operator's session | [EV-0009] |

## Threat model

| Threat | Asset | Actor | Path | Control | Control state | Residual risk | Evidence |
|---|---|---|---|---|---|---|---|
| Malicious hook reaches operator machines | Operator machines | Compromised maintainer account, or a merged malicious change | Push to `main` → client `autoUpdate` sync → hook executes | Code review by convention; both test suites | **policy-only.** Review is not required, checks are not required, and neither suite would detect malice — they test portability and structure | **High.** A single compromised account is sufficient, and there is no second reviewer at any point | [EV-0016], [EV-0017], [EV-0035] |
| Manifest tampering redirects a plugin source | All installers | Same as above | Edit one `source` field | none | **unknown** — nothing validates the manifest | High | [EV-0026] |
| Upstream `main` of `prompt-decorators` is changed | Installers of that plugin | Whoever controls that repository | Floating `ref: main` resolves at install time | none | **not implemented** | Medium. Bounded to one plugin, invisible from here | [EV-0030] |
| Third-party action tag is moved | This repository's CI, including a `contents: write` job | Whoever controls `actions/checkout` | `@v4` resolves to a moved tag | none | **not implemented** — no SHA pinning | Low-to-medium. Requires compromising a major GitHub org | [EV-0042] |
| Prompt injection through content an agent reads | The operator's session and repository | Anyone who can place text where an agent reads it | Untrusted text is interpreted as instruction | dossier's CI path passes a static prompt carrying a path, never content, and marks untrusted values explicitly. flow's hooks block destructive commands and force-pushes at `PreToolUse` | **implemented in 2 plugins; unknown in the other 6**, none of which states an injection posture | Medium | [EV-0009], [EV-0038] |
| Credential exfiltration by an agent's own output | The operator's secrets | An injected or mistaken agent | Agent writes a secret into a file, a commit, or a public document | flow's `block-secrets.sh` at `PreToolUse`; dossier's claim scan redacts before reporting and gates `06-public/**` behind an approved register | implemented in 2 of 8 plugins | Medium | [EV-0038], [EV-0039] |
| Destructive command executed by an agent | The operator's filesystem and git history | An injected or mistaken agent | `rm -rf`, force-push, history rewrite | flow's `block-destructive.sh` and `block-force-push.sh` at `PreToolUse` | implemented, and **observed working during this project's own development**, where it blocked two `rm -rf` invocations by the author | Low, for operators who installed flow | [EV-0038] |
| Secret committed to this repository | This repository | maintainer error | `git commit` | flow's `block-secrets.sh` when flow is active in the session | implemented; scan confirms none present today | Low | [EV-0037], [EV-0038] |
| Shell script fails on the operator's platform | Operator sessions | not adversarial | A bash 4 construct, or a Windows path | Both suites forbid bash 4 constructs and require `set -u` and the executable bit | implemented for macOS and Linux; **not implemented for Windows** | Medium — 2 open issues report real failures | [EV-0008], [EV-0009], [EV-0049] |

## Identity and access controls

| Control | Mechanism | Applies to | Enforcement point | State | Last verified | Evidence |
|---|---|---|---|---|---|---|
| Authentication | GitHub accounts for writes; the operating-system user for execution | maintainer, CI | GitHub; the operator's OS | implemented | 2026-07-26 | [EV-0035] |
| Authorization | GitHub repository write permission | pushes, merges, tags, releases | GitHub | **implemented but ungated** — write permission alone is sufficient for every operation | 2026-07-26 | [EV-0016], [EV-0017] |
| Tenancy separation | N/A | — | — | N/A — there are no tenants | — | [EV-0044] |
| Isolation | **None.** Hook and `bin/` scripts run with the operator's full privileges; no sandbox is applied by this project | operator machines | none | not implemented | 2026-07-26 | [EV-0040] |
| Session management | N/A | — | — | N/A — the project holds no sessions | — | [EV-0044] |
| Administrative access | GitHub repository admin | branch protection, rulesets, secrets | GitHub | implemented; held by one person | 2026-07-26 | [EV-0016], [EV-0035] |

## Secrets, keys, and encryption

| Aspect | Practice | Scope it covers | Scope it does not cover | State | Evidence |
|---|---|---|---|---|---|
| Secret storage | No secret is stored in the repository, and none is required to build, test, or release it | tracked files | The operator's own machine, where an installed hook could read any secret present | implemented | [EV-0037] |
| Secret distribution | N/A. The only secret the codebase anticipates is `ANTHROPIC_API_KEY` in a *consuming* repository that scaffolds dossier's refresh workflow — not configured here | — | — | N/A | [EV-0045] |
| Key management | N/A — no keys are held or issued | — | — | N/A | [EV-0044] |
| Encryption in transit | HTTPS for all git and API traffic, provided by GitHub | distribution | — | implemented, inherited | [EV-0051] |
| Encryption at rest | GitHub's, for a public repository holding public content | hosting | — | implemented, inherited, and immaterial | [EV-0044] |
| Certificate management | N/A — no certificate is issued or terminated by this project | — | — | N/A | [EV-0044] |
| Rotation | N/A — nothing to rotate | — | — | N/A | [EV-0044] |
| Artifact signing | **Not implemented.** No commit signing requirement, no release signing, no provenance attestation. An installer cannot verify that what they received is what the maintainer published | — | everything | not implemented | [EV-0043] |

The last row is the one that matters for a distribution channel. Plugins arrive by `git clone` with no signature and no checksum, so an installer's only integrity guarantee is GitHub's transport and account security.

## Control layers

| Layer | Controls present | State | Gaps | Evidence |
|---|---|---|---|---|
| Network | HTTPS via GitHub | inherited | Nothing this project controls | [EV-0051] |
| Application | 16 hook scripts, of which flow's are deliberately restrictive: `block-destructive.sh`, `block-secrets.sh`, `block-force-push.sh`. dossier adds output-root containment, an action ceiling with all-false defaults, and unregistered-claim blocking | implemented in 2 plugins | The other 6 plugins ship no controls and state no posture | [EV-0038], [EV-0039], [EV-0040] |
| Infrastructure | Workflow `permissions` blocks: `contents: read` on both test workflows | partially implemented | **`codeql.yml` declares no top-level `permissions`** and falls back to the repository default token scope | [EV-0013], [EV-0014] |
| Supply chain | 1 declared dependency; 2 third-party actions | weak | No SHA pinning of actions; no `dependabot.yml`; no dependency scanning; one plugin source pinned to a floating ref; a submodule pointer 2 commits past its advertised tag | [EV-0030], [EV-0031], [EV-0036], [EV-0042] |
| Endpoint | N/A for the project; the operator's machine is the endpoint and is outside its control | not applicable | The project ships code that runs there and can constrain nothing about it | [EV-0040] |
| Physical | N/A — GitHub-hosted | inherited | — | [EV-0044] |

## Secure development and vulnerability management

| Practice | Current state | Enforced by | Coverage | Evidence |
|---|---|---|---|---|
| Threat modelling | This document is the first one. No prior threat model exists in the repository | nothing | first pass | [EV-0046] |
| Security review in code review | Pull requests are used by habit — 62 merged — but review is not required and there is only one reviewer, who is also the author | nothing | none guaranteed | [EV-0016], [EV-0035], [EV-0050] |
| Dependency scanning | **Absent.** No `dependabot.yml`, no scanning workflow | nothing | none | [EV-0036] |
| Static analysis | CodeQL on `actions` and `python` | `codeql.yml` | **Does not cover shell** — the language of all 26 `bin/` scripts and all 16 hook scripts, which is the project's entire executable surface on operator machines | [EV-0012], [EV-0007] |
| Secret scanning | flow's `block-secrets.sh` at `PreToolUse` in a maintainer's session; dossier's `dossier-validate-patch.sh` before any CI patch upload. Neither runs in this repository's CI | the flow plugin, when active | Session-time only. A commit made without flow active is unscanned | [EV-0037], [EV-0038] |
| Vulnerability triage and SLA | **None defined** | nothing | none | [EV-0036] |
| Patch cadence | Ad hoc. 57 releases over roughly 7 months | nothing | — | [EV-0032] |
| Disclosure process | **None.** No `SECURITY.md`, no contact address, no private channel. A researcher's only option is a public issue | nothing | none | [EV-0036] |

The static-analysis row deserves emphasis. CodeQL runs, which reads as coverage — but it analyses `actions` and `python`, and this project's risk lives in shell. **Nothing statically analyses the 42 shell scripts that execute on operator machines.**

## Logging, detection, and evidence preservation

| Capability | What is captured | Retention | Who can read it | Tamper resistance | Evidence |
|---|---|---|---|---|---|
| Application logging | N/A — no application runs | — | — | — | [EV-0044] |
| Audit logging | git history, GitHub's own audit log, and the Actions run history | GitHub's retention | public for history; admin for the audit log | git history is tamper-evident but **rewritable, since `main` has no protection against force-push** | [EV-0016], [EV-0034] |
| Detection and alerting | CodeQL alerts only | GitHub | maintainer | — | [EV-0012] |
| Evidence preservation | Actions run logs and release records | GitHub's retention | public | — | [EV-0012] |

There is no detection capability for the threat that matters. If a malicious hook were merged, nothing in this project would notice; the first signal would be an operator reporting it through a channel that does not exist.

## Data protection and privacy

| Data class | Purpose | Legal basis | Consent mechanism | Minimization | Retention | Deletion path | Residency | Evidence |
|---|---|---|---|---|---|---|---|---|
| none | The project collects, stores, and transmits no personal data | N/A | N/A | Complete — there is nothing to minimize | N/A | N/A | N/A | [EV-0044] |
| Contributor identity | git commit metadata: name and email in public history | Necessary to operate a public git repository | Implicit in contributing | git's minimum | indefinite | Rewriting history, which is destructive | GitHub | [EV-0035] |

| Data-subject right | Supported | Mechanism | Time to fulfil | Verified | Evidence |
|---|---|---|---|---|---|
| Access | N/A — no personal data is held beyond public git metadata | — | — | — | [EV-0044] |
| Erasure | Partially, for commit metadata only, and only by rewriting public history | manual | undefined | no | [EV-0034] |
| Portability | N/A | — | — | — | [EV-0044] |

No privacy regulation attaches to this project's own operations, because it processes no personal data. That is a genuine `N/A`, not an unexamined one.

## Subprocessors and third-party risk

| Party | Function | Data shared | Location | Contractual basis | Assessed | Evidence |
|---|---|---|---|---|---|---|
| GitHub | Hosting, distribution, CI, releases | Public repository content only | GitHub | Standard terms | no | [EV-0051] |
| Anthropic | The Claude Code client that executes every artifact | Nothing by this project. The operator's own session data goes to Anthropic under the operator's own agreement | — | The operator's own | no | [EV-0043] |
| `synaptiai/prompt-decorators` | One published plugin, resolved at install time from `ref: main` | none | GitHub | Same owner | **no** — contents never inspected from here (AQ-0005) | [EV-0030] |
| `actions/checkout`, `github/codeql-action` | CI steps | Repository contents during a run | GitHub | Open source | no | [EV-0042] |
| `pyyaml` | Runtime dependency of one plugin | none | PyPI | Open source | no | [EV-0041] |

## Applicable requirements

| Requirement | Source | Applicability | Basis for the applicability determination | Compliance state | Evidence |
|---|---|---|---|---|---|
| GDPR and equivalent privacy law | statutory | **Not applicable** to the project's own processing | It processes no personal data; it has no runtime, no accounts, and no store | N/A | [EV-0044] |
| SOC 2, ISO 27001 | contractual | Not applicable | No customer contract exists; the project is an unmonetized public repository | N/A | [EV-0044] |
| Open-source licence obligations | statutory | **Applicable and met** | The project distributes source publicly under Apache-2.0: the licence text is at the repository root and every plugin manifest and marketplace entry declares the same identifier | met as of 2026-07-26 | [EV-0019], [EV-0020], [EV-0021] |
| Apache-2.0 attribution obligations | statutory | Applicable | The whole distribution is Apache-2.0 | The licence text is present at the repository root and the submodule carries its own copy | met | [EV-0019], [EV-0021] |

## Control evidence and test dates

| Control | Last tested | Tested by | Method | Result | Next due | Evidence |
|---|---|---|---|---|---|---|
| flow hook and script behaviour | 2026-07-26 | this assessment | `plugins/flow/tests/run.sh` | 1022 pass, 0 fail | on change | [EV-0008] |
| dossier hook and script behaviour | 2026-07-26 | this assessment | `plugins/dossier/tests/run.sh` | 1241 pass, 0 fail | on change | [EV-0009] |
| No credentials in tracked files | 2026-07-26 | this assessment | `git grep` over the project's own detector pattern set | no match | every commit | [EV-0037] |
| No untrusted interpolation in workflow `run:` bodies | 2026-07-26 | this assessment | `awk` run-block scanner | **1 hit** — `release-desktop-skills.yml` line 24 | on workflow change | [EV-0015] |
| Branch protection on `main` | 2026-07-26 | this assessment | `gh api .../branches/main/protection` | **404 — not protected** | on settings change | [EV-0016] |
| Workflow permission scoping | 2026-07-26 | this assessment | YAML parse of all 4 workflows | 3 of 4 scoped; `codeql.yml` unscoped | on workflow change | [EV-0013], [EV-0014] |
| `agent-capability-standard` Python suite | never | — | — | not executed (AQ-0001) | — | [EV-0011] |
| Hook behaviour on a live operator machine | never | — | — | never observed | — | [EV-0040] |
| Windows execution | never | — | — | not executed (AQ-0008) | — | [EV-0049] |

## Gaps

| Gap | Severity | Likelihood | Impact | Affected assets | Remediation | Owner | Evidence |
|---|---|---|---|---|---|---|---|
| No gate on `main`: no protection, no rulesets, no required checks, no required review | **High** | Medium | Any change — mistaken or malicious — reaches every installer's machine as executable code, with no check having to pass | Every operator machine | Enable branch protection requiring both test workflows and one review | Daniel Bentes | [EV-0016], [EV-0017] |
| No security disclosure channel | **High** | Medium | A researcher who finds a flaw in a hook that runs on operator machines must disclose publicly or not at all | Every operator machine | Add `SECURITY.md` with one contact address | Daniel Bentes | [EV-0036] |
| Shell is not statically analysed | Medium | Medium | The entire executable surface on operator machines has no automated security analysis. CodeQL's presence makes this easy to miss | 42 shell scripts | Add `shellcheck` to both test workflows | Daniel Bentes | [EV-0012], [EV-0007] |
| No manifest validation | Medium | Medium | A malformed or tampered `marketplace.json` breaks or redirects all 8 plugins with nothing detecting it | All installers | One CI step: parse, resolve each source, compare versions | Daniel Bentes | [EV-0026] |
| `prompt-decorators` pinned to a floating ref | Medium | Medium | Content reaches installers under this marketplace's name with no commit, review, or record here | Installers of that plugin | Pin `source.ref` to a tag | Daniel Bentes | [EV-0030] |
| Third-party actions pinned by tag, not SHA | Medium | Low | A moved tag executes in CI, including in the `contents: write` release job | This repository's CI | Pin to commit SHAs | Daniel Bentes | [EV-0042] |
| `codeql.yml` declares no top-level `permissions` | Low | Low | Falls back to the repository default token scope rather than least privilege | CI | Add `permissions:` | Daniel Bentes | [EV-0014] |
| `release-desktop-skills.yml` interpolates event data into a `run:` body | Low | Low | Injection via a release tag name. Requires release-publishing access, so an attacker who could do it already has more direct paths — but the repository fails a rule it ships to others and tests for | CI | Bind to `env:` and reference `"$TAG"` | Daniel Bentes | [EV-0015], CT-0004 |
| No dependency scanning | Low | Low | Only one declared dependency exists, so exposure is small — but nothing would notice if that changed | Supply chain | Add `dependabot.yml` | Daniel Bentes | [EV-0036], [EV-0041] |
| Five of seven in-tree plugins have no tests | Medium | Medium | A change to them is unverified by anything, including their structural validity | Installers of those 5 | Add a structural suite per plugin | Daniel Bentes | [EV-0010] |

## Control state summary

| Control state | Count | Notes |
|---|---|---|
| Implemented and evidenced | 7 | Both test suites; the three flow blocking hooks; dossier's output-root containment and action ceiling; workflow permission scoping on 2 of 4 workflows |
| Policy-only — documented, implementation not evidenced | 3 | Code review; commit and branch conventions; the flow/gh-workflow coexistence rule. Each is stated in `.claude/CLAUDE.md` and enforced by nothing |
| Planned | 0 | No security work is committed anywhere in the repository — no issue, no milestone, no decision record |
| Unknown | 6 | The 5 untested plugins state no security posture; `prompt-decorators` was never inspected |

## Public claims and prohibited disclosures

| Safe to state publicly | Scope it holds within | Claim ID |
|---|---|---|
| Plugins run inside the operator's own Claude Code session; the marketplace operates no service and collects no telemetry | The marketplace itself, not the client or the model provider | CL-0007 |
| Three plugins register hooks — shell scripts the client runs on the operator's machine at defined lifecycle points | All 8 plugins | CL-0008 |
| The only declared third-party runtime dependency is `pyyaml` | Declared dependencies; not what the client itself requires | CL-0009 |
| No credential matching the project's own detector pattern set appears in any tracked file | Tracked files, enumerated patterns. **Must ship with that qualification** | CL-0016 |
| The `main` branch carries no branch protection and no rulesets | Live repository settings | CL-0013 |
| The repository publishes no security policy and no private disclosure channel | Current state | CL-0015 |
| The marketplace holds no personal data — no accounts, no server, no database | The marketplace itself | CL-0019 |

| Must not be disclosed | Why |
|---|---|
| Nothing in this document | The disclosure policy for this engagement is `public`, the repository is public, and every fact above is independently checkable by any reader. Withholding the gaps while publishing the controls would misrepresent the posture — which is the failure mode this documentation standard exists to prevent |
