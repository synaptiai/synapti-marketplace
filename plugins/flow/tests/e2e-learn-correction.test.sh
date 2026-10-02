# shellcheck shell=bash
# End-to-end: /flow:learn orders its transcript correction candidates by a
# System One answer (site learn.correction), and records the decision Phase 2
# takes on each screened candidate.
#
# The Transcript Corrections section of commands/learn.md
# (TRANSCRIPT_CORRECTIONS_BLOCK) and the verdict step of Phase 2
# (LEARN_VERDICT_BLOCK) run through tests/lib/e2e.sh in a scratch repository
# with its own HOME, under zsh and bash. The transcripts are a fixture written
# by each scenario into a directory the user settings name
# (learning.transcriptDir); the provider is a stub server
# (tests/lib/s1_stub.py) whose by_state rules answer each candidate by a word in
# its text. The shipped questions file is used as it is. One artifact per
# scenario is written to $FLOW_E2E_ARTIFACT_DIR. FLOW_E2E_SCENARIOS=a,b runs
# only the named scenarios.
#
# Ways it can be wrong, written down before the scenarios:
#   L1 rows are sorted by confidence instead of p, so a confident "not a
#      correction" (p 0.03, confidence 0.94) is listed first
#   L2 with the site off, no provider, or no answer, the section prints
#      something new (an S1_ line, a blank line, a reordered table), or the
#      site off still sends a request
#   L3 shadow mode reorders the table or prints S1_ lines, or writes no
#      records, or records a digest that is not the digest of the state sent
#   L4 a repository setting starts the sending of the user's transcript text
#      (its shadow or its on), raises the user's shadow to on, or cannot
#      lower the user's on to shadow
#   L5 rows are joined to answers by position, so a transcript that grew
#      between the two miner runs gives one row another row's answer
#   L6 one failed call ends screening for the rest
#   L7 screening has no overall limit, or the limit is counted per call
#   L8 transcript text containing a newline and a heading opens a section
#   L9 the verdict writer records a line that was never screened, or keys the
#      verdict to something other than the record of that line
#   L10 the miner itself sends a request
#   L11 the verdict step is given the Line cell as the miner printed it, which
#      is cut at 200 characters (and has whitespace collapsed and | escaped),
#      so it names no record and writes nothing without saying so
#   L12 the verdict writer takes a record of any age, not only one from the
#      last 24 hours
#   L13 rows inside one band are put in the wrong order: rated corrections
#      not by p, or rated non-corrections not in the miner's order

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0
# A scenario here starts its stub before the baseline run and makes up to
# 12 calls after it; the default 60 s stub lifetime leaves too little room
# on a slow machine.
# shellcheck disable=SC2034  # read by e2e_stub_start in tests/lib/e2e.sh
E2E_STUB_LIFETIME=300

LC_RECORDS=".claude/flow-state/system-one.jsonl"
LC_VERDICTS=".claude/flow-state/learn-correction-verdicts.jsonl"
# The commit before this site was added: the Transcript Corrections section of
# its learn.md is the one whose output the site off must reproduce byte for
# byte. A later change that alters that section's output on purpose re-pins
# this to its own parent commit; a change to another section does not.
LC_BEFORE=85b63bc41d3391dcf7005931331c3755d9e952f6
LC_NSH=0
for _lc_sh in $E2E_FENCE_SHELLS; do LC_NSH=$((LC_NSH + 1)); done

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

# Replies in the TypeSafe shape for the one noul question.
_lc_reply() { printf '{"model":"jev-1.13.0","answers":{"is_correction":{"type":"noul","noul":%s}}}' "$1"; }

# _lc_turns <file> <word> <assistant text> <user text> ... — append an
# assistant record and the user turn after it, once per pair. The miner keeps
# a user turn only when it follows an assistant record and contains one of its
# phrases (no, why did, wrong).
_lc_turns() {
  local f="$1"; shift
  while [ $# -ge 2 ]; do
    jq -nc --arg t "$1" '{type:"assistant",sessionId:"session-a",timestamp:"2026-09-30T10:00:00Z",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$f"
    jq -nc --arg t "$2" '{type:"user",sessionId:"session-a",timestamp:"2026-09-30T10:01:00Z",message:{role:"user",content:$t}}' >> "$f"
    shift 2
  done
}

# The three candidates every scenario starts with, in miner order:
#   1 ALPHA   (the stub says p 0.03: confidently not a correction)
#   2 BRAVO   (the stub answers 500)
#   3 CHARLIE (the stub says p 0.95)
# Ordered by p they are 3, 2, 1; by confidence 1 (0.94) would come before 3
# (0.90). Their transcript lines are 2, 4 and 6.
LC_A_ASSISTANT="I added the tests and they pass."
LC_A_USER="no, the output file is still empty ALPHA"
LC_B_ASSISTANT="Done, the build is green."
LC_B_USER="why did you skip the lint step BRAVO"
LC_C_ASSISTANT="I renamed the function as you asked."
LC_C_USER="that is wrong, keep the old name CHARLIE"

_lc_setup() {
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo feature/lc
  LC_TDIR="$E2E_DIR/transcripts"
  mkdir -p "$LC_TDIR"
  _lc_turns "$LC_TDIR/session-a.jsonl" "$LC_A_ASSISTANT" "$LC_A_USER" "$LC_B_ASSISTANT" "$LC_B_USER" "$LC_C_ASSISTANT" "$LC_C_USER"
}

# _lc_stub — the stub answering by word: ALPHA p 0.03, BRAVO 500, CHARLIE
# p 0.95, anything else p 0.95.
_lc_stub() {
  e2e_stub_start a "{\"body\":$(_lc_reply 0.95),\"by_state\":[{\"contains\":\"ALPHA\",\"body\":$(_lc_reply 0.03)},{\"contains\":\"BRAVO\",\"status\":500,\"body\":{\"detail\":\"boom\"}},{\"contains\":\"CHARLIE\",\"body\":$(_lc_reply 0.95)}]}"
}

# _lc_settings <mode or ""> [provider] [extra systemOne fields as jq object] —
# user settings: the stub as a custom provider, the fixture transcripts, and
# the site in <mode> (no uses entry at all for "").
_lc_settings() {
  local mode="$1" provider="${2:-custom}" extra="${3:-}"
  [ -n "$extra" ] || extra='{}'
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url a)" --arg t "$LC_TDIR" --arg m "$mode" --arg p "$provider" --argjson x "$extra" \
    '{systemOne:({provider:$p,baseUrl:$u} + $x + (if $m == "" then {} else {uses:{"learn.correction":$m}} end)),learning:{transcriptDir:$t}}')"
}

