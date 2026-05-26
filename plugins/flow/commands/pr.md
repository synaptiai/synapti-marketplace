---
description: "Create a pull request with full code review, quality gates, comprehension report, and reviewer suggestions. Runs parallel agent review before PR creation."
argument-hint: [title]
allowed-tools: Bash, Read, Write, Edit, Agent, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, Skill, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
When performing multiple independent operations, invoke ALL relevant tools
simultaneously in a single message rather than sequentially.
-->

# Create Pull Request

Full PR creation workflow with multi-faceted review, quality gates, and structured PR body. Follows Explore > Plan > Code > Verify loop.

## Required Skills

- `llm-operator-principles` — foundational operator stance: convergence = zero findings, in-PR fixes by default, no calendar-time estimates, narrow escalation triggers. MUST be consulted before any other phase
- `pr-lifecycle` — pre-flight, PR body, reviewer suggestion
- `code-review-methodology` — 6-facet review synthesis
- `capability-discovery` — detect quality commands and agents
- `holdout-validation` — cross-reference self-review claims against file state (Phase 3)

## References

- [`references/escalation-format.md`](../references/escalation-format.md) — canonical six-field structure used by Phase 4's visual-verification BLOCKED escalation and any other Proactive-Autonomy escalation surfaced during PR creation
- [`references/finding-schema.md`](../references/finding-schema.md) — canonical row shape every reviewer agent dispatched in Phase 3 emits

## Phase 1: EXPLORE

```!
# Output: `###`-headed sections + KEY=value per
# `references/command-output-format.md`. STATE=blocked when on default branch
# (can't create a PR from main); STATE=ok otherwise.

echo "### Branch Context"
BRANCH=$(git branch --show-current 2>/dev/null)
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
echo "BRANCH=$BRANCH"
echo "DEFAULT_BRANCH=$DEFAULT_BRANCH"

if [ "$BRANCH" = "$DEFAULT_BRANCH" ]; then
  echo "STATE=blocked"
  echo "ERROR=Cannot create PR from default branch"
