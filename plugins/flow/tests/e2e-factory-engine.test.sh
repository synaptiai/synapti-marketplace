# shellcheck shell=bash
# flow-test: alone
# Every row of the factory's state table driven through `next` (plan 1a T13,
# AC3): for each row id, a witness from the docs checker (a state and a fact
# assignment under which that row wins), seeded into a scratch factory
# directory so the engine's own `next` raises the witness's event with those
# facts, through the test entry point (E, fe_e). Then the moves outside the
# table, a pair with no winning row, the pass_first rule, a change kept
# pending across a move, the derived-fact precedence, creation row 1, and the
# fence (the shipped `next` evaluates no unbuilt fact).
#
# Ways it can be wrong, written down before the checks:
#   EN1  a row is never driven: an id below the table's full count (its rows
#        plus creation row 1) has no passing scenario
#   EN2  a stay row or a self-move is "covered" by its end state alone; so
#        each scenario asserts the transition line of the pass that applied
#        the witness's event, whose event is the witness's event (the first
#        such line in that pass), not the last line of events.jsonl
#   EN3  a witness is derived from the engine: the witnesses come from
#        tests/fixtures/factory/witness.py, which runs docs/flow-factory/
#        check_transitions.py's Checker over the table and reads nothing
#        under bin/
#   EN4  the derived-fact precedence is wrong through `next` (journal RM2):
#        with both the confirm and the pre-push inputs, open_pr's stage
#        success parks as a push intent (row 40) instead of row 21f
#   EN5  a pending change is lost across a move (R16)
#   EN6  a person's cancel beats their merge in the same pass (pass_first)
#   EN7  an off-table move (a resume into a state no parking row records)
#        is not refused with exit 3, or changes job.json
#   EN8  the shipped `next` evaluates an unbuilt fact (R22), even with a seam
#        fixture file and a seam variable planted
#   EN9  creation row 1 cannot be produced, or the shipped engine creates a
#        job without the 1b creation conditions
#   ENC  a fact assignment the dependencies forbid, with no winning row, moves
#        the job instead of being refused (plan 3.7(3))
#
# Seeds. A witness's event is raised by the engine's own rules, not by the
# test: a person or launcher event is a J/pending/<seq>-<event>.json file; a
# stage or judge event also has the job's current directive and its result;
# github_change is job.json pending_changes (and the gh pulls fixture for the
# PR facts); lease_expired is a directive with a lease whose launcher and
# child have ended and whose heartbeat is a day old; launch_due is a stage
# state with no current directive; sync_tick needs nothing beyond the state.
# The facts the pair reads come from job.json, the probe record, the clone,
# a live orphan group, a second job holding the slot, and the seam for the
# unbuilt ones. Each row's fixture names every unbuilt fact the pair reads
# and sets no default_unbuilt, so a fact the engine reads that the table does
# not list for the pair would block it (SEAM_MISSING) and fail the row, and
# a launch_due raised later in the same pass for another pair is blocked
# instead of starting a process.
#
# Run time. One scenario per row id (172 with row 1), not one per (row,
# state) win (594). Two full runs of this file, on a Mac on 2026-11-17, took
# 765 s and 944 s for the 172 row ids and the other groups, 4 to 5 s per
# scenario; 594 scenarios would take 40 minutes or more, past the 900 s the
# plan allows for adding them. The file prints its run time on stdout at the end.
#
# EN_ONLY=<EN1 ... EN9, ENC> runs only that group. EN_IDS="<id> <id> ..."
# limits EN1 to those row ids (EN1's count check then fails, as it should).

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}
# shellcheck source=lib/factory-e2e.sh
source "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh"

EN_T0=$SECONDS
en_run() { [ -z "${EN_ONLY:-}" ] || [ "$EN_ONLY" = "$1" ]; }
EN_WITNESS="$FE_FIXTURES/witness.py"
EN_TABLE="$REPO_ROOT/plugins/flow/references/factory-transitions.json"

# en_gen <witness.py arguments...> — run the generator with the recorded
# interpreter, isolated, from the scratch root; stdout to a file named by
# the first argument. Returns the generator's exit status.
en_gen() {
  local out="$E2E_ROOT/witness-$1.out"
  ( cd "$E2E_ROOT" && "$(fe_python)" -I "$EN_WITNESS" "$@" ) > "$out" 2> "$out.err"
}

