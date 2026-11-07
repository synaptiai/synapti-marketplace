# shellcheck shell=bash
# End-to-end: the review findings ledger and the FlowGoal gate, as /flow:merge
# and /flow:status run them.
#
# Each scenario runs the shipped `!` block from commands/merge.md or
# commands/status.md in a scratch repository, with gh answering from fixtures.
# The artifact for each scenario is written to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways each part can be wrong, written down before the scenarios — each
# scenario below names the one it catches.
#
# merge.md finding-ledger gate
#   M1 a finding with no RESOLVED entry lets the merge through
#   M2 findings listed with spaces after the commas, `RESOLVED:[F1, F2]`, do
#      not count as resolved, so a clean PR is blocked
#   M3 a non-empty ESCALATED array lets the merge through
#   M4 gh failing (network, auth) reads as "no findings" and opens the gate
#   M5 a PR argument that is not all digits reaches the API calls
#   M6 a resolution marker from an untrusted author resolves findings
#   M7 a later review from an untrusted author, with an empty findings list,
#      replaces the trusted review and so clears its findings
#   M8 an extra word after the PR number (/flow:merge 7 --now) replaces the
#      block reason: Claude Code substitutes $1 with the second argument
#
# merge.md FlowGoal gate
#   G1 an achieved goal on this branch is reported as "no goal" (the helper
#      is asked for active goals only)
#   G2 an active, unfinished goal on this branch lets the merge through
#   G3 an active goal on ANOTHER branch blocks this merge (the lookup is not
#      limited to the current branch)
#   G4 two active goals on this branch pick one silently instead of blocking
#   G5 flow.goals.enabled=false still gates
#   G6 a goal on this branch that is draft, waiting_for_user, waiting_for_ci,
#      blocked, failed or cancelled reads as "no goal" and lets the merge
#      through (#335), or blocks without naming the goal and its status
#   G7 a failed goal beside an achieved one on this branch is passed over for
#      the achieved one
#   G8 the gate judges the checked-out branch's goal, not the pull request's
#      (#309): another branch's active goal blocks a pull request that has
#      none, and a pull request whose own goal is not achieved passes when
#      the checked-out branch has no goal
#   G9 when the pull request's head cannot be read (gh fails, or the head
#      commit is neither here nor fetchable), the gate reads "no goal" and
#      passes
#   G10 a goals directory committed as a symlink in the pull request's head
#      is followed
#   G11 a failed or cancelled goal's block reason says to finish the work
#      under a new goal and stops there, but the failed goal still decides
#      over the new achieved one while its file is on the branch (#335), so
#      the remedy it gives never unblocks the merge
#   G12 the gate reads the working tree because a local branch has the pull
#      request's head branch name, though it is not at the pull request's
#      head commit: a local branch that is ahead of or diverged from the head
#      holds an achieved goal the merge does not land, and a fork's pull
#      request whose branch shares the checked-out branch's name is judged by
#      this clone's working tree; or, the other way, a branch checked out at
#      the head commit with a goal evaluated but not yet committed is no
#      longer read from the working tree
#
# status.md findings ledger
#   S1 RESOLVED does not win over ESCALATED for the same finding
#   S2 a row with a malformed priority is counted instead of warned about
#   S3 a later review from an untrusted author replaces the trusted one
#   S4 a PR that is neither mine nor assigned to me is counted
#   S5 DISPUTED is not reported as its own state
#   S6 gh failing reads as "no open PRs" instead of "unavailable"
#   S7 a finding id outside [A-Za-z][A-Za-z0-9_-]* (a `*`, or one with a `.`)
#      is counted instead of rejected; such ids are how one dismissal written
#      with a comma would mark two findings dismissed
#   S8 with two or more open PRs, the PR numbers reach the API as one string
#      under zsh, the shell Claude Code runs the block with on macOS

