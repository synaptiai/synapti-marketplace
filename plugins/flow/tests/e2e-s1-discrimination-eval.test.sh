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
#   D29 the leak check reads a state as JSON text, so a description holding a
#       quote is escaped and never matched; or column 3 of expected.md in a
#       risk row passes
#   D30 a trap own-test-traps.json did not score, or an oracle test skipped
#       on a variant, is labelled pass
#   D31 a run whose own-test-traps.json is cut short or malformed crashes the
#       export; an --out with no runs gives an empty export and exit 0; a
#       usage error (an --out with no runs/, a cut list without --rescore,
#       two --out folders of one name, a ref over 200 characters) removes
#       the previous export
#   D32 --rescore accepts a run whose re-run moves tests between failing,
#       unobserved and pass on a trap
#   D33 the agent's suite runs with the operator's environment (an API key),
#       or a link in the agent's project puts an outside file in a state
#   D34 the replay sends a state outside the export's states/ folder or one
#       whose bytes are not the ones the pairs file records
#   D35 a settings file holding a list, a client that cannot be started, or
#       a pairs file that is missing or not JSON, or holds a pair with no
#       run or no real state, gives a traceback; an
#       --only-set that names no set sends nothing and exits 0
#   D36 a threshold t outside the sweep crashes the scorer; a set with no
#       pairs passes coverage; name-stripped records older than t pass;
#       score --limit reads the records past the limit as unknown refs; a
#       render that fails leaves a new summary.json or threshold file beside
#       an old summary.md; the clause lines and sweep tables give counts with no
#       coverage beside them
#   D37 the state builder's rename misses "def name (self)", or its --out and
#       --meta follow a link or give a traceback on a write error
#   D38 an input file the step did not write is read without its shape
#       checked: a traps.json, a pair, a record line, a threshold file or a
#       sampled state of another type gives a traceback, is read silently,
#       or (a state) is shown as what the provider received when its bytes
#       are not the ones the pairs file records
#   D39 a file the export or a step reads, or a value read from one that is
#       used as a path, is not checked when it is loaded: a case file that
#       is missing, not UTF-8 or not Python, a module name that is a path, a
#       variant outside the case, a project file that cannot be copied, a
#       suite that writes bytes that are not UTF-8, a pairs or refs line that
#       is not UTF-8, or a records folder that cannot be listed gives a
#       traceback, a file written outside the scratch project, or a field
#       read with a replacement character
#   D40 the re-run writes the reference or a variant through a link the
#       agent's project/ holds, over a file outside the scratch project
#   D41 a value a step passes on is checked less strictly than the command
#       that receives it checks it: a pair ref flow-s1.sh refuses, a records
#       folder or settings path holding a control character (flow-s1.sh
#       then ignores it and uses the user's own settings and state folder),
#       a records folder that is a link, or a state that is not a regular
#       file; or a client's stderr bytes that are not UTF-8 give a traceback
#   D42 a usage error of score or replay fires after the step has created
#       its --dest, its --scratch or the records folder
#
# FLOW_E2E_SCENARIOS=a,b runs only the named scenarios.

# Only tests/run.sh runs this file: it sets REPO_ROOT and loads assert.sh. Run
# any other way, the file stops here with a non-zero exit, because `return`
# alone does not stop a script that is executed rather than sourced, and the
# scenarios below would then run git in the current directory.
{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

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

# _tree_sum <dir> — one sha256 over every file's path and bytes under dir.
_tree_sum() {
  _py 'import hashlib,os,sys
h=hashlib.sha256()
for d,ds,fs in sorted(os.walk(sys.argv[1])):
    ds.sort()
    for f in sorted(fs):
        p=os.path.join(d,f)
        h.update(os.path.relpath(p,sys.argv[1]).encode()+b"\0"+open(p,"rb").read()+b"\0")
print(h.hexdigest())' "$1"
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

# The leak guard, computed here from traps.json and expected.md, not from the
# exporter: no trap description and no other discriminating test name in any
# field, no column 3 of expected.md in the risk row, and in an author state no
# trap name in any spelling and no word "trap". Each field is matched as the
# provider reads it; matched in the JSON text, a description holding a quote
# is escaped and never found. Args: <pairs.jsonl> <evals dir>.
IFS= read -r -d '' DS_LEAK_CHECK <<'PY' || true
import json, os, re, sys
d, ev = os.path.dirname(sys.argv[1]), sys.argv[2]
cases, masking = {}, {}
for c in os.listdir(ev):
    tj = os.path.join(ev, c, "hidden", "traps.json")
    if not os.path.isfile(tj):
        continue
    cases[c] = json.load(open(tj, encoding="utf-8"))["traps"]
    for line in open(os.path.join(ev, c, "expected.md"), encoding="utf-8"):
        m = re.match(r"^\|\s*`([A-Za-z0-9_]+)`\s*\|([^|]*)\|([^|]*)\|", line)
        if m:
            masking[(c, m.group(1))] = m.group(3).strip()
bad = []
for l in open(sys.argv[1], encoding="utf-8"):
    p = json.loads(l)
    for ab, s in p["states"].items():
        st = json.load(open(os.path.join(d, s["path"]), encoding="utf-8"))
        own = st["test"]["id"].rsplit(".", 1)[-1]
        risk = [st["risk"]["area"], st["risk"]["plausible_wrong_version"]]
        src = st["test"]["source"]
        fields = [st["spec"], st["test"]["id"], src] + risk
        for c, traps in cases.items():
            for name, t in traps.items():
                if any(t["description"] in f for f in fields):
                    bad.append((p["ref"], ab, "description"))
                for dt in t["discriminating_tests"]:
                    if dt != own and any(re.search(r"\b%s\b" % re.escape(dt), f) for f in fields):
                        bad.append((p["ref"], ab, dt))
                if masking.get((c, name)) and any(masking[(c, name)] in f for f in risk):
                    bad.append((p["ref"], ab, "column 3"))
                if p["stratum"] == "author":
                    for sp in (name, name.replace("_", "-"), name.replace("_", " ")):
                        if sp in src:
                            bad.append((p["ref"], ab, "trap name " + sp))
        if p["stratum"] == "author" and re.search(r"trap", src, re.I):
            bad.append((p["ref"], ab, "word trap"))
print("no leak" if not bad else repr(bad[:5]))
PY

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

  # A def line spaced as "def name (self)" is renamed all the same.
  cat > "$E2E_DIR/spaced_test.py" <<'EOF'
import unittest


class T(unittest.TestCase):
    def test_spaced (self):
        self.assertEqual(1, 1)
EOF
  e2e_run_bin bin/flow-test-state.sh --test-file "$E2E_DIR/spaced_test.py" --test-id T.test_spaced --area a \
    --wrong-version w --spec-file "$DS_P/ISSUE.md" --rename-test test_x
  e2e_expect_equal 0 "$E2E_RC" "exit status (rename a spaced def line)"
  # The independent check of the rename: a literal line, not the regex the
  # pair-export scenario shares with the state builder.
  e2e_expect_out "def test_x (self):"
  e2e_expect_no_out "test_spaced"
  # --out and --meta: a link there is refused, never followed, and a path
  # that cannot be written is a usage error, not a traceback.
  printf 'KEEP-TARGET\n' > "$E2E_DIR/target.txt"
  ln -s "$E2E_DIR/target.txt" "$E2E_DIR/out-link.json"
  for DS_OPT in --out --meta; do
    e2e_run_bin bin/flow-test-state.sh --test-file "$E2E_DIR/spaced_test.py" --test-id T.test_spaced --area a \
      --wrong-version w --spec-file "$DS_P/ISSUE.md" "$DS_OPT" "$E2E_DIR/out-link.json"
    e2e_expect_equal 2 "$E2E_RC" "exit status with a link at $DS_OPT"
    e2e_expect_err "flow-test-state: cannot write $E2E_DIR/out-link.json"
    e2e_expect_equal "KEEP-TARGET" "$(cat "$E2E_DIR/target.txt")" "the file the $DS_OPT link points to is unchanged"
    e2e_run_bin bin/flow-test-state.sh --test-file "$E2E_DIR/spaced_test.py" --test-id T.test_spaced --area a \
      --wrong-version w --spec-file "$DS_P/ISSUE.md" "$DS_OPT" "$E2E_DIR/no-such-dir/x.json"
    e2e_expect_equal 2 "$E2E_RC" "exit status when $DS_OPT cannot be written"
    e2e_expect_err "flow-test-state: cannot write $E2E_DIR/no-such-dir/x.json"
    e2e_expect_err_lacks "Traceback"
  done
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
  e2e_expect_equal "no leak" "$(_py "$DS_LEAK_CHECK" "$DS_PAIRS" "$DS_EVALS")" "no state carries the answer"
  e2e_expect_equal "column 2" "$(_py 'import json,sys,os
d=os.path.dirname(sys.argv[1])
for l in open(sys.argv[1]):
    p=json.loads(l)
    if p["case"]=="money-allocator" and p["trap"]=="ties_last_first":
        st=json.load(open(os.path.join(d,p["states"]["real"]["path"])))
        print("column 2" if st["risk"]=={"area":"ties last first","plausible_wrong_version":"Remainder ties go to the highest index"} else st["risk"]); break' "$DS_PAIRS")" "risk row is the trap name and expected.md column 2"
  e2e_expect_equal "ok" "$(_py 'import json,sys,os,re
d=os.path.dirname(sys.argv[1])
for l in open(sys.argv[1]):
    p=json.loads(l)
    real=json.load(open(os.path.join(d,p["states"]["real"]["path"])))
    ns=json.load(open(os.path.join(d,p["states"]["name-stripped"]["path"])))
    sh=json.load(open(os.path.join(d,p["states"]["shuffled"]["path"])))
    name=real["test"]["id"].rsplit(".",1)[-1]
    want=re.sub(r"^(\s*(?:async\s+)?def\s+)%s(\s*\()"%re.escape(name), lambda m: m.group(1)+"test_x"+m.group(2), real["test"]["source"], count=1, flags=re.M)
    if ns["test"]["source"]!=want or not ns["test"]["id"].endswith(".test_x") and ns["test"]["id"]!="test_x": print("name-stripped",p["ref"]); sys.exit()
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
  # own.orig.json is edited by the cases below; own.pristine.json is not.
  cp "$DS_RUN/own-test-traps.json" "$E2E_DIR/own.pristine.json"
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
  rm -r "$DS_OUT/runs/claude-sonnet-5/baseline/money-allocator/2"

  # A trap of the case that own-test-traps.json did not score: its pairs
  # would read "every oracle test passes" against a variant that never ran.
  _py 'import json,sys
d=json.load(open(sys.argv[1]))
t=next(n for n,v in sorted(d["per_trap"].items()) if not v["failing_count"] and not v["unobserved_count"])
del d["per_trap"][t]
json.dump(d,open(sys.argv[2],"w"))' "$E2E_DIR/own.pristine.json" "$DS_RUN/own-test-traps.json"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x8" --set dev --out "$DS_OUT"
  e2e_expect_equal 0 "$E2E_RC" "exit status with a trap own-test-traps.json did not score"
  e2e_expect_equal "0 True" "$(wc -l < "$E2E_DIR/x8/pairs.jsonl" | tr -d ' ') $(_py 'import json,sys
e=json.load(open(sys.argv[1]))["excluded_runs"]
print(len(e)==1 and "scores traps" in e[0]["reason"])' "$E2E_DIR/x8/export.json")" "pairs from that run, and the run listed as not scoring every trap"

  # own-test-traps.json cut short, holding a count that is not a number, or
  # holding a list of test ids that is not a list of strings (the export
  # sorts those lists): the run is left out with the reason, and the export
  # goes on.
  for DS_BAD in cut count ownids refids unobserved; do
    if [ "$DS_BAD" = cut ]; then
      printf '{"catch_rate": 0.5, "per_trap": {' > "$DS_RUN/own-test-traps.json"
    else
      _py 'import json,sys
d=json.load(open(sys.argv[1]))
t=sorted(d["per_trap"])[0]
bad=sys.argv[3]
if bad=="count": d["per_trap"][t]["failing_count"]="x"
elif bad=="ownids": d["own_impl"]["failed_ids"]=5
elif bad=="refids": d["reference_run"]["failed_ids"]=["x",1]
else: d["unobserved_on_reference"]=7
json.dump(d,open(sys.argv[2],"w"))' "$E2E_DIR/own.pristine.json" "$DS_RUN/own-test-traps.json" "$DS_BAD"
    fi
    e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x9$DS_BAD" --set dev --out "$DS_OUT"
    e2e_expect_equal 0 "$E2E_RC" "exit status with own-test-traps.json $DS_BAD"
    e2e_expect_err_lacks "Traceback"
    e2e_expect_equal "True" "$(_py 'import json,sys
e=json.load(open(sys.argv[1]))["excluded_runs"]
want={"cut":"own-test-traps.json cannot be read","count":"is not a count",
      "ownids":"own_impl.failed_ids is not a list of test ids",
      "refids":"reference_run.failed_ids is not a list of test ids",
      "unobserved":"unobserved_on_reference is not a list of test ids"}[sys.argv[2]]
print(len(e)==1 and want in e[0]["reason"])' "$E2E_DIR/x9$DS_BAD/export.json" "$DS_BAD")" "the run is listed as excluded, with the reason for own-test-traps.json $DS_BAD"
  done

  # --rescore: a trap whose re-run leaves a different number of tests
  # unobserved than own-test-traps.json stored (here one stored, none on the
  # re-run); the fail pairs alone still add up.
  _py 'import json,sys
d=json.load(open(sys.argv[1]))
t=next(n for n,v in sorted(d["per_trap"].items()) if not v["failing_count"] and not v["unobserved_count"])
d["per_trap"][t]["unobserved_count"]=1
json.dump(d,open(sys.argv[2],"w")); print(t)' "$E2E_DIR/own.pristine.json" "$DS_RUN/own-test-traps.json" > "$E2E_DIR/moved-trap.txt"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x10" --set dev --out "$DS_OUT" --rescore
  e2e_expect_equal 0 "$E2E_RC" "exit status with --rescore and a stored unobserved count the re-run does not give"
  e2e_expect_equal "0 True" "$(wc -l < "$E2E_DIR/x10/pairs.jsonl" | tr -d ' ') $(_py 'import json,sys
e=json.load(open(sys.argv[1]))["excluded_runs"]
t=open(sys.argv[2]).read().strip()
print(True if len(e)==1 and "unobserved counts for "+t in e[0]["reason"] else e)' "$E2E_DIR/x10/export.json" "$E2E_DIR/moved-trap.txt")" "pairs from that run, and the run listed with the trap whose counts moved"

  # A usage error stops the export before the previous one is touched: a
  # cut list without --rescore, an --out with no runs/, two --out folders
  # of one name (their refs would be the same), and an --out whose name
  # makes a ref longer than 200 characters each leave pairs.jsonl,
  # export.json and states/ as the first export wrote them.
  cp "$E2E_DIR/own.pristine.json" "$DS_RUN/own-test-traps.json"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x11" --set dev --out "$DS_OUT"
  e2e_expect_equal "0 present" "$E2E_RC $([ -s "$E2E_DIR/x11/pairs.jsonl" ] && [ -f "$E2E_DIR/x11/export.json" ] && [ -d "$E2E_DIR/x11/states" ] && echo present || echo absent)" "a first export into the folder"
  DS_X11_SUM=$(_tree_sum "$E2E_DIR/x11")
  mkdir -p "$E2E_DIR/no-runs-x11" "$E2E_DIR/twin"
  cp -R "$DS_OUT" "$E2E_DIR/twin/runA"
  DS_LONG="$E2E_DIR/$(printf 'o%.0s' $(seq 1 120))"
  cp -R "$DS_OUT" "$DS_LONG"
  _py 'import json,sys
d=json.load(open(sys.argv[1]))
t=next(n for n,v in sorted(d["per_trap"].items()) if v["failing_own_tests"])
d["per_trap"][t]["failing_own_tests"].pop()
json.dump(d,open(sys.argv[2],"w"))' "$E2E_DIR/own.pristine.json" "$DS_RUN/own-test-traps.json"
  for DS_U in cut no-runs twin long; do
    case $DS_U in
      cut) DS_ARGS=(--out "$DS_OUT"); DS_MSG="failing_count or unobserved_count is above the stored list" ;;
      no-runs) DS_ARGS=(--out "$E2E_DIR/no-runs-x11"); DS_MSG="has no runs/ directory" ;;
      twin) DS_ARGS=(--out "$DS_OUT" --out "$E2E_DIR/twin/runA" --rescore); DS_MSG="have the same name" ;;
      long) DS_ARGS=(--out "$DS_LONG" --rescore); DS_MSG="ref longer than 200 characters" ;;
    esac
    e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x11" --set dev "${DS_ARGS[@]}"
    e2e_expect_equal 2 "$E2E_RC" "exit status of a second export that stops on a usage error, $DS_U"
    e2e_expect_err "$DS_MSG"
    e2e_expect_err_lacks "Traceback"
    e2e_expect_equal "$DS_X11_SUM" "$(_tree_sum "$E2E_DIR/x11")" "the first export's pairs.jsonl, export.json and states/ are kept whole, $DS_U"
  done
  cp "$E2E_DIR/own.pristine.json" "$DS_RUN/own-test-traps.json"

  # An --out with no runs/ folder, and one whose runs/ holds no run.
  mkdir -p "$E2E_DIR/no-runs" "$E2E_DIR/empty-out/runs"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x12" --set dev --out "$E2E_DIR/no-runs"
  e2e_expect_equal 2 "$E2E_RC" "exit status for an --out with no runs/"
  e2e_expect_err "has no runs/ directory"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x13" --set dev --out "$E2E_DIR/empty-out"
  e2e_expect_equal 2 "$E2E_RC" "exit status for an --out with no run"
  e2e_expect_err "holds no run under runs/"
