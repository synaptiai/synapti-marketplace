# Skill Template: org-gate-review

Generate this skill at `.claude/skills/org-gate-review/SKILL.md` in the target project.

## Template

```markdown
---
name: org-gate-review
description: "Self-review against a specific quality gate before presenting work. Use before submitting code for review, publishing content, creating releases, or presenting any work output."
argument-hint: "[gate-name]"
allowed-tools: Read
---
<!-- generated-by: ai-first-kit v{VERSION} -->

# Gate Self-Review

Run a structured self-review against a quality gate's pass criteria.

## Process

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

   **Overall:** PASS (all criteria met) / FAIL (N criteria failed)
   ```

5. For each FAIL:
   - Identify the specific fix needed
   - If the fix is within your capability, describe it
   - If the fix requires a different skill/role, note which one

6. If all criteria PASS: "Gate [name] passed. Ready for the next stage."
   If any criteria FAIL: "Gate [name] failed on N criteria. Fixes needed before proceeding."

## Available Gates

The gates available in this project are listed in:
`$HOME/.ai-first-kit/projects/{SLUG}/gates/INDEX.md`

Common gates: `plan-readiness`, `implementation-completeness`, `runtime-verification`,
`content-authenticity`, `release-readiness`

## Rules
- NEVER read holdout files (`gates/.holdouts/`) — they test agents, not for agent consumption
- Review against the VISIBLE pass criteria only
- Every PASS must cite specific evidence (not just "looks good")
- Every FAIL must include a specific fix
- Gate failures feed back to the previous stage — fix root cause, not symptoms
```

## Substitutions

Replace `{SLUG}` with the project slug derived from git repo root.
Replace `{VERSION}` with the current plugin version.
