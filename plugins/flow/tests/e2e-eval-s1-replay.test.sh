# shellcheck shell=bash
# End-to-end: the review-precision replay of the System One sites review.dedup
# and review.confidence (bin/flow-eval-s1-replay.sh and its Python half), and
# the scorer and runner changes it needs (bin/_flow_eval.py score-review,
# finalize-review-run). Issue #262.
#
# Each scenario runs the shipped scripts in a scratch repository with its own
# HOME. The provider is a stub (tests/lib/s1_stub.py) for the shadow pass and
# the replay's own server for the on passes; nothing reaches a real provider.
# The scratch trees are built from the shipped interval-algebra case, trap
# halfopen_point_kept, whose one changed hunk is line 47 of intervals.py.
# One artifact per scenario goes to $FLOW_E2E_ARTIFACT_DIR.
# FLOW_E2E_SCENARIOS=a,b runs only the named scenarios.
#
# Ways it can be wrong, written down before the scenarios:
#   R1  a merged finding is scored as a hit when any member sits in the hunk,
#       so merging two distinct defects reads as a precision gain
#   R2  LOW findings are dropped in the filter arm only, so the two arms are
#       scored by different rules; or a demotion is not applied before scoring
#   R3  the converter keeps the plugin prefix of a reviewer name
#       (flow:code-reviewer), so no pair is ever a candidate; or a finding
#       without reviewers reaches dedup with an empty list and blocks the run
#   R4  the scratch tree's HEAD changes between builds, so the kept states
#       cannot be matched; or a tree whose HEAD differs from the recorded one
#       is used anyway
#   R5  the replay merges in Python instead of running flow-s1-dedup.sh, so
#       complete linkage is lost (A~B, B~C same, A~C different makes A+B+C)
#   R6  the replay server answers a state it has no record of, or keys on the
#       record's file digest and matches nothing
#   R7  a pass whose records name another model, or that asked nothing
#       because of the settings, is reported as a good pass
#   R8  an off-mode replay changes the findings
#   R9  the report is written while a merged pair has no hand label, or a
#       merge labelled "different" still counts as a gain
#   R10 the threshold is chosen and judged on the same replication
#   R11 a harness artefact (no candidate pairs, outputs identical at every
#       threshold) is not reported
#   R12 the recovered export attributes no reviewer, or its findings do not
#       re-score to the recorded run
#   R13 finalize-review-run keeps no findings file, or accepts a reviewer the
#       session never dispatched

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

RP_BIN="bin/flow-eval-s1-replay.sh"
RP_CASE=interval-algebra
RP_TRAP=halfopen_point_kept
RP_EVALS="$REPO_ROOT/plugins/flow/evals"
RP_HELPER="$REPO_ROOT/plugins/flow/bin/_flow_eval.py"

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

# _rp_setup <scenario> <purpose> — a scratch repository, and the findings
# (F), work (W) and replay (R) directories beside it.
_rp_setup() {
  if [ -n "${CI:-}" ]; then
    { printf 'progress %s %s\n' "$(date -u +%H:%M:%S)" "$1" >&3; } 2>/dev/null
  fi
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo main
  RP_F="$E2E_DIR/findings"; RP_W="$E2E_DIR/work"; RP_R="$E2E_DIR/replay"
  mkdir -p "$RP_F" "$RP_W" "$RP_R"
}

# _sf <id> <priority> <category> <line> <confidence> <reviewers,comma> [problem] — one
# finding as a review session reports it (file and line, plugin-prefixed
# reviewer names).
_sf() {
  jq -nc --arg id "$1" --arg p "$2" --arg c "$3" --argjson l "$4" --arg conf "$5" --arg r "$6" \
    --arg problem "${7:-problem of $1}" \
    '{id:$id,priority:$p,category:$c,file:"intervals.py",line:$l,problem:$problem,
      suggested_fix:("fix for " + $id),confidence:$conf,reviewers:($r | split(","))}'
}

# _rp_findings <model> <run> <finding json>... — one run's findings file.
_rp_findings() {
  local d="$RP_F/$1/review-b/$RP_CASE/$RP_TRAP"
  shift
  mkdir -p "$d"
  local n="$1"; shift
  printf '%s\n' "$@" | jq -s . > "$d/$n.json"
  printf 'findings %s/%s: %s\n' "${d#"$RP_F"/}" "$n" "$(jq -c . "$d/$n.json")" | _e2e_art
}

