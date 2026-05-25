---
description: "Review a pull request with multi-faceted analysis. Supports both single-session parallel review and agent team adversarial review."
argument-hint: <pr-number> [free-form context]
allowed-tools: Bash, Read, Write, Edit, Agent, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, Skill, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
Execute independent operations simultaneously.
-->

# Review PR #$ARGUMENTS

Multi-faceted code review with parallel analysis. Follows Explore > Plan > Code > Verify loop.

## Required Skills

- `llm-operator-principles` — foundational operator stance: convergence = zero findings, in-PR fixes by default, no calendar-time estimates, narrow escalation triggers. MUST be consulted before any other phase
- `code-review-methodology` — 6-facet review, finding synthesis, adversarial protocol
- `holdout-validation` — cross-reference self-review claims against file state (Phase 3)

## Phase 1: EXPLORE

`gh pr checkout` stays inline below (mutating working tree); read-only context-gathering is in the `!` block.

```!
# Take the first whitespace-separated token; accept only if it is all digits.
# A non-numeric token (e.g., "foo42" or "evil;rm") is rejected with empty
# PR_NUM so it never reaches the prompt context or any downstream shell.
#
# Output: `###`-headed sections + KEY=value per
# `references/command-output-format.md`. STATE=blocked on bad input.
ARG1="${ARGUMENTS%% *}"
case "$ARG1" in
  ''|*[!0-9]*) PR_NUM="" ;;
  *) PR_NUM="$ARG1" ;;
esac

echo "### PR Reference"
if [ -z "$PR_NUM" ]; then
  echo "STATE=blocked"
  echo "ERROR=PR number required (all-digit). Usage: /flow:review <pr-number>"
else
  echo "STATE=ok"
  echo "PR_NUM=$PR_NUM"

  # Section: PR Details
  echo ""
  echo "### PR Details"
  gh pr view "$PR_NUM" --json title,headRefName,baseRefName,changedFiles,additions,deletions,labels,author,reviews --jq '"TITLE=\"\(.title)\"\nHEAD_BRANCH=\(.headRefName)\nBASE_BRANCH=\(.baseRefName)\nAUTHOR=@\(.author.login)\nCHANGED_FILES=\(.changedFiles)\nADDITIONS=\(.additions)\nDELETIONS=\(.deletions)\nLABELS=\([.labels[].name] | join(","))\nREVIEW_COUNT=\(.reviews | length)"' 2>/dev/null

  # Section: Linked Issue (parsed from PR body)
  echo ""
  echo "### Linked Issue"
  LINKED=$(gh pr view "$PR_NUM" --json body --jq '.body' 2>/dev/null | grep -oE '#[0-9]+' | head -1 | tr -d '#')
  echo "LINKED_ISSUE=${LINKED:-none}"

  # Section: Previous Reviews (follow-up detection)
  echo ""
  echo "### Previous Reviews"
  # Capture gh exit separately. Without this, `jq 'length' | echo "0"` on a
  # failed gh call (auth, network) produces no output (jq 1.8 empty-input
  # ⇒ exit 0) so `||` doesn't fire, COUNT stays empty, and the section
  # silently leaks `REVIEW_COUNT=` (bare empty).
  PREV_JSON=$(gh pr view "$PR_NUM" --json reviews --jq '.reviews' 2>/dev/null); GH_EXIT=$?
  if [ $GH_EXIT -ne 0 ]; then
    echo "REVIEW_COUNT=0"
    echo "STATE=unavailable"
  else
    PREV_COUNT=$(echo "$PREV_JSON" | jq 'length' 2>/dev/null)
    [ -z "$PREV_COUNT" ] && PREV_COUNT=0
    echo "REVIEW_COUNT=$PREV_COUNT"
    if [ "$PREV_COUNT" = "0" ]; then
      echo "STATE=empty"
    else
      echo "$PREV_JSON" | jq -r '.[] | "REVIEW=state=\(.state) by=@\(.author.login) at=\(.submittedAt)"' 2>/dev/null
    fi
  fi

  # Section: Diff Files
  echo ""
  echo "### Diff Files"
  DIFF_FILES=$(gh pr diff "$PR_NUM" --name-only 2>/dev/null)
  # `grep -c '.' || echo 0` produces multi-line `0\n0` on empty input — use
  # explicit empty-check.
  if [ -z "$DIFF_FILES" ]; then
    DIFF_FILE_COUNT=0
  else
    DIFF_FILE_COUNT=$(printf '%s\n' "$DIFF_FILES" | wc -l | tr -d ' ')
  fi
  echo "DIFF_FILE_COUNT=$DIFF_FILE_COUNT"
  if [ "$DIFF_FILE_COUNT" = "0" ]; then
    echo "STATE=empty"
  else
    printf '%s\n' "$DIFF_FILES" | sed 's/^/DIFF_FILE=/'
  fi
fi

true
```

Then check out the PR branch (mutating, runs inline):

```bash
gh pr checkout "$PR_NUM"
```

**Agent(Explore)**: "Read the changed files in this PR and understand the context. What modules are affected? What patterns are being followed or changed?"

Check for previous reviews — if this is a follow-up review, focus on changes since last review.

**Parse structured findings from previous review/resolution cycles** (follow-up reviews only).

```!
# Parse previous review findings + resolution outcomes. PR_NUM is digit-validated
# (matches Phase 1 block); a non-digit token rejects rather than reaching shell.
ARG1="${ARGUMENTS%% *}"
case "$ARG1" in
  ''|*[!0-9]*) PR_NUM="" ;;
  *) PR_NUM="$ARG1" ;;
esac

echo "### Previous Review Cycles"
if [ -z "$PR_NUM" ]; then
  echo "STATE=blocked"
  echo "ERROR=PR number required (all-digit)"
