# shellcheck shell=bash
# End-to-end: in warn mode the Stop hook stops listing a criterion under
# "Missing evidence for:" when System One (site goal.warn-evidence) says its
# recorded evidence shows it holds, and changes nothing else.
#
# Each scenario runs hooks/scripts/flow-goal-stop.sh, the hook Claude Code
# registers for Stop, in a scratch repository in warn mode (the default). Goals
# are created with bin/flow-goal-record.sh --create, so the trust record is
# real, except where a scenario needs an untrusted goal or a run id the schema
# refuses. Evidence is recorded with bin/flow-record-evidence.sh. System One is
# the stub server in tests/lib/s1_stub.py, named in the user's settings as a
# custom provider. Each scenario first runs the hook with no System One
# settings at all; that run is the output "today". One artifact per scenario
# is written to $FLOW_E2E_ARTIFACT_DIR. FLOW_E2E_SCENARIOS=a,b runs only the
# named scenarios.
#
# Ways it can be wrong, written down before the scenarios:
#   W1 the answer's confidence alone decides, so a confident no (p=0.02,
#      confidence 0.96) removes the criterion
#   W2 incomplete_acs is used as the list to ask about, so an untrusted goal's
#      criterion with a command is asked about and removed
#   W3 shadow mode changes what the user sees: flow-s1's "no answer: shadow"
#      reaches stderr, or shadow acts as on
#   W4 off, or no provider, still builds a state and sends it
#   W5 a criterion with no evidence, or only another model's report, is sent
#      and removed on a yes
#   W6 one call for all criteria, so one timeout drops every answer; or the
#      cut to 5 ids comes before the filter, so a sixth criterion never shows
#   W7 the goal file is written, or a verdict recorded, when everything is
#      supported; or the message says "complete"
#   W8 the calls run one after another, holding the stop for N timeouts
#   W9 a repository's own settings switch the site on
#   W10 evidence is read through a symlinked evidence directory, or from a run
#      id that climbs out of .flow/runs
#   W11 block mode drops a criterion from its block on an answer
#   W12 a no-answer case passes because the stub was never reached
#   W13 the manifest numbers only the string ids, so a criterion id that is
#      not a string shifts every index after it: the wrong criterion leaves
#      "Missing evidence for:"
#   W14 the work directory holding the states, with the evidence output, is
#      left in TMPDIR after an on or a shadow run

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

STOP_HOOK="hooks/scripts/flow-goal-stop.sh"
PAYLOAD='{"session_id":"e2e-session","stop_hook_active":false}'
GOAL_FILE=".flow/goals/g-warn.goal.yaml"
RUN_REL=".flow/runs/run-e2e"
RECORDS="$RUN_REL/system-one.jsonl"
HEADER='FLOW_GOAL_INCOMPLETE — stop ALLOWED (stopHookEnforcement=warn)'

# _setup <scenario> <purpose> [stopHookEnforcement] — scratch repo with the run
# directory present, and with a third argument that enforcement mode set.
_setup() {
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo feature/e2e
  mkdir -p "$E2E_REPO/$RUN_REL"
  if [ -n "${3:-}" ]; then
    mkdir -p "$E2E_REPO/.claude"
    jq -nc --arg m "$3" '{flow:{goals:{stopHookEnforcement:$m}}}' > "$E2E_REPO/.claude/settings.flow.json"
  fi
}

