# shellcheck shell=bash
# The person subcommands, rebuild, status and context --mode
# (bin/_flow_factory_person.py, plan 1a T12). Every scenario runs the shipped
# wrapper; the `next` passes that apply a stored person event, or that build
# the live job PS13 compares with its rebuild, run through the test entry
# point (E, fe_e) with the ordinary seam fixture.
#
# Terminal and session rule: a person subcommand whose result depends on the
# confirmation runs under fe_person_terminal (a terminal, no `claude`
# ancestor) or fe_detached (no terminal, no `claude` ancestor), never straight
# from the test, which may itself have a terminal and a `claude` ancestor when
# the suite runs from Claude Code. PS7(a), (b) and (d) set CLAUDECODE=1, so
# they are inside a session wherever they run; PS7(e) runs under a terminal
# below a process named claude. Scenarios that stop before the confirmation
# (exit 2, 3, 5 or the disabled line) may run from the test.
#
# Ways it can be wrong, written down before the checks:
#   PS1  rebuild does not restore the state, or the cost, from the log (AC10)
#   PS2  rebuild acts without a confirmation (row 69h)
#   PS3  rebuild accepts an illegal recorded move (AC3), or changes job.json
#        when it refuses
#   PS4  a person event in a state where it does not occur is accepted
#   PS5  the checks run in the wrong order: the confirmation before occurs_in,
#        the job lookup before the argument parsing; an unknown or unreadable
#        job is not refused
#   PS6  a person subcommand moves the job itself instead of storing its
#        event, or stores it without its channel and facts (coverage 2)
#   PS7  answer --text from a session acts; answer --choice from a session is
#        refused; an always-ask subcommand from a session acts; a process with
#        no terminal confirms; a `claude` ancestor is not seen (conflicts 2)
#   PS8  a waiting tty prompt holds a lock, so next waits on it (A+7)
#   PS9  status misses a job or a status line (AC10, C.5), prints a dead
#        orphan group, or --json and --brief disagree with the text form
#   PS10 context --mode gives on with a failed check, or invalid with every
#        check holding
#   PS11 the enabled gate covers the wrong subcommands (A.3)
#   PS12 status from a worker's clone reads the clone's own factory folder
#   PS13 a rebuilt job differs from the live one it replaces: a field a
#        row's effect wrote (reason), the slot, the directive, the relaunch,
#        the sessions or the charges; or a rebuild between a result and the
#        next pass loses the result; or a rebuild loses orphan_groups,
#        snapshots or pending_changes, so a job held by a live orphan group
#        (row 43g) is launched again, or keeps the first of several logged
#        values instead of the last
#   PS14 a wrong word typed at the prompt confirms
#
# PS_ONLY=<id> (PS1 ... PS14) runs only that scenario.

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}
# shellcheck source=lib/factory-e2e.sh
source "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh"

ps_run() { [ -z "${PS_ONLY:-}" ] || [ "$PS_ONLY" = "$1" ]; }

PS_T0="2026-11-16T00:00:00Z"
PS_CALLER='{"pid":4242,"start":"Mon Nov 16 00:00:00 2026","ancestry":[4242,1]}'
PS_DISABLED="FACTORY_REFUSED=disabled next: set flow.factory.enabled"
PS_FAIL_RESULT='{"type":"result","subtype":"error_during_execution","is_error":true,"num_turns":1,"total_cost_usd":0.05}'
PS_OK_RESULT='{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.05}'
D1=issue-7-j1-build-1
D2=issue-7-j1-build-2
D3=issue-7-j1-build-3

# ps_seed — the main checkout, a probe record, F, J of issue 7 and the wrapper.
ps_seed() {
  e2e_repo main
  fe_record "${PS_RECORD_EDITS:-}"
  PS_F=$(fe_factory_dir)
  PS_J="$PS_F/jobs/issue-7"
  ps_w
}
# ps_w — the wrapper of the active plugin (again after e2e_plugin_copy).
ps_w() { PS_W="$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh"; }
ps_jq() { jq -r "$2" "$1" 2>/dev/null; }
ps_cents() { jq -r "($2) * 100 | round" "$1" 2>/dev/null; }
# ps_ev <json line> [n] — append a line to job issue-<n>'s events.jsonl.
ps_ev() {
  mkdir -p "$PS_F/jobs/issue-${2:-7}"
  printf '%s\n' "$1" >> "$PS_F/jobs/issue-${2:-7}/events.jsonl"
}
# ps_record <n> <state> — a new job's job.json as next writes it at creation.
ps_record() {
  jq -nc --argjson n "$1" --arg s "$2" --arg t "$PS_T0" '{apiVersion: "flow.synapti.ai/v1", kind: "FlowFactoryJob",
    key: "issue-\($n)-j1", issue: $n, state: $s, attempt: 0, stage_launches: {}, sessions: {}, holds_slot: false,
    directive: null, cost: {usd_total: 0, runs: [], stage_usd: {}, dearest_turn_usd: 0}, created_at: $t,
    updated_at: $t, vouch_at: null}'
}
# ps_created <record json> [to] — the created line (plan 2.5) of row 1.
ps_created() {
  jq -nc --argjson r "$1" --arg to "${2:-queued}" --arg t "$PS_T0" --argjson c "$PS_CALLER" '{type: "created",
    job: $r.key, time: $t, pass: "p1", row: "1", event: "issue_labelled", from: null, to: $to, stay: false,
    effects_applied: ["set vouch_at = the label event time", "write job.json", "no baseline_digest yet"],
    effects_deferred: [], attempt: 0, channel: "engine", caller: $c, record: $r}'
}
# ps_trans <pass> <event> <from> <row> <to, or - for a stay> [effects_applied] [effects_deferred] [n]
ps_trans() {
  jq -nc --arg p "$1" --arg e "$2" --arg f "$3" --arg r "$4" --arg to "$5" --argjson ea "${6:-[]}" \
    --argjson ed "${7:-[]}" --arg job "issue-${8:-7}-j1" '{type: "transition", job: $job,
    time: "2026-11-16T00:10:00Z", pass: $p, event: $e, from: $f, row: $r, to: (if $to == "-" then null else $to end),
    stay: ($to == "-"), effects_applied: $ea, effects_deferred: $ed, attempt: 0, channel: "engine", caller: null,
    records: {}}'
}
# ps_log_prepare — PS1's hand-written log: created -> queued (row 1), queued ->
# intake (row 2, sync_tick), intake -> prepare (row 6, judge_accept).
ps_log_prepare() {
  ps_ev "$(ps_created "$(ps_record 7 queued)")"
  ps_ev "$(ps_trans p2 sync_tick queued 2 intake '[]' '[{"effect":"set baseline_pending","phase":"1b"}]')"
  ps_ev "$(ps_trans p3 judge_accept intake 6 prepare '[]' \
    '[{"effect":"record intake_inputs (its only writer), risk, surfaces and scope","phase":"1b"},{"effect":"post the intake notice","phase":"1b"}]')"
}
# ps_pending_count [n] — pending event files of job issue-<n>.
ps_pending_count() { find "$PS_F/jobs/issue-${1:-7}/pending" -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }
ps_rows() { jq -r 'select(.type == "transition") | .row' "$PS_F/jobs/issue-${1:-7}/events.jsonl" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
ps_settings() {
  local f="$E2E_HOME/.claude/settings.flow.json" cur='{}'
  [ -f "$f" ] && cur=$(cat "$f")
  e2e_user_settings "$(printf '%s' "$cur" | jq -c "$1")"
}
ps_now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
ps_le() { perl -e 'exit(($ARGV[1] - $ARGV[0] <= $ARGV[2]) ? 0 : 1)' "$1" "$2" "$3" && echo yes || echo "no ($(perl -e 'printf "%.2f", $ARGV[1] - $ARGV[0]' "$1" "$2") s)"; }
ps_wait_result() { fe_wait_for "${2:-45}" "[ -f '$PS_J/results/$1.json' ]"; }
ps_wait_launcher_gone() {
  local lp
  lp=$(jq -r '.launcher_pid // empty' "$PS_J/directives/$1.lease.json" 2>/dev/null)
  [ -n "$lp" ] && fe_wait_for 15 "! kill -0 $lp 2>/dev/null"
}
ps_finish() { ps_wait_result "$1" && ps_wait_launcher_gone "$1"; }
ps_valid() {
  fe_py "import _flow_factory_jobs as j
p = j.resolve(create=False)
r = j.read_job(p, ${1:-7})
print(type(r).__name__, getattr(r, 'reason', ''))"
  printf '%s' "$E2E_OUT"
}
# ps_mask_sids [n] — mask every session uuid in job issue-<n>'s job.json,
# directives and events as <sid k>, in the order they first appear.
ps_mask_sids() {
  local j="$PS_F/jobs/issue-${1:-7}" u k
  k=$(grep -c '<sid ' "$E2E_DIR/masks" 2>/dev/null) || k=0
  for u in $(cat "$j"/directives/*.json "$j/events.jsonl" "$j/job.json" 2>/dev/null \
      | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | awk '!seen[$0]++'); do
    grep -qF "$u" "$E2E_DIR/masks" 2>/dev/null && continue
    k=$((k + 1))
    fe_mask_text "$u" "<sid $k>"
  done
}
# ps_art_state [n] — job issue-<n>'s job.json, directives and leases, results,
# pending events and events.jsonl in the artifact, with the values that change
# from run to run (times, pids, start times, the host, the head, session ids,
# the pending sequence numbers) written as fixed tokens, so two runs give the
# same artifact.
ps_art_state() {
  local j="$PS_F/jobs/issue-${1:-7}" f
  local walk='walk(if type == "object" then with_entries(if (.key | test("^(time|at|raised_at|created_at|updated_at|heartbeat_at|started_at|revoked_at|written_at|recorded_at|launcher_pid|launcher_start|child_pid|child_pgid|child_start|pid|pgid|start|ancestry|head_sha|host)$")) and .value != null and .value != "'"$PS_T0"'" then .value = "<masked>" else . end) else . end)'
  ps_mask_sids "${1:-7}"
  {
    printf -- '--- state of job issue-%s (times, pids, start times, the host and the head masked)\n' "${1:-7}"
    for f in "$j/job.json" "$j"/directives/*.json "$j"/results/*.json; do
      [ -f "$f" ] || continue
      printf '%s:\n%s\n' "${f#"$j"/}" "$(jq -S "$walk" "$f" 2>/dev/null || cat "$f")"
    done
    for f in "$j"/pending/*.json; do
      [ -f "$f" ] || continue
      printf 'pending/<seq>-%s:\n%s\n' "${f##*/[0-9]*-}" "$(jq -S "$walk" "$f" 2>/dev/null)"
    done
    if [ -f "$j/events.jsonl" ]; then
      printf 'events.jsonl:\n%s\n' "$(jq -cS "$walk" "$j/events.jsonl" 2>/dev/null)"
    fi
  } | _e2e_art
}
# ps_sleeper — `sleep 60` in a session of its own, registered for cleanup; prints its pid.
ps_sleeper() {
  local pid
  pid=$(_fe_in_scratch "$(fe_python)" -I -c 'import subprocess; print(subprocess.Popen(["sleep", "60"], start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).pid)')
  _fe_register "$pid"
  printf '%s' "$pid"
}

