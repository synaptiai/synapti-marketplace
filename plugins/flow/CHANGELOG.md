# Changelog

## 2.3.0 (2026-05-06)

### New helper scripts (`plugins/flow/bin/`)

- `flow-escalate.sh` — CLI utility that formats canonical six-field Proactive-Autonomy escalations (Situation, What I tried, Options, Recommendation, Time sensitivity, Risk) per `references/escalation-format.md`. Output is a markdown body suitable for `AskUserQuestion`. Validates required fields and option grammar (`<n>: <text>`); exits 0/1/2 with clear stderr. Available for ad-hoc human use; commands continue to inline the escalation prose so the structure stays inspectable in each command body.
- `validate-skill-input.sh` — validates a skill's input payload against its JSON Schema at `${CLAUDE_PLUGIN_ROOT}/schemas/<name>/input-schema.json` (schemas ship inside the plugin payload so end-users get them at install time; `tests/skills/<name>/` continues to hold the test fixtures only). Tries `import jsonschema` for full Draft-07 validation; falls back to a shape-check (required, types, enums, patterns, minItems, minLength) implemented in the standard library so the script works on any Python 3.x install. Exits 0 (valid), 1 (validation failure with path + reason), or 2 (infrastructure error).
- `journal-record.sh` — atomically updates the YAML frontmatter manifest in `.decisions/issue-{N}.md` with a new artifact entry (specification, stranger-test, review-cycle, dropped-finding, design-decision, brainstorm-decision, verdict, escalation-resolved). Idempotent across runs; preserves legacy bodies when the journal lacks a manifest. Atomic via temp file + rename.
- `promote-proposal.sh` — promotes a `/flow:learn` proposal to an active skill at `plugins/flow/skills/learned/{name}/SKILL.md` via a **draft** PR. Validates frontmatter (required fields, status=proposal, kebab-case name) and body sections (`## Pattern Detected`, `## Knowledge`, `## Evidence`, `## Verification`, `## Promotion Checklist`). Tier 2 by design: opens a draft PR and never marks it ready or merges. `--dry-run` flag for non-mutating validation.

### New repo-level test suites

- `tests/skills/holdout-validation/`, `tests/skills/criterion-verification-map/`, `tests/skills/specification-capture/` — six assertions per skill (valid input, invalid input, missing required, non-JSON input, edge-case validation), plus an extra trailing-newline regression test on `holdout-validation` that pins the `(?!\n)$` anchor in the ID pattern. 19 total; all pass.
- `tests/finding-schema/` — 14 assertions (7 valid fixtures + 7 invalid, the latter including a trailing-newline ID rejection) covering the canonical finding row shape (ID grammar, priority/confidence/disposition enums, required fields). Catches drift between `references/finding-schema.md` and the actual rows reviewer agents emit.
- `tests/status-parser/` — 10 assertions verifying that `status.md`'s ledger parser stays in lockstep with `merge.md`'s parser across legacy 5-field, extended 7-field, mixed-cycles, and review+resolution markers. Includes hostile-ID and malformed-priority rejection tests that mirror the production ID grammar.
- `tests/journal-orchestration/` — 16 assertions exercising the full `bin/journal-record.sh` lifecycle for a synthetic issue. Covers all 9 documented artifact types, manifest top-level fields, captured_at presence, type-order preservation, per-type required-field assertions, and append-on-rerun (multi-cycle review-cycle entries).

### New canonical reference documents

- `references/skill-contracts.md` — explains what JSON Schema input contracts exist, the validator strategy (jsonschema if installed, shape-check fallback), the test-fixture convention, and how to add a contract for a new skill.
- `references/decision-journal-schema.md` — extended with the **YAML frontmatter manifest schema**. Documents the required top-level fields, the artifact-type vocabulary (specification, stranger-test, review-cycle, dropped-finding, etc.), per-type required metadata, compatibility with the legacy structured-entry format, and the tradeoff between YAML and JSON for the manifest.

### Tier classification (gate 19 of the plan)

Every command in `plugins/flow/commands/` now carries a `## Tier Classification` section at the bottom listing the actions it takes and the tier for each (1 = autonomous, 2 = journaled, 3 = confirm). Coverage: 17/17 commands. `grep -L "^## Tier Classification" plugins/flow/commands/*.md` returns nothing.

### Frontmatter sweeps

