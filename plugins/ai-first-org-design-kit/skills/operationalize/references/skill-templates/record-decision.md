# Skill Template: org-record-decision

Generate this skill at `.claude/skills/org-record-decision/SKILL.md` in the target project.

## Template

```markdown
---
name: org-record-decision
description: "Record a decision to the organizational decision ledger. Use when making Autonomous+Notify decisions or above, logging architectural choices, documenting policy decisions, or recording any significant judgment call."
allowed-tools: Read, Write, Edit
---
<!-- generated-by: ai-first-kit v{VERSION} -->

# Record Decision

Append a structured entry to the organizational decision ledger.

## Process

1. Read the decision ledger format:
   `$HOME/.ai-first-kit/projects/{SLUG}/governance/DECISION-LEDGER-SPEC.md`

2. Read the existing ledger (if it exists):
   `$HOME/.ai-first-kit/projects/{SLUG}/evolution/decision-ledger.md`

3. Construct the entry from $ARGUMENTS or from the current conversation context:

   ```markdown
   ---

   ## Decision: [Brief Title]

   **Timestamp:** [ISO 8601]
   **Agent type:** [Your role/agent type]
   **Authority level used:** [Autonomous / Autonomous+Notify / Human-in-Loop]
   **Context:** [What triggered this decision — 1-2 sentences]
   **Options considered:** [What alternatives existed]
   **Decision made:** [The choice]
   **Reasoning:** [Why — grounded in values or evidence]
   **Policy reference:** [Which governance doc is relevant, or "novel situation"]
   **Outcome:** Pending
   ```

4. Append the entry to `$HOME/.ai-first-kit/projects/{SLUG}/evolution/decision-ledger.md`
   - Use the Edit tool to append at end of file
   - If file doesn't exist, create it with the header from DECISION-LEDGER-SPEC.md first
   - **NEVER modify existing entries** — append only

5. Confirm: "Decision recorded: [brief title]"

## Rules
- Entries are **append-only** — never modify or delete existing entries
- If a prior decision needs correction, append a NEW entry that references and supersedes it
- Every entry must have a timestamp and authority level
- The decision must be grounded in organizational values or governance
```

## Substitutions

Replace `{SLUG}` with the project slug derived from git repo root.
Replace `{VERSION}` with the current plugin version (e.g., 1.4.0).
