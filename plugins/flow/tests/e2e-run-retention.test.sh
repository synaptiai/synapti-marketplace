# shellcheck shell=bash
# End-to-end: the SessionEnd hook (hooks/scripts/session-end-state.sh) removes
# FlowRun records under .flow/runs/ that ended more than
# flow.runtime.runRetentionDays days ago.
#
# A run is removed only when its run.yaml says it ended (state.status
# completed or cancelled) and run.yaml was last written more than that many
# days ago. Each scenario writes runs into a scratch repository, ages them by
# setting run.yaml's modification time, and runs the hook.
#
# Ways it can be wrong, written down before the scenarios:
#   K1 an active or blocked run is removed, losing work /flow:resume needs
#   K2 an ended run newer than the limit is removed
#   K3 the setting is ignored, so a project's shorter or longer limit has no
#      effect (or the default is not 30)
#   K4 a value that is not a whole number of at least 1 is used as given (0
#      removes everything ended; text crashes the hook)
#   K5 a symlinked .flow, .flow/runs or run directory is followed, so a
#      directory outside the repository is deleted
#   K6 a run.yaml that cannot be read or parsed is treated as ended
#   K7 runs are removed while flow.runtime.enabled is false, when the hook
#      otherwise does nothing with runs

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  _flow_test_begin "e2e-run-retention prerequisites"
  _flow_assert_pass "SKIP: python3 with PyYAML is required — this run proves nothing"
  return 0 2>/dev/null; exit 0
fi

HOOK=hooks/scripts/session-end-state.sh
PAYLOAD='{"session_id":"e2e-retention"}'

# _run <id> <status> <age in days> — a run directory with a run.yaml whose
# modification time is that many days in the past.
_run() {
  local d="$E2E_REPO/.flow/runs/$1"
  mkdir -p "$d"
  printf 'apiVersion: flow.synapti.ai/v1\nkind: FlowRun\nmetadata:\n  id: %s\n  workflow: start-issue\nstate:\n  status: %s\n' "$1" "$2" > "$d/run.yaml"
  printf '{}\n' > "$d/events.jsonl"
  python3 -c 'import os, sys, time; t = time.time() - float(sys.argv[2]) * 86400; os.utime(sys.argv[1], (t, t))' "$d/run.yaml" "$3"
}
_exists() { [ -e "$E2E_REPO/.flow/runs/$1" ] && echo kept || echo removed; }
_settings() { mkdir -p "$E2E_REPO/.claude"; printf '%s\n' "$1" > "$E2E_REPO/.claude/settings.flow.json"; }

_flow_test_begin "SessionEnd: ended runs past the default 30 days are removed; others stay (K1, K2, K3)"
e2e_new retention-default
e2e_describe "runs: completed 40 days, cancelled 31 days, completed 10 days, active 90 days, blocked 90 days; no setting (default 30)"
e2e_repo feature/issue-7-retention
_run 2026-01-01T000000Z-issue-1 completed 40
_run 2026-01-02T000000Z-issue-2 cancelled 31
_run 2026-01-03T000000Z-issue-3 completed 10
_run 2026-01-04T000000Z-issue-4 active 90
_run 2026-01-05T000000Z-issue-5 blocked 90
e2e_run_hook "$HOOK" "$PAYLOAD"
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_equal removed "$(_exists 2026-01-01T000000Z-issue-1)" "the completed run 40 days old"
e2e_expect_equal removed "$(_exists 2026-01-02T000000Z-issue-2)" "the cancelled run 31 days old"
e2e_expect_equal kept "$(_exists 2026-01-03T000000Z-issue-3)" "the completed run 10 days old"
e2e_expect_equal kept "$(_exists 2026-01-04T000000Z-issue-4)" "the active run 90 days old"
e2e_expect_equal kept "$(_exists 2026-01-05T000000Z-issue-5)" "the blocked run 90 days old"

_flow_test_begin "SessionEnd: the project's runRetentionDays sets the limit (K3)"
e2e_new retention-setting
e2e_describe "flow.runtime.runRetentionDays 5; completed runs 6 and 4 days old"
e2e_repo feature/issue-7-retention
_settings '{"flow":{"runtime":{"runRetentionDays":5}}}'
_run 2026-02-01T000000Z-issue-1 completed 6
_run 2026-02-02T000000Z-issue-2 completed 4
e2e_run_hook "$HOOK" "$PAYLOAD"
e2e_expect_equal removed "$(_exists 2026-02-01T000000Z-issue-1)" "the completed run 6 days old"
e2e_expect_equal kept "$(_exists 2026-02-02T000000Z-issue-2)" "the completed run 4 days old"

