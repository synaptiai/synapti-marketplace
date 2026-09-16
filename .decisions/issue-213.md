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
- **Partial failures**: a goal file that exists but does not parse (malformed YAML, missing
  `python3`, missing `yaml` module) yields `STATE=unavailable` with the reason, and the review falls
  back to the issue-text path. It never reports `STATE=none`, which would say "no goal exists" about
  a goal that does exist.
- **Invalid input**: a goal with zero acceptance criteria, or with no risk map, is valid input —
  the risk rows are then derived from the issue text and every row carries `source=issue-text`
  (user decision, 2026-09-16). A goal whose own file is modified by the pull request under review
  raises a finding naming the file and what changed.
- **Missing context**: no linked issue on the pull request means no goal path to resolve, which is
  `STATE=none` and today's behaviour.

### Interface contracts

- `### FlowGoal` section (Phase 1, printed): `STATE=ok|none|unavailable`, `GOAL_PATH=`,
  `GOAL_STATUS=`, `AC=<id>|<text>|<verification_command>` (one per criterion, the command printed
  verbatim and never executed), `NON_GOAL=<text>`, `CONTRACT=<text>`,
  `RISK_MAP=<area>|<plausible_wrong_version>|<discriminating_check>|<source>` where `source` is
  `goal` or `issue-text`, and `GOAL_EDITED=yes|no` for whether the diff modifies the goal file.
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
| Goal trust | A pull request that weakens its own acceptance criteria passes unflagged | A diff that modifies `.flow/goals/issue-213.goal.yaml` sets `GOAL_EDITED=yes` and raises a finding naming the file; a diff that does not sets `GOAL_EDITED=no` |
| Risk-map provenance | Rows derived from issue text are presented as if the team wrote them | With a goal carrying no risk map, every `RISK_MAP=` row ends `|issue-text`, and with the fixture goal's one row it ends `|goal` |
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

<!-- auto-log: 2026-09-16 12:26 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/goal213.py -->

<!-- auto-log: 2026-09-16 12:29 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/ac1_tests.py -->

<!-- auto-log: 2026-09-16 12:30 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/ac1_impl.py -->
