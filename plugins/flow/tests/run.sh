#!/usr/bin/env bash
# plugins/flow/tests/run.sh — flow plugin test runner.
#
# Discovers *.test.sh files in this directory, runs each in a fresh subshell
# with assert.sh sourced, aggregates pass/fail counts, and exits non-zero if
# any assertion failed. No external test framework — pure bash + POSIX utils.
#
# Usage:
#   plugins/flow/tests/run.sh              # run all tests
#   plugins/flow/tests/run.sh <file.test.sh>  # run one file
#
# Several files run at once, each in a run.sh of its own: FLOW_TEST_JOBS=N
# sets how many (default: the number of CPUs; 1 runs them one after another
# in this process). Each file's output is printed whole, in list order, with
# the time it took, followed by every file's time, longest first, and the
# time of the whole run. Files start longest first, by the times the last run
# recorded in FLOW_TEST_TIMES (default ~/.cache/flow-tests/times).
# A file with a line `# flow-test: alone` runs after the others, by itself:
# for a file that measures its own speed or works to a time budget.
# FLOW_TEST_SHARD=K/N runs part K of N (below).
#
# Exit:
#   0 — all assertions passed
#   1 — at least one assertion failed
#   2 — runner-level error (missing test file, missing prerequisites, cd failed)
#
# Notes on flag choice: `set -uo pipefail` is used WITHOUT `-e` on purpose —
# the runner must keep iterating across test files even if one of them fails
# its assertions. Per-step exit codes are checked explicitly where they matter.

set -uo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH

# Several test bodies match the multibyte arrow ("→") in command prose with a
# single `.` under grep -E. Under a POSIX/C locale that is a byte-wise match
# and six integration files fail for reasons unrelated to the code under
# test. Pin a UTF-8 locale when the caller has not chosen one, so results do
# not depend on the runner's LANG (CI images and remote sandboxes often ship
# with LC_CTYPE=POSIX).
if [ -z "${LC_ALL:-}" ]; then
  if locale -a 2>/dev/null | grep -qiE '^C\.utf-?8$'; then
    export LC_ALL=C.UTF-8
  elif locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then
    export LC_ALL=en_US.UTF-8
  fi
fi

# Several suites override HOME to isolate flow state. python3 derives its
# per-user site-packages from HOME, so on a machine where PyYAML was installed
# with `pip install --user` the override also hides PyYAML: flow-active-goal.sh
# then exits 2 (infrastructure error), hooks fall back to allowing, and dozens
# of assertions fail for a reason that has nothing to do with the code. Resolve
# the user site directory now, while HOME is still the real one, and put it on
# PYTHONPATH so it survives. A system-wide or virtualenv PyYAML is unaffected,
# which is why CI never needed this.
if command -v python3 >/dev/null 2>&1; then
  _flow_user_site=$(python3 -m site --user-site 2>/dev/null || true)
  if [ -n "$_flow_user_site" ] && [ -d "$_flow_user_site" ]; then
    case ":${PYTHONPATH:-}:" in
      *":$_flow_user_site:"*) ;;
      *) export PYTHONPATH="${PYTHONPATH:+$PYTHONPATH:}$_flow_user_site" ;;
    esac
  fi
  unset _flow_user_site
fi

