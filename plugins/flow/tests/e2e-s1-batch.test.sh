# shellcheck shell=bash
# End-to-end: System One asks about the items of one goal stop or one review
# in as few requests as the provider's size limit allows (bin/flow-s1.sh
# ask-many), and each caller that asks that way (the goal Stop hooks and
# review.confidence) gets the same per-item answers it got one request at a
# time.
#
# Each scenario runs the shipped scripts in a scratch repository with its own
# HOME, against stub servers (tests/lib/s1_stub.py) that log every request, so
# a scenario counts the requests a call made. The questions are the shipped
# system-one/questions.yaml: the threshold a scenario expects is the one Flow
# ships. One artifact per scenario is written to $FLOW_E2E_ARTIFACT_DIR.
# FLOW_E2E_SCENARIOS=a,b runs only the named scenarios.
#
# Ways it can be wrong, written down before the scenarios:
#   B1  answers are attached to items by their position in the reply, not by
#       key, so a reply that lists them in another order swaps two items
#   B2  the packing bound is off by one (> for >=) or lets an 11th item in
#   B3  one bad answer (malformed, missing, abstained) fails every item of
#       the request, as `ask` does for a site with several questions
#   B4  a record's state_sha256 is the request's digest, so batched records
#       cannot be joined to the records of the same item asked alone
#   B5  the threshold is looked up by the item's key instead of the site's
#       question, so the default (or an error) applies
#   B6  a request that fails as a whole leaves some of its items answered, or
#       fails the items of another request
#   B7  batching is chosen by a repository's settings, or starts when the
#       user has not chosen it
#   B8  an item too large to share a request is shortened inside one, or
#       dropped
#   B9  the layout sent is not the one written down before the measurement:
#       the pointer words, the shape of the state and of each question
#   B10 an item whose state cannot be read fails the call, or a bad items
#       file sends a request
#   B11 a site that keeps one request per item is asked together

# Only tests/run.sh runs this file: it sets REPO_ROOT and loads assert.sh. Run
# any other way, the file stops here with a non-zero exit.
{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

S1_BIN="bin/flow-s1.sh"
S1_RECORDS=".claude/flow-state/system-one.jsonl"

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

_b_setup() {
  if [ -n "${CI:-}" ]; then
    { printf 'progress %s %s\n' "$(date -u +%H:%M:%S)" "$1" >&3; } 2>/dev/null
  fi
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo feature/s1-batch
  mkdir -p "$E2E_REPO/items"
}

# _item <key> <text> — an item state, as the goal sites send one: a criterion
# and its evidence.
_item() {
  jq -nc --arg k "$1" --arg t "$2" '{criterion: {id: $k, text: $t}, evidence: []}' > "$E2E_REPO/items/$1.json"
}

# _items_file <key>... — the items file for those items, in that order.
_items_file() {
  local k args=()
  for k in "$@"; do args+=("$k"); done
  printf '%s\n' "${args[@]}" | jq -R . | jq -sc --arg d "$E2E_REPO/items" \
    '{items: map({key: ., state_file: ($d + "/" + . + ".json"), current: ("now=" + .), ref: ("test:" + .)})}' \
    > "$E2E_REPO/items.json"
}

# _settings <stub> <site> <mode> [batch] [extra jq object] — user settings.
_settings() {
  local extra="${5:-}"
  [ -n "$extra" ] || extra='{}'
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url "$1")" --arg s "$2" --arg m "$3" --arg b "${4:-}" \
    --argjson x "$extra" \
    '{systemOne: ({provider: "custom", baseUrl: $u, uses: {($s): $m}} + (if $b == "" then {} else {batch: $b} end) + $x)}')"
}

_ask_many() {
  local site="$1"; shift
  e2e_run_bin "$S1_BIN" ask-many --site "$site" --items-file items.json "$@"
}

# _line <key> <jq> — a field of the output line for <key>.
_line() { jq -r --arg k "$1" "select(.key == \$k) | $2" <<<"$E2E_OUT"; }

_expect_requests() {
  e2e_expect_equal "$2" "$(e2e_stub_requests "$1")" "requests received by stub $1"
}

# _request <stub> <n> <jq> — a field of the n-th request (0-based) the stub logged.
_request() { sed -n "$(($2 + 1))p" "$(e2e_stub_log "$1")" | jq -c "$3"; }

