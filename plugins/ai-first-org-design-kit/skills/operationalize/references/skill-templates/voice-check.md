# Skill Template: org-voice-check

Generate this skill at `.claude/skills/org-voice-check/SKILL.md` in the target project.

## Template

```markdown
---
name: org-voice-check
description: "Review content against organizational voice norms before publishing. Use before publishing articles, documentation, external communications, or any content visible to people outside the organization."
allowed-tools: Read
context: fork  # Runs in isolated context — voice review should not pollute main conversation
agent: general-purpose
---
<!-- generated-by: ai-first-kit v{VERSION} -->

# Voice Check

Review content against organizational voice norms.

## Process

1. Read the voice specification:
   `$HOME/.ai-first-kit/projects/{SLUG}/genome/00-identity/VOICE.md`

2. Identify the **target channel** for this content (LinkedIn, Medium, docs, Slack, outreach).
   Apply the formality gradient from VOICE.md.

3. Check against voice criteria:

   ### Words We Use
   Scan content for presence of approved vocabulary. Note if the content sounds generic
   rather than using the organization's characteristic language.

   ### Words We Never Use
   Scan for banned vocabulary. Flag every occurrence with the specific word and line.

   ### AI-Slop Detection
   Check for AI-tell phrases: "delve into", "it's important to note",
   "in today's rapidly evolving landscape", "stands as a testament",
   "paving the way", "at the forefront", "without further ado".
   Flag every occurrence.

   ### Formality Match
   Does the tone match the target channel? Professional-substantive for LinkedIn,
   direct-practical for docs, direct-conversational for Slack.

   ### Substance Check
   Could any paragraph be removed without losing value? Flag fluff sections.

4. Produce a **pass/fail report**:

   ```
   ## Voice Check Report

   **Target channel:** [channel]
   **Expected formality:** [level from gradient]

   ### Results
   - [ ] No banned words: {PASS/FAIL — list violations}
   - [ ] No AI-slop markers: {PASS/FAIL — list violations}
   - [ ] Formality matches channel: {PASS/FAIL — specific mismatches}
   - [ ] Approved vocabulary present: {PASS/FAIL — suggestions}
   - [ ] No fluff paragraphs: {PASS/FAIL — which sections}

   ### Specific Fixes
   {For each failure, the exact fix with before/after}

   **Overall:** PASS / NEEDS REVISION
   ```

## Rules
- Every failure must include a specific fix, not just a flag
- Check the FULL content, not just the first few paragraphs
- The voice check is about TONE, not factual accuracy (that's the Content Authenticity gate)
- Content that passes voice check may still fail other gates
```

## Substitutions

Replace `{SLUG}` with the project slug derived from git repo root.
Replace `{VERSION}` with the current plugin version.
