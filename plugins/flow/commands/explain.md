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

echo "### Branch & Issue"
BRANCH=$(git branch --show-current 2>/dev/null)
ISSUE_NUM=$(echo "$BRANCH" | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+')
echo "BRANCH=$BRANCH"
# Quote parenthesized fallback per command-output-format.md rule 2.
echo "ISSUE_NUM=${ISSUE_NUM:-\"(none)\"}"

echo ""
echo "### Decision Journal"
HELPER="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/cascade-resolve.sh"
JOURNAL_DIR=".decisions"
[ -x "$HELPER" ] && JOURNAL_DIR=$("$HELPER" --default ".decisions" '.journal.dir // empty')
echo "JOURNAL_DIR=$JOURNAL_DIR"
if [ -n "$ISSUE_NUM" ] && [ -f "$JOURNAL_DIR/issue-$ISSUE_NUM.md" ]; then
  echo "JOURNAL_FILE=$JOURNAL_DIR/issue-$ISSUE_NUM.md"
  echo "JOURNAL_BYTES=$(wc -c < "$JOURNAL_DIR/issue-$ISSUE_NUM.md" | tr -d ' ')"
  echo ""
  echo "#### Journal contents"
  cat "$JOURNAL_DIR/issue-$ISSUE_NUM.md"
else
  echo "STATE=empty"
fi

echo ""
echo "### Issue Details"
if [ -n "$ISSUE_NUM" ]; then
  gh issue view "$ISSUE_NUM" --json title,body --jq '"TITLE=\"\(.title)\"\nBODY_LENGTH=\(.body | length)"' 2>/dev/null
  echo ""
  echo "#### Issue body"
  gh issue view "$ISSUE_NUM" --json body --jq '.body' 2>/dev/null
else
  echo "STATE=empty"
fi

echo ""
echo "### Branch Diff Summary"
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
echo "DEFAULT_BRANCH=$DEFAULT_BRANCH"
# Capture so an empty stat (e.g., on the default branch) emits STATE=empty
# rather than a silent heading; prefix raw stat lines with DIFF_STAT=.
DIFF_STAT=$(git diff --stat "$DEFAULT_BRANCH"...HEAD 2>/dev/null)
if [ -z "$DIFF_STAT" ]; then
  echo "STATE=empty"
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
