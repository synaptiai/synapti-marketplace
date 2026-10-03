#!/usr/bin/env bash
# [flow] The review-precision eval's replay of the System One sites
# review.dedup and review.confidence over the findings review runs reported
# (references/review-precision-eval.md, "System One filters").
#
# Every decision is made by the shipped scripts, flow-s1-dedup.sh and
# flow-s1-confidence.sh, run from a copy of this plugin outside the scratch
# trees; the Python half, bin/_flow_eval_s1_replay.py, builds the trees,
# converts the findings, runs the passes, serves the recorded answers back to
# the on passes, and scores.
#
# Usage:
#   flow-eval-s1-replay.sh export-recovered --runs-json <file> --transcripts <dir> --out <findings dir>
#   flow-eval-s1-replay.sh convert --in <file> --out <file>
#   flow-eval-s1-replay.sh score --case <name> --trap <name> --findings <file>
#                                [--any-location] [--exclude-low] [--demoted <file>]
#   flow-eval-s1-replay.sh trees  --findings-dir <dir> --work <dir> --replay <dir>
#   flow-eval-s1-replay.sh shadow --findings-dir <dir> --work <dir> --replay <dir>
#                                 --provider typesafe|custom [--base-url <url>] [--model <id>]
#                                 [--api-key-env <name>] [--timeout-ms <n>] [--set base|reps]
#   flow-eval-s1-replay.sh table  --replay <dir> [--model <id>]
#   flow-eval-s1-replay.sh on     --findings-dir <dir> --work <dir> --replay <dir>
#                                 --filter off|dedup|confidence|dedup-confidence
#                                 [--same-defect <t>] [--claim-supported <t>]
#   flow-eval-s1-replay.sh serve  --table <file> --port-file <file> [--log <file>] [--lifetime <s>]
#   flow-eval-s1-replay.sh inspect   --replay <dir>
#   flow-eval-s1-replay.sh aggregate --replay <dir> --findings-dir <dir>
#                                 [--results <dir> | --runs-json <file>] [--choose 1] [--judge 2,3]
#
# Each prints KEY=value lines and exits 0, or 1 when a pass or a check of its
# own fails (PASS_STATE=failed, TREES_STATE=refused, AGGREGATE_STATE=refused).
# The only provider asked is the one a shadow pass names; the on passes ask a
# server on a port the kernel picks, never 8765. No key is printed.

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
SELF_DIR="$(cd "$(dirname "$_self")" 2>/dev/null && pwd -P)" || { printf 'STATE=failed\nERROR=cannot find the directory of flow-eval-s1-replay.sh\n'; exit 1; }
exec python3 "$SELF_DIR/_flow_eval_s1_replay.py" "$@"