# ---------------------------------------------------------------- PS1
if ps_run PS1; then
_flow_test_begin "person: rebuild restores the state and the cost from events.jsonl (PS1, AC10, T:68)"
fe_new ps1a-rebuild-state
# Source: the hand-written log (rows 1, 2, 6: the last move is intake -> prepare);
# T:68; T12 rebuild table (no charge line and no directive: cost 0, directive null,
# holds_slot false); plan 2.6 UNREADABLE line.
e2e_describe "job.json is '{'; events.jsonl: created -> queued, queued -> intake (row 2), intake -> prepare (row 6); status, then rebuild 7 in a terminal"
ps_seed
mkdir -p "$PS_J"
printf '{' > "$PS_J/job.json"
ps_log_prepare
e2e_run_bin bin/flow-factory.sh status
e2e_expect_equal 0 "$E2E_RC" "status exit status ($E2E_ERR)"
e2e_expect_line "UNREADABLE job=issue-7 next: flow-factory.sh rebuild 7"
fe_person_terminal issue-7-j1 "$PS_W" rebuild 7
e2e_expect_equal 0 "$E2E_RC" "rebuild exit status"
e2e_expect_line "REBUILT job=issue-7-j1 state=prepare"
e2e_expect_equal "dict " "$(ps_valid 7)" "job.json reads back as a valid job"
e2e_expect_equal "issue-7-j1 prepare 0 false null 0 0" "$(ps_jq "$PS_J/job.json" '"\(.key) \(.state) \(.attempt) \(.holds_slot) \(.directive) \(.cost.usd_total) \(.cost.runs | length)"')" "key, state, attempt, holds_slot, directive, usd_total, runs"
e2e_expect_equal "$PS_T0" "$(ps_jq "$PS_J/job.json" .created_at)" "created_at"
e2e_expect_equal "{" "$(cat "$PS_J/job.json.bak" 2>/dev/null)" "job.json.bak"
e2e_expect_equal "68 person_rebuild prepare true terminal" "$(jq -r 'select(.type == "rebuilt") | "\(.row) \(.event) \(.from) \(.stay) \(.channel)"' "$PS_J/events.jsonl" 2>/dev/null)" "the rebuilt event"
ps_art_state 7

fe_new ps1b-rebuild-cost
# Source: T12 rebuild table (cost.runs, usd_total, stage_usd from the charge
# lines; dearest_turn_usd from the last one); the hand-written charge line.
e2e_describe "as ps1a plus one charge line (intake, 0.30, dearest 0.12); rebuild 7 in a terminal"
ps_seed
mkdir -p "$PS_J"
printf '{' > "$PS_J/job.json"
ps_log_prepare
ps_ev '{"type":"charge","job":"issue-7-j1","time":"2026-11-16T00:05:00Z","pass":"p2","directive":"issue-7-j1-intake-1","stage":"intake","session_id":null,"charged_usd":0.30,"basis":"first_total","total_cost_usd":0.30,"since_last_usd":null,"dearest_turn_usd":0.12}'
fe_person_terminal issue-7-j1 "$PS_W" rebuild 7
e2e_expect_equal 0 "$E2E_RC" "rebuild exit status"
e2e_expect_line "REBUILT job=issue-7-j1 state=prepare"
e2e_expect_equal 30 "$(ps_cents "$PS_J/job.json" .cost.usd_total)" "cost.usd_total in cents"
e2e_expect_equal 30 "$(ps_cents "$PS_J/job.json" .cost.stage_usd.intake)" "cost.stage_usd.intake in cents"
e2e_expect_equal 12 "$(ps_cents "$PS_J/job.json" .cost.dearest_turn_usd)" "cost.dearest_turn_usd in cents"
e2e_expect_equal "1 30 first_total issue-7-j1-intake-1" "$(ps_jq "$PS_J/job.json" '"\(.cost.runs | length) \(.cost.runs[0].charged_usd * 100 | round) \(.cost.runs[0].basis) \(.cost.runs[0].directive)"')" "cost.runs"
e2e_expect_equal "{}" "$(ps_jq "$PS_J/job.json" '.sessions | tojson')" "sessions (the charge has no session)"
ps_art_state 7
fi

# ---------------------------------------------------------------- PS2
if ps_run PS2; then
_flow_test_begin "person: rebuild with no terminal and no claude ancestor needs a confirmation (PS2, T:69h, R23)"
fe_new ps2-rebuild-detached
# Source: T:69h; person_channels L42 (no controlling terminal: PERSON_CONFIRM_REQUIRED).
e2e_describe "PS1's log and job.json '{'; rebuild 7 run detached (setsid, parent pid 1)"
ps_seed
mkdir -p "$PS_J"
printf '{' > "$PS_J/job.json"
ps_log_prepare
cp "$PS_J/events.jsonl" "$E2E_DIR/events.before"
fe_detached "$PS_W" rebuild 7
e2e_expect_equal 4 "$E2E_RC" "exit status"
e2e_expect_equal "PERSON_CONFIRM_REQUIRED next: run flow-factory.sh rebuild 7 in a terminal" "$E2E_OUT" "stdout"
e2e_expect_equal "{" "$(cat "$PS_J/job.json")" "job.json"
e2e_expect_equal absent "$([ -e "$PS_J/job.json.bak" ] && echo present || echo absent)" "job.json.bak"
e2e_expect_equal same "$(cmp -s "$E2E_DIR/events.before" "$PS_J/events.jsonl" && echo same || echo changed)" "events.jsonl"
fi

# ---------------------------------------------------------------- PS3
if ps_run PS3; then
_flow_test_begin "person: rebuild refuses a recorded move the table has no row for (PS3, AC3)"
fe_new ps3-rebuild-off-table
# Source: plan 3.7(1); plan 2.6 (exit 3, TRANSITION_REFUSED=<from>-><to>: no row moves <from> to <to>).
e2e_describe "a valid job.json in queued; events: created -> queued, then a transition queued -> ready; rebuild 7 in a terminal"
ps_seed
fe_job 7 queued
ps_ev "$(ps_created "$(ps_record 7 queued)")"
ps_ev "$(ps_trans p2 sync_tick queued 2 ready)"
cp "$PS_J/job.json" "$E2E_DIR/job.before"
fe_person_terminal issue-7-j1 "$PS_W" rebuild 7
e2e_expect_equal 3 "$E2E_RC" "exit status"
e2e_expect_line "TRANSITION_REFUSED=queued->ready: no row moves queued to ready"
e2e_expect_no_line "REBUILT job=issue-7-j1 state=ready"
e2e_expect_equal same "$(cmp -s "$E2E_DIR/job.before" "$PS_J/job.json" && echo same || echo changed)" "job.json bytes"
e2e_expect_equal absent "$([ -e "$PS_J/job.json.bak" ] && echo present || echo absent)" "job.json.bak"
e2e_expect_equal 0 "$(jq -c 'select(.type == "rebuilt")' "$PS_J/events.jsonl" | wc -l | tr -d ' ')" "rebuilt events"
fi

