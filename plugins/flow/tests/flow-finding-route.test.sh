# Tests for plugins/flow/bin/flow-finding-route.sh.
#
# Contract (issue #212; .decisions/issue-212.md § Plan):
#   - Input: consolidated finding rows `ID|PRIORITY|category|location|CONFIDENCE|disposition|agent`
#     on stdin or --input, plus --mode external|self and --pr <N>.
#   - Confidence decides what a finding may demand. On an external review a
#     LOW finding (any priority) goes to NEEDS_INVESTIGATION and is excluded
#     from the counts, the decision and the marker rows. On the author's own
#     PR a LOW row may not be routed at all: exit 3 names it.
#   - An absent or invalid confidence is MEDIUM, never LOW or HIGH, with a
#     LEDGER_WARN naming the agent.
#   - Marker rows are 7-field; `%`, `,`, `]` and anything else that could end
#     the marker are percent-encoded in category and location.
#
# Expected values come from the issue's decision table and risk map, copied
# into the journal's Interface contracts and Risk map sections, or from hand
# counts of the fixture marker. None is taken from the script's own output.

HELPER="$REPO_ROOT/plugins/flow/bin/flow-finding-route.sh"
FIXTURES="$REPO_ROOT/plugins/flow/tests/fixtures/finding-route"

FFR_CLEANUP_PATHS=()
_ffr_cleanup() {
  local p
  for p in "${FFR_CLEANUP_PATHS[@]:-}"; do
    [ -n "$p" ] && rm -rf "$p" 2>/dev/null
  done
}
trap _ffr_cleanup EXIT

FFR_DIR=$(mktemp -d -t flow-finding-route.tests.XXXXXX 2>/dev/null)
if [ -z "$FFR_DIR" ] || [ ! -d "$FFR_DIR" ]; then
  _flow_test_begin "mktemp prerequisite"
  _flow_assert_fail "mktemp -d failed"
  return 0
fi
FFR_CLEANUP_PATHS+=("$FFR_DIR")

# _route <stdin-text> <args...> — runs the helper; sets OUT, ERR, CODE.
_route() {
  local input="$1"; shift
  printf '%s' "$input" > "$FFR_DIR/in"
  "$HELPER" "$@" < "$FFR_DIR/in" > "$FFR_DIR/out" 2> "$FFR_DIR/err"
  CODE=$?
  OUT=$(cat "$FFR_DIR/out")
  ERR=$(cat "$FFR_DIR/err")
}

# _key <name> — the value of NAME= in OUT (empty when absent).
_key() {
  local line
  while IFS= read -r line; do
    case "$line" in "$1="*) printf '%s' "${line#"$1="}"; return 0 ;; esac
  done <<<"$OUT"
  return 1
}

_flow_test_begin "helper exists and is executable"
if [ -x "$HELPER" ]; then
  _flow_assert_pass "flow-finding-route.sh is executable"
else
  _flow_assert_fail "missing or not executable: $HELPER"
  return 0
fi

# --- usage ----------------------------------------------------------------

_flow_test_begin "usage errors exit 1; an unreadable input file exits 2"
ROW='F1|P2|correctness|src/a.sh:1|HIGH|unchallenged|code-reviewer'
_route "$ROW" --pr 7;                        assert_exit 1 "$CODE" "missing --mode"
_route "$ROW" --mode review --pr 7;          assert_exit 1 "$CODE" "unknown mode"
_route "$ROW" --mode external;               assert_exit 1 "$CODE" "missing --pr"
_route "$ROW" --mode external --pr 7a;       assert_exit 1 "$CODE" "non-numeric --pr"
_route "$ROW" --mode external --pr 0;        assert_exit 1 "$CODE" "zero --pr"
_route "" --mode external --pr 7 --input "$FFR_DIR/does-not-exist"
assert_exit 2 "$CODE" "unreadable --input"

# --- risk row: absent confidence --------------------------------------------

