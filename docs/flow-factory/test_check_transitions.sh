#!/bin/bash
# Mutation test for check_transitions.py.
#
# Copies transitions.json to a temporary directory, checks that the original
# passes, then applies one mutation at a time and checks that the checker
# fails with the expected message. It also checks that transitions.md equals
# the checker's --markdown output, and that every row id design.json and
# transitions.json cite exists. Bash 3.2 compatible; mutations use Python
# (standard library only).
#
# PYTHONS lists the interpreters to test, oldest first (default:
# "python3.14"; PYTHON=<one interpreter> still works). Flow supports Python
# 3.14 or later; an older interpreter is skipped. The original table, the
# markdown check and the citation check run under every listed interpreter
# that exists; the mutations run under the first one.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECKER="$HERE/check_transitions.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-transitions.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cp "$HERE/transitions.json" "$WORK/original.json"
JOBS="${JOBS:-6}"

pass=0
fail=0

PYS=""
seen=""
for p in ${PYTHONS:-${PYTHON:-python3.14}}; do
  command -v "$p" > /dev/null 2>&1 || { echo "skip interpreter $p: not found"; continue; }
  "$p" -c 'import sys; sys.exit(sys.version_info < (3, 14))' 2>/dev/null || { echo "skip interpreter $p: older than Python 3.14"; continue; }
  exe="$("$p" -c 'import os, sys; print(os.path.realpath(sys.executable))' 2>/dev/null)" || continue
  case " $seen " in *" $exe "*) continue ;; esac
  seen="$seen $exe"
  PYS="$PYS $p"
done
set -- $PYS
if [ "$#" -eq 0 ]; then
  echo "FAIL no Python interpreter found"
  exit 1
fi
PY="$1"

for p in $PYS; do
  echo "Interpreter: $("$p" -c 'import sys; print(sys.executable, sys.version.split()[0])')"
done

# Original must pass under every interpreter.
for p in $PYS; do
  if "$p" "$CHECKER" "$WORK/original.json" > "$WORK/original.out" 2>&1; then
    echo "ok   original table passes ($p)"
    pass=$((pass + 1))
  else
    echo "FAIL original table does not pass ($p):"
    grep -E '^(ERROR|FAIL)' "$WORK/original.out" | head -20 | sed 's/^/     /'
    fail=$((fail + 1))
  fi
done

# mutate NAME EXPECTED_REGEX PYTHON_SNIPPET
# The snippet edits the dict `d`; `row(id)` returns a row by id, and
# `nmo(event, state)` returns the no_move_ok entry of that event that lists
# the state. Mutations run in the background, JOBS at a time.
NAMES=""
running=0
run_one() {
  name="$1"; expect="$2"; snippet="$3"
  f="$WORK/$name.json"
  res="$WORK/$name.result"
  if ! "$PY" - "$WORK/original.json" "$f" "$snippet" > "$WORK/$name.apply" 2>&1 <<'EOF'
import json, sys
src, dst, code = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(src))
def row(i):
    for r in d["rows"]:
        if r["id"] == i:
            return r
    raise SystemExit("no row " + i)
def nmo(event, state):
    for nm in d["events"][event].get("no_move_ok", []):
        if state in nm["states"]:
            return nm
    raise SystemExit("no no_move_ok entry of %s for %s" % (event, state))
exec(code)
json.dump(d, open(dst, "w"), indent=1)
EOF
  then
    { echo "FAIL $name: the mutation itself did not apply"; sed 's/^/     /' "$WORK/$name.apply"; } > "$res"
    return
  fi
  out="$WORK/$name.out"
  "$PY" "$CHECKER" "$f" > "$out" 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "FAIL $name: checker passed a broken table" > "$res"
  elif grep -Eq "$expect" "$out"; then
    echo "ok   $name: exit $rc, $(grep -E "$expect" "$out" | head -1 | cut -c1-170)" > "$res"
  else
    { echo "FAIL $name: exit $rc but no line matches /$expect/:"; grep '^ERROR' "$out" | head -5 | sed 's/^/     /'; } > "$res"
  fi
}
mutate() {
  NAMES="$NAMES $1"
  run_one "$1" "$2" "$3" &
  running=$((running + 1))
  if [ "$running" -ge "$JOBS" ]; then
    wait
    running=0
  fi
}

# ---- coverage, precedence, schema ----
mutate delete_needed_row \
  '\(open_pr, stage_succeeded\) has no matching row' \
  'd["rows"] = [r for r in d["rows"] if r["id"] != "21"]'

