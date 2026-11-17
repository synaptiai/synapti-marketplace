# shellcheck shell=bash
# flow-test: alone
# The factory's `next` pass (bin/_flow_factory_next.py, plan 1a T11): the
# sync, the stored events in the table's order, lease liveness and crash
# recovery, the relaunch kinds, slots, launches, the output protocol and the
# time budget. Most scenarios run `next` through the test entry point (E,
# fe_e) with the ordinary seam fixture, and the launches it starts go
# through the shipped wrapper and the real launcher, with the worker claude
# stand-in in place of claude. The file measures time, so it runs alone.
#
# Ways it can be wrong, written down before the checks:
#   NX1  two `next` calls launch twice, or one waits past the budget (RM5)
#   NX2  a hung gh keeps `next` past its budget, or its process is left
#   NX3  a killed claude is not relaunched, or relaunches with the wrong kind:
#        resume keyed on "a session id exists" after a dirty tree, or the
#        snapshot loses the untracked file (RM3, R7); the per-run limit is
#        not a third of the stage budget less the allowance (A.10)
#   NX4  a killed or stopped launcher never expires
#   NX16 a run whose launcher died is not charged, or is charged twice
#   NX5  a sleeping laptop's stale heartbeat kills a live worker (A+11)
#   NX6  a third run does not launch, or the third failure does not park
#        (43a, 43l)
#   NX7  an orphan group does not block, or a reused pgid is treated as alive
#        or killed (A+8)
#   NX8  a group not gone does not park
#   NX9  slots are not freed on entry to a terminal state (R17)
#   NX10 a normal report does not move the job (R6)
#   NX-AC8 the shell's pending report is not applied, or a forged one is, or
#        it is charged the session total (R26, RM4)
#   NX-AC7 a real worker's person command is not refused
#   NX11 a usage limit counts an attempt or launches
#   NX12 a judge is launched as a process in 1a
#   NX13 a probe's lock blocks `next` (R19)
#   NX14 the output protocol is broken
#   NX15 a terminal job's refs are not copied
#
# Amounts are compared in whole cents through jq. Elapsed times go to stdout,
# not to the artifacts, so the artifacts stay the same from run to run.
#
# NX_ONLY=<id> (NX1 ... NX16, NXAC7, NXAC8) runs only that scenario.

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}
# shellcheck source=lib/factory-e2e.sh
source "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh"

nx_run() { [ -z "${NX_ONLY:-}" ] || [ "$NX_ONLY" = "$1" ]; }
nx_now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
nx_secs() { perl -e 'printf "%.2f", $ARGV[1] - $ARGV[0]' "$1" "$2"; }
nx_le() { perl -e 'exit(($ARGV[0] <= $ARGV[1]) ? 0 : 1)' "$1" "$2" && echo yes || echo "no ($1 s)"; }

D1=issue-7-j1-build-1
D2=issue-7-j1-build-2
D3=issue-7-j1-build-3

# nx_settings <jq expression> — apply it to the scratch user settings.
nx_settings() {
  local f="$E2E_HOME/.claude/settings.flow.json" cur='{}'
  [ -f "$f" ] && cur=$(cat "$f")
  e2e_user_settings "$(printf '%s' "$cur" | jq -c "$1")"
}

# nx_plugin <build template text> — a plugin copy holding
# templates/factory/build.prompt.md with that text.
nx_plugin() { e2e_plugin_copy templates/factory/build.prompt.md "$1"; }

# nx_seed [job edits] — the base seeds: the main checkout, a probe record,
# the factory enabled, job issue-7-j1 in build and its clone.
nx_seed() {
  # A scenario that needed the repository earlier (NX7) has made it already.
  [ -n "${E2E_REPO:-}" ] && [ "${E2E_REPO#"$E2E_DIR"/}" != "$E2E_REPO" ] && [ -d "$E2E_REPO/.git" ] || e2e_repo main
  fe_record "${NX_RECORD_EDITS:-}"
  fe_enable
  fe_job 7 build "${1:-}"
  fe_job_clone 7
  NX_F=$(fe_factory_dir)
  NX_J="$NX_F/jobs/issue-7"
}

# nx_next [fixture] — `next --executor headless` through E, then the output
# protocol check (NX14c): every line but the last parses as JSON, and the
# last is wait, idle or done.
nx_next() {
  local t0 t1
  t0=$(nx_now)
  fe_e "${1:-${NX_FIX:-ordinary.json}}" next --executor headless
  t1=$(nx_now)
  NX_ELAPSED=$(nx_secs "$t0" "$t1")
  nx_protocol "$E2E_OUT"
}
nx_protocol() {
  local bad="" l last
  last=$(printf '%s\n' "$1" | tail -n 1)
  while IFS= read -r l; do
    [ -n "$l" ] || { bad="$bad <empty line>"; continue; }
    printf '%s' "$l" | jq -e 'type == "object" and (.status | type == "string")' >/dev/null 2>&1 || bad="$bad $l"
  done < <(printf '%s\n' "$1" | sed '$d')
  e2e_expect_equal "" "$bad" "every line but the last is a status JSON line (NX14c)"
  case "$last" in wait|idle|done) last=ok ;; esac
  e2e_expect_equal ok "$last" "the last line is wait, idle or done (NX14c)"
}
nx_last() { printf '%s\n' "$E2E_OUT" | tail -n 1; }

