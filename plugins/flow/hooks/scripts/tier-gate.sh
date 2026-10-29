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
#   tiers.release      gh release create                         always confirm
#
# `new` is gh's alias for `create` (`gh pr new`, `gh issue new`, `gh release
# new`) and counts the same. `gh api` counts when its method is POST or PUT,
# given with -X/--method or implied by a -f/-F/--field/--raw-field/--input
# parameter (gh's own rule), on these endpoints: .../pulls/{n}/merge and
# .../merges (merge), .../releases (release), .../pulls (prCreate), .../issues
# (issueCreate), .../issues/{n}/assignees (issueAssign). A leading `/`, a full
# https:// URL, a query string and `{owner}/{repo}` placeholders are allowed.
#
# Values: confirm asks (permissionDecision "ask", with a reason naming the
# action, the setting and the command); journal appends one line to the
# decision journal and allows; autonomous allows. merge and release have a
# floor of confirm: they always ask, and a lower value is ignored with one
# stderr line naming the setting. An "ask" is a prompt in an interactive
# session, bypassPermissions mode included, and a refusal in `claude -p`,
# which has no one to ask.
#
# Decision table:
#   command names no tiered action                    -> exit 0, no output
#   every action it names resolves to autonomous      -> exit 0, no output
#   any action resolves to confirm (merge and release -> exit 0, stdout JSON permissionDecision "ask"
#     always do)                                         naming each such action; no journal line is
#                                                        written, since the person may refuse
#   merge or release set below confirm                -> as above, plus one stderr line naming the setting
#   otherwise, journal-tier actions                   -> one line per action appended to the decision
#                                                        journal (issue-{N}.md on a branch naming issue
#                                                        N, otherwise session-{YYYY-MM-DD}.md), exit 0,
#                                                        no output
#     the journal directory does not exist            -> nothing written, exit 0, no output (the
#                                                        repository does not keep a flow journal)
#     the journal helper fails                        -> exit 0, one stderr line
#   push, prCreate, issueAssign or issueCreate whose  -> that action is allowed, one stderr line
#     value is not autonomous|journal|confirm, or
#     whose setting cannot be read (cascade fails)
#   a gh api write whose whole endpoint is a variable -> "ask": it may be a merge or a release
#     or a substitution
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
# and run as `$CMD`, a gh alias, a script file, a quote inside the word),
# `gh api graphql` mutations, and PATCH requests (publishing a draft release,
# setting assignees through issues/{n}). `--help` is not exempted: it costs a
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
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || COMMAND=""
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
for _tg_fn in _bd_strip_noncode _bd_segments _bd_expand_interpreter_args _rm_tokenise; do
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
  while [ "$i" -lt "$n" ] && _tg_is_assignment "${TOK[i]}"; do i=$((i + 1)); done
  while [ "$i" -lt "$n" ]; do
    [ "${#TOK[i]}" -le 4096 ] || break
    w=$(_tg_prog "${TOK[i]}")
    case "$w" in
      command|exec|env|nohup|time|nice|timeout|sudo|doas|xargs) ;;
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

# Emit one action line: key, a tab, the command summary.
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
  printf '%s\t%s\n' "$1" "$s"
}

# git: the subcommand past git's own options.
_tg_git() {   # $1 = index of git
  local j=$(($1 + 1))
  while [ "$j" -lt "$n" ]; do
    case "${TOK[j]}" in
      -C|-c|--git-dir|--work-tree|--namespace|--config-env|--super-prefix|--list-cmds) j=$((j + 2)); continue ;;
      -*) j=$((j + 1)); continue ;;
    esac
    break
  done
  [ "$j" -lt "$n" ] || return 0
  [ "${TOK[j]}" = push ] && _tg_emit push "$1"
  return 0
}

