#!/usr/bin/env bash
# Regression test for SEC-3 in the commit hook, against its current write target.
#
# SEC-3: log-commits.sh must not append through a symlink. Without that, the
# append follows the link and lands the hook's output, which carries a partially
# attacker-controlled commit subject, in any user-writable file.
#
# The breadcrumb goes to the gitignored `.decisions/auto-log/issue-N.<YYYY-MM>.md`,
# not the tracked `.decisions/issue-N.md`, so the symlink below is placed on the
# auto-log path, which is the one that receives attacker-influenced text.
#
# What this file asserts is the OUTCOME (nothing reaches the link target), and
# the outcome is enforced at two layers: the hook's own `[ -L ]` check, and
# O_NOFOLLOW inside bin/journal-append.sh. Deleting the hook-level guard alone
# leaves these assertions green, because the helper still refuses, so this file
# does not discriminate that layer. The discriminating test for the O_NOFOLLOW
# layer is plugins/flow/tests/journal-append.test.sh T5, which drives the helper
# directly and asserts exit 2. Keep both layers: the hook check is the cheap one
# that runs first, and the syscall check is the one that cannot be raced.

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LOG_COMMITS="$REPO_ROOT/plugins/flow/hooks/scripts/log-commits.sh"
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
# The tracked journal must EXIST (it is the hook's gate) and must NOT be a
# symlink — it is no longer written to at all.
printf '# Journal\n' > "$SANDBOX/.decisions/issue-99.md"

THIS_MONTH=$(date +%Y-%m)
AUTOLOG_REL=".decisions/auto-log/issue-99.$THIS_MONTH.md"
AUTOLOG="$SANDBOX/$AUTOLOG_REL"
mkdir -p "$SANDBOX/.decisions/auto-log"
TARGET="$SANDBOX/sensitive.txt"
echo "ORIGINAL_CONTENT" > "$TARGET"
ln -sf "$TARGET" "$AUTOLOG"

# Simulate hook invocation as Claude Code's PostToolUse fires it: stdin = JSON
# carrying the payload cwd.
INPUT_COMMIT="{\"cwd\":\"$SANDBOX\",\"tool_input\":{\"command\":\"git commit -m foo\"}}"
echo "$INPUT_COMMIT" | bash "$LOG_COMMITS" 2>/dev/null
RC=$?
assert "SEC-3a: log-commits.sh exits cleanly when the auto-log path is a symlink" 0 "$RC"
APPENDED=$(grep -c "auto-log" "$TARGET" 2>/dev/null) || APPENDED=0
assert "SEC-3a: log-commits.sh did NOT append through the symlink" 0 "$APPENDED"

echo ""
echo "============================================"
echo "RESULT: $PASS passed, $FAIL failed"
echo "============================================"
[ "$PASS" -eq 0 ] && exit 1
[ "$FAIL" -gt 0 ] && exit 1
exit 0
