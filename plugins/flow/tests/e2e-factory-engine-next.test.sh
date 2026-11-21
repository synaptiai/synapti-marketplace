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
#   NX17 a pass that changes job.json orphan_groups, snapshots or
#        pending_changes writes no events.jsonl line for it, so rebuild
#        cannot restore the field; or the line's entry differs from the one
#        job.json holds
#   NX32 a linked J/sync is read or unlinked through
#   NX33 a linked J/results or J/archive (or archive entry) is read through
#   NX34 row 41e runs the write when the effect is gone by the handler
#   NX35 a decision whose later effect fails leaves its earlier writes to send
#   NX36 the crash-case replay is not run first, or a failed replay holds back
#        the job's other events
#   NX37 a pass with no sync has no engine login, or one that cannot read it
#        drains or records with none (R95)
#   NX38 labels.priorityHigh does not order the launches
#   NX39 a needs-info round reuses a notice id, posts twice, or drops a reply
#        that already counted (R25, R98)
#   NX40 a malformed judge reply raises intake_round (R21)
#   NX41 row 9 fires before round 3, or not at it
#   NX42 github_change is taken before person_answer (R59)
#   NX43 row 47 does not re-vouch (R62)
#   NX44 a queue label re-add counts as a re-vouch (R64)
#   NX45 the comment facts do not reach the decision (R67)
#   NX46 a stored comment command runs twice after a lost commands_seen (R78)
#   NX47 an edit of a trusted spec comment is not an untrusted edit (R86)
#   NX48 an issue fact or a sync-reading handler is used with no sync (R88)
#   NX49 a stored event's arguments do not reach its handler or replay (R89)
#   NX50 a bot actor is trusted without trustedBots (R90)
#   NX51 dependency lines are matched loosely (R76)
#   NX52 53b and 51b do not apply through the shipped wrapper
#   NX53 /flow-factory reject in needs_human does not reject (T:48)
#   NX54 row 66i takes an issue set whose digest does not match
#   NX55 an NI answer given at row 44 is lost
#   NX56 a 1b field is not rebuilt (R36)
#   NX57 an OS error in an effect escapes the pass
#   NX58 a comment answer is fenced twice, or the engine's notice is a reply
#        (R102)
#   NX59 the round limit is not met by a reply, or met with none (R98)
#   NX60 a linked J/outbox is read or written through by rows 41e, 41k, 11,
#        40 or 50, or by the fact that chooses row 41e; a confirm of an item
#        that is not found is kept, or the park fails silently
#   NX61 a linked J/directives is read or written through: its lease revoked
#        or its pending-report file removed through the link
#   NX62 row 41 runs an item edited after the stored confirm (R32), or the
#        refused confirm is kept and the park fails silently in every pass
#   NX63 a later launch rebuilds in/issue.md from live GitHub (R9)
#   NX64 row 8u posts its notice again on a later pass or after a rebuild (R14)
#   NX65 a changed issue sent back to intake while the slot is taken raises
#        row 50 on the next sync, or loses baseline_pending (R91)
#   NX66 a trusted rename does not reach the next issue.md title fence (R99)
#   NX67 a blocked replay drops the held result, or holds back the job's
#        other events (B14 step 10)
#
# Amounts are compared in whole cents through jq. Elapsed times go to stdout,
# not to the artifacts, so the artifacts stay the same from run to run.
#
# NX_ONLY=<id> (NX1 ... NX67, NXAC7, NXAC8, NX12b) runs only that scenario.

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
# A file's modification time in seconds since the epoch. Not stat: macOS takes
# -f %m, and GNU stat reads -f as "the file system", whose %m is not a time.
nx_mtime() { perl -MTime::HiRes=stat -e 'printf "%.3f", (stat $ARGV[0])[9]' "$1"; }
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

# nx_world [engine login] — a world for the gh stand-in (fe_world_new) on
# flow-e2e/scratch, with `gh --version` answered by a fixture, since the
# world answers only the API calls the engine makes and the environment
# check reads the version.
nx_world() {
  fe_world_new "${1:-flow-e2e-engine}" flow-e2e/scratch
  fe_gh --version 'gh version 2.101.0 (2026-09-15)'
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
NX_E1=$(nx_secs "$NX_T0" "$(nx_mtime "$E2E_DIR/bg-n1.rc")")
NX_E2=$(nx_secs "$NX_T0" "$(nx_mtime "$E2E_DIR/bg-n2.rc")")
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
# The plan's row uses nextBudgetSeconds 4 and a 5 s limit. gh() makes no call
# when left - 2 < 1, so a budget of 4 leaves 1 s for the pass's work before
# the PR call; on a loaded machine that work takes about 1 s, the call is
# skipped and the hang is never exercised (the PR-call count below then reads
# 0). Budget 7 leaves 4 s. The call is then cut at about deadline - 2, and
# next returns at about the budget plus the interpreter's start. The limit,
# 11 s, still fails the plausible wrong version, a fixed 15 s gh timeout that
# ignores the time left (about 15 s or more), and a call with no timeout
# (about 30 s).
e2e_describe "job 7 has PR 12; nextBudgetSeconds 7; the PR call hangs 30 s"
nx_seed "d['pr'] = 12; d['head_sha'] = 'a' * 40"
nx_plugin 'RUN: true'
nx_settings '.flow.factory.nextBudgetSeconds = 7'
fe_gh api_repos_flow-e2e_scratch_pulls_12 "hang 30"
nx_next
printf 'NX2 elapsed: %s s\n' "$NX_ELAPSED"
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal yes "$(nx_le "$NX_ELAPSED" 11)" "next returned within 11 s"
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

fe_new nx8b-child-start-unknown
# Source: A+8 (a group is killed only when its leader's start time is the
# recorded one); a lease whose child_start could not be read gives no start
# to compare, so the group is neither signalled nor taken as gone: it is
# recorded with its leader's start time now, and T:43o parks the job.
e2e_describe "an expired lease naming a live sleep 60 in its own session as claude's group, with child_start null; the ordinary seam; leaseSeconds 3"
nx_seed "d['directive'] = '$D1'; d['stage_launches'] = {'build': 1}; d['holds_slot'] = True"
nx_plugin 'RUN: true'
nx_settings '.flow.factory.leaseSeconds = 3'
fe_directive "$D1" "d['max_budget_usd'] = 0.5; d['started_at'] = '2026-11-16T00:00:00Z'; d['model'] = 'claude-opus-5-5'"
NX_DEAD=$(_fe_in_scratch sh -c 'echo $$')
NX_S=$(_fe_in_scratch "$(fe_python)" -I -c 'import subprocess; print(subprocess.Popen(["sleep", "60"], start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).pid)')
_fe_register "$NX_S"
e2e_expect_equal yes "$(kill -0 "$NX_S" 2>/dev/null && echo yes || echo no)" "the sleeper started"
fe_mask_pid "$NX_S" sleeper
cat > "$NX_J/directives/$D1.lease.json" <<JSON
{"directive": "$D1", "kind": "worker", "host": "h", "launcher_pid": $NX_DEAD, "launcher_start": "Mon Nov 16 00:00:00 2026",
 "started_at": "2026-11-16T00:00:00Z", "heartbeat_at": "2026-11-16T00:00:00Z", "child_pid": $NX_S, "child_pgid": $NX_S,
 "child_start": null, "revoked_at": null}
JSON
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 43o "$(nx_rows)" "rows"
e2e_expect_equal "needs_human orphan_worker" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.reason)"')" "state, reason"
e2e_expect_equal alive "$(kill -0 "$NX_S" 2>/dev/null && echo alive || echo gone)" "the group with no recorded start (not signalled)"
e2e_expect_equal "$NX_S" "$(nx_jq "$NX_J/job.json" '.orphan_groups[0].pgid')" "orphan_groups pgid"
e2e_expect_equal "$(_fe_lstart "$NX_S")" "$(nx_jq "$NX_J/job.json" '.orphan_groups[0].start')" "orphan_groups start (the leader's, read now)"
kill "$NX_S" 2>/dev/null

fe_new nx8d-leaderless-group-killed
# Source: A+8 (a process group id is not given to a new group while any
# member lives); a group whose leader has exited, with no recorded start, can
# only be the recorded group, so it is killed, not left running untracked.
e2e_describe "an expired lease, child_start null, naming a group whose leader (sh) has exited while its sleep 60 still runs; the ordinary seam; leaseSeconds 3"
nx_seed "d['directive'] = '$D1'; d['stage_launches'] = {'build': 1}; d['holds_slot'] = True"
nx_plugin 'RUN: true'
nx_settings '.flow.factory.leaseSeconds = 3'
fe_directive "$D1" "d['max_budget_usd'] = 0.5; d['started_at'] = '2026-11-16T00:00:00Z'; d['model'] = 'claude-opus-5-5'"
NX_DEAD=$(_fe_in_scratch sh -c 'echo $$')
NX_PAIR=$(_fe_in_scratch "$(fe_python)" -I -c 'import subprocess; p = subprocess.Popen(["sh", "-c", "sleep 60 >/dev/null 2>&1 & echo $!"], start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL); child = p.stdout.readline().strip().decode(); p.wait(); print(p.pid, child)')
NX_PG=${NX_PAIR% *}; NX_KID=${NX_PAIR#* }
_fe_register "$NX_KID"
e2e_expect_equal "gone alive" "$(kill -0 "$NX_PG" 2>/dev/null && echo alive || echo gone) $(kill -0 "$NX_KID" 2>/dev/null && echo alive || echo gone)" "the leader has exited, its child runs"
fe_mask_pid "$NX_PG" group
fe_mask_pid "$NX_KID" member
cat > "$NX_J/directives/$D1.lease.json" <<JSON
{"directive": "$D1", "kind": "worker", "host": "h", "launcher_pid": $NX_DEAD, "launcher_start": "Mon Nov 16 00:00:00 2026",
 "started_at": "2026-11-16T00:00:00Z", "heartbeat_at": "2026-11-16T00:00:00Z", "child_pid": $NX_PG, "child_pgid": $NX_PG,
 "child_start": null, "revoked_at": null}
JSON
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal gone "$(kill -0 "$NX_KID" 2>/dev/null && echo alive || echo gone)" "the group's remaining member"
kill "$NX_KID" 2>/dev/null

fe_new nx8c-git-bounded-by-pass
# Source: AC4 (next returns within its time budget); plan 2.18 (every call
# bounded by the time left). A git call that runs out of the pass's time is
# not read as a failed scan: the job is not parked, and the event waits.
e2e_describe "nextBudgetSeconds 5; an expired lease (seam group_gone true); every git status in the clone sleeps 20 s"
nx_seed "d['directive'] = '$D1'; d['stage_launches'] = {'build': 1}; d['holds_slot'] = True"
nx_plugin 'RUN: true'
nx_settings '.flow.factory.leaseSeconds = 3 | .flow.factory.nextBudgetSeconds = 5'
fe_directive "$D1" "d['max_budget_usd'] = 0.5; d['started_at'] = '2026-11-16T00:00:00Z'; d['model'] = 'claude-opus-5-5'"
NX_DEAD=$(_fe_in_scratch sh -c 'echo $$')
cat > "$NX_J/directives/$D1.lease.json" <<JSON
{"directive": "$D1", "kind": "worker", "host": "h", "launcher_pid": $NX_DEAD, "launcher_start": "Mon Nov 16 00:00:00 2026",
 "started_at": "2026-11-16T00:00:00Z", "heartbeat_at": "2026-11-16T00:00:00Z", "child_pid": null, "child_pgid": null,
 "child_start": null, "revoked_at": null}
JSON
jq '.built_inputs = {"group_gone": true}' "$FE_FIXTURES/seam/ordinary.json" > "$E2E_DIR/nx8c.json"
NX_REAL_GIT=$(command -v git)
printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = status ] && exec sleep 20; done\nexec "%s" "$@"\n' "$NX_REAL_GIT" > "$E2E_BIN/git"
chmod +x "$E2E_BIN/git"
nx_next "$E2E_DIR/nx8c.json"
rm -f "$E2E_BIN/git"
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal yes "$(awk -v e="$NX_ELAPSED" 'BEGIN { print (e < 9) ? "yes" : "no (" e " s)" }')" "next returned within its 5 s budget and a 4 s margin"
e2e_expect_equal "build null" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.reason)"')" "state, reason (not parked)"
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
fe_mask_output '[0-9]{19,20}-person_cancel\.json' '<seq>-person_cancel.json'
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
fe_mask_output '[0-9]{19,20}-person_cancel\.json' '<seq>-person_cancel.json'
nx_next
e2e_expect_equal 53 "$(nx_rows)" "rows"
e2e_expect_equal done "$(nx_last)" "last line"
e2e_expect_equal "refs/flow-factory/issue-7/branch refs/flow-factory/issue-7/snapshot-1" \
  "$(_fe_in_scratch git for-each-ref --format='%(refname)' refs/flow-factory/issue-7/ | tr '\n' ' ' | sed 's/ $//')" "main checkout refs"
fi

# ---------------------------------------------------------------- NX-AC8
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

if nx_run NXAC8; then
_flow_test_begin "next: the shell's pending report is applied only from the lease's launcher (NX-AC8, AC8, R26, RM4)"

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

fe_new nxac8d-shell-report-fact-fails
# Source: plan 2.4 (a stage event whose facts cannot be computed is kept, as
# apply_pending keeps a launcher's pending file on failed); T:39 reads
# tree_dirty, whose git status --untracked-files=all fails here (FactFailed)
# while the nested-repository scan (--untracked-files=normal) succeeds.
e2e_describe "the launcher's shell pending-report line for a run that ended in a 529 API error (stage_failed), applied by a pass whose git fails only for status --untracked-files=all; then next runs again with the real git"
nxac8_setup "" "" '{"type":"result","subtype":"success","is_error":true,"num_turns":1,"total_cost_usd":0.05,"api_error_status":529,"api_error":"overloaded_error","terminal_reason":"api_error"}'
NX_REAL_GIT=$(command -v git)
printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = --untracked-files=all ] && { echo "fatal: injected" >&2; exit 128; }; done\nexec "%s" "$@"\n' "$NX_REAL_GIT" > "$E2E_BIN/git"
chmod +x "$E2E_BIN/git"
nx_next
rm -f "$E2E_BIN/git"
e2e_expect_equal 0 "$E2E_RC" "first pass exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_ev_count 7 '.type == "result_applied" and .directive == "'"$D1"'"')" "result_applied events after the first pass"
e2e_expect_equal 0 "$(nx_ev_count 7 '.type == "transition"')" "transitions after the first pass"
e2e_expect_equal 1 "$(find "$NX_J/pending" -name '*-stage_failed.json' 2>/dev/null | wc -l | tr -d ' ')" "pending stage_failed kept after the first pass"
e2e_expect_equal "$D1" "$(nx_jq "$NX_J/job.json" .directive)" "current directive after the first pass (no fresh launch)"
nx_next
e2e_expect_equal 0 "$E2E_RC" "second pass exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_ev_count 7 '.type == "transition" and .event == "stage_failed"')" "stage_failed transitions after the second pass"
e2e_expect_equal 0 "$(find "$NX_J/pending" -name '*-stage_failed.json' 2>/dev/null | wc -l | tr -d ' ')" "pending stage_failed after the second pass"
e2e_expect_equal 1 "$(nx_ev_count 7 '.type == "charge" and .directive == "'"$D1"'"')" "charge events"
e2e_expect_equal 5 "$(nx_cents "$NX_J/job.json" .cost.usd_total)" "cost.usd_total in cents (charged once)"
fe_art_state 7

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
fe_mask_output 'until=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' 'until=<time>'
e2e_expect_equal 0 "$E2E_RC" "pass 2 exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(printf '%s\n' "$E2E_OUT" | grep -c '^{"status":"PAUSED usage_limit until=[0-9TZ:-]*"}$')" "PAUSED usage_limit line"
e2e_expect_equal 1 "$(nx_launches)" "claude launches"
e2e_expect_equal 1 "$(nx_directives)" "directives"
e2e_expect_equal 0 "$(nx_jq "$NX_J/job.json" .attempt)" "attempt"
fi

# ---------------------------------------------------------------- NX12
if nx_run NX12; then
_flow_test_begin "next: the intake judge is launched for real and its accept moves the job (NX12, R93)"
fe_new nx12-judge-launch
# Source: plan B14 step 11 (the intake judge is launched with no seam body;
# pass 1 gives row 66i and one claude launch; after the result file, pass 2
# gives row 6, state prepare and in-copies/intake.json); T:66i, T:6; plan
# 3.3 "Waiting for a judge's result"; plan B13 table (row 6's
# intake_record writes intake_inputs and intake; the accept notice is one
# outbox comment, which the drain of the same pass posts, plan 2.2).
e2e_describe "job 7 in intake; a world with issue 7 and no comments; syncIntervalSeconds 0; the judge stand-in answers ACCEPT; next, wait for the result, next"
e2e_repo main
fe_record
fe_enable
nx_settings '.flow.factory.syncIntervalSeconds = 0'
nx_world
fe_world_issue 7 "Add a port setting" "The service needs a port setting."
fe_judge_says '{"decision":"ACCEPT","risk":"low","surfaces":["config"],"scope":"one setting","proposed_criteria":["the port is read from the settings file"],"questions":[],"reason":"clear"}'
fe_job 7 intake "d['vouch_at'] = '2026-11-16T00:00:00Z'"
NX_F=$(fe_factory_dir); NX_J="$NX_F/jobs/issue-7"
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 1 exit status ($E2E_ERR)"
e2e_expect_equal 66i "$(nx_rows)" "rows after pass 1"
e2e_expect_equal "judge null" "$(nx_jq "$NX_J/directives/issue-7-j1-intake-1.json" '"\(.kind) \(.session_id)"')" "directive kind, session_id"
e2e_expect_equal yes "$([ -f "$NX_J/in-copies/issue.md" ] && echo yes || echo no)" "in-copies/issue.md written by row 66i"
e2e_expect_equal "$(nx_jq "$NX_J/job.json" .issue_digest)" "$(nx_jq "$NX_J/job.json" .baseline_digest)" "baseline_digest equals issue_digest (T:66i)"
e2e_expect_err_lacks "SEAM_MISSING"
fe_wait_for 45 "[ -f '$NX_J/results/issue-7-j1-intake-1.json' ]"
e2e_expect_equal 1 "$(nx_launches)" "claude launches (the judge)"
e2e_expect_equal ACCEPT "$(nx_jq "$NX_J/results/issue-7-j1-intake-1.json" .judge.decision)" "the result holds the judge reply"
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 2 exit status ($E2E_ERR)"
e2e_expect_equal "66i 6" "$(nx_rows)" "rows after pass 2"
e2e_expect_equal prepare "$(nx_jq "$NX_J/job.json" .state)" "state"
e2e_expect_equal "low one setting" "$(nx_jq "$NX_J/job.json" '"\(.intake.risk) \(.intake.scope)"')" "job.json intake"
e2e_expect_equal yes "$([ -f "$NX_J/in-copies/intake.json" ] && echo yes || echo no)" "in-copies/intake.json"
# Source: plan R89 (row 6 from a judge ACCEPT reply with given risk, surfaces
# and scope -> in-copies/intake.json equals those three fields).
e2e_expect_equal '{"risk":"low","scope":"one setting","surfaces":["config"]}' "$(jq -cS '{risk, surfaces, scope}' "$NX_J/in-copies/intake.json" 2>/dev/null)" "in-copies/intake.json holds the reply's risk, surfaces and scope (R89)"
e2e_expect_equal 1 "$(fe_world_posts | jq -r 'select(.method == "POST" and (.path | endswith("/issues/7/comments"))) | .path' | grep -c .)" "the intake notice posted once"
fi

# ---------------------------------------------------------------- NX12b
if nx_run NX12b; then
_flow_test_begin "next: a seam body for the intake judge is refused before the pass (NX12b, R93)"
fe_new nx12b-judge-body-refused
# Source: plan B14 step 11 (set_seam refuses bodies["judge:intake"] with
# SEAM_REFUSED=bodies:judge:intake provider=built, exit 2, as for the 1b
# facts of plan 1.3).
e2e_describe "job 7 in intake; the old NX12 fixture with bodies judge:intake judge_accept; next exits 2 and moves nothing"
e2e_repo main
fe_record
fe_enable
fe_job 7 intake
NX_F=$(fe_factory_dir); NX_J="$NX_F/jobs/issue-7"
jq '.bodies = {"judge:intake": "judge_accept"}' "$FE_FIXTURES/seam/ordinary.json" > "$E2E_DIR/nx12.json"
fe_e "$E2E_DIR/nx12.json" next --executor headless
e2e_expect_equal "2 SEAM_REFUSED=bodies:judge:intake provider=built" "$E2E_RC $E2E_OUT" "exit status and stdout"
e2e_expect_equal "" "$(nx_rows)" "rows"
fi

# nx_stage_result <state> — job 7's current directive in <state>, a
# completed result for it and a pending stage_succeeded from the launcher,
# so apply_pending's directive and result checks pass (plan B14 test plan,
# the push rows; the seeds of tests/fixtures/factory/witness.py).
nx_stage_result() {
  local did="issue-7-j1-$1-1"
  fe_directive "$did" "d['max_budget_usd'] = 0.5"
  fe_job 7 "$1" "d['vouch_at'] = '2026-11-16T00:00:00Z'; d['directive'] = '$did'; d['holds_slot'] = True; ${2:-}"
  mkdir -p "$NX_J/results" "$NX_J/pending"
  jq -n --arg d "$did" '{directive: $d, outcome: "completed", written_at: "2026-11-16T00:00:00Z",
    event: "stage_succeeded", session_id: null, num_turns: null, api_error_status: null, is_error: null,
    permission_denials: null, terminal_reason: null, charged_usd: null, charge_basis: null,
    total_cost_usd: null, since_last_usd: null}' > "$NX_J/results/$did.json"
  jq -n --arg d "$did" '{event: "stage_succeeded", args: {directive: $d}, channel: "launcher",
    caller: {pid: 4242, start: "Mon Nov 16 00:00:00 2026", ancestry: [4242, 1]}, facts: {},
    raised_at: "2026-11-16T00:00:00Z"}' > "$NX_J/pending/00000000000000000001-stage_succeeded.json"
}
# nx_base <state> [job edits] — the scratch repository, a probe record, the
# factory enabled, syncIntervalSeconds 0, a world with issue 7, and job 7 in
# <state> vouched at 2026-11-16T00:00:00Z.
nx_base() {
  e2e_repo main
  fe_record
  fe_enable
  nx_settings '.flow.factory.syncIntervalSeconds = 0'
  nx_world
  fe_world_issue 7 "Add a port setting" "The service needs a port setting."
  fe_job 7 "$1" "d['vouch_at'] = '2026-11-16T00:00:00Z'; ${2:-}"
  NX_F=$(fe_factory_dir); NX_J="$NX_F/jobs/issue-7"
  NX_FIX=""
}
nx_line_count() { printf '%s\n' "$E2E_OUT" | grep -cF -- "$1"; }
nx_posts_to() { fe_world_posts | jq -r --arg p "$1" 'select(.path | endswith($p)) | .path' | grep -c .; }
nx_no_confirm() {
  jq '.unbuilt["*"].executor_can_confirm = false' "$FE_FIXTURES/seam/ordinary.json" > "$E2E_DIR/no-confirm.json"
  NX_FIX="$E2E_DIR/no-confirm.json"
}
NX_ACCEPT='{"decision":"ACCEPT","risk":"low","surfaces":[],"scope":"s","proposed_criteria":["c"],"questions":[],"reason":"r"}'

