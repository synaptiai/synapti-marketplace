# Gate Configuration

Reference for configuring comprehension layer gates and other settings.

## Overview

Gates are configurable pauses at high-stakes decisions during AI-driven workflow execution. They give humans the opportunity to review and approve decisions before the workflow proceeds.

## Configuration Format

Configuration lives in dedicated JSON settings files, validated against `schema.json`. See `references/config-reading.md` for file locations and reading patterns.

Example `.claude/settings.gh-workflow.json`:

```json
{
  "$schema": "https://raw.githubusercontent.com/synaptiai/synapti-marketplace/main/plugins/gh-workflow/schema.json",
  "gates": {
    "newDependencies": "on",
    "securityChanges": "on",
    "schemaChanges": "on",
    "apiSurfaceChanges": "on",
    "scopeDeviations": "on",
    "ambiguousRequirements": "on"
  }
}
```

## Gate Settings

Each gate accepts one of three values:

| Value | Behavior | Use When |
|-------|----------|----------|
| `on` | Pause workflow, present AskUserQuestion to human | Interactive development (default) |
| `log` | Record decision in journal, continue without pausing | CI/automated pipelines, trusted workflows |
| `off` | Skip entirely, no record | Feature not relevant to this project |

**Default**: All gates `on` if no configuration is found.

## Gate Categories

### gates.newDependencies

**Triggers when:** New entries appear in dependency files.

**Detection:**
- `package.json` — new entries in `dependencies` or `devDependencies`
- `requirements.txt` / `pyproject.toml` — new package entries
- `Gemfile` — new gem entries
- `go.mod` — new module requirements
- `Cargo.toml` — new crate dependencies
- `.gitmodules` — new git submodules

### gates.securityChanges

**Triggers when:** Changes touch security-related files or patterns.

**Detection (filename-based):**
- Files matching: `*auth*`, `*security*`, `*permission*`, `*token*`, `*secret*`, `*crypto*`, `*session*`
- Changes to: `.env*`, CORS configuration, TLS configuration

### gates.schemaChanges

**Triggers when:** Data model or schema definitions change.

**Detection:**
- Database migration files (e.g., `db/migrate/`, `migrations/`, `alembic/`)
- Schema files (`schema.*`, `*.schema.*`)
- Model definition files (`*model*`)
- API type definitions (request/response types)

### gates.apiSurfaceChanges

**Triggers when:** Public interfaces change.

**Detection:**
- New route/endpoint definitions
- Changed function signatures in public modules
- New command, skill, or agent files (in plugin context)
- Changes to API documentation or OpenAPI specs

### gates.scopeDeviations

**Triggers when:** Changes fall outside the expected impact area.

**Detection:**
- Files modified that were not identified in `gh-start` Phase 4 (impact analysis)
- Changes to areas unrelated to the issue's acceptance criteria

### gates.ambiguousRequirements

**Triggers when:** Acceptance criteria require interpretation.

**Detection:**
- Criteria containing vague terms: "should be fast", "user-friendly", "appropriate", "etc."
- Contradictory criteria
- Criteria that don't map to observable, testable behavior

## Custom Gate Triggers

Add project-specific file patterns that should trigger gates:

```json
{
  "gates": {
    "customTriggers": ["*.proto", "**/migrations/*", "config/deploy/*"],
    "customTriggersMode": "on"
  }
}
```

Array of glob patterns. Any file matching these patterns triggers a gate.

**Behavior control**: Custom triggers use a separate config key:

| Value | Behavior |
|-------|----------|
| `on` | Pause for approval (default) |
| `log` | Record without pausing |
| `off` | Skip custom triggers entirely |

## Additional Configuration

### Decision Journal

| Key | Default | Options | Purpose |
|-----|---------|---------|---------|
| `.journal.dir` | `.decisions` | Any relative path | Directory for journal files |
| `.journal.sensitivityDefault` | `public` | `public` / `internal` | Default sensitivity for entries |

### Comprehension Report

| Key | Default | Options | Purpose |
|-----|---------|---------|---------|
| `.report.thresholdFull` | `100` | Integer (lines changed) | Diff size triggering full report |

### gh-explain

| Key | Default | Options | Purpose |
|-----|---------|---------|---------|
| `.explain.sessionSave` | `ask` | `always` / `ask` / `never` | Session save behavior |
| `.explain.includeDiff` | `true` | `true` / `false` | Load diff into context automatically |

### Per-Command Toggles

