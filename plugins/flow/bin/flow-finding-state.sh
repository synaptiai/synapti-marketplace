#!/usr/bin/env bash
# [flow] Print the state a System One question about one review finding is
# asked with: the finding's priority, category and problem, and the code each
# of its locations cites, read as files under the tree. Called by
# bin/flow-s1-confidence.sh for each finding it asks about, and by any replay
# over recorded findings, so a replayed state is byte for byte the state sent
# live. bin/_flow_finding_state.py holds the rule and states it.
#
# Usage:
#   flow-finding-state.sh --tree <dir> --finding <json file> [--head <sha>]
#
#   --tree      the tree the cited files are read from; nothing in it is run
#   --finding   one finding as a JSON object: priority, category, problem,
#               location, and optionally locations (a merged finding)
#   --head      the commit the tree is at, written into the state; without
#               it the state says worktree
#
# Exit 0 with the state JSON on stdout (no trailing newline: its sha256 is
# the one the System One records name); 4 with SKIP=<reason> when the finding
# cannot be asked about (invalid-finding, no-line, path-refused,
# file-missing, line-out-of-range, not-text); 2 on a usage error.

set -uo pipefail
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
# The client runs with the repository as its working directory, and a
# planted ./yaml.py or ./json.py there must never run in place of the real
# module. PYTHONSAFEPATH keeps the directory off sys.path on Python 3.11 and
# later; older Pythons ignore it (macOS /usr/bin/python3 is 3.9), and an
# empty element in PYTHONPATH adds it on every version, as an absolute path.
# So every python3 call below also removes, before any other import, each
# sys.path entry that is relative or that resolves to the working directory.
export PYTHONSAFEPATH=1

_usage() {
  printf 'usage: flow-finding-state.sh --tree <dir> --finding <json file> [--head <sha>]\n' >&2
  exit 2
}

# This script's own directory, through symlinks: the Python half is its
# sibling, never found through the working directory. The same lookup as in
# bin/flow-s1.sh.
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
SELF_DIR="$(cd "$(dirname "$_self")" 2>/dev/null && pwd -P)" || _usage

TREE=""; FINDING=""; HEAD_SHA=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tree|--finding|--head)
      [ $# -ge 2 ] || _usage
      case "$1" in
        --tree) TREE="$2" ;;
        --finding) FINDING="$2" ;;
        --head) HEAD_SHA="$2" ;;
      esac
      shift 2 ;;
    *) _usage ;;
  esac
done
[ -n "$TREE" ] && [ -d "$TREE" ] || _usage
[ -n "$FINDING" ] && [ -f "$FINDING" ] && [ -r "$FINDING" ] || _usage
command -v python3 >/dev/null 2>&1 || { printf 'flow-finding-state: python3 is required\n' >&2; exit 2; }

# Every value is passed as --name=value: one that starts with a dash would be
# read as an option.
exec python3 "$SELF_DIR/_flow_finding_state.py" --tree="$TREE" --finding="$FINDING" --head="$HEAD_SHA"
