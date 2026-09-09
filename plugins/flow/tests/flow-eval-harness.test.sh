# Tests for the correctness-eval harness: plugins/flow/bin/flow-eval-run.sh,
# plugins/flow/bin/_flow_eval.py and the seeded-bug cases under
# plugins/flow/evals/. Offline only — no claude calls. Covers:
#   - unittest -v output parsing (single-line and docstring layouts, crash)
#   - the degenerate-input heuristic on fixture test files
#   - own-test trap grading on a fixture case (a fake agent suite that catches
#     two of three trap variants; null-with-reason on unusable suites)
#   - finalize-run on a canned stream (model from modelUsage, own-test fields,
#     project snapshot)
#   - aggregation + decision rule on canned run results, grouped by model,
#     with the own-test secondary signal, and the legacy layout + migrate-layout
#   - --dry-run plan shape (models × 7 arms × 5 cases × N runs) and arm settings
#   - hidden suites pass against every reference impl and fail against every
#     trap variant on the tests traps.json lists for it (all five cases)
#   - case layout matches the documented `claude plugin eval` shape

RUNNER="$REPO_ROOT/plugins/flow/bin/flow-eval-run.sh"
HELPER="$REPO_ROOT/plugins/flow/bin/_flow_eval.py"
EVALS="$REPO_ROOT/plugins/flow/evals"
OLD_CASES="four-stream-codec sliding-window-limiter money-allocator"
NEW_CASES="interval-algebra"
ALL_CASES="$OLD_CASES $NEW_CASES"

if ! command -v python3 >/dev/null 2>&1; then
  _flow_test_begin "python3 prerequisite"
  _flow_assert_pass "SKIP: python3 not installed"
  return 0
fi

