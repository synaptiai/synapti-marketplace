# Tests for the PostToolUse auto-log hooks' relocation (issue #244).
#
# Contract:
#   - log-file-changes.sh (Edit|Write|NotebookEdit) and log-commits.sh (Bash)
#     write a breadcrumb to <journal.dir>/auto-log/, NEVER to the tracked
#     journal (.decisions/issue-N.md).
#   - The repo root, the branch and the journal dir are all resolved from the
#     hook payload's `cwd` — not the hook process's CWD. The payload cwd is
#     normalized with `pwd -P` first, because on macOS a mktemp -d path is
#     /var/... while `git rev-parse --show-toplevel` says /private/var/...
#   - A file whose resolved path is not under the repo root is not recorded.
#   - `agent_type` in the payload adds ` agent=<type>`; without it the entry is
#     byte-identical to the pre-change shape.
#   - Issue-scoped files rotate monthly (`issue-<N>.<YYYY-MM>.md`); the
#     branchless fallback keeps the tracked journal's daily name.
#   - Both pre-existing security fixes survive: symlinked targets are refused,
#     and `-->` / `<!--` are neutralized before embedding.
#
# The hook process here runs from $REPO_ROOT (the runner cd's there), while the
# payloads carry a temp repo's cwd. That is deliberate: it is the exact
# condition the old code got wrong, so every path assertion below is also a
# test that the payload cwd won and the process cwd lost.

HOOK_EDIT="$REPO_ROOT/plugins/flow/hooks/scripts/log-file-changes.sh"
HOOK_COMMIT="$REPO_ROOT/plugins/flow/hooks/scripts/log-commits.sh"

AR_CLEANUP_PATHS=()
_ar_cleanup() {
  local p
  for p in "${AR_CLEANUP_PATHS[@]:-}"; do
    [ -n "$p" ] && [ -e "$p" ] && rm -rf "$p" 2>/dev/null
  done
  return 0
}
trap _ar_cleanup EXIT

_ar_mktemp_dir() {
  local out
  out=$(mktemp -d -t auto-log.tests.XXXXXX 2>/dev/null)
  if [ -z "$out" ] || [ ! -d "$out" ]; then
    echo "auto-log-relocation.test.sh: mktemp -d failed" >&2
    kill -INT $$ 2>/dev/null
    exit 2
  fi
  # Resolve symlinks now: macOS mktemp -d returns /var/... but git reports
  # /private/var/..., and the tests compare paths against git output.
  out=$(cd "$out" && pwd -P)
  AR_CLEANUP_PATHS+=("$out")
  printf '%s' "$out"
}

# Build a scratch repo on an issue branch with a tracked journal present.
# $1 = branch name, $2 = issue number (or "" for a branchless session)
_ar_make_repo() {
  local branch="$1" issue="$2"
  local d
  d=$(_ar_mktemp_dir)
  (
    cd "$d" || exit 1
    git init -q .
    git config user.email "test@example.invalid"
    git config user.name "Test"
    git checkout -q -b "$branch"
    mkdir -p .decisions
    if [ -n "$issue" ]; then
      printf '# Journal\n\nbody\n' > ".decisions/issue-$issue.md"
    else
      printf '# Journal\n\nbody\n' > ".decisions/session-$(date +%Y-%m-%d).md"
    fi
    git add -A >/dev/null 2>&1
    git commit -q -m "chore: seed" >/dev/null 2>&1
  ) || return 1
  printf '%s' "$d"
}

# Feed a payload to a hook on stdin. $1 = hook path, then the remaining args
# are JSON field assignments for jq.
_ar_payload() {
  local tool="$1" toolobj="$2" cwd="$3" agent="${4:-}"
  if [ -n "$agent" ]; then
    printf '{"session_id":"s1","cwd":"%s","tool_name":"%s","tool_input":%s,"agent_id":"a1","agent_type":"%s"}' \
      "$cwd" "$tool" "$toolobj" "$agent"
  else
    printf '{"session_id":"s1","cwd":"%s","tool_name":"%s","tool_input":%s}' \
      "$cwd" "$tool" "$toolobj"
  fi
}

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi

THIS_MONTH=$(date +%Y-%m)
TODAY=$(date +%Y-%m-%d)

# --- T1: an edit writes to the auto-log dir, never to the tracked journal ----
_flow_test_begin "T1 edit writes to auto-log, not the journal"
D=$(_ar_make_repo "feature/issue-99-relocate" 99)
mkdir -p "$D/src"
printf 'x\n' > "$D/src/app.sh"
BEFORE=$(cat "$D/.decisions/issue-99.md")
_ar_payload "Edit" '{"file_path":"src/app.sh"}' "$D" | \
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" bash "$HOOK_EDIT" >/dev/null 2>&1
assert_exit 0 "$?" "T1 hook exit 0"
AUTOLOG="$D/.decisions/auto-log/issue-99.$THIS_MONTH.md"
assert_file_exists "$AUTOLOG" "T1 auto-log file created"
assert_contains "Edit src/app.sh" "$(cat "$AUTOLOG" 2>/dev/null)" "T1 repo-relative path recorded"
assert_equal "$BEFORE" "$(cat "$D/.decisions/issue-99.md")" "T1 tracked journal untouched"

