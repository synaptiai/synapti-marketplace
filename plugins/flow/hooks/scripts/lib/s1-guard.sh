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
# When it succeeds, G_USER_MODE is that mode, and flow-s1-mode.sh still
# decides the mode used.
_g_user_wants() {
  local us
  G_USER_MODE=""
  us=$("$1/cascade-resolve.sh" --user-settings-path 2>/dev/null) || return 1
  [ -f "$us" ] || return 1
  G_USER_MODE=$(jq -r --arg s "$2" '(.systemOne.uses[$s] // "") | select(. == "shadow" or . == "on")' "$us" 2>/dev/null) || G_USER_MODE=""
  [ -n "$G_USER_MODE" ]
}

# shellcheck source=command-parse.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/command-parse.sh" || return 1

# _G_JQ_SHAPES: jq definitions. `shapes` replaces values shaped like a
# credential wherever they stand: tokens with a known prefix, JSON web tokens,
# any run of 20 or more letters, digits, _ + = or - that mixes upper case,
# lower case and digits, and a 40-character run of letters, digits, / and +
# that mixes them (an AWS secret key). Hex digests (no upper case), paths (split at / and
# .) and words are left alone. It is the only rule applied to the output of a
# screened gh read: rules keyed on a name ("api-key: ...") would also hide the
# text that follows the name, and with it a planted instruction.
_G_JQ_SHAPES='
def shapes:
  gsub("(?:gh[pousr]_[A-Za-z0-9]{10,}|github_pat_[A-Za-z0-9_]{10,}|sk-[A-Za-z0-9_-]{16,}|xox[abprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|dop_v1_[a-f0-9]{20,}|shpat_[a-f0-9]{20,}|glpat-[A-Za-z0-9_-]{10,}|AIza[0-9A-Za-z_-]{20,}|eyJ[A-Za-z0-9_-]{4,}\\.[A-Za-z0-9_-]{4,}\\.[A-Za-z0-9_-]{4,})"; "***")
  | gsub("(?<![A-Za-z0-9_+=-])(?=[A-Za-z0-9_+=-]*[A-Z])(?=[A-Za-z0-9_+=-]*[a-z])(?=[A-Za-z0-9_+=-]*[0-9])[A-Za-z0-9_+=-]{20,}(?![A-Za-z0-9_+=-])"; "***")
  | gsub("(?<![A-Za-z0-9/+=])(?=[A-Za-z0-9/+]{0,39}[A-Z])(?=[A-Za-z0-9/+]{0,39}[a-z])(?=[A-Za-z0-9/+]{0,39}[0-9])[A-Za-z0-9+][A-Za-z0-9/+]{39}(?![A-Za-z0-9/+=])"; "***");
'

