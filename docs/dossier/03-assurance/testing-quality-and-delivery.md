---
dossier-header: internal-v1
title: Testing, Quality, and Delivery
purpose: Lets a reader judge how much confidence the passing test numbers actually earn, and where they earn none.
audience: Reviewer, Contributor, Maintainer
confidentiality: Internal
owner: Daniel Bentes
status: partially verified
project-version: 7ee4923
last-verified: 2026-09-10
review-trigger: A test suite is added or removed; a workflow changes; branch protection or required checks change
related: [02-architecture/infrastructure-and-deployment.md, 03-assurance/security-privacy-and-compliance.md, 05-due-diligence/technical-due-diligence-report.md, 00-control/evidence-ledger.md]
---
# Testing, Quality, and Delivery
<!-- contract: references/package-contract-03-assurance.md#testing-quality-and-delivery -->

Both authored suites pass. The flow suite reports `pass=2336 fail=0` at `af6e632` [EV-0098]. The dossier suite reports `pass=1951 fail=0` at the same commit [EV-0107]. Both runs happened on macOS 25.6 under `/bin/bash` 3.2.57 [EV-0098], [EV-0107]. GitHub Actions concluded `success` on `ubuntu-latest` for every commit this range added to `main` [EV-0126].

Those are two separate results and this document keeps them separate. The macOS figures are operator-machine observations. The Linux figures come from Actions run history, read by the session operator outside the engagement's `networkAccess: false` ceiling (AQ-0012) [EV-0126].

Both currently published releases carry the pre-fix flow scripts that `16b4dc4` repaired [EV-0144]. The numbers stay narrower than they look. They cover 2 of the 6 in-tree plugins [EV-0010], [EV-0058]. They assert structure far more than behaviour [EV-0107]. No check is required for merge: `main` carries no branch protection and no rulesets [EV-0131].

## Defects the flow suite caught before 16b4dc4

Before commit `16b4dc4`, four flow test files failed under Apple's bash 3.2.57 [EV-0106, I]. The cause splits, and the split matters more than the count.

`Inferred:` two of the four files exercised defects in shipped runtime scripts. The other two failed for test-harness portability reasons, with no shipped-code change [EV-0106, I].

| Failing file | Cause | Shipped code affected | Evidence |
|---|---|---|---|
| `flow-quality-ledger.test.sh` | Runtime defect in a shipped script | yes | [EV-0103], [EV-0104, R] |
| `verify-task-completion.test.sh` | Runtime defect in a shipped hook script | yes | [EV-0101], [EV-0102, R] |
| `ask-issue-create.test.sh` | Harness PyYAML resolution, file unmodified | no | [EV-0099], [EV-0100] |
| `flow-eval-harness.test.sh` | `Reported:` harness portability, GNU-only invocations | no | [EV-0105, R], [EV-0106, I] |

The two runtime fixes are real. `record-quality-run.sh` now widens its command-end token by suffix removal rather than by quoted replacement [EV-0101]. `flow-quality-ledger.sh` now resolves candidate paths physically before comparing them against the repository root [EV-0103]. The author's account of both pre-fix behaviours is `R`, taken from in-file comments and the pull request [EV-0102, R], [EV-0104, R].

Both defects reached a published release. v4.9.0 was published at 07:18Z and v4.10.0 at 07:48Z on 2026-09-10, while `16b4dc4` merged at 10:39Z [EV-0144]. `git diff v4.10.0..HEAD` over the two scripts returns +39 −1, so both published tags carry the pre-fix trees [EV-0144].

This is shipped runtime code, not test code. One is a hook that records quality runs, the other a ledger script that resolves a path against the repository top [EV-0101], [EV-0103]. An operator installing v4.10.0 today gets both pre-fix scripts [EV-0144]. What that operator experiences on macOS is not established — only that the fixed code is absent from the tag [EV-0144].

## Quality strategy

