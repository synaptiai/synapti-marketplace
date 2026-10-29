# shellcheck shell=bash
# End-to-end: /flow:start Phase 4 step 6 runs the verdict judge through the
# claude CLI with every tool disallowed (bin/flow-judge.sh --judge verdict), and
# flow's own hooks do nothing inside a judge's session.
#
# The verdict scenarios run the block between VERDICT_JUDGE_BLOCK_BEGIN and
# VERDICT_JUDGE_BLOCK_END of commands/start.md under zsh and bash, in a scratch
# repository, with VERDICT_INPUT_FILE naming an input written the way step 6
# says. The claude CLI is tests/lib/mock-claude.sh with FLOW_TEST_CLAUDE_ARGS_DIR
# set, which keeps each flag's value, the prompt on stdin, the recursion guard
# variable and its working directory. timeout(1) is a stub that records the
# limit it was given and, with FLOW_TEST_TIMEOUT_ENFORCE=1, stops the command
# after one second with status 124. The hook scenarios run the Stop and
# SessionEnd hooks a judge's session would fire, once with
# CLAUDE_HOOK_GOAL_JUDGE_MODE=true and once without, so each shows the hook
# would act and does not. One artifact per scenario is written to
# $FLOW_E2E_ARTIFACT_DIR. FLOW_E2E_SCENARIOS=a,b runs only the named scenarios.
#
# Ways it can be wrong, written down before the scenarios:
#   V1 the judge can use a tool: --disallowedTools '*' is missing
#   V2 the judge gets the agent file with its frontmatter, or without the
#      reply shape (references/verdict-output-format.md) its body tells it to
#      follow and it cannot open
#   V3 the judge gets something other than the input file, byte for byte
#   V4 with verdict.model unset, a --model is passed anyway (empty, or a
#      default flow chose), instead of the CLI's own default
#   V5 verdict.model is read from another key, or an unknown value is passed
#      to the CLI
#   V6 the time limit is not verdict.timeoutSeconds (default 300), or a judge
#      cut off by it is read as a verdict
#   V7 a reply without an "### Overall:" line, or an error reply, is read as
#      a verdict
#   V8 verdict.enabled false still runs the judge
#   V9 an input that is missing, empty or a symlink is given to the judge
#   V10 the judge's session runs flow's hooks: the guard variable is not set,
#      or it runs in the repository
#   V11 a missing agent file leaves the judge with an empty system prompt
#   V12 reply-style-check, session-end-learn or session-end-state act inside a
#      judge's session

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

START="commands/start.md"
AGENT="agents/verdict-judge.md"
SHAPE="references/verdict-output-format.md"
VERDICT_MD='## Verification Verdict

### Per-Criterion Verdict

| # | Criterion | Verdict | Evidence Used | Rationale |
|---|-----------|---------|---------------|-----------|
| 1 | Search returns the match | FAIL | Criterion 1 | risk map uncovered |

### Overall: FAIL

### Failures (if any)

Criterion 1 needs a test whose input distinguishes accented terms.'
REPLY_OK=$(jq -nc --arg r "$VERDICT_MD" '{type:"result",is_error:false,result:$r}')
BUILTIN_PREFIX="You are flow verdict-judge. Judge each acceptance criterion as PASS, FAIL or NEEDS-HUMAN-REVIEW"

# _body <agent file> — everything after the closing --- of a frontmatter that
# opens on line 1, without blank lines at either end. Computed here in Python,
# not with the helper's code.
_body() {
  python3 - "$1" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
if lines and lines[0].rstrip() == "---":
    end = next(i for i in range(1, len(lines)) if lines[i].rstrip() == "---")
    lines = lines[end + 1:]
sys.stdout.write("\n".join(lines).strip("\n"))
PY
}