mutate add_tie \
  'tie at precedence 55 between rows 26, 26z' \
  'import copy; r = copy.deepcopy(row("26")); r["id"] = "26z"; d["rows"].append(r)'

mutate undeclared_fact \
  "reads undeclared fact 'made_up_fact'" \
  'row("22")["guard"]["made_up_fact"] = True'

mutate unreachable_state \
  "state 'waiting_ci' is unreachable from the creation target queued" \
  'r = row("59"); r["to"] = "needs_human"; r["records"] = {"blocked_stage": {"default": "sync"}}'

mutate parked_person_exit_removed \
  "parked state 'needs_info' has no exit row into an active state on a person event" \
  '
for r in d["rows"]:
    if r["event"].startswith("person_") and not r.get("stay") and "needs_info" in r["from"]:
        r["from"].remove("needs_info")
d["rows"] = [r for r in d["rows"] if r["from"]]
'

mutate parked_exits_only_end_the_job \
  "parked state 'waiting_ci' has no exit row into an active state on a person event" \
  '
d["events"]["person_rework"]["occurs_in"].remove("waiting_ci")
d["events"]["person_feedback"]["occurs_in"].remove("waiting_ci")
for i in ("37b", "37c", "37d", "40p", "40f", "69c", "69d"):
    row(i)["from"].remove("waiting_ci")
for x in d["expectations"]:
    if "states" in x and "waiting_ci" in x["states"] and set(x["events"]) & {"person_rework", "person_feedback"}:
        x["states"].remove("waiting_ci")
'

mutate sync_marker_exit_removed \
  '\(sync, stage_succeeded\) has no matching row when .*base_moved=false.*marker_agreement=false' \
  'd["rows"] = [r for r in d["rows"] if r["id"] != "31b"]'

mutate merged_row_missing_in_gate \
  '\(gate, github_change\) has no matching row when .*pr_merged_by_person=true' \
  'row("54")["from"].remove("gate")'

mutate prelaunch_park_removed \
  '\(prepare, launch_due\) has no matching row when .*tier_confirm_blocking=true' \
  'd["rows"] = [r for r in d["rows"] if r["id"] != "40b"]'

mutate terminal_rework_row_removed \
  '\(ready, person_rework\) has no matching row when .*via_comment=false' \
  'd["rows"] = [r for r in d["rows"] if r["id"] != "37c"]'

mutate resume_list_drift \
  "row '15' resume lists" \
  'row("15")["resume"].remove("gate")'

mutate no_move_without_reason \
  'has no written reason' \
  'd["events"]["sync_tick"]["no_move_ok"][0]["reason"] = ""'

mutate issue_changed_read_where_undefined \
  "reads fact 'issue_changed' in state 'queued', where it is not defined" \
  'row("50")["from"].append("queued")'

mutate blanket_no_move_ok \
  'no_move_ok\[0\] has an empty or missing "when"' \
  '
d["events"]["stage_succeeded"]["no_move_ok"] = [{"states": ["sync"], "when": {}, "reason": "stays"}]
d["rows"] = [r for r in d["rows"] if r["id"] not in ("31b", "33b", "35")]
'

mutate contradictory_dependencies \
  '\(sync, stage_succeeded\) has no fact assignment that the fact dependencies allow' \
  '
d["fact_dependencies"].append({"states": ["sync"], "if": {}, "then": {"base_moved": True}})
d["fact_dependencies"].append({"states": ["sync"], "if": {}, "then": {"base_moved": False}})
d["rows"] = [r for r in d["rows"] if r["id"] != "31b"]
'

mutate dead_row_keeps_state_reachable \
  "row '64z' never wins in state 'merging'" \
  '
import copy
r = row("59"); r["to"] = "needs_human"; r["records"] = {"blocked_stage": {"default": "sync"}}
z = copy.deepcopy(row("64")); z["id"] = "64z"; z["to"] = "waiting_ci"; z["precedence"] = 99; d["rows"].append(z)
'

mutate dead_row_shadowed \
  "row '31z' never wins in state 'sync'" \
  'import copy; z = copy.deepcopy(row("31")); z["id"] = "31z"; z["to"] = "merged"; z["precedence"] = 99; z.pop("writes", None); d["rows"].append(z)'

mutate resume_into_terminal \
  "records resume_state = 'merged', a terminal state" \
  '
