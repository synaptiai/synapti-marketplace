# shellcheck shell=bash
# End-to-end: the harness that measures whether a System One answer to "would
# this test fail if the module were the risk row's plausible wrong version?"
# agrees with what the correctness eval observed. It runs the shipped scripts
# (bin/flow-test-state.sh, bin/flow-s1-eval.sh) in a scratch repository: the
# pair export over the real cases and a fixture agent run, the replay through
# bin/flow-s1.sh against a stub provider (tests/lib/s1_stub.py), and the
# scorer on records with hand-chosen answers. No real provider is called.
#
# Ways it can be wrong, written down before the scenarios:
#   D1  the state builder drops the class setUp or a helper the test calls, or
#       cuts the test function itself to fit the size cap
#   D2  a state carries the answer: the trap description or expected.md
#       columns 3-4, a discriminating hidden test name other than its own,
#       or (author states) a comment naming the trap
#   D3  every discovered agent test becomes a pair, including one that fails
#       on the reference, so it "catches" every trap
#   D4  a label is two-valued: a test the run never reached is labelled pass
#   D5  a failing list cut at the 50-entry cap is read as complete
#   D6  a run whose re-run oracle set differs from the stored one is used
#   D7  records are joined to pairs by order or by state_sha256, so two pairs
#       with the same state collapse or swap labels
#   D8  the flag is read in the wrong direction (true read as "weak test")
#   D9  a no-answer record (timeout, 429) is scored as "won't fail"
#   D10 records missing, extra or duplicated pass silently
#   D11 a constant predictor (p=0.01 or p=0.99 everywhere) clears the bar,
#       or all p=0.5 is read as a result
#   D12 the threshold is chosen on the set it is judged on, or after the
#       evaluation records were written
#   D13 the replay sends anything when the first call wrote no record
#       (settings refused, provider none)
#   D14 an HTTP 429 is not retried, or is retried more than once
#   D15 the Wilson bound is computed wrongly: 0 of 73 must be within 5%,
#       0 of 72 must not
#   D16 a confident, correct provider on a set that is mostly pass is called
#       degenerate because most of all answers sit in one bin
#   D17 the permutation check pools AUC over traps, so a correct scorer
#       fails it whenever p differs between traps
#   D18 the placebo check judges a per-stratum AUC, so a provider whose
#       pooled placebo AUC is 0.5 is called inconclusive
#
# FLOW_E2E_SCENARIOS=a,b runs only the named scenarios.

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

DS_EVALS="$REPO_ROOT/plugins/flow/evals"
DS_HELPER="$REPO_ROOT/plugins/flow/bin/_flow_eval.py"

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

_setup() {
  if [ -n "${CI:-}" ]; then
    { printf 'progress %s %s\n' "$(date -u +%H:%M:%S)" "$1" >&3; } 2>/dev/null
  fi
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo feature/s1-discrimination
}

# _py <python source> [args] — a check computed outside the code under test.
_py() {
  local src="$1"; shift
  python3 -c 'import os, sys; sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and not (os.path.isdir(p) and os.access(os.curdir, os.X_OK) and os.path.samefile(p, os.curdir))]; src = sys.argv[1]; sys.argv = sys.argv[1:]; exec(src)' "$src" "$@"
}

# _agent_run <dir> — a correctness-eval run directory on money-allocator:
# project/ holds an agent module (the reference, except that it accepts a
# float amount) and an own suite, and own-test-traps.json is written by the
# eval's own scorer, so every label below comes from the code the
# correctness eval used, not from the code under test.
_agent_run() {
  local run="$1" case="$DS_EVALS/money-allocator"
  mkdir -p "$run/project/tests"
  cp "$case/scaffold/ISSUE.md" "$run/project/ISSUE.md"
  : > "$run/project/tests/__init__.py"
  _py 'import sys
s = open(sys.argv[1]).read()
old = "    if isinstance(value, bool) or isinstance(value, float):\n"
new = "    if isinstance(value, float):\n        return Decimal(str(value))\n    if isinstance(value, bool):\n"
assert old in s
open(sys.argv[2], "w").write(s.replace(old, new))' "$case/hidden/reference_impl.py" "$run/project/allocate.py"
  cat > "$run/project/tests/helpers.py" <<'EOF'
from decimal import Decimal


def total(xs):
    return sum(xs, Decimal(0))
EOF
  cat > "$run/project/tests/test_allocate.py" <<'EOF'
import unittest
from decimal import Decimal

from allocate import allocate
from tests.helpers import total


def D(*xs):
    return [Decimal(x) for x in xs]


def unrelated_helper():
    return "UNRELATED-HELPER-TEXT"


class KnownAnswers(unittest.TestCase):
    places = 2

    def setUp(self):
        self.weights = [1, 1, 1]

    def test_tie_goes_to_first(self):
        # COMMENT-MARKER: the leftover cent on a three-way tie goes to index 0
        self.assertEqual(allocate("100.00", self.weights, self.places), D("33.34", "33.33", "33.33"))

    def test_places_zero(self):
        self.assertEqual(allocate("10", [1, 1, 1], places=0), D("4", "3", "3"))

    def test_single_weight(self):
        self.assertEqual(allocate("5.00", [3]), D("5.00"))

    def test_float_amount_accepted(self):
        self.assertEqual(allocate(1.5, [1]), D("1.50"))

    def test_sum_is_amount(self):
        self.assertEqual(total(allocate("1.00", [1, 2, 3])), Decimal("1.00"))

    def test_zero_weight_rejected(self):
        with self.assertRaises(ValueError):
            allocate("1.00", [1, 0])
EOF
  python3 "$DS_HELPER" own-test-traps --case-dir "$case" --project-dir "$run/project" \
    --out "$run/own-test-traps.json" >/dev/null 2>&1
  printf '{"case": "money-allocator", "arm": "baseline", "run": 1, "model": "claude-sonnet-5"}\n' > "$run/result.json"
}

# ---------------------------------------------------------------- state builder
if _want state-builder; then
  _setup state-builder "the shared state builder takes the test whole with its setUp, class attributes and same-file helpers, marks a helper from another file, strips comments on request and renames on request"
  _agent_run "$E2E_DIR/runA/runs/claude-sonnet-5/baseline/money-allocator/1"
  DS_P="$E2E_DIR/runA/runs/claude-sonnet-5/baseline/money-allocator/1/project"
  e2e_run_bin bin/flow-test-state.sh --test-file "$DS_P/tests/test_allocate.py" \
    --test-id tests.test_allocate.KnownAnswers.test_tie_goes_to_first \
    --area "ties last first" --wrong-version "Remainder ties go to the highest index" \
    --spec-file "$DS_P/ISSUE.md" --meta "$E2E_DIR/meta.json"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  printf '%s' "$E2E_OUT" > "$E2E_DIR/state.json"
  DS_SRC=$(_py 'import json,sys; print(json.load(open(sys.argv[1]))["test"]["source"])' "$E2E_DIR/state.json")
  e2e_expect_equal "tests.test_allocate.KnownAnswers.test_tie_goes_to_first" \
    "$(_py 'import json,sys; print(json.load(open(sys.argv[1]))["test"]["id"])' "$E2E_DIR/state.json")" "test.id"
  e2e_expect_equal "ties last first|Remainder ties go to the highest index" \
    "$(_py 'import json,sys; r=json.load(open(sys.argv[1]))["risk"]; print(r["area"]+"|"+r["plausible_wrong_version"])' "$E2E_DIR/state.json")" "risk row"
  e2e_expect_equal "$(cat "$DS_P/ISSUE.md")" "$(_py 'import json,sys; print(json.load(open(sys.argv[1]))["spec"])' "$E2E_DIR/state.json")" "spec is ISSUE.md as written"
  for DS_WANT in "import unittest" "from allocate import allocate" "def test_tie_goes_to_first(self):" "D(\"33.34\", \"33.33\", \"33.33\")" "def setUp(self):" "places = 2" "def D(*xs):" "# COMMENT-MARKER"; do
    case "$DS_SRC" in *"$DS_WANT"*) _e2e_result pass "test.source has: $DS_WANT" ;; *) _e2e_result fail "test.source has: $DS_WANT" ;; esac
  done
  for DS_NOT in "UNRELATED-HELPER-TEXT" "def test_places_zero" "def total"; do
    case "$DS_SRC" in *"$DS_NOT"*) _e2e_result fail "test.source lacks: $DS_NOT" ;; *) _e2e_result pass "test.source lacks: $DS_NOT" ;; esac
  done
  e2e_expect_equal "False" "$(_py 'import json,sys; print(json.load(open(sys.argv[1]))["helpers_missing"])' "$E2E_DIR/meta.json")" "helpers_missing for a test with same-file helpers only"
  e2e_expect_equal "risk,spec,test" "$(_py 'import json,sys; print(",".join(sorted(json.load(open(sys.argv[1])))))' "$E2E_DIR/state.json")" "top-level keys of the state (nothing else is sent)"

  e2e_run_bin bin/flow-test-state.sh --test-file "$DS_P/tests/test_allocate.py" \
    --test-id KnownAnswers.test_sum_is_amount --area a --wrong-version w --spec-file "$DS_P/ISSUE.md" --meta "$E2E_DIR/meta2.json"
  e2e_expect_equal 0 "$E2E_RC" "exit status (Class.method id)"
  e2e_expect_equal "True" "$(_py 'import json,sys; print(json.load(open(sys.argv[1]))["helpers_missing"])' "$E2E_DIR/meta2.json")" "helpers_missing for a test calling a helper imported from another file"

  e2e_run_bin bin/flow-test-state.sh --test-file "$DS_P/tests/test_allocate.py" \
    --test-id test_tie_goes_to_first --area a --wrong-version w --spec-file "$DS_P/ISSUE.md" --strip-comments --rename-test test_x
  e2e_expect_equal 0 "$E2E_RC" "exit status (strip and rename)"
  e2e_expect_no_out "COMMENT-MARKER"
  e2e_expect_no_out "test_tie_goes_to_first"
  e2e_expect_out "def test_x(self):"
  e2e_expect_out "33.34"

  e2e_run_bin bin/flow-test-state.sh --test-file "$DS_P/tests/test_allocate.py" \
    --test-id KnownAnswers.test_missing --area a --wrong-version w --spec-file "$DS_P/ISSUE.md"
  e2e_expect_equal 2 "$E2E_RC" "exit status for a test that is not in the file"

  # Methods of the test's class that the test (or setUp) reaches through self,
  # and the methods those reach, are part of what the test runs.
  cat > "$E2E_DIR/self_test.py" <<'EOF'
