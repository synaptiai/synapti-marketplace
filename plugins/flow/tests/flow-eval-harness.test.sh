# Tests for the correctness-eval harness: plugins/flow/bin/flow-eval-run.sh,
# plugins/flow/bin/_flow_eval.py and the seeded-bug cases under
# plugins/flow/evals/. Offline only — no claude calls. Covers:
#   - unittest -v output parsing (single-line and docstring layouts, crash)
#   - the degenerate-input heuristic on fixture test files
#   - aggregation + decision rule on canned run results
#   - --dry-run plan shape (7 arms × 3 cases × N runs) and arm settings
#   - hidden suites pass against every reference impl and fail against every
#     trap variant on the tests traps.json lists for it (all three cases)
#   - case layout matches the documented `claude plugin eval` shape

RUNNER="$REPO_ROOT/plugins/flow/bin/flow-eval-run.sh"
HELPER="$REPO_ROOT/plugins/flow/bin/_flow_eval.py"
EVALS="$REPO_ROOT/plugins/flow/evals"

if ! command -v python3 >/dev/null 2>&1; then
  _flow_test_begin "python3 prerequisite"
  _flow_assert_pass "SKIP: python3 not installed"
  return 0
fi

TMP=$(mktemp -d -t flow-eval-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- 1. unittest output parsing --------------------------------------------
_flow_test_begin "parse-unittest: single-line and docstring layouts"
cat > "$TMP/canned.txt" <<'EOF'
test_alpha (test_hidden.T.test_alpha) ... ok
test_beta (test_hidden.T.test_beta)
Docstring on its own line. ... FAIL
test_gamma (test_hidden.T.test_gamma) ... ERROR
test_delta (test_hidden.T.test_delta) ... skipped 'not here'
test_epsilon (test_hidden.T.test_epsilon) ... ok

======================================================================
FAIL: test_beta (test_hidden.T.test_beta)
----------------------------------------------------------------------
Ran 5 tests in 0.002s

FAILED (failures=1, errors=1, skipped=1)
EOF
OUT=$(python3 "$HELPER" parse-unittest "$TMP/canned.txt")
assert_contains '"passed": 2' "$OUT" "two passing tests"
assert_contains '"total": 5' "$OUT" "five tests total"
assert_contains '"test_beta": "FAIL"' "$OUT" "docstring layout status attaches to the right test"
assert_contains '"test_gamma": "ERROR"' "$OUT" "ERROR status parsed"
assert_contains '"test_delta": "skipped"' "$OUT" "skipped normalised"
assert_contains '"completed": true' "$OUT" "Ran line matches the test count"

_flow_test_begin "parse-unittest: crash mid-suite leaves the pending test missing"
printf 'test_one (m.T.test_one) ... ok\ntest_two (m.T.test_two) ... Traceback (most recent call last):\nSegmentation fault\n' > "$TMP/crash.txt"
OUT=$(python3 "$HELPER" parse-unittest "$TMP/crash.txt")
assert_contains '"test_two": "missing"' "$OUT" "unterminated test marked missing"
assert_contains '"completed": false' "$OUT" "no Ran line -> not completed"
assert_contains '"passed": 1' "$OUT" "completed test still counted"

# --- 2. degenerate-input heuristic ------------------------------------------
_flow_test_begin "agent-tests: degenerate heuristic on a fixture test file"
mkdir -p "$TMP/proj/tests"
cat > "$TMP/proj/tests/test_mod.py" <<'EOF'
import unittest
import mod


class T(unittest.TestCase):
    def test_identical_streams(self):
        self.assertEqual(mod.pack((b"aa", b"aa", b"aa", b"aa")), b"\x02\x00\x02\x00\x02\x00aaaaaaaa")

    def test_palindrome_roundtrip(self):
        data = b"abba"
        self.assertEqual(mod.decode(mod.encode(data)), data)

    def test_empty_and_single(self):
        mod.split([])
        mod.split([7])

    def test_distinct(self):
        block = mod.pack((b"ab", b"c", b"def", b"gh"))
        self.assertEqual(block, b"\x02\x00\x01\x00\x03\x00bacfedhg")
        mod.allocate("1.00", [1, 2, 3], places=2)
        mod.allocate("1.00", weights=[1] * 7)
        computed = bytes(range(10))
        self.assertEqual(len(mod.encode(computed)), 16)

    def helper(self):
        return [9, 9, 9]
EOF
OUT=$(python3 "$HELPER" agent-tests --project-dir "$TMP/proj")
assert_contains '"test_functions": 4' "$OUT" "four test functions (helper excluded)"
assert_contains '"file_count": 1' "$OUT" "one test file"
# Inputs: (b"aa",)*4 identical; b"abba" palindrome; [] empty; [7] single;
# (b"ab",...) distinct; [1,2,3] distinct; [1]*7 identical. Expected values in
# assertEqual and the computed bytes(range(10)) are not inputs.
assert_contains '"literal_inputs": 7' "$OUT" "seven literal inputs counted"
assert_contains '"degenerate_inputs": 5' "$OUT" "five degenerate inputs"
assert_contains '"identical": 2' "$OUT" "identical kind counted twice"
assert_contains '"palindrome": 1' "$OUT" "palindrome kind"
assert_contains '"empty": 1' "$OUT" "empty kind"
assert_contains '"single": 1' "$OUT" "single kind"
assert_contains "[1] * 7" "$OUT" "repeat literal reported as example"
SHARE=$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(round(json.load(sys.stdin)["degenerate_share"], 3))')
assert_equal "0.714" "$SHARE" "degenerate share = 5/7"

_flow_test_begin "agent-tests: no test files -> zero counts and null share"
mkdir -p "$TMP/empty"
OUT=$(python3 "$HELPER" agent-tests --project-dir "$TMP/empty")
assert_contains '"test_functions": 0' "$OUT" "zero functions"
assert_contains '"degenerate_share": null' "$OUT" "share is null without inputs"

# --- 3. aggregation and decision rule -----------------------------------------
_flow_test_begin "aggregate: canned results -> summary.json/summary.md with decision"
write_result() {
  # write_result <out> <arm> <case> <n> <passed> <total> <tests> <degen-share|null> <cost> <turns> <error|null> <trapA> <trapB>
  local dir="$1/runs/$2/$3/$4"
  mkdir -p "$dir"
  local share="$8" err="${11}"
  [ "$share" != "null" ] && share="$share"
  [ "$err" != "null" ] && err="\"$err\""
  cat > "$dir/result.json" <<EOF
{"arm":"$2","case":"$3","run":$4,"cost_usd":$9,"num_turns":${10},"session_id":"s-$2-$3-$4","is_error":false,"error":$err,
 "hidden":{"passed":$5,"total":$6,"pass_rate":$(python3 -c "print($5/$6)"),"all_pass":$([ "$5" = "$6" ] && echo true || echo false),"failed_ids":[]},
 "traps":{"trap_a":${12},"trap_b":${13}},
 "agent_tests":{"files":1,"test_functions":$7,"literal_inputs":10,"degenerate_inputs":3,"degenerate_share":$share},
 "skills_invoked":["flow:tdd-patterns"]}
EOF
}
AGG="$TMP/agg"
for case in c1 c2 c3; do
  # enforce arms: 60% and 70%; suggest arms: 90% and 100%; off: 80%; baseline 80%
  write_result "$AGG" enforce-risk   "$case" 1 6 10 12 0.5 1.0 20 null true false
  write_result "$AGG" enforce-risk   "$case" 2 7 10 14 0.5 1.2 22 null true false
  write_result "$AGG" enforce-norisk "$case" 1 6 10 11 0.6 0.9 19 null true true
  write_result "$AGG" suggest-risk   "$case" 1 9 10 6 0.2 0.8 15 null false false
  write_result "$AGG" suggest-risk   "$case" 2 10 10 7 0.1 0.7 14 null false false
  write_result "$AGG" suggest-norisk "$case" 1 9 10 6 null 0.8 15 null false false
  write_result "$AGG" off-risk       "$case" 1 8 10 5 0.0 0.6 12 null false true
  write_result "$AGG" off-norisk     "$case" 1 8 10 5 0.0 0.6 12 timeout false true
  write_result "$AGG" baseline       "$case" 1 8 10 4 0.0 0.5 10 null false true
done
OUT=$(python3 "$HELPER" aggregate --out "$AGG")
assert_contains '"verdict": "flip-to-suggest"' "$OUT" "enforce below suggest by more than spread -> flip"
assert_file_exists "$AGG/summary.json" "summary.json written"
assert_file_exists "$AGG/summary.md" "summary.md written"
MD=$(cat "$AGG/summary.md")
assert_contains "should default to suggest" "$MD" "plain-sentence reading names the flip"
assert_contains "| enforce-risk | 6 | 65% |" "$MD" "per-arm row: enforce-risk mean 65% over 6 runs"
assert_contains "| suggest-risk | 6 | 95% |" "$MD" "per-arm row: suggest-risk mean 95%"
assert_contains "| off-norisk | 3 | 80% | 0% | 5.0 | 0% | \$0.60 | 12.0 | 3 |" "$MD" "per-arm row: 8/10 runs are not all-pass; errors counted"
assert_contains "| enforce-risk | c1 | 2 | 65% (60%–70%) |" "$MD" "per-cell row shows min–max"
assert_contains "## Trap catch rate" "$MD" "trap section present"
assert_contains "| enforce-risk | 100% | 0% |" "$MD" "trap catch rates per arm"
assert_match 'baseline scores 80% against a plugin-arm average of' "$MD" "baseline sentence"
assert_contains "riskMap=true average" "$MD" "risk-map sentence"
assert_contains "incomplete" "$MD" "provisional flag when arms lack 3 runs per case"
SPREAD=$(python3 -c 'import json; print(round(json.load(open("'"$AGG"'/summary.json"))["run_to_run_spread"], 4))')
assert_equal "0.0286" "$SPREAD" "spread = mean per-cell max-min (6 of 21 cells vary by 0.1 -> 0.6/21)"
DEG=$(python3 -c 'import json; print(json.load(open("'"$AGG"'/summary.json"))["per_arm"]["suggest-norisk"]["degenerate_share_mean"])')
assert_equal "None" "$DEG" "null degenerate share ignored in the mean"

_flow_test_begin "aggregate: enforce within spread -> keep-enforce"
AGG2="$TMP/agg2"
for case in c1 c2 c3; do
  write_result "$AGG2" enforce-risk "$case" 1 8 10 10 0.3 1.0 20 null false false
  write_result "$AGG2" enforce-risk "$case" 2 10 10 10 0.3 1.0 20 null false false
  write_result "$AGG2" suggest-risk "$case" 1 9 10 6 0.3 1.0 20 null false false
  write_result "$AGG2" suggest-risk "$case" 2 10 10 6 0.3 1.0 20 null false false
done
OUT=$(python3 "$HELPER" aggregate --out "$AGG2")
assert_contains '"verdict": "keep-enforce"' "$OUT" "gap 5 points < spread 15 points -> keep"
assert_contains "keeps testing.tddMode=enforce" "$(cat "$AGG2/summary.md")" "reading says keep"

_flow_test_begin "aggregate: no enforce arm -> insufficient-data"
AGG3="$TMP/agg3"
write_result "$AGG3" baseline c1 1 8 10 4 0.0 0.5 10 null false true
OUT=$(python3 "$HELPER" aggregate --out "$AGG3")
assert_contains '"verdict": "insufficient-data"' "$OUT" "rule not applied without both sides"

# --- 4. dry-run plan ----------------------------------------------------------
_flow_test_begin "--dry-run: 7 arms x 3 cases x N runs, no claude call"
OUT=$(PATH="$TMP/nobin:$PATH" "$RUNNER" --dry-run --runs 2 --out "$TMP/dry" 2>&1)
EXIT=$?
assert_exit 0 "$EXIT" "dry run exits 0 without claude on PATH"
assert_contains "PLAN  42 run(s): 7 arm(s) × 3 case(s)" "$OUT" "42 = 7 × 3 × 2"
assert_equal "42" "$(printf '%s\n' "$OUT" | grep -c '^RUN   ')" "one RUN line per planned run"
for arm in baseline enforce-risk enforce-norisk suggest-risk suggest-norisk off-risk off-norisk; do
  assert_contains "RUN   $arm/money-allocator/2" "$OUT" "arm $arm planned"
done
assert_contains "RUN   baseline/four-stream-codec/1  timeout=1800s  (no plugin)" "$OUT" "baseline has no plugin"
assert_contains 'settings={"testing":{"tddMode":"suggest","tddModeOptOut":true},"specFirst":{"riskMap":false}}' "$OUT" "suggest-norisk two-field opt-out"
assert_contains 'settings={"testing":{"tddMode":"enforce","tddModeOptOut":false},"specFirst":{"riskMap":true}}' "$OUT" "enforce-risk settings"
assert_contains 'settings={"testing":{"tddMode":"off","tddModeOptOut":true},"specFirst":{"riskMap":true}}' "$OUT" "off-risk settings"
assert_contains "--plugin-dir $REPO_ROOT/plugins/flow" "$OUT" "plugin arms load the plugin by absolute path"
assert_contains "--max-turns 60 --max-budget-usd 4" "$OUT" "defaults: 60 turns, \$4 per run"
assert_contains "--permission-mode acceptEdits --allowedTools Bash,Read,Write,Edit,Glob,Grep,Skill,Agent,TodoWrite,TaskCreate,TaskList,TaskUpdate,TaskGet" "$OUT" "allowed tools from prompt.md"
assert_contains "-u CLAUDECODE -u CLAUDE_CODE_SESSION_ID" "$OUT" "session identity vars stripped"
assert_contains "-u CLAUDE_CODE_ENTRYPOINT" "$OUT" "entrypoint stripped"
assert_not_contains "--model" "$OUT" "no model hardcoded"
assert_contains "total cap=\$250" "$OUT" "default total cap"
BASELINE_LINE=$(printf '%s\n' "$OUT" | grep -A1 '^RUN   baseline/four-stream-codec/1' | tail -1)
assert_not_contains "--plugin-dir" "$BASELINE_LINE" "baseline command has no --plugin-dir"
[ -d "$TMP/dry" ] && _flow_assert_fail "dry run left $TMP/dry behind" || _flow_assert_pass "dry run leaves no output dir"

_flow_test_begin "--dry-run: filters, model passthrough and resume skip"
OUT=$("$RUNNER" --dry-run --arm baseline,off-risk --case money-allocator --runs 1 --model my-model --max-turns 9 --out "$TMP/dry5" 2>&1)
assert_contains "PLAN  2 run(s): 2 arm(s) × 1 case(s)" "$OUT" "filters narrow the plan"
assert_contains "--model my-model" "$OUT" "explicit model passed through"
assert_contains "--max-turns 9" "$OUT" "explicit max-turns overrides prompt.md"
mkdir -p "$TMP/dry6/runs/baseline/money-allocator/1" && echo '{}' > "$TMP/dry6/runs/baseline/money-allocator/1/result.json"
OUT=$("$RUNNER" --dry-run --arm baseline --case money-allocator --runs 2 --out "$TMP/dry6" 2>&1)
assert_contains "SKIP  baseline/money-allocator/1 (result.json exists)" "$OUT" "completed run skipped on resume"
assert_contains "RUN   baseline/money-allocator/2" "$OUT" "remaining run still planned"
assert_contains "1 already complete" "$OUT" "plan line counts skips"

_flow_test_begin "usage errors"
ERR=$("$RUNNER" --arm nope --dry-run 2>&1 >/dev/null); EXIT=$?
assert_exit 1 "$EXIT" "unknown arm -> exit 1"
assert_contains "unknown arm 'nope'" "$ERR" "names the bad arm"
ERR=$("$RUNNER" --case nope --dry-run 2>&1 >/dev/null); EXIT=$?
assert_exit 1 "$EXIT" "unknown case -> exit 1"
ERR=$("$RUNNER" --max-budget-usd abc --dry-run 2>&1 >/dev/null); EXIT=$?
assert_exit 1 "$EXIT" "non-numeric budget -> exit 1"
ERR=$("$RUNNER" --bogus 2>&1 >/dev/null); EXIT=$?
assert_exit 1 "$EXIT" "unknown flag -> exit 1"

# --- 5. hidden suites vs reference and traps ---------------------------------
_flow_test_begin "check-cases: reference passes, every trap variant fails its listed tests"
OUT=$("$RUNNER" --check-cases 2>&1); EXIT=$?
assert_exit 0 "$EXIT" "check-cases exits 0"
assert_contains '"problems": []' "$OUT" "no problems reported"
for case in four-stream-codec sliding-window-limiter money-allocator; do
  assert_contains "\"$case\"" "$OUT" "case $case checked"
done
assert_contains '"reference": "25/25"' "$OUT" "four-stream/allocator reference 25/25"
assert_contains '"reference": "23/23"' "$OUT" "limiter reference 23/23"

_flow_test_begin "hidden-run: trap variants are caught, reference is not"
OUT=$(python3 "$HELPER" hidden-run --case-dir "$EVALS/four-stream-codec" --impl "$EVALS/four-stream-codec/hidden/traps/transposed_order.py")
assert_contains '"all_pass": false' "$OUT" "transposed variant fails"
TRAPPED=$(printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["traps"]["transposed_order"]["caught"], d["traps"]["ceil_split"]["caught"])')
assert_equal "True False" "$TRAPPED" "signature match: transposed flagged, ceil_split (shares one test) not"
OUT=$(python3 "$HELPER" hidden-run --case-dir "$EVALS/money-allocator" --impl "$EVALS/money-allocator/hidden/reference_impl.py")
assert_contains '"all_pass": true' "$OUT" "allocator reference passes"
assert_contains '"pass_rate": 1.0' "$OUT" "pass rate 1.0"

_flow_test_begin "hidden-run: missing module scores zero over the full suite"
mkdir -p "$TMP/nomod"
OUT=$(python3 "$HELPER" hidden-run --case-dir "$EVALS/sliding-window-limiter" --project-dir "$TMP/nomod")
assert_contains '"import_or_crash": true' "$OUT" "import failure flagged"
assert_contains '"total": 23' "$OUT" "total taken from the suite size"
assert_contains '"passed": 0' "$OUT" "zero passed"

_flow_test_begin "trap count and test count per case are within the brief"
for case in four-stream-codec sliding-window-limiter money-allocator; do
  N=$(grep -c '    def test_' "$EVALS/$case/hidden/test_hidden.py")
  [ "$N" -ge 12 ] && [ "$N" -le 25 ] && _flow_assert_pass "$case has $N hidden tests (12-25)" || _flow_assert_fail "$case has $N hidden tests"
  T=$(ls "$EVALS/$case/hidden/traps/"*.py | wc -l | tr -d ' ')
  [ "$T" -ge 5 ] && _flow_assert_pass "$case has $T trap variants" || _flow_assert_fail "$case has only $T trap variants"
done

# --- 6. case layout (official `claude plugin eval` shape) ----------------------
_flow_test_begin "case layout: prompt.md frontmatter, graders, scaffold, hidden, expected"
for case in four-stream-codec sliding-window-limiter money-allocator; do
  D="$EVALS/$case"
  for f in prompt.md expected.md graders/module-exists.md graders/completion-phrase.md scaffold/ISSUE.md hidden/test_hidden.py hidden/reference_impl.py hidden/traps.json; do
    assert_file_exists "$D/$f" "$case/$f"
  done
  META=$(python3 "$HELPER" case-meta "$D")
  assert_contains "name=$case" "$META" "$case frontmatter name"
  assert_contains "runs=3" "$META" "$case runs=3"
  assert_contains "max_turns=60" "$META" "$case max_turns=60"
  assert_contains "timeout_seconds=1800" "$META" "$case timeout"
  assert_not_contains "model=" "$META" "$case pins no model"
  assert_contains "type: file_exists" "$(cat "$D/graders/module-exists.md")" "$case file_exists grader"
  assert_contains "type: regex" "$(cat "$D/graders/completion-phrase.md")" "$case regex grader"
  assert_contains "IMPLEMENTATION COMPLETE" "$(cat "$D/graders/completion-phrase.md")" "$case regex matches the prompt's phrase"
  MODULE=$(python3 -c 'import json; print(json.load(open("'"$D"'/hidden/traps.json"))["module"])')
  assert_file_exists "$D/scaffold/$MODULE.py" "$case scaffold module $MODULE.py"
  assert_contains "raise NotImplementedError" "$(cat "$D/scaffold/$MODULE.py")" "$case skeleton bodies raise"
  assert_contains "starting" "$(cat "$D/scaffold/ISSUE.md")" "$case ISSUE.md says the skeleton is the starting point"
  AC=$(grep -c '^- \[ \] .* — verify: `' "$D/scaffold/ISSUE.md")
  [ "$AC" -ge 4 ] && [ "$AC" -le 6 ] && _flow_assert_pass "$case has $AC acceptance criteria with commands" || _flow_assert_fail "$case has $AC acceptance criteria"
  assert_contains "## Acceptance Criteria" "$(cat "$D/scaffold/ISSUE.md")" "$case AC heading"
  PROMPT_BASE=$(python3 "$HELPER" case-prompt "$D" --arm baseline)
  PROMPT_PLUGIN=$(python3 "$HELPER" case-prompt "$D" --arm enforce-risk)
  assert_not_contains "flow plugin" "$PROMPT_BASE" "$case baseline prompt has no plugin block"
  assert_not_contains "flow-only" "$PROMPT_BASE" "$case baseline prompt has no marker residue"
  assert_contains "specification-capture" "$PROMPT_PLUGIN" "$case plugin prompt names specification-capture"
  assert_contains "tdd-patterns" "$PROMPT_PLUGIN" "$case plugin prompt names tdd-patterns"
  assert_not_contains "flow-only" "$PROMPT_PLUGIN" "$case plugin prompt has markers stripped"
  assert_contains "IMPLEMENTATION COMPLETE" "$PROMPT_PLUGIN" "$case prompt asks for the completion phrase"
  # expected.md lists every trap by name
  for trap in $(python3 -c 'import json; print(" ".join(json.load(open("'"$D"'/hidden/traps.json"))["traps"]))'); do
    assert_contains "\`$trap\`" "$(cat "$D/expected.md")" "$case expected.md documents $trap"
  done
done

_flow_test_begin "expected.md test-name claims match traps.json"
for case in four-stream-codec sliding-window-limiter money-allocator; do
  MISSING=$(python3 - "$EVALS/$case" <<'EOF'
import json, re, sys
d = sys.argv[1]
traps = json.load(open(d + "/hidden/traps.json"))["traps"]
text = open(d + "/expected.md").read()
bad = []
for name, trap in traps.items():
    row = next((l for l in text.splitlines() if l.startswith("| `%s` |" % name)), "")
    for t in re.findall(r"`(test_\w+)`", row):
        if t not in trap["discriminating_tests"]:
            bad.append("%s:%s" % (name, t))
    m = re.search(r"\(\+(\d+) more\)", row)
    listed = len(re.findall(r"`test_\w+`", row))
    if m and listed + int(m.group(1)) != len(trap["discriminating_tests"]):
        bad.append("%s:count" % name)
    if not m and listed != len(trap["discriminating_tests"]):
        bad.append("%s:count" % name)
print(" ".join(bad))
EOF
)
  assert_equal "" "$MISSING" "$case expected.md rows agree with traps.json"
done

# --- 7. references doc ----------------------------------------------------------
_flow_test_begin "references/correctness-eval.md documents the harness"
DOC=$(cat "$REPO_ROOT/plugins/flow/references/correctness-eval.md")
assert_contains "flow-eval-run.sh" "$DOC" "names the runner"
assert_contains "summary.md" "$DOC" "explains summary.md"
assert_contains "tddMode" "$DOC" "states the decision rule on tddMode"
assert_contains "run-to-run spread" "$DOC" "defines the spread"
assert_contains "## Limitations" "$DOC" "has a limitations section"
assert_contains "test_hidden.py" "$DOC" "names the hidden suite"
