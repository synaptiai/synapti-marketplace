---
issue: 219
created: '2026-09-22T14:10:00Z'
branch: feature/issue-219-duplicated-logic-two-layers
artifacts:
- type: specification
  captured_at: '2026-09-22T14:10:00Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: specification
  captured_at: '2026-09-22T14:05:08Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: goal-created
  captured_at: '2026-09-22T14:07:00Z'
  goal_id: issue-219
  source: issue-219-body
- type: workflow-run
  captured_at: '2026-09-22T14:07:21Z'
  workflow: start-issue
  run_id: 2026-09-22T141500Z-issue-219
  status: active
- type: review-cycle
  captured_at: '2026-09-22T16:54:37Z'
  cycle: 1
  path: B
  findings_count: 36
  pr: 250
---
# Decision Journal — Issue #219

feat(flow): duplicated logic is prevented at plan time and caught in two layers at review, verbatim and semantic

## Specification

### Non-goals

- A seventh reviewer agent. Layer B runs inside the `code-reviewer` call that every fan-out already
  makes. The external spec proposed a duplicated-logic agent with a knowledge graph; that adds a
  call to every review and still cannot see the semantic half.
- A hand-rolled clone detector. `jscpd` or nothing: a second detector is a second thing to maintain,
  and a scanner written here would be measured against no reference.
- Installing anything during a review. The CI workflow declares `jscpd` the way it already declares
  the Python prerequisites. Flow's runtime never installs a tool on a user's machine mid-run; a
  missing detector is reported, with the install command, and the run continues.
- Reporting pre-existing duplication. Measured on this repository: 1827 duplicate blocks exist at
  the configured thresholds. The scan is scoped to what the branch introduces, against the merge
  base, or it is noise that trains readers to ignore it.
- Type-4 (reimplemented, not copied) detection by the token scanner. A token detector cannot see it
  by construction; that is Layer B's job, and Layer B is retrieval plus judgment, not detection.
- Cross-repository duplication. Flow has no linked-repository model.
- Blocking a task when no scanner ran. The task-time gate blocks on a clone that was **found**,
  never on the absence of a finder.

### Failure modes

- **Timeouts**: measured 2.4 s wall clock over this repository's 841 tracked files. The scan is
  bounded by a file count and a time limit; exceeding either reports `STATE=unavailable` naming the
  bound, never a partial list presented as complete.
- **Partial failures**: `jscpd` present but its report absent or unparseable is `STATE=unavailable`
  with the reason. A base ref that does not resolve — the shallow-clone case, which `jscpd`'s own
  error names — is reported with that error text rather than treated as "no duplication".
- **Invalid input**: a threshold that cannot fire is the defect this feature is most likely to ship.
  `jscpd` enforces a line minimum **and** a token minimum, and its default 50-token floor suppresses
  a genuine 5-line block, measured at 35 tokens. `duplication.minTokens` is pinned on every
  invocation so the documented `minLines` is the threshold that actually binds.
- **Missing context**: no `jscpd` in the environment is `STATE=unavailable` with the reason and the
  install command, stated once per run, and the task completes. Reviewing as though nothing was
  duplicated is a choice; the reader is told it was made.
- **Over-reporting**: `jscpd`'s own new-clone flag is not sufficient on its own. Measured on the
  #218 branch, 8 of the 10 pairs it marked new touched no file the branch changed. Every reported
  pair must have at least one side in `git diff --name-only`.

### Interface contracts

- `bin/flow-clone-scan.sh <base>..<head>` prints `STATE=ok|none|unavailable`, `SCAN_BASE=<sha>`,
  `FILES_SCANNED=<n>`, one `CLONE=added <file:a-b> existing <file:c-d> lines=N tokens=T` line per
  introduced pair and one `CLONE_WITHIN_DIFF=` line per pair whose two sides are both in the diff,
  plus `REASON=` and `INSTALL=` when unavailable. A literal `|` in a value is written `%7C`.
