# shellcheck shell=bash
# End-to-end: the bin/ helpers convert the paths they hand python3 at one
# boundary, lib/py-path.sh, so a native Windows python3 can open them (#246).
#
# This runs on any system: FLOW_PY_PATH_PLATFORM makes lib/py-path.sh take
# its Git Bash branch, and a stub `cygpath` on PATH records each path it is
# asked to convert and hands it back unchanged, so the helper still does its
# work with the system's python3. tests/windows-hooks-smoke.sh runs the same
# helpers on a real Windows runner (.github/workflows/windows-hooks.yml). The
# artifact for each scenario is written to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the scenarios:
#   W1 a helper hands python3 its own directory unconverted, so the import of
#      the module beside it fails on Windows
#   W2 an absolute file argument (a goal file, a verdict file) reaches python3
#      unconverted
#   W3 text that only starts with a slash (`/flow:start Phase 1`) is converted
#      as if it were a path
#   W4 a module directory handed over in an environment variable
#      (FLOW_DEP_BIN) is not converted
#   W5 on Linux and macOS anything is converted (cygpath is called at all)
#   W6 with the conversion in place the helper no longer does its work
#   W7 a user path variable (FLOW_STATE_DIR) that reaches a script in Windows
#      form, as MSYS2 hands it to a script a native python3 starts, is ignored,
#      so the trust ledger is written to one place and read from another

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

if ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_test_begin "windows paths: PyYAML prerequisite"
  _flow_assert_pass "SKIP: PyYAML not installed"
  return 0
fi

WIN=MINGW64_NT-10.0-19045

# _win_case <name> <purpose> — a scratch repository on the goal fixture's
# branch, with a stub cygpath that logs to $E2E_DIR/cygpath.log.
_win_case() {
  _flow_test_begin "$1"
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo feature/issue-42-search-fix
  cat > "$E2E_BIN/cygpath" <<STUB
#!/usr/bin/env bash
[ "\$1" = -m ] || { printf 'unexpected cygpath %s\n' "\$*" >> "$E2E_DIR/cygpath.log"; exit 1; }
printf '%s\n' "\$2" >> "$E2E_DIR/cygpath.log"
printf '%s' "\$2"
STUB
  chmod +x "$E2E_BIN/cygpath"
  : > "$E2E_DIR/cygpath.log"
  cp "$REPO_ROOT/plugins/flow/tests/fixtures/goal/valid.yaml" "$E2E_DIR/goal.yaml"
}
_converted() { grep -qxF -- "$1" "$E2E_DIR/cygpath.log"; }
_expect_converted() {
  if _converted "$1"; then _e2e_result pass "converted: $2"; else _e2e_result fail "converted: $2 ($1)"; fi
}
_expect_not_converted() {
  if grep -qF -- "$1" "$E2E_DIR/cygpath.log"; then _e2e_result fail "not converted: $2"; else _e2e_result pass "not converted: $2"; fi
}
BIN_DIR="$E2E_PLUGIN_DIR/bin"

_win_case win-goal-record "flow-goal-record.sh under Git Bash: its own directory and the absolute goal file are converted, and the goal is written (W1, W2, W6)"
e2e_run_bin FLOW_PY_PATH_PLATFORM=$WIN bin/flow-goal-record.sh --create --goal-file "$E2E_DIR/goal.yaml"
e2e_expect_equal 0 "$E2E_RC" "exit status"
_expect_converted "$(cd "$BIN_DIR" && pwd)" "the bin directory"
_expect_converted "$E2E_DIR/goal.yaml" "the goal file"
e2e_expect_equal yes "$([ -f "$E2E_REPO/.flow/goals/issue-42.goal.yaml" ] && echo yes || echo no)" "the goal was written"
e2e_expect_clean_edges

_win_case win-active-goal "flow-active-goal.sh under Git Bash converts its directory and still answers (W1, W6)"
(_e2e_git_env; cd "$E2E_REPO" && "$E2E_ACTIVE_PLUGIN/bin/flow-goal-record.sh" --create --goal-file "$E2E_DIR/goal.yaml" >/dev/null 2>&1)
: > "$E2E_DIR/cygpath.log"
e2e_run_bin FLOW_PY_PATH_PLATFORM=$WIN bin/flow-active-goal.sh --id --branch-strict
e2e_expect_line "issue-42"
_expect_converted "$(cd "$BIN_DIR" && pwd)" "the bin directory"
e2e_expect_clean_edges

_win_case win-question-text "flow-question.sh under Git Bash: a --command that starts with a slash is text, not a path (W3, W6)"
e2e_run_bin FLOW_PY_PATH_PLATFORM=$WIN bin/flow-question.sh add --situation s --tried t \
  --option "a (Recommended)" --option b --recommendation r --blocking soft --risk k --command "/flow:start Phase 1"
