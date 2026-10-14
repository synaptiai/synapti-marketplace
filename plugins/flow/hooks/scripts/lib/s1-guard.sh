#!/usr/bin/env bash
# plugins/flow/hooks/scripts/lib/s1-guard.sh
#
# Used by the System One hook s1-screen-text.sh (site
# guard.planted-instructions) and by the measurement in
# evals/results-2026-10-12-s1-guard, so the state measured is the state the
# hook sends. Sources lib/command-parse.sh.
#
#   _g_gh_read <command>           0 when the command is one gh read of issue
#                                  or pull request text
#   _g_jq_field <command>          0 when the gh read's last jq filter is a
#                                  path that ends in a field
#   _g_text_state <command>        the guard.planted-instructions state, one
#                                  JSON line, from the hook payload on stdin
#   _g_detach <file> <cmd...>      run cmd in a new session with stdin, stdout
#                                  and stderr on /dev/null, remove <file> when
#                                  it ends, and return at once

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
# is the only rule applied to the output of a screened gh read, the only part
# of it that is sent: rules keyed on a name ("api-key: ...") would also hide
# the text that follows the name, and with it a planted instruction.
_G_JQ_SHAPES='
def shapes:
  gsub("(?<![A-Za-z0-9_-])(?:gh[pousr]_[A-Za-z0-9]{10,255}|github_pat_[A-Za-z0-9_]{10,255}|sk-[A-Za-z0-9_-]{16,255}|xox[abprs]-[A-Za-z0-9-]{10,255}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|dop_v1_[a-f0-9]{20,255}|shpat_[a-f0-9]{20,255}|glpat-[A-Za-z0-9_-]{10,255}|AIza[0-9A-Za-z_-]{20,255}|eyJ[A-Za-z0-9_-]{4,4096}\\.[A-Za-z0-9_-]{4,4096}\\.[A-Za-z0-9_-]{4,4096})"; "***")
  | gsub("(?<![A-Za-z0-9_+=-])(?=[A-Za-z0-9_+=-]*[A-Za-z])(?=[A-Za-z0-9_+=-]*[0-9])[A-Za-z0-9_+=-]{513,}"; "***")
  | gsub("(?<![A-Za-z0-9_+=-])(?=[A-Za-z0-9_+=-]{0,511}[A-Z])(?=[A-Za-z0-9_+=-]{0,511}[a-z])(?=[A-Za-z0-9_+=-]{0,511}[0-9])[A-Za-z0-9_+=-]{20,512}(?![A-Za-z0-9_+=-])"; "***")
  | gsub("(?<![A-Za-z0-9/+=])(?=[A-Za-z0-9/+]{0,39}[A-Z])(?=[A-Za-z0-9/+]{0,39}[a-z])(?=[A-Za-z0-9/+]{0,39}[0-9])[A-Za-z0-9+][A-Za-z0-9/+]{39}(?![A-Za-z0-9/+=])"; "***");
'

# Assignments that cannot change which program runs or what it runs.
_G_SAFE_VARS=" LC_ALL LANG LANGUAGE TZ NO_COLOR TERM COLUMNS LINES "

