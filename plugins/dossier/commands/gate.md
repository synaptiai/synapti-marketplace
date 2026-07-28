---
description: "Evaluate the nineteen release-gate conditions and issue a release-ready, conditionally-ready, or not-ready verdict. Runs the mechanical checks by script and dispatches the scorer for the judgment set — and refuses to pass without both."
argument-hint: [--json] [--strict] [--path <package-root>] [--round <n>]
allowed-tools: Bash, Read, Write, Glob, Grep, Skill, Agent
---

# Release Gate: $ARGUMENTS

Nineteen conditions, conjunctive. Nineteen of nineteen, or the package is not release-ready.

## Required Skills

- `scoring-and-release-gate` — the ten-dimension rubric, the nineteen conditions, and the verdict vocabulary

## The contract this command enforces

**Failing is decidable from a subset. Passing is not.**

Twelve mechanical conditions are enough to prove a package is *not* releasable — one broken link suffices. They are never enough to prove it *is*, because the judgment set includes both scorecard conditions and three of the four "must never appear" rules. A gate that passed on mechanics alone would certify a package whose planned features are documented as shipped and whose targets are printed as measurements, having read neither.

So `bin/dossier-gate.sh` **structurally refuses to emit PASS without a valid scorer verdict file**. Absent, stale, revision-mismatched, round-mismatched, or silent on any judgment condition yields `INCONCLUSIVE` — which maps to `not ready`, never to `conditionally ready`. "We did not check" is an absence of assurance, not a condition to attach.

## References

- [`release-gate-conditions.md`](../references/release-gate-conditions.md)
- [`scorecard-rubric.md`](../references/scorecard-rubric.md)
- [`finding-schema.md`](../references/finding-schema.md)

## Phase 0 — Mechanical conditions

```!
_RAW="$ARGUMENTS"
echo "### Gate Arguments"
echo "ARGS=$_RAW"

__dr="${CLAUDE_PLUGIN_ROOT:-}"
[ -x "$__dr/bin/dossier-gate.sh" ] || __dr=$({ echo plugins/dossier; ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/dossier/*/ 2>/dev/null | sort -Vr; echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/dossier"; } | while read -r __p; do [ -x "${__p%/}/bin/dossier-gate.sh" ] && { echo "${__p%/}"; break; }; done)

echo "### Preflight"
if [ ! -x "$__dr/bin/dossier-gate.sh" ]; then
  echo "GATE_STATE=blocked"
  echo "GATE_ERROR=dossier-gate.sh not found — reinstall or upgrade the dossier plugin"
  true; exit 0
fi

OUTPUT_ROOT=$("$__dr/bin/dossier-resolve-config.sh" --default "docs/dossier" dossier.project.outputRoot 2>/dev/null)
echo "OUTPUT_ROOT=$OUTPUT_ROOT"
echo "MIN_SCORE=$("$__dr/bin/dossier-resolve-config.sh" --default 95 dossier.gate.minScore 2>/dev/null)"
echo "MIN_DIMENSION_PCT=$("$__dr/bin/dossier-resolve-config.sh" --default 80 dossier.gate.minDimensionPercent 2>/dev/null)"

echo "### Mechanical evaluation"
"$__dr/bin/dossier-gate.sh" --output-root "$OUTPUT_ROOT" 2>&1
echo "GATE_SCRIPT_EXIT=$?"
true
```

`--path <package-root>` overrides the resolved `project.outputRoot`, and is passed through to `bin/dossier-gate.sh --output-root`. Use it to gate a package other than the one this repository's config points at.

Exit codes: `0` PASS · `1` FAIL · `2` usage error · `3` INCONCLUSIVE.

**Exit 1 means stop.** A mechanical condition failed, and the judgment set cannot rescue it. Report the failed conditions and their remediation without spending scorer budget.

**Exit 3 is the expected first result** — no verdict file exists yet. Continue to Phase 1.

## Phase 1 — Dispatch the scorer

Dispatch `Agent(dossier-scorer)`. It receives:

1. The final package
2. The adjudicated findings ledger from `07-verification/documentation-verification-report.md`
3. The resolved scope
4. The mechanical results from Phase 0

It receives **none of**: the drafting transcript · the repair rationale · any pass's self-score · which pass reported which finding · anyone's expectation of the verdict.

It writes `.dossier/runs/<round>/scorer-verdict.md` carrying:

- The per-dimension score table with anchors, points, and **cited finding IDs per deduction**
- An explicit `PASS` or `FAIL` line for **every** judgment condition (`G01`, `G02`, `G04`, `G07`, `G13`, `G14`, `G15`)
- The pinned project revision and the audit round

A verdict silent on a condition has not evaluated it, and silence must not read as assent — the script rejects such a file rather than treating the gap as a pass.

## Phase 2 — Re-evaluate with the verdict

```bash
bin/dossier-gate.sh --output-root "$OUTPUT_ROOT" --round "$ROUND"
```

Now all nineteen are decidable. The result is final for this round.

`--strict` maps exit 3 to exit 1, so CI treats an uncovered judgment set as a failure rather than as a state to interpret. Use it in any automated context.

`--json` emits one object per condition with `id`, `tag`, `result`, `evidence`, and `source` (`script` or `verdict`), so a reader can always tell which conditions were machine-decided and which the scorer asserted.

## Phase 3 — Verdict

| Verdict | Condition |
|---|---|
| `release-ready` | All 19 pass |
| `conditionally ready` | Every failure is `needs-owner` or blocked by a stated access limitation — nothing further the run can do |
| `not ready` | Anything else, including any `INCONCLUSIVE` |

An unmade business, legal, or disclosure decision is a real reason a package is not release-ready. `needs-owner` rows block; they are not rounding errors.

Never claim perfection. Where a condition cannot pass because evidence does not exist, say exactly that and name the evidence required.

## Phase 4 — Report

```markdown
### Gate result

GATE_VERDICT={release-ready|conditionally ready|not ready}
GATE_RESULT={PASS|FAIL|INCONCLUSIVE}
TOTAL_SCORE={n}/100  MIN_DIMENSION_MET={yes|no}
GATE_FAILED_CONDITIONS={ids}
SCORER_VERDICT_PRESENT={yes|no}

| ID | Condition | Type | Result | Source | Evidence |
|---|---|---|---|---|---|

### Blockers
| Condition | Why it fails | Exact next action | Owner | Evidence required |
|---|---|---|---|---|
```

The blocker table is the most-read output of the whole package. Every row names a specific artifact or decision. "Improve evidence coverage" is not an action; "obtain the approved data-retention record for the analytics store" is.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Run the mechanical gate checks | 1 | Autonomous, read-only |
| Dispatch `dossier-scorer` | 1 | Autonomous |
| Write `.dossier/runs/<round>/scorer-verdict.md` | 1 | Autonomous, gitignored working state |
| Append the gate result to the verification report | 1 | Autonomous |
| Emit `PASS` without a valid scorer verdict | — | **Structurally impossible.** The script refuses; result is `INCONCLUSIVE` |
| Issue `release-ready` with `needs-owner` items open | — | **Never.** Those block by design |
| Override a failed gate condition | 3 | **Never automated.** Requires explicit human confirmation, recorded with who overrode it and why |
| Lower `gate.minScore` to make a package pass | 3 | **Never automated.** A config change is a policy decision, recorded verbatim in the report |