# _site_instructions <site> — the shipped instructions of the site's one question.
_site_instructions() {
  python3 -c 'import sys, yaml; d = yaml.safe_load(open(sys.argv[1]))["sites"][sys.argv[2]]["questions"]; print(next(iter(d.values()))["instructions"])' \
    "$E2E_ACTIVE_PLUGIN/system-one/questions.yaml" "$1"
}

p_answer() { jq -nc --argjson p "$1" '{type: "noul", noul: $p}'; }

# ----------------------------------------------------------------- the switch

if _want batch-off; then
  _flow_test_begin "batch-off"
  _b_setup batch-off "with systemOne.batch unset, set to off, or set on only in the repository's settings, ask-many exits 4 and sends nothing, so the caller asks one item at a time as before (B7)"
  e2e_stub_start a '{"per_item": {"default": {"type": "noul", "noul": 0.9}}}'
  _item AC1 "one"; _item AC2 "two"; _items_file AC1 AC2
  _settings a goal.judge on
  _ask_many goal.judge
  e2e_expect_equal 4 "$E2E_RC" "exit status with batch unset"
  e2e_expect_err "flow-s1: batch off"
  _settings a goal.judge on off
  _ask_many goal.judge
  e2e_expect_equal 4 "$E2E_RC" "exit status with batch off"
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' '{"systemOne": {"batch": "items-in-state"}}' > "$E2E_REPO/.claude/settings.flow.json"
  printf '%s\n' '{"systemOne": {"batch": "items-in-state"}}' > "$E2E_REPO/.claude/settings.flow.local.json"
  _ask_many goal.judge
  e2e_expect_equal 4 "$E2E_RC" "exit status with batch set only in the repository's settings"
  _expect_requests a 0
fi

# ----------------------------------------------------------------- layouts

