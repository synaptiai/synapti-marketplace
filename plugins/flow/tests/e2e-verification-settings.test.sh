# shellcheck shell=bash
# End-to-end: the verification-settings block of /flow:start Phase 4 (and the
# same block in /flow:pr Phase 4 step 2) reads
# closedLoop.enabled, closedLoop.requireRuntimeVerification and
# visualVerification.enabled and prints one line for each, which the rest of
# Phase 4 acts on:
#   CLOSED_LOOP=on|off                      closedLoop.enabled
#   RUNTIME_VERIFICATION=required|optional  closedLoop.requireRuntimeVerification
#   VISUAL_VERIFICATION=on|off              visualVerification.enabled
#
# Ways it can be wrong, written down before the scenarios:
#   V1 a setting is not read, so false has no effect
#   V2 the defaults (all true) print off or optional
#   V3 a value that is not the boolean false (a string, a typo) turns a check
#      off; only false does
#   V4 the block reads the wrong key, so one setting turns off another check

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

START_MD="$E2E_PLUGIN_DIR/commands/start.md"
PR_MD="$E2E_PLUGIN_DIR/commands/pr.md"
MARKER="VISUAL_VERIFICATION="
_settings() { mkdir -p "$E2E_REPO/.claude"; printf '%s\n' "$1" > "$E2E_REPO/.claude/settings.flow.json"; }
# /flow:pr's block is indented under its list item, which e2e_fence does not
# read: take the indented fence that holds the marker and dedent it.
_run_pr_block() {
  awk -v m="$MARKER" '/^   ```bash$/{f=1; buf=""; hit=0; next} f&&/^   ```$/{ if (hit) { printf "%s", buf; exit } f=0; next } f{sub(/^   /,""); buf = buf $0 "\n"; if (index($0, m)) hit=1}' "$PR_MD" > "$E2E_DIR/fence.sh.raw"
  e2e_expect_equal yes "$([ -s "$E2E_DIR/fence.sh.raw" ] && echo yes || echo no)" "whether the /flow:pr block was found"
  _e2e_run_code "commands/pr.md (verification settings block)" ""
}

_flow_test_begin "/flow:start verification settings: the defaults keep every check on (V2)"
e2e_new verification-defaults
e2e_describe "no settings in the repository"
e2e_repo feature/issue-7-verify
e2e_run_fence "$START_MD" "$MARKER"
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "CLOSED_LOOP=on"
e2e_expect_line "RUNTIME_VERIFICATION=required"
e2e_expect_line "VISUAL_VERIFICATION=on"

_flow_test_begin "/flow:start verification settings: each false turns off its own check only (V1, V4)"
e2e_new verification-closed-loop-off
e2e_describe "closedLoop.enabled false"
e2e_repo feature/issue-7-verify
_settings '{"closedLoop":{"enabled":false}}'
e2e_run_fence "$START_MD" "$MARKER"
e2e_expect_line "CLOSED_LOOP=off"
e2e_expect_line "RUNTIME_VERIFICATION=required"
e2e_expect_line "VISUAL_VERIFICATION=on"

e2e_new verification-runtime-optional
e2e_describe "closedLoop.requireRuntimeVerification false"
e2e_repo feature/issue-7-verify
_settings '{"closedLoop":{"requireRuntimeVerification":false}}'
e2e_run_fence "$START_MD" "$MARKER"
e2e_expect_line "CLOSED_LOOP=on"
e2e_expect_line "RUNTIME_VERIFICATION=optional"
e2e_expect_line "VISUAL_VERIFICATION=on"

e2e_new verification-visual-off
e2e_describe "visualVerification.enabled false"
e2e_repo feature/issue-7-verify
_settings '{"visualVerification":{"enabled":false}}'
e2e_run_fence "$START_MD" "$MARKER"
e2e_expect_line "CLOSED_LOOP=on"
e2e_expect_line "RUNTIME_VERIFICATION=required"
e2e_expect_line "VISUAL_VERIFICATION=off"

_flow_test_begin "/flow:start verification settings: only the boolean false turns a check off (V3)"
e2e_new verification-string-false
e2e_describe "each setting given as the string \"no\""
e2e_repo feature/issue-7-verify
_settings '{"closedLoop":{"enabled":"no","requireRuntimeVerification":"no"},"visualVerification":{"enabled":"no"}}'
e2e_run_fence "$START_MD" "$MARKER"
e2e_expect_line "CLOSED_LOOP=on"
e2e_expect_line "RUNTIME_VERIFICATION=required"
e2e_expect_line "VISUAL_VERIFICATION=on"

_flow_test_begin "/flow:pr verification settings: the same block, the same lines (V1, V2)"
e2e_new verification-pr-defaults
e2e_describe "no settings; the /flow:pr block"
e2e_repo feature/issue-7-verify
_run_pr_block
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "CLOSED_LOOP=on"
e2e_expect_line "RUNTIME_VERIFICATION=required"
e2e_expect_line "VISUAL_VERIFICATION=on"

e2e_new verification-pr-all-off
e2e_describe "all three settings false; the /flow:pr block"
e2e_repo feature/issue-7-verify
_settings '{"closedLoop":{"enabled":false,"requireRuntimeVerification":false},"visualVerification":{"enabled":false}}'
_run_pr_block
e2e_expect_line "CLOSED_LOOP=off"
e2e_expect_line "RUNTIME_VERIFICATION=optional"
e2e_expect_line "VISUAL_VERIFICATION=off"
