# Tests for hooks/scripts/block-force-push.sh.
#
# Contract under test: the hook blocks (exit 2) a `git push` that itself carries
# `-f` or `--force`, and allows everything else. What it must never do is read a
# force flag belonging to something else on the same shell line as if it were the
# push's own — the guard decides on the push invocation's arguments, not on
# whatever else shares the line.
#
# The distinction the cases below turn on: `git push` followed by an unrelated
# command carrying `-f` (a `pgrep -f`, a `grep -f`, an `rm -f`) is one push and
# one other command. A guard that scans the whole line cannot tell that from
# `git push --force`, so it refuses a legitimate push and tells the operator to
# force-push by hand — advice that, followed, is the destructive action the hook
# exists to prevent.
#
# The hook reads {"tool_input":{"command":"..."}} on stdin and exits 0 (allow)
# or 2 (block). It consults no git state, so every case runs from a scratch
# directory.
#
# Prereq: jq (the hook hard-requires it). SKIPS gracefully otherwise.

HOOK="$REPO_ROOT/plugins/flow/hooks/scripts/block-force-push.sh"

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi

# _fp_exit <command> — the hook's exit code for that command.
_fp_exit() {
  jq -n --arg c "$1" '{tool_input:{command:$c}}' | bash "$HOOK" >/dev/null 2>&1
  printf '%s' "$?"
}

# _fp_blocks <command> — PASS when the hook refuses it, FAIL when it allows.
_fp_blocks() {
  local code
  code=$(_fp_exit "$1")
  assert_equal "2" "$code" "blocked: $1"
}

# _fp_allows <command> — PASS when the hook allows it, FAIL when it refuses.
_fp_allows() {
  local code
  code=$(_fp_exit "$1")
  assert_equal "0" "$code" "allowed: $1"
}

# ------------------------------------------------- a push that really forces --

_flow_test_begin "block-force-push — a push that carries a force flag is blocked"
_fp_blocks "git push --force origin main"
_fp_blocks "git push -f origin main"
_fp_blocks "git push --force"
# After a separator, and inside a compound command: the flag still belongs to
# the push.
_fp_blocks "git status && git push --force"
_fp_blocks "cd repo && git push -f origin main"
_fp_blocks "{ git push --force; }"
_fp_blocks "git push origin main -f"
_fp_blocks "git push --force-with-lease --force"
# The flag written as its own word, before the arguments the push takes.
_fp_blocks "git push -f"
# A launcher word leaves the push in command position, so it still counts.
_fp_blocks "sudo git push --force origin main"
# So does a shell keyword that introduces a command list.
_fp_blocks "if git push --force; then :; fi"
_fp_blocks "while true; do git push -f; done"
# `git` takes global options before its subcommand, so the subcommand is not
# the second word.
_fp_blocks "git -C repo push --force"
_fp_blocks "git --git-dir=.git push -f"
# An assignment prefix does not stop it being the command.
_fp_blocks "GIT_DIR=x git push --force"
# A QUOTED FLAG IS STILL A FLAG: the shell strips the quotes and git receives
# the flag. This is the shape a guard that blanks quoted spans lets through.
_fp_blocks "git push '--force'"
_fp_blocks "git push \"-f\""
_fp_blocks "git push --forc''e"

# ------------------------------------- a push that does not, and never did --

_flow_test_begin "block-force-push — a push that carries no force flag is allowed"
_fp_allows "git push origin main"
_fp_allows "git push --force-with-lease origin main"
_fp_allows "git push --set-upstream origin main"
# A branch named -feature is not a flag; the word boundary is what separates
# them, and a guard matching a bare -f prefix would refuse this.
_fp_allows "git push origin --force-with-lease"

# ------------------------- a force flag that belongs to something else ------

_flow_test_begin "block-force-push — another command's force flag is not the push's"
# The reported case: an unrelated command after the push, carrying -f.
_fp_allows "git push origin main && pgrep -f 'dossier/tests/run.sh'"
_fp_allows "git push && grep -f patterns.txt file"
_fp_allows "pgrep -f 'something' && git push origin main"
_fp_allows "git status && pgrep -f x"
# A force flag on a command that is not a push at all.
_fp_allows "rm -f /tmp/scratch"
_fp_allows "git branch -f other main"

# ------------------------------------------- text that only mentions a push --

_flow_test_begin "block-force-push — text that mentions a force-push is not one"
# A command whose text describes the flags, which is how this defect was filed:
# writing an issue body about force-pushing was itself refused as a force-push.
_fp_allows "gh issue create --body 'git push --force is blocked'"
_fp_allows "printf '%s\n' 'never run git push -f'"
_fp_allows "echo 'git push --force'"
# A heredoc body is text being written to a file, not a command being run.
_fp_allows "cat > notes.md <<'EOF'
git push --force is the thing to avoid
EOF"
# A separator inside a quoted string does not start a new command.
_fp_allows "grep -q 'x ; git push --force' file"
# A comment is prose about the command, not an argument to it.
_fp_allows "git push origin main # -f"
# And the reverse of the quoted-flag rule: a push named inside a string is one
# word of another command's argument, not the command itself.
_fp_allows "echo 'git push'"
_fp_allows "printf '%s\n' \"git push -f\""

# ----------------------------------------------------------- shapes that must not crash --

_flow_test_begin "block-force-push — a malformed command is not a crash"
# set -euo pipefail plus a failing grep exits non-zero, and the harness reads a
# non-2 exit as an allow. So a parse path that can error is a path that silently
# stops guarding — these assert the hook survives them.
assert_equal "0" "$(_fp_exit "")" "an empty command is allowed, not an error"
assert_equal "0" "$(_fp_exit "git push 'unbalanced")" "an unbalanced quote does not crash the hook"
_fp_blocks "git push --force 'unbalanced"
