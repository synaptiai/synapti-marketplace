#!/usr/bin/env bash
# [flow] Find the active FlowGoal and inspect it.
#
# Used by /flow:pr, /flow:merge, /flow:status, /flow:learn, and any other
# command that needs to know whether a FlowGoal is in flight and what its
# state is. Centralized so changes to the .flow/goals/ layout or YAML
# schema only touch one reader.
#
# Output modes (exactly one allowed, default --status):
#   --path             absolute-or-relative path to .flow/goals/<id>.goal.yaml
#   --id               metadata.id
#   --status           lifecycle.status (e.g., active, waiting_for_user)
#   --json             full goal as JSON, sorted keys (jq-compatible)
#   --ac-summary       one line per AC: <id>|<status>|<evidence_ref>|<last_result>
#   --verifiable-count <total>/<verifiable> — AC count and the subset carrying a
#                      non-empty verification_command (used by the AC-2 degenerate marker)
#
# Branch scoping (#111 AC-4):
#   Selection is branch-first. The active goal whose scope.branch matches the
#   current git branch is preferred; if none matches (or the branch is unknown,
#   e.g. detached HEAD / legacy goals predating scope.branch), the most-recently-
#   modified active goal is returned. Exit 3 (degenerate) fires ONLY when >1
#   active goal share the current branch — concurrent goals on *different*
#   branches/worktrees each resolve cleanly.
#   --branch <name>    override the detected current branch (test-only / scripting)
#
# Exit codes:
#   0  active goal found; output on stdout
#   1  no active goal (caller decides whether this is OK)
#   2  infrastructure error (python3 / PyYAML missing; symlink rejected)
#   3  degenerate state (>1 active goal on the current branch)
#
# Symlink defense: refuses to read if .flow/goals/ or any *.goal.yaml is a
# symlink. Matches bin/journal-record.sh and bin/flow-record-verdict.sh.

set -euo pipefail
export PYTHONSAFEPATH=1

MODE="--status"
SAW_MODE=0
OVERRIDE_BRANCH=""

while [ $# -gt 0 ]; do
  case "$1" in
    --path|--id|--status|--json|--ac-summary|--verifiable-count)
      [ "$SAW_MODE" = "1" ] && { echo "flow-active-goal.sh: only one mode flag allowed (got both $MODE and $1)" >&2; exit 2; }
      MODE="$1"
      SAW_MODE=1
      shift
      ;;
    --branch)
      [ $# -lt 2 ] && { echo "flow-active-goal.sh: --branch requires a value" >&2; exit 2; }
      OVERRIDE_BRANCH="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,34p' "$0" | sed 's/^# \?//'
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

python3 - "$MODE" "${OVERRIDE_BRANCH:-}" <<'PYEOF'
import sys, glob, os, json, subprocess
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
import yaml

mode = sys.argv[1]
override_branch = sys.argv[2] if len(sys.argv) > 2 else ""

if not os.path.isdir(".flow/goals"):
    sys.exit(1)

# Determine the current branch for branch-first selection (#111 AC-4). An
# explicit --branch override wins (test-only / scripting); otherwise ask git,
# tolerating any failure (not a repo, detached HEAD, git missing) by treating
# the branch as unknown ("").
current_branch = override_branch
if not current_branch:
    try:
        r = subprocess.run(
            ["git", "branch", "--show-current"],
            capture_output=True, text=True, timeout=5,
        )
        if r.returncode == 0:
            current_branch = r.stdout.strip()
    except Exception:
        current_branch = ""

active = []
for path in sorted(glob.glob(".flow/goals/*.goal.yaml")):
    if os.path.islink(path):
        print(f"flow-active-goal.sh: refusing — {path} is a symlink", file=sys.stderr)
        sys.exit(2)
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
        if (data.get("lifecycle") or {}).get("status") == "active":
            branch = (data.get("scope") or {}).get("branch") or ""
            try:
                mtime = os.path.getmtime(path)
            except OSError:
                mtime = 0.0
            active.append((path, data, branch, mtime))
    except Exception:
        # Tolerate unparseable goals — they would block lookup of a sibling
        # legitimate active goal. The Stop hook + status subcommand follow
        # the same tolerate-and-continue pattern.
        continue

if not active:
    sys.exit(1)

# Branch-first selection (#111 AC-4): prefer goals whose scope.branch matches
# the current branch. Exit 3 (degenerate) fires ONLY when >1 active goal share
# the current branch — concurrent goals on different branches no longer collide.
candidates = [t for t in active if current_branch and t[2] == current_branch]
if candidates:
    if len(candidates) > 1:
        paths = [t[0] for t in candidates]
        print(
            f"flow-active-goal.sh: degenerate state — {len(candidates)} active goals "
            f"on branch '{current_branch}': {', '.join(paths)}",
            file=sys.stderr,
        )
        sys.exit(3)
    path, data = candidates[0][0], candidates[0][1]
else:
    # No active goal owns the current branch (or the branch is unknown / legacy
    # goals predate scope.branch): fall back to the most-recently-modified
    # active goal so single-goal callers (e.g. run from main) still resolve.
    best = max(active, key=lambda t: t[3])
    path, data = best[0], best[1]

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
elif mode == "--verifiable-count":
    # #111 AC-2: emit "<total>/<verifiable>" so the compact summary can flag a
    # degenerate goal (0 ACs, or 0 ACs carrying a non-empty verification_command)
    # without re-parsing the YAML. A verification_command of "" or whitespace is
    # not verifiable.
    acs = ((data.get("objective") or {}).get("acceptance_criteria") or [])
    total = 0
    verifiable = 0
    for ac in acs:
        if not isinstance(ac, dict):
            continue
        total += 1
        vc = ac.get("verification_command")
        if isinstance(vc, str) and vc.strip():
            verifiable += 1
    print(f"{total}/{verifiable}")
else:
    print(f"flow-active-goal.sh: unknown mode {mode}", file=sys.stderr)
    sys.exit(2)
PYEOF
