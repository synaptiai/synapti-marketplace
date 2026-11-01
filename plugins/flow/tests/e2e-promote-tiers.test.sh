# shellcheck shell=bash
# End-to-end: bin/promote-proposal.sh under tiers.push and tiers.prCreate.
#
# The script runs `git push` and `gh pr create` itself. In a Claude Code
# session flow's git and gh wrappers check those calls, and a confirm tier
# refuses any call the tier hook did not ask about, which it never does for a
# call made inside a script. So under confirm the script must stop before that
# step and print the command(s) to run on their own, leaving the branch in a
# state those commands complete.
#
# Each scenario runs the real script in a scratch flow checkout (a repository
# holding plugins/flow/skills, committed, with a bare origin), with the tiers
# set in the checkout's .claude/settings.flow.json. gh answers from fixtures;
# `gh pr create` has no fixture, so a call to it is an unhandled call, except
# in the scenarios that put a recording gh in front of the stub. One artifact
# per scenario is written to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the code:
#   P1 tiers.push confirm: the script pushes anyway (the wrapper would refuse,
#      the run fails half way, and its cleanup deletes the promotion commit)
#   P2 tiers.push confirm: the script stops, but its cleanup deletes the
#      branch or the commit, so the printed push has nothing to push
#   P3 tiers.push confirm: the pull request command is not printed, or points
#      at a body file the cleanup already removed
#   P4 tiers.prCreate confirm: the branch is not pushed (push is journal and
#      has no reason to wait), or gh pr create runs anyway
#   P5 the tiers are read from the directory the caller stands in, not from
#      the flow checkout where git push runs and where the wrapper reads them
#   P6 the printed commands do not work when run as printed: wrong
#      directory, wrong branch, an unquoted path with a space in it
#   P7 with both tiers at journal (the default) the script stops as if one
#      were confirm, or no longer pushes and opens the draft pull request
#   P8 --dry-run says it would push and open a pull request when a confirm
#      tier means it would stop first

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

PROMOTE=bin/promote-proposal.sh
BRANCH=feature/learn-promote-tier-check

_git() { ( _e2e_git_env; cd "$E2E_REPO" && git "$@" ); }

# _flow_checkout [<settings json>] — the scratch repository as a flow checkout
# (plugins/flow/skills present), the settings committed so the tree is clean,
# and a bare origin with main pushed. The repository directory has a space in
# its name, so a printed command that does not quote the path breaks (P6).
_flow_checkout() {
  E2E_REPO="$E2E_DIR/flow checkout"
  mkdir -p "$E2E_REPO/plugins/flow/skills/learned"
  : > "$E2E_REPO/plugins/flow/skills/learned/.keep"
  if [ -n "${1:-}" ]; then
    mkdir -p "$E2E_REPO/.claude"
    printf '%s\n' "$1" > "$E2E_REPO/.claude/settings.flow.json"
    printf 'flow checkout settings: %s\n' "$1" | _e2e_art
  fi
  ( _e2e_git_env; cd "$E2E_REPO" \
      && git init -q -b main \
      && git config user.email e2e@example.invalid \
      && git config user.name e2e \
      && git config commit.gpgsign false \
      && git add -A && git commit -q -m init \
      && git init -q --bare "$E2E_DIR/origin.git" \
      && git remote add origin "$E2E_DIR/origin.git" \
      && git push -q -u origin main ) \
    || _flow_assert_fail "$E2E_NAME: could not create the flow checkout"
  e2e_gh_fixture auth '{}'
  e2e_gh_fixture repo '{"nameWithOwner":"octo/market","defaultBranchRef":{"name":"main"}}'
}

# _proposal — a valid proposal named tier-check, outside the checkout.
_proposal() {
  PROPOSAL_FILE="$E2E_DIR/proposals/tier-check.md"
  mkdir -p "$E2E_DIR/proposals"
  cat > "$PROPOSAL_FILE" <<'PROPOSAL'
---
name: "tier-check"
description: "[flow-learned] Use when checking that promotion follows the tiers."
source-sessions:
  - "2026-10-30 test session"
evidence-count: 2
status: proposal
proposed: "2026-10-30"
---

# Tier check

## Contract

Iron law: do the thing. Applies whenever the thing is not done. Returns the
thing, done. Permitted skips: none.

## Pattern Detected

Something keeps happening.

## Knowledge

Do the thing.

## Evidence

Two sessions.

## Verification

Check the thing.

## Promotion Checklist

- [ ] reviewed
PROPOSAL
}

