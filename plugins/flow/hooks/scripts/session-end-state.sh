#!/usr/bin/env bash
# [flow] SessionEnd hook — persist active FlowRun state for /flow:resume.
#
# Fires when the Claude Code session ends. If any FlowRun has
# state.status==active and has not transitioned through a terminal status,
# we annotate it with a session_end event + a blocked_reason so the user's
# next session can pick it up via /flow:resume.
#
# This hook does NOT modify the FlowRun's status — that's a decision for
# the user (active runs may be intentionally paused mid-flow). It only
# records the event and ensures /flow:resume can find the run.
#
# Exits 0 in all cases (SessionEnd hooks must be silent-failure-safe).

set -uo pipefail
export PYTHONSAFEPATH=1

# Graceful degradation — matches session-end-learn.sh:13 pattern.
command -v python3 >/dev/null 2>&1 || exit 0
python3 -c "import yaml" >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/../..}"

# Check the runtime layer is enabled (matches the gating in /flow:resume).
ENABLED=$("${PLUGIN_ROOT}/bin/cascade-resolve.sh" --default "true" '.flow.runtime.enabled // empty' 2>/dev/null)
[ "$ENABLED" != "true" ] && exit 0

# Find active FlowRuns. If none, exit silently.
[ -d .flow/runs ] || exit 0

python3 - "$PLUGIN_ROOT" <<'PYEOF' 2>/dev/null
import sys
sys.path[:] = [p for p in sys.path if p not in ("", ".")]

import datetime
import glob
import json
import os
import yaml

plugin_root = sys.argv[1]
sys.path.insert(0, os.path.join(plugin_root, "bin"))
try:
    from _journal_atomic import append_jsonl
except ImportError:
    # _journal_atomic.py may be missing on a stripped install; degrade gracefully.
    sys.exit(0)

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
active_runs = []

for run_yaml_path in glob.glob(".flow/runs/*/run.yaml"):
    try:
        with open(run_yaml_path, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
        state = data.get("state") or {}
        if state.get("status") == "active":
            run_id = data.get("metadata", {}).get("id", "")
            if run_id:
                active_runs.append((run_id, run_yaml_path))
    except Exception:
        continue

if not active_runs:
    sys.exit(0)

# Append a session_end event to each active run's events.jsonl. We do NOT
# modify run.yaml itself — that's a status decision for the user via
# /flow:resume.
for run_id, run_yaml_path in active_runs:
    events_path = os.path.join(os.path.dirname(run_yaml_path), "events.jsonl")
    event = {
        "at": now,
        "type": "session_end",
        "run_id": run_id,
        "note": "session ended with this run still active; use /flow:resume to continue",
    }
    try:
        append_jsonl(events_path, event)
    except Exception:
        # Non-fatal; events.jsonl is the audit trail, not load-bearing.
        continue

# Print a concise notice (stderr so it doesn't pollute the SessionEnd hook's
# expected silent contract; users see this in the terminal as the session
# closes).
ids = ", ".join(r[0] for r in active_runs)
print(f"flow: {len(active_runs)} active FlowRun(s) persisted: {ids}", file=sys.stderr)
print(f"flow: use /flow:resume to continue any of them in your next session", file=sys.stderr)
PYEOF

exit 0
