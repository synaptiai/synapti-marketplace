# shellcheck shell=bash
# [flow] lib/tier-trail.sh — writes tier breadcrumbs to the auto-log trail.
# Sourced by tier-gate.sh and lib/tier-runtime.sh. The caller defines
# _tg_note and PLUGIN_ROOT.
#
# Not the tracked journal: `<journal dir>/auto-log/`, the git-ignored trail
# log-commits.sh and log-file-changes.sh write, named the same way:
# issue-{N}.{YYYY-MM}.md on a branch naming issue N (rotated monthly),
# otherwise session-{YYYY-MM-DD}.md. The path checks below are theirs (see
# log-file-changes.sh, _flow_autolog). Written only where the repository keeps
# a flow journal directory: a push in a repository that never ran /flow:setup
# must not create .decisions/ in it.

# One HTML-comment breadcrumb per action, as the other trail entries are,
# with the comment terminators and control characters neutralized: the trail
# is fed back to Claude by /flow:explain.
_tg_crumb_safe() {
  local v="${1//-->/-- >}"
  v="${v//<!--/< !--}"
  printf '%s' "$v" | LC_ALL=C tr '\000-\037\177' ' '
}

_tg_trail_refused() { _tg_note "could not write to the auto-log trail ($1); allowing"; }

_tg_write_trail() {   # $1 = repository top, $2 = breadcrumbs
  local top="$1" jdir base branch issue autolog adir user err rc
  [ -n "$top" ] || return 0
  jdir=$(cd "$top" && "$PLUGIN_ROOT/bin/journal-dir.sh" 2>/dev/null) || jdir=""
  [ -n "$jdir" ] || jdir=".decisions"
  case "$jdir" in /*) base="$jdir" ;; *) base="$top/$jdir" ;; esac
  [ -d "$base" ] || return 0
  branch=$(git -C "$top" branch --show-current 2>/dev/null) || branch=""
  issue=$(printf '%s' "$branch" | grep -oE 'issue-[0-9]+' | head -n 1 | grep -oE '[0-9]+') || issue=""
  if [ -n "$issue" ]; then
    autolog="$base/auto-log/issue-$issue.$(date +%Y-%m).md"
  else
    autolog="$base/auto-log/session-$(date +%Y-%m-%d).md"
  fi
  adir=$(dirname "$autolog")
  # A symlinked trail file or directory is refused: after `gh pr checkout` of
  # a hostile fork it could point anywhere. The directory is created by
  # bin/flow-mkdir.sh --contained at the repository top (nothing below the
  # top through a symlink); an absolute journal.dir from the user's own
  # settings is created as configured.
  [ -L "$autolog" ] && { _tg_trail_refused "the trail file is a symlink"; return 0; }
  [ -L "$adir" ] && { _tg_trail_refused "the trail directory is a symlink"; return 0; }
  if ! (cd "$top" && "$PLUGIN_ROOT/bin/flow-mkdir.sh" --contained -- "$adir") >/dev/null 2>&1; then
    user=$(cd "$top" && "$PLUGIN_ROOT/bin/journal-dir.sh" --user-owned 2>/dev/null) || user=""
    [ -n "$user" ] || { _tg_trail_refused "its directory could not be created inside the repository"; return 0; }
    mkdir -p "$adir" 2>/dev/null || { _tg_trail_refused "its directory could not be created"; return 0; }
  fi
  # The trail directory ignores itself, so it never dirties the tree.
  [ -L "$adir/.gitignore" ] && { _tg_trail_refused "its .gitignore is a symlink"; return 0; }
  { [ -f "$adir/.gitignore" ] || printf '*\n' > "$adir/.gitignore" 2>/dev/null; } || true
  err=$(printf '%s' "$2" | (cd "$top" && "$PLUGIN_ROOT/bin/journal-append.sh" --file "$autolog" -) 2>&1 >/dev/null)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    err=$(printf '%s' "$err" | head -n 1 | LC_ALL=C tr '\000-\037\177' ' ' | cut -c1-200)
    _tg_trail_refused "journal-append.sh exit $rc${err:+: $err}"
  fi
  return 0
}

