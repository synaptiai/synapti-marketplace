---
dossier-header: internal-v1
title: Onboarding and Local Development
purpose: Gets a new contributor from a clone to a verified change without needing to ask anyone.
audience: Contributor, Maintainer
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: d0fa737
last-verified: 2026-07-26
review-trigger: A prerequisite, test command, or repository convention changes
related: [02-architecture/components-and-codebase.md, 03-assurance/testing-quality-and-delivery.md, 04-operating/decisions-technical-debt-and-risks.md]
---
# Onboarding and Local Development
<!-- contract: references/package-contract-04-operating.md#onboarding-and-local-development -->

Every command in this document was executed on 2026-07-26 against `d0fa737` on macOS 25.5, and its actual output is recorded. Commands that were not executed are marked as such rather than presented as working.

One caveat frames the whole document: **no one but the maintainer has ever onboarded to this repository.** All 351 commits across all refs carry a single author identity [EV-0035], and no external contribution has been merged (AQ-0007). The routes below are derived from the repository's structure and its own conventions; they have never been walked by a stranger.

## Onboarding routes

| Role | Route | First meaningful contribution | Time to it |
|---|---|---|---|
| Engineering | Clone → run both test suites → read one `SKILL.md` and the test that guards it → change a skill and add its assertion | A skill or `bin/` script change with a matching test | under an hour, given the prerequisites |
| Product | Read `01-project/executive-project-brief.md`, then this package's `README.md` findings | Fixing a stale README fact — four are live today | under an hour |
| Design | N/A — there is no user interface. Output is Markdown rendered by the operator's own client | — | — |
| Data / AI | Read `02-architecture/data-and-ai.md` — particularly the AI risk controls and the absent evaluation | Writing the first behavioural evaluation for any skill; none exists | days |
| Operations | Read `02-architecture/infrastructure-and-deployment.md` | Enabling branch protection, or adding the missing manifest check | under an hour |
| Security | Read `03-assurance/security-privacy-and-compliance.md`, then the 16 hook scripts | Adding `shellcheck` to CI, or writing `SECURITY.md` | under an hour |
| Leadership | `01-project/executive-project-brief.md` alone | Deciding CT-0001 (the licence) and AQ-0002 (whether dossier may be described as working) | one read |

## Prerequisites

| Prerequisite | Supported version | How to install or obtain | Required for | Evidence |
|---|---|---|---|---|
| `git` | any recent | preinstalled on macOS and Linux | everything | [EV-0034] |
| `bash` | 3.2 or later | preinstalled | running the test suites and every script | [EV-0008], [EV-0009] |
| `jq` | any recent | `brew install jq`, `apt install jq` | flow and dossier helper scripts | [EV-0007] |
| `python3` with `pyyaml` | 3.x | `pip install pyyaml` | Optional. Enables the YAML-parse leg of dossier's workflow test; without it the test records a pass with a stated skip and continues | [EV-0009] |
| `gh` CLI, authenticated | any recent | `brew install gh` then `gh auth login` | flow's GitHub commands; dossier's setup preflight; reproducing the live-state checks in this package | [EV-0012] |
| Claude Code | any recent | Anthropic | Using the plugins as an operator, rather than developing them | [EV-0051] |
| Windows | **unsupported** | — | Two open issues report failures; no CI leg exists | [EV-0049] |

| Access needed | Requested from | Approval required | Typical lead time |
|---|---|---|---|
| Read access | nobody — the repository is public | no | none |
| Write access | Daniel Bentes | yes | unknown — never granted to anyone else [EV-0035] |
| Merge access | Daniel Bentes | yes | unknown |
| Repository settings | Daniel Bentes | yes | unknown |

## Setup

| Step | Command | Verifies success by | Verification | Environment | Date |
|---|---|---|---|---|---|
| 1 — clone with submodules | `git clone --recurse-submodules https://github.com/synaptiai/synapti-marketplace.git` | `plugins/agent-capability-standard/` is populated | Not executed here — this assessment ran in an existing clone. The Claude Code client's own clone does populate the submodule [EV-0053] | — | 2026-07-26 |
| 2 — confirm the manifest parses | `jq '.plugins \| length' .claude-plugin/marketplace.json` | prints `8` | executed, printed `8` | macOS 25.5 | 2026-07-26 |
| 3 — run the flow suite | `plugins/flow/tests/run.sh` | `TOTAL pass=… fail=0` | executed: `TOTAL pass=1022 fail=0` | macOS 25.5 | 2026-07-26 |
| 4 — run the dossier suite | `plugins/dossier/tests/run.sh` | `TOTAL pass=… fail=0` | executed: `TOTAL pass=1034 fail=0` | macOS 25.5 | 2026-07-26 |