nx_jq() { jq -r "$2" "$1" 2>/dev/null; }
nx_cents() { jq -r "($2) * 100 | round" "$1" 2>/dev/null; }
# nx_rows [n] — the transition rows of job issue-<n>'s events, space-joined.
nx_rows() { jq -r 'select(.type == "transition") | .row' "$NX_F/jobs/issue-${1:-7}/events.jsonl" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
nx_ev_count() { jq -c "select($2)" "$NX_F/jobs/issue-${1}/events.jsonl" 2>/dev/null | wc -l | tr -d ' '; }
nx_lease() { jq -r ".$2 // empty" "$NX_J/directives/$1.lease.json" 2>/dev/null; }
nx_launches() { if [ -f "$E2E_BIN/claude-launches.log" ]; then wc -l < "$E2E_BIN/claude-launches.log" | tr -d ' '; else echo 0; fi; }
nx_arg_after() { awk -v f="$2" 'p { print; exit } $0 == f { p = 1 }' "$E2E_BIN/claude-argv-$1.txt" 2>/dev/null; }
nx_has_arg() { grep -qxF -- "$2" "$E2E_BIN/claude-argv-$1.txt" 2>/dev/null && echo yes || echo no; }
nx_directives() { find "$NX_J/directives" -name '*.json' ! -name '*.lease.json' 2>/dev/null | wc -l | tr -d ' '; }
nx_leases() { find "$NX_J/directives" -name '*.lease.json' 2>/dev/null | wc -l | tr -d ' '; }
nx_block() { awk -v n="$1" '$0 == "--- start" { k++; next } k == n' "$E2E_BIN/claude-script.out" 2>/dev/null; }

nx_wait_result() { fe_wait_for "${2:-45}" "[ -f '$NX_J/results/$1.json' ]"; }
nx_wait_child() { fe_wait_for "${2:-30}" "[ -n \"\$(jq -r '.child_pgid // empty' '$NX_J/directives/$1.lease.json' 2>/dev/null)\" ]"; }
nx_wait_launcher_gone() {
  local lp
  lp=$(nx_lease "$1" launcher_pid)
  [ -n "$lp" ] && fe_wait_for 15 "! kill -0 $lp 2>/dev/null"
}
nx_kill_group() { kill -9 -- "-$(nx_lease "$1" child_pgid)" 2>/dev/null; }
# nx_finish <directive> — wait for its result and its launcher to end.
nx_finish() { nx_wait_result "$1" "${2:-45}" && nx_wait_launcher_gone "$1"; }

NX_SUCCESS='{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.05}'

# ---------------------------------------------------------------- NX14
if nx_run NX14; then
_flow_test_begin "next: no jobs ends with done; a parked job ends with idle (NX14)"
fe_new nx14a-no-jobs
# Source: plan 2.6 next output (done: no non-terminal job exists).
e2e_describe "no job at all: next prints done and exits 0"
e2e_repo main
fe_record
fe_enable
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal done "$(nx_last)" "last line"
NX_F=$(fe_factory_dir)
e2e_expect_equal 1 "$(nx_jq "$NX_F/state.json" .pass_seq)" "state.json pass_seq after one pass"

fe_new nx14b-needs-human
# Source: plan 2.6 (idle: a non-terminal job, no lease, no open directive, no pending event).
e2e_describe "one job in needs_human: next prints idle"
e2e_repo main
fe_record
fe_enable
fe_job 7 needs_human "d['reason'] = 'attempts_exhausted'; d['blocked_stage'] = 'build'"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal idle "$(nx_last)" "last line"

fe_new nx14d-executor-required
# Source: plan T11 outline (`--executor interactive|headless` is required; usage errors exit 2 with one stderr line).
e2e_describe "next without --executor exits 2 with one stderr line and nothing on stdout"
e2e_repo main
fe_record
fe_enable
fe_e ordinary.json next
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_equal "" "$E2E_OUT" "stdout"
e2e_expect_equal 1 "$(printf '%s\n' "$E2E_ERR" | grep -c '^flow-factory.sh next: ')" "stderr usage lines"
fi

# ---------------------------------------------------------------- NX10
if nx_run NX10; then
_flow_test_begin "next: a launch, then the next pass applies the normal report (NX10, R6)"
fe_new nx10-normal-report
# Source: T:66b (launch_due in build under the ordinary fixture: cost_cap_reached,
# prelaunch_protected_failed, probes_stale, tier_confirm_blocking all false);
# T:20 (stage_succeeded in build, spec_change_needs_approval false, precedence 60;
# 20b needs it true) -> open_pr; amendment B.7, C.2.
e2e_describe "base seeds, a normal worker result; pass 1 launches, pass 2 applies stage_succeeded"
nx_seed
nx_plugin 'RUN: true'
fe_worker_says "worker-result=$NX_SUCCESS"
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 1 exit status ($E2E_ERR)"
e2e_expect_equal wait "$(nx_last)" "pass 1 last line"
e2e_expect_equal 66b "$(nx_rows)" "pass 1 rows"
e2e_expect_equal "$D1" "$(nx_jq "$NX_J/job.json" .directive)" "job.directive"
e2e_expect_equal true "$(nx_jq "$NX_J/job.json" .holds_slot)" "holds_slot after the launch"
e2e_expect_equal "first fresh worker" "$(nx_jq "$NX_J/directives/$D1.json" '"\(.cause_row) \(.start_mode) \(.kind)"')" "directive cause_row, start_mode, kind"
nx_finish "$D1"
e2e_expect_equal completed "$(nx_jq "$NX_J/results/$D1.json" .outcome)" "result outcome"
e2e_expect_equal 1 "$(find "$NX_J/pending" -name '*-stage_succeeded.json' | wc -l | tr -d ' ')" "pending stage_succeeded before pass 2"
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 2 exit status ($E2E_ERR)"
e2e_expect_equal "66b 20" "$(nx_rows)" "rows after pass 2"
e2e_expect_equal open_pr "$(nx_jq "$NX_J/job.json" .state)" "state"
e2e_expect_equal 0 "$(find "$NX_J/pending" -name '*.json' | wc -l | tr -d ' ')" "pending files after pass 2"
e2e_expect_equal 1 "$(nx_launches)" "claude launches"
fe_art_state 7
fi

# ---------------------------------------------------------------- NX1
if nx_run NX1; then
_flow_test_begin "next: two passes started together launch one worker, each within the budget (NX1, AC4, RM5)"
fe_new nx1-two-passes
# Source: journal RM5; plan T11 Phase C ("One spawn for two next calls").
e2e_describe "one job due, concurrency 1, nextBudgetSeconds 10, the stand-in sleeps 5 s; two next started together"
nx_seed
nx_plugin 'RUN: true'
nx_settings '.flow.factory.concurrency = 1 | .flow.factory.nextBudgetSeconds = 10'
fe_worker_says "worker-result=$NX_SUCCESS" worker-sleep=5
NX_T0=$(nx_now)
fe_bg n1 fe_e ordinary.json next --executor headless
fe_bg n2 fe_e ordinary.json next --executor headless
fe_bg_wait n1 15
fe_bg_wait n2 15
NX_E1=$(nx_secs "$NX_T0" "$(stat -f %m "$E2E_DIR/bg-n1.rc")")
NX_E2=$(nx_secs "$NX_T0" "$(stat -f %m "$E2E_DIR/bg-n2.rc")")
printf 'NX1 elapsed: n1 %s s, n2 %s s\n' "$NX_E1" "$NX_E2"
fe_wait_for 15 "[ -f '$NX_J/directives/$D1.lease.json' ]"
nx_finish "$D1" 30
printf 'directives: %s, leases: %s, launches: %s\n' "$(nx_directives)" "$(nx_leases)" "$(nx_launches)" | _e2e_art
e2e_expect_equal 1 "$(nx_directives)" "directives"
e2e_expect_equal 1 "$(nx_leases)" "leases"
e2e_expect_equal 1 "$(nx_launches)" "claude launches"
e2e_expect_equal 1 "$(nx_ev_count 7 '.type == "transition" and .row == "66b"')" "row 66b lines"
e2e_expect_equal 1 "$(nx_jq "$NX_J/job.json" .stage_launches.build)" "stage_launches.build"
e2e_expect_equal 0 "$(cat "$E2E_DIR/bg-n1.rc")" "n1 exit status"
e2e_expect_equal 0 "$(cat "$E2E_DIR/bg-n2.rc")" "n2 exit status"
nx_protocol "$(cat "$E2E_DIR/bg-n1.out")"
nx_protocol "$(cat "$E2E_DIR/bg-n2.out")"
e2e_expect_equal wait "$(tail -n 1 "$E2E_DIR/bg-n1.out")" "n1 last line"
e2e_expect_equal wait "$(tail -n 1 "$E2E_DIR/bg-n2.out")" "n2 last line"
NX_W1=$(nx_le "$NX_E1" 12); NX_W2=$(nx_le "$NX_E2" 12)
[ "$NX_W1$NX_W2" = yesyes ] && NX_W=yes || NX_W="no: $NX_W1 / $NX_W2"
printf 'both within budget: %s\n' "$( [ "$NX_W" = yes ] && echo yes || echo no)" | _e2e_art
e2e_expect_equal yes "$NX_W" "both passes ended within 12 s of their start"
fi

# ---------------------------------------------------------------- NX2
if nx_run NX2; then
_flow_test_begin "next: a hung gh call is cut at the budget and leaves no process (NX2, AC4)"
fe_new nx2-hung-gh
# Source: execution_model L56; plan T11 Sync (timeout min(15, left - 2); a call
# that times out leaves last_sync_at unchanged).
e2e_describe "job 7 has PR 12; nextBudgetSeconds 4; the PR call hangs 30 s"
nx_seed "d['pr'] = 12; d['head_sha'] = 'a' * 40"
nx_plugin 'RUN: true'
nx_settings '.flow.factory.nextBudgetSeconds = 4'
fe_gh api_repos_flow-e2e_scratch_pulls_12 "hang 30"
nx_next
printf 'NX2 elapsed: %s s\n' "$NX_ELAPSED"
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal yes "$(nx_le "$NX_ELAPSED" 5)" "next returned within 5 s"
e2e_expect_equal null "$(nx_jq "$NX_F/state.json" .last_sync_at)" "last_sync_at unchanged"
NX_LEFT=""
while IFS= read -r NX_P; do
  [ -n "$NX_P" ] && kill -0 "$NX_P" 2>/dev/null && NX_LEFT="$NX_LEFT $NX_P"
done < "$E2E_BIN/fe-gh-pids"
e2e_expect_equal "" "$NX_LEFT" "gh stub processes still running"
e2e_expect_equal 1 "$(grep -cxF 'api repos/flow-e2e/scratch/pulls/12' "$E2E_BIN/fe-gh-calls.log")" "PR calls in the gh log"
fi

# ---------------------------------------------------------------- NX3
if nx_run NX3; then
_flow_test_begin "next: a killed claude on a clean tree resumes; on a dirty tree relaunches fresh after a snapshot (NX3, AC5, RM3, A.10)"
fe_new nx3a-clean-resume
# Source: T:39 (stage_failed, attempts_exhausted false, tree_dirty false: attempt += 1,
# relaunch resume); amendments A.10: third = 3.00 / 3 = 1.00, run 1 limit
# min(1.00, 3.00) - 0.50 = 0.50, the killed run charged 0.50 + 0.50 = 1.00, run 2
# limit min(1.00, 3.00 - 1.00) - 0.50 = 0.50.
e2e_describe "build budget 3.00, build.prompt.md RUN: sleep 30; claude's group is killed during the sleep"
nx_seed
nx_plugin 'RUN: sleep 30'
nx_settings '.flow.factory.worker.stages.build.maxBudgetUsd = 3'
fe_worker_says
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 1 exit status ($E2E_ERR)"
NX_SID1=$(nx_jq "$NX_J/directives/$D1.json" .session_id)
fe_mask_text "$NX_SID1" "<sid1>"
nx_wait_child "$D1"
fe_wait_for 15 "[ -f '$E2E_BIN/claude-argv-1.txt' ]"
sleep 1
nx_kill_group "$D1"
nx_wait_result "$D1"
nx_wait_launcher_gone "$D1"
e2e_expect_equal 0.5 "$(nx_arg_after 1 --max-budget-usd)" "run 1 --max-budget-usd"
e2e_expect_equal 100 "$(nx_cents "$NX_J/job.json" '.cost.runs[0].charged_usd')" "run 1 charged in cents"
e2e_expect_equal limit_plus_turn "$(nx_jq "$NX_J/job.json" '.cost.runs[0].basis')" "run 1 basis"
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 2 exit status ($E2E_ERR)"
e2e_expect_equal "66b 39 66b" "$(nx_rows)" "rows after pass 2"
fe_wait_for 20 "[ -f '$E2E_BIN/claude-argv-2.txt' ]"
nx_next
e2e_expect_equal 1 "$(nx_ev_count 7 '.type == "transition" and .row == "39" and .attempt == 1')" "row 39 with attempt 1"
e2e_expect_equal "$NX_SID1" "$(nx_arg_after 2 --resume)" "run 2 --resume"
e2e_expect_equal yes "$(nx_has_arg 2 --fork-session)" "run 2 --fork-session"
e2e_expect_equal no "$(nx_has_arg 2 --session-id)" "run 2 --session-id"
e2e_expect_equal 0.5 "$(nx_arg_after 2 --max-budget-usd)" "run 2 --max-budget-usd"
e2e_expect_equal "39 resume" "$(nx_jq "$NX_J/directives/$D2.json" '"\(.cause_row) \(.start_mode)"')" "directive 2 cause_row, start_mode"
e2e_expect_equal yes "$(grep -q '^This session is a continuation of an earlier run' "$E2E_BIN/claude-stdin-2.txt" && echo yes || echo no)" "run 2 prompt is resume.prompt.md"
nx_finish "$D2"
fe_art_state 7

fe_new nx3b-dirty-fresh
# Source: T:39d (tree_dirty true: snapshot, reset, attempt += 1, relaunch FRESH);
# journal RM3; A.10 as nx3a.
e2e_describe "a.txt tracked as one; the run writes a.txt=two and an untracked new.txt, then sleeps; claude's group is killed"
nx_seed
nx_plugin 'RUN: printf two > a.txt
RUN: printf fresh > new.txt
RUN: sleep 30'
nx_settings '.flow.factory.worker.stages.build.maxBudgetUsd = 3'
NX_WT=$(nx_jq "$NX_J/job.json" .worktree)
_fe_in_scratch sh -c 'cd "$1" && printf one > a.txt && git add a.txt && git commit -q -m a' _ "$NX_WT"
fe_worker_says
printf '%s\n' "echo '--- start'" "git status --porcelain" > "$E2E_BIN/claude-script"
nx_next
NX_SID1=$(nx_jq "$NX_J/directives/$D1.json" .session_id)
fe_mask_text "$NX_SID1" "<sid1>"
nx_wait_child "$D1"
fe_wait_for 15 "[ -f '$NX_WT/new.txt' ]"
sleep 1
nx_kill_group "$D1"
nx_wait_result "$D1"
nx_wait_launcher_gone "$D1"
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 2 exit status ($E2E_ERR)"
fe_wait_for 20 "[ -f '$E2E_BIN/claude-argv-2.txt' ]"
nx_finish "$D2"
e2e_expect_equal "66b 39d 66b" "$(nx_rows)" "rows"
NX_SNAP=$(_fe_in_scratch sh -c 'cd "$1" && git ls-tree --name-only refs/flow-factory/issue-7/snapshot-1 | tr "\n" " "' _ "$NX_WT")
printf 'snapshot-1: %s\n' "$NX_SNAP" | _e2e_art
e2e_expect_equal "README.md a.txt new.txt " "$NX_SNAP" "snapshot-1 files"
e2e_expect_equal two "$(_fe_in_scratch sh -c 'cd "$1" && git show refs/flow-factory/issue-7/snapshot-1:a.txt' _ "$NX_WT")" "snapshot-1 a.txt"
NX_SID2=$(nx_arg_after 2 --session-id)
fe_mask_text "$NX_SID2" "<masked uuid 2>"
printf 'argv-2: --session-id %s\n' "$NX_SID2" | _e2e_art
e2e_expect_equal yes "$([ -n "$NX_SID2" ] && [ "$NX_SID2" != "$NX_SID1" ] && echo yes || echo no)" "run 2 --session-id is a new uuid"
e2e_expect_equal no "$(nx_has_arg 2 --resume)" "run 2 --resume"
printf '%s\n' "$( [ "$(nx_has_arg 2 --resume)" = no ] && echo 'no --resume')" | _e2e_art
e2e_expect_equal 0.5 "$(nx_arg_after 2 --max-budget-usd)" "run 2 --max-budget-usd"
e2e_expect_equal "" "$(nx_block 2)" "git status at the start of run 2"
e2e_expect_equal "39d fresh" "$(nx_jq "$NX_J/directives/$D2.json" '"\(.cause_row) \(.start_mode)"')" "directive 2 cause_row, start_mode"
fe_art_state 7
fi

# ---------------------------------------------------------------- NX4, NX16
if nx_run NX4; then
_flow_test_begin "next: a killed or stopped launcher expires its lease; the engine kills, charges once and relaunches (NX4, NX16, AC5)"
fe_new nx4a-launcher-killed
# Source: T:39l (lease_expired, group_gone true, attempts_exhausted false,
# tree_dirty false); T11 liveness steps 1-6; A.10: charge 0.50 + 0.50 = 1.00,
# relaunch limit min(1.00, 3.00 - 1.00) - 0.50 = 0.50.
e2e_describe "leaseSeconds 3, heartbeatSeconds 1, build budget 3.00, RUN: sleep 30; the launcher is SIGKILLed; next after 4 s"
nx_seed
nx_plugin 'RUN: sleep 30'
nx_settings '.flow.factory.leaseSeconds = 3 | .flow.factory.heartbeatSeconds = 1 | .flow.factory.worker.stages.build.maxBudgetUsd = 3'
fe_worker_says
nx_next
NX_SID1=$(nx_jq "$NX_J/directives/$D1.json" .session_id)
fe_mask_text "$NX_SID1" "<sid1>"
nx_wait_child "$D1"
NX_PG=$(nx_lease "$D1" child_pgid)
kill -9 "$(nx_lease "$D1" launcher_pid)"
sleep 4
nx_next
e2e_expect_equal 0 "$E2E_RC" "expiry pass exit status ($E2E_ERR)"
e2e_expect_equal yes "$([ -n "$(nx_lease "$D1" revoked_at)" ] && echo yes || echo no)" "lease revoked"
e2e_expect_equal gone "$(kill -0 -- "-$NX_PG" 2>/dev/null && echo alive || echo gone)" "claude's group"
e2e_expect_equal "66b 39l 66b" "$(nx_rows)" "rows"
e2e_expect_equal "$NX_SID1" "$(nx_jq "$NX_J/job.json" .sessions.build)" "sessions.build"
e2e_expect_equal 100 "$(nx_cents "$NX_J/job.json" '[.cost.runs[] | select(.directive == "'"$D1"'")][0].charged_usd')" "run 1 charged in cents"
e2e_expect_equal limit_plus_turn "$(nx_jq "$NX_J/job.json" '[.cost.runs[] | select(.directive == "'"$D1"'")][0].basis')" "run 1 basis"
fe_wait_for 20 "[ -f '$E2E_BIN/claude-argv-2.txt' ]"
e2e_expect_equal "$NX_SID1" "$(nx_arg_after 2 --resume)" "run 2 --resume"
e2e_expect_equal yes "$(nx_has_arg 2 --fork-session)" "run 2 --fork-session"
e2e_expect_equal 0.5 "$(nx_arg_after 2 --max-budget-usd)" "run 2 --max-budget-usd"
nx_finish "$D2"
fe_art_state 7

fe_new nx4b-launcher-killed-dirty
# Source: T:39ld (tree_dirty true: kill, snapshot, reset, attempt += 1, relaunch FRESH); A.10 as nx4a.
e2e_describe "as nx4a, but the run wrote dirty.txt in the clone before the launcher was killed"
nx_seed
nx_plugin 'RUN: printf x > dirty.txt
RUN: sleep 30'
nx_settings '.flow.factory.leaseSeconds = 3 | .flow.factory.heartbeatSeconds = 1 | .flow.factory.worker.stages.build.maxBudgetUsd = 3'
NX_WT=$(nx_jq "$NX_J/job.json" .worktree)
fe_worker_says
nx_next
NX_SID1=$(nx_jq "$NX_J/directives/$D1.json" .session_id)
fe_mask_text "$NX_SID1" "<sid1>"
nx_wait_child "$D1"
fe_wait_for 15 "[ -f '$NX_WT/dirty.txt' ]"
kill -9 "$(nx_lease "$D1" launcher_pid)"
sleep 4
nx_next
e2e_expect_equal "66b 39ld 66b" "$(nx_rows)" "rows"
e2e_expect_equal 100 "$(nx_cents "$NX_J/job.json" '[.cost.runs[] | select(.directive == "'"$D1"'")][0].charged_usd')" "run 1 charged in cents"
e2e_expect_equal dirty.txt "$(_fe_in_scratch sh -c 'cd "$1" && git ls-tree --name-only refs/flow-factory/issue-7/snapshot-1 | grep -x dirty.txt' _ "$NX_WT")" "snapshot-1 holds dirty.txt"
fe_wait_for 20 "[ -f '$E2E_BIN/claude-argv-2.txt' ]"
e2e_expect_equal no "$(nx_has_arg 2 --resume)" "run 2 --resume"
NX_SID2=$(nx_arg_after 2 --session-id)
fe_mask_text "$NX_SID2" "<sid2>"
e2e_expect_equal yes "$([ -n "$NX_SID2" ] && [ "$NX_SID2" != "$NX_SID1" ] && echo yes || echo no)" "run 2 --session-id is a new uuid"
e2e_expect_equal 0.5 "$(nx_arg_after 2 --max-budget-usd)" "run 2 --max-budget-usd"
nx_finish "$D2"
fe_art_state 7

fe_new nx4c-launcher-stopped
# Source: T11 liveness ("running": ps stat does not start with T; a stopped
# launcher gets no grace); T:39l; A.10 charge 1.00.
e2e_describe "as nx4a, but the launcher is SIGSTOPped; next at 4 s and at 6 s"
nx_seed
nx_plugin 'RUN: sleep 30'
nx_settings '.flow.factory.leaseSeconds = 3 | .flow.factory.heartbeatSeconds = 1 | .flow.factory.worker.stages.build.maxBudgetUsd = 3'
fe_worker_says
nx_next
nx_wait_child "$D1"
NX_LP=$(nx_lease "$D1" launcher_pid)
NX_PG=$(nx_lease "$D1" child_pgid)
kill -STOP "$NX_LP"
sleep 4
nx_next
sleep 2
nx_next
e2e_expect_equal 1 "$(nx_ev_count 7 '.type == "transition" and .row == "39l"')" "row 39l lines"
e2e_expect_equal gone "$(kill -0 "$NX_LP" 2>/dev/null && echo alive || echo gone)" "the stopped launcher"
e2e_expect_equal gone "$(kill -0 -- "-$NX_PG" 2>/dev/null && echo alive || echo gone)" "claude's group"
e2e_expect_equal 100 "$(nx_cents "$NX_J/job.json" '[.cost.runs[] | select(.directive == "'"$D1"'")][0].charged_usd')" "run 1 charged in cents"
kill -CONT "$NX_LP" 2>/dev/null
kill -9 "$NX_LP" 2>/dev/null
fe_wait_for 20 "[ -f '$E2E_BIN/claude-argv-2.txt' ]"
nx_finish "$D2"
fe_art_state 7
fi

if nx_run NX16; then
_flow_test_begin "next: a run whose launcher died is charged once, in the expiry pass (NX16, A.10)"
fe_new nx16-charge-once
# Source: plan 2.14 charge_run basis limit_plus_turn: limit min(1.00, 3.00) - 0.50 = 0.50,
# charged 0.50 + 0.50 = 1.00; T11 liveness step 5 (charged in the same job-lock hold as row 39l).
e2e_describe "the nx4a setup; the launcher is killed; next after 4 s, then next twice more"
nx_seed
nx_plugin 'RUN: sleep 30'
nx_settings '.flow.factory.leaseSeconds = 3 | .flow.factory.heartbeatSeconds = 1 | .flow.factory.worker.stages.build.maxBudgetUsd = 3'
fe_worker_says
nx_next
NX_SID1=$(nx_jq "$NX_J/directives/$D1.json" .session_id)
fe_mask_text "$NX_SID1" "<sid1>"
nx_wait_child "$D1"
kill -9 "$(nx_lease "$D1" launcher_pid)"
sleep 4
nx_next
NX_PASS=$(jq -r 'select(.type == "transition" and .row == "39l") | .pass' "$NX_J/events.jsonl")
e2e_expect_equal absent "$([ -e "$NX_J/results/$D1.json" ] && echo present || echo absent)" "results file of directive 1"
e2e_expect_equal 1 "$(nx_jq "$NX_J/job.json" '[.cost.runs[] | select(.directive == "'"$D1"'")] | length')" "cost.runs entries for directive 1"
e2e_expect_equal "100 limit_plus_turn $NX_SID1" "$(nx_jq "$NX_J/job.json" '[.cost.runs[] | select(.directive == "'"$D1"'")][0] | "\(.charged_usd * 100 | round) \(.basis) \(.session_id)"')" "directive 1 charge"
e2e_expect_equal "$NX_PASS" "$(jq -r 'select(.type == "charge" and .directive == "'"$D1"'") | .pass' "$NX_J/events.jsonl")" "the charge event is in the row 39l pass"
nx_finish "$D2"
nx_next
nx_next
e2e_expect_equal 1 "$(nx_jq "$NX_J/job.json" '[.cost.runs[] | select(.directive == "'"$D1"'")] | length')" "cost.runs entries for directive 1 after two more passes"
e2e_expect_equal 1 "$(nx_ev_count 7 '.type == "charge" and .directive == "'"$D1"'"')" "charge events for directive 1"
e2e_expect_equal 100 "$(nx_jq "$NX_J/job.json" '((.cost.stage_usd.build) - ([.cost.runs[] | select(.directive != "'"$D1"'") | .charged_usd] | add // 0)) * 100 | round')" "stage_usd.build less the later runs, in cents"
fe_art_state 7
fi

# ---------------------------------------------------------------- NX5
if nx_run NX5; then
_flow_test_begin "next: a stale heartbeat from a live launcher gets one heartbeat of grace (NX5, A+11)"
fe_new nx5-sleep-grace
# Source: amendment A+11; T11 liveness (a live, running launcher with no grace set:
# lease_grace = now + heartbeatSeconds, nothing raised).
e2e_describe "heartbeatSeconds 4, leaseSeconds 3; pass 1 runs right after the test rewrites heartbeat_at 10 s into the past; pass 2 4.5 s after the beat the test saw"
nx_seed
nx_plugin 'RUN: sleep 30'
nx_settings '.flow.factory.leaseSeconds = 3 | .flow.factory.heartbeatSeconds = 4 | .flow.factory.syncIntervalSeconds = 60'
fe_worker_says
nx_next
nx_wait_child "$D1"
NX_L="$NX_J/directives/$D1.lease.json"
NX_HB=$(nx_lease "$D1" heartbeat_at)
fe_wait_for 10 "[ \"\$(jq -r .heartbeat_at '$NX_L' 2>/dev/null)\" != '$NX_HB' ]"
NX_TOBS=$(nx_now)
NX_OLD=$(perl -MPOSIX=strftime -e 'print strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(time - 10))')
jq --arg t "$NX_OLD" '.heartbeat_at = $t' "$NX_L" > "$NX_L.t" && mv "$NX_L.t" "$NX_L"
nx_next
printf 'NX5 pass 1 elapsed: %s s\n' "$NX_ELAPSED"
e2e_expect_equal yes "$(nx_le "$NX_ELAPSED" 2.99)" "pass 1 ran within the 3 s margin (else the scenario is invalid)"
e2e_expect_equal 0 "$(nx_ev_count 7 '.type == "transition" and .event == "lease_expired"')" "lease_expired after pass 1"
e2e_expect_equal yes "$([ -n "$(nx_jq "$NX_J/job.json" '.lease_grace // empty')" ] && echo yes || echo no)" "lease_grace set by pass 1"
# Pass 2 runs 4.5 s after the observed beat: the launcher's next beat
# (about 4 s after it) has been written, and heartbeat_at is written to the
# second, so pass 2 sees it at most about 1.5 s old plus its own start-up,
# under leaseSeconds 3.
perl -MTime::HiRes=time,sleep -e 'my $d = $ARGV[0] + 4.5 - time; sleep($d) if $d > 0' "$NX_TOBS"
nx_next
e2e_expect_equal 0 "$(nx_ev_count 7 '.type == "transition" and .event == "lease_expired"')" "lease_expired after pass 2"
e2e_expect_equal 0 "$(nx_jq "$NX_J/job.json" .attempt)" "attempt"
e2e_expect_equal 1 "$(nx_launches)" "claude launches"
e2e_expect_equal null "$(jq -r .revoked_at "$NX_L")" "revoked_at"
fe_art_state 7
fi

# ---------------------------------------------------------------- NX6
if nx_run NX6; then
_flow_test_begin "next: three killed runs of a stage, the third failure parks (NX6, A.10)"
nx6_setup() {
  nx_seed "d['attempt'] = 0"
  nx_plugin 'RUN: sleep 30
RUN: sleep 30
RUN: sleep 30'
  nx_settings '.flow.factory.leaseSeconds = 3 | .flow.factory.heartbeatSeconds = 1 | .flow.factory.worker.stages.build.maxBudgetUsd = 3'
  fe_worker_says
  nx_next
  NX_SID1=$(nx_jq "$NX_J/directives/$D1.json" .session_id)
  fe_mask_text "$NX_SID1" "<sid1>"
  nx_wait_child "$D1"
  sleep 1
  nx_kill_group "$D1"
  nx_wait_result "$D1"; nx_wait_launcher_gone "$D1"
  nx_next
  nx_wait_child "$D2"
  sleep 1
  nx_kill_group "$D2"
  nx_wait_result "$D2"; nx_wait_launcher_gone "$D2"
  NX_SID2=$(nx_jq "$NX_J/job.json" .sessions.build)
  fe_mask_text "$NX_SID2" "<sid2>"
  nx_next
  nx_wait_child "$D3"
  sleep 1
}
fe_new nx6a-third-failure-parks
# Source: T:39 (attempts_exhausted false) twice, then T:43a (stage_failed,
# attempts_exhausted true: needs_human, reason attempts_exhausted); A.10: limits
# min(1.00, 3.00) - 0.50, min(1.00, 2.00) - 0.50, min(1.00, 1.00) - 0.50 = 0.50
# each, three charges of 1.00 = 3.00.
e2e_describe "attempt 0, build budget 3.00, three RUN: sleep 30 steps; claude's group is killed in each of three runs"
nx6_setup
nx_kill_group "$D3"
nx_wait_result "$D3"; nx_wait_launcher_gone "$D3"
nx_next
e2e_expect_equal "66b 39 66b 39 66b 43a" "$(nx_rows)" "rows"
e2e_expect_equal "$NX_SID1" "$(nx_arg_after 2 --resume)" "run 2 --resume"
e2e_expect_equal "$NX_SID2" "$(nx_arg_after 3 --resume)" "run 3 --resume (run 2's own session)"
e2e_expect_equal yes "$([ "$NX_SID2" != "$NX_SID1" ] && echo yes || echo no)" "run 2's session differs from run 1's (fork)"
for NX_K in 1 2 3; do e2e_expect_equal 0.5 "$(nx_arg_after $NX_K --max-budget-usd)" "run $NX_K --max-budget-usd"; done
e2e_expect_equal "needs_human attempts_exhausted 2 false" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.reason) \(.attempt) \(.holds_slot)"')" "state, reason, attempt, holds_slot"
e2e_expect_equal 300 "$(nx_cents "$NX_J/job.json" .cost.stage_usd.build)" "stage_usd.build in cents"
e2e_expect_equal 3 "$(nx_launches)" "claude launches"
fe_art_state 7

