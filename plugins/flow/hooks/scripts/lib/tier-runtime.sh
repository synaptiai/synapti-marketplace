# shellcheck shell=bash
# [flow] lib/tier-runtime.sh — the run-time half of the tier check, sourced by
# hooks/shims/git and hooks/shims/gh.
#
# tier-session-start.sh puts hooks/shims first on PATH for the Bash commands
# of a Claude Code session and sets FLOW_TIER_DIR. Every git or gh that a
# command runs by name then starts here, with the arguments the program will
# get: the shell has already expanded variables, substitutions, quotes,
# eval, pipes into a shell and every other construct the text check
# (tier-gate.sh) has to read from the command's text. This file decides
# from those arguments which tier action the program is about to do:
#
#   git push       push, or release when it sends or deletes a tag. What a
#                  push sends is asked of git itself: `git push` with the
#                  same arguments and `--dry-run --porcelain --no-verify`
#                  after them (before any `--`, so no option of the
#                  command's cancels them) lists every ref it would update,
#                  tags followed by --follow-tags, push.followTags, --mirror
#                  or the remote's push refspecs included. This runs for a
#                  dry run too. A push whose every destination is a path on
#                  this machine (a local bare repository) leaves nothing on
#                  the network and is not a tier action. A push whose refs
#                  cannot be listed (the dry run fails) is treated as a
#                  possible tag push.
#   git with an option before the subcommand this file does not know, and
#                  a push among its words: a possible tag push.
#   git send-pack, git http-push                    release (a push git does
#                  not describe in a dry run here)
#   git submodule, rebase, bisect, filter-branch, difftool, mergetool
#                  with an argument mentioning push: release. git runs these
#                  commands with its own directory first on PATH, so a git
#                  push inside them does not reach this wrapper.
#   git <alias>    the alias's expansion, read as git reads it (with the
#                  command's -c settings, quotes removed). An alias that
#                  runs a shell command (`!...`), or one whose expansion
#                  cannot be read, is release when it or the arguments
#                  after it mention push.
#   gh pr merge                                     merge
#   gh pr create / new                              prCreate
#   gh issue create / new                           issueCreate
#   gh issue edit --add-assignee                    issueAssign
#   gh release create, new, edit, delete, upload, delete-asset   release
#   gh api         by method and endpoint (a #fragment or ?query left out,
#                  as gh sends it), as tier-gate.sh's header lists them; a
#                  GraphQL document is read for its mutation fields. A query
#                  or body that is not a regular file (stdin, a FIFO,
#                  /dev/fd/N) is not read here, so gh still gets it whole,
#                  and is a possible merge or release.
#   gh <alias>     any first word other than pr, issue, release and api is
#                  looked up in gh's aliases; an alias is expanded as gh
#                  expands it ($1, $2... replaced by the arguments, the rest
#                  appended). A shell alias that mentions merge, release or
#                  push is a possible merge or release.
#
# What happens then follows the tier setting, read where the command runs:
#
#   confirm (merge and release always)
#       The command runs only when tier-gate.sh asked about that action for
#       this Bash call, and so the person approved it, and only as many
#       times as the gate saw it in the command (a merge approved once
#       approves one merge). tier-gate.sh writes a record for the call: a
#       directory <FLOW_TIER_DIR>/pending.<time>.<pid> holding the command
#       (cmdq: the text Claude Code puts inside `eval '...'`), the
#       actions it asked about with their counts (asked: "<key> <n>", or
#       "<key> *" when the gate could not count them), the ones it journaled
#       (journaled) and the tags whose `gh release create --verify-tag` it
#       journaled (verified). The line the session start hook adds to
#       CLAUDE_ENV_FILE moves the record whose command this shell was
#       started with to call.<pid> (FLOW_TIER_CALL) before the command
#       starts; a record whose command is another call's stays where it is.
#       Otherwise the program is not run: one message on stderr says why
#       and how to run the action so that flow can ask, and the exit status
#       is 1. A gh release create --verify-tag of a tag the gate journaled
#       runs without an ask.
#   journal
#       When tier-gate.sh did not already write the breadcrumb for it, one is
#       written to the auto-log trail, marked "runtime", and the program runs.
#   autonomous
#       The program runs.
#
# Without FLOW_TIER_DIR or FLOW_TIER_CALL (a command that unsets them, or a
# shell where flow's session start line did not run) nothing was approved:
# merge, release and actions set to confirm are refused, and journaling
# works as above.
#
# Not covered: a program other than git and gh that pushes, merges or
# releases (curl or a script calling GitHub's API, a gh extension, hub);
# git or gh run by a path rather than by name (`/usr/bin/git push --tags`),
# or with a PATH that leaves out flow's wrapper directory; and commands git
# runs itself (hooks, `!` aliases, external git-* programs such as
# git-flow), whose git push uses git's own copy. tier-gate.sh still reads
# the command text of each of these.

