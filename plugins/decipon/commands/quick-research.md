---
description: Quick research with source verification (lighter than /deep-research)
argument-hint: <question or topic>
model: sonnet
---

# Quick Research: $ARGUMENTS

Research with source verification (2-3 searches max).

## Process

1. **Search** for relevant sources

2. **After each search**, note:
   - Key facts (High/Medium/Low confidence)
   - Any contradictions

3. **Deliver**:

```
## Answer
[Direct response]

## Supporting Evidence
- [Fact] ([Source], [confidence])
- [Fact] ([Source], [confidence])

## Confidence: [High/Medium/Low]
[justification]

## Caveats
[limitations]
```

## User Interaction

Use the **AskUserQuestion tool** when:
- Question is too broad for quick research
- Clarification needed between quick vs deep research
- Low confidence result warrants escalation decision

### Example Invocations

**Broad question:**
```
User: /quick-research climate change
→ Use AskUserQuestion tool:
  Question: "This topic is broad for quick research. What specific question?"
  Options:
  - "Latest IPCC report findings"
  - "Current global temperature trends"
  - "Switch to /deep-research for comprehensive coverage"
```

**Low confidence result:**
```
After research: Confidence LOW (conflicting sources)
→ Use AskUserQuestion tool:
  Question: "Quick research found conflicting information. How to proceed?"
  Options:
  - "Accept low-confidence answer with caveats"
  - "Escalate to /deep-research for thorough verification"
  - "Try different search queries"
```

**Escalation decision:**
```
User: /quick-research [complex multi-part question]
→ Use AskUserQuestion tool:
  Question: "This question may need deeper research. Which approach?"
  Options:
  - "Quick research (2-3 searches, faster)"
  - "Deep research (5-10 searches, more thorough)" (Recommended)
  - "Start quick, escalate if needed"
```

Begin now.
