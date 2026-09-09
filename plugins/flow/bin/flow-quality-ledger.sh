#!/usr/bin/env bash
# [flow] Per-session quality ledger — the file-backed state behind the
# TaskCompleted gate (hooks/scripts/verify-task-completion.sh).
#
# The ledger is an append-only JSONL file:
#   ${FLOW_STATE_DIR:-$HOME/.claude/flow-state}/sessions/<session_id>/quality-ledger.jsonl
#
# Entry shapes (one JSON object per line):
#   {"at":"<ISO-8601 UTC>","type":"file_change","tool":"Edit|Write","path":"<absolute path>"}
#   {"at":"<ISO-8601 UTC>","type":"quality_run","command":"<first 200 chars>",
#    "exit_code":<int|null>,"kind":"test|lint|typecheck|build|project"}
#
# Writers: hooks/scripts/log-file-changes.sh (file_change) and
# hooks/scripts/record-quality-run.sh (quality_run). Reader:
# hooks/scripts/verify-task-completion.sh (status).
#
# Usage:
#   flow-quality-ledger.sh append --session <id> --json '<object>'
#   flow-quality-ledger.sh path   --session <id>
#   flow-quality-ledger.sh status --session <id> [--ignore-prefix <path>]...
#
# `status` prints, one per line:
#   STATE=clean|dirty|empty|unavailable
#   LAST_PASSING_RUN=<at|none>      time of the most recent quality_run with exit_code 0
#   LAST_RUN_EXIT=<code|null|none>  exit code of the most recent quality_run of any
#                                   outcome ("null" when that run had no exit code,
#                                   "none" when no quality_run exists)
#   CHANGED_SINCE=<n>               distinct files changed after the last passing run
#   CHANGED_FILE=<path>             up to five of those files, in first-change order
#
# "dirty" means at least one file_change entry sits after the most recent
# passing quality_run in the ledger (or no passing run exists and there is at
# least one file_change). "empty" means the ledger is missing or holds no
# parseable entry. "unavailable" means python3 is missing — the gate cannot
# evaluate, so callers treat it as pass-through. Ordering is ledger position
# (append order), not the `at` timestamp: hooks append in the order the tools
# ran, and timestamps only carry one-second resolution.
#
# file_change entries whose path is under an --ignore-prefix (resolved against
# the current working directory) are skipped: callers pass the decision journal
# directory, .flow/, and .screenshots/ so bookkeeping writes never dirty the
# gate.
#
# Malformed lines (partial writes, non-object JSON, missing fields) are skipped.
#
# Exit codes:
#   0 — success (status always exits 0, including STATE=unavailable)
#   1 — usage error (unknown subcommand, bad --session, invalid --json)
#   2 — infrastructure error (ledger or its directory is a symlink; write failed)

set -uo pipefail
export PYTHONSAFEPATH=1

_usage() {
  sed -n '2,50p' "$0" | sed 's/^# \?//'
}

SUBCOMMAND="${1:-}"
[ -z "$SUBCOMMAND" ] && { _usage >&2; exit 1; }
shift

case "$SUBCOMMAND" in
  append|path|status) ;;
  -h|--help) _usage; exit 0 ;;
  *) echo "flow-quality-ledger.sh: unknown subcommand: $SUBCOMMAND" >&2; exit 1 ;;
esac

SESSION_ID=""
JSON_ENTRY=""
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

# The session id becomes a directory name under the state dir. Claude Code
# session ids are UUIDs; anything with a path separator, `..`, or a leading
# dot is refused so a hostile payload cannot steer writes outside the ledger
# tree.
if ! [[ "$SESSION_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]; then
  echo "flow-quality-ledger.sh: --session must be 1-128 chars of [A-Za-z0-9._-] starting alphanumeric (got: '${SESSION_ID}')" >&2
  exit 1
fi

STATE_ROOT="${FLOW_STATE_DIR:-${HOME:-/nonexistent}/.claude/flow-state}"
SESSION_DIR="$STATE_ROOT/sessions/$SESSION_ID"
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
    if command -v jq >/dev/null 2>&1; then
      LINE=$(printf '%s' "$JSON_ENTRY" | jq -c 'if type == "object" then . else error("entry must be a JSON object") end' 2>/dev/null) || {
        echo "flow-quality-ledger.sh: --json is not a JSON object" >&2
        exit 1
      }
    else
      case "$JSON_ENTRY" in
        *$'\n'*|*$'\r'*)
          echo "flow-quality-ledger.sh: --json must be a single line when jq is unavailable" >&2
          exit 1
          ;;
      esac
      LINE="$JSON_ENTRY"
    fi
    # Symlink defense: the state dir lives under $HOME, but a pre-staged
    # symlink (e.g. from a shared FLOW_STATE_DIR) must never redirect appends.
    # `>>` follows symlinks, so check every component we create or write.
    for p in "$STATE_ROOT" "$STATE_ROOT/sessions" "$SESSION_DIR" "$LEDGER"; do
      if [ -L "$p" ]; then
        echo "flow-quality-ledger.sh: refusing — $p is a symlink" >&2
        exit 2
      fi
    done
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
    # All values travel via argv; nothing from the ledger or the caller is
    # interpolated into the Python source.
    python3 - "$LEDGER" "${IGNORE_PREFIXES[@]+"${IGNORE_PREFIXES[@]}"}" <<'PYEOF'
import json
import os
import sys

ledger = sys.argv[1]
prefixes = [os.path.abspath(p).rstrip(os.sep) for p in sys.argv[2:] if p]


def ignored(path):
    ap = os.path.abspath(path)
    for pre in prefixes:
        if ap == pre or ap.startswith(pre + os.sep):
            return True
    return False


entries = []  # (type, at, path, exit_code) in ledger order
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
                    entries.append(("quality_run", at, None, ec))
    except OSError as e:
        print(f"flow-quality-ledger.sh: cannot read {ledger}: {e}", file=sys.stderr)

if not entries:
    print("STATE=empty")
    print("LAST_PASSING_RUN=none")
    print("LAST_RUN_EXIT=none")
    print("CHANGED_SINCE=0")
    sys.exit(0)

last_pass_idx = -1
last_pass_at = "none"
last_run_exit = "none"
for i, (etype, at, _path, ec) in enumerate(entries):
    if etype != "quality_run":
        continue
    last_run_exit = "null" if ec is None else str(ec)
    if ec == 0:
        last_pass_idx = i
        last_pass_at = at

changed = []
seen = set()
for etype, _at, path, _ec in entries[last_pass_idx + 1:]:
    if etype != "file_change" or path in seen or ignored(path):
        continue
    seen.add(path)
    changed.append(path)

print("STATE=dirty" if changed else "STATE=clean")
print(f"LAST_PASSING_RUN={last_pass_at}")
print(f"LAST_RUN_EXIT={last_run_exit}")
print(f"CHANGED_SINCE={len(changed)}")
for path in changed[:5]:
    print(f"CHANGED_FILE={path}")
PYEOF
    exit $?
    ;;
esac