# Only tests/run.sh runs this file: it sets REPO_ROOT and loads assert.sh. Run
# any other way, the file stops here with a non-zero exit, because `return`
# alone does not stop a script that is executed rather than sourced, and the
# scenarios below would then run git in the current directory.
{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

MERGE_MD="$E2E_PLUGIN_DIR/commands/merge.md"
STATUS_MD="$E2E_PLUGIN_DIR/commands/status.md"
LEDGER_FENCE='### Finding-Ledger Gate'
GOAL_FENCE='### FlowGoal Gate'
STATUS_FENCE='### Findings Ledger'

REVIEW_F1_F2='<!-- FLOW_REVIEW_CYCLE:1 FINDINGS:[F1|P1|logic|src/a.sh:3|open,F2|P2|style|src/b.sh:9|open] -->'

# A PR with review findings, run through the merge ledger gate.
_ledger_case() {
  e2e_new "$1"; e2e_describe "$2"; e2e_repo feature/e2e
  e2e_gh_fixture repo '{"nameWithOwner":"o/r"}'
  e2e_gh_fixture reviews-7 "$(jq -nc --arg b "$REVIEW_F1_F2" '[{author_association:"OWNER",body:$b}]')"
}
_resolution() { jq -nc --arg a "$1" --arg b "$2" '[{author_association:$a,body:$b}]'; }

# --- merge.md finding-ledger gate --------------------------------------------

_flow_test_begin "merge ledger gate: a finding without a RESOLVED entry blocks (M1)"
_ledger_case merge-ledger-unresolved "F1 resolved, F2 not: the merge must be blocked and name F2"
e2e_gh_fixture comments-7 "$(_resolution OWNER '<!-- FLOW_RESOLUTION_CYCLE:1 RESOLVED:[F1] ESCALATED:[] DISPUTED:[] -->')"
e2e_run_fence "$MERGE_MD" "$LEDGER_FENCE" 7
e2e_expect_line "LEDGER_GATE_STATE=blocked"
e2e_expect_line "FINDING_LEDGER_BLOCK: Unresolved findings: F2"
e2e_expect_clean_edges

_flow_test_begin "merge ledger gate: every finding resolved, written with spaces, passes (M2)"
_ledger_case merge-ledger-resolved "F1 and F2 resolved as 'RESOLVED:[F1, F2]': the merge proceeds"
e2e_gh_fixture comments-7 "$(_resolution OWNER '<!-- FLOW_RESOLUTION_CYCLE:1 RESOLVED:[F1, F2] ESCALATED:[] DISPUTED:[] -->')"
e2e_run_fence "$MERGE_MD" "$LEDGER_FENCE" 7
e2e_expect_line "LEDGER_GATE_STATE=ok"
e2e_expect_no_line "LEDGER_GATE_STATE=blocked"
e2e_expect_clean_edges

_flow_test_begin "merge ledger gate: an escalated finding blocks (M3)"
_ledger_case merge-ledger-escalated "both resolved but F2 also escalated: the merge must be blocked"
e2e_gh_fixture comments-7 "$(_resolution OWNER '<!-- FLOW_RESOLUTION_CYCLE:1 RESOLVED:[F1,F2] ESCALATED:[F2] DISPUTED:[] -->')"
e2e_run_fence "$MERGE_MD" "$LEDGER_FENCE" 7
e2e_expect_line "LEDGER_GATE_STATE=blocked"
e2e_expect_line "FINDING_LEDGER_BLOCK: ESCALATED array is non-empty: [F2]"
e2e_expect_clean_edges

_flow_test_begin "merge ledger gate: gh failing blocks rather than passing (M4)"
_ledger_case merge-ledger-gh-down "the reviews call fails with HTTP 502, so no finding is visible: the gate must still block"
e2e_gh_fixture comments-7 "$(_resolution OWNER '<!-- FLOW_RESOLUTION_CYCLE:1 RESOLVED:[] ESCALATED:[] DISPUTED:[] -->')"
e2e_gh_fail reviews-7
e2e_run_fence "$MERGE_MD" "$LEDGER_FENCE" 7
e2e_expect_line "LEDGER_GATE_STATE=blocked"
e2e_expect_out "gh API unavailable"
e2e_expect_clean_edges

_flow_test_begin "merge ledger gate: a non-numeric PR argument blocks before any API call (M5)"
_ledger_case merge-ledger-bad-arg "the argument is '7;id': the gate must refuse it and make no API call"
e2e_run_fence "$MERGE_MD" "$LEDGER_FENCE" '7;id'
e2e_expect_line "LEDGER_GATE_STATE=blocked"
e2e_expect_line "FINDING_LEDGER_BLOCK: PR number required (all-digit)"
e2e_expect_clean_edges

_flow_test_begin "merge ledger gate: a resolution from an untrusted author does not count (M6)"
_ledger_case merge-ledger-forged "RESOLVED:[F1,F2] posted by a CONTRIBUTOR: the forged marker must block, not resolve"
e2e_gh_fixture comments-7 "$(_resolution CONTRIBUTOR '<!-- FLOW_RESOLUTION_CYCLE:1 RESOLVED:[F1,F2] ESCALATED:[] DISPUTED:[] -->')"
e2e_run_fence "$MERGE_MD" "$LEDGER_FENCE" 7
e2e_expect_line "LEDGER_GATE_STATE=blocked"
e2e_expect_out "FLOW_RESOLUTION_CYCLE marker(s) found but none from trusted authors"
e2e_expect_clean_edges

_flow_test_begin "merge ledger gate: a later empty review from an untrusted author does not clear findings (M7)"
_ledger_case merge-ledger-forged-review "trusted review F1,F2; a later CONTRIBUTOR review lists no findings: the gate must still block"
e2e_gh_fixture reviews-7 "$(jq -nc \
  --arg t '<!-- FLOW_REVIEW_CYCLE:1 FINDINGS:[F1|P1|logic|a:1|open,F2|P2|x|b:2|open] -->' \
  --arg u '<!-- FLOW_REVIEW_CYCLE:9 FINDINGS:[] -->' \
  '[{author_association:"OWNER",body:$t},{author_association:"CONTRIBUTOR",body:$u}]')"
e2e_gh_fixture comments-7 "$(_resolution OWNER '<!-- FLOW_RESOLUTION_CYCLE:1 RESOLVED:[] ESCALATED:[] DISPUTED:[] -->')"
e2e_run_fence "$MERGE_MD" "$LEDGER_FENCE" 7
e2e_expect_line "LEDGER_GATE_STATE=blocked"
e2e_expect_out "Unresolved findings: F1"
e2e_expect_clean_edges

_flow_test_begin "merge ledger gate: extra words after the PR number keep the block reason (M8)"
_ledger_case merge-ledger-extra-args "run as /flow:merge 7 --now with F2 unresolved: the reason must still name F2"
e2e_gh_fixture comments-7 "$(_resolution OWNER '<!-- FLOW_RESOLUTION_CYCLE:1 RESOLVED:[F1] ESCALATED:[] DISPUTED:[] -->')"
e2e_run_fence "$MERGE_MD" "$LEDGER_FENCE" '7 --now'
e2e_expect_line "LEDGER_GATE_STATE=blocked"
e2e_expect_line "FINDING_LEDGER_BLOCK: Unresolved findings: F2"
e2e_expect_no_line "FINDING_LEDGER_BLOCK: --now"
e2e_expect_clean_edges

# --- merge.md FlowGoal gate --------------------------------------------------

# The pull request is #7 and its head is the checked-out branch feature/e2e at
# the commit checked out, unless a scenario says otherwise.
_goal_case() {
  e2e_new "$1"; e2e_describe "$2"; e2e_repo feature/e2e
  e2e_gh_fixture repo '{"nameWithOwner":"o/r"}'
  _pr_head feature/e2e "$(_head_oid)"
}
_pr_head() { e2e_gh_fixture pr-head-7 "$(jq -nc --arg b "$1" --arg o "$2" '{headRefName:$b,headRefOid:$o}')"; }
# _head_oid — the commit checked out in the scratch repository.
_head_oid() { (_e2e_git_env; cd "$E2E_REPO" && git rev-parse HEAD); }
# _commit_all <message> — commit everything in the scratch repository.
_commit_all() {
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    git add -A
    git commit -q -m "$1"
  ) || _flow_assert_fail "$E2E_NAME: could not commit: $1"
}
# _pr_branch <branch> [goal-id status] — commit a branch in the scratch
# repository, carrying one goal when given, and go back to feature/e2e. Prints
# nothing; the head commit is in $E2E_DIR/pr-oid.
_pr_branch() {
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    git checkout -q -b "$1"
  ) || _flow_assert_fail "$E2E_NAME: could not create branch $1"
  if [ -n "${2:-}" ]; then e2e_goal "$2" "$1" "$3" false; fi
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    printf 'pr\n' > pr.txt
    git add -A
    git commit -q -m "pr head"
    git rev-parse HEAD > "$E2E_DIR/pr-oid"
    git checkout -q feature/e2e
  ) || _flow_assert_fail "$E2E_NAME: could not commit branch $1"
  _pr_head "$1" "$(cat "$E2E_DIR/pr-oid")"
}

