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
#      continuation is missed
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
#   T11 when the hook cannot read the command (jq missing, parser missing),
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
#      mutation (inline, query=@file, --input), is missed; a read or another
#      mutation (createIssueType) is caught; an unreadable query is allowed

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
    "every tier confirm; commands that only mention an action run none: each is allowed with no output and no journal file (T4)"
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
    'gh api --method PATCH repos/o/r/pulls/7 -f state=closed'; do
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
    "every tier confirm; a Tier 3 action handed to a program the hook does not know (caffeinate, stdbuf, setsid, watch, find -exec, parallel, script, a variable) asks; a Tier 2 action there, echo or printf of a Tier 3 action, and a gh or git word that runs nothing stay silent (T23)"
  while IFS='|' read -r WANT C; do
    _tg_run "$C"
    case "$WANT" in
      maybe) _expect_ask "may push or delete a tag" ;;
      unknown) _expect_ask "may merge a pull request or create a release" ;;
      silent) _expect_silent_allow; e2e_expect_equal "" "$E2E_ERR" "stderr for: $C" ;;
      *) _expect_ask "is a Tier 3 action (tiers.$WANT)" ;;
    esac
  done <<'EOF'
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
EOF
  for C in 'echo g\h pr merge 1' 'git commit -m "gh pr mer\ge 1"' 'gh pr vi\ew 3'; do
    _tg_run "$C"
    _expect_silent_allow
  done
  e2e_expect_equal "" "$(_tg_journals)" "journal files"
  e2e_expect_clean_edges
fi

# --- T13: a tag push is the release tier ------------------------------------------
if _want tg-tag-push; then
  _tg_setup tg-tag-push feature/issue-42-x '{"tiers":{"push":"autonomous"}}' \
    "push autonomous, the repository has tag v1.2.0 and branches v1-fix and main: every push that sends a tag asks under tiers.release (options abbreviated or bundled as git accepts them included), a source that is not a local branch asks as a possible tag, every branch-only push is silent (T13, T19, T20)"
  ( _e2e_git_env; cd "$E2E_REPO" && git tag -a v1.2.0 -m "v1.2.0" && git branch v1-fix && git branch -f main HEAD ) \
    || _flow_assert_fail "tg-tag-push: could not create the tag and branch"
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
silent|git -c remote.origin.pushurl=x push origin HEAD
silent|git -c remote.pushDefault=origin push origin HEAD
EOF
  _tg_cfg() { ( _e2e_git_env; cd "$E2E_REPO" && git config "$@" ) || _flow_assert_fail "tg-remote-config: git config $*"; }
  _tg_release_ask() { _expect_ask "Creating a release or pushing a tag is a Tier 3 action (tiers.release)"; }
  _tg_cfg remote.origin.mirror true
  _tg_run 'git push origin'
  _tg_release_ask
  _tg_run 'git push'
  _tg_release_ask
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
  _tg_run 'gh release create v1.2.0 --verify-tag && gh pr merge 7 --repo o/r --squash'
  _expect_ask "tiers.merge"
  e2e_expect_equal 1 "$(grep -c 'verify-tag' "$E2E_REPO/$(_tg_trail42)" 2>/dev/null)" "breadcrumbs after the run that also asked"
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
    "every tier confirm; gh api PATCH on a release or on an issue's assignees, and GraphQL mutations read inline, from query=@file and from --input, ask with the right key, a mutation whose name holds Ref, Release or Merge in any case among them; reads and other mutations do not (T15)"
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
merge|gh api graphql -f query='mutation { disablePullRequestAutoMerge(input:{pullRequestId:"x"}) { clientMutationId } }'
silent|gh api graphql -f query='query { repository(owner:"o", name:"r") { refs(first:5, refPrefix:"refs/tags/") { nodes { name } } } }'
silent|gh api graphql -f query='query { repository(owner:"o", name:"r") { pullRequest(number:1) { headRefName mergeable } } }'
silent|gh api graphql -f query='mutation { addComment(input:{subjectId:"x", body:"merge the release ref"}) { clientMutationId } }'
silent|gh api graphql --input read.json
silent|gh api -X PATCH repos/o/r/issues/4 -f title=x
silent|gh api -X PATCH repos/o/r/releases/assets/5 -f name=x
silent|gh api -X PUT repos/o/r/releases/123 -f name=x
silent|gh api -X GET repos/o/r/releases/123
silent|gh api -X PATCH repos/o/r/issues/4/comments -f assignees=x
EOF
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
_rm_tokenise() { TOK=(); }
_bd_unescape_tok() { :; }
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
