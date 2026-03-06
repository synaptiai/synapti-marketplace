# Decision Journal Schema

Reference for the decision journal file format used by the comprehension layer.

## File Location

```
.decisions/issue-{N}.md
```

Where `{N}` is the GitHub issue number. One journal file per issue/branch.

## File Structure

```markdown
# Decision Journal: Issue #{N} — {issue title}

**Issue**: #{N}
**Branch**: {branch-name}
**Started**: {YYYY-MM-DD}

---

### {YYYY-MM-DD HH:MM} [{CATEGORY}] {Decision Title}

**Command**: {command-name}
**Decision**: {what was decided}
**Alternatives**: {what else was considered}
**Rationale**: {why this choice}
**Risk**: {risk level}
**Sensitivity**: {sensitivity level}
**Gate**: {gate status}
**References**: {cross-issue refs}

---
```

Entries are separated by `---` (horizontal rule). The header is the first section before any `---`.

## Entry Fields

| Field | Required | Values | Description |
|-------|----------|--------|-------------|
| Timestamp | Yes | `YYYY-MM-DD HH:MM` | When the decision was recorded |
| Category | Yes | See categories below | Type of decision |
| Title | Yes | Free text | Brief description of the decision |
| Command | Yes | `gh-start`, `gh-commit`, `gh-pr`, `gh-review`, `gh-address` | Which command was executing |
| Decision | Yes | Free text | What was decided |
| Alternatives | Yes | Free text or `N/A` | Other options considered |
| Rationale | Yes | Free text | Why this choice was made |
| Risk | Yes | `Low`, `Medium`, `High`, `Critical` | Risk level of the decision |
| Sensitivity | Yes | `public`, `internal` | Visibility classification |
| Gate | Yes | See gate values below | Whether a human was consulted |
| References | Yes | `#N` format or `None` | Cross-issue references |

## Categories

| Category | When to Use | Examples |
|----------|------------|---------|
| `architecture` | Structural/design choices | New abstraction layer, design pattern choice, module organization |
| `requirements` | How acceptance criteria were interpreted | Ambiguous criterion resolved, assumption made about behavior |
| `trade-off` | Competing concerns balanced | Performance vs. readability, scope vs. timeline |
| `implementation` | Technical approach chosen | Library selection, algorithm choice, API design |
| `risk` | Risk-related decisions | Security approach, error handling strategy, data validation |
| `scope` | Scope boundaries set | Feature deferred, requirement simplified, edge case excluded |

## Gate Values

| Value | Meaning |
|-------|---------|
| `Yes — human approved` | Human gate triggered, human chose recommended or alternative |
| `No — AI decision` | No gate triggered, AI made the decision |
| `Bypassed — human chose to skip` | Gate triggered but human chose "proceed anyway" |
| `Logged (auto-approved)` | Gate was in `log` mode — decision recorded but no pause |

## Sensitivity Classification

| Level | When to Use | PR Summary Behavior |
|-------|------------|-------------------|
| `public` | Default. General technical decisions | Included verbatim in PR body |
| `internal` | Security rationale, credential handling, vulnerability remediation, access control | Redacted to `[Internal decision — see .decisions/ file for details]` |

**Never include in any entry (even `internal`):**
- Specific vulnerability details or exploitation vectors
- Previous insecure states or configurations
- Secret values or their storage locations
- Security architecture weaknesses (even remediated ones)

## Parsing Instructions

To extract entries programmatically:

1. Split the file content on `\n---\n` (entries are separated by horizontal rules)
2. The first section (before the first `---`) is the header — extract `Issue`, `Branch`, `Started`
3. For each subsequent section, parse the `### ` heading line:
   - Format: `### {YYYY-MM-DD HH:MM} [{CATEGORY}] {Decision Title}`
   - Regex: `^### (\d{4}-\d{2}-\d{2} \d{2}:\d{2}) \[(\w+)\] (.+)$`
4. Parse `**Field**: Value` lines within each section
5. Skip any malformed entries (warn but don't fail)

## Session Files

Q&A sessions from `gh-explain` are saved as:

```
.decisions/explain-issue-{N}-{YYYYMMDD-HHMM}.md
```

These are free-form markdown transcripts, not structured journal entries.
