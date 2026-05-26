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
  assert_contains 'flow-migrate-settings.sh" --apply ".claude/settings.flow.json"' "$CONTENT" "apply path present (resolver inlined in the bash block, not a cross-block \$MIGRATOR)"
  assert_contains "AskUserQuestion" "$CONTENT" "rewrite is gated behind a confirmation prompt"
  assert_contains "requireGoalForStart" "$CONTENT" "documents the deprecated key being migrated"
  assert_contains "nothing breaks if declined" "$CONTENT" "frames it as optional hygiene (read-only migration still works)"
  # Guard the P1 regression: the apply must NOT rely on a bare $MIGRATOR resolved
  # in a separate !-block (bash vars don't persist across blocks -> silent no-op).
  assert_not_contains '"$MIGRATOR" --apply' "$CONTENT" "apply does not depend on a cross-block \$MIGRATOR"
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

# --- behavioral: the re-run detection block degrades cleanly, never blocks setup
_flow_test_begin "setup migration-detection degrades to MIGRATE=skip when no committed settings"
DRYRUN_BLOCK=$(python3 - "$SETUP_CMD" <<'PY'
import sys, re
src = open(sys.argv[1]).read()
after = src.split("### Upgrade deprecated settings", 1)[1]
m = re.search(r"```!\n(.*?)\n```", after, re.S)
sys.stdout.write(m.group(1) if m else "")
PY
)
WORK=$(mktemp -d -t flow-setup-skip.XXXXXX)
# No .claude/settings.flow.json present -> the `[ -f "$SETTINGS" ]` guard is false
# -> the block must emit MIGRATE=skip and exit 0 (setup proceeds, not blocked).
OUT=$(cd "$WORK" && bash -c "$DRYRUN_BLOCK" 2>&1); EXIT=$?
assert_equal "0" "$EXIT" "detection block exits 0 with no committed settings"
assert_contains "MIGRATE=skip" "$OUT" "degrades to skip (no settings or migrator) rather than erroring"
