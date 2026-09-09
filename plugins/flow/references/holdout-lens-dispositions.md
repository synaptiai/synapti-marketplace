# Holdout Lens Dispositions (Path A consolidation)

Reference document for `skills/holdout-validation/SKILL.md`. When `commands/review.md` runs Path A (paired-reviewer protocol with `agentTeams: true`), the holdout-validation skill is dispatched twice in parallel with different lens prompts. This file holds the consolidation rules the A.4 step applies to those two result sets.

## Lenses

| Lens | Stance | What it flags |
|---|---|---|
| **Skeptic** | Self-review claims are unsupported until proven | Any claim where file evidence is thin or could be read more than one way; every `Source of expected` the test file does not visibly support |
| **Verifier** | Self-review claims are supported as a baseline | Missed cross-references the skeptic might overlook: the test exists but covers only the happy path; the error handler exists but does not propagate the cause; a risk-map row is cited but the cited input is degenerate for that row's plausible wrong version |

Both lenses read the same files, the same self-review claims, and the same evidence bundle subsections (`### Test inputs and expected values`, `### Risk map coverage`). They differ in priority calibration and in which thin-evidence cases get flagged.

## Marker disposition

Path A's A.4 consolidator treats holdout findings differently from agent findings:

| Lens behavior | Marker disposition |
|---|---|
| Both lenses raise the same finding (same file, line ±2, priority ±1) | `consensus` (HIGH confidence) |
| Only one lens raises the finding | `unchallenged` (MEDIUM confidence) — the lens divergence is itself a signal that the claim is ambiguously evidenced |

Holdout findings NEVER receive `validated`, `refined`, or `kept` dispositions because those are outputs of the A.3 challenge round, which holdout findings do not participate in. Adversarial challenge (AGREE/DISAGREE/REFINE) exists for subjective judgment about priority and severity. Holdout findings are objective claim-verification — the file state is the arbiter, not reviewer opinion. Asking a challenger to DISAGREE with "the file does not contain test X" produces either vacuous AGREE responses or DISAGREE responses with no basis. See `commands/review.md` A.1 and `skills/team-coordination/SKILL.md` Phase 3 for the full rationale.

## Path B

In Path B (single-session, default), the skill is invoked once with no lens prompt and emits findings with `unchallenged` disposition by default — there is no second lens to reach consensus against.
