# shellcheck shell=bash
# End-to-end: the run-time tier check. hooks/scripts/tier-session-start.sh
# (SessionStart) writes the lines Claude Code runs before each Bash command;
# they put hooks/shims first on PATH. hooks/scripts/tier-gate.sh (PreToolUse)
# reads the command text, asks, and records what it asked about. The git and
# gh wrappers (hooks/scripts/lib/tier-runtime.sh) see the arguments the
# program gets, and refuse a merge, a release or a tag push that the gate did
# not ask about in that Bash call.
#
# A scenario does what Claude Code does for one Bash call: it feeds the gate
# the PreToolUse payload, and, when the gate did not ask or the scenario
# approves the ask, runs the command with `bash -c` after the session's
# lines. git is real, and pushes over an ext:: remote to a bare repository in
# the scratch directory (a remote that is not a local path, as a GitHub
# remote is not). gh is a fake that records its arguments in gh-calls.log.
#
# The property every bypass scenario checks: a merge, a release or a tag push
# happens only in a Bash call whose gate asked. Either the gate asked, or the
# action was refused and did not happen.
#
# Ways it can be wrong, written down before the scenarios:
#   W1 a command shape the gate does not read (a script file fed to a shell,
#      a pipe into a shell, an alias, eval of built text, an interpreter's
#      subprocess, find -exec, xargs) merges, releases or pushes a tag
#      without an ask
#   W2 an approved merge, release or tag push is refused at run time
#   W3 a record from an earlier call whose ask was refused approves a later
#      call that the gate did not ask about
#   W4 a branch push, a read (gh pr view, git push --dry-run) or a tag push
#      to a local path is refused, or a branch push is refused when its tier
#      is journal
#   W5 a Tier 2 action set to confirm runs without an ask; one set to journal
#      gets no breadcrumb when the gate missed it, or two when it did not
#   W6 unsetting FLOW_TIER_DIR or FLOW_TIER_CALL turns the check off
#   W7 the session lines are written twice, are not written, put the
#      wrappers after the real programs on PATH, or fail under zsh
#   W8 a push whose refs cannot be listed (an unreachable remote) is run as
#      if it sent no tag
#   W9 a gh or git alias, a gh api call (REST or GraphQL from a file) or a
#      push with --follow-tags, push.followTags, GIT_CONFIG_* or a mirror
#      remote is not seen as the action it is

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

if ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_test_begin "tier runtime: PyYAML prerequisite"
  _flow_assert_pass "SKIP: PyYAML not installed"
  return 0
fi

TR_SID=sess-e2e-317
# The real gh, for `gh alias list` (it reads the scenario's config, no
# network): the wrapper asks it for aliases.
TR_REAL_GH=$(command -v gh 2>/dev/null) || TR_REAL_GH=""
ASK='"permissionDecision":"ask"'

# _tr_setup <name> <purpose> [settings json] — a scratch repository on an
# issue branch with a flow journal directory, a tag v1, an ext:: remote
# `origin` (an empty bare repository), a fake gh, and the session set up by
# the shipped SessionStart hook.
_tr_setup() {
  _flow_test_begin "$1"
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo feature/issue-317-e2e
  mkdir -p "$E2E_REPO/.decisions" "$E2E_DIR/fakegh"
  if [ -n "${3:-}" ]; then
    mkdir -p "$E2E_REPO/.claude"
    printf '%s\n' "$3" > "$E2E_REPO/.claude/settings.flow.json"
  fi
  (
    _e2e_git_env
    cd "$E2E_DIR" || exit 1
    git init -q --bare remote.git || exit 1
    # A remote that takes push options, as GitHub does: a push with -o
    # then reaches it rather than failing for that reason.
    git --git-dir=remote.git config receive.advertisePushOptions true
    cd "$E2E_REPO" || exit 1
    git config protocol.ext.allow always
    git remote add origin "ext::git %s $E2E_DIR/remote.git"
    git tag -a -m v1 v1
  ) || _flow_assert_fail "$1: could not set up the remote"
  # The fake gh logs its arguments, and what it reads on stdin when an
  # argument names stdin (`-`, `@-`, `@/dev/stdin`).
  cat > "$E2E_DIR/fakegh/gh" <<FAKE
#!/bin/sh
[ "\$1 \$2" = "alias list" ] && GH_CONFIG_DIR="$E2E_HOME/.config/gh" exec "$TR_REAL_GH" alias list
printf '%s\\n' "\$*" >> "$E2E_DIR/gh-calls.log"
for a in "\$@"; do
  case "\$a" in -|*@-|*@/dev/stdin) printf 'stdin: %s\\n' "\$(cat)" >> "$E2E_DIR/gh-calls.log"; break ;; esac
done
echo FAKE-GH "\$@"
FAKE
  chmod +x "$E2E_DIR/fakegh/gh"
  : > "$E2E_DIR/gh-calls.log"
  e2e_run_hook CLAUDE_ENV_FILE="$E2E_DIR/env.sh" hooks/scripts/tier-session-start.sh \
    "$(jq -cn --arg s "$TR_SID" '{session_id:$s,hook_event_name:"SessionStart",source:"startup"}')"
}

# _tr_gate <command> — the PreToolUse payload for this Bash call. Sets TR_ASKED.
_tr_gate() {
  e2e_run_hook hooks/scripts/tier-gate.sh \
    "$(jq -cn --arg c "$1" --arg cwd "$E2E_REPO" --arg s "$TR_SID" '{session_id:$s,cwd:$cwd,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}')"
  case "$E2E_OUT" in *"$ASK"*) TR_ASKED=1 ;; *) TR_ASKED=0 ;; esac
  printf 'gate asked: %s\n' "$TR_ASKED" | _e2e_art
}

# _tr_exec <command> [shell] — run the command as the Bash tool does, after
# the session's lines. Sets E2E_OUT, E2E_ERR, E2E_RC.
# The shell is started as Claude Code starts it: the session's lines, then
# the command inside `eval '...'`, each ' in it written '"'"', then
# `< /dev/null && pwd -P >| <file>`. TR_SHELL (default bash) picks the shell.
_tr_exec() {
  local sh=${2:-${TR_SHELL:-bash}} sq="'" esc="'\"'\"'"
  printf 'run under %s: %s\n' "$sh" "$1" | _e2e_art
  _e2e_exec env TR_ENV="$E2E_DIR/env.sh" TR_FAKE="$E2E_DIR/fakegh" \
    "$sh" -c "PATH=\"\$TR_FAKE:\$PATH\"; . \"\$TR_ENV\"; eval '${1//$sq/$esc}' < /dev/null && pwd -P >| \"\$TR_FAKE/cwd\""
  printf -- '--- expectations\n' | _e2e_art
}

