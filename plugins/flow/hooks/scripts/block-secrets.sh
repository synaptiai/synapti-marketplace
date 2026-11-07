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
#     whatever the command but a text command (below), since an option is
#     read by the program as a value; a text command's options carry text
#     (`git commit --message=...`, `-m"..."`, `gh issue create --body=...`,
#     `git log -S"..."`);
#   - any secret-shaped word, or a literal auth header, given to a command
#     that sends data or sets another process's environment (curl, wget,
#     httpie, nc, ssh, mysql, psql, docker, kubectl and the others in
#     SENDERS below), or that stores or sends a credential (gh secret, gh
#     variable, vault, heroku, fly, flyctl, npm, yarn or pnpm `config set`,
#     `npm set`, and aws, gcloud and az with every subcommand but their log
#     and monitoring searches, aws logs and cloudwatch, gcloud logging and az
#     monitor, whose values are search patterns), in its arguments, in a
#     here-string (`<<<`) it reads, or in the words of the commands piped
#     into it (`echo ... | curl -d @-`). The subcommand is found past the
#     global options in front of it (`gh -R o/r secret set`, `npm --location
#     project set`, `aws --region eu-west-1 logs`);
#   - for gh api, a field (`-f`, `-F`, `--field`, `--raw-field` name=value)
#     whose name is secret-shaped or one a secrets endpoint takes
#     (encrypted_value, key_id) with a literal value of 8 or more characters,
#     or whose value is a URL the next rule refuses (`-f config[url]=URL`);
#     a field named anything else (`-f body="... token=..."`) is text;
#   - a word that is a URL (or an assignment or option holding one) with a
#     secret-shaped query parameter (`?token=abcdefghij`) or a literal
#     password in its userinfo (`https://user:abcdefghij@host`), given to
#     any command but a text command (TEXTS below: echo, printf, cat, grep,
#     sed and the like; git commit, log, show, diff, tag, notes and grep;
#     gh issue create, edit and comment, gh pr create, edit, comment and
#     review, gh release create and edit; awk or sed only when it cannot run
#     a program, below), or assigned in command position:
#     `git ls-remote URL`, `pip install --index-url URL` and `svn checkout
#     URL` are refused, `echo URL >> README.md` and `git log --grep URL`
#     are text. A heredoc body fed to cat, tee, echo, printf or gh on a
#     line with no `>` or `|` (`cat <<EOF`, `tee .env <<EOF`) is removed by
#     the parser and never judged. Any other body (`cat <<EOF > notes.md`,
#     `git commit -F - <<EOF`) is kept, and each line of it is judged as a
#     simple command. A line that nothing on its line runs (_body_line)
#     gets the URL rule only when its first word is a sender, a setter, git
#     clone, fetch, pull, push, remote add or set-url, or submodule add, or
#     a program a wrapper runs that this hook does not name; the other rules
#     above apply to it as to any command, so a secret-shaped assignment at
#     its start (`cat <<EOF > .env` with an `API_TOKEN=...` line), a
#     secret-shaped option word, or a secret-shaped word after a sender or
#     a setter is refused, and the flow rule below reads its secrets wherever
#     they stand on the line (`curl <<EOF`, `mysql <<EOF`);
#   - a script given inline to python (`-c`), perl (`-e`, `-E`, also in a
#     bundle such as `-ne` or `-pie`, and after `-i` and its attached backup
#     extension, `-pi.bak -e`, `-i.pre -pe`), ruby (`-e`) or node (`-e`, `-p`,
#     `--eval`, `--print`) whose text holds a secret-shaped assignment
#     (also with a quoted key, `os.environ['API_TOKEN']='...'`) or a literal
#     auth header: a script is not shell, so its words cannot be read as
#     arguments, and its whole text is checked, as before #241. Only the
#     interpreter's own options before the script file are read
#     (_inline_scripts): `python3 -Wignore x.py "token=..."` and
#     `python3 x.py -e prod` pass their words to the script;
#   - any secret-shaped word, literal auth header or URL with a secret given
#     to a program that runs what it is given: eval, source or a shell (`sh
#     -c "..."`); find or fd with -exec, -execdir, -ok, -okdir, -x or
#     --exec; awk whose program may run one (system(), a `|`, getline,
#     /inet, or a program file, _awk_runs); sed whose script may (its e
#     command or the e flag of s, or a script file, _sed_runs); git, with
#     any subcommand, when it is given configuration before the subcommand
#     (-c, --config-env, --exec-path=: `git -c core.pager=... status`, `git
#     -c alias.x=!... x`, `git -c core.sshCommand=... fetch`) or a word
#     there holds the secret (-C and its directory excepted); git config
#     setting any key, since git runs the value of several keys and this
#     hook cannot list them all (`git config alias.x "!curl ..."`, which
#     the next `git x` runs, `credential.helper "!echo password=..."`,
#     whose output git sends to the remote, core.pager, core.sshCommand,
#     user.name and any other key, with --local, --global, --system,
#     --file, --worktree, set, --add or --replace-all; reading it, --get,
#     -l, --list, holds no secret and passes); git grep
#     given a pager to run (-O"cmd", -nO"cmd", --open-files-in-pager=cmd,
#     _grep_pager); or a command this hook does not name, or a wrapper with
#     no program it names, whose words name a sender, a setter, a shell, an
#     interpreter or eval (`chroot / curl ...`, `watch "curl ..."`), which
#     may be the program it runs (_names_runner; a word ending in `/`, such
#     as `out/`, names a directory and no program);
#   - any secret held anywhere in the command when a simple command in it
#     has a device as a target: a redirection to a path under /dev/ but
#     /dev/null, /dev/stdout and /dev/stderr (`echo ... > /dev/tcp/host/80`,
#     `cat <<EOF > /dev/tcp/host/80`, `> /dev/fd/3`), a redirection whose
#     target holds an expansion (`> $D/tcp/host/80`), or tee given such a
#     path (DEVSINK), also the redirection of a subshell or a group (`( echo
#     ... ) > /dev/tcp/host/80`, `>>`, `1<>`). A /dev/tcp or /dev/udp path is
#     a connection, so a text command writing to one sends what it writes.
#     The whole text of such a command is read for a secret, a heredoc body
#     the parser dropped as text included;
#   - the flow rule: when the command has a pipe, a command or process
#     substitution, a kept heredoc body, a /dev/tcp or /dev/udp path, or a
#     simple command holding a secret that writes to a file (a redirection
#     but to /dev/null, /dev/stdout, /dev/stderr or a descriptor, or tee),
#     a secret held by one simple command refuses the command if any other
#     simple command in it is not a text command, a line of a heredoc body,
#     or shell syntax that runs nothing (_flow_record). Following a secret
#     through groups, subshells, loops and substitutions is where a reading
#     goes wrong, so it is not followed: `{ echo ...; } | curl`, `curl <
#     <(echo ...)`, `curl -d "$(echo ...)"`, `curl <<EOF` and `mysql <<EOF`
#     with the secret anywhere in the body, `echo ... > f; curl -d @f`, and
#     `echo ... | xargs ./send.sh` are refused; `echo ... | grep`, a loop of
#     greps piped into wc, and `git commit -m "$(printf ...)"` are text.
#     A gh or git subcommand that is not a text one counts as a command, so
#     `gh run view --log | grep "token=..."` is refused too.
# Allowed: the same text as an argument of any other command: echo, printf,
# grep, git commit -m, gh issue create --body, and so on. That is the policy
# #241 asked to settle: text that names a secret-shaped assignment is not a
# secret being passed. So echo, printf or tee writing a secret-shaped word to
# a file (`echo "API_TOKEN=..." > .env`, `printf ... >> .env`, `tee .env
# <<< "API_TOKEN=..."`, `tee .env <<EOF`) is allowed too, which the
# whole-line check refused before #241, as long as every other command on
# the line is a text command or shell syntax that runs nothing (the flow
# rule: `echo ... > notes.txt; ls` is refused, since ls is neither), and
# the file is not a device (DEVSINK). A program this hook does not
# name may still be given such a word as its argument (`python3 x.py
# "token=..."`), unless its words name a program that sends or runs. A kept
# heredoc body line that is the assignment itself (`cat <<EOF > .env`) is
# refused, as above.
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
# In an inline script a name is often a quoted key or an index, which closes
# before the `=` or `:`: os.environ['API_TOKEN']='...', {'Authorization':
# 'Bearer ...'}.
SCRIPT_RE='('"$SECRET_NAMES"')[]'\''"]*\s*=\s*['\''"]?[A-Za-z0-9+/=_-]{8,}'
SCRIPT_HEADER_RE='(Authorization|X-API-Key)['\''"]?\s*:\s*['\''"]?(Bearer\s+)?[A-Za-z0-9+/=_-]{20,}'
# The fields a secrets endpoint of the GitHub API takes (gh api -f name=value).
FIELD_RE='^[^=]*('"$SECRET_NAMES"'|encrypted_value|key_id)[^=]*=[A-Za-z0-9+/=_-]{8,}'
HEADER_RE='^\s*(Authorization|X-API-Key):\s*(Bearer\s+)?[A-Za-z0-9+/=_-]{20,}'
# A URL with a password in its userinfo, or a secret-shaped query parameter.
# A value with a `$` in it is read from the environment, as above.
USERINFO_RE='[A-Za-z][A-Za-z0-9+.-]*://[^/?#@[:space:]]*:[^/?#@$`[:space:]]{8,}@'
URL_RE='(^|=)([A-Za-z][A-Za-z0-9+.-]*://[^/?#@[:space:]]*:[^/?#@$`[:space:]]{8,}@|[A-Za-z][A-Za-z0-9+.-]*://[^?#[:space:]]*[?]([^#[:space:]]*&)?[^#&=[:space:]]*('"$SECRET_NAMES"')[^#&=[:space:]]*=[A-Za-z0-9+/=_.~%-]{8,})'
# Any of the above in a word, unanchored, for the rules that ask whether a
# command holds one at all (held in _judge).
HELD_RE="$SECRET_RE|(Authorization|X-API-Key):\s*(Bearer\s+)?[A-Za-z0-9+/=_-]{20,}|$URL_RE"
SECRET_MSG="BLOCKED: Possible secret detected in command. Use environment variables or config files instead of inline secrets."
HEADER_MSG="BLOCKED: Literal auth token detected in curl command. Use environment variables for tokens."

