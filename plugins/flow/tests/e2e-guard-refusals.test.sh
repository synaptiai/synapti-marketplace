# shellcheck shell=bash
# End-to-end: what the merge guard (hooks/scripts/block-unchecked-merge.sh) and
# the branch-delete rule of hooks/scripts/block-destructive.sh decide, and what
# their refusals tell the agent (issue #310).
#
# Each scenario feeds the shipped hook a PreToolUse payload in a scratch
# repository. gh answers from fixtures in the shapes real gh prints, including
# the 403 GitHub returns for branch protection and rulesets on a private
# repository on the free plan:
#   stdout {"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.",...,"status":"403"}
#   stderr gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)
#
# Ways it can be wrong, written down before the scenarios:
#   R1 the plan-limit 403 is read as "could not be read", so a checkless pull
#      request on such a repository is refused on every attempt
#   R2 the plan-limit 403 is accepted as "nothing required" by matching any
#      403, so a 403 for missing permission also lets a checkless merge through
#   R3 the refusal names no HTTP status or GitHub message, or names the wrong
#      kind of failure (plan limit, permission, network or rate limit, other)
#   R4 a refusal that retrying cannot change still suggests a re-run, or one
#      that retrying can change says it will not
#   R5 a refusal ends without a next step: neither a command the agent can run
#      nor the exact command the user must type
#   R6 --auto on a plan-limited repository is refused as "could not be read"
#      rather than for the real reason, that nothing can be required there
#   B1 a local branch behind the head of its merged pull request is called
#      unmerged, when that head contains every commit on it
#   B2 the same, when the pull request's head commit is not in the local
#      repository and only GitHub can compare the two
#   B3 a branch whose pull request was merged into another base, or whose tip
#      is not in the pull request's head, is allowed
#   B4 a failed GitHub lookup is read as "merged"
#   B5 the refusal names no base and no missing commits, so "would lose
#      unmerged work" cannot be checked
#   B6 a branch the local checks already prove merged now waits on GitHub

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

MERGE_HOOK=hooks/scripts/block-unchecked-merge.sh
DELETE_HOOK=hooks/scripts/block-destructive.sh
PLAN_MSG="Upgrade to GitHub Pro or make this repository public to enable this feature."
NO_CHECKS='{"number":58,"baseRefName":"main","statusCheckRollup":[]}'
FAILING='{"number":58,"baseRefName":"main","statusCheckRollup":[{"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"FAILURE"}]}'

_payload() { jq -cn --arg c "$1" '{tool_input:{command:$c}}'; }

# The refusal's last line is its next step (R5).
_expect_next_step() {
  local last
  last=$(printf '%s\n' "$E2E_ERR" | sed '/^[[:space:]]*$/d' | tail -n 1)
  case "$last" in
    "Next: "*) _E2E_EXTRA_FRAMES=1 _e2e_result pass "the refusal ends with a next step" ;;
    *) _E2E_EXTRA_FRAMES=1 _e2e_result fail "the refusal ends with a next step (last line: $last)" ;;
  esac
}

# --- the merge guard ----------------------------------------------------------

_flow_test_begin "merge-guard-plan-limit-no-checks"
e2e_new merge-guard-plan-limit-no-checks
e2e_describe "no checks, and both requirement lookups answer the free-plan 403 (R1, the synapti-web case): nothing can be required, so the merge goes ahead"
e2e_repo feature/r1
e2e_gh_fixture pr-58 "$NO_CHECKS"
e2e_gh_http protection 403 "$PLAN_MSG"
e2e_gh_http rules 403 "$PLAN_MSG"
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash --delete-branch')"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_clean_edges

_flow_test_begin "merge-guard-plan-limit-auto"
e2e_new merge-guard-plan-limit-auto
e2e_describe "--auto with no checks on a free-plan private repository: refused because nothing is required, not because it could not be read (R6)"
e2e_repo feature/r6
e2e_gh_fixture pr-58 "$NO_CHECKS"
e2e_gh_http protection 403 "$PLAN_MSG"
e2e_gh_http rules 403 "$PLAN_MSG"
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --auto --squash')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "requires no status checks"
e2e_expect_err "cannot require checks"
e2e_expect_err_lacks "could not be read"
e2e_expect_err "gh pr merge 58 --repo acme/web --squash"
_expect_next_step
e2e_expect_clean_edges