# ---------------------------------------------------------------- B14 helpers (NX32 to NX56)
NX_TERM='{"unvouched_session_action": false}'
# nx_pend <seq> <event> <args json> [facts json] [channel] — a stored person
# event of job 7 written by hand, as the person subcommands store it.
nx_pend() {
  mkdir -p "$NX_J/pending"
  jq -n --arg e "$2" --argjson a "$3" --argjson f "${4:-$NX_TERM}" --arg c "${5:-terminal}" '{event: $e, args: $a,
    channel: $c, caller: {pid: 4242, start: "Mon Nov 16 00:00:00 2026", ancestry: [4242, 1]}, facts: $f,
    raised_at: "2026-11-16T00:00:00Z"}' > "$NX_J/pending/$(printf '%020d' "$1")-$2.json"
}
# nx_nosync — the next pass has no sync: the default syncIntervalSeconds (60)
# and state.json last_sync_at set to now.
nx_nosync() {
  nx_settings 'del(.flow.factory.syncIntervalSeconds)'
  fe_py "import _flow_factory_jobs as jobs, _flow_factory as ff
p = jobs.resolve()
with jobs.global_lock(p, timeout=5):
    s = jobs.read_state(p)
    s['last_sync_at'] = ff.utc_now()
    jobs.write_state(p, s)"
}
# nx_later <seconds> — the UTC time that many seconds from now, for a comment
# that must come after a needs-info round's asked_at (the decision's now).
nx_later() { perl -MPOSIX=strftime -e 'print strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(time + $ARGV[0]))' "$1"; }
# nx_digest <items json> — plan 5.3's issue_digest, computed here by hand: the
# sha256 of the compact JSON of the items, non-ASCII kept.
nx_digest() {
  python3 -I -c 'import hashlib, json, sys
print(hashlib.sha256(json.dumps(json.loads(sys.argv[1]), separators=(",", ":"), ensure_ascii=False).encode("utf-8")).hexdigest())' "$1"
}
# nx_questions <NI id>... — the question records J/questions/<id>.json.
nx_questions() {
  mkdir -p "$NX_J/questions"
  local q
  for q in "$@"; do
    jq -n --arg q "$q" '{job: "issue-7-j1", id: $q, text: "Which port?", round: 1}' > "$NX_J/questions/$q.json"
  done
}
# nx_created — job 7's created line, recording job.json as it is now, so
# rebuild has a start (as PS13 writes it).
nx_created() {
  mkdir -p "$NX_J"
  jq -c '{type: "created", job: .key, time: "2026-11-16T00:00:00Z", pass: "p0", row: "1", event: "issue_labelled",
    from: null, to: .state, stay: false, effects_applied: [], effects_deferred: [], attempt: 0, channel: "engine",
    caller: {pid: 4242, start: "Mon Nov 16 00:00:00 2026", ancestry: [4242, 1]}, record: .}' "$NX_J/job.json" >> "$NX_J/events.jsonl"
}
# nx_rebuild_compare <what> — job.json replaced by '{', `rebuild 7` in a
# terminal, then every field compared with the live job.json, null and absent
# alike, less updated_at and head_sha (PS13) and the fields only a sync
# writes (issue_digest, sync_seen, priority_high: plan 2.2 "not restored").
nx_rebuild_compare() {
  local norm='del(.updated_at, .head_sha, .issue_digest, .sync_seen, .priority_high) | with_entries(select(.value != null))'
  cp "$NX_J/job.json" "$E2E_DIR/live.json"
  printf '{' > "$NX_J/job.json"
  fe_person_terminal issue-7-j1 "$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh" rebuild 7
  e2e_expect_equal 0 "$E2E_RC" "rebuild exit status"
  jq -S "$norm" "$E2E_DIR/live.json" > "$E2E_DIR/live.norm"
  jq -S "$norm" "$NX_J/job.json" > "$E2E_DIR/rebuilt.norm" 2>/dev/null
  printf -- '--- live and rebuilt job.json, normalized, diff\n%s\n' "$(diff "$E2E_DIR/live.norm" "$E2E_DIR/rebuilt.norm")" | _e2e_art
  e2e_expect_equal "" "$(diff "$E2E_DIR/live.norm" "$E2E_DIR/rebuilt.norm" | grep '^[<>]' | tr '\n' ';')" "fields that differ between the live and the rebuilt job ($1)"
}
# nx_wait_job_result — wait for the result of job 7's current directive.
nx_wait_job_result() {
  local d
  d=$(nx_jq "$NX_J/job.json" '.directive // empty')
  [ -n "$d" ] && fe_wait_for 45 "[ -f '$NX_J/results/$d.json' ]"
  return 0
}
# nx_comments_with <text> — comments posted to issue 7 whose body holds text.
nx_comments_with() {
  fe_world_posts | jq -r 'select(.method == "POST" and (.path | endswith("/issues/7/comments"))) | .body // ""' \
    | grep -cF -- "$1"
}
NX_HUMAN="needs a person to look at it"
# nx_world_labels — issue 7's labels on the world, as one JSON line.
nx_world_labels() { jq -c '.issues["7"].labels' "$FE_WORLD"; }
# nx_queued_blocked — job 7 queued, its body naming the open issue 3 as a
# blocker, so row 2 does not move it (T:2, dependency_open).
nx_queued_blocked() {
  nx_base queued
  fe_world_issue 7 "Add a port setting" "The service needs a port setting.
Blocked by #3"
  fe_world_issue 3 "A blocker" "Still open."
}
# nx_wrapper_next — `next` through the shipped wrapper (W: no seam).
nx_wrapper_next() {
  e2e_run_bin bin/flow-factory.sh next --executor headless
  nx_protocol "$E2E_OUT"
}
NX_NEEDS_INFO1="d['needs_info'] = {'asked_at': '2026-11-16T00:30:00Z', 'questions': ['NI-1'], 'round': 1, 'earlier': []}"


# ---------------------------------------------------------------- NX18
if nx_run NX18; then
_flow_test_begin "next: an outsider's edit after the vouch moves an intake job by row 51b (NX18, R100)"
fe_new nx18-untrusted-edit
# Source: plan R100 (E half); T:51b (intake, github_change, untrusted_edit
# true -> needs_human, reason untrusted_edit); T:facts.untrusted_edit (an
# edit after vouch_at by an editor below write); plan 3.1 the github_change
# raise rule (live inputs raise it with no pending change).
e2e_describe "job 7 in intake vouched at 00:00; the body edited at 01:00 by outsider (read access); one pass; then the same world without the edit"
nx_base intake
fe_world_perm outsider read
fe_world_edit issue:7 outsider 2026-11-16T01:00:00Z
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 51b "$(nx_rows)" "rows"
e2e_expect_equal "needs_human untrusted_edit" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.reason)"')" "state and reason"
e2e_expect_err_lacks "Traceback"
# Source: plan B14 step 8 (on entry to needs_human the needs-human notice and
# a label_add of labels.needsHuman, posted by the drain of the same pass).
e2e_expect_equal 1 "$(fe_world_posts | jq -r 'select(.method == "POST" and (.path | endswith("/issues/7/comments"))) | .body // ""' | grep -cF 'needs a person to look at it')" "one needs-human comment"
e2e_expect_equal '["flow:needs-human"]' "$(jq -c '.issues["7"].labels' "$FE_WORLD")" "the needs-human label"
fe_new nx18b-no-edit
e2e_describe "control: the same world with no edit"
nx_base intake
fe_judge_says "$NX_ACCEPT"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 0 "$(nx_rows | tr ' ' '\n' | grep -c '^51b$')" "row 51b lines"
e2e_expect_err_lacks "Traceback"
fi

# ---------------------------------------------------------------- NX19
if nx_run NX19; then
_flow_test_begin "next: a confirm key on the path parks by row 40b, posts one tier-confirm comment a pass later, and a key change releases it (NX19, AC8, R39)"
fe_new nx19-tier-park
# Source: T:40b (intake, launch_due, tier_confirm_blocking true and
# executor_can_confirm false -> waiting_operator, reason tier_confirm, record
# pending_keys); journal wave 1 Tiers (intake's path is issueAssign,
# issueUpdate, push, prCreate); plan 2.3 (the row 40b park line); plan B14
# step 8 (the tier-confirm comment is recorded in phase C and posted by the
# next pass's drain: none after pass 1, one after pass 2); T:41b
# (waiting_operator, sync_tick, tier_confirm_blocking false -> the resume
# state, clear pending_keys); plan 3.3 (the 40b scenarios use a seam copy
# with executor_can_confirm false).
e2e_describe "job 7 in intake; user settings tiers.issueAssign confirm; the seam copy with executor_can_confirm false; pass 1 parks, pass 2 posts the comment, then tiers.issueAssign journal and pass 3 releases"
nx_base intake
nx_settings '.tiers.issueAssign = "confirm"'
nx_no_confirm
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 1 exit status ($E2E_ERR)"
e2e_expect_equal 40b "$(nx_rows)" "rows after pass 1"
e2e_expect_equal 'waiting_operator tier_confirm ["issueAssign"]' "$(nx_jq "$NX_J/job.json" '"\(.state) \(.reason) \(.pending_keys | tojson)"')" "state, reason, pending_keys"
e2e_expect_equal '["issueAssign"]' "$(jq -c 'select(.type == "transition") | .fields.pending_keys' "$NX_J/events.jsonl")" "the 40b line's fields"
e2e_expect_equal 0 "$(fe_world_posts | grep -c .)" "posts after pass 1"
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 2 exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count '"WAITING_OPERATOR job=issue-7-j1 reason=tier_confirm keys=issueAssign next: change the key, or confirm from an interactive executor in default mode"')" "the 40b park line"
e2e_expect_equal 1 "$(nx_posts_to /issues/7/comments)" "tier-confirm comments posted after pass 2"
e2e_expect_equal 1 "$(fe_world_posts | jq -r '.body // ""' | grep -c 'tiers.issueAssign')" "the comment names the key"
e2e_expect_equal waiting_operator "$(nx_jq "$NX_J/job.json" .state)" "still parked after pass 2"
nx_settings '.tiers.issueAssign = "journal"'
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 3 exit status ($E2E_ERR)"
e2e_expect_equal "40b 41b" "$(nx_rows | cut -d' ' -f1-2)" "rows after pass 3"
e2e_expect_equal "null" "$(nx_jq "$NX_J/job.json" .pending_keys)" "pending_keys cleared"
fi

# ---------------------------------------------------------------- NX20
if nx_run NX20; then
_flow_test_begin "next: a failed base fetch and a job with no base both park by row 40b (NX20, R40)"
fe_new nx20-fetch-failed
# Source: plan 3.1 (a failed fetch or a missing ref counts as confirm); plan
# 2.3 (BASE_FETCH_FAILED and BASE_REF_UNRESOLVED lines); plan 3.3 (the two
# fail-closed parks, with no network call); T:40b.
e2e_describe "job 7 in intake with the origin URL pointed at a missing local path; the seam copy with executor_can_confirm false"
nx_base intake
_fe_in_scratch git remote set-url origin "$E2E_DIR/missing.git"
nx_no_confirm
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count '"BASE_FETCH_FAILED job=issue-7-j1 ref=origin/main ')" "the BASE_FETCH_FAILED line"
e2e_expect_equal 40b "$(nx_rows)" "rows"
e2e_expect_equal "waiting_operator tier_confirm" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.reason)"')" "state and reason"
fe_new nx20b-no-base
e2e_describe "job 7 in intake written without base"
nx_base intake "d.pop('base')"
nx_no_confirm
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count '"BASE_REF_UNRESOLVED job=issue-7-j1 ref=origin/-"')" "the BASE_REF_UNRESOLVED line"
e2e_expect_equal 40b "$(nx_rows)" "rows"
fi

# ---------------------------------------------------------------- NX21
if nx_run NX21; then
_flow_test_begin "next: row 11 records one assignment-and-label intent and the drain of the same pass posts it (NX21, AC9)"
fe_new nx21-row-11
# Source: T:11 (prepare, stage_succeeded -> spec; writes assignment and
# in-progress label); plan 2.2 (prepare's writes are one assign_label
# intent, gh issue edit with --add-assignee <engine login> and --add-label
# <labels.inProgress>, key issueAssign and issueUpdate; the drain of the
# same pass runs it); settings.json (issueAssign journal by default).
e2e_describe "job 7 in prepare with a completed stage result; plugin default tiers; a committed .decisions/ folder; one pass"
nx_base prepare
nx_stage_result prepare
( cd "$E2E_REPO" && mkdir -p .decisions && printf '# journal\n' > .decisions/README.md \
  && git add .decisions/README.md && git commit -q -m journal ) || _e2e_result fail "committed .decisions/"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 11 "$(nx_rows)" "rows"
e2e_expect_equal spec "$(nx_jq "$NX_J/job.json" .state)" "state"
e2e_expect_equal 1 "$(find "$NX_J/outbox" -name '*-11-*.json' | grep -c .)" "outbox items of row 11"
e2e_expect_equal '["flow-e2e-engine"] ["flow:in-progress"]' "$(jq -c '.issues["7"] | .assignees, .labels' "$FE_WORLD" | tr '\n' ' ' | sed 's/ $//')" "the issue's assignees and labels on the world"
# Source: plan R75 (the item is sent, and the trail holds one breadcrumb per
# journal key, two in all); plan 5.3 breadcrumb rule.
e2e_expect_equal sent "$(cat "$NX_J/outbox/"*-11-*.json | jq -r .status)" "the item is sent"
e2e_expect_equal "1 1" "$(cat "$E2E_REPO"/.decisions/auto-log/issue-7.*.md 2>/dev/null | grep -c 'tiers.issueAssign (journal, factory engine)') $(cat "$E2E_REPO"/.decisions/auto-log/issue-7.*.md 2>/dev/null | grep -c 'tiers.issueUpdate (journal, factory engine)')" "one breadcrumb for issueAssign and one for issueUpdate (R75)"
fi

# ---------------------------------------------------------------- NX22
if nx_run NX22; then
_flow_test_begin "next: row 40 holds the stage result, a key change releases it by row 41k, and the replay applies row 11 with no second intent (NX22, AC9, R73)"
fe_new nx22-row-40-41k
# Source: T:40 (blocking_write_confirm true -> waiting_operator, record
# pending_intent and the held stage result); plan 2.3 (the row 40 park
# line); T:41k (waiting_operator, sync_tick, intent_key_not_confirm true:
# the engine runs the write, then the replay); plan 2.2 (the confirmation of
# a released intent and the replay: row 11 wins with BWC false and records
# nothing for a kind the confirmed item covers; a replayed line clears
# held_result and confirmed_intent).
e2e_describe "job 7 in prepare with a completed stage result; tiers.issueAssign confirm; pass 1 parks; then tiers.issueAssign journal and pass 2 releases and replays"
nx_base prepare
nx_stage_result prepare
nx_settings '.tiers.issueAssign = "confirm"'
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 1 exit status ($E2E_ERR)"
e2e_expect_equal 40 "$(nx_rows)" "rows after pass 1"
NX_I=$(nx_jq "$NX_J/job.json" .pending_intent.id)
e2e_expect_equal "issue-7-j1-40-1 assign_label stage_succeeded" "$(nx_jq "$NX_J/job.json" '"\(.pending_intent.id) \(.pending_intent.kind) \(.held_result.event)"')" "pending_intent and held_result"
e2e_expect_equal 1 "$(nx_line_count "\"WAITING_OPERATOR job=issue-7-j1 intent=$NX_I kind=assign_label keys=issueAssign,issueUpdate next: flow-factory.sh confirm $NX_I in a terminal, or change the key\"")" "the row 40 park line"
e2e_expect_equal 0 "$(fe_world_posts | grep -c .)" "nothing posted while parked"
nx_settings '.tiers.issueAssign = "journal"'
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 2 exit status ($E2E_ERR)"
e2e_expect_equal "40 41k 11" "$(nx_rows)" "rows after pass 2"
e2e_expect_equal "spec null null null" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.pending_intent) \(.held_result) \(.confirmed_intent)"')" "state and the cleared fields"
e2e_expect_equal 1 "$(find "$NX_J/outbox" -name '*.json' | grep -c .)" "outbox items (no second intent)"
e2e_expect_equal "$NX_I applied" "$(jq -r 'select(.type == "replayed") | "\(.intent) \(.outcome)"' "$NX_J/events.jsonl")" "the replayed line"
e2e_expect_equal '["flow-e2e-engine"]' "$(jq -c '.issues["7"].assignees' "$FE_WORLD")" "the assignment written once"
fi

# ---------------------------------------------------------------- NX23
if nx_run NX23; then
_flow_test_begin "next: a trusted /flow-factory cancel comment cancels a queued job; an untrusted one is listed once (NX23, AC3)"
fe_new nx23-comment-cancel
# Source: design person_channels (a trusted command comment raises the
# person event through the comment channel); T:53 (person_cancel ->
# cancelled); plan 2.3 (UNTRUSTED_COMMAND line, printed once per comment).
e2e_describe "job 7 queued, its body naming an open blocker (Blocked by #3), so row 2 does not move it (T:2, dependency_open); comment 101 by outsider (read) and comment 102 by maintainer (write), both /flow-factory cancel, after vouch_at; two passes"
nx_base queued
fe_world_issue 7 "Add a port setting" "The service needs a port setting.
Blocked by #3"
fe_world_issue 3 "A blocker" "Still open."
fe_world_comment 7 101 outsider read 2026-11-16T01:00:00Z "/flow-factory cancel"
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 1 exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count '"UNTRUSTED_COMMAND job=issue-7-j1 comment=101 author=outsider at=2026-11-16T01:00:00Z length=20"')" "the UNTRUSTED_COMMAND line"
e2e_expect_equal queued "$(nx_jq "$NX_J/job.json" .state)" "still queued"
fe_world_comment 7 102 maintainer write 2026-11-16T01:05:00Z "/flow-factory cancel"
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 2 exit status ($E2E_ERR)"
e2e_expect_equal 0 "$(nx_line_count 'UNTRUSTED_COMMAND job=issue-7-j1 comment=101')" "no second UNTRUSTED_COMMAND line"
e2e_expect_equal 53 "$(nx_rows | tr ' ' '\n' | tail -n 1)" "the last row"
e2e_expect_equal cancelled "$(nx_jq "$NX_J/job.json" .state)" "state"
e2e_expect_equal "comment:102" "$(jq -r 'select(.type == "transition" and .row == "53") | .channel' "$NX_J/events.jsonl")" "the channel of the cancel"
fi

# ---------------------------------------------------------------- NX24
if nx_run NX24; then
_flow_test_begin "next: row 66i with no issue set refuses with issue_set_stale and launches after a synced pass (NX24, R92, R77)"
fe_new nx24-issue-set-stale
# Source: plan 3.1 "Row 66i" (the issue_md handler reads J/sync/issue-set.json;
# missing, it raises issue_set_stale, reported as EFFECT_FAILED, and nothing
# is launched; the launch goes ahead after the next completed sync).
e2e_describe "job 7 in intake with an issue_digest but no issue set; a pass with no sync (state.json last_sync_at now, the default 60 s interval); then a pass with a sync"
nx_base intake "d['issue_digest'] = 'a' * 64"
fe_judge_says "$NX_ACCEPT"
nx_settings 'del(.flow.factory.syncIntervalSeconds)'
fe_py "import _flow_factory_jobs as jobs, _flow_factory as ff
p = jobs.resolve()
with jobs.global_lock(p, timeout=5):
    s = jobs.read_state(p)
    s['last_sync_at'] = ff.utc_now()
    jobs.write_state(p, s)"
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 1 exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count '"EFFECT_FAILED job=issue-7-j1 row=66i issue_set_stale"')" "the EFFECT_FAILED line"
e2e_expect_equal "" "$(nx_rows)" "rows"
e2e_expect_equal 0 "$(nx_launches)" "claude launches"
nx_settings '.flow.factory.syncIntervalSeconds = 0'
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 2 exit status ($E2E_ERR)"
e2e_expect_equal 66i "$(nx_rows)" "rows after a synced pass"
fe_wait_for 45 "[ -f '$NX_J/results/issue-7-j1-intake-1.json' ]"
e2e_expect_equal 1 "$(nx_launches)" "claude launches"
fi

# ---------------------------------------------------------------- NX25
if nx_run NX25; then
_flow_test_begin "next: a cancel whose PR close cannot be recorded keeps what the kill did and applies on the next pass (NX25, carry item 2, R37)"
fe_new nx25-carry-2
# Source: plan B14 step 9 (carry item 2: the handled caller effects run in
# the try that follows kill_current; on a failure job.json keeps the fields
# kill_current set, cost among them, and the pass reports EFFECT_FAILED);
# T:53 (person_cancel -> cancelled; kill a live worker first; close a
# factory PR through the outbox); 1a's charge of a run its launcher can no
# longer charge (basis limit_plus_turn, once per directive).
e2e_describe "job 7 in build with PR 12 and a current directive whose launcher and child are gone; a stored person_cancel; J/outbox is a regular file, so the PR close cannot be recorded; pass 1 fails the effect, pass 2 (outbox fixed) applies row 53"
e2e_repo main
fe_record
fe_enable
fe_gh api_repos_flow-e2e_scratch_pulls_12 '{"number": 12, "state": "open", "merged": false, "merged_at": null, "head": {"sha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}'
fe_job 7 build "d['pr'] = 12; d['head_sha'] = 'a' * 40; d['directive'] = 'issue-7-j1-build-1'; d['holds_slot'] = True"
NX_F=$(fe_factory_dir); NX_J="$NX_F/jobs/issue-7"; NX_FIX=""
fe_directive issue-7-j1-build-1 "d['max_budget_usd'] = 0.5"
NX_DEAD=$(_fe_in_scratch sh -c 'echo $$')
jq -n --argjson p "$NX_DEAD" '{directive: "issue-7-j1-build-1", kind: "worker", host: "h", launcher_pid: $p,
  launcher_start: "Mon Nov 16 00:00:00 2026", started_at: "2026-11-16T00:00:00Z", heartbeat_at: "2026-11-16T00:00:00Z",
  child_pid: $p, child_pgid: $p, child_start: null, revoked_at: null}' > "$NX_J/directives/issue-7-j1-build-1.lease.json"
mkdir -p "$NX_J/pending"
jq -n '{event: "person_cancel", args: {}, channel: "terminal",
  caller: {pid: 4242, start: "Mon Nov 16 00:00:00 2026", ancestry: [4242, 1]},
  facts: {unvouched_session_action: false}, raised_at: "2026-11-16T00:00:00Z"}' > "$NX_J/pending/00000000000000000001-person_cancel.json"
printf 'not a folder\n' > "$NX_J/outbox"
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 1 exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count '"EFFECT_FAILED job=issue-7-j1 row=53 outbox_unwritable')" "the EFFECT_FAILED line"
e2e_expect_equal "build 1 issue-7-j1-build-1 limit_plus_turn" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.cost.runs | length) \(.cost.runs[0].directive) \(.cost.runs[0].basis)"')" "state kept, the lost run charged once"
e2e_expect_equal yes "$(nx_jq "$NX_J/directives/issue-7-j1-build-1.lease.json" 'if .revoked_at then "yes" else "no" end')" "the lease revoked"
e2e_expect_equal 1 "$(find "$NX_J/pending" -name '*-person_cancel.json' | grep -c .)" "the cancel kept for the next pass"
rm -f "$NX_J/outbox"
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 2 exit status ($E2E_ERR)"
e2e_expect_equal "cancelled 1" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.cost.runs | length)"')" "cancelled, no second charge"
e2e_expect_equal 53 "$(nx_rows)" "rows"
e2e_expect_equal 1 "$(cat "$NX_J/outbox/"*.json 2>/dev/null | jq -s 'map(select(.kind == "pr_close")) | length')" "one pr_close item"
fi