_flow_test_begin "risk: absent confidence is MEDIUM with a LEDGER_WARN, never LOW"
_route 'F1|P1|correctness|src/a.sh:10||unchallenged|code-reviewer' --mode external --pr 7
assert_exit 0 "$CODE" "routed"
assert_equal "1" "$(_key COUNT_P1)" "the P1 is counted"
assert_equal "" "$(_key NEEDS_INVESTIGATION)" "not sent to investigation"
assert_equal "REQUEST_CHANGES" "$(_key DECISION)" "a MEDIUM P1 requests changes"
assert_equal "F1|P1|correctness|src/a.sh:10|open|MEDIUM|unchallenged" "$(_key MARKER_ROWS)" "marker row written as MEDIUM"
assert_equal "LEDGER_WARN: PR#7 finding 'F1' from code-reviewer has no confidence — treated as MEDIUM" "$ERR" "one warning naming the agent"

_flow_test_begin "invalid confidence values are MEDIUM with a warning naming the value"
for bad in 0.8 maybe Medium-High; do
  _route "F1|P2|correctness|src/a.sh:3|$bad|unchallenged|error-handler-inspector" --mode external --pr 12
  assert_equal "F1|P2|correctness|src/a.sh:3|open|MEDIUM|unchallenged" "$(_key MARKER_ROWS)" "'$bad' → MEDIUM row"
  assert_equal "LEDGER_WARN: PR#12 finding 'F1' from error-handler-inspector has invalid confidence '$bad' — treated as MEDIUM" "$ERR" "'$bad' warning"
done

_flow_test_begin "valid confidence in any letter case is accepted silently"
_route 'F1|P2|correctness|src/a.sh:3| high |consensus|code-reviewer' --mode external --pr 7
assert_equal "F1|P2|correctness|src/a.sh:3|open|HIGH|consensus" "$(_key MARKER_ROWS)" "' high ' → HIGH"
assert_equal "" "$ERR" "no warning for a valid value"
_route 'F1|P2|correctness|src/a.sh:3|Low|kept|code-reviewer' --mode external --pr 7
assert_equal "F1" "$(_key NEEDS_INVESTIGATION)" "'Low' → LOW, sent to investigation"
assert_equal "" "$ERR" "no warning for 'Low'"

_flow_test_begin "partial failure: one warning per missing confidence, others keep their value"
_route 'F1|P2|security|src/s.sh:4|HIGH|unchallenged|security-reviewer
F2|P2|security|src/s.sh:9||unchallenged|security-reviewer' --mode external --pr 7
assert_equal "F1|P2|security|src/s.sh:4|open|HIGH|unchallenged,F2|P2|security|src/s.sh:9|open|MEDIUM|unchallenged" "$(_key MARKER_ROWS)" "F1 keeps HIGH, F2 becomes MEDIUM"
assert_equal "LEDGER_WARN: PR#7 finding 'F2' from security-reviewer has no confidence — treated as MEDIUM" "$ERR" "exactly one warning, for F2"

# --- risk rows: marker vs decision, header counts ---------------------------

MIXED='F1|P2|correctness|src/b.sh:4|HIGH|consensus|code-reviewer
F2|P1|correctness|src/c.sh:9|LOW|kept|code-reviewer'

_flow_test_begin "risk: a LOW row is excluded from the marker, not only from the decision"
_route "$MIXED" --mode external --pr 7
assert_exit 0 "$CODE" "routed"
assert_equal "F1|P2|correctness|src/b.sh:4|open|HIGH|consensus" "$(_key MARKER_ROWS)" "marker carries F1 only"
assert_not_contains "F2|" "$OUT" "F2 is nowhere in a marker row"
assert_equal "F2" "$(_key NEEDS_INVESTIGATION)" "F2 goes to investigation"
assert_equal "REQUEST_CHANGES" "$(_key DECISION)" "decision comes from F1 (HIGH P2)"

