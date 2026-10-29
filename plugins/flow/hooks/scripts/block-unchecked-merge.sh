#!/bin/bash
# [flow] PreToolUse hook: refuse a merge while its checks are unfinished.
#
# `/flow:merge` reads statusCheckRollup and will not proceed on a red or
# unfinished pull request. That gate only covers merges that go through the
# command. A `gh pr merge` typed straight into Bash consults nothing, and that
# is how a pull request came to be merged with twelve jobs still queued
# (issue #170).
#
# Two things are refused:
#
#   1. Any `gh pr merge` while a check is queued, running, or failed. The
#      checks are named, so the message says what to wait for.
#
#   2. `--auto` on a base branch with no required status checks. GitHub's
#      auto-merge waits for REQUIRED checks; where none are required it merges
#      at once. Reaching for `--auto` means "wait for CI", and on such a
#      repository it does the opposite of what the person asking for it wants.
#      Requiring branch protection is not this hook's business — issue #170
#      says so explicitly — but neither is letting its absence read as a
#      passing gate.
#
# What is NOT refused: a merge of a fully green pull request, written in the
# one shape this hook can read (below). `/flow:merge` writes that shape.
#
# Every refusal ends with a line that starts "Next: " (#310). It is either a
# command the agent can run, or a statement that the user must act, with the
# exact command to type. A command typed with `!` runs without PreToolUse
# hooks, so `! gh pr merge ...` is how the user merges past this hook on
# purpose. A refusal that a retry cannot change says so.
#
# The command is parsed, not matched. `echo "gh pr merge 3"` runs no merge, and
# a hook that reads text rather than commands refuses the bug report that
# describes it — the lesson of issues #167 and #142, whose parser this shares.
#
# One shape (#195). Reading text cannot expand a variable, see a `cd`, know
# what GH_REPO holds, or follow every way gh accepts a flag. Each of those let a
# merge be checked against one pull request while gh merged another, and
# closing them one spelling at a time never ended. So a merge is accepted only
# as
#
#   gh pr merge <number> --repo owner/name --squash|--merge|--rebase
#      [--delete-branch] [--admin] [--auto] [--subject S] [--body B]
#      [--body-file F] [--author-email E] [--match-head-commit SHA]
#
# with gh as the first word, long options only, and every value literal.
# `--repo` is required because it outranks GH_REPO, GH_HOST, the working
# directory and `gh repo set-default` alike: with it written, none of them
# matter. Anything else that is a merge is refused with the shape to use, and a
# value that cannot be read is named. `gh api` on a merge endpoint or a merge
# mutation is refused outright, as is one whose whole endpoint is a variable, or
# a GraphQL call whose query comes from a file.
#
# Not covered, by design. This hook catches merges written in good faith, or
# misdirected by a variable or a directory. It does not stop deliberate
# evasion: a quote or backslash inside the word (`m\erge`), a command held in a
# variable and run as `$CMD`, a gh alias defined in an earlier call, a script
# piped into a shell, a gh extension, or curl to the REST API. Branch protection
# with required checks is the mechanism for that, as #170 says.

set -uo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED: jq not available — cannot verify merge readiness." >&2
  echo "Next: install jq (brew install jq, or apt-get install jq), then run the merge again." >&2
  exit 2
fi
if ! command -v awk >/dev/null 2>&1; then
  echo "BLOCKED: awk not available — cannot verify merge readiness." >&2
  echo "Next: install awk, then run the merge again." >&2
  exit 2
fi

_BD_LIB="$HOOK_DIR/lib/command-parse.sh"
if [ ! -r "$_BD_LIB" ]; then
  echo "BLOCKED: cannot read $_BD_LIB — the command parser is missing, so merge readiness cannot be verified." >&2
  echo "Next: this will not change on retry. The user must reinstall the flow plugin: /plugin install flow@synapti-marketplace" >&2
  exit 2
fi
# shellcheck source=lib/command-parse.sh
. "$_BD_LIB"
# Readable is not the same as loaded. A truncated or broken library defines
# nothing, every call below fails, no merge is found, and the hook allows.
for _bd_fn in _bd_strip_noncode _bd_segments _bd_expand_interpreter_args _rm_tokenise _bd_is_redirection; do
  if ! type "$_bd_fn" >/dev/null 2>&1; then
    echo "BLOCKED: the command parser did not load ($_bd_fn is undefined), so merge readiness cannot be verified." >&2
    echo "Next: this will not change on retry. The user must reinstall the flow plugin: /plugin install flow@synapti-marketplace" >&2
    exit 2
  fi
done
if [ -z "${_BD_SEG_AWK:-}" ]; then
  echo "BLOCKED: the command parser did not load (its segmenter program is empty), so merge readiness cannot be verified." >&2
  echo "Next: this will not change on retry. The user must reinstall the flow plugin: /plugin install flow@synapti-marketplace" >&2
  exit 2
fi

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && exit 0

# Cheap reject before any parsing: this hook runs before every Bash call. On the
# text without quotes and backslashes, so `me""rge` still reaches the parser,
# and in any case, because the GraphQL auto-merge mutation is spelled
# enablePullRequestAutoMerge. `graphql` too: a query read from a file never
# shows the word merge. The quotes are removed with tr, not with a bash pattern
# substitution, which on bash 3.2 takes tens of seconds on a PR body of a few KB.
# If tr fails, the text is kept whole and parsed rather than let through.
if ! _BUM_BARE=$(printf '%s' "$COMMAND" | LC_ALL=C tr -d "'\"\\\\"); then
  _BUM_BARE=merge
fi
case "$_BUM_BARE" in
  *[Mm][Ee][Rr][Gg][Ee]*|*[Gg][Rr][Aa][Pp][Hh][Qq][Ll]*) ;;
  *) exit 0 ;;
