#!/usr/bin/env bash
# [flow] Commit trailing decision-journal churn as housekeeping.
#
# The decision journal (`.decisions/`, tracked) is appended to by the auto-log
# PostToolUse hooks after every edit/commit. Those appends are never staged by
# the hooks, so after normal work the journal shows dirty — and shows dirty at
# PR/merge time. This helper commits that churn as a `chore(decisions):` commit
# so the working tree is clean for PR creation.
#
# Safety: it commits ONLY when every pending change is inside the journal dir.
# If any non-journal path is dirty or staged, it no-ops (it must never sweep
# unrelated work into a housekeeping commit). The `chore(decisions):` prefix is
# matched by hooks/scripts/log-commits.sh Guard 1, so this commit does not
# trigger another auto-log append (no recursion).
#
# Usage:  commit-journal-churn.sh
# Exits:  0 always (best-effort housekeeping; never blocks the caller).

set -uo pipefail

# Not a git repo → nothing to do.
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Resolve the journal directory via the sibling cascade-resolve.sh (does not
# depend on CLAUDE_PLUGIN_ROOT — this script's own location is authoritative).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JOURNAL_DIR=".decisions"
if [ -x "$SCRIPT_DIR/cascade-resolve.sh" ]; then
  JOURNAL_DIR=$("$SCRIPT_DIR/cascade-resolve.sh" --default ".decisions" '.journal.dir // empty' 2>/dev/null)
  [ -n "$JOURNAL_DIR" ] || JOURNAL_DIR=".decisions"
fi

# `-uall` expands untracked directories to individual file paths. Without it, a
# journal dir that was never committed (the fresh-consumer-repo case this
# feature targets) collapses to a single `?? .decisions/` entry that matches
# neither glob below and is misread as a non-journal change — so the helper
# would no-op exactly when it is needed most.
DIRTY=$(git status --porcelain -uall 2>/dev/null)
[ -z "$DIRTY" ] && exit 0   # clean tree

# Classify every pending path. The journal is flat by contract (issue-N.md,
# session-DATE.md), so single-level globs suffice: `.md` inside the journal dir
# is committable churn; `.lock` inside it is transient (ignore); anything else
# disqualifies the auto-commit entirely.
HAS_JOURNAL_MD=0
HAS_OTHER=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  # Porcelain v1: "XY <path>" (or "XY <old> -> <new>" for renames). cut -c4-
  # yields the path field; a rename's " -> " never matches the journal globs
  # below, so renames fall through to HAS_OTHER and we safely no-op.
  p=$(printf '%s' "$line" | cut -c4-)
  case "$p" in
    "$JOURNAL_DIR"/*.md)   HAS_JOURNAL_MD=1 ;;
    "$JOURNAL_DIR"/*.lock) : ;;
    *)                     HAS_OTHER=1 ;;
  esac
done <<EOF
$DIRTY
EOF

if [ "$HAS_OTHER" -eq 1 ]; then
  echo "commit-journal-churn: working tree has non-journal changes — skipping auto-commit" >&2
  exit 0
fi
[ "$HAS_JOURNAL_MD" -eq 0 ] && exit 0   # only locks dirty; nothing to commit

# Stage only journal markdown. The HAS_OTHER guard above guarantees nothing
# non-journal is dirty or pre-staged, so a plain commit cannot capture unrelated
# work; the explicit pathspec on `add` keeps lockfiles out of the index.
git add -- "$JOURNAL_DIR"/*.md 2>/dev/null
if git diff --cached --quiet 2>/dev/null; then
  exit 0   # nothing actually staged (defensive)
fi
git commit -m "chore(decisions): record session journal entries" >/dev/null 2>&1 || true
exit 0
