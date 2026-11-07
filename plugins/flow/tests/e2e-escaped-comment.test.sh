# shellcheck shell=bash
# End-to-end: a command hidden after an escaped separator and a `#`, or after
# a `(#` that zsh reads as a glob, is checked like any other command (#304).
#
# Each scenario feeds a hook the PreToolUse payload Claude Code sends for a
# Bash call and reads its decision. Every place in the plugin that decides
# where a comment starts in a Bash command is run:
#   - lib/command-parse.sh (_bd_strip_noncode), through block-destructive.sh
#     and tier-gate.sh
#   - block-force-push.sh's own scanner
#   - ask-issue-create.sh's comment removal
# The artifact for each scenario is written to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the scenarios:
#   C1 a `#` after an escaped space (`x\ #y`) is read as a comment, so the
#      command after the next `;` is never checked
#   C2 the same after an escaped `;` (`x\;#y`)
#   C3 the same after `(` inside a word (`/(#|tmp)`), which zsh, the shell
#      Claude Code uses on macOS, reads as a glob and not a comment
#   C4 a real comment stops being one: an escaped backslash followed by a real
#      `;` (`x\\;#y`), or `ls # rm -rf ~`, is refused
#   C5 one of the readers is fixed and another is not
#   C6 a `#` right after the `)` that closes a `$( )`, `$(( ))` or `<( )`
#      inside a word is read as a comment, though the word goes on, so the
#      command after the next `;` is never checked
#   C7 a `#` right after the `)` that closes a subshell stops being a comment
#   C8 a `)` the parenthesis count pairs with the wrong `(` is read as
#      closing a subshell, so the `#` after it cuts the rest of the line: a
#      `)` inside `${x:-)}`, a case pattern's `)` inside a `$( )`, or an
#      escaped `\)` inside a `$( )` that the force-push scanner's span
#      skipper takes for the end of the substitution. When the count cannot
#      be trusted the rest of the line must stay code.
#   C9 the same across a line break: a `${`, a `$(` inside double quotes or
#      a backquote opened on one line is still open on the next, where a
#      `)#` is part of its word to bash, but a reader that forgets the open
#      span at the line break reads the `#` as a comment and never checks
#      the command after the span closes
#   C10 a `#` inside `(( ))` arithmetic or inside `[[ ]]` (a `=~` regex),
#      after a `)` (`(1)#2`, `(a)#x`), a space or a `(`, is read as a
#      comment, though bash and zsh read it as part of the expression and
#      run the command after the next `;`; the same when the `((` or `[[`
#      opened on an earlier line, or when an inner `(1+(2))` holds a `))`
#      that does not close the `((`. A real comment after the `))` or `]]`
#      that closes it must stay one (C4).

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

DELETE_HOOK=hooks/scripts/block-destructive.sh
PUSH_HOOK=hooks/scripts/block-force-push.sh
ISSUE_HOOK=hooks/scripts/ask-issue-create.sh
GATE_HOOK=hooks/scripts/tier-gate.sh

_payload() { jq -cn --arg c "$1" --arg cwd "$E2E_REPO" '{session_id:"e2e-304",cwd:$cwd,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }

# _case <name> <hook> <command> <refused|allowed|asks|silent> <purpose>
_case() {
  _flow_test_begin "$1"
  e2e_new "$1"
  e2e_describe "$5"
  e2e_repo feature/issue-304-e2e
  [ -n "${_CASE_SETUP:-}" ] && "$_CASE_SETUP"
  e2e_run_hook "$2" "$(_payload "$3")"
  case "$4" in
    refused) e2e_expect_equal 2 "$E2E_RC" "the hook's exit status (2 refuses)" ;;
    allowed) e2e_expect_equal 0 "$E2E_RC" "the hook's exit status (0 allows)" ;;
    asks) e2e_expect_out '"permissionDecision":"ask"' ;;
    silent) e2e_expect_no_out '"permissionDecision":"ask"' ;;
  esac
  e2e_expect_clean_edges
}