TMP=$(mktemp -d -t flow-eval-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
export PYTHONSAFEPATH=1

json_get() {
  # json_get <file> <python expression over d>
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2" 2>/dev/null
}

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

# --- 3. own-test trap grading on a fixture case -------------------------------
# Fixture case `mini`: module mini.py with add/mul/neg, a hidden suite, a
# reference and three trap variants. The fake agent suite feeds add and mul
# discriminating inputs but only neg(0), which every variant gets right.
MINI="$TMP/mini-case"
mkdir -p "$MINI/hidden/traps" "$MINI/scaffold"
cat > "$MINI/hidden/reference_impl.py" <<'EOF'
"""Reference for the mini fixture case."""
LIMIT = 100


def add(a, b):
    return a + b


def mul(a, b):
    return a * b


def neg(a):
    return -a
EOF
cat > "$MINI/hidden/traps/add_wrong.py" <<'EOF'
"""Trap: add subtracts. Masked by add(x, 0) and add(0, 0)."""
from reference_impl import *  # noqa: F401,F403


def add(a, b):
    return a - b
EOF
cat > "$MINI/hidden/traps/mul_wrong.py" <<'EOF'
"""Trap: mul adds. Masked by mul(2, 2) and mul(0, 0)."""
from reference_impl import *  # noqa: F401,F403


def mul(a, b):
    return a + b
EOF
cat > "$MINI/hidden/traps/neg_wrong.py" <<'EOF'
"""Trap: neg is the identity. Masked by neg(0)."""
from reference_impl import *  # noqa: F401,F403


def neg(a):
    return a
EOF
cat > "$MINI/hidden/test_hidden.py" <<'EOF'
import unittest

import mini


class T(unittest.TestCase):
    def test_add_distinct(self):
        self.assertEqual(mini.add(2, 3), 5)

    def test_mul_distinct(self):
        self.assertEqual(mini.mul(2, 3), 6)

    def test_neg_nonzero(self):
        self.assertEqual(mini.neg(4), -4)


if __name__ == "__main__":
    unittest.main()
EOF
cat > "$MINI/hidden/traps.json" <<'EOF'
{"module": "mini", "traps": {
  "add_wrong": {"description": "add subtracts", "variant": "hidden/traps/add_wrong.py", "discriminating_tests": ["test_add_distinct"]},
  "mul_wrong": {"description": "mul adds", "variant": "hidden/traps/mul_wrong.py", "discriminating_tests": ["test_mul_distinct"]},
  "neg_wrong": {"description": "neg is identity", "variant": "hidden/traps/neg_wrong.py", "discriminating_tests": ["test_neg_nonzero"]}
}}
EOF
printf 'def add(a, b):\n    raise NotImplementedError\n' > "$MINI/scaffold/mini.py"
printf -- '---\nname: mini\n---\nImplement mini.\n' > "$MINI/prompt.md"
make_agent_project() {
  # make_agent_project <dir> — a correct mini.py plus the fake agent suite
  local dir="$1"
  mkdir -p "$dir/tests"
  cp "$MINI/hidden/reference_impl.py" "$dir/mini.py"
  : > "$dir/tests/__init__.py"
  cat > "$dir/tests/test_mini.py" <<'EOF'
import unittest

import mini


class Add(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(mini.add(2, 3), 5)


class Mul(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(mini.mul(2, 3), 6)

    def test_neg_zero_is_degenerate(self):
        self.assertEqual(mini.neg(0), 0)
EOF
}

_flow_test_begin "own-test-traps: fake agent suite catches two of three variants"
make_agent_project "$TMP/agent1"
OUT=$(python3 "$HELPER" own-test-traps --case-dir "$MINI" --project-dir "$TMP/agent1" --out "$TMP/agent1-own.json")
assert_contains '"add_wrong": true' "$OUT" "add_wrong caught (add(2,3) discriminates)"
assert_contains '"mul_wrong": true' "$OUT" "mul_wrong caught (mul(2,3) discriminates)"
assert_contains '"neg_wrong": false' "$OUT" "neg_wrong missed (neg(0) is degenerate)"
assert_contains '"reason": null' "$OUT" "no reason when scored"
RATE=$(json_get "$TMP/agent1-own.json" 'round(d["catch_rate"], 3)')
assert_equal "0.667" "$RATE" "catch rate = 2/3"
assert_equal "3" "$(json_get "$TMP/agent1-own.json" 'd["own_impl"]["passed"]')" "all three own tests pass on the agent's module"
assert_contains 'tests.test_mini.Add.test_basic' "$(json_get "$TMP/agent1-own.json" 'd["per_trap"]["add_wrong"]["failing_own_tests"]')" "failing own test named by full id (same method name in two classes)"
assert_contains 'tests.test_mini.Mul.test_basic' "$(json_get "$TMP/agent1-own.json" 'd["per_trap"]["mul_wrong"]["failing_own_tests"]')" "second class's test_basic counted separately"
assert_contains 'python3 -m unittest discover -s tests -t . -v' "$OUT" "suite run the way the agent ran it"
assert_file_exists "$TMP/agent1/mini.py" "agent project untouched"
assert_equal "$(cat "$MINI/hidden/reference_impl.py")" "$(cat "$TMP/agent1/mini.py")" "agent module not overwritten by the swap"
[ -e "$TMP/agent1/reference_impl.py" ] && _flow_assert_fail "reference_impl.py leaked into the agent project" || _flow_assert_pass "reference_impl.py not left in the agent project"

_flow_test_begin "own-test-traps: unusable suites score null with a reason, never crash"
mkdir -p "$TMP/agent2" && cp "$MINI/hidden/reference_impl.py" "$TMP/agent2/mini.py"
OUT=$(python3 "$HELPER" own-test-traps --case-dir "$MINI" --project-dir "$TMP/agent2"); EXIT=$?
assert_exit 0 "$EXIT" "missing tests/ exits 0"
assert_contains '"catch_rate": null' "$OUT" "null rate without tests/"
assert_contains 'no tests/ directory' "$OUT" "reason names the missing directory"
make_agent_project "$TMP/agent3"
sed -i 's/^import mini$/import calc as mini/' "$TMP/agent3/tests/test_mini.py"
cp "$TMP/agent3/mini.py" "$TMP/agent3/calc.py"
OUT=$(python3 "$HELPER" own-test-traps --case-dir "$MINI" --project-dir "$TMP/agent3")
assert_contains '"catch_rate": null' "$OUT" "null rate when the tests import another module name"
assert_contains 'never import mini' "$OUT" "reason names the module"
make_agent_project "$TMP/agent4"
printf '\n\ndef helper(x):\n    return x\n' >> "$TMP/agent4/mini.py"
printf '\n    def test_helper(self):\n        self.assertEqual(mini.helper(1), 1)\n' >> "$TMP/agent4/tests/test_mini.py"
OUT=$(python3 "$HELPER" own-test-traps --case-dir "$MINI" --project-dir "$TMP/agent4")
assert_contains '"catch_rate": null' "$OUT" "null rate when the tests use a name the variants lack"
assert_contains 'helper' "$OUT" "reason names the missing name"
make_agent_project "$TMP/agent5"
printf 'def add(a, b):\n    return a - b\n' > "$TMP/agent5/mini.py"
OUT=$(python3 "$HELPER" own-test-traps --case-dir "$MINI" --project-dir "$TMP/agent5")
assert_contains '"catch_rate": null' "$OUT" "null rate when no own test passes on the agent's module"
assert_contains 'no own test passes' "$OUT" "reason says the suite is not an oracle"
make_agent_project "$TMP/agent8"
# the agent's neg(0) returns 5 and its test asserts that: passes on its own module,
# fails on the reference (and so on every variant) -> not an oracle, not a catch
printf '\n\ndef neg(a):\n    return 5 if a == 0 else -a\n' >> "$TMP/agent8/mini.py"
printf '\n    def test_neg_zero_disagrees(self):\n        self.assertEqual(mini.neg(0), 5)\n' >> "$TMP/agent8/tests/test_mini.py"
OUT=$(python3 "$HELPER" own-test-traps --case-dir "$MINI" --project-dir "$TMP/agent8" --out "$TMP/agent8-own.json")
assert_contains '"neg_wrong": false' "$OUT" "a test disagreeing with the reference does not catch every variant"
assert_equal "0.667" "$(json_get "$TMP/agent8-own.json" 'round(d["catch_rate"], 3)')" "catch rate unchanged by the disagreeing test"
assert_contains 'tests.test_mini.Mul.test_neg_zero_disagrees' "$(json_get "$TMP/agent8-own.json" 'd["disagree_with_reference"]')" "disagreeing test listed"
assert_equal "3" "$(json_get "$TMP/agent8-own.json" 'd["reference_run"]["passed"]')" "reference passes the other three"
make_agent_project "$TMP/agent6"
printf 'def broken(:\n' > "$TMP/agent6/tests/test_mini.py"
OUT=$(python3 "$HELPER" own-test-traps --case-dir "$MINI" --project-dir "$TMP/agent6"); EXIT=$?
assert_exit 0 "$EXIT" "syntax error in the agent's tests exits 0"
assert_contains '"catch_rate": null' "$OUT" "null rate on a syntax error"

_flow_test_begin "finalize-run: model from modelUsage, own-test fields, project snapshot"
make_agent_project "$TMP/agent7"
RUN7="$TMP/run7"; mkdir -p "$RUN7"
cat > "$RUN7/stream.jsonl" <<'EOF'
{"type":"system","subtype":"init","session_id":"s7"}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{}},{"type":"tool_use","name":"Skill","input":{"skill":"flow:tdd-patterns"}}]}}
{"type":"result","subtype":"success","is_error":false,"num_turns":5,"total_cost_usd":0.25,"session_id":"s7","result":"done IMPLEMENTATION COMPLETE","permission_denials":[],"modelUsage":{"claude-test-model":{"costUSD":0.2},"claude-helper-model":{"costUSD":0.05}}}
EOF
OUT=$(python3 "$HELPER" finalize-run --run-dir "$RUN7" --case-dir "$MINI" --project-dir "$TMP/agent7" --arm off-risk --case mini --run 1 --exit-code 0 --duration 12 --model-requested claude-test-model)
assert_contains '"model": "claude-test-model"' "$OUT" "primary model = the modelUsage key with the largest cost"
assert_file_exists "$RUN7/result.json" "result.json written"
assert_file_exists "$RUN7/own-test-traps.json" "own-test-traps.json written"
assert_file_exists "$RUN7/project/mini.py" "project snapshot keeps the module"
assert_file_exists "$RUN7/project/tests/test_mini.py" "project snapshot keeps the tests"
assert_equal "claude-test-model" "$(json_get "$RUN7/result.json" 'd["model"]')" "result.json model"
assert_equal "['claude-helper-model', 'claude-test-model']" "$(json_get "$RUN7/result.json" 'd["models_used"]')" "every billed model recorded"
assert_equal "claude-test-model" "$(json_get "$RUN7/result.json" 'd["model_requested"]')" "requested model recorded"
assert_equal "0.667" "$(json_get "$RUN7/result.json" 'round(d["own_test_trap_catch_rate"], 3)')" "own-test catch rate in result.json"
assert_equal "True" "$(json_get "$RUN7/result.json" 'd["own_test_traps"]["caught"]["add_wrong"]')" "per-trap own-test verdict in result.json"
assert_equal "1.0" "$(json_get "$RUN7/result.json" 'd["hidden"]["pass_rate"]')" "hidden suite still the primary score"
assert_equal "['flow:tdd-patterns']" "$(json_get "$RUN7/result.json" 'd["skills_invoked"]')" "skills parsed from the stream"
assert_equal "True" "$(json_get "$RUN7/result.json" 'd["completion_phrase"]')" "completion phrase detected"

