# Issue #170 — a merge can proceed while checks are still running, and against the wrong repository

Branch: `fix/issue-170-merge-ci-gate`
Closes #170, #161.

Grouped because both are about the same moment: the data a merge decision rests on.
One report says the checks are not actually waited for; the other says the data may
belong to a different repository entirely. Both are read at the same preflight, and
both gate the one irreversible, outward-facing thing flow does.

## Specification

### Non-goals

- Requiring branch protection. Whether a repository configures required checks is
  the repository's decision. This is about not mistaking their absence for a
  passing gate.
- Changing the merge strategy or the branch-deletion default.
- Blocking `gh pr merge` outright. A merge on a fully green pull request goes
  through untouched, whichever path it takes.
- Changing what `/flow:merge` does once its gate passes.
- Making `gh` resolve repositories differently. The fix is to say which repository
  every call means, not to change how `gh` guesses.

### Failure modes

- **A check is queued or running.** Blocked, naming the checks that are not
  finished. This is the case that prompted the report: a pull request merged with
  twelve jobs still queued.
- **A check failed.** Blocked, naming it.
- **The repository has no required status checks.** `--auto` cannot wait, because
  GitHub's auto-merge waits for *required* checks and there are none. Blocked, and
  the message says that is why.
- **The rollup cannot be read** (auth, network, rate limit). Blocked. A gate that
  opens when it cannot see is not a gate.
- **A pull request with no checks at all.** Reported as "no checks are required
  here", never as "all checks passed" — those are different facts and the
  assessment table now says which one it is.
- **`gh` resolves a different repository than the working tree.** The preflight
  refuses rather than reporting a well-formed answer about someone else's pull
  request.
- **`git remote get-url origin` fails or names a host `gh` does not manage.** The
  cross-check reports that it could not be made, rather than passing silently.

### Interface contracts

- The hook reads `{"tool_input":{"command":...}}` on stdin, exits 0 to allow and 2
  to block with the reason on stderr — the same contract every other hook in
  `hooks/scripts/` follows.
- The command-position parser is shared with `block-destructive.sh` rather than
  copied, so `echo "gh pr merge 3"` is text in both.
- Every preflight `!` block resolves `REPO` once, prints it as part of its output,
  and pins every `gh pr view` and `gh api` call to it.
- The merge assessment table gains the repository name, so a wrong-repository case
  is visible by reading it rather than only by re-running `gh` by hand.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Check completeness | Read only `conclusion` and treat a queued check — which has no conclusion yet — as neither passed nor failed, so a merge with twelve jobs queued still proceeds | A rollup fixture with one `COMPLETED/SUCCESS` and one `QUEUED` check must block, and the message must name the queued one |
| Check completeness | Count only `CheckRun` entries, as the current preflight does, so a legacy `StatusContext` status is invisible | A fixture with a pending `StatusContext` and no `CheckRun` must block |
| Required-checks probe | Treat the 404 from the branch-protection endpoint as an error and fail open | A repository with no protection must reach the "no required checks" branch, not the "cannot read" branch |
| Required-checks probe | Ask only about branch protection and miss a ruleset, so a repository that requires checks through rulesets is told it has none | Both endpoints are consulted; a rulesets-only repository reports required checks |
| Repository identity | Compare `gh repo view` against itself — read the same value twice and call it agreement | The cross-check parses `git remote get-url origin` independently, and a fixture where the two disagree must refuse |
| Hook command position | Fire on any command whose text contains the words, so a commit message about merging is refused | `echo "gh pr merge 3 --auto"` must be allowed while `gh pr merge 3 --auto` is examined |
