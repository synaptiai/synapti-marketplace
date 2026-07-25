---
dossier-header: internal-v1
title: Assumptions, Open Questions, and Contradictions
purpose: Tells a reader which parts of this package rest on something unresolved, so they can weight the rest accordingly.
audience: Reviewer, Maintainer
confidentiality: Public
owner: Daniel Bentes
status: verified
project-version: d0fa737
last-verified: 2026-07-26
review-trigger: Any new evidence that settles an open row, or any new source disagreement discovered during refresh
related: [00-control/evidence-ledger.md, 00-control/claim-and-disclosure-register.md, 04-operating/decisions-technical-debt-and-risks.md]
---
# Assumptions, Open Questions, and Contradictions
<!-- contract: references/package-contract-00-control.md#assumptions-questions-and-contradictions -->

## Method

Two registers. `AQ-####` holds assumptions the package relies on and questions that must be answered; `CT-####` holds disagreements between sources. Column definitions and identifier grammar are in the plugin reference `references/register-schemas.md`.

A contradiction is never resolved by choosing the convenient side. Both sides are recorded with their evidence and authority level, the decision impact is named, and the row stays `unresolved` until evidence settles it or scoping makes both true. While a contradiction is open, both underlying evidence rows drop to at most `R`.

## Assumptions and open questions

| ID | Kind | Statement | Why it matters | Working position | Evidence needed | Proposed owner | Blocking | Affected docs | Due | Status | Resolution |
|---|---|---|---|---|---|---|---|---|---|---|---|
| AQ-0001 | question | The `agent-capability-standard` Python test suite passes at the pinned commit | It is the only plugin with executable logic beyond shell, and the only one carrying a dependency | Unknown. The suite exists; its result is not observed | `pytest` run in an environment with `pyyaml` installed | Daniel Bentes | no | 03-assurance/testing-quality-and-delivery.md, 05-due-diligence | open | — |
| AQ-0002 | question | The dossier post-merge refresh workflow works end to end in a live repository | The plugin's headline capability. Its three-job privilege split, patch validation, and rolling-branch publishing are unit-tested but never executed together | Unverified. Structure is tested (EV-0009); behaviour is not | One scratch repository, one API-key secret, one merged pull request, one observed docs pull request | Daniel Bentes | **yes** | 03-assurance, 04-operating, 05-due-diligence, 06-public | before dossier is described as working in any public document | open | — |
| AQ-0003 | question | The marketplace installs cleanly from a **clean** Claude Code profile | Every claim about how an operator gets the plugins rests on it | Resolution and install are observed working on one machine [EV-0051], [EV-0052]; a first-time install on an unconfigured profile is still unobserved | An install performed from a profile with no marketplace configured, ideally in CI | Daniel Bentes | no | 04-operating/onboarding-and-local-development.md, 06-public | partially resolved | The `add` → resolve → install → cache path is verified for an existing profile; the cold path is not |
| AQ-0004 | assumption | The marketplace has installing users other than its maintainer | Determines whether stale README facts are a real reader-harm or a private inconvenience | Assume yes and treat reader-facing accuracy as material. The repository is public and releases are published | Install telemetry, which does not exist for plugin marketplaces | — | no | 01-project, 06-public | open | Unresolvable from this repository; recorded so no document silently assumes a user base |
| AQ-0005 | question | The `prompt-decorators` entry's description matches its actual contents | It is published to installers from this manifest, but its source is not in this repository | Reported only. Every statement about it in this package is attributed to the marketplace entry | Inspection of `synaptiai/prompt-decorators` at the `claude-code-plugin` subdirectory | Daniel Bentes | no | 02-architecture, 05-due-diligence | open | — |
| AQ-0006 | question | What the 2 commits between tag `v1.2.0` and the pinned submodule commit change | The marketplace advertises `agent-capability-standard` as 1.2.0 while shipping a tree that is not 1.2.0 | Treat the advertised version as approximate | `git log v1.2.0..95f7ac2` in the upstream repository | Daniel Bentes | no | 02-architecture, 05-due-diligence | open | — |
| AQ-0007 | question | Whether the contribution path works for anyone but the maintainer | A public repository with 8 published plugins and no contribution guidance, no CODEOWNERS, and no external contributor to date | Assume untested | One external pull request reviewed and merged, or a documented contribution process | Daniel Bentes | no | 04-operating, 05-due-diligence | open | — |
| AQ-0008 | question | The real Windows and Git Bash portability surface of the 26 shipped shell scripts | The scripts run on the operator's machine. Two open issues (#100, #130) assert defects, and neither CI workflow runs on Windows | Assume defects exist as reported; the scope is unmeasured | A CI matrix job on `windows-latest` running both suites | Daniel Bentes | no | 03-assurance, 04-operating, 06-public | open | — |
| AQ-0009 | assumption | Skill and command counts derived by file-counting are the counts an operator experiences | Every artifact-count claim in this package uses `find … -name SKILL.md` | File-counting is authoritative; directory-counting is not, because an empty directory is not a skill (EV-0029) | — | Daniel Bentes | no | 02-architecture, 06-public | closed | Confirmed: `plugins/flow/skills/learned/` holds only `.gitkeep`, which is exactly the 33-vs-32 discrepancy in CT-0002 |
| AQ-0011 | question | GitHub's repository-level licence detection reports Apache-2.0 | The badge a visitor sees, and the field every automated licence scanner reads | Unobservable from here. The `/license` endpoint returns 404 for any non-default ref, and repository-level detection is computed from the default branch, where `LICENSE` does not yet exist | One `gh api repos/synaptiai/synapti-marketplace --jq .license` after this branch merges | Daniel Bentes | no | 05-due-diligence, 06-public | on merge | open | The file and every declaration are verified; only GitHub's derived field is pending |
| AQ-0010 | assumption | Assessment on an unmerged feature branch is representative of the project | This package was produced at `d0fa737` on `feature/dossier-documentation-plugin`, not on `main` | State it in every header via `project-version`, and treat `main`-only claims as out of scope | Re-run after merge | Daniel Bentes | no | all | open | Version 4.7.0 and the entire dossier plugin exist only on this branch (EV-0033) |

