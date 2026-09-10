#!/usr/bin/env bash
# tests/run-all.sh — runs every check in the repository-root tests/ tree.
#
# These are standalone scripts, each printing its own PASS/FAIL lines and
# exiting 0 on success. They predate the assert.sh harness under
# plugins/flow/tests/ and are kept as written; this runner exists so a workflow
# can reach them. Before it existed, no workflow matched this directory and one
# of the eleven had been failing for an unknown length of time (issue #177).
#
# Entry points are found by name — test.sh, validate.sh, verify.sh — rather than
# by the executable bit, so a lost `chmod +x` cannot silently drop a check. Any
# other .sh file in the tree is reported and treated as a runner error, because
# the alternative is a runner that quietly skips a new check whose author picked
# a different name. A shared helper that is not itself a check belongs under a
# `lib/` directory, which is the one exemption.
#
# Usage:
#   tests/run-all.sh            # run everything
#   tests/run-all.sh --list     # print the entry points and exit
#
# Exit:
#   0 — every entry point exited 0
#   1 — at least one check ran and reported a defect
#   2 — runner error: nothing found, an unclassified .sh file, a walk that could
#       not complete, or a check that could not run (exit 2, a timeout, a
#       signal, or one that exited 0 having examined nothing)

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

LIST_ONLY=0
case "${1:-}" in
  '') ;;
  --list) LIST_ONLY=1 ;;
  *)
    # A silently ignored argument is a typo that runs the whole suite when the
    # caller asked for something else.
    echo "run-all.sh: unknown argument: $1" >&2
    echo "usage: tests/run-all.sh [--list]" >&2
    exit 2 ;;
esac

# Per-script wall-clock ceiling. A hung script must fail the run rather than
# consume the whole job budget. `timeout` is GNU coreutils and is absent from a
# stock macOS; there the scripts run without a ceiling and the workflow's own
# timeout-minutes is the backstop.
TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
fi
PER_SCRIPT_TIMEOUT="${ROOT_TESTS_TIMEOUT:-300}"
case "$PER_SCRIPT_TIMEOUT" in
  ''|*[!0-9]*|0)
    # GNU `timeout 0` means no limit at all. Accepting it would leave the
    # runner reporting a ceiling it is not enforcing.
    echo "run-all.sh: ROOT_TESTS_TIMEOUT must be a positive integer (got: $PER_SCRIPT_TIMEOUT)" >&2
    exit 2 ;;
esac

# The walk's exit status is read, not assumed. `find` exits non-zero when it
# cannot descend somewhere — one subdirectory at mode 000 is enough — and it
# still prints everything it did reach. Trusting that partial list is exactly
# the failure this runner exists to prevent: a check silently stops being run
# while the report stays green.
ENTRY_POINTS=()
FIND_OUT=$(find "$TESTS_DIR" -type f \( -name 'test.sh' -o -name 'validate.sh' -o -name 'verify.sh' \) | LC_ALL=C sort)
FIND_RC=$?
if [ "$FIND_RC" -ne 0 ]; then
  echo "run-all.sh: could not walk $TESTS_DIR (find exit $FIND_RC) — the discovered list may be short, refusing to report on it" >&2
  exit 2
