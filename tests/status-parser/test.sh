#!/usr/bin/env bash
# Verify status.md's ledger parser stays in lockstep with merge.md's parser.
# Both commands consume FLOW_REVIEW_CYCLE and FLOW_RESOLUTION_CYCLE markers
# but render different surfaces (status: per-priority tally with state;
# merge: pass/fail gate). The shared invariant: the same marker corpus must
# yield consistent finding IDs and priorities through both pipelines.
#
# This test exercises the parsers at the bash-pipeline level using the same
# fixtures as tests/issue-86/, plus parity assertions specific to status.md's
# tally output (PRIORITY|STATE rows).
#
# Exits 0 on pass, 1 on first parity failure, 2 on missing fixtures.

set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURE_DIR="$DIR/markers"
PASS=0
FAIL=0

for f in legacy-5-field.txt extended-7-field.txt mixed-cycles.txt with-resolution.txt; do
  if [ ! -f "$FIXTURE_DIR/$f" ]; then
    echo "FATAL: missing fixture $FIXTURE_DIR/$f" >&2
    exit 2
  fi
done

safe() { printf '%s' "${1:-}" | tr -cd '[:print:]' | cut -c1-64; }

assert_eq() {
  local label="$1" expected="$2" actual="$3" context="${4:-}"
  if [ "$expected" = "$actual" ]; then
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

# status.md-style parser (extracted from plugins/flow/commands/status.md
# lines 97-127). Outputs PRIORITY|STATE rows for tally aggregation.
# Trust filter is bypassed here — the test corpus is local, not gh-fetched —
# but the rest of the pipeline mirrors the production parser exactly.
status_md_parse() {
  local body="$1"
  local resolved="$2"
  local escalated="$3"
  local disputed="${4:-}"

  local raw
  raw=$(echo "$body" | grep -o 'FINDINGS:\[[^]]*\]' | sed 's/^FINDINGS:\[//;s/\]$//')
  echo "$raw" | tr ',' '\n' | while IFS='|' read -r ID PRIORITY CAT LOC STATUS; do
    [ -z "$ID" ] && continue
    # ID grammar check (mirrors status.md):
    case "$ID" in
      [A-Za-z]*) ;;
      *) continue ;;
    esac
    case "$ID" in *[!A-Za-z0-9_-]*) continue ;; esac
    case "$PRIORITY" in
      P1|P2|P3) ;;
      *) continue ;;
    esac
    # Precedence: RESOLVED > ESCALATED > DISPUTED > in_fix_forward.
    case ",$resolved," in *",$ID,"*) continue ;; esac
    case ",$escalated," in *",$ID,"*) STATE=escalated ;;
      *) case ",$disputed," in *",$ID,"*) STATE=disputed ;;
           *) STATE=in_fix_forward ;; esac ;;
    esac
    echo "${PRIORITY}|${STATE}"
  done
}

# merge.md-style parser (extracted from plugins/flow/commands/merge.md
# lines 109-112). Outputs the set of finding IDs from the latest cycle.
merge_md_parse_ids() {
  local body="$1"
  echo "$body" | grep -o 'FINDINGS:\[[^]]*\]' | sed 's/^FINDINGS:\[//;s/\]$//' | tr ',' '\n' | sed 's/|.*//' | tr -d ' ' | sort | grep -v '^$' || true
}

# Test 1: legacy 5-field marker, no resolution — all findings in_fix_forward
echo "=== Test 1: legacy 5-field marker (no resolution comment yet) ==="
BODY=$(cat "$FIXTURE_DIR/legacy-5-field.txt")
TALLY=$(status_md_parse "$BODY" "" "" "" | sort | uniq -c | awk '{$1=$1};1' | paste -sd, -)
assert_eq "legacy 5-field tally" "1 P1|in_fix_forward,1 P2|in_fix_forward,1 P3|in_fix_forward" "$TALLY"

IDS=$(merge_md_parse_ids "$BODY" | paste -sd, -)
assert_eq "legacy IDs (parity with merge.md)" "F1,F2,F3" "$IDS"

# Test 2: extended 7-field marker — same tally semantics
echo ""
echo "=== Test 2: extended 7-field marker (with confidence + disposition) ==="
BODY=$(cat "$FIXTURE_DIR/extended-7-field.txt")
TALLY=$(status_md_parse "$BODY" "" "" "" | sort | uniq -c | awk '{$1=$1};1' | paste -sd, -)
assert_eq "extended 7-field tally (no resolution)" "1 P1|in_fix_forward,1 P2|in_fix_forward,1 P3|in_fix_forward" "$TALLY"

