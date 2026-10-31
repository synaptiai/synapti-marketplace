# shellcheck shell=bash
# FLOW_TEST_JOBS=N makes run.sh run up to N files at once, each in a run.sh
# of its own, and print each file's output whole, in list order, with the
# time it took, then the times of all files and of the run.
#
# run.sh is started on fixture test files in a scratch directory, never on
# the real suite. Ways it can be wrong, written down before the checks:
#   P1 the totals, the failed files or the exit status differ from a run
#      of the same files one at a time
#   P2 output from two files is interleaved, or printed out of list order
#   P3 a failing assertion is reported without its file and scenario
#   P4 a file that exits without a SUMMARY, does not parse, or is missing is
#      counted as passing, or stops the run
#   P5 a file is run twice, or not at all, or with another file's state
#      directory
#   P6 a time is missing for a file, or the run's own time is missing
#   P7 a malformed FLOW_TEST_JOBS runs anything
#   P8 the start order from FLOW_TEST_TIMES is ignored, or the times file
#      loses entries for files this run did not record
# Each run's output is kept under FLOW_E2E_ARTIFACT_DIR when that is set.

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null; } || {
  printf '%s\n' "run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

RP_TMP=$(mktemp -d "${TMPDIR:-/tmp}/flow-run-parallel.XXXXXX") || { _flow_assert_fail "mktemp -d failed"; return 0; }
trap 'rm -rf "$RP_TMP"' EXIT
RP_RUN="$REPO_ROOT/plugins/flow/tests/run.sh"
RP_ART=""
if [ -n "${FLOW_E2E_ARTIFACT_DIR:-}" ]; then
  RP_ART="$FLOW_E2E_ARTIFACT_DIR/run-parallel"
  mkdir -p "$RP_ART" || RP_ART=""
fi

# Fixtures: two that pass (one slow, so the fast one ends first), one with a
# failing assertion, one with no SUMMARY, one that does not parse, and one
# that prints its state directory.
printf '%s\n' 'sleep 2' 'assert_equal 1 1 "slow one"' 'assert_equal 2 2 "slow two"' > "$RP_TMP/a.test.sh"
printf '%s\n' 'assert_equal x x "fast"' > "$RP_TMP/b.test.sh"
printf '%s\n' '_flow_test_begin "scenario-c"' 'assert_equal 1 2 "c compares"' > "$RP_TMP/c.test.sh"
printf '%s\n' 'exit 3' > "$RP_TMP/d.test.sh"
printf '%s\n' 'if then' > "$RP_TMP/e.test.sh"
printf '%s\n' 'sleep 2' 'printf "STATE=%s\n" "$FLOW_STATE_DIR"' 'assert_equal 1 1 "state"' > "$RP_TMP/f.test.sh"
RP_ALL=("$RP_TMP/a.test.sh" "$RP_TMP/b.test.sh" "$RP_TMP/c.test.sh" "$RP_TMP/d.test.sh" "$RP_TMP/e.test.sh" "$RP_TMP/f.test.sh" "$RP_TMP/missing.test.sh")

# _rp_run <case> <jobs> <file>... — sets RP_OUT and RP_RC.
_rp_run() {
  local name=$1 jobs=$2
  shift 2
  RP_OUT=$(FLOW_TEST_JOBS=$jobs FLOW_TEST_TIMES="$RP_TMP/times" "$RP_RUN" "$@" 2>&1)
  RP_RC=$?
  [ -z "$RP_ART" ] || printf 'FLOW_TEST_JOBS=%s\nexit=%s\n%s\n' "$jobs" "$RP_RC" "$RP_OUT" > "$RP_ART/$name.txt"
}

_rp_run serial 1 "${RP_ALL[@]}"
RP_SERIAL_OUT=$RP_OUT
RP_SERIAL_RC=$RP_RC
_rp_run parallel 4 "${RP_ALL[@]}"

# P1: the same result as one at a time.
assert_equal "$(printf '%s\n' "$RP_SERIAL_OUT" | grep '^TOTAL ')" "$(printf '%s\n' "$RP_OUT" | grep '^TOTAL ')" "the totals match a run one at a time"
assert_equal "$(printf '%s\n' "$RP_SERIAL_OUT" | grep '^FAILED files:' | sed "s#$RP_TMP/##g")" "$(printf '%s\n' "$RP_OUT" | grep '^FAILED files:' | sed "s#$RP_TMP/##g")" "the failed files match a run one at a time"
assert_equal "$RP_SERIAL_RC" "$RP_RC" "the exit status matches a run one at a time"
assert_equal "TOTAL pass=4 fail=3" "$(printf '%s\n' "$RP_OUT" | grep '^TOTAL ')" "the totals"
assert_equal 2 "$RP_RC" "a file that does not parse makes the exit status 2"

# P2: each file's block whole, in list order.
assert_equal "a b c d e f" "$(printf '%s\n' "$RP_OUT" | sed -n 's/^=== \(.*\)\.test\.sh ===$/\1/p' | tr '\n' ' ' | sed 's/ $//')" "blocks in list order"
assert_contains "$(printf '=== a.test.sh ===\nPASS')" "$RP_OUT" "a's first line follows its header"
assert_contains "$(printf 'SUMMARY pass=2 fail=0\nrun.sh: a.test.sh took')" "$RP_OUT" "a's summary and time follow its assertions"

# P3: the failing assertion names its file and scenario.
assert_contains "c compares" "$RP_OUT" "the failed assertion is reported"
assert_contains "scenario-c" "$RP_OUT" "with its scenario"
assert_contains "[c.test.sh:2]" "$RP_OUT" "with its file and line"

# P4: no SUMMARY, no parse, and a missing file each fail.
assert_contains "no SUMMARY line from d.test.sh" "$RP_OUT" "a file with no SUMMARY is reported"
assert_contains "e.test.sh does not parse" "$RP_OUT" "a file that does not parse is reported"
assert_contains "missing.test.sh not found" "$RP_OUT" "a missing file is reported"

# P5: each file once, each with a state directory of its own.
for _rp_f in a b c d e f missing; do
  assert_equal 1 "$(printf '%s\n' "$RP_OUT" | grep -c "^run.sh: started $_rp_f.test.sh$")" "$_rp_f started once"
done
_rp_state=$(printf '%s\n' "$RP_OUT" | sed -n 's/^STATE=//p')
assert_contains "flow-run-state." "$_rp_state" "f has a state directory"
[ -d "$_rp_state" ] && _flow_assert_fail "f's state directory is removed when its run ends" \
  || _flow_assert_pass "f's state directory is removed when its run ends"

# P6: every file's time, and the run's.
for _rp_f in a b c d f; do
  assert_contains "run.sh: $_rp_f.test.sh took" "$RP_OUT" "a time for $_rp_f"
done
assert_contains "=== durations (seconds, longest first) ===" "$RP_OUT" "the durations list"
assert_match '^TIME [0-9]+s for 7 files, up to 4 at a time$' "$(printf '%s\n' "$RP_OUT" | grep '^TIME ')" "the run's time"
assert_match '^TIME [0-9]+s for 7 files, one at a time$' "$(printf '%s\n' "$RP_SERIAL_OUT" | grep '^TIME ')" "the run's time one at a time"
# The two slow files (2 s each) overlap, so the run takes less than the
# files' times added up.
_rp_sum=$(printf '%s\n' "$RP_OUT" | sed -n 's/^run.sh: .* took \([0-9][0-9]*\)s$/\1/p' | awk '{ s += $1 } END { print s + 0 }')
_rp_total=$(printf '%s\n' "$RP_OUT" | sed -n 's/^TIME \([0-9][0-9]*\)s .*/\1/p')
assert_equal 1 "$([ "$_rp_total" -lt "$_rp_sum" ] && echo 1 || echo 0)" "the run takes less than its files' times added up ($_rp_total s, $_rp_sum s)"

# P7: a malformed FLOW_TEST_JOBS runs nothing.
for _rp_bad in 0 -1 x 1x 1000 ''; do
  if [ -z "$_rp_bad" ]; then continue; fi
  _rp_run "bad-$_rp_bad" "$_rp_bad" "$RP_TMP/b.test.sh" "$RP_TMP/f.test.sh"
  assert_equal 2 "$RP_RC" "FLOW_TEST_JOBS=$_rp_bad exits 2"
  assert_not_contains "=== b.test.sh ===" "$RP_OUT" "FLOW_TEST_JOBS=$_rp_bad runs nothing"
done

# P8: the times file sets the start order and keeps what this run did not
# record (fixture files are not the suite's own, so nothing is recorded).
printf '%s\n' '1 a.test.sh' '50 f.test.sh' '9 keep.test.sh' > "$RP_TMP/times"
_rp_run order 1 "$RP_TMP/a.test.sh"
_rp_run order 2 "$RP_TMP/a.test.sh" "$RP_TMP/b.test.sh" "$RP_TMP/f.test.sh"
assert_equal "b f a" "$(printf '%s\n' "$RP_OUT" | sed -n 's/^run.sh: started \(.*\)\.test\.sh$/\1/p' | tr '\n' ' ' | sed 's/ $//')" "a file with no time starts first, then the longest"
assert_equal "$(printf '%s\n' '1 a.test.sh' '50 f.test.sh' '9 keep.test.sh')" "$(cat "$RP_TMP/times")" "the times file keeps its entries"

# P4: a file whose own run.sh dies (it kills it) is a runner error, and the
# other files still run. Only in parallel: one at a time it would stop this run.
printf '%s\n' 'kill -9 $$' > "$RP_TMP/g.test.sh"
_rp_run killed 2 "$RP_TMP/b.test.sh" "$RP_TMP/g.test.sh" "$RP_TMP/f.test.sh"
assert_equal 2 "$RP_RC" "a file that kills its run.sh makes the exit status 2"
assert_contains "g.test.sh: its run.sh printed no TOTAL line" "$RP_OUT" "the dead run is reported"
assert_equal "TOTAL pass=2 fail=0" "$(printf '%s\n' "$RP_OUT" | grep '^TOTAL ')" "the other files' totals are kept"
assert_contains "FAILED files: g.test.sh" "$RP_OUT" "g is named as failed"

# P9: a program that sends itself SIGINT stops (exit 130) in a file run in
# parallel, as it does one at a time: a background job of a script starts
# with SIGINT ignored, and that must not reach the files.
printf '%s\n' "sh -c 'kill -INT \$\$; exit 0'" 'assert_equal 130 "$?" "a program that sends itself SIGINT exits 130"' > "$RP_TMP/h.test.sh"
_rp_run sigint-serial 1 "$RP_TMP/h.test.sh" "$RP_TMP/b.test.sh"
assert_equal 0 "$RP_RC" "one at a time, the fixture passes"
_rp_run sigint-parallel 2 "$RP_TMP/h.test.sh" "$RP_TMP/b.test.sh"
assert_equal 0 "$RP_RC" "in parallel, the fixture passes"
assert_contains "PASS <unset> — a program that sends itself SIGINT exits 130" "$RP_OUT" "the file saw exit 130"

# P10: a file marked `# flow-test: alone` starts after every other file, and
# its output still comes in list order.
printf '%s\n' '# flow-test: alone' 'assert_equal 1 1 "alone"' > "$RP_TMP/i.test.sh"
_rp_run alone 3 "$RP_TMP/i.test.sh" "$RP_TMP/a.test.sh" "$RP_TMP/b.test.sh"
assert_equal "i" "$(printf '%s\n' "$RP_OUT" | sed -n 's/^run.sh: started \(.*\)\.test\.sh$/\1/p' | tail -n 1)" "the marked file starts last"
assert_equal "i a b" "$(printf '%s\n' "$RP_OUT" | sed -n 's/^=== \(.*\)\.test\.sh ===$/\1/p' | tr '\n' ' ' | sed 's/ $//')" "output in list order"
assert_equal 0 "$RP_RC" "exit status"