# _recording_gh — put a gh in front of the scenario's stub that records
# `gh pr create` (its arguments and the body file's text) and hands every other
# call to the stub.
_recording_gh() {
  mv "$E2E_BIN/gh" "$E2E_BIN/gh-stub"
  cat > "$E2E_BIN/gh" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = pr ] && [ "${2:-}" = create ]; then
  printf '%s\n' "$*" >> "${E2E_DIR:?}/pr-create.log"
  body=""
  while [ $# -gt 0 ]; do
    [ "$1" = --body-file ] && body="$2"
    shift
  done
  [ -n "$body" ] && cp "$body" "$E2E_DIR/pr-create.body"
  printf '%s\n' "https://github.com/octo/market/pull/7"
  exit 0
fi
exec "$(dirname "$0")/gh-stub" "$@"
STUB
  chmod +x "$E2E_BIN/gh"
  printf 'gh: gh pr create is recorded; every other call goes to the fixtures\n' | _e2e_art
}

_origin_has_branch() {
  if git --git-dir="$E2E_DIR/origin.git" show-ref --verify --quiet "refs/heads/$BRANCH"; then printf yes; else printf no; fi
}
_current_branch() { _git rev-parse --abbrev-ref HEAD; }
_branch_has_skill() {
  if _git cat-file -e "$BRANCH:plugins/flow/skills/learned/tier-check/SKILL.md" 2>/dev/null; then printf yes; else printf no; fi
}
# _printed_commands — the indented command lines the script printed.
_printed_commands() { printf '%s\n' "$E2E_OUT" | grep -E '^  (git -C |cd )' | sed 's/^  //'; }
# _body_file — the --body-file path named in the printed gh command.
_body_file() {
  _printed_commands | grep 'gh pr create' | sed -n "s/.*--body-file '\(.*\)'$/\1/p"
}
# _drop_body — remove the body file the script left for the printed command;
# it lives in the system temporary directory, outside the scratch root.
_drop_body() {
  local b; b=$(_body_file)
  case "$b" in */flow-promote-body.*) rm -f "$b" ;; esac
}

_flow_test_begin "tiers.push confirm: commit kept on the branch, nothing pushed, both commands printed (P1, P2, P3)"
e2e_new promote-push-confirm
e2e_describe "tiers.push is confirm in the flow checkout; promote a valid proposal"
_flow_checkout '{"tiers":{"push":"confirm"}}'
_proposal
e2e_run_bin FLOW_REPO_ROOT="$E2E_REPO" "$PROMOTE" --proposal "$PROPOSAL_FILE"
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_out "tiers.push is confirm"
e2e_expect_equal no "$(_origin_has_branch)" "whether origin has the promotion branch"
e2e_expect_equal "$BRANCH" "$(_current_branch)" "the checked-out branch"
e2e_expect_equal yes "$(_branch_has_skill)" "whether the branch's commit holds the promoted skill"
e2e_expect_equal 2 "$(_printed_commands | grep -c .)" "the number of printed commands"
e2e_expect_out "  git -C '$E2E_REPO' push -u origin $BRANCH"
e2e_expect_no_out "OK: draft PR created"
BODY=$(_body_file)
if [ -n "$BODY" ] && grep -q 'Auto-generated draft PR' "$BODY" && grep -q 'Removed from the skill, kept for review' "$BODY"; then
  e2e_expect_equal kept kept "the pull request body file"
else
  e2e_expect_equal kept "missing ($BODY)" "the pull request body file"
fi
e2e_expect_clean_edges

_flow_test_begin "tiers.push confirm: the printed commands, run as printed, push the branch and open the draft pull request (P6)"
_recording_gh
# Run from another directory: the printed commands must name the checkout.
( _e2e_git_env; unset -f git; export PATH="$E2E_BIN:$PATH" E2E_DIR E2E_GH
  cd "$E2E_DIR" || exit 1
  _printed_commands | while IFS= read -r c; do bash -c "$c" || exit 1; done ) > "$E2E_DIR/followup.out" 2>&1
FOLLOWUP_RC=$?
e2e_expect_equal 0 "$FOLLOWUP_RC" "the exit status of the printed commands ($(tr '\n' ' ' < "$E2E_DIR/followup.out"))"
e2e_expect_equal yes "$(_origin_has_branch)" "whether origin has the promotion branch after the printed push"
if grep -q -- "--draft" "$E2E_DIR/pr-create.log" 2>/dev/null && grep -q -- "--head $BRANCH" "$E2E_DIR/pr-create.log"; then
  e2e_expect_equal yes yes "whether the printed gh pr create opened a draft from the branch"
