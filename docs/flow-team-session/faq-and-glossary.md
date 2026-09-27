# FAQ and Glossary

Anticipated questions from a mixed audience (engineering + PM/design) and a quick lookup for terms.

---

## FAQ

### Why a 90-min workshop instead of a doc?

Docs alone don't land the mental model — particularly the verdict-judge isolation, which needs to be **shown**, not described. The recording solves the "demos break in front of audiences" problem; the live narration lets the room interrupt at the right moments.

### "TDD enforce" means I can't write code without a test?

Means a task can't be marked completed without observing the RED-GREEN-REFACTOR cycle (see `plugins/flow/skills/autonomous-workflow/SKILL.md`, "Per-Task Verification Gate"). The agent enforces this on itself when it's writing code. You as a human can still write whatever you want — but if the agent is implementing for you under `/flow:start`, it will write the failing test first.

If that's too strict for your workflow, the team can vote `tddMode: suggest` (or `off`) in section 6.

### Why does the verdict-judge get to decide if the code is "right"?

Because it has the only complete view of "what was asked." The code-writing agent has goals, rationale, journaling, and ego in the loop. The judge is given **only** the acceptance criteria and the evidence bundle. If you can prove the AC against the evidence, it's right. If you can't, it isn't — even if the code looks fine.

This is the answer to the most common PM/design question. It's worth landing twice (slide 22, pause beat 2).

### What if the verdict-judge is wrong?

It returns `NEEDS-HUMAN-REVIEW` for ambiguous cases. The judge doesn't have authority to ship — the human always does. The judge has authority to **block**, and that's enough to prevent silent regressions.

If you think the judge is systematically wrong, that's a bug — file an issue, attach the AC + evidence + verdict, and the prompt construction can be examined against the failure case.

### "Spec Validation Gate" — does this mean we need rigorous specs for every issue?

Means: every AC needs a runnable verification command. "Works correctly" doesn't qualify. "Returns 200 on a valid request" does (`curl -w '%{http_code}' …`).

Issues labeled `documentation` or `chore` (configurable — decision 8) may skip this requirement. The gate runs in `/flow:start`; `/flow:issue` helps you write observable criteria in the first place.

### Do PMs need to write the verification commands?

No. The PM writes ACs in observable-behavior language ("when X, then Y"). The agent classifies each AC against `criterion-verification-map`'s table (behavioral / API / UI / error / performance / configuration / data / contract) and produces the runnable command at plan time, in `/flow:start`. The PM reviews the resulting plan, but doesn't author bash.

### What's the difference between `/flow:debug` and just running `/flow:start` on a bug?

`/flow:debug` is for bugs you can't reproduce yet — structured root-cause analysis, evidence gathering, hypothesis testing. `/flow:start` (with a `bug` label) is for a known-reproducible bug going through the full lifecycle.

Note: `debugging-patterns` skill activates **automatically** when any verification step fails — test, build, server start, smoke test. You don't need a `bug` label to get debugging help (`commands/start.md`, Phase 1).

### Can I disable individual hooks?

Not through settings — hooks are structural and have no settings switch (`plugins/flow/references/gate-configuration.md`, "Hook Override"). The only way is to edit `plugins/flow/hooks/hooks.json` or the scripts themselves. A few hooks have their own setting for how strict they are: `testing.taskCompletionGate` (`block` / `warn` / `off`) for the task-completion gate, `flow.goals.stopHookEnforcement` for the Stop hook, and `minimalScope: true` turns off the issue-create prompt. But seriously consider: the hooks exist as a structural backstop for command bugs. `block-force-push` is what catches the recovery attempt when a command-level guard fails. Don't disable them lightly.

### Why is the recording synthetic instead of using our real codebase?

Two reasons. First, the lifecycle stays visible — nobody drags the demo into "but how does this apply to *our* auth service." Second, the recording is reusable — a new hire six months from now can still follow the demo without it being repo-specific.

If you want a session against the real codebase, run one — but plan more time and accept that it'll be tangent-prone.

### Are `gate-merge.sh` and `gate-release.sh` hook scripts?

No — and they aren't supposed to be. Fourteen scripts are wired (see `plugins/flow/hooks/hooks.json`). Merge and release confirmation lives at the **command** level via `AskUserQuestion` (see `plugins/flow/references/three-tier-safety.md`, "Hook Enforcement"). One hook does concern merges: `block-unchecked-merge.sh` refuses a `gh pr merge` while any check is queued, running or failed. It does not confirm anything; it refuses unfinished or red merges, including ones typed straight into Bash. This is mentioned on the hooks slide and again in HANDBOOK §7.

### Is the marketplace `gh-workflow` plugin going away?

Not immediately. Both can be installed. flow is the recommended path forward; gh-workflow remains for repos that aren't ready to migrate. `/flow:setup` warns when it finds gh-workflow and advises enabling only one at a time, to avoid hook conflicts.

