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
#   G10 an element that is not a directory (a zip, which Python imports
#      sitecustomize from) cannot be resolved with cd, and is compared as
#      written: named through a symlink or a `..`, a zip inside the repository
#      does not look like it is, so it is kept; and a zip outside the
#      repository is kept although only directories should be
#   G11 zsh's `pwd -P` prints "." and succeeds in a deleted directory (bash
#      fails), so a sanitizer that expects an absolute path loops forever
#      looking for .git above ".", or keeps elements it cannot compare with
#      anything
#   G12 bash keeps exactly two leading slashes (`cd //x; pwd -P` prints
#      //x), so a path inside the repository spelled //<repo>/b, a working
#      directory inherited as //<repo>, or the element // does not compare
#      equal, as text, with the repository or with /
#   G13 a kept path that contains a colon is split again by Python, so a
#      symlink to .../a:b outside the repository puts a relative b (the
#      repository's b/) on sys.path
#   G14 on a case-insensitive disk (macOS by default) the repository's path in
#      another case is the same directory but not the same text
#   G15 when the sanitizer removed the element PyYAML was reached through,
#      the "PyYAML unavailable" note names the wrong reason, or none, so the
#      user cannot tell why an install they can see is not used; or the note
#      appears when nothing was removed, because a kept element is renamed to
#      its resolved path and the text of PYTHONPATH changes
#   G16 an element outside the repository that is a symlink to a directory
#      inside it is judged by where it is written, not where it leads
#   G17 in a git worktree .git is a file, so a repository test that looks
#      for a .git directory finds none and treats only the working
#      directory as the repository
#   G18 in a locale whose stdout Python writes strictly, a kept directory
#      whose name that locale cannot encode (a non-Latin name under an ISO
#      8859-1 locale on macOS, a byte that is not UTF-8 under a UTF-8 locale
#      such as en_US.UTF-8 on Linux)
#      cannot be printed as text, so the sanitizer's python3 fails and every
#      element is dropped. C.UTF-8 is no test of it: Python writes stdout
#      there with surrogateescape
#   G19 in a UTF-8 locale, macOS tr stops at the first byte that is not
#      UTF-8, so the hooks count too few PYTHONPATH elements and leave the
#      note out although an element was dropped
#   G20 the one-line guard in front of a PyYAML probe reads the working
#      directory with os.getcwd(), which fails in a deleted directory, so the
#      probe fails and the hook reports "PyYAML unavailable" where a plain
#      `python3 -c "import yaml"` (main's probe) imports PyYAML and goes on
#   G21 os.getcwd() also fails in a working directory that cannot be
#      searched (mode 000), and so does comparing directories by identity,
#      which stats ".", so a guard that avoids getcwd but stats "." without
#      checking it can be searched fails there the same way
#   G22 bin/flow-s1-dedup.sh runs its own python3 before it calls the System
#      One client, so its wrapper must clean PYTHONPATH and its Python half
#      must run the guard, or a module planted in the repository runs first
#   G23 bin/flow-s1-confidence.sh and bin/flow-finding-state.sh run their own
#      python3 the same way, so the same holds for both
#   G24 bin/flow-s1-challenge.sh runs its own python3 the same way, and its
#      Python half imports the confidence and state modules

