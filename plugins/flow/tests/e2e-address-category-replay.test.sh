# shellcheck shell=bash
# End-to-end: the address.category wording comparison of issue #296. The
# harness (evals/results-2026-10-09-address-category/run.sh) runs the shipped
# COMMENT_CATEGORY_BLOCK of commands/address.md, from a copy of the plugin
# outside any repository, once per labelled item, with the question wording of
# one form (current.yaml or alternative.yaml) patched into the copy. The
# summary (summarize.py in the same directory) turns the records into the
# report and checks the issue's acceptance criteria.
#
# The harness scenarios run against a stub System One server
# (tests/lib/s1_stub.py) that answers by item text. The summary scenarios
# feed hand-written records. One artifact per scenario goes to
# $FLOW_E2E_ARTIFACT_DIR. FLOW_E2E_SCENARIOS=a,b runs only the named scenarios.
#
# Ways it can be wrong, written down before the scenarios (the risk map of
# .decisions/issue-296.md, and the failure modes there):
#   R1 raises counted over answered items only, so a form with more
#      no-answers looks better
#   R2 the raise rule uses the probability of P1 instead of the answer's
#      confidence, or > instead of >= at the threshold
#   R3 the alternative run sends the current wording (copy not patched)
#   R4 every lower answer counts as "labelled P1 placed lower", not only
#      those on items labelled P1
#   R5 an item whose text holds a priority is sent, so the label leaks
#   R6 records go to the user's own state directory, mixing with live ones
#   R7 the plugin copy sits inside a repository, where the client refuses the
#      user's settings
#   R8 the item file, which holds reviewer text, is left behind
#   R9 the bars are applied the wrong way, or the shipped wording does not
#      follow them
#   R10 a finding id with dashes is split, so its record matches no item

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

AC_DIR="$E2E_PLUGIN_DIR/evals/results-2026-10-09-address-category"
AC_RUN="$AC_DIR/run.sh"
AC_SUM="$AC_DIR/summarize.py"

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

# _choice <choice> <P1> <P2> <P3> <Question> — a reply in TypeSafe's shape with
# no confidence field, so the client computes (4m - 1) / 3 from the largest
# probability m and rounds it to 6 places.
_choice() {
  printf '{"model":"jev-1.13.0","answers":{"category":{"type":"choice","choice":"%s","probabilities":{"P1":%s,"P2":%s,"P3":%s,"Question":%s}}}}' "$@"
}

# The fixture: five labelled items in the shape of the 2026-10-07 items file.
# Alpha (P3) is answered P1 at 0.96: a raise. Bravo (P2) is answered P1 with
# P1 at 0.85, so (4 * 0.85 - 1) / 3 = 0.8 exactly: a raise at 0.8 (R2).
# Charlie (P1, finding id C1-TR-2) is answered P2: a labelled P1 placed lower
# (R4, R10). Delta's text holds "P2" and Echo's "p3": neither is ever sent (R5).
_ac_items() {
  {
    jq -nc '{ref:"replay:pr-finding:pr12-review345-F1",pr:12,finding_id:"F1",path:"src/a.c",line:"10",text:"Alpha: the loop reads one element past the end of the buffer.",reviewer_priority:"P3",model_choice:"P1"}'
    jq -nc '{ref:"replay:pr-finding:pr12-review345-F2",pr:12,finding_id:"F2",path:"src/b.c",line:"",text:"Bravo: the retry count is never reset after a success.",reviewer_priority:"P2",model_choice:"P1"}'
    jq -nc '{ref:"replay:pr-finding:pr13-review678-C1-TR-2",pr:13,finding_id:"C1-TR-2",path:"",line:"",text:"Charlie: the token is written to the log in clear text.",reviewer_priority:"P1",model_choice:"P2"}'
    jq -nc '{ref:"replay:pr-finding:pr13-review678-F4",pr:13,finding_id:"F4",path:"src/d.c",line:"4",text:"Delta: the P2 helper could have a clearer name.",reviewer_priority:"P3",model_choice:"P3"}'
    jq -nc '{ref:"replay:pr-finding:pr13-review678-F5",pr:13,finding_id:"F5",path:"",line:"",text:"Echo: this looks like a p3 to me.",reviewer_priority:"P3",model_choice:"P3"}'
  } > "$E2E_DIR/items.jsonl"
}

# _ac_stub — a stub that answers each item by its text.
_ac_stub() {
  e2e_stub_start a "$(jq -nc \
    --argjson a "$(_choice P1 0.97 0.01 0.01 0.01)" \
    --argjson b "$(_choice P1 0.85 0.05 0.05 0.05)" \
    --argjson c "$(_choice P2 0.01 0.97 0.01 0.01)" \
    --argjson d "$(_choice P3 0.01 0.01 0.97 0.01)" \
    '{body: $d, rules: [{contains: "Alpha:", body: $a}, {contains: "Bravo:", body: $b}, {contains: "Charlie:", body: $c}]}')"
  jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,model:"jev-1.13.0"}}' > "$E2E_DIR/settings.json"
}

# _ac_run <form> [extra args] — run the harness with HOME set to the scenario's
# own, so a record written to the default state directory would be found.
_ac_run() {
  local form="$1"; shift
  E2E_RC=0
  E2E_OUT=$(cd "$E2E_DIR" && HOME="$E2E_HOME" TMPDIR="$E2E_DIR/tmp" "$AC_RUN" --form "$form" \
    --items "$E2E_DIR/items.jsonl" --settings "$E2E_DIR/settings.json" --out "$E2E_DIR/out" "$@" \
    2> "$E2E_DIR/run-$form.err") || E2E_RC=$?
  E2E_ERR=$(cat "$E2E_DIR/run-$form.err")
  printf 'run.sh --form %s: rc=%s\n--- stdout\n%s\n--- stderr\n%s\n' "$form" "$E2E_RC" "$E2E_OUT" "$E2E_ERR" | _e2e_art
}

# _ac_sum [args] — run the summary over the scenario's out directory.
_ac_sum() {
  E2E_RC=0
  E2E_OUT=$(python3 "$AC_SUM" --dir "$E2E_DIR/out" --items "$E2E_DIR/items.jsonl" "$@" 2> "$E2E_DIR/sum.err") || E2E_RC=$?
  E2E_ERR=$(cat "$E2E_DIR/sum.err")
  printf 'summarize.py %s: rc=%s\n--- stdout\n%s\n--- stderr\n%s\n' "$*" "$E2E_RC" "$E2E_OUT" "$E2E_ERR" | _e2e_art
}

