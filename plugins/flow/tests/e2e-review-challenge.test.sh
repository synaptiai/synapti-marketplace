# shellcheck shell=bash
# End-to-end: the System One decision point review.challenge. On a Path A run
# of /flow:review, after the same-defect merge, bin/flow-s1-challenge.sh asks,
# for each finding that went through the challenge round, whether the code it
# cites contradicts it. The answer is a third voice: in on mode it is shown as
# a note next to the finding; it never changes a confidence, a disposition,
# routing or the review decision, and never drops a finding.
#
# Each scenario runs the shipped code in a scratch repository with its own
# HOME, against a stub System One server (tests/lib/s1_stub.py) that logs every
# request: the script itself, the whole Path A gate fence (which holds
# S1_CHALLENGE_MODE_BLOCK), REVIEW_CHALLENGE_BLOCK and FINDING_ROUTE_BLOCK
# taken from commands/review.md. A block runs once under each shell in
# E2E_FENCE_SHELLS, so its stub request counts are per shell. Every scenario
# that expects the review to stay as it was asserts the stub request count, so
# "unchanged" cannot pass because nothing was asked. One artifact per scenario
# goes to $FLOW_E2E_ARTIFACT_DIR. FLOW_E2E_SCENARIOS=a,b runs only the named
# scenarios.
#
# Ways it can be wrong, written down before the scenarios:
#   H1  the answer changes a finding: a dispute sets LOW (an unchallenged
#       MEDIUM then leaves the counted set, and an external review whose other
#       findings are LOW approves), a support sets HIGH, or a dispute on a kept
#       finding is printed as a drop
#   H2  the direction is inverted: p >= 0.5 is shown as a dispute
#   H3  shadow shows a note: the client checks the threshold before the mode,
#       so a script that follows the exit status alone shows a shadow answer
#   H4  a security finding gets a note shown, which invites the reader to
#       discount it
#   H5  with the site off, no provider, a Path B run, or the plugin only
#       inside the repository, the probe prints a line, a request is sent or a
#       record is written, so the expanded command text or the review changes
#   H6  the note reaches a parsed field (a disposition, a marker row), so
#       routing differs from the rows without System One
#   H7  findings that never went through the challenge round are asked:
#       consensus findings, holdout-validation findings, findings of a facet
#       re-dispatched on Path B
#   H8  the state carries the finding id, the variant that raised it, its
#       disposition or the challenger's answer, which would make the third
#       voice depend on the other two; or the record lacks the challenger's
#       answer, so the comparison cannot be made
#   H9  finding text reaches a shell, or a quote or a line separator breaks
#       the state
#   H10 a cited path is joined to the tree without checks, or a malformed
#       entry stops the whole step
#   H11 a repository's settings raise the user's shadow to on
#   H12 a provider that is down holds the review for a timeout per finding

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

CH_BIN="bin/flow-s1-challenge.sh"
CH_RECORDS=".claude/flow-state/system-one.jsonl"
# shellcheck disable=SC2086
CH_NSH=$(set -- $E2E_FENCE_SHELLS; printf '%s' "$#")

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

# _noul P — a stub config whose reply answers finding_holds with probability P.
_noul() { printf '{"body":{"model":"jev-1.13.0","answers":{"finding_holds":{"type":"noul","noul":%s}}}}' "$1"; }

# _ch_setup <scenario> <purpose> — scratch repository with src/a.py (100
# numbered lines) committed, and a private directory for the findings, as the
# command makes with mktemp -d.
_ch_setup() {
  if [ -n "${CI:-}" ]; then
    { printf 'progress %s %s\n' "$(date -u +%H:%M:%S)" "$1" >&3; } 2>/dev/null
  fi
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo feature/issue-271-x
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    mkdir -p src
    i=1; while [ "$i" -le 100 ]; do printf 'line_%s = %s\n' "$i" "$i"; i=$((i + 1)); done > src/a.py
    git add src/a.py && git commit -q -m a
  ) || _flow_assert_fail "$1: could not commit src/a.py"
  CH_DIR="$E2E_DIR/challenge"
  CH_STUB=a
  mkdir -p "$CH_DIR"
  chmod 700 "$CH_DIR"
  CH_SHA=$(git -C "$E2E_REPO" rev-parse HEAD | cut -c1-7)
}

# _ch_settings <mode> [extra systemOne fields as JSON] — user settings naming
# the stub as a custom provider, with review.challenge in <mode> and paired
# review opted in.
_ch_settings() {
  local extra="${2:-}"
  [ -n "$extra" ] || extra='{}'
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url "$CH_STUB")" --arg m "$1" --argjson x "$extra" \
    '{agentTeams:true, systemOne:({provider:"custom",baseUrl:$u,uses:{"review.challenge":$m}} + $x)}')"
}

# _f <id> <priority> <category> <location> <confidence> <disposition> <reviewers,comma> [problem]
_f() {
  jq -nc --arg id "$1" --arg p "$2" --arg c "$3" --arg l "$4" --arg conf "$5" --arg d "$6" --arg r "$7" \
    --arg problem "${8:-problem of $1}" \
    '{id:$id,priority:$p,category:$c,location:$l,problem:$problem,suggested_fix:("fix for " + $id),
      confidence:$conf,disposition:$d,reviewers:($r | split(","))}'
}