| Dimension | Strategy | Owner | Evidence |
|---|---|---|---|
| Software | Shell suites asserting structural invariants over Markdown and JSON, plus script behaviour | Daniel Bentes | [EV-0098], [EV-0107] |
| Product | **None.** No usability testing, no user research, no install telemetry (AQ-0004) | — | [EV-0044] |
| Data | N/A — the project holds no data | — | [EV-0044] |
| AI / model | An eval harness exists in flow. It is not a gate and did not run this refresh | Daniel Bentes | [EV-0095], CHK-50 |
| Hardware | N/A — the project ships no hardware | — | [EV-0044] |
| Security | CodeQL over `actions` and `python`. shellcheck over dossier's shell only. Hook-based blocking during authoring | Daniel Bentes | [EV-0134], [EV-0165], [EV-0038] |
| Accessibility | N/A — there is no user interface. Output is Markdown rendered by the operator's client | — | [EV-0044] |
| Operational | N/A — there is no runtime to operate | — | [EV-0044] |

Four dimensions are genuine `N/A` for a project with no runtime, no data, and no interface. Product signal remains a real gap.

`Reported:` the retained eval summary records 105 runs across 2 models, 7 arms and 4 cases. It cost $184.65 and returned a `keep-enforce` verdict for both models [EV-0096, R]. That summary was produced by the harness itself on 2026-09-09 and was not re-run here. `flow-eval-run.sh` was not executed, because it needs paid multi-model API access and network (CHK-50).

## Test levels and ownership

| Level | What it covers | Owner | Runs where | Evidence |
|---|---|---|---|---|
| Structural | Frontmatter shape, required headings, cross-reference resolution, contract-pointer anchors | Daniel Bentes | `tests/run.sh` in flow and dossier | [EV-0098], [EV-0107] |
| Script unit | `bash -n`, executable bit, `set -u`, usage header, bash 3.2 portability, exit code 2 | Daniel Bentes | same | [EV-0107] |
| Script behaviour | Real fixtures in temporary directories. Cascade precedence, gate refusal, patch validation | Daniel Bentes | same | [EV-0107] |
| Invariant | Cross-artifact properties over verification agents and their skill loads | Daniel Bentes | dossier suite | [EV-0107] |
| Manifest consistency | Every marketplace entry's version against its source's own `plugin.json` | Daniel Bentes | `marketplace-manifest.yml` | [EV-0080], [EV-0081] |
| Static analysis | CodeQL over `actions` and `python`, both `build-mode: none` | GitHub | `codeql.yml` | [EV-0134] |
| Python unit | The upstream `agent-capability-standard` pytest suite | upstream | nowhere in this repository's CI | [EV-0011], AQ-0001 |
| Correctness eval | 4 flow eval cases with hidden tests and trap variants | Daniel Bentes | run by hand, not in CI | [EV-0095] |
| Integration | **None.** No test installs a plugin, invokes a command, or fires a hook | — | — | [EV-0098], [EV-0107] |
| End-to-end | **None.** The dossier refresh workflow has never executed here (AQ-0002) | — | — | [EV-0045], [EV-0123] |

## Test inventory and coverage gaps

No coverage measurement exists for either suite. Neither run reports lines, branches, functions, or scenarios [EV-0098], [EV-0107]. Assertion counts are counts of executed assertions and nothing more.

| Area | Assertions | Coverage measure | Gap | Consequence | Evidence |
|---|---|---|---|---|---|
| flow | 2336 | none | No behavioural coverage. No Windows environment | A skill can pass every assertion and still be unhelpful | [EV-0098], AQ-0008 |
| dossier | 1951 | none | Its headline capability has never run (AQ-0002) | The plugin's central claim stays unverified | [EV-0107], [EV-0045] |
| gh-workflow | none | none | total | 7 skills, 14 commands, 4 agents unverified | [EV-0010], [EV-0162] |
| decipon | none | none | total | 2 skills, 7 commands, 5 agents unverified | [EV-0010], [EV-0162] |
| context-ledger | none | none | total | 5 skills, 8 commands, 5 agents unverified | [EV-0010], [EV-0162] |
| ai-first-org-design-kit | none | none | total | 15 skills, no commands, no agents. Description off by one | [EV-0010], [EV-0162], [EV-0027] |
| agent-capability-standard | upstream pytest | unknown | Not run in this repository's CI | The only dependency-bearing plugin is untested here | [EV-0011], AQ-0001 |
| `marketplace.json` | version check only | none | No parse or resolution test | Version drift is caught. `Unknown:` whether a malformed manifest is | [EV-0080] |
| `README.md` | none | none | total | 4 verified-stale facts, observed 2026-07-26 | [EV-0022]–[EV-0025] |