# --- the destructive-command check (lib/command-parse.sh) --------------------
_case esc-rm-plain "$DELETE_HOOK" 'rm -rf ~' refused "the plain form is refused (the baseline)"
_case esc-rm-space "$DELETE_HOOK" 'ls x\ #y ; rm -rf ~' refused "an escaped space before # (C1)"
_case esc-rm-semicolon "$DELETE_HOOK" 'ls x\;#y ; rm -rf ~' refused "an escaped ; before # (C2)"
_case esc-rm-glob "$DELETE_HOOK" 'ls /(#|tmp) ; rm -rf ~' refused "a (# that zsh reads as a glob (C3)"
_case esc-rm-real-escaped-bs "$DELETE_HOOK" 'ls x\\;#y ; touch M' allowed "an escaped backslash, then a real ; and a comment: nothing destructive (C4)"
_case esc-rm-real-comment "$DELETE_HOOK" 'ls # rm -rf ~' allowed "a real comment that mentions rm (C4)"
_case esc-rm-subshell-comment "$DELETE_HOOK" '(# rm -rf ~
ls)' allowed "a comment that opens a subshell's first word is still a comment (C4)"

# --- the force-push check (block-force-push.sh) -------------------------------
_case esc-push-plain "$PUSH_HOOK" 'git push --force origin main' refused "the plain form is refused (the baseline)"
_case esc-push-space "$PUSH_HOOK" 'ls x\ #y ; git push --force origin main' refused "an escaped space before # (C1, C5)"
_case esc-push-semicolon "$PUSH_HOOK" 'ls x\;#y ; git push --force origin main' refused "an escaped ; before # (C2, C5)"
_case esc-push-glob "$PUSH_HOOK" 'ls /(#|tmp) ; git push --force origin main' refused "a (# that zsh reads as a glob (C3, C5)"
_case esc-push-real-comment "$PUSH_HOOK" 'ls # git push --force origin main' allowed "a real comment that mentions a force push (C4)"
_case esc-push-real-escaped-bs "$PUSH_HOOK" 'ls x\\;#y ; git push --force origin main' allowed "an escaped backslash, then a real ; that starts a comment holding the push (C4)"

# --- the tier gate (lib/command-parse.sh, as tier-gate.sh reads it) ----------
_case esc-gate-merge "$GATE_HOOK" 'ls x\ #y ; gh pr merge 7 --squash' asks "a merge hidden after an escaped space is asked about (C1, C5)"
_case esc-gate-comment "$GATE_HOOK" 'ls # gh pr merge 7 --squash' silent "a merge in a real comment is not (C4)"

# --- a # after the ) of a substitution inside a word (#304) ------------------
_case esc-rm-subst "$DELETE_HOOK" 'echo $(true)#x ; rm -rf ~' refused "a # after the ) that closes \$( ) is part of the word (C6)"
_case esc-rm-arith "$DELETE_HOOK" 'echo $((1))#x ; rm -rf ~' refused "a # after the )) that closes \$(( )) is part of the word (C6)"
_case esc-rm-procsub "$DELETE_HOOK" 'cat <(true)#x ; rm -rf ~' refused "a # after the ) that closes <( ) is part of the word (C6)"
_case esc-rm-subshell-close "$DELETE_HOOK" '(ls)#x ; rm -rf ~' allowed "a # after the ) that closes a subshell is a comment (C7)"
_case esc-push-subst "$PUSH_HOOK" 'echo $(true)#x ; git push --force origin main' refused "a # after the ) that closes \$( ) (C6, C5)"
_case esc-push-arith "$PUSH_HOOK" 'echo $((1))#x ; git push --force origin main' refused "a # after the )) that closes \$(( )) (C6, C5)"
_case esc-push-procsub "$PUSH_HOOK" 'cat <(true)#x ; git push --force origin main' refused "a # after the ) that closes <( ) (C6, C5)"
_case esc-push-subshell-close "$PUSH_HOOK" '(ls)#x ; git push --force origin main' allowed "a # after the ) that closes a subshell is a comment (C7)"
_case esc-gate-subst "$GATE_HOOK" 'echo $(true)#x ; gh pr merge 7 --squash' asks "a merge after \$(true)#x is asked about (C6, C5)"
_case esc-gate-subshell-close "$GATE_HOOK" '(ls)#x ; gh pr merge 7 --squash' silent "a merge in the comment after a subshell is not (C7)"

