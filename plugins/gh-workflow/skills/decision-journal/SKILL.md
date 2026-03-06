---
name: decision-journal
description: Extracts and structures development decisions from diffs, manages decision journal entries, and detects human gate triggers. Use when logging decisions during gh-start, gh-commit, or gh-address. Use when summarizing decisions for PR bodies or when checking for gate-triggering changes like new dependencies, security modifications, or scope deviations.
allowed-tools: Bash, Read, Grep, Glob
context: fork
agent: Explore
---

# Decision Journal

Captures, structures, and persists significant decisions made during AI-driven workflow execution. Uses post-hoc extraction from diffs rather than AI self-reporting during execution.

## Purpose

In a fully AI-driven workflow, decisions happen invisibly. This skill makes them visible by:
- Extracting decisions from completed diffs (what changed vs. what was expected)
- Detecting high-stakes changes that warrant human approval (gates)
- Structuring decisions into a machine-parseable journal format
- Condensing journals into PR-body-ready summaries

## Mode Routing

This skill operates in one of three modes. The calling command specifies the mode in its invocation prompt.

| Mode | When Used | What It Does |
|------|-----------|-------------|
| `init` | gh-start after branch creation | Creates journal file header |
| `log` | gh-start, gh-commit, gh-address after changes | Extracts decisions from diff + evaluates gate triggers |
| `summarize` | gh-pr during PR content generation | Condenses journal for PR body |

Read the mode from the invocation prompt and execute only that mode's instructions.

## Mode: init

**Input** (from invocation prompt): Issue number, branch name, issue title, issue body.

**Process:**

1. Generate the journal file header:

```markdown
# Decision Journal: Issue #{N} — {issue title}

**Issue**: #{N}
**Branch**: {branch-name}
**Started**: {YYYY-MM-DD}

---
```

**Output:** Return the header markdown and the resolved journal directory (from `journal-dir` config, default `.decisions`). The calling command writes it to `{journal-dir}/issue-{N}.md`.

## Mode: log

**Input** (from invocation prompt): Description of what phase just completed (e.g., "task breakdown", "staged changes for commit", "addressed review feedback"). The calling command provides the relevant context.

**Process:**

### Step 1: Gather Context

```bash
# Get current branch and issue number
BRANCH=$(git branch --show-current)
ISSUE_NUM=$(echo "$BRANCH" | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+')

# Get the default branch
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
[ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH=$(git rev-parse --verify origin/main >/dev/null 2>&1 && echo "main" || echo "master")
```

```bash
# Read journal configuration from CLAUDE.md
CLAUDE_MD=""
[ -f ".claude/CLAUDE.md" ] && CLAUDE_MD=".claude/CLAUDE.md"
[ -z "$CLAUDE_MD" ] && [ -f "CLAUDE.md" ] && CLAUDE_MD="CLAUDE.md"

JOURNAL_DIR=".decisions"
SENSITIVITY_DEFAULT="public"
if [ -n "$CLAUDE_MD" ]; then
  DIR_VAL=$(grep -iE "^\s*-?\s*journal-dir:" "$CLAUDE_MD" 2>/dev/null | sed 's/.*:\s*//' | tr -d ' ')
  [ -n "$DIR_VAL" ] && JOURNAL_DIR="$DIR_VAL"
  SENS_VAL=$(grep -iE "^\s*-?\s*journal-sensitivity-default:" "$CLAUDE_MD" 2>/dev/null | sed 's/.*:\s*//' | tr -d ' ')
  [ -n "$SENS_VAL" ] && SENSITIVITY_DEFAULT="$SENS_VAL"
fi
echo "Journal directory: $JOURNAL_DIR"
echo "Default sensitivity: $SENSITIVITY_DEFAULT"
```

Use `$JOURNAL_DIR` instead of `.decisions` for all journal file paths in this mode. Use `$SENSITIVITY_DEFAULT` as the default sensitivity for new entries.

