# Tests for plugins/flow/bin/flow-active-goal.sh (cycle 13, F1/F2/F3 foundation).
#
# Contract:
#   - Output modes: --path, --id, --status, --json, --ac-summary
#   - Exit 0: active goal found
#   - Exit 1: no active goal
#   - Exit 2: infrastructure error (missing python3/PyYAML or symlink rejected)
#   - Exit 3: degenerate state (multiple active goals)
#   - Symlink defense on .flow/goals/ AND individual goal YAMLs

HELPER="$REPO_ROOT/plugins/flow/bin/flow-active-goal.sh"

FAG_CLEANUP_PATHS=()
_fag_cleanup() {
  local p
  for p in "${FAG_CLEANUP_PATHS[@]:-}"; do
    [ -n "$p" ] && rm -rf "$p" 2>/dev/null
  done
}
trap _fag_cleanup EXIT

_fag_mkdir() {
  local out
  out=$(mktemp -d -t flow-active-goal.tests.XXXXXX 2>/dev/null)
  [ -z "$out" ] && { echo "mktemp failed" >&2; exit 2; }
  FAG_CLEANUP_PATHS+=("$out")
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

# Compose a fixture goal yaml that's syntactically valid against the schema
# (we don't run jsonschema here — only the helper's lifecycle.status check
# needs to be exercised).
_fag_write_goal() {
  local path="$1" status="$2" goal_id="$3"
  cat > "$path" <<EOF
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: ${goal_id}
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
    - id: AC2
      text: Second criterion
      status: pass
      evidence_ref: ".flow/runs/r1/evidence/ac2.yaml"
      last_result: "exit_code=0"
evaluator:
  type: hybrid
lifecycle:
  status: ${status}
EOF
}

# --- Test 1: no .flow/ → exit 1
_flow_test_begin "no .flow/ directory → exit 1"
DIR=$(_fag_mkdir)
EXIT=$(cd "$DIR" && bash "$HELPER" --status >/dev/null 2>&1; echo $?)
assert_equal "1" "$EXIT" "exit 1 when .flow/ absent"

# --- Test 2: empty .flow/goals/ → exit 1
_flow_test_begin "empty .flow/goals/ → exit 1"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
EXIT=$(cd "$DIR" && bash "$HELPER" --status >/dev/null 2>&1; echo $?)
assert_equal "1" "$EXIT" "exit 1 when no goal yamls"

# --- Test 3: one active goal → exit 0, --status prints 'active'
_flow_test_begin "single active goal — --status prints 'active'"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
_fag_write_goal "$DIR/.flow/goals/issue-42.goal.yaml" "active" "issue-42"
OUT=$(cd "$DIR" && bash "$HELPER" --status 2>/dev/null)
EXIT=$?
assert_equal "0" "$EXIT" "exit 0 with active goal"
assert_equal "active" "$OUT" "status reads 'active'"

# --- Test 4: same fixture — --id prints 'issue-42'
_flow_test_begin "single active goal — --id prints id"
OUT=$(cd "$DIR" && bash "$HELPER" --id 2>/dev/null)
assert_equal "issue-42" "$OUT" "--id reads metadata.id"

# --- Test 5: --path prints the file path
_flow_test_begin "single active goal — --path prints relative path"
OUT=$(cd "$DIR" && bash "$HELPER" --path 2>/dev/null)
assert_contains "issue-42.goal.yaml" "$OUT" "path includes the goal file basename"

# --- Test 6: --json prints valid JSON
_flow_test_begin "single active goal — --json prints valid JSON"
OUT=$(cd "$DIR" && bash "$HELPER" --json 2>/dev/null)
PARSED=$(printf '%s' "$OUT" | python3 -c "import sys, json; d = json.load(sys.stdin); print(d.get('metadata', {}).get('id', ''))" 2>/dev/null)
assert_equal "issue-42" "$PARSED" "JSON round-trips through python's json module"

# --- Test 7: --ac-summary one line per AC
_flow_test_begin "single active goal — --ac-summary lists ACs"
OUT=$(cd "$DIR" && bash "$HELPER" --ac-summary 2>/dev/null)
AC_COUNT=$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')
assert_equal "2" "$AC_COUNT" "two ACs (AC1, AC2)"
assert_contains "AC1|pending|-|-" "$OUT" "AC1 row"
assert_contains "AC2|pass|.flow/runs/r1/evidence/ac2.yaml|exit_code=0" "$OUT" "AC2 row"

# --- Test 8: terminal goal not counted as active
_flow_test_begin "achieved goal is not surfaced as active"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
_fag_write_goal "$DIR/.flow/goals/issue-1.goal.yaml" "achieved" "issue-1"
EXIT=$(cd "$DIR" && bash "$HELPER" --status >/dev/null 2>&1; echo $?)
assert_equal "1" "$EXIT" "exit 1 — only achieved goals exist"

# --- Test 9: degenerate state — 2 active goals → exit 3
_flow_test_begin "2 active goals → exit 3 (degenerate)"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
_fag_write_goal "$DIR/.flow/goals/issue-a.goal.yaml" "active" "issue-a"
_fag_write_goal "$DIR/.flow/goals/issue-b.goal.yaml" "active" "issue-b"
ERR=$(cd "$DIR" && bash "$HELPER" --status 2>&1 >/dev/null)
EXIT=$(cd "$DIR" && bash "$HELPER" --status >/dev/null 2>&1; echo $?)
assert_equal "3" "$EXIT" "exit 3 — degenerate"
assert_contains "degenerate state" "$ERR" "stderr names the degenerate state"

# --- Test 10: symlink at .flow/goals/ is refused
_flow_test_begin "symlinked .flow/goals/ → exit 2"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow"
mkdir -p "$DIR/elsewhere"
(cd "$DIR/.flow" && ln -s ../elsewhere goals)
ERR=$(cd "$DIR" && bash "$HELPER" --status 2>&1 >/dev/null)
EXIT=$(cd "$DIR" && bash "$HELPER" --status >/dev/null 2>&1; echo $?)
assert_equal "2" "$EXIT" "exit 2 — symlink rejected"
assert_contains "symlink" "$ERR" "stderr names the symlink refusal"

# --- Test 11: symlinked individual goal file is refused
_flow_test_begin "symlinked goal file → exit 2"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
_fag_write_goal "$DIR/elsewhere.yaml" "active" "issue-1"
(cd "$DIR/.flow/goals" && ln -s ../../elsewhere.yaml issue-1.goal.yaml)
ERR=$(cd "$DIR" && bash "$HELPER" --status 2>&1 >/dev/null)
EXIT=$(cd "$DIR" && bash "$HELPER" --status >/dev/null 2>&1; echo $?)
assert_equal "2" "$EXIT" "exit 2 — goal file symlink rejected"
assert_contains "symlink" "$ERR" "stderr names the goal-file symlink refusal"

# --- Test 12: malformed YAML is tolerated (skip + continue)
_flow_test_begin "malformed YAML tolerated, sibling goals discoverable"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
echo "{ this: is: not: valid: yaml }" > "$DIR/.flow/goals/broken.goal.yaml"
_fag_write_goal "$DIR/.flow/goals/issue-good.goal.yaml" "active" "issue-good"
OUT=$(cd "$DIR" && bash "$HELPER" --id 2>/dev/null)
EXIT=$?
assert_equal "0" "$EXIT" "exit 0 — sibling goal found despite malformed neighbor"
assert_equal "issue-good" "$OUT" "id reads the valid goal"

# --- Test 13: unknown mode flag → exit 2
_flow_test_begin "unknown mode flag → exit 2"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
_fag_write_goal "$DIR/.flow/goals/issue-1.goal.yaml" "active" "issue-1"
ERR=$(cd "$DIR" && bash "$HELPER" --bogus 2>&1 >/dev/null)
EXIT=$(cd "$DIR" && bash "$HELPER" --bogus >/dev/null 2>&1; echo $?)
assert_equal "2" "$EXIT" "exit 2 on unknown argument"
assert_contains "unknown argument" "$ERR" "stderr names the unknown arg"

# --- Test 14: two mode flags → exit 2
_flow_test_begin "two mode flags → exit 2"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
_fag_write_goal "$DIR/.flow/goals/issue-1.goal.yaml" "active" "issue-1"
ERR=$(cd "$DIR" && bash "$HELPER" --status --id 2>&1 >/dev/null)
EXIT=$(cd "$DIR" && bash "$HELPER" --status --id >/dev/null 2>&1; echo $?)
assert_equal "2" "$EXIT" "exit 2 — only one mode allowed"
assert_contains "only one mode flag" "$ERR" "stderr names the conflict"
