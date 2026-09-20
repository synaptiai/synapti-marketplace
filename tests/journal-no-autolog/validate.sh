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
#
# COMMITTED vs WORKING TREE — the two are checked separately, and only the first
# is fatal. An earlier version of this file ran a bare `git grep`, which reads
# the WORKING TREE, while its header claimed it tested committed content; the
# two disagreed and the check reported a failure that its own stated subject did
# not have. The situations they describe are genuinely different:
#
#   * Committed content is the deliverable. A breadcrumb there is in every clone
#     and every PR diff, and nothing outside this repository can put it back —
#     so it is a hard failure.
#   * A dirty working tree is a fact about the machine, not the repository. A
#     session running a pre-3.7.0 flow plugin appends to the tracked journal on
#     every edit, so a developer who has not yet updated the installed plugin
#     sees residue here no matter what this branch contains. Failing on that
#     produces a red check nobody can clear by fixing the repository, which is
#     how a real check gets trained away. It is reported, loudly, as a warning.
#
# A regression in this branch's own hooks is not lost by that split: it lands in
# the working tree first (warned here) and fails the committed assertion the
# moment it is committed, which is when it starts to matter.

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

# --- The invariant, over COMMITTED content -----------------------------------
# `git grep <rev>` reads the tree at that revision. HEAD is the branch head, so
# this is what a fresh clone of this branch receives.
EMITTERS=$(git grep -c '^<!-- auto-log: ' HEAD -- '.decisions/' 2>/dev/null | wc -l | tr -d ' ')
EMITTERS=${EMITTERS:-0}
assert "no committed journal carries an auto-log breadcrumb" "0" "$EMITTERS"

# --- Positive control --------------------------------------------------------
# issue-55.md's prose mentions must NOT be treated as breadcrumbs. If a future
# edit "cleans" these, the record of what that issue's contract said is gone,
# and this asserts they are still there.
if git grep -q 'auto-log' HEAD -- '.decisions/issue-55.md' 2>/dev/null; then
  echo "PASS: issue-55.md's prose mentions survive"
  PASS=$((PASS + 1))
else
  echo "FAIL: issue-55.md's historical prose about the token was removed"
  FAIL=$((FAIL + 1))
fi

# --- Reported, not fatal: residue in the working tree ------------------------
# Named file by file, because "11 breadcrumbs" tells a reader nothing about
# where to look or which plugin version put them there.
WORKTREE=$(git grep -l '^<!-- auto-log: ' -- '.decisions/' 2>/dev/null)
if [ -n "$WORKTREE" ]; then
  WT_FILES=$(printf '%s\n' "$WORKTREE" | wc -l | tr -d ' ')
  WT_LINES=$(git grep -h '^<!-- auto-log: ' -- '.decisions/' 2>/dev/null | wc -l | tr -d ' ')
  echo ""
  echo "WARN: the working tree has $WT_LINES breadcrumb(s) in $WT_FILES journal(s)."
  printf '%s\n' "$WORKTREE" | sed 's/^/WARN:   /'
  echo "WARN: this does not fail the check — see the header. It means a session on"
  echo "WARN: this machine is running a flow plugin older than 3.7.0, which writes"
  echo "WARN: to the tracked journal. Updating the installed plugin stops it;"
  echo "WARN: /flow:setup strips what is already there. If it persists with 3.7.0"
  echo "WARN: installed, the hooks have regressed — and committing it will fail"
  echo "WARN: the committed assertion above."
fi

echo ""
echo "============================================"
echo "RESULT: $PASS passed, $FAIL failed"
echo "============================================"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
