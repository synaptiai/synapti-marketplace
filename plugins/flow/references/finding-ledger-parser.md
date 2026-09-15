# Finding Ledger Parser

Canonical reference for extracting and classifying review findings across one or more pull requests. Used by `/flow:status` (Findings Ledger section) and `/flow:merge` (merge-blocking finding-ledger check).

## Trust Boundary

Markers are extracted from PR reviews and PR conversation comments. Both surfaces are reachable by **any GitHub user with comment access** on a public repo — drive-by accounts can submit `COMMENT`-state reviews, and anyone can post issue comments. A forged `<!-- FLOW_RESOLUTION_CYCLE:N RESOLVED:[F1,F2,...] ESCALATED:[] DISPUTED:[] -->` from an untrusted account would otherwise let an attacker bypass the merge gate.

To prevent this, both consumers (`/flow:status` and `/flow:merge`) filter markers by GitHub's `author_association` field before honoring them. The default trust list is `["OWNER", "MEMBER", "COLLABORATOR"]`, configurable via `plugins/flow/settings.json` → `merge.markerTrust.allowedAssociations`.

**Pinned to plugin tier — does NOT use the standard settings cascade.** A hostile fork PR could otherwise commit `.claude/settings.flow.local.json` with a permissive trust list; after `gh pr checkout`, the cascade would honor the attacker's file and disable this defense. Settings cascade for non-security keys is documented in `gate-configuration.md`.

`/flow:merge` additionally surfaces an explicit `FINDING_LEDGER_BLOCK: ... no trusted authors` reason when markers exist but none come from trusted sources, rather than silently treating the PR as marker-free (which would fail open).

This filter trusts the configured association levels uniformly. It does not protect against malicious or compromised accounts already inside the trust boundary; rely on GitHub branch protection and CODEOWNERS to constrain who can review. `author_association` is also evaluated at read time, not write time — comments from a former MEMBER who has since been removed will still show MEMBER.

## Marker Schemas

Two HTML-comment markers carry the finding state. The review-cycle marker is appended by the posting block in `commands/review.md` Phase 4 step 7 from the rows `bin/flow-finding-route.sh` prints; the resolution marker ends the resolution comment built from `templates/resolution-comment.md`. They are the only ledger source-of-truth. Markers from untrusted authors are ignored — see Trust Boundary above.

### FLOW_REVIEW_CYCLE — emitted in PR review bodies

Source: `commands/review.md` Phase 4 step 7 (the review templates carry no marker). Lists every counted finding raised in cycle `N` with its priority and location.

```
<!-- FLOW_REVIEW_CYCLE:{N} FINDINGS:[{ID}|{priority}|{category}|{file:line}|{status}[|{confidence}|{disposition}],...] -->
```

| Field | Values | Required |
|-------|--------|----------|
| `ID` | Finding identifier (e.g., `F1`, `F12`) | yes |
| `priority` | `P1` \| `P2` \| `P3` | yes |
| `category` | Free text (e.g., `security`, `correctness`, `convention`) | yes |
| `file:line` | Location citation | yes |
| `status` | `open` at review time | yes |
| `confidence` | `HIGH` \| `MEDIUM` \| `LOW` (`LOW` appears only in markers posted before the routing rule below) | written on both review paths; absent in legacy rows |
| `disposition` | `consensus` \| `validated` \| `refined` \| `kept` \| `unchallenged` | written on both review paths; absent in legacy rows |

**Backwards-compat rule (mandatory for parsers):** Readers MUST tolerate variable field count. The legacy 5-field row `ID|P1|category|file:line|open` and the extended 7-field row `ID|P1|category|file:line|open|HIGH|consensus` MUST both parse successfully. Trailing fields beyond the parser's known set are silently ignored (or surfaced for display when the parser knows them).

`commands/review.md` writes the 7-field form on both Path A (paired reviewers) and Path B (single session, disposition `unchallenged`), through `bin/flow-finding-route.sh`. No LOW row is written: on someone else's pull request a LOW finding is listed under Needs investigation instead, and on the author's own pull request it is confirmed (re-recorded HIGH), refuted (dropped) or escalated (re-recorded MEDIUM) before the marker is built. Legacy 5-field rows in markers posted before this rule still parse.

In `category` and `location` the emitter percent-encodes every byte outside `[A-Za-z0-9._~/:@+= -]`: `app/[id]/page.tsx:4` is written `app/%5Bid%5D/page.tsx:4`, and a comma, `]`, `|` or `>` becomes `%2C`, `%5D`, `%7C` or `%3E`, so no value can split a row or end the marker. Parsers read only `ID` and `priority`; decode the other two only for display.

**Disposition vocabulary is fixed (no free text)** — the field is parsed positionally and must not contain commas (the row delimiter) or pipes (the field delimiter). The five values above are the complete v1 vocabulary; new values require a schema bump.

