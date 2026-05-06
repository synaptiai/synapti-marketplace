#!/usr/bin/env bash
# Verifies parser tolerance for the FLOW_REVIEW_CYCLE schema extension
# introduced by issue #86. Mirrors the shell pipelines used by
# plugins/flow/commands/status.md and plugins/flow/commands/merge.md.
#
# Exits 0 on pass, 1 on first failure, 2 on infrastructure error
# (missing fixtures). Bash 3.2+ portable (macOS BSD tools and Linux GNU
# tools). NOT POSIX `sh`-portable due to `pipefail` and process
# substitution (`<( ... )`).

set -uo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")" && pwd)/markers"
PASS=0
FAIL=0

# Sanitize attacker-controlled fields before display: cap length and strip
# non-printable bytes so a hostile fixture (e.g., a PR-modified marker file)
# can't inject ANSI escapes into PASS/FAIL output. Mirrors the helper in
# plugins/flow/commands/status.md (cap matches that helper at 64 chars).
# Note: tr -cd '[:print:]' intentionally collapses newlines too — diagnostic
# display only, not data integrity. If a future test passes multi-line content
# to assert_eq, expect single-line collapsed output in FAIL diagnostics.
safe() { printf '%s' "${1:-}" | tr -cd '[:print:]' | cut -c1-64; }

# Pre-flight: every fixture file must exist before we run any test, so a
# missing fixture surfaces as a clear FATAL rather than every downstream
# assertion failing. NOTE: this list is hard-coded; add new fixtures here too.
for f in legacy-5-field.txt extended-7-field.txt mixed-cycles.txt with-resolution.txt; do
  if [ ! -f "$FIXTURE_DIR/$f" ]; then
    echo "FATAL: missing fixture $FIXTURE_DIR/$f" >&2
    exit 2
  fi
done

assert_eq() {
  local label="$1" expected="$2" actual="$3" context="${4:-}"
  if [ "$expected" = "$actual" ]; then
    # label is a hard-coded operator string at every call site; no need to
    # sanitize. Attacker-controlled fields are sanitized only in the FAIL
    # branch where they actually reach the terminal.
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $(safe "$label")"
    echo "  expected: $(safe "$expected")"
    echo "  actual:   $(safe "$actual")"
    [ -n "$context" ] && echo "  context:  $(safe "$context")"
    FAIL=$((FAIL + 1))
  fi
}

# status.md-style parser: extracts FINDINGS rows then reads ID|PRIORITY via IFS.
# Trailing fields are lumped into the last `read` variable (STATUS); the parser
# doesn't care about them, which is what makes the schema extension safe.
# Variable name `STATUS` is identical to the production parser at
# plugins/flow/commands/status.md:97 — keeping the name aligned makes drift
# easier to spot.
status_parse() {
  local body="$1"
  local raw
  raw=$(echo "$body" | grep -o 'FINDINGS:\[[^]]*\]' | sed 's/^FINDINGS:\[//;s/\]$//' | tr ',' '\n')
  echo "$raw" | while IFS='|' read -r ID PRIORITY CAT LOC STATUS; do
    [ -z "$ID" ] && continue
    case "$PRIORITY" in
      P1|P2|P3) echo "${PRIORITY}|${ID}" ;;
    esac
  done
}

# merge.md-style parser: takes the leading ID-only via sed-strip-after-pipe.
# Ignores priority and any trailing fields; only the ID matters for matching
# against RESOLVED.
merge_parse_ids() {
  local body="$1"
  echo "$body" | grep -o 'FINDINGS:\[[^]]*\]' | sed 's/^FINDINGS:\[//;s/\]$//' | tr ',' '\n' | sed 's/|.*//' | tr -d ' ' | sort
}

# merge.md-style RESOLVED extraction.
merge_parse_resolved() {
  local body="$1"
  echo "$body" | grep -o 'RESOLVED:\[[^]]*\]' | sed 's/^RESOLVED:\[//;s/\]$//' | tr ',' '\n' | tr -d ' ' | sort | grep -v '^$' || true
}

echo "=== Test 1: legacy 5-field marker ==="
BODY=$(cat "$FIXTURE_DIR/legacy-5-field.txt")
COUNT_P1=$(status_parse "$BODY" | grep -c '^P1|' || true)
COUNT_P2=$(status_parse "$BODY" | grep -c '^P2|' || true)
COUNT_P3=$(status_parse "$BODY" | grep -c '^P3|' || true)
IDS=$(merge_parse_ids "$BODY" | paste -sd, -)
assert_eq "legacy P1 count" "1" "$COUNT_P1"
assert_eq "legacy P2 count" "1" "$COUNT_P2"
assert_eq "legacy P3 count" "1" "$COUNT_P3"
assert_eq "legacy IDs"      "F1,F2,F3" "$IDS"

