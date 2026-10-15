#!/usr/bin/env bash
# snap-target.sh — works out what /snap reviews.
#
# Usage: snap-target.sh [target]
#
# The target is one argument: none (or blank) for the current branch, or a ref
# range, a commit, or a path. /snap runs this script with no argument from its
# `!` block, and Claude runs it with the user's argument as one single-quoted
# word. The argument is never pasted into shell text that a shell parses.
#
# Prints KEY=value lines:
#   THANOS_SCRIPT=<path of this script, as invoked>
#   THANOS_TARGET=diff|design|files|none
#   THANOS_WHAT=<one-line description of the target>
#   THANOS_READ=<a git command made only of commit ids, or an absolute path>
#   THANOS_UNTRACKED=<absolute path> (zero or more; untracked files in the change)
#   THANOS_NOTHING=<one-line reason> (only when THANOS_TARGET=none)
#
# Read-only: it runs only git commands that inspect the repository. Every git
# failure ends in THANOS_TARGET=none with a reason; git's own messages are not
# printed. No value printed holds a control character, so each value is one
# line and the output is always the lines above.

# An exported CDPATH would send a relative `cd` somewhere else and make it print.
unset CDPATH

case "$0" in
  /*) _self=$0 ;;
  *) _self=$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0") ;;
esac

_none() { printf 'THANOS_TARGET=none\nTHANOS_NOTHING=%s\n' "$1"; exit 0; }

# _clean <text>: true when <text> holds no control character (newline, CR,
# tab, escape and the rest), so it prints as one line and cannot start a
# KEY=value line of its own.
_clean() { case "$1" in *[[:cntrl:]]*) return 1 ;; esac; return 0; }

# Lines after THANOS_SCRIPT are collected in _out and printed at the end, so a
# value refused halfway leaves no partial target behind.
_out=""
# _emit <KEY> <value>: adds KEY=value, or stops when the value is not clean.
_emit() {
  _clean "$2" || _none "Nothing to review: a name in the target holds a control character, which cannot be handed over safely."
  _out="$_out$1=$2
"
}

_clean "$_self" || _none "Nothing to review: the path of this script holds a control character."
printf 'THANOS_SCRIPT=%s\n' "$_self"

command -v git >/dev/null 2>&1 || _none "Nothing to review: git is not installed."
[ "$#" -le 1 ] || _none "Nothing to review: pass one target (a ref range, a commit or a path) as one argument."

_raw=${1-}
_clean "$_raw" || _none "Nothing to review: pass one target on one line."
# A path is taken as given when it exists, so a name with leading or trailing
# spaces still works; anything else is trimmed.
if [ -n "$_raw" ] && [ -e "$_raw" ]; then _arg=$_raw
else _arg=$(printf '%s' "$_raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
fi

# `git rev-parse --is-inside-work-tree` exits 0 and prints "false" in a bare
# repository and inside .git, so the printed answer is what counts.
_in_git() { [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; }
_shallow() { [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = true ]; }

# _changed <args...>: 0 when `git diff --quiet <args>` finds changes, 1 when it
# finds none. Any other exit is a git failure and stops with a reason, rather
# than being read as "there are changes".
_changed() {
  git diff --quiet "$@" >/dev/null 2>&1
  case $? in
    0) return 1 ;;
    1) return 0 ;;
    *) _none "Nothing to review: git diff failed on this repository." ;;
  esac
}

# _commit <rev>: prints the commit id <rev> names, or nothing. <rev> is
# resolved first and only its id is peeled: a :/<regex> revision takes the
# rest of the string as its regex, so "<rev>^{commit}" would search for it.
_commit() {
  local id
  id=$(git rev-parse --verify --quiet "$1" 2>/dev/null) || return 1
  git rev-parse --verify --quiet "$id^{commit}" 2>/dev/null
}

# _stat <args...>: " (<shortstat>)" for git diff <args>, or nothing when empty.
_stat() {
  local s
  s=$(git diff --shortstat "$@" 2>/dev/null | sed 's/^ *//')
  [ -z "$s" ] || printf ' (%s)' "$s"
}