_rp() { e2e_run_bin "$RP_BIN" "$@"; }
# _helper <subcommand> ... — bin/_flow_eval.py, run from the scratch repository.
_helper() {
  printf 'code: bin/_flow_eval.py %s\n' "$*" | _e2e_art
  (cd "$E2E_REPO" && python3 "$RP_HELPER" "$@") > "$E2E_DIR/helper.out" 2>&1
}

# _score <file> [flags] — score-review on a findings file, as the record JSON.
_score() {
  local f="$1"; shift
  e2e_run_bin "$RP_BIN" score --evals "$RP_EVALS" --case "$RP_CASE" --trap "$RP_TRAP" --findings "$f" "$@"
}
_field() { jq -c "$1" <<<"$E2E_OUT" 2>/dev/null; }

# Two reviewers' findings on the hit hunk (the second a repeat) and one
# outside every hunk from a reviewer outside the schema, the shape most
# pipeline scenarios use.
H=$(_sf H P1 correctness 47 HIGH flow:code-reviewer "a half-open point interval is kept")
R=$(_sf R P2 error-handling 47 HIGH flow:error-handler-inspector "the empty interval check is skipped for points")
O=$(_sf O P2 conventions 120 MEDIUM flow:convention-checker "the helper name does not follow the module style")

# The stub's one reply to both questions, with probability P and model M.
_both() {
  printf '{"body":{"model":"%s","answers":{"same_defect":{"type":"noul","noul":%s},"claim_supported":{"type":"noul","noul":%s}}}}' \
    "${3:-jev-1.13.0}" "$1" "$2"
}
_reply() {
  printf '{"status":200,"body":{"model":"jev-1.13.0","answers":{"same_defect":{"type":"noul","noul":%s},"claim_supported":{"type":"noul","noul":%s}}}}' "$1" "$2"
}

# _shadow — trees, then the shadow pass against stub a as a custom provider.
_shadow() {
  _rp trees --findings-dir "$RP_F" --work "$RP_W" --replay "$RP_R"
  e2e_expect_equal 0 "$E2E_RC" "trees exit status"
  _rp shadow --findings-dir "$RP_F" --work "$RP_W" --replay "$RP_R" --provider custom \
    --base-url "$(e2e_stub_url a)" --model jev-1.13.0
}
# _on <filter> [threshold options] — one on pass from the table.
_on() {
  local f="$1"; shift
  _rp on --findings-dir "$RP_F" --work "$RP_W" --replay "$RP_R" --model jev-1.13.0 --filter "$f" "$@"
}
_run_dir() { printf '%s/%s/%s/review-b/%s/%s/%s' "$RP_R" "$1" "$2" "$RP_CASE" "$RP_TRAP" "$3"; }

# ----------------------------------------------------------------- scoring

if _want score-merged-representative; then
  _flow_test_begin "score-merged-representative"
  _rp_setup score-merged-representative "a merged finding is scored at its own location, and at any of its locations only with --any-location (R1)"
  printf '%s\n' '[{"id":"R","priority":"P1","category":"correctness","location":"intervals.py:120","locations":["intervals.py:120","intervals.py:47"],"problem":"p","confidence":"HIGH","reviewers":["error-handler-inspector","code-reviewer"],"also_reported_as":[{"id":"H","location":"intervals.py:47","priority":"P2"}]}]' > "$E2E_DIR/merged.json"
  _score "$E2E_DIR/merged.json"
  # By the scoring rules: the one P1 finding cites line 120, outside the only
  # hunk (47), so the run is a miss with that finding false.
  e2e_expect_equal 'false' "$(_field .hit)" "representative-location hit"
  e2e_expect_equal 1 "$(_field .false_findings)" "representative-location false findings"
  _score "$E2E_DIR/merged.json" --any-location
  e2e_expect_equal 'true' "$(_field .hit)" "any-location hit"
  e2e_expect_equal 0 "$(_field .false_findings)" "any-location false findings"
  printf '%s\n' '[{"id":"A","priority":"P2","category":"correctness","location":"intervals.py:46-48","problem":"p"},{"id":"B","priority":"P2","category":"correctness","location":"intervals.py","problem":"p"}]' > "$E2E_DIR/loc.json"
  _score "$E2E_DIR/loc.json"
  # A range is read at its low end, as review.dedup and the old line field
  # read it: 46 is outside the hunk. A location without a line cites no line.
  e2e_expect_equal '[false,2]' "$(_field '[.hit,.false_findings]')" "a range from 46 and a whole-file location"
fi

