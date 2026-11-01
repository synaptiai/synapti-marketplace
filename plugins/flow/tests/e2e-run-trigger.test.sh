# shellcheck shell=bash
# End-to-end: the concurrency check /flow:run trigger <id> runs before it
# dispatches a trigger's target (run.md's RUN_CONCURRENCY_BLOCK, which
# /flow:trigger run <id> shares), and the FlowRun field it reads.
#
# Each scenario writes a trigger and FlowRuns into a scratch repository's
# .flow/ and runs the block with the invocation's arguments substituted as
# Claude Code substitutes them. One artifact per scenario is written to
# $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the code:
#   C1 an active run of the trigger's target workflow that no trigger started
#      (a /flow:address the user ran by hand) counts as in flight, and the
#      trigger is skipped for a run that is not its own
#   C2 an active run the trigger started is not found
#   C3 a completed, blocked or cancelled run of the trigger counts as in flight
#   C4 another trigger's active run of the same workflow counts as this one's
#   C5 a run.yaml, run directory, .flow/runs or .flow that is a symbolic link
#      is read (it points outside the checkout)
#   C6 a run.yaml that cannot be read, is not YAML, or is not a mapping is
#      skipped, so the trigger's active run in it never counts as in flight
#      and skip_if_running starts a second run; or it stops the check with a
#      traceback instead of one flow-trigger-concurrency line
#   C7 a trigger id with '/' or '..' reads a file outside .flow/triggers
#   C8 a missing trigger reads as "nothing in flight" rather than an error
#   C9 the run schema refuses a run without metadata.trigger (every run not
#      started by a trigger), or accepts a trigger id the trigger schema
#      would refuse
#
# flow.triggers.defaultConcurrency (the policy for a trigger that sets none):
#   D1 a trigger with no concurrency.policy gets skip_if_running whatever the
#      setting says
#   D2 the setting overrides a trigger's own concurrency.policy
#   D3 the setting is read from the project file only, not the user's
#   D4 a value outside the three policies is used, or reads as the default,
#      instead of stopping the check
#
# flow.triggers.allowTriggerCreationFromTriggeredRun, and trigger-policy step
# 3 (bin/flow-trigger-recursion-check.sh, run from the skill's fence):
#   R1 with the setting false (the default) a trigger whose
#      triggered_runs_may_create_triggers is true passes
#   R2 with the setting true, that trigger is still refused
#   R3 the setting also lets triggered_runs_may_modify_triggers or
#      _enable_triggers through, which its name and description do not cover
#   R4 a setting value that is not a boolean reads as true
#   R5 a trigger that is a symbolic link is read
#   R6 the skill's fence does not find the script in an installed plugin

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

RUN_MD=commands/run.md
TRIGGER_MD=commands/trigger.md
RUN_SCHEMA="$E2E_PLUGIN_DIR/schemas/v1/run.schema.json"

# _trigger <id> [<concurrency policy>] — a trigger targeting address-pr; with no
# policy, the trigger has no concurrency block.
_trigger() {
  mkdir -p "$E2E_REPO/.flow/triggers"
  {
    printf 'apiVersion: flow.synapti.ai/v1\nkind: FlowTrigger\n'
    printf 'metadata:\n  id: %s\n  enabled: true\n  created_at: "2026-10-30T10:00:00Z"\n' "$1"
    printf 'trigger:\n  type: manual\n'
    printf 'target:\n  workflow: address-pr\n  command: "/flow:address 42"\n'
    printf 'policy:\n  forbidden_actions: [merge, release]\n'
    [ -n "${2:-}" ] && printf 'concurrency:\n  policy: %s\n' "$2"
  } > "$E2E_REPO/.flow/triggers/$1.trigger.yaml"
  printf 'trigger %s: concurrency.policy %s\n' "$1" "${2:-(none)}" | _e2e_art
}

