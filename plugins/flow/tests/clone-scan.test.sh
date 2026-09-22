# Tests for plugins/flow/bin/flow-clone-scan.sh (issue #219, Layer A).
#
# Contract (.decisions/issue-219.md § Interface contracts):
#   - The scan reports what THIS BRANCH introduced, against the merge base.
#     Pre-existing duplication is not a finding; a third copy added to a base
#     that already holds two is.
#   - jscpd enforces a line minimum AND a token minimum. Its default 50-token
#     floor suppresses a genuine 5-line block. The helper therefore pins
#     duplication.minTokens on every invocation, or the whole feature is a
#     check that can only confirm.
#   - The location cited is the ADDED side, whichever side jscpd printed first.
#   - A missing jscpd is STATE=unavailable with a reason and an install command,
#     never STATE=none. "Nobody looked" and "there is nothing" are different
#     answers and only one of them is a clean bill of health.
#   - The scan set comes from `git ls-files`, not from walking the tree.
#
# Expected values are derived from the fixtures by hand, never from the
# helper's own output. The 35-token measurement for the five-line block was
# taken from jscpd's own console reporter before this suite was written.

HELPER="$REPO_ROOT/plugins/flow/bin/flow-clone-scan.sh"

_flow_test_begin "helper exists"
assert_file_exists "$HELPER" "flow-clone-scan.sh is present"

if [ ! -x "$HELPER" ]; then
  _flow_assert_fail "flow-clone-scan.sh is not executable"
  return 0
fi

# --- prerequisites -----------------------------------------------------------
# A usable jscpd is required to exercise the scan for real. Preference order:
# a real binary on PATH (what CI installs), then a node/npx shim so a developer
# without a global install still runs the real detector. Neither: skip loudly.
CS_DIR=$(mktemp -d -t flow-clone-scan.tests.XXXXXX 2>/dev/null)
if [ -z "$CS_DIR" ] || [ ! -d "$CS_DIR" ]; then
  _flow_test_begin "mktemp prerequisite"
  _flow_assert_fail "mktemp -d failed"
  return 0
fi
trap 'rm -rf "$CS_DIR"' EXIT

mkdir -p "$CS_DIR/bin"
CS_JSCPD_SOURCE=""
if command -v jscpd >/dev/null 2>&1; then
  CS_JSCPD_SOURCE="binary on PATH"
elif command -v npx >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  cat > "$CS_DIR/bin/jscpd" <<'SHIM'
#!/usr/bin/env bash
exec npx --yes jscpd@5.3.1 "$@"
SHIM
  chmod +x "$CS_DIR/bin/jscpd"
  PATH="$CS_DIR/bin:$PATH"
  export PATH
  CS_JSCPD_SOURCE="npx shim (jscpd@5.3.1)"
fi

if [ -z "$CS_JSCPD_SOURCE" ]; then
  _flow_test_begin "jscpd prerequisite"
  _flow_assert_pass "SKIP: no jscpd and no node/npx to reach one — the scan cannot be exercised here. CI installs jscpd explicitly; see .github/workflows/flow-tests.yml."
  return 0
fi
_flow_test_begin "jscpd prerequisite"
_flow_assert_pass "jscpd reachable via $CS_JSCPD_SOURCE"

# --- fixture builder ---------------------------------------------------------
# Five identical lines, measured at 35 tokens by jscpd's console reporter.
# Below its default 50-token floor and above the pinned 20.
CS_BODY='    with open(path) as fh:
        data = fh.read()
    parsed = json.loads(data)
    checked = validate(parsed)
    return checked'

# _cs_repo <name> — a git repo whose default branch is `base`. Echoes its path.
_cs_repo() {
  local d="$CS_DIR/$1"
  mkdir -p "$d/src"
  ( cd "$d" || exit 1
    git init -q -b base . >/dev/null 2>&1
    git config user.email flow@test.invalid
    git config user.name "flow test" ) || return 1
  printf '%s\n' "$d"
}

# _cs_commit <repo> <message>
_cs_commit() {
  ( cd "$1" || exit 1; git add -A >/dev/null 2>&1; git commit -q -m "$2" >/dev/null 2>&1 )
}

# _cs_bulk <repo> — writes a file with no internal duplication that clears the
# token floor. Without it a fixture of two tiny files leaves the detector with
# nothing above its threshold, and "found no duplication" is indistinguishable
# from "examined nothing" — which is the distinction this helper exists to keep.
# Measured at 680 tokens, 0 clones.
_cs_bulk() {
  python3 - "$1/src/bulk.py" <<'BULKPY'
import sys
words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel",
         "india", "juliet", "kilo", "lima", "mike", "november", "oscar", "papa",
         "quebec", "romeo", "sierra", "tango", "uniform", "victor", "whiskey",
         "xray", "yankee", "zulu", "amber", "basalt", "cobalt", "dune", "ember",
         "flint", "garnet", "harbor", "ivory", "jasper", "kelp", "larch",
         "marble", "nimbus"]
