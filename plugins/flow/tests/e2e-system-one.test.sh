# shellcheck shell=bash
# End-to-end: the System One client (bin/flow-s1.sh) asks a configured
# provider typed questions and prints normalized answers, or says "no answer"
# so its caller keeps today's behavior.
#
# Each scenario runs the shipped script in a scratch repository with its own
# HOME, against stub servers (tests/lib/s1_stub.py) that log every request they
# receive. The providers are real contracts: the TypeSafe stub requires a
# bearer key and names the model that answered; the imajev stub takes no key and
# adds `abstained` and `unknown_probability`. Scenarios that need questions run
# against a copy of the plugin whose system-one/questions.yaml is the fixture
# below; the shipped file has no sites. One artifact per scenario is written to
# $FLOW_E2E_ARTIFACT_DIR. FLOW_E2E_SCENARIOS=a,b runs only the named scenarios.
#
# Ways it can be wrong, written down before the scenarios:
#   S1  provider none still sends a request (a baseUrl being present is taken
#       as permission)
#   S2  the repository's settings choose provider, baseUrl or apiKeyEnv
#   S3  a refusal by cascade-resolve is treated as "no value" and a preset
#       fills in
#   S4  a remote http:// URL, a malformed env var name or an unknown provider
#       still sends
#   S5  TypeSafe with its key unset sends a request anyway
#   S6  the key reaches stdout, stderr or a record
#   S7  noul confidence is taken as p, so a confident "no" falls below the
#       threshold
#   S8  the threshold is looked up by the configured alias, not the model that
#       answered
#   S9  one abstained or low answer and the rest are returned (not
#       all-or-nothing)
#   S10 a missing answer or a wrong-typed answer is passed through
#   S11 truncation counts bytes instead of characters, or splits a multibyte
#       character
#   S12 the timeout applies per socket read, so a slow-drip server holds the
#       caller
#   S13 an HTTP error (429, 5xx, 529) or a malformed body gives exit 0 or a
#       traceback
#   S14 a redirect is followed and the bearer key forwarded (on 302 Python's
#       default opener does this)
#   S15 shadow mode returns the answer
#   S16 a dotted site id is read as a nested settings key, so its mode is
#       always off
#   S17 the repository cannot enable a site
#   S18 records are written through a planted symlink, or into a new
#       directory for a --run-id with no run
#   S19 the state text is written into a record
#   S20 exit 3 prints partial JSON on stdout
#   S21 a "no answer" scenario passes because the stub was never reached, or a
#       stub is left running. Rule: every scenario that expects a request
#       asserts that the stub logged exactly one.

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

S1_BIN="bin/flow-s1.sh"
S1_RECORDS=".claude/flow-state/system-one.jsonl"

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

# Sites used by the scenarios. Every threshold is a hand-picked number the
# scenario's expected result is computed from.
S1_FIXTURE='sites:
  e2e.contract:
    questions:
      q1: {type: noul, instructions: "The ticket is urgent."}
      q2: {type: choice, instructions: "Which team should handle it?", criteria: {x: null, y: null}}
      q3: {type: score, instructions: "How frustrated is the customer?", criteria: [calm, annoyed, angry]}
    thresholds:
      q1: {default: 0.5}
      q2: {default: 0.5}
      q3: {default: 0.5}
  e2e.one:
    questions:
      q1: {type: noul, instructions: "The ticket is urgent."}
    thresholds:
      q1: {default: 0.8}
  e2e.alias:
    questions:
      q1: {type: choice, instructions: "Pick one.", criteria: {a: null, b: null, c: null}}
    thresholds:
      q1: {default: 0.95, models: {jev-1.13.0: 0.5}}
  e2e.pair:
    questions:
      q1: {type: noul, instructions: "The ticket is urgent."}
      q2: {type: noul, instructions: "The ticket is about billing."}
    thresholds:
      q1: {default: 0.5}
      q2: {default: 0.5}
  e2e.nothreshold:
    questions:
      q1: {type: noul, instructions: "The ticket is urgent."}
    thresholds: {}
  review.dedup-a:
    questions:
      q1: {type: noul, instructions: "The ticket is urgent."}
    thresholds:
      q1: {default: 0.5}'

