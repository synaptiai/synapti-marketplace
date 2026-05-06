# Tests — Issue #86 (paired-reviewer + challenge protocol)

Verification fixtures for the marker-schema extension that paired-reviewer mode introduces (`FLOW_REVIEW_CYCLE` gains optional `Confidence|Disposition` trailing fields). Tests run on the same shell pipelines that `commands/status.md` and `commands/merge.md` use against PR markers, so a regression in either consumer's tolerance is caught here.

## What's NOT covered

This fixture verifies the **parser/marker side** of issue #86 ACs only. It does NOT verify:

- The actual paired-reviewer LLM dispatch (Path A.1 in `commands/review.md`) — requires running `/flow:review <pr>` with `agentTeams: true` AND `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` against a synthetic PR.
- The challenge-round prompt behavior — same constraint.
- The auto-consensus match logic (file ±2 lines, priority ±1) — implemented in Path A.2 as pseudocode applied by the orchestrator at runtime; verify via end-to-end PR test.
- The consolidation table semantics — applied at runtime by Path A.4.

The LLM-side verification is a manual step: run `/flow:review` against a synthetic PR with the flag enabled and confirm the consolidated output and the 7-field marker.

## Run

```bash
bash tests/issue-86/verify.sh
```

Exits `0` on pass, `1` on first failure. Each test prints `PASS:` or `FAIL:` with a short reason.

## Fixtures

- `markers/legacy-5-field.txt` — single FLOW_REVIEW_CYCLE marker in the legacy 5-field form. Verifies backwards-compat.
- `markers/extended-7-field.txt` — single marker in the new 7-field form (Confidence + Disposition appended). Verifies new-form parsing.
- `markers/mixed-cycles.txt` — two cycles, one of each form (simulates an in-flight upgrade where a PR has both legacy and paired-reviewer markers from different cycles).
- `markers/with-resolution.txt` — review marker + resolution marker, exercises the full ledger pipeline.

## What gets asserted

For each fixture, `verify.sh` runs:

1. `status.md`-style parser: `tr ',' '\n' | while IFS='|' read -r ID PRIORITY ...` — confirms ID and PRIORITY extract correctly regardless of trailing fields.
2. `merge.md`-style parser: `sed 's/|.*//'` to take the leading ID-only — confirms ID extraction tolerates variable field count.
3. Count assertions: each fixture has a known finding count (P1/P2/P3); the parsers must produce the same totals.
4. Resolution match: for the resolution fixture, `comm -23` between FINDINGS IDs and RESOLVED IDs produces the expected unresolved set.