### What if `/flow:setup` doesn't detect our build?

File an issue with your project's `package.json` / `pyproject.toml` / `Cargo.toml` etc. Setup is heuristic. There is no settings key that lists build, test or lint commands — flow discovers them on each run (`capability-discovery`). If the task-completion gate does not recognise your test or lint command, add a pattern for it to `testing.qualityCommandPatterns` in `.claude/settings.flow.json`.

### Can two of us run `/flow:start` on the same issue?

Don't. `/flow:start` assigns the issue. Branch creation will conflict. The `block-destructive` hook will catch a hard reset or a force-delete of unmerged work, but you'll waste time.

If you genuinely need parallel work, file two issues for the two pieces and `/flow:start` each separately.

### What's the right cadence for `/flow:learn`?

Decision 10 in the worksheet. Suggestion: monthly, rotating owner. A proposal nobody triages is a missed pattern.

### Can we customize the verdict-judge?

No. **Independence is the feature**, not a constraint. Customizing what the judge sees would defeat the purpose. The only knobs:

- `verdict.enabled` — turn it off entirely (not recommended)
- `verdict.requireAllPass` — decision 2 in the worksheet

If you want stricter judgment, write better completeness subsections in the evidence bundle (Principle 5).

### What if I disagree with a P3?

Flow's default is to fix every finding, P3 included, in the PR; deciding what to do with a finding is never a reason for a six-field escalation. If the finding is wrong, push back in `/flow:address`: a pushback must stand on one of three grounds — the finding is factually incorrect (cite the `file:line`), applying it would break a named test, or it contradicts a quoted rule in CLAUDE.md. `/flow:address` replies in the thread, records the dismissal in the journal, and lists the finding as DISPUTED in the `FLOW_RESOLUTION_CYCLE` marker. A disputed finding is still unresolved, so `/flow:merge` keeps reporting it until it is resolved. When the same finding keeps being dismissed, `/flow:learn` can propose it as a review exception, and once promoted, reviewers stop raising it. See the implicit 11th decision in the worksheet.

### How do I file confusion?

GitHub issue, `documentation` label. Specifically log:

- Slides that needed extra explanation we didn't anticipate.
- Conventions we voted on that turn out to be wrong in practice.
- Skills that activate when they shouldn't (or don't when they should).
- Failure modes not in HANDBOOK §11.

The plugin gets better when the team tells it where it failed.

---

## Glossary

### Tiers and safety

- **Tier 1 / 2 / 3** — autonomous / journal / confirm. See `plugins/flow/references/three-tier-safety.md`.
- **Block-force-push / block-destructive / block-unchecked-merge / block-secrets** — the four blocking PreToolUse Bash hooks. Exit 2 = block. A fifth, `ask-issue-create`, asks before `gh issue create` while a FlowGoal is active.
- **`--force-with-lease`** — explicitly allowed; treated as Tier 2 (journal).

### Findings and review

- **P1** — must fix; blocks merge. Security, data loss, broken functionality.
- **P2** — should fix; logic errors, missing edge cases, test gaps, convention violations. Fixed in this PR.
- **P3** — consider; style, optimization. Fixed in this PR. Not a free pass.
- **Confidence** — HIGH (ran code, a test or LSP), MEDIUM (read the full code path) or LOW (pattern match). LOW findings go to "Needs investigation" and never decide the review.
- **ASSERTION / EVIDENCE / VERIFIED** — the citation pattern from `evidence-based-development`. No claim without a file:line cite.
- **Boy Scout Rule** — leave the campsite cleaner than you found it. Recognized in commit type `improve:`.
- **Parallel review fan-out** — `/flow:pr` Phase 3 and `/flow:review` Path B dispatch five agents in parallel — `code-reviewer`, `convention-checker`, `test-runner`, `security-reviewer`, `error-handler-inspector` — alongside the `holdout-validation` skill. `/flow:address` Phase 4 re-reviews the fix commits with the same five agents, then runs `holdout-validation`. The `code-review-methodology` skill calls these six the "6-facet review".
- **Adversarial review** — opt-in (`agentTeams: true` plus the env var), `/flow:review` only. Each agent runs as a skeptic and a verifier, and they challenge each other's findings before consolidating.
- **Review exception** — a row in `.flow/review-exceptions.md`: a rule the team has already rejected a finding over, scoped to a path glob. Reviewers do not raise a matching finding. Security findings are never withheld.
- **Blast radius** — the table `code-reviewer` writes when a change touches a contract other code depends on (API schema, migration, exported signature). A consumer the PR does not update is a P1.
- **Grounding critic** — optional pass (`review.groundingCritic`, default `off`) where the `finding-critic` agent tries to refute each P1/P2 finding from the code.

### Acceptance criteria and evidence

