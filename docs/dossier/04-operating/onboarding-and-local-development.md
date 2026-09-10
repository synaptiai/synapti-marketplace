---
dossier-header: internal-v1
title: Onboarding and Local Development
purpose: Gets a new contributor from a clone to a verified change without needing to ask anyone.
audience: Contributor, Maintainer
confidentiality: Internal
owner: Daniel Bentes
status: partially verified
project-version: 691bcdb
last-verified: 2026-09-10
review-trigger: A prerequisite, test command, or repository convention changes
related: [02-architecture/components-and-codebase.md, 03-assurance/testing-quality-and-delivery.md, 04-operating/decisions-technical-debt-and-risks.md]
---
# Onboarding and Local Development
<!-- contract: references/package-contract-04-operating.md#onboarding-and-local-development -->

Every command marked `executed` below was run on 2026-09-10 against `691bcdb`. Most were run in a throwaway clone of this repository, not in the maintainer's working tree. Commands that were not executed say so.

`691bcdb` is on branch `docs/dossier-refresh`, not on `main` [EV-0092]. A contributor cloning `main` gets a different tree. Cloning `main` was executed on 2026-09-10 and is recorded in step 1 below.

One caveat frames the whole document. Unknown: whether the contribution path works for anyone but the maintainer, which has never been exercised (AQ-0007). The routes below come from the repository's structure and its own conventions.

## Onboarding routes

| Role | Route | First meaningful contribution | Time to it |
|---|---|---|---|
| Engineering | Clone, run both suites, read one `SKILL.md` and the test guarding it | A skill or `bin/` script change with a matching assertion | Setup measured at 8 minutes (below) |
| Product | Read `01-project/executive-project-brief.md`, then the root `README.md` | Correcting a stale README fact — two remain live [EV-0027], [EV-0028] | Unknown: unmeasured (AQ-0007) |
| Design | N/A — no user interface exists. Output is Markdown rendered by the operator's own client [EV-0044] | — | — |
| Data / AI | Read `02-architecture/data-and-ai.md` | Writing the first behavioural evaluation for a dossier skill | Unknown: unmeasured (AQ-0007) |
| Operations | Read `02-architecture/infrastructure-and-deployment.md` | Enabling branch protection, which is absent [EV-0016], [EV-0017] | Unknown: unmeasured (AQ-0007) |
| Security | Read `03-assurance/security-privacy-and-compliance.md`, then the 19 hook scripts [EV-0129] | Writing `SECURITY.md`, which does not exist [EV-0036] | Unknown: unmeasured (AQ-0007) |
| Leadership | `01-project/executive-project-brief.md` alone | Deciding AQ-0002, and whether to gate `main` | One read |

## Prerequisites

| Prerequisite | Supported version | How to install or obtain | Required for | Evidence |
|---|---|---|---|---|
| `git` | any recent | Preinstalled on macOS and Linux | Everything | [EV-0034] |
| `bash` | 3.2 or later | Preinstalled | Both test suites and every script | [EV-0098], [EV-0107] |
| `jq` | any recent | `brew install jq`, `apt install jq` | Helper scripts and the version check | [EV-0080] |
| `python3` with `pyyaml` | 3.x | `pip install --user pyyaml` | Optional. Enables the YAML-parse leg of dossier's workflow test | [EV-0099], [EV-0100] |
| `gh` CLI, authenticated | any recent | `brew install gh`, then `gh auth login` | `scripts/check-plugin-versions.sh` and flow's GitHub commands | [EV-0080] |
| Claude Code | any recent | Anthropic | Using the plugins as an operator | [EV-0051] |
| Windows | **untested** | — | Issues #100 and #130 report Git Bash failures. No CI leg exists (AQ-0008) | [EV-0049], [EV-0126] |

Apple's system `bash` 3.2.57 is enough. Both suites pass on it [EV-0098], [EV-0107]. Do not install a newer `bash` to run them.

| Access needed | Requested from | Approval required | Typical lead time |
|---|---|---|---|
| Read access | Nobody — the repository is public | no | none |
| Write access | Daniel Bentes | yes | Unknown: never granted to anyone else (AQ-0007) |
| Merge access | Daniel Bentes | yes | Unknown: never granted (AQ-0007) |
| Repository settings | Daniel Bentes | yes | Unknown: never granted (AQ-0007) |

## Setup

Setup is a clone, two test runs, and one version check. There is no build step, no dependency install, and no environment file [EV-0044].