# Replies in each provider's shape. The three answers are the same judgments;
# only the provider-specific fields differ.
TS_CONTRACT='{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.8},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8},"q3":{"type":"score","score":1.6,"legend":{"0":"calm","1":"annoyed","2":"angry"},"probabilities":{"0":0.1,"1":0.2,"2":0.7},"confidence":0.55}},"usage":{"input_tokens":40,"output_tokens":3}}'
IMJ_CONTRACT='{"model":"imajev-4b","answers":{"q1":{"type":"noul","noul":0.8,"unknown_probability":0.02,"abstained":false},"q2":{"type":"choice","choice":"y","probabilities":{"x":0.1,"y":0.9},"confidence":0.8,"unknown_probability":0.02,"abstained":false},"q3":{"type":"score","score":1.6,"legend":{"0":"calm","1":"annoyed","2":"angry"},"probabilities":{"0":0.1,"1":0.2,"2":0.7},"confidence":0.55,"unknown_probability":0.02,"abstained":false}},"usage":{"total_ms":120.5,"input_tokens":40}}'
ONE_CONFIDENT='{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.95}}}'
PAIR_CONFIDENT='{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.95},"q2":{"type":"noul","noul":0.1}}}'

# _s1_setup <scenario> <purpose> [fixture] — scratch repo, and with a third
# argument "fixture", a plugin copy carrying the fixture questions.
_s1_setup() {
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo feature/s1
  [ "${3:-}" = fixture ] && e2e_plugin_copy system-one/questions.yaml "$S1_FIXTURE"
  printf 'Customer: I was charged twice and need the duplicate refunded today.\n' > "$E2E_REPO/state.txt"
}

# _s1_settings <json> — user settings; the JSON is built with jq so the stub
# URLs are quoted correctly.
_s1_settings() { e2e_user_settings "$1"; }

# _s1_ask <site> [extra args] — run the client on the scratch state.
_s1_ask() {
  local site="$1"; shift
  e2e_run_bin "${S1_ENV[@]+"${S1_ENV[@]}"}" "$S1_BIN" ask --site "$site" --state-file state.txt "$@"
}

_jq() { jq -r "$1" <<<"$E2E_OUT"; }

_expect_no_answer() {
  e2e_expect_equal 3 "$E2E_RC" "exit status"
  e2e_expect_equal "" "$E2E_OUT" "stdout"
  e2e_expect_err "flow-s1: no answer: $1"
}

_expect_requests() {
  e2e_expect_equal "$2" "$(e2e_stub_requests "$1")" "requests received by stub $1"
}

_expect_no_traceback() {
  case "$E2E_ERR" in
    *Traceback*) _e2e_result fail "stderr has no Python traceback" ;;
    *) _e2e_result pass "stderr has no Python traceback" ;;
  esac
}

_now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }

# ----------------------------------------------------------------- usage

if _want usage-errors; then
  _flow_test_begin "usage-errors"
  _s1_setup usage-errors "arguments the client must refuse with exit 2: no site, a site id that is not a lowercase dotted name (it is put into a settings expression), a missing state file, an unknown subcommand, a run id that climbs out of .flow/runs"
  S1_ENV=()
  e2e_run_bin "$S1_BIN" ask --state-file state.txt
  e2e_expect_equal 2 "$E2E_RC" "exit status without --site"
  for bad in 'Review.X' 'a..b' '../x' 'a"]|.x'; do
    e2e_run_bin "$S1_BIN" ask --site "$bad" --state-file state.txt
    e2e_expect_equal 2 "$E2E_RC" "exit status for site id '$bad'"
  done
  e2e_run_bin "$S1_BIN" ask --site e2e.one --state-file missing.txt
  e2e_expect_equal 2 "$E2E_RC" "exit status for a missing state file"
  e2e_run_bin "$S1_BIN" tell --site e2e.one --state-file state.txt
  e2e_expect_equal 2 "$E2E_RC" "exit status for an unknown subcommand"
  e2e_run_bin "$S1_BIN" ask --site e2e.one --state-file state.txt --run-id ../x
  e2e_expect_equal 2 "$E2E_RC" "exit status for run id ../x"
  e2e_expect_equal "" "$E2E_OUT" "stdout"
fi

