---
issue: 213
created: '2026-09-16T10:25:05Z'
artifacts:
- type: specification
  captured_at: '2026-09-16T10:25:05Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: goal-evaluation
  captured_at: '2026-09-16T18:13:01Z'
  goal_id: issue-213
  result: achieved
  trigger: command
---
# Decision Journal — Issue #213

feat(flow): /flow:review reads the FlowGoal, traces the blast radius of contract changes, and the
docs stop disagreeing about whether review creates a goal

## Specification

### Non-goals

- Cross-repository consumers. Flow has no linked-repository model and this issue does not add one;
  a consumer outside this repository is not traced and not reported as missing.
- Executing anything the goal carries. The `### FlowGoal` block reads the YAML; a
  `verification_command` string is printed, never run, expanded or substituted. `test-runner` keeps
  running the project's own quality commands.
- Changing which commands create goals. `/flow:review` and `/flow:address` stay FlowRun-only; only
  `references/flow-goals.md` changes, because it is the document that is wrong.
- Changing what `holdout-validation` loads. #207 owns the scenario templates; this issue changes
  only what the skill receives.
- Re-litigating the finding vocabulary beyond adding `breaking-change`.

### Failure modes

- **Timeouts**: the goal is fetched over the API, so Phase 1 makes three `gh` calls it did not make
  before: the head commit, the goal contents at that commit, and the pull request file list. The
  contents call carries its response status (`gh api -i`), so telling an absent goal from an
  unreachable one costs no extra call. They carry no explicit timeout, which is
  what every other `gh` call in this fence does; a call that fails or hangs is reported as
  `STATE=unavailable` or `GOAL_EDITED=unavailable` rather than as an answer. No agent call is
  introduced. LSP probes keep the existing `lsp.timeout`; a probe that times out is reported as the
  tool that was used, not as zero callers.
- **Partial failures**: a goal that exists but cannot be read — malformed YAML, valid YAML of the
  wrong shape, missing `python3` or `yaml` module, or a fetch that fails for any reason other than
  404 — yields `STATE=unavailable` with the reason, and the review falls back to the issue-text
  path. It never reports `STATE=none`, which would say "no goal exists" about a goal that does
  exist. Only a 404 at the head commit is `STATE=none`.
- **Invalid input**: a goal with zero acceptance criteria, or with no risk map, is valid input —
  the risk rows are then derived from the issue text and every row carries `source=issue-text`
  (user decision, 2026-09-16). A goal whose own file is modified by the pull request under review
  raises a finding naming the file and what changed.
- **Missing context**: no linked issue on the pull request means no goal path to resolve, which is
  `STATE=none` and today's behaviour.

### Interface contracts

- `### FlowGoal` section (Phase 1, printed): `STATE=ok|none|unavailable`, `GOAL_PATH=`,
  `GOAL_REF=<head commit>`, `ENCODING=`, `GOAL_STATUS=`,
  `AC=<id>|<text>|<verification_command>` (one per criterion, the command printed as text and never
  executed, with a literal `|` inside any value written `%7C`), `NON_GOAL=<text>`, `CONTRACT=<text>`,
  `RISK_MAP=<area>|<plausible_wrong_version>|<discriminating_check>|<source>` where `source` is
  `goal` or `issue-text` (and `issue-text` in every state where no goal was read, so the derivation
  step fires), `GOAL_EDITED=no|created|modified|removed|unavailable` for what this pull request does
  to the goal file it is reviewed against, with `GOAL_EDITED_REASON=` when that is `unavailable`. The goal is read at the pull request
  head commit over the API, not from the working tree: the Phase 1 fence runs before the checkout.
- `code-reviewer` Summary: `callers examined: N (findReferences|incomingCalls|grep)` per modified
  exported or public symbol.
- Review body: a `### Blast radius` section listing each consumer of a changed contract, present in
  `templates/review-comment.md`.
