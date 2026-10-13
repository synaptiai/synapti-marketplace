#!/usr/bin/env bash
# plugins/flow/hooks/scripts/lib/s1-guard.sh
#
# Shared by the System One guard hooks: s1-command-intent.sh (site
# guard.command-intent) and s1-screen-text.sh (site guard.planted-instructions),
# and by the measurement in evals/results-2026-10-12-s1-guard, so the state
# measured is the state the hooks send. Sources lib/command-parse.sh.
#
#   _g_mask <text>                 the text with every credential _G_JQ_MASK
#                                  knows replaced by ***, word by word
#   _g_words <text>                the text as shell words and separators
#   _g_credential_verdict <command>
#                                  true when the command is not to be sent
#   _g_skip_credential <command>   0 when the command is not sent
#   _g_jq_field <command>          0 when the gh read's last jq filter is a
#                                  path that ends in a field
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

# _G_JQ_SHAPES: jq definitions. Every pattern starts only where a run starts
# and either has bounded lengths or scans that one run, so its cost grows with
# the text, not faster. `shapes` replaces values shaped like a credential
# wherever they stand: tokens with a known prefix, JSON web tokens, any run of
# 20 to 512 letters, digits, _ + = or - that mixes upper case, lower case and
# digits, any longer such run that holds a letter and a digit, and a
# 40-character run of letters, digits, / and + that mixes them (an AWS secret
# key). Hex digests (no upper case), paths (split at / and .) and words are
# left alone. No pattern takes in whitespace, a quote or a shell operator. It
# is the only rule applied to the output of a screened gh read: rules keyed on
# a name ("api-key: ...") would also hide the text that follows the name, and
# with it a planted instruction.
_G_JQ_SHAPES='
def shapes:
  gsub("(?<![A-Za-z0-9_-])(?:gh[pousr]_[A-Za-z0-9]{10,255}|github_pat_[A-Za-z0-9_]{10,255}|sk-[A-Za-z0-9_-]{16,255}|xox[abprs]-[A-Za-z0-9-]{10,255}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|dop_v1_[a-f0-9]{20,255}|shpat_[a-f0-9]{20,255}|glpat-[A-Za-z0-9_-]{10,255}|AIza[0-9A-Za-z_-]{20,255}|eyJ[A-Za-z0-9_-]{4,4096}\\.[A-Za-z0-9_-]{4,4096}\\.[A-Za-z0-9_-]{4,4096})"; "***")
  | gsub("(?<![A-Za-z0-9_+=-])(?=[A-Za-z0-9_+=-]*[A-Za-z])(?=[A-Za-z0-9_+=-]*[0-9])[A-Za-z0-9_+=-]{513,}"; "***")
  | gsub("(?<![A-Za-z0-9_+=-])(?=[A-Za-z0-9_+=-]{0,511}[A-Z])(?=[A-Za-z0-9_+=-]{0,511}[a-z])(?=[A-Za-z0-9_+=-]{0,511}[0-9])[A-Za-z0-9_+=-]{20,512}(?![A-Za-z0-9_+=-])"; "***")
  | gsub("(?<![A-Za-z0-9/+=])(?=[A-Za-z0-9/+]{0,39}[A-Z])(?=[A-Za-z0-9/+]{0,39}[a-z])(?=[A-Za-z0-9/+]{0,39}[0-9])[A-Za-z0-9+][A-Za-z0-9/+]{39}(?![A-Za-z0-9/+=])"; "***");
'