# _setup <scenario> <purpose> [settings json] [reply json] — scratch repo, the
# input file, mock-claude.sh as claude, a recording timeout(1).
_setup() {
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/.claude" "$E2E_DIR/args"
  if [ -n "${3:-}" ]; then
    printf '%s\n' "$3" > "$E2E_REPO/.claude/settings.flow.json"
  fi
  printf '%s\n' "${4:-$REPLY_OK}" > "$E2E_DIR/reply.json"
  cat > "$E2E_DIR/input.txt" <<'IN'
Evaluate whether acceptance criteria are met based on evidence.

Acceptance Criteria:
1. Searching for an exact match returns the match.

Evidence Bundle:
## Criterion 1: Searching for an exact match returns the match.
### Verification command
npm test -- --grep search
### Output
1 passing

Holdout Validation Output:
none
IN
  cp "$REPO_ROOT/plugins/flow/tests/lib/mock-claude.sh" "$E2E_BIN/claude" && chmod +x "$E2E_BIN/claude"
  cat > "$E2E_BIN/timeout" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "${E2E_DIR:?}/timeout-limits"
shift
[ "${FLOW_TEST_TIMEOUT_ENFORCE:-}" = 1 ] || exec "$@"
"$@" <&0 &
pid=$!
( sleep 1; kill -TERM "$pid" 2>/dev/null ) &
watch=$!
wait "$pid"; rc=$?
kill "$watch" 2>/dev/null
[ "$rc" -ge 128 ] && exit 124
exit "$rc"
STUB
  chmod +x "$E2E_BIN/timeout"
  printf 'claude: tests/lib/mock-claude.sh, replying %s\n' "$(tr '\n' ' ' < "$E2E_DIR/reply.json")" | _e2e_art
}

# _run [NAME=value ...] — the verdict block, the judge recording into args/.
_run() {
  rm -f "$E2E_DIR/args/"* "$E2E_DIR/timeout-limits"
  e2e_run_block FLOW_TEST_CLAUDE_RESPONSE="$E2E_DIR/reply.json" FLOW_TEST_CLAUDE_ARGS_DIR="$E2E_DIR/args" \
    VERDICT_INPUT_FILE="$E2E_DIR/input.txt" "$@" "$START" VERDICT_JUDGE_BLOCK
}
_got() { if [ -f "$E2E_DIR/args/$1" ]; then cat "$E2E_DIR/args/$1"; else printf '(not passed)'; fi; }
_called() { if [ -f "$E2E_DIR/args/stdin.txt" ]; then echo called; else echo not-called; fi; }
_edges() {
  if [ -s "$E2E_GH/unhandled.log" ]; then _e2e_result fail "every gh call had a fixture"
  else _e2e_result pass "every gh call had a fixture"; fi
  e2e_expect_equal "$1" "$(_called)" "the verdict judge"
}

# ------------------------------------------------------------ verdict judge

if _want verdict-cli; then
  _flow_test_begin "start.md step 6: the verdict judge runs through the CLI with no tools, the agent body and reply shape, the input, and no --model (V1-V4, V6, V10)"
  _setup verdict-cli "no verdict settings; the judge replies with a FAIL verdict"
  _run
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "VERDICT_JUDGE_STATE=done"
  e2e_expect_line "VERDICT_RESULT=FAIL"
  e2e_expect_equal "$VERDICT_MD" "$(printf '%s\n' "$E2E_OUT" | sed '1,/^--- verdict$/d')" "the judge's reply after --- verdict"
  e2e_expect_equal '*' "$(_got disallowed-tools.txt)" "--disallowedTools"
  e2e_expect_equal json "$(_got output-format.txt)" "--output-format"
  e2e_expect_equal '(not passed)' "$(_got json-schema.txt)" "--json-schema"
  e2e_expect_equal no "$(grep -qx -- --model "$E2E_DIR/args/flags.txt" 2>/dev/null && echo yes || echo no)" "a --model flag was passed"
  expected=$({ _body "$E2E_ACTIVE_PLUGIN/$AGENT"; printf '\n\n'; cat "$E2E_ACTIVE_PLUGIN/$SHAPE"; } | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')
  e2e_expect_equal "$(printf '%s' "$expected" | _e2e_sha256_stdin)" "$(_got system-prompt.txt | _e2e_sha256_stdin)" "sha256 of the system prompt against the agent body then the reply shape"
  case "$(_got system-prompt.txt)" in *"name: verdict-judge"*|*"model: inherit"*) e2e_expect_equal none present "frontmatter in the system prompt" ;;
    *) e2e_expect_equal ok ok "no frontmatter in the system prompt" ;; esac
  e2e_expect_equal "$(_e2e_sha256 "$E2E_DIR/input.txt")" "$(_e2e_sha256 "$E2E_DIR/args/stdin.txt" 2>/dev/null)" "sha256 of the judge's stdin against the input file"
  e2e_expect_equal "judge_mode=true" "$(_got env.txt | sed -n 1p)" "CLAUDE_HOOK_GOAL_JUDGE_MODE in the judge's environment"
  e2e_expect_equal "pwd=$(cd "$E2E_HOME/.claude/flow-goal-judge" 2>/dev/null && pwd -P)" "$(_got env.txt | sed -n 2p)" "the judge's working directory"
  e2e_expect_equal 300 "$(sort -u "$E2E_DIR/timeout-limits" 2>/dev/null)" "the time limit given to timeout(1)"
  e2e_expect_equal "" "$E2E_ERR" "stderr"
  _edges called