# ----------------------------------------------------------------- provider none

if _want provider-none; then
  _flow_test_begin "provider-none"
  _s1_setup provider-none "provider none with a server address present and the site switched on: no request, no record" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"none",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer provider-none
  _expect_requests a 0
  [ -e "$E2E_HOME/$S1_RECORDS" ] && _e2e_result fail "no record file" || _e2e_result pass "no record file"
fi

if _want provider-unset; then
  _flow_test_begin "provider-unset"
  _s1_setup provider-unset "no user settings at all: the plugin default is provider none" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer provider-none
  _expect_requests a 0
fi

if _want python-missing; then
  _flow_test_begin "python-missing"
  _s1_setup python-missing "python3 without PyYAML (a stub python3 that fails): no answer, no request" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  printf '#!/bin/sh\nexit 1\n' > "$E2E_BIN/python3"; chmod +x "$E2E_BIN/python3"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer python-missing
  _expect_requests a 0
fi

# ----------------------------------------------------------------- settings

if _want repo-settings-ignored; then
  _flow_test_begin "repo-settings-ignored"
  _s1_setup repo-settings-ignored "user settings name stub A and USER_KEY; both repository settings files name stub B and REPO_KEY. The request must go to A with the user's key" fixture
  e2e_stub_start a "{\"bearer\":\"u-secret\",\"body\":$ONE_CONFIDENT}"
  e2e_stub_start b "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,apiKeyEnv:"USER_KEY",uses:{"e2e.one":"on"}}}')"
  mkdir -p "$E2E_REPO/.claude"
  jq -nc --arg u "$(e2e_stub_url b)" '{systemOne:{provider:"custom",baseUrl:$u,apiKeyEnv:"REPO_KEY"}}' > "$E2E_REPO/.claude/settings.flow.json"
  cp "$E2E_REPO/.claude/settings.flow.json" "$E2E_REPO/.claude/settings.flow.local.json"
  S1_ENV=(USER_KEY=u-secret REPO_KEY=r-secret)
  _s1_ask e2e.one
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  _expect_requests a 1
  _expect_requests b 0
  e2e_expect_equal "Bearer u-secret" "$(jq -r '.headers.authorization' "$(e2e_stub_log a)")" "Authorization received by stub a"
  e2e_expect_err "cascade-resolve: WARN: ignoring"
  e2e_expect_no_out "u-secret"
  case "$E2E_ERR" in *u-secret*|*r-secret*) _e2e_result fail "stderr does not contain a key" ;; *) _e2e_result pass "stderr does not contain a key" ;; esac
fi

if _want repo-provider-ignored; then
  _flow_test_begin "repo-provider-ignored"
  _s1_setup repo-provider-ignored "only the repository's settings name a provider and a server: the user never chose one, so no request" fixture
  e2e_stub_start b "{\"body\":$ONE_CONFIDENT}"
  mkdir -p "$E2E_REPO/.claude"
  jq -nc --arg u "$(e2e_stub_url b)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer provider-none
  _expect_requests b 0
fi

if _want cascade-refused; then
  _flow_test_begin "cascade-refused"
  _s1_setup cascade-refused "the plugin itself lives inside the repository, so cascade-resolve refuses to read provider settings: that is no answer, never a preset" fixture
  cp -R "$E2E_ACTIVE_PLUGIN" "$E2E_REPO/plugin-copy"
  E2E_ACTIVE_PLUGIN="$E2E_REPO/plugin-copy"
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer settings-refused
  e2e_expect_err "cascade-resolve: ERROR"
  _expect_requests a 0
fi

if _want insecure-url; then
  _flow_test_begin "insecure-url"
  _s1_setup insecure-url "a remote server over plain http: the key and the state would cross the network unencrypted" fixture
  _s1_settings '{"systemOne":{"provider":"custom","baseUrl":"http://example.invalid:8080","uses":{"e2e.one":"on"}}}'
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer insecure-url
  e2e_expect_err "WARN"
fi

if _want bad-key-env-name; then
  _flow_test_begin "bad-key-env-name"
  _s1_setup bad-key-env-name "an apiKeyEnv that is not an environment variable name" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,apiKeyEnv:"lower-case;x",uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer invalid-settings
  e2e_expect_err "WARN"
  _expect_requests a 0