# --- T2: the payload cwd wins over the hook process CWD ---------------------
# The hook process runs from $REPO_ROOT (the runner's cwd). If the hook used
# the process cwd it would resolve THIS repo's .decisions, not the temp one.
_flow_test_begin "T2 payload cwd wins"
D=$(_ar_make_repo "feature/issue-99-relocate" 99)
mkdir -p "$D/src"
printf 'x\n' > "$D/src/app.sh"
_ar_payload "Write" '{"file_path":"src/app.sh"}' "$D" | \
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" bash "$HOOK_EDIT" >/dev/null 2>&1
assert_file_exists "$D/.decisions/auto-log/issue-99.$THIS_MONTH.md" "T2 wrote into the payload cwd's repo"

# --- T3: a path outside the repo is not recorded ----------------------------
_flow_test_begin "T3 out-of-tree path skipped"
D=$(_ar_make_repo "feature/issue-99-relocate" 99)
_ar_payload "Write" '{"file_path":"/tmp/ja-scratch.md"}' "$D" | \
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" bash "$HOOK_EDIT" >/dev/null 2>&1
assert_exit 0 "$?" "T3 exit 0"
if [ -f "$D/.decisions/auto-log/issue-99.$THIS_MONTH.md" ]; then
  _flow_assert_fail "T3 out-of-tree path was recorded"
else
  _flow_assert_pass "T3 out-of-tree path not recorded"
fi

# --- T4: a sibling dir sharing a name prefix is outside ---------------------
# Distinguishes a correct trailing-separator comparison from a bare prefix
# match ("$ROOT"* would treat /tmp/x/repo-backup as inside /tmp/x/repo).
_flow_test_begin "T4 sibling prefix is outside"
D=$(_ar_make_repo "feature/issue-99-relocate" 99)
SIB="${D}-backup"
mkdir -p "$SIB"
AR_CLEANUP_PATHS+=("$SIB")
printf 'x\n' > "$SIB/f.md"
_ar_payload "Write" "{\"file_path\":\"$SIB/f.md\"}" "$D" | \
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" bash "$HOOK_EDIT" >/dev/null 2>&1
if [ -f "$D/.decisions/auto-log/issue-99.$THIS_MONTH.md" ]; then
  _flow_assert_fail "T4 sibling-prefix path was recorded as in-repo"
else
  _flow_assert_pass "T4 sibling-prefix path skipped"
fi

# --- T5: a subagent entry carries agent= ------------------------------------
_flow_test_begin "T5 subagent tag"
D=$(_ar_make_repo "feature/issue-99-relocate" 99)
mkdir -p "$D/src"
printf 'x\n' > "$D/src/app.sh"
_ar_payload "Edit" '{"file_path":"src/app.sh"}' "$D" "flow:code-reviewer" | \
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" bash "$HOOK_EDIT" >/dev/null 2>&1
BODY=$(cat "$D/.decisions/auto-log/issue-99.$THIS_MONTH.md" 2>/dev/null)
assert_contains "agent=flow:code-reviewer" "$BODY" "T5 agent tag present"

# --- T6: a main-thread entry keeps the pre-change shape ---------------------
_flow_test_begin "T6 main-thread entry shape unchanged"
D=$(_ar_make_repo "feature/issue-99-relocate" 99)
mkdir -p "$D/src"
printf 'x\n' > "$D/src/app.sh"
_ar_payload "Edit" '{"file_path":"src/app.sh"}' "$D" | \
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" bash "$HOOK_EDIT" >/dev/null 2>&1
BODY=$(cat "$D/.decisions/auto-log/issue-99.$THIS_MONTH.md" 2>/dev/null)
assert_match '^<!-- auto-log: [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} Edit src/app\.sh -->$' \
  "$BODY" "T6 entry matches the original format exactly"
assert_not_contains "agent=" "$BODY" "T6 no agent tag on a main-thread entry"

# --- T7: NotebookEdit's notebook_path is read too ---------------------------
_flow_test_begin "T7 notebook_path"
D=$(_ar_make_repo "feature/issue-99-relocate" 99)
mkdir -p "$D/nb"
printf '{}\n' > "$D/nb/a.ipynb"
_ar_payload "NotebookEdit" '{"notebook_path":"nb/a.ipynb"}' "$D" | \
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" bash "$HOOK_EDIT" >/dev/null 2>&1
assert_contains "NotebookEdit nb/a.ipynb" "$(cat "$D/.decisions/auto-log/issue-99.$THIS_MONTH.md" 2>/dev/null)" \
  "T7 notebook path recorded"