lines = []
for i, w in enumerate(words):
    lines.append("def measure_%s(%s_in, scale):" % (w, w))
    lines.append("    total_%s = %s_in * %d" % (w, w, i + 3))
    lines.append("    return total_%s / scale" % w)
open(sys.argv[1], "w").write("\n".join(lines) + "\n")
BULKPY
}

# _cs_scan <repo> [extra args...] — runs the helper; sets CS_OUT and CS_CODE.
_cs_scan() {
  local repo="$1"; shift
  CS_OUT=$( cd "$repo" && "$HELPER" "$@" 2>&1 )
  CS_CODE=$?
}

# --- must-fire ---------------------------------------------------------------
# A five-line block copied from a file that already existed. This is the case
# the whole feature exists for.
R=$(_cs_repo firing)
printf 'def load_config(path):\n%s\n' "$CS_BODY" > "$R/src/existing.py"
_cs_bulk "$R"
_cs_commit "$R" base
( cd "$R" && git checkout -q -b feat )
printf 'def read_settings(path):\n%s\n' "$CS_BODY" > "$R/src/added.py"
_cs_commit "$R" add
_cs_scan "$R" --base base --head HEAD --min-lines 5 --min-tokens 20

_flow_test_begin "must-fire: an introduced five-line copy is reported"
assert_exit 0 "$CS_CODE" "exit 0 on a completed scan"
assert_match '^STATE=ok$' "$CS_OUT" "STATE=ok when a pair was found"
assert_match 'CLONE=added ' "$CS_OUT" "a CLONE line is emitted"

_flow_test_begin "must-fire: the ADDED side is cited, not the pre-existing one"
assert_match 'CLONE=added src/added\.py:[0-9]+-[0-9]+ existing src/existing\.py:[0-9]+-[0-9]+' \
  "$CS_OUT" "location is the added file, existing file named second"

_flow_test_begin "must-fire: the pair carries its size"
assert_match 'lines=[0-9]+ tokens=[0-9]+' "$CS_OUT" "lines= and tokens= are reported"

# --- the threshold that cannot fire ------------------------------------------
# The discriminating check for the risk-map row of the same name. The SAME
# fixture, at jscpd's default token floor, must find nothing — which is why the
# helper pins the value rather than inheriting it.
_cs_scan "$R" --base base --head HEAD --min-lines 5 --min-tokens 50
_flow_test_begin "threshold: the same block is invisible at jscpd's default token floor"
assert_match '^STATE=none$' "$CS_OUT" "STATE=none at 50 tokens — the block is 35"
assert_not_contains "CLONE=added" "$CS_OUT" "no pair reported at the default floor"
# ...and the silence is a result, not an empty run. Without this the assertion
# above would also pass on a scan that read nothing at all.
CS_ANALYZED=$(printf '%s\n' "$CS_OUT" | sed -n 's/^DETECTOR_SOURCES=//p')
if [ -n "$CS_ANALYZED" ] && [ "$CS_ANALYZED" -gt 0 ] 2>/dev/null; then
  _flow_assert_pass "the detector examined $CS_ANALYZED file(s) and still reported nothing"
else
  _flow_assert_fail "DETECTOR_SOURCES=${CS_ANALYZED:-missing}: the clean result came from an empty run"
fi

# --- must-stay-silent: four lines --------------------------------------------
R4=$(_cs_repo fourline)
CS_BODY4=$(printf '%s\n' "$CS_BODY" | sed -n '1,3p')
printf 'def load_config(path):\n%s\n' "$CS_BODY4" > "$R4/src/existing.py"
_cs_bulk "$R4"
_cs_commit "$R4" base
( cd "$R4" && git checkout -q -b feat )
printf 'def read_settings(path):\n%s\n' "$CS_BODY4" > "$R4/src/added.py"
_cs_commit "$R4" add
_cs_scan "$R4" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "must-stay-silent: a four-line copy is below the line minimum"
assert_match '^STATE=none$' "$CS_OUT" "STATE=none for a four-line copy"
assert_exit 0 "$CS_CODE" "a clean scan still exits 0"
CS_ANALYZED=$(printf '%s\n' "$CS_OUT" | sed -n 's/^DETECTOR_SOURCES=//p')
if [ -n "$CS_ANALYZED" ] && [ "$CS_ANALYZED" -gt 0 ] 2>/dev/null; then
  _flow_assert_pass "examined $CS_ANALYZED file(s)"