if _want score-low-rule; then
  _flow_test_begin "score-low-rule"
  _rp_setup score-low-rule "--exclude-low leaves LOW P1/P2 findings out of scoring for every finding set, and --demoted makes a listed finding LOW first (R2)"
  printf '%s\n' "[$(_sf H P1 correctness 47 HIGH flow:code-reviewer),$(_sf X P2 correctness 120 LOW flow:code-reviewer),$(_sf Y P2 correctness 130 MEDIUM flow:code-reviewer)]" > "$E2E_DIR/f.json"
  _score "$E2E_DIR/f.json"
  e2e_expect_equal '[3,2,true]' "$(_field '[.scored_findings,.false_findings,.hit]')" "LOW kept: scored, false, hit"
  _score "$E2E_DIR/f.json" --exclude-low
  e2e_expect_equal '[2,1,1,true]' "$(_field '[.scored_findings,.false_findings,.low_excluded,.hit]')" "LOW excluded: scored, false, low_excluded, hit"
  printf 'Y\n' > "$E2E_DIR/demoted.txt"
  _score "$E2E_DIR/f.json" --exclude-low --demoted "$E2E_DIR/demoted.txt"
  e2e_expect_equal '[1,0,2,true]' "$(_field '[.scored_findings,.false_findings,.low_excluded,.hit]')" "Y demoted, LOW excluded"
  printf 'H\n' > "$E2E_DIR/demoted.txt"
  _score "$E2E_DIR/f.json" --exclude-low --demoted "$E2E_DIR/demoted.txt"
  e2e_expect_equal '[1,1,false]' "$(_field '[.scored_findings,.false_findings,.hit]')" "the hit demoted, LOW excluded: a miss"
fi

# ----------------------------------------------------------------- conversion

if _want convert; then
  _flow_test_begin "convert"
  _rp_setup convert "a session's findings become the schema input of the site scripts: location, reviewers without the plugin prefix, unattributed and unknown for what is missing (R3)"
  printf '%s\n' "[$H,{\"id\":\"H\",\"priority\":\"p2\",\"category\":\"\",\"line\":5,\"problem\":\"no file\",\"confidence\":\"medium\"},\"not an object\",{\"id\":\"Q\",\"priority\":\"P4\",\"file\":\"intervals.py\",\"line\":3}]" > "$E2E_DIR/in.json"
  _rp convert --in "$E2E_DIR/in.json" --out "$E2E_DIR/out.json"
  e2e_expect_line "CONVERT_IN=4"
  e2e_expect_line "CONVERT_OUT=2"
  e2e_expect_line "CONVERT_DROPPED=2"
  e2e_expect_equal '["H","intervals.py:47",["code-reviewer"],"fix for H","HIGH"]' \
    "$(jq -c '.[0] | [.id,.location,.reviewers,.suggested_fix,.confidence]' "$E2E_DIR/out.json")" "first finding"
  e2e_expect_equal '["H-2","unknown",["unattributed"],"uncategorized","P2","MEDIUM"]' \
    "$(jq -c '.[1] | [.id,.location,.reviewers,.category,.priority,.confidence]' "$E2E_DIR/out.json")" "second finding: a repeated id renamed, no file, no reviewers, no category"
fi

# ----------------------------------------------------------------- trees

if _want trees-pinned; then
  _flow_test_begin "trees-pinned"
  _rp_setup trees-pinned "the scratch trees are built with pinned commit dates, so a rebuild has the recorded HEAD, and a tree whose HEAD differs is refused (R4)"
  _rp_findings opus 1 "$H"
  _rp trees --findings-dir "$RP_F" --work "$RP_W" --replay "$RP_R"
  e2e_expect_line "TREES_BUILT=1"
  e2e_expect_line "TREES_STATE=ok"
  HEAD1=$(jq -r '.trees["interval-algebra/halfopen_point_kept"].head' "$RP_R/trees.json")
  _rp trees --findings-dir "$RP_F" --work "$E2E_DIR/work2" --replay "$RP_R"
  e2e_expect_line "TREES_STATE=ok"
  e2e_expect_line "TREES_CHECKED=1"
  HEAD2=$(git -C "$E2E_DIR/work2/trees/$RP_CASE/$RP_TRAP" rev-parse HEAD)
  e2e_expect_equal "$HEAD1" "$HEAD2" "HEAD of a second build in another directory"
  e2e_expect_equal 40 "${#HEAD1}" "length of the recorded HEAD"
  jq '.trees["interval-algebra/halfopen_point_kept"].head = "0000000000000000000000000000000000000000"' "$RP_R/trees.json" > "$E2E_DIR/t.json"
  mv "$E2E_DIR/t.json" "$RP_R/trees.json"
  _rp trees --findings-dir "$RP_F" --work "$E2E_DIR/work3" --replay "$RP_R"
  e2e_expect_line "TREES_STATE=refused"
  e2e_expect_out "TREE_MISMATCH=interval-algebra/halfopen_point_kept"
  e2e_expect_equal 1 "$E2E_RC" "exit status of a refused rebuild"