_flow_test_begin "merge-guard-permission-403"
e2e_new merge-guard-permission-403
e2e_describe "no checks, and both lookups answer a 403 for missing permission (R2, R3, R4, R5): refused, with the evidence, as not changing on retry, and the command the user must type"
e2e_repo feature/r2
e2e_gh_fixture pr-58 "$NO_CHECKS"
e2e_gh_http protection 403 "Must have admin rights to Repository."
e2e_gh_http rules 403 "Resource not accessible by integration"
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "branch protection: HTTP 403, \"Must have admin rights to Repository.\" (permission)"
e2e_expect_err "rulesets: HTTP 403, \"Resource not accessible by integration\" (permission)"
e2e_expect_err "will not change on retry"
e2e_expect_err_lacks "Re-run"
e2e_expect_err "the user must type: ! gh pr merge 58 --repo acme/web --squash"
_expect_next_step
e2e_expect_clean_edges

_flow_test_begin "merge-guard-network"
e2e_new merge-guard-network
e2e_describe "no checks, and neither lookup reached GitHub (R3, R4): refused as a network failure that a retry can change"
e2e_repo feature/r3
e2e_gh_fixture pr-58 "$NO_CHECKS"
e2e_gh_http protection "" 'error connecting to api.github.com'
e2e_gh_http rules "" 'error connecting to api.github.com'
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "branch protection: no HTTP response, \"error connecting to api.github.com\" (network or rate limit)"
e2e_expect_err "may change on retry"
e2e_expect_err_lacks "will not change on retry"
_expect_next_step
e2e_expect_clean_edges

_flow_test_begin "merge-guard-rate-limit"
e2e_new merge-guard-rate-limit
e2e_describe "no checks, and both lookups answer GitHub's rate-limit 403 (R2, R3): a rate limit, not a permission or plan limit"
e2e_repo feature/r3b
e2e_gh_fixture pr-58 "$NO_CHECKS"
e2e_gh_http protection 403 "API rate limit exceeded for user ID 1."
e2e_gh_http rules 403 "API rate limit exceeded for user ID 1."
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "(network or rate limit)"
e2e_expect_err "gh api rate_limit"
e2e_expect_err_lacks "(permission)"
_expect_next_step
e2e_expect_clean_edges

_flow_test_begin "merge-guard-other-status"
e2e_new merge-guard-other-status
e2e_describe "no checks, and the lookups answer a status that is none of the known kinds (R3): named as other"
e2e_repo feature/r3c
e2e_gh_fixture pr-58 "$NO_CHECKS"
e2e_gh_http protection 422 "Validation Failed"
e2e_gh_http rules 422 "Validation Failed"
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "branch protection: HTTP 422, \"Validation Failed\" (other)"
e2e_expect_err "the user must type: ! gh pr merge 58 --repo acme/web --squash"
_expect_next_step
e2e_expect_clean_edges

_flow_test_begin "merge-guard-rollup-unreadable"
e2e_new merge-guard-rollup-unreadable
e2e_describe "the pull request's checks cannot be read at all (R3, R5): gh's own message is shown, and the refusal ends with a step"
e2e_repo feature/r5
e2e_gh_fail pr-58
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "HTTP 502: Bad Gateway"
_expect_next_step
e2e_expect_clean_edges

_flow_test_begin "merge-guard-failing-check"
e2e_new merge-guard-failing-check
e2e_describe "a check failed (R5): the refusal says what to do next, and what the user would type to merge anyway"
e2e_repo feature/r5b
e2e_gh_fixture pr-58 "$FAILING"
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "test [failure]"
e2e_expect_err "! gh pr merge 58 --repo acme/web --squash"
_expect_next_step
e2e_expect_clean_edges

# --- the branch-delete guard --------------------------------------------------

# _branch_repo — main with one commit, and feat one commit ahead of it ("c1").
# Sets TIP to feat's commit.
_branch_repo() {
  e2e_repo work
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    git checkout -q -B main work
    git checkout -q -b feat
    printf 'one\n' > f.txt; git add f.txt; git commit -q -m c1
    git checkout -q main
    git branch -q -D work
  ) || _flow_assert_fail "$E2E_NAME: could not build the scratch branches"
  TIP=$(cd "$E2E_REPO" && command git rev-parse feat)
}

# _squash_pr_head — the pull request got one more commit after feat ("c2"),
# and was squash-merged into main at that head. Sets HEAD_OID. With "drop",
# the head commit is then removed from the local repository, as it is when
# the remote branch was deleted and never fetched.
_squash_pr_head() {
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    git checkout -q -b pr-head feat
    printf 'two\n' >> f.txt; git add f.txt; git commit -q -m c2
    git rev-parse HEAD > "$E2E_DIR/head-oid"
    git checkout -q main
    git merge -q --squash pr-head; git commit -q -m "squash PR #58"
    git branch -q -D pr-head
    if [ "${1:-}" = drop ]; then
      git reflog expire --expire=now --all
      git gc -q --prune=now
    fi
  ) || _flow_assert_fail "$E2E_NAME: could not build the squash merge"
  HEAD_OID=$(cat "$E2E_DIR/head-oid")
}

