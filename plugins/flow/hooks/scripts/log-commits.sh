#!/bin/bash
# [flow] PostToolUse hook: Log git commits to the local auto-log trail
# Runs after Bash operations to capture commit decisions.
#
# WHERE THE BREADCRUMB GOES. Not into `.decisions/issue-N.md`. That file is
# tracked, so breadcrumbs written there entered commits, PR diffs, and every
# worktree's copy. They go to `<journal.dir>/auto-log/`, which is gitignored.
# The tracked journal keeps only deliberate entries and its manifest. See
# issue #244.

set -euo pipefail

# Graceful: if jq unavailable, skip logging
command -v jq &>/dev/null || exit 0

INPUT=$(cat)
# `|| VAR=""` because these run under `set -e`: an unparseable payload made jq
# exit 5 and took the hook with it, printing a parse error — which breaks this
# hook's own contract that it never fails the tool call it runs after. Every
# jq call added later in this file already carried the guard.
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || COMMAND=""

# Only process git commit commands
echo "$COMMAND" | grep -qE 'git\s+commit' || exit 0

# The payload's cwd is the live working directory and follows into a worktree;
# $PWD is wherever the hook process happened to start. Adopting it is what
# makes the journal dir, the branch and git agree with each other.
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || CWD=""
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"
# `pwd -P` resolves symlinks. On macOS a mktemp -d path is /var/folders/...
# while `git rev-parse --show-toplevel` reports /private/var/folders/...;
# compared unnormalized, the repo looks absent and the hook logs nothing.
CWD=$(cd "$CWD" 2>/dev/null && pwd -P) || exit 0

REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$REPO_ROOT" ] || exit 0

# Determine journal directory via bin/cascade-resolve.sh. Gracefully fall back
# to the default when the helper is unreachable — hooks run from arbitrary
# CWDs and CLAUDE_PLUGIN_ROOT may not always be set (e.g., in test harnesses
# that exercise the hook standalone).
HELPER_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
JOURNAL_DIR=".decisions"
if [ -x "$HELPER_DIR/bin/cascade-resolve.sh" ]; then
  # cascade-resolve reads .claude/settings.flow.json from its process CWD, so
  # it must run inside the repo the payload named, not this process's.
  # `|| JOURNAL_DIR=""` because this runs under `set -e` and is not in a tested
  # context: without it a `cd` or resolver failure aborts the whole hook, which
  # breaks the contract that a hook never fails the tool call it follows. The
  # fallback below then supplies the default, same as if it had resolved empty.
  JOURNAL_DIR=$(cd "$REPO_ROOT" && "$HELPER_DIR/bin/cascade-resolve.sh" \
    --default ".decisions" '.journal.dir // empty' 2>/dev/null) || JOURNAL_DIR=""