# _run <run id> <workflow> <status> [<trigger id>] — a FlowRun; with no trigger
# id, the run has no metadata.trigger.
_run() {
  mkdir -p "$E2E_REPO/.flow/runs/$1"
  {
    printf 'apiVersion: flow.synapti.ai/v1\nkind: FlowRun\n'
    printf 'metadata:\n  id: %s\n  workflow: %s\n  created_at: "2026-10-30T10:00:00Z"\n' "$1" "$2"
    [ -n "${4:-}" ] && printf '  trigger: %s\n' "$4"
    printf 'context:\n  repo: octo/market\n  branch: main\n'
    printf 'state:\n  status: %s\n  completed_activities: []\n' "$3"
  } > "$E2E_REPO/.flow/runs/$1/run.yaml"
  printf 'run %s: workflow %s, status %s, trigger %s\n' "$1" "$2" "$3" "${4:-(none)}" | _e2e_art
}

_flow_test_begin "a run of the same workflow that no trigger started is not in flight (C1)"
e2e_new run-trigger-unrelated-run
e2e_describe "trigger pr-42-watch targets address-pr; an active address-pr run has no metadata.trigger"
e2e_repo main
_trigger pr-42-watch skip_if_running
_run 2026-10-30T100000Z-pr-42 address-pr active
e2e_run_block "$RUN_MD" RUN_CONCURRENCY_BLOCK 'trigger pr-42-watch'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "CONCURRENCY_POLICY=skip_if_running"
e2e_expect_no_out "IN_FLIGHT="
e2e_expect_clean_edges

_flow_test_begin "the trigger's own active run is in flight; its finished runs and another trigger's are not (C2, C3, C4)"
e2e_new run-trigger-own-runs
e2e_describe "one active run of pr-42-watch, a completed, a blocked and a cancelled one, and an active run of pr-43-watch"
e2e_repo main
_trigger pr-42-watch skip_if_running
_run 2026-10-30T100000Z-pr-42-a address-pr active pr-42-watch
_run 2026-10-30T090000Z-pr-42-b address-pr completed pr-42-watch
_run 2026-10-30T080000Z-pr-42-c address-pr blocked pr-42-watch
_run 2026-10-30T070000Z-pr-42-d address-pr cancelled pr-42-watch
_run 2026-10-30T100000Z-pr-43 address-pr active pr-43-watch
e2e_run_block "$RUN_MD" RUN_CONCURRENCY_BLOCK 'trigger pr-42-watch'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "IN_FLIGHT=2026-10-30T100000Z-pr-42-a"
e2e_expect_equal 1 "$(printf '%s\n' "$E2E_OUT" | grep -c '^IN_FLIGHT=')" "the number of runs in flight"
e2e_expect_clean_edges

e2e_new run-trigger-trigger-md
e2e_describe "the same runs, checked by /flow:trigger run pr-42-watch"
e2e_repo main
_trigger pr-42-watch skip_if_running
_run 2026-10-30T100000Z-pr-42-a address-pr active pr-42-watch
_run 2026-10-30T090000Z-pr-42-b address-pr active
_run 2026-10-30T100000Z-pr-43 address-pr active pr-43-watch
e2e_run_block "$TRIGGER_MD" TRIGGER_RUN_CONCURRENCY_BLOCK 'run pr-42-watch'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "CONCURRENCY_POLICY=skip_if_running"
e2e_expect_line "IN_FLIGHT=2026-10-30T100000Z-pr-42-a"
e2e_expect_equal 1 "$(printf '%s\n' "$E2E_OUT" | grep -c '^IN_FLIGHT=')" "the number of runs in flight"
e2e_expect_clean_edges