# _ac_hash <yaml> — the sha256 of the address.category questions in a file,
# as the client loads them, from the function run.sh and the summary use.
_ac_hash() { python3 "$AC_SUM" --hash "$1"; }

if _want ac-replay; then
  _flow_test_begin "ac-replay"
  e2e_new ac-replay
  e2e_describe "R1-R8, R10: both forms through the shipped block against a stub, then the summary over the records"
  mkdir -p "$E2E_DIR/tmp"
  _ac_items
  _ac_stub
  _ac_run current
  e2e_expect_equal 0 "$E2E_RC" "current run exit status"
  _ac_run alternative
  e2e_expect_equal 0 "$E2E_RC" "alternative run exit status"
  e2e_expect_line "SENT_SHA256=$(_ac_hash "$AC_DIR/alternative.yaml")"
  # R3: what the provider received. 3 items per form are sent; Delta never.
  e2e_expect_equal 6 "$(e2e_stub_requests a)" "requests the stub received"
  e2e_expect_equal 0 "$(grep -c -e 'Delta:' -e 'Echo:' "$(e2e_stub_log a)")" "requests holding Delta's or Echo's text (R5)"
  # The current run's requests come first, then the alternative's.
  e2e_expect_equal 0 "$(head -n 3 "$(e2e_stub_log a)" | jq -r '.body.questions.category.instructions' | grep -c 'what happens if the pull request')" \
    "current-run requests carrying the alternative wording (R3)"
  e2e_expect_equal 3 "$(tail -n 3 "$(e2e_stub_log a)" | jq -r '.body.questions.category.instructions' | grep -c 'what happens if the pull request')" \
    "alternative-run requests carrying the alternative wording (R3)"
  # R6: records only in the harness's own state directory.
  e2e_expect_equal no "$([ -e "$E2E_HOME/.claude/flow-state/system-one.jsonl" ] && echo yes || echo no)" "a record in HOME's state directory"
  e2e_expect_equal 3 "$(wc -l < "$E2E_DIR/out/records-alternative.jsonl" | tr -d ' ')" "alternative records"
  e2e_expect_equal "pr:13/review:678/C1-TR-2" "$(jq -r 'select(.answer.choice == "P2") | .ref' "$E2E_DIR/out/records-alternative.jsonl")" "the dashed finding id's ref (R10)"
  e2e_expect_equal true "$(jq -s -r 'map(select(.ref == "replay:pr-finding:pr13-review678-F4")) | .[0].refused' "$E2E_DIR/out/meta-alternative.jsonl")" "Delta refused in the meta (R5)"
  # R8: no item file left in TMPDIR.
  e2e_expect_equal 0 "$(find "$E2E_DIR/tmp" -type f 2>/dev/null | wc -l | tr -d ' ')" "files left in TMPDIR"
  _ac_sum
  e2e_expect_equal 0 "$E2E_RC" "summary exit status"
  e2e_expect_line "alternative.items=5"
  e2e_expect_line "alternative.answered=3"
  e2e_expect_line "alternative.refused=2"
  e2e_expect_line "alternative.raises.0.8=2"
  e2e_expect_line "alternative.raises.0.9=1"
  e2e_expect_line "alternative.p1_lowered=1"
  e2e_expect_line "current.raises.0.8=2"
  # R1 in the report: shares are of all 5 items, so 2 raises are 40.0% and 3
  # answered are 60.0% (over the 3 answered they would be 66.7% and 100.0%).
  _ac_sum --write
  e2e_expect_equal 1 "$(grep -cxF '| Raised above the label at 0.8 | 2 (40.0%) | 2 (40.0%) |' "$E2E_DIR/out/summary.md")" "the raised row of summary.md"
  e2e_expect_equal 1 "$(grep -cxF '| Answered | 3 (60.0%) | 3 (60.0%) |' "$E2E_DIR/out/summary.md")" "the answered row of summary.md"
  _ac_sum --check ac1
  e2e_expect_equal 0 "$E2E_RC" "--check ac1 exit status"
  e2e_expect_clean_edges
fi

if _want ac-copy-in-repo; then
  _flow_test_begin "ac-copy-in-repo"
  e2e_new ac-copy-in-repo
  e2e_describe "R7: a scratch directory inside a repository is refused before anything is sent"
  e2e_repo feature/x
  mkdir -p "$E2E_REPO/tmp"
  _ac_items
  _ac_stub
  E2E_RC=0
  E2E_OUT=$(cd "$E2E_DIR" && HOME="$E2E_HOME" TMPDIR="$E2E_REPO/tmp" "$AC_RUN" --form current \
    --items "$E2E_DIR/items.jsonl" --settings "$E2E_DIR/settings.json" --out "$E2E_DIR/out" 2>&1) || E2E_RC=$?
  printf 'rc=%s\n%s\n' "$E2E_RC" "$E2E_OUT" | _e2e_art
  e2e_expect_equal 1 "$E2E_RC" "exit status"
  e2e_expect_out "inside a git repository"
  e2e_expect_equal 0 "$(e2e_stub_requests a)" "requests the stub received"
  e2e_expect_clean_edges
fi

# _ac_records <form> <file of "ref|choice|P1|P2|P3|Q|confidence|result" lines>
# — hand-written records and a run file for the summary scenarios. A choice of
# "-" writes a record with no answer.
_ac_records() {
  local form="$1" sha="$2"
  mkdir -p "$E2E_DIR/out"
  : > "$E2E_DIR/out/records-$form.jsonl"
  : > "$E2E_DIR/out/meta-$form.jsonl"
  while IFS='|' read -r ref choice p1 p2 p3 q conf result; do
    [ -n "$ref" ] || continue
    if [ "$choice" = - ]; then
      jq -nc --arg r "$ref" --arg res "$result" '{site:"address.category",question:"category",mode:"shadow",model:"jev-1.13.0",result:$res,answer:null,ref:$r}'
    else
      jq -nc --arg r "$ref" --arg c "$choice" --argjson p1 "$p1" --argjson p2 "$p2" --argjson p3 "$p3" --argjson q "$q" --argjson conf "$conf" --arg res "$result" \
        '{site:"address.category",question:"category",mode:"shadow",model:"jev-1.13.0",result:$res,answer:{type:"choice",choice:$c,probabilities:{P1:$p1,P2:$p2,P3:$p3,Question:$q},confidence:$conf},ref:$r}'
    fi >> "$E2E_DIR/out/records-$form.jsonl"
  done
  jq -nc --arg f "$form" --arg s "$sha" '{form:$f,sent_sha256:$s,model:"jev-1.13.0"}' > "$E2E_DIR/out/run-$form.json"
}

