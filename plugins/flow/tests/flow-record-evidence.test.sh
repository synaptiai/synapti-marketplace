# Tests for plugins/flow/bin/flow-record-evidence.sh.
#
# Contract:
#   - Required: --run-id, --evidence-file.
#   - Optional: --raw-output (copied alongside as <id>.txt).
#   - Writes .flow/runs/<run-id>/evidence/<id>.evidence.yaml (atomic).
#   - Validates against schemas/v1/evidence.schema.json when jsonschema present.
#   - Atomicity inherited from _journal_atomic.py.

HELPER="$REPO_ROOT/plugins/flow/bin/flow-record-evidence.sh"

FRE_CLEANUP_PATHS=()
_fre_cleanup() {
  local p
  for p in "${FRE_CLEANUP_PATHS[@]:-}"; do
    [ -n "$p" ] && rm -rf "$p" 2>/dev/null
  done
}
trap _fre_cleanup EXIT

_fre_mktemp_dir() {
  local out
  out=$(mktemp -d -t flow-record-evidence.tests.XXXXXX 2>/dev/null)
  if [ -z "$out" ] || [ ! -d "$out" ]; then
    echo "flow-record-evidence.test.sh: mktemp -d failed" >&2
    kill -INT $$ 2>/dev/null
    exit 2
  fi
  FRE_CLEANUP_PATHS+=("$out")
  printf '%s' "$out"
}