| Step | Command | Verifies success by | Verification | Environment | Date |
|---|---|---|---|---|---|
| 1 — clone | `git clone https://github.com/synaptiai/synapti-marketplace.git` | The tree contains `plugins/` and `.claude-plugin/marketplace.json` | executed against `main`. No `.gitmodules` and no `agent-capability-standard/` directory appeared. Ledger row requested | macOS 25.6 | 2026-09-10 |
| 2 — check the manifest parses | `jq '.plugins \| length' .claude-plugin/marketplace.json` | Prints `8` | executed, printed `8` [EV-0057] | macOS 25.6 | 2026-09-10 |
| 3 — run the flow suite | `plugins/flow/tests/run.sh` | `TOTAL pass=… fail=0` | executed: `TOTAL pass=2336 fail=0`, exit 0 [EV-0098] | macOS 25.6, `/bin/bash` 3.2.57 | 2026-09-10 |
| 4 — run the dossier suite | `plugins/dossier/tests/run.sh` | `TOTAL pass=… fail=0` | executed: `TOTAL pass=1951 fail=0`, exit 0 [EV-0107] | macOS 25.6, `/bin/bash` 3.2.57 | 2026-09-10 |
| 5 — check advertised versions | `bash scripts/check-plugin-versions.sh` | `8 plugin(s) checked, 0 failed, 0 unverifiable` | executed, exit 0 [EV-0127] | macOS 25.6, authenticated `gh` | 2026-09-10 |

**No submodule step exists.** Do not run `git submodule update --init`. No `.gitmodules` file is tracked [EV-0059], and the command does nothing here. The `agent-capability-standard` plugin is a `github` marketplace source pinned to sha `9e2f65b` [EV-0058]. A populated `plugins/agent-capability-standard/` directory on a developer machine is residue from the removed submodule. That path is gitignored and holds no repository content [EV-0060].

Step 5 needs an authenticated `gh`. Six entries resolve from local paths, and two external entries are read at their pinned sha [EV-0127]. Without network access the script cannot check those two.

**Measured setup time.** Steps 3 and 4 took 2 minutes 20 seconds and 4 minutes 52 seconds. Step 5 took 2 seconds. Measured on macOS 25.6 (Darwin arm64) on 2026-09-10, in a clone with no prior state. Total is about 8 minutes including the clone.

## Configuration and secrets

| Setting | Purpose | Required | How to obtain a development value | Safe default |
|---|---|---|---|---|
| **none** | No secret is required to clone, test, or release this repository | no | — | — |
| `ANTHROPIC_API_KEY` | Only in a *consuming* repository running dossier's refresh workflow. Not configured here | no | Anthropic console | none — the workflow fails loudly |
| `.claude/settings.dossier.json` | Configures a dossier run in this repository | no | `/dossier:init` writes it | Plugin defaults, with `networkAccess` false |

No production credential is used anywhere in local development. No step above takes one as input.

`.claude/settings.dossier.json` pins `dossier.ci.expectedPluginVersion` to `1.0.0`, while the dossier plugin is at `1.2.0` [EV-0085], [EV-0065]. `bin/dossier-validate-config.sh` reports the file valid with zero findings and does not flag the stale pin [EV-0086]. A newcomer editing dossier should expect that mismatch and not treat it as breakage.

## Local dependencies and data

| Dependency | Run locally how | Alternative | Seed or synthetic data | Evidence |
|---|---|---|---|---|
| **none** | No database, service, queue, or emulator exists | — | Test fixtures are created in `mktemp -d` directories and removed afterwards | [EV-0044] |

No fixture derives from a production export. There is no production system to export from [EV-0044].

## Daily operations

| Task | Command | Expected result | Verification | Date |
|---|---|---|---|---|
| Build | N/A — no build step exists [EV-0044] | — | — | — |
| Run | N/A — nothing runs. Install a plugin in Claude Code to exercise it [EV-0044] | — | — | — |
| Test | `plugins/flow/tests/run.sh` and `plugins/dossier/tests/run.sh` | `TOTAL pass=<n> fail=0` | executed: 2336 and 1951, zero failures [EV-0098], [EV-0107] | 2026-09-10 |
| Version check | `bash scripts/check-plugin-versions.sh` | `8 plugin(s) checked, 0 failed` | executed, exit 0 [EV-0127] | 2026-09-10 |
| Lint | No local lint entry point exists. CI runs `shellcheck -S warning` over dossier scripts | — | Observed in `.github/workflows/dossier-tests.yml` at 691bcdb. Ledger row requested | 2026-09-10 |
| Debug | Run a `bin/` script directly. Each emits `KEY=value` lines and exits 0, 1, or 2 | Readable diagnostic output | executed for `dossier-validate-config.sh` [EV-0086] | 2026-09-10 |
| Reset to clean state | `git checkout -- .` and `git clean -fd` | Working tree matches HEAD | Not executed — the working tree holds this package | — |
| Clean up | Test fixtures self-remove. `dist/desktop` is untracked and safe to delete | — | — | — |

