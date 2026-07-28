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
DOCS="$FIXTURE/docs/dossier/02-architecture"
mkdir -p "$DOCS"

TODAY_S=$(date -u +%s)
day_offset() { date -u -d "@$((TODAY_S - $1 * 86400))" +%Y-%m-%d 2>/dev/null || date -u -j -f %s "$((TODAY_S - $1 * 86400))" +%Y-%m-%d 2>/dev/null; }

# Fresh: verified 10 days ago, well inside a 90-day threshold.
cat >"$DOCS/fresh.md" <<EOF
dossier-header: v1
last-verified: $(day_offset 10)
---
Fresh document.
EOF

# Stale, most overdue: verified 400 days ago.
cat >"$DOCS/very-stale.md" <<EOF
dossier-header: v1
last-verified: $(day_offset 400)
---
Very stale document.
EOF

# Stale, less overdue: verified 200 days ago.
cat >"$DOCS/somewhat-stale.md" <<EOF
dossier-header: v1
last-verified: $(day_offset 200)
---
Somewhat stale document.
EOF

# Stale, least overdue: verified 100 days ago (just past a 90-day threshold).
cat >"$DOCS/barely-stale.md" <<EOF
dossier-header: v1
last-verified: $(day_offset 100)
---
Barely stale document.
EOF

# Undated: no last-verified header at all.
cat >"$DOCS/undated.md" <<EOF
dossier-header: v1
---
No verification date.
EOF

# Undated: placeholder value, not a real date.
cat >"$DOCS/placeholder.md" <<EOF
dossier-header: v1
last-verified: {fill}
---
Placeholder date.
EOF

OUT=$("$SCRIPT" --output-root "$FIXTURE/docs/dossier" --stale-days 90 --max-sweep 2 2>&1)

get_field() { printf '%s\n' "$OUT" | awk -F= -v k="$1" '$1==k{print $2; exit}'; }

assert_equal "90" "$(get_field STALENESS_THRESHOLD_DAYS)" "threshold echoes the --stale-days flag"
assert_equal "3" "$(get_field DOCUMENTS_STALE)" "three documents cross the 90-day threshold"
assert_equal "2" "$(get_field DOCUMENTS_UNDATED)" "two documents are undated (missing header, placeholder value)"
assert_equal "2" "$(get_field MAX_STALE_DOCS_PER_SWEEP)" "sweep cap echoes the --max-sweep flag"

SWEEP=$(get_field STALE_DOCS_FOR_SWEEP)
SWEEP_COUNT=$(printf '%s' "$SWEEP" | tr ',' '\n' | grep -c .)
assert_equal "2" "$SWEEP_COUNT" "sweep list is capped at 2 even though 3 documents are stale"
assert_contains "very-stale.md" "$SWEEP" "the most-overdue document is in the capped sweep list"
assert_contains "somewhat-stale.md" "$SWEEP" "the second-most-overdue document is in the capped sweep list"
assert_not_contains "barely-stale.md" "$SWEEP" "the least-overdue stale document is excluded once the cap is reached"
assert_not_contains "fresh.md" "$SWEEP" "a fresh document never appears in the sweep list"

# --- Empty/absent package: no crash, zero counts, empty sweep list ----------
EMPTY_OUT=$("$SCRIPT" --output-root "$FIXTURE/docs/nonexistent" --stale-days 90 --max-sweep 5 2>&1)
assert_equal "0" "$(printf '%s\n' "$EMPTY_OUT" | awk -F= '$1=="DOCUMENTS_STALE"{print $2; exit}')" "an absent package reports zero stale documents, not an error"
assert_equal "" "$(printf '%s\n' "$EMPTY_OUT" | awk -F= '$1=="STALE_DOCS_FOR_SWEEP"{print $2; exit}')" "an absent package produces an empty sweep list"

# --- --single-file mode: the per-document query dossier-evidence.sh uses ----
SF_OUT=$("$SCRIPT" --single-file "$DOCS/very-stale.md" --stale-days 90 2>&1)
assert_equal "true" "$(printf '%s\n' "$SF_OUT" | awk -F= '$1=="IS_STALE"{print $2; exit}')" "--single-file: a document verified 400 days ago is stale under a 90-day threshold"
assert_equal "false" "$(printf '%s\n' "$SF_OUT" | awk -F= '$1=="IS_UNDATED"{print $2; exit}')" "--single-file: a dated document is not undated"

SF_FRESH=$("$SCRIPT" --single-file "$DOCS/fresh.md" --stale-days 90 2>&1)
assert_equal "false" "$(printf '%s\n' "$SF_FRESH" | awk -F= '$1=="IS_STALE"{print $2; exit}')" "--single-file: a document verified 10 days ago is not stale under a 90-day threshold"

SF_UNDATED=$("$SCRIPT" --single-file "$DOCS/undated.md" --stale-days 90 2>&1)
assert_equal "true" "$(printf '%s\n' "$SF_UNDATED" | awk -F= '$1=="IS_UNDATED"{print $2; exit}')" "--single-file: a document with no last-verified header is undated"
assert_equal "false" "$(printf '%s\n' "$SF_UNDATED" | awk -F= '$1=="IS_STALE"{print $2; exit}')" "--single-file: an undated document is never reported as stale"

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
  cat >"$STATUS_DOCS/very-stale.md" <<EOF
dossier-header: v1
last-verified: $(day_offset 400)
---
Very stale document for the status.md golden-fixture check.
EOF
  cat >"$STATUS_DOCS/fresh.md" <<EOF
dossier-header: v1
last-verified: $(day_offset 10)
---
Fresh document for the status.md golden-fixture check.
EOF
  cat >"$STATUS_DOCS/undated.md" <<EOF
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
