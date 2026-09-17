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

# Section: Dismissal Artifacts
echo ""
echo "### Dismissal Artifacts"
# DISMISSAL_ARTIFACTS_BLOCK_BEGIN
# Findings the team rejected. `review.md` has written `dropped-finding`
# artifacts since it was added, with a comment saying it does so "so /flow:learn
# can detect repeated drop reasons across cycles" — and nothing here read them.
# This is the first category that reads the journal manifest rather than the
# freeform body.
#
# The two types are different records and both matter: `dropped-finding` says a
# finding did not survive the review machinery, `finding-dismissed` says a human
# rejected it on stated grounds. Only the second is evidence for an exception,
# so they are counted apart.
DISMISSAL_JOURNAL_DIR="${JOURNAL_DIR:-.decisions}"
# The reader is bin/_journal_manifest.py, shared with the DISPUTED_ARRAY_BLOCK
# in address.md and taking its fence predicate from bin/_journal_atomic.py.
# Resolved the same way every other helper in this command is.
# No apostrophes in these comments: this is an inline-! block, and an unpaired
# one kills the whole block on the Windows executor.
FLOW_ROOT="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")"
# Probed for the same reason PyYAML is below: the import sits above the first
# print, so on an install where the reader is missing this block would die
# before emitting any STATE line — and a missing STATE line reads exactly like
# a project that has dismissed nothing.
if [ ! -f "$FLOW_ROOT/bin/_journal_manifest.py" ]; then
  echo "DISMISSED_COUNT=0"
  echo "DROPPED_COUNT=0"
  echo "STATE=unavailable"
  echo "REASON=the shared journal reader could not be located, so whether this project has recorded dismissals is unknown"
else
# Probe before the heredoc. `import yaml` sits above the try below, so a machine
# without PyYAML dies before the first print and the section is a bare heading —
# no STATE line at all, which Phase 2 reads as "this project has dismissed
# nothing". Every sibling block in start.md and status.md probes first.
if ! command -v python3 >/dev/null 2>&1 || \
     ! PYTHONSAFEPATH=1 python3 -c 'import sys
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
import yaml' >/dev/null 2>&1; then
  echo "DISMISSED_COUNT=0"
  echo "DROPPED_COUNT=0"
  echo "STATE=unavailable"
  echo "REASON=python3 with PyYAML is required to read the journal manifests, so whether this project has recorded dismissals is unknown"
else
DISMISSAL_OUT=$(PYTHONSAFEPATH=1 python3 - "$FLOW_ROOT/bin" "$DISMISSAL_JOURNAL_DIR" <<'DISMISSAL_PY'
import sys

# The scrub sits ABOVE the other imports on purpose: glob and os happen to be
# preloaded by CPython today, which is an interpreter detail, not a promise.
sys.path[:] = [p for p in sys.path if p not in ("", ".")]

# The reader lives in the bin/ directory of the plugin, and takes its fence
# predicate from bin/_journal_atomic.py — the module every journal write goes
# through. This block used to carry its own copy. The copies drifted every
# review round: this one never gained the O_NONBLOCK that stops a FIFO in the
# journal directory hanging the read forever, and the comment here claimed the
# sibling reader "opens the same way" while the two had already diverged.
sys.path.insert(0, sys.argv[1])

import glob
import os

from _journal_manifest import ManifestError, one_line, read_artifacts

journal_dir = sys.argv[2]

if not os.path.isdir(journal_dir):
    # A directory that is not there is not a project with no dismissals. The
    # journal dir comes from the settings cascade and falls back to a RELATIVE
    # .decisions, so running from a subdirectory reproduces this.
    print("DISMISSED_COUNT=0")
    print("DROPPED_COUNT=0")
    print("STATE=unavailable")
    # Through one_line: journal.dir is read from .claude/settings.flow.json, a
    # tracked file, so a fork pull request chooses this string.
    print("REASON=the journal directory %s does not exist, so whether this project has "
          "recorded dismissals is unknown" % one_line(journal_dir))
    sys.exit(0)

dismissed = []
dropped = []
unreadable = []

for path in sorted(glob.glob(os.path.join(journal_dir, "*.md"))):
    try:
        for a in read_artifacts(path):
            if not isinstance(a, dict):
                # One silently dropped entry can decide whether a cluster
                # reaches the two-instance threshold.
                unreadable.append((path, "an artifacts entry is %s, not a mapping" % type(a).__name__))
                continue
            t = a.get("type")
            if t == "finding-dismissed":
                dismissed.append((path, a))
            elif t == "dropped-finding":
                dropped.append((path, a))
    except ManifestError as exc:
        # A manifest nobody could read is not a project with no dismissals.
        # Counting it as zero would hide the evidence this category exists to
        # find, which is the whole failure mode being fixed here. A journal with
        # no frontmatter at all is NOT this case — read_artifacts returns [] for
        # it, because the writer prepends a manifest on the first write and a
        # file without one has had nothing recorded in it.
        unreadable.append((path, exc))
    except Exception as exc:
        # Not ours, so only the class goes out: the text of a parse error quotes
        # the file, and the file may not be a manifest at all.
        unreadable.append((path, "the manifest could not be read (%s); its text is not "
                                 "echoed here" % type(exc).__name__))

for path, exc in unreadable:
    print("JOURNAL_UNREADABLE=%s — %s" % (one_line(path), one_line(exc)))
print("DISMISSED_COUNT=%d" % len(dismissed))
print("DROPPED_COUNT=%d" % len(dropped))
if unreadable:
    print("STATE=degraded")
    print("REASON=%d journal file(s) could not be read, so the counts above are a floor, not a total" % len(unreadable))
elif not dismissed and not dropped:
    print("STATE=empty")
else:
    print("STATE=ok")
for path, a in dismissed:
    print("DISMISSED=journal=%s pr=%s cycle=%s finding_id=%s category=%s reason=%s by=%s" % (
        one_line(path), one_line(a.get("pr")), one_line(a.get("cycle")),
        one_line(a.get("finding_id")), one_line(a.get("category")),
        one_line(a.get("reason")), one_line(a.get("by"))))
for path, a in dropped:
    print("DROPPED=journal=%s pr=%s cycle=%s finding_id=%s facet=%s reason=%s" % (
        one_line(path), one_line(a.get("pr")), one_line(a.get("cycle")),
        one_line(a.get("finding_id")), one_line(a.get("facet")),
        one_line(a.get("reason"))))
DISMISSAL_PY
); DISMISSAL_RC=$?
  # A reader that died mutely leaves no STATE line, which reads as a project
  # with nothing to report.
  if [ "$DISMISSAL_RC" -ne 0 ] || [ "$(printf '%s\n' "$DISMISSAL_OUT" | grep -c '^STATE=')" != "1" ]; then
    echo "DISMISSED_COUNT=0"
    echo "DROPPED_COUNT=0"
    echo "STATE=unavailable"
    echo "REASON=the dismissal reader did not complete (exit $DISMISSAL_RC), so whether this project has recorded dismissals is unknown"
  else
    printf '%s\n' "$DISMISSAL_OUT"
  fi
