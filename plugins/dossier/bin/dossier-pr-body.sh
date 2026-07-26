#!/usr/bin/env bash
# dossier-pr-body.sh — render the body of the documentation pull request.
#
# The rolling branch carries one pull request across many source merges, so the
# body is cumulative: each run appends a row to the source-PR table instead of
# replacing it. Without that, the body would describe only the most recent run
# while the diff described all of them, and a reviewer would have no way to see
# which merges the pending documentation change actually covers.
#
# Usage:
#   dossier-pr-body.sh --out <file> [--existing-pr <n>] [--previous-body <file>]
#                      [--evidence <dir>]
#
# Flags:
#   --out <file>            write the rendered body here (required)
#   --existing-pr <n>       number of the pull request being updated. Its body is
#                           read back so the source-PR table survives.
#   --previous-body <file>  use this instead of querying the API for the body
#   --evidence <dir>        evidence bundle, used for the range and PR list
#
# Environment (all optional; the bundle wins where both are present):
#   DOSSIER_BASE_SHA DOSSIER_HEAD_SHA DOSSIER_BASE_REF DOSSIER_DOCS_BRANCH
#   DOSSIER_RUN_URL DOSSIER_SOURCE_PR DOSSIER_SOURCE_PR_TITLE
#   DOSSIER_SIZE_CLASS DOSSIER_FILES_CHANGED DOSSIER_LINES_CHANGED
#   DOSSIER_BASE_SOURCE DOSSIER_POLICY_REASON DOSSIER_DOCS_DIR
#
# Exit:
#   0 — body written
#   1 — the previous body was required and could not be read
#   2 — missing or invalid argument

set -uo pipefail

OUT=""
EXISTING_PR=""
PREVIOUS_BODY=""
EVIDENCE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --out)           [ $# -lt 2 ] && { echo "dossier-pr-body: --out requires a value" >&2; exit 2; }; OUT="$2"; shift 2 ;;
    --existing-pr)   [ $# -lt 2 ] && { echo "dossier-pr-body: --existing-pr requires a value" >&2; exit 2; }; EXISTING_PR="$2"; shift 2 ;;
    --previous-body) [ $# -lt 2 ] && { echo "dossier-pr-body: --previous-body requires a value" >&2; exit 2; }; PREVIOUS_BODY="$2"; shift 2 ;;
    --evidence)      [ $# -lt 2 ] && { echo "dossier-pr-body: --evidence requires a value" >&2; exit 2; }; EVIDENCE="$2"; shift 2 ;;
    -h|--help)       sed -n '2,33p' "$0"; exit 0 ;;
    *) echo "dossier-pr-body: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$OUT" ] || { echo "dossier-pr-body: --out is required" >&2; exit 2; }
case "${EXISTING_PR:-0}" in
  ''|*[!0-9]*) [ -n "$EXISTING_PR" ] && { echo "dossier-pr-body: --existing-pr must be a number" >&2; exit 2; } ;;
esac

BASE_SHA="${DOSSIER_BASE_SHA:-}"
HEAD_SHA="${DOSSIER_HEAD_SHA:-}"
BASE_REF="${DOSSIER_BASE_REF:-}"
DOCS_BRANCH="${DOSSIER_DOCS_BRANCH:-docs/dossier}"
RUN_URL="${DOSSIER_RUN_URL:-}"
SOURCE_PR="${DOSSIER_SOURCE_PR:-}"
SOURCE_PR_TITLE="${DOSSIER_SOURCE_PR_TITLE:-}"
SIZE_CLASS="${DOSSIER_SIZE_CLASS:-ok}"
FILES_CHANGED="${DOSSIER_FILES_CHANGED:-0}"
LINES_CHANGED="${DOSSIER_LINES_CHANGED:-0}"
BASE_SOURCE="${DOSSIER_BASE_SOURCE:-}"
POLICY_REASON="${DOSSIER_POLICY_REASON:-}"

TABLE_START='<!-- dossier:source-pr-table:start -->'
TABLE_END='<!-- dossier:source-pr-table:end -->'
MAX_TABLE_ROWS=50

# Untrusted text reaches this file from pull request titles. Control characters
# are removed because they corrupt a rendered body in ways that are invisible in
# review, and pipes are escaped because an unescaped one silently breaks the
# table into a shape that no longer says what it appears to say.
sanitize() {
  printf '%s' "${1:-}" \
    | LC_ALL=C tr -cd '[:print:][:space:]' \
    | tr '\r\n\t' '   ' \
    | sed -e 's/|/\\|/g' -e 's/\[/\\[/g' -e 's/\]/\\]/g' -e 's/`/\\`/g' \
          -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | cut -c1-120
}

short() { printf '%s' "${1:-}" | cut -c1-8; }

