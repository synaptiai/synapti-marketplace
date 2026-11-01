#!/usr/bin/env bash
# [flow] Print the runtime directory: where flow keeps its goals, runs,
# triggers, watch state, workflow overrides and review exceptions. Every flow
# reader and writer of that state takes the directory from here (shell) or
# from runtime_dir() in bin/_repo_dir.py (Python), which give the same answer.
#
# The directory is flow.runtime.stateDir from the settings cascade
# (bin/cascade-resolve.sh), default .flow. Any settings file may set it. It is
# not the per-user state directory (FLOW_STATE_DIR, cascade-resolve.sh
# --state-dir), which is a different place.
#
# The value is a path relative to the repository top (the nearest directory
# at or above the working directory with a .git entry). It is refused when it
# starts with /, \, ~ or a drive, has a `..` component, names the top itself,
# or does not end below the top with no symlink and nothing but directories
# on the way: ensure_inside_repo() in bin/_repo_dir.py, the rule journal.dir
# is held to (bin/journal-dir.sh). A refused value, or one that cannot be
# checked, prints one warning line on stderr naming the setting and the
# reason, and .flow is used. The check is check_runtime_dir() in
# bin/_repo_dir.py; .flow itself needs none, since a refused value gives
# .flow too.
#
# Usage: flow-runtime-dir.sh
#
# Output: the directory, one line, relative to the repository top,
# normalized (no `.` component, no doubled or trailing /); a name starting
# with `-` is printed as ./<name>. Warnings on stderr.
#
# Exits:
#   0 — printed the directory
#   1 — usage error; nothing printed

set -uo pipefail
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

DEFAULT=".flow"

case "${1:-}" in
  "") ;;
  -h|--help)
    awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
    exit 0 ;;
  *)
    echo "flow-runtime-dir.sh: usage: flow-runtime-dir.sh" >&2
    exit 1 ;;
esac

_self="$0"
_hops=0
while [ -L "$_self" ] && [ "$_hops" -lt 40 ]; do
  _link=$(readlink "$_self") || break
  case "$_link" in
    /*) _self="$_link" ;;
    *)  _self="$(dirname "$_self")/$_link" ;;
  esac
  _hops=$((_hops + 1))
done
SCRIPT_DIR="$(cd "$(dirname "$_self")" 2>/dev/null && pwd -P)" || {
  printf 'flow-runtime-dir: WARN: cannot find its own directory; using %s\n' "$DEFAULT" >&2
  printf '%s\n' "$DEFAULT"
  exit 0
}

DIR=$("${BASH:-bash}" "$SCRIPT_DIR/cascade-resolve.sh" --default "$DEFAULT" '.flow.runtime.stateDir // empty') || DIR=""
# A Windows jq ends the line in \r\n, which $(...) keeps the \r of.
DIR=${DIR%$'\r'}
if [ -z "$DIR" ] || [ "$DIR" = "$DEFAULT" ]; then
  printf '%s\n' "$DEFAULT"
  exit 0
fi

# check_runtime_dir() gives the directory, or .flow and the reason it refused
# the value; the warning goes to stderr. The module needs no PyYAML.
OUT=$(python3 - "$SCRIPT_DIR" "$DIR" <<'PYTHON'
# Keep the working directory (the repository) off sys.path before any other
# import; tests/syspath-guard.test.sh has the reasons.
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]

sys.path.insert(0, sys.argv[1])

from _repo_dir import check_runtime_dir, runtime_dir_warning  # noqa: E402

answer, reason = check_runtime_dir(sys.argv[2])
if reason is not None:
    sys.stderr.write(runtime_dir_warning(reason) + "\n")
sys.stdout.write(answer + "\n")
PYTHON
) || OUT=""
OUT=${OUT%$'\r'}
if [ -z "$OUT" ]; then
  # The check did not run (python3 missing or failing): a value that cannot
  # be checked is not used.
  printf 'flow-runtime-dir: WARN: refusing flow.runtime.stateDir: it could not be checked (python3 did not run); using %s\n' "$DEFAULT" >&2
  OUT="$DEFAULT"
fi
printf '%s\n' "$OUT"
