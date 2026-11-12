Flow plugin lifecycle map, read at commit aab0d132, flow 3.16.0 (from `plugins/flow/.claude-plugin/plugin.json`). This was a read-only pass. Citations give the path plus the heading or step name; line numbers appear only where I took them from an unsliced file. All paths are relative to `/Users/danielbentes/synapti-marketplace/plugins/flow/`.

## 0. Cross-cutting mechanics

**Three-tier safety, defaults in `settings.json`:**
- **Tier 1 (autonomous):** branch, edit, commit, local tag.
- **Tier 2:** push, prCreate, issueAssign and issueCreate default to `journal`. The action runs and a breadcrumb is written to the git-ignored auto-log. Each can be set to `autonomous` or `confirm`.
- **Tier 3:** merge and release are `confirm` and have a floor. `hooks/scripts/tier-gate.sh` enforces this on every Bash call, wired as PreToolUse in `hooks/hooks.json`. Background: `references/three-tier-safety.md`.

**Ask policy (`references/ask-policy.md`, `hooks/scripts/ask-policy.sh`):**
- `autonomous: false` (the default) asks every question.
- `autonomous: true` auto-takes `[ask: default]` sites and journals each as `default-taken`.
- `[ask: decision]` and `[ask: permission]` sites still ask under both policies. They carry `metadata.source = flow:decision` or `flow:permission`. The hook denies every other `AskUserQuestion` in the session.
- Escalations are stored as records with id and status in `bin/flow-question.sh` (add/answer/withdraw/list). `/flow:resume` can re-ask them later. Format: `references/escalation-format.md` (six fields: Situation, Tried, Options, Recommendation, Blocking, Risk).

**Decision journal (`.decisions/issue-N.md`, or `session-YYYY-MM-DD.md` on a branch with no issue):**
- Free-form sections plus manifest artifacts written by `bin/journal-record.sh`.
- Artifact types (`references/decision-journal-schema.md`): specification, design, stranger-test, review-cycle, dropped-finding, finding-dismissed, design-decision, brainstorm-decision, verdict, default-taken, escalation-asked/resolved, workflow-run, goal-created, goal-evaluation, trigger-fired, evidence-captured.

**Runtime state (`.flow/`, `references/flow-runtime-state.md`):**
- FlowGoal: `.flow/goals/<id>.goal.yaml`.
- FlowRun: `.flow/runs/<id>/run.yaml` plus `events.jsonl`.
- FlowEvidence sidecars: `.flow/runs/<id>/evidence/*.evidence.yaml` plus raw `.txt`, written by `bin/flow-record-evidence.sh` (`skills/goal-evidence-ledger/SKILL.md`).
- `runs/` is not committed (`flow-runtime-state.md:51`).

**Evidence bundle (`references/evidence-bundle-format.md`):**
- One markdown document per branch, one `## Criterion N` per acceptance criterion. Each section has Verification command, Output, Visual analysis, Does NOT promise, Risk map coverage, and so on.
- In `commands/start.md` Phase 4 steps 5–6, the bundle is assembled in-session and handed to the verdict judge through `mktemp` files outside the repository.
- That command text names no repository path where the bundle is kept. What persists durably is the `verdict` journal artifact plus the `.flow` evidence sidecars.

**Hooks (`hooks/hooks.json`):**
- PreToolUse Bash: block-force-push, block-destructive, block-unchecked-merge, block-secrets, ask-issue-create, tier-gate.
- PreToolUse AskUserQuestion: ask-policy.
- PostToolUse: log-file-changes, log-commits, record-quality-run, s1-screen-text.
- TaskCompleted: verify-task-completion (`testing.taskCompletionGate: block`).
- Stop: `flow-goal-stop.sh`. It defaults to `stopHookEnforcement: warn`, which never blocks the stop (`references/stop-hook-goal-enforcement.md` § warn).
- SessionEnd: learn and state.

**FlowWorkflow YAMLs (`workflows/*.workflow.yaml`, `references/flow-workflows.md`):**
- Seven YAMLs: start-issue, review-pr, address-pr, merge-pr, release, debug, design.
- They are inspectable contracts checked by `/flow:workflow validate`, not an executor. "The command markdown remains Claude's execution manual." The `completion_gate` field is advisory only.
- validate hard-fails if merge, release or tag_push is not `confirm`.

**Agents (`agents/`):**
- implementation-planner; code-reviewer, security-reviewer, convention-checker, test-runner and error-handler-inspector (the review fan-out); integration-verifier; finding-critic (grounding pass, `review.groundingCritic` defaults to off).
- verdict-judge, run by `bin/flow-judge.sh --judge verdict` through the claude CLI with all tools disallowed.
- goal-evaluator-judge.

