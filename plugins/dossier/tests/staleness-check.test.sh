#!/usr/bin/env bash
# dossier-staleness-check.sh: the single source of truth for document
# staleness, consolidating what status.md and dossier-evidence.sh used to
# compute separately. Covers issue #135 AC #1 and #3's underlying primitive:
# accurate stale/undated counts, and a bounded, oldest-first sweep list.

_dossier_test_begin "staleness-check"

SCRIPT="plugins/dossier/bin/dossier-staleness-check.sh"

if [ ! -x "$SCRIPT" ]; then
  _dossier_assert_fail "$SCRIPT missing or not executable"
  _dossier_test_summary
  return 0 2>/dev/null || exit 0
fi

FIXTURE=$(_dossier_safe_mktemp_dir "staleness-check")
ARCH="$FIXTURE/docs/dossier/02-architecture"
CONTROL="$FIXTURE/docs/dossier/00-control"
mkdir -p "$ARCH" "$CONTROL"

# The sweep walk is restricted to the 23 canonical document paths
# bin/dossier-evidence.sh recognizes (SEC-3) — a made-up filename like
# "very-stale.md" would silently never be found, so every fixture file below
# uses a real canonical relative path.
FRESH_DOC="$ARCH/system-architecture.md"
MOST_OVERDUE_DOC="$ARCH/components-and-codebase.md"
SECOND_OVERDUE_DOC="$ARCH/data-and-ai.md"
LEAST_OVERDUE_DOC="$ARCH/interfaces-and-integrations.md"
UNDATED_DOC="$ARCH/infrastructure-and-deployment.md"
PLACEHOLDER_DOC="$CONTROL/documentation-index.md"

TODAY_S=$(date -u +%s)
day_offset() { date -u -d "@$((TODAY_S - $1 * 86400))" +%Y-%m-%d 2>/dev/null || date -u -j -f %s "$((TODAY_S - $1 * 86400))" +%Y-%m-%d 2>/dev/null; }

# Fresh: verified 10 days ago, well inside a 90-day threshold.
cat >"$FRESH_DOC" <<EOF
dossier-header: v1
last-verified: $(day_offset 10)
---
Fresh document.
EOF

# Stale, most overdue: verified 400 days ago.
cat >"$MOST_OVERDUE_DOC" <<EOF
dossier-header: v1
last-verified: $(day_offset 400)
---
Very stale document.
EOF

# Stale, less overdue: verified 200 days ago.
cat >"$SECOND_OVERDUE_DOC" <<EOF
dossier-header: v1
last-verified: $(day_offset 200)
---
Somewhat stale document.
EOF

# Stale, least overdue: verified 100 days ago (just past a 90-day threshold).
cat >"$LEAST_OVERDUE_DOC" <<EOF
dossier-header: v1
last-verified: $(day_offset 100)
---
Barely stale document.
EOF

# Undated: no last-verified header at all.
cat >"$UNDATED_DOC" <<EOF
dossier-header: v1
---
No verification date.
EOF

# Undated: placeholder value, not a real date.
cat >"$PLACEHOLDER_DOC" <<EOF
dossier-header: v1
last-verified: {fill}
---
Placeholder date.
EOF

# SEC-3 (narrow scope): a stale, dated, non-canonical file (a package README
# that happens to carry a last-verified header, say) must still count toward
# DOCUMENTS_STALE like every other document status.md has always seen — but
# must never be sweep-eligible, even when it is the single most-overdue file
# in the package. Deliberately the oldest of all (500 days), so if the sweep
# ever regressed to walking all *.md files again, this would displace a
# canonical entry from the capped list and the exact-match assertion below
# would catch it.
STRAY_DOC="$FIXTURE/docs/dossier/README.md"
cat >"$STRAY_DOC" <<EOF
dossier-header: v1
last-verified: $(day_offset 500)
---
Not a canonical dossier document, just a plain package readme.
EOF

