# Tests for plugins/flow/bin/flow-record-activity.sh.
#
# Contract:
#   - Required args: --run-id <id>, --activity-file <yaml-path>.
#   - Writes .flow/runs/<run-id>/activities/<NNN>-<id>.yaml (atomic).
#   - Appends one line to .flow/runs/<run-id>/events.jsonl.
#   - Validates activity YAML against schemas/v1/activity.schema.json when
#     jsonschema is available; skips validation when not.
#   - Atomicity inherited from _journal_atomic.py (O_NOFOLLOW, flock, etc.).
#   - Exit 0 on success; 1 on input error; 2 on infrastructure error.

HELPER="$REPO_ROOT/plugins/flow/bin/flow-record-activity.sh"
SCHEMA_DIR="$REPO_ROOT/plugins/flow/schemas/v1"

FRA_CLEANUP_PATHS=()
_fra_cleanup() {
  local p
  for p in "${FRA_CLEANUP_PATHS[@]:-}"; do
    [ -n "$p" ] && rm -rf "$p" 2>/dev/null
  done
}
trap _fra_cleanup EXIT

_fra_mktemp_dir() {
  local out
  out=$(mktemp -d -t flow-record-activity.tests.XXXXXX 2>/dev/null)
  if [ -z "$out" ] || [ ! -d "$out" ]; then
    echo "flow-record-activity.test.sh: mktemp -d failed" >&2
    kill -INT $$ 2>/dev/null
    exit 2
  fi
  FRA_CLEANUP_PATHS+=("$out")
  printf '%s' "$out"
}