# _ch_findings <finding json>... — the findings file, as the session writes it.
_ch_findings() {
  printf '%s\n' "$@" | jq -s . > "$CH_DIR/findings.json"
  printf 'findings: %s\n' "$(jq -c . "$CH_DIR/findings.json")" | _e2e_art
}

# _ch_run [NAME=value ...] [extra arguments] — the script on the findings.
_ch_run() {
  local envs=()
  while [ $# -gt 0 ]; do
    case "$1" in [A-Za-z_]*=*) envs+=("$1"); shift ;; *) break ;; esac
  done
  e2e_run_bin ${envs[@]+"${envs[@]}"} "$CH_BIN" --findings "$CH_DIR/findings.json" --tree "$E2E_REPO" \
    --ref-prefix pr:7/review-cycle:2 "$@"
}

# _ch_block [NAME=value ...] — REVIEW_CHALLENGE_BLOCK with the inputs the
# earlier steps carry.
_ch_block() {
  e2e_run_block CHALLENGE_DIR="$CH_DIR" PR_NUM=7 CYCLE_NUMBER=2 REVIEW_TREE="$E2E_REPO" USE_PATH_A=1 "$@" \
    commands/review.md REVIEW_CHALLENGE_BLOCK
}

# _ch_gate [NAME=value ...] — the whole Path A gate fence of review.md, which
# holds S1_CHALLENGE_MODE_BLOCK, as Claude Code expands it. Path A is on when
# the user settings opt in and CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is set.
_ch_gate() {
  e2e_run_fence "$@" "$E2E_ACTIVE_PLUGIN/commands/review.md" AGENTTEAMS_GATE_BEGIN
}
# _probe_line — the S1_CHALLENGE line the gate printed, or nothing.
_probe_line() { grep '^S1_CHALLENGE' <<<"$E2E_OUT"; }

_requests() { e2e_expect_equal "$1" "$(e2e_stub_requests "$CH_STUB")" "requests received by stub $CH_STUB"; }
_record() { jq -c "$1" "$E2E_HOME/$CH_RECORDS" 2>/dev/null; }
_logged_state() { sed -n "${1}p" "$(e2e_stub_log "$CH_STUB")" | jq -c ".body.state$2"; }
_no_records() { e2e_expect_equal "no" "$([ -e "$E2E_HOME/$CH_RECORDS" ] && echo yes || echo no)" "a records file exists"; }
_result() { grep "^S1_CHALLENGE_RESULT=$1 " <<<"$E2E_OUT"; }
_ch_stub() { CH_STUB="$1"; e2e_stub_start "$1" "$2"; }

F3_KEPT=$(_f F3 P1 correctness src/a.py:42 LOW kept code-reviewer-verifier "the loop at line 42 reads past the end of items")
CELLS=(
  "$(_f V1 P1 correctness src/a.py:10 HIGH validated code-reviewer-skeptic)"
  "$(_f R1 P2 error-handling src/a.py:20 MEDIUM refined error-handler-inspector-verifier)"
  "$(_f K1 P1 correctness src/a.py:30 LOW kept code-reviewer-verifier)"
  "$(_f U1 P2 tests src/a.py:40 MEDIUM unchallenged test-runner-skeptic)"
)

# ----------------------------------------------------------------- off and its look-alikes

if _want challenge-off; then
  _flow_test_begin "challenge-off"
  _ch_setup challenge-off "a provider is set, paired review is on, and review.challenge is off: the gate prints USE_PATH_A=1 and no S1_CHALLENGE line, the block skips, nothing is sent and no record is written; the script run anyway reports mode-off once per finding with the finding's own confidence and disposition (H5)"
  e2e_stub_start a "$(_noul 0.03)"
  _ch_settings off
  _ch_findings "$F3_KEPT" "${CELLS[0]}"
  _ch_gate CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  e2e_expect_line "USE_PATH_A=1"
  e2e_expect_equal "" "$(_probe_line)" "the probe line"
  _ch_block S1_CHALLENGE=
  e2e_expect_line "S1_CHALLENGE_STATE=skipped"
  e2e_expect_line "REASON=not-active"
  _ch_run
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "S1_CHALLENGE_RESULT=F3 STATE=no-answer REASON=mode-off CONFIDENCE=LOW DISPOSITION=kept"
  e2e_expect_line "S1_CHALLENGE_RESULT=V1 STATE=no-answer REASON=mode-off CONFIDENCE=HIGH DISPOSITION=validated"
  e2e_expect_line "S1_CHALLENGE_MODE=off"
  e2e_expect_no_out "S1_NOTE="
  _requests 0
  _no_records
  e2e_expect_clean_edges
fi