# --- 4. aggregation and decision rule -----------------------------------------
_flow_test_begin "aggregate: canned results -> summary.json/summary.md with decision (per model)"
write_result() {
  # write_result <out> <model|-> <arm> <case> <n> <passed> <total> <tests> <degen-share|null> <cost> <turns> <error|null> <trapA> <trapB> <own-rate|null> <ownA> <ownB>
  # model "-" writes the legacy runs/<arm>/<case>/<n> layout without a `model` field.
  local out="$1" model="$2" arm="$3" case="$4" n="$5" passed="$6" total="$7" tests="$8" share="$9"
  local cost="${10}" turns="${11}" err="${12}" trap_a="${13}" trap_b="${14}" own="${15}" own_a="${16}" own_b="${17}"
  local dir model_field=""
  if [ "$model" = "-" ]; then
    dir="$out/runs/$arm/$case/$n"
  else
    dir="$out/runs/$model/$arm/$case/$n"
    model_field="\"model\":\"$model\","
  fi
  mkdir -p "$dir"
  [ "$err" != "null" ] && err="\"$err\""
  cat > "$dir/result.json" <<EOF
{$model_field"arm":"$arm","case":"$case","run":$n,"cost_usd":$cost,"num_turns":$turns,"session_id":"s-$arm-$case-$n","is_error":false,"error":$err,
 "hidden":{"passed":$passed,"total":$total,"pass_rate":$(python3 -c "print($passed/$total)"),"all_pass":$([ "$passed" = "$total" ] && echo true || echo false),"failed_ids":[]},
 "traps":{"trap_a":$trap_a,"trap_b":$trap_b},
 "agent_tests":{"files":1,"test_functions":$tests,"literal_inputs":10,"degenerate_inputs":3,"degenerate_share":$share},
 "own_test_trap_catch_rate":$own,
 "own_test_traps":{"caught":{"trap_a":$([ "$own" = "null" ] && echo null || echo "$own_a"),"trap_b":$([ "$own" = "null" ] && echo null || echo "$own_b")},"reason":$([ "$own" = "null" ] && echo '"no tests/ directory"' || echo null)},
 "skills_invoked":["flow:tdd-patterns"]}
EOF
}
AGG="$TMP/agg"
M=claude-a
for case in c1 c2 c3; do
  # enforce arms: 60% and 70%; suggest arms: 90% and 100%; off: 80%; baseline 80%
  write_result "$AGG" $M enforce-risk   "$case" 1 6 10 12 0.5 1.0 20 null true false 0.5 true false
  write_result "$AGG" $M enforce-risk   "$case" 2 7 10 14 0.5 1.2 22 null true false 0.5 true false
  write_result "$AGG" $M enforce-norisk "$case" 1 6 10 11 0.6 0.9 19 null true true 1.0 true true
  write_result "$AGG" $M suggest-risk   "$case" 1 9 10 6 0.2 0.8 15 null false false 0.0 false false
  write_result "$AGG" $M suggest-risk   "$case" 2 10 10 7 0.1 0.7 14 null false false 0.5 true false
  write_result "$AGG" $M suggest-norisk "$case" 1 9 10 6 null 0.8 15 null false false null false false
  write_result "$AGG" $M off-risk       "$case" 1 8 10 5 0.0 0.6 12 null false true 0.5 false true
  write_result "$AGG" $M off-norisk     "$case" 1 8 10 5 0.0 0.6 12 timeout false true 0.5 false true
  write_result "$AGG" $M baseline       "$case" 1 8 10 4 0.0 0.5 10 null false true 1.0 true true