The `shellcheck` step names dossier's `bin/`, `hooks/scripts/` and `tests/` directories. Observed in `.github/workflows/dossier-tests.yml` on 2026-09-10 at 691bcdb, with no matching step in `flow-tests.yml`. Ledger row requested for both observations.

## Development workflow

| Stage | Practice | Tooling | Evidence |
|---|---|---|---|
| Branching | `feature/issue-{n}-{desc}`, `fix/issue-{n}-{desc}`, `docs/issue-{n}-{desc}` | Convention in `.claude/CLAUDE.md`. **Unenforced** | `.claude/CLAUDE.md` |
| Commit conventions | `<type>(<scope>): <subject>` with semantic prefixes | Convention. Unenforced | `.claude/CLAUDE.md` |
| Review | Pull requests are used by habit but are **not required** [EV-0016], [EV-0017] | GitHub | [EV-0016] |
| CI | Five workflows: codeql, dossier-tests, flow-tests, marketplace-manifest, release-desktop-skills [EV-0123]. All advisory | GitHub Actions | [EV-0123], [EV-0016] |
| CI platform | `ubuntu-latest` only. Every run across this refresh's range succeeded [EV-0126] | GitHub Actions | [EV-0126] |
| Release | Bump `plugin.json` and the matching `marketplace.json` entry, tag, publish | `scripts/check-plugin-versions.sh` guards the version pair [EV-0080], [EV-0081] | [EV-0064], [EV-0066] |
| Feature flags | None at runtime, because there is no runtime. Install-time defaults only | Plugin settings | [EV-0044] |

Version drift between a plugin and its manifest entry is checked. `scripts/check-plugin-versions.sh` compares each entry's advertised version against its source's own `plugin.json`, and requires a `sha` on every external source [EV-0080]. `marketplace-manifest.yml` runs it on pull requests and pushes touching those files, weekly, and on demand [EV-0081]. It passes at HEAD [EV-0127].

What it does not check is prose. README text stating a count or a version is unguarded, which is the whole point of the starter task below.

EV-0126's Actions history was read by the session operator, not by the documentation agent, whose action ceiling sets `networkAccess` false [EV-0126]. The version check behind EV-0127 was operator-observed for that row and re-executed by this document's drafter on 2026-09-10. Both provenance questions belong to AQ-0012.

## Reading order

| Order | Document or code path | Why it comes here | Time |
|---|---|---|---|
| 1 | `.claude-plugin/marketplace.json` | Eight entries in one file — the whole product in one read [EV-0057] | 2 minutes |
| 2 | `.claude/CLAUDE.md` | The repository's conventions, which no tool enforces | 10 minutes |
| 3 | `plugins/flow/skills/evidence-based-development/SKILL.md` | The canonical skill shape every other skill follows | 10 minutes |
| 4 | `plugins/dossier/tests/bin-scripts.test.sh` | Shows what this project considers a test worth writing | 15 minutes |
| 5 | `plugins/flow/hooks/hooks.json` and `hooks/scripts/block-destructive.sh` | The highest-consequence code here. It runs on other people's machines | 15 minutes |
| 6 | `scripts/check-plugin-versions.sh` | The one check that reads the manifest the way an installer does [EV-0080] | 10 minutes |
| 7 | `docs/dossier/01-project/executive-project-brief.md` | This package's summary of what is and is not true here | 10 minutes |

All seven paths above were confirmed tracked at `691bcdb` with one `git ls-files` call on 2026-09-10.

## First day, week, and month

| Horizon | Outcome | How it is demonstrated |
|---|---|---|
| First day | Both suites run green locally, and the version check passes | `pass=2336 fail=0`, `pass=1951 fail=0`, and `0 failed` on your own machine |
| First week | One merged change with a test that fails without it | A pull request adding an assertion and the change it guards |
| First month | You can add a plugin end to end, and you know which steps are checked | A plugin whose manifest entry passes the version check, and whose README row is correct |

The first-month outcome is narrower than it used to be. The manifest-versus-`plugin.json` step is now checked [EV-0080], [EV-0127]. The README row is still not.

## Starter task

The diagnostic steps below were executed on 2026-09-10 against `691bcdb`. The fixes in step 5 were not made, so the total time is unmeasured.

