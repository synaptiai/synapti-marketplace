# Watch mode: branch ${BRANCH}

You are running flow watch mode for the branch `${BRANCH}` in ${REPO}. Each iteration keeps it up to date with `${DEFAULT_BRANCH}` and keeps its checks passing.

Read these on each iteration:
- `.flow/triggers/branch-${BRANCH_SLUG}-watch.trigger.yaml` — the trigger (allowed_actions, forbidden_actions, stop_conditions)
- `.flow/goals/` — the active FlowGoal for this branch, if any, for its verification commands

Read none of them through a symbolic link: when `.flow`, `.flow/triggers`, `.flow/goals` or the file is one, skip it and say so.

On each iteration:
1. Check that you are on `${BRANCH}` (`git branch --show-current`). If not, stop the iteration and say so; never switch branches yourself.
2. Fetch: `git fetch origin`. If `origin/${BRANCH}` no longer exists (`git rev-parse --verify --quiet "refs/remotes/origin/${BRANCH}"` fails), or its pull request has been merged (`gh pr list --repo ${REPO} --head "${BRANCH}" --state merged` lists one), stop (see below). A branch whose commits are all in `${DEFAULT_BRANCH}` is not "merged" by that alone: a branch with no commits of its own yet is in the same state.
3. If `origin/${DEFAULT_BRANCH}` has commits this branch does not (`git rev-list --count "HEAD..origin/${DEFAULT_BRANCH}"` is not 0), run `/flow:run trigger branch-${BRANCH_SLUG}-watch`: it checks the trigger's policy and runs its target, `/flow:resolve "${BRANCH}"`, which merges the default branch in and resolves conflicts. If it left nothing merged, merge it in yourself: `git merge --no-edit "origin/${DEFAULT_BRANCH}"`. Never rebase. If a conflict cannot be resolved, run `git merge --abort`, report the conflicting files, and end the iteration.
4. Run the project's quality checks (lint, type check, tests — the ones `/flow:start` uses, or the FlowGoal's verification commands).
5. If a check fails because of the merge (it passed on the branch before the merge), fix it. A failure that was already there before the merge is reported, not fixed.
6. Commit the merge and any fixes, and push with a plain `git push origin "${BRANCH}"`. Never force-push.
7. **Never merge a pull request**. **Never release**. **Never delete a branch**. Tier 3 actions are forbidden by trigger policy.
8. **Never create or modify triggers**. Recursion is denied by default.

Stop when the branch is merged or deleted: print a summary, then tell the user to end the loop (Ctrl-C) and run `/flow:trigger disable branch-${BRANCH_SLUG}-watch`.
