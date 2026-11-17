# shellcheck shell=bash
# AC9: with a stale platform probe record, `next` still syncs and moves jobs
# but starts no worker, counts no attempt and prints the re-run command; a
# failed environment re-run stops every launch (plan 1a T11, design phasing
# L27-L32). `next` runs through the test entry point (E) with the ordinary
# seam fixture; `launch` runs through the shipped wrapper.
#
# Ways it can be wrong, written down before the checks:
#   PB1 a partially re-run platform (the group's version current, one entry
#       still stamped with the old one) lets a worker launch, or counts an
#       attempt, or stops the sync and the engine directives too (RM6)
#   PB2 `launch` ignores staleness
#   PB3 a failed environment re-run still launches (a worker or an engine
#       directive), or a passing one runs again on every pass
#   PB4 a signer that needs a person passes the re-run
#   PB5 a fresh record does not launch
#
# PB_ONLY=<id> (PB1 ... PB5) runs only that scenario.

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}
# shellcheck source=lib/factory-e2e.sh
source "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh"

pb_run() { [ -z "${PB_ONLY:-}" ] || [ "$PB_ONLY" = "$1" ]; }

PB_SUCCESS='{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.05}'
PB_D7=issue-7-j1-build-1
# The record edits that make the platform group current (2.1.326) but leave
# P5 and its parts stamped with 2.1.325: a partial platform re-run.
PB_PARTIAL='for pid, e in d["probes"].items():
    if e.get("group") == "platform" and "keyed_on" in e:
        v = "2.1.325 (Claude Code)" if pid == "P5" else "2.1.326 (Claude Code)"
        e["keyed_on"]["claude_version"] = v
        for part in (e.get("parts") or {}).values():
            part["keyed_on"]["claude_version"] = v
d["groups"]["platform"]["keyed_on"]["claude_version"] = "2.1.326 (Claude Code)"'

