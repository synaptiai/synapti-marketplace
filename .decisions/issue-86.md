# Decision Journal — Issue #86

**Title**: feat(team-coordination): implement adversarial challenge phase for agentTeams reviews
**Status**: RFC drafting
**Branch**: feature/issue-86-challenge-protocol-rfc
**Created**: 2026-05-06

## Scope of this PR

Issue #86 AC#1 requires an RFC sub-issue to design the challenge-round protocol before implementation begins. This PR delivers ONLY the RFC. Production code (team-coordination/SKILL.md, commands/review.md, settings.json schema) is NOT modified here. After the RFC sub-issue is reviewed and merged, a follow-up `/flow:start` will implement ACs #2–#6 against the agreed design.

## Specification

### Non-goals

- **Does not modify production code** in `plugins/flow/skills/team-coordination/SKILL.md`, `plugins/flow/commands/review.md`, or `plugins/flow/settings.json` in this PR.
- **Does not change marker schemas** (`FLOW_REVIEW_CYCLE`, `FLOW_RESOLUTION_CYCLE`). If the challenge protocol requires schema extensions, the RFC names them as a follow-up dependency.
- **Does not implement the challenge protocol**. Implementation is deferred until the RFC sub-issue is closed/approved.
- **Does not change the default behavior** of `/flow:review`. `agentTeams` remains `false` by default.
- **Does not extend the trust boundary** — the challenge protocol does not relax the `markerTrust` filter introduced in PR #93.

### Failure modes

| Condition | Expected behavior |
|---|---|
| User rejects the RFC's recommended approach | Reopen design; revise the RFC; re-file as new sub-issue (do not amend the closed one). |
| User accepts the RFC but narrows scope ("implement only A and B, defer C") | Implementation sub-issue inherits the narrowed ACs verbatim; deferred items get their own follow-up. |
| RFC body exceeds GitHub issue body limit (~64 KB) | Split into linked sub-issues per design question; primary sub-issue links to the rest. |
| `.decisions/issue-86.md` and the GH sub-issue body diverge after edits | The journal in the repo is source-of-truth; sub-issue updates point to journal commits by SHA. |

### Interface contracts

- **Primary deliverable** — `.decisions/issue-86.md` (this file) contains the full RFC.
- **Secondary deliverable** — a GH sub-issue with title `RFC: adversarial challenge phase for agentTeams reviews` and body that mirrors §RFC below; this issue is the discussion surface.
- **Linkage** — the sub-issue body opens with `Tracks: #86`; #86 gets a comment linking to the sub-issue.

## Stranger Test

PASS — single deliverable, two artifacts (file + issue), zero code paths to follow. A zero-context agent given this journal can produce both artifacts without consulting any other file.

---

## RFC: adversarial challenge phase for agentTeams reviews

### Problem statement

`agentTeams: true` exists as a setting flag but `/flow:review` does not branch on it for paired-reviewer dispatch. The current "Path A" in `commands/review.md` mentions adversarial protocol generically (3 teammates, "challenge each other's findings") but specifies neither the pairing mechanism, the challenge prompt, the consolidation rules, nor the consolidated output schema. As written, an attendee who turns the flag on sees no behavioral difference. The slide deck (slides-v2.pdf p35) advertises a feature that does not exist.

This RFC proposes the missing design.

### Open design questions

#### Q1 — What does "paired reviewer" mean concretely?

Four options considered:

| ID | Mechanism | Cost | Independence quality | Implementation complexity |
|---|---|---|---|---|
| A | Same agent type spawned twice with **different system prompts** (e.g., code-reviewer-strict vs code-reviewer-pragmatic) | 2× | High — orthogonal lenses | Medium — need 2 prompt variants per facet |
| B | **Two different reviewer subtypes** per facet (e.g., security-reviewer + a new adversarial-security-reviewer agent) | 2× | Highest — distinct training/personas | High — need to author N adversarial agents |
| C | Same agent twice with **stochastic seed** (rely on sampling variance) | 2× | Low — both anchor on first plausible finding | Lowest — no new prompts/agents |
| D | Same agent but **split-evidence** (each sees a different file subset) | 2× | Medium — diverges by coverage but converges on common files | Medium — need diff-splitting logic |

**Recommendation: Option A** — paired prompts. Independence comes from explicit lens differences (e.g., one reviewer is told to assume the code is broken until proven otherwise; the other is told to assume the diff is correct and look only for missed edge cases). Lower cost than B (no new agent files), higher independence than C (not seed-dependent), simpler than D (no evidence partitioning).

Open sub-question: how many paired prompt variants per facet? Recommend 2 (skeptic + verifier) for v1; expandable later.

#### Q2 — How does the challenge round work?

Three options considered:

| ID | Mechanism | Anchoring risk |
|---|---|---|
| 1 | Each reviewer sees the OTHER's findings only (not the diff again) and labels each as `agree | disagree | refine` | Low — no fresh diff exposure means no new findings, just disposition |
| 2 | Each reviewer sees both finding sets + the diff and writes a free-form critique | High — second pass reads diff again, biased by first pass |
| 3 | A third "challenger" agent reads both finding sets and adjudicates without re-reading the diff | Lowest anchoring, but introduces a third opinion that can dominate |

**Recommendation: Option 1** — disposition-only challenge. Keeps the challenge round cheap (one prompt per reviewer per finding) and bias-controlled (no diff re-read). Output is a structured per-finding label.

Challenge prompt template (reviewer-A challenging reviewer-B's findings):

```
You are reviewer-A. Reviewer-B raised the following findings on the same diff
you reviewed independently. For each finding, respond with exactly one of:
  - AGREE: you also flagged this or you agree it is a real issue
  - DISAGREE: you believe this is not a real issue (give a one-line reason)
  - REFINE: real issue but priority/category differs (state the corrected
    priority/category)
Do NOT re-read the diff. Decide based on your prior independent analysis.

Findings to challenge:
{reviewer-B findings as a list with file:line, priority, category}
```

#### Q3 — Consolidation rules

Each finding ends up with a confidence label derived from disposition:

| Origin | Other reviewer's disposition | Consolidated confidence | Disposition annotation |
|---|---|---|---|
| Both reviewers raised it independently | n/a (auto-consensus on file:line match within ±2 lines, same facet, priority within ±1) | **HIGH** | `survived challenge (consensus)` |
| One raised, other AGREE | AGREE | **HIGH** | `survived challenge (validated)` |
| One raised, other REFINE | REFINE | **MEDIUM** | `survived challenge (refined)` — priority/category from REFINE response |
| One raised, other DISAGREE | DISAGREE | **LOW** | `challenged but kept` — both interpretations included |
| One raised, other did not respond (timeout/error) | none | **MEDIUM** | `unchallenged` |
| Both raised but later both DISAGREE'd in challenge | n/a | **DROPPED** | excluded from output, logged in journal |

**Match criteria for "both raised independently"**: same facet AND same file AND lines within ±2 AND priority within ±1 (P1↔P2 counts; P1↔P3 does not). Stricter matching produces more "single-raised" findings; looser matching produces more false consensus. ±2 / ±1 is the v1 default; tunable later.

#### Q4 — Output schema

Findings produced by the challenge protocol extend the existing P1/P2/P3 table with two columns:

```markdown
### P1 — Critical
| # | Category | Location | Issue | Fix | Confidence | Disposition |
|---|----------|----------|-------|-----|------------|-------------|
| F1 | security | src/auth.ts:42 | ... | ... | HIGH | survived challenge (consensus) |
| F2 | correctness | src/api.ts:88 | ... | ... | LOW | challenged but kept (B disagreed: "off-by-one is intentional") |
```

The `FLOW_REVIEW_CYCLE` marker schema is extended with optional confidence annotations (preserves backwards-compat — readers that ignore the new fields still parse correctly):

```
<!-- FLOW_REVIEW_CYCLE:{N} FINDINGS:[{ID}|{priority}|{category}|{file:line}|{status}|{confidence}|{disposition},...] -->
```

| Field | Backwards-compat |
|---|---|
| `confidence` | New. Old readers (parser at `references/finding-ledger-parser.md`) skip trailing pipe-fields; readers MUST tolerate variable field count. |
| `disposition` | New. Same compat rule. |

A schema migration sub-issue is filed during implementation to update `finding-ledger-parser.md`, `commands/status.md`, and `commands/merge.md` to read these fields when present.

#### Q5 — Fallback semantics

The challenge protocol must degrade gracefully. Failure-mode matrix:

| Condition | Behavior |
|---|---|
| `agentTeams: false` | Skip entirely. Use single-reviewer Path B (today's behavior). |
| `agentTeams: true` AND env var `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` unset | Single-line WARN to stderr: "agentTeams enabled but env var unset; falling back to single-reviewer". Use Path B. |
| `agentTeams: true` AND env var set, but a paired reviewer (A or B) fails to spawn for one facet | That facet uses single-reviewer fallback. Other facets continue paired. Note in output: "facet X: single-reviewer fallback (B failed to spawn)". |
| `agentTeams: true` AND env var set, but reviewer A or B times out (`timeouts.teammateTimeout`) | Use the responding reviewer's findings only for that facet. Mark as `unchallenged`. |
| `agentTeams: true` AND env var set, but BOTH reviewers fail for one facet | Re-dispatch with single-reviewer Path B for that facet. Note in output. |
| Challenge round itself fails (cannot dispatch challenger prompt) | Skip challenge step. Findings included as `unchallenged`. Do not block review. |

The iron rule: **a failure in the paired/challenge mechanism never blocks `/flow:review`**. It always falls back to producing some output, with annotations explaining what degraded.

#### Q6 — Cost / performance budget

Per `/flow:review` run, default 6-facet fan-out. Paired-reviewer cost:

- **Today (single-session)**: 6 facets × 1 reviewer = 6 LLM calls
- **Paired reviewers (no challenge)**: 6 × 2 = 12 calls
- **Paired + challenge round**: 12 + (6 × 2 challenges) = 24 calls
- **Paired + challenge + consolidation**: 24 + 1 synthesizer = 25 calls

≈ **4× the LLM cost** of today's review. This is the price of higher-confidence findings. The setting is opt-in (`agentTeams: false` by default) and gated behind an experimental env var, so users opt into the cost explicitly.

Performance: paired reviewers run in parallel (one parallel Agent dispatch with 12 calls). Challenge round runs in parallel per facet (6 parallel pairs). Wall-clock impact ≈ 1.5–2× single-session (not 4×) because of parallelism. Documented in implementation sub-issue.

### Recommended design (composite)

| Question | Choice |
|---|---|
| Q1 — pairing mechanism | **Option A** — paired prompts (skeptic + verifier) |
| Q2 — challenge mechanism | **Option 1** — disposition-only (AGREE / DISAGREE / REFINE) |
| Q3 — consolidation | Confidence labels via disposition table; matching window ±2 lines, ±1 priority |
| Q4 — output schema | Extend P1/P2/P3 table with Confidence/Disposition columns; extend `FLOW_REVIEW_CYCLE` marker with backwards-compat optional fields |
| Q5 — fallback | Per-facet graceful degradation; never block review |
| Q6 — cost | ≈4× LLM cost, ≈1.5–2× wall-clock; opt-in only |

### Implementation roadmap (deferred to follow-up sub-issues after this RFC closes)

1. **`team-coordination/SKILL.md` update** — document paired-reviewer + challenge-round protocol with prompt templates from §Q1, §Q2.
2. **`commands/review.md` Path A rewrite** — branch on `agentTeams && env var`; dispatch paired reviewers per facet; run challenge round; consolidate via §Q3 rules; emit §Q4 schema; honor §Q5 fallback.
3. **Marker schema migration** — extend `FLOW_REVIEW_CYCLE` per §Q4; update `references/finding-ledger-parser.md`, `commands/status.md`, `commands/merge.md` parsers to tolerate the new fields.
4. **End-to-end test** — synthetic PR with `agentTeams: true`; assert paired reviewer outputs, challenge round summary, consolidated table with confidence annotations, and that fallback to single-reviewer occurs when env var is unset.
5. **Slides reframe** — once #2 and #4 land, close issue #80 (slides reframe) and update slides-v2 to mark the feature as available with `agentTeams: true`.

### Open questions for reviewers

1. **Pairing variant count (Q1 sub-q)** — start with 2 prompt variants per facet (skeptic + verifier) or 3 (skeptic + verifier + boy-scout)? 3 is more rigorous but pushes cost to 6×.
2. **Match window tunability (Q3)** — should ±2 lines / ±1 priority be settings (`agentTeams.matchWindow.lines` / `agentTeams.matchWindow.priority`) or hard-coded for v1?
3. **Marker schema migration timing (Q4)** — ship the schema extension as a separate PR before implementation, or in the same PR as `commands/review.md` Path A?
4. **Challenger-as-third-agent (Q2 Option 3)** — defer to v2, or worth the experiment now?

### Scope explicitly out of this RFC

- Implementation team protocol (parallel implementation across teammates) — out of scope; this RFC covers review only.
- Cross-PR challenge (challenging findings from a previous PR's review) — out of scope.
- Human-in-the-loop challenge (asking the user to adjudicate disputed findings) — explicit non-goal; preserves the autonomous-with-escalation model.

---

## Decisions Log

### 2026-05-06 — Decision: RFC-only scope for this PR

User selected "Use #86 as the RFC drafting work" (from /flow:start 86 escalation). #86 itself becomes the RFC drafting deliverable; implementation is deferred to a follow-up sub-issue created after the RFC sub-issue closes.

### 2026-05-06 — RFC sub-issue filed: #94

Filed via `gh issue create` with body mirroring §RFC of this journal. URL: https://github.com/synaptiai/synapti-marketplace/issues/94. Issue #86 receives a follow-up comment noting the split: AC#1 is satisfied by the existence and approval of #94; ACs #2–#6 are blocked-by #94 and will be addressed in implementation sub-issues created after #94 closes.

<!-- auto-log: 2026-05-06 03:03 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-86.md -->

<!-- auto-log: 2026-05-06 03:04 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-86.md -->