# en_events [n] — the job's events.jsonl, one compact line each.
en_events() { jq -c . "$EN_F/jobs/issue-${1:-7}/events.jsonl" 2>/dev/null; }
# en_line <n> <pass> <event> — the first transition line of that pass whose
# event is the given one.
en_line() {
  jq -c --arg p "$2" --arg e "$3" 'select(.type == "transition" and .pass == $p and .event == $e)' \
    "$EN_F/jobs/issue-$1/events.jsonl" 2>/dev/null | head -n 1
}
en_pass() { jq -r '"p\(.pass_seq)"' "$EN_F/state.json" 2>/dev/null; }
en_job() { jq -r "$2" "$EN_F/jobs/issue-$1/job.json" 2>/dev/null; }
en_launches() { if [ -f "$E2E_BIN/claude-launches.log" ]; then wc -l < "$E2E_BIN/claude-launches.log" | tr -d ' '; else echo 0; fi; }

# nx7's sleeper (e2e-factory-engine-next.test.sh): `sleep 120` in a session
# of its own, registered for _fe_cleanup; prints its pid.
en_sleeper() {
  local pid
  pid=$(_fe_in_scratch "$(fe_python)" -I -c 'import subprocess; print(subprocess.Popen(["sleep", "120"], start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).pid)')
  _fe_register "$pid"
  printf '%s' "$pid"
}

# en_dead_pid — the pid of a `sleep 0` that has ended and been reaped.
en_dead_pid() {
  local pid
  sleep 0 & pid=$!
  wait "$pid" 2>/dev/null
  printf '%s' "$pid"
}

# en_scenario_start [record edits] — the scratch main checkout, a probe
# record, the factory enabled; sets EN_F.
en_scenario_start() {
  e2e_repo main
  fe_record "${1:-}"
  fe_enable
  EN_F=$(fe_factory_dir)
}

# en_seed <witness json> — seed the witness's job (and what its facts need)
# into F, and write its seam fixture to $E2E_DIR/fixture.json. Expects
# en_scenario_start to have run.
en_seed() {
  local w="$1" n s j did wt pid start jobfile now_seq pend
  n=$(jq -r .issue <<<"$w"); s=$(jq -r .state <<<"$w")
  j="$EN_F/jobs/issue-$n"
  jobfile="$E2E_DIR/seed-job-$n.json"
  jq -c .seed.job <<<"$w" > "$jobfile"
  if [ "$(jq -r .seed.orphan <<<"$w")" = true ]; then
    pid=$(en_sleeper); start=$(_fe_lstart "$pid")
    fe_mask_pid "$pid" orphan
    jq -c --argjson p "$pid" --arg st "$start" --arg stage "$s" \
      '.orphan_groups = [{"pgid": $p, "start": $st, "stage": $stage, "recorded_at": "2026-11-16T00:00:00Z"}]' \
      "$jobfile" > "$jobfile.t" && mv "$jobfile.t" "$jobfile"
  fi
  fe_job "$n" "$s" "d.update(json.load(open('$jobfile')))"
  if [ "$(jq -r .seed.slot <<<"$w")" = other_job ]; then
    fe_job 99 needs_human "d['holds_slot'] = True; d['reason'] = 'attempts_exhausted'; d['blocked_stage'] = 'build'"
  fi
  if [ "$(jq -r .seed.clone <<<"$w")" = true ]; then
    fe_job_clone "$n"
    wt=$(en_job "$n" .worktree)
    if [ "$(jq -r .seed.dirty <<<"$w")" = true ]; then
      printf 'dirty\n' > "$wt/fe-dirty.txt"
    fi
    if [ "$(jq -r .seed.config_change <<<"$w")" = true ]; then
      _fe_in_scratch git -C "$wt" config filter.fe.clean true
    fi
  fi
  if [ "$(jq -r '.seed.pr_fixture // empty' <<<"$w")" != "" ]; then
    fe_gh "$(jq -r .seed.pr_fixture.key <<<"$w")" "$(jq -c .seed.pr_fixture.json <<<"$w")"
  fi
  did=$(jq -r '.seed.directive.id // empty' <<<"$w")
  if [ -n "$did" ]; then
    fe_directive "$did" "$(jq -r '.seed.directive | "d[\"kind\"] = \"\(.kind)\"; d[\"max_budget_usd\"] = \(.max_budget_usd)" + (if .kind == "worker" then "" else "; d[\"session_id\"] = None; d[\"prompt_template\"] = None; d[\"timeout_seconds\"] = None; d[\"allowed_tools\"] = None" end)' <<<"$w")"
  fi
  if [ "$(jq -r '.seed.result // empty' <<<"$w")" != "" ]; then
    mkdir -p "$j/results"
    jq -n --arg d "$did" --argjson r "$(jq -c .seed.result <<<"$w")" '{directive: $d, outcome: $r.outcome,
      written_at: "2026-11-16T00:00:00Z", event: $r.event, session_id: null, num_turns: null,
      api_error_status: null, is_error: null, permission_denials: null, terminal_reason: null,
      charged_usd: null, charge_basis: null, total_cost_usd: null, since_last_usd: null}' > "$j/results/$did.json"
  fi
  if [ "$(jq -r .seed.lease <<<"$w")" = true ]; then
    pid=$(en_dead_pid)
    jq -n --arg d "$did" --arg k "$(jq -r .seed.directive.kind <<<"$w")" --argjson p "$pid" '{directive: $d, kind: $k,
      host: "fe-host", launcher_pid: $p, launcher_start: "Mon Nov 16 00:00:00 2026",
      started_at: "2026-11-16T00:00:00Z", heartbeat_at: "2026-11-16T00:00:00Z", child_pid: $p, child_pgid: $p,
      child_start: "Mon Nov 16 00:00:00 2026", revoked_at: null}' > "$j/directives/$did.lease.json"
  fi
  pend=$(jq -c '.seed.pending // empty' <<<"$w")
  if [ -n "$pend" ]; then
    mkdir -p "$j/pending"
    now_seq=$(printf '%020d' 1)
    jq -n --argjson p "$pend" '{event: $p.event, args: $p.args, channel: $p.channel,
      caller: {pid: 4242, start: "Mon Nov 16 00:00:00 2026", ancestry: [4242, 1]}, facts: $p.facts,
      raised_at: "2026-11-16T00:00:00Z"}' > "$j/pending/$now_seq-$(jq -r .event <<<"$pend").json"
  fi
  jq -c .fixture <<<"$w" > "$E2E_DIR/fixture.json"
  printf 'witness: %s\n' "$w" | _e2e_art
}