# --- T8: a linked worktree records locally and leaves the main checkout ------
_flow_test_begin "T8 linked worktree isolation"
D=$(_ar_make_repo "feature/issue-99-relocate" 99)
WT="$D-wt"
git -C "$D" worktree add -q "$WT" -b feature/issue-99-wt >/dev/null 2>&1
AR_CLEANUP_PATHS+=("$WT")
mkdir -p "$WT/src"
printf 'x\n' > "$WT/src/wt.sh"
MAIN_BEFORE=$(find "$D/.decisions" -name '*.md' -exec cat {} \; 2>/dev/null)
_ar_payload "Edit" '{"file_path":"src/wt.sh"}' "$WT" | \
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" bash "$HOOK_EDIT" >/dev/null 2>&1
assert_exit 0 "$?" "T8 exit 0"
WT_LOG="$WT/.decisions/auto-log/issue-99.$THIS_MONTH.md"
if [ -f "$WT_LOG" ]; then
  _flow_assert_pass "T8 breadcrumb landed in the worktree"
else
  _flow_assert_fail "T8 worktree breadcrumb missing (expected $WT_LOG)"
fi
MAIN_AFTER=$(find "$D/.decisions" -name '*.md' -exec cat {} \; 2>/dev/null)
assert_equal "$MAIN_BEFORE" "$MAIN_AFTER" "T8 main checkout's journal untouched"

# --- T9: branchless fallback keeps the tracked journal's daily name ---------
_flow_test_begin "T9 branchless fallback is daily"
D=$(_ar_make_repo "main" "")
printf 'x\n' > "$D/f.txt"
_ar_payload "Write" '{"file_path":"f.txt"}' "$D" | \
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" bash "$HOOK_EDIT" >/dev/null 2>&1
assert_file_exists "$D/.decisions/auto-log/session-$TODAY.md" "T9 daily session file, not monthly"

# --- T10: a symlinked auto-log target is not written through ----------------
_flow_test_begin "T10 symlinked auto-log refused"
D=$(_ar_make_repo "feature/issue-99-relocate" 99)
mkdir -p "$D/.decisions/auto-log"
printf 'VICTIM\n' > "$D/victim.txt"
ln -s "$D/victim.txt" "$D/.decisions/auto-log/issue-99.$THIS_MONTH.md"
mkdir -p "$D/src"; printf 'x\n' > "$D/src/app.sh"
_ar_payload "Edit" '{"file_path":"src/app.sh"}' "$D" | \
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" bash "$HOOK_EDIT" >/dev/null 2>&1
assert_exit 0 "$?" "T10 exit 0"
assert_equal "VICTIM" "$(cat "$D/victim.txt")" "T10 symlink target untouched"

# --- T11: comment-terminator escaping survives (SEC-7) ----------------------
_flow_test_begin "T11 commit subject escaped"
D=$(_ar_make_repo "feature/issue-99-relocate" 99)
git -C "$D" commit -q --allow-empty -m 'evil --> <!-- injected' >/dev/null 2>&1
_ar_payload "Bash" '{"command":"git commit -m x"}' "$D" | \
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" bash "$HOOK_COMMIT" >/dev/null 2>&1
BODY=$(cat "$D/.decisions/auto-log/issue-99.$THIS_MONTH.md" 2>/dev/null)
assert_not_contains "<!-- injected" "$BODY" "T11 nested comment opener neutralized"
assert_contains "-- >" "$BODY" "T11 comment terminator neutralized"
assert_not_contains "auto-log" "$(cat "$D/.decisions/issue-99.md")" "T11 tracked journal still clean"

# --- T12: log-commits.sh writes to the auto-log, not the journal ------------
_flow_test_begin "T12 commit breadcrumb relocated"
D=$(_ar_make_repo "feature/issue-99-relocate" 99)
BEFORE=$(cat "$D/.decisions/issue-99.md")
printf 'x\n' > "$D/f.txt"; git -C "$D" add -A >/dev/null 2>&1
git -C "$D" commit -q -m "feat: real change" >/dev/null 2>&1
_ar_payload "Bash" '{"command":"git commit -m x"}' "$D" | \
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" bash "$HOOK_COMMIT" >/dev/null 2>&1
assert_contains 'commit "feat: real change"' \
  "$(cat "$D/.decisions/auto-log/issue-99.$THIS_MONTH.md" 2>/dev/null)" "T12 commit entry recorded"