_flow_test_begin "a symbolic link anywhere on the way to run.yaml is not read (C5)"
e2e_new run-trigger-symlinks
e2e_describe "the trigger's active runs reached through a linked run.yaml and a linked run directory; one real run"
e2e_repo main
_trigger pr-42-watch skip_if_running
_run 2026-10-30T100000Z-real address-pr active pr-42-watch
mkdir -p "$E2E_DIR/outside/run-a" "$E2E_DIR/outside/run-b"
_run 2026-10-30T110000Z-tmp-a address-pr active pr-42-watch
mv "$E2E_REPO/.flow/runs/2026-10-30T110000Z-tmp-a/run.yaml" "$E2E_DIR/outside/run-a/run.yaml"
ln -s "$E2E_DIR/outside/run-a/run.yaml" "$E2E_REPO/.flow/runs/2026-10-30T110000Z-tmp-a/run.yaml"
_run 2026-10-30T120000Z-tmp-b address-pr active pr-42-watch
mv "$E2E_REPO/.flow/runs/2026-10-30T120000Z-tmp-b/run.yaml" "$E2E_DIR/outside/run-b/run.yaml"
rmdir "$E2E_REPO/.flow/runs/2026-10-30T120000Z-tmp-b"
ln -s "$E2E_DIR/outside/run-b" "$E2E_REPO/.flow/runs/2026-10-30T120000Z-tmp-b"
e2e_run_block "$RUN_MD" RUN_CONCURRENCY_BLOCK 'trigger pr-42-watch'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "IN_FLIGHT=2026-10-30T100000Z-real"
e2e_expect_equal 1 "$(printf '%s\n' "$E2E_OUT" | grep -c '^IN_FLIGHT=')" "the number of runs in flight"
e2e_expect_clean_edges

e2e_new run-trigger-runs-dir-link
e2e_describe ".flow/runs is a symbolic link to a directory holding the trigger's active run"
e2e_repo main
_trigger pr-42-watch skip_if_running
_run 2026-10-30T100000Z-pr-42 address-pr active pr-42-watch
mv "$E2E_REPO/.flow/runs" "$E2E_DIR/outside-runs"
ln -s "$E2E_DIR/outside-runs" "$E2E_REPO/.flow/runs"
e2e_run_block "$RUN_MD" RUN_CONCURRENCY_BLOCK 'trigger pr-42-watch'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_no_out "IN_FLIGHT="
e2e_expect_err "symbolic link"
e2e_expect_clean_edges

_flow_test_begin "a run.yaml that cannot be read, is not YAML, or is not a mapping stops the check (C6)"
for broken in not-yaml not-mapping unreadable; do
  e2e_new "run-trigger-run-yaml-$broken"
  e2e_describe "a run.yaml that is $broken beside the trigger's active run"
  e2e_repo main
  _trigger pr-42-watch skip_if_running
  _run 2026-10-30T100000Z-pr-42 address-pr active pr-42-watch
  BROKEN="$E2E_REPO/.flow/runs/2026-10-30T110000Z-$broken/run.yaml"
  case "$broken" in
    not-yaml) mkdir -p "${BROKEN%/*}"; printf 'metadata: [unclosed\n' > "$BROKEN" ;;
    not-mapping) mkdir -p "${BROKEN%/*}"; printf -- '- a\n- b\n' > "$BROKEN" ;;
    unreadable)
      if [ "$(id -u)" -eq 0 ]; then
        _flow_assert_pass "SKIP: run as root, which reads a file whatever its mode"
        continue
      fi
      _run 2026-10-30T110000Z-unreadable address-pr active pr-42-watch
      chmod 000 "$BROKEN" ;;
  esac
  e2e_run_block "$RUN_MD" RUN_CONCURRENCY_BLOCK 'trigger pr-42-watch'
  [ -f "$BROKEN" ] && chmod 644 "$BROKEN"
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_no_out "CONCURRENCY_POLICY="
  e2e_expect_no_out "IN_FLIGHT="
  e2e_expect_err "flow-trigger-concurrency: "
  e2e_expect_err "2026-10-30T110000Z-$broken"
  e2e_expect_err_lacks "Traceback"
  e2e_expect_clean_edges
done