# _G_JQ_MASK: jq definitions. `mask` is what _g_mask applies to a command.
# The rules go by kind, not by a list of names:
# - the value of every NAME=value, NAME+=value and NAME[i]=value assignment,
#   a value being a run of shell word parts ($'...', "...", '...', \x, other
#   characters) up to an unquoted space or operator;
# - user:password@ in a URL;
# - the value of an option (- or --) whose name holds token, secret, pass,
#   pwd, key, auth, credential, bearer or cookie, and of --user;
# - what follows a word holding one of those words and a colon (a header,
#   pass:VALUE), quoted or not, the value of a JSON or dict key (quoted with
#   " or ', escaped or not) whose name holds one, and the value of a
#   name=value pair inside a word (?apikey=, -d 'access_key=', api.key=);
# - -u or -U user:password, attached or not, and --proxy-user;
# - the password options of mysql, mysqldump, mysqladmin, mariadb (-pVALUE),
#   sshpass (-p), redis-cli (-a), docker login (-p), zip and unzip (-P), 7z
#   (-pVALUE), ssh-keygen (-N), sqlcmd (-P), mongosh and mongo (-p), smbclient
#   (-U user%VALUE), and the value of gh secret set (--body, -b);
# - and `shapes` above.
_G_JQ_MASK=$_G_JQ_SHAPES'
def kind: "(?i:token|secret|pass|pwd|key|auth|credential|bearer|cookie)";
def val: "(?:\\$\u0027(?:[^\u0027\\\\]|\\\\.)*\u0027|\"(?:[^\"\\\\]|\\\\.)*\"|\u0027[^\u0027]*\u0027|[^\\s;&|]+)";
def mask:
  gsub("(?<pre>^|[\\s;&|(])(?<name>[A-Za-z_][A-Za-z0-9_]*(?:\\[[^\\]\\s]*\\])?\\+?)=(?:\\$\u0027(?:[^\u0027\\\\]|\\\\.)*\u0027|\"(?:[^\"\\\\]|\\\\.)*\"|\u0027[^\u0027]*\u0027|\\\\.|[^\\s;&|()<>\"\u0027\\\\])*"; "\(.pre)\(.name)=***")
  | gsub("(?<s>(?<![A-Za-z0-9+.-])[A-Za-z][A-Za-z0-9+.-]{0,30}://)[^/\\s@\u0027\"]+@"; "\(.s)***@")
  | gsub("(?<o>(?:^|\\s)--?(?:user|proxy-user|[A-Za-z0-9-]{0,64}" + kind + "[A-Za-z0-9-]{0,64})(?:=|\\s+))" + val; "\(.o)***")
  | gsub("(?<o>(?<q>\\\\?[\"\u0027])[^\"\u0027\\s\\\\]{0,64}" + kind + "[^\"\u0027\\s\\\\]{0,64}\\\\?[\"\u0027]\\s*:\\s*)(?:\\\\?\"(?:[^\"\\\\]|\\\\[^\"])*\\\\?\"|\u0027[^\u0027]*\u0027)"; "\(.o)\(.q)***\(.q)")
  | gsub("(?<o>(?<![A-Za-z0-9-])[A-Za-z0-9-]{0,64}" + kind + "[A-Za-z0-9-]{0,64}\\s*:\\s*)(?:\u0027[^\u0027]*\u0027|\"(?:[^\"\\\\]|\\\\.)*\"|[^\u0027\"\\n]+)"; "\(.o)***")
  | gsub("(?<o>[?&\u0027\"=.\\s][A-Za-z0-9_.-]{0,64}" + kind + "[A-Za-z0-9_.-]{0,64}=)[^&\\s\u0027\";|]+"; "\(.o)***")
  | gsub("(?<o>(?:^|\\s)-[uU]\\s*)[^\\s:\u0027\"]+:[^\\s\u0027\"]+"; "\(.o)***")
  | gsub("(?<o>\\b(?:mysql|mysqldump|mysqladmin|mariadb)\\b[^;&|\\n]{0,400}?\\s-p)[^\\s;&|]+"; "\(.o)***")
  | gsub("(?<o>\\bsshpass\\s+-p\\s*)[^\\s;&|]+"; "\(.o)***")
  | gsub("(?<o>\\bredis-cli\\b[^;&|\\n]{0,400}?\\s-a\\s*)[^\\s;&|]+"; "\(.o)***")
  | gsub("(?<o>\\bdocker\\s+login\\b[^;&|\\n]{0,400}?\\s-p\\s*)[^\\s;&|]+"; "\(.o)***")
  | gsub("(?<o>\\bgh\\s+secret\\s+set\\b[^;&|\\n]{0,400}?\\s(?:--body|-b)(?:=|\\s*))" + val; "\(.o)***")
  | gsub("(?<o>\\b(?:zip|unzip)\\b[^;&|\\n]{0,400}?\\s-P\\s*)[^\\s;&|]+"; "\(.o)***")
  | gsub("(?<o>\\b7za?\\b[^;&|\\n]{0,400}?\\s-p)[^\\s;&|]+"; "\(.o)***")
  | gsub("(?<o>\\bssh-keygen\\b[^;&|\\n]{0,400}?\\s-N\\s*)" + val; "\(.o)***")
  | gsub("(?<o>\\bsqlcmd\\b[^;&|\\n]{0,400}?\\s-P\\s*)[^\\s;&|]+"; "\(.o)***")
  | gsub("(?<o>\\b(?:mongosh|mongo)\\b[^;&|\\n]{0,400}?\\s-p\\s*)[^\\s;&|]+"; "\(.o)***")
  | gsub("(?<o>\\bsmbclient\\b[^;&|\\n]{0,400}?\\s-U\\s*[^\\s%;&|]+%)[^\\s;&|]+"; "\(.o)***")
  | shapes;
