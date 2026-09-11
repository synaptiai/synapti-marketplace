---
description: "Analyze the decision journal and session transcripts for learnable patterns and generate skill or enforcement proposals from repeated user corrections and common patterns. Use when reviewing session activity to extract reusable knowledge."
allowed-tools: Bash, Read, Write, Grep, Glob
---

# Learn from Decisions

Analyze the decision journal and the session transcripts for recurring patterns and generate skill proposals.

The journal and run ledgers only contain what flow wrote about itself. The corrections a user actually made ("that's not what I asked", "I opened it and it is empty", "why didn't you run the tests?") live in the Claude Code session transcripts, so Phase 1 mines those too.

## Required Skills

_None — retrospective pattern analysis over the decision journal and transcripts. No skill invocations._

## Phase 1: Gather Journal Entries

```!
# Output: `###`-headed sections + KEY=value per
# `references/command-output-format.md`.

echo "### Resolved Paths"
# JOURNAL_DIR and PROPOSAL_DIR resolve via the standard settings cascade.
# settings.json may store paths with a leading `~` (literal — JSON has no
# tilde-expansion semantics). The cascade helper returns the value verbatim
# without expansion, so downstream tools that do not auto-expand tildes
# (Read/Write/Edit, Python os.path) would fail. Manually expand `~` to
# $HOME so the agent always receives an absolute path.
HELPER="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/cascade-resolve.sh"
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
# do not tilde-expand) receive absolute paths.
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
# YAMLs + run-event ledgers so the Phase 2 Goal Failure Patterns can detect
# recurring failed ACs, stuck-detection hits, and not_executed warnings.
echo ""
echo "### FlowRun Events"
GOALS_ENABLED="false"
[ -x "$HELPER" ] && GOALS_ENABLED=$("$HELPER" --default "true" '.flow.goals.enabled' 2>/dev/null)
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

# Section: Transcript Corrections
# learning.sources (JSON array, default ["journal","transcripts"]) selects the
# evidence sources this command reads. Session transcripts are the Claude Code
# own logs under ~/.claude/projects/<slug>/ (override: learning.transcriptDir,
# empty = auto) — read-only, user-scoped, never written here. The miner keeps
# recall-oriented candidates; Phase 2 does the judging.
echo ""
echo "### Transcript Corrections"
LEARN_SOURCES='["journal","transcripts"]'
[ -x "$HELPER" ] && LEARN_SOURCES=$("$HELPER" --compact --default '["journal","transcripts"]' '.learning.sources // empty' 2>/dev/null)
echo "TRANSCRIPT_SOURCES=$LEARN_SOURCES"
TRANSCRIPTS_ON="false"
if command -v jq >/dev/null 2>&1; then
  TRANSCRIPTS_ON=$(printf '%s' "$LEARN_SOURCES" | jq -r 'type == "array" and any(.[]; . == "transcripts")' 2>/dev/null)
else
  case "$LEARN_SOURCES" in *transcripts*) TRANSCRIPTS_ON="true" ;; esac
fi
MINER="$(dirname "$HELPER")/flow-mine-corrections.sh"
TRANSCRIPT_DIR_SETTING=""
[ -x "$HELPER" ] && TRANSCRIPT_DIR_SETTING=$("$HELPER" --default "" '.learning.transcriptDir // empty' 2>/dev/null)
TRANSCRIPT_DIR_SETTING="${TRANSCRIPT_DIR_SETTING/#\~/$HOME}"
if [ "$TRANSCRIPTS_ON" != "true" ]; then
  echo "TRANSCRIPT_STATE=disabled"
  echo "CANDIDATE_COUNT=0"
elif [ ! -x "$MINER" ]; then
  echo "TRANSCRIPT_STATE=missing"
  echo "ERROR=flow-mine-corrections.sh missing or non-executable next to cascade-resolve.sh"
  echo "CANDIDATE_COUNT=0"
else
  if [ -n "$TRANSCRIPT_DIR_SETTING" ]; then
    MINER_OUT=$("$MINER" --format markdown --max-sessions 50 --transcript-dir "$TRANSCRIPT_DIR_SETTING" 2>/dev/null)
  else
    MINER_OUT=$("$MINER" --format markdown --max-sessions 50 2>/dev/null)
  fi
  case "$MINER_OUT" in
    *TRANSCRIPT_DIR_STATE=ok*) echo "TRANSCRIPT_STATE=ok" ;;
    *) echo "TRANSCRIPT_STATE=missing" ;;
  esac
  if [ -n "$MINER_OUT" ]; then
    printf '%s\n' "$MINER_OUT"
  else
    echo "ERROR=flow-mine-corrections.sh produced no output"
    echo "CANDIDATE_COUNT=0"
  fi