# _g_not_plain <command>: 0 when the shell would read some word of the command
# other than as written, or when the check fails: a backslash, $ or a backtick
# outside single quotes; *, ?, # or [...] outside any quotes; a brace; a quote
# that does not open its word, or open it right after NAME= or --option=, and
# close it; a quoted word that begins NAME=; a quote left open; or &, >& or <&
# outside quotes. A # can start a comment the parser drops, while zsh can read
# it as part of a glob (/(#|tmp)) and run what follows; 2>&1, |& and &> send
# stderr into the output; and a trailing & turns a failed read into a success.
# No gh read needs any of these.
_g_not_plain() {
  local r
  r=$(printf '%s\n' "$1" | LC_ALL=C awk '
    BEGIN { SQ = sprintf("%c", 39); DQ = sprintf("%c", 34); BS = sprintf("%c", 92) }
    { s = (NR > 1) ? s "\n" $0 : $0 }
    END {
      q = ""; n = length(s); ob = 0; pre = ""; shut = 0
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (q == SQ) { if (c == SQ) { q = ""; shut = 1 }; continue }
        if (c == BS || c == "$" || c == "`") { print 1; exit }
        if (q == DQ) { if (c == DQ) { q = ""; shut = 1 }; continue }
        two = substr(s, i, 2)
        if (c == "&" || two == ">&" || two == "<&") { print 1; exit }
        if (c == " " || c == "\t" || c == "\n" || index(";&|()<>", c)) { ob = 0; pre = ""; shut = 0; continue }
        # Nothing may follow a closing quote in the same word.
        if (shut) { print 1; exit }
        if (c == SQ || c == DQ) {
          if (pre != "" && pre !~ /^([A-Za-z_][A-Za-z0-9_]*|--[A-Za-z][A-Za-z0-9-]*)=$/) { print 1; exit }
          # A quoted NAME=value is not an assignment to the shell, which runs
          # it as a program; the grammar would read it as one.
          if (pre == "" && substr(s, i + 1) ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { print 1; exit }
          q = c; continue
        }
        if (c == "#" || c == "*" || c == "?") { print 1; exit }
        # {a,b} and {1..3} expand, and quotes or a nested brace can hide the
        # comma, so every { counts; the gh placeholders such as {owner} are
        # refused with the rest, since gh fills them unescaped.
        if (c == "{") { print 1; exit }
        # [...] in one word: remember an open [ until the word ends.
        if (c == "[") ob = 1
        else if (c == "]" && ob) { print 1; exit }
        pre = pre c
      }
      print (q == "") ? 0 : 1
    }' 2>/dev/null)
  [ "$r" != 0 ]
}

# _g_system_prog <word>: 0 when the word names a program by its bare name or
# from a system directory: ./gh or /tmp/x/gh can do anything.
_g_system_prog() {
  case "$1" in
    */*) case "${1%/*}" in /bin|/usr/bin|/usr/local/bin|/opt/homebrew/bin) return 0 ;; *) return 1 ;; esac ;;
  esac
  return 0
}

# _g_is_get <word>: 0 when the word is GET in any case, with no process.
_g_is_get() {
  case "$1" in [Gg][Ee][Tt]) return 0 ;; esac
  return 1
}

# _g_jq_ok <filter>: 0 for a jq path filter (.body, .[].body,
# .comments[].body, ., .[0]) whose last field, if it ends in one, is body or
# title. Such output is sent as its lines, so a path ending in any other
# field (diff_hunk, user.email) would send code or account data as text.
_g_jq_ok() {
  local path='^\.(\[[0-9]*\]|[A-Za-z_][A-Za-z0-9_]*)?(\.[A-Za-z_][A-Za-z0-9_]*|\[[0-9]*\])*$'
  [[ "$1" =~ $path ]] || return 1
  [[ "$1" =~ [A-Za-z0-9_]$ ]] || return 0
  [[ "$1" =~ (^|[.])(body|title)$ ]]
}

# _g_gh_api_scan <args after `gh api`>: 0 when every option is one a GET read
# of text takes: -X/--method GET, --paginate and a -q/--jq path filter. Any
# other option, bundled flags (-iXDELETE) included, returns 1. Sets _G_GH_N to
# the number of operands and _G_GH_EP to the last one.
_g_gh_api_scan() {
  local a prev=""
  _G_GH_N=0; _G_GH_EP=""
  for a in "$@"; do
    case "$prev" in
      method) prev=""; _g_is_get "$a" || return 1; continue ;;
      jq) prev=""; _g_jq_ok "$a" || return 1; continue ;;
    esac
    case "$a" in
      -X|--method) prev=method ;;
      -X*) _g_is_get "${a#-X}" || return 1 ;;
      --method=*) _g_is_get "${a#--method=}" || return 1 ;;
      --paginate) ;;
      -q|--jq) prev=jq ;;
      --jq=*) _g_jq_ok "${a#--jq=}" || return 1 ;;
      -*) return 1 ;;
      *) _G_GH_N=$((_G_GH_N + 1)); _G_GH_EP="$a" ;;
    esac
  done
  [ -z "$prev" ]
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

# _g_continued <command>: 0 when more than 64 lines of it end in a backslash.
# The shared parser rescans each continued line with all the text before it,
# so such a command would hold it for tens of seconds; it is not screened.
_g_continued() {
  [ "$(printf '%s\n' "$1" | grep -c '\\$')" -gt 64 ]
}

# _g_json_ok <fields>: 0 when the --json value is a comma-separated list of
# field names, without files or commits (code, not text people write).
_g_json_ok() {
  [[ "$1" =~ ^[A-Za-z]+(,[A-Za-z]+)*$ ]] || return 1
  case ",$1," in *,files,*|*,commits,*) return 1 ;; esac
}

# _g_host_ok <host>: 0 for github.com, api.github.com, or the GH_HOST the
# hook itself runs with. A read sent to another host could print whatever
# that server returns, and gh would send it the Enterprise token.
_g_host_ok() {
  case "$1" in github.com|api.github.com) return 0 ;; esac
  [ -n "${GH_HOST:-}" ] && [ "$1" = "$GH_HOST" ]
}

# The forms below are the only ones accepted: a list of what is refused
# missed a new spelling in every review round (gh's :owner placeholder,
# git@host:o/r), so what is not on this list is not screened.
#
# _g_segs_ok <path>: 0 when every /-separated segment is a plain name:
# letters, digits, ., _ and -, and neither . nor .. (no %, :, @, {, ? or an
# empty segment).
_g_segs_ok() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]] || return 1
  case "/$1/" in *"/./"*|*"/../"*) return 1 ;; esac
}

# _g_url_ok <url>: 0 for https://HOST/<plain segments>, with a host
# _g_host_ok accepts.
_g_url_ok() {
  local h rest
  case "$1" in https://*/*) ;; *) return 1 ;; esac
  h="${1#https://}"; rest="${h#*/}"; h="${h%%/*}"
  _g_host_ok "$h" && _g_segs_ok "${rest%/}"
}

