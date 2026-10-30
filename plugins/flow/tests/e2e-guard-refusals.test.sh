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
#   B7 GitHub compares the two commits the wrong way round, so a branch ahead
#      of the merged head, with commits never pushed, reads as contained (the
#      stub answers only the exact <tip>...<head> comparison)
#   B8 a merged pull request GitHub reported is dropped from the refusal, which
#      then tells the agent to open a pull request
#   R7 --admin skips GitHub's own enforcement of required checks, so one
#      unreadable lookup must not be enough to merge a checkless pull request
#   R8 a refusal for --auto says nothing is required when one lookup could not
#      be read
#   R9 an empty answer from gh with exit 0 reads as "nothing required"
#   R10 a base branch name with # or % is sent unencoded, and gh asks about
#      another branch
#   R11 a repository value that is not a GitHub owner/name (a ; in it) is
#      accepted and echoed into the command the user is told to type, and the
#      suggested command drops --admin and --match-head-commit
#   R12 a redirection between the words of a merge, with a space before its
#      target (`gh pr >& /dev/null merge 58`, also &>, &>>, >|, <>, <<, <&,
#      N>&), the subcommand written `$"merge"`, or the merge printed into a
#      pipe that a shell reads as its script, hides the merge
#   D1 a redirection glued to the last word of a discard (`git reset
#      --hard&>/dev/null`, `git restore .>x`, `rm -rf src>>log`) hides the
#      option or the whole-tree pathspec, so the discard runs; or a glued
#      `2>` that bash reads as part of the word (`.2>x` is the path .2) is
#      read as the whole tree; or a discard printed into a pipe that a shell
#      reads as its script (`echo '...' | bash`) runs unread

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

# The refusal's last line ends with this text: the command to type, with
# nothing after it that would stop it running.
_expect_last_line_ends() {
  local last
  last=$(printf '%s\n' "$E2E_ERR" | sed '/^[[:space:]]*$/d' | tail -n 1)
  case "$last" in
    *"$1") _E2E_EXTRA_FRAMES=1 _e2e_result pass "the last line ends with: $1" ;;
    *) _E2E_EXTRA_FRAMES=1 _e2e_result fail "the last line ends with: $1 (last line: $last)" ;;
  esac
}

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
e2e_gh_http protection-main 403 "$PLAN_MSG"
e2e_gh_http rules-main 403 "$PLAN_MSG"
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash --delete-branch')"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_clean_edges

_flow_test_begin "merge-guard-plan-limit-auto"
e2e_new merge-guard-plan-limit-auto
e2e_describe "--auto with no checks on a free-plan private repository: refused because nothing is required, not because it could not be read (R6)"
e2e_repo feature/r6
e2e_gh_fixture pr-58 "$NO_CHECKS"
e2e_gh_http protection-main 403 "$PLAN_MSG"
e2e_gh_http rules-main 403 "$PLAN_MSG"
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
e2e_gh_http protection-main 403 "Must have admin rights to Repository."
e2e_gh_http rules-main 403 "Resource not accessible by integration"
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
e2e_gh_http protection-main "" 'error connecting to api.github.com'
e2e_gh_http rules-main "" 'error connecting to api.github.com'
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
e2e_gh_http protection-main 403 "API rate limit exceeded for user ID 1."
e2e_gh_http rules-main 403 "API rate limit exceeded for user ID 1."
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
e2e_gh_http protection-main 422 "Validation Failed"
e2e_gh_http rules-main 422 "Validation Failed"
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

# _squash_pr_head [drop] [ahead] — the pull request got one more commit after
# feat ("c2"), and was squash-merged into main at that head. Sets HEAD_OID and
# TIP. With "ahead", feat then gets a commit of its own ("c3"). With "drop",
# the head commit is then removed from the local repository, as it is when the
# remote branch was deleted and never fetched.
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
    # "ahead": feat then gets a commit of its own that was never pushed.
    case " $* " in *" ahead "*)
      git checkout -q feat
      printf 'three\n' > g.txt; git add g.txt; git commit -q -m c3
      git checkout -q main ;;
    esac
    if [ "${1:-}" = drop ]; then
      git reflog expire --expire=now --all
      git gc -q --prune=now
    fi
  ) || _flow_assert_fail "$E2E_NAME: could not build the squash merge"
  HEAD_OID=$(cat "$E2E_DIR/head-oid")
  TIP=$(cd "$E2E_REPO" && command git rev-parse feat)
}