else
  _flow_assert_fail "DETECTOR_SOURCES=${CS_ANALYZED:-missing}: nothing was examined"
fi

# --- must-stay-silent: excluded path -----------------------------------------
RX=$(_cs_repo excluded)
printf 'def load_config(path):\n%s\n' "$CS_BODY" > "$RX/src/existing.py"
_cs_commit "$RX" base
( cd "$RX" && git checkout -q -b feat; mkdir -p tests )
printf 'def read_settings(path):\n%s\n' "$CS_BODY" > "$RX/tests/added.py"
_cs_commit "$RX" add
_cs_scan "$RX" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "must-stay-silent: the same block under an excluded path"
assert_match '^STATE=none$' "$CS_OUT" "a copy under tests/ is exempt by default"

# ...and the exclusion is a path rule, not a blanket silence: the identical
# block outside the excluded path is still reported.
_cs_scan "$RX" --base base --head HEAD --min-lines 5 --min-tokens 20 --exclude-paths '**/never-matches-anything/**'
_flow_test_begin "excluded path: the exemption is what silenced it, nothing else"
assert_match '^STATE=ok$' "$CS_OUT" "the same fixture fires once tests/ is not excluded"
assert_match 'CLONE=added tests/added\.py' "$CS_OUT" "and it is the added side that is cited"

# --- within-diff pairs are P3, not P2 ----------------------------------------
RW=$(_cs_repo within)
printf 'placeholder\n' > "$RW/README.md"
_cs_commit "$RW" base
( cd "$RW" && git checkout -q -b feat )
printf 'def load_config(path):\n%s\n' "$CS_BODY" > "$RW/src/one.py"
printf 'def read_settings(path):\n%s\n' "$CS_BODY" > "$RW/src/two.py"
_cs_commit "$RW" add
_cs_scan "$RW" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "within-diff: both sides added is CLONE_WITHIN_DIFF, not CLONE=added"
assert_match 'CLONE_WITHIN_DIFF=' "$CS_OUT" "the within-diff line is emitted"
assert_not_contains "CLONE=added" "$CS_OUT" "it is not reported as duplicating existing code"

# --- pre-existing duplication is not a finding -------------------------------
RP=$(_cs_repo preexisting)
printf 'def load_a(path):\n%s\n' "$CS_BODY" > "$RP/src/a.py"
printf 'def load_b(path):\n%s\n' "$CS_BODY" > "$RP/src/b.py"
_cs_commit "$RP" base
( cd "$RP" && git checkout -q -b feat )
printf 'unrelated\n' > "$RP/README.md"
_cs_commit "$RP" unrelated
_cs_scan "$RP" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "baseline: duplication that already existed is not reported"
assert_match '^STATE=none$' "$CS_OUT" "a branch that introduced nothing reports nothing"

# --- but a third copy is ------------------------------------------------------
( cd "$RP" && git checkout -q feat )
printf 'def load_c(path):\n%s\n' "$CS_BODY" > "$RP/src/c.py"
_cs_commit "$RP" third
_cs_scan "$RP" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "baseline: a third copy added to a base holding two IS reported"
assert_match '^STATE=ok$' "$CS_OUT" "the new pair surfaces"
assert_match 'CLONE=added src/c\.py' "$CS_OUT" "and c.py — the added side — is the location"

# --- input removal -----------------------------------------------------------
RE=$(_cs_repo emptytree)
printf 'placeholder\n' > "$RE/README.md"
_cs_commit "$RE" base
( cd "$RE" && git checkout -q -b feat )
printf 'still placeholder\n' > "$RE/README.md"
_cs_commit "$RE" edit
_cs_scan "$RE" --base base --head HEAD --min-lines 5 --min-tokens 20 --format python
_flow_test_begin "input removal: a scan that reached no file says so and fails"
assert_match '^STATE=unavailable$' "$CS_OUT" "nothing scanned is unavailable, not none"
assert_exit 2 "$CS_CODE" "and exits non-zero"
assert_match '^REASON=' "$CS_OUT" "with a reason"

# --- jscpd absent ---------------------------------------------------------
# A PATH that still has an interpreter, git and python3 but no detector. An
# empty PATH would fail at the shebang and prove nothing about the guard.
mkdir -p "$CS_DIR/nojscpd"
CS_BARE_PATH="/usr/bin:/bin"
if PATH="$CS_BARE_PATH" command -v jscpd >/dev/null 2>&1; then
  _flow_test_begin "absent detector"
  _flow_assert_pass "SKIP: jscpd is installed under $CS_BARE_PATH, so the absent branch cannot be isolated here"
