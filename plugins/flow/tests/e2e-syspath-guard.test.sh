# shellcheck shell=bash
# End-to-end: a module planted in the repository never runs through Flow's
# hooks and scripts, on either way the working directory reaches sys.path.
#
# Each scenario plants yaml.py, glob.py and json.py in the scratch repository;
# each writes a marker file when imported. The Stop hook
# (hooks/scripts/flow-goal-stop.sh) imports all three on every turn, and
# bin/flow-active-goal.sh probes PyYAML and then reads goals.
#
# Ways it can be wrong, written down before the scenarios:
#   G1 an empty PYTHONPATH element puts the repository on sys.path as an
#      absolute path, and a filter of "" and "." keeps it
#   G2 on a Python that ignores PYTHONSAFEPATH (before 3.11), "" is first on
#      sys.path for `python3 -c` and `python3 -`, and the PyYAML probe imports
#      the planted yaml.py before any filter
#   G3 the guard runs after an import on the same line (import os, glob, sys,
#      yaml), so the planted modules run before it
#   G4 the scenario passes because the hook never reached Python: each one
#      also asserts the hook's normal output

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

_plant() {
  local m
  for m in yaml glob json; do
    printf 'open(%s, "w").write("%s")\n' "'$E2E_DIR/ran-$m'" "$m" > "$E2E_REPO/$m.py"
  done
}
_expect_none_ran() {
  local m
  for m in yaml glob json; do
    if [ -e "$E2E_DIR/ran-$m" ]; then _e2e_result fail "the planted $m.py did not run"
    else _e2e_result pass "the planted $m.py did not run"; fi
  done
}
# Keep what run.sh put on PYTHONPATH (it may carry a user-site PyYAML); the
# empty first element is the point.
PP_EMPTY="PYTHONPATH=:/nonexistent${PYTHONPATH:+:$PYTHONPATH}"
STOP='{"session_id":"e2e-session","stop_hook_active":false}'

_flow_test_begin "stop-hook-pythonpath-empty-element"
e2e_new stop-hook-pythonpath-empty-element
e2e_describe "the Stop hook with PYTHONPATH=:/nonexistent (G1) and an active goal, so it reads goals with Python"
e2e_repo feature/g1
_plant
e2e_goal g1 feature/g1 active true
e2e_run_hook "$PP_EMPTY" hooks/scripts/flow-goal-stop.sh "$STOP"
_expect_none_ran
e2e_expect_out '"decision"'

_flow_test_begin "stop-hook-old-python"
e2e_new stop-hook-old-python
e2e_describe "the Stop hook under a python3 that ignores PYTHONSAFEPATH, as Python before 3.11 does (G2, G3)"
e2e_repo feature/g2
_plant
e2e_goal g2 feature/g2 active true
real=$(command -v python3)
printf '#!/bin/sh\nunset PYTHONSAFEPATH\nexec %s "$@"\n' "$real" > "$E2E_BIN/python3"; chmod +x "$E2E_BIN/python3"
e2e_run_hook hooks/scripts/flow-goal-stop.sh "$STOP"
_expect_none_ran
e2e_expect_out '"decision"'

_flow_test_begin "active-goal-script"
e2e_new active-goal-script
e2e_describe "bin/flow-active-goal.sh (PyYAML probe, then a goal scan) with both ways at once"
e2e_repo feature/g3
_plant
e2e_goal g3 feature/g3 active true
printf '#!/bin/sh\nunset PYTHONSAFEPATH\nexec %s "$@"\n' "$real" > "$E2E_BIN/python3"; chmod +x "$E2E_BIN/python3"
e2e_run_bin "$PP_EMPTY" bin/flow-active-goal.sh --id
_expect_none_ran
e2e_expect_line "g3"