- `references/finding-schema.md` category vocabulary gains `breaking-change`.
- Evidence-bundle draft handed to `holdout-validation`: a `### Risk map coverage` list,
  `<area> → <test file:line>` per row or `none`.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Goal parsing | The block expands or executes a `verification_command` while reading it | A goal whose `verification_command` is `$(touch /tmp/flow-pwned)` prints that string verbatim and leaves no file on disk |
| Goal trust | A pull request that weakens its own acceptance criteria passes unflagged | A pull request whose file list reports `modified` for `.flow/goals/issue-213.goal.yaml` sets `GOAL_EDITED=modified` and raises a finding naming the file; one that only adds it sets `created`; one that touches another issue goal sets `no`; a failed file-list call sets `unavailable`, never `no` |
| Risk-map provenance | Rows derived from issue text are presented as if the team wrote them | With a goal carrying no risk map, the section reports `RISK_MAP_SOURCE=issue-text` and every row the derivation step renders ends `|issue-text`; with the fixture goal the section's own rows end `|goal` |
| Blast radius honesty | `callers examined: 0` from a failed or absent LSP reads as "no callers, all fine" | A symbol that Grep finds referenced in another file while the LSP reported zero callers raises a finding rather than passing |
| Goal absent vs unreadable | A malformed goal is reported as no goal, so the review silently drops the specification | A goal file containing `: not: yaml:` yields `STATE=unavailable` with a reason, not `STATE=none` |

## Decisions (user, 2026-09-16)

- **Goal trust**: use the goal's acceptance criteria, non-goals, contracts and risk map even though
  the file arrives on the pull request head, because it is tracked in git and a weakening is visible
  in the diff — and flag the case where the diff edits the goal file.
- **Blast radius**: implement every contract-file pattern the issue names (exported signature,
  schema, migration, OpenAPI, GraphQL, protobuf, goal interface contract), detected by path and
  extension globs only, with a fixture per pattern. No per-format parsing.
- **No risk map**: derive risk areas from the issue text rather than emitting `none`. Every derived
  row is labelled `source=issue-text` in the section and in the review body, so a derived row is
  never mistaken for one the team wrote.

## Holdout validation (cycle 2)

Three claims did not survive cross-referencing against file state.

- **A goal written in prose did not read on an ascii stdout.** Goal text carries em dashes and
  accents, and under a C locale with the PEP 538 coercion disabled the interpreter resolves stdout
  to ascii; printing such a value raised `UnicodeEncodeError` after `STATE=ok` had been printed, so
  the section announced a goal it had read and then listed none of its criteria. That is the same
  failure the buffering was meant to close, reached by another route. Reproduced through the block,
  then fixed by writing UTF-8 explicitly and replacing anything unprintable.
- **A goal naming no criteria was reported as unreadable.** The specification calls zero acceptance
  criteria valid input; the reader raised on it. Now it reads, prints no `AC=` line, and the
  requirements step is told what that means.
- **The failure-modes section said no network call was introduced.** Three are, and the section now
  says so along with what happens when one fails.

## Review cycle 4 (the delta since cycle 2)

One new P1, in the fix for the alias bomb. `MAX_VALUE` and `MAX_ROWS` bounded the output — and
shortened the specification while still reporting `STATE=ok`, which hands the review less than the
goal carries and calls it the goal. It was live on this repository: reviewing this very pull
request, AC1 (737 characters) lost its tail, including the clause about the interpreter hardening
that the same delta added; the interface contract lost the `GOAL_EDITED` values this delta changed.
The row half was worse — a goal with more criteria than the cap printed the first hundred and said
nothing at all.

That contradicted the sibling change in the same commit, which made a wrong-shaped criterion raise
rather than be dropped, with the comment "dropping it would report a goal that named two as a goal
that named none".

