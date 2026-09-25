#!/bin/bash
# [flow] PostToolUse hook: Log file edits to the local auto-log trail
# Runs after Edit|Write|NotebookEdit operations, then records the change in the
# per-session quality ledger (bin/flow-quality-ledger.sh) so the TaskCompleted
# gate can tell whether files changed after the last passing quality run.
# Edit/Write name the file in tool_input.file_path, NotebookEdit in
# tool_input.notebook_path; both are read. Edits made through Bash never reach
# this hook — the gate catches those through the worktree digest recorded by
# record-quality-run.sh.
#
# WHERE THE BREADCRUMB GOES. Not into `.decisions/issue-N.md`. That file is
# tracked, so breadcrumbs written there entered commits, PR diffs, and every
# worktree's copy, and merging two worktrees conflicted on the journal itself.
# They go to `<journal.dir>/auto-log/`, which is gitignored — a local audit
# trail that cannot reach a commit or another checkout. The tracked journal
# keeps only deliberate entries and its manifest. See issue #244.

set -euo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH

# Graceful: if jq unavailable, skip logging
command -v jq &>/dev/null || exit 0

INPUT=$(cat)
# `|| VAR=""` because these run under `set -e`: an unparseable payload made jq
# exit 5 and took the hook with it, printing a parse error — which breaks this
# hook's own contract that it never fails the tool call it runs after. Every
# jq call added later in this file already carried the guard.
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || TOOL_NAME=""
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null) || FILE_PATH=""

# Skip if no file path
[ -z "$FILE_PATH" ] && exit 0