fi

# ----------------------------------------------------------------- shadow, table, on

if _want pipeline-merge; then
  _flow_test_begin "pipeline-merge"
  _rp_setup pipeline-merge "shadow pass, table and an on pass at 0.8 merge the one candidate pair exactly as a direct flow-s1-dedup.sh call does, and the replay server answers every request from the table (R5, R6)"
  e2e_stub_start a "$(_both 0.97 0.97)"
  _rp_findings opus 1 "$H" "$R" "$O"
  _shadow
  e2e_expect_line "PASS_STATE=ok"
  e2e_expect_line "PAIRS_CANDIDATE_TOTAL=1"
  e2e_expect_line "PAIRS_ASKED_TOTAL=1"
  # H and R are eligible; O's category (conventions) is too, so three
  # findings are asked about: 1 pair + 3 findings.
  e2e_expect_line "CONFIDENCE_ASKED_TOTAL=3"
  e2e_expect_equal 4 "$(e2e_stub_requests a)" "requests received by the stub provider"
  RD=$(_run_dir shadow/base opus 1)
  e2e_expect_equal 1 "$(find "$RD/run/system-one-state" -name 'dedup-*.json' | wc -l | tr -d ' ')" "kept dedup states"
  _rp table --replay "$RP_R" --model jev-1.13.0
  e2e_expect_line "TABLE_ENTRIES=4"
  e2e_expect_line "TABLE_CONFLICTS=0"
  _on dedup --same-defect 0.8
  e2e_expect_line "PASS_STATE=ok"
  e2e_expect_line "SERVER_REQUESTS=1"
  e2e_expect_line "SERVER_HITS=1"
  e2e_expect_line "SERVER_MISSES=0"
  OD=$(_run_dir on/dedup-0.8 opus 1)
  REPLAY_MERGED=$(grep '^MERGED=' "$OD/dedup.out")
  e2e_expect_equal "MERGED=H+R" "$REPLAY_MERGED" "MERGED line of the on pass"
  # The same findings through the shipped script directly, with the stub
  # answering in on mode at the shipped threshold 0.8.
  e2e_user_settings "$(jq -nc --arg u "$(e2e_stub_url a)" '{systemOne:{provider:"custom",baseUrl:$u,model:"jev-1.13.0",uses:{"review.dedup":"on"}}}')"
  e2e_run_bin bin/flow-s1-dedup.sh --findings "$OD/in.json" --out "$E2E_DIR/direct-out.json" \
    --tree "$RP_W/trees/$RP_CASE/$RP_TRAP" --ref-prefix eval:direct
  e2e_expect_equal "$REPLAY_MERGED" "$(grep '^MERGED=' <<<"$E2E_OUT")" "MERGED line of a direct flow-s1-dedup.sh call"
  e2e_expect_equal "$(jq -cS . "$E2E_DIR/direct-out.json")" "$(jq -cS . "$OD/out.json")" "finding set of the direct call compared with the on pass"
fi

if _want pipeline-complete-linkage; then
  _flow_test_begin "pipeline-complete-linkage"
  _rp_setup pipeline-complete-linkage "A~B and B~C answered same, A~C different: the on pass merges A and B only, never all three (R5)"
  # Pairs are asked in the order (file, line distance, a, b): A+B (1), B+C
  # (1), A+C (2); then confidence asks A, B, C.
  e2e_stub_start a "{\"replies\":[$(_reply 0.97 0.97),$(_reply 0.97 0.97),$(_reply 0.03 0.97),$(_reply 0.97 0.97)]}"
  _rp_findings opus 1 "$(_sf A P1 correctness 47 HIGH flow:code-reviewer)" \
    "$(_sf B P2 error-handling 48 HIGH flow:error-handler-inspector)" \
    "$(_sf C P2 correctness 49 HIGH flow:integration-verifier)"
  _shadow
  e2e_expect_line "PAIRS_ASKED_TOTAL=3"
  _rp table --replay "$RP_R" --model jev-1.13.0
  _on dedup --same-defect 0.8
  e2e_expect_line "PASS_STATE=ok"
  OD=$(_run_dir on/dedup-0.8 opus 1)
  e2e_expect_equal "MERGED=A+B" "$(grep '^MERGED=' "$OD/dedup.out")" "MERGED lines"
  e2e_expect_equal 2 "$(jq length "$OD/out.json")" "findings after the on pass"
