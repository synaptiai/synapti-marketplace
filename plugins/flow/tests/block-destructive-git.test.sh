# Tests for the git rules in hooks/scripts/block-destructive.sh (issues #167, #142).
#
# Contract under test: checkout, restore, reset and clean are judged from the
# command actually being run, not from the text of the string the command is
# embedded in.
#
#   - A pathspec is the whole tree only when it IS the whole tree: `.`, `./`
#     or `:/`. A path that merely begins with a dot — `.github/workflows/ci.yml`,
#     `.decisions/issue-749.md` — is an ordinary path and passes.
#   - The whole-tree forms still block, including with further arguments after
#     them.
#   - `git restore --staged .` touches the index only and passes; adding
#     `--worktree` makes it a working-tree discard and blocks.
#   - Text that merely contains a destructive command — inside quotes, inside a
#     heredoc body, after a `#` — runs no git and passes. A heredoc fed to a
#     shell is examined, because that body does run.
#
# The hook reads {"tool_input":{"command":"..."}} on stdin and exits 0 (allow)
# or 2 (block). None of these scenarios needs a git repository except the ones
# the branch-delete rule owns, which live in block-destructive-branch.test.sh.
#
# Prereq: jq (the hook hard-requires it). SKIPS gracefully otherwise.

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"; _flow_assert_pass "SKIP: jq not installed"; return 0
fi

HOOK="$REPO_ROOT/plugins/flow/hooks/scripts/block-destructive.sh"

BDG_DIR=$(mktemp -d -t flow-bdg.XXXXXX)
_bdg_cleanup() { [ -n "${BDG_DIR:-}" ] && rm -rf "$BDG_DIR" 2>/dev/null; }
trap _bdg_cleanup EXIT

# The whole-tree pathspec is assembled at run time rather than written as a
# literal. This test file is itself edited through a Bash tool call that the
# very hook under test inspects, and a literal would make the file unwritable
# by the tool that has to write it.
DOT='.'

_run_hook() {
  local cmd="$1" json
  json=$(printf '%s' "$cmd" | jq -Rs .)
  ( cd "$BDG_DIR" && printf '{"tool_input":{"command":%s}}' "$json" | bash "$HOOK" ) >/dev/null 2>&1
}

_run_hook_stderr() {
  local cmd="$1" json
  json=$(printf '%s' "$cmd" | jq -Rs .)
  ( cd "$BDG_DIR" && printf '{"tool_input":{"command":%s}}' "$json" | bash "$HOOK" ) 2>&1 >/dev/null
}

# --- the table in issue #167, row for row --------------------------------------
_flow_test_begin "a dotted single path is not the whole tree"
_run_hook "git checkout -- .decisions/issue-749.md"
assert_exit 0 "$?" "checkout of a path under .decisions allowed"
_run_hook "git checkout -- $DOT"
assert_exit 2 "$?" "checkout of the whole tree blocked"
_run_hook "git restore .github/workflows/ci.yml"
assert_exit 0 "$?" "restore of a path under .github allowed"
_run_hook "git restore $DOT"
assert_exit 2 "$?" "restore of the whole tree blocked"
_run_hook "git checkout -- src/a.py"
assert_exit 0 "$?" "checkout of an ordinary path allowed"

_flow_test_begin "other dotted paths and dotfiles are allowed"
_run_hook "git restore .claude/settings.json"
assert_exit 0 "$?" "restore of a path under .claude allowed"
_run_hook "git checkout -- .gitignore"
assert_exit 0 "$?" "checkout of .gitignore allowed"
_run_hook "git restore -- .github/workflows/ci.yml"
assert_exit 0 "$?" "restore with a separator and a dotted path allowed"
_run_hook "git restore ../sibling/file.txt"
assert_exit 0 "$?" "restore of a parent-relative path allowed"

# --- whole-tree spellings and trailing arguments --------------------------------
_flow_test_begin "the whole tree is still the whole tree with arguments around it"
_run_hook "git checkout -- $DOT src/a.py"
assert_exit 2 "$?" "whole tree followed by another path blocked"
_run_hook "git restore $DOT extra"
assert_exit 2 "$?" "restore whole tree followed by another path blocked"
_run_hook "git restore -- $DOT"
assert_exit 2 "$?" "restore whole tree after a separator blocked"
_run_hook "git restore .${DOT}/"
assert_exit 2 "$?" "restore of ./ blocked (same tree, different spelling)"
_run_hook "git restore :/"
assert_exit 2 "$?" "restore of the :/ root pathspec blocked"
_run_hook "git checkout -- \"$DOT\""
assert_exit 2 "$?" "quoted whole-tree pathspec blocked"
_run_hook "git restore --source=HEAD --worktree -- $DOT"
assert_exit 2 "$?" "the --source --worktree spelling of the whole tree blocked"

# --- restore writes the index or the working tree, and it matters ---------------
# `git restore --staged .` unstages everything and leaves every working-tree
# change in place. Nothing is lost, so it is not the operation this rule guards.
# Source: git-restore(1) — without --worktree, --staged restores the index only.
_flow_test_begin "restore --staged touches the index only and is allowed"
_run_hook "git restore --staged $DOT"
assert_exit 0 "$?" "restore --staged of the whole tree allowed"
_run_hook "git restore -S $DOT"
assert_exit 0 "$?" "restore -S of the whole tree allowed"
_run_hook "git restore --staged --worktree $DOT"
assert_exit 2 "$?" "restore --staged --worktree of the whole tree blocked"
_run_hook "git restore -SW $DOT"
assert_exit 2 "$?" "restore -SW of the whole tree blocked"