OUT=$("$SCRIPT" --output-root "$FIXTURE/docs/dossier" --stale-days 90 --max-sweep 2 2>&1)

get_field() { printf '%s\n' "$OUT" | awk -F= -v k="$1" '$1==k{print $2; exit}'; }

assert_equal "90" "$(get_field STALENESS_THRESHOLD_DAYS)" "threshold echoes the --stale-days flag"
assert_equal "4" "$(get_field DOCUMENTS_STALE)" "four documents cross the 90-day threshold, including the non-canonical stray README"
assert_equal "2" "$(get_field DOCUMENTS_UNDATED)" "two documents are undated (missing header, placeholder value) — the stray README is dated, so it does not add a third"
assert_equal "2" "$(get_field MAX_STALE_DOCS_PER_SWEEP)" "sweep cap echoes the --max-sweep flag"

SWEEP=$(get_field STALE_DOCS_FOR_SWEEP)
SWEEP_COUNT=$(printf '%s' "$SWEEP" | tr ',' '\n' | grep -c .)
assert_equal "2" "$SWEEP_COUNT" "sweep list is capped at 2 even though 3 documents are stale"
# Exact-match, package-relative — never $OUTPUT_ROOT-prefixed. A substring
# match here would not have caught a doubled prefix like
# "docs/dossier/docs/dossier/02-architecture/...", which still contains the
# bare filename as a substring.
assert_equal "02-architecture/components-and-codebase.md,02-architecture/data-and-ai.md" "$SWEEP" "sweep list is exact, package-relative, most-overdue first — and excludes the stray non-canonical README even though it is the single most-overdue stale document of all"

# --- Empty/absent package: no crash, zero counts, empty sweep list ----------
EMPTY_OUT=$("$SCRIPT" --output-root "$FIXTURE/docs/nonexistent" --stale-days 90 --max-sweep 5 2>&1)
assert_equal "0" "$(printf '%s\n' "$EMPTY_OUT" | awk -F= '$1=="DOCUMENTS_STALE"{print $2; exit}')" "an absent package reports zero stale documents, not an error"
assert_equal "" "$(printf '%s\n' "$EMPTY_OUT" | awk -F= '$1=="STALE_DOCS_FOR_SWEEP"{print $2; exit}')" "an absent package produces an empty sweep list"

# --- --single-file mode: the per-document query dossier-evidence.sh uses ----
# --single-file takes an explicit path and is not subject to the canonical-doc
# restriction (that only bounds the sweep-mode walk), but reuses the same
# fixture files for coverage of the same three states.
SF_OUT=$("$SCRIPT" --single-file "$MOST_OVERDUE_DOC" --stale-days 90 2>&1)
assert_equal "true" "$(printf '%s\n' "$SF_OUT" | awk -F= '$1=="IS_STALE"{print $2; exit}')" "--single-file: a document verified 400 days ago is stale under a 90-day threshold"
assert_equal "false" "$(printf '%s\n' "$SF_OUT" | awk -F= '$1=="IS_UNDATED"{print $2; exit}')" "--single-file: a dated document is not undated"

SF_FRESH=$("$SCRIPT" --single-file "$FRESH_DOC" --stale-days 90 2>&1)
assert_equal "false" "$(printf '%s\n' "$SF_FRESH" | awk -F= '$1=="IS_STALE"{print $2; exit}')" "--single-file: a document verified 10 days ago is not stale under a 90-day threshold"

SF_UNDATED=$("$SCRIPT" --single-file "$UNDATED_DOC" --stale-days 90 2>&1)
assert_equal "true" "$(printf '%s\n' "$SF_UNDATED" | awk -F= '$1=="IS_UNDATED"{print $2; exit}')" "--single-file: a document with no last-verified header is undated"
assert_equal "false" "$(printf '%s\n' "$SF_UNDATED" | awk -F= '$1=="IS_STALE"{print $2; exit}')" "--single-file: an undated document is never reported as stale"

