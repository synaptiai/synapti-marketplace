# Quality Gate Patterns

## Gate Architectures

### Architecture 1: Linear Gate Chain
```
[Execute] → [Gate 1] → [Execute] → [Gate 2] → [Final Gate] → [Ship]
```
**When to use:** Sequential workflows where each stage must pass before the next begins. Simple, easy to debug, but slow — every gate adds latency.

**Best for:** Regulated workflows, compliance-heavy processes, high-stakes output.

### Architecture 2: Parallel Gates with Convergence
```
[Execute] → [Gate A: Quality] ─┐
            [Gate B: Compliance]─┼→ [Converge: all must pass] → [Ship]  
            [Gate C: Brand]    ─┘
```
**When to use:** Multiple independent quality dimensions that can be checked simultaneously. Faster than linear but requires a convergence mechanism.

**Best for:** Content pipelines (quality + compliance + brand voice checked in parallel).

### Architecture 3: Tiered Gates
```
[Execute] → [Gate 1: Fast/Cheap] → pass → [Gate 2: Thorough/Expensive] → [Ship]
                                  → fail → [Reject immediately]
```
**When to use:** When most failures are obvious and can be caught cheaply. The expensive gate only runs on output that passed the cheap gate. Saves compute and time.

**Best for:** High-volume workflows where 70%+ of failures are caught by simple criteria.

### Architecture 4: Advisory + Blocking
```
[Execute] → [Advisory Gate: suggestions] → [Continue regardless]
                                         → [Blocking Gate: hard criteria] → pass/fail
```
**When to use:** When some quality dimensions are preferences (nice to have) and others are requirements (must have). Advisory gates flag but don't block; blocking gates halt on failure.

**Best for:** Creative work where taste is subjective but some criteria are non-negotiable.

---

## Gate Pattern Library

### Pattern: Criteria Checklist Gate
The simplest gate. Binary pass/fail on a list of criteria.

```markdown
## Gate: [Name]

### Criteria (ALL must pass)
1. [ ] Output contains [required element]
2. [ ] Output does not contain [prohibited element]  
3. [ ] Output length is between [min] and [max]
4. [ ] Output format matches [template]
5. [ ] [Domain-specific criterion]

### On Fail
- Criteria 1-3 failed → Retry with specific feedback
- Criteria 4 failed → Reformat (agent can self-correct)
- Criteria 5 failed → Escalate (may need human judgment)
```

**Strengths:** Simple, deterministic, easy to debug.
**Weaknesses:** Can only check what you explicitly list. Misses novel failure modes.

### Pattern: LLM-as-Judge Gate
Uses a separate LLM instance to evaluate output quality. The judge sees the specification and the output but NOT the execution process.

```markdown
## Gate: [Name]

### Judge Prompt
"Given this specification: [spec]
And this output: [output]
Rate satisfaction on these dimensions:
1. Does the output achieve the stated intent? (1-10)
2. Would the specified user accept this? (1-10)
3. Does it violate any constraints? (yes/no + which)

Provide a single PASS/FAIL recommendation with reasoning."

### Threshold
- All dimensions ≥ 7/10 AND no constraint violations → PASS
- Any dimension < 5/10 → FAIL immediately
- Between 5-7 → CONDITIONAL PASS with flagged concerns

### Separation Rules
- Judge model MUST be a different instance than the executing model
- Judge does NOT see the execution steps, only the final output
- Judge criteria stored separately from execution spec (holdout principle)
```

**Strengths:** Can evaluate subjective quality. Catches failures that checklists miss.
**Weaknesses:** Circular risk — same class of technology judging itself. Mitigate by using different models or different prompts.

### Pattern: Holdout Scenario Gate
Inspired by ML holdout sets. Test scenarios stored outside the codebase where the executing agent can't see them.