_flow_test_begin "merge goal gate: an achieved goal on this branch passes and is named (G1)"
_goal_case merge-goal-achieved "achieved goal on this branch, plus an active goal on another branch"
e2e_goal g-mine feature/e2e achieved true
e2e_goal g-other feature/other active false
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE" 7
e2e_expect_line "FLOW_GOAL_GATE_STATE=ok"
e2e_expect_line "FLOW_GOAL_ID=g-mine"
e2e_expect_line "FLOW_GOAL_LIFECYCLE=achieved"
e2e_expect_clean_edges

_flow_test_begin "merge goal gate: an unfinished goal on this branch blocks (G2)"
_goal_case merge-goal-active "active goal on this branch that has not reached achieved"
e2e_goal g-mine feature/e2e active false
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE" 7
e2e_expect_line "FLOW_GOAL_GATE_STATE=blocked"
e2e_expect_out "FlowGoal g-mine lifecycle is 'active'"
e2e_expect_clean_edges

_flow_test_begin "merge goal gate: an active goal on another branch does not block this one (G3)"
_goal_case merge-goal-other-branch "the only active goal belongs to feature/other"
e2e_goal g-other feature/other active false
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE" 7
e2e_expect_line "FLOW_GOAL_GATE_STATE=ok"
e2e_expect_line "FLOW_GOAL_GATE_NOTE=no FlowGoal for feature/e2e — gate not applicable"
e2e_expect_no_line "FLOW_GOAL_ID=g-other"
e2e_expect_clean_edges

