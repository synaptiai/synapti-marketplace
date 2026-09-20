#!/usr/bin/env bash
# Regression test for SEC-3 and SEC-7 against the hooks' CURRENT write target.
#
# SEC-3: log-commits.sh and log-file-changes.sh must not append through a
# symlink. Without that, the append follows the link and lands this hook's
# output — which carries a partially attacker-controlled commit subject and file
# path — in any user-writable file.
#
# What this file asserts is the OUTCOME (nothing reaches the link target), and
# the outcome is enforced at two layers: the hooks' own `[ -L ]` check, and
# O_NOFOLLOW inside bin/journal-append.sh. Measured apart, deleting the
# hook-level guard alone leaves these 8 assertions green — the helper still
# refuses — so this file does not discriminate that layer, and it is not trying
# to. The discriminating test for the O_NOFOLLOW layer is
# plugins/flow/tests/journal-append.test.sh T5, which drives the helper directly
# and asserts exit 2. Keep both layers: the hook check is the cheap one that runs
# first, and the syscall check is the one that cannot be raced.
#
# The target moved in issue #244. The breadcrumb no longer goes to the tracked
# `.decisions/issue-N.md`; it goes to `.decisions/auto-log/issue-N.<YYYY-MM>.md`,
# which is gitignored. This test used to symlink the TRACKED journal, and after
# the move its assertions still passed while protecting nothing — proved by
# deleting both the symlink guards and the `-->` escaping from both hooks and
# watching it still report 6/6. Every path below therefore names the auto-log
# file, which is the path that actually receives attacker-influenced text now.

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

INPUT_EDIT="{\"cwd\":\"$SANDBOX\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$SANDBOX/a.txt\"}}"
echo "$INPUT_EDIT" | bash "$LOG_FILES" 2>/dev/null
RC=$?
assert "SEC-3b: log-file-changes.sh exits cleanly when the auto-log path is a symlink" 0 "$RC"
APPENDED=$(grep -c "auto-log" "$TARGET" 2>/dev/null) || APPENDED=0
assert "SEC-3b: log-file-changes.sh did NOT append through the symlink" 0 "$APPENDED"

# Sanity: target file content unchanged.
ORIG=$(cat "$TARGET")
assert "SEC-3: symlink target content unchanged" "ORIGINAL_CONTENT" "$ORIG"

# SEC-7: with the auto-log path NOT a symlink, the entry must be emitted with
# `-->` neutralized in any attacker-controlled subject. Otherwise the HTML
# comment closes early and arbitrary markdown lands in a file `/flow:explain`
# feeds back to Claude. Assert against the file that actually receives it.
command rm -f -- "$AUTOLOG"
git commit -q --allow-empty -m 'chore: payload <!-- attacker --> markdown'
echo "$INPUT_COMMIT" | bash "$LOG_COMMITS" 2>/dev/null
if [ ! -f "$AUTOLOG" ]; then
  echo "FAIL: SEC-7: no entry was written to $AUTOLOG_REL"
  FAIL=$((FAIL + 1))
else
  INJECTED=$(grep -c '<!-- attacker -->' "$AUTOLOG" 2>/dev/null) || INJECTED=0
  assert "SEC-7: log-commits.sh neutralizes attacker --> in the auto-log entry" 0 "$INJECTED"
  RAW_TERMINATOR=$(grep -c 'payload <!--' "$AUTOLOG" 2>/dev/null) || RAW_TERMINATOR=0
  assert "SEC-7: no unescaped comment opener reaches the auto-log" 0 "$RAW_TERMINATOR"
  # The tracked journal is the whole point of the relocation: never written to.
  JOURNAL_AUTOLOG=$(grep -c "auto-log" "$SANDBOX/.decisions/issue-99.md" 2>/dev/null) || JOURNAL_AUTOLOG=0
  assert "SEC-7: tracked journal carries no breadcrumb" 0 "$JOURNAL_AUTOLOG"
fi

echo ""
echo "============================================"
echo "RESULT: $PASS passed, $FAIL failed"
echo "============================================"
[ "$PASS" -eq 0 ] && exit 1
[ "$FAIL" -gt 0 ] && exit 1
exit 0
