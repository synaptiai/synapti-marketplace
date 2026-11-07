# Escalation Format (canonical six-field structure)

Reference document. The canonical structure every command and agent uses when it must escalate a decision to the user. Every command that escalates cites this file rather than inlining the field names, so the format stays consistent across the plugin.

## When escalation IS required

Escalate when ALL THREE of the following hold:

1. **The decision has consequences beyond the current command.** Examples: choosing a migration strategy, accepting a security risk, allowing a skip outside the runtime-verification whitelist, choosing which of two incompatible API designs the issue should commit to.
2. **There is no obvious right answer.** If reading the spec, the journal, or the surrounding code would resolve the question, the agent must do that work itself before asking.
3. **The agent cannot resolve the question with high confidence using available tools.** "I'm not sure" is not enough. The agent must be able to articulate exactly what is unknown and why their tools cannot bridge the gap.

## When escalation IS NOT required (resolve autonomously)

Do NOT escalate when ANY of these apply:

- The answer is in the issue body, the spec, the decision journal, or the code.
- The decision is reversible and small (Tier 1 actions: file edits, branches, commits).
- A reasonable default exists and the cost of asking exceeds the cost of being wrong.
- The agent is asking permission for an already-authorized action ("can I commit?" — yes, that's Tier 1).
- **The decision is about how to dispose of a code-review finding (P1/P2/P3 triage).** Finding triage is NEVER a valid escalation trigger — findings are work, not decisions. The default action for every finding is to fix it in this PR (see `skills/llm-operator-principles/SKILL.md`). If you find yourself drafting a Situation/Tried/Options block about a P1/P2/P3, stop and fix the finding instead.
- **The agent is approaching but has not exceeded an iteration ceiling** (`fixForwardMaxIterations`, `reviewCycleLimit`, `timeouts.qualityCheckMaxIterations`). Ceilings are safety nets against true infinite loops, not budgets — approaching one is a signal to re-check understanding, not to escalate the remaining work.

The Iron Law: **resolve what can be resolved locally, escalate only when there is a real decision to make**. An agent that escalates too eagerly trains the user to ignore escalations.

## The six fields

Every escalation surfaced via `AskUserQuestion` MUST include all six fields, in this order:

### 1. Situation

What specific state requires a decision. Concrete facts only — no recapping the conversation. Should be readable cold by a teammate joining the thread.

> **Situation** — Criterion #3 ("the API returns the same shape after the rename") has no automated verification command. Spec Validation Gate cannot pass.

### 2. What I tried

What the agent already attempted, and why each path did not resolve autonomously. This is the "homework" field — without it, the user has to ask "did you try X?" before they can act on the escalation.

> **What I tried** — Searched the codebase for existing API-shape tests (none found). Tried to classify the criterion via `criterion-verification-map` skill (no verification type matched). Inspected the spec for an explicit reference shape (not present).

### 3. Options

2-3 concrete paths forward, each with a one-line trade-off. Numbered. The user picks one.

> **Options**:
> 1. Add a snapshot test using `vitest --update` on a frozen sample response. Trade-off: test asserts on response shape but not semantics; needs maintenance when the schema legitimately evolves.
> 2. Generate a JSON Schema from the TypeScript response type via `ts-json-schema-generator` and assert at runtime. Trade-off: requires installing a build-time dependency; catches semantic shape changes but not value semantics.
> 3. Mark the criterion as `manual` — the user verifies the shape themselves at VERIFY phase. Trade-off: no automated verdict; requires human-in-the-loop on every PR.

### 4. Recommendation

The agent's preferred option, with one-sentence reasoning. The user can accept, reject, or pick another option.

> **Recommendation** — Option 1. Snapshot tests are the lowest-friction way to lock the shape; the maintenance cost is paid only when the schema legitimately evolves.

### 5. Blocking?

Whether the decision blocks the current command. Three values: **Yes** (blocks — the command cannot proceed until this resolves), **Soft** (advisory — the command can continue with a default but the user should know), or **No** (informational only).

Do NOT use calendar-time language ("urgent," "by Friday," "this week," "ASAP," "ETA"). The flow plugin is an LLM operator — calendar-time framings invite incorrect estimates that anchor deferral behavior. See `skills/llm-operator-principles/SKILL.md`.

> **Blocking?** — Yes. Blocks the Spec Validation Gate; PLAN cannot proceed until this resolves.

### 6. Risk

What breaks if the user defers, and who bears the cost. This is the "wake me at 3 AM if X" field — it tells the user the consequence of inaction or the wrong choice.

> **Risk** — Choosing Option 3 (manual) means the verdict-judge cannot give a confident PASS without the user's manual evidence. Choosing Option 1 with too-broad a snapshot risks false-positive test failures on legitimate schema evolution; the maintenance burden falls on whoever next changes the API.

## Delivery contract

Every escalation MUST be delivered via the `AskUserQuestion` tool, NEVER as inline text in a markdown response. Inline text is bypassable; the tool surfaces a structured prompt the user definitively sees and answers.

The call carries the class of its place ([`ask-policy.md`](ask-policy.md)): `metadata: {"source": "flow:decision"}` for a product or scope decision, `{"source": "flow:permission"}` for a Tier 3 action or an out-of-whitelist skip. Under `autonomous: true` a question without one of those is denied by the `ask-policy.sh` hook, and a place tagged `[ask: default]` takes its recommendation instead of escalating.

The `AskUserQuestion` invocation should structure the six fields as the question prefix and use the **Options** as the actual options the user selects from:

```
AskUserQuestion(
  question: "{Situation summary in one sentence}. What should I do?

  **Situation** — {full situation paragraph}
  **What I tried** — {tried paragraph}
  **Recommendation** — {one-sentence recommendation}
  **Blocking?** — {yes/soft/no}
  **Risk** — {risk paragraph}",
  options: [
    {label: "Option 1: ...", description: "{trade-off}"},
    {label: "Option 2: ...", description: "{trade-off}"},
    {label: "Option 3: ...", description: "{trade-off}"}
  ]
)
```

This shape gives the user the full context (in the question body) AND a structured choice (in the options array). When the user picks an option, the agent has unambiguous direction.

### Every escalation is stored

An escalation is a record with an id and a status, not only a live tool call, so it survives the session ending, a compaction, or a session where nobody can answer it. `bin/flow-question.sh` keeps it under `<runtime dir>/questions/` ([`flow-runtime-state.md`](flow-runtime-state.md)):

1. **Before asking**, store it, the recommended option first:

   ```bash
   "$FLOW_ROOT/bin/flow-question.sh" add --journal \
     --situation "..." --tried "..." \
     --option "<recommended option>" --option "<another>" [--option "<a third>"] \
     --recommendation "..." --blocking yes|soft|no --risk "..." \
     --command "<command and step>" --class decision|permission|default \
     [--issue N] [--pr N] [--run <FlowRun id>]
   ```

   `--class` is the `[ask: ...]` tag of the place that asks ([`ask-policy.md`](ask-policy.md)), so the question is asked the same way when it is asked again later: `/flow:resume` asks a `decision` or `permission` record with that `metadata.source`, and under `autonomous` takes the recommendation of a `default` one. It prints `QUESTION_ID=<id>` and, with `--journal`, writes an `escalation-asked` artifact. A missing field, fewer than two options or more than three, another blocking level or another class is refused with the field named. `bin/flow-question.sh get <id> --prompt` prints the six-field body for the question.
2. **When the session has `AskUserQuestion`** (under either ask policy for a decision or a permission; under `autonomous` an `[ask: default]` place is not asked and takes its recommendation, [`ask-policy.md`](ask-policy.md)): ask it as above, then record the answer: `bin/flow-question.sh answer <id> --choice <option number> --journal`, which writes `escalation-resolved` (`escalation_field: options`, `outcome`: the option chosen); the `/flow:merge` manifest emit then records only escalations that were not stored, so none is recorded twice. A question that no longer applies is withdrawn: `withdraw <id> --reason "..." --journal`.
3. **Where `AskUserQuestion` is not available** (it is not among the session's tools, as in `claude -p`): store the question and do not wait for it.
   - `Blocking: yes` — stop the pipeline. The final reply says the run is waiting and names the question id; `/flow:status` and `/flow:resume` show it, and whoever answers it records the answer with `answer`.
   - `Blocking: soft` — go on with the recommended option and record that with `answer <id> --choice 1 --by recommendation --journal`. The pull request body lists it under `## Decisions taken on a recommendation` (`/flow:pr` reads them with `flow-question.sh list --status answered --issue N`).
   - `Blocking: no` — record it the same way as `soft`; it is not listed in the pull request body.

## Anti-patterns

- **"What should I do?"** with no Situation/Tried/Options. This is the bare question that the protocol exists to prevent.
- **Inline-text escalation** — writing the six fields in a markdown response without invoking `AskUserQuestion`. Users skim text; they do not skim tool prompts.
- **Asking permission for Tier 1 actions** — file edits, commits, branches do not require escalation. See `references/three-tier-safety.md` for the tier definitions.
- **Compound questions** — escalate one decision at a time. If the user must make decisions A AND B, file two escalations or design a single decision that covers both.
- **Recommending "you decide"** — every escalation must include a Recommendation. "I have no preference" is rarely true and signals the agent didn't do the analysis.
- **Finding-triage escalation** — drafting a six-field block to ask the user whether to fix a P1/P2/P3 finding. Findings are work, not decisions. Fix the finding instead. See `skills/llm-operator-principles/SKILL.md`.
- **Calendar-time framings in any field** — "urgent," "by Friday," "1-2 weeks," "ETA." Use the Blocking? field's yes/soft/no values instead.