done
OUT=$(python3 "$HELPER" aggregate --out "$AGG")
assert_contains '"verdicts": {"claude-a": "flip-to-suggest"}' "$OUT" "enforce below suggest by more than spread -> flip (per model)"
assert_contains '"models": ["claude-a"]' "$OUT" "one model listed"
assert_file_exists "$AGG/summary.json" "summary.json written"
assert_file_exists "$AGG/summary.md" "summary.md written"
MD=$(cat "$AGG/summary.md")
assert_contains "should default to suggest" "$MD" "plain-sentence reading names the flip"
assert_contains "Verdict for \`claude-a\`: \`flip-to-suggest\` (decided by the primary signal)" "$MD" "verdict line names the model and the signal"
assert_contains "| Model | Arm | Runs | Hidden pass rate | All-pass runs | Own tests catch traps |" "$MD" "per-arm table has Model and own-test columns"
assert_contains "| claude-a | enforce-risk | 6 | 65% | 0% | 50% (6/6) |" "$MD" "per-arm row: enforce-risk mean 65% over 6 runs, own tests catch 50%"
assert_contains "| claude-a | suggest-risk | 6 | 95% | 50% | 25% (6/6) |" "$MD" "per-arm row: suggest-risk own-test mean over 0.0/0.5"
assert_contains "| claude-a | suggest-norisk | 3 | 90% | 0% | - (0/3) |" "$MD" "unscored own tests render as - with 0 scored runs"
assert_contains "| claude-a | off-norisk | 3 | 80% | 0% | 50% (3/3) | 5.0 | 0% | \$0.60 | 12.0 | 3 |" "$MD" "per-arm row: 8/10 runs are not all-pass; errors counted"
assert_contains "| claude-a | enforce-risk | c1 | 2 | 65% (60%–70%) |" "$MD" "per-cell row shows min–max"
assert_contains "## Trap catch rate" "$MD" "trap section present"
assert_contains "### claude-a — c1" "$MD" "trap tables keyed by model and case"
assert_contains "| enforce-risk | 100% | 0% |" "$MD" "trap catch rates per arm"
assert_contains "## Own-test trap catch rate" "$MD" "own-test trap section present"
assert_contains "| enforce-norisk | 1/1 | 100% | 100% |" "$MD" "own-test per-trap row with scored-run count"
assert_contains "| suggest-norisk | 0/1 | - | - |" "$MD" "own-test per-trap row for an unscored cell"
assert_match 'baseline scores 80% against a plugin-arm average of' "$MD" "baseline sentence"
assert_contains "Own tests catch 100% of the trap variants on the baseline against" "$MD" "baseline own-test sentence"
assert_contains "riskMap=true average" "$MD" "risk-map sentence"
assert_contains "incomplete" "$MD" "provisional flag when arms lack 3 runs per case"
SPREAD=$(json_get "$AGG/summary.json" 'round(d["per_model"]["claude-a"]["run_to_run_spread"], 4)')
assert_equal "0.0286" "$SPREAD" "spread = mean per-cell max-min (6 of 21 cells vary by 0.1 -> 0.6/21)"
DEG=$(json_get "$AGG/summary.json" 'd["per_model"]["claude-a"]["per_arm"]["suggest-norisk"]["degenerate_share_mean"]')
assert_equal "None" "$DEG" "null degenerate share ignored in the mean"
assert_equal "None" "$(json_get "$AGG/summary.json" 'd["per_model"]["claude-a"]["per_arm"]["suggest-norisk"]["own_test_trap_catch_rate"]')" "null own-test rate ignored in the mean"
assert_equal "['no tests/ directory']" "$(json_get "$AGG/summary.json" 'd["per_model"]["claude-a"]["per_cell"]["suggest-norisk/c1"]["own_test_trap_unscored_reasons"]')" "unscored reasons collected per cell"
assert_equal "0.5" "$(json_get "$AGG/summary.json" 'd["per_model"]["claude-a"]["per_cell"]["suggest-risk/c1"]["own_test_trap_catch"]["trap_a"]')" "per-trap own-test catch rate per cell"

_flow_test_begin "aggregate: two models are reported separately with their own verdicts"
AGG2="$TMP/agg2"
for case in c1 c2 c3; do
  write_result "$AGG2" model-x enforce-risk "$case" 1 8 10 10 0.3 1.0 20 null false false 0.5 true false
  write_result "$AGG2" model-x enforce-risk "$case" 2 10 10 10 0.3 1.0 20 null false false 0.5 true false
  write_result "$AGG2" model-x suggest-risk "$case" 1 9 10 6 0.3 1.0 20 null false false 0.5 true false
  write_result "$AGG2" model-x suggest-risk "$case" 2 10 10 6 0.3 1.0 20 null false false 0.5 true false
  write_result "$AGG2" model-y enforce-risk "$case" 1 5 10 10 0.3 2.0 30 null true true 0.5 true false
  write_result "$AGG2" model-y suggest-risk "$case" 1 10 10 6 0.3 2.0 30 null false false 0.5 true false
done
OUT=$(python3 "$HELPER" aggregate --out "$AGG2")
assert_contains '"models": ["model-x", "model-y"]' "$OUT" "both models listed"
assert_contains '"model-x": "keep-enforce"' "$OUT" "model-x: gap 5 points < spread 15 points, own tests tie -> keep"
assert_contains '"model-y": "flip-to-suggest"' "$OUT" "model-y: enforce 50 points below suggest with zero spread -> flip"
MD=$(cat "$AGG2/summary.md")
assert_contains "Runs: 18 across 2 model(s)" "$MD" "header counts models"
assert_contains "| model-x | enforce-risk | 6 | 90% |" "$MD" "model-x per-arm row"
assert_contains "| model-y | enforce-risk | 3 | 50% |" "$MD" "model-y per-arm row"
assert_contains "**model-x**" "$MD" "reading per model"
assert_contains "**model-y**" "$MD" "reading per second model"
assert_equal "secondary" "$(json_get "$AGG2/summary.json" 'd["per_model"]["model-x"]["decision"]["decided_by"]')" "tie within spread goes to the secondary signal"
assert_equal "tie" "$(json_get "$AGG2/summary.json" 'd["per_model"]["model-x"]["decision"]["secondary"]["verdict"]')" "equal own-test rates -> secondary tie"
assert_equal "12.0" "$(json_get "$AGG2/summary.json" 'round(d["per_model"]["model-y"]["total_cost_usd"], 2)')" "per-model cost total (6 runs at \$2)"
assert_equal "24.0" "$(json_get "$AGG2/summary.json" 'round(d["total_cost_usd"], 1)')" "overall cost total (12 at \$1 + 6 at \$2)"