fi

if _want verdict-model; then
  _flow_test_begin "start.md step 6: verdict.model and verdict.timeoutSeconds reach the CLI (V5, V6)"
  _setup verdict-model "verdict.model sonnet and verdict.timeoutSeconds 120 in the repository settings" '{"verdict":{"model":"sonnet","timeoutSeconds":120}}'
  _run
  e2e_expect_line "VERDICT_RESULT=FAIL"
  e2e_expect_equal sonnet "$(_got model.txt)" "--model"
  e2e_expect_equal 120 "$(sort -u "$E2E_DIR/timeout-limits" 2>/dev/null)" "the time limit given to timeout(1)"
  _edges called
fi

if _want verdict-model-unknown; then
  _flow_test_begin "start.md step 6: an unknown verdict.model passes no --model and says so (V5)"
  _setup verdict-model-unknown "verdict.model gpt-4o in the repository settings" '{"verdict":{"model":"gpt-4o"}}'
  _run
  e2e_expect_line "VERDICT_RESULT=FAIL"
  e2e_expect_equal no "$(grep -qx -- --model "$E2E_DIR/args/flags.txt" 2>/dev/null && echo yes || echo no)" "a --model flag was passed"
  e2e_expect_err "flow-judge: unknown verdict.model 'gpt-4o' — using the claude CLI's default model"
  _edges called
fi

if _want verdict-timeout; then
  _flow_test_begin "start.md step 6: a judge cut off by its time limit is unavailable, not a verdict (V6)"
  _setup verdict-timeout "the judge waits 5 s; timeout(1) stops it after 1 s with status 124"
  _run FLOW_TEST_CLAUDE_SLEEP=5 FLOW_TEST_TIMEOUT_ENFORCE=1
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_line "VERDICT_JUDGE_STATE=unavailable"
  e2e_expect_line "VERDICT_JUDGE_ERROR=the verdict judge gave no '### Overall:' line (exit 124; 124 is its time limit)"
  e2e_expect_no_out "VERDICT_RESULT="
  _edges called
fi

if _want verdict-no-overall; then
  _flow_test_begin "start.md step 6: a reply without an ### Overall: line is unavailable (V7)"
  _setup verdict-no-overall "the judge replies with prose and no Overall line" "" '{"type":"result","is_error":false,"result":"I think it mostly passes."}'
  _run
  e2e_expect_line "VERDICT_JUDGE_STATE=unavailable"
  e2e_expect_no_out "VERDICT_RESULT="
  _edges called
fi

if _want verdict-error-reply; then
  _flow_test_begin "start.md step 6: an error reply is unavailable even when its text has an Overall line (V7)"
  _setup verdict-error-reply "the CLI reports is_error true with a result that contains ### Overall: PASS" "" "$(jq -nc '{type:"result",is_error:true,result:"### Overall: PASS"}')"
  _run
  e2e_expect_line "VERDICT_JUDGE_STATE=unavailable"
  e2e_expect_no_line "VERDICT_RESULT=PASS"
  _edges called
