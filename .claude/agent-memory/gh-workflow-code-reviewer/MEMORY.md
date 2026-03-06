# Code Reviewer Memory

## Project Structure
- Markdown-only project: Claude Code plugin marketplace
- Core plugin: `plugins/gh-workflow/` with commands, skills, agents, references, templates
- Config is read from CLAUDE.md via grep patterns (handles bulleted and bare formats)
- Version tracked in `plugin.json` and `marketplace.json`

## Review Patterns Learned

### Config Reading Pattern
- Standard pattern: `grep -iE "^\s*-?\s*{key}:" "$CLAUDE_MD" | sed 's/.*:\s*//' | tr -d ' '`
- CLAUDE.md lookup: try `.claude/CLAUDE.md` first, then `CLAUDE.md`
- Inconsistency found (PR #19): gh-merge has full bash code block for config, other commands use prose-only
- Per-command toggle checks should use prose pattern (5 of 6 commands do)

### Common Issues Found
- Variable scoping: commands that reference `ISSUE_NUM` may not define it (gh-address, gh-commit)
- Path safety: only gh-explain validates issue numbers before path construction
- journal-dir config: no validation against path traversal (`..`, absolute paths) -- flagged as P1
- Placeholder syntax: `{ISSUE_NUM}` vs `$ISSUE_NUM` in bash code blocks must match bash syntax
- Bash placeholder `{ISSUE_NUM}` in decision-journal summarize mode (line 247) is wrong syntax

### Default Branch Detection
- Two patterns exist: `gh repo view --json defaultBranchRef` (most commands) vs `git symbolic-ref` (decision-journal skill)
- `gh repo view` is preferred -- more reliable since `refs/remotes/origin/HEAD` not always set

### Skill Modes (decision-journal)
- `init`: creates journal header (reads only journal-dir, not sensitivity-default)
- `log`: extracts decisions from diff, evaluates gates (reads journal-dir + sensitivity-default)
- `summarize`: condenses journal for PR body (reads journal-dir)

### Custom Gate Triggers
- Documented in gate-configuration.md but NOT implemented in decision-journal skill Step 3
- Only 6 named gates are evaluated; custom glob patterns are not checked

### Integration Map
- gh-start: init + log modes
- gh-commit: log mode (ISSUE_NUM may be empty for non-standard branches)
- gh-pr: summarize mode + comprehension-report skill
- gh-address: log mode (has ISSUE_NUM extraction in Step 7b.0)
- gh-review: comprehension assessment (Facet 6)
- gh-merge: knowledge checkpoint
- gh-status: comprehension health overview (read-only contract tension with checkout)
- gh-explain: interactive Q&A with session save

### Command Count
- As of v1.7.0: 12 commands (gh-setup still references "11" -- needs update)
- gh-explain added to CLAUDE-workflow.md template but missing from gh-setup generated table

### Familiarity Baseline
- Collected in gh-start Step 2.2b but never consumed by gh-pr
- Forward reference at gh-start.md:133 has no matching read in gh-pr