'

# _G_JQ_SKIP: jq definitions. `risky` is true for a command that may hold a
# credential the masking cannot place, which is then not sent (the user's
# choice, 2026-10-13): a secret fed on stdin (--password-stdin, --with-token,
# gh secret set without --body), a positional secret of a credential program
# (vault login, aws configure set, npm config set, htpasswd, chpasswd,
# kubectl create secret, gh auth login, security add-*-password, kinit,
# docker or podman secret create, wrangler secret put, vercel env add), a
# password read from stdin, a file descriptor or a process substitution
# (sudo -S, --passphrase-fd, -passin stdin, --password-file=<(...)), and a
# long base64 run that mixes upper case, lower case and digits and holds +
# (but not c++-style ++/) or holds / between two parts of 8 or more
# characters that each hold a digit.
_G_JQ_SKIP='
def risky:
  test("--[A-Za-z-]{0,40}stdin\\b|--with-token\\b")
  or (test("\\bgh\\s+secret\\s+set\\b") and (test("\\bgh\\s+secret\\s+set\\b[^;&|\\n]{0,400}?\\s(?:--body|-b)") | not))
  or test("\\b(?:vault\\s+(?:login|write|kv)|aws\\s+configure\\s+set|npm\\s+config\\s+set|htpasswd|chpasswd|kubectl\\s+create\\s+secret|gh\\s+auth\\s+login|security\\s+add-(?:generic|internet)-password|kinit|(?:docker|podman)\\s+secret\\s+create|wrangler\\s+secret\\s+put|vercel\\s+env\\s+add)\\b")
  or test("\\bsudo\\b[^;&|\\n]{0,200}?\\s(?:-[A-Za-z]*S[A-Za-z]*|--stdin)\\b|--passphrase-fd\\b|-pass(?:in|out)?\\s+(?:stdin|fd:)|--?[A-Za-z-]{0,40}pass[A-Za-z-]{0,40}(?:=|\\s+)<\\(")
  or test("(?<![A-Za-z0-9/+=])(?=[A-Za-z0-9/+]{0,39}[A-Z])(?=[A-Za-z0-9/+]{0,39}[a-z])(?=[A-Za-z0-9/+]{0,39}[0-9])[A-Za-z0-9+][A-Za-z0-9/+]{39}(?![A-Za-z0-9/+=])")
  or test("(?<![A-Za-z0-9/+=])(?![A-Za-z0-9/+=]{0,200}(?:/\\+\\+|\\+\\+/))(?=[A-Za-z0-9/+=]{0,200}\\+)(?=[A-Za-z0-9/+=]{0,200}[A-Z])(?=[A-Za-z0-9/+=]{0,200}[a-z])(?=[A-Za-z0-9/+=]{0,200}[0-9])[A-Za-z0-9/+=]{24,}")
  or test("(?<![A-Za-z0-9/+=])(?=[A-Za-z0-9/+=]{32,})(?=[A-Za-z0-9/+=]{0,200}[A-Z])(?=[A-Za-z0-9/+=]{0,200}[a-z])[A-Za-z0-9/+=]{0,200}?(?<![A-Za-z0-9+=])(?=[A-Za-z0-9+=]{0,200}[0-9])[A-Za-z0-9+=]{8,}/[A-Za-z0-9/+=]{0,200}?(?<![A-Za-z0-9+=])(?=[A-Za-z0-9+=]{0,200}[0-9])[A-Za-z0-9+=]{8,}");
'

