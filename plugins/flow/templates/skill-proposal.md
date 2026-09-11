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

## Contract

{At most 120 words, and the first H2 in the file — promotion refuses a proposal
without it. Iron law in one sentence; when the knowledge applies; what following
it produces; permitted skips (usually "none"). Match the shape of the Contract
in any `plugins/flow/skills/*/SKILL.md`.}

## Pattern Detected

{Removed from the promoted skill by `bin/promote-proposal.sh` and published in
the promotion pull request instead — this section argues for promotion, and the
promoted file is read by an agent about to act.}

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

{Removed from the promoted skill and published in the promotion pull request
body instead. Journal paths name issues in the project the pattern was mined
from; they resolve in no repository the skill is later installed into.

This text becomes public when the pull request opens. `/flow:learn` mines
whatever project you were standing in, which may be private — quote only what a
reader outside that project may see, and run `--dry-run` first to read exactly
what would be published.}

### Journal Citations

{List of specific journal entries that demonstrate this pattern:}

- `{journal-dir}/issue-{N}.md` @ {timestamp}: "{decision title}"
- `{journal-dir}/issue-{M}.md` @ {timestamp}: "{decision title}"

### Transcript Citations

{User corrections mined from session transcripts by `/flow:learn` Phase 2 (`bin/flow-mine-corrections.sh`). Every line was re-read and verified before being listed; quote only the user's words, truncated. Delete this subsection when the pattern has no transcript evidence.}

- `{transcript_path}:{line_no}` @ {timestamp} (session `{session_id}`): "{what the user said}"
- `{transcript_path}:{line_no}` @ {timestamp} (session `{session_id}`): "{what the user said}"

### Example

{A concrete example showing the pattern in action:}

```
{Before: what was done without this knowledge}
{After: what should be done with this knowledge}
```

## Enforcement point

{Removed from the promoted skill. Enforcement proposals only — delete this section for a new-skill proposal. Use it when Phase 2 labelled the pattern `rule exists in <skill>`: the rule was already written down and still broken, so the proposal is to make it mechanical rather than to write it again.}

- **Rule already stated in**: `plugins/flow/skills/{skill}/SKILL.md` — "{the sentence that states the rule}"
- **Check point**: {hook event (`PreToolUse` / `PostToolUse` / `Stop` / `TaskCompleted` / `SessionEnd`) or command gate/phase, e.g. `/flow:pr` Phase 3}
- **What the check reads**: {tool input / tool response / files / run ledger}
- **On violation**: {block with reason | warn | record finding} — {the exact stderr or reason text}
- **Why the words were not enough**: {what the transcript evidence shows about when the rule was out of context}

## Verification

{How to verify this skill is being applied correctly:}

- [ ] {Verification criterion 1}
- [ ] {Verification criterion 2}

## Promotion Checklist

{Removed from the promoted skill — the last two boxes describe the PR that
carries it. `source-sessions`, `evidence-count` and `proposed` are removed from
the frontmatter for the same reason and published alongside this section.}

- [ ] Reviewed by human
- [ ] Evidence is compelling (not coincidental)
- [ ] Knowledge is general (not issue-specific)
- [ ] Doesn't duplicate existing skills
- [ ] Fits within context window budget
- [ ] Copied to `plugins/flow/skills/learned/{name}/SKILL.md`
- [ ] Committed and PR created