_flow_test_begin "a trigger id that is not an id, or names no trigger, is an error (C7, C8)"
e2e_new run-trigger-bad-id
e2e_describe "/flow:run trigger ../outside; a trigger file exists at .flow/outside.trigger.yaml"
e2e_repo main
_trigger pr-42-watch skip_if_running
cp "$E2E_REPO/.flow/triggers/pr-42-watch.trigger.yaml" "$E2E_REPO/.flow/outside.trigger.yaml"
e2e_run_block "$RUN_MD" RUN_CONCURRENCY_BLOCK 'trigger ../outside'
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_no_out "CONCURRENCY_POLICY="
e2e_expect_err "not a trigger id"
e2e_expect_clean_edges

e2e_new run-trigger-missing
e2e_describe "/flow:run trigger pr-99-watch with no such trigger"
e2e_repo main
_trigger pr-42-watch skip_if_running
e2e_run_block "$RUN_MD" RUN_CONCURRENCY_BLOCK 'trigger pr-99-watch'
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_no_out "CONCURRENCY_POLICY="
e2e_expect_err "pr-99-watch"
e2e_expect_clean_edges

_flow_test_begin "the run schema: metadata.trigger is optional and holds a trigger id (C9)"
if python3 -c 'import jsonschema' >/dev/null 2>&1; then
  _schema_errors() {
    python3 - "$RUN_SCHEMA" "$1" <<'PY'
import json, sys, jsonschema
schema = json.load(open(sys.argv[1], encoding="utf-8"))
run = {"apiVersion": "flow.synapti.ai/v1", "kind": "FlowRun",
       "metadata": {"id": "2026-10-30T100000Z-pr-42", "workflow": "address-pr",
                    "created_at": "2026-10-30T10:00:00Z"},
       "context": {"repo": "octo/market", "branch": "main"},
       "state": {"status": "active"}}
if sys.argv[2] != "absent":
    run["metadata"]["trigger"] = None if sys.argv[2] == "null" else sys.argv[2]
v = jsonschema.validators.validator_for(schema)(schema)
print(len(list(v.iter_errors(run))))
PY
  }
  assert_equal 0 "$(_schema_errors absent)" "a run with no metadata.trigger validates"
  assert_equal 0 "$(_schema_errors null)" "a run with metadata.trigger null validates"
  assert_equal 0 "$(_schema_errors pr-42-watch)" "a run with metadata.trigger pr-42-watch validates"
  assert_equal 1 "$(_schema_errors ../outside)" "a run with metadata.trigger ../outside is refused"
  assert_equal 1 "$(_schema_errors Pr-42)" "a run with metadata.trigger Pr-42 is refused"
else
  _flow_assert_pass "SKIP: jsonschema not installed"
fi

# --- flow.triggers.defaultConcurrency ------------------------------------------

_settings() {
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' "$1" > "$E2E_REPO/.claude/settings.flow.json"
  printf 'project settings: %s\n' "$1" | _e2e_art
}

_flow_test_begin "a trigger with no concurrency.policy takes flow.triggers.defaultConcurrency (D1)"
e2e_new run-trigger-default-shipped
e2e_describe "the trigger sets no concurrency.policy; no setting, so the shipped default applies"
e2e_repo main
_trigger pr-42-watch
e2e_run_block "$RUN_MD" RUN_CONCURRENCY_BLOCK 'trigger pr-42-watch'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "CONCURRENCY_POLICY=skip_if_running"
e2e_expect_line "POLICY_SOURCE=setting"
e2e_expect_clean_edges

e2e_new run-trigger-default-project
e2e_describe "the trigger sets no concurrency.policy; the project sets flow.triggers.defaultConcurrency to queue"
e2e_repo main
_trigger pr-42-watch
_settings '{"flow":{"triggers":{"defaultConcurrency":"queue"}}}'
e2e_run_block "$RUN_MD" RUN_CONCURRENCY_BLOCK 'trigger pr-42-watch'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "CONCURRENCY_POLICY=queue"
e2e_expect_line "POLICY_SOURCE=setting"
e2e_expect_clean_edges

