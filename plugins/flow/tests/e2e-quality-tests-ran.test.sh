# shellcheck shell=bash disable=SC2034  # E2E_ACTIVE_PLUGIN is read by lib/e2e.sh
# End-to-end: the System One decision point quality.tests-ran. After a Bash
# call that Flow records as a passing built-in test run, the quality-run hook
# (hooks/scripts/record-quality-run.sh) may ask the provider whether the
# output shows any test executing. With the site on, a confident "none_ran" or
# "all_skipped" answer records the run as not passing, and the task-completion
# gate says why. Off, shadow, no provider and no answer leave the ledger
# entry as this hook writes it without System One; the exit-code rule applies
# whatever the site's mode.
#
# Each scenario runs the shipped hook, ledger helper and gate in a scratch
# repository with its own HOME, against the shipped system-one/questions.yaml
# (so the shipped threshold is what is tested) and a stub server
# (tests/lib/s1_stub.py) that logs every request. One artifact per scenario
# goes to $FLOW_E2E_ARTIFACT_DIR. FLOW_E2E_SCENARIOS=a,b runs only the named
# scenarios.
#
# Ways it can be wrong, written down before the scenarios:
#   Q1  the output is sent as one string, or its head is kept, so the client's
#       shortening cuts away the runner's summary on the last line
#   Q2  the hook asks on lint, on a repository pattern, on a masked, failed or
#       interrupted run, or with the site off, so ordinary Bash calls start
#       python3 or send output to the provider
#   Q3  an answer upgrades a failed run, or "unclear", a below-threshold
#       answer or a shadow answer downgrades a pass
#   Q4  off, provider none, timeout, an HTTP error or a malformed reply
#       changes the ledger line (a stray field, a lost entry)
#   Q5  a malformed output_check in the ledger is read as a downgrade or
#       crashes the reader
#   Q6  the gate shows a downgraded run as "exited 0; no passing run", or the
#       generic branch wins over the new one
#   Q7  the ledger's s1_state_sha256 is computed over other bytes than the
#       client hashes, so ledger lines never join records
#   Q8  a repository's settings switch the site on or start shadow, or a repository-only on
#       still starts the client and stamps a digest that joins no record
#   Q9  the record cannot be matched to the tool call it judged (no --ref, or
#       a --ref the client refuses, which loses the record)
#   Q10 the hook waits for an exit_code that Claude Code does not send, so a
#       real passing run is never asked about and never counts as passing;
#       or it reads a call moved to the background, or a non-zero exit Claude
#       Code reports as informational, as exit 0
#   Q11 the hook is stopped while it waits for the answer and leaves the file
#       holding the test output in TMPDIR, or exits without recording the run
#   Q12 the hook reads exit 0 for a call whose status need not be the test
#       command's own: a failing run piped to tail, grep or tee, followed by
#       `; cmd`, `&& cmd` or `|| cmd`, put in the background, or after a
#       heredoc, is recorded as passing and asked about; or a plain run after
#       `cd x &&`, an assignment or a leading set line is not asked about
#   Q13 a value assigned in the command's prefix (`TOKEN=x pytest`) is sent,
#       in the command or in the shell's trace of it (`set -x`, `set -v`); or
#       a cd directory holding `=` is sent changed
#   Q14 a run after `cd` into another repository, a nested repository or a
#       submodule is asked about under the session repository's mode,
#       bypassing that repository's settings; or the mode is read in the
#       directory the hook was started in rather than the payload's cwd

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

HOOK="hooks/scripts/record-quality-run.sh"
SITE="quality.tests-ran"
# The hook before this decision point existed (the base of the change): the
# off and no-answer lines must equal what it writes, apart from the exit code.
BASE_COMMIT=85b63bc4

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

# Replies in TypeSafe's shape for the one choice question. Probabilities cover
# every option and sum to 1, and the choice is the most probable option, as
# the client requires.
_reply() { # <choice> <confidence>
  local c="$1" conf="$2"
  jq -nc --arg c "$c" --argjson conf "$conf" '
    {model: "jev-1.13.0",
     answers: {outcome: {type: "choice", choice: $c, confidence: $conf,
       probabilities: ({executed: 0.01, none_ran: 0.01, all_skipped: 0.01, unclear: 0.01} + {($c): 0.97})}}}'
}
# 0.6 is below the shipped 0.9; the probabilities still agree with the choice.
LOW_NONE_RAN='{"model":"jev-1.13.0","answers":{"outcome":{"type":"choice","choice":"none_ran","confidence":0.6,"probabilities":{"executed":0.1,"none_ran":0.7,"all_skipped":0.1,"unclear":0.1}}}}'

_q_setup() {
  if [ -n "${CI:-}" ]; then
    { printf 'progress %s %s\n' "$(date -u +%H:%M:%S)" "$1" >&3; } 2>/dev/null
  fi
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo feature/q
  Q_SID="sess-$1"
  Q_LEDGER="$E2E_HOME/.claude/flow-state/sessions/$Q_SID/quality-ledger.jsonl"
  Q_RECORDS="$E2E_HOME/.claude/flow-state/system-one.jsonl"
}

# _q_settings <mode> [stub name] [extra systemOne json] — user settings with
# the provider at that stub.
_q_settings() {
  local url="" extra="${3:-}"
  [ -n "${2:-}" ] && url=$(e2e_stub_url "$2")
  [ -n "$extra" ] || extra='{}'
  e2e_user_settings "$(jq -nc --arg u "$url" --arg m "$1" --arg s "$SITE" --argjson x "$extra" \
    '{systemOne: ({provider: "custom", baseUrl: $u, uses: {($s): $m}} + $x)}')"
}

# _q_payload <command> <stdout> [exit code] [event] [tool_use_id] [stderr] —
# a Bash hook payload in the shape Claude Code sends: a PostToolUse
# tool_response has no exit code (its keys as Claude Code 2.1.283 transcripts
# record the Bash tool result), and a PostToolUseFailure carries it in the
# "Exit code N" line of `error`. The exit code argument is used only there.
_q_payload() {
  jq -nc --arg sid "$Q_SID" --arg cwd "$E2E_REPO" --arg cmd "$1" --arg out "$2" \
    --argjson ec "${3:-0}" --arg ev "${4:-PostToolUse}" --arg id "${5:-toolu_01q}" --arg err "${6:-}" '
    {session_id: $sid, cwd: $cwd, hook_event_name: $ev, tool_name: "Bash", tool_use_id: $id,
     tool_input: {command: $cmd}}
    + (if $ev == "PostToolUseFailure" then {error: ("Exit code \($ec)\n" + $out)}
       else {tool_response: {stdout: $out, stderr: $err, interrupted: false, isImage: false, noOutputExpected: false}} end)'
}