# Commands that send what they are given, or hand it to another process's
# environment: an argument to them leaves the machine or the shell.
SENDERS=" curl wget http https xh httpie nc ncat netcat telnet ftp sftp scp ssh rsync mysql mysqladmin mysqldump psql pg_dump pg_restore mongo mongosh redis-cli sqlcmd docker podman kubectl helm "
SETTERS=" export declare typeset local readonly env "
# Commands that store a credential or send it to a service. gh only with
# api, secret or variable, npm, yarn and pnpm only with `config set` (and
# npm's alias `npm set`), and aws, gcloud and az with every subcommand but
# their log and monitoring searches (_judge): `gh issue create --body` files
# text, `aws logs filter-log-events` searches.
CREDS=" vault heroku fly flyctl "
# Commands that print, search or file text: a URL given to them is named,
# not used (`echo URL >> README.md`). The text-carrying subcommands of git
# and gh are read in _judge. Every other command gets the URL rule.
TEXTS=" echo printf cat tee grep egrep fgrep rg ag sed awk head tail less more wc sort uniq cut tr diff jq yq "
# Interpreters whose inline script (-c, -e) is not shell.
# Interpreters given an inline script (-c, -e); python3 is spelled out of
# pieces so the PYTHONPATH scan does not take this list for a python call.
INTERPS=" python python2 python""3 node nodejs ruby perl "

