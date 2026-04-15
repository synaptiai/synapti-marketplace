---
name: evidence-based-development
description: "Enforce evidence-based decision-making by requiring file:line citations, P1/P2/P3 finding prioritization, and the ASSERTION/EVIDENCE/VERIFIED pattern before any recommendation. Use when gathering evidence, presenting findings, or making development decisions."
allowed-tools: Bash, Read, Grep, Glob
---

# Evidence-Based Development

Foundation skill that governs how Claude gathers, presents, and acts on evidence during development.

## Iron Law

**EVIDENCE BEFORE CLAIMS, ALWAYS. If you haven't read the code, you don't know what it does.**

This is non-negotiable. No recommendation without a citation. No behavioral claim without verification. Confidence is not evidence.

## Show Before Decide

Never propose a change without first showing the current state. Read the file, cite the line, then suggest.

**Pattern**: "Here's what I found at `file.rb:42` → here's what I recommend → here's why."

## Citation Requirements

Every claim about code must include a file:line reference. No exceptions.

- Use `file_path:line_number` format in all findings
- When reviewing diffs, cite both the file and the specific hunk
- When reporting issues, show the exact code snippet as evidence

## Finding Prioritization

All findings, review comments, and issues use P1/P2/P3 classification:

| Priority | Meaning | Action |
|----------|---------|--------|
| **P1** | Must fix — blocks merge, security issue, data loss risk, broken functionality | Fix before proceeding |
| **P2** | Should fix — logic error, missing edge case, test gap, convention violation | Fix in this PR |
| **P3** | Consider — style preference, optimization opportunity, future improvement | Fix in-PR unless a Proactive-Autonomy escalation is filed (six-field structure: Situation / Tried / Options / Recommendation / Time sensitivity / Risk) |

## ASSERTION/EVIDENCE/VERIFIED Pattern

For any non-trivial claim about code behavior:

1. **ASSERTION**: State what you believe to be true
2. **EVIDENCE**: Show the code/output/test that supports it
3. **VERIFIED**: Confirm by running a test, reading the actual code, or checking behavior

Skip this pattern for obvious facts (e.g., "this file exists"). Use it for behavioral claims, security assessments, and performance analysis.

## Finding-First Display

Always display findings BEFORE recommendations or actions:

1. Show the finding table (sorted P1 → P2 → P3)
2. Show affected files with citations
3. Then propose actions
4. Then ask for decisions (if needed)

Never bury findings after a long narrative. The human should see issues immediately.

## Deduplication

When synthesizing findings from multiple sources (agents, reviews, tools):

- Deduplicate by `file:line` — same location means same finding
- Keep the highest priority version
- Merge descriptions if they add different context
- Note the source of each finding for traceability

## Verification Methods

Every skill should include a verification step. Common patterns:

| Method | When to Use |
|--------|-------------|
| Run tests | After code changes |
| Read code / check git diff | Before behavioral claims or after edits |
| Parallel Bash | Run independent checks simultaneously |
| Agent(Explore) | Investigate unfamiliar code in separate context |

## Stop Conditions

Stop and reassess when:

- You've made 2+ claims without file:line citations in this session
- You're about to recommend a change to a file you haven't read
- Evidence contradicts your initial assumption — update the assumption, don't explain away the evidence
- You find yourself writing "should" or "probably" about code behavior — go verify

## Graceful Degradation

When evidence is unavailable:

- State what you couldn't verify and why
- Proceed with reduced confidence, flagging assumptions
- Never fabricate evidence or cite files you haven't read

## Rationalization Prevention

| Excuse | Response |
|--------|----------|
| "I'm pretty sure this is how it works" | Pretty sure is not evidence. Read the file. |
| "I already checked earlier" | Earlier is stale. Show fresh evidence. |
| "This is obvious from the pattern" | Obvious claims need obvious proof. Cite file:line. |
| "Checking would take too long" | Unchecked claims waste more time when wrong. |
| "The user already knows this" | The citation is for accuracy, not the audience. |
