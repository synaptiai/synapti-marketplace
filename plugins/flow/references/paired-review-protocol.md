# Paired-Review Protocol (agent teams)

Reference document. The full paired-reviewer + challenge-round protocol that `commands/review.md` Path A executes when `agentTeams: true` and `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is set. `skills/team-coordination/SKILL.md` states the rules; this file carries the tables the command applies verbatim (cost expectation, per-phase dispatch, challenge prompt, consolidation rules, marker shape, fallback matrix). The protocol is the contract frozen in `.decisions/issue-86.md`.

## Cost expectation

Per `/flow:review` run with default 6-facet fan-out:

| Phase | LLM calls |
|-------|-----------|
| Phase 1 — Independent Analysis (5 agent facets × 2 + 2 holdout-validation Skill calls) | 12 |
| Phase 2 — Share findings (lead-only orchestration; no LLM call) | 0 |
| Phase 3 — Challenge (each Agent reviewer challenges the other's findings, 5 × 2; holdout-validation excluded — see review.md A.1 note) | 10 |
| Phase 4 — Synthesize (main agent, 1 consolidation pass) | 1 |
| Phase 5 — Emit consolidated output (lead-only; no LLM call) | 0 |
| **Total** | **≈23 calls** (≈3.8× single-session baseline of 6) |

Wall-clock: ≈1.5–2× single-session via parallel dispatch within each phase. The cost is opt-in (`agentTeams: false` by default) and gated behind `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`.

## Phase 1: Independent Analysis (paired reviewers per facet)

For each facet, dispatch **two** subagents with orthogonal prompt lenses. Both run in parallel and never see each other's findings during this phase.

| Variant | System-prompt lens |
|---------|---------------------|
| **skeptic** | "Assume the diff is broken until proven otherwise. Flag every behavior you cannot prove correct from the code as written." |
| **verifier** | "Assume the diff is correct as a baseline. Look only for missed edge cases, undocumented contract assumptions, or invariants that aren't enforced." |

Default 6-facet topology (12 invocations in one parallel dispatch — 5 Agent pairs and 2 Skill calls):

```
Agent(security-reviewer-skeptic) | Agent(security-reviewer-verifier)
Agent(code-reviewer-skeptic) | Agent(code-reviewer-verifier)
Agent(convention-checker-skeptic) | Agent(convention-checker-verifier)
Agent(test-runner-skeptic) | Agent(test-runner-verifier)
Agent(error-handler-inspector-skeptic) | Agent(error-handler-inspector-verifier)
Skill(holdout-validation) [skeptic lens] | Skill(holdout-validation) [verifier lens]
```

The holdout-validation pair is dispatched as Skills (not Agents) because the project does not define a `holdout-validation` agent — the skill IS the contract. The holdout-validation pair contributes findings to A.2 auto-consensus matching but is **excluded from the Phase 3 challenge round** by design, not because Skills lack a challenger prompt pattern.

The principled rationale: adversarial challenge (AGREE/DISAGREE/REFINE) exists for findings where reviewers can hold legitimately different subjective opinions about priority, severity, or category. Holdout findings are categorically different — they are objective claim-verification (file state vs self-reported claim). The file state is the arbiter, so DISAGREE is not a meaningful disposition. Including holdout in challenge would produce vacuous AGREE responses (re-check confirms what we already established) or confuse the protocol (DISAGREE based on what?). See `commands/review.md` A.1 for the full rationale.

Holdout findings carry their own confidence model: `consensus` when both lenses raised the same finding independently, `unchallenged` when only one lens raised it (signal: the lenses parsed the same claim differently or weighted scenario priority differently). They NEVER carry `validated` / `refined` / `kept` — those dispositions are challenge-round outputs.

Each returns P1/P2/P3 findings with `file:line` citations and a category. **No challenge information is included in this phase** — outputs are independent.

## Phase 2: Share Findings

Lead collects all 12 finding sets (10 Agent + 2 Skill). No LLM call. Indexes findings by facet for the per-facet challenge round. Holdout-validation findings are indexed for A.2 auto-consensus matching only and bypass Phase 3.

## Phase 3: Challenge (disposition-only, no diff re-read)

For each facet, dispatch each variant to challenge the OTHER variant's findings. **The challenger does NOT re-read the diff.** The challenger labels each of the other's findings with one of three dispositions:

| Disposition | Meaning |
|-------------|---------|
| `AGREE` | Challenger also flagged this OR confirms it as a real issue |
| `DISAGREE` | Challenger believes this is not a real issue (must give a one-line reason) |
| `REFINE` | Real issue, but priority/category differs (challenger states the corrected priority/category) |

Challenge prompt (issued per facet, both directions in parallel):

```
You are reviewer-{A|B} for facet {facet}. Reviewer-{B|A} raised the following
findings on the same diff you reviewed independently. For each finding, respond
with exactly one line:

  {finding-id} AGREE
  {finding-id} DISAGREE: {one-line reason}
  {finding-id} REFINE: priority={P1|P2|P3} category={text}