fe_new nx6b-third-launcher-killed
# Source: T:43l (lease_expired, group_gone true, attempts_exhausted true); T11
# liveness step 5 (charge 0.50 + 0.50 = 1.00, limit_plus_turn); A.10 as nx6a.
e2e_describe "as nx6a, but in run 3 the launcher is killed; next after 4 s"
nx6_setup
NX_PG=$(nx_lease "$D3" child_pgid)
kill -9 "$(nx_lease "$D3" launcher_pid)"
sleep 4
nx_next
e2e_expect_equal "66b 39 66b 39 66b 43l" "$(nx_rows)" "rows"
e2e_expect_equal "needs_human attempts_exhausted 2" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.reason) \(.attempt)"')" "state, reason, attempt"
e2e_expect_equal gone "$(kill -0 -- "-$NX_PG" 2>/dev/null && echo alive || echo gone)" "run 3's group"
e2e_expect_equal "100 limit_plus_turn" "$(nx_jq "$NX_J/job.json" '[.cost.runs[] | select(.directive == "'"$D3"'")] | "\(length) \(.[0].charged_usd * 100 | round) \(.[0].basis)"' | cut -d' ' -f2-)" "run 3 charge"
e2e_expect_equal 1 "$(nx_jq "$NX_J/job.json" '[.cost.runs[] | select(.directive == "'"$D3"'")] | length')" "cost.runs entries for run 3"
e2e_expect_equal 300 "$(nx_cents "$NX_J/job.json" .cost.stage_usd.build)" "stage_usd.build in cents"
e2e_expect_equal 3 "$(nx_launches)" "claude launches"
fe_art_state 7
fi