else
  echo "STATE=ok"
  REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)

  # Sub-section: review-cycle markers (in PR review bodies)
  echo ""
  echo "#### Review-cycle markers"
  REVIEW_CYCLES=$(gh api "repos/$REPO/pulls/$PR_NUM/reviews" --jq '
    [.[] | select(.body | test("FLOW_REVIEW_CYCLE")) | {
      cycle: (.body | capture("FLOW_REVIEW_CYCLE:(?<n>[0-9]+)") | .n),
      findings: (.body | capture("FINDINGS:\\[(?<f>[^\\]]+)\\]") | .f)
    }]' 2>/dev/null)
  REVIEW_CYCLE_COUNT=$(echo "$REVIEW_CYCLES" | jq 'length' 2>/dev/null || echo "0")
  echo "REVIEW_CYCLE_COUNT=$REVIEW_CYCLE_COUNT"
  if [ "$REVIEW_CYCLE_COUNT" = "0" ]; then
    echo "STATE=empty"
  else
    echo "$REVIEW_CYCLES" | jq -r '.[] | "REVIEW_CYCLE=cycle=\(.cycle) findings=\"\(.findings)\""' 2>/dev/null
  fi

  # Sub-section: resolution-cycle markers (in PR/issue comments)
  echo ""
  echo "#### Resolution-cycle markers"
  RESOLUTION_CYCLES=$(gh api "repos/$REPO/issues/$PR_NUM/comments" --jq '
    [.[] | select(.body | test("FLOW_RESOLUTION_CYCLE")) | {
      cycle: (.body | capture("FLOW_RESOLUTION_CYCLE:(?<n>[0-9]+)") | .n),
      resolved: (.body | capture("RESOLVED:\\[(?<r>[^\\]]*?)\\]") | .r),
      escalated: (.body | capture("ESCALATED:\\[(?<e>[^\\]]*?)\\]") | .e)
    }]' 2>/dev/null)
  RESOLUTION_CYCLE_COUNT=$(echo "$RESOLUTION_CYCLES" | jq 'length' 2>/dev/null || echo "0")
  echo "RESOLUTION_CYCLE_COUNT=$RESOLUTION_CYCLE_COUNT"
  if [ "$RESOLUTION_CYCLE_COUNT" = "0" ]; then
    echo "STATE=empty"
  else
    echo "$RESOLUTION_CYCLES" | jq -r '.[] | "RESOLUTION_CYCLE=cycle=\(.cycle) resolved=\"\(.resolved // "")\" escalated=\"\(.escalated // "")\""' 2>/dev/null
  fi
fi

true
```

If previous cycles exist, build a **Previous Feedback Status** table and cross-reference each finding's location against `git diff` to verify resolution.

### FlowRun (v3 runtime)

A review is a long-running workflow, so it gets a durable FlowRun. Runs are gated by `flow.runtime.enabled` (default `true`); v2 projects that opted out see `FLOW_RUN_STATE=skip` and the wiring is a no-op.

```!
# FLOW_RUN_BLOCK_BEGIN
CASCADE="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/cascade-resolve.sh"
if [ ! -x "$CASCADE" ]; then
  echo "FLOW_RUN_STATE=blocked"
  echo "FLOW_RUN_ERROR=cascade-resolve.sh missing or non-executable at $CASCADE"
  true; exit 0
fi
RUNTIME_ENABLED=$("$CASCADE" --default "true" '.flow.runtime.enabled' 2>/dev/null)
if [ "$RUNTIME_ENABLED" != "true" ]; then
  echo "FLOW_RUN_STATE=skip"
  echo "FLOW_RUN_REASON=flow.runtime.enabled is not true (v2 mode)"
else
  RUN_ID="$(date -u +%Y-%m-%dT%H%M%SZ)-review"
  echo "FLOW_RUN_STATE=create"
  echo "RUN_ID=$RUN_ID"
  echo "WORKFLOW=review-pr"
  echo "INITIAL_PHASE=preflight"
fi
# FLOW_RUN_BLOCK_END
true
```

When `FLOW_RUN_STATE=create`, invoke `Skill(run-state-management)` to create `.flow/runs/$RUN_ID/run.yaml` (workflow=`review-pr`, goal=`null`), initial phase `preflight`. Phase order: `preflight → fan-out → consolidate → report`. Review is **FlowRun-only — it creates NO FlowGoal**: a review session is bounded by the PR under review, and the PR's own review-thread state (the posted review comment plus its FLOW_REVIEW_CYCLE marker) is the durable record of what the review found. The `run.yaml` captures the workflow's resumability state; there is no separate goal contract to satisfy.

## Phase 2: PLAN

```
TaskCreate("Security review", "Check for OWASP top 10, secrets, injection, auth/authz")
TaskCreate("Code quality review", "Logic correctness, edge cases, error handling")
TaskCreate("Convention review", "Commit format, branch naming, code patterns")
TaskCreate("Test review", "Run quality commands, assess test coverage")
TaskCreate("Requirements review", "Map acceptance criteria to implementation")
TaskCreate("Error handling review", "Check for unhandled exceptions, silent failures, missing edge cases")
TaskCreate("Holdout validation", "Cross-reference self-review claims against actual file state using holdout scenarios")
```

## Phase 3: CODE (Review Execution)

### Path A: Agent Teams (when `agentTeams: true` AND `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is set)

Implements the paired-reviewer + challenge-round protocol. The `team-coordination` skill (`plugins/flow/skills/team-coordination/SKILL.md`) is the protocol contract.

**Path A gate check** (mandatory before paired dispatch — runs before A.1).

```!
echo "### Path A Gate"
# AGENTTEAMS_GATE_BEGIN
# Resolve agentTeams from the standard Claude Code settings cascade.
# Precedence (highest first — first non-empty value wins):
#   1. .claude/settings.flow.local.json — project-local override; gitignored
#      so a hostile fork PR via `gh pr checkout` cannot inject it (it's the
#      user's machine-local pin).
#   2. .claude/settings.flow.json — project-shared; committed with team
#      preferences. Visible in PR review like any other repo file.
#   3. $HOME/.claude/settings.flow.json — user-global default across projects.
#   4. ${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json — plugin default.
# Two-key gate is preserved at the env-var layer: enabling Path A still
# requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS in the user's shell on top
# of agentTeams: true from any tier. The env var alone (no agentTeams:true
# anywhere) cannot enable Path A.
USE_PATH_A=0
LOCAL_SETTINGS=".claude/settings.flow.local.json"
PROJECT_SETTINGS=".claude/settings.flow.json"
USER_SETTINGS="${HOME:-/nonexistent}/.claude/settings.flow.json"
PLUGIN_SETTINGS="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/settings.json"
AGENT_TEAMS=""
SOURCE_USED=""

if ! command -v jq >/dev/null 2>&1; then
  echo "WARN: jq not installed; Path A unavailable, using Path B (single-session)" >&2
else
  for SETTINGS_PATH in "$LOCAL_SETTINGS" "$PROJECT_SETTINGS" "$USER_SETTINGS" "$PLUGIN_SETTINGS"; do
    [ -f "$SETTINGS_PATH" ] || continue
    # `// empty` so absent fields fall through to the next source. A parse
    # error is per-source: WARN names the failing file and the loop continues
    # so a typo in $HOME does not silently disable Path A when plugin tier
    # has a definitive value.
    # `if has("agentTeams") then .agentTeams else empty end` distinguishes
    # "key absent" (fall through to next source) from "key set to false"
    # (definitive, stop here). `// empty` would not work: jq treats `false`
    # as falsy and would fall through, so a user-tier opt-OUT would be
    # silently overridden by the plugin default.
    # `jq -c` (NOT `-r`) preserves JSON quoting so a quoted string value like
    # `{"agentTeams": "true"}` (typo: user wrote a string instead of a
    # boolean) shows up as `"true"` rather than `true`. The case arm below
    # then matches the bare boolean `true` for valid input and routes the
    # quoted-string typo to the catchall WARN. `-r` would strip the quotes
    # and silently enable Path A from a malformed config.
    # JSON `null` is treated as "absent" (fall through to next source) — same
    # semantic as a missing key. A user writing `"agentTeams": null` likely
    # means "use the default", not "definitively no" — we honor that intent.
    JQ_OUT=$(jq -c 'if has("agentTeams") and .agentTeams != null then .agentTeams else empty end' "$SETTINGS_PATH" 2>&1)
    JQ_EXIT=$?
    if [ $JQ_EXIT -ne 0 ]; then
      JQ_ERR=$(printf '%s' "$JQ_OUT" | tr '\n' ' ' | cut -c1-200)
      echo "WARN: failed to parse $SETTINGS_PATH (jq exit=$JQ_EXIT, error: $JQ_ERR); skipping this source" >&2
      continue
    fi
    if [ -n "$JQ_OUT" ]; then
      AGENT_TEAMS="$JQ_OUT"
      SOURCE_USED="$SETTINGS_PATH"
      break
    fi
  done

  if [ -z "$SOURCE_USED" ]; then
    # Diagnostic states — surface what the user can act on:
    # (a) Plugin install missing/broken (CLAUDE_PLUGIN_ROOT path doesn't exist)
    # (b) Files exist but no agentTeams key set
    # State (a) is always WARN-worthy regardless of whether user-tier files exist
    # because the user expected the plugin to be reachable. State (b) is just
    # informational ("you haven't opted in yet").
    PLUGIN_ROOT_BROKEN=0
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ ! -f "$PLUGIN_SETTINGS" ]; then
      PLUGIN_ROOT_BROKEN=1
    fi
    ANY_USER_FILE_EXISTS=0
    [ -f "$LOCAL_SETTINGS" ] && ANY_USER_FILE_EXISTS=1
    [ -f "$PROJECT_SETTINGS" ] && ANY_USER_FILE_EXISTS=1
    [ -f "$USER_SETTINGS" ] && ANY_USER_FILE_EXISTS=1

    if [ $PLUGIN_ROOT_BROKEN -eq 1 ]; then
      # Always WARN about broken plugin root — even when user-tier files exist
      # without the key, the broken root is still actionable info.
      echo "WARN: CLAUDE_PLUGIN_ROOT=$CLAUDE_PLUGIN_ROOT but $PLUGIN_SETTINGS does not exist — plugin install may be corrupted. Add \"agentTeams\": true to $USER_SETTINGS, $PROJECT_SETTINGS, or $LOCAL_SETTINGS to enable Path A; using Path B." >&2
    elif [ $ANY_USER_FILE_EXISTS -eq 0 ] && [ ! -f "$PLUGIN_SETTINGS" ]; then
      echo "WARN: agentTeams not set in any cascade source. CLAUDE_PLUGIN_ROOT is unset and $PLUGIN_SETTINGS does not exist — flow plugin may not be installed in this CWD. Add \"agentTeams\": true to $USER_SETTINGS, $PROJECT_SETTINGS, or $LOCAL_SETTINGS to enable Path A; using Path B." >&2
    else
      echo "Path A skipped: agentTeams not declared in any cascade source ($LOCAL_SETTINGS, $PROJECT_SETTINGS, $USER_SETTINGS, $PLUGIN_SETTINGS). Add \"agentTeams\": true to any of them to opt in."
    fi
  else
    case "$AGENT_TEAMS" in
      true)
        if [ -z "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" ]; then
          echo "WARN: agentTeams=true (from $SOURCE_USED) but CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS env var unset; using single-reviewer fallback (Path B)" >&2
        else
          USE_PATH_A=1
        fi
        ;;
      false)
        echo "Path A skipped: agentTeams=false (from $SOURCE_USED). Using Path B (single-session)."
        ;;
      *)
        # Non-canonical value (e.g., string "true"/"True", "1", "yes", or a
        # multi-line object/array). Surface it rather than silently coerce —
        # a typo here means a user explicitly opted into paired review and
        # got single-session anyway. Collapse multi-line values for log
        # scrapability.
        AGENT_TEAMS_DISPLAY=$(printf '%s' "$AGENT_TEAMS" | tr '\n' ' ' | cut -c1-80)
        echo "WARN: agentTeams=$AGENT_TEAMS_DISPLAY (from $SOURCE_USED) is not the JSON boolean true/false; treating as false. Use \"agentTeams\": true (no quotes)." >&2
        ;;
    esac
  fi
