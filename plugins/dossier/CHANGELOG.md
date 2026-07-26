# Changelog

All notable changes to the dossier plugin are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-07-26

Two reviewers reported after 1.0.0 was tagged. Both found real defects, one of
them in a fix that release had just shipped.

### Fixed

- **The action-ceiling wrapper fix was incomplete.** 1.0.0 stripped a wrapper
  token plus one optional flag, which is the wrong shape: it needs to know which
  flags take a value. `timeout 30 curl …` left `30` between the wrapper and the
  payload, so the anchor never matched and the entire deny list passed — and
  `timeout N cmd` is the most idiomatic way to bound a command, so this was the
  modal bypass, not an exotic one. Also affected `sudo -u www-data curl`,
  `nice -n 10 curl`, and `timeout -s KILL 30 curl`. The repair no longer tries to
  find where the real command starts: when a wrapper appears anywhere, whitespace
  itself becomes a boundary, so no argument shape can hide a keyword. The cost is
  a narrow over-block (`timeout 5 grep -r "npm test"` is refused) which is the
  correct direction to fail. It shipped green because every wrapper case tested in
  1.0.0 happened to take no argument.
- **The disclosure scanner printed AWS keys and PEM headers into its own
  findings.** `normalize()` folds case and ran *before* `redact()`, whose
  `AKIA[0-9A-Z]{16}` and PEM-armour patterns are case-sensitive by construction —
  so those two classes emerged lowercased but complete, into output bound for a CI
  log. The redactor now runs on the raw sentence. This is the exact failure the
  function's own comment says it exists to prevent.
- **`dossier-validate-config.sh` reintroduced the `//`-on-`false` bug** that was
  fixed in the cascade resolvers in the same release. `ci.enabled: false` read as
  unset, so three CI guards fired against a config that had explicitly turned CI
  off.
- **Three CI-facing scripts ignored the `DOSSIER_*` environment layer**,
  contradicting `schema.json`, which calls that layer "what lets a CI job run with
  zero interaction". `dossier-policy.sh` and `dossier-evidence.sh` now route
  through the resolver. `dossier-validate-patch.sh` deliberately does not, and now
  says so in both the script and the schema: it runs in the same environment as
  the agent it contains, and the value it reads is the write allowlist — an agent
  able to set `DOSSIER_CI_WRITE_ALLOWLIST` could widen its own boundary.
- **The approved-claim scan swept the whole register**, including the rejected and
  withdrawn table, whose different column layout could let a free-text cell
  containing the approval marker read as an approved claim. Scoped by excluding
  the section that cannot hold approvals, rather than by requiring a specific
  inventory heading — requiring one would silently stop recognising approvals in
  any register that named its sections differently.
- **`--comment` was accepted and ignored** in `--verify` mode.
- **A stray space in a `tr` delete-set** stripped every space from the value, not
  just quotes and CR. Harmless on the ISO date it currently reads, wrong for any
  field with spaces, and duplicated in two files.
- **Unquoted splits still globbed.** A custom `IFS` suppresses word splitting but
  not pathname expansion. Fixed in the ledger cell split and the `related:` entry
  split — and the first attempt at the latter left `set -f` unbalanced, disabling
  globbing for the rest of the script, which is what produced a one-off failure on
  Linux that three later runs did not reproduce.
- **mktemp hard-fails used exit 2** where each script's own documented contract
  reserves 2 for a bad argument and 1 for infrastructure failure.

### Changed

- The gate's condition-count cross-check maps numbers 1–25 instead of a
  three-value window, and fails loudly outside it. Previously an unmapped count
  blanked the variable and skipped every assertion below with no pass and no fail
  recorded — silently absent, which is the defect class the check exists to catch.

## [1.0.0] - 2026-07-26

Initial release. The sections below record the pre-release review cycles, because a defect found and fixed before shipping is still evidence about how the thing was built.

### Fixed before release

- **`enforce-output-root.sh` allowed writes out of the output root.** The allow-case
  was a `case` glob, and a glob `*` matches `/` — so `docs/dossier/../../.github/…`
  textually started with the allowed prefix and was permitted while landing outside
  it. A `..` segment is now refused before the prefix test, which is what makes the
  test read as what it does. The comment three lines below had asserted the opposite
  behaviour since the file was written.
- **The three security hooks failed open on a missing `jq`.** Write containment,
  disclosure blocking, and the action ceiling all silently no-opped when `jq` was
  absent from `PATH`. They now fail closed. `stale-header-stamp.sh` is advisory and
  keeps the old behaviour, which is the correct posture for it.
- **`enforce-allowed-actions.sh` was defeated by one layer of indirection.**
  `/usr/bin/curl`, `env curl`, `command curl`, `bash -c "npm test"`, and
  `eval "curl …"` all placed the keyword where no boundary character preceded it,
  so the whole deny list passed. Wrapper invocations are now detected and rescanned
  with quotes neutralised, while `grep -r "npm test" docs/` — reading about a
  command rather than running one — still passes. The header now states the hook's
  honest scope: a tripwire, not a sandbox.
- **`block-unregistered-claim.sh` had no `internal-path` class.**
  `disclosure-policy-levels.md` names internal repository paths as prohibited in
  `06-public/` and says this hook enforces it alongside `dossier-claim-scan.sh`. The
  scanner had the pattern; the hook did not, so a sentence naming
  `src/internal/billing/config.rb` was written into a public document with no live
  block.
- **`dossier-validate-patch.sh` accepted symlinks and traversal paths.** A path
  inside the write allowlist can still point outside it: mode `120000` escapes by
  reference, and `docs/dossier/../../.env` matches the allowlist's compiled ERE
  `^docs/dossier/.*$`. Both are now refused in staging and verification mode. This
  is the documented control and the publish job's independent re-check, so it no
  longer relies on `git apply` rejecting the path as a side effect.