# _g_words <text>: the text as shell words and the separators between them,
# in order, each a record "W<US>word<RS>" or "S<US>separator<RS>" (US is
# \037, RS is \036). A line continuation (a backslash before a newline) is
# removed first, so a value moved to the next line stays in its word. A
# separator is a run of whitespace and ; & | ( ) < > outside quotes, or a
# comment from a # that starts a word to the end of its line. The body of a
# heredoc, with its closing line, is split at whitespace and those operators
# without reading quotes, so an apostrophe in it opens nothing. A command
# substitution, $(...) or a backtick pair, inside double quotes or not, is
# read as the shell reads it: its words come out as words, with quotes of
# their own. A word keeps its quotes and backslashes as written. Returns 1
# when the text holds \036 or \037, when it ends inside a quote or a
# substitution (the words after it cannot be told apart), or when awk fails.
_g_words() {
  case "$1" in *$'\036'*|*$'\037'*) return 1 ;; esac
  printf '%s\n' "$1" | LC_ALL=C awk '
    function flush(e) { if (cur != "") printf "%s\037%s\036", cur, substr(s, st, e - st); cur = "" }
    function issep(c) { return c == " " || c == "\t" || c == "\n" || index(";&|()<>", c) }
    # Records for s[a, b), split at separators, quotes not read.
    function plain(a, b,   k, t, t0, u) {
      t = ""
      for (k = a; k < b; k++) {
        u = issep(substr(s, k, 1)) ? "S" : "W"
        if (u != t) { if (t != "") printf "%s\037%s\036", t, substr(s, t0, k - t0); t = u; t0 = k }
      }
      if (t != "") printf "%s\037%s\036", t, substr(s, t0, b - t0)
    }
    # The delimiter of the heredoc whose << ends at j: the next word, with
    # its quotes and backslashes removed.
    function hdword(j,   k, c, d, qq) {
      k = j + 1
      if (substr(s, k, 1) == "-") { hdash[nq] = 1; k++ } else hdash[nq] = 0
      while (substr(s, k, 1) == " " || substr(s, k, 1) == "\t") k++
      d = ""; qq = ""
      for (; k <= n; k++) {
        c = substr(s, k, 1)
        if (qq != "") { if (c == qq) qq = ""; else d = d c; continue }
        if (c == SQ || c == DQ) { qq = c; continue }
        if (c == BS) { k++; d = d substr(s, k, 1); continue }
        if (c == " " || c == "\t" || c == "\n" || index(";&|()<>", c)) break
        d = d c
      }
      return d
    }
    BEGIN { SQ = sprintf("%c", 39); DQ = sprintf("%c", 34); BS = sprintf("%c", 92) }
    { s = (NR > 1) ? s "\n" $0 : $0 }
    END {
      gsub(BS BS "\n", "", s)
      n = length(s); q = ""; cur = ""; nq = 0; dp = 0
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (q == SQ) { if (c == SQ) q = ""; continue }
        if (q == DQ || q == "A") {
          if (c == BS) { i++; continue }
          # A command substitution inside double quotes: its words come out
          # as words, with quotes of their own, and the quote resumes after it.
          if (q == DQ && c == "$" && substr(s, i + 1, 1) == "(") {
            flush(i + 1); i++; dp++; qs[dp] = DQ; pc[dp] = 0; bq[dp] = 0; q = ""; cur = "S"; st = i
            continue
          }
          if (q == DQ && c == "`") { flush(i + 1); dp++; qs[dp] = DQ; pc[dp] = 0; bq[dp] = 1; q = ""; continue }
          if ((q == DQ && c == DQ) || (q == "A" && c == SQ)) q = ""
          continue
        }
        if (c == "`" && dp > 0 && bq[dp]) {
          flush(i); q = qs[dp]; dp--; cur = "W"; st = i
          continue
        }
        if (c == "`") {
          if (cur != "W") { flush(i); cur = "W"; st = i }
          flush(i + 1); dp++; qs[dp] = ""; pc[dp] = 0; bq[dp] = 1
          continue
        }
        if (c == " " || c == "\t" || c == "\n" || index(";&|()<>", c)) {
          if (cur != "S") { flush(i); cur = "S"; st = i }
          if (c == "(" && substr(s, i - 1, 1) == "$") { dp++; qs[dp] = ""; pc[dp] = 0; bq[dp] = 0 }
          else if (c == "(" && dp > 0) pc[dp]++
          else if (c == ")" && dp > 0 && !bq[dp]) {
            if (pc[dp] > 0) pc[dp]--
            else {
              q = qs[dp]; dp--
              if (q != "") { flush(i + 1); cur = "W"; st = i + 1 }
              continue
            }
          }
          if (c == "<" && substr(s, i + 1, 1) == "<" && substr(s, i + 2, 1) != "<" && substr(s, i - 1, 1) != "<") {
            nq++; hd[nq] = hdword(i + 1)
          }
          if (c == "\n" && nq > 0) {
            # The bodies of the heredocs opened on this line follow it.
            p = i + 1
            for (k = 1; k <= nq; k++) {
              while (p <= n) {
                e = index(substr(s, p), "\n"); e = (e == 0) ? n + 1 : p + e - 1
                line = substr(s, p, e - p)
                if (hdash[k]) sub(/^\t+/, "", line)
                p = e + 1
                if (line == hd[k]) break
              }
            }
            flush(i + 1)
            e = (p > n + 1) ? n + 1 : p - 1
            plain(i + 1, e)
            i = e - 1; nq = 0
          }
          continue
        }
        if (c == "#" && cur != "W") {
          if (cur != "S") { flush(i); cur = "S"; st = i }
          e = index(substr(s, i), "\n"); i = (e == 0) ? n : i + e - 2
          continue
        }
        if (cur != "W") { flush(i); cur = "W"; st = i }
        if (c == BS) { i++; continue }
        if (c == SQ) {
          # A $ before this quote opens a string with escapes, unless a
          # backslash escapes the $.
          b = 0
          if (i > st && substr(s, i - 1, 1) == "$") for (k = i - 2; k >= st && substr(s, k, 1) == BS; k--) b++
          q = (i > st && substr(s, i - 1, 1) == "$" && b % 2 == 0) ? "A" : SQ
          continue
        }
        if (c == DQ) q = DQ
      }
      flush(n + 1)
      if (q != "" || dp > 0) exit 1
    }'
}