fi

if _want unknown-provider; then
  _flow_test_begin "unknown-provider"
  _s1_setup unknown-provider "a provider name Flow does not know" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"openai",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer invalid-settings
  e2e_expect_err "WARN"
  _expect_requests a 0
fi

if _want typesafe-no-key; then
  _flow_test_begin "typesafe-no-key"
  _s1_setup typesafe-no-key "TypeSafe requires a key and TYPESAFE_API_KEY is unset" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"typesafe",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer no-api-key
  _expect_requests a 0
fi

if _want imajev-no-auth-header; then
  _flow_test_begin "imajev-no-auth-header"
  _s1_setup imajev-no-auth-header "imajev with apiKeyEnv naming a variable that is set but empty: no Authorization header is sent" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"imajev",baseUrl:$u,apiKeyEnv:"IMJ_KEY",uses:{"e2e.one":"on"}}}')"
  S1_ENV=(IMJ_KEY=)
  _s1_ask e2e.one
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  _expect_requests a 1
  e2e_expect_equal "null" "$(jq -r '.headers.authorization' "$(e2e_stub_log a)")" "Authorization received"
fi

# ----------------------------------------------------------------- contract

if _want typesafe-contract; then
  _flow_test_begin "typesafe-contract"
  _s1_setup typesafe-contract "a noul, a choice and a score against the TypeSafe contract; expected values are the reply's fields, and for the noul |2p-1|" fixture
  e2e_stub_start a "{\"bearer\":\"ts-secret\",\"body\":$TS_CONTRACT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"typesafe",baseUrl:$u,uses:{"e2e.contract":"on"}}}')"
  S1_ENV=(TYPESAFE_API_KEY=ts-secret)
  _s1_ask e2e.contract
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  _expect_requests a 1
  e2e_expect_equal "/v1/systemone" "$(jq -r '.path' "$(e2e_stub_log a)")" "request path"
  e2e_expect_equal "Bearer ts-secret" "$(jq -r '.headers.authorization' "$(e2e_stub_log a)")" "Authorization"
  e2e_expect_equal "jev-1.13.0" "$(jq -r '.body.model' "$(e2e_stub_log a)")" "model sent (the pinned default)"
  e2e_expect_equal "false" "$(jq -r '.body | has("images")' "$(e2e_stub_log a)")" "request has an images field"
  e2e_expect_equal "q1,q2,q3" "$(jq -r '.body.questions | keys | join(",")' "$(e2e_stub_log a)")" "questions sent"
  e2e_expect_equal "0.8 0.6" "$(_jq '"\(.answers.q1.p) \(.answers.q1.confidence)"')" "q1 p and confidence"
  e2e_expect_equal "y 0.8 0.9" "$(_jq '"\(.answers.q2.choice) \(.answers.q2.confidence) \(.answers.q2.probabilities.y)"')" "q2 choice, confidence, p(y)"
  e2e_expect_equal "1.6 0.55 0.7" "$(_jq '"\(.answers.q3.score) \(.answers.q3.confidence) \(.answers.q3.probabilities["2"])"')" "q3 score, confidence, p(level 2)"
  e2e_expect_equal "typesafe jev-1.13.0 false" "$(_jq '"\(.provider) \(.model) \(.truncated)"')" "provider, model, truncated"
  e2e_expect_no_out "ts-secret"
  _jq '.answers' > "$E2E_ROOT/typesafe-answers.json"
fi

if _want imajev-contract; then
  _flow_test_begin "imajev-contract"
  _s1_setup imajev-contract "the same judgments against the imajev contract (no key, abstained and unknown_probability on each answer): with the provider-only field removed, the answers must equal the TypeSafe scenario's" fixture
  e2e_stub_start a "{\"body\":$IMJ_CONTRACT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"imajev",baseUrl:$u,uses:{"e2e.contract":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.contract
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  _expect_requests a 1
  e2e_expect_equal "null" "$(jq -r '.headers.authorization' "$(e2e_stub_log a)")" "Authorization"
  e2e_expect_equal "0.02 0.02 0.02" "$(_jq '"\(.answers.q1.unknown_probability) \(.answers.q2.unknown_probability) \(.answers.q3.unknown_probability)"')" "unknown_probability copied"
  e2e_expect_equal "imajev imajev-4b" "$(_jq '"\(.provider) \(.model)"')" "provider and model"
  if [ -f "$E2E_ROOT/typesafe-answers.json" ]; then
    mine=$(_jq '.answers | map_values(del(.unknown_probability))' | jq -S -c .)
    theirs=$(jq -S -c . "$E2E_ROOT/typesafe-answers.json")
    e2e_expect_equal "$theirs" "$mine" "answers without unknown_probability, compared with typesafe-contract"
  else
    e2e_expect_equal "0.8 0.6" "$(_jq '"\(.answers.q1.p) \(.answers.q1.confidence)"')" "q1 p and confidence"
  fi