_lc_run() {
  e2e_run_block HELPER="$E2E_ACTIVE_PLUGIN/bin/cascade-resolve.sh" commands/learn.md TRANSCRIPT_CORRECTIONS_BLOCK
  e2e_expect_equal 0 "$E2E_RC" "exit status of the block"
}

# _lc_baseline — run the block with the site off and keep its stdout as
# LC_BASE: what the section prints today. The stub must not be called.
_lc_baseline() { _lc_baseline_n 3; }
_lc_baseline_n() {
  _lc_settings off
  _lc_run
  LC_BASE="$E2E_OUT"
  e2e_expect_equal 0 "$(e2e_stub_requests a)" "requests with the site off"
  e2e_expect_out "CANDIDATE_COUNT=$1"
}

_lc_expect_base() {
  if [ "$E2E_OUT" = "$LC_BASE" ]; then _e2e_result pass "stdout is the stdout with the site off, byte for byte"
  else _e2e_result fail "stdout is the stdout with the site off, byte for byte"; fi
}

# _lc_rows — the table rows of stdout, by the word each carries, on one line.
_lc_rows() {
  grep '^| [0-9]' <<<"$E2E_OUT" | sed -E 's/.*(ALPHA|BRAVO|CHARLIE|DELTA|ECHO|FOXTROT).*/\1/' | tr '\n' ' ' | sed 's/ $//'
}

# _lc_section <learn.md> — the Transcript Corrections section of that file,
# from its "# Section:" comment to the next one, as a fence of its own.
_lc_section() {
  printf '```!\n'
  awk '$0 == "# Section: Transcript Corrections" { on = 1; print; next }
       on && /^# Section: / { exit }
       on { print }' "$1"
  printf '```\n'
}

# _lc_count_miner — a plugin copy whose miner writes one line to
# $E2E_DIR/miner-jsonl-runs for each --format jsonl run, the run screening
# makes, before running the real miner. _lc_jsonl_runs counts those lines.
_lc_count_miner() {
  e2e_plugin_copy bin/flow-mine-corrections.sh '#!/usr/bin/env bash
case " $* " in *" --format jsonl "*) printf "%s\n" jsonl >> "$E2E_DIR/miner-jsonl-runs" ;; esac
exec "$(dirname "$0")/flow-mine-corrections-real.sh" "$@"'
  cp "$E2E_PLUGIN_DIR/bin/flow-mine-corrections.sh" "$E2E_ACTIVE_PLUGIN/bin/flow-mine-corrections-real.sh"
}
_lc_jsonl_runs() { [ -f "$E2E_DIR/miner-jsonl-runs" ] && grep -c . "$E2E_DIR/miner-jsonl-runs" || printf '0'; }

_lc_records() { [ -f "$E2E_HOME/$LC_RECORDS" ] && grep -c . "$E2E_HOME/$LC_RECORDS" || printf '0'; }

# _lc_state_sha <assistant text> <user text> — the sha256 of the state the
# interface contract defines: {"assistant_before", "user_turn"}, keys sorted,
# UTF-8, no trailing newline. Built here from the fixture, not by the code.
_lc_state_sha() {
  python3 -c 'import hashlib, json, sys; print(hashlib.sha256(json.dumps({"assistant_before": sys.argv[1], "user_turn": sys.argv[2]}, ensure_ascii=False, sort_keys=True).encode("utf-8")).hexdigest())' "$1" "$2"
}

# ----------------------------------------------------------------- off and no answer