# _G_JQ_MASK: jq definitions. `mask` is what _g_mask applies to the records
# _g_words makes of a command. Each rule replaces text inside one shell word,
# and never past the end of its line, so no mask can take in an operator or
# the command after it. The rules go by kind, not by a list of names:
# - in a word that starts NAME=, NAME+= or NAME[i]=, the value;
# - in an option (- or --) whose name holds token, secret, pass, pwd, key,
#   auth, credential, bearer or cookie, or that is --user or --proxy-user,
#   the value after =, or else the next word;
# - -u or -U user:password, attached or as the next word;
# - the password options of mysql, mysqldump, mysqladmin, mariadb and 7z
#   (-pVALUE), sshpass, mongosh and mongo (-p), redis-cli (-a), docker login
#   (-p), zip, unzip and sqlcmd (-P), ssh-keygen (-N), smbclient (-U
#   user%VALUE) and gh secret set (--body, -b), when that program is a word of
#   the same simple command;
# - after a word whose name holds one of those words and ends in a colon
#   (Authorization:), the next word, or the one after Bearer, Basic or Token;
# - inside any word: user:password@ in a URL, what follows one of those
#   names and a colon (a header, pass:VALUE), quoted or up to the next space
#   or quote; the value of a JSON or dict key whose name holds one; and the
#   value of a name=value pair (?apikey=, -d 'access_key=', api.key=);
# - and `shapes` above, over the whole text.
_G_JQ_MASK=$_G_JQ_SHAPES'
def kind: "(?i:token|secret|pass|pwd|key|auth|credential|bearer|cookie)";
def hide: sub("\\A[^\\n]*"; "***");
def after($n): .[0:$n] + (.[$n:] | hide);
def inword:
  if test("://|[:=]") then
    gsub("(?<s>(?<![A-Za-z0-9+.-])[A-Za-z][A-Za-z0-9+.-]{0,30}://)[^/\\s@\u0027\"]+@"; "\(.s)***@")
    | gsub("(?<o>(?<q>\\\\?[\"\u0027])[^\"\u0027\\s\\\\]{0,64}" + kind + "[^\"\u0027\\s\\\\]{0,64}\\\\?[\"\u0027][ \\t]*:[ \\t]*)(?:\\\\?\"(?:[^\"\\\\\\n]|\\\\[^\"\\n])*\\\\?\"|\u0027[^\u0027\\n]*\u0027)"; "\(.o)\(.q)***\(.q)")
    | gsub("(?<o>(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{0,64}" + kind + "[A-Za-z0-9_-]{0,64}[ \\t]*:[ \\t]*(?:(?i:bearer|basic|token)[ \\t]+)?)(?:\u0027[^\u0027\\n]*\u0027|\"(?:[^\"\\\\\\n]|\\\\.)*\"|[^\u0027\"\\s]+)"; "\(.o)***")
    | gsub("(?<o>[?&\u0027\"=.\\s][A-Za-z0-9_.-]{0,64}" + kind + "[A-Za-z0-9_.-]{0,64}=)[^&\\s\u0027\";|]+"; "\(.o)***")
  else . end;
def progkey: {"mysql": "my", "mysqldump": "my", "mysqladmin": "my", "mariadb": "my", "7z": "my", "7za": "my",
  "sshpass": "sp", "mongosh": "sp", "mongo": "sp", "redis-cli": "rc", "docker": "dk", "login": "lg",
  "zip": "zp", "unzip": "zp", "sqlcmd": "zp", "ssh-keygen": "kg", "smbclient": "sb",
  "gh": "gh", "secret": "sc", "set": "st"}[.];
