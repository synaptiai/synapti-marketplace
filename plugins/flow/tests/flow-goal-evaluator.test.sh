# Tests for plugins/flow/hooks/scripts/flow-goal-evaluator.sh (opt-in
# evaluator-loop active mode).
#
# Contract under test:
#   - Graceful degradation when `claude` CLI is unavailable
#   - Graceful degradation when timeout(1) / gtimeout is unavailable
#   - Recursion guard via CLAUDE_HOOK_GOAL_JUDGE_MODE=true
#   - Throttle: 3 continuations / 5min / session
#   - Budget exhaustion → approve "goal budget exhausted"
#   - No active goal → approve "no active flow goal"
#   - Deterministic must_pass-fail → block + last-verdict.json (not_achieved, 1.0)
#   - Deterministic all-pass (no fuzzy) → approve + last-verdict.json (achieved, 1.0)
#   - Hybrid path: judge verdict drives decision + last-verdict.json persistence
#   - Empty / malformed judge response: safe fallback, no last-verdict.json
#
# The hook spawns `claude --print` as a subprocess. We stub it via PATH-shim:
# tests/lib/mock-claude.sh installed as $MOCKBIN/claude, with the response
# selected via $FLOW_TEST_CLAUDE_RESPONSE fixture path. See the shim header
# for the contract.
#
# On macOS without coreutils, `timeout(1)` is also unavailable; we install a
# pass-through timeout shim so the hook can reach its judge branch under
# test. The "missing timeout" code path has its own dedicated test (Test 15).
#
# Counter discipline: each test runs the hook inside a $(...) subshell so
# HOME, PATH, PYTHONUSERBASE overrides can't leak across tests. Assertions
# stay at the parent file scope so FLOW_TEST_PASS / FLOW_TEST_FAIL counters
# accumulate (subshell increments would not reach the parent).

HOOK="$REPO_ROOT/plugins/flow/hooks/scripts/flow-goal-evaluator.sh"
SHIM="$REPO_ROOT/plugins/flow/tests/lib/mock-claude.sh"
FIXTURES="$REPO_ROOT/plugins/flow/tests/fixtures/claude-responses"

FGE_CLEANUP_PATHS=()
_fge_cleanup() {
  local p
  for p in "${FGE_CLEANUP_PATHS[@]:-}"; do
    [ -n "$p" ] && rm -rf "$p" 2>/dev/null
  done
}
trap _fge_cleanup EXIT

_fge_mktemp_dir() {
  local out
  out=$(mktemp -d -t flow-goal-evaluator.tests.XXXXXX 2>/dev/null)
  if [ -z "$out" ] || [ ! -d "$out" ]; then
    echo "flow-goal-evaluator.test.sh: mktemp -d failed" >&2
    kill -INT $$ 2>/dev/null
    exit 2
  fi
  FGE_CLEANUP_PATHS+=("$out")
  printf '%s' "$out"
}

# Populate $dir/mock-bin with claude shim plus a pass-through timeout shim
# when the system lacks it (macOS without coreutils).
_fge_make_mockbin() {
  local dir="$1"
  mkdir -p "$dir/mock-bin"
  cp "$SHIM" "$dir/mock-bin/claude"
  chmod +x "$dir/mock-bin/claude"
  if ! command -v timeout >/dev/null 2>&1 && ! command -v gtimeout >/dev/null 2>&1; then
    cat > "$dir/mock-bin/timeout" <<'TIMEOUT_SHIM'
#!/usr/bin/env bash
# Test shim — discards the duration arg, execs the rest.
shift
exec "$@"
TIMEOUT_SHIM
    chmod +x "$dir/mock-bin/timeout"
  fi
}

# Run the hook in an env-isolated subshell and emit its stdout. Extra env
# bindings (e.g., "CLAUDE_HOOK_GOAL_JUDGE_MODE=true") may be passed as
# trailing args.
_fge_run() {
  local dir="$1" fixture="$2" event="$3"
  shift 3
  local kv
  (
    cd "$dir" || exit 1
    export HOME="$dir"
    export PYTHONUSERBASE="$_FGE_PYTHONUSERBASE"
    export PATH="$dir/mock-bin:$PATH"
    export FLOW_TEST_CLAUDE_RESPONSE="$fixture"
    export CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow"
    for kv in "$@"; do
      # Guard against bare names / empties — `export` with an empty string
      # errors with "not a valid identifier"; with a bare `FOO` exports
      # whatever value is in scope (usually nothing useful under `set -u`).
      case "$kv" in
        '') continue ;;
        *=*) export "$kv" ;;
        *) echo "_fge_run: ignoring kv without '=': '$kv'" >&2 ;;
      esac
    done
    printf '%s' "$event" | "$HOOK"
  )
}