if _want challenge-provider-none; then
  _flow_test_begin "challenge-provider-none"
  _ch_setup challenge-provider-none "no provider, with the site on, paired review on and the stub's address present: the gate prints USE_PATH_A=1 and no S1_CHALLENGE line, and nothing is sent (H5)"
  e2e_stub_start a "$(_noul 0.03)"
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{agentTeams:true, systemOne:{provider:"none",baseUrl:$u,uses:{"review.challenge":"on"}}}')"
  _ch_findings "$F3_KEPT"
  _ch_gate CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  e2e_expect_line "USE_PATH_A=1"
  e2e_expect_equal "" "$(_probe_line)" "the probe line"
  _ch_run
  e2e_expect_line "S1_CHALLENGE_RESULT=F3 STATE=no-answer REASON=provider-none CONFIDENCE=LOW DISPOSITION=kept"
  _requests 0
  _no_records
fi

if _want challenge-not-path-a; then
  _flow_test_begin "challenge-not-path-a"
  _ch_setup challenge-not-path-a "the site on and a provider set: with CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS unset the gate prints USE_PATH_A=0 and no S1_CHALLENGE line; with it set, S1_CHALLENGE=on; the block on a Path B run skips with REASON=path-b and a USE_PATH_A that is neither 0 nor 1 is refused; nothing is sent (H5)"
  e2e_stub_start a "$(_noul 0.03)"
  _ch_settings on
  _ch_findings "$F3_KEPT"
  _ch_gate CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=
  e2e_expect_line "USE_PATH_A=0"
  e2e_expect_equal "" "$(_probe_line)" "the probe line on a Path B run"
  _ch_gate CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  e2e_expect_line "USE_PATH_A=1"
  e2e_expect_equal "S1_CHALLENGE=on" "$(_probe_line)" "the probe line on a Path A run"
  _ch_block S1_CHALLENGE=on USE_PATH_A=0
  e2e_expect_line "S1_CHALLENGE_STATE=skipped"
  e2e_expect_line "REASON=path-b"
  _ch_block S1_CHALLENGE=on USE_PATH_A=
  e2e_expect_equal 2 "$E2E_RC" "exit status for an empty USE_PATH_A"
  e2e_expect_line "STATE=blocked"
  _requests 0
  _no_records
fi

if _want challenge-inside-repo; then
  _flow_test_begin "challenge-inside-repo"
  _ch_setup challenge-inside-repo "the only copy of flow is inside the repository: run from there the script reports settings-refused; the probe and the block skip that copy, so the gate prints no S1_CHALLENGE line, the block reports plugin-missing, and nothing is sent (H5)"
  e2e_stub_start a "$(_noul 0.03)"
  _ch_settings on
  mkdir -p "$E2E_REPO/plugins"
  cp -R "$E2E_PLUGIN_DIR" "$E2E_REPO/plugins/flow"
  E2E_ACTIVE_PLUGIN="$E2E_REPO/plugins/flow"
  _ch_findings "$F3_KEPT"
  _ch_run
  e2e_expect_line "S1_CHALLENGE_RESULT=F3 STATE=no-answer REASON=settings-refused CONFIDENCE=LOW DISPOSITION=kept"
  # The copy is the pull request's own: its mode helper says on and its
  # script claims a note, so a lookup that took it would show.
  printf '#!/bin/sh\necho on\n' > "$E2E_REPO/plugins/flow/bin/flow-s1-mode.sh"
  printf '#!/bin/sh\necho S1_NOTE=F3 planted\n' > "$E2E_REPO/plugins/flow/bin/flow-s1-challenge.sh"
  printf 'plugin for the rest of this scenario: the copy inside the scratch repository, whose bin/flow-s1-mode.sh prints on and whose bin/flow-s1-challenge.sh prints a note\n' | _e2e_art
  _ch_gate CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  e2e_expect_line "USE_PATH_A=1"
  e2e_expect_equal "" "$(_probe_line)" "the probe line"
  _ch_block S1_CHALLENGE=on
  e2e_expect_line "S1_CHALLENGE_STATE=skipped"
  e2e_expect_line "REASON=plugin-missing"
  e2e_expect_no_out "planted"
  _requests 0
fi

# ----------------------------------------------------------------- on mode

if _want challenge-on-dispute-kept; then
  _flow_test_begin "challenge-on-dispute-kept"
  _ch_setup challenge-on-dispute-kept "on mode, a finding the challenger disputed (DISAGREE, LOW kept) and System One p=0.03: the block prints dispute with the finding's own LOW and kept, the note naming the code it checked, and no line that drops the finding; the state carries the problem and the cited window and nothing that names the id, the variant, the disposition or the challenger's answer; the record carries DISAGREE:LOW:kept and the finding's ref (H1, H2, H8)"
  e2e_stub_start a "$(_noul 0.03)"
  _ch_settings on
  _ch_findings "$F3_KEPT"
  _ch_block S1_CHALLENGE=on
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "S1_CHALLENGE_RESULT=F3 STATE=answered ANSWER=dispute P=0.03 ANSWER_CONFIDENCE=0.94 MODEL=jev-1.13.0 CHECKED=src/a.py:12-72@$CH_SHA TRUNCATED=0 CONFIDENCE=LOW DISPOSITION=kept"
  e2e_expect_line "S1_NOTE=F3 System One: the cited code (src/a.py:12-72@$CH_SHA) contradicts this finding (confidence 0.94, jev-1.13.0)."
  e2e_expect_line "S1_CHALLENGE_MODE=on"
  e2e_expect_line "S1_ASKED=1"
  e2e_expect_line "S1_CHALLENGE_SUMMARY=answered:1 no-answer:0 skipped:0"
  e2e_expect_no_out "DROP"
  _requests "$CH_NSH"
  e2e_expect_equal '{"category":"correctness","priority":"P1","problem":"the loop at line 42 reads past the end of items"}' "$(_logged_state 1 .finding)" "the finding in the state sent"
  e2e_expect_equal '[["src/a.py",12,72,42,42]]' "$(_logged_state 1 '.code | map([.path, .start, .end, .cited_start, .cited_end])')" "the code entries sent"
  e2e_expect_equal "false" "$(sed -n 1p "$(e2e_stub_log a)" | jq -c '.body.state | tostring | (contains("F3") or contains("verifier") or contains("kept") or contains("DISAGREE") or contains("LOW") or contains("fix for"))')" "the state names the id, the variant, the disposition, the challenger's answer, the confidence or the fix"
  e2e_expect_equal '{"site":"review.challenge","question":"finding_holds","mode":"on","result":"answered","current":"DISAGREE:LOW:kept","ref":"pr:7/review-cycle:2/F3"}' \
    "$(_record '{site, question, mode, result, current, ref}' | head -n 1)" "the record"
  e2e_expect_clean_edges