fi

# ----------------------------------------------- export: leaks in the cases
if _want export-leak; then
  _setup export-leak "a trap description holding a quote, or column 3 of expected.md in a risk row, stops the export as a leak; a case without its ISSUE.md is a usage error; the scenarios' own leak check reads each field as sent"
  mkdir -p "$E2E_DIR/evals"
  DS_CASE="$E2E_DIR/evals/money-allocator"
  cp -R "$DS_EVALS/money-allocator" "$DS_CASE"
  cp -R "$DS_CASE" "$E2E_DIR/case.orig"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$E2E_DIR/evals" --dest "$E2E_DIR/x0" --set dev --author
  e2e_expect_equal 0 "$E2E_RC" "exit status on the case as shipped"
  # A description with a quote, written into the spec. In JSON text the
  # quote is escaped, so a check on that text would never find it.
  _py 'import json,sys
d=json.load(open(sys.argv[1]))
d["traps"]["ties_last_first"]["description"]="Trap: a tie goes to the \"last\" index first"
json.dump(d,open(sys.argv[1],"w"),indent=2)
open(sys.argv[2],"a").write("\nA tie: Trap: a tie goes to the \"last\" index first\n")' "$DS_CASE/hidden/traps.json" "$DS_CASE/scaffold/ISSUE.md"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$E2E_DIR/evals" --dest "$E2E_DIR/x1" --set dev --author
  e2e_expect_equal 2 "$E2E_RC" "exit status with a quoted description in the spec"
  e2e_expect_err "the description of trap ties_last_first"
  # The scenarios' own check finds the same description in a state, and
  # nothing in the export of the case as shipped.
  _py 'import json,sys,os
src,dst=sys.argv[1],sys.argv[2]
p=json.loads(open(os.path.join(src,"pairs.jsonl")).readline())
st=json.load(open(os.path.join(src,p["states"]["real"]["path"])))
st["spec"]+="\nTrap: a tie goes to the \"last\" index first\n"
os.makedirs(os.path.join(dst,"states"))
json.dump(st,open(os.path.join(dst,"states","x.json"),"w"),ensure_ascii=False)
p["states"]={"real":{"path":"states/x.json","sha256":"-"}}
open(os.path.join(dst,"pairs.jsonl"),"w").write(json.dumps(p)+"\n")' "$E2E_DIR/x0" "$E2E_DIR/planted"
  DS_PLANTED=$(_py "$DS_LEAK_CHECK" "$E2E_DIR/planted/pairs.jsonl" "$E2E_DIR/evals")
  case "$DS_PLANTED" in
    *"'description'"*) _e2e_result pass "the scenarios' own check finds the quoted description in a state" ;;
    *) _e2e_result fail "the scenarios' own check finds the quoted description in a state (got: $DS_PLANTED)" ;;
  esac
  e2e_expect_equal "no leak" "$(_py "$DS_LEAK_CHECK" "$E2E_DIR/x0/pairs.jsonl" "$E2E_DIR/evals")" "the scenarios' own check on the export of the shipped case"
  # Column 3 inside column 2: the risk row would carry the input that masks
  # the trap.
  rm -r "$DS_CASE" && cp -R "$E2E_DIR/case.orig" "$DS_CASE"
  _py 'import sys
s=open(sys.argv[1]).read()
old="| Remainder ties go to the highest index | No tied remainders |"
assert old in s
open(sys.argv[1],"w").write(s.replace(old,"| Remainder ties go to the highest index, or No tied remainders | No tied remainders |"))' "$DS_CASE/expected.md"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$E2E_DIR/evals" --dest "$E2E_DIR/x2" --set dev --author
  e2e_expect_equal 2 "$E2E_RC" "exit status with column 3 in a risk row"
  e2e_expect_err "column 3 of expected.md for trap ties_last_first"
  # A case without its ISSUE.md.
  rm -r "$DS_CASE" && cp -R "$E2E_DIR/case.orig" "$DS_CASE"
  rm "$DS_CASE/scaffold/ISSUE.md"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$E2E_DIR/evals" --dest "$E2E_DIR/x3" --set dev --author
  e2e_expect_equal 2 "$E2E_RC" "exit status for a case without its ISSUE.md"
  e2e_expect_err "cannot read $DS_CASE/scaffold/ISSUE.md"
  e2e_expect_err_lacks "Traceback"
fi

if _want export-traps-file; then
  _setup export-traps-file "a case whose hidden/traps.json is not JSON, not an object with a module and traps, or holds a trap without a variant path, a description that is not a string or discriminating tests that are not a list of names stops the export with a usage error naming the file, never a traceback"
  mkdir -p "$E2E_DIR/evals"
  DS_CASE="$E2E_DIR/evals/money-allocator"
  cp -R "$DS_EVALS/money-allocator" "$E2E_DIR/case.orig"
  for DS_F in notjson list notraps trapstr novariant desc dtstr; do
    rm -r "$DS_CASE" 2>/dev/null
    cp -R "$E2E_DIR/case.orig" "$DS_CASE"
    _py 'import json,sys
f,k=sys.argv[1],sys.argv[2]
d=json.load(open(f))
t=d["traps"]["ties_last_first"]
if k=="notjson": open(f,"w").write("{\"module\""); sys.exit(0)
if k=="list": d=[1]
elif k=="notraps": del d["traps"]
elif k=="trapstr": d["traps"]["ties_last_first"]="x"
elif k=="novariant": del t["variant"]
elif k=="desc": t["description"]=5
elif k=="dtstr": t["discriminating_tests"]=t["discriminating_tests"][0]
json.dump(d,open(f,"w"),indent=2)' "$DS_CASE/hidden/traps.json" "$DS_F"
    case $DS_F in
      notjson) DS_MSG="$DS_CASE/hidden/traps.json cannot be read" ;;
      list|notraps) DS_MSG="$DS_CASE/hidden/traps.json is not a traps file" ;;
      trapstr|novariant) DS_MSG="$DS_CASE/hidden/traps.json: trap ties_last_first is not an object with a variant path" ;;
      desc) DS_MSG="$DS_CASE/hidden/traps.json: trap ties_last_first has a description that is not a string" ;;
      dtstr) DS_MSG="$DS_CASE/hidden/traps.json: trap ties_last_first has discriminating_tests that is not a list of test names" ;;
    esac
    e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$E2E_DIR/evals" --dest "$E2E_DIR/x-$DS_F" --set dev --author
    e2e_expect_equal 2 "$E2E_RC" "exit status, a traps file that is $DS_F"
    e2e_expect_err "$DS_MSG"
    e2e_expect_err_lacks "Traceback"
  done