_flow_test_begin "risk: header counts exclude LOW findings"
assert_equal "0" "$(_key COUNT_P1)" "the LOW P1 is not counted"
assert_equal "1" "$(_key COUNT_P2)" "the HIGH P2 is counted"
assert_equal "0" "$(_key COUNT_P3)" "no P3"
assert_equal "1" "$(_key COUNT_NEEDS_INVESTIGATION)" "one investigation"
assert_equal "2" "$(_key ROWS_READ)" "both rows examined"

# --- risk row: only-LOW decision --------------------------------------------

_flow_test_begin "risk: an external review whose only finding is LOW approves"
_route 'F1|P1|security|src/d.sh:2|LOW|kept|security-reviewer' --mode external --pr 7
assert_exit 0 "$CODE" "routed"
assert_equal "APPROVE" "$(_key DECISION)" "nothing counted → APPROVE"
assert_equal "" "$(_key MARKER_ROWS)" "no marker rows"
assert_equal "F1" "$(_key NEEDS_INVESTIGATION)" "F1 listed for investigation"
assert_equal "0" "$(_key COUNT_P1)" "P1 count is 0"

_flow_test_begin "decision table rows"
_route 'F1|P3|maintainability|src/e.sh:1|MEDIUM|unchallenged|code-reviewer
F2|P1|correctness|src/e.sh:8|LOW|unchallenged|code-reviewer' --mode external --pr 7
assert_equal "COMMENT" "$(_key DECISION)" "MEDIUM P3 + LOW P1 → COMMENT"
_route 'F1|P1|correctness|src/e.sh:1|MEDIUM|unchallenged|code-reviewer' --mode external --pr 7
assert_equal "REQUEST_CHANGES" "$(_key DECISION)" "a MEDIUM P1 alone requests changes (not only HIGH)"
_route 'F1|P3|maintainability|src/e.sh:1|HIGH|unchallenged|code-reviewer' --mode external --pr 7
assert_equal "COMMENT" "$(_key DECISION)" "HIGH P3 only → COMMENT"

_flow_test_begin "investigation ids keep input order"
_route 'F3|P2|correctness|src/f.sh:1|LOW|unchallenged|code-reviewer
F1|P1|correctness|src/f.sh:2|LOW|unchallenged|code-reviewer' --mode external --pr 7
assert_equal "F3,F1" "$(_key NEEDS_INVESTIGATION)" "input order, not sorted"
assert_equal "2" "$(_key COUNT_NEEDS_INVESTIGATION)" "two investigations"

# --- risk row: exclusion scope (own PR) -------------------------------------

_flow_test_begin "risk: on the author's own PR a LOW row blocks routing (exit 3)"
_route 'F1|P2|edge-case|src/e.sh:5|LOW|unchallenged|code-reviewer' --mode self --pr 7
assert_exit 3 "$CODE" "exit 3"
assert_equal "F1" "$(_key UNRESOLVED_LOW)" "names the unresolved id"
assert_not_contains "NEEDS_INVESTIGATION=F1" "$OUT" "not listed as an investigation"
assert_not_contains "DECISION=" "$OUT" "no decision to post"
assert_not_contains "MARKER_ROWS=" "$OUT" "no marker to post"
assert_contains "F1" "$ERR" "stderr names F1"

_flow_test_begin "own PR: the same finding re-recorded HIGH routes normally"
_route 'F1|P2|edge-case|src/e.sh:5|HIGH|unchallenged|code-reviewer' --mode self --pr 7
assert_exit 0 "$CODE" "exit 0"
assert_equal "F1|P2|edge-case|src/e.sh:5|open|HIGH|unchallenged" "$(_key MARKER_ROWS)" "marker row written"
assert_equal "1" "$(_key COUNT_P2)" "counted"
assert_equal "COMMENT" "$(_key DECISION)" "a self-review posts as a comment"
assert_equal "" "$(_key UNRESOLVED_LOW)" "no unresolved LOW"

