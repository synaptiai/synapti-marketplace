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
# CWD modules from `gh pr checkout` of a hostile fork). Defense-in-depth:
# the static-source checks below catch a refactor that removes the line,
# AND a runtime check below proves the defense actually works.
_flow_test_begin "PYTHONSAFEPATH=1 defense present in helper source"
SOURCE=$(cat "$HELPER")
assert_contains "export PYTHONSAFEPATH=1" "$SOURCE" "PYTHONSAFEPATH=1 export is present"
# Use a structurally lenient grep (matches `if p not in` regardless of the
# quote style or whitespace inside the comprehension) so reformatting the
# helper doesn't silently weaken the source-text check.
assert_match 'if p not in' "$SOURCE" "Python <3.11 sys.path filter fallback is present"

# --- Test 9: PYTHONSAFEPATH defense — runtime verification with a hostile
# CWD-poisoned module. Plant a `./jsonschema.py` that would exit 77 if
# imported instead of the real jsonschema package, then run the helper from
# that directory. If the defense works (PYTHONSAFEPATH=1 + sys.path filter),
# the helper imports the real jsonschema (or falls back to shape-check) and
# exits normally — never 77. The source-text check (Test 8) catches removal;
# this runtime check catches functional breakage.
_flow_test_begin "PYTHONSAFEPATH defense: hostile ./jsonschema.py is not imported"
POISON_DIR=$(mktemp -d -t vsi.poison.XXXXXX)
trap "rm -rf '$POISON_DIR'" RETURN 2>/dev/null || true
cat > "$POISON_DIR/jsonschema.py" <<'POISON'
# If this is imported instead of the real package, exit with a sentinel.
import sys
sys.exit(77)
POISON
cat > "$POISON_DIR/yaml.py" <<'POISON'
# Belt-and-suspenders: helper doesn't import yaml but we don't want to risk
# a future refactor importing it from CWD either.
import sys
sys.exit(78)
POISON
VALID_JSON='{"acceptanceCriteria":[{"text":"User can log in successfully"}]}'
# Run from inside the poisoned directory so a vulnerable Python would
# resolve `./jsonschema.py` first on sys.path.
EXIT=0
(cd "$POISON_DIR" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" "$HELPER" "$EXISTING_SKILL" "$VALID_JSON" >/dev/null 2>&1) || EXIT=$?
rm -rf "$POISON_DIR"
# Exit must NOT be 77 (real jsonschema or fallback used) or 78 (yaml.py
# bypass). Anything else means the defense held.
case "$EXIT" in
  77) _flow_assert_fail "PYTHONSAFEPATH defense breached — hostile ./jsonschema.py was imported (exit=77)" ;;
  78) _flow_assert_fail "PYTHONSAFEPATH defense breached — hostile ./yaml.py was imported (exit=78)" ;;
  *)  _flow_assert_pass "hostile CWD modules not imported (exit=$EXIT, !=77, !=78)" ;;
esac

# --- Test 10: jsonschema-fallback path coverage
# The helper falls back to an in-house shape-check when `import jsonschema`
# fails (bin/validate-skill-input.sh:112-220). In CI jsonschema IS installed
# so Tests 5/6/7 only hit the jsonschema branch. Force the fallback by
# running the helper under a shadow PATH that has `python3` but where
# jsonschema is unreachable — we shadow with PYTHONPATH=/dev/null which
# blocks all third-party imports without affecting stdlib.
_flow_test_begin "jsonschema-fallback path: shape-check produces 'fallback' NOTE"
# Force jsonschema ImportError by emptying sys.path of site-packages.
# `python3 -I` (isolated mode) disables user site-packages and PYTHONPATH;
# combined with `-S` (no `site.py`) it never finds installed jsonschema, so
# the helper falls through to its shape-checker. We can't easily inject
# `-I -S` into the helper, but we can stage a shadow PATH where the wrapped
# `python3` invokes the real interpreter with `-I -S`.
SHADOW_PY=$(mktemp -d -t vsi.shadow.XXXXXX)
trap "rm -rf '$SHADOW_PY'" RETURN 2>/dev/null || true
cat > "$SHADOW_PY/python3" <<SHADOW_EOF
#!/bin/sh
# Disable user-site and PYTHONPATH so jsonschema (always installed via pip
# or system) is not reachable. Stdlib (json, sys, re) stays reachable.
exec "$(command -v python3)" -I -S "\$@"
SHADOW_EOF
chmod +x "$SHADOW_PY/python3"
VALID_JSON='{"acceptanceCriteria":[{"text":"User can log in successfully"}]}'
# Use the shadow python by prepending to PATH. Capture stderr for the NOTE.
STDERR_TMP=$(mktemp -t vsi.fallback.se.XXXXXX)
EXIT=0
PATH="$SHADOW_PY:$PATH" CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" \
  "$HELPER" "$EXISTING_SKILL" "$VALID_JSON" >/dev/null 2>"$STDERR_TMP" || EXIT=$?
ERR=$(cat "$STDERR_TMP")
rm -f "$STDERR_TMP"; rm -rf "$SHADOW_PY"
assert_exit 0 "$EXIT" "fallback path returns 0 on valid input"
assert_contains "jsonschema package not installed" "$ERR" "fallback path emits the NOTE on stderr"
assert_contains "shape-check fallback" "$ERR" "NOTE names the fallback validator"