if _want lc-off-matches-before; then
  _flow_test_begin "lc-off-matches-before"
  _lc_setup lc-off-matches-before "with the site off for the user and a provider configured, the Transcript Corrections section of Phase 1 prints what it printed before this site existed, byte for byte, and no request is sent (L2). Only that section is compared, so a change to another Phase 1 section does not fail it"
  _lc_stub
  _lc_settings off
  if git -C "$REPO_ROOT" cat-file -e "$LC_BEFORE:plugins/flow/commands/learn.md" 2>/dev/null; then
    git -C "$REPO_ROOT" show "$LC_BEFORE:plugins/flow/commands/learn.md" > "$E2E_DIR/learn-before.md"
    _lc_section "$E2E_DIR/learn-before.md" > "$E2E_DIR/section-before.md"
    _lc_section "$E2E_ACTIVE_PLUGIN/commands/learn.md" > "$E2E_DIR/section-now.md"
    e2e_run_fence HELPER="$E2E_ACTIVE_PLUGIN/bin/cascade-resolve.sh" "$E2E_DIR/section-before.md" "### Transcript Corrections"
    e2e_expect_equal 0 "$E2E_RC" "exit status of the section before this site"
    LC_OLD="$E2E_OUT"
    e2e_run_fence HELPER="$E2E_ACTIVE_PLUGIN/bin/cascade-resolve.sh" "$E2E_DIR/section-now.md" "### Transcript Corrections"
    e2e_expect_equal 0 "$E2E_RC" "exit status of the section now"
    if [ "$E2E_OUT" = "$LC_OLD" ]; then _e2e_result pass "stdout equals the learn.md of $LC_BEFORE"
    else _e2e_result fail "stdout equals the learn.md of $LC_BEFORE"; fi
    e2e_expect_out "CANDIDATE_COUNT=3"
  else
    # CI fetches the whole history; a clone without this commit cannot run
    # the comparison, and that is a failure, not a pass.
    _e2e_result fail "commit $LC_BEFORE is in this clone"
  fi
  e2e_expect_equal 0 "$(e2e_stub_requests a)" "requests received by the stub"
  e2e_expect_equal 0 "$(_lc_records)" "records written"
fi

if _want lc-off-one-miner-run; then
  _flow_test_begin "lc-off-one-miner-run"
  _lc_setup lc-off-one-miner-run "with the site off the miner runs once per block run, in markdown, as before; with the site in shadow it runs a second time, in jsonl (a plugin copy whose miner logs each run) (L2)"
  e2e_plugin_copy bin/flow-mine-corrections.sh '#!/usr/bin/env bash
case " $* " in
  *" --format jsonl "*) printf "jsonl\n" >> "$E2E_DIR/miner-runs.log" ;;
  *) printf "markdown\n" >> "$E2E_DIR/miner-runs.log" ;;
esac
exec "$(dirname "$0")/flow-mine-corrections-real.sh" "$@"'
  cp "$E2E_PLUGIN_DIR/bin/flow-mine-corrections.sh" "$E2E_ACTIVE_PLUGIN/bin/flow-mine-corrections-real.sh"
  _lc_stub
  _lc_baseline
  e2e_expect_equal "$LC_NSH markdown" "$(sort "$E2E_DIR/miner-runs.log" | uniq -c | sed 's/^ *//' | tr '\n' ' ' | sed 's/ $//')" "miner runs with the site off"
  : > "$E2E_DIR/miner-runs.log"
  _lc_settings shadow
  _lc_run
  e2e_expect_equal "$LC_NSH jsonl $LC_NSH markdown" "$(sort "$E2E_DIR/miner-runs.log" | uniq -c | sed 's/^ *//' | tr '\n' ' ' | sed 's/ $//')" "miner runs with the site in shadow"
fi

if _want lc-no-provider; then
  _flow_test_begin "lc-no-provider"
  _lc_setup lc-no-provider "provider none with the site on: the section prints what it prints with the site off, and nothing is sent or recorded (L2)"
  _lc_stub
  _lc_baseline
  _lc_settings on none
  _lc_run
  _lc_expect_base
  e2e_expect_equal 0 "$(e2e_stub_requests a)" "requests received by the stub"
  e2e_expect_equal 0 "$(_lc_records)" "records written"
fi

if _want lc-no-answer-http; then
  _flow_test_begin "lc-no-answer-http"
  _lc_setup lc-no-answer-http "the site on and every request answered 500: every candidate is unanswered, so the section prints what it prints with the site off, and each call is recorded as http-500 (L2)"
  e2e_stub_start a '{"status":500,"body":{"detail":"boom"}}'
  _lc_baseline
  _lc_settings on
  _lc_run
  _lc_expect_base
  e2e_expect_equal $((3 * LC_NSH)) "$(e2e_stub_requests a)" "requests received by the stub (3 candidates, $LC_NSH shells)"
  e2e_expect_equal "$((3 * LC_NSH)) http-500" "$(_lc_records) $(jq -r .result "$E2E_HOME/$LC_RECORDS" | sort -u | tr '\n' ' ' | sed 's/ $//')" "records and their result"
fi

if _want lc-no-answer-abstained; then
  _flow_test_begin "lc-no-answer-abstained"
  _lc_setup lc-no-answer-abstained "the site on and an imajev-shaped reply that abstains for every candidate: the section prints what it prints with the site off, and the records say abstained (L2)"
  e2e_stub_start a '{"body":{"model":"imajev-4b","answers":{"is_correction":{"type":"noul","noul":0.95,"unknown_probability":0.6,"abstained":true}}}}'
  _lc_baseline
  _lc_settings on
  _lc_run
  _lc_expect_base
  e2e_expect_equal $((3 * LC_NSH)) "$(e2e_stub_requests a)" "requests received by the stub"
  e2e_expect_equal "abstained" "$(jq -r .result "$E2E_HOME/$LC_RECORDS" | sort -u | tr '\n' ' ' | sed 's/ $//')" "result of every record"
fi

if _want lc-below-threshold; then
  _flow_test_begin "lc-below-threshold"
  _lc_setup lc-below-threshold "the site on and every p 0.7 (confidence 0.4, under the 0.8 threshold): the section prints what it prints with the site off, and the records keep the answer with result below-threshold (L2)"
  e2e_stub_start a "{\"body\":$(_lc_reply 0.7)}"
  _lc_baseline
  _lc_settings on
  _lc_run
  _lc_expect_base
  e2e_expect_equal "below-threshold 0.7" "$(jq -r '"\(.result) \(.answer.p)"' "$E2E_HOME/$LC_RECORDS" | sort -u | tr '\n' ' ' | sed 's/ $//')" "result and kept p of every record"