_q_run() { e2e_run_hook "$HOOK" "$1"; }
_q_last() { tail -n 1 "$Q_LEDGER" 2>/dev/null; }
_q_status() { e2e_run_bin bin/flow-quality-ledger.sh status --session "$Q_SID"; }
_q_requests() { local _E2E_EXTRA_FRAMES=1; e2e_expect_equal "$2" "$(e2e_stub_requests "$1")" "requests received by stub $1"; }
# A ledger line without the fields that differ between two runs of one
# payload: the time, the digest of a state the client hashed, and the exit
# code, which the hook before this change left null for every PostToolUse
# payload (the scenarios check it on its own).
_q_norm() { jq -cS 'del(.at, .s1_state_sha256, .exit_code)' <<<"$1"; }
# _q_exit_pair <base line> <new line> — "<base exit_code> <new exit_code>".
_q_exit_pair() { printf '%s %s' "$(jq -c '.exit_code' <<<"$1")" "$(jq -c '.exit_code' <<<"$2")"; }

NONE_RAN_OUT=$'============================= test session starts ==============================\ncollected 0 items\n\n============================ no tests ran in 0.01s =============================\n'
PASS_OUT=$'============================= test session starts ==============================\ncollected 3 items\n\ntests/test_a.py ...                                                       [100%]\n\n============================== 3 passed in 0.02s ===============================\n'

# ----------------------------------------------------------------- on

if _want qtr-on-none-ran; then
  _flow_test_begin "qtr-on-none-ran"
  _q_setup qtr-on-none-ran "site on, a file edit, then pytest exits 0 with 'no tests ran' and the stub answers none_ran at 0.98: one request, the run is recorded as not passing with the reason, status names it, and the gate blocks the task saying no tests ran (Q6)"
  e2e_stub_start a "{\"body\":$(_reply none_ran 0.98)}"
  _q_settings on a
  printf 'x = 1\n' > "$E2E_REPO/app.py"
  e2e_run_hook hooks/scripts/log-file-changes.sh "$(jq -nc --arg sid "$Q_SID" --arg cwd "$E2E_REPO" --arg p "$E2E_REPO/app.py" \
    '{session_id: $sid, cwd: $cwd, hook_event_name: "PostToolUse", tool_name: "Write", tool_input: {file_path: $p}}')"
  _q_run "$(_q_payload "pytest -q" "$NONE_RAN_OUT")"
  e2e_expect_equal "0" "$E2E_RC" "hook exit status"
  e2e_expect_equal "" "$E2E_OUT" "hook stdout"
  _q_requests a 1
  e2e_expect_equal '{"verdict":"none_ran","site":"quality.tests-ran","model":"jev-1.13.0","confidence":0.98}' \
    "$(jq -c '.output_check' <<<"$(_q_last)")" "the entry's output_check"
  e2e_expect_equal "true" "$(jq -r '.s1_state_sha256 | test("^[0-9a-f]{64}$")' <<<"$(_q_last)")" "the entry carries the state's sha256"
  e2e_expect_equal "0 false false test" "$(jq -r '"\(.exit_code) \(.masked) \(.failed) \(.kind)"' <<<"$(_q_last)")" "exit code, masked, failed and kind as before"
  _q_status
  e2e_expect_line "LAST_PASSING_RUN=none"
  e2e_expect_line "LAST_RUN_EXIT=0"
  e2e_expect_line "LAST_RUN_OUTPUT_CHECK=none_ran"
  # What was sent: the state, built from the payload, with the summary.
  e2e_expect_equal "pytest -q|0|true" \
    "$(jq -r '.body.state | "\(.command)|\(.exit_code)|\(.output_tail[-1] | test("no tests ran"))"' "$(e2e_stub_log a)")" "command, exit code and the last output line sent"
  e2e_run_hook hooks/scripts/verify-task-completion.sh "$(jq -nc --arg sid "$Q_SID" --arg cwd "$E2E_REPO" '{session_id: $sid, cwd: $cwd, task_id: "1", task_subject: "ship it"}')"
  e2e_expect_equal "2" "$E2E_RC" "gate exit status"
  e2e_expect_err "the last quality run exited 0 but its output showed no tests ran; no passing run this session"
  e2e_expect_err_lacks "the last quality run exited 0; no passing run"
fi

if _want qtr-on-all-skipped-gate; then
  _flow_test_begin "qtr-on-all-skipped-gate"
  _q_setup qtr-on-all-skipped-gate "site on: a file edit, then a test run whose every test was skipped (stub answers all_skipped), then TaskCompleted: the gate blocks and says every test was skipped"
  e2e_stub_start a "{\"body\":$(_reply all_skipped 0.97)}"
  _q_settings on a
  printf 'x = 1\n' > "$E2E_REPO/app.py"
  e2e_run_hook hooks/scripts/log-file-changes.sh "$(jq -nc --arg sid "$Q_SID" --arg cwd "$E2E_REPO" --arg p "$E2E_REPO/app.py" \
    '{session_id: $sid, cwd: $cwd, hook_event_name: "PostToolUse", tool_name: "Write", tool_input: {file_path: $p}}')"
  _q_run "$(_q_payload "cargo test" $'running 4 tests\ntest a ... ignored\ntest b ... ignored\ntest c ... ignored\ntest d ... ignored\n\ntest result: ok. 0 passed; 0 failed; 4 ignored; 0 measured; 0 filtered out\n')"
  _q_requests a 1
  e2e_expect_equal "all_skipped" "$(jq -r '.output_check.verdict' <<<"$(_q_last)")" "the entry's verdict"
  e2e_run_hook hooks/scripts/verify-task-completion.sh "$(jq -nc --arg sid "$Q_SID" --arg cwd "$E2E_REPO" '{session_id: $sid, cwd: $cwd, task_id: "1", task_subject: "ship it"}')"
  e2e_expect_equal "2" "$E2E_RC" "gate exit status"
  e2e_expect_err "the last quality run exited 0 but its output showed every test was skipped; no passing run this session"
  e2e_expect_err_lacks "the last quality run exited 0; no passing run"
fi

