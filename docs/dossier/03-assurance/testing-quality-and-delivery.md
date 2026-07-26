---
dossier-header: internal-v1
title: Testing, Quality, and Delivery
purpose: Lets a reader judge how much confidence the passing test numbers actually earn, and where they earn none.
audience: Reviewer, Contributor, Maintainer
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: fbeb1ee
last-verified: 2026-07-26
review-trigger: A test suite is added or removed; a workflow changes; branch protection or required checks change
related: [02-architecture/infrastructure-and-deployment.md, 03-assurance/security-privacy-and-compliance.md, 05-due-diligence/technical-due-diligence-report.md, 00-control/evidence-ledger.md]
---
# Testing, Quality, and Delivery
<!-- contract: references/package-contract-03-assurance.md#testing-quality-and-delivery -->

Two numbers dominate this document and both are real: 1022 passing assertions in flow, 1076 in dossier, zero failures at `fbeb1ee` [EV-0008], [EV-0009]. They are also narrower than they look, in three specific ways that this document exists to make explicit — they cover 2 of 7 in-tree plugins, they test structure rather than behaviour, and no check is required for merge.

## Quality strategy

| Dimension | Strategy | Owner | Evidence |
|---|---|---|---|
| Software | Shell test suites asserting structural invariants over Markdown and JSON, plus script behaviour. Markdown has no compiler, so the suites substitute for one | Daniel Bentes | [EV-0008], [EV-0009] |
| Product | **None.** No usability testing, no user research, no install telemetry. No signal exists about whether a plugin helps anyone (AQ-0004) | — | [EV-0044] |
| Data | N/A — the project holds no data | — | [EV-0044] |
| AI / model | **None.** This is a prompt-engineering product with no evaluation of prompt efficacy. A skill can pass every assertion and still make a model behave worse | — | [EV-0008], [EV-0009] |
| Hardware | N/A | — | [EV-0044] |
| Security | CodeQL on `actions` and `python`; hook-based secret and destructive-command blocking during authoring. **Shell is not statically analysed** | Daniel Bentes | [EV-0012], [EV-0038] |
| Accessibility | N/A — there is no user interface. Output is Markdown rendered by the operator's own client | — | [EV-0044] |
| Operational | N/A — there is no runtime to operate | — | [EV-0044] |

Four of eight dimensions are genuine `N/A` for a project with no runtime, no data, and no interface. Two are real gaps: product signal and model evaluation.

## Test levels and ownership

| Level | What it covers | Owner | Runs where | Runtime | Evidence |
|---|---|---|---|---|---|
| Structural | Frontmatter shape, required headings, line-count bounds, directory-to-file bijection, cross-reference resolution, contract-pointer anchors | Daniel Bentes | `tests/run.sh` in flow and dossier; both CI workflows | seconds | [EV-0008], [EV-0009] |
| Script unit | `bash -n`, executable bit, `set -u`, usage header, bash 3.2 portability, exit code 2 on unknown flags | Daniel Bentes | same | seconds | [EV-0009] |
| Script behaviour | Real fixtures in temporary directories: cascade precedence across five layers, the gate's refusal to emit PASS without a verdict, patch validation, claim scanning | Daniel Bentes | same | seconds | [EV-0009] |
| Invariant | Cross-artifact properties — that no verification agent loads the reconciliation skill, that all three passes carry `memory: none`, that they load three different second skills | Daniel Bentes | dossier suite | seconds | [EV-0009] |
| Static analysis | CodeQL over `actions` and `python` | GitHub | `codeql.yml` | ~40s per language | [EV-0012] |
| Python unit | The submodule's pytest suite | upstream | nowhere in this repository's CI | unknown | [EV-0011], AQ-0001 |
| Integration | **None.** No test installs a plugin, invokes a command, or fires a hook | — | — | — | [EV-0008], [EV-0009] |
| End-to-end | **None.** The dossier CI workflow has never executed (AQ-0002) | — | — | — | [EV-0045] |
| Behavioural / model | **None** | — | — | — | [EV-0008], [EV-0009] |

## Test inventory and coverage gaps

