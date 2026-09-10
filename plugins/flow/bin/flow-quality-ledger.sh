#!/usr/bin/env bash
# [flow] Per-session quality ledger — the file-backed state behind the
# TaskCompleted gate (hooks/scripts/verify-task-completion.sh).
#
# The ledger is an append-only JSONL file:
#   ${FLOW_STATE_DIR:-$HOME/.claude/flow-state}/sessions/<session_id>/quality-ledger.jsonl
#
# Entry shapes (one JSON object per line):
#   {"at":"<ISO-8601 UTC>","type":"file_change","tool":"Edit|Write|NotebookEdit","path":"<absolute path>"}
#   {"at":"<ISO-8601 UTC>","type":"quality_run","command":"<first 200 chars>",
#    "exit_code":<int|null>,"kind":"test|lint|typecheck|build|project",
#    "masked":<bool>,"failed":<bool>,"worktree_digest":"<sha256 hex>"|null,
#    "tool_use_id":"<id>"}
#     masked          the command ends in `|| true`, `; true`, or `|| :` — the
#                     exit code says nothing, so the run never counts as passing
#     failed          recorded from PostToolUseFailure (the tool call itself
#                     failed); never counts as passing regardless of exit_code
#     worktree_digest sha256 over the working tree state when the run finished
#                     (see `digest`); null outside a git repo
#     tool_use_id     Claude Code's id for the tool call; an append whose
#                     tool_use_id already exists in the ledger is skipped so a
#                     run that fires both PostToolUse and PostToolUseFailure is
#                     recorded once
#
# Writers: hooks/scripts/log-file-changes.sh (file_change) and
# hooks/scripts/record-quality-run.sh (quality_run). Reader:
# hooks/scripts/verify-task-completion.sh (status). Sweeper:
# hooks/scripts/session-end-state.sh (prune, once per day).
#
# Usage:
#   flow-quality-ledger.sh append --session <id> --json '<object>'
#   flow-quality-ledger.sh path   --session <id>
#   flow-quality-ledger.sh status --session <id> [--cwd <dir>] [--ignore-prefix <path>]...
#   flow-quality-ledger.sh digest --cwd <dir> [--ignore-prefix <path>]...
#   flow-quality-ledger.sh prune  [--max-age-days <n>]
#
# `status` prints, one per line:
#   STATE=clean|dirty|empty|unavailable
#   LAST_PASSING_RUN=<at|none>      time of the most recent passing quality_run
#                                   (exit_code 0, not masked, not failed)
#   LAST_RUN_EXIT=<code|null|none>  exit code of the most recent quality_run of any
#                                   outcome ("null" when that run had no exit code,
#                                   "none" when no quality_run exists)
#   LAST_RUN_MASKED=true            only when the most recent run was masked
#   LAST_RUN_FAILED=true            only when the most recent run failed (tool error)
#   WORKTREE=unchanged|changed|unknown
#                                   result of comparing the last passing run's
#                                   worktree_digest with the digest of --cwd now;
#                                   "unknown" without --cwd, without a digest on
#                                   that run, or when git is unavailable
#   CHANGED_SINCE=<n>               distinct files changed after the last passing run
#   CHANGED_FILE=<path>             up to five of those files, in first-change order
#
# "dirty" means at least one file_change entry sits after the most recent
# passing quality_run in the ledger (or no passing run exists and there is at
# least one file_change), OR the worktree digest differs from the one the last
# passing run recorded (WORKTREE=changed) — that second path catches edits made
# through Bash (sed -i, heredocs, git apply, mv), and checkouts, resets or
# stashes that change file contents, none of which an Edit/Write hook ever
# saw. When the digests differ, the paths from
# `git status --porcelain` (resolved against the repository root) join the
# CHANGED_FILE list. "empty" means the ledger is missing or holds no parseable
# entry. "unavailable" means python3 is missing — the gate cannot evaluate, so
# callers treat it as pass-through. Ordering is ledger position (append
# order), not the `at` timestamp: hooks append in the order the tools ran, and
# timestamps only carry one-second resolution.
#
# file_change entries (and git-status paths) under an --ignore-prefix
# (resolved against the current working directory) are skipped: callers pass
# the decision journal directory, .flow/, and .screenshots/ so bookkeeping
# writes never dirty the gate. The same prefixes are excluded from the
# digest (git `:(exclude)` pathspecs), so a bookkeeping write made through
# Bash does not move it either — recorder and gate must pass the same set.
#
# `digest` prints the sha256 hex of a git tree id for the CONTENTS of the
# working tree: every tracked and untracked (non-gitignored) file with its
# mode, --ignore-prefix paths excluded, computed from the repository root
# that contains --cwd. It is built in a temporary index (`git add -A` then
# `git write-tree`, seeded from the real index for its stat cache), so the
# real index, HEAD, and the working tree are never touched; git may store
# unreferenced blob/tree objects, which `git gc` reclaims. HEAD is not part
# of the digest on purpose: committing the edits a passing run already
# tested leaves the digest unchanged, while committing FURTHER edits, or
# checking out different contents, moves it. Prints nothing and exits 1
# when --cwd is not inside a git work tree, or git / a sha256 tool is
# missing.
#
# `prune` removes session directories under ${FLOW_STATE_DIR}/sessions/ whose
# newest file (or the directory itself) is older than --max-age-days (default
# 14). It never touches anything outside that directory, skips symlinked
# entries, and refuses to run when the state dir or sessions dir is itself a
# symlink. Prints PRUNED=<n>.
#
# Malformed lines (partial writes, non-object JSON, missing fields) are skipped.
#
# Exit codes:
#   0 — success (status always exits 0, including STATE=unavailable)
#   1 — usage error (unknown subcommand, bad --session, invalid --json);
#       for `digest`: no digest available
#   2 — infrastructure error (ledger or its directory is a symlink; write failed)

