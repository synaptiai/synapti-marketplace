#!/usr/bin/env bash
# [flow] PreToolUse hook (matcher: Bash): apply the tier settings (`tiers.*`)
# to the Bash command about to run.
#
# Flow sorts the actions that leave the machine into tiers
# (references/three-tier-safety.md). Each has a setting, resolved through
# bin/cascade-resolve.sh:
#
#   tiers.push         git push                                  default journal
#   tiers.prCreate     gh pr create                              default journal
#   tiers.issueAssign  gh issue edit --add-assignee              default journal
#   tiers.issueCreate  gh issue create                           default journal
#   tiers.merge        gh pr merge                               always confirm
#   tiers.release      gh release create, and a tag push         always confirm
#
# `new` is gh's alias for `create` (`gh pr new`, `gh issue new`, `gh release
# new`) and counts the same. `gh api` counts as follows. A leading `/`, a full
# https:// URL, a query string and `{owner}/{repo}` placeholders are allowed;
# the method is -X/--method, or POST when a -f/-F/--field/--raw-field/--input
# parameter is given (gh's own rule), or GET.
#   POST/PUT .../pulls/{n}/merge, .../merges              merge
#   POST .../releases; PATCH .../releases/{id}            release
#   POST .../git/refs with a refs/tags/ ref               release
#   DELETE or PATCH .../git/refs/tags/{tag}               release
#   POST .../pulls                                        prCreate
#   POST .../issues                                       issueCreate
#   POST .../issues/{n}/assignees; PATCH or PUT
#     .../issues/{n} with an assignee or assignees field  issueAssign
#   graphql with mergePullRequest or
#     enablePullRequestAutoMerge                          merge
#   graphql with createRelease or updateRelease           release
#   graphql with createPullRequest                        prCreate
#   graphql with createIssue                              issueCreate
#   graphql with addAssigneesToAssignable                 issueAssign
# The GraphQL query is read from -f/-F query=..., query=@file and --input
# file (relative to the command's directory).
#
# Pushing a tag is the release tier, not push: `git push` with --tags,
# --follow-tags, --mirror, `-c push.followTags=true`, or push.followTags true
# in the repository's git configuration (a -c on the command line overrides
# it); `git push <remote> tag <name>`; a refspec with refs/tags/ on either
# side (`HEAD:refs/tags/v1`); or a refspec whose source is a tag in this
# repository (`git push origin v1.2.0` when v1.2.0 is a tag; a branch named
# v1-fix is not). Deleting a tag is release too: `:<tag>`, `:refs/tags/<tag>`,
# or --delete/-d with a tag's name; a deleted name that is neither a tag nor
# a known branch (local, or remote-tracking on that remote) may be a tag on
# the remote, so it asks. A command that pushes a branch and a tag is
# release.
#
# `git -C <dir>`, `--git-dir` and `--work-tree` name the repository a push
# acts on: tags, push.followTags and the breadcrumb's trail are taken from
# that repository, not the payload's. When it cannot be found (a missing
# directory, a variable), the payload's repository is used and the push asks
# if it could be a tag push (anything but HEAD or refs/heads/ refspecs with
# push.followTags turned off by -c).
#
# `gh release create <tag> --verify-tag` creates a release for a tag that
# must already be on GitHub, and that tag's push was already confirmed. So
# when `git ls-remote --tags` finds the tag on the remote (origin, or the
# GitHub repository -R/--repo names), within TG_REMOTE_TIMEOUT seconds
# (default 5), it is journaled instead of asked. Without --verify-tag, with a
# tag absent from the remote, or when the check fails, it asks.
#
# Values: confirm asks (permissionDecision "ask", with a reason naming the
# action, the setting and the command); journal writes one breadcrumb to the
# git-ignored auto-log trail and allows; autonomous allows. merge and release
# have a floor of confirm: they always ask, and a lower value is ignored with
# one stderr line naming the setting. An "ask" is a prompt in an interactive
# session, bypassPermissions mode included, and a refusal in `claude -p`,
# which has no one to ask.
#
# Decision table:
#   command names no tiered action                    -> exit 0, no output
#   every action it names resolves to autonomous      -> exit 0, no output
#   any action resolves to confirm (merge and release -> exit 0, stdout JSON permissionDecision "ask"
#     always do)                                         naming each such action; no breadcrumb is
#                                                        written, since the person may refuse
#   merge or release set below confirm                -> as above, plus one stderr line naming the setting
#   gh release create --verify-tag, tag on the remote -> journaled, as below
#   gh release create --verify-tag, tag not found or  -> "ask"
#     the check failed or timed out
#   otherwise, journal-tier actions                   -> one breadcrumb per action in the auto-log
#                                                        trail (<journal dir>/auto-log/issue-{N}.{YYYY-MM}.md
#                                                        on a branch naming issue N, otherwise
#                                                        auto-log/session-{YYYY-MM-DD}.md), exit 0, no
#                                                        output; the tracked journal is not touched
#     the journal directory does not exist            -> nothing written, exit 0, no output (the
#                                                        repository does not keep a flow journal)
#     the trail is refused (a symlink) or the write   -> exit 0, one stderr line
#     fails
#   push, prCreate, issueAssign or issueCreate whose  -> that action is allowed, one stderr line
#     value is not autonomous|journal|confirm, or
#     whose setting cannot be read (cascade fails)
#   gh api PATCH/PUT on .../issues/{n} whose body is  -> allowed, one stderr line (it may change
#     a file (--input)                                   assignees; not a confirm-floor action)
#   a gh api write whose whole endpoint is a variable -> "ask": it may be a merge or a release
#     or a substitution, or a GraphQL query that
#     cannot be read (a variable, stdin, a missing
#     file)
#   a push whose refspec is a variable or a           -> "ask": it may push or delete a tag
#     substitution, a deleted name that is neither
#     tag nor branch, a push into a -C/--git-dir
#     repository that cannot be found, or a gh api
#     git/refs request whose ref cannot be read
#   cannot decide: jq missing, the command parser     -> text that mentions merge or release with gh:
#     missing or failed                                    "ask"; other text that mentions push or gh:
#                                                        exit 0, one stderr line; anything else:
#                                                        exit 0, no output
#
# In practice block-unchecked-merge.sh refuses every Bash call when jq is
# missing, so the jq row decides only when that hook is not installed.
#
# Reading the command. The command is parsed, not matched: the same parser
# block-unchecked-merge.sh and block-destructive.sh use
# (lib/command-parse.sh). `#` comments and heredoc bodies fed to cat, tee,
# echo, printf or gh are removed; the text is split into simple commands at
# `;`, `|`, `&`, newlines and command substitutions, outside quotes; each
# simple command is split into words with quotes removed; and a quoted
# argument handed to something that runs it (`bash -c '...'`, `eval`, `ssh`)
# is read as a command too. An action counts only when its program is the
# command word: first in its simple command, after any VAR=value
# assignments, and after any of these, which run the rest of the line as a
# command: command, exec, env, nohup, time, nice, timeout, sudo, doas, xargs
# (with their options). `gh` and `git` may carry a path. So `echo gh pr merge
# 1`, `git commit -m "then gh pr merge 1"` and `npm run git push` name no
# action, while `make && git push`, `x=$(gh pr create ...)` and `timeout 60
# git push` do.
#
# Not covered, by design: deliberate evasion (a command held in a variable
# and run as `$CMD`, a gh alias, a git alias, a script file, a quote inside
# the word), a GraphQL mutation not listed above, and gh api DELETE requests
# other than on tag refs. Branch protection and rulesets are the mechanism
# against evasion; this hook reads commands written in good faith. `--help` is not exempted: it costs a
# prompt, while exempting a value that happens to read `--help` would cost a
# missed confirmation. For the same reason the parser reads every quoted
# argument with a space in it, after env, sudo, timeout, xargs, nohup and the
# other words it treats as running a script, as a command too: so `timeout 60
# gh pr create --body "git push later"` also counts as a push. That costs an
# extra prompt or journal line, never a missed one.
#
# ask-issue-create.sh is a separate hook and both apply to `gh issue create`:
# Claude Code takes the most restrictive answer, so an ask from either wins.
#
# Hook input (stdin JSON): tool_input.command, and cwd when present (the
# directory the command runs in; the settings, the branch and the journal are
# read there).