assert_equal "$BEFORE" "$(cat "$D/.decisions/issue-99.md")" "T12 tracked journal untouched"

# --- T13: Guard 2 fires from a subdirectory of the repo ----------------------
# The subject deliberately does NOT start with "chore(decisions):", so Guard 1
# cannot fire and this reaches Guard 2 — the guard whose comparison was broken.
# Pre-change, $CHANGED came back repo-root-relative while $JOURNAL_FILE was
# CWD-relative, so off the repo root the two never matched and the guard
# silently stopped firing.
_flow_test_begin "T13 journal-only commit guard from a subdir"
D=$(_ar_make_repo "feature/issue-99-relocate" 99)
mkdir -p "$D/sub"
printf 'journal-only\n' >> "$D/.decisions/issue-99.md"
git -C "$D" add -A >/dev/null 2>&1
git -C "$D" commit -q -m "docs: tweak the record" >/dev/null 2>&1
_ar_payload "Bash" '{"command":"git commit -m x"}' "$D/sub" | \
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" bash "$HOOK_COMMIT" >/dev/null 2>&1
assert_exit 0 "$?" "T13 exit 0"
if [ -f "$D/.decisions/auto-log/issue-99.$THIS_MONTH.md" ]; then
  _flow_assert_fail "T13 Guard 2 did not fire — a journal-only commit was logged"
else
  _flow_assert_pass "T13 journal-only commit not logged"
fi

# --- T14: one entry is one write — no stray lone blank line ------------------
_flow_test_begin "T14 a single entry is one write"
D=$(_ar_make_repo "feature/issue-99-relocate" 99)
mkdir -p "$D/src"; printf 'x\n' > "$D/src/app.sh"
_ar_payload "Edit" '{"file_path":"src/app.sh"}' "$D" | \
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" bash "$HOOK_EDIT" >/dev/null 2>&1
AUTOLOG="$D/.decisions/auto-log/issue-99.$THIS_MONTH.md"
TRAILING_BLANKS=$(grep -c '^$' "$AUTOLOG" 2>/dev/null)
assert_equal "1" "$TRAILING_BLANKS" "T14 exactly one separating blank line per entry"

# --- T15: AC1 in a consumer repo that never ran /flow:setup ------------------
# The repo's own .gitignore is not the mechanism that matters — a consumer
# installs the plugin and gets the hook, but may never run setup. If the trail
# directory were merely untracked rather than ignored, the tree would be dirty
# anyway and AC1 would hold only in this repository.
_flow_test_begin "T15 consumer repo stays clean with no setup"
D=$(_ar_make_repo "feature/issue-99-relocate" 99)
# The scenario AC1 describes is a session that edits files AND commits, so the
# edited file is committed before the hook runs — otherwise the untracked file
# itself is what dirties the tree and the assertion measures the wrong thing.
mkdir -p "$D/src"; printf 'x\n' > "$D/src/app.sh"
git -C "$D" add -A >/dev/null 2>&1
git -C "$D" commit -q -m "feat: add app" >/dev/null 2>&1
[ -f "$D/.gitignore" ] && printf '# no auto-log rule on purpose\n' >> "$D/.gitignore"
_ar_payload "Edit" '{"file_path":"src/app.sh"}' "$D" | \
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" bash "$HOOK_EDIT" >/dev/null 2>&1
assert_file_exists "$D/.decisions/auto-log/.gitignore" "T15 trail dir ignores itself"
DIRTY=$(git -C "$D" status --porcelain -uall 2>/dev/null)
assert_equal "" "$DIRTY" "T15 git status is clean after a breadcrumb"

# --- T16: a payload with no cwd falls back to the process directory ----------
# Run with the process cwd inside the scratch repo, so the fallback is provable
# without writing into this repository.
_flow_test_begin "T16 missing cwd falls back to \$PWD"
D=$(_ar_make_repo "feature/issue-99-relocate" 99)
mkdir -p "$D/src"; printf 'x\n' > "$D/src/app.sh"
( cd "$D" && printf '{"tool_name":"Edit","tool_input":{"file_path":"src/app.sh"}}' | \
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" bash "$HOOK_EDIT" >/dev/null 2>&1 )
assert_file_exists "$D/.decisions/auto-log/issue-99.$THIS_MONTH.md" "T16 fell back to \$PWD"

# --- T17: a payload cwd that no longer exists is not fatal -------------------
_flow_test_begin "T17 deleted cwd exits cleanly"
D=$(_ar_make_repo "feature/issue-99-relocate" 99)
GONE="$D-then-deleted"
_ar_payload "Edit" '{"file_path":"src/app.sh"}' "$GONE" | \
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" bash "$HOOK_EDIT" >/dev/null 2>&1
assert_exit 0 "$?" "T17 exit 0 for a cwd that does not exist"