fi

# ----------------------------------------------------------------- on and shadow

if _want lc-on-orders; then
  _flow_test_begin "lc-on-orders"
  _lc_setup lc-on-orders "the site on, the stub answering p 0.03, 500 and p 0.95 for the three candidates in miner order: the rows are listed by p (0.95, then the unanswered one, then 0.03), the row numbers stay the miner's, no row is added or lost, and four S1_ lines say what happened (L1, L6)"
  _lc_stub
  _lc_baseline
  e2e_expect_equal "ALPHA BRAVO CHARLIE" "$(_lc_rows)" "rows in miner order with the site off"
  _lc_settings on
  _lc_run
  e2e_expect_equal "CHARLIE BRAVO ALPHA" "$(_lc_rows)" "rows by p: 0.95, unanswered, 0.03"
  e2e_expect_equal "3 2 1" "$(grep '^| [0-9]' <<<"$E2E_OUT" | cut -d' ' -f2 | tr '\n' ' ' | sed 's/ $//')" "each row keeps the number the miner gave it"
  e2e_expect_line "S1_STATE=ordered"
  e2e_expect_line "S1_SCREENED=3"
  e2e_expect_line "S1_ANSWERED=2"
  e2e_expect_line "S1_RATED_CORRECTION=1"
  if [ "$(grep -v '^S1_' <<<"$E2E_OUT" | LC_ALL=C sort)" = "$(LC_ALL=C sort <<<"$LC_BASE")" ]; then
    _e2e_result pass "without the S1_ lines, stdout holds the same lines as with the site off"
  else
    _e2e_result fail "without the S1_ lines, stdout holds the same lines as with the site off"
  fi
  # The S1_ lines come after the miner's KEY lines, before the blank line and
  # the table.
  e2e_expect_equal "SESSIONS_WITH_CANDIDATES=1" "$(grep -B1 '^S1_STATE=' <<<"$E2E_OUT" | head -1)" "the line before S1_STATE"
  e2e_expect_equal "" "$(grep -A1 '^S1_RATED_CORRECTION=' <<<"$E2E_OUT" | tail -1)" "the line after S1_RATED_CORRECTION"
  e2e_expect_equal $((3 * LC_NSH)) "$(e2e_stub_requests a)" "requests received by the stub"
fi

if _want lc-shadow; then
  _flow_test_begin "lc-shadow"
  _lc_setup lc-shadow "the site in shadow with the same stub: stdout is what the site off prints, every candidate is asked, and each record says shadow, keyword-candidate, the transcript line it judged, and the sha256 of the state the contract defines (L3)"
  _lc_stub
  _lc_baseline
  _lc_settings shadow
  _lc_run
  _lc_expect_base
  e2e_expect_no_out "S1_"
  e2e_expect_equal $((3 * LC_NSH)) "$(e2e_stub_requests a)" "requests received by the stub"
  e2e_expect_equal $((3 * LC_NSH)) "$(_lc_records)" "records written"
  e2e_expect_equal "shadow keyword-candidate learn.correction is_correction" \
    "$(jq -r '"\(.mode) \(.current) \(.site) \(.question)"' "$E2E_HOME/$LC_RECORDS" | sort -u | tr '\n' ' ' | sed 's/ $//')" "mode, current, site and question of every record"
  sha_a=$(_lc_state_sha "$LC_A_ASSISTANT" "$LC_A_USER")
  sha_b=$(_lc_state_sha "$LC_B_ASSISTANT" "$LC_B_USER")
  sha_c=$(_lc_state_sha "$LC_C_ASSISTANT" "$LC_C_USER")
  e2e_expect_equal "transcript:session-a/2 $sha_a|transcript:session-a/4 $sha_b|transcript:session-a/6 $sha_c" \
    "$(jq -r '"\(.ref) \(.state_sha256)"' "$E2E_HOME/$LC_RECORDS" | sort -u | tr '\n' '|' | sed 's/|$//')" "ref and state digest of each record"
  e2e_expect_equal "$LC_A_USER" "$(jq -r 'select(.body.state.user_turn | test("ALPHA")) | .body.state.user_turn' "$(e2e_stub_log a)" | head -1)" "the user turn sent for the first candidate"
  e2e_expect_equal "assistant_before user_turn" "$(jq -r '.body.state | keys | join(" ")' "$(e2e_stub_log a)" | sort -u)" "the fields of every state sent"
  e2e_expect_equal 0 "$(jq -r 'select(.body.state | tostring | test("transcripts|session-a")) | 1' "$(e2e_stub_log a)" | grep -c .)" "states naming the transcript path or session"
fi

# ----------------------------------------------------------------- who may switch it

if _want lc-repo-shadow; then
  _flow_test_begin "lc-repo-shadow"
  _lc_setup lc-repo-shadow "the repository's settings set the site to shadow and the user's set a provider but no mode for it: the screening miner run does not happen, nothing is sent, and stdout is what the site off prints (L4)"
  _lc_count_miner
  _lc_stub
  _lc_baseline
  _lc_settings ""
  mkdir -p "$E2E_REPO/.claude"
  printf '{"systemOne":{"uses":{"learn.correction":"shadow"}}}\n' > "$E2E_REPO/.claude/settings.flow.json"
  _lc_run
  _lc_expect_base
  e2e_expect_equal 0 "$(_lc_jsonl_runs)" "screening miner runs (--format jsonl)"
  e2e_expect_equal 0 "$(e2e_stub_requests a)" "requests received by the stub"
  e2e_expect_equal 0 "$(_lc_records)" "records written"