# ---------------------------------------------------------------- PS4
if ps_run PS4; then
_flow_test_begin "person: a person event in a state where it does not occur exits 3 (PS4)"
fe_new ps4-event-refused
# Source: person_channels L15; transitions.json occurs_in (person_reject:
# needs_spec_approval, waiting_operator, needs_human; person_retry: needs_info,
# needs_human; neither holds ready).
e2e_describe "job 7 in ready; reject 7 and retry 7 in a terminal"
ps_seed
fe_enable
fe_job 7 ready
fe_person_terminal issue-7-j1 "$PS_W" reject 7
e2e_expect_equal 3 "$E2E_RC" "reject exit status"
e2e_expect_line "EVENT_REFUSED=person_reject state=ready"
e2e_expect_no_out "type the job key"
fe_person_terminal issue-7-j1 "$PS_W" retry 7
e2e_expect_equal 3 "$E2E_RC" "retry exit status"
e2e_expect_line "EVENT_REFUSED=person_retry state=ready"
e2e_expect_equal 0 "$(ps_pending_count)" "pending files"
e2e_expect_equal ready "$(ps_jq "$PS_J/job.json" .state)" "state"
fi

# ---------------------------------------------------------------- PS5
if ps_run PS5; then
_flow_test_begin "person: usage, the job lookup and occurs_in come before the confirmation (PS5, R1)"
fe_new ps5-order
# Source: plan 2.7 order of checks (argument parsing exit 2, job lookup exit 5,
# occurs_in exit 3, then the confirmation exit 4); plan 2.6 lines.
e2e_describe "job 7 in ready, job 8's job.json is '{'; from the test shell: reject 7, reject (no job), reject 9, cancel 8, cancel 7 --x"
ps_seed
fe_enable
fe_job 7 ready
mkdir -p "$PS_F/jobs/issue-8"
printf '{' > "$PS_F/jobs/issue-8/job.json"
e2e_run_bin bin/flow-factory.sh reject 7
e2e_expect_equal 3 "$E2E_RC" "reject 7 exit status"
e2e_expect_equal "EVENT_REFUSED=person_reject state=ready" "$E2E_OUT" "reject 7 stdout"
e2e_run_bin bin/flow-factory.sh reject
e2e_expect_equal 2 "$E2E_RC" "reject with no job: exit status"
e2e_expect_equal "" "$E2E_OUT" "reject with no job: stdout"
e2e_expect_equal 1 "$(printf '%s\n' "$E2E_ERR" | grep -c '^flow-factory.sh reject: ')" "reject with no job: usage lines on stderr"
e2e_expect_equal 1 "$(printf '%s\n' "$E2E_ERR" | grep -c .)" "reject with no job: stderr lines"
e2e_run_bin bin/flow-factory.sh cancel 7 --x
e2e_expect_equal 2 "$E2E_RC" "cancel 7 --x: exit status"
e2e_expect_equal "" "$E2E_OUT" "cancel 7 --x: stdout"
e2e_run_bin bin/flow-factory.sh reject 9
e2e_expect_equal 5 "$E2E_RC" "reject 9 exit status"
e2e_expect_equal "FACTORY_REFUSED=job_unknown job=9" "$E2E_OUT" "reject 9 stdout"
e2e_run_bin bin/flow-factory.sh cancel 8
e2e_expect_equal 5 "$E2E_RC" "cancel 8 exit status"
e2e_expect_equal "FACTORY_REFUSED=job_unreadable job=issue-8" "$E2E_OUT" "cancel 8 stdout"
e2e_run_bin bin/flow-factory.sh cancel issue-7-j2
e2e_expect_equal 5 "$E2E_RC" "cancel issue-7-j2 exit status"
e2e_expect_equal "FACTORY_REFUSED=job_unknown job=issue-7-j2" "$E2E_OUT" "cancel issue-7-j2 stdout (key of another job of the issue)"
e2e_run_bin bin/flow-factory.sh confirm i1
e2e_expect_equal 5 "$E2E_RC" "confirm i1 exit status"
e2e_expect_equal "FACTORY_REFUSED=intent_unknown intent=i1" "$E2E_OUT" "confirm i1 stdout"
e2e_run_bin bin/flow-factory.sh answer q9 --choice 1
e2e_expect_equal 5 "$E2E_RC" "answer q9 exit status"
e2e_expect_equal "FACTORY_REFUSED=question_unknown qid=q9" "$E2E_OUT" "answer q9 stdout"
e2e_expect_equal 0 "$(ps_pending_count)" "pending files"
fi

# ---------------------------------------------------------------- PS6
if ps_run PS6; then
_flow_test_begin "person: cancel stores its event and next applies it (PS6, coverage 2, T:53)"
fe_new ps6-cancel-stored
# Source: states_and_transitions L18; amendment C coverage 2; plan 2.4 pending
# event (channel terminal, facts unvouched_session_action false); T:53.
e2e_describe "job 7 in build; cancel 7 in a terminal; then next through E"
ps_seed
fe_enable
fe_job 7 build
fe_person_terminal issue-7-j1 "$PS_W" cancel 7
e2e_expect_equal 0 "$E2E_RC" "cancel exit status"
e2e_expect_line "RAISED person_cancel job=issue-7-j1"
e2e_expect_out "type the job key to confirm:"
e2e_expect_equal 1 "$(find "$PS_J/pending" -name '*-person_cancel.json' 2>/dev/null | wc -l | tr -d ' ')" "pending person_cancel files"
PS_P=$(find "$PS_J/pending" -name '*-person_cancel.json' 2>/dev/null | head -n 1)
e2e_expect_equal "person_cancel terminal false" "$(ps_jq "$PS_P" '"\(.event) \(.channel) \(.facts.unvouched_session_action)"')" "pending event, channel, fact"
e2e_expect_equal yes "$(ps_jq "$PS_P" '(.caller.pid | type) == "number" and (.caller.ancestry | length) >= 2' | sed 's/true/yes/')" "pending caller has a pid and an ancestry"
e2e_expect_equal build "$(ps_jq "$PS_J/job.json" .state)" "state before next"
e2e_expect_equal "" "$(ps_rows)" "rows before next"
fe_e ordinary.json next --executor headless
e2e_expect_equal 0 "$E2E_RC" "next exit status ($E2E_ERR)"
e2e_expect_equal 53 "$(ps_rows)" "rows after next"
e2e_expect_equal cancelled "$(ps_jq "$PS_J/job.json" .state)" "state after next"
e2e_expect_equal terminal "$(jq -r 'select(.type == "transition") | .channel' "$PS_J/events.jsonl")" "the transition's channel"
e2e_expect_equal 0 "$(ps_pending_count)" "pending files after next"
ps_art_state 7
fi