e2e_expect_equal 0 "$E2E_RC" "exit status"
_expect_converted "$(cd "$BIN_DIR" && pwd)" "the bin directory"
_expect_not_converted "/flow:start" "the --command text"
e2e_run_bin bin/flow-question.sh list
e2e_expect_out "|/flow:start Phase 1|"
e2e_expect_clean_edges

_win_case win-dep-diff-env "flow-dep-diff.sh under Git Bash: the module directory it passes in FLOW_DEP_BIN is converted, and the diff is read (W4, W6)"
(
  _e2e_git_env
  cd "$E2E_REPO" || exit 1
  printf 'flask==2.0\n' > requirements.txt && git add -A && git commit -q -m base
  printf 'flask==2.1\n' > requirements.txt && git add -A && git commit -q -m head
) || _flow_assert_fail "win-dep-diff-env: could not commit the fixture"
e2e_run_bin FLOW_PY_PATH_PLATFORM=$WIN bin/flow-dep-diff.sh --base HEAD~1 --head HEAD
e2e_expect_line "DEP_CHANGED=flask 2.0->2.1 manifest=requirements.txt:1"
_expect_converted "$(cd "$BIN_DIR" && pwd)" "the bin directory (FLOW_DEP_BIN)"
e2e_expect_clean_edges

_win_case win-posix-untouched "on Linux or macOS nothing is converted: cygpath is never called (W5)"
e2e_run_bin bin/flow-goal-record.sh --create --goal-file "$E2E_DIR/goal.yaml"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_equal 0 "$(grep -c . "$E2E_DIR/cygpath.log")" "cygpath calls"
e2e_expect_clean_edges

# Every helper that runs python3 with a path sources the one conversion.
_flow_test_begin "win-every-helper-sources-the-lib"
e2e_new win-every-helper-sources-the-lib
e2e_describe "every bin/ helper and hook that puts a directory on python's sys.path sources lib/py-path.sh, and no helper keeps its own copy of py_path (W1)"
e2e_repo feature/issue-246-e2e
_missing=$(cd "$E2E_PLUGIN_DIR" && grep -l 'sys.path.insert(0' bin/*.sh hooks/scripts/*.sh | while read -r f; do grep -q 'lib/py-path.sh' "$f" || printf '%s\n' "$f"; done)
e2e_expect_equal "" "$_missing" "helpers that put a directory on sys.path without the conversion"
_copies=$(cd "$E2E_PLUGIN_DIR" && grep -l '^py_path() {' bin/*.sh hooks/scripts/*.sh 2>/dev/null || true)
e2e_expect_equal "" "$_copies" "helpers with their own py_path"
e2e_expect_clean_edges

# W7: the stub here converts with -u, mapping the made-up drive Z: to a
# directory of the scenario, as cygpath maps D: to /d.
_win_case win-state-dir-windows-form "FLOW_STATE_DIR in Windows form (Z:\\state, Z:/state) under Git Bash is read as the shell reaches it; off Windows it is not an absolute path and is ignored (W7)"
mkdir -p "$E2E_DIR/zdrive/state"
cat > "$E2E_BIN/cygpath" <<STUB
#!/usr/bin/env bash
[ "\$1" = -u ] || { printf 'unexpected cygpath %s\n' "\$*" >> "$E2E_DIR/cygpath.log"; exit 1; }
printf '%s\n' "\$2" >> "$E2E_DIR/cygpath.log"
p=\${2//\\\\//}
case "\$p" in Z:/*) printf '%s' "$E2E_DIR/zdrive/\${p#Z:/}" ;; *) exit 1 ;; esac
STUB
chmod +x "$E2E_BIN/cygpath"
for form in 'Z:\state' 'Z:/state'; do
  e2e_run_bin FLOW_PY_PATH_PLATFORM=$WIN "FLOW_STATE_DIR=$form" bin/cascade-resolve.sh --state-dir
  e2e_expect_equal 0 "$E2E_RC" "exit status ($form)"
  e2e_expect_equal "$E2E_DIR/zdrive/state" "$E2E_OUT" "the state directory ($form)"
  e2e_expect_err_lacks "ignoring FLOW_STATE_DIR"
done
: > "$E2E_DIR/cygpath.log"
e2e_run_bin "FLOW_STATE_DIR=Z:/state" bin/cascade-resolve.sh --state-dir
e2e_expect_err "ignoring FLOW_STATE_DIR: it is not an absolute path"
_expect_not_converted "Z:/state" "off Windows the value is left as it is"
e2e_expect_clean_edges
