---
description: "Analyze the decision journal for learnable patterns and generate skill proposals from repeated corrections and common patterns. Use when reviewing session activity to extract reusable knowledge."
allowed-tools: Bash, Read, Write, Grep, Glob
---

# Learn from Decisions

Analyze the decision journal for recurring patterns and generate skill proposals.

## Required Skills

_None — retrospective pattern analysis over the decision journal. No skill invocations._

## Phase 1: Gather Journal Entries

```!
# Read journal directory and proposal directory via bin/cascade-resolve.sh.
HELPER="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh"
JOURNAL_DIR=".decisions"
PROPOSAL_DIR="$HOME/.claude/flow-proposals"
if [ -x "$HELPER" ]; then
  JOURNAL_DIR=$("$HELPER" --default ".decisions" '.journal.dir // empty')
  PROPOSAL_DIR=$("$HELPER" --default "$HOME/.claude/flow-proposals" '.learning.proposalDir // empty')
fi
echo "JOURNAL_DIR=$JOURNAL_DIR"
echo "PROPOSAL_DIR=$PROPOSAL_DIR"

# List journal files
ls -la "$JOURNAL_DIR"/*.md 2>/dev/null

# Count existing proposals
ls -la "$PROPOSAL_DIR"/*.md 2>/dev/null | wc -l

true
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

To promote a proposal to an active skill, use the canonical helper:

```bash
${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/promote-proposal.sh \
  --proposal ~/.claude/flow-proposals/YYYY-MM-DD-{topic}.md
```

The script:
1. Validates the proposal frontmatter (required fields, status: proposal, kebab-case name)
2. Validates the body (must contain `## Pattern Detected`, `## Knowledge`, `## Evidence`, `## Verification`, `## Promotion Checklist` sections per `templates/skill-proposal.md`)
3. Refuses to overwrite an existing learned skill at the target name
4. Copies the proposal to `plugins/flow/skills/learned/{name}/SKILL.md`, rewriting `status: proposal` -> `status: promoted` with today's date
5. Creates a feature branch `feature/learn-promote-{name}`, commits, pushes, and opens a **draft** PR for human review

The PR is **always draft** — `bin/promote-proposal.sh` is Tier 2 (journal-and-proceed) and never marks the PR ready or merges it. A human reviewer must mark the PR ready and merge it explicitly. This prevents `/flow:learn` from autonomously reshaping Claude's behavior without explicit consent.

Use `--dry-run` to validate a proposal without filesystem effects:

```bash
${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/promote-proposal.sh \
  --proposal ~/.claude/flow-proposals/YYYY-MM-DD-{topic}.md \
  --dry-run
```

The dry-run reports validation results and the planned filesystem/git actions without executing them.
```

## Phase 6: Clear Pending

```bash
rm -f "$HOME/.claude/flow-learn-pending"
```

## No Entries Case

If no journal entries found:
- "No decision journal entries found. Journal entries are created automatically during `/flow:start`, `/flow:commit`, and `/flow:address` workflows."
- Suggest running a workflow first.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read decision journal | 1 | Autonomous, read-only |
| Pattern detection across journal entries | 1 | Autonomous |
| Write skill proposals to `~/.claude/flow-proposals/` | 1 | Autonomous, user-scoped files (outside repo) |
| Clear `~/.claude/flow-learn-pending` flag | 1 | Autonomous |

Promotion of a proposal to an active skill (`plugins/flow/skills/learned/`) is **separate** and is owned by `bin/promote-proposal.sh`, which opens a draft PR (Tier 2 — never auto-merges). Learning analysis itself is Tier 1; promotion is Tier 2.