esac

_bd_strip_noncode "$COMMAND"
# `bash -c 'gh pr merge 9'` and `eval '...'` hide the merge inside one quoted
# word. Expand those first, so the merge is a command like any other.
_bd_expand_interpreter_args

# A value this hook cannot know without running a shell: a variable, or a
# substitution (the segmenter leaves `__BD_SUBST__` where `$(...)` or a backtick
# pair stood). Quoting is gone by this point, so `'$X'` counts too.
_bum_unreadable() {
  case "$1" in
    *'$'*|*'`'*|*__BD_SUBST__*) return 0 ;;
  esac
  return 1
}

# A `{…}` left in a value: a documented command template run before its
# placeholders were filled in.
_bum_placeholder() {
  case "$1" in
    *'{'*'}'*) return 0 ;;
  esac
  return 1
}

# Text as a refusal may show it: substitutions spelled as the reader wrote them,
# control characters and line breaks replaced (stderr goes back into a
# transcript, and a check name is written by whoever wrote the workflow), and
# not so long that the instruction after it is lost. $2 is the length limit.
_bum_show() {
  local v="$1" max="${2:-200}"
  v="${v// __BD_SUBST__ /\$(...)}"
  v="${v//__BD_SUBST__/\$(...)}"
  v="${v//[[:cntrl:]]/?}"
  v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
  if [ "${#v}" -gt "$max" ]; then v="${v:0:$max}..."; fi
  printf '%s' "$v"
}

_BUM_SHAPE="gh pr merge <number> --repo owner/name --squash (or --merge, --rebase), with any of --delete-branch, --admin, --auto, --subject, --body, --body-file, --author-email, --match-head-commit"

_bum_refuse() {              # $1, $2 = the two lines
  echo "$1" >&2
  echo "$2" >&2
  exit 2
}

_bum_refuse_unreadable() {   # $1 = what, $2 = value
  _bum_refuse "BLOCKED: gh pr merge, but the $1 is given as \"$(_bum_show "$2")\", which this hook reads as text and cannot expand." \
    "Next: write it literally so its checks can be verified: $_BUM_SHAPE."
}

_bum_refuse_placeholder() {  # $1 = what, $2 = value
  _bum_refuse "BLOCKED: gh pr merge, but the $1 is \"$(_bum_show "$2")\", a placeholder that was not filled in." \
    "Next: replace it with the real value and run the merge again."
}

_bum_refuse_shape() {        # $1 = what is wrong
  _bum_refuse "BLOCKED: gh pr merge, but $1." \
    "Next: this hook checks a merge only in one shape, so write it as: $_BUM_SHAPE."
}

# Is this word gh? A path to it counts, a leading backslash counts, and the
# compare ignores case, because a case-insensitive filesystem will run `GH`. A
# case pattern rather than a subprocess per word: this runs on every word of a
# command that mentions merge, and a `git add` of thousands of files followed by
# a merge took seconds when each word forked `tr`.
_bum_is_gh() {
  local b="${1##*/}"
  b="${b#\\}"
  case "$b" in [Gg][Hh]) return 0 ;; esac
  return 1
}

_bum_is_assignment() {
  case "$1" in
    [A-Za-z_]*=*)
      local name="${1%%=*}"
      case "$name" in *[!A-Za-z0-9_]*) return 1 ;; esac
      return 0 ;;
  esac
  return 1
}

# gh's own options that take a value, at the root or on a subcommand, for
# finding the subcommand words past them.
_bum_takes_value() {
  case "$1" in
    -R|--repo|-t|--subject|-b|--body|-F|--body-file|-A|--author-email|--match-head-commit)
      return 0 ;;
  esac
  return 1
}

# The subcommand words after index $1: fills SUB with up to three words, past
# options and their values.
_bum_subwords() {
  local j="$1" t
  SUB=()
  while [ "$j" -lt "$n" ] && [ "${#SUB[@]}" -lt 3 ]; do
    t="${TOK[j]}"
    if _bum_takes_value "$t"; then j=$((j + 2)); continue; fi
    case "$t" in -*) j=$((j + 1)); continue ;; esac
    SUB+=("$t")
    j=$((j + 1))
  done
}

# Does this simple command end inside an open quote?
_bum_unterminated() {
  # Exit 3 means balanced. Any other status, a crashed awk included, is read
  # as unterminated, so a failure refuses rather than lets the merge through.
  local rc=0
  printf '%s\n' "$1" | awk '
    # Does the quote at i open a dollar-quoted string? Only when the character
    # before it is a dollar sign that no backslash escapes.
    function dq_open(s, i,   j, b) {
      if (i < 2 || substr(s, i - 1, 1) != "$") return 0
      b = 0
      for (j = i - 2; j >= 1 && substr(s, j, 1) == "\\"; j--) b++
      return (b % 2) == 0
    }
    BEGIN { SQ = sprintf("%c", 39); DQ = "$" SQ; q = "" }
    {
      n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (c == "\\" && q != SQ) { i++; continue }
        if (q != "") { if (c == q || (q == DQ && c == SQ)) q = ""; continue }
        # A dollar-quoted string: inside it a backslash escapes the quote.
        if (c == SQ && dq_open($0, i)) q = DQ
        else if (c == "\"" || c == SQ) q = c
      }
    }
    END { exit (q != "" ? 0 : 3) }' || rc=$?
  [ "$rc" -ne 3 ]
}