_flow_test_begin "aggregate: secondary signal decides a hidden-pass-rate tie"
AGG3="$TMP/agg3"
for case in c1 c2 c3; do
  # hidden: enforce 90% (80/100), suggest 95% (90/100): gap 5 < spread 15 -> tie.
  # own tests: enforce 30%, suggest 80% with zero own-test spread -> alt ahead.
  write_result "$AGG3" m enforce-risk "$case" 1 8 10 10 0.3 1.0 20 null false false 0.3 false false
  write_result "$AGG3" m enforce-risk "$case" 2 10 10 10 0.3 1.0 20 null false false 0.3 false false
  write_result "$AGG3" m suggest-risk "$case" 1 9 10 6 0.3 1.0 20 null false false 0.8 true true
  write_result "$AGG3" m suggest-risk "$case" 2 10 10 6 0.3 1.0 20 null false false 0.8 true true
done
OUT=$(python3 "$HELPER" aggregate --out "$AGG3")
assert_contains '"m": "flip-to-suggest"' "$OUT" "alt catches more traps with own tests -> flip by the secondary signal"
assert_equal "secondary" "$(json_get "$AGG3/summary.json" 'd["per_model"]["m"]["decision"]["decided_by"]')" "decided_by secondary"
assert_equal "alt-ahead" "$(json_get "$AGG3/summary.json" 'd["per_model"]["m"]["decision"]["secondary"]["verdict"]')" "secondary verdict alt-ahead"
assert_contains "the secondary signal decides: the agent's own tests catch 80% of the trap variants under suggest against 30% under enforce" "$(cat "$AGG3/summary.md")" "reading explains the secondary decision"
AGG4="$TMP/agg4"
for case in c1 c2 c3; do
  write_result "$AGG4" m enforce-risk "$case" 1 8 10 10 0.3 1.0 20 null false false 0.9 true true
  write_result "$AGG4" m enforce-risk "$case" 2 10 10 10 0.3 1.0 20 null false false 0.9 true true
  write_result "$AGG4" m suggest-risk "$case" 1 9 10 6 0.3 1.0 20 null false false 0.4 true false
  write_result "$AGG4" m suggest-risk "$case" 2 10 10 6 0.3 1.0 20 null false false 0.4 true false
done
OUT=$(python3 "$HELPER" aggregate --out "$AGG4")
assert_contains '"m": "keep-enforce"' "$OUT" "enforce catches more traps with own tests -> keep"
assert_equal "enforce-ahead" "$(json_get "$AGG4/summary.json" 'd["per_model"]["m"]["decision"]["secondary"]["verdict"]')" "secondary verdict enforce-ahead"
assert_contains "so the rule keeps testing.tddMode=enforce" "$(cat "$AGG4/summary.md")" "reading says keep"
AGG5="$TMP/agg5"
for case in c1 c2 c3; do
  write_result "$AGG5" m enforce-risk "$case" 1 8 10 10 0.3 1.0 20 null false false null false false
  write_result "$AGG5" m enforce-risk "$case" 2 10 10 10 0.3 1.0 20 null false false null false false
  write_result "$AGG5" m suggest-risk "$case" 1 9 10 6 0.3 1.0 20 null false false 0.8 true true
  write_result "$AGG5" m suggest-risk "$case" 2 10 10 6 0.3 1.0 20 null false false 0.8 true true
done
OUT=$(python3 "$HELPER" aggregate --out "$AGG5")
assert_contains '"m": "keep-enforce"' "$OUT" "own-test rate missing on one side -> primary signal stands"
assert_equal "primary" "$(json_get "$AGG5/summary.json" 'd["per_model"]["m"]["decision"]["decided_by"]')" "decided_by primary"
assert_contains "own-test trap catch rate is unavailable for one side" "$(cat "$AGG5/summary.md")" "reading explains why"

_flow_test_begin "aggregate: no enforce arm -> insufficient-data; no runs -> empty summary"
AGG6="$TMP/agg6"
write_result "$AGG6" m baseline c1 1 8 10 4 0.0 0.5 10 null false true 0.5 true false
OUT=$(python3 "$HELPER" aggregate --out "$AGG6")
assert_contains '"m": "insufficient-data"' "$OUT" "rule not applied without both sides"
mkdir -p "$TMP/agg7"
OUT=$(python3 "$HELPER" aggregate --out "$TMP/agg7"); EXIT=$?
assert_exit 0 "$EXIT" "empty results dir aggregates without error"
assert_contains '"runs": 0' "$OUT" "zero runs reported"
assert_contains "No runs found." "$(cat "$TMP/agg7/summary.md")" "summary.md says so"

_flow_test_begin "aggregate + migrate-layout: legacy runs/<arm>/<case>/<n> results"
LEG="$TMP/legacy"
for case in c1 c2; do
  write_result "$LEG" - enforce-risk "$case" 1 9 10 10 0.3 1.0 20 null false false null false false
  write_result "$LEG" - suggest-risk "$case" 1 9 10 6 0.3 1.0 20 null false false null false false
