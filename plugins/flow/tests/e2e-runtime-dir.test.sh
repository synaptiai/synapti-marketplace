# shellcheck shell=bash
# End-to-end: flow.runtime.stateDir names the runtime directory, the place
# flow keeps its goals, runs, triggers and watch state, and every reader and
# writer of that state uses it.
#
# bin/flow-runtime-dir.sh prints the directory for shell callers and
# runtime_dir() in bin/_repo_dir.py gives it to Python callers. The scenarios
# set flow.runtime.stateDir in the scratch repository's
# .claude/settings.flow.json and run the real resolver, writers, hooks and
# command blocks there.
#
# Ways it can be wrong, written down before the scenarios:
#   D1 the default is not .flow, or the resolver prints a warning when nothing
#      is set
#   D2 a valid nested value (build/flow-runtime) is ignored, or printed
#      unnormalized (./build//flow-runtime/), so a caller's prefix test or
#      path join misses it
#   D3 a value the rule refuses is used: an absolute path (even one inside the
#      repository), one starting with ~, a `..` component (including one
#      that cancels out by its text, build/../x, which the kernel follows
#      through build), one through a symlink inside the repository, one whose
#      symlink leads outside the repository, or the repository top itself
#   D4 a refused value prints no warning, more than one line, a line that
#      does not name the setting, or a line naming where the value leads
#   D5 a refused value falls back to something other than .flow
#   D6 the shell resolver and runtime_dir() disagree on a value
#   D7 a value from the user's settings is not read (any layer may set it)
#   D8 a writer or reader keeps using .flow when the setting names another
#      directory, so state is written where flow does not read it, or read
#      from where it was not written
#   D9 a hook resolves the runtime directory more than once per run (each
#      bin script it calls asking again)

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

RT=build/flow-runtime

_settings() { mkdir -p "$E2E_REPO/.claude"; printf '%s\n' "$1" > "$E2E_REPO/.claude/settings.flow.json"; }
_state_dir() { _settings "{\"flow\":{\"runtime\":{\"stateDir\":$1}}}"; }

# _err_lines — how many lines the last run printed on stderr.
_err_lines() { if [ -z "$E2E_ERR" ]; then echo 0; else printf '%s\n' "$E2E_ERR" | wc -l | tr -d ' '; fi; }

# _py_runtime_dir — runtime_dir() from bin/_repo_dir.py, run in the scratch
# repository as a Python caller runs it. Sets E2E_OUT, E2E_ERR, E2E_RC.
_py_runtime_dir() {
  printf 'code: bin/_repo_dir.py runtime_dir()\n' | _e2e_art
  _e2e_exec python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from _repo_dir import runtime_dir; print(runtime_dir())' "$E2E_ACTIVE_PLUGIN/bin"
  printf -- '--- expectations\n' | _e2e_art
}

# _no_default_dir — nothing was written under .flow in the scratch repository.
_no_default_dir() {
  e2e_expect_equal no "$([ -e "$E2E_REPO/.flow" ] && echo yes || echo no)" ".flow exists in the repository"
}

_flow_test_begin "flow-runtime-dir: the default is .flow, with no warning (D1)"
e2e_new runtime-dir-default
e2e_describe "no flow.runtime.stateDir in any settings file"
e2e_repo feature/issue-1-runtime-dir
e2e_run_bin bin/flow-runtime-dir.sh
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_equal .flow "$E2E_OUT" "the directory"
e2e_expect_equal "" "$E2E_ERR" "stderr"

