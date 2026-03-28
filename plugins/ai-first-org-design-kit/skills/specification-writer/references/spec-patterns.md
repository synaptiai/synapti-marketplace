# Specification Patterns & Anti-Patterns

## Common Specification Patterns

### Pattern 1: The Bounded Task
Best for: one-shot agent tasks with clear input/output.

```markdown
Intent → Input format → Output format → 3-7 acceptance criteria → 
Success example → Failure example → Constraints → Edge cases
```

**When to use:** The agent does one thing, produces one artifact, and you can tell immediately if it worked.

**Example domain:** "Generate a weekly client status email from this project tracker data."

### Pattern 2: The Decision Tree
Best for: tasks where the agent must branch based on input conditions.

```markdown
Intent → Input format → Decision conditions:
  If [condition A] → [action + output A]
  If [condition B] → [action + output B]
  If [ambiguous] → [escalation or default]
→ Quality criteria per branch
```

**When to use:** The same spec covers multiple scenarios, and the agent needs to select the right path.

**Example domain:** "Triage incoming support tickets — classify severity, route to appropriate team, escalate if customer is enterprise tier."

### Pattern 3: The Pipeline
Best for: multi-stage workflows where output of stage N feeds stage N+1.

```markdown
Stage 1: [Input → Action → Output → Gate]
Stage 2: [Input (= Stage 1 output) → Action → Output → Gate]
...
Convergence: [How stages combine]
Feedback loop: [How later stages inform earlier ones on next iteration]
```

**When to use:** Complex work that no single prompt handles well. Decompose into stages with quality gates between them.

**Example domain:** "Research → Draft → Edit → Format → Publish" content pipeline.

### Pattern 4: The Holdout Validation
Best for: tasks where the agent might game visible criteria.

```markdown
Visible spec (agent sees): Intent + constraints + format requirements
Hidden scenarios (agent doesn't see): End-to-end user stories that 
  the evaluation layer validates against
Satisfaction metric: % of trajectories through scenarios that satisfy
```

**When to use:** When you've observed agents writing code/content that technically passes criteria but doesn't actually serve the user. Borrowed from ML holdout-set methodology.

**Example domain:** Any specification where the agent has demonstrated "reward hacking" — satisfying the letter of the criteria but not the spirit.

### Pattern 5: The Template with Variables
Best for: repeatable tasks that vary by input parameters.

```markdown
Template: [Fixed structure with {{variable}} placeholders]
Variables: [List of what changes per instance, with valid ranges]
Invariants: [What NEVER changes regardless of variables]
```

**When to use:** You've solved one instance and want to generalize. This is Beacraft's "solve for a class of problems" principle encoded.

**Example domain:** "Client proposal" where the structure is fixed but client name, industry, problem statement, and proposed solution vary.

### Pattern 6: The Graduated Autonomy
Best for: tasks where trust builds over time.

```markdown
Level 1 (new): Agent drafts → human reviews every output → agent learns
Level 2 (proven): Agent executes → human spot-checks 20% → agent flags uncertainty
Level 3 (trusted): Agent executes → quality gate validates → human reviews exceptions only
Graduation criteria: [What triggers promotion to next level]
Demotion criteria: [What triggers rollback to prior level]
```

**When to use:** You're not sure the agent can handle full autonomy yet but want a path to get there.

---

## Specification Anti-Patterns

### Anti-Pattern 1: The Wish
```
❌ "Make it good"
❌ "Write something compelling"  
❌ "Analyze this thoroughly"
```
**Why it fails:** No testable criteria. "Good" to whom? "Compelling" by what standard? "Thorough" compared to what? The agent will produce something generic because it has no specification to differentiate against.

**Fix:** Replace every adjective with a testable criterion. "Good" → "passes these 5 acceptance criteria." "Compelling" → "reader takes [specific action] after reading." "Thorough" → "covers [these specific dimensions] with [this depth]."

### Anti-Pattern 2: The Procedure Masquerading as Spec
```
❌ "Step 1: Open the file. Step 2: Find the column. Step 3: Calculate..."
```
**Why it fails:** You've specified HOW, not WHAT. The agent is locked into your procedure even when a better approach exists. And if any step fails, the whole spec breaks.

**Fix:** Specify the WHAT (input, output, acceptance criteria) and let the agent determine HOW. Only specify procedure when the procedure IS the requirement (compliance, regulatory, etc.).

### Anti-Pattern 3: The Moving Target
```
❌ "Like the last one but different"
❌ "You know what I mean"
❌ "In our usual style"
```
**Why it fails:** References context the agent doesn't have. "The last one" — which one? "Our style" — encoded where?

**Fix:** Every reference must be explicit. Link to the genome's quality standards. Include actual examples. If you find yourself saying "you know what I mean," you haven't finished specifying.

### Anti-Pattern 4: The Kitchen Sink
```
❌ [2,000-word spec for a simple task]
```
**Why it fails:** Over-specification drowns the signal in noise. The agent can't tell which requirements are critical vs. nice-to-have. Everything looks equally important.

**Fix:** Match spec complexity to task complexity. Simple task → simple spec. Use the "Stranger Test" as the ceiling: once a stranger could execute successfully, stop adding detail.

### Anti-Pattern 5: The Happy-Path-Only Spec
```
❌ "Given clean CSV input, produce a summary report"
```
**Why it fails:** Real inputs are messy. What happens when columns are missing? When data types are wrong? When the file is enormous? The agent will either crash or improvise — neither is what you want.

**Fix:** Every spec needs an "Edge Cases" section. At minimum: malformed input, missing data, unexpected scale, ambiguous interpretation. For each: what should the agent do?

### Anti-Pattern 6: The Implicit Quality Standard
```
❌ "Write a blog post about X"
```
**Why it fails:** No quality bar. A 200-word draft and a 2,000-word polished article both satisfy this spec. The agent defaults to "good enough for an average blog" — which is probably not your standard.

**Fix:** Link to the genome's quality standards for this output type. Or inline it: "Blog post that meets these criteria: [list]. See BY-OUTPUT-TYPE.md for our quality standards."

---

## The Specification Smell Test

Before finalizing any spec, check for these smells:

| Smell | Symptom | Fix |
|-------|---------|-----|
| Vague adjectives | "good", "thorough", "compelling" | Replace with testable criteria |
| Missing failure definition | No "what bad looks like" | Add failure examples |
| Procedure over outcome | Steps instead of requirements | Specify WHAT, not HOW |
| Implicit context | "like usual", "our way" | Make references explicit |
| No edge cases | Only happy path covered | Add malformed/missing/ambiguous cases |
| No Stranger Test | Assumes shared context | Test with someone who has zero context |
| Over-specification | Spec is longer than the output | Simplify to signal only |
