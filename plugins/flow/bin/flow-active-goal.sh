#!/usr/bin/env bash
# [flow] Find the active FlowGoal and inspect it.
#
# Used by /flow:pr, /flow:merge, /flow:status, /flow:learn, and any other
# command that needs to know whether a FlowGoal is in flight and what its
# state is. Centralized so changes to the .flow/goals/ layout or YAML
# schema only touch one reader.
#
# Output modes (exactly one allowed, default --status):
#   --path        absolute-or-relative path to .flow/goals/<id>.goal.yaml
#   --id          metadata.id
#   --status      lifecycle.status (e.g., active, waiting_for_user)
#   --json        full goal as JSON, sorted keys (jq-compatible)
#   --ac-summary  one line per AC: <id>|<status>|<evidence_ref>|<last_result>
#
# Exit codes:
#   0  active goal found; output on stdout
#   1  no active goal (caller decides whether this is OK)
#   2  infrastructure error (python3 / PyYAML missing; symlink rejected)
#   3  degenerate state (>1 active goal — should never happen)
#
# Symlink defense: refuses to read if .flow/goals/ or any *.goal.yaml is a
# symlink. Matches bin/journal-record.sh and bin/flow-record-verdict.sh.

set -euo pipefail
export PYTHONSAFEPATH=1

MODE="--status"
SAW_MODE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --path|--id|--status|--json|--ac-summary)
      [ "$SAW_MODE" = "1" ] && { echo "flow-active-goal.sh: only one mode flag allowed (got both $MODE and $1)" >&2; exit 2; }
      MODE="$1"
      SAW_MODE=1
      shift
      ;;
    -h|--help)
      sed -n '2,24p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "flow-active-goal.sh: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "flow-active-goal.sh: python3 required but not installed" >&2
  exit 2
fi
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  echo "flow-active-goal.sh: PyYAML required (apt install python3-yaml / pip install pyyaml)" >&2
  exit 2
fi

# Symlink defense — refuse to read if .flow/goals/ is a symlink.
if [ -L ".flow/goals" ]; then
  echo "flow-active-goal.sh: refusing — .flow/goals/ is a symlink" >&2
  exit 2
fi

python3 - "$MODE" <<'PYEOF'
import sys, glob, os, json
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
import yaml

mode = sys.argv[1]

if not os.path.isdir(".flow/goals"):
    sys.exit(1)

active = []
for path in sorted(glob.glob(".flow/goals/*.goal.yaml")):
    if os.path.islink(path):
        print(f"flow-active-goal.sh: refusing — {path} is a symlink", file=sys.stderr)
        sys.exit(2)
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
        if (data.get("lifecycle") or {}).get("status") == "active":
            active.append((path, data))
    except Exception:
        # Tolerate unparseable goals — they would block lookup of a sibling
        # legitimate active goal. The Stop hook + status subcommand follow
        # the same tolerate-and-continue pattern.
        continue

if not active:
    sys.exit(1)
if len(active) > 1:
    paths = [p for p, _ in active]
    print(
        f"flow-active-goal.sh: degenerate state — {len(active)} active goals: {', '.join(paths)}",
        file=sys.stderr,
    )
    sys.exit(3)

path, data = active[0]

if mode == "--path":
    print(path)
elif mode == "--id":
    print((data.get("metadata") or {}).get("id", ""))
elif mode == "--status":
    print((data.get("lifecycle") or {}).get("status", ""))
elif mode == "--json":
    print(json.dumps(data, sort_keys=True))
elif mode == "--ac-summary":
    # Cycle-14 F1 (code-reviewer skeptic): sanitize ALL emitted fields for
    # both newlines (line-break contract) and pipes (column-separator
    # contract). A goal YAML with a pipe character in any field would
    # silently inject extra columns into the documented
    # `<id>|<status>|<evidence_ref>|<last_result>` format. Replace pipe
    # with U+2502 (box drawings light vertical) so the visual intent is
    # preserved without breaking parsers.
    def _sanitize(value):
        s = " ".join(str(value).split())  # collapse all whitespace incl. newlines
        return s.replace("|", "│")
    acs = ((data.get("objective") or {}).get("acceptance_criteria") or [])
    for ac in acs:
        if not isinstance(ac, dict):
            # Cycle-14 F7 (code-reviewer verifier): tolerate malformed AC
            # shapes (string instead of dict) rather than crashing with
            # AttributeError outside the try/except in the search loop.
            continue
        ac_id = _sanitize(ac.get("id", "?"))
        status = _sanitize(ac.get("status", "pending"))
        evidence_ref = _sanitize(ac.get("evidence_ref") or "-")
        last_result = _sanitize(ac.get("last_result") or "-")
        print(f"{ac_id}|{status}|{evidence_ref}|{last_result}")
else:
    print(f"flow-active-goal.sh: unknown mode {mode}", file=sys.stderr)
    sys.exit(2)
PYEOF
