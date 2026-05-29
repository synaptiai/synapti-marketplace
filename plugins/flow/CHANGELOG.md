# Changelog

## 3.2.2 (2026-05-29)

### Changed: review/finding tables render as two columns

- **Findings and resolution tables are now two-column (`Finding | Suggested Fix`) for legibility in
  GitHub PR comments.** Review and self-review comments previously used 5–7 column tables (`ID |
  Category | Location | Problem | Suggested Fix | Confidence [| Disposition]`). In GitHub's narrow
  PR-comment column every prose cell collapsed and wrapped one word — sometimes one character — per
  line, stacking `category` vertically and breaking `location` mid-path. All finding and resolution
  tables now collapse to a two-column shape: the short metadata (`{ID} · {category} · {location}`,
  plus the paired-reviewer `_(confidence · disposition)_` suffix) is packed into the bold first line
  of the Finding cell, and the two prose fields each get a full column. Updated across
  `references/finding-schema.md` (keystone), the four reviewer agents, `skills/visual-verification`,
  `skills/code-review-methodology`, `skills/team-coordination`, `templates/review-comment.md`,
  `templates/self-review-comment.md`, `templates/resolution-comment.md`, `commands/review.md`,
  and `commands/address.md`. A new pipe-escaping rule (`\|` inside cells) keeps
  shell-pipe quotes like `grep \| head` from breaking rows. Rendering change only — the finding data
  model and the `FLOW_REVIEW_CYCLE` / `FLOW_RESOLUTION_CYCLE` marker grammar (which the merge/status
  gates parse) are unchanged, so no migration is required.

## 3.2.1 (2026-05-27)

### Fixed: /flow:merge gate false-blocks + diagnostics

