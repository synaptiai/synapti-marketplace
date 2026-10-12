#!/usr/bin/env bash
# plugins/flow/hooks/scripts/lib/s1-guard.sh
#
# Shared by the System One guard hooks: s1-command-intent.sh (site
# guard.command-intent) and s1-screen-text.sh (site guard.planted-instructions),
# and by the measurement in evals/results-2026-10-12-s1-guard, so the state
# measured is the state the hooks send. Sources lib/command-parse.sh.
#
#   _g_mask <text>                 the text with the value of every NAME=value
#                                  assignment replaced by ***
#   _g_ruled_out <command>         0 when the cheap check rules the command out:
#                                  it is not sent
#   _g_gh_read <command>           0 when a simple command of it is a gh read of
#                                  issue or pull request text
#   _g_command_state <command> <cwd> <temp_dir> <repository_root>
#                                  the guard.command-intent state, one JSON line
#   _g_text_state <command>        the guard.planted-instructions state, one
#                                  JSON line, from the hook payload on stdin
#   _g_detach <file> <cmd...>      run cmd in a new session with stdin, stdout
#                                  and stderr on /dev/null, remove <file> when
#                                  it ends, and return at once
#
# The cheap check errs towards sending: a command is ruled out only when every
# simple command in it runs a program from the read-only list below and no
# redirection writes anywhere but /dev/null, /dev/stdout or /dev/stderr. A
# command the parser cannot split, a heredoc body kept as text, a wrapper
# (sudo, env, xargs, bash -c, ...) or any other program is sent.

# _g_user_wants <bin dir> <site>: 0 when the user's own settings put the site
# in shadow or on. A repository can only lower the user's mode, so when this
# fails nothing can be asked, and the hook ends before bin/flow-s1-mode.sh,
# which resolves every settings tier and costs up to 0.2 s per Bash call.
# When it succeeds, flow-s1-mode.sh still decides the mode.
_g_user_wants() {
  local us
  us=$("$1/cascade-resolve.sh" --user-settings-path 2>/dev/null) || return 1
  [ -f "$us" ] || return 1
  jq -e --arg s "$2" '(.systemOne.uses[$s] // "") as $m | ($m == "shadow" or $m == "on")' "$us" >/dev/null 2>&1
}

# shellcheck source=command-parse.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/command-parse.sh" || return 1

_g_mask() {
  jq -rn --arg t "$1" '$t | gsub("(?<pre>^|[\\s;&|(])(?<name>[A-Za-z_][A-Za-z0-9_]*)=(?<v>\"([^\"\\\\]|\\\\.)*\"|'"'"'[^'"'"']*'"'"'|[^\\s;&|)]*)"; "\(.pre)\(.name)=***")'
}

# Programs that only read, print or change the shell's own state.
_G_PLAIN=" ls cat head tail wc grep egrep fgrep rg echo printf pwd which type whoami id uname date hostname file stat du df tree basename dirname realpath readlink true false test [ diff cmp sort uniq cut tr jq column nl od shasum sha256sum md5 md5sum cd export unset sleep seq "
_G_GIT_READ=" status log diff show rev-parse ls-files ls-tree blame describe shortlog grep cat-file merge-base rev-list show-ref for-each-ref "

# _g_redir_ok <redirection token> <next token>: sets _G_SKIP=1 when the
# redirection takes the next token as its target. Returns 1 when the
# redirection writes to a file.
_g_redir_ok() {
  local t="$1" target op
  _G_SKIP=0
  case "$t" in
    '<'*) # input, a heredoc or a here-string: reads only
      case "$t" in '<'|'<<'|'<<<') _G_SKIP=1 ;; esac
      return 0 ;;
  esac
  op="${t%%[!0-9>|]*}"     # 2>, >>, >|
  target="${t#"$op"}"
  if [ -z "$target" ]; then _G_SKIP=1; target="$2"; fi
  case "$target" in
    /dev/null|/dev/stdout|/dev/stderr) return 0 ;;
  esac
  return 1
}

