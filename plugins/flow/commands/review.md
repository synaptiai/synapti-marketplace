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
# Read agentTeams from plugin settings ONLY (no cascade). This is the same
# defense pattern as merge.markerTrust (PR #93): a hostile fork PR could ship
# .claude/settings.flow.local.json with agentTeams=true and the user's env
# var would be the only remaining gate. Treating agentTeams as plugin-tier-
# pinned makes cost-amplification a two-key threat (hostile setting AND env
# var) rather than a one-key threat. The env var alone (set by the user, not
# the repo) cannot enable Path A unless the plugin default also permits it.
USE_PATH_A=0
PLUGIN_SETTINGS="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "WARN: jq not installed; Path A unavailable, using Path B (single-session)" >&2
elif [ ! -f "$PLUGIN_SETTINGS" ]; then
  echo "WARN: $PLUGIN_SETTINGS not found; Path A unavailable, using Path B" >&2
else
  # Capture jq stderr/exit separately so a parse error doesn't silently fall
  # through as an empty AGENT_TEAMS into the * case branch. Merge stderr into
  # stdout for the diagnostic capture; on success jq emits only the field
  # value to stdout, on failure it emits the parse error message there.
  JQ_OUT=$(jq -r '.agentTeams // false' "$PLUGIN_SETTINGS" 2>&1)
  JQ_EXIT=$?
  if [ $JQ_EXIT -ne 0 ]; then
    JQ_ERR=$(printf '%s' "$JQ_OUT" | tr '\n' ' ' | cut -c1-200)
    echo "WARN: failed to parse $PLUGIN_SETTINGS (jq exit=$JQ_EXIT, error: $JQ_ERR); using Path B" >&2
  else
    AGENT_TEAMS="$JQ_OUT"
    case "$AGENT_TEAMS" in
      true)
        if [ -z "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" ]; then
          echo "WARN: agentTeams enabled but CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS env var unset; using single-reviewer fallback (Path B)" >&2
        else
          USE_PATH_A=1
        fi
        ;;
      false)
        echo "Path A skipped: agentTeams=false. Using Path B (single-session)."
        ;;
      "")
        # jq returned empty but exit=0 (shouldn't happen with `// false`, but
        # defensive). Distinguish from the * branch so the WARN text is
        # actionable.
        echo "WARN: agentTeams field returned empty value from $PLUGIN_SETTINGS; treating as false and using Path B" >&2
        ;;
      *)
        # Non-canonical value (e.g., string "true"/"True", "1", "yes", or a
        # multi-line object/array). Surface it rather than silently coerce —
        # a typo here means a user explicitly opted into paired review and
        # got single-session anyway. Collapse multi-line values for log
        # scrapability.
        AGENT_TEAMS_DISPLAY=$(printf '%s' "$AGENT_TEAMS" | tr '\n' ' ' | cut -c1-80)
        echo "WARN: agentTeams=$AGENT_TEAMS_DISPLAY is not the JSON boolean true/false; treating as false. Use \"agentTeams\": true (no quotes)." >&2
        ;;
    esac
  fi
fi
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

**Note on holdout-validation challenge participation**: the two `Skill(holdout-validation)` invocations contribute findings to A.2 auto-consensus matching but **do NOT participate in the A.3 challenge round** — there is no defined Skill-as-challenger prompt pattern (Skills don't accept the structured `[challenge mode]` invocation that Agents do). Holdout-validation findings that match between lenses get `consensus`; non-matching findings carry `unchallenged` confidence MEDIUM by default. This is why the cost table in `team-coordination/SKILL.md` lists 10 challenge calls rather than 12 — the holdout-validation pair is excluded from Phase 3.

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

#### A.5 — Per-facet fallback application

If any of A.1's variants failed (timeout, error, did-not-spawn), apply the fallback semantics from `team-coordination/SKILL.md` per facet — never block the review:

| Failure | Action |
|---------|--------|
| One variant failed for facet F | Use the responding variant's findings only; mark each as `unchallenged` (MEDIUM). Note in output: `facet F: single-reviewer fallback (skeptic failed)`. |
| Both variants failed for facet F | Re-dispatch single Agent for that facet using the Path B prompt. Note in output: `facet F: re-dispatched as single-reviewer (both variants failed)`. |
| Challenge round failed for a facet | Skip A.3 for that facet; keep A.1 findings as `unchallenged`. Note in output: `facet F: challenge skipped (challenge prompt failed)`. |
| A.2 auto-consensus matching errored on finding F (e.g., malformed `file:line`) | Skip auto-consensus for F; route F through A.3 challenge as if non-consensus. Log `LEDGER_WARN: PR#{N} A.2 skipped F:<id> due to <reason>` to stderr. |
| A.4 consolidation lookup missing for finding F (e.g., orphaned challenge response) | Emit F as `unchallenged` MEDIUM. Append to `.decisions/issue-{N}.md` (where N = the issue this PR addresses) under a `## Consolidation gaps (PR #$ARGUMENTS, cycle {N})` heading with the orphan reason. Create the journal file with frontmatter if it does not exist. |

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

8. **Verify posting**: TaskList — confirm "Post review comment" or "Post self-review comment" task is completed. Do NOT proceed to step 9 until this is verified.

9. **Post-review**: If self-review fixed everything, suggest `/flow:pr`. If external review, suggest `/flow:address $ARGUMENTS` for the PR author.