done
# one legacy run carries a claude.json whose modelUsage names the model
printf '{"type":"result","modelUsage":{"claude-legacy":{"costUSD":1.0}}}\n' > "$LEG/runs/enforce-risk/c1/1/claude.json"
OUT=$(python3 "$HELPER" aggregate --out "$LEG")
assert_contains '"models": ["claude-legacy", "default"]' "$OUT" "legacy runs grouped by claude.json model, else default"
assert_contains "4 run(s) were read from the older" "$(cat "$LEG/summary.md")" "summary flags the legacy layout"
OUT=$(python3 "$HELPER" migrate-layout --out "$LEG")
assert_contains '"moved": 4' "$OUT" "four legacy runs moved"
assert_contains "moved runs/enforce-risk/c1/1 -> runs/claude-legacy/enforce-risk/c1/1" "$OUT" "moved under the claude.json model"
assert_file_exists "$LEG/runs/default/suggest-risk/c2/1/result.json" "runs without a model land under default"
assert_equal "claude-legacy" "$(json_get "$LEG/runs/claude-legacy/enforce-risk/c1/1/result.json" 'd["model"]')" "model stamped into result.json"
[ -d "$LEG/runs/enforce-risk" ] && _flow_assert_fail "empty legacy arm dir left behind" || _flow_assert_pass "empty legacy arm dirs removed"
OUT=$(python3 "$HELPER" migrate-layout --out "$LEG")
assert_contains '"moved": 0' "$OUT" "migration is idempotent"
OUT=$(python3 "$HELPER" aggregate --out "$LEG")
assert_not_contains "were read from the older" "$(cat "$LEG/summary.md")" "no legacy flag after migration"
assert_contains '"runs": 4' "$OUT" "all four runs still aggregated"

# --- 5. dry-run plan ----------------------------------------------------------
_flow_test_begin "--dry-run: 7 arms x 5 cases x N runs, no claude call"
OUT=$(PATH="$TMP/nobin:$PATH" "$RUNNER" --dry-run --runs 2 --out "$TMP/dry" 2>&1)
EXIT=$?
assert_exit 0 "$EXIT" "dry run exits 0 without claude on PATH"
assert_contains "PLAN  70 run(s): 1 model(s) × 7 arm(s) × 5 case(s)" "$OUT" "70 = 1 × 7 × 5 × 2"
assert_equal "70" "$(printf '%s\n' "$OUT" | grep -c '^RUN   ')" "one RUN line per planned run"
for arm in baseline enforce-risk enforce-norisk suggest-risk suggest-norisk off-risk off-norisk; do
  assert_contains "RUN   default/$arm/money-allocator/2" "$OUT" "arm $arm planned under the default model"
done
for case in $ALL_CASES; do
  assert_contains "RUN   default/baseline/$case/1" "$OUT" "case $case planned"
done
assert_contains "RUN   default/baseline/four-stream-codec/1  model=<cli default>  timeout=1800s  (no plugin)" "$OUT" "baseline has no plugin"
assert_contains 'settings={"testing":{"tddMode":"suggest","tddModeOptOut":true},"specFirst":{"riskMap":false}}' "$OUT" "suggest-norisk two-field opt-out"
assert_contains 'settings={"testing":{"tddMode":"enforce","tddModeOptOut":false},"specFirst":{"riskMap":true}}' "$OUT" "enforce-risk settings"
assert_contains 'settings={"testing":{"tddMode":"off","tddModeOptOut":true},"specFirst":{"riskMap":true}}' "$OUT" "off-risk settings"
assert_contains "--plugin-dir $REPO_ROOT/plugins/flow" "$OUT" "plugin arms load the plugin by absolute path"
assert_contains "--max-turns 60 --max-budget-usd 4" "$OUT" "defaults: 60 turns, \$4 per run"
assert_contains "--permission-mode acceptEdits --allowedTools Bash,Read,Write,Edit,Glob,Grep,Skill,Agent,TodoWrite,TaskCreate,TaskList,TaskUpdate,TaskGet" "$OUT" "allowed tools from prompt.md"
assert_contains "-u CLAUDECODE -u CLAUDE_CODE_SESSION_ID" "$OUT" "session identity vars stripped"
assert_contains "-u PYTHONSAFEPATH" "$OUT" "PYTHONSAFEPATH stripped so the child can import tests from the project root"
assert_contains "-u CLAUDE_CODE_ENTRYPOINT" "$OUT" "entrypoint stripped"
assert_not_contains "--model " "$OUT" "no model hardcoded"
assert_contains "total cap=\$250" "$OUT" "default total cap"
assert_contains "models=default" "$OUT" "plan line names the model directory"
assert_contains "> runs/default/baseline/four-stream-codec/1/stream.jsonl" "$OUT" "stream path uses the model layout"
BASELINE_LINE=$(printf '%s\n' "$OUT" | grep -A1 '^RUN   default/baseline/four-stream-codec/1' | tail -1)
assert_not_contains "--plugin-dir" "$BASELINE_LINE" "baseline command has no --plugin-dir"
[ -d "$TMP/dry" ] && _flow_assert_fail "dry run left $TMP/dry behind" || _flow_assert_pass "dry run leaves no output dir"

