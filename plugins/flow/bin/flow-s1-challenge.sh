#!/usr/bin/env bash
# [flow] The System One decision point review.challenge: on a Path A run of
# /flow:review, ask, for each finding that went through the challenge round,
# whether the code it cites contradicts it. The answer is a third voice shown
# next to the finding in on mode; it never changes a confidence, a
# disposition, routing or the review decision, and never drops a finding.
#
# Called by REVIEW_CHALLENGE_BLOCK in commands/review.md after the
# same-defect merge, and by any offline replay over recorded findings, so the
# rule exists in one place: bin/_flow_s1_challenge.py, whose header states
# it. The state for each finding is built by bin/flow-finding-state.sh's
# Python half. Each finding is asked through bin/flow-s1.sh, which reads the
# provider settings, applies the threshold in system-one/questions.yaml and
# writes the records. The mode comes from bin/flow-s1-mode.sh --all, the one
# place that decides it; this script never reads systemOne.uses itself. Only
# in on mode is a note printed.
#
# Usage:
#   flow-s1-challenge.sh --findings <file> --tree <dir> --ref-prefix <ref>
#                        [--run-id <id>]
#
#   --findings     a JSON list of findings: id, priority, category, location,
#                  problem, confidence, disposition, reviewers (a non-empty
#                  list), and locations for a merged finding
#   --tree         the tree the cited code is read from, as files
#   --ref-prefix   the start of each record's ref, e.g. pr:275/review-cycle:2;
#                  each finding adds /<id>. At most 150 characters
#   --run-id       records, and the state sent for each finding, go beside
#                  .flow/runs/<id> when that run exists
#
# Exit 0 with KEY=value lines whatever the answers (references/system-one.md
# lists them); exit 2 with STATE=blocked and ERROR=<text> on a usage error or
# a findings file that is not a JSON list. Never 3: no answer is a state, not
# a failure.

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

_blocked() {
  # A value is shown with every byte that is not printable ASCII as ?, so it
  # cannot start another line.
  local LC_ALL=C
  printf 'STATE=blocked\nERROR=%s\n' "${1//[^[:print:]]/?}"
  exit 2
}

# This script's own directory, through symlinks: flow-s1.sh, flow-s1-mode.sh
# and the Python half are its siblings, never found through the working
# directory, which during a review may be the pull request. The same lookup
# as in bin/flow-s1.sh.
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
SELF_DIR="$(cd "$(dirname "$_self")" 2>/dev/null && pwd -P)" || _blocked "cannot find the directory of flow-s1-challenge.sh"

FINDINGS=""; TREE=""; REF_PREFIX=""; RUN_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --findings|--tree|--ref-prefix|--run-id)
      [ $# -ge 2 ] || _blocked "$1 needs a value"
      case "$1" in
        --findings) FINDINGS="$2" ;;
        --tree) TREE="$2" ;;
        --ref-prefix) REF_PREFIX="$2" ;;
        --run-id) RUN_ID="$2" ;;
      esac
      shift 2 ;;
    *) _blocked "unknown argument: $1" ;;
  esac
done
[ -n "$FINDINGS" ] && [ -f "$FINDINGS" ] && [ -r "$FINDINGS" ] || _blocked "--findings is not a readable file"
[ -n "$TREE" ] && [ -d "$TREE" ] || _blocked "--tree is not a directory"
[ -n "$REF_PREFIX" ] || _blocked "--ref-prefix is required"

# Without python3 nothing can be read or asked: the review is as it was.
if ! command -v python3 >/dev/null 2>&1 \
   || ! python3 -c 'import os, sys; sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and not (os.path.isdir(p) and os.access(os.curdir, os.X_OK) and os.path.samefile(p, os.curdir))]; import json' >/dev/null 2>&1; then
  printf 'S1_CHALLENGE_STATE=no-answer\nREASON=python-missing\nS1_ASKED=0\n'
  exit 0
fi

MODE=$("$SELF_DIR/flow-s1-mode.sh" --all review.challenge 2>/dev/null) || MODE=off
# Every value is passed as --name=value: one that starts with a dash would be
# read as an option.
exec python3 "$SELF_DIR/_flow_s1_challenge.py" \
  --findings="$FINDINGS" --tree="$TREE" --ref-prefix="$REF_PREFIX" \
  --run-id="$RUN_ID" --mode="$MODE"