| Area | Tests present | Coverage measure | What the measure counts | Gap | Consequence of the gap | Evidence |
|---|---|---|---|---|---|---|
| flow | 1022 assertions | assertion count | Executed assertions, not lines or branches | No behavioural coverage; no Windows | A skill can be structurally perfect and unhelpful, and nothing detects it | [EV-0008] |
| dossier | 1076 assertions | assertion count | same | Its headline capability has never run (AQ-0002) | The plugin's central claim is unverified | [EV-0009], [EV-0045] |
| gh-workflow | **none** | — | — | total | 14 commands, 7 skills, 4 agents, entirely unverified | [EV-0010] |
| decipon | **none** | — | — | total | 7 commands, 5 agents unverified | [EV-0010] |
| context-ledger | **none** | — | — | total | 8 commands, 5 agents unverified | [EV-0010] |
| ai-first-org-design-kit | **none** | — | — | total | 15 skills unverified; its own description is off by one, which a structural test would catch | [EV-0010], [EV-0027] |
| agent-capability-standard | pytest suite exists upstream | unknown | — | Not run in this repository's CI | The only dependency-bearing plugin is untested here | [EV-0011], AQ-0001 |
| `marketplace.json` | **none** | — | — | total | The highest-blast-radius file has no check at all | [EV-0026] |
| `README.md` | **none** | — | — | total | 4 verified-stale facts are live right now | [EV-0022]–[EV-0025] |

| Critical path | Tested | Test | Evidence |
|---|---|---|---|
| Manifest parses and every source resolves | **no** | — | [EV-0026] |
| Plugin version agrees with its manifest entry | **no** — verified by hand during this assessment | — | [EV-0026] |
| A hook script is executable and portable | yes, for flow and dossier | `bin-scripts.test.sh`, `hooks.test.sh` | [EV-0008], [EV-0009] |
| A hook blocks what it claims to block | **no** — no runtime test exists | — | [EV-0038] |
| A command's declared skills all resolve on disk | yes, for flow and dossier | `command-frontmatter.test.sh` | [EV-0009] |
| The dossier gate cannot self-certify | yes | `bin-scripts.test.sh` anti-theater assertion | [EV-0009] |
| A plugin installs and loads | **no** | — | [EV-0052] |

## Quality gates

| Stage | Gate | Blocking | Bypassable | Bypass requires | Evidence |
|---|---|---|---|---|---|
| Local development | flow's `PreToolUse` hooks — destructive commands, force-pushes, secrets | yes, within a session where flow is active | yes | Not using flow, or not using Claude Code | [EV-0038] |
| Pull request / CI | `flow-tests.yml`, `dossier-tests.yml`, `codeql.yml` | **no — advisory only** | trivially | Nothing. No check is required, so a failing run does not prevent a merge | [EV-0013], [EV-0016] |
| Release | None. A tag and a release can be created regardless of CI state | no | — | Nothing | [EV-0032] |
| Production | N/A — `main` is production, and the push is the deploy | no | — | Nothing | [EV-0016] |

This table is the core finding of the document. The project has genuinely good tests and **no gate anywhere that stops a change**. The 2,098 assertions are information, not enforcement.

## Static and supply-chain checks

| Check | Tool | Scope | Runs where | Blocking | Last result | Evidence |
|---|---|---|---|---|---|---|
| Static analysis | CodeQL | `actions`, `python` | `codeql.yml` on push, pull request, schedule | no | pass, 2026-07-25 | [EV-0012] |
| Formatting | none | — | — | — | — | [EV-0012] |
| Linting | none for shell — **no `shellcheck`**, despite 42 shell scripts being the whole executable surface | — | — | — | — | [EV-0007] |
| Type checking | N/A for Markdown and shell. `mypy` is a dev dependency of the submodule but is not run here | — | — | — | — | [EV-0041] |
| Dependency scanning | **none.** No `dependabot.yml` | — | — | — | — | [EV-0036] |
| Artifact verification | **none.** No commit signing, no release signing, no provenance attestation, no SHA-pinned actions | — | — | — | — | [EV-0042] |
| Executable-bit check | `dossier-tests.yml` | dossier's `bin/` and `hooks/scripts/` | CI | no | pass | [EV-0009] |
| Version-drift check | `dossier-tests.yml` | `plugin.json`, `marketplace.json`, and `settings.json` for **dossier only** | CI | no | pass | [EV-0009] |

