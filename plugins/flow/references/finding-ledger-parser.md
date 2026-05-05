# Finding Ledger Parser

Canonical reference for extracting and classifying review findings across one or more pull requests. Used by `/flow:status` (Findings Ledger section) and `/flow:merge` (merge-blocking finding-ledger check).

## Marker Schemas

Two HTML-comment markers carry the finding state. They are emitted by review and resolution templates and are the only ledger source-of-truth.

### FLOW_REVIEW_CYCLE — emitted in PR review bodies

Source: `templates/review-comment.md`. Lists all findings raised in cycle `N` with their priority and location.

```
<!-- FLOW_REVIEW_CYCLE:{N} FINDINGS:[{ID}|{priority}|{category}|{file:line}|{status},{ID}|{priority}|{category}|{file:line}|{status}] -->
```

| Field | Values |
|-------|--------|
| `ID` | Finding identifier (e.g., `F1`, `F12`) |
| `priority` | `P1` \| `P2` \| `P3` |
| `category` | Free text (e.g., `security`, `correctness`, `convention`) |
| `file:line` | Location citation |
| `status` | `open` at review time |

### FLOW_RESOLUTION_CYCLE — emitted in PR comments

Source: `templates/resolution-comment.md`. Reports the disposition of cycle `N`'s findings.

```
<!-- FLOW_RESOLUTION_CYCLE:{N} RESOLVED:[{ID},{ID}] ESCALATED:[{ID}] DISPUTED:[{ID}] -->
```

Arrays carry IDs only; priority must be looked up from the matching `FLOW_REVIEW_CYCLE`.

## Finding State Classification

For a single PR, after reading the **latest** marker of each kind:

| State | Definition |
|-------|------------|
| `resolved` | ID appears in `RESOLVED` |
| `escalated` | ID appears in `ESCALATED` |
| `disputed` | ID appears in `DISPUTED` |
| `in_fix_forward` | ID appears in `FINDINGS` but in none of the resolution arrays |
| `unknown_priority` | ID appears in a resolution array but is missing from `FINDINGS` (defensive — log, do not error) |

## Canonical Queries

### 1. Enumerate user's open PRs (author OR assignee)

```bash
ME=$(gh api user --jq '.login')
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')

PRS=$(gh pr list --state open --limit 100 --json number,author,assignees \
  | jq -r --arg me "$ME" \
    '[.[] | select(.author.login == $me or (.assignees[].login? == $me))] | .[].number')
```

### 2. Extract latest FLOW_REVIEW_CYCLE FINDINGS for one PR

```bash
PR_NUM=42
REVIEW_BODY=$(gh api "repos/$REPO/pulls/$PR_NUM/reviews" \
  --jq '[.[] | select(.body | test("FLOW_REVIEW_CYCLE:"))] | last | .body // ""')
# Portable extraction (POSIX grep + sed — works on BSD/macOS and GNU/Linux).
# Avoids `grep -P` / `\K` which BSD grep does not support.
FINDINGS_RAW=$(echo "$REVIEW_BODY" | grep -o 'FINDINGS:\[[^]]*\]' | sed 's/^FINDINGS:\[//;s/\]$//' || echo "")
# FINDINGS_RAW like: F1|P1|security|src/auth.ts:42|open,F2|P2|correctness|src/api.ts:88|open
```

### 3. Extract latest FLOW_RESOLUTION_CYCLE arrays for one PR

```bash
RESOLUTION_BODY=$(gh api "repos/$REPO/issues/$PR_NUM/comments" \
  --jq '[.[] | select(.body | test("FLOW_RESOLUTION_CYCLE:"))] | last | .body // ""')

RESOLVED=$(echo "$RESOLUTION_BODY"  | grep -o 'RESOLVED:\[[^]]*\]'  | sed 's/^RESOLVED:\[//;s/\]$//'  || echo "")
ESCALATED=$(echo "$RESOLUTION_BODY" | grep -o 'ESCALATED:\[[^]]*\]' | sed 's/^ESCALATED:\[//;s/\]$//' || echo "")
DISPUTED=$(echo "$RESOLUTION_BODY"  | grep -o 'DISPUTED:\[[^]]*\]'  | sed 's/^DISPUTED:\[//;s/\]$//'  || echo "")
```

### 4. Aggregate counts by priority and state

```bash
# For each finding in FINDINGS_RAW:
#   parse ID and priority (fields 1 and 2, pipe-delimited)
#   classify: in RESOLVED? -> skip. in ESCALATED? -> escalated. in DISPUTED? -> disputed. else -> in_fix_forward.
#   bump count[priority][state]
#
# Empty FINDINGS_RAW (no markers on this PR) contributes zero.
# Empty RESOLUTION arrays mean every finding is in_fix_forward.

echo "$FINDINGS_RAW" | tr ',' '\n' | while IFS='|' read -r ID PRIORITY CAT LOC STATUS; do
  [ -z "$ID" ] && continue
  # Defensive: skip rows that don't conform to ID|P[1-3]|... schema (older or
  # experimental marker formats from prior workflow versions).
  case "$PRIORITY" in P1|P2|P3) ;; *) continue ;; esac
  case ",$RESOLVED," in *",$ID,"*) continue ;; esac   # resolved -> skip
  case ",$ESCALATED," in *",$ID,"*) STATE=escalated ;;
       *) case ",$DISPUTED," in *",$ID,"*) STATE=disputed ;; *) STATE=in_fix_forward ;; esac ;;
  esac
  echo "$PRIORITY $STATE"
done
```

## Failure Modes

| Condition | Behavior |
|-----------|----------|
| `gh` API timeout / unauthenticated | Skip ledger; render "Findings Ledger unavailable" with one-line cause |
| PR with no review markers | Contributes zero findings; not an error |
| Malformed marker (regex match fails) | Skip that PR; do not error |
| Resolution arrays reference IDs missing from FINDINGS | Counted as `unknown_priority`; log and continue |
| No open PRs for user | Render "No open findings" empty state |

## Render Format

The Findings Ledger section uses a single-line summary that matches `docs/flow-team-session/slides.md` lines 802-810:

```
P1: {n}    P2: {n} (in fix-forward)    P3: {n} (ESCALATED — awaiting reviewer accept)
```

Annotation rules:

- Bare `P{n}: 0` — no findings at this priority.
- `P{n}: K (in fix-forward)` — K findings raised but not yet resolved or escalated.
- `P{n}: K (ESCALATED — {short context})` — K findings sitting in `ESCALATED`.
- `P{n}: K (DISPUTED)` — K findings in `DISPUTED`.
- Multiple states at one priority combine with `; ` separator: `P2: 3 (2 in fix-forward; 1 ESCALATED)`.

Empty state (no PRs or no findings across all PRs):

```
No open findings.
```

## Consumers

- `commands/status.md` — Findings Ledger section in `/flow:status` output.
- `commands/merge.md` — finding-ledger check in `/flow:merge`'s prerequisite gate (uses subset: ESCALATED non-empty, FINDINGS without matching RESOLVED).