if _want qtr-on-executed; then
  _flow_test_begin "qtr-on-executed"
  _q_setup qtr-on-executed "site on, tests executed, stub answers executed at 0.99: one request, the run stays passing with no output_check"
  e2e_stub_start a "{\"body\":$(_reply executed 0.99)}"
  _q_settings on a
  _q_run "$(_q_payload "pytest" "$PASS_OUT")"
  _q_requests a 1
  e2e_expect_equal "null" "$(jq -c '.output_check' <<<"$(_q_last)")" "the entry's output_check"
  _q_status
  e2e_expect_no_line "LAST_PASSING_RUN=none"
  e2e_expect_no_out "LAST_RUN_OUTPUT_CHECK"
fi

if _want qtr-on-unclear; then
  _flow_test_begin "qtr-on-unclear"
  _q_setup qtr-on-unclear "site on, stub answers unclear at 0.97: only none_ran and all_skipped downgrade, so the run stays passing"
  e2e_stub_start a "{\"body\":$(_reply unclear 0.97)}"
  _q_settings on a
  _q_run "$(_q_payload "npm test" "$NONE_RAN_OUT")"
  _q_requests a 1
  e2e_expect_equal "null" "$(jq -c '.output_check' <<<"$(_q_last)")" "the entry's output_check"
  _q_status
  e2e_expect_no_line "LAST_PASSING_RUN=none"
fi

if _want qtr-on-below-threshold; then
  _flow_test_begin "qtr-on-below-threshold"
  _q_setup qtr-on-below-threshold "site on, stub answers none_ran at confidence 0.6, below the shipped threshold 0.9: the run stays passing and the record says below-threshold"
  e2e_stub_start a "{\"body\":$LOW_NONE_RAN}"
  _q_settings on a
  _q_run "$(_q_payload "pytest" "$NONE_RAN_OUT")"
  _q_requests a 1
  e2e_expect_equal "null" "$(jq -c '.output_check' <<<"$(_q_last)")" "the entry's output_check"
  e2e_expect_equal "below-threshold on" "$(jq -r '"\(.result) \(.mode)"' "$Q_RECORDS" 2>/dev/null)" "the record's result and mode"
  _q_status
  e2e_expect_no_line "LAST_PASSING_RUN=none"
fi

# ----------------------------------------------------------------- shadow

if _want qtr-shadow; then
  _flow_test_begin "qtr-shadow"
  _q_setup qtr-shadow "shadow, stub answers none_ran: one request, the entry stays passing, the record has mode shadow, current pass, the tool call's ref, and the same state sha256 as the entry (Q7, Q9); a tool_use_id the ref cannot carry falls back to the session"
  e2e_stub_start a "{\"body\":$(_reply none_ran 0.98)}"
  _q_settings shadow a
  _q_run "$(_q_payload "pytest" "$NONE_RAN_OUT" 0 PostToolUse toolu_01shadow)"
  e2e_expect_equal "0" "$E2E_RC" "hook exit status"
  e2e_expect_equal "" "$E2E_OUT" "hook stdout"
  _q_requests a 1
  e2e_expect_equal "null" "$(jq -c '.output_check' <<<"$(_q_last)")" "the entry's output_check"
  e2e_expect_equal "shadow pass answered quality-run:toolu_01shadow outcome quality.tests-ran" \
    "$(jq -r '"\(.mode) \(.current) \(.result) \(.ref) \(.question) \(.site)"' "$Q_RECORDS" 2>/dev/null)" "the record"
  e2e_expect_equal "$(jq -r '.state_sha256' "$Q_RECORDS" 2>/dev/null)" "$(jq -r '.s1_state_sha256' <<<"$(_q_last)")" "the entry's s1_state_sha256 (equal to the record's state_sha256)"
  _q_status
  e2e_expect_no_line "LAST_PASSING_RUN=none"
  e2e_expect_no_out "LAST_RUN_OUTPUT_CHECK"
  # A tool_use_id holding a space is not a valid ref: the session names it.
  _q_run "$(_q_payload "pytest" "$NONE_RAN_OUT" 0 PostToolUse "bad id")"
  _q_requests a 2
  e2e_expect_equal "quality-run:session:sess-qtr-shadow" "$(tail -n 1 "$Q_RECORDS" | jq -r '.ref')" "the fallback ref"
fi

# ----------------------------------------------------------------- off and no answer

# _q_base_line <payload> — the ledger line the hook at BASE_COMMIT writes for
# the payload, in a session of its own.
_q_base_line() {
  local base_sid="$Q_SID-base" p
  p=$(jq -c --arg s "$base_sid" '.session_id = $s' <<<"$1")
  e2e_run_hook "$HOOK" "$p" >/dev/null
  tail -n 1 "$E2E_HOME/.claude/flow-state/sessions/$base_sid/quality-ledger.jsonl" 2>/dev/null
}

_q_use_base_hook() {
  local old
  old=$(git -C "$REPO_ROOT" show "$BASE_COMMIT:plugins/flow/$HOOK" 2>/dev/null)
  if [ -z "$old" ]; then
    _flow_assert_fail "$E2E_NAME: cannot read the hook at $BASE_COMMIT"
    return 1
  fi
  e2e_plugin_copy "$HOOK" "$old"
}

if _want qtr-off-identical; then
  _flow_test_begin "qtr-off-identical"
  _q_setup qtr-off-identical "a provider configured and its stub running, the site off: no request, no record, and the ledger line equals the one the hook wrote before this decision point existed (Q4), apart from the exit code, which is now 0 where that hook wrote null (Q10)"
  e2e_stub_start a "{\"body\":$(_reply none_ran 0.98)}"
  _q_settings off a
  P=$(_q_payload "pytest -q" "$NONE_RAN_OUT")
  _q_use_base_hook && BASE=$(_q_base_line "$P")
  E2E_ACTIVE_PLUGIN="$E2E_PLUGIN_DIR"
  _q_run "$P"
  _q_requests a 0
  e2e_expect_equal "$(jq -c 'del(.at, .exit_code)' <<<"$BASE")" "$(jq -c 'del(.at, .exit_code)' <<<"$(_q_last)")" "the ledger line without its time and exit code, byte for byte"
  e2e_expect_equal "null 0" "$(_q_exit_pair "$BASE" "$(_q_last)")" "exit code before this change and now (Q10)"
  e2e_expect_equal "no" "$([ -e "$Q_RECORDS" ] && echo yes || echo no)" "a records file exists"
fi

