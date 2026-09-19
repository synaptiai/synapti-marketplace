# Tests for hooks/scripts/block-force-push.sh.
#
# Contract under test: the hook blocks (exit 2) a `git push` that itself carries
# a force flag, and allows everything else. What it must never do is read a
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
# Both directions are asserted, and the second one is the dangerous one. Every
# group below that names a way a force-push can be *written* is a case a guard
# that only understood the plain spelling would wave through:
#
#   * the separators that end a command, in their one-character spellings;
#   * launchers that carry their own options, and a path-qualified `git`;
#   * a shell's `-c` payload, and `eval`;
#   * a heredoc whose delimiter a naive reader mis-takes;
#   * quoting — single, double, joined-across-quotes, ANSI-C — and a line
#     continued with a backslash.
#
# The hook reads {"tool_input":{"command":"..."}} on stdin and exits 0 (allow)
# or 2 (block). It consults no git state, so every case runs from a scratch
# directory.
#
# Prereq: jq and awk (the hook hard-requires both). SKIPS gracefully otherwise.

HOOK="$REPO_ROOT/plugins/flow/hooks/scripts/block-force-push.sh"

if ! command -v jq >/dev/null 2>&1 || ! command -v awk >/dev/null 2>&1; then
  _flow_test_begin "jq and awk prerequisites"
  _flow_assert_pass "SKIP: jq and awk are both required"
  return 0
fi

# _fp_exit <command> — the hook's exit code for that command.
#
# The payload reaches the hook through a here-string rather than a pipe: with a
# pipe the status captured is the pipeline's, and under the runner's pipefail a
# hook that exited 2 could be reported as 141 when the writer is killed by
# SIGPIPE. The assertion would then fail for a reason that has nothing to do
# with the hook's decision.
_fp_exit() {
  local payload
  payload=$(jq -n --arg c "$1" '{tool_input:{command:$c}}')
  bash "$HOOK" <<<"$payload" >/dev/null 2>&1
  printf '%s' "$?"
}

