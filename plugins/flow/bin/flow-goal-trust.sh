#!/usr/bin/env bash
# [flow] Per-user trust ledger for FlowGoal verification commands.
#
# A goal's `verification_command` strings run under `bash -c` on every Stop
# event. Executing them from a goal that arrived with a hostile checkout is
# the attack the `flow.goals.executeVerificationCommands: false` default
# prevents — but that default also makes `stopHookEnforcement: block`
# unusable, because every AC with a command is reported `not_executed`.
#
# The trust ledger closes that gap: a goal created through flow in THIS
# user's environment is recorded here (repo + goal id + sha256 over its AC
# ids and commands), and the deterministic-checks runner executes commands
# only for goals whose current commands still match a recorded entry.
# Editing a verification_command by hand changes the hash; re-record to
# trust the edit.
#
# Ledger: ${FLOW_STATE_DIR:-$HOME/.claude/flow-state}/goal-trust.jsonl
# Entry:  {"recorded_at","repo","goal_id","commands_sha256","session_id"}
#
# Usage:
#   flow-goal-trust.sh record --goal-file <path>   append an entry for the goal
#   flow-goal-trust.sh check  --goal-file <path>   TRUSTED=yes (exit 0) | TRUSTED=no (exit 1)
#   flow-goal-trust.sh list                        print every entry, one JSON line each
#
# `repo` is `git rev-parse --show-toplevel` when inside a git work tree,
# otherwise the physical current directory. record and check must run from
# the same repo for an entry to match.
#
# Exits:
#   0 — record/list succeeded; check: goal is trusted
#   1 — input error (missing arg, unreadable goal YAML); check: goal not trusted
#   2 — infrastructure error (python3/PyYAML missing, ledger is a symlink, write failed)

set -uo pipefail
export PYTHONSAFEPATH=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "flow-goal-trust.sh: python3 required but not installed" >&2
  exit 2
fi
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  echo "flow-goal-trust.sh: PyYAML required (apt install python3-yaml / pip install pyyaml)" >&2
  exit 2
fi

SUBCOMMAND="${1:-}"
[ $# -gt 0 ] && shift
GOAL_FILE=""

case "$SUBCOMMAND" in
  record|check|list) ;;
  -h|--help|"")
    sed -n '2,33p' "$0" | sed 's/^# \?//'
    [ -z "$SUBCOMMAND" ] && exit 1
    exit 0
    ;;
  *)
    echo "flow-goal-trust.sh: unknown subcommand '$SUBCOMMAND' — expected record | check | list" >&2
    exit 1
    ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    --goal-file)
      [ $# -lt 2 ] && { echo "flow-goal-trust.sh: --goal-file requires a value" >&2; exit 1; }
      GOAL_FILE="$2"; shift 2 ;;
    *)
      echo "flow-goal-trust.sh: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ "$SUBCOMMAND" != "list" ]; then
  [ -z "$GOAL_FILE" ] && { echo "flow-goal-trust.sh: --goal-file is required for $SUBCOMMAND" >&2; exit 1; }
  [ -f "$GOAL_FILE" ] || { echo "flow-goal-trust.sh: --goal-file '$GOAL_FILE' does not exist" >&2; exit 1; }
fi

LEDGER_DIR="${FLOW_STATE_DIR:-${HOME}/.claude/flow-state}"
LEDGER="${LEDGER_DIR}/goal-trust.jsonl"

# Repo identity: git toplevel when available, else the physical cwd.
REPO=$(git rev-parse --show-toplevel 2>/dev/null) || REPO=$(pwd -P)

if [ "$SUBCOMMAND" = "record" ]; then
  if ! mkdir -p "$LEDGER_DIR" 2>/dev/null; then
    echo "flow-goal-trust.sh: cannot create ledger directory $LEDGER_DIR" >&2
    exit 2
  fi
  chmod 0700 "$LEDGER_DIR" 2>/dev/null || true
fi