if _want qtr-provider-none; then
  _flow_test_begin "qtr-provider-none"
  _q_setup qtr-provider-none "the site on but provider none, with a baseUrl present: no request, and the entry carries no state digest (nothing was prepared for System One), and it is the one written before apart from the exit code (0 now, null before)"
  e2e_stub_start a "{\"body\":$(_reply none_ran 0.98)}"
  _q_settings on a '{"provider":"none"}'
  P=$(_q_payload "pytest" "$NONE_RAN_OUT")
  _q_use_base_hook && BASE=$(_q_base_line "$P")
  E2E_ACTIVE_PLUGIN="$E2E_PLUGIN_DIR"
  _q_run "$P"
  _q_requests a 0
  e2e_expect_equal "null" "$(jq -c '.s1_state_sha256' <<<"$(_q_last)")" "no state digest: nothing was prepared for System One"
  e2e_expect_equal "$(_q_norm "$BASE")" "$(_q_norm "$(_q_last)")" "the ledger line without time, state digest and exit code"
  e2e_expect_equal "null 0" "$(_q_exit_pair "$BASE" "$(_q_last)")" "exit code before this change and now"
  _q_status
  e2e_expect_no_line "LAST_PASSING_RUN=none"
fi

if _want qtr-no-answer; then
  _flow_test_begin "qtr-no-answer"
  _q_setup qtr-no-answer "site on, the stub answers HTTP 500, then a body that is not JSON, then too late (timeoutMs 1000, delay 12000 ms): one request each, the entry is the one written before apart from the state digest and the exit code (0 now, null before), and the hook returns within 8 s, on its own timer rather than the stub's reply"
  P=$(_q_payload "pytest" "$NONE_RAN_OUT")
  _q_use_base_hook && BASE=$(_q_base_line "$P")
  E2E_ACTIVE_PLUGIN="$E2E_PLUGIN_DIR"
  n=0
  for cfg in '{"status":500,"body":{"detail":"boom"}}' '{"body":"not json"}' "{\"delay_ms\":12000,\"body\":$(_reply none_ran 0.98)}"; do
    n=$((n + 1))
    : > "$Q_LEDGER"
    e2e_stub_start "a$n" "$cfg"
    _q_settings on "a$n" '{"timeoutMs":1000}'
    T0=$(python3 -c 'import time; print(int(time.time() * 1000))')
    _q_run "$P"
    T1=$(python3 -c 'import time; print(int(time.time() * 1000))')
    _q_requests "a$n" 1
    e2e_expect_equal "$(_q_norm "$BASE")" "$(_q_norm "$(_q_last)")" "the ledger line without time, state digest and exit code, stub $cfg"
    e2e_expect_equal "null 0" "$(_q_exit_pair "$BASE" "$(_q_last)")" "exit code before this change and now, stub $cfg"
    e2e_expect_equal "true" "$([ $((T1 - T0)) -lt 8000 ] && echo true || echo false)" "the hook returned within 8000 ms"
    _e2e_stop_stubs
  done
fi

# ----------------------------------------------------------------- direction and pre-filter

if _want qtr-failure-never-upgraded; then
  _flow_test_begin "qtr-failure-never-upgraded"
  _q_setup qtr-failure-never-upgraded "site on, a PostToolUseFailure payload for pytest (Exit code 1), stub ready to answer executed: no request, the entry is failed and not passing (Q3)"
  e2e_stub_start a "{\"body\":$(_reply executed 0.99)}"
  _q_settings on a
  _q_run "$(_q_payload "pytest" "1 failed" 1 PostToolUseFailure)"
  _q_requests a 0
  e2e_expect_equal "1 true null null" "$(jq -r '"\(.exit_code) \(.failed) \(.output_check) \(.s1_state_sha256)"' <<<"$(_q_last)")" "exit code, failed, output_check, state digest"
  _q_status
  e2e_expect_line "LAST_PASSING_RUN=none"
  e2e_expect_line "LAST_RUN_FAILED=true"
fi

if _want qtr-prefilter; then
  _flow_test_begin "qtr-prefilter"
  _q_setup qtr-prefilter "site shadow with a provider: a non-test command, a lint command, a masked test run, an interrupted test run, a numeric non-zero exit_code on PostToolUse, a run moved to the background (backgroundTaskId), one that timed out (timedOutAfterMs), a pipeline whose non-zero exit Claude Code reports as informational (returnCodeInterpretation), a payload that does not name its event as PostToolUse, a result with a key Claude Code is not known to send for a finished call, a call with run_in_background true and no backgroundTaskId, and a repository pattern '.' make no request, and their entries carry no state digest (Q2, Q10)"
  e2e_stub_start a "{\"body\":$(_reply none_ran 0.98)}"
  _q_settings shadow a
  mkdir -p "$E2E_REPO/.claude"
  printf '{"testing":{"qualityCommandPatterns":["."]}}\n' > "$E2E_REPO/.claude/settings.flow.json"
  _q_run "$(_q_payload "ls -la" "a b" 0 PostToolUse toolu_ls)"
  _q_run "$(_q_payload "ruff check ." "All checks passed!" 0 PostToolUse toolu_ruff)"
  _q_run "$(_q_payload "pytest || true" "$NONE_RAN_OUT" 0 PostToolUse toolu_m)"
  _q_run "$(jq -c '.tool_response.interrupted = true | .tool_use_id = "toolu_i"' <<<"$(_q_payload "pytest" "$NONE_RAN_OUT")")"
  _q_run "$(jq -c '.tool_response.exit_code = 2 | .tool_use_id = "toolu_2"' <<<"$(_q_payload "pytest" "$NONE_RAN_OUT")")"
  _q_run "$(jq -c '.tool_response.backgroundTaskId = "bash_1" | .tool_use_id = "toolu_bg"' <<<"$(_q_payload "pytest" "")")"
  _q_run "$(jq -c '.tool_response.timedOutAfterMs = 120000 | .tool_use_id = "toolu_to"' <<<"$(_q_payload "pytest" "$NONE_RAN_OUT")")"
  _q_run "$(jq -c '.tool_response.returnCodeInterpretation = "No matches found" | .tool_use_id = "toolu_rc"' <<<"$(_q_payload "pytest -q | grep FAILED" "")")"
  _q_run "$(jq -c 'del(.hook_event_name) | .tool_use_id = "toolu_noevent"' <<<"$(_q_payload "pytest" "$NONE_RAN_OUT")")"
  _q_run "$(jq -c '.tool_response.futureFailureFlag = true | .tool_use_id = "toolu_unknown"' <<<"$(_q_payload "pytest" "$NONE_RAN_OUT")")"
  _q_run "$(jq -c '.tool_input.run_in_background = true | .tool_use_id = "toolu_rib"' <<<"$(_q_payload "pytest" "")")"
  _q_requests a 0
  e2e_expect_equal "project lint test test test test test test test test test" "$(jq -r '.kind' "$Q_LEDGER" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')" "the kinds recorded (ls matched the repository pattern)"
  e2e_expect_equal "0 0 null 130 2 null null null null null null" "$(jq -r '.exit_code' "$Q_LEDGER" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')" "the exit codes recorded"
  e2e_expect_equal "0" "$(jq -s '[.[] | select(has("s1_state_sha256") or has("output_check"))] | length' "$Q_LEDGER" 2>/dev/null)" "entries with a state digest or output_check"