# _goal <trusted|untrusted> <criteria json> [run id] — goal g-warn on this
# branch with run <run id> (default run-e2e); criteria are {id, text, cmd?}.
_goal() {
  local src="$E2E_DIR/goal.src.yaml"
  python3 - "$REPO_ROOT/plugins/flow/tests/fixtures/goal/valid.yaml" "$src" "$2" "${3:-run-e2e}" <<'PY' ||
import json, sys, yaml
fixture, dst, crit, run_id = sys.argv[1:5]
with open(fixture, encoding="utf-8") as f:
    g = yaml.safe_load(f)
g["metadata"]["id"] = "g-warn"
g["scope"]["branch"] = "feature/e2e"
g["scope"]["run_id"] = run_id
acs = []
for c in json.loads(crit):
    ac = {"id": c["id"], "text": c["text"], "must_pass": True, "status": "pending",
          "evidence_ref": None, "last_evaluated_at": None, "last_result": None}
    if c.get("cmd"):
        ac["verification_command"] = c["cmd"]
    acs.append(ac)
g["objective"]["acceptance_criteria"] = acs
with open(dst, "w", encoding="utf-8") as f:
    yaml.safe_dump(g, f, sort_keys=False)
PY
  { _flow_assert_fail "$E2E_NAME: could not write the goal source"; return 0; }
  if [ "$1" = trusted ]; then
    # The trust record goes to the scenario's per-user state, where the hook
    # looks: FLOW_STATE_DIR from the caller would put it elsewhere.
    if ! (_e2e_git_env; unset FLOW_STATE_DIR; cd "$E2E_REPO" && CLAUDE_PLUGIN_ROOT="$E2E_ACTIVE_PLUGIN" \
          "$E2E_ACTIVE_PLUGIN/bin/flow-goal-record.sh" --create --goal-file "$src" >/dev/null 2>"$E2E_DIR/create.err"); then
      _flow_assert_fail "$E2E_NAME: flow-goal-record.sh --create failed: $(cat "$E2E_DIR/create.err")"
    fi
  else
    mkdir -p "$E2E_REPO/.flow/goals" && cp "$src" "$E2E_REPO/$GOAL_FILE"
  fi
  printf 'goal criteria (%s): %s\n' "$1" "$2" | _e2e_art
}

# _evidence <id> <proves> [type] — a passing sidecar recorded with
# flow-record-evidence.sh, with a raw output.
_evidence() {
  local f="$E2E_DIR/$1.evidence.yaml"
  cat > "$f" <<YAML
apiVersion: flow.synapti.ai/v1
kind: FlowEvidence
metadata:
  id: $1
  goal: g-warn
  run_id: run-e2e
  created_at: '2026-10-01T10:00:00Z'
evidence:
  type: ${3:-command_result}
  command: 'bash tests/check-$2.sh'
  exit_code: 0
  proves:
    - $2
  limitations:
    - 'checks only the default locale'
YAML
  printf 'ok: %s holds\n' "$2" > "$E2E_DIR/$1.out"
  if ! (_e2e_git_env; unset FLOW_STATE_DIR; cd "$E2E_REPO" && CLAUDE_PLUGIN_ROOT="$E2E_ACTIVE_PLUGIN" \
        "$E2E_ACTIVE_PLUGIN/bin/flow-record-evidence.sh" --run-id run-e2e --evidence-file "$f" \
        --raw-output "$E2E_DIR/$1.out" >/dev/null 2>"$E2E_DIR/evidence.err"); then
    _flow_assert_fail "$E2E_NAME: flow-record-evidence.sh $1 failed: $(cat "$E2E_DIR/evidence.err")"
  fi
  printf 'evidence %s: %s proves %s\n' "$1" "${3:-command_result}" "$2" | _e2e_art
}

_noul() { printf '{"model":"jev-1.13.0","answers":{"evidence_supports":{"type":"noul","noul":%s}}}' "$1"; }
_match() { printf '"\\"id\\": \\"%s\\", \\"text\\""' "$1"; }
_by() { printf '{"match":%s,"body":%s}' "$(_match "$1")" "$(_noul "$2")"; }

# _s1 <stub> <mode> [timeoutMs] — user settings naming stub <stub> as a
# custom provider, with goal.warn-evidence in <mode> ("" leaves uses empty).
_s1() {
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url "$1")" --arg m "$2" --argjson t "${3:-3000}" \
    '{systemOne:({provider:"custom",baseUrl:$u,timeoutMs:$t} + (if $m == "" then {} else {uses:{"goal.warn-evidence":$m}} end))}')"
}