set -uo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH
export PYTHONSAFEPATH=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/../..}"
# cascade-resolve.sh locates the plugin-default settings.json through
# CLAUDE_PLUGIN_ROOT, so publish the resolved root to it.
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

_tg_note() { printf 'flow: tier-gate — %s\n' "$1" >&2; }

# The ask for a command this hook could not read. Constant text, so it needs
# no jq to be valid JSON.
_tg_ask_unread() {
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Flow could not read this command, and it may merge a pull request or create a release, which flow always asks about (tiers.merge, tiers.release; Tier 3). Approve only if that is intended."}}'
}

# Cannot decide: judge the bare text instead. $1 = the text, $2 = why.
_tg_undecidable() {
  local bare
  bare=$(printf '%s' "$1" | LC_ALL=C tr -d "'\"\\\\" | LC_ALL=C tr 'A-Z' 'a-z' 2>/dev/null) || bare="merge gh"
  case "$bare" in
    *gh*merge*|*gh*release*|*merge*gh*|*release*gh*|*/merge*|*/releases*)
      _tg_ask_unread; exit 0 ;;
    *push*|*gh*)
      _tg_note "could not read the command ($2); allowing it without a tier check"
      exit 0 ;;
  esac
  exit 0
}

INPUT=$(cat 2>/dev/null) || INPUT=""

if ! command -v jq >/dev/null 2>&1; then
  # Without jq the payload cannot be parsed, so the text from the command key
  # on is judged: the rest of the payload (the transcript path, the working
  # directory) says nothing about the command.
  case "$INPUT" in
    *'"command"'*) _tg_undecidable "${INPUT#*\"command\"}" "jq is not installed" ;;
  esac
  exit 0
fi
# A payload jq cannot parse is judged like one read without jq: from the
# command key on. A payload that parses and holds no command is no command.
if ! COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  case "$INPUT" in
    *'"command"'*) _tg_undecidable "${INPUT#*\"command\"}" "the hook payload could not be parsed" ;;
  esac
  exit 0
fi
[ -z "$COMMAND" ] && exit 0

# Cheap reject before any parsing: this hook runs before every Bash call, and
# every action it knows needs `gh` or `push` in the text. Quotes and
# backslashes are removed first, so `p""ush` still reaches the parser.
_TG_BARE=$(printf '%s' "$COMMAND" | LC_ALL=C tr -d "'\"\\\\") || _TG_BARE=gh
case "$_TG_BARE" in
  *[Gg][Hh]*|*[Pp][Uu][Ss][Hh]*) ;;
  *) exit 0 ;;
esac

_TG_LIB="$SCRIPT_DIR/lib/command-parse.sh"
[ -r "$_TG_LIB" ] || _tg_undecidable "$COMMAND" "the command parser $(basename "$_TG_LIB") is missing"
# shellcheck source=lib/command-parse.sh
. "$_TG_LIB" 2>/dev/null
for _tg_fn in _bd_strip_noncode _bd_segments _bd_expand_interpreter_args _rm_tokenise _bd_unescape_tok _bd_is_opt; do
  type "$_tg_fn" >/dev/null 2>&1 || _tg_undecidable "$COMMAND" "the command parser did not load"
done
[ -n "${_BD_SEG_AWK:-}" ] || _tg_undecidable "$COMMAND" "the command parser did not load"

# --- reading one simple command ---------------------------------------------

_tg_is_assignment() {
  case "$1" in
    [A-Za-z_]*=*)
      case "${1%%=*}" in *[!A-Za-z0-9_]*) return 1 ;; esac
      return 0 ;;
  esac
  return 1
}

# A word this hook cannot read without running a shell.
_tg_unreadable() {
  case "$1" in *'$'*|*'`'*|*__BD_SUBST__*) return 0 ;; esac
  return 1
}

# The program a word names: its last path component, a leading backslash
# removed, in lower case (a case-insensitive filesystem runs `GH`).
_tg_prog() {
  local b="${1##*/}"
  b="${b#\\}"
  printf '%s' "$b" | LC_ALL=C tr 'A-Z' 'a-z'
}

# Options of a wrapper that take the next word as their value.
_tg_wrapper_value_opt() {   # $1 = wrapper, $2 = option
  case "$1:$2" in
    exec:-a|env:-u|env:--unset|env:-C|env:--chdir|env:-S|env:--split-string|\
    nice:-n|nice:--adjustment|timeout:-s|timeout:--signal|timeout:-k|timeout:--kill-after|\
    sudo:-u|sudo:--user|sudo:-g|sudo:--group|sudo:-h|sudo:--host|sudo:-p|sudo:--prompt|\
    sudo:-C|sudo:--close-from|sudo:-D|sudo:--chdir|sudo:-R|sudo:--chroot|sudo:-T|sudo:--command-timeout|\
    sudo:-U|sudo:--other-user|sudo:-r|sudo:--role|sudo:-t|sudo:--type|\
    doas:-u|doas:-C|\
    xargs:-a|xargs:--arg-file|xargs:-d|xargs:--delimiter|xargs:-E|xargs:-I|xargs:-L|xargs:--max-lines|\
    xargs:-n|xargs:--max-args|xargs:-P|xargs:--max-procs|xargs:-s|xargs:--max-chars|xargs:--process-slot-var)
      return 0 ;;
  esac
  return 1
}

