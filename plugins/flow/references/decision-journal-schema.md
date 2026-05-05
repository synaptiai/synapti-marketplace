# Decision Journal Schema

Reference for the journal file format used by flow's audit trail and learning loop.

## File Naming

| Pattern | When Used |
|---------|-----------|
| `issue-{N}.md` | Branch matches `issue-{N}` pattern |
| `session-{YYYY-MM-DD}.md` | No issue number in branch name |

Journal files are stored in the journal directory (default: `.decisions/`, configurable via `journal.dir` setting).

## Auto-Log Entry Format

Written by PostToolUse hooks (`log-file-changes.sh`, `log-commits.sh`).

### File Change Entry

```
<!-- auto-log: YYYY-MM-DD HH:MM Edit|Write /path/to/file -->
```

### Commit Entry

```
<!-- auto-log: YYYY-MM-DD HH:MM commit "commit message subject" -->
```

Auto-log entries are HTML comments to avoid cluttering rendered markdown.

## Structured Entry Format

Written by skills (e.g., `autonomous-workflow`, `change-classification`).

```markdown
### [Category] Title

**Timestamp**: YYYY-MM-DD HH:MM
**Sensitivity**: public | internal

**Decision**: What was decided.

**Reasoning**: Why this approach was chosen.

**Alternatives considered**:
- Alternative A — why rejected
- Alternative B — why rejected

**Evidence**: Links, test results, or data supporting the decision.
```

### Categories

| Category | Used By |
|----------|---------|
| `Architecture` | Design decisions, patterns |
| `Implementation` | Code approach choices |
| `Convention` | Style, naming, structure |
| `Quality` | Test strategy, review scope |
| `Risk` | Safety tier overrides, security |

## Sensitivity Levels

| Level | Meaning | Default |
|-------|---------|---------|
| `public` | Safe for anyone to see | Yes (configurable via `journal.sensitivityDefault`) |
| `internal` | Internal team visibility only | |

## Journal Directory

Configurable in the settings cascade (later layers override earlier ones):

1. `plugins/flow/settings.json`
2. `~/.claude/settings.flow.json`
3. `.claude/settings.flow.json`
4. `.claude/settings.flow.local.json` (highest priority)

See [gate-configuration.md](gate-configuration.md#settings-file-locations) for the canonical cascade reference.

```json
{
  "journal": {
    "dir": ".decisions",
    "sensitivityDefault": "public"
  }
}
```
