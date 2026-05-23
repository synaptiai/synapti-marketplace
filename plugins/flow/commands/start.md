---
description: "Start work on a GitHub issue. Assigns issue, creates branch, decomposes tasks from acceptance criteria, and guides implementation with autonomous execution."
argument-hint: <issue-number-or-url> [free-form context]
allowed-tools: Bash, Read, Write, Edit, Agent, Skill, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, TaskGet, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations (reads, API calls, TaskCreate),
invoke ALL relevant tools simultaneously in a single message rather than sequentially.

VARIABLE PERSISTENCE NOTE:
Bash variables do NOT persist across separate tool calls. Each Bash invocation
is independent. Store values mentally and substitute in subsequent commands.
-->

# Start Work on Issue #$ARGUMENTS

Skill-driven workflow from issue assignment through implementation. Follows the Explore > Plan > Code > Verify loop with Task-driven progress tracking.

## Required Skills

This command operates with these domain skills loaded:
- `llm-operator-principles` — foundational operator stance: convergence = zero findings, in-PR fixes by default, no calendar-time estimates, narrow escalation triggers. MUST be consulted before any other phase
- `branch-and-task-management` — branch creation, task decomposition
- `change-classification` — change context awareness
- `capability-discovery` — detect available quality tools
- `debugging-patterns` — activates on-demand for ALL issues when any verification step fails (not gated on `bug` label)
- `preflight-checks` — pure bash pre-flight validation (Phase 0)
- `criterion-verification-map` — per-criterion evidence collection (Phase 2 + Phase 4)
- `holdout-validation` — cross-reference self-review claims against file state (Phase 4)
- `issue-crafting` — invoked when the issue body is missing acceptance criteria or needs reframing
- `specification-capture` — capture non-goals, failure modes, and interface contracts to the decision journal (Phase 1, before Spec Validation Gate)

## References

- [`references/escalation-format.md`](../references/escalation-format.md) — canonical six-field structure used by every Proactive-Autonomy escalation in this command (Spec Validation Gate, NEEDS-HUMAN-REVIEW verdict, visual verification BLOCKED, runtime verification skip request)
- [`references/evidence-bundle-format.md`](../references/evidence-bundle-format.md) — canonical bundle shape Phase 4 step 5 produces and `Agent(verdict-judge)` consumes

## Phase 0: PRE-FLIGHT

Pure bash validation — fails fast before any agent reasoning.

```!
# Take the first whitespace-separated token; accept only if it is all digits.
# A non-numeric token (e.g., "foo42" or "evil;rm") is rejected with empty
# ISSUE_NUM so it never reaches the prompt context or any downstream shell
# (notably `git checkout -b "feature/issue-${ISSUE_NUM}-..."`). Users can still
# invoke as `/flow:start 42 (the search bar bug)` — the trailing prose is
# stripped by the first-token extraction.
#
# Output: `### Pre-Flight` heading + PREFLIGHT_FAIL=/PREFLIGHT_WARN= lines
# per check + final PREFLIGHT_STATE=PASSED|BLOCKED sentinel. See
# `references/command-output-format.md`.
ARG1="${ARGUMENTS%% *}"
case "$ARG1" in
  ''|*[!0-9]*) ISSUE_NUM="" ;;
  *) ISSUE_NUM="$ARG1" ;;
esac

ERRORS=0
WARNINGS=0
FAIL_REASONS=""
WARN_REASONS=""
fail() { FAIL_REASONS="${FAIL_REASONS}PREFLIGHT_FAIL=$1"$'\n'; ERRORS=$((ERRORS+1)); }
warn() { WARN_REASONS="${WARN_REASONS}PREFLIGHT_WARN=$1"$'\n'; WARNINGS=$((WARNINGS+1)); }

# 0. Issue number required (all-digit; non-digit input is rejected above)
[ -z "$ISSUE_NUM" ] && fail "Issue number required (all-digit)"

# 1. Clean git state
[ -n "$(git status --porcelain)" ] && fail "Uncommitted changes"

# 2. Not detached HEAD
git symbolic-ref HEAD >/dev/null 2>&1 || fail "Detached HEAD"

# 3. gh CLI authenticated
gh auth status >/dev/null 2>&1 || fail "gh CLI not authenticated"

# 4. Issue exists and is open
if [ -n "$ISSUE_NUM" ]; then
  ISSUE_STATE=$(gh issue view "$ISSUE_NUM" --json state --jq '.state' 2>/dev/null)
  [ "$ISSUE_STATE" != "OPEN" ] && fail "Issue #$ISSUE_NUM not found or not open (state: ${ISSUE_STATE:-not found})"
fi

# 5. Remote accessible
git ls-remote --exit-code origin >/dev/null 2>&1 || fail "Cannot reach remote 'origin'"

# 6. Already on feature branch (warning only)
# Short-circuits silently if not on a matching branch — the chain is a single
# statement, so failure of any link (no ISSUE_NUM, no match, etc.) just skips
# the warn without aborting the block.
[ -n "$ISSUE_NUM" ] && git branch --show-current | grep -q "issue-$ISSUE_NUM" && warn "Already on branch for issue #$ISSUE_NUM"

echo "### Pre-Flight"
echo "ISSUE_NUM=$ISSUE_NUM"
echo "PREFLIGHT_ERRORS=$ERRORS"
echo "PREFLIGHT_WARNINGS=$WARNINGS"
if [ $ERRORS -gt 0 ]; then
  echo "PREFLIGHT_STATE=BLOCKED"
else
  echo "PREFLIGHT_STATE=PASSED"
fi
# Emit collected reasons (one per line, may be empty)
printf '%s' "$FAIL_REASONS"
printf '%s' "$WARN_REASONS"

true
```

If `PREFLIGHT_STATE=BLOCKED`, stop. Do not proceed to EXPLORE. The `PREFLIGHT_FAIL=` lines under the section enumerate the reasons.

## Phase 0.5: FLOW V3 ONBOARDING

Detects whether this is the first `/flow:start` in a project that has neither been configured nor produced any v3 runtime state. Fires the consent prompt once; subsequent invocations see the persisted answer and skip.

```!
# Onboarding detection. Three branches, evaluated in order:
#
# 1. `.flow/` directory exists — user already has v3 runtime state, skip
#    regardless of settings file state.
# 2. No settings file AND no `.flow/` — fresh install, prompt.
# 3. Settings file exists but lacks `flow.goals` block — partial-file
#    bypass (the user has never answered the v3 onboarding question; an
#    unrelated v2 setting like `agentTeams` doesn't count as opting in
#    either way). Prompt.
#
# Otherwise (settings file with `flow.goals` block present, regardless of
# the block's contents) → skip; the user has answered.
NEEDS_ONBOARDING=0

if [ -d .flow ]; then
  NEEDS_ONBOARDING=0