_flow_test_begin "the user's flow.triggers.defaultConcurrency applies too (D3)"
e2e_new run-trigger-default-user
e2e_describe "the trigger sets no concurrency.policy; the user settings set cancel_previous"
e2e_repo main
_trigger pr-42-watch
e2e_user_settings '{"flow":{"triggers":{"defaultConcurrency":"cancel_previous"}}}'
e2e_run_block "$RUN_MD" RUN_CONCURRENCY_BLOCK 'trigger pr-42-watch'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "CONCURRENCY_POLICY=cancel_previous"
e2e_expect_clean_edges

_flow_test_begin "the trigger's own concurrency.policy wins over the setting (D2)"
e2e_new run-trigger-default-overridden
e2e_describe "the trigger sets cancel_previous; the project sets defaultConcurrency to queue"
e2e_repo main
_trigger pr-42-watch cancel_previous
_settings '{"flow":{"triggers":{"defaultConcurrency":"queue"}}}'
e2e_run_block "$RUN_MD" RUN_CONCURRENCY_BLOCK 'trigger pr-42-watch'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "CONCURRENCY_POLICY=cancel_previous"
e2e_expect_line "POLICY_SOURCE=trigger"
e2e_expect_clean_edges

_flow_test_begin "a defaultConcurrency outside the three policies stops the check (D4)"
e2e_new run-trigger-default-bogus
e2e_describe "the trigger sets no concurrency.policy; the project sets defaultConcurrency to run_anyway"
e2e_repo main
_trigger pr-42-watch
_settings '{"flow":{"triggers":{"defaultConcurrency":"run_anyway"}}}'
e2e_run_block "$RUN_MD" RUN_CONCURRENCY_BLOCK 'trigger pr-42-watch'
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_no_out "CONCURRENCY_POLICY="
e2e_expect_err "flow.triggers.defaultConcurrency"
e2e_expect_clean_edges

# --- trigger-policy step 3: recursion_policy and its setting -------------------

RECURSION=bin/flow-trigger-recursion-check.sh

# _recursive_trigger <file> <create> <modify> <enable> — a trigger whose
# recursion_policy sets the three flags; "unset" leaves a flag out.
_recursive_trigger() {
  {
    printf 'apiVersion: flow.synapti.ai/v1\nkind: FlowTrigger\n'
    printf 'metadata:\n  id: rec\n  enabled: true\n  created_at: "2026-10-30T10:00:00Z"\n'
    printf 'trigger:\n  type: manual\ntarget:\n  command: "/flow:status"\n'
    printf 'policy:\n  forbidden_actions: [merge, release]\n'
    printf 'recursion_policy:\n'
    [ "$2" = unset ] || printf '  triggered_runs_may_create_triggers: %s\n' "$2"
    [ "$3" = unset ] || printf '  triggered_runs_may_modify_triggers: %s\n' "$3"
    [ "$4" = unset ] || printf '  triggered_runs_may_enable_triggers: %s\n' "$4"
  } > "$E2E_REPO/$1"
  printf 'trigger %s: create=%s modify=%s enable=%s\n' "$1" "$2" "$3" "$4" | _e2e_art
}

_flow_test_begin "with the setting false (the default) a trigger may not let its runs create triggers (R1)"
e2e_new recursion-create-default
e2e_describe "triggered_runs_may_create_triggers: true; no setting"
e2e_repo main
_recursive_trigger t.trigger.yaml true unset unset
e2e_run_bin "$RECURSION" t.trigger.yaml
e2e_expect_equal 2 "$E2E_RC" "the exit status"
e2e_expect_line "RECURSION_VIOLATION=triggered_runs_may_create_triggers"
e2e_expect_clean_edges

_flow_test_begin "with the setting true a trigger may let its runs create triggers (R2)"
e2e_new recursion-create-allowed
e2e_describe "triggered_runs_may_create_triggers: true; the project sets allowTriggerCreationFromTriggeredRun true"
e2e_repo main
_recursive_trigger t.trigger.yaml true false unset
_settings '{"flow":{"triggers":{"allowTriggerCreationFromTriggeredRun":true}}}'
e2e_run_bin "$RECURSION" t.trigger.yaml
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_no_out "RECURSION_VIOLATION="
e2e_expect_clean_edges

