#!/usr/bin/env bash
# aggregate-findings-ledger.test.sh — unit tests for plugins/flow/bin/aggregate-findings-ledger.sh
#
# Each test names the finding it would have caught (regression-of-record).

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$TESTS_DIR/../bin/aggregate-findings-ledger.sh"
LIB_DIR="$TESTS_DIR/lib"
FIXTURES="$TESTS_DIR/fixtures"

# Per-test isolated environment with mocked gh, MOCK_GH_ROUTES, and a
# scratch HOME so the trust-list cascade can be controlled per-case.
_setup_mock_gh() {
  MOCK_DIR=$(mktemp -d -t flow-mock.XXXXXX)
  ln -s "$LIB_DIR/mock-gh.sh" "$MOCK_DIR/gh"
  export PATH="$MOCK_DIR:$PATH"
  export MOCK_GH_LOG="$MOCK_DIR/gh.log"
  : > "$MOCK_GH_LOG"
  # Isolated HOME so user-tier settings don't leak in
  SCRATCH_HOME=$(mktemp -d -t flow-home.XXXXXX)
  export HOME="$SCRATCH_HOME"
  # Run from the project root so cascade-resolve.sh finds .claude/ ... at the
  # right relative paths. Set the plugin root explicitly.
  export CLAUDE_PLUGIN_ROOT="$TESTS_DIR/.."
  # cwd matters because the cascade reads .claude/settings.flow.local.json
  # and .claude/settings.flow.json from CWD. Use a scratch CWD for isolation.
  SCRATCH_CWD=$(mktemp -d -t flow-cwd.XXXXXX)
  cd "$SCRATCH_CWD"
}

_teardown_mock_gh() {
  # MOCK_DIR is removed when test exits; cwd reset happens implicitly when
  # the subshell that ran the test unwinds.
  rm -rf "$MOCK_DIR" "$SCRATCH_HOME" "$SCRATCH_CWD" 2>/dev/null
  unset MOCK_GH_LOG MOCK_GH_ROUTES CLAUDE_PLUGIN_ROOT
}

# Build a routes file from key=value pairs. Uses literal strings or glob
# patterns (mock-gh.sh does both via `[[ $a == $b ]]`).
_write_routes() {
  printf '%s\n' "$@" > "$MOCK_DIR/routes"
  export MOCK_GH_ROUTES="$MOCK_DIR/routes"
}

# ─── Test 1: F16 regression — HTML-comment marker scoping ───────────────────
_begin "F16: orphan RESOLVED:[…] in narrative IGNORED (not inside HTML comment)"
_setup_mock_gh
_write_routes \
  "api user --jq .login|0|$FIXTURES/gh-user.json" \
  "repo view --json nameWithOwner --jq .nameWithOwner|0|$FIXTURES/gh-repo.json" \
  "pr list --state open --limit 100 --json number,author,assignees|0|$FIXTURES/gh-pr-list-one.json" \
  "api --paginate repos/synaptiai/synapti-marketplace/pulls/103/reviews|0|$FIXTURES/reviews-cycle-1.json" \
  "api --paginate repos/synaptiai/synapti-marketplace/issues/103/comments|0|$FIXTURES/comments-orphan-narrative.json"
OUTPUT=$(bash "$HELPER" 2>/dev/null)
# Expected: F1 RESOLVED (in real marker), F2 in_fix_forward (orphan narrative IGNORED),
# F3 in_fix_forward (orphan narrative IGNORED). So we should see:
#   - exactly one P2|in_fix_forward row
#   - exactly one P3|in_fix_forward row
#   - no P1 rows (F1 was resolved)
assert_contains "P2|in_fix_forward" "$OUTPUT" "F2 must remain in_fix_forward (orphan RESOLVED:[F2] in narrative must be ignored)"
assert_contains "P3|in_fix_forward" "$OUTPUT" "F3 must remain in_fix_forward (orphan RESOLVED:[F3] in narrative must be ignored)"
assert_not_contains "P1|" "$OUTPUT" "F1 (P1) was resolved by the real marker, should not appear in tally"
_teardown_mock_gh

