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
# a different name.
#
# Usage:
#   tests/run-all.sh            # run everything
#   tests/run-all.sh --list     # print the entry points and exit
#
# Exit:
#   0 — every entry point exited 0
#   1 — at least one entry point failed
#   2 — runner error (nothing found, or an unclassified .sh file)

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

LIST_ONLY=0
[ "${1:-}" = "--list" ] && LIST_ONLY=1

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

ENTRY_POINTS=()
while IFS= read -r f; do
  [ -n "$f" ] && ENTRY_POINTS+=("$f")
done < <(find "$TESTS_DIR" -type f \( -name 'test.sh' -o -name 'validate.sh' -o -name 'verify.sh' \) | LC_ALL=C sort)

# Everything else that looks like a script. run-all.sh itself is excluded; any
# other survivor means someone added a check this runner would not have run.
UNCLASSIFIED=()
while IFS= read -r f; do
  case "$f" in
    "$TESTS_DIR/run-all.sh") continue ;;
    */test.sh|*/validate.sh|*/verify.sh) continue ;;
  esac
  [ -n "$f" ] && UNCLASSIFIED+=("$f")
done < <(find "$TESTS_DIR" -type f -name '*.sh' | LC_ALL=C sort)

if [ "$LIST_ONLY" = "1" ]; then
  for f in "${ENTRY_POINTS[@]:-}"; do
    [ -n "$f" ] && printf '%s\n' "${f#"$REPO_ROOT"/}"
  done
  exit 0
fi

# Reported before the empty-tree check: when a tree holds only scripts this
# runner does not recognise, "no entry points found" is true but useless, and
# the name of the script it declined to run is the whole answer.
if [ "${#UNCLASSIFIED[@]}" -gt 0 ]; then
  echo "run-all.sh: shell scripts under tests/ that this runner does not recognise as entry points:" >&2
  for f in "${UNCLASSIFIED[@]}"; do
    echo "  ${f#"$REPO_ROOT"/}" >&2
  done
  echo "run-all.sh: rename them to test.sh / validate.sh / verify.sh, or teach this runner about them." >&2
  exit 2
fi

if [ "${#ENTRY_POINTS[@]}" -eq 0 ]; then
  echo "run-all.sh: no entry points found under $TESTS_DIR" >&2
  exit 2
fi

# Run from the repository root: several scripts resolve paths relative to the
# git toplevel and one of them shells out to git.
cd "$REPO_ROOT" || { echo "run-all.sh: cannot cd to $REPO_ROOT" >&2; exit 2; }

echo "run-all.sh: ${#ENTRY_POINTS[@]} entry points under tests/"
echo ""

PASSED=0
FAILED=0
FAILED_NAMES=()

for f in "${ENTRY_POINTS[@]}"; do
  REL="${f#"$REPO_ROOT"/}"
  echo "=== $REL ==="
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$PER_SCRIPT_TIMEOUT" bash "$f"
  else
    bash "$f"
  fi
  RC=$?
  if [ "$RC" -eq 0 ]; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
    FAILED_NAMES+=("$REL (exit $RC)")
    if [ -n "$TIMEOUT_BIN" ] && [ "$RC" -eq 124 ]; then
      echo "run-all.sh: $REL exceeded ${PER_SCRIPT_TIMEOUT}s and was killed" >&2
    fi
  fi
  echo ""
done

echo "=== overall ==="
echo "run-all.sh: examined ${#ENTRY_POINTS[@]} entry points — $PASSED passed, $FAILED failed"
if [ "$FAILED" -gt 0 ]; then
  echo "FAILED:"
  for n in "${FAILED_NAMES[@]}"; do echo "  $n"; done
  exit 1
fi
exit 0