# en_worker_plugin <stage> — a plugin copy with the stage's first-launch
# prompt (1a ships only resume.prompt.md), and the worker stand-in giving a
# success, for the one witness whose row starts a real worker launch.
en_worker_plugin() {
  e2e_plugin_copy "templates/factory/$1.prompt.md" 'RUN: true'
  fe_worker_says 'worker-result={"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.05}'
}

# en_expect_witness <witness json> <pass id> — the checks every row
# scenario makes after its pass (EN1, EN2).
en_expect_witness() {
  local w="$1" p="$2" n s e row to stay line got
  n=$(jq -r .issue <<<"$w"); s=$(jq -r .state <<<"$w"); e=$(jq -r .event <<<"$w")
  row=$(jq -r .expect.row <<<"$w"); to=$(jq -r '.expect.to // empty' <<<"$w"); stay=$(jq -r '.expect.stay // false' <<<"$w")
  line=$(en_line "$n" "$p" "$e")
  e2e_expect_equal "$row" "$(jq -r '.row // "none"' <<<"${line:-{\}}")" "row of the first $e transition line of pass $p"
  e2e_expect_equal "$s" "$(jq -r '.from // "none"' <<<"${line:-{\}}")" "its from"
  if [ "$stay" = true ]; then
    e2e_expect_equal "true null" "$(jq -r '"\(.stay) \(.to)"' <<<"${line:-{\}}")" "its stay and to (a stay row)"
  else
    e2e_expect_equal "false $to" "$(jq -r '"\(.stay) \(.to)"' <<<"${line:-{\}}")" "its stay and to"
    e2e_expect_equal "$to" "$(en_job "$n" .state)" "job.json state after the pass"
    if [ "$(jq -r '.expect.holds_slot // empty' <<<"$w")" = false ]; then
      e2e_expect_equal false "$(en_job "$n" .holds_slot)" "holds_slot on entry to $to (T:conventions.slots)"
    fi
  fi
  got=$(printf '%s\n' "$E2E_ERR" | grep -c "^SEAM_MISSING=.* state=$s event=$e\$")
  e2e_expect_equal 0 "$got" "SEAM_MISSING lines for the witness pair"
}

EN_FAILS_BEFORE=0
en_mark() { EN_FAILS_BEFORE=$FLOW_TEST_FAIL; }
en_passed() { [ "$FLOW_TEST_FAIL" = "$EN_FAILS_BEFORE" ]; }