set -uo pipefail
export PYTHONSAFEPATH=1

_usage() {
  sed -n '2,100p' "$0" | sed 's/^# \?//'
}

SUBCOMMAND="${1:-}"
[ -z "$SUBCOMMAND" ] && { _usage >&2; exit 1; }
shift

case "$SUBCOMMAND" in
  append|path|status|digest|prune) ;;
  -h|--help) _usage; exit 0 ;;
  *) echo "flow-quality-ledger.sh: unknown subcommand: $SUBCOMMAND" >&2; exit 1 ;;
esac

SESSION_ID=""
JSON_ENTRY=""
CWD_ARG=""
MAX_AGE_DAYS="14"
IGNORE_PREFIXES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --session)
      [ $# -lt 2 ] && { echo "flow-quality-ledger.sh: --session requires a value" >&2; exit 1; }
      SESSION_ID="$2"
      shift 2
      ;;
    --json)
      [ $# -lt 2 ] && { echo "flow-quality-ledger.sh: --json requires a value" >&2; exit 1; }
      JSON_ENTRY="$2"
      shift 2
      ;;
    --cwd)
      [ $# -lt 2 ] && { echo "flow-quality-ledger.sh: --cwd requires a value" >&2; exit 1; }
      CWD_ARG="$2"
      shift 2
      ;;
    --max-age-days)
      [ $# -lt 2 ] && { echo "flow-quality-ledger.sh: --max-age-days requires a value" >&2; exit 1; }
      MAX_AGE_DAYS="$2"
      shift 2
      ;;
    --ignore-prefix)
      [ $# -lt 2 ] && { echo "flow-quality-ledger.sh: --ignore-prefix requires a value" >&2; exit 1; }
      [ -n "$2" ] && IGNORE_PREFIXES+=("$2")
      shift 2
      ;;
    *)
      echo "flow-quality-ledger.sh: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

STATE_ROOT="${FLOW_STATE_DIR:-${HOME:-/nonexistent}/.claude/flow-state}"
SESSIONS_DIR="$STATE_ROOT/sessions"

# --- worktree digest ---------------------------------------------------------
# sha256 of stdin via whichever tool exists; return 1 when none does.
_sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
  else
    return 1
  fi
}