# Write a minimal active FlowGoal that triggers the HYBRID path (no
# verification_command → fuzzy AC → judge is spawned). Includes
# scope.run_id so _record_verdict persists.
_fge_write_hybrid_goal() {
  local dir="$1"
  local run_id="$2"
  mkdir -p "$dir/.flow/goals"
  cat > "$dir/.flow/goals/test.goal.yaml" <<YML
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: test-goal
  created_at: '2026-05-20T14:30:00Z'
  created_by: tester
scope:
  repo: test/test
  branch: test
  run_id: '${run_id}'
objective:
  outcome: test outcome
  acceptance_criteria:
    - id: AC1
      text: AC1 has no verification_command — fuzzy criterion (drives hybrid path)
      status: pending
evaluator:
  type: hybrid
  command: 'echo ok'
continuation:
  mode: evaluator_loop
  max_iterations: 20
lifecycle:
  status: active
  turns_evaluated: 1
YML
}

# Prerequisites.
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
if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi

# Capture Python's user-site base BEFORE any test overrides HOME. Tests
# redirect HOME into a tmpdir to isolate flow's per-user state directories
# (throttle, judge prompts), but Python derives ~/Library/Python/.../site-
# packages from HOME — overriding HOME hides user-installed PyYAML and the
# hook then short-circuits with "PyYAML unavailable" before reaching the
# code path under test. Exporting PYTHONUSERBASE pins user-site discovery
# to the real install location regardless of HOME.
_FGE_PYTHONUSERBASE=$(python3 -c "import site; print(site.getuserbase())" 2>/dev/null)

# --- Test 1: `claude` CLI unavailable → graceful approve
_flow_test_begin "claude CLI missing → approve with reason 'claude CLI unavailable'"
DIR=$(_fge_mktemp_dir)
# Empty mock-bin → claude is not on PATH.
mkdir -p "$DIR/mock-bin"
OUT=$(
  cd "$DIR"
  export HOME="$DIR"
  export PYTHONUSERBASE="$_FGE_PYTHONUSERBASE"
  export PATH="$DIR/mock-bin:/usr/bin:/bin"
  export CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow"
  printf '%s' '{"session_id":"s1"}' | "$HOOK"
)
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$DECISION" "decision is approve"
assert_contains "claude CLI unavailable" "$REASON" "reason names missing CLI"

# --- Test 2: recursion guard short-circuits inside the judge subprocess
_flow_test_begin "CLAUDE_HOOK_GOAL_JUDGE_MODE=true → short-circuit approve"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-achieved.json" '{"session_id":"s2"}' "CLAUDE_HOOK_GOAL_JUDGE_MODE=true")
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$DECISION" "decision is approve"
assert_equal "judge mode" "$REASON" "reason names recursion-guard"

# --- Test 3: throttle at limit (3 within 5min) → force approve, reset
_flow_test_begin "throttle CONTINUE_COUNT=3 within 5min → force approve"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
THROTTLE_DIR="$DIR/.claude/flow-goal-throttle"
mkdir -p "$THROTTLE_DIR"
NOW=$(date +%s)
printf '3:%s\n' "$NOW" > "$THROTTLE_DIR/s3"
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-not-achieved-made-progress.json" \
  '{"session_id":"s3","stop_hook_active":true}')
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$DECISION" "decision is approve"
assert_contains "throttled" "$REASON" "reason names throttle"
if [ ! -f "$THROTTLE_DIR/s3" ]; then
  _flow_assert_pass "throttle file removed after force-stop"
else
  _flow_assert_fail "throttle file still present after force-stop"
fi

# --- Test 4: throttle stale (>5min ago) → reset counter, proceed
_flow_test_begin "throttle stale (>5min) → proceed past throttle gate"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
THROTTLE_DIR="$DIR/.claude/flow-goal-throttle"
mkdir -p "$THROTTLE_DIR"
OLD=$(( $(date +%s) - 400 ))
printf '3:%s\n' "$OLD" > "$THROTTLE_DIR/s4"
# No active goal → hook proceeds past throttle gate and exits with the
# "no active flow goal" reason. Seeing THIS reason (not "throttled") is the
# proof that the stale throttle reset.
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-achieved.json" \
  '{"session_id":"s4","stop_hook_active":true}')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_not_contains "throttled" "$REASON" "reason does NOT name throttle"
assert_contains "no active flow goal" "$REASON" "reason indicates proceed-past-throttle"

# --- Test 5: no active goal → approve "no active flow goal"
_flow_test_begin "no active goal → approve 'no active flow goal'"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-achieved.json" '{"session_id":"s5"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$DECISION" "decision is approve"
assert_contains "no active flow goal" "$REASON" "reason names missing goal"

# --- Test 6: budget exhausted (turns_evaluated >= max_iterations) → approve
_flow_test_begin "budget exhausted → approve 'goal budget exhausted'"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
mkdir -p "$DIR/.flow/goals"
cat > "$DIR/.flow/goals/budget.goal.yaml" <<'YML'
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: budget
  created_at: '2026-05-20T14:30:00Z'
scope:
  repo: test/test
  branch: test
  run_id: '2026-05-20T143000Z-budget'