# ---------------------------------------------------------------- EN1, EN2, EN3
if en_run EN1; then
_flow_test_begin "every row of the table, through next, lands in its target (EN1, EN2, EN3)"
EN_ROWS_OUT="$E2E_ROOT/witness-rows.out"
en_gen rows
EN_GEN_RC=$?
e2e_new en1-generate
e2e_describe "witness.py rows: one witness per row id from the docs checker"
printf 'generator exit status: %s\n%s\n' "$EN_GEN_RC" "$(cat "$EN_ROWS_OUT.err")" | _e2e_art
e2e_expect_equal 0 "$EN_GEN_RC" "witness.py rows exit status"
EN_COVER=$(tail -n 1 "$EN_ROWS_OUT")
printf '%s\n' "$EN_COVER" | _e2e_art
# Source: the table itself (its row ids), read with jq here, and the checker
# (its wins), counted by the generator.
EN_TABLE_IDS=$(jq '[.rows[].id] | unique | length' "$EN_TABLE")
EN_WINS_IDS=$(sed -n 's/^coverage ids \([0-9]*\)\/\([0-9]*\) .*/\1 \2/p' <<<"$EN_COVER")
e2e_expect_equal "$EN_TABLE_IDS $EN_TABLE_IDS" "$EN_WINS_IDS" "the generator's witnessed ids and the table's row ids"
e2e_expect_equal 0 "$(grep -c '_flow_factory\|plugins/flow/bin' "$EN_WITNESS")" "witness.py names nothing under bin/ (EN3)"

