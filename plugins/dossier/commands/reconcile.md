---
description: "Merge the independent A/B/C findings into one adjudicated ledger, publish the pre-repair table, apply agent-repairable corrections, route owner decisions to the registers, and trigger a re-audit when a material claim changed."
argument-hint: [--round <n>] [--findings <path>] [--dry-run]
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Skill, Agent
---

# Reconcile Findings: $ARGUMENTS

Turns three independent findings tables into one adjudicated ledger, then repairs what evidence supports repairing.

## Required Skills

- `finding-reconciliation` — normalize, dedupe, corroborate, publish before repair, split repairable from owner-decision
- `gap-and-contradiction-register` — route unresolvable findings and cross-pass disagreements to `AQ-`/`CT-`
- `evidence-ledger` — every correction is itself evidence-backed
- `doc-package-contract` — corrections respect the document contracts and the `last-verified` rule
- `disclosure-gating` — corrections touching public documents re-enter through the register

## References

- [`finding-schema.md`](../references/finding-schema.md)
- [`independent-audit-protocol.md`](../references/independent-audit-protocol.md)
- [`register-schemas.md`](../references/register-schemas.md)

## Phase 0 — Locate the round

```!
_RAW="$ARGUMENTS"
echo "### Reconcile Arguments"
echo "ARGS=$_RAW"

__dr="${CLAUDE_PLUGIN_ROOT:-}"
[ -x "$__dr/bin/dossier-resolve-config.sh" ] || __dr=$({ echo plugins/dossier; ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/dossier/*/ 2>/dev/null | sort -Vr; echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/dossier"; } | while read -r __p; do [ -x "${__p%/}/bin/dossier-resolve-config.sh" ] && { echo "${__p%/}"; break; }; done)

echo "### Preflight"
if [ ! -x "$__dr/bin/dossier-resolve-config.sh" ]; then
  echo "RECONCILE_STATE=blocked"
  echo "RECONCILE_ERROR=dossier plugin scripts not found — reinstall or upgrade the plugin"
  true; exit 0
fi

OUTPUT_ROOT=$("$__dr/bin/dossier-resolve-config.sh" --default "docs/dossier" dossier.project.outputRoot 2>/dev/null)
echo "OUTPUT_ROOT=$OUTPUT_ROOT"
echo "MAX_ROUNDS=$("$__dr/bin/dossier-resolve-config.sh" --default 3 dossier.verification.maxRounds 2>/dev/null)"

echo "### Available rounds"
LATEST=$(ls -1d .dossier/runs/*/ 2>/dev/null | sort | tail -1)
echo "LATEST_RUN=${LATEST:-none}"
if [ -n "$LATEST" ]; then
  for p in A B C; do
    f="${LATEST}pass-$p.md"
    if [ -f "$f" ]; then
      echo "PASS_${p}=present findings=$(grep -c '^| \*\*' "$f" 2>/dev/null || echo 0)"
    else
      echo "PASS_${p}=absent"
    fi
  done
fi
true
```

Reconciling a round whose passes did not all return is legitimate — record which lens is missing and that the round's coverage is narrowed. Silently reconciling two passes as though they were three is not.

With `--findings <path>`, ingest an externally-produced audit instead of the in-plugin pass files. Record the independence tier as `external` — that fact belongs in the report.

## Phase 1 — Normalize and deduplicate

Invoke `Skill(finding-reconciliation)`.

Dedupe by `(location_normalized, claim_hash)`. Keep the highest severity. Merge problem descriptions when they add different context — discarding the second pass's reasoning throws away the thing that made it a second pass.

## Phase 2 — Corroboration without ranking

Stamp each finding `N/3`.

**A 1/3 finding is never downgraded for being lonely.** The passes have different lenses by design: pass C is the only one simulating a new engineer's first contribution, so a broken onboarding command *should* be 1/3, and it is no less real. Downgrading by vote count converts three specialists into a majority-vote committee.

Corroboration orders repair work. It does not rank truth.

## Phase 3 — Promote disagreements

