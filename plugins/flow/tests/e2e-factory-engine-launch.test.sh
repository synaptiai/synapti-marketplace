# shellcheck shell=bash
# The factory launcher (bin/_flow_factory_launch.py, plan 1a T7): `launch`
# claims a worker directive and starts a detached launcher, which builds the
# worker's command and environment, keeps the lease and heartbeat, stops the
# worker at the stage timeout, charges the run and stores its result in its
# own process. Every scenario runs `flow-factory.sh launch` through the
# shipped wrapper, with the worker claude stand-in (fixtures/factory/worker)
# in place of claude, and waits for the launcher to end.
#
# Ways it can be wrong, written down before the checks:
#   LA1  the worker environment holds values derived from the issue number,
#        not job.json (AC6)
#   LA2  a never-passed variable leaks, or a kept one is dropped
#   LA3  the keep list is narrower than flow-eval-run.sh's
#   LA4  PATH has flow shims, or no interpreter directory first
#   LA5  --model is missing or a constant, or --max-turns is passed (G2, A.6)
#   LA6  a fresh launch passes --resume, or a resume passes --session-id or a
#        slash-command prompt (RM3)
#   LA7  a first fresh launch keeps a dirty tree, or the snapshot loses the
#        untracked file
#   LA8  a resumed run is charged the session total (RM4)
#   LA9  the overshoot is not held back (old rule or a halves cap), or a
#        killed run is charged only its limit (G3, A.10)
#   LA10 a usage limit counts an attempt, or another API error does not (R11)
#   LA11 the kill comes before 30 s, or `launch` blocks (R9)
#   LA12 a directive launches twice
#   LA13 a worker launches while the platform probes are stale (RM6)
#   LA14 a missing template launches anyway
#   LA15 an external `report` is accepted
#   LA16 the report needs a subprocess, or is lost when the interpreter is gone
#   LA17 the lease or marker is wrong, or the heartbeat does not advance
#   LA18 a changed in/ file survives to the next launch (scope 4)
#   LA19 a plugin inside the repository is used
#   LA20 the allowance is a fixed $0.50, not twice the dearest turn (A.7)
#   LA21 the dearest turn is the last turn, the sum, or the charged cost
#   LA22 a malformed or unknown directive id, a judge of a stage other than
#        intake, an engine directive, a missing claude, or a missing or
#        symlinked io directory launches anyway, or claims the directive; an
#        intake judge directive (session_id null) is refused (plan B11)
#   LA23 a launcher that fails leaves no result, so the engine waits on the
#        directive for ever, or a run that started is not charged
#   LA25 a launcher report retried after a failure part way (store_pending
#        failing after job.json was charged) charges again, or drops the
#        stage event, so the stage runs again
#   LA24 a launch refused after its directive was read (claude missing, the
#        io directory or clone gone) leaves no event naming why, so the job
#        later parks as attempts_exhausted with no reason anywhere
#
# Amounts are compared in whole cents (or tenths of a cent) through jq, so
# 1.2 and 1.20 compare equal and a float's last digit does not matter.
#
# LA_ONLY=<id> (LA1 ... LA25, or e.g. LA9vi) runs only that scenario.

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}
# shellcheck source=lib/factory-e2e.sh
source "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh"

la_run() { [ -z "${LA_ONLY:-}" ] || [ "$LA_ONLY" = "$1" ]; }

LA_ID=issue-7-j1-build-1

# la_plugin [<build template text>] — run this scenario against a plugin copy
# holding templates/factory/build.prompt.md with that text (none when the
# argument is absent).
la_plugin() {
  if [ "$#" -gt 0 ]; then
    e2e_plugin_copy templates/factory/build.prompt.md "$1"
  else
    E2E_ACTIVE_PLUGIN="$E2E_DIR/plugin"
    e2e_copy_plugin "$E2E_PLUGIN_DIR" "$E2E_ACTIVE_PLUGIN" || _flow_assert_fail "$E2E_NAME: cannot copy the plugin"
    printf 'plugin for this scenario: a copy without templates/factory/build.prompt.md\n' | _e2e_art
  fi
}

# la_settings <jq expression> — apply it to the scratch user settings.
la_settings() {
  local f="$E2E_HOME/.claude/settings.flow.json" cur='{}'
  [ -f "$f" ] && cur=$(cat "$f")
  e2e_user_settings "$(printf '%s' "$cur" | jq -c "$1")"
}

# la_seed [job edits] [directive edits] — the scenario's main checkout, probe
# record (LA_RECORD_EDITS), enabled factory, job issue-7-j1 in build whose
# current directive is LA_ID, its clone, and the directive.
la_seed() {
  e2e_repo main
  fe_record "${LA_RECORD_EDITS:-}"
  fe_enable
  fe_job 7 build "d['directive'] = '$LA_ID'
${1:-}"
  fe_job_clone 7
  fe_directive "$LA_ID" "${2:-}"
  LA_F=$(fe_factory_dir)
  LA_J="$LA_F/jobs/issue-7"
}

# la_next_directive <id> [edits] — another directive of the job, made current.
la_next_directive() {
  fe_directive "$1" "${2:-}"
  jq --arg d "$1" '.directive = $d' "$LA_J/job.json" > "$LA_J/job.json.t" && mv "$LA_J/job.json.t" "$LA_J/job.json"
}

la_launch() { e2e_run_bin bin/flow-factory.sh launch "${1:-$LA_ID}"; }

# la_wait [id] [seconds] — wait for the result (or a shell pending-report
# line), then for the launcher named in the lease to be gone.
la_wait() {
  local id="${1:-$LA_ID}" lp
  fe_wait_for "${2:-60}" "[ -f '$LA_J/results/$id.json' ] || [ -s '$LA_J/directives/$id.pending-report.jsonl' ]" || return 1
  lp=$(jq -r '.launcher_pid // empty' "$LA_J/directives/$id.lease.json" 2>/dev/null)
  [ -n "$lp" ] && fe_wait_for 10 "! kill -0 $lp 2>/dev/null"
  fe_art_state 7
}

# la_arg_after <n> <flag> — the argument after <flag> in claude-argv-<n>.txt.
la_arg_after() { awk -v f="$2" 'p { print; exit } $0 == f { p = 1 }' "$E2E_BIN/claude-argv-$1.txt" 2>/dev/null; }
la_has_arg() { grep -qxF -- "$2" "$E2E_BIN/claude-argv-$1.txt" 2>/dev/null && echo yes || echo no; }

# la_jq <file> <expression> — one value of a JSON file, as jq prints it.
la_jq() { jq -r "$2" "$1" 2>/dev/null; }
la_cents() { jq -r "($2) * 100 | round" "$1" 2>/dev/null; }

la_env_has() { grep -q "^$2=" "$E2E_BIN/claude-env-$1.txt" 2>/dev/null && echo yes || echo no; }
la_env_value() { sed -n "s/^$2=//p" "$E2E_BIN/claude-env-$1.txt" 2>/dev/null | head -n 1; }

# la_block <n> — the n-th start's output in claude-script.out, without its
# `--- start` line.
la_block() { awk -v n="$1" '$0 == "--- start" { k++; next } k == n' "$E2E_BIN/claude-script.out" 2>/dev/null; }

la_launches() { if [ -f "$E2E_BIN/claude-launches.log" ]; then wc -l < "$E2E_BIN/claude-launches.log" | tr -d ' '; else echo 0; fi; }

LA_SUCCESS='{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.05}'

# ---------------------------------------------------------------- LA1, LA12
if la_run LA1; then
fe_new la1-job-values
e2e_describe "the worker gets the four job values from job.json, which differ from what the issue number gives; a second launch of the same directive is refused"
la_seed
la_plugin 'RUN: true'
fe_worker_says "worker-result=$LA_SUCCESS"
la_launch
e2e_expect_line "LAUNCHED directive=$LA_ID"
e2e_expect_equal 0 "$E2E_RC" "launch exit status"
la_wait
e2e_expect_equal issue-7-j1 "$(la_env_value 1 FLOW_FACTORY_JOB_KEY)" "FLOW_FACTORY_JOB_KEY"
e2e_expect_equal 7 "$(la_env_value 1 FLOW_FACTORY_ISSUE)" "FLOW_FACTORY_ISSUE"
e2e_expect_equal feature/issue-7-x-2 "$(la_env_value 1 FLOW_FACTORY_BRANCH)" "FLOW_FACTORY_BRANCH"
e2e_expect_equal issue-7-f2 "$(la_env_value 1 FLOW_FACTORY_GOAL_ID)" "FLOW_FACTORY_GOAL_ID"
LA_IO=$(la_jq "$LA_J/job.json" .io_dir)
e2e_expect_equal "FLOW_FACTORY_JOB_KEY=issue-7-j1;FLOW_FACTORY_ISSUE=7;FLOW_FACTORY_BRANCH=feature/issue-7-x-2;FLOW_FACTORY_GOAL_ID=issue-7-f2;" \
  "$(tr '\n' ';' < "$LA_IO/in/job.env")" "in/job.env"