EN_COVERED=""
EN_SUMMARY="$E2E_ROOT/en1-summary.txt"
: > "$EN_SUMMARY"
while IFS= read -r EN_W; do
  case "$EN_W" in '{'*) ;; *) continue ;; esac
  EN_ID=$(jq -r .id <<<"$EN_W")
  if [ -n "${EN_IDS:-}" ]; then
    case " $EN_IDS " in *" $EN_ID "*) ;; *) continue ;; esac
  fi
  en_mark
  fe_new "en1-row-$EN_ID"
  # Source: docs/flow-factory/check_transitions.py's Checker over the table
  # (the witness's row wins its pair under its assignment); plan T13 seeds.
  e2e_describe "row $EN_ID: $(jq -r '"\(.state) \(.event) -> \(.to_text)"' <<<"$EN_W")"
  en_scenario_start "$(jq -r 'if .seed.stale_probes then "d[\"groups\"][\"platform\"][\"keyed_on\"][\"claude_version\"] = \"2.1.300 (Claude Code)\"" else "" end' <<<"$EN_W")"
  en_seed "$EN_W"
  EN_WL=$(jq -r .seed.worker_launch <<<"$EN_W")
  [ "$EN_WL" = true ] && en_worker_plugin "$(jq -r .state <<<"$EN_W")"
  fe_e "$E2E_DIR/fixture.json" next --executor headless
  e2e_expect_equal 0 "$E2E_RC" "next exit status ($(printf '%s' "$E2E_OUT$E2E_ERR" | tr '\n' ' ' | cut -c1-300))"
  en_expect_witness "$EN_W" "$(en_pass)"
  if [ "$EN_WL" = true ]; then
    EN_D=$(en_job 7 .directive)
    e2e_expect_equal 1 "$(jq -r '"\(.kind == "worker")"' "$EN_F/jobs/issue-7/directives/$EN_D.json" 2>/dev/null | grep -c true)" "a worker directive was created"
    fe_wait_for 45 "[ -f '$EN_F/jobs/issue-7/results/$EN_D.json' ]"
    EN_LP=$(jq -r '.launcher_pid // empty' "$EN_F/jobs/issue-7/directives/$EN_D.lease.json" 2>/dev/null)
    [ -n "$EN_LP" ] && fe_wait_for 15 "! kill -0 $EN_LP 2>/dev/null"
    e2e_expect_equal 1 "$(en_launches)" "claude launches"
  else
    e2e_expect_equal 0 "$(en_launches)" "claude launches (no worker launch for this row)"
  fi
  EN_BODY=$(jq -r '.seed.bodies | keys[0] // empty' <<<"$EN_W")
  if [ -n "$EN_BODY" ]; then
    EN_D=$(en_job 7 .directive)
    e2e_expect_equal "${EN_BODY%%:*}" "$(jq -r .kind "$EN_F/jobs/issue-7/directives/$EN_D.json" 2>/dev/null)" "the directive's kind"
    e2e_expect_equal 1 "$(find "$EN_F/jobs/issue-7/results" -name "$EN_D.json" 2>/dev/null | wc -l | tr -d ' ')" "the body's result written inline (plan 2.11 kind 4)"
  fi
  fe_art_state 7
  if en_passed; then
    EN_COVERED="$EN_COVERED $EN_ID"
    printf '%s %s %s -> %s\n' "$EN_ID" "$(jq -r .state <<<"$EN_W")" "$(jq -r .event <<<"$EN_W")" \
      "$(jq -r 'if .expect.stay then "stay" else .expect.to end' <<<"$EN_W")" >> "$EN_SUMMARY"
  fi
done < "$EN_ROWS_OUT"
fi

# ---------------------------------------------------------------- EN9 (row 1)
if en_run EN1 || en_run EN9; then
_flow_test_begin "creation row 1: created under E with the conditions, fenced in the shipped engine (EN9)"
en_mark
EN_ISSUES_KEY='api_repos_flow-e2e_scratch_issues?labels=flow:factory&state=open&per_page=100'
EN_ISSUE9='[{"number": 9, "state": "open", "labels": [{"name": "flow:factory"}], "updated_at": "2026-11-16T10:00:00Z"}]'
fe_new en9a-row-1-created
# Source: amendment C.1 and plan T13 row 1 (job issue-9-j1 in queued,
# vouch_at the issue's updated_at, a created event with row 1).
e2e_describe "an open issue 9 labelled flow:factory and no job; seam creation_allowed true"
en_scenario_start
fe_gh "$EN_ISSUES_KEY" "$EN_ISSUE9"
printf '%s\n' '{"unbuilt": {"*": {"creation_allowed": true}}}' > "$E2E_DIR/fixture.json"
fe_e "$E2E_DIR/fixture.json" next --executor headless
e2e_expect_equal 0 "$E2E_RC" "next exit status ($E2E_ERR)"
e2e_expect_equal "issue-9-j1 queued 2026-11-16T10:00:00Z" "$(en_job 9 '"\(.key) \(.state) \(.vouch_at)"')" "job issue-9-j1 key, state, vouch_at"
e2e_expect_equal "created 1 queued" "$(jq -r 'select(.type == "created") | "\(.type) \(.row) \(.to)"' "$EN_F/jobs/issue-9/events.jsonl" 2>/dev/null)" "the created event"
fe_art_state 9

fe_new en9b-row-1-not-allowed
# Source: plan T13 row 1 (with creation_allowed false there is no job).
e2e_describe "the same issue; seam creation_allowed false"
en_scenario_start
fe_gh "$EN_ISSUES_KEY" "$EN_ISSUE9"
printf '%s\n' '{"unbuilt": {"*": {"creation_allowed": false}}}' > "$E2E_DIR/fixture.json"
fe_e "$E2E_DIR/fixture.json" next --executor headless
e2e_expect_equal 0 "$E2E_RC" "next exit status ($E2E_ERR)"
e2e_expect_equal no "$([ -e "$EN_F/jobs/issue-9" ] && echo yes || echo no)" "a job folder for issue 9"

fe_new en9c-row-1-fenced
# Source: plan 2.11 fence (creation row 1 is fenced through creation_allowed,
# phase 1b); T11 (outside E a fenced creation leaves no job folder, only the
# BLOCKED_UNBUILT status line).
e2e_describe "the same issue through the shipped wrapper, enabled"
en_scenario_start
fe_gh "$EN_ISSUES_KEY" "$EN_ISSUE9"
e2e_run_bin bin/flow-factory.sh next --executor headless
e2e_expect_equal 0 "$E2E_RC" "next exit status ($E2E_ERR)"
e2e_expect_line '{"status":"BLOCKED_UNBUILT job=issue-9-j1 state=none event=issue_labelled fact=creation_allowed phase=1b"}'
e2e_expect_equal no "$([ -e "$EN_F/jobs/issue-9" ] && echo yes || echo no)" "a job folder for issue 9"
en_passed && EN_COVERED="$EN_COVERED 1"
fi

# ---------------------------------------------------------------- EN1 count
if en_run EN1; then
_flow_test_begin "every row id of the table is driven (EN1)"
e2e_new en1-coverage
# Source: the table's row ids plus creation row 1, counted here with jq.
EN_ALL=$(jq '([.rows[].id] + [.creation[].id]) | unique | length' "$EN_TABLE")
EN_N=$(printf '%s\n' $EN_COVERED | grep -c .)
EN_MISSING=$(comm -23 <(jq -r '([.rows[].id] + [.creation[].id]) | unique | .[]' "$EN_TABLE" | sort) \
  <(printf '%s\n' $EN_COVERED | sort))
e2e_describe "the ids whose scenario passed, against the table's ids"
{
  printf 'ids %s/%s %s\n' "$EN_N" "$EN_ALL" "$(sed -n 's/^coverage ids [0-9/]* //p' <<<"${EN_COVER:-}")"
  cat "$EN_SUMMARY" 2>/dev/null
  printf '1 none issue_labelled -> queued\n'
} | _e2e_art
e2e_expect_equal "$EN_ALL" "$EN_N" "row ids driven to their target (missing: $(printf '%s' "$EN_MISSING" | tr '\n' ' '))"
printf 'en1: ids %s/%s\n' "$EN_N" "$EN_ALL"
fi

# ---------------------------------------------------------------- EN4
if en_run EN4; then
_flow_test_begin "derived precedence through next: the pre-push failure wins over the confirm park (EN4, RM2)"
fe_new en4-rm2
# Source: journal RM2; T:21f (open_pr stage_succeeded, prepush_protected_failed
# true, precedence 44, needs_human, no push) and T:40 (blocking_write_confirm,
# precedence 45); plan 2.11 choose() step 4 (the pre-push check comes first).
e2e_describe "open_pr with a stage success; derived inputs: push and PR create or edit resolve to confirm, and the pre-push check fails"
en_gen row 21f open_pr
EN_W=$(cat "$E2E_ROOT/witness-row.out")
en_scenario_start
en_seed "$EN_W"
jq -c '.derived_inputs = {"confirm_keys": ["push", "PR create or edit"], "prepush_fails": true}' "$E2E_DIR/fixture.json" > "$E2E_DIR/fixture.t" \
  && mv "$E2E_DIR/fixture.t" "$E2E_DIR/fixture.json"
fe_e "$E2E_DIR/fixture.json" next --executor headless
e2e_expect_equal 0 "$E2E_RC" "next exit status ($E2E_ERR)"
EN_L=$(en_line 7 "$(en_pass)" stage_succeeded)
e2e_expect_equal "21f needs_human" "$(jq -r '"\(.row) \(.to)"' <<<"${EN_L:-{\}}")" "row and target"
e2e_expect_equal needs_human "$(en_job 7 .state)" "job.json state"
e2e_expect_equal 0 "$(find "$EN_F/jobs/issue-7/outbox" -type f 2>/dev/null | wc -l | tr -d ' ')" "outbox items (no push intent)"
fe_art_state 7
fi

# ---------------------------------------------------------------- EN5
if en_run EN5; then
_flow_test_begin "a pending change survives a move and applies in the new state (EN5, R16)"
fe_new en5-pending-across-move
# Source: T:conventions.event_order (a change seen in the same pass as a move
# is applied in a later pass, in the job's new state); e2e_tests L30; the
# table's expectation cancel_signal_cancels.
e2e_describe "needs_spec_approval with a pending person_approve_spec and pending_changes [cancel_signal]; seam cancel_signal true; two passes"
en_gen rows
EN_W=$(grep '^{' "$E2E_ROOT/witness-rows.out" | jq -c 'select(.event == "person_approve_spec" and .expect.stay != true)' | head -n 1)
EN_TO=$(jq -r .expect.to <<<"$EN_W")
en_scenario_start
en_seed "$(jq -c '.seed.job.pending_changes = ["cancel_signal"]' <<<"$EN_W")"
jq -c '.unbuilt["issue-7-j1"].cancel_signal = true | .default_unbuilt = false' "$E2E_DIR/fixture.json" > "$E2E_DIR/fixture.t" \
  && mv "$E2E_DIR/fixture.t" "$E2E_DIR/fixture.json"
fe_e "$E2E_DIR/fixture.json" next --executor headless
e2e_expect_equal 0 "$E2E_RC" "pass 1 exit status ($E2E_ERR)"
EN_P1=$(en_pass)
e2e_expect_equal "$(jq -r .expect.row <<<"$EN_W") $EN_TO" "$(jq -r '"\(.row) \(.to)"' <<<"$(en_line 7 "$EN_P1" person_approve_spec)")" "pass 1: the approval's row and target"
e2e_expect_equal '["cancel_signal"]' "$(en_job 7 '.pending_changes | tostring')" "pass 1: cancel_signal still pending"
e2e_expect_equal "" "$(en_line 7 "$EN_P1" github_change)" "pass 1: no github_change line"
fe_e "$E2E_DIR/fixture.json" next --executor headless
e2e_expect_equal 0 "$E2E_RC" "pass 2 exit status ($E2E_ERR)"
e2e_expect_equal "$EN_TO cancelled" "$(jq -r '"\(.from) \(.to)"' <<<"$(en_line 7 "$(en_pass)" github_change)")" "pass 2: the change applies from the new state"
e2e_expect_equal cancelled "$(en_job 7 .state)" "job.json state"
fe_art_state 7
fi

# ---------------------------------------------------------------- EN6
if en_run EN6; then
_flow_test_begin "a person's cancel and a merge in the same pass: the merge wins (EN6, pass_first)"
fe_new en6-pass-first
# Source: T:pass_first (github_change with pr_merged_by_person true applies
# row 54 before every event of event_order); e2e_tests L21.
e2e_describe "build with PR 12; a pending person_cancel; the sync shows the PR merged"
en_gen row 54 build
EN_W=$(cat "$E2E_ROOT/witness-row.out")
en_scenario_start
en_seed "$EN_W"
mkdir -p "$EN_F/jobs/issue-7/pending"
jq -n '{event: "person_cancel", args: {}, channel: "terminal", caller: {pid: 4242, start: "Mon Nov 16 00:00:00 2026", ancestry: [4242, 1]},
  facts: {unvouched_session_action: false}, raised_at: "2026-11-16T00:00:00Z"}' > "$EN_F/jobs/issue-7/pending/00000000000000000001-person_cancel.json"
