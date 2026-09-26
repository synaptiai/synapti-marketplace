# Tests for #126 — the merge finding-ledger seed must scan BOTH marker streams.
#
# Contract under test:
#   - commands/merge.md's "Finding-Ledger Seed" diagnostic block queries both the reviews
#     stream (repos/.../pulls/N/reviews, where FLOW_REVIEW_CYCLE lives) AND the issue-comments
#     stream (repos/.../issues/N/comments, where FLOW_RESOLUTION_CYCLE lives). Scanning only
#     issue-comments (the bug) undercounted review-body markers to zero.
#   - Both seed selects use the gate's marker shape `<!-- NAME:<digits> `, so prose mentions
#     and unsubstituted placeholders (FLOW_REVIEW_CYCLE:{N}) are not counted.
#   - The seed's union and count jq steps capture their exit codes (fail closed).
#   - The authoritative finding-ledger gate captures the exit of all four jq passes and
#     blocks the merge when any of them fails.

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
  # A marker is `<!-- NAME:<digits> ` — the seed uses the same shape the gate
  # selects on, so the preview cannot count a marker the gate would drop, and
  # prose or a `:{N}` placeholder is excluded (no false count, no spurious
  # diagnostic).
  assert_contains 'test("<!-- FLOW_RESOLUTION_CYCLE:[0-9]+ |<!-- FLOW_REVIEW_CYCLE:[0-9]+ ")' "$CONTENT" "seed select is the gate's marker shape"
  # Both streams are seeded, so both selects must carry that shape — one of the
  # two reverting to the bare token would still satisfy a single-occurrence check.
  assert_equal "2" "$(grep -c 'test("<!-- FLOW_RESOLUTION_CYCLE:\[0-9\]+ |<!-- FLOW_REVIEW_CYCLE:\[0-9\]+ ")' "$MERGE_MD")" "both seed selects carry it"
  assert_equal "0" "$(grep -c 'test("FLOW_RESOLUTION_CYCLE:\[0-9\]|FLOW_REVIEW_CYCLE:\[0-9\]")' "$MERGE_MD")" "the looser form is gone"
  # Both jq steps (union + count) fail closed on malformed JSON, not STATE=empty.
  assert_contains "SEED_JQ_EXIT" "$CONTENT" "union jq exit captured (fail-closed on malformed JSON)"
  assert_contains "union_jq_exit=" "$CONTENT" "malformed union surfaces as STATE=unavailable"
  assert_contains "SEED_COUNT_EXIT" "$CONTENT" "count jq exit captured (fail-closed)"
fi

# --- the authoritative gate captures its jq exits too ------------------------
# The seed above is a preview and fails closed. The gate 150 lines below it ran
# four jq filter passes and checked only gh's exit. gh exiting 0 does not mean
# the filter ran: one comment with a null body aborts `.body | test(...)` with
# jq exit 5, and the gate then reads an empty RESOLUTION_BODY as "no findings"
# and an empty RES_UNTRUSTED as "nothing untrusted" — the pair that opens it.
_flow_test_begin "merge.md's finding-ledger gate fails closed when a jq pass fails"
CONTENT=$(cat "$MERGE_MD")
assert_contains "JQ_EXIT_RES=" "$CONTENT" "the resolution body filter captures its exit"
assert_contains "JQ_EXIT_RES_U=" "$CONTENT" "so does the untrusted-resolution count"
assert_contains "JQ_EXIT_REV=" "$CONTENT" "so does the review body filter"
assert_contains "JQ_EXIT_REV_U=" "$CONTENT" "so does the untrusted-review count"
# All four are named in one fail-closed condition. Scoped to the matching line
# so a failure prints that line, not the whole command file.
GATE_COND=$(grep -n 'JQ_EXIT_RES -ne 0' "$MERGE_MD" | head -1)
assert_contains "JQ_EXIT_RES_U -ne 0" "$GATE_COND" "the untrusted-resolution pass is in the same condition"
assert_contains "JQ_EXIT_REV -ne 0" "$GATE_COND" "so is the review pass"
assert_contains "JQ_EXIT_REV_U -ne 0" "$GATE_COND" "so is the untrusted-review pass"
# And that condition blocks rather than warns.
GATE_ACTION=$(grep -A2 'JQ_EXIT_RES -ne 0' "$MERGE_MD" | head -3)
assert_contains "emit_block" "$GATE_ACTION" "a failed pass blocks the merge"