else
  CS_OUT=$( cd "$R" && PATH="$CS_BARE_PATH" "$HELPER" --base base --head HEAD 2>&1 )
  CS_CODE=$?
  _flow_test_begin "absent detector: unavailable with an install command, never none"
  assert_match '^STATE=unavailable$' "$CS_OUT" "a missing jscpd is unavailable"
  assert_not_contains "STATE=none" "$CS_OUT" "it must not read as a clean scan"
  assert_exit 2 "$CS_CODE" "exit 2"
  assert_match '^INSTALL=' "$CS_OUT" "the install command is named"
  assert_match '^REASON=' "$CS_OUT" "and the reason is stated"

  # Once per run: a caller that sees two STATE lines cannot tell which is the
  # answer, and a repeated INSTALL line is the nagging this feature promised
  # not to do.
  _flow_test_begin "absent detector: the answer is stated exactly once"
  CS_N_STATE=$(printf '%s\n' "$CS_OUT" | grep -c '^STATE=')
  CS_N_INSTALL=$(printf '%s\n' "$CS_OUT" | grep -c '^INSTALL=')
  assert_equal "1" "$CS_N_STATE" "exactly one STATE line"
  assert_equal "1" "$CS_N_INSTALL" "exactly one INSTALL line"
fi

# --- no silent install -------------------------------------------------------
# Behavioural, not textual: the helper names an install command in its output,
# so grepping its source for the words would fail on the very message the
# contract requires. Stubs that log any invocation are put first on PATH; the
# helper must reach neither, even on the path where it reports the detector
# missing.
mkdir -p "$CS_DIR/fetchbin"
for _f in npx npm; do
  cat > "$CS_DIR/fetchbin/$_f" <<'FETCHSTUB'
#!/usr/bin/env bash
printf '%s\n' "INVOKED $0 $*" >> "$CS_FETCH_LOG"
exit 0
FETCHSTUB
  chmod +x "$CS_DIR/fetchbin/$_f"
done
: > "$CS_DIR/fetch.log"
if ! PATH="$CS_BARE_PATH" command -v jscpd >/dev/null 2>&1; then
  ( cd "$R" && CS_FETCH_LOG="$CS_DIR/fetch.log" \
      PATH="$CS_DIR/fetchbin:$CS_BARE_PATH" "$HELPER" --base base --head HEAD >/dev/null 2>&1 )
fi
_flow_test_begin "no silent install: no package fetcher is invoked, even when the detector is missing"
CS_FETCH=$(cat "$CS_DIR/fetch.log")
assert_equal "" "$CS_FETCH" "neither npx nor npm was executed"

# The stubs must be reachable, or the assertion above passes because nothing
# could have run — the input-removal mutant for this check.
_flow_test_begin "no silent install: the fetcher stubs were reachable"
CS_PROOF=$( CS_FETCH_LOG="$CS_DIR/fetch.log" PATH="$CS_DIR/fetchbin:$CS_BARE_PATH" npx --version >/dev/null 2>&1; cat "$CS_DIR/fetch.log" )
assert_contains "INVOKED" "$CS_PROOF" "a direct call does reach the stub"

