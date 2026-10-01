# shellcheck shell=bash
# End-to-end: command blocks that take arguments, and the workflow validation
# block the workflow-validation skill runs.
#
# Each scenario runs the shipped block in a scratch repository with the
# invocation's arguments substituted as Claude Code substitutes them, under zsh
# (when installed) and bash. The artifact for each scenario is written to
# $FLOW_E2E_ARTIFACT_DIR.
#
# Ways each part can be wrong, written down before the scenarios:
#
# start.md pre-flight
#   A1 a word after the issue number (/flow:start 42 the search bug) replaces
#      each failure reason, because Claude Code substitutes $1 with it
#   A2 the issue number is taken from anything but the first word
#
# resume.md unlinked-change check
#   R1 a run id passed as the argument (/flow:resume <run-id>) replaces awk's
#      $0, so the porcelain lines are never read and a dirty tree reads clean
#   R2 changes under .flow/ or .decisions/ are reported as unlinked
#
# explain.md
#   X1 an issue with no auto-log file aborts the block under zsh (a loop over
#      a glob that matches nothing), so Issue Details is never printed
#   X2 several auto-log files are not all listed, or not in name order
#
# references/workflow-validation-shim.md
#   W1 a workflow that still uses completion_gate.requires fails validation
#      instead of being migrated with a WARN
#   W2 a workflow with both requires and documented_requirements fails
#      validation instead of dropping the legacy field with a WARN

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

START_MD="$E2E_PLUGIN_DIR/commands/start.md"
RESUME_MD="$E2E_PLUGIN_DIR/commands/resume.md"
EXPLAIN_MD="$E2E_PLUGIN_DIR/commands/explain.md"
SHIM_MD="$E2E_PLUGIN_DIR/references/workflow-validation-shim.md"

_flow_test_begin "start pre-flight: words after the issue number keep the failure reasons (A1, A2)"
e2e_new start-preflight-words
e2e_describe "run as /flow:start 42 the search bug, in a tree with an uncommitted file and no origin remote"
e2e_repo feature/e2e
printf 'draft\n' > "$E2E_REPO/notes.txt"
e2e_gh_fixture auth '{}'
e2e_gh_fixture issue-42 '{"state":"OPEN"}'
e2e_run_fence "$START_MD" 'PREFLIGHT_STATE=BLOCKED' '42 the search bug'
e2e_expect_line "ISSUE_NUM=42"
e2e_expect_line "PREFLIGHT_STATE=BLOCKED"
e2e_expect_line "PREFLIGHT_FAIL=Uncommitted changes"
e2e_expect_line "PREFLIGHT_FAIL=Cannot reach remote 'origin'"
e2e_expect_no_line "PREFLIGHT_FAIL=the"
e2e_expect_clean_edges

_flow_test_begin "resume: a run-id argument does not hide unlinked changes (R1, R2)"
e2e_new resume-unlinked-with-run-id
e2e_describe "run as /flow:resume 2026-09-27T000000Z-start-issue-42, with a stray notes.txt and flow-owned files"
e2e_repo feature/e2e
printf 'draft\n' > "$E2E_REPO/notes.txt"
mkdir -p "$E2E_REPO/.flow/runs" "$E2E_REPO/.decisions"
printf 'x\n' > "$E2E_REPO/.flow/runs/state.yaml"
printf 'x\n' > "$E2E_REPO/.decisions/issue-42.md"
e2e_run_fence "$RESUME_MD" 'FLOW_RESUME_UNLINKED=1' '2026-09-27T000000Z-start-issue-42'
e2e_expect_line "FLOW_RESUME_UNLINKED=1"
e2e_expect_line "  notes.txt"
e2e_expect_no_out ".flow/"
e2e_expect_no_out ".decisions/"
e2e_expect_clean_edges

# _explain_repo — an issue branch with a journal, and gh answering for the issue.
_explain_repo() {
  e2e_repo feature/issue-42-search
  mkdir -p "$E2E_REPO/.decisions/auto-log"
  printf '# Issue 42 journal\n' > "$E2E_REPO/.decisions/issue-42.md"
  e2e_gh_fixture issue-42 '{"title":"Search bug","body":"Searching fails."}'
  e2e_gh_fixture repo '{"nameWithOwner":"o/r","defaultBranchRef":{"name":"main"}}'
}

_flow_test_begin "explain: an issue with no auto-log still prints its details (X1)"
e2e_new explain-no-autolog
e2e_describe "branch feature/issue-42-search with a journal and an empty auto-log directory"
_explain_repo
e2e_run_fence "$EXPLAIN_MD" '### Issue Details'
e2e_expect_line "AUTOLOG_FILES=0"
e2e_expect_line "### Issue Details"
e2e_expect_line 'TITLE="Search bug"'
e2e_expect_clean_edges

_flow_test_begin "explain: every auto-log file is listed, in name order (X2)"
e2e_new explain-autolog-files
e2e_describe "two monthly auto-log files for issue 42 and one for another issue"
_explain_repo
printf 'august\n' > "$E2E_REPO/.decisions/auto-log/issue-42.2026-08.md"
printf 'september\n' > "$E2E_REPO/.decisions/auto-log/issue-42.2026-09.md"
printf 'other\n' > "$E2E_REPO/.decisions/auto-log/issue-7.2026-09.md"
e2e_run_fence "$EXPLAIN_MD" '### Issue Details'
e2e_expect_line "AUTOLOG_FILES=2"
e2e_expect_equal "issue-42.2026-08.md issue-42.2026-09.md" \
  "$(grep '^##### ' <<<"$E2E_OUT" | sed 's/^##### //' | tr '\n' ' ' | sed 's/ $//')" "the auto-log files listed"