# The hook's temporary files go to the scenario's own TMPDIR, so a check that
# none is left behind sees only this scenario's.
_run() { mkdir -p "$E2E_DIR/tmp"; e2e_run_hook TMPDIR="$E2E_DIR/tmp" "$STOP_HOOK" "$PAYLOAD"; }
# _baseline — the hook with no System One settings at all: today's output.
_baseline() {
  rm -f "$E2E_HOME/.claude/settings.flow.json"
  printf '\n=== baseline: no user settings\n' >> "$E2E_ARTIFACT"
  _run
  BASE_OUT="$E2E_OUT"; BASE_ERR="$E2E_ERR"
}
_expect_today() {
  e2e_expect_equal "$BASE_OUT" "$E2E_OUT" "stdout (equal to the run with no settings)"
  e2e_expect_equal "$BASE_ERR" "$E2E_ERR" "stderr (equal to the run with no settings)"
}
_reason() { jq -r '.reason' <<<"$E2E_OUT"; }
_reason_line() { _reason | grep -F -- "$1" || printf '(no such line)'; }
_records() { if [ -f "$E2E_REPO/$RECORDS" ]; then wc -l < "$E2E_REPO/$RECORDS" | tr -d ' '; else printf 0; fi; }

CRIT_23='[{"id":"AC1","text":"The search runs.","cmd":"true"},{"id":"AC2","text":"The search results read well."},{"id":"AC3","text":"The error page names the cause."}]'
CRIT_2='[{"id":"AC1","text":"The search runs.","cmd":"true"},{"id":"AC2","text":"The search results read well."}]'

# ----------------------------------------------------------------- off and shadow

if _want warn-off; then
  _flow_test_begin "goal.warn-evidence off, or on with no provider: today's output, nothing sent (W4)"
  _setup warn-off "AC2 and AC3 have sidecars and a stub that would say yes; first a provider with the site unset, then with it off, then the site on with no provider"
  _goal trusted "$CRIT_23"
  _evidence ev-ac2 AC2
  _evidence ev-ac3 AC3
  e2e_stub_start a "{\"body\":$(_noul 0.99)}"
  _baseline
  e2e_expect_line "$(jq -nc --arg r "$HEADER
Active goal: g-warn
Missing evidence for: AC2, AC3
Next action: /flow:goal evaluate g-warn
To enforce, set flow.goals.stopHookEnforcement to block." '{decision:"approve", reason:$r}')"
  _s1 a ""
  _run; _expect_today
  _s1 a off
  _run; _expect_today
  e2e_user_settings '{"systemOne":{"uses":{"goal.warn-evidence":"on"}}}'
  _run; _expect_today
  e2e_expect_equal 0 "$(e2e_stub_requests a)" "requests received by stub a"
  e2e_expect_equal 0 "$(_records)" "records"
  e2e_expect_equal "" "$(ls -A "$E2E_DIR/tmp")" "temporary files left behind"
  e2e_expect_clean_edges
fi

if _want warn-shadow; then
  _flow_test_begin "goal.warn-evidence shadow: today's output, and the answer recorded beside the decision (W3)"
  _setup warn-shadow "AC2 has a sidecar; System One says p=0.99 in shadow mode"
  _goal trusted "$CRIT_2"
  _evidence ev-ac2 AC2
  e2e_stub_start a "{\"body\":$(_noul 0.99)}"
  _baseline
  _s1 a shadow
  _run
  _expect_today
  e2e_expect_equal 1 "$(e2e_stub_requests a)" "requests received by stub a"
  e2e_expect_equal 1 "$(_records)" "records"
  e2e_expect_equal "goal.warn-evidence evidence_supports shadow answered 0.99" \
    "$(jq -r '"\(.site) \(.question) \(.mode) \(.result) \(.answer.p)"' "$E2E_REPO/$RECORDS")" "record"
  e2e_expect_equal "missing-evidence goal=g-warn criterion=AC2" "$(jq -r .current "$E2E_REPO/$RECORDS")" "record current"
  e2e_expect_equal "goal:g-warn/AC2" "$(jq -r .ref "$E2E_REPO/$RECORDS")" "record ref"
  e2e_expect_equal "" "$(ls -A "$E2E_DIR/tmp")" "temporary files left behind (W14)"
  e2e_expect_clean_edges
fi

# ----------------------------------------------------------------- on