_flow_test_begin "--dry-run: --models runs the plan once per model, model × arm × case × run"
OUT=$("$RUNNER" --dry-run --models "model-a, model-b" --arm baseline,off-risk --case money-allocator,interval-algebra --runs 2 --out "$TMP/dry2" 2>&1)
assert_exit 0 "$?" "two-model dry run exits 0"
assert_contains "PLAN  16 run(s): 2 model(s) × 2 arm(s) × 2 case(s)" "$OUT" "16 = 2 × 2 × 2 × 2"
assert_equal "16" "$(printf '%s\n' "$OUT" | grep -c '^RUN   ')" "one RUN line per model × arm × case × run"
assert_equal "8" "$(printf '%s\n' "$OUT" | grep -c '^RUN   model-a/')" "eight runs on model-a"
assert_equal "8" "$(printf '%s\n' "$OUT" | grep -c '^RUN   model-b/')" "eight runs on model-b"
assert_contains "RUN   model-b/off-risk/interval-algebra/2  model=model-b" "$OUT" "second model's last run planned"
assert_equal "8" "$(printf '%s\n' "$OUT" | grep -c -- '--model model-a')" "--model model-a on every model-a command"
assert_contains "models=model-a model-b" "$OUT" "plan line lists both models"
FIRST_B=$(printf '%s\n' "$OUT" | grep -n '^RUN   model-b/' | head -1 | cut -d: -f1)
LAST_A=$(printf '%s\n' "$OUT" | grep -n '^RUN   model-a/' | tail -1 | cut -d: -f1)
[ "$LAST_A" -lt "$FIRST_B" ] && _flow_assert_pass "models run sequentially (all model-a before model-b)" || _flow_assert_fail "model runs interleaved"
OUT=$("$RUNNER" --dry-run --model "org/model-c" --arm baseline --case money-allocator --runs 1 --out "$TMP/dry3" 2>&1)
assert_contains "RUN   org_model-c/baseline/money-allocator/1  model=org/model-c" "$OUT" "slash in the model name is replaced in the directory only"
ERR=$("$RUNNER" --dry-run --model a --models a,b 2>&1 >/dev/null); EXIT=$?
assert_exit 1 "$EXIT" "--model with --models -> exit 1"
assert_contains "either --model or --models" "$ERR" "names the conflict"

_flow_test_begin "--dry-run: a relative --out is resolved to an absolute path"
OUT=$(cd "$TMP" && "$RUNNER" --dry-run --arm baseline --case money-allocator --runs 1 --out rel-out 2>&1)
assert_match 'PLAN  out=/' "$OUT" "plan prints an absolute out dir for a relative --out"
assert_contains "$TMP/rel-out" "$OUT" "the absolute path is the caller's cwd plus the relative --out"

_flow_test_begin "--dry-run: filters, model passthrough and resume skip"
OUT=$("$RUNNER" --dry-run --arm baseline,off-risk --case money-allocator --runs 1 --model my-model --max-turns 9 --out "$TMP/dry5" 2>&1)
assert_contains "PLAN  2 run(s): 1 model(s) × 2 arm(s) × 1 case(s)" "$OUT" "filters narrow the plan"
assert_contains "--model my-model" "$OUT" "explicit model passed through"
assert_contains "RUN   my-model/baseline/money-allocator/1" "$OUT" "runs keyed by the requested model"
assert_contains "--max-turns 9" "$OUT" "explicit max-turns overrides prompt.md"
mkdir -p "$TMP/dry6/runs/default/baseline/money-allocator/1" && echo '{}' > "$TMP/dry6/runs/default/baseline/money-allocator/1/result.json"
OUT=$("$RUNNER" --dry-run --arm baseline --case money-allocator --runs 2 --out "$TMP/dry6" 2>&1)
assert_contains "SKIP  default/baseline/money-allocator/1 (result.json exists)" "$OUT" "completed run skipped on resume"
assert_contains "RUN   default/baseline/money-allocator/2" "$OUT" "remaining run still planned"
assert_contains "1 already complete" "$OUT" "plan line counts skips"
mkdir -p "$TMP/dry7/runs/m1/baseline/money-allocator/1" && echo '{}' > "$TMP/dry7/runs/m1/baseline/money-allocator/1/result.json"
OUT=$("$RUNNER" --dry-run --models m1,m2 --arm baseline --case money-allocator --runs 1 --out "$TMP/dry7" 2>&1)
assert_contains "SKIP  m1/baseline/money-allocator/1" "$OUT" "resume is per model"
assert_contains "RUN   m2/baseline/money-allocator/1" "$OUT" "other model's run still planned"

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
ERR=$("$RUNNER" --models "" --dry-run 2>&1 >/dev/null); EXIT=$?
assert_exit 1 "$EXIT" "empty --models -> exit 1"

# --- 6. hidden suites vs reference and traps ---------------------------------
_flow_test_begin "check-cases: reference passes, every trap variant fails its listed tests"
OUT=$("$RUNNER" --check-cases 2>&1); EXIT=$?
assert_exit 0 "$EXIT" "check-cases exits 0"
assert_contains '"problems": []' "$OUT" "no problems reported"
for case in $ALL_CASES; do
  assert_contains "\"$case\"" "$OUT" "case $case checked"
done
assert_contains '"reference": "25/25"' "$OUT" "four-stream/allocator reference 25/25"
assert_contains '"reference": "23/23"' "$OUT" "limiter reference 23/23"
assert_equal "2" "$(printf '%s\n' "$OUT" | grep -c '"reference": "30/30"')" "both new cases' references pass 30/30"

_flow_test_begin "hidden-run: trap variants are caught, reference is not"
OUT=$(python3 "$HELPER" hidden-run --case-dir "$EVALS/four-stream-codec" --impl "$EVALS/four-stream-codec/hidden/traps/transposed_order.py")
assert_contains '"all_pass": false' "$OUT" "transposed variant fails"
TRAPPED=$(printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["traps"]["transposed_order"]["caught"], d["traps"]["ceil_split"]["caught"])')
assert_equal "True False" "$TRAPPED" "signature match: transposed flagged, ceil_split (shares one test) not"
OUT=$(python3 "$HELPER" hidden-run --case-dir "$EVALS/money-allocator" --impl "$EVALS/money-allocator/hidden/reference_impl.py")
assert_contains '"all_pass": true' "$OUT" "allocator reference passes"
assert_contains '"pass_rate": 1.0' "$OUT" "pass rate 1.0"