e2e_expect_no_out "other"
e2e_expect_clean_edges

# _legacy_workflow <both> — a copy of a shipped workflow whose completion gate
# uses the legacy field name; with "both", it carries both names.
_legacy_workflow() {
  python3 - "$E2E_PLUGIN_DIR/workflows/address-pr.workflow.yaml" "$E2E_REPO/legacy.workflow.yaml" "$1" <<'PY' ||
import sys, yaml
src, dst, both = sys.argv[1:4]
with open(src, encoding="utf-8") as f:
    wf = yaml.safe_load(f)
gate = wf["completion_gate"]
reqs = gate["documented_requirements"]
gate["requires"] = reqs
if both != "both":
    del gate["documented_requirements"]
with open(dst, "w", encoding="utf-8") as f:
    yaml.safe_dump(wf, f, sort_keys=False)
PY
  _flow_assert_fail "$E2E_NAME: could not write the legacy workflow"
}

if ! python3 -c 'import jsonschema' >/dev/null 2>&1; then
  _flow_test_begin "workflow shim (W1, W2)"
  _flow_assert_pass "SKIP: python3 has no jsonschema; the shim block needs it"
else
  _flow_test_begin "workflow shim: a legacy completion_gate.requires is migrated with a WARN (W1)"
  e2e_new workflow-shim-legacy
  e2e_describe "address-pr.workflow.yaml with documented_requirements renamed to the legacy requires"
  e2e_repo feature/e2e
  _legacy_workflow legacy
  export WORKFLOW_PATH=legacy.workflow.yaml SCHEMA_PATH="$E2E_PLUGIN_DIR/schemas/v1/workflow.schema.json"
  e2e_run_fence "$SHIM_MD" 'Pre-validation migration'
  e2e_expect_line "schema_valid: true"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_err "completion_gate.requires is deprecated"
  e2e_expect_clean_edges

  _flow_test_begin "workflow shim: both field names present drops the legacy one with a WARN (W2)"
  e2e_new workflow-shim-both
  e2e_describe "address-pr.workflow.yaml carrying both requires and documented_requirements"
  e2e_repo feature/e2e
  _legacy_workflow both
  e2e_run_fence "$SHIM_MD" 'Pre-validation migration'
  e2e_expect_line "schema_valid: true"
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_err "dropping legacy field"
  e2e_expect_clean_edges
  unset WORKFLOW_PATH SCHEMA_PATH
fi

# A repository's .claude/settings.json can set HOME. The commands find the
# user's own files under the home cascade-resolve.sh --user-home gives, so a
# HOME the repository sets does not choose them. A fake id names a user the
# user database does not have: the home Flow falls back to is /nonexistent,
# and nothing here reads or writes the real home.
_home_from_repo() {  # _home_from_repo: fake id, and the repository setting HOME
  mkdir -p "$E2E_DIR/idbin" "$E2E_REPO/.claude"
  printf '#!/bin/sh\nprintf "%%s\\n" flow_no_such_user_e2e\n' > "$E2E_DIR/idbin/id"
  chmod +x "$E2E_DIR/idbin/id"
  jq -nc --arg v "$E2E_HOME" '{env:{HOME:$v}}' > "$E2E_REPO/.claude/settings.json"
}

_flow_test_begin "/flow:status: the learn-pending flag is read from the user's home, not from a HOME the repository sets"
e2e_new status-pending-home-from-repo
e2e_describe "a learn-pending flag dated 2026-01-01 in HOME/.claude; the repository's .claude/settings.json sets HOME to that directory. The Decision Journal fence reports LEARNING_PENDING=none. Control: with the settings file gone, the same HOME is used and the flag is reported"
e2e_repo feature/e2e
mkdir -p "$E2E_HOME/.claude"
printf '2026-01-01\n' > "$E2E_HOME/.claude/flow-learn-pending"
_home_from_repo
e2e_run_fence "HOME=$E2E_HOME" "PATH=$E2E_DIR/idbin:$PATH" "$E2E_PLUGIN_DIR/commands/status.md" 'LEARNING_PENDING=none'
e2e_expect_line "LEARNING_PENDING=none"
rm "$E2E_REPO/.claude/settings.json"
e2e_run_fence "HOME=$E2E_HOME" "PATH=$E2E_DIR/idbin:$PATH" "$E2E_PLUGIN_DIR/commands/status.md" 'LEARNING_PENDING=none'
e2e_expect_line "LEARNING_PENDING=2026-01-01"
e2e_expect_clean_edges

_flow_test_begin "/flow:learn: the default proposal directory is under the user's home, not under a HOME the repository sets"
e2e_new learn-proposals-home-from-repo
e2e_describe "the repository's .claude/settings.json sets HOME; the Phase 1 fence prints PROPOSAL_DIR under the home Flow falls back to. Control: with the settings file gone, under that HOME"
e2e_repo feature/e2e
_home_from_repo
e2e_run_fence "HOME=$E2E_HOME" "PATH=$E2E_DIR/idbin:$PATH" "$E2E_PLUGIN_DIR/commands/learn.md" 'PROPOSAL_DIR=$PROPOSAL_DIR'
e2e_expect_line "PROPOSAL_DIR=/nonexistent/.claude/flow-proposals"
rm "$E2E_REPO/.claude/settings.json"
e2e_run_fence "HOME=$E2E_HOME" "PATH=$E2E_DIR/idbin:$PATH" "$E2E_PLUGIN_DIR/commands/learn.md" 'PROPOSAL_DIR=$PROPOSAL_DIR'
e2e_expect_line "PROPOSAL_DIR=$E2E_HOME/.claude/flow-proposals"
e2e_expect_clean_edges