fi
# AGENTTEAMS_GATE_END
echo "USE_PATH_A=$USE_PATH_A"
# Dispatch signal: enabled when both keys passed (agentTeams + env var);
# disabled otherwise. The agent reads PATH_A_STATE for the section dispatch
# and USE_PATH_A for the raw 0/1 flag (preserved for backward compat with
# downstream prose referencing it).
if [ "$USE_PATH_A" = "1" ]; then
  echo "PATH_A_STATE=enabled"
else
  echo "PATH_A_STATE=disabled"
fi

# AGENTTEAM_MODEL_BEGIN
# Resolve the model for Path A review agents. Scoped to Path A only —
# Path B agents continue to inherit the session model via their frontmatter.
# Cascade precedence: local > project > user > plugin default (same cascade as
# agentTeams). Default is sonnet: a paired-reviewer run dispatches ~20 agents,
# so inheriting an Opus session would multiply Opus-rate tokens ~4x for
# marginal review value. An invalid value is rejected with a WARN (NOT silently
# coerced) and falls back to sonnet.
if [ "$USE_PATH_A" = "1" ]; then
  AGENT_TEAM_MODEL=$("$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/cascade-resolve.sh" --default sonnet '.agentTeamModel // empty' 2>/dev/null)
  case "$AGENT_TEAM_MODEL" in
    haiku|sonnet|opus|inherit) ;;
    *)
      echo "WARN: agentTeamModel='$AGENT_TEAM_MODEL' is not one of haiku|sonnet|opus|inherit; rejecting and using sonnet. Set a valid value in .claude/settings.flow.local.json, .claude/settings.flow.json, \$HOME/.claude/settings.flow.json, or the plugin settings.json." >&2
      AGENT_TEAM_MODEL=sonnet
      ;;
  esac
  echo "AGENT_TEAM_MODEL=$AGENT_TEAM_MODEL"