# _wordlist <list>...: the words of the lists as one list with a single
# space before, between and after them. Lists joined as they are written
# (" curl ... helm "" export ...") hold two spaces where they meet, and
# `*" $b "*` with an empty b (the basename of `out/`) matches those.
_wordlist() {
  local IFS=' '
  local -a w
  read -r -a w <<< "$*"
  printf ' %s ' "${w[*]}"
}
# The programs _target names.
TARGETS=$(_wordlist "$SENDERS" "$SETTERS" "$CREDS" "$INTERPS" "$TEXTS" gh npm yarn pnpm aws gcloud az git)

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
if ! printf '%s\n' "$COMMAND" | grep -qiE "$SCRIPT_RE|(encrypted_value|key_id)[^=[:space:]]*=|(Authorization|X-API-Key)['\"]?\s*:|$USERINFO_RE"; then
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
  case "$TARGETS" in *" $b "*) r=0 ;; esac
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

# _positional <value-options>: fills POS with the words after the program
# (TOK[BD_CMDI]) that are not options, up to `--`, stepping over the word
# after each option named in <value-options> (" -R --repo "), its value. A
# global option before a subcommand (`gh -R o/r secret set`) then does not
# hide it. POSI gets the index in TOK of each. The caller declares POS, POSI
# and n.
_positional() {
  local j w
  POS=()
  POSI=()
  for ((j = BD_CMDI + 1; j < n; j++)); do
    w=${TOK[j]}
    case "$w" in
      --) break ;;
      -*) case "$1" in *" $w "*) j=$((j + 1)) ;; esac ;;
      *) POS+=("$w"); POSI+=("$j") ;;
    esac
  done
}

# Programs that run what they are given, or send it: a word naming one in the
# arguments of a command this hook does not name (`chroot / curl ...`,
# `find . -exec curl ...`, `uv run curl ...`) may be the program that command
# runs. Shells are added by _bd_is_shell.
RUNNERS=$(_wordlist "$SENDERS" "$SETTERS" "$CREDS" "$INTERPS" eval exec source gh npm npx yarn pnpm aws gcloud az)

# _names_runner: does a word of TOK after the command's first word (but the
# program itself), or a space-separated piece of one (`sh -c "curl ..."`),
# name a program in RUNNERS or a shell? Read loosely: a piece that only looks
# like one counts. A `!` ends a piece as a quote or a separator does: a git
# alias `!curl ...` runs curl. A piece ending in `/` (`out/`, `tests/`)
# names a directory, no program, and its empty basename is skipped. The
# caller declares first and n.
_names_runner() {
  local j p b nc=0 r=1
  local -a P=()
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  for ((j = first + 1; j < n && r == 1; j++)); do
    [ "$j" != "$BD_CMDI" ] || continue
    [ "${#TOK[j]}" -le 65536 ] || { r=0; break; }
    read -r -a P <<< "${TOK[j]//[\(\)\{\}\;\&\|\`\"\'\!]/ }"
    for p in "${P[@]}"; do
      b=${p##*/}
      [ -n "$b" ] || continue
      case "$RUNNERS" in *" $b "*) r=0; break ;; esac
      if _bd_is_shell "$b"; then r=0; break; fi
    done
  done
  [ "$nc" = 1 ] || shopt -u nocasematch
  return "$r"
}