# ---------------------------------------------------------------- NX26
if nx_run NX26; then
_flow_test_begin "next: a retry re-vouches the waiting untrusted reply, but not one edited after the retry (NX26, T:8r, R7)"
fe_new nx26-revouch
# Source: T:8r (needs_info, person_retry, intake_rounds_exhausted false ->
# intake; re-vouch: vouch_at = now, revouched_replies gains each waiting
# untrusted reply with the sha256 of its body); journal wave 2 "R7 is not
# closed by B4" (a reply edited between the retry and the re-vouching sync is
# not trusted); plan 5.3 Context (ctx.sync["revouch"]).
e2e_describe "job 7 in needs_info asking NI-1 at 00:30; comment 202 by outsider (read) naming NI-1 at 01:00; comment 203 by maintainer (write) /flow-factory retry at 01:10; comment 202 edited by outsider at 01:20; one pass; then the same without the edit"
nx_revouch() {
  nx_base needs_info "d['needs_info'] = {'asked_at': '2026-11-16T00:30:00Z', 'questions': ['NI-1'], 'round': 1, 'earlier': []}"
  mkdir -p "$NX_J/questions"
  jq -n '{job: "issue-7-j1", id: "NI-1", text: "Which port?", round: 1}' > "$NX_J/questions/NI-1.json"
  fe_world_comment 7 202 outsider read 2026-11-16T01:00:00Z "NI-1: use port 9090"
  fe_world_comment 7 203 maintainer write 2026-11-16T01:10:00Z "/flow-factory retry"
}
nx_revouch
fe_world_edit comment:202 outsider 2026-11-16T01:20:00Z
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 8r "$(nx_rows)" "rows"
e2e_expect_equal "intake {}" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.revouched_replies | tojson)"')" "state and revouched_replies (the reply edited after the retry is left out)"
e2e_expect_equal absent "$([ -e "$NX_J/sync/issue-set.json" ] && echo present || echo absent)" "J/sync/issue-set.json deleted with the re-vouch (plan 2.2, R92)"
e2e_expect_equal moved "$(nx_jq "$NX_J/job.json" 'if .vouch_at == "2026-11-16T00:00:00Z" then "kept" else "moved" end')" "vouch_at moved to the time of the re-vouch (T:8r)"
fe_new nx26b-revouch
e2e_describe "control: the same with no edit of comment 202"
nx_revouch
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 8r "$(nx_rows)" "rows"
NX_SHA=$(printf '%s' "NI-1: use port 9090" | shasum -a 256 | cut -d' ' -f1)
e2e_expect_equal "{\"202\":\"$NX_SHA\"}" "$(nx_jq "$NX_J/job.json" '.revouched_replies | tojson')" "revouched_replies holds the reply and the sha256 of its body"
e2e_expect_equal "$(nx_jq "$NX_J/job.json" '.revouched_replies | tojson')" "$(jq -c 'select(.type == "transition") | .fields.revouched_replies' "$NX_J/events.jsonl")" "the 8r line's fields carry it"
fi

# ---------------------------------------------------------------- NX27
if nx_run NX27; then
_flow_test_begin "next: a result reached through a linked J/results does not finish the directive (NX27, journal wave 4 linked job folders)"
fe_new nx27-linked-results
# Source: journal wave 4 "Linked job folders" (a linked J/results must not
# mark a directive finished; B14 owns directive_open); 1a's directive_open (a
# directive with no result and no revoked lease is open, so the pass ends
# with wait and starts nothing).
e2e_describe "job 7 in build whose current directive was made now and has no lease; J/results is a symbolic link to a folder holding a result for that directive"
e2e_repo main
fe_record
fe_enable
fe_job 7 build "d['directive'] = 'issue-7-j1-build-1'; d['holds_slot'] = True"
NX_F=$(fe_factory_dir); NX_J="$NX_F/jobs/issue-7"; NX_FIX=""
fe_directive issue-7-j1-build-1 "d['created_at'] = __import__('time').strftime('%Y-%m-%dT%H:%M:%SZ', __import__('time').gmtime())"
mkdir -p "$E2E_DIR/elsewhere"
jq -n '{directive: "issue-7-j1-build-1", outcome: "completed", written_at: "2026-11-16T00:00:00Z",
  event: "stage_succeeded", session_id: null, num_turns: null, api_error_status: null, is_error: null,
  permission_denials: null, terminal_reason: null, charged_usd: null, charge_basis: null,
  total_cost_usd: null, since_last_usd: null}' > "$E2E_DIR/elsewhere/issue-7-j1-build-1.json"
ln -s "$E2E_DIR/elsewhere" "$NX_J/results"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal wait "$(printf '%s\n' "$E2E_OUT" | tail -n 1)" "the final word (the directive is still open)"
e2e_expect_equal issue-7-j1-build-1 "$(nx_jq "$NX_J/job.json" .directive)" "the current directive"
e2e_expect_equal "" "$(nx_rows)" "rows"
fi

# ---------------------------------------------------------------- NX28
if nx_run NX28; then
_flow_test_begin "next: a confirm naming another intent is refused, runs nothing and is not retried (NX28, R68)"
fe_new nx28-other-intent
# Source: plan R68 and 5.3 (run_literal raises IntentNotPending unless the
# id is pending_intent.id; the refusal line INTENT_NOT_PENDING=<id>
# pending=<id>, B6); T:41 (person_confirm runs exactly the stored literal of
# the pending intent). A refusal drops the stored event (1a apply_pending:
# applied, nomove and refused drop it), so it is not tried every pass.
e2e_describe "job 7 parked by row 40 with intent issue-7-j1-40-1 (as NX22 pass 1); a stored person_confirm naming issue-7-j1-40-9; one pass"
nx_base prepare
nx_stage_result prepare
nx_settings '.tiers.issueAssign = "confirm"'
nx_next
e2e_expect_equal 40 "$(nx_rows)" "rows after the park"
jq -n '{event: "person_confirm", args: {intent: "issue-7-j1-40-9"}, channel: "terminal",
  caller: {pid: 4242, start: "Mon Nov 16 00:00:00 2026", ancestry: [4242, 1]},
  facts: {unvouched_session_action: false}, raised_at: "2026-11-16T00:00:00Z"}' > "$NX_J/pending/00000000000000000009-person_confirm.json"
nx_next
e2e_expect_equal 3 "$E2E_RC" "exit status (a refusal in the pass)"
e2e_expect_equal 1 "$(nx_line_count '"INTENT_NOT_PENDING=issue-7-j1-40-9 pending=issue-7-j1-40-1"')" "the refusal line"
e2e_expect_equal "waiting_operator issue-7-j1-40-1" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.pending_intent.id)"')" "still parked on its own intent"
e2e_expect_equal 0 "$(fe_world_posts | grep -c .)" "nothing posted"
e2e_expect_equal 0 "$(find "$NX_J/pending" -name '*-person_confirm.json' | grep -c .)" "the confirm dropped"
fi

# ---------------------------------------------------------------- NX29
if nx_run NX29; then
_flow_test_begin "next: a trusted needs-info reply returns the job to intake by row 8, records the reply ids and removes the needs-info label (NX29, AC5, B14 step 8)"
fe_new nx29-row-8-labels
# Source: T:8 (needs_info, github_change, needs_info_answer true -> intake;
# record the answer comment ids in events.jsonl; set baseline_pending);
# plan B14 step 8 (on leaving needs_info, a label_remove for each label in
# labels_set, recorded with the row, posted by the drain of the same pass;
# a labels_set line follows the change); plan 2.2 (labels_set).
e2e_describe "job 7 in needs_info asking NI-1 at 00:30, labels_set [flow:needs-info] and the label on the issue; comment 201 by maintainer (write) naming NI-1 at 01:00; one pass; then a second pass"
nx_base needs_info "d['needs_info'] = {'asked_at': '2026-11-16T00:30:00Z', 'questions': ['NI-1'], 'round': 1, 'earlier': []}; d['labels_set'] = ['flow:needs-info']"
fe_judge_says "$NX_ACCEPT"
fe_world_comment 7 201 maintainer write 2026-11-16T01:00:00Z "NI-1: use port 8080"
jq '.issues["7"].labels += ["flow:needs-info"]' "$FE_WORLD" > "$FE_WORLD.t" && mv "$FE_WORLD.t" "$FE_WORLD"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 8 "$(nx_rows)" "rows"
e2e_expect_equal "intake true" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.baseline_pending)"')" "state and baseline_pending"
e2e_expect_equal "[201]" "$(jq -c 'select(.type == "answer_comments") | .comments' "$NX_J/events.jsonl")" "the answer comment ids in events.jsonl"
e2e_expect_equal "[]" "$(jq -c 'select(.type == "labels_set") | .labels_set' "$NX_J/events.jsonl")" "the labels_set line"
e2e_expect_equal 1 "$(fe_world_posts | jq -r 'select(.method == "DELETE") | .path' | grep -c '/issues/7/labels/flow%3Aneeds-info$')" "the label removed on GitHub"
# Source: plan R63 (a second pass removes nothing).
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 2 exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(fe_world_posts | jq -r 'select(.method == "DELETE") | .path' | grep -c '/issues/7/labels/')" "no second label removal (R63)"
e2e_expect_equal 1 "$(jq -c 'select(.type == "labels_set")' "$NX_J/events.jsonl" | grep -c .)" "no second labels_set line"
nx_wait_job_result
fi

# ---------------------------------------------------------------- NX30
if nx_run NX30; then
_flow_test_begin "next: the push rows wait on the 1e pre-push input outside a seam, and under a seam list their push texts as 1e (NX30, B14 step 0)"
fe_new nx30-push-rows
# Source: plan B14 test plan "the push rows through next" (no seam: choose
# returns Blocked(prepush_protected_failed, 1e) for a winner whose writes
# include push, so the job stays; under a seam with no prepush_fails and
# journal tier keys row 21 applies and its line lists the push, PR create
# and PR record texts in effects_deferred with phase 1e; the same for rows
# 30 and 34); plan B13 table (the three texts moved to 1e, Q11).
e2e_describe "job 7 in open_pr with a completed stage result through the shipped wrapper (no seam); then the same under the ordinary seam; then rework and resolve under the seam"
nx_base open_pr
nx_stage_result open_pr
e2e_run_bin bin/flow-factory.sh next --executor headless
e2e_expect_equal 0 "$E2E_RC" "no seam: exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count '"BLOCKED_UNBUILT job=issue-7-j1 state=open_pr event=stage_succeeded fact=prepush_protected_failed phase=1e"')" "no seam: the BLOCKED_UNBUILT line"
e2e_expect_equal open_pr "$(nx_jq "$NX_J/job.json" .state)" "no seam: the job stays in open_pr"
for NX_S in open_pr:21 rework:30 resolve:34; do
  fe_new "nx30-row-${NX_S#*:}"
  e2e_describe "job 7 in ${NX_S%%:*} with a completed stage result; the ordinary seam (no prepush_fails); plugin default tiers"
  nx_base "${NX_S%%:*}"
  nx_stage_result "${NX_S%%:*}"
  nx_next
  e2e_expect_equal 0 "$E2E_RC" "${NX_S%%:*}: exit status ($E2E_ERR)"
  e2e_expect_equal "${NX_S#*:} gate" "$(jq -r 'select(.type == "transition") | "\(.row) \(.to)"' "$NX_J/events.jsonl")" "${NX_S%%:*}: row and target"
  e2e_expect_equal 1e "$(jq -r 'select(.type == "transition") | [.effects_deferred[] | select(.effect == "push") | .phase] | join(",")' "$NX_J/events.jsonl")" "${NX_S%%:*}: the push text deferred to 1e"
done
fi

# ---------------------------------------------------------------- NX31
if nx_run NX31; then
_flow_test_begin "next: an untrusted edit during a row 40 park drops the pending intent by row 51bw (NX31, R74)"
fe_new nx31-drop-intent
# Source: T:51bw (waiting_operator, github_change, untrusted_edit true ->
# needs_human; drop the pending intent); plan 2.2 "Dropped items" and B14
# step 7 (the caller drops the outbox item through drop_intent, which
# appends intent_dropped before it saves the item as dropped, so a later key
# change cannot send it).
e2e_describe "job 7 parked by row 40 (as NX22 pass 1); then an outsider edits the body; one pass; then the key changes and one more pass"
nx_base prepare
nx_stage_result prepare
nx_settings '.tiers.issueAssign = "confirm"'
nx_next
e2e_expect_equal 40 "$(nx_rows)" "rows after the park"
fe_world_perm outsider read
fe_world_edit issue:7 outsider 2026-11-16T01:00:00Z
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal "40 51bw" "$(nx_rows)" "rows"
e2e_expect_equal "needs_human null" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.pending_intent)"')" "state and pending_intent"
e2e_expect_equal issue-7-j1-40-1 "$(jq -r 'select(.type == "intent_dropped") | .id' "$NX_J/events.jsonl")" "the intent_dropped line"
e2e_expect_equal dropped "$(nx_jq "$NX_J/outbox/issue-7-j1-40-1.json" .status)" "the item is dropped"
nx_settings '.tiers.issueAssign = "journal"'
nx_next
e2e_expect_equal "[]" "$(jq -c '.issues["7"].assignees' "$FE_WORLD")" "the dropped write never runs"
fi

# ---------------------------------------------------------------- NX32
if nx_run NX32; then
_flow_test_begin "next: a linked J/sync is never read or unlinked through (NX32, journal wave 4 linked job folders)"
fe_new nx32a-linked-sync-66i
# Source: the task rule "a linked J/ folder is refused at every read" (journal
# wave 4, linked job folders); plan 3.1 "Row 66i" (a set that cannot be read
# is issue_set_stale, reported as EFFECT_FAILED, and nothing is launched).
e2e_describe "job 7 in intake; a pass with no sync; J/sync is a link to an outside folder holding an issue set whose digest is the hand-computed digest of its items and job.json's issue_digest"
NX_ITEMS='[["title","Add a port setting"],["body","The service needs a port setting."]]'
NX_D=$(nx_digest "$NX_ITEMS")
nx_base intake "d['issue_digest'] = '$NX_D'"
fe_judge_says "$NX_ACCEPT"
nx_nosync
mkdir -p "$E2E_DIR/outside-sync"
jq -n --argjson i "$NX_ITEMS" --arg d "$NX_D" '{synced_at: "2026-11-16T00:00:00Z", items: $i, others: [], digest: $d}' > "$E2E_DIR/outside-sync/issue-set.json"
ln -s "$E2E_DIR/outside-sync" "$NX_J/sync"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count '"EFFECT_FAILED job=issue-7-j1 row=66i issue_set_stale"')" "the EFFECT_FAILED line"
e2e_expect_equal "" "$(nx_rows)" "rows"
e2e_expect_equal 0 "$(nx_launches)" "claude launches"
e2e_expect_equal absent "$([ -e "$NX_J/in-copies/issue.md" ] && echo present || echo absent)" "in-copies/issue.md"
fe_new nx32b-linked-sync-8r
# Source: the same rule for the unlink (plan 2.2: rows that re-vouch delete
# J/sync/issue-set.json; never a file outside J/); T:8r (needs_info,
# person_retry -> intake).
e2e_describe "job 7 in needs_info; a stored terminal retry; J/sync is a link to an outside folder holding issue-set.json; one pass with a sync"
nx_base needs_info "$NX_NEEDS_INFO1"
mkdir -p "$E2E_DIR/outside-sync"
printf '{"items": [], "others": [], "digest": "x"}\n' > "$E2E_DIR/outside-sync/issue-set.json"
ln -s "$E2E_DIR/outside-sync" "$NX_J/sync"
nx_pend 1 person_retry '{}'
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 8r "$(nx_rows)" "rows"
e2e_expect_equal present "$([ -f "$E2E_DIR/outside-sync/issue-set.json" ] && echo present || echo absent)" "the outside issue-set.json is still there"
e2e_expect_equal 0 "$(nx_launches)" "claude launches"
fi

# ---------------------------------------------------------------- NX33
if nx_run NX33; then
_flow_test_begin "next: a linked J/results or J/archive is never read through (NX33, journal wave 4 linked job folders)"
fe_new nx33a-linked-results-replay
# Source: plan B14 step 10 (a missing or unreadable result gives the replay
# result=None); journal wave 4 (a linked J/results is treated as absent,
# _result_present); plan B13 table (row 6's intake_record needs the judge
# reply, judge_result_missing without one); B14 step 10 (a failed replay keeps
# held_result and confirmed_intent).
e2e_describe "job 7 in intake with held_result judge_accept naming directive issue-7-j1-intake-1 and confirmed_intent set (the crash case); J/results is a link to a folder holding that directive's result with an ACCEPT judge reply; a pass with no sync"
nx_base intake "d['held_result'] = {'event': 'judge_accept', 'args': {'directive': 'issue-7-j1-intake-1'}, 'channel': 'launcher', 'caller': {'pid': 4242, 'start': 'Mon Nov 16 00:00:00 2026', 'ancestry': [4242, 1]}, 'facts': {}}; d['confirmed_intent'] = 'issue-7-j1-40-1'"
nx_nosync
mkdir -p "$E2E_DIR/outside-results"
jq -n --argjson j "$NX_ACCEPT" '{directive: "issue-7-j1-intake-1", outcome: "completed", written_at: "2026-11-16T00:00:00Z",
  event: null, session_id: null, num_turns: null, api_error_status: null, is_error: null, permission_denials: null,
  terminal_reason: null, charged_usd: null, charge_basis: null, total_cost_usd: null, since_last_usd: null, judge: $j}' \
  > "$E2E_DIR/outside-results/issue-7-j1-intake-1.json"
ln -s "$E2E_DIR/outside-results" "$NX_J/results"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count '"EFFECT_FAILED job=issue-7-j1 row=6 judge_result_missing"')" "the replay fails: no result read through the link"
e2e_expect_equal "intake judge_accept issue-7-j1-40-1" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.held_result.event) \(.confirmed_intent)"')" "state, and held_result and confirmed_intent kept"
e2e_expect_equal absent "$([ -e "$NX_J/in-copies/intake.json" ] && echo present || echo absent)" "in-copies/intake.json"

# nx33_creation <archive: entry|folder|plain> — job 7 cancelled as
# issue-7-j2, vouched at 2026-11-16; an archived job j1 vouched at 2026-11-15
# (before the new label); the issue labelled again at 2026-11-17 by write
# access.
nx33_creation() {
  nx_base cancelled "d['key'] = 'issue-7-j2'"
  fe_world_label 7 flow:factory maintainer write 2026-11-17T00:00:00Z
  mkdir -p "$E2E_DIR/outside/j1"
  jq -n '{key: "issue-7-j1", issue: 7, state: "cancelled", vouch_at: "2026-11-15T00:00:00Z"}' > "$E2E_DIR/outside/j1/job.json"
  case "$1" in
    entry) mkdir -p "$NX_J/archive"; ln -s "$E2E_DIR/outside/j1" "$NX_J/archive/j1" ;;
    folder) ln -s "$E2E_DIR/outside" "$NX_J/archive" ;;
    plain) mkdir -p "$NX_J/archive/j1"; cp "$E2E_DIR/outside/j1/job.json" "$NX_J/archive/j1/job.json" ;;
  esac
}
fe_new nx33b-archive-plain
# Source: creation row 1's fifth condition (every terminal job's vouch_at is
# before the label; plan B4 creation_conditions); the control for nx33c/d.
e2e_describe "control: the archived job j1 is a plain folder; one pass creates issue-7-j3"
nx33_creation plain
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal "issue-7-j3 queued" "$(nx_jq "$NX_J/job.json" '"\(.key) \(.state)"')" "a new job is created"
fe_new nx33c-archive-entry-linked
# Source: plan B4 creation_conditions (an unreadable archived job gives None,
# a vouch at or after the label, so creation waits); the linked-folder rule.
e2e_describe "archive/j1 is a link to the outside folder; one pass"
nx33_creation entry
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal "issue-7-j2 cancelled" "$(nx_jq "$NX_J/job.json" '"\(.key) \(.state)"')" "no job is created"
fe_new nx33d-archive-folder-linked
e2e_describe "J/archive is a link to the outside folder; one pass"
nx33_creation folder
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal "issue-7-j2 cancelled" "$(nx_jq "$NX_J/job.json" '"\(.key) \(.state)"')" "no job is created"
e2e_expect_equal 0 "$(nx_line_count 'FACTORY_REFUSED')" "creation waits before any write (no FACTORY_REFUSED line)"
e2e_expect_equal "j1" "$(ls "$E2E_DIR/outside" | tr '\n' ' ' | sed 's/ $//')" "nothing written in the outside folder"

fe_new nx33e-linked-results-stream
# Source: 1a's charge of a run its launcher can no longer charge (basis
# limit_plus_turn; the session from the run's stream, else the directive's);
# the linked-folder rule (no stream read through a linked J/results).
e2e_describe "job 7 in build with a current directive whose launcher and child are gone; a stored person_cancel; J/results is a link to a folder holding the directive's stream, whose init names session outside-session"
e2e_repo main
fe_record
fe_enable
fe_job 7 build "d['directive'] = 'issue-7-j1-build-1'; d['holds_slot'] = True"
NX_F=$(fe_factory_dir); NX_J="$NX_F/jobs/issue-7"; NX_FIX=""
fe_directive issue-7-j1-build-1 "d['max_budget_usd'] = 0.5"
NX_DEAD=$(_fe_in_scratch sh -c 'echo $$')
jq -n --argjson p "$NX_DEAD" '{directive: "issue-7-j1-build-1", kind: "worker", host: "h", launcher_pid: $p,
  launcher_start: "Mon Nov 16 00:00:00 2026", started_at: "2026-11-16T00:00:00Z", heartbeat_at: "2026-11-16T00:00:00Z",
  child_pid: $p, child_pgid: $p, child_start: null, revoked_at: null}' > "$NX_J/directives/issue-7-j1-build-1.lease.json"
nx_pend 1 person_cancel '{}'
mkdir -p "$E2E_DIR/outside-results"
printf '%s\n' '{"type":"system","subtype":"init","session_id":"outside-session"}' > "$E2E_DIR/outside-results/issue-7-j1-build-1.stream.jsonl"
ln -s "$E2E_DIR/outside-results" "$NX_J/results"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal "cancelled 1 limit_plus_turn" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.cost.runs | length) \(.cost.runs[0].basis)"')" "cancelled, the lost run charged once"
e2e_expect_equal 0 "$(grep -c outside-session "$NX_J/job.json" "$NX_J/events.jsonl" | awk -F: '{s += $2} END {print s}')" "no session id read through the link"

fe_new nx33e2-linked-stream-file
e2e_describe "as nx33e, with J/results a folder and only the directive's stream file a link to the outside copy"
e2e_repo main
fe_record
fe_enable
fe_job 7 build "d['directive'] = 'issue-7-j1-build-1'; d['holds_slot'] = True"
NX_F=$(fe_factory_dir); NX_J="$NX_F/jobs/issue-7"; NX_FIX=""
fe_directive issue-7-j1-build-1 "d['max_budget_usd'] = 0.5"
NX_DEAD=$(_fe_in_scratch sh -c 'echo $$')
jq -n --argjson p "$NX_DEAD" '{directive: "issue-7-j1-build-1", kind: "worker", host: "h", launcher_pid: $p,
  launcher_start: "Mon Nov 16 00:00:00 2026", started_at: "2026-11-16T00:00:00Z", heartbeat_at: "2026-11-16T00:00:00Z",
  child_pid: $p, child_pgid: $p, child_start: null, revoked_at: null}' > "$NX_J/directives/issue-7-j1-build-1.lease.json"
