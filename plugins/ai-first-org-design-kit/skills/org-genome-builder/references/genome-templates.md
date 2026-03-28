# Organizational Genome Templates

## MISSION.md Template

```markdown
# Mission

## Operational Mission
[What we do, day to day, in language a 12-year-old understands]

## Why We Exist
[What happens to the people we serve if we disappeared tomorrow]

## Who We Serve
[Specific people, not demographics — "Carol" style ICP]

## What We Don't Do
[Explicit exclusions — prevents scope creep for agents]
```

## VALUES.md Template

```markdown
# Values as Decision Rules

## [Value 1: Name]

### Definition
[One sentence — operational, not aspirational]

### Decision Rule
[When faced with [situation type], choose [action] because [value]]

### Real Example
[Actual decision where this value determined the outcome]

### What We Sacrifice
[What we give up by prioritizing this value — every value has a cost]

### Agent Instruction
[How an agent applies this value in practice]

### Conflict Resolution
When [this value] conflicts with [other value]:
- [Condition A] → this value wins
- [Condition B] → other value wins
- [Ambiguous] → escalate with both sides presented

---
[Repeat for each value]
```

## VOICE.md Template

```markdown
# Communication Norms

## External Communication

### Tone
[e.g., "Direct but warm. Never corporate-speak. First person plural."]

### Formality Gradient
| Context | Formality Level | Example |
|---------|----------------|---------|
| Customer email | Professional-warm | [actual example] |
| Social media | Casual-authentic | [actual example] |
| Legal/contracts | Formal-precise | [actual example] |

### Words We Use
[Specific vocabulary that represents us]

### Words We Never Use
[Specific vocabulary that doesn't represent us — e.g., "leverage", "synergy"]

## Internal Communication

### Tone
[e.g., "Blunt, fast, no hedging. Disagreement is expected."]

### Response Time Expectations
| Channel | Expected Response | Escalation If No Response |
|---------|------------------|--------------------------|
| Slack | Same day | None — async is fine |
| Email | 24 hours | Follow up on Slack |
| Urgent flag | 1 hour | Phone call |
```

## AUTHORITY-MATRIX.md Template

```markdown
# Decision Authority Matrix

## Fully Autonomous (Agent decides, logs, proceeds)
| Decision Type | Examples | Rationale |
|--------------|----------|-----------|
| [Type] | [Examples] | [Why autonomous is safe] |

## Autonomous with Notification (Agent decides, notifies human)
| Decision Type | Examples | Notification To | Rationale |
|...

## Human-in-Loop (Agent recommends, human approves)
| Decision Type | Examples | Who Approves | Max Wait Time | Default If No Response |
|...

## Human-Only (Agent surfaces info, human decides and acts)
| Decision Type | Examples | Why Agent Cannot Decide |
|...

## Authority Escalation
If unsure which level applies → treat as one level higher.
If time-sensitive and human unavailable → see time-bound defaults in escalation protocols.
```

## TRADEOFF-RULES.md Template

```markdown
# Value Conflict Resolution Rules

When organizational values conflict, use these rules to decide.

## Rule: [Value A] vs [Value B]

**When they conflict:** [Describe the scenario where both apply but pull in different directions]

**Default winner:** [Which value takes priority]

**Exception:** [When the other value wins instead]

**Example:**
> [Concrete scenario showing the tradeoff in action]
> Decision: [What we chose and why]

## Priority Ordering

When multiple values apply simultaneously:
1. [Highest priority value] — always wins unless...
2. [Second priority] — wins when [condition]
3. [Third priority] — the tiebreaker

## Agent Instructions

When facing a value conflict:
1. Identify which values are in tension
2. Check this document for a specific rule
3. If no rule exists → escalate to human with both options clearly stated
4. Log the conflict and resolution for future rule creation
```

## BY-OUTPUT-TYPE.md Template

```markdown
# Quality Standards by Output Type

## [Output Type 1: e.g., Client Proposal]

### What "Good" Looks Like
- [Specific marker 1]
- [Specific marker 2]
- [Specific marker 3]

### Pass Criteria
1. [Testable criterion — an evaluator could check this]
2. [Testable criterion]

### Anti-Patterns (What's Not Acceptable)
- [Specific anti-pattern with why it fails]
- [Specific anti-pattern]

### Example: Good
[Actual example or description of excellent output]

### Example: Not Acceptable
[Actual example or description of rejected output, with explanation of what's wrong]

---
[Repeat for each output type]
```

## ANTI-PATTERNS.md Template

```markdown
# Organizational Anti-Patterns

Things that are technically correct but "not us." These are taste markers —
the difference between generic output and output that feels like it came
from this organization.

## Anti-Pattern: [Name]
- **What it looks like:** [Description]
- **Why it's wrong for us:** [Specific reason tied to values]
- **What to do instead:** [The alternative]

## Anti-Pattern: [Name]
[Repeat]
```