# Sets TG_I to the index of the command word in TOK (n words), past
# assignments and wrappers, or to n when there is none.
_tg_command_word() {
  local i=0 w t
  # A reserved word or a group opener in command position starts a compound
  # command, and the command it runs is the next word: `if gh release create
  # v1; then`, `do gh pr merge 1`, `! git push`, `{ git push --tags; }`.
  # `function NAME` is followed by the body (`function f { git push; }`), and
  # coproc by the command it runs, or by a NAME and a body (`coproc N { ...;
  # }`). The parser splits at `(` and `)`, so `f() { ...; }`, a subshell and a
  # case pattern already start their own simple command.
  while [ "$i" -lt "$n" ]; do
    case "${TOK[i]}" in
      if|then|elif|else|while|until|do|'!'|'{') i=$((i + 1)) ;;
      function) i=$((i + 2)) ;;
      coproc)
        i=$((i + 1))
        [ "${TOK[i+1]:-}" = '{' ] && i=$((i + 1)) ;;
      *) _tg_is_assignment "${TOK[i]}" && i=$((i + 1)) || break ;;
    esac
  done
  while [ "$i" -lt "$n" ]; do
    [ "${#TOK[i]}" -le 4096 ] || break
    w=$(_tg_prog "${TOK[i]}")
    case "$w" in
      command|builtin|exec|env|nohup|time|nice|timeout|sudo|doas|xargs) ;;
      *) break ;;
    esac
    i=$((i + 1))
    while [ "$i" -lt "$n" ]; do
      t="${TOK[i]}"
      if [ "$t" = "--" ]; then i=$((i + 1)); break; fi
      if [ "$w" = env ] && _tg_is_assignment "$t"; then i=$((i + 1)); continue; fi
      if _tg_wrapper_value_opt "$w" "$t"; then i=$((i + 2)); continue; fi
      case "$t" in
        -?*) i=$((i + 1)); continue ;;
      esac
      break
    done
    # timeout's first operand is the duration, not the command.
    [ "$w" = timeout ] && [ "$i" -lt "$n" ] && i=$((i + 1))
  done
  TG_I=$i
  return 0
}

# Emit one action line: key, a tab, the command summary, a tab, and the
# top of the repository a `git -C <dir>` push names (TG_ADIR, empty for the
# payload's own).
TG_ADIR=""
_tg_emit() {   # $1 = key, $2 = index of the command word
  # The words from the command word on; a word with a space in it is shown
  # in double quotes, so `--title "Add x"` does not read as two words.
  local s="" w k
  for ((k = $2; k < n; k++)); do
    w="${TOK[k]}"
    case "$w" in *[[:space:]]*|'') w="\"$w\"" ;; esac
    s="$s${s:+ }$w"
  done
  s="${s// __BD_SUBST__ /\$(...)}"
  s="${s//__BD_SUBST__/\$(...)}"
  s=$(printf '%s' "$s" | LC_ALL=C tr '\000-\037\177' ' ' | tr -s ' ')
  if [ "${#s}" -gt 160 ]; then s="${s:0:160}..."; fi
  printf '%s\t%s\t%s\n' "$1" "$s" "$TG_ADIR"
}