# _fp_stderr <command> — what the hook printed on stderr.
_fp_stderr() {
  local payload
  payload=$(jq -n --arg c "$1" '{tool_input:{command:$c}}')
  bash "$HOOK" <<<"$payload" 2>&1 >/dev/null
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
# ANSI-C quoting is a quoted span too: the shell turns it into the same word.
_fp_blocks "git push \$'--force' origin main"
# A `+`-prefixed refspec is git's other way of spelling a forced update.
_fp_blocks "git push origin +main:main"

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
# And the reverse of the quoted-flag rule: a push named inside a string, or as
# another command's argument, is not the command itself. These pin command
# POSITION — a guard that grew tolerant wrappers by scanning for `git` anywhere
# would start refusing them.
_fp_allows "echo 'git push'"
_fp_allows "printf '%s\n' \"git push -f\""
_fp_allows "echo git push --force"
_fp_allows "grep -q 'git push --force' notes.md"
# A quoted string that spans lines is still one argument to one command, so the
# text on the continuation lines is not read as a command of its own.
_fp_allows "gh issue create --body \"notes
git push --force is blocked
end\""

# ----------------------------------- a force-push written some other way -----

_flow_test_begin "block-force-push — a one-character separator does not hide the push"
# Each of these ends a command in one character. A reader that advances two
# characters per separator drops the first letter of the next command word and
# never sees the push at all.
_fp_blocks "true;git push --force"
_fp_blocks "(git push --force)"
_fp_blocks "echo \$(git push --force)"
_fp_blocks "true|git push --force"
_fp_blocks "true &git push --force"
_fp_blocks "true;git push -f"

_flow_test_begin "block-force-push — a launcher's own options do not hide the push"
# The launcher is followed by words that belong to the launcher, not to the
# command it runs; a reader that expects the push immediately after the
# launcher word never reaches it.
_fp_blocks "timeout 10 git push --force"
_fp_blocks "nice -n 5 git push --force"
_fp_blocks "stdbuf -oL git push --force"
_fp_blocks "sudo -u root git push --force"
_fp_blocks "sudo -g staff git push -f"
_fp_blocks "env -i PATH=/usr/bin git push --force"
_fp_blocks "echo x | xargs -n1 git push --force"
_fp_blocks "xargs -n 1 git push --force"
# A path-qualified command is the same command.
_fp_blocks "/usr/bin/git push --force"
_fp_blocks "sudo /usr/bin/git push --force"
# A shell's -c payload is a command line of its own.
_fp_blocks "sh -c \"git push --force\""
_fp_blocks "bash -c 'git push --force'"
# eval takes the rest of its words as the command to run, quoted or not.
_fp_blocks "eval git push --force"
_fp_blocks "eval \"git push --force\""

_flow_test_begin "block-force-push — a heredoc that desyncs does not hide the push"
# `<<<` is a here-string: it has no body, so it must not open one. A reader that
# mistakes it for a heredoc treats the rest of the command as text.
_fp_blocks "read -r x <<< hi
git push --force"
# The delimiter word ends at the first shell metacharacter, so `<<EOF;` opens a
# heredoc terminated by EOF, not by `EOF;`.
_fp_blocks "cat <<EOF; echo done
EOF
git push --force"
# Quote removal applies to the delimiter, so `<<\EOF` and `<<'EOF'` both end at
# a line reading EOF.
_fp_blocks "cat <<\\EOF
EOF
git push --force"
# The delimiter stops at the `;`, so nothing in this command terminates the
# heredoc and the shell would refuse to run any of it. A reader that keeps the
# `;` in the delimiter sees the last line as a terminator instead, and reports
# this as text. Malformed input is not scanned partially — it blocks.
_fp_blocks "cat <<X; echo hi
git push --force
X;"
# A continuation line belongs to the command it continues.
_fp_blocks "git push \\
--force origin main"

# ------------------------- a force-push the guard cannot read, so it refuses ------

_flow_test_begin "block-force-push — a substitution is not text"
# What a substitution expands to is a command, so a line carrying one cannot be
# vouched for. Each of these really force-pushes.
_fp_blocks 'echo "$(git push --force)"'
_fp_blocks 'echo `git push --force`'
_fp_blocks 'x="$(git push --force)"'
_fp_blocks 'git push "$(git push --force)"'
_fp_blocks 'git push --force$(true)'
# Double quotes do not make a substitution text, so all three spellings still
# block when they sit inside one.
_fp_blocks 'echo "`git push --force`"'
_fp_blocks 'echo "${x:-git push --force}"'
# ANSI-C quoting is a substitution of sorts too, and decoding it is out of
# scope, so a line carrying one is refused rather than guessed at.
_fp_blocks "eval \$'\\x67it push --force'"

_flow_test_begin "block-force-push — a push behind a wrapper is still a push"
# The guard does not enumerate wrappers. It names only the commands that CANNOT
# run a command; an unlisted one blocks rather than allows, so a wrapper nobody
# thought of is covered by default.
_fp_blocks 'caffeinate git push --force'
_fp_blocks 'su root git push --force'
_fp_blocks '/usr/bin/sudo git push --force'
_fp_blocks '/usr/bin/env git push --force'
_fp_blocks "env -S 'git push --force'"
_fp_blocks "bash -lc 'git push --force'"
_fp_blocks "bash -ec 'git push --force'"
_fp_blocks "sh -xc 'git push --force'"
# A command is only accounted for if it cannot run a program. `sort` looks
# harmless and is not: --compress-program runs the program it names.
_fp_blocks "sort --compress-program='git push --force' bigfile"
# The same command with no push on the line is ordinary work, not a wrapper.
_fp_allows "sort --compress-program=tmpf bigfile"

_flow_test_begin "block-force-push — a heredoc body is a script when a shell reads it"
# A body is text when `cat > file <<EOF` writes it, and the script when a shell
# is fed it. The consumer decides, not the syntax.
_fp_blocks 'bash <<EOF
git push --force
EOF'
# `<<` inside arithmetic is a shift, not a heredoc opener: reading it as one
# desyncs the body tracker and skips the push below it.
_fp_blocks 'echo $((1<<2))
git push --force
2'

# ----------------------------------------------------------- shapes that must not crash --

_flow_test_begin "block-force-push — a malformed command is not a crash"
# set -euo pipefail plus a failing grep exits non-zero, and the harness reads a
# non-2 exit as an allow. So a parse path that can error is a path that silently
# stops guarding — these assert the hook survives them.
assert_equal "0" "$(_fp_exit "")" "an empty command is allowed, not an error"
# Input that ends mid-construct is not vouched for: an unclosed quote and an
# unterminated heredoc both leave the scan unable to see the whole command, so
# both block rather than allow.
assert_equal "2" "$(_fp_exit "git push 'unbalanced")" "an unclosed quote blocks rather than allowing"
assert_equal "2" "$(_fp_exit "cat <<EOF
git push --force")" "an unterminated heredoc blocks rather than allowing"
_fp_blocks "git push --force 'unbalanced"

# A crash is a silent allow, so every pathological input must still land on one
# of the two documented exits. These assert the exit code is one of them; the
# ones that carry a real force flag are asserted to block.
_fp_exit_is_documented() {
  local code
  code=$(_fp_exit "$1")
  case "$code" in
    0|2) _flow_assert_pass "documented exit ($code): $(printf '%s' "$1" | head -c 40)" ;;
    *)   _flow_assert_fail "undocumented exit $code on: $(printf '%s' "$1" | head -c 40)" ;;
  esac
}

_flow_test_begin "block-force-push — a pathological command is not a crash"
_fp_exit_is_documented "$(printf 'x%.0s' $(seq 1 20000))"
_fp_exit_is_documented "echo '$(printf 'y%.0s' $(seq 1 20000))'"
_fp_exit_is_documented 'echo "a'"'"'b"c'"'"'d"e'
_fp_exit_is_documented 'git push \'
_fp_exit_is_documented "cat <<"
_fp_exit_is_documented 'git push `'
_fp_exit_is_documented 'git push $('
_fp_exit_is_documented 'echo ${a${b${c${d}}}}'
_fp_exit_is_documented "$(printf '\n')"
# A tab separates words, so a tab-separated push is still a push.
_fp_blocks "$(printf 'git\tpush\t--force')"
# Recursion through shells and eval is bounded, so a payload that nests past the
# bound blocks instead of running away.
_fp_exit_is_documented "sh -c 'sh -c \"sh -c \\\"sh -c \\\\\\\"git push --force\\\\\\\"\\\"\"'"

# ------------------------------------------------------ the refusal's message --

_flow_test_begin "block-force-push — the refusal keeps its three lines"
# The message is the operator's only description of what happened and what to do
# instead, so it is pinned rather than left to change with the implementation.
_msg=$(_fp_stderr "git push --force origin main")
assert_contains "BLOCKED: Force-push detected. This is a Tier 3 action that requires manual execution." "$_msg" "the first line"
assert_contains "If you need to force-push, ask the user to run the command directly." "$_msg" "the second line"
assert_contains "Note: --force-with-lease is allowed as a safe alternative." "$_msg" "the third line"
# And nothing is printed when the command is allowed, so a caller reading stderr
# cannot mistake silence for a refusal.
assert_equal "" "$(_fp_stderr "git push origin main")" "no message when the push is allowed"