The bounds stay, because the reason for them stays. What changed is that they are honest: the value
bound sits above the longest value any goal in this repository carries, so an ordinary goal is never
shortened, and when either bound does bite the section prints `GOAL_TRUNCATED=` naming how many
values and rows were lost and where to read the whole thing. The requirements step is told to read a
shortened value at `GOAL_REF` before mapping it. Nothing in three cycles and 72 mutants had pinned
this. A fixture did feed the section a value far longer than the cap — the 20 000-character
`wide.yaml` — but it asserted only that one value cannot make one line unbounded. No test asserted
what became of the content, so the bound was pinned and the loss was not.

## Cycle 5 (commit a5c50f4, delta 768eaef..a5c50f4)

Zero new findings, which is the convergence signal. The cycle handed over seven items it declined to
raise under the third-cycle rule, and three of them were mutants that survived the new tests: a cap
of 730 (the fixture was 720 characters while the comment named 737, so any cap in between passed
while cutting this repository's own criteria), a dropped `…` (asserted on the legend, never on a
value), and a row count of 1 in place of the number actually withheld. The first is the same defect
as the one it was written to catch: a test that passes for a weaker reason than its label. The
fixture now derives its length from `.flow/goals/` and the cap is compared against that, so a cap
below what this project writes fails regardless of what any fixture happens to be.

Two more were the silent-drop family one level up from the case cycle 2 fixed. `sequence()` returned
`[]` for anything that was not a list, so `acceptance_criteria` written as a mapping — or `non_goals`
written as prose — printed `STATE=ok` with no rows, which the requirements step reads as "the goal
names none". Risk rows were filtered by shape for the same result, and that filter also made the
withheld-row count wrong. Both now raise, and the reason names the key. An absent key still means
none, because that is a real answer; only a key that is present and unreadable is unavailable.

One existing assertion had to change with them. The `shape3.yaml` case asserted `STATE=ok` for a
goal whose `non_goals` was a string, under the label "a string is not iterated one character per
non-goal". That guard is still right and still holds; what it also encoded was the silent drop. It
now asserts `STATE=unavailable` with the key named, and keeps the per-character guard.

A separate test-adequacy sweep, re-run at the same commit, reached the risk-row finding
independently and raised one more the cycles had not: the goal-path match in the file-list query
could be loosened from an equality to a containment with every assertion still passing. The existing
prefix case does not discriminate the two, because `issue-420`'s path does not contain `issue-42`'s.
A path that does contain it is the discriminating input, and this repository ships one — a fixture
goal nested under a tests directory — so a pull request touching that fixture would have reported
the goal under review as modified. Two cases now pin it, nested and suffixed; the containment
mutant fails on exactly those two and nothing else.

## Review cycle 6 (the delta since cycle 5)

One P1, and it is the same class again, one key up. `mapping()` returned `{}` for anything that was
not a mapping, so a `specification:` written as prose or as a list swallowed the non-goals, the
interface contracts and the risk map in a single step — and the section still printed `STATE=ok`.
That is strictly more loss than the `sequence()` case fixed in cycle 5, and after that fix the two
disagreed: `non_goals: prose` was unavailable while `specification: prose` was ok. The consumer harm
is the one this block exists to prevent: the `scope` and `breaking-change` rules key off the
`NON_GOAL=` and `CONTRACT=` lines, so an altered contract had nothing to be flagged against.

`mapping()` now mirrors `sequence()`: absent is `{}`, present-but-wrong-shaped raises with the key
named. Every shape check in the reader has now been enumerated, and each one either raises or is the
absent-key arm — the class is closed in this file. One adjacent behaviour changed deliberately: a
`lifecycle:` written as a scalar was `GOAL_STATUS=unknown` and is now `STATE=unavailable`, which
matches `schemas/v1/goal.schema.json` typing it as an object. A goal with no lifecycle block at all
still reads, with the status honestly unknown.

The lesson recorded from this cycle is not about the code. Cycle 5's fix was applied to the instance
the reviewer named, and the twin four lines above it was not examined — which is what bought this
sixth cycle. The rule now carried into future sessions is to name the defect class in a sentence and
sweep every sibling of that shape before pushing.