row("40")["records"]["resume_state"]["sync"] = "merged"
for i in ("41", "41e", "41k"):
    row(i)["resume"].append("merged")
'

mutate resume_into_parked \
  "records resume_state = 'needs_human', a parked state" \
  '
row("40")["records"]["resume_state"]["sync"] = "needs_human"
for i in ("41", "41e", "41k"):
    row(i)["resume"].append("needs_human")
'

mutate new_park_entry_without_records \
  "row '12x' enters needs_spec_approval without recording resume_state" \
  'import copy; z = copy.deepcopy(row("12")); z["id"] = "12x"; z["to"] = "needs_spec_approval"; z["precedence"] = 37; del z["records"]; d["rows"].append(z)'

mutate waiting_operator_entry_without_records \
  "row '40g' enters waiting_operator without recording resume_state" \
  '
del row("40g")["records"]
for i in ("41", "41e", "41k"):
    row(i)["resume_from"].remove("40g")
'

mutate drop_lease_in_build \
  "event 'lease_expired' does not occur in state 'build', which is run by worker" \
  '
d["events"]["lease_expired"]["occurs_in"].remove("build")
for i in ("43o", "43l", "39ld", "39l", "43y"):
    row(i)["from"].remove("build")
for x in d["expectations"]:
    if "lease_expired" in x["events"] and "build" in x.get("states", []):
        x["events"].remove("lease_expired")
'

mutate drop_cancel_in_merging \
  "event 'person_cancel' does not occur in state 'merging'" \
  '
d["events"]["person_cancel"]["occurs_in"].remove("merging")
for i in ("53", "69g"):
    row(i)["from"].remove("merging")
'

mutate typo_defined_in \
  "fact 'held_question' has unknown key 'defined_inn'" \
  'f = d["facts"]["held_question"]; f["defined_inn"] = f.pop("defined_in")'

mutate no_move_ok_reads_undefined_fact \
  "reads fact 'needs_info_answer' in state 'ready', where it is not defined" \
  'nmo("github_change", "ready")["when"]["needs_info_answer"] = False'

mutate dependency_reads_undefined_fact \
  "reads fact 'held_question', which is defined only in some states" \
  'd["fact_dependencies"].append({"if": {"held_question": True}, "then": {"tree_dirty": False}})'

mutate active_state_without_run_by \
  "active state 'gate' needs run_by" \
  'del d["states"]["gate"]["run_by"]'

mutate merging_lease_rows_removed \
  '\(merging, lease_expired\): the event can occur but no row handles it' \
  '
for i in ("43o", "43l", "39l", "39ld", "43y", "40y"):
    row(i)["from"].remove("merging")
    row(i).get("records", {}).get("blocked_stage", {}).pop("merging", None)
    if isinstance(row(i).get("writes"), dict):
        row(i)["writes"].pop("merging", None)
for x in d["expectations"]:
    if "lease_expired" in x["events"] and "merging" in x.get("states", []):
        x["events"].remove("lease_expired")
'

# ---- the always-ask confirmation (rules.person_confirmation) ----
mutate confirmation_dropped_from_rework \
  "\[confirmation\] row '(37b|37c|40p)' handles person_rework, which needs a person's confirmation, but its guard does not read unvouched_session_action" \
  '
d["rows"] = [r for r in d["rows"] if r["id"] != "69d"]
for i in ("40p", "37b", "37c"):
    del row(i)["guard"]["unvouched_session_action"]
'

mutate confirmation_dropped_from_cancel \
  "\[confirmation\] row '53' handles person_cancel, which needs a person's confirmation, but its guard does not read" \
  '
d["rows"] = [r for r in d["rows"] if r["id"] != "69g"]
row("53")["guard"] = {}
'

mutate refusal_row_acts \
  "\[confirmation\] row '69c' acts on person_feedback while unvouched_session_action is true" \
  'r = row("69c"); del r["stay"]; r["to"] = "rework"; r["from"] = ["ready", "approve", "merging", "waiting_ci"]; r["writes"] = ["undo of ready"]'

mutate confirmation_stay_by_no_move_ok \
  "\[confirmation\] event 'person_rebuild' no_move_ok\[0\] can let a job stay while unvouched_session_action is true" \
  '
d["rows"] = [r for r in d["rows"] if r["id"] != "69h"]
d["events"]["person_rebuild"]["no_move_ok"] = [{"states": list(d["events"]["person_rebuild"]["occurs_in"]), "when": {"unvouched_session_action": True}, "reason": "refused"}]
'

