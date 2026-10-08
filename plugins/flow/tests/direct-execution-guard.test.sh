# shellcheck shell=bash
# A test file run any way other than through tests/run.sh must stop before it
# does anything. An e2e file executed with `bash <file>` used to keep going
# when its library did not load: `source ... || return 0` cannot stop a script
# that is executed rather than sourced, so the scenario setup ran git in the
# current directory and committed into it.
#
# Each e2e file is executed directly from inside a scratch git repository:
# with REPO_ROOT unset, with REPO_ROOT naming a directory that holds no
# library, and with REPO_ROOT set to this checkout but without run.sh's
# assert.sh. A fourth run loads assert.sh first and then sources the file
# with REPO_ROOT naming the directory with no library, so only the last step
# of the file's prelude, loading tests/lib/e2e.sh, can fail. Every run must
# exit non-zero, and the repository must keep its commits, branches,
# configuration and working tree. This file is not one of the files it runs.
# The fourth run sets FLOW_E2E_SCENARIOS to a name no scenario has, so a file
# whose prelude let it through still runs no scenario body.
#
# Then the library's own guard: inside a scenario subshell, git refuses to run
# anywhere but below the scratch root, so an empty E2E_REPO cannot put a
# scenario's commit in the directory the tests run from.

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null; } || {
  printf '%s\n' "run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

DEG_TMP=$(mktemp -d "${TMPDIR:-/tmp}/flow-direct-exec.XXXXXX") || { _flow_assert_fail "mktemp -d failed"; return 0; }
DEG_TESTS="$REPO_ROOT/plugins/flow/tests"

# _deg_repo <dir> — a git repository with one commit, isolated from the
# caller's git settings.
_deg_repo() {
  mkdir -p "$1" "$DEG_TMP/home"
  ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
    export HOME="$DEG_TMP/home" GIT_CONFIG_NOSYSTEM=1
    cd "$1" || exit 1
    git init -q && git config user.email t@example.invalid && git config user.name t \
      && git config commit.gpgsign false && printf 'x\n' > x && git add x && git commit -q -m init ) \
    || _flow_assert_fail "could not create the scratch repository $1"
}

# _deg_state <dir> — what a stray run would change: every ref with its commit,
# the configuration, and the working tree's status.
_deg_state() {
  ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
    export HOME="$DEG_TMP/home" GIT_CONFIG_NOSYSTEM=1
    cd "$1" || exit 1
    git for-each-ref --format='%(refname) %(objectname)'
    git rev-parse HEAD
    git rev-list --all --count
    git config --local --list
    git status --porcelain --untracked-files=all )
}

# _deg_run <repo> <file> <REPO_ROOT value or -unset> [assert] — executes the
# file with bash from inside the repository, ended after 60 seconds. With
# `assert`, the bash process sources run.sh's assert.sh and then the file, as
# run.sh does, so the file's prelude finds _flow_assert_fail defined.
_deg_run() {
  local root_arg=()
  if [ "$3" = -unset ]; then root_arg=(-u REPO_ROOT); else root_arg=("REPO_ROOT=$3"); fi
  if [ "${4:-}" = assert ]; then
    # shellcheck disable=SC2016
    ( cd "$1" && env "${root_arg[@]}" HOME="$DEG_TMP/home" FLOW_E2E_ARTIFACT_DIR= FLOW_E2E_SCENARIOS=deg-no-such-scenario \
        perl -e 'alarm 60; exec @ARGV or exit 126' bash -c 'source "$1" || exit 98; source "$2"' _ "$DEG_TESTS/lib/assert.sh" "$2" ) \
      >"$DEG_TMP/out" 2>"$DEG_TMP/err"
    return
  fi
  ( cd "$1" && env "${root_arg[@]}" HOME="$DEG_TMP/home" FLOW_E2E_ARTIFACT_DIR= \
      perl -e 'alarm 60; exec @ARGV or exit 126' bash "$2" ) >"$DEG_TMP/out" 2>"$DEG_TMP/err"
}

