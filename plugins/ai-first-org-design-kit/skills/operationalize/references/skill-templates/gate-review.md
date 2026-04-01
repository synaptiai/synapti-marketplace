# Skill Template: org-gate-review

Generate this skill at `.claude/skills/org-gate-review/SKILL.md` in the target project.

## Template

```markdown
---
name: org-gate-review
description: "Self-review against a specific quality gate before presenting work. Use before submitting code for review, publishing content, creating releases, or presenting any work output."
argument-hint: "[gate-name]"
allowed-tools: Read, Agent
context: fork
agent: general-purpose
---
<!-- generated-by: ai-first-kit v{VERSION} -->
<!-- v1.4.2: added Agent tool + Phase 2 holdout evaluation. Regenerate if upgrading from earlier versions. -->

# Gate Self-Review

Run a structured self-review against a quality gate's pass criteria, optionally
validated by an independent holdout evaluator.

## Phase 1: Visible Criteria Self-Review

1. Determine which gate to review against:
   - If `$ARGUMENTS` provided, use it as the gate name (e.g., `content-authenticity`)
   - If no argument, read the gate index and suggest the most relevant gate:
     `$HOME/.ai-first-kit/projects/{SLUG}/gates/INDEX.md`

2. Read the gate file:
   `$HOME/.ai-first-kit/projects/{SLUG}/gates/$ARGUMENTS.md`

3. Extract the **Pass Criteria** section from the gate file.

4. For EACH criterion, evaluate the current work:

   ```
   ## Gate Review: [Gate Name]

   | # | Criterion | Status | Evidence |
   |---|-----------|--------|----------|
   | 1 | [criterion text] | PASS/FAIL | [specific evidence or violation] |
   | 2 | [criterion text] | PASS/FAIL | [specific evidence or violation] |
   ...

   **Self-Review Result:** PASS (all criteria met) / FAIL (N criteria failed)
   ```

5. For each FAIL:
   - Identify the specific fix needed
   - If the fix is within your capability, describe it
   - If the fix requires a different skill/role, note which one

## Phase 2: Holdout Evaluation (Independent Validation)

After completing Phase 1, spawn the holdout evaluator for independent validation.

1. **Check availability**: Attempt to invoke the holdout-evaluator via the Agent
   tool. If the Agent tool reports the skill is not found or the invocation fails,
   skip to Phase 3 with:
   "Holdout validation skipped — evaluator not available. Self-review only."

2. **Prepare inputs**:
   - Gate name from Phase 1
   - Self-review evidence table from Phase 1 (the full table above)
   - File paths of the work output being reviewed (the files you evaluated)

3. **Spawn isolated evaluator**: Use the Agent tool to invoke the holdout-evaluator
   skill in an isolated context. Pass the gate name, evidence table, and file paths.
   The evaluator runs independently and returns mapped feedback.

   IMPORTANT: Do NOT include any holdout scenario content in your conversation.
   The evaluator handles holdout access in its own isolated context.

4. **Receive mapped feedback**: The evaluator returns feedback that references
   only visible gate criteria. Integrate this into the combined result.

## Phase 3: Combined Result

Present the combined gate review result:

```
## Combined Gate Review: [Gate Name]

### Phase 1: Self-Review
[Self-review result table from Phase 1]

### Phase 2: Holdout Validation
[Mapped feedback from holdout evaluator, or "Skipped" if unavailable]

### Overall Result
**PASS** — Both self-review and holdout validation passed.
  OR
**FAIL** — [Which phase(s) failed and summary of weaknesses]
```

**Result logic:**
- PASS only when BOTH self-review AND holdout evaluation pass
- If either fails, overall result is FAIL with feedback from both layers
- If holdout evaluation was skipped, overall result is based on self-review only

If all criteria PASS and holdout validation PASS:
"Gate [name] passed. Ready for the next stage."

If any criteria FAIL or holdout validation FAIL:
"Gate [name] failed. Fixes needed before proceeding."

If self-review PASS but holdout evaluation FAIL:
"Gate [name] failed holdout validation. Your self-review passed but independent
evaluation detected weaknesses. Re-review your work against the flagged criteria,
focusing on the spirit of the criteria — not just the letter."

## Available Gates

The gates available in this project are listed in:
`$HOME/.ai-first-kit/projects/{SLUG}/gates/INDEX.md`

Common gates: `plan-readiness`, `implementation-completeness`, `runtime-verification`,
`content-authenticity`, `release-readiness`

## Rules
- NEVER read holdout files (`gates/.holdouts/`) — they test agents, not for agent consumption
- Review against the VISIBLE pass criteria only in Phase 1
- Every PASS must cite specific evidence (not just "looks good")
- Every FAIL must include a specific fix
- Gate failures feed back to the previous stage — fix root cause, not symptoms
- If holdout evaluation fails but self-review passed, this signals criteria-gaming —
  take the holdout feedback seriously and re-examine your evidence
```

## Substitutions

Replace `{SLUG}` with the project slug derived from git repo root.
Replace `{VERSION}` with the current plugin version.