# _g_skip_credential <command>: 0 when the command is not sent because it may
# hold a credential the masking cannot place (_G_JQ_SKIP). A jq that fails
# answers 0: nothing is sent.
_g_skip_credential() {
  local r
  r=$(jq -rn --arg t "$1" "$_G_JQ_SKIP"'$t | risky' 2>/dev/null)
  [ "$r" != false ]
}

# _g_mask <text>: the text with every credential _G_JQ_MASK knows replaced by
# ***. record-quality-run.sh masks only the assignments in a command's leading
# prefix, because quality.tests-ran sends only that prefix and the test
# command; this site sends whole commands, so it masks more. The two are kept
# apart so that site's measured state does not change.
_g_mask() {
  jq -rn --arg t "$1" "$_G_JQ_MASK"'$t | mask'
}

# Programs that only read, print or change the shell's own state.
# None of them writes a file or starts another program through an option:
# sort (-o), uniq (a second operand), rg (--pre), tree (-o), file (-C), date
# (-s), hostname, export and unset are not here, and are sent.
_G_PLAIN=" ls cat head tail wc grep egrep fgrep echo printf pwd which type whoami id uname stat du df basename dirname realpath readlink true false test [ diff cmp cut tr jq column nl od shasum sha256sum md5 md5sum cd sleep seq "
# Assignments that cannot change which program runs or what it runs.
_G_SAFE_VARS=" LC_ALL LANG LANGUAGE TZ NO_COLOR TERM COLUMNS LINES "
_G_GIT_READ=" status log diff show rev-parse ls-files ls-tree blame describe shortlog grep cat-file merge-base rev-list show-ref for-each-ref "

# _g_redir_skip <redirection token>: sets _G_SKIP=1 when the redirection
# takes the next token as its target (`> file`, `2> file`, `<<< text`).
# Where a redirection writes is checked before the command is tokenised, in
# _g_segment_ok.
_g_redir_skip() {
  local t="$1"
  _G_SKIP=0
  case "$t" in
    '<'|'<<'|'<<<') _G_SKIP=1; return 0 ;;
    '<'*) return 0 ;;
  esac
  # Only the operator (2>, >>, >|): the target is the next token.
  [ -n "$t" ] && [ -z "${t//[0-9>|]/}" ] && _G_SKIP=1
  return 0
}

# _g_rewrites <simple command>: 0 when the shell would rewrite some word of it
# before the program sees it: a backslash, $ or a backtick outside single
# quotes, or a brace, *, ? or [...] outside any quotes. Quoted text with none
# of these reaches the program as written. An awk that fails answers 0.
_g_rewrites() {
  local r
  r=$(printf '%s\n' "$1" | LC_ALL=C awk '
    BEGIN { SQ = sprintf("%c", 39); DQ = sprintf("%c", 34); BS = sprintf("%c", 92) }
    { s = (NR > 1) ? s "\n" $0 : $0 }
    END {
      q = ""; n = length(s); ob = 0
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (q == SQ) { if (c == SQ) q = ""; continue }
        if (c == BS || c == "$" || c == "`") { print 1; exit }
        if (q == DQ) { if (c == DQ) q = ""; continue }
        if (c == SQ || c == DQ) { q = c; continue }
        if (c == "*" || c == "?" || c == "{") { print 1; exit }
        # [...] in one word: remember an open [ until whitespace.
        if (c == " " || c == "\t" || c == "\n") { ob = 0; continue }
        if (c == "[") { ob = 1; continue }
        if (c == "]" && ob) { print 1; exit }
      }
      print 0
    }' 2>/dev/null)
  [ "$r" != 0 ]
}

