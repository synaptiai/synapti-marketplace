#!/usr/bin/env bash
# [flow] Record the most-recent verdict for a FlowRun.
#
# Writes .flow/runs/<run-id>/last-verdict.json — read by
# bin/_flow_evidence_bundle.py on subsequent turns to compute delta
# (made_progress / unchanged / regressed). Without this producer, every
# evaluator-loop turn computes delta against "nothing", so the loop has
# no memory across iterations.
#
# Two callers:
#   1. hooks/scripts/flow-goal-evaluator.sh — after the judge subprocess
#      returns a structured verdict (every evaluator-loop turn)
#   2. /flow:goal evaluate (manual mode) — after the goal-evaluator skill
#      produces a verdict at user request
#
# Verdict file shape (validated before write):
#   {
#     "verdict": "achieved | not_achieved | blocked | needs_human_review",
#     "confidence": 0.0-1.0,
#     "delta": "made_progress | unchanged | regressed",
#     "reason": "...",
#     "criterion_results": [...],         (optional)
#     "next_step_hint": "...",            (optional)
#     "blocker_type": "...",              (optional)
#     "recorded_at": "2026-05-20T14:30:00Z" (auto-added if absent)
#   }
#
# Usage:
#   flow-record-verdict.sh --run-id <ISO-id> --verdict-file <path-to-json>
#
# Atomicity: writes go through bin/_journal_atomic.py (O_NOFOLLOW + flock
# + tempfile+rename+fsync). Replace semantics — each turn supersedes the
# prior file.
#
# The run directory is created if it is missing, and never through a
# symlink: when .flow, .flow/runs or the run directory is one, nothing is
# written and the helper exits 2 (a repository can commit such a link to a
# directory outside the checkout).
#
# Every message is one line of text: a value in it is escaped and, when no
# earlier check has bounded it, cut (bin/_flow_cli.py).
#
# Exits:
#   0 — verdict recorded, an over-long optional field cut and reported; or
#       --help
#   1 — the arguments or the input: an argument that is not an option, or an
#       option with no value; no --run-id or no --verdict-file; a --run-id
#       holding '..' or '/', or bare '.' or '..', or longer than a directory
#       name; a --verdict-file that is not there or not a regular file, or
#       that cannot be read for a reason of its path; a verdict file that is
#       not UTF-8, not valid JSON or nested too deep to read; a verdict that
#       is not an object, lacks a required key, or holds a value out of its
#       range or of the wrong type
#   2 — python3 or PyYAML missing; a --verdict-file that is a symlink, or
#       that cannot be read for a reason of the system; the run directory
#       refused or not made (a symlinked .flow, .flow/runs or run directory
#       included); the write refused or failing

set -euo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH
# Keep the repository out of PYTHONPATH before python3 starts: the interpreter
# imports sitecustomize from each element at startup. An isolated python3 (-I:
# it reads neither PYTHONPATH nor the working directory) keeps only elements
# that are directories outside the repository and not at or above the working
# directory, comparing directories by identity, not by how the path is spelled;
# tests/syspath-guard.test.sh has the reasons. FLOW_USER_PYTHONPATH keeps the
# original for commands run for the user.
[ -n "${FLOW_USER_PYTHONPATH+x}" ] || export FLOW_USER_PYTHONPATH="${PYTHONPATH-}"
_flow_pp=""; if [ -n "${PYTHONPATH-}" ]; then _flow_pp=$(python3 -I -c 'exec("import os, sys\ndef ids(p):\n    out = set()\n    while True:\n        try:\n            st = os.stat(p)\n        except OSError:\n            return out\n        out.add((st.st_dev, st.st_ino))\n        q = os.path.dirname(p)\n        if q == p:\n            return out\n        p = q\ntry:\n    cwd = os.getcwd()\nexcept OSError:\n    sys.exit(0)\ntop = d = cwd\nwhile True:\n    if os.path.lexists(os.path.join(d, \".git\")):\n        top = d\n        break\n    q = os.path.dirname(d)\n    if q == d:\n        break\n    d = q\nst = os.stat(top)\ntop_id = (st.st_dev, st.st_ino)\nup = ids(cwd)\nkeep = []\nfor e in os.environ.get(\"PYTHONPATH\", \"\").split(\":\"):\n    if not e.startswith(\"/\"):\n        continue\n    r = os.path.realpath(e)\n    if \":\" in r or chr(10) in r or not os.path.isdir(r):\n        continue\n    try:\n        st = os.stat(r)\n    except OSError:\n        continue\n    if (st.st_dev, st.st_ino) in up or top_id in ids(r):\n        continue\n    keep.append(r)\nsys.stdout.buffer.write(os.fsencode(\":\".join(keep)))")' 2>/dev/null) || _flow_pp=""; fi
if [ -n "$_flow_pp" ]; then export PYTHONPATH="$_flow_pp"; else unset PYTHONPATH; fi
export PYTHONSAFEPATH=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "flow-record-verdict.sh: python3 required but not installed" >&2
  exit 2