- **`dossier-policy.sh` wrote unvalidated config into `$GITHUB_OUTPUT`.**
  `schema.json` constrains `ci.agent.model` to a bare token precisely because the
  value is interpolated into `claude_args`, but the only enforcement lived in a
  validator the workflow never invokes. The pattern is now re-checked at the point
  of use, and every emitted value is stripped of control characters — a newline
  forges additional output pairs for the next job rather than merely rendering
  wrong.
- **Five unchecked `git` calls in the refresh workflow.** `fetch`, `push --delete`,
  three `checkout -B`, and the `commit` before `committed=true` ran in a step with
  no `set -e`; a failure left the wrong branch checked out and the run continued,
  or reported a commit that never happened.
- **Temp-file handling was inconsistent across `bin/`.** Eleven sites fell back to a
  predictable `/tmp/<name>.$$` when `mktemp` failed — including the patch validator
  — while three hard-failed. All now hard-fail. `dossier-evidence.sh` registers all
  five of its temp files with the one trap instead of relying on each code path
  reaching its own cleanup, and `dossier-package-check.sh` gained the trap its
  sibling scripts already had.
- **`dossier-blast-radius.sh` dropped an event silently** when its `jq` write
  failed, producing a report that read as "nothing matched" rather than "this was
  not recorded".
- **`dossier-pr-body.sh` escaped `|` but not `[`, `]`, or backtick,** so a hostile
  pull request title could rewrite a table cell into a link that said something the
  title did not.

#### The plugin contradicting itself

These are the defect class dossier exists to catch, found in its own artifacts.

- The `doc-package-contract` skill description stated the directory count as one
  fewer than the Iron Law in the same file. `dossier-scaffold.sh` and this
  changelog carried the same off-by-one.
  **The regression test written to pin this reported a pass on the file that carried
  it** — its pattern required a space and missed the hyphenated form. The pattern now
  matches both, and the scan set covers every file that states the count.
- The plugin README stated the gate as one condition smaller than it is, and
  understated the mechanical half by one. The gate has seventeen conditions, ten
  of them mechanical. The condition count and the mechanical/judgment
  split are now derived from the condition table by a test, so adding G18 moves the
  expectation and any prose that still says "seventeen" fails.
- The repository README said four of seventeen gate conditions fail; the package has
  said two since round 3.
- `finding-schema.md` and `release-gate-conditions.md` cited `AS-` and `OQ-` register
  prefixes. Neither exists anywhere in the plugin — the registers are `CL-`, `CT-`,
  `AQ-`, and `TM-`.
- G17's section sat after `## Related references`, out of sequence with G01–G16.

#### Test coverage added

- `validate-patch.test.sh` — the write-allowlist control had no functional test at
  all. Fourteen assertions, almost all rejection cases: allowlist escape, traversal,
  symlink by mode and by working tree, credential in an allowlisted hunk, and an
  empty allowlist. The traversal defect above was found by this test.
- `package-check-findings.test.sh` — fixtures for the documented finding codes,
  including every field on the internal-only list that `LEAKED-FIELD` guards.
- `bin-behaviour.test.sh` — behavioural coverage for scripts that previously had
  only hygiene checks, including the blast-radius mapping and the four
  always-regenerated control documents.
- Hook tests for traversal refusal, wrapper indirection, fail-closed-on-missing-`jq`,
  and the `internal-path` disclosure class; the action ceiling's deny path was
  previously never exercised.
- The fifth independence mechanism (per-pass model configuration) is now asserted.
  The README claimed a regression test enforced all five; four were covered.

### Shipped in the initial release

#### Added

**Method — 9 skills**

- `engagement-scoping` — resolves the engagement scope, action ceiling, and permitted file set in Phase 0 and freezes them for the run
- `evidence-ledger` — the `EV-####` ledger, the seven-level source-authority ordering, and the six claim states (verified, corroborated, reported, inferred, unknown, not applicable)
- `gap-and-contradiction-register` — the `AQ-####` and `CT-####` registers; contradictions are recorded and escalated, never resolved by choosing
- `project-modeling` — one canonical project model with audience views projected from it, plus the end-to-end traces verification later attempts to falsify
- `doc-package-contract` — the fixed 8-directory, 23-file structure, the internal and public document headers, and index maintenance
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

#### Fixed during the first three review cycles

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

#### Added during the first three review cycles

- `derived:<EV-#### expression>` as a `Source ref` locator form. A row whose grounding is other ledger rows always existed in the method; the schema table had no form for it, so the linter treated the expression as a path.

#### Known limitations

- `plugin_marketplaces` accepts no ref, so a CI run always executes the skill text from marketplace `main` even when the helper scripts are pinned to a tag. Set `ci.instructionSource: vendored` for reproducible CI or a private marketplace.
- The circuit breaker bounds runaway refresh loops, not cost per run. GitHub Actions has no spend cap for third-party API calls; set a budget in the Anthropic console.
- Secret-scan patterns miss novel credential formats. The agent has no network egress and the documentation pull request is human-reviewed, which are the backstops.
- A plugin cannot guarantee a different model for verification. In-plugin passes give independent context with a configurable model; `/dossier:audit --external` renders a self-contained prompt for genuinely cross-model review. Which tier was used is recorded in the verification report.

[1.0.1]: https://github.com/synaptiai/synapti-marketplace/tree/main/plugins/dossier
[1.0.0]: https://github.com/synaptiai/synapti-marketplace/tree/main/plugins/dossier