- **Self-reviewed PRs no longer false-block at the finding-ledger gate (#124).** The self-review
  fix-forward path fixes every finding in-PR but only posted a `FLOW_REVIEW_CYCLE` marker (status
  `open`) with no `FLOW_RESOLUTION_CYCLE`. The merge gate balances `FINDINGS − RESOLVED` and reads
  `RESOLVED` only from a `FLOW_RESOLUTION_CYCLE` issue comment, so a solo/agent-authored PR whose
  findings were all fixed in-PR blocked at merge and required a manual Tier-3 override. Self-review
  now emits the same `FLOW_RESOLUTION_CYCLE` marker `/flow:address` emits (issue-comments stream),
  recording fix-forwarded IDs as `RESOLVED` and any unfixable finding as `ESCALATED` — unifying solo
  and two-actor flows on the mechanism the gate already trusts, with **zero change to the gate's
  classification logic**. Also adds the previously-missing `FLOW_REVIEW_CYCLE` marker to
  `templates/self-review-comment.md`.
- **Finding-ledger seed scans both marker streams (#126).** The merge assessment's diagnostic seed
  scanned only the issue-comments stream, so a PR whose only marker was a `FLOW_REVIEW_CYCLE` in a
  review body reported `SEED_MARKER_COUNT=0`. The seed now queries both the reviews and
  issue-comments streams and emits `SEED_SCANNED` naming the surfaces. A marker is defined precisely
  as `FLOW_*_CYCLE:<digits>`, so bare prose mentions and unsubstituted `:{N}` placeholders are not
  counted (`SEED_MARKER_COUNT=0` means genuinely absent), and both the union and count jq steps fail
  closed to `STATE=unavailable` on unreadable input rather than collapsing to a false `STATE=empty`.
  Diagnostic-only — the authoritative gate already scanned both streams, so gate behavior is unchanged.

### Tests

- **Regression guard for the terminal/achieved FlowGoal merge gate (#125).** #125's primary bug — an
  `achieved` (terminal) goal read as "no active FlowGoal" and false-blocking merge — was already fixed
  in 3.2.0 (`flow-active-goal.sh --allow-terminal --branch-strict`), but nothing pinned the
  lifecycle→state mapping. Adds a consolidated guard asserting `achieved → ok`, `active → blocked`,
  and `failed`/`cancelled`/no-goal `→ not-applicable`. Note: `failed`/`cancelled` resolve to
  not-applicable **by design** (only `achieved` is a gate-relevant terminal state); #125's
  failed/cancelled-should-block wishlist item is intentionally not implemented in 3.2.x — the merge
  gate keys on an *active, incomplete* obligation, and an abandoned/closed goal defers to the PR's own
  review state and the finding-ledger gate.

## 3.2.0 (2026-05-26)

### Added: v3.1 UX layer — invisible-by-default runtime (#111)

"User intent in, runtime artifacts out." Goals/runs/evidence are now managed for you rather than gated behind opt-in.

- **Conditional-auto goal creation (AC-1)** — replaced the binary `flow.goals.requireGoalForStart` with a 3-state `flow.goals.goalCreation: auto | always | off` (default `auto`). `auto` creates a FlowGoal iff the Spec Validation Gate passed with ≥1 acceptance criterion carrying a `verification_command` (labels do not veto; zero-verifiable/spec-free issues skip silently). `always` creates unconditionally; `off` never auto-creates (manual `/flow:goal create` still works). Read-only migration: `requireGoalForStart: true`→`always`, `false`→`off`, absent→`auto` (settings files are never rewritten). The Phase 0.5 onboarding `AskUserQuestion` and the `set_flow_goals` helper are retired.
- **Compact runtime summary (AC-2)** — `/flow:start` replaces the `FlowGoal created: …` dump with a compact Goal/Workflow/Run/Branch summary. A degenerate goal (0 ACs, or 0 ACs carrying a `verification_command`) is flagged `⚠ degenerate / needs-attention`, never shown as a clean `active` line; a skipped goal omits the goal line entirely.
- **Gate on goal existence (AC-1 D-GATE)** — `/flow:pr` and `/flow:merge` now block only when an active goal exists and isn't `achieved`; a branch with **no** goal is no longer blocked (the prior exit-1 fail-closed is removed), preserving v2 merge UX for default installs. The gate is disabled under `goalCreation: off` or `goals.enabled: false`.
- **Branch-first active-goal detection (AC-4)** — `bin/flow-active-goal.sh` resolves the active goal branch-first (`scope.branch == current branch`, falling back to most-recently-modified active). Exit 3 (degenerate) now fires only when >1 active goal share the current branch, so concurrent goals on different branches/worktrees stop colliding. Adds a test-only `--branch` override and a `--verifiable-count` mode.
- **`/flow:status` compact dashboard + deep modes (AC-5)** — default output is a 5-line operational dashboard; `--full`, `--json`, and `--evidence` modes added (bare-`$ARGUMENTS`-first parse; unknown arg → compact fallback). `(v3 not enabled)` gating preserved for v2 users.
- **`/flow:resume` conservatism (AC-6)** — detects uncommitted changes outside `.flow/` and `.decisions/` and asks before suggesting continuation, so a resumed run never silently absorbs unrelated work. Remains informational-only.
- **Docs reframe + count fix (AC-7)** — README leads with work-first framing; the six runtime primitives (`goal`, `workflow`, `trigger`, `run`, `resume`, `watch`) moved to an "Advanced / runtime internals" section, with `/flow:goal create` reframed as the `--manual` path. Fixed `COMMANDS (17)` → `(23)` and added a test that keeps the README count in sync with the actual command-file count.
- **`/flow:review` + `/flow:address` record a FlowRun only, no user-facing FlowGoal (AC-3)** — shipped in #114.
- **`/flow:setup` upgrades deprecated settings on re-run** — new `bin/flow-migrate-settings.sh` detects a committed `flow.goals.requireGoalForStart` and, behind an `AskUserQuestion` confirmation, rewrites it to `goalCreation` (`true`→`always`, `false`→`off`) atomically, preserving all other keys. Optional hygiene only — the runtime already honors the deprecated key read-only, so declining changes nothing. The v3 runtime settings blocks stay governed by plugin defaults (not written into the team file).

### Fixed: FlowGoal gate could never observe an `achieved` goal (#122)

`bin/flow-active-goal.sh` filtered goals to `active`-only, so a goal that had correctly transitioned to terminal `achieved` returned exit 1 (no active goal) and the gate's `if [ "$GOAL_STATUS" = "achieved" ]` success branch in `merge.md`/`pr.md` was unreachable dead code. Combined with the #111 gate-on-existence change this no longer hard-blocked the merge, but it mislabeled an achieved goal as "no active FlowGoal — gate not applicable," losing the audit trail. Added an opt-in `--allow-terminal` flag to the helper (surfaces `achieved` goals as a branch-first fallback, only when no active goal exists, never trips the degenerate exit 3) and wired it into both gate invocations in `merge.md` and `pr.md`. The Stop hook and `/flow:status` keep their narrow active-only semantics by omitting the flag. Closes the test-coverage gap with an end-to-end `achieved`-path test in `flow-active-goal.test.sh`.

## 3.1.2 (2026-05-26)

### Fixed: `${ARGUMENTS%% *}` in command `!`-blocks expanded to empty (#121)

Claude Code's slash-command preprocessor substitutes only the bare `$ARGUMENTS` and `${ARGUMENTS}` tokens — never bash parameter-expansion forms like `${ARGUMENTS%% *}` or `${ARGUMENTS:-}`. The bash interpreter then saw an undefined `ARGUMENTS` variable and the expansion yielded the empty string, so first-token extraction produced `""` and downstream gates (`PREFLIGHT_STATE`, `FLOW_GOAL_STATE`) silently degraded to their no-arg paths even when the user passed an argument.

Command `!`/bash blocks now copy the substituted bare form into a line-local variable first (`_RAW="$ARGUMENTS"; ARG1="${_RAW%% *}"`) across `start`, `address`, `merge`, `review`, `resolve`, `design`, `brainstorm`, and `resume`. A static lint (`command-frontmatter` test) now rejects bash parameter-expansion on `$ARGUMENTS` in `!`/`bash`/`sh` fences — covering trailing-operator (`%% # / : ^ , @ + -`), array-subscript, length (`${#ARGUMENTS}`), and indirection (`${!ARGUMENTS}`) forms — and the onboarding gate fixture now models Claude Code's text substitution instead of injecting `ARGUMENTS` as an environment variable, which is what had masked the bug.

## 3.1.1 (2026-05-25)

### Fixed: command bash blocks could not locate bundled `bin/` on marketplace installs

Command `!`/bash blocks located bundled helpers via `${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/…`. `CLAUDE_PLUGIN_ROOT` is documented for hooks/MCP/LSP/monitors/skill substitution but **not** for slash-command bash blocks (and is unset when an agent runs the steps through its Bash tool), and the `:-plugins/flow` fallback only resolves for an in-repo checkout — never for a marketplace install. The result: in a consumer repo, helpers were unreachable, so `/flow:start` with `flow.goals.requireGoalForStart: true` could not auto-create the FlowGoal (`.flow/` was never created) and the `/flow:merge` goal gate had nothing to check.

Command blocks now use an inline resolver that probes, in order: `$CLAUDE_PLUGIN_ROOT`, in-repo `plugins/flow`, the highest-semver marketplace cache install, then the marketplaces checkout — failing loud (existing `*_STATE=blocked` sentinels) when none resolves. Hooks are unaffected (they receive `CLAUDE_PLUGIN_ROOT` per the docs). See `references/plugin-root-resolution.md`.

### Added: `/flow:pr` commits trailing decision-journal churn

The decision journal (`.decisions/`, tracked) is appended to by the auto-log hooks during normal work and never committed, so it showed dirty at PR time. `/flow:pr` now sweeps journal-only churn into a `chore(decisions):` commit before pushing (new `bin/commit-journal-churn.sh`). It no-ops if any non-journal path is dirty and never stages lockfiles; the `chore(decisions):` subject is skipped by the `log-commits.sh` Guard 1, so there is no re-append loop. Journal lockfiles, `.trail/`, and `.claude/scheduled_tasks.lock` are now gitignored.

## 3.1.0 (2026-05-23)

### Fixed: merge-aware force-branch-delete in the destructive-command hook

`block-destructive.sh` previously blocked every force branch-delete and pointed users at safe-delete — but safe-delete cannot remove squash-merged branches, so merged-branch cleanup was impossible. The hook is now merge-aware: it allows a force-delete only when every target branch is provably merged into the default branch (ancestor check for regular/fast-forward merges; synthetic-commit + `git cherry` patch-equivalence for squash merges; checked against the local default and `origin/<default>`), detecting all force-delete forms (`-D`, `-Df`/`-fD`, `--delete --force`). It still blocks the default branch, unmerged work, unresolvable refs, compound commands, and fails safe on any uncertainty. All other destructive blocks are unchanged. Also fixed a flaky `assert_match` SIGPIPE/`pipefail` race in the test harness.

### Added: v3 runtime integration — FlowRun + FlowGoal wired into the commands

v3.0 shipped the runtime primitives as infrastructure; this release wires them into the workflow commands so runs and goals are automatic rather than opt-in:

- **FlowRun wiring** in all seven long-running commands (`start`, `debug`, `address`, `review`, `pr`, `merge`, `release`). Each creates (or, for `pr`, appends to) a durable `.flow/runs/<id>/run.yaml` at entry, records FlowActivities at phase boundaries, and transitions to a terminal state on completion — gated by `flow.runtime.enabled` (default `true`; v2 projects opting out see a no-op).
- **FlowGoal creation** now also covers `/flow:debug` (alongside the existing `/flow:start`), via `goal-contract-capture` after hypothesis confirmation. `/flow:review` and `/flow:address` are FlowRun-only (a review/address session is bounded by the PR). A `debug` row was added to the `specification-capture` per-invoker scope table.
- **Goal gates**: `/flow:pr` blocks PR creation when the linked goal is not `achieved` (with a journaled override path), and `/flow:merge` blocks merge until the goal is `achieved` and all linked FlowRuns are `completed` (Tier 3, no override).
- **`/flow:status`** now surfaces an **Active Triggers** section (alongside the existing FlowGoal State + Recent Runs).
- **Defaults flipped**: `flow.workflows.enabled` and `flow.triggers.enabled` are now `true` (still per-trigger opt-in; overridable to `false` for v2.x behavior via the settings cascade).

### Added: configurable model for Path A agent-team review

`/flow:review` Path A (agent-team paired-reviewer mode) dispatches ~20 subagents, all previously `model: inherit` — on an Opus session that multiplied Opus-rate tokens ~4x. A new top-level `agentTeamModel` setting (enum `haiku|sonnet|opus|inherit`, default `sonnet`, cascade-resolved) controls the model for those Path A reviewers via the Agent tool's per-invocation `model` override. `inherit` reproduces the prior behavior (override omitted → session model). Invalid values are rejected with a warning and fall back to `sonnet`. Path B (single-session, default) is unchanged.

## 3.0.0 (2026-05-20)

### New: Flow v3 runtime layer — goals, workflows, triggers

Flow v3.0 introduces a **runtime layer** at `.flow/` on top of the existing v2 plugin. Six new primitives — FlowGoal, FlowWorkflow, FlowTrigger, FlowRun, FlowActivity, FlowEvidence — give the plugin durable goals (completion contracts), inspectable workflows (process contracts), declarative triggers (wake-up intent), and resumable execution records.

**The non-negotiable constraint** (verified): Claude Code plugins cannot invoke native `/goal`, `/loop`, `/schedule`, or any built-in slash command. Flow v3 replicates the *contract* via project-local artifacts and runs its own loop via the `Stop` hook.

#### New primitives

- **FlowGoal** — `.flow/goals/<id>.goal.yaml`, schema-validated completion contracts with outcome, AC, verification commands, constraints, evaluator binding, and lifecycle state (`draft → active → {waiting_for_user, waiting_for_ci, blocked} → {achieved, failed, cancelled}`). Lifecycle transitions go through `bin/flow-goal-record.sh` (atomic via `_journal_atomic.py`).
- **FlowWorkflow** — `plugins/flow/workflows/<id>.workflow.yaml`, machine-readable process contracts for `/flow:start`, `/flow:review`, `/flow:address`, `/flow:merge`, `/flow:release`, `/flow:debug`, `/flow:design`. Validated by `/flow:workflow validate`.
- **FlowTrigger** — `.flow/triggers/<id>.trigger.yaml`, wake-up intent contracts. v3.0 supports `manual | hook | loop_prompt`; v3.1+ adds `github_actions | local_cron | local_daemon`. Hard requirement: `merge` and `release` MUST be in every trigger's `policy.forbidden_actions`.
- **FlowRun + FlowActivity** — `.flow/runs/<ISO-timestamp-id>/` with `run.yaml`, sequence-numbered `activities/<NNN>-<name>.yaml`, and `events.jsonl`. Powers `/flow:resume`.
- **FlowEvidence** — `.evidence.yaml` sidecars + raw output captures under `.flow/runs/<id>/evidence/`.

#### New commands

- `/flow:goal` — `status | create | inspect | evaluate | pause | resume | clear | history`
- `/flow:resume` — informational; reads interrupted FlowRun state, suggests next safe action
- `/flow:workflow` — `list | inspect | validate | graph`
- `/flow:trigger` — `list | inspect | enable | disable | run | delete`
- `/flow:watch` — `pr <N> | ci | issue <N> | branch`; creates trigger + generates `.claude/flow-loop-<id>.md` for manual `/loop` invocation
- `/flow:run` — `trigger <id>`; single-shot trigger executor

#### New skills (7)

- `goal-contract-capture` — extends `specification-capture` as 5th invoker; writes goal YAMLs
- `goal-evaluator` — wraps `criterion-verification-map`; runs deterministic checks + optional judge dispatch
- `goal-evidence-ledger` — wraps `evidence-based-development`; file-backed sidecars
- `goal-lifecycle` — state machine enforcement; every transition writes journal artifact
- `run-state-management` — owns FlowRun mutations; wraps `autonomous-workflow`
- `workflow-validation` — schema + cross-reference checks
- `trigger-policy` — Tier 3 absolute deny + recursion deny enforcement

#### New agent

- `goal-evaluator-judge` — specializes `verdict-judge`. Same Independence Protocol; output adds `confidence`, `delta`, `next_step_hint`. Used in evaluator-loop Stop mode and `/flow:goal evaluate`.

#### New hooks

- `flow-goal-stop.sh` — Stop hook in three modes: `warn` (default, $0/turn), `block`, `evaluator-loop` (opt-in, Haiku subprocess ~$0.001/turn).
- `flow-goal-evaluator.sh` — Active evaluator-loop mode. Recursion guarded via `CLAUDE_HOOK_GOAL_JUDGE_MODE` env var; throttled to 3 continuations/5min/session.
- `flow-run-deterministic-checks.sh` — Shared deterministic checks runner.
- `session-end-state.sh` — Annotates active FlowRuns at session end.

#### Refactored

- `bin/journal-record.sh` lines 120-295 (Python heredoc) extracted into `bin/_journal_atomic.py` as a shared module. All 14 existing tests in `journal-record.test.sh` pass unchanged. Security defenses (PYTHONSAFEPATH, O_NOFOLLOW, fcntl.flock, tempfile+rename+fsync, hostile-fork RCE mitigations) preserved verbatim.

#### Settings additions

All under `flow.*` namespace, cascade-resolved via `bin/cascade-resolve.sh`:
- `flow.runtime.*` — master switch + state dir + retention
- `flow.goals.*` — feature flag + auto-create flag + Stop hook posture + judge model
- `flow.workflows.*` — feature flag (default `false`)
- `flow.triggers.*` — feature flag + allowed types + concurrency + recursion deny

#### Behavior defaults (preserve v2.x UX)

- `flow.goals.requireGoalForStart: false` — `/flow:start` does NOT auto-create goals by default. Users opt in via `/flow:goal create` OR via the first-run consent prompt below.
- `flow.goals.stopHookEnforcement: warn` — Stop hook is silent for users without active goals.
- `flow.workflows.enabled: false` — `/flow:workflow` opt-in.
- `flow.triggers.enabled: false` — `/flow:trigger` and `/flow:watch` opt-in.

To disable the v3 runtime layer entirely (rollback): set `flow.runtime.enabled: false` and `flow.goals.enabled: false`.

#### First-run consent prompt + integration into `/flow:start`

To close the "feature ships dormant" usability gap surfaced by the post-cycle-8 review, `/flow:start` now wires v3 into the workflow surface and prompts new users to opt in:

- **Phase 0.5 onboarding** — when both `.claude/settings.flow.json` AND `.flow/` are absent (fresh-install signal), `/flow:start` fires a single `AskUserQuestion` consent prompt with three options: enable v3 (recommended for new projects), skip and keep v2 behavior, or read the quickstart first. The user's answer is persisted to `.claude/settings.flow.json` so the prompt fires exactly once per project. v2 projects upgrading (with any existing settings file) never see the prompt.
- **Phase 1 goal auto-creation** — after the Spec Validation Gate passes, `/flow:start` checks `flow.goals.requireGoalForStart`. When `true`, it invokes `Skill(goal-contract-capture)` + `Skill(goal-lifecycle)` to create `.flow/goals/issue-<N>.goal.yaml` and transition to `active`, then echoes `FlowGoal created: issue-<N> at <path> (status: active)`. When the goal already exists, it surfaces the path without overwriting.
- **`/flow:goal evaluate` hint** — when ACs return `last_result.reason: not_executed` (deterministic checks skipped because `flow.goals.executeVerificationCommands: false`), the evaluator output now includes the settings hint to flip the flag, replacing the previous silent skip behavior.

#### New documentation (post-cycle-8)

- `references/flow-goals-quickstart.md` — 5-minute Hello-FlowGoal walkthrough on a synthetic issue (enable → start → inspect → evaluate → verdict)
- `references/migration-v2-to-v3.md` — step-by-step v2 → v3 opt-in across the four independent feature flags (goals, Stop-hook posture, workflows, triggers), with rollback path
- `references/flow-goals.md` — new "Enabling v3 in your project" section with copy-pasteable JSON for `.claude/settings.flow.json`
- `README.md` — new "Get started with v3" link block pointing at the quickstart and migration guide

#### New test

`tests/flow-start-onboarding.test.sh` covers the onboarding detection logic (fresh / settings present / `.flow/` present / both present), the idempotency of both `enable` and `skip` arms (settings file written + re-detection returns `skip`), and the FlowGoal auto-creation gate (create / exists / skip-when-disabled / skip-on-missing-or-invalid issue number). 19 new assertions.

#### Cycle-10 regression fixes (field-feedback hotfix)

Field testing on a separate project surfaced two regressions in the cycle-9 expansion:

- **Onboarding gate detects partial settings** — Phase 0.5 in `/flow:start` now treats a `.claude/settings.flow.json` lacking the `flow.goals` block as "not onboarded yet" and fires the consent prompt. Previously, any existing settings file silently bypassed onboarding, so a project where `/flow:setup` had landed `{"agentTeams": false}` before `/flow:start` was ever run would never see the v3 prompt. New detection: `.flow/` exists → skip; no settings file → prompt; settings file without `flow.goals` block (parsed via `jq -e '.flow.goals // empty'`) → prompt; settings file with `flow.goals` block (any contents, even `{}`) → skip. Conservative jq-unavailable fallback: skip.
- **Settings merge preserves v2 keys** — when the user answers "Enable v3" or "Skip" and a partial file already exists, the new keys are merged via `jq` into the existing file instead of overwriting it. Previously the `cat > settings.flow.json <<JSON` heredoc would silently wipe v2 settings like `agentTeams`, `tiers`, `conventions.commitTypes`. New helper `set_flow_goals()` in `/flow:start` Phase 0.5 uses `jq --argjson req $1 --argjson exe $2 '.flow.goals.requireGoalForStart = $req | .flow.goals.executeVerificationCommands = $exe'` to mutate only the two flags.
- **`context: fork` removed from three command-invoked skills** — `specification-capture`, `holdout-validation`, `runtime-verification` no longer fork. The `Skill(X)` invocation pattern with inline `Inputs:` blocks (used in `start.md`, `pr.md`, `review.md`, `address.md`, `design.md`, `brainstorm.md`) now resolves against the parent's context as intended. Field report: forked subprocess returned "what would you like me to do?" when invoked with full inline args, rendering all three documented-mandatory skills silently optional.
- **Test additions**: `flow-start-onboarding.test.sh` grows by 13 assertions covering partial-settings detection (6 cases: `{}`, v2-only keys, `flow` block without `goals`, empty `flow.goals`, `.flow/` overrides partial settings, malformed JSON), jq-merge preservation (4 assertions on agentTeams/tiers/requireGoalForStart/executeVerificationCommands), and the `context: fork` lint (3 assertions, one per fixed skill).

#### Cycle-11 broader `context: fork` audit

A pointed question — "why was the broader audit deferred?" — surfaced that cycle 10 had stopped at the 3 user-reported failures while 25 other skills carried the same field. Per the [Claude Code docs on skill subagent context](https://code.claude.com/docs/en/skills.md), `context: fork` is only correct when the skill body is a self-contained task directive that captures inputs via `$ARGUMENTS`. None of the 25 remaining skills satisfied that contract; all were in documented-misuse territory. Cycle 11 audits and fixes the broader scope:

- **8 Pattern A skills** (invoked from command markdown via `Skill(X)` references, same bug shape as cycle-10's three): `capability-discovery`, `goal-contract-capture`, `goal-evaluator`, `goal-lifecycle`, `issue-crafting`, `trigger-policy`, `visual-verification`, `workflow-validation`. Of these, 5 (goal-contract-capture, goal-evaluator, goal-lifecycle, trigger-policy, workflow-validation) explicitly declare "The invoking command MUST pass" inputs in their bodies — fork was dropping those inputs entirely, silently. The other 3 are reference-doc / self-contained but gain access to parent context (e.g., git diff state) by running inline.
- **4 disable-invoke skills** (cosmetic cleanup; fork is dormant when `disable-model-invocation: true` prevents autonomous invocation): `merge-and-release`, `pr-lifecycle`, `preflight-checks`, `team-coordination`. Zero behavior change; removes the misleading frontmatter field.
- **13 ambient-only skills deferred**: `architecture-patterns`, `brainstorming`, `branch-and-task-management`, `change-classification`, `code-review-methodology`, `convention-enforcement`, `criterion-verification-map`, `debugging-patterns`, `feedback-resolution`, `goal-evidence-ledger`, `merge-conflict-resolution`, `run-state-management`, `tdd-patterns`. These are listed only in `## Required Skills` blocks (loaded as ambient context, no `Skill(X)` invocation), so fork is dormant unless Claude autonomously invokes them via description matching. Each body needs individual audit (task-directive-with-$ARGUMENTS vs reference) before unforking. Tracked as deferred follow-up; the lint test asserts they still carry `context: fork` to catch accidental removals.

**Test additions**: `flow-start-onboarding.test.sh` grows by 13 assertions (12 fork-lint extensions covering the new fixes + 1 sanity assertion that the 13 deferred skills still carry `context: fork`).

**Cumulative fork-removal scope**: 15 of 28 skills (3 cycle-10 + 12 cycle-11). 13 ambient skills retain fork pending follow-up audit.

#### Cycle-12 self-review fix-forward (paired-reviewer review of cycles 9-11)

Cycle-12 paired-reviewer protocol (Path A: 10 facet agents + 2 holdout-validation lenses) surfaced 17 findings across cycles 9-11. All P1 + P2 fixed in-PR; P3 cosmetic items folded into the same changes where bounded.

**P1 fixes** (load-bearing correctness):
- **Onboarding answer dispatch** (`commands/start.md` Phase 0.5) — the prior `case "$ONBOARDING_ANSWER"` block referenced a variable that never received the `AskUserQuestion` response, so all three arms fell through silently. Restructured as prose-driven dispatch (Claude runs ONE of three documented bash blocks based on the user's chosen option) with explicit halt semantics on `set_flow_goals` failure.
- **Terminal-goal resume guard** (Phase 1) — when `.flow/goals/issue-<N>.goal.yaml` already exists, the gate now parses `lifecycle.status`. Terminal goals (`achieved | failed | cancelled`) emit `FLOW_GOAL_STATE=terminal` and surface a six-field escalation rather than silently attempting to "resume" an immutable goal.
- **Post-write verify after `Skill(goal-contract-capture)`** (Phase 1) — the "FlowGoal created" echo now fires only after confirming `$GOAL_PATH` exists AND `lifecycle.status == active`. Skill silent failure no longer produces a false-positive visibility line.
- **Symlink defense on settings file** (`set_flow_goals` helper) — refuses to write through `.claude` or `settings.flow.json` if either is a symlink, matching the O_NOFOLLOW pattern in `bin/journal-record.sh`. TOCTOU re-check before the actual write.
- **`executeVerificationCommands` gate scope clarified** — the docs in `commands/goal.md`, `references/flow-goals.md`, `references/flow-goals-quickstart.md` previously claimed the flag governs `/flow:goal evaluate`. The implementation only honors it in the Stop hook's `bin/flow-run-deterministic-checks.sh` (matching `schema.json:309`). Docs corrected to say the flag governs the Stop hook path; `/flow:goal evaluate` executes verification commands when present regardless.
- **README v3 prompt-firing claim corrected** — README previously said "v2 projects with an existing settings file never see the prompt"; cycle-10 introduced partial-settings detection that fires the prompt when the existing file lacks a `flow.goals` block. README and `migration-v2-to-v3.md` now describe the actual behavior with a carve-out.

**P2 fixes**:
- **jq-absent fallback regression** (`set_flow_goals`) — when the file exists and jq is unavailable, the helper refuses to write rather than overwrite v2 keys with a heredoc fallback. Closes the gap where cycle-10's "v2 keys preserved" claim applied only to the jq-present path.
- **Concurrent-write race** — wrapped the read-modify-write in `flock -x` with a PID-scoped tmpfile and explicit `mv`/jq error handling, so two parallel `/flow:start` invocations cannot lose data.
- **`skill-manifests.md` drift** — the "Domain Skills Inventory" table is now synced with current SKILL.md frontmatter state (15 inline + 13 fork + 4 disable-model-invocation), with explanatory header noting the cycle-10/11 unfork scope. Added 13 v3 skills missing from the table entirely.
- **`jq -e` stderr handling** + **`cascade-resolve.sh` existence check** — both error paths now surface `FLOW_ONBOARDING_ERROR=` / `FLOW_GOAL_ERROR=` lines instead of silently degrading. cascade-resolve absence halts Phase 1 with a `FLOW_GOAL_STATE=blocked` exit.
- **`migration-v2-to-v3.md` "no change" carve-out** — added a section explicitly documenting the v2-visible behavior change (first-run prompt for v2-with-partial-settings users) and how to pre-empt it.
- **"Rolling back" destructive snippet fix** — added a jq-merge example so users don't wipe v2 settings by copy-pasting the disable JSON.

**P3 fixes** (folded into above where bounded):
- Per-skill enumeration of the 13 deferred ambient skills (replacing opaque count assertion) — the test now reports which skill drifted.
- Added inverse-direction assertion catching a new fork-using skill outside the 13 deferred + 15 fixed set.
- Added 3 new partial-settings edge cases: array root (`[]`), `flow.goals: null`, and the previously-tested malformed JSON.
- Added 2 new `set_flow_goals` direct tests: jq-absent refusal + symlink refusal.

**Not addressed** (intentionally deferred to follow-up, not regression):
- Orphaned `agent:` field on 15 unforked SKILL.md files — dead frontmatter, no behavior impact. Cosmetic cleanup tracked in follow-up.
- CHANGELOG cycle-9 heading-shape inconsistency (no `#### Cycle-9` heading vs cycle-10/11) — purely indexing style.
- End-to-end `/flow:start` integration test — convention across the suite is to lift bash blocks; adding an end-to-end runner is a suite-wide change.

**Test additions**: `flow-start-onboarding.test.sh` grew by 20 assertions (45 → 65): 3 new edge cases (array, null, refined malformed), 5 set_flow_goals direct tests, 12 per-skill deferred-audit assertions (replacing 1 count assertion = net +12). Suite total: 478 → 498 pass.

**Self-review verdict**: All 6 P1 + 6 P2 + 5 P3 findings either fixed or explicitly documented as deferred with rationale. Cycle 12 converged to zero outstanding findings.

#### Cycle-13 — logical-usability assessment fixes (all 16 findings, P1+P2+P3)

A logical-usability assessment after cycle-12 surfaced 16 findings spanning integration gaps (4 P1), contract drift (8 P2), and polish (4 P3). All addressed in-PR per the no-scope-deferral feedback. Decisions locked via AskUserQuestion:

- Scope: All 16 findings (P1+P2+P3)
- F4: Workflows documented as inspectable contracts (not enforced gates); `completion_gate.requires` renamed to `completion_gate.documented_requirements`
- F5: Single "Enable v3" enables goals + workflows together; triggers stay separate opt-in (they can fire shell)
- F6: Helper is single source for verdict persistence; skill returns structured verdict and never writes
- F9: Implement stuck-detection (saner default than removing the contract)

**P1 fixes** (integration gaps):

- **F1 — FlowGoal gate in `/flow:pr` and `/flow:merge`**: `pr.md` Phase 1 surfaces a `### FlowGoal State` section reading `bin/flow-active-goal.sh`. Phase 4 step 7a fires AskUserQuestion when the gate blocks (Run /flow:goal evaluate / Create PR with not-yet-achieved status / Cancel). `merge.md` Phase 1 extends the finding-ledger gate with a parallel `### FlowGoal Gate` block; the BLOCKED display gains a FlowGoal row. Gated behind `flow.goals.requireGoalForStart` — v2 projects (flag false/unset) see no behavior change.
- **F2 — `### FlowGoal State` + `### Recent Runs` in `/flow:status`**: New `!`-block sections after `### Decision Journal`. FlowGoal State surfaces active goal + per-AC status via `bin/flow-active-goal.sh --ac-summary`. Recent Runs lists last 3 entries from `.flow/runs/<ISO-id>/` with verdict + activity count. Both gated behind `flow.goals.enabled`; v2 mode → `STATE=disabled`.
- **F3 — Goal failure pattern analysis in `/flow:learn`**: Phase 1 enumerates `.flow/goals/*.goal.yaml` + `.flow/runs/*/events.jsonl`. Phase 2 adds a `Goal Failure Patterns` category covering recurring failed ACs (same `verification_command` failing across 3+ goals), stuck-detection hits, `not_executed` ACs, and path-boundary violations. Pattern qualifies same as decision patterns (≥2 occurrences + evidence citations).
- **F6 — Verdict persistence consolidated to a single helper**: Eliminates the prior 3-way race (skill, command, hook all wrote `last-verdict.json`; last writer won, skill's verdict silently discarded). `goal-evaluator` SKILL.md Step 8 rewritten: skill returns structured verdict and does NOT write. Command (`goal.md`) and Stop hook (`flow-goal-evaluator.sh`) each invoke `bin/flow-record-verdict.sh` directly. Two callers, one helper, one write per turn.

**P2 fixes** (contract drift):

- **F4 — `completion_gate.requires` renamed to `completion_gate.documented_requirements`**: The legacy name implied enforcement; the field is advisory documentation. Renamed across `workflow.schema.json`, 7 plugin workflow YAMLs, `flow-workflows.md` docs. `workflow-validation` SKILL.md gains a v3.0.x migration shim — YAMLs with the legacy field are accepted with a stderr deprecation warning. Support drops in v3.1.
- **F5 — Onboarding enables goals + workflows together**: `/flow:start` Phase 0.5 "Enable v3" arm now invokes a new `set_flow_workflows_enabled` helper after `set_flow_goals` succeeds. Both go through atomic jq-merge + flock. Skip arm leaves `flow.workflows` untouched (preserves user's existing setting). Triggers stay separate opt-in — they can fire shell, so a single Enable answer doesn't grant trigger autonomy. Confirmation message tells the user how to enable triggers later.
- **F7 — `delta` semantics documented**: New "Verdict delta semantics" section in `references/flow-goals.md` defines `made_progress | unchanged | regressed` values + computation rules + consumers (stuck detection, /flow:learn, /flow:goal status). `goal.md` status output template gains a `Delta:` line.
- **F8 — Throttle event logging**: `flow-goal-evaluator.sh` throttle path now appends a `throttle-block` event to the active run's `events.jsonl` so `/flow:learn` can detect projects frequently hitting the throttle. Inline best-effort RUN_ID resolution via `bin/flow-active-goal.sh`. `references/stop-hook-goal-enforcement.md` gains a "Throttle event log" subsection documenting the schema.
- **F9 — Stuck-detection implemented in the hook**: New `_check_stuck` helper in `flow-goal-evaluator.sh` increments a per-run counter on `delta == "unchanged"`, resets on other deltas, transitions the goal to `lifecycle.status: failed` when counter reaches `flow.goals.failAfterStuckTurns` (default 3). Counter state at `.flow/runs/<id>/stuck-counter`. Emits `stuck-detection-fired` event. Integrated into both must-pass-fail and judge not_achieved paths — on stuck, hook emits approve instead of block (goal is terminal; further iteration moot).
- **F12 — Tier Classification audit + lint test**: Added `## Tier Classification` sections to 6 commands missing them (`goal.md`, `resume.md`, `run.md`, `trigger.md`, `watch.md`, `workflow.md`). New `tests/flow-tier-classification-lint.test.sh` runs in CI; catches future regressions.
- **F13 — Trigger target workflow cross-reference**: `trigger-policy` SKILL.md gains Step 7 — verifies `trigger.target.workflow` resolves to an existing workflow YAML (plugin or project-local). Hard fail. Catches typos at trigger-create time rather than at runtime when `/flow:run trigger <id>` dispatches.
- **F16 — Test coverage for all 14 changes**: 7 new test files + 1 extended; 91 new assertions (498 → 589 pass).

**P3 fixes** (polish):

- **F10 — Tier 2 confirm on terminal-state transition**: `goal-evaluator` SKILL.md Step 6 contract updated — skill writes lifecycle only for non-terminal states. Terminal verdicts (`achieved`/`failed`) return a `proposed_transition`; the command fires AskUserQuestion with Confirm | Re-evaluate | Cancel. Stop-hook evaluator-loop excluded (no AskUserQuestion in hook context — emits approve + next-step hint).
- **F11 — Hard-warn on missing jsonschema**: `bin/flow-goal-record.sh` now emits a one-line stderr WARN when `import jsonschema` fails. Idempotent via module-level sentinel. Previously silent skip masked the validation degradation.
- **F14 — Workflow + trigger quickstarts**: Two new files mirroring `flow-goals-quickstart.md` shape — `flow-workflows-quickstart.md` (5-minute walkthrough of `/flow:workflow list|inspect|validate|graph` + project-local overrides) and `flow-triggers-quickstart.md` (5-minute walkthrough of `/flow:watch pr <N>` + `/flow:trigger` lifecycle + watch-mode `/loop` usage). All three quickstarts cross-link.
- **F15 — Validation errors emit source path + example**: `workflow-validation` SKILL.md violations now include `source_file` + `example` fields. `commands/workflow.md` renders source path + corrected YAML snippet per violation.

**Test additions**: 7 new test files + 1 extension = +91 assertions (498 → 589 pass). New files: `flow-active-goal.test.sh` (14), `flow-tier-classification-lint.test.sh` (2), `flow-workflow-completion-gate-rename.test.sh` (4), `flow-goal-record-jsonschema.test.sh` (2), `flow-throttle-stuck-presence.test.sh` (4), `flow-trigger-cross-ref.test.sh` (2), `flow-pr-merge-goal-gate.test.sh` (4), `flow-status-learn-v3.test.sh` (4). `flow-start-onboarding.test.sh` extended by 7 (F5 verification).

**Self-review verdict**: All 4 P1 + 8 P2 + 4 P3 findings (F1-F16) addressed in this cycle. Cycle 13 converges with 589/589 tests passing.

#### Cycle-14 — paired-reviewer fix-forward (18 findings across security, correctness, tests)

Cycle-13's Path A paired-reviewer self-review surfaced 18 additional findings (6 security P1, 6 correctness P1, 6 P2). Per the user's no-deferral rule, all addressed in-PR.

**Security (P1)**:
- **SEC-1 — `scope.run_id` path-traversal**: schema now constrains run_id to `^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$` so the value can't traverse out of `.flow/runs/<id>/` when interpolated into bash path expressions. Defense-in-depth bash reject in `flow-goal-evaluator.sh` for the jsonschema-unavailable path.
- **SEC-2 — `events.jsonl` symlink defense**: both throttle-block (F8) and stuck-detection-fired (F9) writes now refuse to append if the file is a symlink. Previously the bash `>>` followed symlinks, creating a write primitive for any user-writable target.
- **SEC-3 — Python injection via `$THROTTLE_GOAL_PATH`**: converted the `python3 -c "...'$VAR'..."` heredoc to `python3 - "$VAR" <<'PYEOF' ... sys.argv[1] ... PYEOF` argv pattern. Matches the safe pattern used elsewhere in the same file. Stuck-counter writes also gain `[ -L ]` symlink defense.
- **SEC-6 — `trigger.target.workflow` + `trigger.target.goal` path-traversal**: schema constrains both to `^[a-z0-9][a-z0-9-]{0,63}$` (matches `metadata.id` pattern). Closes the cross-reference probe vector.

**Correctness (P1)**:
- **F1 — `--ac-summary` pipe + newline sanitization**: pipe characters in AC fields used to silently inject extra columns into the documented `<id>|<status>|<evidence_ref>|<last_result>` contract. Now replaced with U+2502 (visual fidelity, parser-safe). Malformed AC shapes (string instead of dict) skipped instead of crashing.
- **F2 — `/flow:status` Recent Runs `tac` fallback**: previous `... | tac 2>/dev/null || ... | tail -3` silently produced oldest-first when `tac` was missing on macOS. Now uses awk-based reverse for portable most-recent-first ordering.
- **F2 — F5 partial-onboarding atomic write**: cycle-13's two-helper sequence (`set_flow_goals` + `set_flow_workflows_enabled`) had a partial-success failure mode where `flow.goals` landed but `flow.workflows` didn't. Refactored to single helper with 3rd arg (`workflows: "true"|"false"|"skip"`) writing all keys in one jq merge. Plus mktemp instead of PID-scoped tmpfile (SEC-V6), cleanup trap, and post-merge JSON validation before mv.
- **F1 — F9 lifecycle preserves `turns_evaluated`**: stuck-detection now reads the existing `turns_evaluated` and writes it back in the failed lifecycle fragment (was hard-coded to 0, losing iteration history `/flow:learn` needs).
- **F7 — F9 stuck-transition no longer lies on failure**: when `flow-goal-record.sh --update-lifecycle` fails, the hook returns 0 (keep block loop active) instead of emitting "lifecycle transitioned to failed" — which was a lie when the write didn't happen.
- **F2 — F9 stuck-counter write fail-closed**: previously `|| true` masked counter-write failure, letting in-memory increment diverge from on-disk state and trapping the user in infinite continuations. Now fail-closed (treat as stuck) when the write fails.
- **F4-COVERAGE — workflow-validation migration shim unreachable**: cycle-13 documented an in-memory `requires → documented_requirements` shim but then invoked `python3 -m jsonschema -i <file> <schema>` which re-read the file from disk, bypassing the shim entirely. Now SKILL.md shows the canonical inline-Python invocation that runs the shim and jsonschema in the same process.
- **F3 — both-fields-present migration**: shim now drops legacy `requires` with WARN when `documented_requirements` is also present (was opaque schema error).

**P2 cluster**:
- **SEC-V4 — cascade-resolve null vs false**: settings cascade could not distinguish "absent" from "explicit false" — both jq `// empty` and `// null` operators fire on null/false, so a higher-precedence source could never override a lower source's true with false. Two-part fix: (a) `cascade-resolve.sh` now treats jq output of `"null"` as not-found (was only treating empty string); (b) 19 boolean-flag call sites converted from `.flow.X // empty` to bare `.flow.X` so jq outputs `false`/`true`/`null` verbatim and cascade routes each correctly.
- **F11-SENTINEL — jsonschema WARN dedup**: cycle-13's `_JSONSCHEMA_WARN_EMITTED` Python sentinel was per-process; since each bash call spawned a fresh Python, WARN fired on every `/flow:goal` command. Now per-day file sentinel at `$TMPDIR/flow-warn-jsonschema-USER-DATE` survives across invocations. TMPDIR (not HOME) so isolated-HOME tests don't break Python user-site-packages lookup.
- **F11-INCONSISTENCY — sibling helpers**: `flow-record-activity.sh` and `flow-record-evidence.sh` were silently swallowing jsonschema ImportError while `flow-goal-record.sh` warned — divergent from F11's "surface the degradation" rationale. All three writers now use the same per-day sentinel.
- **F5 — fresh-file atomic write**: cycle-13's `printf > $SETTINGS` for new settings files was non-atomic; signal mid-write would leave partial content. Now goes through tmpfile + jq-empty-check + mv like the merge path.

**Convention polish (P3)**:
- Cycle-13 test file headers converted from "Source-presence tests for cycle-13 F<n>" to the established "Tests for plugins/flow/<exact-path>" convention.
- Three quickstart `Next steps` sections converted from bare-backtick filenames to clickable markdown links matching project precedent.

**Test coverage (F16 upgrade)**:
- New `flow-cycle14-behavioral.test.sh` provides 33 fixture-driven assertions for the cycle-13 source-presence-only tests:
  - F4 migration shim runs full Python pipeline against schema (legacy `requires` + both-fields cases)
  - F9 stuck-counter increment/reset semantics + symlink defense
  - F10 `proposed_transition` contract + three-option AskUserQuestion
  - F1 pr.md goal-gate state vocabulary (5 states)
  - F8 hook source contains both event types + 3+ symlink-guard sites
  - SEC-1/SEC-6 schema patterns verified at the property level
  - SEC-V4 cascade-resolve explicit-false recognition

**Test totals**: 589 → 622 (+33). Cycle-14 self-review verdict: zero outstanding findings; all 18 paired-reviewer findings addressed in-PR.

#### File-tree additions

- `plugins/flow/schemas/v1/` — 6 schemas (goal, run, activity, evidence, workflow, trigger)
- `plugins/flow/workflows/` — 7 workflow YAMLs
- `plugins/flow/triggers/templates/` — 3 trigger templates
- `plugins/flow/references/` — 5 new references (flow-goals, stop-hook-goal-enforcement, flow-runtime-state, flow-workflows, flow-triggers)
- Root `.gitignore` — `.flow/runs/`, `.flow/evidence/`, `.flow/triggers/*.local.yaml` gitignored; `.flow/goals/`, `.flow/workflows/`, non-`.local` triggers tracked

#### Migration

v3.0 is **purely additive**. Existing v2.x users see no breaking changes; opting into v3 features is a settings flag (`flow.goals.requireGoalForStart`, `flow.workflows.enabled`, `flow.triggers.enabled` — all default `false` or to safe v2.x-compatible values). To roll back entirely, set `flow.runtime.enabled: false` and `flow.goals.enabled: false`.

#### Pre-GA hardening (during PR #109 self-review)

Iterative paired-reviewer self-review converged the 3.0.0 surface against:

- **Independence Protocol enforcement** — new `bin/_flow_evidence_bundle.py` assembles the judge prompt from goal contract + deterministic report + evidence sidecars only; the conversation transcript is never read. All untrusted content is wrapped in `<<<UNTRUSTED_*>>>` fences; the judge's `--disallowedTools '*'` plus `tools: []` in the agent spec is the security boundary.
- **`last-verdict.json` producer + cross-judge enforcement** — `bin/flow-record-verdict.sh` is invoked from every verdict-producing site (evaluator-loop hook on all 3 exit paths; `/flow:goal evaluate` after the skill produces a verdict). Assembler emits `### Evidence coverage analysis` headers with per-AC classification (`deterministic | mixed | judge_only | none`); judge-only ACs are flagged `CROSS-CHECK REQUIRED`.
- **Schema enum coverage + `_safe_ac_id` + orphan-AC + malformed-AC surfacing** in the assembler.
- **Symlink defenses everywhere** — `O_NOFOLLOW` on every file read and tempfile write; `-L` directory checks before+after `mkdir -p`; rejected symlinked goal YAMLs trigger safe-fallback.
- **`timeout(1)` detection** for evaluator-loop mode — hook detects `timeout` or `gtimeout` and degrades with platform-aware install guidance (`brew install coreutils` on Darwin; `apt/dnf/apk add coreutils` on Linux) when neither exists.
- **Integration harness** for evaluator-loop active mode — `tests/lib/mock-claude.sh` PATH-shim, 6 verdict fixtures, 25 test cases covering every documented exit path.

#### Test totals

622 assertions pass, 0 fail (initial v3 baseline 259 → 433 after iterative self-review → 452 after post-cycle-8 onboarding + docs → 465 after cycle-10 regression fixes → 478 after cycle-11 broader fork audit → 498 after cycle-12 paired-reviewer self-review fix-forward → 589 after cycle-13 logical-usability fixes → 622 after cycle-14 paired-reviewer fix-forward). Tests cover JSON schemas, atomic write helpers, Stop hook behavior, the integration harness (full `claude` mock for evaluator-loop active mode), the fresh-install onboarding detection, partial-settings detection + merge (with array/null/malformed edge cases), the `set_flow_goals` helper direct (jq-absent refusal + symlink refusal), the `context: fork` skill-frontmatter lint (15 fixed + 13 deferred-audit per-skill + inverse-drift detection), `bin/flow-active-goal.sh` (all 4 output modes, symlink defense, degenerate-state), Tier Classification convention lint, `completion_gate.documented_requirements` rename + schema acceptance, jsonschema-unavailable WARN, throttle/stuck source-presence, trigger cross-reference, /flow:pr + /flow:merge goal gate presence, /flow:status + /flow:learn v3 sections.

#### What's deferred (after cycle 13)

- Integration of FlowRun creation + FlowGoal auto-creation into the remaining commands (`debug.md`, `address.md`, `review.md`, `release.md`). `start.md` is wired (see "First-run consent prompt + integration into `/flow:start`" above). `pr.md` and `merge.md` gain goal-state visibility + gating in cycle 13 F1; full FlowRun creation in these commands is deferred.
- ~~`/flow:status` and `/flow:learn` extensions to read from `.flow/`.~~ — completed in cycle-13 F2 + F3.
- Recovery / stuck-goal documentation (`references/recovering-stuck-goals.md`).
- Consolidated cost-comparison table for the three Stop-hook modes in a single page.
- `/flow:watch` post-creation `AskUserQuestion` confirmation step.
- Polyglot Windows wrapper for hook scripts (separate cleanup PR).
- Per-skill / per-command unit tests for workflow / run-state / trigger surfaces.
- `context: fork` audit across the remaining 13 ambient-only skills (`architecture-patterns`, `brainstorming`, `branch-and-task-management`, `change-classification`, `code-review-methodology`, `convention-enforcement`, `criterion-verification-map`, `debugging-patterns`, `feedback-resolution`, `goal-evidence-ledger`, `merge-conflict-resolution`, `run-state-management`, `tdd-patterns`) — fork is dormant for these because they're only loaded via `## Required Skills` (no `Skill(X)` invocations); each body must be individually classified before any fork-removal action.
- Auto-log compaction (50+ `<!-- auto-log: -->` lines per session reduced to one rolled-up entry per phase).
- Review fan-out extracted as a shared skill (`/flow:pr` Phase 3 and `/flow:review` Path B currently duplicate the 5-agent dispatch).
- Cross-cycle pattern linker for findings (finding-id stability + "same pattern as cycle N-1" detector).
- Structured Tier 3 override-with-rationale option in `/flow:merge` and `/flow:release`.
- Journal `## Lessons Learned` section appended at `/flow:merge` or `/flow:learn`.
- Defense-in-depth: hard-fail when a `Skill(X)` invocation returns empty / "what would you like me to do?" instead of silently accepting the skip.

---

## 2.4.0 (2026-05-19)

### Behavior change — LLM Operator Principles

The flow plugin now treats Claude as an LLM operator that does not tire. Three structural shifts close the deferral and time-estimation patterns observed in v2.3.x usage despite the existing "P3 not deferrable" policy.

#### New skill: `llm-operator-principles`

A new foundational skill at `skills/llm-operator-principles/SKILL.md` is consulted by every `/flow:*` command. It encodes:

- **Convergence = zero findings, not exhausted budget.** Iteration ceilings are safety nets, not budgets.
- **In-PR fix by default for all findings.** Finding triage (P1/P2/P3 disposition) is NEVER a valid escalation trigger.
- **Calendar-time estimates prohibited.** PR bodies, decision-journal entries, escalations, and resolution comments MUST NOT include weeks/days/hours/sprints/ETAs.
- **Multi-PR sequencing is the user's call.** Default to one PR that resolves all findings.

#### Settings changes

- `fixForwardMaxIterations` default raised from `2` to `10`
- `reviewCycleLimit` default raised from `3` to `10`
- New flag `autonomous` (default `false`) — when `true`, removes `AskUserQuestion` interruptions for any decision the agent can resolve under the operator principles. Recommended for sole-maintainer repositories.
- New flag `minimalScope` (default `false`) — when `true`, restores the original follow-up-issue workflow for cosmetic P3 in untouched files only. P1/P2 findings still fix in-PR even in this mode.

#### Command changes

- `commands/address.md`, `commands/review.md`: the "Create a follow-up issue?" `AskUserQuestion` prompts are removed in default mode. Cosmetic P3 in untouched files is fix-if-bounded (<10 lines) or documented inline in the PR body. `minimalScope: true` restores the original workflow.
- `commands/pr.md`: removed the "after 2 fix iterations, remaining P2 become Known issues" deferral path. P2s are fixed until zero remain.
- All six commands (`start`, `address`, `pr`, `review`, `commit`, `merge`) reference `llm-operator-principles` as the first required skill.

#### Reference changes

- `references/escalation-format.md`: the `Time sensitivity` field is replaced by a `Blocking?` field (yes/soft/no, no calendar verbs). Finding triage is explicitly added under "When escalation IS NOT required."
- The same anti-deferral and anti-estimation language is propagated to `skills/code-quality-principles`, `skills/feedback-resolution`, `skills/code-review-methodology`, `skills/evidence-based-development`, `skills/autonomous-workflow`, `skills/specification-capture`, and `commands/commit.md`.

#### Template changes

- `templates/pr-body.md`: HTML-comment guard forbids calendar-time estimates in any field.

#### Migration

**Behavior change for unpinned configs.** Existing `.claude/settings.flow.json` files that explicitly pinned `fixForwardMaxIterations` or `reviewCycleLimit` to the old defaults (2 / 3) keep their pinned values — the cascade honors local settings. Configs that did not pin these keys (relying on plugin defaults) will see the new 10 / 10 ceilings on first run. Review against the new safety-net framing: ceilings are no longer planned stop points; reaching them is the signal that you have hit **genuine non-convergence** (see `skills/llm-operator-principles/SKILL.md` § Genuine non-convergence).

To restore v2.3.x behavior, set in `.claude/settings.flow.json`:

```json
{
  "fixForwardMaxIterations": 2,
  "reviewCycleLimit": 3,
  "minimalScope": true
}
```

#### Additional changes from in-PR self-review (fix-forward on PR #107)

The first run of `/flow:review` under the new operator principles surfaced five findings; all were fixed in-PR per the new defaults (no deferral). Notable additions:

- `bin/flow-escalate.sh` — `--blocking` now enforces a `yes|soft|no` value space. Without this guard, a caller passing `--blocking "by Friday"` would defeat the calendar-time-rename's purpose. Test 8 covers the enforcement (5 invalid + 3 valid values).
- `bin/flow-escalate.sh` — trailing-flag detection via `require_value` helper. A trailing flag like `flow-escalate.sh ... --blocking` (no value following) now produces "`--blocking requires a value`" instead of the misleading missing-fields message. Test 9 covers this path.
- `skills/llm-operator-principles/SKILL.md` and `commands/address.md` — new "Genuine non-convergence" guidance defining the ONE case where an iteration ceiling becomes a stop point: same findings persist 3 iterations in a row AND `fixForwardMaxIterations` is reached. Closes the silent-failure gap where the LLM could either silently exceed the ceiling or exit with unresolved findings.

Closes #106.

## 2.3.1 (2026-05-08)

### Bug fixes

- **Plugin settings cascade unified to standard Claude Code precedence (#101).** Originally reported as "Path A paired-reviewer gate unreachable for marketplace installs": `commands/review.md`'s `agentTeams` gate read `${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json` only, and `CLAUDE_PLUGIN_ROOT` is not exported into the bash subshell that runs the gate, so the fallback resolved to a directory that doesn't exist in the user's repo. The same broken single-source pattern was present in five other consumer sites (`commands/merge.md`, `commands/status.md`, `bin/journal-record.sh`, three hook scripts, and `agents/convention-checker.md`).

  The original threat model justifying the "trimmed cascade" — a hostile fork PR committing `.claude/settings.flow.json` to escalate gates after `gh pr checkout` — was overengineered. Claude Code's standard convention is to honor the full settings cascade and let reviewers see settings changes in the PR diff like any other repo file. The fix replaces the trimmed-cascade pattern with the standard Claude Code precedence (highest first):

  1. `.claude/settings.flow.local.json` — project-local, gitignored (your machine-local pin)
  2. `.claude/settings.flow.json` — project-shared, committed (team defaults)
  3. `$HOME/.claude/settings.flow.json` — user-global, cross-project default
  4. `${CLAUDE_PLUGIN_ROOT}/settings.json` — plugin default

  First non-empty value wins. Applies uniformly to every flow setting — no special-cased exclusion for any key.

  Files updated: `commands/review.md` (agentTeams gate), `commands/merge.md` (markerTrust gate), `commands/status.md` (markerTrust + journal.dir), `commands/learn.md` (journal.dir + learning.proposalDir), `commands/explain.md` (journal.dir), `agents/convention-checker.md` (conventions.commitTypes), `bin/journal-record.sh` (journal.dir), `hooks/scripts/{log-commits,log-file-changes,session-end-learn}.sh` (journal.dir + learning.enabled).

  The two-key gate for `agentTeams` is preserved at the env-var layer: enabling Path A still requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` set in the user's shell on top of `agentTeams: true` from any source. The env var alone (no `agentTeams: true` anywhere) cannot enable Path A.

  `agentTeams` gate gained a three-state diagnostic distinguishing (a) plugin not installed, (b) `CLAUDE_PLUGIN_ROOT` set but pointing at a missing path, (c) all four cascade files exist but none sets the key. Each variant names the exact paths checked.

  `merge.md` and `status.md` markerTrust gates now surface JSON parse errors per-source (matching the agentTeams gate pattern) — `WARN: failed to parse $SETTINGS_PATH (jq exit=$JQ_EXIT, error: ...)` rather than silently swallowing parse errors and treating them identically to "key absent."

- **`commands/setup.md` rewritten to align with the standard cascade.** Previous setup wrote `agentTeams` and `conventions.commitTypes` into the project-shared file but then those keys were excluded by the trimmed-cascade pattern. With the cascade unified, all flow keys are valid in `.claude/settings.flow.json` and team-shareable. Phase 2 now writes the full default set including `agentTeams: false`, `conventions.commitTypes`, `merge.markerTrust.allowedAssociations`, `journal.dir`, and `learning.proposalDir`. Phase 6 summary describes the four-tier override hierarchy users can use to customize.

- **`${HOME:-/nonexistent}` defensive default** applied at every USER_SETTINGS construction site (15+ loops across .md commands, .sh hooks, and bin/ scripts). Catches `set -u` / `env -i` invocations where `$HOME` could otherwise abort the gate with "unbound variable" instead of degrading to the safe "user-tier file does not exist" path.

### Documentation

- `references/gate-configuration.md` — replaced the "Trimmed-Cascade Settings Keys" section with a "Settings Cascade" section documenting the standard four-tier precedence. The `merge.markerTrust.allowedAssociations` row in the gate config table updated. New worked examples for "Persistent personal opt-in" (using `.local.json` or `$HOME`) and "Team-wide opt-in" (using committed `.json`).

### P3 cleanup (cycle 2 review pass — pre-merge)

Address the P3 findings raised during the cycle-2 self-review before landing:

- **F4/ERR-8 — `agentTeams: null` semantic.** A user writing `"agentTeams": null` likely means "use the default", not "definitively no". The gate now treats `null` as absent (falls through to next source) rather than triggering the `non-canonical value` WARN. New test S7b verifies this.
- **F5 — gate-configuration.md ordering inconsistency.** The "Settings File Locations" section listed cascade with plugin first / local last; the new "Settings Cascade" section uses highest-first ordering. Aligned both to the highest-first form so the document is internally consistent.
- **F6 — three-state diagnostic gap.** When `CLAUDE_PLUGIN_ROOT` was set to a missing path AND user-tier files existed without the key, the gate fell into the catchall message and never named the broken plugin root. Now tracks `PLUGIN_ROOT_BROKEN` explicitly and emits a WARN naming the path even when user-tier files are present. New test S9 verifies this.
- **SEC-1 — high-risk markerTrust values warn at gate time.** When the resolved trust list contains `NONE`, `FIRST_TIMER`, `FIRST_TIME_CONTRIBUTOR`, or `MANNEQUIN`, the gate emits `LEDGER_WARN: trust list ... includes high-risk values [...]` on stderr at every merge attempt. PR-diff visibility remains the primary defense; the WARN raises the signal so a maintainer cannot accidentally miss it. New test S4b verifies this.
- **SEC-3/ERR-6 — `journal.dir` path-traversal warn.** When the resolved `journal.dir` contains `..` path segments, `bin/journal-record.sh` emits a WARN to stderr. Defense-in-depth — the cascade visibility is the primary defense, but a `journal.dir: "../../tmp/x"` value would silently write artifacts outside the repo without this WARN.
- **ERR-5 — `gh api` exit-code coverage in `commands/merge.md`.** The untrusted-counting `gh api` calls didn't capture their exit codes via `${PIPESTATUS[0]}`. A network blip during those secondary calls would silently treat as "no untrusted markers" rather than failing closed. Now captures `GH_EXIT_RES_U` and `GH_EXIT_REV_U` and includes them in the fail-closed condition.
- **ERR-9 — `commitTypes` array type-check.** `agents/convention-checker.md` previously crashed jq's `join("|")` step if `commitTypes` was a non-array (e.g., string typo). Now wraps in `if type == "array" then join("|") else empty end` so non-array values silently fall through to the next cascade source.
- **ERR-4 — extracted shared cascade-resolve helper.** New `plugins/flow/bin/cascade-resolve.sh` (with 12 regression tests at `tests/cascade-resolve/test.sh`) reads any settings key from the standard cascade with parse-error WARN surfacing on stderr. Refactored 9 simple cascade-loop sites (3 markdown commands, 1 agent, 1 bin script, 3 hook scripts, 1 hooks site reading two keys) to call the helper. The 2 security-critical gate sites (`commands/review.md` agentTeams gate, `commands/merge.md` markerTrust gate) keep their inline implementations because they need source-tracking and specialized boolean handling. Removes the diagnostic asymmetry where 9 sites silently swallowed parse errors via `2>/dev/null` while the gate sites surfaced them.

### Self-review fix-forward (cycle 2 review pass)

- **P1 — `commands/merge.md` markerTrust fall-through emitted `FINDING_LEDGER_BLOCK:` on stdout.** When one tier had an invalid `markerTrust.allowedAssociations` (e.g., empty array) AND the gate fell through to a valid lower tier with a working trust list, the gate still printed `FINDING_LEDGER_BLOCK:` on stdout. The downstream merge gate scans stdout for that prefix and would treat this as a hard block — even though the cascade fall-through resolved a valid trust list. Fixed: emit `LEDGER_WARN:` on stderr instead of `FINDING_LEDGER_BLOCK:` on stdout when fall-through succeeds. The `FINDING_LEDGER_BLOCK:` prefix is now reserved for cases where the merge gate genuinely cannot proceed (gh API down, ESCALATED markers, untrusted-only markers).
- **P2 — `commands/review.md` agentTeams gate used `jq -r`** which strips JSON string quotes. A typo like `{"agentTeams": "true"}` (quoted string instead of boolean) would silently match the `case true)` arm and enable Path A. Fixed: use `jq -c` so the quoted string remains `"true"` and routes to the catchall `*)` WARN. Updated test S8 verifies this.
- **P2 — `commands/setup.md` did not add `.claude/settings.flow.local.json` to `.gitignore`.** A downstream user running `/flow:setup` in a fresh repo would create their personal-pin file at the documented location and have it staged for commit by default — defeating the cascade's "project-local is gitignored, your machine-local pin" property. Fixed: setup now appends the entry to `.gitignore` (idempotent — only if missing).
- **P2 — `commands/setup.md` could silently override user-global preferences.** Under the unified cascade, project-shared overrides user-global. Setup writing `agentTeams: false` (or any other key matching the plugin default) would silently override a user's `$HOME/.claude/settings.flow.json` preference. Fixed: setup reads user-global first and surfaces conflicts via `AskUserQuestion` before writing, with three options (skip the key / write team baseline anyway / cancel).

### New regression tests

- `tests/agentteams-gate/test.sh` (new, 20 assertions) extracts the gate body from `commands/review.md` via `# AGENTTEAMS_GATE_BEGIN` / `# AGENTTEAMS_GATE_END` markers and runs it against scenarios for: marketplace install with `$HOME` override, upgrade survival, project-tier overrides plugin default (S3), project-local overrides project-shared (S3b), full precedence chain (S3c), three-state diagnostic, malformed-HOME fall-through, env-var double-key requirement, and JSON-string vs boolean coercion (S8). The harness runs `bash -n` against the extracted body so a corrupted END marker FATALs instead of silently partial-eval'ing.
- `tests/markertrust-gate/test.sh` (new, 15 assertions) covers the same scenarios for `merge.markerTrust.allowedAssociations`, including project-local-overrides-project-shared precedence and the empty-array fall-through. S4 specifically asserts the gate emits `LEDGER_WARN` on stderr (not `FINDING_LEDGER_BLOCK` on stdout) when an invalid array falls through to a valid lower tier. S4b verifies the high-risk-trust-value WARN.
- `tests/cascade-resolve/test.sh` (new, 12 assertions) verifies the four-tier cascade behavior, parse-error WARN surfacing, default-value handling, and compact-vs-raw output mode of the new `bin/cascade-resolve.sh` helper.

### Test totals

110 assertions across 9 suites (was 89 in 2.3.0). The cycle-2 cascade work added two new gate-test suites (24 + 15 = 39 assertions) and the new cascade-resolve test suite (12 assertions); the older suites kept their counts.

## 2.3.0 (2026-05-06)

### Post-review hardening — cycle 2 (PR #99 `/flow:review` second pass)

A second adversarial review (parallel `code-reviewer` + `security-reviewer` + `convention-checker` + cross-reference auditor) found four reproducible exploit primitives the cycle-0 and cycle-1 passes missed, all post-`gh pr checkout`-of-hostile-fork. Reproduced inline; fixes shipped here.

- **SEC-1: sys.path injection (RCE).** `python3 -c "import yaml"` and `python3 - <<'PYTHON'` heredocs in `bin/journal-record.sh`, `bin/promote-proposal.sh`, and `bin/validate-skill-input.sh` had `sys.path[0] = ''` (CWD). After `gh pr checkout` of a hostile fork, an attacker-shipped `./yaml.py` (or `./jsonschema.py`) at the repo root would shadow the real package on import — full RCE under the user's UID before any of our other defenses ran. Fix: `export PYTHONSAFEPATH=1` near the top of each script (Python 3.11+ honors the env var), plus a defensive `sys.path[:] = [p for p in sys.path if p not in ("", ".")]` filter inside every inline heredoc as a fallback for older Pythons.
- **SEC-2: journal-file symlink read (file exfiltration).** Cycle 1 added `[ -L "$LOCKFILE" ]` defense on the lockfile but the journal file itself was opened with Python's `open()`, which follows symlinks. Attacker pre-stages `.decisions/issue-N.md` → symlink to `~/.ssh/id_rsa` (or `~/.aws/credentials`, `~/.config/gh/hosts.yml`); user runs `/flow:start N`; secret content is read into the new journal body and committed/pushed. Fix: read via `os.open(O_RDONLY | O_NOFOLLOW)` in the inline Python block — open fails atomically with ELOOP if the path is a symlink.
- **SEC-3: hook symlink append (file tampering).** `hooks/scripts/log-commits.sh` and `log-file-changes.sh` write auto-log lines via `>> "$JOURNAL_FILE"`; bash `>>` follows symlinks. Attacker pre-stages `.decisions/issue-N.md` → symlink to `~/.bashrc` or any user-writable file; PostToolUse fires after every Edit/Write/git-commit Claude makes; each invocation appends `<!-- auto-log: ... -->` to the symlink target. Fix: `[ -L "$JOURNAL_FILE" ] && exit 0` before each `>>` redirect in both hooks.
- **F1: lockfile TOCTOU (regression in cycle-1 fix).** The cycle-1 lockfile defense was `[ -L "$LOCKFILE" ]` followed by `exec 9>"$LOCKFILE"` — a TOCTOU window an attacker could exploit by planting a symlink between the check and the redirect. Fix: move the lockfile open into Python and use `os.open(LOCKFILE, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)` for atomic ELOOP rejection; use `fcntl.flock` on the resulting fd. The bash-layer `[ -L ]` check is now redundant and removed.

Defense-in-depth and quality fixes shipped alongside:

- **SEC-7: HTML-comment injection via attacker-controlled commit subject.** `hooks/scripts/log-commits.sh` interpolated `$LAST_MSG` (latest commit subject from a hostile fork) into an `<!-- auto-log: ... -->` comment. A subject containing `-->` would close the comment early; subsequent markdown would land in the journal that `/flow:explain` and `/flow:review` later feed back to Claude — prompt injection. Same pattern in `log-file-changes.sh` for `$TOOL_NAME` and `$FILE_PATH`. Fix: substitute `-->` → `-- >` and `<!--` → `< !--` before embedding in both hooks.
- **SEC-5: `bin/promote-proposal.sh` dangling-symlink write.** `[ -e "$TARGET" ]` follows symlinks, so a *dangling* attacker-pre-staged symlink at `plugins/flow/skills/learned/<name>/SKILL.md` passes the existence check; subsequent `cp` writes through to an arbitrary user-writable path. Fix: explicit `[ -L "$TARGET" ]` check before the existence check, refusing both states.
- **SEC-8: YAML newline injection in journal metadata.** `bin/journal-record.sh --metadata key=$'value\nline2'` would let `yaml.safe_dump` emit a multi-line block scalar; with a `:` in the value, downstream readers could re-parse as multiple keys. Fix: bash-level `case` to reject newline/CR in metadata pairs at parse time, with a corresponding regression test.
- **F1 atomic-write durability (related).** Added `f.flush() + os.fsync(f.fileno())` before `os.rename` and a best-effort directory `os.fsync` after, so a power loss between rename and durable write cannot leave a zero-length journal behind. Comment updated to match.
- **F2: `runtime-verification` documentation orphan.** `visualVerification.maxIterations` was documented in both `runtime-verification/SKILL.md` and `visual-verification/SKILL.md`. Removed from the runtime skill (which delegates to visual when both run together); single source of truth restored.
- **F4: trimmed-cascade keys not documented.** Added a "Trimmed-Cascade Settings Keys" subsection to `references/gate-configuration.md` listing `journal.dir`, `learning.proposalDir`, and `conventions.commitTypes` with their threat models — the same treatment `merge.markerTrust` already had.
- **F6: `commands/status.md` cascade-coverage gap.** `JOURNAL_DIR` was hardcoded `.decisions`. Now reads the same trimmed cascade as the other eight consumers; users with a non-default `journal.dir` will see correct counts.

### New regression tests (cycle 2)

- `tests/journal-orchestration/test.sh` grew 16 → 22 assertions covering SEC-1 (attacker yaml.py at CWD does not load), SEC-2 (journal symlink rejected with secret-content non-leak verified), SEC-8 (newline metadata rejected), and F1 (lockfile symlink rejected atomically).
- `tests/hooks-symlink/test.sh` (new, 6 assertions) covers SEC-3 (both hooks refuse symlink writes; symlink target content unchanged) and SEC-7 (`-->` neutralized in commit subject before journal embedding).

### Test totals

89 assertions across 8 suites (cycle 0: 75; cycle 1: 77; cycle 2: 89). All pass. The cycle-2 totals replace earlier "75" and "77" references in the PR body.

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
