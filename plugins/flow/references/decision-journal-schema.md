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
    "dir": ".decisions"
  }
}
```

## Manifest Frontmatter

Journal files MAY include a YAML frontmatter manifest at the top of the file. The manifest lists every artifact captured during the work — specification, Stranger Test result, review cycles, dropped findings, design decisions, brainstorm decisions, and so on. The manifest enables tooling (and human readers) to query the journal's contents without reading the full markdown body.

The manifest is **append-only via `bin/journal-record.sh`**. Direct manual edits are permitted (the file is plain markdown with YAML frontmatter, no special parser), but the helper guarantees atomic writes and consistent timestamping.

### Schema

```yaml
---
issue: <integer>                 # the issue number (matches the file name)
created: <ISO-8601 UTC>          # first timestamp the manifest was written
branch: <string>                 # optional — set by /flow:start when the branch is created
artifacts:
  - type: <enum>                 # see artifact types below
    captured_at: <ISO-8601 UTC>
    # plus per-artifact-type fields (see below)
---
```

### Artifact types

| `type` | Required additional fields | Captured by | When |
|---|---|---|---|
| `specification` | `by: specification-capture`, `elements: [non-goals, failure-modes, interface-contracts]` | `specification-capture` skill via `bin/journal-record.sh` | start.md Phase 1 (and design/brainstorm when they capture missing elements) |
| `stranger-test` | `result: PASS\|BLOCK`, `task_count: <int>`, optionally `failed_task: <id>` | `start.md` Phase 2 end-of-PLAN gate | start.md Phase 2 |
| `review-cycle` | `cycle: <int>`, `path: A\|B`, `findings_count: <int>`, optionally `pr: <int>` | `review.md` Phase 4 step 7 (after FLOW_REVIEW_CYCLE marker is posted) | review.md, pr.md |
| `dropped-finding` | `cycle: <int>`, `finding_id: <string>`, `facet: <string>`, `reason: <string>`, `pr: <int>` | `review.md` Path A A.4 (DROPPED rows) | review.md A.4 |
| `consolidation-gap` | `cycle: <int>`, `pr: <int>`, `finding_id: <string>`, `reason: <string>` | `review.md` Path A A.5 fallback table | review.md A.5 |
| `design-decision` | `decision: <string>`, `category: architecture` | `design.md` Phase 4 | design.md |
| `brainstorm-decision` | `topic: <string>`, `chosen: <string>`, `options_considered: <int>` | `brainstorm.md` Phase 4 | brainstorm.md |
| `verdict` | `result: PASS\|FAIL\|NEEDS-HUMAN-REVIEW`, `pr: <int>` (optional), `failures: [<criterion>...]` (optional) | `start.md` Phase 4 step 6 (after Agent(verdict-judge) returns) | start.md Phase 4 |
| `escalation-resolved` | `escalation_field: <string>` (one of the six canonical fields), `outcome: <string>` | manual or automated when an `AskUserQuestion` escalation closes | any |

Adding a new artifact type means adding the row above and using the matching `--metadata key=value` arguments to `bin/journal-record.sh`. The helper does not enforce a closed enum — it accepts any `--type` value — but the table here is the contract reviewers check during PR review.

### Compatibility with the legacy structured entry format

Journal files that pre-date the manifest use the structured entry format (`### [Category] Title` blocks) without YAML frontmatter. The manifest is **additive**: when `bin/journal-record.sh` is invoked on a manifest-less file, it inserts a manifest block at the top and preserves the existing body verbatim. Legacy entries remain readable; the manifest summarizes what kinds of artifacts the body contains so tooling does not need to parse the freeform sections.

### Reading the manifest

```bash
# Extract the artifacts list from a journal file
python3 -c "
import sys, yaml
content = open(sys.argv[1]).read()
if not content.startswith('---\n'):
    print('NO_MANIFEST')
    sys.exit(0)
end = content.find('\n---\n', 4)
if end == -1:
    print('MALFORMED_MANIFEST')
    sys.exit(1)
manifest = yaml.safe_load(content[4:end])
for a in manifest.get('artifacts', []):
    print(a.get('type'), '@', a.get('captured_at'))
" .decisions/issue-142.md
```

### Why YAML, not JSON?

YAML frontmatter is the convention for Markdown documents (Jekyll, Hugo, Pandoc, Marp, etc.). Tools like `gh` and `mkdocs` already understand it. JSON would be machine-friendlier but reads worse to humans skimming the journal. The trade-off favors YAML because the journal is intended to be human-readable first, machine-readable second.