e2e_expect_equal "$LA_IO" "$(la_env_value 1 FLOW_FACTORY_IO)" "FLOW_FACTORY_IO"
e2e_expect_equal "$LA_ID" "$(la_env_value 1 FLOW_FACTORY_DIRECTIVE)" "FLOW_FACTORY_DIRECTIVE"
e2e_expect_equal issue-7-j1 "$(la_env_value 1 FLOW_FACTORY_JOB)" "FLOW_FACTORY_JOB"
e2e_expect_equal "$(dirname "$LA_IO")/state" "$(la_env_value 1 FLOW_STATE_DIR)" "FLOW_STATE_DIR"
e2e_expect_equal flow-e2e/scratch "$(la_env_value 1 GH_REPO)" "GH_REPO"
e2e_expect_equal 1 "$(la_env_value 1 GH_PROMPT_DISABLED)" "GH_PROMPT_DISABLED"
e2e_expect_equal "$(cd "$E2E_ACTIVE_PLUGIN" && pwd -P)" "$(la_env_value 1 CLAUDE_PLUGIN_ROOT)" "CLAUDE_PLUGIN_ROOT"
e2e_expect_equal completed "$(la_jq "$LA_J/results/$LA_ID.json" .outcome)" "outcome"
# LA12: the directive is started; a second launch is refused and runs nothing.
la_launch
e2e_expect_line "FACTORY_REFUSED=directive_started directive=$LA_ID"
e2e_expect_equal 5 "$E2E_RC" "second launch exit status"
e2e_expect_equal 1 "$(la_launches)" "claude launches"
fi

# ---------------------------------------------------------------- LA2
if la_run LA2; then
fe_new la2-never-passed
e2e_describe "the person's environment holds every never-passed name, an unlisted name, two kept provider names and an extraEnv name"
la_seed
la_plugin 'RUN: true'
# extraEnv also names GH_TOKEN: a never-passed name stays out even then.
la_settings '.flow.factory.worker.extraEnv = ["MY_VAR", "GH_TOKEN"]'
fe_worker_says "worker-result=$LA_SUCCESS"
e2e_run_bin CLAUDECODE=1 GH_TOKEN=t1 GITHUB_TOKEN=t2 GH_ENTERPRISE_TOKEN=t3 GITHUB_ENTERPRISE_TOKEN=t4 \
  FLOW_TIER_DIR=/x FLOW_TIER_CALL=1 CLAUDE_HOOK_GOAL_JUDGE_MODE=x CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 \
  SSH_AUTH_SOCK=/s GIT_ASKPASS=/a GIT_SSH=/g GIT_SSH_COMMAND=ssh FOO_BAR=1 AWS_REGION=eu-west-1 \
  GOOGLE_APPLICATION_CREDENTIALS=/c MY_VAR=mine bin/flow-factory.sh launch "$LA_ID"
e2e_expect_line "LAUNCHED directive=$LA_ID"
la_wait
for LA_V in CLAUDECODE GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN FLOW_TIER_DIR FLOW_TIER_CALL \
    CLAUDE_HOOK_GOAL_JUDGE_MODE CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS SSH_AUTH_SOCK GIT_ASKPASS GIT_SSH GIT_SSH_COMMAND FOO_BAR; do
  e2e_expect_equal no "$(la_env_has 1 "$LA_V")" "worker environment has $LA_V"
done
e2e_expect_equal eu-west-1 "$(la_env_value 1 AWS_REGION)" "AWS_REGION"
e2e_expect_equal /c "$(la_env_value 1 GOOGLE_APPLICATION_CREDENTIALS)" "GOOGLE_APPLICATION_CREDENTIALS"
e2e_expect_equal mine "$(la_env_value 1 MY_VAR)" "MY_VAR (worker.extraEnv)"
fi

# ---------------------------------------------------------------- LA3
if la_run LA3; then
fe_new la3-keep-superset
e2e_describe "the factory's keep list covers every name of flow-eval-run.sh's KEEP_ENV_NAMES, and the patterns are equal"
e2e_repo main
fe_py 'import _flow_factory_launch as L
print(" ".join(L.KEEP_ENV_NAMES))
print(L.KEEP_ENV_PATTERN.pattern)'
LA_OURS=$(printf '%s\n' "$E2E_OUT" | sed -n 1p)
LA_PAT=$(printf '%s\n' "$E2E_OUT" | sed -n 2p)
LA_EVAL="$E2E_PLUGIN_DIR/bin/flow-eval-run.sh"
LA_NAMES=$(awk '/^KEEP_ENV_NAMES=\(/ { p = 1; next } p && /^\)/ { exit } p' "$LA_EVAL" | tr -s ' \n' '\n\n' | sed '/^$/d')
LA_EVAL_PAT=$(sed -n "s/^KEEP_ENV_PATTERN='\(.*\)'$/\1/p" "$LA_EVAL")
e2e_expect_equal 26 "$(printf '%s\n' "$LA_NAMES" | wc -l | tr -d ' ')" "names parsed from flow-eval-run.sh"
LA_MISSING=""
for LA_V in $LA_NAMES; do
  case " $LA_OURS " in *" $LA_V "*) ;; *) LA_MISSING="$LA_MISSING $LA_V" ;; esac
done
e2e_expect_equal "" "$LA_MISSING" "names of flow-eval-run.sh missing from the factory's list"
e2e_expect_equal "$LA_EVAL_PAT" "$LA_PAT" "keep pattern"
fi

# ---------------------------------------------------------------- LA4
if la_run LA4; then
fe_new la4-worker-path
e2e_describe "a flow shim directory (one with ../scripts/lib/tier-runtime.sh) is first on the caller's PATH"
la_seed
la_plugin 'RUN: true'
fe_worker_says "worker-result=$LA_SUCCESS"
mkdir -p "$E2E_DIR/fp/shims" "$E2E_DIR/fp/scripts/lib"
: > "$E2E_DIR/fp/scripts/lib/tier-runtime.sh"
e2e_run_bin PATH="$E2E_DIR/fp/shims:$E2E_BIN:$PATH" bin/flow-factory.sh launch "$LA_ID"
e2e_expect_line "LAUNCHED directive=$LA_ID"
la_wait
LA_WPATH=$(la_env_value 1 PATH)
e2e_expect_equal "$(dirname "$(fe_python)")" "${LA_WPATH%%:*}" "first worker PATH entry"
LA_SHIMS=""
LA_OLDIFS=$IFS; IFS=:
for LA_D in $LA_WPATH; do
  [ -f "$LA_D/../scripts/lib/tier-runtime.sh" ] && LA_SHIMS="$LA_SHIMS $LA_D"
done
IFS=$LA_OLDIFS
e2e_expect_equal "" "$LA_SHIMS" "worker PATH entries with ../scripts/lib/tier-runtime.sh"
fi

# ---------------------------------------------------------------- LA5
if la_run LA5; then
fe_new la5-model
e2e_describe "the record's platform model is claude-test-model and worker.model is unset"
LA_RECORD_EDITS='d["groups"]["platform"]["keyed_on"]["model"] = "claude-test-model"' la_seed
la_plugin 'RUN: true'
fe_worker_says "worker-result=$LA_SUCCESS"
la_launch
la_wait
e2e_expect_equal claude-test-model "$(la_arg_after 1 --model)" "--model"
e2e_expect_equal no "$(la_has_arg 1 --max-turns)" "argv has --max-turns"
e2e_expect_equal claude-test-model "$(la_jq "$LA_J/directives/$LA_ID.json" .model)" "directive model"
fi

