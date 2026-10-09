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
# FLOW_E2E_SCENARIOS=a,b runs only the named scenarios, one after another.
# Without it, the scenarios run in FLOW_E2E_JOBS workers at once (default: the
# number of processors, at most 6; 1 runs them one after another). Most of a
# scenario's time is the System One client starting once per question, and
# scenarios run side by side finish sooner. Each worker sources this file again
# for its share and has its own scratch root and stub servers; the shares are
# dealt by the times in RP_WEIGHTS below, longest first.
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
#   R12 the recovered export attributes no reviewer, credits a finding to a
#       subagent whose range or prose only covers its line, credits only one
#       of the subagents that cite it, or its findings do not re-score to the
#       recorded run
#   R14 recovered findings that cannot test review.dedup (most carry four or
#       more reviewers, or most runs have no candidate pair) still give it a
#       verdict, or the report does not say which half the replay tested
#   R13 finalize-review-run keeps no findings file, or accepts a reviewer the
#       session never dispatched
#   R15 a check that never ran (no off pass, no recorded scores) lets the
#       verdict stand, or a threshold point missing a run's output is scored
#       on fewer runs than the plain findings
#   R16 the labelling sheet shows the threshold points or hunks, so a label
#       can follow the score instead of the findings
#   R17 the ceiling is below what a merge can reach, so a correct merge of
#       two findings outside every hunk is flagged
#   R18 a demoted repeat on the hit hunk is counted as a demoted hit
#   R19 the threshold is chosen on a replication it is also judged on, or an
#       on pass that left items unasked reads as complete
#   R20 a check about one site (no candidate pairs) holds the other site's
#       verdict too
#   R21 no score on the replication the threshold is chosen on reads as
#       keep-off instead of missing data
#   R22 a label is changed after the report was read, with nothing recorded,
#       or the labelling sheet points beside the recorded answers
#   R23 the converter changes a run's score (a file that ends in :<line>
#       becomes an in-hunk location) and no check sees it
#   R24 two runs that sent the same state and were given different answers
#       are both replayed the first one
#   R25 one run sent the same state for two findings and was given two
#       answers, and the table keeps the first one without a word
#   R26 most states got no answer in the shadow pass (rate limiting), every
#       check passes and the verdict reads as a result
#   R27 a threshold point answered from an earlier table is scored beside
#       points answered from the current one
#   R28 --allow-unasked lets a shadow pass through whose unasked items the
#       on passes will ask about (a time budget, a provider that stopped
#       answering), so every on pass fails on them later
#   R29 the threshold check flags review.confidence when every answer says
#       the finding is supported, which demotes nothing at any threshold, so
#       a filter that rightly changes nothing holds the verdict
#   R30 --allow-unasked waives the confidence cap but not the dedup cap
#       (STOPPED=max-pairs), so a run with 25 candidate pairs fails anyway
#   R31 the representatives' pass asks again about a merged finding whose
#       state the base pass already asked (two reviewers at one line), and a
#       second, different answer for it fails the table
#   R32 a pair or finding the client failed on (client-error, then
#       client-broken) keeps no state, the shadow pass reads as complete, and
#       every on pass fails later on states the table never had
#   R33 an on pass in which the client gave no answer (a client error, a
#       timeout) reads as complete, so the pair is not merged and the finding
#       not demoted, and the verdict is computed from a degraded pass
#   R34 a pass stopped part way leaves an earlier pass's "ok" beside run
#       directories it rewrote, or a findings file that is not a list is
#       replayed as a run with no findings
#   R35 a scratch tree whose build stopped after the reference commit is
#       recorded as built
#   R36 a questions.yaml whose layout changed stops a pass with a traceback
#       and no STATE line
#   R37 the representatives' shadow pass failed or never ran, and no check
#       holds the verdict
#   R38 the bar's two numeric rules are not applied: a gain inside the spread
#       adopts, or a filter that loses more than one run's worth of recall on
#       the chosen or the judged replications is chosen or adopted
#   R39 the plain findings are scored with session-reported LOW findings
#       kept while the filters leave them out
#   R40 an attempt at a run that gives no parseable findings leaves the
#       earlier attempt's findings file in place
#   R41 the scorer's location reading and review.dedup's differ