# ─── Test 2: cumulative marker semantics ────────────────────────────────────
_begin "Cumulative resolution: cycle 2 marker (RESOLVED:[F1,F2]) supersedes cycle 1"
_setup_mock_gh
_write_routes \
  "api user --jq .login|0|$FIXTURES/gh-user.json" \
  "repo view --json nameWithOwner --jq .nameWithOwner|0|$FIXTURES/gh-repo.json" \
  "pr list --state open --limit 100 --json number,author,assignees|0|$FIXTURES/gh-pr-list-one.json" \
  "api --paginate repos/synaptiai/synapti-marketplace/pulls/103/reviews|0|$FIXTURES/reviews-cycle-1.json" \
  "api --paginate repos/synaptiai/synapti-marketplace/issues/103/comments|0|$FIXTURES/comments-cumulative-cycle-2.json"
OUTPUT=$(bash "$HELPER" 2>/dev/null)
# Expected: F1 and F2 RESOLVED (last marker wins, cumulative), F3 in_fix_forward
assert_not_contains "P1|" "$OUTPUT" "F1 (P1) RESOLVED by cumulative cycle 2 marker"
assert_not_contains "P2|" "$OUTPUT" "F2 (P2) RESOLVED by cumulative cycle 2 marker"
assert_contains "P3|in_fix_forward" "$OUTPUT" "F3 (P3) remains in_fix_forward"
_teardown_mock_gh

# ─── Test 3: gh API failure → LEDGER: unavailable ────────────────────────────
_begin "C2: gh pr list failure → LEDGER: unavailable on stdout"
_setup_mock_gh
_write_routes \
  "api user --jq .login|0|$FIXTURES/gh-user.json" \
  "repo view --json nameWithOwner --jq .nameWithOwner|0|$FIXTURES/gh-repo.json" \
  "pr list --state open --limit 100 --json number,author,assignees|1|/dev/null"
OUTPUT=$(bash "$HELPER" 2>/dev/null)
assert_contains "LEDGER: unavailable" "$OUTPUT" "gh failure should produce LEDGER: unavailable"
_teardown_mock_gh

# ─── Test 4: per-PR failure → LEDGER: partial ───────────────────────────────
_begin "C2/F13: per-PR reviews fetch failure → LEDGER: partial"
_setup_mock_gh
_write_routes \
  "api user --jq .login|0|$FIXTURES/gh-user.json" \
  "repo view --json nameWithOwner --jq .nameWithOwner|0|$FIXTURES/gh-repo.json" \
  "pr list --state open --limit 100 --json number,author,assignees|0|$FIXTURES/gh-pr-list-one.json" \
  "api --paginate repos/synaptiai/synapti-marketplace/pulls/103/reviews|1|/dev/null"
OUTPUT=$(bash "$HELPER" 2>/dev/null)
WARNS=$(bash "$HELPER" 2>&1 >/dev/null)
assert_contains "LEDGER: partial" "$OUTPUT" "per-PR failure should emit LEDGER: partial on stdout"
assert_contains "LEDGER_WARN" "$WARNS" "per-PR failure should emit LEDGER_WARN on stderr"
_teardown_mock_gh

# ─── Test 5: hostile ID rejection (F7/F9) ────────────────────────────────────
_begin "F7/F9: hostile ID '*' rejected with LEDGER_WARN, valid IDs still counted"
_setup_mock_gh
_write_routes \
  "api user --jq .login|0|$FIXTURES/gh-user.json" \
  "repo view --json nameWithOwner --jq .nameWithOwner|0|$FIXTURES/gh-repo.json" \
  "pr list --state open --limit 100 --json number,author,assignees|0|$FIXTURES/gh-pr-list-one.json" \
  "api --paginate repos/synaptiai/synapti-marketplace/pulls/103/reviews|0|$FIXTURES/reviews-hostile-id.json" \
  "api --paginate repos/synaptiai/synapti-marketplace/issues/103/comments|0|$FIXTURES/comments-hostile-id.json"