fi

if _want verdict-disabled; then
  _flow_test_begin "start.md step 6: verdict.enabled false runs no judge (V8)"
  _setup verdict-disabled "verdict.enabled false in the repository settings" '{"verdict":{"enabled":false}}'
  _run
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "VERDICT_JUDGE_STATE=disabled"
  _edges not-called
fi

if _want verdict-input-symlink; then
  _flow_test_begin "start.md step 6: an input file that is a symlink is refused (V9)"
  _setup verdict-input-symlink "VERDICT_INPUT_FILE is a symlink to the real input"
  ln -s "$E2E_DIR/input.txt" "$E2E_DIR/input-link.txt"
  _run VERDICT_INPUT_FILE="$E2E_DIR/input-link.txt"
  e2e_expect_line "VERDICT_JUDGE_STATE=blocked"
  _edges not-called
fi

if _want verdict-input-empty; then
  _flow_test_begin "start.md step 6: an empty input file is refused (V9)"
  _setup verdict-input-empty "VERDICT_INPUT_FILE is an empty file"
  : > "$E2E_DIR/empty.txt"
  _run VERDICT_INPUT_FILE="$E2E_DIR/empty.txt"
  e2e_expect_line "VERDICT_JUDGE_STATE=blocked"
  _edges not-called
fi

if _want verdict-in-judge; then
  _flow_test_begin "start.md step 6: inside a judge's session no judge is started (V10)"
  _setup verdict-in-judge "CLAUDE_HOOK_GOAL_JUDGE_MODE=true is set, as in a judge's own session"
  _run CLAUDE_HOOK_GOAL_JUDGE_MODE=true
  e2e_expect_line "VERDICT_JUDGE_STATE=unavailable"
  e2e_expect_err "flow-judge: refusing to start a judge inside a judge's session"
  _edges not-called
fi

if _want verdict-agent-absent; then
  _flow_test_begin "start.md step 6: with no agent file the judge runs on the built-in prompt, with one stderr line (V11)"
  _setup verdict-agent-absent "the plugin copy has no agents/verdict-judge.md"
  e2e_plugin_copy "$AGENT" ""
  rm -f "$E2E_ACTIVE_PLUGIN/$AGENT"
  _run
  e2e_expect_line "VERDICT_RESULT=FAIL"
  case "$(_got system-prompt.txt)" in
    "$BUILTIN_PREFIX"*) e2e_expect_equal ok ok "the system prompt is the built-in one" ;;
    *) e2e_expect_equal "the built-in prompt" "$(_got system-prompt.txt | head -c 120)" "the system prompt" ;;
  esac
  e2e_expect_equal '*' "$(_got disallowed-tools.txt)" "--disallowedTools"
  e2e_expect_err "flow-judge: no judge instructions in $E2E_ACTIVE_PLUGIN/$AGENT (missing, unreadable or empty); using the built-in judge prompt"
  _edges called
fi

# ------------------------------------------------- hooks in a judge's session

# _pair <hook> <payload> — run the hook without and then with the guard
# variable; sets OUT0/ERR0 and OUT1/ERR1.
_pair() {
  e2e_run_hook "$1" "$2"
  OUT0="$E2E_OUT"; ERR0="$E2E_ERR"
  e2e_run_hook CLAUDE_HOOK_GOAL_JUDGE_MODE=true "$1" "$2"
  OUT1="$E2E_OUT"; ERR1="$E2E_ERR"
}