fi

if _want server-refuses-unknown; then
  _flow_test_begin "server-refuses-unknown"
  _rp_setup server-refuses-unknown "a state the shadow pass never sent (one character changed) gets HTTP 500 from the replay server, and the on pass fails (R6)"
  e2e_stub_start a "$(_both 0.97 0.97)"
  _rp_findings opus 1 "$H" "$R"
  _shadow
  _rp table --replay "$RP_R" --model jev-1.13.0
  F1="$RP_F/opus/review-b/$RP_CASE/$RP_TRAP/1.json"
  jq '.[0].problem = "a half-open point interval is kepT"' "$F1" > "$E2E_DIR/x.json" && mv "$E2E_DIR/x.json" "$F1"
  _on dedup --same-defect 0.8
  e2e_expect_line "PASS_STATE=failed"
  e2e_expect_out "FAIL=server-miss"
  e2e_expect_line "SERVER_MISSES=1"
  e2e_expect_equal 1 "$E2E_RC" "exit status of a failed pass"
  OD=$(_run_dir on/dedup-0.8 opus 1)
  e2e_expect_equal "NO_ANSWER_HTTP_500=1" "$(grep '^NO_ANSWER_HTTP_500=' "$OD/dedup.out")" "the dedup script's count of HTTP 500 answers"
fi

if _want shadow-model-pinned; then
  _flow_test_begin "shadow-model-pinned"
  _rp_setup shadow-model-pinned "a shadow pass whose answers name another model than the pinned one fails (R7)"
  e2e_stub_start a "$(_both 0.97 0.97 jev-latest)"
  _rp_findings opus 1 "$H" "$R"
  _shadow
  e2e_expect_line "PASS_STATE=failed"
  e2e_expect_out "FAIL=model-not-pinned"
  e2e_expect_equal 1 "$E2E_RC" "exit status"
fi

if _want shadow-settings-refused; then
  _flow_test_begin "shadow-settings-refused"
  _rp_setup shadow-settings-refused "a shadow pass that asked nothing because the client refused the settings fails instead of reading as no candidates (R7)"
  _rp_findings opus 1 "$H" "$R"
  _rp trees --findings-dir "$RP_F" --work "$RP_W" --replay "$RP_R"
  _rp shadow --findings-dir "$RP_F" --work "$RP_W" --replay "$RP_R" --provider custom \
    --base-url "http://example.invalid:1" --model jev-1.13.0
  e2e_expect_line "PASS_STATE=failed"
  e2e_expect_out "FAIL=stop-reason:insecure-url"
fi

if _want on-off-identity; then
  _flow_test_begin "on-off-identity"
  _rp_setup on-off-identity "an off-mode replay leaves every finding as it was and sends nothing (R8)"
  e2e_stub_start a "$(_both 0.97 0.03)"
  _rp_findings opus 1 "$H" "$R" "$O"
  _shadow
  _rp table --replay "$RP_R" --model jev-1.13.0
  _on off
  e2e_expect_line "PASS_STATE=ok"
  e2e_expect_line "SERVER_REQUESTS=0"
  OD=$(_run_dir on/off opus 1)
  e2e_expect_equal "$(jq -cS . "$OD/in.json")" "$(jq -cS . "$OD/out.json")" "off-mode output compared with its input"
  e2e_expect_equal "0" "$( [ -s "$OD/demoted.txt" ] && echo 1 || echo 0)" "a demoted list"
fi

# ----------------------------------------------------------------- inspection and the verdict

# _verdict_fixture <p same> — two models, three replications, one trap: H and R
# on the hit hunk (one candidate pair), O outside. Shadow, table, an off pass,
# dedup at 0.8 and 0.9, confidence at 0.9.
_verdict_fixture() {
  e2e_stub_start a "$(_both "$1" 0.97)"
  local m n
  for m in opus sonnet; do for n in 1 2 3; do _rp_findings "$m" "$n" "$H" "$R" "$O"; done; done
  _shadow
  _rp table --replay "$RP_R" --model jev-1.13.0
  _on off
  _on dedup --same-defect 0.8
  _on dedup --same-defect 0.9
  _on confidence --claim-supported 0.9
}