Four in-tree plugins ship no test suite at all [EV-0010], [EV-0058]. That row was observed on 2026-07-26 and has not been re-checked at HEAD.

| Critical path | Tested | Test | Evidence |
|---|---|---|---|
| Manifest parses and every source resolves | `Unknown:` no test asserts it (AQ-0020) | — | [EV-0080] |
| Plugin version agrees with its manifest entry | yes | `scripts/check-plugin-versions.sh` in CI | [EV-0080], [EV-0081], [EV-0127] |
| Every external source carries a `sha` | yes | same | [EV-0080] |
| A pinned external `sha` is current | **no** | The check reports staleness rather than failing | [EV-0080] |
| A hook script is executable and portable | yes, for flow and dossier | `bin-scripts.test.sh`, `hooks.test.sh` | [EV-0098], [EV-0107] |
| A hook blocks what it claims to block | **no** — no runtime test exists | — | [EV-0038] |
| A command's declared skills all resolve on disk | yes, for flow and dossier | `command-frontmatter.test.sh` | [EV-0107] |
| The dossier gate cannot self-certify | yes | `bin-scripts.test.sh` anti-theater assertion | [EV-0107] |
| A plugin installs and loads from a clean profile | **no** | — | AQ-0003 |

## Quality gates

| Stage | Gate | Blocking | Bypassable | Bypass requires | Evidence |
|---|---|---|---|---|---|
| Local development | flow `PreToolUse` hooks — destructive commands, force pushes, secrets | yes, inside a session where flow is active | yes | Not using flow, or not using Claude Code | [EV-0038] |
| Pull request / CI | `flow-tests`, `dossier-tests`, `codeql`, `marketplace-manifest` | **no — advisory only** | trivially | Nothing. No check is required | [EV-0131], [EV-0123] |
| Release | None. A tag and a release can be cut regardless of CI state | no | — | Nothing | [EV-0032] |
| Production | N/A — `main` is production, and the push is the deploy | no | — | Nothing | [EV-0131] |

This table is the core finding. The project has good tests and no gate anywhere that stops a change. 4287 assertions across the two suites are information, not enforcement [EV-0098], [EV-0107].

`main` carried no branch protection, no rulesets and 0 Actions secrets when read live on 2026-09-10 [EV-0131]. That read sits 45 days past the July rows' stated freshness bound and found no change [EV-0016], [EV-0017], [EV-0131].

## Static and supply-chain checks

| Check | Tool | Scope | Blocking | Last result | Evidence |
|---|---|---|---|---|---|
| Static analysis | CodeQL | `actions` and `python` | no | 3 analyses, `results_count` 0 each | [EV-0134], [EV-0140] |
| Manifest version drift | `check-plugin-versions.sh` | All 8 marketplace entries | no | 8 checked, 0 failed, 0 unverifiable | [EV-0127] |
| Formatting | none | — | — | — | [EV-0123] |
| Shell linting | shellcheck v0.11.0 | dossier `bin/`, hooks and tests only | no | Runs in `dossier-tests.yml` | [EV-0165] |
| Type checking | N/A for Markdown and shell | — | — | — | [EV-0041] |
| Dependency scanning | **none.** No `dependabot.yml` | — | — | — | [EV-0036] |
| Vulnerability scanning | **none executed** | — | — | No artifact exists | [EV-0121] |
| Action pinning | GitHub | 2 third-party action sources | — | Pinned by major tag, not by commit sha | [EV-0042] |
| Configuration validation | `dossier-validate-config.sh` | This repository's dossier settings | no | pass, 0 findings | [EV-0086] |