# Three items labelled P3, P2 and P1 for the summary scenarios.
_ac_small_items() {
  {
    jq -nc '{ref:"replay:pr-finding:pr1-review1-F1",pr:1,finding_id:"F1",text:"one",reviewer_priority:"P3",model_choice:"P1"}'
    jq -nc '{ref:"replay:pr-finding:pr1-review1-F2",pr:1,finding_id:"F2",text:"two",reviewer_priority:"P2",model_choice:"P1"}'
    jq -nc '{ref:"replay:pr-finding:pr1-review1-F3",pr:1,finding_id:"F3",text:"three",reviewer_priority:"P1",model_choice:"P1"}'
  } > "$E2E_DIR/items.jsonl"
}

if _want ac-sum-rules; then
  _flow_test_begin "ac-sum-rules"
  e2e_new ac-sum-rules
  e2e_describe "R1, R2, R4: raises over all items, >= at the threshold on the answer's confidence, P1 lowered only for P1 labels"
  _ac_small_items
  CUR=$(_ac_hash "$AC_DIR/current.yaml"); ALT=$(_ac_hash "$AC_DIR/alternative.yaml")
  # Current: F1 (P3) answered P1 at 0.8 exactly: a raise at 0.8 (R2, >=).
  # F2 (P2) answered P3 at 0.99: lower, but not a P1 label (R4). F3 no answer.
  _ac_records current "$CUR" <<'EOF'
pr:1/review:1/F1|P1|0.85|0.05|0.05|0.05|0.8|answered
pr:1/review:1/F2|P3|0.0|0.0|1.0|0.0|0.99|answered
pr:1/review:1/F3|-|||||timeout
EOF
  # Alternative: F1 (P3) answered P2 at 0.79 with P1 at 0.85 in the
  # probabilities: no raise at 0.8 (R2, confidence not P(P1)). F2 no answer
  # (R1: 1 raise of 3, not of 2). F3 (P1) answered P2 at 0.5: placed lower at
  # any confidence, not at 0.8 (R4).
  _ac_records alternative "$ALT" <<'EOF'
pr:1/review:1/F1|P2|0.85|0.1|0.05|0.0|0.79|below-threshold
pr:1/review:1/F2|-|||||connection
pr:1/review:1/F3|P2|0.2|0.6|0.1|0.1|0.5|below-threshold
EOF
  _ac_sum
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "current.raises.0.8=1"
  e2e_expect_line "current.p1_lowered=0"
  e2e_expect_line "current.answered=2"
  e2e_expect_line "alternative.raises.0.8=0"
  e2e_expect_line "alternative.raises.0.7=1"
  e2e_expect_line "alternative.answered=2"
  e2e_expect_line "alternative.no_answer=1"
  e2e_expect_line "alternative.p1_lowered=1"
  e2e_expect_line "alternative.p1_lowered.0.8=0"
fi

if _want ac-sum-hash; then
  _flow_test_begin "ac-sum-hash"
  e2e_new ac-sum-hash
  e2e_describe "R3: an alternative run whose sent wording is the current one fails --check ac1"
  _ac_small_items
  CUR=$(_ac_hash "$AC_DIR/current.yaml")
  printf 'pr:1/review:1/F1|P3|0|0|1|0|1|answered\npr:1/review:1/F2|P2|0|1|0|0|1|answered\npr:1/review:1/F3|P1|1|0|0|0|1|answered\n' > "$E2E_DIR/r.txt"
  _ac_records current "$CUR" < "$E2E_DIR/r.txt"
  _ac_records alternative "$CUR" < "$E2E_DIR/r.txt"
  _ac_sum --check ac1
  e2e_expect_equal 1 "$E2E_RC" "exit status"
  e2e_expect_out "alternative run sent"
fi

# _ac_bars <alt raises> — write records where the current form raises all three
# items to P1 and the alternative raises the first <n>; P1 is never lowered.
_ac_bars() {
  local cur alt i n="$1"
  cur=$(_ac_hash "$AC_DIR/current.yaml"); alt=$(_ac_hash "$AC_DIR/alternative.yaml")
  printf 'pr:1/review:1/F1|P1|1|0|0|0|1|answered\npr:1/review:1/F2|P1|1|0|0|0|1|answered\npr:1/review:1/F3|P1|1|0|0|0|1|answered\n' | _ac_records current "$cur"
  {
    for i in 1 2; do
      if [ "$i" -le "$n" ]; then printf 'pr:1/review:1/F%s|P1|1|0|0|0|1|answered\n' "$i"
      else printf 'pr:1/review:1/F%s|P3|0|0|1|0|1|answered\n' "$i"; fi
    done
    printf 'pr:1/review:1/F3|P1|1|0|0|0|1|answered\n'
  } | _ac_records alternative "$alt"
}

# _ac_shipped <yaml> — a questions file whose address.category site is <yaml>'s.
_ac_shipped() { cp "$1" "$E2E_DIR/shipped.yaml"; }