# --- ERR-2: calendar-invalid but shape-valid dates count as undated, not stale
CALENDAR_INVALID_DOC="$ARCH/calendar-invalid.md"
cat >"$CALENDAR_INVALID_DOC" <<EOF
dossier-header: v1
last-verified: 2024-13-45
---
Shape-valid, not a real calendar date.
EOF
SF_INVALID=$("$SCRIPT" --single-file "$CALENDAR_INVALID_DOC" --stale-days 90 2>&1)
assert_equal "true" "$(printf '%s\n' "$SF_INVALID" | awk -F= '$1=="IS_UNDATED"{print $2; exit}')" "--single-file: a calendar-invalid date (2024-13-45) counts as undated, not fresh"
assert_equal "false" "$(printf '%s\n' "$SF_INVALID" | awk -F= '$1=="IS_STALE"{print $2; exit}')" "--single-file: a calendar-invalid date is never reported as stale"

# --- Rollover dates: shape-valid AND parseable, but not a real calendar day.
# Distinct from the ERR-2 case above (2024-13-45, which both BSD and GNU date
# refuse outright): BSD/GNU date silently ROLL OVER an out-of-range day
# (2026-06-31 -> July 1, 2024-02-30 -> March) instead of failing, so the naive
# parse-and-compare-age logic reads a typo as freshly verified — the dangerous
# direction, since it actively hides a genuinely-unverified document. This is
# what validate_calendar_date()'s round-trip check exists to catch.
ROLLOVER_JUNE_DOC="$ARCH/rollover-june.md"
cat >"$ROLLOVER_JUNE_DOC" <<EOF
dossier-header: v1
last-verified: 2026-06-31
---
June has no 31st; BSD/GNU date rolls this to July 1.
EOF
SF_ROLLOVER_JUNE=$("$SCRIPT" --single-file "$ROLLOVER_JUNE_DOC" --stale-days 90 2>&1)
assert_equal "true" "$(printf '%s\n' "$SF_ROLLOVER_JUNE" | awk -F= '$1=="IS_UNDATED"{print $2; exit}')" "--single-file: 2026-06-31 (rolls to July 1) counts as undated, not fresh"
assert_equal "false" "$(printf '%s\n' "$SF_ROLLOVER_JUNE" | awk -F= '$1=="IS_STALE"{print $2; exit}')" "--single-file: 2026-06-31 is never reported as stale"

ROLLOVER_FEB_DOC="$ARCH/rollover-feb.md"
cat >"$ROLLOVER_FEB_DOC" <<EOF
dossier-header: v1
last-verified: 2024-02-30
---
February has no 30th; rolls to March.
EOF
SF_ROLLOVER_FEB=$("$SCRIPT" --single-file "$ROLLOVER_FEB_DOC" --stale-days 90 2>&1)
assert_equal "true" "$(printf '%s\n' "$SF_ROLLOVER_FEB" | awk -F= '$1=="IS_UNDATED"{print $2; exit}')" "--single-file: 2024-02-30 (rolls to March) counts as undated, not stale under a 90-day threshold"

# Sweep mode must catch the same rollover — a document with only a rollover
# date and nothing else planted in this fixture must count toward
# DOCUMENTS_UNDATED, not silently vanish from every count.
ROLLOVER_FIXTURE=$(_dossier_safe_mktemp_dir "staleness-rollover")
mkdir -p "$ROLLOVER_FIXTURE/docs/dossier/02-architecture"
cat >"$ROLLOVER_FIXTURE/docs/dossier/02-architecture/system-architecture.md" <<EOF
dossier-header: v1
last-verified: 2026-06-31
---
Rollover date, sweep mode.
EOF
SWEEP_ROLLOVER_OUT=$("$SCRIPT" --output-root "$ROLLOVER_FIXTURE/docs/dossier" --stale-days 90 --max-sweep 5 2>&1)
assert_equal "0" "$(printf '%s\n' "$SWEEP_ROLLOVER_OUT" | awk -F= '$1=="DOCUMENTS_STALE"{print $2; exit}')" "sweep mode: a rollover date is never counted as stale"
assert_equal "1" "$(printf '%s\n' "$SWEEP_ROLLOVER_OUT" | awk -F= '$1=="DOCUMENTS_UNDATED"{print $2; exit}')" "sweep mode: a rollover date counts toward DOCUMENTS_UNDATED"

