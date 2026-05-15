---
description: "Display a read-only overview of workflow state including assigned issues, open PRs, pending reviews, branch state, and decision journal health. Use when checking current development status."
allowed-tools: Bash, Read
---

# Workflow Status

Read-only overview of the current development state. No skills needed — pure observation.

## Required Skills

_None — read-only status command. No skill invocations._

## Gather State

Pre-executed at command load (`!` prefix) — the agent receives this output as part of the prompt, no Bash tool round-trip.

```!
# 1. Current branch and uncommitted changes
git branch --show-current
git status --short | head -20

# 2. Commits ahead of default branch
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
git rev-list --count "$DEFAULT_BRANCH"..HEAD 2>/dev/null || echo "0"

# 3. Assigned issues
gh issue list --assignee @me --state open --limit 10 --json number,title,labels

# 4. Open PRs (authored)
gh pr list --author @me --state open --json number,title,state,reviewDecision,statusCheckRollup

# 5. PRs needing my review
gh pr list --search "review-requested:@me" --state open --json number,title,author

# 6. Decision journal health. Resolved via bin/cascade-resolve.sh.
HELPER="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh"
JOURNAL_DIR=".decisions"
[ -x "$HELPER" ] && JOURNAL_DIR=$("$HELPER" --default ".decisions" '.journal.dir // empty')
[ -d "$JOURNAL_DIR" ] && ls -la "$JOURNAL_DIR"/*.md 2>/dev/null | wc -l || echo "0"

# 7. Learning pending
[ -f "$HOME/.claude/flow-learn-pending" ] && echo "LEARNING PENDING: $(cat $HOME/.claude/flow-learn-pending)" || echo "No pending learning"

true
```

## Gather Findings Ledger

Aggregate review findings across the user's open PRs (author OR assignee). See [`references/finding-ledger-parser.md`](../references/finding-ledger-parser.md) for the canonical marker schemas, queries, and state classification — the bash below applies that contract. Pre-executed at command load (`!` prefix).