# git: the subcommand past git's own options. -C, --git-dir and --work-tree
# say which repository the push acts on; tags, push.followTags and the
# journal target are judged there (TG_GDIR and TG_GARGS, the arguments every
# lookup runs git with). When they name a repository that cannot be found,
# or are given as a variable, the payload's repository is used and the push
# asks if it could be a tag push (TG_UNRES=1). GIT_DIR= and GIT_WORK_TREE=
# before git count as --git-dir and --work-tree.
#
# Configuration set for this one command can make a push send tags:
# `-c remote.<name>.mirror`, `-c remote.<name>.push=<refspec>`, the same keys
# through --config-env, and GIT_CONFIG_* before git. Each asks as a possible
# tag push (cfg=1); push.followTags through --config-env is unknown.
_tg_git() {   # $1 = index of git
  local j=$(($1 + 1)) follow="" c v o base="$CWD" gd="" wt="" explicit=0 cfg=0 k
  for ((k = 0; k < $1; k++)); do
    case "${TOK[k]}" in
      GIT_CONFIG*=*) cfg=1 ;;
      GIT_DIR=*) gd="${TOK[k]#GIT_DIR=}"; explicit=1 ;;
      GIT_WORK_TREE=*) wt="${TOK[k]#GIT_WORK_TREE=}"; explicit=1 ;;
    esac
  done
  [ -n "$gd" ] && case "$gd" in /*) ;; *) gd="$base/$gd" ;; esac
  [ -n "$wt" ] && case "$wt" in /*) ;; *) wt="$base/$wt" ;; esac
  while [ "$j" -lt "$n" ]; do
    c=""
    case "${TOK[j]}" in
      -c) c="${TOK[j+1]:-}"; j=$((j + 2)) ;;
      -c?*) c="${TOK[j]#-c}"; j=$((j + 1)) ;;
      --config-env=*)
        # --config-env=<key>=<variable>: the value is in the environment.
        c="${TOK[j]#--config-env=}"; c="${c%%=*}"; j=$((j + 1))
        c=$(printf '%s' "$c" | LC_ALL=C tr 'A-Z' 'a-z')
        case "$c" in
          push.followtags) follow=unknown ;;
          remote.*.mirror|remote.*.push) cfg=1 ;;
        esac
        continue ;;
      -C)
        v="${TOK[j+1]:-}"; j=$((j + 2)); explicit=1
        case "$v" in /*) base="$v" ;; *) base="$base/$v" ;; esac
        continue ;;
      --git-dir|--git-dir=*|--work-tree|--work-tree=*)
        o="${TOK[j]%%=*}"
        case "${TOK[j]}" in
          *=*) v="${TOK[j]#*=}"; j=$((j + 1)) ;;
          *) v="${TOK[j+1]:-}"; j=$((j + 2)) ;;
        esac
        explicit=1
        case "$v" in /*) ;; *) v="$base/$v" ;; esac
        if [ "$o" = --git-dir ]; then gd="$v"; else wt="$v"; fi
        continue ;;
      --namespace|--config-env|--super-prefix|--list-cmds) j=$((j + 2)); continue ;;
      -*) j=$((j + 1)); continue ;;
      *) break ;;
    esac
    # `-c push.followTags=true` makes the push send annotated tags too. A
    # bare `-c push.followTags` is true in git's grammar.
    c=$(printf '%s' "$c" | LC_ALL=C tr 'A-Z' 'a-z')
    case "$c" in
      push.followtags|push.followtags=true|push.followtags=yes|push.followtags=on|push.followtags=1) follow=1 ;;
      push.followtags=*) follow=0 ;;
      remote.*.mirror|remote.*.mirror=*|remote.*.push|remote.*.push=*) cfg=1 ;;
    esac
  done
  [ "$j" -lt "$n" ] || return 0
  [ "${TOK[j]}" = push ] || return 0

  TG_GDIR="$base"; TG_GARGS=(); TG_UNRES=0; TG_ADIR=""
  [ -n "$gd" ] && TG_GARGS+=("--git-dir=$gd")
  [ -n "$wt" ] && TG_GARGS+=("--work-tree=$wt")
  if [ "$explicit" = 1 ]; then
    # A directory given as a variable or a substitution names a path that
    # does not exist, so it is not found here either.
    if [ -d "$base" ] \
       && git -C "$base" ${TG_GARGS[@]+"${TG_GARGS[@]}"} rev-parse --git-dir >/dev/null 2>&1; then
      TG_ADIR=$(git -C "$base" ${TG_GARGS[@]+"${TG_GARGS[@]}"} rev-parse --show-toplevel 2>/dev/null) || TG_ADIR=""
    else
      TG_GDIR="$CWD"; TG_GARGS=(); TG_UNRES=1
    fi
  fi
  # push.followTags from git's configuration, unless a -c set it. Unknown when
  # the repository could not be found.
  if [ -z "$follow" ]; then
    if [ "$TG_UNRES" = 1 ]; then follow=unknown
    elif [ "$(_tg_git_in config --type=bool --get push.followTags 2>/dev/null)" = true ]; then follow=1
    else follow=0
    fi
  fi
  _tg_git_push "$1" $((j + 1)) "$follow" "$cfg"
  TG_ADIR=""
  return 0
}

# git, run in the repository the push acts on.
_tg_git_in() { git -C "$TG_GDIR" ${TG_GARGS[@]+"${TG_GARGS[@]}"} "$@"; }

# What a name is in the repository the push acts on: tag, branch (a local
# branch, or a remote-tracking one on the remote being pushed to), or
# unknown. Unknown too when that repository could not be found.
_tg_ref_kind() {   # $1 = name, $2 = remote
  case "$1" in ''|*'*'*) printf unknown; return 0 ;; esac
  [ "${TG_UNRES:-0}" = 1 ] && { printf unknown; return 0; }
  if _tg_git_in rev-parse -q --verify "refs/tags/$1" >/dev/null 2>&1; then printf tag
  elif _tg_git_in rev-parse -q --verify "refs/heads/$1" >/dev/null 2>&1 \
       || { [ -n "$2" ] && _tg_git_in rev-parse -q --verify "refs/remotes/$2/$1" >/dev/null 2>&1; }; then printf branch
  else printf unknown
  fi
}

# Is this name a local branch of the repository the push acts on? A
# revision suffix (`main~1`, `HEAD^`) names a commit on that branch.
_tg_is_local_branch() {   # $1 = name
  local b="${1%%[~^]*}"
  case "$b" in HEAD|@) return 0 ;; ''|*'*'*) return 1 ;; esac
  [ "${TG_UNRES:-0}" = 1 ] && return 1
  case "$b" in refs/heads/?*) b="${b#refs/heads/}" ;; esac
  _tg_git_in rev-parse -q --verify "refs/heads/$b" >/dev/null 2>&1
}

# The remote a push that names none goes to, found as git finds it:
# branch.<branch>.pushRemote, remote.pushDefault, branch.<branch>.remote,
# then origin.
_tg_push_remote() {
  local b r=""
  b=$(_tg_git_in symbolic-ref -q --short HEAD 2>/dev/null) || b=""
  [ -n "$b" ] && r=$(_tg_git_in config --get "branch.$b.pushRemote" 2>/dev/null)
  [ -n "$r" ] || r=$(_tg_git_in config --get remote.pushDefault 2>/dev/null)
  [ -n "$b" ] && [ -z "$r" ] && r=$(_tg_git_in config --get "branch.$b.remote" 2>/dev/null)
  printf '%s' "${r:-origin}"
}

# Does a remote's configuration push tags? Prints mirror when
# remote.<name>.mirror is true, and otherwise its remote.<name>.push
# refspecs, one per line. An empty name (the remote is a variable) stands for
# every remote: mirror when any of them mirrors, and every configured push
# refspec.
_tg_remote_config() {   # $1 = remote name, or empty for any
  local line
  if [ -n "$1" ]; then
    [ "$(_tg_git_in config --type=bool --get "remote.$1.mirror" 2>/dev/null)" = true ] && { printf 'mirror\n'; return 0; }
    _tg_git_in config --get-all "remote.$1.push" 2>/dev/null
    return 0
  fi
  while IFS= read -r line; do
    case "$line" in
      *.mirror\ *) [ "$(_tg_git_in config --type=bool --get "${line%% *}" 2>/dev/null)" = true ] && { printf 'mirror\n'; return 0; } ;;
    esac
  done <<TG_RC_EOF
$(_tg_git_in config --get-regexp '^remote\..*\.mirror$' 2>/dev/null)
TG_RC_EOF
  _tg_git_in config --get-regexp '^remote\..*\.push$' 2>/dev/null | sed 's/^[^ ]* //'
  return 0
}

# git push's long options, read the way git reads them: any unambiguous
# prefix counts (`--tag`, `--mirr`, `--follow-tag`, `--del`). Prints the
# option's full name, or nothing for one this hook does not need.
_tg_push_long() {   # $1 = the word, without any =value
  local o
  for o in --tags:--ta --mirror:--m --follow-tags:--fol --delete:--de \
           --repo:--rep --receive-pack:--rece --exec:--e --push-option:--pu \
           --recurse-submodules:--recu; do
    if _bd_is_opt "$1" "${o%%:*}" "${o#*:}"; then printf '%s' "${o%%:*}"; return 0; fi
  done
  case "$1" in
    --no-?*) _bd_is_opt "--${1#--no-}" --follow-tags --fol && printf '%s' --no-follow-tags ;;
  esac
  return 0
}

# git push: a tag push is the release tier, a branch push the push tier.
# A tag is pushed by --tags, --follow-tags, --mirror, push.followTags,
# `tag <name>`, a refspec naming refs/tags/ on either side, a source or a
# destination that is the name of a tag in the repository (a branch named
# v1-fix is not a tag), or a `tags/<name>` source. A tag is deleted by
# `:<tag>` or --delete/-d <tag>; a name deleted that is neither a tag nor a
# known branch may be a tag on the remote. Any other source that is not a
# local branch (a name that does not exist yet, a commit, a glob such as
# refs/*:refs/*, a remote-tracking branch) may be a tag, and a refspec this
# hook cannot read may be one: both ask.
#
# The remote's configuration counts too: remote.<name>.mirror makes every
# push to it a tag push, and its remote.<name>.push refspecs are read as if
# written when the command names none. -c settings of those keys ask ($4).
_tg_git_push() {   # $1 = index of git, $2 = first word after push, $3 = followTags (1, 0, unknown), $4 = 1 when -c sets a remote's mirror or push
  local j k t o c rest tag=0 unread=0 del=0 nofollow=0 words=() specs=() r src dst w name kind remote line
  for ((k = $2; k < n; k++)); do
    t="${TOK[k]}"
    case "$t" in
      --) for ((j = k + 1; j < n; j++)); do words+=("${TOK[j]}"); done; k=$n ;;
      --*)
        o=$(_tg_push_long "${t%%=*}")
        case "$o" in
          --tags|--follow-tags|--mirror) tag=1 ;;
          --no-follow-tags) nofollow=1 ;;
          --delete) del=1 ;;
          --repo|--receive-pack|--exec|--push-option|--recurse-submodules)
            case "$t" in *=*) ;; *) k=$((k + 1)) ;; esac ;;
        esac ;;
      -?*)
        # A bundle of short options (`-qd`, `-fdu`): d is --delete; o takes
        # the rest of the word as its value, or the next word.
        rest="${t#-}"
        while [ -n "$rest" ]; do
          c="${rest:0:1}"; rest="${rest:1}"
          case "$c" in
            d) del=1 ;;
            o) [ -z "$rest" ] && k=$((k + 1)); break ;;
          esac
        done ;;
      -) ;;
      *) words+=("$t") ;;
    esac
  done
  if [ "$nofollow" = 0 ]; then
    case "$3" in 1) tag=1 ;; unknown) unread=1 ;; esac
  fi
  [ "${4:-0}" = 1 ] && unread=1
  # words[0] is the remote; the rest are refspecs.
  for ((w = 1; w < ${#words[@]}; w++)); do specs+=("${words[w]}"); done
  if [ "${TG_UNRES:-0}" = 1 ]; then
    # The repository is unknown, so its remotes' configuration is too.
    unread=1
  else
    remote="${words[0]:-}"
    [ -z "$remote" ] && remote=$(_tg_push_remote)
    # A remote given as a variable may be any of them: a mirror among them,
    # or a push refspec that is not plainly a branch's, may push a tag.
    _tg_unreadable "$remote" && remote=""
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      if [ -z "$remote" ]; then
        case "$line" in
          mirror) unread=1 ;;
          *) [ "${#words[@]}" -le 1 ] && case "${line#+}" in *refs/tags/*) unread=1 ;; *:refs/heads/*|refs/heads/*) ;; *) unread=1 ;; esac ;;
        esac
      elif [ "$line" = mirror ]; then tag=1
      elif [ "${#words[@]}" -le 1 ]; then specs+=("$line")
      fi
    done <<TG_PUSH_EOF
$(_tg_remote_config "$remote")
TG_PUSH_EOF
  fi
  for ((w = 0; w < ${#specs[@]}; w++)); do
    r="${specs[w]}"
    if [ "$r" = tag ] && [ $((w + 1)) -lt ${#specs[@]} ]; then tag=1; w=$((w + 1)); continue; fi
    if _tg_unreadable "$r"; then unread=1; continue; fi
    r="${r#+}"
    src="${r%%:*}"
    case "$r" in *:*) dst="${r#*:}" ;; *) dst="" ;; esac
    case "$src $dst" in *refs/tags/*) tag=1; continue ;; esac
    case "$dst" in refs/heads/*) continue ;; esac
    if [ "$del" = 1 ] || [ -z "$src" ]; then
      # A deletion names the remote ref: a tag, a branch, or unknown.
      name="${dst:-$src}"
      case "$name" in refs/heads/*) continue ;; esac
      kind=$(_tg_ref_kind "$name" "${words[0]}")
      case "$kind" in tag) tag=1 ;; unknown) unread=1 ;; esac
      continue
    fi
    # A destination that is a tag here is that tag on the remote.
    case "$dst" in
      ''|refs/*) ;;
      *) [ "$(_tg_ref_kind "$dst" "")" = tag ] && { tag=1; continue; } ;;
    esac
    case "$src" in tags/?*) tag=1; continue ;; refs/heads/*) continue ;; esac
    if [ "$(_tg_ref_kind "$src" "")" = tag ]; then tag=1
    elif ! _tg_is_local_branch "$src"; then unread=1
    fi
  done
  if [ "$tag" = 1 ]; then _tg_emit release "$1"
  elif [ "$unread" = 1 ]; then _tg_emit tagUnread "$1"
  else _tg_emit push "$1"
  fi
}

# The text of a GraphQL query given as a field value or a file: prints it, or
# returns 1 when it cannot be read (a variable, a substitution, stdin, a file
# that is not there). A `$` inside the query is a GraphQL variable, so only a
# value that is wholly a variable counts as unreadable.
_tg_query_text() {   # $1 = the value after query=, or @file
  local v="$1" f
  case "$v" in
    '$'*|__BD_SUBST__*|'`'*) return 1 ;;
    @*)
      f="${v#@}"
      case "$f" in ''|-|*'$'*|*__BD_SUBST__*) return 1 ;; esac
      case "$f" in /*) ;; *) f="$CWD/$f" ;; esac
      [ -f "$f" ] && [ -r "$f" ] || return 1
      head -c 200000 "$f" 2>/dev/null || return 1 ;;
    *) printf '%s' "$v" ;;
  esac
}

# gh api: the effective method, the endpoint and the fields.
_tg_api() {   # $1 = index of gh, $2 = index of the word api
  local k=$(($2 + 1)) t method="" ep="" after=0 input="" fv
  local -a fields=()
  while [ "$k" -lt "$n" ]; do
    t="${TOK[k]}"
    if [ "$after" = 1 ]; then [ -z "$ep" ] && ep="$t"; k=$((k + 1)); continue; fi
    case "$t" in
      --) after=1 ;;
      -X|--method) method="${TOK[k+1]:-}"; k=$((k + 2)); continue ;;
      --method=*) method="${t#--method=}" ;;
      --raw-field=*) fields+=("${t#--raw-field=}") ;;
      --field=*) fields+=("${t#--field=}") ;;
      --input=*) input="${t#--input=}" ;;
      --input) input="${TOK[k+1]:--}"; k=$((k + 2)); continue ;;
      -f|--raw-field|-F|--field) fields+=("${TOK[k+1]:-}"); k=$((k + 2)); continue ;;
      -H|--header|-q|--jq|-t|--template|--hostname|-p|--preview|--cache) k=$((k + 2)); continue ;;
      --*) ;;
      -X?*) method="${t#-X}" ;;
      -f?*|-F?*) fields+=("${t#-?}") ;;
      -*) ;;
      *) [ -z "$ep" ] && ep="$t" ;;
    esac
    k=$((k + 1))
  done
  [ -n "$ep" ] || return 0

  # GraphQL: the mutation names decide, read from -f/-F query=..., a
  # query=@file, or the --input body.
  case "$ep" in
    graphql|/graphql|*/graphql)
      local text="" unread=0 found=0 m
      for fv in "${fields[@]+"${fields[@]}"}"; do
        case "$fv" in
          query=*) found=1
            if t=$(_tg_query_text "${fv#query=}"); then text="$text $t"; else unread=1; fi ;;
        esac
      done
      if [ -n "$input" ]; then
        found=1
        if t=$(_tg_query_text "@$input"); then text="$text $t"; else unread=1; fi
      fi
      [ "$found" = 1 ] || return 0
      for m in $(printf '%s' "$text" | grep -owE 'mergePullRequest|enablePullRequestAutoMerge|createRelease|updateRelease|createPullRequest|createIssue|addAssigneesToAssignable' | LC_ALL=C sort -u); do
        case "$m" in
          mergePullRequest|enablePullRequestAutoMerge) _tg_emit merge "$1" ;;
          createRelease|updateRelease) _tg_emit release "$1" ;;
          createPullRequest) _tg_emit prCreate "$1" ;;
          createIssue) _tg_emit issueCreate "$1" ;;
          addAssigneesToAssignable) _tg_emit issueAssign "$1" ;;
        esac
      done
      # Any other mutation field whose name holds Merge, Release or Ref, in
      # any case (mergeBranch, enqueuePullRequest, deleteRelease, createRef,
      # updateRef, deleteRef, updateRefs): a field is a name followed by its
      # arguments. Only in a document that has a mutation; a query that
      # reads refs or mergeable changes nothing.
      case "$text" in
        *mutation*)
          local fm=0 fr=0
          for m in $(printf '%s' "$text" | grep -oE '[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' | LC_ALL=C tr -d '(\t ' | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C sort -u); do
            case "$m" in
              mutation|mergepullrequest|enablepullrequestautomerge|createrelease|updaterelease) ;;
              *merge*|enqueuepullrequest) fm=1 ;;
              *release*|*ref*) fr=1 ;;
            esac
          done
          [ "$fm" = 1 ] && _tg_emit merge "$1"
          [ "$fr" = 1 ] && _tg_emit release "$1" ;;
      esac
      [ "$unread" = 1 ] && _tg_emit unknown "$1"
      return 0 ;;
  esac

  if [ -z "$method" ]; then
    if [ "${#fields[@]}" -gt 0 ] || [ -n "$input" ]; then method=POST; else method=GET; fi
  fi
  if ! _tg_unreadable "$method"; then
    method=$(printf '%s' "$method" | LC_ALL=C tr 'a-z' 'A-Z')
    case "$method" in POST|PUT|PATCH|DELETE) ;; *) return 0 ;; esac
  fi
  # A whole endpoint this hook cannot read may be a merge or a release. A
  # partly unreadable one is read by its literal parts: `/merge` would have
  # to be written.
  case "$ep" in
    */*) ;;
    *) if _tg_unreadable "$ep"; then _tg_emit unknown "$1"; return 0; fi ;;
  esac
  # Matched by the end of the path, so a leading `/`, a full URL and
  # `{owner}/{repo}` all read the same; a query string and trailing slashes
  # are not part of the path.
  ep="${ep%%\?*}"
  while :; do case "$ep" in */) ep="${ep%/}" ;; *) break ;; esac; done

  # A tag ref deleted or moved (DELETE or PATCH on .../git/refs/tags/<tag>)
  # is a tag push. A ref whose last part cannot be read may be a tag.
  if [ "$method" = DELETE ] || [ "$method" = PATCH ]; then
    case "$ep" in
      */git/refs/tags/*) _tg_emit release "$1"; return 0 ;;
      */git/refs/*)
        case "${ep##*/git/refs/}" in heads/*) ;; *) _tg_unreadable "$ep" && { _tg_emit tagUnread "$1"; return 0; } ;; esac ;;
      # Deleting a release or one of its files.
      */releases/*) [ "$method" = DELETE ] && { _tg_emit release "$1"; return 0; } ;;
    esac
    [ "$method" = DELETE ] && return 0
  fi

  # PATCH: editing or publishing a release, and changing an issue's
  # assignees. (PUT on an issue is matched the same way.)
  if [ "$method" = PATCH ] || [ "$method" = PUT ]; then
    case "$ep" in
      */releases/*/*) ;;
      */releases/*) [ "$method" = PATCH ] && { _tg_emit release "$1"; return 0; } ;;
      */issues/*/*) ;;
      */issues/*)
        for fv in "${fields[@]+"${fields[@]}"}"; do
          case "${fv%%=*}" in
            assignee|assignees|'assignees[]') _tg_emit issueAssign "$1"; return 0 ;;
          esac
        done
        # A body from a file may change the assignees; that is not a
        # confirm-floor action, so it is allowed with a note.
        [ -n "$input" ] && _tg_emit assignUnread "$1"
        return 0 ;;
    esac
    [ "$method" = PATCH ] && return 0
  fi

  case "$ep" in
    */git/refs)
      # Creating a tag ref is a tag push. A ref that cannot be read (a
      # variable, or --input) may be a tag.
      local refs="" have=0
      for fv in "${fields[@]+"${fields[@]}"}"; do
        case "$fv" in ref=*) have=1; refs="$refs ${fv#ref=}" ;; esac
      done
      case "$refs" in
        *refs/tags/*) _tg_emit release "$1" ;;
        *'$'*|*__BD_SUBST__*) _tg_emit tagUnread "$1" ;;
        *) { [ "$have" = 0 ] || [ -n "$input" ]; } && _tg_emit tagUnread "$1" ;;
      esac ;;
    */pulls/*/merge|*/merges) _tg_emit merge "$1" ;;
    */releases|*/releases/*/assets) _tg_emit release "$1" ;;
    */pulls) _tg_emit prCreate "$1" ;;
    */issues) _tg_emit issueCreate "$1" ;;
    */issues/*/assignees) _tg_emit issueAssign "$1" ;;
  esac
  return 0
}

# gh release create: with --verify-tag and a literal tag, emit
# releaseVerified:<tag>:<repo> so the caller can ask the remote whether the
# tag is already there; otherwise release. A tag name cannot hold a `:`.
_tg_release() {   # $1 = index of gh, $2 = index of the word create
  local k t tag="" verify=0 repo=""
  for ((k = $2 + 1; k < n; k++)); do
    t="${TOK[k]}"
    case "$t" in
      --verify-tag) verify=1 ;;
      -R|--repo) repo="${TOK[k+1]:-}"; k=$((k + 1)) ;;
      --repo=*) repo="${t#--repo=}" ;;
      -t|--title|-n|--notes|-F|--notes-file|--target|--discussion-category|--notes-start-tag|-A|--assets) k=$((k + 1)) ;;
      -*) ;;
      *) [ -z "$tag" ] && tag="$t" ;;
    esac
  done
  # -R before `release` belongs to gh too.
  for ((k = $1 + 1; k < $2; k++)); do
    case "${TOK[k]}" in -R|--repo) repo="${TOK[k+1]:-}" ;; --repo=*) repo="${TOK[k]#--repo=}" ;; esac
  done
  # A repository given as a variable is not looked up: the URL would name
  # nothing. A tag given as one is looked up as written, and is not found.
  if [ "$verify" = 1 ] && [ -n "$tag" ] && ! _tg_unreadable "$repo"; then
    case "$tag$repo" in *:*|*[[:space:]]*) _tg_emit release "$1"; return 0 ;; esac
    _tg_emit "releaseVerified:$tag:$repo" "$1"
  else
    _tg_emit release "$1"
  fi
}

# gh: the two subcommand words past options.
_tg_gh() {   # $1 = index of gh
  local j=$(($1 + 1)) w1="" w2="" i2=-1 t k
  while [ "$j" -lt "$n" ]; do
    t="${TOK[j]}"
    case "$t" in
      -R|--repo|--hostname) j=$((j + 2)); continue ;;
      -*) j=$((j + 1)); continue ;;
    esac
    if [ -z "$w1" ]; then
      w1="$t"
      [ "$w1" = api ] && { _tg_api "$1" "$j"; return 0; }
    else
      w2="$t"; i2=$j; break
    fi
    j=$((j + 1))
  done
  case "$w1 $w2" in
    "pr create"|"pr new") _tg_emit prCreate "$1" ;;
    "pr merge") _tg_emit merge "$1" ;;
    "issue create"|"issue new") _tg_emit issueCreate "$1" ;;
    "release create"|"release new") _tg_release "$1" "$i2" ;;
    # edit publishes a draft (--draft=false) or moves its tag; delete removes
    # a release (and its tag, with --cleanup-tag); upload and delete-asset
    # change the files people download from it.
    "release edit"|"release delete"|"release upload"|"release delete-asset") _tg_emit release "$1" ;;
    "issue edit")
      for ((k = i2 + 1; k < n; k++)); do
        case "${TOK[k]}" in
          --add-assignee|--add-assignee=*) _tg_emit issueAssign "$1"; break ;;
        esac
      done ;;
  esac
  return 0
}

# A program this hook does not know may run the rest of its line as a
# command: caffeinate, stdbuf, setsid, watch, `find -exec`, parallel,
# `script -q /dev/null`, and any other. So the words after it are read for gh
# or git, and what each would do is kept when it is a Tier 3 action (a merge,
# a release, a tag push or a possible one, a gh api call that cannot be read)
# and dropped otherwise: `npm run git push` names no action, and a Tier 2
# action there would cost a prompt for every script that merely mentions
# git. A command word that is a variable or a substitution (`$GH pr merge 7`)
# may be gh or git itself. The --verify-tag exemption does not apply here.
_tg_scan() {   # $1 = index of the command word
  local k t out line start=$(($1 + 1))
  _tg_unreadable "${TOK[$1]}" && start=$1
  for ((k = start; k < n; k++)); do
    t="${TOK[k]}"
    [ "${#t}" -le 4096 ] || continue
    case "${t##*/}" in
      [Gg][Hh]) out=$(_tg_gh "$k") ;;
      [Gg][Ii][Tt]) out=$(_tg_git "$k") ;;
      *)
        [ "$k" = "$1" ] || continue
        out=$(_tg_gh "$k"; _tg_git "$k") ;;
    esac
    while IFS= read -r line; do
      case "${line%%$'\t'*}" in
        merge|release|tagUnread|unknown) printf '%s\n' "$line" ;;
        releaseVerified:*) printf 'release\t%s\n' "${line#*$'\t'}" ;;
      esac
    done <<TG_SCAN_EOF