# ---- outcomes the prose names (expectations) ----
mutate cancel_in_merging_goes_to_ready \
  "expectation 'cancel_ends_the_job': in \(merging, person_cancel\) the job must move to cancelled" \
  '
import copy
row("53")["from"].remove("merging")
z = copy.deepcopy(row("53")); z["id"] = "53m"; z["from"] = ["merging"]; z["to"] = "ready"; d["rows"].append(z)
'

mutate cancel_signal_outranks_merge \
  "expectation 'merge_by_person_wins': in \(.*, github_change\) the job must move to merged, but row '53b' wins" \
  'row("53b")["precedence"] = 4'

mutate reject_removed_from_needs_human \
  "expectation 'reject_rejects' names state 'needs_human', where event 'person_reject' does not occur" \
  '
d["events"]["person_reject"]["occurs_in"].remove("needs_human")
d["rows"] = [r for r in d["rows"] if r["id"] != "48"]
row("69f")["from"].remove("needs_human")
'

mutate untrusted_edit_ignored_in_build \
  "expectation 'untrusted_edit_parks': in \(build, github_change\) the job must move to needs_human or waiting_operator" \
  '
row("51b")["from"].remove("build")
del nmo("github_change", "build")["when"]["untrusted_edit"]
'

mutate untrusted_close_ignored_in_review \
  "expectation 'untrusted_close_parks': in \(review, github_change\) the job must move to needs_human or waiting_operator, but row '52' wins" \
  'row("53u")["precedence"] = 16'

mutate push_ignored_before_build \
  "expectation 'foreign_push_before_build': in \(spec, github_change\) one of rows 52e must win, but no row matches" \
  '
row("52e")["from"].remove("spec")
del nmo("github_change", "spec")["when"]["foreign_head_change"]
'

mutate changes_requested_ignored_in_waiting_ci \
  "expectation 'changes_requested_reworks': in \(waiting_ci, github_change\) the job must move to rework or waiting_operator" \
  '
row("37")["from"].remove("waiting_ci")
del nmo("github_change", "waiting_ci")["when"]["trusted_changes_requested"]
'

mutate row_2_ignores_slots \
  "expectation 'queued_waits_for_slot': in \(queued, sync_tick\) the job must stay, but row '2' wins" \
  'del row("2")["guard"]["slot_free"]'

mutate triage_retry_resumes_any_park \
  "expectation 'triage_retry_revouches_only': in \(needs_human, person_retry\) the job must stay, but row '(44r|47|44c)' wins" \
  'row("44t")["precedence"] = 45'

mutate retry_while_issue_closed \
  "expectation 'closed_issue_refuses_resume': in \(needs_human, person_retry\) the job must stay" \
  'd["rows"] = [r for r in d["rows"] if r["id"] != "44z"]'

mutate ready_left_without_mark \
  "expectation 'ready_mark_restored': in \(ready, sync_tick\) the job must move to sync, but row '36u' wins \(\(stays\)\)" \
  'r = row("36u"); del r["to"]; r["stay"] = True'

mutate expectation_that_never_applies \
  "expectation 'queued_waits_for_slot' never applies in \(queued, sync_tick\)" \
  'd["fact_dependencies"].append({"states": ["queued"], "if": {}, "then": {"slot_free": True}})'

# ---- creation target ----
mutate creation_targets_ready \
  "creation row '1' targets 'ready'; a new job starts in 'queued'" \
  'd["creation"][0]["to"] = "ready"'

mutate creation_targets_needs_human \
  "creation row '1' targets 'needs_human'; a new job starts in 'queued'" \
  'd["creation"][0]["to"] = "needs_human"'

# ---- goal reachability ----
mutate needs_info_can_only_end \
  "state 'needs_info' cannot reach ready" \
  '
for i in ("8", "8a", "8e", "8r", "9", "9a", "9r"):
    r = row(i); r["to"] = "rejected"; r.pop("records", None)
row("51b")["from"].remove("needs_info")
row("53u")["from"].remove("needs_info")
'

# ---- no_move_ok literals the dependencies force ----
mutate no_move_ok_forced_literal \
  "\[no_move_ok\] event 'github_change' no_move_ok\[[0-9]+\] reads pr_exists=true in state 'gate', which the fact dependencies force there" \
  '
row("52")["from"].remove("gate")
nm = nmo("github_change", "gate"); nm["states"].remove("gate")
d["events"]["github_change"]["no_move_ok"].append({"states": ["gate"], "when": {"pr_exists": True}, "reason": "anything"})
d["expectations"] = [x for x in d["expectations"] if x["id"] != "foreign_push_regates"]
'