- **Spec Validation Gate** — fires if a criterion lacks a runnable verification command. Blocks PLAN.
- **Stranger Test** — gate at end of PLAN. Plan must be executable by someone with zero prior context.
- **Eval-as-spec** — every AC produces a runnable verification command at plan time, not verify time.
- **Does NOT promise** — first-class field on every AC. Fences scope so a narrow PASS isn't inflated to a broad guarantee.
- **Risk map** — part of the specification: where the logic is most likely to be subtly wrong, what the plausible wrong version does, and a check that tells them apart.
- **Evidence bundle** — structured per-AC document fed to the verdict-judge. Five required completeness subsections, plus `Does NOT promise` and `Visual analysis`.
- **Holdout validation** — hidden scenarios cross-referenced against actual file state. Catches "test added" claims that aren't true.

### Lifecycle markers

- **FLOW_REVIEW_CYCLE** — marker in PR review bodies; captures findings per cycle.
- **FLOW_RESOLUTION_CYCLE** — marker in PR comments; captures resolved, escalated and disputed findings per cycle. Merge gate's substrate.
- **ESCALATED** — a finding that could not be fixed in this PR for one of the allowed reasons (a product decision only the user can make, or a file or dependency flow does not own), escalated with the six fields. Auditable; not silently dropped. `/flow:merge` blocks while the latest marker lists any.
- **DISPUTED** — a finding the author pushed back on in `/flow:address`, with evidence. Still unresolved, so it still blocks `/flow:merge`.
- **Per-Task Verification Gate** — a task can't move to `completed` until tests pass, evidence captured, no out-of-context files, TDD cycle observed. (`autonomous-workflow/SKILL.md`, "Per-Task Verification Gate".) The `TaskCompleted` hook also refuses completion while files changed after the last passing check.

### Decision journal

- **`.decisions/`** — default journal directory. Configurable via `journal.dir`.
- **Auto-log entry** — HTML comment written by hooks: `<!-- auto-log: timestamp action target -->`. Kept in a local, gitignored trail under `{journal.dir}/auto-log/`, not in the tracked journal; a subagent's entries carry `agent=<type>`.
- **Structured entry** — Markdown written by skills with category / decision / rationale / alternatives / evidence.
- **Sensitivity** — set per entry: `public` (the default when an entry has no `Sensitivity:` line; included in PR body) or `internal` (shown in the PR body only as "[Internal decision]").
- **Categories** — Architecture, Implementation, Convention, Quality, Risk.

### Phases

- **EXPLORE** — gather context. Parallel reads, agent dispatch, capability discovery, LSP trace.
- **PLAN** — decompose. TaskCreate per deliverable, verification command per AC, Stranger Test gate.
- **CODE** — execute tasks. Per-Task Gate, TDD cycle, incremental commits.
- **VERIFY** — four layers: static, runtime, review (fix-forward), verdict (independent).

### Roles

- **Verdict-judge** — independent agent. Sees only ACs + evidence bundle + holdout. No diff, no journal, no file tools.
- **Implementation-planner** — agent that parses ACs into tasks with dependencies.
- **Code-reviewer / security-reviewer / convention-checker / error-handler-inspector / integration-verifier / test-runner** — the review and verification agents.
- **Finding-critic** — agent that tries to refute a review finding when the grounding critic is on.
- **Goal-evaluator-judge** — agent that judges whether a FlowGoal is achieved, for `/flow:goal evaluate` and the Stop hook's `evaluator-loop` mode.
- **Six-field escalation** — Situation / What I tried / Options / Recommendation / Blocking? (yes · soft · no) / Risk. Delivered via `AskUserQuestion`.

### Goals and runtime

- **FlowGoal** — the completion contract for a piece of work, at `.flow/goals/<id>.goal.yaml`. `/flow:start` creates it when at least one AC has a verification command. `/flow:merge` requires an active goal to be `achieved`.
- **Stop hook** — checks the active goal's evidence before the agent stops. Default `warn` never blocks; `block` and `evaluator-loop` are opt-in (`flow.goals.stopHookEnforcement`).
- **FlowRun** — the record of one command's run, in `.flow/runs/` (local). `/flow:resume` reads it and proposes the next step.

### Settings

- **Cascade** — `plugins/flow/settings.json` → `~/.claude/settings.flow.json` → `.claude/settings.flow.json` → `.claude/settings.flow.local.json`. Later wins.
- **Schema** — full reference in `plugins/flow/schema.json`.
- **`tddMode: enforce` / `suggest` / `off`** — strict default vs opt-out. Decision 1.
- **`verdict.requireAllPass: true / false`** — strict default vs opt-out. Decision 2.
- **`agentTeams: false / true`** — adversarial review opt-in. Decision 3. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`.
- **`minimalScope: false / true`** — `true` allows a follow-up issue instead of a fix, for a cosmetic P3 in a file the PR did not touch.