# _g_repo_ok <value>: 0 when a -R or GH_REPO value is OWNER/REPO,
# HOST/OWNER/REPO with a host _g_host_ok accepts, or such a URL.
_g_repo_ok() {
  case "$1" in https://*) _g_url_ok "$1"; return ;; esac
  _g_segs_ok "$1" || return 1
  case "$1" in
    */*/*/*) return 1 ;;
    */*/*) _g_host_ok "${1%%/*}" ;;
    */*) return 0 ;;
    *) return 1 ;;
  esac
}

# _g_operand_ok <value>: 0 for the issue or pull request an issue view or pr
# view names: a number, a branch of plain segments, or a URL _g_url_ok
# accepts.
_g_operand_ok() {
  case "$1" in https://*) _g_url_ok "$1"; return ;; esac
  [[ "$1" =~ ^[0-9]+$ ]] || _g_segs_ok "$1"
}

# _g_gh_read_ok <args after gh>: 0 when they are `issue view` or `pr view`
# with only -R/--repo, -c/--comments, --json (field names, not files or
# commits) and a --jq/-q path filter, and at most one issue or pull request,
# with -R and the operand in the forms _g_repo_ok and _g_operand_ok accept; or
# `api` as a GET (_g_gh_api_scan) with exactly one endpoint that is an issues
# or pulls path of a repository in plain segments, on api.github.com or
# $GH_HOST when it is a full URL. Any other option (--template, -H, --input,
# ...) means the read is not screened.
_g_gh_read_ok() {
  local a prev="" n=0 ep p h q qre='^[A-Za-z0-9_.,=&-]*$'
  case "${1:-} ${2:-}" in
    "issue view"|"pr view")
      shift 2
      for a in "$@"; do
        case "$prev" in
          value) prev=""; _g_repo_ok "$a" || return 1; continue ;;
          json) prev=""; _g_json_ok "$a" || return 1; continue ;;
          jq) prev=""; _g_jq_ok "$a" || return 1; continue ;;
        esac
        case "$a" in
          -R|--repo) prev=value ;;
          --json) prev=json ;;
          --json=*) _g_json_ok "${a#--json=}" || return 1 ;;
          -R?*) _g_repo_ok "${a#-R}" || return 1 ;;
          --repo=*) _g_repo_ok "${a#--repo=}" || return 1 ;;
          -c|--comments) ;;
          -q|--jq) prev=jq ;;
          --jq=*) _g_jq_ok "${a#--jq=}" || return 1 ;;
          -*) return 1 ;;
          *) n=$((n + 1)); _g_operand_ok "$a" || return 1 ;;
        esac
      done
      [ -z "$prev" ] && [ "$n" -le 1 ] ;;
    "api "*)
      shift
      _g_gh_api_scan "$@" || return 1
      [ "$_G_GH_N" = 1 ] || return 1
      ep="$_G_GH_EP"
      p="$ep"
      case "$ep" in
        https://*)
          h="${ep#https://}"; h="${h%%/*}"
          [ "$h" = api.github.com ] || { [ -n "${GH_HOST:-}" ] && [ "$h" = "$GH_HOST" ]; } || return 1
          p="${ep#https://$h}"
          [ "$h" = api.github.com ] || p="${p#/api/v3}" ;;
      esac
      # The path is repos/OWNER/REPO/issues or pulls and plain segments,
      # with at most a query of names, values, commas and &. gh fills
      # {owner}, :owner and the like from the git remote or GH_REPO without
      # escaping, so a remote such as github.com/../user%3F could otherwise
      # turn the path into a read of another endpoint; plain segments leave
      # no placeholder, %, .. or empty segment.
      q=""
      case "$p" in *'?'*) q="${p#*\?}"; p="${p%%\?*}" ;; esac
      [[ "$q" =~ $qre ]] || return 1
      p="${p#/}"
      _g_segs_ok "$p" || return 1
      # Only issues, pull requests, their comments and their reviews: text
      # people write. A timeline or events list holds commit emails and other
      # repositories' issues, and files, commits and diffs are code.
      [[ "$p" =~ ^repos/[^/]+/[^/]+/(issues(/comments)?(/[0-9]+)?|issues/[0-9]+/comments|pulls(/comments)?(/[0-9]+)?|pulls/[0-9]+/(comments|reviews(/[0-9]+(/comments)?)?))$ ]] ;;
    *) return 1 ;;
  esac
}