fi

# ------------------------------------- export: every case file it reads
if _want export-case-files; then
  _setup export-case-files "a case whose expected.md is not UTF-8, whose hidden suite is missing, not UTF-8 or not Python, or an --evals-dir that is not there, stops the export with a usage error naming the file before the previous export is touched, never a traceback"
  mkdir -p "$E2E_DIR/evals"
  DS_CASE="$E2E_DIR/evals/money-allocator"
  cp -R "$DS_EVALS/money-allocator" "$E2E_DIR/case.orig"
  for DS_F in expected-bytes suite-missing suite-bytes suite-syntax suite-null; do
    rm -r "$DS_CASE" 2>/dev/null
    cp -R "$E2E_DIR/case.orig" "$DS_CASE"
    case $DS_F in
      expected-bytes) printf '\377\n' >> "$DS_CASE/expected.md"; DS_MSG="cannot read $DS_CASE/expected.md" ;;
      suite-missing) rm "$DS_CASE/hidden/test_hidden.py"; DS_MSG="cannot read $DS_CASE/hidden/test_hidden.py" ;;
      suite-bytes) printf '# \377\n' >> "$DS_CASE/hidden/test_hidden.py"; DS_MSG="cannot read $DS_CASE/hidden/test_hidden.py" ;;
      suite-syntax) printf 'def broken(:\n' >> "$DS_CASE/hidden/test_hidden.py"; DS_MSG="cannot parse $DS_CASE/hidden/test_hidden.py" ;;
      suite-null) printf 'x = 1\000\n' >> "$DS_CASE/hidden/test_hidden.py"; DS_MSG="cannot parse $DS_CASE/hidden/test_hidden.py" ;;
    esac
    # A previous export in the destination: a usage error at load time
    # leaves it as it was.
    mkdir -p "$E2E_DIR/x-$DS_F" && printf 'PREVIOUS\n' > "$E2E_DIR/x-$DS_F/pairs.jsonl"
    e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$E2E_DIR/evals" --dest "$E2E_DIR/x-$DS_F" --set dev --author
    e2e_expect_equal 2 "$E2E_RC" "exit status, a case whose $DS_F"
    e2e_expect_err "$DS_MSG"
    e2e_expect_err_lacks "Traceback"
    e2e_expect_equal "PREVIOUS" "$(cat "$E2E_DIR/x-$DS_F/pairs.jsonl")" "the previous export is kept, a case whose $DS_F"
  done
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$E2E_DIR/no-such-evals" --dest "$E2E_DIR/x-nodir" --set dev --author
  e2e_expect_equal 2 "$E2E_RC" "exit status, an --evals-dir that is not there"
  e2e_expect_err "--evals-dir cannot be listed"
  e2e_expect_err_lacks "Traceback"
fi

# ------------- export: a module name or variant path that is not the case's
# The re-run writes <module>.py into its scratch project and copies each
# variant over it, so a module name that is a path writes outside the scratch
# project, and a variant outside the case is copied in as a trap. TMPDIR is
# the scenario's own, so a write outside the scratch project lands where the
# scenario can see it.
if _want export-module-variant; then
  _setup export-module-variant "with --out (and --rescore for the variants), a traps.json module that is not a Python module name, a variant that is not a regular file inside the case, or a case without hidden/reference_impl.py stops the export with a usage error naming the file, never a traceback or a file written outside the scratch project"
  mkdir -p "$E2E_DIR/evals" "$E2E_DIR/tmp/t"
  DS_CASE="$E2E_DIR/evals/money-allocator"
  cp -R "$DS_EVALS/money-allocator" "$E2E_DIR/case.orig"
  DS_OUT="$E2E_DIR/runM"
  _agent_run "$DS_OUT/runs/claude-sonnet-5/baseline/money-allocator/1"
  printf 'from reference_impl import *\n' > "$E2E_DIR/evals/outside.py"
  for DS_F in mod-slash mod-up mod-reference mod-keyword var-missing var-up var-abs var-dir var-link ref-missing; do
    rm -r "$DS_CASE" 2>/dev/null
    cp -R "$E2E_DIR/case.orig" "$DS_CASE"
    rm -f "$E2E_DIR/tmp/t/x.py"
    _py 'import json,sys
f,k,outside=sys.argv[1],sys.argv[2],sys.argv[3]
d=json.load(open(f))
t=d["traps"]["ties_last_first"]
if k=="mod-slash": d["module"]="a/b"
elif k=="mod-up": d["module"]="../../x"
elif k=="mod-reference": d["module"]="reference_impl"
elif k=="mod-keyword": d["module"]="class"
elif k=="var-missing": t["variant"]="hidden/traps/no_such_variant.py"
elif k=="var-up": t["variant"]="../outside.py"
elif k=="var-abs": t["variant"]=outside
elif k=="var-dir": t["variant"]="hidden/traps"
elif k=="var-link": t["variant"]="hidden/traps/linked.py"
json.dump(d,open(f,"w"),indent=2)' "$DS_CASE/hidden/traps.json" "$DS_F" "$E2E_DIR/evals/outside.py"
    case $DS_F in
      mod-*) DS_MSG="$DS_CASE/hidden/traps.json: module" ;;
      var-*) DS_MSG="$DS_CASE/hidden/traps.json: trap ties_last_first has variant" ;;
      ref-missing) rm "$DS_CASE/hidden/reference_impl.py"; DS_MSG="$DS_CASE/hidden/reference_impl.py is not a regular file inside the case" ;;
    esac
    [ "$DS_F" = var-link ] && ln -s "$E2E_DIR/evals/outside.py" "$DS_CASE/hidden/traps/linked.py"
    e2e_run_bin "TMPDIR=$E2E_DIR/tmp/t" bin/flow-s1-eval.sh pairs --evals-dir "$E2E_DIR/evals" --dest "$E2E_DIR/x-$DS_F" --set dev --out "$DS_OUT" --rescore
    e2e_expect_equal 2 "$E2E_RC" "exit status, $DS_F"
    e2e_expect_err "$DS_MSG"
    e2e_expect_err_lacks "Traceback"
    e2e_expect_equal "absent" "$([ -e "$E2E_DIR/tmp/t/x.py" ] && echo present || echo absent)" "no file written outside the scratch project, $DS_F"
  done
  # The case as shipped still exports with --rescore.
  rm -r "$DS_CASE" && cp -R "$E2E_DIR/case.orig" "$DS_CASE"
  e2e_run_bin "TMPDIR=$E2E_DIR/tmp/t" bin/flow-s1-eval.sh pairs --evals-dir "$E2E_DIR/evals" --dest "$E2E_DIR/x-ok" --set dev --out "$DS_OUT" --rescore
  e2e_expect_equal 0 "$E2E_RC" "exit status on the case as shipped, with --rescore"
  e2e_expect_equal "1 0" "$(_py 'import json,sys
e=json.load(open(sys.argv[1])); print(len(e["runs"]), len(e["excluded_runs"]))' "$E2E_DIR/x-ok/export.json")" "the run gives pairs on the case as shipped"
fi

# ---------------- export: what the re-run reads from the agent's project
if _want export-run-reads; then
  _setup export-run-reads "a run whose project/ holds a file that cannot be copied is left out with the reason, and a suite that writes bytes that are not UTF-8 is re-run, never a traceback"
  DS_OUT="$E2E_DIR/runR"
  DS_RUN="$DS_OUT/runs/claude-sonnet-5/baseline/money-allocator/1"
  DS_CASE="$DS_EVALS/money-allocator"
  _agent_run "$DS_RUN"
  # The module writes two bytes that are not UTF-8 when it is imported, once
  # a marker is in place: own-test-traps.json is written without it, so the
  # stored oracle set is the one the re-run must reproduce.
  cat >> "$DS_RUN/project/allocate.py" <<'EOF'

import os as _os
import sys as _sys
if _os.path.exists(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)), "emit-bytes")):
    _sys.stderr.buffer.write(b"\xff\xfe\n")
    _sys.stderr.flush()
EOF
  python3 "$DS_HELPER" own-test-traps --case-dir "$DS_CASE" --project-dir "$DS_RUN/project" \
    --out "$DS_RUN/own-test-traps.json" >/dev/null 2>&1
  : > "$DS_RUN/project/emit-bytes"
  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x-bytes" --set dev --out "$DS_OUT"
  e2e_expect_equal 0 "$E2E_RC" "exit status, a suite that writes bytes that are not UTF-8"
  e2e_expect_err_lacks "Traceback"
  e2e_expect_equal "1 0" "$(_py 'import json,sys
e=json.load(open(sys.argv[1])); print(len(e["runs"]), len(e["excluded_runs"]))' "$E2E_DIR/x-bytes/export.json")" "the run gives pairs"
  if [ "$(id -u)" != 0 ]; then
    printf 'secret\n' > "$DS_RUN/project/unreadable.txt"
    chmod 000 "$DS_RUN/project/unreadable.txt"
    e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x-copy" --set dev --out "$DS_OUT"
    chmod 644 "$DS_RUN/project/unreadable.txt"
    e2e_expect_equal 0 "$E2E_RC" "exit status, a project file that cannot be copied"
    e2e_expect_err_lacks "Traceback"
    e2e_expect_equal "True" "$(_py 'import json,sys
e=json.load(open(sys.argv[1]))["excluded_runs"]
print(len(e)==1 and "project/ cannot be copied" in e[0]["reason"] and "unreadable.txt" in e[0]["reason"])' "$E2E_DIR/x-copy/export.json")" "the run is left out, naming the file"
  fi
fi

# ------------- export: a link in project/ where the re-run writes a file
# The re-run copies the reference over <module>.py and to reference_impl.py
# in its copy of project/, which keeps links. A link there must leave the
# run out, never send the reference to the file it points to.
if _want export-run-links; then
  _setup export-run-links "a run whose project/allocate.py or project/reference_impl.py is a link to a file outside project/ is left out with the reason, and the file the link points to is unchanged"
  DS_CASE="$DS_EVALS/money-allocator"
  for DS_L in allocate reference_impl; do
    DS_OUT="$E2E_DIR/run-$DS_L"
    DS_RUN="$DS_OUT/runs/claude-sonnet-5/baseline/money-allocator/1"
    _agent_run "$DS_RUN"
    if [ "$DS_L" = allocate ]; then
      mv "$DS_RUN/project/allocate.py" "$E2E_DIR/target-$DS_L.py"
    else
      printf '# the agent own reference_impl, outside project/\n' > "$E2E_DIR/target-$DS_L.py"
    fi
    # own-test-traps.json is the one _agent_run wrote before the link: the
    # agent's tests never import reference_impl, and allocate.py keeps its
    # bytes, so the re-run on the agent's module gives the stored results.
    ln -s "$E2E_DIR/target-$DS_L.py" "$DS_RUN/project/$DS_L.py"
    DS_BEFORE=$(_py 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$E2E_DIR/target-$DS_L.py")
    e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x-$DS_L" --set dev --out "$DS_OUT" --rescore
    e2e_expect_equal 0 "$E2E_RC" "exit status, project/$DS_L.py a link"
    e2e_expect_err_lacks "Traceback"
    e2e_expect_equal "$DS_BEFORE" "$(_py 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$E2E_DIR/target-$DS_L.py")" "the file project/$DS_L.py links to is unchanged"
    e2e_expect_equal "True" "$(_py 'import json,sys
e=json.load(open(sys.argv[1]))
print(len(e["runs"])==0 and len(e["excluded_runs"])==1 and (sys.argv[2]+".py is a link or not a regular file") in e["excluded_runs"][0]["reason"])' "$E2E_DIR/x-$DS_L/export.json" "$DS_L")" "the run is left out, naming project/$DS_L.py"
  done