def short($o; $f): if . == $o then [., "val"] elif startswith($o) and $f then [after(2), ""] else null end;
def word($f):
  if (startswith("-") or contains("=") or contains(":")) | not then [., ""]
  elif test("\\A[A-Za-z_][A-Za-z0-9_]*(?:\\[[^\\]\\s]*\\])?\\+?=") then [after(index("=") + 1), ""]
  elif test("\\A--?(?:user|proxy-user|[A-Za-z0-9_.:-]{0,64}" + kind + "[A-Za-z0-9_.:-]{0,64})(?:=|\\z)") then
    (if contains("=") then [after(index("=") + 1), ""] else [., "val"] end)
  elif $f.sb and startswith("-U") then (if . == "-U" then [., "smb"] else [sub("%[^\\n]*"; "%***"), ""] end)
  elif . == "-u" or . == "-U" then [., "u"]
  elif test("\\A-[uU][\"\u0027]?[^\\s:\"\u0027]+:") then [after(2), ""]
  elif $f.my and test("\\A-p.") then [after(2), ""]
  else
    ((if $f.sp then short("-p"; true) else null end)
     // (if $f.rc then short("-a"; true) else null end)
     // (if $f.dk and $f.lg then short("-p"; true) else null end)
     // (if $f.zp then short("-P"; true) else null end)
     // (if $f.kg then short("-N"; true) else null end)
     // (if $f.gh and $f.sc and $f.st then (short("-b"; true) // short("--body"; false)
          // (if startswith("--body=") then [after(7), ""] else null end)) else null end)
     // (if test(kind + "[A-Za-z0-9_.-]{0,64}:\\z") then [inword, "hdr"] else null end)
     // [inword, ""])
  end;
def mask:
  [split("\u001e")[] | select(length > 0) | {w: startswith("W"), t: .[2:]}]
  | reduce .[] as $p ({out: [], pend: "", f: {}};
      if ($p.w | not) then
        .out += [$p.t]
        | if ($p.t | test("[;&|()\\n]")) then .pend = "" | .f = {} else . end
        | if ($p.t | test("[<>]")) then .pend = "" else . end
      else
        $p.t as $t
        | (if ($t | length) > 64 then null
           else (($t | ascii_downcase | gsub("[\"\u0027\\\\]"; "") | sub("\\A.*/"; "") | progkey) // null) end) as $k
        | (if $k then .f[$k] = true else . end)
        | if .pend == "val" then .out += [$t | hide] | .pend = ""
          elif .pend == "hdr" then
            (if ($t | test("\\A(?i:bearer|basic|token)\\z")) then .out += [$t] | .pend = "val"
             else .out += [$t | hide] | .pend = "" end)
          elif .pend == "u" then
            .out += [if ($t | test("\\A[\"\u0027]?[^\\s:\"\u0027]+:")) then ($t | hide) else ($t | inword) end] | .pend = ""
          elif .pend == "smb" then .out += [$t | sub("%[^\\n]*"; "%***")] | .pend = ""
          else .f as $f | ($t | word($f)) as $r | .out += [$r[0]] | .pend = $r[1]
          end
      end)
  | .out | join("") | shapes;
'

# _G_JQ_SKIP: jq definitions. A command is not sent when it may hold a
# credential the masking did not place (the user's choices, 2026-10-13: mask
# what can be placed, else skip). `leftover` is true when the masked command
# still holds a credential word not run together with other letters (token,
# secret, password, passwd, passphrase, pwd, key, api_key, auth, credential,
# bearer, cookie, login, signin, netrc, SecureString, or any of them in the
# plural; auth.json, GITHUB_TOKEN and .user.login count) anywhere but
# in front of a value the masking replaced: a heredoc into `doppler secrets
# set`, `--client.secret pw`, a SecureString in --cli-input-json and any
# other shape no rule names. `risky` is true for the shapes that carry no such
# word, or carry it where the masking does replace something: a secret fed
# on stdin (--password-stdin, --with-token, gh secret set without --body), a
# positional secret of a credential program (vault login, write or kv, aws
# configure set, npm config set, htpasswd, chpasswd, kubectl create secret,
# gh auth login, security add-*-password, kinit, docker or podman secret
# create, wrangler secret put, vercel env add), a password read from stdin, a file descriptor
# or a process substitution (sudo -S, --passphrase-fd, -passin stdin, an
# option named for a credential whose value is <(...), /dev/stdin,
# /dev/fd/N, /proc/self/fd/N, file:/dev/stdin or -, a here-string on a
# command with such an option, ssh-add -), and a long base64 run that mixes
# upper case, lower case and digits and holds + (but not c++-style ++/) or
# holds / between two parts of 8 or more characters that each hold a digit
# and does not start with / (a path, such as a temporary directory, does).
_G_JQ_SKIP='
def words: "(?:tokens?|secrets?|passwords?|passwds?|passphrases?|pwds?|api[_-]?keys?|keys?|auths?|credentials?|bearers?|cookies?|logins?|signins?|netrcs?|securestrings?)";
def leftover:
  gsub("(?i:(?<![A-Za-z0-9_.:-])[A-Za-z0-9_.:-]{0,64}" + words + "[A-Za-z0-9_.:-]{0,64}(?:\\[[^\\]\\s]{0,64}\\])?\\\\?[\"\u0027]?[ \\t]*\\+?[:=]?[ \\t]*(?:(?:bearer|basic|token)[ \\t]+)?\\\\?[\"\u0027]?\\*\\*\\*)"; "")
  | test("(?i:(?<![A-Za-z])" + words + "(?![A-Za-z]))");
def risky:
  test("--[A-Za-z_.:-]{0,40}stdin\\b|--with-token\\b")
  or (test("\\bgh\\s+secret\\s+set\\b") and (test("\\bgh\\s+secret\\s+set\\b[^;&|\\n]{0,400}?\\s(?:--body|-b)") | not))
  or test("\\b(?:vault\\s+(?:login|write|kv)|aws\\s+configure\\s+set|npm\\s+config\\s+set|htpasswd|chpasswd|kubectl\\s+create\\s+secret|gh\\s+auth\\s+login|security\\s+add-(?:generic|internet)-password|kinit|(?:docker|podman)\\s+secret\\s+create|wrangler\\s+secret\\s+put|vercel\\s+env\\s+add)\\b")
  or test("\\bsudo\\b[^;&|\\n]{0,200}?\\s(?:-[A-Za-z]*S[A-Za-z]*|--stdin)\\b|--passphrase-fd\\b|-pass(?:in|out)?\\s+(?:stdin|fd:)")
  or test("--?[A-Za-z_.:-]{0,40}(?i:pass|token|secret|key|auth|cred)[A-Za-z_.:-]{0,40}(?:=|\\s+)(?:<\\(|/dev/stdin\\b|/dev/fd/[0-9]|/proc/self/fd/|-(?:\\s|$|[;&|)])|fd:|file:/+dev/stdin)")
  or (test("<<<") and test("(?:^|\\s)--?[A-Za-z_.:-]{0,40}(?i:pass|token|secret|key|auth|cred)"))
  or test("\\bssh-add\\b[^;&|\\n]{0,200}?\\s-(?:\\s|$)")
  or test("(?<![A-Za-z0-9/+=])(?=[A-Za-z0-9/+]{0,39}[A-Z])(?=[A-Za-z0-9/+]{0,39}[a-z])(?=[A-Za-z0-9/+]{0,39}[0-9])[A-Za-z0-9+][A-Za-z0-9/+]{39}(?![A-Za-z0-9/+=])")
  or test("(?<![A-Za-z0-9/+=])(?![A-Za-z0-9/+=]{0,200}(?:/\\+\\+|\\+\\+/))(?=[A-Za-z0-9/+=]{0,200}\\+)(?=[A-Za-z0-9/+=]{0,200}[A-Z])(?=[A-Za-z0-9/+=]{0,200}[a-z])(?=[A-Za-z0-9/+=]{0,200}[0-9])[A-Za-z0-9/+=]{24,}")
  or test("(?<![A-Za-z0-9/+=])(?=[A-Za-z0-9+=])(?=[A-Za-z0-9/+=]{32,})(?=[A-Za-z0-9/+=]{0,200}[A-Z])(?=[A-Za-z0-9/+=]{0,200}[a-z])[A-Za-z0-9/+=]{0,200}?(?<![A-Za-z0-9+=])(?=[A-Za-z0-9+=]{0,200}[0-9])[A-Za-z0-9+=]{8,}/[A-Za-z0-9/+=]{0,200}?(?<![A-Za-z0-9+=])(?=[A-Za-z0-9+=]{0,200}[0-9])[A-Za-z0-9+=]{8,}");
'

# _g_credential_verdict <command>: prints true when the command is not to be
# sent (`risky`, or `leftover` in the masked command), false when it may be;
# returns non-zero when it could not decide. The screen hook does not use it:
# a screened gh read passes a grammar that leaves no free text but its
# endpoint, its jq path and gh's own variables, which the masking replaces,
# and a repository name or a jq path such as .user.login would otherwise keep
# the read from being screened.
_g_credential_verdict() {
  local m
  m=$(_g_mask "$1") || return 1
  jq -rn --arg t "$1" --arg m "$m" "$_G_JQ_SKIP"'($t | risky) or ($m | leftover)'
}

# _g_skip_credential <command>: 0 when the command is not sent.
# When the verdict cannot be made, nothing is sent.
_g_skip_credential() {
  local r
  r=$(_g_credential_verdict "$@" 2>/dev/null) || r=""
  [ "$r" != false ]
}

# _g_mask <text>: the text with every credential _G_JQ_MASK knows replaced by
# ***. record-quality-run.sh masks only the assignments in a command's leading
# prefix, because quality.tests-ran sends only that prefix and the test
# command; this site sends whole commands, so it masks more. The two are kept
# apart so that site's measured state does not change.
_g_mask() {
  local w
  w=$(_g_words "$1") || return 1
  jq -rn --arg w "$w" "$_G_JQ_MASK"'$w | mask'
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
# quotes, or *, ?, [...] or a brace (other than gh's {owner}, {repo} and
# {branch}) outside any quotes. Quoted text with none
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
        if (c == "*" || c == "?") { print 1; exit }
        # {a,b} and {1..3} expand, and quotes or a nested brace can hide the
        # comma, so every { counts but the {owner}, {repo} and {branch}
        # placeholders of gh, which the shell leaves alone.
        if (c == "{") {
          if (substr(s, i + 1, 6) == "owner}") { i += 6; continue }
          if (substr(s, i + 1, 5) == "repo}") { i += 5; continue }
          if (substr(s, i + 1, 7) == "branch}") { i += 7; continue }
          print 1; exit
        }
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
    # Quotes can split $( so that only the word, quotes removed, holds it,
    # and backslashes can spell it (\$\(, which bash 5 runs in test -v).
    case "$tok" in *'$('*|*'`'*|*'\$'*|*'$\('*) return 1 ;; esac
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
    # --textc), so every prefix of an option that writes or names a program
    # on the command line is sent. Programs the repository's own config
    # names (textconv, clean and smudge filters) run on plain reads too and
    # are not considered here.
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

# _g_is_get <word>: 0 when the word is GET in any case, with no process.
_g_is_get() {
  case "$1" in [Gg][Ee][Tt]) return 0 ;; esac
  return 1
}

# _g_gh_api_scan <strict> <args after `gh api`>: 0 when every option is one a
# GET read takes: -X/--method GET, --paginate and -q/--jq; without strict
# also -i/--include, --silent, --hostname and --cache. Any other option,
# bundled flags (-iXDELETE) included, returns 1. With strict the --jq filter
# must be a path. Sets _G_GH_N to the number of operands and _G_GH_EP to the
# last one.
_g_gh_api_scan() {
  local strict="$1" a prev="" path='^\.(\[[0-9]*\]|[A-Za-z_][A-Za-z0-9_]*)?(\.[A-Za-z_][A-Za-z0-9_]*|\[[0-9]*\])*$'
  shift
  _G_GH_N=0; _G_GH_EP=""
  for a in "$@"; do
    case "$prev" in
      method) prev=""; _g_is_get "$a" || return 1; continue ;;
      jq) prev=""; [ "$strict" = 1 ] && { [[ "$a" =~ $path ]] || return 1; }; continue ;;
      value) prev=""; continue ;;
    esac
    case "$a" in
      -X|--method) prev=method ;;
      -X*) _g_is_get "${a#-X}" || return 1 ;;
      --method=*) _g_is_get "${a#--method=}" || return 1 ;;
      --paginate) ;;
      -q|--jq) prev=jq ;;
      --jq=*) [ "$strict" = 1 ] && { [[ "${a#--jq=}" =~ $path ]] || return 1; } ;;
      -i|--include|--silent) [ "$strict" = 1 ] && return 1 ;;
      --hostname|--cache) [ "$strict" = 1 ] && return 1; prev=value ;;
      --hostname=*|--cache=*) [ "$strict" = 1 ] && return 1 ;;
      -*) return 1 ;;
      *) _G_GH_N=$((_G_GH_N + 1)); _G_GH_EP="$a" ;;
    esac
  done
  [ -z "$prev" ]
}