# _g_segment_ok <simple command>: 0 when it only reads.
_g_segment_ok() {
  local seg="$1" i n tok prog
  local -a TOK=() ARGS=()
  _rm_tokenise "$seg"
  n=${#TOK[@]}
  _G_SKIP=0
  for ((i = 0; i < n; i++)); do
    tok="${TOK[i]}"
    if [ "$_G_SKIP" = 1 ]; then _G_SKIP=0; continue; fi
    case "$tok" in
      [0-9]'>'*|[0-9][0-9]'>'*|'>'*|'<'*)
        _g_redir_ok "$tok" "${TOK[i+1]:-}" || return 1
        continue ;;
    esac
    ARGS+=("$tok")
  done
  # Leading assignments only set variables.
  while [ "${#ARGS[@]}" -gt 0 ] && [[ "${ARGS[0]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do ARGS=("${ARGS[@]:1}"); done
  [ "${#ARGS[@]}" -gt 0 ] || return 0
  prog="${ARGS[0]##*/}"
  case "$_G_PLAIN" in *" $prog "*) return 0 ;; esac
  case "$prog" in
    git) _g_git_ok "$seg" ;;
    gh) _g_gh_ok "${ARGS[@]:1}" ;;
    find)
      for tok in "${ARGS[@]:1}"; do
        case "$tok" in -delete|-exec|-execdir|-ok|-okdir|-fprint|-fprint0|-fprintf|-fls) return 1 ;; esac
      done
      return 0 ;;
    sed) _g_sed_ok "${ARGS[@]:1}" ;;
    *) return 1 ;;
  esac
}

_g_git_ok() {
  local a listing=0 pos=0
  # A configuration given on the command line can name a program git runs
  # (core.pager, an alias starting with !), so it is sent.
  local -a TOK=()
  _rm_tokenise "$1"
  for a in "${TOK[@]+"${TOK[@]}"}"; do
    case "$a" in -c|-c?*|--config-env*|--exec-path*) return 1 ;; esac
  done
  _bd_git_parse "$1" || return 1
  local -a G=()
  for a in "${GIT_ARGS[@]+"${GIT_ARGS[@]}"}"; do
    _bd_is_redirection "$a" && continue
    # Options that write a file or start a program.
    case "$a" in --output|--output=*|-O*|--open-files-in-pager*) return 1 ;; esac
    G+=("$a")
  done
  case " $_G_GIT_READ " in *" $GIT_SUB "*) return 0 ;; esac
  case "$GIT_SUB" in
    branch|tag)
      for a in "${G[@]+"${G[@]}"}"; do
        case "$a" in
          -l|--list|-a|--all|-r|--remotes|-v|-vv|--verbose|--show-current|--contains|--no-contains|--merged|--no-merged|--points-at|--sort=*|--format=*|--column|--no-column) listing=1 ;;
          -*) return 1 ;;
          *) pos=1 ;;
        esac
      done
      [ "$pos" = 0 ] || [ "$listing" = 1 ] ;;
    remote)
      for a in "${G[@]+"${G[@]}"}"; do
        case "$a" in -v|--verbose) ;; get-url) return 0 ;; *) return 1 ;; esac
      done
      return 0 ;;
    config)
      for a in "${G[@]+"${G[@]}"}"; do
        case "$a" in --unset*|--add|--replace-all|--edit|-e|--rename-section|--remove-section) return 1 ;; esac
      done
      for a in "${G[@]+"${G[@]}"}"; do
        case "$a" in --get|--get-all|--get-regexp|--list|-l) return 0 ;; esac
      done
      return 1 ;;
    stash|worktree)
      [ "${G[0]:-}" = list ] ;;
    *) return 1 ;;
  esac
}

# _g_gh_get <args after `gh api`>: 0 when the call is a GET with no fields.
_g_gh_get() {
  local a prev=""
  for a in "$@"; do
    if [ "$prev" = method ]; then
      [ "$(printf '%s' "$a" | tr '[:lower:]' '[:upper:]')" = GET ] || return 1
      prev=""; continue
    fi
    case "$a" in
      -X|--method) prev=method ;;
      -X*) [ "$(printf '%s' "${a#-X}" | tr '[:lower:]' '[:upper:]')" = GET ] || return 1 ;;
      --method=*) [ "$(printf '%s' "${a#--method=}" | tr '[:lower:]' '[:upper:]')" = GET ] || return 1 ;;
      -f|-F|--field|--raw-field|--input|-f*|-F*|--field=*|--raw-field=*|--input=*) return 1 ;;
    esac
  done
  [ "$prev" != method ]
}

_g_gh_ok() {
  case "${1:-} ${2:-}" in
    "issue view"|"issue list"|"issue status"|"pr view"|"pr list"|"pr checks"|"pr diff"|"pr status"|"repo view"|"run view"|"run list"|"release view"|"release list") return 0 ;;
  esac
  [ "${1:-}" = api ] || return 1
  shift
  _g_gh_get "$@"
}