_flow_test_begin "hidden-run: new cases' references pass and every variant fails"
for case in $NEW_CASES; do
  OUT=$(python3 "$HELPER" hidden-run --case-dir "$EVALS/$case" --impl "$EVALS/$case/hidden/reference_impl.py")
  assert_contains '"all_pass": true' "$OUT" "$case reference passes"
  assert_contains '"total": 30' "$OUT" "$case has 30 hidden tests"
  for variant in "$EVALS/$case"/hidden/traps/*.py; do
    name=$(basename "$variant" .py)
    OUT=$(python3 "$HELPER" hidden-run --case-dir "$EVALS/$case" --impl "$variant")
    assert_contains '"all_pass": false' "$OUT" "$case/$name fails the hidden suite"
    CAUGHT=$(printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["traps"]["'"$name"'"]["caught"])')
    assert_equal "True" "$CAUGHT" "$case/$name matches its own signature"
  done
done

_flow_test_begin "hidden-run: missing module scores zero over the full suite"
mkdir -p "$TMP/nomod"
OUT=$(python3 "$HELPER" hidden-run --case-dir "$EVALS/sliding-window-limiter" --project-dir "$TMP/nomod")
assert_contains '"import_or_crash": true' "$OUT" "import failure flagged"
assert_contains '"total": 23' "$OUT" "total taken from the suite size"
assert_contains '"passed": 0' "$OUT" "zero passed"

_flow_test_begin "trap count and test count per case are within the brief"
for case in $OLD_CASES; do
  N=$(grep -c '    def test_' "$EVALS/$case/hidden/test_hidden.py")
  [ "$N" -ge 12 ] && [ "$N" -le 25 ] && _flow_assert_pass "$case has $N hidden tests (12-25)" || _flow_assert_fail "$case has $N hidden tests"
  T=$(ls "$EVALS/$case/hidden/traps/"*.py | wc -l | tr -d ' ')
  [ "$T" -ge 5 ] && _flow_assert_pass "$case has $T trap variants" || _flow_assert_fail "$case has only $T trap variants"
done
for case in $NEW_CASES; do
  N=$(grep -c '    def test_' "$EVALS/$case/hidden/test_hidden.py")
  [ "$N" -ge 15 ] && [ "$N" -le 30 ] && _flow_assert_pass "$case has $N hidden tests (15-30)" || _flow_assert_fail "$case has $N hidden tests"
  T=$(ls "$EVALS/$case/hidden/traps/"*.py | wc -l | tr -d ' ')
  [ "$T" -ge 8 ] && _flow_assert_pass "$case has $T trap variants" || _flow_assert_fail "$case has only $T trap variants"
done

# --- 7. case layout (official `claude plugin eval` shape) ----------------------
_flow_test_begin "case layout: prompt.md frontmatter, graders, scaffold, hidden, expected"
for case in $ALL_CASES; do
  D="$EVALS/$case"
  for f in prompt.md expected.md graders/module-exists.md graders/completion-phrase.md scaffold/ISSUE.md scaffold/tests/__init__.py hidden/test_hidden.py hidden/reference_impl.py hidden/traps.json; do
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
  assert_contains "path: \"$MODULE.py\"" "$(cat "$D/graders/module-exists.md")" "$case file_exists grader names the module"
  assert_contains "raise NotImplementedError" "$(cat "$D/scaffold/$MODULE.py")" "$case skeleton bodies raise"
  assert_contains "starting" "$(cat "$D/scaffold/ISSUE.md")" "$case ISSUE.md says the skeleton is the starting point"
  AC=$(grep -c '^- \[ \] .* — verify: `' "$D/scaffold/ISSUE.md")
  [ "$AC" -ge 4 ] && [ "$AC" -le 6 ] && _flow_assert_pass "$case has $AC acceptance criteria with commands" || _flow_assert_fail "$case has $AC acceptance criteria"
  assert_contains "## Acceptance Criteria" "$(cat "$D/scaffold/ISSUE.md")" "$case AC heading"
  assert_contains "python3 -m unittest discover -s tests -t . -v" "$(cat "$D/scaffold/ISSUE.md")" "$case names the discover command own-test scoring reuses"
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
for case in $ALL_CASES; do
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

_flow_test_begin "new cases record their baseline calibration in expected.md and clear the bar"
for case in $NEW_CASES; do
  EXP=$(cat "$EVALS/$case/expected.md")
  assert_contains "## Calibration" "$EXP" "$case expected.md has a calibration section"
  assert_contains "| Run | Hidden pass rate |" "$EXP" "$case calibration table present"
  assert_contains "Bar (the baseline fails at least one hidden test in at least one of three runs): **cleared**" "$EXP" "$case clears the bar"
  N=$(printf '%s\n' "$EXP" | grep -c '^| [0-9] | [0-9]*/30 ')
  [ "$N" -ge 3 ] && _flow_assert_pass "$case records $N calibration runs" || _flow_assert_fail "$case records only $N calibration runs"
done

# --- 8. references doc ----------------------------------------------------------
_flow_test_begin "references/correctness-eval.md documents the harness"
DOC=$(cat "$REPO_ROOT/plugins/flow/references/correctness-eval.md")
assert_contains "flow-eval-run.sh" "$DOC" "names the runner"
assert_contains "summary.md" "$DOC" "explains summary.md"
assert_contains "tddMode" "$DOC" "states the decision rule on tddMode"
assert_contains "run-to-run spread" "$DOC" "defines the spread"
assert_contains "## Limitations" "$DOC" "has a limitations section"
assert_contains "test_hidden.py" "$DOC" "names the hidden suite"
assert_contains "own-test-traps.json" "$DOC" "documents the own-test trap record"
assert_contains "secondary" "$DOC" "documents the secondary signal"
assert_contains "--models" "$DOC" "documents --models"
assert_contains "migrate-layout" "$DOC" "documents the one-off migration"
assert_contains "runs/<model>/<arm>/<case>/<n>" "$DOC" "documents the model-keyed layout"
for case in $NEW_CASES; do
  assert_contains "\`$case\`" "$DOC" "case table lists $case"
done
