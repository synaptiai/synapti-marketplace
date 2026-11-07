# shellcheck shell=bash
# End-to-end: /flow:setup writes, detects and upgrades the settings file the
# settings cascade reads, wherever in the repository it runs.
#
# bin/cascade-resolve.sh reads the repository's .claude/settings.flow.json and
# .claude/settings.flow.local.json at the repository top (#337). /flow:setup
# looked for, created and upgraded .claude/settings.flow.json relative to the
# working directory, so a session working in packages/app wrote a file no
# hook or command reads, and its tiers.push: confirm read as the default
# journal. Each scenario runs the shipped setup fences in a scratch
# repository, from a subdirectory or the top, and then asks
# bin/cascade-resolve.sh what it reads. The artifact for each scenario is
# written to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the scenarios:
#   P1 the Phase 1 detection, run in a subdirectory, looks for the settings
#      there: it reports EXISTING_SETTINGS=false for a repository whose top
#      has them, or names a SETTINGS_FILE the cascade does not read
#   P2 a settings file in the working directory or in CLAUDE_PROJECT_DIR below
#      the top, which nothing reads, is not reported, so its tiers.push:
#      confirm silently counts for nothing; or it is reported twice when the
#      two are the same directory
#   P3 at the top, anything changes: SETTINGS_FILE is not the relative
#      .claude/settings.flow.json, or the top's own files are reported as
#      not read
#   P4 the Phase 2 write, run in a subdirectory, creates .claude there
#   P5 the Phase 2 ignore lines, run in a subdirectory, go to that
#      subdirectory's .gitignore, where .claude/settings.flow.local.json names
#      a file Flow does not read and leaves the top's unignored
#   P6 the deprecated-settings dry run, run in a subdirectory, reports skip
#      for the top's deprecated keys, and the apply upgrades a file the
#      cascade does not read (or fails), so the top keeps its deprecated key
#   P7 flow-migrate-settings.sh with no file named upgrades a file in the
#      working directory instead of the one the cascade reads

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "setup settings: jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi

SETUP_MD="$E2E_PLUGIN_DIR/commands/setup.md"
DETECT='# 1. The project settings file Flow reads'
MKDIR='--project-settings-path) && mkdir -p'
IGNORE_FENCE='for IGNORE in'
MIGRATE_DRY='dry-run — emits MIGRATE'
MIGRATE_APPLY='flow-migrate-settings.sh" --apply'
SUB=packages/app

# _write <path under the repository> <json>
_write() { mkdir -p "$E2E_REPO/${1%/*}"; printf '%s\n' "$2" > "$E2E_REPO/$1"; }

# _in <directory under the repository> <command> [arguments] — run a harness
# runner (e2e_run_fence, e2e_run_bin) with the working directory there. The
# harness runs code in E2E_REPO, so it is pointed at the directory for the one
# call; the artifact names the directory.
_in() {
  local dir="$1" top="$E2E_REPO"; shift
  printf 'working directory: %s\n' "$dir" | _e2e_art
  E2E_REPO="$top/$dir"
  "$@"
  E2E_REPO="$top"
}

# _top_physical — the repository top as git prints it.
_top_physical() { (cd "$E2E_REPO" && pwd -P); }

# _cascade <directory> <expression> — what bin/cascade-resolve.sh reads there.
_cascade() { _in "$1" e2e_run_bin bin/cascade-resolve.sh "$2"; }

_flow_test_begin "/flow:setup detection in a subdirectory finds the settings at the top and reports the one it does not read (P1, P2)"
e2e_new setup-detect-subdir
e2e_describe "tiers.push confirm in .claude/settings.flow.json at the top; journal in $SUB/.claude/settings.flow.json; Phase 1 runs in $SUB with CLAUDE_PROJECT_DIR there"
e2e_repo feature/issue-1-setup
_write .claude/settings.flow.json '{"tiers":{"push":"confirm"}}'
_write "$SUB/.claude/settings.flow.json" '{"tiers":{"push":"journal"}}'
_in "$SUB" e2e_run_fence "CLAUDE_PROJECT_DIR=$E2E_REPO/$SUB" "$SETUP_MD" "$DETECT"
e2e_expect_line "SETTINGS_FILE=$(_top_physical)/.claude/settings.flow.json"
e2e_expect_line "EXISTING_SETTINGS=true"
e2e_expect_line "UNREAD_SETTINGS=./.claude/settings.flow.json"
e2e_expect_equal 1 "$(printf '%s\n' "$E2E_OUT" | grep -c '^UNREAD_SETTINGS=')" "the number of UNREAD_SETTINGS lines"
_cascade "$SUB" '.tiers.push'
e2e_expect_equal confirm "$E2E_OUT" "tiers.push as the cascade reads it in $SUB"

_flow_test_begin "/flow:setup detection reports a settings file in CLAUDE_PROJECT_DIR below the top (P2)"
e2e_new setup-detect-project-dir
e2e_describe "no settings at the top; a .local file in $SUB, which is CLAUDE_PROJECT_DIR; Phase 1 runs at the top"
e2e_repo feature/issue-1-setup
_write "$SUB/.claude/settings.flow.local.json" '{"tiers":{"push":"confirm"}}'
e2e_run_fence "CLAUDE_PROJECT_DIR=$E2E_REPO/$SUB" "$SETUP_MD" "$DETECT"
e2e_expect_line "SETTINGS_FILE=.claude/settings.flow.json"
e2e_expect_line "EXISTING_SETTINGS=false"
e2e_expect_line "UNREAD_SETTINGS=$E2E_REPO/$SUB/.claude/settings.flow.local.json"