else
  echo "STATE=ok"

  # Section: Branch Delta vs Default
  echo ""
  echo "### Branch Delta"
  echo "COMMITS_AHEAD=$(git rev-list --count "$DEFAULT_BRANCH"..HEAD 2>/dev/null || echo "0")"
  # Cache the porcelain count once — previously invoked twice in adjacent
  # lines (count + gate on the UNCOMMITTED_LINE listing).
  UNCOMMITTED_COUNT=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  echo "UNCOMMITTED_COUNT=$UNCOMMITTED_COUNT"
  [ "$UNCOMMITTED_COUNT" != "0" ] && git status --short 2>/dev/null | head -20 | sed 's/^/UNCOMMITTED_LINE=/'
  echo ""
  echo "#### Diff stat"
  DIFF_STAT=$(git diff --stat "$DEFAULT_BRANCH"...HEAD 2>/dev/null)
  if [ -z "$DIFF_STAT" ]; then
    echo "STATE=empty"
  else
    printf '%s\n' "$DIFF_STAT" | sed 's/^/DIFF_STAT=/'
  fi

  # Section: Issue Context (extracted from branch name `feature/issue-N-...`)
  echo ""
  echo "### Issue Context"
  ISSUE_NUM=$(echo "$BRANCH" | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+')
  # Quote parenthesized fallback per command-output-format.md rule 2 (values
  # with whitespace/parens must be double-quoted scalars).
  echo "ISSUE_NUM=${ISSUE_NUM:-\"(none)\"}"
  if [ -n "$ISSUE_NUM" ]; then
    gh issue view "$ISSUE_NUM" --json title,body,labels --jq '
      "ISSUE_TITLE=\"\(.title)\"\nISSUE_LABELS=\([.labels[].name] | join(","))\nISSUE_BODY_LENGTH=\(.body | length)"
    ' 2>/dev/null
  fi

  # Section: Existing PR Check
  echo ""
  echo "### Existing PR Check"
  # Capture gh exit separately. The `|| echo "0"` fallback fails to fire when
  # gh succeeds but returns "" (impossible here — gh returns [] for empty
  # success) OR when jq receives empty input from a failed gh call (jq 1.8
  # produces no output + exit 0, so `||` doesn't trigger and the section
  # silently leaks `EXISTING_PR_COUNT=`).
  EXISTING=$(gh pr list --head "$BRANCH" --state open --json number,url 2>/dev/null); GH_EXIT=$?
  if [ $GH_EXIT -ne 0 ]; then
    echo "EXISTING_PR_COUNT=0"
    echo "STATE=unavailable"
  else
    EXISTING_COUNT=$(echo "$EXISTING" | jq 'length' 2>/dev/null)
    [ -z "$EXISTING_COUNT" ] && EXISTING_COUNT=0
    echo "EXISTING_PR_COUNT=$EXISTING_COUNT"
    if [ "$EXISTING_COUNT" = "0" ]; then
      echo "STATE=empty"
    else
      echo "$EXISTING" | jq -r '.[] | "EXISTING_PR=number=\(.number) url=\(.url)"' 2>/dev/null
    fi
  fi

  # Section: Decision Journal
  echo ""
  echo "### Decision Journal"
  JOURNAL_DIR=".decisions"
  if [ -n "$ISSUE_NUM" ] && [ -f "$JOURNAL_DIR/issue-$ISSUE_NUM.md" ]; then
    echo "JOURNAL_FILE=$JOURNAL_DIR/issue-$ISSUE_NUM.md"
    echo "JOURNAL_BYTES=$(wc -c < "$JOURNAL_DIR/issue-$ISSUE_NUM.md" | tr -d ' ')"
    echo ""
    echo "#### Journal contents"
    cat "$JOURNAL_DIR/issue-$ISSUE_NUM.md"
  else
    echo "STATE=empty"
  fi

  # Section: FlowGoal State (v3) — gate on goal existence (#111 D-GATE).
  # Surface the active goal's lifecycle so Phase 4 can gate PR creation on goal
  # achievement WHEN a goal exists; a branch with no goal is not blocked. The
  # gate is disabled when flow.goals.enabled is false or goalCreation is off,
  # preserving the v2 (requireGoalForStart:false) UX.
  echo ""
  echo "### FlowGoal State"
  HELPER="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/cascade-resolve.sh"
  # Migration-aware (#111 AC-1): goalCreation wins; else map legacy
  # requireGoalForStart (true→always, false→off); else null → cascade default auto.
  GOAL_MODE=$("$HELPER" --default "auto" '.flow.goals.goalCreation // (if .flow.goals.requireGoalForStart == true then "always" elif .flow.goals.requireGoalForStart == false then "off" else null end)' 2>/dev/null)
  case "$GOAL_MODE" in auto|always|off) ;; *) GOAL_MODE="auto" ;; esac
  ENABLED=$("$HELPER" --default "true" '.flow.goals.enabled' 2>/dev/null)
  if [ "$ENABLED" != "true" ] || [ "$GOAL_MODE" = "off" ]; then
    echo "STATE=disabled"
    echo "REASON=flow.goals.enabled is false or goalCreation is off"
  else
    ACTIVE_GOAL_HELPER="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/flow-active-goal.sh"
    if [ ! -x "$ACTIVE_GOAL_HELPER" ]; then
      echo "STATE=unavailable"
      echo "REASON=flow-active-goal.sh missing or non-executable"
    else
      # --allow-terminal (#122): surface an already-`achieved` goal so the
      # GATE=pass branch below is reachable (the helper is active-only otherwise).
      GOAL_STATUS=$("$ACTIVE_GOAL_HELPER" --status --allow-terminal 2>/dev/null); GOAL_EXIT=$?
      case "$GOAL_EXIT" in
        0)
          GOAL_ID=$("$ACTIVE_GOAL_HELPER" --id --allow-terminal 2>/dev/null)
          echo "STATE=ok"
          echo "GOAL_ID=$GOAL_ID"
          echo "GOAL_LIFECYCLE=$GOAL_STATUS"
          if [ "$GOAL_STATUS" = "achieved" ]; then
            echo "GATE=pass"
          else
            echo "GATE=block"
          fi
          ;;
        1)
          # No active goal on this branch — gate not applicable (#111 D-GATE:
          # gate on existence). PR creation proceeds; a goal-less PR is not blocked.
          echo "STATE=none"
          echo "GATE=pass"
          echo "REASON=no active FlowGoal for this branch — gate not applicable"
          ;;
        3)
          echo "STATE=degenerate"
          echo "GATE=block"
          echo "REASON=multiple active goals on the current branch — run /flow:goal history and clear extras"
          ;;
        *)
          echo "STATE=unavailable"
          echo "GATE=block"
          echo "REASON=flow-active-goal.sh exited $GOAL_EXIT"
          ;;
      esac
    fi
  fi