elif [ ! -f .claude/settings.flow.json ]; then
  NEEDS_ONBOARDING=1
else
  if command -v jq >/dev/null 2>&1; then
    # `jq -e` exits non-zero on null/false/missing, which redirects
    # HAS_GOALS to empty. Parse errors also produce empty output.
    HAS_GOALS=$(jq -e '.flow.goals // empty' .claude/settings.flow.json 2>/dev/null)
    [ -z "$HAS_GOALS" ] && NEEDS_ONBOARDING=1
  fi
  # If jq is unavailable we conservatively skip — a v2 user with a
  # carefully configured settings file should not be re-prompted on every
  # /flow:start just because we cannot parse the file. Onboarding is
  # still reachable via /flow:goal create or manual settings edit.
fi

if [ "$NEEDS_ONBOARDING" = "1" ]; then
  echo "FLOW_V3_ONBOARDING=needed"
else
  echo "FLOW_V3_ONBOARDING=skip"
fi

true
```

If `FLOW_V3_ONBOARDING=needed`, use `AskUserQuestion` exactly once with this prompt:

> **Enable Flow v3 runtime layer for this project?**
>
> Flow v3 adds durable completion contracts (FlowGoal), inspectable workflows, and resumable execution records under `.flow/`. Acceptance criteria with `verification_command` auto-validate via `/flow:goal evaluate`. See `references/flow-goals-quickstart.md` for a walkthrough.
>
> Options:
> 1. **Enable v3 (recommended for new projects)** — auto-create goals on `/flow:start`, run verification commands during evaluate
> 2. **Skip — keep v2 behavior** — `/flow:start` proceeds without goals; v3 surfaces remain reachable via explicit `/flow:goal create`
> 3. **Tell me more** — open the quickstart, decide on the next invocation

Persist the answer to `.claude/settings.flow.json`. When the file already exists with a partial shape (e.g., the user committed `{"agentTeams": false}` from `/flow:setup` before v3 onboarding), the new keys are MERGED via `jq` so unrelated v2 settings are preserved. When the file is absent, a fresh JSON document is written. When `jq` is unavailable AND the file already exists, the helper refuses to write rather than clobber v2 keys with a heredoc fallback.

The `set_flow_goals` helper below is shared by all three answer arms. After defining it, dispatch based on the user's `AskUserQuestion` response — the dispatch is prose-driven, not a shell `case` (the `AskUserQuestion` answer reaches Claude, not the shell, so Claude runs the appropriate arm directly).

**Helper definition** (run once):

```bash
SETTINGS=.claude/settings.flow.json

# Symlink defense: refuse to write through symlinks at .claude/ or settings file.
# Matches the O_NOFOLLOW pattern documented in bin/journal-record.sh and the
# CHANGELOG's "symlink defenses everywhere" rule. A hostile fork PR could plant
# .claude as a symlink to ~/.ssh or settings.flow.json as a symlink to ~/.bashrc;
# refuse rather than corrupt the target.
if [ -e .claude ] && [ -L .claude ]; then
  echo "FLOW_ONBOARDING_ERROR=.claude is a symlink — refusing to write through it" >&2
  exit 1
fi
if [ -e "$SETTINGS" ] && [ -L "$SETTINGS" ]; then
  echo "FLOW_ONBOARDING_ERROR=$SETTINGS is a symlink — refusing to write through it" >&2
  exit 1
fi
mkdir -p .claude

set_flow_goals() {
  # Args: $1=requireGoalForStart (true|false) $2=executeVerificationCommands (true|false)
  #       $3=workflowsEnabled (true|false|skip — "skip" omits the workflows key)
  # Cycle-14 F2 (code-reviewer verifier): merges all three keys atomically
  # via a single jq invocation so there's no partial-write state where
  # flow.goals lands but flow.workflows.enabled is missing. The previous
  # split into two helpers (set_flow_goals + set_flow_workflows_enabled)
  # introduced the partial-success bug — eliminating the second helper
  # eliminates the bug.
  local req="$1" exe="$2" wfl="${3:-skip}"

  # Re-check symlink between definition and call — defense against TOCTOU race.
  if [ -e "$SETTINGS" ] && [ -L "$SETTINGS" ]; then
    echo "FLOW_ONBOARDING_ERROR=$SETTINGS became a symlink — refusing to write" >&2
    return 1
  fi

  # Compose the jq merge expression. Conditional workflows clause: "skip"
  # leaves the existing value (or absence) untouched; "true"/"false" sets it.
  local jq_expr='.flow.goals.requireGoalForStart = $req | .flow.goals.executeVerificationCommands = $exe'
  if [ "$wfl" = "true" ] || [ "$wfl" = "false" ]; then
    jq_expr="$jq_expr | .flow.workflows.enabled = \$wfl"
  fi

  if [ -f "$SETTINGS" ]; then
    # File exists — must merge, never overwrite. Requires jq.
    if ! command -v jq >/dev/null 2>&1; then
      echo "FLOW_ONBOARDING_ERROR=$SETTINGS exists but jq is unavailable — refusing to overwrite v2 keys; install jq and re-run /flow:start" >&2
      return 1
    fi

    # Cycle-14 SEC-6: use mktemp instead of PID-scoped tmpfile. PID
    # predictability (~15 bits of entropy) allows symlink-planting attacks
    # on multi-user systems; mktemp's random suffix defeats it.
    local tmp
    tmp=$(mktemp -t flow-settings.XXXXXX 2>/dev/null) || {
      echo "FLOW_ONBOARDING_ERROR=mktemp failed for settings merge" >&2
      return 1
    }
    local lockfile="${SETTINGS}.lock"
    # Cycle-14 F5 (error-handler skeptic): trap to clean tmpfile on signal
    # so .claude/ doesn't accumulate stale `settings.flow.json.tmp.NNNN`.
    trap 'rm -f "$tmp"' EXIT INT TERM
    (
      # flock guards the read-modify-write window; (subshell) scopes the fd.
      flock -x 9 || { echo "FLOW_ONBOARDING_ERROR=failed to acquire $lockfile" >&2; exit 1; }
      if [ "$wfl" = "true" ] || [ "$wfl" = "false" ]; then
        if ! jq --argjson req "$req" --argjson exe "$exe" --argjson wfl "$wfl" \
             "$jq_expr" \
             "$SETTINGS" > "$tmp"; then
          rm -f "$tmp"
          echo "FLOW_ONBOARDING_ERROR=jq merge failed on $SETTINGS" >&2
          exit 1
        fi
      else
        if ! jq --argjson req "$req" --argjson exe "$exe" \
             "$jq_expr" \
             "$SETTINGS" > "$tmp"; then
          rm -f "$tmp"
          echo "FLOW_ONBOARDING_ERROR=jq merge failed on $SETTINGS" >&2
          exit 1
        fi
      fi
      # Cycle-14 SEC-V5 (security verifier): validate the merged file is
      # non-empty AND parseable BEFORE replacing the original — a jq that
      # exits 0 with empty/truncated output would otherwise destroy settings.
      if [ ! -s "$tmp" ] || ! jq empty "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        echo "FLOW_ONBOARDING_ERROR=jq produced empty or invalid JSON; $SETTINGS unchanged" >&2
        exit 1
      fi
      if ! mv "$tmp" "$SETTINGS"; then
        rm -f "$tmp"
        echo "FLOW_ONBOARDING_ERROR=mv failed; $SETTINGS unchanged" >&2
        exit 1
      fi
    ) 9>"$lockfile"
    local rc=$?
    trap - EXIT INT TERM
    rm -f "$tmp"
    [ "$rc" -ne 0 ] && return 1
  else
    # Fresh file — write atomically via tmpfile+mv (cycle-14 F4 error-handler
    # verifier: the previous non-atomic `printf > $SETTINGS` left the file
    # partial on signal mid-write).
    local tmp
    tmp=$(mktemp -t flow-settings.XXXXXX 2>/dev/null) || {
      echo "FLOW_ONBOARDING_ERROR=mktemp failed for fresh-file write" >&2
      return 1
    }
    trap 'rm -f "$tmp"' EXIT INT TERM
    # Compose the JSON document with conditional workflows.enabled.
    if [ "$wfl" = "true" ] || [ "$wfl" = "false" ]; then
      printf '%s\n' "{" \
        "  \"flow\": {" \
        "    \"goals\": {" \
        "      \"requireGoalForStart\": ${req}," \
        "      \"executeVerificationCommands\": ${exe}" \
        "    }," \
        "    \"workflows\": {" \
        "      \"enabled\": ${wfl}" \
        "    }" \
        "  }" \
        "}" > "$tmp"
    else
      printf '%s\n' "{" \
        "  \"flow\": {" \
        "    \"goals\": {" \
        "      \"requireGoalForStart\": ${req}," \
        "      \"executeVerificationCommands\": ${exe}" \
        "    }" \
        "  }" \
        "}" > "$tmp"
    fi
    if [ ! -s "$tmp" ] || ! jq empty "$tmp" >/dev/null 2>&1; then
      rm -f "$tmp"
      trap - EXIT INT TERM
      echo "FLOW_ONBOARDING_ERROR=fresh file write produced empty or invalid JSON" >&2
      return 1
    fi
    if ! mv "$tmp" "$SETTINGS"; then
      rm -f "$tmp"
      trap - EXIT INT TERM
      echo "FLOW_ONBOARDING_ERROR=mv failed for fresh-file write" >&2
      return 1
    fi
    trap - EXIT INT TERM
  fi
}