_flow_test_begin "own PR: absent confidence is MEDIUM, not a blocking LOW"
_route 'F1|P2|edge-case|src/e.sh:5||unchallenged|code-reviewer' --mode self --pr 7
assert_exit 0 "$CODE" "exit 0"
assert_equal "F1|P2|edge-case|src/e.sh:5|open|MEDIUM|unchallenged" "$(_key MARKER_ROWS)" "MEDIUM row"

# --- validation: must fire / must stay silent -------------------------------

_flow_test_begin "rows that the merge gate could not read are rejected (exit 1)"
_route '1F|P2|correctness|src/a.sh:1|HIGH|unchallenged|code-reviewer' --mode external --pr 7
assert_exit 1 "$CODE" "id starting with a digit"
_route 'F*|P2|correctness|src/a.sh:1|HIGH|unchallenged|code-reviewer' --mode external --pr 7
assert_exit 1 "$CODE" "id with a glob character"
_route 'F1|P4|correctness|src/a.sh:1|HIGH|unchallenged|code-reviewer' --mode external --pr 7
assert_exit 1 "$CODE" "priority P4"
_route 'F1|P2|correctness|src/a.sh:1|HIGH|code-reviewer' --mode external --pr 7
assert_exit 1 "$CODE" "6-field row"
assert_contains "line 1" "$ERR" "names the input line"
_route 'F1|P2|correctness|src/a.sh:1|HIGH|unchallenged|code-reviewer|extra' --mode external --pr 7
assert_exit 1 "$CODE" "8-field row"
_route 'F1|P2||src/a.sh:1|HIGH|unchallenged|code-reviewer' --mode external --pr 7
assert_exit 1 "$CODE" "empty category"
_route 'F1|P2|correctness||HIGH|unchallenged|code-reviewer' --mode external --pr 7
assert_exit 1 "$CODE" "empty location"
_route 'F1|P2|correctness|src/a.sh:1|HIGH|unchallenged|code-reviewer
F1|P3|correctness|src/a.sh:2|HIGH|unchallenged|code-reviewer' --mode external --pr 7
assert_exit 1 "$CODE" "duplicate id"
assert_not_contains "MARKER_ROWS=" "$OUT" "nothing routed after a rejection"

_flow_test_begin "ids are ASCII whatever the caller's locale"
BAD_ID_ROW="$(printf 'F\xc3\xa91|P2|correctness|src/a.sh:1|HIGH|unchallenged|code-reviewer')"
printf '%s' "$BAD_ID_ROW" > "$FFR_DIR/in"
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 "$HELPER" --mode external --pr 7 < "$FFR_DIR/in" > "$FFR_DIR/out" 2> "$FFR_DIR/err"
assert_exit 1 "$?" "a non-ASCII letter in an id is rejected under a UTF-8 locale"

_flow_test_begin "valid ids, dispositions and agent defaults route silently"
_route 'SEC-1|P2|security|src/a.sh:1|HIGH|unchallenged|security-reviewer
C-F1|P3|correctness|src/a.sh:2|MEDIUM||code-reviewer
ERR_2|P3|error-handling|src/a.sh:3|MEDIUM|refined|' --mode external --pr 7
assert_exit 0 "$CODE" "exit 0"
assert_equal "SEC-1|P2|security|src/a.sh:1|open|HIGH|unchallenged,C-F1|P3|correctness|src/a.sh:2|open|MEDIUM|unchallenged,ERR_2|P3|error-handling|src/a.sh:3|open|MEDIUM|refined" "$(_key MARKER_ROWS)" "empty disposition → unchallenged"
assert_equal "" "$ERR" "no warnings"
_route 'F1|P3|correctness|src/a.sh:2||unchallenged|' --mode external --pr 7
assert_equal "LEDGER_WARN: PR#7 finding 'F1' from unknown has no confidence — treated as MEDIUM" "$ERR" "empty agent is named 'unknown'"

