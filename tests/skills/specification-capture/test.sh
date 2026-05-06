#!/usr/bin/env bash
# Test the specification-capture skill input contract.

set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
VALIDATE="$REPO_ROOT/plugins/flow/bin/validate-skill-input.sh"

if [ ! -x "$VALIDATE" ]; then
  echo "FATAL: validator not found or not executable at $VALIDATE" >&2
  exit 2
fi

PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $desc (exit=$actual)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc (expected exit=$expected, got exit=$actual)"
    FAIL=$((FAIL + 1))
  fi
}

# Test 1: valid input
"$VALIDATE" specification-capture "$(cat "$DIR/valid-input.json")" >/dev/null 2>&1
assert_exit "valid-input.json validates" 0 $?

# Test 2: invalid (missing title, journalPath has wrong extension, invocationReason not in enum)
"$VALIDATE" specification-capture "$(cat "$DIR/invalid-input.json")" >/dev/null 2>&1
assert_exit "invalid-input.json fails validation" 1 $?

# Test 3: missing journalPath
"$VALIDATE" specification-capture '{"issueContext":{"title":"X"},"invocationReason":"start"}' >/dev/null 2>&1
assert_exit "missing journalPath fails validation" 1 $?

# Test 4: invocationReason "merge" not in enum
"$VALIDATE" specification-capture '{"issueContext":{"title":"X"},"journalPath":".decisions/issue-1.md","invocationReason":"merge"}' >/dev/null 2>&1
assert_exit "invocationReason='merge' not in enum, fails" 1 $?

# Test 5: minimal valid (only required fields, no comments/labels)
"$VALIDATE" specification-capture '{"issueContext":{"title":"X"},"journalPath":".decisions/issue-1.md","invocationReason":"design"}' >/dev/null 2>&1
assert_exit "minimal valid input validates" 0 $?

# Test 6: invocationReason="brainstorm" is valid
"$VALIDATE" specification-capture '{"issueContext":{"title":"X"},"journalPath":".decisions/issue-1.md","invocationReason":"brainstorm"}' >/dev/null 2>&1
assert_exit "invocationReason='brainstorm' validates" 0 $?

echo ""
echo "============================================"
echo "RESULT: $PASS passed, $FAIL failed"
echo "============================================"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
