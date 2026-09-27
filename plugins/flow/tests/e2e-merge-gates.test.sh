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

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

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

_goal_case() { e2e_new "$1"; e2e_describe "$2"; e2e_repo feature/e2e; }

_flow_test_begin "merge goal gate: an achieved goal on this branch passes and is named (G1)"
_goal_case merge-goal-achieved "achieved goal on this branch, plus an active goal on another branch"
e2e_goal g-mine feature/e2e achieved true
e2e_goal g-other feature/other active false
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE"
e2e_expect_line "FLOW_GOAL_GATE_STATE=ok"
e2e_expect_line "FLOW_GOAL_ID=g-mine"
e2e_expect_line "FLOW_GOAL_LIFECYCLE=achieved"
e2e_expect_clean_edges

_flow_test_begin "merge goal gate: an unfinished goal on this branch blocks (G2)"
_goal_case merge-goal-active "active goal on this branch that has not reached achieved"
e2e_goal g-mine feature/e2e active false
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE"
e2e_expect_line "FLOW_GOAL_GATE_STATE=blocked"
e2e_expect_out "FlowGoal g-mine lifecycle is 'active'"
e2e_expect_clean_edges

_flow_test_begin "merge goal gate: an active goal on another branch does not block this one (G3)"
_goal_case merge-goal-other-branch "the only active goal belongs to feature/other"
e2e_goal g-other feature/other active false
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE"
e2e_expect_line "FLOW_GOAL_GATE_STATE=ok"
e2e_expect_line "FLOW_GOAL_GATE_NOTE=no active FlowGoal for this branch — gate not applicable"
e2e_expect_no_line "FLOW_GOAL_ID=g-other"
e2e_expect_clean_edges

_flow_test_begin "merge goal gate: two active goals on this branch block (G4)"
_goal_case merge-goal-two-active "two active goals both own this branch"
e2e_goal g-one feature/e2e active false
e2e_goal g-two feature/e2e active false
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE"
e2e_expect_line "FLOW_GOAL_GATE_STATE=blocked"
e2e_expect_out "multiple active FlowGoals on the current branch"
e2e_expect_clean_edges

_flow_test_begin "merge goal gate: goals disabled in project settings turns the gate off (G5)"
_goal_case merge-goal-disabled "flow.goals.enabled=false, with an unfinished goal on this branch"
e2e_goal g-mine feature/e2e active false
mkdir -p "$E2E_REPO/.claude"
printf '%s\n' '{"flow":{"goals":{"enabled":false}}}' > "$E2E_REPO/.claude/settings.flow.json"
e2e_run_fence "$MERGE_MD" "$GOAL_FENCE"
e2e_expect_line "FLOW_GOAL_GATE_STATE=disabled"
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
