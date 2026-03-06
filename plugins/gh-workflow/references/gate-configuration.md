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
