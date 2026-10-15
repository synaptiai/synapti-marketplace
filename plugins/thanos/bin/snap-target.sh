#!/usr/bin/env bash
# snap-target.sh — works out what /snap reviews.
#
# Usage: snap-target.sh [target]
#
# The target is one argument: none for the current branch, or a ref range, a
# commit, or a path. /snap runs this script with no argument from its `!`
# block, and Claude runs it with the user's argument as one single-quoted
# word. The argument is never pasted into shell text that a shell parses.
#
# Prints KEY=value lines:
#   THANOS_SCRIPT=<absolute path of this script>
#   THANOS_TARGET=diff|design|files|none
#   THANOS_WHAT=<one-line description of the target>
#   THANOS_READ=<a git command made only of commit ids, or an absolute path>
#   THANOS_UNTRACKED=<absolute path> (zero or more; untracked files in the change)
#   THANOS_NOTHING=<one-line reason> (only when THANOS_TARGET=none)
#
# Read-only: it runs only git commands that inspect the repository. Every git
# failure ends in THANOS_TARGET=none with a reason; git's own messages are not
# printed, so the output is always the lines above.

_self=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)/$(basename "$0")
printf 'THANOS_SCRIPT=%s\n' "$_self"

_none() { printf 'THANOS_TARGET=none\nTHANOS_NOTHING=%s\n' "$1"; exit 0; }

command -v git >/dev/null 2>&1 || _none "Nothing to review: git is not installed."
[ "$#" -le 1 ] || _none "Nothing to review: pass one target (a ref range, a commit or a path) as one argument."

_nl='
'
_cr=$(printf '\r')
_arg=${1-}
case "$_arg" in
  *"$_nl"*|*"$_cr"*) _none "Nothing to review: pass one target on one line." ;;
esac
_arg=$(printf '%s' "$_arg" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

# `git rev-parse --is-inside-work-tree` exits 0 and prints "false" in a bare
# repository and inside .git, so the printed answer is what counts.
_in_git() { [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; }

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

# _commit <rev>: prints the commit id <rev> names, or nothing.
_commit() { git rev-parse --verify --quiet "$1^{commit}" 2>/dev/null; }

# _stat <args...>: " (<shortstat>)" for git diff <args>, or nothing when empty.
_stat() {
  local s
  s=$(git diff --shortstat "$@" 2>/dev/null | sed 's/^ *//')
  [ -z "$s" ] || printf ' (%s)' "$s"
}

# _abs <path>: the absolute path of an existing file or directory.
_abs() {
  if [ -d "$1" ]; then (cd "$1" 2>/dev/null && pwd -P)
  else printf '%s/%s\n' "$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" "$(basename "$1")"
  fi
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
    if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
      _none "Nothing to review: this is a shallow clone without the history shared with $_base; fetch more history or pass a ref range."
    fi
    _none "Nothing to review: HEAD shares no history with $_base."
  fi
  # Untracked files are listed from the top of the work tree, so a run from a
  # subdirectory sees the same change as a run from the top.
  _top=$(git rev-parse --show-toplevel 2>/dev/null) || _none "Nothing to review: cannot find the top of the work tree."
  _untracked=$(git -C "$_top" -c core.quotePath=off ls-files --others --exclude-standard 2>/dev/null) \
    || _none "Nothing to review: git could not list untracked files."
  if ! _changed "$_mb" && [ -z "$_untracked" ]; then
    _none "Nothing to review: no changes against $_base."
  fi
  _branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse --short HEAD)
  _n=0; [ -z "$_untracked" ] || _n=$(printf '%s\n' "$_untracked" | wc -l | tr -d ' ')
  _desc=$(git diff --shortstat "$_mb" 2>/dev/null | sed 's/^ *//')
  [ "$_n" = 0 ] || _desc="${_desc:+$_desc, }$_n untracked file(s)"
  printf 'THANOS_TARGET=diff\n'
  printf 'THANOS_WHAT=%s vs %s, committed and uncommitted changes (%s)\n' "$_branch" "$_base" "$_desc"
  printf 'THANOS_READ=git diff %s\n' "$_mb"
  [ -z "$_untracked" ] || printf '%s\n' "$_untracked" | sed "s|^|THANOS_UNTRACKED=$_top/|"
elif [ -f "$_arg" ]; then
  case "$_arg" in
    *.md|*.MD|*.markdown) printf 'THANOS_TARGET=design\nTHANOS_WHAT=design document %s\n' "$_arg" ;;
    *) printf 'THANOS_TARGET=files\nTHANOS_WHAT=%s as it stands\n' "$_arg" ;;
  esac
  printf 'THANOS_READ=%s\n' "$(_abs "$_arg")"
elif [ -d "$_arg" ]; then
  printf 'THANOS_TARGET=files\nTHANOS_WHAT=%s as it stands\nTHANOS_READ=%s\n' "$_arg" "$(_abs "$_arg")"
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
      [ -n "$_l" ] && [ -n "$_r" ] || _none "Nothing to review: '$_arg' is not a path or a git ref."
      if [ "$_three" = 1 ]; then
        _l=$(git merge-base "$_l" "$_r" 2>/dev/null) || _none "Nothing to review: the two sides of '$_arg' share no history."
      fi
      _changed "$_l" "$_r" || _none "Nothing to review: $_arg has no changes."
      printf 'THANOS_TARGET=diff\nTHANOS_WHAT=%s%s\nTHANOS_READ=git diff %s %s\n' "$_arg" "$(_stat "$_l" "$_r")" "$_l" "$_r" ;;
    *)
      _sha=$(_commit "$_arg")
      [ -n "$_sha" ] || _none "Nothing to review: '$_arg' is not a path or a git ref."
      _subject=$(git log -1 --format=%s "$_sha" 2>/dev/null)
      _short=$(git rev-parse --short "$_sha" 2>/dev/null)
      # A merge commit is reviewed against its first parent: what it brought in.
      _p1=$(git rev-parse --verify --quiet "$_sha^2" >/dev/null 2>&1 && git rev-parse --verify --quiet "$_sha^1" 2>/dev/null)
      if [ -n "$_p1" ]; then
        _changed "$_p1" "$_sha" || _none "Nothing to review: merge commit $_arg brought in no changes."
        printf 'THANOS_TARGET=diff\nTHANOS_WHAT=merge commit %s %s, against its first parent%s\nTHANOS_READ=git diff %s %s\n' \
          "$_short" "$_subject" "$(_stat "$_p1" "$_sha")" "$_p1" "$_sha"
      else
        git diff-tree --quiet --root --no-commit-id -r "$_sha" >/dev/null 2>&1
        case $? in
          0) _none "Nothing to review: commit $_arg has no changes." ;;
          1) ;;
          *) _none "Nothing to review: git could not read commit $_arg." ;;
        esac
        printf 'THANOS_TARGET=diff\nTHANOS_WHAT=commit %s %s\nTHANOS_READ=git show %s\n' "$_short" "$_subject" "$_sha"
      fi ;;
  esac
fi
exit 0