fi

# ------------------- replay, score, smoke: a pairs or refs file not UTF-8
if _want utf8-inputs; then
  _setup utf8-inputs "a pairs file or a --refs file holding a byte that is not UTF-8, and a records folder that cannot be listed, stop with the path and line (the scorer with harness-error), never a traceback or a field read with a replacement character"
  mkdir -p "$E2E_DIR/p" "$E2E_DIR/records"
  DS_PAIR='{"ref": "eval:author/c/hidden/t/000000000001", "set": "dev", "stratum": "author", "case": "c", "run": "hidden", "trap": "t", "label": "fail", "hn_behavioral": false, "states": {}}'
  printf '%s\n' "$DS_PAIR" > "$E2E_DIR/p/good.jsonl"
  printf '{"ref": "eval:author/c/hidden/t/000000000001", "set": "dev", "stratum": "author", "case": "c\377", "run": "hidden", "trap": "t", "label": "fail", "hn_behavioral": false, "states": {}}\n' > "$E2E_DIR/p/bad.jsonl"
  e2e_expect_equal "1" "$(LC_ALL=C grep -c "$(printf '\377')" "$E2E_DIR/p/bad.jsonl")" "fixture: the bad pairs file holds the byte"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/p/bad.jsonl" --records "$E2E_DIR/records" --dest "$E2E_DIR/s"
  e2e_expect_equal 2 "$E2E_RC" "exit status, score on a pairs file that is not UTF-8"
  e2e_expect_err "$E2E_DIR/p/bad.jsonl line 1 is not UTF-8"
  e2e_expect_err_lacks "Traceback"
  printf 'eval:author/c/hidden/t/000000000001\n# \377\n' > "$E2E_DIR/p/refs.txt"
  e2e_run_bin bin/flow-s1-eval.sh smoke --pairs "$E2E_DIR/p/good.jsonl" --records "$E2E_DIR/records" --refs "$E2E_DIR/p/refs.txt"
  e2e_expect_equal 2 "$E2E_RC" "exit status, smoke with a --refs file that is not UTF-8"
  e2e_expect_err "$E2E_DIR/p/refs.txt line 2 is not UTF-8"
  e2e_expect_err_lacks "Traceback"
  printf '{}\n' > "$E2E_DIR/p/settings.json"
  e2e_run_bin bin/flow-s1-eval.sh replay --pairs "$E2E_DIR/p/good.jsonl" --records "$E2E_DIR/records" --provider-settings "$E2E_DIR/p/settings.json" --scratch "$E2E_DIR/replay-scratch" --refs "$E2E_DIR/p/refs.txt"
  e2e_expect_equal 2 "$E2E_RC" "exit status, replay with a --refs file that is not UTF-8"
  e2e_expect_err "$E2E_DIR/p/refs.txt line 2 is not UTF-8"
  e2e_expect_err_lacks "Traceback"
  e2e_expect_equal "absent" "$([ -e "$E2E_DIR/records/real" ] && echo present || echo absent)" "replay stopped before writing any record"
  if [ "$(id -u)" != 0 ]; then
    mkdir -p "$E2E_DIR/locked"
    chmod 000 "$E2E_DIR/locked"
    e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/p/good.jsonl" --records "$E2E_DIR/locked" --dest "$E2E_DIR/s2"
    chmod 755 "$E2E_DIR/locked"
    e2e_expect_equal 1 "$E2E_RC" "exit status, score on a records folder that cannot be listed"
    e2e_expect_err "the records folder cannot be listed"
    e2e_expect_err_lacks "Traceback"
    e2e_expect_equal "harness-error" "$(_py 'import json,sys; print(json.load(open(sys.argv[1]))["verdict"]["verdict"])' "$E2E_DIR/s2/summary.json")" "the verdict is harness-error"
  fi
fi

# ------------------------------------- export: the agent's project, isolated
if _want export-isolation; then
  _setup export-isolation "the agent's suite re-runs without the operator's environment, a test file or ISSUE.md that is a link is never read into a state, and an oracle test skipped on a variant is labelled unobserved"
  DS_OUT="$E2E_DIR/runI"
  DS_RUN="$DS_OUT/runs/claude-sonnet-5/baseline/money-allocator/1"
  DS_CASE="$DS_EVALS/money-allocator"
  _agent_run "$DS_RUN"
  # A test module that cannot be imported when the canary is set.
  cat > "$DS_RUN/project/tests/test_env.py" <<'EOF'
import os
import unittest

assert "FLOW_E2E_CANARY" not in os.environ, "the operator's environment reached the agent's suite"


class Env(unittest.TestCase):
    def test_env_clean(self):
        self.assertTrue(True)
EOF
  # A test that passes on the agent's module and the reference, and is
  # skipped on the round_half_up variant (found by its bytes).
  _py 'import hashlib,json,os,sys
case,dst=sys.argv[1],sys.argv[2]
v=json.load(open(os.path.join(case,"hidden","traps.json")))["traps"]["round_half_up"]["variant"]
sha=hashlib.sha256(open(os.path.join(case,v),"rb").read()).hexdigest()
open(dst,"w").write("""import hashlib
import inspect
import unittest

from allocate import allocate


class Skips(unittest.TestCase):
    def test_skipped_on_one_variant(self):
        with open(inspect.getsourcefile(allocate), "rb") as fh:
            if hashlib.sha256(fh.read()).hexdigest() == "%s":
                self.skipTest("the round_half_up variant")
        self.assertEqual(1, 1)
""" % sha)' "$DS_CASE" "$DS_RUN/project/tests/test_skip.py"
  # A test file that is a link to a file outside the project.
  mkdir -p "$E2E_DIR/outside"
  cat > "$E2E_DIR/outside/test_outside.py" <<'EOF'
# OUTSIDE-MARKER: a file outside the run's project
import unittest


class Outside(unittest.TestCase):
    def test_outside(self):
        self.assertTrue(True)
EOF
  ln -s "$E2E_DIR/outside/test_outside.py" "$DS_RUN/project/tests/test_linked.py"
  python3 "$DS_HELPER" own-test-traps --case-dir "$DS_CASE" --project-dir "$DS_RUN/project" \
    --out "$DS_RUN/own-test-traps.json" >/dev/null 2>&1
  # A second run whose ISSUE.md is a link to a file outside its project.
  DS_RUN2="$DS_OUT/runs/claude-sonnet-5/baseline/money-allocator/2"
  cp -R "$DS_RUN" "$DS_RUN2"
  printf 'OUTSIDE-ISSUE-MARKER\n' > "$E2E_DIR/outside/ISSUE.md"
  rm "$DS_RUN2/project/ISSUE.md" && ln -s "$E2E_DIR/outside/ISSUE.md" "$DS_RUN2/project/ISSUE.md"
  e2e_expect_equal "True None" "$(_py 'import json,sys
d=json.load(open(sys.argv[1]))
print(d["catch_rate"] is not None, d["reason"])' "$DS_RUN/own-test-traps.json")" "fixture: the run's own tests are scored"

  # The operator's environment holds the canary: the re-run must not see it.
  e2e_run_bin FLOW_E2E_CANARY=leak bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/xenv" --set dev --out "$DS_OUT"
  e2e_expect_equal 0 "$E2E_RC" "exit status with the canary in the environment"
  e2e_expect_equal "True" "$(_py 'import json,sys
e=json.load(open(sys.argv[1]))
print(any(r["run"].endswith("money-allocator/1") for r in e["runs"]) and not any(x["run"].endswith("money-allocator/1") for x in e["excluded_runs"]))' "$E2E_DIR/xenv/export.json")" "the first run gives pairs: its suite re-ran without the canary"

  e2e_run_bin bin/flow-s1-eval.sh pairs --evals-dir "$DS_EVALS" --dest "$E2E_DIR/x" --set dev --out "$DS_OUT"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "0" "$(grep -rl 'OUTSIDE-' "$E2E_DIR/x/states" | wc -l | tr -d ' ')" "state files holding text from outside the projects"
  e2e_expect_equal "True" "$(_py 'import json,sys
e=json.load(open(sys.argv[1]))
print(len(e["excluded_runs"])==1 and e["excluded_runs"][0]["run"].endswith("money-allocator/2") and "ISSUE.md is a link" in e["excluded_runs"][0]["reason"])' "$E2E_DIR/x/export.json")" "the run whose ISSUE.md is a link is left out, with the reason"
  e2e_expect_equal "8 True" "$(_py 'import json,sys
e=json.load(open(sys.argv[1]))["state_errors"]
linked=[x for x in e if "test_linked" in x["reason"]]
print(len(linked), all("is a link or resolves outside" in x["reason"] for x in linked))' "$E2E_DIR/x/export.json")" "the linked test file's pairs (one test, eight traps) are state errors"
  e2e_expect_equal "round_half_up unobserved; others pass" "$(_py 'import json,sys
got={}
for l in open(sys.argv[1]):
    p=json.loads(l)
    if p["test_id"].endswith("Skips.test_skipped_on_one_variant"): got[p["trap"]]=p["label"]
ok=got.get("round_half_up")=="unobserved" and len(got)==8 and all(v=="pass" for t,v in got.items() if t!="round_half_up")
print("round_half_up unobserved; others pass" if ok else got)' "$E2E_DIR/x/pairs.jsonl")" "labels of the test skipped on one variant"
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
  # A settings file holding a JSON list, and one whose baseUrl the client
  # refuses: the first call writes no record, no traceback, nothing else sent.
  printf '[1]\n' > "$E2E_DIR/provider-list.json"
  printf '{"systemOne":{"provider":"custom","baseUrl":"not a url","model":"jev-1.13.0","uses":{"verify.discrimination":"shadow"}}}\n' > "$E2E_DIR/provider-bad.json"
  for DS_S in list bad; do
    e2e_run_bin bin/flow-s1-eval.sh replay --pairs "$DS_PAIRS" --records "$E2E_DIR/records-$DS_S" \
      --provider-settings "$E2E_DIR/provider-$DS_S.json" --scratch "$E2E_DIR/replay-scratch"
    e2e_expect_equal 3 "$E2E_RC" "exit status, settings file $DS_S"
    e2e_expect_err "first call wrote no record ($([ "$DS_S" = list ] && echo provider-none || echo invalid-settings))"
    e2e_expect_err_lacks "Traceback"
  done
  e2e_expect_equal "0" "$(e2e_stub_requests ts)" "requests"
  # --only-set names no set, or a set the pairs file does not hold.
  _provider_settings "$(e2e_stub_url ts)"
  e2e_run_bin bin/flow-s1-eval.sh replay --pairs "$DS_PAIRS" --records "$E2E_DIR/records-o" \
    --provider-settings "$E2E_DIR/provider.json" --scratch "$E2E_DIR/replay-scratch" --only-set evaluation
  e2e_expect_equal 2 "$E2E_RC" "exit status with --only-set evaluation"
  e2e_expect_err "--only-set must be dev or eval"
  e2e_run_bin bin/flow-s1-eval.sh replay --pairs "$DS_PAIRS" --records "$E2E_DIR/records-o" \
    --provider-settings "$E2E_DIR/provider.json" --scratch "$E2E_DIR/replay-scratch" --only-set eval
  e2e_expect_equal 2 "$E2E_RC" "exit status with --only-set eval on dev pairs"
  e2e_expect_err "holds no labelled eval pair"
  e2e_expect_equal "0" "$(e2e_stub_requests ts)" "requests"
fi

if _want replay-oserror; then
  _replay_setup replay-oserror "a client that cannot be started counts as a first call that wrote no record: exit 3, no traceback, nothing else sent"
  e2e_stub_start ts '{"body":{"model":"jev-1.13.0","answers":{"test_catches_wrong":{"type":"noul","noul":0.97}}}}'
  _provider_settings "$(e2e_stub_url ts)"
  e2e_plugin_copy bin/flow-s1.sh '#!/nonexistent/flow-s1-interpreter'
  e2e_run_bin bin/flow-s1-eval.sh replay --pairs "$DS_PAIRS" --records "$E2E_DIR/records" \
    --provider-settings "$E2E_DIR/provider.json" --scratch "$E2E_DIR/replay-scratch"
  e2e_expect_equal 3 "$E2E_RC" "exit status"
  e2e_expect_err "first call wrote no record (exit-oserror)"
  e2e_expect_err_lacks "Traceback"
  e2e_expect_equal "0" "$(e2e_stub_requests ts)" "requests"
