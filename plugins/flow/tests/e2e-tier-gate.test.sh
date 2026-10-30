# shellcheck shell=bash
# End-to-end: the tier hook (hooks/scripts/tier-gate.sh), which applies the
# tiers.* settings to a Bash command before it runs.
#
# Each scenario feeds the shipped hook a PreToolUse payload in a scratch
# repository, with the tier settings in the repository's
# .claude/settings.flow.json. gh is the harness stub and must never be called:
# the hook only reads the command.
#
# Ways it can be wrong, written down before the scenarios:
#   T1 a tier value is read from the wrong key (the brief's .flow.tiers rather
#      than the shipped .tiers), so every setting falls back to the default
#   T2 confirm does not ask, journal asks or writes nothing, autonomous writes
#      a line or asks, for one of push, prCreate, issueAssign, issueCreate
#   T3 merge or release set to journal or autonomous lets the action through
#      without asking, or asks without saying the setting was ignored
#   T4 text that only mentions an action (echo, a commit message, a comment,
#      a heredoc body, a grep pattern, a quoted bash -c argument that echoes)
#      is read as the action
#   T5 an action after &&, ;, |, inside $(...), inside bash -c '...', behind
#      VAR=value, env, timeout, xargs, a path to the program, or a line
#      continuation is missed; T5b: after a shell keyword, a group opener, a
#      function definition, coproc, or builtin
#   T6 gh api: a POST/PUT to a tiered endpoint is missed (explicit method,
#      --method=, -XPOST, lower case, implied by -f, a leading /, a full URL,
#      {owner}/{repo}), or a GET or a write to another endpoint is caught
#   T7 a gh api write whose whole endpoint is a variable is allowed, when it
#      may be a merge
#   T8 the journal line goes to the wrong file: not issue-<N>.md on an issue
#      branch, not session-<day>.md on a branch with no issue number, or a
#      .decisions directory is created in a repository that has none
#   T9 a journal-tier action in a command that also asks is journaled before
#      the person has approved it
#   T10 a value that is not autonomous|journal|confirm, a cascade that fails,
#      or a journal write that fails stops the command or says nothing
#   T11 when the hook cannot read the command (jq missing, a payload jq
#      cannot parse, parser missing),
#      a merge or release is allowed, or anything else is refused
#   T12 the hook is not registered on PreToolUse for Bash
#   T13 a tag push (--tags, --follow-tags, -c push.followTags, a refs/tags/
#      refspec, a tag's name, `tag <name>`, gh api git/refs) is read as a
#      branch push, or a branch whose name looks like a version is read as a tag
#   T14 gh release create --verify-tag is journaled although the tag is not on
#      the remote, the check fails or hangs, or it asks although the tag is there
#   T16 a push through git -C/--git-dir/--work-tree is judged (tags,
#      push.followTags, the trail) in the payload's repository instead of the
#      one named, or a -C that cannot be found lets a possible tag push through
#   T17 deleting a tag (:<tag>, --delete/-d, gh api DELETE or PATCH on
#      git/refs/tags) is read as a branch push, or a known branch is asked about
#   T15 gh api PATCH on a release or an issue's assignees, or a GraphQL
#      mutation (inline, query=@file, --input), is missed, a mutation whose
#      name holds Ref, Release or Merge among them; a read or another
#      mutation (createIssueType) is caught; an unreadable query is allowed
#   T18 a backslash inside the program, a subcommand or an option, which bash
#      removes, hides the action
#   T19 a git push option written as an abbreviation git accepts (--tag,
#      --mirr, --del) or in a short bundle (-qd) is missed, or the value of
#      -o, --recurse-submodules, --repo is read as the remote or a refspec
#   T20 a push source that is not a local branch (a tag made in the same
#      command, a glob, tags/<name>, a commit) is read as a branch push
#   T21 a remote that mirrors, or whose push refspecs send tags, set in the
#      repository or for one command, is read as a branch push
#   T22 gh release edit, delete, upload or delete-asset, or the gh api
#      equivalents, run without the release ask
#   T23 a Tier 3 action behind a program the hook does not know runs without
#      an ask, or a Tier 2 action there, echo, or printf asks
#   T24 --verify-tag is journaled when gh would create the release in another
#      repository than origin's (-R, GH_REPO, GH_HOST, a cd, a default chosen
#      on another remote)
#   T25 a redirection (2>&1, >/dev/null, > out.log) is read as a remote or a
#      refspec, so a branch push asks or a push to a mirror is read as a
#      branch push
#   T26 an option is read in one of the forms its program accepts and not
#      another: gh's -X=VALUE, -XVALUE, bundles, -f=key=value; git's
#      --config-env <key>=<var>, --repo <remote>, -f in a bundle; a wrapper's
#      bundled or abbreviated options (sudo -Eu root, env -S'...'); a
#      push.followTags value git reads as true
#   T27 a quoted argument after a program the hook does not know (watch,
#      script -c, trap, awk system()) runs a Tier 3 action unasked, or one
#      after grep or jq asks
#   T28 a cd, an export of GIT_CONFIG_*/GIT_DIR/HOME, an include.path, a git
#      config or git remote earlier in the command (also inside bash -c), or
#      words xargs appends change which repository, configuration or refspec
#      a later push uses, and the push is read as the payload's; or a word
#      that only names such a variable (echo HOME) or a config read asks
#   T25b a redirection glued to a word (--tags>/dev/null) hides the option,
#      or a quoted target (> "push log.txt") is read as a refspec
#   T29 a forced push to a destination that may be a tag only on the remote
#      is read as a branch push
#   T30 a GraphQL name inside a string or a comment is read as a field, or a
#      comment hides the field after it
#   T31 a command a shell reads from a here-string, a shell's -c argument
#      inside a substitution, a backquote inside double quotes, or an action
#      with 2>&1 in the middle of it is missed; text that cat or grep only
#      reads is read as a command; quoted words after a program the hook
#      does not know are read without limit, or past the limit unasked
#   T32 a cd into another worktree of the same repository, or to
#      $(git rev-parse --show-toplevel), asks about a branch push; a cd into
#      another repository, a worktree with its own configuration, or a push
#      whose remote the branch picks there does not ask

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

if ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_test_begin "tier gate: PyYAML prerequisite"
  _flow_assert_pass "SKIP: PyYAML not installed"
  return 0
fi

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

HOOK=hooks/scripts/tier-gate.sh
ALL_CONFIRM='{"tiers":{"push":"confirm","prCreate":"confirm","issueAssign":"confirm","issueCreate":"confirm","merge":"confirm","release":"confirm"}}'
ASK='"permissionDecision":"ask"'

# _tg_setup <name> <branch> <settings json or empty> <purpose> — a scenario in
# a scratch repository whose .decisions directory exists (the repository keeps
# a flow journal), with the given repository settings.
_tg_setup() {
  _flow_test_begin "$1"
  e2e_new "$1"
  e2e_describe "$4"
  e2e_repo "$2"
  mkdir -p "$E2E_REPO/.decisions"
  if [ -n "$3" ]; then
    mkdir -p "$E2E_REPO/.claude"
    printf '%s\n' "$3" > "$E2E_REPO/.claude/settings.flow.json"
  fi
}