fi

if _want noul-confidence; then
  _flow_test_begin "noul-confidence"
  _s1_setup noul-confidence "a confident no: p=0.05 has confidence |2*0.05-1| = 0.9, above the 0.8 threshold" fixture
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.05}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "0.05 0.9" "$(_jq '"\(.answers.q1.p) \(.answers.q1.confidence)"')" "q1 p and confidence"
fi

if _want threshold-by-answering-model; then
  _flow_test_begin "threshold-by-answering-model"
  _s1_setup threshold-by-answering-model "configured model jev-latest, the reply names jev-1.13.0; its threshold (0.5) applies, not the default (0.95), so confidence 0.7 answers" fixture
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"choice","choice":"a","probabilities":{"a":0.7,"b":0.2,"c":0.1},"confidence":0.7}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,model:"jev-latest",uses:{"e2e.alias":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.alias
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "a 0.7 jev-1.13.0" "$(_jq '"\(.answers.q1.choice) \(.answers.q1.confidence) \(.model)"')" "choice, confidence, model"
  e2e_expect_equal "jev-latest" "$(jq -r '.body.model' "$(e2e_stub_log a)")" "model sent"
fi

if _want abstained; then
  _flow_test_begin "abstained"
  _s1_setup abstained "q1 is confident, q2 abstained: the whole call is no answer" fixture
  e2e_stub_start a '{"body":{"model":"imajev-4b","answers":{"q1":{"type":"noul","noul":0.95,"abstained":false},"q2":{"type":"noul","noul":0.5,"unknown_probability":0.9,"abstained":true}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"imajev",baseUrl:$u,uses:{"e2e.pair":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.pair
  _expect_no_answer abstained
  _expect_requests a 1
fi

if _want below-threshold; then
  _flow_test_begin "below-threshold"
  _s1_setup below-threshold "p=0.6 has confidence 0.2, below the 0.8 threshold" fixture
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.6}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer below-threshold
  _expect_requests a 1
fi

if _want missing-answer; then
  _flow_test_begin "missing-answer"
  _s1_setup missing-answer "the reply answers q1 and leaves out q2" fixture
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":0.95}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.pair":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.pair
  _expect_no_answer missing-answer
fi

if _want wrong-type; then
  _flow_test_begin "wrong-type"
  _s1_setup wrong-type "the reply gives p as the string \"0.95\"" fixture
  e2e_stub_start a '{"body":{"model":"jev-1.13.0","answers":{"q1":{"type":"noul","noul":"0.95"}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer malformed
  _expect_no_traceback
fi

if _want state-truncation; then
  _flow_test_begin "state-truncation"
  _s1_setup state-truncation "stateTokenCap 10 allows 40 characters; the state is 100 two-byte characters, so 40 of them (80 bytes) are sent" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,stateTokenCap:10,uses:{"e2e.one":"on"}}}')"
  python3 -c 'import sys; sys.stdout.write("é" * 100)' > "$E2E_REPO/state.txt"
  S1_ENV=()
  _s1_ask e2e.one
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "40 80 true" "$(jq -r '.body.state | "\(length) \(utf8bytelength) \(test("^é+$"))"' "$(e2e_stub_log a)")" "characters, bytes, all é"
  e2e_expect_equal "true" "$(_jq '.truncated')" "truncated"
fi