if _want layout-state; then
  _flow_test_begin "layout-state"
  _b_setup layout-state "items-in-state: one request whose state is {items: {key: item}} and whose questions, keyed by item, start with the pointer words written down before the measurement; answers come back by key, whatever order the reply lists them in (B1, B9)"
  # The stub's reply lists AC1 before AC3; the input lists AC3 first.
  e2e_stub_start a "$(jq -nc --argjson a "$(p_answer 0.1)" --argjson b "$(p_answer 0.9)" \
    '{per_item: {answers: [{match: "\"AC1\"", answer: $a}, {match: "\"AC3\"", answer: $b}]}}')"
  _item AC3 "three"; _item AC1 "one"; _items_file AC3 AC1
  _settings a goal.judge on items-in-state
  _ask_many goal.judge
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  _expect_requests a 1
  e2e_expect_equal "AC3 AC1" "$(jq -r .key <<<"$E2E_OUT" | tr '\n' ' ' | sed 's/ $//')" "output lines in input order"
  # goal.judge's shipped threshold is 0.5: |2p - 1| is 0.8 for both p.
  e2e_expect_equal "answered 0.9" "$(_line AC3 '.result + " " + (.answer.p | tostring)')" "AC3 is answered with its own p"
  e2e_expect_equal "answered 0.1" "$(_line AC1 '.result + " " + (.answer.p | tostring)')" "AC1 is answered with its own p"
  # The stub logs a request with its keys sorted, so the order sent is not seen here.
  e2e_expect_equal '["AC1","AC3"]' "$(_request a 0 '.body.state.items | keys')" "the state holds both items under their keys"
  e2e_expect_equal "$(jq -c . "$E2E_REPO/items/AC3.json")" "$(_request a 0 '.body.state.items.AC3')" "an item is sent as its file holds it"
  instr=$(_site_instructions goal.judge)
  e2e_expect_equal "$(jq -nc --arg i "This question is about \`items.AC3\` only. Every field named below is a field of \`items.AC3\`. $instr" '$i')" \
    "$(_request a 0 '.body.questions.AC3.instructions')" "AC3's question is the pointer words, then the site's instructions"
  e2e_expect_equal '"noul"' "$(_request a 0 '.body.questions.AC1.type')" "the question keeps the site's type"
  e2e_expect_equal "$(python3 -c 'import sys, yaml, json; d = yaml.safe_load(open(sys.argv[1]))["sites"]["goal.judge"]["questions"]["supported"]["criteria"]; print(json.dumps(d, separators=(",", ":"), sort_keys=True))' "$E2E_ACTIVE_PLUGIN/system-one/questions.yaml")" \
    "$(_request a 0 '.body.questions.AC1.criteria | tojson | fromjson' | jq -cS .)" "the question keeps the site's criteria"
  e2e_expect_equal '"items-in-state" 2' "$(_line AC1 '.batch.layout | tojson' ) $(_line AC1 '.batch.size')" "the line names the layout and the request's size"
fi

if _want layout-questions; then
  _flow_test_begin "layout-questions"
  _b_setup layout-questions "items-in-questions: one request whose state is the list of keys and whose questions carry their item in an instructions object, with the pointer words written down before the measurement; answers come back by key (B1, B9)"
  e2e_stub_start a "$(jq -nc --argjson a "$(p_answer 0.1)" --argjson b "$(p_answer 0.9)" \
    '{per_item: {answers: [{match: "\"AC1\"", answer: $a}, {match: "\"AC3\"", answer: $b}]}}')"
  _item AC3 "three"; _item AC1 "one"; _items_file AC3 AC1
  _settings a goal.judge on items-in-questions
  _ask_many goal.judge
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  _expect_requests a 1
  e2e_expect_equal "0.9 0.1" "$(_line AC3 '.answer.p') $(_line AC1 '.answer.p')" "each item gets its own p"
  e2e_expect_equal '{"items":["AC3","AC1"]}' "$(_request a 0 '.body.state')" "the state is the list of keys"
  instr=$(_site_instructions goal.judge)
  e2e_expect_equal "$(jq -ncS --arg i "The item to judge is \`item\`, given here, not in the state. Every field named below is a field of \`item\`. $instr" --slurpfile it "$E2E_REPO/items/AC1.json" '{question: $i, item: $it[0]}')" \
    "$(_request a 0 '.body.questions.AC1.instructions')" "AC1's instructions are {question, item}"
  e2e_expect_equal '"items-in-questions"' "$(_line AC3 '.batch.layout | tojson')" "the line names the layout"
fi

# ----------------------------------------------------------------- packing

if _want packing-cap; then
  _flow_test_begin "packing-cap"
  _b_setup packing-cap "two items whose request measures exactly the cap (stateTokenCap x 4 characters of state and questions) share one request; one character more makes two (B2)"
  e2e_stub_start a '{"per_item": {"default": {"type": "noul", "noul": 0.9}}}'
  # The size of the request's state and questions, computed from the layout
  # written down before the measurement, with the shipped instructions:
  # len(json.dumps(state)) + len(json.dumps(questions)), ensure_ascii off.
  # AC2's text is padded so the total is exactly 4 x 1000 characters.
  pad=$(python3 - "$E2E_ACTIVE_PLUGIN/system-one/questions.yaml" <<'PY'
import json, sys, yaml
q = yaml.safe_load(open(sys.argv[1]))["sites"]["goal.judge"]["questions"]["supported"]
def item(k, t): return {"criterion": {"id": k, "text": t}, "evidence": []}
def size(a, b):
    items = {"AC1": item("AC1", a), "AC2": item("AC2", b)}
    qs = {k: dict(q, instructions="This question is about `items.%s` only. Every field named below is a field of `items.%s`. %s" % (k, k, q["instructions"])) for k in items}
    return len(json.dumps({"items": items}, ensure_ascii=False)) + len(json.dumps(qs, ensure_ascii=False))
print(4000 - size("a", ""))
PY
)
  _item AC1 "a"; _item AC2 "$(printf '%*s' "$pad" '' | tr ' ' x)"; _items_file AC1 AC2
  _settings a goal.judge shadow items-in-state '{"stateTokenCap": 1000}'
  _ask_many goal.judge
  e2e_expect_equal 0 "$E2E_RC" "exit status at exactly the cap"
  _expect_requests a 1
  _item AC2 "$(printf '%*s' "$((pad + 1))" '' | tr ' ' x)"
  _ask_many goal.judge
  e2e_expect_equal 0 "$E2E_RC" "exit status one character over"
  _expect_requests a 3
  e2e_expect_equal "1 1" "$(_line AC1 '.batch.size') $(_line AC2 '.batch.size')" "one character over: each item in a request of its own"
fi

if _want packing-ten; then
  _flow_test_begin "packing-ten"
  _b_setup packing-ten "11 small items make two requests, of 10 and 1, in input order (B2)"
  e2e_stub_start a '{"per_item": {"default": {"type": "noul", "noul": 0.9}}}'
  keys=()
  for i in 01 02 03 04 05 06 07 08 09 10 11; do _item "K$i" "item $i"; keys+=("K$i"); done
  _items_file "${keys[@]}"
  _settings a goal.judge shadow items-in-state
  _ask_many goal.judge
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  _expect_requests a 2
  e2e_expect_equal "10 0 10 9 1 0" "$(_line K01 '.batch.size') $(_line K01 '.batch.index') $(_line K10 '.batch.size') $(_line K10 '.batch.index') $(_line K11 '.batch.size') $(_line K11 '.batch.index')" "K01 to K10 share a request, K11 is alone"
  e2e_expect_equal 11 "$(jq -r .key <<<"$E2E_OUT" | wc -l | tr -d ' ')" "one line per item"
fi

if _want packing-oversized; then
  _flow_test_begin "packing-oversized"
  _b_setup packing-oversized "an item over the cap on its own is asked on its own through ask, which shortens it as it does today; the others share a request (B8)"
  e2e_stub_start a '{"per_item": {"default": {"type": "noul", "noul": 0.9}}}'
  _item AC1 "one"; _item BIG "$(printf '%*s' 9000 '' | tr ' ' y)"; _item AC3 "three"; _items_file AC1 BIG AC3
  _settings a goal.judge on items-in-state '{"stateTokenCap": 1000}'
  _ask_many goal.judge
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  _expect_requests a 2
  e2e_expect_equal "AC1 BIG AC3" "$(jq -r .key <<<"$E2E_OUT" | tr '\n' ' ' | sed 's/ $//')" "lines in input order"
  e2e_expect_equal "true null" "$(_line BIG '.truncated') $(_line BIG '.batch')" "BIG was shortened, outside any batch"
  e2e_expect_equal "answered answered answered" "$(_line AC1 .result) $(_line BIG .result) $(_line AC3 .result)" "every item is answered"
  n_single=0
  for i in 0 1; do
    if [ "$(_request a "$i" '.body.state | has("items")')" = false ]; then n_single=$((n_single + 1)); fi
  done
  e2e_expect_equal 1 "$n_single" "one request carries BIG alone, not under items"
  e2e_expect_equal 2 "$(_line AC1 '.batch.size')" "AC1 and AC3 share the other request"
fi

# ----------------------------------------------------------------- failures

if _want item-failures; then
  _flow_test_begin "item-failures"
  _b_setup item-failures "a malformed, a missing and an abstained answer each affect only their own item: the others are answered, and the call exits 0 (B3)"
  e2e_stub_start a "$(jq -nc --argjson ok "$(p_answer 0.9)" \
    '{per_item: {default: $ok, answers: [{match: "\"BAD\"", answer: {type: "noul", noul: 1.5}}, {match: "\"GONE\"", answer: "omit"}, {match: "\"ABS\"", answer: {type: "noul", noul: 0.9, abstained: true}}]}}')"
  _item AC1 "one"; _item BAD "two"; _item GONE "three"; _item ABS "four"; _item AC5 "five"
  _items_file AC1 BAD GONE ABS AC5
  _settings a goal.judge on items-in-state
  _ask_many goal.judge
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  _expect_requests a 1
  e2e_expect_equal "answered malformed missing-answer abstained answered" \
    "$(for k in AC1 BAD GONE ABS AC5; do _line "$k" .result; done | tr '\n' ' ' | sed 's/ $//')" "results per item"
  e2e_expect_equal "0.9 null 0.9" "$(_line AC1 .answer.p) $(_line BAD .answer) $(_line AC5 .answer.p)" "a failed item has no answer; the others keep theirs"
fi

if _want request-failures; then
  _flow_test_begin "request-failures"
  _b_setup request-failures "a request that fails as a whole (HTTP 500, timeout) gives every item in it that reason, and only its items: the other request's items are answered (B6)"
  # The cap puts AC1+AC2 in one request and LATE alone in another.
  e2e_stub_start a "$(jq -nc --argjson ok "$(p_answer 0.9)" '{per_item: {default: $ok, fail: [{match: "LATE", status: 500}]}}')"
  _item AC1 "one"; _item AC2 "two"; _item LATE "$(printf '%*s' 1500 '' | tr ' ' z)"; _items_file AC1 AC2 LATE
  _settings a goal.judge on items-in-state '{"stateTokenCap": 1000}'
  _ask_many goal.judge
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  _expect_requests a 2
  e2e_expect_equal "answered answered http-500" "$(_line AC1 .result) $(_line AC2 .result) $(_line LATE .result)" "only LATE's request failed"
  e2e_stub_start b "$(jq -nc --argjson ok "$(p_answer 0.9)" '{per_item: {default: $ok}, delay_ms: 2000}')"
  _settings b goal.judge on items-in-state '{"timeoutMs": 300}'
  _ask_many goal.judge
  e2e_expect_equal "timeout timeout timeout" "$(_line AC1 .result) $(_line AC2 .result) $(_line LATE .result)" "a timeout gives every item timeout"
  _expect_requests b 1
  e2e_stub_start c '{"status": 500, "body": {"detail": "down"}}'
  _settings c goal.judge on items-in-state
  _ask_many goal.judge
  e2e_expect_equal "http-500 http-500 http-500" "$(_line AC1 .result) $(_line AC2 .result) $(_line LATE .result)" "HTTP 500 gives every item http-500"
fi

if _want threshold; then
  _flow_test_begin "threshold"
  _b_setup threshold "the threshold is the site question's, for the model that answered: goal.warn-evidence on jev-1.13.0 has 0.6, so p 0.79 (confidence 0.58) is below it and p 0.81 (0.62) clears it; the default 0.9 would refuse both (B5)"
  e2e_stub_start a "$(jq -nc --argjson lo "$(p_answer 0.79)" --argjson hi "$(p_answer 0.81)" \
    '{per_item: {model: "jev-1.13.0", answers: [{match: "\"LO\"", answer: $lo}, {match: "\"HI\"", answer: $hi}]}}')"
  _item LO "low"; _item HI "high"; _items_file LO HI
  _settings a goal.warn-evidence on items-in-state
  _ask_many goal.warn-evidence
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "below-threshold answered" "$(_line LO .result) $(_line HI .result)" "0.6 applies"
  e2e_expect_equal "null 0.81 jev-1.13.0" "$(_line LO .answer) $(_line HI .answer.p) $(_line HI .model)" "only the answered item carries its answer"
fi

if _want records; then
  _flow_test_begin "records"
  _b_setup records "shadow mode records one line per item: the site's question, the item's own ref and current, state_sha256 of the item's file (not of the request), and batch {id, size, index, layout}; stdout says shadow and carries no answer (B4)"
  e2e_stub_start a '{"per_item": {"default": {"type": "noul", "noul": 0.9}}}'
  _item AC1 "one"; _item AC2 "two"; _item AC3 "three"; _items_file AC1 AC2 AC3
  _settings a goal.warn-evidence shadow items-in-questions
  _ask_many goal.warn-evidence
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "shadow null shadow null" "$(_line AC1 .result) $(_line AC1 .answer) $(_line AC3 .result) $(_line AC3 .answer)" "shadow: no answer on stdout"
  f="$E2E_HOME/$S1_RECORDS"
  e2e_expect_equal 3 "$(wc -l < "$f" | tr -d ' ')" "one record per item"
  for k in AC1 AC2 AC3; do
    want=$(shasum -a 256 "$E2E_REPO/items/$k.json" | cut -d' ' -f1)
    got=$(jq -r --arg r "test:$k" 'select(.ref == $r) | .state_sha256' "$f")
    e2e_expect_equal "$want" "$got" "$k's record names the digest of its own file"
  done
  req=$(_request a 0 '.body.state' | tr -d '\n' | shasum -a 256 | cut -d' ' -f1)
  e2e_expect_equal 0 "$(jq -r --arg d "$req" 'select(.state_sha256 == $d)' "$f" | wc -l | tr -d ' ')" "no record names the request's digest"
  e2e_expect_equal "evidence_supports goal.warn-evidence now=AC2 shadow" \
    "$(jq -r 'select(.ref == "test:AC2") | [.question, .site, .current, .mode] | join(" ")' "$f")" "AC2's record: site question, site, its current, mode"
  e2e_expect_equal "3 0 1 2 items-in-questions 1" \
    "$(jq -r '.batch.size' "$f" | head -1) $(jq -r '.batch.index' "$f" | sort | tr '\n' ' ')$(jq -r '.batch.layout' "$f" | sort -u) $(jq -r '.batch.id' "$f" | sort -u | wc -l | tr -d ' ')" \
    "batch: size 3, indexes 0 to 2, the layout, one id"
  e2e_expect_equal 0.9 "$(jq -r 'select(.ref == "test:AC1") | .answer.p' "$f")" "the record keeps the answer"
fi

# ----------------------------------------------------------------- input

if _want bad-input; then
  _flow_test_begin "bad-input"
  _b_setup bad-input "an item whose state cannot be read is refused alone (state-invalid) and the rest are asked; a bad items file, a duplicate key, a site that keeps one request per item, a missing provider and a site that is off send nothing (B10, B11)"
  e2e_stub_start a '{"per_item": {"default": {"type": "noul", "noul": 0.9}}}'
  _item AC1 "one"; _item AC3 "three"; printf 'not json\n' > "$E2E_REPO/items/AC2.json"; _items_file AC1 AC2 AC3
  _settings a goal.judge on items-in-state
  _ask_many goal.judge
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "answered state-invalid answered" "$(_line AC1 .result) $(_line AC2 .result) $(_line AC3 .result)" "only AC2 is refused"
  _expect_requests a 1
  printf '{"items": [{"key": "AC1"}]}\n' > "$E2E_REPO/items.json"
  _ask_many goal.judge
  e2e_expect_equal 2 "$E2E_RC" "an item without state_file is a usage error"
  printf 'nope\n' > "$E2E_REPO/items.json"
  _ask_many goal.judge
  e2e_expect_equal 2 "$E2E_RC" "an items file that is not JSON is a usage error"
  _items_file AC1 AC1
  _ask_many goal.judge
  e2e_expect_equal 2 "$E2E_RC" "a duplicate key is a usage error"
  _items_file AC1 AC3
  for site in review.dedup review.challenge address.category address.still_applies quality.tests-ran; do
    _settings a "$site" on items-in-state
    _ask_many "$site"
    e2e_expect_equal 2 "$E2E_RC" "$site is not asked together"
  done
  _settings a goal.judge off items-in-state
  _ask_many goal.judge
  e2e_expect_equal 3 "$E2E_RC" "mode off"
  e2e_expect_err "flow-s1: no answer: mode-off"
  e2e_user_settings '{"systemOne": {"provider": "none", "batch": "items-in-state", "uses": {"goal.judge": "on"}}}'
  _ask_many goal.judge
  e2e_expect_equal 3 "$E2E_RC" "provider none"
  e2e_expect_err "flow-s1: no answer: provider-none"
  _expect_requests a 1
fi

# ----------------------------------------------------------------- goal stop

STOP_HOOK="hooks/scripts/flow-goal-stop.sh"
STOP_PAYLOAD='{"session_id":"e2e-session","stop_hook_active":false}'

# _goal_warn <criteria json> — trusted goal g-warn on this branch with run
# run-e2e, through flow-goal-record.sh --create; criteria are {id, text, cmd?}.
_goal_warn() {
  local src="$E2E_DIR/goal.src.yaml"
  mkdir -p "$E2E_REPO/.flow/runs/run-e2e"
  python3 - "$REPO_ROOT/plugins/flow/tests/fixtures/goal/valid.yaml" "$src" "$1" <<'PY' ||
import json, sys, yaml
fixture, dst, crit = sys.argv[1:4]
with open(fixture, encoding="utf-8") as f:
    g = yaml.safe_load(f)
g["metadata"]["id"] = "g-warn"
g["scope"]["branch"] = "feature/s1-batch"
g["scope"]["run_id"] = "run-e2e"
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
  if ! (_e2e_git_env; unset FLOW_STATE_DIR; cd "$E2E_REPO" && CLAUDE_PLUGIN_ROOT="$E2E_ACTIVE_PLUGIN" \
        "$E2E_ACTIVE_PLUGIN/bin/flow-goal-record.sh" --create --goal-file "$src" >/dev/null 2>"$E2E_DIR/create.err"); then
    _flow_assert_fail "$E2E_NAME: flow-goal-record.sh --create failed: $(cat "$E2E_DIR/create.err")"
  fi
  printf 'goal criteria: %s\n' "$1" | _e2e_art
}

# _evidence <id> <proves> — a passing command_result sidecar with raw output.
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
  type: command_result
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
}

# _crit_match <id> — a substring of a criterion state about <id> alone, as the
# stub serializes an item (sort_keys): the id is followed by the text.
_crit_match() { printf '"id": "%s", "text"' "$1"; }

_stop() { mkdir -p "$E2E_DIR/tmp"; e2e_run_hook TMPDIR="$E2E_DIR/tmp" "$STOP_HOOK" "$STOP_PAYLOAD"; }

CRIT_4='[{"id":"AC1","text":"The search runs.","cmd":"true"},{"id":"AC2","text":"The search results read well."},{"id":"AC3","text":"The error page names the cause."},{"id":"AC4","text":"The empty state explains itself."}]'

if _want goal-warn; then
  _flow_test_begin "goal-warn"
  _b_setup goal-warn "warn mode with three command-less criteria: one ask-many request gives the hook the output that three single requests give, each criterion keeping its own answer; a timeout gives today's output (B1, B6)"
  _goal_warn "$CRIT_4"
  _evidence ev-ac2 AC2; _evidence ev-ac3 AC3; _evidence ev-ac4 AC4
  # AC2 and AC4 are supported (p 0.99, above jev-1.13.0's 0.6), AC3 is not (p 0.1).
  cfg=$(jq -nc --arg m2 "$(_crit_match AC2)" --arg m3 "$(_crit_match AC3)" --arg m4 "$(_crit_match AC4)" \
    --argjson hi "$(p_answer 0.99)" --argjson lo "$(p_answer 0.1)" \
    '{per_item: {model: "jev-1.13.0", answers: [{match: $m2, answer: $hi}, {match: $m3, answer: $lo}, {match: $m4, answer: $hi}]}}')
  e2e_stub_start one "$cfg"
  _settings one goal.warn-evidence on off
  _stop
  ONE_OUT="$E2E_OUT"
  _expect_requests one 3
  e2e_expect_equal "Missing evidence for: AC3" "$(jq -r .reason <<<"$ONE_OUT" | grep -F 'Missing evidence for:')" "one request per criterion: AC3 is still missing"
  e2e_stub_start many "$cfg"
  _settings many goal.warn-evidence on items-in-state
  _stop
  _expect_requests many 1
  e2e_expect_equal "$ONE_OUT" "$E2E_OUT" "one request for all three: the same hook output"
  e2e_stub_start q "$cfg"
  _settings q goal.warn-evidence on items-in-questions
  _stop
  _expect_requests q 1
  e2e_expect_equal "$ONE_OUT" "$E2E_OUT" "items-in-questions: the same hook output"
  # Today's output: no System One settings at all.
  rm -f "$E2E_HOME/.claude/settings.flow.json"
  _stop
  TODAY="$E2E_OUT"
  e2e_stub_start slow "$(jq -nc --argjson c "$cfg" '$c + {delay_ms: 2000}')"
  _settings slow goal.warn-evidence on items-in-state '{"timeoutMs": 300}'
  _stop
  _expect_requests slow 1
  e2e_expect_equal "$TODAY" "$E2E_OUT" "a timeout gives today's output"
  e2e_expect_equal "" "$(ls -A "$E2E_DIR/tmp")" "temporary files left behind"
fi

# ----------------------------------------------------------------- review.confidence

CF_BIN="bin/flow-s1-confidence.sh"

# _cf_repo — src/a.py (100 numbered lines) committed, and a private directory
# for the findings.
_cf_repo() {
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    mkdir -p src
    i=1; while [ "$i" -le 100 ]; do printf 'line_%s = %s\n' "$i" "$i"; i=$((i + 1)); done > src/a.py
    git add src/a.py && git commit -q -m a
  ) || _flow_assert_fail "$E2E_NAME: could not commit src/a.py"
  CF_DIR="$E2E_DIR/conf"
  mkdir -p "$CF_DIR" && chmod 700 "$CF_DIR"
}

# _cf_findings <id:line:reviewer>... — P2 correctness findings, HIGH, each
# citing its line of src/a.py, problem "problem of <id>".
_cf_findings() {
  local spec out=()
  for spec in "$@"; do
    out+=("$(jq -nc --arg id "${spec%%:*}" --arg l "src/a.py:$(cut -d: -f2 <<<"$spec")" --arg r "${spec##*:}" \
      '{id:$id,priority:"P2",category:"correctness",location:$l,problem:("problem of " + $id),suggested_fix:("fix for " + $id),
        confidence:"HIGH",disposition:"unchallenged",reviewers:[$r]}')")
  done
  printf '%s\n' "${out[@]}" | jq -s . > "$CF_DIR/findings.json"
}

_cf_run() {
  e2e_run_bin "$CF_BIN" --findings "$CF_DIR/findings.json" --tree "$E2E_REPO" \
    --ref-prefix pr:7/review-cycle:1 --demoted-out "$CF_DIR/demoted.txt"
}

if _want confidence; then
  _flow_test_begin "confidence"
  _b_setup confidence "review.confidence: four eligible findings and a security finding; with batching on, one request gives the output that four single requests give, each finding keeping its own answer (F2 demoted, the others not); one malformed answer affects only its finding (B1, B3)"
  _cf_repo
  _cf_findings F1:10:code-reviewer F2:20:code-reviewer S1:30:security-reviewer F3:40:code-reviewer F4:50:code-reviewer
  # Confidence |2p - 1|: 0.96 and 0.96, both at or above the shipped threshold 0.9.
  cfg=$(jq -nc --argjson hi "$(p_answer 0.98)" --argjson lo "$(p_answer 0.02)" \
    '{per_item: {model: "jev-1.13.0", default: $hi, answers: [{match: "problem of F2", answer: $lo}]}}')
  e2e_stub_start one "$cfg"
  _settings one review.confidence on off
  _cf_run
  ONE_OUT="$E2E_OUT"
  _expect_requests one 4
  e2e_expect_line "S1_DEMOTED=F2"
  e2e_expect_line "S1_CONFIDENCE_RESULT=S1 STATE=skipped REASON=not-eligible-security"
  for layout in items-in-state items-in-questions; do
    e2e_stub_start "$layout" "$cfg"
    _settings "$layout" review.confidence on "$layout"
    _cf_run
    _expect_requests "$layout" 1
    e2e_expect_equal "$ONE_OUT" "$E2E_OUT" "$layout: the same output as one request per finding"
  done
  e2e_stub_start bad "$(jq -nc --argjson c "$cfg" '$c | .per_item.answers += [{match: "problem of F3", answer: {type: "noul", noul: 1.5}}]')"
  _settings bad review.confidence on items-in-state
  _cf_run
  _expect_requests bad 1
  e2e_expect_line "S1_CONFIDENCE_RESULT=F3 STATE=no-answer REASON=malformed"
  e2e_expect_line "S1_DEMOTED=F2"
  e2e_expect_equal 3 "$(grep -c 'STATE=answered' <<<"$E2E_OUT")" "F1, F2 and F4 are answered"
  e2e_expect_line "S1_ASKED=4"
fi

if _want confidence-off; then
  _flow_test_begin "confidence-off"
  _b_setup confidence-off "review.confidence off: batching on or off, the output is the same and nothing is sent"
  _cf_repo
  _cf_findings F1:10:code-reviewer F2:20:code-reviewer
  e2e_stub_start a '{"per_item": {"default": {"type": "noul", "noul": 0.9}}}'
  _settings a review.confidence off off
  _cf_run
  OFF_OUT="$E2E_OUT"
  _settings a review.confidence off items-in-state
  _cf_run
  e2e_expect_equal "$OFF_OUT" "$E2E_OUT" "the same output with batching on"
  _expect_requests a 0
fi

_e2e_stop_stubs