_run_helper() {
  local dir="$1"; shift
  (cd "$dir" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" "$HELPER" "$@")
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

# --- Test 1: missing required args
_flow_test_begin "missing --run-id → exit 1"
DIR=$(_fre_mktemp_dir)
ERR=$(_run_helper "$DIR" --evidence-file "$DIR/x.yaml" 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "--run-id is required" "$ERR" "stderr names missing arg"

_flow_test_begin "missing --evidence-file → exit 1"
DIR=$(_fre_mktemp_dir)
ERR=$(_run_helper "$DIR" --run-id 2026-05-20T143000Z-test 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "--evidence-file is required" "$ERR" "stderr names missing arg"

# --- Test 2: evidence YAML missing metadata.id → exit 1
_flow_test_begin "evidence without metadata.id → exit 1"
DIR=$(_fre_mktemp_dir)
EV="$DIR/no-id.yaml"
cat > "$EV" <<'YML'
apiVersion: flow.synapti.ai/v1
kind: FlowEvidence
metadata:
  created_at: '2026-05-20T14:42:00Z'
evidence:
  type: command_result
  exit_code: 0
YML
ERR=$(_run_helper "$DIR" --run-id 2026-05-20T143000Z-test --evidence-file "$EV" 2>&1 >/dev/null)
EXIT=$?
assert_exit 1 "$EXIT" "exit 1"
assert_contains "metadata.id is required" "$ERR" "stderr names missing field"

# --- Test 3: happy path — writes sidecar
_flow_test_begin "happy path: writes sidecar"
DIR=$(_fre_mktemp_dir)
EV="$DIR/happy.yaml"
cat > "$EV" <<'YML'
apiVersion: flow.synapti.ai/v1
kind: FlowEvidence
metadata:
  id: evidence_ac1_test
  goal: issue-42
  run_id: 2026-05-20T143000Z-test
  created_at: '2026-05-20T14:42:00Z'
evidence:
  type: command_result
  command: 'npm test'
  exit_code: 0
  proves:
    - AC1
  limitations:
    - 'does not test browser rendering'
YML
ERR=$(_run_helper "$DIR" --run-id 2026-05-20T143000Z-test --evidence-file "$EV" 2>&1 >/dev/null)
EXIT=$?
assert_exit 0 "$EXIT" "exit 0"
assert_file_exists "$DIR/.flow/runs/2026-05-20T143000Z-test/evidence/evidence_ac1_test.evidence.yaml" "sidecar written"

# --- Test 4: --raw-output copies the stdout capture
_flow_test_begin "--raw-output copies the stdout capture"
DIR=$(_fre_mktemp_dir)
EV="$DIR/with-raw.yaml"
cat > "$EV" <<'YML'
apiVersion: flow.synapti.ai/v1
kind: FlowEvidence
metadata:
  id: evidence_lint
  created_at: '2026-05-20T14:42:00Z'
evidence:
  type: lint_result
  exit_code: 0
YML
RAW="$DIR/stdout.txt"
printf 'All checks passed.\n' > "$RAW"
ERR=$(_run_helper "$DIR" --run-id 2026-05-20T143000Z-test --evidence-file "$EV" --raw-output "$RAW" 2>&1 >/dev/null)
EXIT=$?
assert_exit 0 "$EXIT" "exit 0"
assert_file_exists "$DIR/.flow/runs/2026-05-20T143000Z-test/evidence/evidence_lint.evidence.yaml" "sidecar written"
assert_file_exists "$DIR/.flow/runs/2026-05-20T143000Z-test/evidence/evidence_lint.txt" "raw output copied"
COPIED=$(cat "$DIR/.flow/runs/2026-05-20T143000Z-test/evidence/evidence_lint.txt")
assert_equal "All checks passed." "$COPIED" "raw output content matches"

# --- Test 5: symlink at lockfile → exit 2 (O_NOFOLLOW)
_flow_test_begin "symlink at lockfile path → exit 2 (O_NOFOLLOW)"
DIR=$(_fre_mktemp_dir)
mkdir -p "$DIR/.flow/runs/2026-05-20T143000Z-test"
TARGET_REDIRECT="$DIR/lock-redirect"
echo "untouched-lock-target" > "$TARGET_REDIRECT"
ln -s "$TARGET_REDIRECT" "$DIR/.flow/runs/2026-05-20T143000Z-test/.lock"

EV="$DIR/sym.yaml"
cat > "$EV" <<'YML'
apiVersion: flow.synapti.ai/v1
kind: FlowEvidence
metadata:
  id: evidence_lockfile_test
  created_at: '2026-05-20T14:42:00Z'
evidence:
  type: command_result
YML
ERR=$(_run_helper "$DIR" --run-id 2026-05-20T143000Z-test --evidence-file "$EV" 2>&1 >/dev/null)
EXIT=$?
assert_exit 2 "$EXIT" "exit 2"
assert_contains "symlink" "$ERR" "stderr names the symlink refusal"
assert_equal "untouched-lock-target" "$(cat "$TARGET_REDIRECT")" "redirect target preserved"

# --- Test 6: symlink at raw-output target → exit 2 (O_NOFOLLOW)
# Sidecar write succeeds, but raw-output destination pre-staged as a symlink
# must be refused — O_NOFOLLOW + O_EXCL on the destination.
_flow_test_begin "symlink at raw-output target → exit 2 (O_NOFOLLOW on dst)"
DIR=$(_fre_mktemp_dir)
mkdir -p "$DIR/.flow/runs/2026-05-20T143000Z-test/evidence"
RAW_REDIRECT="$DIR/raw-output-redirect"
echo "untouched-raw-content" > "$RAW_REDIRECT"
# Pre-stage the destination as a symlink to a redirect file.
ln -s "$RAW_REDIRECT" "$DIR/.flow/runs/2026-05-20T143000Z-test/evidence/evidence_symtest.txt"

EV="$DIR/symraw.yaml"
cat > "$EV" <<'YML'
apiVersion: flow.synapti.ai/v1
kind: FlowEvidence
metadata:
  id: evidence_symtest
  created_at: '2026-05-20T14:42:00Z'
evidence:
  type: command_result
  exit_code: 0
YML
RAW="$DIR/raw-source.txt"
printf 'real source content\n' > "$RAW"

ERR=$(_run_helper "$DIR" --run-id 2026-05-20T143000Z-test --evidence-file "$EV" --raw-output "$RAW" 2>&1 >/dev/null)
EXIT=$?
assert_exit 2 "$EXIT" "exit 2"
# Refusal can present as either ELOOP ("symlink") or EEXIST ("already exists")
# depending on platform errno precedence under O_NOFOLLOW|O_EXCL. Either form
# proves the symlink was NOT followed — what matters is the protection holds.
if echo "$ERR" | grep -qE 'symlink|already exists'; then
  _flow_assert_pass "stderr refuses raw-output write to symlinked dst"
else
  _flow_assert_fail "stderr did not signal refusal: $ERR"
fi
assert_equal "untouched-raw-content" "$(cat "$RAW_REDIRECT")" "redirect target NOT overwritten via symlink"