# gh api: the effective method and the endpoint.
_tg_api() {   # $1 = index of gh, $2 = index of the word api
  local k=$(($2 + 1)) t method="" fields=0 ep="" after=0
  while [ "$k" -lt "$n" ]; do
    t="${TOK[k]}"
    if [ "$after" = 1 ]; then [ -z "$ep" ] && ep="$t"; k=$((k + 1)); continue; fi
    case "$t" in
      --) after=1 ;;
      -X|--method) method="${TOK[k+1]:-}"; k=$((k + 2)); continue ;;
      --method=*) method="${t#--method=}" ;;
      --raw-field=*|--field=*|--input=*) fields=1 ;;
      -f|--raw-field|-F|--field|--input) fields=1; k=$((k + 2)); continue ;;
      -H|--header|-q|--jq|-t|--template|--hostname|-p|--preview|--cache) k=$((k + 2)); continue ;;
      --*) ;;
      -X?*) method="${t#-X}" ;;
      -f?*|-F?*) fields=1 ;;
      -*) ;;
      *) [ -z "$ep" ] && ep="$t" ;;
    esac
    k=$((k + 1))
  done
  [ -n "$ep" ] || return 0
  if [ -z "$method" ]; then
    if [ "$fields" = 1 ]; then method=POST; else method=GET; fi
  fi
  if ! _tg_unreadable "$method"; then
    method=$(printf '%s' "$method" | LC_ALL=C tr 'a-z' 'A-Z')
    case "$method" in POST|PUT) ;; *) return 0 ;; esac
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
  case "$ep" in
    */pulls/*/merge|*/merges) _tg_emit merge "$1" ;;
    */releases) _tg_emit release "$1" ;;
    */pulls) _tg_emit prCreate "$1" ;;
    */issues) _tg_emit issueCreate "$1" ;;
    */issues/*/assignees) _tg_emit issueAssign "$1" ;;
  esac
  return 0
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
    "release create"|"release new") _tg_emit release "$1" ;;
    "issue edit")
      for ((k = i2 + 1; k < n; k++)); do
        case "${TOK[k]}" in
          --add-assignee|--add-assignee=*) _tg_emit issueAssign "$1"; break ;;
        esac
      done ;;
  esac
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
    n=${#TOK[@]}
    [ "$n" -gt 0 ] || continue
    _tg_command_word
    [ "$TG_I" -lt "$n" ] || continue
    case "$(_tg_prog "${TOK[TG_I]}")" in
      git) _tg_git "$TG_I" ;;
      gh) _tg_gh "$TG_I" ;;
    esac
  done <<< "$segs"
}

# The parser's own refusal text ("BLOCKED: ...") is not this hook's answer,
# so its stderr is dropped; the line below says what happened.
if ! ACTIONS=$(_tg_actions 2>/dev/null); then
  _tg_undecidable "$COMMAND" "the command parser failed"
fi
[ -n "$ACTIONS" ] || exit 0

# --- the settings, the branch and the journal live where the command runs ---
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || CWD=""
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"
REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT=""
RUN_DIR="${REPO_ROOT:-$CWD}"

_tg_phrase() {
  case "$1" in
    push) printf 'Pushing to a remote' ;;
    prCreate) printf 'Creating a pull request' ;;
    issueAssign) printf 'Assigning an issue' ;;
    issueCreate) printf 'Creating an issue' ;;
    merge) printf 'Merging a pull request' ;;
    release) printf 'Creating a release' ;;
  esac
}

REASONS=()
JOURNAL_LINES=()
while IFS=$'\t' read -r KEY SUMMARY; do
  if [ "$KEY" = unknown ]; then
    REASONS+=("A gh api write whose endpoint cannot be read from the command may merge a pull request or create a release, which flow always asks about (tiers.merge, tiers.release; Tier 3). Command: $SUMMARY")
    continue
  fi
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
        journal) JOURNAL_LINES+=("- $(date -u +%Y-%m-%dT%H:%M:%SZ) tiers.$KEY (journal): $SUMMARY") ;;
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

# The journal: issue-{N}.md on a branch that names issue N, else the session
# journal. Written only where the repository keeps a flow journal: a push in a
# repository that never ran /flow:setup must not create .decisions/ in it.
[ -n "$REPO_ROOT" ] || exit 0
JOURNAL_DIR=$(cd "$REPO_ROOT" && "$PLUGIN_ROOT/bin/journal-dir.sh" 2>/dev/null) || JOURNAL_DIR=""
[ -n "$JOURNAL_DIR" ] || JOURNAL_DIR=".decisions"
case "$JOURNAL_DIR" in
  /*) JOURNAL_ABS="$JOURNAL_DIR" ;;
  *) JOURNAL_ABS="$REPO_ROOT/$JOURNAL_DIR" ;;
esac
[ -d "$JOURNAL_ABS" ] || exit 0

BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null) || BRANCH=""
ISSUE_NUM=$(printf '%s' "$BRANCH" | grep -oE 'issue-[0-9]+' | head -n 1 | grep -oE '[0-9]+') || ISSUE_NUM=""
if [ -n "$ISSUE_NUM" ]; then TARGET=(--issue "$ISSUE_NUM"); else TARGET=(--session); fi

TEXT=$(printf '%s\n' "${JOURNAL_LINES[@]}")
ERR=$(cd "$REPO_ROOT" && "$PLUGIN_ROOT/bin/journal-append.sh" "${TARGET[@]}" --text "$TEXT" 2>&1 >/dev/null)
RC=$?
if [ "$RC" -ne 0 ]; then
  ERR=$(printf '%s' "$ERR" | head -n 1 | LC_ALL=C tr '\000-\037\177' ' ' | cut -c1-200)
  _tg_note "could not append to the decision journal (journal-append.sh exit $RC${ERR:+: $ERR}); allowing"
fi
exit 0
