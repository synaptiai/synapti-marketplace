# Changelog

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