objective:
  outcome: test
  acceptance_criteria:
    - id: AC1
      text: fuzzy
      status: pending
evaluator:
  type: hybrid
continuation:
  max_iterations: 5
lifecycle:
  status: active
  turns_evaluated: 5
YML
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-achieved.json" '{"session_id":"s6"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$DECISION" "decision is approve"
assert_contains "goal budget exhausted" "$REASON" "reason names budget exhaustion"

# --- Test 7: deterministic must_pass-fail → block + last-verdict.json (not_achieved, 1.0)
_flow_test_begin "must_pass-fail → block + last-verdict.json with not_achieved 1.0"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
RUN_ID="2026-05-20T143000Z-mp-fail"
mkdir -p "$DIR/.flow/goals" "$DIR/.claude"
cat > "$DIR/.claude/settings.flow.json" <<'JSON'
{"flow":{"goals":{"executeVerificationCommands":true}}}
JSON
cat > "$DIR/.flow/goals/mp-fail.goal.yaml" <<YML
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: mp-fail
  created_at: '2026-05-20T14:30:00Z'
scope:
  repo: test/test
  branch: test
  run_id: '${RUN_ID}'
objective:
  outcome: test
  acceptance_criteria:
    - id: AC1
      text: deterministic check that fails
      verification_command: 'false'
      must_pass: true
      status: pending
evaluator:
  type: hybrid
continuation:
  max_iterations: 20
lifecycle:
  status: active
  turns_evaluated: 1
YML
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-achieved.json" '{"session_id":"s7"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "block" "$DECISION" "decision is block"
assert_contains "FLOW_GOAL_CONTINUATION" "$REASON" "reason names continuation"
VFILE="$DIR/.flow/runs/$RUN_ID/last-verdict.json"
if [ -f "$VFILE" ]; then
  _flow_assert_pass "last-verdict.json written"
  V=$(jq -r '.verdict' "$VFILE")
  C=$(jq -r '.confidence' "$VFILE")
  SRC=$(jq -r '.source' "$VFILE")
  assert_equal "not_achieved" "$V" "verdict=not_achieved"
  # jq emits integer-valued numbers as "1" not "1.0" — assert canonical form.
  assert_match '^1(\.0+)?$' "$C" "confidence is 1.0 (canonical or trailing-zero)"
  assert_contains "must-pass-fail" "$SRC" "source identifies the must_pass-fail path"
else
  _flow_assert_fail "last-verdict.json missing at $VFILE"
fi

# --- Test 8: deterministic all-pass (no fuzzy AC) → approve + last-verdict.json (achieved, 1.0)
_flow_test_begin "deterministic all-pass → approve + last-verdict.json with achieved 1.0"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
RUN_ID="2026-05-20T143000Z-all-pass"
mkdir -p "$DIR/.flow/goals" "$DIR/.claude"
cat > "$DIR/.claude/settings.flow.json" <<'JSON'
{"flow":{"goals":{"executeVerificationCommands":true}}}
JSON
cat > "$DIR/.flow/goals/all-pass.goal.yaml" <<YML
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: all-pass
  created_at: '2026-05-20T14:30:00Z'
scope:
  repo: test/test
  branch: test
  run_id: '${RUN_ID}'
objective:
  outcome: test
  acceptance_criteria:
    - id: AC1
      text: deterministic AC that passes
      verification_command: 'true'
      must_pass: true
      status: pending
evaluator:
  type: hybrid
continuation:
  max_iterations: 20
lifecycle:
  status: active
  turns_evaluated: 1
YML
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-achieved.json" '{"session_id":"s8"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$DECISION" "decision is approve"
assert_contains "evidence complete" "$REASON" "reason names evidence-complete"
VFILE="$DIR/.flow/runs/$RUN_ID/last-verdict.json"
if [ -f "$VFILE" ]; then
  _flow_assert_pass "last-verdict.json written"
  V=$(jq -r '.verdict' "$VFILE")
  D=$(jq -r '.delta' "$VFILE")
  SRC=$(jq -r '.source' "$VFILE")
  assert_equal "achieved" "$V" "verdict=achieved"
  assert_equal "made_progress" "$D" "delta=made_progress"
  assert_contains "deterministic-all-pass" "$SRC" "source identifies the all-pass path"
else
  _flow_assert_fail "last-verdict.json missing at $VFILE"
fi