# ---------------------------------------------------------------- PS7
if ps_run PS7; then
_flow_test_begin "person: a session may answer by choice only; no terminal confirms nothing (PS7, conflicts 2)"
fe_new ps7-session-answer
# Source: person_channels L37-L42; amendment C conflicts 2 (answer --text inside
# a session: PERSON_CONFIRM_REQUIRED, outside the table); T:44 (person_answer
# in needs_human).
e2e_describe "job 7 in needs_human; questions/q1.json names it. (a) CLAUDECODE=1 answer q1 --choice 1 --text hi; (b) CLAUDECODE=1 answer q1 --choice 1; (c) answer q1 --choice 1 detached; (d) CLAUDECODE=1 cancel 7; (e) cancel 7 in a terminal below a process named claude"
ps_seed
fe_enable
fe_job 7 needs_human "d['reason'] = 'attempts_exhausted'; d['blocked_stage'] = 'build'"
mkdir -p "$PS_J/questions"
printf '{"job":"issue-7-j1"}\n' > "$PS_J/questions/q1.json"
e2e_run_bin CLAUDECODE=1 bin/flow-factory.sh answer q1 --choice 1 --text hi
e2e_expect_equal 4 "$E2E_RC" "(a) exit status"
e2e_expect_equal "PERSON_CONFIRM_REQUIRED next: run flow-factory.sh answer q1 --choice 1 --text hi in a terminal" "$E2E_OUT" "(a) stdout"
e2e_expect_equal 0 "$(ps_pending_count)" "(a) pending files"
e2e_run_bin CLAUDECODE=1 CLAUDE_SESSION_ID=s-ps7 bin/flow-factory.sh answer q1 --choice 1
e2e_expect_equal 0 "$E2E_RC" "(b) exit status ($E2E_ERR)"
e2e_expect_equal "RAISED person_answer job=issue-7-j1" "$E2E_OUT" "(b) stdout"
PS_P=$(find "$PS_J/pending" -name '*-person_answer.json' 2>/dev/null | head -n 1)
e2e_expect_equal "session:s-ps7 q1 1 false" "$(ps_jq "$PS_P" '"\(.channel) \(.args.qid) \(.args.choice) \(.facts.unvouched_session_action)"')" "(b) pending channel, args, fact"
rm -f "$PS_P"
fe_detached "$PS_W" answer q1 --choice 1
e2e_expect_equal 4 "$E2E_RC" "(c) exit status"
e2e_expect_equal "PERSON_CONFIRM_REQUIRED next: run flow-factory.sh answer q1 --choice 1 in a terminal" "$E2E_OUT" "(c) stdout"
e2e_expect_equal 0 "$(ps_pending_count)" "(c) pending files"
# The detached process's ancestors, as the engine's session test reads them.
fe_detached bash -c 'p=$$; while [ "$p" -gt 1 ]; do /bin/ps -ww -o command= -p "$p"; p=$(/bin/ps -o ppid= -p "$p" | tr -d " "); done'
PS_ANC=$(printf '%s\n' "$E2E_OUT" | awk 'NF { n = split($1, a, "/"); print a[n] }')
printf 'detached ancestry programs: %s\n' "$(printf '%s' "$PS_ANC" | tr '\n' ' ')" | _e2e_art
e2e_expect_equal 0 "$(printf '%s\n' "$PS_ANC" | grep -cx claude)" "(c) ancestors whose program is named claude"
e2e_run_bin CLAUDECODE=1 bin/flow-factory.sh cancel 7
e2e_expect_equal 4 "$E2E_RC" "(d) exit status"
e2e_expect_equal "PERSON_CONFIRM_REQUIRED next: run flow-factory.sh cancel 7 in a terminal" "$E2E_OUT" "(d) stdout"
mkdir -p "$E2E_DIR/fake-session"
ln -s /bin/bash "$E2E_DIR/fake-session/claude"
# Two commands, so bash does not exec the wrapper in its own place and stays
# its ancestor.
fe_person_terminal issue-7-j1 "$E2E_DIR/fake-session/claude" -c "$(printf '%q cancel 7; exit $?' "$PS_W")"
e2e_expect_equal 4 "$E2E_RC" "(e) exit status"
e2e_expect_line "PERSON_CONFIRM_REQUIRED next: run flow-factory.sh cancel 7 in a terminal"
e2e_expect_no_out "type the job key"
e2e_expect_equal 0 "$(ps_pending_count)" "(d), (e) pending files"
fi

# ---------------------------------------------------------------- PS8
if ps_run PS8; then
_flow_test_begin "person: a waiting tty prompt holds no lock; next launches meanwhile (PS8, A+7)"
ps8_seed() {
  ps_seed
  fe_enable
  fe_job 7 build
  fe_job_clone 7
  e2e_plugin_copy templates/factory/build.prompt.md 'RUN: true'
  ps_w
  ps_settings '.flow.factory.nextBudgetSeconds = 4'
  fe_worker_says "worker-result=$PS_OK_RESULT"
}
fe_new ps8a-prompt-holds-no-lock
# Source: amendment A+7 (next stays within its budget while a person subcommand
# waits at the tty prompt); plan 2.7 (the confirmation holds no lock); T:66b.
e2e_describe "job 7 in build with its clone; nextBudgetSeconds 4; cancel 7 waits 8 s at the prompt while next runs"
ps8_seed
( fe_person_terminal --delay 8 issue-7-j1 "$PS_W" cancel 7 >/dev/null 2>&1 ) &
PS_BG=$!
fe_wait_for 10 "grep -q 'type the job key' '$E2E_DIR/terminal-1.out' 2>/dev/null"
PS_T0N=$(ps_now)
fe_e ordinary.json next --executor headless
PS_T1N=$(ps_now)
e2e_expect_equal 0 "$E2E_RC" "next exit status ($E2E_ERR)"
e2e_expect_equal yes "$(ps_le "$PS_T0N" "$PS_T1N" 5)" "next returned within 5 s"
e2e_expect_equal 66b "$(ps_rows)" "rows after next"
e2e_expect_equal yes "$([ -f "$PS_J/directives/$D1.json" ] && echo yes || echo no)" "directive 1 exists"
fe_wait_for 10 "[ -s '$E2E_BIN/claude-launches.log' ]"
wait "$PS_BG"
e2e_expect_equal 0 "$(cat "$E2E_DIR/terminal-1.rc" 2>/dev/null)" "cancel exit status"
E2E_OUT=$(tr -d '\r' < "$E2E_DIR/terminal-1.out")
e2e_expect_line "RAISED person_cancel job=issue-7-j1"
e2e_expect_equal 1 "$(find "$PS_J/pending" -name '*-person_cancel.json' 2>/dev/null | wc -l | tr -d ' ')" "pending person_cancel files"

fe_new ps8b-together
# Source: amendment A+7.
e2e_describe "as ps8a; cancel 7 (typed at once) and next started together"
ps8_seed
PS_T0N=$(ps_now)
( fe_person_terminal issue-7-j1 "$PS_W" cancel 7 >/dev/null 2>&1 ) &
PS_BG=$!
fe_bg n1 fe_e ordinary.json next --executor headless
fe_bg_wait n1 12
wait "$PS_BG"
PS_T1N=$(ps_now)
e2e_expect_equal yes "$(ps_le "$PS_T0N" "$PS_T1N" 10)" "both finished within 10 s"
e2e_expect_equal 0 "$(cat "$E2E_DIR/bg-n1.rc" 2>/dev/null)" "next exit status"
e2e_expect_equal 0 "$(cat "$E2E_DIR/terminal-1.rc" 2>/dev/null)" "cancel exit status"
E2E_OUT=$(tr -d '\r' < "$E2E_DIR/terminal-1.out")
e2e_expect_line "RAISED person_cancel job=issue-7-j1"
fi

# ---------------------------------------------------------------- PS9
if ps_run PS9; then
_flow_test_begin "person: status prints every job and every active status line (PS9, AC10, C.5)"
fe_new ps9a-status-lines
# Source: AC10; plan 2.6 status output and status lines; design phasing L27-L36;
# amendment C.5; T11 orphan_group_alive (a dead pgid prints nothing).
e2e_describe "stale platform (2.1.326 installed against 2.1.325), so the interactive group is stale too; the GitHub-write group recorded gh 1.x; state.json env_failed_check interpreter and paused_until 2099; job 7 in build with a live and a dead orphan group; job 8 unreadable"
PS_RECORD_EDITS="d['groups']['github_write']['keyed_on']['gh_version'] = 'gh version 1.14.0 (2020-01-01)'"
ps_seed
PS_RECORD_EDITS=""
printf '2.1.326 (Claude Code)\n' > "$E2E_BIN/claude-version"
printf '%s\n' '{"apiVersion":"flow.synapti.ai/v1","kind":"FlowFactoryState","last_sync_at":null,"env_recheck_at":null,"env_failed_check":"interpreter","paused_until":"2099-01-01T00:00:00Z","pass_seq":0}' > "$PS_F/state.json"
PS_LIVE=$(ps_sleeper)
PS_LIVE_START=$(_fe_lstart "$PS_LIVE")
fe_mask_text "$PS_LIVE_START" "<start live-group>"
PS_DEAD=$(_fe_in_scratch "$(fe_python)" -I -c 'import subprocess; p = subprocess.Popen(["true"], start_new_session=True); p.wait(); print(p.pid)')
fe_mask_pid "$PS_LIVE" live-group
fe_mask_pid "$PS_DEAD" dead-group
fe_job 7 build "d['orphan_groups'] = [{'pgid': $PS_LIVE, 'start': '$PS_LIVE_START', 'stage': 'build', 'recorded_at': '$PS_T0'}, {'pgid': $PS_DEAD, 'start': 'Mon Nov 16 00:00:00 2026', 'stage': 'build', 'recorded_at': '$PS_T0'}]"
mkdir -p "$PS_F/jobs/issue-8"
printf '{' > "$PS_F/jobs/issue-8/job.json"
e2e_run_bin bin/flow-factory.sh status
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_line "JOB issue-7-j1 state=build attempt=0 reason=- paused_reason=- slot=no"
e2e_expect_line "UNREADABLE job=issue-8 next: flow-factory.sh rebuild 8"
e2e_expect_line "PAUSED probes_stale=platform recorded=2.1.325 (Claude Code) current=2.1.326 (Claude Code) next: flow-factory.sh probe --platform"
e2e_expect_line "DEGRADED probes_stale=interactive next: /flow:factory probe"
e2e_expect_line "PAUSED probes_failed=environment check=interpreter next: flow-factory.sh probe --environment (from a terminal when check=signing)"
e2e_expect_line "REMINDER probes_stale=github_write next: flow-factory.sh probe --github-write --sandbox <owner/repo> (asks for sandbox approval)"
e2e_expect_line "ORPHAN_GROUP job=issue-7-j1 pgid=$PS_LIVE stage=build"
e2e_expect_equal 1 "$(printf '%s\n' "$E2E_OUT" | grep -c '^ORPHAN_GROUP ')" "ORPHAN_GROUP lines"
e2e_expect_line "PAUSED usage_limit until=2099-01-01T00:00:00Z"
e2e_expect_equal 1 "$(printf '%s\n' "$E2E_OUT" | grep -c '^JOB ')" "JOB lines"
PS_TEXT="$E2E_OUT"
e2e_run_bin bin/flow-factory.sh status --brief
e2e_expect_equal 0 "$E2E_RC" "--brief exit status"
e2e_expect_equal "JOB issue-7-j1 state=build attempt=0 reason=- paused_reason=- slot=no" "$E2E_OUT" "--brief stdout"
e2e_run_bin bin/flow-factory.sh status --json
e2e_expect_equal 0 "$E2E_RC" "--json exit status"
printf '%s' "$E2E_OUT" > "$E2E_DIR/status.json"
e2e_expect_equal "issue-7-j1 build 0 false" "$(ps_jq "$E2E_DIR/status.json" '.jobs | map("\(.key) \(.state) \(.attempt) \(.slot)") | join(";")')" "--json jobs"
e2e_expect_equal "issue-8 invalid_json" "$(ps_jq "$E2E_DIR/status.json" '.unreadable | map("\(.folder) \(.reason)") | join(";")')" "--json unreadable"
e2e_expect_equal "issue-7-j1 $PS_LIVE build" "$(ps_jq "$E2E_DIR/status.json" '.orphan_groups | map("\(.job) \(.pgid) \(.stage)") | join(";")')" "--json orphan_groups"
e2e_expect_equal "2099-01-01T00:00:00Z" "$(ps_jq "$E2E_DIR/status.json" .paused_until)" "--json paused_until"
PS_TEXT_LINES=$(printf '%s\n' "$PS_TEXT" | grep -v '^JOB ' | LC_ALL=C sort)
PS_JSON_LINES=$(jq -r '.status_lines[]' "$E2E_DIR/status.json" 2>/dev/null | LC_ALL=C sort)
e2e_expect_equal "$PS_TEXT_LINES" "$PS_JSON_LINES" "--json status_lines equal the text form's status lines"