_flow_test_begin "an out-of-vocabulary disposition is unchallenged with a warning, not a rejection"
_route 'F1|P2|correctness|src/a.sh:1|HIGH|maybe|code-reviewer' --mode external --pr 7
assert_exit 0 "$CODE" "routed"
assert_equal "F1|P2|correctness|src/a.sh:1|open|HIGH|unchallenged" "$(_key MARKER_ROWS)" "disposition → unchallenged"
assert_equal "LEDGER_WARN: PR#7 finding 'F1' from code-reviewer has invalid disposition 'maybe' — treated as unchallenged" "$ERR" "warning names the value"

_flow_test_begin "whitespace around fields and CRLF line endings are tolerated"
_route "$(printf 'F1 | P2 | correctness | src/a.sh:1 | HIGH | consensus | code-reviewer\r\n')" --mode external --pr 7
assert_exit 0 "$CODE" "routed"
assert_equal "F1|P2|correctness|src/a.sh:1|open|HIGH|consensus" "$(_key MARKER_ROWS)" "fields trimmed, CR removed"

# --- marker encoding ----------------------------------------------------------

_flow_test_begin "characters that would break the marker are percent-encoded in category and location"
_route 'F1|P2|correctness|app/[id]/page.tsx:4|HIGH|unchallenged|code-reviewer' --mode external --pr 7
assert_equal "F1|P2|correctness|app/%5Bid%5D/page.tsx:4|open|HIGH|unchallenged" "$(_key MARKER_ROWS)" "brackets encoded"
_route 'F1|P2|edge,case|src/a,b.sh:4|HIGH|unchallenged|code-reviewer' --mode external --pr 7
assert_equal "F1|P2|edge%2Ccase|src/a%2Cb.sh:4|open|HIGH|unchallenged" "$(_key MARKER_ROWS)" "commas encoded (a comma separates rows)"
_route 'F1|P2|correctness|src/100%.sh:4|HIGH|unchallenged|code-reviewer' --mode external --pr 7
assert_equal "F1|P2|correctness|src/100%25.sh:4|open|HIGH|unchallenged" "$(_key MARKER_ROWS)" "percent encoded, so encoding is unambiguous"
_route 'F1|P2|correctness|docs/a-->b.md:1|HIGH|unchallenged|code-reviewer' --mode external --pr 7
assert_equal "F1|P2|correctness|docs/a--%3Eb.md:1|open|HIGH|unchallenged" "$(_key MARKER_ROWS)" "'>' encoded, so the HTML comment cannot close early"
_route "$(printf 'F1|P2|correctness|src/caf\xc3\xa9.md:1|HIGH|unchallenged|code-reviewer')" --mode external --pr 7
assert_equal "F1|P2|correctness|src/caf%C3%A9.md:1|open|HIGH|unchallenged" "$(_key MARKER_ROWS)" "non-ASCII encoded byte by byte"
_route 'F1|P2|correctness|src/a.sh:4 grep \| head|HIGH|unchallenged|code-reviewer' --mode external --pr 7
assert_exit 0 "$CODE" "an escaped pipe does not add a field"
assert_equal "F1|P2|correctness|src/a.sh:4 grep %7C head|open|HIGH|unchallenged" "$(_key MARKER_ROWS)" "escaped pipe encoded"

_flow_test_begin "plain locations are not encoded (must stay silent)"
_route 'F1|P2|error-handling|plugins/flow/bin/x_y-z.sh:10-12|HIGH|unchallenged|code-reviewer' --mode external --pr 7
assert_equal "F1|P2|error-handling|plugins/flow/bin/x_y-z.sh:10-12|open|HIGH|unchallenged" "$(_key MARKER_ROWS)" "unchanged"

# --- input removal and examined count ---------------------------------------