```markdown
## Gate: [Name]

### Visible Spec (agent sees during execution)
[Standard specification — intent, constraints, format]

### Holdout Scenarios (agent NEVER sees)
Stored in: [separate location, not in agent context]

Scenario 1: "Given [specific input], the output must [specific behavior]"
Scenario 2: "When [edge case], the output must [handle correctly]"
Scenario 3: "User attempts [adversarial action], system must [prevent/handle]"

### Satisfaction Metric
Run all scenarios against the output.
Satisfaction = (scenarios satisfied) / (total scenarios)
Target: ≥ [X]% satisfaction

### Why Holdout Works
If the agent can see the test cases, it optimizes for them specifically
(reward hacking). Holdout scenarios force the agent to build genuine
capability, not test-passing capability.
```

**Strengths:** Prevents gaming. Tests real behavior, not criteria compliance.
**Weaknesses:** Requires maintaining a separate scenario bank. Scenarios need updating as requirements evolve.

### Pattern: Diff Gate
Compares output against a known-good reference or previous version.

```markdown
## Gate: [Name]

### Reference
[Known-good output or baseline]

### Comparison Criteria
- Structural similarity: ≥ [X]% (prevents wild deviation)
- Content accuracy: [specific checks]
- Regression check: no quality dimensions worse than reference

### On Deviation
- Minor deviation (< 10% structural change) → PASS with note
- Major deviation (> 30%) → ESCALATE with diff report
- Regression on any quality dimension → FAIL
```

**Strengths:** Catches regressions. Good for iterative workflows.
**Weaknesses:** Anchors to the reference — may block legitimate improvements.

### Pattern: Human Sampling Gate
Not every output gets reviewed. Statistical sampling gives confidence without bottleneck.

```markdown
## Gate: [Name]

### Sampling Rate
- First 10 outputs: 100% human review (calibration period)
- Next 50 outputs: 20% random sample
- Steady state: 5% random sample + 100% of escalations

### Recalibration Triggers
If sampled output fails human review:
- Increase sampling rate to 50% for next 20 outputs
- If failures continue → halt and redesign specification
- If failures stop → gradually reduce sampling rate

### Dashboard
Show: pass rate trend, failure categories, time between failures
```

**Strengths:** Scales. Humans stay in loop without becoming bottleneck.
**Weaknesses:** Statistical risk — bad outputs can slip through between samples.

---

## Converting Common Approval Types

| Current Approval | Gate Replacement | Key Design Decision |
|-----------------|-----------------|-------------------|
| Manager sign-off on deliverable | Criteria checklist + LLM-as-judge | Who defines the criteria? (The manager — they become Quality Architect) |
| Legal review of contracts | Criteria checklist (hard rules) + human sampling (edge cases) | Which clauses are deterministic vs. judgment-dependent? |
| Design review of UI | LLM-as-judge with brand guidelines + diff gate against design system | How much deviation from design system is acceptable? |
| Code review | Holdout scenario gate + automated testing | What does the holdout set test that unit tests don't? |
| Content approval for publication | Tiered: brand voice check (fast) → LLM-as-judge quality (thorough) | What's the brand voice specification? (Needs genome VOICE.md) |
| Budget approval | Criteria checklist (threshold) + human-only above threshold | What's the autonomous spending limit? |
| Client communication approval | LLM-as-judge against VOICE.md + human sampling | What sampling rate gives confidence? |

---

## Gate Health Metrics

Track these to know if your gates are working:

| Metric | Healthy Range | Problem If Outside |
|--------|--------------|-------------------|
| Pass rate | 75-95% | <75% = spec or execution too weak. >95% = gate too lenient |
| False positive rate | <5% | Gate blocking good work → criteria too strict |
| Escape rate | <2% | Bad output getting through → gate too lenient or missing criteria |
| Gate latency | <10% of execution time | Gate is becoming a bottleneck |
| Escalation rate | 5-15% | <5% = agents may be overstepping. >15% = governance too restrictive |
| Scenario staleness | Updated within last 30 days | Old scenarios miss new failure modes |