_tr_note() { printf 'flow: tier check — %s\n' "$1" >&2; }

# The first <prog> on PATH that is not in a wrapper directory: this one, or
# another flow's (a nested session, an older version), which would run this
# one again.
_tr_real() {   # $1 = git or gh
  local d p IFS=:
  set -f
  for d in $PATH; do
    [ -n "$d" ] || d=.
    [ "$d" = "$_TR_SHIMS" ] && continue
    if [ -f "$d/$1" ] && [ -x "$d/$1" ]; then
      p=$(cd "$d" 2>/dev/null && pwd -P) || p=""
      [ "$p" = "$_TR_SHIMS" ] && continue
      [ -f "$d/../scripts/lib/tier-runtime.sh" ] && continue
      set +f
      printf '%s\n' "$d/$1"
      return 0
    fi
  done
  set +f
  return 1
}

# Record an action: $1 = tier key, $2 = what was seen.
_tr_add() {
  case " $_TR_KEYS " in *" $1 "*) ;; *) _TR_KEYS="$_TR_KEYS $1" ;; esac
  [ -n "$_TR_WHAT" ] || _TR_WHAT="$2"
}

# A remote URL that is a path on this machine: file://, an absolute or
# relative path, or anything without a colon before its first slash (git's
# rule for telling host:path from a path).
_tr_is_local_url() {   # $1 = the URL git printed after "To "
  case "$1" in
    file://*|/*|./*|../*) return 0 ;;
    *::*|*://*) return 1 ;;
  esac
  case "${1%%/*}" in *:*) return 1 ;; esac
  return 0
}

# --- git --------------------------------------------------------------------

_TR_GIT_PLAIN=" add am annotate apply archive blame branch bundle cat-file check-attr check-ignore check-mailmap check-ref-format checkout checkout-index cherry cherry-pick clean clone column commit commit-graph commit-tree config count-objects credential describe diff diff-files diff-index diff-tree fast-export fast-import fetch fetch-pack for-each-ref format-patch fsck gc grep hash-object help index-pack init interpret-trailers log ls-files ls-remote ls-tree mailinfo mailsplit maintenance merge merge-base merge-file merge-tree mktag mktree mv name-rev notes pack-objects pack-refs prune pull range-diff read-tree reflog remote repack replace rerere reset restore rev-list rev-parse revert rm shortlog show show-branch show-ref sparse-checkout stash status stripspace switch symbolic-ref tag unpack-objects update-index update-ref var verify-commit verify-pack verify-tag version whatchanged worktree write-tree receive-pack upload-pack upload-archive "

# git's options before the subcommand; sets _TR_G (to pass on) and _TR_DIR.
_tr_git() {   # $@ = git's arguments
  _TR_G=()
  _tr_git_opts 0 "$@"
}