_flow_test_begin "/flow:setup detection at the top: the relative path, and nothing reported unread (P3)"
e2e_new setup-detect-top
e2e_describe "both settings files at the top; Phase 1 runs at the top with CLAUDE_PROJECT_DIR the top"
e2e_repo feature/issue-1-setup
_write .claude/settings.flow.json '{"tiers":{"push":"confirm"}}'
_write .claude/settings.flow.local.json '{"tiers":{"push":"journal"}}'
e2e_run_fence "CLAUDE_PROJECT_DIR=$E2E_REPO" "$SETUP_MD" "$DETECT"
e2e_expect_line "SETTINGS_FILE=.claude/settings.flow.json"
e2e_expect_line "EXISTING_SETTINGS=true"
e2e_expect_no_out "UNREAD_SETTINGS="

_flow_test_begin "/flow:setup Phase 2 in a subdirectory creates .claude and the ignore lines at the top (P4, P5)"
e2e_new setup-write-subdir
e2e_describe "no settings anywhere; the Phase 2 mkdir and ignore fences run in $SUB"
e2e_repo feature/issue-1-setup
mkdir -p "$E2E_REPO/$SUB"
_in "$SUB" e2e_run_fence "$SETUP_MD" "$MKDIR"
e2e_expect_equal 0 "$E2E_RC" "the mkdir fence's exit status"
e2e_expect_equal yes "$([ -d "$E2E_REPO/.claude" ] && echo yes || echo no)" ".claude exists at the top"
e2e_expect_equal no "$([ -e "$E2E_REPO/$SUB/.claude" ] && echo yes || echo no)" ".claude exists in $SUB"
_in "$SUB" e2e_run_fence "$SETUP_MD" "$IGNORE_FENCE"
e2e_expect_no_out "GITIGNORE=skipped"
e2e_expect_file_has .gitignore ".claude/settings.flow.local.json"
e2e_expect_file_has .gitignore ".flow/watch/"
e2e_expect_file_has .gitignore ".decisions/auto-log/"
e2e_expect_equal no "$([ -e "$E2E_REPO/$SUB/.gitignore" ] && echo yes || echo no)" "a .gitignore exists in $SUB"

_flow_test_begin "/flow:setup Phase 2 at the top writes the ignore lines there, as before (P3, P5)"
e2e_new setup-write-top
e2e_describe "no settings anywhere; the Phase 2 ignore fence runs at the top"
e2e_repo feature/issue-1-setup
e2e_run_fence "$SETUP_MD" "$IGNORE_FENCE"
e2e_expect_file_has .gitignore ".claude/settings.flow.local.json"
e2e_expect_file_has .gitignore ".claude/*.lock"

_flow_test_begin "/flow:setup settings upgrade in a subdirectory upgrades the file the cascade reads (P6)"
e2e_new setup-migrate-subdir
e2e_describe "requireGoalForStart true in .claude/settings.flow.json at the top; $SUB/.claude/settings.flow.json holds only tiers; the dry run and the apply run in $SUB"
e2e_repo feature/issue-1-setup
_write .claude/settings.flow.json '{"flow":{"goals":{"requireGoalForStart":true}}}'
_write "$SUB/.claude/settings.flow.json" '{"tiers":{"push":"journal"}}'
_in "$SUB" e2e_run_fence "$SETUP_MD" "$MIGRATE_DRY"
e2e_expect_line "MIGRATE=requireGoalForStart->goalCreation"
e2e_expect_line "MIGRATE_TO=goalCreation=always"
# The apply rewrites the file, so it runs once, under the shell Claude Code
# uses: a second shell would find nothing left to upgrade.
E2E_ALL_SHELLS="$E2E_FENCE_SHELLS"
E2E_FENCE_SHELLS="${E2E_FENCE_SHELLS%% *}"
_in "$SUB" e2e_run_fence "$SETUP_MD" "$MIGRATE_APPLY"
E2E_FENCE_SHELLS="$E2E_ALL_SHELLS"
e2e_expect_line "MIGRATE_APPLIED=1"
e2e_expect_equal always "$(jq -r '.flow.goals.goalCreation' "$E2E_REPO/.claude/settings.flow.json")" "goalCreation in the top's file"
e2e_expect_equal '{"tiers":{"push":"journal"}}' "$(jq -c . "$E2E_REPO/$SUB/.claude/settings.flow.json")" "$SUB's file"
_cascade "$SUB" '.flow.goals.goalCreation'
e2e_expect_equal always "$E2E_OUT" "goalCreation as the cascade reads it in $SUB"

_flow_test_begin "flow-migrate-settings.sh with no file named upgrades the top's file from a subdirectory (P7)"
e2e_new migrate-default-subdir
e2e_describe "requireGoalForStart false at the top, requireGoalForStart true in $SUB/.claude/settings.flow.json; the migrator runs in $SUB with no file named"
e2e_repo feature/issue-1-setup
_write .claude/settings.flow.json '{"flow":{"goals":{"requireGoalForStart":false}}}'
_write "$SUB/.claude/settings.flow.json" '{"flow":{"goals":{"requireGoalForStart":true}}}'
_in "$SUB" e2e_run_bin bin/flow-migrate-settings.sh --apply
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_equal off "$(jq -r '.flow.goals.goalCreation' "$E2E_REPO/.claude/settings.flow.json")" "goalCreation in the top's file"
e2e_expect_equal true "$(jq -r '.flow.goals.requireGoalForStart' "$E2E_REPO/$SUB/.claude/settings.flow.json")" "requireGoalForStart left in $SUB's file"