_flow_test_begin "SessionEnd: a runRetentionDays that is not a whole number of at least 1 means 30 (K4)"
for bad in 0 -3 '"x"' 2.5; do
  e2e_new "retention-bad-$(printf '%s' "$bad" | tr -c 'a-z0-9' '_')"
  e2e_describe "flow.runtime.runRetentionDays $bad; completed runs 31 and 20 days old"
  e2e_repo feature/issue-7-retention
  _settings "{\"flow\":{\"runtime\":{\"runRetentionDays\":$bad}}}"
  _run 2026-03-01T000000Z-issue-1 completed 31
  _run 2026-03-02T000000Z-issue-2 completed 20
  e2e_run_hook "$HOOK" "$PAYLOAD"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal removed "$(_exists 2026-03-01T000000Z-issue-1)" "the completed run 31 days old"
  e2e_expect_equal kept "$(_exists 2026-03-02T000000Z-issue-2)" "the completed run 20 days old"
done

_flow_test_begin "SessionEnd: a symlinked run directory or .flow/runs is never followed (K5)"
e2e_new retention-run-dir-link
e2e_describe "an old completed run whose directory is a symlink to a directory outside the repository"
e2e_repo feature/issue-7-retention
_run 2026-04-01T000000Z-issue-1 completed 60
mv "$E2E_REPO/.flow/runs/2026-04-01T000000Z-issue-1" "$E2E_DIR/outside-run"
ln -s "$E2E_DIR/outside-run" "$E2E_REPO/.flow/runs/2026-04-01T000000Z-issue-1"
e2e_run_hook "$HOOK" "$PAYLOAD"
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_equal yes "$([ -f "$E2E_DIR/outside-run/run.yaml" ] && echo yes || echo no)" "the directory outside the repository still holds run.yaml"

e2e_new retention-runs-link
e2e_describe "an old completed run under a .flow/runs that is a symlink to a directory outside the repository"
e2e_repo feature/issue-7-retention
_run 2026-04-02T000000Z-issue-1 completed 60
mv "$E2E_REPO/.flow/runs" "$E2E_DIR/outside-runs"
ln -s "$E2E_DIR/outside-runs" "$E2E_REPO/.flow/runs"
e2e_run_hook "$HOOK" "$PAYLOAD"
e2e_expect_equal yes "$([ -f "$E2E_DIR/outside-runs/2026-04-02T000000Z-issue-1/run.yaml" ] && echo yes || echo no)" "the run outside the repository is still there"

_flow_test_begin "SessionEnd: a run.yaml that cannot be parsed is kept (K6)"
e2e_new retention-unparsable
e2e_describe "an old run whose run.yaml is not YAML"
e2e_repo feature/issue-7-retention
_run 2026-05-01T000000Z-issue-1 completed 60
printf 'state: [unclosed\n' > "$E2E_REPO/.flow/runs/2026-05-01T000000Z-issue-1/run.yaml"
python3 -c 'import os, time; t = time.time() - 60 * 86400; os.utime("'"$E2E_REPO"'/.flow/runs/2026-05-01T000000Z-issue-1/run.yaml", (t, t))'
e2e_run_hook "$HOOK" "$PAYLOAD"
e2e_expect_equal kept "$(_exists 2026-05-01T000000Z-issue-1)" "the run with the unparsable run.yaml"

_flow_test_begin "SessionEnd: with flow.runtime.enabled false nothing is removed (K7)"
e2e_new retention-runtime-off
e2e_describe "flow.runtime.enabled false; a completed run 60 days old"
e2e_repo feature/issue-7-retention
_settings '{"flow":{"runtime":{"enabled":false}}}'
_run 2026-06-01T000000Z-issue-1 completed 60
e2e_run_hook "$HOOK" "$PAYLOAD"
e2e_expect_equal kept "$(_exists 2026-06-01T000000Z-issue-1)" "the completed run 60 days old"
