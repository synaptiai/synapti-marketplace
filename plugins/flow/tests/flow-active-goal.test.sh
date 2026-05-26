# Tests for plugins/flow/bin/flow-active-goal.sh.
#
# Contract:
#   - Output modes: --path, --id, --status, --json, --ac-summary, --verifiable-count
#   - Branch-first selection: prefer scope.branch == current branch,
#     fall back to most-recently-modified active; --branch <name> overrides detection
#   - Exit 0: active goal found
#   - Exit 1: no active goal
#   - Exit 2: infrastructure error (missing python3/PyYAML or symlink rejected)
#   - Exit 3: degenerate state (>1 active goal on the current branch)
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
  local path="$1" status="$2" goal_id="$3" branch="${4:-feature/test}"
  cat > "$path" <<EOF
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: ${goal_id}
  created_at: "2026-05-21T00:00:00Z"
scope:
  repo: owner/example
  branch: ${branch}
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

# Goal fixture with a controllable number of verification_command-carrying ACs,
# for --verifiable-count and degenerate-marker tests.
_fag_write_goal_vc() {
  local path="$1" status="$2" goal_id="$3" verifiable="$4" branch="${5:-feature/test}"
  {
    cat <<EOF
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: ${goal_id}
  created_at: "2026-05-21T00:00:00Z"
scope:
  repo: owner/example
  branch: ${branch}
objective:
  outcome: Test outcome
  acceptance_criteria:
EOF
    # AC1 always present; carries a verification_command iff verifiable >= 1.
    echo "    - id: AC1"
    echo "      text: First criterion"
    echo "      status: pending"
    [ "$verifiable" -ge 1 ] && echo "      verification_command: \"bash tests/run.sh\""
    echo "    - id: AC2"
    echo "      text: Second criterion"
    echo "      status: pending"
    [ "$verifiable" -ge 2 ] && echo "      verification_command: \"npm test\""
    cat <<EOF
evaluator:
  type: hybrid
lifecycle:
  status: ${status}
EOF
  } > "$path"
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

# --- Test 9: degenerate state — 2 active goals on the SAME (current) branch → exit 3
# Branch-first selection: degeneracy is now scoped to the current
# branch, so both fixtures share one branch and we pin the current branch via
# --branch to exercise the same-branch collision deterministically.
_flow_test_begin "2 active goals on same branch → exit 3 (degenerate)"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
_fag_write_goal "$DIR/.flow/goals/issue-a.goal.yaml" "active" "issue-a" "feature/shared"
_fag_write_goal "$DIR/.flow/goals/issue-b.goal.yaml" "active" "issue-b" "feature/shared"
ERR=$(cd "$DIR" && bash "$HELPER" --status --branch feature/shared 2>&1 >/dev/null)
EXIT=$(cd "$DIR" && bash "$HELPER" --status --branch feature/shared >/dev/null 2>&1; echo $?)
assert_equal "3" "$EXIT" "exit 3 — degenerate on the current branch"
assert_contains "degenerate state" "$ERR" "stderr names the degenerate state"
assert_contains "feature/shared" "$ERR" "stderr names the colliding branch"

# --- Test 9b: 2 active goals on DIFFERENT branches → each resolves its own (exit 0)
# Concurrent goals across branches/worktrees must
# stop tripping the degenerate-state error.
_flow_test_begin "2 active goals on different branches each resolve (exit 0)"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
_fag_write_goal "$DIR/.flow/goals/issue-a.goal.yaml" "active" "issue-a" "feature/aaa"
_fag_write_goal "$DIR/.flow/goals/issue-b.goal.yaml" "active" "issue-b" "feature/bbb"
OUT_A=$(cd "$DIR" && bash "$HELPER" --id --branch feature/aaa 2>/dev/null); EXIT_A=$?
OUT_B=$(cd "$DIR" && bash "$HELPER" --id --branch feature/bbb 2>/dev/null); EXIT_B=$?
assert_equal "0" "$EXIT_A" "branch aaa resolves (exit 0)"
assert_equal "issue-a" "$OUT_A" "branch aaa returns its own goal"
assert_equal "0" "$EXIT_B" "branch bbb resolves (exit 0)"
assert_equal "issue-b" "$OUT_B" "branch bbb returns its own goal"

# --- Test 9c: no goal owns the current branch → fall back to most-recently-modified
_flow_test_begin "no branch match → fall back to most-recently-modified active"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
_fag_write_goal "$DIR/.flow/goals/issue-old.goal.yaml" "active" "issue-old" "feature/aaa"
sleep 1
_fag_write_goal "$DIR/.flow/goals/issue-new.goal.yaml" "active" "issue-new" "feature/bbb"
OUT=$(cd "$DIR" && bash "$HELPER" --id --branch feature/unrelated 2>/dev/null); EXIT=$?
assert_equal "0" "$EXIT" "fallback resolves (exit 0)"
assert_equal "issue-new" "$OUT" "fallback returns the most-recently-modified active goal"

# --- Test 9d: --branch requires a value
_flow_test_begin "--branch without value → exit 2"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
_fag_write_goal "$DIR/.flow/goals/issue-1.goal.yaml" "active" "issue-1"
ERR=$(cd "$DIR" && bash "$HELPER" --branch 2>&1 >/dev/null)
EXIT=$(cd "$DIR" && bash "$HELPER" --branch >/dev/null 2>&1; echo $?)
assert_equal "2" "$EXIT" "exit 2 when --branch has no value"
assert_contains "--branch requires a value" "$ERR" "stderr names the missing value"

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

# --- Test 15: --verifiable-count reports total/verifiable (both ACs verifiable)
_flow_test_begin "--verifiable-count: 2 ACs, 2 verifiable → 2/2"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
_fag_write_goal_vc "$DIR/.flow/goals/issue-1.goal.yaml" "active" "issue-1" 2
OUT=$(cd "$DIR" && bash "$HELPER" --verifiable-count 2>/dev/null); EXIT=$?
assert_equal "0" "$EXIT" "exit 0 with active goal"
assert_equal "2/2" "$OUT" "2 total ACs, 2 carry verification_command"

# --- Test 16: --verifiable-count with one verifiable AC → 2/1
_flow_test_begin "--verifiable-count: 2 ACs, 1 verifiable → 2/1"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
_fag_write_goal_vc "$DIR/.flow/goals/issue-1.goal.yaml" "active" "issue-1" 1
OUT=$(cd "$DIR" && bash "$HELPER" --verifiable-count 2>/dev/null)
assert_equal "2/1" "$OUT" "1 of 2 ACs carries a verification_command"

# --- Test 17: --verifiable-count degenerate (0 verifiable) → 2/0
_flow_test_begin "--verifiable-count: 2 ACs, 0 verifiable → 2/0 (degenerate)"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
_fag_write_goal_vc "$DIR/.flow/goals/issue-1.goal.yaml" "active" "issue-1" 0
OUT=$(cd "$DIR" && bash "$HELPER" --verifiable-count 2>/dev/null)
assert_equal "2/0" "$OUT" "no AC carries a verification_command — degenerate"

# --- --allow-terminal: branch-scoped surfacing of achieved goals for the gate --
_flow_test_begin "achieved goal is hidden by default (active-only) -> exit 1"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
_fag_write_goal "$DIR/.flow/goals/issue-72.goal.yaml" "achieved" "issue-72" "feature/done"
EXIT=$(cd "$DIR" && bash "$HELPER" --status --branch feature/done >/dev/null 2>&1; echo $?)
assert_equal "1" "$EXIT" "achieved goal not surfaced without --allow-terminal (Stop hook / status semantics preserved)"

_flow_test_begin "--allow-terminal surfaces an achieved goal that owns the current branch"
OUT=$(cd "$DIR" && bash "$HELPER" --status --allow-terminal --branch feature/done 2>/dev/null); EXIT=$?
assert_equal "0" "$EXIT" "achieved goal surfaced with --allow-terminal on its own branch"
assert_equal "achieved" "$OUT" "status reads 'achieved' — the gate's achieved branch is reachable"
OUT=$(cd "$DIR" && bash "$HELPER" --id --allow-terminal --branch feature/done 2>/dev/null)
assert_equal "issue-72" "$OUT" "--id resolves the achieved goal"

_flow_test_begin "achieved goal is NOT surfaced cross-branch (no terminal mtime fallback)"
# A planted or stale achieved goal on another branch must never answer the gate
# for the current branch.
OUT=$(cd "$DIR" && bash "$HELPER" --status --allow-terminal --branch feature/other 2>/dev/null); EXIT=$?
assert_equal "1" "$EXIT" "achieved goal on a different branch is not applicable (exit 1)"

_flow_test_begin "active goal on the current branch beats an achieved goal on the same branch"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
_fag_write_goal "$DIR/.flow/goals/issue-done.goal.yaml" "achieved" "issue-done" "feature/x"
_fag_write_goal "$DIR/.flow/goals/issue-live.goal.yaml" "active" "issue-live" "feature/x"
OUT=$(cd "$DIR" && bash "$HELPER" --id --allow-terminal --branch feature/x 2>/dev/null); EXIT=$?
assert_equal "0" "$EXIT" "resolves (exit 0)"
assert_equal "issue-live" "$OUT" "active goal wins over achieved on the same branch"

_flow_test_begin "branch ownership beats lifecycle status: achieved-on-current > active-cross-branch"
# Branch ownership takes priority over status — an achieved goal owning the
# current branch must beat an active goal on a different branch.
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
_fag_write_goal "$DIR/.flow/goals/issue-other.goal.yaml" "active" "issue-other" "feature/aaa"
_fag_write_goal "$DIR/.flow/goals/issue-mine.goal.yaml" "achieved" "issue-mine" "feature/bbb"
OUT=$(cd "$DIR" && bash "$HELPER" --id --allow-terminal --branch feature/bbb 2>/dev/null); EXIT=$?
assert_equal "0" "$EXIT" "resolves (exit 0)"
assert_equal "issue-mine" "$OUT" "achieved goal on current branch beats active goal on another branch"

_flow_test_begin "achieved fallback prefers the current branch among multiple achieved"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
_fag_write_goal "$DIR/.flow/goals/issue-a.goal.yaml" "achieved" "issue-a" "feature/aaa"
_fag_write_goal "$DIR/.flow/goals/issue-b.goal.yaml" "achieved" "issue-b" "feature/bbb"
OUT=$(cd "$DIR" && bash "$HELPER" --id --allow-terminal --branch feature/bbb 2>/dev/null)
assert_equal "issue-b" "$OUT" "achieved goal on the current branch is preferred"

_flow_test_begin "multiple achieved goals on one branch do NOT trip exit 3 (history is normal)"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
_fag_write_goal "$DIR/.flow/goals/issue-1.goal.yaml" "achieved" "issue-1" "feature/x"
sleep 1
_fag_write_goal "$DIR/.flow/goals/issue-2.goal.yaml" "achieved" "issue-2" "feature/x"
OUT=$(cd "$DIR" && bash "$HELPER" --id --allow-terminal --branch feature/x 2>/dev/null); EXIT=$?
assert_equal "0" "$EXIT" "no degenerate error for multiple achieved on a branch"
assert_equal "issue-2" "$OUT" "most-recently-modified achieved goal wins"

_flow_test_begin "failed/cancelled goals are NOT surfaced even with --allow-terminal"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
_fag_write_goal "$DIR/.flow/goals/issue-x.goal.yaml" "cancelled" "issue-x" "feature/x"
EXIT=$(cd "$DIR" && bash "$HELPER" --status --allow-terminal --branch feature/x >/dev/null 2>&1; echo $?)
assert_equal "1" "$EXIT" "only 'achieved' is a gate-relevant terminal state; cancelled stays out of window"

# --- robustness: degenerate AC shapes + legacy goals ---------------------------
_flow_test_begin "--verifiable-count on a goal with zero ACs -> 0/0"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
cat > "$DIR/.flow/goals/issue-empty.goal.yaml" <<'EOF'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata: { id: issue-empty, created_at: "2026-05-21T00:00:00Z" }
scope: { repo: owner/example, branch: feature/test }
objective:
  outcome: Test outcome
  acceptance_criteria: []
evaluator: { type: hybrid }
lifecycle: { status: active }
EOF
OUT=$(cd "$DIR" && bash "$HELPER" --verifiable-count --branch feature/test 2>/dev/null); EXIT=$?
assert_equal "0" "$EXIT" "resolves (exit 0)"
assert_equal "0/0" "$OUT" "empty acceptance_criteria reports 0/0 (degenerate)"

_flow_test_begin "--verifiable-count / --ac-summary tolerate a non-list acceptance_criteria (no crash)"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
cat > "$DIR/.flow/goals/issue-bad.goal.yaml" <<'EOF'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata: { id: issue-bad, created_at: "2026-05-21T00:00:00Z" }
scope: { repo: owner/example, branch: feature/test }
objective:
  outcome: Test outcome
  acceptance_criteria: 42
evaluator: { type: hybrid }
lifecycle: { status: active }
EOF
OUT=$(cd "$DIR" && bash "$HELPER" --verifiable-count --branch feature/test 2>/dev/null); EXIT=$?
assert_equal "0" "$EXIT" "non-list acceptance_criteria does not crash --verifiable-count"
assert_equal "0/0" "$OUT" "scalar acceptance_criteria treated as zero ACs"
OUT=$(cd "$DIR" && bash "$HELPER" --ac-summary --branch feature/test 2>/dev/null); EXIT=$?
assert_equal "0" "$EXIT" "non-list acceptance_criteria does not crash --ac-summary"

_flow_test_begin "legacy goal with no scope.branch resolves via the most-recent-active fallback"
DIR=$(_fag_mkdir)
mkdir -p "$DIR/.flow/goals"
cat > "$DIR/.flow/goals/issue-legacy.goal.yaml" <<'EOF'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata: { id: issue-legacy, created_at: "2026-05-21T00:00:00Z" }
objective:
  outcome: Test outcome
  acceptance_criteria:
    - { id: AC1, text: First, status: pending }
evaluator: { type: hybrid }
lifecycle: { status: active }
EOF
OUT=$(cd "$DIR" && bash "$HELPER" --id --branch feature/anything 2>/dev/null); EXIT=$?
assert_equal "0" "$EXIT" "legacy goal (no scope.branch) still resolves via mtime fallback"
assert_equal "issue-legacy" "$OUT" "the active legacy goal is returned"
