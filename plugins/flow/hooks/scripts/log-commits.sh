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
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

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
  JOURNAL_DIR=$(cd "$REPO_ROOT" && "$HELPER_DIR/bin/cascade-resolve.sh" \
    --default ".decisions" '.journal.dir // empty' 2>/dev/null)
fi
[ -n "$JOURNAL_DIR" ] || JOURNAL_DIR=".decisions"

# Get the branch and issue number from the payload's repo
BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "")
ISSUE_NUM=$(echo "$BRANCH" | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+' || echo "")

# Determine the tracked journal (the gate and Guard 2) and the local trail
# (where the breadcrumb goes). Issue-scoped trails rotate monthly; the
# branchless one keeps the tracked journal's own daily name, which is already
# bounded by the day it belongs to.
if [ -n "$ISSUE_NUM" ]; then
  TRACKED="$REPO_ROOT/$JOURNAL_DIR/issue-$ISSUE_NUM.md"
  TRACKED_REL="$JOURNAL_DIR/issue-$ISSUE_NUM.md"
  AUTOLOG="$REPO_ROOT/$JOURNAL_DIR/auto-log/issue-$ISSUE_NUM.$(date +%Y-%m).md"
else
  TRACKED="$REPO_ROOT/$JOURNAL_DIR/session-$(date +%Y-%m-%d).md"
  TRACKED_REL="$JOURNAL_DIR/session-$(date +%Y-%m-%d).md"
  AUTOLOG="$REPO_ROOT/$JOURNAL_DIR/auto-log/session-$(date +%Y-%m-%d).md"
fi

# Only log if the tracked journal exists
if [ -f "$TRACKED" ]; then
  # Refuse if the trail path is a symlink. After `gh pr checkout` of a hostile
  # fork, an attacker-staged path could point at ~/.bashrc, and bash `>>`
  # follows symlinks. The append helper refuses this at the syscall
  # (O_NOFOLLOW) as well; this is the cheap check that runs first.
  [ -L "$AUTOLOG" ] && exit 0

  # The trail directory ignores itself. A consumer repo that never ran
  # /flow:setup has no `.decisions/auto-log/` line in its .gitignore, and an
  # untracked directory is exactly the dirty tree this change exists to remove —
  # so the guarantee cannot depend on the operator having added an ignore rule.
  # `*` matches this file too, which is intended: nothing here belongs in git.
  AUTOLOG_DIR=$(dirname "$AUTOLOG")
  mkdir -p "$AUTOLOG_DIR" 2>/dev/null || exit 0
  [ -f "$AUTOLOG_DIR/.gitignore" ] || printf '*\n' > "$AUTOLOG_DIR/.gitignore" 2>/dev/null

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
  if [ "$CHANGED" = "$TRACKED_REL" ]; then
    exit 0
  fi

  # Sanitize the commit subject before embedding it inside an HTML comment.
  # An attacker-supplied subject containing `-->` would close the comment
  # early; subsequent text would land in the journal as renderable markdown,
  # which `/flow:explain` and `/flow:review` later feed back to Claude as
  # context — a prompt-injection vector against future sessions.
  LAST_MSG_SAFE=${LAST_MSG//-->/-- >}
  LAST_MSG_SAFE=${LAST_MSG_SAFE//<!--/< !--}

  # A subagent's Bash calls fire this same hook; agent_type is present only
  # then, and is sanitized on the same grounds as the subject.
  AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null) || AGENT_TYPE=""
  AGENT_SAFE=""
  if [ -n "$AGENT_TYPE" ]; then
    AGENT_SAFE=${AGENT_TYPE//-->/-- >}
    AGENT_SAFE=${AGENT_SAFE//<!--/< !--}
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