fi
# AGENTTEAM_MODEL_END

true
```

If `USE_PATH_A=0`, skip the rest of Path A and dispatch Path B below.

**Model selection.** When `USE_PATH_A=1`, the gate emits `AGENT_TEAM_MODEL` (default `sonnet`). Dispatch every Path A agent below — both the A.1 paired reviewers and the A.3 challenge rounds — passing `AGENT_TEAM_MODEL` as the Agent tool's per-invocation `model` override (the `model=...` shown in the `Agent(...)` examples maps to that tool argument). The override takes precedence over each agent's `model: inherit` frontmatter (precedence: dispatch override > frontmatter > session model), so the reviewers run on `AGENT_TEAM_MODEL` regardless of the session's model. **When `AGENT_TEAM_MODEL=inherit`, OMIT the `model` argument entirely** — the dispatch-time override accepts only `sonnet`/`opus`/`haiku`, and the session model (the behavior before this setting existed) is expressed by dropping the override, NOT by passing `model=inherit`. The two `Skill(holdout-validation)` invocations are unaffected (skills run inline in the parent context, not as model-dispatched subagents).

#### A.1 — Independent Analysis (paired reviewers, parallel dispatch)

Dispatch **12 invocations** (10 `Agent(...)` + 2 `Skill(holdout-validation)`) in a single parallel block — 5 agent facets × {skeptic, verifier} plus the holdout-validation skill in both lenses. Each variant carries an orthogonal lens; both run with no awareness of each other.

Each `Agent(...)` call below carries `model=$AGENT_TEAM_MODEL` per **Model selection** above. (When the resolved value is `inherit`, drop the `model=` argument — the session model is the default when no override is passed.)

```
Agent(security-reviewer-skeptic, model=$AGENT_TEAM_MODEL):
  "You are reviewing PR #$ARGUMENTS as the SKEPTIC variant. Assume the diff is
   broken until proven otherwise. Flag every security behavior you cannot prove
   correct from the code as written: OWASP Top 10, secrets, auth/authz, input
   validation, dependency vulnerabilities. Return P1/P2/P3 findings with
   file:line citations and category. Do NOT include challenge information —
   another reviewer will challenge your findings later."

Agent(security-reviewer-verifier, model=$AGENT_TEAM_MODEL):
  "You are reviewing PR #$ARGUMENTS as the VERIFIER variant. Assume the diff is
   correct as a baseline. Look only for missed security edge cases, undocumented
   contract assumptions, or invariants that aren't enforced. Return P1/P2/P3
   findings with file:line citations and category."

Agent(code-reviewer-skeptic, model=$AGENT_TEAM_MODEL):
  "PR #$ARGUMENTS as SKEPTIC. Assume broken; flag logic/quality/edge-case
   issues you cannot prove correct. P1/P2/P3 + file:line + category."

Agent(code-reviewer-verifier, model=$AGENT_TEAM_MODEL):
  "PR #$ARGUMENTS as VERIFIER. Assume correct; look only for missed edge cases
   and unenforced invariants. P1/P2/P3 + file:line + category."

Agent(convention-checker-skeptic, model=$AGENT_TEAM_MODEL):
  "PR #$ARGUMENTS as SKEPTIC. Flag every convention violation (commits, branch
   naming, code patterns) you cannot prove conformant. P1/P2/P3 + file:line."

Agent(convention-checker-verifier, model=$AGENT_TEAM_MODEL):
  "PR #$ARGUMENTS as VERIFIER. Look for convention drift the skeptic might miss
   (e.g., subtle stylistic divergence). P1/P2/P3 + file:line."

