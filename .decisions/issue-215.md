---
issue: 215
created: '2026-09-22T00:00:00Z'
artifacts:
- type: specification
  captured_at: '2026-09-22T00:00:00Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: review-cycle
  captured_at: '2026-09-23T09:45:44Z'
  cycle: 4
  path: B
  findings_count: 19
  pr: 251
- type: review-cycle
  captured_at: '2026-09-23T11:30:54Z'
  cycle: 5
  path: B
  findings_count: 21
  pr: 251
- type: review-cycle
  captured_at: '2026-09-23T12:55:21Z'
  cycle: 6
  path: B
  findings_count: 23
  pr: 251
- type: review-cycle
  captured_at: '2026-09-23T14:07:45Z'
  cycle: 7
  path: B
  findings_count: 24
  pr: 251
- type: review-cycle
  captured_at: '2026-09-23T15:36:02Z'
  cycle: 8
  path: B
  findings_count: 24
  pr: 251
- type: review-cycle
  captured_at: '2026-09-23T17:33:14Z'
  cycle: 9
  path: B
  findings_count: 31
  pr: 251
- type: review-cycle
  captured_at: '2026-09-23T21:10:29Z'
  cycle: 10
  path: B
  findings_count: 22
  pr: 251
- type: review-cycle
  captured_at: '2026-09-23T22:38:35Z'
  cycle: 11
  path: B
  findings_count: 23
  pr: 251
- type: review-cycle
  captured_at: '2026-09-23T23:34:06Z'
  cycle: 12
  path: B
  findings_count: 25
  pr: 251
- type: review-cycle
  captured_at: '2026-09-24T00:32:48Z'
  cycle: 13
  path: B
  findings_count: 26
  pr: 251
---
# Decision Journal — Issue #215 (with #216)

**Title:** an evidence-grounded critic pass for the default review fan-out (#215), and the review-precision eval that will decide its default (#216)
**Branch:** feature/issue-215-216-grounding-critic-and-review-eval
**Started:** 2026-09-22

The two issues ship as one change because neither is finished without the other: the critic
is shipped `off`, and the only thing that may turn it on is a reading of the eval's summary
table.

## Specification

### Non-goals

- Path A (the experimental agent-teams path) is not touched. Its A.3 challenge round keeps
  its AGREE / DISAGREE / REFINE vocabulary, its "do not re-read the diff" instruction and
  its consolidation table. Aligning A.3 with the constrained grammar is a separate change
  that waits for eval numbers.
- P3 findings never enter the critic, and the critic never sees a finding it could only
  re-rank: it cannot propose a priority, a category, a fix, or a finding of its own.
- The `FLOW_REVIEW_CYCLE` marker keeps seven fields and the rendered suffix keeps two terms
  (`_(CONFIDENCE · disposition)_`). `grounding` is a synthesis-time field and a journal
  field; it does not enter either parsed surface.
- No new review path. The grounding pass is a step inside the existing Path B fan-out, not
  an alternative to it.
- #216 AC5 — a recorded two-model run checked in under `evals/results-<date>-review/` — is
  not performed here. See "AC5 is parked" below.
- The review eval does not exercise `/flow:review`'s `gh pr` steps. The scratch repository
  has no GitHub remote; the session reviews a branch diff.

### Failure modes

- **Critic unavailable** (agent fails to spawn, times out, returns nothing): the findings
  pass through unchanged, every one of them, at the confidence synthesis already gave it.
  A grounding pass that cannot run never removes a finding.
- **Critic answers off-grammar**: a line that is not `<id> AGREE`,
  `<id> DISAGREE_EVIDENCE: <file:line> <what the code shows>` or
  `<id> DISAGREE_CONCERN: <objection>` is *no verdict for that finding*. A finding with no
  verdict is treated exactly as a finding the critic never saw. This is the 0.457 result
  made operational: an unconstrained disagreement cannot cost a finding its place.
- **Critic answers about a finding that does not exist, or re-prioritizes**: the line is
  discarded. The critic's output is read as verdicts keyed by finding id and nothing else.
- **Reviewer re-pass answers without a citation**: the finding is dropped and journaled.
  This is the only path by which the critic removes anything, and it needs the reviewer's
  own agreement, not the critic's assertion.
- **Setting malformed** (`true`, `1`, `"yes"`, empty): the gate warns on stderr and resolves
  to `off`. Silent coercion of `true` to `on` would turn a typo into a behaviour change and
  into spend.
- **Eval: variant cannot be materialized into the reference** (see below): the case is
  reported by `--check-cases --mode review` and excluded, never scored. A review case whose
  diff is the whole file measures nothing, so it must fail loudly rather than score 1.0.
- **Eval: session ends without a parseable findings block**: the run is scored as a miss
  with a `reason`, never as a clean zero-findings review.

### Interface contracts

- **`agents/finding-critic.md` frontmatter**: `tools: Read, Grep, Glob, LSP`, `memory: none`,
  `skills: evidence-based-development`, `model: inherit`. No Write, Edit or Bash: a critic
  that can change the tree is not auditing the tree.
- **Critic input**: the consolidated P1/P2 findings as `id`, `priority`, `category`,
  `location`, `problem`, plus the diff scope. Not the reviewer's rationale.
- **Critic output**: exactly one line per finding, in the three-verdict grammar above.
- **Re-pass rule, identical for both disagree forms**: cite `file:line` or drop. A surviving
  finding carries `grounding: agreed` (critic AGREE'd) or `grounding: cited` (reviewer
  answered with a citation) and confidence HIGH.
- **Journal**: a dropped finding is a `dropped-finding` artifact with
  `reason=critic-evidence` or `reason=critic-unrefuted-concern`.
- **Setting**: `review.groundingCritic`, `"off" | "on"`, default `"off"`, resolved through
  `bin/cascade-resolve.sh` like every other flow setting.
- **`flow-eval-run.sh --mode review`**: per case and trap, a scratch repository whose default
  branch holds the reference implementation as `<module>.py` and whose feature branch holds
  the materialized variant as the same file. Arms `review-b` and `review-b-critic`.
- **`_flow_eval.py score-review --case <dir> --trap <name> --findings <json>`**: prints
  `{"hit": bool, "hits": n, "false_findings": n, "reason": <string|null>, ...}`. A run is a
  hit when at least one P1/P2 finding cites the module and a line inside a changed hunk;
  every other P1/P2 finding is a false finding; P3 findings are neither.

### What the trap variants actually are, and what that cost

The issue says the reference→variant diff is the seeded defect. It is not. Every variant
under `evals/<case>/hidden/traps/` opens with `from reference_impl import *` and redefines
one or two names; `ceil_split.py` is 16 lines against a 63-line reference. Committing the
reference on one branch and that file on the other produces a diff that replaces the whole
module — every line is inside a hunk, so every finding that names the module is a hit and
precision and recall are 1.0 regardless of what the reviewer saw. That is a measurement
artefact, not a review result.

So the variant is **materialized** before it is committed: the reference's source with the
variant's redefined top-level statements substituted in place (and the variant's new names
appended), plus `import reference_impl as _ref` when the variant delegates to the original.
`reference_impl.py` is committed unchanged on both branches, so it never enters the diff.
The resulting branch diff touches only the seeded defect, which is what a hit has to be
measured against.