_flow_test_begin "merge goal gate: two active goals on this branch block (G4)"
_goal_case merge-goal-two-active "two active goals both own this branch"
e2e_goal g-one feature/e2e active false
e2e_goal g-two feature/e2e active false
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE" 7
e2e_expect_line "FLOW_GOAL_GATE_STATE=blocked"
e2e_expect_out "multiple active FlowGoals on feature/e2e"
e2e_expect_clean_edges

_flow_test_begin "merge goal gate: goals disabled in project settings turns the gate off (G5)"
_goal_case merge-goal-disabled "flow.goals.enabled=false, with an unfinished goal on this branch"
e2e_goal g-mine feature/e2e active false
mkdir -p "$E2E_REPO/.claude"
printf '%s\n' '{"flow":{"goals":{"enabled":false}}}' > "$E2E_REPO/.claude/settings.flow.json"
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE" 7
e2e_expect_line "FLOW_GOAL_GATE_STATE=disabled"
e2e_expect_clean_edges

# G6: every status other than active and achieved, as the #335 table lists
# them. Each blocks, and the reason names the goal, its status and what to do.
_goal_status_case() {
  local status=$1 expect=$2
  _flow_test_begin "merge goal gate: a $status goal on this branch blocks (G6)"
  _goal_case "merge-goal-$status" "the goal owning this branch is $status: the merge must be blocked and the reason name it"
  e2e_goal g-mine feature/e2e "$status" false
  e2e_goal g-other feature/other active false
  e2e_run_fence "$MERGE_MD" "$GOAL_FENCE" 7
  e2e_expect_line "FLOW_GOAL_GATE_STATE=blocked"
  e2e_expect_line "FLOW_GOAL_ID=g-mine"
  e2e_expect_line "FLOW_GOAL_LIFECYCLE=$status"
  e2e_expect_out "FlowGoal g-mine lifecycle is '$status' — $expect"
  e2e_expect_no_line "FLOW_GOAL_GATE_NOTE=no FlowGoal for feature/e2e — gate not applicable"
  e2e_expect_clean_edges
}
_goal_status_case failed "a failed goal does not merge"
_goal_status_case cancelled "a cancelled goal does not merge"
_goal_status_case waiting_for_user "it waits for a person's answer"
_goal_status_case waiting_for_ci "it waits for CI"
_goal_status_case blocked "it is blocked"
_goal_status_case draft "it is a draft that was never activated"