fi

if _want challenge-on-each-cell; then
  _flow_test_begin "challenge-on-each-cell"
  _ch_setup challenge-on-each-cell "on mode, one finding for each challenge outcome (AGREE HIGH validated, REFINE MEDIUM refined, DISAGREE LOW kept, none MEDIUM unchallenged), asked once with p=0.03 and once with p=0.97: every line keeps the finding's own confidence and disposition; p=0.03 is a dispute and p=0.97 a support, with the matching note; the record's current names the challenger's answer each disposition stands for (H1, H2, H8)"
  for spec in 'a|0.03|dispute|contradicts this finding' 'b|0.97|support|nothing in the cited code'; do
    IFS='|' read -r stub p answer words <<<"$spec"
    _ch_stub "$stub" "$(_noul "$p")"
    _ch_settings on
    _ch_findings "${CELLS[@]}"
    _ch_run
    for cell in V1:10:HIGH:validated R1:20:MEDIUM:refined K1:30:LOW:kept U1:40:MEDIUM:unchallenged; do
      IFS=: read -r id line conf disp <<<"$cell"
      e2e_expect_line "S1_CHALLENGE_RESULT=$id STATE=answered ANSWER=$answer P=$p ANSWER_CONFIDENCE=0.94 MODEL=jev-1.13.0 CHECKED=src/a.py:$((line > 30 ? line - 30 : 1))-$((line + 30))@$CH_SHA TRUNCATED=0 CONFIDENCE=$conf DISPOSITION=$disp"
      e2e_expect_equal "1" "$(grep -c "^S1_NOTE=$id System One: .*$words" <<<"$E2E_OUT")" "notes for $id saying '$words'"
    done
    e2e_expect_line "S1_CHALLENGE_SUMMARY=answered:4 no-answer:0 skipped:0"
    _requests 4
    e2e_expect_equal '"AGREE:HIGH:validated","REFINE:MEDIUM:refined","DISAGREE:LOW:kept","none:MEDIUM:unchallenged"' "$(_record .current | tail -n 4 | paste -sd, -)" "the current decision recorded for each"
  done
fi

if _want challenge-on-route-unchanged; then
  _flow_test_begin "challenge-on-route-unchanged"
  _ch_setup challenge-on-route-unchanged "on mode, p=0.03 for all four cells: rows built from the block's CONFIDENCE and DISPOSITION and routed through FINDING_ROUTE_BLOCK on someone else's pull request give the same output as the rows without System One, with no LEDGER_WARN; the unchallenged MEDIUM P2 stays counted, so the decision stays REQUEST_CHANGES (H1, H6)"
  e2e_stub_start a "$(_noul 0.03)"
  _ch_settings on
  _ch_findings "${CELLS[@]}"
  _ch_run
  # The rows the session writes, one per finding: id, priority, category and
  # location from the finding set, confidence and disposition from the line.
  : > "$E2E_DIR/rows.s1"
  : > "$E2E_DIR/rows.plain"
  for cell in V1:P1:correctness:10:code-reviewer-skeptic R1:P2:error-handling:20:error-handler-inspector-verifier K1:P1:correctness:30:code-reviewer-verifier U1:P2:tests:40:test-runner-skeptic; do
    IFS=: read -r id pri cat line rev <<<"$cell"
    L=$(_result "$id")
    C=$(sed -n 's/.* CONFIDENCE=\([A-Z]*\) DISPOSITION=\([a-z]*\)$/\1|\2/p' <<<"$L")
    printf '%s|%s|%s|src/a.py:%s|%s|%s\n' "$id" "$pri" "$cat" "$line" "$C" "$rev" >> "$E2E_DIR/rows.s1"
    jq -r --arg id "$id" '.[] | select(.id == $id) | [.id, .priority, .category, .location, .confidence, .disposition, .reviewers[0]] | join("|")' "$CH_DIR/findings.json" >> "$E2E_DIR/rows.plain"
  done
  e2e_expect_equal "$(cat "$E2E_DIR/rows.plain")" "$(cat "$E2E_DIR/rows.s1")" "the rows built from the block's lines, compared with the rows without System One"
  e2e_run_bin bin/flow-finding-route.sh --mode external --pr 7 --input "$E2E_DIR/rows.plain"
  PLAIN="$E2E_OUT"
  e2e_run_bin bin/flow-finding-route.sh --mode external --pr 7 --input "$E2E_DIR/rows.s1"
  e2e_expect_equal "$PLAIN" "$E2E_OUT" "router output on the rows after System One"
  e2e_expect_err_lacks "LEDGER_WARN"
  e2e_expect_line "DECISION=REQUEST_CHANGES"
  e2e_expect_line "NEEDS_INVESTIGATION=K1"
  e2e_expect_line "MARKER_ROWS=V1|P1|correctness|src/a.py:10|open|HIGH|validated,R1|P2|error-handling|src/a.py:20|open|MEDIUM|refined,U1|P2|tests|src/a.py:40|open|MEDIUM|unchallenged"
