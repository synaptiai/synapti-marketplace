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
_run_hook "git restore ${DOT}/"
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

# A force branch delete chained to anything else stays refused. That used to be
# a side effect of a target parser that could not tell branch names from the
# rest of the line; now the parser can, so the refusal is stated as its own rule
# and says why.
_flow_test_begin "a chained force branch delete says why it is refused"
ERR=$(_run_hook_stderr "git branch -D somebranch && echo done")
assert_contains "chained into a compound command" "$ERR" "the message names the chaining as the reason"

# --- the tokeniser is doing the work, not a lucky regex ------------------------
# If _bd_git_parse silently failed to find git in every one of these, every
# allow-assertion above would pass for the wrong reason. Two commands that must
# still block prove the parse reaches the subcommand through the shapes that
# make parsing hard.
# --- the shape a PR body and a commit message actually take ---------------------
# `"$(cat <<EOF ... EOF)"` is how nearly every long body reaches the shell. The
# heredoc introducer sits inside a double-quoted string, so a scanner that stops
# at the opening quote records no heredoc and reads the body as commands. That
# is precisely how writing the issue asking for this fix got refused three
# times, and it is the case worth being sure about.
SQ="'"
_flow_test_begin "a heredoc inside a command substitution inside quotes is content"
_run_hook "gh pr create --body \"\$(cat <<${SQ}EOF${SQ}
This body explains why git restore $DOT is dangerous.
EOF
)\""
assert_exit 0 "$?" "a PR body naming a restore is allowed"
_run_hook "git commit -m \"\$(cat <<${SQ}EOF${SQ}
fix: stop reading a dotted path as the whole tree

The prose here mentions rm -rf and git reset --hard on purpose.
EOF
)\""
assert_exit 0 "$?" "a commit message naming destructive commands is allowed"

_flow_test_begin "the same shape still blocks when the substitution runs a shell"
_run_hook "echo \"\$(bash <<${SQ}EOF${SQ}
git reset --hard
EOF
)\""
assert_exit 2 "$?" "a body handed to bash inside a substitution is examined"
_run_hook "OUT=\$(sh <<${SQ}EOF${SQ}
rm -rf /some/path
EOF
)"
assert_exit 2 "$?" "a body handed to sh through an assignment is examined"
_run_hook "ssh host <<EOF
git reset --hard
EOF"
assert_exit 2 "$?" "a body handed to ssh runs on the far side and is examined"

# --- long commands ------------------------------------------------------------
# This hook runs before every Bash call, so the cost of reading a command is
# paid on every command. The first version of the scanner walked characters in
# bash and concatenated a string per character: a 40KB quoted argument took 22
# seconds. The bound below is generous by two orders of magnitude — it is there
# to catch a return to quadratic behaviour, not to measure anything.
_flow_test_begin "a long command is read quickly and still read correctly"
BIG=$(awk 'BEGIN { s = ""; while (length(s) < 40000) s = s "x"; print s }')
BIG_CMD="echo '$BIG git restore $DOT'"
BDG_START=$(date +%s)
_run_hook "$BIG_CMD"
BDG_RC=$?
BDG_ELAPSED=$(( $(date +%s) - BDG_START ))
assert_exit 0 "$BDG_RC" "a destructive command quoted inside a 40KB argument is allowed"
if [ "$BDG_ELAPSED" -le 10 ]; then
  _flow_assert_pass "40KB command read in ${BDG_ELAPSED}s (bound: 10s)"
else
  _flow_assert_fail "40KB command took ${BDG_ELAPSED}s — the scanner is quadratic again, and this cost is paid before every Bash call"
fi

_flow_test_begin "a long heredoc body is content and does not slow the hook"
BDG_START=$(date +%s)
_run_hook "cat <<EOF
$BIG
git reset --hard
EOF"
BDG_RC=$?
BDG_ELAPSED=$(( $(date +%s) - BDG_START ))
assert_exit 0 "$BDG_RC" "a destructive command inside a 40KB heredoc body is allowed"
if [ "$BDG_ELAPSED" -le 10 ]; then
  _flow_assert_pass "40KB heredoc read in ${BDG_ELAPSED}s (bound: 10s)"
else
  _flow_assert_fail "40KB heredoc took ${BDG_ELAPSED}s"
fi

_flow_test_begin "the parse still finds the subcommand through awkward spellings"
_run_hook "/usr/bin/git reset --hard"; assert_exit 2 "$?" "absolute git binary blocked"
_run_hook "git -c core.pager=cat reset --hard"; assert_exit 2 "$?" "reset --hard behind -c key=value blocked"
_run_hook "sudo git clean -fd"; assert_exit 2 "$?" "clean --force behind sudo blocked"
_run_hook "git \"reset\" --hard"; assert_exit 2 "$?" "quoted subcommand blocked"

