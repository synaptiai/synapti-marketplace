# shellcheck shell=bash
# End-to-end: flow.runtime.stateDir names the runtime directory, the place
# flow keeps its goals, runs, triggers and watch state, and every reader and
# writer of that state uses it.
#
# bin/flow-runtime-dir.sh prints the directory for shell callers and
# runtime_dir() in bin/_repo_dir.py gives it to Python callers. The scenarios
# set flow.runtime.stateDir in the scratch repository's
# .claude/settings.flow.json and run the real resolver, writers, hooks and
# command blocks there.
#
# Ways it can be wrong, written down before the scenarios:
#   D1 the default is not .flow, or the resolver prints a warning when nothing
#      is set
#   D2 a valid nested value (build/flow-runtime) is ignored, or printed
#      unnormalized (./build//flow-runtime/), so a caller's prefix test or
#      path join misses it
#   D3 a value the rule refuses is used: an absolute path (even one inside the
#      repository), one starting with ~, a `..` component (including one
#      that cancels out by its text, build/../x, which the kernel follows
#      through build), one through a symlink inside the repository, one whose
#      symlink leads outside the repository, or the repository top itself
#   D4 a refused value prints no warning, more than one line, a line that
#      does not name the setting, or a line naming where the value leads
#   D5 a refused value falls back to something other than .flow
#   D6 the shell resolver and runtime_dir() disagree on a value
#   D7 a value from the user's settings is not read (any layer may set it)
#   D8 a writer or reader keeps using .flow when the setting names another
#      directory, so state is written where flow does not read it, or read
#      from where it was not written

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

RT=build/flow-runtime

_settings() { mkdir -p "$E2E_REPO/.claude"; printf '%s\n' "$1" > "$E2E_REPO/.claude/settings.flow.json"; }
_state_dir() { _settings "{\"flow\":{\"runtime\":{\"stateDir\":$1}}}"; }

# _err_lines — how many lines the last run printed on stderr.
_err_lines() { if [ -z "$E2E_ERR" ]; then echo 0; else printf '%s\n' "$E2E_ERR" | wc -l | tr -d ' '; fi; }

# _py_runtime_dir — runtime_dir() from bin/_repo_dir.py, run in the scratch
# repository as a Python caller runs it. Sets E2E_OUT, E2E_ERR, E2E_RC.
_py_runtime_dir() {
  printf 'code: bin/_repo_dir.py runtime_dir()\n' | _e2e_art
  _e2e_exec python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from _repo_dir import runtime_dir; print(runtime_dir())' "$E2E_ACTIVE_PLUGIN/bin"
  printf -- '--- expectations\n' | _e2e_art
}

# _no_default_dir — nothing was written under .flow in the scratch repository.
_no_default_dir() {
  e2e_expect_equal no "$([ -e "$E2E_REPO/.flow" ] && echo yes || echo no)" ".flow exists in the repository"
}

_flow_test_begin "flow-runtime-dir: the default is .flow, with no warning (D1)"
e2e_new runtime-dir-default
e2e_describe "no flow.runtime.stateDir in any settings file"
e2e_repo feature/issue-1-runtime-dir
e2e_run_bin bin/flow-runtime-dir.sh
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_equal .flow "$E2E_OUT" "the directory"
e2e_expect_equal "" "$E2E_ERR" "stderr"

_flow_test_begin "flow-runtime-dir: a nested relative value is used, normalized (D2, D6)"
for v in "$RT" "./build//flow-runtime/" "build/./flow-runtime"; do
  e2e_new "runtime-dir-valid-$(printf '%s' "$v" | tr -c 'a-z0-9' '_')"
  e2e_describe "flow.runtime.stateDir '$v' in the project settings; build/ does not exist yet"
  e2e_repo feature/issue-1-runtime-dir
  _state_dir "\"$v\""
  e2e_run_bin bin/flow-runtime-dir.sh
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal "$RT" "$E2E_OUT" "the directory"
  e2e_expect_equal "" "$E2E_ERR" "stderr"
  sh_out="$E2E_OUT"
  _py_runtime_dir
  e2e_expect_equal "$sh_out" "$E2E_OUT" "runtime_dir() beside flow-runtime-dir.sh"
  e2e_expect_equal "" "$E2E_ERR" "runtime_dir()'s stderr"
  _no_default_dir
done

_flow_test_begin "flow-runtime-dir: a value in the user's settings is used (D7)"
e2e_new runtime-dir-user
e2e_describe "flow.runtime.stateDir build/flow-runtime in the user's settings only"
e2e_repo feature/issue-1-runtime-dir
e2e_user_settings "{\"flow\":{\"runtime\":{\"stateDir\":\"$RT\"}}}"
e2e_run_bin bin/flow-runtime-dir.sh
e2e_expect_equal "$RT" "$E2E_OUT" "the directory"

_flow_test_begin "flow-runtime-dir: a refused value prints one warning naming the setting and .flow is used (D3, D4, D5, D6)"
# name|value (a JSON string)|what stderr must say|setup
_refused() {
  local name="$1" value="$2" reason="$3" setup="$4"
  e2e_new "runtime-dir-refused-$name"
  e2e_describe "flow.runtime.stateDir $value: $reason"
  e2e_repo feature/issue-1-runtime-dir
  mkdir -p "$E2E_DIR/elsewhere"
  case "$setup" in
    link-inside) mkdir -p "$E2E_REPO/real"; ln -s real "$E2E_REPO/build" ;;
    link-outside) ln -s "$E2E_DIR/elsewhere" "$E2E_REPO/build" ;;
    build) mkdir -p "$E2E_REPO/build" "$E2E_REPO/x" ;;
  esac
  _state_dir "$value"
  e2e_run_bin bin/flow-runtime-dir.sh
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal .flow "$E2E_OUT" "the directory"
  e2e_expect_equal 1 "$(_err_lines)" "the number of stderr lines"
  e2e_expect_err "refusing flow.runtime.stateDir: $reason"
  e2e_expect_err "using .flow"
  e2e_expect_err_lacks "$E2E_DIR"
  e2e_expect_err_lacks "elsewhere"
  e2e_expect_err_lacks "/real"
  local sh_out="$E2E_OUT" sh_err="$E2E_ERR"
  _py_runtime_dir
  e2e_expect_equal "$sh_out" "$E2E_OUT" "runtime_dir() beside flow-runtime-dir.sh"
  e2e_expect_equal "$sh_err" "$E2E_ERR" "runtime_dir()'s warning beside flow-runtime-dir.sh's"
}
_refused absolute-inside "\"$E2E_ROOT/runtime-dir-refused-absolute-inside/repo/$RT\"" "it is an absolute path" ""
_refused absolute-outside '"/tmp/flow-runtime"' "it is an absolute path" ""
_refused tilde '"~/flow-runtime"' "it starts with ~" ""
_refused dotdot-out '"../flow-runtime"' "it has a .. component" ""
_refused dotdot-cancels '"build/../x"' "it has a .. component" build
_refused link-inside "\"$RT\"" "build is a symlink" link-inside
_refused link-outside "\"$RT\"" "build is a symlink" link-outside
_refused top '"."' "it names the repository top itself" ""