# ---------------------------------------------------------------- LA6
if la_run LA6; then
fe_new la6a-fresh
e2e_describe "a fresh directive of a job that has a recorded build session"
la_seed "d['sessions'] = {'build': '11111111-1111-4111-8111-111111111111'}" \
  "d['session_id'] = '22222222-2222-4222-8222-222222222222'"
la_plugin 'RUN: true'
fe_worker_says "worker-result=$LA_SUCCESS"
la_launch
la_wait
e2e_expect_equal 22222222-2222-4222-8222-222222222222 "$(la_arg_after 1 --session-id)" "--session-id"
e2e_expect_equal no "$(la_has_arg 1 --resume)" "argv has --resume"
e2e_expect_equal no "$(la_has_arg 1 --fork-session)" "argv has --fork-session"
if cmp -s "$E2E_BIN/claude-stdin-1.txt" "$E2E_ACTIVE_PLUGIN/templates/factory/build.prompt.md"; then LA_X=same; else LA_X=differs; fi
e2e_expect_equal same "$LA_X" "prompt on stdin against the build template"

fe_new la6b-resume
e2e_describe "the same job with a resume directive made by row 39"
la_seed "d['sessions'] = {'build': '11111111-1111-4111-8111-111111111111'}" \
  "d['start_mode'] = 'resume'; d['cause_row'] = '39'; d['prompt_template'] = 'templates/factory/resume.prompt.md'"
la_plugin 'RUN: true'
fe_worker_says
la_launch
la_wait
e2e_expect_equal 11111111-1111-4111-8111-111111111111 "$(la_arg_after 1 --resume)" "--resume"
e2e_expect_equal yes "$(la_has_arg 1 --fork-session)" "argv has --fork-session"
e2e_expect_equal no "$(la_has_arg 1 --session-id)" "argv has --session-id"
e2e_expect_equal 0 "$(grep -c '^/' "$E2E_BIN/claude-stdin-1.txt")" "prompt lines starting with /"
e2e_expect_equal 1 "$(grep -c "That run stopped because the stage's last run failed." "$E2E_BIN/claude-stdin-1.txt")" "resume prompt names row 39's reason"
e2e_expect_equal 0 "$(grep -c '{' "$E2E_BIN/claude-stdin-1.txt")" "unfilled placeholders in the resume prompt"
fi

# ---------------------------------------------------------------- LA7
if la_run LA7; then
fe_new la7-dirty-first-launch
e2e_describe "the job clone has a.txt edited and new.txt untracked before the stage's first, fresh launch"
e2e_repo main
( _e2e_git_env; cd "$E2E_REPO" && printf 'a\n' > a.txt && git add a.txt && git commit -q -m a ) || _flow_assert_fail "LA7: commit a.txt"
fe_record
fe_enable
fe_job 7 build "d['directive'] = '$LA_ID'"
fe_job_clone 7
fe_directive "$LA_ID"
LA_F=$(fe_factory_dir); LA_J="$LA_F/jobs/issue-7"
LA_WT=$(la_jq "$LA_J/job.json" .worktree)
printf 'edited\n' > "$LA_WT/a.txt"
printf 'new\n' > "$LA_WT/new.txt"
la_plugin 'RUN: true'
fe_worker_says "claude-script=echo '--- start'; git status --porcelain"
la_launch
e2e_expect_line "LAUNCHED directive=$LA_ID"
la_wait
LA_REF=refs/flow-factory/issue-7/snapshot-1
e2e_expect_equal edited "$(_fe_in_scratch git -C "$LA_WT" show "$LA_REF:a.txt" 2>&1)" "a.txt in $LA_REF"
e2e_expect_equal new "$(_fe_in_scratch git -C "$LA_WT" show "$LA_REF:new.txt" 2>&1)" "new.txt in $LA_REF"
e2e_expect_equal "" "$(la_block 1)" "git status at the start of launch 1"
e2e_expect_equal 1 "$(grep -cxF "Edits from an earlier session are kept in $LA_REF." "$E2E_BIN/claude-stdin-1.txt")" "prompt names the snapshot"
e2e_expect_equal "$LA_REF" "$(la_jq "$LA_J/directives/$LA_ID.json" .snapshot_ref)" "directive snapshot_ref"
# The job's record lists the snapshot as the engine's own snapshots do
# ({ref, k, reason, at}), and a snapshot event carries the whole list, so the
# person's history (rebuilt from events) names it too.
LA_SNAP_WANT="[{\"ref\":\"$LA_REF\",\"k\":1,\"reason\":\"fresh launch of $LA_ID\"}]"
e2e_expect_equal "$LA_SNAP_WANT" "$(jq -c '[.snapshots[]? | {ref, k, reason}]' "$LA_J/job.json" 2>&1)" "job.json snapshots"
e2e_expect_equal yes "$(jq -r 'if (.snapshots | length) == 1 and (.snapshots[0].at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}")) then "yes" else "no" end' "$LA_J/job.json" 2>&1)" "job.json snapshot has a UTC time"
e2e_expect_equal "$LA_SNAP_WANT" "$(jq -c 'select(.type == "snapshot") | [.snapshots[] | {ref, k, reason}]' "$LA_J/events.jsonl" 2>&1)" "one snapshot event with the whole list"
e2e_expect_equal "$LA_REF 1 fresh launch of $LA_ID" "$(jq -r 'select(.type == "snapshot") | "\(.ref) \(.k) \(.reason)"' "$LA_J/events.jsonl" 2>&1)" "snapshot event names the ref"
fi

# ---------------------------------------------------------------- LA8
if la_run LA8; then
fe_new la8-resume-charge
e2e_describe "a resumed run whose session total is 1.20 and whose own since-last cost is 0.20 + 0.03"
LA_SID=33333333-3333-4333-8333-333333333333
la_seed "d['sessions'] = {'build': '$LA_SID'}; d['cost']['usd_total'] = 0.97; d['cost']['stage_usd'] = {'build': 0.97}; d['last_session_total'] = {'$LA_SID': 0.97}" \
  "d['start_mode'] = 'resume'; d['cause_row'] = '39'; d['prompt_template'] = 'templates/factory/resume.prompt.md'"
la_plugin 'RUN: true'
fe_worker_says "worker-result={\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"num_turns\":1,\"session_id\":\"$LA_SID\",\"total_cost_usd\":1.20,\"model_usage_since_last_result\":{\"claude-opus-5-5\":{\"costUSD\":0.20},\"claude-haiku-4-5\":{\"costUSD\":0.03}}}"
la_launch
la_wait
# Hand computation: 0.97 + 0.20 + 0.03 = 1.20 (the total would give 2.17,
# the first model only 1.17).
e2e_expect_equal 120 "$(la_cents "$LA_J/job.json" .cost.usd_total)" "job cost.usd_total in cents"
e2e_expect_equal 23 "$(la_cents "$LA_J/job.json" '.cost.runs[-1].charged_usd')" "last run charged in cents"
e2e_expect_equal since_last "$(la_jq "$LA_J/job.json" '.cost.runs[-1].basis')" "last run basis"
e2e_expect_equal 120 "$(la_cents "$LA_J/job.json" ".last_session_total[\"$LA_SID\"]")" "session total recorded"
fi

