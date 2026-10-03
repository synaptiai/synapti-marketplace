#!/usr/bin/env bash
# [flow] The measurement of the System One question "would this test fail if
# the module were the risk row's plausible wrong version?" against what the
# correctness eval observed (references/correctness-eval.md, section "System
# One: does a test catch the wrong version").
#
#   flow-s1-eval.sh pairs   export (test, wrong version) pairs and their states
#   flow-s1-eval.sh replay  send each pair through flow-s1.sh in shadow mode
#                           from a scratch copy of the plugin
#   flow-s1-eval.sh score   join the records to the pairs and write the summary
#   flow-s1-eval.sh smoke   before the dev replay: obvious catches and
#                           non-catches answered on the right side of 0.5
#
# bin/_flow_s1_eval.py has the options of each.
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
SELF_DIR="$(cd "$(dirname "$_self")" 2>/dev/null && pwd -P)" || { printf 'flow-s1-eval: cannot find its own directory\n' >&2; exit 2; }
case "${1:-}" in
  pairs|replay|score|smoke) _sub="s1-$1"; shift ;;
  *) printf 'usage: flow-s1-eval.sh pairs|replay|score|smoke [options]; see bin/_flow_s1_eval.py\n' >&2; exit 2 ;;
esac
exec python3 "$SELF_DIR/_flow_eval.py" "$_sub" "$@"