# ---------------------------------------------------------------------------
# Bundle-derived facts take precedence: they were computed from git, whereas the
# environment carries whatever the workflow chose to pass through.
# ---------------------------------------------------------------------------
PR_LIST=""
CHANGED_FILES=""
COMMITS=""
TRUNCATED=""
if [ -n "$EVIDENCE" ] && [ -f "$EVIDENCE/manifest.json" ] && command -v jq >/dev/null 2>&1; then
  MB=$(jq -r '.range.base // empty' "$EVIDENCE/manifest.json" 2>/dev/null); [ -n "$MB" ] && BASE_SHA="$MB"
  MH=$(jq -r '.range.head // empty' "$EVIDENCE/manifest.json" 2>/dev/null); [ -n "$MH" ] && HEAD_SHA="$MH"
  CHANGED_FILES=$(jq -r '.counts.changed_files // empty' "$EVIDENCE/manifest.json" 2>/dev/null)
  COMMITS=$(jq -r '.counts.commits // empty' "$EVIDENCE/manifest.json" 2>/dev/null)
  TRUNCATED=$(jq -r '.source_diff.truncated // false' "$EVIDENCE/manifest.json" 2>/dev/null)
  if [ -f "$EVIDENCE/pull-requests.json" ]; then
    PR_LIST=$(jq -r '.[] | "#\(.number) \(.title // "")"' "$EVIDENCE/pull-requests.json" 2>/dev/null | head -20)
  fi
  if [ -z "$SOURCE_PR" ] && [ -f "$EVIDENCE/source-pr.json" ]; then
    SOURCE_PR=$(jq -r 'if . == null then "" else (.number | tostring) end' "$EVIDENCE/source-pr.json" 2>/dev/null)
    SOURCE_PR_TITLE=$(jq -r 'if . == null then "" else (.title // "") end' "$EVIDENCE/source-pr.json" 2>/dev/null)
  fi
fi

