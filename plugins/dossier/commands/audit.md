---
description: "Run the three independent verification passes over a documentation package. Dispatches evidence, falsification, and audience lenses in isolated contexts and collects their findings tables verbatim. Does not merge, judge, or repair — that is /dossier:reconcile."
argument-hint: [--round <n>] [--passes A,B,C] [--path <package-root>] [--external]
allowed-tools: Bash, Read, Write, Glob, Grep, Skill, Agent
---

# Audit Documentation Package: $ARGUMENTS

Three independent passes, three isolated contexts, three findings tables collected verbatim.

<!--
SINGLE-MESSAGE DISPATCH IS LOAD-BEARING: Phase 2 MUST dispatch all three pass
agents in ONE message with three Agent calls. Dispatching sequentially puts
pass A's findings into this orchestrator's context before pass B is spawned,
which is exactly the contamination the three-pass design exists to prevent.
-->

## Required Skills

- `engagement-scoping` — resolve the package root and the scope each pass receives
- `doc-package-contract` — structural precheck before spending any pass budget

## Non-goals

This command **must not** merge findings, adjudicate disagreements, judge severity, repair anything, or compute a gate verdict. Those belong to `/dossier:reconcile` and `/dossier:gate`.

The separation is structural, not stylistic. An orchestrator that merged findings would need the reconciliation logic in its context, and anything in this context is one dispatch away from a verifier's.

## References

- [`independent-audit-protocol.md`](../references/independent-audit-protocol.md)
- [`finding-schema.md`](../references/finding-schema.md)
- [`scorecard-rubric.md`](../references/scorecard-rubric.md)

## Phase 0 — Precheck

```!
_RAW="$ARGUMENTS"
echo "### Audit Arguments"
echo "ARGS=$_RAW"

__dr="${CLAUDE_PLUGIN_ROOT:-}"
[ -x "$__dr/bin/dossier-package-check.sh" ] || __dr=$({ echo plugins/dossier; ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/dossier/*/ 2>/dev/null | sort -Vr; echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/dossier"; } | while read -r __p; do [ -x "${__p%/}/bin/dossier-package-check.sh" ] && { echo "${__p%/}"; break; }; done)

echo "### Preflight"
if [ ! -x "$__dr/bin/dossier-package-check.sh" ]; then
  echo "AUDIT_STATE=blocked"
  echo "AUDIT_ERROR=dossier plugin scripts not found — reinstall or upgrade the plugin"
  true; exit 0
fi

OUTPUT_ROOT=$("$__dr/bin/dossier-resolve-config.sh" --default "docs/dossier" dossier.project.outputRoot 2>/dev/null)
echo "OUTPUT_ROOT=$OUTPUT_ROOT"
echo "PACKAGE_EXISTS=$([ -d "$OUTPUT_ROOT/00-control" ] && echo true || echo false)"
echo "PINNED_VERSION=$("$__dr/bin/dossier-resolve-config.sh" --default auto dossier.project.versionOrCommit 2>/dev/null)"
echo "PASS_MODELS=$("$__dr/bin/dossier-resolve-config.sh" --compact --default '{}' dossier.verification.passModels 2>/dev/null)"
echo "TRACE_COUNT=$("$__dr/bin/dossier-resolve-config.sh" --default 10 dossier.verification.traceCount 2>/dev/null)"

echo "### Structural precheck"
"$__dr/bin/dossier-package-check.sh" --output-root "$OUTPUT_ROOT" 2>&1 | head -20 || true

echo "### Prior rounds"
if [ -d .dossier/runs ]; then
  echo "PRIOR_ROUNDS=$(ls -1d .dossier/runs/*/ 2>/dev/null | wc -l | tr -d ' ')"
else
  echo "PRIOR_ROUNDS=0"
fi
true
```

`--path <package-root>` overrides the resolved `project.outputRoot` for this run — use it to audit a package that is not the one this repository's config points at (a vendored copy, a second project, a package under review from elsewhere). Everything downstream reads the override, not the config.

A package missing canonical files is a structural finding, not an audit input. Report it and stop rather than spending three passes' budget confirming the same absence three times.

## Phase 1 — Build three isolated payloads

Each pass receives **only**:

1. The package root path
2. The resolved scope (`00-control/.scope.json`)
3. The source roots the scope permits
4. Its lens
5. The round number

