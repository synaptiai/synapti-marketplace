# shellcheck shell=bash
# End-to-end: bin/flow-trigger-tier3-check.sh, step 2 of the trigger-policy
# skill. A trigger must forbid merge and release in policy.forbidden_actions,
# unless flow.triggers.allowAutonomousMerge is true in the user's settings.
#
# Ways it can be wrong, written down before the scenarios:
#   M1 a trigger that leaves merge or release out is accepted with the
#      setting false (the default)
#   M2 the setting true in the user's settings has no effect
#   M3 a repository's own settings turn the setting on: a pull request could
#      then relax the check by committing .claude/settings.flow.json
#   M4 a trigger that cannot be read safely (a symbolic link, not YAML) is
#      judged rather than refused
#   M5 a trigger that forbids both is refused

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  _flow_test_begin "e2e-trigger-tier3 prerequisites"
  _flow_assert_pass "SKIP: python3 with PyYAML is required — this run proves nothing"
  return 0 2>/dev/null; exit 0
fi

CHECK=bin/flow-trigger-tier3-check.sh

# _trigger <file> <forbidden actions, YAML flow list>
_trigger() {
  printf 'apiVersion: flow.synapti.ai/v1\nkind: FlowTrigger\nmetadata:\n  id: t3\n  enabled: true\n  created_at: "2026-11-01T10:00:00Z"\ntrigger:\n  type: manual\ntarget:\n  command: "/flow:status"\npolicy:\n  forbidden_actions: %s\n' "$2" > "$E2E_REPO/$1"
  printf 'trigger %s: forbidden_actions %s\n' "$1" "$2" | _e2e_art
}

_flow_test_begin "a trigger that forbids merge and release passes (M5)"
e2e_new tier3-both-forbidden
e2e_describe "forbidden_actions [merge, release]; no setting"
e2e_repo main
_trigger t.trigger.yaml '[merge, release]'
e2e_run_bin "$CHECK" t.trigger.yaml
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_no_out "TIER3_VIOLATION="
e2e_expect_clean_edges

_flow_test_begin "with the setting false a trigger that leaves merge or release out is refused (M1)"
e2e_new tier3-release-missing
e2e_describe "forbidden_actions [merge]; no setting"
e2e_repo main
_trigger t.trigger.yaml '[merge]'
e2e_run_bin "$CHECK" t.trigger.yaml
e2e_expect_equal 2 "$E2E_RC" "the exit status"
e2e_expect_line "TIER3_VIOLATION=release"
e2e_expect_no_out "TIER3_VIOLATION=merge"
e2e_expect_clean_edges

e2e_new tier3-none-forbidden
e2e_describe "forbidden_actions []; no setting"
e2e_repo main
_trigger t.trigger.yaml '[]'
e2e_run_bin "$CHECK" t.trigger.yaml
e2e_expect_equal 2 "$E2E_RC" "the exit status"
e2e_expect_line "TIER3_VIOLATION=merge"
e2e_expect_line "TIER3_VIOLATION=release"
e2e_expect_clean_edges

_flow_test_begin "the setting true in the user's settings lets a trigger leave them out (M2)"
e2e_new tier3-user-allows
e2e_describe "forbidden_actions []; the user's settings set allowAutonomousMerge true"
e2e_repo main
_trigger t.trigger.yaml '[]'
e2e_user_settings '{"flow":{"triggers":{"allowAutonomousMerge":true}}}'
e2e_run_bin "$CHECK" t.trigger.yaml
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_no_out "TIER3_VIOLATION="
e2e_expect_clean_edges

_flow_test_begin "the repository's own settings cannot turn the setting on (M3)"
for f in settings.flow.json settings.flow.local.json; do
  e2e_new "tier3-repo-$f"
  e2e_describe "forbidden_actions []; the repository's .claude/$f sets allowAutonomousMerge true"
  e2e_repo main
  _trigger t.trigger.yaml '[]'
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' '{"flow":{"triggers":{"allowAutonomousMerge":true}}}' > "$E2E_REPO/.claude/$f"
  e2e_run_bin "$CHECK" t.trigger.yaml
  e2e_expect_equal 2 "$E2E_RC" "the exit status"
  e2e_expect_line "TIER3_VIOLATION=merge"
  e2e_expect_clean_edges
done

_flow_test_begin "a trigger that cannot be read safely is not judged (M4)"
e2e_new tier3-symlink
e2e_describe "the trigger file is a symbolic link"
e2e_repo main
_trigger real.yaml '[merge, release]'
ln -s real.yaml "$E2E_REPO/t.trigger.yaml"
e2e_run_bin "$CHECK" t.trigger.yaml
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_err "symbolic link"
e2e_expect_clean_edges

e2e_new tier3-not-yaml
e2e_describe "the trigger file is not YAML"
e2e_repo main
printf 'policy: [unclosed\n' > "$E2E_REPO/t.trigger.yaml"
e2e_run_bin "$CHECK" t.trigger.yaml
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_err "not valid YAML"
e2e_expect_clean_edges

_flow_test_begin "trigger-policy step 2's fence runs the check from an installed plugin"
e2e_new tier3-skill-fence
e2e_describe "the step 2 fence of skills/trigger-policy/SKILL.md, run with CLAUDE_PLUGIN_ROOT set, on a trigger that forbids neither"
e2e_repo main
_trigger t.trigger.yaml '[]'
# The fence is indented under its list item: take the one that runs the
# tier-3 check out and dedent it.
awk '/^   ```bash$/{f=1; buf=""; next} f&&/^   ```$/{ if (buf ~ /flow-trigger-tier3-check/) { printf "%s", buf; exit } f=0; next } f{sub(/^   /,""); buf = buf $0 "\n"}' \
  "$E2E_PLUGIN_DIR/skills/trigger-policy/SKILL.md" > "$E2E_DIR/fence.sh.raw"
e2e_expect_equal yes "$(grep -q 'bin/flow-trigger-tier3-check.sh' "$E2E_DIR/fence.sh.raw" && echo yes || echo no)" "whether the step 2 fence was extracted"
_e2e_run_code "skills/trigger-policy/SKILL.md (step 2 fence)" "" "TRIGGER_YAML=t.trigger.yaml"
e2e_expect_equal 2 "$E2E_RC" "the exit status"
e2e_expect_line "TIER3_VIOLATION=merge"
e2e_expect_clean_edges
