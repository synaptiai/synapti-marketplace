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
CS_ANALYZED=$(printf '%s\n' "$CS_OUT" | sed -n 's/^FILES_ANALYZED=//p')
if [ -n "$CS_ANALYZED" ] && [ "$CS_ANALYZED" -gt 0 ] 2>/dev/null; then
  _flow_assert_pass "the detector examined $CS_ANALYZED file(s) and still reported nothing"
else
  _flow_assert_fail "FILES_ANALYZED=${CS_ANALYZED:-missing}: the clean result came from an empty run"
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
CS_ANALYZED=$(printf '%s\n' "$CS_OUT" | sed -n 's/^FILES_ANALYZED=//p')
if [ -n "$CS_ANALYZED" ] && [ "$CS_ANALYZED" -gt 0 ] 2>/dev/null; then
  _flow_assert_pass "examined $CS_ANALYZED file(s)"
else
  _flow_assert_fail "FILES_ANALYZED=${CS_ANALYZED:-missing}: nothing was examined"
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

# --- real, full-size input ---------------------------------------------------
# One run over this repository's own tree, with FILES_SCANNED reconciled
# against an independent enumeration. A count that matched nothing would look
# exactly like a clean result without this.
_flow_test_begin "real tree: FILES_SCANNED reconciles with git ls-files"
CS_REAL=$( cd "$REPO_ROOT" && "$HELPER" --base HEAD --head HEAD --print-scan-set 2>&1 )
CS_REAL_CODE=$?
CS_SCANNED=$(printf '%s\n' "$CS_REAL" | sed -n 's/^FILES_SCANNED=//p')
CS_TRACKED=$( cd "$REPO_ROOT" && git ls-files | wc -l | tr -d ' ' )
if [ -z "$CS_SCANNED" ]; then
  _flow_assert_fail "the helper printed no FILES_SCANNED over the real tree (exit $CS_REAL_CODE)"
else
  if [ "$CS_SCANNED" -gt 0 ] 2>/dev/null; then
    _flow_assert_pass "examined $CS_SCANNED files"
  else
    _flow_assert_fail "FILES_SCANNED=0 over a repository with $CS_TRACKED tracked files"
  fi
  if [ "$CS_SCANNED" -le "$CS_TRACKED" ] 2>/dev/null; then
    _flow_assert_pass "scan set ($CS_SCANNED) is within the tracked set ($CS_TRACKED)"
  else
    _flow_assert_fail "scanned $CS_SCANNED files but only $CS_TRACKED are tracked — the walk escaped git"
  fi
fi