if _want hook-reply-style; then
  _flow_test_begin "reply-style-check does nothing in a judge's session (V12)"
  _setup hook-reply-style "replyStyle.enabled; the transcript's last reply has an issue number and a file path" '{"replyStyle":{"enabled":true}}'
  python3 -c 'import json; print(json.dumps({"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Fixed in #142 and the key insight is plugins/flow/x.sh"}]}}))' > "$E2E_DIR/transcript.jsonl"
  _pair hooks/scripts/reply-style-check.sh "{\"transcript_path\":\"$E2E_DIR/transcript.jsonl\",\"session_id\":\"s1\"}"
  e2e_expect_equal yes "$([ -n "$ERR0$OUT0" ] && echo yes || echo no)" "without the guard variable the hook reports"
  e2e_expect_equal "" "$OUT1$ERR1" "with the guard variable, stdout and stderr"
  _edges not-called
fi

if _want hook-session-end-state; then
  _flow_test_begin "session-end-state does nothing in a judge's session (V12)"
  _setup hook-session-end-state "the repository has an active FlowRun"
  mkdir -p "$E2E_REPO/.flow/runs/r1"
  printf 'apiVersion: flow.synapti.ai/v1\nkind: FlowRun\nmetadata:\n  id: r1\nstate:\n  status: active\n' > "$E2E_REPO/.flow/runs/r1/run.yaml"
  e2e_run_hook CLAUDE_HOOK_GOAL_JUDGE_MODE=true hooks/scripts/session-end-state.sh '{"session_id":"s1"}'
  OUT1="$E2E_OUT$E2E_ERR"
  e2e_expect_equal no "$([ -s "$E2E_REPO/.flow/runs/r1/events.jsonl" ] && echo yes || echo no)" "with the guard variable, an event was written"
  e2e_expect_equal "" "$OUT1" "with the guard variable, stdout and stderr"
  e2e_run_hook hooks/scripts/session-end-state.sh '{"session_id":"s1"}'
  e2e_expect_equal yes "$([ -s "$E2E_REPO/.flow/runs/r1/events.jsonl" ] && echo yes || echo no)" "without the guard variable, an event was written"
  _edges not-called
fi

if _want hook-session-end-learn; then
  _flow_test_begin "session-end-learn does nothing in a judge's session (V12)"
  _setup hook-session-end-learn "the repository's decision journal changed today"
  mkdir -p "$E2E_REPO/.decisions"
  printf '# issue 42\n' > "$E2E_REPO/.decisions/issue-42.md"
  e2e_run_hook CLAUDE_HOOK_GOAL_JUDGE_MODE=true hooks/scripts/session-end-learn.sh '{"session_id":"s1"}'
  e2e_expect_equal no "$([ -f "$E2E_HOME/.claude/flow-learn-pending" ] && echo yes || echo no)" "with the guard variable, a learn reminder was written"
  e2e_run_hook hooks/scripts/session-end-learn.sh '{"session_id":"s1"}'
  e2e_expect_equal yes "$([ -f "$E2E_HOME/.claude/flow-learn-pending" ] && echo yes || echo no)" "without the guard variable, a learn reminder was written"
  _edges not-called
fi

if _want hook-goal-stop; then
  _flow_test_begin "flow-goal-stop does nothing in a judge's session (V12)"
  _setup hook-goal-stop "evaluator-loop is on and an active goal has a failing must_pass command" '{"flow":{"goals":{"stopHookEnforcement":"block"}}}'
  e2e_goal g-42 feature/issue-42-e2e active false
  e2e_run_hook CLAUDE_HOOK_GOAL_JUDGE_MODE=true hooks/scripts/flow-goal-stop.sh '{"session_id":"s1","stop_hook_active":false}'
  OUT1="$E2E_OUT"
  e2e_run_hook hooks/scripts/flow-goal-stop.sh '{"session_id":"s1","stop_hook_active":false}'
  OUT0="$E2E_OUT"
  e2e_expect_equal yes "$([ -n "$OUT0" ] && [ "$OUT0" != "$OUT1" ] && echo yes || echo no)" "without the guard variable the hook decides differently"
  case "$OUT1" in ''|*'"approve"'*) e2e_expect_equal ok ok "with the guard variable the hook approves or says nothing" ;;
    *) e2e_expect_equal "approve or nothing" "$OUT1" "with the guard variable, stdout" ;; esac
  _edges not-called
fi