# _tr_call <command> [deny] — one Bash call: the gate, then the command
# unless the gate asked and the scenario says the person refused.
_tr_call() {
  _tr_gate "$1"
  if [ "$TR_ASKED" = 1 ] && [ "${2:-}" = deny ]; then
    printf 'the person refused the ask; the command did not run\n' | _e2e_art
    E2E_OUT=""; E2E_ERR=""; E2E_RC=""
    return 0
  fi
  _tr_exec "$1"
}

_tr_remote_tags() { git --git-dir="$E2E_DIR/remote.git" for-each-ref --format='%(refname:short)' refs/tags 2>/dev/null | tr '\n' ' '; }

# _tr_tag_guarded <tag> — the tag reached the remote only if the gate asked;
# when it did not, the command was refused by the wrapper.
_tr_tag_guarded() {
  local tags
  tags=" $(_tr_remote_tags)"
  if [ "$TR_ASKED" = 1 ]; then
    e2e_expect_equal 1 "$TR_ASKED" "the gate asked (the command ran as approved)"
    return 0
  fi
  case "$tags" in
    *" $1 "*) _e2e_result fail "tag $1 is not on the remote, since nothing asked (remote tags:$tags)" ;;
    *) _e2e_result pass "tag $1 is not on the remote, since nothing asked" ;;
  esac
  # The wrapper's exit status reaches the command's only when nothing in
  # between (python, find) drops it, so the refusal is checked on stderr.
  e2e_expect_err "needs your confirmation"
}

# _tr_gh_guarded <argument text> — the fake gh got these arguments only if
# the gate asked.
_tr_gh_guarded() {
  if [ "$TR_ASKED" = 1 ]; then
    e2e_expect_equal 1 "$TR_ASKED" "the gate asked (the command ran as approved)"
    return 0
  fi
  if grep -qF -- "$1" "$E2E_DIR/gh-calls.log"; then
    _e2e_result fail "gh did not run '$1', since nothing asked"
  else
    _e2e_result pass "gh did not run '$1', since nothing asked"
  fi
  # The wrapper's exit status reaches the command's only when nothing in
  # between (python, find) drops it, so the refusal is checked on stderr.
  e2e_expect_err "needs your confirmation"
}

_tr_trail() { cat "$E2E_REPO"/.decisions/auto-log/issue-317.*.md 2>/dev/null; }

# --- the session lines (W7) ---------------------------------------------------

_tr_setup tr-session-lines "the SessionStart hook writes lines that put the wrappers first on PATH and set the session's directory; a second start of the same session adds nothing"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_equal "" "$E2E_OUT" "stdout"
e2e_expect_file_has ../env.sh "hooks/shims"
e2e_expect_file_has ../env.sh "sessions/$TR_SID/tier"
TR_LINES=$(wc -l < "$E2E_DIR/env.sh" | tr -d ' ')
e2e_run_hook CLAUDE_ENV_FILE="$E2E_DIR/env.sh" hooks/scripts/tier-session-start.sh \
  "$(jq -cn --arg s "$TR_SID" '{session_id:$s,hook_event_name:"SessionStart",source:"resume"}')"
e2e_expect_equal "$TR_LINES" "$(wc -l < "$E2E_DIR/env.sh" | tr -d ' ')" "line count after a second start"
for TR_SH in $E2E_FENCE_SHELLS; do
  _tr_exec 'command -v git; command -v gh' "$TR_SH"
  e2e_expect_line "$E2E_ACTIVE_PLUGIN/hooks/shims/git"
  e2e_expect_line "$E2E_ACTIVE_PLUGIN/hooks/shims/gh"
done

_flow_test_begin tr-session-no-env-file
e2e_new tr-session-no-env-file
e2e_describe "without CLAUDE_ENV_FILE, or with a session id that is not a plain name, the hook writes nothing and says nothing"
e2e_repo main
e2e_run_hook hooks/scripts/tier-session-start.sh '{"session_id":"abc","hook_event_name":"SessionStart"}'
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_equal "" "$E2E_OUT$E2E_ERR" "output"
e2e_run_hook CLAUDE_ENV_FILE="$E2E_DIR/env.sh" hooks/scripts/tier-session-start.sh '{"session_id":"../x","hook_event_name":"SessionStart"}'
e2e_expect_equal 0 "$E2E_RC" "exit status"
[ -e "$E2E_DIR/env.sh" ] && _e2e_result fail "no env file written for a session id with a slash" \
  || _e2e_result pass "no env file written for a session id with a slash"

# --- approved actions run, and ordinary commands are untouched (W2, W4) -------

_tr_setup tr-approved-tag-push "a plain tag push: the gate asks, and once approved the wrapper lets it run"
_tr_call 'git push origin v1'
e2e_expect_equal 1 "$TR_ASKED" "the gate asked"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_equal "v1 " "$(_tr_remote_tags)" "remote tags"

_tr_setup tr-approved-merge "a plain merge: the gate asks, and once approved gh runs it"
_tr_call 'gh pr merge 7 --squash'
e2e_expect_equal 1 "$TR_ASKED" "the gate asked"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_equal "pr merge 7 --squash" "$(cat "$E2E_DIR/gh-calls.log")" "gh's arguments"

_tr_setup tr-approved-unread "a merge in a command the gate cannot read (a variable program): it asks, and once approved it runs"
_tr_call 'G=gh; $G pr merge 7'
e2e_expect_equal 1 "$TR_ASKED" "the gate asked"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_equal "pr merge 7" "$(cat "$E2E_DIR/gh-calls.log")" "gh's arguments"

_tr_setup tr-branch-push "a branch push with the default journal tier, hidden from the gate in a script file: it runs, and the wrapper writes the breadcrumb"
_tr_call "printf 'git push origin HEAD:refs/heads/main\n' > s.sh; bash s.sh"
e2e_expect_equal 0 "$TR_ASKED" "the gate did not ask"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_equal "main" "$(git --git-dir="$E2E_DIR/remote.git" for-each-ref --format='%(refname:short)' refs/heads)" "remote branches"
case "$(_tr_trail)" in
  *"tiers.push (journal, runtime)"*) _e2e_result pass "the trail has the wrapper's breadcrumb" ;;
  *) _e2e_result fail "the trail has the wrapper's breadcrumb" ;;