The last row is worth noting as a near-miss: dossier ships exactly the version-drift check the whole marketplace needs, scoped to itself. Generalizing it to all 8 entries is a small change that would close the manifest gap.

## Test data and environments

| Concern | Approach | Contains production data | Refresh | Evidence |
|---|---|---|---|---|
| Test data | Fixtures created in `mktemp -d` directories at test time and removed after. No committed fixture corpus beyond small inline files | no — there is no production data to contain | per run | [EV-0009] |
| Test environments | The maintainer's macOS shell (bash 3.2) and ubuntu-latest (bash 5). **No Windows environment** | no | per run | [EV-0008], [EV-0049] |
| Fixtures and seeds | Inline heredocs and generated JSON; credential *patterns* appear in secret-scanner fixtures by necessity and are never real values | no | per run | [EV-0037] |

## Flaky tests, quarantines, and manual gates

| Item | Kind | Where | Since | Owner | Impact | Evidence |
|---|---|---|---|---|---|---|
| An intermittent failure in `flow-goal-stop.test.sh` | flaky | flow | first observed 2026-07-26 | Daniel Bentes | Failed 4 assertions on one run, then passed 10 consecutive runs. **Not reproduced.** A suite that is already advisory is worth less again if its pass is not repeatable | [EV-0055] |
| Temp directories leaked every run | harness defect | both suites | since the harness was written | Daniel Bentes | flow +254 and dossier +81 directories per run. Test files are *sourced*, so an `EXIT` trap set by one is replaced by the next file's, and a trailing cleanup line strands above anything appended after it. Fixed in dossier by scoping `TMPDIR` to a runner-owned directory that is removed on exit; **still present in flow** | [EV-0056] |
| No quarantined or skipped test | — | — | — | — | Both suites report 0 failures and no deliberate skips | [EV-0008], [EV-0009] |
| Conditional degradation on missing `pyyaml` | graceful skip, not a quarantine | `workflow-template.test.sh` | since the test was written | Daniel Bentes | The YAML parse check is skipped where `pyyaml` is absent; it records a pass with the reason and continues structural checks. CI pins `pyyaml`, so the skip does not occur there | [EV-0009] |
| Version bump across two files | manual gate | `plugin.json` and `marketplace.json` | always | Daniel Bentes | Consistent today, verified by hand; nothing enforces it | [EV-0026] |
| README accuracy | manual gate | `README.md` | always | Daniel Bentes | **Already failed** — 4 stale facts | [EV-0022]–[EV-0025] |
| Submodule pointer alignment | manual gate | `.gitmodules` | always | Daniel Bentes | **Already drifted** — 2 commits past the advertised tag | [EV-0031] |

Three of the five manual gates have already failed at least once. That is the empirical case for automating them — and the two harness rows above make the same point about the suites themselves: a test that leaks state is a test whose result depends on how many times it has run before.

## Delivery pipeline

| Aspect | Current practice | Enforced by | Evidence |
|---|---|---|---|
| CI workflows | 4, path-filtered. Both test workflows scope `permissions: contents: read` | `.github/workflows/` | [EV-0012], [EV-0013] |
| Branch policy | `feature/issue-{n}-{desc}`, `fix/…`, `docs/…` | `.claude/CLAUDE.md`; unenforced | `.claude/CLAUDE.md` |
| Review policy | Pull requests used by habit — 62 merged against 198 commits | **nothing** | [EV-0016], [EV-0050] |
| Artifact provenance | none | — | [EV-0043] |
| Signing | none | — | [EV-0043] |
| Promotion between environments | N/A — one environment | — | [EV-0044] |

## Release process

| Aspect | Current practice | Evidence |
|---|---|---|
| Cadence | Ad hoc. 57 tags; latest `v4.6.2` on 2026-05-29 | [EV-0032] |
| Approval | None required | [EV-0016] |
| Rollback | `git revert` and push. Installers pick it up on their next client sync, on a schedule this project neither controls nor observes | [EV-0051] |
| Hotfix path | Identical to the normal path, because the normal path has no gate to skip | [EV-0016] |

