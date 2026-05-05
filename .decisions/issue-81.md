# Decision Journal — Issue #81

**Title**: fix(verdict-judge): tighten tool budget to Read-only
**Branch**: fix/issue-81-verdict-judge-read-only
**Started**: 2026-05-06

## Specification

### Non-goals
- Don't change the verdict-judge agent's prompt body (Steps 1-3 unchanged).
- Don't modify the agent's inputs (acceptance criteria + evidence bundle + holdout output) or outputs (markdown verdict table).
- Don't change the holdout-validation skill or any caller of verdict-judge.
- Don't touch slide content describing verdict-judge tool budget — slides-v2 corrections are tracked separately.

### Failure modes
- **If Phase 4 verdict-judge fails due to missing Bash/Grep**: fix-forward by reverting `tools:` to the prior value AND reframing this issue per AC4 toward a slide-only correction. Per the journal protocol, record the failure mode and the resolution path.
- **Markdown/config-only change otherwise**: no runtime failure modes (no timeouts, no partial failures, no invalid input contract).

### Interface contracts
- Agent frontmatter is YAML with leading and trailing `---`.
- `tools:` field is a comma-separated list of tool name strings (no brackets, no quotes around names).
- Agent identity (`name`, `description`), behavior (`model: inherit`, `memory: none`), and required skills (`skills: evidence-based-development`) are unchanged.

## Spec Validation Gate

| # | Acceptance Criterion | Verification Command | Gate Status |
|---|---|---|---|
| 1 | Frontmatter `tools:` lists only `Read` | `grep "^tools:" plugins/flow/agents/verdict-judge.md` returns `tools: Read` | PASS |
| 2 | E2E run produces valid coverage scan + verdict table from verdict-judge with no missing-tool errors | Phase 4 of this workflow dispatches verdict-judge with the new tool budget; output is the test | PASS (self-bootstrapping) |
| 3 | No caller requires Bash/Grep from verdict-judge | `git grep verdict-judge plugins/flow/` returns only references describing isolation; verified no caller passes Bash commands | PASS |
| 4 | Contingent: if Phase 4 surfaces a Bash/Grep dependency, reframe | Activates only if AC2 fails; otherwise N/A | PASS (contingent) |

All ACs PASS — proceeding to PLAN.

## Stranger Test

A zero-context agent could execute the plan: edit one frontmatter line in a single file, verify with one grep command, then run the existing /flow:start Phase 4 to confirm the verdict-judge still works. **PASS**.

## Atomic task

Single change: edit `plugins/flow/agents/verdict-judge.md` line 5 from `tools: Read, Bash, Grep` to `tools: Read`. Verification = grep + Phase 4 verdict-judge dispatch (self-bootstrapping E2E).

<!-- auto-log: 2026-05-06 00:00 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-81.md -->

<!-- auto-log: 2026-05-06 00:00 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/agents/verdict-judge.md -->