$out
TG_SCAN_EOF
  done
  return 0
}

# Every action the command names, one `key<TAB>summary` line each. Runs in a
# subshell: the parser exits 2 when awk fails, and that must reach the caller
# as "cannot decide", not end this hook with a refusal.
_tg_actions() {
  _bd_strip_noncode "$COMMAND"
  _bd_expand_interpreter_args
  local segs seg
  segs=$(_bd_segments "$BD_CODE")
  case "$segs" in *__BD_SEG_FAIL__*) exit 3 ;; esac
  while IFS= read -r seg; do
    [ -z "$seg" ] && continue
    case "$seg" in __BD_UNBALANCED__) continue ;; esac
    TOK=()
    _rm_tokenise "$seg"
    # Every comparison below is on the words as bash passes them, with
    # backslash escapes removed.
    _bd_unescape_tok
    n=${#TOK[@]}
    [ "$n" -gt 0 ] || continue
    _tg_command_word
    [ "$TG_I" -lt "$n" ] || continue
    case "$(_tg_prog "${TOK[TG_I]}")" in
      git) _tg_git "$TG_I" ;;
      gh) _tg_gh "$TG_I" ;;
      # They print their arguments: `echo gh pr merge 1` runs nothing.
      echo|printf) ;;
      *) _tg_scan "$TG_I" ;;
    esac
  done <<< "$segs"
}