fe_new ps9b-status-engine-lines
# Source: plan 2.6 status lines (BLOCKED_UNBUILT, CLONE_CONFIG_CHANGED, the
# NESTED_REPOSITORY form of T11, OUTBOX_PENDING, PAUSED stage_budget_exhausted);
# T:43x reason protected; T11 worker_precheck (A.10: budget 3.00 with 3.00 spent).
e2e_describe "job 9 in spec blocked at launch_due, with an outbox item; job 12 blocked in intake, then moved to spec (no line); job 10 parked protected after a config change; job 13 parked protected after a nested repository; job 11 in build with its 3.00 budget spent"
ps_seed
ps_settings '.flow.factory.worker.stages.build.maxBudgetUsd = 3'
fe_job 9 spec
ps_ev "$(ps_trans p2 judge_accept intake 6 prepare '[]' '[]' 9)" 9
ps_ev '{"type":"blocked_unbuilt","job":"issue-9-j1","time":"2026-11-16T00:20:00Z","pass":"p4","state":"spec","event":"launch_due","fact":"cost_cap_reached","phase":"1g"}' 9
mkdir -p "$PS_F/jobs/issue-9/outbox"
printf '{}\n' > "$PS_F/jobs/issue-9/outbox/i1.json"
fe_job 12 spec
ps_ev '{"type":"blocked_unbuilt","job":"issue-12-j1","time":"2026-11-16T00:20:00Z","pass":"p4","state":"intake","event":"launch_due","fact":"cost_cap_reached","phase":"1g"}' 12
ps_ev "$(ps_trans p5 judge_accept intake 6 prepare '[]' '[]' 12)" 12
fe_job 10 needs_human "d['reason'] = 'protected'; d['blocked_stage'] = 'build'"
ps_ev '{"type":"clone_config_changed","job":"issue-10-j1","time":"2026-11-16T00:20:00Z","pass":"p4","file":"config","key":"core.hookspath"}' 10
ps_ev "$(ps_trans p4 stage_failed build 43x needs_human '[]' '[]' 10)" 10
fe_job 13 needs_human "d['reason'] = 'protected'; d['blocked_stage'] = 'build'"
ps_ev '{"type":"clone_config_changed","job":"issue-13-j1","time":"2026-11-16T00:20:00Z","pass":"p4","nested_repository":"sub"}' 13
ps_ev "$(ps_trans p4 stage_failed build 43x needs_human '[]' '[]' 13)" 13
fe_job 11 build "d['cost'] = {'usd_total': 3, 'runs': [], 'stage_usd': {'build': 3}, 'dearest_turn_usd': 0}"
PS_WT10=$(ps_jq "$PS_F/jobs/issue-10/job.json" .worktree)
e2e_run_bin bin/flow-factory.sh status
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 5 "$(printf '%s\n' "$E2E_OUT" | grep -c '^JOB ')" "JOB lines"
e2e_expect_line "JOB issue-10-j1 state=needs_human attempt=0 reason=protected paused_reason=- slot=no"
e2e_expect_line "BLOCKED_UNBUILT job=issue-9-j1 state=spec event=launch_due fact=cost_cap_reached phase=1g"
e2e_expect_equal 1 "$(printf '%s\n' "$E2E_OUT" | grep -c '^BLOCKED_UNBUILT ')" "BLOCKED_UNBUILT lines (job 12 moved on)"
e2e_expect_line "CLONE_CONFIG_CHANGED job=issue-10-j1 file=config key=core.hookspath next: restore $PS_WT10/.git/config from $PS_F/jobs/issue-10/clone-config/config"
e2e_expect_line "NESTED_REPOSITORY job=issue-13-j1 path=sub"
e2e_expect_line "OUTBOX_PENDING job=issue-9-j1 items=1"
e2e_expect_line "PAUSED stage_budget_exhausted job=issue-11-j1 stage=build next: raise flow.factory.worker.stages.build.maxBudgetUsd or cancel the job"
e2e_expect_no_out "issue-12-j1 state=intake"

fe_new ps9c-status-sync-repo
# Source: plan 2.18 (no repository gh would use: PAUSED sync_repo_unknown).
e2e_describe "the main checkout has no remote"
ps_seed
_fe_in_scratch git remote remove origin
e2e_run_bin bin/flow-factory.sh status
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(printf '%s\n' "$E2E_OUT" | grep -c '^PAUSED sync_repo_unknown next: run gh repo set-default in /')" "the sync_repo_unknown line"
fi

# ---------------------------------------------------------------- PS10, PS12
if ps_run PS10 || ps_run PS12; then
_flow_test_begin "person: context --mode is on only when every check holds; status from a clone reads the main F (PS10, PS12)"
# ps_ctx_script <file> <lease> <body> — a worker script for fe_fake_launcher:
# it waits until the lease names its parent, then runs the body, then touches
# $E2E_DIR/w/<name>.done. The body may call
#   ctx <tag> <cwd> [NAME=value ...]   context --mode with the good values,
#                                      every FLOW_FACTORY_* replaced, these set
#   st <tag> <cwd>                     status, every FLOW_FACTORY_* removed
#   go <name>                          wait up to 60 s for $E2E_DIR/w/go-<name>
# each writing $E2E_DIR/w/<tag>.out, .err and .rc.
ps_ctx_script() {
  local file="$1" lease="$2" body="$3"
  mkdir -p "$E2E_DIR/w"
  {
    printf 'W=%q\nR=%q\nLEASE=%q\nME=%q\nMAIN=%q\n' "$PS_W" "$E2E_DIR/w" "$lease" "$(basename -- "$file")" "$PS_MAIN"
    cat <<'SH'
i=0
until [ "$(jq -r '.launcher_pid // empty' "$LEASE" 2>/dev/null)" = "$PPID" ]; do
  i=$((i + 1)); [ "$i" -gt 100 ] && break; sleep 0.1
done
run_in() {
  local tag="$1" cwd="$2"; shift 2
  ( cd "$cwd" || exit 96; exec env -u FLOW_FACTORY_JOB -u FLOW_FACTORY_DIRECTIVE -u FLOW_FACTORY_IO -u FLOW_FACTORY_MAIN \
      -u FLOW_FACTORY_JOB_KEY -u FLOW_FACTORY_ISSUE -u FLOW_FACTORY_BRANCH -u FLOW_FACTORY_GOAL_ID "$@" ) \
    < /dev/null > "$R/$tag.out" 2> "$R/$tag.err"
  echo "$?" > "$R/$tag.rc.t" && mv "$R/$tag.rc.t" "$R/$tag.rc"
}
ctx() {
  local tag="$1" cwd="$2"; shift 2
  run_in "$tag" "$cwd" FLOW_FACTORY_JOB=issue-7-j1 FLOW_FACTORY_DIRECTIVE=issue-7-j1-build-1 FLOW_FACTORY_MAIN="$MAIN" \
    FLOW_FACTORY_JOB_KEY=issue-7-j1 FLOW_FACTORY_ISSUE=7 FLOW_FACTORY_BRANCH=feature/issue-7-x-2 \
    FLOW_FACTORY_GOAL_ID=issue-7-f2 "$@" "$W" context --mode
}
st() { run_in "$1" "$2" "$W" status; }
go() { local n=0; until [ -e "$R/go-$1" ]; do n=$((n + 1)); [ "$n" -gt 600 ] && return 1; sleep 0.1; done; }
SH
    printf '%s\n' "$body"
    printf 'touch "$R/$ME.done"\n'
  } > "$file"
}
# ps_out <tag> — the recorded run: "<rc> <stdout on one line>".
ps_out() { printf '%s %s' "$(cat "$E2E_DIR/w/$1.rc" 2>/dev/null || echo none)" "$(tr '\n' ' ' < "$E2E_DIR/w/$1.out" 2>/dev/null | sed 's/ $//')"; }