# --- a ) the parenthesis count cannot place (C8) -----------------------------
MERGE_HOOK=hooks/scripts/block-unchecked-merge.sh
_case esc-rm-param-paren "$DELETE_HOOK" '( echo ${x:-)#} ; rm -rf ~ )' refused "a ) inside \${x:-)} does not close the subshell (C8)"
_case esc-rm-case-subst "$DELETE_HOOK" '( echo $(case y in y) true;; esac)#x ; rm -rf ~ )' refused "a case pattern's ) inside \$( ) does not close the subshell (C8)"
_case esc-rm-escaped-subst "$DELETE_HOOK" '( echo $(echo a\)b)#x ; rm -rf ~ )' refused "an escaped ) inside \$( ) does not close the subshell (C8)"
_case esc-push-escaped-subst "$PUSH_HOOK" '( echo $(echo a\)b)#x ; git push --force origin main )' refused "an escaped ) inside \$( ) is not the end of the substitution (C8, C5)"
_case esc-push-case-subst "$PUSH_HOOK" '( echo $(case y in y) true;; esac)#x ; git push --force origin main )' refused "a case pattern's ) inside \$( ) (C8, C5)"
_case esc-push-param-paren "$PUSH_HOOK" '( echo ${x:-)#} ; git push --force origin main )' refused "a ) inside \${x:-)} (C8, C5)"
_case esc-gate-param-paren "$GATE_HOOK" '( echo ${x:-)#} ; gh pr merge 5 )' asks "a merge after \${x:-)#} is asked about (C8, C5)"
_case esc-merge-case-subst "$MERGE_HOOK" '( echo $(case y in y) true;; esac)#x ; gh pr merge 5 )' refused "an unchecked merge after a case pattern inside \$( ) is refused (C8, C5)"

# --- a span opened on one line and still open on the next (C9) ---------------
NL='
'
BQ='`'
_case esc-rm-param-nl "$DELETE_HOOK" "( echo \${x:-${NL}(a)#} ; rm -rf ~ )" refused "a \${x:- still open on the next line keeps (a)#} one word (C9)"
_case esc-rm-backquote-nl "$DELETE_HOOK" "( echo ${BQ}echo${NL}(a)#x${BQ} ; rm -rf ~ )" refused "a backquote still open on the next line (C9)"
_case esc-rm-quoted-subst-nl "$DELETE_HOOK" "echo \"\$(echo \"${NL}(a)#x\" ; rm -rf ~ )\"" refused "a \$( inside double quotes, whose quotes nest, still open on the next line (C9)"
_case esc-push-param-nl "$PUSH_HOOK" "( echo \${x:-${NL}(a)#} ; git push --force origin main )" refused "a \${x:- still open on the next line (C9, C5)"
_case esc-push-backquote-nl "$PUSH_HOOK" "( echo ${BQ}echo${NL}(a)#x${BQ} ; git push --force origin main )" refused "a backquote still open on the next line (C9, C5)"
_case esc-gate-param-nl "$GATE_HOOK" "( echo \${x:-${NL}(a)#} ; gh pr merge 5 )" asks "a merge after a \${x:- still open on the next line is asked about (C9, C5)"
_case esc-gate-backquote-nl "$GATE_HOOK" "( echo ${BQ}echo${NL}(a)#x${BQ} ; gh pr merge 5 )" asks "a merge after a backquote still open on the next line is asked about (C9, C5)"
_case esc-merge-param-nl "$MERGE_HOOK" "( echo \${x:-${NL}(a)#} ; gh pr merge 5 )" refused "an unchecked merge after a \${x:- still open on the next line is refused (C9, C5)"
_case esc-merge-backquote-nl "$MERGE_HOOK" "( echo ${BQ}echo${NL}(a)#x${BQ} ; gh pr merge 5 )" refused "an unchecked merge after a backquote still open on the next line is refused (C9, C5)"
_case esc-rm-subshell-close-nl "$DELETE_HOOK" "ls${NL}(ls)#x ; rm -rf ~" allowed "a # after a subshell on a line after one with no span is still a comment (C7, C9)"
_case esc-push-subshell-close-nl "$PUSH_HOOK" "ls${NL}(ls)#x ; git push --force origin main" allowed "the same for the force-push check (C7, C9)"