Three notes belong beside that table.

CodeQL produced 3 analyses across the range, each with `results_count` 0, and the repository holds 0 open alerts [EV-0140]. Run status and finding count are separate facts, and both are now observed [EV-0140].

CodeQL's matrix is `actions` and `python` [EV-0134]. All 53 tracked `.py` files sit under `plugins/`, so removing the submodule checkout did not remove Python from its reach [EV-0134], [EV-0063]. Shell is outside every configured language [EV-0140].

Shell linting exists and is narrower than the repository. `dossier-tests.yml` installs shellcheck v0.11.0 by pinned release URL and runs it over dossier's `bin/`, hook and test scripts [EV-0165]. dossier's 20 `bin/` and 5 hook scripts are linted. flow's 20 `bin/` and 14 hook scripts are not [EV-0165], [EV-0162].

The absence of a vulnerability scan is not a clean bill of health. `runSecurityScan` resolves false, so no scanner ran [EV-0077], [EV-0121].

### What the manifest check does and does not catch

`scripts/check-plugin-versions.sh` compares each marketplace entry's advertised version against its source's own `plugin.json` [EV-0080]. It reads external sources at their pinned sha and fails when an entry disagrees or an external source carries no `sha` [EV-0080].

Its own header states the limit. It cannot catch a pin that is stale but self-consistent, and it reports staleness rather than failing on it [EV-0080].

At `af6e632` it passes: 8 plugins checked, 0 failed, 0 unverifiable, exit 0 [EV-0127]. Both external entries resolved and matched their pinned sources [EV-0127]. That run was executed by the session operator outside the agent action ceiling (AQ-0012) [EV-0127]. The agent's own attempt is recorded as not executed, because `networkAccess` is false [EV-0125], CHK-65.

## Test data and environments

| Concern | Approach | Contains production data | Evidence |
|---|---|---|---|
| Test data | Fixtures created in `mktemp -d` directories and removed after | no — there is no production data | [EV-0107] |
| macOS environment | macOS 25.6 arm64, `/bin/bash` 3.2.57, operator machine | no | [EV-0098], [EV-0107] |
| Linux environment | GitHub-hosted `ubuntu-latest`, both test workflows | no | [EV-0126] |
| Windows environment | **None.** Both test workflows declare `runs-on: ubuntu-latest` | — | [EV-0126], AQ-0008 |
| Python dependency | `run.sh` puts the per-user site-packages tree on `PYTHONPATH` | no | [EV-0099], [EV-0100] |
| Fixtures and seeds | Inline heredocs and generated JSON. Credential patterns appear in scanner fixtures | no | [EV-0037] |

## Flaky tests, quarantines, and manual gates

| Item | Kind | Where | Since | Owner | Impact | Evidence |
|---|---|---|---|---|---|---|
| Intermittent failure in `flow-goal-stop.test.sh` | flaky | flow | 2026-07-26 | Daniel Bentes | Failed 4 assertions once, then passed 10 runs. Not reproduced, not re-checked at HEAD | [EV-0055] |
| Temp directories leaked every run | harness defect | flow | since the harness was written | Daniel Bentes | flow leaked ~254 directories per run. Fixed in dossier, not re-checked in flow | [EV-0056] |
| No quarantined or skipped test | — | — | — | — | Both suites report 0 failures and no deliberate skips | [EV-0098], [EV-0107] |
| Conditional degradation on missing PyYAML | graceful skip | `workflow-template.test.sh` | since the test was written | Daniel Bentes | The YAML parse check records a pass with a reason where PyYAML is absent | [EV-0107] |
| Stale `expectedPluginVersion` pin | manual gate | `.claude/settings.dossier.json` | unrecorded | Daniel Bentes | Pins 1.0.0 while dossier ships 1.2.0. The config validator still passes | [EV-0085], [EV-0086] |
| External pin currency | manual gate | `marketplace.json` | always | Daniel Bentes | The CI check confirms the pin matches, never that it is current (AQ-0006) | [EV-0080], [EV-0127] |
| README accuracy | manual gate | `README.md` | always | Daniel Bentes | **Already failed** — 4 stale facts on 2026-07-26 | [EV-0022]–[EV-0025] |