fe_new ps10-context-mode
# Source: design factory_mode_in_commands L5-L10 (the one list of checks);
# e2e_tests L38; plan T12 cmd_context; plan 2.4 (a worker's status reads the F
# its launcher names).
e2e_describe "job 7 in build with its clone, below a fake launcher of issue-7-j1-build-1; hand leases build-2 (live) and build-3 (revoked) copied from it; a second fake launcher of issue-8-j1-build-1 runs one check with job 7's values"
ps_seed
fe_job 7 build
fe_job_clone 7
PS_WT=$(ps_jq "$PS_J/job.json" .worktree)
PS_MAIN=$(cd "$E2E_REPO" && pwd -P)
_fe_in_scratch git clone -q "$E2E_REPO" "$E2E_DIR/other" >/dev/null 2>&1
PS_OTHER=$(cd "$E2E_DIR/other" && pwd -P)
ps_ctx_script "$E2E_DIR/w7.sh" "$PS_J/directives/$D1.lease.json" "
go leases
ctx on $(printf %q "$PS_WT")
ctx branch $(printf %q "$PS_WT") FLOW_FACTORY_BRANCH=feature/other
ctx issue $(printf %q "$PS_WT") FLOW_FACTORY_ISSUE=8
ctx main $(printf %q "$PS_WT") FLOW_FACTORY_MAIN=$(printf %q "$PS_OTHER")
ctx directive $(printf %q "$PS_WT") FLOW_FACTORY_DIRECTIVE=issue-7-j1-build-9
ctx cwd $(printf %q "$PS_MAIN")
ctx lease2 $(printf %q "$PS_WT") FLOW_FACTORY_DIRECTIVE=$D2
ctx revoked $(printf %q "$PS_WT") FLOW_FACTORY_DIRECTIVE=$D3
st status $(printf %q "$PS_WT")
touch \"\$R/cases.done\"
go end"
PS_L7=$(fe_fake_launcher "$PS_F" "$D1" "$E2E_DIR/w7.sh")
[ -n "$PS_L7" ] && fe_mask_pid "$PS_L7" launcher-7
jq --arg d "$D2" '.directive = $d' "$PS_J/directives/$D1.lease.json" > "$PS_J/directives/$D2.lease.json"
jq --arg d "$D3" '.directive = $d | .revoked_at = "2026-11-16T00:00:00Z"' "$PS_J/directives/$D1.lease.json" > "$PS_J/directives/$D3.lease.json"
touch "$E2E_DIR/w/go-leases"
fe_wait_for 90 "[ -e '$E2E_DIR/w/cases.done' ]"
ps_ctx_script "$E2E_DIR/w8.sh" "$PS_F/jobs/issue-8/directives/issue-8-j1-build-1.lease.json" "
ctx notbelow $(printf %q "$PS_WT")"
PS_L8=$(fe_fake_launcher "$PS_F" issue-8-j1-build-1 "$E2E_DIR/w8.sh")
[ -n "$PS_L8" ] && fe_mask_pid "$PS_L8" launcher-8
fe_wait_for 60 "[ -e '$E2E_DIR/w/w8.sh.done' ]"
touch "$E2E_DIR/w/go-end"
fe_wait_for 30 "[ -e '$E2E_DIR/w/w7.sh.done' ]"
for PS_TAG in on branch issue main directive cwd lease2 revoked notbelow status; do
  printf -- '--- %s: rc %s\n%s\n--- stderr\n%s\n' "$PS_TAG" "$(cat "$E2E_DIR/w/$PS_TAG.rc" 2>/dev/null)" \
    "$(cat "$E2E_DIR/w/$PS_TAG.out" 2>/dev/null)" "$(cat "$E2E_DIR/w/$PS_TAG.err" 2>/dev/null)" | _e2e_art
done
if ps_run PS10; then
e2e_expect_equal "0 FACTORY_MODE=on" "$(ps_out on)" "(a) every check holds"
e2e_expect_equal "0 FACTORY_MODE=on" "$(ps_out lease2)" "(a) a second live lease naming its directive, same claude"
e2e_expect_equal "0 FACTORY_MODE=invalid" "$(ps_out branch)" "(b) FLOW_FACTORY_BRANCH differs from job.json"
e2e_expect_equal "0 FACTORY_MODE=invalid" "$(ps_out issue)" "(b) FLOW_FACTORY_ISSUE differs from job.json"
e2e_expect_equal "0 FACTORY_MODE=invalid" "$(ps_out main)" "(b) FLOW_FACTORY_MAIN names another checkout"
e2e_expect_equal "0 FACTORY_MODE=invalid" "$(ps_out directive)" "(b) FLOW_FACTORY_DIRECTIVE names a directive with no lease"
e2e_expect_equal "0 FACTORY_MODE=invalid" "$(ps_out cwd)" "(b) the cwd is not the job clone"
e2e_expect_equal "0 FACTORY_MODE=invalid" "$(ps_out revoked)" "(b) the lease is revoked"
e2e_expect_equal "0 FACTORY_MODE=invalid" "$(ps_out notbelow)" "(b) not below the lease's claude pid"
# Each case fails on its own check, so no case passes because another check
# happens to fail.
for PS_PAIR in branch:FLOW_FACTORY_BRANCH issue:FLOW_FACTORY_ISSUE main:main directive:lease cwd:toplevel \
    revoked:lease notbelow:claude_ancestor; do
  e2e_expect_equal "flow-factory.sh context: check failed: ${PS_PAIR#*:}" "$(cat "$E2E_DIR/w/${PS_PAIR%%:*}.err" 2>/dev/null)" "(b) ${PS_PAIR%%:*}: the check named on stderr"
done
fi
if ps_run PS12; then
e2e_run_bin bin/flow-factory.sh status --brief
e2e_expect_equal 0 "$E2E_RC" "status from the main checkout: exit status ($E2E_ERR)"
e2e_expect_equal "JOB issue-7-j1 state=build attempt=0 reason=- paused_reason=- slot=no" "$E2E_OUT" "status --brief from the main checkout"
e2e_expect_equal 0 "$(cat "$E2E_DIR/w/status.rc" 2>/dev/null)" "status from the clone: exit status"
e2e_expect_equal "$E2E_OUT" "$(grep '^JOB ' "$E2E_DIR/w/status.out" 2>/dev/null)" "status from the clone: the same JOB lines"
fi
fi

# ---------------------------------------------------------------- PS11
if ps_run PS11; then
_flow_test_begin "person: with the factory not enabled, cancel is refused and status and rebuild act (PS11, A.3)"
fe_new ps11-enabled-gate
# Source: amendment A.3 (status, rebuild, probe and context --mode never check
# flow.factory.enabled); plan 2.6 disabled line.
e2e_describe "flow.factory.enabled unset; job 7 in build with a created line naming it; cancel 7, status, rebuild 7 in a terminal"
ps_seed
fe_job 7 build
ps_ev "$(ps_created "$(jq -c . "$PS_J/job.json")" build)"
e2e_run_bin bin/flow-factory.sh cancel 7
e2e_expect_equal 5 "$E2E_RC" "cancel exit status"
e2e_expect_equal "$PS_DISABLED" "$E2E_OUT" "cancel stdout"
e2e_run_bin bin/flow-factory.sh status --brief
e2e_expect_equal 0 "$E2E_RC" "status exit status ($E2E_ERR)"
e2e_expect_equal "JOB issue-7-j1 state=build attempt=0 reason=- paused_reason=- slot=no" "$E2E_OUT" "status stdout"
fe_person_terminal issue-7-j1 "$PS_W" rebuild 7
e2e_expect_equal 0 "$E2E_RC" "rebuild exit status"
e2e_expect_line "REBUILT job=issue-7-j1 state=build"
e2e_expect_equal 0 "$(ps_pending_count)" "pending files"
fi