# The walk and every rule of the shape, for the command in TOK whose gh stands
# at index c. Sets sel, repo, strat, delbr, admin, mhc and auto for a merge in the shape; any other
# refuses, and a refusal exits the hook.
_bum_judge_merge() {
  if [ "$c" -gt 0 ] || ! _bum_is_gh "${TOK[0]}"; then
    if _bum_unreadable "${TOK[c]}"; then
      { _bum_refuse_unreadable "gh command" "${TOK[c]}"; return 1; }
    fi
    { _bum_refuse_shape "\"$(_bum_show "${TOK[*]:0:$c}")\" comes before gh, and whatever runs first can change which pull request gh merges"; return 1; }
  fi

  repo=""; repo_n=0; strat_n=0; strat=""; delbr=0; admin=0; mhc=""; auto=0; bad=""; badrepo=""
  words=()
  i=1
  while [ "$i" -lt "$n" ]; do
    tok="${TOK[i]}"
    nxt="${TOK[i+1]:-}"
    # A bare redirection operator takes the next word as its target, which is
    # a file name and not a selector.
    case "$tok" in
      '>'|'>>'|'<'|'<<<'|[0-9]'>'|[0-9]'>>'|[0-9]'<') i=$((i + 2)); continue ;;
    esac
    if _bd_is_redirection "$tok"; then i=$((i + 1)); continue; fi
    case "$tok" in
      --repo)
        repo="$nxt"; repo_n=$((repo_n + 1)); i=$((i + 2))
        # An unquoted `$(...)` joined to the value is split off by the
        # segmenter; the repository is the two together.
        [ "${TOK[i]:-}" = "__BD_SUBST__" ] && { repo="$repo${TOK[i]}"; i=$((i + 1)); }
        continue ;;
      --repo=*)
        repo="${tok#--repo=}"; repo_n=$((repo_n + 1)); i=$((i + 1))
        [ "${TOK[i]:-}" = "__BD_SUBST__" ] && { repo="$repo${TOK[i]}"; i=$((i + 1)); }
        continue ;;
      --squash|--merge|--rebase) strat_n=$((strat_n + 1)); strat="$tok" ;;
      --delete-branch) delbr=1 ;;
      --admin) admin=1 ;;
      --auto) auto=1 ;;
      --match-head-commit) mhc="$nxt"; i=$((i + 2)); continue ;;
      --match-head-commit=*) mhc="${tok#--match-head-commit=}" ;;
      --subject|--body|--body-file|--author-email)
        i=$((i + 2)); continue ;;
      --subject=*|--body=*|--body-file=*|--author-email=*) ;;
      # -R is not in the shape, but its value is still the repository: when that
      # value cannot be read, naming it says more than naming the option.
      -R)
        [ -z "$bad" ] && bad="$tok"
        _bum_unreadable "$nxt" && [ -z "$badrepo" ] && badrepo="$nxt"
        i=$((i + 2)); continue ;;
      -R?*)
        [ -z "$bad" ] && bad="$tok"
        _bum_unreadable "${tok#-R}" && [ -z "$badrepo" ] && badrepo="${tok#-R}" ;;
      -*) [ -z "$bad" ] && bad="$tok" ;;
      *) words+=("$tok") ;;
    esac
    i=$((i + 1))
  done

  # Values first, by name, before anything else is said about the merge: that
  # is what tells the reader which word to fix.
  sel="${words[2]:-}"
  for ((w = 3; w < ${#words[@]}; w++)); do
    if _bum_unreadable "${words[w]}"; then sel="${words[*]:2}"; break; fi
  done
  _bum_unreadable "$sel" && { _bum_refuse_unreadable "pull request" "$sel"; return 1; }
  _bum_unreadable "$repo" && { _bum_refuse_unreadable "repository" "$repo"; return 1; }
  [ -n "$badrepo" ] && { _bum_refuse_unreadable "repository" "$badrepo"; return 1; }
  _bum_placeholder "$sel" && { _bum_refuse_placeholder "pull request" "$sel"; return 1; }
  _bum_placeholder "$repo" && { _bum_refuse_placeholder "repository" "$repo"; return 1; }

  [ -z "$bad" ] || { _bum_refuse_shape "\"$(_bum_show "$bad")\" is not one of the options it reads (long options only)"; return 1; }
  if [ "${#words[@]}" -ne 3 ] || [ "${words[0]}" != "pr" ] || [ "${words[1]}" != "merge" ]; then
    if [ "${#words[@]}" -lt 3 ]; then
      { _bum_refuse_shape "it names no pull request number"; return 1; }
    fi
    { _bum_refuse_shape "\"$(_bum_show "${words[*]}")\" is not pr merge followed by one pull request number"; return 1; }
  fi
  case "$sel" in
    ''|*[!0-9]*) _bum_refuse_shape "the pull request is \"$(_bum_show "$sel")\", not a number"; return 1 ;;
  esac
  [ "$repo_n" -ge 1 ] || { _bum_refuse_shape "it names no --repo, so the repository would come from the directory or GH_REPO, which this hook cannot see"; return 1; }
  [ "$repo_n" -eq 1 ] || { _bum_refuse_shape "--repo is given more than once"; return 1; }
  # owner/name only. A host/owner/name form reads the pull request from the
  # right host, but the required-checks lookup is a REST path on the default
  # host, where it 404s, and a 404 reads as "nothing required".
  case "$repo" in
    */*/*|''|/*|*/) _bum_refuse_shape "the repository \"$(_bum_show "$repo")\" is not owner/name"; return 1 ;;
    */*) ;;
    *) _bum_refuse_shape "the repository \"$(_bum_show "$repo")\" is not owner/name"; return 1 ;;
  esac
  # GitHub owner and repository names use letters, digits, '.', '-' and '_'
  # only. Anything else is not a repository this hook can look up, and the
  # value goes into API paths and into the command a refusal tells the user to
  # type.
  case "$repo" in
    *[!A-Za-z0-9._/-]*) _bum_refuse_shape "the repository \"$(_bum_show "$repo")\" is not owner/name"; return 1 ;;
  esac

  [ "$strat_n" -eq 1 ] || { _bum_refuse_shape "it needs exactly one of --squash, --merge or --rebase"; return 1; }

  return 0
}

# Segment once. A parse that failed says so in a marker line, because an empty
# list would read as "no merge here"; `__BD_UNBALANCED__` means the per-line
# reading is in the list too (see _bd_segments).
BD_SEGS=$(_bd_segments "$BD_CODE")
case "$BD_SEGS" in
  *__BD_SEG_FAIL__*)
    echo "BLOCKED: could not split the command into simple commands, so merge readiness cannot be verified." >&2
    echo "Next: run the merge as its own command: $_BUM_SHAPE." >&2
    exit 2 ;;
esac

MERGE_N=0
MERGE_SEL=()
MERGE_REPO=()
MERGE_AUTO=()
MERGE_STRAT=()
MERGE_DEL=()
MERGE_ADMIN=()
MERGE_MHC=()

while IFS= read -r SEG; do
  [ -z "$SEG" ] && continue
  case "$SEG" in __BD_UNBALANCED__|__BD_SEG_FAIL__) continue ;; esac
  TOK=()
  _rm_tokenise "$SEG"
  n=${#TOK[@]}
  [ "$n" -gt 0 ] || continue

  # --- is there a merge in this command, wherever gh stands? -----------------
  # gh anywhere, or a word this hook cannot read that might expand to gh, then
  # `pr merge`, `api`, or `alias`. Finding it anywhere, rather than only first,
  # is what lets `sudo gh pr merge` or `xargs gh pr merge` be refused instead of
  # passed over.
  c=-1
  kind=""
  for ((k = 0; k < n; k++)); do
    [ "${#TOK[k]}" -le 4096 ] || continue
    if _bum_is_gh "${TOK[k]}"; then
      :
    elif _bum_unreadable "${TOK[k]}" && ! _bum_is_assignment "${TOK[k]}"; then
      :
    else
      continue
    fi
    _bum_subwords $((k + 1))
    case "${SUB[0]:-} ${SUB[1]:-}" in
      "pr merge") c=$k; kind="merge"; break ;;
    esac
    case "${SUB[0]:-}" in
      api)   _bum_is_gh "${TOK[k]}" && { c=$k; kind="api"; break; } ;;
      alias) _bum_is_gh "${TOK[k]}" && { c=$k; kind="alias"; break; } ;;
    esac
  done
  [ "$c" -ge 0 ] || continue

  # --- gh api, gh alias: refused, not parsed ---------------------------------
  if [ "$kind" = "api" ]; then
    # A merge endpoint (pulls/N/merge, and repos/o/r/merges, which merges one
    # branch into another with no pull request at all), or a merge mutation by
    # name. Not the bare word: `--jq .mergeable_state` is an ordinary read, and
    # so are the fields autoMergeRequest, autoMergeAllowed and
    # viewerCanEnableAutoMerge, which is why the auto-merge mutation is matched
    # by its whole name.
    is_graphql=0
    for ((k = c + 1; k < n; k++)); do
      case "${TOK[k]}" in
        */[Mm][Ee][Rr][Gg][Ee]|*/[Mm][Ee][Rr][Gg][Ee][/?]*|*/[Mm][Ee][Rr][Gg][Ee][Ss]|*/[Mm][Ee][Rr][Gg][Ee][Ss][/?]*|\
        *[Mm]erge[Pp]ull[Rr]equest*|*[Mm]erge[Bb]ranch*|*[Ee]nable[Pp]ull[Rr]equest[Aa]uto[Mm]erge*|*[Ee]nqueue[Pp]ull[Rr]equest*)
          echo "BLOCKED: gh api on a merge endpoint or mutation. Its checks cannot be verified from here." >&2
          echo "Next: to merge, run $_BUM_SHAPE. To ask whether it merged: gh pr view <number> --repo owner/name --json mergedAt." >&2
          exit 2 ;;
        graphql|/graphql|*://*/graphql) is_graphql=1 ;;
      esac
    done
    # An endpoint that is wholly a variable or a substitution may be a merge
    # endpoint. Only the whole endpoint: `repos/$REPO/pulls/$PR` is not a merge
    # whatever it expands to, since `/merge` would have to be written, and a
    # GraphQL query with `$id` in it is a query with variables. Values of -f
    # and -F are not read for `$` either; a merge mutation is caught by name.
    # The endpoint is the first word after `api` that is not an option or an
    # option's value; gh api's own value-taking options are skipped here.
    ep=""
    seen_api=0
    for ((k = c + 1; k < n; k++)); do
      t="${TOK[k]}"
      if [ "$seen_api" = "0" ]; then [ "$t" = "api" ] && seen_api=1; continue; fi
      case "$t" in
        -X|--method|-f|--raw-field|-F|--field|-H|--header|--input|-q|--jq|-t|--template|--hostname|-p|--preview|--cache)
          k=$((k + 1)); continue ;;
        -*) continue ;;
      esac
      ep="$t"; break
    done
    case "$ep" in
      */*) ;;
      *)
        if _bum_unreadable "$ep"; then
          echo "BLOCKED: gh api with its endpoint given as \"$(_bum_show "$ep")\". Whether it merges cannot be read from the command." >&2
          echo "Next: write the endpoint literally, or merge with: $_BUM_SHAPE." >&2
          exit 2
        fi ;;
    esac
    if [ "$is_graphql" = "1" ]; then
      for ((k = c + 1; k < n; k++)); do
        case "${TOK[k]}" in
          --input|--input=*|@*|*=@*)
            echo "BLOCKED: gh api graphql with its query in a file or on stdin. Whether it merges cannot be read from the command." >&2
            echo "Next: pass the query inline, or merge with: $_BUM_SHAPE." >&2
            exit 2 ;;
        esac
      done
    fi
    continue
  fi
  if [ "$kind" = "alias" ]; then
    for ((k = c + 1; k < n; k++)); do
      case "${TOK[k]}" in
        *[Mm][Ee][Rr][Gg][Ee]*)
          echo "BLOCKED: a gh alias that mentions merge. A merge run through an alias never shows the word merge, so this hook could not check it." >&2
          echo "Next: merge with: $_BUM_SHAPE." >&2
          exit 2 ;;
      esac
    done
    continue
  fi

  # --- a merge: is it the one shape? -----------------------------------------
  # `gh pr merge --help` merges nothing. Only as an option: the value of
  # `--subject -h` is a commit subject, and after `--` a word is an argument.
  for ((k = c + 1; k < n; k++)); do
    case "${TOK[k]}" in
      --help|-h) continue 2 ;;
      --) break ;;
    esac
    _bum_takes_value "${TOK[k]}" && k=$((k + 1))
  done
  # Text that does not balance is read line by line as well (see _bd_segments),
  # and a merge found in a line that ends inside an open quote may be half of
  # one: which half gh would run cannot be read. Refused, with how to write it.
  if _bum_unterminated "$SEG"; then
    _bum_refuse "BLOCKED: gh pr merge, but the command around it does not balance its quotes, so where the merge ends cannot be read." \
      "Next: run the merge as its own command, with the number and --repo before any value that spans lines (or use --body-file): $_BUM_SHAPE."
  fi
  _bum_judge_merge || continue

  MERGE_SEL[$MERGE_N]="$sel"
  MERGE_REPO[$MERGE_N]="$repo"
  MERGE_AUTO[$MERGE_N]="$auto"
  MERGE_STRAT[$MERGE_N]="$strat"
  MERGE_DEL[$MERGE_N]="$delbr"
  MERGE_ADMIN[$MERGE_N]="$admin"
  MERGE_MHC[$MERGE_N]="$mhc"
  MERGE_N=$((MERGE_N + 1))
done <<< "$BD_SEGS"

[ "$MERGE_N" -gt 0 ] || exit 0

if ! command -v gh >/dev/null 2>&1; then
  echo "BLOCKED: gh pr merge, but the gh CLI is not on PATH — merge readiness cannot be checked." >&2
  echo "Next: install gh (https://cli.github.com), run gh auth login, then run the merge again." >&2
  exit 2
fi

# The merge as the user would type it to run it past this hook (`!` skips
# PreToolUse hooks), and as the agent would run it without --auto. Built from
# the parsed values, each of which the shape checks has no character a shell
# reads specially; a --subject or --body given to the merge is not repeated.
_bum_merge_cmd() {
  local c="gh pr merge $SEL --repo $RREPO $STRAT"
  [ "$DELBR" = "1" ] && c="$c --delete-branch"
  [ "$ADMIN" = "1" ] && c="$c --admin"
  # --match-head-commit is repeated only as a literal commit id. A value such
  # as $(git rev-parse HEAD) cannot be read here: the command leaves it out,
  # and a line on stderr says so. That line is written while the caller's
  # $(...) runs, so it comes before the line that holds the command.
  case "$MHC" in
    '') ;;
    *[!0-9A-Fa-f]*) echo "The command below leaves out --match-head-commit, whose value this hook cannot read." >&2 ;;
    *) c="$c --match-head-commit $MHC" ;;
  esac
  printf '%s' "$c"
}

# The next step for a refusal about what gh returned for the pull request.
_bum_next_inspect() {
  echo "Next: run gh pr view $PR_NUMBER --repo $RREPO --json number,baseRefName,statusCheckRollup and read what it returns. If the merge should go ahead anyway, the user must type: ! $(_bum_merge_cmd)" >&2
}

for ((M = 0; M < MERGE_N; M++)); do
  SEL="${MERGE_SEL[M]}"
  RREPO="${MERGE_REPO[M]}"
  AUTO="${MERGE_AUTO[M]}"
  STRAT="${MERGE_STRAT[M]}"
  DELBR="${MERGE_DEL[M]}"
  ADMIN="${MERGE_ADMIN[M]}"
  MHC="${MERGE_MHC[M]}"
  PR_NUMBER="$SEL"

  # The same pull request the merge names, in the repository it names. Both
  # are required by the shape above, so there is nothing left to resolve.
  # gh's stderr is kept: it is what says why the read failed.
  ERRF=$(mktemp -t flow-bum-err.XXXXXX 2>/dev/null) || ERRF=""
  ROLLUP=$(gh pr view "$SEL" --repo "$RREPO" --json "number,baseRefName,statusCheckRollup" 2>"${ERRF:-/dev/null}"); GH_RC=$?
  GH_ERR=""
  if [ -n "$ERRF" ]; then GH_ERR=$(head -c 2000 "$ERRF" 2>/dev/null); rm -f "$ERRF"; fi
  if [ "$GH_RC" -ne 0 ] || [ -z "$ROLLUP" ]; then
    echo "BLOCKED: gh pr merge $SEL --repo $RREPO, but its checks could not be read (gh exit $GH_RC: $(_bum_show "${GH_ERR:-no message}" 300)). A gate that cannot see must not open." >&2
    echo "Next: if that is an authentication error, the user must type: ! gh auth login. Otherwise run the merge again; if it fails the same way, the user must type: ! $(_bum_merge_cmd)" >&2
    exit 2
  fi
  # gh can exit 0 having printed something that is not the object expected —
  # an error body, a truncated stream. Emptiness is not the only way to fail.
  # Entries must be objects too. A rollup of `["ci"]` satisfies "is an array"
  # and then kills the classifiers below with a type error, leaving both
  # empty — which reads as "nothing wrong".
  if ! printf '%s' "$ROLLUP" | jq -e 'type == "object" and has("number") and (.statusCheckRollup | type == "array") and (all(.statusCheckRollup[]; type == "object"))' >/dev/null 2>&1; then
    echo "BLOCKED: gh pr merge $SEL --repo $RREPO, but the check rollup did not parse as expected. Refusing rather than guessing." >&2
    _bum_next_inspect
    exit 2
  fi

  PR_NUMBER=$(printf '%s' "$ROLLUP" | jq -r '.number')
  case "$PR_NUMBER" in ''|*[!0-9]*) PR_NUMBER="$SEL" ;; esac
  # Everything below that came from the API is shown through _bum_show: a
  # branch or check name is written by whoever opened the pull request.
  BASE=$(printf '%s' "$ROLLUP" | jq -r '.baseRefName // empty')
  if [ -z "$BASE" ]; then
    echo "BLOCKED: the base branch of PR #$PR_NUMBER could not be read, so its required checks cannot be established." >&2
    _bum_next_inspect
    exit 2
  fi

  # An allow-list, not a deny-list. A conclusion this does not recognise —
  # ACTION_REQUIRED and STALE were the two that got through, and GitHub can add
  # more — must land in "not passing", never in "fine". Same for an entry whose
  # __typename is missing.
  # Each classifier's exit status is checked. An empty result must mean "jq
  # looked and found none", never "jq fell over". That distinction is the whole
  # difference between a gate and a formality.
  UNFINISHED=$(printf '%s' "$ROLLUP" | jq -r '
    [ .statusCheckRollup[]
      | if .__typename == "CheckRun"
        then select(.status != "COMPLETED") | "\(.name // "check") [\(.status // "unknown" | ascii_downcase)]"
        elif .__typename == "StatusContext"
        then select(.state == "PENDING" or .state == "EXPECTED") | "\(.context // "status") [pending]"
        else "\(.name // .context // "unrecognised check") [unknown shape]"
        end ]
    | join(", ")') || {
    echo "BLOCKED: the check rollup for PR #$PR_NUMBER could not be classified. Refusing rather than guessing." >&2
    _bum_next_inspect
    exit 2
  }

  NOT_PASSING=$(printf '%s' "$ROLLUP" | jq -r '
    [ .statusCheckRollup[]
      | if .__typename == "CheckRun"
        then select(.status == "COMPLETED")
             | select((.conclusion // "") | IN("SUCCESS","SKIPPED","NEUTRAL") | not)
             | "\(.name // "check") [\(.conclusion // "no conclusion" | ascii_downcase)]"
        elif .__typename == "StatusContext"
        then select(.state != "PENDING" and .state != "EXPECTED" and .state != "SUCCESS")
             | "\(.context // "status") [\(.state // "unknown" | ascii_downcase)]"
        else empty
        end ]
    | join(", ")') || {
    echo "BLOCKED: the check rollup for PR #$PR_NUMBER could not be classified. Refusing rather than guessing." >&2
    _bum_next_inspect
    exit 2
  }

  TOTAL=$(printf '%s' "$ROLLUP" | jq -r '.statusCheckRollup | length') || TOTAL=""
  case "$TOTAL" in
    ''|*[!0-9]*)
      echo "BLOCKED: could not count the checks on PR #$PR_NUMBER." >&2
      _bum_next_inspect
      exit 2 ;;
  esac

  if [ -n "$UNFINISHED" ]; then
    echo "BLOCKED: PR #$PR_NUMBER has checks that have not finished: $(_bum_show "$UNFINISHED" 1000)" >&2
    echo "Next: wait for them (gh pr checks $PR_NUMBER --repo $RREPO --watch), then run the merge again." >&2
    exit 2
  fi
  if [ -n "$NOT_PASSING" ]; then
    echo "BLOCKED: PR #$PR_NUMBER has checks that did not pass: $(_bum_show "$NOT_PASSING" 1000)" >&2
    echo "Next: fix them and push, then run the merge again once they pass. To merge with them failing, the user must type: ! $(_bum_merge_cmd)" >&2
    exit 2
  fi

  # What does this base branch require? Both branch protection and rulesets,
  # because asking only the first reports "none required" on a repository that
  # requires plenty. The endpoints are also consulted for the empty-rollup case
  # below, so the probe runs whether or not --auto was asked for.
  #
  # `gh api` exits 1 for every HTTP error, so the status is read from gh's
  # stderr, "(HTTP 403)", and GitHub's message from the error body gh prints on
  # stdout. Two answers are definite:
  #   - 404: nothing is configured on this branch.
  #   - 403 "Upgrade to GitHub Pro or make this repository public to enable
  #     this feature.": a private repository on the free plan, which can have
  #     neither branch protection nor rulesets, so nothing can be required.
  #     Reading it as "cannot tell" refused every checkless merge there for
  #     ever (#310).
  # Anything else is "cannot tell", in one of three kinds: permission (any
  # other 401 or 403, which a retry does not change), network or rate limit
  # (no HTTP status, 429, 5xx, or a message about a rate limit, which a retry
  # can change), and other.
  # Sets REQ_STATE (read, absent, unknown), REQ_OUT (the required checks, a
  # JSON array of names: a check name can hold ", "),
  # REQ_WHY (the status, GitHub's message and the kind, for a refusal), and
  # REQ_KIND for an unknown answer. REQ_PLAN and REQ_RATE are set, never
  # cleared, when a lookup answered the plan limit or a rate limit.
  _bum_required() {   # $1 = endpoint, $2 = jq filter, $3 = the JSON type of a real answer
    local body errf rc err status msg
    REQ_STATE="unknown"; REQ_OUT="[]"; REQ_WHY=""; REQ_KIND="other"
    if ! errf=$(mktemp -t flow-bum-err.XXXXXX 2>/dev/null); then
      REQ_WHY="not asked: a temporary file could not be created (other)"; return
    fi
    body=$(gh api "$1" 2>"$errf"); rc=$?
    err=$(head -c 2000 "$errf" 2>/dev/null); rm -f "$errf"
    if [ "$rc" -eq 0 ]; then
      # jq reads an empty answer as no input and succeeds, and reads two
      # documents one after the other, so the answer must first be exactly one
      # JSON value of the type the endpoint returns.
      if printf '%s' "$body" | jq -se --arg t "$3" 'length == 1 and (.[0] | type) == $t' >/dev/null 2>&1 \
         && REQ_OUT=$(printf '%s' "$body" | jq -c "$2" 2>/dev/null) \
         && [ -n "$REQ_OUT" ]; then
        REQ_STATE="read"
        REQ_WHY="read, requires $(printf '%s' "$REQ_OUT" | jq -r 'if length == 0 then "nothing" else join(", ") end' 2>/dev/null)"
        REQ_WHY=$(_bum_show "$REQ_WHY" 300)
      else
        REQ_OUT="[]"
        REQ_WHY="gh exit 0, but the answer did not parse (other)"
      fi
      return
    fi
    status=$(printf '%s\n' "$err" | sed -n 's/.*(HTTP \([0-9][0-9][0-9]\)).*/\1/p' | head -n 1)
    msg=$(printf '%s' "$body" | jq -r 'if type == "object" then (.message // empty) else empty end' 2>/dev/null)
    if [ -z "$msg" ]; then
      msg=$(printf '%s\n' "$err" | sed '/^[[:space:]]*$/d' | head -n 1)
      msg="${msg#gh: }"
      msg="${msg% (HTTP [0-9][0-9][0-9])}"
    fi
    if [ -n "$status" ]; then
      REQ_WHY="HTTP $status, \"$(_bum_show "${msg:-no message}" 300)\""
    else
      REQ_WHY="no HTTP response, \"$(_bum_show "${msg:-no message}" 300)\""
    fi
    if [ "$status" = "404" ]; then
      REQ_STATE="absent"; REQ_WHY="$REQ_WHY (nothing configured)"; return
    fi
    case "$msg" in
      *[Rr]ate\ limit*) REQ_RATE=1; REQ_KIND="network or rate limit" ;;
      *)
        case "$status" in
          403)
            case "$msg" in
              *"Upgrade to GitHub Pro"*|*"make this repository public"*)
                REQ_STATE="absent"; REQ_PLAN=1
                REQ_WHY="$REQ_WHY (plan limit: nothing can be required here)"; return ;;
            esac
            REQ_KIND="permission" ;;
          401) REQ_KIND="permission" ;;
          ''|429|5[0-9][0-9]) REQ_KIND="network or rate limit" ;;
          *) REQ_KIND="other" ;;
        esac ;;
    esac
    REQ_WHY="$REQ_WHY ($REQ_KIND)"
  }

  REQUIRED=""        # the required checks, as a reader sees them
  REQ_LIST="[]"      # the same, a JSON array of names
  REQ_READABLE=0
  REQ_PLAN=0
  REQ_RATE=0
  REQ_RETRYABLE=0
  REQ_OTHER=0
  REQ_UNKNOWN=0
  REQ_EVIDENCE=""
  # The branch name goes into a URL path: `#` would end it and `%` would start
  # an escape, so gh would ask about another branch. A `/` stays a `/`, which
  # is how GitHub reads a branch name with one in it.
  if ! BASE_PATH=$(jq -rn --arg b "$BASE" '$b | @uri | gsub("%2F"; "/")' 2>/dev/null) || [ -z "$BASE_PATH" ]; then
    echo "BLOCKED: the base branch of PR #$PR_NUMBER, '$(_bum_show "$BASE")', could not be written into a lookup, so its required checks cannot be established." >&2
    _bum_next_inspect
    exit 2
  fi
  # Each filter fails on a field of the wrong type, so a malformed answer is
  # "did not parse" rather than "nothing required".
  _bum_required "repos/$RREPO/branches/$BASE_PATH/protection/required_status_checks" \
    '(if .contexts == null then [] else .contexts end) as $c
     | (if .checks == null then [] else .checks end) as $k
     | if ($c | type) == "array" and ($k | type) == "array"
          and all($c[]; type == "string" and length > 0)
          and all($k[]; type == "object" and (.context | type) == "string" and (.context | length) > 0)
       then [$c[], ($k[] | .context)] | unique else error("shape") end' object
  [ "$REQ_STATE" != "unknown" ] && REQ_READABLE=1
  [ "$REQ_STATE" = "unknown" ] && REQ_UNKNOWN=1
  [ "$REQ_STATE" = "unknown" ] && [ "$REQ_KIND" = "network or rate limit" ] && REQ_RETRYABLE=1
  [ "$REQ_STATE" = "unknown" ] && [ "$REQ_KIND" = "other" ] && REQ_OTHER=1
  REQ_EVIDENCE="  branch protection: $REQ_WHY"
  REQ_LIST="$REQ_OUT"
  # Without --admin, checks required by branch protection are enough to go on:
  # GitHub enforces the rulesets' own on merge. --admin skips that, so then
  # the rulesets are always read too.
  if [ "$REQ_LIST" = "[]" ] || [ "$ADMIN" = "1" ]; then
    _bum_required "repos/$RREPO/rules/branches/$BASE_PATH" \
      'if all(.[]; type == "object") then
         [ .[] | select(.type == "required_status_checks") | .parameters.required_status_checks
           | if type == "array" and all(.[]; type == "object" and (.context | type) == "string" and (.context | length) > 0)
             then .[].context else error("shape") end ] | unique
       else error("shape") end' array
    [ "$REQ_STATE" != "unknown" ] && REQ_READABLE=1
    [ "$REQ_STATE" = "unknown" ] && REQ_UNKNOWN=1
    [ "$REQ_STATE" = "unknown" ] && [ "$REQ_KIND" = "network or rate limit" ] && REQ_RETRYABLE=1
    [ "$REQ_STATE" = "unknown" ] && [ "$REQ_KIND" = "other" ] && REQ_OTHER=1
    REQ_EVIDENCE="$REQ_EVIDENCE
  rulesets: $REQ_WHY"
    if ! REQ_LIST=$(jq -cn --argjson a "$REQ_LIST" --argjson b "$REQ_OUT" '$a + $b | unique' 2>/dev/null); then
      echo "BLOCKED: the required checks of '$(_bum_show "$BASE")' could not be combined, so they cannot be established." >&2
      _bum_next_inspect
      exit 2
    fi
  fi
  if ! REQUIRED=$(printf '%s' "$REQ_LIST" | jq -r 'join(", ")' 2>/dev/null); then
    echo "BLOCKED: the required checks of '$(_bum_show "$BASE")' could not be read back, so they cannot be established." >&2
    _bum_next_inspect
    exit 2
  fi

  # The next step when what the base requires could not be established.
  _bum_next_unknown() {
    if [ "$REQ_RETRYABLE" = "1" ]; then
      local rate=""
      [ "$REQ_RATE" = "1" ] && rate=" (gh api rate_limit shows when the limit resets)"
      echo "This may change on retry." >&2
      echo "Next: wait a minute$rate, then run the merge again. If it keeps failing, the user must type: ! $(_bum_merge_cmd)" >&2
    elif [ "$REQ_OTHER" = "1" ]; then
      # An answer of no known kind: whether a retry changes it is not known.
      echo "Next: run the merge again once. If it is refused the same way, the user must type: ! $(_bum_merge_cmd)" >&2
    else
      echo "This will not change on retry." >&2
      echo "Next: the user must type: ! $(_bum_merge_cmd)" >&2
    fi
  }

  # --admin merges past GitHub's own enforcement of required checks, which the
  # rules below rely on when one lookup answered and the other did not. So with
  # --admin both must answer. A required check that is not on the PR at all is
  # not refused here: merging past such a check is what --admin is for.
  if [ "$ADMIN" = "1" ]; then
    if [ "$REQ_UNKNOWN" = "1" ]; then
      echo "BLOCKED: gh pr merge --admin on PR #$PR_NUMBER, and what '$(_bum_show "$BASE")' requires could not be fully established:" >&2
      echo "$REQ_EVIDENCE" >&2
      echo "--admin skips GitHub's own check that required checks passed, so the hook needs both answers." >&2
      _bum_next_unknown
      exit 2
    fi
  fi

  # An empty rollup is "no checks" on a repository with no CI, and "not
  # reported yet" in the seconds after a push. Where the base requires checks,
  # the second reading is the one that matters.
  if [ "$TOTAL" = "0" ]; then
    if [ -n "$REQUIRED" ]; then
      echo "BLOCKED: PR #$PR_NUMBER reports no checks yet, but '$(_bum_show "$BASE")' requires: $(_bum_show "$REQUIRED" 1000)" >&2
      echo "They have not been created on this commit." >&2
      echo "Next: wait for them to appear and finish (gh pr checks $PR_NUMBER --repo $RREPO --watch), then run the merge again." >&2
      exit 2
    fi
    # An empty rollup means "no CI here" on a repository with none, and "not
    # reported yet" in the seconds after a push — which is the window this hook
    # was written for. Telling them apart depends on knowing what the base
    # requires, so when that could not be read, neither reading is available.
    # One definite answer is enough without --admin (above): GitHub itself
    # refuses a merge that misses a required check, and this hook is for the
    # merge it would let through.
    if [ "$REQ_READABLE" = "0" ]; then
      echo "BLOCKED: PR #$PR_NUMBER reports no checks, and whether '$(_bum_show "$BASE")' requires any could not be established:" >&2
      echo "$REQ_EVIDENCE" >&2
      echo "No checks yet and no checks at all look identical from here." >&2
      _bum_next_unknown
      exit 2
    fi
  fi

  # Here one unread lookup is enough to refuse: "requires no status checks"
  # would be a claim about both.
  if [ "$AUTO" = "1" ] && [ -z "$REQUIRED" ]; then
    if [ "$REQ_UNKNOWN" = "1" ]; then
      echo "BLOCKED: --auto on PR #$PR_NUMBER, but whether '$(_bum_show "$BASE")' requires any checks could not be established:" >&2
      echo "$REQ_EVIDENCE" >&2
      echo "Auto-merge waits only for required checks, so this cannot be established as a wait. Every check on this PR has already passed ($TOTAL of $TOTAL)." >&2
    else
      echo "BLOCKED: --auto on PR #$PR_NUMBER, but '$(_bum_show "$BASE")' requires no status checks." >&2
      if [ "$REQ_PLAN" = "1" ]; then
        echo "GitHub answered that this repository's plan cannot require checks on a private repository, so none will ever be required here." >&2
      fi
      echo "Auto-merge waits for REQUIRED checks. With none required it merges immediately, which is the opposite of what --auto is usually reached for." >&2
      if [ "$TOTAL" = "0" ]; then
        echo "This pull request has no checks at all, so there is nothing to wait for." >&2
      else
        echo "Every check on this PR has already passed ($TOTAL of $TOTAL)." >&2
      fi
    fi
    echo "Next: merge without --auto: $(_bum_merge_cmd)" >&2
    exit 2
  fi
done
