# Tests for plugins/flow/bin/commit-journal-churn.sh.
#
# Contract (from the script header): commit trailing decision-journal churn as a
# `chore(decisions):` commit, but ONLY when every pending change is inside the
# journal dir. Non-journal changes → no-op. Lockfiles → ignored, never staged.
# The `chore(decisions):` subject is skipped by log-commits.sh Guard 1, so it
# does not trigger another auto-log append (no recursion).

HELPER="$REPO_ROOT/plugins/flow/bin/commit-journal-churn.sh"
LOGCOMMITS="$REPO_ROOT/plugins/flow/hooks/scripts/log-commits.sh"

CLEANUP_PATHS=()
_clean() { local p; for p in "${CLEANUP_PATHS[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _clean EXIT

FAKE_HOME=$(mktemp -d -t cjc.home.XXXXXX); CLEANUP_PATHS+=("$FAKE_HOME")

# Build a fresh temp repo on a feature/issue-1 branch with a baseline journal.
_new_repo() {
  local r; r=$(mktemp -d -t cjc.repo.XXXXXX); CLEANUP_PATHS+=("$r")
  git -C "$r" init -q
  git -C "$r" checkout -q -b feature/issue-1-test 2>/dev/null || git -C "$r" checkout -q -B feature/issue-1-test
  git -C "$r" config user.email "t@example.com"
  git -C "$r" config user.name "Test"
  mkdir -p "$r/.decisions"
  printf -- '---\nissue: 1\n---\n\n<!-- auto-log: seed -->\n' > "$r/.decisions/issue-1.md"
  git -C "$r" add -A
  git -C "$r" commit -q -m "init"
  printf '%s' "$r"
}

_run_helper() { ( cd "$1" && HOME="$FAKE_HOME" "$HELPER" ) 2>&1; }
_subject() { git -C "$1" log -1 --format='%s'; }
_porcelain() { git -C "$1" status --porcelain; }

# --- Scenario A: journal-only modification → committed, tree clean -----------
_flow_test_begin "journal-only churn is committed as chore(decisions):"
R=$(_new_repo)
printf '<!-- auto-log: edit 1 -->\n' >> "$R/.decisions/issue-1.md"
_run_helper "$R" >/dev/null
assert_equal "chore(decisions): record session journal entries" "$(_subject "$R")" "housekeeping commit created"
assert_equal "" "$(_porcelain "$R")" "working tree clean after commit"

# --- Scenario B: a non-journal change present → no-op -----------------------
_flow_test_begin "non-journal change present → helper no-ops"
R=$(_new_repo)
BEFORE=$(_subject "$R")
printf '<!-- auto-log: edit -->\n' >> "$R/.decisions/issue-1.md"
printf 'code\n' > "$R/src.txt"
OUT=$(_run_helper "$R")
assert_equal "$BEFORE" "$(_subject "$R")" "no new commit when non-journal dirty"
assert_contains "non-journal changes" "$OUT" "explains why it skipped"

# --- Scenario C: brand-new untracked journal file → committed ---------------
_flow_test_begin "new untracked journal .md is staged and committed"
R=$(_new_repo)
printf -- '---\nissue: 2\n---\n' > "$R/.decisions/issue-2.md"
_run_helper "$R" >/dev/null
assert_equal "chore(decisions): record session journal entries" "$(_subject "$R")" "new journal file committed"
assert_equal "" "$(_porcelain "$R")" "tree clean (issue-2.md now tracked)"

# --- Scenario D: lockfile alongside journal churn → .md committed, lock left -
_flow_test_begin "journal lockfile is never staged"
R=$(_new_repo)
printf '<!-- auto-log: edit -->\n' >> "$R/.decisions/issue-1.md"
: > "$R/.decisions/issue-1.md.lock"
_run_helper "$R" >/dev/null
assert_equal "chore(decisions): record session journal entries" "$(_subject "$R")" "journal .md committed"
# Only the untracked lock remains dirty.
assert_equal "?? .decisions/issue-1.md.lock" "$(_porcelain "$R")" "lock left untracked, not committed"

# --- Scenario E: clean tree → no-op, exit 0 ---------------------------------
_flow_test_begin "clean tree → no-op exit 0"
R=$(_new_repo)
BEFORE=$(_subject "$R")
( cd "$R" && HOME="$FAKE_HOME" "$HELPER" ); RC=$?
assert_exit 0 "$RC" "exit 0 on clean tree"
assert_equal "$BEFORE" "$(_subject "$R")" "no commit on clean tree"

# --- Recursion guard: log-commits.sh skips the chore(decisions): commit ------
_flow_test_begin "chore(decisions): commit does not trigger a re-append (Guard 1)"
R=$(_new_repo)
printf '<!-- auto-log: edit -->\n' >> "$R/.decisions/issue-1.md"
_run_helper "$R" >/dev/null
COUNT_BEFORE=$(grep -c 'auto-log' "$R/.decisions/issue-1.md")
# Simulate the PostToolUse Bash hook firing for the housekeeping commit.
printf '{"tool_input":{"command":"git commit -m x"}}' \
  | ( cd "$R" && HOME="$FAKE_HOME" bash "$LOGCOMMITS" ) >/dev/null 2>&1 || true
COUNT_AFTER=$(grep -c 'auto-log' "$R/.decisions/issue-1.md")
assert_equal "$COUNT_BEFORE" "$COUNT_AFTER" "no new auto-log line appended after chore(decisions): commit"

# --- Scenario F: wholly-untracked journal dir (fresh consumer repo) ----------
# Regression for the -uall fix: when .decisions/ was never committed,
# `git status --porcelain` collapses it to a single `?? .decisions/` entry that
# would be misread as a non-journal change. The helper must use -uall so the
# untracked journal files are seen individually and committed.
_flow_test_begin "wholly-untracked .decisions/ is committed (the fresh-consumer-repo case)"
RF=$(mktemp -d -t cjc.repo.XXXXXX); CLEANUP_PATHS+=("$RF")
git -C "$RF" init -q
git -C "$RF" checkout -q -B feature/issue-1-test
git -C "$RF" config user.email "t@example.com"
git -C "$RF" config user.name "Test"
printf 'readme\n' > "$RF/README.md"
git -C "$RF" add README.md
git -C "$RF" commit -q -m "init (no journal yet)"
mkdir -p "$RF/.decisions"
printf -- '---\nissue: 1\n---\n<!-- auto-log: x -->\n' > "$RF/.decisions/issue-1.md"
# Sanity: default porcelain would hide the per-file path (the bug condition).
assert_equal "?? .decisions/" "$(git -C "$RF" status --porcelain)" "default porcelain collapses the untracked journal dir"
_run_helper "$RF" >/dev/null
assert_equal "chore(decisions): record session journal entries" "$(_subject "$RF")" "untracked journal dir committed"
assert_equal "" "$(_porcelain "$RF")" "tree clean after committing untracked journal dir"