fi

if _want lc-repo-on; then
  _flow_test_begin "lc-repo-on"
  _lc_setup lc-repo-on "the repository's settings set the site on and the user's set a provider but no mode for it: the screening miner run does not happen, nothing is sent, and stdout is what the site off prints (L4)"
  _lc_count_miner
  _lc_stub
  _lc_baseline
  _lc_settings ""
  mkdir -p "$E2E_REPO/.claude"
  printf '{"systemOne":{"uses":{"learn.correction":"on"}}}\n' > "$E2E_REPO/.claude/settings.flow.json"
  _lc_run
  _lc_expect_base
  e2e_expect_equal 0 "$(_lc_jsonl_runs)" "screening miner runs (--format jsonl)"
  e2e_expect_equal 0 "$(e2e_stub_requests a)" "requests received by the stub"
fi

if _want lc-repo-lowers; then
  _flow_test_begin "lc-repo-lowers"
  _lc_setup lc-repo-lowers "the user sets the site on and the repository sets it off: the repository may lower the mode, so nothing is sent and stdout is what the site off prints"
  _lc_stub
  _lc_baseline
  _lc_settings on
  mkdir -p "$E2E_REPO/.claude"
  printf '{"systemOne":{"uses":{"learn.correction":"off"}}}\n' > "$E2E_REPO/.claude/settings.flow.json"
  _lc_run
  _lc_expect_base
  e2e_expect_equal 0 "$(e2e_stub_requests a)" "requests received by the stub"
fi

if _want lc-repo-lowers-to-shadow; then
  _flow_test_begin "lc-repo-lowers-to-shadow"
  _lc_setup lc-repo-lowers-to-shadow "the user sets the site on and the repository sets it to shadow: the lower mode, shadow, is used, so every candidate is asked and recorded in shadow and stdout is what the site off prints (L4)"
  _lc_count_miner
  _lc_stub
  _lc_baseline
  _lc_settings on
  mkdir -p "$E2E_REPO/.claude"
  printf '{"systemOne":{"uses":{"learn.correction":"shadow"}}}\n' > "$E2E_REPO/.claude/settings.flow.json"
  _lc_run
  _lc_expect_base
  e2e_expect_no_out "S1_"
  e2e_expect_equal $((3 * LC_NSH)) "$(e2e_stub_requests a)" "requests received by the stub"
  e2e_expect_equal "$LC_NSH" "$(_lc_jsonl_runs)" "screening miner runs (--format jsonl), one per shell"
  e2e_expect_equal "shadow" "$(jq -r .mode "$E2E_HOME/$LC_RECORDS" | sort -u | tr '\n' ' ' | sed 's/ $//')" "mode of every record"
fi

if _want lc-repo-cannot-raise; then
  _flow_test_begin "lc-repo-cannot-raise"
  _lc_setup lc-repo-cannot-raise "the user sets the site to shadow and the repository sets it on: the user's shadow is used, so the rows stay in miner order, no S1_ line is printed, and every record says shadow (L4)"
  _lc_stub
  _lc_baseline
  _lc_settings shadow
  mkdir -p "$E2E_REPO/.claude"
  printf '{"systemOne":{"uses":{"learn.correction":"on"}}}\n' > "$E2E_REPO/.claude/settings.flow.json"
  _lc_run
  _lc_expect_base
  e2e_expect_no_out "S1_"
  e2e_expect_equal $((3 * LC_NSH)) "$(e2e_stub_requests a)" "requests received by the stub"
  e2e_expect_equal "shadow" "$(jq -r .mode "$E2E_HOME/$LC_RECORDS" | sort -u | tr '\n' ' ' | sed 's/ $//')" "mode of every record"
fi

# ----------------------------------------------------------------- the join, the budget, the text

if _want lc-mismatch; then
  _flow_test_begin "lc-mismatch"
  _lc_setup lc-mismatch "the transcript gains a fourth candidate between the markdown and the jsonl miner runs (a plugin copy whose miner appends it before a jsonl run): the rows stay in miner order and S1_STATE=mismatch is printed, rather than answers being given to rows by position (L5)"
  cp "$LC_TDIR/session-a.jsonl" "$E2E_DIR/session-a.pristine"
  e2e_plugin_copy bin/flow-mine-corrections.sh '#!/usr/bin/env bash
# A miner that sees a transcript growing: a markdown run reads the fixture as
# written, a jsonl run reads it after one more candidate (DELTA) is appended.
case " $* " in
  *" --format jsonl "*)
    printf "%s\n" "{\"type\":\"assistant\",\"sessionId\":\"session-a\",\"message\":{\"role\":\"assistant\",\"content\":\"Fixed.\"}}" "{\"type\":\"user\",\"sessionId\":\"session-a\",\"message\":{\"role\":\"user\",\"content\":\"no, still wrong DELTA\"}}" >> "$E2E_DIR/transcripts/session-a.jsonl" ;;
  *) cp "$E2E_DIR/session-a.pristine" "$E2E_DIR/transcripts/session-a.jsonl" ;;