# _g_system_prog <word>: 0 when the word names a program by its bare name or
# from a system directory: ./cat or script/test can do anything.
_g_system_prog() {
  case "$1" in
    */*) case "${1%/*}" in /bin|/usr/bin|/usr/local/bin|/opt/homebrew/bin) return 0 ;; *) return 1 ;; esac ;;
  esac
  return 0
}

# _g_segment_ok <simple command>: 0 when it only reads.
_g_segment_ok() {
  local seg="$1" i n tok prog rest a
  local -a TOK=() ARGS=()
  # Any > left once the redirections to /dev/null, /dev/stdout or /dev/stderr
  # are removed writes somewhere, wherever it stands in a word (a>b, >&file,
  # <>file); a > inside quotes is sent too.
  rest=$(printf '%s' "$seg" | sed -E 's#[0-9]*>>?[[:space:]]*/dev/(null|stdout|stderr)([[:space:]]|$)# \2#g') || return 1
  case "$rest" in *'>'*) return 1 ;; esac
  _rm_tokenise "$seg"
  n=${#TOK[@]}
  _G_SKIP=0
  for ((i = 0; i < n; i++)); do
    tok="${TOK[i]}"
    if [ "$_G_SKIP" = 1 ]; then _G_SKIP=0; continue; fi
    case "$tok" in
      [0-9]'>'*|[0-9][0-9]'>'*|'>'*|'<'*)
        _g_redir_skip "$tok"
        continue ;;
    esac
    ARGS+=("$tok")
  done
  # A leading assignment can change what the program runs (PATH, GIT_*,
  # LD_PRELOAD, PAGER), so only a few harmless names are allowed. An index
  # moves past them: shifting the array each time is quadratic in bash.
  i=0
  while [ "$i" -lt "${#ARGS[@]}" ] && [[ "${ARGS[i]}" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; do
    case "${BASH_REMATCH[1]}" in LC_*) ;; *) case "$_G_SAFE_VARS" in *" ${BASH_REMATCH[1]} "*) ;; *) return 1 ;; esac ;; esac
    i=$((i + 1))
  done
  [ "$i" = 0 ] || ARGS=("${ARGS[@]:i}")
  [ "${#ARGS[@]}" -gt 0 ] || return 0
  # A listed program named by a path is the system's only in a system
  # directory: ./cat or script/test can do anything.
  _g_system_prog "${ARGS[0]}" || return 1
  prog="${ARGS[0]##*/}"
  # printf -v assigns a variable (PATH, GIT_DIR, PAGER), which the leading
  # assignments rule above exists to stop.
  if [ "$prog" = printf ]; then
    _g_rewrites "$seg" && return 1
    for a in "${ARGS[@]:1}"; do case "$a" in -v*) return 1 ;; esac; done
  fi
  case "$_G_PLAIN" in *" $prog "*) return 0 ;; esac
  # The checks below compare words with options that write or delete, so a
  # word the shell rewrites (-de\lete, $'-delete', -{delete,x}, ${X}, *)
  # could become one of them: such a command is sent.
  _g_rewrites "$seg" && return 1
  # A command substitution is split off as its own command and leaves
  # __BD_SUBST__ here, but its output becomes words of this one.
  case "$seg" in *__BD_SUBST__*) return 1 ;; esac
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
    case "$a" in -c|-c?*|--config-env*|--exec-path*|--git-dir*|--work-tree*) return 1 ;; esac
  done
  _bd_git_parse "$1" || return 1
  local -a G=()
  for a in "${GIT_ARGS[@]+"${GIT_ARGS[@]}"}"; do
    _bd_is_redirection "$a" && continue
    # Options that write a file or start a program.
    # git grep and cat-file take abbreviated long options (--open=,
    # --textc), so every prefix of a writing or program option is sent.
    # -O also bundles with other short flags (-iOcmd).
    case "$a" in --output|--output=*|-O*|-[!-]*O*|--op*|--ou*|--ext*|--te*) return 1 ;; esac
    G+=("$a")
  done
  case " $_G_GIT_READ " in *" $GIT_SUB "*) return 0 ;; esac
  case "$GIT_SUB" in
    branch|tag)
      # A name makes git create a ref unless a listing option is given;
      # -v, --sort and the like only change how a list looks.
      for a in "${G[@]+"${G[@]}"}"; do
        case "$GIT_SUB $a" in
          "branch -l"|"branch --list"|"branch -a"|"branch --all"|"branch -r"|"branch --remotes"|"branch --show-current"|"tag -l"|"tag --list") listing=1 ;;
          *" --contains"|*" --no-contains"|*" --merged"|*" --no-merged"|*" --points-at") listing=1 ;;
          *" -v"|*" -vv"|*" --verbose"|*" --sort="*|*" --format="*|*" --column"|*" --no-column"|"tag -n"*) ;;
          *" -"*) return 1 ;;
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
  # Only a duplication onto a descriptor (2>&1, >&2, <&0, >&-) is removed:
  # >&2025-report.csv writes a file and keeps its >.
  code=$(printf '%s' "$BD_CODE" | sed -E 's/[0-9]*[<>]&([0-9]+-?|-)([[:space:];|&)<>]|$)/ \2/g; s/&>>/ >> /g; s/&>/ > /g')
  _G_SEGS=$(_bd_segments "$code")
  case "$_G_SEGS" in *__BD_SEG_FAIL__*|*__BD_UNBALANCED__*) return 1 ;; esac
  return 0
}

