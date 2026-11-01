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
#   C6 a run.yaml that is not YAML, or not a mapping, stops the check with a
#      traceback instead of being skipped with a warning
#   C7 a trigger id with '/' or '..' reads a file outside .flow/triggers
#   C8 a missing trigger reads as "nothing in flight" rather than an error
#   C9 the run schema refuses a run without metadata.trigger (every run not
#      started by a trigger), or accepts a trigger id the trigger schema
#      would refuse

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

_flow_test_begin "a run.yaml that is not YAML, or not a mapping, is skipped with a warning (C6)"
e2e_new run-trigger-bad-run-yaml
e2e_describe "two broken run.yaml files beside the trigger's active run"
e2e_repo main
_trigger pr-42-watch skip_if_running
_run 2026-10-30T100000Z-pr-42 address-pr active pr-42-watch
mkdir -p "$E2E_REPO/.flow/runs/2026-10-30T110000Z-bad" "$E2E_REPO/.flow/runs/2026-10-30T120000Z-list"
printf 'metadata: [unclosed\n' > "$E2E_REPO/.flow/runs/2026-10-30T110000Z-bad/run.yaml"
printf -- '- a\n- b\n' > "$E2E_REPO/.flow/runs/2026-10-30T120000Z-list/run.yaml"
e2e_run_block "$RUN_MD" RUN_CONCURRENCY_BLOCK 'trigger pr-42-watch'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "IN_FLIGHT=2026-10-30T100000Z-pr-42"
e2e_expect_err "2026-10-30T110000Z-bad"
e2e_expect_err "2026-10-30T120000Z-list"
e2e_expect_err_lacks "Traceback"
e2e_expect_clean_edges

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