# --- a # inside (( )) arithmetic or a [[ ]] regex (C10) ----------------------
_case esc-rm-arith-cmd "$DELETE_HOOK" '(( x = (1)#2 )) ; rm -rf ~' refused "a # after a ) inside (( )) is part of the expression (C10)"
_case esc-rm-arith-space "$DELETE_HOOK" '(( x = 1 #2 )) ; rm -rf ~' refused "a # after a space inside (( )) is part of the expression (C10)"
_case esc-rm-arith-inner "$DELETE_HOOK" '(( x = (1+(2)) #2 )) ; rm -rf ~' refused "an inner )) does not close the (( (C10)"
_case esc-rm-arith-nl "$DELETE_HOOK" "((${NL}(1)#2 )) ; rm -rf ~" refused "a (( opened on the line before is still open (C10)"
_case esc-rm-arith-nl-expr "$DELETE_HOOK" "(( x = 1 +${NL}(1)#2 )) ; rm -rf ~" refused "the same with the expression begun on the line before (C10)"
_case esc-rm-arith-if "$DELETE_HOOK" 'if (( (1)#2 )); then rm -rf ~; fi' refused "a (( after if (C10)"
_case esc-rm-arith-while "$DELETE_HOOK" 'echo a | while (( (1)#2 )); do :; done; rm -rf ~' refused "a (( after while in a pipeline (C10)"
_case esc-rm-regex "$DELETE_HOOK" '[[ a =~ (a)#x ]] ; rm -rf ~' refused "a # after a ) inside a [[ =~ ]] regex (C10)"
_case esc-rm-regex-open "$DELETE_HOOK" '[[ a =~ (#y) ]] ; rm -rf ~' refused "a # after a ( inside a [[ =~ ]] regex (C10)"
_case esc-rm-regex-nl "$DELETE_HOOK" "[[ a =~ x${NL}(a)#x ]] ; rm -rf ~" refused "a [[ opened on the line before is still open (C10)"
_case esc-rm-arith-comment "$DELETE_HOOK" '(( x = 1 )) # rm -rf ~' allowed "a real comment after the )) that closes (( (C10, C4)"
_case esc-rm-regex-comment "$DELETE_HOOK" '[[ -f x ]] # rm -rf ~' allowed "a real comment after the ]] that closes [[ (C10, C4)"
_case esc-rm-for-comment "$DELETE_HOOK" 'for ((i=0;i<3;i++)); do echo $i; done # rm -rf ~' allowed "a real comment after a for (( )) loop (C10, C4)"
_case esc-push-arith-cmd "$PUSH_HOOK" '(( x = (1)#2 )) ; git push --force origin main' refused "a # after a ) inside (( )) (C10, C5)"
_case esc-push-arith-space "$PUSH_HOOK" '(( x = 1 #2 )) ; git push --force origin main' refused "a # after a space inside (( )) (C10, C5)"
_case esc-push-arith-if "$PUSH_HOOK" 'if (( (1)#2 )); then git push --force origin main; fi' refused "a (( after if (C10, C5)"
_case esc-push-arith-nl "$PUSH_HOOK" "((${NL}(1)#2 )) ; git push --force origin main" refused "a (( opened on the line before (C10, C5)"
_case esc-push-regex "$PUSH_HOOK" '[[ a =~ (a)#x ]] ; git push --force origin main' refused "a # after a ) inside a [[ =~ ]] regex (C10, C5)"
_case esc-push-arith-comment "$PUSH_HOOK" '(( x = 1 )) # git push --force origin main' allowed "a real comment after the )) that closes (( (C10, C4)"
_case esc-push-regex-comment "$PUSH_HOOK" '[[ -f x ]] # git push --force origin main' allowed "a real comment after the ]] that closes [[ (C10, C4)"
_case esc-merge-arith "$MERGE_HOOK" '(( x = (1)#2 )) ; gh pr merge 5' refused "an unchecked merge after a # inside (( )) is refused (C10, C5)"
_case esc-merge-regex "$MERGE_HOOK" '[[ a =~ (a)#x ]] ; gh pr merge 5' refused "an unchecked merge after a # inside a [[ =~ ]] regex is refused (C10, C5)"
_case esc-gate-arith "$GATE_HOOK" '(( x = (1)#2 )) ; gh pr merge 5' asks "a merge after a # inside (( )) is asked about (C10, C5)"
_case esc-gate-regex "$GATE_HOOK" '[[ a =~ (a)#x ]] ; gh pr merge 5' asks "a merge after a # inside a [[ =~ ]] regex is asked about (C10, C5)"
_case esc-gate-arith-comment "$GATE_HOOK" '(( x = 1 )) # gh pr merge 5' silent "a merge in a real comment after (( )) is not (C10, C4)"

# --- gh issue create during an active goal (ask-issue-create.sh) ------------
_issue_goal() { e2e_goal issue-304 feature/issue-304-e2e active true; }
_CASE_SETUP=_issue_goal
_case esc-issue-plain "$ISSUE_HOOK" 'gh issue create --title t --body b' asks "the plain form asks during an active goal (the baseline)"
_case esc-issue-space "$ISSUE_HOOK" 'ls x\ #y ; gh issue create --title t --body b' asks "an issue created after an escaped space and # still asks (C1, C5)"
_case esc-issue-comment "$ISSUE_HOOK" 'ls # gh issue create --title t' silent "an issue creation in a real comment does not ask (C4)"
_CASE_SETUP=""