_flow_test_begin "branch-delete-behind-pr-head"
e2e_new branch-delete-behind-pr-head
e2e_describe "feat is one commit behind the head of PR #58, which was squash-merged into main; the head is in the local repository (B1)"
_branch_repo
_squash_pr_head
e2e_gh_fixture merged-prs-feat-main "[{\"number\":58,\"baseRefName\":\"main\",\"headRefOid\":\"$HEAD_OID\"}]"
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
e2e_gh_fixture merged-prs-feat-main "[{\"number\":58,\"baseRefName\":\"main\",\"headRefOid\":\"$HEAD_OID\"}]"
e2e_gh_fixture "compare-$TIP...$HEAD_OID" '{"status":"ahead","ahead_by":1,"behind_by":0}'
e2e_run_hook "$DELETE_HOOK" "$(_payload 'git branch -D feat')"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_clean_edges

_flow_test_begin "branch-delete-not-in-pr-head"
e2e_new branch-delete-not-in-pr-head
e2e_describe "GitHub says feat's tip is one commit ahead of the merged PR's head: a commit that was never pushed (B3, B5)"
_branch_repo
_squash_pr_head drop
e2e_gh_fixture merged-prs-feat-main "[{\"number\":58,\"baseRefName\":\"main\",\"headRefOid\":\"$HEAD_OID\"}]"
e2e_gh_fixture "compare-$TIP...$HEAD_OID" '{"status":"diverged","ahead_by":1,"behind_by":1}'
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
e2e_gh_fixture merged-prs-feat-main "[{\"number\":58,\"baseRefName\":\"develop\",\"headRefOid\":\"$HEAD_OID\"}]"
e2e_run_hook "$DELETE_HOOK" "$(_payload 'git branch -D feat')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "no pull request from 'feat' merged into 'main'"
_expect_next_step
e2e_expect_clean_edges

_flow_test_begin "branch-delete-unmerged-evidence"
e2e_new branch-delete-unmerged-evidence
e2e_describe "feat has a commit on no base and no merged PR (B5): the refusal names the base, the missing commit and what GitHub said"
_branch_repo
e2e_gh_fixture merged-prs-feat-main '[]'
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
e2e_gh_fail merged-prs-feat-main
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

# --- found in review of the first version -------------------------------------

GREEN_ONE='{"number":58,"baseRefName":"main","statusCheckRollup":[{"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"SUCCESS"}]}'

_flow_test_begin "merge-guard-admin-one-lookup-unknown"
e2e_new merge-guard-admin-one-lookup-unknown
e2e_describe "--admin, no checks, branch protection unreadable and no ruleset (R7): GitHub will not enforce required checks, so the unread one must stop the merge"
e2e_repo feature/r7
e2e_gh_fixture pr-58 "$NO_CHECKS"
e2e_gh_http protection-main 403 "Must have admin rights to Repository."
e2e_gh_fixture rules-main '[]'
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash --admin')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "--admin"
e2e_expect_err "branch protection: HTTP 403, \"Must have admin rights to Repository.\" (permission)"
e2e_expect_err "! gh pr merge 58 --repo acme/web --squash --admin"
_expect_next_step
e2e_expect_clean_edges

_flow_test_begin "merge-guard-no-admin-one-lookup-unknown"
e2e_new merge-guard-no-admin-one-lookup-unknown
e2e_describe "the same without --admin (R7): one definite answer is enough, because GitHub refuses a merge that misses a required check"
e2e_repo feature/r7b
e2e_gh_fixture pr-58 "$NO_CHECKS"
e2e_gh_http protection-main 403 "Must have admin rights to Repository."
e2e_gh_fixture rules-main '[]'
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash')"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_clean_edges

