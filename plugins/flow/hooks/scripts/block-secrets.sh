#!/bin/bash
# [flow] PreToolUse hook: block a command that passes a secret inline.
#
# The guard decides on how secret-shaped text is used, not on the bare fact
# that it appears on the line (#241). Reading the whole line refused the
# commands that only name such text: filing an issue about a leaked token,
# documenting the pattern in a README, committing a message about a rotation.
#
# A word is secret-shaped when it matches the pattern this hook has always
# used: a name holding password, token, api_key, secret, private_key,
# aws_secret or credentials, then `=`, then at least 8 characters of
# [A-Za-z0-9+/=_-] (so `PASSWORD=$PW`, which reads it from the environment,
# never matches). A literal auth header is `Authorization:` or `X-API-Key:`,
# optionally `Bearer `, then at least 20 such characters.
#
# Refused, in each simple command of the command (lib/command-parse.sh reads
# it as the shell does: comments and heredoc bodies fed to text commands
# removed, quotes removed, a `bash -c "..."` script read too). The program a
# simple command runs is found as lib/command-parse.sh finds it
# (_bd_command_word): past shell keywords (`{`, `if`/`then`, `do`, `!`) and
# past programs that run the rest of their line (sudo, time, timeout N,
# nohup, exec, command, xargs and the others in _BD_WRAPPERS), whose program
# is the first word after them that names one of the commands below.
#   - a secret-shaped shell assignment in command position
#     (`PASSWORD=abcdefghij cmd`, `then DB_TOKEN=abcdefghij`), or one a
#     wrapper hands to the program it runs (`sudo DB_TOKEN=abcdefghij cmd`);
#   - any secret-shaped word given to export, declare, typeset, local,
#     readonly or env, which set it;
#   - a secret-shaped option word (`--password=abcdefghij`, `-token=...`),
#     whatever the command, since an option is read by the program as a value;
#   - any secret-shaped word, or a literal auth header, given to a command
#     that sends data or sets another process's environment (curl, wget,
#     httpie, nc, ssh, mysql, psql, docker, kubectl and the others in
#     SENDERS below), or that stores or sends a credential (gh api, gh
#     secret, gh variable, vault, heroku, fly, flyctl, aws, gcloud, az, and
#     npm, yarn or pnpm `config set`), in its arguments, in a here-string
#     (`<<<`) it reads, or in the words of the commands piped into it
#     (`echo ... | curl -d @-`);
#   - a word that is a URL (or an assignment or option holding one) with a
#     secret-shaped query parameter (`?token=abcdefghij`) or a literal
#     password in its userinfo (`https://user:abcdefghij@host`), whatever
#     the command;
#   - a script given inline to python, node, ruby or perl (`-c`, `-e`,
#     `--eval`) whose text holds a secret-shaped assignment or a literal
#     auth header: a script is not shell, so its words cannot be read as
#     arguments, and the whole simple command is checked as before #241.
# Allowed: the same text as an argument of any other command: echo, printf,
# grep, git commit -m, gh issue create --body, and so on. That is the policy
# #241 asked to settle: text that names a secret-shaped assignment is not a
# secret being passed.
#
# Not a general shell parser: a variable is not expanded, as in the
# force-push guard. When the parser cannot be loaded or cannot split the
# command, the hook falls back to the whole-line check it used before, so a
# failure refuses at least what it always refused.

set -euo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH

# Fail-safe: if jq unavailable, block rather than allow
if ! command -v jq &>/dev/null; then
  echo "BLOCKED: jq not available — cannot verify command safety. Install jq to proceed." >&2
  exit 2
fi

# printf, not echo: echo rewrites a backslash escape in the payload before jq
# sees it.
INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -n "$COMMAND" ] || exit 0

SECRET_NAMES='password|token|api_key|secret|private_key|aws_secret|credentials'
SECRET_RE='('"$SECRET_NAMES"')\s*=\s*['\''"]?[A-Za-z0-9+/=_-]{8,}'
HEADER_RE='^\s*(Authorization|X-API-Key):\s*(Bearer\s+)?[A-Za-z0-9+/=_-]{20,}'
# A URL with a password in its userinfo, or a secret-shaped query parameter.
# A value with a `$` in it is read from the environment, as above.
USERINFO_RE='[A-Za-z][A-Za-z0-9+.-]*://[^/?#@[:space:]]*:[^/?#@$`[:space:]]{8,}@'
URL_RE='(^|=)([A-Za-z][A-Za-z0-9+.-]*://[^/?#@[:space:]]*:[^/?#@$`[:space:]]{8,}@|[A-Za-z][A-Za-z0-9+.-]*://[^?#[:space:]]*[?]([^#[:space:]]*&)?[^#&=[:space:]]*('"$SECRET_NAMES"')[^#&=[:space:]]*=[A-Za-z0-9+/=_.~%-]{8,})'
SECRET_MSG="BLOCKED: Possible secret detected in command. Use environment variables or config files instead of inline secrets."
HEADER_MSG="BLOCKED: Literal auth token detected in curl command. Use environment variables for tokens."