import unittest


def module_helper(x):
    return x


class T(unittest.TestCase):
    def setUp(self):
        self.v = self._make()

    def _make(self):
        return "MAKE-BODY"

    def _check(self, x):
        self.assertEqual(self._inner(x), module_helper(x))

    def _inner(self, x):
        return "INNER-BODY" and x

    def _unused(self):
        return "UNUSED-METHOD-TEXT"

    def test_it(self):
        self._check(self.v)
EOF
  e2e_run_bin bin/flow-test-state.sh --test-file "$E2E_DIR/self_test.py" --test-id T.test_it --area a \
    --wrong-version w --spec-file "$DS_P/ISSUE.md" --meta "$E2E_DIR/meta3.json"
  e2e_expect_equal 0 "$E2E_RC" "exit status (methods reached through self)"
  e2e_expect_out "MAKE-BODY"
  e2e_expect_out "def _check(self, x):"
  e2e_expect_out "INNER-BODY"
  e2e_expect_out "def module_helper(x):"
  e2e_expect_no_out "UNUSED-METHOD-TEXT"
  e2e_expect_equal "False" "$(_py 'import json,sys; print(json.load(open(sys.argv[1]))["helpers_missing"])' "$E2E_DIR/meta3.json")" "helpers_missing when every method the test reaches is included"

  # A helper larger than the cap: the test function stays whole, the state's
  # test.source is at most 12 KB.
  python3 - "$E2E_DIR/big_test.py" <<'PY'
import os, sys
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p)]
body = "\n".join("    x%d = %d" % (i, i) for i in range(1500))
with open(sys.argv[1], "w") as f:
    f.write("import unittest\n\n\ndef big():\n" + body + "\n    return 1\n\n\nclass T(unittest.TestCase):\n"
            "    def test_big(self):\n        # KEEP-WHOLE-START\n        self.assertEqual(big(), 1)\n        # KEEP-WHOLE-END\n")
PY
  e2e_run_bin bin/flow-test-state.sh --test-file "$E2E_DIR/big_test.py" --test-id T.test_big --area a --wrong-version w --spec-file "$DS_P/ISSUE.md"
  e2e_expect_equal 0 "$E2E_RC" "exit status (oversized helper)"
  e2e_expect_out "KEEP-WHOLE-START"
  e2e_expect_out "KEEP-WHOLE-END"
  printf '%s' "$E2E_OUT" > "$E2E_DIR/big.json"
  e2e_expect_equal "True" "$(_py 'import json,sys; print(len(json.load(open(sys.argv[1]))["test"]["source"].encode()) <= 12288)' "$E2E_DIR/big.json")" "test.source within 12 KB"
fi

# ---------------------------------------------------------------- pair export
if _want export; then
  _setup export "the pair export over the four real cases (author stratum) and a fixture agent run: counts from the cases, labels from own-test-traps.json, three-valued labels, no leak, unique refs"
  DS_OUT="$E2E_DIR/runA"
  _agent_run "$DS_OUT/runs/claude-sonnet-5/baseline/money-allocator/1"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/export" --set dev --author --out "$DS_OUT"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  DS_PAIRS="$E2E_DIR/export/pairs.jsonl"
  DS_TRAPS_JSON="$DS_OUT/runs/claude-sonnet-5/baseline/money-allocator/1/own-test-traps.json"
  # Author counts: tests x traps per case and the failing pairs from
  # traps.json, as counted for the specification (901 pairs, 200 failing).
  e2e_expect_equal "901 200" "$(_py 'import json,sys
ps=[json.loads(l) for l in open(sys.argv[1])]
a=[p for p in ps if p["stratum"]=="author"]
print(len(a), sum(p["label"]=="fail" for p in a))' "$DS_PAIRS")" "author pairs and failing author pairs"
  e2e_expect_equal "four-stream-codec 150 49;interval-algebra 390 69;money-allocator 200 43;sliding-window-limiter 161 39" "$(_py 'import json,sys,collections
ps=[json.loads(l) for l in open(sys.argv[1]) ]
c=collections.defaultdict(lambda:[0,0])
for p in ps:
    if p["stratum"]=="author":
        c[p["case"]][0]+=1; c[p["case"]][1]+=p["label"]=="fail"
print(";".join("%s %d %d"%(k,v[0],v[1]) for k,v in sorted(c.items())))' "$DS_PAIRS")" "author pairs per case"
  # Agent pairs: the oracle tests (own_passing_tests) times 8 traps, each
  # label as own-test-traps.json recorded it.
  e2e_expect_equal "ok" "$(_py 'import json,sys
ps=[json.loads(l) for l in open(sys.argv[1])]
own=json.load(open(sys.argv[2]))
a=[p for p in ps if p["stratum"]=="agent"]
n=own["own_passing_tests"]*len(own["per_trap"])
if len(a)!=n: print("pairs %d != %d"%(len(a),n)); sys.exit()
for p in a:
    t=own["per_trap"][p["trap"]]
    want="fail" if p["test_id"] in t["failing_own_tests"] else ("unobserved" if p["test_id"] in t["unobserved_oracle_tests"] else "pass")
    if p["label"]!=want: print("label %s %s %s != %s"%(p["test_id"],p["trap"],p["label"],want)); sys.exit()
    fails_other=any(p["test_id"] in own["per_trap"][o]["failing_own_tests"] for o in own["per_trap"] if o!=p["trap"])
    want_hn = p["label"]=="pass" and fails_other
    if bool(p["hn_behavioral"])!=want_hn: print("hn %s %s"%(p["test_id"],p["trap"])); sys.exit()
print("ok")' "$DS_PAIRS" "$DS_TRAPS_JSON")" "agent labels and hard-negative flags match own-test-traps.json"
  e2e_expect_equal "0" "$(grep -c 'test_float_amount_accepted' "$DS_PAIRS")" "a test that fails on the reference is not a pair"
  e2e_expect_equal "True" "$(_py 'import json,sys