_flow_test_begin "merge-guard-auto-one-lookup-unknown"
e2e_new merge-guard-auto-one-lookup-unknown
e2e_describe "--auto on a green PR, branch protection unreadable and no ruleset (R8): the refusal shows the unread lookup instead of saying nothing is required"
e2e_repo feature/r8
e2e_gh_fixture pr-58 "$GREEN_ONE"
e2e_gh_http protection-main 403 "Must have admin rights to Repository."
e2e_gh_fixture rules-main '[]'
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --auto --squash')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "branch protection: HTTP 403, \"Must have admin rights to Repository.\" (permission)"
e2e_expect_err "rulesets: read, requires nothing"
e2e_expect_err_lacks "requires no status checks"
_expect_next_step
e2e_expect_clean_edges

_flow_test_begin "merge-guard-empty-answer"
e2e_new merge-guard-empty-answer
e2e_describe "both lookups exit 0 with an empty answer, and the PR has no checks (R9): an empty answer is not 'nothing required'"
e2e_repo feature/r9
e2e_gh_fixture pr-58 "$NO_CHECKS"
e2e_gh_fixture protection-main ''
e2e_gh_fixture rules-main ''
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "did not parse"
_expect_next_step
e2e_expect_clean_edges

_flow_test_begin "merge-guard-base-name-encoded"
e2e_new merge-guard-base-name-encoded
e2e_describe "the base branch is rel#1/x%y (R10): the lookups ask about that branch, encoded, so the plan-limit answer for it lets the merge through"
e2e_repo feature/r10
e2e_gh_fixture pr-58 '{"number":58,"baseRefName":"rel#1/x%y","statusCheckRollup":[]}'
e2e_gh_http 'protection-rel%231_x%25y' 403 "$PLAN_MSG"
e2e_gh_http 'rules-rel%231_x%25y' 403 "$PLAN_MSG"
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash')"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_clean_edges

_flow_test_begin "merge-guard-repo-not-a-github-name"
e2e_new merge-guard-repo-not-a-github-name
e2e_describe "the repository is 'a/b;touch pwned' (R11): refused as not owner/name before any call, so it never reaches a command the user is told to type"
e2e_repo feature/r11
e2e_run_hook "$MERGE_HOOK" "$(_payload "gh pr merge 58 --repo 'a/b;touch pwned' --squash")"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "is not owner/name"
e2e_expect_err_lacks "! gh pr merge"
_expect_next_step
e2e_expect_clean_edges

_flow_test_begin "merge-guard-suggested-command-keeps-flags"
e2e_new merge-guard-suggested-command-keeps-flags
e2e_describe "a failing check, merged with --admin and --match-head-commit (R11): the command the user is told to type keeps both"
e2e_repo feature/r11b
e2e_gh_fixture pr-58 "$FAILING"
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash --admin --match-head-commit 01ab8bb3f9909457c320ad94d0a995cbc8eef091')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "! gh pr merge 58 --repo acme/web --squash --admin --match-head-commit 01ab8bb3f9909457c320ad94d0a995cbc8eef091"
_expect_next_step
e2e_expect_clean_edges

_flow_test_begin "branch-delete-ahead-of-pr-head"
e2e_new branch-delete-ahead-of-pr-head
e2e_describe "feat has a commit after the merged PR's head that was never pushed, and the head is not local (B7): GitHub's compare of tip...head says 1 behind, so the delete is refused; the reverse comparison has no fixture"
_branch_repo
_squash_pr_head drop ahead
if (cd "$E2E_REPO" && command git merge-base --is-ancestor feat~1 main 2>/dev/null) || [ "$(cd "$E2E_REPO" && command git log -1 --format=%s feat)" != c3 ]; then
  _flow_assert_fail "$E2E_NAME: feat is not one unpushed commit ahead of the PR head; the scenario would not test B7"
fi
e2e_gh_fixture merged-prs-feat-main "[{\"number\":58,\"baseRefName\":\"main\",\"headRefOid\":\"$HEAD_OID\"}]"
e2e_gh_fixture "compare-$TIP...$HEAD_OID" '{"status":"diverged","ahead_by":1,"behind_by":1}'
e2e_run_hook "$DELETE_HOOK" "$(_payload 'git branch -D feat')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "1 commit(s) on 'feat' are not in it"
e2e_expect_clean_edges

