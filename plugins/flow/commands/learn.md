---
description: "Analyze the decision journal for learnable patterns and generate skill proposals from repeated corrections and common patterns. Use when reviewing session activity to extract reusable knowledge."
allowed-tools: Bash, Read, Write, Grep, Glob
---

# Learn from Decisions

Analyze the decision journal for recurring patterns and generate skill proposals.

## Phase 1: Gather Journal Entries

```bash
# Read journal directory
JOURNAL_DIR=".decisions"
for SETTINGS in ".claude/settings.flow.local.json" ".claude/settings.flow.json" "$HOME/.claude/settings.flow.json" "plugins/flow/settings.json"; do
  [ -f "$SETTINGS" ] && DIR=$(jq -r '.journal.dir // empty' "$SETTINGS" 2>/dev/null) && [ -n "$DIR" ] && JOURNAL_DIR="$DIR" && break
done

# Read proposal directory
PROPOSAL_DIR="$HOME/.claude/flow-proposals"
for SETTINGS in ".claude/settings.flow.local.json" ".claude/settings.flow.json" "$HOME/.claude/settings.flow.json" "plugins/flow/settings.json"; do
  [ -f "$SETTINGS" ] && DIR=$(jq -r '.learning.proposalDir // empty' "$SETTINGS" 2>/dev/null) && [ -n "$DIR" ] && PROPOSAL_DIR="$DIR" && break
done

# List journal files
ls -la "$JOURNAL_DIR"/*.md 2>/dev/null

# Count existing proposals
ls -la "$PROPOSAL_DIR"/*.md 2>/dev/null | wc -l
```

Read all journal files from the current session (today's entries).

## Phase 2: Pattern Analysis

Analyze journal entries for:

### Repeated Corrections
- Same type of fix applied multiple times (e.g., "added missing error handling" appears 3x)
- Same convention violation corrected repeatedly
- Same file structure pattern created repeatedly

### Decision Patterns
- Consistent architectural choices (always choosing X over Y)
- Recurring trade-off resolutions
- Common risk assessments

### Gate Patterns
- Gates that always get approved → candidate for tier demotion
- Gates that frequently trigger → valuable safety check

## Phase 3: Quality Filters

A pattern qualifies for a skill proposal when:

1. **Minimum occurrences**: Pattern appears ≥2 times in journal entries
2. **Evidence citations**: Can cite specific journal entries as evidence
3. **Actionable knowledge**: The pattern can be expressed as a reusable instruction
4. **Not already covered**: No existing skill captures this knowledge

### Fatigue Circuit Breaker

If >5 proposals would be generated in one session:
- Generate only the top 5 (by occurrence count)
- Note: "High activity session — additional patterns detected but deferred"

## Phase 4: Generate Proposals

For each qualifying pattern, create a skill proposal:

```bash
mkdir -p "$PROPOSAL_DIR"
```

Write each proposal to `$PROPOSAL_DIR/YYYY-MM-DD-{topic}.md` using the skill-proposal template.

## Phase 5: Display Summary

```markdown
## Learning Analysis

### Patterns Detected
| # | Pattern | Occurrences | Evidence |
|---|---------|-------------|----------|
| 1 | {pattern description} | {N} | issue-{X}.md, issue-{Y}.md |

### Proposals Generated
| # | Proposal | Path |
|---|----------|------|
| 1 | {skill name} | {proposal file path} |

### Promotion Workflow
To promote a proposal to an active skill:
1. Review the proposal file
2. Copy to `plugins/flow/skills/learned/{name}/SKILL.md`
3. Commit and create PR
```

## Phase 6: Clear Pending

```bash
rm -f "$HOME/.claude/flow-learn-pending"
```

## No Entries Case

If no journal entries found:
- "No decision journal entries found. Journal entries are created automatically during `/flow:start`, `/flow:commit`, and `/flow:address` workflows."
- Suggest running a workflow first.