# _g_gh_get <args after `gh api`>: 0 when the call is a GET with only the
# options a read takes.
_g_gh_get() {
  _g_gh_api_scan 0 "$@"
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
  code=$(printf '%s' "$BD_CODE" | sed -E 's/[0-9]*[<>]&([0-9]+-?|-)([[:space:];|&)<>]|$)/ \2/g; s/&>>/ >> /g; s/&>/ > /g') || return 1
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
  # A command substitution anywhere is sent, wherever it stands: inside
  # double quotes, a heredoc body, or a quoted subscript the shell still
  # evaluates (test -v 'a[$(...)]'). So is any $'...' word, whose escapes
  # (\x24, \050) can spell one; _g_segment_ok also looks for one in each
  # word once quotes are removed ('a[$'"("'x)]').
  case "$1" in *'`'*|*'$('*|*"\$'"*) return 1 ;; esac
  # A line continuation can split $( in two, in a heredoc body too, where
  # the segments below never see it joined.
  case "$1" in
    *'\'$'\n'*)
      t=$(printf '%s\n' "$1" | LC_ALL=C awk 'BEGIN { BS = sprintf("%c", 92) } { s = (NR > 1) ? s "\n" $0 : $0 } END { gsub(BS BS "\n", "", s); printf "%s", s }') || return 1
      case "$t" in *'`'*|*'$('*|*"\$'"*) return 1 ;; esac ;;
  esac
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
# with only -R/--repo, -c/--comments, --json (without files or commits) and a
# --jq/-q path filter, and at most one issue or pull request, or `api` as a
# strict GET (_g_gh_api_scan 1) with exactly one endpoint that is an issues or
# pulls path of a repository, on api.github.com or $GH_HOST when it is a full
# URL. Any other option (--template, -H, --input, ...) means the read is not
# screened.
_g_gh_read_ok() {
  local a prev="" n=0 ep p h path='^\.(\[[0-9]*\]|[A-Za-z_][A-Za-z0-9_]*)?(\.[A-Za-z_][A-Za-z0-9_]*|\[[0-9]*\])*$'
  case "${1:-} ${2:-}" in
    "issue view"|"pr view")
      shift 2
      for a in "$@"; do
        case "$prev" in
          value) prev=""; continue ;;
          json) prev=""; case ",$a," in *,files,*|*,commits,*) return 1 ;; esac; continue ;;
          jq) prev=""; [[ "$a" =~ $path ]] || return 1; continue ;;
        esac
        case "$a" in
          -R|--repo) prev=value ;;
          --json) prev=json ;;
          --json=*) case ",${a#--json=}," in *,files,*|*,commits,*) return 1 ;; esac ;;
          -R?*|--repo=*|-c|--comments) ;;
          -q|--jq) prev=jq ;;
          --jq=*) [[ "${a#--jq=}" =~ $path ]] || return 1 ;;
          -*) return 1 ;;
          *) n=$((n + 1)) ;;
        esac
      done
      [ -z "$prev" ] && [ "$n" -le 1 ] ;;
    "api "*)
      shift
      _g_gh_api_scan 1 "$@" || return 1
      [ "$_G_GH_N" = 1 ] || return 1
      ep="$_G_GH_EP"
      # Characters gh or GitHub may drop or decode (#fragment, %66, ;) and an
      # empty segment could hide the path below.
      case "$ep" in *'#'*|*'%'*|*';'*) return 1 ;; esac
      p="$ep"
      case "$ep" in
        https://*)
          h="${ep#https://}"; h="${h%%/*}"
          [ "$h" = api.github.com ] || { [ -n "${GH_HOST:-}" ] && [ "$h" = "$GH_HOST" ]; } || return 1
          p="${ep#https://$h}" ;;
      esac
      # An empty segment, and any scheme other than https, holds //.
      case "$p" in *//*) return 1 ;; esac
      # Text people write, not code: a pull request's files, commits, diff or
      # patch are not screened, and neither is a path with a .. segment.
      [[ "$p" =~ (^|/)\.\.(/|$) ]] && return 1
      [[ "$p" =~ /pulls/[^/]+/(files|commits)(/|\?|$) ]] && return 1
      [[ "$p" =~ \.(diff|patch)(\?|$) ]] && return 1
      [[ "$p" =~ ^/?repos/[^/]+/[^/]+/(issues|pulls)(/|\?|$) ]] ;;
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
  local seg reads=0 segs=0 k t skip
  local -a TOK=() ARGS=() B=()
  _g_segments "$1" || return 1
  while IFS= read -r seg; do
    [[ $seg == *[![:space:]]* ]] || continue
    segs=$((segs + 1))
    [ "$segs" -le "$_G_MAX_SEGS" ] || return 1
    # A redirection from or to /dev/null, /dev/stdout or /dev/stderr is
    # dropped, word by word; any other redirection (2>out, <notes.txt, a
    # here-string), and any other word holding < or >, means the read is not
    # screened.
    TOK=(); _rm_tokenise "$seg"
    ARGS=(); skip=0
    for t in "${TOK[@]+"${TOK[@]}"}"; do
      if [ "$skip" = 1 ]; then
        skip=0
        case "$t" in /dev/null|/dev/stdout|/dev/stderr) continue ;; *) return 1 ;; esac
      fi
      case "$t" in
        [0-9]'>'*|[0-9][0-9]'>'*|'>'*|'<'*)
          case "$t" in *'>'|*'<') skip=1; continue ;; esac
          case "${t##*[<>]}" in /dev/null|/dev/stdout|/dev/stderr) continue ;; *) return 1 ;; esac ;;
        *'<'*|*'>'*) return 1 ;;
      esac
      ARGS+=("$t")
    done
    [ "$skip" = 0 ] || return 1
    [ "${#ARGS[@]}" -gt 0 ] || continue
    # cd prints a directory with - and when CDPATH finds a relative name,
    # and that would join the text screened; cd alone, or to an absolute,
    # ~ or ./ path, prints nothing.
    if [ "${ARGS[0]}" = cd ]; then
      [ "${#ARGS[@]}" -le 2 ] || return 1
      [ "${#ARGS[@]}" = 1 ] && continue
      case "${ARGS[1]}" in /*|'~'|'~/'*|.|..|./*|../*) continue ;; *) return 1 ;; esac
    fi
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

# _g_jq_field <command>: 0 when the last jq filter of the gh read (its
# --jq/-q, or a pipe into jq) is a path that ends in a field (.body,
# .[].body): the output is then the text of that field. 1 when there is none,
# or it ends otherwise (., .[], .[0]), so the output is still gh's JSON. 0 when
# the command cannot be split, so nothing is dropped.
_g_jq_field() {
  local seg t prev="" last=""
  local -a TOK=()
  _g_segments "$1" || return 0
  while IFS= read -r seg; do
    [[ $seg == *[![:space:]]* ]] || continue
    TOK=(); _rm_tokenise "$seg"
    [ "${#TOK[@]}" -gt 0 ] || continue
    if [ "${TOK[0]##*/}" = jq ]; then
      for t in "${TOK[@]:1}"; do case "$t" in -*) ;; *) last="$t" ;; esac; done
      continue
    fi
    for t in "${TOK[@]}"; do
      if [ "$prev" = 1 ]; then last="$t"; prev=""; continue; fi
      case "$t" in -q|--jq) prev=1 ;; --jq=*) last="${t#--jq=}" ;; esac
    done
  done <<<"$_G_SEGS"
  [[ $last =~ [A-Za-z0-9_]$ ]]
}

