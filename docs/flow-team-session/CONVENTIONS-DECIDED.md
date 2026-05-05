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
| 6 | `journal.sensitivityDefault` | _____ | |
| 7 | `tiers` | _____ | |
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

**Proposal triage**: who reviews `~/.claude/flow-proposals/` and decides what gets promoted to `plugins/flow/skills/learned/`? ____

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