# --- the false allows three reviewers constructed -----------------------------
# Each of these is a command that main blocks and an earlier version of this
# change let through. They are grouped because they share one cause: the
# stripper deciding a span was text when it was code, and every rule reading
# only what survives stripping. The rule now is that anything uncertain is kept.

_flow_test_begin "a here-string is not a heredoc"
_run_hook "grep foo <<<\"\$VAR\"
git reset --hard"
assert_exit 2 "$?" "a command after a here-string is still examined"
_run_hook "cmd <<<word
git reset --hard"
assert_exit 2 "$?" "the unquoted here-string form too"

_flow_test_begin "a left shift is arithmetic, not a heredoc introducer"
_run_hook "echo \$((1 << 3))
git reset --hard"
assert_exit 2 "$?" "a command after \$((a << b)) is still examined"
_run_hook "(( x << 2 ))
rm -rf /important"
assert_exit 2 "$?" "a command after a bare arithmetic command is still examined"
_run_hook "let x=1<<3
git reset --hard"
assert_exit 2 "$?" "a command after let x=1<<3 is still examined"

_flow_test_begin "a heredoc that never terminates keeps everything it swallowed"
_run_hook "cat <<EOF
git reset --hard"
assert_exit 2 "$?" "an unterminated heredoc does not hide the command inside it"
_run_hook "cat <<\\EOF
text
EOF
git reset --hard"
assert_exit 2 "$?" "a backslash-quoted delimiter is not recognised, so its body is kept"

_flow_test_begin "an escaped quote does not desynchronise the scan"
_run_hook "echo \"he said \\\"a << EOF b\\\"\"
git reset --hard"
assert_exit 2 "$?" "a command after an escaped quote is still examined"
_run_hook "echo \"\$(echo \"\$(date)\") <<EOF\"
git reset --hard"
assert_exit 2 "$?" "a command after a nested substitution is still examined"

# --- a heredoc body is only text when its owner is a text sink ----------------
# The question is not "does this line name an interpreter" but "who owns the
# heredoc". `gh pr create --body "$(cat <<EOF` is owned by cat and is text;
# everything below runs its body, on this machine or another one.
_flow_test_begin "a heredoc handed to something that runs it is examined"
for RUNNER in "bash" "sh" "ssh host" "sudo -s" "docker exec -i c1" "make -f -"; do
  _run_hook "$RUNNER <<EOF
git reset --hard
EOF"
  assert_exit 2 "$?" "heredoc to '$RUNNER' is examined"
done
_run_hook "\$SHELL <<EOF
git reset --hard
EOF"
assert_exit 2 "$?" "heredoc to a shell named by a variable is examined"
_run_hook "cat <<EOF | bash
git reset --hard
EOF"
assert_exit 2 "$?" "heredoc piped into a shell is examined"
_run_hook "cat > /tmp/x.sh <<EOF
git reset --hard
EOF"
assert_exit 2 "$?" "heredoc written to a file is examined — something later runs that file"

_flow_test_begin "a heredoc owned by a text sink is still content"
_run_hook "cat <<EOF
git restore $DOT
EOF"
assert_exit 0 "$?" "cat is a sink"
_run_hook "tee notes.txt <<EOF
git reset --hard
EOF"
assert_exit 0 "$?" "tee is a sink"

# --- an interpreter handed its script as a quoted argument --------------------
_flow_test_begin "a command inside an interpreter argument is examined"
_run_hook "bash -c \"git reset --hard\""
assert_exit 2 "$?" "bash -c with a double-quoted script"
_run_hook "sh -c 'git clean -fd'"
assert_exit 2 "$?" "sh -c with a single-quoted script"
_run_hook "ssh host \"git checkout -- $DOT\""
assert_exit 2 "$?" "ssh with a quoted remote command"
_run_hook "eval \"git reset --hard\""
assert_exit 2 "$?" "eval with a quoted command"
_run_hook "bash -c \"git status\""
assert_exit 0 "$?" "an ordinary command inside an interpreter argument is allowed"

# --- git accepts abbreviated long options -------------------------------------
# Verified against real git: `git reset --har` performs a hard reset and
# `git clean --forc` deletes untracked files. Matching only the full spelling
# let both through.
_flow_test_begin "an abbreviated long option is the option"
_run_hook "git reset --har HEAD";        assert_exit 2 "$?" "git reset --har blocked"
_run_hook "git reset --ha HEAD";         assert_exit 2 "$?" "git reset --ha blocked"
_run_hook "git clean --forc -d";         assert_exit 2 "$?" "git clean --forc blocked"
_run_hook "git clean --fo -d";           assert_exit 2 "$?" "git clean --fo blocked"
_run_hook "git restore --stag --workt $DOT"
assert_exit 2 "$?" "abbreviated --staged --worktree still writes the tree"