# Commands that send what they are given, or hand it to another process's
# environment: an argument to them leaves the machine or the shell.
SENDERS=" curl wget http https xh httpie nc ncat netcat telnet ftp sftp scp ssh rsync mysql mysqladmin mysqldump psql pg_dump pg_restore mongo mongosh redis-cli sqlcmd docker podman kubectl helm "
SETTERS=" export declare typeset local readonly env "
# Commands that store a credential or send it to a service. gh only with
# api, secret or variable, and npm, yarn and pnpm only with `config set`
# (_judge): `gh issue create --body` files text.
CREDS=" vault heroku fly flyctl aws gcloud az "
# Interpreters whose inline script (-c, -e) is not shell.
INTERPS=" python python2 python3 node nodejs ruby perl "

# The check this hook made before #241, on the whole line: the fallback.
_whole_line() {
  if printf '%s\n' "$COMMAND" | grep -qiE "$SECRET_RE"; then
    echo "$SECRET_MSG" >&2
    exit 2
  fi
  if printf '%s\n' "$COMMAND" | grep -qiE 'curl.*(-H|--header)\s+['\''"]?(Authorization|X-API-Key):\s*(Bearer\s+)?[A-Za-z0-9+/=_-]{20,}'; then
    echo "$HEADER_MSG" >&2
    exit 2
  fi
  exit 0
}

# Fast path: nothing secret-shaped anywhere, nothing to judge.
if ! printf '%s\n' "$COMMAND" | grep -qiE "$SECRET_RE|(Authorization|X-API-Key):|$USERINFO_RE"; then
  exit 0
fi

_BD_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/command-parse.sh"
[ -r "$_BD_LIB" ] || _whole_line
# shellcheck source=lib/command-parse.sh
. "$_BD_LIB" || _whole_line
for _bd_fn in _bd_strip_noncode _bd_segments _bd_expand_interpreter_args _bd_words _bd_command_word; do
  type "$_bd_fn" >/dev/null 2>&1 || _whole_line
done
[ -n "${_BD_SEG_AWK:-}" ] || _whole_line

_bd_strip_noncode "$COMMAND"
_bd_expand_interpreter_args
# BD_SEG_MARK=1: a simple command a pipe feeds starts with __BD_PIPE__.
BD_SEGS=$(BD_SEG_MARK=1 _bd_segments "$BD_CODE") || _whole_line
case "$BD_SEGS" in *__BD_SEG_FAIL__*) _whole_line ;; esac

_secret_word() { printf '%s\n' "$1" | grep -qiE "$SECRET_RE"; }
_header_word() { printf '%s\n' "$1" | grep -qiE "$HEADER_RE"; }
_url_word() {
  case "$1" in *://*) ;; *) return 1 ;; esac
  printf '%s\n' "$1" | grep -qiE "$URL_RE"
}
_refuse() { echo "$1" >&2; exit 2; }

# _target <word>: does the word name a program this hook judges? The program
# after a wrapper is the first word that does (_bd_command_word).
_target() {
  local b r=1 nc=0
  [ "${#1}" -le 4096 ] || return 1
  b="${1##*/}"
  case "$b" in ''|*[[:space:]]*) return 1 ;; esac
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  case "$SENDERS$SETTERS$CREDS$INTERPS gh npm yarn pnpm " in *" $b "*) r=0 ;; esac
  case "$b" in python[0-9]*) r=0 ;; esac
  [ "$nc" = 1 ] || shopt -u nocasematch
  return "$r"
}