fi

true
```

Read all journal files from the current session (today's entries). The `### Transcript Corrections` table is already in context — do not re-run the miner; re-read individual cited lines only (Phase 2).

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

### Correction Patterns (transcript source)

Source: the `### Transcript Corrections` table from Phase 1, when `TRANSCRIPT_STATE=ok`. Skip this category when the state is `disabled` or `missing`, or when `CANDIDATE_COUNT=0`. Every row is a *candidate* selected by the recall-oriented keyword filter in `bin/flow-mine-corrections.sh` (`REACTION_PHRASES`); most rows are noise, and this phase is where the judging happens.

1. **Verify before counting.** For each row you intend to cite, re-read the cited transcript line (`sed -n '<line_no>p' <transcript_path>`, or `Read` with an offset) and confirm the user is correcting the assistant's previous turn — not giving a new task, asking about the codebase, or thanking. Drop rows that do not survive. Quote only the user's turn and the truncated assistant context; never paste whole assistant turns or tool results into the analysis.
2. **Cluster by what the user asked for**, not by wording. "I opened it and it is empty", "the file has nothing in it", and "why is the output blank?" are one cluster: *verify the output exists before reporting done*. Name every cluster as the behaviour the user wanted.
3. **Threshold.** A cluster qualifies only with ≥3 verified instances across ≥2 distinct sessions (`Session` column). Repeats inside one session show one bad session, not a habit.
4. **Cross-reference existing skills.** For each qualifying cluster, search for the rule with 2–3 phrasings: `grep -ril '<key phrase>' plugins/flow/skills` (use the plugin root from Phase 1 when not running inside this repo). Label the cluster `rule exists in <skill>` when a skill already states the behaviour, otherwise `no rule`.
5. Record per cluster: name, verified instance count, session count, cited lines (`transcript_path:line_no`), and the label. These feed Phase 3 and the Phase 5 table.

## Phase 3: Quality Filters

A pattern qualifies for a skill proposal when:

1. **Minimum occurrences**: Pattern appears ≥2 times in journal entries
2. **Evidence citations**: Can cite specific journal entries as evidence
3. **Actionable knowledge**: The pattern can be expressed as a reusable instruction
4. **Not already covered**: No existing skill captures this knowledge

### Transcript-sourced Patterns

Correction patterns from Phase 2 use their own threshold (≥3 verified instances across ≥2 sessions) in place of filter 1, and transcript line citations satisfy filter 2. Filter 4 changes what gets proposed rather than whether:

- `no rule` → a standard skill proposal, with transcript citations as evidence.
- `rule exists in <skill>` → **not** a new skill. The words were already in a skill and were still broken, so the proposal is of type `enforcement`: name the skill holding the rule, the mechanical check point (which hook — `PreToolUse`, `PostToolUse`, `Stop`, `TaskCompleted`, `SessionEnd` — or which command gate/phase), what the check reads, and what it blocks or warns on. Fill in the template's `## Enforcement point` section and cite transcript lines under `## Evidence`. Skip the proposal only when an existing hook or gate already enforces the rule mechanically — cite the script.

### Fatigue Circuit Breaker

If >5 proposals would be generated in one session:
- Generate only the top 5 (by occurrence count)
- Note: "High activity session — additional patterns detected but deferred"

## Phase 4: Generate Proposals

For each qualifying pattern, create a skill proposal:

```bash
mkdir -p "$PROPOSAL_DIR"
```

Write each proposal to `$PROPOSAL_DIR/YYYY-MM-DD-{topic}.md` using the skill-proposal template. Enforcement proposals (Phase 3) keep the same template and required sections, add the `## Enforcement point` section, and use the `-enforcement` topic suffix (e.g. `YYYY-MM-DD-verify-output-enforcement.md`) so reviewers can tell them from new-skill proposals at a glance.

## Phase 5: Display Summary

