---
description: "Build the full documentation package from evidence. Inventories sources, models the project, resolves material gaps, drafts the 21 internal documents in dependency waves, then derives the 2 public documents from approved claims only."
argument-hint: [--only <dir-or-file>] [--max-drafters <n>]
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Skill, Agent, AskUserQuestion, TaskCreate, TaskList, TaskUpdate
---

# Build Documentation Baseline: $ARGUMENTS

Phases 0 through 5 of the documentation protocol. Produces a complete, evidence-cited package. Verification is `/dossier:audit`.

<!--
PARALLEL EXECUTION RULE: dispatch each drafting wave's agents in a SINGLE
message with multiple Agent calls. Sequential dispatch serializes waves that
have no dependency on each other and triples wall-clock for no benefit.
-->

## Required Skills

- `engagement-scoping` — Phase 0: resolve and freeze scope, ceiling, and inspection batches
- `evidence-ledger` — Phase 1: claim states, source authority, executed checks
- `project-modeling` — Phase 2: the canonical model, terminology, and end-to-end traces
- `gap-and-contradiction-register` — Phase 3: classify and route material gaps
- `doc-package-contract` — Phase 4: per-document contracts and headers
- `disclosure-gating` — Phase 5: derive the public documents from approved claims only

## References

- [`package-contract-00-control.md`](../references/package-contract-00-control.md) and the seven sibling contracts
- [`source-authority-and-claim-states.md`](../references/source-authority-and-claim-states.md)
- [`evidence-ledger-schema.md`](../references/evidence-ledger-schema.md)
- [`disclosure-policy-levels.md`](../references/disclosure-policy-levels.md)

## Phase 0 — Orient and protect

```!
__dr="${CLAUDE_PLUGIN_ROOT:-}"
[ -x "$__dr/bin/dossier-resolve-config.sh" ] || __dr=$({ echo plugins/dossier; ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/dossier/*/ 2>/dev/null | sort -Vr; echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/dossier"; } | while read -r __p; do [ -x "${__p%/}/bin/dossier-resolve-config.sh" ] && { echo "${__p%/}"; break; }; done)

echo "### Preflight"
if [ ! -x "$__dr/bin/dossier-resolve-config.sh" ]; then
  echo "BASELINE_STATE=blocked"
  echo "BASELINE_ERROR=dossier plugin scripts not found — reinstall or upgrade the plugin"
  true; exit 0
fi
echo "DOSSIER_ROOT=$__dr"

OUTPUT_ROOT=$("$__dr/bin/dossier-resolve-config.sh" --default "docs/dossier" dossier.project.outputRoot 2>/dev/null)
echo "OUTPUT_ROOT=$OUTPUT_ROOT"
echo "DELIVERY_MODE=$("$__dr/bin/dossier-resolve-config.sh" --default full dossier.engagement.deliveryMode 2>/dev/null)"
echo "PACKAGE_EXISTS=$([ -d "$OUTPUT_ROOT/00-control" ] && echo true || echo false)"

echo "### Config"
"$__dr/bin/dossier-validate-config.sh" 2>&1 || echo "CONFIG_FINDINGS=present"

echo "### Working tree"
echo "UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
echo "COMMIT=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
true
```

If the package does not exist, stop and direct the user to `/dossier:init`. Baseline drafts into a scaffold; it does not create one.

Invoke `Skill(engagement-scoping)`. Preserve unrelated user work — the output root is the only thing this command writes to.

Emit the work plan and the source-access limitations before proceeding. A reader must know what could not be inspected before they read anything that was.

## Phase 1 — Inventory evidence

Dispatch `Agent(dossier-evidence-collector)` per inspection batch, **in a single message**. A monorepo's manifests, schemas, pipelines, and infrastructure definitions will not fit alongside twenty-three documents being drafted, which is why inventory runs in its own context and returns rows rather than file contents.

Each collector receives its batch boundary and the frozen scope. Each returns evidence-ledger rows, executed-check results, and coverage gaps.

Verify the returned distribution before proceeding. A run reporting mostly `V` at authority level 1 without having executed anything has misclassified, and catching that here costs one re-run rather than a whole package.

Then invoke `Skill(gap-and-contradiction-register)` to record every coverage gap. Never silently skip a directory, service, or evidence class.

## Phase 2 — Model the project

Invoke `Skill(project-modeling)`. Build the canonical model and the terminology register, then test the model against at least three end-to-end flows: one primary user or business flow, one change-to-production flow, one credible failure or abuse flow.