# git's options before the subcommand, also at the start of an alias's
# expansion (`-p push`, `-c push.followTags=true push`), which git accepts.
_tr_git_opts() {   # $1 = alias depth, rest = the words
  local a depth=$1
  shift
  while [ $# -gt 0 ]; do
    a=$1
    case "$a" in
      -C)
        [ $# -ge 2 ] || return 0
        case "$2" in /*) _TR_DIR=$2 ;; '') ;; *) _TR_DIR=$_TR_DIR/$2 ;; esac
        _TR_G+=("$a" "$2"); shift 2 ;;
      -c|--git-dir|--work-tree|--namespace|--config-env|--attr-source|--shallow-file)
        [ $# -ge 2 ] || return 0
        _TR_G+=("$a" "$2"); shift 2 ;;
      --git-dir=*|--work-tree=*|--namespace=*|--config-env=*|--exec-path=*|--super-prefix=*|--attr-source=*|--shallow-file=*|--list-cmds=*|-p|--paginate|-P|--no-pager|--no-replace-objects|--no-lazy-fetch|--no-optional-locks|--no-advice|--bare|--literal-pathspecs|--no-literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs)
        _TR_G+=("$a"); shift ;;
      -*)
        # An option this file does not know: what follows cannot be read
        # as git reads it, so a push among the words is a possible tag push.
        for a in "$@"; do
          [ "$a" = push ] && { _tr_add release "git with an option flow does not read ($1) and push"; break; }
        done
        return 0 ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || return 0
  _tr_git_sub "$depth" "$@"
}

_tr_git_sub() {   # $1 = alias depth, $2 = subcommand, rest = its arguments
  local depth=$1 sub=$2 al
  shift 2
  case "$sub" in
    push) _tr_git_push "$@"; return 0 ;;
    send-pack|http-push) _tr_add release "git $sub"; return 0 ;;
    submodule|rebase|bisect|filter-branch|difftool|mergetool)
      case "$*" in
        *[Pp][Uu][Ss][Hh]*) _tr_add release "git $sub running a command that mentions push" ;;
      esac
      return 0 ;;
  esac
  case "$_TR_GIT_PLAIN" in *" $sub "*) return 0 ;; esac
  [ "$depth" -lt 10 ] || return 0
  al=$("$_TR_REAL" ${_TR_G[@]+"${_TR_G[@]}"} config --get "alias.$sub" 2>/dev/null) || return 0
  case "$al $*" in
    '!'*[Pp][Uu][Ss][Hh]*) _tr_add release "git $sub, an alias that runs a shell command, with push in it or its arguments"; return 0 ;;
    '!'*) return 0 ;;
  esac
  # git removes quotes and backslashes from an alias's words (`"push"
  # origin v1`, `p\ush`).
  al=${al//\"/}; al=${al//\'/}; al=${al//\\/}
  local -a aw
  set -f
  # shellcheck disable=SC2206
  aw=($al)
  set +f
  [ "${#aw[@]}" -gt 0 ] || return 0
  _tr_git_opts $((depth + 1)) "${aw[@]}" "$@"
}

_tr_git_push() {   # $@ = push's arguments
  local a out err rc line ref flag remote=0 seen=0 tag=0 sent=0 dd=0
  local -a opts=() rest=()
  # The command's own words, with this file's options after them and before
  # any `--`: git takes the last of an option given twice, so a
  # --no-dry-run, --no-porcelain or --verify of the command's cannot undo
  # them. Quiet would hide the ref lines; the push itself keeps it.
  for a in "$@"; do
    if [ "$dd" = 1 ]; then rest+=("$a"); continue; fi
    case "$a" in
      # After either, git reads every word as a refspec.
      --|--end-of-options) dd=1; rest+=("$a") ;;
      -q|--quiet|--qu|--qui|--quie) ;;
      *) opts+=("$a") ;;
    esac
  done
  err=$(mktemp "${TMPDIR:-/tmp}/flow-tier-push.XXXXXX" 2>/dev/null) || err=/dev/null
  # --dry-run twice: when the command's last word is an option that takes
  # the next word as its value (`-o`, `--push-option`, `--receive-pack`),
  # it takes the first, and the second still makes this a dry run.
  out=$(GIT_TERMINAL_PROMPT=0 "$_TR_REAL" ${_TR_G[@]+"${_TR_G[@]}"} push ${opts[@]+"${opts[@]}"} --dry-run --dry-run --porcelain --no-verify --no-quiet ${rest[@]+"${rest[@]}"} < /dev/null 2> "$err")
  rc=$?
  while IFS= read -r line; do
    case "$line" in
      'To '*)
        _tr_is_local_url "${line#To }" || remote=1 ;;
      ?$'\t'*$'\t'*)
        seen=1
        flag=${line%%$'\t'*}
        ref=${line#*$'\t'}; ref=${ref%%$'\t'*}
        [ "$flag" = "=" ] && continue
        sent=1
        case "${ref#*:}" in refs/tags/*) tag=1 ;; esac ;;
    esac
  done <<EOF
$out
EOF
  if [ "$seen" = 0 ]; then
    if [ "$rc" -ne 0 ] || [ "$remote" = 1 ] || ! grep -q 'Everything up-to-date' "$err" 2>/dev/null; then
      line=$(LC_ALL=C tr '\000-\037\177' ' ' < "$err" 2>/dev/null | head -c 200)
      [ "$err" = /dev/null ] || rm -f "$err"
      _tr_add release "git push, whose refs could not be listed${line:+ (git said: $line)}"
      return 0
    fi
  fi
  [ "$err" = /dev/null ] || rm -f "$err"
  [ "$remote" = 1 ] || return 0
  if [ "$tag" = 1 ]; then
    _tr_add release "git push that sends or deletes a tag"
  elif [ "$sent" = 1 ]; then
    _tr_add push "git push"
  fi
  return 0
}

# --- gh ---------------------------------------------------------------------

_tr_gh() {   # $1 = alias depth, rest = gh's arguments
  local depth=$1 w1="" w2="" a al
  shift
  local -a rest=()
  # The two subcommand words, past options, as gh reads them.
  while [ $# -gt 0 ]; do
    a=$1
    case "$a" in
      --repo|--hostname|-R) shift; [ $# -eq 0 ] || shift; continue ;;
      --*|-) shift; continue ;;
      -R*) shift; continue ;;
      -?*) shift; continue ;;
    esac
    if [ -z "$w1" ]; then
      w1=$a; shift
      if [ "$w1" = api ]; then _tr_gh_api "$@"; return 0; fi
      case "$w1" in pr|issue|release) continue ;; esac
      rest=("$@")
      break
    fi
    w2=$a; shift; break
  done
  case "$w1 $w2" in
    "pr merge") _tr_add merge "gh pr merge" ;;
    "pr create"|"pr new") _tr_add prCreate "gh pr create" ;;
    "issue create"|"issue new") _tr_add issueCreate "gh issue create" ;;
    "issue edit")
      for a in "$@"; do
        case "$a" in --add-assignee|--add-assignee=*) _tr_add issueAssign "gh issue edit --add-assignee"; break ;; esac
      done ;;
    "release create"|"release new")
      _tr_add release "gh release $w2"
      _tr_release_tag "$@" ;;
    "release edit"|"release delete"|"release upload"|"release delete-asset")
      _tr_add release "gh release $w2" ;;
  esac
  case "$w1" in pr|issue|release|'') return 0 ;; esac
  # Any other first word: an alias (gh's own `co` among them, which a user
  # may redefine), an extension, or a command flow does not tier.
  [ "$depth" -lt 10 ] || return 0
  # gh's own commands take no alias; asking gh costs a process.
  case "$_TR_GH_CMDS" in *" $w1 "*) return 0 ;; esac
  if ! al=$(_tr_gh_alias "$w1"); then
    return 0
  fi
  if [ "$al" = __FLOW_UNREAD__ ]; then
    _tr_add merge "gh $w1, an alias flow cannot read"
    _tr_add release "gh $w1, an alias flow cannot read"
    return 0
  fi
  case "$al" in
    \"*\") al=${al#\"}; al=${al%\"} ;;
    "'"*"'") al=${al#\'}; al=${al%\'} ;;
  esac
  case "$al" in
    '!'*)
      case "$al" in
        *[Mm][Ee][Rr][Gg][Ee]*|*[Rr][Ee][Ll][Ee][Aa][Ss][Ee]*|*[Pp][Uu][Ss][Hh]*)
          _tr_add merge "gh $w1, an alias that runs a shell command"
          _tr_add release "gh $w1, an alias that runs a shell command" ;;
      esac
      return 0 ;;
  esac
  # gh decodes the YAML value, replaces $N anywhere in it and splits it as
  # a shell does. Only a value of plain words and whole-word $N is read
  # here; one with a quote, a backslash, a $ inside a word, or a YAML block
  # or flow marker may expand to anything, so it is a possible merge or
  # release.
  local bare
  bare=$(printf ' %s ' "$al" | sed -e 's/ [$][0-9][0-9]* / /g' -e 's/ [$][0-9][0-9]* / /g')
  case "$bare" in
    *[!A-Za-z0-9\ _./:=,@+-]*)
      _tr_add merge "gh $w1, an alias flow cannot read"
      _tr_add release "gh $w1, an alias flow cannot read"
      return 0 ;;
  esac
  # As gh expands it: $N is the Nth argument after the alias, and the
  # arguments no $N used are appended.
  local -a aw out
  local w n used=0
  set -f
  # shellcheck disable=SC2206
  aw=($al)
  set +f
  out=()
  for w in ${aw[@]+"${aw[@]}"}; do
    case "$w" in
      '$'[1-9]|'$'[1-9][0-9])
        n=${w#?}
        # gh replaces $N in turn, so an argument that is itself $N is
        # replaced again: such an argument cannot be read here.
        case "${rest[n-1]:-}" in
          *'$'[0-9]*)
            _tr_add merge "gh $w1 with an argument flow cannot read"
            _tr_add release "gh $w1 with an argument flow cannot read"
            return 0 ;;
        esac
        out+=("${rest[n-1]:-}")
        [ "$n" -gt "$used" ] && used=$n ;;
      *) out+=("$w") ;;
    esac
  done
  _tr_gh $((depth + 1)) ${out[@]+"${out[@]}"} ${rest[@]+"${rest[@]:$used}"}
}

# gh release create <tag> ... --verify-tag: sets _TR_VTAG to the tag.
_tr_release_tag() {   # $@ = the arguments after create
  local a tag="" verify=0 skip=0
  # GH_REPO or GH_HOST names another repository than the one the gate
  # checked the tag in.
  [ -z "${GH_REPO:-}" ] && [ -z "${GH_HOST:-}" ] || return 0
  for a in "$@"; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$a" in
      --verify-tag|--verify-tag=true) verify=1 ;;
      # The gate checked the tag in origin's repository only.
      -R|--repo|-R*|--repo=*) return 0 ;;
      -t|--title|-n|--notes|-F|--notes-file|--target|--discussion-category|--notes-start-tag) skip=1 ;;
      -*) ;;
      *) [ -n "$tag" ] || tag=$a ;;
    esac
  done
  [ "$verify" = 1 ] && _TR_VTAG=$tag
  return 0
}

# gh's own commands, which no alias replaces.
_TR_GH_CMDS=" agent-task alias api attestation auth browse cache codespace completion config copilot extension gist gpg-key help issue label licenses org pr preview project release repo ruleset run search secret ssh-key status variable workflow version "

# The value of gh alias $1, as gh itself reads its configuration (`gh alias
# list`: GH_CONFIG_DIR, XDG_CONFIG_HOME and HOME as gh resolves them; no
# network). gh prints the aliases back as YAML, one `name: value` per line.
# A value written in single quotes is printed without them; a block value
# (`|`, `>`), a value continued on the next line, or a double-quoted one
# prints __FLOW_UNREAD__. Returns 1 when $1 is no alias, or gh cannot list
# them.
_tr_gh_alias() {
  local out
  out=$("$_TR_REAL" alias list 2>/dev/null) || return 1
  # The name is read as gh prints it: bare, in double quotes (a name YAML
  # would read as another type: "yes", "1") or in single quotes (one that
  # starts with a special character or holds `: `). A name with a backslash
  # is an escape this reader does not decode, so any lookup then answers
  # __FLOW_UNREAD__ unless the name was found as written.
  printf '%s\n' "$out" | awk -v name="$1" '
    /^[[:space:]]/ { if (cur) cont = 1; next }
    {
      cur = 0; raw = $0
      if (raw ~ /^"/) {
        k = substr(raw, 2); i = index(k, "\": "); if (!i) i = index(k, "\":\t")
        key = substr(k, 1, i - 1); rest = substr(k, i + 2)
      } else if (raw ~ /^\047/) {
        k = substr(raw, 2); i = index(k, "\047: "); if (!i) i = index(k, "\047:\t")
        key = substr(k, 1, i - 1); gsub(/\047\047/, "\047", key); rest = substr(k, i + 2)
      } else {
        i = match(raw, /:[ \t]/); key = substr(raw, 1, i - 1); rest = substr(raw, i + 1)
      }
      if (!i) next
      sub(/^[ \t]+/, "", rest)
      if (raw ~ /^"/ && key ~ /\\/) bs = 1
      if (key == name && !have) { have = 1; val = rest; cur = 1 }
    }
    END {
      if (have) {
        if (cont || val ~ /^[|>"]/) { print "__FLOW_UNREAD__"; exit 0 }
        if (val ~ /^\047.*\047$/) { val = substr(val, 2, length(val) - 2); gsub(/\047\047/, "\047", val) }
        print val; exit 0
      }
      if (bs) { print "__FLOW_UNREAD__"; exit 0 }
      exit 1
    }'
}

# GraphQL: the names of the fields called with arguments in a document that
# holds a mutation, with strings and comments removed, one per line.
_tr_gql_fields() {   # stdin = the document
  awk '
    { doc = doc $0 "\n" }
    END {
      out = ""; i = 1; n = length(doc)
      while (i <= n) {
        c = substr(doc, i, 1)
        if (substr(doc, i, 3) == "\"\"\"") {
          j = index(substr(doc, i + 3), "\"\"\""); i = (j ? i + 3 + j + 2 : n + 1); out = out " "; continue
        }
        if (c == "\"") {
          i++
          while (i <= n) { c = substr(doc, i, 1); if (c == "\\") { i += 2; continue } if (c == "\"" || c == "\n") break; i++ }
          i++; out = out " "; continue
        }
        if (c == "#") { while (i <= n && substr(doc, i, 1) != "\n") i++; continue }
        out = out c; i++
      }
      if (out !~ /(^|[^A-Za-z0-9_])mutation([^A-Za-z0-9_]|$)/) exit
      while (match(out, /[A-Za-z_][A-Za-z0-9_]*[ \t\r\n,]*\(/)) {
        f = substr(out, RSTART, RLENGTH); sub(/[ \t\r\n,]*\($/, "", f)
        print f
        out = substr(out, RSTART + RLENGTH)
      }
    }'
}

_tr_gql() {   # $1 = the document, or empty when it could not be read
  local f lf
  if [ -z "$1" ]; then
    _tr_add merge "gh api graphql with a query flow could not read"
    _tr_add release "gh api graphql with a query flow could not read"
    return 0
  fi
  while IFS= read -r f; do
    lf=$(printf '%s' "$f" | LC_ALL=C tr 'A-Z' 'a-z')
    case "$lf" in
      disablepullrequestautomerge|mutation) ;;
      *merge*|enqueuepullrequest) _tr_add merge "gh api graphql $f" ;;
      *release*|*ref*) _tr_add release "gh api graphql $f" ;;
      createpullrequest) _tr_add prCreate "gh api graphql $f" ;;
      createissue) _tr_add issueCreate "gh api graphql $f" ;;
      addassigneestoassignable) _tr_add issueAssign "gh api graphql $f" ;;
    esac
  done <<EOF
$(printf '%s\n' "$1" | _tr_gql_fields)
EOF
}

# A field's value as gh sends it: -F key=@file reads the file (@- is stdin,
# which cannot be read here); -f is the text itself. Sets _TR_FV, or returns 1.
_tr_field_value() {   # $1 = -f or -F, $2 = the value after key=
  _TR_FV=$2
  if [ "$1" = -F ]; then
    case "$2" in
      @-) return 1 ;;
      # A regular file only: a FIFO, stdin or /dev/fd/N would be read here
      # instead of by gh, and could hand gh something else.
      @*) [ -f "${2#@}" ] && [ -r "${2#@}" ] || return 1; _TR_FV=$(cat "${2#@}") || return 1 ;;
    esac
  fi
  return 0
}

_tr_gh_api() {   # $@ = the arguments after api
  local method="" ep="" body=0 a k v kind q="" qok=1 input="" ref="" refok=1 assignee=0 i c
  while [ $# -gt 0 ]; do
    a=$1; shift
    kind=""
    case "$a" in
      -X|--method) method=${1-}; shift ;;
      --method=*) method=${a#--method=} ;;
      -f|--raw-field) kind=-f; v=${1-}; shift ;;
      -F|--field) kind=-F; v=${1-}; shift ;;
      --raw-field=*) kind=-f; v=${a#--raw-field=} ;;
      --field=*) kind=-F; v=${a#--field=} ;;
      --input) input=${1-}; shift; body=1 ;;
      --input=*) input=${a#--input=}; body=1 ;;
      -H|--header|-p|--preview|-q|--jq|-t|--template|--cache|--hostname) shift ;;
      --*) ;;
      -?*)
        # A bundle of short options: the first that takes a value takes
        # the rest of the word (less one '='), or the next word.
        i=1
        while [ "$i" -lt "${#a}" ]; do
          c=${a:i:1}
          case "$c" in
            X|f|F|H|p|q|t)
              v=${a:i+1}; v=${v#=}
              if [ -z "$v" ]; then v=${1-}; shift; fi
              case "$c" in
                X) method=$v ;;
                f) kind=-f ;;
                F) kind=-F ;;
              esac
              break ;;
          esac
          i=$((i + 1))
        done ;;
      *) [ -n "$ep" ] || ep=$a ;;
    esac
    if [ -n "$kind" ]; then
      body=1
      k=${v%%=*}
      case "$v" in *=*) v=${v#*=} ;; *) v="" ;; esac
      case "$k" in
        query)
          if _tr_field_value "$kind" "$v"; then q=$_TR_FV; else qok=0; fi ;;
        ref)
          if _tr_field_value "$kind" "$v"; then ref=$_TR_FV; else refok=0; fi ;;
        assignee|assignees|assignee\[\]|assignees\[\]) assignee=1 ;;
      esac
    fi
  done
  method=$(printf '%s' "$method" | LC_ALL=C tr 'a-z' 'A-Z')
  [ -n "$method" ] || { if [ "$body" = 1 ]; then method=POST; else method=GET; fi; }
  # The path: no scheme or host, no leading /, no query, %2F as /.
  case "$ep" in *://*) ep=${ep#*://}; ep=${ep#*/} ;; esac
  ep=${ep%%#*}; ep=${ep#/}; ep=${ep%%\?*}; ep=${ep#api/v3/}
  # Every %XX decoded and repeated slashes collapsed, as the server reads
  # the path and as tier-gate.sh does.
  case "$ep" in *%[0-9A-Fa-f][0-9A-Fa-f]*) ep=$(printf '%b' "${ep//%/\\x}") ;; esac
  local dbl='//' one='/'
  while :; do case "$ep" in *//*) ep=${ep//$dbl/$one} ;; *) break ;; esac; done
  if [ "$ep" = graphql ]; then
    if [ -n "$input" ]; then
      if [ "$input" != - ] && [ -f "$input" ] && [ -r "$input" ]; then
        q=$(jq -r '.query // empty' "$input" 2>/dev/null) || q=""
      else
        q=""
      fi
      [ -n "$q" ] || qok=0
    fi
    [ "$qok" = 1 ] || q=""
    _tr_gql "$q"
    return 0
  fi
  case "$method" in GET|HEAD) return 0 ;; esac
  # Matched by the end of the path.
  local R='(^|/)'
  if [[ "$ep" =~ ${R}pulls/[^/]+/merge/?$ ]] || [[ "$ep" =~ ${R}merges/?$ ]]; then
    case "$method" in PUT|POST|PATCH) _tr_add merge "gh api $method $ep" ;; esac
  elif [[ "$ep" =~ ${R}releases(/|$) ]] || [[ "$ep" =~ ${R}git/refs/tags(/|$) ]]; then
    _tr_add release "gh api $method $ep"
  elif [[ "$ep" =~ ${R}git/refs/?$ ]]; then
    if [ -n "$input" ] || [ "$refok" = 0 ]; then
      _tr_add release "gh api $method $ep with a ref flow could not read"
    else
      case "$ref" in refs/tags/*) _tr_add release "gh api $method $ep ($ref)" ;; esac
    fi
  elif [[ "$ep" =~ ${R}pulls/?$ ]]; then
    [ "$method" = POST ] && _tr_add prCreate "gh api POST $ep"
  elif [[ "$ep" =~ ${R}issues/?$ ]]; then
    [ "$method" = POST ] && _tr_add issueCreate "gh api POST $ep"
  elif [[ "$ep" =~ ${R}issues/[^/]+/assignees/?$ ]]; then
    [ "$method" = POST ] && _tr_add issueAssign "gh api POST $ep"
  elif [[ "$ep" =~ ${R}issues/[^/]+/?$ ]]; then
    case "$method" in
      PATCH|PUT)
        if [ "$assignee" = 1 ]; then
          _tr_add issueAssign "gh api $method $ep"
        elif [ -n "$input" ]; then
          if [ "$input" = - ] || ! [ -f "$input" ] || ! [ -r "$input" ] || grep -q '"assignees\{0,1\}"' "$input" 2>/dev/null; then
            _tr_add issueAssign "gh api $method $ep"
          fi
        fi ;;
    esac
  fi
  return 0
}

# --- the decision -----------------------------------------------------------

_tr_phrase() {
  case "$1" in
    push) printf 'Pushing to a remote' ;;
    prCreate) printf 'Creating a pull request' ;;
    issueAssign) printf 'Assigning an issue' ;;
    issueCreate) printf 'Creating an issue' ;;
    merge) printf 'Merging a pull request' ;;
    release) printf 'Creating a release or pushing a tag' ;;
  esac
}

# Use one of the approvals the call's record holds for $1: 0 when there was
# one (or the gate could not count them), 1 when there is none left. The
# count is changed under a lock, since programs of one command can run at
# the same time.
_tr_take() {   # $1 = tier key
  local f="$_TR_REC/asked" n i=0 tmp
  [ -n "$_TR_REC" ] && [ -f "$f" ] || return 1
  # A lock left by a wrapper that died holding it is removed after a minute.
  find "$_TR_REC/lock" -maxdepth 0 -mmin +1 -exec rmdir {} \; 2>/dev/null
  while ! mkdir "$_TR_REC/lock" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -lt 50 ] || return 1; sleep 0.1
  done
  n=$(awk -v k="$1" '$1 == k { print $2; exit }' "$f" 2>/dev/null)
  case "$n" in
    '*') rmdir "$_TR_REC/lock"; return 0 ;;
    ''|0|*[!0-9]*) rmdir "$_TR_REC/lock"; return 1 ;;
  esac
  tmp="$f.$$"
  awk -v k="$1" '$1 == k { $2 = $2 - 1 } { print }' "$f" > "$tmp" 2>/dev/null && mv -f "$tmp" "$f"
  rmdir "$_TR_REC/lock"
  return 0
}

_tr_decide() {   # $1 = git or gh
  local rec="${FLOW_TIER_CALL:-}" journaled="" key value rc refused="" crumbs="" top
  _TR_REC=""
  if [ -n "${FLOW_TIER_DIR:-}" ] && [ -n "$rec" ] && [ -d "$rec" ] && [ ! -L "$rec" ]; then
    case "$rec" in
      "$FLOW_TIER_DIR"/call.*)
        _TR_REC=$rec
        journaled=" $({ tr '\n' ' ' < "$rec/journaled"; } 2>/dev/null) " ;;
    esac
  fi
  for key in $_TR_KEYS; do
    case "$key" in
      merge|release) value=confirm ;;
      *)
        value=$(cd "$_TR_DIR" 2>/dev/null && "$_TR_ROOT/bin/cascade-resolve.sh" --default journal ".tiers.$key" 2>/dev/null)
        rc=$?
        value=$(printf '%s' "$value" | LC_ALL=C tr -d '\r\n')
        if [ "$rc" -ne 0 ]; then
          _tr_note "could not read tiers.$key; running $_TR_WHAT without a tier check"
          continue
        fi ;;
    esac
    case "$value" in
      confirm)
        # gh release create --verify-tag of the tag tier-gate.sh found on
        # origin and journaled: that one command, not any other release.
        if [ "$key" = release ] && [ "$_TR_KEYS" = " release" ] && [ -n "$_TR_VTAG" ] && [ -n "$_TR_REC" ] &&
           grep -qxF -- "$_TR_VTAG" "$_TR_REC/verified" 2>/dev/null; then
          continue
        fi
        _tr_take "$key" && continue
        refused="$refused $key" ;;
      journal)
        case "$journaled" in *" $key "*) continue ;; esac
        if [ -n "$_TR_REC" ] && awk -v k="$key" '$1 == k { f = 1 } END { exit !f }' "$_TR_REC/asked" 2>/dev/null; then continue; fi
        # At most 160 characters of the command, as tier-gate.sh writes.
        crumbs="$crumbs<!-- auto-log: $(date -u +%Y-%m-%dT%H:%M:%SZ) tiers.$key (journal, runtime) \"$(_tg_crumb_safe "$(printf '%s' "$1 $_TR_ARGS" | cut -c1-160)")\" -->"$'\n' ;;
      autonomous) ;;
      *) _tr_note "tiers.$key is not autonomous, journal or confirm; running $_TR_WHAT without a tier check" ;;
    esac
  done
  if [ -n "$refused" ]; then
    local first="${refused# }"; first=${first%% *}
    printf 'flow: %s (tiers.%s) needs your confirmation, and this Bash call was not confirmed for it: flow did not find %s in the command text before it ran (or found fewer of them than ran), so it could not ask. Nothing was run. Run the %s command on its own, with its arguments written out (for example: gh pr merge 7 --squash, or git push origin v1.2.0), so that flow asks first.\n' \
      "$(_tr_phrase "$first")" "$first" "$_TR_WHAT" "$1" >&2
    # An approval record that no call took, while this call has none: the
    # shell may have been started with the command in a form the session's
    # line does not match (a Claude Code update, a hook that rewrites
    # commands). Say so, since the message above would then be wrong.
    if [ -z "$_TR_REC" ] && [ -n "${FLOW_TIER_DIR:-}" ] &&
       command ls "$FLOW_TIER_DIR" 2>/dev/null | grep -q '^pending\.'; then
      printf 'flow: if you approved this command, flow could not tie the approval to it: a record of an approval is waiting that no command took. Claude Code may now start its shell in a way flow does not read, or another hook rewrote the command. Run the command yourself with ! in front of it, and report this to the flow plugin.\n' >&2
    fi
    exit 1
  fi
  if [ -n "$crumbs" ]; then
    top=$("$_TR_GITBIN" -C "$_TR_DIR" rev-parse --show-toplevel 2>/dev/null) || top=""
    _tg_write_trail "$top" "$crumbs"
  fi
  return 0
}

# --- entry ------------------------------------------------------------------

_tr_main() {   # $1 = git or gh, rest = the program's arguments
  local prog=$1
  shift
  _TR_SHIMS=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../shims" 2>/dev/null && pwd -P) || _TR_SHIMS=""
  _TR_REAL=$(_tr_real "$prog") || {
    _tr_note "no $prog on PATH apart from flow's wrapper"
    exit 127
  }
  _TR_KEYS=""
  _TR_WHAT=""
  _TR_VTAG=""
  _TR_DIR=$PWD
  case "$prog" in
    git) _TR_GITBIN=$_TR_REAL; _tr_git "$@" ;;
    gh) _tr_gh 0 "$@" ;;
  esac
  if [ -n "$_TR_KEYS" ]; then
    _TR_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd -P)
    export CLAUDE_PLUGIN_ROOT="$_TR_ROOT"
    PLUGIN_ROOT=$_TR_ROOT
    [ -n "${_TR_GITBIN:-}" ] || _TR_GITBIN=$(_tr_real git) || _TR_GITBIN=git
    _TR_ARGS="$*"
    _tg_note() { _tr_note "$1"; }
    # shellcheck source=tier-trail.sh
    . "$(dirname "${BASH_SOURCE[0]}")/tier-trail.sh"
    _tr_decide "$prog"
  fi
  exec "$_TR_REAL" "$@"
}
