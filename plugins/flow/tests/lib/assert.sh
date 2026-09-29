# Bash assertions for plugins/flow/tests.
#
# Each assertion emits PASS/FAIL to stdout with a file:line citation derived
# from the caller's BASH_SOURCE/LINENO, and returns 0/1 so a calling script
# can decide whether to keep going or abort. The runner aggregates pass/fail
# counts via the FLOW_TEST_PASS / FLOW_TEST_FAIL counters maintained here.
#
# Conventions:
#   - All assertions read FLOW_TEST_CURRENT (the current test name) to label
#     output. Tests call _flow_test_begin "name" before assertions.
#   - Assertions write to stdout (captured by run.sh); diagnostic detail goes
#     to the same line so a tail of the output reads like a checklist.
#   - No external dependencies beyond standard POSIX utilities.

# Counters live in the test process. run.sh re-sources this file per test
# file (each test runs in a fresh subshell), so the counters reset between
# files but accumulate within a file.
: "${FLOW_TEST_PASS:=0}"
: "${FLOW_TEST_FAIL:=0}"
: "${FLOW_TEST_CURRENT:=<unset>}"

_flow_test_begin() {
  FLOW_TEST_CURRENT="$1"
}

_flow_assert_pass() {
  FLOW_TEST_PASS=$((FLOW_TEST_PASS + 1))
  printf 'PASS %s — %s\n' "$FLOW_TEST_CURRENT" "$1"
}

_flow_assert_fail() {
  FLOW_TEST_FAIL=$((FLOW_TEST_FAIL + 1))
  # Depth-aware citation. Two call shapes exist:
  #   (a) assert_equal/match/contains/... wraps _flow_assert_fail
  #       → BASH_SOURCE[2] is the test file (one wrapper between us and caller)
  #   (b) test body calls _flow_assert_fail directly (used by the static
  #       lints in command-frontmatter.test.sh)
  #       → BASH_SOURCE[1] is the test file (no wrapper)
  # Picking the wrong depth produces citations like [run.sh:80] — the line
  # in run.sh that sourced the test, not the assertion line. Detect by
  # checking whether [1] is assert.sh.
  local where
  if [ "${BASH_SOURCE[1]##*/}" = "assert.sh" ]; then
    where="${BASH_SOURCE[2]##*/}:${BASH_LINENO[1]}"
  else
    where="${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}"
  fi
  printf 'FAIL %s — %s [%s]\n' "$FLOW_TEST_CURRENT" "$1" "$where"
}

# assert_equal <expected> <actual> [<label>]
assert_equal() {
  local expected="$1" actual="$2" label="${3:-equal}"
  if [ "$expected" = "$actual" ]; then
    _flow_assert_pass "$label"
    return 0
  fi
  _flow_assert_fail "$label: expected '$expected', got '$actual'"
  return 1
}

# assert_match <regex> <actual> [<label>]
# Uses grep -E so the regex is ERE — same flavor the test bodies already use.
# A here-string (not `printf ... | grep`) feeds the haystack: with a pipe,
# `grep -q` exits at the first match and closes the pipe, so printf is killed by
# SIGPIPE (141) and — under the runner's `set -o pipefail` — the pipeline
# reports non-zero even though the match succeeded. That produced nondeterministic
# false failures on large haystacks (the match position races the pipe buffer).
# A here-string has no pipeline, so pipefail/SIGPIPE cannot corrupt the result.
assert_match() {
  local pattern="$1" actual="$2" label="${3:-match}"
  if grep -qE "$pattern" <<<"$actual"; then
    _flow_assert_pass "$label"
    return 0
  fi
  _flow_assert_fail "$label: '$actual' does not match /$pattern/"
  return 1
}

# assert_contains <needle> <haystack> [<label>]
# Literal substring match (no regex). Useful for asserting on multi-line
# stderr where a regex special would need escaping.
assert_contains() {
  local needle="$1" haystack="$2" label="${3:-contains}"
  case "$haystack" in
    *"$needle"*)
      _flow_assert_pass "$label"
      return 0
      ;;
  esac
  _flow_assert_fail "$label: missing '$needle'"
  return 1
}