# ---------------------------------------------------------------- NX7
if nx_run NX7; then
_flow_test_begin "next: a live orphan group parks the launch; a dead or reused pgid does not (NX7, A+8)"
# nx7_sleeper — start `sleep 60` in a session of its own; print its pid.
nx7_sleeper() {
  local pid
  pid=$(_fe_in_scratch "$(fe_python)" -I -c 'import subprocess; print(subprocess.Popen(["sleep", "60"], start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).pid)')
  _fe_register "$pid"
  printf '%s' "$pid"
}
nx7_orphan() { printf "d['orphan_groups'] = [{'pgid': %s, 'start': '%s', 'stage': 'build', 'recorded_at': '2026-11-16T00:00:00Z'}]" "$1" "$2"; }

fe_new nx7a-orphan-alive
# Source: T:43g (launch_due, orphan_group_alive true, precedence 9: needs_human,
# reason orphan_worker, do not launch); execution_model L72; A+8.
e2e_describe "orphan_groups holds a live sleep 60 in its own session, with its own start time"
e2e_repo main
NX_S=$(nx7_sleeper)
fe_mask_pid "$NX_S" sleeper
NX_SS=$(_fe_lstart "$NX_S")
nx_seed "$(nx7_orphan "$NX_S" "$NX_SS")"
nx_plugin 'RUN: true'
fe_worker_says "worker-result=$NX_SUCCESS"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 43g "$(nx_rows)" "rows"
e2e_expect_equal "needs_human orphan_worker" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.reason)"')" "state, reason"
e2e_expect_equal 0 "$(nx_directives)" "directives"
e2e_expect_line "{\"status\":\"ORPHAN_GROUP job=issue-7-j1 pgid=$NX_S stage=build\"}"