if _want verdict-adopt; then
  _flow_test_begin "verdict-adopt"
  _rp_setup verdict-adopt "the report is refused while a merged pair has no label; with every merge labelled same, dedup clears the bar and confidence does not (R9, R10)"
  _verdict_fixture 0.97
  _rp aggregate --replay "$RP_R" --findings-dir "$RP_F" --evals "$RP_EVALS" --model jev-1.13.0
  e2e_expect_line "AGGREGATE_STATE=refused"
  e2e_expect_line "REASON=unlabelled-merged-pairs"
  e2e_expect_equal 1 "$E2E_RC" "exit status while pairs are unlabelled"
  e2e_expect_equal 0 "$( [ -e "$RP_R/report.md" ] && echo 1 || echo 0)" "a report written while pairs are unlabelled"
  _rp inspect --replay "$RP_R" --evals "$RP_EVALS"
  # One pair (H, R) per run, six runs, the same pair at both dedup points.
  e2e_expect_line "MERGED_PAIRS=6"
  e2e_expect_line "UNLABELLED=6"
  jq '[.[] | .label = "same" | .reason = "both describe the dropped point"]' "$RP_R/merged-pairs.json" > "$E2E_DIR/m.json" && mv "$E2E_DIR/m.json" "$RP_R/merged-pairs.json"
  _rp aggregate --replay "$RP_R" --findings-dir "$RP_F" --evals "$RP_EVALS" --model jev-1.13.0
  e2e_expect_line "AGGREGATE_STATE=ok"
  # Hand computation per model and replication: plain is 1 hit and 2 false
  # findings (R repeats the hit hunk, O is outside): precision 1/3, recall 1,
  # F1 0.5. Dedup merges R into H: 1 hit, 1 false, F1 2/3. Every replication
  # gives the same, so each spread is 0 and 0.667 - 0.5 clears it. Both
  # points tie on replication 1, so the higher one, 0.9, is chosen.
  e2e_expect_line "CHOSEN_REVIEW_DEDUP=0.9"
  e2e_expect_line "RULE_REVIEW_DEDUP=adopt"
  e2e_expect_line "RULE_REVIEW_CONFIDENCE=keep-off"
  e2e_expect_line "JUDGED_REPLICATIONS=2,3"
  e2e_expect_line "CHECK_OFF_IDENTITY=ok"
  e2e_expect_line "CHECK_PARTITION=ok"
  e2e_expect_line "CHECK_PAIRS_CANDIDATE=ok"
  e2e_expect_line "CHECK_CEILING=ok"
  e2e_expect_line "VERDICT_REVIEW_DEDUP=adopt"
  e2e_expect_equal 1 "$( [ -s "$RP_R/report.md" ] && echo 1 || echo 0)" "report.md written"
  e2e_expect_equal '0.667' "$(jq -r '.models.opus.filters["dedup-0.9"].judged.f1 | . * 1000 | round / 1000' "$RP_R/report.json")" "opus judged F1 of dedup at 0.9"
  e2e_expect_equal '0.5' "$(jq -r '.models.opus.plain.judged.f1' "$RP_R/report.json")" "opus judged plain F1"
fi

if _want verdict-merge-guard; then
  _flow_test_begin "verdict-merge-guard"
  _rp_setup verdict-merge-guard "a merge hand-labelled different is undone before the bar is applied, so it is not a gain (R9)"
  _verdict_fixture 0.97
  _rp inspect --replay "$RP_R" --evals "$RP_EVALS"
  jq '[.[] | .label = "different" | .reason = "R is about the empty check, H about the kept point"]' "$RP_R/merged-pairs.json" > "$E2E_DIR/m.json" && mv "$E2E_DIR/m.json" "$RP_R/merged-pairs.json"
  _rp aggregate --replay "$RP_R" --findings-dir "$RP_F" --evals "$RP_EVALS" --model jev-1.13.0
  e2e_expect_line "AGGREGATE_STATE=ok"
  e2e_expect_line "RULE_REVIEW_DEDUP=keep-off"
  e2e_expect_equal '0.667' "$(jq -r '.models.opus.filters["dedup-0.9"].judged_raw.f1 | . * 1000 | round / 1000' "$RP_R/report.json")" "raw F1 of dedup, shown beside"
  e2e_expect_equal '0.5' "$(jq -r '.models.opus.filters["dedup-0.9"].judged.f1' "$RP_R/report.json")" "F1 with different-labelled merges undone"
fi

