---
description: "Review a pull request with multi-faceted analysis. Supports both single-session parallel review and agent team adversarial review."
argument-hint: <pr-number>
allowed-tools: Bash, Read, Write, Edit, Agent, AskUserQuestion, TaskCreate, TaskList, TaskUpdate, Skill, Grep, Glob
---

<!--
PARALLEL EXECUTION RULE:
Execute independent operations simultaneously.
-->

# Review PR #$ARGUMENTS

Multi-faceted code review with parallel analysis. Follows Explore > Plan > Code > Verify loop.

## Required Skills

- `code-review-methodology` — 6-facet review, finding synthesis, adversarial protocol
- `holdout-validation` — cross-reference self-review claims against file state (Phase 3)

## Phase 1: EXPLORE

**Parallel operations:**

```bash
# 1. PR details
gh pr view $ARGUMENTS --json title,body,headRefName,baseRefName,changedFiles,additions,deletions,labels,author,reviews

# 2. Linked issue
gh pr view $ARGUMENTS --json body --jq '.body' | grep -oE '#[0-9]+' | head -1 | tr -d '#'

# 3. Previous reviews (follow-up detection)
gh pr view $ARGUMENTS --json reviews --jq '.reviews[] | "\(.state) by \(.author.login)"'

# 4. Checkout PR branch
gh pr checkout $ARGUMENTS

# 5. Diff
gh pr diff $ARGUMENTS --name-only
```

**Agent(Explore)**: "Read the changed files in this PR and understand the context. What modules are affected? What patterns are being followed or changed?"

Check for previous reviews — if this is a follow-up review, focus on changes since last review.

**Parse structured findings from previous review/resolution cycles** (follow-up reviews only):

```bash
# Parse previous review findings (from review bodies)
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
gh api repos/$REPO/pulls/$ARGUMENTS/reviews --jq '
  [.[] | select(.body | test("FLOW_REVIEW_CYCLE")) | {
    cycle: (.body | capture("FLOW_REVIEW_CYCLE:(?<n>[0-9]+)") | .n),
    findings: (.body | capture("FINDINGS:\\[(?<f>[^\\]]+)\\]") | .f)
  }]'

# Parse previous resolution outcomes (from issue comments posted via gh pr comment)
gh api repos/$REPO/issues/$ARGUMENTS/comments --jq '
  [.[] | select(.body | test("FLOW_RESOLUTION_CYCLE")) | {
    cycle: (.body | capture("FLOW_RESOLUTION_CYCLE:(?<n>[0-9]+)") | .n),
    resolved: (.body | capture("RESOLVED:\\[(?<r>[^\\]]*?)\\]") | .r),
    escalated: (.body | capture("ESCALATED:\\[(?<e>[^\\]]*?)\\]") | .e)
  }]'
```

If previous cycles exist, build a **Previous Feedback Status** table and cross-reference each finding's location against `git diff` to verify resolution.

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

**Path A gate check** (mandatory before paired dispatch — runs before A.1):

```bash
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
PLUGIN_SETTINGS="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json"
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
    JQ_OUT=$(jq -c 'if has("agentTeams") then .agentTeams else empty end' "$SETTINGS_PATH" 2>&1)
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
    # Three-state diagnostic — distinguish (a) plugin not installed,
    # (b) CLAUDE_PLUGIN_ROOT pointed at a path that does not exist,
    # (c) all four files (local, project, user, plugin) exist but no agentTeams
    # key, so the user can take the right next step without re-running with
    # debug instrumentation.
    ANY_USER_FILE_EXISTS=0
    [ -f "$LOCAL_SETTINGS" ] && ANY_USER_FILE_EXISTS=1
    [ -f "$PROJECT_SETTINGS" ] && ANY_USER_FILE_EXISTS=1
    [ -f "$USER_SETTINGS" ] && ANY_USER_FILE_EXISTS=1
    if [ $ANY_USER_FILE_EXISTS -eq 0 ] && [ ! -f "$PLUGIN_SETTINGS" ]; then
      if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
        echo "WARN: agentTeams not set in any cascade source. CLAUDE_PLUGIN_ROOT is unset and $PLUGIN_SETTINGS does not exist — flow plugin may not be installed in this CWD. Add \"agentTeams\": true to $USER_SETTINGS, $PROJECT_SETTINGS, or $LOCAL_SETTINGS to enable Path A; using Path B." >&2
      else
        echo "WARN: agentTeams not set in any cascade source. CLAUDE_PLUGIN_ROOT=$CLAUDE_PLUGIN_ROOT but $PLUGIN_SETTINGS does not exist — plugin install may be corrupted or env var pointing wrong place. Add \"agentTeams\": true to $USER_SETTINGS, $PROJECT_SETTINGS, or $LOCAL_SETTINGS to enable Path A; using Path B." >&2
      fi
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
```