nx_pend 1 person_cancel '{}'
mkdir -p "$E2E_DIR/outside-stream" "$NX_J/results"
printf '%s\n' '{"type":"system","subtype":"init","session_id":"outside-session"}' > "$E2E_DIR/outside-stream/issue-7-j1-build-1.stream.jsonl"
ln -s "$E2E_DIR/outside-stream/issue-7-j1-build-1.stream.jsonl" "$NX_J/results/issue-7-j1-build-1.stream.jsonl"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal "cancelled 1" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.cost.runs | length)"')" "cancelled, the lost run charged once"
e2e_expect_equal 0 "$(grep -c outside-session "$NX_J/job.json" "$NX_J/events.jsonl" | awk -F: '{s += $2} END {print s}')" "no session id read through the linked stream file"

fe_new nx33f-linked-results-report
# Source: 1a plan 2.4 report rule (a pending-report line is applied only when
# its result can be written; every other line is report_refused); the
# linked-folder rule (no result written or read through a linked J/results).
e2e_describe "as NX-AC8a: the launcher's shell pending-report line; then J/results is moved out and replaced by a link to it; one pass"
nxac8_setup
mv "$NX_J/results" "$E2E_DIR/outside-reports"
ln -s "$E2E_DIR/outside-reports" "$NX_J/results"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_ev_count 7 '.type == "report_refused" and .reason == "results_linked"')" "the report refused for the link"
e2e_expect_equal build "$(nx_jq "$NX_J/job.json" .state)" "state"
e2e_expect_equal absent "$([ -e "$E2E_DIR/outside-reports/$D1.json" ] && echo present || echo absent)" "no result written through the link"
fe_new nx33g-linked-stream-report
e2e_describe "as nx33f, with J/results a folder and only the directive's stream file replaced by a link to a copy outside"
nxac8_setup
mkdir -p "$E2E_DIR/outside-stream"
mv "$NX_J/results/$D1.stream.jsonl" "$E2E_DIR/outside-stream/$D1.stream.jsonl"
ln -s "$E2E_DIR/outside-stream/$D1.stream.jsonl" "$NX_J/results/$D1.stream.jsonl"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_ev_count 7 '.type == "report_refused" and .reason == "results_linked"')" "the report refused for the linked stream"
e2e_expect_equal build "$(nx_jq "$NX_J/job.json" .state)" "state"
fi

# ---------------------------------------------------------------- NX34
if nx_run NX34; then
_flow_test_begin "next: row 41e records the observed effect and never runs the write (NX34, T:41e)"
fe_new nx34-41e-record-only
# Source: T:41e (waiting_operator, github_change, intent_effect_observed true
# -> resume state; effects "record the observed effect", replay): no effect
# runs the write. The intent's keys still resolve to confirm (tiers
# issueAssign confirm), so running it would be a write no person confirmed.
# An effect gone before the handler looks is not observed: the decision
# fails (EFFECT_FAILED) and the job stays parked.
e2e_describe "job 7 parked by row 40 (tiers.issueAssign confirm); a person adds the assignee and the label on GitHub; in the next pass the world drops both right after the read that computes intent_effect_observed (the second read of the issue in the pass: the sync's is the first)"
nx_base prepare
nx_stage_result prepare
nx_settings '.tiers.issueAssign = "confirm"'
nx_next
e2e_expect_equal 40 "$(nx_rows)" "rows after the park"
jq '.issues["7"].assignees = ["flow-e2e-engine"] | .issues["7"].labels = ["flow:in-progress"]' "$FE_WORLD" > "$FE_WORLD.t" && mv "$FE_WORLD.t" "$FE_WORLD"
mv "$E2E_BIN/gh" "$E2E_BIN/gh-stub"
cat > "$E2E_BIN/gh" <<'SH'
#!/bin/bash
# The gh stand-in, except that the second read of issue 7 drops its
# assignees and labels on the world after it answers.
here=$(cd "$(dirname "$0")" && pwd)
if [ "$*" = "api repos/flow-e2e/scratch/issues/7" ]; then
  n=$(( $(cat "$here/nx34-issue-reads" 2>/dev/null || echo 0) + 1 ))
  printf '%s\n' "$n" > "$here/nx34-issue-reads"
  "$here/gh-stub" "$@"
  rc=$?
  if [ "$n" = 2 ]; then
    jq '.issues["7"].assignees = [] | .issues["7"].labels = []' "$FE_WORLD" > "$FE_WORLD.t" && mv "$FE_WORLD.t" "$FE_WORLD"
  fi
  exit "$rc"
fi
exec "$here/gh-stub" "$@"
SH
chmod +x "$E2E_BIN/gh"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 0 "$(fe_world_posts | grep -c .)" "nothing posted (the write is not run)"
e2e_expect_equal 1 "$(nx_line_count '"EFFECT_FAILED job=issue-7-j1 row=41e effect_not_observed issue-7-j1-40-1"')" "the EFFECT_FAILED line"
e2e_expect_equal "waiting_operator issue-7-j1-40-1" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.pending_intent.id)"')" "still parked on its intent"
e2e_expect_equal recorded "$(nx_jq "$NX_J/outbox/issue-7-j1-40-1.json" .status)" "the item is not sent"
fe_new nx34b-41e-observed
# Source: T:41e (record the observed effect, then replay); plan 2.2 (the item
# becomes sent with a write_recorded line, WRITE_SKIPPED, and the replayed row
# 11 records nothing for the kinds the confirmed item covers).
e2e_describe "control: as nx34, with the assignee and the label left on the world"
nx_base prepare
nx_stage_result prepare
nx_settings '.tiers.issueAssign = "confirm"'
nx_next
jq '.issues["7"].assignees = ["flow-e2e-engine"] | .issues["7"].labels = ["flow:in-progress"]' "$FE_WORLD" > "$FE_WORLD.t" && mv "$FE_WORLD.t" "$FE_WORLD"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal "40 41e 11" "$(nx_rows)" "rows"
e2e_expect_equal 0 "$(fe_world_posts | grep -c .)" "nothing posted"
e2e_expect_equal 1 "$(nx_line_count '"WRITE_SKIPPED job=issue-7-j1 intent=issue-7-j1-40-1 found=flow:in-progress"')" "the WRITE_SKIPPED line"
e2e_expect_equal "spec sent 1" "$(printf '%s %s %s' "$(nx_jq "$NX_J/job.json" .state)" "$(nx_jq "$NX_J/outbox/issue-7-j1-40-1.json" .status)" "$(find "$NX_J/outbox" -name '*.json' | grep -c .)")" "state, the item sent, one item"
fi

# ---------------------------------------------------------------- NX35
if nx_run NX35; then
_flow_test_begin "next: a decision whose later effect fails leaves none of its writes to send (NX35, B14 step 8)"
fe_new nx35-no-orphan-writes
# Source: plan B14 step 8 (on leaving needs_info a label_remove, on entry to
# needs_human the needs-human notice); B14 step 9 (a failed handled effect
# reports EFFECT_FAILED and the job does not move); plan 2.2 "Dropped items"
# (a write of a move that was not made must never be sent).
e2e_describe "a plugin copy without templates/factory/needs-human.comment.md; job 7 in needs_info with labels_set [flow:needs-info] and the label on the issue; an outsider edits the body after the vouch (row 51b to needs_human); one pass"
nx_base needs_info "$NX_NEEDS_INFO1; d['labels_set'] = ['flow:needs-info']"
jq '.issues["7"].labels += ["flow:needs-info"]' "$FE_WORLD" > "$FE_WORLD.t" && mv "$FE_WORLD.t" "$FE_WORLD"
e2e_plugin_copy templates/factory/needs-human.comment.md 'placeholder'
rm -f "$E2E_ACTIVE_PLUGIN/templates/factory/needs-human.comment.md"
fe_world_perm outsider read
fe_world_edit issue:7 outsider 2026-11-16T01:00:00Z
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count '"EFFECT_FAILED job=issue-7-j1 row=51b ')" "the EFFECT_FAILED line"
e2e_expect_equal needs_info "$(nx_jq "$NX_J/job.json" .state)" "the job does not move"
e2e_expect_equal 0 "$(fe_world_posts | grep -c .)" "nothing posted"
e2e_expect_equal '["flow:needs-info"]' "$(nx_world_labels)" "the needs-info label stays"
e2e_expect_equal "" "$(cat "$NX_J/outbox/"*.json 2>/dev/null | jq -r 'select(.status != "dropped") | .id' | tr '\n' ' ' | sed 's/ $//')" "outbox items of the failed decision not dropped"
fe_new nx35b-intent-kept
# Source: T:51bw (drop the pending intent, then needs_human); B14 step 9 (a
# decision that fails does not move the job); plan 2.2 "Dropped items" (a
# dropped intent can never run, so it is dropped only by a move that is made).
e2e_describe "the same plugin copy; job 7 parked by row 40 (tiers.issueAssign confirm); an outsider edits the body (row 51bw); one pass"
nx_base prepare
nx_stage_result prepare
nx_settings '.tiers.issueAssign = "confirm"'
e2e_plugin_copy templates/factory/needs-human.comment.md 'placeholder'
rm -f "$E2E_ACTIVE_PLUGIN/templates/factory/needs-human.comment.md"
nx_next
e2e_expect_equal 40 "$(nx_rows)" "rows after the park"
fe_world_perm outsider read
fe_world_edit issue:7 outsider 2026-11-16T01:00:00Z
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count '"EFFECT_FAILED job=issue-7-j1 row=51bw ')" "the EFFECT_FAILED line"
e2e_expect_equal "waiting_operator issue-7-j1-40-1 recorded 0" "$(printf '%s %s %s' "$(nx_jq "$NX_J/job.json" '"\(.state) \(.pending_intent.id)"')" "$(nx_jq "$NX_J/outbox/issue-7-j1-40-1.json" .status)" "$(nx_ev_count 7 '.type == "intent_dropped" and .id == "issue-7-j1-40-1"')")" "still parked, its intent not dropped"
fe_new nx35c-answer-not-written
# Source: T:9a (needs_info, person_answer, intake_rounds_exhausted -> needs_human;
# record the answer); B14 step 9 (a decision that fails does not apply, so the
# answer is not recorded and the stored event is tried again).
e2e_describe "the same plugin copy; job 7 in needs_info at intake_round 3 asking NI-1; a stored terminal answer NI-1; one pass"
nx_base needs_info "$NX_NEEDS_INFO1; d['intake_round'] = 3"
nx_questions NI-1
e2e_plugin_copy templates/factory/needs-human.comment.md 'placeholder'
rm -f "$E2E_ACTIVE_PLUGIN/templates/factory/needs-human.comment.md"
nx_pend 1 person_answer '{"qid": "NI-1", "text": "use port 8080"}'
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count '"EFFECT_FAILED job=issue-7-j1 row=9a ')" "the EFFECT_FAILED line"
e2e_expect_equal "needs_info absent 1" "$(printf '%s %s %s' "$(nx_jq "$NX_J/job.json" .state)" "$([ -e "$NX_J/answers.json" ] && echo present || echo absent)" "$(find "$NX_J/pending" -name '*.json' | grep -c .)")" "state, no answers file, the answer kept for the next pass"
fi

# ---------------------------------------------------------------- NX35d
if nx_run NX35; then
fe_new nx35d-labels-line-deferred
# Source: plan 2.2 (labels_set is restored by rebuild from the last labels_set
# line, written whenever the list changes); B14 step 9 (a decision that fails
# does not apply), so a failed decision writes no labels_set line.
e2e_describe "job 7 in needs_info at intake_round 3 asking NI-1, with labels_set [flow:needs-info]; no question record for NI-1, so recording the answer fails; a stored terminal answer NI-1 (row 9a); one pass"
nx_base needs_info "$NX_NEEDS_INFO1; d['intake_round'] = 3; d['labels_set'] = ['flow:needs-info']"
nx_pend 1 person_answer '{"qid": "NI-1", "text": "use port 8080"}'
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count '"EFFECT_FAILED job=issue-7-j1 row=9a ')" "the EFFECT_FAILED line"
e2e_expect_equal "needs_info 0" "$(nx_jq "$NX_J/job.json" .state) $(nx_ev_count 7 '.type == "labels_set"')" "state, and no labels_set line"
fi

# ---------------------------------------------------------------- NX60
# nx_link_outbox — move job 7's J/outbox to a folder outside the job, put a
# symbolic link to it in its place, and keep a copy of the item
# issue-7-j1-40-1 as it was, for nx_outside_same.
nx_link_outbox() {
  mv "$NX_J/outbox" "$E2E_DIR/outside-outbox"
  ln -s "$E2E_DIR/outside-outbox" "$NX_J/outbox"
  cp "$E2E_DIR/outside-outbox/issue-7-j1-40-1.json" "$E2E_DIR/outside-item.before"
}
# nx_outside_same — "same" when the outside item is byte-equal to its copy.
nx_outside_same() {
  cmp -s "$E2E_DIR/outside-item.before" "$E2E_DIR/outside-outbox/issue-7-j1-40-1.json" && echo same \
    || echo "changed: $(jq -c '{status, effect}' "$E2E_DIR/outside-outbox/issue-7-j1-40-1.json" 2>/dev/null)"
}
# nx_link_outbox_at_read <k> — replace the gh stand-in so that right after
# its k-th read of issue 7 in the next run it does what nx_link_outbox does.
# A read of issue 7 comes from the sync (the first in a pass) and from each
# lookup of the pending intent's effect (the intent_effect_observed fact of
# each decision in waiting_operator, and run_literal's look before a run).
nx_link_outbox_at_read() {
  mv "$E2E_BIN/gh" "$E2E_BIN/gh-stub"
  cat > "$E2E_BIN/gh" <<SH
#!/bin/bash
here=\$(cd "\$(dirname "\$0")" && pwd)
if [ "\$*" = "api repos/flow-e2e/scratch/issues/7" ]; then
  n=\$(( \$(cat "\$here/nx60-issue-reads" 2>/dev/null || echo 0) + 1 ))
  printf '%s\n' "\$n" > "\$here/nx60-issue-reads"
  "\$here/gh-stub" "\$@"
  rc=\$?
  if [ "\$n" = $1 ]; then
    mv '$NX_J/outbox' '$E2E_DIR/outside-outbox'
    ln -s '$E2E_DIR/outside-outbox' '$NX_J/outbox'
    cp '$E2E_DIR/outside-outbox/issue-7-j1-40-1.json' '$E2E_DIR/outside-item.before'
  fi
  exit "\$rc"
fi
exec "\$here/gh-stub" "\$@"
SH
  chmod +x "$E2E_BIN/gh"
}
# nx_park — job 7 parked by row 40 (tiers.issueAssign confirm).
nx_park() {
  nx_base prepare
  nx_stage_result prepare
  nx_settings '.tiers.issueAssign = "confirm"'
  nx_next
  e2e_expect_equal 40 "$(nx_rows)" "rows after the park"
}
# nx_park_linked — job 7 parked by row 40 (tiers.issueAssign confirm), then
# its J/outbox replaced by a link (nx_link_outbox).
nx_park_linked() {
  nx_base prepare
  nx_stage_result prepare
  nx_settings '.tiers.issueAssign = "confirm"'
  nx_next
  e2e_expect_equal 40 "$(nx_rows)" "rows after the park"
  nx_link_outbox
}
# nx_replay_linked — job 7 in prepare with held_result stage_succeeded and
# confirmed_intent issue-7-j1-40-1, that assign_label item recorded and sent
# (the assignee and label on the world, as in nx36a), then its J/outbox
# replaced by a link.
nx_replay_linked() {
  nx_base prepare
  fe_py "import os, _flow_factory_jobs as jobs, _flow_factory_github as g
p = jobs.resolve()
with jobs.job_lock(p, 7, timeout=5):
    j = jobs.read_job(p, 7)
    argv = g.literal_assign_label('flow-e2e/scratch', 7, 'flow-e2e-engine', 'flow:in-progress')
    iid = g.record_job_intent(p, j, '40', 'assign_label', argv, None, ['issueAssign', 'issueUpdate'], True,
                              state='waiting_operator', repo='flow-e2e/scratch')
    path = os.path.join(jobs.job_dir(p, 7), 'outbox', iid + '.json')
    g._sent(p, 7, path, g._valid(path, iid, j['key']), {'label': 'flow:in-progress'})
    j['held_result'] = {'event': 'stage_succeeded', 'args': {'directive': 'issue-7-j1-prepare-1'}, 'channel': 'launcher',
                        'caller': {'pid': 4242, 'start': 'Mon Nov 16 00:00:00 2026', 'ancestry': [4242, 1]}, 'facts': {}}
    j['confirmed_intent'] = iid
    jobs.write_job(p, j)"
  jq '.issues["7"].assignees = ["flow-e2e-engine"] | .issues["7"].labels = ["flow:in-progress"]' "$FE_WORLD" > "$FE_WORLD.t" && mv "$FE_WORLD.t" "$FE_WORLD"
  nx_link_outbox
}
if nx_run NX60; then
_flow_test_begin "next: a linked J/outbox is treated as not found by the row paths, never read or written through (NX60)"
fe_new nx60a-41e-linked
# Source: journal wave 4 "Linked folders" (a symbolic link for J/outbox is
# treated as not found, INTENT_UNKNOWN, as plan 2.2's lookup rule says);
# T:41e (intent_effect_observed: the pending intent's effect is on GitHub):
# an item that is not found has no effect to observe, so the fact is false
# without reading the item through the link, row 41e does not apply and no
# handler runs; the park names the missing item in its status line in
# every pass (plan 5.2; Inferred line form, plan 2.3's INTENT_UNKNOWN=<id>
# with the job= field the other next lines carry).
e2e_describe "job 7 parked by row 40; J/outbox replaced by a link to a folder outside the job; the assignee and label added on GitHub; one pass"
nx_park_linked
jq '.issues["7"].assignees = ["flow-e2e-engine"] | .issues["7"].labels = ["flow:in-progress"]' "$FE_WORLD" > "$FE_WORLD.t" && mv "$FE_WORLD.t" "$FE_WORLD"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 0 "$(nx_line_count 'EFFECT_FAILED')" "no row chosen (row 41e does not apply)"
e2e_expect_equal 1 "$(nx_line_count '"INTENT_UNKNOWN=issue-7-j1-40-1 job=issue-7-j1"')" "the park's status line"
e2e_expect_equal same "$(nx_outside_same)" "the item outside the job is not written"
e2e_expect_equal 0 "$(fe_world_posts | grep -c .)" "nothing posted"
e2e_expect_equal "40 waiting_operator issue-7-j1-40-1" "$(nx_rows) $(nx_jq "$NX_J/job.json" '"\(.state) \(.pending_intent.id)"')" "rows, and still parked on its intent"
fe_new nx60b-41k-linked-after-fact
# Source: as nx60a, for the handler of rows 41 and 41k (one branch runs
# run_literal for both): T:41k (intent_key_not_confirm true: the engine runs
# the write); B14 step 9 (a failed handled effect reports EFFECT_FAILED and
# the job does not move); plan 2.3 (intent_unknown, the reason a missing
# item gives). With the link in place from the start the fact fails first
# (nx60a), so the link appears after the fact read the item.
e2e_describe "job 7 parked by row 40; tiers.issueAssign journal; in the next pass J/outbox is replaced by a link right after the third read of issue 7 (the sync's, then the lookups of the github_change and sync_tick decisions)"
nx_park
nx_settings '.tiers.issueAssign = "journal"'
nx_link_outbox_at_read 3
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal yes "$([ -L "$NX_J/outbox" ] && echo yes || echo no)" "the link was put in place during the pass"
e2e_expect_equal 1 "$(nx_line_count '"EFFECT_FAILED job=issue-7-j1 row=41k intent_unknown issue-7-j1-40-1"')" "the EFFECT_FAILED line"
e2e_expect_equal same "$(nx_outside_same)" "the item outside the job is not written"
e2e_expect_equal 0 "$(fe_world_posts | grep -c .)" "nothing posted"
e2e_expect_equal "40 waiting_operator issue-7-j1-40-1" "$(nx_rows) $(nx_jq "$NX_J/job.json" '"\(.state) \(.pending_intent.id)"')" "rows, and still parked on its intent"
fe_new nx60c-41e-linked-after-fact
# Source: as nx60a, for row 41e's handler: the link appears after the fact
# read the item, so only the handler's own check stands between the link and
# the item saved as sent.
e2e_describe "job 7 parked by row 40 with the assignee and label added on GitHub; in the next pass J/outbox is replaced by a link right after the second read of issue 7 (the lookup that computes intent_effect_observed; the sync's is the first)"
nx_park
jq '.issues["7"].assignees = ["flow-e2e-engine"] | .issues["7"].labels = ["flow:in-progress"]' "$FE_WORLD" > "$FE_WORLD.t" && mv "$FE_WORLD.t" "$FE_WORLD"
nx_link_outbox_at_read 2
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal yes "$([ -L "$NX_J/outbox" ] && echo yes || echo no)" "the link was put in place during the pass"
e2e_expect_equal 1 "$(nx_line_count '"EFFECT_FAILED job=issue-7-j1 row=41e intent_unknown issue-7-j1-40-1"')" "the EFFECT_FAILED line"
e2e_expect_equal same "$(nx_outside_same)" "the item outside the job is not written"
e2e_expect_equal "40 waiting_operator" "$(nx_rows) $(nx_jq "$NX_J/job.json" .state)" "rows, and still parked"
fe_new nx60d-replay-linked
# Source: as nx60a; plan 2.2 (row 11 records nothing for the kinds a sent
# confirmed item covers, read through sent_item): a confirmed item behind a
# link is not found, so row 11 records its own write, which the outbox
# writer refuses for a linked J/outbox (outbox_unwritable); B14 step 10 (a
# failed replay keeps held_result and confirmed_intent).
e2e_describe "job 7 in prepare with held_result and confirmed_intent, its sent assign_label item in a J/outbox that is a link to a folder outside the job; tiers.issueAssign journal (the default); one pass"
nx_replay_linked
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count '"EFFECT_FAILED job=issue-7-j1 row=11 outbox_unwritable')" "the EFFECT_FAILED line"
e2e_expect_equal "prepare stage_succeeded issue-7-j1-40-1" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.held_result.event) \(.confirmed_intent)"')" "the job does not move and keeps the held result"
e2e_expect_equal "" "$(nx_rows)" "rows"
e2e_expect_equal same "$(nx_outside_same)" "the item outside the job is not written"
fe_new nx60e-replay-linked-confirm
# Source: as nx60d with tiers.issueAssign confirm: a confirmed item behind a
# link covers no write kind, so BWC reads the assignment's key as confirm and
# row 40 wins (T:40) instead of row 11; its hold_intent record is refused for
# the linked folder.
e2e_describe "as nx60d with tiers.issueAssign confirm; one pass"
nx_replay_linked
nx_settings '.tiers.issueAssign = "confirm"'
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count '"EFFECT_FAILED job=issue-7-j1 row=40 outbox_unwritable')" "the EFFECT_FAILED line (row 40, not row 11)"
e2e_expect_equal "prepare stage_succeeded" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.held_result.event)"')" "the job does not move"
e2e_expect_equal same "$(nx_outside_same)" "the item outside the job is not written"
fe_new nx60f-50-linked-after-fact
# Source: T:50 (waiting_operator, github_change, issue_changed true,
# build_started false -> intake; from waiting_operator drop the pending
# intent); drop_intent's rule (the intent_dropped line is written even when
# the item does not read); journal wave 4 "Linked folders" (the item behind a
# link is not found, so it is never saved as dropped through the link). The
# link appears after the decision's facts were read, as in nx60b.
e2e_describe "job 7 parked by row 40; baseline_digest set to a digest no issue has; a maintainer edits the body; in the next pass J/outbox is replaced by a link right after the second read of issue 7 (the github_change decision's lookup)"
nx_park
fe_py "import _flow_factory_jobs as jobs
p = jobs.resolve()
with jobs.job_lock(p, 7, timeout=5):
    j = jobs.read_job(p, 7)
    j['baseline_digest'] = 'f' * 64
    j['baseline_pending'] = False
    jobs.write_job(p, j)"