fi

true
```

**Skill invocation:** `Skill(capability-discovery)` — detect quality commands.

If uncommitted changes exist, offer to run `/flow:commit` first.
If PR already exists, offer to update instead.

## Phase 2: PLAN

Create review tasks:

```
TaskCreate("Code quality and logic review", "Review diff for logic errors, edge cases, error handling")
TaskCreate("Security scan", "Check for OWASP top 10, secrets, auth issues")
TaskCreate("Convention check", "Validate commits, branch naming, patterns")
TaskCreate("Quality commands", "Run lint, test, typecheck")
TaskCreate("Requirements compliance", "Map acceptance criteria to implementation")
TaskCreate("Error handling review", "Check for unhandled exceptions, silent failures, missing edge cases")
TaskCreate("Holdout validation", "Cross-reference self-review claims against actual file state using holdout scenarios")
```

If the diff includes UI-relevant files (`.tsx`, `.jsx`, `.vue`, `.html`, `.css`, `.scss`):
```
TaskCreate("Visual verification", "Verify UI renders correctly with screenshot analysis")
```

Add runtime verification task:
```
TaskCreate("Runtime verification", "Build, start, and smoke test before PR creation")
```

Get the diff for review:

```bash
git diff "$DEFAULT_BRANCH"...HEAD
```

## Phase 3: CODE (Review Execution)

**Parallel Agent dispatch** — 5 agents and skill in a single message (parity with `/flow:review` Path B):

```
Agent(code-reviewer):
  "Review the branch diff against $DEFAULT_BRANCH for code quality,
   logic correctness, edge cases, and security. Return P1/P2/P3 findings
   with file:line citations."

Agent(convention-checker):
  "Validate commit messages, branch naming, and code conventions
   against project standards. Return findings."

Agent(test-runner):
  "Discover and run quality commands (lint, test, typecheck).
   Return structured results table."

Agent(security-reviewer):
  "Review the branch diff against $DEFAULT_BRANCH for OWASP Top 10,
   secrets, auth/authz, input validation, dependency vulnerabilities.
   Return P1/P2/P3 findings with file:line."

Agent(error-handler-inspector):
  "Inspect changed files for error handling gaps, silent failures,
   unhandled exceptions. Return P1/P2/P3 findings."

Skill(holdout-validation):
  Inputs:
  - Self-review findings: {P1/P2/P3 from code-reviewer}
  - Evidence bundle draft: {requirements compliance map}
  - File list: {all files changed since branch creation}
