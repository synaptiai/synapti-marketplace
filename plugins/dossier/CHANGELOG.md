# Changelog

All notable changes to the dossier plugin are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-07-25

Initial release.

### Added

**Method — 9 skills**

- `engagement-scoping` — resolves the engagement scope, action ceiling, and permitted file set in Phase 0 and freezes them for the run
- `evidence-ledger` — the `EV-####` ledger, the seven-level source-authority ordering, and the six claim states (verified, corroborated, reported, inferred, unknown, not applicable)
- `gap-and-contradiction-register` — the `AQ-####` and `CT-####` registers; contradictions are recorded and escalated, never resolved by choosing
- `project-modeling` — one canonical project model with audience views projected from it, plus the end-to-end traces verification later attempts to falsify
- `doc-package-contract` — the fixed 7-directory, 23-file structure, the internal and public document headers, and index maintenance
- `disclosure-gating` — the `CL-####` claim and disclosure register and the derivation of the two public documents from approved claims only
- `verification-protocol` — one independent verification pass executed by falsification, emitting findings before any repair
- `finding-reconciliation` — merges the independent A/B/C findings, publishes the pre-repair table, and splits agent-repairable from owner-decision
- `scoring-and-release-gate` — the ten-dimension weighted scorecard and the seventeen-condition binary release gate

**Commands — 9**

`/dossier:init`, `/dossier:baseline`, `/dossier:refresh`, `/dossier:audit`, `/dossier:reconcile`, `/dossier:gate`, `/dossier:claim`, `/dossier:status`, `/dossier:setup`.

**Agents — 6**

Three context-isolated verification passes (`dossier-pass-a-evidence`, `dossier-pass-b-falsification`, `dossier-pass-c-audience`), plus `dossier-scorer`, `dossier-evidence-collector`, and `dossier-doc-drafter`.

Pass independence is architectural rather than instructed: separate dispatches, `memory: none`, a skill firewall that keeps reconciliation logic out of every verifier's context, single-message dispatch, and per-pass model configuration. A regression test enforces all five properties.

**Package**

The canonical 23-file documentation package across `00-control/`, `01-project/`, `02-architecture/`, `03-assurance/`, `04-operating/`, `05-due-diligence/`, `06-public/`, and `07-verification/`, with per-file content contracts and document skeletons.

A `README.md` signpost is scaffolded at the output root alongside them. It is supplemental rather than canonical — never overwritten, excluded from the canonical count, and asserting no fact about the project, so it cannot go stale. It exists because a reader browsing the output root otherwise reaches eight numbered directories and never finds the index that routes them.

`dossier-package-check.sh` reports `CHECK_DIAGRAMS_EXPECTED` and `CHECK_DIAGRAMS_PRESENT`, and records a finding when a document whose template asks for a diagram ships without one. Counting mermaid fences grades the diagrams somebody drew and says nothing about the prompts they skipped.

**Post-merge automation**

`/dossier:setup` scaffolds a GitHub Actions workflow into the consuming repository that regenerates affected documents after a pull request merges and opens a documentation pull request against the same repository.

- Three jobs split by privilege: the policy job decides and builds evidence with no agent, the refresh job runs the agent with no write token, and the publish job holds the write token and runs no agent code
- Range-based refresh against a durable cursor, so concurrent merges, dropped runs, and the scheduled sweep compose without re-processing or gaps
- Four independent loop guards evaluated before a runner is allocated
- Patch validation against a write allowlist in both the unprivileged and the privileged job, with a secret scan before the patch artifact is uploaded
- Fast-forward pushes only; merge-forward, never rebase
- Hard failure with remediation when Anthropic credentials are absent, so stale documentation never masquerades as current

**Configuration**

`.claude/settings.dossier.json` resolved through the standard four-source cascade with `DOSSIER_*` environment overrides. Conditional and cross-field rules live in `bin/dossier-validate-config.sh` rather than in `schema.json`, because the documented fallback validator ignores `if`/`then` when `jsonschema` is absent — a schema conditional would report success and enforce nothing on exactly the machines that need it.

### Fixed

First run against a real project — this repository — surfaced nine defects that 1034 assertions had not, because each was a disagreement between two artifacts no single test compared.

- `dossier-gate.sh` condition G17 required a heading and a `Model diversity:` line that the shipped verification-report template did not carry, so a faithfully drafted report failed the gate every time. The template now matches the gate and the contract reference, and a test reads the expected heading out of the gate script so renaming either alone fails.
- `dossier-ledger-lint.sh` compared the `Source ref` cell against the filesystem verbatim, while `references/evidence-ledger-schema.md` writes every one of its own examples as a Markdown code span — the documented form failed the lint. Code spans are now stripped before classification, and a cell carrying several spans has each of them checked.
- `dossier-ledger-lint.sh` iterated locators through a pipe, so `emit` incremented the error counter inside a subshell and the linter printed findings under `LEDGER_ERRORS=0`. A caller reading only the count saw a clean ledger. The loop no longer forks.
- `dossier-claim-scan.sh` read YAML frontmatter as prose, reporting `title:` and `audience:` as unregistered claims in every public document — findings no drafter could resolve.
- `dossier-claim-scan.sh` lowercased approved wordings but did not normalize them, while document sentences were fully normalized. Markdown survived on one side only, so a claim containing a code span, emphasis, or a link could never match its own approved row — the registration check could not pass for a realistic claim.
- `dossier-claim-scan.sh` split sentences on a bare `.`, cutting inside `SKILL.md`, `plugin.json`, and version numbers, and reporting the fragments as unregistered claims. Code spans now come out before the split.
- `dossier-claim-scan.sh` matched only approved claim rows, so a **required qualification** — text the contract mandates appear beside the claim it qualifies — was always reported as an unregistered sentence. Two rules the plugin ships, contradicting each other, with no way for a drafter to satisfy both.
- `tests/plugin-manifest.test.sh` asserted a hard-coded licence identifier. A constant passes while the file it names says something else, which is how this repository came to advertise a licence it did not carry. It now reads the SPDX identifier from the `LICENSE` file and fails loudly when there is none.
- `tests/run.sh` leaked roughly 80 temp directories per run. Test files are *sourced*, so an `EXIT` trap set by one is replaced by the next file's, and a trailing cleanup line strands above whatever the next contributor appends. The runner now owns one directory, points `TMPDIR` at it, and removes it on exit, so cleanup no longer depends on per-file discipline.

### Added

- `derived:<EV-#### expression>` as a `Source ref` locator form. A row whose grounding is other ledger rows always existed in the method; the schema table had no form for it, so the linter treated the expression as a path.

### Known limitations

- `plugin_marketplaces` accepts no ref, so a CI run always executes the skill text from marketplace `main` even when the helper scripts are pinned to a tag. Set `ci.instructionSource: vendored` for reproducible CI or a private marketplace.
- The circuit breaker bounds runaway refresh loops, not cost per run. GitHub Actions has no spend cap for third-party API calls; set a budget in the Anthropic console.
- Secret-scan patterns miss novel credential formats. The agent has no network egress and the documentation pull request is human-reviewed, which are the backstops.
- A plugin cannot guarantee a different model for verification. In-plugin passes give independent context with a configurable model; `/dossier:audit --external` renders a self-contained prompt for genuinely cross-model review. Which tier was used is recorded in the verification report.

[1.0.0]: https://github.com/synaptiai/synapti-marketplace/tree/main/plugins/dossier