if _want check-artefacts; then
  _flow_test_begin "check-artefacts"
  _rp_setup check-artefacts "the report flags no candidate pairs in most runs and outputs identical at thresholds the recorded answers fall between (R11)"
  # p = 0.9 gives confidence 0.8: same at 0.6 and 0.8, unsure below 0.9.
  e2e_stub_start a "$(_both 0.9 0.97)"
  _rp_findings opus 1 "$H" "$R"
  _rp_findings opus 2 "$H" "$(_sf R2 P2 correctness 47 HIGH flow:code-reviewer)"
  _rp_findings opus 3 "$H" "$(_sf R3 P2 correctness 47 HIGH flow:code-reviewer)"
  _shadow
  _rp table --replay "$RP_R" --model jev-1.13.0
  _on dedup --same-defect 0.6
  _on dedup --same-defect 0.9
  _rp inspect --replay "$RP_R" --evals "$RP_EVALS"
  jq '[.[] | .label = "same" | .reason = "r"]' "$RP_R/merged-pairs.json" > "$E2E_DIR/m.json" && mv "$E2E_DIR/m.json" "$RP_R/merged-pairs.json"
  _rp aggregate --replay "$RP_R" --findings-dir "$RP_F" --evals "$RP_EVALS" --model jev-1.13.0
  # Two of three runs have one reviewer only, so no candidate pair.
  e2e_expect_line "CHECK_PAIRS_CANDIDATE=flagged"
  e2e_expect_line "CHECK_THRESHOLDS=ok"
  e2e_expect_out "VERDICT_REVIEW_DEDUP=held-by-checks"
  # The 0.9 point given the 0.6 point's output: the thresholds no longer
  # reach the scripts.
  for f in dedup.out out.json; do
    cp "$(_run_dir on/dedup-0.6 opus 1)/$f" "$(_run_dir on/dedup-0.9 opus 1)/$f"
  done
  _rp aggregate --replay "$RP_R" --findings-dir "$RP_F" --evals "$RP_EVALS" --model jev-1.13.0
  e2e_expect_line "CHECK_THRESHOLDS=flagged"
fi

# ----------------------------------------------------------------- recovered export

if _want export-recovered; then
  _flow_test_begin "export-recovered"
  _rp_setup export-recovered "the recovered 2026-09-25 runs are exported from their transcripts with reviewers attributed by cited line, and re-score to the recorded run (R12)"
  T="$E2E_DIR/transcripts"; P="$T/-private-var-x"; S=sid-1
  mkdir -p "$P/$S/subagents"
  FIND="[{\"id\":\"F1\",\"priority\":\"P1\",\"category\":\"correctness\",\"file\":\"intervals.py\",\"line\":47,\"problem\":\"p\",\"confidence\":\"HIGH\"},{\"id\":\"F2\",\"priority\":\"P2\",\"category\":\"error-handling\",\"file\":\"intervals.py\",\"line\":120,\"problem\":\"q\",\"confidence\":\"MEDIUM\"},{\"id\":\"F3\",\"priority\":\"P2\",\"category\":\"tests\",\"file\":\"intervals.py\",\"line\":160,\"problem\":\"r\",\"confidence\":\"MEDIUM\"}]"
  jq -nc --arg t "Consolidated.
