#!/usr/bin/env bash
# [flow] Record the decision /flow:learn Phase 2 took on one screened
# correction candidate: kept (the user was correcting the assistant) or
# dropped. The record is what System One answers for the site
# learn.correction are compared against before the site is switched on by
# default (references/system-one.md).
#
# Usage:
#   flow-learn-verdict.sh --line <transcript_path>:<line_no> --verdict kept|dropped
#
# <transcript_path> is the full path. The /flow:learn Line cell cuts a path
# longer than 200 characters and ends it with an ellipsis; that cut form is
# refused with exit 2.
#
# Writes one JSON line {ts, site, ref, state_sha256, verdict} to
# learn-correction-verdicts.jsonl in the per-user state directory
# (cascade-resolve.sh --state-dir), and only when system-one.jsonl there holds
# a learn.correction record for that transcript line from the last 24 hours:
# a line /flow:learn did not screen gets nothing, so with the site off this
# writes nothing. It never prints transcript text.
#
# Exit: 0 (written, or nothing to write); 2 for a usage error.

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

usage() {
  printf 'usage: flow-learn-verdict.sh --line <transcript_path>:<line_no> --verdict kept|dropped\n' >&2
  exit 2
}

LINE=""; VERDICT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --line|--verdict)
      [ $# -ge 2 ] || usage
      case "$1" in --line) LINE="$2" ;; --verdict) VERDICT="$2" ;; esac
      shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$LINE" ] || usage
case "$VERDICT" in kept|dropped) ;; *) usage ;; esac

# This script's own directory, through symlinks: the state directory and the
# Python half are found next to it, never through the working directory.
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
SELF_DIR="$(cd "$(dirname "$_self")" 2>/dev/null && pwd -P)" || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
STATE_DIR=$("${BASH:-bash}" "$SELF_DIR/cascade-resolve.sh" --state-dir 2>/dev/null) || exit 0
[ -n "$STATE_DIR" ] || exit 0
exec python3 "$SELF_DIR/_flow_learn_s1.py" verdict --line="$LINE" --verdict="$VERDICT" --state-dir="$STATE_DIR"
