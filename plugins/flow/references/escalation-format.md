# Escalation Format (canonical six-field structure)

Reference document. The canonical structure every command and agent uses when it must escalate a decision to the user. Every command that escalates cites this file rather than inlining the field names, so the format stays consistent across the plugin.

## When escalation IS required

Escalate when ALL THREE of the following hold:

1. **The decision has consequences beyond the current command.** Examples: choosing a migration strategy, accepting a security risk, allowing a skip outside the runtime-verification whitelist, picking which P1/P2 finding becomes the merge blocker.
2. **There is no obvious right answer.** If reading the spec, the journal, or the surrounding code would resolve the question, the agent must do that work itself before asking.
3. **The agent cannot resolve the question with high confidence using available tools.** "I'm not sure" is not enough. The agent must be able to articulate exactly what is unknown and why their tools cannot bridge the gap.

## When escalation IS NOT required (resolve autonomously)

Do NOT escalate when ANY of these apply:

- The answer is in the issue body, the spec, the decision journal, or the code.
- The decision is reversible and small (Tier 1 actions: file edits, branches, commits).
- A reasonable default exists and the cost of asking exceeds the cost of being wrong.
- The agent is asking permission for an already-authorized action ("can I commit?" — yes, that's Tier 1).

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

### 5. Time sensitivity

Whether the decision is blocking, urgent, or safe to wait. If a deadline applies, name it. The user uses this to triage when to read.

> **Time sensitivity** — Blocks the Spec Validation Gate. PLAN cannot proceed until this resolves.

### 6. Risk

What breaks if the user defers, and who bears the cost. This is the "wake me at 3 AM if X" field — it tells the user the consequence of inaction or the wrong choice.

> **Risk** — Choosing Option 3 (manual) means the verdict-judge cannot give a confident PASS without the user's manual evidence. Choosing Option 1 with too-broad a snapshot risks false-positive test failures on legitimate schema evolution; the maintenance burden falls on whoever next changes the API.

## Delivery contract

Every escalation MUST be delivered via the `AskUserQuestion` tool, NEVER as inline text in a markdown response. Inline text is bypassable; the tool surfaces a structured prompt the user definitively sees and answers.

The `AskUserQuestion` invocation should structure the six fields as the question prefix and use the **Options** as the actual options the user selects from:

```
AskUserQuestion(
  question: "{Situation summary in one sentence}. What should I do?

  **Situation** — {full situation paragraph}
  **What I tried** — {tried paragraph}
  **Recommendation** — {one-sentence recommendation}
  **Time sensitivity** — {blocking/urgent/safe}
  **Risk** — {risk paragraph}",
  options: [
    {label: "Option 1: ...", description: "{trade-off}"},
    {label: "Option 2: ...", description: "{trade-off}"},
    {label: "Option 3: ...", description: "{trade-off}"}
  ]
)
```

This shape gives the user the full context (in the question body) AND a structured choice (in the options array). When the user picks an option, the agent has unambiguous direction.

## Field-name compatibility

The vision article (`flow_plugin_medium_article_grounded.md`) uses a slightly different set of field names: `Context / Options considered / Tradeoffs / Recommendation / Risk of inaction / Decision needed`. The mapping is:

| Vision name | Canonical name (this doc) | Notes |
|---|---|---|
| Context | Situation | Same intent: state the relevant facts |
| Options considered | (combined with Tried + Options) | The vision treats "options considered" as a single field; the canonical split separates "what I tried (and why those didn't work)" from "what I am offering as paths forward" because users frequently need to see the failed attempts before they trust the offered options |
| Tradeoffs | (one-line trade-offs in each Option) | Inlined per option for brevity |
| Recommendation | Recommendation | Same |
| Risk of inaction | Time sensitivity + Risk | The vision combines these; the canonical split separates "when does this matter" (Time sensitivity) from "what breaks if wrong" (Risk) because they answer different triage questions |
| Decision needed | (implicit in the AskUserQuestion options array) | The structured tool surfaces this naturally |

Both shapes carry the same information. The canonical six-field structure is preferred for new commands and agents because it maps cleanly onto `AskUserQuestion`, which is the only delivery channel the project endorses.

## Anti-patterns

- **"What should I do?"** with no Situation/Tried/Options. This is the bare question that the protocol exists to prevent.
- **Inline-text escalation** — writing the six fields in a markdown response without invoking `AskUserQuestion`. Users skim text; they do not skim tool prompts.
- **Asking permission for Tier 1 actions** — file edits, commits, branches do not require escalation. See `references/three-tier-safety.md` for the tier definitions.
- **Compound questions** — escalate one decision at a time. If the user must make decisions A AND B, file two escalations or design a single decision that covers both.
- **Recommending "you decide"** — every escalation must include a Recommendation. "I have no preference" is rarely true and signals the agent didn't do the analysis.