# Only tests/run.sh runs this file: it sets REPO_ROOT and loads assert.sh. Run
# any other way, the file stops here with a non-zero exit, because `return`
# alone does not stop a script that is executed rather than sourced, and the
# scenarios below would then run git in the current directory.
{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

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

_flow_test_begin "system-one-client-zip-through-symlink"
e2e_new system-one-client-zip-through-symlink
e2e_describe "bin/flow-s1.sh with PYTHONPATH naming vendor.zip in the repository, which holds a sitecustomize.py, through a symlink to the repository and through sub/.. (G10)"
e2e_repo feature/g10
mkdir -p "$E2E_REPO/sub"
printf 'state\n' > "$E2E_REPO/state.txt"
python3 - "$E2E_REPO/vendor.zip" "$E2E_DIR/ran-zip-sitecustomize" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("sitecustomize.py", "open(%r, 'w').write('zip')\n" % sys.argv[2])
PY
ln -s "$E2E_REPO" "$E2E_DIR/link-to-repo"
for el in "$E2E_DIR/link-to-repo/vendor.zip" "$E2E_REPO/sub/../vendor.zip"; do
  rm -f "$E2E_DIR/ran-zip-sitecustomize"
  e2e_run_bin "PYTHONPATH=$el${PYTHONPATH:+:$PYTHONPATH}" bin/flow-s1.sh ask --site e2e.one --state-file state.txt
  e2e_expect_equal 3 "$E2E_RC" "exit status"
  e2e_expect_err "flow-s1: no answer: provider-none"
  e2e_expect_equal no "$([ -e "$E2E_DIR/ran-zip-sitecustomize" ] && echo yes || echo no)" "the zip's sitecustomize.py ran"
done
# A zip outside the repository is dropped too: only directories are kept. The
# shipped sanitizer lines, run under each shell, show what they leave.
cp "$E2E_REPO/vendor.zip" "$E2E_DIR/outside.zip"
mkdir -p "$E2E_DIR/site-outside"
flow_block "$E2E_ACTIVE_PLUGIN/commands/address.md" DISPUTED_ARRAY_BLOCK 2>/dev/null \
  | sed -n '/FLOW_USER_PYTHONPATH+x/,/unset PYTHONPATH; fi/p' > "$E2E_DIR/sanitizer.sh"
printf '%s\n' 'printf "PYTHONPATH=%s\n" "${PYTHONPATH-unset}"' >> "$E2E_DIR/sanitizer.sh"
e2e_plugin_copy bin/run-shell.sh "$(printf '%s\n' '#!/bin/sh' 'exec "$1" "$2"')"
for sh in $E2E_FENCE_SHELLS; do
  e2e_run_bin "PYTHONPATH=$E2E_DIR/outside.zip:$E2E_DIR/site-outside" bin/run-shell.sh "$sh" "$E2E_DIR/sanitizer.sh"
  e2e_expect_line "PYTHONPATH=$(cd -P "$E2E_DIR/site-outside" && pwd -P)"
done

_flow_test_begin "sanitizer-from-deleted-directory"
e2e_new sanitizer-from-deleted-directory
e2e_describe "the PYTHONPATH sanitizer as shipped at the top of address.md's DISPUTED_ARRAY_BLOCK, then python3, run under each shell from a working directory that has been deleted, with PYTHONPATH naming a directory outside the repository that holds a sitecustomize.py: it finishes, and drops every element, since nothing can be compared with a directory it cannot read (G11)"
e2e_repo feature/g11
mkdir -p "$E2E_DIR/site-outside"
printf 'open(%s, "w").write("sitecustomize")\n' "'$E2E_DIR/ran-outside-sitecustomize'" > "$E2E_DIR/site-outside/sitecustomize.py"
# The sanitizer's lines, taken from the plugin under test.
flow_block "$E2E_ACTIVE_PLUGIN/commands/address.md" DISPUTED_ARRAY_BLOCK 2>/dev/null \
  | sed -n '/FLOW_USER_PYTHONPATH+x/,/unset PYTHONPATH; fi/p' > "$E2E_DIR/sanitizer.sh"
e2e_expect_equal 3 "$(grep -c . "$E2E_DIR/sanitizer.sh")" "sanitizer lines taken from the block"
printf '%s\n' 'printf "PYTHONPATH=%s\n" "${PYTHONPATH-unset}"' 'python3 -c "print(\"python ran\")"' >> "$E2E_DIR/sanitizer.sh"
# Start the shell from a directory removed first; a watchdog ends a shell
# that has not finished within 10 s. The helper goes into a copy of the plugin.
e2e_plugin_copy bin/from-deleted-dir-shell.sh "$(printf '%s\n' '#!/bin/sh' \
  'mkdir gone && cd gone && rmdir ../gone || exit 97' \
  '"$1" "$2" & p=$!' \
  '( sleep 10; kill -9 "$p" 2>/dev/null ) & w=$!' \
  'wait "$p"; rc=$?' \
  'kill "$w" 2>/dev/null' \
  'exit "$rc"')"
for sh in $E2E_FENCE_SHELLS; do
  e2e_run_bin "PYTHONPATH=$E2E_DIR/site-outside${PYTHONPATH:+:$PYTHONPATH}" bin/from-deleted-dir-shell.sh "$sh" "$E2E_DIR/sanitizer.sh"
  e2e_expect_equal 0 "$E2E_RC" "exit status under $sh"
  e2e_expect_line "PYTHONPATH=unset"
  e2e_expect_line "python ran"
  e2e_expect_equal no "$([ -e "$E2E_DIR/ran-outside-sitecustomize" ] && echo yes || echo no)" "the sitecustomize.py outside the repository ran under $sh"
done

# _plant_site <dir> <marker> — a sitecustomize.py in <dir> that writes <marker>.
_plant_site() {
  mkdir -p "$1"
  printf 'open(%s, "w").write("sitecustomize")\n' "'$2'" > "$1/sitecustomize.py"
}
# _s1_none <label> [NAME=value ...] — run bin/flow-s1.sh with no provider (its
# PyYAML probe runs python3, then it reports provider-none) and check the
# planted sitecustomize.py did not run.
_s1_none() {
  local label=$1; shift
  rm -f "$E2E_DIR/ran-planted"
  e2e_run_bin "$@" bin/flow-s1.sh ask --site e2e.one --state-file state.txt
  e2e_expect_equal 3 "$E2E_RC" "exit status ($label)"
  e2e_expect_err "flow-s1: no answer: provider-none"
  e2e_expect_equal no "$([ -e "$E2E_DIR/ran-planted" ] && echo yes || echo no)" "the planted sitecustomize.py ran ($label)"
}

_flow_test_begin "system-one-client-double-slash"
e2e_new system-one-client-double-slash
e2e_describe "bin/flow-s1.sh (bash) with the repository's b/ directory, which holds a sitecustomize.py, named with two leading slashes, which bash keeps; with the working directory inherited as //<repo>; and with PYTHONPATH=// (G12)"
e2e_repo feature/g12
printf 'state\n' > "$E2E_REPO/state.txt"
_plant_site "$E2E_REPO/b" "$E2E_DIR/ran-planted"
_s1_none "element //<repo>/b" "PYTHONPATH=/$E2E_REPO/b${PYTHONPATH:+:$PYTHONPATH}"
_s1_none "working directory //<repo>" "PWD=/$E2E_REPO" "PYTHONPATH=$E2E_REPO/b${PYTHONPATH:+:$PYTHONPATH}"
# Nothing can be planted at /, so the element // is checked by what the
# sanitizer leaves: the shipped lines, run under each shell, keep only the
# directory outside the repository.
flow_block "$E2E_ACTIVE_PLUGIN/commands/address.md" DISPUTED_ARRAY_BLOCK 2>/dev/null \
  | sed -n '/FLOW_USER_PYTHONPATH+x/,/unset PYTHONPATH; fi/p' > "$E2E_DIR/sanitizer.sh"
printf '%s\n' 'printf "PYTHONPATH=%s\n" "${PYTHONPATH-unset}"' >> "$E2E_DIR/sanitizer.sh"
mkdir -p "$E2E_DIR/site-outside"
e2e_plugin_copy bin/run-shell.sh "$(printf '%s\n' '#!/bin/sh' 'exec "$1" "$2"')"
for sh in $E2E_FENCE_SHELLS; do
  e2e_run_bin "PYTHONPATH=//:$E2E_DIR/site-outside" bin/run-shell.sh "$sh" "$E2E_DIR/sanitizer.sh"
  e2e_expect_line "PYTHONPATH=$(cd -P "$E2E_DIR/site-outside" && pwd -P)"
done

_flow_test_begin "system-one-client-colon-in-resolved-path"
e2e_new system-one-client-colon-in-resolved-path
e2e_describe "bin/flow-s1.sh with PYTHONPATH naming a symlink to a directory called a:b outside the repository; kept as resolved, it would split into a and a relative b, which is the repository's b/ where a sitecustomize.py is planted (G13)"
e2e_repo feature/g13
printf 'state\n' > "$E2E_REPO/state.txt"
_plant_site "$E2E_REPO/b" "$E2E_DIR/ran-planted"
mkdir -p "$E2E_DIR/outside/a:b" "$E2E_DIR/outside/a"
ln -s "$E2E_DIR/outside/a:b" "$E2E_DIR/outside/link"
_s1_none "symlink to a:b" "PYTHONPATH=$E2E_DIR/outside/link${PYTHONPATH:+:$PYTHONPATH}"

_flow_test_begin "system-one-client-case-variant"
e2e_new system-one-client-case-variant
e2e_describe "bin/flow-s1.sh with PYTHONPATH naming the repository's Src/ directory, where a sitecustomize.py is planted, through the scenario directory's name in upper case; on a case-insensitive disk that is the same directory (G14)"
e2e_repo feature/g14
printf 'state\n' > "$E2E_REPO/state.txt"
_plant_site "$E2E_REPO/Src" "$E2E_DIR/ran-planted"
# The scenario's own directory name, upper-cased: the same directory on a
# case-insensitive disk, and a path that differs as text above the repository.
E2E_LOWER="$(dirname "$E2E_DIR")/$(basename "$E2E_DIR" | tr 'a-z' 'A-Z')/repo/Src"
if [ -d "$E2E_LOWER" ] && [ "$E2E_LOWER" != "$E2E_REPO/Src" ]; then
  _s1_none "upper-case scenario directory" "PYTHONPATH=$E2E_LOWER${PYTHONPATH:+:$PYTHONPATH}"
else
  printf 'case-sensitive disk: %s does not name the same directory; nothing to check\n' "$E2E_LOWER" | _e2e_art
  _e2e_result pass "skipped: the disk is case-sensitive"
fi


_flow_test_begin "pyyaml-only-inside-repository"
e2e_new pyyaml-only-inside-repository
e2e_describe "the Stop hook and the evaluator with PyYAML reachable only through PYTHONPATH=<repo>/vendor, which the sanitizer drops: each says why in its PyYAML note (G15, G19)"
e2e_repo feature/g15
mkdir -p "$E2E_REPO/vendor"
cp -R "$(python3 -c 'import os, yaml; print(os.path.dirname(yaml.__file__))')" "$E2E_REPO/vendor/yaml"
e2e_goal g15 feature/g15 active true
# python3 without site-packages (-S), so PyYAML is found only through
# PYTHONPATH, which it still reads, wherever PyYAML is installed here.
S15_REAL=$(command -v python3)
printf '#!/bin/sh\nexec %s -S "$@"\n' "$S15_REAL" > "$E2E_BIN/python3"; chmod +x "$E2E_BIN/python3"
for hook in hooks/scripts/flow-goal-stop.sh hooks/scripts/flow-goal-evaluator.sh; do
  rm -f "$E2E_HOME/.claude/flow-degraded-pyyaml"
  e2e_run_hook "PYTHONPATH=$E2E_REPO/vendor" "$hook" "$STOP"
  e2e_expect_out '"reason":"PyYAML unavailable"'
  e2e_expect_err "Flow uses only PYTHONPATH entries that are directories outside the repository and not at or above the working directory"
done
# Nothing dropped: a directory outside the repository, named through a
# symlink, is kept under its resolved path, so the PYTHONPATH text changes
# but no element was removed, and the note must not appear.
mkdir -p "$E2E_DIR/real-site"
ln -s "$E2E_DIR/real-site" "$E2E_DIR/link-site"
for hook in hooks/scripts/flow-goal-stop.sh hooks/scripts/flow-goal-evaluator.sh; do
  rm -f "$E2E_HOME/.claude/flow-degraded-pyyaml"
  e2e_run_hook "PYTHONPATH=$E2E_DIR/link-site" "$hook" "$STOP"
  e2e_expect_out '"reason":"PyYAML unavailable"'
  e2e_expect_equal 0 "$(grep -c 'Flow uses only PYTHONPATH' <<<"$E2E_ERR")" "notes about the PYTHONPATH rule from $hook when nothing was dropped"
done
# G19: an element holding a byte that is not UTF-8, in a UTF-8 locale; the
# element that holds PyYAML is still dropped, so the note must appear. The
# locale list is read whole first: grep -q stops early, and under pipefail the
# listing's SIGPIPE would fail the pipeline.
S15_LIST=$(locale -a 2>/dev/null); S15_LIST_RC=$?
S15_UTF8=$(grep -ix 'en_us\.utf-\{0,1\}8' <<<"$S15_LIST" | head -1)
# Where locale -a fails or lists no en_US UTF-8 locale, en_US.UTF-8 is used
# anyway: the scenario holds in any locale, and in a UTF-8 one it is the
# macOS tr case it was written for.
if [ -n "$S15_UTF8" ]; then S15_WHY="listed by locale -a"
elif [ "$S15_LIST_RC" -ne 0 ]; then S15_WHY="locale -a failed (exit $S15_LIST_RC)"
else S15_WHY="locale -a lists no en_US UTF-8 locale"; fi
S15_UTF8=${S15_UTF8:-en_US.UTF-8}
printf 'G19 locale: %s (%s)\n' "$S15_UTF8" "$S15_WHY" | _e2e_art
for hook in hooks/scripts/flow-goal-stop.sh hooks/scripts/flow-goal-evaluator.sh; do
  rm -f "$E2E_HOME/.claude/flow-degraded-pyyaml"
  e2e_run_hook "LC_ALL=$S15_UTF8" "PYTHONPATH=$E2E_DIR/real-site:$E2E_REPO/vendor:"$'/bad\xff'":$E2E_DIR/link-site" "$hook" "$STOP"
  e2e_expect_out '"reason":"PyYAML unavailable"'
  e2e_expect_err "Flow uses only PYTHONPATH entries that are directories outside the repository and not at or above the working directory"
done

_flow_test_begin "system-one-client-symlink-into-repository"
e2e_new system-one-client-symlink-into-repository
e2e_describe "bin/flow-s1.sh with PYTHONPATH naming a symlink outside the repository that points to the repository's b/, where a sitecustomize.py is planted (G16)"
e2e_repo feature/g16
printf 'state\n' > "$E2E_REPO/state.txt"
_plant_site "$E2E_REPO/b" "$E2E_DIR/ran-planted"
mkdir -p "$E2E_DIR/outside"
ln -s "$E2E_REPO/b" "$E2E_DIR/outside/to-b"
_s1_none "symlink to <repo>/b" "PYTHONPATH=$E2E_DIR/outside/to-b${PYTHONPATH:+:$PYTHONPATH}"

_flow_test_begin "system-one-client-in-worktree"
e2e_new system-one-client-in-worktree
e2e_describe "bin/flow-s1.sh run in sub/ of a git worktree of the repository (where .git is a file), with PYTHONPATH naming the worktree's src/, where a sitecustomize.py is planted (G17)"
e2e_repo feature/g17
(_e2e_git_env; cd "$E2E_REPO" && git worktree add -q -b g17-wt "$E2E_DIR/wt" >/dev/null 2>&1) \
  || _flow_assert_fail "$E2E_NAME: could not add a worktree"
e2e_expect_equal file "$([ -f "$E2E_DIR/wt/.git" ] && echo file || echo other)" "the worktree's .git"
mkdir -p "$E2E_DIR/wt/sub"
printf 'state\n' > "$E2E_DIR/wt/sub/state.txt"
_plant_site "$E2E_DIR/wt/src" "$E2E_DIR/ran-planted"
E2E_TOP="$E2E_REPO"; E2E_REPO="$E2E_DIR/wt/sub"
_s1_none "worktree src from its sub/" "PYTHONPATH=$E2E_DIR/wt/src${PYTHONPATH:+:$PYTHONPATH}"
E2E_REPO="$E2E_TOP"

_flow_test_begin "sanitizer-name-outside-locale"
e2e_new sanitizer-name-outside-locale
e2e_describe "the shipped sanitizer lines under each shell, in a strict locale whose stdout cannot encode the name of a directory outside the repository: the directory is still kept (G18)"
e2e_repo feature/g18
S18_LC=""; S18_NAME=""; S18_TRIED=""; S18_CHECKS=0
S18_LOCALES=$(locale -a 2>/dev/null); S18_LIST_RC=$?
# _s18_try <kind> <locale> <name> <name as text> — use <locale> if printing the
# path of a directory called <name> as text fails there, which is where the
# defect shows; otherwise record why not, for the note below.
_s18_try() {
  if ! mkdir -p "$E2E_DIR/$3" 2>/dev/null; then
    S18_TRIED="${S18_TRIED}$2: could not create $4; "; return 1
  fi
  S18_CHECKS=$((S18_CHECKS + 1))
  if ! LC_ALL=$2 python3 -I -c 'import os, sys; sys.stdout.write(os.path.realpath(sys.argv[1]))' "$E2E_DIR/$3" >/dev/null 2>&1; then
    S18_LC=$2; S18_NAME=$3; return 0
  fi
  S18_TRIED="${S18_TRIED}$2 printed $4 without error; "
  rmdir "$E2E_DIR/$3" 2>/dev/null
  return 1
}
# First a language_territory UTF-8 locale (never C.UTF-8 or POSIX, where
# Python's stdout is lenient) with a byte that is not UTF-8, which Linux file
# names may hold; then a language_territory ISO 8859-1 locale with a
# non-Latin name, for macOS, whose file names must be UTF-8.
# When locale -a lists no such locale (or cannot run), the common en_US name is
# tried anyway, and the print check decides.
S18_UTF8=$(grep -ix '[a-z]\{2,3\}_[a-z]\{2\}\.utf-\{0,1\}8' <<<"$S18_LOCALES" | head -1)
S18_ISO=$(grep -ix '[a-z]\{2,3\}_[a-z]\{2\}\.iso-\{0,1\}8859-\{0,1\}1' <<<"$S18_LOCALES" | head -1)
# _s18_why <kind> <listed locale> <fallback> — one reason per kind: the listing
# failed, or it lists nothing of that form (a listed locale needs none).
_s18_why() {
  [ -z "$2" ] || return 0
  if [ "$S18_LIST_RC" -ne 0 ]; then
    S18_TRIED="${S18_TRIED}locale -a failed (exit $S18_LIST_RC), so $3 was tried; "
  else
    S18_TRIED="${S18_TRIED}locale -a lists no locale of the form xx_YY.$1, so $3 was tried; "
  fi
}
_s18_why UTF-8 "$S18_UTF8" en_US.UTF-8
_s18_why ISO8859-1 "$S18_ISO" en_US.ISO8859-1
_s18_try UTF-8 "${S18_UTF8:-en_US.UTF-8}" "site-"$'\xff' 'site-\xff' \
  || _s18_try ISO8859-1 "${S18_ISO:-en_US.ISO8859-1}" "site-日本" "site-日本"
if [ -n "$S18_LC" ]; then
  flow_block "$E2E_ACTIVE_PLUGIN/commands/address.md" DISPUTED_ARRAY_BLOCK 2>/dev/null \
    | sed -n '/FLOW_USER_PYTHONPATH+x/,/unset PYTHONPATH; fi/p' > "$E2E_DIR/sanitizer.sh"
  printf '%s\n' 'printf "PYTHONPATH=%s\n" "${PYTHONPATH-unset}"' >> "$E2E_DIR/sanitizer.sh"
  e2e_plugin_copy bin/run-shell.sh "$(printf '%s\n' '#!/bin/sh' 'exec "$1" "$2"')"
  for sh in $E2E_FENCE_SHELLS; do
    e2e_run_bin "LC_ALL=$S18_LC" "PYTHONPATH=$E2E_DIR/$S18_NAME" bin/run-shell.sh "$sh" "$E2E_DIR/sanitizer.sh"
    e2e_expect_line "PYTHONPATH=$(cd -P "$E2E_DIR/$S18_NAME" && pwd -P)"
  done
else
  printf 'nothing to check: %sprint checks run: %d\n' "$S18_TRIED" "$S18_CHECKS" | _e2e_art
  _e2e_result pass "skipped: ${S18_TRIED}print checks run: $S18_CHECKS"
fi

_flow_test_begin "one-line-guard-without-working-directory"
e2e_new one-line-guard-without-working-directory
e2e_describe "the Stop hook, the goal evaluator and flow-active-goal.sh, each started from a working directory that has been deleted (G20) and from one that cannot be searched, mode 000 (G21), with PYTHONPATH empty and PyYAML importable from site-packages: none reports PyYAML as unavailable or required, as a plain import of PyYAML would not. The harness moves HOME, so a PyYAML installed with pip --user is named through PYTHONUSERBASE. With PYTHONPATH set, the sanitizer drops every element in such a directory by design (G11), so PYTHONPATH is left empty here. The session-end hook is left out: it exits quietly whether or not its probe fails. Run as root, mode 000 does not stop a search, so the G21 half checks nothing"
e2e_repo feature/g20
e2e_plugin_copy bin/from-unusable-dir-run.sh "$(printf '%s\n' '#!/bin/sh' \
  'root=$(cd "$(dirname "$0")/.." && pwd)' \
  'here=$(pwd)' \
  'case "$3" in' \
  '  deleted) mkdir gone && cd gone && rmdir ../gone || exit 97 ;;' \
  '  unsearchable) mkdir locked && cd locked && chmod 000 "$here/locked" || exit 97 ;;' \
  'esac' \
  'printf "%s" "$2" | "$root/$1"; rc=$?' \
  '[ "$3" = unsearchable ] && chmod 755 "$here/locked" && rmdir "$here/locked"' \
  'exit $rc')"
G20_BASE=$(python3 -m site --user-base 2>/dev/null)
if env -u PYTHONPATH PYTHONUSERBASE="$G20_BASE" python3 -c 'import yaml' 2>/dev/null; then
  for how in deleted unsearchable; do
    for code in hooks/scripts/flow-goal-stop.sh hooks/scripts/flow-goal-evaluator.sh bin/flow-active-goal.sh; do
      rm -f "$E2E_HOME/.claude/flow-degraded-pyyaml"
      e2e_run_bin "PYTHONPATH=" "PYTHONUSERBASE=$G20_BASE" bin/from-unusable-dir-run.sh "$code" "$STOP" "$how"
      e2e_expect_equal "0 0" "$(grep -cE 'PyYAML (unavailable|required)' <<<"$E2E_OUT") $(grep -cE 'PyYAML (unavailable|required)' <<<"$E2E_ERR")" "lines saying PyYAML is unavailable or required, in stdout and stderr of $code ($how)"
      e2e_expect_equal no "$([ "$E2E_RC" = 97 ] && echo yes || echo no)" "the helper could not make its working directory $how ($code)"
    done
  done
else
  _e2e_result pass "skipped: python3 cannot import PyYAML without PYTHONPATH here, so there is nothing to compare"
fi

_flow_test_begin "system-one-dedup-planted-modules"
e2e_new system-one-dedup-planted-modules
e2e_describe "bin/flow-s1-dedup.sh in the repository with the modules planted in it and in its src/ directory, PYTHONPATH naming src/ after an empty element, under a python3 that ignores PYTHONSAFEPATH (G22). With no provider it reads the findings with Python and reports provider-none from the client"
e2e_repo feature/g22
_plant
_plant "$E2E_REPO/src"
printf 'value = 1\n' > "$E2E_REPO/app.py"
printf '%s\n' '[{"id":"F1","priority":"P1","category":"correctness","location":"app.py:1","confidence":"HIGH","reviewers":["code-reviewer"]},{"id":"ERR-1","priority":"P2","category":"error-handling","location":"app.py:1","confidence":"HIGH","reviewers":["error-handler-inspector"]}]' > "$E2E_DIR/findings.json"
real=$(command -v python3)
printf '#!/bin/sh\nunset PYTHONSAFEPATH\nexec %s "$@"\n' "$real" > "$E2E_BIN/python3"; chmod +x "$E2E_BIN/python3"
e2e_run_bin "PYTHONPATH=:$E2E_REPO/src${PYTHONPATH:+:$PYTHONPATH}" bin/flow-s1-dedup.sh --findings "$E2E_DIR/findings.json" --out "$E2E_DIR/out.json" --tree "$E2E_REPO" --ref-prefix pr:1/review-cycle:1
_expect_none_ran
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_line "DEDUP_STATE=no-answer"
e2e_expect_line "REASON=provider-none"

_flow_test_begin "system-one-confidence-planted-modules"
e2e_new system-one-confidence-planted-modules
e2e_describe "bin/flow-s1-confidence.sh and bin/flow-finding-state.sh in the repository with the modules planted in it and in its src/ directory, PYTHONPATH naming src/ after an empty element, under a python3 that ignores PYTHONSAFEPATH (G23). With no provider the first reads the findings and the cited code with Python and reports provider-none from the client; the second prints the state"
e2e_repo feature/g23
_plant
_plant "$E2E_REPO/src"
printf 'value = 1\n' > "$E2E_REPO/app.py"
# The cited file is committed: a file git does not track is never read.
(_e2e_git_env; cd "$E2E_REPO" && git add app.py && git commit -q -m app) || _flow_assert_fail "$E2E_NAME: commit app.py"
printf '%s\n' '[{"id":"F1","priority":"P1","category":"correctness","location":"app.py:1","problem":"p","confidence":"HIGH","reviewers":["code-reviewer"]}]' > "$E2E_DIR/findings.json"
printf '%s\n' '{"id":"F1","priority":"P1","category":"correctness","location":"app.py:1","problem":"p","confidence":"HIGH","reviewers":["code-reviewer"]}' > "$E2E_DIR/finding.json"
real=$(command -v python3)
printf '#!/bin/sh\nunset PYTHONSAFEPATH\nexec %s "$@"\n' "$real" > "$E2E_BIN/python3"; chmod +x "$E2E_BIN/python3"
e2e_run_bin "PYTHONPATH=:$E2E_REPO/src${PYTHONPATH:+:$PYTHONPATH}" bin/flow-s1-confidence.sh --findings "$E2E_DIR/findings.json" --tree "$E2E_REPO" --ref-prefix pr:1/review-cycle:1
_expect_none_ran
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_line "S1_CONFIDENCE_RESULT=F1 STATE=no-answer REASON=provider-none"
e2e_run_bin "PYTHONPATH=:$E2E_REPO/src${PYTHONPATH:+:$PYTHONPATH}" bin/flow-finding-state.sh --tree "$E2E_REPO" --finding "$E2E_DIR/finding.json"
_expect_none_ran
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_out '"text":"value = 1"'

_flow_test_begin "system-one-challenge-planted-modules"
e2e_new system-one-challenge-planted-modules
e2e_describe "bin/flow-s1-challenge.sh in the repository with the modules planted in it and in its src/ directory, PYTHONPATH naming src/ after an empty element, under a python3 that ignores PYTHONSAFEPATH (G24). With no provider it reads the findings and the cited code with Python and reports provider-none from the client"
e2e_repo feature/g24
_plant
_plant "$E2E_REPO/src"
printf 'value = 1\n' > "$E2E_REPO/app.py"
(_e2e_git_env; cd "$E2E_REPO" && git add app.py && git commit -q -m app) || _flow_assert_fail "$E2E_NAME: commit app.py"
printf '%s\n' '[{"id":"F1","priority":"P1","category":"correctness","location":"app.py:1","problem":"p","confidence":"LOW","disposition":"kept","reviewers":["code-reviewer-verifier"]}]' > "$E2E_DIR/findings.json"
real=$(command -v python3)
printf '#!/bin/sh\nunset PYTHONSAFEPATH\nexec %s "$@"\n' "$real" > "$E2E_BIN/python3"; chmod +x "$E2E_BIN/python3"
e2e_run_bin "PYTHONPATH=:$E2E_REPO/src${PYTHONPATH:+:$PYTHONPATH}" bin/flow-s1-challenge.sh --findings "$E2E_DIR/findings.json" --tree "$E2E_REPO" --ref-prefix pr:1/review-cycle:1
_expect_none_ran
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_line "S1_CHALLENGE_RESULT=F1 STATE=no-answer REASON=provider-none CONFIDENCE=LOW DISPOSITION=kept"