```bash
# Get the diff to analyze (staged changes for commit, or branch diff for other phases)
git diff --stat "$DEFAULT_BRANCH"...HEAD
git diff --name-only "$DEFAULT_BRANCH"...HEAD
```

```bash
# Get issue context
gh issue view "$ISSUE_NUM" --json title,body,labels 2>/dev/null
```

### Step 2: Extract Decisions (Post-Hoc)

Analyze the completed diff against the issue context. Identify decisions by comparing:
- **What changed** vs. **what the issue requested** — scope decisions, requirement interpretations
- **Patterns chosen** vs. **alternatives available** — architecture, implementation trade-offs
- **Files touched** vs. **expected impact area** — scope deviations

For each significant decision found, generate a journal entry:

```markdown
### {YYYY-MM-DD HH:MM} [{CATEGORY}] {Decision Title}

**Command**: {gh-start | gh-commit | gh-address}
**Decision**: {What was decided}
**Alternatives**: {What else was considered, or "N/A" for obvious choices}
**Rationale**: {Why this choice was made}
**Risk**: {Low | Medium | High | Critical}
**Sensitivity**: {public | internal}
**Gate**: {No — AI decision}
**References**: {#M, #K — cross-issue refs, or "None"}

---
```

**Categories**: `architecture`, `requirements`, `trade-off`, `implementation`, `risk`, `scope`

**Sensitivity rules:**
- Default: Use the `$SENSITIVITY_DEFAULT` value from Step 1 config (falls back to `public` if not configured)
- Use `internal` for decisions involving: security rationale, credential/secret handling, vulnerability remediation, access control logic
- Never document specific vulnerability details, exploitation vectors, previous insecure states, or secret values/locations — even in `internal` entries

### Step 3: Evaluate Gate Triggers

Read gate configuration from CLAUDE.md:

```bash
# Check for gate configuration (handles both bulleted and bare formats)
CLAUDE_MD=""
[ -f ".claude/CLAUDE.md" ] && CLAUDE_MD=".claude/CLAUDE.md"
[ -z "$CLAUDE_MD" ] && [ -f "CLAUDE.md" ] && CLAUDE_MD="CLAUDE.md"

if [ -n "$CLAUDE_MD" ]; then
  grep -iE "^\s*-?\s*gate-" "$CLAUDE_MD" 2>/dev/null
fi
```

If no configuration found, all gates default to `on`.

Check the diff against these gate detection heuristics:

| Trigger | Detection Method | Config Key |
|---------|-----------------|------------|
| New dependency | New entries in `package.json`, `requirements.txt`, `Gemfile`, `go.mod`, `Cargo.toml`, or new git submodule | `gate-new-dependencies` |
| Security changes | Files matching `*auth*`, `*security*`, `*permission*`, `*token*`, `*secret*`, `*crypto*`, `*session*`; changes to `.env*`, CORS/TLS config | `gate-security-changes` |
| Schema changes | Database migration files, changes to `schema.*`, `*model*` definitions, API type definitions | `gate-schema-changes` |
| API surface changes | New route/endpoint definitions, changed function signatures in public modules, new command/skill files | `gate-api-surface-changes` |
| Scope deviations | Files modified outside the expected impact area from the issue | `gate-scope-deviations` |
| Ambiguous requirements | Acceptance criteria containing vague terms ("should be fast", "user-friendly", "appropriate"), contradictory criteria | `gate-ambiguous-requirements` |

```bash
# Example detection for new dependencies
git diff "$DEFAULT_BRANCH"...HEAD --name-only | grep -E "(package\.json|requirements\.txt|Gemfile|go\.mod|Cargo\.toml|\.gitmodules)" 2>/dev/null
```

```bash
# Example detection for security-related files
git diff "$DEFAULT_BRANCH"...HEAD --name-only | grep -iE "(auth|security|permission|token|secret|crypto|session|\.env)" 2>/dev/null
```

For each trigger that fires:
1. Check the corresponding config key
2. If `on` — include in gate trigger output
3. If `log` — log the decision entry with `Gate: Logged (auto-approved)` but do not include in gate triggers
4. If `off` — skip entirely