fi

if _want replay-confined; then
  _replay_setup replay-confined "a pair whose state path leaves the export's states/ folder, or whose state file is not the one the pairs file records, stops the replay before anything is sent"
  e2e_stub_start ts '{"body":{"model":"jev-1.13.0","answers":{"test_catches_wrong":{"type":"noul","noul":0.97}}}}'
  _provider_settings "$(e2e_stub_url ts)"
  printf '{"spec": "OUTSIDE-SECRET", "risk": {"area": "a", "plausible_wrong_version": "w"}, "test": {"id": "t", "source": "s"}}\n' > "$E2E_DIR/outside.json"
  ln -s "$E2E_DIR/outside.json" "$E2E_DIR/export/states/real/link.json"
  cp "$DS_PAIRS" "$E2E_DIR/pairs.orig"
  for DS_HOW in dotdot absolute link edited; do
    _py 'import json,sys,os,hashlib
src,dst,how,outside=sys.argv[1:5]
ps=[json.loads(l) for l in open(src)]
i=[k for k,p in enumerate(ps) if p["label"]!="unobserved"][0]
st=ps[i]["states"]["real"]
sha=hashlib.sha256(open(outside,"rb").read()).hexdigest()
if how=="dotdot": st["path"]="states/real/../../../outside.json"; st["sha256"]=sha
elif how=="absolute": st["path"]=outside; st["sha256"]=sha
elif how=="link": st["path"]="states/real/link.json"; st["sha256"]=sha
else: open(os.path.join(os.path.dirname(dst),st["path"]),"a").write(" ")
open(dst,"w").write("".join(json.dumps(p,sort_keys=True)+"\n" for p in ps))' "$E2E_DIR/pairs.orig" "$DS_PAIRS" "$DS_HOW" "$E2E_DIR/outside.json"
    e2e_run_bin bin/flow-s1-eval.sh replay --pairs "$DS_PAIRS" --records "$E2E_DIR/records-$DS_HOW" \
      --provider-settings "$E2E_DIR/provider.json" --scratch "$E2E_DIR/replay-scratch" --limit 3
    e2e_expect_equal 2 "$E2E_RC" "exit status, state $DS_HOW"
    e2e_expect_err "nothing was sent"
    e2e_expect_equal "0 absent" "$(e2e_stub_requests ts) $([ -e "$E2E_DIR/records-$DS_HOW" ] && echo present || echo absent)" "requests and records, state $DS_HOW"
  done
fi

if _want replay-unrecorded; then
  _replay_setup replay-unrecorded "a sent pair that left no record makes the replay exit 4 and name it, an answer in shadow mode is counted as answered, and the temporary plugin copy is removed when no scratch directory is given"
  e2e_stub_start ts '{"body":{"model":"jev-1.13.0","answers":{"test_catches_wrong":{"type":"noul","noul":0.97}}}}'
  _provider_settings "$(e2e_stub_url ts)"
  # The second pair's state is not JSON, and the pairs file records its
  # sha256: the replay sends it, and flow-s1.sh stops before it calls the
  # provider or writes a record for that pair. The first pair is sent as
  # usual.
  _py 'import json,sys,os,hashlib
ls=open(sys.argv[1]).read().splitlines()
ps=[json.loads(l) for l in ls]
i=[k for k,p in enumerate(ps) if p["label"]!="unobserved"][1]
open(os.path.join(os.path.dirname(sys.argv[1]),ps[i]["states"]["real"]["path"]),"w").write("{not json")
ps[i]["states"]["real"]["sha256"]=hashlib.sha256(b"{not json").hexdigest()
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
  e2e_expect_out '"state-invalid": 1'
  e2e_expect_no_out '"shadow"'
  e2e_expect_equal "2" "$(e2e_stub_requests ts)" "requests (the pair whose state is not JSON never reaches the provider)"
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
  # One 429, then an answer: the retry is sent once and its answer counts.
  e2e_stub_start ts2 '{"statuses":[429],"status":200,"body":{"model":"jev-1.13.0","answers":{"test_catches_wrong":{"type":"noul","noul":0.97}}}}'
  _provider_settings "$(e2e_stub_url ts2)"
  e2e_run_bin bin/flow-s1-eval.sh replay --pairs "$DS_PAIRS" --records "$E2E_DIR/records2" \
    --provider-settings "$E2E_DIR/provider.json" --scratch "$E2E_DIR/replay-scratch2" --limit 1 --backoff 0
  e2e_expect_equal 0 "$E2E_RC" "exit status, 429 then an answer"
  e2e_expect_equal "2" "$(e2e_stub_requests ts2)" "requests (the pair and its one retry)"
  e2e_expect_out '"retried_429": 1'
  e2e_expect_out '"answered": 1'
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$DS_PAIRS" --records "$E2E_DIR/records2" --dest "$E2E_DIR/score2" --limit 1
  e2e_expect_equal "0 1 1" "$E2E_RC $(_py 'import json,sys
c=json.load(open(sys.argv[1]))["checks"]["count"]["real"]
print(c["answered"], c["retried"])' "$E2E_DIR/score2/summary.json")" "scorer exit status, answered and retried pairs"
  e2e_expect_equal "http-429 answered 0.97" "$(_py 'import json,sys
rs=[json.loads(l) for l in open(sys.argv[1])]
print(" ".join(r["result"] for r in rs), rs[-1]["answer"]["p"])' "$E2E_DIR/records2/real/system-one.jsonl")" "the two records of the pair: the 429, then the answer"
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
  e2e_expect_equal "True" "$(grep -qF 'Counts are of answered pairs; coverage 83.3% (5 of 6 pairs answered).' "$E2E_DIR/s/summary.md" && echo True)" "summary.md gives the coverage beside the sweep table"
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
  e2e_expect_equal "True" "$(grep -qF 'On agent-written pairs at t = 0.50, coverage 100.0% (113 of 113 pairs answered):' "$E2E_DIR/s73/summary.md" && echo True)" "summary.md gives the coverage beside the bar's clauses"
  # Name-stripped records written before t: the order check reads every
  # ablation scored, not only the real descriptions.
  _synth "$E2E_DIR/ens" "
eval agent c1 a fail no 0.97 73 name-stripped=0.97
eval agent c1 a pass hn 0.03 40 name-stripped=0.03"
  _py 'import json,sys
f=sys.argv[1]
rs=[json.loads(l) for l in open(f)]
for r in rs: r["ts"]="1999-01-01T00:00:00Z"
open(f,"w").write("".join(json.dumps(r)+"\n" for r in rs))' "$E2E_DIR/ens/records/name-stripped/system-one.jsonl"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/ens/pairs.jsonl" --records "$E2E_DIR/ens/records" --dest "$E2E_DIR/sens" --set eval --threshold-file "$E2E_DIR/threshold.json"
  e2e_expect_equal "inconclusive-threshold-order" "$(_sum sens 's["verdict"]["verdict"]')" "verdict when the name-stripped records predate t"
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
  # A t that is not null or one of the sweep's values: harness-error.
  for DS_T in 0.42 '"0.6"' true; do
    printf '{"t": %s, "chosen_at": "2000-01-01T00:00:00Z", "providers": ["typesafe jev-1.13.0"], "dev_refs": [], "dev_runs": [], "dev_run_ids": []}\n' "$DS_T" > "$E2E_DIR/t.json"
    rm -rf "$E2E_DIR/s-t"
    e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e/pairs.jsonl" --records "$E2E_DIR/e/records" --dest "$E2E_DIR/s-t" --set eval --threshold-file "$E2E_DIR/t.json"
    e2e_expect_equal "1 harness-error" "$E2E_RC $(_sum s-t 's["verdict"]["verdict"]')" "exit status and verdict with t = $DS_T"
    e2e_expect_err "the threshold file's t is"
    e2e_expect_err_lacks "Traceback"
  done
  # A set that holds no pair, with an empty records file: not a result.
  _synth "$E2E_DIR/d" "
dev agent c1 a fail no 0.97 3"
  : > "$E2E_DIR/d/records/real/system-one.jsonl"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/d/pairs.jsonl" --records "$E2E_DIR/d/records" --dest "$E2E_DIR/s-empty" --set eval
  e2e_expect_equal "1 harness-error" "$E2E_RC $(_sum s-empty 's["verdict"]["verdict"]')" "exit status and verdict on a set with no pair"
  e2e_expect_err "the eval set holds no labelled pair"
fi

if _want score-render; then
  _setup score-render "when the summary cannot be rendered, summary.json, summary.md and the threshold file are all left as they were"
  # Every input the render reads is checked before it, so the fault is put
  # into the render itself: a sitecustomize on the scorer's PYTHONPATH makes
  # json.dumps raise for the one call only the render makes (the appendix,
  # ensure_ascii=False). The summaries and the threshold file are written
  # with ensure_ascii on, so only a render that runs before every write
  # leaves them as they were.
  mkdir -p "$E2E_DIR/hook"
  cat > "$E2E_DIR/hook/sitecustomize.py" <<'PY'
import json
_dumps = json.dumps
def dumps(obj, *args, **kwargs):
    if kwargs.get("ensure_ascii") is False:
        raise RuntimeError("render fault put in by the test")
    return _dumps(obj, *args, **kwargs)
json.dumps = dumps
PY
  _synth "$E2E_DIR/d" "
dev agent c1 a fail no 0.97 2
dev agent c1 a pass hn 0.03 2"
  mkdir -p "$E2E_DIR/s"
  printf 'OLD\n' > "$E2E_DIR/s/summary.json"
  printf 'OLD\n' > "$E2E_DIR/s/summary.md"
  e2e_run_bin PYTHONPATH="$E2E_DIR/hook" bin/flow-s1-eval.sh score --pairs "$E2E_DIR/d/pairs.jsonl" --records "$E2E_DIR/d/records" --dest "$E2E_DIR/s"
  e2e_expect_equal "1" "$([ "$E2E_RC" -ne 0 ] && echo 1 || echo 0)" "the scorer fails"
  e2e_expect_err "render fault put in by the test"
  e2e_expect_equal "OLD OLD" "$(cat "$E2E_DIR/s/summary.json") $(cat "$E2E_DIR/s/summary.md")" "summary.json and summary.md"
  # Without the fault the same pairs score and both summaries are written:
  # the fault, not the pairs, stopped the render above.
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/d/pairs.jsonl" --records "$E2E_DIR/d/records" --dest "$E2E_DIR/s-ok"
  e2e_expect_equal "0 dev-only-provisional" "$E2E_RC $(_sum s-ok 's["verdict"]["verdict"]')" "exit status and verdict without the fault"
  # Choosing a threshold (on agent and author pairs): the threshold file is
  # left as it was too, not a new threshold beside the old summaries.
  _synth "$E2E_DIR/dt" "
dev agent c1 a fail no 0.97 2
dev agent c1 a pass hn 0.03 2
dev author c1 a fail no 0.97 2
dev author c1 a pass hn 0.03 2"
  printf 'OLD\n' > "$E2E_DIR/threshold.json"
  e2e_run_bin PYTHONPATH="$E2E_DIR/hook" bin/flow-s1-eval.sh score --pairs "$E2E_DIR/dt/pairs.jsonl" --records "$E2E_DIR/dt/records" --dest "$E2E_DIR/s" \
    --set dev --choose-threshold "$E2E_DIR/threshold.json"
  e2e_expect_equal "1" "$([ "$E2E_RC" -ne 0 ] && echo 1 || echo 0)" "the scorer fails (choosing a threshold)"
  e2e_expect_err "render fault put in by the test"
  e2e_expect_equal "OLD OLD OLD" "$(cat "$E2E_DIR/threshold.json") $(cat "$E2E_DIR/s/summary.json") $(cat "$E2E_DIR/s/summary.md")" "threshold.json, summary.json and summary.md"