The manifest currently advertises `metadata.version` 4.7.0 with no corresponding tag [EV-0033]. That is expected on an unmerged feature branch, and it is also exactly the state that a manifest check would flag if one existed.

## Delivery metrics

| Metric | Value | Window | Source | State | Evidence |
|---|---|---|---|---|---|
| Change failure rate | **unknown** — no incident record exists to divide by | — | — | U | [EV-0036] |
| Defect escape rate | **unknown**. 2 open issues, both portability reports from users, which is the only escape signal that exists | live | GitHub issues | U | [EV-0049] |
| Incident rate | **unknown** — no incident process, and no runtime for an incident to occur in | — | — | U | [EV-0044] |
| Lead time to production | Effectively zero — a push to `main` is production | live | git | I — inferred from the absence of any gate | [EV-0016] |
| Deployment frequency | 198 commits to `main` over ~7 months, each of which is a deployment | 2025-12-19 to 2026-07-25 | git | V | [EV-0034] |
| Merged pull requests | 62 | full history | GitHub | V | [EV-0050] |
| Test assertions executed per run | 2,098 across both suites | per CI run | `tests/run.sh` | V | [EV-0008], [EV-0009] |

Three of the seven metrics are `unknown`, and they are the three that would measure whether quality is *achieved* rather than *attempted*. That is the honest summary of this project's delivery evidence: the inputs are visible, the outcomes are not.

## Commands executed during documentation verification

| Command | Purpose | Environment | Date | Result | Output artifact |
|---|---|---|---|---|---|
| `plugins/flow/tests/run.sh` | Verify flow's suite passes | macOS 25.5, bash | 2026-07-26 | pass | `TOTAL pass=1022 fail=0` |
| `plugins/dossier/tests/run.sh` | Verify dossier's suite passes | macOS 25.5, bash | 2026-07-26 | pass | `TOTAL pass=1076 fail=0` |
| `ls plugins/*/tests/run.sh` | Establish which plugins have suites | macOS 25.5 | 2026-07-26 | 2 matches | [EV-0010] |
| YAML parse of all 4 workflows | Establish triggers, permissions, jobs | python3 + pyyaml | 2026-07-26 | 4 parsed | [EV-0012], [EV-0013], [EV-0014] |
| `awk` run-block scanner | Find untrusted interpolation in `run:` bodies | macOS 25.5 | 2026-07-26 | 1 hit | [EV-0015] |
| `gh api .../branches/main/protection` | Establish whether any merge gate exists | gh | 2026-07-26 | HTTP 404 | [EV-0016] |
| `gh api .../rulesets` | Same, for rulesets | gh | 2026-07-26 | empty | [EV-0017] |
| Per-plugin version comparison | Check `plugin.json` against the manifest | jq | 2026-07-26 | 7 of 7 match | [EV-0026] |
| `gh run list --json workflowName` | Establish whether the dossier refresh has ever run | gh | 2026-07-26 | 4 names, refresh absent | [EV-0045] |
| `dossier-scaffold.sh`, `dossier-package-check.sh`, `dossier-validate-config.sh` | Exercise the plugin under assessment against this repository | bash | 2026-07-26 | 23 created, config valid | [EV-0047], [EV-0048] |

| Command not executed | Why | What it would have established |
|---|---|---|
| `pytest plugins/agent-capability-standard` | Requires installing a Python environment; `engagement.allowedActions.runBuild` is `false` for this run | Whether the only dependency-bearing plugin's tests pass (AQ-0001) |
| The dossier post-merge workflow, end to end | Requires a scratch repository, an API-key secret, and a merged pull request | Whether the plugin's headline capability works at all (AQ-0002) |
| A clean-profile marketplace install | `engagement.allowedActions.networkAccess` is `false` | Whether a first-time install succeeds (AQ-0003) |
| Both suites on Windows | No Windows environment available | The real scope of issues #100 and #130 (AQ-0008) |
| Any behavioural evaluation of any skill | None exists to run | Whether the prompts improve model behaviour |