# --- The auto-log breadcrumb -------------------------------------------------
# A function rather than inline `exit 0`s: the quality-ledger block below must
# run whatever this decides, or an edit outside the repository would stop
# reaching the TaskCompleted gate.
_flow_autolog() {
  local cwd repo_root abs rel branch issue_num helper_dir journal_dir
  local tracked autolog autolog_dir journal_base timestamp tool_safe path_safe agent_type agent_safe entry

  # The payload's cwd is the live working directory and follows into a
  # worktree; $PWD is wherever the hook process happened to start. Adopting it
  # is what makes the journal dir, the branch and git agree with each other —
  # the ledger block below already resolves its own path this way.
  cwd=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || cwd=""
  [ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"
  # `pwd -P` resolves symlinks. On macOS a mktemp -d path is /var/folders/...
  # while `git rev-parse --show-toplevel` reports /private/var/folders/...;
  # compared unnormalized, every in-repo file looks out-of-tree and the hook
  # silently logs nothing.
  cwd=$(cd "$cwd" 2>/dev/null && pwd -P) || return 0

  repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || return 0
  [ -n "$repo_root" ] || return 0

  # Resolve the edited path against the payload cwd, then require it to be
  # inside the repository. The trailing separator matters: a bare "$repo_root"*
  # would treat a sibling directory sharing a name prefix as in-repo. A scratch
  # file a subagent wrote to /tmp is not journal content, and neither is a path
  # in no repository at all.
  case "$FILE_PATH" in
    /*)
      # An absolute path is NOT taken verbatim. `repo_root` is physical, so the
      # symlinked form of the same location never prefix-matches: macOS /tmp is
      # /private/tmp, and a project reached through a symlinked directory has
      # the same shape. The breadcrumb is then dropped for the whole session
      # while the hook still looks healthy, which is the failure this file's
      # `pwd -P` comment describes for the other side of the comparison.
      # Physicalize the directory — it exists for anything being edited.
      adir=$(dirname "$FILE_PATH")
      if [ -d "$adir" ]; then
        abs=$(cd "$adir" 2>/dev/null && pwd -P)/$(basename "$FILE_PATH")
      else
        abs="$FILE_PATH"
      fi
      ;;
    *)  abs="${cwd%/}/$FILE_PATH" ;;
  esac
  # A relative path can traverse out of the repository: "../elsewhere/f.md"
  # composes to "$cwd/../elsewhere/f.md", which the prefix match below accepts
  # because nothing here normalizes. Reject any parent segment rather than
  # resolve it — such a path is either leaving the repo, or (rarely) staying
  # inside at the cost of one unrecorded breadcrumb, which is the safe way to be
  # wrong.
  case "/$abs/" in
    */../*) return 0 ;;
  esac
  case "$abs" in
    "$repo_root"/*) rel=${abs#"$repo_root"/} ;;
    *) return 0 ;;
  esac
  [ -n "$rel" ] || return 0

  helper_dir="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
  journal_dir=".decisions"
  if [ -x "$helper_dir/bin/cascade-resolve.sh" ]; then
    # cascade-resolve reads .claude/settings.flow.json from its process CWD, so
    # it must run inside the repo the payload named, not this process's.
    # Guarded even though this function's only call site is `_flow_autolog ||
    # true`, which suspends `set -e` inside it: the body should not depend on
    # how a future caller invokes it.
    journal_dir=$(cd "$repo_root" && "$helper_dir/bin/cascade-resolve.sh" \
      --default ".decisions" '.journal.dir // empty' 2>/dev/null) || journal_dir=""
  fi
  [ -n "$journal_dir" ] || journal_dir=".decisions"

  branch=$(git -C "$cwd" branch --show-current 2>/dev/null || echo "")
  issue_num=$(printf '%s\n' "$branch" | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+' || echo "")

  # journal.dir may be absolute — the settings schema permits it — and prefixing
  # the repo root unconditionally composed "$repo_root//abs/path", which exists
  # nowhere, so the gate below failed and the hook silently stopped logging.
  case "$journal_dir" in
    /*) journal_base="$journal_dir" ;;
    *)  journal_base="$repo_root/$journal_dir" ;;
  esac
  # Containment. A symlinked journal DIRECTORY is caught by neither the
  # auto-log-dir check below nor O_NOFOLLOW — that protects one path component,
  # and this is a different one. A fork can commit `.decisions -> /elsewhere`;
  # resolving the composed path and requiring it inside the repository catches
  # the link, a deeper redirection, and a `journal_dir` that leaves the tree, in
  # one test. A directory that does not exist resolves empty and is left to the
  # tracked-journal gate below.
  case "$journal_base" in
    "$repo_root"/*)
      # Compared against BOTH forms of the repo root. `pwd -P` resolves a mount
      # to its real location — Git Bash's `/tmp` is one — so the physical
      # journal path does not prefix-match the form `git rev-parse` reports, and
      # the hook returned before writing anything at all. Only the Windows leg
      # caught it, because only there do the two forms differ; locally the
      # payload cwd is already physical, so they agree. Accepting either form
      # keeps the containment: a journal that resolved outside the repository
      # matches neither pattern and is still refused.
      repo_root_phys=$(cd "$repo_root" 2>/dev/null && pwd -P)
      [ -n "$repo_root_phys" ] || repo_root_phys="$repo_root"
      jb_phys=$(cd "$journal_base" 2>/dev/null && pwd -P)
      case "$jb_phys" in
        "") ;;
        "$repo_root"/*|"$repo_root_phys"/*) ;;
        *) return 0 ;;
      esac
      ;;
  esac

  if [ -n "$issue_num" ]; then
    # Issue-scoped trails rotate monthly — a long-running branch accumulates
    # hundreds of entries otherwise.
    tracked="$journal_base/issue-$issue_num.md"
    autolog="$journal_base/auto-log/issue-$issue_num.$(date +%Y-%m).md"
  else
    # The branchless trail keeps the tracked journal's own daily name. It is
    # already bounded by the day it belongs to, and rotating it monthly would
    # decouple it from the tracked file it accompanies.
    tracked="$journal_base/session-$(date +%Y-%m-%d).md"
    autolog="$journal_base/auto-log/session-$(date +%Y-%m-%d).md"
  fi

  # Log only if the tracked journal exists, so a repo that never initialized
  # flow stays untouched. Preserved from the pre-change gate.
  [ -f "$tracked" ] || return 0

  # Refuse a symlinked target. After `gh pr checkout` of a hostile fork, an
  # attacker-staged auto-log path could point at ~/.bashrc; the append helper
  # refuses this at the syscall (O_NOFOLLOW) as well, which is the load-bearing
  # defense — this is the cheap check that runs first.
  [ -L "$autolog" ] && return 0

  autolog_dir=$(dirname "$autolog")
  # Refuse a symlinked trail DIRECTORY as well as a symlinked file. The
  # O_NOFOLLOW inside journal-append.sh protects the final path component only,
  # so a pre-staged `.decisions/auto-log -> /tmp/elsewhere` would otherwise have
  # mkdir, the self-ignoring .gitignore and the entry itself all written through
  # it — the same class as the symlinked-file case the guard above covers, and
  # the same check bin/flow-strip-auto-log.sh already makes.
  [ -L "$autolog_dir" ] && return 0

  # The trail directory ignores itself. A consumer repo that never ran
  # /flow:setup has no `.decisions/auto-log/` line in its .gitignore, and an
  # untracked directory is exactly the dirty tree this change exists to remove —
  # so the guarantee cannot depend on the operator having added an ignore rule.
  # `*` matches this file too, which is intended: nothing here belongs in git.
  mkdir -p "$autolog_dir" 2>/dev/null || return 0
  # A plain `>` follows a symlink, and the `-f` test only blocks an existing
  # regular file — so a staged link to a non-existent path would be written
  # through. Refuse it explicitly, as the entry target already is.
  [ -L "$autolog_dir/.gitignore" ] && return 0
  # Grouped and guarded, matching log-commits.sh. Ungrouped, this is the last
  # command of an `A || B` list, which `set -e` does not exempt — and the only
  # reason it does not abort is that the sole call site is `_flow_autolog ||
  # true`. Left unguarded, a `.gitignore` staged as a directory would leave the
  # trail without its self-ignore rule, breaking the "cannot dirty the tree"
  # guarantee silently.
  { [ -f "$autolog_dir/.gitignore" ] || printf '*\n' > "$autolog_dir/.gitignore" 2>/dev/null; } || true

  timestamp=$(date +"%Y-%m-%d %H:%M")
  # Neutralize comment terminators before embedding. An attacker-supplied path
  # containing `-->` would close the HTML comment early and land renderable
  # markdown in a file `/flow:explain` later feeds back to Claude.
  tool_safe=${TOOL_NAME//-->/-- >}
  tool_safe=${tool_safe//<!--/< !--}
  path_safe=${rel//-->/-- >}
  path_safe=${path_safe//<!--/< !--}
  # A newline in the path ends the breadcrumb's line and lands whatever follows
  # as ORDINARY markdown — the outcome the `-->` escaping exists to prevent,
  # reached through a character that escaping set omits. Collapse every
  # whitespace control to a space so one entry is always exactly one line.
  path_safe=$(printf '%s' "$path_safe" | LC_ALL=C tr '\000-\037\177' ' ')
  tool_safe=$(printf '%s' "$tool_safe" | LC_ALL=C tr '\000-\037\177' ' ')

  # A subagent's tool calls fire this same hook; agent_type is present only
  # then. It is sanitized too — it comes from an agent definition a plugin or a
  # fork supplies, so it is no more trusted than the path beside it.
  agent_type=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null) || agent_type=""
  agent_safe=""
  if [ -n "$agent_type" ]; then
    agent_safe=${agent_type//-->/-- >}
    agent_safe=${agent_safe//<!--/< !--}
    agent_safe=$(printf '%s' "$agent_safe" | LC_ALL=C tr '\000-\037\177' ' ')
    agent_safe=" agent=$agent_safe"
  fi

  entry="<!-- auto-log: $timestamp $tool_safe $path_safe$agent_safe -->"
  # ONE write for the whole entry, via the locked helper. Two `echo >>` calls
  # (the pre-change shape) let a concurrent writer split the blank line from
  # its entry. Best-effort: a breadcrumb must never fail the tool call it
  # follows, so every failure here is swallowed.
  [ -x "$helper_dir/bin/journal-append.sh" ] || return 0
  printf '%s\n' "$entry" | "$helper_dir/bin/journal-append.sh" \
    --file "$autolog" - >/dev/null 2>&1 || true
  return 0
}
_flow_autolog || true

# --- Quality ledger -------------------------------------------------------
# Append a file_change entry for the TaskCompleted gate. Best-effort: the
# journal logic above must never be affected, and a ledger failure (missing
# helper, unwritable state dir, refused symlink) must never fail the hook.
_flow_ledger_record() {
  local session_id helper cwd path tool now entry
  session_id=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || return 0
  [ -n "$session_id" ] || return 0
  helper="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}/bin/flow-quality-ledger.sh"
  [ -x "$helper" ] || return 0
  # The ledger stores absolute paths so ignore prefixes compare reliably;
  # resolve a relative file_path against the payload's cwd (fallback: $PWD).
  path="$FILE_PATH"
  case "$path" in
    /*) ;;
    *)
      cwd=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || cwd=""
      [ -n "$cwd" ] || cwd="$PWD"
      path="${cwd%/}/$path"
      ;;
  esac
  tool="$TOOL_NAME"
  [ -n "$tool" ] || tool="unknown"
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  entry=$(jq -cn --arg at "$now" --arg tool "$tool" --arg path "$path" \
    '{at: $at, type: "file_change", tool: $tool, path: $path}' 2>/dev/null) || return 0
  "$helper" append --session "$session_id" --json "$entry" >/dev/null 2>&1 || return 0
}
_flow_ledger_record || true

exit 0