esac
exec "$(dirname "$0")/flow-mine-corrections-real.sh" "$@"'
  cp "$E2E_PLUGIN_DIR/bin/flow-mine-corrections.sh" "$E2E_ACTIVE_PLUGIN/bin/flow-mine-corrections-real.sh"
  _lc_stub
  _lc_baseline
  _lc_settings on
  _lc_run
  e2e_expect_equal "ALPHA BRAVO CHARLIE" "$(_lc_rows)" "rows in miner order"
  e2e_expect_line "S1_STATE=mismatch"
  e2e_expect_line "S1_SCREENED=4"
  e2e_expect_equal "$LC_BASE" "$(grep -v '^S1_' <<<"$E2E_OUT")" "stdout without the S1_ lines"
  e2e_expect_equal $((4 * LC_NSH)) "$(e2e_stub_requests a)" "requests received by the stub (the 4 candidates of the jsonl run)"
fi

if _want lc-budget-calls; then
  _flow_test_begin "lc-budget-calls"
  _lc_setup lc-budget-calls "a plugin copy whose screening asks at most 2 candidates, with the stub answering ALPHA p 0.03 and BRAVO 500: ALPHA and BRAVO are asked and CHARLIE is not, so on mode prints S1_STATE=partial and S1_SCREENED=2, and the two unanswered rows come before ALPHA in miner order (L7)"
  e2e_plugin_copy bin/_flow_learn_s1.py "$(sed 's/^BUDGET_CALLS = 100$/BUDGET_CALLS = 2/' "$E2E_PLUGIN_DIR/bin/_flow_learn_s1.py")"
  if grep -q '^BUDGET_CALLS = 2$' "$E2E_ACTIVE_PLUGIN/bin/_flow_learn_s1.py"; then
    _e2e_result pass "the plugin copy asks at most 2 candidates"
  else
    _e2e_result fail "the plugin copy asks at most 2 candidates"
  fi
  _lc_stub
  _lc_baseline
  _lc_settings on
  _lc_run
  e2e_expect_line "S1_STATE=partial"
  e2e_expect_line "S1_SCREENED=2"
  e2e_expect_line "S1_ANSWERED=1"
  e2e_expect_line "S1_RATED_CORRECTION=0"
  e2e_expect_equal $((2 * LC_NSH)) "$(e2e_stub_requests a)" "requests received by the stub"
  e2e_expect_equal "BRAVO CHARLIE ALPHA" "$(_lc_rows)" "rows: the unanswered BRAVO and the unasked CHARLIE in miner order, then ALPHA (p 0.03)"
fi

if _want lc-budget-time; then
  _flow_test_begin "lc-budget-time"
  _lc_setup lc-budget-time "a plugin copy whose screening budget is 2 s, and a stub that waits 2.5 s before each answer: the first call ends past the budget however fast the machine is, so the second is never started; a limit counted per call, or none, would ask all three. On mode prints S1_STATE=partial and S1_SCREENED=1 (L7)"
  e2e_plugin_copy bin/_flow_learn_s1.py "$(sed 's/^BUDGET_SECONDS = 60$/BUDGET_SECONDS = 2/' "$E2E_PLUGIN_DIR/bin/_flow_learn_s1.py")"
  if grep -q '^BUDGET_SECONDS = 2$' "$E2E_ACTIVE_PLUGIN/bin/_flow_learn_s1.py"; then
    _e2e_result pass "the plugin copy has a 2 s budget"
  else
    _e2e_result fail "the plugin copy has a 2 s budget"
  fi
  e2e_stub_start a "{\"delay_ms\":2500,\"body\":$(_lc_reply 0.95)}"
  _lc_baseline
  _lc_settings on custom '{"timeoutMs":10000}'
  _lc_run
  e2e_expect_line "S1_STATE=partial"
  e2e_expect_line "S1_SCREENED=1"
  e2e_expect_line "S1_ANSWERED=1"
  e2e_expect_equal "$LC_NSH" "$(e2e_stub_requests a)" "requests received by the stub (one per shell)"
  e2e_expect_equal "ALPHA BRAVO CHARLIE" "$(_lc_rows)" "rows: ALPHA (p 0.95), then the two not asked in miner order"
fi

if _want lc-on-bands; then
  _flow_test_begin "lc-on-bands"
  _lc_setup lc-on-bands "six candidates answered p 0.03, 500, 0.95, 0.99, 0.01 and 0.05 in miner order: the rated corrections come first by p (0.99 before 0.95, the reverse of miner order), then the unanswered one, then the rated non-corrections in miner order (0.03, 0.01, 0.05), which is neither ascending nor descending p (L13)"
  _lc_turns "$LC_TDIR/session-a.jsonl" "I updated the docs." "no, the docs still say the old flag DELTA" \
    "The migration ran." "no, ECHO is a new question about the schema" \
    "I pushed the branch." "no, FOXTROT, thanks, that is all"
  e2e_stub_start a "{\"body\":$(_lc_reply 0.95),\"by_state\":[{\"contains\":\"ALPHA\",\"body\":$(_lc_reply 0.03)},{\"contains\":\"BRAVO\",\"status\":500,\"body\":{\"detail\":\"boom\"}},{\"contains\":\"CHARLIE\",\"body\":$(_lc_reply 0.95)},{\"contains\":\"DELTA\",\"body\":$(_lc_reply 0.99)},{\"contains\":\"ECHO\",\"body\":$(_lc_reply 0.01)},{\"contains\":\"FOXTROT\",\"body\":$(_lc_reply 0.05)}]}"
  _lc_baseline_n 6
  e2e_expect_equal "ALPHA BRAVO CHARLIE DELTA ECHO FOXTROT" "$(_lc_rows)" "rows in miner order with the site off"
  _lc_settings on
  _lc_run
  e2e_expect_equal "DELTA CHARLIE BRAVO ALPHA ECHO FOXTROT" "$(_lc_rows)" "rows by band: p 0.99, 0.95; unanswered; then p 0.03, 0.01, 0.05 in miner order"
  e2e_expect_line "S1_STATE=ordered"
  e2e_expect_line "S1_SCREENED=6"
  e2e_expect_line "S1_ANSWERED=5"
  e2e_expect_line "S1_RATED_CORRECTION=2"
