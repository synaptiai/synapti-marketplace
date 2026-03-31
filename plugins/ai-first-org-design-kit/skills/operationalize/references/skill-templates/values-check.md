# Skill Template: org-values-check

Generate this skill at `.claude/skills/org-values-check/SKILL.md` in the target project.

## Template

```markdown
---
name: org-values-check
description: "Check a decision against organizational values and tradeoff rules. Use when values conflict, when making decisions that affect quality vs speed, simplicity vs completeness, or autonomy vs asking first."
allowed-tools: Read
<!-- generated-by: ai-first-kit v{VERSION} -->
---

# Values Check

Evaluate a decision or proposed action against organizational values and tradeoff rules.

## Process

1. Read the organizational values:
   `$HOME/.ai-first-kit/projects/{SLUG}/genome/00-identity/VALUES.md`

2. Read the tradeoff rules:
   `$HOME/.ai-first-kit/projects/{SLUG}/genome/01-decision-architecture/TRADEOFF-RULES.md`

3. Identify the decision or action to evaluate:
   - From `$ARGUMENTS` if provided
   - From the current conversation context if not

4. Determine which values are in tension:
   - Which values apply to this decision?
   - Do any conflict?

5. Apply the tradeoff rules:
   - Check the Priority Ordering (which value wins when they conflict)
   - Check for specific rules (e.g., "Quality vs Speed" → quality always wins)
   - Check the audience distinction (personal use vs public/adoption-facing)

6. Produce a **values assessment**:

   ```
   ## Values Assessment

   **Decision:** [What's being decided]

   **Values in play:**
   - [Value 1]: [How it applies — supports or opposes the decision]
   - [Value 2]: [How it applies]

   **Conflict?** Yes / No
   **If conflict, resolution rule:** [From TRADEOFF-RULES.md]
   **Audience consideration:** [Personal use vs public — this often breaks ties]

   **Recommendation:** [What the values say to do]
   **Confidence:** High / Medium / Low
   **If Low:** Escalate with this assessment as context
   ```

## Rules
- Always read the FULL VALUES.md and TRADEOFF-RULES.md — don't rely on memory
- The priority ordering is authoritative: Quality > Simplicity > Autonomy > Observation
- Audience breaks ties: building for self → quality wins; building for others → simplicity gates
- If no tradeoff rule covers this specific conflict → flag as novel and recommend escalation
- This skill evaluates, it doesn't decide — present the assessment, let the human or agent decide
```

## Substitutions

Replace `{SLUG}` with the project slug derived from git repo root.
Replace `{VERSION}` with the current plugin version.
