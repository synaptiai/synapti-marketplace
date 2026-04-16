# Gate Configuration

Configuration reference for flow's safety gates and tier settings.

## Settings File Locations

Settings are read in cascading order (first found wins):

1. `.claude/settings.flow.local.json` — local overrides (gitignored)
2. `.claude/settings.flow.json` — project settings (committed)
3. `~/.claude/settings.flow.json` — user defaults
4. `plugins/flow/settings.json` — plugin defaults

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
    "dir": ".decisions",
    "sensitivityDefault": "public"
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

Flow enforces eight quality gates across the workflow lifecycle. Gates are structural -- they block progression until satisfied.

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

Executes dev server startup, API smoke tests, E2E tests, and browser checks. Only whitelisted commands are allowed to run. Diagnostics from LSP servers are treated as quality signals (errors -> P1, warnings -> P2).

**Blocks:** VERIFY phase completion
**Configuration:** `verification.whitelist` in settings, `lsp.diagnosticsAsQuality`

### 5. Evidence Completeness (VERIFY phase)

Every criterion's evidence bundle must include three completeness subsections: "What was NOT tested," "Known limitations," and "Negative/adversarial cases." Missing subsections block the evidence bundle from being submitted to the verdict judge.

**Blocks:** Evidence bundle submission
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

## Gate Summary

| # | Gate | Phase | Blocks |
|---|------|-------|--------|
| 1 | Spec Validation | EXPLORE | PLAN transition |
| 2 | Stranger Test | PLAN | CODE transition |
| 3 | Per-Task Verification | CODE | Task completion |
| 4 | Runtime Verification | VERIFY | Phase completion |
| 5 | Evidence Completeness | VERIFY | Evidence submission |
| 6 | Missing-Criterion Scan | Verdict | Verdict evaluation |
| 7 | Holdout Validation | VERIFY/review/address | Self-review acceptance |
| 8 | Finding-Ledger Merge | Merge | PR merge |

## Hook Override

Hooks cannot be disabled via settings — they are structural safety mechanisms. To modify hook behavior, edit the hook scripts directly in `plugins/flow/hooks/scripts/`.
