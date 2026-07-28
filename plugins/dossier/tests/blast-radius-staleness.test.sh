#!/usr/bin/env bash
# dossier-blast-radius.sh --stale-docs: the fourth blast-radius membership
# criterion (documents/refresh.md Phase 2) — a document named by the schedule
# sweep belongs in the affected set even when no changed file reaches it.
# Class "stale" (not "matched") is how Phase 4 knows to run a verification
# pass instead of a redraft (issue #135 AC #2).

_dossier_test_begin "blast-radius-staleness"

SCRIPT="plugins/dossier/bin/dossier-blast-radius.sh"

if [ ! -x "$SCRIPT" ]; then
  _dossier_assert_fail "$SCRIPT missing or not executable"
  _dossier_test_summary
  return 0 2>/dev/null || exit 0
fi

FIXTURE=$(mktemp -d "$RUN_TMPDIR/blast-radius-staleness.XXXXXX")

# A changed-files list that matches nothing in the event matrix, so the only
# documents in the result (absent --stale-docs) are the four "always" docs.
CHANGED="$FIXTURE/changed-files.txt"
printf 'some/unmatched/path.xyz\n' >"$CHANGED"

OUT="$FIXTURE/blast-radius.json"
"$SCRIPT" --changed-files "$CHANGED" --out "$OUT" \
  --stale-docs "02-architecture/system-architecture.md,04-operating/onboarding-and-local-development.md" >/dev/null 2>&1

assert_file_exists "$OUT" "blast-radius.json was written"

STALE_DOC_CLASS=$(jq -r '.documents[] | select(.path=="02-architecture/system-architecture.md") | .class' "$OUT" 2>/dev/null)
assert_equal "stale" "$STALE_DOC_CLASS" "a stale-only document gets class=stale, not matched"

STALE_DOC_REASONS=$(jq -r '.documents[] | select(.path=="02-architecture/system-architecture.md") | .reasons | join(",")' "$OUT" 2>/dev/null)
assert_equal "stale" "$STALE_DOC_REASONS" "a stale-only document's reasons array is exactly [\"stale\"]"

SECOND_DOC_CLASS=$(jq -r '.documents[] | select(.path=="04-operating/onboarding-and-local-development.md") | .class' "$OUT" 2>/dev/null)
assert_equal "stale" "$SECOND_DOC_CLASS" "the second stale-only document also gets class=stale"

ALWAYS_DOC_CLASS=$(jq -r '.documents[] | select(.path=="00-control/documentation-index.md") | .class' "$OUT" 2>/dev/null)
assert_equal "always" "$ALWAYS_DOC_CLASS" "an always-doc keeps class=always even when --stale-docs is passed"

# --- Precedence: a doc that is BOTH event-matched and stale-listed stays
# "matched" — the sweep must never downgrade a genuinely change-driven
# document to the lighter verification-only treatment.
CHANGED2="$FIXTURE/changed-files-2.txt"
printf 'src/api/handler.go\n' >"$CHANGED2"
OUT2="$FIXTURE/blast-radius-2.json"
"$SCRIPT" --changed-files "$CHANGED2" --out "$OUT2" \
  --stale-docs "02-architecture/system-architecture.md" >/dev/null 2>&1

MIXED_CLASS=$(jq -r '.documents[] | select(.path=="02-architecture/system-architecture.md") | .class' "$OUT2" 2>/dev/null)
assert_equal "matched" "$MIXED_CLASS" "a document that is both event-matched and stale-listed stays class=matched (event wins)"

MIXED_REASONS=$(jq -r '.documents[] | select(.path=="02-architecture/system-architecture.md") | .reasons | sort | join(",")' "$OUT2" 2>/dev/null)
assert_contains "stale" "$MIXED_REASONS" "the mixed document's reasons still record that it was also stale"
assert_contains "product-capability" "$MIXED_REASONS" "the mixed document's reasons still record the event that matched it"

# --- No --stale-docs flag at all: behaviour is unchanged from before --------
OUT3="$FIXTURE/blast-radius-3.json"
"$SCRIPT" --changed-files "$CHANGED" --out "$OUT3" >/dev/null 2>&1
DOC_COUNT_NO_STALE=$(jq -r '.documents | length' "$OUT3" 2>/dev/null)
assert_equal "4" "$DOC_COUNT_NO_STALE" "with no --stale-docs flag, only the four always-docs appear for an unmatched changed-files list"

_dossier_test_summary