_flow_test_begin "branch-delete-upstream-name"
e2e_new branch-delete-upstream-name
e2e_describe "the local branch feat tracks the remote branch feat/cronoq-open-source (B1): GitHub is asked about the upstream name"
_branch_repo
_squash_pr_head
(cd "$E2E_REPO" && command git config branch.feat.merge refs/heads/feat/cronoq-open-source)
e2e_gh_fixture merged-prs-feat_cronoq-open-source-main "[{\"number\":58,\"baseRefName\":\"main\",\"headRefOid\":\"$HEAD_OID\"}]"
e2e_run_hook "$DELETE_HOOK" "$(_payload 'git branch -D feat')"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_clean_edges

_flow_test_begin "branch-delete-pr-without-number"
e2e_new branch-delete-pr-without-number
e2e_describe "GitHub reports a merged PR whose number cannot be read (B8): the refusal says so instead of telling the agent to open a pull request"
_branch_repo
e2e_gh_fixture merged-prs-feat-main '[{"number":null,"baseRefName":"main","headRefOid":"0000000000000000000000000000000000000000"}]'
e2e_run_hook "$DELETE_HOOK" "$(_payload 'git branch -D feat')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "GitHub: a merged pull request from 'feat' has no readable number"
e2e_expect_err_lacks "open a pull request"
e2e_expect_err_lacks "connection failure"
_expect_next_step
e2e_expect_clean_edges

# --- found in review of the fixes ----------------------------------------------
#   R12 with --admin, the rulesets lookup is skipped when branch protection
#       already lists checks, so an unreadable ruleset answer is never seen
#   R13 with --admin, a required check missing from the PR is refused, which
#       stops the deliberate --admin merge past a check that never runs (the
#       user chose that this stays allowed)
#   R14 a field inside an answer has the wrong type, and the [] ? in the
#       filter reads it as "nothing required"
#   R15 --match-head-commit given as $(git rev-parse HEAD), in capitals, or
#       shortened is refused, which the hook before #310 allowed; or the note
#       that it was left out is written inside the command to type, which then
#       does not run
#   R16 gh prints two JSON documents, a jq step fails, and the failure reads
#       as "nothing required"
#   R17 a field that is false or an empty name reads as "nothing required"
#   B9 a merged pull request whose head commit cannot be read is followed by
#      "open a pull request", and a reply GitHub sent that could not be read is
#      followed by advice about connection failures
#   B10 a merged-PR list of the wrong shape reads as "no pull request merged"
#   B11 a compare answer that is not a number is advised as a connection
#       failure

_flow_test_begin "merge-guard-admin-ruleset-unread"
e2e_new merge-guard-admin-ruleset-unread
e2e_describe "--admin; branch protection requires test, which passed, and the rulesets lookup is refused (R12): with --admin both lookups must answer"
e2e_repo feature/r12
e2e_gh_fixture pr-58 "$GREEN_ONE"
e2e_gh_fixture protection-main '{"contexts":["test"]}'
e2e_gh_http rules-main 403 "Must have admin rights to Repository."
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash --admin')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "rulesets: HTTP 403, \"Must have admin rights to Repository.\" (permission)"
_expect_next_step
e2e_expect_clean_edges

_flow_test_begin "merge-guard-admin-required-check-absent"
e2e_new merge-guard-admin-required-check-absent
e2e_describe "--admin; branch protection requires test, a ruleset requires security, and the PR has only test, which passed (R13): allowed, as before #310"
e2e_repo feature/r13
e2e_gh_fixture pr-58 "$GREEN_ONE"
e2e_gh_fixture protection-main '{"contexts":["test"]}'
e2e_gh_fixture rules-main '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"security"}]}}]'
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash --admin')"
e2e_expect_equal 0 "$E2E_RC" "exit status"
e2e_expect_clean_edges