When two passes reach incompatible conclusions about the same claim, that is **a Critical finding in its own right** — the package contains a claim two independent reviewers could not agree on, and a reader will not do better.

Promote it, open a `CT-####` row, and resolve with **evidence, not majority vote**. Two passes agreeing against one is not evidence; it is two passes.

## Phase 4 — Publish before repair

Write the merged pre-repair table to `07-verification/documentation-verification-report.md`.

**This is a commit point.** It is never rewritten; later rounds append. The pre-repair table is the evidence that verification happened — a package that quietly fixes what it found and reports only the clean end state has destroyed its own audit trail.

With `--dry-run`, stop here.

## Phase 5 — Split and repair

| Class | Handling |
|---|---|
| Agent-repairable | The evidence already supports the correction. Apply it |
| Needs-owner | Business decision, legal interpretation, disclosure approval, risk acceptance, or missing evidence. Route to `AQ-`/`CT-`. **Blocks the gate** |
| Blocked | Correction is clear but the action ceiling forbids it. Record the specific ceiling |

Repair Critical and High first. Each correction is itself evidence-backed — a fix that replaces one unsourced claim with another is not a fix.

**Never mark a finding corrected because the sentence was deleted**, unless deletion was the required correction. Removing a claim to clear a finding is laundering, and it is detectable by the next round.

Applying a correction does not erase the finding. Status becomes `Corrected` and the correction is described; a reader must see what was wrong, not only that it is now right.

## Phase 6 — Re-check and decide on re-audit

Re-run every check a correction touched:

```bash
bin/dossier-package-check.sh --output-root "$OUTPUT_ROOT"
bin/dossier-ledger-lint.sh --output-root "$OUTPUT_ROOT"
bin/dossier-claim-scan.sh --output-root "$OUTPUT_ROOT"
```

Re-audit in fresh contexts when a correction materially changed architecture, product behaviour, data handling, security, reliability, or a public claim. Minor and clarity corrections do not require a full round.

On reaching `verification.maxRounds` with findings still open, **stop and report `conditionally ready` or `not ready` with exact blockers**. Never `release-ready` with rounds unrun, and never an unbounded loop.

## Phase 7 — Report

```markdown
### Reconciliation complete — round {n}

FINDINGS_RAW={A:n B:n C:n}  AFTER_DEDUPE={n}
BY_SEVERITY={Critical:n High:n Medium:n Low:n}
BY_CORROBORATION={3/3:n 2/3:n 1/3:n}
DISAGREEMENTS_PROMOTED={n}
CORRECTED={n}  NEEDS_OWNER={n}  BLOCKED={n}  OPEN={n}
RECHECKS_RUN={n}  REAUDIT_REQUIRED={yes|no}
ROUNDS_USED={n}/{max}

### Owner decisions required
| ID | Decision | Who must decide | What is blocked |
|---|---|---|---|

### Next
{`/dossier:audit --round n+1` | `/dossier:gate`}
```

The owner-decision table is what a human must act on. Every row names the decision and who can make it — "needs review" is not a decision.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read raw pass output and the package | 1 | Autonomous, read-only |
| Normalize, dedupe, stamp corroboration | 1 | Autonomous |
| Promote a cross-pass disagreement to Critical | 1 | Autonomous |
| **Publish the pre-repair findings table** | 1 | Autonomous — a commit point, never rewritten |
| Apply agent-repairable corrections to internal documents | 1 | Autonomous |
| Apply a correction to `06-public/**` | 2 | Journal — re-enters through the claim register |
| Open `AQ-`/`CT-` rows for unresolvable findings | 1 | Autonomous |
| Mark a finding `Corrected` | 1 | Autonomous — only when the correction was made, never for a deletion that was not the required fix |
| Mark a finding `Accepted risk` | 3 | **Never automated.** Requires a named accepting authority |
| Resolve a contradiction without new evidence | — | **Never.** That is an accepted risk, recorded as such |
| Declare `release-ready` | — | **Not this command.** `/dossier:gate` |