fe_new nx7b-orphan-dead
# Source: A+8 (a dead pgid is not alive) -> T:66b.
e2e_describe "orphan_groups holds the pgid of a process that has ended"
e2e_repo main
NX_S=$(_fe_in_scratch sh -c 'echo $$')
nx_seed "$(nx7_orphan "$NX_S" 'Mon Nov 16 00:00:00 2026')"
nx_plugin 'RUN: true'
fe_worker_says "worker-result=$NX_SUCCESS"
nx_next
e2e_expect_equal 66b "$(nx_rows)" "rows"
nx_finish "$D1"

fe_new nx7c-orphan-reused
# Source: A+8 (a pgid led by a process with another start time is not the
# recorded group: not alive, not killed) -> T:66b.
e2e_describe "orphan_groups holds the pgid of a live process, with a start time that is not its own"
e2e_repo main
NX_S=$(nx7_sleeper)
fe_mask_pid "$NX_S" sleeper
nx_seed "$(nx7_orphan "$NX_S" 'Thu Jan  1 00:00:00 1970')"
nx_plugin 'RUN: true'
fe_worker_says "worker-result=$NX_SUCCESS"
nx_next
e2e_expect_equal 66b "$(nx_rows)" "rows"
e2e_expect_equal alive "$(kill -0 "$NX_S" 2>/dev/null && echo alive || echo gone)" "the process holding the pgid"
nx_finish "$D1"
fi