fi

if _want challenge-on-security; then
  _flow_test_begin "challenge-on-security"
  _ch_setup challenge-on-security "on mode, p=0.03: a finding with category auth, one raised by a security-reviewer variant, and one with an id starting SEC- are asked and recorded like any other, but no note is shown for them (NOTE=withheld); a plain correctness finding beside them gets its note (H4)"
  e2e_stub_start a "$(_noul 0.03)"
  _ch_settings on
  _ch_findings "$(_f A1 P1 auth src/a.py:10 MEDIUM unchallenged code-reviewer-skeptic)" \
    "$(_f S1 P2 correctness src/a.py:20 HIGH validated security-reviewer-verifier)" \
    "$(_f SEC-3 P2 correctness src/a.py:25 HIGH validated code-reviewer-verifier)" \
    "$F3_KEPT"
  _ch_run
  for id in A1 S1 SEC-3; do
    e2e_expect_equal "1" "$(_result "$id" | grep -c ' STATE=answered ANSWER=dispute .* NOTE=withheld CONFIDENCE=')" "answered, dispute, note withheld for $id"
    e2e_expect_no_out "S1_NOTE=$id "
  done
  e2e_expect_out "S1_NOTE=F3 System One: the cited code"
  _requests 4
  e2e_expect_equal "4" "$(_record .site | grep -c review.challenge)" "records written"
fi

if _want challenge-below-threshold; then
  _flow_test_begin "challenge-below-threshold"
  _ch_setup challenge-below-threshold "on mode, p=0.6 (confidence 0.2, below 0.9): no answer, no note; the record keeps the answer with result below-threshold"
  e2e_stub_start a "$(_noul 0.6)"
  _ch_settings on
  _ch_findings "$F3_KEPT"
  _ch_run
  e2e_expect_line "S1_CHALLENGE_RESULT=F3 STATE=no-answer REASON=below-threshold CONFIDENCE=LOW DISPOSITION=kept"
  e2e_expect_no_out "S1_NOTE="
  _requests 1
  e2e_expect_equal '{"result":"below-threshold","p":0.6}' "$(_record '{result, p: .answer.p}')" "the record"
fi

if _want challenge-no-answer; then
  _flow_test_begin "challenge-no-answer"
  _ch_setup challenge-no-answer "on mode, an HTTP 500, a reply slower than timeoutMs, and a body that is not JSON: each is no answer with its reason, no note, and the finding's own confidence and disposition"
  for spec in 'a|http-500|{"status":500,"body":{"detail":"boom"}}' 'b|timeout|{"delay_ms":1500,"body":{}}' 'c|malformed|{"body":"not json"}'; do
    IFS='|' read -r stub reason config <<<"$spec"
    _ch_stub "$stub" "$config"
    _ch_settings on '{"timeoutMs":200}'
    _ch_findings "${CELLS[3]}"
    _ch_run
    e2e_expect_line "S1_CHALLENGE_RESULT=U1 STATE=no-answer REASON=$reason CONFIDENCE=MEDIUM DISPOSITION=unchallenged"
    e2e_expect_no_out "ANSWER="
    e2e_expect_no_out "S1_NOTE="
    _requests 1
  done
fi

if _want challenge-provider-down; then
  _flow_test_begin "challenge-provider-down"
  _ch_setup challenge-provider-down "four findings and a provider that never answers within timeoutMs: two timeouts in a row stop the asking, and the other two are not asked (H12)"
  e2e_stub_start a '{"delay_ms":1500,"body":{}}'
  _ch_settings on '{"timeoutMs":200}'
  _ch_findings "${CELLS[@]}"
  _ch_run
  e2e_expect_line "S1_CHALLENGE_RESULT=R1 STATE=no-answer REASON=timeout CONFIDENCE=MEDIUM DISPOSITION=refined"
  e2e_expect_line "S1_CHALLENGE_RESULT=K1 STATE=skipped REASON=provider-down CONFIDENCE=LOW DISPOSITION=kept"
  e2e_expect_line "S1_CHALLENGE_RESULT=U1 STATE=skipped REASON=provider-down CONFIDENCE=MEDIUM DISPOSITION=unchallenged"
  e2e_expect_line "S1_ASKED=2"
  e2e_expect_line "S1_CHALLENGE_SUMMARY=answered:0 no-answer:2 skipped:2"
  _requests 2