else
  e2e_expect_equal yes "no ($(cat "$E2E_DIR/pr-create.log" 2>/dev/null))" "whether the printed gh pr create opened a draft from the branch"
fi
e2e_expect_equal yes "$(grep -q 'Auto-generated draft PR' "$E2E_DIR/pr-create.body" 2>/dev/null && printf yes || printf no)" "whether the pull request got the rendered body"
e2e_expect_clean_edges
_drop_body

_flow_test_begin "tiers.prCreate confirm: the branch is pushed, gh pr create is printed, not run (P4)"
e2e_new promote-prcreate-confirm
e2e_describe "tiers.prCreate is confirm, tiers.push is the default journal"
_flow_checkout '{"tiers":{"prCreate":"confirm"}}'
_proposal
e2e_run_bin FLOW_REPO_ROOT="$E2E_REPO" "$PROMOTE" --proposal "$PROPOSAL_FILE"
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_out "tiers.prCreate is confirm"
e2e_expect_equal yes "$(_origin_has_branch)" "whether origin has the promotion branch"
e2e_expect_equal 1 "$(_printed_commands | grep -c .)" "the number of printed commands"
e2e_expect_equal 1 "$(_printed_commands | grep -c 'gh pr create --draft')" "printed gh pr create commands"
e2e_expect_no_out "OK: draft PR created"
BODY=$(_body_file)
e2e_expect_equal yes "$([ -n "$BODY" ] && grep -q 'Auto-generated draft PR' "$BODY" && printf yes || printf no)" "whether the body file the command names exists"
e2e_expect_clean_edges
_drop_body

_flow_test_begin "the tiers are read in the flow checkout, not where the caller stands (P5)"
e2e_new promote-tiers-from-checkout
e2e_describe "the caller stands in a project whose settings say push autonomous; the flow checkout says push confirm"
_flow_checkout '{"tiers":{"push":"confirm"}}'
_proposal
CHECKOUT="$E2E_REPO"
mkdir -p "$E2E_DIR/project/.claude"
printf '%s\n' '{"tiers":{"push":"autonomous","prCreate":"autonomous"}}' > "$E2E_DIR/project/.claude/settings.flow.json"
( _e2e_git_env; cd "$E2E_DIR/project" && git init -q && git config user.email e2e@example.invalid && git config user.name e2e ) \
  || _flow_assert_fail "$E2E_NAME: could not create the project"
E2E_REPO="$E2E_DIR/project"
e2e_run_bin FLOW_REPO_ROOT="$CHECKOUT" "$PROMOTE" --proposal "$PROPOSAL_FILE"
E2E_REPO="$CHECKOUT"
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_out "tiers.push is confirm"
e2e_expect_equal no "$(_origin_has_branch)" "whether origin has the promotion branch"
e2e_expect_clean_edges
_drop_body

_flow_test_begin "both tiers journal (the default): the script pushes and opens the draft pull request (P7)"
e2e_new promote-journal
e2e_describe "no tier settings; gh pr create is recorded"
_flow_checkout ''
_proposal
_recording_gh
e2e_run_bin FLOW_REPO_ROOT="$E2E_REPO" "$PROMOTE" --proposal "$PROPOSAL_FILE"
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_out "OK: draft PR created"
e2e_expect_equal yes "$(_origin_has_branch)" "whether origin has the promotion branch"
e2e_expect_equal 0 "$(_printed_commands | grep -c .)" "the number of printed commands"
e2e_expect_equal 1 "$(grep -c -- 'pr create --draft' "$E2E_DIR/pr-create.log" 2>/dev/null || printf 0)" "gh pr create calls"
e2e_expect_clean_edges

_flow_test_begin "--dry-run names the stop a confirm tier makes (P8)"
e2e_new promote-dry-run-confirm
e2e_describe "tiers.push is confirm; --dry-run"
_flow_checkout '{"tiers":{"push":"confirm"}}'
_proposal
e2e_run_bin FLOW_REPO_ROOT="$E2E_REPO" "$PROMOTE" --proposal "$PROPOSAL_FILE" --dry-run
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_out "DRY-RUN: tiers.push is confirm"
e2e_expect_no_out "DRY-RUN: would commit + push + open draft PR"
e2e_expect_clean_edges