# Cycle-14 F2 (code-reviewer verifier): set_flow_workflows_enabled REMOVED.
# Previously cycle-13 added a second helper for the workflows.enabled key, but
# the two-helper sequence created a partial-success failure mode: if the
# second invocation failed, the settings file ended up with flow.goals but no
# flow.workflows, and the Phase 0.5 detector silently skipped the re-prompt
# (looks for .flow.goals only). The fix is structural: set_flow_goals now
# takes a 3rd arg (workflows: "true"|"false"|"skip") and writes all keys in
# a single jq merge. Enable arm passes "true"; Skip arm passes "skip" to
# preserve any pre-existing flow.workflows.enabled setting.
```

**Dispatch based on the user's answer** (Claude runs ONE of the following based on the `AskUserQuestion` response — NOT a shell `case`):

- **Answer = "Enable v3 (recommended for new projects)"**:
  ```bash
  set_flow_goals true true true \
    && echo "Flow v3 enabled (goals + workflows). Settings written to $SETTINGS." \
    && echo "Note: FlowTriggers (/flow:watch, /flow:trigger) remain separate opt-in." \
    && echo "  Enable later via: jq '.flow.triggers.enabled = true' $SETTINGS > /tmp/s && mv /tmp/s $SETTINGS"
  ```
  Cycle-14 F2: `set_flow_goals` now writes all three keys atomically in one jq merge — no more partial-success state where goals lands but workflows is missing. If the helper returns non-zero, halt Phase 0.5 and surface the `FLOW_ONBOARDING_ERROR` line.

- **Answer = "Skip — keep v2 behavior"**:
  ```bash
  set_flow_goals false false skip && echo "Flow v3 left disabled. Settings written to $SETTINGS (re-enable later by editing the file)."
  ```
  Third arg is `skip` so the helper leaves `flow.workflows` untouched (preserves any pre-existing user choice). Same error-halt semantics.

- **Answer = "Tell me more"**:
  ```bash
  echo "Open plugins/flow/references/flow-goals-quickstart.md, then re-run /flow:start when ready."
  ```
  Do NOT write the settings file. Halt Phase 0.5 without proceeding. The next `/flow:start` will re-prompt — by design.

Only the Enable and Skip arms write the settings file (with opposing flag values) so the prompt fires exactly once per project for users who actually answered. `Tell me more` is non-persistent so the user can re-enter the flow after reading the quickstart.

## Phase 1: EXPLORE

Gather all context before planning.

**Bug issue detection**: If issue labels include `bug`:
- Phase 3 becomes: reproduce → isolate root cause → write failing test → fix → verify

**Note**: `debugging-patterns` activates automatically for ALL issues when any verification step fails (build, test, server start, smoke test). No `bug` label required.

```!
# Digit-validate ISSUE_NUM (matches Phase 0 block).
ARG1="${ARGUMENTS%% *}"
case "$ARG1" in
  ''|*[!0-9]*) ISSUE_NUM="" ;;
  *) ISSUE_NUM="$ARG1" ;;
esac

echo "### Issue Reference"
if [ -z "$ISSUE_NUM" ]; then
  echo "STATE=blocked"
  echo "ERROR=issue number required (all-digit; Phase 0 PRE-FLIGHT carries the authoritative BLOCKED signal)"
