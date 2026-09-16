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

- **Timeouts**: none added — no network or agent call is introduced. LSP probes keep the existing
  `lsp.timeout`; a probe that times out is reported as the tool that was used, not as zero callers.
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