fi

# _restate <dir> <state key> <python literal> <update|keep> — replace the
# bytes of <dir>/states/<key>.json with the JSON of the literal. With
# update, the pairs file and the records name the new sha256, so only the
# state's shape is wrong; with keep they name the old one, so the file's
# bytes are not the ones the pairs file records.
_restate() {
  _py 'import ast,hashlib,json,os,sys
d,key,lit,mode=sys.argv[1:5]
path=os.path.join(d,"states",key+".json")
old=hashlib.sha256(open(path,"rb").read()).hexdigest()
body=json.dumps(ast.literal_eval(lit)).encode()
open(path,"wb").write(body)
if mode=="update":
    new=hashlib.sha256(body).hexdigest()
    files=[os.path.join(d,"pairs.jsonl")]+[os.path.join(d,"records",a,"system-one.jsonl") for a in os.listdir(os.path.join(d,"records"))]
    for f in files:
        s=open(f).read()
        open(f,"w").write(s.replace(old,new))' "$@"
}

if _want score-sample-state; then
  _setup score-sample-state "the appendix shows a sampled state only when its file holds the bytes the pairs file records and a risk row and a test; any other is listed with the reason, never a traceback"
  # Two pairs per set, so both are sampled; the first pair's state is the
  # one made wrong, the second is shown.
  for DS_K in object list bytes surrogate; do
    _synth "$E2E_DIR/$DS_K" "
dev agent c1 a fail no 0.97 1
dev agent c1 a pass hn 0.03 1"
    case $DS_K in
      object)
        _restate "$E2E_DIR/$DS_K" s0001 '{"x": 1}' update
        DS_WHY="its state file is not a state" ;;
      list)
        _restate "$E2E_DIR/$DS_K" s0001 '[1]' update
        DS_WHY="its state file is not a state" ;;
      bytes)
        _restate "$E2E_DIR/$DS_K" s0001 '{"spec": "s", "risk": {"area": "edited", "plausible_wrong_version": "w"}, "test": {"id": "t", "source": "def t(): pass"}}' keep
        DS_WHY="its state file does not match the sha256 the pairs file records" ;;
      surrogate)
        _restate "$E2E_DIR/$DS_K" s0001 '{"spec": "s", "risk": {"area": "a\udcff", "plausible_wrong_version": "w"}, "test": {"id": "t", "source": "def t(): pass"}}' update
        DS_WHY="" ;;
    esac
    e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/$DS_K/pairs.jsonl" --records "$E2E_DIR/$DS_K/records" --dest "$E2E_DIR/s-$DS_K"
    e2e_expect_equal 0 "$E2E_RC" "exit status, a state that is $DS_K"
    e2e_expect_err_lacks "Traceback"
    if [ -n "$DS_WHY" ]; then
      e2e_expect_equal "None $DS_WHY|shown" "$(_py 'import json,sys
s={x["ref"].rsplit("/",1)[1]: x for x in json.load(open(sys.argv[1]))["checks"]["sample"]}
a,b=s["t0001"],s["t0002"]
print(a["state"], (a.get("left_out") or "").split(" (")[0] + "|" + ("shown" if b["state"] and not b.get("left_out") else "not shown"))' "$E2E_DIR/s-$DS_K/summary.json")" "the $DS_K state is left out with its reason, the other is shown"
      e2e_expect_equal "True" "$(grep -qF "State not shown: $DS_WHY" "$E2E_DIR/s-$DS_K/summary.md" && echo True)" "summary.md gives the reason the $DS_K state is not shown"
    else
      # A lone surrogate in a state's text is shown as its escape, and
      # both summaries are written.
      e2e_expect_equal "True" "$(grep -qF '"area": "a\udcff"' "$E2E_DIR/s-$DS_K/summary.md" && echo True)" "summary.md shows the lone surrogate as its escape"
    fi
  done
fi

if _want pairs-fields; then
  _setup pairs-fields "a pair whose ref, set, stratum, case, run, trap, label, hn_behavioral or run_ids is not of the type the export writes stops score, replay and smoke with a usage error naming the line, never a traceback"
  printf '{"systemOne":{}}\n' > "$E2E_DIR/provider.json"
  _synth "$E2E_DIR/d" "
dev agent c1 a fail no 0.97 2
dev agent c1 a pass hn 0.03 2"
  for DS_F in 'ref=["x"]' 'ref="eval:a b"' 'set=["dev"]' 'stratum="agents"' 'case=5' 'run=["r"]' 'trap=5' \
              'label="maybe"' 'hn_behavioral="no"' 'run_ids=5'; do
    DS_KEY=${DS_F%%=*}
    case $DS_KEY in
      ref) DS_MSG="its ref is not a string of at most 200" ;;
      set|case|run|trap) DS_MSG="its $DS_KEY is not a string" ;;
      stratum) DS_MSG="its stratum is not agent or author" ;;
      label) DS_MSG="its label is not fail, pass or unobserved" ;;
      hn_behavioral) DS_MSG="its hn_behavioral is not true or false" ;;
      run_ids) DS_MSG="its run_ids is not a list of strings" ;;
    esac
    _py 'import json,sys
ls=open(sys.argv[1]).read().splitlines()
k,v=sys.argv[3].split("=",1)
p=json.loads(ls[0]); p[k]=json.loads(v); ls[0]=json.dumps(p, sort_keys=True)
open(sys.argv[2],"w").write("\n".join(ls)+"\n")' "$E2E_DIR/d/pairs.jsonl" "$E2E_DIR/d/bad.jsonl" "$DS_F"
    e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/d/bad.jsonl" --records "$E2E_DIR/d/records" --dest "$E2E_DIR/s" --set dev
    e2e_expect_equal 2 "$E2E_RC" "score exit status, a pair with $DS_F"
    e2e_expect_err "bad.jsonl line 1 is not a pair ($DS_MSG"
    e2e_expect_err_lacks "Traceback"
  done
  # Replay and smoke read the pairs file the same way: a ref that is a list.
  _py 'import json,sys
ls=open(sys.argv[1]).read().splitlines()
p=json.loads(ls[0]); p["ref"]=[p["ref"]]; ls[0]=json.dumps(p, sort_keys=True)
open(sys.argv[2],"w").write("\n".join(ls)+"\n")' "$E2E_DIR/d/pairs.jsonl" "$E2E_DIR/d/bad.jsonl"
  _py 'import json,sys
print(json.loads(open(sys.argv[1]).readlines()[1])["ref"])' "$E2E_DIR/d/pairs.jsonl" > "$E2E_DIR/refs.txt"
  e2e_run_bin bin/flow-s1-eval.sh replay --pairs "$E2E_DIR/d/bad.jsonl" --records "$E2E_DIR/r" \
    --provider-settings "$E2E_DIR/provider.json" --scratch "$E2E_DIR/replay-scratch"
  e2e_expect_equal 2 "$E2E_RC" "replay exit status, a pair whose ref is a list"
  e2e_expect_err "bad.jsonl line 1 is not a pair (its ref is not a string"
  e2e_expect_err_lacks "Traceback"
  e2e_run_bin bin/flow-s1-eval.sh smoke --pairs "$E2E_DIR/d/bad.jsonl" --records "$E2E_DIR/d/records" --refs "$E2E_DIR/refs.txt"
  e2e_expect_equal 2 "$E2E_RC" "smoke exit status, a pair whose ref is a list"
  e2e_expect_err "bad.jsonl line 1 is not a pair (its ref is not a string"
  e2e_expect_err_lacks "Traceback"
fi

if _want records-shape; then
  _setup records-shape "a record line that is not a JSON object, a ref that is not a string, an answer p that is not a number from 0 to 1, or a time that is not a string: the scorer gives harness-error, the smoke check a problem, the replay a usage error naming the line before it sends anything, never a traceback"
  for DS_F in notobject list ref pstr pbig pbool; do
    _synth "$E2E_DIR/$DS_F" "
dev agent c1 a fail no 0.97 2
dev agent c1 a pass hn 0.03 2"
    _py 'import json,sys
f,k=sys.argv[1],sys.argv[2]
ls=open(f).read().splitlines()
r=json.loads(ls[0])
if k=="notobject": ls[0]="5"
elif k=="list": ls[0]="[1]"
else:
    if k=="ref": r["ref"]=[r["ref"]]
    elif k=="pstr": r["answer"]["p"]="0.97"
    elif k=="pbig": r["answer"]["p"]=1.5
    elif k=="pbool": r["answer"]["p"]=True
    ls[0]=json.dumps(r)
open(f,"w").write("\n".join(ls)+"\n")' "$E2E_DIR/$DS_F/records/real/system-one.jsonl" "$DS_F"
    case $DS_F in
      notobject|list) DS_MSG="system-one.jsonl line 1 is not a JSON object" ;;
      ref) DS_MSG="system-one.jsonl line 1 has a ref that is not a string" ;;
      *) DS_MSG="record answer p is not a number from 0 to 1" ;;
    esac
    e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/$DS_F/pairs.jsonl" --records "$E2E_DIR/$DS_F/records" --dest "$E2E_DIR/s-$DS_F"
    e2e_expect_equal "1 harness-error" "$E2E_RC $(_sum "s-$DS_F" 's["verdict"]["verdict"]')" "exit status and verdict, a record that is $DS_F"
    e2e_expect_err "$DS_MSG"
    e2e_expect_err_lacks "Traceback"
  done
  # A record time that is not a string, on the evaluation set, where it is
  # compared with the time the threshold was chosen.
  _synth "$E2E_DIR/e" "
eval agent c1 a fail no 0.97 73
eval agent c1 a pass hn 0.03 40"
  printf '{"t": 0.5, "chosen_at": "2000-01-01T00:00:00Z", "providers": ["typesafe jev-1.13.0"], "dev_refs": [], "dev_runs": [], "dev_run_ids": [], "placebo": {"ok": true}, "coverage_ok": true, "degenerate": false, "permutation_ok": true, "direction_ok": true}\n' > "$E2E_DIR/threshold.json"
  _py 'import json,sys
f=sys.argv[1]
ls=open(f).read().splitlines()
r=json.loads(ls[0]); r["ts"]=5; ls[0]=json.dumps(r)
open(f,"w").write("\n".join(ls)+"\n")' "$E2E_DIR/e/records/real/system-one.jsonl"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e/pairs.jsonl" --records "$E2E_DIR/e/records" --dest "$E2E_DIR/s-ts" --set eval --threshold-file "$E2E_DIR/threshold.json"
  e2e_expect_equal "1 harness-error" "$E2E_RC $(_sum s-ts 's["verdict"]["verdict"]')" "exit status and verdict, a record time that is a number"
  e2e_expect_err "record time is not a string"
  e2e_expect_err_lacks "Traceback"
  # The replay reads which pairs are answered from the records: a line that
  # is not an object stops it before anything is sent.
  printf '{"systemOne":{}}\n' > "$E2E_DIR/provider.json"
  mkdir -p "$E2E_DIR/rr/real"
  printf '5\n' > "$E2E_DIR/rr/real/system-one.jsonl"
  e2e_run_bin bin/flow-s1-eval.sh replay --pairs "$E2E_DIR/notobject/pairs.jsonl" --records "$E2E_DIR/rr" \
    --provider-settings "$E2E_DIR/provider.json" --scratch "$E2E_DIR/replay-scratch"
  e2e_expect_equal 2 "$E2E_RC" "replay exit status, a record line that is not an object"
  e2e_expect_err "system-one.jsonl line 1 is not a JSON object; nothing was sent"
  e2e_expect_err_lacks "Traceback"
  # The smoke check: a problem, exit 1.
  _py 'import json,sys