_flow_test_begin "flow-runtime-dir: a nested relative value is used, normalized (D2, D6)"
for v in "$RT" "./build//flow-runtime/" "build/./flow-runtime"; do
  e2e_new "runtime-dir-valid-$(printf '%s' "$v" | tr -c 'a-z0-9' '_')"
  e2e_describe "flow.runtime.stateDir '$v' in the project settings; build/ does not exist yet"
  e2e_repo feature/issue-1-runtime-dir
  _state_dir "\"$v\""
  e2e_run_bin bin/flow-runtime-dir.sh
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal "$RT" "$E2E_OUT" "the directory"
  e2e_expect_equal "" "$E2E_ERR" "stderr"
  sh_out="$E2E_OUT"
  _py_runtime_dir
  e2e_expect_equal "$sh_out" "$E2E_OUT" "runtime_dir() beside flow-runtime-dir.sh"
  e2e_expect_equal "" "$E2E_ERR" "runtime_dir()'s stderr"
  _no_default_dir
done

_flow_test_begin "flow-runtime-dir: a value in the user's settings is used (D7)"
e2e_new runtime-dir-user
e2e_describe "flow.runtime.stateDir build/flow-runtime in the user's settings only"
e2e_repo feature/issue-1-runtime-dir
e2e_user_settings "{\"flow\":{\"runtime\":{\"stateDir\":\"$RT\"}}}"
e2e_run_bin bin/flow-runtime-dir.sh
e2e_expect_equal "$RT" "$E2E_OUT" "the directory"

_flow_test_begin "flow-runtime-dir: a refused value prints one warning naming the setting and .flow is used (D3, D4, D5, D6)"
# name|value (a JSON string)|what stderr must say|setup
_refused() {
  local name="$1" value="$2" reason="$3" setup="$4"
  e2e_new "runtime-dir-refused-$name"
  e2e_describe "flow.runtime.stateDir $value: $reason"
  e2e_repo feature/issue-1-runtime-dir
  mkdir -p "$E2E_DIR/elsewhere"
  case "$setup" in
    link-inside) mkdir -p "$E2E_REPO/real"; ln -s real "$E2E_REPO/build" ;;
    link-outside) ln -s "$E2E_DIR/elsewhere" "$E2E_REPO/build" ;;
    build) mkdir -p "$E2E_REPO/build" "$E2E_REPO/x" ;;
  esac
  _state_dir "$value"
  e2e_run_bin bin/flow-runtime-dir.sh
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal .flow "$E2E_OUT" "the directory"
  e2e_expect_equal 1 "$(_err_lines)" "the number of stderr lines"
  e2e_expect_err "refusing flow.runtime.stateDir: $reason"
  e2e_expect_err "using .flow"
  e2e_expect_err_lacks "$E2E_DIR"
  e2e_expect_err_lacks "elsewhere"
  e2e_expect_err_lacks "/real"
  local sh_out="$E2E_OUT" sh_err="$E2E_ERR"
  _py_runtime_dir
  e2e_expect_equal "$sh_out" "$E2E_OUT" "runtime_dir() beside flow-runtime-dir.sh"
  e2e_expect_equal "$sh_err" "$E2E_ERR" "runtime_dir()'s warning beside flow-runtime-dir.sh's"
}
_refused absolute-inside "\"$E2E_ROOT/runtime-dir-refused-absolute-inside/repo/$RT\"" "it is an absolute path" ""
_refused absolute-outside '"/tmp/flow-runtime"' "it is an absolute path" ""
_refused tilde '"~/flow-runtime"' "it starts with ~" ""
_refused dotdot-out '"../flow-runtime"' "it has a .. component" ""
_refused dotdot-cancels '"build/../x"' "it has a .. component" build
_refused link-inside "\"$RT\"" "build is a symlink" link-inside
_refused link-outside "\"$RT\"" "build is a symlink" link-outside
_refused top '"."' "it names the repository top itself" ""

# --- writers and readers in bin/ (D8) -------------------------------------

GOAL_FIXTURE="$REPO_ROOT/plugins/flow/tests/fixtures/goal/valid.yaml"
ACTIVITY_FIXTURE="$REPO_ROOT/plugins/flow/tests/fixtures/activity/valid.yaml"
RUN_ID=2026-05-20T143000Z-issue-42

