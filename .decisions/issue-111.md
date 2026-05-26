---
issue: 111
created: '2026-05-26T12:00:00Z'
artifacts:
- type: plan
  captured_at: '2026-05-26T12:00:00Z'
  by: flow-start-interview
  mode: lock-the-plan-only
  status: awaiting-implementation
- type: review-cycle
  captured_at: '2026-05-26T13:14:59Z'
  cycle: 1
  path: B
  findings_count: 1
  pr: 123
---
# Issue #111 — v3.1 UX layer (invisible-by-default runtime)

**Session mode:** interview-driven planning. Deliverable is this locked plan; **no code this
session**. Implementation happens in a follow-up `/flow:start 111`.

**State (audited against repo source, post-#114):** AC-3 shipped in #114. 6 ACs remain:
AC-1, AC-2, AC-4, AC-5, AC-6, AC-7. Full plugin suite green at 840 tests today; every step
below must keep it green.

**Codebase facts established this session (corrections to the issue):**
- Command count = **23** (`commands/*.md`, all with valid frontmatter). README says `(17)` and
  lists 17, omitting the 6 runtime commands.
- `FILE_COUNT_FLOOR` in `tests/command-frontmatter.test.sh:26` is **15** (not 17), with a stale
  "17 as of this writing" comment at `:23`.
- Goal schema: ACs require `id, text, status`; `verification_command` is **optional**
  (`schemas/v1/goal.schema.json:104`). "Verifiable AC" = AC with a non-empty `verification_command`.
- `flow-active-goal.sh --ac-summary` emits `id|status|evidence_ref|last_result` — it does **not**
  expose a verifiable-AC count today.
- `cascade-resolve.sh` passes any jq expression through (`:88`) — compound `if/elif` exprs work but
  are **untested** (`tests/cascade-resolve.test.sh` only exercises `.journal.dir // empty`).
- A live active goal already exists in the repo: `.flow/goals/issue-120.goal.yaml`. Under the
  *current* `flow-active-goal.sh`, creating a second active goal would trip exit 3 (the AC-4 bug, live).

---

## Decisions (locked this session)

| # | Decision | Resolution | Rationale |
|---|----------|-----------|-----------|
| D0 | Session scope | **Lock the plan only** | Implement in a follow-up session. |
| D-A2 | `auto` predicate when spec-free-labeled but has verifiable ACs | **Verifiable ACs win** | Rule collapses to "create iff ≥1 AC has a `verification_command`." Spec-free label is purely the upstream Spec-Gate relaxation. #111 itself (documentation-labeled, 7 verifiable ACs) → gets a goal. No silent loss of tracking. |
| D-A1 | AC-1 settings migration mechanism | **Compound jq, `else null`** + `--default auto` | `.flow.goals.goalCreation // (if .flow.goals.requireGoalForStart == true then "always" elif .flow.goals.requireGoalForStart == false then "off" else null end)`. `else null` (not `else "auto"`) lets a settings source with *neither* key fall through to the next cascade source — fixes a precedence-leak in the pinned-comment sketch where an unrelated `settings.flow.local.json` would mask a project-level `requireGoalForStart`. Add a cascade-resolve compound-expr test. |
| D-A3 | Phase 0.5 onboarding | **Full deletion** | Delete `FLOW_V3_ONBOARDING` detection, the `AskUserQuestion`, and `set_flow_goals()` (`start.md:114-358`). `workflows.enabled`/`triggers` have plugin defaults in `settings.json`; deletion loses nothing. Migration is read-only → configured projects never re-prompted. |
| D-GATE | pr.md/merge.md FlowGoal gate behavior | **Gate on goal existence** | Gate arms when an active goal exists and blocks merge unless `achieved`. **PRs/merges with no goal are NOT blocked** — remove the current exit-1 fail-closed (`merge.md:358-363`, `pr.md` equivalent). Goal state stays load-bearing at merge (per issue Risks) without breaking default-install merges. |
| D-B2 | Verifiable-AC count source (AC-2 + AC-5) | **Extend the shared helper** | Add a discrete `--verifiable-count` mode to `flow-active-goal.sh` (not a 5th `--ac-summary` column — that contract's pipe/newline sanitization is tied to 4 columns). One source of truth; needs its own test. |
| D-OFF | `goalCreation: off` vs `goals.enabled: false` | **Distinct meanings** | `enabled:false` = whole feature off (Stop hook fast-paths, `/flow:goal` disabled). `goalCreation:off` = feature on, `/flow:start` won't auto-create, manual `/flow:goal create` still works. Document in schema + migration docs. |
| D-WORD | AC-1 wording reconciliation | **Draft revised text here** (below); user pastes into issue | Keeps the issue and the implementation-session verdict-judge aligned with "verifiable ACs win." |
| D-E1 | `/flow:resume` linkage detection | **Simple** | Any tracked working-tree change outside `.flow/` and `.decisions/` counts as unlinked → surface + ask before suggesting continuation. Informational-only. |

### Derived semantics — flag for sign-off at implementation start
- **Gate arming key:** the pr/merge gate is **disabled entirely when `goalCreation == off`** (honors the explicit opt-out and preserves the v2 `requireGoalForStart:false` behavior) **or** `goals.enabled == false`. For `auto`/`always`, the gate is armed and follows D-GATE (block iff a goal exists and is not `achieved`; no goal → pass). _This is a derivation from D-GATE + D-OFF, not an explicit user choice — confirm before coding._
- **Degenerate definition (AC-2):** degenerate = `0 ACs` **or** `0 ACs carrying a verification_command`. Note: under `auto` a degenerate goal can no longer be auto-created (auto requires ≥1 verifiable AC), so the `⚠ degenerate / needs-attention` marker is a safety net for `always` mode and `/flow:goal create --manual` only.
- **`requireGoalForStart` retirement:** kept as **deprecated-accepted indefinitely** (read-only migration); no removal timeline, to avoid breaking configured projects.
- **Stop hook:** unchanged. It keys off `goals.enabled` + `stopHookEnforcement`, not `goalCreation`.
- **AC-5 `--json` shape:** `{ goal: {id, lifecycle, ac_summary, verifiable_count}, run: {id, workflow, phase, status}, findings: [...] }`. No existing consumer constrains it.

---

## Revised AC-1 wording (paste into the issue)

> ### AC-1 — `/flow:start` conditional-auto goal creation
> - [ ] Replace the binary `flow.goals.requireGoalForStart` with a 3-state `flow.goals.goalCreation: auto | always | off`, default `auto`.
> - [ ] `auto`: create a FlowGoal **iff the captured goal has ≥1 acceptance criterion carrying a `verification_command`**, regardless of issue labels. The spec-free path (`specFirst.allowSpecFreeLabels`, e.g. `documentation`/`chore`) is solely an *upstream Spec-Gate relaxation* — it lets an issue pass with zero verifiable ACs. When that results in zero verifiable ACs, goal creation is skipped **silently** (no prompt, no error). A spec-free-labeled issue that nonetheless carries verifiable ACs **does** get a goal.
> - [ ] `always`: create a goal unconditionally (a degenerate goal is allowed but flagged per AC-2). `off`: never auto-create; manual `/flow:goal create` still works.
> - [ ] Backward-compatible **read-only** migration: `requireGoalForStart: true` → `always`; `false` → `off`; absence → `auto`. Never rewrites the user's settings file; no configured project is re-prompted or silently changed.
> - [ ] The Phase 0.5 onboarding `AskUserQuestion` is retired (invisible-auto is the default; no consent prompt needed for writing local `.flow/` artifacts).
> - [ ] **Observable:** `/flow:start <issue-with-≥1-verification_command-AC>` on a fresh project creates `.flow/goals/issue-<N>.goal.yaml` with `lifecycle.status: active` and prints **no** `FlowGoal created:` line — only the compact summary (AC-2). `/flow:start` on an issue with **zero** verifiable ACs creates **no** goal and prints no goal line, independent of label.

---

## Per-AC implementation plan (locked approach; sequence low-risk → wide-blast → docs-last)

### 1. AC-4 — branch-first active-goal/run detection (`bin/flow-active-goal.sh`, embedded Python `:65-137`)
- Read current branch (`git branch --show-current`, tolerate failure → `""`); add a test-only `--branch <name>` override for hermetic tests.
- Partition `active` goals by `data["scope"]["branch"]`: if ≥1 matches current branch → that subset is the candidate set; else fall back to most-recently-modified active (`os.path.getmtime`) — covers legacy goals authored before `scope.branch` existed.
- Exit 3 **only** when the current-branch candidate set has `>1`.
- Keep symlink defenses, tolerate-unparseable loop, and all 5 output modes unchanged. `scope.branch` is already required in `goal.schema.json` — no schema change.
- **Tests:** extend `tests/flow-active-goal.test.sh` — two active goals on different branches each resolve their own (exit 0); two on same branch → exit 3.

### 2. AC-1 — conditional-auto `goalCreation` (widest blast radius)
- **Resolve** via `cascade-resolve.sh` with the D-A1 compound expr (`else null`, `--default auto`).
- **Readers (all currently branch on `requireGoalForStart == true`):**
  - `commands/start.md` gate (`:539,548`): `always`→create; `off`→skip; `auto`→create iff `SPEC_HAS_VERIFIABLE_AC` (≥1 AC with `verification_command`). Thread `SPEC_HAS_VERIFIABLE_AC` into the `FLOW_GOAL_STATE` block.
  - `commands/pr.md:124`, `commands/merge.md:330`: retie to D-GATE + derived arming key (off/`enabled:false` → disabled; auto/always → armed, gate-on-existence). **Remove the exit-1 fail-closed.**
  - `schema.json:295`: add `goalCreation` enum `[auto,always,off]` default `auto`; keep `requireGoalForStart` as deprecated-accepted; document D-OFF distinction.
  - `settings.json:97`: replace `requireGoalForStart` with `goalCreation: auto`.
- **Retire Phase 0.5 onboarding** (`start.md:114-358`): delete detection, `AskUserQuestion`, `set_flow_goals()`.
- **Docs:** `references/flow-goals.md`, `flow-goals-quickstart.md`, `migration-v2-to-v3.md`, README — document the 3-state model, migration mapping, and D-OFF.
- **Tests:** `start-v3-integration.test.sh`, `flow-start-onboarding.test.sh` (replace onboarding cases with migration-mapping assertions: `true`→`always`, `false`→`off`, absent→`auto`, explicit wins), `flow-pr-merge-goal-gate.test.sh` (gate-on-existence: goal-present-not-achieved → block; no-goal → pass; off → disabled), `status-triggers-v3-integration.test.sh`, plus a new `cascade-resolve.test.sh` compound-expr case. Add conditional-auto: ≥1-verifiable-AC issue → goal; zero-verifiable / documentation → no goal, no prompt.

### 3. AC-2 — compact runtime summary + degenerate marker (`commands/start.md:621-624`)
- Replace `FlowGoal created: <ID> at <PATH> (status: active)` with a compact block: **Goal id (+ "N ACs / M verifiable"), Workflow, Run id, Branch**, and a one-line "I'll work until the goal is achieved, blocked, or needs your decision." Suppress the old dump line.
- **Truthfulness gate:** degenerate (per D-derived definition) or unevaluated goal renders `⚠ degenerate / needs-attention`, never a clean `active` line. Compute verifiable count via the new `flow-active-goal.sh --verifiable-count`.
- **Tests:** `start-v3-integration.test.sh` — compact format + degenerate marker for a goal with no verification commands.

### 4. AC-5 — `/flow:status` compact dashboard + deep modes (`commands/status.md`)
- Parse mode arg with the **bare-`$ARGUMENTS`-first** pattern (`_RAW="$ARGUMENTS"; ARG1="${_RAW%% *}"`) per the #120 fix — never `${ARGUMENTS%% *}` directly.
- Default → compact dashboard (Active work / Goal AC-evidence summary / Workflow phase+activity / Evidence state / Next safe action). `--full` → current verbose. `--json` → D-derived shape. `--evidence` → per-AC sidecar (reuse `--ac-summary` + `.flow/runs/<id>/evidence/`). Unknown arg → compact fallback.
- Keep the existing `(v3 not enabled)` gating line (`status.md:425`), which keys off `goals.enabled`.
- **Tests:** `flow-status-learn-v3.test.sh` — each mode's distinct shape; unknown arg → compact.

### 5. AC-6 — `/flow:resume` conservatism (`commands/resume.md:30-169`)
- After resolving the active run, run `git status --porcelain`; treat any tracked change outside `.flow/` and `.decisions/` as unlinked. If unlinked changes exist, surface them and **ask before suggesting continuation** via `AskUserQuestion`. Informational-only; never auto-execute.
- **Tests:** dirty tree with unrelated change → warning; clean/run-linked → none.

### 6. AC-7 — README reframe + count fix (`README.md`, `tests/command-frontmatter.test.sh`)
- Lead with a **Work** section ("/flow:start creates a goal, selects a workflow, records evidence, prevents premature completion — inspect with /flow:status; you don't manage it manually"). Move the six runtime primitives (`goal`, `workflow`, `trigger`, `run`, `resume`, `watch`) to an **Advanced / runtime internals** subsection; reframe `/flow:goal create` as `--manual`-only.
- Fix `README.md:180` `COMMANDS (17)` → **23**; reconcile the table to list all 23.
- Bump `FILE_COUNT_FLOOR` 15 → 20 and fix the stale "17 as of this writing" comment (`:23`).

---

## Verification (each AC + end)
- `bash plugins/flow/tests/run.sh` stays green (840 today) + the per-AC tests above.
- Manual smoke: fresh-project `/flow:start <≥1-verifiable-AC issue>` → goal created, compact summary, no `FlowGoal created:` line, no onboarding prompt; zero-verifiable issue → no goal, no prompt; goal w/o verification commands (`always`) → degenerate marker. Two-branch worktrees → `flow-active-goal.sh --status` returns each branch's goal (exit 0). `/flow:status --full|--json|--evidence` distinct. Dirty unrelated tree → `/flow:resume` warns. `/flow:review <pr>` then `/flow:resume` → run exists, no goal (AC-3 regression guard). Merge gate: goal-present-not-achieved → block; no-goal PR → not blocked.

## Out of scope (per #111 non-goals)
No native `/loop`/`/goal`/`/schedule` path; don't delete runtime commands (only demote in docs); no change to `/flow:review` auto-by-severity posting; don't add FlowGoals to review/address.

## Housekeeping note (not part of #111)
The live `.flow/goals/issue-120.goal.yaml` is the running AC-4 bug instance. AC-4 tests must be
hermetic (temp dirs + `--branch` override) so they don't depend on it. Optionally clear/finalize
issue-120's goal separately; not required by this plan.

<!-- auto-log: 2026-05-26 14:24 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-active-goal.sh -->

<!-- auto-log: 2026-05-26 14:24 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-active-goal.sh -->

<!-- auto-log: 2026-05-26 14:24 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-active-goal.sh -->

<!-- auto-log: 2026-05-26 14:24 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-active-goal.sh -->

<!-- auto-log: 2026-05-26 14:25 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-active-goal.test.sh -->

<!-- auto-log: 2026-05-26 14:25 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-active-goal.test.sh -->

<!-- auto-log: 2026-05-26 14:27 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-active-goal.test.sh -->

<!-- auto-log: 2026-05-26 14:27 commit "feat(flow): branch-first active-goal detection + --verifiable-count (#111 AC-4)" -->

<!-- auto-log: 2026-05-26 14:28 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/start.md -->

<!-- auto-log: 2026-05-26 14:29 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/start.md -->

<!-- auto-log: 2026-05-26 14:29 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/settings.json -->

<!-- auto-log: 2026-05-26 14:29 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/schema.json -->

<!-- auto-log: 2026-05-26 14:30 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/merge.md -->

<!-- auto-log: 2026-05-26 14:30 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/merge.md -->

<!-- auto-log: 2026-05-26 14:31 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/pr.md -->

<!-- auto-log: 2026-05-26 14:31 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/pr.md -->

<!-- auto-log: 2026-05-26 14:31 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/pr.md -->

<!-- auto-log: 2026-05-26 14:33 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-cycle14-behavioral.test.sh -->

<!-- auto-log: 2026-05-26 14:33 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/status-triggers-v3-integration.test.sh -->

<!-- auto-log: 2026-05-26 14:35 Write /tmp/rewrite_onboarding.py -->

<!-- auto-log: 2026-05-26 14:37 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-pr-merge-goal-gate.test.sh -->

<!-- auto-log: 2026-05-26 14:37 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-pr-merge-goal-gate.test.sh -->

<!-- auto-log: 2026-05-26 14:43 commit "feat(flow): conditional-auto goalCreation + retire onboarding (#111 AC-1)" -->

<!-- auto-log: 2026-05-26 14:44 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/start.md -->

<!-- auto-log: 2026-05-26 14:44 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/start.md -->

<!-- auto-log: 2026-05-26 14:46 commit "feat(flow): compact runtime summary + degenerate marker (#111 AC-2)" -->

<!-- auto-log: 2026-05-26 14:49 commit "feat(flow): /flow:status compact dashboard + deep modes (#111 AC-5)" -->

<!-- auto-log: 2026-05-26 14:50 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/resume.md -->

<!-- auto-log: 2026-05-26 14:50 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/resume.md -->

<!-- auto-log: 2026-05-26 14:50 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/resume.md -->

<!-- auto-log: 2026-05-26 14:52 commit "feat(flow): /flow:resume guards against unlinked changes (#111 AC-6)" -->

<!-- auto-log: 2026-05-26 14:55 commit "docs(flow): README work-first reframe + command-count fix (#111 AC-7)" -->

<!-- auto-log: 2026-05-26 14:57 commit "docs(flow): changelog entry for #111 v3.1 UX layer + fix stale test comment" -->

<!-- auto-log: 2026-05-26 15:01 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-active-goal.sh -->

<!-- auto-log: 2026-05-26 15:01 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-active-goal.sh -->

<!-- auto-log: 2026-05-26 15:01 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-active-goal.sh -->

<!-- auto-log: 2026-05-26 15:02 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-active-goal.sh -->

<!-- auto-log: 2026-05-26 15:02 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-active-goal.sh -->

<!-- auto-log: 2026-05-26 15:04 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/CHANGELOG.md -->

<!-- auto-log: 2026-05-26 15:05 commit "fix(flow): FlowGoal gate can observe achieved goals via --allow-terminal (#122)" -->

<!-- auto-log: 2026-05-26 15:12 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/resume.md -->

<!-- auto-log: 2026-05-26 15:13 commit "fix(flow): resume unlinked-detection handles git-quoted paths (PR review F1)" -->

<!-- auto-log: 2026-05-26 15:14 Write /tmp/pr-111-body.md -->

<!-- auto-log: 2026-05-26 15:34 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-active-goal.sh -->

<!-- auto-log: 2026-05-26 15:34 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-active-goal.sh -->

<!-- auto-log: 2026-05-26 15:34 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-active-goal.sh -->

<!-- auto-log: 2026-05-26 15:35 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-active-goal.sh -->

<!-- auto-log: 2026-05-26 15:36 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-active-goal.test.sh -->

<!-- auto-log: 2026-05-26 15:37 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/resume.md -->

<!-- auto-log: 2026-05-26 15:37 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/resume.md -->

<!-- auto-log: 2026-05-26 15:39 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-resume-unlinked.test.sh -->

<!-- auto-log: 2026-05-26 15:39 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/merge.md -->

<!-- auto-log: 2026-05-26 15:40 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/pr.md -->

<!-- auto-log: 2026-05-26 15:46 commit "fix(flow): address self-review findings on the v3.1 UX layer" -->

<!-- auto-log: 2026-05-26 15:46 Write /tmp/pr-123-review.md -->

<!-- auto-log: 2026-05-26 15:56 Edit /Users/danielbentes/synapti-marketplace/README.md -->

<!-- auto-log: 2026-05-26 15:56 commit "docs(flow): strip remaining finding/AC refs from comments + fix main README count" -->