if _want warn-on-supported; then
  _flow_test_begin "goal.warn-evidence on: a supported criterion moves to its own line; a confident no stays (W1)"
  _setup warn-on-supported "AC2 and AC3 have sidecars; System One answers AC2 p=0.99 and AC3 p=0.02 (a confident no, confidence 0.96)"
  _goal trusted "$CRIT_23"
  _evidence ev-ac2 AC2
  _evidence ev-ac3 AC3
  e2e_stub_start a "{\"body\":$(_noul 0.5),\"by_state\":[$(_by AC2 0.99),$(_by AC3 0.02)]}"
  _s1 a on
  _run
  e2e_expect_equal "Missing evidence for: AC3" "$(_reason_line 'Missing evidence for:')" "missing-evidence line"
  e2e_expect_equal "Supported by recorded evidence (System One; not a verdict): AC2" "$(_reason_line 'Supported by recorded evidence')" "supported line"
  e2e_expect_out '"decision":"approve"'
  e2e_expect_equal "$(_reason)" "$E2E_ERR" "stderr (the same text as the reason)"
  e2e_expect_equal 2 "$(e2e_stub_requests a)" "requests received by stub a"
  e2e_expect_equal "0.02" "$(jq -r 'select(.ref == "goal:g-warn/AC3") | .answer.p' "$E2E_REPO/$RECORDS")" "AC3 record p"
  e2e_expect_equal "" "$(ls -A "$E2E_DIR/tmp")" "temporary files left behind (W14)"
  e2e_expect_clean_edges
fi

if _want warn-on-confident-no; then
  _flow_test_begin "goal.warn-evidence on: a confident no keeps the criterion reported (W1)"
  _setup warn-on-confident-no "AC2 has a sidecar; System One says p=0.02"
  _goal trusted "$CRIT_2"
  _evidence ev-ac2 AC2
  e2e_stub_start a "{\"body\":$(_noul 0.02)}"
  _baseline
  _s1 a on
  _run
  _expect_today
  e2e_expect_no_out 'Supported by recorded evidence'
  e2e_expect_equal "answered 0.02" "$(jq -r '"\(.result) \(.answer.p)"' "$E2E_REPO/$RECORDS")" "record"
  e2e_expect_clean_edges
fi

if _want warn-on-all-supported; then
  _flow_test_begin "goal.warn-evidence on: all supported allows the stop without a verdict or a write (W7)"
  _setup warn-on-all-supported "AC1's command passes; AC2 and AC3 have sidecars and System One says p=0.99 to both"
  _goal trusted "$CRIT_23"
  _evidence ev-ac2 AC2
  _evidence ev-ac3 AC3
  GOAL_SHA=$(_e2e_sha256 "$E2E_REPO/$GOAL_FILE")
  EVIDENCE_BEFORE=$(find "$E2E_REPO/$RUN_REL/evidence" -type f | LC_ALL=C sort | tr '\n' ' ')
  e2e_stub_start a "{\"body\":$(_noul 0.99)}"
  _s1 a on
  _run
  e2e_expect_line '{"decision":"approve","reason":"FLOW_GOAL_EVIDENCE_RECORDED — stop ALLOWED; recorded evidence supports AC2, AC3 (System One, not a verdict); run /flow:goal evaluate g-warn"}'
  e2e_expect_no_out 'complete'
  e2e_expect_equal "" "$E2E_ERR" "stderr"
  e2e_expect_equal "$GOAL_SHA" "$(_e2e_sha256 "$E2E_REPO/$GOAL_FILE")" "goal file sha256 (unchanged)"
  e2e_expect_equal "$EVIDENCE_BEFORE" "$(find "$E2E_REPO/$RUN_REL/evidence" -type f | LC_ALL=C sort | tr '\n' ' ')" "evidence files (unchanged)"
  e2e_expect_equal absent "$([ -e "$E2E_REPO/$RUN_REL/last-verdict.json" ] && echo present || echo absent)" "last-verdict.json"
  e2e_expect_clean_edges
fi