fi
while IFS= read -r f; do
  [ -n "$f" ] || continue
  # A path is only an entry point if it is under tests/. `find` output is split
  # on newlines, and git permits a newline in a filename: such a path arrives as
  # two entries, the second of them relative, which would resolve against the
  # repository root once this runner cd's there.
  case "$f" in
    "$TESTS_DIR"/*) ENTRY_POINTS+=("$f") ;;
    *)
      echo "run-all.sh: refusing a discovered path that is not under $TESTS_DIR: $f" >&2
      exit 2 ;;
  esac
done <<EOF_FIND
$FIND_OUT
EOF_FIND

# Everything else that looks like a script. run-all.sh itself is excluded; any
# other survivor means someone added a check this runner would not have run.
UNCLASSIFIED=()
ALL_SH=$(find "$TESTS_DIR" -type f -name '*.sh' | LC_ALL=C sort)
FIND_RC=$?
if [ "$FIND_RC" -ne 0 ]; then
  echo "run-all.sh: could not walk $TESTS_DIR (find exit $FIND_RC)" >&2
  exit 2
fi
while IFS= read -r f; do
  case "$f" in
    "$TESTS_DIR/run-all.sh") continue ;;
    */test.sh|*/validate.sh|*/verify.sh) continue ;;
    */lib/*) continue ;;                      # shared helpers, not checks
  esac
  [ -n "$f" ] && UNCLASSIFIED+=("$f")
done <<EOF_ALL
$ALL_SH
EOF_ALL

# Both modes share one discovery contract. --list used to return above these
# checks, so it printed an empty list and exited 0 on a tree the run path calls
# a runner error.
if [ "${#UNCLASSIFIED[@]}" -gt 0 ]; then
  echo "run-all.sh: shell scripts under tests/ that this runner does not recognise as entry points:" >&2
  for f in "${UNCLASSIFIED[@]}"; do
    echo "  ${f#"$REPO_ROOT"/}" >&2
  done
  echo "run-all.sh: rename them to test.sh / validate.sh / verify.sh, or move a shared helper under a lib/ directory." >&2
  exit 2
fi

if [ "${#ENTRY_POINTS[@]}" -eq 0 ]; then
  echo "run-all.sh: no entry points found under $TESTS_DIR" >&2
  exit 2
fi

if [ "$LIST_ONLY" = "1" ]; then
  for f in "${ENTRY_POINTS[@]}"; do
    printf '%s\n' "${f#"$REPO_ROOT"/}"
  done
  exit 0
fi

# Run from the repository root: several scripts resolve paths relative to the
# git toplevel and one of them shells out to git.
cd "$REPO_ROOT" || { echo "run-all.sh: cannot cd to $REPO_ROOT" >&2; exit 2; }

# Several of these checks build a sandbox with `SANDBOX=$(mktemp -d)` and then
# `cd "$SANDBOX"` without checking either. `cd ""` returns 0 and leaves $PWD
# alone, so on a machine where mktemp cannot allocate — a read-only or full
# TMPDIR — those scripts would run `git init`, `git commit` and `ln -sf` in
# whatever directory they inherited. This runner is what makes that inherited
# directory deterministically the repository, so it is the right place to
# refuse. Probing once here covers every callee without reaching into files
# this change does not otherwise touch.
_probe=$(mktemp -d 2>/dev/null) || _probe=""
if [ -z "$_probe" ] || [ ! -d "$_probe" ]; then
  echo "run-all.sh: mktemp -d failed. Several checks cd into their mktemp result without" >&2
  echo "run-all.sh: checking it, and would run git commands in $REPO_ROOT instead. Refusing." >&2
  exit 2
fi
rmdir "$_probe" 2>/dev/null || true
unset _probe

# tests/journal-orchestration/test.sh drives the PyYAML-backed journal writer and
# does not skip when the module is absent — it reports thirteen failures that all
# say the same thing. Say it once, up front, so the output is legible.
if command -v python3 >/dev/null 2>&1 && ! python3 -c "import yaml" >/dev/null 2>&1; then
  echo "run-all.sh: WARN PyYAML is not importable by $(command -v python3)." >&2
  echo "run-all.sh: WARN tests/journal-orchestration/test.sh needs it and will fail without it." >&2
  echo "run-all.sh: WARN python3 -m pip install --user --break-system-packages -r plugins/flow/requirements.txt" >&2
  echo "" >&2
fi

echo "run-all.sh: ${#ENTRY_POINTS[@]} entry points under tests/"
echo ""

PASSED=0
FAILED=0
FAILED_NAMES=()
# A check that could not run is not the same event as a check that ran and
# found a defect, and collapsing them loses the distinction the checks
# themselves take care to make: every one of them exits 2 when a prerequisite
# is missing. Tracked separately and reported as exit 2, matching
# plugins/flow/tests/run.sh.
RUNNER_ERR=0

for f in "${ENTRY_POINTS[@]}"; do
  REL="${f#"$REPO_ROOT"/}"
  echo "=== $REL ==="
  # -k sends KILL after a grace period, so a check that traps or ignores TERM
  # is still stopped here and keeps its attribution, rather than running on
  # until the job-level timeout kills the whole run with no name attached.
  OUT_FILE=$(mktemp -t root-tests-out.XXXXXX)
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" -k 10 "$PER_SCRIPT_TIMEOUT" bash "$f" 2>&1 | tee "$OUT_FILE"
    RC=${PIPESTATUS[0]}
  else
    bash "$f" 2>&1 | tee "$OUT_FILE"
    RC=${PIPESTATUS[0]}
  fi

  # How much did it examine? Each of these scripts prints its own tally; a run
  # that reports zero assertions passed is a check that reached nothing, which
  # reads identically to a clean run unless it is called out.
  TALLY=$(grep -oE '(RESULT: [0-9]+ passed|Total: [0-9]+ PASS|SUMMARY pass=[0-9]+)' "$OUT_FILE" | tail -1)
  PASS_N=$(printf '%s' "$TALLY" | grep -oE '[0-9]+' | tail -1)
  rm -f "$OUT_FILE"

  if [ "$RC" -eq 0 ] && [ -n "$TALLY" ] && [ "${PASS_N:-0}" -eq 0 ]; then
    echo "run-all.sh: $REL exited 0 but reports 0 assertions passed — it examined nothing" >&2
    RUNNER_ERR=1
    FAILED_NAMES+=("$REL (0 assertions examined)")
    echo ""
    continue
  fi

  if [ "$RC" -eq 0 ]; then
    PASSED=$((PASSED + 1))
  else
    case "$RC" in
      2|124|125|126|127|13[0-9]|14[0-3])
        # 2 is the infrastructure exit these scripts use for a missing
        # prerequisite; 124-127 come from timeout and the shell failing to run
        # the file; 13x is death by signal.
        RUNNER_ERR=1
        FAILED_NAMES+=("$REL (could not run: exit $RC)") ;;
      *)
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("$REL (failed: exit $RC)") ;;
    esac
    if [ -n "$TIMEOUT_BIN" ] && { [ "$RC" -eq 124 ] || [ "$RC" -eq 137 ]; }; then
      echo "run-all.sh: $REL exceeded ${PER_SCRIPT_TIMEOUT}s and was killed" >&2
    fi
  fi
  echo ""
done

echo "=== overall ==="
echo "run-all.sh: examined ${#ENTRY_POINTS[@]} entry points — $PASSED passed, $FAILED failed"
if [ "${#FAILED_NAMES[@]}" -gt 0 ]; then
  echo "FAILED:"
  for n in "${FAILED_NAMES[@]}"; do echo "  $n"; done
fi
# Exit-code precedence matches plugins/flow/tests/run.sh: a runner error (2)
# beats an assertion failure (1) beats success.
if [ "$RUNNER_ERR" != "0" ]; then
  exit 2
fi
if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
exit 0