if _want json-state-truncation; then
  _flow_test_begin "json-state-truncation"
  _s1_setup json-state-truncation "a JSON state over the cap: it is sent as JSON, and only its longest string is shortened, until the serialized state fits in 4 x cap characters" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,stateTokenCap:30,uses:{"e2e.one":"on"}}}')"
  python3 -c 'import json; print(json.dumps({"title": "Charged twice", "body": "x" * 500}))' > "$E2E_REPO/state.json"
  S1_ENV=()
  e2e_run_bin "$S1_BIN" ask --site e2e.one --state-file state.json --state-format json
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "object Charged twice" "$(jq -r '.body.state | "\(type) \(.title)"' "$(e2e_stub_log a)")" "state type and untouched field"
  e2e_expect_equal "true" "$(jq -r '(.body.state | tojson | length) <= 120' "$(e2e_stub_log a)")" "serialized state fits in 120 characters"
  e2e_expect_equal "true" "$(jq -r '(.body.state.body | length) > 50' "$(e2e_stub_log a)")" "the long field is shortened, not dropped"
fi

if _want unknown-site; then
  _flow_test_begin "unknown-site"
  _s1_setup unknown-site "the shipped questions file has no sites, so any site is unknown: no request"
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"any.site":"on"}}}')"
  S1_ENV=()
  _s1_ask any.site
  _expect_no_answer unknown-site
  _expect_requests a 0
fi

if _want no-threshold; then
  _flow_test_begin "no-threshold"
  _s1_setup no-threshold "a question with no threshold entry is a questions-file error, never an implicit 0" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.nothreshold":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.nothreshold
  _expect_no_answer no-threshold
  _expect_requests a 0
fi

# ----------------------------------------------------------------- transport

if _want timeout; then
  _flow_test_begin "timeout"
  _s1_setup timeout "timeoutMs 200 against a server that waits 8 s before replying" fixture
  e2e_stub_start a "{\"delay_ms\":8000,\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,timeoutMs:200,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  t0=$(_now_ms); _s1_ask e2e.one; t1=$(_now_ms)
  _expect_no_answer timeout
  e2e_expect_equal true "$([ $((t1 - t0)) -lt 3000 ] && echo true || echo false)" "returned within 3 s"
fi

if _want timeout-drip; then
  _flow_test_begin "timeout-drip"
  _s1_setup timeout-drip "timeoutMs 500 against a server that sends one byte every 100 ms for 6 s: each read is fast, the whole request is not" fixture
  e2e_stub_start a '{"drip_ms":100,"drip_count":60}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,timeoutMs:500,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  t0=$(_now_ms); _s1_ask e2e.one; t1=$(_now_ms)
  _expect_no_answer timeout
  e2e_expect_equal true "$([ $((t1 - t0)) -lt 3000 ] && echo true || echo false)" "returned within 3 s"
fi

if _want timeout-clamp; then
  _flow_test_begin "timeout-clamp"
  _s1_setup timeout-clamp "timeoutMs 1 is raised to the 200 ms floor, so a reply after 60 ms still answers" fixture
  e2e_stub_start a "{\"delay_ms\":60,\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,timeoutMs:1,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  e2e_expect_equal 0 "$E2E_RC" "exit status"
fi

for code in 500 429 529; do
  if _want "http-$code"; then
    _flow_test_begin "http-$code"
    _s1_setup "http-$code" "the server replies HTTP $code" fixture
    e2e_stub_start a "{\"status\":$code,\"body\":{\"detail\":\"error\"}}"
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
    S1_ENV=()
    _s1_ask e2e.one
    _expect_no_answer "http-$code"
    _expect_requests a 1
    _expect_no_traceback
  fi
done

if _want malformed-json; then
  _flow_test_begin "malformed-json"
  _s1_setup malformed-json "HTTP 200 with a body that is not JSON" fixture
  e2e_stub_start a '{"body":"not json{"}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer malformed
  _expect_requests a 1
  _expect_no_traceback
fi

for code in 307 302; do
  if _want "redirect-$code"; then
    _flow_test_begin "redirect-$code"
    _s1_setup "redirect-$code" "TypeSafe with its key; stub A replies $code to stub B. No redirect is followed, so B never sees the request or the key" fixture
    e2e_stub_start b "{\"body\":$ONE_CONFIDENT}"
    e2e_stub_start a "$(jq -nc --arg l "$(e2e_stub_url b)/v1/systemone" --argjson s "$code" '{status:$s,location:$l}')"
    _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"typesafe",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
    S1_ENV=(TYPESAFE_API_KEY=ts-secret)
    _s1_ask e2e.one
    _expect_no_answer redirect
    _expect_requests a 1
    _expect_requests b 0
  fi