Disable specific comprehension features per command:

| Key | Default | Purpose |
|-----|---------|---------|
| `.commands.ghStartFamiliarityPrompt` | `true` | Show familiarity question at start |
| `.commands.ghCommitFirstTouch` | `true` | Flag first-touch files |
| `.commands.ghPrComprehensionReport` | `true` | Generate comprehension report |
| `.commands.ghReviewComprehensionCheck` | `true` | Verify comprehension report in reviews |
| `.commands.ghPrDecisionSummary` | `true` | Include decision summary in PR body |
| `.commands.ghMergeKnowledgeCheckpoint` | `true` | Show knowledge checkpoint before merge |

### Merge

| Key | Default | Options | Purpose |
|-----|---------|---------|---------|
| `.merge.strategy` | `squash` | `squash` / `merge` / `rebase` | Default merge strategy for PRs |
| `.merge.deleteBranch` | `true` | `true` / `false` | Delete source branch after merge |

### Conventions

| Key | Default | Options | Purpose |
|-----|---------|---------|---------|
| `.conventions.commitSubjectMaxLength` | `72` | Integer (30-200) | Max commit subject line length |
| `.conventions.commitTypes` | `["feat","fix",...]` | Array of strings | Valid conventional commit type prefixes |
| `.conventions.branchPatterns.feature` | `feature/issue-{N}-{desc}` | String with `{N}`, `{desc}` | Feature branch pattern |
| `.conventions.branchPatterns.fix` | `fix/issue-{N}-{desc}` | String with `{N}`, `{desc}` | Fix branch pattern |
| `.conventions.branchPatterns.docs` | `docs/issue-{N}-{desc}` | String with `{N}`, `{desc}` | Docs branch pattern |
| `.conventions.additionalBranchTypes` | `{}` | Object of patterns | Extra branch types (e.g., `{"refactor": "refactor/issue-{N}-{desc}"}`) |

### Release

| Key | Default | Options | Purpose |
|-----|---------|---------|---------|
| `.release.tagPrefix` | `v` | Any string | Prefix for version tags (`v1.2.3` or `1.2.3`) |

### Timeouts

| Key | Default | Options | Purpose |
|-----|---------|---------|---------|
| `.timeouts.devServerStartup` | `30` | Integer (5-300) seconds | Dev server readiness wait |
| `.timeouts.e2eTest` | `120` | Integer (30-600) seconds | E2E test suite timeout |
| `.timeouts.verificationScript` | `180` | Integer (30-600) seconds | Verification script timeout |
| `.timeouts.qualityCheckMaxIterations` | `3` | Integer (1-10) | Max lint/test/typecheck fix cycles |

### Review

| Key | Default | Options | Purpose |
|-----|---------|---------|---------|
| `.review.firstTouchLineThreshold` | `50` | Integer (10-500) lines | First-touch AI pattern detection threshold |
| `.review.activityLookbackDays` | `30` | Integer (7-365) days | Reviewer suggestion activity window |
| `.review.activityFallbackDays` | `90` | Integer (30-365) days | Extended lookback when no recent activity |

## Reading Configuration

See `references/config-reading.md` for the canonical config reading patterns and full JSON path reference.

## Examples

### Minimal (accept all defaults)

No configuration needed. All gates default to `on`.

### CI/Automated Pipeline

```json
{
  "gates": {
    "newDependencies": "log",
    "securityChanges": "on",
    "schemaChanges": "log",
    "apiSurfaceChanges": "log",
    "scopeDeviations": "log",
    "ambiguousRequirements": "log"
  }
}
```

Only security changes pause — everything else is logged without blocking.

### Trusted Team / Fast Iteration

```json
{
  "gates": {
    "newDependencies": "off",
    "securityChanges": "on",
    "schemaChanges": "on",
    "apiSurfaceChanges": "off",
    "scopeDeviations": "off",
    "ambiguousRequirements": "off"
  }
}
```

Only security and schema changes gate — trust the AI for everything else.

## Gate Visual Format

When a gate triggers (`on` mode), the calling command presents:

```
COMPREHENSION GATE: {category}

{Context explaining what triggered the gate}

{Findings / decision details}

Options:
1. "Approve: {recommended approach}" (Recommended)
2. "Alternative: {alternative A}" — {trade-off}
3. "I need more information"
4. "Proceed anyway — skip this gate"
```

Option 4 ("proceed anyway") is always available. Bypasses are logged with `Gate: Bypassed — human chose to skip`.