Trace failures become `AQ-` or `CT-` rows **before drafting begins**. A model corrected here costs one edit; corrected in Phase 6 it costs a rewrite of everything downstream.

## Phase 3 — Resolve material gaps

Invoke `Skill(gap-and-contradiction-register)`. Classify each gap blocking · material non-blocking · minor.

For blocking gaps, in order: search again by a different route → run a safe check the ceiling permits → ask a concise evidence-seeking question (only when `allowedActions.contactHumans` is true) → otherwise mark the affected claims unresolved and continue.

Do not stall the package for a non-blocking unknown.

## Phase 4 — Draft the internal documents

Dispatch `Agent(dossier-doc-drafter)` once per document, in dependency waves. Within a wave, dispatch **all** agents in a single message.

**Cap the fan-out.** `--max-drafters <n>` bounds how many drafters run concurrently within a wave; default **6**. A wave larger than the cap is split into consecutive batches, still one message per batch.

The cap is not ceremony. Wave 2 alone is five documents and the full package is 21, each drafter re-reading its contract and its ledger slice — and current models delegate more readily than their predecessors, so an uncapped fan-out multiplies cost and latency without improving any single document. Raise it only when the documents are genuinely independent and the budget is deliberate.

| Wave | Documents | Depends on |
|---|---|---|
| 1 | `00-control/*` (4 registers) | Phase 1–3 |
| 2 | `02-architecture/*` (5) | The model |
| 3 | `01-project/*` (2), `03-assurance/*` (3) | Wave 2 |
| 4 | `04-operating/*` (3) | Waves 2–3 |
| 5 | `05-due-diligence/*` (2) | All internal documents |
| 6 | `00-control/documentation-index.md` | Every file's final status |

Each drafter receives exactly one document path, its contract section, the project model, and its evidence-ledger slice. It loads one `package-contract-*.md`, never all eight.

Due-diligence documents draft last among internal documents so they assess the completed evidence set rather than a partial one.

With `--only <dir-or-file>`, restrict to the matching documents and skip waves with nothing to do.

## Phase 5 — Derive the public documents

Invoke `Skill(disclosure-gating)`.

Start from the **approved** rows of the claim and disclosure register. Not from the internal documents, not from existing marketing copy — starting anywhere else is how unapproved claims leak.

Then verify:

```bash
bin/dossier-claim-scan.sh --output-root "$OUTPUT_ROOT"
```

Exit 2 means leakage: stop and fix the source sentence, not the symptom. If a credential reached a draft, it is also in whatever the draft was copied from.

## Phase 6 — Report

```bash
bin/dossier-package-check.sh --output-root "$OUTPUT_ROOT"
bin/dossier-ledger-lint.sh --output-root "$OUTPUT_ROOT"
```

```markdown
### Baseline complete

PROJECT_VERSION={commit}  EVIDENCE_CUTOFF={ISO}
DOCUMENTS_WRITTEN={n}/23  LEDGER_ROWS={n}  BY_STATE={V:n C:n R:n I:n U:n}
CHECKS_EXECUTED={n}  CHECKS_NOT_EXECUTED={n}
OPEN_QUESTIONS={n}  CONTRADICTIONS={n}  PENDING_CLAIMS={n}

### Sources inspected / inaccessible
### Unresolved material uncertainty
### Next
1. `/dossier:audit` — three independent verification passes
2. `/dossier:gate` — scorecard and release gate
```

Never claim the package is complete or correct. Report what was verified, what was not executed and why, and what remains unknown.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read project sources within `project.sources` | 1 | Autonomous, read-only |
| Run checks the action ceiling permits | 1 | Autonomous; blocked by `enforce-allowed-actions.sh` when not permitted |
| Write evidence, assumption, contradiction, and terminology registers | 1 | Autonomous |
| Draft the 21 internal documents inside the output root | 1 | Autonomous; confined by `enforce-output-root.sh` |
| Dispatch collector and drafter agents | 1 | Autonomous |
| Write `06-public/**` | 2 | Journal — derived from approved claims only, scanned before completion |
| Modify the claim and disclosure register | 2 | Journal |
| Mark a public claim approved | 3 | **Never automated.** Approval is a human act; unapproved stays `pending` |
| Write outside the output root | 3 | **Blocked** unless `allowedActions.writeOutsideOutputRoot` is set deliberately |
| Committing anything baseline wrote | 3 | **Never automated.** The user reviews the diff and commits |