# ---------------------------------------------------------------- NX8
if nx_run NX8; then
_flow_test_begin "next: an expired lease whose group is not confirmed gone parks (NX8)"
fe_new nx8-group-not-gone
# Source: T:43o (lease_expired, group_gone false, precedence 39: needs_human,
# reason orphan_worker); 43y needs clone_config_changed, false with the clone.
e2e_describe "seam group_gone false; a current directive whose lease names an exited launcher and an old heartbeat; leaseSeconds 3"
nx_seed "d['directive'] = '$D1'; d['stage_launches'] = {'build': 1}; d['holds_slot'] = True"
nx_plugin 'RUN: true'
nx_settings '.flow.factory.leaseSeconds = 3'
fe_directive "$D1" "d['max_budget_usd'] = 0.5; d['started_at'] = '2026-11-16T00:00:00Z'; d['model'] = 'claude-opus-5-5'"
NX_DEAD=$(_fe_in_scratch sh -c 'echo $$')
cat > "$NX_J/directives/$D1.lease.json" <<JSON
{"directive": "$D1", "kind": "worker", "host": "h", "launcher_pid": $NX_DEAD, "launcher_start": "Mon Nov 16 00:00:00 2026",
 "started_at": "2026-11-16T00:00:00Z", "heartbeat_at": "2026-11-16T00:00:00Z", "child_pid": null, "child_pgid": null,
 "child_start": null, "revoked_at": null}
JSON
jq '.built_inputs = {"group_gone": false}' "$FE_FIXTURES/seam/ordinary.json" > "$E2E_DIR/nx8.json"
nx_next "$E2E_DIR/nx8.json"
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 43o "$(nx_rows)" "rows"
e2e_expect_equal "needs_human orphan_worker false" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.reason) \(.holds_slot)"')" "state, reason, holds_slot"
e2e_expect_equal yes "$([ -n "$(nx_lease "$D1" revoked_at)" ] && echo yes || echo no)" "lease revoked"
fi