# --- unparseable report ------------------------------------------------------
# A detector that ran but produced nothing readable is unavailable, not none.
mkdir -p "$CS_DIR/badreport"
cat > "$CS_DIR/badreport/jscpd" <<'BADSTUB'
#!/usr/bin/env bash
OUTDIR=""
while [ $# -gt 0 ]; do
  [ "$1" = "--output" ] && OUTDIR="$2"
  shift
done
[ -n "$OUTDIR" ] && { mkdir -p "$OUTDIR"; printf '%s\n' "{not json" > "$OUTDIR/jscpd-report.json"; }
exit 0
BADSTUB
chmod +x "$CS_DIR/badreport/jscpd"
CS_OUT=$( cd "$R" && PATH="$CS_DIR/badreport:$CS_BARE_PATH" "$HELPER" --base base --head HEAD 2>&1 )
CS_CODE=$?
_flow_test_begin "unreadable report: the detector ran but said nothing readable"
assert_match '^STATE=unavailable$' "$CS_OUT" "an unparseable report is unavailable"
assert_not_contains "STATE=none" "$CS_OUT" "never a clean result"
assert_exit 2 "$CS_CODE" "exit 2"

# --- unresolvable base ref ---------------------------------------------------
_cs_scan "$R" --base no-such-ref-anywhere --head HEAD
_flow_test_begin "unresolvable base: a ref that does not exist is unavailable"
assert_match '^STATE=unavailable$' "$CS_OUT" "an unresolvable base ref is unavailable"
assert_exit 2 "$CS_CODE" "exit 2"

# --- the exclude list is READ, not hardcoded ---------------------------------
# The default-excludes case alone cannot tell "reads duplication.excludePaths"
# from "hardcodes that list": both pass. A non-default override discriminates.
RS=$(_cs_repo settingsread)
printf 'def load_config(path):\n%s\n' "$CS_BODY" > "$RS/src/existing.py"
_cs_commit "$RS" base
( cd "$RS" && git checkout -q -b feat; mkdir -p src/generated )
printf 'def read_settings(path):\n%s\n' "$CS_BODY" > "$RS/src/generated/added.py"
_cs_commit "$RS" add
_cs_scan "$RS" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "exclude list: a path outside the defaults is reported"
assert_match '^STATE=ok$' "$CS_OUT" "src/generated is not excluded by default"
_cs_scan "$RS" --base base --head HEAD --min-lines 5 --min-tokens 20 --exclude-paths '**/generated/**'
_flow_test_begin "exclude list: and a caller-supplied glob silences it"
assert_match '^STATE=none$' "$CS_OUT" "the supplied glob is honoured, so the list is read"

# --- untracked files are not in the scan set ---------------------------------
RU=$(_cs_repo untracked)
printf 'def load_config(path):\n%s\n' "$CS_BODY" > "$RU/src/existing.py"
_cs_commit "$RU" base
( cd "$RU" && git checkout -q -b feat )
printf 'placeholder\n' > "$RU/src/note.txt"
_cs_commit "$RU" note
printf 'def read_settings(path):\n%s\n' "$CS_BODY" > "$RU/src/untracked_copy.py"
_cs_scan "$RU" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "scan set: an untracked copy is not scanned"
assert_match '^STATE=none$' "$CS_OUT" "a file git does not track is not a finding"
assert_not_contains "untracked_copy" "$CS_OUT" "and is never named"

# --- the report parser, pinned against a crafted report ------------------------
# Three properties of the parser cannot be produced on demand by the real
# detector, so they are driven by a stub that writes a report of our choosing:
#   1. a pair the detector calls new whose two sides are BOTH outside the diff
#      must be dropped — measured on the #218 branch, 8 of 10 flagged pairs
#      were of exactly this shape;
#   2. a pair with both sides inside the diff is CLONE_WITHIN_DIFF;
#   3. the exclude globs actually reach the detector, which the real-jscpd
#      fixtures cannot show, because the scan set is filtered here as well and
#      either mechanism alone silences them.
RC=$(_cs_repo craftedreport)
printf 'def load_config(path):\n%s\n' "$CS_BODY" > "$RC/src/existing.py"
printf 'def untouched_one(path):\n%s\n' "$CS_BODY" > "$RC/src/untouched_a.py"
printf 'def untouched_two(path):\n%s\n' "$CS_BODY" > "$RC/src/untouched_b.py"
_cs_commit "$RC" base
( cd "$RC" && git checkout -q -b feat )
printf 'def read_settings(path):\n%s\n' "$CS_BODY" > "$RC/src/added.py"
printf 'def first_new(path):\n%s\n' "$CS_BODY" > "$RC/src/one_new.py"
printf 'def second_new(path):\n%s\n' "$CS_BODY" > "$RC/src/two_new.py"
_cs_commit "$RC" add

mkdir -p "$CS_DIR/craftbin"
cat > "$CS_DIR/craftbin/jscpd" <<'CRAFTSTUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CS_ARGV_LOG"
OUTDIR=""
PREV=""
for A in "$@"; do
  [ "$PREV" = "--output" ] && OUTDIR="$A"
  PREV="$A"
done
[ -n "$OUTDIR" ] || exit 1
mkdir -p "$OUTDIR"
CRAFT_OUT="$OUTDIR/jscpd-report.json" python3 -c '
import json, os, sys
root = os.getcwd()
def f(name, a, b):
    return {"name": os.path.join(root, name), "start": a, "end": b}
report = {
  "duplicates": [
    {"firstFile": f("src/existing.py", 1, 6), "secondFile": f("src/added.py", 1, 6),
     "isNew": True, "lines": 6, "tokens": 35, "format": "python", "kind": "exact"},
    {"firstFile": f("src/one_new.py", 1, 6), "secondFile": f("src/two_new.py", 1, 6),
     "isNew": True, "lines": 6, "tokens": 35, "format": "python", "kind": "exact"},
    {"firstFile": f("src/untouched_a.py", 1, 6), "secondFile": f("src/untouched_b.py", 1, 6),
     "isNew": True, "lines": 6, "tokens": 35, "format": "python", "kind": "exact"},
  ],
  "statistics": {"total": {"sources": 6, "clones": 3}},
}
open(os.environ["CRAFT_OUT"], "w").write(json.dumps(report))
'
exit 0
CRAFTSTUB
chmod +x "$CS_DIR/craftbin/jscpd"

CS_OUT=$( cd "$RC" && CS_ARGV_LOG="$CS_DIR/argv.log" \
  PATH="$CS_DIR/craftbin:$CS_BARE_PATH" "$HELPER" --base base --head HEAD \
  --min-lines 5 --min-tokens 20 2>&1 )
CS_CODE=$?

_flow_test_begin "crafted report: a new pair touching no changed file is dropped"
assert_exit 0 "$CS_CODE" "exit 0"
assert_not_contains "untouched_a" "$CS_OUT" "the untouched pair is not reported"
assert_not_contains "untouched_b" "$CS_OUT" "neither side of it is named"

_flow_test_begin "crafted report: the other two pairs ARE reported"
# Without these the assertions above would pass on a parser that reports
# nothing at all.
assert_match 'CLONE=added src/added\.py:1-6 existing src/existing\.py:1-6' "$CS_OUT" \
  "the added-side pair survives, cited on the added side"
assert_match 'CLONE_WITHIN_DIFF=src/one_new\.py:1-6 src/two_new\.py:1-6' "$CS_OUT" \
  "the both-sides-added pair is within-diff"
CS_N_ADDED=$(printf '%s\n' "$CS_OUT" | grep -c '^CLONE=added ')
CS_N_WITHIN=$(printf '%s\n' "$CS_OUT" | grep -c '^CLONE_WITHIN_DIFF=')
assert_equal "1" "$CS_N_ADDED" "exactly one added-side pair"
assert_equal "1" "$CS_N_WITHIN" "exactly one within-diff pair"

_flow_test_begin "crafted report: the exclude globs reach the detector"
# The scan set is filtered here too, so a fixture alone cannot tell whether the
# globs were passed on. The detector's own argv can.
CS_N_IGNORE=$(grep -c -- '--ignore' "$CS_DIR/argv.log")
if [ "$CS_N_IGNORE" -gt 0 ] 2>/dev/null; then
  _flow_assert_pass "the detector was given $CS_N_IGNORE --ignore flag(s)"
else
  _flow_assert_fail "no --ignore reached the detector: the base-tree scan would not honour excludePaths"
fi
CS_N_MINTOK=$(grep -c -- '--min-tokens' "$CS_DIR/argv.log")
assert_equal "1" "$CS_N_MINTOK" "the token floor is pinned on the invocation, not inherited"

# --- run from a subdirectory ---------------------------------------------------
# `git ls-files` is limited to the working directory. A scan started anywhere
# but the root would enumerate a subtree and report that count as the whole
# scan set: fewer files, no findings, and nothing in the output saying so.
mkdir -p "$R/src/deeper"
CS_OUT=$( cd "$R/src/deeper" && "$HELPER" --base base --head HEAD --min-lines 5 --min-tokens 20 2>&1 )
CS_CODE=$?
_flow_test_begin "subdirectory: the scan set is the repository, not the working directory"
assert_exit 0 "$CS_CODE" "exit 0 from a subdirectory"
assert_match '^STATE=ok$' "$CS_OUT" "the pair is still found"
assert_match 'CLONE=added src/added\.py' "$CS_OUT" "and paths stay repository-relative"

# --- the shared range library is a hard requirement -----------------------------
# A helper that cannot load it must not carry on with an inline copy, and must
# not exit in silence either: a caller reading stdout has to be able to tell a
# helper that never ran from a scan that found nothing.
mkdir -p "$CS_DIR/orphan"
cp "$HELPER" "$CS_DIR/orphan/flow-clone-scan.sh"
chmod +x "$CS_DIR/orphan/flow-clone-scan.sh"
CS_OUT=$( cd "$R" && "$CS_DIR/orphan/flow-clone-scan.sh" --base base --head HEAD 2>/dev/null )
CS_CODE=$?
_flow_test_begin "missing library: reported on stdout, not merely on stderr"
assert_match '^STATE=unavailable$' "$CS_OUT" "the absent library is unavailable"
assert_not_contains "STATE=none" "$CS_OUT" "never a clean scan"
assert_match '^REASON=' "$CS_OUT" "with a reason"
assert_exit 2 "$CS_CODE" "exit 2"

# And the same copy works once the library is beside it — otherwise the case
# above would pass for any reason at all, including a typo in the copy.
mkdir -p "$CS_DIR/orphan/lib"
cp "$REPO_ROOT/plugins/flow/bin/lib/range-args.sh" "$CS_DIR/orphan/lib/range-args.sh"
CS_OUT=$( cd "$R" && "$CS_DIR/orphan/flow-clone-scan.sh" --base base --head HEAD --min-lines 5 --min-tokens 20 2>&1 )
CS_CODE=$?
_flow_test_begin "missing library: the copy runs once the library is beside it"
assert_exit 0 "$CS_CODE" "exit 0"
assert_match '^STATE=ok$' "$CS_OUT" "and finds the pair it should"

# --- an exclude glob containing a space stays one pattern -----------------------
# The rest of the command line is handed back from the library as an array and
# re-expanded. Word splitting there would turn one glob into two, silently
# widening or narrowing the scan set with nothing in the output to show it.
CS_A=$( cd "$REPO_ROOT" && "$HELPER" --base HEAD --head HEAD --print-scan-set \
  --exclude-paths 'plugins/flow/bin/**' 2>&1 | sed -n 's/^FILES_SCANNED=//p' )
CS_B=$( cd "$REPO_ROOT" && "$HELPER" --base HEAD --head HEAD --print-scan-set \
  --exclude-paths 'no such dir/**,plugins/flow/bin/**' 2>&1 | sed -n 's/^FILES_SCANNED=//p' )
CS_C=$( cd "$REPO_ROOT" && "$HELPER" --base HEAD --head HEAD --print-scan-set \
  --exclude-paths 'no such dir/**' 2>&1 | sed -n 's/^FILES_SCANNED=//p' )
_flow_test_begin "quoting: a glob containing a space is one pattern, not two"
assert_equal "$CS_A" "$CS_B" "prepending a spaced, non-matching glob changes nothing"
# ...and the comparison is not vacuous: the excluded glob really does exclude.
if [ -n "$CS_C" ] && [ -n "$CS_A" ] && [ "$CS_C" -gt "$CS_A" ] 2>/dev/null; then
  _flow_assert_pass "excluding bin/ removed $((CS_C - CS_A)) files, so the counts discriminate"
else
  _flow_assert_fail "excluding bin/ changed nothing ($CS_C vs $CS_A): the comparison proves nothing"
fi

# --- turned off is not the same as found nothing --------------------------------
# A team that disables the layer has not learned that there is no duplication.
# Reporting `none` here would be a clean duplication review nobody performed.
RD=$(_cs_repo disabled)
printf 'def load_config(path):\n%s\n' "$CS_BODY" > "$RD/src/existing.py"
_cs_commit "$RD" base
( cd "$RD" && git checkout -q -b feat )
printf 'def read_settings(path):\n%s\n' "$CS_BODY" > "$RD/src/added.py"
_cs_commit "$RD" add
mkdir -p "$RD/.claude"
printf '%s\n' '{"duplication": {"enabled": false}}' > "$RD/.claude/settings.flow.json"
_cs_scan "$RD" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "disabled: reported as unavailable, not as a clean scan"
assert_match '^STATE=unavailable$' "$CS_OUT" "a disabled layer is unavailable"
assert_not_contains "STATE=none" "$CS_OUT" "never as no duplication found"
assert_exit 0 "$CS_CODE" "and exits 0 — a deliberate setting is not a failure"
assert_match '^REASON=.*enabled' "$CS_OUT" "the reason names the setting"

# The control: the same fixture DOES report a pair once the setting is removed,
# so the case above cannot pass on a scanner that reports nothing regardless.
rm -f "$RD/.claude/settings.flow.json"
_cs_scan "$RD" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "disabled: the setting is what silenced it"
assert_match '^STATE=ok$' "$CS_OUT" "the same fixture fires with the setting gone"

# --- resolving settings must not warn about valid files -------------------------
# A jq filter that errors on a source lacking the key makes cascade-resolve
# report that whole file unparseable. The value still resolves from a lower
# tier, so the only symptom is a warning on every run about a file that is
# perfectly valid — the kind of noise that gets ignored and then hides a real one.
CS_ERR=$( cd "$REPO_ROOT" && "$HELPER" --base HEAD --head HEAD --print-scan-set 2>&1 >/dev/null )
_flow_test_begin "settings: resolving the exclude list warns about nothing"
assert_not_contains "failed to parse" "$CS_ERR" "no settings source is reported unparseable"
assert_equal "" "$CS_ERR" "nothing at all on stderr for a clean run"

# --- an option value is never mistaken for a range ------------------------------
# The library reads any argument containing `..` as a range. A relative glob
# does too, so without the value-option declaration `--exclude-paths ../foo/**`
# is parsed as base `.` and head `/foo/**`, and the helper refuses its own
# command line. A caller cannot tell that from a typo in their glob.
CS_OUT=$( cd "$REPO_ROOT" && "$HELPER" --base HEAD --head HEAD --print-scan-set \
  --exclude-paths '../foo/**' 2>&1 )
CS_CODE=$?
_flow_test_begin "option values containing .. are not read as a range"
assert_not_contains "usage:" "$CS_OUT" "the command line is accepted"
assert_exit 0 "$CS_CODE" "and the run proceeds"
assert_match '^FILES_SCANNED=[0-9]+$' "$CS_OUT" "the scan set is reported"

# The control: a genuine positional range is still recognised, so the fix did
# not simply stop the library reading ranges at all.
CS_OUT=$( cd "$REPO_ROOT" && "$HELPER" HEAD..HEAD --print-scan-set 2>&1 )
CS_CODE=$?
_flow_test_begin "a positional range is still a range"
assert_exit 0 "$CS_CODE" "the positional form still works"
assert_match '^FILES_SCANNED=[0-9]+$' "$CS_OUT" "and reports the scan set"

# --- enumerating the scan set does not need the detector ------------------------
# `--print-scan-set` only reads git. Requiring the detector for it would leave
# someone asking "why is my scan set this size?" on a machine without jscpd
# with an answer about jscpd instead of an answer to their question.
if ! PATH="$CS_BARE_PATH" command -v jscpd >/dev/null 2>&1; then
  CS_OUT=$( cd "$REPO_ROOT" && PATH="$CS_BARE_PATH" "$HELPER" --base HEAD --head HEAD --print-scan-set 2>&1 )
  CS_CODE=$?
  _flow_test_begin "scan set: enumeration answers without a detector installed"
  assert_exit 0 "$CS_CODE" "exit 0"
  assert_match '^FILES_SCANNED=[0-9]+$' "$CS_OUT" "the scan set is reported"
  assert_not_contains "jscpd is not installed" "$CS_OUT" "and the answer is not about the detector"

  # The control: a real scan on the same PATH still refuses, so the case above
  # is not simply the detector check having been removed.
  CS_OUT=$( cd "$R" && PATH="$CS_BARE_PATH" "$HELPER" --base base --head HEAD 2>&1 )
  _flow_test_begin "scan set: a real scan still requires the detector"
  assert_match '^STATE=unavailable$' "$CS_OUT" "the scan itself still reports unavailable"
else
  _flow_test_begin "scan set without a detector"
  _flow_assert_pass "SKIP: jscpd is present under $CS_BARE_PATH, so the branch cannot be isolated"
fi

# --- real, full-size input ---------------------------------------------------
# One run over this repository's own tree, with FILES_SCANNED reconciled
# against an independent enumeration. A count that matched nothing would look
# exactly like a clean result without this.
_flow_test_begin "real tree: FILES_SCANNED reconciles with git ls-files"
CS_REAL=$( cd "$REPO_ROOT" && "$HELPER" --base HEAD --head HEAD --print-scan-set 2>&1 )
CS_REAL_CODE=$?
CS_SCANNED=$(printf '%s\n' "$CS_REAL" | sed -n 's/^FILES_SCANNED=//p')
CS_REPORTED_TRACKED=$(printf '%s\n' "$CS_REAL" | sed -n 's/^FILES_TRACKED=//p')
CS_TRACKED=$( cd "$REPO_ROOT" && git ls-files | wc -l | tr -d ' ' )
if [ -z "$CS_SCANNED" ]; then
  _flow_assert_fail "the helper printed no FILES_SCANNED over the real tree (exit $CS_REAL_CODE)"
else
  if [ "$CS_SCANNED" -gt 0 ] 2>/dev/null; then
    _flow_assert_pass "examined $CS_SCANNED files"
  else
    _flow_assert_fail "FILES_SCANNED=0 over a repository with $CS_TRACKED tracked files"
  fi
  # The helper's own view of what git tracks must equal an independent count.
  # Without this, "within the tracked set" holds for any walk that happens to be
  # smaller, including one that never reached git at all.
  assert_equal "$CS_TRACKED" "$CS_REPORTED_TRACKED" \
    "the helper's tracked count matches git ls-files exactly"
  if [ "$CS_SCANNED" -le "$CS_TRACKED" ] 2>/dev/null; then
    _flow_assert_pass "scan set ($CS_SCANNED) is within the tracked set ($CS_TRACKED)"
  else
    _flow_assert_fail "scanned $CS_SCANNED files but only $CS_TRACKED are tracked — the walk escaped git"
  fi
  # And the excludes did something: equal counts would mean the default exclude
  # list never reached the filter, which is the mutant that survived once.
  if [ "$CS_SCANNED" -lt "$CS_TRACKED" ] 2>/dev/null; then
    _flow_assert_pass "the default excludes removed $((CS_TRACKED - CS_SCANNED)) tracked files"
  else
    _flow_assert_fail "scan set equals the tracked set — the default excludes did nothing"
  fi
fi
