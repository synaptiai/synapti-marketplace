# FAQ and Glossary

Anticipated questions from a mixed audience (engineering + PM/design) and a quick lookup for terms.

---

## FAQ

### Why a 90-min workshop instead of a doc?

Docs alone don't land the mental model — particularly the verdict-judge isolation, which needs to be **shown**, not described. The recording solves the "demos break in front of audiences" problem; the live narration lets the room interrupt at the right moments.

### "TDD enforce" means I can't write code without a test?

Means a task can't be marked completed without observing the RED-GREEN-REFACTOR cycle (see `plugins/flow/skills/autonomous-workflow/SKILL.md` lines 44–59). The agent enforces this on itself when it's writing code. You as a human can still write whatever you want — but if the agent is implementing for you under `/flow:start`, it will write the failing test first.

If that's too strict for your workflow, the team can vote `tddMode: suggest` in section 6.

### Why does the verdict-judge get to decide if the code is "right"?

Because it has the only complete view of "what was asked." The code-writing agent has goals, rationale, journaling, and ego in the loop. The judge is given **only** the acceptance criteria and the evidence bundle. If you can prove the AC against the evidence, it's right. If you can't, it isn't — even if the code looks fine.

This is the answer to the most common PM/design question. It's worth landing twice (slide 22, pause beat 2).

### What if the verdict-judge is wrong?

It returns `NEEDS-HUMAN-REVIEW` for ambiguous cases. The judge doesn't have authority to ship — the human always does. The judge has authority to **block**, and that's enough to prevent silent regressions.

If you think the judge is systematically wrong, that's a bug — file an issue, attach the AC + evidence + verdict, and the prompt construction can be examined against the failure case.

### "Spec Validation Gate" — does this mean we need rigorous specs for every issue?

Means: every AC needs a runnable verification command. "Works correctly" doesn't qualify. "Returns 200 on a valid request" does (`curl -w '%{http_code}' …`).

Issues labeled `documentation` or `chore` (configurable — decision 8) skip this requirement.

### Do PMs need to write the verification commands?

No. The PM writes ACs in observable-behavior language ("when X, then Y"). The agent classifies each AC against `criterion-verification-map`'s table (behavioral / API / UI / error / performance / configuration / data / contract) and produces the runnable command at plan time. The PM reviews the resulting plan, but doesn't author bash.

### What's the difference between `/flow:debug` and just running `/flow:start` on a bug?

`/flow:debug` is for bugs you can't reproduce yet — structured root-cause analysis, evidence gathering, hypothesis testing. `/flow:start` (with a `bug` label) is for a known-reproducible bug going through the full lifecycle.

Note: `debugging-patterns` skill activates **automatically** when any verification step fails — test, build, server start, smoke test. You don't need a `bug` label to get debugging help (`commands/start.md` lines 70–73).

### Can I disable individual hooks?

Yes — edit `plugins/flow/hooks/hooks.json` or shadow it via local override. But seriously consider: the hooks exist as a structural backstop for command bugs. `block-force-push` is what catches the recovery attempt when a command-level guard fails. Don't disable them lightly.

### Why is the recording synthetic instead of using our real codebase?

Two reasons. First, the lifecycle stays visible — nobody drags the demo into "but how does this apply to *our* auth service." Second, the recording is reusable — a new hire six months from now can still follow the demo without it being repo-specific.

If you want a session against the real codebase, run one — but plan more time and accept that it'll be tangent-prone.

### The README mentions `gate-merge.sh` and `gate-release.sh` — where are they?

They don't exist. The README's "Hooks (10 scripts)" section is stale. Eight scripts are wired (see `plugins/flow/hooks/hooks.json`). Merge and release confirmation is at the **command** level via `AskUserQuestion` (see `plugins/flow/references/three-tier-safety.md` line 80). This is mentioned on slide 24 and again in HANDBOOK §7.

### Is the marketplace `gh-workflow` plugin going away?

Not immediately. They coexist. flow is the recommended path forward; gh-workflow remains for repos that aren't ready to migrate. `/flow:setup` warns on coexistence.

### What if `/flow:setup` doesn't detect our build?

File an issue with your project's `package.json` / `pyproject.toml` / `Cargo.toml` etc. Setup is heuristic. The fallback is to manually populate `.claude/settings.flow.json` with the right commands.

### Can two of us run `/flow:start` on the same issue?

Don't. `/flow:start` assigns the issue. Branch creation will conflict. The `block-destructive` hook will catch overwrites, but you'll waste time.

If you genuinely need parallel work, file two issues for the two pieces and `/flow:start` each separately.

### What's the right cadence for `/flow:learn`?

Decision 10 in the worksheet. Suggestion: monthly, rotating owner. A proposal nobody triages is a missed pattern.