fi
fi
# DISMISSAL_ARTIFACTS_BLOCK_END

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

### Dismissal patterns

Read the `### Dismissal Artifacts` section from Phase 1. Cluster the `DISMISSED=` rows by
`category` and `reason`; a cluster is a finding the team keeps rejecting for the same stated reason.

`DROPPED=` rows are counted and shown but are **not** evidence for an exception. A dropped finding
did not survive the review machinery — both variants disagreed, or consolidation lost it. A
dismissed finding is one a human rejected on stated grounds. Only the second says anything about
what this team wants, and conflating them would turn a reviewer disagreement into a standing rule.

A cluster that recurs in one project becomes an `exception` proposal (below). A cluster that recurs
across projects is knowledge rather than a local preference, and becomes a skill proposal as today.

When Phase 1 reported `STATE=degraded`, say so alongside the counts: journals that could not be read
mean the counts are a floor, and a cluster that just missed the threshold may only have missed it
because a file was unreadable.

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

### Dismissal Patterns

Replaces filter 1 for the Dismissal patterns category. A cluster qualifies at
**two or more dismissals across two or more pull requests**.
Two dismissals on one pull request is one argument
had twice, not a pattern — the same reviewer and the same author in the same conversation. Requiring
two pull requests is what makes it a property of the project rather than of one exchange.

Filter 2 is already satisfied: every `finding-dismissed` artifact carries its `evidence` field,
which `references/decision-journal-schema.md` requires per reason.

### Fatigue Circuit Breaker

When a session yields more proposals than you can evidence well, propose the patterns
with the strongest transcript evidence and say in the output which patterns were seen
but not written up, so the next run can pick them up.

## Phase 4: Generate Proposals

For each qualifying pattern, create a skill proposal:

```bash
mkdir -p "$PROPOSAL_DIR"
```

Write each proposal to `$PROPOSAL_DIR/YYYY-MM-DD-{topic}.md` using the skill-proposal template. Enforcement proposals (Phase 3) keep the same template and required sections, add the `## Enforcement point` section, and use the `-enforcement` topic suffix (e.g. `YYYY-MM-DD-verify-output-enforcement.md`) so reviewers can tell them from new-skill proposals at a glance.

Set `type:` in the frontmatter — `skill`, `enforcement` or `exception`. It is what
`bin/promote-proposal.sh` branches on, and the filename suffix alone is a convention the promoter
cannot read.

**Exception proposals** (from the Dismissal patterns category) use the `-exception` suffix and carry
only `## Pattern Detected`, `## Evidence` and `## Exception row`. The other sections are skill-shaped
and say nothing about a rule. The body of `## Exception row` is one table row for
`.flow/review-exceptions.md`:

```
| {the rule, as a reviewer needs to read it} | {path glob it is scoped to} | {why the team rejected the finding} | {the pull requests it was dismissed on} |
```

The glob comes from where the dismissals actually happened — the `location` field of the clustered
artifacts, narrowed to the directory they share. A rule scoped wider than the evidence supports is a
rule that will suppress findings nobody dismissed. Promotion appends the row; it never writes a
skill, and `/flow:learn` never writes `.flow/review-exceptions.md` itself.

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
| 1 | {skill name} | skill \| enforcement \| exception | {proposal file path} |

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