_flow_test_begin "merge goal gate: a failed goal is not hidden by an achieved one on the same branch (G7)"
_goal_case merge-goal-failed-and-achieved "this branch carries an achieved goal and a failed one: the failed one decides"
e2e_goal g-done feature/e2e achieved true
e2e_goal g-failed feature/e2e failed false
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE" 7
e2e_expect_line "FLOW_GOAL_GATE_STATE=blocked"
e2e_expect_line "FLOW_GOAL_ID=g-failed"
e2e_expect_clean_edges

# G11: the remedy the reason gives must be one that unblocks the merge.
_retry_case() {
  local status=$1
  _flow_test_begin "merge goal gate: a $status goal's reason says to remove its file, which then unblocks the retry (G11)"
  _goal_case "merge-goal-$status-retry" "issue-5 is $status and issue-5-retry achieved on this branch: the $status one decides, and its reason must say the file has to leave the branch"
  e2e_goal issue-5 feature/e2e "$status" false
  e2e_goal issue-5-retry feature/e2e achieved true
  e2e_run_fence "$MERGE_MD" "$GOAL_FENCE" 7
  e2e_expect_line "FLOW_GOAL_GATE_STATE=blocked"
  e2e_expect_line "FLOW_GOAL_ID=issue-5"
  e2e_expect_out "FlowGoal issue-5 lifecycle is '$status' — a $status goal does not merge, and the merge stays blocked while .flow/goals/issue-5.goal.yaml is on the branch: if this PR still ships the work, finish it under a new goal with the same id (/flow:goal create replaces .flow/goals/issue-5.goal.yaml), or under another id and remove .flow/goals/issue-5.goal.yaml from the branch; if it does not, remove .flow/goals/issue-5.goal.yaml from the branch"
  e2e_expect_clean_edges
  # The remedy, followed: the file leaves the branch and the retry decides.
  rm "$E2E_REPO/.flow/goals/issue-5.goal.yaml"
  e2e_run_fence "$MERGE_MD" "$GOAL_FENCE" 7
  e2e_expect_line "FLOW_GOAL_GATE_STATE=ok"
  e2e_expect_line "FLOW_GOAL_ID=issue-5-retry"
  e2e_expect_clean_edges
}
_retry_case failed
_retry_case cancelled

_flow_test_begin "merge goal gate: read from the pull request's head, a failed goal's reason names the file to remove, not the commit (G11)"
_goal_case merge-goal-pr-failed "checked out: feature/e2e with no goal; PR #7's head feature/pr carries a failed goal"
_pr_branch feature/pr g-pr failed
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE" 7
e2e_expect_line "FLOW_GOAL_GATE_STATE=blocked"
e2e_expect_out "the merge stays blocked while .flow/goals/g-pr.goal.yaml is on the branch"
e2e_expect_no_out "$(cat "$E2E_DIR/pr-oid"):"
e2e_expect_clean_edges