echo
echo "=== Test 2: extended 7-field marker (Confidence + Disposition) ==="
BODY=$(cat "$FIXTURE_DIR/extended-7-field.txt")
COUNT_P1=$(status_parse "$BODY" | grep -c '^P1|' || true)
COUNT_P2=$(status_parse "$BODY" | grep -c '^P2|' || true)
COUNT_P3=$(status_parse "$BODY" | grep -c '^P3|' || true)
IDS=$(merge_parse_ids "$BODY" | paste -sd, -)
assert_eq "extended P1 count" "1" "$COUNT_P1"
assert_eq "extended P2 count" "1" "$COUNT_P2"
assert_eq "extended P3 count" "1" "$COUNT_P3"
assert_eq "extended IDs"      "F1,F2,F3" "$IDS"

echo
echo "=== Test 3: mixed-cycles marker (legacy + extended in one body) ==="
BODY=$(cat "$FIXTURE_DIR/mixed-cycles.txt")
# status.md/merge.md take the LAST FLOW_REVIEW_CYCLE marker via `last` in jq.
# When using local fixtures (no jq selecting "last"), grep returns all matches.
# Simulate `last` selection by taking only the last FLOW_REVIEW_CYCLE line.
LAST_REVIEW=$(echo "$BODY" | grep 'FLOW_REVIEW_CYCLE:' | tail -1)
COUNT_P1=$(status_parse "$LAST_REVIEW" | grep -c '^P1|' || true)
COUNT_P3=$(status_parse "$LAST_REVIEW" | grep -c '^P3|' || true)
IDS=$(merge_parse_ids "$LAST_REVIEW" | paste -sd, -)
assert_eq "mixed last-cycle P1 count" "1" "$COUNT_P1"
assert_eq "mixed last-cycle P3 count" "1" "$COUNT_P3"
assert_eq "mixed last-cycle IDs"      "F3,F4" "$IDS"

echo
echo "=== Test 4: review + resolution markers (full ledger pipeline) ==="
BODY=$(cat "$FIXTURE_DIR/with-resolution.txt")
REVIEW_BODY=$(echo "$BODY" | grep 'FLOW_REVIEW_CYCLE:' | tail -1)
RESOLUTION_BODY=$(echo "$BODY" | grep 'FLOW_RESOLUTION_CYCLE:' | tail -1)
REVIEW_IDS=$(merge_parse_ids "$REVIEW_BODY")
RESOLVED_IDS=$(merge_parse_resolved "$RESOLUTION_BODY")
UNRESOLVED=$(comm -23 <(echo "$REVIEW_IDS") <(echo "$RESOLVED_IDS") | grep -v '^$' | paste -sd, -)
assert_eq "review IDs (extended form)" "F1,F2,F3" "$(echo "$REVIEW_IDS" | paste -sd, -)"
assert_eq "resolved IDs"               "F1,F3"    "$(echo "$RESOLVED_IDS" | paste -sd, -)"
assert_eq "unresolved (= F2)"          "F2"       "$UNRESOLVED"

# Extract DISPUTED to confirm the resolution-cycle parser handles arrays.
DISPUTED=$(echo "$RESOLUTION_BODY" | grep -o 'DISPUTED:\[[^]]*\]' | sed 's/^DISPUTED:\[//;s/\]$//' | tr -d ' ')
assert_eq "disputed = F2" "F2" "$DISPUTED"

echo
echo "=== Test 5: 7-field IFS read does not corrupt P1/P2/P3 tally ==="
# This is the load-bearing assertion: status.md uses
#   while IFS='|' read -r ID PRIORITY CAT LOC STATUS
# When the row has 7 fields, STATUS receives "open|HIGH|consensus" — but
# only ID and PRIORITY are USED for the tally. Verify that 7-field rows
# still produce the correct priority counts.
BODY=$(cat "$FIXTURE_DIR/extended-7-field.txt")
TALLY=$(status_parse "$BODY" | sort | paste -sd, -)
assert_eq "7-field tally is canonical" "P1|F1,P2|F2,P3|F3" "$TALLY"

echo
echo "=================================================="
echo "RESULT: $PASS passed, $FAIL failed"
echo "=================================================="
[ "$FAIL" -gt 0 ] && exit 1
exit 0