Two refinements the implementation added. Most variants do not redefine a top-level name at
all: they subclass one of the reference's classes and override one method, then rebind the
public functions through an instance of the subclass. Substituting such a class wholesale
replaced the reference's 45-line class with a 5-line subclass — the same whole-file diff by
another route. So an overridden method is written into the reference's class where that
method is defined, and the statements that only existed to install the subclass are dropped;
the reference's own wiring already reaches the patched method. Dropping them is verified
rather than assumed: `--check-cases --mode review` runs the hidden suite against the
materialized module and requires the same tests to fail as the stored variant. All 34
shipped variants pass that check, and the diff is now 1 to 15 lines, 6% of the module.

Second, the module docstring is stripped from both branches. Every reference opens by naming
the hidden suite and the trap variants under `hidden/traps/`, which tells the reviewer it is
being tested. It is stripped from the reference and the materialized variant alike, so the
diff is unchanged. One tell remains that the harness cannot remove: 15 of the 34 variants
call back into `reference_impl`, so the module under review still names it. Those are
recorded in `traps.json` as `delegates_to_reference` rather than quietly included.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| The critic's grammar is the whole result | The critic may disagree in free text, or a bare `DISAGREE:` line is honoured. The paper measures that configuration at F1 0.457 — *worse* than no critic at all (0.495) — so an implementation that accepts it is worse than the one it replaces, while looking like the improvement | Feed the grounding step a critic line `F1 DISAGREE: I do not think this is real` → right: the finding survives untouched, and both command files say an off-grammar line is no verdict; wrong: the text permits a bare DISAGREE, or omits the rule |
| Who may remove a finding | The critic's `DISAGREE_EVIDENCE` drops the finding directly, because the critic cited code and the reviewer's answer looks like a formality | Read the re-pass rule in both commands → right: only a reviewer reply without a citation drops it, and `DISAGREE_CONCERN` needs the reviewer to *fail* to cite; wrong: any text that lets the critic's line be terminal |
| Setting parsing | `"true"` is accepted as on (JSON-ish coercion), or an unknown value silently enables the pass | Extracted gate block with the resolver stubbed to `true`, `1` and `""` → right: `GROUNDING_CRITIC=off` and a WARN on stderr each time; wrong: `on`, or a silent `off` |
| Marker and suffix compatibility | `grounding` is appended to the marker row or to the `_(HIGH · consensus)_` suffix, and `flow-finding-route.sh` and the merge-gate parsers start reading a field that is not theirs | Assert the marker row shape stays seven fields and the documented suffix stays two terms, and run the existing ledger-parser suites → right: unchanged; wrong: an 8th field appears |
| Eval hit measurement | `changed_lines` is taken from a whole-file replacement diff, so recall is 1.0 for any reviewer that names the file — the degenerate run that reads as a triumph | `score-review` fixtures: a P1 on the right file but outside every hunk must score `false`, and a P1 on a different file must score `false` → right: 0 hits; wrong: a hit, which is what a whole-file diff produces |
| Eval completeness | A session that ends without a findings block is scored as a clean review with zero findings, which reads as perfect precision | Fixture with malformed JSON → right: miss with a `reason`; wrong: `hit=false, false=0` indistinguishable from a careful reviewer |

## AC5 is parked

#216's fifth acceptance criterion — one recorded run on two models checked in under
`evals/results-<date>-review/`, with the parent issue's `review.groundingCritic` decision
citing it — is deliberately not done in this change, and its box stays unchecked. The run
costs real money across two model families, and that spend has not been decided by the
repository owner. Everything the run needs is built and tested offline here: the mode, the
dry run, the case check, the scorer, the summary shape and the reading rule. When the spend
is approved the run is a single command, and the decision on the default is the reading of
its summary table. Until then `review.groundingCritic` stays `off`, which is the state the
absence of numbers argues for anyway.
