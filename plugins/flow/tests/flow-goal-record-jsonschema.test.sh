# Tests for cycle-13 F11 — bin/flow-goal-record.sh now emits a stderr WARN
# when jsonschema is unavailable instead of silently skipping validation.
#
# Strategy: Run the helper under a PYTHONPATH-isolated subshell that fails
# the `import jsonschema` line. The Python module-level `_JSONSCHEMA_WARN_EMITTED`
# sentinel makes the warning idempotent (fires once per process).

HELPER="$REPO_ROOT/plugins/flow/bin/flow-goal-record.sh"

FJS_CLEANUP_PATHS=()
_fjs_cleanup() {
  local p
  for p in "${FJS_CLEANUP_PATHS[@]:-}"; do
    [ -n "$p" ] && rm -rf "$p" 2>/dev/null
  done
}
trap _fjs_cleanup EXIT

_fjs_mkdir() {
  local out
  out=$(mktemp -d -t flow-jsonschema-warn.tests.XXXXXX 2>/dev/null)
  [ -z "$out" ] && { echo "mktemp failed" >&2; exit 2; }
  FJS_CLEANUP_PATHS+=("$out")
  printf '%s' "$out"
}

if ! command -v python3 >/dev/null 2>&1; then
  _flow_test_begin "python3 prerequisite"
  _flow_assert_pass "SKIP: python3 not installed"
  return 0
fi
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_test_begin "PyYAML prerequisite"
  _flow_assert_pass "SKIP: PyYAML not installed"
  return 0
fi

# Construct a minimal valid goal YAML. The helper validates against the schema
# when jsonschema is available; the test verifies the WARN appears when it isn't.
_fjs_write_goal() {
  local path="$1"
  cat > "$path" <<'EOF'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: issue-jsonschema-test
  created_at: "2026-05-21T00:00:00Z"
scope:
  repo: owner/example
  branch: feature/test
objective:
  outcome: Test outcome
  acceptance_criteria:
    - id: AC1
      text: First criterion
      status: pending
evaluator:
  type: hybrid
lifecycle:
  status: draft
EOF
}

# --- Test 1: when jsonschema is unavailable, helper emits a stderr WARN
_flow_test_begin "WARN when jsonschema is missing"
DIR=$(_fjs_mkdir)
GOAL="$DIR/.flow/goals/issue-jsonschema-test.goal.yaml"
mkdir -p "$DIR/.flow/goals"
_fjs_write_goal "$GOAL"

# Stub out jsonschema: create a fake site-packages dir with a sentinel module
# that intercepts the import and raises ImportError. Easier approach: use
# PYTHONPATH to point at a directory that contains an empty jsonschema module
# whose import errors out.
#
# Cleanest portable approach: set up a PYTHONPATH that DOESN'T include the
# system jsonschema, AND export a sentinel that overrides. We can use a
# Python script that monkey-patches sys.modules before the helper imports.
# But the helper invokes python3 itself via a heredoc — we can't inject
# pre-import hooks easily.
#
# Pragmatic alternative: install jsonschema's name as a broken module via
# usercustomize.py / sitecustomize.py. Or simpler: use a sitecustomize
# located on a PYTHONPATH dir that runs at interpreter start and removes
# jsonschema from sys.modules.

CUSTOM_DIR=$(_fjs_mkdir)
cat > "$CUSTOM_DIR/sitecustomize.py" <<'PYEOF'
# Test stub — blocks `import jsonschema` so we can exercise the F11 WARN path.
import sys, importlib.abc, importlib.machinery
class _BlockJsonschema(importlib.abc.MetaPathFinder, importlib.abc.Loader):
    def find_spec(self, fullname, path, target=None):
        if fullname == "jsonschema" or fullname.startswith("jsonschema."):
            return importlib.machinery.ModuleSpec(fullname, self)
        return None
    def create_module(self, spec):
        raise ImportError(f"test stub: {spec.name} blocked")
    def exec_module(self, module):
        raise ImportError(f"test stub: {module} blocked")
sys.meta_path.insert(0, _BlockJsonschema())
PYEOF

# Cycle-14: WARN dedup uses per-day file sentinel at $TMPDIR/. Isolate TMPDIR
# so the test sentinel doesn't survive across runs (which would silently pass
# even if the WARN logic regressed). Use TMPDIR (not HOME) because HOME
# isolation also breaks Python's user-site-packages lookup and hides PyYAML.
ISOLATED_TMP=$(_fjs_mkdir)
ERR=$(cd "$DIR" && TMPDIR="$ISOLATED_TMP" PYTHONPATH="$CUSTOM_DIR" CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" \
  bash "$HELPER" --create --goal-file "$GOAL" 2>&1 >/dev/null)
# Helper may succeed (validation skipped) but MUST print the WARN.
assert_contains "jsonschema unavailable" "$ERR" "stderr surfaces the missing jsonschema"
assert_contains "WARN" "$ERR" "WARN tag visible in the message"

# --- Test 1b: Second invocation in the same isolated HOME — WARN should NOT
# re-fire (per-day sentinel dedup works).
_flow_test_begin "WARN deduped across same-day invocations (cycle-14 F11-SENTINEL)"
GOAL2="$DIR/.flow/goals/issue-jsonschema-test-second.goal.yaml"
cat > "$GOAL2" <<'EOF'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: issue-jsonschema-test-second
  created_at: "2026-05-21T00:00:00Z"
scope:
  repo: owner/example
  branch: feature/test
objective:
  outcome: Test outcome
  acceptance_criteria:
    - id: AC1
      text: First criterion
      status: pending
evaluator:
  type: hybrid
lifecycle:
  status: draft
EOF
ERR2=$(cd "$DIR" && TMPDIR="$ISOLATED_TMP" PYTHONPATH="$CUSTOM_DIR" CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" \
  bash "$HELPER" --create --goal-file "$GOAL2" 2>&1 >/dev/null)
assert_not_contains "jsonschema unavailable" "$ERR2" "WARN does NOT re-fire on same-day second invocation"

# --- Test 2: when jsonschema IS available, no WARN is emitted
_flow_test_begin "no WARN when jsonschema present"
if ! python3 -c "import jsonschema" >/dev/null 2>&1; then
  _flow_assert_pass "SKIP: jsonschema not installed on this host (cannot test the happy path)"
else
  # Use a fresh goal+dir so the previous test's state doesn't interfere.
  DIR2=$(_fjs_mkdir)
  GOAL2="$DIR2/.flow/goals/issue-jsonschema-test-2.goal.yaml"
  mkdir -p "$DIR2/.flow/goals"
  cat > "$GOAL2" <<'EOF'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: issue-jsonschema-test-2
  created_at: "2026-05-21T00:00:00Z"
scope:
  repo: owner/example
  branch: feature/test
objective:
  outcome: Test outcome
  acceptance_criteria:
    - id: AC1
      text: First criterion
      status: pending
evaluator:
  type: hybrid
lifecycle:
  status: draft
EOF
  ERR=$(cd "$DIR2" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" \
    bash "$HELPER" --create --goal-file "$GOAL2" 2>&1 >/dev/null)
  assert_not_contains "jsonschema unavailable" "$ERR" "no WARN when jsonschema present"
fi
