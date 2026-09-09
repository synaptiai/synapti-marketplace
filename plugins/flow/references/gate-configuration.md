# Gate Configuration

Configuration reference for flow's safety gates and tier settings.

## Settings File Locations

Settings cascade — highest precedence first; first non-empty value wins:

1. `.claude/settings.flow.local.json` — project-local; gitignored (your machine-local pin for this repo)
2. `.claude/settings.flow.json` — project-shared; committed (team defaults)
3. `~/.claude/settings.flow.json` — user-global; cross-project default
4. `${CLAUDE_PLUGIN_ROOT}/settings.json` — plugin default; bundled with flow

See [Settings Cascade](#settings-cascade) below for the full precedence rules and worked examples.

## Tier Settings

```json
{
  "tiers": {
    "push": "journal",
    "prCreate": "journal",
    "issueAssign": "journal",
    "issueCreate": "journal",
    "merge": "confirm",
    "release": "confirm"
  }
}
```

### Values

| Value | Behavior |
|-------|----------|
| `autonomous` | Execute without any user interaction |
| `journal` | Execute and log to decision journal |
| `confirm` | Require explicit human confirmation via AskUserQuestion |

### Actions

| Key | Default | Action |
|-----|---------|--------|
| `push` | journal | `git push` to remote |
| `prCreate` | journal | `gh pr create` |
| `issueAssign` | journal | `gh issue edit --add-assignee` |
| `issueCreate` | journal | `gh issue create` |
| `merge` | confirm | `gh pr merge` |
| `release` | confirm | `gh release create` |

## Timeout Settings

```json
{
  "timeouts": {
    "devServerStartup": 30,
    "e2eTest": 120,
    "qualityCheckMaxIterations": 3,
    "teammateTimeout": 300
  }
}
```

| Key | Default | Unit | Purpose |
|-----|---------|------|---------|
| `devServerStartup` | 30 | seconds | Max wait for dev server |
| `e2eTest` | 120 | seconds | Max E2E test suite time |
| `qualityCheckMaxIterations` | 3 | count | Max fix-and-retry loops |
| `teammateTimeout` | 300 | seconds | Max teammate idle time |

## Convention Settings

```json
{
  "conventions": {
    "commitTypes": ["feat", "fix", "docs", "..."],
    "branchPatterns": {
      "feature": "feature/issue-{N}-{desc}",
      "fix": "fix/issue-{N}-{desc}"
    }
  }
}
```

## Journal Settings

```json
{
  "journal": {
    "dir": ".decisions"
  }
}
```

## Learning Settings

```json
{
  "learning": {
    "enabled": true,
    "proposalDir": "~/.claude/flow-proposals"
  }
}
```

## Quality Gates

Flow enforces ten quality gates across the workflow lifecycle. Gates are structural -- they block progression until satisfied.

### 1. Spec Validation Gate (EXPLORE phase)

Validates that every acceptance criterion has a concrete, automated verification command before the workflow transitions to PLAN. Rejects vague criteria (e.g., "works correctly") and requires specification of non-goals, failure modes, and interface contracts.

**Blocks:** EXPLORE -> PLAN transition
**Override:** None. Fix the spec.

### 2. Stranger Test Gate (end of PLAN)

Ensures the plan is executable by someone with zero prior context. Every task must have explicit inputs, expected outputs, and verification steps. Implicit assumptions, undefined references, and "you know what I mean" instructions fail the gate.

**Blocks:** PLAN -> CODE transition
**Override:** None. Rewrite until zero-context executable.

### 3. Per-Task Verification Gate (CODE phase)

Tests must pass and evidence must be captured before `TaskUpdate(completed)` is accepted. When `tddMode: "enforce"`, tests must exist before the implementation is written.

**Blocks:** Individual task completion
**Override:** Set `testing.tddMode: "suggest"` and `testing.tddModeOptOut: true`

### 4. Runtime Verification Whitelist (VERIFY phase)

Runtime verification (dev server startup, API smoke tests, E2E tests, browser checks) is mandatory for every change. The only permitted skips are three enumerated categories: `markdown-only`, `config-only`, and `dependency-bump-only`. Any skip outside this whitelist requires a Proactive-Autonomy escalation. Diagnostics from LSP servers are treated as quality signals (errors -> P1, warnings -> P2) when `lsp.diagnosticsAsQuality` is true.

**Blocks:** VERIFY phase completion
**Configuration:** `lsp.diagnosticsAsQuality`. Skip categories are enumerated in `runtime-verification/SKILL.md` (not user-configurable).

### 5. Evidence Completeness (VERIFY phase)

Every criterion's evidence bundle must include five completeness subsections: "What was NOT tested," "Known limitations," "Negative/adversarial cases," "Test inputs and expected values" (with the source of each expected value), and "Risk map coverage." The verdict-judge FAILs any criterion whose evidence is missing these subsections, whose expected values are self-referential (copied from the implementation), or whose risk-map rows have no discriminating test. A `ui` criterion must additionally carry `### Visual analysis` (one `Viewport:` / `Screenshot:` / `Result:` / `Observed:` block per configured viewport copied from the visual-verification result); the verdict-judge has no file tools and judges the `Observed:` sentences, never the image.

**Blocks:** PASS verdict on the affected criterion (judge-side, not pre-submission)
**Override:** None. Add the missing subsections.

### 6. Missing-Criterion Scan (verdict-judge)

Step 1 of verdict evaluation checks that every acceptance criterion from the issue has a corresponding evidence entry. Criteria without evidence are flagged as `FAIL` before any evaluation begins. `verdict.requireAllPass: true` means a single missing criterion blocks the verdict.

**Blocks:** Verdict evaluation
**Override:** Set `verdict.requireAllPass: false` (all criteria still evaluated, but missing ones do not block)

### 7. Holdout Validation (VERIFY + review + address phases)

Cross-references agent self-review claims against actual file state. Runs inline during verification, code review, and feedback resolution. Detects claims that are not grounded in the codebase (e.g., "all edge cases handled" when error paths are uncovered).

**Blocks:** Self-review acceptance
**Override:** None. Fix the claims or fix the code.

### 8. Finding-Ledger Merge Gate (merge)

Scans for `FLOW_RESOLUTION_CYCLE` markers in the codebase. Blocks merge when the markers contain unresolved or escalated items. Previously used "DEFERRED" status; now uses "ESCALATED" to signal that deferral without structured escalation is not permitted.

**Blocks:** `gh pr merge` / `/flow:merge`
**Override:** Resolve all findings or complete Proactive Autonomy escalation for each.

**Marker trust filter:** Both `/flow:merge` and `/flow:status` filter markers by GitHub `author_association` before honoring them — see the Trust Boundary section of [`finding-ledger-parser.md`](finding-ledger-parser.md) for the threat model.

| Setting | Default | Notes |
|---------|---------|-------|
| `merge.markerTrust.allowedAssociations` | `["OWNER","MEMBER","COLLABORATOR"]` | Read from the standard cascade (see "Settings Cascade" below). Used by `commands/merge.md` and `commands/status.md` to filter forgeable `FLOW_REVIEW_CYCLE` / `FLOW_RESOLUTION_CYCLE` markers by GitHub `author_association`. |

### 9. Task-Completion Quality Ledger (every session)

`hooks/scripts/verify-task-completion.sh` (TaskCompleted) refuses to mark a task complete while the working tree changed in this session after the last PASSING quality-command run. The per-session ledger under `${FLOW_STATE_DIR:-~/.claude/flow-state}/sessions/<session_id>/quality-ledger.jsonl` is written by `log-file-changes.sh` (PostToolUse `Edit|Write|NotebookEdit`) and `record-quality-run.sh` (PostToolUse **and** PostToolUseFailure `Bash`: test/lint/typecheck/build commands matched at command position only, with their exit code, a `masked` flag for `|| true`, a `failed` flag for the failure event, and a sha256 digest of the git working tree). A run passes only when it exited 0, unmasked, and did not fail. The digest is a git tree id of the working tree contents (HEAD excluded), recomputed by the gate, so edits made through Bash (`sed -i`, heredocs, `git apply`) and checkouts after the last passing run block too, while committing the edits that run already tested does not. Journal, `.flow/`, and `.screenshots/` writes never dirty the gate (they are excluded from the digest as well). `session-end-state.sh` prunes session ledgers idle for 14 days once per day. This is the one gate that runs with or without a FlowGoal.

**Blocks:** `TaskUpdate(completed)` (exit 2, the changed paths named on stderr)
**Configuration:** `testing.taskCompletionGate` = `block` (default) / `warn` / `off`; `testing.qualityCommandPatterns` adds project-specific ERE patterns.

### 10. Issue-Create Ask Gate (active FlowGoal)

`hooks/scripts/ask-issue-create.sh` (PreToolUse, Bash) turns `gh issue create` into a permission prompt while a FlowGoal is active, naming the goal and the operator rule (findings are fixed in this PR, not filed as follow-ups). Approve for a genuine product decision or work outside the goal's scope; deny and fix it here otherwise.

**Blocks:** nothing on its own; it asks. Never fires when `minimalScope: true` or when no goal is active.
**Override:** `minimalScope: true`.

### Stop hook posture (FlowGoal evidence)

`hooks/scripts/flow-goal-stop.sh` ships in `warn` mode and says so: the reason starts with `FLOW_GOAL_INCOMPLETE — stop ALLOWED (stopHookEnforcement=warn)` and is echoed to stderr. `block` is opt-in (`flow.goals.stopHookEnforcement: block`). In block mode, verification commands execute only for goals recorded in the user-local trust ledger (`bin/flow-goal-trust.sh`, written automatically when flow creates the goal) or when `flow.goals.executeVerificationCommands` is true; consecutive blocks are capped by `flow.goals.failAfterStuckTurns`. See [`stop-hook-goal-enforcement.md`](stop-hook-goal-enforcement.md).

### Settings Cascade

Flow follows the standard Claude Code settings precedence (highest first):

1. `.claude/settings.flow.local.json` — project-local; gitignored. Personal pins for this project that should not be shared with the team.
2. `.claude/settings.flow.json` — project-shared; committed. Team-wide defaults.
3. `$HOME/.claude/settings.flow.json` — user-global; cross-project defaults across all repositories.
4. `${CLAUDE_PLUGIN_ROOT}/settings.json` — plugin default; bundled with the plugin.

**First non-empty value wins.** A user setting `agentTeams: true` in `.claude/settings.flow.local.json` overrides the same key in `.claude/settings.flow.json`, which overrides `$HOME/.claude/settings.flow.json`, which overrides the plugin default.

The cascade applies uniformly to every flow setting — there is no special-cased exclusion for security-sensitive keys. The threat model relies on Claude Code's standard review surface: changes to `.claude/settings.flow.json` appear in the PR diff like any other repo file, and reviewers can spot a permissive `merge.markerTrust.allowedAssociations` or a flipped `agentTeams: true` in normal review.

#### Persistent personal opt-in

To enable a setting just for yourself (not committed to the team's project file), write it to either:

- `.claude/settings.flow.local.json` — applies only to this repository, gitignored
- `$HOME/.claude/settings.flow.json` — applies across all your projects

Example: enabling Path A paired-reviewer mode for yourself in this project only:

```json
// .claude/settings.flow.local.json (gitignored)
{
  "agentTeams": true
}
```

(Note: `agentTeams: true` also requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` set in your shell environment — the env var is the user-side opt-in for the experimental feature.)

**Path A review model (`agentTeamModel`).** Path A dispatches ~20 review agents (paired skeptic/verifier × 5 facets + a challenge round), all of which would otherwise inherit the session model. To avoid running an Opus session's rate across that fan-out, the model is configurable via the top-level `agentTeamModel` key (enum `haiku|sonnet|opus|inherit`, default `sonnet`), resolved through this same cascade. An invalid value is rejected with a WARN and falls back to `sonnet`. Use `inherit` to reproduce the pre-configuration behavior. This is scoped to Path A only — Path B (single-session) agents always inherit the session model.

```json
// .claude/settings.flow.local.json (gitignored) — pin a higher model for a hard review
{
  "agentTeams": true,
  "agentTeamModel": "opus"
}
```

#### Team-wide opt-in

To enable a setting for the whole team via the committed project-shared file:

```json
// .claude/settings.flow.json (committed)
{
  "agentTeams": true,
  "merge": {
    "markerTrust": {
      "allowedAssociations": ["OWNER", "MEMBER", "COLLABORATOR", "CONTRIBUTOR"]
    }
  }
}
```

Reviewers will see the change in the PR diff. Anyone can override with their own `.claude/settings.flow.local.json` or `$HOME` setting if they don't want the team-wide value.

## Gate Summary

| # | Gate | Phase | Blocks |
|---|------|-------|--------|
| 1 | Spec Validation | EXPLORE | PLAN transition |
| 2 | Stranger Test | PLAN | CODE transition |
| 3 | Per-Task Verification | CODE | Task completion |
| 4 | Runtime Verification | VERIFY | Phase completion |
| 5 | Evidence Completeness | VERIFY | PASS verdict (judge-side) |
| 6 | Missing-Criterion Scan | Verdict | Verdict evaluation |
| 7 | Holdout Validation | VERIFY/review/address | Self-review acceptance |
| 8 | Finding-Ledger Merge | Merge | PR merge |
| 9 | Task-Completion Quality Ledger | Every session | Task completion |
| 10 | Issue-Create Ask Gate | Active goal | Asks before `gh issue create` |

## Hook Override

Hooks cannot be disabled via settings — they are structural safety mechanisms. To modify hook behavior, edit the hook scripts directly in `plugins/flow/hooks/scripts/`.