DEG_FILES=()
for _deg_f in "$DEG_TESTS"/*.test.sh; do
  [ "$(basename "$_deg_f")" = direct-execution-guard.test.sh ] && continue
  grep -qF 'source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"' "$_deg_f" && DEG_FILES+=("$_deg_f")
done

_flow_test_begin "every e2e file executed directly stops with a non-zero exit and changes nothing in the repository it runs in"
assert_match '^[1-9][0-9]+$' "${#DEG_FILES[@]}" "the e2e files were found"
mkdir -p "$DEG_TMP/no-library"
for _deg_f in "${DEG_FILES[@]}"; do
  _deg_name=$(basename "$_deg_f")
  for _deg_root in -unset "$DEG_TMP/no-library" "$REPO_ROOT" -assert; do
    _deg_mode=""
    case "$_deg_root" in
      -unset) _deg_how="REPO_ROOT unset" ;;
      "$REPO_ROOT") _deg_how="REPO_ROOT set, without run.sh's assert.sh" ;;
      -assert) _deg_how="assert.sh loaded, REPO_ROOT without the library"; _deg_root="$DEG_TMP/no-library"; _deg_mode=assert ;;
      *) _deg_how="REPO_ROOT without the library" ;;
    esac
    _deg_dir="$DEG_TMP/repo-$_deg_name-$(printf '%s' "$_deg_how" | tr -c 'A-Za-z0-9' '-')"
    _deg_repo "$_deg_dir"
    _deg_before=$(_deg_state "$_deg_dir")
    _deg_run "$_deg_dir" "$_deg_f" "$_deg_root" $_deg_mode; _deg_rc=$?
    if [ "$_deg_rc" -ne 0 ]; then
      _flow_assert_pass "$_deg_name ($_deg_how): exit $_deg_rc"
    else
      _flow_assert_fail "$_deg_name ($_deg_how): exited 0; stderr: $(head -5 "$DEG_TMP/err")"
    fi
    assert_contains "run this file with plugins/flow/tests/run.sh" "$(cat "$DEG_TMP/err")" "$_deg_name ($_deg_how): says how to run it"
    assert_equal "$_deg_before" "$(_deg_state "$_deg_dir")" "$_deg_name ($_deg_how): commits, branches, configuration and working tree unchanged"
  done
done

_flow_test_begin "inside a scenario subshell, git refuses to run outside the scratch root"
_deg_repo "$DEG_TMP/outside"
_deg_before=$(_deg_state "$DEG_TMP/outside")
# The library is loaded in a subshell of its own, as a test file loads it; its
# EXIT trap removes its scratch root when the subshell ends.
DEG_OUT=$(
  cd "$DEG_TMP/outside" || exit 1
  # shellcheck source=lib/e2e.sh
  source "$DEG_TESTS/lib/e2e.sh" || exit 1
  e2e_new guard-empty-repo
  # No e2e_repo: E2E_REPO is empty, so cd "$E2E_REPO" stays in the directory
  # the subshell started in, outside the scratch root.
  ( _e2e_git_env; cd "$E2E_REPO" || exit 1; git commit -q --allow-empty -m stray ) 2>"$DEG_TMP/guard.err"
  printf 'empty-repo=%s\n' "$?"
  ( _e2e_git_env; git -C "$DEG_TMP/outside" commit -q --allow-empty -m stray ) 2>>"$DEG_TMP/guard.err"
  printf 'dash-c-outside=%s\n' "$?"
  e2e_repo feature/guard
  ( _e2e_git_env; cd "$E2E_REPO" && git commit -q --allow-empty -m inside && git rev-list --count HEAD )
  printf 'inside=%s\n' "$?"
)
assert_contains "empty-repo=97" "$DEG_OUT" "git in the directory an empty E2E_REPO leaves is refused"
assert_contains "dash-c-outside=97" "$DEG_OUT" "git -C naming a directory outside the scratch root is refused"
assert_contains "refusing to run git outside the scratch root" "$(cat "$DEG_TMP/guard.err")" "and the refusal says why"
assert_contains $'2\ninside=0' "$DEG_OUT" "git inside the scratch repository still runs"
assert_equal "$_deg_before" "$(_deg_state "$DEG_TMP/outside")" "the repository outside the scratch root is unchanged"

rm -rf "$DEG_TMP"
