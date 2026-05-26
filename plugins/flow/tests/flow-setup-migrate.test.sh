# Tests that /flow:setup wires the deprecated-settings migration (re-run path)
# and that the migrator helper ships executable.

SETUP_CMD="$REPO_ROOT/plugins/flow/commands/setup.md"
MIGRATOR="$REPO_ROOT/plugins/flow/bin/flow-migrate-settings.sh"

_flow_test_begin "setup.md wires the deprecated-settings migration on re-run"
if [ ! -f "$SETUP_CMD" ]; then
  _flow_assert_fail "setup.md missing"
else
  CONTENT=$(cat "$SETUP_CMD")
  assert_contains "flow-migrate-settings.sh" "$CONTENT" "setup invokes the migrator"
  assert_contains '"$MIGRATOR" --apply' "$CONTENT" "apply path documented"
  assert_contains "AskUserQuestion" "$CONTENT" "rewrite is gated behind a confirmation prompt"
  assert_contains "requireGoalForStart" "$CONTENT" "documents the deprecated key being migrated"
  assert_contains "nothing breaks if declined" "$CONTENT" "frames it as optional hygiene (read-only migration still works)"
fi

_flow_test_begin "migrator helper ships and is executable"
if [ -x "$MIGRATOR" ]; then
  _flow_assert_pass "flow-migrate-settings.sh is executable"
else
  _flow_assert_fail "flow-migrate-settings.sh missing or not executable: $MIGRATOR"
fi

_flow_test_begin "setup migration is classified Tier 2 (confirmation-gated rewrite)"
CONTENT=$(cat "$SETUP_CMD")
assert_contains "flow-migrate-settings.sh --apply" "$CONTENT" "tier table names the apply action"
