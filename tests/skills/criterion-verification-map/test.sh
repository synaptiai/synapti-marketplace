#!/usr/bin/env bash
# Test the criterion-verification-map skill input contract.

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
"$VALIDATE" criterion-verification-map "$(cat "$DIR/valid-input.json")" >/dev/null 2>&1
assert_exit "valid-input.json validates" 0 $?

# Test 2: invalid (text too short, type not in enum)
"$VALIDATE" criterion-verification-map "$(cat "$DIR/invalid-input.json")" >/dev/null 2>&1
assert_exit "invalid-input.json (short text + bad enum) fails validation" 1 $?

# Test 3: empty acceptanceCriteria fails (minItems: 1)
"$VALIDATE" criterion-verification-map '{"acceptanceCriteria":[]}' >/dev/null 2>&1
assert_exit "empty acceptanceCriteria fails minItems" 1 $?

# Test 4: missing acceptanceCriteria entirely
"$VALIDATE" criterion-verification-map '{}' >/dev/null 2>&1
assert_exit "missing acceptanceCriteria fails validation" 1 $?

# Test 5: criterion missing required text field
"$VALIDATE" criterion-verification-map '{"acceptanceCriteria":[{"type":"api"}]}' >/dev/null 2>&1
assert_exit "criterion without text fails validation" 1 $?

# Test 6: criterion with text but no type (type is optional)
"$VALIDATE" criterion-verification-map '{"acceptanceCriteria":[{"text":"Some criterion text"}]}' >/dev/null 2>&1
assert_exit "criterion with only text validates (type optional)" 0 $?

echo ""
echo "============================================"
echo "RESULT: $PASS passed, $FAIL failed"
echo "============================================"
[ "$PASS" -eq 0 ] && { echo "FAIL: no assertions ran — harness regression" >&2; exit 1; }
[ "$FAIL" -gt 0 ] && exit 1
exit 0