fi

if _want qtr-call-status; then
  _flow_test_begin "qtr-call-status"
  _q_setup qtr-call-status "site shadow with a provider, each payload in the shape Claude Code sends for a call that finished, with a failing summary in stdout: a test run piped to tail, to a grep that matches, to tee, followed by '; echo done', by '&& echo ok', by '|| echo x', put in the background with '&', or after a heredoc are recorded with exit code null, make no request, and leave no passing run; 'cd x && pytest', 'FOO=1 pytest', 'pytest -q 2>&1' and 'set -euo pipefail' on its own line before 'pytest' keep exit code 0 and are asked about (Q12)"
  e2e_stub_start a "{\"body\":$(_reply executed 0.98)}"
  _q_settings shadow a
  mkdir -p "$E2E_REPO/tests"
  FAIL_OUT=$'TOTAL pass=9 fail=1\nFAILED files: x.test.sh\n'
  _q_run "$(_q_payload "bash plugins/flow/tests/run.sh x.test.sh 2>&1 | tail -20" "$FAIL_OUT" 0 PostToolUse toolu_tail)"
  _q_run "$(_q_payload "pytest -q | grep -E \"FAILED|passed\"" "FAILED tests/test_a.py::test_x" 0 PostToolUse toolu_grep)"
  _q_run "$(_q_payload "go test ./... 2>&1 | tee test.log" "--- FAIL: TestX" 0 PostToolUse toolu_tee)"
  _q_run "$(_q_payload "cargo test; echo done" $'test result: FAILED. 1 failed\ndone' 0 PostToolUse toolu_semi)"
  _q_run "$(_q_payload "pytest && echo ok" "$PASS_OUT" 0 PostToolUse toolu_and)"
  _q_run "$(_q_payload "pytest || echo x" $'1 failed\nx' 0 PostToolUse toolu_or)"
  _q_run "$(_q_payload "pytest &" "" 0 PostToolUse toolu_bg2)"
  _q_run "$(_q_payload $'cat > conftest.py <<\'EOF\'\nimport os\nEOF\npytest' "$PASS_OUT" 0 PostToolUse toolu_hd)"
  _q_requests a 0
  e2e_expect_equal "null null null null null null null null" "$(jq -r '.exit_code' "$Q_LEDGER" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')" "the exit codes recorded"
  _q_status
  e2e_expect_line "LAST_PASSING_RUN=none"
  _q_run "$(_q_payload "cd tests && pytest" "$PASS_OUT" 0 PostToolUse toolu_cd)"
  _q_run "$(_q_payload "FOO=1 pytest" "$PASS_OUT" 0 PostToolUse toolu_env)"
  _q_run "$(_q_payload "pytest -q 2>&1" "$PASS_OUT" 0 PostToolUse toolu_redir)"
  _q_run "$(_q_payload $'set -euo pipefail\npytest' "$PASS_OUT" 0 PostToolUse toolu_set)"
  _q_requests a 4
  e2e_expect_equal "0 0 0 0" "$(tail -n 4 "$Q_LEDGER" | jq -r '.exit_code' | tr '\n' ' ' | sed 's/ $//')" "the exit codes of the last four runs"
  _q_status
  e2e_expect_no_line "LAST_PASSING_RUN=none"
fi

if _want qtr-tail-kept; then
  _flow_test_begin "qtr-tail-kept"
  _q_setup qtr-tail-kept "site shadow, stateTokenCap 3000 (12,000 characters): a 1,000-line output of 58-character lines whose only summary, 32 characters, is its last line, followed by a newline, so the 200 tail lines alone exceed the cap and the client must shorten every long line; the request's output_tail still ends with that line, and output_head starts with the first (Q1). 1,000 lines rather than more: the harness writes every payload into the artifact, and bash 3.2 masks a payload of several hundred KB for over a minute, past the stub's lifetime"
  e2e_stub_start a "{\"body\":$(_reply none_ran 0.98)}"
  _q_settings shadow a '{"stateTokenCap":3000}'
  BIG=$(python3 -c 'print("\n".join("tests/test_%04d.py::case_with_a_long_name SKIPPED (marker)" % i for i in range(999)) + "\n===== 999 skipped in 1.00s =====")'; printf x)
  BIG="${BIG%x}"
  _q_run "$(_q_payload "pytest -rs" "$BIG")"
  _q_requests a 1
  e2e_expect_equal "===== 999 skipped in 1.00s =====" "$(jq -r '.body.state.output_tail[-1]' "$(e2e_stub_log a)")" "the last line of output_tail sent"
  e2e_expect_equal "true" "$(jq -r '.body.state.output_tail[0] | length < 58' "$(e2e_stub_log a)")" "the client shortened the lines (the cap was reached)"
  e2e_expect_equal "200 40" "$(jq -r '.body.state | "\(.output_tail | length) \(.output_head | length)"' "$(e2e_stub_log a)")" "lines sent in output_tail and output_head"
  e2e_expect_equal "true" "$(jq -r '.body.state.output_head[0] | startswith("tests/test_0000")' "$(e2e_stub_log a)")" "output_head starts with the first line"
fi