Two of these gates have already failed at least once. The stale configuration pin is the sharper case, because a validator reports `pass` over it [EV-0085], [EV-0086].

## Delivery pipeline

| Aspect | Current practice | Enforced by | Evidence |
|---|---|---|---|
| CI workflows | 5 tracked, path-filtered. Both test workflows declare `permissions: contents: read` | `.github/workflows/` | [EV-0123], [EV-0013] |
| CI result | Green on Linux for every commit this range added to `main` | GitHub Actions | [EV-0126] |
| Branch policy | `feature/issue-{n}-{desc}`, `fix/…`, `docs/…` | `.claude/CLAUDE.md`, unenforced | `.claude/CLAUDE.md` |
| Review policy | Pull requests used by habit — 62 merged against 193 commits to 2026-07-25 | **nothing** | [EV-0131], [EV-0050] |
| Artifact provenance | `Inferred:` none. Distribution is a git read by the client, with no publish step | — | [EV-0043, I] |
| Signing | Branch-authored commits are unsigned. GitHub signs the squash-merge commits it creates. No tag is signed | GitHub's merge path | [EV-0138] |
| Promotion between environments | N/A — one environment | — | [EV-0044] |
| Documentation refresh automation | Not installed. The plugin ships the template, this repository has not adopted it | — | [EV-0084], [EV-0123] |

One workflow interpolates `${{ github.event.release.tag_name }}` inside a `run:` body [EV-0015]. That is the pattern the dossier CI template forbids in its own workflows [EV-0015].

## Release process

| Aspect | Current practice | Evidence |
|---|---|---|
| Cadence | Ad hoc. v4.9.0 and v4.10.0 were both published on 2026-09-10 | [EV-0066] |
| Manifest version | `metadata.version` is 4.10.0, publishing 8 plugin entries | [EV-0057] |
| Approval | None required | [EV-0131] |
| Rollback | `git revert` and push. Installers pick it up on their next client sync | [EV-0051] |
| Hotfix path | Identical to the normal path, because the normal path has no gate to skip | [EV-0131] |

The manifest check does not cover releases. It compares entry versions against their sources, not `metadata.version` against a tag [EV-0080].

## Delivery metrics

| Metric | Value | Window | State | Evidence |
|---|---|---|---|---|
| Change failure rate | **unknown** — no incident record exists to divide by | — | U | [EV-0036] |
| Defect escape rate | **unknown**. 2 open portability issues are the only escape signal | 2026-07-26 | U | [EV-0049] |
| Incident rate | **unknown** — no incident process and no runtime | — | U | [EV-0044] |
| Lead time to production | Effectively zero — a push to `main` is production | live | I — inferred from the absence of any gate | [EV-0131] |
| Deployment frequency | 193 commits over roughly 7 months, each a deployment | 2025-12-19 to 2026-07-25 | V | [EV-0034] |
| Merged pull requests | 62 | to 2026-07-25 | V | [EV-0050] |
| Test assertions executed per run | 4287 across both suites | per run at `af6e632` | V | [EV-0098], [EV-0107] |

Three of the seven metrics are `unknown`, and they are the three that measure whether quality is achieved rather than attempted. Two more rest on counts observed on 2026-07-26 and are not extended to today.

## Commands executed during documentation verification