_flow_test_begin "flow-goal-record --create writes the goal under the runtime directory; flow-active-goal reads it there (D8)"
e2e_new runtime-dir-goal-record
e2e_describe "flow.runtime.stateDir build/flow-runtime; create goal issue-42 on its branch, then look it up"
e2e_repo feature/issue-42-search-fix
_state_dir "\"$RT\""
e2e_run_bin bin/flow-goal-record.sh --create --goal-file "$GOAL_FIXTURE"
e2e_expect_equal 0 "$E2E_RC" "flow-goal-record's exit status"
e2e_expect_equal yes "$([ -f "$E2E_REPO/$RT/goals/issue-42.goal.yaml" ] && echo yes || echo no)" "$RT/goals/issue-42.goal.yaml exists"
e2e_run_bin bin/flow-active-goal.sh --path
e2e_expect_equal 0 "$E2E_RC" "flow-active-goal's exit status"
e2e_expect_equal "$RT/goals/issue-42.goal.yaml" "$E2E_OUT" "the active goal's path"
e2e_run_bin bin/flow-active-goal.sh --id --runtime-dir "$RT"
e2e_expect_equal issue-42 "$E2E_OUT" "the active goal's id with --runtime-dir"
_no_default_dir

_flow_test_begin "flow-active-goal: a goal under .flow is not read when the setting names another directory (D8)"
e2e_new runtime-dir-goal-elsewhere
e2e_describe "flow.runtime.stateDir build/flow-runtime; an active goal only under .flow/goals"
e2e_repo feature/issue-42-search-fix
_state_dir "\"$RT\""
e2e_goal issue-42 feature/issue-42-search-fix active "true"
e2e_run_bin bin/flow-active-goal.sh --id
e2e_expect_equal 1 "$E2E_RC" "flow-active-goal's exit status (no goal)"
e2e_expect_equal "" "$E2E_OUT" "stdout"

_flow_test_begin "flow-record-activity writes the run under the runtime directory (D8)"
e2e_new runtime-dir-record-activity
e2e_describe "flow.runtime.stateDir build/flow-runtime; record activity task-ac1 for run $RUN_ID"
e2e_repo feature/issue-42-search-fix
_state_dir "\"$RT\""
e2e_run_bin bin/flow-record-activity.sh --run-id "$RUN_ID" --activity-file "$ACTIVITY_FIXTURE"
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_equal yes "$([ -f "$E2E_REPO/$RT/runs/$RUN_ID/activities/001-task-ac1.yaml" ] && echo yes || echo no)" "the activity under $RT/runs"
e2e_expect_file_has "$RT/runs/$RUN_ID/events.jsonl" 'activity_recorded'
_no_default_dir

_flow_test_begin "flow-record-activity: a symlink inside the runtime directory is refused as under .flow (D8)"
e2e_new runtime-dir-record-activity-link
e2e_describe "flow.runtime.stateDir build/flow-runtime, whose runs is a symlink to a directory outside the repository"
e2e_repo feature/issue-42-search-fix
_state_dir "\"$RT\""
mkdir -p "$E2E_REPO/$RT" "$E2E_DIR/outside-runs"
ln -s "$E2E_DIR/outside-runs" "$E2E_REPO/$RT/runs"
e2e_run_bin bin/flow-record-activity.sh --run-id "$RUN_ID" --activity-file "$ACTIVITY_FIXTURE"
e2e_expect_equal 2 "$E2E_RC" "the exit status"
e2e_expect_err "$RT/runs is a symlink"
e2e_expect_equal 0 "$(find "$E2E_DIR/outside-runs" -type f | wc -l | tr -d ' ')" "files written outside the repository"