```markdown
## Learning Analysis

### Patterns Detected
| # | Pattern | Source | Occurrences | Evidence |
|---|---------|--------|-------------|----------|
| 1 | {pattern description} | journal | {N} | issue-{X}.md, issue-{Y}.md |
| 2 | {behaviour the user asked for} | transcripts ({sessions} sessions) — {rule exists in <skill> \| no rule} | {N verified} | {transcript_path}:{line_no}, … |

### Proposals Generated
| # | Proposal | Type | Path |
|---|----------|------|------|
| 1 | {skill name} | skill \| enforcement | {proposal file path} |

### Promotion Workflow

To promote a proposal to an active skill, use the canonical helper:

```bash
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/promote-proposal.sh" \
  --proposal ~/.claude/flow-proposals/YYYY-MM-DD-{topic}.md
```

The script:
1. Validates the proposal frontmatter (required fields, status: proposal, kebab-case name)
2. Validates the body (must contain `## Contract`, `## Pattern Detected`, `## Knowledge`, `## Evidence`, `## Verification`, `## Promotion Checklist` sections per `templates/skill-proposal.md`)
3. Refuses to overwrite an existing learned skill at the target name
4. Writes `plugins/flow/skills/learned/{name}/SKILL.md`, rewriting `status: proposal` -> `status: promoted` with today's date and removing `## Pattern Detected`, `## Evidence`, `## Enforcement point`, `## Promotion Checklist` and the `source-sessions` / `evidence-count` / `proposed` frontmatter — those argue for promotion or name the project the pattern was mined in, while the installed file is read by an agent about to act. All of it is published in the pull request body, where it can still be edited before merge. It then refuses the promotion unless the result is skill-shaped: `## Contract` first, at most 120 contract words and 600 body words.
5. Creates a feature branch `feature/learn-promote-{name}`, commits, pushes, and opens a **draft** PR for human review

The PR is **always draft** — `bin/promote-proposal.sh` is Tier 2 (journal-and-proceed) and never marks the PR ready or merges it. A human reviewer must mark the PR ready and merge it explicitly. This prevents `/flow:learn` from autonomously reshaping Claude's behavior without explicit consent.

Use `--dry-run` to validate a proposal without filesystem effects:

```bash
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/promote-proposal.sh" \
  --proposal ~/.claude/flow-proposals/YYYY-MM-DD-{topic}.md \
  --dry-run
```

The dry-run reports validation results and the planned filesystem/git actions without executing them. It also runs the real transform against a throwaway copy, so it catches a proposal that would not promote to a well-formed skill, and prints the material the pull request would publish — the last point at which you can decide something mined from another project should not go public.
```

## Phase 6: Clear Pending

```bash
rm -f "$HOME/.claude/flow-learn-pending"
```

## No Entries Case

If no journal entries found:
- "No decision journal entries found. Journal entries are created automatically during `/flow:start`, `/flow:commit`, and `/flow:address` workflows."
- Suggest running a workflow first.

State the transcript half plainly, because it is the half that carries the behavioural signal and the half that fails silently.

- `TRANSCRIPT_STATE=ok` and `CANDIDATE_COUNT=0`: "No correction candidates in the last `SESSION_COUNT` transcripts." The source was read and held nothing.
- `TRANSCRIPT_STATE=missing`: say the transcript half produced nothing **and why** — name every root from `TRANSCRIPT_ROOTS_TRIED`, not just the one path, and say that `learning.transcriptDir` or `CLAUDE_TRANSCRIPT_DIR` points at it. Do not let this read as "no corrections found": the corrections a user actually made live in the transcripts, so a run without them has seen only what flow wrote about itself.
- `disabled`: say transcripts are off via `learning.sources`.

The two states are different findings. One says the evidence was read and was empty; the other says the evidence was never reached.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read decision journal | 1 | Autonomous, read-only |
| Read `.flow/goals/*.goal.yaml` + `.flow/runs/*/events.jsonl` (v3) | 1 | Autonomous, read-only |
| Read session transcripts under `~/.claude/projects/<slug>/` via `bin/flow-mine-corrections.sh` | 1 | Autonomous, read-only, user-scoped files (outside repo); gated by `learning.sources` |
| Pattern detection across journal entries + goal/run events + transcript corrections | 1 | Autonomous |
| Write skill proposals to `~/.claude/flow-proposals/` | 1 | Autonomous, user-scoped files (outside repo) |
| Clear `~/.claude/flow-learn-pending` flag | 1 | Autonomous |

Promotion of a proposal to an active skill (`plugins/flow/skills/learned/`) is **separate** and is owned by `bin/promote-proposal.sh`, which opens a draft PR (Tier 2 — never auto-merges). Learning analysis itself is Tier 1; promotion is Tier 2.