pb_jq() { jq -r "$2" "$1" 2>/dev/null; }
pb_rows() { jq -r 'select(.type == "transition") | .row' "$PB_F/jobs/issue-$1/events.jsonl" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
pb_launches() { if [ -f "$E2E_BIN/claude-launches.log" ]; then wc -l < "$E2E_BIN/claude-launches.log" | tr -d ' '; else echo 0; fi; }
pb_leases() { find "$PB_F/jobs" -name '*.lease.json' 2>/dev/null | wc -l | tr -d ' '; }
pb_next() { fe_e "${1:-ordinary.json}" next --executor headless; }

# pb_seed <record edits> — the main checkout, the record, the factory on,
# job 7 in build with its clone, job 8 in gate with PR 12 at head h8, a plugin
# copy with build.prompt.md, and a fixture: ordinary plus the gate body.
pb_seed() {
  e2e_repo main
  fe_record "${1:-}"
  fe_enable
  fe_job 7 build
  fe_job_clone 7
  fe_job 8 gate "d['pr'] = 12; d['head_sha'] = '8' * 40"
  PB_F=$(fe_factory_dir)
  e2e_plugin_copy templates/factory/build.prompt.md 'RUN: true'
  fe_gh api_repos_flow-e2e_scratch_pulls_12 "{\"number\":12,\"state\":\"open\",\"merged\":false,\"merged_at\":null,\"head\":{\"sha\":\"$(printf '8%.0s' $(seq 40))\"}}"
  jq '.bodies = {"directive:gate": "succeeded"}' "$FE_FIXTURES/seam/ordinary.json" > "$E2E_DIR/pb.json"
}

# ---------------------------------------------------------------- PB1
if pb_run PB1; then
_flow_test_begin "probes: a partially re-run platform syncs and moves jobs, starts no worker and counts no attempt (PB1, AC9, RM6)"
fe_new pb1-partial-platform
# Source: AC9; journal RM6; design phasing L27; T:66c (launch_due, probes_stale
# true: stay, do not launch, paused_reason probes_stale); T:66 (gate's engine
# directive does not read probes_stale); T:24 (stage_succeeded in gate,
# gate_pass false and round_limit_reached false under the ordinary fixture,
# precedence 53 -> rework; 25, 25e and 25f need a true fact).
e2e_describe "claude --version 2.1.326; the platform group is 2.1.326 but P5 is 2.1.325; job 7 in build, job 8 in gate with PR 12; concurrency 2; next twice"
pb_seed "$PB_PARTIAL"
# Two slots: with one, job 8's gate directive takes it in pass 1 and keeps it
# in rework, and job 7's pass 2 is row 66w (precedence 25), not 66c (30).
e2e_user_settings "$(jq -c '.flow.factory.concurrency = 2' "$E2E_HOME/.claude/settings.flow.json")"
fe_worker_says "worker-result=$PB_SUCCESS" 'claude-version=2.1.326 (Claude Code)'
pb_next "$E2E_DIR/pb.json"
e2e_expect_equal 0 "$E2E_RC" "pass 1 exit status ($E2E_ERR)"
e2e_expect_line '{"status":"PAUSED probes_stale=platform recorded=2.1.325 (Claude Code) current=2.1.326 (Claude Code) next: flow-factory.sh probe --platform"}'
pb_next "$E2E_DIR/pb.json"
e2e_expect_equal 0 "$E2E_RC" "pass 2 exit status ($E2E_ERR)"
e2e_expect_line '{"status":"PAUSED probes_stale=platform recorded=2.1.325 (Claude Code) current=2.1.326 (Claude Code) next: flow-factory.sh probe --platform"}'
e2e_expect_equal 1 "$(grep -cxF 'api repos/flow-e2e/scratch/pulls/12' "$E2E_BIN/fe-gh-calls.log")" "the sync's PR call"
e2e_expect_equal "66 24" "$(pb_rows 8)" "job 8 rows"
e2e_expect_equal rework "$(pb_jq "$PB_F/jobs/issue-8/job.json" .state)" "job 8 state"
e2e_expect_equal "66c 66c" "$(pb_rows 7)" "job 7 rows"
e2e_expect_equal "build probes_stale 0 null" "$(pb_jq "$PB_F/jobs/issue-7/job.json" '"\(.state) \(.paused_reason) \(.attempt) \(.directive)"')" "job 7 state, paused_reason, attempt, directive"
e2e_expect_equal 0 "$(pb_leases)" "lease files"
e2e_expect_equal 0 "$(pb_launches)" "claude launches"
fe_art_state 7
fe_art_state 8
fi

# ---------------------------------------------------------------- PB2
if pb_run PB2; then
_flow_test_begin "probes: launch of a worker directive refuses while the platform is stale (PB2)"
fe_new pb2-launch-stale
# Source: execution_model L65; plan 2.6 (PROBES_STALE=platform, exit 5); T7 not_started_reason.
e2e_describe "the PB1 record; job 7's current directive is a fresh worker directive; flow-factory.sh launch"
e2e_repo main
fe_record "$PB_PARTIAL"
fe_enable
fe_job 7 build "d['directive'] = '$PB_D7'; d['stage_launches'] = {'build': 1}"
fe_job_clone 7
fe_directive "$PB_D7"
PB_F=$(fe_factory_dir)
e2e_plugin_copy templates/factory/build.prompt.md 'RUN: true'
fe_worker_says "worker-result=$PB_SUCCESS" 'claude-version=2.1.326 (Claude Code)'
e2e_run_bin bin/flow-factory.sh launch "$PB_D7"
e2e_expect_equal 5 "$E2E_RC" "exit status"
e2e_expect_line "PROBES_STALE=platform"
e2e_expect_equal probes_stale "$(pb_jq "$PB_F/jobs/issue-7/directives/$PB_D7.json" .not_started_reason)" "not_started_reason"
e2e_expect_equal 0 "$(pb_launches)" "claude launches"
fi

# ---------------------------------------------------------------- PB3
if pb_run PB3; then
_flow_test_begin "probes: a changed gh is re-run once and then launches; a changed interpreter stops every launch (PB3)"
fe_new pb3a-gh-changed
# Source: design phasing L29; e2e_tests L45; plan 2.12 environment_recheck
# (a new gh version is recorded under probes.lock); T:66b.
e2e_describe "gh reports 2.102.0, the record 2.101.0; next, then next again within syncIntervalSeconds"
pb_seed
fe_gh --version 'gh version 2.102.0 (2026-10-01)'
fe_worker_says "worker-result=$PB_SUCCESS"
pb_next
e2e_expect_equal 0 "$E2E_RC" "pass 1 exit status ($E2E_ERR)"
PB_AT=$(pb_jq "$PB_F/state.json" .env_recheck_at)
e2e_expect_equal yes "$([ "$PB_AT" != null ] && [ -n "$PB_AT" ] && echo yes || echo no)" "env_recheck_at written by pass 1"
e2e_expect_equal "gh version 2.102.0 (2026-10-01)" "$(pb_jq "$PB_F/probes.json" .groups.environment.keyed_on.gh_version)" "recorded gh version"
e2e_expect_equal null "$(pb_jq "$PB_F/state.json" .env_failed_check)" "env_failed_check"
e2e_expect_equal 66b "$(pb_rows 7)" "job 7 rows (a launch)"
fe_wait_for 45 "[ -f '$PB_F/jobs/issue-7/results/$PB_D7.json' ]"
sleep 1.2
pb_next
fe_mask_found "$PB_AT"
e2e_expect_equal "$PB_AT" "$(pb_jq "$PB_F/state.json" .env_recheck_at)" "env_recheck_at after pass 2 (no second re-run)"

fe_new pb3b-interpreter-changed
# Source: design phasing L29 ("while it fails, the engine raises no launch_due
# event for any job", T:events.launch_due); plan 2.6 status line.
e2e_describe "the record's interpreter version differs from the interpreter's own; job 7 in build and job 8 in gate are both due"
pb_seed 'd["groups"]["environment"]["keyed_on"]["interpreter_version"] = "3.0.0"'
fe_worker_says "worker-result=$PB_SUCCESS"
pb_next "$E2E_DIR/pb.json"
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_line '{"status":"PAUSED probes_failed=environment check=interpreter next: flow-factory.sh probe --environment (from a terminal when check=signing)"}'
e2e_expect_equal "" "$(pb_rows 7)" "job 7 rows"
e2e_expect_equal "" "$(pb_rows 8)" "job 8 rows (no row 66)"
e2e_expect_equal 0 "$(jq -c 'select(.event == "launch_due")' "$PB_F"/jobs/issue-*/events.jsonl 2>/dev/null | wc -l | tr -d ' ')" "launch_due lines of any kind"
e2e_expect_equal 0 "$(pb_launches)" "claude launches"
fi

# ---------------------------------------------------------------- PB4
if pb_run PB4; then
_flow_test_begin "probes: a signer that needs a person pauses next with check=signing; without the wait it launches (PB4)"
fe_new pb4-signer-hangs
# Source: e2e_tests L49; design phasing L29; plan 2.6 status line.
e2e_describe "commit signing on with a signer that waits 60 s, SSH_AUTH_SOCK unset, next run with no terminal and no ancestor"
pb_seed
fe_worker_says "worker-result=$PB_SUCCESS"
cp "$FE_FIXTURES/bin/signer" "$E2E_BIN/"
: > "$E2E_BIN/signer-hangs"
printf '[commit]\n\tgpgsign = true\n[user]\n\tsigningkey = 0123456789ABCDEF\n[gpg]\n\tprogram = %s\n' "$E2E_BIN/signer" > "$E2E_HOME/.gitconfig"
fe_detached env -u SSH_AUTH_SOCK "$(fe_python)" -E "$FE_FIXTURES/engine_under_test.py" --plugin "$E2E_ACTIVE_PLUGIN" \
  --fixtures "$FE_FIXTURES/seam/ordinary.json" next --executor headless
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_line '{"status":"PAUSED probes_failed=environment check=signing next: flow-factory.sh probe --environment (from a terminal when check=signing)"}'
e2e_expect_equal "" "$(pb_rows 7)" "job 7 rows"
e2e_expect_equal 0 "$(pb_launches)" "claude launches"

fe_new pb4-signer-signs
# Source: as pb4-signer-hangs; the signer answers at once, so the re-run passes.
e2e_describe "the same, but the signer answers at once"
pb_seed
fe_worker_says "worker-result=$PB_SUCCESS"
cp "$FE_FIXTURES/bin/signer" "$E2E_BIN/"
printf '[commit]\n\tgpgsign = true\n[user]\n\tsigningkey = 0123456789ABCDEF\n[gpg]\n\tprogram = %s\n' "$E2E_BIN/signer" > "$E2E_HOME/.gitconfig"
fe_detached env -u SSH_AUTH_SOCK "$(fe_python)" -E "$FE_FIXTURES/engine_under_test.py" --plugin "$E2E_ACTIVE_PLUGIN" \
  --fixtures "$FE_FIXTURES/seam/ordinary.json" next --executor headless
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 66b "$(pb_rows 7)" "job 7 rows (a launch)"
fe_wait_for 45 "[ -f '$PB_F/jobs/issue-7/results/$PB_D7.json' ]"
fi

# ---------------------------------------------------------------- PB5
if pb_run PB5; then
_flow_test_begin "probes: with every probe current, job 7 launches (PB5, control)"
fe_new pb5-current
# Source: design phasing L27; T:66b.
e2e_describe "the record matches every installed tool"
pb_seed
fe_worker_says "worker-result=$PB_SUCCESS"
pb_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 66b "$(pb_rows 7)" "job 7 rows"
fe_wait_for 45 "[ -f '$PB_F/jobs/issue-7/results/$PB_D7.json' ]"
e2e_expect_equal 1 "$(pb_launches)" "claude launches"
e2e_expect_equal 0 "$(printf '%s\n' "$E2E_OUT" | grep -c 'probes_stale=platform\|probes_failed=')" "probe PAUSED lines"
fi
