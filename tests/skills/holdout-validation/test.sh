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

# Test 6: empty arrays for all required fields satisfy the schema. Whether the
# skill should be invoked on empty inputs is the caller's call; the schema
# permits the shape.
"$VALIDATE" holdout-validation '{"selfReviewFindings":[],"evidenceBundle":[],"fileList":[]}' >/dev/null 2>&1
assert_exit "all-empty-arrays payload validates (schema permits empty)" 0 $?

# Test 7: ID with trailing newline must fail. Python `re` accepts `\n` before
# `$` in default mode; the schema uses `\Z` to reject. Regression guard for
# the marker-grammar corruption vector (FINDINGS:[F1\n|P1|...] in merge.md).
"$VALIDATE" holdout-validation '{
  "selfReviewFindings":[{"id":"F1\n","priority":"P1","category":"security","location":"src/x.ts:1","problem":"any"}],
  "evidenceBundle":[],
  "fileList":[]
}' >/dev/null 2>&1
assert_exit "ID with trailing newline rejected (\\Z anchor)" 1 $?

echo ""
echo "============================================"
echo "RESULT: $PASS passed, $FAIL failed"
echo "============================================"
# Guard against a no-op run masquerading as success: if not a single assert
# fired, the test harness itself is broken (e.g., a python helper raised
# before the loop ran). With set -uo pipefail (no -e) and PASS+FAIL accumulators,
# only this final check distinguishes "no assertions" from "all assertions ok".
[ "$PASS" -eq 0 ] && { echo "FAIL: no assertions ran — harness regression" >&2; exit 1; }
[ "$FAIL" -gt 0 ] && exit 1
exit 0
