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
#   _g_mask_read <command>         the gh read with assignment values, URL
#                                  user:password and credential-shaped values
#                                  replaced by ***
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

# _G_JQ_READ: jq definitions. `readmask` is what _g_mask_read applies to a
# command _g_gh_read accepted. That grammar leaves no free text but the
# values of leading assignments (gh's token variables among them), the
# operands (an issue number or URL, the endpoint), -R, --json fields and jq
# paths, and no word the shell rewrites. So the value of every NAME=value
# word, quoted or not, and user:password@ in a URL are replaced, and then
# `shapes` above.
_G_JQ_READ=$_G_JQ_SHAPES'
def readmask:
  gsub("(?<o>(?:^|[\\s;|&(])[A-Za-z_][A-Za-z0-9_]*=)(?:\u0027[^\u0027]*\u0027|\"[^\"]*\"|[^\\s\u0027\";|&()<>])+"; "\(.o)***")
  | gsub("(?<s>[A-Za-z][A-Za-z0-9+.-]{0,30}://)[^/\\s@\u0027\"]+@"; "\(.s)***@")
  | shapes;
'

# _g_mask_read <command>: the command with readmask applied.
_g_mask_read() {
  jq -rn --arg c "$1" "$_G_JQ_READ"'$c | readmask'
}

# Assignments that cannot change which program runs or what it runs.
_G_SAFE_VARS=" LC_ALL LANG LANGUAGE TZ NO_COLOR TERM COLUMNS LINES "

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

# _g_is_get <word>: 0 when the word is GET in any case, with no process.
_g_is_get() {
  case "$1" in [Gg][Ee][Tt]) return 0 ;; esac
  return 1
}

# _g_gh_api_scan <args after `gh api`>: 0 when every option is one a GET read
# of text takes: -X/--method GET, --paginate and a -q/--jq path filter. Any
# other option, bundled flags (-iXDELETE) included, returns 1. Sets _G_GH_N to
# the number of operands and _G_GH_EP to the last one.
_g_gh_api_scan() {
  local a prev="" path='^\.(\[[0-9]*\]|[A-Za-z_][A-Za-z0-9_]*)?(\.[A-Za-z_][A-Za-z0-9_]*|\[[0-9]*\])*$'
  _G_GH_N=0; _G_GH_EP=""
  for a in "$@"; do
    case "$prev" in
      method) prev=""; _g_is_get "$a" || return 1; continue ;;
      jq) prev=""; [[ "$a" =~ $path ]] || return 1; continue ;;
    esac
    case "$a" in
      -X|--method) prev=method ;;
      -X*) _g_is_get "${a#-X}" || return 1 ;;
      --method=*) _g_is_get "${a#--method=}" || return 1 ;;
      --paginate) ;;
      -q|--jq) prev=jq ;;
      --jq=*) [[ "${a#--jq=}" =~ $path ]] || return 1 ;;
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

# _G_MAX_SEGS: a command of more simple commands than this is not screened:
# each check starts processes, and the length cap alone does not bound their
# number.
_G_MAX_SEGS=64

# _g_continued <command>: 0 when more than 64 lines of it end in a backslash.
# The shared parser rescans each continued line with all the text before it,
# so such a command would hold it for tens of seconds; it is not screened.
_g_continued() {
  [ "$(printf '%s\n' "$1" | grep -c '\\$')" -gt 64 ]
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
# GET (_g_gh_api_scan) with exactly one endpoint that is an issues or
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
      _g_gh_api_scan "$@" || return 1
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
  _g_continued "$1" && return 1
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
    # ~, ., .., ./ or ../ path, prints nothing.
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
# into pieces of up to 1000 characters, so short lines do not multiply the
# items the client must fit under its token cap. Nothing else is cut: the
# cut above already bounds the text. "truncated": true says the cut happened.
_g_text_state() {
  local masked raw=false
  masked=$(_g_mask_read "$1") || return 1
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
