# Source-presence + contract test for cycle-13 F13 — trigger-policy now
# verifies trigger.target.workflow resolves to an existing workflow YAML.
#
# Lint-style: verify the SKILL.md documents the step + hard-fail semantics.
# Full enforcement is in the validator code path that invokes the skill;
# this catches regressions where the documented step is silently removed.

SKILL="$REPO_ROOT/plugins/flow/skills/trigger-policy/SKILL.md"

_flow_test_begin "F13 — trigger-policy documents target workflow cross-ref step"

if [ ! -f "$SKILL" ]; then
  _flow_assert_fail "trigger-policy/SKILL.md missing at $SKILL"
else
  CONTENT=$(cat "$SKILL")
  assert_contains "Target workflow cross-reference" "$CONTENT" "Step heading present"
  assert_contains "target.workflow" "$CONTENT" "field name documented"
  assert_contains "missing_target_workflow" "$CONTENT" "violation type defined"
  assert_contains "cross_reference_violations" "$CONTENT" "violations bucket named in output"
  assert_contains "plugins/flow/workflows/" "$CONTENT" "plugin workflow path checked"
  assert_contains ".flow/workflows/" "$CONTENT" "project-local override path checked"
  assert_contains "Hard fail" "$CONTENT" "documented as hard fail (not soft warning)"
fi

_flow_test_begin "F13 — overall verdict table includes cross-reference branch"
CONTENT=$(cat "$SKILL")
assert_contains "cross_reference_failed" "$CONTENT" "overall verdict has cross-ref branch"