if _want qtr-repo-settings; then
  _flow_test_begin "qtr-repo-settings"
  _q_setup qtr-repo-settings "the user configures the provider and leaves the site unset; the repository sets it on, and also a baseUrl of its own: no request to either stub and no state digest (Q8). The repository sets shadow: still no request and no digest, since a repository can only lower the user's mode. The user sets shadow and the repository off: no request. Both set shadow: the request goes to the user's stub, never the repository's"
  e2e_stub_start a "{\"body\":$(_reply none_ran 0.98)}"
  e2e_stub_start b "{\"body\":$(_reply none_ran 0.98)}"
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne: {provider: "custom", baseUrl: $u}}')"
  mkdir -p "$E2E_REPO/.claude"
  jq -nc --arg u "$(e2e_stub_url b)" --arg s "$SITE" '{systemOne: {baseUrl: $u, uses: {($s): "on"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  _q_run "$(_q_payload "pytest" "$NONE_RAN_OUT")"
  _q_requests a 0
  _q_requests b 0
  e2e_expect_equal "null null" "$(jq -r '"\(.s1_state_sha256) \(.output_check)"' <<<"$(_q_last)")" "state digest and output_check"
  jq -nc --arg u "$(e2e_stub_url b)" --arg s "$SITE" '{systemOne: {baseUrl: $u, uses: {($s): "shadow"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  _q_run "$(_q_payload "pytest" "$NONE_RAN_OUT" 0 PostToolUse toolu_02)"
  _q_requests a 0
  _q_requests b 0
  e2e_expect_equal "null null" "$(jq -r '"\(.s1_state_sha256) \(.output_check)"' <<<"$(_q_last)")" "state digest and output_check, repository shadow"
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url a)" --arg s "$SITE" '{systemOne: {provider: "custom", baseUrl: $u, uses: {($s): "shadow"}}}')"
  jq -nc --arg u "$(e2e_stub_url b)" --arg s "$SITE" '{systemOne: {baseUrl: $u, uses: {($s): "off"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  _q_run "$(_q_payload "pytest" "$NONE_RAN_OUT" 0 PostToolUse toolu_03)"
  _q_requests a 0
  _q_requests b 0
  e2e_expect_equal "null null" "$(jq -r '"\(.s1_state_sha256) \(.output_check)"' <<<"$(_q_last)")" "state digest and output_check, user shadow and repository off"
  jq -nc --arg u "$(e2e_stub_url b)" --arg s "$SITE" '{systemOne: {baseUrl: $u, uses: {($s): "shadow"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  _q_run "$(_q_payload "pytest" "$NONE_RAN_OUT" 0 PostToolUse toolu_04)"
  _q_requests a 1
  _q_requests b 0
  e2e_expect_equal "true null" "$(jq -r '"\(.s1_state_sha256 | type == "string") \(.output_check)"' <<<"$(_q_last)")" "state digest and output_check, both shadow"
fi

# ----------------------------------------------------------------- reader

if _want qtr-ledger-malformed-output-check; then
  _flow_test_begin "qtr-ledger-malformed-output-check"
  _q_setup qtr-ledger-malformed-output-check "hand-written ledger entries whose output_check is a string, an unknown verdict, an object without a verdict, or null: status equals the status of the same ledger without the field (Q5)"
  mkdir -p "$(dirname "$Q_LEDGER")"
  for oc in '"none_ran"' '{"verdict":"maybe"}' '{"site":"quality.tests-ran"}' 'null' '{"verdict":["none_ran"]}'; do
    printf '{"at":"2026-10-01T00:00:00Z","type":"file_change","tool":"Write","path":"%s/a.py"}\n' "$E2E_REPO" > "$Q_LEDGER"
    printf '{"at":"2026-10-01T00:00:01Z","type":"quality_run","command":"pytest","exit_code":0,"kind":"test","masked":false,"failed":false,"worktree_digest":null}\n' >> "$Q_LEDGER"
    _q_status
    PLAIN="$E2E_OUT"
    printf '{"at":"2026-10-01T00:00:00Z","type":"file_change","tool":"Write","path":"%s/a.py"}\n' "$E2E_REPO" > "$Q_LEDGER"
    printf '{"at":"2026-10-01T00:00:01Z","type":"quality_run","command":"pytest","exit_code":0,"kind":"test","masked":false,"failed":false,"worktree_digest":null,"output_check":%s}\n' "$oc" >> "$Q_LEDGER"
    _q_status
    e2e_expect_equal "$PLAIN" "$E2E_OUT" "status with output_check $oc"
    e2e_expect_equal "0" "$E2E_RC" "status exit with output_check $oc"
  done
  e2e_expect_line "LAST_PASSING_RUN=2026-10-01T00:00:01Z"
fi

# ----------------------------------------------------------------- real payload and stopping

if _want qtr-real-payload-gate; then
  _flow_test_begin "qtr-real-payload-gate"
  _q_setup qtr-real-payload-gate "no System One settings: a file edit, then a passing pytest run whose payload has the keys Claude Code sends (no exit_code), then TaskCompleted: the entry has exit code 0, status names a passing run, and the gate lets the task complete (Q10)"
  printf 'x = 1\n' > "$E2E_REPO/app.py"
  e2e_run_hook hooks/scripts/log-file-changes.sh "$(jq -nc --arg sid "$Q_SID" --arg cwd "$E2E_REPO" --arg p "$E2E_REPO/app.py" \
    '{session_id: $sid, cwd: $cwd, hook_event_name: "PostToolUse", tool_name: "Write", tool_input: {file_path: $p}}')"
  _q_run "$(_q_payload "pytest" "$PASS_OUT")"
  e2e_expect_equal "0 false false null" "$(jq -r '"\(.exit_code) \(.masked) \(.failed) \(.s1_state_sha256)"' <<<"$(_q_last)")" "exit code, masked, failed, state digest"
  _q_status
  e2e_expect_no_line "LAST_PASSING_RUN=none"
  e2e_expect_line "LAST_RUN_EXIT=0"
  e2e_run_hook hooks/scripts/verify-task-completion.sh "$(jq -nc --arg sid "$Q_SID" --arg cwd "$E2E_REPO" '{session_id: $sid, cwd: $cwd, task_id: "1", task_subject: "ship it"}')"
  e2e_expect_equal "0" "$E2E_RC" "gate exit status"
fi

if _want qtr-stopped-while-waiting; then
  _flow_test_begin "qtr-stopped-while-waiting"
  _q_setup qtr-stopped-while-waiting "site shadow, the stub holds its reply 12 s, timeoutMs 3000: the hook is sent SIGTERM once the stub has the request; it ends with status 0, the file holding the test output is no longer in TMPDIR, and the run is still recorded, without the System One fields (Q11)"
  e2e_stub_start a "{\"delay_ms\":12000,\"body\":$(_reply none_ran 0.98)}"
  _q_settings shadow a '{"timeoutMs":3000}'
  mkdir -p "$E2E_DIR/tmp"
  _q_payload "pytest" "$NONE_RAN_OUT" > "$E2E_DIR/stop-payload.json"
  {
    printf 'code: %s\n' "$HOOK"
    printf 'code sha256: %s\n' "$(_e2e_sha256 "$E2E_ACTIVE_PLUGIN/$HOOK")"
    printf 'payload: %s\n' "$(cat "$E2E_DIR/stop-payload.json")"
    printf 'environment: TMPDIR=<scenario>/tmp\n'
  } | _e2e_art
  # Only the hook gets the signal, as when Claude Code stops a hook; the
  # client it started runs to its own timeout.
  # shellcheck disable=SC2016  # expanded by the inner bash
  _e2e_exec env TMPDIR="$E2E_DIR/tmp" bash -c '
    "$1" < "$2" & pid=$!
    i=0
    while [ ! -s "$3" ] && [ "$i" -lt 150 ]; do sleep 0.1; i=$((i + 1)); done
    kill -TERM "$pid"
    wait "$pid"
    echo "hook ended with status $?"' _ "$E2E_ACTIVE_PLUGIN/$HOOK" "$E2E_DIR/stop-payload.json" "$(e2e_stub_log a)"
  _q_requests a 1
  e2e_expect_out "hook ended with status 0"
  e2e_expect_equal "" "$(find "$E2E_DIR/tmp" -name 'flow-s1-quality.*' 2>/dev/null)" "state files left in TMPDIR"
  e2e_expect_equal "pytest 0 test null null" "$(jq -r '"\(.command) \(.exit_code) \(.kind) \(.s1_state_sha256) \(.output_check)"' <<<"$(_q_last)")" "the stopped run's ledger entry"