- `settings.json` / `schema.json`: `duplication.enabled` (`true`), `duplication.minLines` (`5`),
  `duplication.minTokens` (`20`), `duplication.excludePaths` (test directories, vendored and
  generated code, plus flow's own machine-written artifact trees `.decisions/**` and `.flow/**`).
- `references/finding-schema.md`: category `duplication`, ID prefix `DUP-`. P2 for an introduced
  block duplicating code that already existed, P3 for a block duplicated only within the diff,
  confidence HIGH — a verbatim match is a fact. The location is the **added** side; the problem text
  names the existing block.
- `agents/implementation-planner.md` Step 3 task field `Reuses:`, in exactly two forms:
  `existing <file>:<symbol>`, or `none — searched: <terms>; candidates examined: N (<list>)`.
  `commands/start.md` Stranger Test gains the failure mode "Missing reuse check".
- `agents/code-reviewer.md` Step 4 gains a Reuse check emitting `candidates examined: N`; zero
  candidates is stated, not silent.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Threshold that cannot fire | `minLines` is passed as the line minimum and jscpd's 50-token default is left in place, so no real 5-line block is ever reported and every run is green | A must-fire fixture of 5 identical lines (35 tokens, measured) reports one clone at the pinned `minTokens`; the same fixture reports none when the token floor is left at its default, and the test asserts both |
| Baseline scope | The scan reports the repository's pre-existing duplication rather than what the branch introduced | A run over this repository's own tree reports 1827 blocks; a run scoped to a branch that introduced none reports none, and a third copy added to a base that already holds two is still reported |
| Which side is cited | The finding cites the pre-existing block, so the fix looks like a change to code the branch never touched | jscpd lists the pre-existing file first in a verified fixture; the test asserts the emitted location is the side present in `git diff --name-only`, not the side jscpd printed first |
| Absent vs unreadable | A missing or failing `jscpd` prints `STATE=none`, telling every reviewer there is no duplication when nobody looked | A `PATH` with no `jscpd` prints `STATE=unavailable` with `REASON=` and `INSTALL=`; only a scan that ran and found no pair prints `STATE=none` |
| Exempt paths | `excludePaths` is accepted in settings but never reaches the scanner, so test-file duplication floods every review | Measured: the #217 branch yields 33 pairs, 21 of them between test files; the test asserts those 21 are absent under the default excludes and that a non-excluded pair survives |
| Scan set | The scanner walks the working tree, picking up untracked files and `.git` internals, so `FILES_SCANNED` describes a set nobody chose | Measured: an unfiltered run reported 1370 sources against 841 tracked files, including `.git/hooks` samples. The scan enumerates through `git ls-files` and `FILES_SCANNED` is reconciled against it |

## Decisions (AskUserQuestion, 2026-09-22)

- **Two PRs, built in parallel worktrees.** #219 alone; #215 and #216 together, because #216 exists
  to measure #215. Merge order follows the stated issue order. #216's recorded-run criterion is
  parked behind a spend decision, and keeping it out of #219 means that block cannot stall this work.
- **Three acceptance criteria rested on false premises and were corrected, with approval.** #219 AC2
  and AC3 required `bin/_flow_clone_scan.py`, the hand-rolled fallback already rejected; #219 AC5 and
  #215 AC3 named `tests/flow-schemas.test.sh`, which validates the `schemas/v1/` artifact schemas and
  never reads `schema.json`. Same class as #217's AC3 and #218's AC2 — the third occurrence.
- **CI installs `jscpd` explicitly**, beside the existing Python prerequisites step, so the scanner
  is exercised for real rather than only against a stub. Tests skip-PASS loudly when it is absent
  locally, following the PyYAML precedent in the same suite.
- **`duplication.minTokens` is a fourth setting, default 20.** Measured: a 5-line copied block is 35
  tokens and does not fire at jscpd's 50-token default; a 4-line copy stays silent at 20. Both halves
  of the threshold are visible to the team that tunes them.
- **Diff-awareness comes from `jscpd --baseline-from-ref`,** verified on a two-branch fixture and on
  a third-copy fixture, with `git diff --name-only` used only to pick which side is the added one.
  Rejected: hand-rolled hunk intersection — more code in the area that has cost the most review
  cycles, for line-level precision the finding does not need.
- **Everything jscpd parses is scanned, narrowed by `excludePaths`.** In this plugin the source is
  markdown; a code-only rule would exempt the repository shipping the feature, and the largest real
  duplication found here is 166 lines shared between two command documents.
- **That 166-line duplication becomes a review exception, not a refactor.** Command documents have no
  include mechanism, so the duplication cannot be removed; it is recorded in
  `.flow/review-exceptions.md` with its reason, which is the first real use of the #214 feature.

## Decisions and corrections during implementation (2026-09-22)

- **`references/skill-contracts.md` was the wrong home for the `Reuses:` assertion.** That file
  governs SKILL.md *frontmatter* schemas and says nothing about agent return shapes. AC1 permits
  either it or the planner's return shape; the field is asserted on the planner's Step 6 table,
  where the plan actually surfaces it.
- **`--fail-on-empty` cannot be used as the emptiness signal.** jscpd fires it both when nothing was
  scannable and when every file was below the token floor, and reports `sources: 0` in both cases.
  Collapsing those would report "nobody looked" for a repository of small files. The scan set is
  therefore enumerated here, and `DETECTOR_SOURCES=0` against a non-empty scan set is `unavailable`
  because the detector genuinely examined nothing. Fixtures for a clean result carry a file that
  clears the floor, so `STATE=none` is a result rather than an empty run.
- **`DETECTOR_SOURCES` counts both scans.** `--baseline-from-ref` scans the merge base as well, so the
  number is normally larger than `FILES_SCANNED` and is not a subset of it. Stated in the helper
  rather than left to be rediscovered.
- **`git ls-files` is limited to the working directory.** A scan started in a subdirectory
  enumerated only that subtree and reported the smaller count as the whole scan set. Every git call
  now runs from the repository root, and a test starts the scan from a subdirectory.
- **The category vocabulary lives in two places and only one was updated.** `review-blast-radius.test.sh`
  caught `duplication` missing from `tests/finding-schema/row-schema.json`. Sweeping the class rather
  than the instance: `dependency`, added by #217, was missing from the same list and is now present.

## The feature run against its own branch

`bin/flow-clone-scan.sh --base origin/main --head HEAD` reported two pairs on this branch: the
positional range parser and the reference validator in the new helper duplicated `flow-dep-diff.sh`,
because both were copied from the hardened sibling as the standing rule says to.

Resolved by extraction, with the user's agreement, rather than by an exception: unlike a command
document, a shell file can share code. `bin/lib/range-args.sh` is the first shared shell library in
`bin/`; it owns the whole `--base`/`--head`/`<base>..<head>`/`--help` command line and hands back
what it did not recognise, so a helper with its own options parses only those. A partial extraction
was not enough — it left the call site itself duplicated at 18 lines, and rewriting code to fall
under the detector's threshold would have been avoidance rather than a fix. A helper that cannot
load the library refuses to run and prints `STATE=unavailable` on stdout; it never falls back to an
inline copy, which is the duplication this removed.

The scan now reports `STATE=none` on this branch.

- **The 166-line block shared by `commands/address.md` and `commands/review.md` gets no exception
  row.** The plan had been to record one. The finished feature shows it is never reported: it is
  pre-existing duplication, and the scan is scoped to what a branch introduces, so it is suppressed
  automatically even on this branch, which edits both files. An exception for it would be
  configuration that never matches. It would become reportable only if someone made that block newly
  duplicated, and at that point it should be judged afresh.

## Two tests passed locally for a reason that does not exist in CI

The first CI run failed three assertions on both runners while the same suite was green locally.

`CLAUDE_PLUGIN_ROOT` is unset in both places, so the helper falls back to searching for an installed
copy of the plugin to reach the settings cascade. This machine has ten of them under
`~/.claude/plugins/cache/`; a CI runner has none. So the `duplication.enabled: false` case resolved
real settings here and silently fell back to the built-in defaults there, reporting `STATE=ok` for a
layer the fixture had turned off. The test was reading the machine, not the tree under test. Both
that case and its control now pin `CLAUDE_PLUGIN_ROOT` to the repository's own `plugins/flow`, and a
mutant that ignores `duplication.enabled` fails them.

The third failure was an assertion that a clean run prints nothing on stderr. When the plugin root is
not pinned, the shared root-resolution idiom breaks out of its own pipeline as soon as a candidate
matches, and the producer can lose the race and print a broken-pipe notice. That is a property of an
idiom every `bin/` helper shares, not of this change, and it is harmless — it goes to stderr and no
caller reads it. The assertion now pins the root and checks what it was actually about: that the
exclude-list filter does not make a settings source look unparseable.

## Review cycle 1 — five reviewers, 29 findings

Two reviewers reproduced their findings against the shipped helper rather than reading it, and the
two that mattered most were both real.

**The task-time gate was blind exactly where it runs.** `commands/start.md` invokes it at step 8b,
before the commit at step 9, but the changed set was built from committed history alone. The
detector saw the duplicate in the worktree and the pair was then discarded for touching nothing
"changed". Measured: the same tree reported `STATE=none` staged and `STATE=ok` once committed. The
changed set is now the union of the merge-base diff, the worktree diff and the index diff.

**A path spelled two ways was invisible.** `git diff --name-only` quotes a path containing any
non-ASCII byte; `git ls-files -z` does not. The two sets never intersected for such a file, so a
clone behind a non-ASCII filename read as a clean scan. Both sides now use `-z`. This repository
already knew the defect — `code-reviewer.md`'s blast-radius fence passes `-c core.quotePath=off` with
a comment about it — and the new helper still shipped with it.

**Two findings were about the reviewer's own machine.** The plugin root was resolved with the
inline idiom that `references/plugin-root-resolution.md` scopes to command fences, whose first
candidate is a working-directory-relative `plugins/flow`. Scanning a repository that happens to
contain one would have executed that repository's `cascade-resolve.sh` and let it choose the
settings. The root is now a sibling of the script, as every other `bin/` helper resolves it. That
also removed the broken-pipe notice on stderr, so the assertion about it went back to being strict.

Other fixes: a `--` separator and `./` prefixes so a tracked path beginning with a dash is a file
rather than an option; a file-count and a wall-clock bound, which the specification promised and the
code did not have; consecutive `**/` groups collapsed, because adjacent ones backtrack exponentially
on a pattern the reviewed branch supplies; control characters percent-encoded, so a newline in a
filename cannot forge a `KEY=value` line; `0` refused as a threshold, matching the schema's minimum;
the exclude list carried as newline-separated, so a glob containing a comma stays one pattern; a
`SETTINGS_SOURCE=` line, so a run that never reached the cascade says so; and the secrets fence in
`security-reviewer.md` now refuses to run silently when `origin/<branch>` does not resolve.

Four test defects were fixed too: an assertion matching a pre-existing unrelated line, a fence walk
counting fences rather than the variables it examined, two silence cases with no control showing the
same fixture fires, and a fence-assignment check that would have flagged a `read` or `for` target.