# _G_MAX_SEGS: a command of more simple commands than this is sent (or, for a
# gh read, not screened) without checking each: each check starts processes,
# and the length cap alone does not bound their number.
_G_MAX_SEGS=64

_g_ruled_out() {
  local seg any=0
  [[ $1 == *[![:space:]]* ]] || return 1
  _g_segments "$1" || return 1
  while IFS= read -r seg; do
    [[ $seg == *[![:space:]]* ]] || continue
    any=$((any + 1))
    [ "$any" -le "$_G_MAX_SEGS" ] || return 1
    _g_segment_ok "$seg" || return 1
  done <<<"$_G_SEGS"
  [ "$any" -gt 0 ]
}

# _g_gh_filter <words...>: 0 when the simple command only reshapes what the
# gh read printed: head or tail with -n N, -c N or -N, wc with -l, -w, -c or
# -m, or jq with output options and at most one path filter (.body,
# .comments[].body, .[0].title). Anything that could print other content (a
# file operand, a long option, a jq filter that reads the environment or
# another input) is not.
_g_gh_filter() {
  local a n=0 prev="" path='^\.(\[[0-9]*\]|[A-Za-z_][A-Za-z0-9_]*)?(\.[A-Za-z_][A-Za-z0-9_]*|\[[0-9]*\])*$'
  case "${1##*/}" in
    head|tail)
      shift
      for a in "$@"; do
        if [ -n "$prev" ]; then [[ "$a" =~ ^[0-9]+$ ]] || return 1; prev=""; continue; fi
        case "$a" in
          -n|-c) prev=1 ;;
          *) [[ "$a" =~ ^-[nc]?[0-9]+$ ]] || return 1 ;;
        esac
      done
      [ -z "$prev" ] ;;
    wc)
      shift
      for a in "$@"; do case "$a" in -l|-w|-c|-m) ;; *) return 1 ;; esac; done ;;
    jq)
      shift
      for a in "$@"; do
        case "$a" in
          -r|-c|-e|-S|-M|-j|--raw-output|--compact-output) ;;
          -*) return 1 ;;
          *) n=$((n + 1)); [[ "$a" =~ $path ]] || return 1 ;;
        esac
      done
      [ "$n" -le 1 ] ;;
    *) return 1 ;;
  esac
}