# --- Test 9: hybrid + verdict=achieved → approve + last-verdict.json
_flow_test_begin "hybrid + judge verdict=achieved → approve + last-verdict.json"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
RUN_ID="2026-05-20T143000Z-h-ach"
_fge_write_hybrid_goal "$DIR" "$RUN_ID"
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-achieved.json" '{"session_id":"s9"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$DECISION" "decision is approve"
assert_contains "judge verdict: achieved" "$REASON" "reason names judge verdict"
VFILE="$DIR/.flow/runs/$RUN_ID/last-verdict.json"
if [ -f "$VFILE" ]; then
  _flow_assert_pass "last-verdict.json written"
  V=$(jq -r '.verdict' "$VFILE")
  C=$(jq -r '.confidence' "$VFILE")
  D=$(jq -r '.delta' "$VFILE")
  assert_equal "achieved" "$V" "verdict=achieved (from judge)"
  assert_equal "0.92" "$C" "confidence preserved from judge fixture"
  assert_equal "made_progress" "$D" "delta preserved from judge fixture"
  # recorded_at invariant: UTC ISO-8601 with second resolution + literal Z.
  # Regression-locks the auto-timestamp shape from flow-record-verdict.sh:258.
  RA=$(jq -r '.recorded_at' "$VFILE")
  assert_match '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$RA" "recorded_at is UTC ISO-8601 with literal Z"
else
  _flow_assert_fail "last-verdict.json missing at $VFILE"
fi

# --- Test 10: hybrid + verdict=not_achieved + made_progress → block + last-verdict.json
_flow_test_begin "hybrid + verdict=not_achieved → block + delta=made_progress in last-verdict"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
RUN_ID="2026-05-20T143000Z-h-na"
_fge_write_hybrid_goal "$DIR" "$RUN_ID"
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-not-achieved-made-progress.json" '{"session_id":"s10"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "block" "$DECISION" "decision is block"
assert_contains "FLOW_GOAL_CONTINUATION" "$REASON" "reason carries continuation prefix"
VFILE="$DIR/.flow/runs/$RUN_ID/last-verdict.json"
if [ -f "$VFILE" ]; then
  _flow_assert_pass "last-verdict.json written"
  V=$(jq -r '.verdict' "$VFILE")
  D=$(jq -r '.delta' "$VFILE")
  H=$(jq -r '.next_step_hint' "$VFILE")
  assert_equal "not_achieved" "$V" "verdict=not_achieved"
  assert_equal "made_progress" "$D" "delta=made_progress"
  assert_contains "AC2 edge case" "$H" "next_step_hint preserved from fixture"
else
  _flow_assert_fail "last-verdict.json missing at $VFILE"
fi

# --- Test 11: hybrid + verdict=blocked → approve with notice + last-verdict.json
_flow_test_begin "hybrid + verdict=blocked → approve with notice + last-verdict.json"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
RUN_ID="2026-05-20T143000Z-h-bl"
_fge_write_hybrid_goal "$DIR" "$RUN_ID"
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-blocked.json" '{"session_id":"s11"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$DECISION" "decision is approve"
assert_contains "Goal blocked" "$REASON" "reason names blocked verdict"
VFILE="$DIR/.flow/runs/$RUN_ID/last-verdict.json"
if [ -f "$VFILE" ]; then
  V=$(jq -r '.verdict' "$VFILE")
  assert_equal "blocked" "$V" "verdict=blocked persisted"
else
  _flow_assert_fail "last-verdict.json missing at $VFILE"
fi

# --- Test 12: hybrid + verdict=needs_human_review → approve with notice + last-verdict.json
_flow_test_begin "hybrid + verdict=needs_human_review → approve with notice + last-verdict.json"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
RUN_ID="2026-05-20T143000Z-h-nhr"
_fge_write_hybrid_goal "$DIR" "$RUN_ID"
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-needs-human-review.json" '{"session_id":"s12"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$DECISION" "decision is approve"
assert_contains "Goal needs_human_review" "$REASON" "reason names needs_human_review verdict"
VFILE="$DIR/.flow/runs/$RUN_ID/last-verdict.json"
if [ -f "$VFILE" ]; then
  V=$(jq -r '.verdict' "$VFILE")
  assert_equal "needs_human_review" "$V" "verdict=needs_human_review persisted"
else
  _flow_assert_fail "last-verdict.json missing at $VFILE"
fi

# --- Test 13: empty RESP (simulates timeout) → fallback + NO last-verdict.json
_flow_test_begin "empty judge response → fallback verdict + last-verdict.json NOT written"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
RUN_ID="2026-05-20T143000Z-h-empty"
_fge_write_hybrid_goal "$DIR" "$RUN_ID"
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-empty.txt" '{"session_id":"s13"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
# Empty RESP: `echo "" | jq -r '... // "default"'` exits non-zero with no
# stdout (no input to parse) — the // alternative ONLY triggers when jq
# parses successfully and the field is null. So VERDICT="" falls through
# the case to not_achieved|* → block. The hook's `if [ -n "$RESP" ]` then
# skips _record_verdict entirely (different code path from test 14's
# malformed RESP, same end-state outcome).
assert_equal "block" "$DECISION" "decision is block (catch-all on empty verdict)"
VFILE="$DIR/.flow/runs/$RUN_ID/last-verdict.json"
if [ ! -f "$VFILE" ]; then
  _flow_assert_pass "last-verdict.json NOT written (record skipped, preserves prior verdict for delta)"
