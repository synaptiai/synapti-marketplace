#!/usr/bin/env bash
# [flow] Run the goal judge for one FlowGoal, as /flow:goal evaluate does.
#
# Usage:
#   flow-goal-judge-run.sh <goal-id> [<run-id>]
#
# Called by skills/goal-evaluator/SKILL.md Step 5 from the repository root. It
# gives the judge what the Stop hook gives it in evaluator-loop mode
# (hooks/scripts/flow-goal-evaluator.sh): the deterministic-check report from
# hooks/scripts/flow-run-deterministic-checks.sh, the input assembled by
# bin/_flow_evidence_bundle.py from the goal, that report and the run's
# evidence sidecars, and the judge run by bin/flow-judge.sh --judge goal. So
# for a trusted goal the verification commands run again here, and the report
# the judge reads is the one the hook would produce for the same tree.
#
# Stdout, one KEY=value per line:
#   JUDGE_STATE=done        then JUDGE_VERDICT=<the judge's reply, one line of JSON>
#   JUDGE_STATE=blocked     then JUDGE_ERROR=<why>: a bad id, no goal file, a
#                           symlink on the way, checks or bundle that did not run
#   JUDGE_STATE=unavailable then JUDGE_ERROR=<why>: the judge gave no verdict
#                           (time limit, CLI failure, reply outside the schema)
#
# Never reads through a symlink: a goal or run reached through a link belongs
# to its target, not to this repository.
#
# Exits: 0 with JUDGE_STATE=done; 1 otherwise.

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

GOAL_ID="${1-}"
RUN_ID="${2-}"

_blocked() { printf '%s\n' "JUDGE_STATE=blocked" "JUDGE_ERROR=$1"; exit 1; }

case "$GOAL_ID" in
  ''|.|..|*/*|*..*) _blocked "GOAL_ID must be a goal id without '/' or '..'" ;;
esac
case "$RUN_ID" in
  .|..|*/*|*..*) _blocked "RUN_ID must be a run id without '/' or '..'" ;;
esac

# The plugin this script ships in; the skill's block found it before calling.
FLOW_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

GOAL_FILE=".flow/goals/$GOAL_ID.goal.yaml"
if ! "$FLOW_ROOT/bin/flow-mkdir.sh" --check -- .flow/goals >/dev/null 2>&1 || [ -L "$GOAL_FILE" ] || [ ! -f "$GOAL_FILE" ]; then
  _blocked "no goal file to read at .flow/goals/<GOAL_ID>.goal.yaml (missing, or reached through a symlink)"
fi
RUN_DIR=""
if [ -n "$RUN_ID" ]; then
  if ! "$FLOW_ROOT/bin/flow-mkdir.sh" --check -- ".flow/runs/$RUN_ID" >/dev/null 2>&1; then
    _blocked "the run directory is reached through a symlink or cannot be checked"
  fi
  RUN_DIR=".flow/runs/$RUN_ID"
fi

# The report, from the producer the Stop hook runs. No "checked" key, or a
# non-zero exit, means the checks did not run.
REPORT=$(CLAUDE_PLUGIN_ROOT="$FLOW_ROOT" "$FLOW_ROOT/hooks/scripts/flow-run-deterministic-checks.sh" "$GOAL_FILE" 2>/dev/null)
CHECKS_RC=$?
if [ "$CHECKS_RC" -ne 0 ] || ! printf '%s' "$REPORT" | jq -e 'has("checked")' >/dev/null 2>&1; then
  _blocked "the deterministic checks did not run (exit $CHECKS_RC)"
fi
BUNDLE_FILE=$(mktemp -t flow-judge-input.XXXXXX) || _blocked "mktemp failed"
if ! PYTHONSAFEPATH=1 python3 "$FLOW_ROOT/bin/_flow_evidence_bundle.py" "$GOAL_FILE" "$REPORT" "$RUN_DIR" > "$BUNDLE_FILE" 2>/dev/null; then
  rm -f "$BUNDLE_FILE"
  _blocked "the evidence bundle could not be assembled (python3 or PyYAML missing, or a goal or sidecar the assembler refused)"
fi
# The judge: claude --print with every tool disallowed, through the helper the
# Stop hook uses. A timeout, a CLI failure or a reply without a verdict is
# "unavailable", never a verdict.
REPLY=$("$FLOW_ROOT/bin/flow-judge.sh" --judge goal < "$BUNDLE_FILE")
JUDGE_RC=$?
rm -f "$BUNDLE_FILE"
VERDICT_JSON=""
[ "$JUDGE_RC" -ne 0 ] || VERDICT_JSON=$(printf '%s' "$REPLY" | jq -c '.structured_output | select(type == "object" and (.verdict | IN("achieved", "not_achieved", "blocked", "needs_human_review")))' 2>/dev/null)
if [ -z "$VERDICT_JSON" ]; then
  printf '%s\n' "JUDGE_STATE=unavailable" "JUDGE_ERROR=the judge gave no verdict (exit $JUDGE_RC; 124 is its time limit)"
  exit 1
fi
printf '%s\n' "JUDGE_STATE=done" "JUDGE_VERDICT=$VERDICT_JSON"