_flow_test_begin "merge goal gate: a waiting goal's reason is shown (G6)"
_goal_case merge-goal-waiting-reason "a waiting_for_user goal whose last evaluation says what it waits for"
e2e_goal g-mine feature/e2e waiting_for_user false
python3 - "$E2E_REPO/.flow/goals/g-mine.goal.yaml" <<'PY'
import sys, yaml
p = sys.argv[1]
g = yaml.safe_load(open(p, encoding="utf-8"))
g["lifecycle"]["last_evaluation"] = {"result": "needs_human_review", "reason": "which API version to target"}
yaml.safe_dump(g, open(p, "w", encoding="utf-8"), sort_keys=False)
PY
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE" 7
e2e_expect_line "FLOW_GOAL_GATE_STATE=blocked"
e2e_expect_out "(last evaluation: which API version to target)"
e2e_expect_clean_edges

_flow_test_begin "merge goal gate: another branch's goal does not block a pull request without one (G8)"
_goal_case merge-goal-pr-has-none "checked out: feature/e2e with an active goal; PR #7's head feature/pr carries no goal"
_pr_branch feature/pr
e2e_goal g-checked-out feature/e2e active false
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE" 7
e2e_expect_line "FLOW_GOAL_GATE_STATE=ok"
e2e_expect_line "FLOW_GOAL_GATE_NOTE=no FlowGoal for feature/pr — gate not applicable"
e2e_expect_out "FLOW_GOAL_SOURCE=commit "
e2e_expect_no_line "FLOW_GOAL_ID=g-checked-out"
e2e_expect_clean_edges

_flow_test_begin "merge goal gate: the pull request's own unfinished goal blocks with nothing checked out of it (G8)"
_goal_case merge-goal-pr-own-active "checked out: feature/e2e with no goal; PR #7's head feature/pr carries an active goal"
_pr_branch feature/pr g-pr active
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE" 7
e2e_expect_line "FLOW_GOAL_GATE_STATE=blocked"
e2e_expect_line "FLOW_GOAL_ID=g-pr"
e2e_expect_out "FlowGoal g-pr lifecycle is 'active'"
e2e_expect_clean_edges

_flow_test_begin "merge goal gate: the pull request's achieved goal passes whatever is checked out (G8)"
_goal_case merge-goal-pr-own-achieved "checked out: feature/e2e with an active goal; PR #7's head feature/pr carries an achieved goal"
_pr_branch feature/pr g-pr achieved
e2e_goal g-checked-out feature/e2e active false
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE" 7
e2e_expect_line "FLOW_GOAL_GATE_STATE=ok"
e2e_expect_line "FLOW_GOAL_ID=g-pr"
e2e_expect_line "FLOW_GOAL_LIFECYCLE=achieved"
e2e_expect_clean_edges

_flow_test_begin "merge goal gate: a pull request head gh cannot read blocks (G9)"
_goal_case merge-goal-pr-gh-down "gh pr view fails for PR #7, and the checked-out branch has no goal"
e2e_gh_fail pr-head-7
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE" 7
e2e_expect_line "FLOW_GOAL_GATE_STATE=blocked"
e2e_expect_out "could not read pull request #7's head branch and commit"
e2e_expect_clean_edges

_flow_test_begin "merge goal gate: a pull request head that is not here and cannot be fetched blocks (G9)"
_goal_case merge-goal-pr-head-missing "PR #7's head is feature/pr at a commit this clone lacks, and there is no origin to fetch it from"
_pr_head feature/pr 0123456789abcdef0123456789abcdef01234567
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE" 7
e2e_expect_line "FLOW_GOAL_GATE_STATE=blocked"
e2e_expect_out "is not in this clone and could not be fetched from origin"
e2e_expect_clean_edges