if _want ac-sum-bars; then
  _flow_test_begin "ac-sum-bars"
  e2e_new ac-sum-bars
  e2e_describe "R9: the shipped wording must be the one the bars select"
  _ac_small_items
  # The current form raises F1 (P3) and F2 (P2) to P1: 2 raises. With the
  # alternative raising 1, the bars are 1 <= 2/2, P1 lowered 0 <= 0, and
  # answered 3 of 3; the alternative answers every item, so bar 3 (at least
  # 195 of 200) is read as at least 97.5% of the items.
  _ac_bars 1
  # The forms disagree on F2 only (current P1, alternative P3); the ruling
  # agrees with the alternative, so bar 4 holds.
  jq -nc '{ref:"replay:pr-finding:pr1-review1-F2",ruling:"P3"}' > "$E2E_DIR/out/rulings.jsonl"
  _ac_sum
  e2e_expect_line "bars=pass"
  _ac_shipped "$AC_DIR/current.yaml"
  _ac_sum --shipped "$E2E_DIR/shipped.yaml" --check ac3
  e2e_expect_equal 1 "$E2E_RC" "--check ac3 with bars passing and the current wording shipped"
  _ac_shipped "$AC_DIR/alternative.yaml"
  _ac_sum --shipped "$E2E_DIR/shipped.yaml" --check ac3
  e2e_expect_equal 0 "$E2E_RC" "--check ac3 with bars passing and the alternative shipped"
  # Alternative raising 2 of the current 2: bar 1 fails (2 > 2/2).
  _ac_bars 2
  _ac_sum
  e2e_expect_line "bars=fail"
  _ac_sum --shipped "$E2E_DIR/shipped.yaml" --check ac3
  e2e_expect_equal 1 "$E2E_RC" "--check ac3 with bars failing and the alternative shipped"
  _ac_shipped "$AC_DIR/current.yaml"
  _ac_sum --shipped "$E2E_DIR/shipped.yaml" --check ac3
  e2e_expect_equal 0 "$E2E_RC" "--check ac3 with bars failing and the current wording shipped"
fi

if _want ac-sum-truncated; then
  _flow_test_begin "ac-sum-truncated"
  e2e_new ac-sum-truncated
  e2e_describe "a truncated item answered above its label is counted as truncated and never as a raise: the block does not act on it"
  _ac_small_items
  printf 'pr:1/review:1/F1|P1|1|0|0|0|1|answered\npr:1/review:1/F2|P2|0|1|0|0|1|answered\npr:1/review:1/F3|P1|1|0|0|0|1|answered\n' > "$E2E_DIR/r.txt"
  _ac_records current "$(_ac_hash "$AC_DIR/current.yaml")" < "$E2E_DIR/r.txt"
  _ac_records alternative "$(_ac_hash "$AC_DIR/alternative.yaml")" < "$E2E_DIR/r.txt"
  jq -nc '{ref:"replay:pr-finding:pr1-review1-F1",refused:false,truncated:true}' > "$E2E_DIR/out/meta-current.jsonl"
  _ac_sum
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "current.truncated=1"
  e2e_expect_line "current.raises.0.5=0"
  e2e_expect_line "alternative.raises.0.5=1"
fi

if _want ac-sum-rulings; then
  _flow_test_begin "ac-sum-rulings"
  e2e_new ac-sum-rulings
  e2e_describe "bar 4: the blind sample is the items the forms answered differently, and the alternative must match the rulings at least as often"
  _ac_small_items
  # Current says P1, P1, P2; the alternative P3, P1, P1. They disagree on F1
  # and F3. Bars 1 to 3 hold: raises at 0.8 are 2 (F1, F2) against 1 (F2),
  # labelled P1 placed lower 1 (F3) against 0, and all 3 answered.
  printf 'pr:1/review:1/F1|P1|1|0|0|0|1|answered\npr:1/review:1/F2|P1|1|0|0|0|1|answered\npr:1/review:1/F3|P2|0|1|0|0|1|answered\n' | _ac_records current "$(_ac_hash "$AC_DIR/current.yaml")"
  printf 'pr:1/review:1/F1|P3|0|0|1|0|1|answered\npr:1/review:1/F2|P1|1|0|0|0|1|answered\npr:1/review:1/F3|P1|1|0|0|0|1|answered\n' | _ac_records alternative "$(_ac_hash "$AC_DIR/alternative.yaml")"
  _ac_sum --sample
  e2e_expect_equal 0 "$E2E_RC" "--sample exit status"
  e2e_expect_out "one"
  e2e_expect_out "three"
  e2e_expect_no_out "two"
  # Blind: no priority appears in the sample (the item texts hold none).
  e2e_expect_equal 0 "$(printf '%s' "$E2E_OUT" | grep -cE 'P[123]|Question')" "priorities in the sample"
  _ac_sum
  e2e_expect_line "bar4.rulings=pending"
  e2e_expect_line "bars=pending"
  # Rulings P3 (F1) and P2 (F3): each form matches one, so bar 4 holds.
  { jq -nc '{ref:"replay:pr-finding:pr1-review1-F1",ruling:"P3"}'; jq -nc '{ref:"replay:pr-finding:pr1-review1-F3",ruling:"P2"}'; } > "$E2E_DIR/out/rulings.jsonl"
  _ac_sum
  e2e_expect_line "bar4.sample=2"
  e2e_expect_line "bar4.current_matches=1"
  e2e_expect_line "bar4.alternative_matches=1"
  e2e_expect_line "bar4.rulings=pass"
  e2e_expect_line "bars=pass"
  # Rulings P1 (F1) and P2 (F3): the current wording matches 2, the
  # alternative 0.
  { jq -nc '{ref:"replay:pr-finding:pr1-review1-F1",ruling:"P1"}'; jq -nc '{ref:"replay:pr-finding:pr1-review1-F3",ruling:"P2"}'; } > "$E2E_DIR/out/rulings.jsonl"
  _ac_sum
  e2e_expect_line "bar4.rulings=fail"
  e2e_expect_line "bars=fail"
  # A ruling missing for a sampled item leaves the bar pending.
  jq -nc '{ref:"replay:pr-finding:pr1-review1-F1",ruling:"P1"}' > "$E2E_DIR/out/rulings.jsonl"
  _ac_sum
  e2e_expect_line "bar4.rulings=pending"
fi

if _want ac-sum-bar3; then
  _flow_test_begin "ac-sum-bar3"
  e2e_new ac-sum-bar3
  e2e_describe "bar 3: an alternative that answers 2 of 3 items (under 97.5%) fails, whatever its raises"
  _ac_small_items
  printf 'pr:1/review:1/F1|P1|1|0|0|0|1|answered\npr:1/review:1/F2|P1|1|0|0|0|1|answered\npr:1/review:1/F3|P1|1|0|0|0|1|answered\n' | _ac_records current "$(_ac_hash "$AC_DIR/current.yaml")"
  printf 'pr:1/review:1/F1|P3|0|0|1|0|1|answered\npr:1/review:1/F2|-|||||timeout\npr:1/review:1/F3|P1|1|0|0|0|1|answered\n' | _ac_records alternative "$(_ac_hash "$AC_DIR/alternative.yaml")"
  _ac_sum
  e2e_expect_line "bar1.raises_at_most_half=pass"
  e2e_expect_line "bar3.answered_at_least_97.5pct=fail"
  e2e_expect_line "bars=fail"