fi

# ----------------------------------------------------------------- shadow

if _want challenge-shadow; then
  _flow_test_begin "challenge-shadow"
  _ch_setup challenge-shadow "shadow mode, a DISAGREE LOW kept finding and p=0.03: the gate prints S1_CHALLENGE=shadow; the block prints no-answer REASON=shadow and no note; the record has mode shadow, current DISAGREE:LOW:kept, the finding's ref and p; the state sent is kept beside the run with the sha256 the record names (H3)"
  e2e_stub_start a "$(_noul 0.03)"
  _ch_settings shadow
  mkdir -p "$E2E_REPO/.flow/runs/r1"
  _ch_findings "$F3_KEPT"
  _ch_gate CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  e2e_expect_equal "S1_CHALLENGE=shadow" "$(_probe_line)" "the probe line"
  _ch_block S1_CHALLENGE=shadow RUN_ID=r1
  e2e_expect_line "S1_CHALLENGE_RESULT=F3 STATE=no-answer REASON=shadow CONFIDENCE=LOW DISPOSITION=kept"
  e2e_expect_line "S1_CHALLENGE_MODE=shadow"
  e2e_expect_no_out "S1_NOTE="
  e2e_expect_no_out "ANSWER="
  _requests "$CH_NSH"
  REC="$E2E_REPO/.flow/runs/r1/system-one.jsonl"
  e2e_expect_equal '{"mode":"shadow","current":"DISAGREE:LOW:kept","ref":"pr:7/review-cycle:2/F3","p":0.03}' \
    "$(head -n 1 "$REC" | jq -c '{mode, current, ref, p: .answer.p}')" "the record"
  KEPT="$E2E_REPO/.flow/runs/r1/system-one-state/challenge-F3.json"
  e2e_expect_equal "$(head -n 1 "$REC" | jq -r .state_sha256)" "$(_e2e_sha256 "$KEPT" 2>/dev/null)" "sha256 of the kept state"
fi

if _want challenge-shadow-follows-mode; then
  _flow_test_begin "challenge-shadow-follows-mode"
  _ch_setup challenge-shadow-follows-mode "shadow mode with a client that answers p=0.02 and exits 0, as it does only in on mode: the script takes the mode from flow-s1-mode.sh, not from the exit status, so no note is shown (H3)"
  e2e_plugin_copy bin/flow-s1.sh "#!/bin/sh
printf '%s\\n' '{\"site\":\"review.challenge\",\"provider\":\"custom\",\"model\":\"jev-1.13.0\",\"truncated\":false,\"answers\":{\"finding_holds\":{\"type\":\"noul\",\"p\":0.02,\"confidence\":0.96}}}'
exit 0"
  e2e_stub_start a "$(_noul 0.02)"
  _ch_settings shadow
  _ch_findings "$F3_KEPT"
  _ch_run
  e2e_expect_line "S1_CHALLENGE_RESULT=F3 STATE=answered ANSWER=dispute P=0.02 ANSWER_CONFIDENCE=0.96 MODEL=jev-1.13.0 CHECKED=src/a.py:12-72@$CH_SHA TRUNCATED=0 CONFIDENCE=LOW DISPOSITION=kept"
  e2e_expect_line "S1_CHALLENGE_MODE=shadow"
  e2e_expect_no_out "S1_NOTE="
fi

if _want challenge-repo-cannot-raise; then
  _flow_test_begin "challenge-repo-cannot-raise"
  _ch_setup challenge-repo-cannot-raise "the user has review.challenge in shadow and the repository sets it on: the gate prints S1_CHALLENGE=shadow, and p=0.03 shows no note; the record's mode is shadow (H11)"
  e2e_stub_start a "$(_noul 0.03)"
  _ch_settings shadow
  mkdir -p "$E2E_REPO/.claude"
  printf '{"systemOne":{"uses":{"review.challenge":"on"}}}\n' > "$E2E_REPO/.claude/settings.flow.json"
  _ch_findings "$F3_KEPT"
  _ch_gate CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  e2e_expect_equal "S1_CHALLENGE=shadow" "$(_probe_line)" "the probe line"
  _ch_run
  e2e_expect_line "S1_CHALLENGE_MODE=shadow"
  e2e_expect_no_out "S1_NOTE="
  _requests 1
  e2e_expect_equal '"shadow"' "$(_record .mode)" "the record's mode"
fi

# ----------------------------------------------------------------- who is asked