**How skills load:** each command's `## Required Skills` is inlined by `bin/flow-load-skills.sh`.
- Dispatched skills, per their frontmatter: specification-capture (`agent: general-purpose`), holdout-validation (`agent: general-purpose`), and code-review-methodology (`context: fork`, `agent: Explore`).
- branch-and-task-management, criterion-verification-map and goal-evidence-ledger are `context: fork`.
- `autonomous-workflow` is not in any command's Required Skills list or in any workflow YAML. A grep finds it referenced only from `skills/branch-and-task-management/SKILL.md:57`, for the journal entry format. It is an ambient or reference skill, not a loaded phase driver.
- System One (an optional external model at decision points) is off by default (`settings.json` `systemOne.provider: none`). One line covers it.

## 1. Per-command map

### /flow:issue (`commands/issue.md`)
- **Phases:** EXPLORE → PLAN (duplicate search over open and closed issues, label discovery) → CODE (body from `templates/issue-body.md`: Context / Current State / Objective / Acceptance Criteria) → VERIFY.
- **Skill:** issue-crafting.
- **Human:** `[ask: decision]` for missing elements of the description, and when duplicates are found.
- **Autonomous:** `gh issue create` is Tier 2 journal. While a FlowGoal is active and `minimalScope` is false, `ask-issue-create.sh` asks.
- **Artifact:** the GitHub issue. Next step suggested: `/flow:start <N>`.

### /flow:brainstorm (`commands/brainstorm.md`)
- **Phases:** EXPLORE → GENERATE (2–4 approaches) → COMPARE → DECIDE.
- **Skills:** brainstorming, capability-discovery, specification-capture. Non-goals are read or captured when an issue is in scope.
- **Human:** `[ask: decision]` to clarify a vague goal, and `[ask: decision]` to pick the approach.
- **Artifacts:** `## Brainstorm Decision` in the journal plus a `brainstorm-decision` manifest entry.

### /flow:design (`commands/design.md`)
- **Phases:** EXPLORE → PLAN → REVIEW → DECIDE.
- **Skills:** architecture-patterns, capability-discovery, specification-capture.
- **Human:** `[ask: decision]` "Recommended design … Approve?" in Phase 4 DECIDE.
- **Artifacts:** `## Design Decision` in the journal plus a `design-decision` manifest entry.
- **Related step inside start:** `/flow:start` also runs its own design step when its risk check reports `RISK=high` (`references/design-step.md`). That step writes `## Design` with options, `Does not add` and `Invariants`.

### /flow:start <issue> (`commands/start.md`): the main autonomous pipeline
**Phase 0 PRE-FLIGHT:** pure-bash checks (preflight-checks): issue number, clean tree, not detached. Prints `ASK_POLICY`.

**Phase 1 EXPLORE:**
- `Agent(Explore)` and `Skill(capability-discovery)` run in parallel.
- Acceptance-criteria parse. With zero criteria and `specFirst.requireAcceptanceCriteria: true`, it asks `[ask: decision]`: write criteria / spec-free (only for `documentation`/`chore` labels) / cancel.
- Risk check, which runs the design step when `RISK=high`.
- `Skill(specification-capture)` (`[ask: decision]`, with per-element confirmation) writes `## Specification`: non-goals, failure modes, interface contracts, and a risk map of 2–6 rows. A `specification` manifest entry follows.
- **Spec Validation Gate (blocking):** every criterion must map to a runnable verification command. A criterion that BLOCKs triggers a six-field `[ask: decision]` escalation, with `manual` allowed only by the user.
- Issue assignment (Tier 2).
- FlowGoal auto-created (`goalCreation: auto`, when at least one criterion has a command) through goal-contract-capture, then goal-lifecycle draft→active, verified after the write.
- FlowRun created.

**Phase 2 PLAN:**
- Branch `feature/issue-N-…` (Tier 1). Journal initialised.
- `Agent(implementation-planner)` produces atomic tasks (implementation + test + evidence command) through TaskCreate with dependencies.
- **Stranger Test gate:** if any task fails it, the agent rewrites the task or escalates `[ask: decision]`. Recorded as `## Stranger Test` plus a `stranger-test` artifact.
- The plan is displayed and the command "Proceed[s] unless user objects."

**Phase 3 CODE:** per task, in this order:
1. TDD RED/GREEN/REFACTOR (`testing.tddMode: enforce`).
2. Debug-fix-retest loop, bounded by `closedLoop.maxDebugIterations`. `[ask: decision]` only on genuine non-convergence.
3. Evidence capture.
4. Per-task change classification. `[ask: default]` for uncertain files, auto-handled under the autonomous policy.
5. Clone scan.
6. Incremental commit (Tier 1).

The TaskCompleted hook gates completion.