fi

if _want ac-sum-retry; then
  _flow_test_begin "ac-sum-retry"
  e2e_new ac-sum-retry
  e2e_describe "a retried item: the last of its records decides, and the retry is counted"
  _ac_small_items
  # F1 (P3) first answered P1 at 1.0, then P3: the last one decides, no raise.
  printf 'pr:1/review:1/F1|P1|1|0|0|0|1|answered\npr:1/review:1/F1|P3|0|0|1|0|1|answered\npr:1/review:1/F2|P2|0|1|0|0|1|answered\npr:1/review:1/F3|P1|1|0|0|0|1|answered\n' | _ac_records current "$(_ac_hash "$AC_DIR/current.yaml")"
  printf 'pr:1/review:1/F1|P3|0|0|1|0|1|answered\npr:1/review:1/F2|P2|0|1|0|0|1|answered\npr:1/review:1/F3|P1|1|0|0|0|1|answered\n' | _ac_records alternative "$(_ac_hash "$AC_DIR/alternative.yaml")"
  _ac_sum
  e2e_expect_line "current.retried=1"
  e2e_expect_line "current.raises.0.5=0"
  e2e_expect_line "current.agree=3"
fi

if _want ac-sum-sample-order; then
  _flow_test_begin "ac-sum-sample-order"
  e2e_new ac-sum-sample-order
  e2e_describe "bar 4: with 22 items answered differently, the sample is the first 20 by the sha256 of the item ref"
  : > "$E2E_DIR/items.jsonl"; : > "$E2E_DIR/cur.txt"; : > "$E2E_DIR/alt.txt"
  for i in $(seq 1 22); do
    jq -nc --arg r "replay:pr-finding:pr1-review1-F$i" --arg t "item number $i here" '{ref:$r,pr:1,finding_id:"F",text:$t,reviewer_priority:"P2",model_choice:"P2"}' >> "$E2E_DIR/items.jsonl"
    printf 'pr:1/review:1/F%s|P2|0|1|0|0|1|answered\n' "$i" >> "$E2E_DIR/cur.txt"
    printf 'pr:1/review:1/F%s|P3|0|0|1|0|1|answered\n' "$i" >> "$E2E_DIR/alt.txt"
  done
  _ac_records current "$(_ac_hash "$AC_DIR/current.yaml")" < "$E2E_DIR/cur.txt"
  _ac_records alternative "$(_ac_hash "$AC_DIR/alternative.yaml")" < "$E2E_DIR/alt.txt"
  # The two refs with the largest sha256, computed here with openssl, are
  # the ones left out.
  OUTSIDE=$(for i in $(seq 1 22); do printf '%s %s\n' "$(printf '%s' "replay:pr-finding:pr1-review1-F$i" | openssl dgst -sha256 -r | cut -d' ' -f1)" "$i"; done | sort | tail -n 2 | cut -d' ' -f2 | tr '\n' ' ')
  _ac_sum --sample
  e2e_expect_equal 20 "$(printf '%s\n' "$E2E_OUT" | grep -c '^ITEM ')" "items in the sample"
  for i in $OUTSIDE; do e2e_expect_no_line "item number $i here"; done
  INSIDE=$(seq 1 22 | grep -vxF -e "${OUTSIDE%% *}" -e "$(echo $OUTSIDE | cut -d' ' -f2)" | head -n 1)
  e2e_expect_line "item number $INSIDE here"
fi

if _want ac-partial-run; then
  _flow_test_begin "ac-partial-run"
  e2e_new ac-partial-run
  e2e_describe "a run stopped after 10 transport failures in a row keeps the records of the items it asked"
  mkdir -p "$E2E_DIR/tmp"
  : > "$E2E_DIR/items.jsonl"
  for i in $(seq 1 11); do
    jq -nc --arg r "replay:pr-finding:pr1-review1-F$i" --arg t "Failure item $i" '{ref:$r,pr:1,finding_id:"F",text:$t,reviewer_priority:"P2",model_choice:"P2"}' >> "$E2E_DIR/items.jsonl"
  done
  e2e_stub_start a '{"status":502,"body":{"error":"bad gateway"}}'
  jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,model:"jev-1.13.0"}}' > "$E2E_DIR/settings.json"
  _ac_run current
  e2e_expect_equal 1 "$E2E_RC" "exit status"
  e2e_expect_err "10 transport failures in a row"
  e2e_expect_equal 10 "$(e2e_stub_requests a)" "requests the stub received"
  e2e_expect_equal 10 "$(wc -l < "$E2E_DIR/out/records-current.jsonl" | tr -d ' ')" "records kept"
  e2e_expect_clean_edges
fi

# _ac_meta <form> <n...> — one meta row per listed finding number.
_ac_meta() {
  local form="$1" i; shift
  : > "$E2E_DIR/out/meta-$form.jsonl"
  for i in "$@"; do jq -nc --arg r "replay:pr-finding:pr1-review1-F$i" '{ref:$r,refused:false,truncated:false}' >> "$E2E_DIR/out/meta-$form.jsonl"; done
}

if _want ac-sum-meta; then
  _flow_test_begin "ac-sum-meta"
  e2e_new ac-sum-meta
  e2e_describe "--check ac1 needs exactly one meta row per item: a missing row, or a missing row hidden by a duplicate, fails it"
  _ac_small_items
  printf 'pr:1/review:1/F1|P1|1|0|0|0|1|answered\npr:1/review:1/F2|P1|1|0|0|0|1|answered\npr:1/review:1/F3|P1|1|0|0|0|1|answered\n' > "$E2E_DIR/r.txt"
  _ac_records current "$(_ac_hash "$AC_DIR/current.yaml")" < "$E2E_DIR/r.txt"
  _ac_records alternative "$(_ac_hash "$AC_DIR/alternative.yaml")" < "$E2E_DIR/r.txt"
  _ac_meta current 1 2 3; _ac_meta alternative 1 2 3
  _ac_sum --check ac1
  e2e_expect_equal 0 "$E2E_RC" "--check ac1 with one row per item"
  _ac_meta current 1 2
  _ac_sum --check ac1
  e2e_expect_equal 1 "$E2E_RC" "--check ac1 with a row missing"
  e2e_expect_out "meta-current.jsonl has 2 rows"
  _ac_meta current 1 2 2
  _ac_sum --check ac1
  e2e_expect_equal 1 "$E2E_RC" "--check ac1 with a row missing and another duplicated"