done

if _want connection-refused; then
  _flow_test_begin "connection-refused"
  _s1_setup connection-refused "a loopback port with nothing listening (a stub that was stopped)" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  url=$(e2e_stub_url a)
  _e2e_stop_stubs; sleep 0.2
  _s1_settings "$(jq -nc --arg u "$url" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer connection
  _expect_no_traceback
fi

# ----------------------------------------------------------------- modes and records

if _want shadow-mode; then
  _flow_test_begin "shadow-mode"
  _s1_setup shadow-mode "shadow mode with two confident answers: the request is made and both are recorded, and the caller gets no answer" fixture
  e2e_stub_start a "{\"body\":$PAIR_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.pair":"shadow"}}}')"
  S1_ENV=()
  _s1_ask e2e.pair --current keep
  _expect_no_answer shadow
  _expect_requests a 1
  f="$E2E_HOME/$S1_RECORDS"
  e2e_expect_equal 2 "$( [ -f "$f" ] && wc -l < "$f" | tr -d ' ' || echo 0)" "records written"
  e2e_expect_equal "q1 q2" "$( [ -f "$f" ] && jq -r '.question' "$f" | tr '\n' ' ' | sed 's/ $//')" "questions recorded"
  e2e_expect_equal "keep keep" "$( [ -f "$f" ] && jq -r '.current' "$f" | tr '\n' ' ' | sed 's/ $//')" "current decision recorded"
  e2e_expect_equal "answered answered" "$( [ -f "$f" ] && jq -r '.result' "$f" | tr '\n' ' ' | sed 's/ $//')" "results recorded"
  e2e_expect_equal "shadow" "$( [ -f "$f" ] && jq -r '.mode' "$f" | head -1)" "mode recorded"
fi

if _want on-mode-records; then
  _flow_test_begin "on-mode-records"
  _s1_setup on-mode-records "on mode: the caller gets the answers and each question is recorded" fixture
  e2e_stub_start a "{\"body\":$PAIR_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.pair":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.pair
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal 1 "$(printf '%s\n' "$E2E_OUT" | grep -c .)" "stdout lines"
  f="$E2E_HOME/$S1_RECORDS"
  e2e_expect_equal 2 "$( [ -f "$f" ] && wc -l < "$f" | tr -d ' ' || echo 0)" "records written"
fi

if _want partial-records; then
  _flow_test_begin "partial-records"
  _s1_setup partial-records "shadow mode, q1 answered and q2 abstained: both are recorded, with q1's answer kept" fixture
  e2e_stub_start a '{"body":{"model":"imajev-4b","answers":{"q1":{"type":"noul","noul":0.95,"abstained":false},"q2":{"type":"noul","noul":0.5,"abstained":true}}}}'
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"imajev",baseUrl:$u,uses:{"e2e.pair":"shadow"}}}')"
  S1_ENV=()
  _s1_ask e2e.pair
  _expect_no_answer abstained
  f="$E2E_HOME/$S1_RECORDS"
  e2e_expect_equal "answered abstained" "$( [ -f "$f" ] && jq -r '.result' "$f" | tr '\n' ' ' | sed 's/ $//')" "results recorded"
  e2e_expect_equal "0.95" "$( [ -f "$f" ] && jq -r 'select(.question == "q1") | .answer.p' "$f")" "q1's answer recorded"
fi

if _want mode-off; then
  _flow_test_begin "mode-off"
  _s1_setup mode-off "a provider is configured and the site is not switched on: no request, no record" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer mode-off
  _expect_requests a 0
  [ -e "$E2E_HOME/$S1_RECORDS" ] && _e2e_result fail "no record file" || _e2e_result pass "no record file"
fi

