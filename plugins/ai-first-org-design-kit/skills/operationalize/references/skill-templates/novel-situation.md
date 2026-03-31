# Skill Template: org-novel-situation

Generate this skill at `.claude/skills/org-novel-situation/SKILL.md` in the target project.

## Template

```markdown
---
name: org-novel-situation
description: "Handle a novel situation with no existing governance policy. Use when encountering a scenario the authority matrix and policies don't cover, when governance has a gap, or when a new type of decision needs a policy."
allowed-tools: Read, Write, AskUserQuestion
<!-- generated-by: ai-first-kit v{VERSION} -->
---

# Novel Situation Handler

When you encounter a situation with no existing policy, draft a candidate policy and escalate.

## Process

1. Read the policy generation protocol:
   `$HOME/.ai-first-kit/projects/{SLUG}/governance/POLICY-GENERATION.md`

2. **Recognize** — Confirm this is genuinely novel:
   - Check `$HOME/.ai-first-kit/projects/{SLUG}/governance/AUTHORITY-MATRIX.md` — is this really not covered?
   - Check `$HOME/.ai-first-kit/projects/{SLUG}/governance/HARD-BOUNDARIES.md` — does a boundary apply?
   - If a policy exists, use it. Only proceed if genuinely novel.

3. **Analyze** — What makes this novel?
   - What adjacent policies exist that are close but don't cover this?
   - What's the risk if handled incorrectly?
   - Which organizational values are most relevant?

4. **Draft candidate policy** using the template from POLICY-GENERATION.md:

   ```markdown
   ## Candidate Policy: [Name]
   **Trigger:** [When does this apply?]
   **Action:** [What should the agent do?]
   **Boundary:** [What should the agent NOT do?]
   **Authority level:** [Which tier? Start conservative — Human-in-Loop or Human-Only]
   **Rationale:** [Why this policy?]
   **Grounded in:** [Which genome values support this?]
   ```

5. **Escalate** — Present to the human with:
   - The novel situation description
   - The drafted candidate policy
   - Your recommendation for authority level
   - What happens if this isn't addressed (risk)

6. **Record** — Use `/org-record-decision` to log this novel situation and the escalation.

## Rules
- Always start with the MOST CONSERVATIVE authority level (Human-Only or Human-in-Loop)
- Never assume a novel situation should be Autonomous — that's earned through the promotion path
- Ground every candidate policy in organizational values (read VALUES.md if needed)
- If the situation involves a hard boundary → this is NOT novel, it's a boundary enforcement
```

## Substitutions

Replace `{SLUG}` with the project slug derived from git repo root.
Replace `{VERSION}` with the current plugin version.
