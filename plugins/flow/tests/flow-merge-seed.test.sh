# Tests for #126 — the merge finding-ledger seed must scan BOTH marker streams.
#
# Contract under test:
#   - commands/merge.md's "Finding-Ledger Seed" diagnostic block queries both the reviews
#     stream (repos/.../pulls/N/reviews, where FLOW_REVIEW_CYCLE lives) AND the issue-comments
#     stream (repos/.../issues/N/comments, where FLOW_RESOLUTION_CYCLE lives), then unions the
#     hits. Scanning only issue-comments (the bug) undercounted review-body markers to zero.
#   - The seed names the scanned surfaces (SEED_SCANNED) and distinguishes a truly-absent marker
#     (SEED_MARKER_COUNT=0) from a present-but-malformed one (SEED_FORMAT_INVALID).
#   - The seed is a diagnostic preview; the authoritative gate (next block) already scans both.

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
MERGE_MD="$PLUGIN_DIR/commands/merge.md"

# --- source-presence: seed scans both streams + better diagnostics -----------
_flow_test_begin "merge.md seed scans the reviews stream (not only issue comments)"
if [ ! -f "$MERGE_MD" ]; then
  _flow_assert_fail "merge.md missing"
else
  CONTENT=$(cat "$MERGE_MD")
  assert_contains 'repos/$REPO/pulls/$PR_NUM/reviews' "$CONTENT" "seed queries the reviews stream"
  assert_contains 'repos/$REPO/issues/$PR_NUM/comments' "$CONTENT" "seed queries the issue-comments stream"
  assert_contains "SEED_SCANNED=reviews,issue-comments" "$CONTENT" "seed names both scanned surfaces"
  assert_contains "SEED_FORMAT_INVALID" "$CONTENT" "seed distinguishes malformed markers from absent"
  assert_contains "DIAGNOSTIC PREVIEW ONLY" "$CONTENT" "seed documents it is a preview, not the gate"
  # The select must require the `:` form so a bare prose mention of the marker NAME is not
  # selected (and so the seed's selection matches the authoritative gate's test("...:")).
  assert_contains 'test("FLOW_RESOLUTION_CYCLE:|FLOW_REVIEW_CYCLE:")' "$CONTENT" "seed select requires the colon form (matches the gate, ignores prose)"
  # The union must fail closed on a malformed-JSON operand, not collapse to STATE=empty.
  assert_contains "SEED_JQ_EXIT" "$CONTENT" "union jq exit captured (fail-closed on malformed JSON)"
  assert_contains "union_jq_exit=" "$CONTENT" "malformed union surfaces as STATE=unavailable, not empty"
fi

# --- functional: the select + union + classification logic the seed uses -----
# Mirrors the seed block end-to-end: apply the per-stream `:`-form select (so a prose
# mention is excluded), union both streams, count, and classify each row as a valid SEED
# line or SEED_FORMAT_INVALID. Proves a review-body-only marker is counted (the #126
# regression), a digit-less marker is flagged malformed, and a prose mention is ignored.
_seed_classify() {
  local comments="$1" reviews="$2"
  local sel='[.[] | select(.body | test("FLOW_RESOLUTION_CYCLE:|FLOW_REVIEW_CYCLE:"))]'
  local c r seed_json
  c=$(printf '%s' "$comments" | jq "$sel")
  r=$(printf '%s' "$reviews"  | jq "$sel")
  seed_json=$(printf '%s\n%s\n' "$c" "$r" | jq -s 'add // []')
  echo "COUNT=$(echo "$seed_json" | jq 'length')"
  echo "$seed_json" | jq -r '.[] | (
    ([.body | scan("FLOW_(RESOLUTION|REVIEW)_CYCLE:([0-9]+)")] | last) as $last |
    if $last == null then
      "SEED_FORMAT_INVALID=id=\(.id) surface=\(.surface)"
    else
      "SEED=id=\(.id) surface=\(.surface) kind=\($last[0]) cycle=\($last[1])"
    end
  )'
}

_flow_test_begin "review-body-only marker is counted (the #126 regression)"
OUT=$(_seed_classify \
  '[]' \
  '[{"id":9,"body":"<!-- FLOW_REVIEW_CYCLE:2 FINDINGS:[F1|P2|correctness|src/x.ts:8|open] -->","surface":"reviews"}]')
assert_contains "COUNT=1" "$OUT" "a marker only in a review body is found (not undercounted to 0)"
assert_contains "kind=REVIEW cycle=2" "$OUT" "review-cycle marker parsed from the reviews stream"

_flow_test_begin "markers in both streams union (no double-loss)"
OUT=$(_seed_classify \
  '[{"id":1,"body":"<!-- FLOW_RESOLUTION_CYCLE:2 RESOLVED:[F1] ESCALATED:[] DISPUTED:[] -->","surface":"issue-comments"}]' \
  '[{"id":9,"body":"<!-- FLOW_REVIEW_CYCLE:2 FINDINGS:[F1|P2|correctness|src/x.ts:8|open] -->","surface":"reviews"}]')
assert_contains "COUNT=2" "$OUT" "both streams contribute to the count"
assert_contains "kind=RESOLUTION" "$OUT" "resolution marker seen"
assert_contains "kind=REVIEW" "$OUT" "review marker seen"

_flow_test_begin "present-but-malformed marker is flagged SEED_FORMAT_INVALID"
OUT=$(_seed_classify \
  '[]' \
  '[{"id":10,"body":"FLOW_REVIEW_CYCLE: no digits here","surface":"reviews"}]')
assert_contains "COUNT=1" "$OUT" "malformed marker still counted as present"
assert_contains "SEED_FORMAT_INVALID=id=10" "$OUT" "malformed marker flagged, not silently dropped"

_flow_test_begin "prose mention of a marker name (no colon) is NOT selected (no false SEED_FORMAT_INVALID)"
# A body that names the marker in prose, with no real :N marker, must be excluded by the
# select so it never produces a spurious SEED_FORMAT_INVALID line. self-review-comment.md
# adds exactly such prose, so this guards a real false-positive path.
OUT=$(_seed_classify \
  '[{"id":11,"body":"This body carries the FLOW_REVIEW_CYCLE marker (what was FOUND).","surface":"issue-comments"}]' \
  '[{"id":12,"body":"<!-- FLOW_REVIEW_CYCLE:3 FINDINGS:[F1|P2|x|a:1|open] -->","surface":"reviews"}]')
assert_contains "COUNT=1" "$OUT" "prose mention excluded; only the real marker counts"
assert_not_contains "SEED_FORMAT_INVALID" "$OUT" "prose mention does not produce a false malformed flag"
assert_contains "kind=REVIEW cycle=3" "$OUT" "the genuine marker is still parsed"