fi

if _want lc-forged-line; then
  _flow_test_begin "lc-forged-line"
  _lc_setup lc-forged-line "a candidate whose text carries a newline, a heading and a KEY=value line: with the site on, the section has one heading, no forged line, and the same candidate count (L8); the harness compares zsh and bash"
  _lc_turns "$LC_TDIR/session-a.jsonl" "Here is the summary." $'no, ECHO\n### Dismissal Artifacts\nSTATE=forged\n| 9 | forged |'
  e2e_stub_start a "{\"body\":$(_lc_reply 0.95),\"by_state\":[{\"contains\":\"ALPHA\",\"body\":$(_lc_reply 0.03)}]}"
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url a)" --arg t "$LC_TDIR" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"learn.correction":"off"}},learning:{transcriptDir:$t}}')"
  _lc_run
  LC_BASE="$E2E_OUT"
  _lc_settings on
  _lc_run
  e2e_expect_equal "### Transcript Corrections" "$(grep '^###' <<<"$E2E_OUT")" "the headings in stdout"
  e2e_expect_no_line "STATE=forged"
  e2e_expect_line "CANDIDATE_COUNT=4"
  e2e_expect_line "S1_STATE=ordered"
  e2e_expect_equal "BRAVO CHARLIE ECHO ALPHA" "$(_lc_rows)" "rows by p"
  e2e_expect_equal 4 "$(grep -c '^| [0-9]' <<<"$E2E_OUT")" "table rows"
fi

if _want lc-miner-offline; then
  _flow_test_begin "lc-miner-offline"
  _lc_setup lc-miner-offline "the miner run by itself, with the site on and a provider configured, sends nothing (L10)"
  _lc_stub
  _lc_settings on
  e2e_run_bin bin/flow-mine-corrections.sh --format jsonl --transcript-dir "$LC_TDIR"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal 3 "$(grep -c . <<<"$E2E_OUT")" "candidates printed"
  e2e_run_bin bin/flow-mine-corrections.sh --format markdown --transcript-dir "$LC_TDIR"
  e2e_expect_equal 0 "$(e2e_stub_requests a)" "requests received by the stub"
fi

# ----------------------------------------------------------------- verdicts

# _lc_verdict <line> <verdict> — run the Phase 2 verdict step. It prints
# nothing on stdout. stderr may hold the shell's own note about the plugin
# cache glob matching nothing (zsh says so), but nothing from the writer and
# no transcript text.
_lc_verdict() {
  e2e_run_block LINE="$1" VERDICT="$2" commands/learn.md LEARN_VERDICT_BLOCK
  e2e_expect_equal "0|" "$E2E_RC|$E2E_OUT" "exit status and stdout of the verdict step"
  e2e_expect_err_lacks "flow-learn-verdict"
  e2e_expect_err_lacks "CHARLIE"
  e2e_expect_err_lacks "Traceback"
}

if _want lc-verdict; then
  _flow_test_begin "lc-verdict"
  _lc_setup lc-verdict "after a shadow run, the Phase 2 verdict step records kept for a screened line with the digest of that line's record; a line that was not screened gets nothing; nothing it prints carries transcript text (L9)"
  _lc_stub
  _lc_settings shadow
  _lc_run
  _lc_verdict "$LC_TDIR/session-a.jsonl:6" kept
  rec_c=$(jq -r 'select(.ref == "transcript:session-a/6") | .state_sha256' "$E2E_HOME/$LC_RECORDS" | sort -u)
  e2e_expect_equal "$(_lc_state_sha "$LC_C_ASSISTANT" "$LC_C_USER")" "$rec_c" "the record digest of line 6"
  e2e_expect_equal "learn.correction transcript:session-a/6 $rec_c kept" \
    "$(jq -r '"\(.site) \(.ref) \(.state_sha256) \(.verdict)"' "$E2E_HOME/$LC_VERDICTS" | sort -u)" "the verdicts written (one per shell run)"
  e2e_expect_equal "$LC_NSH" "$(grep -c . "$E2E_HOME/$LC_VERDICTS")" "verdict lines"
  _lc_verdict "$LC_TDIR/session-a.jsonl:5" dropped
  e2e_expect_equal "$LC_NSH" "$(grep -c . "$E2E_HOME/$LC_VERDICTS")" "verdict lines after the unscreened line"
  _lc_verdict "$E2E_DIR/other/session-b.jsonl:6" dropped
  e2e_expect_equal "$LC_NSH" "$(grep -c . "$E2E_HOME/$LC_VERDICTS")" "verdict lines after a line in a transcript that was not screened"
  # The ref names a transcript by its file name only, which for Claude Code
  # is the session id: a file of the same name in another directory is
  # taken as the same session.
  _lc_verdict "$E2E_DIR/other/session-a.jsonl:6" dropped
  e2e_expect_equal "$((2 * LC_NSH)) $rec_c" "$(grep -c . "$E2E_HOME/$LC_VERDICTS") $(jq -r 'select(.verdict == "dropped") | .state_sha256' "$E2E_HOME/$LC_VERDICTS" | sort -u)" \
    "verdict lines and the digest after a same-named transcript in another directory"
  if grep -q 'CHARLIE\|wrong' "$E2E_HOME/$LC_VERDICTS"; then _e2e_result fail "the verdicts file holds no transcript text"
  else _e2e_result pass "the verdicts file holds no transcript text"; fi
