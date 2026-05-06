# Finding Ledger Parser

Canonical reference for extracting and classifying review findings across one or more pull requests. Used by `/flow:status` (Findings Ledger section) and `/flow:merge` (merge-blocking finding-ledger check).

## Trust Boundary

Markers are extracted from PR reviews and PR conversation comments. Both surfaces are reachable by **any GitHub user with comment access** on a public repo — drive-by accounts can submit `COMMENT`-state reviews, and anyone can post issue comments. A forged `<!-- FLOW_RESOLUTION_CYCLE:N RESOLVED:[F1,F2,...] ESCALATED:[] DISPUTED:[] -->` from an untrusted account would otherwise let an attacker bypass the merge gate.

To prevent this, both consumers (`/flow:status` and `/flow:merge`) filter markers by GitHub's `author_association` field before honoring them. The default trust list is `["OWNER", "MEMBER", "COLLABORATOR"]`, configurable via `settings.json` → `merge.markerTrust.allowedAssociations`.

`/flow:merge` additionally surfaces an explicit `FINDING_LEDGER_BLOCK: ... no trusted authors` reason when markers exist but none come from trusted sources, rather than silently treating the PR as marker-free (which would fail open).

## Marker Schemas

Two HTML-comment markers carry the finding state. They are emitted by review and resolution templates and are the only ledger source-of-truth. Markers from untrusted authors are ignored — see Trust Boundary above.

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
| `malformed` | Row in `FINDINGS` doesn't conform to `ID|P[1-3]|...` schema (legacy/experimental marker formats — emit `LEDGER_WARN` to stderr and skip) |

**Precedence** when the same ID appears in multiple resolution arrays: `RESOLVED` > `ESCALATED` > `DISPUTED`. Resolution wins; the finding is treated as fully closed.

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

Trust filter applied: only reviews from authors in the configured trust list count. Without this, anyone able to submit a `COMMENT`-state review could forge findings.

```bash
PR_NUM=42
# TRUST_REGEX="OWNER|MEMBER|COLLABORATOR" (built from settings; see consumers).
REVIEW_BODY=$(gh api "repos/$REPO/pulls/$PR_NUM/reviews" \
  --jq "[.[] | select((.author_association | test(\"^($TRUST_REGEX)\$\")) and (.body | test(\"FLOW_REVIEW_CYCLE:\")))] | last | .body // \"\"")
# Portable extraction (POSIX grep + sed — works on BSD/macOS and GNU/Linux).
# Avoids `grep -P` / `\K` which BSD grep does not support.
# Empty input + grep no-match still produces empty stdout (sed exits 0 on empty),
# so no `|| echo ""` fallback is needed here.
FINDINGS_RAW=$(echo "$REVIEW_BODY" | grep -o 'FINDINGS:\[[^]]*\]' | sed 's/^FINDINGS:\[//;s/\]$//')
# FINDINGS_RAW like: F1|P1|security|src/auth.ts:42|open,F2|P2|correctness|src/api.ts:88|open
```

### 3. Extract latest FLOW_RESOLUTION_CYCLE arrays for one PR

```bash
RESOLUTION_BODY=$(gh api "repos/$REPO/issues/$PR_NUM/comments" \
  --jq "[.[] | select((.author_association | test(\"^($TRUST_REGEX)\$\")) and (.body | test(\"FLOW_RESOLUTION_CYCLE:\")))] | last | .body // \"\"")

# Strip whitespace so reviewer-edited arrays like `[F1, F2]` still match the
# `,F1,` containment check used in classification.
RESOLVED=$(echo "$RESOLUTION_BODY"  | grep -o 'RESOLVED:\[[^]]*\]'  | sed 's/^RESOLVED:\[//;s/\]$//'  | tr -d ' ')
ESCALATED=$(echo "$RESOLUTION_BODY" | grep -o 'ESCALATED:\[[^]]*\]' | sed 's/^ESCALATED:\[//;s/\]$//' | tr -d ' ')
DISPUTED=$(echo "$RESOLUTION_BODY"  | grep -o 'DISPUTED:\[[^]]*\]'  | sed 's/^DISPUTED:\[//;s/\]$//'  | tr -d ' ')
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

# NOTE: this snippet expects the caller to have set $PR_NUM (PR number being
# processed) in scope; LEDGER_WARN messages reference it for traceability.
# Sanitize attacker-controlled fields before logging (strip non-printable
# bytes, cap length) so hostile review-body content can't inject ANSI escapes.
safe() { printf '%s' "$1" | tr -cd '[:print:]' | cut -c1-64; }
echo "$FINDINGS_RAW" | tr ',' '\n' | while IFS='|' read -r ID PRIORITY CAT LOC STATUS; do
  [ -z "$ID" ] && continue
  # Reject IDs that don't match [A-Za-z][A-Za-z0-9_-]*. Required because the
  # containment checks below use POSIX `case` glob — an ID of `*` would
  # spuriously match every RESOLVED list and silently disappear from the tally.
  case "$ID" in [A-Za-z]*) ;; *) echo "LEDGER_WARN: PR#$PR_NUM finding '$(safe "$ID")' rejected (non-conforming ID)" >&2; continue ;; esac
  case "$ID" in *[!A-Za-z0-9_-]*) echo "LEDGER_WARN: PR#$PR_NUM finding '$(safe "$ID")' rejected (non-conforming ID)" >&2; continue ;; esac
  case "$PRIORITY" in
    P1|P2|P3) ;;
    *) echo "LEDGER_WARN: PR#$PR_NUM finding '$(safe "$ID")' has malformed priority '$(safe "$PRIORITY")'" >&2; continue ;;
  esac
  # Precedence: RESOLVED > ESCALATED > DISPUTED > in_fix_forward.
  case ",$RESOLVED," in *",$ID,"*) continue ;; esac
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
| PR with markers but none from trusted authors | `/flow:status`: contributes zero (display only). `/flow:merge`: emits `FINDING_LEDGER_BLOCK: ... no trusted authors` to fail closed. |
| Malformed marker (regex match fails) | Skip that PR; do not error |
| FINDINGS row missing pipe-delimited priority field | Emit `LEDGER_WARN` to stderr; skip that row |
| Resolution arrays reference IDs missing from FINDINGS | Not iterated (loop walks FINDINGS only); resolution-only IDs are silently inert |
| No open PRs for user | Render "No open findings" empty state |

## Render Format

The Findings Ledger section uses a single-line summary that matches the slide mockup in `docs/flow-team-session/slides.md`:

```
P1: {n}    P2: {n} (in fix-forward)    P3: {n} (ESCALATED)
```

Annotation rules:

- Bare `P{n}: 0` — no findings at this priority (no annotation).
- `P{n}: K (in fix-forward)` — K findings raised but not yet resolved or escalated.
- `P{n}: K (ESCALATED)` — K findings sitting in `ESCALATED`.
- `P{n}: K (DISPUTED)` — K findings in `DISPUTED`.
- Multiple states at one priority combine with `; ` separator: `P2: 3 (2 in fix-forward; 1 ESCALATED)`.

The marker schema carries no per-finding context string, so trailing free-text annotations (e.g., "— awaiting reviewer accept") are not part of the contract — adding them requires a schema extension.

Empty state (no PRs or no findings across all PRs):

```
No open findings.
```

## Consumers

- `commands/status.md` — Findings Ledger section in `/flow:status` output.
- `commands/merge.md` — finding-ledger check in `/flow:merge`'s prerequisite gate (uses subset: ESCALATED non-empty, FINDINGS without matching RESOLVED).