_flow_test_begin "flow-watch-create (issue) writes the trigger and the watch folder under the runtime directory (D8)"
e2e_new runtime-dir-watch-issue
e2e_describe "flow.runtime.stateDir build/flow-runtime, its triggers folder made by the pre-flight; issue 7"
e2e_repo feature/issue-7-watch
_state_dir "\"$RT\""
mkdir -p "$E2E_REPO/$RT/triggers"
e2e_run_bin bin/flow-watch-create.sh --kind issue --repo o/r --now 2026-01-01T00:00:00Z --issue 7
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "TRIGGER_FILE=$RT/triggers/issue-7-watch.trigger.yaml"
e2e_expect_equal yes "$([ -f "$E2E_REPO/$RT/watch/.gitignore" ] && echo yes || echo no)" "$RT/watch/.gitignore exists"
e2e_expect_file_has .claude/flow-loop-issue-7-watch.md "\`$RT/watch/issue-7.json\`"
e2e_expect_file_lacks .claude/flow-loop-issue-7-watch.md ".flow/"
e2e_run_bin bin/flow-trigger-concurrency.sh issue-7-watch
e2e_expect_equal 0 "$E2E_RC" "flow-trigger-concurrency's exit status"
e2e_expect_line "POLICY_SOURCE=trigger"
_no_default_dir

# --- hooks (D8) --------------------------------------------------------------

STOP_PAYLOAD='{"session_id":"e2e-runtime-dir","stop_hook_active":false}'

# _goal_at <dir> — the fixture goal issue-42 (active, branch
# feature/issue-42-search-fix) under <dir>/goals in the scratch repository.
_goal_at() {
  mkdir -p "$E2E_REPO/$1/goals"
  cp "$GOAL_FIXTURE" "$E2E_REPO/$1/goals/issue-42.goal.yaml"
}

_flow_test_begin "Stop hook: the active goal is found under the runtime directory (D8)"
e2e_new runtime-dir-stop-hook
e2e_describe "flow.runtime.stateDir build/flow-runtime; active goal issue-42 under it; stopHookEnforcement warn"
e2e_repo feature/issue-42-search-fix
_state_dir "\"$RT\""
_goal_at "$RT"
e2e_run_hook hooks/scripts/flow-goal-stop.sh "$STOP_PAYLOAD"
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_out "Active goal: issue-42"
e2e_expect_no_out "no active flow goal"
_no_default_dir

_flow_test_begin "Stop hook: a goal under .flow is not read when the setting names another directory (D8)"
e2e_new runtime-dir-stop-hook-elsewhere
e2e_describe "flow.runtime.stateDir build/flow-runtime; active goal issue-42 only under .flow/goals"
e2e_repo feature/issue-42-search-fix
_state_dir "\"$RT\""
_goal_at .flow
e2e_run_hook hooks/scripts/flow-goal-stop.sh "$STOP_PAYLOAD"
e2e_expect_line '{"decision":"approve","reason":"no active flow goal"}'