_flow_test_begin "merge goal gate: a goals directory committed as a symlink in the pull request's head is refused (G10)"
_goal_case merge-goal-pr-symlink "PR #7's head commits .flow as a symlink"
(
  _e2e_git_env
  cd "$E2E_REPO" || exit 1
  git checkout -q -b feature/pr
  ln -s /tmp .flow
  git add .flow
  git commit -q -m "symlinked runtime dir"
  git rev-parse HEAD > "$E2E_DIR/pr-oid"
  git checkout -q feature/e2e
) || _flow_assert_fail "merge-goal-pr-symlink: could not commit the symlink"
_pr_head feature/pr "$(cat "$E2E_DIR/pr-oid")"
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE" 7
e2e_expect_line "FLOW_GOAL_GATE_STATE=blocked"
e2e_expect_out ".flow is a symlink in"
e2e_expect_clean_edges

_flow_test_begin "merge goal gate: a local branch ahead of the pull request's head is not read in its place (G12)"
_goal_case merge-goal-local-ahead "PR #7's head is feature/e2e at a commit whose goal g-mine is active; the checked-out feature/e2e has a later local commit that makes g-mine achieved"
e2e_goal g-mine feature/e2e active false
_commit_all "goal active"
_pr_head feature/e2e "$(_head_oid)"
e2e_goal g-mine feature/e2e achieved true
_commit_all "goal achieved, not pushed"
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE" 7
e2e_expect_line "FLOW_GOAL_GATE_STATE=blocked"
e2e_expect_out "FLOW_GOAL_SOURCE=commit "
e2e_expect_line "FLOW_GOAL_ID=g-mine"
e2e_expect_line "FLOW_GOAL_LIFECYCLE=active"
e2e_expect_no_line "FLOW_GOAL_SOURCE=working tree of feature/e2e"
e2e_expect_clean_edges

_flow_test_begin "merge goal gate: a fork's pull request whose branch shares the checked-out branch's name is read from its head commit (G12)"
_goal_case merge-goal-fork-same-name "checked out: feature/e2e with no goal; PR #7 comes from a fork whose head branch is also named feature/e2e, at a commit (made here on fork-head) carrying an active goal for feature/e2e"
(
  _e2e_git_env
  cd "$E2E_REPO" || exit 1
  git checkout -q -b fork-head
) || _flow_assert_fail "merge-goal-fork-same-name: could not create fork-head"
e2e_goal g-fork feature/e2e active false
_commit_all "fork head"
_pr_head feature/e2e "$(_head_oid)"
(
  _e2e_git_env
  cd "$E2E_REPO" || exit 1
  git checkout -q feature/e2e
) || _flow_assert_fail "merge-goal-fork-same-name: could not go back to feature/e2e"
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE" 7
e2e_expect_line "FLOW_GOAL_GATE_STATE=blocked"
e2e_expect_out "FLOW_GOAL_SOURCE=commit "
e2e_expect_line "FLOW_GOAL_ID=g-fork"
e2e_expect_no_line "FLOW_GOAL_GATE_NOTE=no FlowGoal for feature/e2e — gate not applicable"
e2e_expect_clean_edges

_flow_test_begin "merge goal gate: checked out at the pull request's head, a goal evaluated but not committed is read from the working tree (G12)"
_goal_case merge-goal-head-uncommitted "PR #7's head is the checked-out feature/e2e commit, whose goal g-mine is active; the working tree holds g-mine achieved, not yet committed"
e2e_goal g-mine feature/e2e active false
_commit_all "goal active"
_pr_head feature/e2e "$(_head_oid)"
e2e_goal g-mine feature/e2e achieved true
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE" 7
e2e_expect_line "FLOW_GOAL_GATE_STATE=ok"
e2e_expect_line "FLOW_GOAL_SOURCE=working tree of feature/e2e"
e2e_expect_line "FLOW_GOAL_LIFECYCLE=achieved"
e2e_expect_clean_edges

# --- status.md findings ledger -----------------------------------------------