esac

_tr_setup tr-branch-push-gate-journaled "a plain branch push: the gate writes the breadcrumb, and the wrapper does not write a second one (W5)"
_tr_call 'git push origin HEAD:refs/heads/main'
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_equal 1 "$(_tr_trail | grep -c 'tiers.push')" "breadcrumbs for the push"

_tr_setup tr-reads "reads run through the wrappers untouched: gh pr view, git status, a dry-run tag push, a pipe into grep, which bash"
_tr_call "printf 'gh pr view 7\ngit status --short\ngit push --dry-run origin v1\n' > r.sh; bash r.sh | grep -c . ; which bash >/dev/null"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_equal "pr view 7" "$(cat "$E2E_DIR/gh-calls.log")" "gh's arguments"
e2e_expect_equal "" "$(_tr_remote_tags)" "remote tags"

_tr_setup tr-local-remote "a tag push to a remote that is a path on this machine leaves nothing on the network: it runs without an ask"
( _e2e_git_env; cd "$E2E_REPO" && git remote add localr "$E2E_DIR/remote.git" )
_tr_call "printf 'git push localr v1\n' > s.sh; bash s.sh"
e2e_expect_equal 0 "$TR_ASKED" "the gate did not ask"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_equal "v1 " "$(_tr_remote_tags)" "remote tags"

# --- tag pushes the gate cannot see, and the ones it reads (W1, W9) -----------

TR_N=0
_tr_tag_case() {   # <purpose> <command>; every command pushes tag v1
  TR_N=$((TR_N + 1))
  _tr_setup "tr-tag-$TR_N" "tag push shape: $1"
  _tr_call "$2"
  _tr_tag_guarded v1
}
_tr_tag_case "a script file fed to bash" "printf 'git push origin v1\n' > s.sh; bash s.sh"
_tr_tag_case "a script file sourced" "printf 'git push origin v1\n' > s.sh; . ./s.sh"
_tr_tag_case "echo piped into bash" "echo 'git push origin v1' | bash"
_tr_tag_case "a pipe into a shell inside a group" "echo 'git push origin v1' | { :; bash; }"
_tr_tag_case "a here-string to bash" "bash <<<'git push origin v1'"
_tr_tag_case "a here-string piped into bash" "cat <<<'git push origin v1' | bash"
_tr_tag_case "bash -c inside a substitution" "x=\$(bash -c 'git push origin v1' 2>&1)"
_tr_tag_case "a process substitution read by bash" "bash < <(echo 'git push origin v1')"
_tr_tag_case "an output process substitution into bash" "echo 'git push origin v1' > >(bash)"
_tr_tag_case "a substitution glued to a word" "git push origin v1\$(true)"
_tr_tag_case "quotes split inside the words" "\"git\" \"pu\"sh origin \"v\"'1'"
_tr_tag_case "backslashes inside the words" "g\\it pu\\sh origin v\\1"
_tr_tag_case "the refspec in a variable" "T=v1; git push origin \$T"
_tr_tag_case "the option in an unquoted default" "git push \${X:- --tags} origin"
_tr_tag_case "the command in \"\$@\"" "set -- git push origin v1; \"\$@\""
_tr_tag_case "the command in an array" "A=(git push origin v1); \"\${A[@]}\""
_tr_tag_case "eval of built text" "eval \"\$(printf 'git %s origin v1' push)\""
_tr_tag_case "eval of a variable read by name" "c='git push origin v1'; eval \"\$c\""
_tr_tag_case "python's subprocess" "python3 -c 'import subprocess; subprocess.run([\"git\", \"push\", \"origin\", \"v1\"])'"
_tr_tag_case "find -exec" "find . -maxdepth 0 -exec git push origin v1 \\;"
_tr_tag_case "xargs appending the tag" "echo v1 | xargs git push origin"
_tr_tag_case "env and command in front" "env command git push origin v1"
_tr_tag_case "sh -c with the tag as \$0" "sh -c 'git push origin \"\$0\"' v1"
_tr_tag_case "a git alias set on the command line" "git -c alias.pt='push --tags' pt origin"
_tr_tag_case "a git alias set earlier in the command" "git config alias.pt 'push --tags' && git pt origin"
_tr_tag_case "an alias hidden in a script" "printf 'git config alias.pt \"push --tags\"\ngit pt origin\n' > s.sh; bash s.sh"
_tr_tag_case "push.followTags set in a script" "printf 'git config push.followTags true\ngit push origin HEAD:refs/heads/main\n' > s.sh; bash s.sh"
_tr_tag_case "--follow-tags abbreviated, in a script" "printf 'git push --follow-tag origin HEAD:refs/heads/main\n' > s.sh; bash s.sh"
_tr_tag_case "GIT_CONFIG_* turning on followTags, in a script" "printf 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=push.followTags GIT_CONFIG_VALUE_0=true git push origin HEAD:refs/heads/main\n' > s.sh; bash s.sh"
_tr_tag_case "a mirror remote set in a script" "printf 'git config remote.origin.mirror true\ngit push origin\n' > s.sh; bash s.sh"
_tr_tag_case "a refs/tags refspec in a script" "printf 'git push origin HEAD:refs/tags/v1\n' > s.sh; bash s.sh"
_tr_tag_case "the remote's push refspec, in a script" "printf 'git config remote.origin.push refs/tags/v1:refs/tags/v1\ngit push origin\n' > s.sh; bash s.sh"
_tr_tag_case "FLOW_TIER_DIR and FLOW_TIER_CALL removed (W6)" "printf 'git push origin v1\n' > s.sh; env -u FLOW_TIER_DIR -u FLOW_TIER_CALL bash s.sh"

_tr_setup tr-tag-delete "deleting a tag on the remote from a script: refused, and the tag stays (W1)"
( _e2e_git_env; cd "$E2E_REPO" && git push -q origin v1 2>/dev/null )
_tr_call "printf 'git push origin :refs/tags/v1\n' > d.sh; bash d.sh"
e2e_expect_equal 0 "$TR_ASKED" "the gate did not ask"
e2e_expect_equal 1 "$E2E_RC" "exit status"
e2e_expect_equal "v1 " "$(_tr_remote_tags)" "remote tags"