WARNS=$(bash "$HELPER" 2>&1 >/dev/null)
OUTPUT=$(bash "$HELPER" 2>/dev/null)
assert_contains "LEDGER_WARN" "$WARNS" "hostile ID '*' should emit LEDGER_WARN"
assert_contains "non-conforming ID" "$WARNS" "warn message should describe the rejection"
assert_contains "P1|in_fix_forward" "$OUTPUT" "valid F1 should still tally"
_teardown_mock_gh

# ─── Test 6: bad priority skipped with LEDGER_WARN (F12) ─────────────────────
_begin "F12: malformed priority 'P9' rejected, valid finding still counted"
_setup_mock_gh
_write_routes \
  "api user --jq .login|0|$FIXTURES/gh-user.json" \
  "repo view --json nameWithOwner --jq .nameWithOwner|0|$FIXTURES/gh-repo.json" \
  "pr list --state open --limit 100 --json number,author,assignees|0|$FIXTURES/gh-pr-list-one.json" \
  "api --paginate repos/synaptiai/synapti-marketplace/pulls/103/reviews|0|$FIXTURES/reviews-bad-priority.json" \
  "api --paginate repos/synaptiai/synapti-marketplace/issues/103/comments|0|$FIXTURES/comments-hostile-id.json"
WARNS=$(bash "$HELPER" 2>&1 >/dev/null)
OUTPUT=$(bash "$HELPER" 2>/dev/null)
assert_contains "malformed priority" "$WARNS" "bad priority should emit malformed priority WARN"
assert_contains "P2|in_fix_forward" "$OUTPUT" "valid F2 (P2) should still tally"
assert_not_contains "P9|" "$OUTPUT" "P9 should not appear in tally"
_teardown_mock_gh

# ─── Test 7: untrusted author_association skipped ────────────────────────────
_begin "Trust list: NONE author_association is rejected by default"
_setup_mock_gh
_write_routes \
  "api user --jq .login|0|$FIXTURES/gh-user.json" \
  "repo view --json nameWithOwner --jq .nameWithOwner|0|$FIXTURES/gh-repo.json" \
  "pr list --state open --limit 100 --json number,author,assignees|0|$FIXTURES/gh-pr-list-one.json" \
  "api --paginate repos/synaptiai/synapti-marketplace/pulls/103/reviews|0|$FIXTURES/reviews-untrusted.json" \
  "api --paginate repos/synaptiai/synapti-marketplace/issues/103/comments|0|$FIXTURES/comments-hostile-id.json"
OUTPUT=$(bash "$HELPER" 2>/dev/null)
assert_not_contains "P1|" "$OUTPUT" "NONE author_association should be filtered out"
assert_not_contains "F99" "$OUTPUT" "F99 from untrusted review should not tally"
_teardown_mock_gh

# ─── Test 8: trust list HIGH_RISK detection ──────────────────────────────────
_begin "C19: HIGH_RISK trust value (NONE) emits LEDGER_WARN"
_setup_mock_gh
mkdir -p .claude
cp "$FIXTURES/settings-high-risk.json" .claude/settings.flow.local.json
_write_routes \
  "api user --jq .login|0|$FIXTURES/gh-user.json" \
  "repo view --json nameWithOwner --jq .nameWithOwner|0|$FIXTURES/gh-repo.json" \
  "pr list --state open --limit 100 --json number,author,assignees|0|$FIXTURES/gh-pr-list-empty.json"
WARNS=$(bash "$HELPER" 2>&1 >/dev/null)
assert_contains "high-risk values" "$WARNS" "high-risk trust value should emit LEDGER_WARN"
assert_contains "NONE" "$WARNS" "warn message should name the high-risk value"
_teardown_mock_gh

# ─── Test 9: invalid trust list shape (not an array) → skip, no crash ───────
_begin "C19: invalid trust list (string instead of array) skipped, falls through to next source"
_setup_mock_gh
mkdir -p .claude
cp "$FIXTURES/settings-invalid-trust.json" .claude/settings.flow.local.json
_write_routes \
  "api user --jq .login|0|$FIXTURES/gh-user.json" \
  "repo view --json nameWithOwner --jq .nameWithOwner|0|$FIXTURES/gh-repo.json" \
  "pr list --state open --limit 100 --json number,author,assignees|0|$FIXTURES/gh-pr-list-empty.json"
