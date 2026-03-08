---
name: "{proposal-name}"
description: "[flow-learned] {one-line description of the knowledge this skill captures}"
source-sessions:
  - "{YYYY-MM-DD session identifier}"
evidence-count: {N}
status: proposal
proposed: "{YYYY-MM-DD}"
---

# {Skill Name}

## Pattern Detected

{Description of the recurring pattern that was identified from decision journal analysis.}

## Knowledge

{The reusable knowledge extracted from the pattern. Written as instructions that Claude should follow when the pattern applies.}

### When This Applies

{Conditions under which this knowledge is relevant.}

### What To Do

{Step-by-step guidance based on the learned pattern.}

### What To Avoid

{Anti-patterns or mistakes this knowledge helps prevent.}

## Evidence

### Journal Citations

{List of specific journal entries that demonstrate this pattern:}

- `{journal-dir}/issue-{N}.md` @ {timestamp}: "{decision title}"
- `{journal-dir}/issue-{M}.md` @ {timestamp}: "{decision title}"

### Example

{A concrete example showing the pattern in action:}

```
{Before: what was done without this knowledge}
{After: what should be done with this knowledge}
```

## Verification

{How to verify this skill is being applied correctly:}

- [ ] {Verification criterion 1}
- [ ] {Verification criterion 2}

## Promotion Checklist

- [ ] Reviewed by human
- [ ] Evidence is compelling (not coincidental)
- [ ] Knowledge is general (not issue-specific)
- [ ] Doesn't duplicate existing skills
- [ ] Fits within context window budget
- [ ] Copied to `plugins/flow/skills/learned/{name}/SKILL.md`
- [ ] Committed and PR created