fi
[ -n "$JOURNAL_DIR" ] || JOURNAL_DIR=".decisions"
# A trailing slash or a leading "./" is legal in the settings but produces a
# doubled or dotted separator in the composed path. Guard 2 compares that path
# against the form git reports, so ".decisions/" silently stopped the guard
# firing while ".decisions" worked — the same silent-guard class this hook's
# Guard 2 was already fixed for, on a second axis.
JOURNAL_DIR=${JOURNAL_DIR%/}
case "$JOURNAL_DIR" in ./*) JOURNAL_DIR=${JOURNAL_DIR#./} ;; esac
[ -n "$JOURNAL_DIR" ] || JOURNAL_DIR=".decisions"

# Get the branch and issue number from the payload's repo
BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "")
ISSUE_NUM=$(echo "$BRANCH" | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+' || echo "")

# Determine the tracked journal (the gate and Guard 2) and the local trail
# (where the breadcrumb goes). Issue-scoped trails rotate monthly; the
# branchless one keeps the tracked journal's own daily name, which is already
# bounded by the day it belongs to.
# journal.dir may be absolute — the settings schema permits it — and prefixing
# the repo root unconditionally composed "$REPO_ROOT//abs/path", which exists
# nowhere, so the gate below failed and the hook silently stopped logging.
case "$JOURNAL_DIR" in
  /*) JOURNAL_BASE="$JOURNAL_DIR" ;;
  *)  JOURNAL_BASE="$REPO_ROOT/$JOURNAL_DIR" ;;
esac
# Containment — see log-file-changes.sh. A symlinked journal DIRECTORY is caught
# by neither the auto-log-dir check nor O_NOFOLLOW, which protects one component.
case "$JOURNAL_BASE" in
  "$REPO_ROOT"/*)
    # `|| JB_PHYS=""` because this is top level under `set -e`: a `cd` into a
    # directory that does not exist — the ordinary "flow installed, project
    # never initialized" state — returned non-zero from the assignment and
    # aborted the whole hook with exit 1, breaking the contract that a hook
    # never fails the tool call it follows. The sibling hook's identical block
    # is safe only because its caller is `_flow_autolog || true`; this one is
    # not, and the empty case below is the arm that must be reached.
    # Both forms of the repo root — see log-file-changes.sh. `pwd -P` resolves
    # a mount to its real location, which on Git Bash is not the form
    # `git rev-parse` reports, so the physical journal path never prefix-matched
    # and the hook exited before writing anything. Only the Windows leg could
    # catch that, because locally the payload cwd is already physical.
    REPO_ROOT_PHYS=$(cd "$REPO_ROOT" 2>/dev/null && pwd -P) || REPO_ROOT_PHYS=""
    [ -n "$REPO_ROOT_PHYS" ] || REPO_ROOT_PHYS="$REPO_ROOT"
    JB_PHYS=$(cd "$JOURNAL_BASE" 2>/dev/null && pwd -P) || JB_PHYS=""
    case "$JB_PHYS" in
      "") ;;
      "$REPO_ROOT"/*|"$REPO_ROOT_PHYS"/*) ;;
      *) exit 0 ;;
    esac
    ;;
esac

if [ -n "$ISSUE_NUM" ]; then
  JFILE="issue-$ISSUE_NUM.md"
  AUTOLOG="$JOURNAL_BASE/auto-log/issue-$ISSUE_NUM.$(date +%Y-%m).md"
else
  JFILE="session-$(date +%Y-%m-%d).md"
  AUTOLOG="$JOURNAL_BASE/auto-log/session-$(date +%Y-%m-%d).md"
fi
TRACKED="$JOURNAL_BASE/$JFILE"

# Guard 2 compares the commit's file list, which git reports repo-relative,
# against the journal FILE's repo-relative path — the directory's would never
# match a commit entry, which is how this was briefly wrong. A journal outside
# the repository has no repo-relative form and cannot be tracked, so Guard 2
# cannot apply to it: leave the value empty and let it not fire.
case "$TRACKED" in
  "$REPO_ROOT"/*) TRACKED_REL=${TRACKED#"$REPO_ROOT"/} ;;
  *)              TRACKED_REL="" ;;
esac

# Only log if the tracked journal exists
if [ -f "$TRACKED" ]; then
  # Refuse if the trail path is a symlink. After `gh pr checkout` of a hostile
  # fork, an attacker-staged path could point at ~/.bashrc, and bash `>>`
  # follows symlinks. The append helper refuses this at the syscall
  # (O_NOFOLLOW) as well; this is the cheap check that runs first.
  [ -L "$AUTOLOG" ] && exit 0

  AUTOLOG_DIR=$(dirname "$AUTOLOG")
  # Refuse a symlinked trail DIRECTORY as well as a symlinked file — see
  # log-file-changes.sh. O_NOFOLLOW in journal-append.sh covers the final
  # component only, so mkdir and the self-ignoring .gitignore would otherwise be
  # written through a pre-staged directory symlink.
  [ -L "$AUTOLOG_DIR" ] && exit 0

  # The trail directory ignores itself. A consumer repo that never ran
  # /flow:setup has no `.decisions/auto-log/` line in its .gitignore, and an
  # untracked directory is exactly the dirty tree this change exists to remove —
  # so the guarantee cannot depend on the operator having added an ignore rule.
  # `*` matches this file too, which is intended: nothing here belongs in git.
  mkdir -p "$AUTOLOG_DIR" 2>/dev/null || exit 0
  # Grouped and `|| true`-guarded: this was the last command of an `A || B`
  # list with no guard, so under `set -e` a failed write exited the hook — and
  # a `.gitignore` staged as a directory, or as a symlink to a path that does
  # not exist, reaches that. A plain `>` also follows a link, so the symlink is
  # refused first rather than written through.
  [ -L "$AUTOLOG_DIR/.gitignore" ] && exit 0
  { [ -f "$AUTOLOG_DIR/.gitignore" ] || printf '*\n' > "$AUTOLOG_DIR/.gitignore" 2>/dev/null; } || true

  TIMESTAMP=$(date +"%Y-%m-%d %H:%M")
  LAST_MSG=$(git -C "$CWD" log -1 --format="%s" 2>/dev/null || echo "unknown")

  # Guard 1: skip explicit housekeeping commits ("chore(decisions): ...")
  case "$LAST_MSG" in
    "chore(decisions):"*) exit 0 ;;
  esac

  # Guard 2: skip if the most recent commit touched ONLY the tracked journal.
  # $CHANGED is repo-root-relative and newline-joined, so the comparison must be
  # against the repo-relative journal path — comparing it to a CWD-relative path
  # (as this did before) meant the two never matched off the repo root and the
  # guard silently stopped firing. Newline-joining is also what makes this mean
  # "touched the journal and nothing else"; it is deliberate, not incidental.
  CHANGED=$(git -C "$CWD" diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null || echo "")
  if [ -n "$TRACKED_REL" ] && [ "$CHANGED" = "$TRACKED_REL" ]; then
    exit 0
  fi

  # Sanitize the commit subject before embedding it inside an HTML comment.
  # An attacker-supplied subject containing `-->` would close the comment
  # early; subsequent text would land in the journal as renderable markdown,
  # which `/flow:explain` and `/flow:review` later feed back to Claude as
  # context — a prompt-injection vector against future sessions.
  LAST_MSG_SAFE=${LAST_MSG//-->/-- >}
  LAST_MSG_SAFE=${LAST_MSG_SAFE//<!--/< !--}
  # Escaping the comment terminators is not enough to keep one entry on one
  # line: `git log -1 --format=%s` preserves CR, VT and FF verbatim, so a
  # subject carrying one (a fork's commit, logged when the operator's own
  # `git commit --amend` leaves it as HEAD) breaks the one-line invariant and
  # everything after the control character reads as a fabricated line in the
  # file /flow:explain cats into Claude's context. The whole C0 range collapses,
  # matching one_line() elsewhere in this plugin and the sibling hook's fields.
  LAST_MSG_SAFE=$(printf '%s' "$LAST_MSG_SAFE" | LC_ALL=C tr '\000-\037\177' ' ')

  # A subagent's Bash calls fire this same hook; agent_type is present only
  # then, and is sanitized on the same grounds as the subject.
  AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null) || AGENT_TYPE=""
  AGENT_SAFE=""
  if [ -n "$AGENT_TYPE" ]; then
    AGENT_SAFE=${AGENT_TYPE//-->/-- >}
    AGENT_SAFE=${AGENT_SAFE//<!--/< !--}
    # A control character would end the breadcrumb's line and land the rest as
    # ordinary markdown — the outcome the escaping above exists to prevent,
    # reached through a character that escaping set omits.
    AGENT_SAFE=$(printf '%s' "$AGENT_SAFE" | LC_ALL=C tr '\000-\037\177' ' ')
    AGENT_SAFE=" agent=$AGENT_SAFE"
  fi

  ENTRY="<!-- auto-log: $TIMESTAMP commit \"$LAST_MSG_SAFE\"$AGENT_SAFE -->"
  # ONE write for the whole entry, via the locked helper. Two `echo >>` calls
  # (the pre-change shape) let a concurrent writer split the blank line from its
  # entry. Best-effort: never fail the tool call this follows.
  if [ -x "$HELPER_DIR/bin/journal-append.sh" ]; then
    printf '%s\n' "$ENTRY" | "$HELPER_DIR/bin/journal-append.sh" \
      --file "$AUTOLOG" - >/dev/null 2>&1 || true
  fi
fi

exit 0
