#!/usr/bin/env bash
# Test the holdout-validation skill input contract.
# Verifies that bin/validate-skill-input.sh correctly accepts the canonical
# valid input shape and rejects malformed inputs.

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

# Test 1: valid input must exit 0
"$VALIDATE" holdout-validation "$(cat "$DIR/valid-input.json")" >/dev/null 2>&1
assert_exit "valid-input.json validates" 0 $?

# Test 2: invalid input (missing required fields, bad ID, bad priority) must exit 1
"$VALIDATE" holdout-validation "$(cat "$DIR/invalid-input.json")" >/dev/null 2>&1
assert_exit "invalid-input.json fails validation" 1 $?

# Test 3: empty object must fail (missing all required fields)
"$VALIDATE" holdout-validation '{}' >/dev/null 2>&1
assert_exit "empty payload fails validation" 1 $?

# Test 4: missing one required field
"$VALIDATE" holdout-validation '{"selfReviewFindings":[],"evidenceBundle":[]}' >/dev/null 2>&1
assert_exit "missing fileList fails validation" 1 $?

# Test 5: invalid JSON must exit 2 (infrastructure-level error, not validation)
"$VALIDATE" holdout-validation 'not json' >/dev/null 2>&1
assert_exit "non-JSON input exits 2 (infra error)" 2 $?

# Test 6: empty arrays for all required fields are still valid (skill handles empty inputs)
"$VALIDATE" holdout-validation '{"selfReviewFindings":[],"evidenceBundle":[],"fileList":[]}' >/dev/null 2>&1
assert_exit "all-empty-arrays payload validates (skill accepts)" 0 $?

echo ""
echo "============================================"
echo "RESULT: $PASS passed, $FAIL failed"
echo "============================================"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
