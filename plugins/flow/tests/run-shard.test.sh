# shellcheck shell=bash
# FLOW_TEST_SHARD=K/N makes run.sh run one of N parts of its file list: the
# files whose 0-based position i has i mod N = K-1. CI runs the Linux suite
# as four such parts so that each finishes well inside its time limit.
#
# run.sh is started on fixture test files in a scratch directory, never on
# the real suite. The checks: every file runs in exactly one part, the parts
# of a list given as arguments are taken from that list, the suites never see
# the variable, and a malformed value runs nothing and exits 2. Each run's
# output is kept under FLOW_E2E_ARTIFACT_DIR when that is set.

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null; } || {
  printf '%s\n' "run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

RS_TMP=$(mktemp -d "${TMPDIR:-/tmp}/flow-run-shard.XXXXXX") || { _flow_assert_fail "mktemp -d failed"; return 0; }
RS_RUN="$REPO_ROOT/plugins/flow/tests/run.sh"
RS_ART=""
if [ -n "${FLOW_E2E_ARTIFACT_DIR:-}" ]; then
  RS_ART="$FLOW_E2E_ARTIFACT_DIR/run-shard"
  mkdir -p "$RS_ART" || RS_ART=""
fi

for _rs_n in a b c d e; do
  printf '%s\n' \
    "assert_equal 1 1 \"fixture $_rs_n\"" \
    "printf 'SHARD_SEEN=%s\n' \"\${FLOW_TEST_SHARD-unset}\"" \
    > "$RS_TMP/$_rs_n.test.sh"
done

# _rs_run <case name> <shard value | -unset> <file>... — runs run.sh on the
# fixture files; sets RS_OUT, RS_RC and RS_RAN (the files it started, in
# order, separated by spaces).
_rs_run() {
  local name=$1 shard=$2
  shift 2
  if [ "$shard" = -unset ]; then
    RS_OUT=$(unset FLOW_TEST_SHARD; "$RS_RUN" "$@" 2>&1)
  else
    RS_OUT=$(FLOW_TEST_SHARD=$shard "$RS_RUN" "$@" 2>&1)
  fi
  RS_RC=$?
  RS_RAN=$(printf '%s\n' "$RS_OUT" | sed -n 's/^=== \(.*\)\.test\.sh ===$/\1/p' | tr '\n' ' ')
  RS_RAN=${RS_RAN% }
  [ -z "$RS_ART" ] || printf 'FLOW_TEST_SHARD=%s\nexit=%s\n%s\n' "$shard" "$RS_RC" "$RS_OUT" > "$RS_ART/$name.txt"
}

RS_ALL=("$RS_TMP"/a.test.sh "$RS_TMP"/b.test.sh "$RS_TMP"/c.test.sh "$RS_TMP"/d.test.sh "$RS_TMP"/e.test.sh)

# Position 0 (a) goes to part 1; an off-by-one drops a file or empties a part.
_rs_run two-of-1 1/2 "${RS_ALL[@]}"
assert_equal "a c e" "$RS_RAN" "1/2 of a..e runs a, c and e"
assert_equal 0 "$RS_RC" "1/2 exits 0"
assert_contains "run.sh: shard 1/2 runs 3 of 5 files" "$RS_OUT" "1/2 says how many files it runs"
_rs_run two-of-2 2/2 "${RS_ALL[@]}"
assert_equal "b d" "$RS_RAN" "2/2 of a..e runs b and d"
assert_contains "run.sh: shard 2/2 runs 2 of 5 files" "$RS_OUT" "2/2 says how many files it runs"

# Every file in exactly one of four parts, including a part of one file.
_rs_seen=""
for _rs_k in 1 2 3 4; do
  _rs_run "four-of-$_rs_k" "$_rs_k/4" "${RS_ALL[@]}"
  assert_equal 0 "$RS_RC" "$_rs_k/4 exits 0"
  _rs_seen="$_rs_seen $RS_RAN"
done
assert_equal "a b c d e" "$(printf '%s\n' $_rs_seen | sort | tr '\n' ' ' | sed 's/ $//')" "the four parts together run each file once"

# 1/1 is the whole list.
_rs_run one-of-1 1/1 "${RS_ALL[@]}"
assert_equal "a b c d e" "$RS_RAN" "1/1 runs every file"

# A part of a list given as arguments comes from that list, not the glob.
_rs_run args 1/3 "$RS_TMP/b.test.sh" "$RS_TMP/d.test.sh" "$RS_TMP/e.test.sh"
assert_equal "b" "$RS_RAN" "1/3 of b, d, e runs b only"
assert_contains "run.sh: shard 1/3 runs 1 of 3 files" "$RS_OUT" "1/3 of three arguments says 1 of 3"

# The suites never see the variable.
_rs_run inherit 1/2 "${RS_ALL[@]}"
assert_contains "SHARD_SEEN=unset" "$RS_OUT" "a suite run in a part sees FLOW_TEST_SHARD unset"
assert_not_contains "SHARD_SEEN=1/2" "$RS_OUT" "a suite run in a part does not see 1/2"

# Unset: every file, and no shard line.
_rs_run unset -unset "${RS_ALL[@]}"
assert_equal "a b c d e" "$RS_RAN" "without FLOW_TEST_SHARD every file runs"
assert_not_contains "run.sh: shard" "$RS_OUT" "without FLOW_TEST_SHARD no shard line is printed"

# A malformed value runs nothing and is a runner error.
_rs_i=0
for _rs_bad in 0/4 5/4 1/0 a/b 1/4x 1 /4 1/ 01/4 1/04 "" " 1/4" 1//4 1/4/4 99999/99999; do
  _rs_i=$((_rs_i + 1))
  _rs_run "bad-$_rs_i" "$_rs_bad" "${RS_ALL[@]}"
  assert_equal 2 "$RS_RC" "FLOW_TEST_SHARD='$_rs_bad' exits 2"
  assert_equal "" "$RS_RAN" "FLOW_TEST_SHARD='$_rs_bad' runs no file"
  assert_contains "run.sh: FLOW_TEST_SHARD must be K/N" "$RS_OUT" "FLOW_TEST_SHARD='$_rs_bad' says the value is malformed"
done

# More parts than files: a part with no file is an error, not a pass.
_rs_run six-of-6 6/6 "${RS_ALL[@]}"
assert_equal 2 "$RS_RC" "6/6 of five files exits 2"
assert_equal "" "$RS_RAN" "6/6 of five files runs no file"
assert_contains "selects no file" "$RS_OUT" "6/6 of five files says it selects no file"

rm -rf "$RS_TMP"