# _g_text_state <command>: from the hook payload on stdin. The output is
# first cut to its first and last 30,000 characters when it is longer than
# 60,000 (Claude Code passes at most 30,000 to the hook as of 2.1.296; the cut
# bounds the work if that changes), and the whole word at each cut is dropped,
# so a credential the cut splits is not sent in part. Output that parses as JSON,
# as one document or one per line, is then sent as every string in it, the
# titles and bodies first and each string once, without diff hunks and
# patches (code, not text people write). Output a jq path to a field
# printed (--jq .body, | jq -r '.[].body') is sent as its lines, since it is
# the text of that field, such as an issue body that may itself be JSON. So is
# output that is not JSON.
# Empty lines are dropped; each line is masked by `shapes`, a line over 1000
# characters is split into pieces of 1000, and consecutive lines are joined
# with newlines into pieces of up to 1000 characters. Nothing else is cut: the
# cut above already bounds the text. "truncated": true says the cut happened.
_g_text_state() {
  local masked raw=false
  masked=$(_g_mask "$1") || return 1
  _g_jq_field "$1" && raw=true
  jq -c --arg cmd "${masked:0:2000}" --argjson raw "$raw" "$_G_JQ_SHAPES"'
    def lines: (if endswith("\n") then .[:-1] else . end)
      | if . == "" then [] else split("\n") end;
    def docs: (try fromjson catch null) as $one
      | if ($one | type) == "object" or ($one | type) == "array" then [$one]
        else [lines[] | select(test("\\S"))] as $ls
          | [$ls[] | (try fromjson catch null) | select(type == "object" or type == "array")] as $ds
          | if ($ls | length) > 0 and ($ds | length) == ($ls | length) then $ds else null end
        end;
    def texts: walk(if type == "object" then del(.diff_hunk, .patch) else . end)
      | ([.. | objects | (.title?, .body?) | strings] + [.. | strings])
      | reduce .[] as $x ({}; .[$x] = true) | keys_unsorted;
    def pieces: if length <= 1000 then [.] else [match("[\\s\\S]{1,1000}"; "g").string] end;
    def pack: reduce .[] as $p ([];
      if length > 0 and ((.[-1] | length) + 1 + ($p | length)) <= 1000 then .[-1] += "\n" + $p else . + [$p] end);
    def endword: ([match("\\s"; "g").offset] | last) as $k | if $k == null then "" else .[:$k + 1] end;
    def startword: ([match("\\s")][0].offset) as $k | if $k == null then "" else .[$k:] end;
    (.tool_response.stdout | if type == "string" then . else "" end) as $s
    | ($s | length > 60000) as $cut
    | (if $cut then ($s[:30000] | endword) + "\n" + ($s[-30000:] | startword) else $s end) as $s0
    | (if $raw then null else ($s0 | docs) end) as $ds
    | (if $ds then ($ds | texts | join("\n")) else $s0 end) as $t
    | [$t | lines[] | select(length > 0) | shapes | pieces[]] | pack
    | {command: $cmd, output: .} + (if $cut then {truncated: true} else {} end)'
}

# _g_budget_ms: how long, in milliseconds, a client call the hook waits for
# may take: hooks.json stops the hook after 35 s, and the client needs a few
# seconds of that to start and to write its record, so the call gets what is
# left of 29 s since the hook started. Prints nothing and returns 1 when no
# time is left.
_g_budget_ms() {
  local left=$(( (29 - SECONDS) * 1000 ))
  [ "$left" -gt 0 ] || return 1
  printf '%s' "$left"
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