if _want warn-no-answer; then
  _flow_test_begin "goal.warn-evidence on: every kind of no answer gives today's output, after reaching the stub (W12)"
  _setup warn-no-answer "AC2 has a sidecar. One run each: a reply slower than timeoutMs, HTTP 500, a reply that is not JSON, an abstention, and p=0.9 (confidence 0.8, below the 0.9 threshold)"
  _goal trusted "$CRIT_2"
  _evidence ev-ac2 AC2
  _baseline
  i=0
  for cfg in "{\"delay_ms\":1500,\"body\":$(_noul 0.99)}" '{"status":500,"body":{"detail":"boom"}}' '{"body":"not json"}' \
             '{"body":{"model":"imajev-4b","answers":{"evidence_supports":{"type":"noul","noul":0.99,"abstained":true}}}}' \
             "{\"body\":$(_noul 0.9)}"; do
    i=$((i + 1))
    e2e_stub_start "n$i" "$cfg"
    _s1 "n$i" on 300
    _run
    _expect_today
    e2e_expect_equal 1 "$(e2e_stub_requests "n$i")" "requests received by stub n$i"
  done
  e2e_expect_equal "timeout http-500 malformed abstained below-threshold" "$(jq -r .result "$E2E_REPO/$RECORDS" | tr '\n' ' ' | sed 's/ $//')" "record results"
  e2e_expect_clean_edges
fi

if _want warn-on-no-evidence; then
  _flow_test_begin "goal.warn-evidence on: no evidence, or only another model's report, is not asked about (W5)"
  _setup warn-on-no-evidence "AC2 has no sidecar; AC3's only sidecar is an llm_judge_report; System One would say p=0.99"
  _goal trusted "$CRIT_23"
  _evidence ev-ac3 AC3 llm_judge_report
  e2e_stub_start a "{\"body\":$(_noul 0.99)}"
  _baseline
  _s1 a on
  _run
  _expect_today
  e2e_expect_equal "Missing evidence for: AC2, AC3" "$(_reason_line 'Missing evidence for:')" "missing-evidence line"
  e2e_expect_equal 0 "$(e2e_stub_requests a)" "requests received by stub a"
  e2e_expect_clean_edges
fi

if _want warn-on-only-no-command; then
  _flow_test_begin "goal.warn-evidence on: a criterion with a command is never asked about (W2)"
  _setup warn-on-only-no-command "an untrusted goal: AC1 has a command that is not executed, AC2 has none; both have sidecars; System One says p=0.99"
  _goal untrusted "$CRIT_2"
  _evidence ev-ac1 AC1
  _evidence ev-ac2 AC2
  e2e_stub_start a "{\"body\":$(_noul 0.99)}"
  _s1 a on
  _run
  e2e_expect_equal 1 "$(e2e_stub_requests a)" "requests received by stub a"
  e2e_expect_equal "AC2" "$(jq -r '.body.state.criterion.id' "$(e2e_stub_log a)")" "criterion asked about"
  e2e_expect_equal "Missing evidence for: AC1" "$(_reason_line 'Missing evidence for:')" "missing-evidence line"
  e2e_expect_equal "Supported by recorded evidence (System One; not a verdict): AC2" "$(_reason_line 'Supported by recorded evidence')" "supported line"
  e2e_expect_out 'not executed because goal g-warn is not trusted'
  e2e_expect_clean_edges
fi

if _want warn-on-partial; then
  _flow_test_begin "goal.warn-evidence on: one criterion answered and one timed out (W6)"
  _setup warn-on-partial "AC2 and AC3 have sidecars; AC2 is answered p=0.99, AC3's reply comes after timeoutMs"
  _goal trusted "$CRIT_23"
  _evidence ev-ac2 AC2
  _evidence ev-ac3 AC3
  e2e_stub_start a "{\"body\":$(_noul 0.99),\"by_state\":[{\"match\":$(_match AC3),\"delay_ms\":1500}]}"
  _s1 a on 300
  _run
  e2e_expect_equal "Missing evidence for: AC3" "$(_reason_line 'Missing evidence for:')" "missing-evidence line"
  e2e_expect_equal "Supported by recorded evidence (System One; not a verdict): AC2" "$(_reason_line 'Supported by recorded evidence')" "supported line"
  e2e_expect_clean_edges
fi

