# shellcheck shell=bash
# End-to-end: flow-eval-run.sh --trap checks the trap name against the case's
# list without depending on how fast the lister writes. The check piped
# `list-traps` into `grep -q`, which exits at the first match; when the lister
# was still writing, it was killed by the closed pipe, and under pipefail the
# runner said the case had no such trap. A full suite run hit it under load
# (1 in 8 runs of the same command then). Here a python3 on PATH prints the
# first trap name, waits a second, and prints the rest, so the closed pipe
# happens every time the check stops reading early. The artifact for each
# scenario is written to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the scenarios:
#   R1 a trap the case has is refused when the lister is still writing after
#      the name was found
#   R2 a trap the case does not have is accepted
#   R3 the accepted trap does not narrow the plan to that trap

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

REAL_PY=$(command -v python3)
CASE=interval-algebra
FIRST_TRAP=$("$REAL_PY" "$E2E_PLUGIN_DIR/bin/_flow_eval.py" list-traps "$E2E_PLUGIN_DIR/evals/$CASE" | head -n 1)

# _er_case <name> <purpose> — a scenario with the slow lister on PATH.
_er_case() {
  _flow_test_begin "$1"
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo main
  cat > "$E2E_BIN/python3" <<STUB
#!/usr/bin/env bash
case " \$* " in
  *" list-traps "*)
    out=\$("$REAL_PY" "\$@") || exit \$?
    printf '%s\n' "\${out%%\$'\n'*}"
    sleep 1
    printf '%s\n' "\${out#*\$'\n'}"
    exit \$? ;;
esac
exec "$REAL_PY" "\$@"
STUB
  chmod +x "$E2E_BIN/python3"
  printf 'python3 on PATH: list-traps prints the first trap, waits a second, then prints the rest; anything else runs %s\n' "$REAL_PY" | _e2e_art
}

if [ -z "$FIRST_TRAP" ]; then
  _flow_test_begin "eval-run --trap: prerequisite"
  _flow_assert_fail "the case $CASE lists no trap"
  return 0
fi

_er_case er-trap-slow-lister "R1 R3: --trap names the first trap of $CASE while the lister is still writing the rest: the plan is accepted and holds that trap only"
e2e_run_bin bin/flow-eval-run.sh --mode review --dry-run --case "$CASE" --trap "$FIRST_TRAP" --runs 1 --models a,b --out "$E2E_DIR/plan"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_err_lacks "has no trap"
e2e_expect_out "PLAN  4 run(s): 2 model(s) × 2 arm(s) × 1 case(s) × 1 trap(s)"
e2e_expect_equal 4 "$(printf '%s\n' "$E2E_OUT" | grep -c "^RUN .*/$FIRST_TRAP/1 ")" "RUN lines for the named trap"
e2e_expect_equal 4 "$(printf '%s\n' "$E2E_OUT" | grep -c '^RUN ')" "RUN lines in all"

_er_case er-trap-unknown "R2: --trap names a trap $CASE does not have: refused with the list command, and nothing is planned"
e2e_run_bin bin/flow-eval-run.sh --mode review --dry-run --case "$CASE" --trap no_such_trap --runs 1 --models a,b --out "$E2E_DIR/plan"
e2e_expect_equal 1 "$E2E_RC" "exit status"
e2e_expect_err "case '$CASE' has no trap 'no_such_trap'"
e2e_expect_equal 0 "$(printf '%s\n' "$E2E_OUT" | grep -c '^RUN ')" "RUN lines"