_tr_setup tr-unlistable-push "a push whose refs git cannot list (the remote does not answer) is refused as a possible tag push, with git's reason (W8)"
( _e2e_git_env; cd "$E2E_REPO" && git remote add dead "ext::sh -c false" )
_tr_call "printf 'git push dead HEAD:refs/heads/main\n' > s.sh; bash s.sh"
e2e_expect_equal 0 "$TR_ASKED" "the gate did not ask"
e2e_expect_equal 1 "$E2E_RC" "exit status"
e2e_expect_err "whose refs could not be listed"

# --- merges and releases the gate cannot see (W1, W9) -------------------------

TR_M=0
_tr_gh_case() {   # <purpose> <command> <gh arguments that must not run unasked>
  TR_M=$((TR_M + 1))
  _tr_setup "tr-gh-$TR_M" "gh shape: $1"
  _tr_call "$2"
  _tr_gh_guarded "$3"
}
_tr_gh_case "a merge in a script file" "printf 'gh pr merge 7 --squash\n' > m.sh; bash m.sh" "pr merge"
_tr_gh_case "a merge piped into bash" "echo 'gh pr merge 7' | bash" "pr merge"
_tr_gh_case "a merge through python" "python3 -c 'import subprocess; subprocess.run([\"gh\", \"pr\", \"merge\", \"7\"])'" "pr merge"
_tr_gh_case "a merge with options before the subcommand, in a script" "printf 'gh pr -R o/r merge 7\n' > m.sh; bash m.sh" "merge 7"
_tr_gh_case "a release in a script file" "printf 'gh release create v9 --notes x\n' > m.sh; bash m.sh" "release create"
_tr_gh_case "a release delete in a script file" "printf 'gh release delete v1 --yes\n' > m.sh; bash m.sh" "release delete"
_tr_gh_case "a REST merge through gh api, in a script" "printf 'gh api -X PUT repos/o/r/pulls/7/merge\n' > m.sh; bash m.sh" "pulls/7/merge"
_tr_gh_case "a REST merge, method in a bundle, in a script" "printf 'gh api -iXPUT /repos/o/r/pulls/7/merge\n' > m.sh; bash m.sh" "pulls/7/merge"
_tr_gh_case "a release through gh api with an implied POST, in a script" "printf 'gh api repos/o/r/releases -f tag_name=v9\n' > m.sh; bash m.sh" "releases"
_tr_gh_case "a tag ref through gh api, in a script" "printf 'gh api repos/o/r/git/refs -f ref=refs/tags/v9 -f sha=abc\n' > m.sh; bash m.sh" "git/refs"
_tr_gh_case "a GraphQL merge from a query file, in a script" "printf 'mutation { mergePullRequest(input: {pullRequestId: \"x\"}) { clientMutationId } }' > q.graphql; printf 'gh api graphql -F query=@q.graphql\n' > m.sh; bash m.sh" "graphql"
_tr_gh_case "a GraphQL query read from stdin, in a script" "printf 'echo q | gh api graphql -F query=@-\n' > m.sh; bash m.sh" "graphql"

_tr_setup tr-gh-alias "a gh alias for pr merge, in gh's config file: the wrapper reads the alias (W9)"
mkdir -p "$E2E_HOME/.config/gh"
printf 'aliases:\n    mm: pr merge\n' > "$E2E_HOME/.config/gh/config.yml"
_tr_call "gh mm 7"
_tr_gh_guarded "mm 7"

_tr_setup tr-gh-graphql-read "a GraphQL query that only reads, through a script: it runs (W4)"
_tr_call "printf 'gh api graphql -f query=\"query { viewer { login } }\"\n' > m.sh; bash m.sh"
e2e_expect_equal 0 "$E2E_RC" "exit status"
case "$(cat "$E2E_DIR/gh-calls.log")" in *graphql*) _e2e_result pass "gh ran the query" ;; *) _e2e_result fail "gh ran the query" ;; esac

# --- a refused ask approves nothing later (W3) ---------------------------------

_tr_setup tr-stale-record "the gate asks about a merge and the person refuses; the next call, which the gate does not ask about, merges from a script: refused"
_tr_call 'gh pr merge 7' deny
e2e_expect_equal 1 "$TR_ASKED" "the first gate asked"
_tr_call "printf 'gh pr merge 7\n' > m.sh; bash m.sh"
_tr_gh_guarded "pr merge"

_tr_setup tr-record-one-call "an approved merge's record is used up by its own call: the next call merges from a script without an ask, refused"
_tr_call 'gh pr merge 7'
e2e_expect_equal 0 "$E2E_RC" "the approved merge ran"
_tr_call "printf 'gh pr merge 8\n' > m.sh; bash m.sh"
_tr_gh_guarded "pr merge 8"

# --- Tier 2 set to confirm (W5) --------------------------------------------------

_tr_setup tr-push-confirm "tiers.push is confirm: a branch push the gate reads asks and runs once approved; one hidden in a script is refused" '{"tiers":{"push":"confirm"}}'
_tr_call 'git push origin HEAD:refs/heads/main'
e2e_expect_equal 1 "$TR_ASKED" "the gate asked"
e2e_expect_equal 0 "$E2E_RC" "exit status"
_tr_call "printf 'git push origin HEAD:refs/heads/second\n' > s.sh; bash s.sh"
e2e_expect_equal 0 "$TR_ASKED" "the gate did not ask"
e2e_expect_equal 1 "$E2E_RC" "exit status"
e2e_expect_err "tiers.push"
e2e_expect_equal "main" "$(git --git-dir="$E2E_DIR/remote.git" for-each-ref --format='%(refname:short)' refs/heads | tr '\n' ' ' | sed 's/ $//')" "remote branches"

_tr_setup tr-prcreate-journal "a pull request created from a script with the default journal tier: it runs, with the wrapper's breadcrumb"
_tr_call "printf 'gh pr create --title t --body b\n' > m.sh; bash m.sh"
e2e_expect_equal 0 "$E2E_RC" "exit status"
case "$(_tr_trail)" in
  *"tiers.prCreate (journal, runtime)"*) _e2e_result pass "the trail has the wrapper's breadcrumb" ;;
  *) _e2e_result fail "the trail has the wrapper's breadcrumb" ;;
esac

_tr_setup tr-record-moved "the session line moves the record to the Bash call that starts after the ask: a second command started without the gate in between (one whose gate could not clear the record) does not reuse the approval (W3)"
_tr_gate 'gh pr merge 7'
e2e_expect_equal 1 "$TR_ASKED" "the gate asked"
_tr_exec 'gh pr merge 7'
e2e_expect_equal 0 "$E2E_RC" "the approved merge ran"
_tr_exec "printf 'gh pr merge 8\n' > m.sh; bash m.sh"
TR_ASKED=0
_tr_gh_guarded "pr merge 8"

