#!/usr/bin/env bash
# mock-gh.sh — stub for the `gh` CLI. Tests prepend a temp dir to $PATH that
# contains a `gh` symlink to this script, isolating the suite from real
# GitHub state.
#
# Routing via $MOCK_GH_ROUTES: a file mapping argument signatures to
# response/exit-code fixtures, parsed line-by-line:
#
#   <signature>|<exit_code>|<stdout_fixture_path>
#
# The signature is matched against the whole argv joined by spaces, e.g.:
#   "api user --jq .login" → exit 0, prints contents of file
#   "pr list --state open --limit 100 --json number,author,assignees" → ...
#
# First matching line wins. If $MOCK_GH_ROUTES is unset or no line matches:
#   - exit 0, empty stdout (mimics a quiet success)
#
# Invocations are appended to $MOCK_GH_LOG so tests can assert call shape.

set -uo pipefail

ARGV_LINE="$*"

# Always log the invocation
if [ -n "${MOCK_GH_LOG:-}" ]; then
  printf '%s\n' "$ARGV_LINE" >> "$MOCK_GH_LOG"
fi

# No routes file → return empty success
if [ -z "${MOCK_GH_ROUTES:-}" ] || [ ! -f "${MOCK_GH_ROUTES}" ]; then
  exit 0
fi

while IFS='|' read -r SIGNATURE EXIT_CODE STDOUT_PATH; do
  # Skip comments and blank lines
  case "$SIGNATURE" in '' | '#'*) continue ;; esac
  # Trim trailing whitespace from SIGNATURE
  SIGNATURE="${SIGNATURE%"${SIGNATURE##*[![:space:]]}"}"
  if [ "$ARGV_LINE" = "$SIGNATURE" ] || [[ "$ARGV_LINE" == $SIGNATURE ]]; then
    if [ -n "$STDOUT_PATH" ] && [ -f "$STDOUT_PATH" ]; then
      cat "$STDOUT_PATH"
    fi
    exit "${EXIT_CODE:-0}"
  fi
done < "${MOCK_GH_ROUTES}"

# No route matched — quiet success (matches "no PRs" / "no comments" semantics)
exit 0