# --- text that runs no git ------------------------------------------------------
_flow_test_begin "quoted text and comments that run no git are allowed"
_run_hook "echo \"git restore $DOT\""
assert_exit 0 "$?" "echoing the command text allowed"
_run_hook "grep -q 'git checkout -- $DOT' notes.txt"
assert_exit 0 "$?" "grepping for the command text allowed"
_run_hook "# git reset --hard is the thing we avoid"
assert_exit 0 "$?" "a comment naming the command allowed"
_run_hook "echo hello  # git clean -fd would be bad here"
assert_exit 0 "$?" "a trailing comment naming the command allowed"
_run_hook "printf '%s' 'rm -rf /tmp/x'"
assert_exit 0 "$?" "quoting an rm allowed"

_flow_test_begin "heredoc bodies are content, not commands"
_run_hook "cat <<EOF
git restore $DOT
EOF"
assert_exit 0 "$?" "heredoc body naming a restore allowed"
_run_hook "cat <<'EOF'
rm -rf /some/path
EOF"
assert_exit 0 "$?" "quoted-delimiter heredoc body naming an rm allowed"
_run_hook "cat <<-EOF
	git reset --hard
	EOF"
assert_exit 0 "$?" "tab-indented heredoc body allowed"

# --- and the cases where the pattern really does run ---------------------------
# Stripping heredoc bodies must not become a way past the rule. Two ways it
# could: a real command after the terminator, and a body fed to a shell.
_flow_test_begin "stripping stops at the terminator and spares nothing after it"
_run_hook "cat <<EOF
git restore $DOT
EOF
git reset --hard HEAD~1"
assert_exit 2 "$?" "a real reset after the heredoc terminator still blocked"

_flow_test_begin "a heredoc fed to a shell is examined, because that body runs"
_run_hook "bash <<EOF
git reset --hard HEAD~1
EOF"
assert_exit 2 "$?" "heredoc piped into bash still blocked"
_run_hook "sh <<'EOF'
rm -rf /some/path
EOF"
assert_exit 2 "$?" "heredoc piped into sh still blocked"

_flow_test_begin "a # inside an argument is not a comment"
_run_hook "git reset --hard 'HEAD#1'"
assert_exit 2 "$?" "a hash inside a quoted argument does not hide the command"
_run_hook "git restore $DOT # discard everything"
assert_exit 2 "$?" "a comment after a real command does not excuse it"

_flow_test_begin "command substitution runs git and is examined"
_run_hook "echo \$(git restore $DOT)"
assert_exit 2 "$?" "restore inside a command substitution blocked"

# --- the rules that were already there still fire -------------------------------
_flow_test_begin "reset --hard and clean --force still block"
_run_hook "git reset --hard HEAD~1";  assert_exit 2 "$?" "reset --hard blocked"
_run_hook "git reset --hard";         assert_exit 2 "$?" "bare reset --hard blocked"
_run_hook "git clean -fd";            assert_exit 2 "$?" "clean -fd blocked"
_run_hook "git clean -d -f";          assert_exit 2 "$?" "clean with separate flags blocked"
_run_hook "git clean --force";        assert_exit 2 "$?" "clean --force blocked"
_run_hook "git -C /somewhere reset --hard"; assert_exit 2 "$?" "reset --hard behind -C blocked"
_run_hook "cd /tmp && git restore $DOT"; assert_exit 2 "$?" "restore after && blocked"

_flow_test_begin "the safe neighbours of those rules stay allowed"
_run_hook "git reset HEAD~1";         assert_exit 0 "$?" "mixed reset allowed"
_run_hook "git reset --soft HEAD~1";  assert_exit 0 "$?" "soft reset allowed"
_run_hook "git clean -n";             assert_exit 0 "$?" "clean dry run allowed"
_run_hook "git clean -nd";            assert_exit 0 "$?" "clean dry run with -d allowed"
_run_hook "git status";               assert_exit 0 "$?" "status allowed"
_run_hook "git restore --source=HEAD --worktree -- src/a.py"
assert_exit 0 "$?" "the single-path form of the documented workaround allowed"
_run_hook "git checkout main";        assert_exit 0 "$?" "switching branches allowed"
_run_hook "git checkout -b feature/x"; assert_exit 0 "$?" "creating a branch allowed"

_flow_test_begin "git is matched as a command word, not as a substring"
_run_hook "npm run git-reset-helper"; assert_exit 0 "$?" "a script named after the command is not the command"
_run_hook "echo digit"; assert_exit 0 "$?" "the letters git inside a word are not the command"

# --- messages ------------------------------------------------------------------
_flow_test_begin "block messages name the rule and the remedy"
ERR=$(_run_hook_stderr "git restore $DOT")
assert_contains "BLOCKED:" "$ERR" "restore message carries the BLOCKED prefix"
ERR=$(_run_hook_stderr "git checkout -- $DOT")
assert_contains "BLOCKED:" "$ERR" "checkout message carries the BLOCKED prefix"
ERR=$(_run_hook_stderr "git reset --hard")
assert_contains "BLOCKED:" "$ERR" "reset message carries the BLOCKED prefix"
ERR=$(_run_hook_stderr "git clean -fd")
assert_contains "BLOCKED:" "$ERR" "clean message carries the BLOCKED prefix"