_g_sed_ok() {
  local a n=0 expect_script=0 have_e=0
  local -a S=() P=()
  for a in "$@"; do
    if [ "$expect_script" = 1 ]; then S+=("$a"); expect_script=0; continue; fi
    case "$a" in
      -i*|--in-place*) return 1 ;;
      -n|--quiet|--silent) n=1 ;;
      -E|-r|--regexp-extended) ;;
      -e) expect_script=1; have_e=1 ;;
      -*) return 1 ;;
      *) P+=("$a") ;;
    esac
  done
  [ "$n" = 1 ] || return 1
  [ "$have_e" = 1 ] || { [ "${#P[@]}" -gt 0 ] || return 1; S+=("${P[0]}"); }
  [ "${#S[@]}" -gt 0 ] || return 1
  for a in "${S[@]}"; do
    [[ "$a" =~ ^[0-9]+(,([0-9]+|\$))?p$ ]] || return 1
  done
  return 0
}

# _g_segments <command>: the simple commands, one per line, with file-descriptor
# redirections (2>&1, >&2, <&0, >&-) removed and &> read as >, because the
# segmenter splits on & and would read `2>&1` as a second command `1`.
# Returns 1 when the command cannot be split or a heredoc body was kept.
_g_segments() {
  local code
  _bd_strip_noncode "$1"
  [ "${BD_KEPT_BODY:-0}" = 1 ] && return 1
  code=$(printf '%s' "$BD_CODE" | sed -E 's/[0-9]*[<>]&[0-9]*-?/ /g; s/&>>/ >> /g; s/&>/ > /g')
  _G_SEGS=$(_bd_segments "$code")
  case "$_G_SEGS" in *__BD_SEG_FAIL__*|*__BD_UNBALANCED__*) return 1 ;; esac
  return 0
}

_g_ruled_out() {
  local seg any=0
  [ -n "${1//[[:space:]]/}" ] || return 1
  _g_segments "$1" || return 1
  while IFS= read -r seg; do
    [ -n "${seg//[[:space:]]/}" ] || continue
    any=1
    _g_segment_ok "$seg" || return 1
  done <<<"$_G_SEGS"
  [ "$any" = 1 ]
}

_g_gh_read() {
  local seg
  local -a TOK=() ARGS=()
  _g_segments "$1" || return 1
  while IFS= read -r seg; do
    [ -n "${seg//[[:space:]]/}" ] || continue
    TOK=(); _rm_tokenise "$seg"
    ARGS=("${TOK[@]+"${TOK[@]}"}")
    while [ "${#ARGS[@]}" -gt 0 ] && [[ "${ARGS[0]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do ARGS=("${ARGS[@]:1}"); done
    [ "${#ARGS[@]}" -ge 2 ] || continue
    [ "${ARGS[0]##*/}" = gh ] || continue
    case "${ARGS[1]} ${ARGS[2]:-}" in
      "issue view"|"pr view") return 0 ;;
    esac
    [ "${ARGS[1]}" = api ] || continue
    _g_gh_get "${ARGS[@]:2}" || continue
    local a
    for a in "${ARGS[@]:2}"; do
      [[ "$a" =~ ^/?repos/[^/]+/[^/]+/(issues|pulls)(/|\?|$) ]] && return 0
    done
  done <<<"$_G_SEGS"
  return 1
}

# _g_ref_ok <ref>: the shape flow-s1.sh accepts for --ref, in the C locale so
# the ranges are ASCII only; a ref of another shape loses the record.
_g_ref_ok() {
  local LC_ALL=C
  [ "${#1}" -le 200 ] && [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._:/#@+-]*$ ]]
}

_g_command_state() {
  local masked
  masked=$(_g_mask "$1") || return 1
  jq -nc --arg c "${masked:0:8000}" --arg cwd "$2" --arg t "$3" --arg r "$4" \
    '{command: $c, cwd: $cwd, temp_dir: $t, repository_root: $r}'
}

_g_text_state() {
  local masked
  masked=$(_g_mask "$1") || return 1
  jq -c --arg cmd "${masked:0:2000}" '
    def lines: (if type == "string" then . else "" end)
      | (if endswith("\n") then .[:-1] else . end)
      | if . == "" then [] else split("\n") end;
    {command: $cmd, output: (.tool_response.stdout | lines | .[0:600] | map(.[0:1000]))}'
}

_g_detach() {
  python3 -I -c '
import os, sys
if os.fork():
    os._exit(0)
os.setsid()
if os.fork():
    os._exit(0)
fd = os.open(os.devnull, os.O_RDWR)
for i in (0, 1, 2):
    os.dup2(fd, i)
os.execvp("bash", ["bash", "-c", "f=$1; shift; \"$@\"; rm -f -- \"$f\"", "flow-s1-guard"] + sys.argv[1:])
' "$@" </dev/null >/dev/null 2>&1
}