Each pass receives **none of**: the drafting transcript · the authored project-model narrative as authority · another pass's findings, this round or any prior · prior-round findings · the reconciliation logic · any self-score or prior gate verdict.

Do not summarize the package for the passes. A summary is authored content, and a pass reading your summary is auditing you rather than the package.

## Phase 2 — Dispatch all three in one message

```
Agent(dossier-pass-a-evidence)      → .dossier/runs/<id>/pass-A.md
Agent(dossier-pass-b-falsification) → .dossier/runs/<id>/pass-B.md
Agent(dossier-pass-c-audience)      → .dossier/runs/<id>/pass-C.md
```

**One message. Three calls.** Sequential dispatch leaks pass A's output into this context before B is spawned.

Apply `verification.passModels` per pass — **but the value `inherit` is not a dispatch argument.**

The Agent tool's per-invocation `model` override accepts only `sonnet`, `opus`, `haiku`, or `fable`. `inherit` is valid in an agent's *frontmatter*, where it means "use the session model"; it is **not** a valid override value. The default for all three passes is `inherit`, so a literal reading of "apply passModels" breaks the out-of-the-box configuration at the moment of dispatch.

| `passModels.{A,B,C}` | What to pass |
|---|---|
| `inherit` (the default) | **Omit `model` entirely.** The agent's `model: inherit` frontmatter already selects the session model |
| `sonnet` / `opus` / `haiku` / `fable` | Pass it as the dispatch override — it takes precedence over frontmatter |
| anything else | Do not dispatch. Report a configuration error naming the invalid value |

Omitting the override and passing `model="inherit"` are not the same thing: the first works, the second is an invalid enum value.

A plugin cannot guarantee a different model, so this is the honest half-measure: independent context always, a different model only when the operator configures one. Record which tier was used — the package's own evidence standard requires it.

With `--passes A,C`, run only those and record the narrowed coverage as a deliberate reduction in assurance. Narrowing is legitimate; hiding it is not.

## Phase 3 — Collect verbatim

Write each pass's table to `.dossier/runs/<id>/pass-{A,B,C}.md` **unmodified**. Do not reorder, renumber, summarize, dedupe, or reconcile. Do not drop a finding you believe is wrong — that judgment belongs to reconciliation, with evidence.

Verify each file carries its marker:

```
<!-- DOSSIER_AUDIT round={n} pass={A|B|C} model={id} started={ISO} findings={n} critical={n} high={n} -->
```

A pass that returned no marker did not complete. Report it as an infrastructure failure — never as a clean pass, which is what an empty findings table would otherwise imply.

## Phase 4 — External audit

With `--external`, render `templates/external-audit-prompt.md` as a self-contained prompt for a genuinely different model, substituting the package root, scope, and round. Do not run it — hand it to the user.

Ingest the result via `/dossier:reconcile --findings <path>`.

This is the only path to true cross-model independence, and it is worth saying plainly: in-plugin subagents give independent *context*, not an independent *model*.

## Phase 5 — Hand off

Append each pass's section to `07-verification/documentation-verification-report.md` under the round heading. Sections stay separate and unmerged until reconciliation.

```markdown
### Audit complete — round {n}

PASSES_RUN={A,B,C}  INDEPENDENCE_TIER={in-plugin|external}
MODELS={A:…, B:…, C:…}
FINDINGS={A:n B:n C:n}  CRITICAL={n}  HIGH={n}
SCORES={A:n B:n C:n}    SCORE_VARIANCE={n}

### Next
`/dossier:reconcile --round {n}`
```

Score variance across passes is signal. Near-identical scores from three different lenses suggest contamination, not agreement — flag it.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read the package and project sources | 1 | Autonomous, read-only |
| Run the structural precheck | 1 | Autonomous |
| Dispatch the three pass agents | 1 | Autonomous |
| Write raw pass output to `.dossier/runs/<id>/` | 1 | Autonomous, gitignored working state |
| Append per-pass sections to the verification report | 1 | Autonomous |
| Render the external audit prompt | 1 | Autonomous — renders only, never executes |
| Merge, dedupe, or adjudicate findings | — | **Not this command.** `/dossier:reconcile` |
| Repair any document | — | **Not this command.** Findings are published before repair |
| Issue a gate verdict | — | **Not this command.** `/dossier:gate` |