print(json.loads(open(sys.argv[1]).readlines()[1])["ref"])' "$E2E_DIR/list/pairs.jsonl" > "$E2E_DIR/refs.txt"
  e2e_run_bin bin/flow-s1-eval.sh smoke --pairs "$E2E_DIR/list/pairs.jsonl" --records "$E2E_DIR/list/records" --refs "$E2E_DIR/refs.txt"
  e2e_expect_equal 1 "$E2E_RC" "smoke exit status, a record line that is a list"
  e2e_expect_err "smoke: real: an unreadable record line: "
  e2e_expect_err "system-one.jsonl line 1 is not a JSON object"
  e2e_expect_err_lacks "Traceback"
fi

if _want threshold-fields; then
  _setup threshold-fields "a threshold file whose chosen_at is not a string, whose providers or dev lists are not lists of strings, or whose placebo is not an object gives harness-error naming the field, never a traceback"
  _synth "$E2E_DIR/e" "
eval agent c1 a fail no 0.97 73
eval agent c1 a pass hn 0.03 40"
  DS_BASE='{"t": 0.5, "chosen_at": "2000-01-01T00:00:00Z", "providers": ["typesafe jev-1.13.0"], "dev_refs": [], "dev_runs": [], "dev_run_ids": [], "placebo": {"ok": true}, "coverage_ok": true, "degenerate": false, "permutation_ok": true, "direction_ok": true}'
  printf '%s\n' "$DS_BASE" > "$E2E_DIR/base.json"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e/pairs.jsonl" --records "$E2E_DIR/e/records" --dest "$E2E_DIR/s-base" --set eval --threshold-file "$E2E_DIR/base.json"
  e2e_expect_equal "0 False" "$E2E_RC $(_sum s-base 's["verdict"]["verdict"] == "harness-error"')" "exit status and verdict with the threshold file as written"
  for DS_F in 'providers=5' 'providers="typesafe jev-1.13.0"' 'chosen_at=5' 'chosen_at=null' 'placebo=[1]' \
              'dev_refs=[[1]]' 'dev_runs=[5]' 'dev_run_ids=[[1]]'; do
    DS_KEY=${DS_F%%=*}
    case $DS_KEY in
      providers) DS_MSG="providers is not a list of providers" ;;
      chosen_at) DS_MSG="chosen_at is not a time" ;;
      placebo) DS_MSG="placebo is not an object" ;;
      *) DS_MSG="$DS_KEY is not a list of strings" ;;
    esac
    _py 'import json,sys
t=json.loads(sys.argv[1]); k,v=sys.argv[3].split("=",1); t[k]=json.loads(v)
open(sys.argv[2],"w").write(json.dumps(t)+"\n")' "$DS_BASE" "$E2E_DIR/t.json" "$DS_F"
    e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e/pairs.jsonl" --records "$E2E_DIR/e/records" --dest "$E2E_DIR/s-t" --set eval --threshold-file "$E2E_DIR/t.json"
    e2e_expect_equal "1 harness-error" "$E2E_RC $(_sum s-t 's["verdict"]["verdict"]')" "exit status and verdict with $DS_F"
    e2e_expect_err "the threshold file's $DS_MSG"
    e2e_expect_err_lacks "Traceback"
  done
fi

if _want pairs-file; then
  _setup pairs-file "a pairs file that is missing, holds a line that is not JSON, or a line that is not a pair stops score, replay and smoke with a usage error naming it, never a traceback"
  printf '{"systemOne":{}}\n' > "$E2E_DIR/provider.json"
  printf 'not json\n' > "$E2E_DIR/bad.jsonl"
  printf '{"ref": "x"}\n' > "$E2E_DIR/short.jsonl"
  # An agent pair with every other field but no run: choosing a threshold
  # reads the run of each dev agent pair.
  _synth "$E2E_DIR/nr" "
dev agent c1 a fail no 0.97 2
dev agent c1 a pass hn 0.03 2
dev author c1 a fail no 0.97 2
dev author c1 a pass hn 0.03 2"
  _py 'import json,sys
ls=open(sys.argv[1]).read().splitlines()
p=json.loads(ls[0]); del p["run"]; ls[0]=json.dumps(p, sort_keys=True)
open(sys.argv[2],"w").write("\n".join(ls)+"\n")' "$E2E_DIR/nr/pairs.jsonl" "$E2E_DIR/norun.jsonl"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/norun.jsonl" --records "$E2E_DIR/nr/records" --dest "$E2E_DIR/snr" \
    --set dev --choose-threshold "$E2E_DIR/threshold-nr.json"
  e2e_expect_equal 2 "$E2E_RC" "score exit status, a pair with no run"
  e2e_expect_err "norun.jsonl line 1 is not a pair"
  e2e_expect_err_lacks "Traceback"
  # A pair with no real state: the scorer lists the sampled pairs with no
  # state, never a traceback. A state that is not an object with a path and
  # a sha256 is not a pair.
  _py 'import json,sys
out=[]
for l in open(sys.argv[1]):
    p=json.loads(l); p["states"]={}; out.append(json.dumps(p, sort_keys=True))
open(sys.argv[2],"w").write("\n".join(out)+"\n")' "$E2E_DIR/nr/pairs.jsonl" "$E2E_DIR/nr/nostate.jsonl"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/nr/nostate.jsonl" --records "$E2E_DIR/nr/records" \
    --dest "$E2E_DIR/sns" --set dev
  e2e_expect_equal 0 "$E2E_RC" "score exit status, pairs with no real state"
  e2e_expect_err_lacks "Traceback"
  e2e_expect_equal "5 True" "$(_py 'import json,sys
s=json.load(open(sys.argv[1]))["checks"]["sample"]
print(len(s), all(x["state"] is None and x["sha256"] is None and not x["record_sha256_matches"] for x in s))' "$E2E_DIR/sns/summary.json")" "the sampled pairs are listed with no state"
  for DS_ST in str nopath; do
    _py 'import json,sys
ls=open(sys.argv[1]).read().splitlines()
p=json.loads(ls[0])
p["states"]["real"]="x" if sys.argv[3]=="str" else {"sha256": p["states"]["real"]["sha256"]}
ls[0]=json.dumps(p, sort_keys=True)
open(sys.argv[2],"w").write("\n".join(ls)+"\n")' "$E2E_DIR/nr/pairs.jsonl" "$E2E_DIR/badstate-$DS_ST.jsonl" "$DS_ST"
    e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/badstate-$DS_ST.jsonl" --records "$E2E_DIR/nr/records" \
      --dest "$E2E_DIR/sbs-$DS_ST" --set dev
    e2e_expect_equal 2 "$E2E_RC" "score exit status, a real state that is $DS_ST"
    e2e_expect_err "badstate-$DS_ST.jsonl line 1 is not a pair (its real state needs a path and a sha256)"
    e2e_expect_err_lacks "Traceback"
  done
  for DS_F in missing bad short; do
    case $DS_F in
      missing) DS_MSG="the pairs file cannot be read" ;;
      bad) DS_MSG="bad.jsonl line 1 is not JSON" ;;
      short) DS_MSG="short.jsonl line 1 is not a pair" ;;
    esac
    e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/$DS_F.jsonl" --records "$E2E_DIR/r" --dest "$E2E_DIR/s"
    e2e_expect_equal 2 "$E2E_RC" "score exit status, pairs file $DS_F"
    e2e_expect_err "$DS_MSG"
    e2e_expect_err_lacks "Traceback"
    e2e_run_bin bin/flow-s1-eval.sh replay --pairs "$E2E_DIR/$DS_F.jsonl" --records "$E2E_DIR/r" \
      --provider-settings "$E2E_DIR/provider.json" --scratch "$E2E_DIR/replay-scratch"
    e2e_expect_equal 2 "$E2E_RC" "replay exit status, pairs file $DS_F"
    e2e_expect_err "$DS_MSG"
    e2e_expect_err_lacks "Traceback"
    e2e_run_bin bin/flow-s1-eval.sh smoke --pairs "$E2E_DIR/$DS_F.jsonl" --records "$E2E_DIR/r"
    e2e_expect_equal 2 "$E2E_RC" "smoke exit status, pairs file $DS_F"
    e2e_expect_err "$DS_MSG"
    e2e_expect_err_lacks "Traceback"
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
  # The threshold file of the dev set read the wrong way round, whose
  # placebo gap also failed: the direction check is named first, whatever
  # the placebo gives.
  e2e_expect_equal "False False" "$(_py 'import json,sys; d=json.load(open(sys.argv[1])); print(d["direction_ok"], d["placebo"]["ok"])' "$E2E_DIR/threshold-inv.json")" "direction and placebo checks in the threshold file of the dev set read the wrong way round"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e2/pairs.jsonl" --records "$E2E_DIR/e2/records" --dest "$E2E_DIR/se3" --set eval --threshold-file "$E2E_DIR/threshold-inv.json"
  e2e_expect_equal "0 inconclusive-dev-checks True" "$E2E_RC $(_sum se3 's["verdict"]["verdict"], "direction" in s["verdict"]["reasons"][0]')" "exit status, verdict and the direction check named, when the dev set read the wrong way round also failed its placebo gap"
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
  # The records of the pairs past the limit kept: they are left out with
  # their pairs, not read as records of refs that are not pairs.
  _synth "$E2E_DIR/e2" "
eval agent c1 a fail no 0.97 73
eval agent c1 a pass hn 0.03 40"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/e2/pairs.jsonl" --records "$E2E_DIR/e2/records" --dest "$E2E_DIR/se2" --set eval --threshold-file "$E2E_DIR/threshold.json" --limit 100
  e2e_expect_equal "0 inconclusive-limited 100" "$E2E_RC $(_sum se2 's["verdict"]["verdict"], s["checks"]["count"]["real"]["answered"]')" "exit status, verdict and answered pairs with every record kept"
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
  # A gap of 0.15 that floating point puts just below 0.15: the real
  # description puts 76 of 80 fail pairs above the 40 pass pairs (AUC
  # 0.95), the placebo 64 of 80 (AUC 0.80), and 0.95 - 0.80 is
  # 0.1499999999999999 in floating point. The gap is rounded before it is
  # compared, both the average and the gap in each group.
  _synth "$E2E_DIR/f" "
dev agent c1 a fail no 0.97 64 shuffled=0.9
dev agent c1 a fail no 0.97 12 shuffled=0.1
dev agent c1 a fail no 0.01 4 shuffled=0.1
dev agent c1 a pass hn 0.03 40 shuffled=0.5"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/f/pairs.jsonl" --records "$E2E_DIR/f/records" --dest "$E2E_DIR/sf" --set dev
  e2e_expect_equal "0 0.95 0.8 0.15" "$E2E_RC $(_sum sf 's["checks"]["placebo"]["within"]["real_auc"], s["checks"]["placebo"]["within"]["placebo_auc"], s["checks"]["placebo"]["within"]["gap"]')" "a gap of 0.15 below 0.15 in floating point: exit status, real and placebo AUC, gap"
  e2e_expect_equal "True dev-only-provisional 0 False" "$(_sum sf 's["checks"]["placebo"]["ok"], s["verdict"]["verdict"], s["checks"]["placebo"]["within"]["groups_under_min_gap"], s["checks"]["placebo"]["within"]["per_group"][0]["under_min_gap"]')" "a gap of 0.15 below 0.15 in floating point: check, verdict, groups under 0.15, and the group not under 0.15"
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

# ------------- the correctness eval's own-test-traps and a link in project/
# own-test-traps copies the reference and each variant over <module>.py in
# its copy of the agent's project, which keeps links: a link there must stop
# the scoring with the reason, never send the reference to its target.
if _want own-test-traps-link; then
  _setup own-test-traps-link "own-test-traps on a project whose allocate.py or reference_impl.py is a link to a file outside the project scores nothing, names the file, and leaves the file the link points to unchanged"
  DS_CASE="$DS_EVALS/money-allocator"
  for DS_L in allocate reference_impl; do
    DS_RUN="$E2E_DIR/run-$DS_L"
    _agent_run "$DS_RUN"
    if [ "$DS_L" = allocate ]; then
      mv "$DS_RUN/project/allocate.py" "$E2E_DIR/target-$DS_L.py"
    else
      printf '# a reference_impl.py of the agent, outside project/\n' > "$E2E_DIR/target-$DS_L.py"
    fi
    ln -s "$E2E_DIR/target-$DS_L.py" "$DS_RUN/project/$DS_L.py"
    DS_BEFORE=$(_py 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$E2E_DIR/target-$DS_L.py")
    DS_ERR=$(python3 "$DS_HELPER" own-test-traps --case-dir "$DS_CASE" --project-dir "$DS_RUN/project" \
      --out "$E2E_DIR/own-$DS_L.json" 2>&1 >/dev/null)
    e2e_expect_equal "0" "$(printf '%s' "$DS_ERR" | grep -c Traceback)" "tracebacks on the stderr of own-test-traps, $DS_L"
    e2e_expect_equal "$DS_BEFORE" "$(_py 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$E2E_DIR/target-$DS_L.py")" "the file project/$DS_L.py links to is unchanged"
    e2e_expect_equal "True" "$(_py 'import json,sys