**Vocabulary is enforced on both sides.** The emitter, `bin/flow-finding-route.sh`, rejects a row whose ID or priority fails the allowlist, rewrites an out-of-vocabulary disposition to `unchallenged` with a `LEDGER_WARN`, and encodes category and location as above; the posting block also refuses a review body that quotes `FINDINGS:[`, `RESOLVED:[`, `ESCALATED:[` or `DISPUTED:[`. If a trusted reviewer (the only kind whose markers reach parsing — see Trust Boundary above) hand-edits a posted marker afterwards and inserts an out-of-vocabulary disposition or injects extra rows via embedded `]`/`,`, the consumer parsers still degrade safely:

- `grep -o 'FINDINGS:\[[^]]*\]'` (used by `status.md`, `merge.md`, `tests/issue-86/verify.sh`) terminates at the first unescaped `]`, truncating any row containing one. The truncated row then fails the consumer's ID/priority allowlist (`[A-Za-z][A-Za-z0-9_-]*` for IDs, `P1|P2|P3` for priority) and is rejected with a `LEDGER_WARN` to stderr.
- A comma in disposition splits into a phantom row that is similarly caught by the ID/priority allowlists.
- Out-of-vocabulary dispositions parse without error but carry no semantic meaning to consumers (the field is currently display-only — only `ID` and `PRIORITY` reach merge-gate logic).

The consumer allowlists and grep truncation stay the backstop for a marker edited after it was posted.

### FLOW_RESOLUTION_CYCLE — emitted in PR comments

Source: `templates/resolution-comment.md`. Reports the disposition of cycle `N`'s findings.

```
<!-- FLOW_RESOLUTION_CYCLE:{N} RESOLVED:[{ID},{ID}] ESCALATED:[{ID}] DISPUTED:[{ID}] -->
```

Arrays carry IDs only; priority must be looked up from the matching `FLOW_REVIEW_CYCLE`.

**Two emitters, one mechanism.** This marker is emitted by both paths that close findings:

- **Two-actor flow** — `/flow:address` (`commands/address.md` step 9) posts it after the PR author
  resolves a reviewer's findings.
- **Self-review / fix-forward** — `/flow:review` on your *own*
  PR posts it too (`commands/review.md` Phase 4 step 7, self-review branch). Self-review is raise +
  resolve in one action: the `FLOW_REVIEW_CYCLE` marker in the review body records what was found
  (status `open`), and this `FLOW_RESOLUTION_CYCLE` issue comment records the fix-forwarded IDs as
  `RESOLVED`. Without it, a solo/agent-authored PR whose every finding was fixed in-PR would
  false-block at the merge finding-ledger gate (it reads `RESOLVED` only from this marker, never from
  an inline `FLOW_REVIEW_CYCLE` status field).

In both cases the marker lands in the **issue-comments stream** (`gh pr comment`) — never a review
body — so the merge gate's resolution query (§3 below) finds it regardless of which command emitted it.

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

Trust filter applied via jq's `index()` exact-match (no regex injection surface). `--paginate` keeps fetching pages so a noisy thread can't hide forgeries past the default 30-item cutoff.

```bash
PR_NUM=42
# TRUST_LIST is a JSON array like ["OWNER","MEMBER","COLLABORATOR"], read by
# the consumer from plugin settings.
REVIEW_BODY=$(gh api --paginate "repos/$REPO/pulls/$PR_NUM/reviews" \
  | jq -s -r --argjson trust "$TRUST_LIST" \
      'add | [.[] | select((.author_association as $a | $trust | index($a)) and (.body | test("FLOW_REVIEW_CYCLE:")))] | last | .body // ""')
# Portable extraction (POSIX grep + sed — works on BSD/macOS and GNU/Linux).
# Avoids `grep -P` / `\K` which BSD grep does not support.
# Empty input + grep no-match still produces empty stdout (sed exits 0 on empty),
# so no `|| echo ""` fallback is needed here.
FINDINGS_RAW=$(echo "$REVIEW_BODY" | grep -o 'FINDINGS:\[[^]]*\]' | sed 's/^FINDINGS:\[//;s/\]$//')
# FINDINGS_RAW like: F1|P1|security|src/auth.ts:42|open,F2|P2|correctness|src/api.ts:88|open
```

### 3. Extract latest FLOW_RESOLUTION_CYCLE arrays for one PR

```bash
RESOLUTION_BODY=$(gh api --paginate "repos/$REPO/issues/$PR_NUM/comments" \
  | jq -s -r --argjson trust "$TRUST_LIST" \
      'add | [.[] | select((.author_association as $a | $trust | index($a)) and (.body | test("FLOW_RESOLUTION_CYCLE:")))] | last | .body // ""')

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