Agent(test-runner-skeptic, model=$AGENT_TEAM_MODEL):
  "PR #$ARGUMENTS as SKEPTIC. Run quality commands (lint, test, typecheck) and
   flag every failure or warning. Return findings with command output."

Agent(test-runner-verifier, model=$AGENT_TEAM_MODEL):
  "PR #$ARGUMENTS as VERIFIER. Run quality commands and flag missing test
   coverage or weak assertions in passing tests. Return findings."

Agent(error-handler-inspector-skeptic, model=$AGENT_TEAM_MODEL):
  "PR #$ARGUMENTS as SKEPTIC. Flag every error-handling gap, silent failure,
   or unhandled exception you cannot prove handled. P1/P2/P3 + file:line."

Agent(error-handler-inspector-verifier, model=$AGENT_TEAM_MODEL):
  "PR #$ARGUMENTS as VERIFIER. Look for missed error contracts and unenforced
   exception invariants. P1/P2/P3 + file:line."

Skill(holdout-validation):
  Inputs (skeptic lens):
  - Self-review findings: {existing P1/P2/P3 findings}
  - Evidence bundle draft: {requirements compliance map}
  - File list: {all files changed in this PR}
  - Lens: SKEPTIC — assume claims are unsupported until proven

Skill(holdout-validation):
  Inputs (verifier lens):
  - Same inputs
  - Lens: VERIFIER — assume claims are supported; look for missed cross-references
```

Each returns a structured finding list. Index returned findings by facet for the challenge round: `findings[facet][variant] = [F1, F2, ...]`.

**Note on holdout-validation challenge participation** (designed asymmetry — not a tooling workaround): the two `Skill(holdout-validation)` invocations contribute findings to A.2 auto-consensus matching but **do NOT participate in the A.3 challenge round**. This is the principled split between two categorically different finding types:

- **Adversarial challenge (AGREE/DISAGREE/REFINE) is for subjective judgment.** Reviewers can legitimately hold different opinions about whether a SQL pattern is actually exploitable, whether a race condition matters at the project's scale, or whether a P2 finding should be P1 instead. The challenge round surfaces those disagreements; the consolidator weights confidence by the disposition the OTHER reviewer assigned.
- **Holdout findings are objective claim-verification.** The question they answer is binary: did the self-reported evidence match the file state? The file state is the arbiter, not reviewer opinion. A challenger cannot meaningfully DISAGREE with "the agent claimed test X exists; grep finds no test for X" — they can re-check the file (which produces the same answer) but they cannot vote it away.

Including holdout in challenge would either (a) produce vacuous AGREE responses (re-check confirms what we already established) or (b) confuse the protocol (DISAGREE based on what — the file state changed? the claim was parsed differently?). The asymmetry is principled and intentional. The two holdout lenses (skeptic + verifier) DO produce a confidence signal: when both lenses raise the same finding the disposition is `consensus`; when only one lens raises it the disposition is `unchallenged` (meaning the OTHER lens parsed the claim differently or weighted holdout-scenario priority differently — itself a useful signal worth investigating, but not via AGREE/DISAGREE voting).

Consequently, the cost table in `team-coordination/SKILL.md` lists **10** challenge calls rather than 12 — the 2-call savings is the principled exclusion, not a tooling shortcut. Holdout findings emit at A.4 with `consensus` (both lenses raised it independently) or `unchallenged` (one lens only); they NEVER carry `validated` / `refined` / `kept` because those dispositions are challenge-round outputs.

**Post-condition on returned IDs**: each variant's findings must have IDs matching `^[A-Za-z][A-Za-z0-9_-]*$` before A.2 consumes them — the same allowlist that downstream consumers (`status.md:104-117`, `merge.md`) enforce. IDs that fail validation are skipped at A.2 with a `LEDGER_WARN: PR#{N} A.1 rejected non-conforming ID '{safe-id}' from {variant}` to stderr. This avoids producing markers that get silently dropped downstream and makes the A.2 lexicographic tiebreaker safe against pathological IDs.

#### A.2 — Auto-consensus detection

Before dispatching the challenge round, detect findings that BOTH variants raised independently. The match window is hard-coded for v1: same facet AND same file AND lines within ±2 AND priority within ±1 (P1↔P2 counts; P1↔P3 does not).

```bash
# Pseudocode (apply per facet, deterministic — see helpers below).
# Iterate skeptic findings in lexicographic ID order so the loop itself is
# deterministic. paired_b = set() tracks verifier findings already paired in
# this facet — once paired, a finding cannot be paired again.
# paired_b = set()
# for finding_a in sorted(findings[facet][skeptic], key=lambda a: a.id):
#   candidates = []
#   for finding_b in findings[facet][verifier]:
#     if finding_b.id in paired_b: continue            # skip already-paired
#     if (line(finding_a) > 0) != (line(finding_b) > 0): continue  # see C10
#     if same_file(finding_a, finding_b) AND
#        abs(line(finding_a) - line(finding_b)) <= 2 AND
#        priority_distance(finding_a.priority, finding_b.priority) <= 1:
#       candidates.append(finding_b)
#   if candidates:
#     # Deterministic tiebreaker: smallest line distance, then smallest priority
#     # distance, then lexicographic ID. Required so re-runs of the same review
#     # produce the same consensus pairing.
#     finding_b = min(candidates, key=lambda b: (
#       abs(line(finding_a) - line(b)),
#       priority_distance(finding_a.priority, b.priority),
#       b.id
#     ))
#     mark (finding_a, finding_b) as auto-consensus -> confidence=HIGH, disposition=consensus
#     paired_b.add(finding_b.id)
#     remove finding_a and finding_b from challenge candidates for this facet
```

**Helper definitions** (specified to remove implementer ambiguity):

