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
# The settings cascade is reached through the plugin root. Unpinned, that root
# is whatever copy of the plugin happens to be installed on the machine — which
# is why this case passed locally and failed on CI, where none is. Pin it to
# the tree under test so the case exercises the settings path deterministically.
CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" _cs_scan "$RD" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "disabled: reported as unavailable, not as a clean scan"
assert_match '^STATE=unavailable$' "$CS_OUT" "a disabled layer is unavailable"
assert_not_contains "STATE=none" "$CS_OUT" "never as no duplication found"
assert_exit 0 "$CS_CODE" "and exits 0 — a deliberate setting is not a failure"
assert_match '^REASON=.*enabled' "$CS_OUT" "the reason names the setting"

# The control: the same fixture DOES report a pair once the setting is removed,
# so the case above cannot pass on a scanner that reports nothing regardless.
rm -f "$RD/.claude/settings.flow.json"
CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" _cs_scan "$RD" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "disabled: the setting is what silenced it"
assert_match '^STATE=ok$' "$CS_OUT" "the same fixture fires with the setting gone"

# --- resolving settings must not warn about valid files -------------------------
# A jq filter that errors on a source lacking the key makes cascade-resolve
# report that whole file unparseable. The value still resolves from a lower
# tier, so the only symptom is a warning on every run about a file that is
# perfectly valid — the kind of noise that gets ignored and then hides a real one.
CS_ERR=$( cd "$REPO_ROOT" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" \
  "$HELPER" --base HEAD --head HEAD --print-scan-set 2>&1 >/dev/null )
_flow_test_begin "settings: resolving the exclude list warns about nothing"
assert_not_contains "failed to parse" "$CS_ERR" "no settings source is reported unparseable"
assert_not_contains "Cannot iterate over null" "$CS_ERR" "the filter handles a source that lacks the key"
# Strict again: the helper now resolves its root as a sibling of itself, so
# there is no pipeline to race and nothing benign left to allow through.
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

# --- paths the detector and git spell differently --------------------------------
# `git diff --name-only` quotes a non-ASCII path while `ls-files -z` does not,
# so without -z the two sets never intersect and the pair is dropped in silence.
RN=$(_cs_repo nonascii)
printf 'def load_config(path):\n%s\n' "$CS_BODY" > "$RN/src/existing.py"
_cs_bulk "$RN"
_cs_commit "$RN" base
( cd "$RN" && git checkout -q -b feat )
printf 'def read_settings(path):\n%s\n' "$CS_BODY" > "$RN/src/café.py"
_cs_commit "$RN" add
_cs_scan "$RN" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "a non-ASCII path is still reported"
assert_match '^STATE=ok$' "$CS_OUT" "the pair is found"
assert_contains "café.py" "$CS_OUT" "and the path is cited as git spells it"

# --- a path that would be read as an option --------------------------------------
# A tracked name beginning with a dash is legal. Handed to the detector without
# a -- separator it is consumed as an option and the file is never parsed,
# while the run still reports a clean scan.
RDash=$(_cs_repo dashname)
printf 'def load_config(path):\n%s\n' "$CS_BODY" > "$RDash/src/existing.py"
_cs_bulk "$RDash"
_cs_commit "$RDash" base
( cd "$RDash" && git checkout -q -b feat )
# At the repository root, so the path itself begins with a dash. In a
# subdirectory it would read "src/-silent.py" and carry no hazard at all.
printf 'def read_settings(path):\n%s\n' "$CS_BODY" > "$RDash/-silent.py"
_cs_commit "$RDash" add
_cs_scan "$RDash" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "a dash-leading path is a file, not an option"
assert_match '^STATE=ok$' "$CS_OUT" "the pair is found"
assert_contains "-silent.py" "$CS_OUT" "and the file was parsed rather than read as a flag"

# --- a colon in a path -----------------------------------------------------------
RC2=$(_cs_repo colonname)
printf 'def load_config(path):\n%s\n' "$CS_BODY" > "$RC2/src/ex:isting.py"
_cs_bulk "$RC2"
_cs_commit "$RC2" base
( cd "$RC2" && git checkout -q -b feat )
printf 'def read_settings(path):\n%s\n' "$CS_BODY" > "$RC2/src/added.py"
_cs_commit "$RC2" add
_cs_scan "$RC2" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "a colon in a path is not a line number"
assert_match '^STATE=ok$' "$CS_OUT" "the pair is found"
assert_contains "src/ex:isting.py" "$CS_OUT" "and the existing side is cited whole, not truncated"

# --- a pipe in a path is encoded -------------------------------------------------
# The interface contract says a literal pipe is written %7C, because a raw one
# splits a downstream marker row.
RP2=$(_cs_repo pipename)
printf 'def load_config(path):\n%s\n' "$CS_BODY" > "$RP2/src/existing.py"
_cs_bulk "$RP2"
_cs_commit "$RP2" base
( cd "$RP2" && git checkout -q -b feat )
printf 'def read_settings(path):\n%s\n' "$CS_BODY" > "$RP2/src/pi|pe.py"
_cs_commit "$RP2" add
_cs_scan "$RP2" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "a pipe in a path is percent-encoded"
assert_match '^STATE=ok$' "$CS_OUT" "the pair is found"
CS_CLONE_LINE=$(printf '%s\n' "$CS_OUT" | grep '^CLONE=added ')
assert_contains "pi%7Cpe.py" "$CS_CLONE_LINE" "the pipe is encoded"
assert_not_contains "pi|pe.py" "$CS_CLONE_LINE" "and no literal pipe reaches the row"

# --- the gate runs before the commit ---------------------------------------------
# commands/start.md runs the task-time gate at step 8b, before the commit at
# step 9. A changed set built only from committed history does not hold the code
# the task just wrote, so the gate would be blind exactly where it is invoked.
RS2=$(_cs_repo staged)
printf 'def load_config(path):\n%s\n' "$CS_BODY" > "$RS2/src/existing.py"
_cs_bulk "$RS2"
_cs_commit "$RS2" base
( cd "$RS2" && git checkout -q -b feat )
printf 'def read_settings(path):\n%s\n' "$CS_BODY" > "$RS2/src/added.py"
( cd "$RS2" && git add src/added.py )
_cs_scan "$RS2" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "staged but uncommitted work is in the changed set"
assert_match '^STATE=ok$' "$CS_OUT" "the gate sees the task's own code"
assert_match 'CLONE=added src/added\.py' "$CS_OUT" "cited on the added side"

# --- a threshold that cannot fire is refused -------------------------------------
_cs_scan "$R" --base base --head HEAD --min-lines 0 --min-tokens 20
_flow_test_begin "a zero threshold is refused rather than silently silencing the scan"
assert_exit 1 "$CS_CODE" "--min-lines 0 is a usage error"
_cs_scan "$R" --base base --head HEAD --min-lines 5 --min-tokens 0
assert_exit 1 "$CS_CODE" "--min-tokens 0 is a usage error"

# --- the exclusion translator terminates -----------------------------------------
# Adjacent `**/` groups match the same language and backtrack exponentially,
# and the pattern comes from the settings of the branch under review.
_flow_test_begin "a pathological exclude pattern does not hang the scan"
# A deep path, because the backtracking is over path SEGMENTS: against a
# two-segment fixture path the pathological pattern is cheap whether or not the
# groups are collapsed, and the case proves nothing.
CS_DEEP="$R/src/l1/l2/l3/l4/l5/l6/l7/l8/l9/l10/l11/l12/l13/l14/l15/l16/l17/l18/l19/l20"
mkdir -p "$CS_DEEP"
printf 'def deep_one(path):\n%s\n' "$CS_BODY" > "$CS_DEEP/deep.py"
( cd "$R" && git add -A && git commit -q -m deep )
CS_PATHOLOGICAL='**/**/**/**/**/**/**/**/**/**/**/**/nomatch.py'
CS_T0=$(date +%s)
_cs_scan "$R" --base base --head HEAD --min-lines 5 --min-tokens 20 --exclude-paths "$CS_PATHOLOGICAL"
CS_T1=$(date +%s)
CS_ELAPSED=$((CS_T1 - CS_T0))
assert_exit 0 "$CS_CODE" "the scan completes"
if [ "$CS_ELAPSED" -le 30 ] 2>/dev/null; then
  _flow_assert_pass "twelve adjacent globs translated and matched in ${CS_ELAPSED}s"
else
  _flow_assert_fail "the exclusion pass took ${CS_ELAPSED}s on twelve adjacent globs"
fi

# --- controls for the two silence cases that had none ----------------------------
_flow_test_begin "within-diff: the same fixture reports an added pair when one side is pre-existing"
assert_match 'CLONE=added src/added\.py' "$(cd "$R" && "$HELPER" --base base --head HEAD --min-lines 5 --min-tokens 20 2>&1)" \
  "the within-diff case is silent because both sides are new, not because nothing fires"

_flow_test_begin "scan set: the untracked copy fires once it is tracked"
( cd "$RU" && git add src/untracked_copy.py && git commit -q -m tracked )
_cs_scan "$RU" --base base --head HEAD --min-lines 5 --min-tokens 20
assert_match '^STATE=ok$' "$CS_OUT" "the same content is reported once git tracks it"
assert_match 'CLONE=added src/untracked_copy\.py' "$CS_OUT" "cited on the added side"

# --- a tracked file modified in the worktree, never staged -----------------------
# The gate runs before the task stages anything, so a duplicate added to a file
# git already tracks has to count as changed from the worktree alone. Staging it
# would be caught by the index diff instead, which is a different code path.
RW2=$(_cs_repo worktree)
printf 'def load_config(path):\n%s\n' "$CS_BODY" > "$RW2/src/existing.py"
printf 'def placeholder(path):\n    return path\n' > "$RW2/src/target.py"
_cs_bulk "$RW2"
_cs_commit "$RW2" base
( cd "$RW2" && git checkout -q -b feat )
printf 'def read_settings(path):\n%s\n' "$CS_BODY" > "$RW2/src/target.py"
_cs_scan "$RW2" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "an unstaged worktree edit is in the changed set"
assert_match '^STATE=ok$' "$CS_OUT" "the edit is seen without staging or committing"
assert_match 'CLONE=added src/target\.py' "$CS_OUT" "cited on the edited side"

# --- a control character in a path cannot forge a line ---------------------------
# ls-files -z passes a newline in a filename through intact, and an unescaped
# one would forge a whole KEY=value line of this helper's own output.
RNL=$(_cs_repo newlinename)
printf 'def load_config(path):\n%s\n' "$CS_BODY" > "$RNL/src/existing.py"
_cs_bulk "$RNL"
_cs_commit "$RNL" base
( cd "$RNL" && git checkout -q -b feat )
CS_NL_NAME=$(printf 'src/we\nird.py')
printf 'def read_settings(path):\n%s\n' "$CS_BODY" > "$RNL/$CS_NL_NAME"
_cs_commit "$RNL" add
_cs_scan "$RNL" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "a newline in a path is encoded, not passed through"
assert_match '^STATE=ok$' "$CS_OUT" "the pair is found"
assert_contains "we%0Aird.py" "$CS_OUT" "the newline is percent-encoded"
# And it forged no extra line: exactly one CLONE row, and every line of the
# output is a KEY=value the contract names.
CS_N_CLONE=$(printf '%s\n' "$CS_OUT" | grep -c '^CLONE=added ')
assert_equal "1" "$CS_N_CLONE" "exactly one CLONE row, so no line was forged"
CS_STRAY=$(printf '%s\n' "$CS_OUT" | grep -cvE '^(STATE|REASON|SETTINGS_SOURCE|EXCLUDES_SOURCE|EXCLUDES_APPLIED|SCAN_BASE|FILES_SCANNED|FILES_TRACKED|DETECTOR_SOURCES|MIN_LINES|MIN_TOKENS|MODE|INSTALL|CLONE|CLONE_WITHIN_DIFF)=')
assert_equal "0" "$CS_STRAY" "every output line is a key the contract names"

# --- a detector that cannot tell new from pre-existing ---------------------------
# The parser filters on the report's new-clone field, which only
# --baseline-from-ref populates. A detector that ignores that option reports
# every pair without it, they all filter out as pre-existing, and the scan reads
# as clean. That is "nobody could tell", not "there is nothing".
mkdir -p "$CS_DIR/nonewbin"
cat > "$CS_DIR/nonewbin/jscpd" <<'NONEWSTUB'
#!/usr/bin/env bash
OUTDIR=""
PREV=""
for A in "$@"; do
  [ "$PREV" = "--output" ] && OUTDIR="$A"
  PREV="$A"
done
[ -n "$OUTDIR" ] || exit 1
mkdir -p "$OUTDIR"
CRAFT_OUT="$OUTDIR/jscpd-report.json" python3 -c '
import json, os
root = os.getcwd()
def f(name, a, b):
    return {"name": os.path.join(root, name), "start": a, "end": b}
report = {
  "duplicates": [
    {"firstFile": f("src/existing.py", 1, 6), "secondFile": f("src/added.py", 1, 6),
     "lines": 6, "tokens": 35, "format": "python", "kind": "exact"},
  ],
  "statistics": {"total": {"sources": 2, "clones": 1}},
}
open(os.environ["CRAFT_OUT"], "w").write(json.dumps(report))
'
exit 0
NONEWSTUB
chmod +x "$CS_DIR/nonewbin/jscpd"
CS_OUT=$( cd "$R" && PATH="$CS_DIR/nonewbin:$CS_BARE_PATH" "$HELPER" --base base --head HEAD \
  --min-lines 5 --min-tokens 20 2>&1 )
CS_CODE=$?
_flow_test_begin "a report with no new-clone field is unavailable, not clean"
assert_match '^STATE=unavailable$' "$CS_OUT" "the scan cannot tell new from pre-existing"
assert_not_contains "STATE=none" "$CS_OUT" "and does not read as a clean scan"
assert_exit 2 "$CS_CODE" "exit 2"

# --- an over-quantified exclude pattern is refused, not run ----------------------
# The pattern comes from the settings of the branch under review and the match
# runs once per tracked file, so an unreasonable one is refused up front rather
# than discovered at review time.
_cs_scan "$R" --base base --head HEAD --exclude-paths 'a*/b*/c*/d*/e*/f*/g*/h*/i*/j*/**'
_flow_test_begin "an over-quantified exclude pattern is refused"
assert_match '^STATE=unavailable$' "$CS_OUT" "the pattern is refused"
assert_not_contains "STATE=none" "$CS_OUT" "and the run does not read as clean"
assert_match 'wildcard groups' "$CS_OUT" "the reason names what was wrong with it"
# The control: a pattern within the bound is accepted, so the refusal is about
# the bound and not about every pattern.
_cs_scan "$R" --base base --head HEAD --min-lines 5 --min-tokens 20 --exclude-paths 'a*/b*/**'
_flow_test_begin "a pattern within the bound is accepted"
assert_exit 0 "$CS_CODE" "the scan runs"
assert_not_contains "wildcard groups" "$CS_OUT" "no refusal"

# --- a project exclude list with TWO entries -------------------------------------
# One entry proves nothing: the list is carried as JSON precisely because a
# delimiter breaks on more than one. A comma splits a glob that legally
# contains one, and the settings cascade REFUSES any value holding a control
# character, so a newline-joined list was rejected and silently replaced by the
# built-in default with nothing said about it.
RJ=$(_cs_repo jsonexcludes)
mkdir -p "$RJ/.claude" "$RJ/src" "$RJ/docs"
printf '%s\n' '{"duplication": {"excludePaths": ["src/**","docs/**"]}}' > "$RJ/.claude/settings.flow.json"
printf 'x\n' > "$RJ/README.md"
printf 'y\n' > "$RJ/src/a.py"
printf 'z\n' > "$RJ/docs/b.py"
_cs_commit "$RJ" base
CS_OUT=$( cd "$RJ" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" \
  "$HELPER" --base HEAD --head HEAD --print-scan-set 2>&1 )
CS_JSCANNED=$(printf '%s\n' "$CS_OUT" | sed -n 's/^FILES_SCANNED=//p')
CS_JTRACKED=$(printf '%s\n' "$CS_OUT" | sed -n 's/^FILES_TRACKED=//p')
_flow_test_begin "settings: a two-entry exclude list is honoured, not discarded"
assert_equal "4" "$CS_JTRACKED" "four files are tracked"
assert_equal "2" "$CS_JSCANNED" "src/ and docs/ are excluded, leaving two"

# --- the plugin-default tier must not come from the tree being scanned -----------
# The cascade's plugin tier is a RELATIVE path, and the helper moves to the
# repository root, so without pinning it the scanned repository supplies the
# defaults for its own review.
RT=$(_cs_repo ownsettings)
mkdir -p "$RT/plugins/flow"
printf '%s\n' '{"duplication": {"minTokens": 200, "minLines": 99}}' > "$RT/plugins/flow/settings.json"
printf 'def load_config(path):\n%s\n' "$CS_BODY" > "$RT/src/existing.py"
_cs_bulk "$RT"
_cs_commit "$RT" base
( cd "$RT" && git checkout -q -b feat )
printf 'def read_settings(path):\n%s\n' "$CS_BODY" > "$RT/src/added.py"
_cs_commit "$RT" add
CS_OUT=$( cd "$RT" && env -u CLAUDE_PLUGIN_ROOT "$HELPER" --base base --head HEAD 2>&1 )
_flow_test_begin "settings: the scanned repository does not supply the plugin defaults"
assert_match '^MIN_TOKENS=20$' "$CS_OUT" "the token floor is the plugin's, not the scanned tree's 200"
assert_match '^MIN_LINES=5$' "$CS_OUT" "the line minimum is the plugin's, not the scanned tree's 99"
assert_match '^STATE=ok$' "$CS_OUT" "so the introduced pair is still reported"

# --- a bound that cannot be read is a state, not a traceback ---------------------
CS_OUT=$( cd "$R" && FCS_MAX_FILES=abc "$HELPER" --base base --head HEAD 2>&1 )
CS_CODE=$?
_flow_test_begin "an unreadable bound is reported, not raised"
assert_match '^STATE=unavailable$' "$CS_OUT" "it is a reported state"
assert_match 'FCS_MAX_FILES' "$CS_OUT" "naming the bound that could not be read"
assert_exit 2 "$CS_CODE" "exit 2, not the usage code"
assert_not_contains "Traceback" "$CS_OUT" "and no traceback reaches the caller"

# --- the worktree counts only when the range's head IS the checkout --------------
RH=$(_cs_repo headscope)
printf 'def load_a(path):\n%s\n' "$CS_BODY" > "$RH/src/a.py"
_cs_bulk "$RH"
printf 'placeholder\n' > "$RH/README.md"
_cs_commit "$RH" base
( cd "$RH" && git checkout -q -b other && printf 'other\n' > README.md && git add -A && git commit -q -m other && git checkout -q base )
printf 'def load_c(path):\n%s\n' "$CS_BODY" > "$RH/src/c.py"
( cd "$RH" && git add src/c.py )
_cs_scan "$RH" --base base --head other --min-lines 5 --min-tokens 20
_flow_test_begin "range scope: a staged file outside the range is not reported"
assert_match '^STATE=none$' "$CS_OUT" "--head other does not fold in the checkout's index"
assert_not_contains "src/c.py" "$CS_OUT" "and never names it"
# The control: with the range's head AS the checkout, the same file IS reported.
_cs_scan "$RH" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "range scope: and it is reported when the head is the checkout"
assert_match '^STATE=ok$' "$CS_OUT" "the staged file counts for --head HEAD"
assert_match 'CLONE=added src/c\.py' "$CS_OUT" "cited on the added side"

# --- a path containing a space cannot split the row ------------------------------
# Space is the CLONE row's own field separator, so an unencoded one makes the
# added side parse as a different file.
RSp=$(_cs_repo spacename)
printf 'def load_config(path):\n%s\n' "$CS_BODY" > "$RSp/src/existing.py"
_cs_bulk "$RSp"
_cs_commit "$RSp" base
( cd "$RSp" && git checkout -q -b feat )
printf 'def read_settings(path):\n%s\n' "$CS_BODY" > "$RSp/src/added existing zz.py"
_cs_commit "$RSp" add
_cs_scan "$RSp" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "a space in a path is encoded, so the row keeps its fields"
assert_match '^STATE=ok$' "$CS_OUT" "the pair is found"
CS_ROW=$(printf '%s\n' "$CS_OUT" | grep '^CLONE=added ')
assert_contains "added%20existing%20zz.py" "$CS_ROW" "the spaces are encoded"
# By the grammar the header states, field 2 is the whole added location.
CS_ADDED=$(printf '%s\n' "$CS_ROW" | awk '{print $2}')
assert_match '^src/added%20existing%20zz\.py:[0-9]+-[0-9]+$' "$CS_ADDED" \
  "and the added side is one whitespace-free token"

# --- a library that loads but does not define what the helper calls --------------
mkdir -p "$CS_DIR/halflib/lib"
cp "$HELPER" "$CS_DIR/halflib/flow-clone-scan.sh"
chmod +x "$CS_DIR/halflib/flow-clone-scan.sh"
sed '/^flow_range_validate()/,/^}/d' "$REPO_ROOT/plugins/flow/bin/lib/range-args.sh" \
  > "$CS_DIR/halflib/lib/range-args.sh"
CS_OUT=$( cd "$R" && "$CS_DIR/halflib/flow-clone-scan.sh" --base base --head HEAD 2>&1 )
CS_CODE=$?
_flow_test_begin "a library that loads but is missing a function is reported"
assert_match '^STATE=unavailable$' "$CS_OUT" "sourcing returning 0 is not the contract being met"
assert_match 'flow_range_validate' "$CS_OUT" "the missing name is named"
assert_exit 2 "$CS_CODE" "exit 2"

# --- print-scan-set with nothing left to scan ------------------------------------
_cs_scan "$R" --base base --head HEAD --print-scan-set --exclude-paths '**'
_flow_test_begin "scan set: excluding everything is unavailable, not an empty ok"
assert_match '^STATE=unavailable$' "$CS_OUT" "an empty scan set is never a clean result"
assert_not_contains "STATE=ok" "$CS_OUT" "and does not report ok"

# --- every adjacent wildcard run folds, not only `**/` ---------------------------
# Collapsing the slash form alone left `****` emitting four `.*` atoms that
# backtrack against each other. Measured before the fold: 13.4s for a SINGLE
# path at exactly the group bound, run once per tracked file, so the scan
# produced no output at all across a real tree.
_flow_test_begin "adjacent wildcard runs of every shape are cheap"
for CS_PAT in '****************ZZZ' '****/****/****ZZZ' '**********ZZZ' '*********' ; do
  CS_T0=$(date +%s)
  CS_OUT=$( cd "$REPO_ROOT" && "$HELPER" --base HEAD --head HEAD --print-scan-set \
    --exclude-paths "$CS_PAT" 2>&1 )
  CS_T1=$(date +%s)
  CS_EL=$((CS_T1 - CS_T0))
  if [ "$CS_EL" -le 20 ] 2>/dev/null; then
    _flow_assert_pass "pattern '$CS_PAT' matched the whole tree in ${CS_EL}s"
  else
    _flow_assert_fail "pattern '$CS_PAT' took ${CS_EL}s over the tree"
  fi
  assert_match '^STATE=' "$CS_OUT" "and it printed a state rather than dying"
done

# --- a line-breaking character cannot forge a row --------------------------------
# str.splitlines() breaks on U+0085, U+2028 and U+2029 as well as C0, so
# encoding only the C0 range left a filename able to forge an output line.
_flow_test_begin "line-breaking characters outside C0 are encoded too"
CS_FIELD=$( cd "$REPO_ROOT" && python3 - <<'FIELDPY'
import re, unicodedata
src = open("plugins/flow/bin/flow-clone-scan.sh").read()
body = re.search(r"python3 - <<.PYEOF.\n(.*?)\nPYEOF", src, re.S).group(1)
ns = {}
exec(compile(re.search(r"( *)def field\(value\):.*?(?=\n\1[a-zA-Z#])", body, re.S).group(0)
             .replace("\n    ", "\n").lstrip(), "field", "exec"),
     {"unicodedata": unicodedata}, ns)
probe = "a" + "\u0085" + "b" + " " + "c" + " " + "d"
out = ns["field"](probe)
print("LINES=%d" % len(out.splitlines()))
print("ENCODED=%s" % ("yes" if "%" in out else "no"))
FIELDPY
)
assert_contains "LINES=1" "$CS_FIELD" "the encoded value is a single line"
assert_contains "ENCODED=yes" "$CS_FIELD" "because the breaks were percent-encoded"

# --- the run says which exclude list applied -------------------------------------
# "Reported rather than prevented" only holds if the report names what was
# applied: a branch narrowing the scan through its own settings otherwise
# produced a clean result with nothing attributing the narrowing.
_cs_scan "$R" --base base --head HEAD --min-lines 5 --min-tokens 20
_flow_test_begin "the run attributes its exclude list"
assert_match '^EXCLUDES_SOURCE=' "$CS_OUT" "the source is named"
assert_match '^EXCLUDES_APPLIED=[0-9]+$' "$CS_OUT" "and how many patterns applied"
_cs_scan "$R" --base base --head HEAD --min-lines 5 --min-tokens 20 --exclude-paths '**/nothing/**'
_flow_test_begin "and says when the list came from the caller"
assert_match '^EXCLUDES_SOURCE=flag$' "$CS_OUT" "a caller-supplied list is attributed to the flag"
assert_match '^EXCLUDES_APPLIED=1$' "$CS_OUT" "with its one pattern counted"

# A flag that is empty once stripped did not supply a list, so it must not be
# attributed one. The attribution used to be decided twice, in shell and in
# python, and the two disagreed here: the shell reported the flag while the
# built-in list was what actually applied.
_cs_scan "$R" --base base --head HEAD --min-lines 5 --min-tokens 20
CS_NOFLAG_APPLIED=$(printf '%s\n' "$CS_OUT" | sed -n 's/^EXCLUDES_APPLIED=//p')
_cs_scan "$R" --base base --head HEAD --min-lines 5 --min-tokens 20 --exclude-paths ' '
_flow_test_begin "must-stay-silent: a flag that is blank once stripped is not the source"
assert_not_contains "EXCLUDES_SOURCE=flag" "$CS_OUT" "the blank flag supplied nothing"
assert_match '^EXCLUDES_SOURCE=built-in defaults' "$CS_OUT" "so the built-in list is named"
assert_equal "$CS_NOFLAG_APPLIED" \
  "$(printf '%s\n' "$CS_OUT" | sed -n 's/^EXCLUDES_APPLIED=//p')" \
  "and the same number of patterns applied as with no flag at all"

# --- STATE leads every unavailable path, and no key is printed twice -------------
# unavailable() prints FILES_SCANNED so that STATE always comes first. The
# sweep that removed the per-call-site pre-prints matched on the key name and
# missed three sites, so the key printed twice with data ahead of the state
# that qualifies it. These assertions check the shape of the output rather than
# the call sites, so a site added later is covered too.
_cs_scan "$R" --base base --head HEAD --min-lines 5 --min-tokens 20 --exclude-paths '**'
_flow_test_begin "unavailable with nothing to scan: STATE first, one FILES_SCANNED"
assert_equal "STATE=unavailable" "$(printf '%s\n' "$CS_OUT" | head -1)" "STATE is the first line"
assert_equal "1" "$(printf '%s\n' "$CS_OUT" | grep -c '^FILES_SCANNED=')" "FILES_SCANNED appears once"
assert_exit 2 "$CS_CODE" "exit 2"

# A detector that runs, succeeds and writes nothing. The real jscpd cannot be
# made to do this on demand, so a stub stands in for it; what is under test is
# the helper's reaction, not the detector.
mkdir -p "$CS_DIR/stubdetector"
printf '#!/bin/sh\nexit 0\n' > "$CS_DIR/stubdetector/jscpd"
chmod +x "$CS_DIR/stubdetector/jscpd"
CS_OUT=$( cd "$R" && PATH="$CS_DIR/stubdetector:$PATH" "$HELPER" --base base --head HEAD \
  --min-lines 5 --min-tokens 20 2>&1 )
CS_CODE=$?
_flow_test_begin "unavailable with no report written: STATE first, one FILES_SCANNED"
assert_equal "STATE=unavailable" "$(printf '%s\n' "$CS_OUT" | head -1)" "STATE is the first line"
assert_equal "1" "$(printf '%s\n' "$CS_OUT" | grep -c '^FILES_SCANNED=')" "FILES_SCANNED appears once"
assert_contains "wrote no report" "$CS_OUT" "and the reason names the missing report"
assert_exit 2 "$CS_CODE" "exit 2"

# A detector that succeeds and reports having parsed nothing. The real jscpd
# exits 1 under --fail-on-empty before reaching this branch, so a stub writes
# the empty report; what is under test is the helper's reaction to it.
mkdir -p "$CS_DIR/stubempty"
cat > "$CS_DIR/stubempty/jscpd" <<'EMPTYSTUB'
#!/bin/sh
out=""
while [ $# -gt 0 ]; do
  case "$1" in --output) out="$2"; shift 2 ;; *) shift ;; esac
done
[ -n "$out" ] || exit 1
mkdir -p "$out"
printf '%s\n' '{"statistics":{"total":{"sources":0}},"duplicates":[]}' > "$out/jscpd-report.json"
exit 0
EMPTYSTUB
chmod +x "$CS_DIR/stubempty/jscpd"
CS_OUT=$( cd "$R" && PATH="$CS_DIR/stubempty:$PATH" "$HELPER" --base base --head HEAD \
  --min-lines 5 --min-tokens 20 2>&1 )
CS_CODE=$?
_flow_test_begin "unavailable with nothing parsed: STATE first, the zero count after it"
assert_equal "STATE=unavailable" "$(printf '%s\n' "$CS_OUT" | head -1)" "STATE is the first line"
assert_match '^DETECTOR_SOURCES=0$' "$CS_OUT" "the zero count still reaches the caller"
assert_equal "1" "$(printf '%s\n' "$CS_OUT" | grep -c '^DETECTOR_SOURCES=')" "exactly once"
assert_contains "parsed none of the" "$CS_OUT" "and the reason says nothing was examined"
assert_exit 2 "$CS_CODE" "exit 2"

# --- the script's own directory follows the symlink chain ------------------------
# Taken from the link's directory, a lib/ planted beside a symlink is sourced
# instead of the real one.
mkdir -p "$CS_DIR/symlinkdir/lib"
printf 'flow_range_parse_args() { :; }\nflow_range_validate() { return 1; }\n' \
  > "$CS_DIR/symlinkdir/lib/range-args.sh"
ln -sf "$HELPER" "$CS_DIR/symlinkdir/flow-clone-scan.sh" 2>/dev/null
CS_OUT=$( cd "$R" && "$CS_DIR/symlinkdir/flow-clone-scan.sh" --base base --head HEAD \
  --min-lines 5 --min-tokens 20 2>&1 )
_flow_test_begin "a library planted beside a symlink is not the one that loads"
assert_match '^STATE=ok$' "$CS_OUT" "the real library was used, so the scan ran"
assert_match 'CLONE=added' "$CS_OUT" "and found the pair"

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