jq -c '.default_unbuilt = false' "$E2E_DIR/fixture.json" > "$E2E_DIR/fixture.t" && mv "$E2E_DIR/fixture.t" "$E2E_DIR/fixture.json"
fe_e "$E2E_DIR/fixture.json" next --executor headless
e2e_expect_equal 0 "$E2E_RC" "next exit status ($E2E_ERR)"
e2e_expect_equal "54 merged" "$(jq -r 'select(.type == "transition") | "\(.row) \(.to)"' "$EN_F/jobs/issue-7/events.jsonl" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')" "every transition of the pass"
e2e_expect_equal merged "$(en_job 7 .state)" "job.json state"
fe_art_state 7
fi

# ---------------------------------------------------------------- EN7
if en_run EN7; then
_flow_test_begin "an off-table move is refused with exit 3 and changes nothing (EN7)"
fe_new en7-off-table
# Source: plan 3.7(2) and 2.6 (TRANSITION_REFUSED=<from>-><to>: resume_state
# not recorded by a parking row, exit 3); T:41b's resume list has no ready.
e2e_describe "waiting_operator with reason tier_confirm and resume_state ready, and the seeds of row 41b's witness"
en_gen row 41b waiting_operator
EN_W=$(cat "$E2E_ROOT/witness-row.out")
e2e_expect_equal no "$(jq -r '.rows[] | select(.id == "41b") | .resume | index("ready") | if . == null then "no" else "yes" end' "$EN_TABLE")" "ready is in row 41b's resume list"
en_scenario_start
en_seed "$(jq -c '.seed.job.reason = "tier_confirm" | .seed.job.resume_state = "ready"' <<<"$EN_W")"
EN_E=$(jq -r .event <<<"$EN_W")
EN_SHA=$(_e2e_sha256 "$EN_F/jobs/issue-7/job.json")
fe_e "$E2E_DIR/fixture.json" next --executor headless
e2e_expect_equal 3 "$E2E_RC" "next exit status"
e2e_expect_line '{"status":"TRANSITION_REFUSED=waiting_operator->ready: resume_state not recorded by a parking row"}'
e2e_expect_equal "TRANSITION_REFUSED=waiting_operator->ready: resume_state not recorded by a parking row" \
  "$(jq -r 'select(.type == "refused") | .line' "$EN_F/jobs/issue-7/events.jsonl" 2>/dev/null)" "the refused event's line"