fe_world_perm maintainer write
fe_world_edit issue:7 maintainer 2026-11-16T01:00:00Z
nx_link_outbox_at_read 2
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal yes "$([ -L "$NX_J/outbox" ] && echo yes || echo no)" "the link was put in place during the pass"
e2e_expect_equal "40 50 intake null" "$(nx_rows) $(nx_jq "$NX_J/job.json" '"\(.state) \(.pending_intent)"')" "rows, state and pending_intent"
e2e_expect_equal 1 "$(nx_ev_count 7 '.type == "intent_dropped" and .id == "issue-7-j1-40-1"')" "the intent_dropped line"
e2e_expect_equal same "$(nx_outside_same)" "the item outside the job is not written"
fe_new nx60g-confirm-linked
# Source: as nx60a, for a stored confirm: plan 2.3 (an intent that is not
# found refuses with INTENT_UNKNOWN=<id>, exit 3); 1a apply_pending (a
# refused person event is dropped, so it is not tried again every pass);
# T:53b (cancel_signal: a close by a login with write access cancels from
# waiting_operator), which the false fact leaves free to apply.
e2e_describe "job 7 parked by row 40; J/outbox replaced by a link to a folder outside the job; a stored terminal person_confirm naming issue-7-j1-40-1; pass 2; then a maintainer (write) closes issue 7 at 03:00; pass 3"
nx_park_linked
nx_pend 9 person_confirm '{"intent": "issue-7-j1-40-1"}'
nx_next
e2e_expect_equal 3 "$E2E_RC" "pass 2 exit status (a refusal in the pass)"
e2e_expect_err_lacks "Traceback"
e2e_expect_equal 1 "$(nx_line_count '"INTENT_UNKNOWN=issue-7-j1-40-1"')" "pass 2: row 41's refusal line"
e2e_expect_equal 1 "$(nx_line_count '"INTENT_UNKNOWN=issue-7-j1-40-1 job=issue-7-j1"')" "pass 2: the park's status line"
e2e_expect_equal 0 "$(find "$NX_J/pending" -name '*-person_confirm.json' | grep -c .)" "pass 2: the stored confirm dropped"
e2e_expect_equal 0 "$(fe_world_posts | grep -c .)" "pass 2: nothing posted"
e2e_expect_equal "40 waiting_operator issue-7-j1-40-1" "$(nx_rows) $(nx_jq "$NX_J/job.json" '"\(.state) \(.pending_intent.id)"')" "pass 2: rows, and still parked on its intent"
e2e_expect_equal same "$(nx_outside_same)" "pass 2: the item outside the job is not written"
fe_world_close 7 maintainer write 2026-11-16T03:00:00Z
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 3 exit status ($E2E_ERR)"
e2e_expect_equal "40 53b cancelled" "$(nx_rows) $(nx_jq "$NX_J/job.json" .state)" "pass 3: the close cancels the parked job"
e2e_expect_equal same "$(nx_outside_same)" "pass 3: the item outside the job is not written"
fe_new nx60h-confirm-unreadable
# Source: as nx60g, for an item in a real J/outbox that does not read: the
# lookup rule of plan 2.2 finds no item, so it is INTENT_UNKNOWN (2.3).
e2e_describe "job 7 parked by row 40; its outbox item replaced by the text '{'; a stored terminal person_confirm naming issue-7-j1-40-1; one pass"
nx_park
nx_pend 9 person_confirm '{"intent": "issue-7-j1-40-1"}'
printf '{' > "$NX_J/outbox/issue-7-j1-40-1.json"
nx_next
e2e_expect_equal 3 "$E2E_RC" "exit status (a refusal in the pass)"
e2e_expect_err_lacks "Traceback"
e2e_expect_equal 1 "$(nx_line_count '"INTENT_UNKNOWN=issue-7-j1-40-1"')" "row 41's refusal line"
e2e_expect_equal 1 "$(nx_line_count '"INTENT_UNKNOWN=issue-7-j1-40-1 job=issue-7-j1"')" "the park's status line"
e2e_expect_equal 0 "$(find "$NX_J/pending" -name '*-person_confirm.json' | grep -c .)" "the stored confirm dropped"
e2e_expect_equal 0 "$(fe_world_posts | grep -c .)" "nothing posted"
fe_new nx60i-failed-decision-linked
# Source: journal wave 4 "Linked folders" (a linked J/outbox is never listed
# through); plan B14 step 7 (a decision that did not apply drops the outbox
# items it recorded, and only those: the ids found now less the ids found
# when it started). When J/outbox becomes a link during the decision, the
# folder behind the link may hold ids the decision never recorded; listing
# them would drop an intent of the job that this decision did not make.
# T:41k with tiers.issueAssign journal; the shim's post_fails makes the run
# fail (write_failed, EFFECT_FAILED, B14 step 9).
e2e_describe "job 7 parked by row 40; a second intent issue-7-j1-40-2 (label_add) recorded for the job, its item file kept outside the job; tiers.issueAssign journal; every write fails; in the next pass, right after the fourth read of issue 7 (run_literal's look before the run), J/outbox is replaced by a link to a folder that also holds issue-7-j1-40-2"
nx_park
nx_settings '.tiers.issueAssign = "journal"'
fe_py "import os, _flow_factory_jobs as jobs, _flow_factory_github as g
p = jobs.resolve()
with jobs.job_lock(p, 7, timeout=5):
    j = jobs.read_job(p, 7)
    iid = g.record_job_intent(p, j, '40', 'label_add', g.literal_label_add('flow-e2e/scratch', 7, 'flow:x'), None,
                              ['issueUpdate'], False, state='waiting_operator', repo='flow-e2e/scratch')
    jobs.write_job(p, j)
    print(iid)"
e2e_expect_equal issue-7-j1-40-2 "$E2E_OUT" "the second intent's id"
mv "$NX_J/outbox/issue-7-j1-40-2.json" "$E2E_DIR/stash-40-2.json"
fe_world_knob post_fails true
mv "$E2E_BIN/gh" "$E2E_BIN/gh-stub"
cat > "$E2E_BIN/gh" <<SH
#!/bin/bash
here=\$(cd "\$(dirname "\$0")" && pwd)
if [ "\$*" = "api repos/flow-e2e/scratch/issues/7" ]; then
  n=\$(( \$(cat "\$here/nx60-issue-reads" 2>/dev/null || echo 0) + 1 ))
  printf '%s\n' "\$n" > "\$here/nx60-issue-reads"
  "\$here/gh-stub" "\$@"
  rc=\$?
  if [ "\$n" = 4 ]; then
    mv '$NX_J/outbox' '$E2E_DIR/outside-outbox'
    cp '$E2E_DIR/stash-40-2.json' '$E2E_DIR/outside-outbox/issue-7-j1-40-2.json'
    ln -s '$E2E_DIR/outside-outbox' '$NX_J/outbox'
    cp '$E2E_DIR/outside-outbox/issue-7-j1-40-1.json' '$E2E_DIR/outside-item.before'
  fi
  exit "\$rc"
fi
exec "\$here/gh-stub" "\$@"
SH
chmod +x "$E2E_BIN/gh"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal yes "$([ -L "$NX_J/outbox" ] && echo yes || echo no)" "the link was put in place during the pass"
e2e_expect_equal 1 "$(nx_line_count '"EFFECT_FAILED job=issue-7-j1 row=41k write_failed issue-7-j1-40-1')" "the EFFECT_FAILED line"
e2e_expect_equal 0 "$(nx_ev_count 7 '.type == "intent_dropped" and .id == "issue-7-j1-40-2"')" "no intent_dropped line for the intent the decision did not record"
e2e_expect_equal same "$(cmp -s "$E2E_DIR/stash-40-2.json" "$E2E_DIR/outside-outbox/issue-7-j1-40-2.json" && echo same || echo changed)" "the second item behind the link is not written"
e2e_expect_equal same "$(nx_outside_same)" "the pending item behind the link is not written"
e2e_expect_equal "40 waiting_operator issue-7-j1-40-1" "$(nx_rows) $(nx_jq "$NX_J/job.json" '"\(.state) \(.pending_intent.id)"')" "rows, and still parked on its intent"
fi

# ---------------------------------------------------------------- NX61
if nx_run NX61; then
_flow_test_begin "next: a linked J/directives is treated as absent, never read or written through (NX61)"
fe_new nx61-directives-linked
# Source: journal wave 4 and its B12 follow-up "Linked job folders" (a linked
# J/directives is treated as absent at every read; a linked job folder is
# never read through or written through); T11 Liveness (an expired lease is
# revoked by writing it, and its launcher killed): through a link that write
# and that kill would act on files and processes that are not the job's.
e2e_describe "as nx8 (a current directive whose lease names an exited launcher and an old heartbeat; leaseSeconds 3), with a pending-report file for the directive; then J/directives moved outside the job and a link put in its place; one pass"
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
printf '%s\n' '{"directive": "'"$D1"'", "report": {}}' > "$NX_J/directives/$D1.pending-report.jsonl"
mv "$NX_J/directives" "$E2E_DIR/outside-directives"
ln -s "$E2E_DIR/outside-directives" "$NX_J/directives"
cp -R "$E2E_DIR/outside-directives" "$E2E_DIR/directives.before"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_err_lacks "Traceback"
e2e_expect_equal "" "$(diff -r "$E2E_DIR/directives.before" "$E2E_DIR/outside-directives" 2>&1)" "the files outside the job are not written or removed"
e2e_expect_equal 0 "$(nx_ev_count 7 '.type == "report_refused"')" "no report line read through the link"
fi

# ---------------------------------------------------------------- NX62
# nx_intent_hash <item file> — plan 2.2's literal hash, computed here by
# hand: sha256 over the argv elements joined by NUL bytes, then a NUL byte,
# then the body bytes (none for an item whose body_file is null).
nx_intent_hash() {
  python3 -I -c 'import hashlib, json, sys
it = json.load(open(sys.argv[1]))
print(hashlib.sha256(b"\0".join(a.encode("utf-8") for a in it["argv"]) + b"\0").hexdigest())' "$1"
}
if nx_run NX62; then
_flow_test_begin "next: an item edited after the stored confirm is refused with INTENT_CHANGED, the confirm is dropped, the park stays visible and a trusted close still cancels (NX62, R32)"
fe_new nx62-edited-after-confirm
# Source: plan R32 (body edited after the stored confirm -> row 41 does not
# run it; design interactive_executor L8: the hash is checked again when row
# 41 runs the literal); plan 5.2 ("Outbox file edited -> INTENT_CHANGED;
# nothing runs"); plan 2.3 (the line INTENT_CHANGED=<id> recorded=<hex>
# current=<hex>, exit 3); 1a apply_pending (a refused person event is
# dropped, so it is not tried again every pass). intent_effect_observed
# (T:facts: the pending intent's effect is on GitHub) is false for an item
# that is not the recorded one, so the park is not stuck: each pass names
# the changed item in its own status line (Inferred line form: plan 2.3's
# INTENT_CHANGED=<id> with the job= field the other next lines carry), and a
# GitHub exit of waiting_operator still applies (T:53b, cancel_signal: a
# close by a login with write access). assign_label has no body, so the
# item's argv is edited instead.
e2e_describe "job 7 parked by row 40 with intent issue-7-j1-40-1; a stored terminal person_confirm naming it; then the item's argv edited to add flow:other in place of flow:in-progress; pass 2 (the confirm); pass 3 (no stored event); a maintainer (write) closes issue 7 at 03:00; pass 4"
nx_park
nx_pend 9 person_confirm '{"intent": "issue-7-j1-40-1"}'
NX_REC=$(nx_intent_hash "$NX_J/outbox/issue-7-j1-40-1.json")
jq '.argv |= map(if type == "string" then gsub("flow:in-progress"; "flow:other") else . end)' "$NX_J/outbox/issue-7-j1-40-1.json" > "$E2E_DIR/item.t" && mv "$E2E_DIR/item.t" "$NX_J/outbox/issue-7-j1-40-1.json"
e2e_expect_equal 1 "$(grep -c 'flow:other' "$NX_J/outbox/issue-7-j1-40-1.json")" "the item's argv holds the edited label"
NX_CUR=$(nx_intent_hash "$NX_J/outbox/issue-7-j1-40-1.json")
nx_next
e2e_expect_equal 3 "$E2E_RC" "pass 2 exit status (a refusal in the pass)"
e2e_expect_err_lacks "Traceback"
e2e_expect_equal 1 "$(nx_line_count "\"INTENT_CHANGED=issue-7-j1-40-1 recorded=$NX_REC current=$NX_CUR\"")" "pass 2: row 41's refusal line"
e2e_expect_equal 1 "$(nx_line_count "\"INTENT_CHANGED=issue-7-j1-40-1 job=issue-7-j1 recorded=$NX_REC current=$NX_CUR\"")" "pass 2: the park's status line"
e2e_expect_equal 0 "$(nx_line_count 'EFFECT_FAILED')" "pass 2: no EFFECT_FAILED line"
e2e_expect_equal 0 "$(find "$NX_J/pending" -name '*-person_confirm.json' | grep -c .)" "pass 2: the stored confirm dropped"
e2e_expect_equal 0 "$(fe_world_posts | grep -c .)" "pass 2: nothing posted"
e2e_expect_equal "[] []" "$(jq -c '.issues["7"] | .assignees, .labels' "$FE_WORLD" | tr '\n' ' ' | sed 's/ $//')" "pass 2: the issue's assignees and labels"
e2e_expect_equal "40 waiting_operator issue-7-j1-40-1" "$(nx_rows) $(nx_jq "$NX_J/job.json" '"\(.state) \(.pending_intent.id)"')" "pass 2: rows, and still parked on its intent"
e2e_expect_equal 0 "$(nx_ev_count 7 '.type == "write_recorded"')" "pass 2: no write_recorded line"
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 3 exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count "\"INTENT_CHANGED=issue-7-j1-40-1 job=issue-7-j1 recorded=$NX_REC current=$NX_CUR\"")" "pass 3: the park's status line again"
e2e_expect_equal "40 waiting_operator" "$(nx_rows) $(nx_jq "$NX_J/job.json" .state)" "pass 3: rows and state"
fe_world_close 7 maintainer write 2026-11-16T03:00:00Z
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 4 exit status ($E2E_ERR)"
e2e_expect_err_lacks "Traceback"
e2e_expect_equal "40 53b cancelled" "$(nx_rows) $(nx_jq "$NX_J/job.json" .state)" "pass 4: the close cancels the parked job"
e2e_expect_equal "[] []" "$(jq -c '.issues["7"] | .assignees, .labels' "$FE_WORLD" | tr '\n' ' ' | sed 's/ $//')" "pass 4: the edited literal never ran"
fi

# ---------------------------------------------------------------- NX63
if nx_run NX63; then
_flow_test_begin "next: a spec comment added after row 66i does not reach a later launch's in/issue.md (NX63, R9)"
fe_new nx63-issue-md-one-writer
# Source: plan R9 (spec comment added after 66i; a later launch's
# in/issue.md is byte-equal to 66i's); design stages L39 and T:66i (the only
# writer of in/issue.md); B11 rewrite_in (a worker launch copies J/in-copies
# into the io folder's in/). The later launch is spec's worker, the first
# worker after intake (prepare is an engine directive, given a seam body
# here); every pass after the comment has no sync, so the comment does not
# send the job back to intake (T:50).
e2e_describe "job 7 in intake with its clone; pass 1 gives row 66i and the judge (ACCEPT); after its result, a maintainer posts a /flow-factory spec comment; then passes with no sync, under a seam giving prepare's directive a body, until spec's worker is launched (at most six)"
nx_base intake
fe_job_clone 7
nx_plugin 'RUN: true'
e2e_plugin_copy templates/factory/spec.prompt.md 'RUN: true'
fe_judge_says "$NX_ACCEPT"
nx_next
e2e_expect_equal 66i "$(nx_rows)" "rows after pass 1"
cp "$NX_J/in-copies/issue.md" "$E2E_DIR/issue-66i.md"
fe_wait_for 45 "[ -f '$NX_J/results/issue-7-j1-intake-1.json' ]"
fe_world_comment 7 951 maintainer write 2026-11-16T02:00:00Z "/flow-factory spec Use port 9090."
jq '.bodies = {"directive:prepare": "succeeded"}' "$FE_FIXTURES/seam/ordinary.json" > "$E2E_DIR/prepare-body.json"
NX_FIX="$E2E_DIR/prepare-body.json"
for NX_K in 1 2 3 4 5 6; do
  [ "$(nx_jq "$NX_J/job.json" '.directive // ""')" = issue-7-j1-spec-1 ] && break
  nx_nosync
  nx_next
done
e2e_expect_equal "spec issue-7-j1-spec-1" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.directive)"')" "spec's worker launched"
# Source: T:66 (launch prepare's directive), T:11 (prepare -> spec), T:66b
# (launch spec's worker); no T:50.
e2e_expect_equal "66i 6 66 11 66b" "$(nx_rows)" "rows (no row 50)"
# The launcher runs after the pass: wait for the worker's result.
nx_wait_job_result
NX_IO=$(nx_jq "$NX_J/job.json" '.io_dir // empty')
e2e_expect_equal yes "$([ -n "$NX_IO" ] && [ -f "$NX_IO/in/issue.md" ] && echo yes || echo "no ($NX_IO)")" "the spec launch wrote in/issue.md"
e2e_expect_equal same "$(cmp -s "$E2E_DIR/issue-66i.md" "$NX_IO/in/issue.md" && echo same || echo differs)" "in/issue.md is byte-equal to row 66i's"
e2e_expect_equal 0 "$(grep -c 'port 9090' "$NX_IO/in/issue.md" 2>/dev/null)" "the later comment is not in it"
nx_wait_job_result
fe_new nx63b-issue-md-synced
# Source: as nx63, with a sync in every pass after the comment: plan R9
# (a later launch's in/issue.md is byte-equal to 66i's, so a launch that
# rendered it from the sync's newer issue set would differ); plan 2.2
# (J/sync/issue-set.json is rewritten after every completed sync, and only
# row 66i renders issue.md from it); plan 5.3 (issue.md ends with the
# Other comments list of every comment outside the spec-input set). The
# comment is an outsider's plain comment, so it is outside the spec-input
# set: the digest does not change and no sync sends the job back to intake
# (T:50, issue_changed), while the sync's set does list it under Other
# comments.
e2e_describe "job 7 in intake with its clone; pass 1 gives row 66i and the judge (ACCEPT); after its result, an outsider (read) posts a plain comment at 02:00; then passes with a sync, under a seam giving prepare's directive a body, until spec's worker is launched (at most six)"
nx_base intake
fe_job_clone 7
nx_plugin 'RUN: true'
e2e_plugin_copy templates/factory/spec.prompt.md 'RUN: true'
fe_judge_says "$NX_ACCEPT"
nx_next
e2e_expect_equal 66i "$(nx_rows)" "rows after pass 1"
cp "$NX_J/in-copies/issue.md" "$E2E_DIR/issue-66i.md"
fe_wait_for 45 "[ -f '$NX_J/results/issue-7-j1-intake-1.json' ]"
fe_world_comment 7 952 outsider read 2026-11-16T02:00:00Z "I would pick port 9090."
jq '.bodies = {"directive:prepare": "succeeded"}' "$FE_FIXTURES/seam/ordinary.json" > "$E2E_DIR/prepare-body.json"
NX_FIX="$E2E_DIR/prepare-body.json"
for NX_K in 1 2 3 4 5 6; do
  [ "$(nx_jq "$NX_J/job.json" '.directive // ""')" = issue-7-j1-spec-1 ] && break
  nx_next
done
e2e_expect_equal "spec issue-7-j1-spec-1" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.directive)"')" "spec's worker launched"
e2e_expect_equal "66i 6 66 11 66b" "$(nx_rows)" "rows (no row 50)"
e2e_expect_equal 1 "$(jq -r '.others[] | .author' "$NX_J/sync/issue-set.json" 2>/dev/null | grep -c '^outsider$')" "the sync's issue set lists the outsider's comment"
nx_wait_job_result
NX_IO=$(nx_jq "$NX_J/job.json" '.io_dir // empty')
e2e_expect_equal yes "$([ -n "$NX_IO" ] && [ -f "$NX_IO/in/issue.md" ] && echo yes || echo "no ($NX_IO)")" "the spec launch wrote in/issue.md"
e2e_expect_equal same "$(cmp -s "$E2E_DIR/issue-66i.md" "$NX_IO/in/issue.md" && echo same || echo differs)" "in/issue.md is byte-equal to row 66i's"
e2e_expect_equal 0 "$(grep -c '^- outsider ' "$NX_IO/in/issue.md" 2>/dev/null)" "the later comment is not listed in it"
nx_wait_job_result
fi

# ---------------------------------------------------------------- NX64
if nx_run NX64; then
_flow_test_begin "next: row 8u posts its notice once for one untrusted reply, over passes and after a rebuild (NX64, R14)"
fe_new nx64-8u-once
# Source: plan R14 (two passes, one untrusted reply -> one post; a second,
# unrelated comment in pass 2 re-raises github_change, so row 8u applies
# again -> still one post; the same after a rebuild); T:8u (a stay row:
# untrusted_needs_info_answer true, issue_changed false; post a notice that a
# trusted retry is needed); plan 3.1 raise rule; plan 2.2 dedupe on ref.
e2e_describe "job 7 in needs_info asking NI-1 at 00:30 (no baseline_digest, so issue_changed is false); comment 961 by outsider (read) naming NI-1 at 01:00; pass 1; then comment 962 by outsider, unrelated, at 01:10; pass 2; then rebuild 7; pass 3"
nx_base needs_info "$NX_NEEDS_INFO1"
nx_created
fe_world_comment 7 961 outsider read 2026-11-16T01:00:00Z "NI-1: use port 8080"
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 1 exit status ($E2E_ERR)"
e2e_expect_equal 8u "$(nx_rows)" "rows after pass 1"
e2e_expect_equal 1 "$(nx_posts_to /issues/7/comments)" "one notice after pass 1"
fe_world_comment 7 962 outsider read 2026-11-16T01:10:00Z "Looks fine to me."
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 2 exit status ($E2E_ERR)"
e2e_expect_equal "8u 8u" "$(nx_rows)" "rows after pass 2 (row 8u applied again)"
e2e_expect_equal 1 "$(nx_posts_to /issues/7/comments)" "still one notice after pass 2"
printf '{' > "$NX_J/job.json"
fe_person_terminal issue-7-j1 "$E2E_ACTIVE_PLUGIN/bin/flow-factory.sh" rebuild 7
e2e_expect_equal 0 "$E2E_RC" "rebuild exit status"
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 3 exit status ($E2E_ERR)"
e2e_expect_equal needs_info "$(nx_jq "$NX_J/job.json" .state)" "state after pass 3"
e2e_expect_equal 1 "$(nx_posts_to /issues/7/comments)" "still one notice after the rebuild and pass 3"
fi