_flow_test_begin "branch-delete-behind-pr-head"
e2e_new branch-delete-behind-pr-head
e2e_describe "feat is one commit behind the head of PR #58, which was squash-merged into main; the head is in the local repository (B1)"
_branch_repo
_squash_pr_head
e2e_gh_fixture merged-prs "[{\"number\":58,\"baseRefName\":\"main\",\"headRefOid\":\"$HEAD_OID\"}]"
e2e_run_hook "$DELETE_HOOK" "$(_payload 'git branch -D feat')"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_clean_edges

_flow_test_begin "branch-delete-behind-pr-head-remote-only"
e2e_new branch-delete-behind-pr-head-remote-only
e2e_describe "as above, but the PR's head commit is not in the local repository, so GitHub compares feat with it (B2)"
_branch_repo
_squash_pr_head drop
if (cd "$E2E_REPO" && command git cat-file -e "$HEAD_OID^{commit}" 2>/dev/null); then
  _flow_assert_fail "$E2E_NAME: the head commit is still in the scratch repository; the scenario would not test the GitHub comparison"
fi
e2e_gh_fixture merged-prs "[{\"number\":58,\"baseRefName\":\"main\",\"headRefOid\":\"$HEAD_OID\"}]"
e2e_gh_fixture compare '{"status":"ahead","ahead_by":1,"behind_by":0}'
e2e_run_hook "$DELETE_HOOK" "$(_payload 'git branch -D feat')"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_clean_edges

_flow_test_begin "branch-delete-not-in-pr-head"
e2e_new branch-delete-not-in-pr-head
e2e_describe "GitHub says feat's tip is one commit ahead of the merged PR's head: a commit that was never pushed (B3, B5)"
_branch_repo
_squash_pr_head drop
e2e_gh_fixture merged-prs "[{\"number\":58,\"baseRefName\":\"main\",\"headRefOid\":\"$HEAD_OID\"}]"
e2e_gh_fixture compare '{"status":"diverged","ahead_by":1,"behind_by":1}'
e2e_run_hook "$DELETE_HOOK" "$(_payload 'git branch -D feat')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "PR #58"
e2e_expect_err "does not contain"
e2e_expect_err "${TIP:0:7}"
_expect_next_step
e2e_expect_clean_edges

_flow_test_begin "branch-delete-merged-into-other-base"
e2e_new branch-delete-merged-into-other-base
e2e_describe "the only merged PR from feat went into develop, not main (B3)"
_branch_repo
_squash_pr_head
e2e_gh_fixture merged-prs "[{\"number\":58,\"baseRefName\":\"develop\",\"headRefOid\":\"$HEAD_OID\"}]"
e2e_run_hook "$DELETE_HOOK" "$(_payload 'git branch -D feat')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "no pull request from 'feat' merged into 'main'"
_expect_next_step
e2e_expect_clean_edges

_flow_test_begin "branch-delete-unmerged-evidence"
e2e_new branch-delete-unmerged-evidence
e2e_describe "feat has a commit on no base and no merged PR (B5): the refusal names the base, the missing commit and what GitHub said"
_branch_repo
e2e_gh_fixture merged-prs '[]'
e2e_run_hook "$DELETE_HOOK" "$(_payload 'git branch -D feat')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "'main': 1 commit on 'feat' is not in it"
e2e_expect_err "${TIP:0:7} c1"
e2e_expect_err "no pull request from 'feat' merged into 'main'"
e2e_expect_err "the user must type: ! git branch -D feat"
_expect_next_step
e2e_expect_clean_edges

_flow_test_begin "branch-delete-lookup-failed"
e2e_new branch-delete-lookup-failed
e2e_describe "the merged-PR lookup fails with HTTP 502 (B4): refused, and the failure is shown"
_branch_repo
_squash_pr_head
e2e_gh_fail merged-prs
e2e_run_hook "$DELETE_HOOK" "$(_payload 'git branch -D feat')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "HTTP 502: Bad Gateway"
_expect_next_step
e2e_expect_clean_edges

_flow_test_begin "branch-delete-squash-at-head-no-lookup"
e2e_new branch-delete-squash-at-head-no-lookup
e2e_describe "feat is at the head that was squash-merged (the fix/cronoq-review case): allowed by the local check, with no call to GitHub (B6)"
_branch_repo
(
  _e2e_git_env
  cd "$E2E_REPO" || exit 1
  git merge -q --squash feat; git commit -q -m "squash feat"
) || _flow_assert_fail "$E2E_NAME: could not squash-merge feat"
e2e_run_hook "$DELETE_HOOK" "$(_payload 'git branch -D feat')"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_clean_edges
