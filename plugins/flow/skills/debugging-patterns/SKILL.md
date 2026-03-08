---
name: debugging-patterns
description: "[flow] Use when investigating bugs or unexpected behavior. Guides root cause isolation through log analysis, hypothesis testing, and fix validation. Prevents symptom-fixing and tunnel vision."
allowed-tools: Bash, Read, Grep, Glob, TaskCreate, TaskList, TaskUpdate
context: fork
agent: general-purpose
---

# Debugging Patterns

Domain skill for structured investigation of bugs and unexpected behavior.

## Iron Law

**ALWAYS FIND ROOT CAUSE BEFORE ATTEMPTING FIXES. Symptom fixes are failure.**

A fix that doesn't address root cause creates a new bug later. Every. Single. Time.

## Four-Phase Investigation

### 1. Gather Evidence

Collect before theorizing:

```bash
# Error logs, stack traces, recent changes
git log --oneline -10
git diff HEAD~3..HEAD --stat
```

- Read error messages and stack traces FULLY — don't skim
- Check logs in chronological order around the failure
- Note what changed recently (`git log`, `git diff`)
- Reproduce the error — if you can't reproduce it, you can't verify the fix

### 2. Pattern Analysis

Look for patterns in the evidence:

- When does it fail vs succeed? (inputs, timing, environment)
- What's different between working and broken states?
- Is the error consistent or intermittent?
- Use `Grep` to find similar patterns: error messages, function calls, data flows

### 3. Hypothesis Testing

Form and test hypotheses systematically. Use TaskCreate for each hypothesis:

```
TaskCreate("Hypothesis 1: {theory}", "Confidence: High\nTest: {specific test}\nEvidence: {what points here}")
TaskCreate("Hypothesis 2: {theory}", "Confidence: Medium\nTest: {specific test}\nEvidence: {what points here}")
TaskCreate("Hypothesis 3: {theory}", "Confidence: Low\nTest: {specific test}\nEvidence: {what points here}")
```

| # | Hypothesis | Confidence | Test | Result |
|---|-----------|------------|------|--------|
| 1 | {theory} | High/Med/Low | {specific test} | {outcome} |
| 2 | {theory} | High/Med/Low | {specific test} | {outcome} |
| 3 | {theory} | High/Med/Low | {specific test} | {outcome} |

For each hypothesis: TaskUpdate(status: "in_progress") before testing, TaskUpdate(status: "completed") after — whether confirmed or disproven. Record the result.

**Rules:**
- Maximum 3 hypotheses at a time (more means insufficient evidence — go back to phase 1)
- Test highest confidence first
- Test ONE at a time — never change two things simultaneously
- A disproven hypothesis is progress, not failure

### 4. Fix Validation

**Write a test that reproduces the bug BEFORE fixing.** If the test doesn't fail, you haven't found the bug.

```
TaskCreate("Fix validation", "Write reproducing test, implement fix, verify no regressions")
TaskUpdate("Fix validation", status: "in_progress")
```

1. Write failing test that captures the bug behavior
2. Verify the test fails for the right reason
3. Implement the fix
4. Verify the test passes
5. Run full test suite — no regressions

TaskUpdate("Fix validation", status: "completed") after all tests pass.
Use TaskList to confirm all hypotheses resolved and fix validated.

## Log-First Methodology

Read logs and errors BEFORE reading code:

1. **Start at the error** — read the full error message and stack trace
2. **Trace backward** — follow the data flow from error to origin
3. **Check boundaries** — inputs, API responses, config values at each step
4. **Only then read code** — now you know WHERE to look

Never start with "let me read the code and understand how it works." Start with "what went wrong and where."

## Stop Conditions

| Trigger | Action |
|---------|--------|
| 3+ failed fix attempts | Stop fixing forward. The problem is architectural. Return to EXPLORE. |
| Can't explain current behavior | Don't guess. Investigate more. Add logging, add assertions. |
| Tunnel vision (>30 min on one theory) | Step back. List what you KNOW vs what you ASSUME. |
| Fix works but you can't explain WHY | Revert. An unexplained fix is a time bomb. |

## Cognitive Bias Awareness

| Bias | Symptom | Antidote |
|------|---------|----------|
| **Confirmation bias** | Only looking for evidence that confirms your theory | Actively seek DISCONFIRMING evidence |
| **Anchoring** | First theory dominates even after disproof | Write down ALL hypotheses before testing any |
| **Recency bias** | Blaming the last change | Check if the bug existed before the last change: `git stash && test` |
| **Complexity bias** | Assuming an elaborate cause | Check the simple things first: typos, wrong variable, off-by-one |

## Rationalization Prevention

| Excuse | Response |
|--------|----------|
| "I know what's wrong" | Then prove it with evidence. If you're right, it takes 30 seconds. |
| "Quick fix, then proper fix later" | Later never comes. Fix root cause now. |
| "It works on my machine" | Then the bug is in environment differences. Investigate THAT. |
| "Let me just add a try-catch" | That's hiding the bug, not fixing it. Find the root cause. |
| "It's probably a race condition" | Probably? Prove it. Add timing logs, reproduce it reliably. |