# ---------------------------------------------------------------- NX65
if nx_run NX65; then
_flow_test_begin "next: a changed issue sent back to intake waits for the slot with baseline_pending, and the next sync raises no row 50 (NX65, R91)"
fe_new nx65-baseline-pending-waits
# Source: plan R91's E half (a needs_human job with a trusted body edit, a
# terminal retry -> row 44c to intake, baseline_pending true; concurrency 1
# with a second job holding the slot, so row 66w waits; the next pass, with a
# sync, raises github_change in the new state -> no row 50 line, the job
# stays in intake with baseline_pending true); T:44c; T:66w; T:50 (guard
# issue_changed true); 5.3 issue_changed (false while baseline_pending).
e2e_describe "job 7 in needs_human (reason untrusted_edit, so row 47 does not apply) with baseline_digest the digest of the old body and baseline_pending false; a maintainer edits the body; a stored terminal person_retry; job 8 in needs_human holding the one slot (concurrency 1); pass 1; pass 2 with a sync"
nx_base needs_human "d['reason'] = 'untrusted_edit'; d['blocked_stage'] = 'intake'; d['baseline_pending'] = False; d['baseline_digest'] = '$(nx_digest '[["title","Add a port setting"],["body","The service needs a port setting."]]')'"
nx_settings '.flow.factory.concurrency = 1'
fe_job 8 needs_human "d['vouch_at'] = '2026-11-16T00:00:00Z'; d['holds_slot'] = True; d['reason'] = 'needs_info_exhausted'; d['blocked_stage'] = 'intake'"
fe_world_issue 8 "Another job" "It holds the slot."
fe_world_perm maintainer write
fe_world_issue 7 "Add a port setting" "The service needs a port setting, read from the settings file."
fe_world_edit issue:7 maintainer 2026-11-16T01:00:00Z
nx_pend 1 person_retry '{}'
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 1 exit status ($E2E_ERR)"
e2e_expect_equal 44c "$(nx_rows)" "rows after pass 1 (a job that moved in phase B is not launched in the same pass)"
e2e_expect_equal "intake true" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.baseline_pending)"')" "state and baseline_pending after pass 1"
e2e_expect_equal null "$(nx_jq "$NX_J/job.json" .directive)" "no launch (the slot is taken)"
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 2 exit status ($E2E_ERR)"
e2e_expect_equal "44c 66w" "$(nx_rows)" "rows after pass 2 (row 66w waits for the slot; no row 50)"
e2e_expect_equal "intake true" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.baseline_pending)"')" "state and baseline_pending after pass 2"
fi

# ---------------------------------------------------------------- NX66
if nx_run NX66; then
_flow_test_begin "next: a rename by a trusted login reaches the next issue.md in the title fence (NX66, R99)"
fe_new nx66-trusted-rename
# Source: plan R99's E half (a rename by a trusted login -> untrusted_edit
# false, issue_digest changes, and at the next row 66i in-copies/issue.md
# holds the new title in the <<<UNTRUSTED_ISSUE_TITLE>>> fence); design
# trust_and_untrusted_text L5 (renamed events name the title's editors, so a
# rename by a trusted login is not an untrusted edit; the title text is the
# issue's own title as the sync reads it); plan 5.3 issue_digest (computed
# here by hand over the new title).
e2e_describe "job 7 in intake vouched at 00:00; a maintainer (write) renames issue 7 to 'Add a port option' at 01:00; one pass"
nx_base intake
fe_judge_says "$NX_ACCEPT"
fe_world_rename 7 maintainer write 2026-11-16T01:00:00Z "Add a port option"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal "66i intake" "$(nx_rows) $(nx_jq "$NX_J/job.json" .state)" "rows and state (no row 51b)"
e2e_expect_equal "$(nx_digest '[["title","Add a port option"],["body","The service needs a port setting."]]')" "$(nx_jq "$NX_J/job.json" .issue_digest)" "issue_digest over the new title"
e2e_expect_equal "> Add a port option" "$(awk '$0 == "<<<UNTRUSTED_ISSUE_TITLE>>>" { p = 1; next } $0 == "<<<END_UNTRUSTED_ISSUE_TITLE>>>" { p = 0 } p' "$NX_J/in-copies/issue.md")" "the title fence holds the new title"
nx_wait_job_result
fi

# ---------------------------------------------------------------- NX67
if nx_run NX67; then
_flow_test_begin "next: a replay that is blocked keeps the held result, and the job's other events still run (NX67, B14 step 10)"
# Source: plan B14 step 10 (on failed or blocked the replay keeps
# held_result and confirmed_intent, and the next pass retries it before the
# events of event_order); T:21 (open_pr, stage_succeeded -> gate, writes a
# push) and plan B14 test plan (with no seam, a winning row that writes a
# push is BLOCKED_UNBUILT ... fact=prepush_protected_failed phase=1e);
# T:53 (person_cancel -> cancelled).
NX67_SEED="import os, _flow_factory_jobs as jobs, _flow_factory_github as g
p = jobs.resolve()
with jobs.job_lock(p, 7, timeout=5):
    j = jobs.read_job(p, 7)
    argv = g.literal_assign_label('flow-e2e/scratch', 7, 'flow-e2e-engine', 'flow:in-progress')
    iid = g.record_job_intent(p, j, '40', 'assign_label', argv, None, ['issueAssign', 'issueUpdate'], True,
                              state='waiting_operator', repo='flow-e2e/scratch')
    path = os.path.join(jobs.job_dir(p, 7), 'outbox', iid + '.json')
    g._sent(p, 7, path, g._valid(path, iid, j['key']), {'label': 'flow:in-progress'})
    j['held_result'] = {'event': 'stage_succeeded', 'args': {}, 'channel': 'launcher',
                        'caller': {'pid': 4242, 'start': 'Mon Nov 16 00:00:00 2026', 'ancestry': [4242, 1]}, 'facts': {}}
    j['confirmed_intent'] = iid
    jobs.write_job(p, j)"
fe_new nx67a-replay-blocked
e2e_describe "job 7 in open_pr with held_result stage_succeeded and confirmed_intent issue-7-j1-40-1 (recorded and sent); next through the shipped wrapper (no seam, so the push of row 21 is blocked); a plugin copy whose build template is RUN: true; one pass"
nx_base open_pr
nx_plugin 'RUN: true'
fe_py "$NX67_SEED"
nx_wrapper_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count 'BLOCKED_UNBUILT job=issue-7-j1 state=open_pr event=stage_succeeded fact=prepush_protected_failed phase=1e')" "the BLOCKED_UNBUILT line"
e2e_expect_equal "open_pr stage_succeeded issue-7-j1-40-1" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.held_result.event) \(.confirmed_intent)"')" "the held result and confirmed intent kept"
e2e_expect_equal "0 " "$(nx_ev_count 7 '.type == "replayed"') $(nx_rows)" "no replayed line, no transition"
fe_new nx67b-replay-blocked-then-cancel
e2e_describe "as nx67a, with a stored terminal person_cancel; one pass"
nx_base open_pr
nx_plugin 'RUN: true'
fe_py "$NX67_SEED"
nx_pend 1 person_cancel '{}'
nx_wrapper_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count 'BLOCKED_UNBUILT job=issue-7-j1 state=open_pr event=stage_succeeded')" "the replay was blocked"
e2e_expect_equal "53 cancelled" "$(nx_rows) $(nx_jq "$NX_J/job.json" .state)" "the cancel applied after the blocked replay"
fi

# ---------------------------------------------------------------- NX57
if nx_run NX57; then
_flow_test_begin "next: an effect that fails with an OS error reports EFFECT_FAILED and does not move the job (NX57, carry item 2)"
fe_new nx57-os-error
# Source: plan B14 step 9 (a failure of a handled caller effect after
# kill_current: job.json keeps the kill's fields and the pass reports
# EFFECT_FAILED); T:8r (re-vouch deletes J/sync/issue-set.json, plan 2.2).
e2e_describe "job 7 in needs_info; J/sync holds issue-set.json and cannot be written (mode 555), so the delete fails; a stored terminal retry; one pass"
nx_base needs_info "$NX_NEEDS_INFO1"
mkdir -p "$NX_J/sync"
printf '{"items": [], "others": [], "digest": "x"}\n' > "$NX_J/sync/issue-set.json"
chmod 555 "$NX_J/sync"
nx_pend 1 person_retry '{}'
nx_next
chmod 755 "$NX_J/sync"
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_err_lacks "Traceback"
e2e_expect_equal 1 "$(nx_line_count '"EFFECT_FAILED job=issue-7-j1 row=8r ')" "the EFFECT_FAILED line"
e2e_expect_equal "needs_info 1" "$(nx_jq "$NX_J/job.json" .state) $(find "$NX_J/pending" -name '*.json' | grep -c .)" "state, and the retry kept"
fi

# ---------------------------------------------------------------- NX58
if nx_run NX58; then
_flow_test_begin "next: a comment answer is one answer, and the engine's own notice is never a reply (NX58, R102)"
fe_new nx58a-comment-answer
# Source: plan R102's E half (a needs_info job with NI-1 and a trusted
# /flow-factory answer NI-1 use port 8080 comment -> row 8a and no row 8 line;
# J/answers.json holds the text; at the next row 66i in-copies/issue.md holds
# one ANSWER fence for NI-1 and no COMMENT fence for that comment, and
# baseline_digest equals the hand computation of plan 5.3).
e2e_describe "job 7 in needs_info asking NI-1 at 00:30; comment 901 by maintainer (write) '/flow-factory answer NI-1 use port 8080' at 01:00; the judge answers ACCEPT; two passes"
nx_base needs_info "$NX_NEEDS_INFO1"
nx_questions NI-1
fe_world_comment 7 901 maintainer write 2026-11-16T01:00:00Z "/flow-factory answer NI-1 use port 8080"
fe_judge_says "$NX_ACCEPT"
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 1 exit status ($E2E_ERR)"
e2e_expect_equal 8a "$(nx_rows)" "rows after pass 1 (no row 8)"
e2e_expect_equal '[{"qid":"NI-1","text":"use port 8080"}]' "$(jq -c 'map({qid, text})' "$NX_J/answers.json" 2>/dev/null)" "answers.json"
nx_next
e2e_expect_equal "8a 66i" "$(nx_rows)" "rows after pass 2"
e2e_expect_equal "1 0" "$(grep -c '^<<<UNTRUSTED_ISSUE_ANSWER qid=NI-1>>>$' "$NX_J/in-copies/issue.md") $(grep -c '^<<<UNTRUSTED_ISSUE_COMMENT id=901>>>$' "$NX_J/in-copies/issue.md")" "one ANSWER fence, no COMMENT fence for 901"
e2e_expect_equal "$(nx_digest '[["title","Add a port setting"],["body","The service needs a port setting."],["answer","NI-1","use port 8080"]]')" "$(nx_jq "$NX_J/job.json" .baseline_digest)" "baseline_digest is the hand computation"
nx_wait_job_result
fe_new nx58b-engine-notice
# Source: plan R102's E half (a needs_info job whose world holds only the
# engine's needs-info notice for NI-1 after asked_at, posted by the world's
# engine_login with role write -> no row 8 line, no row 8u notice posted, the
# job stays in needs_info); plan 5.3 Engine marker.
e2e_describe "job 7 in needs_info asking NI-1 at 00:30; comment 902 by flow-e2e-engine (write) whose first line is the engine marker and whose body names NI-1, at 00:31; one pass"
nx_base needs_info "$NX_NEEDS_INFO1"
fe_world_comment 7 902 flow-e2e-engine write 2026-11-16T00:31:00Z "<!-- FLOW_FACTORY job=issue-7-j1 event=issue-7-j1-4-1 -->
The factory needs more information. NI-1: Which port?"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal "" "$(nx_rows)" "rows"
e2e_expect_equal "needs_info 0" "$(nx_jq "$NX_J/job.json" .state) $(fe_world_posts | grep -c .)" "state, and nothing posted"
fi

# ---------------------------------------------------------------- NX59
if nx_run NX59; then
_flow_test_begin "next: at the round limit a trusted reply parks by row 9, and no reply leaves the job (NX59, R98)"
# Source: plan R98 (E: at the round limit, a trusted reply naming a current id
# -> row 9; with no comment after that round's T:4 -> no row 9); T:9; plan
# 5.3 issue_digest (the baseline is the hand computation over the issue with
# no reply, so only a reply changes it).
for NX_CASE in reply none; do
  fe_new "nx59-$NX_CASE"
  e2e_describe "job 7 in needs_info at intake_round 3 asking NI-1 at 00:30; baseline_digest the hand-computed digest of the title and body; $([ "$NX_CASE" = reply ] && echo 'comment 903 by maintainer naming NI-1 at 01:00' || echo 'no comment'); one pass"
  nx_base needs_info "$NX_NEEDS_INFO1; d['intake_round'] = 3; d['baseline_pending'] = False; d['baseline_digest'] = '$(nx_digest '[["title","Add a port setting"],["body","The service needs a port setting."]]')'"
  [ "$NX_CASE" = reply ] && fe_world_comment 7 903 maintainer write 2026-11-16T01:00:00Z "NI-1: use port 8080"
  nx_next
  e2e_expect_equal 0 "$E2E_RC" "$NX_CASE: exit status ($E2E_ERR)"
  e2e_expect_equal "$([ "$NX_CASE" = reply ] && echo '9 needs_human' || echo ' needs_info')" "$(nx_rows) $(nx_jq "$NX_J/job.json" .state)" "$NX_CASE: rows and state"
done
fi

# ---------------------------------------------------------------- NX36
if nx_run NX36; then
_flow_test_begin "next: a replay the process did not finish runs first in the next pass, and one that fails does not hold back the job's events (NX36, B14 step 10)"
fe_new nx36a-replay-crash
# Source: plan B14 test plan "the replay crash case" (job.json written by hand
# in prepare with held_result and confirmed_intent set and a sent item -> the
# next pass replays first: spec, one item, a replayed line); plan 2.2 (the
# confirmed item's kinds leave BWC, and row 11 records nothing for them).
e2e_describe "job 7 in prepare with held_result stage_succeeded, confirmed_intent issue-7-j1-40-1, and that assign_label item recorded and sent (the assignee and label on the world); one pass"
nx_base prepare
fe_py "import os, _flow_factory_jobs as jobs, _flow_factory_github as g
p = jobs.resolve()
with jobs.job_lock(p, 7, timeout=5):
    j = jobs.read_job(p, 7)
    argv = g.literal_assign_label('flow-e2e/scratch', 7, 'flow-e2e-engine', 'flow:in-progress')
    iid = g.record_job_intent(p, j, '40', 'assign_label', argv, None, ['issueAssign', 'issueUpdate'], True,
                              state='waiting_operator', repo='flow-e2e/scratch')
    path = os.path.join(jobs.job_dir(p, 7), 'outbox', iid + '.json')
    g._sent(p, 7, path, g._valid(path, iid, j['key']), {'label': 'flow:in-progress'})
    j['held_result'] = {'event': 'stage_succeeded', 'args': {'directive': 'issue-7-j1-prepare-1'}, 'channel': 'launcher',
                        'caller': {'pid': 4242, 'start': 'Mon Nov 16 00:00:00 2026', 'ancestry': [4242, 1]}, 'facts': {}}
    j['confirmed_intent'] = iid
    jobs.write_job(p, j)"
jq '.issues["7"].assignees = ["flow-e2e-engine"] | .issues["7"].labels = ["flow:in-progress"]' "$FE_WORLD" > "$FE_WORLD.t" && mv "$FE_WORLD.t" "$FE_WORLD"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 11 "$(nx_rows)" "rows (the replay applies row 11)"
e2e_expect_equal "spec null null" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.held_result) \(.confirmed_intent)"')" "state and the cleared fields"
e2e_expect_equal 1 "$(find "$NX_J/outbox" -name '*.json' | grep -c .)" "outbox items (no second intent)"
e2e_expect_equal "issue-7-j1-40-1 applied" "$(jq -r 'select(.type == "replayed") | "\(.intent) \(.outcome)"' "$NX_J/events.jsonl")" "one replayed line"
fe_new nx36b-replay-fails
# Source: plan B14 step 10 (on failed or blocked the replay keeps
# held_result and confirmed_intent, and the next pass retries it before the
# events of event_order: so the events still run); T:53 (person_cancel ->
# cancelled); T:11's write needs the engine login (5.3), which fails here.
e2e_describe "job 7 in prepare with held_result stage_succeeded and confirmed_intent naming an intent that was never sent; gh api user fails, so row 11's write cannot be recorded; a stored terminal person_cancel; one pass"
nx_base prepare "d['held_result'] = {'event': 'stage_succeeded', 'args': {}, 'channel': 'launcher', 'caller': {'pid': 4242, 'start': 'Mon Nov 16 00:00:00 2026', 'ancestry': [4242, 1]}, 'facts': {}}; d['confirmed_intent'] = 'issue-7-j1-40-1'"
fe_world_knob list_fails '["user"]'
nx_pend 1 person_cancel '{}'
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count '"EFFECT_FAILED job=issue-7-j1 row=11 engine_login_unknown"')" "the replay failed"
e2e_expect_equal 53 "$(nx_rows)" "rows (the cancel applied after the failed replay)"
e2e_expect_equal cancelled "$(nx_jq "$NX_J/job.json" .state)" "state"
fe_new nx36c-replay-fails-no-launch
# Source: plan B14 step 10 (a failed replay keeps held_result and
# confirmed_intent and is retried by the next pass): the stage whose result is
# held is not launched again meanwhile (Inferred: the held result is applied
# before any launch).
e2e_describe "as nx36b with no stored event, under a seam giving prepare's directive a body (a launch would make a directive at once); one pass"
nx_base prepare "d['held_result'] = {'event': 'stage_succeeded', 'args': {}, 'channel': 'launcher', 'caller': {'pid': 4242, 'start': 'Mon Nov 16 00:00:00 2026', 'ancestry': [4242, 1]}, 'facts': {}}; d['confirmed_intent'] = 'issue-7-j1-40-1'"
jq '.bodies = {"directive:prepare": "succeeded"}' "$FE_FIXTURES/seam/ordinary.json" > "$E2E_DIR/prepare-body.json"
NX_FIX="$E2E_DIR/prepare-body.json"
fe_world_knob list_fails '["user"]'
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count '"EFFECT_FAILED job=issue-7-j1 row=11 engine_login_unknown"')" "the replay failed"
e2e_expect_equal "prepare null stage_succeeded" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.directive) \(.held_result.event)"')" "no launch, the held result kept"
e2e_expect_equal "" "$(nx_rows)" "rows"
fi

# ---------------------------------------------------------------- NX37
if nx_run NX37; then
_flow_test_begin "next: the engine login is read in a pass with no sync, and a pass that cannot read it says so and records nothing (NX37, R95)"
fe_new nx37a-login-no-sync
# Source: plan R95 (a pass with no sync: row 11, the world issue's assignee is
# the world's engine_login and labels.inProgress is on it, the assign_label
# item is sent, and a second drain posts nothing); plan 3.2 item 1. Inferred:
# the pass with no sync comes from state.json last_sync_at, as NX24's, in
# place of a first pass that syncs.
e2e_describe "job 7 in prepare with a completed stage result; the engine login flow-e2e-robot; a pass with no sync; then a second pass"
nx_base prepare
nx_world flow-e2e-robot
fe_world_issue 7 "Add a port setting" "The service needs a port setting."
nx_stage_result prepare
nx_nosync
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 1 exit status ($E2E_ERR)"
e2e_expect_equal 11 "$(nx_rows)" "rows"
e2e_expect_equal '["flow-e2e-robot"] ["flow:in-progress"]' "$(jq -c '.issues["7"] | .assignees, .labels' "$FE_WORLD" | tr '\n' ' ' | sed 's/ $//')" "the assignee is the world's engine login, and the label is on"
e2e_expect_equal sent "$(cat "$NX_J/outbox/"*-11-*.json | jq -r .status)" "the item is sent"
NX_P=$(fe_world_posts | grep -c .)
nx_next
e2e_expect_equal "$NX_P" "$(fe_world_posts | grep -c .)" "a second drain posts nothing"
fe_new nx37b-login-fails
# Source: plan R95 (with gh api user failing: ENGINE_LOGIN_UNKNOWN, EFFECT_FAILED
# with engine_login_unknown, no outbox item, the job still in prepare; with
# the read restored the next pass applies row 11).
e2e_describe "as nx37a, with gh api user failing (list_fails user) in the first pass and answering in the second"
nx_base prepare
nx_stage_result prepare
nx_nosync
fe_world_knob list_fails '["user"]'
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 1 exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count '"ENGINE_LOGIN_UNKNOWN next: check gh auth status in ')" "the ENGINE_LOGIN_UNKNOWN line"
e2e_expect_equal 1 "$(nx_line_count '"EFFECT_FAILED job=issue-7-j1 row=11 engine_login_unknown"')" "the EFFECT_FAILED line"
e2e_expect_equal "prepare 0" "$(printf '%s %s' "$(nx_jq "$NX_J/job.json" .state)" "$(find "$NX_J/outbox" -name '*.json' 2>/dev/null | grep -c .)")" "state and outbox items"
fe_world_knob list_fails '[]'
nx_next
e2e_expect_equal 11 "$(nx_rows)" "rows after the read is restored"
fe_new nx37c-no-drain-without-login
# Source: plan B14 step 5 (ENGINE_LOGIN_UNKNOWN and no drain when the login
# cannot be read; 5.2).
e2e_describe "job 7 in needs_human with one recorded notice in its outbox; gh api user fails; one pass"
nx_base needs_human "d['reason'] = 'attempts_exhausted'"
fe_py "import _flow_factory_jobs as jobs, _flow_factory_github as g
p = jobs.resolve()
with jobs.job_lock(p, 7, timeout=5):
    j = jobs.read_job(p, 7)
    g.record_job_intent(p, j, 'note', 'comment', g.literal_comment('flow-e2e/scratch', 7), 'a note', ['issueUpdate'],
                        False, repo='flow-e2e/scratch')
    jobs.write_job(p, j)"
fe_world_knob list_fails '["user"]'
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count '"ENGINE_LOGIN_UNKNOWN next: check gh auth status in ')" "the ENGINE_LOGIN_UNKNOWN line"
e2e_expect_equal 0 "$(nx_line_count 'WRITE_FAILED')" "no drain ran (no WRITE_FAILED line)"
e2e_expect_equal 0 "$(nx_line_count 'ENGINE_LOGIN_UNKNOWN job=')" "no drain ran (B6's drain, called with no login, would print ENGINE_LOGIN_UNKNOWN job=<key>)"
e2e_expect_equal recorded "$(cat "$NX_J/outbox/"*.json | jq -r .status)" "the item is still recorded"
fi