else
  echo "STATE=ok"
  echo "ISSUE_NUM=$ISSUE_NUM"

  # Section: Issue Details
  echo ""
  echo "### Issue Details"
  gh issue view "$ISSUE_NUM" --json title,body,labels,assignees,milestone --jq '
    "TITLE=\"\(.title)\"\nLABELS=\([.labels[].name] | join(","))\nASSIGNEES=\([.assignees[].login] | map("@" + .) | join(","))\nMILESTONE=\(.milestone.title // "(none)")\nBODY_LENGTH=\(.body | length)"
  ' 2>/dev/null
  # Issue body is variable-length; emit it under a sub-heading so the agent
  # can locate and read it as prose rather than parse it as fields.
  echo ""
  echo "#### Issue Body"
  gh issue view "$ISSUE_NUM" --json body --jq '.body' 2>/dev/null

  # Section: Issue Comments
  echo ""
  echo "### Issue Comments"
  REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
  COMMENT_COUNT=$(gh api "repos/$REPO/issues/$ISSUE_NUM/comments" --jq 'length' 2>/dev/null || echo "0")
  echo "COMMENT_COUNT=$COMMENT_COUNT"
  if [ "$COMMENT_COUNT" = "0" ]; then
    echo "STATE=empty"
  else
    gh api "repos/$REPO/issues/$ISSUE_NUM/comments" --jq '.[] | "COMMENT=author=@\(.user.login) at=\(.created_at) length=\(.body | length)"' 2>/dev/null
  fi

  # Section: Repo Context
  echo ""
  echo "### Repo Context"
  DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
  echo "REPO=$REPO"
  echo "DEFAULT_BRANCH=$DEFAULT_BRANCH"
  echo "CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)"
  STATUS_LINES=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  echo "UNCOMMITTED_COUNT=$STATUS_LINES"
  [ "$STATUS_LINES" != "0" ] && git status --short 2>/dev/null | head -20 | sed 's/^/UNCOMMITTED_LINE=/'
fi

true
```

**Parallel Agent + Skill calls:**

- `Agent(Explore)`: "Read CLAUDE.md (.claude/CLAUDE.md or CLAUDE.md). Identify tech stack, testing commands, coding conventions, and any project-specific rules. Also search for code related to the issue keywords to understand affected modules."
- `Skill(capability-discovery)`: Discover available agents, quality commands, and tech stack.

**Spec-first validation** (after issue details are fetched):

Parse the issue body for acceptance criteria:
- Look for `## Acceptance Criteria` section with `- [ ]` items
- Look for numbered requirement lists
- Look for task lists in the body

If zero acceptance criteria found and `specFirst.requireAcceptanceCriteria` is `true` (default), use `AskUserQuestion`:

> No acceptance criteria found in issue #$ARGUMENTS. Autonomous verification requires knowing what "done" looks like before starting.
>
> Options:
> 1. Add acceptance criteria now (I'll help you write them)
> 2. Spec-free task (docs/config only) — proceed without AC
> 3. Cancel — I'll update the issue first

- Option 1: Use `Skill(issue-crafting)` to help write ACs, then update the issue via `gh issue edit`
- Option 2: Only available if issue labels include any of `specFirst.allowSpecFreeLabels` (default: `documentation`, `chore`). Log to decision journal: "Spec-free task: {justification}"
- Option 3: Stop workflow

**Specification capture** (before Spec Validation Gate):

Acceptance criteria alone do not describe the full specification. Before building the Spec Validation Gate, capture three additional specification elements (non-goals, failure modes, interface contracts) and persist them to the decision journal under a `## Specification` heading. The capture lifecycle is owned by the `specification-capture` skill — do NOT inline the prompts or the journal write. The skill handles journal-first detection, issue-body extraction, per-element user confirmation via `AskUserQuestion` (with the canonical six-field structure from `references/escalation-format.md`), and the journal write.

```
Skill(specification-capture):
  Inputs:
  - Issue context: {pre-fetched issue title, body, comments, labels}
  - Journal path: .decisions/issue-$ISSUE_NUM.md
  - Invocation reason: start
```

The skill returns the captured specification (non-goals, failure modes, interface contracts). It writes them to the journal and verifies the write before returning.

After the skill returns, verify per the skill's "Verification gates" section:

1. The journal `.decisions/issue-$ISSUE_NUM.md` contains a `## Specification` heading
2. All three element subsections (`### Non-goals`, `### Failure modes`, `### Interface contracts`) are present and non-empty (or `none — {reason}` for failure-mode categories that don't apply)
3. The returned payload matches the journal contents

If any check fails, halt and re-invoke the skill with the failure noted. Do NOT proceed to the Spec Validation Gate with a partial specification — the Stranger Test at end-of-PLAN will fail downstream.

**Manifest emit** — record the specification artifact in the journal manifest so downstream tooling and `/flow:status` can see it without parsing the freeform `## Specification` body:

```bash
"${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/journal-record.sh" \
  --issue "$ISSUE_NUM" \
  --type specification \
  --metadata by=specification-capture \
  --metadata elements=non-goals,failure-modes,interface-contracts
```

If the helper exits non-zero, halt — a missing manifest entry breaks downstream artifact discovery (`/flow:status`, the `verdict-judge` evidence-bundle assembly). The emit is required even when the skill returned an existing-spec verbatim from the journal-first path: the freeform section may already be present, but the manifest entry is the audit trail of *this* invocation.

Once the captured specification is in the journal, downstream phases reference it: `implementation-planner` agent receives it as the `Specification` field in its dispatch (Phase 2); the Phase 4 evidence-bundle producer pulls `Non-goals` into each criterion's `### Does NOT promise` subsection (per `references/evidence-bundle-format.md`).

**Spec Validation Gate** (blocking):

If acceptance criteria are found, build a **Spec Validation Table** and treat it as a gate, NOT a display. Every criterion MUST map to a concrete automated verification command before proceeding to Phase 2 (PLAN). This gate blocks progression when any criterion is vague, untestable, or marked `manual` without proper escalation.

```markdown
### Spec Validation Gate
| # | Acceptance Criterion | Verification Command | Gate Status |
|---|---------------------|----------------------|-------------|
| 1 | {criterion text} | `{exact command, e.g. npm test -- --grep "auth"}` | PASS |
| 2 | {vague criterion} | (none — cannot automate) | BLOCK |
```

**Gate rules:**

- **PASS** — criterion has a concrete, runnable verification command (test command, curl, script invocation, build check, lint rule). The command must be specific enough that a zero-context agent could run it and collect evidence without further interpretation.
- **BLOCK** — criterion is vague ("handle errors gracefully", "improve performance", "be user-friendly"), has no automatable check, or the verification method is unknown. Progression to PLAN is blocked.
- **MANUAL (escalation only)** — `manual` verification is ONLY permitted when flagged as a Proactive-Autonomy escalation with the full six-field structure. Default behavior treats `manual` as BLOCK.

**When any criterion BLOCKS**, the agent MUST NOT proceed to PLAN. Instead, issue a Proactive-Autonomy escalation via `AskUserQuestion` with all six fields:

> **Situation** — Criterion #{n} "{vague text}" has no automatable verification. Shipping with this criterion means the plan cannot define what "done" looks like.
>
> **Tried** — I attempted to classify the criterion via `criterion-verification-map`. No verification type matched. Searched the codebase for existing tests covering similar behavior: {found|not found}.
>
> **Options**:
> 1. Rewrite criterion as "{concrete measurable rewording}" with verification command `{specific command}`
> 2. Rewrite criterion as "{alternative measurable rewording}" with verification command `{alternative command}`
> 3. Mark as `manual` — I (the user) will verify this step myself at VERIFY phase. The plan will record manual evidence collection.
>
> **Recommendation** — Option {1|2} — measurable criteria produce better verdicts and prevent vague implementations.
>
> **Blocking?** — Yes. Blocks planning; Phase 2 cannot proceed until this resolves.
>
> **Risk** — Choosing Option 3 (`manual`) means no automated verdict for this criterion and requires a human-in-the-loop at VERIFY phase.

Only after every criterion shows PASS or user-approved MANUAL can the workflow proceed to Phase 2.

**Assign the issue:**

```bash
gh issue edit "$ISSUE_NUM" --add-assignee @me
```

**FlowGoal auto-creation (gated by `flow.goals.requireGoalForStart`):**

```!
CASCADE="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh"
# Surface cascade-resolve unavailability instead of silently degrading the gate.
if [ ! -x "$CASCADE" ]; then
  echo "FLOW_GOAL_STATE=blocked"
  echo "FLOW_GOAL_ERROR=cascade-resolve.sh missing or non-executable at $CASCADE"
  true; exit 0
fi
REQUIRE_GOAL=$("$CASCADE" --default "false" '.flow.goals.requireGoalForStart' 2>/dev/null)

ARG1="${ARGUMENTS%% *}"
case "$ARG1" in
  ''|*[!0-9]*) ISSUE_NUM="" ;;
  *) ISSUE_NUM="$ARG1" ;;
esac

if [ "$REQUIRE_GOAL" = "true" ] && [ -n "$ISSUE_NUM" ]; then
  GOAL_ID="issue-$ISSUE_NUM"
  GOAL_PATH=".flow/goals/${GOAL_ID}.goal.yaml"
  if [ -f "$GOAL_PATH" ]; then
    # Inspect lifecycle.status — terminal goals (achieved/failed/cancelled)
    # are immutable per goal-lifecycle/SKILL.md ("terminal → any" is
    # disallowed). Resume only when status is non-terminal.
    if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1; then
      STATUS=$(python3 - "$GOAL_PATH" <<'PY' 2>/dev/null
import sys, yaml
with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}
print(data.get("lifecycle", {}).get("status", "unknown"))
PY
)
    else
      STATUS="unknown"
    fi
    case "$STATUS" in
      achieved|failed|cancelled)
        echo "FLOW_GOAL_STATE=terminal"
        echo "GOAL_PATH=$GOAL_PATH"
        echo "GOAL_STATUS=$STATUS"
        ;;
      *)
        echo "FLOW_GOAL_STATE=exists"
        echo "GOAL_PATH=$GOAL_PATH"
        echo "GOAL_STATUS=$STATUS"
        ;;
    esac
  else
    echo "FLOW_GOAL_STATE=create"
    echo "GOAL_ID=$GOAL_ID"
    echo "GOAL_PATH=$GOAL_PATH"
  fi
else
  echo "FLOW_GOAL_STATE=skip"
fi

true
```

Dispatch based on `FLOW_GOAL_STATE`:

- **`create`** — proceed to invoke the skills (steps below). The visibility echo is gated on the post-write verify.
- **`exists`** — non-terminal goal already on disk; print `FlowGoal already exists: <GOAL_PATH> (status: $GOAL_STATUS) — resuming. Use /flow:goal inspect <GOAL_ID> to review.`
- **`terminal`** — goal is `achieved|failed|cancelled` and immutable. Refuse to resume; surface a six-field escalation per [`references/escalation-format.md`](../references/escalation-format.md): _Situation_: terminal goal at `<GOAL_PATH>`. _Tried_: detected `lifecycle.status=<GOAL_STATUS>`. _Options_: (1) Use `/flow:goal clear <GOAL_ID>` then re-run `/flow:start`, (2) Pick a new goal id, (3) Abort. _Recommendation_: Option 1 if the original goal is stale. _Blocking_: yes. _Risk_: mutating a terminal goal corrupts the audit trail.
- **`blocked`** — cascade-resolve unavailable; surface `FLOW_GOAL_ERROR` and halt Phase 1.
- **`skip`** — proceed without goal creation (v2 behavior preserved).

For `FLOW_GOAL_STATE=create`:

1. Invoke `Skill(goal-contract-capture)` with inputs:
   - `goal id` = the `GOAL_ID` from the block above
   - `scope` = `repo` (current repo), `branch` (will be set after Phase 2 branch creation), `issue` = `$ISSUE_NUM`
   - `source` = pre-fetched issue body + Spec Validation Gate output
   - `invocation reason` = `start`
2. After the skill writes the YAML, invoke `Skill(goal-lifecycle)` to transition `draft → active`.
3. **Post-write verify** — before emitting the visibility echo, confirm the contract was persisted and is in `active`:
   ```bash
   if [ ! -f "$GOAL_PATH" ]; then
     echo "FLOW_GOAL_ERROR=goal-contract-capture returned success but $GOAL_PATH does not exist" >&2
     # halt — do not proceed to Phase 2 with inconsistent state
     exit 1
   fi
   if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1; then
     STATUS=$(python3 -c "import sys, yaml; print((yaml.safe_load(open('$GOAL_PATH')) or {}).get('lifecycle', {}).get('status', 'unknown'))" 2>/dev/null)
     if [ "$STATUS" != "active" ]; then
       echo "FLOW_GOAL_ERROR=goal-lifecycle did not transition to active (current: $STATUS)" >&2
       exit 1
     fi
   fi
   ```
4. Only after verify passes, emit:
   ```
   FlowGoal created: <GOAL_ID> at <GOAL_PATH> (status: active)
   ```

### FlowRun (v3 runtime)

`/flow:start` is a long-running workflow, so it gets a durable FlowRun linked to the FlowGoal. Runs are gated by `flow.runtime.enabled` (default `true`); v2 projects that opted out see `FLOW_RUN_STATE=skip` and the wiring is a no-op.

```!
# FLOW_RUN_BLOCK_BEGIN
CASCADE="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh"
if [ ! -x "$CASCADE" ]; then
  echo "FLOW_RUN_STATE=blocked"
  echo "FLOW_RUN_ERROR=cascade-resolve.sh missing or non-executable at $CASCADE"
  true; exit 0
fi
RUNTIME_ENABLED=$("$CASCADE" --default "true" '.flow.runtime.enabled' 2>/dev/null)
ARG1="${ARGUMENTS%% *}"
case "$ARG1" in
  ''|*[!0-9]*) ISSUE_NUM="" ;;
  *) ISSUE_NUM="$ARG1" ;;
esac
if [ "$RUNTIME_ENABLED" != "true" ]; then
  echo "FLOW_RUN_STATE=skip"
  echo "FLOW_RUN_REASON=flow.runtime.enabled is not true (v2 mode)"
else
  SLUG="${ISSUE_NUM:-nonum}"
  RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-issue-${SLUG}"
  echo "FLOW_RUN_STATE=create"
  echo "RUN_ID=$RUN_ID"
  echo "WORKFLOW=start-issue"
  echo "INITIAL_PHASE=preflight"
  if [ -n "$ISSUE_NUM" ]; then echo "GOAL_LINK=issue-$ISSUE_NUM"; else echo "GOAL_LINK=null"; fi
fi
# FLOW_RUN_BLOCK_END
true
```

When `FLOW_RUN_STATE=create`, invoke `Skill(run-state-management)` to create `.flow/runs/$RUN_ID/run.yaml` (workflow=`start-issue`, goal=`$GOAL_LINK` — the FlowGoal created above, or `null` when goal creation was skipped), initial phase `preflight`. Because `/flow:start` is issue-scoped, also emit the `workflow-run` artifact to `.decisions/issue-$ISSUE_NUM.md`:

```bash
"${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/journal-record.sh" \
  --issue "$ISSUE_NUM" --type workflow-run \
  --metadata workflow=start-issue --metadata run_id="$RUN_ID" --metadata status=active
```

Phase order: `preflight → explore → plan → code → verify`. At each subsequent phase boundary (PLAN, CODE, VERIFY), invoke `Skill(run-state-management)` to write a FlowActivity record and advance `state.current_phase`. After the Phase 4 verdict settles, transition the FlowRun: `state.status: completed` when the verdict is PASS (and update the `workflow-run` artifact to `status=completed`); `state.status: blocked` (with `blocked_reason`) when the verdict is FAIL or the session ends mid-workflow, so `/flow:resume` can pick it up.

## Phase 2: PLAN

Create branch and decompose tasks.

**Branch creation** (Tier 1 — autonomous):

```bash
git fetch origin $DEFAULT_BRANCH
git checkout -b "feature/issue-${ISSUE_NUM}-{kebab-desc}" "origin/$DEFAULT_BRANCH"
```

**Initialize decision journal:**

```bash
mkdir -p .decisions
```

Write journal header to `.decisions/issue-$ISSUE_NUM.md`.

**Task decomposition** — dispatch implementation-planner agent:

Each implementation task is an **atomic unit** that bundles three responsibilities, not three separate tasks:

1. **Implementation** — the code change
2. **Test** — the test(s) that verify the behavior the code change introduces
3. **Verification-evidence collection** — the exact command that will be run in Phase 4 to prove this task's acceptance criterion is met, and the captured output that becomes evidence

A task is not "done" until all three are complete. Splitting them into three sibling tasks (one for code, one for test, one for verify) is explicitly prohibited — it causes implementation to ship before tests catch up and verification to happen after the author has lost context.

```
Agent(implementation-planner):
  "Parse acceptance criteria from issue #$ISSUE_NUM and create atomic tasks.
   Issue context: {pre-fetched issue title, body, comments}
   Specification (from EXPLORE): {non-goals, failure modes, interface contracts}
   Spec Validation Gate results: {criterion -> verification command mapping}

   For each acceptance criterion, use TaskCreate with a single atomic task:
   - subject: imperative description of the behavior
   - description: |
       Criterion: {full criterion text}
       Non-goals touched: {which non-goals this task must respect}
       Failure modes covered: {which failure modes this task implements handling for}
       Interface contract: {schema/signature this task must honor}
       Implementation outline: {files + approach}
       Test plan: {test file + cases + assertions}
       Verification command: {exact command from Spec Validation Gate}
       Expected evidence: {what success output looks like}

   Set dependencies with TaskUpdate(addBlockedBy).
   Identify parallel execution opportunities.
   Return: task list, dependency graph, suggested order."
```

Each atomic task flows through implementation → test → evidence collection within the same task lifecycle in Phase 3 (CODE). Phase 4 (VERIFY) still runs the full evidence bundle assembly and independent verdict judge, but per-task evidence is captured at the moment the task completes, not in a bulk pass after all tasks have completed and context is fragmented.

**Stranger Test check** (mandatory PLAN gate):

Before proceeding to Phase 3 (CODE), the agent MUST run the Stranger Test against the assembled plan:

> **Could a zero-context agent — one that has never seen this repo, this issue, or this plan conversation — execute every task in this plan and produce acceptable output?**

Check each task for these failure modes:

- **Implicit file references** — "update the auth module" without the path
- **Undefined terms** — uses project jargon without definition
- **Missing preconditions** — assumes setup, env vars, or state that is not written down
- **Vague success criteria** — "make it work", "fix the issue", "handle it correctly"
- **Unspecified verification command** — a zero-context agent would not know what to run to prove the task is done
- **Missing interface contracts** — schema/signature/shape is not written in the task
- **Missing failure-mode coverage** — the task does not reference which failure modes it must handle

If ANY task fails the Stranger Test, the plan is incomplete. The agent must either rewrite the task to close the gap, or issue a Proactive-Autonomy escalation asking the user to fill in the missing context. Only after every task passes the Stranger Test can the workflow proceed to Phase 3.

Record the Stranger Test result to `.decisions/issue-$ISSUE_NUM.md` under a `## Stranger Test` heading with either "PASS — {N} tasks reviewed" or "BLOCK — {task id}: {failure mode}".

**Manifest emit** — append the stranger-test artifact (alongside the freeform `## Stranger Test` section) so the manifest captures the gate's outcome:

```bash
"${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/journal-record.sh" \
  --issue "$ISSUE_NUM" \
  --type stranger-test \
  --metadata result={PASS|BLOCK} \
  --metadata task_count=$N
```

Add `--metadata failed_task=$TASK_ID` when result is BLOCK (the task ID that failed the gate, so downstream readers can locate the offending task without re-parsing the body).

Display task plan. Proceed unless user objects.

## Phase 3: CODE

**TDD enforcement**: Check `settings.json` → `testing.tddMode`:
- `enforce` (default) — write a failing test FIRST. Implementation without a preceding RED test is blocked.
- `suggest` — recommend TDD but allow override. Only active when `testing.tddModeOptOut` is `true`.
- `off` — no TDD guidance; tests still run in verification.

Execute tasks following the per-task verification gate loop:

```
For each task (in dependency order):
  1. TaskUpdate(taskId, status: "in_progress")
  2. Read relevant files (follow existing patterns)
  3. TDD enforcement (when tddMode=enforce):
     a. RED: Write the failing test FIRST — the test MUST fail before any implementation
     b. Verify it fails for the right reason (not syntax error, not wrong import)
  4. GREEN: Implement the change — simplest code to make the test pass
     - Follow existing patterns (co-located files, same framework)
     - At minimum, one test per acceptance criterion or behavior
     - Test edge cases, not just the happy path
     - For bug fixes: write a test that would have caught the original bug
  5. Run tests (existing + new):
     IF tests FAIL → enter debug-fix-retest loop:
       - Read failure output, identify root cause
       - Fix the failing code (not the test, unless the test is wrong)
       - Re-run tests
       - Repeat until all tests pass (bounded by closedLoop.maxDebugIterations)
       - Do NOT proceed to step 6. Do NOT call TaskUpdate(completed).
       - Approaching `closedLoop.maxDebugIterations` is a signal to re-check whether you're fixing the wrong layer or whether two test failures are in tension — not a budget to stop at. Only halt for genuine non-convergence (same failure persists 3+ iterations with no progress AND the ceiling is reached); in that case file a six-field Proactive-Autonomy escalation per `skills/llm-operator-principles/SKILL.md` § Genuine non-convergence.
     IF tests PASS → continue to step 6
  6. REFACTOR: Clean up implementation and tests. Re-run tests — they must still pass.
  7. Capture verification evidence:
     - Run the verification command from the task description
     - Record the output as evidence for this task's acceptance criterion
     - IF verification command fails → enter debug-fix-retest loop (same rules as step 5)
  8. Per-task change classification:
     - Classify all files modified during this task using change-classification signals
     - Flag any out-of-context files NOW — do not accumulate until commit time
     - If out-of-context files found, use AskUserQuestion to resolve before proceeding
  9. Incremental commit (Tier 1: autonomous)
  10. ONLY after ALL of the following are true may TaskUpdate(completed) be called:
      - All tests pass (existing + new)
      - Verification evidence captured for this task's acceptance criterion
      - No unresolved out-of-context files from this task
      - TDD cycle completed (RED → GREEN → REFACTOR) when tddMode=enforce
      TaskUpdate(taskId, status: "completed")
```

**Critical gate**: Step 5 is a HARD GATE. If tests fail, the task CANNOT be marked completed. The loop stays on the current task until tests pass or the user is escalated to. Skipping ahead to the next task with failing tests is explicitly prohibited.

**Parallel task detection**: If tasks have no overlapping files and agent teams are enabled, suggest parallel execution via agent team.

**Quality loop** (bounded by `qualityCheckMaxIterations`):

```bash
# Run quality commands discovered in Phase 1 (parallel)
$LINT_CMD
$TEST_CMD
$TYPECHECK_CMD
```

If failures: fix and re-run. The iteration ceiling is a safety net against true infinite loops, not a budget — approaching it is a signal to re-check understanding, not to escalate. Only halt for genuine non-convergence per `skills/llm-operator-principles/SKILL.md` § Genuine non-convergence.

**Build-and-run verification** (before proceeding to Phase 4):

1. **Build the project** → if build fails, apply debugging-patterns: read errors, fix, rebuild (up to `closedLoop.maxBuildIterations`)
2. **Start dev server** (if applicable) → if won't start, read logs, fix, retry (up to `closedLoop.maxServerRetries`)
3. **Smoke test** → hit key endpoints or run the CLI with sample input
4. If any step fails → enter debug-fix-retest loop. Do NOT proceed to Phase 4 until code builds and runs.

Skipping the build-and-run step is ONLY permitted if the change falls into one of the three enumerated whitelist categories defined in the `runtime-verification` skill: `markdown-only`, `config-only`, or `dependency-bump-only`. Any other skip requires a Proactive-Autonomy escalation — see the skill for the required six-field structure. If in doubt, run it.

## Phase 4: VERIFY

Prove everything works with fix-forward:

1. **Run full quality suite** (parallel Bash calls for lint, test, typecheck)
2. **Runtime verification** (MANDATORY — not conditional on skill availability):

   Invoke `Skill(runtime-verification)` for build, dev-server, smoke, E2E, and LSP-diagnostics checks. The skill owns the skip whitelist (the three enumerated categories `markdown-only`, `config-only`, `dependency-bump-only` with their required evidence) and the escalation protocol for out-of-whitelist skips per [`references/escalation-format.md`](../references/escalation-format.md). Any skip outside the whitelist requires an approved Proactive-Autonomy escalation surfaced via `AskUserQuestion` — blanket or subjective justifications are not valid. If in doubt, run it.

   When the diff is UI-relevant (UI file extensions OR acceptance criteria with UI keywords — see the visual-verification skill for the exact detection rules), invoke `Skill(visual-verification)` in parallel. The two skills coordinate via the dev server URL: if `runtime-verification` cannot start the dev server, `visual-verification` returns SKIP with that reason and the completion gate treats the dev-server failure as the primary finding.
3. **Self-review with fix-forward** — dispatch Agent(code-reviewer):
   ```
   Agent(code-reviewer):
     "Review the diff on this branch against $DEFAULT_BRANCH.
      Check for: logic errors, security issues, missing edge cases,
      convention violations. Return P1/P2/P3 findings with file:line."
   ```
   **Fix-forward** (bounded by `fixForwardMaxIterations`, default 10 — safety net against true infinite loops, NOT a planned stop point; see `skills/llm-operator-principles/SKILL.md`):
   - P1 findings → fix immediately (you just wrote this code, no "pre-existing" excuse)
   - P2 findings → fix immediately
   - P3 findings → fix immediately (same disposition as P1/P2 — the proximity test is not a deferral mechanism). Cosmetic P3 in untouched files only: fix if bounded (<10 lines) or document inline in the PR body under `### Known cosmetic notes`. Finding triage is NEVER a valid escalation trigger.
   - After fixes: re-run quality commands, then targeted re-review on files changed by fixes
   - Approaching the iteration ceiling without convergence is a signal to re-check understanding (are two findings in tension? are you fixing the wrong thing?), not to escalate the remaining findings. See `skills/llm-operator-principles/SKILL.md` § Genuine non-convergence for the one terminal case.
4. **Holdout validation** — invoke `holdout-validation` skill to cross-reference self-review claims against actual file state:
   ```
   Skill(holdout-validation):
     Inputs:
     - Self-review findings: {P1/P2/P3 findings from step 3}
     - Evidence bundle draft: {per-criterion evidence collected so far}
     - File list: {all files modified/created on this branch}
   ```
   **Blocking treatment:**
   - P1/P2 findings from holdout-validation → fix immediately before proceeding (same fix-forward loop as step 3)
   - After fixes: re-run holdout-validation to confirm the conflict is resolved
   - P3 findings → fix in-PR as part of the same convergence loop. Only cosmetic P3 in untouched files may be documented inline in the PR body under `### Known cosmetic notes` instead of fixed. Do NOT defer fixable P3 to the PR body.
   - Only proceed to step 5 when holdout-validation returns PASS or no fixable findings remain

   The holdout-validation output is passed to the verdict-judge in step 6 as a required input.
5. **Per-criterion evidence collection** — execute verification tasks created in Phase 2:
   ```
   For each "Verify: ..." task:
     1. TaskUpdate(verifyTaskId, status: "in_progress")
     2. Run the verification command from the task description
     3. Capture output as evidence
     4. TaskUpdate(verifyTaskId, status: "completed", result: "EVIDENCE_COLLECTED")
   ```
   Assemble the evidence bundle following the canonical format in [`references/evidence-bundle-format.md`](../references/evidence-bundle-format.md). For every acceptance criterion, the bundle MUST include: `### Verification command` (the exact command from the Spec Validation Gate), `### Output` (captured stdout/stderr verbatim), `### Does NOT promise` (non-goals — pulled from the Phase 1 specification capture), `### What was tested` (informational), and the three mandatory completeness subsections `### What was NOT tested`, `### Known limitations of this evidence`, `### Negative/adversarial cases covered`. All four mandatory subsections (`Does NOT promise` plus the three completeness ones) accept `none` as a positive statement when the producer can affirmatively say there is nothing to disclose; bare blank is NOT permitted and triggers the verdict-judge auto-FAIL. If a mandatory subsection cannot be filled, escalate via `references/escalation-format.md` rather than emitting a blank field — the gap surfaces with better context than waiting for the auto-FAIL downstream.
6. **Independent verdict** — if `verdict.enabled` is `true` (default), dispatch Agent(verdict-judge):
   ```
   Agent(verdict-judge):
     "Evaluate whether acceptance criteria are met based on evidence.

      Acceptance Criteria:
      {list of ACs from issue body}

      Evidence Bundle:
      {assembled evidence from step 5}

      Holdout Validation Output:
      {findings from step 4 — P1/P2/P3 with file:line citations}"
   ```
   The verdict-judge receives ONLY the acceptance criteria, evidence bundle, and holdout-validation output.
   It does NOT receive: the diff, decision journal, planning rationale, or self-review findings.

   **Handle verdicts:**
   - **All PASS** → proceed to completion gate
   - **Any FAIL** → enter fix loop: fix the failing criterion, re-collect evidence, re-judge (bounded by `fixForwardMaxIterations` as a safety net, not a budget — see `skills/llm-operator-principles/SKILL.md`). FAIL on an acceptance criterion is a genuine escalation case (failing acceptance criteria is a product-level decision, not finding-triage) — but only escalate after genuine non-convergence (same criterion fails 3+ iterations with no progress AND the ceiling is reached).
   - **NEEDS-HUMAN-REVIEW** (no FAILs):
     - If `verdict.requireAllPass` is `true` → treat as FAIL (enter fix loop to produce definitive evidence)
     - If `verdict.requireAllPass` is `false` (default) → present verdict table to user via `AskUserQuestion`:
       > The verdict judge could not determine pass/fail for some criteria.
       > {verdict table}
       > Options:
       > 1. Approve — these criteria are met (I've reviewed the evidence)
       > 2. Reject — fix these criteria before proceeding
     - Based on response: proceed or enter fix loop
   **Manifest emit** — record the verdict artifact after the verdict-judge returns (and any fix-loop iterations have settled):

   ```bash
   "${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/journal-record.sh" \
     --issue "$ISSUE_NUM" \
     --type verdict \
     --metadata result={PASS|FAIL|NEEDS-HUMAN-REVIEW}
   ```

   Add `--metadata pr=$PR_NUMBER` when a PR exists (Phase 4 may run before or after PR creation depending on the workflow). When the verdict is FAIL after the fix loop exhausted iterations, add `--metadata failures=criterion-1,criterion-2` listing the criteria that did not converge — the manifest then carries enough context for `/flow:status` to surface the open verdicts without re-running the judge.

7. **TaskList** — confirm all tasks show status: completed
8. **Visual verification** — when UI-relevant changes detected (changed `.tsx`/`.jsx`/`.vue`/`.html`/`.css`/`.scss`/`.svelte` files OR acceptance criteria mention UI/page/render/display/visual/layout/responsive/component/style):

   This step is normally already covered by step 2's parallel `Skill(visual-verification)` invocation. If step 2 returned `SKIP` because the dev server was unavailable, retry it here once `runtime-verification` has had a chance to fix the dev server failure. Otherwise, this step is a no-op confirmation — read the visual-verification result tasks from step 2 and confirm they reached a terminal state (PASS, FAIL, SKIP, SKIP_WARN, SKIP_USER_APPROVED, MANUAL, or BLOCKED).

   The visual-verification skill owns task creation, browser-tool cascade, screenshot-analyze-verify loop, responsive checks, and result vocabulary. Do not re-implement those steps inline — delegate via `Skill(visual-verification)` per `skills/visual-verification/SKILL.md`. Read its Output Format section to know what to expect in the consolidated output.
9. **Completion gate**: ALL of:
   - All quality checks pass
   - Runtime verification passed (or skipped under one of the three enumerated whitelist categories in the `runtime-verification` skill: `markdown-only`, `config-only`, `dependency-bump-only`)
   - No unresolved P1 findings
   - Holdout validation: PASS or P3-only (no unresolved P1/P2 conflicts)
   - All tasks completed (including verification tasks)
   - Verdict: all criteria PASS or user-approved (when `verdict.enabled`)
   - Visual verification: no BLOCKED results (see escalation below)

   **Visual verification escalation**: If any visual verification task has result containing "BLOCKED", use `AskUserQuestion`:
   > Visual verification is required (`requireVisualVerification: true`) but no browser tools are available.
   > UI files changed: {list of changed .tsx/.jsx/.vue/.html/.css/.scss files}
   >
   > Options:
   > 1. Skip visual verification for this change (will be noted in PR body)
   > 2. I will verify visually myself (manual verification)
   > 3. Help me install browser tools (Playwright MCP recommended)

   Based on response:
   - Option 1 → `TaskUpdate` visual tasks with result "SKIP_USER_APPROVED"
   - Option 2 → `TaskUpdate` visual tasks with result "MANUAL — user will verify"
   - Option 3 → Provide Playwright MCP installation guidance, then retry browser tool cascade
10. **Display summary**:
   - Tasks completed: N/N
   - Quality checks: pass/fail
   - Self-review findings: P1: X, P2: Y, P3: Z (all P1/P2 fixed via fix-forward)
   - Holdout validation: PASS / FINDINGS (P1: X, P2: Y, P3: Z — all P1/P2 fixed)
   - Verdict: PASS (N/N criteria) / FAIL / NEEDS-HUMAN-REVIEW / N/A (spec-free task)
   - Runtime verification: pass/fail/skip
   - Visual verification: PASS / FAIL / SKIP / SKIP_WARN / SKIP_USER_APPROVED / MANUAL
   - Branch: ready for PR

## Completion

Present next steps:

- `/flow:pr` — create pull request (primary suggestion — fix-forward should have committed everything)
- `/flow:commit` — if uncommitted changes remain
- Continue working — keep implementing

## Tier Classification

| Action | Tier | Behavior |
|--------|------|----------|
| Branch creation | 1 | Autonomous |
| File edits | 1 | Autonomous |
| Commits | 1 | Autonomous, logged by hook |
| Issue assignment | 2 | Journal-and-proceed |
| Push | 2 | Journal-and-proceed |