## Contradictions

| ID | Claim A | Claim B | Likely cause | Decision impact | Resolution | Resolution basis | Owner | Next verification | Affected docs |
|---|---|---|---|---|---|---|---|---|---|
| CT-0001 | `README.md` presented an MIT licence badge linking to `LICENSE`, and its closing section stated the project was MIT-licensed [EV-0020] | No `LICENSE` file existed and GitHub detected no licence for the repository | A badge and a licence sentence were written without the file being added | **High while open.** Absent a licence file, default copyright applied and no installer had a grant of rights to the six MIT-declared plugins, whatever the badge said | **resolved** | Evidence, not choice: a `LICENSE` file carrying the canonical Apache-2.0 text was added at the repository root and pushed [EV-0019], and every declaration was aligned to it — 7 plugin manifests, 8 marketplace entries, the README badge and licence section, 5 plugin READMEs [EV-0021], [EV-0020]. The owner chose Apache-2.0 | Daniel Bentes | On merge, confirm `gh api repos/…` reports `apache-2.0` — detection is computed from the default branch and cannot be observed from a feature branch (AQ-0011) | 05-due-diligence/assets-dependencies-and-licenses.md, 06-public |
| CT-0002 | The flow plugin's README claims 33 skills [EV-0028] | 32 `SKILL.md` files exist in the flow tree [EV-0004] | `plugins/flow/skills/learned/` is a reserved placeholder holding only `.gitkeep`; it counts as a directory but is not a skill [EV-0029] | Low. A reader comparing the README to the installed tree finds one skill they cannot locate | resolved | Both sides are true under different counting rules. The file count is the one an operator experiences, so 32 is the number a document may state | Daniel Bentes | On any change to the flow skill set | 02-architecture/components-and-codebase.md, 04-operating |
| CT-0003 | The `ai-first-org-design-kit` marketplace description says "Fourteen opinionated skills" [EV-0027] | 15 `SKILL.md` files exist in that tree [EV-0004] | The set grew by one without the description being updated; the description also enumerates exactly fourteen capabilities | Low, but the description is what an installer reads before installing | unresolved | — | Daniel Bentes | Recount after the description is corrected | 04-operating/decisions-technical-debt-and-risks.md |
| CT-0004 | The repository's own dossier CI template forbids `${{ github.event.* }}` interpolation inside a `run:` body, and a shipped test enforces it | `release-desktop-skills.yml` line 24 does exactly that with `github.event.release.tag_name` [EV-0015] | The rule was written for the artifact being shipped to others and never applied to the repository's own workflows | Medium. Release tag names are set by whoever can publish a release, so exploitation requires maintainer-level access — but the repository fails a standard it publishes | unresolved | — | Daniel Bentes | Re-run the `awk` scanner (CHK-06) over all workflows | 03-assurance/security-privacy-and-compliance.md, 04-operating |