_flow_test_begin "SessionEnd: runs under the runtime directory get session_end and old ended runs are removed (D8)"
e2e_new runtime-dir-session-end
e2e_describe "flow.runtime.stateDir build/flow-runtime; an active run, and a completed run 40 days old, under it"
e2e_repo feature/issue-42-search-fix
_state_dir "\"$RT\""
for r in active-run:active old-run:completed; do
  id=${r%%:*}; st=${r#*:}
  mkdir -p "$E2E_REPO/$RT/runs/$id"
  printf 'apiVersion: flow.synapti.ai/v1\nkind: FlowRun\nmetadata:\n  id: %s\n  workflow: start-issue\nstate:\n  status: %s\n' "$id" "$st" > "$E2E_REPO/$RT/runs/$id/run.yaml"
done
python3 -c 'import os, sys, time; t = time.time() - 40 * 86400; os.utime(sys.argv[1], (t, t))' "$E2E_REPO/$RT/runs/old-run/run.yaml"
e2e_run_hook hooks/scripts/session-end-state.sh '{"session_id":"e2e-runtime-dir"}'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_file_has "$RT/runs/active-run/events.jsonl" session_end
e2e_expect_equal removed "$([ -e "$E2E_REPO/$RT/runs/old-run" ] && echo kept || echo removed)" "the completed run 40 days old"
_no_default_dir

# --- command and skill blocks (D8) -------------------------------------------

_flow_test_begin "run-state-management: the run directory is created under the runtime directory (D8)"
e2e_new runtime-dir-run-create
e2e_describe "flow.runtime.stateDir build/flow-runtime; the skill's run directory block for run r-1"
e2e_repo feature/issue-42-search-fix
_state_dir "\"$RT\""
e2e_run_block RUN_ID=r-1 skills/run-state-management/SKILL.md RUN_DIR_CREATE_BLOCK
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "RUNTIME_DIR=$RT"
e2e_expect_line "RUN_DIR=$RT/runs/r-1"
e2e_expect_equal yes "$([ -d "$E2E_REPO/$RT/runs/r-1" ] && echo yes || echo no)" "$RT/runs/r-1 exists"
_no_default_dir

_flow_test_begin "/flow:watch pre-flight creates the triggers folder under the runtime directory (D8)"
e2e_new runtime-dir-watch-preflight
e2e_describe "flow.runtime.stateDir build/flow-runtime; the /flow:watch pre-flight block"
e2e_repo feature/issue-7-watch
_state_dir "\"$RT\""
e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/watch.md" '"$RT/triggers"'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "RUNTIME_DIR=$RT"
e2e_expect_equal yes "$([ -d "$E2E_REPO/$RT/triggers" ] && echo yes || echo no)" "$RT/triggers exists"
_no_default_dir

_flow_test_begin "/flow:status: recent runs and triggers are read from the runtime directory (D8)"
e2e_new runtime-dir-status
e2e_describe "flow.runtime.stateDir build/flow-runtime; one run and one trigger under it"
e2e_repo feature/issue-7-watch
_state_dir "\"$RT\""
mkdir -p "$E2E_REPO/$RT/runs/r-1" "$E2E_REPO/$RT/triggers"
printf 'apiVersion: flow.synapti.ai/v1\nkind: FlowRun\nmetadata:\n  id: r-1\n  workflow: start-issue\nstate:\n  status: active\n' > "$E2E_REPO/$RT/runs/r-1/run.yaml"
e2e_run_bin bin/flow-watch-create.sh --kind issue --repo o/r --now 2026-01-01T00:00:00Z --issue 7
e2e_run_block commands/status.md RECENT_RUNS_BLOCK
e2e_expect_line "STATE=ok"
e2e_expect_out "r-1"
e2e_run_block commands/status.md TRIGGERS_BLOCK
e2e_expect_line "STATE=ok"
e2e_expect_out "issue-7-watch"
_no_default_dir

_flow_test_begin "/flow:resume and /flow:goal read runs and goals from the runtime directory (D8)"
e2e_new runtime-dir-resume-goal
e2e_describe "flow.runtime.stateDir build/flow-runtime; an active run and the active goal issue-42 under it"
e2e_repo feature/issue-42-search-fix
_state_dir "\"$RT\""
mkdir -p "$E2E_REPO/$RT/runs/r-1"
printf 'apiVersion: flow.synapti.ai/v1\nkind: FlowRun\nmetadata:\n  id: r-1\n  workflow: start-issue\nstate:\n  status: active\n' > "$E2E_REPO/$RT/runs/r-1/run.yaml"
_goal_at "$RT"
e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'No FlowRuns exist'
e2e_expect_line "RUNTIME_DIR=$RT"
e2e_expect_no_out "No FlowRuns exist"
e2e_run_block commands/resume.md RESUME_SCAN_BLOCK
e2e_expect_line "RUN_ID=r-1"
e2e_run_block commands/goal.md GOAL_SCAN_BLOCK
e2e_expect_line "STATE=ok"
e2e_expect_line "ACTIVE_GOAL=$RT/goals/issue-42.goal.yaml"
e2e_expect_line "RUNTIME_DIR=$RT"
_no_default_dir

_flow_test_begin "/flow:setup ignores the watch folder of the runtime directory (D8)"
e2e_new runtime-dir-setup-ignore
e2e_describe "flow.runtime.stateDir build/flow-runtime; the /flow:setup ignore block"
e2e_repo feature/issue-7-watch
_state_dir "\"$RT\""
e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/setup.md" 'for IGNORE in'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_file_has .gitignore "$RT/watch/"
e2e_expect_file_lacks .gitignore ".flow/watch/"

# --- one resolver call per hook run (D9) -------------------------------------

_flow_test_begin "Stop hook with System One: records go to the run under the runtime directory, resolved once (D8, D9)"
e2e_new runtime-dir-stop-s1
e2e_describe "flow.runtime.stateDir build/flow-runtime; trusted goal with run run-e2e and evidence for AC2; goal.warn-evidence on against a stub; the resolver counts its calls"
e2e_repo feature/issue-42-search-fix
e2e_plugin_copy bin/flow-runtime-dir.sh '#!/usr/bin/env bash
printf "call\n" >> "$E2E_DIR/resolver-calls"
exec "$(dirname "$0")/flow-runtime-dir-real.sh" "$@"'
cp "$E2E_PLUGIN_DIR/bin/flow-runtime-dir.sh" "$E2E_ACTIVE_PLUGIN/bin/flow-runtime-dir-real.sh"
_state_dir "\"$RT\""
python3 - "$GOAL_FIXTURE" "$E2E_DIR/goal.yaml" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding="utf-8") as f:
    g = yaml.safe_load(f)