_flow_test_begin "an abbreviation that is not the option is not blocked"
_run_hook "git reset --soft HEAD~1";     assert_exit 0 "$?" "--soft is not a prefix of --hard"
_run_hook "git clean -n";                assert_exit 0 "$?" "clean dry run still allowed"
_run_hook "git restore --stag $DOT";     assert_exit 0 "$?" "abbreviated --staged alone touches the index only"

# --- whole-tree pathspec spellings --------------------------------------------
_flow_test_begin "every spelling of the whole tree is the whole tree"
_run_hook "git checkout $DOT";           assert_exit 2 "$?" "checkout with no separator"
_run_hook "git checkout ${DOT}/";        assert_exit 2 "$?" "checkout ./ with no separator"
_run_hook "git checkout -f $DOT";        assert_exit 2 "$?" "checkout -f ."
_run_hook "git checkout -- ${DOT}/$DOT"; assert_exit 2 "$?" "checkout -- ./."
_run_hook "git checkout -- ${DOT}//";    assert_exit 2 "$?" "checkout -- .//"
_run_hook "git restore '*'";             assert_exit 2 "$?" "restore of a glob"
_run_hook "git checkout -- '*'";         assert_exit 2 "$?" "checkout of a glob"
_run_hook "git restore ':'";             assert_exit 2 "$?" "restore of the : pathspec"
_run_hook "git restore ':(top)'";        assert_exit 2 "$?" "restore of :(top)"
_run_hook "git checkout -- ':/*'";       assert_exit 2 "$?" "checkout of :/*"

_flow_test_begin "branch names and ordinary paths are still not the whole tree"
_run_hook "git checkout main";           assert_exit 0 "$?" "switching branches"
_run_hook "git checkout -b feature/x";   assert_exit 0 "$?" "creating a branch"
_run_hook "git checkout ${DOT}decisions/x.md"; assert_exit 0 "$?" "a dotted path with no separator"
_run_hook "git checkout -- src/a.py";    assert_exit 0 "$?" "an ordinary path"

# --- CRLF ---------------------------------------------------------------------
# The two tokeniser paths disagreed about the carriage return, so the same
# command got a different verdict depending on whether a quote happened to
# appear in it.
_flow_test_begin "a CRLF command is read like an LF one"
_run_hook "git reset --hard$(printf '\r')"
assert_exit 2 "$?" "a trailing CR does not hide the option"
_run_hook "echo \"x\"$(printf '\r')
git reset --hard$(printf '\r')"
assert_exit 2 "$?" "CRLF on every line does not hide the command"

# --- the branch rule ----------------------------------------------------------
_flow_test_begin "a redirection target is not a branch name"
ERR=$(_run_hook_stderr "git branch -D somebranch > out.txt")
assert_contains "BLOCKED:" "$ERR" "still refused, but"
if printf '%s' "$ERR" | grep -q "out.txt"; then
  _flow_assert_fail "the redirection target was collected as a branch name: $ERR"
else
  _flow_assert_pass "out.txt was not read as a branch name"
fi

# --- the hook refuses when it cannot see --------------------------------------
_flow_test_begin "a missing scanner blocks rather than allowing"
NOAWK=$(mktemp -d -t flow-noawk.XXXXXX 2>/dev/null) || NOAWK=""
if [ -z "$NOAWK" ]; then
  _flow_assert_fail "mktemp failed; cannot build the no-awk environment"
else
  BDG_CLEAN_NOAWK="$NOAWK"
  for TOOL in jq git bash sed grep basename printf; do
    TP=$(command -v "$TOOL" 2>/dev/null) && ln -sf "$TP" "$NOAWK/$TOOL" 2>/dev/null
  done
  JSON=$(printf '%s' "git reset --hard" | jq -Rs .)
  printf '{"tool_input":{"command":%s}}' "$JSON" | PATH="$NOAWK" bash "$HOOK" >/dev/null 2>&1
  NOAWK_RC=$?
  if [ "$NOAWK_RC" -eq 2 ]; then
    _flow_assert_pass "with no awk on PATH the hook exits 2 rather than falling through"
  else
    _flow_assert_fail "with no awk on PATH the hook exited $NOAWK_RC — a hook that cannot see must not allow"
  fi
  rm -r -- "$NOAWK" 2>/dev/null
fi