## The goal's terminal record

`.flow/goals/issue-213.goal.yaml` carries `last_evaluation` naming commit `468a717` and 3784
assertions, which is two fixes and 33 assertions behind this branch. It stays that way: the goal
reached `achieved`, and `bin/flow-goal-record.sh` refuses to update a terminal goal, per the
goal-lifecycle iron law. That record is the vintage of the verdict that closed the goal, not a claim
about the head commit, and hand-editing it would both bypass the helper and untrust the goal in the
trust ledger. The later cycles are recorded here instead.

Worth noting as a property of flow rather than of this issue: a goal marked terminal cannot record
findings that arrive afterwards, and two cycles did arrive afterwards here.

Two items from an adequacy sweep are recorded as having nothing to pin rather than fixed. The `LC_ALL=C`
in `kind_of()` guards pattern matching against locale-dependent collation, but no pattern in the
function uses a character range or class, so no input distinguishes the pinned locale from an
unpinned one. It stays as a guard for patterns added later; a test asserting it today would pass for
a weaker reason than its label, which is the defect this branch spent three cycles removing. The
`[ -t 0 ]` usage guard needs a controlling terminal to exercise, and the test asserts its source text
and says so at the assertion.

## Verdict (issue #213, commit 468a717)

All six acceptance criteria PASS. The judge reached that in four passes, and the first three are worth
recording because none of them was about the code.

The first invocation was mis-made: I handed the judge file paths, and it runs without file tools. It
refused to emit a degenerate all-FAIL and said so, which was the right call — six FAILs would have
reported the work unverified when the evidence simply had not been delivered.

The second returned FAIL on all six because the bundle was ad-hoc prose rather than the shape
`references/evidence-bundle-format.md` defines: no per-criterion sections, none of the mandatory
subsections that force a producer to state what was NOT tested and what the evidence does not
promise. Rebuilding it to the format is what surfaced the real gaps — the holdout findings had been
retired by my assertion rather than by a re-run, and several criteria had no captured output at all.

The third returned five PASSes and one FAIL, for a hole the format is designed to expose: the goal's
`Goal trust` risk row cited a test but no table anywhere stated its inputs, its expected values or
the wrong version they discriminate. The row is now documented with its eight file-list inputs, and
one more was added afterwards on the judge's advisory — a goal whose issue number merely begins with
this one, which a select narrowed from equality to a prefix would answer for.

The holdout validation was re-run at the current tree rather than assumed: it confirmed the two
earlier P1s and the P2 as fixed against file state, and raised one P3 of its own — the failure-modes
section described four network calls where the block makes three, a leftover from the commit-probe
design that the response status replaced.

## Review cycle 2 (five reviewers plus holdout validation)

Twenty-four findings, all fixed here. The two that mattered most were introduced by cycle 1 fixes.

- **The requirements step told the reviewer to run a `verification_command`.** Those strings come
  from the goal at the pull request head, `allowed-tools: Bash` pre-approves execution, and a goal
  that arrived with a checkout is never in the trust ledger — so the one sentence handed an author
  arbitrary execution in the reviewer shell, while three other places in the same change said the
  goal is never executed. The sentence is gone: criteria are read, and `test-runner` keeps running
  the quality commands the project defines.
- **A goal built out of YAML aliases had no bound.** `safe_load` shares alias nodes, so the load is
  cheap and `str()` is not: a few hundred bytes expanded to 72MB on one `AC=` line, and each further
  alias level multiplies it. The reader refuses aliases (nothing flow writes uses an anchor), caps
  any one value, and caps how many rows of a kind it prints.

Three agents independently found the same defect one level up from cycle 1's: `LINKED=unavailable`
means the linked-issue lookup FAILED, and it was folded in with "no issue linked", so an unreachable
API was reported as the positive claim that the pull request links no issue. It has its own answer
now, as does a reader that dies without printing (the section took its output without checking that
it exited or said anything), a criterion of the wrong shape (dropped silently, so a goal naming two
criteria read as a goal naming none), and a rename.