ps=[json.loads(l) for l in open(sys.argv[1])]
print(any(p["helpers_missing"] for p in ps if p["test_id"].endswith("test_sum_is_amount")))' "$DS_PAIRS")" "helpers_missing carried into the pairs"
  # Held in a variable: bash 3.2 reads the text of a $( ) as shell, and the
  # hash in the ref pattern would start a comment there.
  DS_CHECK_REFS=$(cat <<'PY'
import json, re, sys
refs = [json.loads(l)["ref"] for l in open(sys.argv[1])]
bad = [r for r in refs if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:/#@+-]{0,199}", r)]
print("unique" if len(set(refs)) == len(refs) and not bad else "dup or bad: %r" % bad[:3])
PY
)
  e2e_expect_equal "unique" "$(_py "$DS_CHECK_REFS" "$DS_PAIRS")" "every ref is unique and a valid --ref"
  e2e_expect_equal "ok" "$(_py 'import json,sys,hashlib,os
d=os.path.dirname(sys.argv[1])
for l in open(sys.argv[1]):
    p=json.loads(l)
    for ab,s in p["states"].items():
        b=open(os.path.join(d,s["path"]),"rb").read()
        if hashlib.sha256(b).hexdigest()!=s["sha256"]: print("sha mismatch",p["ref"],ab); sys.exit()
print("ok")' "$DS_PAIRS")" "each state file matches its recorded sha256"
  # Leak guard, computed here from traps.json and expected.md, not from the
  # exporter: no description, no other discriminating test name, and in an
  # author state no trap name in any spelling and no word "trap".
  e2e_expect_equal "no leak" "$(_py 'import json,sys,os,re
d=os.path.dirname(sys.argv[1]); ev=sys.argv[2]
cases={}
for c in os.listdir(ev):
    tj=os.path.join(ev,c,"hidden","traps.json")
    if os.path.isfile(tj): cases[c]=json.load(open(tj))["traps"]
bad=[]
for l in open(sys.argv[1]):
    p=json.loads(l)
    for ab,s in p["states"].items():
        st=json.load(open(os.path.join(d,s["path"])))
        own=st["test"]["id"].rsplit(".",1)[-1]
        text=json.dumps(st)
        src=st["test"]["source"]
        for c,traps in cases.items():
            for name,t in traps.items():
                if t["description"] in text: bad.append((p["ref"],ab,"description"))
                for dt in t["discriminating_tests"]:
                    if dt!=own and re.search(r"\b%s\b"%re.escape(dt), text): bad.append((p["ref"],ab,dt))
                if p["stratum"]=="author":
                    for sp in (name, name.replace("_","-"), name.replace("_"," ")):
                        if sp in src: bad.append((p["ref"],ab,"trap name "+sp))
        if p["stratum"]=="author" and re.search(r"trap", src, re.I): bad.append((p["ref"],ab,"word trap"))
print("no leak" if not bad else repr(bad[:5]))' "$DS_PAIRS" "$DS_EVALS")" "no state carries the answer"
  e2e_expect_equal "column 2" "$(_py 'import json,sys,os
d=os.path.dirname(sys.argv[1])
for l in open(sys.argv[1]):
    p=json.loads(l)
    if p["case"]=="money-allocator" and p["trap"]=="ties_last_first":
        st=json.load(open(os.path.join(d,p["states"]["real"]["path"])))
        print("column 2" if st["risk"]=={"area":"ties last first","plausible_wrong_version":"Remainder ties go to the highest index"} else st["risk"]); break' "$DS_PAIRS")" "risk row is the trap name and expected.md column 2"
  e2e_expect_equal "ok" "$(_py 'import json,sys,os
d=os.path.dirname(sys.argv[1])
for l in open(sys.argv[1]):
    p=json.loads(l)
    real=json.load(open(os.path.join(d,p["states"]["real"]["path"])))
    ns=json.load(open(os.path.join(d,p["states"]["name-stripped"]["path"])))
    sh=json.load(open(os.path.join(d,p["states"]["shuffled"]["path"])))
    name=real["test"]["id"].rsplit(".",1)[-1]
    if ns["test"]["source"]!=real["test"]["source"].replace("def %s("%name,"def test_x(",1) or not ns["test"]["id"].endswith(".test_x") and ns["test"]["id"]!="test_x": print("name-stripped",p["ref"]); sys.exit()
    if ns["spec"]!=real["spec"] or ns["risk"]!=real["risk"]: print("name-stripped changed more",p["ref"]); sys.exit()
    if sh["test"]!=real["test"] or sh["spec"]!=real["spec"] or p["states"]["shuffled"]["placebo_case"]==p["case"]: print("shuffled",p["ref"]); sys.exit()
print("ok")' "$DS_PAIRS")" "the name-stripped state differs only in the test name, the shuffled one only in a risk row from another case"
  e2e_expect_equal "True" "$(_py 'import json,sys
ps=[json.loads(l) for l in open(sys.argv[1])]
print(all(p["comments_stripped"]==(p["stratum"]=="author") for p in ps))' "$DS_PAIRS")" "comments stripped in author states only"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/export2" --set dev --author --out "$DS_OUT"
  e2e_expect_equal "$(cat "$E2E_DIR/export/pairs.jsonl")" "$(cat "$E2E_DIR/export2/pairs.jsonl")" "a second export writes the same pairs (seeded)"
fi

# ------------------------------------------------- export refusals and labels
if _want export-guards; then
  _setup export-guards "a cut failing list is refused unless re-scored, an unobserved test is labelled unobserved, and a run whose oracle set differs is excluded"
  DS_OUT="$E2E_DIR/runA"
  DS_RUN="$DS_OUT/runs/claude-sonnet-5/baseline/money-allocator/1"
  _agent_run "$DS_RUN"
  cp "$DS_RUN/own-test-traps.json" "$E2E_DIR/own.orig.json"
  # A failing count above its stored list: the list was cut at 50.
  _py 'import json,sys
d=json.load(open(sys.argv[1]))
t=next(n for n,v in sorted(d["per_trap"].items()) if v["failing_own_tests"])
d["per_trap"][t]["failing_count"]=60
json.dump(d,open(sys.argv[1],"w"))' "$DS_RUN/own-test-traps.json"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x1" --set dev --out "$DS_OUT"
  e2e_expect_equal 2 "$E2E_RC" "exit status for a cut failing list"
  e2e_expect_err "failing_count"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x2" --set dev --out "$DS_OUT" --rescore
  e2e_expect_equal 0 "$E2E_RC" "exit status with --rescore"
  e2e_expect_equal "$(_py 'import json,sys; d=json.load(open(sys.argv[1])); print(d["own_passing_tests"]*len(d["per_trap"]))' "$E2E_DIR/own.orig.json")" \
    "$(wc -l < "$E2E_DIR/x2/pairs.jsonl" | tr -d ' ')" "pairs after re-scoring the run"

  # One failing test moved to the unobserved list: its pair is unobserved.
  _py 'import json,sys
d=json.load(open(sys.argv[1]))
t=next(n for n,v in sorted(d["per_trap"].items()) if v["failing_own_tests"])
v=d["per_trap"][t]; x=v["failing_own_tests"].pop(0); v["failing_count"]-=1
v["unobserved_oracle_tests"].append(x); v["unobserved_count"]+=1
json.dump(d,open(sys.argv[1],"w")); print(t+"|"+x)' "$E2E_DIR/own.orig.json" > "$E2E_DIR/moved.txt"
  cp "$E2E_DIR/own.orig.json" "$DS_RUN/own-test-traps.json"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x3" --set dev --out "$DS_OUT"
  e2e_expect_equal 0 "$E2E_RC" "exit status with one unobserved test"
  e2e_expect_equal "unobserved" "$(_py 'import json,sys
t,x=open(sys.argv[2]).read().strip().split("|")
for l in open(sys.argv[1]):
    p=json.loads(l)
    if p["trap"]==t and p["test_id"]==x: print(p["label"])' "$E2E_DIR/x3/pairs.jsonl" "$E2E_DIR/moved.txt")" "label of the unobserved pair"
  e2e_expect_equal "1" "$(_py 'import json,sys; print(json.load(open(sys.argv[1]))["labels"]["unobserved"])' "$E2E_DIR/x3/export.json")" "unobserved count in export.json"

  # A stored oracle count that the re-run does not reproduce: run excluded.
  _py 'import json,sys
d=json.load(open(sys.argv[1])); d["own_passing_tests"]=99; json.dump(d,open(sys.argv[1],"w"))' "$DS_RUN/own-test-traps.json"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x4" --set dev --out "$DS_OUT"
  e2e_expect_equal 0 "$E2E_RC" "exit status with an excluded run"
  e2e_expect_equal "0" "$(wc -l < "$E2E_DIR/x4/pairs.jsonl" | tr -d ' ')" "pairs from the excluded run"
  e2e_expect_equal "True" "$(_py 'import json,sys
e=json.load(open(sys.argv[1]))["excluded_runs"]
print(len(e)==1 and "oracle" in e[0]["reason"])' "$E2E_DIR/x4/export.json")" "the run is listed as excluded, with the oracle reason"

  # A stored failing count below its list: the fail pairs (one per listed
  # test) no longer sum to the stored counts, so the run is left out.
  _py 'import json,sys
d=json.load(open(sys.argv[1]))
t=next(n for n,v in sorted(d["per_trap"].items()) if v["failing_own_tests"])
d["per_trap"][t]["failing_count"]-=1
json.dump(d,open(sys.argv[2],"w"))' "$E2E_DIR/own.orig.json" "$DS_RUN/own-test-traps.json"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x6" --set dev --out "$DS_OUT"
  e2e_expect_equal 0 "$E2E_RC" "exit status with fail pairs that do not match the stored counts"
  e2e_expect_equal "0 0" "$(wc -l < "$E2E_DIR/x6/pairs.jsonl" | tr -d ' ') $(find "$E2E_DIR/x6/states" -type f | wc -l | tr -d ' ')" "pairs and state files from that run"
  e2e_expect_equal "True" "$(_py 'import json,sys
e=json.load(open(sys.argv[1]))["excluded_runs"]
print(len(e)==1 and "failing counts" in e[0]["reason"])' "$E2E_DIR/x6/export.json")" "the run is listed as excluded, with the fail-count reason"

  # A run that started and wrote no result.json gives no pairs and is listed.
  mkdir -p "$DS_OUT/runs/claude-sonnet-5/baseline/money-allocator/2"
  printf 'prompt\n' > "$DS_OUT/runs/claude-sonnet-5/baseline/money-allocator/2/prompt.txt"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x5" --set dev --out "$DS_OUT"
  e2e_expect_equal 0 "$E2E_RC" "exit status with an unfinished run"
  e2e_expect_equal "True" "$(_py 'import json,sys
u=json.load(open(sys.argv[1]))["unfinished_runs"]
print(len(u)==1 and u[0].endswith("money-allocator/2 (started, no result.json)"))' "$E2E_DIR/x5/export.json")" "the unfinished run is listed"
fi

# ------------------------------------------------------------- replay (stub)
# The replay runs from the scratch repository; its scratch plugin copy and
# working directory go under the scenario directory, outside the repository.
_replay_setup() {
  _setup "$1" "$2"
  DS_OUT="$E2E_DIR/runA"
  _agent_run "$DS_OUT/runs/claude-sonnet-5/baseline/money-allocator/1"
  python3 "$DS_HELPER" s1-pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/export" --set dev --out "$DS_OUT" >/dev/null 2>&1 \
    || _flow_assert_fail "$E2E_NAME: export for the replay failed"
  DS_PAIRS="$E2E_DIR/export/pairs.jsonl"
  DS_LABELLED=$(_py 'import json,sys; print(sum(json.loads(l)["label"]!="unobserved" for l in open(sys.argv[1])))' "$DS_PAIRS")
}
_provider_settings() {
  printf '{"systemOne":{"provider":"custom","baseUrl":"%s","model":"jev-1.13.0","timeoutMs":5000,"uses":{"verify.discrimination":"shadow"}}}\n' "$1" > "$E2E_DIR/provider.json"
}

if _want replay; then
  _replay_setup replay "every labelled pair is sent once through flow-s1.sh in shadow, with its ref and label, to the provider the settings file names; the stub answers by state"
  e2e_stub_start ts '{"rules":[{"contains":"test_tie_goes_to_first","body":{"model":"jev-1.13.0","answers":{"test_catches_wrong":{"type":"noul","noul":0.97}}}}],"body":{"model":"jev-1.13.0","answers":{"test_catches_wrong":{"type":"noul","noul":0.03}}}}'
  _provider_settings "$(e2e_stub_url ts)"
  e2e_run_bin bin/flow-s1-eval.sh replay --pairs "$DS_PAIRS" --records "$E2E_DIR/records" \
    --provider-settings "$E2E_DIR/provider.json" --scratch "$E2E_DIR/replay-scratch" --workers 4
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "$DS_LABELLED" "$(e2e_stub_requests ts)" "requests (one per labelled pair)"
  e2e_expect_equal "ok" "$(_py 'import json,sys
ps={}
for l in open(sys.argv[1]):
    p=json.loads(l)
    if p["label"]!="unobserved": ps[p["ref"]]=p
recs=[json.loads(l) for l in open(sys.argv[2])]
if sorted(r["ref"] for r in recs)!=sorted(ps): print("refs differ"); sys.exit()
for r in recs:
    p=ps[r["ref"]]
    if r["site"]!="verify.discrimination" or r["mode"]!="shadow" or r["current"]!=p["label"] or r["state_sha256"]!=p["states"]["real"]["sha256"]:
        print("bad record",r); sys.exit()
    want=0.97 if p["test_id"].endswith("test_tie_goes_to_first") else 0.03
    if r["answer"]["p"]!=want: print("p",r["ref"],r["answer"]["p"]); sys.exit()
print("ok")' "$DS_PAIRS" "$E2E_DIR/records/real/system-one.jsonl")" "records: one per pair, by ref, with its label and state"
  e2e_expect_equal "ok" "$(_py 'import json,sys,yaml
q=yaml.safe_load(open(sys.argv[2]))["sites"]["verify.discrimination"]["questions"]
for l in open(sys.argv[1]):
    b=json.loads(l)["body"]
    if b["questions"]!=q or set(b["state"])!={"spec","risk","test"}: print("bad request"); sys.exit()
print("ok")' "$(e2e_stub_log ts)" "$REPO_ROOT/plugins/flow/evals/s1-discrimination/questions.yaml")" "each request asks the eval question file's question about a three-part state"
  e2e_expect_equal "absent" "$( [ -e "$E2E_REPO/.claude/flow-state" ] || [ -e "$E2E_HOME/.claude/flow-state/system-one.jsonl" ] && echo present || echo absent)" "nothing written to the scenario's own state"

  e2e_run_bin bin/flow-s1-eval.sh replay --pairs "$DS_PAIRS" --records "$E2E_DIR/records" \
    --provider-settings "$E2E_DIR/provider.json" --scratch "$E2E_DIR/replay-scratch2" --ablation name-stripped --limit 3
  e2e_expect_equal 0 "$E2E_RC" "exit status (name-stripped, 3 pairs)"
  e2e_expect_equal "3" "$(wc -l < "$E2E_DIR/records/name-stripped/system-one.jsonl" | tr -d ' ')" "name-stripped records"
  e2e_expect_equal "True" "$(_py 'import json,sys
ls=[json.loads(l)["body"]["state"]["test"]["source"] for l in open(sys.argv[1])][-3:]
print(all("def test_x(" in s for s in ls))' "$(e2e_stub_log ts)")" "name-stripped requests carry test_x"
fi

if _want replay-refused; then
  _replay_setup replay-refused "when the first call writes no record (here: the settings file names no provider), the replay stops before sending anything else"
  e2e_stub_start ts '{"body":{"model":"jev-1.13.0","answers":{"test_catches_wrong":{"type":"noul","noul":0.5}}}}'
  printf '{"systemOne":{"provider":"none","uses":{"verify.discrimination":"shadow"}}}\n' > "$E2E_DIR/provider.json"
  e2e_run_bin bin/flow-s1-eval.sh replay --pairs "$DS_PAIRS" --records "$E2E_DIR/records" \
    --provider-settings "$E2E_DIR/provider.json" --scratch "$E2E_DIR/replay-scratch"
  e2e_expect_equal 3 "$E2E_RC" "exit status"
  e2e_expect_err "first call wrote no record"
  e2e_expect_equal "0" "$(e2e_stub_requests ts)" "requests"
fi

if _want replay-unrecorded; then
  _replay_setup replay-unrecorded "a sent pair that left no record makes the replay exit 4 and name it, an answer in shadow mode is counted as answered, and the temporary plugin copy is removed when no scratch directory is given"
  e2e_stub_start ts '{"body":{"model":"jev-1.13.0","answers":{"test_catches_wrong":{"type":"noul","noul":0.97}}}}'
  _provider_settings "$(e2e_stub_url ts)"
  # The second pair's state file is missing: flow-s1.sh stops before it
  # writes a record for that pair. The first pair is sent as usual.
  _py 'import json,sys
ls=open(sys.argv[1]).read().splitlines()
ps=[json.loads(l) for l in ls]
i=[k for k,p in enumerate(ps) if p["label"]!="unobserved"][1]
ps[i]["states"]["real"]["path"]="states/real/missing.json"
open(sys.argv[1],"w").write("".join(json.dumps(p,sort_keys=True)+"\n" for p in ps))
print(ps[i]["ref"])' "$DS_PAIRS" > "$E2E_DIR/missing-ref.txt"
  # An earlier replay left a no-answer record for that pair: it is sent
  # again, and that old record is not a record of this send.
  mkdir -p "$E2E_DIR/records/real"
  _py 'import json,sys
print(json.dumps({"ts": "2026-01-01T00:00:00Z", "site": "verify.discrimination", "question": "test_catches_wrong",
                  "mode": "shadow", "provider": "custom", "model": "jev-1.13.0", "result": "timeout", "answer": None,
                  "current": "pass", "ref": open(sys.argv[1]).read().strip(), "state_sha256": "0"*64}))' "$E2E_DIR/missing-ref.txt" > "$E2E_DIR/records/real/system-one.jsonl"
  mkdir -p "$E2E_DIR/tmp"
  e2e_run_bin TMPDIR="$E2E_DIR/tmp" bin/flow-s1-eval.sh replay --pairs "$DS_PAIRS" --records "$E2E_DIR/records" \
    --provider-settings "$E2E_DIR/provider.json" --limit 3
  e2e_expect_equal 4 "$E2E_RC" "exit status"
  e2e_expect_err "1 sent pairs have no record (first: $(cat "$E2E_DIR/missing-ref.txt"))"
  e2e_expect_out '"sent_without_record": 1'
  e2e_expect_out '"answered": 2'
  e2e_expect_out '"exit-2": 1'
  e2e_expect_no_out '"shadow"'
  e2e_expect_equal "2" "$(e2e_stub_requests ts)" "requests (the pair without a state file is not sent)"
  e2e_expect_equal "0" "$(find "$E2E_DIR/tmp" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" "entries left in the temporary directory"
fi

if _want replay-429; then
  _replay_setup replay-429 "HTTP 429 is retried once per pair, and the scorer counts both failures as no answer"
  e2e_stub_start ts '{"status":429,"body":{"detail":"rate limited"}}'
  _provider_settings "$(e2e_stub_url ts)"
  e2e_run_bin bin/flow-s1-eval.sh replay --pairs "$DS_PAIRS" --records "$E2E_DIR/records" \
    --provider-settings "$E2E_DIR/provider.json" --scratch "$E2E_DIR/replay-scratch" --limit 2 --backoff 0
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "4" "$(e2e_stub_requests ts)" "requests (2 pairs, each retried once)"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$DS_PAIRS" --records "$E2E_DIR/records" --dest "$E2E_DIR/score" --limit 2
  e2e_expect_equal 0 "$E2E_RC" "scorer exit status"
  e2e_expect_equal "0 2 inconclusive-coverage" "$(_py 'import json,sys
s=json.load(open(sys.argv[1]))
c=s["checks"]["count"]["real"]
print(c["answered"], c["no_answer"].get("http-429",0), s["verdict"]["verdict"])' "$E2E_DIR/score/summary.json")" "answered, http-429 no-answers and the verdict"
fi

# ---------------------------------------------------------------- scorer
# _synth <dir> <spec> — pairs.jsonl, state files and records written from a
# compact spec: one line per group, "set stratum case trap label hn p count
# [ablation=p ...]". p is a number or "timeout". The records' time is
# DS_TS. Every pair gets a unique ref; a group with "same" shares one state
# file between its pairs.
_synth() {
  DS_TS="${DS_TS:-2099-01-01T00:00:00Z}" python3 - "$1" "$2" <<'PY'
import os, sys
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p)]
import hashlib, json
d, spec = sys.argv[1], sys.argv[2]
os.makedirs(os.path.join(d, "states"), exist_ok=True)
pairs, recs = [], {}
n = 0
for line in spec.strip().splitlines():
    f = line.split()
    st, stratum, case, trap, label, hn, p, count = f[:8]
    extra = dict(x.split("=") for x in f[8:] if "=" in x)
    same = "same" in f[8:]
    for i in range(int(count)):
        n += 1
        ref = "eval:%s/%s/r1/%s/t%04d" % (stratum, case, trap, n)
        key = "shared" if same else "s%04d" % n
        path = os.path.join("states", key + ".json")
        # Pairs of a "same" group get byte-identical states, whatever their trap.
        body = json.dumps({"spec": "s", "risk": {"area": "shared" if same else trap, "plausible_wrong_version": "w"},
                           "test": {"id": "t" + key, "source": "def t%s(): pass" % key}}, sort_keys=True).encode()
        with open(os.path.join(d, path), "wb") as fh:
            fh.write(body)
        sha = hashlib.sha256(body).hexdigest()
        pairs.append({"ref": ref, "set": st, "stratum": stratum, "case": case, "run": "r1", "trap": trap,
                      "test_id": "t" + key, "label": label, "hn_behavioral": hn == "hn",
                      "comments_stripped": False, "helpers_missing": False,
                      "states": {"real": {"path": path, "sha256": sha}}})
        for ab, val in [("real", p)] + list(extra.items()):
            # a cycle "c:0.2,0.4" gives the i-th pair of the group the i-th value
            if val.startswith("c:"):
                vals = val[2:].split(",")
                val = vals[i % len(vals)]
            if val == "none":
                continue
            if val in ("timeout", "http-429"):
                rec = {"answer": None, "result": val}
            else:
                pv = float(val)
                conf = abs(2 * pv - 1)
                rec = {"answer": {"type": "noul", "p": pv, "confidence": round(conf, 6)},
                       "result": "answered" if conf >= 0.9 else "below-threshold"}
            rec.update({"ts": os.environ["DS_TS"], "site": "verify.discrimination", "question": "test_catches_wrong",
                        "mode": "shadow", "provider": "typesafe", "model": "jev-1.13.0", "current": label,
                        "ref": ref, "state_sha256": sha})
            recs.setdefault(ab, []).append(rec)
