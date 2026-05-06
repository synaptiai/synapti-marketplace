#!/usr/bin/env bash
# Regression test for SEC-3: log-commits.sh and log-file-changes.sh hooks
# must refuse to append when the journal file is a symlink. Without the
# `[ -L ]` guard, bash `>>` follows the symlink and appends auto-log lines
# (containing partially attacker-controlled commit subject / file path) to
# the symlink target — a persistence/tampering primitive against any
# user-writable file.

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LOG_COMMITS="$REPO_ROOT/plugins/flow/hooks/scripts/log-commits.sh"
LOG_FILES="$REPO_ROOT/plugins/flow/hooks/scripts/log-file-changes.sh"
SANDBOX=$(mktemp -d -t flow-hook-sec3.XXXXXX)
cleanup() { [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ] && command rm -rf -- "$SANDBOX"; }
trap cleanup EXIT

PASS=0
FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

cd "$SANDBOX"
git init -q -b main
git config user.email t@t
git config user.name t
echo "x" > a.txt
git add a.txt && git commit -qm "initial"
git checkout -q -b feature/issue-99-x
mkdir -p .decisions
TARGET="$SANDBOX/sensitive.txt"
echo "ORIGINAL_CONTENT" > "$TARGET"
ln -sf "$TARGET" "$SANDBOX/.decisions/issue-99.md"

# Simulate hook invocation as Claude Code's PostToolUse fires it: stdin = JSON.
INPUT_COMMIT='{"tool_input":{"command":"git commit -m foo"}}'
echo "$INPUT_COMMIT" | bash "$LOG_COMMITS" 2>/dev/null
RC=$?
assert "SEC-3a: log-commits.sh exit cleanly when journal is symlink" 0 "$RC"
APPENDED=$(grep -c "auto-log" "$TARGET" 2>/dev/null) || APPENDED=0
assert "SEC-3a: log-commits.sh did NOT append to symlink target" 0 "$APPENDED"

INPUT_EDIT='{"tool_name":"Edit","tool_input":{"file_path":"/some/file"}}'
echo "$INPUT_EDIT" | bash "$LOG_FILES" 2>/dev/null
RC=$?
assert "SEC-3b: log-file-changes.sh exit cleanly when journal is symlink" 0 "$RC"
APPENDED=$(grep -c "auto-log" "$TARGET" 2>/dev/null) || APPENDED=0
assert "SEC-3b: log-file-changes.sh did NOT append to symlink target" 0 "$APPENDED"

# Sanity: target file content unchanged.
ORIG=$(cat "$TARGET")
assert "SEC-3: symlink target content unchanged" "ORIGINAL_CONTENT" "$ORIG"

# SEC-7: when the journal is NOT a symlink, the auto-log must still be
# emitted but with `-->` neutralized in any attacker-controlled commit
# subject. Otherwise the comment closes early and arbitrary markdown lands
# in the journal that `/flow:explain` later feeds back to Claude.
mkdir -p .decisions
JOURNAL_OK="$SANDBOX/.decisions/issue-99.md"
command rm -f -- "$JOURNAL_OK"
touch "$JOURNAL_OK"
git commit -q --allow-empty -m 'chore: payload <!-- attacker --> markdown'
echo "$INPUT_COMMIT" | bash "$LOG_COMMITS" 2>/dev/null
INJECTED=$(grep -c '<!-- attacker -->' "$JOURNAL_OK" 2>/dev/null) || INJECTED=0
assert "SEC-7: log-commits.sh neutralizes attacker --> in commit subject" 0 "$INJECTED"

echo ""
echo "============================================"
echo "RESULT: $PASS passed, $FAIL failed"
echo "============================================"
[ "$PASS" -eq 0 ] && exit 1
[ "$FAIL" -gt 0 ] && exit 1
exit 0