_tg_run() {   # [NAME=value ...] <command>
  local envs=()
  while [ $# -gt 1 ]; do envs+=("$1"); shift; done
  TG_DAY_BEFORE=$(date +%Y-%m-%d)
  e2e_run_hook ${envs[@]+"${envs[@]}"} "$HOOK" "$(jq -cn --arg c "$1" --arg cwd "$E2E_REPO" '{cwd:$cwd,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}')"
  TG_DAY_AFTER=$(date +%Y-%m-%d)
}

# The journal files under .decisions, one name per line (sorted).
_tg_journals() { (cd "$E2E_REPO/.decisions" 2>/dev/null && ls *.md 2>/dev/null) | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'; }

# _tg_trail [<journal dir>] [<repo>] — the auto-log trail files the hook wrote,
# as paths under the repository, one per line (sorted).
_tg_trail() {
  local d="${1:-.decisions}" r="${2:-$E2E_REPO}"
  (cd "$r" 2>/dev/null && ls "$d"/auto-log/*.md 2>/dev/null) | LC_ALL=C sort
}
# The trail file for issue 42 this month, as the hook names it.
_tg_trail42() { printf '.decisions/auto-log/issue-42.%s.md' "$(date +%Y-%m)"; }

_expect_ask() {   # <text the reason must contain>
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  _E2E_EXTRA_FRAMES=1 e2e_expect_out "$ASK"
  _E2E_EXTRA_FRAMES=1 e2e_expect_out "$1"
}

_expect_silent_allow() {
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_equal "" "$E2E_OUT" "stdout"
}

# One command per tier key, as an agent would write it.
_tg_command() {
  case "$1" in
    push) printf '%s' 'git push -u origin HEAD' ;;
    prCreate) printf '%s' 'gh pr create --title "Add x" --body "Closes #42"' ;;
    issueAssign) printf '%s' 'gh issue edit 42 --add-assignee @me' ;;
    issueCreate) printf '%s' 'gh issue create --title "Bug" --body "Steps"' ;;
  esac
}

# --- T1, T2: each key, each value -------------------------------------------
for KEY in push prCreate issueAssign issueCreate; do
  CMD=$(_tg_command "$KEY")
  if _want "tg-$KEY-confirm"; then
    _tg_setup "tg-$KEY-confirm" feature/issue-42-x "{\"tiers\":{\"$KEY\":\"confirm\"}}" \
      "tiers.$KEY confirm: the hook asks, the reason names tiers.$KEY and the command, and no journal line is written (T1, T2)"
    _tg_run "$CMD"
    _expect_ask "tiers.$KEY"
    e2e_expect_out "Command: ${CMD%% --*}"
    # A quoted word keeps its quotes in the reason (escaped, inside JSON).
    [ "$KEY" = prCreate ] && e2e_expect_out 'Command: gh pr create --title \"Add x\" --body \"Closes #42\"'
    e2e_expect_equal "" "$(_tg_journals)" "journal files"
    e2e_expect_clean_edges
  fi
  if _want "tg-$KEY-journal"; then
    _tg_setup "tg-$KEY-journal" feature/issue-42-x "{\"tiers\":{\"$KEY\":\"journal\"}}" \
      "tiers.$KEY journal on branch feature/issue-42-x: no output, one breadcrumb naming tiers.$KEY and the command in the git-ignored trail .decisions/auto-log/issue-42.<YYYY-MM>.md, and the tracked .decisions/issue-42.md unchanged (T1, T2, T8)"
    printf '# Journal\n' > "$E2E_REPO/.decisions/issue-42.md"
    _tg_run "$CMD"
    _expect_silent_allow
    e2e_expect_equal "$(_tg_trail42)" "$(_tg_trail)" "trail files"
    e2e_expect_file_has "$(_tg_trail42)" "tiers.$KEY (journal) \"${CMD%% --*}"
    e2e_expect_equal 1 "$(grep -c "^<!-- auto-log: .*tiers\.$KEY (journal)" "$E2E_REPO/$(_tg_trail42)" 2>/dev/null)" "breadcrumbs"
    e2e_expect_equal "# Journal" "$(cat "$E2E_REPO/.decisions/issue-42.md")" "the tracked journal"
    e2e_expect_equal "*" "$(cat "$E2E_REPO/.decisions/auto-log/.gitignore" 2>/dev/null)" "the trail's .gitignore"
    e2e_expect_clean_edges
  fi
  if _want "tg-$KEY-autonomous"; then
    _tg_setup "tg-$KEY-autonomous" feature/issue-42-x "{\"tiers\":{\"$KEY\":\"autonomous\"}}" \
      "tiers.$KEY autonomous: no output and no journal line (T1, T2)"
    _tg_run "$CMD"
    _expect_silent_allow
    e2e_expect_equal "" "$E2E_ERR" "stderr"
    e2e_expect_equal "" "$(_tg_journals)" "journal files"
    e2e_expect_clean_edges
  fi
done

if _want tg-default-journal; then
  _tg_setup tg-default-journal feature/issue-42-x "" \
    "no repository settings: the plugin default for push, journal, applies (T1)"
  _tg_run 'git push'
  _expect_silent_allow
  e2e_expect_file_has "$(_tg_trail42)" 'tiers.push (journal) "git push"'
  e2e_expect_clean_edges
fi

if _want tg-user-tier; then
  _tg_setup tg-user-tier feature/issue-42-x "" \
    "tiers.prCreate confirm in the user's own settings and nothing in the repository: the hook asks (the cascade is read, not only the repository file) (T1)"
  e2e_user_settings '{"tiers":{"prCreate":"confirm"}}'
  _tg_run 'gh pr create --fill'
  _expect_ask "tiers.prCreate"
  e2e_expect_clean_edges
fi

# --- T3: the merge and release floor -----------------------------------------
if _want tg-merge-floor; then
  _tg_setup tg-merge-floor feature/issue-42-x '{"tiers":{"merge":"journal"}}' \
    "tiers.merge journal: the hook still asks, says Tier 3, and one stderr line names tiers.merge as ignored; no journal line (T3)"
  _tg_run 'gh pr merge 7 --repo o/r --squash'
  _expect_ask "tiers.merge"
  e2e_expect_out "Tier 3"
  e2e_expect_err 'tiers.merge is "journal", below the confirm floor'
  e2e_expect_equal 1 "$(printf '%s\n' "$E2E_ERR" | grep -c .)" "stderr lines"
  e2e_expect_equal "" "$(_tg_journals)" "journal files"
  e2e_expect_clean_edges
fi

if _want tg-release-floor; then
  _tg_setup tg-release-floor feature/issue-42-x '{"tiers":{"release":"autonomous"}}' \
    "tiers.release autonomous: the hook still asks, and one stderr line names tiers.release as ignored (T3)"
  _tg_run 'gh release create v1.2.0 --title v1.2.0 --notes "x"'
  _expect_ask "tiers.release"
  e2e_expect_err 'tiers.release is "autonomous", below the confirm floor'
  e2e_expect_clean_edges
fi

if _want tg-merge-default; then
  _tg_setup tg-merge-default feature/issue-42-x "" \
    "no settings: gh pr merge asks, gh release new asks, and nothing is printed on stderr (the default is confirm) (T3)"
  _tg_run 'gh pr merge 7 --repo o/r --squash'
  _expect_ask "tiers.merge"
  e2e_expect_equal "" "$E2E_ERR" "stderr"
  _tg_run 'gh release new v2'
  _expect_ask "tiers.release"
  e2e_expect_equal "" "$E2E_ERR" "stderr"
  e2e_expect_clean_edges
fi

# --- T4: look-alikes ---------------------------------------------------------
if _want tg-lookalikes; then
  _tg_setup tg-lookalikes feature/issue-42-x "$ALL_CONFIRM" \
    "every tier confirm; commands that only mention an action run none (including quoted text after grep, rg, jq, test and a harmless command handed to watch or trap, and gh api reads in every method spelling): each is allowed with no output and no journal file (T4, T27)"
  NL=$'\n'
  for C in \
    'echo gh pr merge 1' \
    'echo "git push origin main"' \
    'git commit -m "then gh pr create and git push"' \
    "git commit -m 'gh release create v1; git push'" \
    '# gh pr merge 1' \
    'ls # git push' \
    'grep -n "gh issue create" README.md' \
    "cat <<'EOF'${NL}gh pr merge 1 --repo o/r --squash${NL}git push${NL}EOF" \
    'bash -c "echo gh pr merge 1"' \
    'npm run git push' \
    'command -v gh' \
    'gh pr view 3' \
    'gh pr list --search "is:open gh pr create"' \
    'gh issue edit 5 --add-label bug' \
    'gh issue edit 5 --remove-assignee @me' \
    'gh release view v1' \
    'git push-helper' \
    'gh api repos/o/r/pulls/7/merge' \
    'gh api -X GET repos/o/r/releases' \
    'gh api -X POST repos/o/r/issues/3/comments -f body=x' \
    'gh api --method PATCH repos/o/r/pulls/7 -f state=closed' \
    'grep -rn "gh release create v9" plugins' \
    'rg -n "gh pr merge 1 --squash" .' \
    'jq ".body | contains(\"gh pr merge 1\")" pr.json' \
    '[ "$X" = "gh release create v9" ] && echo same' \
    'watch "git status"' \
    'watch -n 5 "gh pr view 1"' \
    "trap 'rm -f x' EXIT" \
    'gh api -X=GET repos/o/r/releases' \
    'gh api -XGET repos/o/r/pulls/7/merge' \
    'gh api --method=head repos/o/r/releases' \
    'gh api -X OPTIONS repos/o/r/issues/3/comments' \
    'gh api -X "$M" repos/o/r/issues/3/comments'; do
    _tg_run "$C"
    _expect_silent_allow
    e2e_expect_equal "" "$E2E_ERR" "stderr for: $C"
  done
  e2e_expect_equal "" "$(_tg_journals)" "journal files"
  e2e_expect_clean_edges
fi

# --- T5: chained and wrapped forms --------------------------------------------
if _want tg-chained; then
  _tg_setup tg-chained feature/issue-42-x "$ALL_CONFIRM" \
    "every tier confirm; the action sits after a separator, inside a substitution or bash -c, behind assignments, env, timeout, xargs, a path, or a line continuation: each asks, naming its key (T5)"
  NL=$'\n'
  while IFS='|' read -r KEY C; do
    _tg_run "$C"
    _expect_ask "tiers.$KEY"
  done <<EOF
push|git add -A && git commit -m "x" && git push
push|make test; git push origin HEAD
push|timeout 60 git push
push|GIT_TRACE=1 /usr/bin/git -C . push
push|time -p git push
prCreate|cd sub && URL=\$(gh pr create --fill)
prCreate|gh pr new --fill
prCreate|gh pr -R o/r create --fill
prCreate|echo ready | gh pr create --fill
issueCreate|bash -c 'gh issue create -t x -b y'
issueAssign|printf '%s\n' 5 | xargs -n 1 gh issue edit --add-assignee @me
issueAssign|gh issue edit 5 --add-assignee=octocat
release|env GH_REPO=o/r gh release create v1
merge|sudo -u ci gh pr merge 7 --repo o/r --squash
merge|GH_REPO=o/r command gh pr merge 7 --squash
EOF
  _tg_run "gh pr \\${NL}  merge 9 --repo o/r --squash"
  _expect_ask "tiers.merge"
  e2e_expect_equal "" "$(_tg_journals)" "journal files"
  e2e_expect_clean_edges
fi

# --- T5b: behind a shell keyword or a group ------------------------------------
if _want tg-keywords; then
  _tg_setup tg-keywords feature/issue-42-x "$ALL_CONFIRM" \
    "every tier confirm; the action follows if, then, else, elif, while, until, do, !, {, a function definition, coproc, select, case, a subshell, or builtin: each asks, naming its key, and a read-only gh command in the same place stays silent (T5b)"
  while IFS='|' read -r KEY C; do
    _tg_run "$C"
    _expect_ask "tiers.$KEY"
  done <<'EOF'
release|if gh release create v1 --notes x; then echo ok; fi
release|if true; then gh release create v1; fi
release|if false; then :; else gh release create v1; fi
release|if false; then :; elif gh release create v1; then :; fi
release|for r in a; do gh release create v1; done
release|make && { gh release create v1; }
release|{ git push origin --tags; }
release|! git push origin v1:refs/tags/v1
merge|if gh pr merge 1; then echo; fi
merge|until gh pr merge 1 --repo o/r --squash; do sleep 1; done
merge|while true; do gh pr merge 1; done
push|if make; then git push; fi
prCreate|! { gh pr create --fill; }
release|function f { gh release create v9; }
release|function f() { gh release create v9; }
release|f() { gh release create v9; }
release|f () { gh release create v9; }
release|coproc gh release create v9
release|coproc NAME { gh release create v9; }
release|select x in a b; do gh release create v9; done
release|case x in x) gh release create v9;; esac
release|case x in (x) gh release create v9;; esac
release|( gh release create v9 )
push|coproc git push
push|function f { git push; }
issueCreate|builtin command gh issue create -t x -b y
EOF
  for C in 'if gh pr view 3; then echo; fi' '{ gh release view v1; }' 'echo if gh release create v1' 'function gh { echo; }' 'coproc cat' 'function release { echo; }'; do
    _tg_run "$C"
    _expect_silent_allow
  done
  e2e_expect_equal "" "$(_tg_journals)" "journal files"
  e2e_expect_clean_edges
fi

# --- T23: behind a program the hook does not know ----------------------------------
if _want tg-unknown-wrapper; then
  _tg_setup tg-unknown-wrapper feature/issue-42-x "$ALL_CONFIRM" \
    "every tier confirm; a Tier 3 action handed to a program the hook does not know (caffeinate, stdbuf, setsid, watch, find -exec, parallel, script, a variable), as words or as one quoted argument, asks; a wrapper's bundled, abbreviated or env -S options do not hide a Tier 2 action; a Tier 2 action behind an unknown program, echo or printf of a Tier 3 action, and a gh or git word that runs nothing stay silent (T23, T26, T27)"
  while IFS='|' read -r WANT C; do
    _tg_run "$C"
    case "$WANT" in
      maybe) _expect_ask "may push or delete a tag" ;;
      unknown) _expect_ask "may merge a pull request or create a release" ;;
      silent) _expect_silent_allow; e2e_expect_equal "" "$E2E_ERR" "stderr for: $C" ;;
      push|prCreate) _expect_ask "is a Tier 2 action set to confirm (tiers.$WANT)" ;;
      *) _expect_ask "is a Tier 3 action (tiers.$WANT)" ;;
    esac
  done <<'EOF'
release|watch 'gh release create v9'
merge|watch -n 30 'gh pr merge 1 --squash'
release|script -q /dev/null -c 'git push --tags'
release|flock /tmp/l -c 'gh release create v9'
merge|tmux new -d 'gh pr merge 1'
release|trap 'gh release create v9' EXIT
release|caffeinate sh -c 'watch "gh release create v9"'
release|awk 'BEGIN { system("gh release create v9") }'
release|perl -e 'system("gh release create v9")'
release|python3 -c 'import os; os.system("gh release create v9")'
release|watch 'g""h release create v9'
release|watch '/usr/local/bin/gh release create v9'
release|watch 'cd /tmp;gh release create v9'
release|watch 'env -Sgh release create v9'
release|watch 'G\H release create v9'
merge|watch '$GH pr merge 1'
release|watch "sh -c 'gh release create v9'"
release|env -S'gh release create v9'
release|env -iS'gh release create v9'
release|env --split-string='gh release create v9'
release|env --sp='gh release create v9'
release|env -S gh release create v9
push|env -S'git push origin HEAD'
push|env -S'-i FOO=1 git push origin HEAD'
push|sudo -Eu root git push origin HEAD
push|sudo --us root git push origin HEAD
push|timeout -vk 5 10 git push origin HEAD
push|env -iu FOO git push origin HEAD
push|env - git push origin HEAD
prCreate|xargs -tn 1 gh pr create --fill
prCreate|exec -cla name gh pr create --fill
merge|caffeinate '>' gh pr merge 1
merge|caffeinate gh pr merge 1
merge|stdbuf -o0 gh pr merge 1
release|setsid gh release create v9
merge|watch -n1 gh pr merge 1
merge|find . -name x -exec gh pr merge 1 \;
merge|parallel gh pr merge ::: 1
merge|script -q /dev/null gh pr merge 1
merge|sudo -E caffeinate /opt/bin/gh pr merge 1
merge|caffeinate gh api -X PUT repos/o/r/pulls/7/merge
release|caffeinate gh release create v1 --verify-tag
release|caffeinate gh release delete v1
release|caffeinate git push --tags
release|setsid git -c push.followTags=true push origin HEAD
maybe|caffeinate git push origin v9
unknown|caffeinate gh api -X POST "$EP"
merge|$GH pr merge 7
merge|$X pr merge 7
release|"$X" release create v1
release|"$G" push origin --tags
merge|$(command -v gh) pr merge 7
silent|npm run git push
silent|npm run git push origin HEAD
silent|caffeinate gh pr create --fill
silent|caffeinate git push origin HEAD
silent|caffeinate gh pr view 1
silent|echo gh pr merge 1
silent|printf '%s\n' gh release create v1
silent|brew upgrade gh git
silent|make gh-pr-merge
silent|$EDITOR notes.md
silent|watch 'git status'
silent|watch -n 30 'gh pr view 1'
silent|trap 'rm -f x' EXIT
silent|tmux new -d 'git log --oneline'
EOF
  e2e_expect_equal "" "$(_tg_journals)" "journal files"
  e2e_expect_clean_edges
fi

# --- T18: backslashes inside a word ---------------------------------------------
if _want tg-backslash; then
  _tg_setup tg-backslash feature/issue-42-x "$ALL_CONFIRM" \
    "every tier confirm; a backslash inside the program, a subcommand or an option, which bash removes before running it: each asks, naming its key; text that only mentions the action stays silent (T18)"
  while IFS='|' read -r KEY C; do
    _tg_run "$C"
    _expect_ask "tiers.$KEY"
  done <<'EOF'
merge|g\h pr merge 1
merge|gh pr mer\ge 1
merge|gh p\r merge 1
merge|\g\h pr merge 1
merge|ba\sh -c 'gh pr merge 1'
release|gh rel\ease create v9
release|git pu\sh --tags
release|git push origin --t\ags
release|g\it -c push.follow\Tags=true push origin HEAD
push|git pu\sh origin HEAD
prCreate|gh pr cr\eate --fill
issueAssign|gh issue edit 5 --add-as\signee @me
merge|gh api -X P\UT repos/o/r/pulls/7/me\rge
merge|watch 'g\h pr merge 1 --body aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' 'b\c ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
release|watch 'x\y ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd' 'gh rel\ease create v9 --notes aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
merge|gh api -X PUT repos/o/r/pulls/7/me\rge?per_page=100aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa -f b\ody=ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
EOF
  # Inside double quotes bash keeps a backslash before any character but $, `,
  # " and \, so gh is handed mer\ge, which is not merge.
  for C in 'echo g\h pr merge 1' 'git commit -m "gh pr mer\ge 1"' 'gh pr vi\ew 3' 'gh pr "mer\ge" 1'; do
    _tg_run "$C"
    _expect_silent_allow
  done
  e2e_expect_equal "" "$(_tg_journals)" "journal files"
  e2e_expect_clean_edges
fi

# --- T13: a tag push is the release tier ------------------------------------------
if _want tg-tag-push; then
  _tg_setup tg-tag-push feature/issue-42-x '{"tiers":{"push":"autonomous"}}' \
    "push autonomous, the repository has tag v1.2.0 and branches v1-fix and main: every push that sends a tag asks under tiers.release (options abbreviated or bundled as git accepts them included, a redirection glued to the option), a source that is not a local branch asks as a possible tag, a forced push to a destination that is not a known branch asks, a push after a cd elsewhere, an export of git's configuration variables, an include.path, a git config or git remote that may change what it sends (also inside bash -c), or under xargs asks, every branch-only push is silent with or without redirections, after a git config of another key or a read of one, and after a word that only names a variable (T13, T19, T20, T25, T25b, T26, T28, T29)"
  ( _e2e_git_env; cd "$E2E_REPO" && git tag -a v1.2.0 -m "v1.2.0" && git branch v1-fix && git branch -f main HEAD ) \
    || _flow_assert_fail "tg-tag-push: could not create the tag and branch"
  mkdir -p "$E2E_REPO/sub"
  while IFS='|' read -r WANT C; do
    _tg_run "$C"
    if [ "$WANT" = ask ]; then
      _expect_ask "Creating a release or pushing a tag is a Tier 3 action (tiers.release)"
    elif [ "$WANT" = maybe ]; then
      _expect_ask "may push or delete a tag"
    else
      _expect_silent_allow
      e2e_expect_equal "" "$E2E_ERR" "stderr for: $C"
    fi
  done <<'EOF'
ask|git push origin v1.2.0
ask|git push origin refs/tags/v1.2.0
ask|git push origin HEAD:refs/tags/v1
ask|git push origin +v1.2.0
ask|git push origin :refs/tags/v1
ask|git push --tags
ask|git push origin --follow-tags
ask|git push --mirror origin
ask|git -c push.followTags=true push
ask|git -c push.followtags push origin HEAD
ask|git push origin tag v9
ask|git push origin main v1.2.0
ask|git push --delete origin v1.2.0
ask|git push -o ci.skip origin v1.2.0
ask|gh api -X POST repos/o/r/git/refs -f ref=refs/tags/v1 -f sha=abc
ask|git push --tag
ask|git push --mirr origin
ask|git push --m origin
ask|git push origin --follow-tag
ask|git push origin --fol
ask|git push origin --del v1.2.0
ask|git push -qd origin v1.2.0
ask|git push origin tags/v1.2.0
ask|git push origin 'refs/heads/*:refs/tags/*'
ask|git push origin HEAD:v1.2.0
maybe|git push origin 'refs/*:refs/*'
maybe|git push origin '*:*'
maybe|git push origin v9.9.9
maybe|git tag v7.0.0 && git push origin v7.0.0
maybe|git push origin abc1234:feature-x
maybe|git push origin origin/main:main
maybe|git push origin "$TAG"
maybe|git push origin $(git describe --tags)
maybe|gh api -X POST repos/o/r/git/refs -f ref="$REF" -f sha=abc
maybe|gh api -X POST repos/o/r/git/refs --input ref.json
silent|git push origin v1-fix
silent|git push origin main
silent|git push -u origin HEAD
silent|git push origin refs/heads/v1-fix
silent|git push origin v1.2.0:refs/heads/v1-copy
silent|git -c push.followTags=false push
silent|git -c push.followTags=true -c push.followTags=false push
silent|git -c push.followTags=true push --no-follow-tags
silent|git push origin -o v1.2.0 main
silent|git push -od origin main
silent|git push -uo v1.2.0 origin main
silent|git push --recurse-submodules check origin main
silent|git push --recu check origin main
silent|git push --rep v1.2.0 origin main
silent|git push --push-o v1.2.0 origin main
silent|git push --no-fol origin main
silent|git push origin 'refs/heads/*:refs/heads/*'
silent|git push origin v1-fix:v1-fix
silent|git push -u origin HEAD:feature-new
silent|gh api -X POST repos/o/r/git/refs -f ref=refs/heads/x -f sha=abc
silent|echo git push --tags
silent|git tag -a v2 -m v2
silent|git push origin v1-fix 2>&1
silent|git push -u origin v1-fix 2>&1
silent|git push origin v1-fix >/dev/null
silent|git push origin v1-fix 2>/dev/null
silent|git push origin v1-fix > out.log 2>&1
silent|git push origin v1-fix 2> err.log
silent|git push origin v1-fix &>/dev/null
silent|git push -u origin HEAD 2>&1 | tail -3
silent|>/dev/null git push origin v1-fix
silent|git push --force-with-lease origin v1-fix
silent|git push -f origin HEAD:v1-fix
silent|git push --force origin v1-fix:v1-fix
silent|git push origin HEAD:v5
maybe|git push --force-with-lease=v5:abc1234 origin HEAD:v5
maybe|git push -f origin HEAD:v5
maybe|git push -fu origin HEAD:v5
maybe|git push origin +HEAD:v5
maybe|git push --force origin HEAD:tags/v5
maybe|git push --force-w origin HEAD:v5
ask|git -c push.followTags=2 push origin main
ask|git -c push.followTags=TRUE push origin main
ask|git -c push.followTags=-1 push origin main
silent|git -c push.followTags=no push origin main
silent|git -c push.followTags=Off push origin main
silent|git -c push.followTags= push origin main
silent|git -c push.followTags=0 push origin main
silent|GIT_CONFIG_NOSYSTEM=1 git push origin v1-fix
maybe|GIT_CONFIG_GLOBAL=/tmp/x git push origin v1-fix
maybe|GIT_CONFIG_PARAMETERS="'remote.origin.mirror'='true'" git push origin v1-fix
maybe|HOME=/tmp/h git push origin v1-fix
maybe|git -c include.path=/tmp/x push origin v1-fix
maybe|git -c includeIf.onbranch:main.path=/tmp/x push origin v1-fix
maybe|git --config-env include.path=X push origin v1-fix
maybe|export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.mirror GIT_CONFIG_VALUE_0=true; git push origin v1-fix
maybe|export GIT_DIR=../x/.git && git push origin v1-fix
maybe|export HOME=/tmp/h; git push origin v1-fix
maybe|cd .. && git push origin v1-fix
maybe|cd "$D" && git push origin v1-fix
maybe|cd - && git push origin v1-fix
maybe|popd && git push origin v1-fix
maybe|cd && git push origin v1-fix
maybe|cd ~ && git push origin v1-fix
maybe|cd ~/src && git push origin v1-fix
silent|cd . && git push origin v1-fix
silent|cd sub && git push origin v1-fix
silent|git status && git push origin v1-fix
maybe|xargs -n1 git push origin < list
maybe|printf '%s\n' v1-fix | xargs git push origin
maybe|xargs -a list git push origin
ask|git push -o '>x' origin v1.2.0
ask|git push -o ">x" origin v1.2.0
ask|git push -o \>x origin v1.2.0
ask|sudo -u '>x' git push --tags
maybe|printf 'v1.2.0\n' | xargs -I '>x' git push origin '>x'
silent|git push -q 2>/dev/null origin v1-fix
ask|git push --tags>/dev/null
ask|git push --follow-tags>/dev/null
ask|git push --mirror>/dev/null
ask|git push --tags</dev/null
ask|git push --tags&>/dev/null
ask|git push origin v1.2.0>/dev/null
ask|git -c push.followTags=true push>/dev/null
maybe|git push origin '2>&1'
silent|git push origin v1-fix>/dev/null
silent|git push origin v1-fix 2>/dev/null>out.log
silent|git push origin v1-fix > "push log.txt"
silent|git push origin v1-fix 2>"err log.txt"
silent|git push origin v1-fix >| out.log
silent|git push origin v1-fix 2>&1>/dev/null
maybe|git config push.followTags true && git push
maybe|git config --local push.followTags true; git push origin v1-fix
maybe|git config remote.origin.mirror true && git push
maybe|git config --add remote.origin.push 'refs/tags/*' && git push
maybe|git config remote.pushDefault mir && git push
maybe|git config Branch.v1-fix.pushRemote mir && git push
maybe|git config include.path /tmp/x && git push origin v1-fix
maybe|git -C . config --global push.followTags true && git push origin v1-fix
maybe|git config --file .git/config push.followTags true && git push origin v1-fix
maybe|git config set push.followTags true && git push origin v1-fix
maybe|git config -e && git push origin v1-fix
maybe|git config "$K" true && git push origin v1-fix
maybe|git remote add m2 ../remote.git --mirror=push && git push m2
maybe|git remote set-url origin ../x.git && git push origin v1-fix
maybe|git remote rename origin old && git push origin v1-fix
maybe|git config push.followTags true && cd sub && git push origin v1-fix
silent|git config user.name x && git push origin v1-fix
silent|git config core.editor vim; git push origin v1-fix
silent|git config --get push.followTags && git push origin v1-fix
silent|git config get remote.origin.url && git push origin v1-fix
silent|git config --list && git push origin v1-fix
silent|git remote -v && git push origin v1-fix
silent|git remote get-url origin && git push origin v1-fix
silent|git push origin v1-fix && git config push.followTags true
maybe|bash -c 'git config push.followTags true' && git push origin v1-fix
maybe|sh -c "git remote add m2 ../repo.git --mirror=push" && git push m2
maybe|eval 'git config remote.origin.mirror true' && git push
maybe|bash <<<'git config push.followTags true' && git push origin v1-fix
silent|bash -c 'git config user.name x' && git push origin v1-fix
silent|echo git config push.followTags true && git push origin v1-fix
silent|echo HOME && git push origin v1-fix
silent|echo GIT_DIR=x && git push origin v1-fix
silent|unset GIT_DIR; git push origin v1-fix
silent|printf '%s\n' GIT_CONFIG_COUNT; git push origin v1-fix
maybe|GIT_DIR=../x/.git; export GIT_DIR; git push origin v1-fix
maybe|export GIT_CONFIG_GLOBAL; git push origin v1-fix
maybe|declare -x HOME=/tmp/h; git push origin v1-fix
maybe|env HOME=/tmp/h git push origin v1-fix
EOF
  e2e_expect_equal "" "$(_tg_journals)" "journal files"
  e2e_expect_clean_edges
fi

if _want tg-tag-journal-floor; then
  _tg_setup tg-tag-journal-floor feature/issue-42-x '{"tiers":{"push":"journal","release":"journal"}}' \
    "push journal and release journal: a branch push is journaled, a tag push still asks and names tiers.release as ignored (T13)"
  _tg_run 'git push --tags'
  _expect_ask "tiers.release"
  e2e_expect_err 'tiers.release is "journal", below the confirm floor'
  e2e_expect_equal "" "$(_tg_journals)" "journal files after the tag push"
  _tg_run 'git push origin HEAD'
  _expect_silent_allow
  e2e_expect_file_has "$(_tg_trail42)" 'tiers.push (journal) "git push origin HEAD"'
  # A redirection is not a refspec: the push is journaled, and the breadcrumb
  # shows the push without it.
  _tg_run 'git push -u origin HEAD >/dev/null 2>&1'
  _expect_silent_allow
  e2e_expect_file_has "$(_tg_trail42)" 'tiers.push (journal) "git push -u origin HEAD"'
  # env -S with a quoted string is read twice (as env's words and as a script
  # handed to env); the push it runs is one push, so one breadcrumb.
  _tg_run "env -S 'git push origin HEAD:refs/heads/dd'"
  _expect_silent_allow
  e2e_expect_equal 1 "$(grep -c 'tiers.push (journal) "git push origin HEAD:refs/heads/dd"' "$E2E_REPO/$(_tg_trail42)" 2>/dev/null)" "breadcrumbs for the env -S push"
  e2e_expect_clean_edges
fi

if _want tg-follow-tags-config; then
  _tg_setup tg-follow-tags-config feature/issue-42-x '{"tiers":{"push":"autonomous"}}' \
    "push.followTags true in the repository's git config: a branch push asks under tiers.release; -c push.followTags=false or --no-follow-tags on the command line turns it off again (T13)"
  ( _e2e_git_env; cd "$E2E_REPO" && git config push.followTags true ) \
    || _flow_assert_fail "tg-follow-tags-config: could not set push.followTags"
  _tg_run 'git push origin HEAD'
  _expect_ask "tiers.release"
  _tg_run 'git -c push.followTags=false push origin HEAD'
  _expect_silent_allow
  _tg_run 'git push --no-follow-tags origin HEAD'
  _expect_silent_allow
  _tg_run 'git push --no-fol origin HEAD'
  _expect_silent_allow
  e2e_expect_clean_edges
fi

# --- T21: a remote configured to mirror or to push tags ---------------------------
if _want tg-remote-config; then
  _tg_setup tg-remote-config feature/issue-42-x '{"tiers":{"push":"autonomous"}}' \
    "push autonomous: -c remote.<name>.mirror or remote.<name>.push on the command line asks; remote.<name>.mirror in the repository's configuration makes a push to that remote a tag push, and so does a remote.<name>.push refspec naming tags or a glob when the command names no refspec; the remote a bare git push uses is found as git finds it (T21)"
  while IFS='|' read -r WANT C; do
    _tg_run "$C"
    case "$WANT" in
      maybe) _expect_ask "may push or delete a tag" ;;
      silent) _expect_silent_allow; e2e_expect_equal "" "$E2E_ERR" "stderr for: $C" ;;
    esac
  done <<'EOF'
maybe|git -c remote.origin.mirror=true push
maybe|git -c remote.origin.push=refs/tags/*:refs/tags/* push
maybe|git -c Remote.Origin.Push=HEAD push origin
maybe|git -c remote.origin.mirror push origin HEAD
maybe|git --config-env=remote.origin.mirror=M push origin HEAD
maybe|git --config-env=push.followTags=F push origin HEAD
maybe|GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.mirror GIT_CONFIG_VALUE_0=true git push origin HEAD
maybe|git --config-env remote.origin.mirror=M push origin HEAD
maybe|git --config-env Remote.Origin.Push=P push origin HEAD
maybe|git --config-env push.followTags=F push origin HEAD
maybe|git -c remote.pushDefault=backup push
maybe|git -c branch.feature/issue-42-x.pushRemote=backup push
maybe|git -c branch.feature/issue-42-x.remote=backup push
maybe|git --config-env remote.pushDefault=R push
maybe|git --config-env=remote.pushDefault=R push
silent|git -c remote.origin.pushurl=x push origin HEAD
silent|git -c remote.pushDefault=origin push origin HEAD
silent|git -c remote.pushDefault=backup push origin HEAD
silent|git -c remote.pushDefault=backup push --repo=origin
EOF
  _tg_cfg() { ( _e2e_git_env; cd "$E2E_REPO" && git config "$@" ) || _flow_assert_fail "tg-remote-config: git config $*"; }
  _tg_release_ask() { _expect_ask "Creating a release or pushing a tag is a Tier 3 action (tiers.release)"; }
  _tg_cfg remote.origin.mirror true
  _tg_run 'git push origin'
  _tg_release_ask
  _tg_run 'git push'
  _tg_release_ask
  # A redirection is not the remote: each of these pushes to the mirror.
  for C in 'git push 2>&1' 'git push >/dev/null' 'git push -q 2>&1 | tail -2' 'git push > out.log 2>&1'; do
    _tg_run "$C"
    _tg_release_ask
  done
  _tg_cfg --unset remote.origin.mirror
  _tg_cfg remote.origin.push 'refs/tags/*:refs/tags/*'
  _tg_run 'git push'
  _tg_release_ask
  _tg_run 'git push origin'
  _tg_release_ask
  _tg_run 'git push origin HEAD'
  _expect_silent_allow
  _tg_cfg --replace-all remote.origin.push 'refs/heads/*:refs/heads/*'
  _tg_run 'git push origin'
  _expect_silent_allow
  _tg_cfg --add remote.origin.push 'refs/*:refs/*'
  _tg_run 'git push origin'
  _expect_ask "may push or delete a tag"
  _tg_cfg --unset-all remote.origin.push
  _tg_cfg remote.backup.mirror true
  _tg_run 'git push backup'
  _tg_release_ask
  # --repo names the remote when no positional one does, in every spelling
  # git accepts.
  for C in 'git push --repo=backup' 'git push --repo backup' 'git push --rep=backup' 'git push --repo backup 2>&1'; do
    _tg_run "$C"
    _tg_release_ask
  done
  _tg_run 'git push --repo=backup origin HEAD'
  _expect_silent_allow
  _tg_run 'git push origin HEAD'
  _expect_silent_allow
  _tg_run 'git push'
  _expect_silent_allow
  _tg_cfg remote.pushDefault backup
  _tg_run 'git push'
  _tg_release_ask
  _tg_cfg --unset remote.pushDefault
  _tg_cfg branch.feature/issue-42-x.pushRemote backup
  _tg_run 'git push'
  _tg_release_ask
  _tg_run 'git push "$R"'
  _expect_ask "may push or delete a tag"
  e2e_expect_clean_edges
fi

# --- T16: git -C <dir>, --git-dir, --work-tree ----------------------------------
if _want tg-git-dash-c; then
  _tg_setup tg-git-dash-c feature/issue-42-x '{"tiers":{"push":"journal"}}' \
    "a second repository ../other (branch feature/issue-77-y, tag v7, a journal directory): a push into it through -C, --git-dir, --work-tree, GIT_DIR= or GIT_WORK_TREE= judges v7 there and writes its breadcrumb to other's trail; a -C that cannot be found asks, since neither its tags nor its remotes' configuration can be read (T16)"
  OTHER="$E2E_DIR/other"
  mkdir -p "$OTHER"
  ( _e2e_git_env; cd "$OTHER" && git init -q && git config user.email e2e@example.invalid && git config user.name e2e \
      && git config commit.gpgsign false && printf 'o\n' > o.txt && git add o.txt && git commit -q -m init \
      && git checkout -q -b feature/issue-77-y && git tag -a v7 -m v7 ) >/dev/null 2>&1 \
    || _flow_assert_fail "tg-git-dash-c: could not create the second repository"
  mkdir -p "$OTHER/.decisions"
  OTHER_TRAIL="$OTHER/.decisions/auto-log/issue-77.$(date +%Y-%m).md"
  # rel is a tag in other and a branch here: a relative --git-dir or GIT_DIR
  # is found from the directory -C names, as git finds it.
  ( _e2e_git_env; git -C "$OTHER" tag rel && git -C "$E2E_REPO" branch rel ) >/dev/null 2>&1 \
    || _flow_assert_fail "tg-git-dash-c: could not create rel"
  while IFS='|' read -r WANT C; do
    _tg_run "$C"
    case "$WANT" in
      ask) _expect_ask "Creating a release or pushing a tag is a Tier 3 action (tiers.release)" ;;
      maybe) _expect_ask "may push or delete a tag" ;;
      other) _expect_silent_allow
             e2e_expect_equal yes "$(grep -qF "tiers.push (journal) \"$C\"" "$OTHER_TRAIL" 2>/dev/null && echo yes || echo no)" "breadcrumb in other's trail for: $C" ;;
      here) _expect_silent_allow
            e2e_expect_file_has "$(_tg_trail42)" "tiers.push (journal) \"$C\"" ;;
    esac
  done <<EOF
ask|git -C ../other push origin v7
ask|git -C $OTHER push origin v7
ask|git -C .. -C other push origin v7
ask|git --git-dir=../other/.git push origin v7
ask|git --git-dir ../other/.git --work-tree ../other push origin refs/tags/v7
maybe|git push origin v7
other|git -C ../other push origin HEAD
other|git -C .. -C other push origin refs/heads/feature/issue-77-y
other|git -C $OTHER push origin HEAD:refs/heads/x
other|git --work-tree=../other --git-dir=../other/.git push origin HEAD
maybe|git -C ../missing push origin HEAD
maybe|git -C "\$D" push origin HEAD
maybe|git -C ../missing -c push.followTags=false push origin v7
maybe|git -C ../missing -c push.followTags=false push origin HEAD
ask|GIT_DIR=../other/.git git push origin v7
ask|GIT_DIR=.git git -C ../other push origin rel
ask|git --git-dir=.git -C ../other push origin rel
ask|git --git-dir .git -C ../other push origin rel
ask|git --work-tree=. --git-dir=.git -C ../other push origin rel
here|git push origin rel
ask|env GIT_WORK_TREE=../other GIT_DIR=../other/.git git push origin v7
EOF
  e2e_expect_equal "" "$(_tg_journals)" "tracked journal files here"
  e2e_expect_equal no "$([ -e "$OTHER/.decisions/issue-77.md" ] && echo yes || echo no)" "a tracked journal in other"
  ( _e2e_git_env; git -C "$OTHER" config push.followTags true )
  _tg_run 'git -C ../other push origin HEAD'
  _expect_ask "tiers.release"
  _tg_run 'git push origin HEAD'
  _expect_silent_allow
  ( _e2e_git_env; git -C "$OTHER" config push.followTags false )
  printf '%s\n' '{"tiers":{"push":"journal","prCreate":"journal"}}' > "$E2E_REPO/.claude/settings.flow.json"
  _tg_run 'git -C ../other push origin HEAD && gh pr create --fill'
  _expect_silent_allow
  e2e_expect_equal yes "$(grep -qF 'tiers.prCreate (journal) "gh pr create --fill"' "$E2E_REPO/$(_tg_trail42)" 2>/dev/null && echo yes || echo no)" "the pr create breadcrumb in this repository's trail"
  e2e_expect_equal no "$(grep -qF 'tiers.prCreate' "$OTHER_TRAIL" 2>/dev/null && echo yes || echo no)" "a pr create breadcrumb in other's trail"
  e2e_expect_clean_edges
fi

# --- T17: deleting a tag -------------------------------------------------------------
if _want tg-tag-delete; then
  _tg_setup tg-tag-delete feature/issue-42-x '{"tiers":{"push":"autonomous"}}' \
    "deleting a tag on the remote asks under tiers.release: :<tag>, --delete/-d <tag>, gh api DELETE or PATCH on git/refs/tags; deleting a known branch is silent; deleting a name that is neither asks (T17)"
  ( _e2e_git_env; cd "$E2E_REPO" && git tag -a v1.2.0 -m v1.2.0 && git branch feature-local \
      && git update-ref refs/remotes/origin/feature-gone HEAD ) >/dev/null 2>&1 \
    || _flow_assert_fail "tg-tag-delete: could not create the refs"
  while IFS='|' read -r WANT C; do
    _tg_run "$C"
    case "$WANT" in
      ask) _expect_ask "Creating a release or pushing a tag is a Tier 3 action (tiers.release)" ;;
      maybe) _expect_ask "may push or delete a tag" ;;
      silent) _expect_silent_allow; e2e_expect_equal "" "$E2E_ERR" "stderr for: $C" ;;
    esac
  done <<'EOF'
ask|git push origin :v1.2.0
ask|git push origin :refs/tags/v9
ask|git push origin --delete v1.2.0
ask|git push -d origin v1.2.0
ask|git push origin --delete refs/tags/v9
ask|gh api -X DELETE repos/o/r/git/refs/tags/v1
ask|gh api --method DELETE /repos/{owner}/{repo}/git/refs/tags/v1.2.0
ask|gh api -X PATCH repos/o/r/git/refs/tags/v1 -f sha=abc -F force=true
maybe|git push origin --delete v9
maybe|git push origin :v9
maybe|gh api -X DELETE repos/o/r/git/refs/$REF
silent|git push origin :feature-local
silent|git push origin --delete feature-gone
silent|git push origin --del feature-gone
silent|git push -qd origin feature-gone
silent|git push -fdu origin feature-gone
maybe|git push -od origin feature-gone
maybe|git push origin feature-gone
silent|git push -d origin refs/heads/anything
silent|gh api -X DELETE repos/o/r/git/refs/heads/feature-x
silent|gh api -X DELETE repos/o/r/git/refs/heads/$B
silent|gh api -X DELETE repos/o/r/issues/comments/5
silent|gh api -X PATCH repos/o/r/git/refs/heads/main -f sha=abc
EOF
  e2e_expect_clean_edges
fi

# --- T14: gh release create --verify-tag ---------------------------------------
# _tg_remote — give the scratch repository a bare origin holding tag v1.2.0;
# v2.0.0 exists only locally.
_tg_remote() {
  ( _e2e_git_env
    git -C "$E2E_DIR" init -q --bare remote.git && cd "$E2E_REPO" \
      && git remote add origin "$E2E_DIR/remote.git" \
      && git tag -a v1.2.0 -m v1.2.0 && git tag -a v2.0.0 -m v2.0.0 \
      && git push -q origin v1.2.0 ) >/dev/null 2>&1 \
    || _flow_assert_fail "$E2E_NAME: could not create the bare remote"
}

if _want tg-verify-tag; then
  _tg_setup tg-verify-tag feature/issue-42-x '{"tiers":{"push":"autonomous"}}' \
    "gh release create --verify-tag on a tag origin has: journaled in the trail, no ask; on a tag only local, without --verify-tag, or with the tag a variable: ask (T14)"
  _tg_remote
  _tg_run 'gh release create --title "v 1" v1.2.0 --verify-tag --notes x'
  _expect_silent_allow
  e2e_expect_equal "" "$E2E_ERR" "stderr of the journaled --verify-tag (no job report from the stopped watchdog)"
  e2e_expect_file_has "$(_tg_trail42)" 'tiers.release (--verify-tag, v1.2.0 already on the remote) "gh release create --title "v 1" v1.2.0 --verify-tag --notes x"'
  _tg_run 'gh release create v2.0.0 --verify-tag'
  _expect_ask "v2.0.0 could not be found on origin"
  _tg_run 'gh release create v1.2.0 --title v1.2.0'
  _expect_ask "tiers.release"
  _tg_run 'gh release create "$TAG" --verify-tag'
  _expect_ask "tiers.release"
  _tg_run 'gh release create v1.2.0 --verify-tag -R "$R"'
  _expect_ask "Creating a release or pushing a tag is a Tier 3 action (tiers.release)"
  e2e_expect_no_out "could not be found"
  # Behind a program the hook does not know, the exemption does not apply.
  _tg_run 'caffeinate gh release create v1.2.0 --verify-tag'
  _expect_ask "Creating a release or pushing a tag is a Tier 3 action (tiers.release)"
  # A tag made and pushed in the same command is not on the remote when the
  # hook runs: the push asks, and so does the release.
  _tg_run 'git tag v3.0.0 && git push origin v3.0.0 && gh release create v3.0.0 --verify-tag'
  _expect_ask "may push or delete a tag"
  e2e_expect_out "v3.0.0 could not be found on origin"
  _tg_run 'gh release create v1.2.0 --verify-tag && gh pr merge 7 --repo o/r --squash'
  _expect_ask "tiers.merge"
  e2e_expect_equal 1 "$(grep -c 'verify-tag' "$E2E_REPO/$(_tg_trail42)" 2>/dev/null)" "breadcrumbs after the run that also asked"
  e2e_expect_clean_edges
fi

if _want tg-verify-tag-repo; then
  _tg_setup tg-verify-tag-repo feature/issue-42-x '{"tiers":{"push":"autonomous"}}' \
    "origin is https://github.com/acme/widgets.git (rewritten to a local bare repository holding v1.2.0): --verify-tag is journaled only when gh would create the release in origin's repository; another repository in -R or GH_REPO, GH_HOST, a cd or an export before it, a second remote with no default chosen, or a default chosen on another remote asks (T24)"
  _tg_remote
  WIDGETS=https://github.com/acme/widgets.git
  ( _e2e_git_env; cd "$E2E_REPO" && git remote set-url origin "$WIDGETS" \
      && git config "url.$E2E_DIR/remote.git.insteadOf" "$WIDGETS" ) \
    || _flow_assert_fail "tg-verify-tag-repo: could not point origin at the bare repository"
  UNCONFIRMED="could not be confirmed to be origin's"
  JN=0
  while IFS='|' read -r WANT C; do
    _tg_run "$C"
    case "$WANT" in
      journal)
        JN=$((JN + 1))
        _expect_silent_allow
        e2e_expect_equal "" "$E2E_ERR" "stderr for: $C"
        e2e_expect_equal "$JN" "$(grep -c 'already on the remote' "$E2E_REPO/$(_tg_trail42)" 2>/dev/null)" "breadcrumbs after: $C" ;;
      unconfirmed) _expect_ask "$UNCONFIRMED" ;;
      release) _expect_ask "Creating a release or pushing a tag is a Tier 3 action (tiers.release)" ;;
    esac
  done <<'EOF'
journal|gh release create v1.2.0 --verify-tag
journal|gh release create v1.2.0 --verify-tag -R acme/widgets
journal|gh release create v1.2.0 --verify-tag --repo ACME/Widgets
journal|gh -R github.com/acme/widgets release create v1.2.0 --verify-tag
journal|GH_REPO=acme/widgets gh release create v1.2.0 --verify-tag
journal|GH_REPO=acme/other gh release create v1.2.0 --verify-tag -R acme/widgets
unconfirmed|gh release create v1.2.0 --verify-tag -R acme/other
unconfirmed|gh release create v1.2.0 --verify-tag -R ghe.example.com/acme/widgets
unconfirmed|gh release create v1.2.0 --verify-tag -Racme/other
unconfirmed|gh release create v1.2.0 --verify-tag -R=acme/other
unconfirmed|gh release create -dR acme/other v1.2.0 --verify-tag
journal|gh release create v1.2.0 --verify-tag -R=acme/widgets
journal|gh release create -dt "Title" v1.2.0 --verify-tag
unconfirmed|gh -Racme/other release create v1.2.0 --verify-tag
unconfirmed|GH_REPO=acme/other gh release create v1.2.0 --verify-tag
unconfirmed|env GH_REPO=acme/other gh release create v1.2.0 --verify-tag
unconfirmed|GH_REPO=acme/other gh release create v1.2.0 --verify-tag -R acme/other
release|GH_HOST=ghe.example.com gh release create v1.2.0 --verify-tag
release|export GH_REPO=acme/other; gh release create v1.2.0 --verify-tag
release|cd ../elsewhere && gh release create v1.2.0 --verify-tag
release|(cd /tmp; gh release create v1.2.0 --verify-tag)
EOF
  _tg_run GH_REPO=acme/other 'gh release create v1.2.0 --verify-tag'
  _expect_ask "$UNCONFIRMED"
  _tg_run GH_HOST=ghe.example.com 'gh release create v1.2.0 --verify-tag'
  _expect_ask "Creating a release or pushing a tag is a Tier 3 action (tiers.release)"
  ( _e2e_git_env; cd "$E2E_REPO" && git remote add upstream "$WIDGETS" ) || _flow_assert_fail "tg-verify-tag-repo: could not add upstream"
  _tg_run 'gh release create v1.2.0 --verify-tag'
  _expect_ask "$UNCONFIRMED"
  ( _e2e_git_env; cd "$E2E_REPO" && git config remote.origin.gh-resolved base ) || _flow_assert_fail "tg-verify-tag-repo: gh-resolved"
  _tg_run 'gh release create v1.2.0 --verify-tag'
  _expect_silent_allow
  ( _e2e_git_env; cd "$E2E_REPO" && git config --unset remote.origin.gh-resolved && git config remote.upstream.gh-resolved base ) || _flow_assert_fail "tg-verify-tag-repo: gh-resolved on upstream"
  _tg_run 'gh release create v1.2.0 --verify-tag'
  _expect_ask "$UNCONFIRMED"
  e2e_expect_clean_edges
fi

if _want tg-verify-tag-no-remote; then
  _tg_setup tg-verify-tag-no-remote feature/issue-42-x "" \
    "gh release create --verify-tag in a repository with no origin: the check fails, so it asks (T14)"
  ( _e2e_git_env; cd "$E2E_REPO" && git tag -a v1.2.0 -m v1.2.0 ) >/dev/null 2>&1
  _tg_run 'gh release create v1.2.0 --verify-tag'
  _expect_ask "v1.2.0 could not be found on origin"
  e2e_expect_equal "" "$(_tg_trail)" "trail files"
  e2e_expect_clean_edges
fi

if _want tg-verify-tag-timeout; then
  _tg_setup tg-verify-tag-timeout feature/issue-42-x "" \
    "origin is an ssh remote whose ssh never answers: the check is stopped after TG_REMOTE_TIMEOUT=2 seconds and the release asks, well inside 15 seconds (T14)"
  ( _e2e_git_env; cd "$E2E_REPO" && git remote add origin ssh://example.invalid/r.git ) >/dev/null 2>&1
  printf '#!/bin/sh\nsleep 30\n' > "$E2E_BIN/slow-ssh"; chmod +x "$E2E_BIN/slow-ssh"
  T0=$(date +%s)
  _tg_run "GIT_SSH_COMMAND=$E2E_BIN/slow-ssh" TG_REMOTE_TIMEOUT=2 'gh release create v1.2.0 --verify-tag'
  T1=$(date +%s)
  _expect_ask "v1.2.0 could not be found on origin"
  e2e_expect_equal "" "$E2E_ERR" "stderr"
  e2e_expect_equal yes "$([ $((T1 - T0)) -lt 15 ] && echo yes || echo no)" "finished within 15 seconds ($((T1 - T0)) s)"
  e2e_expect_clean_edges
fi

# --- T15: gh api PATCH and GraphQL ---------------------------------------------
if _want tg-api-patch-graphql; then
  _tg_setup tg-api-patch-graphql feature/issue-42-x "$ALL_CONFIRM" \
    "every tier confirm; gh api PATCH on a release or on an issue's assignees, and GraphQL mutations read inline, from query=@file and from --input, ask with the right key, a mutation whose name holds Ref, Release or Merge in any case among them, also after a string with an escaped quote in single or double quotes; reads and other mutations do not; a double-quoted query in which the shell expands something asks as unreadable (T15)"
  printf '%s\n' 'mutation { enablePullRequestAutoMerge(input:{pullRequestId:"x"}) { clientMutationId } }' > "$E2E_REPO/q.graphql"
  printf '%s\n' '{"query":"mutation { createRelease(input:{repositoryId:\"r\", tagName:\"v1\"}) { release { id } } }"}' > "$E2E_REPO/body.json"
  printf '%s\n' '{"query":"query { viewer { login } }"}' > "$E2E_REPO/read.json"
  printf '%s\n' '{"assignees":["me"]}' > "$E2E_REPO/assign.json"
  while IFS='|' read -r WANT C; do
    _tg_run "$C"
    case "$WANT" in
      silent) _expect_silent_allow; e2e_expect_equal "" "$E2E_ERR" "stderr for: $C" ;;
      unknown) _expect_ask "may merge a pull request or create a release" ;;
      *) _expect_ask "(tiers.$WANT)" ;;
    esac
  done <<'EOF'
release|gh api -X PATCH repos/o/r/releases/123 -F draft=false
release|gh api --method PATCH /repos/{owner}/{repo}/releases/9 -f name=x
issueAssign|gh api -X PATCH repos/o/r/issues/4 -f 'assignees[]=me'
issueAssign|gh api --method PUT repos/o/r/issues/4 -f assignee=me
merge|gh api graphql -f query='mutation { mergePullRequest(input:{pullRequestId:"x"}) { clientMutationId } }'
merge|gh api graphql -F query=@q.graphql
release|gh api graphql -f query='mutation($id:ID!){ updateRelease(input:{releaseId:$id}){ release { id } } }'
release|gh api graphql --input body.json
prCreate|gh api graphql -f query='mutation { createPullRequest(input:{}) { pullRequest { id } } }'
issueCreate|gh api graphql -fquery='mutation { createIssue(input:{}) { issue { id } } }'
issueAssign|gh api graphql -f query='mutation { addAssigneesToAssignable(input:{}) { clientMutationId } }'
unknown|gh api graphql -f query="$Q"
unknown|gh api graphql -F query=@missing.graphql
unknown|gh api graphql --input -
silent|gh api graphql -f query='query { repository(owner:"o", name:"r") { pullRequest(number:1) { mergeable } } }'
silent|gh api graphql -f query='mutation { addComment(input:{}) { clientMutationId } }'
silent|gh api graphql -f query='mutation { createIssueType(input:{}) { clientMutationId } }'
release|gh api graphql -f query='mutation { createRef(input:{repositoryId:"r", name:"refs/tags/v1", oid:"a"}) { ref { id } } }'
release|gh api graphql -f query='mutation { updateRef(input:{refId:"r", oid:"a", force:true}) { ref { id } } }'
release|gh api graphql -f query='mutation { deleteRef(input:{refId:"r"}) { clientMutationId } }'
release|gh api graphql -f query='mutation { updateRefs(input:{repositoryId:"r", refUpdates:[]}) { clientMutationId } }'
release|gh api graphql -f query='mutation { t: CreateRef (input:{}) { ref { id } } }'
release|gh api graphql -f query='mutation { deleteRelease(input:{}) { clientMutationId } }'
merge|gh api graphql -f query='mutation { mergeBranch(input:{}) { mergeCommit { oid } } }'
merge|gh api graphql -f query='mutation { enqueuePullRequest(input:{pullRequestId:"x"}) { mergeQueueEntry { id } } }'
silent|gh api graphql -f query='mutation { disablePullRequestAutoMerge(input:{pullRequestId:"x"}) { clientMutationId } }'
silent|gh api graphql -f query='mutation { addComment(input:{subjectId:"x", body:"refactor(gate) and merge(y), prefer(x)"}) { clientMutationId } }'
silent|gh api graphql -f query='mutation { addComment(input:{subjectId:"x", body:"""release(v1) and mergeBranch(x)"""}) { clientMutationId } }'
merge|gh api graphql -f query='mutation { addComment(input:{body:"see #1"}) { clientMutationId } mergeBranch(input:{}) { mergeCommit { oid } } }'
release|gh api graphql -f query='mutation { addComment(input:{body:"x"}) { clientMutationId } a: createRef(input:{}) { ref { id } } }'
merge|gh api graphql -f query='mutation { addComment(input:{body:"unterminated) { id } mergeBranch(input:{}) { mergeCommit { oid } } }'
silent|gh api graphql -f query='query { repository(owner:"o", name:"r") { refs(first:5, refPrefix:"refs/tags/") { nodes { name } } } }'
silent|gh api graphql -f query='query { repository(owner:"o", name:"r") { pullRequest(number:1) { headRefName mergeable } } }'
silent|gh api graphql -f query='mutation { addComment(input:{subjectId:"x", body:"merge the release ref"}) { clientMutationId } }'
silent|gh api graphql --input read.json
silent|gh api -X PATCH repos/o/r/issues/4 -f title=x
silent|gh api -X PATCH repos/o/r/releases/assets/5 -f name=x
silent|gh api -X PUT repos/o/r/releases/123 -f name=x
silent|gh api -X GET repos/o/r/releases/123
silent|gh api -X PATCH repos/o/r/issues/4/comments -f assignees=x
release|gh api graphql -f query='mutation { updatePullRequest(input:{pullRequestId:"x", title:"Say \"hi"}) { clientMutationId } createRelease(input:{repositoryId:"x", tagName:"v9"}) { clientMutationId } }'
merge|gh api graphql -f query='mutation { updatePullRequest(input:{pullRequestId:"x", body:"use a 6\" cable"}) { clientMutationId } mergePullRequest(input:{pullRequestId:"x"}) { clientMutationId } }'
release|gh api graphql -f query='mutation { updatePullRequest(input:{pullRequestId:"x", body:"C:\\"}) { clientMutationId } createRelease(input:{repositoryId:"x", tagName:"v9"}) { clientMutationId } }'
merge|gh api graphql -f query="mutation { updatePullRequest(input:{pullRequestId:\"x\", body:\"use a 6\\\" cable\"}) { clientMutationId } mergePullRequest(input:{pullRequestId:\"x\"}) { clientMutationId } }"
release|gh api graphql -f query="mutation { updatePullRequest(input:{pullRequestId:\"x\", title:\"Say \\\"hi\"}) { clientMutationId } createRelease(input:{repositoryId:\"x\", tagName:\"v9\"}) { clientMutationId } }"
silent|gh api graphql -f query='mutation { addComment(input:{subjectId:"x", body:"say \"hi\" then merge(x) and release(y)"}) { clientMutationId } }'
silent|gh api graphql -f query="mutation { addComment(input:{subjectId:\"x\", body:\"say \\\"hi\\\" then merge(x) and release(y)\"}) { clientMutationId } }"
silent|gh api graphql -f query="mutation(\$id: ID!) { addComment(input:{subjectId:\$id, body:\"x\"}) { clientMutationId } }"
unknown|gh api graphql -f query="mutation { $FIELD(input:{}) { clientMutationId } }"
unknown|gh api graphql -f query="mutation { addComment(input:{subjectId:\"x\", body:\"`cat b`\"}) { clientMutationId } }"
EOF
  # A comment runs to the end of its line: a quote inside it opens no string,
  # and the mutation on the next line is read.
  _tg_run "gh api graphql -f query='mutation { # do not \"merge\"
  mergeBranch(input:{}) { mergeCommit { oid } } }'"
  _expect_ask "(tiers.merge)"
  # Inline, the line ends cannot be seen, so the rest of a query after a
  # comment is read as code: a merge named in a comment asks. From a file the
  # comment ends at its line end.
  _tg_run "gh api graphql -f query='mutation { # mergeBranch(input:{})
  addComment(input:{}) { clientMutationId } }'"
  _expect_ask "(tiers.merge)"
  printf '%s
' 'mutation { # mergeBranch(input:{}) "' 'addComment(input:{body:"x"}) { clientMutationId } }' > "$E2E_REPO/comment.graphql"
  _tg_run 'gh api graphql -F query=@comment.graphql'
  _expect_silent_allow
  printf '%s
' 'mutation { # a "quote' 'mergeBranch(input:{}) { mergeCommit { oid } } }' > "$E2E_REPO/comment2.graphql"
  _tg_run 'gh api graphql -F query=@comment2.graphql'
  _expect_ask "(tiers.merge)"
  _tg_run 'gh api -X PATCH repos/o/r/issues/4 --input assign.json'
  _expect_silent_allow
  e2e_expect_err "could not read whether gh api -X PATCH repos/o/r/issues/4 --input assign.json changes an issue's assignees"
  e2e_expect_clean_edges
fi

# --- T22: changing or deleting a release ------------------------------------------
if _want tg-release-subcommands; then
  _tg_setup tg-release-subcommands feature/issue-42-x '{"tiers":{"push":"autonomous","prCreate":"autonomous","issueAssign":"autonomous","issueCreate":"autonomous"}}' \
    "every Tier 2 action autonomous; editing (which publishes a draft), deleting a release, and adding or removing its files, through gh release or gh api, ask under tiers.release; reading or downloading a release stays silent (T22)"
  while IFS='|' read -r WANT C; do
    _tg_run "$C"
    case "$WANT" in
      release) _expect_ask "Creating a release or pushing a tag is a Tier 3 action (tiers.release)" ;;
      silent) _expect_silent_allow; e2e_expect_equal "" "$E2E_ERR" "stderr for: $C" ;;
    esac
  done <<'EOF'
release|gh release edit v1 --draft=false
release|gh release edit v1 --tag v2 --verify-tag
release|gh release delete v1 --cleanup-tag -y
release|gh -R o/r release delete v1
release|gh release upload v1 a.zip --clobber
release|gh release delete-asset v1 a.zip -y
release|gh api -X DELETE repos/o/r/releases/123
release|gh api -X POST https://uploads.github.com/repos/o/r/releases/123/assets?name=a.zip --input a.zip
release|gh api -X DELETE repos/o/r/releases/assets/5
silent|gh release view v1
silent|gh release list
silent|gh release download v1 -p '*.zip'
silent|gh api repos/o/r/releases/123/assets
silent|gh api -X PATCH repos/o/r/releases/assets/5 -f name=x
EOF
  e2e_expect_clean_edges
fi

# --- T6, T7: gh api ------------------------------------------------------------
if _want tg-api; then
  _tg_setup tg-api feature/issue-42-x "$ALL_CONFIRM" \
    "every tier confirm; gh api writes to the tiered endpoints ask with the right key, in every way the method and endpoint can be written (T6)"
  while IFS='|' read -r KEY C; do
    _tg_run "$C"
    _expect_ask "tiers.$KEY"
  done <<'EOF'
merge|gh api -X PUT repos/o/r/pulls/7/merge
merge|gh api --method PUT /repos/{owner}/{repo}/pulls/7/merge -f merge_method=squash
merge|gh api -X POST https://api.github.com/repos/o/r/merges -f base=main -f head=x
release|gh api --method POST /repos/{owner}/{repo}/releases -f tag_name=v1
release|gh api -XPOST repos/o/r/releases/
prCreate|gh api --method=post repos/o/r/pulls
issueCreate|gh api repos/o/r/issues -f title=x
issueCreate|gh api -H 'Accept: application/vnd.github+json' --jq .number --method POST repos/o/r/issues
issueCreate|gh api repos/o/r/issues?per_page=1 --input body.json
issueAssign|gh api -X POST repos/o/r/issues/4/assignees -f 'assignees[]=me'
EOF
  e2e_expect_clean_edges
fi

# --- T6: every way gh reads an option of gh api --------------------------------
if _want tg-api-forms; then
  _tg_setup tg-api-forms feature/issue-42-x "$ALL_CONFIRM" \
    "every tier confirm; gh api's method and fields are read as gh reads them (-X=VALUE, -XVALUE, -X VALUE, a bundle such as -iX=POST, -f=key=value); a method that is not a known verb, or a variable, asks for an endpoint that a write would make a merge or a release; a ref read from a file (-F ref=@file) asks; a raw -f value starting with @ is text; an endpoint is read percent-decoded and without a redirection glued to it (T6, T7)"
  while IFS='|' read -r WANT C; do
    _tg_run "$C"
    case "$WANT" in
      silent) _expect_silent_allow; e2e_expect_equal "" "$E2E_ERR" "stderr for: $C" ;;
      unknown) _expect_ask "may merge a pull request or create a release" ;;
      maybe) _expect_ask "may push or delete a tag" ;;
      *) _expect_ask "is a Tier 3 action (tiers.$WANT)" ;;
    esac
  done <<'EOF'
release|gh api -X=POST repos/o/r/releases -f tag_name=v9
release|gh api -X=PATCH repos/o/r/releases/1 -F draft=false
release|gh api -X=DELETE repos/o/r/git/refs/tags/v1.0.0
release|gh api -X=POST repos/o/r/git/refs -f ref=refs/tags/v9 -f sha=abc
merge|gh api -X=PUT repos/o/r/pulls/1/merge
release|gh api -iX=POST repos/o/r/releases -f tag_name=v9
release|gh api -iXPOST repos/o/r/releases
release|gh api -iX POST repos/o/r/releases
release|gh api --method=DELETE repos/o/r/releases/1
release|gh api repos/o/r/releases -f=tag_name=v9
release|gh api repos/o/r/git/refs -f=ref=refs/tags/v9 -f sha=abc
release|gh api repos/o/r/git/refs -fref=refs/tags/v9 -f sha=abc
release|gh api repos/o/r/git/refs --raw-field=ref=refs/tags/v9 -f sha=abc
unknown|gh api -X "$M" repos/o/r/releases/1
unknown|gh api -X "$M" repos/o/r/git/refs/tags/v1
unknown|gh api --method=$M repos/o/r/pulls/1/merge
unknown|gh api -X OPTIONS repos/o/r/pulls/1/merge
unknown|gh api -X=POSTX repos/o/r/releases
unknown|gh api -X= repos/o/r/releases
maybe|gh api repos/o/r/git/refs -F ref=@ref.txt -f sha=abc
maybe|gh api repos/o/r/git/refs --field=ref=@- -f sha=abc
maybe|gh api repos/o/r/git/refs -f "$K=refs/heads/x" -f ref=refs/heads/y -f sha=abc
silent|gh api repos/o/r/git/refs -f ref=@heads.txt -f sha=abc
silent|gh api -X=GET repos/o/r/releases
silent|gh api -X "$M" repos/o/r/issues/3/comments
silent|gh api -X OPTIONS repos/o/r/issues
unknown|printf '%s\n' repos/o/r/pulls/1/merge | xargs gh api -X PUT
unknown|xargs -n1 gh api --method=POST < endpoints.txt
merge|gh api -q '1>0' -X PUT repos/o/r/pulls/1/merge
merge|gh api -X PUT repos/o/r/pulls/1/merge>/dev/null
release|gh api -X DELETE repos/o/r/git/refs/tags%2Fv1
release|gh api -X POST repos/o/r/%72eleases -f tag_name=v9
merge|gh api -X PUT repos/o/r/pulls/1%2Fmerge
silent|gh api -X DELETE repos/o/r/git/refs/heads%2Fx
release|gh api repos/o/r/releases -f tag_name=v9>/dev/null
EOF
  e2e_expect_equal "" "$(_tg_journals)" "journal files"
  e2e_expect_clean_edges
fi

if _want tg-api-unreadable; then
  _tg_setup tg-api-unreadable feature/issue-42-x '{"tiers":{"push":"autonomous","prCreate":"autonomous","issueAssign":"autonomous","issueCreate":"autonomous"}}' \
    "a gh api POST whose whole endpoint is a variable or a substitution asks, since it may be a merge, even with every other tier autonomous; a GET of a variable endpoint does not (T7)"
  _tg_run 'gh api -X POST "$EP" -f x=1'
  _expect_ask "may merge a pull request or create a release"
  _tg_run 'gh api -X PUT $(cat endpoint.txt)'
  _expect_ask "may merge a pull request or create a release"
  _tg_run 'gh api "$EP"'
  _expect_silent_allow
  e2e_expect_clean_edges
fi

# --- T31: a command on a shell's input, in a substitution, around 2>&1 ---------
if _want tg-shell-input; then
  _tg_setup tg-shell-input feature/issue-42-x '{"tiers":{"push":"autonomous","prCreate":"autonomous","issueAssign":"autonomous","issueCreate":"autonomous"}}' \
    "every Tier 2 action autonomous, tag v1.2.0 and branch v1-fix: a here-string a shell reads as its script (any spacing, a file descriptor before <<<, before the command word, through a pipe, escaped spaces) or one given to a program the hook does not know, a shell's -c argument inside a substitution, a backquote inside double quotes, and an action with 2>&1 or >&2 in the middle of it ask; the same text read by cat or grep, an escaped or single-quoted backquote, a branch push with 2>&1, and up to 16 quoted words after one program that name no Tier 3 action do not; a 17th quoted word that names one asks (T31)"
  ( _e2e_git_env; cd "$E2E_REPO" && git tag -a v1.2.0 -m "v1.2.0" && git branch v1-fix ) \
    || _flow_assert_fail "tg-shell-input: could not create the tag and branch"
  while IFS='|' read -r WANT C; do
    _tg_run "$C"
    case "$WANT" in
      silent) _expect_silent_allow; e2e_expect_equal "" "$E2E_ERR" "stderr for: $C" ;;
      maybe) _expect_ask "may push or delete a tag" ;;
      unknown) _expect_ask "may merge a pull request or create a release" ;;
      *) _expect_ask "is a Tier 3 action (tiers.$WANT)" ;;
    esac
  done <<'EOF'
release|bash <<<'gh release create v9'
release|bash <<< 'gh release create v9'
release|sh <<<"git push --tags"
merge|bash 0<<<'gh pr merge 1'
merge|<<<'gh pr merge 1' bash
merge|cat <<<'gh pr merge 1' | bash
merge|bash <<<gh\ pr\ merge\ 1
merge|bash -c gh\ pr\ merge\ 1
merge|x=$(bash -c 'gh pr merge 1')
release|x=$(sh -c "git push --tags")
merge|y=`bash -c 'gh pr merge 1'`
merge|x="`gh pr merge 1`"
release|echo "v: `git push --tags`"
merge|gh pr comment 1 --body "`gh pr merge 1`"
silent|git commit -m "run \`gh pr merge 1\` later"
silent|git commit -m 'run `gh pr merge 1` later'
silent|cat <<<'gh pr merge 1'
silent|grep -c merge <<<'gh pr merge 1'
release|git push 2>&1 --tags
release|git push origin 2>&1 v1.2.0
release|git push origin >&2 v1.2.0
release|gh release 2>&1 create v9
release|gh api 2>&1 -X POST repos/o/r/releases -f tag_name=v9
merge|gh api -X PUT 2>&1 repos/o/r/pulls/1/merge
silent|git push -u origin HEAD 2>&1 | tail -3
silent|git push origin v1-fix 2>&1 >/dev/null
silent|git push origin 2>&1 v1-fix
merge|script -q /dev/null <<<'gh pr merge 1'
release|mytool 0<<<"git push --tags"
silent|mytool <<<'gh pr view 1'
silent|mytool 'gh pr view 1' 'gh pr view 2' 'gh pr view 3' 'gh pr view 4' 'gh pr view 5' 'gh pr view 6' 'gh pr view 7' 'gh pr view 8' 'gh pr view 9' 'gh pr view 10' 'gh pr view 11' 'gh pr view 12' 'gh pr view 13' 'gh pr view 14' 'gh pr view 15' 'gh pr view 16' 'gh pr view 17' 'gh pr view 18' 'gh pr view 19' 'gh pr view 20'
unknown|mytool 'gh release view v1' 'gh release view v2' 'gh release view v3' 'gh release view v4' 'gh release view v5' 'gh release view v6' 'gh release view v7' 'gh release view v8' 'gh release view v9' 'gh release view v10' 'gh release view v11' 'gh release view v12' 'gh release view v13' 'gh release view v14' 'gh release view v15' 'gh release view v16' 'gh release view v17'
merge|mytool 'gh pr view 1' 'gh pr view 2' 'gh pr view 3' 'gh pr view 4' 'gh pr view 5' 'gh pr view 6' 'gh pr view 7' 'gh pr view 8' 'gh pr view 9' 'gh pr view 10' 'gh pr view 11' 'gh pr view 12' 'gh pr view 13' 'gh pr view 14' 'gh pr view 15' 'gh pr view 16' 'gh pr merge 9'
EOF
  e2e_expect_clean_edges
fi

# --- T32: a cd into another worktree of the same repository ---------------------
if _want tg-cd-worktree; then
  _tg_setup tg-cd-worktree feature/issue-42-x '{"tiers":{"push":"autonomous","prCreate":"autonomous","issueAssign":"autonomous","issueCreate":"autonomous"}}' \
    "a worktree ../wt of this repository (branch wt-branch), a separate repository ../other, tag v1.2.0: a cd into the worktree reads the push there as a branch push when it names its remote, asks when the remote is left to the branch's configuration or the worktree has its own configuration; a cd to \$(git rev-parse --show-toplevel) is a cd to the top of this repository; a cd to a variable, to another repository, or to any other substitution asks (T32)"
  ( _e2e_git_env; cd "$E2E_REPO" && git tag -a v1.2.0 -m "v1.2.0" && git branch v1-fix \
      && git worktree add -q -b wt-branch "$E2E_DIR/wt" && git init -q "$E2E_DIR/other" ) >/dev/null 2>&1 \
    || _flow_assert_fail "tg-cd-worktree: could not create the worktree"
  while IFS='|' read -r WANT C; do
    _tg_run "$C"
    case "$WANT" in
      ask) _expect_ask "Creating a release or pushing a tag is a Tier 3 action (tiers.release)" ;;
      maybe) _expect_ask "may push or delete a tag" ;;
      silent) _expect_silent_allow; e2e_expect_equal "" "$E2E_ERR" "stderr for: $C" ;;
    esac
  done <<'EOF'
silent|cd ../wt && git push -u origin HEAD
silent|cd ../wt && git push origin wt-branch
silent|cd ../wt && gh pr create --title t --body b
silent|git -C ../wt push -u origin HEAD
ask|cd ../wt && git push origin v1.2.0
maybe|cd ../wt && git push
maybe|cd ../other && git push -u origin HEAD
silent|cd "$(git rev-parse --show-toplevel)" && git push -u origin HEAD
silent|cd "$(git rev-parse --show-toplevel)" && git push
silent|cd $(git rev-parse --show-toplevel) && git push origin v1-fix
silent|cd "`git rev-parse --show-toplevel`" && git push origin v1-fix
maybe|cd "$(git rev-parse --show-toplevel)/sub" && git push origin v1-fix
maybe|cd "$(git -C ../other rev-parse --show-toplevel)" && git push origin v1-fix
maybe|cd "$(git rev-parse --show-toplevel)" && cd .. && git push origin v1-fix
maybe|cd $REPO_ROOT && git push origin v1-fix
EOF
  # A worktree with configuration of its own may push tags where this one
  # does not.
  ( _e2e_git_env; git -C "$E2E_REPO" config extensions.worktreeConfig true ) >/dev/null 2>&1 \
    || _flow_assert_fail "tg-cd-worktree: could not set extensions.worktreeConfig"
  _tg_run 'cd ../wt && git push -u origin HEAD'
  _expect_ask "may push or delete a tag"
  e2e_expect_clean_edges
fi

# --- T8, T9: where the journal line goes ----------------------------------------
if _want tg-journal-session; then
  _tg_setup tg-journal-session feature/no-number '{"tiers":{"push":"journal"}}' \
    "tiers.push journal on a branch with no issue number: the breadcrumb goes to .decisions/auto-log/session-<local day>.md, with a UTC time, and no tracked journal is created (T8)"
  _tg_run 'git push origin HEAD'
  _expect_silent_allow
  SESSION_FILE=""
  for D in "$TG_DAY_AFTER" "$TG_DAY_BEFORE"; do
    [ -f "$E2E_REPO/.decisions/auto-log/session-$D.md" ] && { SESSION_FILE=".decisions/auto-log/session-$D.md"; break; }
  done
  e2e_expect_equal ".decisions/auto-log/session-$TG_DAY_AFTER.md" "$(_tg_trail)" "trail files"
  e2e_expect_equal "" "$(_tg_journals)" "tracked journal files"
  LINE=$(grep 'tiers.push (journal)' "$E2E_REPO/$SESSION_FILE" 2>/dev/null)
  case "$LINE" in
    "<!-- auto-log: "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z' tiers.push (journal) "git push origin HEAD" -->')
      _e2e_result pass "the breadcrumb is '<!-- auto-log: <UTC time> tiers.push (journal) \"<command>\" -->'" ;;
    *) _e2e_result fail "the breadcrumb is '<!-- auto-log: <UTC time> tiers.push (journal) \"<command>\" -->' (got '$LINE')" ;;
  esac
  e2e_expect_clean_edges
fi

if _want tg-journal-no-dir; then
  _tg_setup tg-journal-no-dir feature/issue-42-x '{"tiers":{"push":"journal"}}' \
    "tiers.push journal in a repository with no .decisions directory: no output, and no directory or file is created (T8)"
  rmdir "$E2E_REPO/.decisions"
  _tg_run 'git push'
  _expect_silent_allow
  e2e_expect_equal "" "$E2E_ERR" "stderr"
  e2e_expect_equal "no" "$([ -e "$E2E_REPO/.decisions" ] && echo yes || echo no)" ".decisions exists"
  e2e_expect_clean_edges
fi

if _want tg-journal-dir-setting; then
  _tg_setup tg-journal-dir-setting feature/issue-42-x '{"tiers":{"push":"journal"},"journal":{"dir":"notes"}}' \
    "journal.dir notes: the breadcrumb goes to notes/auto-log/issue-42.<YYYY-MM>.md, and none to .decisions (T8)"
  mkdir -p "$E2E_REPO/notes"
  _tg_run 'git push'
  _expect_silent_allow
  e2e_expect_equal "notes/auto-log/issue-42.$(date +%Y-%m).md" "$(_tg_trail notes)" "trail files under notes"
  e2e_expect_file_has "notes/auto-log/issue-42.$(date +%Y-%m).md" 'tiers.push (journal) "git push"'
  e2e_expect_equal "" "$(_tg_trail)" "trail files under .decisions"
  e2e_expect_clean_edges
fi

if _want tg-ask-no-journal; then
  _tg_setup tg-ask-no-journal feature/issue-42-x '{"tiers":{"push":"journal"}}' \
    "git push (journal) chained with gh pr merge (confirm): one ask naming the merge, and no journal line for the push, since the person may refuse (T9)"
  _tg_run 'git push && gh pr merge 7 --repo o/r --squash'
  _expect_ask "tiers.merge"
  e2e_expect_no_out "tiers.push"
  e2e_expect_equal "" "$(_tg_journals)" "journal files"
  e2e_expect_clean_edges
fi

if _want tg-two-journal; then
  _tg_setup tg-two-journal feature/issue-42-x '{"tiers":{"push":"journal","prCreate":"journal"}}' \
    "git push then gh pr create, both journal: one breadcrumb each, in that order, in the issue-42 trail (T8)"
  _tg_run 'git push -u origin HEAD && gh pr create --fill'
  _expect_silent_allow
  e2e_expect_equal "push,prCreate" "$(grep -oE 'tiers\.[A-Za-z]+ \(journal\)' "$E2E_REPO/$(_tg_trail42)" | sed -E 's/tiers\.([A-Za-z]+).*/\1/' | tr '\n' ',' | sed 's/,$//')" "breadcrumb keys in order"
  e2e_expect_clean_edges
fi

# --- T10: values and helpers that fail -------------------------------------------
if _want tg-bad-value; then
  _tg_setup tg-bad-value feature/issue-42-x '{"tiers":{"push":"sometimes"}}' \
    "tiers.push sometimes: allowed, no journal line, one stderr line naming tiers.push and the value (T10)"
  _tg_run 'git push'
  _expect_silent_allow
  e2e_expect_err 'tiers.push is "sometimes", not autonomous, journal or confirm'
  e2e_expect_equal 1 "$(printf '%s\n' "$E2E_ERR" | grep -c .)" "stderr lines"
  e2e_expect_equal "" "$(_tg_journals)" "journal files"
  e2e_expect_clean_edges
fi

if _want tg-cascade-fails; then
  _tg_setup tg-cascade-fails feature/issue-42-x '{"tiers":{"push":"confirm"}}' \
    "cascade-resolve.sh exits 2: git push is allowed with one stderr line naming tiers.push; gh pr merge still asks (T10)"
  e2e_plugin_copy bin/cascade-resolve.sh '#!/bin/sh
exit 2'
  _tg_run 'git push'
  _expect_silent_allow
  e2e_expect_err "could not read tiers.push (cascade-resolve.sh exit 2)"
  e2e_expect_equal 1 "$(printf '%s\n' "$E2E_ERR" | grep -c .)" "stderr lines"
  _tg_run 'gh pr merge 7 --repo o/r --squash'
  _expect_ask "tiers.merge"
  e2e_expect_clean_edges
fi

if _want tg-crumb-safe; then
  _tg_setup tg-crumb-safe feature/issue-42-x '{"tiers":{"push":"journal"}}' \
    "a pushed refspec holding a comment terminator: the breadcrumb neutralizes it, so it stays one HTML comment (T8)"
  _tg_run "git push origin 'HEAD:refs/heads/a-->b<!--c'"
  _expect_silent_allow
  e2e_expect_file_has "$(_tg_trail42)" 'tiers.push (journal) "git push origin HEAD:refs/heads/a-- >b< !--c" -->'
  e2e_expect_equal 1 "$(grep -o -- '-->' "$E2E_REPO/$(_tg_trail42)" 2>/dev/null | wc -l | tr -d ' ')" "comment terminators in the trail"
  e2e_expect_clean_edges
fi

if _want tg-trail-dir-symlink; then
  _tg_setup tg-trail-dir-symlink feature/issue-42-x '{"tiers":{"push":"journal"}}' \
    "the trail directory .decisions/auto-log is a symlink to a directory outside the repository: git push is allowed with one stderr line naming it, and nothing is written there (T10)"
  mkdir -p "$E2E_DIR/elsewhere"
  ln -s "$E2E_DIR/elsewhere" "$E2E_REPO/.decisions/auto-log"
  _tg_run 'git push'
  _expect_silent_allow
  e2e_expect_err "could not write to the auto-log trail (the trail directory is a symlink)"
  e2e_expect_equal "" "$(ls -A "$E2E_DIR/elsewhere")" "files in the link's target"
  e2e_expect_clean_edges
fi

if _want tg-journal-fails; then
  _tg_setup tg-journal-fails feature/issue-42-x '{"tiers":{"push":"journal"}}' \
    "the trail file is a symlink: git push is allowed with one stderr line, and the link's target is untouched (T10)"
  printf 'outside\n' > "$E2E_DIR/outside.md"
  mkdir -p "$E2E_REPO/.decisions/auto-log"
  ln -s "$E2E_DIR/outside.md" "$E2E_REPO/$(_tg_trail42)"
  _tg_run 'git push'
  _expect_silent_allow
  e2e_expect_err "could not write to the auto-log trail (the trail file is a symlink)"
  e2e_expect_equal 1 "$(printf '%s\n' "$E2E_ERR" | grep -c .)" "stderr lines"
  e2e_expect_equal "outside" "$(cat "$E2E_DIR/outside.md")" "the link target"
  e2e_expect_clean_edges
fi

# --- T11: cannot read the command ------------------------------------------------
if _want tg-parser-missing; then
  _tg_setup tg-parser-missing feature/issue-42-x '{"tiers":{"push":"confirm"}}' \
    "the command parser defines nothing: gh pr merge asks, git push is allowed with one stderr line, ls is allowed silently (T11)"
  e2e_plugin_copy hooks/scripts/lib/command-parse.sh '# emptied'
  _tg_run 'gh pr merge 7 --repo o/r --squash'
  _expect_ask "tiers.merge"
  _tg_run 'git push'
  _expect_silent_allow
  e2e_expect_err "could not read the command (the command parser did not load)"
  e2e_expect_equal 1 "$(printf '%s\n' "$E2E_ERR" | grep -c .)" "stderr lines"
  _tg_run 'ls -la'
  _expect_silent_allow
  e2e_expect_equal "" "$E2E_ERR" "stderr for ls"
  e2e_expect_clean_edges
fi

if _want tg-jq-missing; then
  _tg_setup tg-jq-missing feature/issue-42-x '{"tiers":{"push":"confirm"}}' \
    "no jq on PATH: gh release create asks with valid JSON, git push is allowed with one stderr line (T11)"
  NOJQ="$E2E_DIR/nojq"
  mkdir -p "$NOJQ"
  for P in bash cat dirname tr; do ln -s "$(command -v "$P")" "$NOJQ/$P"; done
  _tg_run "PATH=$NOJQ" 'gh release create v1'
  _expect_ask "tiers.release"
  e2e_expect_equal "ask" "$(printf '%s' "$E2E_OUT" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" "the decision parsed as JSON"
  _tg_run "PATH=$NOJQ" 'git push'
  _expect_silent_allow
  e2e_expect_err "could not read the command (jq is not installed)"
  # Only the command is judged, not the rest of the payload: a transcript
  # path that mentions github and push says nothing about `ls`.
  e2e_run_hook "PATH=$NOJQ" "$HOOK" '{"transcript_path":"/home/u/github/push-merge-release.jsonl","tool_input":{"command":"ls -la"}}'
  _expect_silent_allow
  e2e_expect_equal "" "$E2E_ERR" "stderr for ls"
  e2e_expect_clean_edges
fi

if _want tg-payload-unparsable; then
  _tg_setup tg-payload-unparsable feature/issue-42-x '{"tiers":{"push":"confirm"}}' \
    "the payload is not valid JSON: a command text naming gh pr merge asks, one naming git push is allowed with one stderr line naming the payload, and one naming neither is allowed silently (T11)"
  e2e_run_hook "$HOOK" '{"tool_input":{"command":"gh pr merge 7 --repo o/r --squash"'
  _expect_ask "Flow could not read this command"
  e2e_run_hook "$HOOK" '{"tool_input":{"command":"git push origin HEAD"},'
  _expect_silent_allow
  e2e_expect_err "could not read the command (the hook payload could not be parsed)"
  e2e_run_hook "$HOOK" '{"transcript_path":"/home/u/gh-merge.jsonl","tool_input":{"command":"ls -la"'
  _expect_silent_allow
  e2e_expect_equal "" "$E2E_ERR" "stderr for ls"
  e2e_expect_clean_edges
fi

if _want tg-parser-fails; then
  _tg_setup tg-parser-fails feature/issue-42-x '{"tiers":{"push":"confirm"}}' \
    "the command parser loads but fails while reading (it exits 2, as it does when awk fails): gh pr merge asks, git push is allowed with one stderr line and no BLOCKED text (T11)"
  e2e_plugin_copy hooks/scripts/lib/command-parse.sh '_bd_strip_noncode() { echo "BLOCKED: could not scan the command (awk failed)" >&2; exit 2; }
_bd_segments() { :; }
_bd_expand_interpreter_args() { :; }
_bd_words() { TOK=(); TOKE=(); BD_HSTR=(); }
_bd_is_interpreter() { return 1; }
_bd_is_opt() { return 1; }
_BD_SEG_AWK=x'
  _tg_run 'gh pr merge 7 --repo o/r --squash'
  _expect_ask "tiers.merge"
  _tg_run 'git push'
  _expect_silent_allow
  e2e_expect_err "could not read the command (the command parser failed)"
  e2e_expect_err_lacks "BLOCKED"
  e2e_expect_clean_edges
fi

if _want tg-parser-words-fails; then
  _tg_setup tg-parser-words-fails feature/issue-42-x '{"tiers":{"push":"confirm"}}' \
    "the command parser fails while splitting a simple command into words (it exits 2, as it does when awk fails): gh pr merge asks, git push is allowed with one stderr line and no BLOCKED text (T11)"
  e2e_plugin_copy hooks/scripts/lib/command-parse.sh '_bd_strip_noncode() { BD_CODE="$1"; BD_KEPT_BODY=0; }
_bd_segments() { printf "%s\n" "$1"; }
_bd_expand_interpreter_args() { :; }
_bd_words() { echo "BLOCKED: could not split a command into words (awk failed)" >&2; exit 2; }
_bd_is_interpreter() { return 1; }
_bd_is_opt() { return 1; }
_BD_SEG_AWK=x'
  _tg_run 'gh pr merge 7 --repo o/r --squash'
  _expect_ask "tiers.merge"
  _tg_run 'git push'
  _expect_silent_allow
  e2e_expect_err "could not read the command (the command parser failed)"
  e2e_expect_err_lacks "BLOCKED"
  e2e_expect_clean_edges
fi

# --- the directory the command runs in ------------------------------------------------
if _want tg-cwd; then
  _tg_setup tg-cwd feature/issue-42-x '{"tiers":{"push":"autonomous","prCreate":"autonomous"}}' \
    "the payload's cwd names another repository (branch feature/issue-77-y, push journal, prCreate confirm) than the one the hook starts in: its settings decide and its journal gets the line (T1, T8)"
  OTHER="$E2E_DIR/other"
  mkdir -p "$OTHER"
  ( _e2e_git_env; cd "$OTHER" && git init -q && git config user.email e2e@example.invalid && git config user.name e2e \
      && git config commit.gpgsign false && printf 'o\n' > o.txt && git add o.txt && git commit -q -m init \
      && git checkout -q -b feature/issue-77-y ) || _flow_assert_fail "tg-cwd: could not create the second repository"
  mkdir -p "$OTHER/.decisions" "$OTHER/.claude"
  printf '%s\n' '{"tiers":{"push":"journal","prCreate":"confirm"}}' > "$OTHER/.claude/settings.flow.json"
  e2e_run_hook "$HOOK" "$(jq -cn --arg cwd "$OTHER" '{cwd:$cwd,tool_input:{command:"git push"}}')"
  _expect_silent_allow
  e2e_expect_equal "yes" "$(grep -q 'tiers.push (journal) "git push"' "$OTHER/.decisions/auto-log/issue-77.$(date +%Y-%m).md" 2>/dev/null && echo yes || echo no)" "the breadcrumb in the other repository's issue-77 trail"
  e2e_expect_equal "" "$(_tg_trail)" "trail files in the starting repository"
  e2e_expect_equal "" "$(_tg_journals)" "journal files in the starting repository"
  e2e_run_hook "$HOOK" "$(jq -cn --arg cwd "$OTHER" '{cwd:$cwd,tool_input:{command:"gh pr create --fill"}}')"
  _expect_ask "tiers.prCreate"
  e2e_expect_clean_edges
fi

# --- T12: registration --------------------------------------------------------------
if _want tg-registered; then
  _flow_test_begin "tg-registered"
  REG=$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command] | map(select(endswith("/hooks/scripts/tier-gate.sh"))) | length' "$REPO_ROOT/plugins/flow/hooks/hooks.json" 2>/dev/null)
  assert_equal "1" "$REG" "hooks.json runs tier-gate.sh once on PreToolUse for Bash (T12)"
fi