_flow_test_begin "input removal: no rows is an error unless the review really had no findings"
_route "" --mode external --pr 7
assert_exit 1 "$CODE" "zero rows without --allow-empty → exit 1"
assert_equal "0" "$(_key ROWS_READ)" "reports ROWS_READ=0"
assert_not_contains "DECISION=" "$OUT" "no decision from an empty read"
_route "" --mode external --pr 7 --allow-empty
assert_exit 0 "$CODE" "--allow-empty → exit 0"
assert_equal "APPROVE" "$(_key DECISION)" "empty external review approves"
assert_equal "" "$(_key MARKER_ROWS)" "empty marker"
_route "" --mode self --pr 7 --allow-empty
assert_equal "COMMENT" "$(_key DECISION)" "empty self-review is a comment"

_flow_test_begin "blank lines are not rows"
_route 'F1|P3|docs|a.md:1|HIGH|unchallenged|code-reviewer

F2|P3|docs|a.md:2|HIGH|unchallenged|code-reviewer

F3|P3|docs|a.md:3|HIGH|unchallenged|code-reviewer' --mode external --pr 7
assert_equal "3" "$(_key ROWS_READ)" "3 rows read, blank lines skipped"

_flow_test_begin "--input reads the same rows as stdin"
printf '%s\n' "$MIXED" > "$FFR_DIR/rows"
"$HELPER" --mode external --pr 7 --input "$FFR_DIR/rows" > "$FFR_DIR/out2" 2>/dev/null </dev/null
assert_equal "$(printf 'ROWS_READ=2\nCOUNT_P1=0\nCOUNT_P2=1\nCOUNT_P3=0\nCOUNT_NEEDS_INVESTIGATION=1\nNEEDS_INVESTIGATION=F2\nDECISION=REQUEST_CHANGES\nMARKER_ROWS=F1|P2|correctness|src/b.sh:4|open|HIGH|consensus')" "$(cat "$FFR_DIR/out2")" "full stdout, keys in contract order"

# --- a real posted marker -----------------------------------------------------

_flow_test_begin "real input: the review marker posted on PR #220, cycle 1"
MARKER_FILE="$FIXTURES/pr-220-cycle-1.marker.txt"
assert_file_exists "$MARKER_FILE" "fixture present"
RAW=$(sed 's/.*FINDINGS:\[//; s/\].*//' "$MARKER_FILE")
# Independent enumeration of the fixture: rows are comma-separated.
EXPECTED_ROWS=$(tr ',' '\n' <<<"$RAW" | grep -c '|')
# The posted marker is legacy 5-field (no confidence); convert each row to
# route input with confidence and disposition left empty.
ROWS=$(tr ',' '\n' <<<"$RAW" | awk -F'|' 'NF>=5 {print $1"|"$2"|"$3"|"$4"|||unknown"}')
_route "$ROWS" --mode external --pr 220
assert_exit 0 "$CODE" "routed"
assert_equal "14" "$EXPECTED_ROWS" "fixture holds 14 rows (hand count of the posted marker)"
assert_equal "$EXPECTED_ROWS" "$(_key ROWS_READ)" "ROWS_READ reconciles with the fixture's own row count"
assert_equal "5" "$(_key COUNT_P1)" "P1: F1 F2 F3 F7 F8"
assert_equal "5" "$(_key COUNT_P2)" "P2: F4 F6 F9 F11 F13"
assert_equal "4" "$(_key COUNT_P3)" "P3: F5 F10 F12 F14"
assert_equal "REQUEST_CHANGES" "$(_key DECISION)" "P1s present"
WARNS=$(grep -c '^LEDGER_WARN: PR#220 finding ' <<<"$ERR")
assert_equal "14" "$WARNS" "one no-confidence warning per row"
MARKER_COUNT=$(tr ',' '\n' <<<"$(_key MARKER_ROWS)" | grep -c '|MEDIUM|unchallenged$')
assert_equal "14" "$MARKER_COUNT" "every row written 7-field as MEDIUM|unchallenged"