fi

if _want ac-sum-drift; then
  _flow_test_begin "ac-sum-drift"
  e2e_new ac-sum-drift
  e2e_describe "drift is counted over all items: an item the current wording left unanswered counts as changed"
  _ac_small_items
  # The 2026-10-07 choice is P1 for all three; today F1 and F2 are P1 and F3
  # has no answer: 2 of 3, where counting answered items only gives 2 of 2.
  printf 'pr:1/review:1/F1|P1|1|0|0|0|1|answered\npr:1/review:1/F2|P1|1|0|0|0|1|answered\npr:1/review:1/F3|-|||||timeout\n' | _ac_records current "$(_ac_hash "$AC_DIR/current.yaml")"
  printf 'pr:1/review:1/F1|P1|1|0|0|0|1|answered\npr:1/review:1/F2|P1|1|0|0|0|1|answered\npr:1/review:1/F3|P1|1|0|0|0|1|answered\n' | _ac_records alternative "$(_ac_hash "$AC_DIR/alternative.yaml")"
  _ac_sum
  e2e_expect_line "drift.current_same_as_2026-10-07=2/3"
fi

# _ac_plugin_copy [sed expression] — a copy of the plugin outside any git
# repository, with this eval directory, and commands/address.md edited by the
# sed expression when one is given. Sets AC_COPY_RUN to its run.sh.
_ac_plugin_copy() {
  local c="$E2E_DIR/plug"
  mkdir -p "$c/evals/results-2026-10-09-address-category"
  tar -C "$E2E_PLUGIN_DIR" --exclude ./evals --exclude ./tests -cf - . | tar -C "$c" -xf -
  cp "$AC_DIR/run.sh" "$AC_DIR/summarize.py" "$AC_DIR/current.yaml" "$AC_DIR/alternative.yaml" "$c/evals/results-2026-10-09-address-category/"
  if [ -n "${1:-}" ]; then sed -i.bak -e "$1" "$c/commands/address.md" && rm -f "$c/commands/address.md.bak"; fi
  AC_COPY_RUN="$c/evals/results-2026-10-09-address-category/run.sh"
}

# _ac_run_with <run.sh> <cwd> <form> [env...] — run a given harness from a
# given directory.
_ac_run_with() {
  local runsh="$1" cwd="$2" form="$3"; shift 3
  E2E_RC=0
  E2E_OUT=$(cd "$cwd" && env HOME="$E2E_HOME" TMPDIR="$E2E_DIR/tmp" "$@" "$runsh" --form "$form" \
    --items "$E2E_DIR/items.jsonl" --settings "$E2E_DIR/settings.json" --out "$E2E_DIR/out" 2> "$E2E_DIR/run.err") || E2E_RC=$?
  E2E_ERR=$(cat "$E2E_DIR/run.err")
  printf 'run.sh (%s) --form %s from %s: rc=%s\n--- stdout\n%s\n--- stderr\n%s\n' "$runsh" "$form" "$cwd" "$E2E_RC" "$E2E_OUT" "$E2E_ERR" | _e2e_art
}

if _want ac-planted-modules; then
  _flow_test_begin "ac-planted-modules"
  e2e_new ac-planted-modules
  e2e_describe "a yaml.py or json.py in the directory run.sh is started from is never loaded, even with an empty PYTHONPATH element"
  mkdir -p "$E2E_DIR/tmp" "$E2E_DIR/planted"
  for m in yaml json hashlib; do
    printf 'open(%s, "a").write("%s\\n")\nraise SystemExit("planted %s")\n' "'$E2E_DIR/planted.log'" "$m" "$m" > "$E2E_DIR/planted/$m.py"
  done
  _ac_items
  _ac_stub
  _ac_run_with "$AC_RUN" "$E2E_DIR/planted" alternative PYTHONPATH=":${PYTHONPATH:-}"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal no "$([ -e "$E2E_DIR/planted.log" ] && echo yes || echo no)" "a planted module ran"
  E2E_RC=0
  E2E_OUT=$(cd "$E2E_DIR/planted" && PYTHONPATH=":${PYTHONPATH:-}" python3 "$AC_SUM" --hash "$AC_DIR/current.yaml" 2>&1) || E2E_RC=$?
  e2e_expect_equal "0 $(_ac_hash "$AC_DIR/current.yaml")" "$E2E_RC $E2E_OUT" "summarize.py --hash from the planted directory"
  e2e_expect_equal no "$([ -e "$E2E_DIR/planted.log" ] && echo yes || echo no)" "a planted module ran (summarize.py)"
  e2e_expect_equal 2 "$(jq -r .refused "$E2E_DIR/out/run-alternative.json")" "refused in run-alternative.json"
  e2e_expect_equal 3 "$(jq -r .asked "$E2E_DIR/out/run-alternative.json")" "asked in run-alternative.json"
  e2e_expect_clean_edges
fi

if _want ac-settings-broken; then
  _flow_test_begin "ac-settings-broken"
  e2e_new ac-settings-broken
  e2e_describe "settings the client refuses fail the run on the first item, with no run file, instead of a complete-looking run of no answers"
  mkdir -p "$E2E_DIR/tmp" "$E2E_DIR/out"
  _ac_items
  jq -nc '{systemOne:{provider:"custom",baseUrl:"ftp://example.invalid",model:"jev-1.13.0"}}' > "$E2E_DIR/settings.json"
  # Files from an earlier complete run are removed before this one starts.
  printf '{"form":"current"}\n' > "$E2E_DIR/out/run-current.json"
  printf '{"ref":"old"}\n' > "$E2E_DIR/out/records-current.jsonl"
  _ac_run current
  e2e_expect_equal 1 "$E2E_RC" "exit status"
  e2e_expect_err "invalid-settings"
  e2e_expect_equal 1 "$(wc -l < "$E2E_DIR/out/meta-current.jsonl" | tr -d ' ')" "meta rows written before the stop"
  e2e_expect_equal no "$([ -e "$E2E_DIR/out/run-current.json" ] && echo yes || echo no)" "a run file exists"
  e2e_expect_equal no "$([ -e "$E2E_DIR/out/records-current.jsonl" ] && echo yes || echo no)" "the earlier records file exists"
  _ac_sum
  e2e_expect_equal 2 "$E2E_RC" "summary exit status with no run file"
  e2e_expect_err "a run that stopped part way writes none"