if _want challenge-who-is-asked; then
  _flow_test_begin "challenge-who-is-asked"
  _ch_setup challenge-who-is-asked "on mode: a consensus finding, a holdout-validation finding, a finding of a facet re-dispatched on Path B (plain code-reviewer), and a finding raised by a variant and by holdout-validation are not asked; a convention-checker variant finding is; one request (H7)"
  e2e_stub_start a "$(_noul 0.97)"
  _ch_settings on
  _ch_findings "$(_f C1 P1 correctness src/a.py:10 HIGH consensus code-reviewer-skeptic,code-reviewer-verifier)" \
    "$(_f H1 P2 claim-verification src/a.py:20 MEDIUM unchallenged holdout-validation)" \
    "$(_f B1 P2 correctness src/a.py:30 MEDIUM unchallenged code-reviewer)" \
    "$(_f M1 P2 correctness src/a.py:35 MEDIUM unchallenged code-reviewer-skeptic,holdout-validation)" \
    "$(_f N1 P3 conventions src/a.py:40 MEDIUM refined convention-checker-verifier)"
  _ch_run
  e2e_expect_line "S1_CHALLENGE_RESULT=C1 STATE=skipped REASON=consensus CONFIDENCE=HIGH DISPOSITION=consensus"
  e2e_expect_line "S1_CHALLENGE_RESULT=H1 STATE=skipped REASON=not-challenged CONFIDENCE=MEDIUM DISPOSITION=unchallenged"
  e2e_expect_line "S1_CHALLENGE_RESULT=B1 STATE=skipped REASON=not-challenged CONFIDENCE=MEDIUM DISPOSITION=unchallenged"
  e2e_expect_line "S1_CHALLENGE_RESULT=M1 STATE=skipped REASON=not-challenged CONFIDENCE=MEDIUM DISPOSITION=unchallenged"
  e2e_expect_equal "1" "$(_result N1 | grep -c ' STATE=answered ANSWER=support ')" "N1 answered"
  e2e_expect_line "S1_ASKED=1"
  _requests 1
fi

