# Conventions Worksheet (live during session)

Project this on screen during section 6. **Don't advance past a row until it has an answer** — even if the answer is "default, revisit in 30 days."

After the session, copy decisions into `CONVENTIONS-DECIDED.md` and open a follow-up PR for `.claude/settings.flow.json` if any non-default values were chosen.

Defaults are pulled from `plugins/flow/settings.json`.

---

| # | Decision | Default | Options | Lands in | Decision |
|---|----------|---------|---------|----------|----------|
| 1 | TDD mode | `enforce` | `enforce` / `suggest` / `off` | `settings.flow.json` → `testing.tddMode` | ☐ default ☐ change to: ____ |
| 2 | Verdict requires all pass | `true` | `true` / `false` | `settings.flow.json` → `verdict.requireAllPass` | ☐ default ☐ change to: ____ |
| 3 | Agent teams (adversarial review) | `false` | `false` / `true` (+ env `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`) | `settings.flow.json` → `agentTeams` | ☐ default ☐ change to: ____ |
| 4 | Branch naming patterns | `feature/issue-{N}-{desc}`, `fix/issue-{N}-{desc}`, `docs/issue-{N}-{desc}` | keep / adjust prefixes / add categories | `settings.flow.json` → `conventions.branchPatterns` | ☐ default ☐ change to: ____ |
| 5 | Commit type vocabulary | 12 types: `feat, fix, docs, style, refactor, test, chore, perf, ci, build, revert, improve` | keep / drop unused / add | `settings.flow.json` → `conventions.commitTypes` | ☐ default ☐ change to: ____ |
| 6 | Journal sensitivity default | `public` | `public` / `internal` | `CONVENTIONS-DECIDED.md` (policy) — flow has no setting for this; see note | ☐ default ☐ change to: ____ |
| 7 | Tier overrides | push=journal, prCreate=journal, issueAssign=journal, issueCreate=journal, merge=confirm, release=confirm | keep / promote any to `confirm` (cannot demote) | `settings.flow.json` → `tiers` (see note) | ☐ default ☐ change to: ____ |
| 8 | Spec-free label list | `["documentation", "chore"]` | keep / add labels / remove | `settings.flow.json` → `specFirst.allowSpecFreeLabels` | ☐ default ☐ change to: ____ |
| 9 | Reviewer routing (policy) | n/a | round-robin / by area / by author preference / least-recently-reviewed | `CONVENTIONS-DECIDED.md` (policy) | choice: ____ |
| 10 | Learning-loop cadence (policy) | n/a | owner of `/flow:learn` + cadence + proposal triage | `CONVENTIONS-DECIDED.md` (policy) | owner: ____ cadence: ____ |

**Notes on what flow does today**

- Row 6: flow has no setting for the journal sensitivity default. Each entry declares `Sensitivity: public` or `internal`; an entry without the line is `public`. `internal` entries appear in PR bodies only as "[Internal decision]". Whatever the team chooses here is a writing policy, not a config value.
- Row 7: the `tiers` keys are accepted in settings, but no flow command or hook reads them. `/flow:merge` and `/flow:release` ask for confirmation whatever the setting says, and every other command applies the tier listed in its own Tier Classification section. "Cannot demote" is documented policy, not something the settings loader enforces.
- Row 10: `/flow:learn` reads session transcripts as well as the journal, and proposes review exceptions as well as skills. Promoting a proposal is done with `bin/promote-proposal.sh`, which opens a draft PR.

---

## Implicit 11th decision (surface if energy allows)

How do we handle disagreement on a P3?

**What flow does**: every finding, P3 included, is fixed in the PR, and deciding what to do with a finding is never a reason for a six-field escalation. An author who thinks a finding is wrong pushes back in `/flow:address` on one of three grounds (factually incorrect with a `file:line`, breaks a named test, or contradicts a quoted CLAUDE.md rule). The finding is recorded as DISPUTED and still blocks `/flow:merge` until it is resolved. Repeated dismissals can become a review exception through `/flow:learn`.

**Recommended answer**: use flow's pushback path above rather than an escalation.

☐ adopt recommendation ☐ alternative: ____

---

## Forcing function

The facilitator does not advance to the next decision until the current row has a checkbox marked.

90 seconds per row. Section 6 is 15 minutes — that's 90 seconds × 10 rows = 15 min, exactly. No buffer. Section 6 is a vote, not a debate.

If a decision genuinely needs more discussion: pick the default, mark "revisit in 30 days," move on. Don't burn the whole session on one row.