# Every attacker-influenceable value (goal path, repo path, session id) is
# passed via argv — never interpolated into the Python source.
python3 - "$SCRIPT_DIR" "$SUBCOMMAND" "$GOAL_FILE" "$LEDGER" "$REPO" "${CLAUDE_SESSION_ID:-}" <<'PYTHON'
import sys
sys.path[:] = [p for p in sys.path if p not in ("", ".")]

script_dir = sys.argv[1]
sys.path.insert(0, script_dir)

import datetime
import hashlib
import json
import os
import stat

import yaml
from _journal_atomic import JournalAtomicError, _read_with_no_follow, append_jsonl

subcommand, goal_file, ledger, repo, session_id = sys.argv[2:7]


def fail(msg, code):
    print(f"flow-goal-trust.sh: {msg}", file=sys.stderr)
    sys.exit(code)


def load_goal(path):
    try:
        content = _read_with_no_follow(path)
    except JournalAtomicError as e:
        fail(str(e), 2)
    try:
        goal = yaml.safe_load(content)
    except yaml.YAMLError as e:
        fail(f"goal YAML parse error: {e}", 1)
    if not isinstance(goal, dict):
        fail("goal YAML is not a mapping", 1)
    goal_id = (goal.get("metadata") or {}).get("id")
    if not isinstance(goal_id, str) or not goal_id or ".." in goal_id or "/" in goal_id:
        fail("goal.metadata.id is missing or contains '..' or '/'", 1)
    return goal, goal_id


def commands_sha256(goal):
    """sha256 over the canonical JSON of [{id, verification_command}, ...]
    sorted by AC id. Compact separators + sorted keys make the encoding
    stable across PyYAML round-trips and hand edits that only reflow the
    file; any change to an AC id or command changes the digest."""
    acs = (goal.get("objective") or {}).get("acceptance_criteria") or []
    rows = []
    for ac in acs:
        if not isinstance(ac, dict):
            continue
        rows.append({
            "id": str(ac.get("id", "")),
            "verification_command": ac.get("verification_command"),
        })
    rows.sort(key=lambda r: r["id"])
    canonical = json.dumps(rows, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def refuse_symlinked_ledger():
    try:
        st = os.lstat(ledger)
    except FileNotFoundError:
        return False
    except OSError as e:
        fail(f"cannot stat ledger {ledger}: {e}", 2)
    if stat.S_ISLNK(st.st_mode):
        fail(f"refusing — ledger {ledger} is a symlink", 2)
    return True


def read_entries():
    if not refuse_symlinked_ledger():
        return []
    try:
        content = _read_with_no_follow(ledger)
    except JournalAtomicError as e:
        fail(str(e), 2)
    entries = []
    for line in content.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue  # partial write from a killed writer; JSONL readers skip
        if isinstance(entry, dict):
            entries.append(entry)
    return entries


if subcommand == "record":
    goal, goal_id = load_goal(goal_file)
    refuse_symlinked_ledger()
    entry = {
        "recorded_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "repo": repo,
        "goal_id": goal_id,
        "commands_sha256": commands_sha256(goal),
        "session_id": session_id,
    }
    try:
        append_jsonl(ledger, entry)
    except JournalAtomicError as e:
        fail(str(e), e.exit_code)
    print(f"flow-goal-trust.sh: recorded {goal_id} ({entry['commands_sha256'][:12]}…) in {ledger}", file=sys.stderr)
    sys.exit(0)

if subcommand == "check":
    goal, goal_id = load_goal(goal_file)
    digest = commands_sha256(goal)
    for entry in read_entries():
        if (
            entry.get("repo") == repo
            and entry.get("goal_id") == goal_id
            and entry.get("commands_sha256") == digest
        ):
            print("TRUSTED=yes")
            sys.exit(0)
    print("TRUSTED=no")
    sys.exit(1)

if subcommand == "list":
    entries = read_entries()
    if not entries:
        print(f"flow-goal-trust.sh: no entries in {ledger}", file=sys.stderr)
    for entry in entries:
        print(json.dumps(entry, sort_keys=True))
    sys.exit(0)
PYTHON