# ---------------------------------------------------------------- LA9
if la_run LA9; then
fe_new la9-per-run-limit
e2e_describe "build maxBudgetUsd 3.00, a fresh job: four launches of the stage, the fourth refused"
la_seed
la_plugin 'RUN: true'
la_settings '.flow.factory.worker.stages.build.maxBudgetUsd = 3'
# (i), (ii): third = 1.00; min(1.00, 3.00 - 0) - 0.50 = 0.50.
fe_worker_says 'worker-result={"type":"result","subtype":"error_max_budget_usd","is_error":true,"num_turns":3,"total_cost_usd":0.62}'
la_launch
la_wait
e2e_expect_equal 0.5 "$(la_arg_after 1 --max-budget-usd)" "run 1 --max-budget-usd"
e2e_expect_equal 62 "$(la_cents "$LA_J/job.json" '.cost.runs[-1].charged_usd')" "run 1 charged in cents"
e2e_expect_equal first_total "$(la_jq "$LA_J/job.json" '.cost.runs[-1].basis')" "run 1 basis"
e2e_expect_equal 62 "$(la_cents "$LA_J/job.json" .cost.stage_usd.build)" "stage_usd.build after run 1"
e2e_expect_equal error "$(la_jq "$LA_J/results/$LA_ID.json" .outcome)" "run 1 outcome"
# (iii): min(1.00, 3.00 - 0.62) - 0.50 = 0.50; 0.62 + 0.95 = 1.57.
la_next_directive issue-7-j1-build-2
fe_worker_says 'worker-result={"type":"result","subtype":"success","is_error":false,"num_turns":2,"total_cost_usd":0.95}'
la_launch issue-7-j1-build-2
la_wait issue-7-j1-build-2
e2e_expect_equal 0.5 "$(la_arg_after 2 --max-budget-usd)" "run 2 --max-budget-usd"
e2e_expect_equal 95 "$(la_cents "$LA_J/job.json" '.cost.runs[-1].charged_usd')" "run 2 charged in cents"
e2e_expect_equal 157 "$(la_cents "$LA_J/job.json" .cost.stage_usd.build)" "stage_usd.build after run 2"
# (iv): min(1.00, 3.00 - 1.57) - 0.50 = 0.50; 1.57 + 0.98 = 2.55.
la_next_directive issue-7-j1-build-3
fe_worker_says 'worker-result={"type":"result","subtype":"success","is_error":false,"num_turns":2,"total_cost_usd":0.98}'
la_launch issue-7-j1-build-3
la_wait issue-7-j1-build-3
e2e_expect_equal 0.5 "$(la_arg_after 3 --max-budget-usd)" "run 3 --max-budget-usd"
e2e_expect_equal 98 "$(la_cents "$LA_J/job.json" '.cost.runs[-1].charged_usd')" "run 3 charged in cents"
e2e_expect_equal 255 "$(la_cents "$LA_J/job.json" .cost.stage_usd.build)" "stage_usd.build after run 3"
# (v): min(1.00, 3.00 - 2.55) - 0.50 = 0.45 - 0.50 < 0: no launch.
la_next_directive issue-7-j1-build-4
la_launch issue-7-j1-build-4
e2e_expect_line "FACTORY_REFUSED=stage_budget_exhausted stage=build remaining=0.45 needed=0.50"
e2e_expect_equal 5 "$E2E_RC" "run 4 exit status"
e2e_expect_equal stage_budget_exhausted "$(la_jq "$LA_J/directives/issue-7-j1-build-4.json" .not_started_reason)" "run 4 not_started_reason"
e2e_expect_equal null "$(la_jq "$LA_J/directives/issue-7-j1-build-4.json" .started_at)" "run 4 started_at"
e2e_expect_equal 3 "$(la_launches)" "claude launches"
e2e_expect_equal 1 "$(jq -c 'select(.type == "launch_not_started" and .reason == "stage_budget_exhausted")' "$LA_J/events.jsonl" | wc -l | tr -d ' ')" "launch_not_started events"
fe_art_state 7
fi

if la_run LA9vi; then
fe_new la9vi-killed-run
e2e_describe "build maxBudgetUsd 3.00, a fresh job; claude is killed with SIGKILL while a step's sleep 30 runs in its group"
la_seed
la_plugin 'RUN: sleep 30'
la_settings '.flow.factory.worker.stages.build.maxBudgetUsd = 3'
fe_worker_says
la_launch
e2e_expect_line "LAUNCHED directive=$LA_ID"
fe_wait_for 15 "[ -n \"\$(jq -r '.child_pgid // empty' '$LA_J/directives/$LA_ID.lease.json' 2>/dev/null)\" ]"
LA_PG=$(la_jq "$LA_J/directives/$LA_ID.lease.json" .child_pgid)
fe_wait_for 15 "/bin/ps -A -o pgid=,command= | awk -v g=$LA_PG '\$1 == g && /sleep 30/ { f = 1 } END { exit !f }'"
kill -9 "$(cat "$E2E_BIN/claude-pid-1")"
la_wait "$LA_ID" 45
# A.10: min(1.00, 3.00) - 0.50 = 0.50, charged 0.50 + 0.50 = 1.00 (old rule:
# 2.50 and 3.00; halves cap: 1.00 and 1.50).
e2e_expect_equal 0.5 "$(la_arg_after 1 --max-budget-usd)" "--max-budget-usd"
e2e_expect_equal 100 "$(la_cents "$LA_J/job.json" '.cost.runs[-1].charged_usd')" "charged in cents"
e2e_expect_equal limit_plus_turn "$(la_jq "$LA_J/job.json" '.cost.runs[-1].basis')" "basis"
e2e_expect_equal killed "$(la_jq "$LA_J/results/$LA_ID.json" .outcome)" "outcome"
e2e_expect_equal 1 "$(jq -c 'select(.type == "charge")' "$LA_J/events.jsonl" | wc -l | tr -d ' ')" "charge events"
e2e_expect_equal 1 "$(find "$LA_J/pending" -name '*-stage_failed.json' | wc -l | tr -d ' ')" "pending stage_failed events"
fi

# ---------------------------------------------------------------- LA10
if la_run LA10; then
fe_new la10a-usage-limit
e2e_describe "the run ends with a usage limit (429 usage_limit_reached)"
la_seed
la_plugin 'RUN: true'
fe_worker_says 'worker-result={"type":"result","subtype":"success","is_error":true,"num_turns":1,"total_cost_usd":0,"api_error_status":429,"api_error":"usage_limit_reached","terminal_reason":"api_error"}'
LA_T0=$(date -u +%s)
la_launch
la_wait
e2e_expect_equal usage_limit "$(la_jq "$LA_J/results/$LA_ID.json" .outcome)" "outcome"
e2e_expect_equal null "$(la_jq "$LA_J/results/$LA_ID.json" .event)" "result event"
e2e_expect_equal 0 "$(find "$LA_J/pending" -type f 2>/dev/null | wc -l | tr -d ' ')" "pending events"
e2e_expect_equal 0 "$(la_jq "$LA_J/job.json" .attempt)" "job attempt"
LA_PU=$(la_jq "$LA_F/state.json" .paused_until)
LA_PUS=$(jq -rn --arg t "$LA_PU" '$t | fromdateiso8601' 2>/dev/null)
# A.8: now + 3600 s; the launch took under a minute.
if [ -n "$LA_PUS" ] && [ "$LA_PUS" -ge $((LA_T0 + 3600)) ] && [ "$LA_PUS" -le $((LA_T0 + 3660)) ]; then LA_X=yes; else LA_X="no ($LA_PU)"; fi
e2e_expect_equal yes "$LA_X" "state.json paused_until is 3600 s after the launch"

fe_new la10c-pause-fails-after-charge
e2e_describe "the run ends with a usage limit and cost 0.30, and state.json cannot be read when the launcher pauses, so the pause fails after the charge was applied"
la_seed
la_plugin 'RUN: true'
fe_worker_says 'worker-result={"type":"result","subtype":"success","is_error":true,"num_turns":1,"total_cost_usd":0.30,"api_error_status":429,"api_error":"usage_limit_reached","terminal_reason":"api_error"}' worker-sleep=3
la_launch
e2e_expect_line "LAUNCHED directive=$LA_ID"
fe_wait_for 15 "[ -f '$E2E_BIN/claude-pid-1' ]"
printf '{' > "$LA_F/state.json"
la_wait
e2e_expect_equal usage_limit "$(la_jq "$LA_J/results/$LA_ID.json" .outcome)" "outcome (the first one, not rewritten)"
e2e_expect_equal 1 "$(la_jq "$LA_J/job.json" '.cost.runs | length')" "runs charged in job.json"
e2e_expect_equal 30 "$(la_cents "$LA_J/job.json" .cost.usd_total)" "job cost in cents"
e2e_expect_equal 30 "$(la_cents "$LA_J/job.json" .cost.stage_usd.build)" "build stage cost in cents"
e2e_expect_equal 1 "$(grep -c '"type": *"charge"' "$LA_J/events.jsonl" 2>/dev/null)" "charge events"
if grep -q 'state_unreadable' "$LA_J/results/$LA_ID.launcher.log" 2>/dev/null; then LA_X=yes; else LA_X=no; fi
e2e_expect_equal yes "$LA_X" "launcher log names the failed pause"