# --- the settings, the branch and the journal live where the command runs ---
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || CWD=""
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"

# The parser's own refusal text ("BLOCKED: ...") is not this hook's answer,
# so its stderr is dropped; the line below says what happened.
if ! ACTIONS=$(_tg_actions 2>/dev/null); then
  _tg_undecidable "$COMMAND" "the command parser failed"
fi
[ -n "$ACTIONS" ] || exit 0

REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT=""
RUN_DIR="${REPO_ROOT:-$CWD}"

_tg_phrase() {
  case "$1" in
    push) printf 'Pushing to a remote' ;;
    prCreate) printf 'Creating a pull request' ;;
    issueAssign) printf 'Assigning an issue' ;;
    issueCreate) printf 'Creating an issue' ;;
    merge) printf 'Merging a pull request' ;;
    release) printf 'Creating a release or pushing a tag' ;;
  esac
}

# Is this tag already on the remote? `git ls-remote --tags`, against origin,
# or against the GitHub repository a -R/--repo names, stopped after
# TG_REMOTE_TIMEOUT seconds (default 5). Any failure to check is "no". Sets
# TG_REMOTE to what was asked.
_tg_tag_on_remote() {   # $1 = tag, $2 = owner/name, host/owner/name, or empty
  local tmp pid w rc=1
  case "$2" in
    '') TG_REMOTE=origin ;;
    */*/*) TG_REMOTE="https://$2.git" ;;
    */*) TG_REMOTE="https://github.com/$2.git" ;;
    *) TG_REMOTE="$2"; return 1 ;;
  esac
  tmp=$(mktemp -t flow-tier-gate.XXXXXX 2>/dev/null) || return 1
  # Output goes to a file, not a pipe: a killed git can leave a helper (ssh,
  # a credential helper) holding a pipe open, and the read would then wait
  # for it.
  GIT_TERMINAL_PROMPT=0 git -C "$RUN_DIR" ls-remote --tags "$TG_REMOTE" "refs/tags/$1" >"$tmp" 2>/dev/null &
  pid=$!
  ( sleep "${TG_REMOTE_TIMEOUT:-5}"; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  w=$!
  # The shell reports a killed job on stderr when it reaps it; that report
  # is not this hook's to print.
  { wait "$pid"; } 2>/dev/null; rc=$?
  { kill "$w"; wait "$w"; } 2>/dev/null
  if [ "$rc" -eq 0 ] && awk -v r="refs/tags/$1" '$2 == r { f = 1 } END { exit !f }' "$tmp" 2>/dev/null; then
    rm -f "$tmp"; return 0
  fi
  rm -f "$tmp"
  return 1
}