There is no build step, no dependency install, and no environment file. Steps 3 and 4 are the whole setup [EV-0044].

## Configuration and secrets

| Setting | Purpose | Required | How to obtain a development value | Safe default |
|---|---|---|---|---|
| **none** | No secret or configuration value is required to clone, test, or release this repository | no | — | — |
| `ANTHROPIC_API_KEY` | Only in a *consuming* repository that scaffolds dossier's post-merge workflow. **Not configured here** | no | Anthropic console | none — the workflow fails loudly rather than silently skipping |
| `.claude/settings.dossier.json` | Configures a dossier run in a consuming project. This repository now has one, written during this assessment | no | `/dossier:init` writes it | Plugin defaults; every `allowedActions` capability is `false` except `readSource` |

No secret exists in this repository and none is needed [EV-0037].

## Local dependencies and data

| Dependency | Run locally how | Alternative | Seed or synthetic data | Evidence |
|---|---|---|---|---|
| **none** | There is no database, service, queue, or emulator to run | — | Test fixtures are created in `mktemp -d` directories at test time and removed after | [EV-0044], [EV-0009] |

## Daily operations

| Task | Command | Expected result | Verification | Date |
|---|---|---|---|---|
| Build | N/A — no build step exists | — | — | — |
| Run | N/A — nothing runs. To exercise a plugin, install it in Claude Code | — | — | — |
| Test | `plugins/flow/tests/run.sh` and `plugins/dossier/tests/run.sh` | `TOTAL pass=<n> fail=0` | executed: 1022 and 1034, 0 failures | 2026-07-26 |
| Lint / type-check | **none exists.** No `shellcheck`, no formatter, no type checker | — | — | — |
| Debug | Run the individual `bin/` script directly; every one emits `KEY=value` lines and exits 0/1/2 | Readable diagnostic output | executed for `dossier-validate-config.sh`, `dossier-scaffold.sh`, `dossier-package-check.sh` | 2026-07-26 |
| Reset to clean state | `git checkout -- .` and `git clean -fd` | Working tree matches HEAD | not executed — the working tree holds this in-progress package | — |
| Clean up | Test fixtures self-remove; `dist/desktop` is untracked and safe to delete | — | — | — |

The absent lint row is a real gap rather than a stylistic one: 42 shell scripts execute on operator machines and nothing statically analyses them [EV-0007], [EV-0012].

## Development workflow

| Stage | Practice | Tooling | Evidence |
|---|---|---|---|
| Branching | `feature/issue-{n}-{desc}`, `fix/issue-{n}-{desc}`, `docs/issue-{n}-{desc}` | convention in `.claude/CLAUDE.md`; **unenforced** | `.claude/CLAUDE.md` |
| Commit conventions | `<type>(<scope>): <subject>` with semantic prefixes. **No Claude attribution lines** | convention; unenforced | `.claude/CLAUDE.md` |
| Review | Pull requests used by habit — 62 merged against 194 commits — but **not required** | GitHub | [EV-0016], [EV-0050] |
| CI | `flow-tests.yml` and `dossier-tests.yml`, path-filtered, `contents: read`; plus CodeQL. **All advisory** | GitHub Actions | [EV-0013], [EV-0016] |
| Release | Bump `plugin.json` and the matching `marketplace.json` entry, optionally bump `metadata.version`, tag, publish. Publishing triggers desktop packaging | manual, unverified by anything | [EV-0032], [EV-0026] |
| Feature flags | None at runtime — there is no runtime. Install-time defaults only | plugin `settings.json` | [EV-0044] |

## Reading order

| Order | Document or code path | Why it comes here | Time |
|---|---|---|---|
| 1 | `.claude-plugin/marketplace.json` | 8 entries in one file — the whole product in one read | 2 minutes |
| 2 | `.claude/CLAUDE.md` | The repository's own conventions, which no tool enforces | 10 minutes |
| 3 | `plugins/flow/skills/evidence-based-development/SKILL.md` | The canonical skill shape every other skill follows | 10 minutes |
| 4 | `plugins/dossier/tests/bin-scripts.test.sh` | Shows what this project considers a test worth writing, including the anti-theater assertion | 15 minutes |
| 5 | `plugins/flow/hooks/hooks.json` and `hooks/scripts/block-destructive.sh` | The highest-consequence code in the repository — it runs on other people's machines | 15 minutes |
| 6 | `docs/dossier/01-project/executive-project-brief.md` | This package's own summary of what is and is not true here | 10 minutes |