fi

if _want ac-block-leaves-item; then
  _flow_test_begin "ac-block-leaves-item"
  e2e_new ac-block-leaves-item
  e2e_describe "a block that leaves the item file (reviewer text) behind stops the run; a copy outside git records uncommitted_changes as unknown"
  mkdir -p "$E2E_DIR/tmp"
  _ac_items
  _ac_stub
  _ac_plugin_copy
  _ac_run_with "$AC_COPY_RUN" "$E2E_DIR" current
  e2e_expect_equal 0 "$E2E_RC" "exit status with the shipped block"
  e2e_expect_equal '"unknown" "unknown"' "$(jq -c '.uncommitted_changes, .commit' "$E2E_DIR/out/run-current.json" | tr '\n' ' ' | sed 's/ $//')" "uncommitted_changes and commit outside git"
  _ac_plugin_copy 's/^rm -f -- "\$ITEM_FILE"$/: kept/'
  e2e_expect_equal 0 "$(grep -c '^rm -f -- "\$ITEM_FILE"$' "$E2E_DIR/plug/commands/address.md")" "the item-file removal is gone from the copy"
  _ac_run_with "$AC_COPY_RUN" "$E2E_DIR" current
  e2e_expect_equal 1 "$E2E_RC" "exit status with a block that keeps the item file"
  e2e_expect_err "left the item file behind"
fi

if _want ac-truncated-run; then
  _flow_test_begin "ac-truncated-run"
  e2e_new ac-truncated-run
  e2e_describe "an item over the provider's state limit is marked truncated in the meta and is never a raise"
  mkdir -p "$E2E_DIR/tmp"
  _ac_items
  _ac_stub
  jq '.systemOne.stateTokenCap = 15' "$E2E_DIR/settings.json" > "$E2E_DIR/s2.json" && mv "$E2E_DIR/s2.json" "$E2E_DIR/settings.json"
  _ac_run current
  _ac_run alternative
  # Every state is longer than 15 tokens (60 characters), so all three sent
  # items are truncated, and none can be a raise.
  e2e_expect_equal 3 "$(jq -s '[.[] | select(.truncated == true)] | length' "$E2E_DIR/out/meta-current.jsonl")" "truncated items in the meta"
  _ac_sum
  e2e_expect_line "current.truncated=3"
  e2e_expect_line "current.raises.0.5=0"
fi

if _want ac-sum-bar2; then
  _flow_test_begin "ac-sum-bar2"
  e2e_new ac-sum-bar2
  e2e_describe "bar 2 alone fails the result: an alternative that places a labelled P1 lower at a confidence under 0.8"
  _ac_small_items
  # Current: F1 (P3) and F2 (P2) to P1: 2 raises; F3 (P1) kept. Alternative:
  # F1 to P1 (1 raise, at most 2/2), F2 kept, F3 (P1) at P2 with 0.5.
  printf 'pr:1/review:1/F1|P1|1|0|0|0|1|answered\npr:1/review:1/F2|P1|1|0|0|0|1|answered\npr:1/review:1/F3|P1|1|0|0|0|1|answered\n' | _ac_records current "$(_ac_hash "$AC_DIR/current.yaml")"
  printf 'pr:1/review:1/F1|P1|1|0|0|0|1|answered\npr:1/review:1/F2|P2|0|1|0|0|1|answered\npr:1/review:1/F3|P2|0.2|0.6|0.1|0.1|0.5|below-threshold\n' | _ac_records alternative "$(_ac_hash "$AC_DIR/alternative.yaml")"
  _ac_sum
  e2e_expect_line "bar1.raises_at_most_half=pass"
  e2e_expect_line "bar3.answered_at_least_97.5pct=pass"
  e2e_expect_line "bar2.p1_lowered_no_more=fail"
  e2e_expect_line "bar4.rulings=not-needed"
  e2e_expect_line "bars=fail"
  _ac_shipped "$AC_DIR/alternative.yaml"
  _ac_sum --shipped "$E2E_DIR/shipped.yaml" --check ac3
  e2e_expect_equal 1 "$E2E_RC" "--check ac3 with the alternative shipped"
fi

if _want ac-sum-ac1; then
  _flow_test_begin "ac-sum-ac1"
  e2e_new ac-sum-ac1
  e2e_describe "each ac1 check fails on its own: another model, a record for a ref not among the items, a missing record, a state that differs from the one sent"
  _ac_small_items
  OK='pr:1/review:1/F1|P1|1|0|0|0|1|answered
pr:1/review:1/F2|P1|1|0|0|0|1|answered
pr:1/review:1/F3|P1|1|0|0|0|1|answered'
  _ac_base() {
    printf '%s\n' "$OK" | _ac_records current "$(_ac_hash "$AC_DIR/current.yaml")"
    printf '%s\n' "$OK" | _ac_records alternative "$(_ac_hash "$AC_DIR/alternative.yaml")"
    _ac_meta current 1 2 3; _ac_meta alternative 1 2 3
  }
  _ac_base; _ac_sum --check ac1
  e2e_expect_equal 0 "$E2E_RC" "--check ac1 on a complete fixture"
  _ac_base; jq -c 'if .ref == "pr:1/review:1/F2" then .model = "jev-9" else . end' "$E2E_DIR/out/records-current.jsonl" > "$E2E_DIR/x" && mv "$E2E_DIR/x" "$E2E_DIR/out/records-current.jsonl"
  _ac_sum --check ac1
  e2e_expect_equal 1 "$E2E_RC" "--check ac1 with an answer from another model"
  e2e_expect_out "answers from models"
  _ac_base; printf '%s\n' '{"site":"address.category","model":"jev-1.13.0","result":"answered","answer":{"choice":"P1","confidence":1},"ref":"pr:9/review:9/F9"}' >> "$E2E_DIR/out/records-current.jsonl"
  _ac_sum --check ac1
  e2e_expect_equal 1 "$E2E_RC" "--check ac1 with a record for another ref"
  e2e_expect_out "refs not among the items"
  _ac_base; grep -v 'F3"' "$E2E_DIR/out/records-current.jsonl" > "$E2E_DIR/x" && mv "$E2E_DIR/x" "$E2E_DIR/out/records-current.jsonl"
  _ac_sum --check ac1
  e2e_expect_equal 1 "$E2E_RC" "--check ac1 with a record missing"
  e2e_expect_out "items have no record"
  _ac_base
  jq -c '. + {state_sha256: "aaa"}' "$E2E_DIR/out/meta-current.jsonl" > "$E2E_DIR/x" && mv "$E2E_DIR/x" "$E2E_DIR/out/meta-current.jsonl"
  jq -c '. + {state_sha256: "bbb"}' "$E2E_DIR/out/records-current.jsonl" > "$E2E_DIR/x" && mv "$E2E_DIR/x" "$E2E_DIR/out/records-current.jsonl"
  _ac_sum --check ac1
  e2e_expect_equal 1 "$E2E_RC" "--check ac1 with a state that differs from the one sent"
  e2e_expect_out "state differs"