# _g_gh_read <command>: 0 when the command is one gh read of issue or pull
# request text (_g_gh_read_ok) and nothing else: one simple command, gh named
# bare or from a system directory, with only harmless variables and gh's own
# (the token variables, GH_HOST for a host _g_host_ok accepts, and GH_REPO in
# a form _g_repo_ok accepts) set before it. Claude Code passes a command's
# stderr to the hook inside stdout, and a pipe (| head) makes a failed read a
# success, so gh's error messages, which repeat words of the command, would be
# screened as its output; a read alone that fails fires PostToolUseFailure,
# which the hook ignores (Claude Code 2.1.299, checked 2026-10-14). A cd
# before it, a pipe after it, or any other command is not screened.
_g_gh_read() {
  local seg reads=0 segs=0 k t skip
  local -a TOK=() ARGS=() B=()
  _g_continued "$1" && return 1
  # Every word must reach the shell's programs as the grammar below reads
  # it: a word the shell rewrites ($'--jq=env', \--jq, ${X:--jq}) could
  # become an option the grammar refuses, and a comment could hide a command.
  # The whole command is checked.
  _g_not_plain "$1" && return 1
  _g_segments "$1" || return 1
  while IFS= read -r seg; do
    [[ $seg == *[![:space:]]* ]] || continue
    segs=$((segs + 1))
    [ "$segs" = 1 ] || return 1
    # A redirection from or to /dev/null or /dev/stderr is dropped, word by
    # word; any other redirection (2>out, <notes.txt, 2>/dev/stdout, a
    # here-string), and any other word holding < or >, means the read is not
    # screened.
    TOK=(); _rm_tokenise "$seg"
    ARGS=(); skip=0
    for t in "${TOK[@]+"${TOK[@]}"}"; do
      if [ "$skip" = 1 ]; then
        skip=0
        case "$t" in /dev/null|/dev/stderr) continue ;; *) return 1 ;; esac
      fi
      # No read of issue text needs a URL with a user part, a quote
      # character within a word ("a'b"), or a space in a word holding ? or #.
      [[ "$t" =~ ://[^/]*@ ]] && return 1
      case "$t" in *[\'\"]*|*[?#]*[[:space:]]*|*[[:space:]]*[?#]*) return 1 ;; esac
      case "$t" in
        [0-9]'>'*|[0-9][0-9]'>'*|'>'*|'<'*)
          case "$t" in *'>'|*'<') skip=1; continue ;; esac
          case "${t##*[<>]}" in /dev/null|/dev/stderr) continue ;; *) return 1 ;; esac ;;
        *'<'*|*'>'*) return 1 ;;
      esac
      ARGS+=("$t")
    done
    [ "$skip" = 0 ] || return 1
    [ "${#ARGS[@]}" -gt 0 ] || continue
    k=0
    while [ "$k" -lt "${#ARGS[@]}" ] && [[ "${ARGS[k]}" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; do
      case "${BASH_REMATCH[1]}" in
        GH_HOST) _g_host_ok "${ARGS[k]#GH_HOST=}" || return 1 ;;
        GH_REPO) _g_repo_ok "${ARGS[k]#GH_REPO=}" || return 1 ;;
        LC_*|GH_TOKEN|GITHUB_TOKEN|GH_ENTERPRISE_TOKEN) ;;
        *) case "$_G_SAFE_VARS" in *" ${BASH_REMATCH[1]} "*) ;; *) return 1 ;; esac ;;
      esac
      k=$((k + 1))
    done
    [ "$k" -lt "${#ARGS[@]}" ] || return 1
    B=("${ARGS[@]:k}")
    # rtk's own PreToolUse hook rewrites gh issue view to rtk gh issue view
    # (or rtk proxy gh ...), and PostToolUse receives the rewritten command:
    # the output is then what rtk printed of the read, which is what the
    # agent reads (Claude Code 2.1.296, rtk 0.51.0).
    if [ "${B[0]##*/}" = rtk ] && _g_system_prog "${B[0]}"; then
      if [ "${B[1]:-}" = proxy ]; then B=("${B[@]:2}"); else B=("${B[@]:1}"); fi
      [ "${#B[@]}" -gt 0 ] && [ "${B[0]}" = gh ] || return 1
    fi
    if [ "${B[0]##*/}" = gh ]; then
      _g_system_prog "${B[0]}" || return 1
      _g_gh_read_ok "${B[@]:1}" || return 1
      reads=$((reads + 1))
      continue
    fi
    return 1
  done <<<"$_G_SEGS"
  [ "$reads" = 1 ]
}

