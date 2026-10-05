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
#       placebo points one way on agent pairs and the other way on author
#       pairs is called inconclusive
#   D19 t is not the lowest t at which clause 1 holds on each dev stratum:
#       always the first t of the sweep, or chosen on agent pairs alone
#   D20 the pairs that chose t are judged again: dev pairs exported a second
#       time as the evaluation set and replayed after t was written
#   D21 a run whose re-run oracle tests differ from the stored ones but are
#       as many is used, or --rescore labels are never checked against the
#       stored failing counts
#   D22 answers read the wrong way round on every pair leave no t and are
#       reported as a provider that cannot do the task, and the smoke step
#       passes a provider that answers the obvious pairs backwards
#   D23 score --limit adopts or writes a threshold on part of the pairs, or
#       trims before choosing the set, so --set eval keeps no pair
#   D24 a placebo replayed on the evaluation set fails and the verdict is
#       still adopt
#   D25 a dev run copied under another --out and exported as the
#       evaluation set gets new refs and run keys and is judged again
#   D26 the direction check judges the AUC pooled over traps, so a provider
#       that orders the tests correctly within every trap is called a
#       harness fault when the traps differ in their share of fail pairs,
#       and one that orders them backwards within every trap passes
#   D27 two answers to the same state that differ by more than 0.02 stop
#       the smoke check or change the scorer's verdict, or the difference is
#       not reported per pair and overall; or a spread lets a smoke run with
#       answers on the wrong side of 0.5 pass
#   D28 the placebo check judges the placebo AUC on its own, not the gap
#       between it and the real-description AUC within each case and trap:
#       a pooled placebo AUC near 0.5 hides a placebo that orders the tests
#       as well as the real description within every trap, a provider whose
#       answers come partly from the test alone is called inconclusive even
#       when the description adds a clear margin, a gap of exactly 0.15
#       is lost to float error, or a single group under 0.15 fails a check
#       whose averages over the case-and-trap groups pass, or the gap in
#       each group is not listed
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
  printf '{"case": "money-allocator", "arm": "baseline", "run": 1, "model": "claude-sonnet-5", "session_id": "fixture-session-1"}\n' > "$run/result.json"
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
  # The run's identity: the sha256 of its own-test-traps.json and the
  # session id in its result.json, computed here from the files.
  e2e_expect_equal "ok" "$(_py 'import json,sys,hashlib
want=sorted(["own-test-traps:"+hashlib.sha256(open(sys.argv[2],"rb").read()).hexdigest(),"session:fixture-session-1"])
for l in open(sys.argv[1]):
    p=json.loads(l)
    if p["stratum"]=="agent" and sorted(p["run_ids"])!=want: print("run_ids",p["run_ids"]); sys.exit()
print("ok")' "$DS_PAIRS" "$DS_TRAPS_JSON")" "agent pairs carry the run identity"
  # The same run copied under another --out: new run keys and refs, the
  # same identity.
  mkdir -p "$E2E_DIR/discrimination-copy"
  cp -R "$DS_OUT/runs" "$E2E_DIR/discrimination-copy/runs"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/export3" --set eval --out "$E2E_DIR/discrimination-copy"
  e2e_expect_equal 0 "$E2E_RC" "exit status of the export of the copied run"
  e2e_expect_equal "disjoint same" "$(_py 'import json,sys
a=[json.loads(l) for l in open(sys.argv[1])]; b=[json.loads(l) for l in open(sys.argv[2])]
a=[p for p in a if p["stratum"]=="agent"]
ra={p["ref"] for p in a}|{p["run"] for p in a}; rb={p["ref"] for p in b}|{p["run"] for p in b}
ia={i for p in a for i in p["run_ids"]}; ib={i for p in b for i in p["run_ids"]}
print("disjoint" if not ra&rb else "shared", "same" if ia==ib else "differ")' "$DS_PAIRS" "$E2E_DIR/export3/pairs.jsonl")" "refs and run keys of the copied run, and its identity"
fi

# ------------------------------------------------- export refusals and labels
if _want export-guards; then
  _setup export-guards "a cut failing list is refused unless re-scored, an unobserved test is labelled unobserved, and a run whose oracle set differs is excluded"
  DS_OUT="$E2E_DIR/runA"
  DS_RUN="$DS_OUT/runs/claude-sonnet-5/baseline/money-allocator/1"
  _agent_run "$DS_RUN"
  cp "$DS_RUN/own-test-traps.json" "$E2E_DIR/own.orig.json"
  # A failing list shorter than its count, as when it was cut at 50: one
  # entry dropped from the list, the count kept.
  _py 'import json,sys
d=json.load(open(sys.argv[1]))
t=next(n for n,v in sorted(d["per_trap"].items()) if v["failing_own_tests"])
d["per_trap"][t]["failing_own_tests"].pop()
json.dump(d,open(sys.argv[1],"w"))' "$DS_RUN/own-test-traps.json"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x1" --set dev --out "$DS_OUT"
  e2e_expect_equal 2 "$E2E_RC" "exit status for a cut failing list"
  e2e_expect_err "failing_count"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x2" --set dev --out "$DS_OUT" --rescore
  e2e_expect_equal 0 "$E2E_RC" "exit status with --rescore"
  e2e_expect_equal "$(_py 'import json,sys; d=json.load(open(sys.argv[1])); print(d["own_passing_tests"]*len(d["per_trap"]))' "$E2E_DIR/own.orig.json")" \
    "$(wc -l < "$E2E_DIR/x2/pairs.jsonl" | tr -d ' ')" "pairs after re-scoring the run"
  e2e_expect_equal "$(_py 'import json,sys; d=json.load(open(sys.argv[1])); print(sum(v["failing_count"] for v in d["per_trap"].values()))' "$E2E_DIR/own.orig.json")" \
    "$(grep -c '"label": "fail"' "$E2E_DIR/x2/pairs.jsonl")" "fail pairs after re-scoring: the stored failing counts"
  # A stored failing count the re-run does not reproduce: with --rescore the
  # fail pairs come from the re-run, and they must still sum to the stored
  # counts, so the run is left out.
  _py 'import json,sys
d=json.load(open(sys.argv[1]))
t=next(n for n,v in sorted(d["per_trap"].items()) if v["failing_own_tests"])
d["per_trap"][t]["failing_count"]=60
json.dump(d,open(sys.argv[2],"w"))' "$E2E_DIR/own.orig.json" "$DS_RUN/own-test-traps.json"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x2b" --set dev --out "$DS_OUT" --rescore
  e2e_expect_equal 0 "$E2E_RC" "exit status with --rescore and a stored count the re-run does not reproduce"
  e2e_expect_equal "0 True" "$(wc -l < "$E2E_DIR/x2b/pairs.jsonl" | tr -d ' ') $(_py 'import json,sys
e=json.load(open(sys.argv[1]))["excluded_runs"]
print(len(e)==1 and "failing counts" in e[0]["reason"])' "$E2E_DIR/x2b/export.json")" "pairs from that run, and the run listed with the fail-count reason"

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

  # The same number of oracle tests, but not the same tests: own-test-traps.json
  # names another test as failing on the reference, or one more test as
  # failing on the agent's module. Comparing the count alone accepts both.
  for DS_SWAP in disagree own_failed; do
    _py 'import json,sys
d=json.load(open(sys.argv[1]))
if sys.argv[3]=="disagree":
    assert len(d["disagree_with_reference"])==1 and d["disagree_with_reference"][0].endswith(".test_float_amount_accepted")
    d["disagree_with_reference"]=[d["disagree_with_reference"][0].replace("test_float_amount_accepted","test_places_zero")]
else:
    d["own_impl"]["failed_ids"]=d["own_impl"]["failed_ids"]+["tests.test_allocate.KnownAnswers.test_ghost"]
