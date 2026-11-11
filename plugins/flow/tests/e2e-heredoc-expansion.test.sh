# shellcheck shell=bash
# End-to-end: a heredoc body that bash expands, or a line that only looks
# like a heredoc, is read as the commands it runs by every hook that judges a
# Bash command (#344).
#
# Each scenario feeds a hook the PreToolUse payload Claude Code sends for a
# Bash call and reads its decision. The hooks run are the ones that read the
# command with the first reading of lib/command-parse.sh (_bd_strip_noncode):
# block-destructive.sh and block-unchecked-merge.sh; and block-force-push.sh,
# whose own scanner decides where a heredoc body starts. tier-gate.sh has its
# scenarios in e2e-tier-gate.test.sh (tg-unquoted-body-subst,
# tg-escaped-heredoc). The artifact for each scenario is written to
# $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the scenarios:
#   H1 an unquoted body (<<EOF, <<-EOF) handed to a text sink (cat, tee,
#      echo, printf, gh, a commit message through "$(cat <<EOF)") is dropped
#      as text, though bash runs its $(...) or backquotes before the sink
#      reads anything, so the rm, merge or force push in them is never
#      checked
#   H2 the reverse: a quoted body (<<'EOF', <<"EOF", <<\EOF), or an escaped
#      \$( or \` in an unquoted one, which bash leaves as text, is read as
#      commands and refused
#   H3 a backslash before << (\<<'EOF', \<<EOF) is read as a heredoc, though
#      bash reads it as a literal < and a < redirection from the file EOF, so
#      the commands on the lines after it are dropped as a body
#   H4 the reverse: two backslashes before << (\\<<'EOF'), a literal
#      backslash and then a heredoc, stop being one, and its body is refused
#   H5 one hook is fixed and another is not
#   H6 a quote in the text of an unquoted body (an apostrophe in prose:
#      it's ... isn't) pairs with another and hides the substitution between
#      them, or a substitution the parser cannot follow to its end (inside
#      ${x:-...}, holding a case pattern's ) or a quoted ")") is dropped
#   H7 a backslash-newline in an unquoted body, which bash removes before it
#      expands the body, splits a $ from the ( after it ($\ then (rm -rf ~)
#      on the next line) or a command inside a substitution in two, so the
#      rm, merge or force push is read as text; or the reverse, an escaped
#      backslash before a newline ($\\) is joined and refused
#   H8 a ) inside a ${...} within a substitution ($(echo ${x:-)}; rm -rf ~))
#      is read as the end of the substitution, so the commands after it are
#      read as text

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

DELETE_HOOK=hooks/scripts/block-destructive.sh
MERGE_HOOK=hooks/scripts/block-unchecked-merge.sh
PUSH_HOOK=hooks/scripts/block-force-push.sh

_payload() { jq -cn --arg c "$1" --arg cwd "$E2E_REPO" '{session_id:"e2e-344",cwd:$cwd,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }

# _scenario <name> <hook> <purpose>, then lines "refused|allowed|<command>"
# on stdin, each command with \n, \t and \\ escapes. Every command runs in
# the one scratch repository of the scenario.
_scenario() {
  local want c
  _flow_test_begin "$1"
  e2e_new "$1"
  e2e_describe "$3"
  e2e_repo feature/issue-344-e2e
  while IFS='|' read -r want c; do
    c=$(printf '%b' "$c")
    e2e_run_hook "$2" "$(_payload "$c")"
    case "$want" in
      refused) e2e_expect_equal 2 "$E2E_RC" "the hook's exit status (2 refuses) for: $c" ;;
      allowed) e2e_expect_equal 0 "$E2E_RC" "the hook's exit status (0 allows) for: $c" ;;
    esac
  done
  e2e_expect_clean_edges
}

_scenario hx-rm-unquoted-body "$DELETE_HOOK" \
  "an rm -rf ~ in a \$(...) or backquote of an unquoted body is refused whichever sink reads the body (H1, H5), also between two apostrophes of its prose and inside \${x:-...}, a case or a quoted ) (H6); a quoted body, an escaped \\\$( or text around a \$(date) stays text (H2)" <<'EOF'
refused|cat <<EOF\n$(rm -rf ~)\nEOF
refused|cat <<EOF\n`rm -rf ~`\nEOF
refused|cat <<-EOF\n\tnotes $(rm -rf ~)\n\tEOF
refused|tee notes.md <<EOF\n$(rm -rf ~)\nEOF
refused|gh issue comment 5 --body-file - <<EOF\n$(rm -rf ~)\nEOF
refused|git commit -m "$(cat <<EOF\nfix: x\n\n$(rm -rf ~)\nEOF\n)"
refused|cat <<EOF\nit's $(rm -rf ~) isn't\nEOF
refused|cat <<EOF\nit's ${x:-$(rm -rf ~)} isn't\nEOF
refused|cat <<EOF\nit's $(case x in a) rm -rf ~;; esac) isn't\nEOF
refused|cat <<EOF\nit's $(echo ")" ; rm -rf ~) isn't\nEOF
allowed|cat <<'EOF'\n$(rm -rf ~)\nEOF
allowed|cat <<"EOF"\n`rm -rf ~`\nEOF
allowed|cat <<EOF\n\\$(rm -rf ~) and \\`rm -rf ~\\`\nEOF
allowed|cat <<EOF\nrm -rf ~ on ${BRANCH} in $HOME\nEOF
allowed|cat <<EOF\nit's $(date), and rm -rf ~ isn't run\nEOF
allowed|git commit -m "$(cat <<'EOF'\nfix: x\n\n$(rm -rf ~)\nEOF\n)"
EOF