EXIT_CODE=0
bash "$HELPER" >/dev/null 2>&1 || EXIT_CODE=$?
assert_exit 0 "$EXIT_CODE" "invalid trust list should fall through silently, not error"
_teardown_mock_gh

# ─── Test 10: malformed settings JSON → WARN, skip source ───────────────────
_begin "Malformed settings JSON → LEDGER_WARN, continue cascade"
_setup_mock_gh
mkdir -p .claude
cp "$FIXTURES/settings-malformed.json" .claude/settings.flow.local.json
_write_routes \
  "api user --jq .login|0|$FIXTURES/gh-user.json" \
  "repo view --json nameWithOwner --jq .nameWithOwner|0|$FIXTURES/gh-repo.json" \
  "pr list --state open --limit 100 --json number,author,assignees|0|$FIXTURES/gh-pr-list-empty.json"
WARNS=$(bash "$HELPER" 2>&1 >/dev/null)
assert_contains "failed to parse" "$WARNS" "malformed JSON should emit parse-failed WARN"
_teardown_mock_gh

# ─── Test 11: jq missing → LEDGER: unavailable + exit 0 ─────────────────────
_begin "C6: jq missing → LEDGER: unavailable, exit 0 (graceful degrade)"
_setup_mock_gh
# Build a minimal PATH containing only essentials, with no jq anywhere.
# Symlink the binaries the helper needs into a fresh dir, then set PATH to it.
NOJQ_DIR=$(mktemp -d -t no-jq.XXXXXX)
ln -s "$LIB_DIR/mock-gh.sh" "$NOJQ_DIR/gh"
for BIN in bash cat grep sed tr cut rm mkdir ls mktemp cp printf echo head tail tee dirname basename find sort uniq; do
  REAL=$(command -v "$BIN" 2>/dev/null) || continue
  ln -s "$REAL" "$NOJQ_DIR/$BIN" 2>/dev/null || true
done
# Note: NOJQ_DIR has no `jq` symlink. The helper's `command -v jq` should now fail.
ORIG_PATH="$PATH"
export PATH="$NOJQ_DIR"
OUTPUT=$(bash "$HELPER" 2>/dev/null)
EXIT_CODE=0
bash "$HELPER" >/dev/null 2>&1 || EXIT_CODE=$?
export PATH="$ORIG_PATH"
assert_contains "jq not installed" "$OUTPUT" "missing jq should produce 'jq not installed' message"
assert_exit 0 "$EXIT_CODE" "missing jq must still exit 0 (graceful degrade)"
rm -rf "$NOJQ_DIR"
_teardown_mock_gh

# ─── Test 12: safe() sanitization via hostile finding ID ────────────────────
_begin "F4: safe() strips hostile chars from LEDGER_WARN (backticks, \$, non-printable)"
_setup_mock_gh
# Create a fixture with a hostile ID that includes backticks and $
HOSTILE_FIXTURE="$MOCK_DIR/reviews-hostile-chars.json"
cat > "$HOSTILE_FIXTURE" <<'EOF'
[{"author_association":"OWNER","body":"<!-- FLOW_REVIEW_CYCLE:1 FINDINGS:[F`rm -rf$|P1|sec|loc|new] -->"}]
EOF
_write_routes \
  "api user --jq .login|0|$FIXTURES/gh-user.json" \
  "repo view --json nameWithOwner --jq .nameWithOwner|0|$FIXTURES/gh-repo.json" \
  "pr list --state open --limit 100 --json number,author,assignees|0|$FIXTURES/gh-pr-list-one.json" \
  "api --paginate repos/synaptiai/synapti-marketplace/pulls/103/reviews|0|$HOSTILE_FIXTURE" \
  "api --paginate repos/synaptiai/synapti-marketplace/issues/103/comments|0|$FIXTURES/comments-hostile-id.json"
WARNS=$(bash "$HELPER" 2>&1 >/dev/null)
# The hostile chars `, $, \ must be stripped from the WARN message.
assert_not_contains '`' "$WARNS" "backticks must be stripped from LEDGER_WARN"
assert_not_contains '$' "$WARNS" "dollar sign must be stripped from LEDGER_WARN"
_teardown_mock_gh