# _g_gh_read_ok <args after gh>: 0 when they are `issue view` or `pr view`
# with only -R/--repo, -c/--comments, --json and a --jq/-q path filter, and
# at most one issue or pull request, or `api` as GET (-X/--method GET) with
# only --paginate and a --jq/-q path filter, and exactly one endpoint that is
# an issues or pulls path of a repository (a full API URL too). Any other
# option (--template, -H, --input, ...) means the read is not screened.
_g_gh_read_ok() {
  local a prev="" n=0 ep="" path='^\.(\[[0-9]*\]|[A-Za-z_][A-Za-z0-9_]*)?(\.[A-Za-z_][A-Za-z0-9_]*|\[[0-9]*\])*$'
  case "${1:-} ${2:-}" in
    "issue view"|"pr view")
      shift 2
      for a in "$@"; do
        case "$prev" in
          value) prev=""; continue ;;
          jq) prev=""; [[ "$a" =~ $path ]] || return 1; continue ;;
        esac
        case "$a" in
          -R|--repo|--json) prev=value ;;
          -R?*|--repo=*|--json=*|-c|--comments) ;;
          -q|--jq) prev=jq ;;
          --jq=*) [[ "${a#--jq=}" =~ $path ]] || return 1 ;;
          -*) return 1 ;;
          *) n=$((n + 1)) ;;
        esac
      done
      [ -z "$prev" ] && [ "$n" -le 1 ] ;;
    "api "*)
      shift
      for a in "$@"; do
        case "$prev" in
          method) prev=""; [ "$(printf '%s' "$a" | tr '[:lower:]' '[:upper:]')" = GET ] || return 1; continue ;;
          jq) prev=""; [[ "$a" =~ $path ]] || return 1; continue ;;
        esac
        case "$a" in
          -X|--method) prev=method ;;
          -X*) [ "$(printf '%s' "${a#-X}" | tr '[:lower:]' '[:upper:]')" = GET ] || return 1 ;;
          --method=*) [ "$(printf '%s' "${a#--method=}" | tr '[:lower:]' '[:upper:]')" = GET ] || return 1 ;;
          --paginate) ;;
          -q|--jq) prev=jq ;;
          --jq=*) [[ "${a#--jq=}" =~ $path ]] || return 1 ;;
          -*) return 1 ;;
          *) n=$((n + 1)); ep="$a" ;;
        esac
      done
      [ -z "$prev" ] && [ "$n" = 1 ] || return 1
      # Text people write, not code: a pull request's files, commits, diff or
      # patch are not screened, and neither is a path with a .. segment.
      [[ "$ep" =~ (^|/)\.\.(/|$) ]] && return 1
      [[ "$ep" =~ /pulls/[^/]+/(files|commits)(/|\?|$) ]] && return 1
      [[ "$ep" =~ \.(diff|patch)(\?|$) ]] && return 1
      [[ "$ep" =~ ^(https?://[^/]+)?/?repos/[^/]+/[^/]+/(issues|pulls)(/|\?|$) ]] ;;
    *) return 1 ;;
  esac
}

# _g_gh_read <command>: 0 when the command is one gh read of issue or pull
# request text (_g_gh_read_ok), after any `cd <dir>`, optionally piped into
# _g_gh_filter commands. gh and the filters must be named bare or from a
# system directory, and only harmless variables and gh's own (GH_REPO,
# GH_HOST, the token variables, sent masked) may be set before gh. A gh read
# chained to any other command is not screened: its output would carry that
# command's too.
_g_gh_read() {
  local seg reads=0 segs=0 k
  local -a TOK=() ARGS=() B=()
  _g_segments "$1" || return 1
  while IFS= read -r seg; do
    [[ $seg == *[![:space:]]* ]] || continue
    segs=$((segs + 1))
    [ "$segs" -le "$_G_MAX_SEGS" ] || return 1
    TOK=(); _rm_tokenise "$seg"
    ARGS=("${TOK[@]+"${TOK[@]}"}")
    [ "${#ARGS[@]}" -gt 0 ] || continue
    if [ "${ARGS[0]}" = cd ] && [ "${#ARGS[@]}" -le 2 ]; then continue; fi
    # A word the shell rewrites ($'--jq=env', \--jq, ${X:--jq}) could become
    # an option the grammar below refuses.
    _g_rewrites "$seg" && return 1
    k=0
    while [ "$k" -lt "${#ARGS[@]}" ] && [[ "${ARGS[k]}" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; do
      case "${BASH_REMATCH[1]}" in
        LC_*|GH_REPO|GH_HOST|GH_TOKEN|GITHUB_TOKEN|GH_ENTERPRISE_TOKEN) ;;
        *) case "$_G_SAFE_VARS" in *" ${BASH_REMATCH[1]} "*) ;; *) return 1 ;; esac ;;
      esac
      k=$((k + 1))
    done
    [ "$k" -lt "${#ARGS[@]}" ] || return 1
    B=("${ARGS[@]:k}")
    if [ "${B[0]##*/}" = gh ]; then
      _g_system_prog "${B[0]}" || return 1
      _g_gh_read_ok "${B[@]:1}" || return 1
      reads=$((reads + 1))
      continue
    fi
    _g_system_prog "${ARGS[0]}" || return 1
    _g_gh_filter "${ARGS[@]}" || return 1
  done <<<"$_G_SEGS"
  [ "$reads" = 1 ]
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