## First day, week, and month

| Horizon | Outcome | How it is demonstrated |
|---|---|---|
| First day | Both suites run green locally; you can name what a skill, command, agent, and hook each are, and which of them execute without an operator asking | `TOTAL pass=1022 fail=0` and `TOTAL pass=1034 fail=0` on your own machine |
| First week | One merged change with a test that fails without it | A pull request that adds an assertion and the change it guards |
| First month | You can add a plugin end to end — tree, manifest entry, README row, version agreement — and you know which of those steps nothing checks | A published plugin whose `plugin.json` and manifest entry agree, and whose README row is correct on the first try |

## Starter task

| Step | Action | Expected result |
|---|---|---|
| 1 | Run `grep -c -i dossier README.md` | `0` — a published plugin absent from the storefront [EV-0023] |
| 2 | Run `jq '.plugins \| length' .claude-plugin/marketplace.json` and compare with the README's `Plugins-6-green` badge | 8 versus 6 [EV-0022] |
| 3 | Compare each README version cell against `jq -r '.plugins[] \| "\(.name)=\(.version)"'` | flow 3.2.0 vs 3.2.2; prompt-decorators 0.1.0 vs 0.1.1 [EV-0024], [EV-0025] |
| 4 | Fix all four in `README.md` | The storefront matches the manifest |
| 5 | Consider what would have prevented all four | One CI step comparing the README to the manifest. That is the real starter task, and it does not exist yet [EV-0026] |

This starter task is deliberately a real defect rather than a toy. It takes about fifteen minutes, it touches the file a prospective user reads first, and it ends by making the point the whole repository is about.

## Troubleshooting

| Symptom | Likely cause | Resolution | Verified |
|---|---|---|---|
| A script fails with `declare: -A: invalid option` | macOS bash 3.2; the script uses a bash 4 construct | Rewrite without associative arrays. Both suites assert against this class | yes — the assertion exists and passes [EV-0008], [EV-0009] |
| A hook does not fire | The file lacks the executable bit | `chmod +x`. Both suites and `dossier-tests.yml` check this | yes [EV-0009] |
| `dossier-package-check.sh` reports 175 findings on a fresh scaffold | Expected. The headers are still `{fill}` placeholders | Draft the documents | yes — observed exactly this on the fresh scaffold [EV-0047] |
| The YAML-parse leg of the workflow test is skipped | `pyyaml` is not installed | Optional. The test records a pass with the reason and continues structural checks; CI pins `pyyaml` | yes [EV-0009] |
| A `!` bash block cannot find the plugin root | `CLAUDE_PLUGIN_ROOT` is unset in slash-command bash blocks | Both flow and dossier ship a four-candidate fallback resolver for this | yes — it is why the resolver exists |
| Anything on Windows | Two open issues report failures under Git Bash | **No resolution exists.** Use macOS or Linux (AQ-0008) | reported, not reproduced [EV-0049] |

## Proposing changes

| Change kind | Where to propose it | Who decides | What the proposal must contain |
|---|---|---|---|
| Product | A GitHub issue | Daniel Bentes | The problem observed, not the feature wanted |
| Architecture | A GitHub issue, then a pull request | Daniel Bentes | The tradeoff and the rejected alternative. Note that **no decision record in this repository covers an architectural choice** [EV-0046] |
| Security | **There is no private channel.** A public issue is the only path | Daniel Bentes | — |
| Documentation | A pull request | Daniel Bentes | The evidence for the corrected fact |

No `CONTRIBUTING.md`, CODEOWNERS, issue template, or pull-request template exists [EV-0036]. Everything in this table is inferred from the repository's structure and its `.claude/CLAUDE.md` conventions, not from a stated process.

## Definition of done

| Work type | Done means |
|---|---|
| Engineering | The change is made; a test that fails without it exists where the plugin has a suite; both suites pass; any prose stating a count or version that the change alters is updated in the same commit |
| Product | The decision is recorded somewhere durable. Today that means a `.decisions/` record, which is the only such mechanism present [EV-0046] |

The second half of the engineering row is the one this repository keeps failing: four README facts drifted because prose and manifest were changed in different commits [EV-0022]–[EV-0025].

## Getting help

| Need | Contact | Channel | Hours |
|---|---|---|---|
| Anything | Daniel Bentes | GitHub issues, public | none stated |
| Security disclosure | **no private contact exists** | — | — |
| Escalation | **none — there is no second person** | — | — |

Three rows, one person, no private channel, no stated hours. That is the accurate state, and it is why the bus-factor and disclosure-channel findings appear in the risk register rather than only here.