# ---------------------------------------------------------------- NX38
if nx_run NX38; then
_flow_test_begin "next: a job with labels.priorityHigh launches before a lower-numbered one (NX38, design stages L35)"
fe_new nx38-priority
# Source: design stages L35 and plan 3.2 (scanned is sorted labels.priorityHigh
# first, then issue number, for phase B and phase C); T:66i, T:66w (no slot:
# no launch); conventions.slots (a launch takes the one slot of concurrency 1).
e2e_describe "jobs 7 and 9 in intake; issue 9 carries flow:priority-high; concurrency 1; one pass"
nx_base intake
fe_world_issue 9 "Another setting" "The service needs a host setting."
jq '.issues["9"].labels = ["flow:priority-high"]' "$FE_WORLD" > "$FE_WORLD.t" && mv "$FE_WORLD.t" "$FE_WORLD"
fe_job 9 intake "d['vouch_at'] = '2026-11-16T00:00:00Z'"
fe_judge_says "$NX_ACCEPT"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal "issue-9-j1-intake-1 null" "$(printf '%s %s' "$(jq -r .directive "$NX_F/jobs/issue-9/job.json")" "$(nx_jq "$NX_J/job.json" .directive)")" "the directives of jobs 9 and 7"
fe_wait_for 45 "[ -f '$NX_F/jobs/issue-9/results/issue-9-j1-intake-1.json' ]"
fi

# ---------------------------------------------------------------- NX39
if nx_run NX39; then
_flow_test_begin "next: needs-info rounds post one notice each, keep every counted reply in the spec-input set, and survive a rebuild (NX39, R25, R98)"
fe_new nx39-rounds
# Source: plan R25 (needs_info -> intake -> needs_info gives two notices; two
# drains in one round give one; round 1's notice sent, then rebuild, then
# round 2 -> a second notice with a larger k, posted, not WRITE_SKIPPED);
# plan R98's E half (round 1 asks NI-1 and NI-2; R1 naming NI-1 -> row 8;
# R2 naming NI-2 added while the job waits in intake -> no row 50, row 66i
# takes the baseline over a set holding R1 and R2; round 2 asks NI-3; a pass
# with no new comment -> no row 8e or 9 line, issue_digest equals
# baseline_digest; a reply naming NI-3 -> row 8, and the next issue.md fences
# R1, R2 and that reply); T:4, T:8, T:66i.
e2e_describe "job 7 in intake; the judge answers NEEDS_INFO (two questions), NEEDS_INFO (one), ACCEPT; replies 301 (NI-1), 302 (NI-2) and 303 (NI-3) by maintainer (write), each after the round's asked_at; rebuild between rounds"
nx_base intake
nx_created
fe_judge_says '{"decision":"NEEDS_INFO","risk":"low","surfaces":[],"scope":"s","proposed_criteria":[],"questions":["Which port?","Which host?"],"reason":"r"}' \
  '{"decision":"NEEDS_INFO","risk":"low","surfaces":[],"scope":"s","proposed_criteria":[],"questions":["Which user?"],"reason":"r"}' \
  "$NX_ACCEPT"
nx_next
nx_wait_job_result
nx_next
e2e_expect_equal "needs_info [\"NI-1\",\"NI-2\"]" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.needs_info.questions | tojson)"')" "round 1"
e2e_expect_equal 1 "$(nx_comments_with 'needs more information')" "round 1's notice posted"
nx_next
e2e_expect_equal 1 "$(nx_comments_with 'needs more information')" "a second drain in round 1 posts no second notice"
fe_world_comment 7 301 maintainer write "$(nx_later 3600)" "NI-1: use port 8080"
nx_next
e2e_expect_equal intake "$(nx_jq "$NX_J/job.json" .state)" "row 8 to intake"
fe_world_comment 7 302 maintainer write "$(nx_later 3600)" "NI-2: host example.org"
nx_rebuild_compare "after rows 4 and 8"
nx_next
nx_wait_job_result
e2e_expect_equal 2 "$(grep -cE '^<<<UNTRUSTED_ISSUE_COMMENT id=(301|302)>>>$' "$NX_J/in-copies/issue.md")" "issue.md fences R1 and R2"
nx_next
e2e_expect_equal "66i 4 8 66i 4" "$(nx_rows)" "rows (no row 50)"
e2e_expect_equal "needs_info [\"NI-3\"]" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.needs_info.questions | tojson)"')" "round 2"
e2e_expect_equal 2 "$(nx_comments_with 'needs more information')" "round 2's notice posted"
NX_K=$(cat "$NX_J/outbox/"*.json | jq -r 'select(.row == "4" and .kind == "comment") | .id' | sed 's/.*-4-//' | sort -n | tr '\n' ' ' | sed 's/ $//')
e2e_expect_equal yes "$(set -- $NX_K; [ "$#" = 2 ] && [ "$2" -gt "$1" ] && echo yes || echo "no ($NX_K)")" "the round 2 notice has a larger k"
e2e_expect_equal 0 "$(nx_line_count 'WRITE_SKIPPED')" "round 2's notice is posted, not skipped"
nx_next
e2e_expect_equal "66i 4 8 66i 4" "$(nx_rows)" "a pass with no new comment: no row 8e or 9"
e2e_expect_equal "$(nx_jq "$NX_J/job.json" .issue_digest)" "$(nx_jq "$NX_J/job.json" .baseline_digest)" "issue_digest equals baseline_digest"
fe_world_comment 7 303 maintainer write "$(nx_later 3600)" "NI-3: user bob"
nx_next
nx_next
nx_wait_job_result
e2e_expect_equal "66i 4 8 66i 4 8 66i" "$(nx_rows)" "rows"
e2e_expect_equal 3 "$(grep -cE '^<<<UNTRUSTED_ISSUE_COMMENT id=(301|302|303)>>>$' "$NX_J/in-copies/issue.md")" "issue.md fences R1, R2 and R3"
fi

# ---------------------------------------------------------------- NX40
if nx_run NX40; then
_flow_test_begin "next: three malformed judge replies end in row 43a with intake_round unchanged, and one needs-human comment (NX40, R21, AC4)"
fe_new nx40-malformed-judge
# Source: plan R21 (three malformed results -> three judge launches, then row
# 43a, intake_round unchanged; T:39's effect is attempt += 1 only); plan 5.3
# Judge reply (a stdout that is not one JSON value maps to stage_failed); B14
# step 8 (on entry to needs_human, the needs-human notice and a label_add of
# labels.needsHuman, posted by the drain of the same pass).
e2e_describe "job 7 in intake; the judge stand-in prints 'not json' three times; passes until the job leaves intake"
nx_base intake
fe_judge_raw 'not json' 'not json' 'not json'
for NX_I in 1 2 3 4 5 6 7 8; do
  nx_next
  [ "$(nx_jq "$NX_J/job.json" .state)" = intake ] || break
  nx_wait_job_result
done
e2e_expect_equal 3 "$(nx_launches)" "judge launches"
e2e_expect_equal "43a needs_human attempts_exhausted" "$(printf '%s %s' "$(nx_rows | tr ' ' '\n' | tail -n 1)" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.reason)"')")" "the last row, state and reason"
e2e_expect_equal 0 "$(nx_jq "$NX_J/job.json" '.intake_round // 0')" "intake_round"
e2e_expect_equal 1 "$(nx_comments_with "$NX_HUMAN")" "one needs-human comment"
e2e_expect_equal '["flow:needs-human"]' "$(nx_world_labels)" "the needs-human label"
fi

# ---------------------------------------------------------------- NX41
if nx_run NX41; then
_flow_test_begin "next: an issue change at round 3 parks by row 9 with one needs-human comment; at round 2 it is row 8e (NX41, T:9, T:8e)"
fe_new nx41a-exhausted
# Source: T:9 (needs_info, github_change, issue_changed and
# intake_rounds_exhausted -> needs_human, reason needs_info_exhausted);
# T:facts.intake_rounds_exhausted (intake_round has reached
# flow.factory.intake.maxRounds, default 3); plan B13 (issue_changed: the
# issue_digest differs from baseline_digest, baseline_pending false); B14
# step 8 (one needs-human comment and the label).
e2e_describe "job 7 in needs_info with intake_round 3 and a baseline_digest the issue no longer has; one pass"
nx_base needs_info "$NX_NEEDS_INFO1; d['intake_round'] = 3; d['baseline_digest'] = 'a' * 64; d['baseline_pending'] = False"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 9 "$(nx_rows)" "rows"
e2e_expect_equal "needs_human needs_info_exhausted" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.reason)"')" "state and reason"
e2e_expect_equal 1 "$(nx_comments_with "$NX_HUMAN")" "one needs-human comment"
e2e_expect_equal '["flow:needs-human"]' "$(nx_world_labels)" "the needs-human label"
fe_new nx41b-not-exhausted
e2e_describe "control: the same at intake_round 2"
nx_base needs_info "$NX_NEEDS_INFO1; d['intake_round'] = 2; d['baseline_digest'] = 'a' * 64; d['baseline_pending'] = False"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 8e "$(nx_rows)" "rows"
e2e_expect_equal "intake 3" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.intake_round)"')" "state and intake_round (T:8e intake_round += 1)"
fi

# ---------------------------------------------------------------- NX42
if nx_run NX42; then
_flow_test_begin "next: a comment answer and an outsider edit in one pass: row 8a first, then row 51b (NX42, R59)"
fe_new nx42-answer-then-edit
# Source: plan R59 (a trusted /flow-factory answer NI-1 comment and an outsider
# body edit in one pass: row 8a moves the job to intake, person_answer before
# github_change; the next pass raises github_change and row 51b parks it);
# T:event_order.
e2e_describe "job 7 in needs_info asking NI-1; comment 401 by maintainer '/flow-factory answer NI-1 use port 8080' and an outsider body edit, both at 01:00; two passes"
nx_base needs_info "$NX_NEEDS_INFO1"
nx_questions NI-1
fe_world_comment 7 401 maintainer write 2026-11-16T01:00:00Z "/flow-factory answer NI-1 use port 8080"
fe_world_perm outsider read
fe_world_edit issue:7 outsider 2026-11-16T01:00:00Z
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 1 exit status ($E2E_ERR)"
e2e_expect_equal 8a "$(nx_rows)" "rows after pass 1"
e2e_expect_equal '[{"qid":"NI-1","text":"use port 8080"}]' "$(jq -c 'map({qid, text})' "$NX_J/answers.json" 2>/dev/null)" "answers.json"
nx_next
e2e_expect_equal "8a 51b" "$(nx_rows)" "rows after pass 2"
e2e_expect_equal "needs_human untrusted_edit" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.reason)"')" "state and reason"
fi

# ---------------------------------------------------------------- NX43
if nx_run NX43; then
_flow_test_begin "next: a retry after needs-info exhaustion re-vouches and restarts the rounds (NX43, R62, T:47)"
fe_new nx43-row-47
# Source: T:47 (needs_human, person_retry, reason_needs_info_exhausted ->
# intake; re-vouch, intake_round = 0, set baseline_pending); plan R62 (vouch_at
# = now and baseline_pending set by the same handlers as T:9r and T:8; the
# transition line's fields carry vouch_at).
e2e_describe "job 7 in needs_human, reason needs_info_exhausted, intake_round 3; a stored terminal retry; one pass with a sync"
nx_base needs_human "d['reason'] = 'needs_info_exhausted'; d['intake_round'] = 3"
nx_pend 1 person_retry '{}'
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 47 "$(nx_rows)" "rows"
e2e_expect_equal "intake 0 true" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.intake_round) \(.baseline_pending)"')" "state, intake_round, baseline_pending"
e2e_expect_equal moved "$(nx_jq "$NX_J/job.json" 'if .vouch_at == "2026-11-16T00:00:00Z" then "kept" else "moved" end')" "vouch_at moved to now"
e2e_expect_equal "$(nx_jq "$NX_J/job.json" .vouch_at)" "$(jq -r 'select(.type == "transition") | .fields.vouch_at' "$NX_J/events.jsonl")" "the 47 line's fields carry vouch_at"
fi

# ---------------------------------------------------------------- NX44
if nx_run NX44; then
_flow_test_begin "next: a queue label removed by triage and re-added by write access leaves the needs_human job as it was (NX44, R64)"
fe_new nx44-label-readded
# Source: plan R64 (queue label removed by triage: a status note and no
# cancel; re-added by write access: state needs_human, vouch_at unchanged,
# untrusted_edit still true); T:creation (row 1 refuses while a non-terminal
# job exists); T:45v (needs_human, person_feedback, untrusted_edit true:
# refuse, the untrusted edit needs a trusted retry first), which shows
# untrusted_edit is still true.
e2e_describe "job 7 in intake, labelled flow:factory by maintainer; an outsider edits the body (row 51b); then triager removes the label, then maintainer adds it again; then a stored person_feedback"
nx_base intake
fe_world_label 7 flow:factory maintainer write 2026-11-16T00:00:00Z
fe_world_perm outsider read
fe_world_edit issue:7 outsider 2026-11-16T01:00:00Z
nx_next
e2e_expect_equal 51b "$(nx_rows)" "rows after the edit"
fe_world_label 7 flow:factory triager triage 2026-11-16T02:00:00Z unlabeled
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status after the removal ($E2E_ERR)"
e2e_expect_equal "needs_human 51b" "$(printf '%s %s' "$(nx_jq "$NX_J/job.json" .state)" "$(nx_rows)")" "no cancel after the removal"
e2e_expect_equal 1 "$(nx_comments_with 'did not act on the removal of the label `flow:factory` by triager')" "the status note for the removal (R64)"
fe_world_label 7 flow:factory maintainer write 2026-11-16T03:00:00Z
nx_next
e2e_expect_equal "issue-7-j1 needs_human 2026-11-16T00:00:00Z 51b" "$(printf '%s %s' "$(nx_jq "$NX_J/job.json" '"\(.key) \(.state) \(.vouch_at)"')" "$(nx_rows)")" "key, state, vouch_at and rows after the re-add"
nx_pend 1 person_feedback '{"text": "more"}'
nx_next
e2e_expect_equal 1 "$(printf '%s\n' "$E2E_OUT" | grep -c 'the untrusted edit needs a trusted retry first')" "row 45v refuses: untrusted_edit is still true"
e2e_expect_equal needs_human "$(nx_jq "$NX_J/job.json" .state)" "state"
fi

# ---------------------------------------------------------------- NX45
if nx_run NX45; then
_flow_test_begin "next: a retry from triage with no untrusted reply waiting is row 8t, through the shipped wrapper (NX45, R67)"
fe_new nx45-row-8t
# Source: plan R67 (W: a triage /flow-factory retry comment on a needs_info job
# with no untrusted reply waiting -> row 8t, state unchanged; with
# retry_by_triage_only read as false, row 8r would apply); T:8t.
e2e_describe "job 7 in needs_info asking NI-1; comment 501 by triager (triage) '/flow-factory retry' at 01:00; one pass through the shipped wrapper"
nx_base needs_info "$NX_NEEDS_INFO1"
fe_world_comment 7 501 triager triage 2026-11-16T01:00:00Z "/flow-factory retry"
nx_wrapper_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 8t "$(nx_rows)" "rows"
e2e_expect_equal "needs_info 2026-11-16T00:00:00Z" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.vouch_at)"')" "state and vouch_at unchanged"
fi

# ---------------------------------------------------------------- NX46
if nx_run NX46; then
_flow_test_begin "next: a stored comment command whose commands_seen entry was lost runs once (NX46, R78)"
fe_new nx46-store-crash
# Source: plan R78 (W: the crash state written by hand: a pending file with
# channel comment:12 and a job.json whose commands_seen lacks 12; one pass ->
# one transition line for that command, commands_seen holds 12, no second
# pending file); design person_channels L78 (one action per comment).
e2e_describe "job 7 queued with an open blocker; comment 12 by maintainer '/flow-factory cancel'; a pending person_cancel with channel comment:12 already stored; commands_seen empty; one pass through the shipped wrapper"
nx_queued_blocked
fe_world_comment 7 12 maintainer write 2026-11-16T01:00:00Z "/flow-factory cancel"
mkdir -p "$NX_J/pending"
jq -n '{event: "person_cancel", args: {}, channel: "comment:12",
  caller: {pid: 4242, start: "Mon Nov 16 00:00:00 2026", ancestry: [4242, 1]},
  facts: {unvouched_session_action: false, via_comment: true, retry_by_triage_only: false},
  comment: {id: 12, author: "maintainer", permission: "write", created_at: "2026-11-16T01:00:00Z"},
  raised_at: "2026-11-16T01:00:00Z"}' > "$NX_J/pending/00000000000000000001-person_cancel.json"
nx_wrapper_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 53 "$(nx_rows)" "one transition line"
e2e_expect_equal "[12]" "$(jq -c 'select(.type == "commands_seen") | .commands_seen' "$NX_J/events.jsonl" | tail -n 1)" "commands_seen holds 12"
e2e_expect_equal 0 "$(find "$NX_J/pending" -name '*.json' 2>/dev/null | grep -c .)" "no pending file left"
fi

# ---------------------------------------------------------------- NX47
if nx_run NX47; then
_flow_test_begin "next: an untrusted edit of a trusted spec comment parks an intake job by row 51b with one needs-human comment (NX47, R86, B14 step 8)"
fe_new nx47-spec-comment-edit
# Source: plan R86's E half (row 51b from intake after an untrusted edit to a
# trusted /flow-factory spec comment); T:facts.untrusted_edit; B14 step 8.
e2e_describe "job 7 in intake; comment 601 by maintainer '/flow-factory spec use port 8080' at 00:30, edited by outsider (read) at 01:00; one pass"
nx_base intake
fe_world_comment 7 601 maintainer write 2026-11-16T00:30:00Z "/flow-factory spec use port 8080"
fe_world_perm outsider read
fe_world_edit comment:601 outsider 2026-11-16T01:00:00Z
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 51b "$(nx_rows)" "rows"
e2e_expect_equal "needs_human untrusted_edit" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.reason)"')" "state and reason"
e2e_expect_equal 1 "$(nx_comments_with "$NX_HUMAN")" "one needs-human comment"
fi

# ---------------------------------------------------------------- NX48
if nx_run NX48; then
_flow_test_begin "next: an issue fact is never taken in a pass with no sync (NX48, R88)"
fe_new nx48a-blocked-no-sync
# Source: plan R88 (E, default syncIntervalSeconds: a queued job whose body has
# Blocked by #3, #3 open: pass 1 syncs and the job stays queued; pass 2
# within 60 s has no sync and the job is still queued with no row 2 line).
e2e_describe "job 7 queued, Blocked by #3 with #3 open; the default sync interval; two passes"
nx_queued_blocked
nx_settings 'del(.flow.factory.syncIntervalSeconds)'
nx_next
e2e_expect_equal "queued " "$(nx_jq "$NX_J/job.json" .state) $(nx_rows)" "pass 1: queued, no rows"
nx_next
e2e_expect_equal "queued " "$(nx_jq "$NX_J/job.json" .state) $(nx_rows)" "pass 2 (no sync): queued, no rows"
fe_new nx48b-retry-waits-for-sync
# Source: plan R88 (E: a needs_human job parked by row 51b and a terminal
# retry stored in a pass with no sync: the pending file stays, no transition
# line, vouch_at unchanged; then syncIntervalSeconds 0 and one more pass:
# row 44d applies and vouch_at moves); T:44d.
e2e_describe "job 7 in needs_human, reason untrusted_edit, with an outsider body edit on the world; a stored terminal retry; a pass with no sync; then a pass with a sync"
nx_base needs_human "d['reason'] = 'untrusted_edit'"
fe_world_perm outsider read
fe_world_edit issue:7 outsider 2026-11-16T01:00:00Z
nx_pend 1 person_retry '{}'
nx_nosync
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 1 exit status ($E2E_ERR)"
e2e_expect_equal " 1 2026-11-16T00:00:00Z" "$(nx_rows) $(find "$NX_J/pending" -name '*.json' | grep -c .) $(nx_jq "$NX_J/job.json" .vouch_at)" "no rows, the retry kept, vouch_at unchanged"
nx_settings '.flow.factory.syncIntervalSeconds = 0'
nx_next
e2e_expect_equal 44d "$(nx_rows)" "row 44d after a synced pass"
e2e_expect_equal "intake moved" "$(nx_jq "$NX_J/job.json" '"\(.state) \(if .vouch_at == "2026-11-16T00:00:00Z" then "kept" else "moved" end)"')" "state and vouch_at"
fi

# ---------------------------------------------------------------- NX49
if nx_run NX49; then
_flow_test_begin "next: a stored event's arguments reach its handler and its replay (NX49, R89)"
fe_new nx49a-answer-text
# Source: plan R89 (row 8a from a terminal answer NI-1 --text whose text has
# two inner spaces and a $ -> answers.json holds that text byte for byte);
# T:8a.
e2e_describe "job 7 in needs_info asking NI-1; a stored terminal person_answer NI-1 with text 'use  port \$8080'; one pass"
nx_base needs_info "$NX_NEEDS_INFO1"
nx_questions NI-1
nx_pend 1 person_answer '{"qid": "NI-1", "text": "use  port $8080"}'
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 8a "$(nx_rows)" "rows"
e2e_expect_equal 'use  port $8080' "$(jq -r '.[0].text' "$NX_J/answers.json" 2>/dev/null)" "answers.json holds the text byte for byte"
fe_new nx49b-held-args
# Source: plan R89 (row 40 from a pending stage_succeeded whose args are
# {"directive": D} -> the T:40 line's fields.held_result.args is {"directive":
# D}; then a terminal confirm and row 41 -> the replayed line's args is
# {"directive": D}, and row 41 ran the intent the confirm's args.intent names).
e2e_describe "job 7 in prepare with a completed stage result; tiers.issueAssign confirm; pass 1 parks by row 40; a stored terminal person_confirm naming the pending intent; pass 2"
nx_base prepare
nx_stage_result prepare
nx_settings '.tiers.issueAssign = "confirm"'
nx_next
e2e_expect_equal '{"directive":"issue-7-j1-prepare-1"}' "$(jq -c 'select(.type == "transition" and .row == "40") | .fields.held_result.args' "$NX_J/events.jsonl")" "the 40 line's held_result.args"
nx_pend 9 person_confirm '{"intent": "issue-7-j1-40-1"}'
nx_next
e2e_expect_equal 0 "$E2E_RC" "pass 2 exit status ($E2E_ERR)"
e2e_expect_equal "40 41 11" "$(nx_rows)" "rows"
e2e_expect_equal '{"directive":"issue-7-j1-prepare-1"}' "$(jq -c 'select(.type == "replayed") | .args' "$NX_J/events.jsonl")" "the replayed line's args"
e2e_expect_equal "sent issue-7-j1-40-1" "$(jq -r 'select(.type == "write_recorded") | "sent \(.id)"' "$NX_J/events.jsonl")" "row 41 ran the confirmed intent"
e2e_expect_equal '["flow-e2e-engine"]' "$(jq -c '.issues["7"].assignees' "$FE_WORLD")" "the assignment on the world"
fi