_flow_test_begin "the setting does not cover modify or enable (R3)"
e2e_new recursion-modify-enable
e2e_describe "all three flags true; the project sets allowTriggerCreationFromTriggeredRun true"
e2e_repo main
_recursive_trigger t.trigger.yaml true true true
_settings '{"flow":{"triggers":{"allowTriggerCreationFromTriggeredRun":true}}}'
e2e_run_bin "$RECURSION" t.trigger.yaml
e2e_expect_equal 2 "$E2E_RC" "the exit status"
e2e_expect_line "RECURSION_VIOLATION=triggered_runs_may_modify_triggers"
e2e_expect_line "RECURSION_VIOLATION=triggered_runs_may_enable_triggers"
e2e_expect_no_line "RECURSION_VIOLATION=triggered_runs_may_create_triggers"
e2e_expect_clean_edges

e2e_new recursion-none
e2e_describe "all three flags false or unset; no setting"
e2e_repo main
_recursive_trigger t.trigger.yaml false unset false
e2e_run_bin "$RECURSION" t.trigger.yaml
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_no_out "RECURSION_VIOLATION="
e2e_expect_clean_edges

_flow_test_begin "a setting that is not a boolean stops the check (R4)"
e2e_new recursion-setting-string
e2e_describe "triggered_runs_may_create_triggers: true; the project sets allowTriggerCreationFromTriggeredRun to the string yes"
e2e_repo main
_recursive_trigger t.trigger.yaml true unset unset
_settings '{"flow":{"triggers":{"allowTriggerCreationFromTriggeredRun":"yes"}}}'
e2e_run_bin "$RECURSION" t.trigger.yaml
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_no_out "RECURSION_VIOLATION="
e2e_expect_err "flow.triggers.allowTriggerCreationFromTriggeredRun"
e2e_expect_clean_edges

_flow_test_begin "a trigger that is a symbolic link is not read (R5)"
e2e_new recursion-symlink
e2e_describe "the trigger is a symbolic link to a trigger outside the repository"
e2e_repo main
_recursive_trigger t.trigger.yaml false false false
mv "$E2E_REPO/t.trigger.yaml" "$E2E_DIR/outside.trigger.yaml"
ln -s "$E2E_DIR/outside.trigger.yaml" "$E2E_REPO/t.trigger.yaml"
e2e_run_bin "$RECURSION" t.trigger.yaml
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_err "symbolic link"
e2e_expect_clean_edges

_flow_test_begin "trigger-policy step 3's fence runs the check from an installed plugin (R6)"
e2e_new recursion-skill-fence
e2e_describe "the step 3 fence of skills/trigger-policy/SKILL.md, run with CLAUDE_PLUGIN_ROOT set, on a trigger whose runs may create triggers"
e2e_repo main
_recursive_trigger t.trigger.yaml true unset unset
# The fence is indented under its list item: take the one that runs the
# recursion check out and dedent it.
awk '/^   ```bash$/{f=1; buf=""; next} f&&/^   ```$/{ if (buf ~ /flow-trigger-recursion-check/) { printf "%s", buf; exit } f=0; next } f{sub(/^   /,""); buf = buf $0 "\n"}' \
  "$E2E_PLUGIN_DIR/skills/trigger-policy/SKILL.md" > "$E2E_DIR/fence.sh.raw"
e2e_expect_equal yes "$(grep -q 'bin/flow-trigger-recursion-check.sh' "$E2E_DIR/fence.sh.raw" && echo yes || echo no)" "whether the step 3 fence was extracted"
_e2e_run_code "skills/trigger-policy/SKILL.md (step 3 fence)" "" "TRIGGER_YAML=t.trigger.yaml"
e2e_expect_equal 2 "$E2E_RC" "the exit status"
e2e_expect_line "RECURSION_VIOLATION=triggered_runs_may_create_triggers"
e2e_expect_clean_edges