### Can we customize the verdict-judge?

No. **Independence is the feature**, not a constraint. Customizing what the judge sees would defeat the purpose. The only knobs:

- `verdict.enabled` — turn it off entirely (not recommended)
- `verdict.requireAllPass` — decision 2 in the worksheet

If you want stricter judgment, write better completeness subsections in the evidence bundle (Principle 5).

### What if I disagree with a P3?

Rewrite it as a six-field escalation in the PR comment. Reviewer accepts (becomes a real escalation in `FLOW_RESOLUTION_CYCLE`) or rejects (the original P3 stands and you fix it). See implicit 11th decision in worksheet.

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
- **Block-force-push / block-destructive / block-secrets** — the three PreToolUse Bash hooks. Exit 2 = block.
- **`--force-with-lease`** — explicitly allowed; treated as Tier 2 (journal).

### Findings and review

- **P1** — must fix; blocks merge. Security, data loss, broken functionality.
- **P2** — should fix; logic errors, missing edge cases, test gaps, convention violations.
- **P3** — fix-or-escalate. Style, optimization, future improvements. Not a free pass.
- **ASSERTION / EVIDENCE / VERIFIED** — the citation pattern from `evidence-based-development`. No claim without a file:line cite.
- **Boy Scout Rule** — leave the campsite cleaner than you found it. Recognized in commit type `improve:`.
- **5-facet review** — quality, security, conventions, tests, requirements. See `code-review-methodology`.
- **Adversarial review** — opt-in (`agentTeams: true`). Reviewers challenge each other's findings before consolidating.

### Acceptance criteria and evidence

- **Spec Validation Gate** — fires if a criterion lacks a runnable verification command. Blocks PLAN.
- **Stranger Test** — gate at end of PLAN. Plan must be executable by someone with zero prior context.
- **Eval-as-spec** — every AC produces a runnable verification command at plan time, not verify time.
- **Does NOT promise** — first-class field on every AC. Fences scope so a narrow PASS isn't inflated to a broad guarantee.
- **Evidence bundle** — structured per-AC document fed to the verdict-judge. Three required completeness subsections.
- **Holdout validation** — hidden scenarios cross-referenced against actual file state. Catches "test added" claims that aren't true.

### Lifecycle markers

- **FLOW_REVIEW_CYCLE** — marker in PR review bodies; captures findings per cycle.
- **FLOW_RESOLUTION_CYCLE** — marker in PR comments; captures resolved + escalated findings per cycle. Merge gate's substrate.
- **ESCALATED** — was "DEFERRED" pre-v2.0. P3 escalated via the six-field structure, not silently dropped.
- **Per-Task Verification Gate** — a task can't move to `completed` until tests pass, evidence captured, no out-of-context files, TDD cycle observed. (`autonomous-workflow/SKILL.md` lines 44–59)

### Decision journal

- **`.decisions/`** — default journal directory. Configurable via `journal.dir`.
- **Auto-log entry** — HTML comment written by hooks: `<!-- auto-log: timestamp action target -->`.
- **Structured entry** — Markdown written by skills with category / decision / rationale / alternatives / evidence.
- **Sensitivity** — `public` (default; included in PR body) or `internal` (redacted).
- **Categories** — Architecture, Implementation, Convention, Quality, Risk.

### Phases

- **EXPLORE** — gather context. Parallel reads, agent dispatch, capability discovery, LSP trace.
- **PLAN** — decompose. TaskCreate per deliverable, verification command per AC, Stranger Test gate.
- **CODE** — execute tasks. Per-Task Gate, TDD cycle, incremental commits.
- **VERIFY** — four layers: static, runtime, review (fix-forward), verdict (independent).

### Roles

- **Verdict-judge** — independent agent. Sees only ACs + evidence bundle + holdout. No diff, no journal.
- **Implementation-planner** — agent that parses ACs into tasks with dependencies.
- **Code-reviewer / security-reviewer / convention-checker / error-handler-inspector / integration-verifier / test-runner** — the other 6 agents.
- **Six-field escalation** — Situation / What I tried / Options (one Recommended) / My recommendation / Time sensitivity / Risk if wrong.

### Settings

- **Cascade** — `plugins/flow/settings.json` → `~/.claude/settings.flow.json` → `.claude/settings.flow.json` → `.claude/settings.flow.local.json`. Later wins.
- **Schema** — full reference in `plugins/flow/schema.json`.
- **`tddMode: enforce` / `suggest`** — strict default vs opt-out. Decision 1.
- **`verdict.requireAllPass: true / false`** — strict default vs opt-out. Decision 2.
- **`agentTeams: false / true`** — adversarial review opt-in. Decision 3. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`.