```

**Main thread** (while agents run in parallel if using background agents, or after if foreground):
- Requirements compliance check: map acceptance criteria → implementation evidence
- TaskUpdate for requirements task

After agents return, TaskUpdate each review task with findings.

## Phase 4: VERIFY

1. **Synthesize findings**: Deduplicate by file:line, prioritize P1 > P2 > P3
2. **Integration verification** — dispatch Agent(integration-verifier):
   ```
   Agent(integration-verifier):
     "Verify runtime behavior for this branch. Invoke Skill(runtime-verification)
      for build, dev-server, smoke, E2E, and LSP diagnostics. If UI files changed,
      ALSO invoke Skill(visual-verification) in parallel for the screenshot-
      analyze-verify loop and responsive checks. Validate acceptance criteria at
      runtime. Return the verification results table per `skills/runtime-
      verification/SKILL.md` plus the visual table per `skills/visual-
      verification/SKILL.md`. Emit any findings using the canonical schema in
      `references/finding-schema.md`."
   ```
   After agent returns:
   - If visual verification task was created in Phase 2: `TaskUpdate(visualVerificationTaskId, status: "completed", result: "{agent's visual verification findings}")`
   - Record screenshot paths from agent results as evidence
3. **TaskList**: Confirm all review tasks complete (including visual verification if created)
4. **Runtime verification**: If integration-verifier returns SKIP without justification, run runtime verification directly (build, start, smoke test). Runtime verification must pass before PR creation.
5. **Visual verification enforcement**: If `visualVerification.requireVisualVerification` is `true` and integration-verifier returned visual verification as BLOCKED:
   - Use `AskUserQuestion` with a Proactive-Autonomy escalation:
     > **Situation** — Visual verification is required (`requireVisualVerification: true`) but no browser tools are available. UI files changed: {list}.
     >
     > **What I tried** — Checked for Playwright MCP, headless browser tools, and gstack. None available.
     >
     > **Options**:
     > 1. Skip visual verification — noted in PR body (Recommended if changes are minor CSS/copy)
     > 2. I will verify visually myself — marked as MANUAL in PR body
     > 3. Help me install browser tools — I'll provide Playwright MCP installation guidance and retry
     >
     > **Recommendation** — Option {1|2|3} based on scope of UI changes.
     >
     > **Blocking?** — Yes if `requireVisualVerification: true`; otherwise soft.
     >
     > **Risk** — Skipping may miss visual regressions. Manual verification depends on user follow-through.
   - Based on response → `TaskUpdate` visual tasks to SKIP_USER_APPROVED or MANUAL, or provide installation guidance and retry
   - The PR body should note whether visual verification was PASS, MANUAL, SKIP_USER_APPROVED, or SKIP_WARN
6. **Display findings** (finding-first pattern; fix-forward bounded by `fixForwardMaxIterations`, default 10 — safety net, not a budget; see `skills/llm-operator-principles/SKILL.md`):
   - P1 findings → must fix before PR
   - P2 findings → fix before PR (continue iterating until zero remain; finding triage is NEVER a valid escalation trigger)
   - P3 findings → fix in-PR by default. Cosmetic P3 in untouched files only: fix if bounded (<10 lines) or document inline in the PR body under `### Known cosmetic notes`. Do NOT add a "Known issues" section that defers fixable P2s.
7. **If P1 or P2 findings**: Fix them, re-run review