_scenario hx-rm-shell-owner "$DELETE_HOOK" \
  "a heredoc read by a shell in a group after a printing command, or by bash with a \$(cat ...) argument, is a script, and its rm -rf ~ is refused; the same text in a gh body written with \${ISSUE} or after echo \"\${HOME}\" is a body, and stays text" <<'EOF'
refused|(echo start; bash) <<'EOF'\nrm -rf ~\nEOF
refused|(tee /dev/null; bash) <<'EOF'\nrm -rf ~\nEOF
refused|bash -s "$(cat args.txt)" <<'EOF'\nrm -rf ~\nEOF
allowed|gh issue comment ${ISSUE} --body-file - <<'EOF'\nclean with rm -rf ~/build first\nEOF
allowed|echo "${HOME}" && cat <<'EOF'\nclean with rm -rf ~/build first\nEOF
EOF

_scenario hx-rm-escaped-introducer "$DELETE_HOOK" \
  "the line after \\<<'EOF' or \\<<EOF is a command and its rm -rf ~ is refused (H3); after \\\\<<'EOF' it is a body cat reads (H4)" <<'EOF'
refused|cat \\<<'EOF'\nrm -rf ~\nEOF
refused|cat \\<<EOF\nrm -rf ~\nEOF
refused|gh issue comment 5 --body-file - \\<<'EOF'\nrm -rf ~\nEOF
allowed|cat \\\\<<'EOF'\nrm -rf ~\nEOF
EOF

_scenario hx-merge-unquoted-body "$MERGE_HOOK" \
  "an unchecked gh pr merge in a \$(...) or backquote of an unquoted body is refused (H1, H5), and on the line after \\<<'EOF' (H3); a quoted body stays text (H2)" <<'EOF'
refused|cat <<EOF\n$(gh pr merge 5)\nEOF
refused|cat <<EOF\n`gh pr merge 5`\nEOF
refused|cat \\<<'EOF'\ngh pr merge 5\nEOF
allowed|cat <<'EOF'\n$(gh pr merge 5)\nEOF
allowed|cat <<EOF\n\\$(gh pr merge 5)\nEOF
EOF

_scenario hx-push-unquoted-body "$PUSH_HOOK" \
  "a force push in a \$(...) or backquote of an unquoted body is refused (H1, H5); a quoted body stays text (H2)" <<'EOF'
refused|cat <<EOF\n$(git push --force origin main)\nEOF
refused|cat <<EOF\nnotes `git push --force origin main`\nEOF
refused|tee notes.md <<EOF\n$(git push --force origin main)\nEOF
allowed|cat <<'EOF'\n$(git push --force origin main)\nEOF
allowed|cat <<EOF\ngit push --force origin main is what we avoid\nEOF
EOF

_scenario hx-rm-line-join "$DELETE_HOOK" \
  "an rm -rf ~ in a substitution split by a backslash-newline of an unquoted body (\$\\ then (rm -rf ~), or rm \\ then -rf ~ inside one) is refused (H7, H5); \$\\\\ before a newline and a quoted body stay text" <<'EOF'
refused|cat <<EOF\n$\\\n(rm -rf ~)\nEOF
refused|cat <<EOF\nnotes $\\\n(rm -rf ~) today\nEOF
refused|cat <<EOF\n$(rm \\\n-rf ~)\nEOF
allowed|cat <<EOF\n$\\\\\n(rm -rf ~)\nEOF
allowed|cat <<'EOF'\n$\\\n(rm -rf ~)\nEOF
EOF

_scenario hx-rm-subst-brace "$DELETE_HOOK" \
  "an rm -rf ~ after a \${x:-)} inside a substitution of an unquoted body is refused, also in a group of it (H8, H5); a plain \${BRANCH:-main} in prose stays text" <<'EOF'
refused|cat <<EOF\n$(echo ${x:-)}; rm -rf ~)\nEOF
refused|cat <<EOF\n$( (echo ${x:-)}); rm -rf ~)\nEOF
allowed|cat <<EOF\nbuilt $(date +%F) from ${BRANCH:-main}; rm -rf ~ is not run\nEOF
EOF

_scenario hx-merge-line-join "$MERGE_HOOK" \
  "an unchecked gh pr merge in a substitution split by a backslash-newline (H7) or after a \${x:-)} inside one (H8) of an unquoted body is refused (H5)" <<'EOF'
refused|cat <<EOF\n$\\\n(gh pr merge 5)\nEOF
refused|cat <<EOF\n$(gh pr \\\nmerge 5)\nEOF
refused|cat <<EOF\n$(echo ${x:-)}; gh pr merge 5)\nEOF
allowed|cat <<EOF\n$\\\\\n(gh pr merge 5)\nEOF
EOF

_scenario hx-push-line-join "$PUSH_HOOK" \
  "a force push in a substitution split by a backslash-newline (H7) or after a \${x:-)} inside one (H8) of an unquoted body is refused (H5)" <<'EOF'
refused|cat <<EOF\n$\\\n(git push --force origin main)\nEOF
refused|cat <<EOF\n$(git push \\\n--force origin main)\nEOF
refused|cat <<EOF\n$(echo ${x:-)}; git push --force origin main)\nEOF
allowed|cat <<'EOF'\n$\\\n(git push --force origin main)\nEOF
EOF