_flow_test_begin "merge-guard-admin-inner-type"
e2e_new merge-guard-admin-inner-type
e2e_describe "--admin; the ruleset answer holds required_status_checks as a string, not a list (R14)"
e2e_repo feature/r14
e2e_gh_fixture pr-58 "$GREEN_ONE"
e2e_gh_fixture protection-main '{}'
e2e_gh_fixture rules-main '[{"type":"required_status_checks","parameters":{"required_status_checks":"security"}}]'
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash --admin')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "rulesets: gh exit 0, but the answer did not parse (other)"
_expect_next_step
e2e_expect_clean_edges

_flow_test_begin "merge-guard-match-head-commit-forms"
e2e_new merge-guard-match-head-commit-forms
e2e_describe "a green PR merged with --match-head-commit as a substitution, in capitals, and shortened (R15): each is allowed, as before #310"
e2e_repo feature/r15
e2e_gh_fixture pr-58 "$GREEN_ONE"
e2e_gh_not_found protection-main
e2e_gh_fixture rules-main '[]'
for v in '$(git rev-parse HEAD)' '"$SHA"' ABCDEF1234567 abc12; do
  e2e_run_hook "$MERGE_HOOK" "$(_payload "gh pr merge 58 --repo acme/web --squash --match-head-commit $v")"
  e2e_expect_equal 0 "$E2E_RC" "exit status with --match-head-commit $v"
done
e2e_expect_clean_edges

_flow_test_begin "merge-guard-match-head-commit-unread"
e2e_new merge-guard-match-head-commit-unread
e2e_describe "a failing check, merged with --match-head-commit \$(git rev-parse HEAD) (R15): the line before the next step says the value was left out, and the command itself ends where it would run"
e2e_repo feature/r15b
e2e_gh_fixture pr-58 "$FAILING"
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash --match-head-commit $(git rev-parse HEAD)')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
_expect_next_step
_expect_last_line_ends "! gh pr merge 58 --repo acme/web --squash"
BEFORE=$(printf '%s\n' "$E2E_ERR" | sed '/^[[:space:]]*$/d' | tail -n 2 | head -n 1)
e2e_expect_equal "The command below leaves out --match-head-commit, whose value this hook cannot read." "$BEFORE" "the line before the next step"
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash --match-head-commit ABCDEF1')"
e2e_expect_err "! gh pr merge 58 --repo acme/web --squash --match-head-commit ABCDEF1"
e2e_expect_clean_edges

_flow_test_begin "branch-delete-pr-head-unreadable"
e2e_new branch-delete-pr-head-unreadable
e2e_describe "GitHub reports merged PR #58 with a head commit that is not a commit id (B9): the refusal does not tell the agent to open a pull request"
_branch_repo
e2e_gh_fixture merged-prs-feat-main '[{"number":58,"baseRefName":"main","headRefOid":"nothex"}]'
e2e_run_hook "$DELETE_HOOK" "$(_payload 'git branch -D feat')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "GitHub: PR #58 has no readable head commit"
e2e_expect_err_lacks "open a pull request"
e2e_expect_err_lacks "connection failure"
e2e_expect_err "gh pr list --state merged --head feat --base main"
_expect_next_step
e2e_expect_clean_edges

_flow_test_begin "merge-guard-two-documents"
e2e_new merge-guard-two-documents
e2e_describe "--admin, no checks; branch protection answers two JSON documents (R16): not 'nothing required'"
e2e_repo feature/r16
e2e_gh_fixture pr-58 "$NO_CHECKS"
e2e_gh_fixture protection-main '{"contexts":[]} {"contexts":["ci"]}'
e2e_gh_fixture rules-main '[]'
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash --admin')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "branch protection: gh exit 0, but the answer did not parse (other)"
_expect_next_step
e2e_expect_clean_edges

_flow_test_begin "merge-guard-false-and-empty-fields"
e2e_new merge-guard-false-and-empty-fields
e2e_describe "--admin; branch protection answers contexts false, then a ruleset requires an empty name (R17): neither reads as 'nothing required'"
e2e_repo feature/r17
e2e_gh_fixture pr-58 "$GREEN_ONE"
e2e_gh_fixture rules-main '[]'
for answer in '{"contexts":false}' '{"checks":false}'; do
  e2e_gh_fixture protection-main "$answer"
  e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash --admin')"
  e2e_expect_equal 2 "$E2E_RC" "exit status for $answer"
  e2e_expect_err "branch protection: gh exit 0, but the answer did not parse (other)"