mutate no_move_ok_forced_literal_build_started \
  "\[no_move_ok\] event 'stage_succeeded' no_move_ok\[0\] reads build_started=true in state 'sync', which the fact dependencies force there" \
  '
d["events"]["stage_succeeded"]["no_move_ok"] = [{"states": ["sync"], "when": {"build_started": True}, "reason": "anything"}]
d["rows"] = [r for r in d["rows"] if r["id"] != "31b"]
d["expectations"] = [x for x in d["expectations"] if x["id"] != "marker_disagreement_parks"]
'

# ---- blocking writes (rules.blocking_write) ----
mutate undo_without_confirm_park_waiting_ci \
  "\[blocking_write\] \(waiting_ci, sync_tick\): row '63(s|t)' makes the blocking write\(s\) undo of ready, but when blocking_write_confirm is true row '63(s|t)' wins" \
  '
d["rows"] = [r for r in d["rows"] if r["id"] != "40t"]
for i in ("41", "41e", "41k"):
    row(i)["resume_from"].remove("40t")
'

mutate escalation_without_confirm_park \
  "\[blocking_write\] \(approve, judge_escalate\): row '58' makes the blocking write\(s\) undo of ready" \
  '
d["rows"] = [r for r in d["rows"] if r["id"] != "40j"]
for i in ("41", "41e", "41k"):
    row(i)["resume_from"].remove("40j")
'

mutate park_without_resume_record \
  "\[blocking_write\] \(ready, sync_tick\): row '36' makes the blocking write\(s\) undo of ready, but when blocking_write_confirm is true row '40r' wins instead of a row that parks" \
  '
r = row("40r"); r["to"] = "needs_human"; r["records"] = {"blocked_stage": {"default": "sync"}}
for i in ("41", "41e", "41k"):
    row(i)["resume_from"].remove("40r")
'

mutate undeclared_push_in_sync \
  "\[blocking_write\] row '32' requires blocking_write_confirm false but lists no write for sync" \
  'del row("32")["writes"]'

mutate undeclared_pr_create \
  "\[blocking_write\] row '21' requires blocking_write_confirm false but lists no write for open_pr" \
  'del row("21")["writes"]'

mutate ready_confirm_park_removed \
  "\[blocking_write\] \(ready, github_change\): row '(37|38|51|51b|52|53u)' makes the blocking write\(s\) undo of ready, but when blocking_write_confirm is true row '(37|38|51|51b|52|53u)' wins" \
  '
d["rows"] = [r for r in d["rows"] if r["id"] != "40g"]
for i in ("41", "41e", "41k"):
    row(i)["resume_from"].remove("40g")
'

mutate auto_mode_refusal_removed \
  '\(needs_spec_approval, person_approve_spec\) has no matching row when .*unvouched_session_action=true' \
  'd["rows"] = [r for r in d["rows"] if r["id"] != "69a"]'

# ---- the ready mark (rules.ready_mark) ----
mutate escalation_keeps_ready_mark \
  "\[ready_mark\] row '58' moves a job from approve, where the PR is marked ready, to needs_human without 'undo of ready' in its writes" \
  'del row("58")["writes"]'

mutate lease_park_from_merging_keeps_mark \
  "\[ready_mark\] row '43l' moves a job from merging, where the PR is marked ready, to needs_human without 'undo of ready'" \
  'row("43l")["writes"].pop("merging")'

mutate ready_entered_without_mark \
  "\[ready_mark\] row '31' moves a job from sync into ready, where the PR is marked ready, without 'ready mark'" \
  'del row("31")["writes"]'

# ---- records as if (rules.records_as_if) ----
mutate spec_change_resumes_into_intake \
  "\[records_as_if\] row '20b' records resume_state = \['intake'\] for build, but with spec_change_needs_approval false the winning rows enter \['open_pr'\]" \
  '
row("20b")["records"]["resume_state"]["build"] = "intake"
row("15")["resume"].append("intake")
'

mutate spec_approval_resumes_into_spec \
  "\[records_as_if\] row '14' records resume_state = \['spec'\] for spec, but with spec_approval_required false the winning rows enter \['build'\]" \
  '
row("14")["records"]["resume_state"]["default"] = "spec"
row("15")["resume"].append("spec")
'