# _sed_runs: may the sed command TOK[BD_CMDI] run a program? GNU sed runs one
# with its e command (`1e curl ...`) and the e flag of s (`s/x/curl .../e`),
# and a script read from a file (-f) cannot be seen. Read loosely: any `e`
# after an address, a separator or a delimiter, with nothing but other
# flags between, counts, so a script that only looks like one does too.
_sed_runs() {
  local j w
  for ((j = BD_CMDI + 1; j < n; j++)); do
    w=${TOK[j]}
    case "$w" in
      --file|--file=*|-[!-]*f*) return 0 ;;
      --expression=*) w=${w#*=} ;;
      -*) continue ;;
    esac
    printf '%s\n' "$w" | grep -qE '(^|[^A-Za-z0-9\\])[gpiImMw0-9]*e[gpiImMw0-9]*([[:space:];}]|$)' && return 0
  done
  return 1
}

# _awk_runs: may the awk command TOK[BD_CMDI] run a program? awk runs one with
# system(), a pipe to or from a command (`print | "curl ..."`, `"cmd" |
# getline`), and gawk opens a network connection through /inet; a program
# read from a file (-f) cannot be seen.
_awk_runs() {
  local j w
  for ((j = BD_CMDI + 1; j < n; j++)); do
    w=${TOK[j]}
    case "$w" in
      -f|-f?*|--file|--file=*|--exec|--exec=*|-E|--include|--include=*|-i|-l|--load|--load=*) return 0 ;;
      *system*|*'|'*|*getline*|*/inet*) return 0 ;;
    esac
  done
  return 1
}

# _grep_pager <word>: is the word an option of git grep that names the pager
# it runs: --open-files-in-pager=cmd (or a prefix of it, which git accepts),
# or -O with its value glued, alone or ending a bundle of short options
# (-O"cmd", -nO"cmd")? A bare -O or --open-files-in-pager runs the
# configured pager, and a word after -O is the pattern. In a bundle, a letter
# that takes a value (-A -B -C -e -f -m) makes the rest of the word its value.
_grep_pager() {
  local r
  case "$1" in
    --*=*)
      r=${1%%=*}
      [ "${#r}" -ge 3 ] || return 1
      case "--open-files-in-pager" in "$r"*) return 0 ;; esac
      return 1 ;;
    --*) return 1 ;;
    -?*)
      r=${1#-}
      while [ -n "$r" ]; do
        case "$r" in
          O?*) return 0 ;;
          [ABCefm]*) return 1 ;;
        esac
        r=${r:1}
      done ;;
  esac
  return 1
}

# _in_order <word>...: are these words among POS, in this order? Options
# whose values are not known (`aws --profile prod ssm put-parameter`) only
# add words between them.
_in_order() {
  local k
  for ((k = 0; k < ${#POS[@]}; k++)); do
    [ "${POS[k]}" = "$1" ] && shift
    [ "$#" -gt 0 ] || return 0
  done
  return 1
}

# _inline_scripts <python|perl|ruby|node>: fills SCRIPTS with the scripts
# the interpreter TOK[BD_CMDI] is given inline, read from its own options up
# to the script file (a word after the script file, or after `--`, is the
# script's): python -c, also ending a bundle (-Bc), which ends the options;
# perl -e and -E, also in a bundle (-ne, -le, and -pie, read as -p -i -e);
# ruby -e (-ne); node -e, -p, -pe, --eval, --print. An option that takes the
# next word as its value (python -W, -X; perl -I; ruby -I, -r; node -r,
# --require, ...) steps over it, and an attached value (-Wignore, -Mstrict)
# is not read as options. perl's and ruby's -i takes its backup extension
# attached (-i.bak, -pi.save, -i.pre): the rest of the word is the
# extension, not option letters, except a lone `e` (-pie), read as -i -e.
# The caller declares SCRIPTS and n.
_inline_scripts() {
  local kind=$1 j=$((BD_CMDI + 1)) w rest c
  SCRIPTS=()
  while [ "$j" -lt "$n" ]; do
    w=${TOK[j]}
    case "$w" in ''|-|--|[!-]*) return 0 ;; esac
    if [ "$kind" = node ]; then
      case "$w" in
        -e|-p|-pe|--eval|--print) j=$((j + 1)); SCRIPTS+=("${TOK[j]:-}") ;;
        --eval=*|--print=*) SCRIPTS+=("${w#*=}") ;;
        -r|--require|--import|--loader|--experimental-loader|-C|--conditions|--input-type|--title|--env-file|--env-file-if-exists|--inspect-port|--debug-port|--redirect-warnings|--disable-warning|--stack-trace-limit|--watch-path|--test-reporter|--test-reporter-destination|--test-name-pattern|--test-skip-pattern|--unhandled-rejections|--dns-result-order|--icu-data-dir|--openssl-config)
          j=$((j + 1)) ;;
      esac
      j=$((j + 1))
      continue
    fi
    case "$kind:$w" in
      python:--check-hash-based-pycs|ruby:--encoding|ruby:--external-encoding|ruby:--internal-encoding|ruby:--enable|ruby:--disable|ruby:--dump)
        j=$((j + 2)); continue ;;
      *:--*) j=$((j + 1)); continue ;;
    esac
    rest=${w#-}
    while [ -n "$rest" ]; do
      c=${rest:0:1}
      rest=${rest:1}
      case "$kind:$c" in
        python:c|perl:e|perl:E|ruby:e)
          if [ -n "$rest" ]; then SCRIPTS+=("$rest"); else j=$((j + 1)); SCRIPTS+=("${TOK[j]:-}"); fi
          [ "$kind" != python ] || return 0
          rest="" ;;
        python:m) return 0 ;;
        perl:i|ruby:i) case "$kind:$rest" in perl:e|perl:E|ruby:e) ;; *) rest="" ;; esac ;;
        python:[WXQ]|perl:I|ruby:[IrCE])
          [ -n "$rest" ] || j=$((j + 1))
          rest="" ;;
        perl:[0l]|ruby:0)
          case "$c:$rest" in 0:[xX]*) rest=${rest:1}; while case "$rest" in [0-9A-Fa-f]*) true ;; *) false ;; esac; do rest=${rest:1}; done ;; esac
          while case "$rest" in [0-9]*) true ;; *) false ;; esac; do rest=${rest:1}; done ;;
        perl:[MmxdDCFV]|ruby:[xFWTK]) rest="" ;;
      esac
    done
    j=$((j + 1))
  done
}