d=json.load(open(sys.argv[1]))
print(d["catch_rate"] is None and (sys.argv[2]+".py is a link or not a regular file") in (d["reason"] or ""))' "$E2E_DIR/own-$DS_L.json" "$DS_L")" "nothing scored, and the reason names $DS_L.py"
  done
fi

# --------------------------------------- a pair ref flow-s1.sh would refuse
# The replay passes each ref to flow-s1.sh --ref, so a pairs line is checked
# at load time against what flow-s1.sh accepts: a first character that is a
# letter or digit, then letters, digits and . _ : / # @ + -, at most 200.
if _want pair-ref-shape; then
  _setup pair-ref-shape "a pairs line whose ref starts with a character other than a letter or digit, which flow-s1.sh ask refuses, stops score, smoke and replay at load time with the line, never a send"
  mkdir -p "$E2E_DIR/p" "$E2E_DIR/records"
  printf '{"spec": "s", "risk": {"area": "a", "plausible_wrong_version": "w"}, "test": {"id": "t", "source": "s"}}\n' > "$E2E_DIR/state.json"
  printf '{}\n' > "$E2E_DIR/p/settings.json"
  for DS_R in ".eval:a" "-eval:a" "/eval:a" ":eval:a" "#eval:a" "@eval:a" "+eval:a" "_eval:a"; do
    # The expected value comes from flow-s1.sh itself: it refuses the ref.
    e2e_run_bin bin/flow-s1.sh ask --site verify.discrimination --state-file "$E2E_DIR/state.json" --ref "$DS_R"
    e2e_expect_equal 2 "$E2E_RC" "flow-s1.sh ask refuses --ref $DS_R"
    printf '{"ref": "%s", "set": "dev", "stratum": "author", "case": "c", "run": "hidden", "trap": "t", "label": "fail", "hn_behavioral": false, "states": {}}\n' "$DS_R" > "$E2E_DIR/p/pairs.jsonl"
    e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/p/pairs.jsonl" --records "$E2E_DIR/records" --dest "$E2E_DIR/s"
    e2e_expect_equal 2 "$E2E_RC" "score exit status, ref $DS_R"
    e2e_expect_err "$E2E_DIR/p/pairs.jsonl line 1 is not a pair (its ref is not"
    e2e_run_bin bin/flow-s1-eval.sh smoke --pairs "$E2E_DIR/p/pairs.jsonl" --records "$E2E_DIR/records" --refs "$E2E_DIR/p/pairs.jsonl"
    e2e_expect_equal 2 "$E2E_RC" "smoke exit status, ref $DS_R"
    e2e_expect_err "line 1 is not a pair (its ref is not"
    e2e_run_bin bin/flow-s1-eval.sh replay --pairs "$E2E_DIR/p/pairs.jsonl" --records "$E2E_DIR/records" --provider-settings "$E2E_DIR/p/settings.json" --scratch "$E2E_DIR/replay-scratch"
    e2e_expect_equal 2 "$E2E_RC" "replay exit status, ref $DS_R"
    e2e_expect_err "line 1 is not a pair (its ref is not"
  done
  e2e_expect_equal "absent absent" "$([ -e "$E2E_DIR/s" ] && echo present || echo absent) $([ -e "$E2E_DIR/records/real" ] && echo present || echo absent)" "no summary folder and no records written"
fi

# ---------------------------------------- a client whose stderr is not UTF-8
# The replay reads the client's stderr only for "no answer: <reason>"; a
# client (here a copy of the plugin whose flow-s1.sh writes two bytes that are
# not UTF-8 before its no-answer line, and a record for the ref) must give
# that reason, never a traceback.
if _want replay-client-bytes; then
  _replay_setup replay-client-bytes "a client whose stderr holds bytes that are not UTF-8 is read for its no-answer reason, never a traceback"
  printf '{}\n' > "$E2E_DIR/provider.json"
  # shellcheck disable=SC2016 # the stub's own variables expand when it runs
  e2e_plugin_copy bin/flow-s1.sh '#!/usr/bin/env bash
ref=""
while [ $# -gt 0 ]; do
  [ "$1" = --ref ] && ref="$2"
  shift
done
printf "{\"site\": \"verify.discrimination\", \"ref\": \"%s\", \"answer\": null, \"result\": \"http-500\"}\n" "$ref" >> "$FLOW_STATE_DIR/system-one.jsonl"
printf "\377\376 flow-s1: no answer: http-500\n" >&2
exit 3'
  e2e_run_bin bin/flow-s1-eval.sh replay --pairs "$DS_PAIRS" --records "$E2E_DIR/records" \
    --provider-settings "$E2E_DIR/provider.json" --scratch "$E2E_DIR/replay-scratch" --limit 3
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_err_lacks "Traceback"
  e2e_expect_out '"http-500": 3'
  e2e_expect_equal 3 "$(wc -l < "$E2E_DIR/records/real/system-one.jsonl" | tr -d ' ')" "records the client wrote"
fi

# ------------------ replay: what flow-s1.sh would ignore, refused at load
# flow-s1.sh ignores a FLOW_STATE_DIR or FLOW_USER_SETTINGS holding a
# control character and uses the user's own state folder and settings, and
# writes no record into a records folder that is a link; a state that is not
# a regular file is not one it reads. The replay refuses each before
# anything is created or sent.
if _want replay-usage-first; then
  _replay_setup replay-usage-first "a records folder or settings path holding a control character, a records folder that is a link, a state that is a FIFO, a scratch folder inside the repository, and a records file that cannot be read each stop the replay with exit 2 before any request, record, scratch folder or plugin copy"
  e2e_stub_start ts '{"body":{"model":"jev-1.13.0","answers":{"test_catches_wrong":{"type":"noul","noul":0.97}}}}'
  _provider_settings "$(e2e_stub_url ts)"
  DS_TAB=$(printf '\t')
  cp "$E2E_DIR/provider.json" "$E2E_DIR/provider${DS_TAB}x.json"
  mkdir -p "$E2E_DIR/elsewhere" "$E2E_DIR/records-link"
  ln -s "$E2E_DIR/elsewhere" "$E2E_DIR/records-link/real"
  mkdir -p "$E2E_DIR/records-bad/real"
  printf 'not json\n' > "$E2E_DIR/records-bad/real/system-one.jsonl"
  for DS_U in records-tab settings-tab records-link in-repo records-bad; do
    DS_REC="$E2E_DIR/records-$DS_U" DS_SET="$E2E_DIR/provider.json" DS_SCR="$E2E_DIR/scratch-$DS_U"
    case $DS_U in
      records-tab) DS_REC="$E2E_DIR/rec${DS_TAB}ords"; DS_MSG="--records holds a control character" ;;
      settings-tab) DS_SET="$E2E_DIR/provider${DS_TAB}x.json"; DS_MSG="--provider-settings holds a control character" ;;
      records-link) DS_REC="$E2E_DIR/records-link"; DS_MSG="is a link or not a directory" ;;
      in-repo) DS_SCR="$E2E_REPO/sub/scratch"; DS_MSG="inside a git repository" ;;
      records-bad) DS_REC="$E2E_DIR/records-bad"; DS_MSG="line 1 is not JSON; nothing was sent" ;;
    esac
    e2e_run_bin bin/flow-s1-eval.sh replay --pairs "$DS_PAIRS" --records "$DS_REC" \
      --provider-settings "$DS_SET" --scratch "$DS_SCR" --limit 2
    e2e_expect_equal 2 "$E2E_RC" "exit status, $DS_U"
    e2e_expect_err "$DS_MSG"
    e2e_expect_err_lacks "Traceback"
    e2e_expect_equal "absent" "$([ -e "$DS_SCR" ] && echo present || echo absent)" "no scratch folder, $DS_U"
  done
  e2e_expect_equal "absent absent 0" "$([ -e "$E2E_DIR/rec${DS_TAB}ords" ] && echo present || echo absent) $([ -e "$E2E_REPO/sub" ] && echo present || echo absent) $(find "$E2E_DIR/elsewhere" -mindepth 1 | wc -l | tr -d ' ')" "no records folder, no folder in the repository, nothing written through the link"
  # A state that is a FIFO inside states/: refused as not a regular file,
  # never opened (an open would wait for a writer). A writer is started so a
  # check that opens it ends instead of waiting.
  _py 'import json,sys,os
ps=[json.loads(l) for l in open(sys.argv[1])]
i=[k for k,p in enumerate(ps) if p["label"]!="unobserved"][0]
ps[i]["states"]["real"]["path"]="states/real/fifo.json"
open(sys.argv[1],"w").write("".join(json.dumps(p,sort_keys=True)+"\n" for p in ps))' "$DS_PAIRS"
  mkfifo "$E2E_DIR/export/states/real/fifo.json"
  ( : > "$E2E_DIR/export/states/real/fifo.json" ) &
  DS_WRITER=$!
  e2e_run_bin bin/flow-s1-eval.sh replay --pairs "$DS_PAIRS" --records "$E2E_DIR/records-fifo" \
    --provider-settings "$E2E_DIR/provider.json" --scratch "$E2E_DIR/scratch-fifo" --limit 2
  e2e_expect_equal 2 "$E2E_RC" "exit status, a FIFO state"
  e2e_expect_err "its state file is not a regular file"
  # Release the writer if nothing opened the FIFO.
  { exec 9<>"$E2E_DIR/export/states/real/fifo.json"; exec 9<&-; } 2>/dev/null
  wait "$DS_WRITER" 2>/dev/null
  e2e_expect_equal "0" "$(e2e_stub_requests ts)" "requests"
fi

# ---------------------------------------- score: usage errors before --dest
if _want score-usage-first; then
  _setup score-usage-first "a threshold file that cannot be read, or a --choose-threshold in a folder that is not there, stops the scorer with exit 2 before its --dest is created"
  mkdir -p "$E2E_DIR/p" "$E2E_DIR/records"
  printf '{"ref": "eval:author/c/hidden/t/000000000001", "set": "dev", "stratum": "author", "case": "c", "run": "hidden", "trap": "t", "label": "fail", "hn_behavioral": false, "states": {}}\n' > "$E2E_DIR/p/pairs.jsonl"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/p/pairs.jsonl" --records "$E2E_DIR/records" --dest "$E2E_DIR/s1" --threshold-file "$E2E_DIR/no-such-threshold.json"
  e2e_expect_equal 2 "$E2E_RC" "exit status, a threshold file that is not there"
  e2e_expect_err "--threshold-file cannot be read"
  e2e_run_bin bin/flow-s1-eval.sh score --pairs "$E2E_DIR/p/pairs.jsonl" --records "$E2E_DIR/records" --dest "$E2E_DIR/s2" --choose-threshold "$E2E_DIR/no-such-dir/t.json"
  e2e_expect_equal 2 "$E2E_RC" "exit status, a --choose-threshold in a folder that is not there"
  e2e_expect_err "--choose-threshold names a file in a folder that is not there"
  e2e_expect_err_lacks "Traceback"
  e2e_expect_equal "absent absent" "$([ -e "$E2E_DIR/s1" ] && echo present || echo absent) $([ -e "$E2E_DIR/s2" ] && echo present || echo absent)" "no --dest folder"
fi
