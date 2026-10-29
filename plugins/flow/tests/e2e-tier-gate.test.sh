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
      "tiers.$KEY journal on branch feature/issue-42-x: no output, and one line naming tiers.$KEY and the command in .decisions/issue-42.md (T1, T2, T8)"
    _tg_run "$CMD"
    _expect_silent_allow
    e2e_expect_equal "issue-42.md" "$(_tg_journals)" "journal files"
    e2e_expect_file_has .decisions/issue-42.md "tiers.$KEY (journal): ${CMD%% --*}"
    e2e_expect_equal 1 "$(grep -c "tiers\.$KEY (journal)" "$E2E_REPO/.decisions/issue-42.md" 2>/dev/null)" "journal lines"
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
  e2e_expect_file_has .decisions/issue-42.md "tiers.push (journal): git push"
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
    "tiers.push journal on a branch with no issue number: the line goes to .decisions/session-<local day>.md, with a UTC time (T8)"
  _tg_run 'git push origin HEAD'
  _expect_silent_allow
  SESSION_FILE=""
  for D in "$TG_DAY_AFTER" "$TG_DAY_BEFORE"; do
    [ -f "$E2E_REPO/.decisions/session-$D.md" ] && { SESSION_FILE=".decisions/session-$D.md"; break; }
  done
  e2e_expect_equal "session-$TG_DAY_AFTER.md" "$(_tg_journals)" "journal files"
  e2e_expect_file_has "$SESSION_FILE" "tiers.push (journal): git push origin HEAD"
  LINE=$(grep 'tiers.push (journal)' "$E2E_REPO/$SESSION_FILE" 2>/dev/null)
  case "$LINE" in
    "- "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z" tiers.push (journal): git push origin HEAD")
      _e2e_result pass "the line is '- <UTC time> tiers.push (journal): <command>'" ;;
    *) _e2e_result fail "the line is '- <UTC time> tiers.push (journal): <command>' (got '$LINE')" ;;
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
    "journal.dir notes: the line goes to notes/issue-42.md, and none to .decisions (T8)"
  mkdir -p "$E2E_REPO/notes"
  _tg_run 'git push'
  _expect_silent_allow
  e2e_expect_file_has notes/issue-42.md "tiers.push (journal): git push"
  e2e_expect_equal "" "$(_tg_journals)" "journal files under .decisions"
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
    "git push then gh pr create, both journal: one line each, in that order, in issue-42.md (T8)"
  _tg_run 'git push -u origin HEAD && gh pr create --fill'
  _expect_silent_allow
  e2e_expect_equal "push,prCreate" "$(grep -oE 'tiers\.[A-Za-z]+ \(journal\)' "$E2E_REPO/.decisions/issue-42.md" | sed -E 's/tiers\.([A-Za-z]+).*/\1/' | tr '\n' ',' | sed 's/,$//')" "journal keys in order"
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

if _want tg-journal-fails; then
  _tg_setup tg-journal-fails feature/issue-42-x '{"tiers":{"push":"journal"}}' \
    "the issue journal is a symlink, so journal-append.sh refuses it: git push is allowed with one stderr line, and the link's target is untouched (T10)"
  printf 'outside\n' > "$E2E_DIR/outside.md"
  ln -s "$E2E_DIR/outside.md" "$E2E_REPO/.decisions/issue-42.md"
  _tg_run 'git push'
  _expect_silent_allow
  e2e_expect_err "could not append to the decision journal (journal-append.sh exit 2"
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

if _want tg-parser-fails; then
  _tg_setup tg-parser-fails feature/issue-42-x '{"tiers":{"push":"confirm"}}' \
    "the command parser loads but fails while reading (it exits 2, as it does when awk fails): gh pr merge asks, git push is allowed with one stderr line and no BLOCKED text (T11)"
  e2e_plugin_copy hooks/scripts/lib/command-parse.sh '_bd_strip_noncode() { echo "BLOCKED: could not scan the command (awk failed)" >&2; exit 2; }
_bd_segments() { :; }
_bd_expand_interpreter_args() { :; }
_rm_tokenise() { TOK=(); }
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
  e2e_expect_equal "yes" "$(grep -q 'tiers.push (journal): git push' "$OTHER/.decisions/issue-77.md" 2>/dev/null && echo yes || echo no)" "the line in the other repository's issue-77.md"
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
