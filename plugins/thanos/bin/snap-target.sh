#!/usr/bin/env bash
# snap-target.sh — works out what /snap reviews, from the command's argument.
#
# Reads the argument on stdin and prints KEY=value lines:
#   THANOS_TARGET=diff|design|files|none
#   THANOS_WHAT=<one-line description of the target>
#   THANOS_READ=<git command to run, or path to read>
#   THANOS_UNTRACKED=<path>        (zero or more; untracked files in the change)
#   THANOS_NOTHING=<one-line reason> (only when THANOS_TARGET=none)
#
# Read-only: it runs only git commands that inspect the repository.

# The argument arrives on stdin, never on the command line, so nothing in it
# is expanded or executed by a shell.
_arg=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | head -n 1)
_none() { printf 'THANOS_TARGET=none\nTHANOS_NOTHING=%s\n' "$1"; }
_in_git() { git rev-parse --is-inside-work-tree >/dev/null 2>&1; }

if [ -n "$_arg" ] && [ "${_arg#-}" != "$_arg" ]; then
  # A leading dash would reach git as an option (git diff --output=<file> writes to disk).
  _none "Nothing to review: '$_arg' is not a path or a git ref."
elif [ -z "$_arg" ]; then
  if ! _in_git; then
    _none "Nothing to review: not inside a git repository."
  elif ! git rev-parse --verify --quiet 'HEAD^{commit}' >/dev/null; then
    _none "Nothing to review: this repository has no commits yet."
  else
    # Default branch: the remote's HEAD, then init.defaultBranch, then main or master.
    _base=""
    for _r in $(git remote 2>/dev/null); do
      _h=$(git symbolic-ref --quiet --short "refs/remotes/$_r/HEAD" 2>/dev/null) && { _base=$_h; break; }
    done
    if [ -z "$_base" ]; then
      for _b in "$(git config --get init.defaultBranch 2>/dev/null)" main master; do
        [ -n "$_b" ] || continue
        if git rev-parse --verify --quiet "refs/remotes/origin/$_b" >/dev/null; then _base="origin/$_b"; break; fi
        if git rev-parse --verify --quiet "refs/heads/$_b" >/dev/null; then _base=$_b; break; fi
      done
    fi
    if [ -z "$_base" ]; then
      _none "Nothing to review: cannot detect the default branch; pass a ref range such as <base>..HEAD."
    else
      _mb=$(git merge-base "$_base" HEAD 2>/dev/null)
      _untracked=$(git ls-files --others --exclude-standard)
      if [ -z "$_mb" ]; then
        _none "Nothing to review: HEAD shares no history with $_base."
      elif git diff --quiet "$_mb" && [ -z "$_untracked" ]; then
        _none "Nothing to review: no changes against $_base."
      else
        _branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse --short HEAD)
        printf 'THANOS_TARGET=diff\n'
        printf 'THANOS_WHAT=%s vs %s, committed and uncommitted changes (%s)\n' "$_branch" "$_base" "$(git diff --shortstat "$_mb" | sed 's/^ *//')"
        printf 'THANOS_READ=git diff %s\n' "$_mb"
        [ -z "$_untracked" ] || printf '%s\n' "$_untracked" | sed 's/^/THANOS_UNTRACKED=/'
      fi
    fi
  fi
elif [ -f "$_arg" ]; then
  case "$_arg" in
    *.md|*.MD|*.markdown) printf 'THANOS_TARGET=design\nTHANOS_WHAT=design document %s\n' "$_arg" ;;
    *) printf 'THANOS_TARGET=files\nTHANOS_WHAT=%s as it stands\n' "$_arg" ;;
  esac
  printf 'THANOS_READ=%s\n' "$_arg"
elif [ -d "$_arg" ]; then
  printf 'THANOS_TARGET=files\nTHANOS_WHAT=%s as it stands\nTHANOS_READ=%s\n' "$_arg" "$_arg"
elif ! _in_git; then
  _none "Nothing to review: '$_arg' is not a path, and this is not a git repository."
else
  case "$_arg" in
    *..*)
      if ! git rev-parse --quiet "$_arg" >/dev/null 2>&1; then
        _none "Nothing to review: '$_arg' is not a path or a git ref."
      elif git diff --quiet "$_arg" 2>/dev/null; then
        _none "Nothing to review: $_arg has no changes."
      else
        printf 'THANOS_TARGET=diff\nTHANOS_WHAT=%s (%s)\nTHANOS_READ=git diff %s\n' "$_arg" "$(git diff --shortstat "$_arg" | sed 's/^ *//')" "$_arg"
      fi ;;
    *)
      _sha=$(git rev-parse --verify --quiet "$_arg^{commit}" 2>/dev/null)
      if [ -z "$_sha" ]; then
        _none "Nothing to review: '$_arg' is not a path or a git ref."
      elif [ -z "$(git show --format= --name-only "$_sha")" ]; then
        _none "Nothing to review: commit $_arg has no changes."
      else
        printf 'THANOS_TARGET=diff\nTHANOS_WHAT=commit %s %s\nTHANOS_READ=git show %s\n' "$(git rev-parse --short "$_sha")" "$(git log -1 --format=%s "$_sha")" "$_sha"
      fi ;;
  esac
fi
exit 0