done
e2e_gh_fixture protection-main '{"contexts":["test"]}'
e2e_gh_fixture rules-main '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":""}]}}]'
e2e_run_hook "$MERGE_HOOK" "$(_payload 'gh pr merge 58 --repo acme/web --squash --admin')"
e2e_expect_equal 2 "$E2E_RC" "exit status with an empty required name"
e2e_expect_err "rulesets: gh exit 0, but the answer did not parse (other)"
e2e_expect_clean_edges

_flow_test_begin "branch-delete-pr-list-shapes"
e2e_new branch-delete-pr-list-shapes
e2e_describe "the merged-PR list is an object, a list of numbers, or an entry with no base (B10): each is an answer that could not be read, not 'no pull request merged'"
_branch_repo
for answer in '{"a":1}' '[1,2]' '[{"number":58,"headRefOid":"0000000000000000000000000000000000000000"}]'; do
  e2e_gh_fixture merged-prs-feat-main "$answer"
  e2e_run_hook "$DELETE_HOOK" "$(_payload 'git branch -D feat')"
  e2e_expect_equal 2 "$E2E_RC" "exit status for $answer"
  e2e_expect_err "returned an answer that did not parse"
  e2e_expect_err_lacks "open a pull request"
done
e2e_expect_clean_edges

_flow_test_begin "branch-delete-compare-unreadable"
e2e_new branch-delete-compare-unreadable
e2e_describe "GitHub's compare exits 0 with an answer that is not a number (B11): reported as unreadable, not as a connection failure"
_branch_repo
_squash_pr_head drop
e2e_gh_fixture merged-prs-feat-main "[{\"number\":58,\"baseRefName\":\"main\",\"headRefOid\":\"$HEAD_OID\"}]"
e2e_gh_fixture "compare-$TIP...$HEAD_OID" '{"status":"ahead","ahead_by":1,"behind_by":null}'
e2e_run_hook "$DELETE_HOOK" "$(_payload 'git branch -D feat')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "GitHub's compare answer could not be read"
e2e_expect_err_lacks "connection failure"
_expect_next_step
e2e_expect_clean_edges

#   B12 a branch name with $( ) or ; is printed unquoted in the command the
#       user is told to type, which would run what is inside it
#   B13 an unreadable answer and a failed call together lose the retry note

_flow_test_begin "branch-delete-name-quoted"
e2e_new branch-delete-name-quoted
e2e_describe "an unmerged branch named x\$(id);y (B12): the command the user is told to type quotes it"
e2e_repo work
(
  _e2e_git_env
  cd "$E2E_REPO" || exit 1
  git checkout -q -B main work
  git checkout -q -b 'x$(id);y'
  printf 'one\n' > f.txt; git add f.txt; git commit -q -m c1
  git checkout -q main
  git branch -q -D work
) || _flow_assert_fail "$E2E_NAME: could not build the scratch branch"
e2e_gh_fixture 'merged-prs-x$(id);y-main' '[]'
e2e_run_hook "$DELETE_HOOK" "$(_payload "git branch -D 'x\$(id);y'")"
e2e_expect_equal 2 "$E2E_RC" "exit status"
_expect_last_line_ends "the user must type: ! git branch -D 'x\$(id);y'"
e2e_expect_clean_edges

_flow_test_begin "branch-delete-odd-and-failed"
e2e_new branch-delete-odd-and-failed
e2e_describe "two merged PRs: the first compare fails with HTTP 502, the second head is unreadable (B13): the refusal says a retry may help, and the inspect step names the base field"
_branch_repo
_squash_pr_head drop
e2e_gh_fixture merged-prs-feat-main "[{\"number\":58,\"baseRefName\":\"main\",\"headRefOid\":\"$HEAD_OID\"},{\"number\":59,\"baseRefName\":\"main\",\"headRefOid\":\"nothex\"}]"
e2e_gh_fail "compare-$TIP...$HEAD_OID"
e2e_run_hook "$DELETE_HOOK" "$(_payload 'git branch -D feat')"
e2e_expect_equal 2 "$E2E_RC" "exit status"
e2e_expect_err "A call to GitHub also failed, so running the delete again may help."
e2e_expect_err "--json number,baseRefName,headRefOid"
_expect_next_step
e2e_expect_clean_edges