\`\`\`json
$FIND
\`\`\`" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' > "$P/$S.jsonl"
  jq -nc '{type:"assistant",message:{content:[{type:"text",text:"intervals.py:46-48 keeps a half-open point"}]}}' > "$P/$S/subagents/agent-a.jsonl"
  printf '{"agentType":"flow:code-reviewer"}' > "$P/$S/subagents/agent-a.meta.json"
  jq -nc '{type:"assistant",message:{content:[{type:"text",text:"At line 120 the error is swallowed."}]}}' > "$P/$S/subagents/agent-b.jsonl"
  printf '{"agentType":"flow:error-handler-inspector"}' > "$P/$S/subagents/agent-b.meta.json"
  jq -nc --arg c "$RP_CASE" --arg t "$RP_TRAP" '[{model:"claude-opus-5-5",arm:"review-b",case:$c,trap:$t,run:1,session_id:"sid-1",
    review:{hit:true,false_findings:2,scored_findings:3,findings_total:3,incomplete:false}},
    {model:"claude-opus-5-5",arm:"review-b-critic",case:$c,trap:$t,run:1,session_id:"sid-2",review:{}}]' > "$E2E_DIR/runs.json"
  _rp export-recovered --runs-json "$E2E_DIR/runs.json" --transcripts "$T" --out "$RP_F"
  e2e_expect_line "EXPORTED=1"
  e2e_expect_line "FINDINGS=3"
  e2e_expect_line "ATTRIBUTED=2"
  e2e_expect_line "UNATTRIBUTED=1"
  e2e_expect_line "RESCORE_MISMATCH=0"
  OUTF="$RP_F/claude-opus-5-5/review-b/$RP_CASE/$RP_TRAP/1.json"
  e2e_expect_equal '[["flow:code-reviewer"],["flow:error-handler-inspector"],["unattributed"]]' "$(jq -c '[.[].reviewers]' "$OUTF")" "attributed reviewers"
  jq '.[0].review.false_findings = 1' "$E2E_DIR/runs.json" > "$E2E_DIR/r2.json"
  _rp export-recovered --runs-json "$E2E_DIR/r2.json" --transcripts "$T" --out "$E2E_DIR/f2"
  e2e_expect_line "RESCORE_MISMATCH=1"
fi

# ----------------------------------------------------------------- the runner's findings file

if _want finalize-findings-out; then
  _flow_test_begin "finalize-findings-out"
  _rp_setup finalize-findings-out "finalize-review-run keeps the parsed findings, and a reviewer the session never dispatched makes the run incomplete (R13)"
  RD="$E2E_DIR/run"; mkdir -p "$RD"
  _stream() {
    jq -nc '{type:"assistant",message:{content:[{type:"tool_use",id:"t1",name:"Agent",input:{subagent_type:"flow:code-reviewer"}},{type:"tool_use",id:"t2",name:"Agent",input:{subagent_type:"flow:error-handler-inspector"}}]}}'
    jq -nc --arg t "$1" '{type:"result",result:$t,session_id:"s",total_cost_usd:0.5,num_turns:3}'
  }
  GOOD="[{\"id\":\"F1\",\"priority\":\"P1\",\"category\":\"correctness\",\"file\":\"intervals.py\",\"line\":47,\"problem\":\"p\",\"suggested_fix\":\"f\",\"confidence\":\"HIGH\",\"reviewers\":[\"code-reviewer\",\"flow:error-handler-inspector\"]}]"
  _stream "\`\`\`json
$GOOD
\`\`\`" > "$RD/stream.jsonl"
  _helper finalize-review-run --run-dir "$RD" --case-dir "$RP_EVALS/$RP_CASE" --arm review-b \
    --case "$RP_CASE" --trap "$RP_TRAP" --run 1 --exit-code 0 --findings-out "$E2E_DIR/kept/1.json" --require-reviewers
  e2e_expect_equal 'false' "$(jq -c .review.incomplete "$RD/result.json")" "incomplete with dispatched reviewers"
  e2e_expect_equal "$(jq -cS . <<<"$GOOD")" "$(jq -cS . "$E2E_DIR/kept/1.json")" "the kept findings file"
  BAD="[{\"id\":\"F1\",\"priority\":\"P1\",\"category\":\"correctness\",\"file\":\"intervals.py\",\"line\":47,\"problem\":\"p\",\"confidence\":\"HIGH\",\"reviewers\":[\"integration-verifier\"]}]"
  _stream "\`\`\`json
$BAD
\`\`\`" > "$RD/stream.jsonl"
  _helper finalize-review-run --run-dir "$RD" --case-dir "$RP_EVALS/$RP_CASE" --arm review-b \
    --case "$RP_CASE" --trap "$RP_TRAP" --run 1 --exit-code 0 --findings-out "$E2E_DIR/kept/2.json" --require-reviewers
  e2e_expect_equal '[true,"reviewers-missing"]' "$(jq -c '[.review.incomplete,.review.reason]' "$RD/result.json")" "a reviewer never dispatched"
  NONE="[{\"id\":\"F1\",\"priority\":\"P2\",\"category\":\"correctness\",\"file\":\"intervals.py\",\"line\":47,\"problem\":\"p\",\"confidence\":\"HIGH\"}]"
  _stream "\`\`\`json
$NONE
\`\`\`" > "$RD/stream.jsonl"
  _helper finalize-review-run --run-dir "$RD" --case-dir "$RP_EVALS/$RP_CASE" --arm review-b \
    --case "$RP_CASE" --trap "$RP_TRAP" --run 1 --exit-code 0 --findings-out "$E2E_DIR/kept/3.json" --require-reviewers
  e2e_expect_equal '[true,"reviewers-missing"]' "$(jq -c '[.review.incomplete,.review.reason]' "$RD/result.json")" "a P2 finding with no reviewers"
  _helper finalize-review-run --run-dir "$RD" --case-dir "$RP_EVALS/$RP_CASE" --arm review-b \
    --case "$RP_CASE" --trap "$RP_TRAP" --run 1 --exit-code 0
  e2e_expect_equal 'false' "$(jq -c .review.incomplete "$RD/result.json")" "the same run without --require-reviewers (the older prompt)"
fi