# _g_ref_ok <ref>: the shape flow-s1.sh accepts for --ref, in the C locale so
# the ranges are ASCII only; a ref of another shape loses the record.
_g_ref_ok() {
  local LC_ALL=C
  [ "${#1}" -le 200 ] && [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._:/#@+-]*$ ]]
}

# _g_jq_field <command>: 0 when the gh read's last --jq/-q filter is a path
# that ends in a field (.body, .[].body): the output is then the text of that
# field. 1 when there is none, or it ends otherwise (., .[], .[0]), so the
# output is still gh's JSON. 0 when the command cannot be split, so nothing is
# dropped.
_g_jq_field() {
  local seg t prev="" last=""
  local -a TOK=()
  _g_segments "$1" || return 0
  while IFS= read -r seg; do
    [[ $seg == *[![:space:]]* ]] || continue
    TOK=(); _rm_tokenise "$seg"
    for t in "${TOK[@]+"${TOK[@]}"}"; do
      if [ "$prev" = 1 ]; then last="$t"; prev=""; continue; fi
      case "$t" in -q|--jq) prev=1 ;; --jq=*) last="${t#--jq=}" ;; esac
    done
  done <<<"$_G_SEGS"
  [[ $last =~ [A-Za-z0-9_]$ ]]
}

# _g_text_state <command>: from the hook payload on stdin. The state holds the
# output only; the command is not sent. The output is first cut to its first
# and last 30,000 characters when it is longer than 60,000 (Claude Code passes
# at most 30,000 to the hook as of 2.1.296; the cut bounds the work if that
# changes), and the whole word at each cut is dropped, so a credential the cut
# splits is not sent in part. Output that parses as JSON, as one document or
# one per line, is then sent as its title and body strings, each once: other
# fields (logins, emails, diff hunks) are not text people wrote. Output that
# starts like JSON but does not parse, as when a cut shortens a listing, is
# not screened, and neither is JSON with no title or body. Output a jq path to
# body or title printed (--jq .body, --jq '.[].body') is sent as its lines,
# since it is the text of that field, such as an issue body that may itself be
# JSON. So is output that is not JSON. Empty lines are dropped; each line is
# masked by `shapes`, a line over 1000 characters is split into pieces of
# 1000, and consecutive lines are joined into pieces of up to 1000 characters,
# so short lines do not multiply the items the client must fit under its token
# cap. Nothing else is cut: the cut above already bounds the text.
# "truncated": true says the cut happened.
_g_text_state() {
  local raw=false
  _g_jq_field "$1" && raw=true
  jq -c --argjson raw "$raw" "$_G_JQ_SHAPES"'
    def lines: (if endswith("\n") then .[:-1] else . end)
      | if . == "" then [] else split("\n") end;
    def docs: (try fromjson catch null) as $one
      | if ($one | type) == "object" or ($one | type) == "array" then [$one]
        else [lines[] | select(test("\\S"))] as $ls
          | [$ls[] | (try fromjson catch null) | select(type == "object" or type == "array")] as $ds
          | if ($ls | length) > 0 and ($ds | length) == ($ls | length) then $ds else null end
        end;
    def texts: [.. | objects | (.title?, .body?) | strings]
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
    | if ($raw | not) and $ds == null and ($s0 | test("\\A\\s*[\\[{]")) then empty
      else
        (if $ds then ($ds | texts | join("\n")) else $s0 end) as $t
        | [$t | lines[] | select(length > 0) | shapes | pieces[]] | pack
        | if length == 0 then empty else {output: .} + (if $cut then {truncated: true} else {} end) end
      end'
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