| Command | Purpose | Environment | Date | Result | Output |
|---|---|---|---|---|---|
| `bash plugins/flow/tests/run.sh` (CHK-51) | Verify flow's suite | macOS 25.6, bash 3.2.57 | 2026-09-10 | pass | `TOTAL pass=2336 fail=0` |
| `bash plugins/dossier/tests/run.sh` (CHK-54) | Verify dossier's suite | macOS 25.6, bash 3.2.57 | 2026-09-10 | pass | `TOTAL pass=1951 fail=0` |
| `python3 -m site --user-site` (CHK-52) | Locate PyYAML on this machine | macOS 25.6 | 2026-09-10 | pass | Resolves only from the user-site tree |
| `git diff --stat 15bcb24..af6e632` (CHK-53) | Establish the tree delta | git | 2026-09-10 | pass | 11 files, no dossier test file |
| `git ls-files '.github/workflows/*'` (CHK-62) | Establish CI definitions | git | 2026-09-10 | pass | 5 workflows |
| `ls .dossier/scan`; `git ls-files` filter (CHK-61) | Look for vulnerability evidence | macOS 25.6 | 2026-09-10 | pass | No directory, 0 tracked matches |
| `dossier-resolve-config.sh` (CHK-64) | Resolve the action ceiling | bash | 2026-09-10 | pass | `networkAccess` false |
| `dossier-validate-config.sh` (CHK-41) | Validate this repository's settings | bash | 2026-09-10 | pass | 0 findings |
| `gh run list --branch main` (CHK-68) | Read Linux CI results | GitHub | 2026-09-10 | pass | Six runs, all `success` |
| `bash scripts/check-plugin-versions.sh` (CHK-69) | Check every manifest entry | macOS 25.6, `gh` authenticated | 2026-09-10 | pass | 8 checked, 0 failed |
| `gh api` protection, rulesets, secrets (CHK-73) | Establish live merge and secret controls | GitHub REST | 2026-09-10 | pass | 404, `[]`, `total_count` 0 |
| `grep` over `codeql.yml`; `git ls-files '*.py'` (CHK-74) | Establish CodeQL scope at HEAD | macOS 25.6, git | 2026-09-10 | pass | Matrix `actions`, `python`; 53 `.py` files |
| `git log --format=%G?`; `git tag -v` (CHK-78) | Establish commit and tag signing | git, GitHub REST | 2026-09-10 | pass | Merges verified, tag unsigned |
| `gh api code-scanning/analyses` and `/alerts` (CHK-80) | Read CodeQL findings | GitHub REST | 2026-09-10 | pass | 3 analyses, 0 results, 0 open alerts |
| `gh release list`; `git diff v4.10.0..HEAD` (CHK-84) | Order the flow fixes against publication | GitHub REST, git | 2026-09-10 | pass | Fixes merged after both releases |
| Per-plugin artifact census (CHK-95) | Count skills, commands, agents, scripts | macOS 25.6, git | 2026-09-10 | pass | 40 plugin `bin/` scripts |
| `grep -rn shellcheck .github/workflows/` (CHK-97) | Find static analysis of shell | macOS 25.6 | 2026-09-10 | pass | Present in `dossier-tests.yml` only |

CHK-68, CHK-69, CHK-73, CHK-78, CHK-80 and CHK-84 were executed by the session operator, not by a dispatched agent. Each needs network access, which the engagement ceiling denies (AQ-0012) [EV-0077].

### Checks carried forward from earlier rounds

Every claim in this document that rests on an earlier round cites one of these. Each carries the date it ran, so a reader can see which findings are two rounds old.