e2e_expect_equal "" "$(en_line 7 "$(en_pass)" "$EN_E")" "no transition line"
e2e_expect_equal "$EN_SHA" "$(_e2e_sha256 "$EN_F/jobs/issue-7/job.json")" "job.json sha256"
fe_art_state 7
fi

# ---------------------------------------------------------------- ENC
if en_run ENC; then
_flow_test_begin "a fact assignment the dependencies forbid, with no winning row, is refused (ENC, plan 3.7(3))"
en_gen contradictions
EN_C_RC=$?
EN_C_OUT="$E2E_ROOT/witness-contradictions.out"
e2e_new enc-search
e2e_describe "witness.py contradictions: per (state, event) pair, an assignment the dependencies forbid with no top row and no agreeing no_move_ok"
printf 'generator exit status: %s\n%s\n' "$EN_C_RC" "$(cat "$EN_C_OUT")" | _e2e_art
e2e_expect_equal 0 "$EN_C_RC" "witness.py contradictions exit status"
if [ "$(tail -n 1 "$EN_C_OUT")" = "contradictions 0" ]; then
  printf 'no reachable contradiction in this table\n' | _e2e_art
fi
while IFS= read -r EN_W; do
  case "$EN_W" in '{'*) ;; *) continue ;; esac
  EN_N=$(jq -r .issue <<<"$EN_W")
  fe_new "enc-$(jq -r '"\(.state)-\(.event)"' <<<"$EN_W")"
  # Source: plan 2.6 and 3.7(3) (TRANSITION_REFUSED=<state>->?: no row wins
  # for event <event>, exit 3, nothing moves); the checker's rows and
  # no_move_ok entries for the pair.
  e2e_describe "$(jq -r '"\(.state) \(.event) under \(.assignment | tostring)"' <<<"$EN_W")"
  en_scenario_start
  en_seed "$EN_W"
  EN_S=$(jq -r .state <<<"$EN_W"); EN_E=$(jq -r .event <<<"$EN_W")
  fe_e "$E2E_DIR/fixture.json" next --executor headless
  e2e_expect_equal 3 "$E2E_RC" "next exit status ($(printf '%s' "$E2E_ERR" | tr '\n' ' ' | cut -c1-200))"
  e2e_expect_line "{\"status\":\"$(jq -r .expect.refused <<<"$EN_W")\"}"
  e2e_expect_equal "" "$(en_line "$EN_N" "$(en_pass)" "$EN_E")" "no $EN_E transition line"
  e2e_expect_equal "$EN_S" "$(en_job "$EN_N" .state)" "job.json state"
  e2e_expect_equal 0 "$(en_launches)" "claude launches"
  fe_art_state "$EN_N"
