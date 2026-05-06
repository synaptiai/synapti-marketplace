# Changelog

## 2.3.0 (2026-05-06)

Structural-enforcement landing. Closes Approach C of the comprehensive review by introducing four `bin/` helper scripts, three new repo-level test suites with 41 passing assertions, machine-checkable input contracts for three skills, a YAML frontmatter manifest schema for the decision journal, the `/flow:learn` promotion path that closes the learning loop, tier classification tables on every command, and the formal vendor-or-document decision for the `compound-engineering` visual-verification dependency. After Landing 3, every plugin boundary has either a runnable test fixture or an explicit policy document; drift becomes detectable at PR-review time rather than at runtime.

### New helper scripts (`plugins/flow/bin/`)

- `flow-escalate.sh` — formats canonical six-field Proactive-Autonomy escalations (Situation, What I tried, Options, Recommendation, Time sensitivity, Risk) per `references/escalation-format.md`. Output is a markdown body suitable for `AskUserQuestion`. Validates required fields and option grammar (`<n>: <text>`); exits 0/1/2 with clear stderr.
- `validate-skill-input.sh` — validates a skill's input payload against its JSON Schema at `tests/skills/<name>/input-schema.json`. Tries `import jsonschema` for full Draft-07 validation; falls back to a shape-check (required, types, enums, patterns, minItems, minLength) implemented in the standard library so the script works on any Python 3.x install. Exits 0 (valid), 1 (validation failure with path + reason), or 2 (infrastructure error).
- `journal-record.sh` — atomically updates the YAML frontmatter manifest in `.decisions/issue-{N}.md` with a new artifact entry (specification, stranger-test, review-cycle, dropped-finding, design-decision, brainstorm-decision, verdict, escalation-resolved). Idempotent across runs; preserves legacy bodies when the journal lacks a manifest. Atomic via temp file + rename.
- `promote-proposal.sh` — promotes a `/flow:learn` proposal to an active skill at `plugins/flow/skills/learned/{name}/SKILL.md` via a **draft** PR. Validates frontmatter (required fields, status=proposal, kebab-case name) and body sections (`## Pattern Detected`, `## Knowledge`, `## Evidence`, `## Verification`, `## Promotion Checklist`). Tier 2 by design: opens a draft PR and never marks it ready or merges. `--dry-run` flag for non-mutating validation.

### New repo-level test suites

- `tests/skills/holdout-validation/`, `tests/skills/criterion-verification-map/`, `tests/skills/specification-capture/` — six assertions per skill (valid input, invalid input, missing required, non-JSON input, edge-case validation). 18 total; all pass.
- `tests/finding-schema/` — 13 assertions (7 valid fixtures + 6 invalid) covering the canonical finding row shape (ID grammar, priority/confidence/disposition enums, required fields). Catches drift between `references/finding-schema.md` and the actual rows reviewer agents emit.
- `tests/status-parser/` — 10 assertions verifying that `status.md`'s ledger parser stays in lockstep with `merge.md`'s parser across legacy 5-field, extended 7-field, mixed-cycles, and review+resolution markers. Includes hostile-ID and malformed-priority rejection tests that mirror the production ID grammar.

### New canonical reference documents

- `references/skill-contracts.md` — explains what JSON Schema input contracts exist, the validator strategy (jsonschema if installed, shape-check fallback), the test-fixture convention, and how to add a contract for a new skill.
- `references/decision-journal-schema.md` — extended with the **YAML frontmatter manifest schema** (Landing 3). Documents the required top-level fields, the artifact-type vocabulary (specification, stranger-test, review-cycle, dropped-finding, etc.), per-type required metadata, compatibility with the legacy structured-entry format, and the tradeoff between YAML and JSON for the manifest.

### Tier classification (gate 19 of the plan)

Every command in `plugins/flow/commands/` now carries a `## Tier Classification` section at the bottom listing the actions it takes and the tier for each (1 = autonomous, 2 = journaled, 3 = confirm). Coverage: 17/17 commands. `grep -L "^## Tier Classification" plugins/flow/commands/*.md` returns nothing.

### Frontmatter sweeps

- `disable-model-invocation: true` added to `pr-lifecycle/SKILL.md` and `preflight-checks/SKILL.md` (matching the existing flag on `merge-and-release/SKILL.md` and `team-coordination/SKILL.md`). All four reference-only skills now disable autonomous invocation by the model — they are policy documents consumed by commands, not skills the orchestrator invokes on its own.
- `paths:` declarations added to `tdd-patterns/SKILL.md` (test-file globs across JS/TS/Python/Ruby/Go/Rust) and `visual-verification/SKILL.md` (UI file extensions). Future Claude Code versions that respect the `paths:` field will scope auto-discovery for these skills to relevant file changes only, reducing context-budget pressure when many skills are loaded.

### compound-engineering vendor-or-document decision (gate 20)

**Decision: document, do not vendor.** The `visual-verification` skill's browser-tool cascade includes two entries from the `compound-engineering` plugin (`compound-engineering:test-browser`, `compound-engineering:agent-browser`) at fallback positions 4 and 5. The cascade gracefully handles their absence (Playwright MCP, Chrome DevTools MCP, and the CLI fallback are all viable for the production loop); vendoring would fork the behavior and create maintenance debt for code flow did not author. The `visual-verification/SKILL.md` "External dependency" section documents the rationale, the in-practice behavior (with/without compound-engineering installed), and the BLOCKED escalation path when no browser tools are available.

### `/flow:learn` integration

`commands/learn.md` Phase 5 (Promotion Workflow) now points at `bin/promote-proposal.sh` as the canonical promotion path, replacing the previous "Copy to plugins/flow/skills/learned/{name}/SKILL.md / Commit and create PR" manual instructions. Includes documentation of the `--dry-run` flag for validation without filesystem effects.

### Verification

All Landing 3 verification gates from the plan (13–21) pass:

| Gate | Result |
|---|---|
| 13. `bin/validate-skill-input.sh` accepts valid input + rejects malformed | PASS |
| 14. All three `tests/skills/<name>/test.sh` exit 0 | PASS (18/18 assertions) |
| 15. `tests/finding-schema/validate.sh` exits 0 | PASS (13/13) |
| 16. `tests/status-parser/test.sh` exits 0 | PASS (10/10) |
| 18. `bin/promote-proposal.sh --dry-run` smoke test exits 0 | PASS |
| 19. Every command has `## Tier Classification` | PASS (17/17) |
| 20. `compound-engineering` decision documented | PASS |
| 21. Full regression (issue-86 + 3 skill IO + finding-schema + status-parser) | PASS (16 + 18 + 13 + 10 = 57 assertions) |

Gate 17 (synthetic issue end-to-end with manifest in journal) is a manual integration test — the helper scripts are unit-tested above; the end-to-end journey requires a real GitHub issue and is exercised by maintainers running `/flow:start` in their own work after this PR lands.

## 2.2.0 (2026-05-06)

Vision-alignment landing. Closes the structural P1 gaps surfaced by the comprehensive review: reviewer output fragmentation, verdict-judge contract opacity, escalation field-name drift, specification-capture lifecycle drift, runtime-verification scope creep, and the `/flow:review` Path A holdout asymmetry. Three new canonical reference documents and one new skill (specification-capture) plus one extracted skill (visual-verification) make the plugin's cross-cutting contracts auditable as published documents instead of inline prose.

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