fi
# PyYAML is imported transitively by _journal_atomic.py — check here so
# callers see a clear message instead of a Python traceback. Matches the
# graceful-degradation pattern used by flow-record-evidence.sh and
# flow-record-activity.sh.
if ! python3 -c "import os, sys; sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and not (os.path.isdir(p) and os.access(os.curdir, os.X_OK) and os.path.samefile(p, os.curdir))]; import yaml" >/dev/null 2>&1; then
  echo "flow-record-verdict.sh: PyYAML required (apt install python3-yaml / pip install pyyaml)" >&2
  exit 2
fi

# --help, where an option is expected. Every other argument is python3's to
# read, and to refuse: a message that prints a value is written by one
# printer, whatever the shell's locale.
wants_help() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --run-id|--verdict-file) [ $# -ge 2 ] || return 1; shift 2 ;;
      -h|--help) return 0 ;;
      *) return 1 ;;
    esac
  done
  return 1
}
if wants_help "$@"; then
  awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
  exit 0
fi

# The run directory is created in Python, after the verdict is validated,
# through ensure_repo_dir(): O_NOFOLLOW on the verdict file alone is
# insufficient if .flow, .flow/runs or .flow/runs/<id> is a symlink to a
# directory outside the repository — mkdir -p would follow it, and
# tempfile.mkstemp + os.rename inside _journal_atomic would then write there.
python3 - "$SCRIPT_DIR" "$@" <<'PYTHON'
# Keep the working directory (the repository) off sys.path before any other
# import; tests/syspath-guard.test.sh has the reasons.
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]
import sys

script_dir = sys.argv[1]
sys.path.insert(0, script_dir)

import datetime
import json
import os
from _flow_cli import Messages, name_max, shown
from _journal_atomic import JournalAtomicError, ensure_repo_dir, write_json_file

messages = Messages("flow-record-verdict.sh")
say, refuse = messages.say, messages.refuse

options = messages.read_arguments(sys.argv[2:], ("--run-id", "--verdict-file"))
run_id = options["--run-id"]
verdict_file = options["--verdict-file"]
if not run_id:
    refuse("--run-id is required")
if not verdict_file:
    refuse("--verdict-file is required")
# Defense against path traversal in the run-id (the schema also rejects
# but defend at every layer per project convention), and the bare `.`/`..`
# identifiers, which would collapse the run dir to `.flow/runs/` itself. A
# run id longer than a directory name fails to be made, and its error prints
# the whole path.
if run_id in (".", "..") or ".." in run_id or "/" in run_id:
    refuse(f"--run-id contains '..' or '/' or is bare '.'/'..' — refusing for safety (got: {shown(run_id)})")
NAME_MAX = name_max()
run_id_bytes = len(os.fsencode(run_id))
if run_id_bytes > NAME_MAX:
    refuse(f"--run-id is {run_id_bytes} bytes; a directory name here holds at most {NAME_MAX}")
run_dir = os.path.join(".flow", "runs", run_id)

# The verdict file is opened as the recorder opens its inputs
# (bin/_flow_cli.py): looked at by name, then opened without following a
# symlink (refused by name where there is no O_NOFOLLOW) and without waiting
# (a FIFO put in its place is opened, then refused), and refused unless fstat
# says a regular file; 1 for a path that is not there, cannot be read or is
# not a regular file, 2 for a symlink or a failure of the system.
src_fd = messages.open_input(verdict_file, "--verdict-file", "--verdict-file")
try:
    with os.fdopen(src_fd, "r", encoding="utf-8") as f:
        verdict_data = json.load(f)
except json.JSONDecodeError as e:
    refuse(f"--verdict-file is not valid JSON: {shown(e)}")
except RecursionError:
    refuse("--verdict-file is nested too deep to read")
except UnicodeDecodeError as e:
    refuse(f"--verdict-file is not UTF-8: {shown(e)}")
except OSError as e:
    messages.cannot("read", "--verdict-file", verdict_file, e)

if not isinstance(verdict_data, dict):
    refuse("verdict JSON must be a top-level object")