REASONS=()
# Each entry: the setting's label, a tab, the command summary.
JOURNAL_LINES=()
while IFS=$'\t' read -r KEY SUMMARY ADIR; do
  case "$KEY" in
    tagUnread)
      REASONS+=("A push whose refs or repository cannot be read or resolved from the command may push or delete a tag, which is a Tier 3 action (tiers.release): flow asks before every one. Command: $SUMMARY")
      continue ;;
    unknown)
      REASONS+=("A gh api call whose endpoint or GraphQL query cannot be read from the command (a variable, a substitution, stdin or a missing file) may merge a pull request or create a release, which flow always asks about (tiers.merge, tiers.release; Tier 3). Command: $SUMMARY")
      continue ;;
    assignUnread)
      _tg_note "could not read whether $SUMMARY changes an issue's assignees (its body is a file); allowing it without a tier check"
      continue ;;
    releaseVerified:*)
      # gh release create --verify-tag on a tag already on the remote creates
      # a release for a tag whose push was already confirmed: journaled. A tag
      # that is not there, or a check that fails, asks as any release does.
      VREST="${KEY#releaseVerified:}"
      VTAG="${VREST%%:*}"
      if _tg_tag_on_remote "$VTAG" "${VREST#*:}"; then
        JOURNAL_LINES+=("tiers.release (--verify-tag, $VTAG already on the remote)"$'\t'"$SUMMARY"$'\t'"$ADIR")
      else
        REASONS+=("Creating a release is a Tier 3 action (tiers.release). flow asks unless --verify-tag names a tag that is already on the remote, and $VTAG could not be found on $TG_REMOTE. Command: $SUMMARY")
      fi
      continue ;;
  esac
  case "$KEY" in merge|release) DEFAULT=confirm ;; *) DEFAULT=journal ;; esac
  VALUE=$(cd "$RUN_DIR" 2>/dev/null && "$PLUGIN_ROOT/bin/cascade-resolve.sh" --default "$DEFAULT" ".tiers.$KEY" 2>/dev/null)
  RC=$?
  VALUE=$(printf '%s' "$VALUE" | LC_ALL=C tr -d '\r\n')
  case "$KEY" in
    merge|release)
      # The floor: whatever the setting says, ask. A lower value is named so
      # the person can see their setting is not what decides.
      if [ "$RC" -eq 0 ] && [ "$VALUE" != confirm ]; then
        _tg_note "tiers.$KEY is \"$(printf '%s' "$VALUE" | LC_ALL=C tr '\000-\037\177' ' ' | cut -c1-40)\", below the confirm floor for $KEY; ignoring it and asking"
      fi
      REASONS+=("$(_tg_phrase "$KEY") is a Tier 3 action (tiers.$KEY): flow asks before every one. Command: $SUMMARY")
      ;;
    *)
      if [ "$RC" -ne 0 ]; then
        _tg_note "could not read tiers.$KEY (cascade-resolve.sh exit $RC); allowing $SUMMARY without a tier check"
        continue
      fi
      case "$VALUE" in
        confirm) REASONS+=("$(_tg_phrase "$KEY") is a Tier 2 action set to confirm (tiers.$KEY), so it needs your approval. Command: $SUMMARY") ;;
        journal) JOURNAL_LINES+=("tiers.$KEY (journal)"$'\t'"$SUMMARY"$'\t'"$ADIR") ;;
        autonomous) ;;
        *) _tg_note "tiers.$KEY is \"$(printf '%s' "$VALUE" | LC_ALL=C tr '\000-\037\177' ' ' | cut -c1-40)\", not autonomous, journal or confirm; allowing $SUMMARY without a tier check" ;;
      esac
      ;;
  esac