# --- findings of the first review of #317 -------------------------------------
#   W10 two Bash calls in flight take each other's record: a call the gate did
#       not ask about runs the merge the person is still being asked about
#   W11 one approval covers every action of its kind in the call: an approved
#       merge lets a second, unseen merge through
#   W12 a journaled `gh release create --verify-tag` lets any other release
#       action of the call through
#   W13 the wrapper's own dry run becomes a real push (--no-dry-run), or an
#       -n / --dry-run that a later option cancels, or one that is another
#       option's value, skips the check
#   W14 a git global option the wrapper does not know, an alias written with
#       quotes, or a `!` alias whose arguments name the push, hides the push
#   W15 a gh alias with $1 placeholders, or one named like gh's own `co`,
#       hides a merge
#   W16 a #fragment on a gh api endpoint hides a merge or a release
#   W17 a query read from a FIFO can hand gh another document than the one
#       read; stdin given to gh is consumed by the wrapper
#   W18 two flow wrapper directories on PATH run each other for ever

_tr_setup tr-parallel-calls "W10: call B (a merge in a script) is read by the gate, then call A (a plain merge) asks; B starts while A's ask is open: B is refused, and A runs once approved"
_tr_gate "printf 'gh pr merge 2\n' > m.sh; bash m.sh"
TR_B_ASKED=$TR_ASKED
_tr_gate 'gh pr merge 1'
e2e_expect_equal 1 "$TR_ASKED" "A's gate asked"
_tr_exec "printf 'gh pr merge 2\n' > m.sh; bash m.sh"
TR_ASKED=$TR_B_ASKED
_tr_gh_guarded "pr merge 2"
_tr_exec 'gh pr merge 1'
e2e_expect_equal 0 "$E2E_RC" "A's approved merge ran"
e2e_expect_equal 1 "$(grep -c 'pr merge 1' "$E2E_DIR/gh-calls.log")" "A's merge ran once"

_tr_setup tr-approval-count "W11: the gate asks about one merge, and the approved call also merges a second pull request from a script: the second is refused"
_tr_call "gh pr merge 1 && printf 'gh pr merge 2\n' > m.sh && bash m.sh"
e2e_expect_equal 1 "$TR_ASKED" "the gate asked"
e2e_expect_equal 1 "$(grep -c 'pr merge 1' "$E2E_DIR/gh-calls.log")" "the approved merge ran"
e2e_expect_equal 0 "$(grep -c 'pr merge 2' "$E2E_DIR/gh-calls.log")" "the second merge did not run"
e2e_expect_err "needs your confirmation"

# For the --verify-tag journal, origin must be a GitHub repository the gate
# can name and reach: its URL is rewritten to the bare repository.
_tr_setup tr-verify-tag-only "W12: gh release create v1 --verify-tag with v1 on origin is journaled by the gate; a release delete in a script of the same call is refused"
(
  _e2e_git_env
  cd "$E2E_REPO" || exit 1
  git remote set-url origin https://github.com/o/r.git
  git config url."$E2E_DIR/remote.git".insteadOf https://github.com/o/r.git
  git push -q origin v1 2>/dev/null
)
_tr_call "gh release create v1 --verify-tag --notes x && printf 'gh release delete v3 -y\n' > p.sh && bash p.sh"
e2e_expect_equal 0 "$TR_ASKED" "the gate did not ask"
e2e_expect_equal 1 "$(grep -c 'release create v1' "$E2E_DIR/gh-calls.log")" "the journaled release ran"
e2e_expect_equal 0 "$(grep -c 'release delete' "$E2E_DIR/gh-calls.log")" "the release delete did not run"
e2e_expect_err "needs your confirmation"

_tr_tag_case "W13: --no-dry-run in a script" "printf 'git push --no-dry-run origin v1\n' > s.sh; bash s.sh"
_tr_tag_case "W13: --no-dr, abbreviated, in a script" "printf 'git push --no-dr origin v1\n' > s.sh; bash s.sh"
_tr_tag_case "W13: --dry-run then --no-dry-run, in a script" "printf 'git push --dry-run --no-dry-run origin v1\n' > s.sh; bash s.sh"
_tr_tag_case "W13: -n then --no-dry-run, in a script" "printf 'git push -n --no-dry-run origin v1\n' > s.sh; bash s.sh"
_tr_tag_case "W13: -n as --repo's value, in a script" "printf 'git push --repo -n origin v1\n' > s.sh; bash s.sh"
_tr_tag_case "W14: a global option the wrapper does not know, in a script" "printf 'git --no-literal-pathspecs push origin v1\n' > s.sh; bash s.sh"
_tr_tag_case "W14: an alias whose first word is quoted, set in a script" "printf 'git config alias.pq '\"'\"'\"push\" origin v1'\"'\"'\ngit pq\n' > s.sh; bash s.sh"
_tr_tag_case "W14: a ! alias whose arguments name the push" "git config alias.run '!git' && git run push origin v1"

_tr_setup tr-gh-alias-args "W15: a gh alias with a \$1 placeholder (p: pr \$1 7) expanded with merge"
mkdir -p "$E2E_HOME/.config/gh"
printf 'aliases:\n    p: pr $1 7\n' > "$E2E_HOME/.config/gh/config.yml"
_tr_call "gh p merge"
_tr_gh_guarded "p merge"

_tr_setup tr-gh-alias-co "W15: co, gh's own alias, redefined in the config file as pr merge"
mkdir -p "$E2E_HOME/.config/gh"
printf 'aliases:\n    co: pr merge\n' > "$E2E_HOME/.config/gh/config.yml"
_tr_call "gh co 7"
_tr_gh_guarded "co 7"

_tr_gh_case "W16: a REST merge with a #fragment, in a script" "printf 'gh api -X PUT \"repos/o/r/pulls/1/merge#x\"\n' > m.sh; bash m.sh" "pulls/1/merge"
_tr_gh_case "W16: a release with a #fragment, in a script" "printf 'gh api -X POST \"repos/o/r/releases#x\" -f tag_name=v2\n' > m.sh; bash m.sh" "releases"
_tr_gh_case "W17: a query read from a FIFO, in a script" "printf 'mkfifo q; (printf \"query{viewer{login}}\" > q; printf \"mutation{mergePullRequest(input:{pullRequestId:1}){clientMutationId}}\" > q) & w=\$!; gh api graphql -F query=@q; kill \$w 2>/dev/null\n' > m.sh; bash m.sh" "graphql"