fi

if _want qtr-stale-state-file; then
  _flow_test_begin "qtr-stale-state-file"
  _q_setup qtr-stale-state-file "site shadow: a state file left in TMPDIR by a hook that was killed, last changed in 2020, is removed when the next run is asked about; one changed now, which another hook may still be using, is kept (Q11)"
  e2e_stub_start a "{\"body\":$(_reply executed 0.98)}"
  _q_settings shadow a
  mkdir -p "$E2E_DIR/tmp"
  printf 'old output\n' > "$E2E_DIR/tmp/flow-s1-quality.OLD123"
  touch -t 202001010000 "$E2E_DIR/tmp/flow-s1-quality.OLD123"
  printf 'new output\n' > "$E2E_DIR/tmp/flow-s1-quality.NEW123"
  e2e_run_hook TMPDIR="$E2E_DIR/tmp" "$HOOK" "$(_q_payload "pytest" "$PASS_OUT")"
  _q_requests a 1
  e2e_expect_equal "flow-s1-quality.NEW123" "$(cd "$E2E_DIR/tmp" && ls)" "state files left in TMPDIR"
fi

if _want qtr-secret-masked; then
  _flow_test_begin "qtr-secret-masked"
  _q_setup qtr-secret-masked "site shadow: 'TOKEN=secret123 pytest', 'cd sub && API_KEY=abc987 CI=1 pytest -q' and a run after 'set -e' are asked about, and the command sent has each leading assignment's value replaced by ***; 'cd a=b && pytest' is sent as written. Runs after a set line that turns on xtrace or verbose ('set -x', 'set -v', 'set -euxo pipefail', 'set -o xtrace'), whose trace of the command line Claude Code returns in the output, are not asked about. No value reaches the stub (Q13)"
  e2e_stub_start a "{\"body\":$(_reply executed 0.98)}"
  _q_settings shadow a
  mkdir -p "$E2E_REPO/sub" "$E2E_REPO/a=b"
  _q_run "$(_q_payload "TOKEN=secret123 pytest" "$PASS_OUT" 0 PostToolUse toolu_s1)"
  _q_run "$(_q_payload "cd sub && API_KEY=abc987 CI=1 pytest -q" "$PASS_OUT" 0 PostToolUse toolu_s2)"
  _q_run "$(_q_payload $'set -e\nTOKEN=secret123 pytest' "$PASS_OUT" 0 PostToolUse toolu_s3)"
  _q_run "$(_q_payload "cd a=b && pytest" "$PASS_OUT" 0 PostToolUse toolu_s4)"
  _q_requests a 4
  e2e_expect_equal '"TOKEN=*** pytest"|"cd sub && API_KEY=*** CI=*** pytest -q"|"set -e\nTOKEN=*** pytest"|"cd a=b && pytest"' "$(jq -c '.body.state.command' "$(e2e_stub_log a)" | paste -sd'|' -)" "the commands sent"
  # The trace as bash writes it, and as Claude Code returns it: inside stdout,
  # with stderr empty. It is put in stderr as well, so neither field is relied on.
  n=5
  for first in "set -x" "set -v" "set -euxo pipefail" "set -o xtrace"; do
    _q_run "$(_q_payload "$first"$'\nTOKEN=secret123 pytest' $'+ TOKEN=secret123 pytest\n'"$PASS_OUT" 0 PostToolUse "toolu_s$n" '+ TOKEN=secret123 pytest')"
    n=$((n + 1))
  done
  _q_requests a 4
  e2e_expect_equal "0 0 0 0 0 0 0 0" "$(jq -r '.exit_code' "$Q_LEDGER" | paste -sd' ' -)" "every run is recorded with exit code 0"
  e2e_expect_equal "0" "$(grep -c -e secret123 -e abc987 "$(e2e_stub_log a)")" "requests holding either value"
  e2e_expect_equal "TOKEN=secret123 pytest" "$(head -n 1 "$Q_LEDGER" | jq -r '.command')" "the local ledger keeps the command as run"
fi

if _want qtr-other-repo; then
  _flow_test_begin "qtr-other-repo"
  _q_setup qtr-other-repo "site shadow in the session's repository: 'cd <another repository> && pytest' (whose settings set the site off), and 'cd missing && pytest' into a directory that does not exist, are not asked about; 'cd sub && pytest' inside the session's repository is (Q14)"
  e2e_stub_start a "{\"body\":$(_reply executed 0.98)}"
  _q_settings shadow a
  OTHER="$E2E_DIR/other"
  mkdir -p "$OTHER/.claude" "$E2E_REPO/sub"
  git -C "$OTHER" init -q
  jq -nc --arg s "$SITE" '{systemOne: {uses: {($s): "off"}}}' > "$OTHER/.claude/settings.flow.json"
  _q_run "$(_q_payload "cd $OTHER && pytest" "$PASS_OUT" 0 PostToolUse toolu_o1)"
  _q_run "$(_q_payload "cd missing && pytest" "$PASS_OUT" 0 PostToolUse toolu_o2)"
  _q_requests a 0
  e2e_expect_equal "0 0" "$(jq -r '.exit_code' "$Q_LEDGER" | paste -sd' ' -)" "both runs are recorded with exit code 0"
  _q_run "$(_q_payload "cd sub && pytest" "$PASS_OUT" 0 PostToolUse toolu_o3)"
  _q_requests a 1
fi

