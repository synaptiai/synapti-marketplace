# Tests for plugins/flow/hooks/scripts/flow-goal-evaluator.sh throttle log + stuck-detection.
# Source-presence lint tests. These are lint-style checks that the new behavior
# remains in the hook script — they catch regressions where someone
# removes the logic during a refactor without realizing it.
#
# Full integration testing (mock-claude subprocess, deterministic-check
# fixtures, end-to-end stuck transitions) is the responsibility of
# flow-goal-evaluator.test.sh; this file is a lighter belt-and-suspenders.

HOOK="$REPO_ROOT/plugins/flow/hooks/scripts/flow-goal-evaluator.sh"

# --- throttle block writes events.jsonl
_flow_test_begin "throttle block writes a throttle-block event to .flow/runs/<id>/events.jsonl"

if [ ! -f "$HOOK" ]; then
  _flow_assert_fail "hook script missing at $HOOK"
else
  CONTENT=$(cat "$HOOK")
  assert_contains "throttle-block" "$CONTENT" "throttle-block event type referenced"
  assert_contains 'flow-active-goal.sh' "$CONTENT" "throttle path resolves active goal for RUN_ID"
  assert_contains '3 continuations in 5min' "$CONTENT" "throttle block reason text present"
  assert_contains 'events.jsonl' "$CONTENT" "events.jsonl write target present"
fi

# --- stuck-detection helper exists
_flow_test_begin "_check_stuck helper defined in hook source"

if [ ! -f "$HOOK" ]; then
  _flow_assert_fail "hook script missing"
else
  CONTENT=$(cat "$HOOK")
  assert_contains "_check_stuck" "$CONTENT" "_check_stuck helper function defined"
  assert_contains "stuck-counter" "$CONTENT" "stuck-counter file referenced"
  assert_contains "failAfterStuckTurns" "$CONTENT" "settings key consulted"
  assert_contains "stuck_no_progress" "$CONTENT" "reason text used in lifecycle transition"
  assert_contains "stuck-detection-fired" "$CONTENT" "stuck event type emitted to events.jsonl"
fi

# --- stuck-detection invoked from both must-pass-fail and judge paths
_flow_test_begin "_check_stuck called from must-pass-fail path"
CONTENT=$(cat "$HOOK")
# Count occurrences of _check_stuck calls. Should be:
#   1× definition (function declaration)
#   1× must-pass-fail path
#   1× judge not_achieved path
#   = 3 total
CALL_COUNT=$(grep -c "_check_stuck" "$HOOK")
if [ "$CALL_COUNT" -ge "3" ]; then
  _flow_assert_pass "expected ≥3 occurrences (definition + 2 call sites); got $CALL_COUNT"
else
  _flow_assert_fail "expected ≥3 _check_stuck occurrences (definition + ≥2 calls); got $CALL_COUNT — stuck-detection may not be integrated into both paths"
fi

# --- lifecycle YAML fragment uses correct status name
_flow_test_begin "lifecycle transition writes status:failed"
CONTENT=$(cat "$HOOK")
# When stuck fires, the hook writes a lifecycle YAML to a temp file with
# status:failed. Verify the literal is present.
assert_contains "status: failed" "$CONTENT" "lifecycle fragment uses 'status: failed'"
assert_contains 'flow-goal-record.sh' "$CONTENT" "transition invokes the canonical writer"
assert_contains '--from-status active' "$CONTENT" "from-status guard prevents racing transitions"
