# Tests for #126 — the merge finding-ledger seed must scan BOTH marker streams.
#
# Contract under test:
#   - commands/merge.md's "Finding-Ledger Seed" diagnostic block queries both the reviews
#     stream (repos/.../pulls/N/reviews, where FLOW_REVIEW_CYCLE lives) AND the issue-comments
#     stream (repos/.../issues/N/comments, where FLOW_RESOLUTION_CYCLE lives), then unions the
#     hits. Scanning only issue-comments (the bug) undercounted review-body markers to zero.
#   - A "marker" is NAME:<digits>. The select requires FLOW_*_CYCLE:[0-9] so prose mentions
#     and unsubstituted placeholders (FLOW_REVIEW_CYCLE:{N}) are NOT counted and never produce
#     a spurious diagnostic. SEED_MARKER_COUNT=0 then means genuinely absent.
#   - The union and count jq steps fail CLOSED (STATE=unavailable) on malformed JSON, never
#     collapsing to a false STATE=empty.
#   - The seed is a diagnostic preview; the authoritative gate (next block) already scans both.

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
MERGE_MD="$PLUGIN_DIR/commands/merge.md"

# --- source-presence: seed scans both streams + fail-closed diagnostics ------
_flow_test_begin "merge.md seed scans the reviews stream (not only issue comments)"
if [ ! -f "$MERGE_MD" ]; then
  _flow_assert_fail "merge.md missing"
else
  CONTENT=$(cat "$MERGE_MD")
  assert_contains 'repos/$REPO/pulls/$PR_NUM/reviews' "$CONTENT" "seed queries the reviews stream"
  assert_contains 'repos/$REPO/issues/$PR_NUM/comments' "$CONTENT" "seed queries the issue-comments stream"
  assert_contains "SEED_SCANNED=reviews,issue-comments" "$CONTENT" "seed names both scanned surfaces"
  assert_contains "DIAGNOSTIC PREVIEW ONLY" "$CONTENT" "seed documents it is a preview, not the gate"
  # A marker is NAME:<digits> — the select requires a digit after the colon so prose and
  # `:{N}` placeholders are excluded (no false count, no spurious diagnostic).
  assert_contains 'test("FLOW_RESOLUTION_CYCLE:[0-9]|FLOW_REVIEW_CYCLE:[0-9]")' "$CONTENT" "seed select requires a digit after the colon"
  # Both jq steps (union + count) fail closed on malformed JSON, not STATE=empty.
  assert_contains "SEED_JQ_EXIT" "$CONTENT" "union jq exit captured (fail-closed on malformed JSON)"
  assert_contains "union_jq_exit=" "$CONTENT" "malformed union surfaces as STATE=unavailable"
  assert_contains "SEED_COUNT_EXIT" "$CONTENT" "count jq exit captured (fail-closed)"
fi

# --- functional: the select + union + count + classification the seed uses ---
# Mirrors the seed block end-to-end: apply the per-stream :[0-9] select, union both
# streams, capture the union exit (fail closed), count, and classify each row. Proves a
# review-body-only marker is counted (#126), prose/placeholders are excluded, a mixed body
# resolves to the real marker, and a malformed-JSON union fails closed.
_seed_classify() {
  local comments="$1" reviews="$2"
  local sel='[.[] | select(.body | test("FLOW_RESOLUTION_CYCLE:[0-9]|FLOW_REVIEW_CYCLE:[0-9]"))]'
  local c r seed_json jqx
  c=$(printf '%s' "$comments" | jq "$sel")
  r=$(printf '%s' "$reviews"  | jq "$sel")
  seed_json=$(printf '%s\n%s\n' "$c" "$r" | jq -s 'add // []' 2>/dev/null); jqx=$?
  if [ $jqx -ne 0 ]; then echo "STATE=unavailable"; return; fi
  echo "COUNT=$(echo "$seed_json" | jq 'length')"
  echo "$seed_json" | jq -r '.[] |
    ([.body | scan("FLOW_(RESOLUTION|REVIEW)_CYCLE:([0-9]+)")] | last) as $last |
    "SEED=id=\(.id) surface=\(.surface) kind=\($last[0]) cycle=\($last[1])"
  '
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

_flow_test_begin "prose mention (no colon) and placeholder (:{N}) are NOT counted"
# Neither a bare prose mention of the marker NAME nor an unsubstituted :{N} placeholder
# (which the self-review template carries in its format-guide comment) is a real marker;
# both must be excluded by the select so they never inflate the count or alarm the operator.
OUT=$(_seed_classify \
  '[{"id":11,"body":"This body carries the FLOW_REVIEW_CYCLE marker (what was FOUND)."},
    {"id":13,"body":"guide: FLOW_REVIEW_CYCLE:{N} FINDINGS:[...]"}]' \
  '[{"id":12,"body":"<!-- FLOW_REVIEW_CYCLE:3 FINDINGS:[F1|P2|x|a:1|open] -->","surface":"reviews"}]')
assert_contains "COUNT=1" "$OUT" "prose + placeholder excluded; only the real marker counts"
assert_contains "kind=REVIEW cycle=3" "$OUT" "the genuine marker is still parsed"

_flow_test_begin "mixed body (placeholder prose + real marker) resolves to the real cycle"
# A single body that contains both the :{N} format guide and the real numbered marker must
# classify by the real marker — scan over the whole body picks the digit-bearing match.
OUT=$(_seed_classify \
  '[]' \
  '[{"id":14,"surface":"reviews","body":"guide FLOW_REVIEW_CYCLE:{N} ... real <!-- FLOW_REVIEW_CYCLE:5 FINDINGS:[] -->"}]')
assert_contains "COUNT=1" "$OUT" "mixed body counts once"
assert_contains "cycle=5" "$OUT" "the real numbered marker wins over the placeholder"

_flow_test_begin "malformed-JSON union fails closed (jq exits non-zero -> STATE=unavailable)"
# Mirrors the seed's union line directly (the real seed feeds the raw per-stream gh output,
# which on a weird gh-exit-0 case may be non-JSON, into `jq -s 'add // []'`). The fail-closed
# guard keys on the captured jq exit, so prove that a non-JSON operand makes jq exit non-zero
# rather than silently producing an empty array.
SEED_JSON=$(printf '%s\n%s\n' 'not-json' '[{"id":1}]' | jq -s 'add // []' 2>/dev/null); SEED_JQ_EXIT=$?
if [ "$SEED_JQ_EXIT" != "0" ]; then
  _flow_assert_pass "malformed operand makes the union jq exit non-zero (caught by SEED_JQ_EXIT)"
else
  _flow_assert_fail "malformed operand should make the union jq exit non-zero, got exit 0"
fi
# And the normal one-empty-stream case must NOT trip the guard (exit 0).
printf '%s\n%s\n' '[]' '[{"id":1}]' | jq -s 'add // []' >/dev/null 2>&1
assert_equal "0" "$?" "an empty stream + a populated stream unions cleanly (exit 0)"