# _g_text_state <command>: from the hook payload on stdin. Output that parses
# as JSON, as one document or one per line, is sent as every string in it,
# the titles and bodies first and each string once, so planted text in a long
# line of JSON or in any field is not lost; other output is sent as its lines.
# A line over 1000 characters is split into 1000-character pieces. Past 600
# lines the first 300 and the last 300 are kept and the state carries
# "truncated": true, as it does when output over 2,000,000 characters is cut
# to its first and last 1,000,000. Every line passes through `shapes` before
# it is split, so a credential across a cut is masked whole.
_g_text_state() {
  local masked
  masked=$(_g_mask "$1") || return 1
  jq -c --arg cmd "${masked:0:2000}" "$_G_JQ_SHAPES"'
    def lines: (if endswith("\n") then .[:-1] else . end)
      | if . == "" then [] else split("\n") end;
    def docs: (try fromjson catch null) as $one
      | if ($one | type) == "object" or ($one | type) == "array" then [$one]
        else [lines[] | select(test("\\S"))] as $ls
          | [$ls[] | (try fromjson catch null) | select(type == "object" or type == "array")] as $ds
          | if ($ls | length) > 0 and ($ds | length) == ($ls | length) then $ds else null end
        end;
    def texts: ([.. | objects | (.title?, .body?) | strings] + [.. | strings])
      | reduce .[] as $x ({seen: {}, out: []}; if .seen[$x] then . else .seen[$x] = true | .out += [$x] end) | .out;
    def pieces: if length <= 1000 then [.] else [match("[\\s\\S]{1,1000}"; "g").string] end;
    (.tool_response.stdout | if type == "string" then . else "" end) as $s0
    | ($s0 | length > 2000000) as $cut
    | (if $cut then $s0[0:1000000] + "\n" + $s0[-1000000:] else $s0 end) as $s
    | ($s | docs) as $ds
    | (if $ds then [$ds | texts | .[] | lines[]] else ($s | lines) end) as $ls
    | [$ls[] | shapes | pieces[]] as $all
    | {command: $cmd, output: (if ($all | length) > 600 then $all[0:300] + $all[-300:] else $all end)}
      + (if ($all | length) > 600 or $cut then {truncated: true} else {} end)'
}

# _g_sweep_stale: remove this user's state and payload files left by a hook
# that was killed, older than 10 minutes (timeoutMs is at most 30 s).
_g_sweep_stale() {
  find "${TMPDIR:-/tmp}/" -maxdepth 1 -type f -name 'flow-s1-guard.*' -user "$(id -u)" -mmin +10 \
    -exec rm -f {} + >/dev/null 2>&1 || true
}

_g_detach() {
  python3 -I -c '
import os, sys
if os.fork():
    os._exit(0)
try:
    os.setsid()
    if os.fork():
        os._exit(0)
    fd = os.open(os.devnull, os.O_RDWR)
    for i in (0, 1, 2):
        os.dup2(fd, i)
    os.execvp("bash", ["bash", "-c", "f=$1; shift; \"$@\"; rm -f -- \"$f\"", "flow-s1-guard"] + sys.argv[1:])
except BaseException:
    # Nothing will run the command, so nothing would remove the file.
    try:
        os.unlink(sys.argv[1])
    except OSError:
        pass
    os._exit(1)
' "$@" </dev/null >/dev/null 2>&1
}