| Step | Action | Expected result |
|---|---|---|
| 1 | `bash scripts/check-plugin-versions.sh` | `8 plugin(s) checked, 0 failed`. executed, exit 0 [EV-0127] |
| 2 | Compare `plugins/flow/README.md`'s skill count against `git ls-files 'plugins/flow/skills/*/SKILL.md' \| wc -l` | README says 33, the tree has 32. executed, both figures reproduced [EV-0028] |
| 3 | Compare the `ai-first-org-design-kit` description against its skill count | Description says "Fourteen", the tree has 15. executed, both reproduced [EV-0027] |
| 4 | Compare each README version cell against `jq -r '.plugins[] \| "\(.name)=\(.version)"'` | executed. One cell disagrees with the manifest. Result recorded in this refresh's report, ledger row requested |
| 5 | Fix the three prose facts, and consider what would have caught them | One CI step comparing README prose to the manifest. It does not exist [EV-0080] |

Step 2's counting rule matters. `plugins/flow/skills/learned/` holds only `.gitkeep`, so directory counting yields 33 and file counting yields 32 [EV-0029]. The tree is right and the README is wrong.

Step 4 is the interesting one. The machine-readable pair already agrees [EV-0064], and the check in step 1 proves it [EV-0127]. Prose drifted anyway, because nothing reads it.

## Troubleshooting

| Symptom | Likely cause | Resolution | Verified |
|---|---|---|---|
| `git submodule update --init` does nothing | Correct. No submodule exists [EV-0059] | Skip the step. Any older instruction saying otherwise is stale | yes — executed in a clean clone, no output, exit 0 |
| `plugins/agent-capability-standard/` is populated but `git status` ignores it | Residue from the removed submodule [EV-0060] | Leave it or delete it. It is not repository content | yes [EV-0060] |
| A script fails with `declare: -A: invalid option` | macOS `bash` 3.2 meeting a `bash` 4 construct | Rewrite without associative arrays. Both suites assert against this | yes [EV-0098], [EV-0107] |
| A hook does not fire | The file lacks the executable bit | `chmod +x`. Both suites check this | yes [EV-0107] |
| The YAML-parse leg of the workflow test is skipped | `pyyaml` is missing from the interpreter the suite uses | Install it for the user site directory. The suite adds that directory to `PYTHONPATH` | yes [EV-0099], [EV-0100] |
| `check-plugin-versions.sh` reports an entry unverifiable | `gh` is unauthenticated, or network access is unavailable | Run `gh auth login`. Six local entries still resolve without it | yes [EV-0127] |
| `dossier-package-check.sh` reports many findings on a fresh scaffold | The scaffold writes 23 files with placeholder headers [EV-0047] | Draft the documents | Inferred: the findings follow from the placeholders, and were not re-counted today |
| Anything on Windows | Issues #100 and #130 report Git Bash failures [EV-0049] | **No resolution exists.** Use macOS or Linux | Unknown: reported, never reproduced or measured (AQ-0008) |

Windows and Git Bash remain unmeasured. CI runs `ubuntu-latest` only [EV-0126], and no `windows-latest` job exists (AQ-0008).

## Proposing changes

| Change kind | Where to propose it | Who decides | What the proposal must contain |
|---|---|---|---|
| Product | A GitHub issue | Daniel Bentes | The problem observed, not the feature wanted |
| Architecture | A GitHub issue, then a pull request | Daniel Bentes | The tradeoff and the rejected alternative |
| Security | **No private channel exists.** A public issue is the only path [EV-0036] | Daniel Bentes | — |
| Documentation | A pull request | Daniel Bentes | The evidence for the corrected fact |

No `CONTRIBUTING.md`, CODEOWNERS, issue template, or pull-request template exists [EV-0036].

Inferred: the table above describes the maintainer's own practice rather than a stated process. The chain is that no contribution document exists to state one [EV-0036].

## Definition of done

| Work type | Done means |
|---|---|
| Engineering | The change is made. A test that fails without it exists. Both suites pass |
| Engineering | `bash scripts/check-plugin-versions.sh` passes if a version or manifest entry changed [EV-0080] |
| Engineering | Any prose stating a count or version the change alters is updated in the same commit |
| Product | The decision is recorded in `.decisions/`, the only durable mechanism present [EV-0046] |

The third engineering row is the one this repository keeps missing. Two README facts are stale right now [EV-0027], [EV-0028].

## Getting help

| Need | Contact | Channel | Hours |
|---|---|---|---|
| Anything | Daniel Bentes | GitHub issues, public | None stated |
| Security disclosure | unassigned — no private contact exists [EV-0036] | — | — |
| Escalation | unassigned — no second person exists | — | — |

Three rows, one person, no private channel, no stated hours. That is why the bus-factor and disclosure-channel findings sit in the risk register rather than only here.

## Recommendations

Recommendation: add a CI step comparing README prose counts and versions against the manifest. `scripts/check-plugin-versions.sh` covers the machine-readable pair, not the prose [EV-0080].

Recommendation: extend the `shellcheck` step to flow's scripts, or state in CI why it covers dossier only.

Recommendation: add a `windows-latest` job to both test workflows, so AQ-0008 becomes measured rather than reported.
