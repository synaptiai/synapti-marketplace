#!/usr/bin/env bash
# Repository-level assertion: no TRACKED decision journal carries an auto-log
# breadcrumb.
#
# This is about this repository's committed content, not about the plugin's
# behaviour, which is why it lives under tests/ rather than plugins/flow/tests/.
# The plugin-side tests prove the hooks write the gitignored trail; this proves
# the residue those hooks left behind is gone and stays gone.
#
# Scope, stated precisely: the invariant is EMITTER lines, matched by the
# `<!-- auto-log: ` line prefix. It is deliberately NOT "the token appears
# nowhere". `.decisions/issue-55.md` carries three lines of ordinary prose that
# mention the token — an acceptance criterion, a non-goal, and an interface
# contract recorded in 2026-05 — and they are correct as history. A bare-token
# grep could therefore never reach zero, and a check written that way would have
# been unmeetable rather than wrong.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FATAL: cannot cd to repo root" >&2; exit 2; }

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

if ! command -v git >/dev/null 2>&1 || ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "FATAL: not a git repository" >&2
  exit 2
fi

# --- Floor guard -------------------------------------------------------------
# A pathspec that silently matches nothing reports zero violations, which reads
# exactly like a clean result. Establish that the check reached the journals it
# claims to cover before trusting any count below.
JOURNAL_COUNT=$(git ls-files '.decisions/*.md' 2>/dev/null | wc -l | tr -d ' ')
if [ "${JOURNAL_COUNT:-0}" -ge 40 ]; then
  echo "PASS: found $JOURNAL_COUNT tracked journals"
  PASS=$((PASS + 1))
else
  echo "FAIL: only $JOURNAL_COUNT tracked journals found — the pathspec reached nothing"
  FAIL=$((FAIL + 1))
  echo ""
  echo "============================================"
  echo "RESULT: $PASS passed, $FAIL failed"
  echo "============================================"
  exit 1
fi

# --- The invariant -----------------------------------------------------------
EMITTERS=$(git grep -c '^<!-- auto-log: ' -- '.decisions/' 2>/dev/null | wc -l | tr -d ' ')
EMITTERS=${EMITTERS:-0}
assert "no tracked journal carries an auto-log breadcrumb" "0" "$EMITTERS"

# --- Positive control --------------------------------------------------------
# issue-55.md's prose mentions must NOT be treated as breadcrumbs. If a future
# edit "cleans" these, the record of what that issue's contract said is gone,
# and this asserts they are still there.
if git grep -q 'auto-log' -- '.decisions/issue-55.md' 2>/dev/null; then
  echo "PASS: issue-55.md's prose mentions survive"
  PASS=$((PASS + 1))
else
  echo "FAIL: issue-55.md's historical prose about the token was removed"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "============================================"
echo "RESULT: $PASS passed, $FAIL failed"
echo "============================================"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