Telling an absent goal from an unreadable one no longer rests on a second API call or on the wording
of an error message: `gh api -i` carries the HTTP status, so 404 is absent and 403, 5xx and a dead
network are unreadable. The size cap was above Linux's per-string exec limit, so a goal between
128KB and 256KB would have passed the guard and failed the exec.

`bin/flow-contract-files.sh` now encodes what it prints, for the same reason the goal reader does: a
path is author-controlled, and a newline in one forged a second `CONTRACT_FILE=` row that a reviewer
reads as another contract. The agent also resolves the plugin root instead of assuming the working
directory — it runs in the project under review, where `bin/flow-contract-files.sh` does not exist,
so the blast-radius step would have failed everywhere except this checkout.

## Test adequacy (cycle 2)

A 72-mutant sweep with 19 sanity controls, all 19 caught, so a survivor meant the tests were blind
rather than the harness. It found assertions that could not fail, and the worst of them were mine.

- **The stub decided the answer the filter was supposed to decide.** The `gh` stub replied to the
  file-list call from its own variables, so four loosenings of the real `jq` select — a prefix match,
  `contains()`, dropping `previous_filename`, dropping `head -1` — all left the suite green. The stub
  now runs the caller's own filter over a fixture array, so the code under test decides.
- **The head-revision read was pinned only against reading from disk.** The stub answered any
  contents request, so deleting `?ref=` — reading the default branch while printing the head SHA —
  stayed green. The stub now serves a decoy to any request that did not ask for the head.
- **A fixture never reached the loop it was written for.** The wrong-shaped-specification goal had no
  `objective`, so the reader raised before the non-goals loop; the assertion that a string is not
  iterated one character at a time passed because there were no lines at all, not because the guard
  worked.