if _want warn-on-many; then
  _flow_test_begin "goal.warn-evidence on: the cut to five ids comes after the supported ones leave (W6)"
  _setup warn-on-many "AC2 to AC8 have no command and a sidecar each; System One supports AC2 and AC3 and says p=0.02 to the rest"
  _goal trusted '[{"id":"AC1","text":"runs","cmd":"true"},{"id":"AC2","text":"c2"},{"id":"AC3","text":"c3"},{"id":"AC4","text":"c4"},{"id":"AC5","text":"c5"},{"id":"AC6","text":"c6"},{"id":"AC7","text":"c7"},{"id":"AC8","text":"c8"}]'
  for n in 2 3 4 5 6 7 8; do _evidence "ev-ac$n" "AC$n"; done
  _baseline
  e2e_expect_equal "Missing evidence for: AC2, AC3, AC4, AC5, AC6" "$(_reason_line 'Missing evidence for:')" "missing-evidence line today"
  e2e_stub_start a "{\"body\":$(_noul 0.02),\"by_state\":[$(_by AC2 0.99),$(_by AC3 0.99)]}"
  _s1 a on
  _run
  e2e_expect_equal "Missing evidence for: AC4, AC5, AC6, AC7, AC8" "$(_reason_line 'Missing evidence for:')" "missing-evidence line"
  e2e_expect_equal "Supported by recorded evidence (System One; not a verdict): AC2, AC3" "$(_reason_line 'Supported by recorded evidence')" "supported line"
  e2e_expect_equal 7 "$(e2e_stub_requests a)" "requests received by stub a"
  e2e_expect_clean_edges
fi

if _want warn-on-parallel; then
  _flow_test_begin "goal.warn-evidence on: the calls run at the same time (W8)"
  _setup warn-on-parallel "AC2, AC3 and AC4 have sidecars; every reply waits 3000 ms, timeoutMs 4500: one after another the three calls would add at least 9 s to the hook's run with no settings from the waits alone (each call also spends about 2 s starting the client), at the same time about one wait and one start"
  _goal trusted '[{"id":"AC1","text":"runs","cmd":"true"},{"id":"AC2","text":"c2"},{"id":"AC3","text":"c3"},{"id":"AC4","text":"c4"}]'
  for n in 2 3 4; do _evidence "ev-ac$n" "AC$n"; done
  t0=$(python3 -c 'import time; print(int(time.time() * 1000))')
  _baseline
  t1=$(python3 -c 'import time; print(int(time.time() * 1000))')
  e2e_stub_start a "{\"delay_ms\":3000,\"body\":$(_noul 0.99)}"
  _s1 a on 4500
  t2=$(python3 -c 'import time; print(int(time.time() * 1000))')
  _run
  t3=$(python3 -c 'import time; print(int(time.time() * 1000))')
  printf 'wall time: %s ms with no settings, %s ms with three delayed calls (not compared between runs)\n' "$((t1 - t0))" "$((t3 - t2))" >> "$E2E_ARTIFACT"
  e2e_expect_out 'FLOW_GOAL_EVIDENCE_RECORDED'
  e2e_expect_out 'supports AC2, AC3, AC4'
  if [ $((t3 - t2)) -lt $((t1 - t0 + 9000)) ]; then
    _e2e_result pass "the three calls added less than 9 s (one after another their waits alone add 9 s)"
  else
    _e2e_result fail "the three calls added less than 9 s (one after another their waits alone add 9 s)"
  fi
  e2e_expect_clean_edges
fi

if _want warn-on-non-string-id; then
  _flow_test_begin "goal.warn-evidence on: a criterion id that is not a string gives today's output (W13)"
  _setup warn-on-non-string-id "a goal written by hand: criterion 7 (an unquoted number) and AC3, neither with a command; only AC3 has a sidecar; System One says p=0.99"
  _goal untrusted '[{"id":7,"text":"The search results read well."},{"id":"AC3","text":"The error page names the cause."}]'
  _evidence ev-ac3 AC3
  e2e_stub_start a "{\"body\":$(_noul 0.99)}"
  _baseline
  e2e_expect_equal "Missing evidence for: 7, AC3" "$(_reason_line 'Missing evidence for:')" "missing-evidence line today"
  _s1 a on
  _run
  _expect_today
  e2e_expect_equal 0 "$(e2e_stub_requests a)" "requests received by stub a"
  e2e_expect_equal "" "$(ls -A "$E2E_DIR/tmp")" "temporary files left behind"
  e2e_expect_clean_edges
fi

# ----------------------------------------------------------------- refusals