if _want mode-from-repo-settings; then
  _flow_test_begin "mode-from-repo-settings"
  _s1_setup mode-from-repo-settings "the user chose the provider; the repository switches on the dotted site review.dedup-a" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u}}')"
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' '{"systemOne":{"uses":{"review.dedup-a":"on"}}}' > "$E2E_REPO/.claude/settings.flow.json"
  S1_ENV=()
  _s1_ask review.dedup-a
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  _expect_requests a 1
fi

if _want unknown-mode; then
  _flow_test_begin "unknown-mode"
  _s1_setup unknown-mode "a mode value that is not off, shadow or on counts as off" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"yes"}}}')"
  S1_ENV=()
  _s1_ask e2e.one
  _expect_no_answer mode-off
  e2e_expect_err "WARN"
  _expect_requests a 0
fi

if _want records-in-run-dir; then
  _flow_test_begin "records-in-run-dir"
  _s1_setup records-in-run-dir "--run-id names an existing run: records go to that run's directory" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  mkdir -p "$E2E_REPO/.flow/runs/r1"
  S1_ENV=()
  _s1_ask e2e.one --run-id r1
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_file_has ".flow/runs/r1/system-one.jsonl" '"question": "q1"'
  [ -e "$E2E_HOME/$S1_RECORDS" ] && _e2e_result fail "no record in the user state directory" || _e2e_result pass "no record in the user state directory"
fi

if _want run-id-missing-dir; then
  _flow_test_begin "run-id-missing-dir"
  _s1_setup run-id-missing-dir "--run-id names a run that does not exist: records go to the user state directory, and no run directory is created" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  S1_ENV=()
  _s1_ask e2e.one --run-id r2
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  [ -e "$E2E_REPO/.flow/runs/r2" ] && _e2e_result fail "no run directory created" || _e2e_result pass "no run directory created"
  e2e_expect_equal 1 "$( [ -f "$E2E_HOME/$S1_RECORDS" ] && wc -l < "$E2E_HOME/$S1_RECORDS" | tr -d ' ' || echo 0)" "records in the user state directory"
fi

if _want records-symlink-file; then
  _flow_test_begin "records-symlink-file"
  _s1_setup records-symlink-file "the run's record file is a planted symlink to another file: nothing is written through it, and the answer still returns" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  mkdir -p "$E2E_REPO/.flow/runs/r1"
  printf 'victim\n' > "$E2E_DIR/victim.txt"
  before=$(_e2e_sha256 "$E2E_DIR/victim.txt")
  ln -s "$E2E_DIR/victim.txt" "$E2E_REPO/.flow/runs/r1/system-one.jsonl"
  S1_ENV=()
  _s1_ask e2e.one --run-id r1
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "$before" "$(_e2e_sha256 "$E2E_DIR/victim.txt")" "victim file sha256"
  e2e_expect_err "WARN"
fi

if _want records-symlink-dir; then
  _flow_test_begin "records-symlink-dir"
  _s1_setup records-symlink-dir "the run directory itself is a symlink to a directory elsewhere: nothing is written there" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  mkdir -p "$E2E_DIR/elsewhere" "$E2E_REPO/.flow/runs"
  ln -s "$E2E_DIR/elsewhere" "$E2E_REPO/.flow/runs/r1"
  S1_ENV=()
  _s1_ask e2e.one --run-id r1
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "" "$(ls -A "$E2E_DIR/elsewhere")" "files written in the symlink's target"
  e2e_expect_err "WARN"
fi

if _want state-not-recorded; then
  _flow_test_begin "state-not-recorded"
  _s1_setup state-not-recorded "the record holds the state's sha256, never the state" fixture
  e2e_stub_start a "{\"body\":$ONE_CONFIDENT}"
  _s1_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,uses:{"e2e.one":"on"}}}')"
  printf 'S1-MARKER-7f3 customer text\n' > "$E2E_REPO/state.txt"
  S1_ENV=()
  _s1_ask e2e.one
  f="$E2E_HOME/$S1_RECORDS"
  if [ -f "$f" ] && grep -q 'S1-MARKER-7f3' "$f"; then _e2e_result fail "record lacks the state text"; else _e2e_result pass "record lacks the state text"; fi
  e2e_expect_equal "$(_e2e_sha256 "$E2E_REPO/state.txt")" "$( [ -f "$f" ] && jq -r '.state_sha256' "$f")" "state_sha256"
fi

_e2e_stop_stubs