# assert_not_contains <needle> <haystack> [<label>]
assert_not_contains() {
  local needle="$1" haystack="$2" label="${3:-not-contains}"
  case "$haystack" in
    *"$needle"*)
      _flow_assert_fail "$label: unexpectedly contains '$needle'"
      return 1
      ;;
  esac
  _flow_assert_pass "$label"
  return 0
}

# assert_exit <expected> <actual> [<label>]
assert_exit() {
  local expected="$1" actual="$2" label="${3:-exit}"
  if [ "$expected" = "$actual" ]; then
    _flow_assert_pass "$label"
    return 0
  fi
  _flow_assert_fail "$label: expected exit $expected, got $actual"
  return 1
}

# assert_file_exists <path> [<label>]
assert_file_exists() {
  local path="$1" label="${2:-file-exists}"
  if [ -f "$path" ]; then
    _flow_assert_pass "$label"
    return 0
  fi
  _flow_assert_fail "$label: $path missing"
  return 1
}

# flow_block <file> <NAME> — print the lines between `# <NAME>_BEGIN` and
# `# <NAME>_END` in <file>, exactly as written. A marker is a line that reads
# exactly that once its leading blanks are removed, so a marker indented inside
# a list item is found and a sentence that mentions one is not.
#
# It fails, printing nothing on stdout and the reason on stderr (naming the
# marker, the file and the line), when the file cannot be read, when BEGIN is
# never seen, when BEGIN appears a second time, when BEGIN has no END after it,
# when an END has no open BEGIN before it, or when nothing but blank lines sits
# between the two. An extractor that stopped only at END took everything to the
# end of the file when END was renamed, and a test that ran the result ran the
# command file's prose as shell.
#
# It reports and does not assert, so it is safe inside $(...). Every test file
# has it, because run.sh sources this file before each one; the e2e harness
# (lib/e2e.sh) is sourced after it and uses it for e2e_run_block.
flow_block() {
  local file="$1" name="$2"
  if [ ! -f "$file" ] || [ ! -r "$file" ]; then
    printf 'block %s: cannot read %s\n' "$name" "$file" >&2
    return 1
  fi
  awk -v b="# ${name}_BEGIN" -v e="# ${name}_END" -v file="$file" '
    { t = $0; sub(/^[ \t]+/, "", t) }
    t == b {
      if (begun) { err = sprintf("%s appears again at line %d of %s (first at line %d)", b, NR, file, begun); exit }
      begun = NR; open = 1; next
    }
    t == e {
      if (!open) { err = sprintf("%s at line %d of %s has no open %s before it", e, NR, file, b); exit }
      open = 0; next
    }
    open { buf = buf $0 "\n"; if ($0 ~ /[^ \t]/) text = 1 }
    END {
      if (err == "" && !begun) err = sprintf("%s is not in %s", b, file)
      if (err == "" && open) err = sprintf("%s at line %d of %s has no %s after it", b, begun, file, e)
      if (err == "" && !text) err = sprintf("%s at line %d of %s is followed by %s with nothing but blank lines between them", b, begun, file, e)
      if (err != "") { print "block: " err > "/dev/stderr"; exit 1 }
      printf "%s", buf
    }' "$file"
}

# assert_block <file> <NAME> <out file> — flow_block into <out file>, as an
# assertion: a block that extracts is a pass, and one that does not is a fail
# naming the marker and the file, with <out file> left empty so nothing partial
# runs. Call it as a statement, never inside $(...) or with its stdout
# redirected: an assertion made in a subshell is not counted, and a redirect
# would write the PASS or FAIL line into the file.
assert_block() {
  local err
  if err=$(flow_block "$1" "$2" 2>&1 >"$3"); then
    _flow_assert_pass "block $2 extracted from ${1##*/}"
    return 0
  fi
  : > "$3"
  _flow_assert_fail "$err"
  return 1
}

# Print summary; called by run.sh after each test file completes.
_flow_test_summary() {
  printf 'SUMMARY pass=%d fail=%d\n' "$FLOW_TEST_PASS" "$FLOW_TEST_FAIL"
}