# ---------------------------------------------------------------------------
# Carry the existing table forward.
# ---------------------------------------------------------------------------
PREVIOUS_ROWS=""
if [ -n "$EXISTING_PR" ]; then
  BODY_SRC=""
  if [ -n "$PREVIOUS_BODY" ] && [ -f "$PREVIOUS_BODY" ]; then
    BODY_SRC=$(cat "$PREVIOUS_BODY" 2>/dev/null)
  elif command -v gh >/dev/null 2>&1; then
    BODY_SRC=$(gh pr view "$EXISTING_PR" --json body --jq '.body // ""' 2>/dev/null)
    if [ -z "$BODY_SRC" ]; then
      # Refusing here rather than writing a fresh body: overwriting the pull
      # request description would silently erase the record of which merges the
      # accumulated documentation change already covers.
      echo "dossier-pr-body: could not read the body of pull request #${EXISTING_PR}; refusing to overwrite it with a partial history." >&2
      exit 1
    fi
  else
    echo "dossier-pr-body: --existing-pr was given but neither --previous-body nor the gh CLI is available." >&2
    exit 1
  fi
  PREVIOUS_ROWS=$(printf '%s\n' "$BODY_SRC" \
    | awk -v s="$TABLE_START" -v e="$TABLE_END" '
        $0 == s { inside = 1; next }
        $0 == e { inside = 0; next }
        inside && /^\|/ && $0 !~ /^\|---/ && $0 !~ /^\| Source PR/ { print }
      ')
fi

NEW_ROW=$(printf '| %s | %s | `%s..%s` | %s |' \
  "$([ -n "$SOURCE_PR" ] && printf '#%s' "$SOURCE_PR" || printf 'sweep')" \
  "$(sanitize "$SOURCE_PR_TITLE")" \
  "$(short "$BASE_SHA")" "$(short "$HEAD_SHA")" \
  "$([ -n "$RUN_URL" ] && printf '[run](%s)' "$RUN_URL" || printf 'n/a')")

ALL_ROWS=$(printf '%s\n%s\n' "$PREVIOUS_ROWS" "$NEW_ROW" | grep -E '^\| ' )
ROW_COUNT=$(printf '%s\n' "$ALL_ROWS" | grep -c . | tr -d ' ')
[ -n "$ROW_COUNT" ] || ROW_COUNT=0
ELIDED=0
if [ "$ROW_COUNT" -gt "$MAX_TABLE_ROWS" ]; then
  ELIDED=$((ROW_COUNT - MAX_TABLE_ROWS))
  ALL_ROWS=$(printf '%s\n' "$ALL_ROWS" | tail -n "$MAX_TABLE_ROWS")
fi

mkdir -p "$(dirname "$OUT")" 2>/dev/null

{
  printf '## Documentation refresh\n\n'
  printf 'This pull request keeps the documentation package under `%s` in step with\n' "${DOSSIER_DOCS_DIR:-docs/dossier}"
  printf 'what has actually merged. It was opened and is maintained by the dossier\n'
  printf 'refresh job; every commit on it carries a `Dossier-Generated: true` trailer.\n\n'

  printf '### What changed\n\n'
  printf '| Field | Value |\n|---|---|\n'
  printf '| Documented range | `%s..%s` |\n' "$(short "$BASE_SHA")" "$(short "$HEAD_SHA")"
  [ -n "$COMMITS" ]       && printf '| Source commits | %s |\n' "$COMMITS"
  [ -n "$CHANGED_FILES" ] && printf '| Source files changed | %s |\n' "$CHANGED_FILES"
  printf '| Documentation files changed | %s |\n' "$FILES_CHANGED"
  printf '| Documentation lines changed | %s |\n' "$LINES_CHANGED"
  [ -n "$BASE_REF" ]      && printf '| Target branch | `%s` |\n' "$BASE_REF"
  printf '| Documentation branch | `%s` |\n' "$DOCS_BRANCH"
  [ -n "$BASE_SOURCE" ]   && printf '| Watermark source | `%s` |\n' "$BASE_SOURCE"
  [ -n "$POLICY_REASON" ] && printf '| Policy decision | `%s` |\n' "$POLICY_REASON"
  printf '\n'

  printf '### Why\n\n'
  printf 'A documentation package that looks current but is not is worse than one that\n'
  printf 'is visibly stale, because a reader trusts it. The refresh runs on every merge\n'
  printf 'that touches a watched path, plus a scheduled sweep for whatever the path\n'
  printf 'filters missed, and rewrites only the documents the change actually reaches.\n\n'

  if [ "$SIZE_CLASS" = "oversized" ]; then
    printf '> **Oversized change — opened as a draft.**\n'
    printf '> This refresh rewrites %s files and %s lines, past the configured ceilings.\n' "$FILES_CHANGED" "$LINES_CHANGED"
    printf '> That is expected for a cold start or a large refactor, so the work is kept\n'
    printf '> rather than discarded. Read it more closely than a routine refresh, and\n'
    printf '> mark the pull request ready when you are satisfied.\n\n'
  fi

  if [ "$TRUNCATED" = "true" ]; then
    printf '> **Note.** The source diff exceeded the evidence cap and was truncated. The\n'
    printf '> refresh read the affected files directly from the checkout instead, which\n'
    printf '> reflects the merged state exactly.\n\n'
  fi

  printf '### Source pull requests documented on this branch\n\n'
  printf '%s\n' "$TABLE_START"
  printf '| Source PR | Title | Range | Run |\n'
  printf '|---|---|---|---|\n'
  printf '%s\n' "$ALL_ROWS"
  printf '%s\n' "$TABLE_END"
  if [ "$ELIDED" -gt 0 ]; then
    printf '\n_%s earlier rows elided. `git log --grep %s` on this branch has the complete record._\n' \
      "$ELIDED" "'Dossier-Source-PR'"
  fi
  printf '\n'

  if [ -n "$PR_LIST" ]; then
    printf '<details>\n<summary>Pull requests in this run'"'"'s range</summary>\n\n'
    printf '%s\n' "$PR_LIST" | while IFS= read -r L; do
      [ -n "$L" ] || continue
      printf -- '- %s\n' "$(sanitize "$L")"
    done
    printf '\n</details>\n\n'
  fi

  printf '### Reviewer checklist\n\n'
  printf -- '- [ ] Every changed statement is supported by something in the merged range, not by plausibility.\n'
  printf -- '- [ ] Claim states are honest: what is implemented, what is planned, what is unknown.\n'
  printf -- '- [ ] Nothing in `06-public/` says more than the claim register approves.\n'
  printf -- '- [ ] No secret, internal hostname, customer name or repository path leaked into a public document.\n'
  printf -- '- [ ] `last verified` dates moved only on documents this range actually touched.\n'
  printf -- '- [ ] Documents the change should have reached but did not are noted below.\n\n'

  printf '### Provenance\n\n'
  if [ -n "$RUN_URL" ]; then
    printf -- '- Workflow run: %s\n' "$RUN_URL"
  fi
  printf -- '- Every commit carries `Dossier-Generated`, `Dossier-Range`, `Dossier-Source-PR` and `Dossier-Run` trailers.\n'
  printf -- '- `git log --grep '"'"'Dossier-Source-PR: #N'"'"'` answers what a given source pull request changed here.\n'
  printf -- '- The agent that wrote these files held no write token; this branch was produced by a separate job from a validated patch.\n'
} >"$OUT"

printf 'body_file=%s\n' "$OUT"
printf 'rows=%s\n' "$(printf '%s\n' "$ALL_ROWS" | grep -c . | tr -d ' ')"
printf 'size_class=%s\n' "$SIZE_CLASS"
exit 0
