# Tests that bin/flow-goal-record.sh emits a stderr WARN
# when jsonschema is unavailable instead of silently skipping validation,
# and that --create records the goal in the per-user trust ledger
# (bin/flow-goal-trust.sh) without ever failing the create over the ledger.
#
# Strategy: Run the helper under a PYTHONPATH-isolated subshell that fails
# the `import jsonschema` line. The WARN is deduplicated per day through a
# sentinel file under TMPDIR, so TMPDIR is isolated per test.
#
# Every invocation sets FLOW_STATE_DIR under a temp dir so the trust ledger
# never lands in the developer's real ~/.claude/flow-state.

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
# Block `import jsonschema` by SHADOWING it on PYTHONPATH, not via
# sitecustomize.py. sitecustomize is only honoured when the interpreter's
# `site` processing picks it up, and on the macos-latest runner it did not —
# the stub never loaded, the real jsonschema imported, validation succeeded,
# and the WARN this test exists to check was never printed. The test then
# failed for a reason that had nothing to do with the code under test.
#
# A module of this name earlier on sys.path is honoured by any interpreter
# that honours PYTHONPATH at all, which is the condition the rest of the
# harness already depends on.
cat > "$CUSTOM_DIR/jsonschema.py" <<'PYEOF'
# Test stub — shadows the real jsonschema so the helper takes its WARN path.
raise ImportError("test stub: jsonschema blocked")
PYEOF

# WARN dedup uses per-day file sentinel at $TMPDIR/. Isolate TMPDIR
# so the test sentinel doesn't survive across runs (which would silently pass
# even if the WARN logic regressed). Use TMPDIR (not HOME) because HOME
# isolation also breaks Python's user-site-packages lookup and hides PyYAML.
ISOLATED_TMP=$(_fjs_mkdir)
ERR=$(cd "$DIR" && TMPDIR="$ISOLATED_TMP" PYTHONPATH="$CUSTOM_DIR" CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" FLOW_STATE_DIR="$DIR/.flow-state" \
  bash "$HELPER" --create --goal-file "$GOAL" 2>&1 >/dev/null)
# Helper may succeed (validation skipped) but MUST print the WARN.
assert_contains "jsonschema unavailable" "$ERR" "stderr surfaces the missing jsonschema"
assert_contains "WARN" "$ERR" "WARN tag visible in the message"

# --- Test 1b: Second invocation in the same isolated HOME — WARN should NOT
# re-fire (per-day sentinel dedup works).
_flow_test_begin "WARN deduped across same-day invocations"
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
ERR2=$(cd "$DIR" && TMPDIR="$ISOLATED_TMP" PYTHONPATH="$CUSTOM_DIR" CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" FLOW_STATE_DIR="$DIR/.flow-state" \
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
  ERR=$(cd "$DIR2" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" FLOW_STATE_DIR="$DIR2/.flow-state" \
    bash "$HELPER" --create --goal-file "$GOAL2" 2>&1 >/dev/null)
  assert_not_contains "jsonschema unavailable" "$ERR" "no WARN when jsonschema present"
fi

# --- Test 3: --create records the goal in the trust ledger
_flow_test_begin "--create records the goal in FLOW_STATE_DIR/goal-trust.jsonl"
DIR3=$(_fjs_mkdir)
GOAL3="$DIR3/issue-trust-record.yaml"
mkdir -p "$DIR3/.flow/goals"
cat > "$GOAL3" <<'EOF'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: issue-trust-record
  created_at: "2026-05-21T00:00:00Z"
scope:
  repo: owner/example
  branch: feature/test
objective:
  outcome: Test outcome
  acceptance_criteria:
    - id: AC1
      text: First criterion
      verification_command: 'true'
      must_pass: true
      status: pending
evaluator:
  type: deterministic
lifecycle:
  status: draft
EOF
OUT=$(cd "$DIR3" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" FLOW_STATE_DIR="$DIR3/.flow-state" CLAUDE_SESSION_ID="rec-sess" \
  bash "$HELPER" --create --goal-file "$GOAL3" 2>&1); RC=$?
assert_exit 0 "$RC" "create succeeds"
assert_file_exists "$DIR3/.flow/goals/issue-trust-record.goal.yaml" "goal written"
assert_file_exists "$DIR3/.flow-state/goal-trust.jsonl" "trust ledger created"
ENTRY=$(tail -1 "$DIR3/.flow-state/goal-trust.jsonl")
assert_equal "issue-trust-record" "$(echo "$ENTRY" | jq -r '.goal_id')" "ledger entry names the goal"
assert_equal "rec-sess" "$(echo "$ENTRY" | jq -r '.session_id')" "ledger entry carries the session id"
CHECK=$(cd "$DIR3" && FLOW_STATE_DIR="$DIR3/.flow-state" "$REPO_ROOT/plugins/flow/bin/flow-goal-trust.sh" check --goal-file .flow/goals/issue-trust-record.goal.yaml 2>/dev/null); RC=$?
assert_exit 0 "$RC" "written goal is trusted"
assert_equal "TRUSTED=yes" "$CHECK" "check prints TRUSTED=yes"
assert_not_contains "trust ledger record failed" "$OUT" "no failure note on the happy path"

# --- Test 4: a ledger failure never fails the create (note on stderr)
_flow_test_begin "--create succeeds when the trust ledger is a symlink (stderr note only)"
DIR4=$(_fjs_mkdir)
GOAL4="$DIR4/issue-trust-symlink.yaml"
mkdir -p "$DIR4/.flow/goals" "$DIR4/.flow-state"
: > "$DIR4/victim.jsonl"
ln -s "$DIR4/victim.jsonl" "$DIR4/.flow-state/goal-trust.jsonl"
sed 's/issue-trust-record/issue-trust-symlink/' "$GOAL3" > "$GOAL4"
OUT=$(cd "$DIR4" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" FLOW_STATE_DIR="$DIR4/.flow-state" \
  bash "$HELPER" --create --goal-file "$GOAL4" 2>&1); RC=$?
assert_exit 0 "$RC" "create still exits 0"
assert_file_exists "$DIR4/.flow/goals/issue-trust-symlink.goal.yaml" "goal written despite ledger failure"
assert_contains "trust ledger record failed" "$OUT" "stderr notes the ledger failure"
assert_contains "flow-goal-trust.sh record --goal-file .flow/goals/issue-trust-symlink.goal.yaml" "$OUT" "note gives the re-record command"
assert_contains "symlink" "$OUT" "note carries the underlying reason"
assert_equal "0" "$(wc -c < "$DIR4/victim.jsonl" | tr -d ' ')" "nothing written through the symlink"