# The suites set HOME to fixture directories to control the user settings tier
# of cascade-resolve.sh. FLOW_USER_SETTINGS replaces that tier, so an operator's
# own value would change what every one of them reads.
unset FLOW_USER_SETTINGS
# Likewise the plugin-root resolvers look for installed flow under
# ${CLAUDE_CONFIG_DIR:-$HOME/.claude}; an operator's CLAUDE_CONFIG_DIR would
# replace the fixture installs the suites build under HOME.
unset CLAUDE_CONFIG_DIR
# CLAUDE_PROJECT_DIR (set by Claude Code for hooks) is part of the repository
# cascade-resolve.sh judges; a test that needs it sets it itself.
unset CLAUDE_PROJECT_DIR
# A /flow:review dispatch exports these for its reviewers, and the reviewer
# fences the suites extract read them: an operator's or reviewer's value would
# point those fences at another tree.
unset REVIEW_TREE REVIEW_RUN_PR_COMMANDS
# Run inside a Claude Code session with flow installed, PATH starts with
# flow's git and gh wrappers (hooks/scripts/tier-session-start.sh), which
# would refuse a suite's tag push to a scratch remote. The suites see the
# same PATH they see outside a session; a suite about the wrappers sets them
# up itself.
unset FLOW_TIER_DIR FLOW_TIER_CALL
_flow_path=""
_flow_ifs=$IFS
IFS=:
for _flow_d in $PATH; do
  case "$_flow_d" in */flow/hooks/shims|*/flow/*/hooks/shims) continue ;; esac
  _flow_path="${_flow_path:+$_flow_path:}$_flow_d"
done
IFS=$_flow_ifs
PATH=$_flow_path
unset _flow_path _flow_ifs _flow_d
# Per-user state goes to a directory of this run's own. A suite that runs a
# hook or a script without setting FLOW_STATE_DIR or HOME itself would
# otherwise write into the real ~/.claude/flow-state: the quality-ledger
# tests' session s1 did, for weeks. A suite that tests the default under HOME
# unsets FLOW_STATE_DIR for that call. Removed when the run ends.
_flow_run_state=$(mktemp -d "${TMPDIR:-/tmp}/flow-run-state.XXXXXX") || {
  echo "run.sh: cannot create a state directory for this run" >&2
  exit 2
}
export FLOW_STATE_DIR="$_flow_run_state"
trap 'chmod -R u+rwx "$_flow_run_state" 2>/dev/null; rm -r "$_flow_run_state" 2>/dev/null' EXIT

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$TESTS_DIR/lib/assert.sh"

if [ ! -f "$LIB" ]; then
  echo "run.sh: missing $LIB" >&2
  exit 2
fi

# Prerequisite check: surface a single clear message at the runner level
# rather than letting individual tests produce cryptic per-tool errors.
for tool in awk grep sed mktemp; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "run.sh: missing prerequisite: $tool" >&2
    exit 2
  fi
done

# repo root is two levels up from tests/ (plugins/flow/tests -> plugins/flow -> repo).
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"

# Tests run from REPO_ROOT so relative paths in commands/ (e.g.,
# `.claude/settings.flow.local.json`) resolve against the same directory the
# actual command bash blocks would resolve them in. Fail loudly if the cd
# fails — silently running from the caller's cwd would make every test that
# uses a relative path report misleading results.
cd "$REPO_ROOT" || { echo "run.sh: cannot cd to $REPO_ROOT" >&2; exit 2; }

if [ $# -gt 0 ]; then
  TEST_FILES=("$@")
else
  # Glob in TESTS_DIR; sort for deterministic order.
  shopt -s nullglob
  TEST_FILES=("$TESTS_DIR"/*.test.sh)
  shopt -u nullglob
fi

if [ "${#TEST_FILES[@]}" -eq 0 ]; then
  echo "run.sh: no *.test.sh files found in $TESTS_DIR" >&2
  exit 2
fi

# FLOW_TEST_SHARD=K/N runs part K of N: the files at 0-based positions i in
# the list above with i mod N = K-1. CI splits the Linux suite this way so
# each part finishes well inside its time limit. A malformed value runs
# nothing: a typo must not pass by running a part of the suite, or none of it.
# The suites never see the variable.
if [ -n "${FLOW_TEST_SHARD+x}" ]; then
  _flow_shard=$FLOW_TEST_SHARD
  unset FLOW_TEST_SHARD
  _flow_k=${_flow_shard%%/*}
  _flow_n=${_flow_shard#*/}
  _flow_ok=1
  case "$_flow_shard" in */*) ;; *) _flow_ok=0 ;; esac
  # No leading zero, and at most four digits so the arithmetic cannot overflow.
  case "$_flow_k" in ''|0*|*[!0-9]*|?????*) _flow_ok=0 ;; esac
  case "$_flow_n" in ''|0*|*[!0-9]*|?????*) _flow_ok=0 ;; esac
  if [ "$_flow_ok" = 1 ] && [ "$_flow_k" -gt "$_flow_n" ]; then
    _flow_ok=0
  fi
  if [ "$_flow_ok" = 0 ]; then
    echo "run.sh: FLOW_TEST_SHARD must be K/N with whole numbers 1 <= K <= N, got '$_flow_shard'" >&2
    exit 2
  fi
  _flow_part=()
  _flow_i=0
  for _flow_f in "${TEST_FILES[@]}"; do
    [ $((_flow_i % _flow_n)) -ne $((_flow_k - 1)) ] || _flow_part+=("$_flow_f")
    _flow_i=$((_flow_i + 1))
  done
  echo "run.sh: shard $_flow_k/$_flow_n runs ${#_flow_part[@]} of ${#TEST_FILES[@]} files"
  # A part with no file would pass having tested nothing.
  if [ "${#_flow_part[@]}" -eq 0 ]; then
    echo "run.sh: FLOW_TEST_SHARD=$_flow_shard selects no file; use fewer parts" >&2
    exit 2
  fi
  TEST_FILES=("${_flow_part[@]}")
  unset _flow_part _flow_i _flow_f _flow_k _flow_n _flow_ok _flow_shard
fi

# FLOW_TEST_JOBS=N runs up to N files at once. The default is the number of
# CPUs; 1 runs them one after another in this process, as a single file
# always is. Each file runs in a run.sh of its own, given that one file, so
# it sees exactly what it sees when it is run alone: its own state directory
# and the same environment. Its output is printed whole, in list order, when
# it ends. The suites never see the variable.
_flow_jobs=${FLOW_TEST_JOBS-}
unset FLOW_TEST_JOBS
if [ -z "$_flow_jobs" ]; then
  _flow_jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
fi
case "$_flow_jobs" in
  ''|0*|*[!0-9]*|????*)
    echo "run.sh: FLOW_TEST_JOBS must be a whole number from 1 to 999, got '$_flow_jobs'" >&2
    exit 2 ;;
esac

# _flow_secs — seconds since the epoch.
_flow_secs() { date +%s; }

if [ "$_flow_jobs" -gt 1 ] && [ "${#TEST_FILES[@]}" -gt 1 ]; then
  _flow_par=$(mktemp -d "${TMPDIR:-/tmp}/flow-run-par.XXXXXX") || {
    echo "run.sh: cannot create a directory for the parallel run" >&2
    exit 2
  }
  # Stop the files still running when this run is stopped, and remove what it
  # wrote. A file's own run.sh removes its own state directory.
  # Every process under the one that starts the workers, deepest first.
  _flow_killtree() {
    local c
    for c in $(pgrep -P "$1" 2>/dev/null); do _flow_killtree "$c"; done
    kill -TERM "$1" 2>/dev/null
  }
  _flow_par_cleanup() {
    [ -z "${_flow_xargs_pid:-}" ] || _flow_killtree "$_flow_xargs_pid"
    rm -rf "$_flow_par" 2>/dev/null
    chmod -R u+rwx "$_flow_run_state" 2>/dev/null; rm -r "$_flow_run_state" 2>/dev/null
  }
  trap '_flow_par_cleanup' EXIT
  trap '_flow_par_cleanup; trap - INT; kill -INT $$' INT
  trap '_flow_par_cleanup; exit 143' TERM

  _flow_n=${#TEST_FILES[@]}
  echo "run.sh: running $_flow_n files, up to $_flow_jobs at a time"
  _flow_start=$(_flow_secs)
  _flow_i=0
  for _flow_f in "${TEST_FILES[@]}"; do
    if [ ! -f "$_flow_f" ] && [ -f "$TESTS_DIR/$_flow_f" ]; then
      _flow_f="$TESTS_DIR/$_flow_f"
    fi
    printf '%s\t%s\0' "$_flow_i" "$_flow_f"
    _flow_i=$((_flow_i + 1))
  done > "$_flow_par/list"

  # Files start longest first, by the times the last full run on this machine
  # took, kept in FLOW_TEST_TIMES (default ~/.cache/flow-tests/times, one
  # "<seconds> <file name>" line each). A file with no time yet starts first.
  # The order changes only how soon the run ends; output stays in list order.
  _flow_times_file=${FLOW_TEST_TIMES:-${XDG_CACHE_HOME:-$HOME/.cache}/flow-tests/times}
  tr '\0' '\n' < "$_flow_par/list" | awk -F '\t' -v times="$_flow_times_file" '
    BEGIN { while ((getline line < times) > 0) { split(line, a, " "); t[a[2]] = a[1] + 0 } }
    { n = $2; sub(/.*\//, "", n); s = (n in t) ? t[n] : 1000000; printf "%d\t%s\t%s\n", s, $1, $2 }
  ' | sort -t "$(printf '\t')" -k1,1nr -k2,2n | cut -f2- > "$_flow_par/order"
  # A file with a line `# flow-test: alone` (one that measures its own
  # speed, or works to a time budget) runs after the others, by itself, so
  # the load of the files around it cannot change its result.
  : > "$_flow_par/start"; : > "$_flow_par/alone"
  while IFS= read -r _flow_l; do
    if grep -qx '# flow-test: alone' "${_flow_l#*	}" 2>/dev/null; then
      printf '%s\0' "$_flow_l" >> "$_flow_par/alone"
    else
      printf '%s\0' "$_flow_l" >> "$_flow_par/start"
    fi
  done < "$_flow_par/order"

  # One worker per file: run.sh on that file alone, with FLOW_TEST_JOBS=1 so
  # a run.sh the file itself starts runs its fixtures in order. Writes
  # <i>.out (everything run.sh printed), <i>.rc, <i>.secs and, last, <i>.done.
  # shellcheck disable=SC2016
  # A background job of a script starts with SIGINT and SIGQUIT ignored, and
  # a program cannot undo an ignore it inherits from bash; perl resets both
  # before xargs starts, so a suite that interrupts its own processes sees
  # them stop as they do in a run one at a time.
  _flow_worker='
    dir=$1 runsh=$2 i=${3%%	*} f=${3#*	}
    s=$(date +%s)
    printf "run.sh: started %s\n" "${f##*/}"
    FLOW_TEST_JOBS=1 "$runsh" "$f" > "$dir/$i.out" 2>&1 < /dev/null
    printf "%s\n" "$?" > "$dir/$i.rc"
    printf "%s\n" "$(( $(date +%s) - s ))" > "$dir/$i.secs"
    : > "$dir/$i.done"
  '
  {
    perl -e '$SIG{INT} = $SIG{QUIT} = "DEFAULT"; exec @ARGV or die "exec: $!\n"' \
      xargs -0 -n 1 -P "$_flow_jobs" bash -c "$_flow_worker" _ "$_flow_par" "$TESTS_DIR/run.sh" < "$_flow_par/start"
    perl -e '$SIG{INT} = $SIG{QUIT} = "DEFAULT"; exec @ARGV or die "exec: $!\n"' \
      xargs -0 -n 1 -P 1 bash -c "$_flow_worker" _ "$_flow_par" "$TESTS_DIR/run.sh" < "$_flow_par/alone"
  } &
  _flow_xargs_pid=$!

  TOTAL_PASS=0
  TOTAL_FAIL=0
  FAILED_FILES=()
  RUNNER_ERR=0
  _flow_times=""
  _flow_i=0
  while [ "$_flow_i" -lt "$_flow_n" ]; do
    # Each file is printed in list order once it has ended; a finished xargs
    # with no .done for it means its worker never ran or was killed.
    while [ ! -f "$_flow_par/$_flow_i.done" ]; do
      if ! kill -0 "$_flow_xargs_pid" 2>/dev/null && [ ! -f "$_flow_par/$_flow_i.done" ]; then
        break
      fi
      sleep 0.2
    done
    _flow_f=$(tr '\0' '\n' < "$_flow_par/list" | sed -n "$((_flow_i + 1))p")
    _flow_f=${_flow_f#*	}
    _flow_name=${_flow_f##*/}
    if [ ! -f "$_flow_par/$_flow_i.done" ]; then
      echo "=== $_flow_name ==="
      echo "run.sh: $_flow_name did not finish: its worker stopped before it ended" >&2
      RUNNER_ERR=1
      FAILED_FILES+=("$_flow_name")
      _flow_i=$((_flow_i + 1))
      continue
    fi
    _flow_rc=$(cat "$_flow_par/$_flow_i.rc")
    _flow_s=$(cat "$_flow_par/$_flow_i.secs")
    _flow_out=$(cat "$_flow_par/$_flow_i.out")
    # The file's own run.sh printed its block, with the time the file took,
    # then "=== overall ===" and its totals; the block is printed as it is.
    printf '%s\n' "$_flow_out" | sed '/^=== overall ===$/,$d'
    _flow_total=$(printf '%s\n' "$_flow_out" | sed -n 's/^TOTAL pass=\([0-9][0-9]*\) fail=\([0-9][0-9]*\)$/\1 \2/p' | tail -1)
    if [ -z "$_flow_total" ]; then
      echo "run.sh: $_flow_name: its run.sh printed no TOTAL line (exit=$_flow_rc); last lines:" >&2
      printf '%s\n' "$_flow_out" | tail -10 >&2
      RUNNER_ERR=1
      FAILED_FILES+=("$_flow_name")
    else
      TOTAL_PASS=$((TOTAL_PASS + ${_flow_total% *}))
      TOTAL_FAIL=$((TOTAL_FAIL + ${_flow_total#* }))
      case "$_flow_rc" in
        0) ;;
        1) FAILED_FILES+=("$_flow_name") ;;
        *) RUNNER_ERR=1; FAILED_FILES+=("$_flow_name") ;;
      esac
    fi
    _flow_times="$_flow_times$_flow_s $_flow_name
"
    [ "${_flow_f%/*}" != "$TESTS_DIR" ] || printf '%s\n' "$_flow_name" >> "$_flow_par/names"
    _flow_i=$((_flow_i + 1))
  done
  touch "$_flow_par/names"
  wait "$_flow_xargs_pid" 2>/dev/null
  _flow_xargs_pid=""
  _flow_elapsed=$(( $(_flow_secs) - _flow_start ))

  echo "=== durations (seconds, longest first) ==="
  printf '%s' "$_flow_times" | sort -rn -k1,1 | sed 's/^/  /'
  # Keep this run's times of the suite's own files for the next run's order;
  # a file not run this time keeps its old time.
  if mkdir -p "$(dirname "$_flow_times_file")" 2>/dev/null; then
    {
      printf '%s' "$_flow_times" | awk -v d="$TESTS_DIR" -v list="$_flow_par/names" '
        BEGIN { while ((getline l < list) > 0) own[l] = 1 }
        ($2 in own) { print }'
      [ -f "$_flow_times_file" ] && awk -v list="$_flow_par/names" '
        BEGIN { while ((getline l < list) > 0) own[l] = 1 }
        !($2 in own)' "$_flow_times_file"
    } > "$_flow_times_file.$$" 2>/dev/null && mv -f "$_flow_times_file.$$" "$_flow_times_file" 2>/dev/null
    rm -f "$_flow_times_file.$$" 2>/dev/null
  fi
  echo "=== overall ==="
  echo "TOTAL pass=$TOTAL_PASS fail=$TOTAL_FAIL"
  echo "TIME ${_flow_elapsed}s for ${_flow_n} files, up to ${_flow_jobs} at a time"
  if [ "${#FAILED_FILES[@]}" -gt 0 ]; then
    echo "FAILED files: ${FAILED_FILES[*]}"
  fi
  if [ "$RUNNER_ERR" != "0" ]; then
    exit 2
  fi
  if [ "$TOTAL_FAIL" != "0" ]; then
    exit 1
  fi
  exit 0
fi

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_FILES=()
# Tracked separately from assertion failures: a runner-level error (missing
# test file, malformed SUMMARY) is NOT the same as a test failure. The exit
# code distinguishes 1 (assertions failed) from 2 (runner error).
RUNNER_ERR=0
_flow_times=""
_flow_start=$(_flow_secs)

for TEST_FILE in "${TEST_FILES[@]}"; do
  # Resolve relative arg against TESTS_DIR.
  if [ ! -f "$TEST_FILE" ] && [ -f "$TESTS_DIR/$TEST_FILE" ]; then
    TEST_FILE="$TESTS_DIR/$TEST_FILE"
  fi
  if [ ! -f "$TEST_FILE" ]; then
    echo "run.sh: $TEST_FILE not found" >&2
    RUNNER_ERR=1
    FAILED_FILES+=("$TEST_FILE")
    continue
  fi

  echo "=== $(basename "$TEST_FILE") ==="
  _flow_file_start=$(_flow_secs)
  # Parse before sourcing. `source` on a file with a syntax error stops at the
  # error but leaves the subshell alive, so _flow_test_summary still prints a
  # well-formed SUMMARY counting only the assertions that ran — a file bash
  # cannot parse reported "pass=71 fail=0" and the truncation was invisible.
  if ! PARSE_ERR=$(bash -n "$TEST_FILE" 2>&1); then
    echo "run.sh: $(basename "$TEST_FILE") does not parse — no assertion in it ran:" >&2
    printf '%s\n' "$PARSE_ERR" >&2
    RUNNER_ERR=1
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    FAILED_FILES+=("$(basename "$TEST_FILE")")
    continue
  fi
  # Capture stdout AND stderr together: stderr from awk/grep/jq inside test
  # bodies otherwise interleaves out-of-order with the SUMMARY extraction
  # below and is invisible to CI artifact capture (T4/EV2). Also capture the
  # subshell's exit code so a `set -u` unbound-var abort or explicit `exit`
  # inside a test body surfaces with diagnostic context rather than just a
  # bare "no SUMMARY line".
  # fd 3 is this runner's own stdout, left out of the capture: a suite may
  # write progress there that shows while it runs (the output below appears
  # only when the file ends, so a CI job cut off inside a file says nothing
  # about where).
  exec 3>&1
  OUTPUT=$({
    set +e
    # shellcheck source=lib/assert.sh
    source "$LIB"
    # shellcheck disable=SC1090
    source "$TEST_FILE"
    _flow_test_summary
  } 2>&1)
  RC=$?
  printf '%s\n' "$OUTPUT"
  _flow_s=$(( $(_flow_secs) - _flow_file_start ))
  echo "run.sh: $(basename "$TEST_FILE") took ${_flow_s}s"
  _flow_times="$_flow_times$_flow_s $(basename "$TEST_FILE")
"
  # Extract last SUMMARY line — tolerate trailing whitespace and CR (a stray
  # CRLF in a test file used to make the anchored regex reject the line).
  SUMMARY=$(printf '%s\n' "$OUTPUT" | tr -d '\r' | grep -E '^SUMMARY pass=[0-9]+ fail=[0-9]+[[:space:]]*$' | tail -1)
  if [ -z "$SUMMARY" ]; then
    echo "run.sh: WARN no SUMMARY line from $(basename "$TEST_FILE") (subshell exit=$RC); last lines:" >&2
    printf '%s\n' "$OUTPUT" | tail -10 >&2
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    FAILED_FILES+=("$(basename "$TEST_FILE")")
    continue
  fi
  FILE_PASS=$(printf '%s' "$SUMMARY" | sed -E 's/.*pass=([0-9]+).*/\1/')
  FILE_FAIL=$(printf '%s' "$SUMMARY" | sed -E 's/.*fail=([0-9]+).*/\1/')
  # Defensive: a future SUMMARY format that emits non-numeric values would
  # break the arithmetic that follows. Catch and route to a clear error.
  if ! [[ "$FILE_PASS" =~ ^[0-9]+$ ]] || ! [[ "$FILE_FAIL" =~ ^[0-9]+$ ]]; then
    echo "run.sh: WARN malformed SUMMARY from $(basename "$TEST_FILE"): '$SUMMARY'" >&2
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    FAILED_FILES+=("$(basename "$TEST_FILE")")
    continue
  fi
  # Zero-assertion files are a hazard, not a clean PASS: a future test that
  # accidentally comments out every assertion would otherwise silently
  # report green. Treat as a runner-level error.
  if [ "$FILE_PASS" = "0" ] && [ "$FILE_FAIL" = "0" ]; then
    echo "run.sh: WARN $(basename "$TEST_FILE") executed no assertions; counting as failure" >&2
    RUNNER_ERR=1
    FAILED_FILES+=("$(basename "$TEST_FILE")")
    continue
  fi
  TOTAL_PASS=$((TOTAL_PASS + FILE_PASS))
  TOTAL_FAIL=$((TOTAL_FAIL + FILE_FAIL))
  if [ "$FILE_FAIL" != "0" ]; then
    FAILED_FILES+=("$(basename "$TEST_FILE")")
  fi
  echo ""
done

if [ "${#TEST_FILES[@]}" -gt 1 ]; then
  echo "=== durations (seconds, longest first) ==="
  printf '%s' "$_flow_times" | sort -rn -k1,1 | sed 's/^/  /'
fi
echo "=== overall ==="
echo "TOTAL pass=$TOTAL_PASS fail=$TOTAL_FAIL"
echo "TIME $(( $(_flow_secs) - _flow_start ))s for ${#TEST_FILES[@]} files, one at a time"
if [ "${#FAILED_FILES[@]}" -gt 0 ]; then
  echo "FAILED files: ${FAILED_FILES[*]}"
fi
# Exit code precedence: runner errors (exit 2) beat assertion failures
# (exit 1) beat success (exit 0). The two are reported separately above so
# CI can tell "you broke the harness" apart from "a real test failed".
if [ "$RUNNER_ERR" != "0" ]; then
  exit 2
fi
if [ "$TOTAL_FAIL" != "0" ]; then
  exit 1
fi
exit 0