# ---------------------------------------------------------------- NX9, NX15
if nx_run NX9; then
_flow_test_begin "next: a cancelled job frees its slot and the waiting job launches (NX9, R17)"
fe_new nx9-slot-freed
# Source: T:conventions.slots; T:66w (slot_available false: stay, do not launch);
# T:53 (person_cancel, unvouched_session_action false -> cancelled, terminal).
e2e_describe "concurrency 1; job 7 launches and sleeps 30 s; job 8 waits at 66w; job 7 gets a pending person_cancel"
nx_seed
fe_job 8 build
fe_job_clone 8
NX_J8="$NX_F/jobs/issue-8"
nx_plugin 'RUN: true'
nx_settings '.flow.factory.concurrency = 1'
fe_worker_says "worker-result=$NX_SUCCESS" worker-sleep=30
nx_next
e2e_expect_equal 66b "$(nx_rows 7)" "job 7 rows after pass 1"
e2e_expect_equal 66w "$(nx_rows 8)" "job 8 rows after pass 1"
e2e_expect_equal null "$(nx_jq "$NX_J8/job.json" .directive)" "job 8 directive after pass 1"
nx_wait_child "$D1"
NX_PG=$(nx_lease "$D1" child_pgid)
fe_py "import _flow_factory_jobs as j
p = j.resolve(create=False)
print(j.store_pending(p, 7, 'person_cancel', {}, 'terminal', {'pid': 1, 'start': 'x', 'ancestry': [1]}, {'unvouched_session_action': False}))"
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 2 exit status ($E2E_ERR)"
e2e_expect_equal "66b 53" "$(nx_rows 7)" "job 7 rows"
e2e_expect_equal "cancelled false" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.holds_slot)"')" "job 7 state, holds_slot"
e2e_expect_equal gone "$(kill -0 -- "-$NX_PG" 2>/dev/null && echo alive || echo gone)" "job 7's worker group"
e2e_expect_equal "66w 66b" "$(nx_rows 8)" "job 8 rows"
e2e_expect_equal issue-8-j1-build-1 "$(nx_jq "$NX_J8/job.json" .directive)" "job 8 directive"
e2e_expect_equal true "$(nx_jq "$NX_J8/job.json" .holds_slot)" "job 8 holds_slot"
fe_art_state 7
fe_art_state 8
fi

if nx_run NX15; then
_flow_test_begin "next: a cancelled job's branch and snapshots are copied into the main checkout (NX15)"
fe_new nx15-terminal-refs
# Source: states_and_transitions L87 (terminal cleanup); T:53.
e2e_describe "job 7 in build with a snapshot ref in its clone; a pending person_cancel"
nx_seed
nx_plugin 'RUN: true'
NX_WT=$(nx_jq "$NX_J/job.json" .worktree)
_fe_in_scratch sh -c 'cd "$1" && git update-ref refs/flow-factory/issue-7/snapshot-1 HEAD' _ "$NX_WT"
fe_py "import _flow_factory_jobs as j
p = j.resolve(create=False)
print(j.store_pending(p, 7, 'person_cancel', {}, 'terminal', {'pid': 1, 'start': 'x', 'ancestry': [1]}, {'unvouched_session_action': False}))"
nx_next
e2e_expect_equal 53 "$(nx_rows)" "rows"
e2e_expect_equal done "$(nx_last)" "last line"
e2e_expect_equal "refs/flow-factory/issue-7/branch refs/flow-factory/issue-7/snapshot-1" \
  "$(_fe_in_scratch git for-each-ref --format='%(refname)' refs/flow-factory/issue-7/ | tr '\n' ' ' | sed 's/ $//')" "main checkout refs"
fi

# ---------------------------------------------------------------- NX-AC8
if nx_run NXAC8; then
_flow_test_begin "next: the shell's pending report is applied only from the lease's launcher (NX-AC8, AC8, R26, RM4)"
# nxac8_setup [job edits] [directive edits] [worker result] — T7 LA16(b): the
# recorded interpreter is a link the test removes while the worker sleeps, so
# the launcher reports through the shell and leaves a pending-report line.
nxac8_setup() {
  e2e_repo main
  fe_record_link
  fe_enable
  fe_job 7 build "d['directive'] = '$D1'; d['stage_launches'] = {'build': 1}; d['holds_slot'] = True
${1:-}"
  fe_job_clone 7
  fe_directive "$D1" "${2:-}"
  NX_F=$(fe_factory_dir); NX_J="$NX_F/jobs/issue-7"
  nx_plugin 'RUN: true'
  fe_worker_says "worker-result=${3:-$NX_SUCCESS}" worker-sleep=3
  e2e_run_bin bin/flow-factory.sh launch "$D1"
  e2e_expect_line "LAUNCHED directive=$D1"
  fe_wait_for 15 "[ -f '$E2E_BIN/claude-pid-1' ]"
  rm -f "$E2E_DIR/py/python3.14"
  fe_wait_for 30 "[ -s '$NX_J/directives/$D1.pending-report.jsonl' ]"
  nx_wait_launcher_gone "$D1"
  ln -sfn "$(fe_python)" "$E2E_DIR/py/python3.14"
}

fe_new nxac8a-shell-report-applied
# Source: execution_model L9; plan 2.4 report rule; T:20 (stage_succeeded in build -> open_pr).
e2e_describe "the launcher's shell pending-report line, with the interpreter link restored"
nxac8_setup
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_ev_count 7 '.type == "result_applied" and .directive == "'"$D1"'"')" "result_applied events"
e2e_expect_equal 20 "$(nx_rows)" "rows"
e2e_expect_equal open_pr "$(nx_jq "$NX_J/job.json" .state)" "state"
e2e_expect_equal absent "$([ -e "$NX_J/directives/$D1.pending-report.jsonl" ] && echo present || echo absent)" "pending-report file"
e2e_expect_equal completed "$(nx_jq "$NX_J/results/$D1.json" .outcome)" "result outcome"
e2e_expect_equal 1 "$(nx_ev_count 7 '.type == "charge" and .directive == "'"$D1"'"')" "charge events"
e2e_expect_equal 5 "$(nx_cents "$NX_J/job.json" .cost.usd_total)" "cost.usd_total in cents (first_total 0.05)"
fe_art_state 7

fe_new nxac8b-forged-report-refused
# Source: plan 2.4 (a line whose caller is not the lease's launcher is recorded report_refused and dropped); R26.
e2e_describe "the pending-report line is rewritten to name the test shell's pid and its 2.4-form start"
nxac8_setup
NX_ME=$$
NX_MS=$(_fe_lstart "$NX_ME")
NX_RL="$NX_J/directives/$D1.pending-report.jsonl"
jq -c --argjson p "$NX_ME" --arg s "$NX_MS" '.caller_pid = $p | .caller_start = $s' "$NX_RL" > "$NX_RL.t" && mv "$NX_RL.t" "$NX_RL"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_ev_count 7 '.type == "report_refused" and .directive == "'"$D1"'" and .reason == "not_launcher"')" "report_refused events"
e2e_expect_equal 0 "$(nx_ev_count 7 '.type == "transition"')" "transition lines"
e2e_expect_equal build "$(nx_jq "$NX_J/job.json" .state)" "state"
e2e_expect_equal absent "$([ -e "$NX_J/results/$D1.json" ] && echo present || echo absent)" "results file"