# _abs <path>: the absolute path of an existing file or directory, or nothing
# when it cannot be entered.
_abs() {
  local d
  if [ -d "$1" ]; then (cd "$1" 2>/dev/null && pwd -P)
  else d=$(cd "$(dirname "$1")" 2>/dev/null && pwd -P) && printf '%s/%s\n' "$d" "$(basename "$1")"
  fi
}

# _subject <id>: the commit's subject without control characters, at most 100
# characters. It is a label taken from the repository.
_subject() { git log -1 --format=%s "$1" 2>/dev/null | tr -d '[:cntrl:]' | cut -c1-100; }

_unknown() {
  if _shallow; then _none "Nothing to review: '$_arg' is not a path or a git ref in this shallow clone; fetch more history if it should be."; fi
  _none "Nothing to review: '$_arg' is not a path or a git ref."
}

if [ -n "$_arg" ] && [ "${_arg#-}" != "$_arg" ]; then
  # A leading dash would reach git as an option (git diff --output=<file> writes to disk).
  _none "Nothing to review: '$_arg' is not a path or a git ref."
elif [ -z "$_arg" ]; then
  _in_git || _none "Nothing to review: not inside a git work tree."
  _commit HEAD >/dev/null || _none "Nothing to review: this repository has no commits yet."
  # Default branch: the remote's HEAD, then init.defaultBranch, then main or
  # master. A remote HEAD that names a branch which no longer exists is skipped.
  _base=""
  for _r in $(git remote 2>/dev/null); do
    _h=$(git symbolic-ref --quiet --short "refs/remotes/$_r/HEAD" 2>/dev/null) || continue
    if _commit "$_h" >/dev/null; then _base=$_h; break; fi
  done
  if [ -z "$_base" ]; then
    for _b in "$(git config --get init.defaultBranch 2>/dev/null)" main master; do
      [ -n "$_b" ] || continue
      if _commit "refs/remotes/origin/$_b" >/dev/null; then _base="origin/$_b"; break; fi
      if _commit "refs/heads/$_b" >/dev/null; then _base=$_b; break; fi
    done
  fi
  [ -n "$_base" ] || _none "Nothing to review: cannot detect the default branch; pass a ref range such as <base>..HEAD."
  if ! _mb=$(git merge-base "$_base" HEAD 2>/dev/null); then
    _shallow && _none "Nothing to review: this is a shallow clone without the history shared with $_base; fetch more history or pass a ref range."
    _none "Nothing to review: HEAD shares no history with $_base."
  fi
  # Untracked files are listed from the top of the work tree, so a run from a
  # subdirectory sees the same change as a run from the top. -z keeps every
  # name exactly as it is, with no quoting.
  _top=$(git rev-parse --show-toplevel 2>/dev/null) || _none "Nothing to review: cannot find the top of the work tree."
  git -C "$_top" ls-files --others --exclude-standard >/dev/null 2>&1 \
    || _none "Nothing to review: git could not list untracked files."
  _n=0; _ulines=""
  while IFS= read -r -d '' _f; do
    _clean "$_f" || _none "Nothing to review: an untracked file name holds a control character, which cannot be handed over safely; rename it or pass a ref range."
    _n=$((_n + 1))
    _ulines="$_ulines$_top/$_f
"
  done < <(git -C "$_top" ls-files -z --others --exclude-standard 2>/dev/null)
  if ! _changed "$_mb" && [ "$_n" = 0 ]; then
    _none "Nothing to review: no changes against $_base."
  fi
  _branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
  _desc=$(git diff --shortstat "$_mb" 2>/dev/null | sed 's/^ *//')
  [ "$_n" = 0 ] || _desc="${_desc:+$_desc, }$_n untracked file(s)"
  _emit THANOS_TARGET diff
  _emit THANOS_WHAT "$_branch vs $_base, committed and uncommitted changes ($_desc)"
  _emit THANOS_READ "git diff $_mb"
  while IFS= read -r _f; do
    [ -z "$_f" ] || _emit THANOS_UNTRACKED "$_f"
  done <<EOF