Do NOT re-read the diff. Decide based on your prior independent analysis only.

Findings to challenge:
{list of the OTHER reviewer's findings: ID, file:line, priority, category}
```

10 challenge prompts run in parallel (5 agent facets × 2 directions; the holdout-validation Skill pair is excluded by design — see A.1 note for the principled rationale: holdout is objective claim-verification, not subjective judgment, so AGREE/DISAGREE/REFINE doesn't apply).

## Phase 4: Synthesize (consolidation rules)

Lead applies the consolidation table to each finding:

| Origin | Other reviewer's disposition | Consolidated confidence | Disposition vocab |
|--------|------------------------------|-------------------------|-------------------|
| Both raised independently (file ±2 lines, priority ±1) | n/a | **HIGH** | `consensus` |
| One raised, other AGREE | AGREE | **HIGH** | `validated` |
| One raised, other REFINE | REFINE | **MEDIUM** | `refined` (priority/category from REFINE) |
| One raised, other DISAGREE | DISAGREE | **LOW** | `kept` |
| One raised, other timed out / errored | none | **MEDIUM** | `unchallenged` |
| Both raised, both DISAGREE'd in challenge | n/a | **DROPPED** | excluded; logged in journal |

**Independence-match window** (hard-coded for v1): same facet AND same file AND lines within ±2 AND priority within ±1 (P1↔P2 counts; P1↔P3 does not).

The disposition vocabulary `consensus|validated|refined|kept|unchallenged` is the controlled set emitted into the `FLOW_REVIEW_CYCLE` marker — see `references/finding-ledger-parser.md` for the marker schema.

## Phase 5: Emit consolidated output

Lead writes the per-priority finding tables, folding confidence and disposition into the Finding cell as a trailing `_(confidence · disposition)_` suffix:

```markdown
### P1 — Critical
| Finding | Suggested Fix |
|---------|---------------|
| **F1 · security · `src/auth.ts:42`**<br>... _(HIGH · consensus)_ | ... |
| **F2 · correctness · `src/api.ts:88`**<br>... _(LOW · kept — B disagreed: "off-by-one is intentional")_ | ... |
```

And the extended `FLOW_REVIEW_CYCLE` marker (7 fields per row; example exercises three disposition values):

```
<!-- FLOW_REVIEW_CYCLE:{N} FINDINGS:[F1|P1|security|src/auth.ts:42|open|HIGH|validated,F2|P2|correctness|src/api.ts:88|open|MEDIUM|refined,F3|P1|race|src/job.ts:17|open|LOW|kept] -->
```

DROPPED findings do NOT appear in the marker; they are logged in the decision journal under `## Dropped after challenge` for traceability.

## Cognitive Bias Awareness

- **Anchoring**: A reviewer who reads another's findings before producing their own anchors on them. Phase 1 is strictly independent for this reason; the challenge round in Phase 3 explicitly forbids diff re-read so the reviewer cannot synthesize fresh "agreements" from re-reading.
- **Groupthink**: Confidence-HIGH-on-everything is a smell, not a goal. A healthy review surfaces some `kept` (challenged but disagreed) findings.
- **Central-judge bias**: The protocol intentionally has no third-agent challenger and no main-agent adjudicator. The lead consolidates mechanically via the table above; it does not opine on which finding is "really" correct.

## Fallback Semantics (per-facet graceful degradation)

A failure in the paired/challenge mechanism **never blocks `/flow:review`**. Per-facet matrix:

| Condition | Behavior |
|-----------|----------|
| `agentTeams: false` | Skip paired protocol entirely. Emit `Path A skipped: agentTeams=false. Using Path B (single-session).` to stdout and use single-reviewer dispatch (the `commands/review.md` Path B fallback). |
| `agentTeams: true` AND env var `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` unset | Single-line `WARN` to stderr: `agentTeams enabled but env var unset; using single-reviewer fallback`. Use Path B. |
| `agentTeams: true` AND env var set, but one variant (skeptic OR verifier) fails to spawn for one facet | That facet uses single-reviewer fallback (the responding variant). Other facets continue paired. Note in output: `facet {facet}: single-reviewer fallback (verifier failed to spawn)`. |
| Variant times out (`timeouts.teammateTimeout`) | Use the responding variant's findings only for that facet. Mark each finding as `unchallenged` (MEDIUM confidence). |
| BOTH variants fail for one facet | Re-dispatch with single-reviewer Path B for that facet. Note in output. |
| Challenge round itself fails (cannot dispatch challenger prompt) | Skip challenge step. Findings included as `unchallenged`. Do not block review. |