# --- R12: redirections between the words of a merge ---------------------------

_flow_test_begin "merge-guard-redirection-between-words"
e2e_new merge-guard-redirection-between-words
e2e_describe "a check failed, and the merge has a redirection between its words with a space before the target, its subcommand written \$\"merge\", or is printed into a pipe a shell reads (R12): each is read as the merge and refused for the failing check"
e2e_repo feature/r12
e2e_gh_fixture pr-58 "$FAILING"
while IFS= read -r C; do
  e2e_run_hook "$MERGE_HOOK" "$(_payload "$C")"
  e2e_expect_equal 2 "$E2E_RC" "exit status for: $C"
  e2e_expect_err "test [failure]"
done <<'ROWS'
gh pr >& /dev/null merge 58 --repo acme/web --squash
gh pr &> /dev/null merge 58 --repo acme/web --squash
gh pr &>> log merge 58 --repo acme/web --squash
gh pr >| log merge 58 --repo acme/web --squash
gh pr <> f merge 58 --repo acme/web --squash
gh pr <& 0 merge 58 --repo acme/web --squash
gh pr 2>& 1 merge 58 --repo acme/web --squash
gh pr 0<& 3 merge 58 --repo acme/web --squash
gh pr 1<> f merge 58 --repo acme/web --squash
gh pr merge 58 >& /dev/null --repo acme/web --squash
gh pr $"merge" 58 --repo acme/web --squash
echo 'gh pr merge 58 --repo acme/web --squash' | bash
printf '%s\n' "gh pr merge 58 --repo acme/web --squash" | sudo sh -s
ROWS
e2e_expect_clean_edges

# --- D1: a redirection glued to the last word of a discard ---------------------

_flow_test_begin "discard-glued-redirection"
e2e_new discard-glued-redirection
e2e_describe "every discard block-destructive refuses, with a redirection glued to its last word (&>, >, >>, &>>, >|, <), or printed into a pipe a shell reads as its script (D1): each is still refused; a glued 2> that bash reads as part of the word, the non-discarding forms, and harmless text piped into a shell are allowed"
e2e_repo work
while IFS= read -r FORM; do
  for OP in '&>/dev/null' '>/dev/null' '>>log' '&>>log' '>|log' '</dev/null'; do
    e2e_run_hook "$DELETE_HOOK" "$(_payload "$FORM$OP")"
    e2e_expect_equal 2 "$E2E_RC" "exit status for: $FORM$OP"
  done
  e2e_run_hook "$DELETE_HOOK" "$(_payload "$FORM 2>/dev/null")"
  e2e_expect_equal 2 "$E2E_RC" "exit status for: $FORM 2>/dev/null"
done <<'ROWS'
git reset --hard
git reset HEAD~1 --hard
git reset --har
git restore .
git restore --worktree .
git checkout .
git checkout -- .
git clean -fd
git clean --force
rm -rf src
rm -r -f src
ROWS
while IFS= read -r C; do
  e2e_run_hook "$DELETE_HOOK" "$(_payload "$C")"
  e2e_expect_equal 0 "$E2E_RC" "exit status for: $C"
done <<'ROWS'
git checkout .2>/dev/null
git restore .2>x
git checkout -- src/a.py&>/dev/null
git reset --soft HEAD~1&>/dev/null
git restore --staged .&>/dev/null
git clean -n&>/dev/null
rm -rf node_modules&>/dev/null
git status&>/dev/null
echo 'git status' | bash
git log | bash scripts/fmt.sh
ROWS
# Text piped into a shell that reads its script from its input is a command.
for C in "echo 'git reset --hard' | bash" "printf '%s\n' 'rm -rf src' | sh -s" "echo 'git checkout -- .' | sudo bash -x"; do
  e2e_run_hook "$DELETE_HOOK" "$(_payload "$C")"
  e2e_expect_equal 2 "$E2E_RC" "exit status for: $C"
done
e2e_expect_clean_edges
