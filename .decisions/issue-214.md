---
issue: 214
created: '2026-09-17T00:05:00Z'
branch: feature/issue-214-dismissed-findings-become-exceptions
artifacts:
- type: specification
  captured_at: '2026-09-17T07:19:17Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: goal-created
  captured_at: '2026-09-17T07:23:51Z'
  goal_id: issue-214
  source: issue-214-body
- type: workflow-run
  captured_at: '2026-09-17T07:27:22Z'
  workflow: start-issue
  run_id: 2026-09-16T235523Z-issue-214
  status: active
---
# Decision Journal — Issue #214

feat(flow): dismissed findings become durable review exceptions instead of vanishing

## Specification

### Non-goals

- An embeddings store. The issue names LanceDB and SQLite vectors and rejects both: the corpus is
  tens of rules per project, and an embedding query is a network call, which
  `bin/flow-mine-corrections.sh` rules out by design. Plain text in context does the same job at
  this scale.
- A fine-tuned rejection predictor. A LoRA classifier cannot ship inside a markdown plugin.
- Suppressing security findings. An exception annotates a security finding and names itself; it
  never removes one. `security-reviewer` keeps reporting regardless.
- A review run writing `.flow/review-exceptions.md`. The file is a team contract, written by hand
  or by promoting a `/flow:learn` proposal. No review or address run edits it.
- Cross-repository exceptions. An exception is scoped to the project whose team dismissed the
  finding; nothing is shared between repositories.
- Re-opening the finding-ledger marker grammar. `DISPUTED:[...]` already exists in
  `templates/resolution-comment.md` and in `references/finding-ledger-parser.md`; this issue fills
  it and adds nothing to the grammar.

### Failure modes

- **Timeouts**: one new `gh api` call per `/flow:review` and `/flow:pr` Phase 1 — the exceptions
  file read at the base commit. It carries no explicit timeout, matching every other `gh` call in
  those fences. A call that fails or hangs reports `STATE=unavailable`, never `STATE=none`, because
  "there are no exceptions" is the answer that lets a reviewer raise a finding the team already
  rejected.
- **Partial failures**: an exceptions file that exists but does not parse as the documented table
  reports `STATE=unavailable` with the reason and the rows it could read are not handed over
  half-complete. A `bin/journal-record.sh` failure while writing `finding-dismissed` must not fail
  the address run — the precedent is the trust-ledger note in `pr.md`, which reports the failure and
  continues.
- **Invalid input**: a `reason` outside the closed set, or a table row missing a column, is named in
  the output rather than dropped. A PR that closes no issue has no journal to write to; the existing
  `dropped-finding` blocks skip with a message and this follows them.
- **Missing context**: a PR with no `FLOW_REVIEW_CYCLE` marker has no ledger ids, so a Pushback item
  cannot be keyed to one. That is reported as the reason the artifact was not written, not as a
  dismissal with an invented id.

### Interface contracts

- `finding-dismissed` journal artifact: `pr: <int>`, `cycle: <int>`, `finding_id: <string>`,
  `category: <string>`, `location: <string>`, `by: address|review`, `reason: <closed set>`,
  `evidence: <string>`. The closed set is `factually-incorrect`, `breaks-test`,
  `contradicts-claude-md`, `critic-evidence`, `critic-unrefuted-concern`, `self-review-refuted`.
- `.flow/review-exceptions.md`: a table `| Rule | Scope (path glob) | Why | Source |`, tracked in
  git alongside goals.
- `### Review Exceptions` section printed by `/flow:review` and `/flow:pr` Phase 1:
  `STATE=ok|none|unavailable`, `EXCEPTIONS_REF=<base sha>`, one `EXCEPTION=<rule>|<glob>|<why>|<source>`
  line per row, and `REASON=` when unavailable. A literal `|` inside a value is written `%7C`, as the
  FlowGoal section does.
- `templates/skill-proposal.md` frontmatter gains `type: skill|enforcement|exception`.
  `bin/promote-proposal.sh` branches on it: `skill` and `enforcement` promote to `skills/learned/`,
  `exception` appends its row to `.flow/review-exceptions.md`, and an unknown type is refused.
- Every reviewer dispatch carries the exceptions plus the rule: do not raise a finding that matches
  a listed exception; if you raise it anyway, label it `exception-override` and say why.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Exception trust | The exceptions are read from the pull request head or the working tree, so a pull request grants itself an exemption | A fixture whose base and head hold different exceptions files: the base rule is printed and the head-only rule does not appear anywhere in the section |
| Absent vs unreadable | A failed read prints `STATE=none`, telling every reviewer there are no exceptions when the team wrote several | A 403 or 5xx prints `STATE=unavailable` naming the status; only a 404 at the base commit is `STATE=none` |
| Security suppression | An exception matching a security finding removes it from the report | A security finding whose text matches a listed exception is still reported, labelled `exception-override`, with the matching exception named |
| Dispatch coverage | The exceptions reach some dispatch blocks and not others — the existing `Risk areas:` triplet is in 3 of 27 prompts today | A parity test asserts all four fan-out blocks (review Path A, review Path B, pr Phase 3, address Phase 4) carry the exceptions text |
| Dismissal identity | `finding_id` is recorded as a GitHub comment id, so clusters cannot join to the ledger and `DISPUTED` stays empty | A dismissed finding carries the same ledger id in the artifact and in the `DISPUTED:[...]` array of the resolution marker |
| Proposal reachability | `exception` proposals are written but nothing can promote them, so the loop never closes | `promote-proposal.sh` on a `type: exception` proposal appends its row to `.flow/review-exceptions.md` and leaves `skills/learned/` untouched |