**Phase 4 VERIFY:**
- Steps 1–4:
  1. Quality suite.
  2. `Skill(runtime-verification)`, mandatory. A skip outside its whitelist is `[ask: permission]`.
  3. `Agent(code-reviewer)` self-review with fix-forward (≤ `fixForwardMaxIterations`, default 10).
  4. `Skill(holdout-validation)`.
- Step 5: per-criterion evidence is collected again and the evidence bundle is assembled.
- Step 6: independent verdict judge returns PASS / FAIL / NEEDS-HUMAN-REVIEW. With `verdict.requireAllPass: true`, NHR counts as FAIL and enters the fix loop. When `requireAllPass: false`, NHR is `[ask: decision]`. A FAIL that does not converge is `[ask: decision]`.
- `verdict` artifact. Visual-verification BLOCKED is `[ask: permission]`.
- Step 9a: goal evaluation (deterministic checks plus the verdict) is recorded in `lifecycle.last_evaluation`.

**Completion:** it suggests `/flow:pr`. It does not invoke it.

### /flow:debug (`commands/debug.md`)
- **Phases:** EXPLORE → PLAN → CODE → VERIFY.
- **Skills:** debugging-patterns, change-classification, goal-contract-capture, goal-evaluator, goal-lifecycle, run-state-management.
- **Process:** hypotheses (at most 3 at a time), then a reproducing RED test, then the fix.
- **Artifacts:** a FlowGoal is created after the hypothesis is confirmed. FlowRun `debug`.
- **Human:** the FlowGoal evaluation and terminal transition are `[ask: permission]` (VERIFY step 6).
- **Next:** it suggests `/flow:commit` and `/flow:pr`.

### /flow:pr (`commands/pr.md`)
- **Phase 1 EXPLORE:** branch/delta preflight, FlowGoal state (`GATE=pass|block`), review exceptions.
- **Phase 2 PLAN:** review TaskCreates.
- **Phase 3:** parallel fan-out of code-reviewer, convention-checker, test-runner, security-reviewer and error-handler-inspector, plus `Skill(holdout-validation)`.
- **Phase 4 VERIFY:**
  - Synthesis.
  - Optional grounding pass.
  - integration-verifier (runtime and visual). `CLOSED_LOOP=off` makes this step `[ask: default]`.
  - LOW-confidence findings are investigated, `[ask: decision]` when unresolvable.
  - Fix-forward of P1/P2.
  - Step 7a: FlowGoal gate. When the goal is not achieved, `[ask: permission]`; an override is journaled as `escalation-resolved`.
  - Step 8: PR body from `templates/pr-body.md` plus a comprehension report.
  - Step 9: push (Tier 2). Step 10: `gh pr create` (Tier 2).
  - Step 11: suggest reviewers. Step 13: `review-cycle` artifact.
- **FlowRun:** it is "the tail of the `start-issue` workflow" and creates no FlowRun of its own.

### /flow:review <pr> (`commands/review.md`)
- **Path B (default):** 5 agents plus holdout.
- **Path A:** paired adversarial agent teams (A.1–A.6). Requires `agentTeams: true` and the experimental env flag.
- **Phase 4:**
  - Synthesise, ground and route findings through `bin/flow-finding-route.sh`.
  - **Own PR:** self-review fix-forward. Unreproducible LOW findings are `[ask: decision]`.
  - **External PR:** LOW findings go to "Needs investigation"; follow-up issues for cosmetic P3 only under `minimalScope`, as `[ask: default]`.
  - Step 7: mandatory posting of a review with a `<!-- FLOW_REVIEW_CYCLE:N FINDINGS:[…] -->` marker, plus `FLOW_RESOLUTION_CYCLE` on self-review. These posts are Tier 2 with no tier setting: they run without asking.
- **Next:** suggests `/flow:pr` (own PR) or `/flow:address` (external).

### /flow:address <pr> (`commands/address.md`)
- **Phase 1:** fetch comments.
- **Review Cycle Tracking:** cycle = count of `CHANGES_REQUESTED` reviews. Cycle-based strategy and "fix the class".
- **Phase 2:** categorise (feedback-resolution).
- **Phase 3:** surgical TDD fixes plus a Boy Scout pass. P1/P2 in untouched files are fixed in the PR, never escalated (`[ask: none]`).
- **Phase 4 convergence:**
  - Quality.
  - Full fan-out self-review.
  - Holdout.
  - Convergence check, ≤10 iterations. Genuine non-convergence is `[ask: decision]`.
  - Push (Tier 2).
  - Inline replies, the resolution comment (`templates/resolution-comment.md`, carrying `FLOW_RESOLUTION_CYCLE`), the PR body update and the re-request for review all run without asking.
  - Step 12: when the cycle reaches `reviewCycleLimit` (10), deadlock is `[ask: decision]`.
- **FlowRun:** `address-pr` is marked completed.

