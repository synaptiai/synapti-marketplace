---
issue: 178
created: '2026-09-14T20:47:21Z'
artifacts:
- type: specification
  captured_at: '2026-09-14T20:47:21Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: goal-created
  captured_at: '2026-09-14T20:51:10Z'
  goal_id: issue-178
  source: start
- type: goal-evaluation
  captured_at: '2026-09-14T21:58:48Z'
  goal_id: issue-178
  result: achieved
  evidence_bundle: .flow/runs/2026-09-14T215033Z-issue-178
  failures: none
- type: review-cycle
  captured_at: '2026-09-14T22:01:24Z'
  cycle: 1
  path: B
  findings_count: 6
  pr: 204
---
# Issue #178 — scaffold overwrites non-frontmatter files and reports them as CREATED, not REPAIRED

## Specification

_Captured by specification-capture skill on 2026-09-14. Source: mixed (extracted-from-issue + drafted from codebase read)._

### Non-goals

- Not reconsidering whether "no frontmatter fence" is the right damage test at all (the issue's own point 3 is explicitly speculative "consider" language) — this fix keeps the existing fence-based damage detection and only fixes its counter visibility and documentation.
- Not adding a `.bak`-move-aside behavior for non-empty, non-frontmatter files — a different, larger design change the issue only floats as a possibility, not a requirement.
- Not adding a `--json` output mode — `dossier-scaffold.sh` has no JSON mode today, and this fix stays within the existing plain-text `KEY=value` + `ACTIONS` contract.
- Not changing the `DEST_INTACT` / empty-file detection logic (introduced in the 1.0.2 fix for truncated files) — only the reporting of what happens after a file is judged damaged.

**Resolved during review (was: accepted residual risk)** — the README's failure branches originally incremented `SCAFFOLD_FAILED` without a matching `FAILED README.md (...)` `ACTIONS` line. Initially filed as a genuinely pre-existing, untouched-by-this-diff follow-up (issue #203), but a second review cycle added a new symlink guard directly above that same block (closing a directory-level symlink bypass, and a template-source symlink gap — see risk-map addendum below), which brought the block back into this PR's active scope. Fixed in-PR instead of carried forward: all three README failure branches (symlink, missing template, copy failed) now emit a matching `ACTIONS` line and stderr diagnostic. Issue #203 remains open as a historical record but is closed by this PR's diff.

**Accepted residual risk** — `dossier-scaffold.sh`'s template-directory resolution falls back to a bare CWD-relative path (`plugins/dossier/templates/package`) when neither `CLAUDE_PLUGIN_ROOT` nor a `$SCRIPT_DIR`-relative candidate resolves. Confirmed genuinely pre-existing (predates PR #201/issue #176) and untouched by this PR's diff — not worsened in kind. Tracked as a follow-up: issue #205.

### Failure modes

- **Timeouts** — none; local filesystem copy operations only, no network.
- **Partial failures** — a single file's copy failure is already handled (`FAILED` counter, `FAILED <path>` action line); this fix must not change that path, only the REPAIRED/CREATED distinction for successful copies.
- **Invalid input** — n/a; the script's existing argument parsing is unchanged.
- **Missing context** — n/a; no new external dependency or config is introduced.

### Interface contracts

- CLI contract unchanged: `dossier-scaffold.sh [--output-root <path>] [--dry-run]`, exit codes unchanged (0 success, 1 on any `FAILED` count > 0).
- Plain-text summary gains one new additive line: `SCAFFOLD_REPAIRED=<n>`, placed alongside the existing `SCAFFOLD_CREATED`/`SCAFFOLD_SKIPPED`/`SCAFFOLD_FAILED` lines — does not remove or reorder existing `SCAFFOLD_*` lines.
- A repaired file's `ACTIONS` output changes from two lines (`REPAIRED <path>` then `CREATED <path>`) to exactly one (`REPAIRED <path>`) — existing consumers asserting `CREATED=23` on a *clean* first scaffold (no repairs) are unaffected, since `CREATED` only changes for paths that were actually repaired.
- New stderr-only diagnostic on the repair path: names the file and the byte count of the content it replaced. Not part of the stdout `KEY=value` contract, so does not affect existing stdout-parsing consumers.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| REPAIRED/CREATED fallthrough | the fix adds a `SCAFFOLD_REPAIRED` counter but forgets to also suppress the `CREATED` increment/line for the same path, so both counters now count the same repair | fixture: a non-frontmatter-fenced existing file at a canonical path, run once → right: `SCAFFOLD_REPAIRED=1`, `SCAFFOLD_CREATED=<n minus this file>`, exactly one `REPAIRED <path>` line and no `CREATED <path>` line for it; wrong: both counters increment or both action lines appear |
| clean-first-scaffold regression | the fix accidentally changes CREATED counting for files that were never damaged (a true first-run creation), conflating "created because absent" with "created because repaired" | fixture: run scaffold into an empty output root (no pre-existing files at all) → right: `SCAFFOLD_REPAIRED=0`, `SCAFFOLD_CREATED=23`, no `REPAIRED` lines; wrong: `SCAFFOLD_REPAIRED` non-zero or `SCAFFOLD_CREATED` under 23 |
| SKIPPED path untouched | the fix's changes to the DEST_INTACT branch accidentally also touch the "file starts with `---`, is skipped" path | fixture: a properly frontmatter-fenced existing file at a canonical path → right: unchanged, `SCAFFOLD_SKIPPED=1`, byte-identical file after run, no REPAIRED/CREATED line for it; wrong: it gets repaired or re-created |
| header-comment correction scope | correcting the "never overwritten" claim at the script header also needs to land in the doc-package-contract skill's own copy of the same claim, or the two go out of sync again | grep both files for the exact old unqualified phrasing after the fix → right: neither file contains it; wrong: only one was corrected |

<!-- auto-log: 2026-09-14 22:47 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-178.md -->

<!-- auto-log: 2026-09-14 22:51 Write /tmp/issue-178.goal.yaml -->

<!-- auto-log: 2026-09-14 22:51 Write /tmp/issue-178-lifecycle-active.yaml -->

<!-- auto-log: 2026-09-14 22:54 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-09-14 22:54 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-09-14 22:56 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scaffold.sh -->

<!-- auto-log: 2026-09-14 22:56 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scaffold.sh -->

<!-- auto-log: 2026-09-14 22:56 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scaffold.sh -->

<!-- auto-log: 2026-09-14 22:56 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scaffold.sh -->

<!-- auto-log: 2026-09-14 22:56 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scaffold.sh -->

<!-- auto-log: 2026-09-14 22:56 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/skills/doc-package-contract/SKILL.md -->

<!-- auto-log: 2026-09-14 23:00 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-09-14 23:00 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/CHANGELOG.md -->

<!-- auto-log: 2026-09-14 23:13 commit "fix(dossier): scaffold no longer double-counts a repaired file as CREATED" -->

<!-- auto-log: 2026-09-14 23:18 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scaffold.sh -->

<!-- auto-log: 2026-09-14 23:18 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-09-14 23:19 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scaffold.sh -->

<!-- auto-log: 2026-09-14 23:19 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-09-14 23:19 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-error-handler-inspector/project_dossier_status_line_before_outcome_known.md -->

<!-- auto-log: 2026-09-14 23:19 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-error-handler-inspector/MEMORY.md -->

<!-- auto-log: 2026-09-14 23:20 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-09-14 23:21 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scaffold.sh -->

<!-- auto-log: 2026-09-14 23:28 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-09-14 23:28 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scaffold.sh -->

<!-- auto-log: 2026-09-14 23:29 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scaffold.sh -->

<!-- auto-log: 2026-09-14 23:30 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-09-14 23:30 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scaffold.sh -->

<!-- auto-log: 2026-09-14 23:30 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scaffold.sh -->

<!-- auto-log: 2026-09-14 23:37 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/CHANGELOG.md -->

<!-- auto-log: 2026-09-14 23:37 commit "fix(dossier): scaffold refuses symlinks/non-files, never double-reports a failed repair" -->

<!-- auto-log: 2026-09-14 23:38 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scaffold.sh -->

<!-- auto-log: 2026-09-14 23:44 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/CHANGELOG.md -->

<!-- auto-log: 2026-09-14 23:44 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-178.md -->

<!-- auto-log: 2026-09-14 23:44 commit "fix(dossier): stop a TOCTOU race from leaking a redirection error to stderr" -->

<!-- auto-log: 2026-09-15 00:01 Write /tmp/pr-178-body.md -->

<!-- auto-log: 2026-09-15 00:16 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scaffold.sh -->

<!-- auto-log: 2026-09-15 00:16 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scaffold.sh -->

<!-- auto-log: 2026-09-15 00:16 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scaffold.sh -->

<!-- auto-log: 2026-09-15 00:17 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-09-15 00:17 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-09-15 00:19 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scaffold.sh -->

<!-- auto-log: 2026-09-15 00:19 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-09-15 00:26 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scaffold.sh -->

<!-- auto-log: 2026-09-15 00:26 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scaffold.sh -->

<!-- auto-log: 2026-09-15 00:26 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-scaffold.sh -->

<!-- auto-log: 2026-09-15 00:27 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-09-15 00:27 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/bin-scripts.test.sh -->

<!-- auto-log: 2026-09-15 00:28 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/CHANGELOG.md -->

<!-- auto-log: 2026-09-15 00:28 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-178.md -->