# Run the helper from a scratch repo root so .flow/ writes land in the temp
# dir, not the real repo.
_run_helper() {
  local dir="$1"; shift
  (cd "$dir" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" "$HELPER" "$@")
}

# Skip-graceful prerequisite check.
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

# --- Test 1: missing --run-id → exit 1
_flow_test_begin "missing --run-id → exit 1"
DIR=$(_fra_mktemp_dir)
ERR=$(_run_helper "$DIR" --activity-file "$DIR/missing.yaml" 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "--run-id is required" "$ERR" "stderr names the missing arg"

# --- Test 2: missing --activity-file → exit 1
_flow_test_begin "missing --activity-file → exit 1"
DIR=$(_fra_mktemp_dir)
ERR=$(_run_helper "$DIR" --run-id 2026-05-20T143000Z-issue-42 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "--activity-file is required" "$ERR" "stderr names the missing arg"

# --- Test 3: path-traversal in --run-id → exit 1
_flow_test_begin "--run-id with '..' → exit 1 (path-traversal refusal)"
DIR=$(_fra_mktemp_dir)
ACT="$DIR/act.yaml"
cat > "$ACT" <<'YML'
apiVersion: flow.synapti.ai/v1
kind: FlowActivity
metadata:
  id: t1
  run_id: '../../etc/passwd'
activity:
  type: task
  status: passed
YML
ERR=$(_run_helper "$DIR" --run-id '../bad' --activity-file "$ACT" 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "refusing for safety" "$ERR" "stderr names the safety reason"

# --- Test 4: nonexistent --activity-file → exit 1
_flow_test_begin "nonexistent --activity-file → exit 1"
DIR=$(_fra_mktemp_dir)
ERR=$(_run_helper "$DIR" --run-id 2026-05-20T143000Z-test --activity-file "$DIR/missing.yaml" 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "does not exist" "$ERR" "stderr explains the missing file"

# --- Test 5: malformed YAML → exit 1
_flow_test_begin "malformed activity YAML → exit 1"
DIR=$(_fra_mktemp_dir)
ACT="$DIR/bad.yaml"
cat > "$ACT" <<'YML'
this is: [unclosed list
YML
ERR=$(_run_helper "$DIR" --run-id 2026-05-20T143000Z-test --activity-file "$ACT" 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "not valid YAML" "$ERR" "stderr names the parse failure"

# --- Test 6: activity missing metadata.id → exit 1
_flow_test_begin "activity without metadata.id → exit 1"
DIR=$(_fra_mktemp_dir)
ACT="$DIR/no-id.yaml"
cat > "$ACT" <<'YML'
apiVersion: flow.synapti.ai/v1
kind: FlowActivity
metadata:
  run_id: 2026-05-20T143000Z-test
activity:
  type: task
  status: passed
YML
ERR=$(_run_helper "$DIR" --run-id 2026-05-20T143000Z-test --activity-file "$ACT" 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "metadata.id is required" "$ERR" "stderr names the missing field"

# --- Test 7: happy path — writes 001-<id>.yaml and appends events.jsonl
_flow_test_begin "happy path: writes 001-<id>.yaml + events.jsonl"
DIR=$(_fra_mktemp_dir)
ACT="$DIR/happy.yaml"
cat > "$ACT" <<'YML'
apiVersion: flow.synapti.ai/v1
kind: FlowActivity
metadata:
  id: preflight_check
  run_id: 2026-05-20T143000Z-test
  workflow: start-issue
  phase: preflight
activity:
  type: bash
  name: 'Pre-flight check'
  status: passed
  started_at: '2026-05-20T14:30:00Z'
  completed_at: '2026-05-20T14:30:02Z'
outputs:
  command_exit_code: 0
YML
ERR=$(_run_helper "$DIR" --run-id 2026-05-20T143000Z-test --activity-file "$ACT" 2>&1 >/dev/null)
EXIT=$?
assert_exit 0 "$EXIT" "exit 0"
assert_file_exists "$DIR/.flow/runs/2026-05-20T143000Z-test/activities/001-preflight_check.yaml" "sequence 001 written"
assert_file_exists "$DIR/.flow/runs/2026-05-20T143000Z-test/events.jsonl" "events.jsonl created"

# --- Test 8: sequence increments — second invocation writes 002-
_flow_test_begin "sequence increments on re-invocation"
ACT2="$DIR/happy2.yaml"
cat > "$ACT2" <<'YML'
apiVersion: flow.synapti.ai/v1
kind: FlowActivity
metadata:
  id: fetch_issue
  run_id: 2026-05-20T143000Z-test
activity:
  type: bash
  status: passed
YML
_run_helper "$DIR" --run-id 2026-05-20T143000Z-test --activity-file "$ACT2" >/dev/null 2>&1
EXIT=$?
assert_exit 0 "$EXIT" "second invocation exits 0"
assert_file_exists "$DIR/.flow/runs/2026-05-20T143000Z-test/activities/002-fetch_issue.yaml" "sequence 002 written"
# events.jsonl now has two lines
LINES=$(wc -l < "$DIR/.flow/runs/2026-05-20T143000Z-test/events.jsonl" | tr -d ' ')
assert_equal "2" "$LINES" "events.jsonl has two lines after two writes"

# --- Test 9: events.jsonl entries are well-formed JSON
_flow_test_begin "events.jsonl lines parse as JSON"
# Each line must be valid JSON.
while IFS= read -r line; do
  ERR=$(printf '%s' "$line" | jq . 2>&1 >/dev/null)
  assert_exit 0 "$?" "events.jsonl line parses: $line"
done < "$DIR/.flow/runs/2026-05-20T143000Z-test/events.jsonl"

# --- Test 10: symlink at lockfile → exit 2 (O_NOFOLLOW defense inherited).
#
# This mirrors journal-record.test.sh Test 10: pre-stage a symlink at the
# lockfile path the helper will try to flock(). _journal_atomic.acquire_lock
# opens with O_NOFOLLOW; the syscall returns ELOOP/EMLINK atomically. A
# regression that demoted O_NOFOLLOW from the lockfile open would let the
# helper write through the symlink into an attacker-chosen file.
_flow_test_begin "symlink at lockfile path → exit 2 (O_NOFOLLOW)"
DIR=$(_fra_mktemp_dir)
mkdir -p "$DIR/.flow/runs/2026-05-20T143000Z-test"
TARGET_REDIRECT="$DIR/lock-redirect-target"
echo "untouched-lock-target" > "$TARGET_REDIRECT"
ln -s "$TARGET_REDIRECT" "$DIR/.flow/runs/2026-05-20T143000Z-test/.lock"

ACT="$DIR/sym.yaml"
cat > "$ACT" <<'YML'
apiVersion: flow.synapti.ai/v1
kind: FlowActivity
metadata:
  id: lockfile_symlink_test
  run_id: 2026-05-20T143000Z-test
activity:
  type: bash
  status: passed
YML
ERR=$(_run_helper "$DIR" --run-id 2026-05-20T143000Z-test --activity-file "$ACT" 2>&1 >/dev/null)
EXIT=$?
assert_exit 2 "$EXIT" "exit 2 on lockfile symlink"
assert_contains "symlink" "$ERR" "stderr names the symlink refusal"
assert_contains "lockfile" "$ERR" "stderr names which file was a symlink"
# Lockfile redirect target was NOT overwritten.
assert_equal "untouched-lock-target" "$(cat "$TARGET_REDIRECT")" "redirect target preserved"