## Decisions (user, 2026-09-17)

Four questions the issue's Resolution section assumed but the codebase did not support. Each was
put to the user with the codebase evidence; the answers expand the issue's original six acceptance
criteria to eight, and the issue body was updated before the goal was built from it.

- **Dismissal identity**: parse the `FLOW_REVIEW_CYCLE` markers in `/flow:address` Phase 1 so a
  Pushback item carries a real ledger id, and fill the `DISPUTED:[...]` array that
  `templates/resolution-comment.md` already defines and `/flow:merge` already gates on. The
  alternative — recording the GitHub comment id — was rejected because a comment id is not stable
  across cycles and cannot be joined to the ledger, which is what clustering needs.
- **Base read**: the contents API at the base commit (`gh api -i "…/contents/…?ref=<base sha>"`)
  rather than `git show origin/<base>:<path>`. This was not the recommended option — `git show` is
  offline and costs nothing — but the API reuses the absent-versus-unreadable handling already built
  and tested in `review.md`, where a 404 and a 403 are told apart by protocol rather than by the
  wording of an error message. The cost is a network call per review and no offline path, and the
  failure is reported rather than silent.
- **Dispatch scope**: include `/flow:address` Phase 4, which the acceptance criteria did not name,
  and add a parity test over all four fan-out blocks. `address.md` documents its duplicated reviewer
  roster deliberately so drift is locally verifiable; threading the exceptions into three of four
  blocks would recreate exactly the drift that comment warns about.
- **Proposal type**: make the informal type axis explicit as a `type:` frontmatter key and teach
  `promote-proposal.sh` both targets. Today the type is a filename suffix plus a marker section, and
  the promoter assumes every proposal becomes a `skills/learned/` skill. An `exception` proposal
  that nothing can promote is a proposal that does nothing.
- **Matching semantics**: the `Scope (path glob)` column gates mechanically — the finding's file
  must match the glob or the exception does not apply at all — and the free-text `Rule` is judged by
  the reviewing model against the finding. A reviewer that raises a matching finding anyway labels
  it `exception-override` and says why, so a wrong match is visible in the output rather than
  silent. The alternatives were a glob-only annotation, which does not stop the recurrence this
  issue exists to stop, and an explicit `Match` pattern column, which changes the file schema the
  issue specified and pushes teams toward brittle patterns that miss the same finding phrased
  differently. The glob is what bounds the blast radius: no free-text match can fire outside the
  paths the team named.

  This was settled after `.flow/goals/issue-214.goal.yaml` was written, and
  `bin/flow-goal-record.sh` offers `--create` and `--update-lifecycle` only — there is no sanctioned
  path to amend an active goal's `specification`. The contract therefore lives here, and the goal
  carries the eight acceptance criteria that depend on it. Worth noting as a property of flow
  rather than of this issue: a specification element settled during PLAN cannot reach the goal it
  belongs in.

<!-- auto-log: 2026-09-17 09:18 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-214.md -->

<!-- auto-log: 2026-09-17 09:38 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-214.md -->

<!-- auto-log: 2026-09-17 09:39 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/references/decision-journal-schema.md -->

<!-- auto-log: 2026-09-17 09:39 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/references/decision-journal-schema.md -->

<!-- auto-log: 2026-09-17 09:42 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/address.md -->

<!-- auto-log: 2026-09-17 09:42 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/address.md -->

<!-- auto-log: 2026-09-17 09:44 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/address.md -->

<!-- auto-log: 2026-09-17 09:45 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/address.md -->

<!-- auto-log: 2026-09-17 09:45 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/address.md -->

<!-- auto-log: 2026-09-17 09:47 commit "feat(flow): a rejected finding is recorded, not just replied to" -->

<!-- auto-log: 2026-09-17 09:49 Write /Users/danielbentes/synapti-marketplace/plugins/flow/tests/review-exceptions.test.sh -->

<!-- auto-log: 2026-09-17 09:51 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/review.md -->

<!-- auto-log: 2026-09-17 09:52 Write /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-review-exceptions.sh -->

<!-- auto-log: 2026-09-17 09:54 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/pr.md -->

<!-- auto-log: 2026-09-17 09:54 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/commands/pr.md -->

<!-- auto-log: 2026-09-17 10:00 commit "feat(flow): reviewers are handed the rules the team already rejected" -->

<!-- auto-log: 2026-09-17 10:05 Write /Users/danielbentes/synapti-marketplace/plugins/flow/tests/learn-dismissal-patterns.test.sh -->

<!-- auto-log: 2026-09-17 10:11 commit "feat(flow): a dismissal that repeats becomes a rule the reviewers are given" -->

<!-- auto-log: 2026-09-17 10:23 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/gen_hostile.py -->

<!-- auto-log: 2026-09-17 10:26 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/rx/mk.py -->

<!-- auto-log: 2026-09-17 10:28 Write /private/tmp/claude-501/-Users-danielbentes-synapti-marketplace/7278d682-9ed8-40c5-9b13-61da01c78c4a/scratchpad/alias/mk_alias.py -->

<!-- auto-log: 2026-09-17 10:33 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-error-handler-inspector/project_flow_unavailable_collapse.md -->

<!-- auto-log: 2026-09-17 10:35 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/project_flow_marker_guard_vs_parser.md -->

<!-- auto-log: 2026-09-17 10:35 Edit /Users/danielbentes/synapti-marketplace/.claude/agent-memory/flow-code-reviewer/MEMORY.md -->

<!-- auto-log: 2026-09-17 10:54 commit "fix(flow): the exceptions a reviewer is given come from a ref the author cannot choose" -->