fe_new la10b-api-error
e2e_describe "the run ends with an overloaded API error (529)"
la_seed
la_plugin 'RUN: true'
fe_worker_says 'worker-result={"type":"result","subtype":"success","is_error":true,"num_turns":1,"total_cost_usd":0,"api_error_status":529,"api_error":"overloaded_error","terminal_reason":"api_error"}'
la_launch
la_wait
e2e_expect_equal api_error "$(la_jq "$LA_J/results/$LA_ID.json" .outcome)" "outcome"
e2e_expect_equal 1 "$(find "$LA_J/pending" -name '*-stage_failed.json' | wc -l | tr -d ' ')" "pending stage_failed events"
e2e_expect_equal null "$(la_jq "$LA_F/state.json" .paused_until 2>/dev/null || echo null)" "state.json paused_until"
fi

# ---------------------------------------------------------------- LA11
LA_T='t() { perl -MTime::HiRes=time -e '"'"'printf "%.2f", time'"'"'; }'
if la_run LA11; then
fe_new la11a-timeout-term
e2e_describe "timeout_seconds 2; the worker traps TERM, then takes 10 s to exit"
la_seed "" "d['timeout_seconds'] = 2"
la_plugin 'RUN: true'
fe_worker_says
cat > "$E2E_BIN/claude-script" <<SH
$LA_T
echo '--- start'
trap 'echo "term-at \$(t)"; sleep 10; echo "term-exit \$(t)"; exit 0' TERM
while :; do sleep 0.2; done
SH
la_launch
# Read before anything else once launch has returned. A launch that waited
# for its worker returns only after the worker has handled TERM and written
# term-exit, 12 s or more after it started; one that does not wait returns
# while the worker still runs, so term-exit is not there yet. This holds on
# a loaded machine, where a bound on launch's own time (the plan's "under
# 2 s") does not: launch took 2.35 s and 2.60 s with 8 test files running.
if grep -q '^term-exit ' "$E2E_BIN/claude-script.out" 2>/dev/null; then LA_X="no: the worker had already ended"; else LA_X=yes; fi
e2e_expect_line "LAUNCHED directive=$LA_ID"
e2e_expect_equal yes "$LA_X" "launch returned while its worker still ran"
la_wait "$LA_ID" 45
LA_TA=$(sed -n 's/^term-at //p' "$E2E_BIN/claude-script.out")
LA_TE=$(sed -n 's/^term-exit //p' "$E2E_BIN/claude-script.out")
e2e_expect_equal yes "$(awk -v a="$LA_TA" -v b="$LA_TE" 'BEGIN { d = b - a; print (a != "" && b != "" && d >= 10 && d <= 12) ? "yes" : "no (" d " s)" }')" "term-exit 10-12 s after term-at"
e2e_expect_equal timeout "$(la_jq "$LA_J/results/$LA_ID.json" .outcome)" "outcome"
# A.10: third = 20 / 3 = 6.66 (rounded down); 6.66 - 0.50 = 6.16; charged
# 6.16 + 0.50 = 6.66.
e2e_expect_equal 6.16 "$(la_arg_after 1 --max-budget-usd)" "--max-budget-usd"
e2e_expect_equal 666 "$(la_cents "$LA_J/job.json" '.cost.runs[-1].charged_usd')" "charged in cents"
e2e_expect_equal limit_plus_turn "$(la_jq "$LA_J/job.json" '.cost.runs[-1].basis')" "basis"

fe_new la11b-timeout-kill
e2e_describe "timeout_seconds 2; the worker ignores TERM and keeps printing alive every 0.1 s"
la_seed "" "d['timeout_seconds'] = 2"
la_plugin 'RUN: true'
fe_worker_says
cat > "$E2E_BIN/claude-script" <<SH
$LA_T
echo '--- start'
trap 'echo "term-at \$(t)"' TERM
while :; do echo "alive \$(t)"; sleep 0.1; done
SH
la_launch
la_wait "$LA_ID" 60
LA_TA=$(sed -n 's/^term-at //p' "$E2E_BIN/claude-script.out" | head -n 1)
LA_LAST=$(sed -n 's/^alive //p' "$E2E_BIN/claude-script.out" | tail -n 1)
# The SIGKILL is due 30 s after SIGTERM. The worker prints alive every
# 0.1 s plus one perl start (0.04 s measured at load average 64), so its last
# line lands well within 0.7 s before the kill: at 29.3 s or later when the
# kill comes at 30 s, and before 29.3 s when it comes 1 s early. A 0.5 s tick
# left only about 0.15 s of that room on a loaded machine.
e2e_expect_equal yes "$(awk -v a="$LA_TA" -v b="$LA_LAST" 'BEGIN { d = b - a; print (a != "" && d >= 29.3 && d <= 33) ? "yes" : "no (" d " s)" }')" "last alive 29.3-33 s after term-at"
e2e_expect_equal 0 "$(sed -n 's/^alive //p' "$E2E_BIN/claude-script.out" | awk -v a="$LA_TA" '$1 - a > 33.5' | wc -l | tr -d ' ')" "alive lines later than 33.5 s after term-at"
e2e_expect_equal timeout "$(la_jq "$LA_J/results/$LA_ID.json" .outcome)" "outcome"
fi

# ---------------------------------------------------------------- LA13
if la_run LA13; then
fe_new la13-platform-stale
e2e_describe "claude --version is 2.1.326; the platform group is stamped 2.1.326 but P5 is still 2.1.325"
LA_RECORD_EDITS='v = "2.1.326 (Claude Code)"
d["groups"]["platform"]["keyed_on"]["claude_version"] = v
for pid, e in d["probes"].items():
    if e.get("group") == "platform" and pid != "P5" and "keyed_on" in e:
        e["keyed_on"]["claude_version"] = v
        for part in (e.get("parts") or {}).values():
            part["keyed_on"]["claude_version"] = v' la_seed
la_plugin 'RUN: true'
fe_worker_says "worker-result=$LA_SUCCESS" "claude-version=2.1.326 (Claude Code)"
la_launch
e2e_expect_line "PROBES_STALE=platform"
e2e_expect_equal 5 "$E2E_RC" "launch exit status"
e2e_expect_equal probes_stale "$(la_jq "$LA_J/directives/$LA_ID.json" .not_started_reason)" "not_started_reason"
e2e_expect_equal 0 "$(la_jq "$LA_J/job.json" .attempt)" "job attempt"
e2e_expect_equal 0 "$(la_launches)" "claude launches"
if [ -e "$LA_J/directives/$LA_ID.lease.json" ]; then LA_X=present; else LA_X=absent; fi
e2e_expect_equal absent "$LA_X" "lease"
fi

# ---------------------------------------------------------------- LA14
if la_run LA14; then
fe_new la14-prompt-missing
e2e_describe "the plugin has no templates/factory/build.prompt.md"
la_seed
la_plugin
fe_worker_says "worker-result=$LA_SUCCESS"
la_launch
e2e_expect_line "FACTORY_REFUSED=prompt_missing stage=build"
e2e_expect_equal 5 "$E2E_RC" "launch exit status"
e2e_expect_equal prompt_missing "$(la_jq "$LA_J/directives/$LA_ID.json" .not_started_reason)" "not_started_reason"
e2e_expect_equal 0 "$(la_launches)" "claude launches"
fi

# ---------------------------------------------------------------- LA15
if la_run LA15; then
fe_new la15-external-report
e2e_describe "the test shell, under no lease, runs report for a directive"
la_seed
la_plugin 'RUN: true'
e2e_run_bin bin/flow-factory.sh report "$LA_ID"
e2e_expect_line "PERSON_ONLY_REFUSED=not_launcher"
e2e_expect_equal 4 "$E2E_RC" "report exit status"
if [ -e "$LA_J/directives/$LA_ID.pending-report.jsonl" ] || [ -d "$LA_J/pending" ]; then LA_X=present; else LA_X=absent; fi
e2e_expect_equal absent "$LA_X" "pending report or event"
fi

