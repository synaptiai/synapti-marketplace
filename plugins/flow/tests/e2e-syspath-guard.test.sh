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
#   G5 the interpreter imports sitecustomize from an empty PYTHONPATH element
#      at startup, before any line of Flow's code runs, so only cleaning
#      PYTHONPATH before python3 starts can stop it
#   G6 PYTHONPATH names a directory inside the repository other than the
#      working directory (a src/ layout, set by direnv), and the sanitizer
#      keeps it because it only compares each element with the working
#      directory
#   G7 the hook runs in a subdirectory and PYTHONPATH names another
#      directory of the same repository, neither the working directory nor
#      above or below it, which only finding the repository's top catches
#   G8 the sanitizer passes G6 and G7 by dropping every element, so a PyYAML
#      that the user reaches only through PYTHONPATH is lost: an element
#      outside the repository must reach Python, also when a directory above
#      the repository is itself kept in git (a home directory under git), so
#      the repository is the nearest .git, not the outermost
#   G9 the working directory is in no git repository (an unpacked archive), and
#      PYTHONPATH names a directory above it, where the modules are planted

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

# _plant [dir] — the four modules, in the repository or in <dir>.
_plant() {
  local m d="${1:-$E2E_REPO}"
  mkdir -p "$d"
  for m in yaml glob json sitecustomize; do
    printf 'open(%s, "w").write("%s")\n' "'$E2E_DIR/ran-$m'" "$m" > "$d/$m.py"
  done
}
_expect_none_ran() {
  local m
  for m in yaml glob json sitecustomize; do
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

_flow_test_begin "verification-command-keeps-user-pythonpath"
e2e_new verification-command-keeps-user-pythonpath
e2e_describe "Flow's own Python gets a cleaned PYTHONPATH, but a goal's verification command is the user's own and must see the PYTHONPATH the user set, empty element included"
e2e_repo feature/g4
e2e_user_settings '{"flow":{"goals":{"executeVerificationCommands":true}}}'
e2e_goal g4 feature/g4 active "printf '%s' \"\$PYTHONPATH\" > \"$E2E_DIR/seen-pythonpath\""
e2e_run_bin "$PP_EMPTY" hooks/scripts/flow-run-deterministic-checks.sh .flow/goals/g4.goal.yaml
e2e_expect_equal "${PP_EMPTY#PYTHONPATH=}" "$(cat "$E2E_DIR/seen-pythonpath" 2>/dev/null)" "PYTHONPATH seen by the verification command"

_flow_test_begin "stop-hook-pythonpath-inside-repository"
e2e_new stop-hook-pythonpath-inside-repository
e2e_describe "the Stop hook with PYTHONPATH naming the repository's src/ directory, where the modules are planted (G6)"
e2e_repo feature/g6
_plant "$E2E_REPO/src"
e2e_goal g6 feature/g6 active true
e2e_run_hook "PYTHONPATH=$E2E_REPO/src${PYTHONPATH:+:$PYTHONPATH}" hooks/scripts/flow-goal-stop.sh "$STOP"
_expect_none_ran
e2e_expect_out '"decision"'

_flow_test_begin "system-one-client-from-subdirectory"
e2e_new system-one-client-from-subdirectory
e2e_describe "bin/flow-s1.sh run in the repository's sub/ directory with PYTHONPATH naming the repository's src/ directory, where the modules are planted (G7). With no provider it imports yaml in python3 before it reports provider-none; without Python it would report python-missing"
e2e_repo feature/g7
_plant "$E2E_REPO/src"
mkdir -p "$E2E_REPO/sub"
printf 'state\n' > "$E2E_REPO/sub/state.txt"
E2E_TOP="$E2E_REPO"; E2E_REPO="$E2E_REPO/sub"
e2e_run_bin "PYTHONPATH=$E2E_TOP/src${PYTHONPATH:+:$PYTHONPATH}" bin/flow-s1.sh ask --site e2e.one --state-file state.txt
E2E_REPO="$E2E_TOP"
_expect_none_ran
e2e_expect_equal 3 "$E2E_RC" "exit status"
e2e_expect_err "flow-s1: no answer: provider-none"

_flow_test_begin "stop-hook-pythonpath-outside-repository"
e2e_new stop-hook-pythonpath-outside-repository
e2e_describe "the Stop hook with PYTHONPATH naming a directory outside the repository that holds a sitecustomize.py, while the directory holding the repository is itself marked as a git repository: the element reaches Python, so the module runs (G8)"
e2e_repo feature/g8
mkdir -p "$E2E_DIR/site-outside" "$E2E_DIR/.git"
printf 'open(%s, "w").write("sitecustomize")\n' "'$E2E_DIR/ran-outside-sitecustomize'" > "$E2E_DIR/site-outside/sitecustomize.py"
e2e_goal g8 feature/g8 active true
e2e_run_hook "PYTHONPATH=$E2E_DIR/site-outside${PYTHONPATH:+:$PYTHONPATH}" hooks/scripts/flow-goal-stop.sh "$STOP"
e2e_expect_equal yes "$([ -e "$E2E_DIR/ran-outside-sitecustomize" ] && echo yes || echo no)" "the sitecustomize.py outside the repository ran"
e2e_expect_out '"decision"'

_flow_test_begin "system-one-client-outside-git"
e2e_new system-one-client-outside-git
e2e_describe "bin/flow-s1.sh run in proj/sub, a directory in no git repository, with PYTHONPATH naming proj, where the modules are planted (G9)"
e2e_repo feature/g9
_plant "$E2E_DIR/proj"
mkdir -p "$E2E_DIR/proj/sub"
printf 'state\n' > "$E2E_DIR/proj/sub/state.txt"
E2E_TOP="$E2E_REPO"; E2E_REPO="$E2E_DIR/proj/sub"
e2e_run_bin "PYTHONPATH=$E2E_DIR/proj${PYTHONPATH:+:$PYTHONPATH}" bin/flow-s1.sh ask --site e2e.one --state-file state.txt
E2E_REPO="$E2E_TOP"
_expect_none_ran
e2e_expect_equal 3 "$E2E_RC" "exit status"
e2e_expect_err "flow-s1: no answer: provider-none"
