# Tests for #124 — self-reviewed PRs must not false-block at the merge finding-ledger gate.
#
# Contract under test:
#   - The self-review path of commands/review.md emits a FLOW_RESOLUTION_CYCLE marker as a
#     PR issue comment (gh pr comment), recording fix-forwarded finding IDs as RESOLVED — the
#     same marker/placement /flow:address uses and the only surface the merge gate reads RESOLVED
#     from. Without it, a solo-authored PR whose every finding was fix-forwarded false-blocks.
#   - templates/self-review-comment.md carries the FLOW_REVIEW_CYCLE marker (previously missing).
#   - references/finding-ledger-parser.md documents the two-emitter (address + self-review) model.
#   - The merge gate's classification logic is UNCHANGED — the fix is purely on the emit side.
#
# These are source-presence lints (the repo convention for command/template markdown); the actual
# emission happens when Claude runs the command. See flow-pr-merge-goal-gate.test.sh for the pattern.

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
REVIEW_MD="$PLUGIN_DIR/commands/review.md"
SELF_TMPL="$PLUGIN_DIR/templates/self-review-comment.md"
PARSER_REF="$PLUGIN_DIR/references/finding-ledger-parser.md"
MERGE_MD="$PLUGIN_DIR/commands/merge.md"

# --- review.md: self-review emits the resolution marker ----------------------
_flow_test_begin "review.md self-review path emits a FLOW_RESOLUTION_CYCLE marker"
if [ ! -f "$REVIEW_MD" ]; then
  _flow_assert_fail "review.md missing"
else
  CONTENT=$(cat "$REVIEW_MD")
  assert_contains "Self-review resolution marker" "$CONTENT" "self-review resolution step present"
  assert_contains "FLOW_RESOLUTION_CYCLE" "$CONTENT" "names the resolution marker"
  assert_contains 'gh pr comment "$PR_NUM"' "$CONTENT" "posts via issue-comments stream (gh pr comment)"
  assert_contains "templates/resolution-comment.md" "$CONTENT" "builds body from the resolution template"
  assert_contains "RESOLVED:[" "$CONTENT" "records fix-forwarded IDs as RESOLVED"
  assert_contains "resolutionCommentTaskId" "$CONTENT" "tracks the resolution-post task"
fi

_flow_test_begin "review.md creates the resolution-post task in the self-review path"
CONTENT=$(cat "$REVIEW_MD")
# Assert on the TaskCreate form specifically (not the bare label, which also appears in the
# step-8 gate prose) so removing the step-5 TaskCreate would actually fail this test.
assert_contains 'TaskCreate("Post self-review resolution marker"' "$CONTENT" "step-5 TaskCreate for resolution marker present"

_flow_test_begin "review.md gates step 8 on the resolution-marker task (no silent skip on gh failure)"
# A failed `gh pr comment` must NOT advance the workflow — otherwise the resolution marker
# is silently absent and the merge gate false-blocks again (the bug this whole change fixes).
CONTENT=$(cat "$REVIEW_MD")
assert_contains 'BOTH "Post self-review comment" AND "Post self-review resolution marker"' "$CONTENT" "step 8 requires both self-review posting tasks"
assert_contains "RES_EXIT" "$CONTENT" "resolution post captures gh exit for a machine-checkable backstop"
assert_contains "leave the task" "$CONTENT" "resolution post has a failure backstop (retry, do not advance)"

_flow_test_begin "review.md step 8 has a zero-findings carve-out (no deadlock when nothing to resolve)"
# A zero-findings self-review legitimately skips the resolution marker; step 8 must allow the
# task to be completed as SKIP rather than deadlocking on the both-tasks gate.
CONTENT=$(cat "$REVIEW_MD")
assert_contains "Zero-findings exception" "$CONTENT" "step 8 documents the zero-findings carve-out"
assert_contains "SKIP — no findings to resolve" "$CONTENT" "zero-findings path completes the task as SKIP"

_flow_test_begin "review.md self-review still posts FLOW_REVIEW_CYCLE in the review body"
CONTENT=$(cat "$REVIEW_MD")
assert_contains "FLOW_REVIEW_CYCLE" "$CONTENT" "review-body marker retained (records what was found)"

# --- self-review template carries the review marker --------------------------
_flow_test_begin "self-review-comment.md carries the FLOW_REVIEW_CYCLE marker"
if [ ! -f "$SELF_TMPL" ]; then
  _flow_assert_fail "self-review-comment.md missing"
else
  TMPL=$(cat "$SELF_TMPL")
  assert_contains "FLOW_REVIEW_CYCLE:" "$TMPL" "template emits the review-cycle marker"
  assert_contains "FLOW_RESOLUTION_CYCLE" "$TMPL" "template explains the separate resolution marker"
fi

# --- parser reference documents the two-emitter model ------------------------
_flow_test_begin "finding-ledger-parser.md documents self-review as a FLOW_RESOLUTION_CYCLE emitter"
if [ ! -f "$PARSER_REF" ]; then
  _flow_assert_fail "finding-ledger-parser.md missing"
else
  REF=$(cat "$PARSER_REF")
  assert_contains "Two emitters" "$REF" "documents both emitters of the resolution marker"
  assert_contains "Self-review" "$REF" "names the self-review emitter"
  assert_contains "issue-comments stream" "$REF" "documents placement (issue comments, not review body)"
fi

# --- the gate classification logic is unchanged (guard against accidental edits) ---
_flow_test_begin "merge.md finding-ledger gate still balances FINDINGS - RESOLVED unchanged"
if [ ! -f "$MERGE_MD" ]; then
  _flow_assert_fail "merge.md missing"
else
  MCONTENT=$(cat "$MERGE_MD")
  assert_contains "comm -23" "$MCONTENT" "gate still uses comm -23 FINDINGS vs RESOLVED"
  assert_contains "Unresolved findings:" "$MCONTENT" "gate still blocks on unmatched findings"
fi