# ---------------------------------------------------------------- LA16
if la_run LA16; then
fe_new la16a-in-process-report
e2e_describe "a run that succeeds: the launcher applies its report in its own process"
la_seed
la_plugin 'RUN: true'
fe_worker_says "worker-result=$LA_SUCCESS"
la_launch
la_wait
LA_LP=$(la_jq "$LA_J/directives/$LA_ID.lease.json" .launcher_pid)
fe_mask_pid "$LA_LP" launcher
fe_mask_found "$(la_jq "$LA_J/directives/$LA_ID.lease.json" .launcher_start)"
LA_P=$(find "$LA_J/pending" -name '*-stage_succeeded.json' | head -n 1)
e2e_expect_equal 1 "$(find "$LA_J/pending" -name '*-stage_succeeded.json' | wc -l | tr -d ' ')" "pending stage_succeeded events"
e2e_expect_equal "$LA_LP" "$(la_jq "$LA_P" .caller.pid)" "pending event caller pid (the launcher)"
e2e_expect_equal launcher "$(la_jq "$LA_P" .channel)" "pending event channel"
e2e_expect_equal "$(la_jq "$LA_J/directives/$LA_ID.lease.json" .launcher_start)" "$(la_jq "$LA_P" .caller.start)" "pending event caller start"
if [ -e "$LA_J/directives/$LA_ID.pending-report.jsonl" ]; then LA_X=present; else LA_X=absent; fi
e2e_expect_equal absent "$LA_X" "shell pending-report file"
e2e_expect_equal 1 "$(jq -c 'select(.type == "charge")' "$LA_J/events.jsonl" | wc -l | tr -d ' ')" "charge events"

fe_new la16b-interpreter-gone
e2e_describe "the recorded interpreter is a link that the test removes while the worker sleeps"
e2e_repo main
fe_record_link
fe_enable
fe_job 7 build "d['directive'] = '$LA_ID'"
fe_job_clone 7
fe_directive "$LA_ID"
LA_F=$(fe_factory_dir); LA_J="$LA_F/jobs/issue-7"
la_plugin 'RUN: true'
fe_worker_says "worker-result=$LA_SUCCESS" worker-sleep=3
la_launch
e2e_expect_line "LAUNCHED directive=$LA_ID"
fe_wait_for 15 "[ -f '$E2E_BIN/claude-pid-1' ]"
rm -f "$E2E_DIR/py/python3.14"
la_wait "$LA_ID" 30
LA_LP=$(la_jq "$LA_J/directives/$LA_ID.lease.json" .launcher_pid)
fe_mask_pid "$LA_LP" launcher
e2e_expect_equal 1 "$(wc -l < "$LA_J/directives/$LA_ID.pending-report.jsonl" 2>/dev/null | tr -d ' ')" "pending-report lines"
e2e_expect_equal "$LA_LP" "$(head -n 1 "$LA_J/directives/$LA_ID.pending-report.jsonl" | jq -r .caller_pid)" "pending-report caller_pid (the launcher)"
e2e_expect_equal completed "$(head -n 1 "$LA_J/directives/$LA_ID.pending-report.jsonl" | jq -r .report.outcome)" "reported outcome"
if [ -e "$LA_J/results/$LA_ID.json" ]; then LA_X=present; else LA_X=absent; fi
e2e_expect_equal absent "$LA_X" "results file"
fi

# ---------------------------------------------------------------- LA17
if la_run LA17; then
fe_new la17-lease-marker-heartbeat
e2e_describe "heartbeatSeconds 1; the worker sleeps 4 s"
la_seed
la_plugin 'RUN: true'
la_settings '.flow.factory.heartbeatSeconds = 1'
fe_worker_says "worker-result=$LA_SUCCESS" worker-sleep=4
la_launch
LA_L="$LA_J/directives/$LA_ID.lease.json"
fe_wait_for 15 "[ -n \"\$(jq -r '.child_pid // empty' '$LA_L' 2>/dev/null)\" ]"
LA_LP=$(la_jq "$LA_L" .launcher_pid)
LA_CMD=$(/bin/ps -ww -o command= -p "$LA_LP")
LA_BEATS=""
for LA_I in $(seq 1 30); do
  LA_B=$(la_jq "$LA_L" .heartbeat_at)
  case " $LA_BEATS " in *" $LA_B "*) ;; *) LA_BEATS="$LA_BEATS $LA_B" ;; esac
  [ -f "$LA_J/results/$LA_ID.json" ] && break
  sleep 0.2
done
la_wait
case "$LA_CMD" in
  *"/bin/_flow_factory_launch.py --factory-dir $LA_F $LA_ID") LA_X=marker ;;
  *) LA_X="not a marker: $LA_CMD" ;;
esac
e2e_expect_equal marker "$LA_X" "the launcher's command line names F and the directive"
fe_mask_pid "$(la_jq "$LA_L" .child_pid)" child
fe_mask_found "$(la_jq "$LA_L" .launcher_start)"
e2e_expect_equal "$(la_jq "$LA_L" .child_pid)" "$(la_jq "$LA_L" .child_pgid)" "child_pgid equals child_pid"
e2e_expect_equal "$(la_jq "$LA_L" .launcher_start)" "$(la_jq "$LA_L" .launcher_start | grep -E '^[A-Z][a-z]{2} [A-Z][a-z]{2} [ 0-9][0-9] [0-9:]{8} [0-9]{4}$')" "launcher_start in the lstart form"
e2e_expect_equal null "$(la_jq "$LA_L" .revoked_at)" "revoked_at"
e2e_expect_equal yes "$([ "$(printf '%s\n' $LA_BEATS | wc -l | tr -d ' ')" -ge 2 ] && echo yes || echo "no:$LA_BEATS")" "two or more heartbeat_at values seen"
fi

# ---------------------------------------------------------------- LA18
if la_run LA18; then
fe_new la18-in-rewritten
e2e_describe "launch 1's worker changes in/job.env and adds in/evil.md; launch 2 lists in/"
la_seed
la_plugin 'RUN: true'
fe_worker_says
# fe_worker_says takes no / in a knob, so the script is written directly.
cat > "$E2E_BIN/claude-script" <<'SH'
echo '--- start'
printf 'X=1\n' >> "$FLOW_FACTORY_IO/in/job.env"
echo evil > "$FLOW_FACTORY_IO/in/evil.md"
SH
la_launch
la_wait
la_next_directive issue-7-j1-build-2
cat > "$E2E_BIN/claude-script" <<'SH'
echo '--- start'
ls "$FLOW_FACTORY_IO/in"
cat "$FLOW_FACTORY_IO/in/job.env"
SH
la_launch issue-7-j1-build-2
la_wait issue-7-j1-build-2
e2e_expect_equal "$(printf 'job.env\n'; cat "$LA_J/in-copies/job.env")" "$(la_block 2)" "in/ at launch 2's start"
fi

# ---------------------------------------------------------------- LA19
if la_run LA19; then
fe_new la19-plugin-inside
e2e_describe "the plugin copy that runs lies inside the scratch main checkout"
la_seed
E2E_ACTIVE_PLUGIN="$E2E_REPO/plugin-inside"
e2e_copy_plugin "$E2E_PLUGIN_DIR" "$E2E_ACTIVE_PLUGIN" || _flow_assert_fail "LA19: copy the plugin"
printf 'RUN: true\n' > "$E2E_ACTIVE_PLUGIN/templates/factory/build.prompt.md"
fe_worker_says "worker-result=$LA_SUCCESS"
la_launch
e2e_expect_line "FACTORY_REFUSED=plugin_inside_repository"
e2e_expect_equal 5 "$E2E_RC" "launch exit status"
e2e_expect_equal 0 "$(la_launches)" "claude launches"
fi

# ---------------------------------------------------------------- LA20
if la_run LA20; then
fe_new la20a-allowance-dearest
e2e_describe "build maxBudgetUsd 3.00; the job's dearest turn so far cost 0.40"
la_seed "d['cost']['dearest_turn_usd'] = 0.40"
la_plugin 'RUN: true'
la_settings '.flow.factory.worker.stages.build.maxBudgetUsd = 3'
fe_worker_says "worker-result=$LA_SUCCESS"
la_launch
la_wait
# A.7: allowance max(0.50, 2 x 0.40) = 0.80; A.10: min(1.00, 3.00) - 0.80 = 0.20.
e2e_expect_equal 0.2 "$(la_arg_after 1 --max-budget-usd)" "--max-budget-usd"

fe_new la20b-allowance-floor
e2e_describe "build maxBudgetUsd 3.00; a fresh job (dearest turn 0)"
la_seed
la_plugin 'RUN: true'
la_settings '.flow.factory.worker.stages.build.maxBudgetUsd = 3'
fe_worker_says "worker-result=$LA_SUCCESS"
la_launch
la_wait
# max(0.50, 0) = 0.50; min(1.00, 3.00) - 0.50 = 0.50.
e2e_expect_equal 0.5 "$(la_arg_after 1 --max-budget-usd)" "--max-budget-usd"
fi

