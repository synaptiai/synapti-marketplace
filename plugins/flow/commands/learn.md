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
# Output: `###`-headed sections + KEY=value per
# `references/command-output-format.md`.

echo "### Resolved Paths"
# JOURNAL_DIR and PROPOSAL_DIR resolve via the standard settings cascade.
# settings.json may store paths with a leading `~` (literal — JSON has no
# tilde-expansion semantics). The cascade helper returns the value verbatim
# without expansion, so downstream tools that don't auto-expand tildes
# (Read/Write/Edit, Python os.path) would fail. Manually expand `~` to
# $HOME so the agent always receives an absolute path.
HELPER="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh"
JOURNAL_DIR=".decisions"
PROPOSAL_DIR="$HOME/.claude/flow-proposals"
if [ -x "$HELPER" ]; then
  JOURNAL_DIR=$("$HELPER" --default ".decisions" '.journal.dir // empty')
  PROPOSAL_DIR=$("$HELPER" --default "$HOME/.claude/flow-proposals" '.learning.proposalDir // empty')
  echo "STATE=ok"
else
  # Helper missing or non-executable — using compile-time defaults. Surface
  # so the agent knows resolution was best-effort and config might be ignored.
  echo "STATE=unavailable"
  echo "ERROR=cascade-resolve.sh missing or non-executable; using built-in defaults"
fi
# Expand leading `~` to $HOME so downstream Read/Write/Edit tools (which
# don't tilde-expand) receive absolute paths.
JOURNAL_DIR="${JOURNAL_DIR/#\~/$HOME}"
PROPOSAL_DIR="${PROPOSAL_DIR/#\~/$HOME}"
echo "JOURNAL_DIR=$JOURNAL_DIR"
echo "PROPOSAL_DIR=$PROPOSAL_DIR"

echo ""
echo "### Journal Files"
JOURNAL_FILES=0
[ -d "$JOURNAL_DIR" ] && JOURNAL_FILES=$(ls "$JOURNAL_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
echo "JOURNAL_FILE_COUNT=$JOURNAL_FILES"
if [ "$JOURNAL_FILES" = "0" ]; then
  echo "STATE=empty"
else
  ls "$JOURNAL_DIR"/*.md 2>/dev/null | sed 's/^/JOURNAL_FILE=/'
fi

echo ""
echo "### Proposal Files"
PROPOSAL_FILES=0
[ -d "$PROPOSAL_DIR" ] && PROPOSAL_FILES=$(ls "$PROPOSAL_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
echo "PROPOSAL_FILE_COUNT=$PROPOSAL_FILES"
if [ "$PROPOSAL_FILES" = "0" ]; then
  echo "STATE=empty"
else
  ls "$PROPOSAL_DIR"/*.md 2>/dev/null | sed 's/^/PROPOSAL_FILE=/'
fi

# Section: FlowRun Events + FlowGoals (v3)
# Gated behind flow.goals.enabled — when v3 is enabled, surface the goal
# YAMLs + run-event ledgers so Phase 2's Goal Failure Patterns can detect
# recurring failed ACs, stuck-detection hits, and not_executed warnings.
echo ""
echo "### FlowRun Events"
GOALS_ENABLED="false"
[ -x "$HELPER" ] && GOALS_ENABLED=$("$HELPER" --default "true" '.flow.goals.enabled // empty' 2>/dev/null)
if [ "$GOALS_ENABLED" != "true" ]; then
  echo "STATE=disabled"
else
  GOAL_FILES=0
  [ -d ".flow/goals" ] && GOAL_FILES=$(ls .flow/goals/*.goal.yaml 2>/dev/null | wc -l | tr -d ' ')
  RUN_FILES=0
  [ -d ".flow/runs" ] && RUN_FILES=$(find .flow/runs -name "events.jsonl" 2>/dev/null | wc -l | tr -d ' ')
  echo "GOAL_FILE_COUNT=$GOAL_FILES"
  echo "RUN_EVENT_FILE_COUNT=$RUN_FILES"
  if [ "$GOAL_FILES" = "0" ] && [ "$RUN_FILES" = "0" ]; then
    echo "STATE=empty"
  else
    echo "STATE=ok"
    ls .flow/goals/*.goal.yaml 2>/dev/null | sed 's/^/GOAL_FILE=/'
    find .flow/runs -name "events.jsonl" 2>/dev/null | sed 's/^/RUN_EVENTS=/'
  fi
fi

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

### Goal Failure Patterns (v3, when `flow.goals.enabled: true`)

Parse `.flow/goals/*.goal.yaml` and `.flow/runs/*/events.jsonl` to detect goal-level patterns the journal alone can't see:

- **Recurring failed ACs**: same `verification_command` failing across 3+ goals → the command may be wrong, flaky, or testing the wrong thing. Pattern qualifies when the same command string appears in `objective.acceptance_criteria[].verification_command` of ≥3 goals AND the corresponding AC `last_result` shows non-zero exit on each.
- **Stuck-detection hits**: count of `delta == "unchanged"` runs across recent verdicts. A goal that hit `failAfterStuckTurns` is parseable from `last-verdict.json` files + a final `lifecycle.status: failed` with `last_evaluation.reason: stuck_no_progress`. Pattern: 2+ goals failing this way → either ACs are too coarse, or the executor needs different scaffolding.
- **`not_executed` ACs**: across goals, count ACs whose `last_result.reason` includes `not_executed`. If the user has `executeVerificationCommands: false` but goals consistently fail to capture deterministic evidence, suggest flipping the flag.
- **Path-boundary violations**: `events.jsonl` entries with `type: path-boundary-violation` indicate goals whose `allowed_paths` was too narrow OR the executor strayed from scope. Recurring violations of the same path glob → either the glob is too tight, or the workflow's natural scope exceeds the goal's contract.

Pattern qualifies for proposal generation under the same rules as decision patterns: ≥2 occurrences + evidence citations (goal id + AC id + run id + event timestamp).

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
| Read `.flow/goals/*.goal.yaml` + `.flow/runs/*/events.jsonl` (v3) | 1 | Autonomous, read-only |
| Pattern detection across journal entries + goal/run events | 1 | Autonomous |
| Write skill proposals to `~/.claude/flow-proposals/` | 1 | Autonomous, user-scoped files (outside repo) |
| Clear `~/.claude/flow-learn-pending` flag | 1 | Autonomous |

Promotion of a proposal to an active skill (`plugins/flow/skills/learned/`) is **separate** and is owned by `bin/promote-proposal.sh`, which opens a draft PR (Tier 2 — never auto-merges). Learning analysis itself is Tier 1; promotion is Tier 2.