- `disable-model-invocation: true` added to `pr-lifecycle/SKILL.md` and `preflight-checks/SKILL.md` (matching the existing flag on `merge-and-release/SKILL.md` and `team-coordination/SKILL.md`). All four reference-only skills now disable autonomous invocation by the model — they are policy documents consumed by commands, not skills the orchestrator invokes on its own.
- `paths:` declarations added to `tdd-patterns/SKILL.md` (test-file globs across JS/TS/Python/Ruby/Go/Rust) and `visual-verification/SKILL.md` (UI file extensions). Future Claude Code versions that respect the `paths:` field will scope auto-discovery for these skills to relevant file changes only, reducing context-budget pressure when many skills are loaded.

### compound-engineering vendor-or-document decision (gate 20)

**Decision: document, do not vendor.** The `visual-verification` skill's browser-tool cascade includes two entries from the `compound-engineering` plugin (`compound-engineering:test-browser`, `compound-engineering:agent-browser`) at fallback positions 4 and 5. The cascade gracefully handles their absence (Playwright MCP, Chrome DevTools MCP, and the CLI fallback are all viable for the production loop); vendoring would fork the behavior and create maintenance debt for code flow did not author. The `visual-verification/SKILL.md` "External dependency" section documents the rationale, the in-practice behavior (with/without compound-engineering installed), and the BLOCKED escalation path when no browser tools are available.

### `/flow:learn` integration

`commands/learn.md` Phase 5 (Promotion Workflow) now points at `bin/promote-proposal.sh` as the canonical promotion path, replacing the previous "Copy to plugins/flow/skills/learned/{name}/SKILL.md / Commit and create PR" manual instructions. Includes documentation of the `--dry-run` flag for validation without filesystem effects.

### Post-review hardening (PR #99 review pass)

Fixes surfaced by the pre-landing review:

- **Plugin version sync**: `plugins/flow/.claude-plugin/plugin.json` and the flow entry in `.claude-plugin/marketplace.json` bumped from `2.1.0` → `2.3.0` to match this CHANGELOG. The CLAUDE.md "Versioning" rule (bump both files on release) was missed when the 2.1.1/2.2.0/2.3.0 entries landed.
- **Schemas now ship inside the plugin payload.** Moved `tests/skills/<name>/input-schema.json` → `plugins/flow/schemas/<name>/input-schema.json` and updated `bin/validate-skill-input.sh` to resolve via `${CLAUDE_PLUGIN_ROOT}/schemas/...`. The previous `tests/skills/...` location was repo-only — end-users installing the marketplace plugin via Claude Code did not get the schemas, so any runtime call to the validator (per `references/skill-contracts.md`) would have failed with exit 2. Test fixtures (`valid-input.json`, `invalid-input.json`, `test.sh`) stay at repo level.
- **Concurrency lock on `bin/journal-record.sh`.** Two parallel writers (e.g. paired-reviewer dispatch under Path A) could both read the manifest, both append in-memory, and the second `rename` would clobber the first writer's append. Added a per-journal `flock` (with `shlock` fallback for macOS without coreutils, and a one-line warning when neither is present). Doc updated: "Idempotent and atomic" → "Append-only with atomic per-record writes" because re-running with identical args produces a duplicate `artifacts[]` entry by design (callers dedupe).
- **`bin/promote-proposal.sh` cleanup hardening.** Cleanup trap now registers BEFORE the `mkdir`/`cp`/python rewrite of the target SKILL.md, so a failure in those steps no longer leaves an orphan `plugins/flow/skills/learned/<name>/` in the working tree. Newline/CR in `--proposal` paths is rejected upfront; previously a path like `evil\nname` would fall through to the `sed` substitution at the end of the script (after `git push -u`), strand a remote branch with no PR, and leave `.bak` artifacts behind.
- **`journal.dir` cascade trimmed (security).** `bin/journal-record.sh`, `hooks/scripts/{session-end-learn,log-commits,log-file-changes}.sh` no longer read `journal.dir` from the repo-local sources `.claude/settings.flow.local.json` and `.claude/settings.flow.json`. After `gh pr checkout` of a hostile fork PR, those files would otherwise let an attacker redirect every hook write to an attacker-controlled path. User-global (`$HOME/.claude/settings.flow.json`) and plugin defaults are preserved — same defense pattern as `merge.markerTrust` and the `agentTeams` plugin pin in `review.md`.
- **JSON Schema regex portability.** `\Z` anchor (Python-only) replaced with `(?!\n)$` lookahead in `plugins/flow/schemas/holdout-validation/input-schema.json` and `tests/finding-schema/row-schema.json`. The lookahead form is portable across Python `re` and ECMA-262 validators (ajv, etc.), unblocking future use of the schemas in non-Python tooling. The two trailing-newline regression assertions (`tests/skills/holdout-validation/test.sh` and `tests/finding-schema/fixtures.json`'s `F1\n` invalid fixture) both still reject correctly.
- **`commands/merge.md` `$TRUST_REGEX` fix.** Replaced the dead reference (a leftover from PR #93 that produced "trusted authors ()" or aborted under `set -u`) with a `TRUST_LIST_DISPLAY` rendered from `$TRUST_LIST` via `jq -r 'join(",")'`.
- **`bin/flow-escalate.sh` numbered-list rendering + duplicate-option rejection.** Output is now a real Markdown numbered list (`1. ...`) rather than bullets with the user-supplied `<n>:` embedded as text — matches the docstring claim. Duplicate option numbers (`1: A;1: B`) are now rejected with a clear error rather than rendered ambiguously.

### Post-review hardening — cycle 2 (PR #99 `/flow:review`)

The first hardening pass left three sister sites still reading the unsafe cascade and a few ancillary issues. Cycle 2 closes them:

- **Cascade trim now covers all 7 consumers.** `commands/learn.md` (`journal.dir` + `learning.proposalDir`), `commands/explain.md` (`journal.dir`), and `agents/convention-checker.md` (`conventions.commitTypes`) were still reading `.claude/settings.flow.{local.,}json` despite executing inside Claude Code at command time after `gh pr checkout`. Trimmed to user-global + plugin only, matching the four `.sh` scripts. Without this, a fork PR could redirect proposal writes to `/tmp/attacker` (then have them picked up by `/flow:learn`) or relax `commitTypes` to `.*` defeating commit-message validation.
- **`bin/promote-proposal.sh` git commit reads from stdin via `git commit -F -`.** The previous `git commit -m "...$PROPOSAL..."` would have evaluated backticks or `$(...)` inside `$PROPOSAL` (a user-supplied path) at message-construction time. The earlier newline rejection covered LF/CR but not the substitution metacharacters; switching to stdin removes the risk by construction.
- **`bin/validate-skill-input.sh` charset-guards `$SKILL`.** `$SKILL` is interpolated directly into the schema path; combined with `jsonschema`'s default `$ref` resolver (which honors `file://` URLs), an unsanitized value like `../../etc/passwd` was a theoretical local-file-read primitive. Now rejects anything outside `^[a-z][a-z0-9-]*$` (same charset as `bin/promote-proposal.sh`'s `PROPOSAL_NAME`). Two new regression tests in `tests/skills/holdout-validation/test.sh` (path-traversal name, non-kebab-case name) — total assertions for that suite 7 → 9.
- **`bin/promote-proposal.sh` cleanup safety.** Pre-flight refuses when `$TARGET_DIR` exists with content (not just when `SKILL.md` exists). Without this, a contributor's half-finished hand-promotion (e.g., `references/foo.md` placed manually before adding `SKILL.md`) would be silently wiped by the cleanup trap's `rm -rf "$TARGET_DIR"` on a python rewrite failure.
- **`bin/journal-record.sh` lockfile symlink check.** Refuses `[ -L "$LOCKFILE" ]` upfront. `exec 9>"$LOCKFILE"` would otherwise truncate a symlink target chosen by an attacker (low severity since the journal directory is no longer attacker-controlled, but defense-in-depth).
- **Stale `\Z` anchor doc cleanup** in `tests/skills/holdout-validation/test.sh` (assertion label + comment) so the canonical anchor is the `(?!\n)$` lookahead everywhere.
- **Schema `$id` URIs corrected.** All three relocated schemas had `$id` URIs still pointing at `tests/skills/<name>/...`; updated to `plugins/flow/schemas/<name>/...`. JSON Schema Draft-07 treats `$id` as the canonical identifier — incorrect URIs would break `$ref` resolution if any tooling does cross-schema lookups.
- **CHANGELOG totals fixed.** Cycle-1 entry overcounted "21 trailing-newline regression assertions" — actual count is 2 (one in `tests/skills/holdout-validation/test.sh`, one in `tests/finding-schema/fixtures.json`'s `F1\n` invalid fixture). Updated.

### Verification

Test totals on this release: 77 assertions across `tests/issue-86/` (16), `tests/skills/{holdout-validation,criterion-verification-map,specification-capture}/` (21 — holdout-validation grew from 7 → 9 with the path-traversal regressions), `tests/finding-schema/` (14), `tests/status-parser/` (10), and `tests/journal-orchestration/` (16). All pass — including after the schema relocation, the `(?!\n)$` lookahead migration, the journal-record concurrency lock + symlink check, and the `validate-skill-input.sh` charset guard. The synthetic-issue end-to-end manifest journey via Claude Code's prompt layer is a manual integration check exercised by maintainers running `/flow:start` after the helper scripts ship.

## 2.2.0 (2026-05-06)

### New Reference Documents

- `references/finding-schema.md` — canonical 6-field reviewer output row (`ID | Category | Location | Problem | Suggested Fix | Confidence`) plus the marker-only `status` and `disposition` fields. Compatible with the existing `FLOW_REVIEW_CYCLE` 7-field marker grammar.
- `references/escalation-format.md` — canonical six-field Proactive-Autonomy structure (Situation, What I tried, Options, Recommendation, Time sensitivity, Risk) delivered via `AskUserQuestion`. Implementation field names adopted as canonical because they were already 4× consistent across commands.
- `references/evidence-bundle-format.md` — canonical markdown shape `verdict-judge` consumes. Per-criterion sections with mandatory `### Does NOT promise` plus three completeness subsections (`### What was NOT tested`, `### Known limitations of this evidence`, `### Negative/adversarial cases covered`); `none` is a valid positive-statement answer; bare blank triggers auto-FAIL.

### New Skills

- `specification-capture` — owns the lifecycle for non-goals, failure modes, and interface contracts. Reads journal first, extracts from issue body, prompts for missing elements via `AskUserQuestion` with the canonical six-field structure, writes to `.decisions/issue-{N}.md` under a `## Specification` heading. Invoked by `/flow:start` Phase 1, `/flow:design` Phase 1, and `/flow:brainstorm` Phase 1.
- `visual-verification` — extracted from `runtime-verification` (which dropped from 399 → 242 lines). Owns the screenshot-analyze-verify loop, browser-tool priority cascade (Playwright MCP → Chrome DevTools MCP → CLI → external skill fallback), responsive viewport checks, and the result vocabulary (PASS / FAIL / SKIP / SKIP_WARN / SKIP_USER_APPROVED / MANUAL / BLOCKED). Total skill count is now 24 (3 foundation + 21 domain).

### Migrations

- All 4 reviewer agents (`code-reviewer`, `security-reviewer`, `error-handler-inspector`, `integration-verifier`) emit findings using the canonical schema in `references/finding-schema.md`. The previous ASSERTION/EVIDENCE/VERIFIED-vs-table inconsistency between agents is resolved. Reviewer ID prefixes (`F`, `SEC-`, `ERR-`, `INT-`) make finding provenance recoverable from the ID alone.
- `agents/verdict-judge.md` Step 1 cites `references/evidence-bundle-format.md` as the input contract. Auto-FAIL rules now reference the exact canonical headings; producer non-conformance surfaces as a producer bug rather than an opaque judge failure.
- `commands/start.md` Phase 4 step 5 produces evidence bundles in the canonical format; the journal-write-to-judge-input chain is now traceable through one document.
- All 6 escalating commands (`start`, `pr`, `merge`, `commit`, `address`, `resolve`) cite `references/escalation-format.md` in their References section. Situation-specific escalation prose stays in the commands; the structural contract is canonical.
- `commands/start.md` Phase 1 replaces ~30 lines of inline specification-capture prose with `Skill(specification-capture)` invocation; `commands/design.md` and `commands/brainstorm.md` invoke the same skill so the journal is the single source of truth across all three commands.
- `commands/start.md` Phase 4 and `commands/pr.md` Phase 4 invoke `Skill(visual-verification)` in parallel with `Skill(runtime-verification)` when the diff is UI-relevant. `agents/integration-verifier.md` Step 6 delegates the screenshot-analyze-verify loop to the new skill rather than re-implementing it inline.

### Documentation

- `commands/review.md` Path A note + `skills/team-coordination/SKILL.md` Phase 3 + `skills/holdout-validation/SKILL.md` Integration Points: the holdout-validation challenge-round exclusion is now documented as a principled design decision (objective claim verification vs subjective judgment) rather than a tooling workaround. Holdout findings emit with `consensus` (both lenses raised the finding) or `unchallenged` (one lens only — itself a useful divergence signal); they NEVER carry `validated` / `refined` / `kept` because those are challenge-round outputs.
- README adds a "Canonical Reference Documents" section listing the three new docs plus the existing reference library, so contributors can find the source of truth without grepping.
- README skill-library count updated from 22 to 24 (architecture diagram).

## 2.1.1 (2026-05-06)

### Documentation

- All 22 skill descriptions rewritten to lead with the artifact, name 2-3 specific triggers, and add either "MUST be consulted because…" (verification, safety, and gate-enforcing skills) or "Proactively suggest when…" (creative and exploratory skills) — bringing the active skills into the same trigger pattern that drove `holdout-validation`'s invocation rate from ~0% to the high 90s.
- README adds a Hook Compatibility table noting that `TaskCompleted` and `TeammateIdle` hooks require Claude Code v2.1.33+ and treat their JSON payloads as best-effort because the schema is undocumented.
- `code-review-methodology` skill now cites `references/test-review-checklist.md` for the Tests facet.
- `pr-lifecycle` skill now cites `references/gate-configuration.md#quality-gates` for the canonical map of the eight gates flow enforces.
- `merge.markerTrust` is now documented in `schema.json` with an inline rationale explaining the security-driven decision to read it from `plugins/flow/settings.json` only (no settings cascade).

### Bug Fixes

- `/flow:address` Phase 4 fan-out now explicitly enumerates all 5 reviewer agents (added `security-reviewer`); previously claimed pr.md parity by reference but the dispatch block only listed 4 agents — security review was silently skipped on every re-review.
- `session-end-learn.sh` no longer false-matches today's date string when it appears inside journal content (e.g. due-date references in older entries). Switched from `grep -q "$TODAY"` to `find -mtime -1` for portable, content-agnostic detection of recent journal activity.
- Removed unused `journal.sensitivityDefault` setting from `settings.json` and `schema.json` (no consumer existed). Related references in `gate-configuration.md` and `decision-journal-schema.md` updated.

## 2.1.0 (2026-05-05)

### New Features

- `/flow:address` re-review now matches `/flow:pr` fan-out parity, running the full reviewer set on resolved feedback (#64, #75)
- `/flow:pr` and `/flow:review` default fan-out now wires `security-reviewer` for security-aware coverage on every PR (#61, #70)

### Bug Fixes

- `/flow:pr` review depth brought to parity with `/flow:review` (#62, #71)
- Skill bodies that duplicated command bash are now deduped; commands stay the canonical source (#65, #67)
- Three inaccurate gate descriptions in `gate-configuration.md` corrected (#60, #69)
- `schema.json` defaults synced with post-v2.0 settings (#59, #68)

### Documentation

- Required Skills vs `Skill()` invocation convention documented (#66, #74)
- Settings cascade direction unified across all docs (#63, #73)
- Three source-of-truth drifts in README and `criterion-verification-map` corrected (#58, #72)
- Flow plugin team workshop materials added (#57)

## 2.0.1 (2026-05-05)

### Bug Fixes

- `log-commits.sh` PostToolUse hook no longer leaves the worktree permanently dirty. Two idempotency guards added: skip when the last commit message starts with `chore(decisions):`, and skip when the most recent commit only modified the journal file itself. The `auto-log → commit → auto-log` infinite append loop is now bounded. (#56, closes #55)

## 2.0.0 (2026-04-16)

### Breaking Changes

- `tddMode` default changed from `suggest` to `enforce`
- `verdict.requireAllPass` default changed from `false` to `true`
- P3 findings are no longer deferrable -- fix in-PR or file a Proactive-Autonomy escalation
- Pre-existing findings in touched files keep natural priority (no longer capped at P3)
- Merge gate now blocks on unresolved findings in FLOW_RESOLUTION_CYCLE markers
- "DEFERRED" markers renamed to "ESCALATED" in FLOW_RESOLUTION_CYCLE comments

### New Features

- Spec Validation Gate: acceptance criteria must have concrete automated verification commands before PLAN phase
- Specification capture: non-goals, failure modes, and interface contracts required in EXPLORE phase
- Stranger Test: mandatory end-of-PLAN gate ensuring zero-context executability
- Per-task verification gate: tests must pass and evidence captured before TaskUpdate(completed)
- Holdout-validation skill: cross-references agent self-review claims against actual file state
- Evidence bundle completeness: "What was NOT tested", "Known limitations", "Negative/adversarial cases" required per criterion
- Missing-criterion scan: verdict-judge Step 1 checks every criterion has evidence before evaluation
- Proactive Autonomy with Prepared Escalation: codified six-field structure, anti-pattern list
- Finding-ledger merge gate: blocks merge on non-empty ESCALATED array

### Migration Guide

- To keep old TDD behavior: set `testing.tddMode: "suggest"` and `testing.tddModeOptOut: true` in settings.json
- To keep old verdict behavior: set `verdict.requireAllPass: false` in settings.json
- "DEFERRED" markers renamed to "ESCALATED" in FLOW_RESOLUTION_CYCLE comments