| Command | Purpose | Environment | Date | Result | Output |
|---|---|---|---|---|---|
| `ls plugins/*/tests/run.sh` (CHK-04) | Establish which plugins carry suites | macOS 25.5 | 2026-07-26 | pass | 2 matches |
| `yaml.safe_load` per workflow (CHK-05) | Read triggers, permissions, jobs | python3, pyyaml | 2026-07-26 | pass | 4 workflows parsed |
| `awk` run-block scanner (CHK-06) | Find untrusted interpolation in `run:` bodies | macOS 25.5 | 2026-07-26 | fail | 1 hit in `release-desktop-skills.yml` |
| README grep (CHK-10) | Compare README facts against the tree | macOS 25.5 | 2026-07-26 | fail | 4 stale facts |
| Skill-count comparison (CHK-12) | Compare counts against prose | macOS 25.5 | 2026-07-26 | fail | 15 versus "Fourteen" |
| `git tag --list`, `gh release list` (CHK-15) | Establish release history | git, gh | 2026-07-26 | pass | 57 tags |
| `git rev-list --count HEAD` (CHK-16) | Count commits on the assessed branch | git | 2026-07-26 | pass | 193 commits |
| Community-health path test (CHK-18) | Look for `SECURITY.md` and siblings | macOS 25.5 | 2026-07-26 | fail | 9 of 9 absent |
| `git grep -nE` credential scan (CHK-19) | Look for real credentials in tracked files | git | 2026-07-26 | pass | No match outside fixtures |
| `grep -hoE 'uses:'` (CHK-21) | Inventory third-party actions | macOS 25.5 | 2026-07-26 | pass | 2 distinct sources |
| `gh run list --json workflowName` (CHK-22) | Look for a refresh workflow run | gh | 2026-07-26 | pass | Refresh absent |
| `gh api branches/main/protection` | Establish whether a merge gate exists | gh | 2026-07-26 | pass | HTTP 404 |
| `gh api rulesets` | Same, for rulesets | gh | 2026-07-26 | pass | Empty array |
| `jq` over client install state (CHK-28) | Confirm an installed plugin resolves | macOS 25.5, jq | 2026-07-26 | pass | Marketplace resolved |
| `plugins/flow/tests/run.sh` repeated 10 times (CHK-31) | Test for flakiness | macOS 25.5 | 2026-07-26 | 10 of 11 pass | One run reported `fail=4` |
| `TMPDIR` entry count (CHK-32) | Measure temp-directory leakage | macOS 25.5 | 2026-07-26 | fail | flow +254 per run |
| Submodule residue inspection (CHK-33) | Establish `.gitmodules` state | macOS 25.5, git | 2026-09-10 | pass | No `.gitmodules` tracked |
| `dossier-resolve-config.sh` (CHK-38) | Resolve the action ceiling | bash | 2026-09-10 | pass | `networkAccess` false |
| `git ls-files '.github/workflows/*'` (CHK-40) | Establish CI definitions | git | 2026-09-10 | pass | 5 workflows |
| `git ls-files` artifact census (CHK-46) | Count skills, scripts, eval files | git | 2026-09-10 | pass | 82 tracked eval files |

| Command not executed | Why | What it would have established |
|---|---|---|
| `scripts/check-plugin-versions.sh` by an agent (CHK-65) | `networkAccess` is false | The same result CHK-69 obtained through the operator |
| `gh auth status` (CHK-66) | The probe contacts GitHub | Whether the new `gh_available` probe succeeds here |
| `flow-eval-run.sh` (CHK-50) | Needs paid multi-model API access | Whether the eval verdict holds at HEAD |
| `pytest plugins/agent-capability-standard` (CHK-09) | `runBuild` is false | Whether the dependency-bearing plugin's tests pass (AQ-0001) |
| The dossier refresh workflow, end to end | Needs a scratch repository and a merged pull request | Whether the plugin's headline capability works (AQ-0002) |
| Both suites on Windows | No Windows environment available | The real scope of issues #100 and #130 (AQ-0008) |

## Recommendations

`Recommendation:` require both test workflows and the manifest check as status checks on `main`. Nothing today stops a red change from merging [EV-0131].

`Recommendation:` add a `windows-latest` job to both test workflows, so AQ-0008 stops resting on user reports.

`Recommendation:` update `.claude/settings.dossier.json` to pin 1.2.0, and make the config validator fail on a pin below the installed plugin version [EV-0085], [EV-0086].

`Recommendation:` extend the existing shellcheck step to flow. Flow's hooks run as blocking `PreToolUse` calls on a contributor's machine, and nothing lints them [EV-0165], [EV-0162] (AQ-0019).