fi

if _want ac-sum-ac2; then
  _flow_test_begin "ac-sum-ac2"
  e2e_new ac-sum-ac2
  e2e_describe "--check ac2 holds after --write and fails once summary.md is edited"
  _ac_small_items
  printf 'pr:1/review:1/F1|P1|1|0|0|0|1|answered\npr:1/review:1/F2|P1|1|0|0|0|1|answered\npr:1/review:1/F3|P1|1|0|0|0|1|answered\n' > "$E2E_DIR/r.txt"
  _ac_records current "$(_ac_hash "$AC_DIR/current.yaml")" < "$E2E_DIR/r.txt"
  _ac_records alternative "$(_ac_hash "$AC_DIR/alternative.yaml")" < "$E2E_DIR/r.txt"
  _ac_sum --check ac2
  e2e_expect_equal 1 "$E2E_RC" "--check ac2 with no summary.md"
  _ac_sum --write
  _ac_sum --check ac2
  e2e_expect_equal 0 "$E2E_RC" "--check ac2 after --write"
  sed -i.bak 's/| Raised above the label at 0.8 | 2 /| Raised above the label at 0.8 | 1 /' "$E2E_DIR/out/summary.md"
  _ac_sum --check ac2
  e2e_expect_equal 1 "$E2E_RC" "--check ac2 after summary.md was edited"
fi

if _want ac-sum-bar3-edge; then
  _flow_test_begin "ac-sum-bar3-edge"
  e2e_new ac-sum-bar3-edge
  e2e_describe "bar 3 holds at exactly 97.5% (39 of 40) and fails at 38 of 40; drift is reported at 80%"
  : > "$E2E_DIR/items.jsonl"; : > "$E2E_DIR/cur.txt"; : > "$E2E_DIR/alt.txt"
  for i in $(seq 1 40); do
    # The 2026-10-07 choice is P2 for items 1 to 32 and P1 for 33 to 40, so a
    # current wording that answers P2 throughout matches 32 of 40 (80%).
    mc=P2; [ "$i" -le 32 ] || mc=P1
    jq -nc --arg r "replay:pr-finding:pr1-review1-F$i" --arg t "item $i" --arg mc "$mc" '{ref:$r,pr:1,finding_id:"F",text:$t,reviewer_priority:"P2",model_choice:$mc}' >> "$E2E_DIR/items.jsonl"
    printf 'pr:1/review:1/F%s|P2|0|1|0|0|1|answered\n' "$i" >> "$E2E_DIR/cur.txt"
    if [ "$i" -eq 40 ]; then printf 'pr:1/review:1/F40|-|||||timeout\n' >> "$E2E_DIR/alt.txt"
    else printf 'pr:1/review:1/F%s|P2|0|1|0|0|1|answered\n' "$i" >> "$E2E_DIR/alt.txt"; fi
  done
  _ac_records current "$(_ac_hash "$AC_DIR/current.yaml")" < "$E2E_DIR/cur.txt"
  _ac_records alternative "$(_ac_hash "$AC_DIR/alternative.yaml")" < "$E2E_DIR/alt.txt"
  _ac_sum
  e2e_expect_line "bar3.answered_at_least_97.5pct=pass"
  e2e_expect_line "drift.current_same_as_2026-10-07=32/40"
  e2e_expect_line "drift=yes"
  sed -i.bak 's#^pr:1/review:1/F39|.*#pr:1/review:1/F39|-|||||timeout#' "$E2E_DIR/alt.txt"
  _ac_records alternative "$(_ac_hash "$AC_DIR/alternative.yaml")" < "$E2E_DIR/alt.txt"
  _ac_sum
  e2e_expect_line "bar3.answered_at_least_97.5pct=fail"
fi

if _want ac-sum-bad-input; then
  _flow_test_begin "ac-sum-bad-input"
  e2e_new ac-sum-bad-input
  e2e_describe "input the summary cannot read exits 2 with a message, never 1 (which means a criterion does not hold)"
  _ac_small_items
  printf 'pr:1/review:1/F1|P1|1|0|0|0|1|answered\npr:1/review:1/F2|P1|1|0|0|0|1|answered\npr:1/review:1/F3|P1|1|0|0|0|1|answered\n' > "$E2E_DIR/r.txt"
  _ac_records current "$(_ac_hash "$AC_DIR/current.yaml")" < "$E2E_DIR/r.txt"
  _ac_records alternative "$(_ac_hash "$AC_DIR/alternative.yaml")" < "$E2E_DIR/r.txt"
  printf 'not json\n' >> "$E2E_DIR/out/records-current.jsonl"
  _ac_sum
  e2e_expect_equal 2 "$E2E_RC" "exit status with a line that is not JSON"
  e2e_expect_err "is not JSON"
  _ac_records current "$(_ac_hash "$AC_DIR/current.yaml")" < "$E2E_DIR/r.txt"
  jq -c 'if .finding_id == "F2" then .reviewer_priority = "p2" else . end' "$E2E_DIR/items.jsonl" > "$E2E_DIR/x" && mv "$E2E_DIR/x" "$E2E_DIR/items.jsonl"
  _ac_sum
  e2e_expect_equal 2 "$E2E_RC" "exit status with a label outside P1/P2/P3/Question"
  e2e_expect_err "reviewer_priority"
  _ac_small_items
  printf 'sites: {}\n' > "$E2E_DIR/empty.yaml"
  _ac_sum --check ac3 --shipped "$E2E_DIR/empty.yaml"
  e2e_expect_equal 2 "$E2E_RC" "--check ac3 with a questions file without the site"
  e2e_expect_err "no usable address.category questions"
fi