# ---------------------------------------------------------------- LA21
if la_run LA21; then
fe_new la21a-dearest-turn
e2e_describe "two RUN steps; the first message's usage prices at 0.16, every later one at 0.044"
la_seed
la_plugin $'RUN: true\nRUN: true'
fe_worker_says claude-model=claude-opus-5-5 \
  "claude-turn-usage=$(printf '0.01\t{"input_tokens":10000,"output_tokens":5000,"cache_read_input_tokens":100000}\n0.02\t{"input_tokens":1000,"output_tokens":2000}')"
la_launch
la_wait
# MODEL_PRICES claude-opus-5-5: input 4, output 20, cache read 0.20 dollars per
# million tokens. Turn 1: (10000 x 4 + 5000 x 20 + 100000 x 0.20) / 10^6 =
# 0.16; turn 2: (1000 x 4 + 2000 x 20) / 10^6 = 0.044. The dearest is 0.16
# (the last turn gives 44, the sum of three turns 248, the charged column 20).
e2e_expect_equal 160 "$(jq -r '.cost.dearest_turn_usd * 1000 | round' "$LA_J/job.json")" "dearest_turn_usd in tenths of a cent"
e2e_expect_equal completed "$(la_jq "$LA_J/results/$LA_ID.json" .outcome)" "outcome"
# The next launch's allowance stays 0.50 (2 x 0.16 = 0.32 < 0.50): with the
# default build budget 20 the third is 6.66, run 1 spent well under 13.34, so
# the limit is 6.66 - 0.50 = 6.16 (an allowance of 0.32 would give 6.34).
la_next_directive issue-7-j1-build-2
la_launch issue-7-j1-build-2
la_wait issue-7-j1-build-2
e2e_expect_equal 6.16 "$(la_arg_after 2 --max-budget-usd)" "run 2 --max-budget-usd (allowance 0.50)"

fe_new la21b-no-turn
e2e_describe "a stream with an init event and a result but no assistant turn"
la_seed
la_plugin 'RUN: true'
fe_worker_says "worker-result=$LA_SUCCESS"
la_launch
la_wait
e2e_expect_equal 0 "$(la_jq "$LA_J/job.json" .cost.dearest_turn_usd)" "dearest_turn_usd"
fi

# ---------------------------------------------------------------- LA22
if la_run LA22; then
fe_new la22a-id-refusals
e2e_describe "launch with a malformed directive id, then with a well-formed id that has no directive file"
la_seed
la_plugin 'RUN: true'
fe_worker_says "worker-result=$LA_SUCCESS"
la_launch issue-7-build-1
e2e_expect_line "FACTORY_REFUSED=directive_id_invalid"
e2e_expect_equal 5 "$E2E_RC" "malformed id exit status"
la_launch issue-7-j1-build-9
e2e_expect_line "FACTORY_REFUSED=directive_unknown directive=issue-7-j1-build-9"
e2e_expect_equal 5 "$E2E_RC" "unknown id exit status"
e2e_expect_equal 0 "$(la_launches)" "claude launches"

fe_new la22b-kind-not-built
e2e_describe "the job's current directive is a judge directive"
la_seed "" "d['kind'] = 'judge'; d['session_id'] = None; d['prompt_template'] = None; d['timeout_seconds'] = None; d['allowed_tools'] = None"
la_plugin 'RUN: true'
fe_worker_says "worker-result=$LA_SUCCESS"
la_launch
e2e_expect_line "FACTORY_REFUSED=kind_not_built directive=$LA_ID kind=judge"
e2e_expect_equal 5 "$E2E_RC" "launch exit status"
e2e_expect_equal kind_not_built "$(la_jq "$LA_J/directives/$LA_ID.json" .not_started_reason)" "not_started_reason"
e2e_expect_equal null "$(la_jq "$LA_J/directives/$LA_ID.json" .started_at)" "started_at"
e2e_expect_equal 1 "$(jq -c 'select(.type == "launch_not_started" and .reason == "kind_not_built")' "$LA_J/events.jsonl" | wc -l | tr -d ' ')" "launch_not_started events"
e2e_expect_equal 0 "$(la_launches)" "claude launches"

fe_new la22b-directive-kind-not-built
e2e_describe "the job's current directive is an engine directive (kind directive), which phase 1b does not launch"
la_seed "" "d['kind'] = 'directive'; d['session_id'] = None; d['prompt_template'] = None; d['timeout_seconds'] = None; d['allowed_tools'] = None"
la_plugin 'RUN: true'
fe_worker_says "worker-result=$LA_SUCCESS"
la_launch
e2e_expect_line "FACTORY_REFUSED=kind_not_built directive=$LA_ID kind=directive"
e2e_expect_equal 5 "$E2E_RC" "launch exit status"
e2e_expect_equal 0 "$(la_launches)" "claude launches"

fe_new la22b-intake-judge-launches
e2e_describe "plan B11 step 2 and R93: an intake judge directive (kind judge, stage intake, session_id null as create_directive writes every judge directive) is launched, not refused with kind_not_built or directive_unknown; the judge reply comes from the stand-in (fe_judge_says)"
e2e_repo main
fe_record
fe_enable
fe_job 7 intake "d['directive'] = 'issue-7-j1-intake-1'; d['worktree'] = None; d['io_dir'] = None"
fe_directive issue-7-j1-intake-1 "d['kind'] = 'judge'; d['session_id'] = None; d['prompt_template'] = None; d['timeout_seconds'] = None; d['allowed_tools'] = None"
LA_F=$(fe_factory_dir)
LA_J="$LA_F/jobs/issue-7"
mkdir -p "$LA_J/in-copies"
printf '%s\n' '<<<UNTRUSTED_ISSUE_TITLE>>>' '> Add a port setting' '<<<END_UNTRUSTED_ISSUE_TITLE>>>' > "$LA_J/in-copies/issue.md"
fe_judge_says '{"decision":"REJECT","risk":"high","surfaces":[],"scope":"none","proposed_criteria":[],"questions":[],"reason":"no"}'
la_launch issue-7-j1-intake-1
e2e_expect_line "LAUNCHED directive=issue-7-j1-intake-1"
e2e_expect_equal 0 "$E2E_RC" "launch exit status"
la_wait issue-7-j1-intake-1
e2e_expect_equal 1 "$(la_launches)" "claude launches"
e2e_expect_equal 0 "$(grep -c 'kind_not_built\|directive_unknown' "$LA_J/events.jsonl")" "refusal events"
e2e_expect_equal null "$(la_jq "$LA_J/directives/issue-7-j1-intake-1.json" .session_id)" "directive session_id"

fe_new la22c-claude-missing
e2e_describe "no claude on the PATH launch runs with"
la_seed
la_plugin 'RUN: true'
LA_NOCLAUDE=$(e2e_path_without claude)
e2e_run_bin PATH="$LA_NOCLAUDE" bin/flow-factory.sh launch "$LA_ID"
e2e_expect_line "FACTORY_REFUSED=claude_missing directive=$LA_ID"
e2e_expect_equal 5 "$E2E_RC" "launch exit status"
e2e_expect_equal 1 "$(jq -c 'select(.type == "launch_not_started" and .reason == "claude_missing" and .directive == "'"$LA_ID"'")' "$LA_J/events.jsonl" 2>/dev/null | wc -l | tr -d ' ')" "launch_not_started claude_missing events"
e2e_expect_equal null "$(la_jq "$LA_J/directives/$LA_ID.json" .not_started_reason)" "not_started_reason (the directive stays open; its lease expiry counts the attempt)"
e2e_expect_equal null "$(la_jq "$LA_J/directives/$LA_ID.json" .started_at)" "started_at"
if [ -e "$LA_J/directives/$LA_ID.lease.json" ]; then LA_X=present; else LA_X=absent; fi
e2e_expect_equal absent "$LA_X" "lease"

