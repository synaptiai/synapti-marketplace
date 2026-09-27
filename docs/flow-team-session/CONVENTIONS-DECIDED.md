# Conventions Decided

**Status**: TEMPLATE — fill in during the session, then commit.

**Session date**: ____
**Facilitator**: ____
**Attendees** (engineering / PM / design): ____

This is the source of truth for the team's flow plugin overrides. Settings decisions land in `.claude/settings.flow.json` (committed). Policy decisions stay here — the plugin doesn't enforce them, humans do.

---

## Settings decisions

| # | Setting | Value | Notes |
|---|---------|-------|-------|
| 1 | `testing.tddMode` | _____ | |
| 2 | `verdict.requireAllPass` | _____ | |
| 3 | `agentTeams` | _____ | |
| 4 | `conventions.branchPatterns` | _____ | |
| 5 | `conventions.commitTypes` | _____ | |
| 6 | `journal.sensitivityDefault` | _____ | Flow has no such setting: each journal entry declares `Sensitivity:`, and an entry without the line is `public`. Record the choice here as a writing policy. |
| 7 | `tiers` | _____ | No flow command or hook reads these keys; `/flow:merge` and `/flow:release` always ask for confirmation. |
| 8 | `specFirst.allowSpecFreeLabels` | _____ | |

If any value differs from `plugins/flow/settings.json` defaults, file a follow-up PR adding the override to `.claude/settings.flow.json` (committed) within one week.

---

## Policy decisions

### 9. Reviewer routing

**Approach**: ____

**Owner**: ____

**Examples / clarifications**:

- ____

### 10. Learning-loop cadence

**Owner of `/flow:learn` runs**: ____

**Cadence**: ____ (e.g. monthly, post-project-ship, after every 10 issues)

**Proposal triage**: who reviews `~/.claude/flow-proposals/` and decides what gets promoted — skill proposals to `plugins/flow/skills/learned/`, review-exception proposals to `.flow/review-exceptions.md`? ____

### 11. P3 disagreement (if surfaced)

**Approach**: ____

---

## Revisit dates

| Decision | Revisit by | Trigger |
|----------|-----------|---------|
| ____ | ____ | ____ |

---

## Sign-off

By committing this file, attendees confirm: these are the conventions our team will follow until the next revisit date. Disagreements get filed as issues, not silently ignored.

**Committed by**: ____
**Date**: ____