# Only tests/run.sh runs this file: it sets REPO_ROOT and loads assert.sh. Run
# any other way, the file stops here with a non-zero exit, because `return`
# alone does not stop a script that is executed rather than sourced, and the
# scenarios below would then run git in the current directory.
{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

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
# RP_FTRAP, when set, names another trap of the case.
_rp_findings() {
  local d="$RP_F/$1/review-b/$RP_CASE/${RP_FTRAP:-$RP_TRAP}"
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
# RP_STRAP, when set, names another trap of the case.
_score() {
  local f="$1"; shift
  e2e_run_bin "$RP_BIN" score --evals "$RP_EVALS" --case "$RP_CASE" --trap "${RP_STRAP:-$RP_TRAP}" --findings "$f" "$@"
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

# _rp_runs_json — $E2E_DIR/runs.json: each findings file's score by the
# unchanged scorer, as the runner records it.
_rp_runs_json() {
  local f rel m n t rec="$E2E_DIR/runs.json"
  printf '[]\n' > "$rec"
  for f in "$RP_F"/*/review-b/"$RP_CASE"/*/*.json; do
    rel=${f#"$RP_F"/}; m=${rel%%/*}; n=$(basename "$f" .json)
    t=$(basename "$(dirname "$f")")
    RP_STRAP="$t" _score "$f"
    jq --arg m "$m" --arg c "$RP_CASE" --arg t "$t" --argjson n "$n" --argjson r "$E2E_OUT" \
      '. + [{model:$m,arm:"review-b",case:$c,trap:$t,run:$n,review:$r}]' "$rec" > "$rec.tmp" && mv "$rec.tmp" "$rec"
  done
}
# _agg [options] — aggregate with the recorded scores.
_agg() {
  _rp aggregate --replay "$RP_R" --findings-dir "$RP_F" --evals "$RP_EVALS" --model jev-1.13.0 --runs-json "$E2E_DIR/runs.json" "$@"
}

# ----------------------------------------------------------------- workers

# Seconds each scenario took, run alone on a Mac, for dealing the shares. A
# scenario missing here counts as 5. verdict-adopt and verdict-merge-guard are
# one unit: the second starts from the fixture the first built, which is kept
# under the worker's scratch root.
RP_WEIGHTS="verdict-recall-guard:100 verdict-adopt,verdict-merge-guard:80 shadow-dedup-cap:80
shadow-allow-unasked:63 verdict-spread:54 ceiling-bound:49 check-artefacts:35 threshold-direction:24
on-interrupted:22 demoted-hits:21 pipeline-reps:18 reps-same-line:18 pipeline-complete-linkage:15
table-per-run:15 pipeline-merge:12 pilot-dedup-not-exercised:12 on-off-identity:11
on-threshold-models:11 on-no-answer:11 server-refuses-unknown:9 table-unanswered:9"

# _rp_workers <n> — every scenario of this file in n workers at once. Each
# worker's output is printed after all have finished, in worker order, and its
# pass and fail counts are added to this shell's.
_rp_workers() {
  local n="$1" file="${BASH_SOURCE[0]}" units="" u w i best listed="," pass fail line
  local load=() share=() pids=()
  for u in $RP_WEIGHTS; do
    units="$units $u"
    listed="$listed${u%:*},"
  done
  for u in $(grep -o '^if _want [a-z0-9-]*' "$file" | cut -d' ' -f3); do
    case "$listed" in *",$u,"*) ;; *) units="$units $u:5" ;; esac
  done
  i=0
  while [ "$i" -lt "$n" ]; do load[i]=0; share[i]=""; i=$((i + 1)); done
  for u in $units; do
    w=${u##*:}
    best=0; i=1
    while [ "$i" -lt "$n" ]; do
      [ "${load[i]}" -lt "${load[best]}" ] && best=$i
      i=$((i + 1))
    done
    share[best]="${share[best]},${u%:*}"
    load[best]=$((load[best] + w))
  done
  i=0
  while [ "$i" -lt "$n" ]; do
    if [ -n "${share[i]}" ]; then
      (
        export FLOW_E2E_SCENARIOS="${share[i]#,}" FLOW_E2E_JOBS=1
        FLOW_TEST_PASS=0; FLOW_TEST_FAIL=0
        # shellcheck disable=SC1090
        source "$file"
        printf 'WORKER pass=%s fail=%s\n' "$FLOW_TEST_PASS" "$FLOW_TEST_FAIL"
      ) > "$E2E_ROOT/worker-$i.out" 2>&1 &
      pids[i]=$!
    fi
    i=$((i + 1))
  done
  i=0
  while [ "$i" -lt "$n" ]; do
    if [ -n "${share[i]}" ]; then
      wait "${pids[i]}"
      printf 'worker %d: %s\n' "$i" "${share[i]#,}"
      grep -v '^WORKER pass=' "$E2E_ROOT/worker-$i.out"
      line=$(grep '^WORKER pass=[0-9]* fail=[0-9]*$' "$E2E_ROOT/worker-$i.out" | tail -1)
      if [ -z "$line" ]; then
        _flow_assert_fail "worker $i (${share[i]#,}) stopped before it printed its counts"
      else
        pass=${line#WORKER pass=}; pass=${pass%% *}
        fail=${line##*fail=}
        FLOW_TEST_PASS=$((FLOW_TEST_PASS + pass))
        FLOW_TEST_FAIL=$((FLOW_TEST_FAIL + fail))
      fi
    fi
    i=$((i + 1))
  done
}

if [ -z "${FLOW_E2E_SCENARIOS:-}" ]; then
  RP_JOBS=${FLOW_E2E_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}
  case "$RP_JOBS" in ''|*[!0-9]*) RP_JOBS=1 ;; esac
  [ "$RP_JOBS" -gt 6 ] && [ -z "${FLOW_E2E_JOBS:-}" ] && RP_JOBS=6
  if [ "$RP_JOBS" -gt 1 ]; then
    _rp_workers "$RP_JOBS"
    return 0
  fi
fi

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
  # A findings file that is not a list is refused, not converted as a run
  # with no findings (R34).
  printf '{}\n' > "$E2E_DIR/obj.json"
  _rp convert --in "$E2E_DIR/obj.json" --out "$E2E_DIR/obj-out.json"
  e2e_expect_line "STATE=failed"
  e2e_expect_out "is not a JSON list of findings"
  e2e_expect_equal 1 "$E2E_RC" "exit status for a findings file that is not a list"
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
  # A tree whose build stopped after the reference commit is not recorded as
  # built, even with no record to compare it with (R35).
  git -C "$E2E_DIR/work2/trees/$RP_CASE/$RP_TRAP" reset -q --keep HEAD~1
  _rp trees --findings-dir "$RP_F" --work "$E2E_DIR/work2" --replay "$E2E_DIR/replay2"
  e2e_expect_line "TREES_STATE=refused"
  e2e_expect_out "TREE_INVALID=interval-algebra/halfopen_point_kept"
  e2e_expect_out "(not two commits)"
  e2e_expect_equal 0 "$( [ -e "$E2E_DIR/replay2/trees.json" ] && echo 1 || echo 0)" "a trees.json written for an incomplete tree"
  # A complete tree switched to another branch at the same commit, and one
  # whose module was edited, are refused too: both still have two commits.
  _rp trees --findings-dir "$RP_F" --work "$E2E_DIR/work4" --replay "$E2E_DIR/replay4"
  e2e_expect_line "TREES_STATE=ok"
  git -C "$E2E_DIR/work4/trees/$RP_CASE/$RP_TRAP" checkout -q -b other
  _rp trees --findings-dir "$RP_F" --work "$E2E_DIR/work4" --replay "$E2E_DIR/replay4"
  e2e_expect_line "TREES_STATE=refused"
  e2e_expect_out "(not on review-candidate)"
  git -C "$E2E_DIR/work4/trees/$RP_CASE/$RP_TRAP" checkout -q review-candidate
  printf '# edited\n' >> "$E2E_DIR/work4/trees/$RP_CASE/$RP_TRAP/intervals.py"
  _rp trees --findings-dir "$RP_F" --work "$E2E_DIR/work4" --replay "$E2E_DIR/replay4"
  e2e_expect_line "TREES_STATE=refused"
  e2e_expect_out "(uncommitted changes)"
  # A tree is built beside its place: a build an earlier run left behind is
  # cleared first, and a build that fails leaves nothing in either place, so
  # the next run builds it again instead of finding a tree to check.
  mkdir -p "$E2E_DIR/work5/trees/$RP_CASE/$RP_TRAP.building"
  printf 'left by a stopped build\n' > "$E2E_DIR/work5/trees/$RP_CASE/$RP_TRAP.building/intervals.py"
  RP_FTRAP=no_such_trap _rp_findings opus 1 "$H"
  _rp trees --findings-dir "$RP_F" --work "$E2E_DIR/work5" --replay "$E2E_DIR/replay5"
  e2e_expect_line "STATE=failed"
  e2e_expect_out "could not build $RP_CASE/no_such_trap"
  e2e_expect_equal 1 "$E2E_RC" "exit status of a failed build"
  e2e_expect_equal 2 "$(git -C "$E2E_DIR/work5/trees/$RP_CASE/$RP_TRAP" rev-list --count review-candidate 2>/dev/null)" "commits of the tree built over an earlier stopped build"
  e2e_expect_equal 0 "$( [ -e "$E2E_DIR/work5/trees/$RP_CASE/$RP_TRAP.building" ] && echo 1 || echo 0)" "the earlier build left in place"
  e2e_expect_equal 0 "$( [ -e "$E2E_DIR/work5/trees/$RP_CASE/no_such_trap" ] && echo 1 || echo 0)" "a failed build in place"
  e2e_expect_equal 0 "$( [ -e "$E2E_DIR/work5/trees/$RP_CASE/no_such_trap.building" ] && echo 1 || echo 0)" "a failed build beside its place"
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
  e2e_expect_equal 0 "$(find "$RD/run" -name '*.lock' | wc -l | tr -d ' ')" "lock files kept beside the records"
  # The run directory holds only what the replay README lists as kept, so a
  # copy into the eval results needs no pruning: the site scripts' stderr and
  # review.dedup's unchanged copy of the findings go to the work directory.
  e2e_expect_equal "confidence.out dedup.out in.json" \
    "$(find "$RD" -maxdepth 1 -type f -exec basename {} \; | sort | tr '\n' ' ' | sed 's/ $//')" "files in a shadow run directory"
  e2e_expect_equal 0 "$(find "$RP_R/shadow" \( -name '*.err' -o -name 'dedup-out.json' \) | wc -l | tr -d ' ')" "stderr logs and dedup output under the kept shadow pass"
  RL="$RP_W/logs/shadow-base/opus/review-b/$RP_CASE/$RP_TRAP/1"
  e2e_expect_equal "confidence.err dedup-out.json dedup.err" \
    "$(find "$RL" -maxdepth 1 -type f -exec basename {} \; | sort | tr '\n' ' ' | sed 's/ $//')" "files the shadow run left in the work directory"
  # Kept script output names no directory of the machine that ran it.
  e2e_expect_equal 0 "$(cat "$RD/dedup.out" "$RD/confidence.out" | grep -c -F "$E2E_DIR")" "lines of kept script output naming the test directory"
  e2e_expect_equal "DEDUP_OUT=<work>/logs/shadow-base/opus/review-b/$RP_CASE/$RP_TRAP/1/dedup-out.json" \
    "$(grep '^DEDUP_OUT=' "$RD/dedup.out")" "the dedup output line as kept"
  # An on pass's per-run output is rebuilt from table.json, so git does not
  # take it into the eval results; each on pass's pass.json is kept.
  e2e_expect_equal 0 "$(git -C "$REPO_ROOT" check-ignore -q --no-index plugins/flow/evals/results-x/replay/on/dedup-0.8/opus/review-b/c/t/1/out.json; echo $?)" "check-ignore status of an on pass's per-run output"
  e2e_expect_equal 1 "$(git -C "$REPO_ROOT" check-ignore -q --no-index plugins/flow/evals/results-x/replay/on/dedup-0.8/pass.json; echo $?)" "check-ignore status of an on pass's pass.json"
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

if _want pipeline-reps; then
  _flow_test_begin "pipeline-reps"
  _rp_setup pipeline-reps "a merged finding carries both locations, so its confidence state is new: the reps shadow pass asks it, and the dedup-then-confidence pass is answered for it from the table"
  e2e_stub_start a "$(_both 0.97 0.97)"
  _rp_findings opus 1 "$H" "$(_sf R P2 error-handling 50 HIGH flow:error-handler-inspector "the empty interval check is skipped")" "$O"
  _shadow
  _rp table --replay "$RP_R" --model jev-1.13.0
  e2e_expect_line "TABLE_ENTRIES=4"
  _on dedup --same-defect 0.8
  e2e_expect_equal "MERGED=H+R" "$(grep '^MERGED=' "$(_run_dir on/dedup-0.8 opus 1)/dedup.out")" "MERGED line"
  _rp shadow --findings-dir "$RP_F" --work "$RP_W" --replay "$RP_R" --provider custom \
    --base-url "$(e2e_stub_url a)" --model jev-1.13.0 --set reps
  e2e_expect_line "PASS_STATE=ok"
  # Only H, now carrying intervals.py:47 and intervals.py:50, is a merged finding.
  e2e_expect_line "CONFIDENCE_ASKED_TOTAL=1"
  _rp table --replay "$RP_R" --model jev-1.13.0
  e2e_expect_line "TABLE_ENTRIES=5"
  _on dedup-confidence --same-defect 0.8 --claim-supported 0.9
  e2e_expect_line "PASS_STATE=ok"
  # One pair, then confidence for the merged H and for O.
  e2e_expect_line "SERVER_REQUESTS=3"
  e2e_expect_line "SERVER_MISSES=0"
  e2e_expect_line "SERVER_UNANSWERED=0"
  e2e_expect_equal 1 "$(grep -c '^S1_CONFIDENCE_RESULT=H STATE=answered VERDICT=supported' "$(_run_dir on/dedup-0.8-confidence-0.9 opus 1)/confidence.out")" "confidence answer for the merged H"
fi

if _want on-threshold-models; then
  _flow_test_begin "on-threshold-models"
  _rp_setup on-threshold-models "the sweep value applies even when questions.yaml has a per-model threshold for the pinned model: the copy's models entry is removed"
  e2e_plugin_copy system-one/questions.yaml "$(sed 's/^        default: 0.8$/        default: 0.8\
        models:\
          jev-1.13.0: 0.95/' "$E2E_PLUGIN_DIR/system-one/questions.yaml")"
  # p = 0.9 is confidence 0.8: unsure at the planted 0.95, same at the sweep 0.6.
  e2e_stub_start a "$(_both 0.9 0.97)"
  _rp_findings opus 1 "$H" "$R"
  _shadow
  _rp table --replay "$RP_R" --model jev-1.13.0
  _on dedup --same-defect 0.6
  e2e_expect_line "PASS_STATE=ok"
  e2e_expect_equal "MERGED=H+R" "$(grep '^MERGED=' "$(_run_dir on/dedup-0.6 opus 1)/dedup.out")" "MERGED line at the sweep value"
fi

# ----------------------------------------------------------------- inspection and the verdict

# _on_written off | confidence <claim_supported> [<tag>...] — an on pass
# written by the test instead of run, for a scenario about the bar and the
# checks rather than the site scripts (the scenarios above run the sites at
# a threshold and check what they do). Each run's findings are those the
# shadow pass converted, unchanged; at a confidence point the findings whose
# problem carries one of the tags are demoted, and every finding's answer is
# taken from table.json by the digest of its shadow state, as the replay
# server serves it. The scenario fails when the tags and the answers
# disagree: a finding is demoted by a "not supported" answer (p below 0.5)
# whose confidence, 1 - 2p, is at or above the threshold, and a tagged
# finding without such an answer, or an untagged one with it, is refused. A
# real pass over the verdict fixture writes the same pass.json, out.json and
# demoted lists.
_on_written() {
  local filter="$1" t="null" point=off tags='[]' runs='{}' served='[]' d key od sums next
  shift
  if [ "$filter" = confidence ]; then
    t="$1"; point="confidence-$1"; shift
    tags=$(printf '%s\n' "$@" | jq -Rsc 'split("\n") | map(select(. != ""))')
  fi
  printf 'on pass %s written by the test: demoted the findings tagged %s\n' "$point" "$tags" | _e2e_art
  for d in "$RP_R"/shadow/base/*/*/*/*/*/; do
    key=${d#"$RP_R/shadow/base/"}; key=${key%/}
    od="$RP_R/on/$point/$key"
    mkdir -p "$od"
    cp "$d/in.json" "$od/in.json"
    cp "$d/in.json" "$od/out.json"
    jq -r --argjson tags "$tags" '.[] | select(.problem as $p | any($tags[]; . as $t | $p | contains($t))) | .id' \
      "$d/in.json" > "$od/demoted.txt"
    runs=$(jq -c --arg k "$key" --rawfile dm "$od/demoted.txt" \
      '. + {($k): {merged: [], demoted: ($dm | split("\n") | map(select(. != "")) | sort), unasked: []}}' <<<"$runs")
    [ -s "$od/demoted.txt" ] || rm -f "$od/demoted.txt"
    [ "$filter" = confidence ] || continue
    sums=$(jq -r '.[].id' "$d/in.json" | while IFS= read -r id; do
      printf '%s %s\n' "$id" "$(_e2e_sha256 "$d/run/system-one-state/confidence-$id.json")"
    done | jq -Rsc 'split("\n") | map(select(. != "") | split(" ") | {id: .[0], key: .[1]})')
    if next=$(jq -c --arg run "$key" --argjson t "$t" --argjson sums "$sums" --argjson tags "$tags" --slurpfile table "$RP_R/table.json" \
      --slurpfile f "$d/in.json" --argjson acc "$served" -n '
      ($f[0] | map({(.id): .problem}) | add) as $prob
      | $acc + [$sums[] | {id, key, p: $table[0].entries[.key].runs[$run]}
                | . as $s | {id, key, p, tagged: ($prob[$s.id] as $q | any($tags[]; . as $t | $q | contains($t)))}
                | if .p == null then error("no answer in table.json for \(.id) of \($run)")
                  elif .tagged != (.p < 0.5 and (1 - 2 * .p) >= $t)
                  then error("the tags and the answer disagree for \(.id) of \($run) (p \(.p), threshold \($t))")
                  else [$run, .key, .p] end]'); then
      served=$next
    else
      _flow_assert_fail "$E2E_NAME: on pass $point written by the test: $key"
    fi
  done
  served=$(jq -c 'unique' <<<"$served")
  jq -n --arg point "$point" --arg filter "$filter" --argjson t "$t" --argjson runs "$runs" --argjson served "$served" \
    '{point:$point, filter:$filter, same_defect:null, claim_supported:$t, model:"jev-1.13.0", state:"ok", fails:[],
      server:{hits:($served | length), misses:0, requests:($served | length), unanswered:0}, served:$served, runs:$runs}' \
    > "$RP_R/on/$point/pass.json"
}

# _verdict_fixture <p same> — two models, three replications, one trap: H and R
# on the hit hunk (one candidate pair), O outside. Shadow, table, dedup at 0.8
# and 0.9, an off pass and confidence at 0.6 and 0.9 written by the test (the
# answers, p 0.97, demote nothing), and the recorded scores. The scenarios
# that use it are about the bar and the checks; on-off-identity and the
# confidence scenarios run those passes.
# The first scenario of a run to ask for a fixture builds it and keeps a copy
# of the findings, work and replay directories and runs.json, taken before
# the scenario changes anything; a later scenario of the same run starts from
# that copy. Every path the replay keeps is relative to its directory, and
# trees.json holds the tree's HEAD only, so the copy replays as the original.
_verdict_fixture() {
  local cache="$E2E_ROOT/fixture-verdict-$1" m n
  if [ -d "$cache" ]; then
    printf 'fixture: a copy of the one built by an earlier scenario of this run (p same %s)\n' "$1" | _e2e_art
    rm -rf "$RP_F" "$RP_W" "$RP_R"
    cp -R "$cache/findings" "$RP_F" && cp -R "$cache/work" "$RP_W" && cp -R "$cache/replay" "$RP_R" \
      && cp "$cache/runs.json" "$E2E_DIR/runs.json" \
      || _flow_assert_fail "$E2E_NAME: could not copy the verdict fixture"
    # The copied tree is checked against the recorded HEAD, as a build is.
    _rp trees --findings-dir "$RP_F" --work "$RP_W" --replay "$RP_R"
    e2e_expect_equal 0 "$E2E_RC" "trees exit status"
    e2e_expect_line "TREES_CHECKED=1"
    return 0
  fi
  e2e_stub_start a "$(_both "$1" 0.97)"
  for m in opus sonnet; do for n in 1 2 3; do _rp_findings "$m" "$n" "$H" "$R" "$O"; done; done
  _shadow
  _rp table --replay "$RP_R" --model jev-1.13.0
  _on_written off
  _on dedup --same-defect 0.8
  _on dedup --same-defect 0.9
  _on_written confidence 0.6
  _on_written confidence 0.9
  _rp_runs_json
  mkdir -p "$cache.building"
  cp -R "$RP_F" "$cache.building/findings" && cp -R "$RP_W" "$cache.building/work" \
    && cp -R "$RP_R" "$cache.building/replay" && cp "$E2E_DIR/runs.json" "$cache.building/runs.json" \
    && mv "$cache.building" "$cache" || rm -rf "$cache.building"
}

if _want verdict-adopt; then
  _flow_test_begin "verdict-adopt"
  _rp_setup verdict-adopt "the report is refused while a merged pair has no label; with every merge labelled same, dedup clears the bar and confidence does not (R9, R10)"
  _verdict_fixture 0.97
  _agg
  e2e_expect_line "AGGREGATE_STATE=refused"
  e2e_expect_line "REASON=unlabelled-merged-pairs"
  e2e_expect_equal 1 "$E2E_RC" "exit status while pairs are unlabelled"
  e2e_expect_equal 0 "$( [ -e "$RP_R/report.md" ] && echo 1 || echo 0)" "a report written while pairs are unlabelled"
  _rp inspect --replay "$RP_R" --evals "$RP_EVALS"
  # One pair (H, R) per run, six runs, the same pair at both dedup points.
  e2e_expect_line "MERGED_PAIRS=6"
  e2e_expect_line "UNLABELLED=6"
  # The sheet shows the findings and the state, not the threshold points or
  # the hunks (R16).
  e2e_expect_equal '["a","a_location","a_problem","b","b_location","b_problem","label","reason","run","state"]' \
    "$(jq -c '[.[] | keys] | unique | .[0]' "$RP_R/merged-pairs.json")" "fields of the labelling sheet"
  e2e_expect_equal 1 "$(jq '[.[] | keys] | unique | length' "$RP_R/merged-pairs.json")" "one field set for every row"
  jq '[.[] | .label = "same" | .reason = "both describe the dropped point"]' "$RP_R/merged-pairs.json" > "$E2E_DIR/m.json" && mv "$E2E_DIR/m.json" "$RP_R/merged-pairs.json"
  _agg
  e2e_expect_line "AGGREGATE_STATE=ok"
  AGG_OUT=$E2E_OUT
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
  e2e_expect_line "CHECK_RESCORE=ok"
  e2e_expect_line "CHECK_COVERAGE=ok"
  e2e_expect_line "CHECK_UNASKED=ok"
  e2e_expect_line "CHECK_THRESHOLDS=ok"
  e2e_expect_line "CHECK_TABLE_IDENTITY=ok"
  e2e_expect_line "CHECK_ANSWERS=ok"
  e2e_expect_equal '0.667' "$(jq -r '.models.opus.filters["dedup-0.9"].judged.f1 | . * 1000 | round / 1000' "$RP_R/report.json")" "opus judged F1 of dedup at 0.9"
  e2e_expect_equal '0.5' "$(jq -r '.models.opus.plain.judged.f1' "$RP_R/report.json")" "opus judged plain F1"
  # After the labels, the report lists each pair's points and hunks.
  e2e_expect_equal '["same",["dedup-0.8","dedup-0.9"],"hunk 1 (47-47)"]' \
    "$(jq -c '.merged_pairs[0] | [.label, .points, .a_hunk]' "$RP_R/report.json")" "a merged pair in report.json"
  e2e_expect_equal '[]' "$(jq -c '[.runs[].unasked[]]' "$RP_R/on/dedup-0.9/pass.json")" "unasked items recorded by a clean on pass"
  # The same report through bin/_flow_eval.py replay-aggregate.
  _helper replay-aggregate --replay "$RP_R" --findings-dir "$RP_F" --evals "$RP_EVALS" --model jev-1.13.0 --runs-json "$E2E_DIR/runs.json"
  e2e_expect_equal "$AGG_OUT" "$(cat "$E2E_DIR/helper.out")" "output of _flow_eval.py replay-aggregate compared with aggregate"

  # Checks that did not run hold the verdict (R15): no recorded scores.
  _rp aggregate --replay "$RP_R" --findings-dir "$RP_F" --evals "$RP_EVALS" --model jev-1.13.0
  e2e_expect_line "CHECK_RESCORE=not-checked"
  e2e_expect_line "RULE_REVIEW_DEDUP=adopt"
  e2e_expect_line "VERDICT_REVIEW_DEDUP=held-by-checks"
  # No off pass.
  mv "$RP_R/on/off" "$E2E_DIR/off-aside"
  _agg
  e2e_expect_line "CHECK_OFF_IDENTITY=not-run"
  e2e_expect_line "VERDICT_REVIEW_DEDUP=held-by-checks"
  mv "$E2E_DIR/off-aside" "$RP_R/on/off"
  # One run's output missing at one point, then one run's findings changed
  # after the passes: that point is not scored on the same runs.
  OUT9="$(_run_dir on/dedup-0.9 sonnet 3)/out.json"
  mv "$OUT9" "$E2E_DIR/out-aside.json"
  _agg
  e2e_expect_line "CHECK_COVERAGE=flagged"
  e2e_expect_line "VERDICT_REVIEW_DEDUP=held-by-checks"
  e2e_expect_equal '["sonnet/review-b/interval-algebra/halfopen_point_kept/3 (no output)"]' \
    "$(jq -c '.checks.coverage.points["dedup-0.9"]' "$RP_R/report.json")" "the run the coverage check names"
  mv "$E2E_DIR/out-aside.json" "$OUT9"
  F3="$RP_F/sonnet/review-b/$RP_CASE/$RP_TRAP/3.json"
  cp "$F3" "$E2E_DIR/f3-aside.json"
  jq '.[2].problem = "the helper name is wrong"' "$E2E_DIR/f3-aside.json" > "$F3"
  _rp_runs_json
  _agg
  e2e_expect_line "CHECK_COVERAGE=flagged"
  e2e_expect_line "CHECK_RESCORE=ok"
  cp "$E2E_DIR/f3-aside.json" "$F3"
  _rp_runs_json
  # An on pass that left a run's items unasked (R19).
  cp "$RP_R/on/dedup-0.9/pass.json" "$E2E_DIR/pass-aside.json"
  jq '.runs["opus/review-b/interval-algebra/halfopen_point_kept/1"].unasked = ["confidence:budget"]' "$E2E_DIR/pass-aside.json" > "$RP_R/on/dedup-0.9/pass.json"
  _agg
  e2e_expect_line "CHECK_UNASKED=flagged"
  e2e_expect_line "VERDICT_REVIEW_DEDUP=held-by-checks"
  cp "$E2E_DIR/pass-aside.json" "$RP_R/on/dedup-0.9/pass.json"
  # The threshold chosen on a replication it is judged on (R19).
  _agg --choose 2 --judge 2,3
  e2e_expect_line "AGGREGATE_STATE=refused"
  e2e_expect_line "REASON=choose-in-judge"
  e2e_expect_equal 1 "$E2E_RC" "exit status when --choose is in --judge"
  _agg
  e2e_expect_line "VERDICT_REVIEW_DEDUP=adopt"
  e2e_expect_line "VERDICT_REVIEW_CONFIDENCE=keep-off"
  # The table run again after the on passes, with another answer to one
  # run's pair: the points still hold the earlier answer (R27).
  cp "$RP_R/table.json" "$E2E_DIR/table-aside.json"
  jq '.entries |= with_entries(if .value.site == "review.dedup" then .value.runs["opus/review-b/interval-algebra/halfopen_point_kept/1"] = 0.5 else . end)' \
    "$E2E_DIR/table-aside.json" > "$RP_R/table.json"
  _agg
  e2e_expect_line "CHECK_TABLE_IDENTITY=flagged"
  e2e_expect_line "VERDICT_REVIEW_DEDUP=held-by-checks"
  e2e_expect_line "VERDICT_REVIEW_CONFIDENCE=held-by-checks"
  e2e_expect_equal '["dedup-0.8","dedup-0.9"]' "$(jq -c '.checks["table-identity"].points | keys' "$RP_R/report.json")" "the points answered from the earlier table"
  cp "$E2E_DIR/table-aside.json" "$RP_R/table.json"
  # A pass that kept no record of the answers it was served.
  cp "$RP_R/on/confidence-0.6/pass.json" "$E2E_DIR/pass-aside.json"
  jq 'del(.served)' "$E2E_DIR/pass-aside.json" > "$RP_R/on/confidence-0.6/pass.json"
  _agg
  e2e_expect_line "CHECK_TABLE_IDENTITY=flagged"
  cp "$E2E_DIR/pass-aside.json" "$RP_R/on/confidence-0.6/pass.json"
  _agg
  e2e_expect_line "CHECK_TABLE_IDENTITY=ok"
  # A check about one site holds only that site's verdict (R20): no
  # candidate pair in four of six shadow runs holds review.dedup, and
  # review.confidence still gets its rule.
  cp "$RP_R/shadow/base/pass.json" "$E2E_DIR/shadow-aside.json"
  jq '.runs |= with_entries(if (.key | test("/[12]$")) then .value.pairs_candidate = 0 else . end)' \
    "$E2E_DIR/shadow-aside.json" > "$RP_R/shadow/base/pass.json"
  _agg
  e2e_expect_line "CHECK_PAIRS_CANDIDATE=flagged"
  e2e_expect_line "VERDICT_REVIEW_DEDUP=held-by-checks"
  e2e_expect_line "VERDICT_REVIEW_CONFIDENCE=keep-off"
  e2e_expect_equal '[["pairs-candidate"],[]]' \
    "$(jq -c '[.sites["review.dedup"].held_by, .sites["review.confidence"].held_by]' "$RP_R/report.json")" "the checks holding each site"
  cp "$E2E_DIR/shadow-aside.json" "$RP_R/shadow/base/pass.json"
  # Every opus run of replication 1 incomplete: no point has a score on the
  # replication the threshold is chosen on, which is missing data, not
  # keep-off (R21).
  jq '[.[] | if .model == "opus" and .run == 1 then .review.incomplete = true else . end]' "$E2E_DIR/runs.json" > "$E2E_DIR/runs-inc.json"
  _rp aggregate --replay "$RP_R" --findings-dir "$RP_F" --evals "$RP_EVALS" --model jev-1.13.0 --runs-json "$E2E_DIR/runs-inc.json"
  e2e_expect_line "RULE_REVIEW_DEDUP=no-score-on-choose"
  e2e_expect_line "RULE_REVIEW_CONFIDENCE=no-score-on-choose"
  # The labelling sheet points at a copy of each state, not at the shadow
  # run whose records hold the answers (R22).
  e2e_expect_equal 'label-states/opus/review-b/interval-algebra/halfopen_point_kept/1/dedup-H+R.json' \
    "$(jq -r '.[0].state' "$RP_R/merged-pairs.json")" "state path of the first labelling row"
  e2e_expect_equal "$(cat "$RP_R/shadow/base/opus/review-b/$RP_CASE/$RP_TRAP/1/run/system-one-state/dedup-H+R.json")" \
    "$(cat "$RP_R/$(jq -r '.[0].state' "$RP_R/merged-pairs.json")")" "the copied state"
  # A label changed after a report exists is refused without --relabel, and
  # the report keeps the record of the change (R22).
  _agg
  e2e_expect_line "AGGREGATE_STATE=ok"
  jq '.[0].label = "different"' "$RP_R/merged-pairs.json" > "$E2E_DIR/m.json" && mv "$E2E_DIR/m.json" "$RP_R/merged-pairs.json"
  cp "$RP_R/report.json" "$E2E_DIR/report-before.json"
  _agg
  e2e_expect_line "AGGREGATE_STATE=refused"
  e2e_expect_line "REASON=labels-changed-after-report"
  e2e_expect_equal 1 "$E2E_RC" "exit status when the labels changed after a report"
  e2e_expect_equal same "$(cmp -s "$E2E_DIR/report-before.json" "$RP_R/report.json" && echo same || echo changed)" "report.json after a refused aggregate"
  _agg --relabel
  e2e_expect_line "AGGREGATE_STATE=ok"
  e2e_expect_equal "[\"$(jq -r .labels.sha256 "$E2E_DIR/report-before.json")\"]" \
    "$(jq -c .labels.relabelled_from "$RP_R/report.json")" "the label change recorded in report.json"
  _agg
  e2e_expect_line "AGGREGATE_STATE=ok"
  e2e_expect_equal 1 "$(jq '.labels.relabelled_from | length' "$RP_R/report.json")" "the record kept by a later aggregate"
  e2e_expect_equal 1 "$(grep -c 'changed after a report had been written (--relabel): 1' "$RP_R/report.md")" "the record in report.md"
  # Reformatting the sheet without changing a label is not a change.
  jq . "$RP_R/merged-pairs.json" > "$E2E_DIR/m.json" && jq -c . "$E2E_DIR/m.json" > "$RP_R/merged-pairs.json"
  _agg
  e2e_expect_line "AGGREGATE_STATE=ok"
fi

if _want verdict-merge-guard; then
  _flow_test_begin "verdict-merge-guard"
  _rp_setup verdict-merge-guard "a merge hand-labelled different is undone before the bar is applied, so it is not a gain (R9)"
  _verdict_fixture 0.97
  _rp inspect --replay "$RP_R" --evals "$RP_EVALS"
  jq '[.[] | .label = "different" | .reason = "R is about the empty check, H about the kept point"]' "$RP_R/merged-pairs.json" > "$E2E_DIR/m.json" && mv "$E2E_DIR/m.json" "$RP_R/merged-pairs.json"
  _agg
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
  _on confidence --claim-supported 0.6
  _on confidence --claim-supported 0.9
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

if _want threshold-direction; then
  _flow_test_begin "threshold-direction"
  _rp_setup threshold-direction "identical confidence outputs at 0.6 and 0.9 are not flagged when every answer is supported, and are flagged when an unsupported answer falls between the two points (R29)"
  # p = 0.81: supported, confidence 0.62, between 0.6 and 0.9. It demotes
  # nothing at either point, so the outputs are rightly identical.
  e2e_stub_start a "$(_both 0.97 0.81)"
  _rp_findings opus 1 "$H"
  _shadow
  e2e_expect_line "PASS_STATE=ok"
  _rp table --replay "$RP_R" --model jev-1.13.0
  for t in 0.6 0.9; do _on dedup --same-defect "$t"; _on confidence --claim-supported "$t"; done
  e2e_expect_equal '|' "$(cat "$(_run_dir on/confidence-0.6 opus 1)/demoted.txt" 2>/dev/null)|$(cat "$(_run_dir on/confidence-0.9 opus 1)/demoted.txt" 2>/dev/null)" "demoted findings at 0.6 and 0.9"
  _rp aggregate --replay "$RP_R" --findings-dir "$RP_F" --evals "$RP_EVALS" --model jev-1.13.0
  e2e_expect_line "CHECK_THRESHOLDS=ok"
  # p = 0.19: unsupported, confidence 0.62. H is demoted at 0.6 and kept at
  # 0.9; the 0.9 point given the 0.6 point's output must be flagged.
  _rp_setup threshold-direction-unsupported "an unsupported answer between the two points, with the 0.9 output replaced by the 0.6 one, is flagged (R29)"
  e2e_stub_start a "$(_both 0.97 0.19)"
  _rp_findings opus 1 "$H"
  _shadow
  _rp table --replay "$RP_R" --model jev-1.13.0
  for t in 0.6 0.9; do _on dedup --same-defect "$t"; _on confidence --claim-supported "$t"; done
  e2e_expect_equal 'H|' "$(cat "$(_run_dir on/confidence-0.6 opus 1)/demoted.txt" 2>/dev/null)|$(cat "$(_run_dir on/confidence-0.9 opus 1)/demoted.txt" 2>/dev/null)" "demoted findings at 0.6 and 0.9"
  _rp aggregate --replay "$RP_R" --findings-dir "$RP_F" --evals "$RP_EVALS" --model jev-1.13.0
  e2e_expect_line "CHECK_THRESHOLDS=ok"
  cp "$(_run_dir on/confidence-0.6 opus 1)/demoted.txt" "$(_run_dir on/confidence-0.9 opus 1)/demoted.txt"
  _rp aggregate --replay "$RP_R" --findings-dir "$RP_F" --evals "$RP_EVALS" --model jev-1.13.0
  e2e_expect_line "CHECK_THRESHOLDS=flagged"
fi

if _want ceiling-bound; then
  _flow_test_begin "ceiling-bound"
  _rp_setup ceiling-bound "the ceiling is a bound on what review.dedup can reach: merging two findings outside every hunk, from different reviewers, is not flagged as above it (R17)"
  e2e_stub_start a "$(_both 0.97 0.97)"
  X1=$(_sf X1 P2 correctness 120 HIGH flow:code-reviewer "the helper drops the bound")
  X2=$(_sf X2 P2 error-handling 121 HIGH flow:error-handler-inspector "the helper drops the bound")
  for n in 1 2; do _rp_findings opus "$n" "$H" "$X1" "$X2"; done
  _shadow
  _rp table --replay "$RP_R" --model jev-1.13.0
  _on off
  for t in 0.8 0.9; do _on dedup --same-defect "$t"; done
  for c in 0.6 0.9; do _on confidence --claim-supported "$c"; done
  # H and X1 have the same reviewer list; X1+X2 (distance 1) and H+X2 are asked, and
  # complete linkage keeps H apart, as H+X1 was never asked.
  e2e_expect_equal "MERGED=X1+X2" "$(grep '^MERGED=' "$(_run_dir on/dedup-0.9 opus 2)/dedup.out")" "MERGED line"
  _rp inspect --replay "$RP_R" --evals "$RP_EVALS"
  jq '[.[] | .label = "same" | .reason = "both say the helper drops the bound"]' "$RP_R/merged-pairs.json" > "$E2E_DIR/m.json" && mv "$E2E_DIR/m.json" "$RP_R/merged-pairs.json"
  _rp_runs_json
  _agg --choose 1 --judge 2
  e2e_expect_line "AGGREGATE_STATE=ok"
  # Plain: 1 hit and 2 false findings, F1 0.5. Dedup: 1 hit and 1 false, F1
  # 0.667. The ceiling collapses the three accepted findings of the file to H:
  # 1 hit and none false, F1 1.
  e2e_expect_equal '[0.5,0.667,1]' "$(jq -c '.models.opus | [.plain.judged.f1, .filters["dedup-0.9"].judged_raw.f1, .ceiling.judged.f1] | map(. * 1000 | round / 1000)' "$RP_R/report.json")" "plain, dedup and ceiling F1"
  e2e_expect_line "CHECK_CEILING=ok"
fi

if _want demoted-hits; then
  _flow_test_begin "demoted-hits"
  _rp_setup demoted-hits "the demoted hits count only the finding the scorer takes as the run's hit, not a demoted repeat on the same hunk (R18)"
  # Per run: the pair H+R (answered different), then confidence for H, R, O.
  # Run 1 demotes R, the repeat on the hit hunk; run 2 demotes H, the hit.
  e2e_stub_start a "{\"replies\":[$(_reply 0.03 0.97),$(_reply 0.97 0.97),$(_reply 0.97 0.03),$(_reply 0.97 0.97),$(_reply 0.03 0.97),$(_reply 0.97 0.03),$(_reply 0.97 0.97),$(_reply 0.97 0.97)]}"
  # Run 2 words H and R differently, so its states are its own.
  _rp_findings opus 1 "$H" "$R" "$O"
  _rp_findings opus 2 "$(_sf H P1 correctness 47 HIGH flow:code-reviewer "a point interval is kept half-open")" \
    "$(_sf R P2 error-handling 47 HIGH flow:error-handler-inspector "points skip the empty interval check")" "$O"
  _shadow
  e2e_expect_line "PASS_STATE=ok"
  _rp table --replay "$RP_R" --model jev-1.13.0
  _on confidence --claim-supported 0.9
  e2e_expect_equal 'R|H' "$(cat "$(_run_dir on/confidence-0.9 opus 1)/demoted.txt")|$(cat "$(_run_dir on/confidence-0.9 opus 2)/demoted.txt")" "demoted findings of runs 1 and 2"
  _rp aggregate --replay "$RP_R" --findings-dir "$RP_F" --evals "$RP_EVALS" --model jev-1.13.0 --choose 1 --judge 2
  e2e_expect_line "AGGREGATE_STATE=ok"
  e2e_expect_equal '[2,1]' "$(jq -c '.models.opus.filters["confidence-0.9"] | [.demoted, .demoted_hits]' "$RP_R/report.json")" "demoted findings and demoted hits"
fi

if _want rescore-converted; then
  _flow_test_begin "rescore-converted"
  _rp_setup rescore-converted "the rescore check also scores the findings as converted against the recorded score, so a converter change to a score is flagged (R23)"
  _rp_findings opus 1 "$H" "$O"
  _rp_runs_json
  _agg
  e2e_expect_line "CHECK_RESCORE=ok"
  # A file that already ends in :47, with no line: the session's finding is
  # outside every hunk, and its converted location intervals.py:47 is inside.
  _rp_findings opus 1 '{"id":"H","priority":"P1","category":"correctness","file":"intervals.py:47","problem":"p","confidence":"HIGH","reviewers":["flow:code-reviewer"]}' "$O"
  _rp_runs_json
  e2e_expect_equal 'false' "$(jq -c '.[0].review.hit' "$E2E_DIR/runs.json")" "recorded hit of the session's findings"
  _agg
  e2e_expect_line "CHECK_RESCORE=flagged"
  e2e_expect_equal '[0,1,["opus/review-b/interval-algebra/halfopen_point_kept/1"]]' \
    "$(jq -c '.checks.rescore | [.mismatch, .converted_mismatch, .converted_runs]' "$RP_R/report.json")" "raw and converted mismatches"
fi

if _want table-per-run; then
  _flow_test_begin "table-per-run"
  _rp_setup table-per-run "two runs sent the same pair state and were given answers on either side of the threshold: each run is replayed its own answer; one run given two answers for one state fails the table (R24)"
  # Per run: the pair H+R, then confidence for H and R. Run 1 is told same,
  # run 2 different.
  e2e_stub_start a "{\"replies\":[$(_reply 0.97 0.97),$(_reply 0.97 0.97),$(_reply 0.97 0.97),$(_reply 0.03 0.97),$(_reply 0.97 0.97),$(_reply 0.97 0.97)]}"
  _rp_findings opus 1 "$H" "$R"
  _rp_findings opus 2 "$H" "$R"
  _shadow
  e2e_expect_line "PASS_STATE=ok"
  _rp table --replay "$RP_R" --model jev-1.13.0
  e2e_expect_line "TABLE_ENTRIES=3"
  e2e_expect_line "TABLE_CONFLICTS=1"
  e2e_expect_line "TABLE_STATE=ok"
  _on dedup --same-defect 0.8
  e2e_expect_line "PASS_STATE=ok"
  e2e_expect_line "SERVER_MISSES=0"
  e2e_expect_equal 'MERGED=H+R|' "$(grep '^MERGED=' "$(_run_dir on/dedup-0.8 opus 1)/dedup.out")|$(grep '^MERGED=' "$(_run_dir on/dedup-0.8 opus 2)/dedup.out")" "MERGED lines of runs 1 and 2"
  # Run 1's records again under a second run directory, with another answer
  # to the pair: one run, one state, two answers.
  RD=$(_run_dir shadow/base opus 1)
  cp -R "$RD/run" "$RD/run-9"
  jq -c 'if .site == "review.dedup" then .answer.p = 0.5 else . end' "$RD/run/system-one.jsonl" > "$RD/run-9/system-one.jsonl"
  _rp table --replay "$RP_R" --model jev-1.13.0
  e2e_expect_line "TABLE_SAME_RUN_CONFLICTS=1"
  e2e_expect_line "TABLE_STATE=failed"
  e2e_expect_equal 1 "$E2E_RC" "exit status of a failed table"
fi

if _want table-same-run-twice; then
  _flow_test_begin "table-same-run-twice"
  _rp_setup table-same-run-twice "one run sent the same confidence state for two findings and was given two answers: the table fails (R25)"
  # Two findings that differ only in their id: the confidence state has no
  # id, so both send the same state. One reviewer, so no pair is asked.
  T1='{"id":"T1","priority":"P2","category":"correctness","file":"intervals.py","line":47,"problem":"the point is kept","suggested_fix":"drop it","confidence":"HIGH","reviewers":["flow:code-reviewer"]}'
  _rp_findings opus 1 "$T1" "$(jq -c '.id = "T2"' <<<"$T1")"
  e2e_stub_start a "{\"replies\":[$(_reply 0.97 0.9),$(_reply 0.97 0.1)]}"
  _shadow
  e2e_expect_line "PASS_STATE=ok"
  e2e_expect_line "CONFIDENCE_ASKED_TOTAL=2"
  RD=$(_run_dir shadow/base opus 1)
  e2e_expect_equal same "$(cmp -s "$RD/run/system-one-state/confidence-T1.json" "$RD/run/system-one-state/confidence-T2.json" && echo same || echo different)" "the two kept states"
  _rp table --replay "$RP_R" --model jev-1.13.0
  e2e_expect_line "TABLE_ENTRIES=1"
  e2e_expect_line "TABLE_SAME_RUN_CONFLICTS=1"
  e2e_expect_line "TABLE_STATE=failed"
  e2e_expect_equal 1 "$E2E_RC" "exit status of a failed table"
fi

if _want table-unanswered; then
  _flow_test_begin "table-unanswered"
  _rp_setup table-unanswered "states the provider gave no answer for (HTTP 429) fail the table and hold both verdicts, though every answer that came is far from 0.5 (R26)"
  # Per run: the pair H+R, then confidence for H, R and O. The pair and H
  # are answered, R and O get HTTP 429.
  e2e_stub_start a "{\"replies\":[$(_reply 0.97 0.97),$(_reply 0.97 0.97),{\"status\":429,\"body\":{\"detail\":\"rate limited\"}}]}"
  _rp_findings opus 1 "$H" "$R" "$O"
  _shadow
  e2e_expect_line "PASS_STATE=ok"
  _rp table --replay "$RP_R" --model jev-1.13.0
  e2e_expect_line "TABLE_UNANSWERED=2"
  e2e_expect_line "UNANSWERED_SITE=review.confidence 2 of 3"
  e2e_expect_line "UNANSWERED_SITE=review.dedup 0 of 1"
  e2e_expect_line "TABLE_STATE=failed"
  e2e_expect_equal 1 "$E2E_RC" "exit status of a failed table"
  _rp aggregate --replay "$RP_R" --findings-dir "$RP_F" --evals "$RP_EVALS" --model jev-1.13.0 --choose 1 --judge 2
  e2e_expect_line "CHECK_ANSWERS=flagged"
  e2e_expect_line "VERDICT_REVIEW_DEDUP=held-by-checks"
  e2e_expect_line "VERDICT_REVIEW_CONFIDENCE=held-by-checks"
  e2e_expect_equal '[2,2,3]' \
    "$(jq -c '.checks.answers | [.unanswered, .unanswered_by_site["review.confidence"].unanswered, .unanswered_by_site["review.confidence"].sent]' "$RP_R/report.json")" "unanswered answers in report.json"
fi

if _want shadow-allow-unasked; then
  _flow_test_begin "shadow-allow-unasked"
  _rp_setup shadow-allow-unasked "--allow-unasked waives findings over the cap, which every on pass leaves unasked, but not findings a provider that stopped answering left unasked (R28)"
  # 26 findings from one reviewer: no pair, and the confidence cap (25)
  # leaves the last one unasked.
  CAP_SET=()
  for i in $(seq 1 26); do CAP_SET+=("$(_sf "C$i" P2 correctness "$((100 + i))" HIGH flow:code-reviewer "problem $i")"); done
  _rp_findings opus 1 "${CAP_SET[@]}"
  # A stub per pass: each stops after its 60 s lifetime, and a pass of 25
  # requests can take a good part of that.
  e2e_stub_start a "$(_both 0.97 0.97)"
  _shadow
  e2e_expect_line "PASS_STATE=failed"
  e2e_expect_out "FAIL=unasked"
  e2e_expect_equal '["confidence:cap"]' "$(jq -c '.runs[].unasked' "$RP_R/shadow/base/pass.json")" "the unasked item recorded without --allow-unasked"
  e2e_stub_start b "$(_both 0.97 0.97)"
  _rp shadow --findings-dir "$RP_F" --work "$RP_W" --replay "$RP_R" --provider custom \
    --base-url "$(e2e_stub_url b)" --model jev-1.13.0 --allow-unasked
  e2e_expect_line "PASS_STATE=ok"
  e2e_expect_line "RUNS_UNASKED=1"
  e2e_expect_equal '["confidence:cap"]' "$(jq -c '.runs[].unasked' "$RP_R/shadow/base/pass.json")" "the unasked item recorded"
  # Three findings and a provider slower than the timeout: two timeouts in a
  # row stop the confidence script, and the third finding goes unasked.
  _rp_findings opus 1 "$H" "$(_sf R P2 correctness 120 HIGH flow:code-reviewer)" "$O"
  e2e_stub_start c '{"delay_ms":1500,"body":{}}'
  _rp shadow --findings-dir "$RP_F" --work "$RP_W" --replay "$RP_R" --provider custom \
    --base-url "$(e2e_stub_url c)" --model jev-1.13.0 --timeout-ms 500 --allow-unasked
  e2e_expect_equal '["confidence:provider-down"]' "$(jq -c '.runs[].unasked' "$RP_R/shadow/base/pass.json")" "the unasked item recorded"
  e2e_expect_line "PASS_STATE=failed"
  e2e_expect_out "FAIL=unasked"
fi

if _want shadow-dedup-cap; then
  _flow_test_begin "shadow-dedup-cap"
  _rp_setup shadow-dedup-cap "--allow-unasked waives the dedup cap (STOPPED=max-pairs) as it waives the confidence cap, and an on pass that meets the same cap passes (R30)"
  # Five code-reviewer and five error-handler-inspector findings in one
  # file: 25 candidate pairs, one over the cap of 24. They are P3, which
  # review.dedup pairs and review.confidence does not ask about, so the
  # passes make no confidence call.
  CAP_SET=()
  for i in 1 2 3 4 5; do
    CAP_SET+=("$(_sf "A$i" P3 correctness "$((100 + i))" HIGH flow:code-reviewer "problem a$i")")
    CAP_SET+=("$(_sf "B$i" P3 error-handling "$((110 + i))" HIGH flow:error-handler-inspector "problem b$i")")
  done
  _rp_findings opus 1 "${CAP_SET[@]}"
  e2e_stub_start a "$(_both 0.03 0.97)"
  _shadow
  e2e_expect_line "PAIRS_CANDIDATE_TOTAL=25"
  e2e_expect_line "PAIRS_ASKED_TOTAL=24"
  e2e_expect_line "CONFIDENCE_ASKED_TOTAL=0"
  e2e_expect_line "PASS_STATE=failed"
  e2e_expect_out "FAIL=unasked"
  _rp shadow --findings-dir "$RP_F" --work "$RP_W" --replay "$RP_R" --provider custom \
    --base-url "$(e2e_stub_url a)" --model jev-1.13.0 --allow-unasked
  e2e_expect_line "PASS_STATE=ok"
  e2e_expect_line "RUNS_UNASKED=1"
  e2e_expect_equal '["dedup:UNASKED=1 STOPPED=max-pairs"]' "$(jq -c '.runs[].unasked' "$RP_R/shadow/base/pass.json")" "the unasked item recorded"
  _rp table --replay "$RP_R" --model jev-1.13.0
  _on dedup --same-defect 0.8
  e2e_expect_line "PASS_STATE=ok"
  e2e_expect_line "SERVER_REQUESTS=24"
  e2e_expect_line "SERVER_MISSES=0"
fi

if _want reps-same-line; then
  _flow_test_begin "reps-same-line"
  _rp_setup reps-same-line "two reviewers' findings at one line merge into a finding whose confidence state the base pass already asked: the representatives' pass does not ask it again, so a second answer cannot fail the table (R31); a failed or missing representatives' pass holds the confidence verdict (R37)"
  # Base pass: the pair H+R, then H, R and O. Any later request is told H's
  # claim is not supported, so asking H's state again gives the run a second
  # answer for it.
  e2e_stub_start a "{\"replies\":[$(_reply 0.97 0.97),$(_reply 0.97 0.97),$(_reply 0.97 0.97),$(_reply 0.97 0.97),$(_reply 0.97 0.1)]}"
  _rp_findings opus 1 "$H" "$R" "$O"
  _shadow
  _rp table --replay "$RP_R" --model jev-1.13.0
  _on dedup --same-defect 0.8
  e2e_expect_equal "MERGED=H+R" "$(grep '^MERGED=' "$(_run_dir on/dedup-0.8 opus 1)/dedup.out")" "MERGED line"
  _rp shadow --findings-dir "$RP_F" --work "$RP_W" --replay "$RP_R" --provider custom \
    --base-url "$(e2e_stub_url a)" --model jev-1.13.0 --set reps
  e2e_expect_line "PASS_STATE=ok"
  e2e_expect_line "CONFIDENCE_ASKED_TOTAL=0"
  e2e_expect_equal 4 "$(e2e_stub_requests a)" "requests received by the stub provider"
  _rp table --replay "$RP_R" --model jev-1.13.0
  e2e_expect_line "TABLE_SAME_RUN_CONFLICTS=0"
  e2e_expect_line "TABLE_STATE=ok"
  _on dedup-confidence --same-defect 0.8 --claim-supported 0.9
  e2e_expect_line "PASS_STATE=ok"
  e2e_expect_line "SERVER_MISSES=0"
  _rp inspect --replay "$RP_R" --evals "$RP_EVALS"
  jq '[.[] | .label = "same" | .reason = "both describe the kept point"]' "$RP_R/merged-pairs.json" > "$E2E_DIR/m.json" && mv "$E2E_DIR/m.json" "$RP_R/merged-pairs.json"
  _rp aggregate --replay "$RP_R" --findings-dir "$RP_F" --evals "$RP_EVALS" --model jev-1.13.0 --choose 1 --judge 2
  e2e_expect_line "CHECK_REPS_PASS=ok"
  e2e_expect_line "CHECK_PARTITION=ok"
  # The representatives' pass failed: the partition check names it.
  cp "$RP_R/shadow/reps/pass.json" "$E2E_DIR/reps-aside.json"
  jq '.state = "failed" | .fails = ["model-not-pinned"]' "$E2E_DIR/reps-aside.json" > "$RP_R/shadow/reps/pass.json"
  _rp aggregate --replay "$RP_R" --findings-dir "$RP_F" --evals "$RP_EVALS" --model jev-1.13.0 --choose 1 --judge 2
  e2e_expect_line "CHECK_PARTITION=flagged"
  e2e_expect_equal '["shadow-reps"]' "$(jq -c '.checks.partition.failed_passes' "$RP_R/report.json")" "the failed passes"
  # The representatives' pass never ran: the confidence verdict is held.
  rm "$RP_R/shadow/reps/pass.json"
  _rp aggregate --replay "$RP_R" --findings-dir "$RP_F" --evals "$RP_EVALS" --model jev-1.13.0 --choose 1 --judge 2
  e2e_expect_line "CHECK_REPS_PASS=not-run"
  e2e_expect_equal '["reps-pass"]' "$(jq -c '.sites["review.confidence"].held_by - ["off-identity","rescore","thresholds","pairs-candidate"]' "$RP_R/report.json")" "the checks holding review.confidence, besides those this fixture does not run"
fi

if _want shadow-client-error; then
  _flow_test_begin "shadow-client-error"
  _rp_setup shadow-client-error "pairs and findings the client failed on keep no state: the shadow pass fails with them unasked instead of reading as complete (R32)"
  _rp_findings opus 1 "$H" "$R" "$O"
  _rp trees --findings-dir "$RP_F" --work "$RP_W" --replay "$RP_R"
  # A client that exits 1 with no reason: each call is a client-error, and
  # two in a row stop the confidence script (client-broken).
  e2e_plugin_copy bin/flow-s1.sh '#!/bin/sh
exit 1'
  e2e_stub_start a "$(_both 0.97 0.97)"
  _rp shadow --findings-dir "$RP_F" --work "$RP_W" --replay "$RP_R" --provider custom \
    --base-url "$(e2e_stub_url a)" --model jev-1.13.0 --allow-unasked
  e2e_expect_line "PASS_STATE=failed"
  e2e_expect_out "FAIL=unasked"
  e2e_expect_equal '["dedup:NO_ANSWER_CLIENT_ERROR=1","confidence:client-error","confidence:client-error","confidence:client-broken"]' \
    "$(jq -c '.runs[].unasked' "$RP_R/shadow/base/pass.json")" "the unasked items recorded"
  e2e_expect_equal 0 "$(e2e_stub_requests a)" "requests received by the stub provider"
fi

if _want on-no-answer; then
  _flow_test_begin "on-no-answer"
  _rp_setup on-no-answer "an on pass in which the client gave no answer fails, though the replay server missed nothing (R33)"
  e2e_stub_start a "$(_both 0.97 0.97)"
  _rp_findings opus 1 "$H" "$R" "$O"
  _shadow
  e2e_expect_line "PASS_STATE=ok"
  _rp table --replay "$RP_R" --model jev-1.13.0
  e2e_plugin_copy bin/flow-s1.sh '#!/bin/sh
exit 1'
  _on dedup --same-defect 0.8
  e2e_expect_line "PASS_STATE=failed"
  e2e_expect_out "FAIL=no-answer"
  e2e_expect_out "FAIL=request-count"
  e2e_expect_line "SERVER_MISSES=0"
  e2e_expect_line "SERVER_REQUESTS=0"
  e2e_expect_equal "NO_ANSWER_CLIENT_ERROR=1" "$(grep '^NO_ANSWER_' "$(_run_dir on/dedup-0.8 opus 1)/dedup.out")" "the dedup script's no-answer count"
  _on confidence --claim-supported 0.9
  e2e_expect_line "PASS_STATE=failed"
  e2e_expect_out "FAIL=no-answer"
  e2e_expect_out "FAIL=unasked"
fi

if _want on-interrupted; then
  _flow_test_begin "on-interrupted"
  _rp_setup on-interrupted "a pass stopped part way, here by a findings file that is not a list, leaves no earlier 'ok' beside the run directories it rewrote, and the report flags it (R34)"
  e2e_stub_start a "$(_both 0.97 0.97)"
  _rp_findings opus 1 "$H" "$O"
  _rp_findings opus 2 "$H" "$O"
  _shadow
  _rp table --replay "$RP_R" --model jev-1.13.0
  _on confidence --claim-supported 0.9
  e2e_expect_line "PASS_STATE=ok"
  _rp_runs_json
  printf '{}\n' > "$RP_F/opus/review-b/$RP_CASE/$RP_TRAP/2.json"
  _on confidence --claim-supported 0.9
  e2e_expect_line "STATE=failed"
  e2e_expect_out "2.json is not a JSON list of findings"
  e2e_expect_no_out "PASS_STATE=ok"
  e2e_expect_equal 'running' "$(jq -r .state "$RP_R/on/confidence-0.9/pass.json")" "the state of the stopped pass"
  # The shadow pass stopped the same way.
  _rp shadow --findings-dir "$RP_F" --work "$RP_W" --replay "$RP_R" --provider custom \
    --base-url "$(e2e_stub_url a)" --model jev-1.13.0
  e2e_expect_line "STATE=failed"
  e2e_expect_equal 'running' "$(jq -r .state "$RP_R/shadow/base/pass.json")" "the state of the stopped shadow pass"
  # The findings file restored, so aggregate reads every run: the stopped
  # pass still holds the verdict.
  cp "$RP_F/opus/review-b/$RP_CASE/$RP_TRAP/1.json" "$RP_F/opus/review-b/$RP_CASE/$RP_TRAP/2.json"
  _agg --choose 1 --judge 2
  e2e_expect_line "CHECK_PARTITION=flagged"
  e2e_expect_equal '["confidence-0.9","shadow"]' "$(jq -c '.checks.partition.failed_passes' "$RP_R/report.json")" "the failed passes"
fi

if _want on-questions-layout; then
  _flow_test_begin "on-questions-layout"
  _rp_setup on-questions-layout "a questions.yaml whose layout the threshold edit does not know stops the pass with STATE=failed and the reason, not a traceback (R36)"
  _rp_findings opus 1 "$H"
  _rp trees --findings-dir "$RP_F" --work "$RP_W" --replay "$RP_R"
  # A comment after the site key: valid YAML, another line.
  e2e_plugin_copy system-one/questions.yaml "$(sed 's/^  review\.dedup:$/  review.dedup:  # merge duplicate findings/' "$E2E_PLUGIN_DIR/system-one/questions.yaml")"
  _on dedup --same-defect 0.8
  e2e_expect_line "STATE=failed"
  e2e_expect_out "its layout changed"
  e2e_expect_equal 1 "$E2E_RC" "exit status"
  e2e_expect_err_lacks "Traceback"
fi

# _body <same_defect p> <claim_supported p> — the provider's reply body.
_body() {
  printf '{"model":"jev-1.13.0","answers":{"same_defect":{"type":"noul","noul":%s},"claim_supported":{"type":"noul","noul":%s}}}' "$1" "$2"
}

if _want verdict-spread; then
  _flow_test_begin "verdict-spread"
  _rp_setup verdict-spread "a dedup gain that does not exceed the spread of the judged replications keeps the site off (R38)"
  # The pair is answered same, except in replication 3, whose R carries the
  # tag [r3] in its problem: there it is answered different, so the dedup
  # filter's F1 differs between the judged replications.
  e2e_stub_start a "{\"body\":$(_body 0.97 0.97),\"by_state\":[{\"match\":\"[r3]\",\"body\":$(_body 0.03 0.97)}]}"
  for m in opus sonnet; do
    for n in 1 2; do _rp_findings "$m" "$n" "$H" "$R" "$O"; done
    _rp_findings "$m" 3 "$H" "$(_sf R P2 error-handling 47 HIGH flow:error-handler-inspector "the empty interval check is skipped for points [r3]")" "$O"
  done
  _shadow
  _rp table --replay "$RP_R" --model jev-1.13.0
  _on dedup --same-defect 0.8
  _on dedup --same-defect 0.9
  _rp inspect --replay "$RP_R" --evals "$RP_EVALS"
  jq '[.[] | .label = "same" | .reason = "both describe the kept point"]' "$RP_R/merged-pairs.json" > "$E2E_DIR/m.json" && mv "$E2E_DIR/m.json" "$RP_R/merged-pairs.json"
  _rp_runs_json
  _agg
  e2e_expect_line "AGGREGATE_STATE=ok"
  # Hand computation per model. Plain, every replication: 1 hit and 2 false
  # findings, F1 0.5, so the plain spread is 0. Dedup, replication 2: R
  # merged into H, 1 hit and 1 false, F1 2/3; replication 3: nothing merged,
  # F1 0.5. Spread: (0 + (2/3 - 0.5)) / 2 = 1/12 = 0.083. Judged F1 with
  # dedup: 2 hits and 3 false findings, precision 0.4, F1 0.8/1.4 = 0.571, a
  # gain of 0.071 over 0.5, which is not more than 0.083.
  e2e_expect_equal '[0.5,0.571,0.083]' \
    "$(jq -c '.models.opus | [.plain.judged.f1, .filters["dedup-0.9"].judged.f1, .filters["dedup-0.9"].spread] | map(. * 1000 | round / 1000)' "$RP_R/report.json")" \
    "plain F1, dedup F1 and spread"
  e2e_expect_line "CHOSEN_REVIEW_DEDUP=0.9"
  e2e_expect_line "RULE_REVIEW_DEDUP=keep-off"
  e2e_expect_equal 2 "$(jq '[.sites["review.dedup"].reading[] | select(test("does not clear it"))] | length' "$RP_R/report.json")" "readings that say the gain does not clear the spread"
fi

if _want verdict-recall-guard; then
  _flow_test_begin "verdict-recall-guard"
  _rp_setup verdict-recall-guard "a confidence point that loses more than one run's worth of recall is not chosen on replication 1, and a chosen point that loses it on the judged replications is not adopted, though its F1 gain clears the spread (R38)"
  # Three traps, one changed line each: halfopen_point_kept (47),
  # point_dropped (44) and difference_keeps_closedness (145). Each run has
  # its hit H and three findings outside every hunk (lines 100-102). A tag in
  # each problem sets the answer: [keep] supported (p 0.97), [drop] not
  # supported at confidence 0.98 (p 0.01, demoted at 0.6 and 0.9), [drop6]
  # not supported at confidence 0.8 (p 0.1, demoted at 0.6 only). The shadow
  # pass asks the stub; the two on passes are written from the same tags.
  e2e_stub_start a "{\"body\":$(_body 0.97 0.97),\"by_state\":[{\"match\":\"[drop6]\",\"body\":$(_body 0.97 0.1)},{\"match\":\"[drop]\",\"body\":$(_body 0.97 0.01)}]}"
  for m in opus sonnet; do
    for n in 1 2 3; do
      if [ "$n" = 1 ]; then OUTTAG='[drop6]'; MISSTAG='[drop6]'; else OUTTAG='[drop]'; MISSTAG='[drop]'; fi
      for tl in halfopen_point_kept:47 point_dropped:44 difference_keeps_closedness:145; do
        tr=${tl%%:*}; ln=${tl#*:}
        if [ "$tr" = halfopen_point_kept ]; then HTAG='[keep]'; else HTAG=$MISSTAG; fi
        RP_FTRAP=$tr _rp_findings "$m" "$n" "$(_sf H P1 correctness "$ln" HIGH flow:code-reviewer "the changed line is wrong $HTAG")" \
          "$(_sf X1 P2 correctness 100 HIGH flow:code-reviewer "x1 is odd $OUTTAG")" \
          "$(_sf X2 P2 correctness 101 HIGH flow:code-reviewer "x2 is odd $OUTTAG")" \
          "$(_sf X3 P2 correctness 102 HIGH flow:code-reviewer "x3 is odd $OUTTAG")"
      done
    done
  done
  _shadow
  e2e_expect_line "PASS_STATE=ok"
  _rp table --replay "$RP_R" --model jev-1.13.0
  _on_written confidence 0.6 '[drop]' '[drop6]'
  _on_written confidence 0.9 '[drop]'
  _rp_runs_json
  _agg
  e2e_expect_line "AGGREGATE_STATE=ok"
  # Hand computation per model and replication, three runs each. Plain: 3
  # hits and 9 false findings, precision 0.25, F1 0.4.
  # Replication 1 at 0.6: every outside finding and the hits of
  # point_dropped and difference_keeps_closedness are demoted: 1 hit, no
  # false finding, F1 0.5, a gain of 0.1, but recall 1/3 falls by two runs'
  # worth (one run is 1/3). At 0.9 nothing is demoted: a gain of 0. So 0.9
  # is chosen.
  e2e_expect_line "CHOSEN_REVIEW_CONFIDENCE=0.9"
  e2e_expect_equal 1 "$(jq '[.sites["review.confidence"].reading[] | select(test("^confidence-0.6 loses more than one run.s worth of recall"))] | length' "$RP_R/report.json")" "the reading for the 0.6 point"
  # Replications 2 and 3 at 0.9: the same demotions in each, so the spread
  # is 0. F1 0.5 against 0.4 clears it, but recall is 2 of 6 against 6 of 6,
  # more than one run's worth (1/6) lower.
  e2e_expect_equal '[0.4,0.5,0,0.333]' \
    "$(jq -c '.models.opus | [.plain.judged.f1, .filters["confidence-0.9"].judged.f1, .filters["confidence-0.9"].spread, .filters["confidence-0.9"].judged.recall] | map(. * 1000 | round / 1000)' "$RP_R/report.json")" \
    "plain F1, confidence F1, spread and confidence recall"
  e2e_expect_line "RULE_REVIEW_CONFIDENCE=keep-off"
  e2e_expect_equal 2 "$(jq '[.sites["review.confidence"].reading[] | select(test("clears it; recall 0.333 against 1.000, more than one run lower"))] | length' "$RP_R/report.json")" "readings that say the gain clears the spread and recall falls too far"
fi

if _want aggregate-low-plain; then
  _flow_test_begin "aggregate-low-plain"
  _rp_setup aggregate-low-plain "the report's plain score leaves a session-reported LOW P2 out, and its LOW-kept score counts it (R39)"
  for n in 1 2; do
    _rp_findings opus "$n" "$H" "$O" "$(_sf L P2 correctness 130 LOW flow:code-reviewer "the bound is suspicious")"
  done
  _rp_runs_json
  _agg --choose 1 --judge 2
  e2e_expect_line "AGGREGATE_STATE=ok"
  # By the scoring rules, replication 2: H is the hit and O is false; L is
  # LOW, so it is left out: 2 scored, 1 false, precision 0.5, recall 1, F1
  # 0.667. Kept: 3 scored, 2 false, precision 1/3, F1 0.5.
  e2e_expect_equal '[[2,1,0.667],[3,2,0.5]]' \
    "$(jq -c '.models.opus.plain | [.judged, .judged_low_kept] | map([.scored_findings, .false_findings, (.f1 * 1000 | round / 1000)])' "$RP_R/report.json")" \
    "plain and LOW-kept judged scores"
fi

if _want location-parsers-agree; then
  _flow_test_begin "location-parsers-agree"
  _rp_setup location-parsers-agree "the scorer reads a location's file and line as review.dedup does (R41)"
  printf 'code: bin/_flow_eval.py location_site, bin/_flow_s1_dedup.py parse_location\n' | _e2e_art
  DIFF=$(cd "$E2E_REPO" && PYTHONDONTWRITEBYTECODE=1 python3 - "$REPO_ROOT/plugins/flow/bin" <<'PPY' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
import _flow_eval as fe
import _flow_s1_dedup as dd
for loc in ["intervals.py:47", "intervals.py:46-48", "intervals.py", "src/a b.py:3", "a.py:47:5",
            "a.py:x", "a.py:", ":12", "dir/a.py:0", "a.py:12-", "C:/x/a.py:9"]:
    fpath, fline = fe.location_site(loc)
    dpath, dline = dd.parse_location(loc)
    if (fpath, fline if fline is not None else 0) != (dpath, dline):
        print("%r: scorer %r, review.dedup %r" % (loc, (fpath, fline), (dpath, dline)))
PPY
)
  printf 'differences: %s\n' "${DIFF:-none}" | _e2e_art
  e2e_expect_equal "" "$DIFF" "locations the two read differently"
fi

# ----------------------------------------------------------------- recovered export

# _rec_session <transcripts dir> <session id> <findings json> — one recovered
# session: its final answer holds the findings block.
_rec_session() {
  mkdir -p "$1/-private-var-x/$2/subagents"
  jq -nc --arg t "Consolidated.
\`\`\`json
$3
\`\`\`" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' > "$1/-private-var-x/$2.jsonl"
}
# _rec_agent <transcripts dir> <session id> <name> <agentType> <report text> — one subagent.
_rec_agent() {
  local d="$1/-private-var-x/$2/subagents"
  jq -nc --arg t "$5" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' > "$d/agent-$3.jsonl"
  printf '{"agentType":"%s"}' "$4" > "$d/agent-$3.meta.json"
}
# _rec_find <id> <priority> <category> <line> — one recovered finding (no reviewers).
_rec_find() {
  printf '{"id":"%s","priority":"%s","category":"%s","file":"intervals.py","line":%s,"problem":"p of %s","confidence":"HIGH"}' "$1" "$2" "$3" "$4" "$1"
}
if _want export-recovered; then
  _flow_test_begin "export-recovered"
  _rp_setup export-recovered "the recovered 2026-09-25 runs are exported with each finding credited to every subagent that cites its exact line, ranges and prose not counted, and re-score to the recorded run (R12)"
  T="$E2E_DIR/transcripts"
  _rec_session "$T" sid-1 "[$(_rec_find F1 P1 correctness 47),$(_rec_find F2 P2 missing-validation 120),$(_rec_find F3 P2 tests 160)]"
  # Line 47: code-reviewer with a column after the line, error-handler-inspector
  # with a directory before the file. Both are credited, not only one.
  _rec_agent "$T" sid-1 a flow:code-reviewer "intervals.py:47:5 keeps a half-open point."
  _rec_agent "$T" sid-1 b flow:error-handler-inspector "src/intervals.py:47 skips the check; intervals.py:120 swallows the error."
  # Line 160 is only covered: by a range, by prose, by a longer line number,
  # by another module and by a longer file name. None of these cites it.
  _rec_agent "$T" sid-1 c flow:convention-checker "intervals.py:159-161 and intervals.py:158 – 162 are odd; at line 160 the name is wrong; see intervals.py:1600."
  _rec_agent "$T" sid-1 d flow:test-runner "reference_impl.py:160 differs; myintervals.py:160 too."
  _rec_agent "$T" sid-1 e flow:finding-critic "intervals.py:160 is real."
  jq -nc --arg c "$RP_CASE" --arg t "$RP_TRAP" '[{model:"claude-opus-5-5",arm:"review-b",case:$c,trap:$t,run:1,session_id:"sid-1",
    review:{hit:true,false_findings:2,scored_findings:3,findings_total:3,incomplete:false}},
    {model:"claude-opus-5-5",arm:"review-b-critic",case:$c,trap:$t,run:1,session_id:"sid-2",review:{}}]' > "$E2E_DIR/runs.json"
  _rp export-recovered --runs-json "$E2E_DIR/runs.json" --transcripts "$T" --out "$RP_F"
  e2e_expect_line "EXPORTED=1"
  e2e_expect_line "FINDINGS=3"
  e2e_expect_line "ATTRIBUTED=2"
  e2e_expect_line "UNATTRIBUTED=1"
  e2e_expect_line "RESCORE_MISMATCH=0"
  e2e_expect_line "REVIEWERS_PER_FINDING=0:1,1:1,2:1"
  e2e_expect_line "REVIEWERS_PER_P1_P2_FINDING=0:1,1:1,2:1"
  OUTF="$RP_F/claude-opus-5-5/review-b/$RP_CASE/$RP_TRAP/1.json"
  e2e_expect_equal '[["flow:code-reviewer","flow:error-handler-inspector"],["flow:error-handler-inspector"],["unattributed"]]' \
    "$(jq -c '[.[].reviewers]' "$OUTF")" "attributed reviewers"
  # F2 is a security finding (a bare missing-validation), and F3 has no
  # reviewer dedup accepts: no pair.
  e2e_expect_line "PAIRS_CANDIDATE_TOTAL=0"
  e2e_expect_line "RUNS_WITHOUT_PAIRS=1"
  e2e_expect_line "DEDUP_HALF=not-exercised"
  e2e_expect_line "DEDUP_HALF_REASON=1 of 1 runs have no dedup candidate pair"
  e2e_expect_equal 'not-exercised|exact-line|{"0":1,"1":1,"2":1}' \
    "$(jq -r '[.dedup_half, .attribution, (.reviewers_per_finding | tojson)] | join("|")' "$RP_F/export-report.json")" "export-report.json"
  jq '.[0].review.false_findings = 1' "$E2E_DIR/runs.json" > "$E2E_DIR/r2.json"
  _rp export-recovered --runs-json "$E2E_DIR/r2.json" --transcripts "$T" --out "$E2E_DIR/f2"
  e2e_expect_line "RESCORE_MISMATCH=1"

  # A second run with one disjoint pair (code-reviewer at 47, error-handler-
  # inspector at 50): one run of two without a pair is not more than half.
  _rec_session "$T" sid-3 "[$(_rec_find G1 P1 correctness 47),$(_rec_find G2 P2 error-handling 50)]"
  _rec_agent "$T" sid-3 a flow:code-reviewer "intervals.py:47 keeps the point."
  _rec_agent "$T" sid-3 b flow:error-handler-inspector "intervals.py:50 drops the error."
  jq --arg c "$RP_CASE" --arg t "$RP_TRAP" '. + [{model:"claude-opus-5-5",arm:"review-b",case:$c,trap:$t,run:2,session_id:"sid-3",
    review:{hit:true,false_findings:1,scored_findings:2,findings_total:2,incomplete:false}}]' "$E2E_DIR/runs.json" > "$E2E_DIR/r3.json"
  _rp export-recovered --runs-json "$E2E_DIR/r3.json" --transcripts "$T" --out "$E2E_DIR/f3"
  e2e_expect_line "EXPORTED=2"
  e2e_expect_line "PAIRS_CANDIDATE_TOTAL=1"
  e2e_expect_line "RUNS_WITHOUT_PAIRS=1"
  e2e_expect_line "REVIEWERS_PER_FINDING=0:1,1:3,2:1"
  e2e_expect_line "DEDUP_HALF=exercised"
  e2e_expect_no_out "DEDUP_HALF_REASON="

  # Three of five findings cited by four subagents at their exact lines: the
  # run has a pair, but most findings carry four or more reviewers.
  T4="$E2E_DIR/t4"
  _rec_session "$T4" sid-4 "[$(_rec_find K1 P1 correctness 47),$(_rec_find K2 P2 correctness 48),$(_rec_find K3 P2 correctness 49),$(_rec_find K4 P2 correctness 10),$(_rec_find K5 P2 error-handling 11)]"
  for who in a:flow:code-reviewer b:flow:error-handler-inspector c:flow:convention-checker d:flow:test-runner; do
    _rec_agent "$T4" sid-4 "${who%%:*}" "${who#*:}" "intervals.py:47, intervals.py:48 and intervals.py:49 are wrong."
  done
  _rec_agent "$T4" sid-4 e flow:code-reviewer "intervals.py:10 is wrong."
  _rec_agent "$T4" sid-4 f flow:error-handler-inspector "intervals.py:11 swallows it."
  jq -nc --arg c "$RP_CASE" --arg t "$RP_TRAP" '[{model:"claude-opus-5-5",arm:"review-b",case:$c,trap:$t,run:1,session_id:"sid-4",
    review:{hit:true,false_findings:4,scored_findings:5,findings_total:5,incomplete:false}}]' > "$E2E_DIR/r4.json"
  _rp export-recovered --runs-json "$E2E_DIR/r4.json" --transcripts "$T4" --out "$E2E_DIR/f4"
  e2e_expect_line "REVIEWERS_PER_FINDING=1:2,4:3"
  e2e_expect_line "PAIRS_CANDIDATE_TOTAL=1"
  e2e_expect_line "RUNS_WITHOUT_PAIRS=0"
  e2e_expect_line "DEDUP_HALF=not-exercised"
  e2e_expect_line "DEDUP_HALF_REASON=3 of 5 findings carry 4 or more reviewers"
  # A record without its case stops the export with a STATE line, not a
  # traceback alone.
  jq -nc '[{model:"claude-opus-5-5",arm:"review-b",run:1,session_id:"sid-4"}]' > "$E2E_DIR/r5.json"
  _rp export-recovered --runs-json "$E2E_DIR/r5.json" --transcripts "$T4" --out "$E2E_DIR/f5"
  e2e_expect_line "STATE=failed"
  e2e_expect_out "ERROR=KeyError"
  e2e_expect_equal 1 "$E2E_RC" "exit status of an export that cannot read a record"
fi

if _want pilot-dedup-not-exercised; then
  _flow_test_begin "pilot-dedup-not-exercised"
  _rp_setup pilot-dedup-not-exercised "recovered findings that cannot exercise review.dedup: the report says so, the pair check reads not-exercised and review.dedup gets no verdict, while review.confidence is replayed (R14)"
  T="$E2E_DIR/transcripts"
  _rec_session "$T" sid-1 "[$(_rec_find F1 P1 correctness 47),$(_rec_find F2 P2 error-handling 120)]"
  _rec_agent "$T" sid-1 a flow:code-reviewer "intervals.py:47 keeps a half-open point; intervals.py:120 too."
  _rec_agent "$T" sid-1 b flow:error-handler-inspector "intervals.py:47 and intervals.py:120."
  jq -nc --arg c "$RP_CASE" --arg t "$RP_TRAP" '[{model:"opus",arm:"review-b",case:$c,trap:$t,run:1,session_id:"sid-1",
    review:{hit:true,false_findings:1,scored_findings:2,findings_total:2,incomplete:false}}]' > "$E2E_DIR/runs.json"
  _rp export-recovered --runs-json "$E2E_DIR/runs.json" --transcripts "$T" --out "$RP_F"
  e2e_expect_line "RESCORE_MISMATCH=0"
  e2e_expect_line "DEDUP_HALF=not-exercised"
  e2e_stub_start a "$(_both 0.9 0.2)"
  _shadow
  e2e_expect_line "PASS_STATE=ok"
  e2e_expect_line "PAIRS_CANDIDATE_TOTAL=0"
  e2e_expect_line "CONFIDENCE_ASKED_TOTAL=2"
  _rp table --replay "$RP_R" --model jev-1.13.0
  _on confidence --claim-supported 0.5
  e2e_expect_line "PASS_STATE=ok"
  _on dedup --same-defect 0.6
  _rp inspect --replay "$RP_R" --evals "$RP_EVALS"
  _rp aggregate --replay "$RP_R" --findings-dir "$RP_F" --evals "$RP_EVALS" --model jev-1.13.0 --runs-json "$E2E_DIR/runs.json"
  e2e_expect_line "AGGREGATE_STATE=ok"
  e2e_expect_line "DEDUP_HALF=not-exercised"
  e2e_expect_line "CHECK_PAIRS_CANDIDATE=not-exercised"
  e2e_expect_line "VERDICT_REVIEW_DEDUP=not-exercised"
  e2e_expect_no_out "CHOSEN_REVIEW_DEDUP="
  # review.confidence is replayed, and held: this pilot has no off pass and
  # one point per filter, so those checks did not run.
  e2e_expect_line "CHECK_OFF_IDENTITY=not-run"
  e2e_expect_line "CHECK_THRESHOLDS=not-run"
  e2e_expect_line "VERDICT_REVIEW_CONFIDENCE=held-by-checks"
  e2e_expect_equal 'not-exercised' "$(jq -r '.checks["pairs-candidate"].status' "$RP_R/report.json")" "the pair check in report.json"
  if grep -qF "review.dedup is first tested on the fresh re-run" "$RP_R/report.md" \
      && grep -qF "this replay tests the conversion, review.confidence, the answer table and the replay server only" "$RP_R/report.md"; then
    e2e_expect_equal yes yes "report.md says which half the replay tests"
  else
    e2e_expect_equal yes no "report.md says which half the replay tests"
  fi
  # The same findings without the export's note: the check is a flag again,
  # as it is for the fresh re-run.
  rm "$RP_F/export-report.json"
  _rp aggregate --replay "$RP_R" --findings-dir "$RP_F" --evals "$RP_EVALS" --model jev-1.13.0 --runs-json "$E2E_DIR/runs.json"
  e2e_expect_line "CHECK_PAIRS_CANDIDATE=flagged"
  e2e_expect_no_out "DEDUP_HALF="
  e2e_expect_line "VERDICT_REVIEW_DEDUP=held-by-checks"
  if grep -qF "review.dedup is first tested" "$RP_R/report.md"; then
    e2e_expect_equal no yes "report.md without the export's note"
  else
    e2e_expect_equal no no "report.md without the export's note"
  fi
fi

if _want helper-no-docstrings; then
  _flow_test_begin "helper-no-docstrings"
  _rp_setup helper-no-docstrings "bin/_flow_eval.py run without docstrings (python -OO) and no subcommand prints usage and exits 2, without a traceback"
  printf 'code: python3 -OO bin/_flow_eval.py\n' | _e2e_art
  rc=0; (cd "$E2E_REPO" && python3 -OO "$RP_HELPER") > "$E2E_DIR/helper.out" 2> "$E2E_DIR/helper.err" || rc=$?
  e2e_expect_equal 2 "$rc" "exit status"
  if grep -q Traceback "$E2E_DIR/helper.err"; then
    e2e_expect_equal none "$(head -c 200 "$E2E_DIR/helper.err")" "stderr traceback"
  else
    e2e_expect_equal none none "stderr traceback"
  fi
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
  # Another attempt at run 1 whose findings do not parse: the first
  # attempt's findings file is removed, not left as this run's (R40).
  _stream "no findings block" > "$RD/stream.jsonl"
  _helper finalize-review-run --run-dir "$RD" --case-dir "$RP_EVALS/$RP_CASE" --arm review-b \
    --case "$RP_CASE" --trap "$RP_TRAP" --run 1 --exit-code 0 --findings-out "$E2E_DIR/kept/1.json" --require-reviewers
  e2e_expect_equal 'true' "$(jq -c .review.incomplete "$RD/result.json")" "a run whose findings do not parse"
  e2e_expect_equal 0 "$( [ -e "$E2E_DIR/kept/1.json" ] && echo 1 || echo 0)" "the earlier attempt's findings file"
fi

# ----------------------------------------------------------------- recorded pilot pair counts

# The recovered runs' and the prompt pilots' committed pair counts are
# recomputed from their committed findings with the shipped candidate rule. A
# count or pair list that no longer matches (a rule change, or a count typed by
# hand) fails here.
if _want recorded-pilot-pairs; then
  _flow_test_begin "recorded-pilot-pairs"
  _rp_setup recorded-pilot-pairs "the recovered runs' and the prompt pilots' recorded review.dedup candidate pairs match the shipped rule over their committed findings"
  for REC in results-2026-09-25-review/candidate-pairs-2026-10-05.json \
             results-2026-10-05-review-s1/candidate-pairs-2026-10-05.json \
             results-2026-10-05-review-s1-pilot2/pilot-gate.json; do
    printf 'record: evals/%s\n' "$REC" | _e2e_art
    MISMATCH=$(cd "$E2E_REPO" && PYTHONDONTWRITEBYTECODE=1 python3 - "$REPO_ROOT/plugins/flow/bin" "$RP_EVALS/$REC" <<'PPY' 2>&1
import json, os, sys
sys.path.insert(0, sys.argv[1])
import _flow_eval_s1_replay as rp
import _flow_s1_dedup as dd
rec_path = sys.argv[2]
rec = json.load(open(rec_path))
base = os.path.join(os.path.dirname(rec_path), "findings")
total = 0
for run in rec["runs"]:
    conv = rp.convert(json.load(open(os.path.join(base, run["run"] + ".json"))))[0]
    got = [[p[2], p[3]] for p in dd.candidates(conv)]
    total += len(got)
    if run["dedup_candidate_pairs"] != len(got) or run["pairs"] != got:
        print("%s: recorded %s %s, recomputed %d %s" % (run["run"], run["dedup_candidate_pairs"], run["pairs"], len(got), got))
if rec["result"]["dedup_candidate_pairs"] != total:
    print("total: recorded %s, recomputed %d" % (rec["result"]["dedup_candidate_pairs"], total))
PPY
)
    printf 'mismatch: %s\n' "${MISMATCH:-none}" | _e2e_art
    e2e_expect_equal "" "$MISMATCH" "recorded pairs of $REC compared with the shipped rule"
  done
fi