if _want challenge-skips; then
  _flow_test_begin "challenge-skips"
  _ch_setup challenge-skips "on mode: a file-level location, a ../ path, an absolute path, a deleted file, a line past the end, and an id 1bad are each skipped with their reason and nothing sent for them; the finding after them is still asked (H10)"
  e2e_stub_start a "$(_noul 0.97)"
  _ch_settings on
  printf 'OUTSIDE-SECRET\n' > "$E2E_DIR/outside.txt"
  _ch_findings "$(_f F1 P1 correctness src/a.py MEDIUM unchallenged code-reviewer-skeptic)" \
    "$(_f F2 P1 correctness ../outside.txt:1 MEDIUM unchallenged code-reviewer-skeptic)" \
    "$(_f F3 P1 correctness "$E2E_DIR/outside.txt:1" MEDIUM unchallenged code-reviewer-skeptic)" \
    "$(_f F4 P1 correctness src/gone.py:3 MEDIUM unchallenged code-reviewer-skeptic)" \
    "$(_f F5 P1 correctness src/a.py:101 MEDIUM unchallenged code-reviewer-skeptic)" \
    "$(_f 1bad P1 correctness src/a.py:5 MEDIUM unchallenged code-reviewer-skeptic)" \
    "$(_f F7 P1 correctness src/a.py:5 MEDIUM unchallenged code-reviewer-skeptic)"
  _ch_run
  e2e_expect_line "S1_CHALLENGE_RESULT=F1 STATE=skipped REASON=no-line CONFIDENCE=MEDIUM DISPOSITION=unchallenged"
  e2e_expect_line "S1_CHALLENGE_RESULT=F2 STATE=skipped REASON=path-refused CONFIDENCE=MEDIUM DISPOSITION=unchallenged"
  e2e_expect_line "S1_CHALLENGE_RESULT=F3 STATE=skipped REASON=path-refused CONFIDENCE=MEDIUM DISPOSITION=unchallenged"
  e2e_expect_line "S1_CHALLENGE_RESULT=F4 STATE=skipped REASON=file-missing CONFIDENCE=MEDIUM DISPOSITION=unchallenged"
  e2e_expect_line "S1_CHALLENGE_RESULT=F5 STATE=skipped REASON=line-out-of-range CONFIDENCE=MEDIUM DISPOSITION=unchallenged"
  e2e_expect_line "S1_CHALLENGE_RESULT=#6 STATE=skipped REASON=invalid-finding CONFIDENCE=MEDIUM DISPOSITION=unchallenged"
  e2e_expect_equal "1" "$(_result F7 | grep -c ' STATE=answered ')" "F7 answered"
  e2e_expect_line "S1_CHALLENGE_SUMMARY=answered:1 no-answer:0 skipped:6"
  _requests 1
  e2e_expect_equal "0" "$(grep -c 'OUTSIDE-SECRET' "$(e2e_stub_log a)")" "requests carrying the outside file"
  _no_records_for() { e2e_expect_equal "" "$(_record "select(.ref | endswith(\"/$1\")) | .ref")" "a record for $1"; }
  for id in F1 F2 F3 F4 F5; do _no_records_for "$id"; done
fi

if _want challenge-injection; then
  _flow_test_begin "challenge-injection"
  _ch_setup challenge-injection "a problem holding \$(touch pwned), a backtick command, a double quote, a newline and U+2028, run through the block: no command runs, the provider receives the text byte for byte, the output carries none of it, and both shells print the same (H9)"
  e2e_stub_start a "$(_noul 0.97)"
  _ch_settings on
  HOSTILE=$'a $(touch pwned) "quoted"\nsecond line\xe2\x80\xa8after LS `touch pwned2`'
  _ch_findings "$(_f F1 P1 correctness src/a.py:42 HIGH validated code-reviewer-skeptic "$HOSTILE")"
  _ch_block S1_CHALLENGE=on
  e2e_expect_line "S1_ASKED=1"
  e2e_expect_equal "no no" "$([ -e "$E2E_REPO/pwned" ] && echo yes || echo no) $([ -e "$E2E_REPO/pwned2" ] && echo yes || echo no)" "files the text names"
  e2e_expect_equal "$(jq -c --arg h "$HOSTILE" -n '$h')" "$(_logged_state 1 .finding.problem)" "the problem as sent"
  e2e_expect_no_out "quoted"
  _requests "$CH_NSH"
fi

if _want challenge-input-invalid; then
  _flow_test_begin "challenge-input-invalid"
  _ch_setup challenge-input-invalid "a findings file that is not a JSON list stops the step with STATE=blocked and nothing asked; an entry that is not an object, a disposition outside the controlled set, an entry without reviewers and the second of two entries with one id are invalid-finding, while the valid findings around them are still asked; the block refuses a missing CHALLENGE_DIR (H10)"
  e2e_stub_start a "$(_noul 0.97)"
  _ch_settings on
  printf 'not json' > "$CH_DIR/findings.json"
  _ch_run
  e2e_expect_equal 2 "$E2E_RC" "exit status for text that is not JSON"
  e2e_expect_line "STATE=blocked"
  printf '{"id":"F1"}' > "$CH_DIR/findings.json"
  _ch_run
  e2e_expect_equal 2 "$E2E_RC" "exit status for an object"
  _ch_findings '"text"' "$(jq -c '.id = "D1" | .disposition = "disputed"' <<<"$F3_KEPT")" "$(jq -c '.id = "N1" | del(.reviewers)' <<<"$F3_KEPT")" "$F3_KEPT" "$F3_KEPT" "${CELLS[0]}"
  _ch_run
  e2e_expect_equal 0 "$E2E_RC" "exit status with malformed entries"
  e2e_expect_line "S1_CHALLENGE_RESULT=#1 STATE=skipped REASON=invalid-finding CONFIDENCE= DISPOSITION="
  e2e_expect_line "S1_CHALLENGE_RESULT=D1 STATE=skipped REASON=invalid-finding CONFIDENCE=LOW DISPOSITION="
  e2e_expect_line "S1_CHALLENGE_RESULT=N1 STATE=skipped REASON=invalid-finding CONFIDENCE=LOW DISPOSITION=kept"
  e2e_expect_equal "1" "$(_result F3 | grep -c ' STATE=answered ')" "the first F3 answered"
  e2e_expect_line "S1_CHALLENGE_RESULT=F3 STATE=skipped REASON=invalid-finding CONFIDENCE=LOW DISPOSITION=kept"
  e2e_expect_equal "1" "$(_result V1 | grep -c ' STATE=answered ')" "V1 answered"
  e2e_expect_line "S1_ASKED=2"
  _ch_block S1_CHALLENGE=on CHALLENGE_DIR="$E2E_DIR/missing"
  e2e_expect_equal 2 "$E2E_RC" "exit status for a missing CHALLENGE_DIR"
  e2e_expect_line "STATE=blocked"
  _requests 2
fi

# ----------------------------------------------------------------- records and state

if _want challenge-no-run-id; then
  _flow_test_begin "challenge-no-run-id"
  _ch_setup challenge-no-run-id "no run id: the record lands in the per-user state directory of the scenario's HOME and the temporary state file is removed"
  e2e_stub_start a "$(_noul 0.97)"
  _ch_settings on
  mkdir -p "$E2E_DIR/tmp"
  _ch_findings "$F3_KEPT"
  _ch_run TMPDIR="$E2E_DIR/tmp"
  e2e_expect_line "S1_ASKED=1"
  e2e_expect_equal '"pr:7/review-cycle:2/F3"' "$(_record .ref)" "the record's ref in the per-user state directory"
  e2e_expect_equal "" "$(ls -A "$E2E_DIR/tmp")" "files left in TMPDIR"
fi

if _want challenge-merged; then
  _flow_test_begin "challenge-merged"
  _ch_setup challenge-merged "a finding the same-defect step merged, with two locations: one request whose state holds both windows, and CHECKED names both"
  e2e_stub_start a "$(_noul 0.97)"
  _ch_settings on
  _ch_findings "$(jq -c '. + {locations:["src/a.py:42","src/a.py:90"]}' <<<"$F3_KEPT")"
  _ch_run
  e2e_expect_line "S1_CHALLENGE_RESULT=F3 STATE=answered ANSWER=support P=0.97 ANSWER_CONFIDENCE=0.94 MODEL=jev-1.13.0 CHECKED=src/a.py:12-72@$CH_SHA,src/a.py:60-100@$CH_SHA TRUNCATED=0 CONFIDENCE=LOW DISPOSITION=kept"
  _requests 1
  e2e_expect_equal '[["src/a.py",12,72],["src/a.py",60,100]]' "$(_logged_state 1 '.code | map([.path, .start, .end])')" "the code entries sent"
fi