## Blocking decisions

| ID | Decision required | Who must decide | What is blocked | Consequence of proceeding without it | Deadline |
|---|---|---|---|---|---|
| AQ-0002 | Whether the dossier post-merge automation may be described as working before it has been observed working | Daniel Bentes | Any public statement that the plugin refreshes documentation automatically after a merge | The package would assert a capability whose only evidence is that its parts are unit-tested — the precise failure mode this documentation standard exists to prevent | Before the dossier plugin is announced or its pull request is merged |
| CT-0001 | ~~Whether to add a `LICENSE` file, and which licence it states~~ | Daniel Bentes | — | **Discharged 2026-07-26.** Apache-2.0 chosen; file added; all declarations aligned | — |

## Recommended evidence requests

Ordered by decision impact, highest first.

| Rank | Request | Smallest sufficient artifact | Resolves | Decision unblocked | Asked of |
|---:|---|---|---|---|---|
| 1 | Confirm GitHub reports the licence once this branch merges | One `gh api repos/… --jq .license` returning `apache-2.0` | AQ-0011 | Whether the repository badge and automated scanners see the licence | Daniel Bentes |
| 2 | Run the post-merge refresh once, end to end, and keep the run URL | One GitHub Actions run link plus the docs pull request it opened | AQ-0002 | Whether the plugin's headline capability may be stated as fact | Daniel Bentes |
| 3 | Add a `windows-latest` job to both plugin test workflows | One CI run, pass or fail | AQ-0008 | The scope of issues #100 and #130 | Daniel Bentes |
| 4 | Run the submodule's Python suite once | `pytest` output | AQ-0001 | Whether the marketplace's only dependency-bearing plugin is tested | Daniel Bentes |
| 5 | Read the 2 commits past `v1.2.0` in the submodule | `git log v1.2.0..95f7ac2 --oneline` | AQ-0006 | Whether the advertised version is accurate | Daniel Bentes |
| 6 | Inspect the `prompt-decorators` plugin subdirectory | A file listing plus its `plugin.json` | AQ-0005 | Whether an entry published from this manifest is described accurately | Daniel Bentes |

## Open items summary

| Measure | Count |
|---|---|
| Open assumptions | 3 |
| Open questions | 7 |
| Open `blocking` items | 1 |
| Unresolved contradictions | 2 |
| Items with no proposed owner | 1 |
| Items past due | 0 |

Any open `blocking` item, and any unresolved contradiction that could materially mislead a diligence, onboarding, integration, operational, security, or customer decision, fails the release gate regardless of package score. AQ-0002 remains open and blocking. CT-0001 is now resolved by evidence — the licence file exists and every declaration matches it — so the materially-misleading contradiction that failed the gate on the first round is gone. Both states are carried into the verification report.