# ---- reachability through winning rows only ----
mutate gate_skips_review_to_sync \
  "state 'review' is unreachable from the creation target queued" \
  'row("22")["to"] = "sync"'

# ---- stage-outcome safety rules (required expectations) ----
mutate sync_to_ready_without_review \
  "expectation 'ready_needs_valid_review': in \(sync, stage_succeeded\) the job must move to gate, but row '31' wins" \
  '
d["rows"] = [r for r in d["rows"] if r["id"] not in ("32c", "32d")]
g = row("31")["guard"]; del g["valid_review_at_head"]; del g["ledger_passes"]
'

mutate protected_to_rework \
  "expectation 'protected_violation_needs_human': in \(gate, stage_succeeded\) the job must move to needs_human, but row '25' wins" \
  'r = row("25"); r["to"] = "rework"; del r["records"]'

mutate conflict_protected_to_resolve \
  "expectation 'protected_conflict_needs_human': in \(sync, stage_succeeded\) the job must move to needs_human, but row '33b' wins" \
  'r = row("33b"); r["to"] = "resolve"; del r["records"]'

mutate escalated_to_rework \
  "expectation 'escalated_review_needs_human': in \(review, stage_succeeded\) the job must move to needs_human or waiting_operator, but row '29' wins" \
  'r = row("29"); r["to"] = "rework"; del r["records"]'

mutate ready_marker_disagreement_stays \
  "expectation 'marker_disagreement_in_ready_parks': in \(ready, github_change\) the job must move to needs_human or waiting_operator, but row '38' wins \(\(stays\)\)" \
  'r = row("38"); del r["to"]; del r["records"]; del r["writes"]; r["stay"] = True'

mutate person_push_ignores_untrusted_edit \
  "expectation 'person_push_waits_on_untrusted_edit': in \(needs_human, github_change\) the job must stay, but row '52h' wins" \
  'del row("52h")["guard"]["untrusted_edit"]'

mutate person_push_ignores_untrusted_close \
  "expectation 'person_push_waits_on_untrusted_close': in \(needs_human, github_change\) the job must stay, but row '52h' wins" \
  'del row("52h")["guard"]["untrusted_close"]'

mutate person_push_ignores_build_reached \
  "expectation 'person_push_before_build_waits': in \(needs_human, github_change\) the job must stay, but row '52h' wins" \
  'del row("52h")["guard"]["build_started"]'

mutate resolve_repeat_retry_launches \
  "expectation 'resolve_repeat_refused': in \(needs_human, person_retry\) the job must stay, but row '44r' wins" \
  'd["rows"] = [r for r in d["rows"] if r["id"] != "44xr"]'

mutate merge_done_to_needs_human \
  "expectation 'merge_success_merges': in \(merging, stage_succeeded\) the job must move to merged, but row '64' wins" \
  'r = row("64"); r["to"] = "needs_human"; r["records"] = {"blocked_stage": {"default": "sync"}}; r["writes"] = ["undo of ready"]'

mutate worker_parked_stays \
  "expectation 'worker_park_needs_human': in \((spec|build|open_pr|review|rework), worker_parked\) the job must move to needs_human, but row '43' wins" \
  'r = row("43"); del r["to"]; del r["records"]; r["stay"] = True'

mutate ci_timeout_stays \
  "expectation 'ci_timeout_needs_human': in \(waiting_ci, sync_tick\) the job must move to needs_human or waiting_operator, but row '63t' wins" \
  'r = row("63t"); del r["to"]; del r["records"]; del r["writes"]; r["stay"] = True'

mutate judge_reject_to_cancelled \
  "expectation 'judge_reject_rejects': in \(intake, judge_reject\) the job must move to rejected, but row '5' wins" \
  'row("5")["to"] = "cancelled"'

mutate triage_retry_reintakes_in_needs_info \
  "expectation 'needs_info_triage_retry_revouches_only': in \(needs_info, person_retry\) the job must stay, but row '(8r|9r)' wins" \
  'd["rows"] = [r for r in d["rows"] if r["id"] != "8t"]'

# ---- every rule, the event order and the expectations are required ----
mutate drop_person_confirmation_and_69a \
  "rules.person_confirmation is missing; the checker requires every rule" \
  '
del d["rules"]["person_confirmation"]
for i in ("15", "15s"):
    del row(i)["guard"]["unvouched_session_action"]
d["rows"] = [r for r in d["rows"] if r["id"] != "69a"]
'