7a. **FlowGoal gate (v3, opt-in)** — when the Phase 1 `### FlowGoal State` section reported `GATE=block`, the active FlowGoal is not yet `achieved`. Do NOT push or create the PR with an incomplete goal — use the AskUserQuestion tool with these options:

   - **Option 1 (Recommended): Run `/flow:goal evaluate <id>` first** — produces a verdict that may transition the goal to `achieved`. If the verdict is `achieved`, return here and proceed with PR creation.
   - **Option 2: Create PR with goal not-yet-achieved** — proceed with PR creation; the PR body includes a `## FlowGoal Status` section noting the lifecycle is `<status>`. The `/flow:merge` gate will block until the goal is achieved or the user overrides. This is a Proactive-Autonomy override of the gate, so record it to the decision journal:

     ```bash
     # Self-contained: the Phase 1 !-block's vars do not persist into this
     # block's shell, so re-derive the issue from the branch and read the
     # lifecycle from the helper (same pattern as the manifest-emit block).
     ISSUE_NUM=$(git branch --show-current 2>/dev/null | grep -oE 'issue-[0-9]+' | head -1 | sed 's/issue-//')
     GOAL_LIFECYCLE=$("$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/flow-active-goal.sh" --status 2>/dev/null || echo "unknown")
     if [ -n "$ISSUE_NUM" ]; then
       "$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/journal-record.sh" \
         --issue "$ISSUE_NUM" --type escalation-resolved \
         --metadata gate=flowgoal-pr \
         --metadata goal_status="$GOAL_LIFECYCLE" \
         --metadata outcome="user-overrode: created PR with goal not yet achieved"
     fi
     ```
   - **Option 3: Cancel** — exit `/flow:pr` and finish the implementation work first.

   When `STATE=disabled` (`flow.goals.enabled` false or `goalCreation: off`): skip this step silently.

   When `STATE=none` (no active FlowGoal for this branch): the gate is **not applicable** (#111 D-GATE gates on existence). Proceed with PR creation silently — a goal-less PR is not blocked and needs no prompt. The PR body omits the `## FlowGoal Status` section.

8. **Generate PR body** from template + findings + journal + comprehension report.

   If the FlowGoal gate fired and user chose Option 2 (proceed with not-yet-achieved goal), include a `## FlowGoal Status` section at the top of the body:

   ```markdown
   ## FlowGoal Status

   - **Goal**: `<GOAL_ID>` (from `.flow/goals/<id>.goal.yaml`)
   - **Lifecycle**: `<status>` (not yet `achieved`)
   - **Evidence**: per-criterion FlowEvidence sidecars under `.flow/runs/<run-id>/evidence/`
   - **Note**: `/flow:merge` will block until this goal is `achieved` or the user explicitly overrides.
   ```

   The `<run-id>` is the active FlowRun for this branch (the `start-issue` run created by `/flow:start`). List the evidence sidecar filenames so a reviewer can trace each acceptance criterion to its captured output.
   If visual verification ran, include visual evidence section:
   ```markdown
   ## Visual Verification
   | Page | Viewport | Status | Screenshot |
   |------|----------|--------|------------|
   ```
   Note: screenshots are local files; for remote visibility, mention "verified locally"
9. **Push** (Tier 2: journal-and-proceed). First sweep any trailing decision-journal
   churn into a `chore(decisions):` commit so the working tree is clean for the PR — the
   auto-log hooks append to the tracked journal during normal work and never commit it.
   The helper no-ops if any non-journal path is dirty (it never sweeps unrelated work), and
   its `chore(decisions):` subject is skipped by `log-commits.sh` Guard 1 (no re-append):
   ```bash
   "$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/commit-journal-churn.sh" 2>/dev/null || true
   git push -u origin $BRANCH
   ```
10. **Create PR** (Tier 2):
    ```bash
    gh pr create --title "$TITLE" --body "$BODY"
    ```

    **FlowRun activity** — `/flow:pr` is the tail of the `start-issue` workflow, not a workflow of its own, so it does NOT create a new FlowRun. Instead, when `flow.runtime.enabled` is `true` and an active FlowRun exists for this branch (the `start-issue` run), invoke `Skill(run-state-management)` to append a `pr_create` FlowActivity (type `bash`, phase `verify`) recording the PR number and URL as evidence. Best-effort: if no active run is found for the branch, skip — the PR itself is the durable record.
11. **Suggest reviewers** using pr-lifecycle skill algorithm
12. **Verify**: `gh pr view --json number,url`
13. **Manifest emit** — record the review-cycle artifact for the parallel-review pass that ran during PR creation. Same emit shape as `commands/review.md` Phase 4 step 7 — the PR-creation flow runs an inline review and is morally a cycle:

    ```bash
    PR_NUMBER=$(gh pr view --json number --jq '.number')
    ISSUE=$(gh issue list --state open --search "$BRANCH" --json number --jq '.[0].number' 2>/dev/null || echo "")
    if [ -z "$ISSUE" ]; then
      ISSUE=$(echo "$BRANCH" | grep -oE 'issue-([0-9]+)' | head -1 | sed 's/issue-//')
    fi
    if [ -n "$ISSUE" ]; then
      "$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/journal-record.sh" \
        --issue $ISSUE \
        --type review-cycle \
        --metadata cycle=1 \
        --metadata path=B \
        --metadata findings_count=$TOTAL_FINDINGS \
        --metadata pr=$PR_NUMBER
    fi
    ```

    The emit is best-effort — if the issue cannot be inferred from the branch name, skip rather than fail. PR-creation flow uses Path B (single-session 5-agent dispatch); subsequent `/flow:review` invocations may re-emit with `path=A` if paired-reviewer mode is enabled.

Display PR URL and next steps.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Pre-flight checks (branch, commits, PR existence) | 1 | Autonomous; blocks on failure |
| Phase 1 FlowGoal State section (v3 opt-in) | 1 | Autonomous read; sets GATE=pass\|block sentinel |
| Multi-agent review fan-out (5 reviewers + holdout-validation) | 1 | Autonomous; Tasks tracked |
| `Skill(integration-verifier)` runtime + visual verification | 1 | Autonomous |
| File edits (fix-forward for P1/P2 findings) | 1 | Autonomous |
| Commits (`fix:` from fix-forward) | 1 | Autonomous, logged by hook |
| FlowGoal gate AskUserQuestion (Phase 4 step 7a, fires only when GATE=block) | 2 | Asks via `AskUserQuestion`; outcome (proceed/cancel) journaled |
| `git push -u origin <branch>` | 2 | Journal-and-proceed |
| `gh pr create` | 2 | Journal-and-proceed |
| Visual-verification BLOCKED escalation (when `requireVisualVerification: true`) | 2 | Asks via `AskUserQuestion`; outcome journaled |