if _want warn-on-symlinked-evidence; then
  _flow_test_begin "goal.warn-evidence on: a symlinked evidence directory is not read (W10)"
  _setup warn-on-symlinked-evidence "the run's evidence directory is a symlink to a directory holding a passing sidecar for AC2; System One would say p=0.99"
  _goal trusted "$CRIT_2"
  _evidence ev-ac2 AC2
  mv "$E2E_REPO/$RUN_REL/evidence" "$E2E_DIR/outside-evidence"
  ln -s "$E2E_DIR/outside-evidence" "$E2E_REPO/$RUN_REL/evidence"
  e2e_stub_start a "{\"body\":$(_noul 0.99)}"
  _baseline
  _s1 a on
  _run
  _expect_today
  e2e_expect_equal 0 "$(e2e_stub_requests a)" "requests received by stub a"
  e2e_expect_clean_edges
fi

if _want warn-on-bad-run-id; then
  _flow_test_begin "goal.warn-evidence on: a run id that climbs out of .flow/runs is not read (W10)"
  _setup warn-on-bad-run-id "a goal written by hand whose run id is ../outside, where a passing sidecar for AC2 sits; System One would say p=0.99"
  _goal untrusted '[{"id":"AC2","text":"The search results read well."}]' "../outside"
  _evidence ev-ac2 AC2
  mkdir -p "$E2E_REPO/.flow/outside" && cp -R "$E2E_REPO/$RUN_REL/evidence" "$E2E_REPO/.flow/outside/evidence"
  e2e_stub_start a "{\"body\":$(_noul 0.99)}"
  _baseline
  _s1 a on
  _run
  _expect_today
  e2e_expect_equal 0 "$(e2e_stub_requests a)" "requests received by stub a"
  e2e_expect_clean_edges
fi

if _want warn-repo-on; then
  _flow_test_begin "goal.warn-evidence: a repository's settings cannot switch the site on (W9)"
  _setup warn-repo-on "the user's settings name a provider and leave the site unset; the repository's settings set it on"
  _goal trusted "$CRIT_2"
  _evidence ev-ac2 AC2
  e2e_stub_start a "{\"body\":$(_noul 0.99)}"
  _baseline
  mkdir -p "$E2E_REPO/.claude"
  printf '{"systemOne":{"uses":{"goal.warn-evidence":"on"}}}\n' > "$E2E_REPO/.claude/settings.flow.json"
  _s1 a ""
  _run
  _expect_today
  e2e_expect_equal 0 "$(e2e_stub_requests a)" "requests received by stub a"
  e2e_expect_clean_edges
fi

# ----------------------------------------------------------------- other modes

if _want warn-fallback-mode; then
  _flow_test_begin "goal.warn-evidence on: an unknown enforcement mode falls back to warn with the same change"
  _setup warn-fallback-mode "stopHookEnforcement is 'bogus'; AC2 and AC3 have sidecars; System One supports AC2 only" bogus
  _goal trusted "$CRIT_23"
  _evidence ev-ac2 AC2
  _evidence ev-ac3 AC3
  e2e_stub_start a "{\"body\":$(_noul 0.02),\"by_state\":[$(_by AC2 0.99)]}"
  _s1 a on
  _run
  e2e_expect_out 'FLOW_GOAL_CONFIG_FALLBACK_WARN'
  e2e_expect_equal "Missing evidence for: AC3" "$(_reason_line 'Missing evidence for:')" "missing-evidence line"
  e2e_expect_equal "Supported by recorded evidence (System One; not a verdict): AC2" "$(_reason_line 'Supported by recorded evidence')" "supported line"
  e2e_expect_clean_edges
fi

if _want warn-block-untouched; then
  _flow_test_begin "goal.warn-evidence on: block mode still blocks on a command-less criterion and asks nothing (W11)"
  _setup warn-block-untouched "stopHookEnforcement is block; AC2 has a sidecar; System One would say p=0.99" block
  _goal trusted "$CRIT_2"
  _evidence ev-ac2 AC2
  e2e_stub_start a "{\"body\":$(_noul 0.99)}"
  _s1 a on
  _run
  e2e_expect_out '"decision":"block"'
  e2e_expect_equal "Missing evidence for: AC2" "$(_reason_line 'Missing evidence for:')" "missing-evidence line"
  e2e_expect_equal 0 "$(e2e_stub_requests a)" "requests received by stub a"
  e2e_expect_clean_edges
fi