_tr_setup tr-stdin-kept "W17: a GraphQL query on stdin (-F query=@/dev/stdin): the gate asks, and once approved gh reads the whole query; the wrapper reads none of it"
_tr_call "printf 'query{viewer{login}}' | gh api graphql -F query=@/dev/stdin"
e2e_expect_equal 1 "$TR_ASKED" "the gate asked"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_equal 1 "$(grep -c 'stdin: query{viewer{login}}' "$E2E_DIR/gh-calls.log")" "gh read the query"

_tr_setup tr-two-wrapper-dirs "W18: a second flow's wrapper directory on PATH (a nested session, another version): git and gh still run, within 20 seconds"
mkdir -p "$E2E_DIR/flowcopy"
cp -R "$E2E_ACTIVE_PLUGIN/hooks" "$E2E_DIR/flowcopy/hooks"
# A watchdog process kills the program after 20 s: an alarm does not
# survive the exec loop this scenario guards against.
TR_TIMEOUT='perl -e '"'"'$p = fork; if (!$p) { exec @ARGV; exit 127 } $SIG{ALRM} = sub { kill 9, $p; exit 124 }; alarm 20; waitpid $p, 0; exit($? >> 8)'"'"
_tr_exec "PATH=\"$E2E_DIR/flowcopy/hooks/shims:\$PATH\"; $TR_TIMEOUT git --version && $TR_TIMEOUT gh pr view 1"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_out "git version"
e2e_expect_out "FAKE-GH pr view 1"

# W19: a heredoc body with a bare delimiter is not data: bash runs the
# $(...) in it, even when the text goes to gh. W16 for the merge guard: a
# #fragment does not hide a merge endpoint.
_tr_setup tr-heredoc-substitution "W19: cat <<EOF | gh pr create --body-file - with \$(gh pr merge 7) in the body: the gate asks and the merge guard refuses"
TR_HD=$(printf 'cat <<EOF | gh pr create --title t --body-file -\nnotes $(gh pr merge 7 --squash)\nEOF')
_tr_gate "$TR_HD"
e2e_expect_equal 1 "$TR_ASKED" "the gate asked"
e2e_run_hook hooks/scripts/block-unchecked-merge.sh "$(jq -cn --arg c "$TR_HD" '{tool_input:{command:$c}}')"
e2e_expect_equal 2 "$E2E_RC" "the merge guard refuses"
TR_HD=$(printf "cat <<'EOF' | gh pr create --title t --body-file -\nnotes \$(gh pr merge 7 --squash)\nEOF")
_tr_gate "$TR_HD"
e2e_expect_equal 0 "$TR_ASKED" "with a quoted delimiter the body is data: the gate does not ask"
e2e_run_hook hooks/scripts/block-unchecked-merge.sh "$(jq -cn --arg c "$TR_HD" '{tool_input:{command:$c}}')"
e2e_expect_equal 0 "$E2E_RC" "with a quoted delimiter the merge guard allows"
e2e_run_hook hooks/scripts/block-unchecked-merge.sh "$(jq -cn '{tool_input:{command:"gh api -X PUT \"repos/o/r/pulls/1/merge#x\""}}')"
e2e_expect_equal 2 "$E2E_RC" "the merge guard refuses a merge endpoint with a #fragment"

# --- findings of the second review of #317 ------------------------------------
#   W20 an ask the person refused approves a later run of the same command
#   W21 a trailing option that takes a value (-o, --push-option) takes the
#       wrapper's --dry-run, and the check pushes for real
#   W22 a gh alias written with quotes, $1 inside a word, a YAML block or an
#       escape, or a flow-map aliases section, hides a merge
#   W23 a backslash in a git alias word hides the push
#   W24 a word put in front of the command by another hook (`rtk gh ...`)
#       stops the approved call from finding its record
#   W25 a command that extends another's text takes the other's record

_tr_setup tr-refused-then-rerun "W20: the gate asks (a query file it cannot read), the person refuses; the same command run again, now with a readable query, does not use the refused approval for the merge in its script"
TR_CMD="gh api graphql -F query=@q.graphql; printf 'gh pr merge 88\n' > s.sh; bash s.sh"
_tr_call "$TR_CMD" deny
e2e_expect_equal 1 "$TR_ASKED" "the first gate asked"
printf 'query{viewer{login}}' > "$E2E_REPO/q.graphql"
_tr_call "$TR_CMD"
e2e_expect_equal 0 "$TR_ASKED" "the second gate did not ask"
e2e_expect_equal 0 "$(grep -c 'pr merge 88' "$E2E_DIR/gh-calls.log")" "the merge did not run"
e2e_expect_err "needs your confirmation"

_tr_tag_case "W21: -o as the last word, in a script" "printf 'git push origin v1 -o\n' > s.sh; bash s.sh"
_tr_tag_case "W21: --push-option as the last word, in a script" "printf 'git push origin v1 --push-option\n' > s.sh; bash s.sh"
_tr_tag_case "W21: --receive-pack as the last word, in a script" "printf 'git push origin v1 --receive-pack\n' > s.sh; bash s.sh"
_tr_tag_case "W23: a backslash in a git alias word, set in a script" "printf 'git config alias.zz \"p\\\\\\\\ush origin v1\"\ngit zz\n' > s.sh; bash s.sh"

TR_A=0
_tr_alias_case() {   # <purpose> <config.yml body> <command>
  TR_A=$((TR_A + 1))
  _tr_setup "tr-gh-alias-form-$TR_A" "W22: $1"
  mkdir -p "$E2E_HOME/.config/gh"
  printf '%s' "$2" > "$E2E_HOME/.config/gh/config.yml"
  _tr_call "printf '%s\n' '$3' > m.sh; bash m.sh"
  _tr_gh_guarded "${3#gh }"
}
_tr_alias_case "a quoted word in the value" 'aliases:
    qa: pr "merge"
' 'gh qa 5'
_tr_alias_case "\$1 inside a word" 'aliases:
    qb: pr mer$1
' 'gh qb ge 6'
_tr_alias_case "a YAML block value" 'aliases:
    qc: |-
        pr merge