- **Two assertions could not fail by construction:** the forged-goal check (the hostile module
  returned a half-shaped document the reader discarded before printing) and the GOAL_EDITED consumer
  count (it counted the block's own echoes, so a review with no consumer still passed).

Five of the nine `RISK_MAP_SOURCE=issue-text` emissions, the non-numeric-issue arm, the size cap, and
six of the helper's patterns had no input that distinguished them from their absence. All are pinned
now, and the fifteen mutants written against them are all caught.

## Self-review resolution (cycle 1)

An 18-finding self-review of the branch at 5fa26bc. Every finding is fixed in this pull request;
the two that were P1 both changed the design rather than a line.

- **The goal was read from the working tree.** The Phase 1 fence runs when the command loads, which
  is before the `gh pr checkout` further down, so the block read whatever branch the reviewer was on
  — reproduced from a worktree at origin/main, which reported `STATE=none` for a pull request whose
  head carries the goal. The goal is now fetched at the head commit over the API, and the section
  reports which commit under `GOAL_REF=`. AC1 was Not Met for any review that was not already on the
  branch, which is the ordinary external-review case.
- **Reading the goal could run code the pull request ships.** Both interpreter invocations ran with
  the repository as the working directory, so a pull request adding `yaml.py` at the root executed
  arbitrary code the moment Phase 1 read the goal; `gh pr checkout` leaves exactly that in the tree.
  Reproduced with a marker-writing `yaml.py` that also forged `STATE=ok`. Both invocations now set
  `PYTHONSAFEPATH` and scrub the import path, and the test runs the hostile module against an
  interpreter that ignores `PYTHONSAFEPATH`, because that variable is honoured only from Python 3.11
  and the scrub is the half that has to hold on its own.

Three answers were wrong in the direction that reads as "nothing to see": a goal that was valid YAML
but not a goal announced `STATE=ok` and then failed partway; a failed file-list call printed
`GOAL_EDITED=no`, which is the answer meaning this pull request does not weaken its goal; and the
goal-edited probe matched any goal path including additions, so it fired on every spec-first pull
request. Each now has its own answer, and `GOAL_EDITED` takes five values rather than two.

**The derivation the decision asked for was not implemented.** The section reported
`RISK_MAP_SOURCE=issue-text` and stopped: no step derived rows, so no row labelled `issue-text` could
exist, and the test asserted the absence rather than the rule. A named step now reads the issue body
and renders the rows. The user decision is unchanged; what changed is where the rows are produced —
prose derivation is not something the `!` block can do, so the block reports the state and the step
next to it does the work. The spec check reads accordingly: the block invents no rows, and every row
the step renders ends `|issue-text`.

**Acceptance criteria corrected in flight.** AC1 described a goal file on disk and AC3 named a
heading level the template does not render. Both are tightened rather than weakened, and this is the
case the new `GOAL_EDITED=modified` rule exists to surface — recorded here because a goal edited by
the pull request it judges should never be a silent edit.

Five guards that mutation testing had shown were free are now pinned, and the 18 mutants written for
this round are all caught: the goal-file location check, the migration extension list, the field
separator escaping, the interpreter guard, and the N=0 rule, which had been asserted by its token
rather than by its clause.

<!-- auto-log: 2026-09-16 12:26 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/goal213.py -->

<!-- auto-log: 2026-09-16 12:29 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/ac1_tests.py -->

<!-- auto-log: 2026-09-16 12:30 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/ac1_impl.py -->

<!-- auto-log: 2026-09-16 12:32 commit "feat(flow): /flow:review Phase 1 reads the FlowGoal it is reviewing against" -->

<!-- auto-log: 2026-09-16 12:35 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/ac2_impl.py -->

<!-- auto-log: 2026-09-16 12:36 commit "feat(flow): hand the risk map to the two passes that can check it" -->

<!-- auto-log: 2026-09-16 12:37 Write /Users/danielbentes/synapti-marketplace/plugins/flow/tests/review-blast-radius.test.sh -->

<!-- auto-log: 2026-09-16 12:38 Write /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-contract-files.sh -->

<!-- auto-log: 2026-09-16 12:38 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/ac3_impl.py -->

<!-- auto-log: 2026-09-16 12:44 commit "feat(flow): a contract change lists who depends on it" -->

<!-- auto-log: 2026-09-16 13:03 commit "docs(flow): the references stop claiming review and address create goals" -->

<!-- auto-log: 2026-09-16 13:22 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/review-213-findings.md -->

<!-- auto-log: 2026-09-16 13:22 Edit /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/review-213-findings.md -->

<!-- auto-log: 2026-09-16 13:23 Edit /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/review-213-findings.md -->

<!-- auto-log: 2026-09-16 13:23 Edit /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/review-213-findings.md -->

<!-- auto-log: 2026-09-16 13:27 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/review-213-findings.md -->

<!-- auto-log: 2026-09-16 13:41 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-09-16 13:42 commit "fix(flow): the review reads the goal at the pull request head, safely" -->

<!-- auto-log: 2026-09-16 13:44 commit "feat(flow): the risk map, the non-goals and the goal-trust flag are acted on" -->

<!-- auto-log: 2026-09-16 13:46 commit "fix(flow): a contract file git had to quote is still a contract file" -->

<!-- auto-log: 2026-09-16 13:47 commit "fix(flow): the categories the review instructs are the categories it defines" -->

<!-- auto-log: 2026-09-16 13:59 commit "refactor(flow): the goal reader leaves nothing behind and asks the API what happened" -->

<!-- auto-log: 2026-09-16 14:05 commit "test(flow): the import-path scrub is pinned on an interpreter that ignores PYTHONSAFEPATH" -->

<!-- auto-log: 2026-09-16 14:06 commit "test(flow): an empty API response is told apart from a goal that will not parse" -->

<!-- auto-log: 2026-09-16 14:09 commit "docs(flow): the goal states the contract the review actually implements" -->

<!-- auto-log: 2026-09-16 14:43 commit "fix(flow): the goal-edited flag is reported whatever the goal state is" -->

<!-- auto-log: 2026-09-16 14:59 commit "fix(flow): the rows are derived from the issue text whenever no goal supplied them" -->

<!-- auto-log: 2026-09-16 15:48 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/evidence-213.md -->

<!-- auto-log: 2026-09-16 15:52 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/stub/gh -->

<!-- auto-log: 2026-09-16 15:53 commit "fix(flow): a goal written in prose reads whatever the locale resolved to" -->

<!-- auto-log: 2026-09-16 15:53 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/convention-findings.md -->

<!-- auto-log: 2026-09-16 15:54 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/pr-body-213.md -->

<!-- auto-log: 2026-09-16 15:59 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/mutants.py -->

<!-- auto-log: 2026-09-16 15:59 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/convention-findings.md -->

<!-- auto-log: 2026-09-16 16:01 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/sec/evidence.md -->

<!-- auto-log: 2026-09-16 16:03 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-security-reviewer/project_flow_goal_trust_ledger_threat_model.md -->

<!-- auto-log: 2026-09-16 16:03 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/mutants2.py -->

<!-- auto-log: 2026-09-16 16:04 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-security-reviewer/MEMORY.md -->

<!-- auto-log: 2026-09-16 16:08 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/project_flow_marker_guard_vs_parser.md -->

<!-- auto-log: 2026-09-16 16:08 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/MEMORY.md -->

<!-- auto-log: 2026-09-16 16:08 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/err-inspector-draft.md -->

<!-- auto-log: 2026-09-16 16:10 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/cycle2-fixes.md -->

<!-- auto-log: 2026-09-16 16:12 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/err-inspector-draft.md -->

<!-- auto-log: 2026-09-16 16:13 Write /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-error-handler-inspector/project_flow_unavailable_collapse.md -->

<!-- auto-log: 2026-09-16 16:13 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-error-handler-inspector/MEMORY.md -->

<!-- auto-log: 2026-09-16 16:16 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-test-runner/reference_revert_harness.md -->

<!-- auto-log: 2026-09-16 16:16 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-test-runner/reference_revert_harness.md -->

<!-- auto-log: 2026-09-16 16:24 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/test-adequacy-findings.txt -->

<!-- auto-log: 2026-09-16 16:25 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/reader.py -->

<!-- auto-log: 2026-09-16 16:35 Edit /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/test-adequacy-findings.txt -->

<!-- auto-log: 2026-09-16 16:37 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-test-runner/reference_revert_harness.md -->

<!-- auto-log: 2026-09-16 16:38 commit "fix(flow): the review never runs what the goal carries, and a goal cannot flood it" -->

<!-- auto-log: 2026-09-16 17:31 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/mut3.py -->

<!-- auto-log: 2026-09-16 19:00 commit "test(flow): the tests decide the answer, not the stub that feeds them" -->

<!-- auto-log: 2026-09-16 19:29 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/bundle-213.md -->

<!-- auto-log: 2026-09-16 19:34 commit "test(flow): every state says why, and both vocabularies can report a miss" -->

<!-- auto-log: 2026-09-16 19:56 commit "docs(flow): the failure modes count the calls the block makes" -->

<!-- auto-log: 2026-09-16 20:11 commit "test(flow): a goal whose issue number begins with this one is not this one" -->

<!-- auto-log: 2026-09-16 20:14 commit "chore(flow): the goal records the verdict that closed it" -->

<!-- auto-log: 2026-09-16 20:43 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/cycle4-finding.txt -->

<!-- auto-log: 2026-09-16 20:44 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/project_flow_marker_guard_vs_parser.md -->

<!-- auto-log: 2026-09-16 20:44 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/MEMORY.md -->

<!-- auto-log: 2026-09-16 20:54 commit "fix(flow): a goal the section had to shorten says so" -->

<!-- auto-log: 2026-09-16 20:59 commit "fix(flow): the new comment keeps its apostrophes paired" -->

<!-- auto-log: 2026-09-16 21:04 Write /Users/danielbentes/.claude-work/projects/-Users-danielbentes-synapti-marketplace/memory/feedback_grep_masks_test_failure.md -->

<!-- auto-log: 2026-09-16 21:17 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/forge.py -->

<!-- auto-log: 2026-09-16 21:19 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/cycle5-finding.txt -->

<!-- auto-log: 2026-09-16 21:21 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/project_flow_marker_guard_vs_parser.md -->

<!-- auto-log: 2026-09-16 21:21 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/MEMORY.md -->

<!-- auto-log: 2026-09-16 21:26 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/review-v3-integration.test.sh -->

<!-- auto-log: 2026-09-16 21:26 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/review-v3-integration.test.sh -->

<!-- auto-log: 2026-09-16 21:27 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/review-v3-integration.test.sh -->

<!-- auto-log: 2026-09-16 21:27 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/review-v3-integration.test.sh -->

<!-- auto-log: 2026-09-16 21:28 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/review-v3-integration.test.sh -->

<!-- auto-log: 2026-09-16 21:29 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-09-16 21:29 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-09-16 21:29 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-09-16 21:29 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-09-16 21:30 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/review-v3-integration.test.sh -->

<!-- auto-log: 2026-09-16 21:35 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-213.md -->

<!-- auto-log: 2026-09-16 22:04 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/review-v3-integration.test.sh -->

<!-- auto-log: 2026-09-16 22:21 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-213.md -->

<!-- auto-log: 2026-09-16 22:22 commit "fix(flow): a list the section cannot read is not a goal that names none" -->

<!-- auto-log: 2026-09-16 22:38 Write /Users/danielbentes/.claude-work/projects/-Users-danielbentes-synapti-marketplace/memory/feedback_sweep_the_defect_class.md -->

<!-- auto-log: 2026-09-16 22:39 Edit /Users/danielbentes/.claude-work/projects/-Users-danielbentes-synapti-marketplace/memory/feedback_test_the_check_not_the_defect.md -->

<!-- auto-log: 2026-09-16 22:39 Edit /Users/danielbentes/.claude-work/projects/-Users-danielbentes-synapti-marketplace/memory/MEMORY.md -->

<!-- auto-log: 2026-09-16 22:52 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-09-16 22:53 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/review-v3-integration.test.sh -->

<!-- auto-log: 2026-09-16 22:58 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-213.md -->

<!-- auto-log: 2026-09-16 22:58 commit "fix(flow): a specification the section cannot read is not an empty one" -->

<!-- auto-log: 2026-09-16 23:26 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/merge.md -->

<!-- auto-log: 2026-09-16 23:26 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/merge.md -->

<!-- auto-log: 2026-09-16 23:27 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/merge.md -->

<!-- auto-log: 2026-09-16 23:27 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-active-goal.sh -->

<!-- auto-log: 2026-09-16 23:27 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-active-goal.sh -->

<!-- auto-log: 2026-09-16 23:27 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-active-goal.sh -->

<!-- auto-log: 2026-09-16 23:28 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-active-goal.sh -->

<!-- auto-log: 2026-09-16 23:28 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-goal-record.sh -->

<!-- auto-log: 2026-09-16 23:28 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-goal-record.sh -->

<!-- auto-log: 2026-09-16 23:28 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-goal-record.sh -->

<!-- auto-log: 2026-09-16 23:29 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-active-goal.test.sh -->

<!-- auto-log: 2026-09-16 23:34 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-merge-seed.test.sh -->

<!-- auto-log: 2026-09-16 23:35 commit "fix(flow): a gate that cannot read its input does not pass" -->

<!-- auto-log: 2026-09-16 23:53 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/finding-confidence.test.sh -->