# _physical_path <path>: print <path> with its existing directory part resolved
# through any symlinks, so it can be compared against a path git reported.
# The trailing component is never required to exist — an --ignore-prefix may
# name a directory that has not been created yet.
_physical_path() {
  local p="$1" d b
  if [ -d "$p" ]; then
    (cd "$p" 2>/dev/null && pwd -P) || printf '%s' "$p"
    return
  fi
  d=$(dirname "$p"); b=$(basename "$p")
  if [ -d "$d" ]; then
    printf '%s/%s' "$(cd "$d" 2>/dev/null && pwd -P || printf '%s' "$d")" "$b"
  else
    printf '%s' "$p"
  fi
}

# _worktree_digest <dir> [ignore-prefix...]: prints the hex digest, or
# nothing (return 1). Ignore prefixes (absolute, or relative to $PWD like
# the status reader resolves them) inside the repository become
# `:(exclude)` pathspecs for `git add -A` and are then force-removed from
# the temporary index, so tracked files under them (the decision journal)
# drop out of the tree too. GIT_OPTIONAL_LOCKS=0 keeps rev-parse from
# refreshing the real index; every write goes to the temporary index file.
_worktree_digest() {
  local dir="$1" top pre abs rel gitdir tmpidx tree out
  shift
  [ -d "$dir" ] || return 1
  command -v git >/dev/null 2>&1 || return 1
  top=$(GIT_OPTIONAL_LOCKS=0 git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -n "$top" ] || return 1
  gitdir=$(GIT_OPTIONAL_LOCKS=0 git -C "$top" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  local -a spec=(--)
  spec+=(.)
  local -a excluded=()
  for pre in "$@"; do
    [ -n "$pre" ] || continue
    case "$pre" in
      /*) abs="$pre" ;;
      *) abs="$PWD/$pre" ;;
    esac
    abs="${abs%/}"
    # Match git's own spelling of the path before comparing against $top.
    # `git rev-parse` reports the PHYSICAL path, while $PWD and any caller-
    # supplied absolute path are LOGICAL: on macOS /var is a symlink to
    # /private/var, so a repository under TMPDIR is /var/folders/... to the
    # shell and /private/var/folders/... to git. The prefix then never matched
    # "$top"/* and every --ignore-prefix was silently discarded.
    abs=$(_physical_path "$abs")
    case "$abs" in
      "$top"/*) rel="${abs#"$top"/}"; spec+=(":(exclude)$rel"); excluded+=("$rel") ;;
      *) ;;   # outside this repository: nothing to exclude
    esac
  done
  tmpidx=$(mktemp "${TMPDIR:-/tmp}/flow-digest-index.XXXXXX" 2>/dev/null) || return 1
  # Seed from the real index so unchanged files keep their stat cache and
  # only modified or new files are re-hashed. A missing index (unborn
  # repository) means every file is hashed, which is still correct.
  if [ -f "$gitdir/index" ]; then
    cp "$gitdir/index" "$tmpidx" 2>/dev/null || { rm -f "$tmpidx"; return 1; }
  fi
  tree=""
  if GIT_INDEX_FILE="$tmpidx" git -C "$top" add -A --ignore-errors "${spec[@]}" >/dev/null 2>&1; then
    if [ "${#excluded[@]}" -gt 0 ]; then
      GIT_INDEX_FILE="$tmpidx" git -C "$top" ls-files -z -- "${excluded[@]}" 2>/dev/null \
        | GIT_INDEX_FILE="$tmpidx" git -C "$top" update-index -z --force-remove --stdin >/dev/null 2>&1
    fi
    tree=$(GIT_INDEX_FILE="$tmpidx" git -C "$top" write-tree 2>/dev/null) || tree=""
  fi
  rm -f "$tmpidx" "$tmpidx.lock"
  [ -n "$tree" ] || return 1
  out=$(printf 'tree\0%s\n' "$tree" | _sha256_stdin) || return 1
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

# --- subcommands that need no session ----------------------------------------
case "$SUBCOMMAND" in
  digest)
    [ -n "$CWD_ARG" ] || { echo "flow-quality-ledger.sh: digest requires --cwd" >&2; exit 1; }
    DIGEST=$(_worktree_digest "$CWD_ARG" "${IGNORE_PREFIXES[@]+"${IGNORE_PREFIXES[@]}"}") || exit 1
    printf '%s\n' "$DIGEST"
    exit 0
    ;;

  prune)
    if ! [[ "$MAX_AGE_DAYS" =~ ^[1-9][0-9]*$ ]]; then
      echo "flow-quality-ledger.sh: --max-age-days must be a positive integer (got: '${MAX_AGE_DAYS}')" >&2
      exit 1
    fi
    for p in "$STATE_ROOT" "$SESSIONS_DIR"; do
      if [ -L "$p" ]; then
        echo "flow-quality-ledger.sh: refusing — $p is a symlink" >&2
        exit 2
      fi
    done
    if [ ! -d "$SESSIONS_DIR" ]; then
      echo "PRUNED=0"
      exit 0
    fi
    PRUNED=0
    shopt -s nullglob
    for d in "$SESSIONS_DIR"/*; do
      shopt -u nullglob
      d="${d%/}"
      # Only real directories, directly under sessions/, named like a session
      # id. Symlinks are skipped (rm -rf would follow a symlinked path
      # argument into whatever it points at).
      [ -L "$d" ] && continue
      [ -d "$d" ] || continue
      case "$d" in "$SESSIONS_DIR"/*) ;; *) continue ;; esac
      name="${d##*/}"
      [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || continue
      # Anything (the directory itself, or any file/dir beneath it) modified
      # within the window keeps the session. `find -P` never follows links.
      recent=$(find -P "$d" -mtime -"$MAX_AGE_DAYS" 2>/dev/null | head -n 1)
      [ -n "$recent" ] && continue
      if rm -rf -- "$d" 2>/dev/null; then
        PRUNED=$((PRUNED + 1))
      fi
      shopt -s nullglob
    done
    shopt -u nullglob
    echo "PRUNED=$PRUNED"
    exit 0
    ;;
esac

# The session id becomes a directory name under the state dir. Claude Code
# session ids are UUIDs; anything with a path separator, `..`, or a leading
# dot is refused so a hostile payload cannot steer writes outside the ledger
# tree.
if ! [[ "$SESSION_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]; then
  echo "flow-quality-ledger.sh: --session must be 1-128 chars of [A-Za-z0-9._-] starting alphanumeric (got: '${SESSION_ID}')" >&2
  exit 1
fi

SESSION_DIR="$SESSIONS_DIR/$SESSION_ID"
LEDGER="$SESSION_DIR/quality-ledger.jsonl"

case "$SUBCOMMAND" in
  path)
    printf '%s\n' "$LEDGER"
    exit 0
    ;;

  append)
    [ -z "$JSON_ENTRY" ] && { echo "flow-quality-ledger.sh: append requires --json" >&2; exit 1; }
    # Normalise to one compact line and require a JSON object. Without jq we
    # still accept the entry, but only when it cannot break the line-per-entry
    # contract.
    TOOL_USE_ID=""
    if command -v jq >/dev/null 2>&1; then
      LINE=$(printf '%s' "$JSON_ENTRY" | jq -c 'if type == "object" then . else error("entry must be a JSON object") end' 2>/dev/null) || {
        echo "flow-quality-ledger.sh: --json is not a JSON object" >&2
        exit 1
      }
      TOOL_USE_ID=$(printf '%s' "$LINE" | jq -r 'if (.tool_use_id | type) == "string" then .tool_use_id else empty end' 2>/dev/null)
    else
      case "$JSON_ENTRY" in
        *$'\n'*|*$'\r'*)
          echo "flow-quality-ledger.sh: --json must be a single line when jq is unavailable" >&2
          exit 1
          ;;
      esac
      LINE="$JSON_ENTRY"
      TOOL_USE_ID=$(printf '%s' "$LINE" | grep -oE '"tool_use_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | sed -E 's/^.*:[[:space:]]*"//; s/"$//')
    fi
    # Symlink defense: the state dir lives under $HOME, but a pre-staged
    # symlink (e.g. from a shared FLOW_STATE_DIR) must never redirect appends.
    # `>>` follows symlinks, so check every component we create or write.
    for p in "$STATE_ROOT" "$SESSIONS_DIR" "$SESSION_DIR" "$LEDGER"; do
      if [ -L "$p" ]; then
        echo "flow-quality-ledger.sh: refusing — $p is a symlink" >&2
        exit 2
      fi
    done
    # Dedupe on tool_use_id: PostToolUse and PostToolUseFailure both carry
    # record-quality-run.sh; if both ever fire for one tool call, the second
    # append is a no-op. A literal substring match on the compact line is
    # enough — jq -c always renders the key as `"tool_use_id":"<id>"`.
    if [ -n "$TOOL_USE_ID" ] && [ -f "$LEDGER" ] && [ ! -L "$LEDGER" ]; then
      if grep -qF -- "\"tool_use_id\":\"${TOOL_USE_ID}\"" "$LEDGER" 2>/dev/null; then
        exit 0
      fi
    fi
    mkdir -p "$SESSION_DIR" 2>/dev/null || {
      echo "flow-quality-ledger.sh: cannot create $SESSION_DIR" >&2
      exit 2
    }
    # `>>` opens with O_APPEND; a single short printf is one write(2), so
    # concurrent hook processes interleave whole lines, never partial ones.
    printf '%s\n' "$LINE" >> "$LEDGER" 2>/dev/null || {
      echo "flow-quality-ledger.sh: cannot append to $LEDGER" >&2
      exit 2
    }
    exit 0
    ;;

  status)
    if ! command -v python3 >/dev/null 2>&1; then
      echo "flow-quality-ledger.sh: python3 unavailable — cannot evaluate ledger" >&2
      echo "STATE=unavailable"
      exit 0
    fi
    CURRENT_DIGEST=""
    if [ -n "$CWD_ARG" ]; then
      CURRENT_DIGEST=$(_worktree_digest "$CWD_ARG" "${IGNORE_PREFIXES[@]+"${IGNORE_PREFIXES[@]}"}") || CURRENT_DIGEST=""
    fi
    # All values travel via argv; nothing from the ledger or the caller is
    # interpolated into the Python source.
    python3 - "$LEDGER" "$CWD_ARG" "$CURRENT_DIGEST" "${IGNORE_PREFIXES[@]+"${IGNORE_PREFIXES[@]}"}" <<'PYEOF'
import json
import os
import subprocess
import sys

ledger = sys.argv[1]
cwd = sys.argv[2]
current_digest = sys.argv[3]
prefixes = [os.path.abspath(p).rstrip(os.sep) for p in sys.argv[4:] if p]


def ignored(path):
    ap = os.path.abspath(path)
    for pre in prefixes:
        if ap == pre or ap.startswith(pre + os.sep):
            return True
    return False


class Run:
    __slots__ = ("at", "exit_code", "masked", "failed", "digest")

    def __init__(self, at, exit_code, masked, failed, digest):
        self.at = at
        self.exit_code = exit_code
        self.masked = masked
        self.failed = failed
        self.digest = digest

    @property
    def passing(self):
        return self.exit_code == 0 and not self.masked and not self.failed


entries = []  # (type, at, path, Run|None) in ledger order
if os.path.islink(ledger):
    print("flow-quality-ledger.sh: refusing to read — ledger is a symlink", file=sys.stderr)
elif os.path.isfile(ledger):
    try:
        with open(ledger, "r", encoding="utf-8", errors="replace") as f:
            for raw in f:
                line = raw.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(obj, dict):
                    continue
                at = obj.get("at")
                if not isinstance(at, str) or not at:
                    at = "unknown"
                kind = obj.get("type")
                if kind == "file_change":
                    path = obj.get("path")
                    if not isinstance(path, str) or not path:
                        continue
                    entries.append(("file_change", at, path, None))
                elif kind == "quality_run":
                    ec = obj.get("exit_code")
                    if isinstance(ec, bool) or not isinstance(ec, int):
                        ec = None
                    digest = obj.get("worktree_digest")
                    if not isinstance(digest, str) or not digest:
                        digest = None
                    run = Run(at, ec, obj.get("masked") is True, obj.get("failed") is True, digest)
                    entries.append(("quality_run", at, None, run))
    except OSError as e:
        print(f"flow-quality-ledger.sh: cannot read {ledger}: {e}", file=sys.stderr)

if not entries:
    print("STATE=empty")
    print("LAST_PASSING_RUN=none")
    print("LAST_RUN_EXIT=none")
    print("WORKTREE=unknown")
    print("CHANGED_SINCE=0")
    sys.exit(0)

last_pass_idx = -1
last_pass_run = None
last_run = None
for i, (etype, _at, _path, run) in enumerate(entries):
    if etype != "quality_run":
        continue
    last_run = run
    if run.passing:
        last_pass_idx = i
        last_pass_run = run

changed = []
def canonical(path):
    """One spelling per file, for de-duplication only.

    Ledger `file_change` paths are LOGICAL (they come from $PWD or a caller
    argument); `git status` paths are PHYSICAL (built from `git rev-parse
    --show-toplevel`). On macOS /var is a symlink to /private/var, so one
    edited file under TMPDIR arrives as both /var/folders/... and
    /private/var/folders/... and a string-keyed `seen` set never collapsed
    them — the operator was told `2 file(s) changed` for one edit.

    realpath is used for the KEY only. The reported path keeps its original
    spelling, which is the one the operator recognises."""
    try:
        return os.path.realpath(path)
    except (OSError, TypeError, ValueError):
        return path


seen = set()
for etype, _at, path, _run in entries[last_pass_idx + 1:]:
    # Type first: a non-file_change entry carries path=None, and
    # canonicalising it raises before the guard that would have skipped it.
    if etype != "file_change" or ignored(path):
        continue
    key = canonical(path)
    if key in seen:
        continue
    seen.add(key)
    changed.append(path)


def git_status_paths(directory):
    """Paths from `git status --porcelain=v1 -z`, absolute, repo-root relative
    input resolved. Empty on any git failure."""
    env = dict(os.environ, GIT_OPTIONAL_LOCKS="0")
    try:
        top = subprocess.run(
            ["git", "-C", directory, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, env=env, check=False,
        )
        if top.returncode != 0:
            return []
        root = top.stdout.strip()
        st = subprocess.run(
            ["git", "-C", root, "status", "--porcelain=v1", "-z", "--untracked-files=all"],
            capture_output=True, env=env, check=False,
        )
        if st.returncode != 0:
            return []
    except (OSError, ValueError):
        return []
    fields = st.stdout.split(b"\0")
    paths = []
    i = 0
    while i < len(fields):
        rec = fields[i]
        i += 1
        if len(rec) < 4:
            continue
        xy = rec[:2]
        rel = rec[3:].decode("utf-8", errors="replace")
        paths.append(os.path.join(root, rel))
        # Renames/copies carry the original path as the next NUL field.
        if b"R" in xy or b"C" in xy:
            i += 1
    return paths


worktree = "unknown"
if last_pass_run is not None and last_pass_run.digest and current_digest:
    if current_digest == last_pass_run.digest:
        worktree = "unchanged"
    else:
        worktree = "changed"
        for path in git_status_paths(cwd):
            key = canonical(path)
            if key in seen or ignored(path):
                continue
            seen.add(key)
            changed.append(path)

dirty = bool(changed) or worktree == "changed"
print("STATE=dirty" if dirty else "STATE=clean")
print(f"LAST_PASSING_RUN={last_pass_run.at if last_pass_run else 'none'}")
if last_run is None:
    print("LAST_RUN_EXIT=none")
else:
    print(f"LAST_RUN_EXIT={'null' if last_run.exit_code is None else last_run.exit_code}")
    if last_run.masked:
        print("LAST_RUN_MASKED=true")
    if last_run.failed:
        print("LAST_RUN_FAILED=true")
print(f"WORKTREE={worktree}")
print(f"CHANGED_SINCE={len(changed)}")
for path in changed[:5]:
    print(f"CHANGED_FILE={path}")
PYEOF
    exit $?
    ;;
esac