' 'gh qc 7'
_tr_alias_case "an escape in a double-quoted value" 'aliases:
    qd: "pr \x6derge"
' 'gh qd 8'
_tr_alias_case "a flow-map aliases section" 'aliases: {qe: pr merge}
' 'gh qe 9'

_tr_setup tr-prefixed-command "W24: another hook puts a word in front of the approved command (rtk gh pr merge 5): the call still finds its record and the merge runs"
mkdir -p "$E2E_DIR/fakegh"
printf '#!/bin/sh\nexec "$@"\n' > "$E2E_DIR/fakegh/rtk"; chmod +x "$E2E_DIR/fakegh/rtk"
_tr_gate 'gh pr merge 5 --squash'
e2e_expect_equal 1 "$TR_ASKED" "the gate asked"
_tr_exec 'rtk gh pr merge 5 --squash'
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_equal 1 "$(grep -c 'pr merge 5' "$E2E_DIR/gh-calls.log")" "the merge ran"

_tr_setup tr-extended-command "W25: call A (gh pr merge 1) and call B (A's text with more after it) both ask; B starts first and takes its own record, then A runs"
TR_B="gh pr merge 1 --squash''; gh pr merge 2 --squash"
_tr_gate 'gh pr merge 1 --squash'
_tr_gate "$TR_B"
e2e_expect_equal 1 "$TR_ASKED" "B's gate asked"
_tr_exec "$TR_B"
e2e_expect_equal 0 "$E2E_RC" "B ran"
_tr_exec 'gh pr merge 1 --squash'
e2e_expect_equal 0 "$E2E_RC" "A ran"
e2e_expect_equal 2 "$(grep -c 'pr merge 1' "$E2E_DIR/gh-calls.log")" "merge 1 ran in both calls"

#   W26 --end-of-options turns the wrapper's own options into refspecs, and
#       the check pushes for real
#   W27 an approved loop that merges twice is refused on the second pass
#   W28 an approved run prints anything of the wrapper's own on stderr

_tr_setup tr-end-of-options "W26: git push origin --end-of-options v1, in a script, with refs named like the wrapper's options: refused, nothing on the remote"
( _e2e_git_env; cd "$E2E_REPO" && for r in --dry-run --porcelain --no-verify --no-quiet; do git update-ref "refs/heads/$r" HEAD 2>/dev/null; done )
_tr_call "printf 'git push origin --end-of-options v1\n' > s.sh; bash s.sh"
e2e_expect_equal 0 "$TR_ASKED" "the gate did not ask"
e2e_expect_equal "" "$(git --git-dir="$E2E_DIR/remote.git" for-each-ref --format='%(refname)' | tr '\n' ' ')" "the remote's refs"
e2e_expect_err "needs your confirmation"

_tr_setup tr-approved-loop "W27: the gate asks about a loop that merges two pull requests; once approved, both run"
_tr_call 'for p in 7 8; do gh pr merge $p --squash; done'
e2e_expect_equal 1 "$TR_ASKED" "the gate asked"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_equal 2 "$(grep -c 'pr merge' "$E2E_DIR/gh-calls.log")" "both merges ran"

_tr_setup tr-quiet-approved "W28: an approved merge prints nothing of the wrapper's own on stderr"
_tr_call 'gh pr merge 7 --squash'
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_equal "" "$E2E_ERR" "stderr"

# --- findings of the third review of #317 -------------------------------------
#   W29 a word like "for" or "xargs" inside a message makes every approved
#       action uncounted
#   W30 a git alias whose expansion starts with -p or -c hides the push
#   W31 a gh config whose aliases section has a comment after `aliases:`, or
#       a value continued on the next line, hides a merge
#   W32 a // or a %XX in a gh api path hides a merge or a release from the
#       wrapper

_tr_setup tr-prose-for "W29: an approved merge whose subject says 'fix for login', with a second merge in a script: the second is refused"
_tr_call "gh pr merge 5 --squash --subject 'fix for login'; printf 'gh pr merge 66 --admin\n' > s.sh; bash s.sh"
e2e_expect_equal 1 "$TR_ASKED" "the gate asked"
e2e_expect_equal 0 "$(grep -c 'pr merge 66' "$E2E_DIR/gh-calls.log")" "the second merge did not run"
e2e_expect_err "needs your confirmation"

_tr_tag_case "W30: a git alias that starts with -p" "git -c alias.zz='-p push origin v1' zz"
_tr_tag_case "W30: a git alias that starts with -c push.followTags=true" "git config alias.zc '-c push.followTags=true push' && git zc origin HEAD:refs/heads/main"

_tr_alias_case "a comment after aliases:" 'aliases: # mine
    qf: pr merge
' 'gh qf 5'
_tr_alias_case "a value continued on the next line" 'aliases:
    qg: pr
        merge
' 'gh qg 5'

_tr_gh_case "W32: a // in a merge path, in a script" "printf 'gh api -X PUT repos/o/r//pulls/1/merge\n' > m.sh; bash m.sh" "pulls/1/merge"
_tr_gh_case "W32: %6D for m in a merge path, in a script" "printf 'gh api -X PUT repos/o/r/pulls/1/%%6Derge\n' > m.sh; bash m.sh" "6Derge"
_tr_gh_case "W32: a // in a release path, in a script" "printf 'gh api repos/o/r//releases -f tag_name=v9\n' > m.sh; bash m.sh" "releases"

#   W33 the env-file lines or the record match behave differently under zsh,
#       the shell Claude Code uses on macOS; a GH_REPO aimed elsewhere
#       reuses a journaled --verify-tag; a refused command's text at the end
#       of a later command approves it

if command -v zsh >/dev/null 2>&1; then
  TR_SHELL=zsh
  _tr_setup tr-zsh-approved "W33: under zsh, an approved merge runs and a hidden one is refused"
  _tr_call "gh pr merge 1 --squash && printf 'gh pr merge 2\n' > m.sh && bash m.sh"
  e2e_expect_equal 1 "$(grep -c 'pr merge 1' "$E2E_DIR/gh-calls.log")" "the approved merge ran"
  e2e_expect_equal 0 "$(grep -c 'pr merge 2' "$E2E_DIR/gh-calls.log")" "the hidden merge did not run"
  _tr_setup tr-zsh-prefixed "W33: under zsh, an approved merge rewritten with rtk in front still runs"
  printf '#!/bin/sh\nexec "$@"\n' > "$E2E_DIR/fakegh/rtk"; chmod +x "$E2E_DIR/fakegh/rtk"
  _tr_gate 'gh pr merge 5 --squash'
  _tr_exec 'rtk gh pr merge 5 --squash'
  e2e_expect_equal 1 "$(grep -c 'pr merge 5' "$E2E_DIR/gh-calls.log")" "the merge ran"
  unset TR_SHELL