g["scope"]["run_id"] = "run-e2e"
g["objective"]["acceptance_criteria"] = [{"id": "AC2", "text": "The search results read well.", "must_pass": True,
    "status": "pending", "evidence_ref": None, "last_evaluated_at": None, "last_result": None}]
with open(sys.argv[2], "w", encoding="utf-8") as f:
    yaml.safe_dump(g, f, sort_keys=False)
PY
e2e_run_bin bin/flow-goal-record.sh --create --goal-file "$E2E_DIR/goal.yaml"
cat > "$E2E_DIR/ev.yaml" <<'YAML'
apiVersion: flow.synapti.ai/v1
kind: FlowEvidence
metadata:
  id: ev-ac2
  goal: issue-42
  run_id: run-e2e
  created_at: '2026-10-01T10:00:00Z'
evidence:
  type: command_result
  command: 'bash tests/check-AC2.sh'
  exit_code: 0
  proves:
    - AC2
  limitations:
    - 'checks only the default locale'
YAML
printf 'ok: AC2 holds\n' > "$E2E_DIR/ev.out"
e2e_run_bin bin/flow-record-evidence.sh --run-id run-e2e --evidence-file "$E2E_DIR/ev.yaml" --raw-output "$E2E_DIR/ev.out"
e2e_expect_equal 0 "$E2E_RC" "flow-record-evidence's exit status"
e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"evidence_supports":{"type":"noul","noul":0.99}}}}'
e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,timeoutMs:3000,uses:{"goal.warn-evidence":"on"}}}')"
: > "$E2E_DIR/resolver-calls"
e2e_run_hook hooks/scripts/flow-goal-stop.sh "$STOP_PAYLOAD"
e2e_expect_equal 0 "$E2E_RC" "the hook's exit status"
e2e_expect_equal yes "$([ -s "$E2E_REPO/$RT/runs/run-e2e/system-one.jsonl" ] && echo yes || echo no)" "$RT/runs/run-e2e/system-one.jsonl written"
e2e_expect_equal 1 "$(wc -l < "$E2E_DIR/resolver-calls" | tr -d ' ')" "resolver calls during the Stop hook run"
_no_default_dir
