# Changelog

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