fi

_tr_setup tr-refused-suffix "W33: the gate asks about gh pr merge 5 and the person refuses; a later command that ends with that text, and merges 99 from a script, is refused"
_tr_call 'gh pr merge 5 --squash' deny
_tr_call "printf 'gh pr merge 99 --admin\n' > s.sh; bash s.sh; echo gh pr merge 5 --squash"
e2e_expect_equal 0 "$(grep -c 'pr merge 99' "$E2E_DIR/gh-calls.log")" "the merge did not run"

_tr_setup tr-verify-tag-other-repo "W33: after a journaled gh release create v1 --verify-tag, a script running it with GH_REPO set to another repository is refused"
(
  _e2e_git_env
  cd "$E2E_REPO" || exit 1
  git remote set-url origin https://github.com/o/r.git
  git config url."$E2E_DIR/remote.git".insteadOf https://github.com/o/r.git
  git push -q origin v1 2>/dev/null
)
_tr_call "gh release create v1 --verify-tag --notes x && printf 'GH_REPO=evil/other gh release create v1 --verify-tag --notes y\n' > p.sh && bash p.sh"
e2e_expect_equal 1 "$(grep -c 'notes x' "$E2E_DIR/gh-calls.log")" "the journaled release ran"
e2e_expect_equal 0 "$(grep -c 'notes y' "$E2E_DIR/gh-calls.log")" "the other repository's release did not run"

# --- findings of the final pass -----------------------------------------------
#   W34 every gh api write is read as a merge, or a DELETE on a release is
#       not read at all; an approved gh api release is refused
#   W35 the comment gh writes in its own config makes every alias and
#       extension unreadable; a dotted alias name does too
#   W36 an approved loop inside if, { }, a function or bash -c is counted
#       once, and its second pass is refused
#   W37 a chained command the rtk hook rewrote word by word loses its record

_tr_setup tr-api-untiered "W34: gh api POST to a comment endpoint, from a script, runs: it is no tier action"
_tr_call "printf 'gh api -X POST repos/o/r/issues/5/comments -f body=hi\n' > m.sh; bash m.sh"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_equal 1 "$(grep -c 'issues/5/comments' "$E2E_DIR/gh-calls.log")" "gh ran it"
_tr_gh_case "W34: gh api DELETE on a release, in a script" "printf 'gh api -X DELETE repos/o/r/releases/1\n' > m.sh; bash m.sh" "releases/1"
_tr_setup tr-api-release-approved "W34: an approved gh api release runs"
_tr_call 'gh api repos/o/r/releases -f tag_name=v9'
e2e_expect_equal 1 "$TR_ASKED" "the gate asked"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_equal 1 "$(grep -c 'tag_name=v9' "$E2E_DIR/gh-calls.log")" "gh ran it"

_tr_setup tr-gh-config-as-written "W35: gh's config as gh writes it (a comment after the aliases, a dotted alias name): gh co 5 runs as pr checkout, and an alias for pr merge is still caught"
mkdir -p "$E2E_HOME/.config/gh"
printf '%s\n' '# What protocol to use when performing git operations. Supported values: ssh, https' 'git_protocol: https' 'aliases:' '    co: pr checkout' '    a.b: pr list' '    mm: pr merge' '# The path to a unix socket through which send HTTP connections.' 'http_unix_socket:' > "$E2E_HOME/.config/gh/config.yml"
_tr_call "printf 'gh co 5\n' > m.sh; bash m.sh"
e2e_expect_equal 0 "$E2E_RC" "gh co 5 runs"
_tr_call "printf 'gh mm 6\n' > m.sh; bash m.sh"
_tr_gh_guarded "mm 6"

TR_L=0
_tr_loop_case() {   # <purpose> <command that merges 7 and 8>
  TR_L=$((TR_L + 1))
  _tr_setup "tr-approved-loop-$TR_L" "W36: $1: approved, both merges run"
  _tr_call "$2"
  e2e_expect_equal 1 "$TR_ASKED" "the gate asked"
  e2e_expect_equal 2 "$(grep -c 'pr merge' "$E2E_DIR/gh-calls.log")" "both merges ran"
}
_tr_loop_case "a loop inside if" 'if true; then for p in 7 8; do gh pr merge $p --squash; done; fi'
_tr_loop_case "a loop inside braces" '{ for p in 7 8; do gh pr merge $p --squash; done; }'
_tr_loop_case "a function called twice" 'm() { gh pr merge $1 --squash; }; m 7; m 8'
_tr_loop_case "a loop in bash -c" "bash -c 'for p in 7 8; do gh pr merge \$p --squash; done'"

_tr_setup tr-rtk-chain "W37: an approved chain the rtk hook rewrote word by word (rtk gh ... && rtk git status) still runs"
printf '#!/bin/sh\nexec "$@"\n' > "$E2E_DIR/fakegh/rtk"; chmod +x "$E2E_DIR/fakegh/rtk"
_tr_gate 'gh pr merge 5 --squash && git status --short'
e2e_expect_equal 1 "$TR_ASKED" "the gate asked"
_tr_exec 'rtk gh pr merge 5 --squash && rtk git status --short'
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_equal 1 "$(grep -c 'pr merge 5' "$E2E_DIR/gh-calls.log")" "the merge ran"

#   W38 a gh alias whose name gh prints in quotes (yes, on, 1) is not found,
#       and its merge runs unchecked
#   W39 a function whose header and body are on separate lines is counted
#       once, and its second call is refused

_tr_alias_case "a name gh prints in quotes (yes)" 'aliases:
    "yes": pr merge
' 'gh yes 5'
_tr_alias_case "a number as the name" 'aliases:
    "1": pr merge
' 'gh 1 5'

_tr_setup tr-approved-function-lines "W39: an approved function written over several lines, called twice: both merges run"
_tr_call "$(printf 'm ( )\n{\n  gh pr merge $1 --squash\n}\nm 7; m 8')"
e2e_expect_equal 1 "$TR_ASKED" "the gate asked"
e2e_expect_equal 2 "$(grep -c 'pr merge' "$E2E_DIR/gh-calls.log")" "both merges ran"
