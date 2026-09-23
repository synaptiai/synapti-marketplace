---
description: "Answer questions about architecture decisions, implementation rationale, and trade-offs by loading the decision journal and diff context for the current branch or issue. Use when seeking to understand what was built and why."
allowed-tools: Bash, Read, AskUserQuestion, Grep, Glob
---

# Explain Decisions

Interactive Q&A mode for understanding what was built and why. Read-only — no changes made.

## Required Skills

_None — explanatory Q&A over journal and diff context. No skill invocations._

## Phase 1: Load Context

```!
# Output: `###`-headed sections + KEY=value per
# `references/command-output-format.md`.

printf '%s\n' "### Branch & Issue"
BRANCH=$(git branch --show-current 2>/dev/null)
ISSUE_NUM=$(printf '%s\n' "$BRANCH" | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+')
printf '%s\n' "BRANCH=$BRANCH"
# Quote parenthesized fallback per command-output-format.md rule 2.
printf '%s\n' "ISSUE_NUM=${ISSUE_NUM:-\"(none)\"}"

printf '%s\n' ""
printf '%s\n' "### Decision Journal"
HELPER="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/cascade-resolve.sh"
JOURNAL_DIR=".decisions"
[ -x "$HELPER" ] && JOURNAL_DIR=$("$HELPER" --default ".decisions" '.journal.dir // empty')
printf '%s\n' "JOURNAL_DIR=$JOURNAL_DIR"
if [ -n "$ISSUE_NUM" ] && [ -f "$JOURNAL_DIR/issue-$ISSUE_NUM.md" ]; then
  printf '%s\n' "JOURNAL_FILE=$JOURNAL_DIR/issue-$ISSUE_NUM.md"
  printf '%s\n' "JOURNAL_BYTES=$(wc -c < "$JOURNAL_DIR/issue-$ISSUE_NUM.md" | tr -d ' ')"
  printf '%s\n' ""
  printf '%s\n' "#### Journal contents"
  cat "$JOURNAL_DIR/issue-$ISSUE_NUM.md"
  # The auto-log breadcrumbs live in a local trail, one file per month. They are
  # context for "what was touched", not decisions, so they are labelled and kept
  # separate from the journal body above rather than inlined into it. A set of
  # files, not one: the issue-scoped trail rotates monthly.
  #
  # The heading names where the trail came from rather than asserting it is
  # untracked. The journal dir is read from a TRACKED settings file, so a fork
  # could point it at a tracked path, and this label would then be vouching for
  # content it has not checked.
  AUTOLOG_FILES=0
  printf '%s\n' ""
  printf '%s\n' "#### Auto-log trail ($JOURNAL_DIR/auto-log/)"
  for AUTOLOG in "$JOURNAL_DIR/auto-log/issue-$ISSUE_NUM".*.md; do
    [ -f "$AUTOLOG" ] || continue
    AUTOLOG_FILES=$((AUTOLOG_FILES + 1))
    printf '%s\n' ""
    printf '%s\n' "##### $(basename "$AUTOLOG")"
    cat "$AUTOLOG"
  done
  printf '%s\n' "AUTOLOG_FILES=$AUTOLOG_FILES"
else
  printf '%s\n' "STATE=empty"
fi

printf '%s\n' ""
printf '%s\n' "### Issue Details"
if [ -n "$ISSUE_NUM" ]; then
  gh issue view "$ISSUE_NUM" --json title,body --jq '"TITLE=\"\(.title)\"\nBODY_LENGTH=\(.body | length)"' 2>/dev/null
  printf '%s\n' ""
  printf '%s\n' "#### Issue body"
  gh issue view "$ISSUE_NUM" --json body --jq '.body' 2>/dev/null
else
  printf '%s\n' "STATE=empty"
fi

printf '%s\n' ""
printf '%s\n' "### Branch Diff Summary"
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || printf '%s\n' "main")
printf '%s\n' "DEFAULT_BRANCH=$DEFAULT_BRANCH"
# Capture so an empty stat (e.g., on the default branch) emits STATE=empty
# rather than a silent heading; prefix raw stat lines with DIFF_STAT=.
DIFF_STAT=$(git diff --stat "$DEFAULT_BRANCH"...HEAD 2>/dev/null)
if [ -z "$DIFF_STAT" ]; then
  printf '%s\n' "STATE=empty"
else
  printf '%s\n' "$DIFF_STAT" | sed 's/^/DIFF_STAT=/'
fi

true
```

## Phase 2: Present Context

```markdown
## Decision Context

**Branch**: {branch}
**Issue**: #{N} — {title}
**Files changed**: {count}
**Journal entries**: {count}
**Key decisions**: {list from journal}
```

## Phase 3: Interactive Q&A

Use the AskUserQuestion tool with contextual options to ask: "What would you like to understand about this implementation?"

For each question:
1. Search the decision journal for relevant entries
2. Read referenced files for evidence
3. Construct an evidence-based answer with file:line citations
4. Offer follow-up question

## No Context Case

If no decision journal or no branch context:
- "No decision context available for the current branch."
- Offer to explain based on diff analysis alone
- Or suggest running `/flow:start` first to generate context

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read decision journal / commits / PR history | 1 | Autonomous, read-only |
| `AskUserQuestion` (clarify scope) | n/a | User-driven |

`/flow:explain` is read-only. It never modifies files, never pushes, never creates issues or PRs. The only user-facing surface is the Q&A response.