done < "$EN_C_OUT"
fi

# ---------------------------------------------------------------- EN8
if en_run EN8; then
_flow_test_begin "the fence: the shipped next evaluates no unbuilt fact, with a seam planted (EN8, R22)"
fe_new en8-fence
# Source: plan 2.11 (fence; Blocked on the first unbuilt fact in sorted order
# of facts_read; the provider list) and plan 3.3; the fact and its phase are
# computed by witness.py from the table and the plan's 1a provider list.
e2e_describe "shipped flow-factory.sh next, enabled; F/seam.json holds a fixture and FLOW_FACTORY_SEAM names it; job 7 due in build"
en_gen fence build launch_due
EN_FENCE=$(cat "$E2E_ROOT/witness-fence.out")
e2e_expect_equal "cost_cap_reached 1g" "$EN_FENCE" "the first unbuilt fact of (build, launch_due) and its phase, from the table"
en_scenario_start
fe_job 7 build "d['build_started'] = True"
fe_job_clone 7
printf '%s\n' '{"default_unbuilt": false, "bodies": {"worker:build": "succeeded"}}' > "$EN_F/seam.json"
e2e_run_bin "FLOW_FACTORY_SEAM=$EN_F/seam.json" "FLOW_FACTORY_FIXTURES=$EN_F/seam.json" bin/flow-factory.sh next --executor headless
e2e_expect_equal 0 "$E2E_RC" "next exit status ($E2E_ERR)"
EN_LINE="BLOCKED_UNBUILT job=issue-7-j1 state=build event=launch_due fact=${EN_FENCE% *} phase=${EN_FENCE#* }"
e2e_expect_line "{\"status\":\"$EN_LINE\"}"
e2e_expect_equal build "$(en_job 7 .state)" "job.json state"
e2e_expect_equal "null" "$(en_job 7 .directive)" "job.json directive"
e2e_expect_equal 0 "$(find "$EN_F/jobs/issue-7/directives" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')" "directive files"
e2e_expect_equal 0 "$(jq -c 'select(.type == "transition")' "$EN_F/jobs/issue-7/events.jsonl" 2>/dev/null | wc -l | tr -d ' ')" "transition lines"
e2e_expect_equal "build launch_due ${EN_FENCE% *} ${EN_FENCE#* }" \
  "$(jq -r 'select(.type == "blocked_unbuilt") | "\(.state) \(.event) \(.fact) \(.phase)"' "$EN_F/jobs/issue-7/events.jsonl" 2>/dev/null)" "the blocked_unbuilt event"
e2e_expect_equal 0 "$(en_launches)" "claude launches"
e2e_run_bin bin/flow-factory.sh status
e2e_expect_equal 0 "$E2E_RC" "status exit status ($E2E_ERR)"
e2e_expect_line "$EN_LINE"
fe_art_state 7
fi

printf 'e2e-factory-engine: %s s\n' "$((SECONDS - EN_T0))"