# ---------------------------------------------------------------- PS13
if ps_run PS13; then
_flow_test_begin "person: a rebuilt job equals the live one field by field (PS13, AC10)"
ps13_seed() {
  ps_seed
  fe_enable
  fe_job 7 build
  fe_job_clone 7
  ps_ev "$(ps_created "$(jq -c . "$PS_J/job.json")" build)"
  e2e_plugin_copy templates/factory/build.prompt.md 'RUN: true'
  ps_w
  fe_worker_says "worker-result=$PS_FAIL_RESULT"
}
# ps13_compare <saved live job.json> — every field but updated_at and head_sha,
# with null and absent alike, in the artifact and compared.
ps13_compare() {
  local norm='del(.updated_at, .head_sha) | with_entries(select(.value != null))'
  ps_mask_sids 7
  jq -S "$norm" "$1" > "$E2E_DIR/live.norm"
  jq -S "$norm" "$PS_J/job.json" > "$E2E_DIR/rebuilt.norm" 2>/dev/null
  printf -- '--- live job.json (normalized)\n%s\n--- rebuilt job.json (normalized)\n%s\n--- diff\n%s\n' \
    "$(cat "$E2E_DIR/live.norm")" "$(cat "$E2E_DIR/rebuilt.norm")" \
    "$(diff "$E2E_DIR/live.norm" "$E2E_DIR/rebuilt.norm")" | _e2e_art
  e2e_expect_equal "" "$(diff "$E2E_DIR/live.norm" "$E2E_DIR/rebuilt.norm" | grep '^[<>]' | tr '\n' ';')" "fields that differ between the live and the rebuilt job"
}
fe_new ps13a-rebuilt-equals-live
# Source: T12 rebuild table; T:66b, T:39 (attempt += 1, relaunch resume), T:43a
# (reason attempts_exhausted, blocked_stage build); the live job.json that four
# real next passes wrote is the expected value.
e2e_describe "job 7 in build with a created line; three runs fail; four next passes give 66b 39 66b 39 66b 43a; job.json is then replaced by '{' and rebuilt in a terminal"
ps13_seed
for PS_K in 1 2 3; do
  fe_e ordinary.json next --executor headless
  ps_finish "issue-7-j1-build-$PS_K"
done
fe_e ordinary.json next --executor headless
e2e_expect_equal "66b 39 66b 39 66b 43a" "$(ps_rows)" "rows of the live job"
e2e_expect_equal "needs_human attempts_exhausted 2" "$(ps_jq "$PS_J/job.json" '"\(.state) \(.reason) \(.attempt)"')" "live state, reason, attempt"
cp "$PS_J/job.json" "$E2E_DIR/live.json"
printf '{' > "$PS_J/job.json"
fe_person_terminal issue-7-j1 "$PS_W" rebuild 7
e2e_expect_equal 0 "$E2E_RC" "rebuild exit status"
e2e_expect_line "REBUILT job=issue-7-j1 state=needs_human"
ps13_compare "$E2E_DIR/live.json"
PS_HEAD=$(_fe_in_scratch git -C "$(ps_jq "$E2E_DIR/live.json" .worktree)" rev-parse HEAD)
fe_mask_text "$PS_HEAD" "<clone head>"
e2e_expect_equal "$PS_HEAD" "$(ps_jq "$PS_J/job.json" .head_sha)" "head_sha is the clone's HEAD"
ps_art_state 7

fe_new ps13b-rebuild-before-result
# Source: T:39 (the stored stage_failed still applies after a rebuild); T:66b.
e2e_describe "as ps13a; after the first run's result is stored and before the next pass, job.json is replaced by '{' and rebuilt; then next"
ps13_seed
fe_e ordinary.json next --executor headless
ps_finish "$D1"
e2e_expect_equal 1 "$(find "$PS_J/pending" -name '*-stage_failed.json' 2>/dev/null | wc -l | tr -d ' ')" "a stored stage_failed"
cp "$PS_J/job.json" "$E2E_DIR/live.json"
printf '{' > "$PS_J/job.json"
fe_person_terminal issue-7-j1 "$PS_W" rebuild 7
e2e_expect_equal 0 "$E2E_RC" "rebuild exit status"
e2e_expect_line "REBUILT job=issue-7-j1 state=build"
ps13_compare "$E2E_DIR/live.json"
fe_e ordinary.json next --executor headless
e2e_expect_equal 0 "$E2E_RC" "next exit status ($E2E_ERR)"
e2e_expect_equal "66b 39 66b" "$(ps_rows)" "rows: the stored result applied (39) and the stage relaunched"
e2e_expect_equal "$D2" "$(ps_jq "$PS_J/job.json" .directive)" "directive after next"
ps_finish "$D2"
ps_art_state 7