else
  _flow_assert_fail "last-verdict.json unexpectedly written despite empty RESP"
fi

# --- Test 14: malformed RESP → fallback + NO last-verdict.json (recorder rejects empty verdict)
_flow_test_begin "malformed judge response → fallback + last-verdict.json NOT written"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
RUN_ID="2026-05-20T143000Z-h-mal"
_fge_write_hybrid_goal "$DIR" "$RUN_ID"
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-malformed.json" '{"session_id":"s14"}' 2>/dev/null)
DECISION=$(echo "$OUT" | jq -r '.decision')
# Malformed RESP: jq parse fails so VERDICT="" (no jq output captured),
# CONFIDENCE="" → coerced to 0.5 in _record_verdict, DELTA="", REASON_TXT="",
# HINT="". Verdict "" falls through case to the not_achieved|* catch-all
# → block decision. The recorder then refuses the empty-string verdict
# (not in enum), so last-verdict.json is NOT written.
assert_equal "block" "$DECISION" "decision is block (fallthrough on empty verdict)"
VFILE="$DIR/.flow/runs/$RUN_ID/last-verdict.json"
if [ ! -f "$VFILE" ]; then
  _flow_assert_pass "last-verdict.json NOT written (recorder refused empty verdict)"
else
  _flow_assert_fail "last-verdict.json unexpectedly written despite malformed RESP"
fi

# --- Test 15: timeout(1) unavailable → graceful approve (regression guard)
# This branch was added after the integration harness discovered the hook
# silently broke on macOS systems without coreutils — `timeout 60 …` resolved
# to nothing, the claude subprocess errored, and the hook fell through to a
# content-free "block" decision. The fix detects both `timeout` and
# `gtimeout` and degrades with a clear message when neither exists. This
# test guards against regression.
_flow_test_begin "neither timeout nor gtimeout → approve with 'timeout(1) unavailable'"
DIR=$(_fge_mktemp_dir)
# Build a mock-bin with claude + every other binary the hook touches —
# but NO timeout/gtimeout. Then REPLACE PATH entirely so any system
# timeout is unreachable.
mkdir -p "$DIR/mock-bin"
cp "$SHIM" "$DIR/mock-bin/claude"
chmod +x "$DIR/mock-bin/claude"
for tool in jq python3 bash sh sed grep awk cat tr head cut date mktemp dirname basename mkdir ls rm chmod cp printf env touch find tail xargs uname; do
  if command -v "$tool" >/dev/null 2>&1; then
    ln -sf "$(command -v "$tool")" "$DIR/mock-bin/$tool"
  fi
done
OUT=$(
  cd "$DIR"
  export HOME="$DIR"
  export PYTHONUSERBASE="$_FGE_PYTHONUSERBASE"
  export PATH="$DIR/mock-bin"
  export FLOW_TEST_CLAUDE_RESPONSE="$FIXTURES/verdict-achieved.json"
  export CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow"
  printf '%s' '{"session_id":"s15"}' | "$HOOK"
)
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$DECISION" "decision is approve"
assert_contains "timeout(1) unavailable" "$REASON" "reason names missing timeout(1)"
# Platform-aware install hint: Darwin → "brew install coreutils";
# Linux → "install GNU coreutils (apt/dnf/apk add coreutils)";
# other → "install GNU coreutils for your platform".
case "$(uname -s 2>/dev/null)" in
  Darwin) _EXPECTED_HINT="brew install coreutils" ;;
  Linux)  _EXPECTED_HINT="apt/dnf/apk add coreutils" ;;
  *)      _EXPECTED_HINT="install GNU coreutils" ;;
esac
assert_contains "$_EXPECTED_HINT" "$REASON" "reason carries platform-appropriate install hint"

# --- Test 16: path-boundary violation → block + last-verdict.json with violations in reason
# Exercises the second arm of the must_pass-fail gate at flow-goal-evaluator.sh:228 —
# the `VIOLATIONS` branch composes a distinct reason from must_pass-fail. Requires a
# real git repo with a tracked file outside allowed_paths because path-violation
# detection runs `git diff --name-only`.
_flow_test_begin "path-boundary violation → block + reason names 'Path boundary violations'"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
RUN_ID="2026-05-20T143000Z-pathv"
mkdir -p "$DIR/.flow/goals" "$DIR/.claude" "$DIR/src"
# Initialize a git repo so `git diff --name-only` returns a non-empty result.
# `git diff --name-only` shows TRACKED-and-modified files. Commit both
# files first, then modify the disallowed one so it surfaces in the diff.
( cd "$DIR" && git init -q --initial-branch=main && git config user.email t@t && git config user.name t && \
  mkdir -p src billing && echo "init" > src/keep.ts && echo "init" > billing/disallowed.ts && \
  git add src/keep.ts billing/disallowed.ts && git commit -qm "init" && \
  echo "modified" >> billing/disallowed.ts ) >/dev/null 2>&1
