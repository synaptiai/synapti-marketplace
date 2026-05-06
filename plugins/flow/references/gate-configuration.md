# Gate Configuration

Configuration reference for flow's safety gates and tier settings.

## Settings File Locations

Settings cascade in priority order; later layers override earlier ones:

1. `plugins/flow/settings.json` — plugin defaults
2. `~/.claude/settings.flow.json` — user defaults
3. `.claude/settings.flow.json` — project settings (committed)
4. `.claude/settings.flow.local.json` — local overrides (gitignored, highest priority)

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

Runtime verification (dev server startup, API smoke tests, E2E tests, browser checks) is mandatory for every change. The only permitted skips are three enumerated categories: `markdown-only`, `config-only`, and `dependency-bump-only`. Any skip outside this whitelist requires a Proactive-Autonomy escalation. Diagnostics from LSP servers are treated as quality signals (errors -> P1, warnings -> P2) when `lsp.diagnosticsAsQuality` is true.

**Blocks:** VERIFY phase completion
**Configuration:** `lsp.diagnosticsAsQuality`. Skip categories are enumerated in `runtime-verification/SKILL.md` (not user-configurable).

### 5. Evidence Completeness (VERIFY phase)

Every criterion's evidence bundle must include three completeness subsections: "What was NOT tested," "Known limitations," and "Negative/adversarial cases." The verdict-judge FAILs any criterion whose evidence is missing these subsections.

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
| `merge.markerTrust.allowedAssociations` | `["OWNER","MEMBER","COLLABORATOR"]` | **Read from `plugins/flow/settings.json` ONLY** — does NOT use the cascade above (security pin: a hostile fork PR could otherwise commit `.claude/settings.flow.local.json` with a permissive trust list and disable the forgery defense after `gh pr checkout`). |

### Trimmed-Cascade Settings Keys

The following keys read from `$HOME/.claude/settings.flow.json` and `${CLAUDE_PLUGIN_ROOT}/settings.json` ONLY — they intentionally exclude the repo-local sources `.claude/settings.flow.json` and `.claude/settings.flow.local.json`. Same threat model as `merge.markerTrust`: after `gh pr checkout` of a hostile fork those files are attacker-controlled, so a permissive override could redirect hook writes, relax commit-type validation, or repoint the proposal directory.

| Setting | Consumers | Threat if cascaded from repo-local |
|---------|-----------|------------------------------------|
| `journal.dir` | `bin/journal-record.sh`, `hooks/scripts/{session-end-learn,log-commits,log-file-changes}.sh`, `commands/{learn,explain,status}.md` | Redirects every journal/hook write to an attacker-controlled path (e.g., `/tmp/attacker`, or a path-traversal target). |
| `learning.proposalDir` | `commands/learn.md` | Redirects `/flow:learn` proposals into an attacker-controlled directory; subsequent `bin/promote-proposal.sh` runs would then promote the attacker's content as a "learned skill." |
| `conventions.commitTypes` | `agents/convention-checker.md` | Relaxes the allowed-commit-types list (e.g., to `.*`), defeating commit-message validation in PR review. |

If you need to override one of these for local development, set it in `$HOME/.claude/settings.flow.json` (your user-global file) — that source is honored by all consumers above.

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

## Hook Override

Hooks cannot be disabled via settings — they are structural safety mechanisms. To modify hook behavior, edit the hook scripts directly in `plugins/flow/hooks/scripts/`.