# _fed_secret: does a word of a simple command in FEED, the commands piped
# into the one being judged, hold a secret or a literal auth header?
_fed_secret() {
  local seg k
  local -a TOK=() TOKE=() TOKQ=() BD_HSTR=() BD_RDIR=()
  local BD_RIN=0
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    _bd_words "$seg"
    for ((k = 0; k < ${#TOK[@]}; k++)); do
      if _secret_word "${TOK[k]}" || _header_word "${TOK[k]}"; then return 0; fi
    done
    for ((k = 0; k < ${#BD_HSTR[@]}; k++)); do
      if _secret_word "${BD_HSTR[k]}" || _header_word "${BD_HSTR[k]}"; then return 0; fi
    done
  done <<< "$FEED"
  return 1
}

# _judge <simple command> <piped>: exits 2 with the reason when it passes a
# secret. <piped> is 1 when a pipe feeds it the output of FEED.
_judge() {
  # shellcheck disable=SC2034
  local -a TOK=() TOKE=() TOKQ=() BD_HSTR=() BD_RDIR=() BD_WRAPI=()
  # shellcheck disable=SC2034
  local BD_RIN=0 BD_CMDI=0
  _bd_words "$1"
  local n=${#TOK[@]} i=0 j k w first cmd="" sender=0 setter=0 interp=0 a1="" a2=""
  # A URL holding a secret, in any word.
  for ((j = 0; j < n; j++)); do
    _url_word "${TOK[j]}" && _refuse "$SECRET_MSG"
  done
  # Keywords and assignments in command position are set in the shell or the
  # command's environment.
  while [ "$i" -lt "$n" ]; do
    w=${TOK[i]}
    case " $_BD_KEYWORDS " in *" $w "*) i=$((i + 1)); continue ;; esac
    case "$w" in
      [A-Za-z_]*=*)
        case "${w%%=*}" in *[!A-Za-z0-9_]*) break ;; esac
        _secret_word "$w" && _refuse "$SECRET_MSG"
        i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] || return 0
  first=$i
  _bd_command_word _target "$i"
  # A wrapper hands the assignments after it, and its options, to the program
  # it runs (`sudo DB_TOKEN=... cmd`); env sets every word it is given.
  for ((k = 0; k < ${#BD_WRAPI[@]}; k++)); do
    j=$((BD_WRAPI[k] + 1))
    while [ "$j" -lt "$n" ]; do
      w=${TOK[j]}
      case "$w" in
        -*) ;;
        [A-Za-z_]*=*)
          case "${w%%=*}" in *[!A-Za-z0-9_]*) break ;; esac
          _secret_word "$w" && _refuse "$SECRET_MSG" ;;
        *) break ;;
      esac
      j=$((j + 1))
    done
    w=${TOK[BD_WRAPI[k]]}
    [ "$(printf '%s' "${w##*/}" | tr 'A-Z' 'a-z')" = env ] && setter=1
  done
  if [ "$BD_CMDI" -lt "$n" ]; then
    cmd=$(printf '%s' "${TOK[BD_CMDI]##*/}" | tr 'A-Z' 'a-z')
    # The first two words after the program that are not options: the
    # subcommand that decides what gh, npm, yarn and pnpm do.
    for ((j = BD_CMDI + 1; j < n; j++)); do
      case "${TOK[j]}" in -*) continue ;; esac
      if [ -z "$a1" ]; then a1=${TOK[j]}; else a2=${TOK[j]}; break; fi
    done
  fi
  case "$SENDERS" in *" $cmd "*) sender=1 ;; esac
  case "$SETTERS" in *" $cmd "*) setter=1 ;; esac
  case "$CREDS" in *" $cmd "*) sender=1 ;; esac
  case "$cmd" in
    gh) case "$a1" in api|secret|variable) sender=1 ;; esac ;;
    npm|yarn|pnpm) [ "$a1" = config ] && [ "$a2" = set ] && sender=1 ;;
    python|python[0-9]*|node|nodejs|ruby|perl)
      for ((j = BD_CMDI + 1; j < n; j++)); do
        # -c, -e, -E, or a bundle of short options ending in one (`-ne`).
        case "${TOK[j]}" in --eval|--eval=*|--print|--print=*|-[ceE]|-[A-Za-z]*[ceE]) interp=1; break ;; esac
      done ;;
  esac
  # An inline script is not shell: the whole simple command is checked.
  if [ "$interp" = 1 ]; then
    printf '%s\n' "$1" | grep -qiE "$SECRET_RE" && _refuse "$SECRET_MSG"
    printf '%s\n' "$1" | grep -qiE '(Authorization|X-API-Key):\s*(Bearer\s+)?[A-Za-z0-9+/=_-]{20,}' && _refuse "$HEADER_MSG"
  fi
  for ((j = first + 1; j < n; j++)); do
    w=${TOK[j]}
    if _secret_word "$w"; then
      if [ "$sender" = 1 ] || [ "$setter" = 1 ]; then _refuse "$SECRET_MSG"; fi
      case "$w" in -*) _refuse "$SECRET_MSG" ;; esac
    fi
    if [ "$sender" = 1 ]; then
      # A header given as its own word (`-H "Authorization: Bearer ..."`) or
      # glued to its option (`--header=Authorization: ...`).
      if _header_word "$w" || _header_word "${w#--header=}" || _header_word "${w#-H}"; then
        _refuse "$HEADER_MSG"
      fi
    fi
  done
  [ "$sender" = 1 ] || return 0
  # What the sender reads on its input: a here-string, or a pipe.
  for ((j = 0; j < ${#BD_HSTR[@]}; j++)); do
    _secret_word "${BD_HSTR[j]}" && _refuse "$SECRET_MSG"
    _header_word "${BD_HSTR[j]}" && _refuse "$HEADER_MSG"
  done
  if [ "$2" = 1 ] && _fed_secret; then _refuse "$SECRET_MSG"; fi
  return 0
}

# FEED: the simple commands of the pipeline so far, which a pipe-fed command
# reads the output of.
FEED=""
while IFS= read -r SEG; do
  case "$SEG" in ''|__BD_UNBALANCED__|__BD_SEG_FAIL__) continue ;; esac
  PIPED=0
  case "$SEG" in __BD_PIPE__*) SEG=${SEG:11}; PIPED=1 ;; esac
  case "$SEG" in __BD_*) continue ;; esac
  _judge "$SEG" "$PIPED"
  if [ "$PIPED" = 1 ]; then FEED="$FEED
$SEG"; else FEED=$SEG; fi
done <<< "$BD_SEGS"

exit 0