fe_new la22d-io-dir-missing
e2e_describe "the job's io directory is gone, then a symlink to a real directory"
la_seed
la_plugin 'RUN: true'
fe_worker_says "worker-result=$LA_SUCCESS"
LA_IO=$(la_jq "$LA_J/job.json" .io_dir)
mv "$LA_IO" "$LA_IO.real"
la_launch
e2e_expect_line "FACTORY_REFUSED=io_dir_missing directive=$LA_ID"
e2e_expect_equal 5 "$E2E_RC" "missing io_dir exit status"
ln -s "$LA_IO.real" "$LA_IO"
la_launch
e2e_expect_line "FACTORY_REFUSED=io_dir_missing directive=$LA_ID"
e2e_expect_equal 5 "$E2E_RC" "symlinked io_dir exit status"
e2e_expect_equal 2 "$(jq -c 'select(.type == "launch_not_started" and .reason == "io_dir_missing")' "$LA_J/events.jsonl" 2>/dev/null | wc -l | tr -d ' ')" "launch_not_started io_dir_missing events"
e2e_expect_equal null "$(la_jq "$LA_J/directives/$LA_ID.json" .started_at)" "started_at"
e2e_expect_equal 0 "$(la_launches)" "claude launches"
fi

# ---------------------------------------------------------------- LA23
if la_run LA23; then
fe_new la23a-launcher-fails-before-claude
e2e_describe "the launcher marker run directly on a claimed directive whose job clone does not exist, so claude cannot start"
e2e_repo main
fe_record
fe_enable
fe_job 7 build "d['directive'] = '$LA_ID'"
fe_directive "$LA_ID" "d['started_at'] = '2026-11-16T00:00:00Z'; d['max_budget_usd'] = 0.5; d['model'] = 'claude-opus-5-5'"
LA_F=$(fe_factory_dir); LA_J="$LA_F/jobs/issue-7"
la_plugin 'RUN: true'
fe_worker_says "worker-result=$LA_SUCCESS"
_e2e_exec "$(fe_python)" -E "$E2E_ACTIVE_PLUGIN/bin/_flow_factory_launch.py" --factory-dir "$LA_F" "$LA_ID"
e2e_expect_equal 1 "$E2E_RC" "launcher exit status"
fe_art_state 7
e2e_expect_equal not_started "$(la_jq "$LA_J/results/$LA_ID.json" .outcome)" "outcome"
e2e_expect_equal null "$(la_jq "$LA_J/results/$LA_ID.json" .event)" "result event"
e2e_expect_equal null "$(la_jq "$LA_J/results/$LA_ID.json" .charged_usd)" "charged"
e2e_expect_equal 0 "$(find "$LA_J/pending" -type f 2>/dev/null | wc -l | tr -d ' ')" "pending events"
e2e_expect_equal 1 "$(grep -c 'launcher failed' "$LA_J/results/$LA_ID.launcher.log" 2>/dev/null)" "launcher log records the failure"
e2e_expect_equal 0 "$(la_launches)" "claude launches"
e2e_expect_equal 1 "$(jq -c 'select(.type == "launch_not_started" and .reason == "launcher_failed" and .directive == "'"$LA_ID"'")' "$LA_J/events.jsonl" 2>/dev/null | wc -l | tr -d ' ')" "launch_not_started launcher_failed events"

fe_new la23c-launcher-fails-in-constructor
e2e_describe "the launcher marker run directly with a factory directory that is not the one it resolves (factory_dir_mismatch), whose jobs/issue-7/results folder exists"
la_seed
la_plugin 'RUN: true'
fe_worker_says "worker-result=$LA_SUCCESS"
LA_OTHER="$E2E_DIR/other-factory"
mkdir -p "$LA_OTHER/jobs/issue-7/results"
_e2e_exec "$(fe_python)" -E "$E2E_ACTIVE_PLUGIN/bin/_flow_factory_launch.py" --factory-dir "$LA_OTHER" "$LA_ID"
e2e_expect_equal 1 "$E2E_RC" "launcher exit status"
if grep -q 'factory_dir_mismatch' "$LA_OTHER/jobs/issue-7/results/$LA_ID.launcher.log" 2>/dev/null; then LA_X=yes; else LA_X=no; fi
e2e_expect_equal yes "$LA_X" "the marker's launcher log names factory_dir_mismatch"
e2e_expect_equal 0 "$(la_launches)" "claude launches"

fe_new la23b-launcher-fails-after-claude
e2e_describe "job.json becomes unreadable while the worker runs, so the launcher cannot apply its report"
la_seed
la_plugin 'RUN: true'
fe_worker_says "worker-result=$LA_SUCCESS" worker-sleep=3
la_launch
e2e_expect_line "LAUNCHED directive=$LA_ID"
fe_wait_for 15 "[ -f '$E2E_BIN/claude-pid-1' ]"
printf '{' > "$LA_J/job.json"
la_wait
# Default build budget 20: third 6.66, limit 6.16; the job cannot be read, so
# the allowance is the 0.50 floor: 6.16 + 0.50 = 6.66.
e2e_expect_equal no_result "$(la_jq "$LA_J/results/$LA_ID.json" .outcome)" "outcome"
e2e_expect_equal stage_failed "$(la_jq "$LA_J/results/$LA_ID.json" .event)" "result event"
e2e_expect_equal 666 "$(la_cents "$LA_J/results/$LA_ID.json" .charged_usd)" "charged in cents"
e2e_expect_equal limit_plus_turn "$(la_jq "$LA_J/results/$LA_ID.json" .charge_basis)" "basis"
e2e_expect_equal 1 "$(find "$LA_J/pending" -name '*-stage_failed.json' | wc -l | tr -d ' ')" "pending stage_failed events"
fi

# ---------------------------------------------------------------- LA25
if la_run LA25; then
fe_new la25-apply-retried-after-pending-fails
# Source: plan 2.4 (the launcher's report: result, charge, charge event and
# the pending stage event, each once). A retry after a failure part way
# finishes the steps not done and repeats none.
e2e_describe "the launcher's apply, run twice in one process, with store_pending failing on the first try only (after job.json was charged)"
la_seed
la_plugin 'RUN: true'
fe_py "import json
from decimal import Decimal
import _flow_factory_jobs as jobs
import _flow_factory_launch as L
ln = L.Launcher('$LA_F', '$LA_ID')
ln.directive = json.load(open(L._directive_path(ln.paths, 7, '$LA_ID')))
ln.job = jobs.read_job(ln.paths, 7)
L._real_dir(ln.rdir)
record = {'directive': '$LA_ID', 'outcome': 'completed', 'written_at': '2026-11-18T00:00:00Z',
          'event': 'stage_succeeded', 'session_id': None, 'num_turns': 1, 'api_error_status': None,
          'is_error': False, 'permission_denials': None, 'terminal_reason': None, 'charged_usd': 0.05,
          'charge_basis': 'first_total', 'total_cost_usd': 0.05, 'since_last_usd': None}
charge = {'charged_usd': Decimal('0.05'), 'basis': 'first_total', 'total_cost_usd': Decimal('0.05'),
          'since_last_usd': None}
real, calls = jobs.store_pending, [0]
def flaky(*a, **k):
    calls[0] += 1
    if calls[0] == 1:
        raise jobs.Refused('pending_unwritable injected')
    return real(*a, **k)
jobs.store_pending = flaky
try:
    ln.apply(record, charge, None, None, 'stage_succeeded', 'completed')
    print('first try: applied')
except jobs.Refused as e:
    print('first try: refused %s' % e)
ln.apply(record, charge, None, None, 'stage_succeeded', 'completed')
print('second try: applied')"
e2e_expect_equal 0 "$E2E_RC" "the driver's exit status ($E2E_ERR)"
e2e_expect_line "first try: refused pending_unwritable injected"
e2e_expect_line "second try: applied"
e2e_expect_equal 1 "$(find "$LA_J/pending" -name '*-stage_succeeded.json' 2>/dev/null | wc -l | tr -d ' ')" "pending stage_succeeded events"
e2e_expect_equal 1 "$(la_jq "$LA_J/job.json" '.cost.runs | length')" "runs charged in job.json"
e2e_expect_equal 5 "$(la_cents "$LA_J/job.json" .cost.usd_total)" "job cost in cents"
e2e_expect_equal 1 "$(grep -c '"type": *"charge"' "$LA_J/events.jsonl" 2>/dev/null)" "charge events"
fi

# ---------------------------------------------------------------- reaping
fe_new la-no-launcher-left
e2e_describe "after every scenario: no launcher whose factory directory lies under this file's scratch root still runs"
LA_ROOT_NAME=$(basename "$E2E_ROOT")
LA_LEFT=$(/bin/ps -A -ww -o pid=,command= | grep -F '_flow_factory_launch.py --factory-dir' | grep -F "$LA_ROOT_NAME" | grep -v grep || true)
e2e_expect_equal "" "$LA_LEFT" "launchers still running"