# Test 3: mixed cycles — only the LAST cycle's findings count
echo ""
echo "=== Test 3: mixed-cycles marker (only last cycle counts) ==="
BODY=$(cat "$FIXTURE_DIR/mixed-cycles.txt")
LAST_REVIEW=$(echo "$BODY" | grep 'FLOW_REVIEW_CYCLE:' | tail -1)
TALLY=$(status_md_parse "$LAST_REVIEW" "" "" "" | sort | uniq -c | awk '{$1=$1};1' | paste -sd, -)
assert_eq "mixed last-cycle tally" "1 P1|in_fix_forward,1 P3|in_fix_forward" "$TALLY"

LAST_IDS=$(merge_md_parse_ids "$LAST_REVIEW" | paste -sd, -)
assert_eq "mixed last-cycle IDs (parity with merge.md)" "F3,F4" "$LAST_IDS"

# Test 4: review + resolution — RESOLVED IDs disappear; ESCALATED gets state=escalated
echo ""
echo "=== Test 4: review + resolution markers (full state precedence) ==="
BODY=$(cat "$FIXTURE_DIR/with-resolution.txt")
REVIEW_BODY=$(echo "$BODY" | grep 'FLOW_REVIEW_CYCLE:' | tail -1)
RESOLUTION_BODY=$(echo "$BODY" | grep 'FLOW_RESOLUTION_CYCLE:' | tail -1)

RESOLVED=$(echo "$RESOLUTION_BODY" | grep -o 'RESOLVED:\[[^]]*\]' | sed 's/^RESOLVED:\[//;s/\]$//' | tr -d ' ')
ESCALATED=$(echo "$RESOLUTION_BODY" | grep -o 'ESCALATED:\[[^]]*\]' | sed 's/^ESCALATED:\[//;s/\]$//' | tr -d ' ')
DISPUTED=$(echo "$RESOLUTION_BODY" | grep -o 'DISPUTED:\[[^]]*\]' | sed 's/^DISPUTED:\[//;s/\]$//' | tr -d ' ')

TALLY=$(status_md_parse "$REVIEW_BODY" "$RESOLVED" "$ESCALATED" "$DISPUTED" | sort | uniq -c | awk '{$1=$1};1' | paste -sd, -)
# F1, F3 RESOLVED → drop. F2 DISPUTED → state=disputed.
assert_eq "with-resolution tally (RESOLVED dropped, DISPUTED state)" "1 P2|disputed" "$TALLY"

# Parity: merge.md sees F1,F2,F3 as the FINDINGS; our resolved=F1,F3 means F2 unresolved.
REVIEW_IDS=$(merge_md_parse_ids "$REVIEW_BODY" | paste -sd, -)
RESOLVED_IDS=$(echo "$RESOLVED" | tr ',' '\n' | sort | grep -v '^$' | paste -sd, -)
assert_eq "review IDs (parity with merge.md)" "F1,F2,F3" "$REVIEW_IDS"
assert_eq "resolved IDs (per resolution comment)" "F1,F3" "$RESOLVED_IDS"

# Test 5: hostile ID — `*` would slip past a naive containment check, must be rejected
echo ""
echo "=== Test 5: hostile ID rejection (status.md ID grammar enforcement) ==="
HOSTILE_BODY="<!-- FLOW_REVIEW_CYCLE:1 FINDINGS:[*|P1|security|src/x.ts:1|open,F1|P1|security|src/y.ts:2|open] -->"
TALLY=$(status_md_parse "$HOSTILE_BODY" "" "" "" | sort | uniq -c | awk '{$1=$1};1' | paste -sd, -)
# `*` rejected by `case "$ID" in [A-Za-z]*)`; only F1 survives → 1 row.
assert_eq "hostile ID '*' rejected; F1 survives" "1 P1|in_fix_forward" "$TALLY"

# Test 6: malformed priority — gets rejected (LEDGER_WARN to stderr in production)
echo ""
echo "=== Test 6: malformed priority is rejected ==="
MALFORMED_BODY="<!-- FLOW_REVIEW_CYCLE:1 FINDINGS:[F1|P9|security|src/x.ts:1|open,F2|P2|correctness|src/y.ts:2|open] -->"
TALLY=$(status_md_parse "$MALFORMED_BODY" "" "" "" | sort | uniq -c | awk '{$1=$1};1' | paste -sd, -)
assert_eq "malformed P9 rejected; F2 P2 survives" "1 P2|in_fix_forward" "$TALLY"

echo ""
echo "============================================"
echo "RESULT: $PASS passed, $FAIL failed"
echo "============================================"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