fe_new nxac8c-shell-report-resume-charge
# Source: journal RM4; plan 2.14 charge_run since_last: 0.20 + 0.03 = 0.23, so
# usd_total 0.97 + 0.23 = 1.20 (the session total would give 2.17).
e2e_describe "a resumed run reported through the shell: session total 1.20, its own since-last cost 0.20 + 0.03"
NX_SID=33333333-3333-4333-8333-333333333333
nxac8_setup "d['sessions'] = {'build': '$NX_SID'}; d['cost']['usd_total'] = 0.97; d['cost']['stage_usd'] = {'build': 0.97}; d['last_session_total'] = {'$NX_SID': 0.97}" \
  "d['start_mode'] = 'resume'; d['cause_row'] = '39'; d['prompt_template'] = 'templates/factory/resume.prompt.md'" \
  "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"num_turns\":1,\"session_id\":\"$NX_SID\",\"total_cost_usd\":1.20,\"model_usage_since_last_result\":{\"claude-opus-5-5\":{\"costUSD\":0.20},\"claude-haiku-4-5\":{\"costUSD\":0.03}}}"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 120 "$(nx_cents "$NX_J/job.json" .cost.usd_total)" "cost.usd_total in cents"
e2e_expect_equal "23 since_last" "$(nx_jq "$NX_J/job.json" '.cost.runs[-1] | "\(.charged_usd * 100 | round) \(.basis)"')" "the run's charge"
e2e_expect_equal 23 "$(nx_cents "$NX_J/results/$D1.json" .charged_usd)" "result charged_usd in cents"
fe_art_state 7
fi

# ---------------------------------------------------------------- NX-AC7
if nx_run NXAC7; then
_flow_test_begin "next: a worker that next launched cannot run a person command (NX-AC7, AC7, RM1)"
fe_new nxac7-worker-cancel
# Source: journal RM1 (right: exit 4 PERSON_ONLY_REFUSED=lease_ancestor); AC7.
e2e_describe "the worker's RUN step clears every FLOW_FACTORY_* name, moves out of the clone and runs cancel 7"
nx_seed
nx_plugin 'RUN: cd "$FLOW_FACTORY_IO/.." && env -u FLOW_FACTORY_JOB -u FLOW_FACTORY_DIRECTIVE -u FLOW_FACTORY_IO -u FLOW_FACTORY_MAIN "$CLAUDE_PLUGIN_ROOT/bin/flow-factory.sh" cancel 7 > cancel.out; echo rc=$? >> cancel.out'
fe_worker_says
nx_next
nx_finish "$D1" 60
NX_IO=$(nx_jq "$NX_J/job.json" .io_dir)
e2e_expect_equal "PERSON_ONLY_REFUSED=lease_ancestor;rc=4;" "$(tr '\n' ';' < "$(dirname "$NX_IO")/cancel.out" 2>/dev/null)" "cancel.out"
fi

# ---------------------------------------------------------------- NX11
if nx_run NX11; then
_flow_test_begin "next: a usage limit pauses launches and counts no attempt (NX11)"
fe_new nx11-usage-limit
# Source: execution_model L139; amendments A.8 (paused 3600 s); T7 (usage_limit raises no event).
e2e_describe "the worker's result is a usage limit (api_error_status 429); next, then next again"
nx_seed
nx_plugin 'RUN: true'
fe_worker_says 'worker-result={"type":"result","subtype":"error","is_error":true,"num_turns":0,"api_error_status":429}'
nx_next
nx_finish "$D1"
e2e_expect_equal usage_limit "$(nx_jq "$NX_J/results/$D1.json" .outcome)" "result outcome"
NX_NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
e2e_expect_equal yes "$([ "$(nx_jq "$NX_F/state.json" .paused_until)" \> "$NX_NOW" ] && echo yes || echo no)" "paused_until is in the future"
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 2 exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(printf '%s\n' "$E2E_OUT" | grep -c '^{"status":"PAUSED usage_limit until=[0-9TZ:-]*"}$')" "PAUSED usage_limit line"
e2e_expect_equal 1 "$(nx_launches)" "claude launches"
e2e_expect_equal 1 "$(nx_directives)" "directives"
e2e_expect_equal 0 "$(nx_jq "$NX_J/job.json" .attempt)" "attempt"
fi

# ---------------------------------------------------------------- NX12
if nx_run NX12; then
_flow_test_begin "next: an intake judge is a directive with no process; its result moves the job (NX12, scope 2)"
fe_new nx12-judge-as-data
# Source: amendment C scope 2; T:66i (launch_due in intake); T:6 (judge_accept in intake, no guard -> prepare).
e2e_describe "job 7 in intake; seam bodies judge:intake judge_accept; next twice"
e2e_repo main
fe_record
fe_enable
fe_job 7 intake
NX_F=$(fe_factory_dir); NX_J="$NX_F/jobs/issue-7"
jq '.bodies = {"judge:intake": "judge_accept"}' "$FE_FIXTURES/seam/ordinary.json" > "$E2E_DIR/nx12.json"
nx_next "$E2E_DIR/nx12.json"
e2e_expect_equal 0 "$E2E_RC" "pass 1 exit status ($E2E_ERR)"
e2e_expect_equal 66i "$(nx_rows)" "rows after pass 1"
e2e_expect_equal "judge null" "$(nx_jq "$NX_J/directives/issue-7-j1-intake-1.json" '"\(.kind) \(.session_id)"')" "directive kind, session_id"
e2e_expect_equal 0 "$(nx_launches)" "claude launches"
nx_next "$E2E_DIR/nx12.json"
e2e_expect_equal "66i 6" "$(nx_rows)" "rows after pass 2"
e2e_expect_equal prepare "$(nx_jq "$NX_J/job.json" .state)" "state"
fi

# ---------------------------------------------------------------- NX13
if nx_run NX13; then
_flow_test_begin "next: a probe holding the probe lock delays next by at most 2 s (NX13, R19)"
fe_new nx13-probe-lock
# Source: plan 2.12 environment_recheck (waits min(2, left - 1) s for probes.lock
# only when gh or git moved; on a timeout it writes nothing); plan 2.5.
e2e_describe "gh reports a new version, so the re-run must record it under probes.lock, which a probe holds for 30 s; syncIntervalSeconds 0; nextBudgetSeconds 5"
nx_seed
nx_plugin 'RUN: true'
nx_settings '.flow.factory.syncIntervalSeconds = 0 | .flow.factory.nextBudgetSeconds = 5'
fe_worker_says "worker-result=$NX_SUCCESS"
fe_gh --version 'gh version 2.102.0 (2026-10-01)'
fe_bg probe fe_py "import time, _flow_factory as ff, _flow_factory_jobs as j
p = j.resolve(create=False)
with ff.factory_lock(p.fdir, timeout=5):
    print('locked', flush=True)
    time.sleep(30)"
fe_wait_for 10 'grep -qx locked "$E2E_DIR/bg-probe.out"'
NX_REC0=$(jq -c .groups.environment "$NX_F/probes.json")
nx_next
printf 'NX13 elapsed: %s s\n' "$NX_ELAPSED"
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal yes "$(nx_le "$NX_ELAPSED" 6)" "next returned within 6 s"
e2e_expect_equal 66b "$(nx_rows)" "rows (job 7 launched)"
e2e_expect_equal null "$(nx_jq "$NX_F/state.json" .env_recheck_at)" "env_recheck_at unchanged"
e2e_expect_equal "$NX_REC0" "$(jq -c .groups.environment "$NX_F/probes.json")" "the record's environment group"
nx_finish "$D1"
fi