$_ulines
EOF
elif [ -f "$_arg" ] || [ -d "$_arg" ]; then
  _p=$(_abs "$_arg")
  [ -n "$_p" ] || _none "Nothing to review: cannot read '$_arg'."
  if [ -f "$_arg" ]; then
    case "$_arg" in
      *.md|*.MD|*.markdown) _emit THANOS_TARGET design; _emit THANOS_WHAT "design document $_arg" ;;
      *) _emit THANOS_TARGET files; _emit THANOS_WHAT "$_arg as it stands" ;;
    esac
  else
    _emit THANOS_TARGET files; _emit THANOS_WHAT "$_arg as it stands"
  fi
  _emit THANOS_READ "$_p"
elif ! _in_git; then
  _none "Nothing to review: '$_arg' is not a path, and this is not a git work tree."
else
  case "$_arg" in
    *..*)
      # Both ends are resolved to commit ids, so THANOS_READ never carries the
      # argument's own text (a revision such as :/<regex> may hold any character).
      case "$_arg" in
        *...*) _left=${_arg%%...*}; _right=${_arg#*...}; _three=1 ;;
        *) _left=${_arg%%..*}; _right=${_arg#*..}; _three=0 ;;
      esac
      _l=$(_commit "${_left:-HEAD}"); _r=""
      case "$_right" in -*) ;; *) _r=$(_commit "${_right:-HEAD}") ;; esac
      [ -n "$_l" ] && [ -n "$_r" ] || _unknown
      if [ "$_three" = 1 ]; then
        _l=$(git merge-base "$_l" "$_r" 2>/dev/null) || _none "Nothing to review: the two sides of '$_arg' share no history."
      fi
      _changed "$_l" "$_r" || _none "Nothing to review: $_arg has no changes."
      _emit THANOS_TARGET diff
      _emit THANOS_WHAT "$_arg$(_stat "$_l" "$_r")"
      _emit THANOS_READ "git diff $_l $_r" ;;
    *)
      _sha=$(_commit "$_arg")
      [ -n "$_sha" ] || _unknown
      _short=$(git rev-parse --short "$_sha" 2>/dev/null); _short=${_short:-$_sha}
      # In a shallow clone, the oldest commit fetched looks like it added every
      # file; its real parent is not here.
      _sfile=$(git rev-parse --git-path shallow 2>/dev/null)
      if _shallow && [ -n "$_sfile" ] && grep -qx "$_sha" "$_sfile" 2>/dev/null; then
        _none "Nothing to review: commit $_short is the oldest commit in this shallow clone and its parent is missing; fetch more history."
      fi
      # A merge commit is reviewed against its first parent: what it brought in.
      _p1=$(git rev-parse --verify --quiet "$_sha^2" >/dev/null 2>&1 && git rev-parse --verify --quiet "$_sha^1" 2>/dev/null)
      if [ -n "$_p1" ]; then
        _changed "$_p1" "$_sha" || _none "Nothing to review: merge commit $_arg brought in no changes."
        _emit THANOS_TARGET diff
        _emit THANOS_WHAT "merge commit $_short $(_subject "$_sha"), against its first parent$(_stat "$_p1" "$_sha")"
        _emit THANOS_READ "git diff $_p1 $_sha"
      else
        git diff-tree --quiet --root --no-commit-id -r "$_sha" >/dev/null 2>&1
        case $? in
          0) _none "Nothing to review: commit $_arg has no changes." ;;
          1) ;;
          *) _none "Nothing to review: git could not read commit $_arg." ;;
        esac
        _emit THANOS_TARGET diff
        _emit THANOS_WHAT "commit $_short $(_subject "$_sha")"
        _emit THANOS_READ "git show $_sha"
      fi ;;
  esac
fi
printf '%s' "$_out"
exit 0
