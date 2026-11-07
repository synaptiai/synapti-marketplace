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
# removed, quotes removed, a `bash -c "..."` script read too):
#   - a secret-shaped shell assignment in command position
#     (`PASSWORD=abcdefghij cmd`, `DB_TOKEN=abcdefghij`);
#   - any secret-shaped word given to export, declare, typeset, local,
#     readonly or env, which set it;
#   - a secret-shaped option word (`--password=abcdefghij`, `-token=...`),
#     whatever the command, since an option is read by the program as a value;
#   - any secret-shaped word, or a literal auth header, given to a command
#     that sends data or sets another process's environment (curl, wget,
#     httpie, nc, ssh, mysql, psql, docker, kubectl and the others in
#     SENDERS below).
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

SECRET_RE='(password|token|api_key|secret|private_key|aws_secret|credentials)\s*=\s*['\''"]?[A-Za-z0-9+/=_-]{8,}'
HEADER_RE='^\s*(Authorization|X-API-Key):\s*(Bearer\s+)?[A-Za-z0-9+/=_-]{20,}'
SECRET_MSG="BLOCKED: Possible secret detected in command. Use environment variables or config files instead of inline secrets."
HEADER_MSG="BLOCKED: Literal auth token detected in curl command. Use environment variables for tokens."

# Commands that send what they are given, or hand it to another process's
# environment: an argument to them leaves the machine or the shell.
SENDERS=" curl wget http https xh httpie nc ncat netcat telnet ftp sftp scp ssh rsync mysql mysqladmin mysqldump psql pg_dump pg_restore mongo mongosh redis-cli sqlcmd docker podman kubectl helm "
SETTERS=" export declare typeset local readonly env "

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
if ! printf '%s\n' "$COMMAND" | grep -qiE "$SECRET_RE|(Authorization|X-API-Key):"; then
  exit 0
fi

_BD_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/command-parse.sh"
[ -r "$_BD_LIB" ] || _whole_line
# shellcheck source=lib/command-parse.sh
. "$_BD_LIB" || _whole_line
for _bd_fn in _bd_strip_noncode _bd_segments _bd_expand_interpreter_args _bd_words; do
  type "$_bd_fn" >/dev/null 2>&1 || _whole_line
done
[ -n "${_BD_SEG_AWK:-}" ] || _whole_line

_bd_strip_noncode "$COMMAND"
_bd_expand_interpreter_args
BD_SEGS=$(_bd_segments "$BD_CODE") || _whole_line
case "$BD_SEGS" in *__BD_SEG_FAIL__*) _whole_line ;; esac

_secret_word() { printf '%s\n' "$1" | grep -qiE "$SECRET_RE"; }
_header_word() { printf '%s\n' "$1" | grep -qiE "$HEADER_RE"; }

# _judge <simple command>: exits 2 with the reason when it passes a secret.
_judge() {
  # shellcheck disable=SC2034
  local -a TOK=() TOKE=() TOKQ=() BD_HSTR=() BD_RDIR=()
  # shellcheck disable=SC2034
  local BD_RIN=0
  _bd_words "$1"
  local n=${#TOK[@]} i=0 w cmd="" sender=0 setter=0
  # Assignments in command position are set in the shell or the command's
  # environment.
  while [ "$i" -lt "$n" ]; do
    w=${TOK[i]}
    case "$w" in
      [A-Za-z_]*=*)
        case "${w%%=*}" in *[!A-Za-z0-9_]*) break ;; esac
        if _secret_word "$w"; then echo "$SECRET_MSG" >&2; exit 2; fi
        i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] || return 0
  # A command word is a program name, never a long argument (4096 is PATH_MAX).
  [ "${#TOK[i]}" -le 4096 ] && cmd=$(printf '%s' "${TOK[i]##*/}" | tr 'A-Z' 'a-z')
  case "$SENDERS" in *" $cmd "*) sender=1 ;; esac
  case "$SETTERS" in *" $cmd "*) setter=1 ;; esac
  i=$((i + 1))
  while [ "$i" -lt "$n" ]; do
    w=${TOK[i]}
    if _secret_word "$w"; then
      if [ "$sender" = 1 ] || [ "$setter" = 1 ]; then echo "$SECRET_MSG" >&2; exit 2; fi
      case "$w" in -*) echo "$SECRET_MSG" >&2; exit 2 ;; esac
    fi
    if [ "$sender" = 1 ]; then
      # A header given as its own word (`-H "Authorization: Bearer ..."`) or
      # glued to its option (`--header=Authorization: ...`).
      if _header_word "$w" || _header_word "${w#--header=}" || _header_word "${w#-H}"; then
        echo "$HEADER_MSG" >&2; exit 2
      fi
    fi
    i=$((i + 1))
  done
  return 0
}

while IFS= read -r SEG; do
  [ -z "$SEG" ] && continue
  case "$SEG" in __BD_*) continue ;; esac
  _judge "$SEG"
done <<< "$BD_SEGS"

exit 0