### /flow:merge <pr> (`commands/merge.md`): Tier 3
**Phase 1 gates, all fail-closed:**
- Finding-ledger check (`FLOW_REVIEW_CYCLE` / `FLOW_RESOLUTION_CYCLE`; `references/finding-ledger-parser.md`; `merge.markerTrust` limits which commenters count).
- FlowGoal gate: blocks unless `lifecycle.status == achieved`.
- Linked-run completion check: all start-issue, address and review runs completed.
- Merge settings.

**Phase 2:** assessment. Required Checks row; `--auto` is refused where nothing is required. Conflicts are `[ask: default]` and auto-routed to `/flow:resolve` under the autonomous policy.

**Phase 3:** description-staleness check, then `[ask: permission]` "Proceed with a {strategy} merge?". This asks "even when `autonomous: true`". `tier-gate.sh` asks a second time. `block-unchecked-merge.sh` refuses the merge while checks are pending or failed.

**Phase 4:** post-merge cleanup and FlowRun completed. Suggests `/flow:release`.

### /flow:release <type> (`commands/release.md`): Tier 3, two runs
- **Phases:** Gather → Release State/Version → Changelog → Act → Post-Release.
- **`RELEASE_RUN=pr`:** no AskUserQuestion. Release branch, bump, commit, push (Tier 2), release PR (Tier 2).
- **Between runs:** the release PR must be merged, which means `/flow:merge` and its Tier 3 confirmation.
- **`RELEASE_RUN=tag`:** `[ask: permission]` "Create release {TAG}…?", then tier-gate asks again for the tag push plus `gh release create`.
- **`RELEASE_RUN=publish`:** for a tag already on origin, the same two prompts.

### Router, resume, watch and triggers
- **`/flow` router** (`commands/flow.md`): routes a verb to one subcommand only.
- **`/flow:resume`:** "never auto-executes the next phase" (`commands/resume.md`).
- **`/flow:watch` and FlowTrigger** (`references/flow-triggers.md`): "Flow CANNOT invoke `/loop` from plugin code". The user starts the loop by hand.
- **`flow.triggers.allowAutonomousMerge`** (default false, user settings only) only lets a trigger policy omit merge/release from `forbidden_actions`. Even when it is true, "`/flow:merge` and `/flow:release` ask first, and the tier hook asks again" (`flow-triggers.md:71`).

## 2. End-to-end path from idea to release, and where a human acts

1. `/flow:issue`: human answers description and duplicate decisions. Issue creation is Tier 2 journal.
2. `/flow:brainstorm` and/or `/flow:design` (optional): human picks the approach and approves the design.
3. Human invokes `/flow:start N`. Human input is needed for:
   - missing acceptance criteria
   - spec-capture confirmations
   - any criterion that BLOCKs the Spec Validation Gate
   - a Stranger Test BLOCK the agent cannot close
   - debug non-convergence
   - verdict FAIL or NEEDS-HUMAN-REVIEW that does not converge
   - a runtime or visual verification skip

   Everything else is autonomous: branch, TDD, commits, review, holdout, verdict and goal evaluation. Uncertain-file questions are auto-taken only under `autonomous: true`.
4. Human invokes `/flow:pr`. Push and PR creation are journal-tier and autonomous. Human input only for the goal-gate override or a visual BLOCKED result.
5. A reviewer, human or `/flow:review` invoked by a human, posts `FLOW_REVIEW_CYCLE`.
6. Human invokes `/flow:address N`, repeated until the review converges. Human input only at review-cycle deadlock or non-convergence.
7. Human invokes `/flow:merge N`. **A human must confirm, twice:** AskUserQuestion, then tier-gate. No setting removes this.
8. Human invokes `/flow:release type`. Run 1 opens the release PR. The release PR then needs its own `/flow:merge`, a human Tier 3 confirmation. Run 2 tags and publishes, needing a human `[ask: permission]` plus a tier-gate prompt.

## 3. Structural facts for the automation design

- **No command chains into the next.** Each ends with "suggest `/flow:X`" (start Completion, pr Final reply, merge Phase 4). `/flow` routes, resume is informational only, and watch cannot start `/loop`. A human starts every lifecycle step.
- **Workflow YAMLs are declarative contracts, not an orchestrator.** Their completion gates are advisory (`references/flow-workflows.md`).
- **The autonomous ask policy removes only `[ask: default]` questions.** Decision and permission questions still require a person.
  - Escalations are stored records (`bin/flow-question.sh`) with an open/answered status.
  - The stored-question helper and the docs I read describe no path that answers decision or permission questions without a person: no policy oracle and no timeout default.
- **The Stop-hook goal enforcement defaults to `warn` and never blocks.** `block` mode exists but is opt-in (`references/stop-hook-goal-enforcement.md`).
- **Merge and release always require a human, confirmed twice.** The floor is hard-coded in settings, the validator, the commands and the hook.