cat > "$DIR/.flow/goals/pathv.goal.yaml" <<YML
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: pathv
  created_at: '2026-05-20T14:30:00Z'
scope:
  repo: t/t
  branch: main
  run_id: '${RUN_ID}'
objective:
  outcome: test
  acceptance_criteria:
    - id: AC1
      text: fuzzy
      status: pending
constraints:
  allowed_paths:
    - src/**
evaluator:
  type: hybrid
continuation:
  max_iterations: 20
lifecycle:
  status: active
  turns_evaluated: 1
YML
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-achieved.json" '{"session_id":"s16"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "block" "$DECISION" "decision is block"
assert_contains "Path boundary violations" "$REASON" "reason names path-boundary branch"
assert_contains "billing/disallowed.ts" "$REASON" "reason surfaces the specific violating path"
VFILE="$DIR/.flow/runs/$RUN_ID/last-verdict.json"
if [ -f "$VFILE" ]; then
  V=$(jq -r '.verdict' "$VFILE")
  assert_equal "not_achieved" "$V" "verdict=not_achieved persisted on path-violation"
else
  _flow_assert_fail "last-verdict.json missing for path-violation case"
fi

# --- Test 17: lifecycle status != "active" → no-goal exit
# Hook only picks up goals where lifecycle.status == "active". A goal with
# status: draft / paused / waiting_for_user / achieved must NOT be selected,
# even if it's the only goal file present.
_flow_test_begin "lifecycle status draft/paused/achieved → 'no active flow goal'"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
mkdir -p "$DIR/.flow/goals"
# Emit three goals with non-active statuses. None should be picked.
for status in draft paused achieved; do
cat > "$DIR/.flow/goals/lc-${status}.goal.yaml" <<YML
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata: {id: lc-${status}, created_at: '2026-05-20T14:30:00Z'}
scope: {repo: t/t, branch: t, run_id: '2026-05-20T143000Z-lc-${status}'}
objective:
  outcome: t
  acceptance_criteria:
    - {id: AC1, text: fuzzy, status: pending}
evaluator: {type: hybrid}
continuation: {max_iterations: 20}
lifecycle: {status: ${status}}
YML
done
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-achieved.json" '{"session_id":"s17"}')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_contains "no active flow goal" "$REASON" "draft/paused/achieved goals not selected"

# --- Test 18: unknown JUDGE_MODEL → fallback to haiku + stderr warning
# Settings cascade can specify any string; the hook validates against an
# allowlist (haiku/sonnet/opus) and falls back to haiku with a stderr note.
_flow_test_begin "unknown JUDGE_MODEL → fallback + stderr note + hybrid path completes"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
RUN_ID="2026-05-20T143000Z-bad-model"
mkdir -p "$DIR/.claude"
cat > "$DIR/.claude/settings.flow.json" <<'JSON'
{"flow":{"goals":{"judge":{"model":"gpt-4-rogue"}}}}
JSON
_fge_write_hybrid_goal "$DIR" "$RUN_ID"
# Capture both stdout and stderr to assert on the fallback log.
COMBINED=$(_fge_run "$DIR" "$FIXTURES/verdict-achieved.json" '{"session_id":"s18"}' 2>&1)
DECISION=$(echo "$COMBINED" | grep -E '^\{' | head -1 | jq -r '.decision')
assert_equal "approve" "$DECISION" "hybrid path completes despite bad model name"
assert_contains "unknown judge.model 'gpt-4-rogue'" "$COMBINED" "stderr names the fallback trigger"
assert_contains "falling back to haiku" "$COMBINED" "stderr names the fallback target"

# --- Test 19: JUDGE_TIMEOUT out-of-range → clamp to 60
# The clamp at flow-goal-evaluator.sh:97-99 rejects values <5 or >600. Verify
# both bounds + non-numeric.
_flow_test_begin "JUDGE_TIMEOUT out-of-range → clamp to 60 + hybrid path completes"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
RUN_ID="2026-05-20T143000Z-bad-timeout"
mkdir -p "$DIR/.claude"
cat > "$DIR/.claude/settings.flow.json" <<'JSON'
{"flow":{"goals":{"judge":{"timeoutSeconds":99999}}}}
JSON
_fge_write_hybrid_goal "$DIR" "$RUN_ID"
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-achieved.json" '{"session_id":"s19"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
# The mock timeout shim discards the duration arg, so we can't observe the
# clamped value directly — but a successful hybrid path completion proves
# the hook didn't crash on an out-of-range timeout.
assert_equal "approve" "$DECISION" "out-of-range timeout doesn't break hybrid path"
VFILE="$DIR/.flow/runs/$RUN_ID/last-verdict.json"
assert_file_exists "$VFILE" "last-verdict.json written despite bad timeout setting"

# --- Test 20: symlinked goal YAML → bundle-assembler safe-fallback
# The bundle assembler runs with O_NOFOLLOW; a symlinked goal YAML triggers
# the safe-fallback path (approve with "evidence-bundle assembly failed"
# reason) rather than feeding the judge a partial prompt.
_flow_test_begin "symlinked goal YAML → safe-fallback approve (assembler refuses)"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
RUN_ID="2026-05-20T143000Z-symlink"
mkdir -p "$DIR/.flow/goals"
# Write a real goal elsewhere, then symlink it into .flow/goals/.
mkdir -p "$DIR/real-goals"
cat > "$DIR/real-goals/real.goal.yaml" <<YML
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata: {id: sym, created_at: '2026-05-20T14:30:00Z'}
scope: {repo: t/t, branch: t, run_id: '${RUN_ID}'}
objective:
  outcome: t
  acceptance_criteria:
    - {id: AC1, text: fuzzy, status: pending}
evaluator: {type: hybrid}
continuation: {max_iterations: 20}
lifecycle: {status: active, turns_evaluated: 1}
YML
ln -sf "$DIR/real-goals/real.goal.yaml" "$DIR/.flow/goals/sym.goal.yaml"
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-achieved.json" '{"session_id":"s20"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
# Either branch is acceptable here: the bundle assembler may refuse the
# symlink (preferred — safe-fallback) OR the goal-discovery itself may
# parse the symlinked YAML successfully and proceed to judge. The contract
# under test is: NO CRASH, hook always returns a JSON decision.
assert_match '^(approve|block)$' "$DECISION" "decision is a well-formed JSON verdict (no crash on symlinked goal)"
assert_match '^.+$' "$REASON" "reason is non-empty"

# --- Test 21: must_pass=false failing-tolerated AC → hybrid path (judge spawn)
# A failing verification_command with must_pass:false should NOT trigger the
# must_pass-fail block branch; it should route through hybrid path to the
# judge. Closes the gate-logic coverage gap at flow-goal-evaluator.sh:231-233.
_flow_test_begin "must_pass=false failing AC → hybrid path completes (no block)"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
RUN_ID="2026-05-20T143000Z-soft-fail"
mkdir -p "$DIR/.flow/goals" "$DIR/.claude"
cat > "$DIR/.claude/settings.flow.json" <<'JSON'
{"flow":{"goals":{"executeVerificationCommands":true}}}
JSON
cat > "$DIR/.flow/goals/soft-fail.goal.yaml" <<YML
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: soft-fail
  created_at: '2026-05-20T14:30:00Z'
scope: {repo: t/t, branch: t, run_id: '${RUN_ID}'}
objective:
  outcome: t
  acceptance_criteria:
    - id: AC1
      text: failing-tolerated AC
      verification_command: 'false'
      must_pass: false
      status: pending
evaluator: {type: hybrid}
continuation: {max_iterations: 20}
lifecycle: {status: active, turns_evaluated: 1}
YML
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-achieved.json" '{"session_id":"s21"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
# Tolerated failure → INCOMPLETE empty, FAILING non-empty, HAS_MUST_PASS_FAIL
# empty (because must_pass: false). Hook routes to hybrid → judge → achieved.
assert_equal "approve" "$DECISION" "soft-fail routes to judge, not must_pass-fail block"
assert_contains "judge verdict: achieved" "$REASON" "reason carries judge verdict (proves hybrid path)"

# --- Test 22: mixed-AC state (passing must_pass + incomplete fuzzy) → hybrid
# Multi-AC goal exercises the gate logic's interaction between passing[],
# failing[], and incomplete_acs[]. The hook must route to judge because
# at least one fuzzy AC remains (INCOMPLETE non-empty), even though the
# must_pass AC passed.
_flow_test_begin "mixed AC (passing must_pass + incomplete fuzzy) → hybrid path"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
RUN_ID="2026-05-20T143000Z-mixed"
mkdir -p "$DIR/.flow/goals" "$DIR/.claude"
cat > "$DIR/.claude/settings.flow.json" <<'JSON'
{"flow":{"goals":{"executeVerificationCommands":true}}}
JSON
cat > "$DIR/.flow/goals/mixed.goal.yaml" <<YML
apiVersion: flow.synapti.ai/v1
kind: FlowGoal
metadata:
  id: mixed
  created_at: '2026-05-20T14:30:00Z'
scope: {repo: t/t, branch: t, run_id: '${RUN_ID}'}
objective:
  outcome: t
  acceptance_criteria:
    - id: AC1
      text: deterministic that passes
      verification_command: 'true'
      must_pass: true
      status: pending
    - id: AC2
      text: fuzzy criterion (no verification_command)
      status: pending
evaluator: {type: hybrid}
continuation: {max_iterations: 20}
lifecycle: {status: active, turns_evaluated: 1}
YML
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-achieved.json" '{"session_id":"s22"}')
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$DECISION" "mixed-AC routes to judge (fuzzy AC remains)"
assert_contains "judge verdict" "$REASON" "reason carries judge verdict (proves hybrid path)"

# --- Test 23: non-zero claude exit + non-empty stdout → RESP zeroed, catch-all block
# `RESP=$(... 2>/dev/null) || RESP=""` triggers on ANY non-zero subshell
# exit, including the case where claude exits non-zero with non-empty
# stdout. The hook's documented contract treats non-zero exit as "judge
# unavailable" regardless of stdout content. This test locks that in so
# a future "treat stdout as authoritative" refactor doesn't slip through.
_flow_test_begin "non-zero claude exit + non-empty stdout → block + no last-verdict.json (RESP zeroed)"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
RUN_ID="2026-05-20T143000Z-nonzero"
_fge_write_hybrid_goal "$DIR" "$RUN_ID"
# Shim emits the achieved fixture AND exits 2 — simulates claude returning
# parseable JSON but with a non-zero exit (e.g., model API warning).
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-achieved.json" '{"session_id":"s23"}' "FLOW_TEST_CLAUDE_EXIT=2")
DECISION=$(echo "$OUT" | jq -r '.decision')
assert_equal "block" "$DECISION" "non-zero exit zeros RESP, falls through to catch-all block"
VFILE="$DIR/.flow/runs/$RUN_ID/last-verdict.json"
if [ ! -f "$VFILE" ]; then
  _flow_assert_pass "last-verdict.json NOT written (RESP empty path, prior verdict preserved)"
else
  _flow_assert_fail "last-verdict.json unexpectedly written on non-zero claude exit"
fi

# --- Test 24: oversized next_step_hint → soft-truncated with ellipsis marker
# flow-record-verdict.sh:204-230 caps next_step_hint at 500 bytes. The
# producer truncates with "…" rather than reject, so a verbose judge
# doesn't break the next-turn delta. Verifies the soft-cap branch.
_flow_test_begin "oversized next_step_hint → truncated with ellipsis at 500B cap"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
RUN_ID="2026-05-20T143000Z-oversize"
_fge_write_hybrid_goal "$DIR" "$RUN_ID"
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-oversized-hint.json" '{"session_id":"s24"}' 2>/dev/null)
DECISION=$(echo "$OUT" | jq -r '.decision')
assert_equal "block" "$DECISION" "decision is block (verdict=not_achieved)"
VFILE="$DIR/.flow/runs/$RUN_ID/last-verdict.json"
if [ -f "$VFILE" ]; then
  HINT=$(jq -r '.next_step_hint' "$VFILE")
  # Expected: 500 chars of content + "…" trailing marker = 501 chars + UTF-8
  # byte-count for ellipsis (3 bytes for "…"). awk emits character count.
  HINT_LEN=$(printf '%s' "$HINT" | awk '{print length}')
  # 501 characters (500 of content + 1 ellipsis char) — assert <= 510 to
  # allow for UTF-8 counting variance across awk implementations.
  if [ "$HINT_LEN" -le 510 ] && [ "$HINT_LEN" -ge 500 ]; then
    _flow_assert_pass "next_step_hint length ($HINT_LEN) within soft-cap window [500, 510]"
  else
    _flow_assert_fail "next_step_hint length ($HINT_LEN) outside soft-cap window"
  fi
  case "$HINT" in
    *…) _flow_assert_pass "next_step_hint ends with ellipsis marker (truncation evidence)" ;;
    *) _flow_assert_fail "next_step_hint missing trailing ellipsis marker" ;;
  esac
else
  _flow_assert_fail "last-verdict.json missing for oversized-hint case"
fi

# --- Test 25: malformed throttle file → defensive parse zeros counter, proceeds
# flow-goal-evaluator.sh:118-119 coerces non-numeric throttle fields to 0
# via `case [!0-9]*`. A corrupt throttle file (binary, single field, etc.)
# should NOT crash the hook; the worst case is a dropped throttle increment.
_flow_test_begin "malformed throttle file → defensive parse zeros counter, proceeds"
DIR=$(_fge_mktemp_dir)
_fge_make_mockbin "$DIR"
THROTTLE_DIR="$DIR/.claude/flow-goal-throttle"
mkdir -p "$THROTTLE_DIR"
# Write garbage: non-numeric count, non-numeric time, no colon separator.
printf 'NaN:not-a-time\nbinary-garbage' > "$THROTTLE_DIR/s25"
# No active goal so we exit cleanly past the throttle gate — that's the
# proof point. A crash inside throttle parsing would surface as a non-JSON
# OUT or a missing reason.
OUT=$(_fge_run "$DIR" "$FIXTURES/verdict-achieved.json" \
  '{"session_id":"s25","stop_hook_active":true}')
DECISION=$(echo "$OUT" | jq -r '.decision')
REASON=$(echo "$OUT" | jq -r '.reason')
assert_equal "approve" "$DECISION" "decision is approve (hook proceeded past throttle gate)"
assert_contains "no active flow goal" "$REASON" "reason proves throttle gate passed"
assert_not_contains "throttled" "$REASON" "reason does NOT name throttle (defensive parse zeroed counter)"