# =============================================================================
# Golden-fixture check: commands/status.md's "### Staleness" section must keep
# emitting the same four fields, in the same order, with the same values, now
# that the computation has moved into dossier-staleness-check.sh. A silent
# format drift here would break /dossier:status's dashboard contract with
# nothing else in the suite to catch it (status.md has no other test coverage).
# =============================================================================
STATUS_MD="plugins/dossier/commands/status.md"
if [ -f "$STATUS_MD" ]; then
  STATUS_BLOCK=$(sed -n '/^```!$/,/^```$/p' "$STATUS_MD" | sed '1d;$d')

  if printf '%s' "$STATUS_BLOCK" | grep -q 'dossier-staleness-check\.sh'; then
    _dossier_assert_pass "status.md calls the shared dossier-staleness-check.sh script"
  else
    _dossier_assert_fail "status.md does not call dossier-staleness-check.sh — still has its own inline staleness loop"
  fi

  STATUS_FIXTURE="$RUN_TMPDIR/status-md-fixture"
  STATUS_DOCS="$STATUS_FIXTURE/docs/dossier/02-architecture"
  mkdir -p "$STATUS_DOCS" "$STATUS_FIXTURE/docs/dossier/00-control"
  # Canonical filenames — see the SEC-3 comment above; the sweep walk only
  # ever looks at the 23 recognized document paths.
  cat >"$STATUS_DOCS/system-architecture.md" <<EOF
dossier-header: v1
last-verified: $(day_offset 400)
---
Very stale document for the status.md golden-fixture check.
EOF
  cat >"$STATUS_DOCS/components-and-codebase.md" <<EOF
dossier-header: v1
last-verified: $(day_offset 10)
---
Fresh document for the status.md golden-fixture check.
EOF
  cat >"$STATUS_DOCS/data-and-ai.md" <<EOF
dossier-header: v1
---
Undated document for the status.md golden-fixture check.
EOF

  SCRIPT_FILE="$RUN_TMPDIR/status-block.sh"
  printf '%s\n' "$STATUS_BLOCK" >"$SCRIPT_FILE"
  DOSSIER_PLUGIN_ABS="$(pwd)/plugins/dossier"

  STATUS_OUT=$(cd "$STATUS_FIXTURE" && ARGUMENTS="" CLAUDE_PLUGIN_ROOT="$DOSSIER_PLUGIN_ABS" bash "$SCRIPT_FILE" 2>/dev/null)

  get_status_field() { printf '%s\n' "$STATUS_OUT" | awk -F= -v k="$1" '$1==k{print $2; exit}'; }

  assert_equal "90" "$(get_status_field STALENESS_THRESHOLD_DAYS)" "status.md: STALENESS_THRESHOLD_DAYS uses the plugin default of 90"
  assert_equal "1" "$(get_status_field DOCUMENTS_STALE)" "status.md: DOCUMENTS_STALE correctly reports one stale document via the shared script"
  assert_equal "1" "$(get_status_field DOCUMENTS_UNDATED)" "status.md: DOCUMENTS_UNDATED correctly reports one undated document via the shared script"
  assert_match "^[0-9]{4}-[0-9]{2}-[0-9]{2}$" "$(get_status_field OLDEST_VERIFICATION)" "status.md: OLDEST_VERIFICATION is a well-formed date"
else
  _dossier_assert_fail "$STATUS_MD missing"
fi

_dossier_test_summary