_flow_test_begin "status ledger: tallies my open PRs' findings by priority and state (S1-S5, S7, S8)"
e2e_new status-ledger-tally
e2e_describe "PR 7 (mine) and PR 8 (assigned to me) carry findings; PR 9 belongs to someone else"
e2e_repo feature/e2e
e2e_gh_fixture user '{"login":"me"}'
e2e_gh_fixture repo '{"nameWithOwner":"o/r"}'
e2e_gh_fixture prs '[{"number":7,"author":{"login":"me"},"assignees":[]},{"number":8,"author":{"login":"ann"},"assignees":[{"login":"me"}]},{"number":9,"author":{"login":"bob"},"assignees":[]}]'
# PR 7: F1 resolved AND escalated (resolved wins), F2 escalated, F3 open,
# F4 carries a priority outside P1-P3; `*` and `F.5` are ids outside the
# allowed shape.
e2e_gh_fixture reviews-7 "$(jq -nc --arg b '<!-- FLOW_REVIEW_CYCLE:2 FINDINGS:[F1|P1|logic|a:1|open,F2|P2|logic|a:2|open,F3|P3|style|a:3|open,F4|PX|style|a:4|open,*|P1|logic|a:5|open,F.5|P1|logic|a:6|open] -->' '[{author_association:"OWNER",body:$b}]')"
e2e_gh_fixture comments-7 "$(_resolution OWNER '<!-- FLOW_RESOLUTION_CYCLE:2 RESOLVED:[F1] ESCALATED:[F1, F2] DISPUTED:[] -->')"
# PR 8: a trusted review with F5 and F6, then a LATER review from an untrusted
# author claiming a P1 finding F9. F5 is disputed.
e2e_gh_fixture reviews-8 "$(jq -nc \
  --arg t '<!-- FLOW_REVIEW_CYCLE:1 FINDINGS:[F5|P2|logic|b:1|open,F6|P1|logic|b:2|open] -->' \
  --arg u '<!-- FLOW_REVIEW_CYCLE:9 FINDINGS:[F9|P1|logic|b:9|open] -->' \
  '[{author_association:"MEMBER",body:$t},{author_association:"CONTRIBUTOR",body:$u}]')"
e2e_gh_fixture comments-8 "$(_resolution MEMBER '<!-- FLOW_RESOLUTION_CYCLE:1 RESOLVED:[] ESCALATED:[] DISPUTED:[F5] -->')"
e2e_run_fence "$STATUS_MD" "$STATUS_FENCE"
e2e_expect_line "LEDGER_STATE=findings"
e2e_expect_line "TALLY_P1_in_fix_forward=1"
e2e_expect_line "TALLY_P2_escalated=1"
e2e_expect_line "TALLY_P2_disputed=1"
e2e_expect_line "TALLY_P3_in_fix_forward=1"
e2e_expect_no_line "TALLY_P1_escalated=1"
e2e_expect_err "PR#7 finding 'F4' has malformed priority 'PX'"
e2e_expect_err "PR#7 finding '*' rejected (non-conforming ID)"
e2e_expect_err "PR#7 finding 'F.5' rejected (non-conforming ID)"
e2e_expect_clean_edges

_flow_test_begin "status ledger: no open PRs (S4)"
e2e_new status-ledger-none
e2e_describe "the open PRs all belong to someone else"
e2e_repo feature/e2e
e2e_gh_fixture user '{"login":"me"}'
e2e_gh_fixture repo '{"nameWithOwner":"o/r"}'
e2e_gh_fixture prs '[{"number":9,"author":{"login":"bob"},"assignees":[]}]'
e2e_run_fence "$STATUS_MD" "$STATUS_FENCE"
e2e_expect_line "LEDGER_STATE=no_open_prs"
e2e_expect_clean_edges

_flow_test_begin "status ledger: gh failing reports unavailable, not an empty ledger (S6)"
e2e_new status-ledger-gh-down
e2e_describe "listing open PRs fails with HTTP 502"
e2e_repo feature/e2e
e2e_gh_fixture user '{"login":"me"}'
e2e_gh_fixture repo '{"nameWithOwner":"o/r"}'
e2e_gh_fail prs
e2e_run_fence "$STATUS_MD" "$STATUS_FENCE"
e2e_expect_line "LEDGER_STATE=unavailable"
e2e_expect_no_line "LEDGER_STATE=no_open_prs"
e2e_expect_clean_edges