```!
ME=$(gh api user --jq '.login')
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')

# MARKERTRUST_GATE_BEGIN
# Resolve trust list from the standard Claude Code settings cascade — same
# precedence as /flow:merge. See commands/merge.md for the full rationale.
TRUST_DEFAULT='["OWNER","MEMBER","COLLABORATOR"]'
TRUST_LIST="$TRUST_DEFAULT"
LOCAL_SETTINGS=".claude/settings.flow.local.json"
PROJECT_SETTINGS=".claude/settings.flow.json"
USER_SETTINGS="${HOME:-/nonexistent}/.claude/settings.flow.json"
PLUGIN_SETTINGS="${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json"
for SETTINGS_PATH in "$LOCAL_SETTINGS" "$PROJECT_SETTINGS" "$USER_SETTINGS" "$PLUGIN_SETTINGS"; do
  [ -f "$SETTINGS_PATH" ] || continue
  CONFIGURED=$(jq -c '.merge.markerTrust.allowedAssociations // empty' "$SETTINGS_PATH" 2>&1)
  JQ_EXIT=$?
  if [ $JQ_EXIT -ne 0 ]; then
    JQ_ERR=$(printf '%s' "$CONFIGURED" | tr '\n' ' ' | cut -c1-200)
    echo "WARN: failed to parse $SETTINGS_PATH (jq exit=$JQ_EXIT, error: $JQ_ERR); skipping this source" >&2
    continue
  fi
  [ -z "$CONFIGURED" ] && continue
  if echo "$CONFIGURED" | jq -e '. | type == "array" and length > 0 and all(.[]; type == "string")' >/dev/null 2>&1; then
    TRUST_LIST="$CONFIGURED"
    break
  fi
  # Invalid (non-array, empty array, non-string elements) — fall through to
  # next source rather than block /flow:status (an aggregator command). The
  # /flow:merge gate is the authoritative validator and emits FINDING_LEDGER_BLOCK
  # for the same input, so the user sees the right error in the right place.
done
# MARKERTRUST_GATE_END

# Enumerate PRs (author OR assignee). Capture gh exit code separately so a
# silent gh failure (auth, network) doesn't masquerade as "no PRs".
LEDGER_PRS_RAW=$(gh pr list --state open --limit 100 --json number,author,assignees 2>/dev/null)
GH_EXIT=$?
if [ $GH_EXIT -ne 0 ] || [ -z "$LEDGER_PRS_RAW" ]; then
  LEDGER_PRS="LEDGER_UNAVAILABLE"
else
  LEDGER_PRS=$(echo "$LEDGER_PRS_RAW" | jq -r --arg me "$ME" \
    '[.[] | select(.author.login == $me or (.assignees[].login? == $me))] | .[].number' 2>/dev/null || echo "LEDGER_UNAVAILABLE")
fi

if [ "$LEDGER_PRS" = "LEDGER_UNAVAILABLE" ]; then
  echo "LEDGER: unavailable (gh API failed)"
else
  # Sanitize attacker-controlled fields before display/echo: cap length and
  # strip non-printable bytes so a hostile review-body can't inject ANSI
  # escapes into LEDGER_WARN output. Defined once for the whole loop.
  safe() { printf '%s' "$1" | tr -cd '[:print:]' | cut -c1-64; }
  for PR_NUM in $LEDGER_PRS; do
    REVIEW_BODY=$(gh api --paginate "repos/$REPO/pulls/$PR_NUM/reviews" 2>/dev/null \
      | jq -s -r --argjson trust "$TRUST_LIST" \
          'add | [.[] | select((.author_association as $a | $trust | index($a)) and (.body | test("FLOW_REVIEW_CYCLE:")))] | last | .body // ""')
    FINDINGS_RAW=$(echo "$REVIEW_BODY" | grep -o 'FINDINGS:\[[^]]*\]' | sed 's/^FINDINGS:\[//;s/\]$//')
    [ -z "$FINDINGS_RAW" ] && continue

    RESOLUTION_BODY=$(gh api --paginate "repos/$REPO/issues/$PR_NUM/comments" 2>/dev/null \
      | jq -s -r --argjson trust "$TRUST_LIST" \
          'add | [.[] | select((.author_association as $a | $trust | index($a)) and (.body | test("FLOW_RESOLUTION_CYCLE:")))] | last | .body // ""')
    # Strip whitespace so reviewer-edited arrays like `[F1, F2]` still match.
    RESOLVED=$(echo "$RESOLUTION_BODY"  | grep -o 'RESOLVED:\[[^]]*\]'  | sed 's/^RESOLVED:\[//;s/\]$//'  | tr -d ' ')
    ESCALATED=$(echo "$RESOLUTION_BODY" | grep -o 'ESCALATED:\[[^]]*\]' | sed 's/^ESCALATED:\[//;s/\]$//' | tr -d ' ')
    DISPUTED=$(echo "$RESOLUTION_BODY"  | grep -o 'DISPUTED:\[[^]]*\]'  | sed 's/^DISPUTED:\[//;s/\]$//'  | tr -d ' ')

    echo "$FINDINGS_RAW" | tr ',' '\n' | while IFS='|' read -r ID PRIORITY CAT LOC STATUS; do
      [ -z "$ID" ] && continue
      # Reject IDs containing case-glob metacharacters (`*`, `?`, `[`, `]`) —
      # IDs are template-issued and should match [A-Za-z][A-Za-z0-9_-]*.
      # Without this, a hostile finding ID of `*` would always match the
      # `case ",$RESOLVED," in *",$ID,"*)` containment check and silently
      # disappear from the tally.
      case "$ID" in
        [A-Za-z]*) ;;
        *) echo "LEDGER_WARN: PR#$PR_NUM finding '$(safe "$ID")' rejected (non-conforming ID)" >&2; continue ;;
      esac
      case "$ID" in *[!A-Za-z0-9_-]*)
        echo "LEDGER_WARN: PR#$PR_NUM finding '$(safe "$ID")' rejected (non-conforming ID)" >&2
        continue ;;
      esac
      # Defensive: surface non-conforming priority rows to stderr (visible
      # without breaking the tally), then skip. Older marker formats produced
      # findings without P{1-3} priority fields.
      case "$PRIORITY" in
        P1|P2|P3) ;;
        *) echo "LEDGER_WARN: PR#$PR_NUM finding '$(safe "$ID")' has malformed priority '$(safe "$PRIORITY")'" >&2; continue ;;
      esac
      # Precedence: RESOLVED > ESCALATED > DISPUTED > in_fix_forward.
      case ",$RESOLVED," in *",$ID,"*) continue ;; esac
      case ",$ESCALATED," in *",$ID,"*) STATE=escalated ;;
        *) case ",$DISPUTED," in *",$ID,"*) STATE=disputed ;;
             *) STATE=in_fix_forward ;; esac ;;
      esac
      echo "${PRIORITY}|${STATE}"
    done
  done | sort | uniq -c
fi

true
```