| Helper | Definition |
|--------|------------|
| `line(finding)` | Integer parsed from the first `:N` group in `file:line`. For ranges (`file:42-50`), use the low end (`42`). For file-level findings (no line citation), treat as line `0`. The pseudocode above explicitly skips pairs where one side is line-bearing (`>0`) and the other is file-level (`==0`) — see the second `continue` in the loop — so file-level findings only ever match other file-level findings on the same file. |
| `same_file(a, b)` | Compare normalized paths: strip leading `./`, resolve `..` segments, lowercase only on case-insensitive filesystems. Returns true on equality. |
| `priority_distance(p1, p2)` | `0` if equal, `1` for P1↔P2 or P2↔P3, `2` for P1↔P3. The match window threshold is `≤ 1` so P1↔P3 NEVER match. |

Auto-consensus findings skip the challenge round (no need — both reviewers already agreed independently).

#### A.3 — Challenge Round (disposition-only, parallel)

For findings NOT in auto-consensus, dispatch each variant to challenge the OTHER variant's findings. **Variants do NOT re-read the diff.** Up to 10 challenge prompts run in parallel (5 agent facets × 2 directions; holdout-validation excluded — see A.1 note). Each challenge `Agent(...)` carries `model=$AGENT_TEAM_MODEL` per **Model selection**.

```
Agent(security-reviewer-skeptic, model=$AGENT_TEAM_MODEL) [challenge mode]:
  "You are reviewer-A (skeptic) for facet 'security'. Reviewer-B (verifier)
   raised the following findings on the same diff you reviewed independently.
   For each finding, respond with exactly one line:

     {finding-id} AGREE
     {finding-id} DISAGREE: {one-line reason}
     {finding-id} REFINE: priority={P1|P2|P3} category={text}

   Do NOT re-read the diff. Decide based on your prior independent analysis only.

   Findings to challenge:
   {list of verifier's non-auto-consensus findings: ID, file:line, priority, category}"

Agent(security-reviewer-verifier, model=$AGENT_TEAM_MODEL) [challenge mode]:
  "Same instructions, reversed: challenge the skeptic's non-auto-consensus
   findings for facet 'security'."

[... repeat for the other 5 facets in parallel ...]
```

Each challenge call returns a list of `{finding-id, disposition, optional reason/refinement}`.

#### A.4 — Consolidation

Apply the consolidation table from `team-coordination/SKILL.md` Phase 4. For each finding, look up its origin and the other variant's disposition:

| Origin | Other variant's disposition | Confidence | Marker disposition vocab |
|--------|------------------------------|------------|--------------------------|
| Auto-consensus (A.2) | n/a | **HIGH** | `consensus` |
| One raised, other AGREE | AGREE | **HIGH** | `validated` |
| One raised, other REFINE | REFINE | **MEDIUM** | `refined` (use REFINE'd priority/category) |
| One raised, other DISAGREE | DISAGREE | **LOW** | `kept` (record reason) |
| One raised, other timed out / errored | none | **MEDIUM** | `unchallenged` |
| Both raised, both DISAGREE'd | n/a | **DROPPED** | excluded from output, logged below |

**DROPPED findings** are logged to `.decisions/issue-{N}.md` (where N = the issue this PR addresses) under a `## Dropped after challenge (PR #$PR_NUM, cycle {N})` heading with the finding details and both DISAGREE reasons. They never appear in the rendered tables or the FLOW_REVIEW_CYCLE marker.

**Manifest emit** — for each DROPPED finding, append a `dropped-finding` artifact to the journal manifest so `/flow:learn` can detect repeated drop reasons across cycles (a recurring drop reason is a learnable signal):

```bash
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/journal-record.sh" \
  --issue $ISSUE \
  --type dropped-finding \
  --metadata cycle=$CYCLE \
  --metadata finding_id=$FINDING_ID \
  --metadata facet=$FACET \
  --metadata reason="$REASON" \
  --metadata pr="$PR_NUM"
```

Repeat once per dropped finding. The freeform `## Dropped after challenge` section preserves the verbose details (both DISAGREE reasons, file:line); the manifest entry is the queryable index.

#### A.5 — Per-facet fallback application

If any of A.1's variants failed (timeout, error, did-not-spawn), apply the fallback semantics from `team-coordination/SKILL.md` per facet — never block the review:

| Failure | Action |
|---------|--------|
| One variant failed for facet F | Use the responding variant's findings only; mark each as `unchallenged` (MEDIUM). Note in output: `facet F: single-reviewer fallback (skeptic failed)`. |
| Both variants failed for facet F | Re-dispatch single Agent for that facet using the Path B prompt. Note in output: `facet F: re-dispatched as single-reviewer (both variants failed)`. |
| Challenge round failed for a facet | Skip A.3 for that facet; keep A.1 findings as `unchallenged`. Note in output: `facet F: challenge skipped (challenge prompt failed)`. |
| A.2 auto-consensus matching errored on finding F (e.g., malformed `file:line`) | Skip auto-consensus for F; route F through A.3 challenge as if non-consensus. Log `LEDGER_WARN: PR#{N} A.2 skipped F:<id> due to <reason>` to stderr. |
| A.4 consolidation lookup missing for finding F (e.g., orphaned challenge response) | Emit F as `unchallenged` MEDIUM. Append to `.decisions/issue-{N}.md` (where N = the issue this PR addresses) under a `## Consolidation gaps (PR #$PR_NUM, cycle {N})` heading with the orphan reason. Create the journal file with frontmatter if it does not exist. **Also emit `--type consolidation-gap`** via `bin/journal-record.sh` with `cycle`, `finding_id`, `reason`, and `pr` metadata so the manifest carries a machine-readable trail of fallback fires. |

#### A.6 — Emit consolidated output

Use the synthesized findings (with confidence + disposition) for steps in Phase 4 below. The FLOW_REVIEW_CYCLE marker emitted in Phase 4 step 7 uses the 7-field form when paired-reviewer mode produced the findings (example exercises three disposition values):

```
<!-- FLOW_REVIEW_CYCLE:{N} FINDINGS:[F1|P1|security|src/auth.ts:42|open|HIGH|consensus,F2|P2|correctness|src/api.ts:88|open|MEDIUM|refined,F3|P1|race|src/job.ts:17|open|LOW|kept] -->
```

When Path A is the orchestrator, the marker is **uniformly 7-field** — including for findings produced by per-facet fallbacks (which carry `MEDIUM|unchallenged`). The 5-field form is preserved ONLY for full Path B runs (gate failed at the top of this section). Mixing 5-field and 7-field rows within a single marker is forbidden — pad fallback findings to 7 fields with `MEDIUM|unchallenged` so all rows match. This rule is restated at Phase 4 step 7.

After A.6 completes, jump to Phase 4 with the consolidated finding set.

### Path B: Single Session (default)

Path B dispatch is intentionally unchanged — its agents carry no `model` parameter and inherit the session model via frontmatter. The `agentTeamModel` setting applies to Path A only.

**Parallel Agent dispatch** — 5 agents in single message:

```
Agent(code-reviewer):
  "Review PR #$ARGUMENTS diff for quality, logic, edge cases, security.
   Return P1/P2/P3 findings with file:line."

Agent(convention-checker):
  "Validate commits, branch naming, conventions for PR #$ARGUMENTS."

Agent(test-runner):
  "Run quality commands for PR #$ARGUMENTS branch."

Agent(error-handler-inspector):
  "Inspect changed files in PR #$ARGUMENTS for error handling gaps,
   silent failures, unhandled exceptions. Return P1/P2/P3 findings."

Agent(security-reviewer):
  "Review PR #$ARGUMENTS diff for OWASP Top 10, secrets, auth/authz,
   input validation, dependency vulnerabilities. Return P1/P2/P3 with file:line."

Skill(holdout-validation):
  Inputs:
  - Self-review findings: {P1/P2/P3 findings from code-reviewer agent}
  - Evidence bundle draft: {per-criterion evidence from requirements review}
  - File list: {all files changed in this PR}
```

**Main thread**: Requirements compliance — map acceptance criteria to implementation.

TaskUpdate each review task as agents complete.

**FlowActivity writes** (when `FLOW_RUN_STATE=create`): invoke `Skill(run-state-management)` to record a FlowActivity as the consolidate boundary completes — once the per-facet findings (Path A consolidation or Path B synthesis) have been merged into a single deduplicated finding set, advancing `state.current_phase` to `consolidate` per the `preflight → fan-out → consolidate → report` order.

## Phase 4: VERIFY

**CRITICAL: Posting review findings to the PR is MANDATORY. NEVER skip posting. The review is not complete until `gh pr review` has been executed and TaskUpdate confirms the post task is completed. Do not suggest next steps until posting is verified.**

1. **TaskList**: Confirm all review facets complete
2. **Synthesize findings**: Deduplicate by file:line, prioritize P1/P2/P3
3. **Display findings** (finding-first pattern):

```markdown
## Review Summary for PR #$PR_NUM

### Findings: P1: {X}, P2: {Y}, P3: {Z}

### P1 — Critical
| # | Category | Location | Issue | Fix |
|---|----------|----------|-------|-----|

### Requirements Adherence
| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
```

4. **Determine review mode** — compare PR author vs current user:

   ```bash
   PR_AUTHOR=$(gh pr view "$PR_NUM" --json author --jq '.author.login')
   CURRENT_USER=$(gh api user --jq '.login')
   ```

5. **Self-review (own PR — PR_AUTHOR == CURRENT_USER)**:

   Fix-forward approach (bounded by `fixForwardMaxIterations`, default 10 — a safety net against true infinite loops, not a budget; see `skills/llm-operator-principles/SKILL.md`):
   - P1 findings → fix immediately
   - P2 findings → fix immediately
   - P3 findings → fix immediately (the proximity test is not a deferral mechanism — P3 in touched files gets the same disposition as P1/P2)
   - TaskCreate("Test coverage for fix-forward", "Write or update tests for each P1/P2/P3 fix applied during self-review")
   - For each fix: write or update a test that covers the fixed behavior
   - After fixes: run targeted re-review of only changed files
   - TaskUpdate(testCoverageTaskId, status: "completed", result: "Tests written/updated for {N} fixes")
   - No follow-up issue creation for fixable items — finding triage is NEVER a valid escalation trigger; fix in this PR
   - Approaching the iteration ceiling without convergence is a signal to re-check the findings (are two findings in tension? misunderstood scope?), not to escalate
   - TaskCreate("Post self-review comment", "Post review findings summary to PR via gh pr review --comment")

6. **External review (someone else's PR — PR_AUTHOR != CURRENT_USER)**:

   - TaskCreate("Post review comment", "Post structured review findings to PR via gh pr review")
   - P1/P2/P3 in already-touched files → REQUEST_CHANGES (P1/P2) or COMMENT with fix-expected language (P3) — the author must fix
   - Cosmetic P3 in untouched files → COMMENT with fix-if-bounded-or-document-inline language (default mode) OR follow-up issue workflow (only when `minimalScope: true` or the PR author has explicitly invoked minimal scope)
   - P1/P2 in untouched files → REQUEST_CHANGES; author must address in-PR (finding triage is NEVER a valid escalation trigger; see `skills/llm-operator-principles/SKILL.md`)

   Findings in files the PR already modifies are NEVER out-of-scope — the author owns the known defects in any file they touch. Do NOT flag them as informational; flag them as blocking.

   **Default mode (no `minimalScope` set):** for cosmetic P3 findings in untouched files, do NOT create follow-up issues and do NOT present an AskUserQuestion asking the author to defer. Recommend "fix if bounded (<10 lines) or document inline in the PR body" in the review comment.

   **Minimal-scope mode (`settings.json` → `minimalScope: true`):** for cosmetic P3 findings in untouched files only, the original follow-up workflow is restored:

   Present the findings and use the AskUserQuestion tool with contextual options: "These cosmetic P3 findings are in untouched files. Which ones should become follow-up issues?"

   For each selected finding, create a GitHub issue using issue-crafting skill knowledge:
   - Title: concise, solution-agnostic description of the finding
   - Body: Context, Current State (file:line), Objective, Acceptance Criteria
   - Labels: select from repo labels based on finding category
   - Issue creation is Tier 2 (journal-and-proceed)

   ```bash
   gh issue create --title "{title}" --body "{body}" --label "{labels}"
   ```

   Include created issue numbers in the review comment body.

   **Note**: Reviewers should recognize `improve:` commits as legitimate Boy Scout cleanup — approve if they pass the proximity test.

7. **Post review findings** (MANDATORY — applies to both self-review and external review):

   For follow-up reviews, include the **Previous Feedback Status** table:
   ```markdown
   ### Previous Feedback Status
   | Cycle | Finding | Priority | Claimed Status | Verified |
   |-------|---------|----------|----------------|----------|
   ```
   Cross-reference each prior finding's location against `git diff` to verify resolution.

   Build `$BODY` using the appropriate template:
   - Self-review: `templates/self-review-comment.md`
   - External review: `templates/review-comment.md`

   **Marker form selection** (FLOW_REVIEW_CYCLE):
   - If Path A produced the findings (paired-reviewer mode), emit the **7-field** marker with Confidence + Disposition fields per finding. Render the Confidence + Disposition columns in the P1/P2/P3 tables.
   - If Path B produced the findings (single-session, fallback, or `agentTeams: false`), emit the legacy **5-field** marker. Omit the Confidence + Disposition columns.
   - When Path A had per-facet fallbacks, individual findings from fallback facets carry `unchallenged` disposition with MEDIUM confidence — emit them in the 7-field form alongside the rest. Mixed-form rows within a single marker are NOT permitted (parsers tolerate variable field count, but emitting both forms in one row list would be confusing); pad fallback findings to 7 fields with `MEDIUM|unchallenged`.

   Post the review:
   - Self-review → `gh pr review "$PR_NUM" --comment --body "$BODY"`
   - External + P1 findings → `gh pr review "$PR_NUM" --request-changes --body "$BODY"`
   - External + P2 findings (no P1) → `gh pr review "$PR_NUM" --request-changes --body "$BODY"`
   - External + P3 only → `gh pr review "$PR_NUM" --comment --body "$BODY"` (fix-expected, not approve-with-nits)
   - External + No findings → `gh pr review "$PR_NUM" --approve --body "$BODY"`

   TaskUpdate(postCommentTaskId, status: "completed", result: "PASS — review posted as {approve/request-changes/comment}")

   **Manifest emit** — record the review-cycle artifact in the issue's journal manifest. Use the issue number associated with this PR (parse from PR body: `gh pr view "$PR_NUM" --json body --jq '.body' | grep -oE '#[0-9]+' | head -1 | tr -d '#'`):

   ```bash
   ISSUE=$(gh pr view "$PR_NUM" --json body --jq '.body' | grep -oE '#[0-9]+' | head -1 | tr -d '#')
   if [ -n "$ISSUE" ]; then
     "$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/journal-record.sh" \
       --issue $ISSUE \
       --type review-cycle \
       --metadata cycle=$CYCLE_NUMBER \
       --metadata path={A|B} \
       --metadata findings_count=$TOTAL \
       --metadata pr="$PR_NUM"
   fi
   ```

   The `path` value is `A` when paired-reviewer mode produced the findings (7-field marker), `B` when Path B (5-field marker) produced them. `findings_count` is the total across P1+P2+P3 in the cycle. If the PR body does not link an issue, skip the emit (the marker on the PR comment is sufficient for that PR's own state; the manifest is keyed by issue, not PR).

8. **Verify posting**: TaskList — confirm "Post review comment" or "Post self-review comment" task is completed. Do NOT proceed to step 9 until this is verified.

9. **Post-review**: If self-review fixed everything, suggest `/flow:pr`. If external review, suggest `/flow:address $PR_NUM` for the PR author.

**FlowActivity writes** (when `FLOW_RUN_STATE=create`): invoke `Skill(run-state-management)` to record a FlowActivity as the report boundary completes — once the review comment is posted (step 7) and posting is verified (step 8), advancing `state.current_phase` to `report` per the `preflight → fan-out → consolidate → report` order.

**FlowRun terminal transition** (when `FLOW_RUN_STATE=create`): once the review comment is posted (or no-finding evidence is recorded), invoke `Skill(run-state-management)` to transition the FlowRun to `state.status: completed`. The `workflow-run` journal artifact is best-effort — a review is PR-scoped, not issue-scoped — so emit `bin/journal-record.sh --type workflow-run` only if a single issue can be inferred from the PR (the linked issue parsed from the PR body); otherwise the `run.yaml` is the durable record and no journal artifact is written. If the review failed or was cancelled before posting, transition to `state.status: cancelled` (with `blocked_reason`) instead so `/flow:resume` does not treat it as resumable.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| `gh pr checkout` | 1 | Autonomous |
| Read PR diff / files / previous reviews | 1 | Autonomous, read-only |
| Multi-agent dispatch (Path B: 5 agents + holdout) or paired-reviewer dispatch (Path A: 12 invocations + 10 challenge) | 1 | Autonomous; Tasks tracked |
| Holdout validation (skill, parallel) | 1 | Autonomous |
| Self-review fix-forward (when reviewing own PR) | 1 | File edits + commits autonomous; push is Tier 2 |
| `gh pr review --comment / --request-changes / --approve` | 2 | Journal-and-proceed |
| Follow-up issue creation (cosmetic P3 in untouched files, external PR review only) | 2 | Journal-and-proceed |