# ---------------------------------------------------------------- NX50
if nx_run NX50; then
_flow_test_begin "next: bot actors are untrusted unless listed (NX50, R90)"
fe_new nx50a-bot-cancel-wrapper
# Source: plan R90 (W, B14: ci[bot] with role write, not in trustedBots,
# commenting /flow-factory cancel on a queued job through next -> no pending
# event, job queued, UNTRUSTED_COMMAND).
e2e_describe "job 7 queued with an open blocker; comment 701 by ci[bot] (write) '/flow-factory cancel'; one pass through the shipped wrapper"
nx_queued_blocked
fe_world_comment 7 701 'ci[bot]' write 2026-11-16T01:00:00Z "/flow-factory cancel"
nx_wrapper_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_line_count 'UNTRUSTED_COMMAND job=issue-7-j1 comment=701 author=ci[bot]')" "the UNTRUSTED_COMMAND line"
e2e_expect_equal "queued 0" "$(nx_jq "$NX_J/job.json" .state) $(find "$NX_J/pending" -name '*.json' 2>/dev/null | grep -c .)" "queued, no pending event"
fe_new nx50b-triage-bot-retry
# Source: plan R90 (E, B14: the triage-bot retry in needs_info with an
# untrusted reply waiting -> no pending event, job in needs_info).
e2e_describe "job 7 in needs_info asking NI-1; comment 702 by outsider (read) 'NI-1: port 9090'; comment 703 by helper-app (type Bot, triage) '/flow-factory retry'; one pass"
nx_base needs_info "$NX_NEEDS_INFO1"
fe_world_comment 7 702 outsider read 2026-11-16T01:00:00Z "NI-1: port 9090"
fe_world_comment 7 703 helper-app triage 2026-11-16T01:10:00Z "/flow-factory retry"
fe_world_actor_type helper-app Bot
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal "needs_info 0" "$(nx_jq "$NX_J/job.json" .state) $(find "$NX_J/pending" -name '*.json' 2>/dev/null | grep -c .)" "needs_info, no pending event"
e2e_expect_equal 0 "$(nx_rows | tr ' ' '\n' | grep -c '^8[rt]$')" "no row 8r or 8t"
fe_new nx50c-bot-close
# Source: plan R90 (E, B14: the bot close in intake -> row 53u, not 53b);
# T:53u (untrusted_close -> needs_human, reason issue_closed_untrusted); B14
# step 8 (one needs-human comment).
e2e_describe "job 7 in intake; ci[bot] (write) closes the issue at 01:00; one pass"
nx_base intake
fe_world_close 7 'ci[bot]' write 2026-11-16T01:00:00Z
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 53u "$(nx_rows)" "rows"
e2e_expect_equal "needs_human issue_closed_untrusted" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.reason)"')" "state and reason"
e2e_expect_equal 1 "$(nx_comments_with "$NX_HUMAN")" "one needs-human comment"
fi

# ---------------------------------------------------------------- NX51
if nx_run NX51; then
_flow_test_begin "next: dependency lines through next (NX51, R76)"
# Source: plan R76 (Depends on #3 with #3 closed not_planned -> dependency_open
# false, row 2 applies; See #3 and Depends on o/other#3 only -> ignored, row
# 2; Depends on #3 with the read of #3 failing -> no fact, no row 2); T:2.
for NX_CASE in closed ignored readfails; do
  fe_new "nx51-$NX_CASE"
  e2e_describe "job 7 queued; dependency case $NX_CASE; one pass"
  nx_base queued
  case "$NX_CASE" in
    closed) fe_world_issue 7 "Add a port setting" "Depends on #3"; fe_world_issue 3 "Dropped" "x" closed
            jq '.issues["3"].state_reason = "not_planned"' "$FE_WORLD" > "$FE_WORLD.t" && mv "$FE_WORLD.t" "$FE_WORLD"; NX_EXP=2 ;;
    ignored) fe_world_issue 7 "Add a port setting" "See #3
Depends on o/other#3"; fe_world_issue 3 "Open" "x"; NX_EXP=2 ;;
    readfails) fe_world_issue 7 "Add a port setting" "Depends on #3"; fe_world_issue 3 "Open" "x"
               fe_world_knob list_fails '["repos/flow-e2e/scratch/issues/3"]'; NX_EXP="" ;;
  esac
  nx_next
  e2e_expect_equal 0 "$E2E_RC" "$NX_CASE: exit status ($E2E_ERR)"
  e2e_expect_equal "$NX_EXP" "$(nx_rows)" "$NX_CASE: rows"
done
fi

# ---------------------------------------------------------------- NX52
if nx_run NX52; then
_flow_test_begin "next: a trusted close cancels and an outsider edit parks, from queued and intake, through the shipped wrapper (NX52, T:53b, T:51b)"
# Source: T:53b (github_change, cancel_signal -> cancelled); T:51b
# (untrusted_edit -> needs_human); plan B14 test plan W "53b and 51b from
# queued and intake".
for NX_CASE in queued:53b intake:53b queued:51b intake:51b; do
  NX_S=${NX_CASE%%:*}; NX_R=${NX_CASE#*:}
  fe_new "nx52-$NX_S-$NX_R"
  e2e_describe "job 7 in $NX_S; $([ "$NX_R" = 53b ] && echo 'maintainer (write) closes the issue' || echo 'outsider (read) edits the body') at 01:00; one pass through the shipped wrapper"
  if [ "$NX_S" = queued ]; then nx_queued_blocked; else nx_base intake; fi
  if [ "$NX_R" = 53b ]; then
    fe_world_close 7 maintainer write 2026-11-16T01:00:00Z; NX_TO=cancelled
  else
    fe_world_perm outsider read; fe_world_edit issue:7 outsider 2026-11-16T01:00:00Z; NX_TO=needs_human
  fi
  nx_wrapper_next
  e2e_expect_equal 0 "$E2E_RC" "$NX_CASE: exit status ($E2E_ERR)"
  e2e_expect_equal "$NX_R $NX_TO" "$(nx_rows) $(nx_jq "$NX_J/job.json" .state)" "$NX_CASE: row and state"
done
fi

# ---------------------------------------------------------------- NX53
if nx_run NX53; then
_flow_test_begin "next: /flow-factory reject in needs_human rejects the job, through the shipped wrapper (NX53, T:48)"
fe_new nx53-reject
# Source: T:48 (needs_human, person_reject, unvouched_session_action false ->
# rejected); design person_channels (a trusted command comment raises the
# person event through the comment channel).
e2e_describe "job 7 in needs_human; comment 801 by maintainer (write) '/flow-factory reject' at 01:00; one pass through the shipped wrapper"
nx_base needs_human "d['reason'] = 'attempts_exhausted'"
fe_world_comment 7 801 maintainer write 2026-11-16T01:00:00Z "/flow-factory reject"
nx_wrapper_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal "48 rejected comment:801" "$(nx_rows) $(nx_jq "$NX_J/job.json" .state) $(jq -r 'select(.type == "transition") | .channel' "$NX_J/events.jsonl")" "row, state and channel"
# Source: T:48 and T:42 ("close any PR through the outbox"); plan 2.2 (a
# pr_close item, run by the drain of the same pass: the job ended in that
# state, so the item's state_at_write is it).
for NX_CASE in needs_human:48 waiting_operator:42; do
  fe_new "nx53-pr-${NX_CASE#*:}"
  e2e_describe "job 7 in ${NX_CASE%%:*} with PR 12 open on the world; a stored terminal person_reject; one pass"
  nx_base "${NX_CASE%%:*}" "d['reason'] = 'attempts_exhausted' if d['state'] == 'needs_human' else 'write_confirm'; d['pr'] = 12; d['head_sha'] = 'a' * 40"
  fe_world_pull 12 feature/issue-7-x-2 flow-e2e-engine write "Closes #7"
  nx_pend 1 person_reject '{}'
  nx_next
  e2e_expect_equal 0 "$E2E_RC" "${NX_CASE}: exit status ($E2E_ERR)"
  e2e_expect_equal "${NX_CASE#*:} rejected" "$(nx_rows) $(nx_jq "$NX_J/job.json" .state)" "${NX_CASE}: row and state"
  e2e_expect_equal "1 sent" "$(cat "$NX_J/outbox/"*.json 2>/dev/null | jq -r --arg r "${NX_CASE#*:}" 'select(.row == $r and .kind == "pr_close") | .status' | sort | uniq -c | awk '{print $1, $2}')" "${NX_CASE}: one pr_close item, sent"
  e2e_expect_equal closed "$(jq -r '.pulls[] | select(.number == 12) | .state' "$FE_WORLD")" "${NX_CASE}: the PR closed on the world"
done
fi

# ---------------------------------------------------------------- NX54
if nx_run NX54; then
_flow_test_begin "next: row 66i refuses an issue set whose digest does not match (NX54, R8, B14 step 6)"
# Source: plan B14 step 6 (the set's digest must equal both digest(items) and
# job.json's issue_digest; a mismatch raises issue_set_stale, reported as
# EFFECT_FAILED, and nothing is launched).
NX_ITEMS='[["title","Add a port setting"],["body","The service needs a port setting."]]'
NX_D=$(nx_digest "$NX_ITEMS")
for NX_CASE in job items; do
  fe_new "nx54-$NX_CASE"
  e2e_describe "job 7 in intake; a pass with no sync; J/sync/issue-set.json whose digest $([ "$NX_CASE" = job ] && echo 'equals its items but not job.json issue_digest' || echo 'equals job.json issue_digest but not its items')"
  if [ "$NX_CASE" = job ]; then nx_base intake "d['issue_digest'] = 'b' * 64"; else nx_base intake "d['issue_digest'] = 'c' * 64"; NX_D=$(printf 'c%.0s' $(seq 64)); fi
  fe_judge_says "$NX_ACCEPT"
  nx_nosync
  mkdir -p "$NX_J/sync"
  jq -n --argjson i "$NX_ITEMS" --arg d "$NX_D" '{synced_at: "2026-11-16T00:00:00Z", items: $i, others: [], digest: $d}' > "$NX_J/sync/issue-set.json"
  nx_next
  e2e_expect_equal 0 "$E2E_RC" "$NX_CASE: exit status ($E2E_ERR)"
  e2e_expect_equal 1 "$(nx_line_count '"EFFECT_FAILED job=issue-7-j1 row=66i issue_set_stale"')" "$NX_CASE: the EFFECT_FAILED line"
  e2e_expect_equal 0 "$(nx_launches)" "$NX_CASE: claude launches"
done
fi

# ---------------------------------------------------------------- NX55
if nx_run NX55; then
_flow_test_begin "next: an NI answer given in needs_human by row 44 reaches the answers file (NX55, journal wave 3)"
fe_new nx55-row-44-answer
# Source: journal wave 3 (row 44, needs_human person_answer with no guard,
# records no answer in its effects; an NI answer given there must still reach
# the answers file before the job resumes); T:44 (-> blocked_stage).
e2e_describe "job 7 in needs_human, blocked_stage intake, asking NI-1; a stored terminal person_answer NI-1 'use port 8080'; one pass with a sync"
nx_base needs_human "d['reason'] = 'attempts_exhausted'; d['blocked_stage'] = 'intake'; $NX_NEEDS_INFO1"
nx_questions NI-1
nx_pend 1 person_answer '{"qid": "NI-1", "text": "use port 8080"}'
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal "44 intake" "$(nx_rows) $(nx_jq "$NX_J/job.json" .state)" "row and state"
e2e_expect_equal '[{"qid":"NI-1","text":"use port 8080"}]' "$(jq -c 'map({qid, text})' "$NX_J/answers.json" 2>/dev/null)" "answers.json"
fi

# ---------------------------------------------------------------- NX56
if nx_run NX56; then
_flow_test_begin "next: the rows 4, 6, 8r, 40 and 40b leave job.json equal to its rebuild (NX56, R36)"
fe_new nx56a-rebuild-4-8r-6-40
# Source: plan R36 (rebuild after rows 4, 6, 8r, 40, 40b -> job.json equal to
# the pre-rebuild file, sync fields excluded, which shows the transition
# lines' fields and the LOGGED_LISTS lines carry every 1b field); 1a AC10.
e2e_describe "job 7 in intake with a created line; the judge answers NEEDS_INFO then ACCEPT; a terminal retry; the prepare directive's body under the seam; tiers.issueAssign confirm before prepare's result; passes until row 40; then rebuild"
nx_base intake
nx_created
jq '.bodies = {"directive:prepare": "succeeded"}' "$FE_FIXTURES/seam/ordinary.json" > "$E2E_DIR/prepare-body.json"
NX_FIX="$E2E_DIR/prepare-body.json"
fe_judge_says '{"decision":"NEEDS_INFO","risk":"low","surfaces":[],"scope":"s","proposed_criteria":[],"questions":["Which port?"],"reason":"r"}' "$NX_ACCEPT"
nx_next
nx_wait_job_result
nx_next
e2e_expect_equal needs_info "$(nx_jq "$NX_J/job.json" .state)" "row 4"
nx_pend 1 person_retry '{}'
nx_next
nx_next
nx_wait_job_result
nx_next
e2e_expect_equal prepare "$(nx_jq "$NX_J/job.json" .state)" "row 6"
nx_settings '.tiers.issueAssign = "confirm"'
for NX_I in 1 2 3; do
  nx_next
  [ "$(nx_jq "$NX_J/job.json" .state)" = waiting_operator ] && break
done
e2e_expect_equal 40 "$(nx_rows | tr ' ' '\n' | tail -n 1)" "the last row"
e2e_expect_equal 1 "$(nx_rows | tr ' ' '\n' | grep -c '^8r$')" "row 8r ran"
nx_rebuild_compare "rows 4, 8r, 6 and 40"
fe_new nx56b-rebuild-40b
e2e_describe "job 7 in intake with a created line; tiers.issueAssign confirm and the seam copy with executor_can_confirm false; one pass (row 40b); then rebuild"
nx_base intake
nx_created
nx_settings '.tiers.issueAssign = "confirm"'
nx_no_confirm
nx_next
e2e_expect_equal 40b "$(nx_rows)" "rows"
nx_rebuild_compare "row 40b"
fi

# ---------------------------------------------------------------- NX17
if nx_run NX17; then
_flow_test_begin "next: each change to orphan_groups, snapshots and pending_changes writes its event line (NX17, AC10)"
# nx17_lease <directive> <child pid or null> <child start or null> — a lease
# whose launcher has exited and whose heartbeat is old.
nx17_lease() {
  local dead cs=null
  dead=$(_fe_in_scratch sh -c 'echo $$')
  [ "$3" = null ] || cs="\"$3\""
  cat > "$NX_J/directives/$1.lease.json" <<JSON
{"directive": "$1", "kind": "worker", "host": "h", "launcher_pid": $dead, "launcher_start": "Mon Nov 16 00:00:00 2026",
 "started_at": "2026-11-16T00:00:00Z", "heartbeat_at": "2026-11-16T00:00:00Z", "child_pid": $2, "child_pgid": $2,
 "child_start": $cs, "revoked_at": null}
JSON
}
# nx17_zombie_group — sets NX_Z to the pid of a `sleep 60` in a session of its
# own, whose parent (a background python) never reaps it. Once the engine
# kills it, the group leader is a zombie: killpg(pgid, 0) still finds the
# group and ps still gives the leader's start, so the group is not confirmed
# gone and stays alive by orphan_alive. Both processes are registered for
# cleanup. (Observed on darwin: killpg gives EPERM for the zombie's group.)
nx17_zombie_group() {
  fe_bg zombie fe_py "import subprocess, time
p = subprocess.Popen(['sleep', '60'], start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print(p.pid, flush=True)
time.sleep(60)"
  fe_wait_for 10 "[ -s '$E2E_DIR/bg-zombie.out' ]" || return 1
  NX_Z=$(head -n 1 "$E2E_DIR/bg-zombie.out")
  _fe_register "$NX_Z"
}
# nx17_seed_expired [job edits] — job 7 in build whose current directive D1
# has an expired lease; leaseSeconds 3.
nx17_seed_expired() {
  nx_seed "d['directive'] = '$D1'; d['stage_launches'] = {'build': 1}; d['holds_slot'] = True
${1:-}"
  nx_settings '.flow.factory.leaseSeconds = 3'
  fe_directive "$D1" "d['max_budget_usd'] = 0.5; d['started_at'] = '2026-11-16T00:00:00Z'; d['model'] = 'claude-opus-5-5'"
}
# nx17_entries <event type> <keys> — the entries of that event type's lines,
# reduced to the keys, as one sorted JSON array.
nx17_entries() { jq -cS -s "[.[] | select(.type == \"$1\") | {$2}]" "$NX_J/events.jsonl" 2>/dev/null; }
NX17_B40=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

fe_new nx17a-snapshot-event
# Source: T:39ld (lease_expired, group_gone true, attempts_exhausted false,
# tree_dirty true: snapshot, reset, attempt += 1, relaunch fresh); the
# snapshot line's entry is the one job.json snapshots holds (T12 rebuild
# table: a field the pass writes is restored from the log).
e2e_describe "D1's lease expired with no child; the clone has an untracked file; leaseSeconds 3"
nx17_seed_expired
nx17_lease "$D1" null null
nx_plugin 'RUN: true'
fe_worker_says "worker-result=$NX_SUCCESS"
NX_WT=$(nx_jq "$NX_J/job.json" .worktree)
printf 'dirty\n' > "$NX_WT/dirty.txt"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal "39ld 66b" "$(nx_rows)" "rows"
e2e_expect_equal 1 "$(nx_jq "$NX_J/job.json" '.snapshots | length')" "job.json snapshots entries"
e2e_expect_equal 1 "$(nx_ev_count 7 '.type == "snapshot"')" "snapshot lines"
fe_mask_found "$(jq -cS '.snapshots' "$NX_J/job.json" 2>/dev/null)"
e2e_expect_equal "$(jq -cS '.snapshots' "$NX_J/job.json" 2>/dev/null)" "$(nx17_entries snapshot 'ref, k, reason, at')" \
  "the snapshot line's entry equals job.json snapshots"
nx_finish "$D2"
fe_art_state 7

fe_new nx17b-orphan-group-event
# Source: plan T11 (a group not confirmed gone is added to orphan_groups with
# its start); T:43o (lease_expired, group_gone false: needs_human,
# orphan_worker); the orphan_group line's entry is the one job.json holds.
e2e_describe "D1's lease expired; its child group is a sleep 60 whose parent never reaps it; leaseSeconds 3"
e2e_repo main
nx17_zombie_group
fe_mask_pid "$NX_Z" sleeper
NX_ZS=$(_fe_lstart "$NX_Z")
nx17_seed_expired
nx17_lease "$D1" "$NX_Z" "$NX_ZS"
nx_plugin 'RUN: true'
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 43o "$(nx_rows)" "rows"
e2e_expect_equal "needs_human orphan_worker" "$(nx_jq "$NX_J/job.json" '"\(.state) \(.reason)"')" "state, reason"
e2e_expect_equal "$NX_Z build" "$(nx_jq "$NX_J/job.json" '.orphan_groups[0] | "\(.pgid) \(.stage)"')" "job.json orphan_groups[0] pgid, stage"
e2e_expect_equal 1 "$(nx_ev_count 7 '.type == "orphan_group"')" "orphan_group lines"
fe_mask_found "$(jq -cS '.orphan_groups' "$NX_J/job.json" 2>/dev/null)"
e2e_expect_equal "$(jq -cS '.orphan_groups' "$NX_J/job.json" 2>/dev/null)" "$(nx17_entries orphan_group 'pgid, start, stage, recorded_at')" \
  "the orphan_group line's entry equals job.json orphan_groups"
e2e_expect_equal "$D1" "$(jq -r 'select(.type == "orphan_group") | .directive' "$NX_J/events.jsonl" 2>/dev/null)" "the orphan_group line's directive"

fe_new nx17c-pending-changes-event
# Source: plan T11 Sync (a head the factory did not push adds
# foreign_head_change to job.json pending_changes); the pending_changes line
# holds the facts added and the list job.json was given.
e2e_describe "job 7 in needs_human with PR 12 at head a*40; gh reports head b*40"
nx_seed "d['state'] = 'needs_human'; d['reason'] = 'orphan_worker'; d['blocked_stage'] = 'build'; d['pr'] = 12; d['head_sha'] = 'a' * 40"
nx_plugin 'RUN: true'
fe_gh api_repos_flow-e2e_scratch_pulls_12 "{\"state\":\"open\",\"merged\":false,\"merged_at\":null,\"head\":{\"sha\":\"$NX17_B40\"}}"
nx_next
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal 1 "$(nx_ev_count 7 '.type == "pending_changes"')" "pending_changes lines"
e2e_expect_equal '["foreign_head_change"] ["foreign_head_change"]' \
  "$(jq -c 'select(.type == "pending_changes") | .added, .pending_changes' "$NX_J/events.jsonl" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')" \
  "the pending_changes line's added and pending_changes"
fe_art_state 7
fi

# ---------------------------------------------------------------- NX13
if nx_run NX13; then
_flow_test_begin "next: a probe holding the probe lock delays next by at most 2 s (NX13, R19)"
fe_new nx13-probe-lock
# Source: plan 2.12 environment_recheck (waits min(2, left - 1) s for probes.lock
# only when gh or git moved; on a timeout it writes nothing); plan 2.5; plan
# T11 (before every step, compare the time left with 2 s).
# The plan's row uses nextBudgetSeconds 5 and a 6 s limit. A launch needs 2 s
# left after the lock wait of up to 2 s, so a budget of 5 leaves 1 s for the
# pass's work before the wait; on a loaded machine that work takes about
# 1.7 s, the wait shrinks to left - 1 and the pass ends without launching.
# Budget 10 leaves 6 s. It stays small enough that a wait without the 2 s cap
# (left - 1, or the 10 s lock timeout) leaves under 2 s and launches nothing,
# so the rows check fails it. The probe still holding the lock when next
# returns, and the 15 s limit, fail the plan's wrong version, an unbounded
# wait that returns after the probe releases the lock at about 30 s.
e2e_describe "gh reports a new version, so the re-run must record it under probes.lock, which a probe holds for 30 s; syncIntervalSeconds 0; nextBudgetSeconds 10"
nx_seed
nx_plugin 'RUN: true'
nx_settings '.flow.factory.syncIntervalSeconds = 0 | .flow.factory.nextBudgetSeconds = 10'
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
NX_HELD=$([ -f "$E2E_DIR/bg-probe.rc" ] && echo "no, the probe had ended" || echo yes)
printf 'NX13 elapsed: %s s\n' "$NX_ELAPSED"
e2e_expect_equal 0 "$E2E_RC" "exit status ($E2E_ERR)"
e2e_expect_equal yes "$NX_HELD" "the probe still held probes.lock when next returned"
e2e_expect_equal yes "$(nx_le "$NX_ELAPSED" 15)" "next returned within 15 s"
e2e_expect_equal 66b "$(nx_rows)" "rows (job 7 launched)"
e2e_expect_equal null "$(nx_jq "$NX_F/state.json" .env_recheck_at)" "env_recheck_at unchanged"
e2e_expect_equal "$NX_REC0" "$(jq -c .groups.environment "$NX_F/probes.json")" "the record's environment group"
# The 2 s cap itself, measured inside one process so load does not move it:
# the recheck's record step, given 100 s, must give up on the held lock after
# about 2 s ("locked"). A cap of 3 s or more, or none (left - 1, 99 s), fails
# the upper bound; a wait that does not try the lock at all fails the lower.
fe_py "import time, _flow_factory_jobs as j, _flow_factory_staleness as s
p = j.resolve(create=False)
t = time.monotonic()
r = s._record_versions(p.fdir, {'gh': 'gh version 2.102.0'}, time.time() + 100)
w = time.monotonic() - t
print('yes' if r == 'locked' and 1.9 <= w < 2.9 else 'no (%s %.2f s)' % (r, w))"
NX_WAIT=$E2E_OUT
e2e_expect_equal yes "$([ -f "$E2E_DIR/bg-probe.rc" ] && echo "no, the probe had ended" || echo yes)" "the probe still held probes.lock after the record step"
e2e_expect_equal yes "$NX_WAIT" "the record step gave up on the held lock after 2 s (locked, 1.9-2.9 s)"
e2e_expect_equal "$NX_REC0" "$(jq -c .groups.environment "$NX_F/probes.json")" "the record's environment group after the record step"
nx_finish "$D1"
fi