mutate drop_ready_mark_rule_and_undo_on_58 \
  "rules.ready_mark is missing; the checker requires every rule" \
  'del d["rules"]["ready_mark"]; del row("58")["writes"]'

mutate drop_push_check_and_21f \
  "rules.push_check is missing; the checker requires every rule" \
  '
del d["rules"]["push_check"]
d["rows"] = [r for r in d["rows"] if r["id"] != "21f"]
'

mutate drop_all_expectations \
  "required expectation 'cancel_ends_the_job' is missing from the table" \
  'd["expectations"] = []'

mutate drop_event_order \
  "missing top-level key 'event_order'" \
  'del d["event_order"]'

mutate person_event_with_no_states \
  "person event 'person_reject' has an empty occurs_in list" \
  '
d["events"]["person_reject"]["occurs_in"] = []
d["rows"] = [r for r in d["rows"] if r["event"] != "person_reject"]
d["expectations"] = [x for x in d["expectations"] if "person_reject" not in x["events"]]
d["rules"]["person_confirmation"]["events"].remove("person_reject")
'

# ---- a person merge is applied before every event of the pass (pass_first) ----
mutate drop_pass_first \
  "missing top-level key 'pass_first'" \
  'del d["pass_first"]'

mutate pass_first_names_cancel_row \
  "\[pass_first\] \(.*, github_change\): row '54' wins, but pass_first applies only rows 53b" \
  'd["pass_first"]["rows"] = ["53b"]'

# ---- the ready mark on computed targets ----
mutate park_records_ready_resume_ready_unmarked \
  "\[ready_mark\] row '44' can resume a job into ready, where the PR is marked ready; only rows 41, 41e, 41k may" \
  '
row("38")["records"]["blocked_stage"]["default"] = "ready"
for i in ("44", "44r"):
    row(i)["resume"].append("ready")
'

mutate draft_park_records_ready \
  "\[ready_mark\] row '40' records resume_state ready for prepare, where the PR is not marked ready" \
  'row("40")["records"]["resume_state"]["prepare"] = "ready"'

mutate ready_park_resumes_into_sync \
  "\[ready_mark\] row '40g' parks a job from ready, where the PR is marked ready, recording resume_state \['sync'\]; it must resume into ready" \
  'row("40g")["records"]["resume_state"]["default"] = "sync"'

# ---- the protected check before every engine push (rules.push_check) ----
mutate freeze_row_skips_open_pr \
  "\[push_check\] \(open_pr, stage_succeeded\): row '21' pushes, but when prepush_protected_failed is true row '21' wins" \
  'row("21f")["from"].remove("open_pr")'

mutate freeze_row_below_push_rows \
  "\[push_check\] \((open_pr|review|rework|resolve|sync), stage_succeeded\): row '[0-9a-z]+' pushes, but when prepush_protected_failed is true row '[0-9a-z]+' wins" \
  'row("21f")["precedence"] = 99'

mutate freeze_row_pushes \
  "\[push_check\] \(open_pr, stage_succeeded\): row '21' pushes, but when prepush_protected_failed is true row '21f' wins" \
  'row("21f")["writes"] = ["push"]'

wait

for name in $NAMES; do
  cat "$WORK/$name.result"
  case "$(head -1 "$WORK/$name.result")" in
    ok*) pass=$((pass + 1)) ;;
    *) fail=$((fail + 1)) ;;
  esac
done

# Duplicate JSON keys are rejected, not silently resolved to the last value.
f="$WORK/duplicate_key.json"
"$PY" - "$WORK/original.json" "$f" <<'EOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
old = '"to": "merged", "precedence": 5,'
assert text.count(old) == 1, "row 54 text not found"
open(dst, "w").write(text.replace(old, '"to": "merged", "to": "cancelled", "precedence": 5,'))
EOF
if "$PY" "$CHECKER" "$f" > "$WORK/duplicate_key.out" 2>&1; then
  echo "FAIL duplicate_key: checker passed a broken table"
  fail=$((fail + 1))
elif grep -q "duplicate key 'to'" "$WORK/duplicate_key.out"; then
  echo "ok   duplicate_key: $(grep "duplicate key" "$WORK/duplicate_key.out" | head -1 | cut -c1-150)"
  pass=$((pass + 1))
else
  echo "FAIL duplicate_key: no line names the duplicate key"
  fail=$((fail + 1))
fi