### Step 4: Return Output

**Output format:**

```markdown
## Decision Entries

{One or more journal entries in the schema format above}

## Gate Triggers

{If any gates fired with config = `on`:}

| Category | Trigger | Reason | Recommended Action | Alternatives |
|----------|---------|--------|--------------------|-------------|
| security-changes | gate-security-changes | Modified auth middleware | Review security implications | Proceed without review |

{If no gates fired:}

No gate triggers detected.
```

The calling command:
- Appends decision entries to `{journal-dir}/issue-{N}.md` (using the resolved `$JOURNAL_DIR` from Step 1)
- If gate triggers are present, presents AskUserQuestion with the gate format
- Logs gate responses (approved/bypassed) back to the journal

## Mode: summarize

**Input** (from invocation prompt): Issue number (or path to the journal file), sensitivity filter preference.

**Process:**

1. Read journal configuration and the journal file:

```bash
# Read journal-dir from CLAUDE.md (same as log mode Step 1)
CLAUDE_MD=""
[ -f ".claude/CLAUDE.md" ] && CLAUDE_MD=".claude/CLAUDE.md"
[ -z "$CLAUDE_MD" ] && [ -f "CLAUDE.md" ] && CLAUDE_MD="CLAUDE.md"

JOURNAL_DIR=".decisions"
if [ -n "$CLAUDE_MD" ]; then
  DIR_VAL=$(grep -iE "^\s*-?\s*journal-dir:" "$CLAUDE_MD" 2>/dev/null | sed 's/.*:\s*//' | tr -d ' ')
  [ -n "$DIR_VAL" ] && JOURNAL_DIR="$DIR_VAL"
fi

# Read the specific journal file (use issue number from invocation, NOT a glob)
cat "$JOURNAL_DIR/issue-${ISSUE_NUM}.md" 2>/dev/null
```

2. Parse entries by splitting on `---` separators
3. For each entry:
   - If `Sensitivity: public` — include full entry in summary
   - If `Sensitivity: internal` — replace with: `[Internal decision — see .decisions/ file for details]`
4. Condense into a summary format:

**Output format:**

```markdown
## Decision Summary

**Total decisions**: {N} ({M} public, {K} internal)
**Gates triggered**: {X} ({Y} approved, {Z} bypassed)

### Key Decisions

| # | Category | Decision | Risk |
|---|----------|----------|------|
| 1 | architecture | {title} | {risk} |
| 2 | requirements | {title} | {risk} |

### Decision Details

{For each public entry, include a condensed version:}

**{Category}: {Title}** — {Decision}. {Rationale}. Risk: {risk}.

{For internal entries:}

**{Category}: [Internal decision]** — [See .decisions/ file for details]

### Gate Activity

{Summary of gate triggers and responses}
```

## Output Format

All modes return structured markdown. The calling command handles file I/O.

| Mode | Returns |
|------|---------|
| `init` | Journal file header markdown |
| `log` | Decision entries + gate trigger table |
| `summarize` | Condensed summary for PR body |

## Graceful Degradation

| Missing Capability | Fallback |
|-------------------|----------|
| No CLAUDE.md gate config | All gates default to `on` |
| No issue context (gh issue view fails) | Extract decisions from diff only, skip requirement comparison |
| No existing journal file (for summarize) | Return "No decision journal found" notice |
| Empty diff | Return "No changes to analyze" with no entries |
| Branch has no issue number | Use branch name as identifier, skip issue context |

## Integration Points

This skill is invoked by:
- `gh-start` — Phase 2 (`init` mode), Phase 5 (`log` mode)
- `gh-commit` — Phase 2 (`log` mode)
- `gh-pr` — Phase 3 (`summarize` mode)
- `gh-address` — After feedback aggregation (`log` mode)

The calling command handles all file persistence (Write/Edit to `{journal-dir}/issue-{N}.md`, where `journal-dir` is read from CLAUDE.md config, default `.decisions`) and AskUserQuestion presentation for gate triggers.