json.dump(d,open(sys.argv[2],"w"))' "$E2E_DIR/own.orig.json" "$DS_RUN/own-test-traps.json" "$DS_SWAP"
    e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x4$DS_SWAP" --set dev --out "$DS_OUT"
    e2e_expect_equal 0 "$E2E_RC" "exit status with a stored $DS_SWAP list the re-run does not reproduce"
    e2e_expect_equal "0" "$(wc -l < "$E2E_DIR/x4$DS_SWAP/pairs.jsonl" | tr -d ' ')" "pairs from the run with a changed $DS_SWAP list"
    e2e_expect_equal "True" "$(_py 'import json,sys
e=json.load(open(sys.argv[1]))["excluded_runs"]
want={"disagree":"disagree_with_reference","own_failed":"own_impl.failed_ids"}[sys.argv[2]]
print(len(e)==1 and "oracle" in e[0]["reason"] and want in e[0]["reason"])' "$E2E_DIR/x4$DS_SWAP/export.json" "$DS_SWAP")" "the run is excluded, naming the $DS_SWAP list"
  done

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
# DS_TS. Every pair gets a unique ref, and its run and ref carry the set
# name, so dev and evaluation pairs never share one; a group with "same"
# shares one state file between its pairs.
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
        run = "%s-r1" % st
        ref = "eval:%s/%s/%s/%s/t%04d" % (stratum, case, run, trap, n)
        key = "shared" if same else "s%04d" % n
        path = os.path.join("states", key + ".json")
        # Pairs of a "same" group get byte-identical states, whatever their trap.
        body = json.dumps({"spec": "s", "risk": {"area": "shared" if same else trap, "plausible_wrong_version": "w"},
                           "test": {"id": "t" + key, "source": "def t%s(): pass" % key}}, sort_keys=True).encode()
        with open(os.path.join(d, path), "wb") as fh:
            fh.write(body)
        sha = hashlib.sha256(body).hexdigest()
        pairs.append({"ref": ref, "set": st, "stratum": stratum, "case": case, "run": run,
                      "run_ids": ["own-test-traps:" + run] if stratum == "agent" else None, "trap": trap,
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
  sed 's#"ref": "eval:agent/c1/dev-r1/a/t0001"#"ref": "eval:agent/c1/dev-r1/a/zz"#' "$E2E_DIR/d/records/real/system-one.jsonl" > "$E2E_DIR/x" && cp "$E2E_DIR/x" "$E2E_DIR/d/records/real/system-one.jsonl"
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

if _want score-held-out; then
  _setup score-held-out "pairs or runs that chose t cannot be judged again as the evaluation set: the scorer stops with harness-error"
  DS_TS=2000-01-01T00:00:00Z _synth "$E2E_DIR/dev" "
dev agent c1 a fail no 0.97 80 shuffled=c:0.2,0.4,0.6,0.8
dev agent c1 a pass hn 0.03 40 shuffled=c:0.2,0.4,0.6,0.8
dev author c1 a fail no 0.97 80 shuffled=c:0.2,0.4,0.6,0.8
dev author c1 a pass no 0.03 20 shuffled=c:0.2,0.4,0.6,0.8"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/dev/pairs.jsonl" --records "$E2E_DIR/dev/records" --dest "$E2E_DIR/sdev" --set dev --choose-threshold "$E2E_DIR/threshold.json"
  e2e_expect_equal 0 "$E2E_RC" "dev scorer exit status"
  # 80 + 40 + 80 + 20 dev pairs, and the one agent run of the fixture.
  e2e_expect_equal "220 dev-r1" "$(_py 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d["dev_refs"]), ",".join(d["dev_runs"]))' "$E2E_DIR/threshold.json")" "dev refs and runs in the threshold file"
  e2e_expect_equal "False" "$(_sum sdev '"dev_refs" in s["threshold"]')" "summary.json does not copy the dev refs"
  _synth "$E2E_DIR/e" "
eval agent c1 a fail no 0.97 73
eval agent c1 a pass hn 0.03 40"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e/pairs.jsonl" --records "$E2E_DIR/e/records" --dest "$E2E_DIR/s0" --set eval --threshold-file "$E2E_DIR/threshold.json"
  e2e_expect_equal "0 adopt" "$E2E_RC $(_sum s0 's["verdict"]["verdict"]')" "exit status and verdict on held-out pairs"
  # One evaluation ref that is a dev ref, in the pairs and in its record.
  for DS_F in pairs.jsonl records/real/system-one.jsonl; do
    sed 's#eval:agent/c1/eval-r1/a/t0001"#eval:agent/c1/dev-r1/a/t0001"#' "$E2E_DIR/e/$DS_F" > "$E2E_DIR/x" && cp "$E2E_DIR/x" "$E2E_DIR/e/$DS_F"
  done
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e/pairs.jsonl" --records "$E2E_DIR/e/records" --dest "$E2E_DIR/s1" --set eval --threshold-file "$E2E_DIR/threshold.json"
  e2e_expect_equal "1 harness-error" "$E2E_RC $(_sum s1 's["verdict"]["verdict"]')" "exit status and verdict with one evaluation ref from the dev set"
  e2e_expect_err "1 evaluation pairs were in the dev set"
  # The run key of a dev run on evaluation pairs whose refs are new.
  _synth "$E2E_DIR/e2" "
eval agent c1 a fail no 0.97 73
eval agent c1 a pass hn 0.03 40"
  sed 's#"run": "eval-r1"#"run": "dev-r1"#' "$E2E_DIR/e2/pairs.jsonl" > "$E2E_DIR/x" && cp "$E2E_DIR/x" "$E2E_DIR/e2/pairs.jsonl"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e2/pairs.jsonl" --records "$E2E_DIR/e2/records" --dest "$E2E_DIR/s2" --set eval --threshold-file "$E2E_DIR/threshold.json"
  e2e_expect_equal 1 "$E2E_RC" "exit status with an evaluation run from the dev set"
  e2e_expect_err "1 evaluation runs were in the dev set"
  # The dev pairs exported again as the evaluation set and replayed after t
  # was written: every record is newer than the threshold, every ref is old.
  _py 'import json,sys,os
src,dst=sys.argv[1],sys.argv[2]
os.makedirs(os.path.join(dst,"records","real"),exist_ok=True)
with open(os.path.join(dst,"pairs.jsonl"),"w") as fh:
    for l in open(os.path.join(src,"pairs.jsonl")):
        p=json.loads(l); p["set"]="eval"; fh.write(json.dumps(p)+"\n")
with open(os.path.join(dst,"records","real","system-one.jsonl"),"w") as fh:
    for l in open(os.path.join(src,"records","real","system-one.jsonl")):
        r=json.loads(l); r["ts"]="2099-01-01T00:00:00Z"; fh.write(json.dumps(r)+"\n")' "$E2E_DIR/dev" "$E2E_DIR/again"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/again/pairs.jsonl" --records "$E2E_DIR/again/records" --dest "$E2E_DIR/s3" --set eval --threshold-file "$E2E_DIR/threshold.json"
  e2e_expect_equal "1 harness-error" "$E2E_RC $(_sum s3 's["verdict"]["verdict"]')" "exit status and verdict on the dev pairs exported again as the evaluation set"
  e2e_expect_err "220 evaluation pairs were in the dev set"
  # A threshold file that does not list the dev pairs cannot be checked.
  _py 'import json,sys
d=json.load(open(sys.argv[1])); del d["dev_refs"]; json.dump(d,open(sys.argv[2],"w"))' "$E2E_DIR/threshold.json" "$E2E_DIR/threshold-norefs.json"
  _synth "$E2E_DIR/e4" "
eval agent c1 a fail no 0.97 73
eval agent c1 a pass hn 0.03 40"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e4/pairs.jsonl" --records "$E2E_DIR/e4/records" --dest "$E2E_DIR/s4" --set eval --threshold-file "$E2E_DIR/threshold-norefs.json"
  e2e_expect_equal 1 "$E2E_RC" "exit status with a threshold file that does not list the dev pairs"
  e2e_expect_err "does not list the dev pairs"
  # A dev run copied under another --out: new refs and a new run key, the
  # dev run's identity.
  _synth "$E2E_DIR/e5" "
eval agent c1 a fail no 0.97 73
eval agent c1 a pass hn 0.03 40"
  sed 's#"own-test-traps:eval-r1"#"own-test-traps:dev-r1"#' "$E2E_DIR/e5/pairs.jsonl" > "$E2E_DIR/x" && cp "$E2E_DIR/x" "$E2E_DIR/e5/pairs.jsonl"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e5/pairs.jsonl" --records "$E2E_DIR/e5/records" --dest "$E2E_DIR/s5" --set eval --threshold-file "$E2E_DIR/threshold.json"
  e2e_expect_equal "1 harness-error" "$E2E_RC $(_sum s5 's["verdict"]["verdict"]')" "exit status and verdict with a dev run under a new run key"
  e2e_expect_err "1 evaluation runs were in the dev set"
  # Evaluation pairs exported before runs carried an identity.
  _synth "$E2E_DIR/e6" "
eval agent c1 a fail no 0.97 73
eval agent c1 a pass hn 0.03 40"
  sed 's#"run_ids": \["own-test-traps:eval-r1"\], ##' "$E2E_DIR/e6/pairs.jsonl" > "$E2E_DIR/x" && cp "$E2E_DIR/x" "$E2E_DIR/e6/pairs.jsonl"
  e2e_expect_equal "0" "$(grep -c run_ids "$E2E_DIR/e6/pairs.jsonl")" "pairs without a run identity"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e6/pairs.jsonl" --records "$E2E_DIR/e6/records" --dest "$E2E_DIR/s6" --set eval --threshold-file "$E2E_DIR/threshold.json"
  e2e_expect_equal 1 "$E2E_RC" "exit status with evaluation pairs that carry no run identity"
  e2e_expect_err "carry no run identity"
  # A threshold is not chosen on dev pairs without a run identity.
  sed 's#"run_ids": \["own-test-traps:dev-r1"\], ##' "$E2E_DIR/dev/pairs.jsonl" > "$E2E_DIR/x" && cp "$E2E_DIR/x" "$E2E_DIR/dev/pairs.jsonl"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/dev/pairs.jsonl" --records "$E2E_DIR/dev/records" --dest "$E2E_DIR/sdev7" --set dev --choose-threshold "$E2E_DIR/threshold7.json"
  e2e_expect_equal 2 "$E2E_RC" "exit status when dev pairs carry no run identity"
  e2e_expect_equal "absent" "$([ -e "$E2E_DIR/threshold7.json" ] && echo present || echo absent)" "threshold file"
fi

if _want score-threshold-rule; then
  _setup score-threshold-rule "t is the lowest t at which clause 1 holds on dev agent pairs and on dev author pairs separately; with no such t the evaluation set is inconclusive"
  # Two fail pairs at p=0.20 (confidence 0.6) are flagged at t up to 0.60
  # and not above. Wilson 95% upper bound by hand, z^2 = 3.8415: 2 of 116 is
  # (0.01724 + 0.01656 + 1.96 sqrt(0.01724 * 0.98276 / 116 + 3.8415 / 53824))
  # / 1.03312 = 0.0607, above 5%; 0 of 116 is 3.8415 / 119.8415 = 0.0321.
  # So t = 0.65, whichever stratum holds the two pairs.
  for DS_S in agent author; do
    if [ "$DS_S" = agent ]; then DS_A=0.20; DS_U=0.97; else DS_A=0.97; DS_U=0.20; fi
    DS_TS=2000-01-01T00:00:00Z _synth "$E2E_DIR/dev-$DS_S" "
dev agent c1 a fail no 0.97 114
dev agent c1 a fail no $DS_A 2
dev agent c1 a pass hn 0.03 40
dev author c1 a fail no 0.97 114
dev author c1 a fail no $DS_U 2
dev author c1 a pass no 0.03 20"
    e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/dev-$DS_S/pairs.jsonl" --records "$E2E_DIR/dev-$DS_S/records" --dest "$E2E_DIR/s-$DS_S" --set dev --choose-threshold "$E2E_DIR/threshold-$DS_S.json"
    e2e_expect_equal 0 "$E2E_RC" "dev scorer exit status, two flagged fail pairs in the $DS_S stratum"
    e2e_expect_equal "2 116 0.0607 0 0.0321" "$(_py 'import json,sys
r=json.load(open(sys.argv[1]))["sweep"][sys.argv[2]]
a,b=r["0.60"]["false_alarm"],r["0.65"]["false_alarm"]
print(a["k"], a["n"], "%.4f" % a["wilson_upper"], b["k"], "%.4f" % b["wilson_upper"])' "$E2E_DIR/s-$DS_S/summary.json" "$DS_S")" "$DS_S false alarms at t=0.60 and t=0.65"
    e2e_expect_equal "0.65" "$(_py 'import json,sys; print(json.load(open(sys.argv[1]))["t"])' "$E2E_DIR/threshold-$DS_S.json")" "chosen t, two flagged fail pairs in the $DS_S stratum"
  done
  # Two agent fail pairs at p=0.01 (confidence 0.98) are flagged at every t.
  DS_TS=2000-01-01T00:00:00Z _synth "$E2E_DIR/dev-none" "
dev agent c1 a fail no 0.97 114
dev agent c1 a fail no 0.01 2
dev agent c1 a pass hn 0.03 40
dev author c1 a fail no 0.97 116
dev author c1 a pass no 0.03 20"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/dev-none/pairs.jsonl" --records "$E2E_DIR/dev-none/records" --dest "$E2E_DIR/s-none" --set dev --choose-threshold "$E2E_DIR/threshold-none.json"
  e2e_expect_equal 0 "$E2E_RC" "dev scorer exit status, no t holds"
  e2e_expect_equal "None" "$(_py 'import json,sys; print(json.load(open(sys.argv[1]))["t"])' "$E2E_DIR/threshold-none.json")" "chosen t when clause 1 holds at no t"
  _synth "$E2E_DIR/e" "
eval agent c1 a fail no 0.97 73
eval agent c1 a pass hn 0.03 40"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e/pairs.jsonl" --records "$E2E_DIR/e/records" --dest "$E2E_DIR/se" --set eval --threshold-file "$E2E_DIR/threshold-none.json"
  e2e_expect_equal "0 inconclusive-no-threshold" "$E2E_RC $(_sum se 's["verdict"]["verdict"]')" "exit status and evaluation verdict with no dev threshold"
fi

if _want score-name-stripped; then
  _setup score-name-stripped "the agent AUC with the test name and without it, their difference and its standard error are reported, not judged"
  # Real answers separate fail from pass completely (AUC 1); with the name
  # removed every answer is 0.5 (AUC 0.5). The drop is 0.5 and, with no
  # spread in either set of answers, its standard error is 0.
  _synth "$E2E_DIR/a" "
dev agent c1 a fail no 0.97 10 name-stripped=0.5
dev agent c1 a pass hn 0.03 10 name-stripped=0.5"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/a/pairs.jsonl" --records "$E2E_DIR/a/records" --dest "$E2E_DIR/sa"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "20 1.0 0.5 0.5 0.0" "$(_sum sa 'tuple(s["checks"]["name_stripped"][k] for k in ("pairs", "auc_real", "auc_name_stripped", "difference", "standard_error"))')" "pairs, AUC with and without the name, drop, standard error"
  e2e_expect_equal "dev-only-provisional" "$(_sum sa 's["verdict"]["verdict"]')" "the drop does not change the verdict"
  e2e_expect_equal "True" "$(grep -q '| Test name removed, agent pairs (reported, not judged.*| AUC 1.000 with the name, 0.500 without; drop 0.500, standard error 0.000, over 20 pairs' "$E2E_DIR/sa/summary.md" && echo True)" "summary.md row"
  # Spread-out answers: the standard error is checked against DeLong's
  # formula computed here pair by pair, not by the scorer's code.
  _synth "$E2E_DIR/b" "
dev agent c1 a fail no c:0.9,0.6,0.4,0.8 8 name-stripped=c:0.7,0.5,0.3
dev agent c1 a pass hn c:0.1,0.5,0.7 9 name-stripped=c:0.2,0.6,0.4,0.45"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/b/pairs.jsonl" --records "$E2E_DIR/b/records" --dest "$E2E_DIR/sb"
  e2e_expect_equal 0 "$E2E_RC" "exit status, spread-out answers"
  e2e_expect_equal "ok" "$(_py 'import json,sys,math
s=json.load(open(sys.argv[1])); n=s["checks"]["name_stripped"]
def recs(ab): return {json.loads(l)["ref"]: json.loads(l)["answer"]["p"] for l in open(sys.argv[2]+"/records/"+ab+"/system-one.jsonl")}
lab={json.loads(l)["ref"]: json.loads(l)["label"]=="fail" for l in open(sys.argv[2]+"/pairs.jsonl")}
r, q = recs("real"), recs("name-stripped")
F=[k for k in lab if lab[k]]; P=[k for k in lab if not lab[k]]
psi=lambda x,y: 1.0 if x>y else (0.5 if x==y else 0.0)
out=[]
for d in (r,q):
    v10=[sum(psi(d[f],d[p]) for p in P)/len(P) for f in F]
    v01=[sum(psi(d[f],d[p]) for f in F)/len(F) for p in P]
    out.append((sum(v10)/len(F), v10, v01))
def cov(u,v):
    mu,mv=sum(u)/len(u),sum(v)/len(v); return sum((a-mu)*(b-mv) for a,b in zip(u,v))/(len(u)-1)
(a,a10,a01),(b,b10,b01)=out
var=(cov(a10,a10)+cov(b10,b10)-2*cov(a10,b10))/len(F)+(cov(a01,a01)+cov(b01,b01)-2*cov(a01,b01))/len(P)
want=(round(a,6), round(b,6), round(a-b,6), round(math.sqrt(var),6))
got=(n["auc_real"], n["auc_name_stripped"], n["difference"], n["standard_error"])
print("ok" if all(abs(x-y)<1e-6 for x,y in zip(want,got)) and want[3]>0 else "%r != %r" % (got, want))' "$E2E_DIR/sb/summary.json" "$E2E_DIR/b")" "AUCs, drop and standard error against DeLong computed pair by pair"
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
  _setup score-placebo-pooled "the placebo check averages the groups of both strata; the pooled and per-stratum placebo AUCs are reported with their standard errors"
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
  # Within the agent group the placebo AUC is 1 and within the author group
  # 0: the mean is 0.5, and the real description (1 in both) exceeds it by
  # 0.5.
  e2e_expect_equal "0.5 0.5 True" "$(_sum sdev 's["checks"]["placebo"]["within"]["placebo_auc"], s["checks"]["placebo"]["within"]["gap"], s["checks"]["placebo"]["ok"]')" "placebo AUC within case and trap, the gap, and the check"
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

if _want score-threshold-file; then
  _setup score-threshold-file "a threshold file that is missing, not JSON, or not an object stops the scorer with a usage error"
  _synth "$E2E_DIR/e" "
eval agent c1 a fail no 0.97 73
eval agent c1 a pass hn 0.03 40"
  printf 'null\n' > "$E2E_DIR/null.json"
  printf '[0.5]\n' > "$E2E_DIR/list.json"
  printf '{"t": 0.5' > "$E2E_DIR/cut.json"
  for DS_T in null list; do
    e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e/pairs.jsonl" --records "$E2E_DIR/e/records" --dest "$E2E_DIR/s-$DS_T" --set eval --threshold-file "$E2E_DIR/$DS_T.json"
    e2e_expect_equal 2 "$E2E_RC" "exit status for a threshold file holding $DS_T"
    e2e_expect_err "does not hold a threshold"
  done
  for DS_T in cut missing; do
    e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e/pairs.jsonl" --records "$E2E_DIR/e/records" --dest "$E2E_DIR/s-$DS_T" --set eval --threshold-file "$E2E_DIR/$DS_T.json"
    e2e_expect_equal 2 "$E2E_RC" "exit status for a threshold file that is $DS_T"
    e2e_expect_err "threshold-file cannot be read"
  done
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
  _setup score-determinism "pairs sent twice: the difference between the two answers is reported per pair and overall, and never changes the verdict"
  _synth "$E2E_DIR/d" "
dev agent c1 a fail no 0.90 3 repeat=0.95
dev agent c1 a pass hn 0.10 3 repeat=0.11
dev agent c1 a pass hn 0.10 2 repeat=none"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/d/pairs.jsonl" --records "$E2E_DIR/d/records" --dest "$E2E_DIR/s"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "6 3" "$(_sum s 's["checks"]["determinism"]["pairs"], s["checks"]["determinism"]["over_0.02"]')" "repeated pairs and differences above 0.02"
  # Three differences of 0.05 and three of 0.01, by hand: largest 0.05,
  # mean (3 x 0.05 + 3 x 0.01) / 6 = 0.03.
  e2e_expect_equal "0.05 0.03" "$(_sum s 's["checks"]["determinism"]["largest_difference"], s["checks"]["determinism"]["mean_difference"]')" "largest and mean difference"
  e2e_expect_equal "6 0.05 0.01" "$(_sum s 'len(s["checks"]["determinism"]["per_pair"]), max(r["difference"] for r in s["checks"]["determinism"]["per_pair"]), min(r["difference"] for r in s["checks"]["determinism"]["per_pair"])')" "one row per pair sent twice, with its difference"
  e2e_expect_equal "True" "$(grep -qF '| Same state sent twice: how far apart the two answers are (smaller is better; reported, not judged) | 6 pairs; the two answers differ by 0.050 at most and 0.030 on average; 3 differ by more than 0.02 |' "$E2E_DIR/s/summary.md" && echo True)" "summary.md row in plain words"
  e2e_expect_equal "6" "$(grep -cE '^\| eval:agent/c1/dev-r1/a/t[0-9]{4} \| 0\.(900|100) \| 0\.(950|110) \| 0\.(050|010) \|$' "$E2E_DIR/s/summary.md")" "summary.md table with each pair sent twice"
  # The same pairs with repeats 0.50 away: the verdict is the one the
  # scorer gives with no repeat at all.
  _synth "$E2E_DIR/far" "
dev agent c1 a fail no 0.90 3 repeat=0.40
dev agent c1 a pass hn 0.10 3 repeat=0.60
dev agent c1 a pass hn 0.10 2 repeat=none"
  _synth "$E2E_DIR/none" "
dev agent c1 a fail no 0.90 3
dev agent c1 a pass hn 0.10 3
dev agent c1 a pass hn 0.10 2"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/far/pairs.jsonl" --records "$E2E_DIR/far/records" --dest "$E2E_DIR/sfar"
  e2e_expect_equal 0 "$E2E_RC" "exit status, repeats 0.50 away"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/none/pairs.jsonl" --records "$E2E_DIR/none/records" --dest "$E2E_DIR/snone"
  e2e_expect_equal 0 "$E2E_RC" "exit status, no repeat"
  e2e_expect_equal "$(_sum snone 's["verdict"]["verdict"]') 0.5 6" "$(_sum sfar 's["verdict"]["verdict"], s["checks"]["determinism"]["largest_difference"], s["checks"]["determinism"]["over_0.02"]')" "verdict with repeats 0.50 away equals the verdict with no repeat"
  e2e_expect_equal "0 None None" "$(_sum snone 's["checks"]["determinism"]["pairs"], s["checks"]["determinism"]["largest_difference"], s["checks"]["determinism"]["per_pair"] or None')" "no repeat: nothing measured"
  e2e_expect_equal "True" "$(grep -qF 'not measured: no pair was answered twice' "$E2E_DIR/snone/summary.md" && echo True)" "summary.md says not measured"
fi

if _want score-direction-check; then
  _setup score-direction-check "answers read the wrong way round give inconclusive-direction, on the dev set, on the evaluation set and through the threshold file, and are not reported as a provider without the signal"
  # Every fail pair answered 0.03 and every pass pair 0.97: the real AUC is
  # 0, which is far more than 2 no-signal standard errors below 0.5.
  DS_TS=2000-01-01T00:00:00Z _synth "$E2E_DIR/inv" "
dev agent c1 a fail no 0.03 80 shuffled=c:0.2,0.4,0.6,0.8
dev agent c1 a pass hn 0.97 40 shuffled=c:0.2,0.4,0.6,0.8
dev author c1 a fail no 0.03 80 shuffled=c:0.2,0.4,0.6,0.8
dev author c1 a pass no 0.97 20 shuffled=c:0.2,0.4,0.6,0.8"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/inv/pairs.jsonl" --records "$E2E_DIR/inv/records" --dest "$E2E_DIR/sinv" --set dev --choose-threshold "$E2E_DIR/threshold-inv.json"
  e2e_expect_equal 0 "$E2E_RC" "dev scorer exit status"
  e2e_expect_equal "inconclusive-direction 0.0 False" "$(_sum sinv 's["verdict"]["verdict"], s["checks"]["direction"]["auc"], s["checks"]["direction"]["ok"]')" "dev verdict, real AUC, direction check"
  e2e_expect_equal "False" "$(_py 'import json,sys; print(json.load(open(sys.argv[1]))["direction_ok"])' "$E2E_DIR/threshold-inv.json")" "direction in the threshold file"
  e2e_expect_equal "True" "$(grep -q '| Real-description AUC, mean within case and trap, not more than 2 standard errors below 0.5 .* | NO (AUC 0.000' "$E2E_DIR/sinv/summary.md" && echo True)" "summary.md direction row"
  # A dev set read the right way round, then evaluation answers read the
  # wrong way round.
  DS_TS=2000-01-01T00:00:00Z _synth "$E2E_DIR/dev" "
dev agent c1 a fail no 0.97 80 shuffled=c:0.2,0.4,0.6,0.8
dev agent c1 a pass hn 0.03 40 shuffled=c:0.2,0.4,0.6,0.8
dev author c1 a fail no 0.97 80 shuffled=c:0.2,0.4,0.6,0.8
dev author c1 a pass no 0.03 20 shuffled=c:0.2,0.4,0.6,0.8"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/dev/pairs.jsonl" --records "$E2E_DIR/dev/records" --dest "$E2E_DIR/sdev" --set dev --choose-threshold "$E2E_DIR/threshold.json"
  e2e_expect_equal "dev-only-provisional True" "$(_sum sdev 's["verdict"]["verdict"], s["checks"]["direction"]["ok"]')" "dev verdict and direction check read the right way round"
  _synth "$E2E_DIR/e" "
eval agent c1 a fail no 0.03 73
eval agent c1 a pass hn 0.97 40"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e/pairs.jsonl" --records "$E2E_DIR/e/records" --dest "$E2E_DIR/se" --set eval --threshold-file "$E2E_DIR/threshold.json"
  e2e_expect_equal "0 inconclusive-direction" "$E2E_RC $(_sum se 's["verdict"]["verdict"]')" "exit status and verdict, evaluation answers read the wrong way round"
  # The threshold file of a dev set whose direction check failed.
  _py 'import json,sys
d=json.load(open(sys.argv[1])); d["direction_ok"]=False; json.dump(d,open(sys.argv[2],"w"))' "$E2E_DIR/threshold.json" "$E2E_DIR/threshold-dir.json"
  _synth "$E2E_DIR/e2" "
eval agent c1 a fail no 0.97 73
eval agent c1 a pass hn 0.03 40"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e2/pairs.jsonl" --records "$E2E_DIR/e2/records" --dest "$E2E_DIR/se2" --set eval --threshold-file "$E2E_DIR/threshold-dir.json"
  e2e_expect_equal "inconclusive-dev-checks" "$(_sum se2 's["verdict"]["verdict"]')" "verdict when the dev direction check failed"
  e2e_expect_equal "True" "$(_sum se2 '"direction" in s["verdict"]["reasons"][0]')" "the reason names the direction check"
  # No signal on the real description: named in summary.md, verdict unchanged.
  _synth "$E2E_DIR/flat" "
dev agent c1 a fail no c:0.2,0.4,0.6,0.8 40
dev agent c1 a pass hn c:0.2,0.4,0.6,0.8 40"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/flat/pairs.jsonl" --records "$E2E_DIR/flat/records" --dest "$E2E_DIR/sflat"
  e2e_expect_equal "True 0.5 dev-only-provisional" "$(_sum sflat 's["checks"]["direction"]["ok"], s["checks"]["direction"]["auc"], s["verdict"]["verdict"]')" "direction check, AUC and verdict with no signal"
  e2e_expect_equal "True" "$(grep -q 'carry no signal on the real description' "$E2E_DIR/sflat/summary.md" && echo True)" "summary.md names no signal on the real description"
fi

if _want score-direction-within-trap; then
  _setup score-direction-within-trap "the direction check judges the mean of the AUCs within each case and trap, not the AUC pooled over traps that differ in their share of fail pairs"
  # Right way round within each trap. Trap a: 80 fail pairs at 0.35 or 0.45
  # above 10 pass pairs at 0.25 or 0.15. Trap b: 10 fail pairs at 0.95 or
  # 0.85 above 80 pass pairs at 0.75 or 0.65. Each trap's AUC is 1. Pooled,
  # a trap-a fail pair is above only the 10 trap-a pass pairs and a trap-b
  # fail pair above all 90, so AUC = (80*10 + 10*90) / (90*90) = 0.2099,
  # far below 0.5 - 2 * 0.0432 = 0.4137.
  _synth "$E2E_DIR/w" "
dev agent c1 a fail no c:0.35,0.45 80
dev agent c1 a pass hn c:0.25,0.15 10
dev agent c1 b fail no c:0.95,0.85 10
dev agent c1 b pass hn c:0.75,0.65 80"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/w/pairs.jsonl" --records "$E2E_DIR/w/records" --dest "$E2E_DIR/sw"
  e2e_expect_equal 0 "$E2E_RC" "scorer exit status"
  e2e_expect_equal "True 1.0" "$(_sum sw 's["checks"]["direction"]["ok"], s["checks"]["direction"]["auc"]')" "direction check and the judged AUC, the mean within traps"
  e2e_expect_equal "2 180 0.209877" "$(_sum sw 's["checks"]["direction"].get("groups"), s["checks"]["direction"].get("pairs"), s["checks"]["direction"].get("pooled_auc")')" "groups, pairs and the pooled AUC reported beside it"
  # With no signal each trap's AUC has standard error sqrt(91 / (12*80*10));
  # the mean of the two has sqrt(2 * 91 / 9600) / 2.
  e2e_expect_equal "$(_py 'import math; print("%.6f" % (math.sqrt(2 * 91 / 9600.0) / 2))')" "$(_sum sw '"%.6f" % s["checks"]["direction"]["null_se"]')" "standard error of the mean with no signal"
  e2e_expect_equal "dev-only-provisional" "$(_sum sw 's["verdict"]["verdict"]')" "verdict, not inconclusive-direction"
  e2e_expect_equal "True" "$(grep -q '| Real-description AUC, mean within case and trap, .* | yes (AUC 1.000.*over 2 case and trap groups holding 180 pairs; pooled over all pairs, reported and not judged: AUC 0.210' "$E2E_DIR/sw/summary.md" && echo True)" "summary.md direction row reports the pooled AUC beside the judged mean"
  # Wrong way round within each trap. Trap a: 80 fail pairs at 0.65 or 0.75
  # below 10 pass pairs at 0.85 or 0.95. Trap b: 10 fail pairs at 0.15 or
  # 0.25 below 80 pass pairs at 0.35 or 0.45. Each trap's AUC is 0. Pooled,
  # a trap-a fail pair is above the 80 trap-b pass pairs, so AUC =
  # 80*80 / (90*90) = 0.7901, which the pooled number would pass.
  _synth "$E2E_DIR/b" "
dev agent c1 a fail no c:0.65,0.75 80
dev agent c1 a pass hn c:0.85,0.95 10
dev agent c1 b fail no c:0.15,0.25 10
dev agent c1 b pass hn c:0.35,0.45 80"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/b/pairs.jsonl" --records "$E2E_DIR/b/records" --dest "$E2E_DIR/sb"
  e2e_expect_equal 0 "$E2E_RC" "scorer exit status, backwards within each trap"
  e2e_expect_equal "False 0.0 inconclusive-direction" "$(_sum sb 's["checks"]["direction"]["ok"], s["checks"]["direction"]["auc"], s["verdict"]["verdict"]')" "direction check, judged AUC and verdict, backwards within each trap"
  e2e_expect_equal "0.790123" "$(_sum sb 's["checks"]["direction"].get("pooled_auc")')" "pooled AUC, backwards within each trap"
fi

if _want score-limit; then
  _setup score-limit "score --limit never adopts and never chooses a threshold, records the limit, and trims after the set is chosen"
  DS_TS=2000-01-01T00:00:00Z _synth "$E2E_DIR/dev" "
dev agent c1 a fail no 0.97 80 shuffled=c:0.2,0.4,0.6,0.8
dev agent c1 a pass hn 0.03 40 shuffled=c:0.2,0.4,0.6,0.8
dev author c1 a fail no 0.97 80 shuffled=c:0.2,0.4,0.6,0.8
dev author c1 a pass no 0.03 20 shuffled=c:0.2,0.4,0.6,0.8"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/dev/pairs.jsonl" --records "$E2E_DIR/dev/records" --dest "$E2E_DIR/slim" --set dev --choose-threshold "$E2E_DIR/threshold-lim.json" --limit 200
  e2e_expect_equal 2 "$E2E_RC" "exit status of --choose-threshold with --limit"
  e2e_expect_err "--limit cannot be used with --choose-threshold"
  e2e_expect_equal "absent" "$([ -e "$E2E_DIR/threshold-lim.json" ] && echo present || echo absent)" "threshold file"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/dev/pairs.jsonl" --records "$E2E_DIR/dev/records" --dest "$E2E_DIR/sdev" --set dev --choose-threshold "$E2E_DIR/threshold.json"
  e2e_expect_equal 0 "$E2E_RC" "dev scorer exit status"
  # 113 evaluation pairs; all of them adopt (score-bar), and the records of
  # the 13 pass pairs past the limit are dropped, as a replay --limit 100
  # would not have written them.
  _synth "$E2E_DIR/e" "
eval agent c1 a fail no 0.97 73
eval agent c1 a pass hn 0.03 40"
  _py 'import json,sys
keep={json.loads(l)["ref"] for l in list(open(sys.argv[1]))[:100]}
ls=[l for l in open(sys.argv[2]) if json.loads(l)["ref"] in keep]
open(sys.argv[2],"w").write("".join(ls))' "$E2E_DIR/e/pairs.jsonl" "$E2E_DIR/e/records/real/system-one.jsonl"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e/pairs.jsonl" --records "$E2E_DIR/e/records" --dest "$E2E_DIR/se" --set eval --threshold-file "$E2E_DIR/threshold.json" --limit 100
  e2e_expect_equal 0 "$E2E_RC" "eval scorer exit status with --limit"
  e2e_expect_equal "inconclusive-limited 100 100" "$(_sum se 's["verdict"]["verdict"], s["limit"], s["pairs"]')" "verdict, limit and pairs scored"
  e2e_expect_equal "True" "$(grep -q 'only the first 100 (--limit)' "$E2E_DIR/se/summary.md" && echo True)" "summary.md names the limit"
  # A file holding both sets: --set eval --limit 5 scores five evaluation
  # pairs, not the first five lines of the file.
  _synth "$E2E_DIR/m" "
dev agent c1 a fail no 0.97 10
eval agent c1 a fail no 0.97 10"
  _py 'import json,sys
ev=[json.loads(l)["ref"] for l in open(sys.argv[1]) if json.loads(l)["set"]=="eval"][:5]
ls=[l for l in open(sys.argv[2]) if json.loads(l)["ref"] in ev]
open(sys.argv[2],"w").write("".join(ls))' "$E2E_DIR/m/pairs.jsonl" "$E2E_DIR/m/records/real/system-one.jsonl"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/m/pairs.jsonl" --records "$E2E_DIR/m/records" --dest "$E2E_DIR/sm" --set eval --limit 5
  e2e_expect_equal "0 5 eval" "$E2E_RC $(_sum sm 's["pairs"], s["set"]')" "exit status, pairs scored and set"
fi

if _want score-placebo-gap; then
  _setup score-placebo-gap "the placebo check passes when, averaged over the case-and-trap groups, the real-description AUC exceeds the placebo AUC by at least 0.15, the gap in each group is listed and not judged, and the placebo AUC alone, pooled or not, does not decide it"
  # One trap, 80 fail and 40 pass pairs; the real description orders them
  # perfectly (AUC 1). The placebo puts K fail pairs at 0.9, the other fail
  # pairs at 0.1 and every pass pair at 0.5, so its AUC is K/80 and the gap
  # is 1 - K/80: K=68 gives exactly 0.15, K=72 gives 0.10, K=56 gives 0.30
  # with a pooled placebo AUC of 0.7, far from 0.5.
  for DS_K in 68 72 56; do
    _synth "$E2E_DIR/d$DS_K" "
dev agent c1 a fail no 0.97 $DS_K shuffled=0.9
dev agent c1 a fail no 0.97 $((80 - DS_K)) shuffled=0.1
dev agent c1 a pass hn 0.03 40 shuffled=0.5"
    e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/d$DS_K/pairs.jsonl" --records "$E2E_DIR/d$DS_K/records" --dest "$E2E_DIR/s$DS_K" --set dev
    e2e_expect_equal 0 "$E2E_RC" "scorer exit status, K=$DS_K"
  done
  e2e_expect_equal "True dev-only-provisional" "$(_sum s68 's["checks"]["placebo"]["ok"], s["verdict"]["verdict"]')" "a gap of exactly 0.15: check and verdict"
  e2e_expect_equal "0.85 0.15" "$(_sum s68 's["checks"]["placebo"]["within"]["placebo_auc"], s["checks"]["placebo"]["within"]["gap"]')" "a gap of exactly 0.15: placebo AUC within case and trap, and the gap"
  e2e_expect_equal "False inconclusive-placebo" "$(_sum s72 's["checks"]["placebo"]["ok"], s["verdict"]["verdict"]')" "a gap of 0.10: check and verdict"
  e2e_expect_equal "0.9 0.1" "$(_sum s72 's["checks"]["placebo"]["within"]["placebo_auc"], s["checks"]["placebo"]["within"]["gap"]')" "a gap of 0.10: placebo AUC within case and trap, and the gap"
  e2e_expect_equal "True" "$(grep -q 'gap of 0.100, less than 0.15' "$E2E_DIR/s72/summary.md" && echo True)" "summary.md gives the gap that failed"
  e2e_expect_equal "0.7 True dev-only-provisional" "$(_sum s56 's["checks"]["placebo"]["auc"], s["checks"]["placebo"]["ok"], s["verdict"]["verdict"]')" "a pooled placebo AUC of 0.7 with a gap of 0.30: pooled AUC, check and verdict"
  e2e_expect_equal "0.3" "$(_sum s56 's["checks"]["placebo"]["within"]["gap"]')" "a pooled placebo AUC of 0.7: the gap"
  e2e_expect_equal "True" "$(grep -q 'placebo AUC reported, not judged: pooled 0.700' "$E2E_DIR/s56/summary.md" && echo True)" "summary.md reports the pooled placebo AUC as not judged"
  # Two traps with opposite shares of fail pairs and placebo answers that
  # order the tests perfectly within each trap. Pooled over 40 fail and 40
  # pass pairs: the 12 fail pairs at 0.9 beat all 40 pass pairs and the 28 at
  # 0.2 beat the 12 at 0.1, so AUC = (480 + 336) / 1600 = 0.51, within 0.05
  # of 0.5. Within each trap the placebo AUC is 1, as is the real one, so the
  # description adds nothing: a gap of 0.
  _synth "$E2E_DIR/h" "
dev agent c1 a fail no 0.97 12 shuffled=0.9
dev agent c1 a pass hn 0.03 28 shuffled=0.8
dev agent c1 b fail no 0.97 28 shuffled=0.2
dev agent c1 b pass hn 0.03 12 shuffled=0.1"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/h/pairs.jsonl" --records "$E2E_DIR/h/records" --dest "$E2E_DIR/sh" --set dev
  e2e_expect_equal "0 0.51 False inconclusive-placebo" "$E2E_RC $(_sum sh 's["checks"]["placebo"]["auc"], s["checks"]["placebo"]["ok"], s["verdict"]["verdict"]')" "a pooled placebo AUC near 0.5 that orders the tests within each trap: exit status, pooled AUC, check and verdict"
  e2e_expect_equal "2 1.0 0.0" "$(_sum sh 's["checks"]["placebo"]["within"]["groups"], s["checks"]["placebo"]["within"]["placebo_auc"], s["checks"]["placebo"]["within"]["gap"]')" "a pooled placebo AUC near 0.5: groups, placebo AUC within case and trap, and the gap"
  # The gap is judged on the averages over the case-and-trap groups, and the
  # gap in each group is listed and not judged. In trap a the placebo orders
  # the tests as well as the real description (gap 0); in trap b it ties
  # every pair (AUC 0.5, gap 0.5). Mean real 1.0, mean placebo 0.75, gap
  # 0.25: the check passes with one group under 0.15.
  _synth "$E2E_DIR/g" "
dev agent c1 a fail no 0.97 20 shuffled=0.9
dev agent c1 a pass hn 0.03 20 shuffled=0.1
dev agent c1 b fail no 0.97 20 shuffled=0.5
dev agent c1 b pass hn 0.03 20 shuffled=0.5"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/g/pairs.jsonl" --records "$E2E_DIR/g/records" --dest "$E2E_DIR/sg" --set dev
  e2e_expect_equal "0 0.25 True 1" "$E2E_RC $(_sum sg 's["checks"]["placebo"]["within"]["gap"], s["checks"]["placebo"]["ok"], s["checks"]["placebo"]["within"]["groups_under_min_gap"]')" "one group under 0.15, average gap 0.25: exit status, gap, check, groups under 0.15"
  e2e_expect_equal "agent/c1/a 0.0 True agent/c1/b 0.5 False" "$(_sum sg '" ".join("%s %s %s" % (g["group"], g["gap"], g["under_min_gap"]) for g in s["checks"]["placebo"]["within"]["per_group"])')" "per-group gaps listed, smallest first"
  e2e_expect_equal "True" "$(grep -q '^| agent/c1/a | 1.000 | 1.000 | 0.000 | yes |$' "$E2E_DIR/sg/summary.md" && grep -q '^| agent/c1/b | 1.000 | 0.500 | 0.500 |  |$' "$E2E_DIR/sg/summary.md" && echo True)" "summary.md lists the gap in each group"
  # No placebo answer at all: the gap cannot be computed, and the check
  # fails rather than passing or stopping the scorer.
  _synth "$E2E_DIR/n" "
dev agent c1 a fail no 0.97 80 shuffled=timeout
dev agent c1 a pass hn 0.03 40 shuffled=timeout"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/n/pairs.jsonl" --records "$E2E_DIR/n/records" --dest "$E2E_DIR/sn" --set dev
  e2e_expect_equal "0 0 False inconclusive-placebo" "$E2E_RC $(_sum sn 's["checks"]["placebo"]["within"]["groups"], s["checks"]["placebo"]["ok"], s["verdict"]["verdict"]')" "no placebo answer: exit status, groups, check and verdict"
  e2e_expect_equal "True" "$(grep -q 'gap not computed' "$E2E_DIR/sn/summary.md" && echo True)" "summary.md says the gap was not computed"
  # A threshold chosen on a dev set whose pooled placebo AUC is 0.7 with a
  # gap of 0.30 carries a passing placebo, so the evaluation set can adopt.
  DS_TS=2000-01-01T00:00:00Z _synth "$E2E_DIR/dev" "
dev agent c1 a fail no 0.97 56 shuffled=0.9
dev agent c1 a fail no 0.97 24 shuffled=0.1
dev agent c1 a pass hn 0.03 40 shuffled=0.5
dev author c1 a fail no 0.97 56 shuffled=0.9
dev author c1 a fail no 0.97 24 shuffled=0.1
dev author c1 a pass no 0.03 40 shuffled=0.5"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/dev/pairs.jsonl" --records "$E2E_DIR/dev/records" --dest "$E2E_DIR/sdev" --set dev --choose-threshold "$E2E_DIR/threshold.json"
  e2e_expect_equal "0 True" "$E2E_RC $(_py 'import json,sys; print(json.load(open(sys.argv[1]))["placebo"]["ok"])' "$E2E_DIR/threshold.json")" "dev scorer exit status and the placebo check in the threshold file"
  _synth "$E2E_DIR/e" "
eval agent c1 a fail no 0.97 73
eval agent c1 a pass hn 0.03 40"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e/pairs.jsonl" --records "$E2E_DIR/e/records" --dest "$E2E_DIR/se" --set eval --threshold-file "$E2E_DIR/threshold.json"
  e2e_expect_equal "0 adopt" "$E2E_RC $(_sum se 's["verdict"]["verdict"]')" "eval scorer exit status and verdict"
fi

if _want score-placebo-eval; then
  _setup score-placebo-eval "a placebo replayed on the evaluation set gates its verdict as it does on the dev set"
  DS_TS=2000-01-01T00:00:00Z _synth "$E2E_DIR/dev" "
dev agent c1 a fail no 0.97 80 shuffled=c:0.2,0.4,0.6,0.8
dev agent c1 a pass hn 0.03 40 shuffled=c:0.2,0.4,0.6,0.8
dev author c1 a fail no 0.97 80 shuffled=c:0.2,0.4,0.6,0.8
dev author c1 a pass no 0.03 20 shuffled=c:0.2,0.4,0.6,0.8"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/dev/pairs.jsonl" --records "$E2E_DIR/dev/records" --dest "$E2E_DIR/sdev" --set dev --choose-threshold "$E2E_DIR/threshold.json"
  e2e_expect_equal 0 "$E2E_RC" "dev scorer exit status"
  # The same answers as the adopting set of score-bar, with a placebo that
  # scores as well as the real description (pooled AUC 1.0).
  _synth "$E2E_DIR/e" "
eval agent c1 a fail no 0.97 73 shuffled=0.97
eval agent c1 a pass hn 0.03 40 shuffled=0.03"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e/pairs.jsonl" --records "$E2E_DIR/e/records" --dest "$E2E_DIR/se" --set eval --threshold-file "$E2E_DIR/threshold.json"
  e2e_expect_equal "0 False inconclusive-placebo" "$E2E_RC $(_sum se 's["checks"]["placebo"]["ok"], s["verdict"]["verdict"]')" "exit status, evaluation placebo and verdict"
fi

if _want smoke; then
  _setup smoke "the smoke pairs are five obvious catches and five obvious non-catches; replay --refs sends only them, smoke passes only answers on the right side of 0.5, and the spread of the pairs sent twice is reported and never stops it"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/export" --set dev --author
  e2e_expect_equal 0 "$E2E_RC" "export exit status"
  DS_PAIRS="$E2E_DIR/export/pairs.jsonl"
  DS_REFS="$REPO_ROOT/plugins/flow/evals/s1-discrimination/smoke-refs.txt"
  # Labels from traps.json, not from the exporter: a catch is a test listed
  # among its trap's discriminating tests.
  e2e_expect_equal "fail fail fail fail fail pass pass pass pass pass" "$(_py 'import json,sys,os
ps={json.loads(l)["ref"]:json.loads(l) for l in open(sys.argv[1])}
traps=json.load(open(os.path.join(sys.argv[3],"money-allocator","hidden","traps.json")))["traps"]
out=[]
for r in open(sys.argv[2]):
    r=r.strip()
    if not r or r.startswith("#"): continue
    p=ps[r]
    out.append("fail" if p["test_id"].rsplit(".",1)[-1] in traps[p["trap"]]["discriminating_tests"] else "pass")
print(" ".join(out))' "$DS_PAIRS" "$DS_REFS" "$DS_EVALS")" "the five catches and five non-catches, by traps.json"
  e2e_stub_start ts '{"body":{"model":"jev-1.13.0","answers":{"test_catches_wrong":{"type":"noul","noul":0.97}}}}'
  _provider_settings "$(e2e_stub_url ts)"
  e2e_run_bin bin/flow-s1-eval.sh replay --pairs "$DS_PAIRS" --records "$E2E_DIR/smoke" \
    --provider-settings "$E2E_DIR/provider.json" --scratch "$E2E_DIR/replay-scratch" --refs "$DS_REFS"
  e2e_expect_equal 0 "$E2E_RC" "replay exit status"
  e2e_expect_equal "10" "$(e2e_stub_requests ts)" "requests (the ten listed pairs)"
  e2e_expect_equal "same" "$(_py 'import json,sys
want=sorted(l.strip() for l in open(sys.argv[2]) if l.strip() and not l.startswith("#"))
got=sorted(json.loads(l)["ref"] for l in open(sys.argv[1]))
print("same" if got==want else got)' "$E2E_DIR/smoke/real/system-one.jsonl" "$DS_REFS")" "records for the listed refs"
  e2e_run_bin bin/flow-s1-eval.sh replay --pairs "$DS_PAIRS" --records "$E2E_DIR/smoke" \
    --provider-settings "$E2E_DIR/provider.json" --scratch "$E2E_DIR/replay-scratch" --refs "$DS_REFS" --sample 3 --records-name repeat
  e2e_expect_equal "0 13" "$E2E_RC $(e2e_stub_requests ts)" "repeat replay exit status and requests"
  # 0.97 everywhere: the five non-catches are on the wrong side of 0.5.
  e2e_run_bin bin/flow-s1-eval.sh smoke --pairs "$DS_PAIRS" --records "$E2E_DIR/smoke"
  e2e_expect_equal 1 "$E2E_RC" "smoke exit status, 0.97 everywhere"
  e2e_expect_err "label pass but p = 0.970, the wrong side of 0.5"
  e2e_expect_equal "5" "$(_py 'import json,sys; print(sum(1 for r in json.loads(sys.stdin.read())["pairs"] if not r["ok"]))' <<<"$E2E_OUT")" "pairs on the wrong side"
  # _smoke_set <real fail p> <real pass p> <repeat shift>: the records'
  # answers rewritten by label.
  _smoke_set() {
    _py 'import json,sys
ps={json.loads(l)["ref"]:json.loads(l)["label"] for l in open(sys.argv[1])}
for name,shift in (("real",0.0),("repeat",float(sys.argv[5]))):
    f="%s/%s/system-one.jsonl"%(sys.argv[2],name)
    rs=[json.loads(l) for l in open(f)]
    for r in rs:
        r["answer"]["p"]=round((float(sys.argv[3]) if ps[r["ref"]]=="fail" else float(sys.argv[4]))+shift,6)
    open(f,"w").write("".join(json.dumps(r)+"\n" for r in rs))' "$DS_PAIRS" "$E2E_DIR/smoke" "$1" "$2" "$3"
  }
  _smoke_set 0.97 0.03 0
  e2e_run_bin bin/flow-s1-eval.sh smoke --pairs "$DS_PAIRS" --records "$E2E_DIR/smoke"
  e2e_expect_equal "0 3" "$E2E_RC $(_py 'import json,sys; print(json.loads(sys.stdin.read())["sent_twice"])' <<<"$E2E_OUT")" "smoke exit status and pairs answered twice, answers on the right side"
  _smoke_set 0.03 0.97 0
  e2e_run_bin bin/flow-s1-eval.sh smoke --pairs "$DS_PAIRS" --records "$E2E_DIR/smoke"
  e2e_expect_equal 1 "$E2E_RC" "smoke exit status, answers read the wrong way round"
  e2e_expect_err "label fail but p = 0.030"
  # Each repeat 0.05 above its first answer (the smoke check of 2026-10-04
  # saw up to 0.10): reported, and the smoke check passes.
  _smoke_set 0.90 0.10 0.05
  e2e_run_bin bin/flow-s1-eval.sh smoke --pairs "$DS_PAIRS" --records "$E2E_DIR/smoke"
  e2e_expect_equal 0 "$E2E_RC" "smoke exit status, every repeat 0.05 away"
  e2e_expect_equal "3 0.05 0.05 3 3 []" "$(_py 'import json,sys; o=json.loads(sys.stdin.read()); r=o["repeatability"]; print(o["sent_twice"], r["largest_difference"], r["mean_difference"], r["over_0.02"], sum(1 for x in r["per_pair"] if x["difference"]==0.05), o["problems"])' <<<"$E2E_OUT")" "pairs sent twice, largest and mean difference, count above 0.02, per-pair differences, no problem"
  e2e_expect_err "same state sent twice (smaller is better; reported, does not stop): 3 pairs; the two answers differ by 0.050 at most and 0.050 on average; 3 differ by more than 0.02"
  e2e_expect_equal 3 "$(grep -cE '^flow-s1-eval: smoke:   eval:author/[^ ]+: 0\.(900|100) then 0\.(950|150), difference 0\.050$' <<<"$E2E_ERR")" "one stderr line per pair sent twice, with both answers and the difference"
  # A spread does not let answers on the wrong side through.
  _smoke_set 0.10 0.90 0.05
  e2e_run_bin bin/flow-s1-eval.sh smoke --pairs "$DS_PAIRS" --records "$E2E_DIR/smoke"
  e2e_expect_equal 1 "$E2E_RC" "smoke exit status, wrong way round with repeats 0.05 away"
  e2e_expect_err "label fail but p = 0.100"
  _smoke_set 0.97 0.03 0
  mv "$E2E_DIR/smoke/repeat" "$E2E_DIR/repeat-aside"
  e2e_run_bin bin/flow-s1-eval.sh smoke --pairs "$DS_PAIRS" --records "$E2E_DIR/smoke"
  e2e_expect_equal "0 0 None" "$E2E_RC $(_py 'import json,sys; o=json.loads(sys.stdin.read()); print(o["sent_twice"], o["repeatability"]["largest_difference"])' <<<"$E2E_OUT")" "smoke exit status without the repeat, nothing measured"
  e2e_expect_err "not measured: no pair was answered twice"
  printf 'eval:author/money-allocator/hidden/no_such_trap/000000000000\n' > "$E2E_DIR/bad-refs.txt"
  e2e_run_bin bin/flow-s1-eval.sh smoke --pairs "$DS_PAIRS" --records "$E2E_DIR/smoke" --refs "$E2E_DIR/bad-refs.txt"
  e2e_expect_equal 2 "$E2E_RC" "smoke exit status with a ref that is not a pair"
  e2e_expect_err "1 listed refs are not labelled pairs"
fi