The output of the loop is a tally like:

```
   2 P1|in_fix_forward
   1 P2|escalated
   3 P3|in_fix_forward
```

Use this to render the Findings Ledger line per priority. If the loop produces no rows AND `LEDGER_PRS` was non-empty, the user has open PRs but no review markers yet — render `No open findings`.

## Display

```markdown
## Flow Status

### Current Branch
- **Branch**: {branch name}
- **Commits ahead**: {N} ahead of {default branch}
- **Uncommitted changes**: {count} files

### My Issues (Open)
| # | Title | Labels |
|---|-------|--------|
| {N} | {title} | {labels} |

### My PRs
| # | Title | Status | Checks |
|---|-------|--------|--------|
| {N} | {title} | {review status} | {check status} |

### Awaiting My Review
| # | Title | Author |
|---|-------|--------|
| {N} | {title} | @{author} |

### Decision Journal
- **Journals**: {N} active
- **Learning**: {pending/none}

### Findings Ledger
{single line: `P1: {n}[ (annotation)]    P2: {n}[ (annotation)]    P3: {n}[ (annotation)]` — annotations are omitted when count is 0; see render rules below}

### Suggested Next Action
{Based on state, suggest the most useful /flow command}
```

## Render Rules — Findings Ledger

Convert the `PRIORITY|STATE` tally from the gather step into one line. Per-priority rules:

- `0` findings at this priority → `P{n}: 0` (bare).
- All findings at this priority share one state → `P{n}: K (state-label)`.
- Multiple states at this priority → `P{n}: K (a STATE_A; b STATE_B)`.

State labels:

| State | Label |
|-------|-------|
| `in_fix_forward` | `in fix-forward` |
| `escalated` | `ESCALATED` |
| `disputed` | `DISPUTED` |

Edge cases:

- `LEDGER_PRS` empty (no open PRs for user) → `No open findings.`
- `LEDGER_PRS` non-empty but tally empty (no markers yet) → `No open findings.`
- `LEDGER_UNAVAILABLE` (gh API failed) → `Findings Ledger unavailable — gh API failed.` (one-line cause).

Format matches the workshop slide mockup in `docs/flow-team-session/slides.md` (`/flow:status — what to expect` section, Findings Ledger row).

## Suggestions Logic

| State | Suggestion |
|-------|-----------|
| On default branch, no assigned issues | "Assign an issue or `/flow:start <N>`" |
| On default branch, has assigned issue | "`/flow:start {first-issue-number}`" |
| On feature branch, uncommitted changes | "`/flow:commit`" |
| On feature branch, commits ahead, no PR | "`/flow:pr`" |
| Has PR with review comments | "`/flow:address {pr-number}`" |
| Has PR approved | "`/flow:merge {pr-number}`" |
| PRs awaiting review | "`/flow:review {first-pr-number}`" |
| Learning pending | "`/flow:learn`" |

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read git state / branch / commits-ahead | 1 | Autonomous, read-only |
| `gh issue list` / `gh pr list` (assigned + reviewing) | 1 | Autonomous, read-only |
| Read `.decisions/` journal directory | 1 | Autonomous, read-only |
| Read `~/.claude/flow-learn-pending` flag | 1 | Autonomous, read-only |
| Findings-ledger aggregation across open PRs (`gh api` paginated) | 1 | Autonomous, read-only |
| Render status tables | 1 | Autonomous, output-only |

`/flow:status` makes **zero mutations**. It cannot create branches, commit files, push, post comments, create issues, or change settings. Every action is a read; every output is a render.