fi

if _want lc-verdict-long-path; then
  _flow_test_begin "lc-verdict-long-path"
  _lc_setup lc-verdict-long-path "a transcript path longer than 200 characters, which the miner cuts in the Line cell: the verdict step given the Line cell as printed refuses it with exit 2 and says to pass the full path, and writes nothing; given the full path, it records the verdict with the digest of that line's record (L11)"
  LC_TDIR="$E2E_DIR/$(printf 't%.0s' $(seq 1 190))"
  mkdir -p "$LC_TDIR"
  mv "$E2E_DIR/transcripts/session-a.jsonl" "$LC_TDIR/session-a.jsonl"
  _lc_stub
  _lc_settings shadow
  _lc_run
  lc_cell=$(grep '^| [0-9].*CHARLIE' <<<"$E2E_OUT" | awk -F ' [|] ' '{print $4}')
  case "$lc_cell" in
    *"…:6") _e2e_result pass "the Line cell of the third candidate is cut" ;;
    *) _e2e_result fail "the Line cell of the third candidate is cut (got: $lc_cell)" ;;
  esac
  e2e_run_block LINE="$lc_cell" VERDICT=kept commands/learn.md LEARN_VERDICT_BLOCK
  e2e_expect_equal "2|" "$E2E_RC|$E2E_OUT" "exit status and stdout for the cut Line cell"
  e2e_expect_err "pass the full path"
  if [ -e "$E2E_HOME/$LC_VERDICTS" ]; then _e2e_result fail "no verdicts file after the cut Line cell"
  else _e2e_result pass "no verdicts file after the cut Line cell"; fi
  _lc_verdict "$LC_TDIR/session-a.jsonl:6" kept
  e2e_expect_equal "learn.correction transcript:session-a/6 $(_lc_state_sha "$LC_C_ASSISTANT" "$LC_C_USER") kept" \
    "$(jq -r '"\(.site) \(.ref) \(.state_sha256) \(.verdict)"' "$E2E_HOME/$LC_VERDICTS" | sort -u)" "the verdicts written for the full path"
fi

if _want lc-verdict-off; then
  _flow_test_begin "lc-verdict-off"
  _lc_setup lc-verdict-off "with the site off nothing is screened, so the verdict step writes nothing"
  _lc_stub
  _lc_baseline
  _lc_verdict "$LC_TDIR/session-a.jsonl:6" kept
  [ -e "$E2E_HOME/$LC_VERDICTS" ] && _e2e_result fail "no verdicts file" || _e2e_result pass "no verdicts file"
fi

if _want lc-verdict-cut-early; then
  _flow_test_begin "lc-verdict-cut-early"
  _lc_setup lc-verdict-cut-early "a plugin copy whose cascade-resolve.sh fails, so the writer cannot find the state directory: a cut Line cell is still refused with exit 2 and the message to pass the full path, rather than accepted with exit 0 (L11)"
  e2e_plugin_copy bin/cascade-resolve.sh '#!/usr/bin/env bash
exit 1'
  lc_cut="$(printf 't%.0s' $(seq 1 199))…:6"
  e2e_run_block LINE="$lc_cut" VERDICT=kept commands/learn.md LEARN_VERDICT_BLOCK
  e2e_expect_equal "2|" "$E2E_RC|$E2E_OUT" "exit status and stdout for the cut Line cell"
  e2e_expect_err "pass the full path"
fi

if _want lc-verdict-window; then
  _flow_test_begin "lc-verdict-window"
  _lc_setup lc-verdict-window "a learn.correction record for transcript line 6 written 25 hours ago gets no verdict; once a record for that line from 23 hours ago is added, the verdict carries that record's digest (L12)"
  mkdir -p "$E2E_HOME/.claude/flow-state"
  chmod 700 "$E2E_HOME/.claude/flow-state"
  lc_ts() { python3 -c 'import sys, datetime; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
  lc_old=$(printf 'a%.0s' $(seq 1 64))
  lc_new=$(printf 'b%.0s' $(seq 1 64))
  jq -nc --arg ts "$(lc_ts 25)" --arg d "$lc_old" '{ts:$ts,site:"learn.correction",question:"is_correction",mode:"shadow",current:"keyword-candidate",ref:"transcript:session-a/6",state_sha256:$d,result:"answered"}' > "$E2E_HOME/$LC_RECORDS"
  _lc_verdict "$LC_TDIR/session-a.jsonl:6" kept
  if [ -e "$E2E_HOME/$LC_VERDICTS" ]; then _e2e_result fail "no verdicts file for a record 25 hours old"
  else _e2e_result pass "no verdicts file for a record 25 hours old"; fi
  jq -nc --arg ts "$(lc_ts 23)" --arg d "$lc_new" '{ts:$ts,site:"learn.correction",question:"is_correction",mode:"shadow",current:"keyword-candidate",ref:"transcript:session-a/6",state_sha256:$d,result:"answered"}' >> "$E2E_HOME/$LC_RECORDS"
  _lc_verdict "$LC_TDIR/session-a.jsonl:6" kept
  e2e_expect_equal "$LC_NSH transcript:session-a/6 $lc_new kept" \
    "$(grep -c . "$E2E_HOME/$LC_VERDICTS") $(jq -r '"\(.ref) \(.state_sha256) \(.verdict)"' "$E2E_HOME/$LC_VERDICTS" | sort -u)" "verdict lines and what they hold for a record 23 hours old"
fi