# _body_line <simple command>: is it a line of a heredoc body that no shell
# or interpreter on its line reads (`cat <<EOF > notes.md`, `git commit -F -
# <<EOF`), and not also a command outside such a body? Only when
# _bd_strip_noncode kept a body (BD_KEPT_BODY=1): the command is read again
# with those bodies left out (BD_BLANK_BODIES=1), once, as tier-gate.sh does,
# and a simple command that reading still has is a command. A reading that
# fails counts it as one.
BODYFREE=""
BODYFREE_DONE=0
_body_line() {
  local s l
  [ "${BD_KEPT_BODY:-0}" = 1 ] || return 1
  if [ "$BODYFREE_DONE" = 0 ]; then
    BODYFREE=$(BD_BLANK_BODIES=1; _bd_strip_noncode "$COMMAND" && _bd_expand_interpreter_args && _bd_segments "$BD_CODE") \
      || BODYFREE=__BD_SEG_FAIL__
    BODYFREE_DONE=1
  fi
  case "$BODYFREE" in *__BD_SEG_FAIL__*) return 1 ;; esac
  s="${1#"${1%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"
  while IFS= read -r l; do
    l="${l#__BD_ALT__}"; l="${l#__BD_PIPE__}"
    l="${l#"${l%%[![:space:]]*}"}"; l="${l%"${l##*[![:space:]]}"}"
    [ "$l" = "$s" ] && return 1
  done <<< "$BODYFREE"
  return 0
}

# The flow rule, applied after every simple command is judged. A secret that
# one simple command holds can reach another through a pipe, a command or
# process substitution, a heredoc body, a file it writes, or a /dev/tcp or
# /dev/udp connection, and following each of these through groups,
# subshells and loops is where a reading goes wrong. So when the command has
# any of them (FLOW=1), a secret held by one simple command (HELD) refuses
# the command if any other simple command (RISKY) is not a text command, a
# line of a heredoc body, or shell syntax that runs nothing (`done`, `}`,
# `cd`, `true`, `read` and the others in _flow_record). SEGNO numbers the
# simple commands.
FLOW=0
HELD=()
RISKY=()
SEGNO=0
# DEVSINK: some simple command writes to, or reads from, a device: a
# redirection to a path under /dev/ but /dev/null, /dev/stdout and
# /dev/stderr (`> /dev/tcp/host/80`, `> /dev/fd/3`), a redirection whose
# target holds an expansion (`> $D/tcp/host/80`), which may be one, or tee
# given such a path. A /dev/tcp or /dev/udp path is a connection, so a
# secret held anywhere in the command refuses it, even when every command
# in it is a text command (`echo ... > /dev/tcp/host/80`, `cat <<EOF >
# /dev/tcp/host/80`).
DEVSINK=0

# _dev_target <word>: is the word a device path that is not /dev/null,
# /dev/stdout or /dev/stderr, or a path that holds an expansion?
_dev_target() {
  case "$1" in
    /dev/null|/dev/stdout|/dev/stderr) return 1 ;;
    */dev/*|*'$'*|*'`'*) return 0 ;;
  esac
  return 1
}

# _flow_record <held> <body>: called by _judge for each simple command, with
# its cmd, text, TOK, n, BD_CMDI, BD_RDIR and BD_WRAPI. A simple command that
# holds a secret and writes to a file (any redirection but to /dev/null,
# /dev/stdout, /dev/stderr or a file descriptor), or is tee, sets FLOW. A tee
# given a device path sets DEVSINK; a device redirection has set it already,
# in _judge.
_flow_record() {
  local t k
  if [ "$cmd" = tee ]; then
    for ((k = BD_CMDI + 1; k < n; k++)); do
      if _dev_target "${TOK[k]}"; then DEVSINK=1; fi
    done
  fi
  if [ "$1" = 1 ]; then
    HELD+=("$SEGNO")
    [ "$cmd" != tee ] || FLOW=1
    for t in ${BD_RDIR[@]+"${BD_RDIR[@]}"}; do
      case "$t" in /dev/null|/dev/stdout|/dev/stderr|-|[0-9]|[0-9]-) ;; *) FLOW=1 ;; esac
    done
  fi
  if [ "$2" = 1 ] || [ "$text" = 1 ]; then return 0; fi
  case " } ) done fi esac for case select in true false : test [ [[ read cd pushd popd pwd " in
    *" $cmd "*) return 0 ;;
  esac
  if [ -z "$cmd" ] && [ "${#BD_WRAPI[@]}" = 0 ]; then return 0; fi
  RISKY+=("$SEGNO")
}

# _judge <simple command> <piped> <body>: exits 2 with the reason when it
# passes a secret. <piped> is 1 when a pipe feeds it the output of FEED,
# <body> 1 when it is a line of a heredoc body (_body_line).
_judge() {
  # shellcheck disable=SC2034
  local -a TOK=() TOKE=() TOKQ=() BD_HSTR=() BD_RDIR=() BD_WRAPI=() POS=() POSI=() SCRIPTS=()
  # shellcheck disable=SC2034
  local BD_RIN=0 BD_CMDI=0
  _bd_words "$1"
  local n=${#TOK[@]} i=0 j k w f first cmd="" sender=0 setter=0 text=0 urls=0 gitnet=0 ghapi=0 runs=0 held=0
  # A device target counts before anything else is read. The redirection
  # after a subshell's `)` (`( echo ... ) > /dev/tcp/host/80`) is a simple
  # command with no words, which returns below before _flow_record, and the
  # subshell still sends what it writes.
  for w in ${BD_RDIR[@]+"${BD_RDIR[@]}"}; do
    if _dev_target "$w"; then DEVSINK=1; fi
  done
  # Keywords and assignments in command position are set in the shell or the
  # command's environment, a URL holding a secret among them.
  while [ "$i" -lt "$n" ]; do
    w=${TOK[i]}
    case " $_BD_KEYWORDS " in *" $w "*) i=$((i + 1)); continue ;; esac
    case "$w" in
      [A-Za-z_]*=*)
        case "${w%%=*}" in *[!A-Za-z0-9_]*) break ;; esac
        if _secret_word "$w" || _url_word "$w"; then _refuse "$SECRET_MSG"; fi
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
          if _secret_word "$w" || _url_word "$w"; then _refuse "$SECRET_MSG"; fi ;;
        *) break ;;
      esac
      j=$((j + 1))
    done
    w=${TOK[BD_WRAPI[k]]}
    [ "$(printf '%s' "${w##*/}" | tr 'A-Z' 'a-z')" = env ] && setter=1
  done
  # A wrapper running a program this hook does not name (`sudo pip install`,
  # `xargs ./deploy.sh`) leaves cmd empty: not a text command.
  if [ "$BD_CMDI" -lt "$n" ]; then
    cmd=$(printf '%s' "${TOK[BD_CMDI]##*/}" | tr 'A-Z' 'a-z')
  fi
  case "$SENDERS" in *" $cmd "*) sender=1 ;; esac
  case "$SETTERS" in *" $cmd "*) setter=1 ;; esac
  case "$CREDS" in *" $cmd "*) sender=1 ;; esac
  case "$TEXTS" in *" $cmd "*) text=1 ;; esac
  # After a wrapper, the program is the first word this hook names, which a
  # text command can be only when nothing but options or a duration stands
  # between the wrapper and it: in `sudo pip install --index-url URL jq`, jq
  # is the package, not the program, and the command is one this hook does
  # not name (cmd empty), which keeps the URL rule.
  if [ "$text" = 1 ] && [ "${#BD_WRAPI[@]}" -gt 0 ]; then
    for ((k = BD_WRAPI[${#BD_WRAPI[@]} - 1] + 1; k < BD_CMDI; k++)); do
      case "${TOK[k]}" in
        -*|[0-9]|[0-9]*[0-9smhd]) ;;
        *) text=0; cmd=""; break ;;
      esac
    done
  fi
  # The subcommand decides what gh, npm, yarn, pnpm, aws, gcloud, az and git
  # do, read past the global options in front of it (_positional). A global
  # option whose value is not listed leaves the value as the subcommand, so
  # aws, gcloud and az stay senders.
  case "$cmd" in
    gh)
      _positional " -R --repo "
      case "${POS[0]:-}" in
        api) sender=1; ghapi=1 ;;
        secret|variable) sender=1 ;;
        # The subcommands that file text: a title, a body, notes.
        issue) case "${POS[1]:-}" in create|edit|comment) text=1 ;; esac ;;
        pr) case "${POS[1]:-}" in create|edit|comment|review) text=1 ;; esac ;;
        release) case "${POS[1]:-}" in create|edit) text=1 ;; esac ;;
      esac ;;
    npm)
      _positional " --location --prefix --userconfig --globalconfig --registry --cache --workspace -w --loglevel "
      if _in_order config set || [ "${POS[0]:-}" = set ]; then sender=1; fi ;;
    yarn|pnpm) _positional " "; if _in_order config set; then sender=1; fi ;;
    aws)
      # A log or metric search takes a pattern as its value.
      _positional " --profile --region --output --endpoint-url --query --ca-bundle --cli-read-timeout --cli-connect-timeout --color --cli-binary-format "
      case "${POS[0]:-}" in logs|cloudwatch) ;; *) sender=1 ;; esac ;;
    gcloud)
      _positional " --project --account --configuration --format --verbosity --impersonate-service-account --billing-project --flags-file --flatten --trace-token --access-token-file "
      case "${POS[0]:-}" in alpha|beta) POS=("${POS[@]:1}") ;; esac
      case "${POS[0]:-}" in logging) ;; *) sender=1 ;; esac ;;
    az)
      _positional " --subscription --output -o --query "
      case "${POS[0]:-}" in monitor) ;; *) sender=1 ;; esac ;;
    git)
      # The subcommands that carry a message or show history are text; those
      # that take a URL to fetch from or push to, network ones.
      _positional " -C -c --git-dir --work-tree --namespace --exec-path --config-env "
      case "${POS[0]:-}" in
        commit|log|show|diff|tag|notes|grep) text=1 ;;
        clone|fetch|pull|push) gitnet=1 ;;
        remote) case "${POS[1]:-}" in add|set-url) gitnet=1 ;; esac ;;
        submodule) [ "${POS[1]:-}" != add ] || gitnet=1 ;;
      esac ;;
    python|python[0-9]*) _inline_scripts python ;;
    perl) _inline_scripts perl ;;
    ruby) _inline_scripts ruby ;;
    node|nodejs) _inline_scripts node ;;
  esac
  # Programs that run what they are given (runs=1), for the rule after the
  # word loop: eval, source and a shell run their words as a command, find
  # and fd the words after -exec (-execdir, -ok, -x and the like), and awk
  # and sed a program their script names (_awk_runs, _sed_runs), which makes
  # them no text command. git reads a value given before its subcommand
  # (`git -c core.pager=...`, `-c alias.x=!...`, `--config-env`) as
  # configuration, not text, and may run it whatever the subcommand
  # (`status` runs core.pager, `x` the alias, `fetch` core.sshCommand), so
  # any of those options, or a word before the subcommand holding a
  # secret, makes the command no text command. Only -C and its value, a
  # directory, run nothing. git grep runs the pager given to -O (glued, or
  # ending a bundle: -O"cmd", -nO"cmd") or --open-files-in-pager=cmd
  # (_grep_pager).
  case "$cmd" in
    eval|source|.) runs=1 ;;
    find|fd|fdfind)
      for ((k = BD_CMDI + 1; k < n; k++)); do
        case "${TOK[k]}" in -exec|-execdir|-ok|-okdir|-x|-X|--exec|--exec=*|--exec-batch|--exec-batch=*) runs=1 ;; esac
      done ;;
    awk|gawk|mawk|nawk) if _awk_runs; then runs=1; text=0; fi ;;
    sed|gsed) if _sed_runs; then runs=1; text=0; fi ;;
    git)
      for ((k = BD_CMDI + 1; k < ${POSI[0]:-$n}; k++)); do
        case "${TOK[k]}" in
          -C) k=$((k + 1)); continue ;;
          -c|-c?*|--config-env|--config-env=*|--exec-path=*) runs=1; text=0 ;;
        esac
        if printf '%s\n' "${TOK[k]}" | grep -qiE "$HELD_RE"; then runs=1; text=0; fi
      done
      if [ "${POS[0]:-}" = grep ]; then
        for ((k = POSI[0] + 1; k < n; k++)); do
          [ "${TOK[k]}" != -- ] || break
          if _grep_pager "${TOK[k]}"; then runs=1; text=0; fi
        done
      fi
      # git config stores a value git may run later, whatever the key: an
      # alias (`alias.x "!curl ..."`, which the next `git x` runs), a
      # credential helper (`credential.helper "!echo password=..."`, whose
      # output git sends to the remote on the next fetch or push),
      # core.pager, core.sshCommand, and others this hook cannot list. So
      # git config with a secret-shaped word anywhere in its words is
      # refused, with any scope option (--local, --global, --system,
      # --file, --worktree), the set subcommand, --add or --replace-all.
      # Reading it (`--get`, `-l`, `--list`) holds no secret and passes.
      if [ "${POS[0]:-}" = config ]; then runs=1; text=0; fi ;;
  esac
  if [ -n "$cmd" ] && _bd_is_shell "$cmd"; then runs=1; fi
  # The URL rule: every command but a text command. A line of a heredoc body
  # that nothing on its line runs (<body> 1, `cat <<EOF > notes.md`) is not
  # a command, and keeps the narrower rule it had before: a sender, a setter,
  # git's fetch and push subcommands, or a program a wrapper runs that this
  # hook does not name.
  if [ "$text" = 0 ]; then
    if [ "${3:-0}" = 0 ] || [ "$sender" = 1 ] || [ "$setter" = 1 ] || [ "$gitnet" = 1 ] || [ -z "$cmd" ]; then
      urls=1
    fi
  fi
  # An inline script is not shell: its words cannot be read as arguments, so
  # its whole text is checked.
  for ((k = 0; k < ${#SCRIPTS[@]}; k++)); do
    printf '%s\n' "${SCRIPTS[k]}" | grep -qiE "$SCRIPT_RE" && _refuse "$SECRET_MSG"
    printf '%s\n' "${SCRIPTS[k]}" | grep -qiE "$SCRIPT_HEADER_RE" && _refuse "$HEADER_MSG"
  done
  # HW: the words judged below, which the rules after the loop read again.
  local -a HW=("${TOK[first]}")
  for ((j = first + 1; j < n; j++)); do
    w=${TOK[j]}
    # gcloud --set-secrets and --update-secrets take Secret Manager references
    # (NAME=secret-name:version), not values.
    if [ "$cmd" = gcloud ]; then
      case "$w" in
        --set-secrets|--update-secrets) j=$((j + 1)); continue ;;
        --set-secrets=*|--update-secrets=*) continue ;;
      esac
    fi
    # gh api judges a field (-f/-F/--field/--raw-field name=value) by its
    # name: a secrets endpoint takes token, encrypted_value, key_id; a
    # comment body that names a token is text.
    if [ "$ghapi" = 1 ] && [ "$j" -gt "$BD_CMDI" ]; then
      f=1
      case "$w" in
        -f|-F|--field|--raw-field) j=$((j + 1)); w=${TOK[j]:-} ;;
        --field=*|--raw-field=*) w=${w#*=} ;;
        -f?*|-F?*) w=${w:2} ;;
        *) f=0 ;;
      esac
      if [ "$f" = 1 ]; then
        printf '%s\n' "$w" | grep -qiE "$FIELD_RE" && _refuse "$SECRET_MSG"
        # A field holding a URL gets the URL rule: `-f config[url]=URL`.
        _url_word "$w" && _refuse "$SECRET_MSG"
        continue
      fi
    fi
    HW+=("$w")
    if [ "$urls" = 1 ] && _url_word "$w"; then _refuse "$SECRET_MSG"; fi
    if _secret_word "$w"; then
      if [ "$sender" = 1 ] || [ "$setter" = 1 ]; then _refuse "$SECRET_MSG"; fi
      # An option is read by the program as a value, but the text options of
      # a text command (`git commit --message=...`, `git log -S...`, `gh
      # issue create --body=...`) carry text like any other word of it.
      if [ "$text" = 0 ] || [ "$j" -le "$BD_CMDI" ]; then
        case "$w" in -*) _refuse "$SECRET_MSG" ;; esac
      fi
    fi
    if [ "$sender" = 1 ]; then
      # A header given as its own word (`-H "Authorization: Bearer ..."`) or
      # glued to its option (`--header=Authorization: ...`).
      if _header_word "$w" || _header_word "${w#--header=}" || _header_word "${w#-H}"; then
        _refuse "$HEADER_MSG"
      fi
    fi
  done
  # held: the command holds a secret-shaped word, a literal auth header or a
  # URL with a secret, in its words or a here-string, that the rules above
  # let through.
  if printf '%s\n' "${HW[@]}" ${BD_HSTR[@]+"${BD_HSTR[@]}"} | grep -qiE "$HELD_RE"; then held=1; fi
  # A program that runs what it is given (runs=1), or a command this hook does
  # not name whose words name a program that sends or runs (`chroot / curl
  # ...`, `watch "curl ..."`), may hand the secret to that program. Not for a
  # line of a heredoc body nothing runs, which is text.
  if [ "$held" = 1 ] && [ "$text" = 0 ] && [ "${3:-0}" = 0 ]; then
    if [ "$runs" = 1 ] || _names_runner; then _refuse "$SECRET_MSG"; fi
  fi
  _flow_record "$held" "${3:-0}"
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
case "$BD_SEGS" in *__BD_PIPE__*|*__BD_SUBST__*) FLOW=1 ;; esac
[ "${BD_KEPT_BODY:-0}" != 1 ] || FLOW=1
case "$COMMAND" in */dev/tcp/*|*/dev/udp/*) FLOW=1 ;; esac
while IFS= read -r SEG; do
  case "$SEG" in ''|__BD_UNBALANCED__|__BD_SEG_FAIL__) continue ;; esac
  PIPED=0
  case "$SEG" in __BD_PIPE__*) SEG=${SEG:11}; PIPED=1 ;; esac
  case "$SEG" in __BD_*) continue ;; esac
  SEGNO=$((SEGNO + 1))
  BODY=0
  if _body_line "$SEG"; then BODY=1; fi
  _judge "$SEG" "$PIPED" "$BODY"
  if [ "$PIPED" = 1 ]; then FEED="$FEED
$SEG"; else FEED=$SEG; fi
done <<< "$BD_SEGS"

# With a device target the whole text of the command is read too: a heredoc
# body the parser removed as text (`(cat <<EOF` ... `EOF` then `) >
# /dev/tcp/host/80`, where the body belongs to cat and the redirection to the
# subshell) is what the connection is sent.
if [ "$DEVSINK" = 1 ]; then
  [ "${#HELD[@]}" = 0 ] || _refuse "$SECRET_MSG"
  if printf '%s\n' "$COMMAND" | grep -qiE "$HELD_RE"; then _refuse "$SECRET_MSG"; fi
fi
if [ "$FLOW" = 1 ] && [ "${#HELD[@]}" -gt 0 ] && [ "${#RISKY[@]}" -gt 0 ]; then
  for H in "${HELD[@]}"; do
    for R in "${RISKY[@]}"; do
      [ "$H" = "$R" ] || _refuse "$SECRET_MSG"
    done
  done
fi

exit 0