with open(os.path.join(d, "pairs.jsonl"), "w") as fh:
    for p in pairs:
        fh.write(json.dumps(p, sort_keys=True) + "\n")
for ab, rs in recs.items():
    os.makedirs(os.path.join(d, "records", ab), exist_ok=True)
    with open(os.path.join(d, "records", ab, "system-one.jsonl"), "w") as fh:
        for r in rs:
            fh.write(json.dumps(r, sort_keys=True) + "\n")
PY
}
# _sum <dest> <python expression over s, the summary>: a tuple prints as its
# items joined by spaces.
_sum() { _py 'import json,sys
s=json.load(open(sys.argv[1]))
v=eval(sys.argv[2])
print(" ".join(str(x) for x in v) if isinstance(v, tuple) else v)' "$E2E_DIR/$1/summary.json" "$2"; }

if _want score-direction; then
  _setup score-direction "p=0.03 on a fail pair is one false alarm, p=0.97 on a pass pair one missed flag, a timeout is no answer, and two pairs with one state keep their own labels"
  # Fail pairs answer 0.03 once and 0.97 twice, so reading the flag the wrong
  # way round gives 2 of 3 false alarms instead of 1 of 3. The second and third
  # lines share one state file; a join by state_sha256 merges them.
  _synth "$E2E_DIR/d" "
dev agent c1 a fail no 0.03 1
dev agent c1 a fail no 0.97 1 same
dev agent c1 b pass hn 0.03 1 same
dev agent c1 a fail no 0.97 1
dev agent c1 b pass hn 0.97 1
dev agent c1 a fail no timeout 1"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/d/pairs.jsonl" --records "$E2E_DIR/d/records" --dest "$E2E_DIR/s"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "1 3" "$(_sum s 's["sweep"]["agent"]["0.90"]["false_alarm"]["k"], s["sweep"]["agent"]["0.90"]["false_alarm"]["n"]')" "false alarms at t=0.90 (flagged fail pairs, answered fail pairs)"
  e2e_expect_equal "1 2" "$(_sum s 's["sweep"]["agent"]["0.90"]["hn_recall"]["k"], s["sweep"]["agent"]["0.90"]["hn_recall"]["n"]')" "hard negatives flagged at t=0.90"
  e2e_expect_equal "5 1 0.833333" "$(_sum s 's["checks"]["count"]["real"]["answered"], s["checks"]["count"]["real"]["no_answer"]["timeout"], s["strata"]["agent"]["real"]["coverage"]')" "answered, timeouts, coverage"
  e2e_expect_equal "inconclusive-coverage" "$(_sum s 's["verdict"]["verdict"]')" "verdict with 83% coverage"
  # Every pass pair, hard negative or not, flagged at t=0.90: the pair at
  # 0.03 of the two. Wilson 95% lower bound for 1 of 2, by hand:
  # (0.5 - 1.96 sqrt(0.125 + 3.8415/16) / 2.9207) = 0.0945.
  e2e_expect_equal "1 2 0.0945" "$(_sum s 's["sweep"]["agent"]["0.90"]["pass_flagged"]["k"], s["sweep"]["agent"]["0.90"]["pass_flagged"]["n"], "%.4f" % s["sweep"]["agent"]["0.90"]["pass_flagged"]["wilson_lower"]')" "all pass pairs flagged at t=0.90, with the Wilson lower bound"
  e2e_expect_equal "True" "$(grep -q '| 0.90 | 1 of 3 | .* | 1 of 2 | .* | 1 of 2 | 9.5%, ' "$E2E_DIR/s/summary.md" && echo True)" "summary.md sweep row with all pass pairs flagged"
  # The two pairs sharing a state answered 0.97 (fail) and 0.03 (pass); a join
  # by state_sha256 would give both the same answer and two false alarms.
  # Fail {0.03, 0.97, 0.97} against pass {0.03, 0.97}: of 6 comparisons, 2
  # are wins and 3 are ties, so AUC = (2 + 3/2) / 6.
  e2e_expect_equal "0.583333" "$(_sum s 's["strata"]["agent"]["real"]["auc"]')" "AUC"
fi

if _want score-counts; then
  _setup score-counts "a missing, unknown or doubly answered record stops the scorer with harness-error before any metric"
  _synth "$E2E_DIR/d" "
dev agent c1 a fail no 0.97 3
dev agent c1 a pass hn 0.03 3"
  head -n 5 "$E2E_DIR/d/records/real/system-one.jsonl" > "$E2E_DIR/five" && cp "$E2E_DIR/five" "$E2E_DIR/d/records/real/system-one.jsonl"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/d/pairs.jsonl" --records "$E2E_DIR/d/records" --dest "$E2E_DIR/s1"
  e2e_expect_equal 1 "$E2E_RC" "exit status with a missing record"
  e2e_expect_equal "harness-error" "$(_sum s1 's["verdict"]["verdict"]')" "verdict with a missing record"
  e2e_expect_err "records"
  _synth "$E2E_DIR/d" "
dev agent c1 a fail no 0.97 3
dev agent c1 a pass hn 0.03 3"
  tail -n 1 "$E2E_DIR/d/records/real/system-one.jsonl" > "$E2E_DIR/last" && cat "$E2E_DIR/last" >> "$E2E_DIR/d/records/real/system-one.jsonl"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/d/pairs.jsonl" --records "$E2E_DIR/d/records" --dest "$E2E_DIR/s2"
  e2e_expect_equal 1 "$E2E_RC" "exit status with a ref answered twice"
  _synth "$E2E_DIR/d" "
dev agent c1 a fail no 0.97 3
dev agent c1 a pass hn 0.03 3"
  sed 's#"ref": "eval:agent/c1/r1/a/t0001"#"ref": "eval:agent/c1/r1/a/zz"#' "$E2E_DIR/d/records/real/system-one.jsonl" > "$E2E_DIR/x" && cp "$E2E_DIR/x" "$E2E_DIR/d/records/real/system-one.jsonl"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/d/pairs.jsonl" --records "$E2E_DIR/d/records" --dest "$E2E_DIR/s3"
  e2e_expect_equal 1 "$E2E_RC" "exit status with a record for a ref that is not a pair"
  # A no-answer followed by an answer for the same ref (the 429 retry) is one answered pair.
  _synth "$E2E_DIR/d" "
dev agent c1 a fail no 0.97 3
dev agent c1 a pass hn 0.03 3"
  _py 'import json,sys
ls=open(sys.argv[1]).read().splitlines()
r=json.loads(ls[0]); r["answer"]=None; r["result"]="http-429"
open(sys.argv[1],"w").write(json.dumps(r)+"\n"+"\n".join(ls)+"\n")' "$E2E_DIR/d/records/real/system-one.jsonl"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/d/pairs.jsonl" --records "$E2E_DIR/d/records" --dest "$E2E_DIR/s4"
  e2e_expect_equal 0 "$E2E_RC" "exit status with a retried pair"
  e2e_expect_equal "6 1" "$(_sum s4 's["checks"]["count"]["real"]["answered"], s["checks"]["count"]["real"]["retried"]')" "answered and retried pairs"
fi

if _want score-constant; then
  _setup score-constant "a constant predictor does not clear the bar: p=0.01 everywhere fails clause 1, p=0.99 everywhere fails clause 2, all p=0.5 is degenerate"
  DS_TS=2000-01-01T00:00:00Z _synth "$E2E_DIR/dev" "
dev agent c1 a fail no 0.97 80 shuffled=c:0.2,0.4,0.6,0.8
dev agent c1 a pass hn 0.03 40 shuffled=c:0.2,0.4,0.6,0.8
dev author c1 a fail no 0.97 80 shuffled=c:0.2,0.4,0.6,0.8
dev author c1 a pass no 0.03 20 shuffled=c:0.2,0.4,0.6,0.8"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/dev/pairs.jsonl" --records "$E2E_DIR/dev/records" --dest "$E2E_DIR/sdev" --set dev --choose-threshold "$E2E_DIR/threshold.json"
  e2e_expect_equal 0 "$E2E_RC" "dev scorer exit status"
  for DS_P in 0.01 0.99 0.5; do
    _synth "$E2E_DIR/e$DS_P" "
eval agent c1 a fail no $DS_P 80
eval agent c1 a pass hn $DS_P 40"
    e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e$DS_P/pairs.jsonl" --records "$E2E_DIR/e$DS_P/records" --dest "$E2E_DIR/s$DS_P" --set eval --threshold-file "$E2E_DIR/threshold.json"
    e2e_expect_equal 0 "$E2E_RC" "eval scorer exit status, p=$DS_P"
    e2e_expect_no_out '"verdict": "adopt"'
    e2e_expect_equal "inconclusive-degenerate" "$(_sum "s$DS_P" 's["verdict"]["verdict"]')" "verdict, p=$DS_P everywhere"
  done
  e2e_expect_equal "False True" "$(_sum s0.01 's["verdict"]["clauses"]["false_alarm"]["holds"], s["verdict"]["clauses"]["hn_recall"]["holds"]')" "clauses at p=0.01 everywhere"
  e2e_expect_equal "True False" "$(_sum s0.99 's["verdict"]["clauses"]["false_alarm"]["holds"], s["verdict"]["clauses"]["hn_recall"]["holds"]')" "clauses at p=0.99 everywhere"
fi

if _want score-bar; then
  _setup score-bar "t is chosen on the dev set and written before the evaluation records; 0 false alarms in 73 fail pairs clears clause 1 and 0 in 72 does not; records older than t cannot adopt"
  DS_TS=2000-01-01T00:00:00Z _synth "$E2E_DIR/dev" "
dev agent c1 a fail no 0.97 80 shuffled=c:0.2,0.4,0.6,0.8
dev agent c1 a pass hn 0.03 40 shuffled=c:0.2,0.4,0.6,0.8
dev author c1 a fail no 0.97 80 shuffled=c:0.2,0.4,0.6,0.8
dev author c1 a pass no 0.03 20 shuffled=c:0.2,0.4,0.6,0.8"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/dev/pairs.jsonl" --records "$E2E_DIR/dev/records" --dest "$E2E_DIR/sdev" --set dev --choose-threshold "$E2E_DIR/threshold.json"
  e2e_expect_equal 0 "$E2E_RC" "dev scorer exit status"
  # Clause 1 holds at every t on dev (80 fail pairs, none flagged; Wilson
  # upper 3.84/83.84 = 4.6%), so the lowest t in the sweep is chosen.
  e2e_expect_equal "0.5" "$(_py 'import json,sys; print(json.load(open(sys.argv[1]))["t"])' "$E2E_DIR/threshold.json")" "chosen t"
  e2e_expect_equal "dev-only-provisional" "$(_sum sdev 's["verdict"]["verdict"]')" "dev verdict"
  e2e_expect_equal "True" "$(_sum sdev 'abs(s["checks"]["placebo"]["auc"]-0.5)<=0.05 and s["checks"]["placebo"]["ok"]')" "placebo AUC on dev"
  e2e_expect_equal "True" "$(_sum sdev 's["checks"]["permutation"]["ok"]')" "label-permutation check on dev"
  # The placebo AUC's spread with no signal, 80 fail and 40 pass agent pairs:
  # sqrt((80 + 40 + 1) / (12 * 80 * 40)) = sqrt(121 / 38400) = 0.0561.
  e2e_expect_equal "0.0561" "$(_sum sdev '"%.4f" % s["checks"]["placebo"]["null_se"]["agent"]')" "placebo standard error with no signal, agent pairs"
  e2e_expect_equal "True" "$(grep -q 'agent AUC [0-9.]*, standard error 0.056' "$E2E_DIR/sdev/summary.md" && echo True)" "summary.md gives the placebo standard error"
  # Author pass pairs here are not hard negatives: all 20 are flagged at
  # t=0.90 and none counts toward clause 2. Wilson 95% lower bound for 20 of
  # 20: 20 / (20 + 3.8415) = 0.8389.
  e2e_expect_equal "0 20 20 0.8389" "$(_sum sdev 's["sweep"]["author"]["0.90"]["hn_recall"]["n"], s["sweep"]["author"]["0.90"]["pass_flagged"]["k"], s["sweep"]["author"]["0.90"]["pass_flagged"]["n"], "%.4f" % s["sweep"]["author"]["0.90"]["pass_flagged"]["wilson_lower"]')" "author pass pairs flagged at t=0.90: hard negatives, all pass pairs, Wilson lower bound"
  for DS_N in 73 72; do
    _synth "$E2E_DIR/e$DS_N" "
eval agent c1 a fail no 0.97 $DS_N
eval agent c1 a pass hn 0.03 40"
    e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e$DS_N/pairs.jsonl" --records "$E2E_DIR/e$DS_N/records" --dest "$E2E_DIR/s$DS_N" --set eval --threshold-file "$E2E_DIR/threshold.json"
    e2e_expect_equal 0 "$E2E_RC" "eval scorer exit status, $DS_N fail pairs"
  done
  e2e_expect_equal "adopt 0.04999" "$(_sum s73 's["verdict"]["verdict"], "%.5f" % s["verdict"]["clauses"]["false_alarm"]["wilson_upper"]')" "verdict and Wilson upper bound, 0 of 73"
  e2e_expect_equal "not-adopted 0.05065" "$(_sum s72 's["verdict"]["verdict"], "%.5f" % s["verdict"]["clauses"]["false_alarm"]["wilson_upper"]')" "verdict and Wilson upper bound, 0 of 72"
  e2e_expect_equal "0.91238" "$(_sum s73 '"%.5f" % s["verdict"]["clauses"]["hn_recall"]["wilson_lower"]')" "Wilson lower bound, 40 of 40 (40/43.8416)"
  DS_TS=1999-01-01T00:00:00Z _synth "$E2E_DIR/old" "
eval agent c1 a fail no 0.97 73
eval agent c1 a pass hn 0.03 40"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/old/pairs.jsonl" --records "$E2E_DIR/old/records" --dest "$E2E_DIR/sold" --set eval --threshold-file "$E2E_DIR/threshold.json"
  e2e_expect_equal "inconclusive-threshold-order" "$(_sum sold 's["verdict"]["verdict"]')" "verdict when the evaluation records predate t"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e73/pairs.jsonl" --records "$E2E_DIR/e73/records" --dest "$E2E_DIR/snot" --set eval
  e2e_expect_equal "inconclusive-no-threshold" "$(_sum snot 's["verdict"]["verdict"]')" "verdict on the evaluation set without a dev threshold"
  e2e_expect_equal "True" "$(grep -q 'Measurement checks' "$E2E_DIR/s73/summary.md" && grep -q 'Adoption bar' "$E2E_DIR/s73/summary.md" && echo True)" "summary.md has the checks and the bar"
  e2e_expect_equal "True" "$(_py 'import sys
t=open(sys.argv[1]).read()
print(t.index("Measurement checks") < t.index("Adoption bar"))' "$E2E_DIR/s73/summary.md")" "the checks come before the bar in summary.md"
fi

if _want score-identity; then
  _setup score-identity "answers from two providers or models, or from another one than the threshold's, stop the scorer; a threshold needs both dev strata; a dev set whose own checks failed cannot adopt"
  DS_TS=2000-01-01T00:00:00Z _synth "$E2E_DIR/dev" "
dev agent c1 a fail no 0.97 80 shuffled=c:0.2,0.4,0.6,0.8
dev agent c1 a pass hn 0.03 40 shuffled=c:0.2,0.4,0.6,0.8
dev author c1 a fail no 0.97 80 shuffled=c:0.2,0.4,0.6,0.8
dev author c1 a pass no 0.03 20 shuffled=c:0.2,0.4,0.6,0.8"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/dev/pairs.jsonl" --records "$E2E_DIR/dev/records" --dest "$E2E_DIR/sdev" --set dev --choose-threshold "$E2E_DIR/threshold.json"
  e2e_expect_equal 0 "$E2E_RC" "dev scorer exit status"
  e2e_expect_equal "typesafe jev-1.13.0" "$(_py 'import json,sys; print(";".join(json.load(open(sys.argv[1]))["providers"]))' "$E2E_DIR/threshold.json")" "provider and model in the threshold file"
  # One answer from another model in the evaluation records.
  _synth "$E2E_DIR/e1" "
eval agent c1 a fail no 0.97 73
eval agent c1 a pass hn 0.03 40"
  sed '1s/"model": "jev-1.13.0"/"model": "jev-1.14.0"/' "$E2E_DIR/e1/records/real/system-one.jsonl" > "$E2E_DIR/x" && cp "$E2E_DIR/x" "$E2E_DIR/e1/records/real/system-one.jsonl"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e1/pairs.jsonl" --records "$E2E_DIR/e1/records" --dest "$E2E_DIR/s1" --set eval --threshold-file "$E2E_DIR/threshold.json"
  e2e_expect_equal 1 "$E2E_RC" "exit status with answers from two models"
  e2e_expect_equal "harness-error" "$(_sum s1 's["verdict"]["verdict"]')" "verdict with answers from two models"
  e2e_expect_err "more than one provider and model"
  # Every evaluation answer from another model than the threshold's.
  _synth "$E2E_DIR/e2" "
eval agent c1 a fail no 0.97 73
eval agent c1 a pass hn 0.03 40"
  sed 's/"model": "jev-1.13.0"/"model": "jev-1.14.0"/' "$E2E_DIR/e2/records/real/system-one.jsonl" > "$E2E_DIR/x" && cp "$E2E_DIR/x" "$E2E_DIR/e2/records/real/system-one.jsonl"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e2/pairs.jsonl" --records "$E2E_DIR/e2/records" --dest "$E2E_DIR/s2" --set eval --threshold-file "$E2E_DIR/threshold.json"
  e2e_expect_equal 1 "$E2E_RC" "exit status with answers from another model than the threshold's"
  e2e_expect_err "the threshold was chosen on answers from typesafe jev-1.13.0"
  # A no-answer record names the configured model, which may be spelled
  # differently from the model a reply names: it is not a second model.
  _synth "$E2E_DIR/e3" "
eval agent c1 a fail no 0.97 73
eval agent c1 a pass hn 0.03 40
eval agent c1 a fail no timeout 1"
  sed '$s/"model": "jev-1.13.0"/"model": "jev-latest"/' "$E2E_DIR/e3/records/real/system-one.jsonl" > "$E2E_DIR/x" && cp "$E2E_DIR/x" "$E2E_DIR/e3/records/real/system-one.jsonl"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e3/pairs.jsonl" --records "$E2E_DIR/e3/records" --dest "$E2E_DIR/s3" --set eval --threshold-file "$E2E_DIR/threshold.json"
  e2e_expect_equal 0 "$E2E_RC" "exit status with a no-answer record naming the configured model"
  e2e_expect_equal "adopt" "$(_sum s3 's["verdict"]["verdict"]')" "verdict with a no-answer record naming the configured model"
  # A dev set whose own coverage check failed.
  _py 'import json,sys
d=json.load(open(sys.argv[1])); d["coverage_ok"]=False; json.dump(d,open(sys.argv[2],"w"))' "$E2E_DIR/threshold.json" "$E2E_DIR/threshold-lowcov.json"
  _synth "$E2E_DIR/e4" "
eval agent c1 a fail no 0.97 73
eval agent c1 a pass hn 0.03 40"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e4/pairs.jsonl" --records "$E2E_DIR/e4/records" --dest "$E2E_DIR/s4" --set eval --threshold-file "$E2E_DIR/threshold-lowcov.json"
  e2e_expect_equal "inconclusive-dev-checks" "$(_sum s4 's["verdict"]["verdict"]')" "verdict when the dev coverage check failed"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e4/pairs.jsonl" --records "$E2E_DIR/e4/records" --dest "$E2E_DIR/s5" --set eval --threshold-file "$E2E_DIR/threshold.json"
  e2e_expect_equal "adopt" "$(_sum s5 's["verdict"]["verdict"]')" "verdict on the same records with the dev checks passed"
  # A threshold chosen on agent pairs alone.
  DS_TS=2000-01-01T00:00:00Z _synth "$E2E_DIR/dev2" "
dev agent c1 a fail no 0.97 80 shuffled=c:0.2,0.4,0.6,0.8
dev agent c1 a pass hn 0.03 40 shuffled=c:0.2,0.4,0.6,0.8"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/dev2/pairs.jsonl" --records "$E2E_DIR/dev2/records" --dest "$E2E_DIR/sdev2" --set dev --choose-threshold "$E2E_DIR/threshold2.json"
  e2e_expect_equal 2 "$E2E_RC" "exit status when the dev set has no author pairs"
  e2e_expect_err "dev agent pairs and dev author pairs separately"
  e2e_expect_equal "absent" "$([ -e "$E2E_DIR/threshold2.json" ] && echo present || echo absent)" "threshold file"
fi

if _want score-placebo; then
  _setup score-placebo "a placebo that scores as well as the real description makes the dev result unusable for adoption"
  DS_TS=2000-01-01T00:00:00Z _synth "$E2E_DIR/dev" "
dev agent c1 a fail no 0.97 80 shuffled=0.97
dev agent c1 a pass hn 0.03 40 shuffled=0.03
dev author c1 a fail no 0.97 80 shuffled=0.97
dev author c1 a pass no 0.03 20 shuffled=0.03"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/dev/pairs.jsonl" --records "$E2E_DIR/dev/records" --dest "$E2E_DIR/sdev" --set dev --choose-threshold "$E2E_DIR/threshold.json"
  e2e_expect_equal "False" "$(_sum sdev 's["checks"]["placebo"]["ok"]')" "placebo check"
  _synth "$E2E_DIR/e" "
eval agent c1 a fail no 0.97 73
eval agent c1 a pass hn 0.03 40"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e/pairs.jsonl" --records "$E2E_DIR/e/records" --dest "$E2E_DIR/se" --set eval --threshold-file "$E2E_DIR/threshold.json"
  e2e_expect_equal "inconclusive-placebo" "$(_sum se 's["verdict"]["verdict"]')" "verdict"
fi

if _want score-placebo-pooled; then
  _setup score-placebo-pooled "the placebo check judges only the pooled AUC; the per-stratum AUCs are reported with their standard errors"
  # Placebo answers point one way on agent pairs and the other way on author
  # pairs. Per stratum the AUC is 1 (agent) and 0 (author). Pooled over 160
  # fail and 80 pass pairs: a fail pair at 0.97 beats the 40 pass pairs at
  # 0.03 and ties the 40 at 0.97; a fail pair at 0.03 ties the 40 at 0.03 and
  # loses to the 40 at 0.97, so AUC = (80*40 + 80*40/2 + 80*40/2) / (160*80) = 0.5.
  DS_TS=2000-01-01T00:00:00Z _synth "$E2E_DIR/dev" "
dev agent c1 a fail no 0.97 80 shuffled=0.97
dev agent c1 a pass hn 0.03 40 shuffled=0.03
dev author c1 a fail no 0.97 80 shuffled=0.03
dev author c1 a pass no 0.03 40 shuffled=0.97"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/dev/pairs.jsonl" --records "$E2E_DIR/dev/records" --dest "$E2E_DIR/sdev" --set dev --choose-threshold "$E2E_DIR/threshold.json"
  e2e_expect_equal 0 "$E2E_RC" "dev scorer exit status"
  e2e_expect_equal "0.5 1.0 0.0" "$(_sum sdev 's["checks"]["placebo"]["auc"], s["checks"]["placebo"]["per_stratum"]["agent"], s["checks"]["placebo"]["per_stratum"]["author"]')" "pooled, agent and author placebo AUC"
  e2e_expect_equal "True" "$(_sum sdev 's["checks"]["placebo"]["ok"]')" "placebo check judged on the pooled AUC only"
  # Standard error with no signal for 80 fail and 40 pass pairs:
  # sqrt(121 / 38400) = 0.0561, on each stratum.
  e2e_expect_equal "0.0561 0.0561" "$(_sum sdev '"%.4f" % s["checks"]["placebo"]["null_se"]["agent"], "%.4f" % s["checks"]["placebo"]["null_se"]["author"]')" "per-stratum placebo standard errors"
  e2e_expect_equal "True" "$(grep -q 'agent AUC 1.0*, standard error 0.056.*author AUC 0.0*, standard error 0.056' "$E2E_DIR/sdev/summary.md" && echo True)" "summary.md reports the per-stratum AUCs with their standard errors"
  e2e_expect_equal "dev-only-provisional" "$(_sum sdev 's["verdict"]["verdict"]')" "dev verdict"
  _synth "$E2E_DIR/e" "
eval agent c1 a fail no 0.97 73
eval agent c1 a pass hn 0.03 40"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e/pairs.jsonl" --records "$E2E_DIR/e/records" --dest "$E2E_DIR/se" --set eval --threshold-file "$E2E_DIR/threshold.json"
  e2e_expect_equal 0 "$E2E_RC" "eval scorer exit status"
  e2e_expect_equal "False" "$(_sum se 's["verdict"]["verdict"].startswith("inconclusive")')" "eval verdict is not inconclusive"
fi

if _want score-checks; then
  _setup score-checks "a confident provider on a mostly-pass set is not degenerate, and the permutation check is not moved by p differing between traps"
  _synth "$E2E_DIR/a" "
dev agent c1 a fail no 0.97 10
dev agent c1 a pass hn 0.03 90"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/a/pairs.jsonl" --records "$E2E_DIR/a/records" --dest "$E2E_DIR/sa"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "False 0.9" "$(_sum sa 's["checks"]["degenerate"]["agent"]["degenerate"], s["checks"]["degenerate"]["agent"]["largest_bin_share"]')" "degenerate, with 90% of all answers in one bin"
  # Trap a: half fail, every p 0.9; trap b: 10% fail, every p 0.1. Within a
  # trap all p tie, so every permuted within-trap AUC is exactly 0.5; pooled
  # over both traps the permuted AUC is about 0.74.
  _synth "$E2E_DIR/b" "
dev agent c1 a fail no 0.9 50
dev agent c1 a pass hn 0.9 50
dev agent c1 b fail no 0.1 10
dev agent c1 b pass hn 0.1 90"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/b/pairs.jsonl" --records "$E2E_DIR/b/records" --dest "$E2E_DIR/sb"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "True 0.5 True" "$(_sum sb 's["checks"]["permutation"]["ok"], s["checks"]["permutation"]["per_stratum"]["agent"], s["checks"]["permutation"]["pooled_per_stratum"]["agent"] > 0.7')" "permutation check passes; pooled AUC reported above 0.7"
fi

if _want score-determinism; then
  _setup score-determinism "pairs sent twice: answers that differ by more than 0.02 are counted"
  _synth "$E2E_DIR/d" "
dev agent c1 a fail no 0.90 3 repeat=0.95
dev agent c1 a pass hn 0.10 3 repeat=0.11
dev agent c1 a pass hn 0.10 2 repeat=none"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/d/pairs.jsonl" --records "$E2E_DIR/d/records" --dest "$E2E_DIR/s"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "6 3" "$(_sum s 's["checks"]["determinism"]["pairs"], s["checks"]["determinism"]["over_0.02"]')" "repeated pairs and differences above 0.02"
fi