If `USE_PATH_A=0`, skip the rest of Path A and dispatch Path B below.

#### A.1 — Independent Analysis (paired reviewers, parallel dispatch)

Dispatch **12 invocations** (10 `Agent(...)` + 2 `Skill(holdout-validation)`) in a single parallel block — 5 agent facets × {skeptic, verifier} plus the holdout-validation skill in both lenses. Each variant carries an orthogonal lens; both run with no awareness of each other.

```
Agent(security-reviewer-skeptic):
  "You are reviewing PR #$ARGUMENTS as the SKEPTIC variant. Assume the diff is
   broken until proven otherwise. Flag every security behavior you cannot prove
   correct from the code as written: OWASP Top 10, secrets, auth/authz, input
   validation, dependency vulnerabilities. Return P1/P2/P3 findings with
   file:line citations and category. Do NOT include challenge information —
   another reviewer will challenge your findings later."

Agent(security-reviewer-verifier):
  "You are reviewing PR #$ARGUMENTS as the VERIFIER variant. Assume the diff is
   correct as a baseline. Look only for missed security edge cases, undocumented
   contract assumptions, or invariants that aren't enforced. Return P1/P2/P3
   findings with file:line citations and category."

Agent(code-reviewer-skeptic):
  "PR #$ARGUMENTS as SKEPTIC. Assume broken; flag logic/quality/edge-case
   issues you cannot prove correct. P1/P2/P3 + file:line + category."

Agent(code-reviewer-verifier):
  "PR #$ARGUMENTS as VERIFIER. Assume correct; look only for missed edge cases
   and unenforced invariants. P1/P2/P3 + file:line + category."

Agent(convention-checker-skeptic):
  "PR #$ARGUMENTS as SKEPTIC. Flag every convention violation (commits, branch
   naming, code patterns) you cannot prove conformant. P1/P2/P3 + file:line."

Agent(convention-checker-verifier):
  "PR #$ARGUMENTS as VERIFIER. Look for convention drift the skeptic might miss
   (e.g., subtle stylistic divergence). P1/P2/P3 + file:line."

Agent(test-runner-skeptic):
  "PR #$ARGUMENTS as SKEPTIC. Run quality commands (lint, test, typecheck) and
   flag every failure or warning. Return findings with command output."

Agent(test-runner-verifier):
  "PR #$ARGUMENTS as VERIFIER. Run quality commands and flag missing test
   coverage or weak assertions in passing tests. Return findings."

Agent(error-handler-inspector-skeptic):
  "PR #$ARGUMENTS as SKEPTIC. Flag every error-handling gap, silent failure,
   or unhandled exception you cannot prove handled. P1/P2/P3 + file:line."

Agent(error-handler-inspector-verifier):
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

For findings NOT in auto-consensus, dispatch each variant to challenge the OTHER variant's findings. **Variants do NOT re-read the diff.** Up to 10 challenge prompts run in parallel (5 agent facets × 2 directions; holdout-validation excluded — see A.1 note).

```
Agent(security-reviewer-skeptic) [challenge mode]:
  "You are reviewer-A (skeptic) for facet 'security'. Reviewer-B (verifier)
   raised the following findings on the same diff you reviewed independently.
   For each finding, respond with exactly one line:

     {finding-id} AGREE
     {finding-id} DISAGREE: {one-line reason}
     {finding-id} REFINE: priority={P1|P2|P3} category={text}

   Do NOT re-read the diff. Decide based on your prior independent analysis only.

   Findings to challenge:
   {list of verifier's non-auto-consensus findings: ID, file:line, priority, category}"

Agent(security-reviewer-verifier) [challenge mode]:
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

**DROPPED findings** are logged to `.decisions/issue-{N}.md` (where N = the issue this PR addresses) under a `## Dropped after challenge (PR #$ARGUMENTS, cycle {N})` heading with the finding details and both DISAGREE reasons. They never appear in the rendered tables or the FLOW_REVIEW_CYCLE marker.

**Manifest emit** — for each DROPPED finding, append a `dropped-finding` artifact to the journal manifest so `/flow:learn` can detect repeated drop reasons across cycles (a recurring drop reason is a learnable signal):

```bash
"${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/journal-record.sh" \
  --issue $ISSUE \
  --type dropped-finding \
  --metadata cycle=$CYCLE \
  --metadata finding_id=$FINDING_ID \
  --metadata facet=$FACET \
  --metadata reason="$REASON" \
  --metadata pr=$ARGUMENTS
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
| A.4 consolidation lookup missing for finding F (e.g., orphaned challenge response) | Emit F as `unchallenged` MEDIUM. Append to `.decisions/issue-{N}.md` (where N = the issue this PR addresses) under a `## Consolidation gaps (PR #$ARGUMENTS, cycle {N})` heading with the orphan reason. Create the journal file with frontmatter if it does not exist. **Also emit `--type consolidation-gap`** via `bin/journal-record.sh` with `cycle`, `finding_id`, `reason`, and `pr` metadata so the manifest carries a machine-readable trail of fallback fires. |

#### A.6 — Emit consolidated output

Use the synthesized findings (with confidence + disposition) for steps in Phase 4 below. The FLOW_REVIEW_CYCLE marker emitted in Phase 4 step 7 uses the 7-field form when paired-reviewer mode produced the findings (example exercises three disposition values):

```
<!-- FLOW_REVIEW_CYCLE:{N} FINDINGS:[F1|P1|security|src/auth.ts:42|open|HIGH|consensus,F2|P2|correctness|src/api.ts:88|open|MEDIUM|refined,F3|P1|race|src/job.ts:17|open|LOW|kept] -->
```

When Path A is the orchestrator, the marker is **uniformly 7-field** — including for findings produced by per-facet fallbacks (which carry `MEDIUM|unchallenged`). The 5-field form is preserved ONLY for full Path B runs (gate failed at the top of this section). Mixing 5-field and 7-field rows within a single marker is forbidden — pad fallback findings to 7 fields with `MEDIUM|unchallenged` so all rows match. This rule is restated at Phase 4 step 7.

After A.6 completes, jump to Phase 4 with the consolidated finding set.

### Path B: Single Session (default)

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

## Phase 4: VERIFY

**CRITICAL: Posting review findings to the PR is MANDATORY. NEVER skip posting. The review is not complete until `gh pr review` has been executed and TaskUpdate confirms the post task is completed. Do not suggest next steps until posting is verified.**

1. **TaskList**: Confirm all review facets complete
2. **Synthesize findings**: Deduplicate by file:line, prioritize P1/P2/P3
3. **Display findings** (finding-first pattern):

```markdown
## Review Summary for PR #$ARGUMENTS

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
   PR_AUTHOR=$(gh pr view $ARGUMENTS --json author --jq '.author.login')
   CURRENT_USER=$(gh api user --jq '.login')
   ```

5. **Self-review (own PR — PR_AUTHOR == CURRENT_USER)**:

   Fix-forward approach (max `fixForwardMaxIterations`, default 2):
   - P1 findings → fix immediately
   - P2 findings → fix immediately
   - P3 findings → fix immediately (the proximity test is not a deferral mechanism — P3 in touched files gets the same disposition as P1/P2)
   - TaskCreate("Test coverage for fix-forward", "Write or update tests for each P1/P2/P3 fix applied during self-review")
   - For each fix: write or update a test that covers the fixed behavior
   - After fixes: run targeted re-review of only changed files
   - TaskUpdate(testCoverageTaskId, status: "completed", result: "Tests written/updated for {N} fixes")
   - No follow-up issue creation for fixable items — just fix them
   - If any P1/P2 finding cannot be fixed in-PR, file a six-field Proactive-Autonomy escalation (Situation / Tried / Options / Recommendation / Time sensitivity / Risk) rather than deferring silently
   - TaskCreate("Post self-review comment", "Post review findings summary to PR via gh pr review --comment")

6. **External review (someone else's PR — PR_AUTHOR != CURRENT_USER)**:

   - TaskCreate("Post review comment", "Post structured review findings to PR via gh pr review")
   - P1/P2/P3 in already-touched files → REQUEST_CHANGES (P1/P2) or COMMENT with fix-expected language (P3) — the author must fix or file an escalation
   - Cosmetic P3 in untouched files → follow-up issue workflow
   - P1/P2 in untouched files → REQUEST_CHANGES; author must address in-PR or file a six-field Proactive-Autonomy escalation

   Findings in files the PR already modifies are NEVER out-of-scope — the author owns the known defects in any file they touch. Do NOT flag them as informational; flag them as blocking.

   For cosmetic P3 findings in untouched files that warrant follow-up:
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
   - Self-review → `gh pr review $ARGUMENTS --comment --body "$BODY"`
   - External + P1 findings → `gh pr review $ARGUMENTS --request-changes --body "$BODY"`
   - External + P2 findings (no P1) → `gh pr review $ARGUMENTS --request-changes --body "$BODY"`
   - External + P3 only → `gh pr review $ARGUMENTS --comment --body "$BODY"` (fix-expected, not approve-with-nits)
   - External + No findings → `gh pr review $ARGUMENTS --approve --body "$BODY"`

   TaskUpdate(postCommentTaskId, status: "completed", result: "PASS — review posted as {approve/request-changes/comment}")

   **Manifest emit** — record the review-cycle artifact in the issue's journal manifest. Use the issue number associated with this PR (parse from PR body: `gh pr view $ARGUMENTS --json body --jq '.body' | grep -oE '#[0-9]+' | head -1 | tr -d '#'`):

   ```bash
   ISSUE=$(gh pr view $ARGUMENTS --json body --jq '.body' | grep -oE '#[0-9]+' | head -1 | tr -d '#')
   if [ -n "$ISSUE" ]; then
     "${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/journal-record.sh" \
       --issue $ISSUE \
       --type review-cycle \
       --metadata cycle=$CYCLE_NUMBER \
       --metadata path={A|B} \
       --metadata findings_count=$TOTAL \
       --metadata pr=$ARGUMENTS
   fi
   ```

   The `path` value is `A` when paired-reviewer mode produced the findings (7-field marker), `B` when Path B (5-field marker) produced them. `findings_count` is the total across P1+P2+P3 in the cycle. If the PR body does not link an issue, skip the emit (the marker on the PR comment is sufficient for that PR's own state; the manifest is keyed by issue, not PR).

8. **Verify posting**: TaskList — confirm "Post review comment" or "Post self-review comment" task is completed. Do NOT proceed to step 9 until this is verified.

9. **Post-review**: If self-review fixed everything, suggest `/flow:pr`. If external review, suggest `/flow:address $ARGUMENTS` for the PR author.

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