if _want qtr-nested-repo; then
  _flow_test_begin "qtr-nested-repo"
  _q_setup qtr-nested-repo "site shadow in the user's settings: 'cd vendor/lib && pytest', where vendor/lib is a git repository nested inside the session's repository whose settings set the site off, is not asked about; neither is a run whose payload cwd is another repository with the site off, while the hook process starts in the session's repository, which sets nothing. With those settings removed, the same two runs are asked about (Q14)"
  e2e_stub_start a "{\"body\":$(_reply executed 0.98)}"
  _q_settings shadow a
  mkdir -p "$E2E_REPO/vendor/lib/.claude"
  git -C "$E2E_REPO/vendor/lib" init -q
  jq -nc --arg s "$SITE" '{systemOne: {uses: {($s): "off"}}}' > "$E2E_REPO/vendor/lib/.claude/settings.flow.json"
  _q_run "$(_q_payload "cd vendor/lib && pytest" "$PASS_OUT" 0 PostToolUse toolu_n1)"
  _q_requests a 0
  OTHER="$E2E_DIR/other"
  mkdir -p "$OTHER/.claude"
  git -C "$OTHER" init -q
  jq -nc --arg s "$SITE" '{systemOne: {uses: {($s): "off"}}}' > "$OTHER/.claude/settings.flow.json"
  # A python3 ahead of the real one notes each start of the client's Python
  # half, which the client reaches only after the hook's own mode check.
  printf '#!/usr/bin/env bash\ncase " $* " in *_flow_s1.py*) printf "client\\n" >> "%s/client-starts" ;; esac\nexec %q "$@"\n' \
    "$E2E_DIR" "$(command -v python3)" > "$E2E_BIN/python3"
  chmod +x "$E2E_BIN/python3"
  _q_run "$(jq -c --arg cwd "$OTHER" '.cwd = $cwd' <<<"$(_q_payload "pytest" "$PASS_OUT" 0 PostToolUse toolu_n2)")"
  _q_requests a 0
  e2e_expect_equal "0" "$(cat "$E2E_DIR/client-starts" 2>/dev/null | wc -l | tr -d ' ')" "starts of the client's Python half"
  e2e_expect_equal "0 0" "$(jq -r '.exit_code' "$Q_LEDGER" | paste -sd' ' -)" "both runs are recorded with exit code 0"
  # Not even the client starts: it would read the same mode and send nothing,
  # but would still write a record, and the entry would carry its digest.
  e2e_expect_equal "null null" "$(jq -r '.s1_state_sha256' "$Q_LEDGER" | paste -sd' ' -)" "state digests of both entries"
  e2e_expect_equal "absent" "$([ -e "$Q_RECORDS" ] && echo present || echo absent)" "the records file"
  rm "$E2E_REPO/vendor/lib/.claude/settings.flow.json" "$OTHER/.claude/settings.flow.json"
  _q_run "$(jq -c --arg cwd "$OTHER" '.cwd = $cwd' <<<"$(_q_payload "pytest" "$PASS_OUT" 0 PostToolUse toolu_n3)")"
  rm "$E2E_BIN/python3"
  _q_requests a 1
  e2e_expect_equal "1" "$(cat "$E2E_DIR/client-starts" 2>/dev/null | wc -l | tr -d ' ')" "starts of the client's Python half, after the run that is asked about"
fi

if _want qtr-no-record-no-digest; then
  _flow_test_begin "qtr-no-record-no-digest"
  _q_setup qtr-no-record-no-digest "site on, the stub answers none_ran at 0.98, but the records file cannot be written (a directory stands at its path): the run is downgraded, and its entry carries no s1_state_sha256, since no record holds that state"
  e2e_stub_start a "{\"body\":$(_reply none_ran 0.98)}"
  _q_settings on a
  mkdir -p "$Q_RECORDS"
  _q_run "$(_q_payload "pytest" "$NONE_RAN_OUT")"
  _q_requests a 1
  e2e_expect_equal "null none_ran" "$(jq -r '"\(.s1_state_sha256) \(.output_check.verdict)"' <<<"$(_q_last)")" "state digest and verdict"
fi

if _want qtr-client-stopped-no-digest; then
  _flow_test_begin "qtr-client-stopped-no-digest"
  _q_setup qtr-client-stopped-no-digest "site shadow, and a records file that already holds a record from an earlier call; the user's model setting is longer than 4096 characters, so the client stops before it sends or writes anything: no request, the records file keeps its one line, and the entry carries no s1_state_sha256"
  e2e_stub_start a "{\"body\":$(_reply executed 0.98)}"
  _q_settings shadow a "$(jq -nc '{model: ("m" * 5000)}')"
  mkdir -p "${Q_RECORDS%/*}"
  jq -nc '{site: "quality.tests-ran", ref: "quality-run:toolu_earlier", state_sha256: ("0" * 64), result: "answered"}' > "$Q_RECORDS"
  _q_run "$(_q_payload "pytest" "$PASS_OUT")"
  _q_requests a 0
  e2e_expect_equal "1" "$(wc -l < "$Q_RECORDS" | tr -d ' ')" "lines in the records file"
  e2e_expect_equal "0 null null" "$(jq -r '"\(.exit_code) \(.s1_state_sha256) \(.output_check)"' <<<"$(_q_last)")" "exit code, state digest and output_check"
fi

if _want qtr-timeout-clamp; then
  _flow_test_begin "qtr-timeout-clamp"
  _q_setup qtr-timeout-clamp "site on, timeoutMs 60000, which the client clamps to 30000, and a stub that holds its reply 40 s: the hook returns after about 30 s, within 38 s, and the run is recorded as passing, with a record saying timeout"
  e2e_stub_start a "{\"delay_ms\":40000,\"body\":$(_reply none_ran 0.98)}"
  _q_settings on a '{"timeoutMs":60000}'
  T0=$(python3 -c 'import time; print(int(time.time() * 1000))')
  _q_run "$(_q_payload "pytest" "$NONE_RAN_OUT")"
  T1=$(python3 -c 'import time; print(int(time.time() * 1000))')
  _q_requests a 1
  e2e_expect_equal "true" "$([ $((T1 - T0)) -ge 29000 ] && [ $((T1 - T0)) -lt 38000 ] && echo true || echo false)" "the hook returned between 29000 and 38000 ms"
  e2e_expect_equal "0 null" "$(jq -r '"\(.exit_code) \(.output_check)"' <<<"$(_q_last)")" "exit code and output_check"
  e2e_expect_equal "timeout" "$(jq -r '.result' "$Q_RECORDS" 2>/dev/null)" "the record's result"
fi