# Required keys for downstream delta computation. Without these, the
# assembler can't surface a useful previous-verdict section, so we refuse
# rather than write a half-formed file.
required = ("verdict", "confidence", "delta", "reason")
missing = [k for k in required if k not in verdict_data]
if missing:
    refuse(f"verdict JSON missing required keys: {', '.join(missing)}")

# Validate enum values for verdict + delta (mirror the schema enforced by
# the evaluator hook so we refuse bogus data at write time).
valid_verdicts = {"achieved", "not_achieved", "blocked", "needs_human_review"}
valid_deltas = {"made_progress", "unchanged", "regressed"}
if verdict_data["verdict"] not in valid_verdicts:
    refuse(f"verdict must be one of {sorted(valid_verdicts)}, got {shown(repr(verdict_data['verdict']))}")
if verdict_data["delta"] not in valid_deltas:
    refuse(f"delta must be one of {sorted(valid_deltas)}, got {shown(repr(verdict_data['delta']))}")

confidence = verdict_data.get("confidence")
# isinstance(True, int) is True in Python — explicitly reject bools to
# preserve the "must be a number" contract.
if isinstance(confidence, bool) or not isinstance(confidence, (int, float)) or not (0.0 <= float(confidence) <= 1.0):
    refuse(f"confidence must be a number in [0.0, 1.0], got {shown(repr(confidence))}")

# Validate optional fields. Producers writing untrusted content (e.g.,
# judge subprocess output) can ship strings that would survive into the
# next-turn UNTRUSTED_PREVIOUS_VERDICT fence. The fence is the primary
# defense; this is belt-and-suspenders bounding.
_OPTIONAL_STRING_CAPS = {
    "reason": 2048,
    "next_step_hint": 500,
    "source": 64,
}
_VALID_BLOCKER_TYPES = {
    "missing_dep", "missing_approval", "ambiguous_requirement",
    "external_service", "scope_violation", "none",
}
for _key, _cap in _OPTIONAL_STRING_CAPS.items():
    _val = verdict_data.get(_key)
    if _val is None:
        continue
    if not isinstance(_val, str):
        refuse(f"optional field '{_key}' must be a string, got {type(_val).__name__}")
    if len(_val) > _cap:
        # Soft cap — truncate with marker rather than reject, so a slightly
        # over-budget verdict doesn't break the next-turn delta loop.
        verdict_data[_key] = _val[:_cap] + "…"
        say(f"optional field '{_key}' exceeded {_cap}-byte cap; truncated")

_blocker = verdict_data.get("blocker_type")
if _blocker is not None and _blocker not in _VALID_BLOCKER_TYPES:
    refuse(f"blocker_type must be one of {sorted(_VALID_BLOCKER_TYPES)}, got {shown(repr(_blocker))}")

# criterion_results, when present, must be a list of dicts. Don't
# deep-validate (the schema enforces shape upstream); just refuse
# non-list to prevent type confusion downstream.
_crit = verdict_data.get("criterion_results")
if _crit is not None and not isinstance(_crit, list):
    refuse(f"criterion_results must be a list, got {type(_crit).__name__}")

# Auto-add recorded_at if absent. Use UTC ISO-8601 with second resolution
# to match the rest of the flow plugin's timestamp convention. We mutate
# a COPY of verdict_data, not the caller's dict — the helper's contract
# is "validate + write", not "mutate input". Callers (especially the
# shell heredoc subprocess) don't observe the mutation today, but the
# copy semantics keep the contract clean for future Python callers.
to_write = dict(verdict_data)
to_write.setdefault(
    "recorded_at",
    datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
)

target = os.path.join(run_dir, "last-verdict.json")
lockfile = os.path.join(run_dir, ".verdict.lock")

try:
    # Caller usually created the run already; /flow:goal evaluate may run
    # before the first activity record, so a missing directory is created.
    ensure_repo_dir(run_dir, create=True)
    write_json_file(target, lockfile, to_write)
except JournalAtomicError as e:
    say(f"{e}")
    # Surface the `refuse` attribute so a clobber-refusal includes the
    # canonical "fix manually" suffix the journal-record helper uses.
    if getattr(e, "refuse", False):
        say("refusing to overwrite — fix manually")
    sys.exit(e.exit_code)

# Success-path stderr is gated behind FLOW_RECORD_VERDICT_QUIET so callers
# (the evaluator-loop hook in particular) can suppress chatter without
# losing real error visibility. Default unset = chatty (manual `/flow:goal
# evaluate` callers benefit from the confirmation).
if not os.environ.get("FLOW_RECORD_VERDICT_QUIET", ""):
    say(f"recorded verdict for {run_id} -> {target}")
PYTHON
