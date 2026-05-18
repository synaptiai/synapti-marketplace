# Tests for plugins/flow/bin/validate-skill-input.sh.
#
# Contract (from the helper's header):
#   Usage: validate-skill-input.sh <skill-name> '<json-input>'
#
#   Exit 0: input validates against the schema.
#   Exit 1: input fails validation (rationale on stderr).
#   Exit 2: schema not found, input not valid JSON, kebab-case violation,
#           or other infrastructure error.
#
#   Schema lookup: ${CLAUDE_PLUGIN_ROOT}/schemas/<skill>/input-schema.json,
#   falling back to <repo>/plugins/flow/schemas/<skill>/ for in-repo callers.
#
# Prerequisites: python3. The jsonschema package is optional — the helper
# falls back to an in-house shape-checker for the JSON Schema subset flow
# actually uses. Tests cover both paths where feasible.

HELPER="$REPO_ROOT/plugins/flow/bin/validate-skill-input.sh"

# An always-present skill schema in this repo. criterion-verification-map
# declares `acceptanceCriteria` (array, minItems=1) as required.
EXISTING_SKILL="criterion-verification-map"

# Skip the suite if python3 is unavailable.
if ! command -v python3 >/dev/null 2>&1; then
  _flow_test_begin "python3 prerequisite"
  _flow_assert_pass "SKIP: python3 not installed"
  return 0
fi

# --- Test 1: too few args → exit 2 with usage
_flow_test_begin "no args → exit 2 with usage"
ERR=$("$HELPER" 2>&1 >/dev/null)
EXIT=$?
assert_exit 2 "$EXIT" "exit 2"
assert_contains "Usage:" "$ERR" "usage text on stderr"

# --- Test 2: invalid skill name (path traversal attempt) → exit 2
_flow_test_begin "path-traversal skill name → exit 2 (charset guard)"
ERR=$("$HELPER" "../../../etc/passwd" '{}' 2>&1 >/dev/null)
EXIT=$?
assert_exit 2 "$EXIT" "exit 2"
assert_contains "invalid skill name" "$ERR" "stderr names the charset rejection"
assert_contains "kebab-case" "$ERR" "stderr explains the expected form"

# --- Test 3: schema not found for a well-formed but unknown skill name
_flow_test_begin "schema not found → exit 2"
ERR=$("$HELPER" "no-such-skill-anywhere" '{}' 2>&1 >/dev/null)
EXIT=$?
assert_exit 2 "$EXIT" "exit 2"
assert_contains "schema not found" "$ERR" "stderr names the missing schema"

# --- Test 4: input is not valid JSON → exit 2
# Note: `CLAUDE_PLUGIN_ROOT=...` MUST be inside the `$(...)` so it scopes to
# the helper invocation. Putting it on a line preceding `ERR=$(...)` makes
# it a parallel parent-shell assignment instead of a one-shot exec-env
# (because `ERR=$(...)` is itself an assignment, not a command), and the
# helper would only find the schema via the git-rev-parse fallback — testing
# the wrong code path.
_flow_test_begin "non-JSON input → exit 2"
ERR=$(CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" "$HELPER" "$EXISTING_SKILL" 'not json at all' 2>&1 >/dev/null)
EXIT=$?
assert_exit 2 "$EXIT" "exit 2"
assert_contains "not valid JSON" "$ERR" "stderr names the JSON parse failure"

# --- Test 5: input validates → exit 0
_flow_test_begin "valid input → exit 0"
VALID_JSON='{"acceptanceCriteria":[{"text":"User can log in successfully"}]}'
OUT=$(CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" "$HELPER" "$EXISTING_SKILL" "$VALID_JSON" 2>&1)
EXIT=$?
assert_exit 0 "$EXIT" "exit 0 on valid input"

# --- Test 6: input violates schema (missing required field) → exit 1
_flow_test_begin "missing required field → exit 1"
INVALID_JSON='{"someOtherField": "x"}'
ERR=$(CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" "$HELPER" "$EXISTING_SKILL" "$INVALID_JSON" 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1 on schema violation"
assert_contains "validation failed" "$ERR" "stderr surfaces validation failure"

# --- Test 7: input violates schema (minLength on string) → exit 1
_flow_test_begin "string under minLength → exit 1"
INVALID_JSON='{"acceptanceCriteria":[{"text":"hi"}]}'  # minLength=5
ERR=$(CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" "$HELPER" "$EXISTING_SKILL" "$INVALID_JSON" 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1 on minLength violation"
assert_contains "validation failed" "$ERR" "stderr surfaces validation failure"

# --- Test 8: PYTHONSAFEPATH=1 is exported (defense against attacker-controlled
# CWD modules from `gh pr checkout` of a hostile fork). Static check on the
# helper source — the runtime effect is implicit and hard to assert directly,
# but a future maintainer removing the line in a refactor would silently
# weaken the threat-model. The defensive sys.path filter inside the Python
# heredoc provides the Python-<3.11 fallback.
_flow_test_begin "PYTHONSAFEPATH=1 export preserved in helper source"
SOURCE=$(cat "$HELPER")
assert_contains "export PYTHONSAFEPATH=1" "$SOURCE" "PYTHONSAFEPATH=1 export is present"
assert_contains 'sys.path[:] = [p for p in sys.path if p not in ("", ".")]' "$SOURCE" "Python <3.11 sys.path filter fallback is present"