done <<< "$ACTIONS"

if [ "${#REASONS[@]}" -gt 0 ]; then
  REASON="Flow tier gate. ${REASONS[0]}"
  for ((r = 1; r < ${#REASONS[@]}; r++)); do REASON="$REASON Also: ${REASONS[r]}"; done
  jq -nc --arg r "$REASON" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
fi

[ "${#JOURNAL_LINES[@]}" -gt 0 ] || exit 0

# --- the journal line goes to the auto-log trail ------------------------------
# Not the tracked journal: `<journal dir>/auto-log/`, the git-ignored trail
# log-commits.sh and log-file-changes.sh write, named the same way:
# issue-{N}.{YYYY-MM}.md on a branch naming issue N (rotated monthly),
# otherwise session-{YYYY-MM-DD}.md. The path checks below are theirs (see
# log-file-changes.sh, _flow_autolog). Written only where the repository keeps
# a flow journal directory: a push in a repository that never ran /flow:setup
# must not create .decisions/ in it. A `git -C <dir> push` is recorded in
# <dir>'s repository, on <dir>'s branch.

# One HTML-comment breadcrumb per action, as the other trail entries are,
# with the comment terminators and control characters neutralized: the trail
# is fed back to Claude by /flow:explain.
_tg_crumb_safe() {
  local v="${1//-->/-- >}"
  v="${v//<!--/< !--}"
  printf '%s' "$v" | LC_ALL=C tr '\000-\037\177' ' '
}

_tg_trail_refused() { _tg_note "could not write to the auto-log trail ($1); allowing"; }

_tg_write_trail() {   # $1 = repository top, $2 = breadcrumbs
  local top="$1" jdir base branch issue autolog adir user err rc
  [ -n "$top" ] || return 0
  jdir=$(cd "$top" && "$PLUGIN_ROOT/bin/journal-dir.sh" 2>/dev/null) || jdir=""
  [ -n "$jdir" ] || jdir=".decisions"
  case "$jdir" in /*) base="$jdir" ;; *) base="$top/$jdir" ;; esac
  [ -d "$base" ] || return 0
  branch=$(git -C "$top" branch --show-current 2>/dev/null) || branch=""
  issue=$(printf '%s' "$branch" | grep -oE 'issue-[0-9]+' | head -n 1 | grep -oE '[0-9]+') || issue=""
  if [ -n "$issue" ]; then
    autolog="$base/auto-log/issue-$issue.$(date +%Y-%m).md"
  else
    autolog="$base/auto-log/session-$(date +%Y-%m-%d).md"
  fi
  adir=$(dirname "$autolog")
  # A symlinked trail file or directory is refused: after `gh pr checkout` of
  # a hostile fork it could point anywhere. The directory is created by
  # bin/flow-mkdir.sh --contained at the repository top (nothing below the
  # top through a symlink); an absolute journal.dir from the user's own
  # settings is created as configured.
  [ -L "$autolog" ] && { _tg_trail_refused "the trail file is a symlink"; return 0; }
  [ -L "$adir" ] && { _tg_trail_refused "the trail directory is a symlink"; return 0; }
  if ! (cd "$top" && "$PLUGIN_ROOT/bin/flow-mkdir.sh" --contained -- "$adir") >/dev/null 2>&1; then
    user=$(cd "$top" && "$PLUGIN_ROOT/bin/journal-dir.sh" --user-owned 2>/dev/null) || user=""
    [ -n "$user" ] || { _tg_trail_refused "its directory could not be created inside the repository"; return 0; }
    mkdir -p "$adir" 2>/dev/null || { _tg_trail_refused "its directory could not be created"; return 0; }
  fi
  # The trail directory ignores itself, so it never dirties the tree.
  [ -L "$adir/.gitignore" ] && { _tg_trail_refused "its .gitignore is a symlink"; return 0; }
  { [ -f "$adir/.gitignore" ] || printf '*\n' > "$adir/.gitignore" 2>/dev/null; } || true
  err=$(printf '%s' "$2" | (cd "$top" && "$PLUGIN_ROOT/bin/journal-append.sh" --file "$autolog" -) 2>&1 >/dev/null)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    err=$(printf '%s' "$err" | head -n 1 | LC_ALL=C tr '\000-\037\177' ' ' | cut -c1-200)
    _tg_trail_refused "journal-append.sh exit $rc${err:+: $err}"
  fi
  return 0
}

AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null) || AGENT_TYPE=""
AGENT_SAFE=""
[ -n "$AGENT_TYPE" ] && AGENT_SAFE=" agent=$(_tg_crumb_safe "$AGENT_TYPE")"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# Group the breadcrumbs by repository, in the order the actions came.
TOPS=()
for J in "${JOURNAL_LINES[@]}"; do
  T="${J##*$'\t'}"; [ -n "$T" ] || T="$REPO_ROOT"
  SEEN=0
  for U in ${TOPS[@]+"${TOPS[@]}"}; do [ "$U" = "$T" ] && SEEN=1; done
  [ "$SEEN" = 1 ] || TOPS+=("$T")
done
for T in ${TOPS[@]+"${TOPS[@]}"}; do
  TEXT=""
  for J in "${JOURNAL_LINES[@]}"; do
    JT="${J##*$'\t'}"; [ -n "$JT" ] || JT="$REPO_ROOT"
    [ "$JT" = "$T" ] || continue
    J="${J%$'\t'*}"
    TEXT="$TEXT<!-- auto-log: $NOW $(_tg_crumb_safe "${J%%$'\t'*}") \"$(_tg_crumb_safe "${J#*$'\t'}")\"$AGENT_SAFE -->"$'\n'
  done
  _tg_write_trail "$T" "$TEXT"
done
exit 0