# The committed transitions.md equals the checker's --markdown output, under
# every interpreter.
for p in $PYS; do
  rm -rf "$WORK/md"
  mkdir -p "$WORK/md"
  cp "$HERE/transitions.json" "$WORK/md/transitions.json"
  if "$p" "$CHECKER" "$WORK/md/transitions.json" --markdown > "$WORK/md.out" 2>&1 \
     && diff -q "$HERE/transitions.md" "$WORK/md/transitions.md" > /dev/null; then
    echo "ok   transitions.md matches the checker's --markdown output ($p)"
    pass=$((pass + 1))
  else
    echo "FAIL transitions.md differs from the checker's --markdown output under $p (run check_transitions.py --markdown):"
    diff "$HERE/transitions.md" "$WORK/md/transitions.md" | head -5 | sed 's/^/     /'
    fail=$((fail + 1))
  fi
done

# The citation pattern reads every id of a list or range: ids joined by
# commas, "and", "or", "to", a hyphen or an en dash, and ids followed by a
# parenthesis, as in "Rows 39 (stage_failed) and 39l (lease_expired)".
"$PY" - > "$WORK/citepat.out" 2>&1 <<'EOF'
import re
ID = r"\d+[a-z]{0,2}"
PAREN = r"(?:\s*\([^()]*\))?"
SEP = r"(?:,\s+and\s+|,\s+|\s+and\s+|\s+to\s+|\s+or\s+|\s*-\s*|\s*\u2013\s*)"
pat = re.compile(r"\b[Rr]ows?\s+(" + ID + PAREN + r"(?:" + SEP + ID + PAREN + r")*)")
cases = {
    "rows 69a\u201369z": ["69a", "69z"],
    "rows 69a-69h": ["69a", "69h"],
    "Rows 39 (stage_failed) and 39zz (lease_expired)": ["39", "39zz"],
    "rows 37, 37b, 37c and 37d": ["37", "37b", "37c", "37d"],
}
bad = 0
for text, want in cases.items():
    got = [i for m in pat.finditer(text) for i in re.findall(ID, re.sub(r"\([^()]*\)", "", m.group(1)))]
    if got != want:
        bad += 1
        print("pattern reads %r as %s, not %s" % (text, got, want))
raise SystemExit(1 if bad else 0)
EOF
if [ "$?" -eq 0 ]; then
  echo "ok   the citation pattern reads ranges, en dashes and parenthesised ids"
  pass=$((pass + 1))
else
  echo "FAIL the citation pattern:"
  sed 's/^/     /' "$WORK/citepat.out"
  fail=$((fail + 1))
fi

# Every row id that design.json or transitions.json cites exists.
for p in $PYS; do
  if "$p" - "$HERE/transitions.json" "$HERE/design.json" > "$WORK/cited.out" 2>&1 <<'EOF'
import json, re, sys
t = json.load(open(sys.argv[1]))
ids = set(r["id"] for r in t["rows"]) | set(c["id"] for c in t.get("creation", []))
ID = r"\d+[a-z]{0,2}"
PAREN = r"(?:\s*\([^()]*\))?"
SEP = r"(?:,\s+and\s+|,\s+|\s+and\s+|\s+to\s+|\s+or\s+|\s*-\s*|\s*\u2013\s*)"
pat = re.compile(r"\b[Rr]ows?\s+(" + ID + PAREN + r"(?:" + SEP + ID + PAREN + r")*)")
def strings(x):
    if isinstance(x, str):
        yield x
    elif isinstance(x, dict):
        for k, v in x.items():
            if k == "__open_before_fix":
                continue
            for s in strings(v):
                yield s
    elif isinstance(x, list):
        for v in x:
            for s in strings(v):
                yield s
missing = {}
count = 0
for path in sys.argv[1:]:
    for s in strings(json.load(open(path))):
        for m in pat.finditer(s):
            for rid in re.findall(ID, re.sub(r"\([^()]*\)", "", m.group(1))):
                count += 1
                if rid not in ids:
                    missing.setdefault(rid, set()).add(path.rsplit("/", 1)[-1])
for rid in sorted(missing):
    print("missing row %s cited in %s" % (rid, ", ".join(sorted(missing[rid]))))
print("%d row citations checked" % count)
sys.exit(1 if missing else 0)
EOF
  then
    echo "ok   every cited row id exists ($p): $(tail -1 "$WORK/cited.out")"
    pass=$((pass + 1))
  else
    echo "FAIL cited row ids are missing from transitions.json ($p):"
    sed 's/^/     /' "$WORK/cited.out"
    fail=$((fail + 1))
  fi
done

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