# ps13c_zombie_group — sets PS_Z to the pid of a `sleep 60` in a session of
# its own, whose parent (a background python) never reaps it. Once the engine
# kills it, the group leader is a zombie: killpg(pgid, 0) still finds the
# group and ps still gives the leader's start, so the group is not confirmed
# gone and stays alive by the engine's orphan_alive. Both processes are
# registered for cleanup. (Observed on darwin: killpg gives EPERM for the
# zombie's group.)
ps13c_zombie_group() {
  fe_bg zombie fe_py "import subprocess, time
p = subprocess.Popen(['sleep', '60'], start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print(p.pid, flush=True)
time.sleep(60)"
  fe_wait_for 10 "[ -s '$E2E_DIR/bg-zombie.out' ]" || return 1
  PS_Z=$(head -n 1 "$E2E_DIR/bg-zombie.out")
  _fe_register "$PS_Z"
}
# ps13c_lease <directive> — a lease for a directive no launcher ran: the
# launcher has exited, the heartbeat is old and no child was started.
ps13c_lease() {
  local dead
  dead=$(_fe_in_scratch sh -c 'echo $$')
  cat > "$PS_J/directives/$1.lease.json" <<JSON
{"directive": "$1", "kind": "worker", "host": "h", "launcher_pid": $dead, "launcher_start": "Mon Nov 16 00:00:00 2026",
 "started_at": "2026-11-16T00:00:00Z", "heartbeat_at": "2026-11-16T00:00:00Z", "child_pid": null, "child_pgid": null,
 "child_start": null, "revoked_at": null}
JSON
}
# ps13c_kill_run <directive> — once the run's claude has written dirty.txt,
# SIGKILL its launcher, then claude's group, and age the heartbeat, so the
# next pass finds the lease expired with no result.
ps13c_kill_run() {
  local l="$PS_J/directives/$1.lease.json" lp pg
  fe_wait_for 30 "[ -n \"\$(jq -r '.child_pgid // empty' '$l' 2>/dev/null)\" ] && [ -f '$PS_WT/dirty.txt' ]" || return 1
  lp=$(jq -r .launcher_pid "$l")
  pg=$(jq -r .child_pgid "$l")
  kill -KILL "$lp" 2>/dev/null
  fe_wait_for 15 "! kill -0 $lp 2>/dev/null"
  kill -KILL -- "-$pg" 2>/dev/null
  fe_wait_for 15 "! kill -0 -- -$pg 2>/dev/null"
  jq '.heartbeat_at = "2026-11-16T00:00:00Z"' "$l" > "$l.t" && mv "$l.t" "$l"
}
# ps13c_fields <job.json> — orphan_groups, snapshots, pending_changes and
# state, each as sorted compact JSON on its own line.
ps13c_fields() { jq -cS '.orphan_groups, .snapshots, .pending_changes, .state' "$1" 2>/dev/null; }
# ps13c_masked <job.json> — the same, with the values that change from run
# to run written as fixed tokens, for the artifact.
ps13c_masked() {
  jq -cS '(.orphan_groups // [] | map(.pgid = "<pgid>" | .start = "<start>" | .recorded_at = "<time>")),
    (.snapshots // [] | map(.at = "<time>")), .pending_changes, .state' "$1" 2>/dev/null
}
PS_A40=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
PS_B40=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
PS_D4=issue-7-j1-build-4

fe_new ps13c-rebuild-keeps-orphan-snapshots-changes
# Source: T12 rebuild table (every field a pass writes is restored from the
# log); T:39ld (snapshot, reset, attempt += 1, relaunch fresh); T:43o (a group
# not confirmed gone is recorded; needs_human, orphan_worker); plan T11 Sync
# (a head the factory did not push joins pending_changes, which stays while
# github_change is blocked); T:44r (retry to blocked_stage); T:43g (launch_due
# with orphan_group_alive: needs_human, do not launch). The live job.json the
# real passes wrote is the expected value.
e2e_describe "four next passes: D1's lease expires on a dirty clone (39ld, snapshot-1, D2 launches); D2 is killed after dirtying the clone (39ld, snapshot-2, D3 launches); D3 is killed and its lease names a group that cannot be confirmed gone (43o); gh reports a foreign head while github_change is blocked. job.json is replaced by '{' and rebuilt; then retry and next"
ps_seed
ps13c_zombie_group
fe_mask_pid "$PS_Z" sleeper
fe_enable
fe_job 7 build "d['directive'] = '$D1'; d['stage_launches'] = {'build': 1}; d['holds_slot'] = True; d['pr'] = 12; d['head_sha'] = '$PS_A40'"
fe_job_clone 7
ps_ev "$(ps_created "$(jq -c . "$PS_J/job.json")" build)"
ps_settings '.flow.factory.leaseSeconds = 3 | .flow.factory.syncIntervalSeconds = 0'
fe_directive "$D1" "d['max_budget_usd'] = 0.5; d['started_at'] = '2026-11-16T00:00:00Z'; d['model'] = 'claude-opus-5-5'"
ps13c_lease "$D1"
e2e_plugin_copy templates/factory/build.prompt.md 'RUN: printf run > dirty.txt
RUN: sleep 60'
ps_w
fe_worker_says
fe_gh api_repos_flow-e2e_scratch_pulls_12 "{\"state\":\"open\",\"merged\":false,\"merged_at\":null,\"head\":{\"sha\":\"$PS_A40\"}}"
PS_WT=$(ps_jq "$PS_J/job.json" .worktree)
printf 'seeded\n' > "$PS_WT/dirty.txt"
fe_e ordinary.json next --executor headless
e2e_expect_equal 0 "$E2E_RC" "pass 1 exit status ($E2E_ERR)"
ps13c_kill_run "$D2"
fe_e ordinary.json next --executor headless
e2e_expect_equal 0 "$E2E_RC" "pass 2 exit status ($E2E_ERR)"
ps13c_kill_run "$D3"
PS_L3="$PS_J/directives/$D3.lease.json"
jq --argjson z "$PS_Z" --arg s "$(_fe_lstart "$PS_Z")" '.child_pid = $z | .child_pgid = $z | .child_start = $s' "$PS_L3" > "$PS_L3.t" && mv "$PS_L3.t" "$PS_L3"
fe_e ordinary.json next --executor headless
e2e_expect_equal 0 "$E2E_RC" "pass 3 exit status ($E2E_ERR)"
fe_gh api_repos_flow-e2e_scratch_pulls_12 "{\"state\":\"open\",\"merged\":false,\"merged_at\":null,\"head\":{\"sha\":\"$PS_B40\"}}"
# No default_unbuilt: an unbuilt fact has no value, as without the seam, so
# github_change in needs_human is blocked and the change stays pending.
printf '%s\n' '{"unbuilt": {"*": {"executor_can_confirm": true}}}' > "$E2E_DIR/blocking.json"
fe_e "$E2E_DIR/blocking.json" next --executor headless
e2e_expect_equal 0 "$E2E_RC" "pass 4 exit status ($E2E_ERR)"
e2e_expect_equal "39ld 66b 39ld 66b 43o" "$(ps_rows)" "rows of the live job"
e2e_expect_equal "needs_human orphan_worker 1 2" \
  "$(ps_jq "$PS_J/job.json" '"\(.state) \(.reason) \(.orphan_groups | length) \(.snapshots | length)"')" \
  "live state, reason, orphan groups, snapshots"
e2e_expect_equal '["foreign_head_change"]' "$(jq -c .pending_changes "$PS_J/job.json" 2>/dev/null)" "live pending_changes"
fe_py "import json, _flow_factory_next as nx
d = json.load(open('$PS_J/job.json'))
print(sum(1 for e in d.get('orphan_groups') or [] if nx.orphan_alive(e)))"
e2e_expect_equal 1 "$E2E_OUT" "live orphan groups alive by orphan_alive"
cp "$PS_J/job.json" "$E2E_DIR/live.json"
printf -- '--- live job.json: orphan_groups, snapshots, pending_changes, state (masked)\n%s\n' "$(ps13c_masked "$E2E_DIR/live.json")" | _e2e_art
printf '{' > "$PS_J/job.json"
fe_person_terminal issue-7-j1 "$PS_W" rebuild 7
e2e_expect_equal 0 "$E2E_RC" "rebuild exit status"
e2e_expect_line "REBUILT job=issue-7-j1 state=needs_human"
printf -- '--- rebuilt job.json: orphan_groups, snapshots, pending_changes, state (masked)\n%s\n' "$(ps13c_masked "$PS_J/job.json")" | _e2e_art
e2e_expect_equal "$(ps13c_fields "$E2E_DIR/live.json" | tr '\n' ';')" "$(ps13c_fields "$PS_J/job.json" | tr '\n' ';')" \
  "rebuilt orphan_groups; snapshots; pending_changes; state equal the live job's"
# Held: the retry returns the job to build, and row 43g holds the launch while
# the orphan group lives.
fe_person_terminal issue-7-j1 "$PS_W" retry 7
e2e_expect_line "RAISED person_retry job=issue-7-j1"
fe_e ordinary.json next --executor headless
e2e_expect_equal 0 "$E2E_RC" "pass 5 exit status ($E2E_ERR)"
e2e_expect_equal 44r "$(jq -r 'select(.type == "transition") | .row' "$PS_J/events.jsonl" 2>/dev/null | tail -n 1)" "pass 5 applies the retry"
fe_e ordinary.json next --executor headless
e2e_expect_equal 0 "$E2E_RC" "pass 6 exit status ($E2E_ERR)"
e2e_expect_equal "needs_human orphan_worker" "$(ps_jq "$PS_J/job.json" '"\(.state) \(.reason)"')" "state, reason after retry and two passes"
e2e_expect_equal 43g "$(jq -r 'select(.type == "transition") | .row' "$PS_J/events.jsonl" 2>/dev/null | tail -n 1)" "the last row"
e2e_expect_equal absent "$([ -e "$PS_J/directives/$PS_D4.json" ] && echo present || echo absent)" "a fourth directive"
ps_art_state 7
# Mutant: rebuild keeps the first logged value of each field instead of the
# last. In the scenario's plugin copy only; it must not equal the live job.
PS_M="$E2E_ACTIVE_PLUGIN/bin/_flow_factory_person.py"
cp "$PS_M" "$E2E_DIR/person.orig.py"
_fe_in_scratch "$(fe_python)" -I -c 'import sys
p = sys.argv[1]
s = open(p).read()
old = "if isinstance(line.get(field), list):"
assert s.count(old) == 1, "mutation site"
open(p, "w").write(s.replace(old, "if isinstance(line.get(field), list) and not job.get(field):"))' "$PS_M"
e2e_expect_equal changed "$(cmp -s "$PS_M" "$E2E_DIR/person.orig.py" && echo same || echo changed)" "the mutant differs from the module"
printf 'mutant: rebuild keeps the first logged value of each field (plugin copy only)\n' | _e2e_art
printf '{' > "$PS_J/job.json"
fe_person_terminal issue-7-j1 "$PS_W" rebuild 7
e2e_expect_equal 0 "$E2E_RC" "mutant rebuild exit status"
e2e_expect_equal 1 "$(jq '.snapshots | length' "$PS_J/job.json" 2>/dev/null)" "the mutant keeps one snapshot of the live two"
e2e_expect_equal different "$([ "$(ps13c_fields "$E2E_DIR/live.json" | tr '\n' ';')" = "$(ps13c_fields "$PS_J/job.json" | tr '\n' ';')" ] && echo equal || echo different)" \
  "the mutant's rebuilt fields differ from the live job's"
fi

# ---------------------------------------------------------------- PS14
if ps_run PS14; then
_flow_test_begin "person: a wrong word at the prompt confirms nothing (PS14)"
fe_new ps14-wrong-word
# Source: person_channels L42 (the job id typed back); plan T12 outline step 3
# (anything else gives PERSON_CONFIRM_REQUIRED).
e2e_describe "job 7 in build; cancel 7 in a terminal, typing issue-8-j1"
ps_seed
fe_enable
fe_job 7 build
fe_person_terminal issue-8-j1 "$PS_W" cancel 7
e2e_expect_equal 4 "$E2E_RC" "exit status"
e2e_expect_out "type the job key to confirm:"
e2e_expect_line "PERSON_CONFIRM_REQUIRED next: run flow-factory.sh cancel 7 in a terminal"
e2e_expect_equal 0 "$(ps_pending_count)" "pending files"
# Plan 2.6: a refusal is exactly one stdout line. Under the pty stdout and the
# prompt share the terminal, so stdout goes to a file here.
fe_person_terminal issue-8-j1 bash -c "$(printf '%q cancel 7 > %q; exit $?' "$PS_W" "$E2E_DIR/ps14b.out")"
e2e_expect_equal 4 "$E2E_RC" "(b) exit status, stdout to a file"
e2e_expect_equal "PERSON_CONFIRM_REQUIRED next: run flow-factory.sh cancel 7 in a terminal" "$(cat "$E2E_DIR/ps14b.out" 2>/dev/null)" "(b) stdout is exactly the refusal line"
e2e_expect_equal 1 "$(wc -l < "$E2E_DIR/ps14b.out" | tr -d ' ')" "(b) stdout lines"
fi

_flow_test_summary
