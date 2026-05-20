# Tests for plugins/flow/bin/flow-record-verdict.sh.
#
# Contract:
#   - Required: --run-id, --verdict-file.
#   - Refuses: path-traversal in run-id, malformed JSON, missing required
#     keys, invalid enum values, out-of-range confidence.
#   - Writes .flow/runs/<run-id>/last-verdict.json atomically.
#   - Auto-adds recorded_at if absent.
#   - Replace semantics — second write supersedes first.
#   - Atomicity inherited from _journal_atomic.py (O_NOFOLLOW + flock).

HELPER="$REPO_ROOT/plugins/flow/bin/flow-record-verdict.sh"

FRV_CLEANUP_PATHS=()
_frv_cleanup() {
  local p
  for p in "${FRV_CLEANUP_PATHS[@]:-}"; do
    [ -n "$p" ] && rm -rf "$p" 2>/dev/null
  done
}
trap _frv_cleanup EXIT

_frv_mktemp_dir() {
  local out
  out=$(mktemp -d -t flow-record-verdict.tests.XXXXXX 2>/dev/null)
  if [ -z "$out" ] || [ ! -d "$out" ]; then
    echo "flow-record-verdict.test.sh: mktemp -d failed" >&2
    kill -INT $$ 2>/dev/null
    exit 2
  fi
  FRV_CLEANUP_PATHS+=("$out")
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

# --- Test 1: missing --run-id → exit 1
_flow_test_begin "missing --run-id → exit 1"
DIR=$(_frv_mktemp_dir)
ERR=$(_run_helper "$DIR" 2>&1 >/dev/null; echo "EXIT=$?")
EXIT=$(echo "$ERR" | grep -oE 'EXIT=[0-9]+' | cut -d= -f2)
assert_equal "1" "$EXIT" "exit 1 on missing args"

# --- Test 2: missing --verdict-file → exit 1
_flow_test_begin "missing --verdict-file → exit 1"
DIR=$(_frv_mktemp_dir)
ERR=$(_run_helper "$DIR" --run-id 2026-05-20T143000Z-test 2>&1 >/dev/null; echo "EXIT=$?")
EXIT=$(echo "$ERR" | grep -oE 'EXIT=[0-9]+' | cut -d= -f2)
assert_equal "1" "$EXIT" "exit 1"
assert_contains "verdict-file is required" "$ERR" "stderr names the missing arg"

# --- Test 3: --run-id with path traversal refused
_flow_test_begin "run-id with '..' is refused"
DIR=$(_frv_mktemp_dir)
echo '{}' > "$DIR/v.json"
ERR=$(_run_helper "$DIR" --run-id "../etc" --verdict-file "$DIR/v.json" 2>&1 >/dev/null; echo "EXIT=$?")
EXIT=$(echo "$ERR" | grep -oE 'EXIT=[0-9]+' | cut -d= -f2)
assert_equal "1" "$EXIT" "exit 1"
assert_contains "refusing for safety" "$ERR" "stderr names the path-traversal refusal"

# --- Test 4: malformed JSON → exit 1
_flow_test_begin "malformed JSON verdict file → exit 1"
DIR=$(_frv_mktemp_dir)
echo "this is not json {{{" > "$DIR/bad.json"
ERR=$(_run_helper "$DIR" --run-id 2026-05-20T143000Z-test --verdict-file "$DIR/bad.json" 2>&1 >/dev/null; echo "EXIT=$?")
EXIT=$(echo "$ERR" | grep -oE 'EXIT=[0-9]+' | cut -d= -f2)
assert_equal "1" "$EXIT" "exit 1"
assert_contains "not valid JSON" "$ERR" "stderr names the parse failure"

# --- Test 5: missing required keys → exit 1
_flow_test_begin "verdict missing required keys → exit 1 with key list"
DIR=$(_frv_mktemp_dir)
cat > "$DIR/v.json" <<'JSON'
{"verdict": "achieved"}
JSON
ERR=$(_run_helper "$DIR" --run-id 2026-05-20T143000Z-test --verdict-file "$DIR/v.json" 2>&1 >/dev/null; echo "EXIT=$?")
EXIT=$(echo "$ERR" | grep -oE 'EXIT=[0-9]+' | cut -d= -f2)
assert_equal "1" "$EXIT" "exit 1"
assert_contains "missing required keys" "$ERR" "stderr names the missing-keys refusal"
assert_contains "confidence" "$ERR" "stderr lists confidence as missing"
assert_contains "delta" "$ERR" "stderr lists delta as missing"

# --- Test 6: invalid verdict enum → exit 1
_flow_test_begin "verdict not in enum → exit 1"
DIR=$(_frv_mktemp_dir)
cat > "$DIR/v.json" <<'JSON'
{"verdict": "winning", "confidence": 0.9, "delta": "made_progress", "reason": "test"}
JSON
ERR=$(_run_helper "$DIR" --run-id 2026-05-20T143000Z-test --verdict-file "$DIR/v.json" 2>&1 >/dev/null; echo "EXIT=$?")
EXIT=$(echo "$ERR" | grep -oE 'EXIT=[0-9]+' | cut -d= -f2)
assert_equal "1" "$EXIT" "exit 1"
assert_contains "verdict must be one of" "$ERR" "stderr names the verdict-enum refusal"

# --- Test 7: confidence out of range → exit 1
_flow_test_begin "confidence > 1.0 → exit 1"
DIR=$(_frv_mktemp_dir)
cat > "$DIR/v.json" <<'JSON'
{"verdict": "achieved", "confidence": 1.5, "delta": "unchanged", "reason": "test"}
JSON
ERR=$(_run_helper "$DIR" --run-id 2026-05-20T143000Z-test --verdict-file "$DIR/v.json" 2>&1 >/dev/null; echo "EXIT=$?")
EXIT=$(echo "$ERR" | grep -oE 'EXIT=[0-9]+' | cut -d= -f2)
assert_equal "1" "$EXIT" "exit 1"
assert_contains "confidence must be a number in" "$ERR" "stderr names the range refusal"

# --- Test 8: happy path writes the file and auto-adds recorded_at
_flow_test_begin "happy path → last-verdict.json written with recorded_at"
DIR=$(_frv_mktemp_dir)
cat > "$DIR/v.json" <<'JSON'
{"verdict": "not_achieved", "confidence": 0.8, "delta": "made_progress", "reason": "AC1 still incomplete"}
JSON
ERR=$(_run_helper "$DIR" --run-id 2026-05-20T143000Z-test --verdict-file "$DIR/v.json" 2>&1 >/dev/null; echo "EXIT=$?")
EXIT=$(echo "$ERR" | grep -oE 'EXIT=[0-9]+' | cut -d= -f2)
assert_equal "0" "$EXIT" "exit 0 on happy path"
TARGET="$DIR/.flow/runs/2026-05-20T143000Z-test/last-verdict.json"
assert_file_exists "$TARGET" "last-verdict.json created"
CONTENT=$(cat "$TARGET")
assert_contains "\"verdict\": \"not_achieved\"" "$CONTENT" "verdict key present"
assert_contains "\"confidence\": 0.8" "$CONTENT" "confidence key present"
assert_contains "\"delta\": \"made_progress\"" "$CONTENT" "delta key present"
assert_contains "\"recorded_at\":" "$CONTENT" "recorded_at auto-added"

# --- Test 9: replace semantics — second write supersedes first
_flow_test_begin "second write replaces the first verdict"
DIR=$(_frv_mktemp_dir)
cat > "$DIR/v1.json" <<'JSON'
{"verdict": "not_achieved", "confidence": 0.5, "delta": "unchanged", "reason": "first"}
JSON
cat > "$DIR/v2.json" <<'JSON'
{"verdict": "achieved", "confidence": 0.95, "delta": "made_progress", "reason": "second"}
JSON
_run_helper "$DIR" --run-id 2026-05-20T143000Z-test --verdict-file "$DIR/v1.json" 2>&1 >/dev/null
_run_helper "$DIR" --run-id 2026-05-20T143000Z-test --verdict-file "$DIR/v2.json" 2>&1 >/dev/null
TARGET="$DIR/.flow/runs/2026-05-20T143000Z-test/last-verdict.json"
CONTENT=$(cat "$TARGET")
assert_contains "\"verdict\": \"achieved\"" "$CONTENT" "second verdict won (achieved)"
if echo "$CONTENT" | grep -q '"reason": "first"'; then
  _flow_assert_fail "first verdict not replaced (saw 'first' in content)"
else
  _flow_assert_pass "first verdict replaced (no 'first' in content)"
fi

# --- Test 10: symlink at target → exit 2 (O_NOFOLLOW)
_flow_test_begin "pre-staged symlink at target → exit 2"
DIR=$(_frv_mktemp_dir)
mkdir -p "$DIR/.flow/runs/2026-05-20T143000Z-test"
echo "untouched-redirect" > "$DIR/redirect"
ln -s "$DIR/redirect" "$DIR/.flow/runs/2026-05-20T143000Z-test/last-verdict.json"
cat > "$DIR/v.json" <<'JSON'
{"verdict": "achieved", "confidence": 0.9, "delta": "made_progress", "reason": "via symlink"}
JSON
ERR=$(_run_helper "$DIR" --run-id 2026-05-20T143000Z-test --verdict-file "$DIR/v.json" 2>&1 >/dev/null; echo "EXIT=$?")
EXIT=$(echo "$ERR" | grep -oE 'EXIT=[0-9]+' | cut -d= -f2)
assert_equal "2" "$EXIT" "exit 2 on symlink"
assert_contains "symlink" "$ERR" "stderr names the symlink refusal"
assert_equal "untouched-redirect" "$(cat "$DIR/redirect")" "redirect target preserved"
