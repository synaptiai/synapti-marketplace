# Decision Journal — Issue #265

**Title**: feat(flow): warn mode stops reporting a criterion as missing evidence when its recorded evidence supports it
**Branch**: feature/issue-264-265-goal-judge-s1 (shared with #264)
**Tracks**: #258

## Specification

Site `goal.warn-evidence`, question `evidence_supports` (noul; the same
question body as `goal.judge.supported`, through a YAML alias). One call per
criterion with no verification command that has recorded evidence. Mode
`systemOne.uses["goal.warn-evidence"]`: off (plugin default), shadow or on; a
repository's settings can only lower the user's mode, applied by
`bin/flow-s1-mode.sh` (shared rule of #258; no trust gating, per the user's
decision).

### Non-goals

- Block mode is unchanged: BLOCKING_INCOMPLETE still holds command-less
  criteria, and no request is made.
- Evaluator-loop mode and the Haiku judge are #264.
- The goal file is never written: no status, evidence_ref, last_result or
  lifecycle change, no sidecar, no verdict.
- Criteria with a verification command (untrusted not_executed, or launch
  failed) are never asked about.
- A criterion with no evidence, or only llm_judge_report or verdict evidence,
  is not asked about and stays reported.
- No change to the client's contract.
- The site ships off; the threshold is provisional.

### Failure modes

| Condition | Behaviour |
|---|---|
| Timeout | Each call is bounded by timeoutMs; calls run in parallel (at most 5 at once); a timed-out criterion stays reported. |
| Partial failure | Only answered criteria are removed; the rest stay reported. |
| Confident no (exit 0, p < 0.5) | Stays reported; the record holds p. |
| Malformed or non-mapping sidecar | Left out of the state; with no usable evidence left, no request. |
| Symlinked .flow, runs, run or evidence directory | Nothing is read or asked; output unchanged. |
| Invalid run_id or no run directory | Nothing is asked; output unchanged. |
| No run_id, no evidence, REPORT_ERROR set | Nothing is asked; output unchanged. |
| Client exit 2 | Treated as no answer; nothing printed. |
| Client stderr | Discarded in every mode. |
| settings-refused (plugin inside the repository) | No answer; output unchanged. |
| Work directory cannot be created | Nothing is asked; output unchanged. |

### Interface contracts

- Report `no_command` and the state builder are shared with #264 (see
  `.decisions/issue-264.md`). Warn mode asks only for indices whose coverage
  is deterministic or mixed.
- The run directory is checked with `flow-mkdir.sh --check` (never created),
  as the evaluator checks it.
- Call: `flow-s1.sh ask --site goal.warn-evidence --state-file F --state-format
  json --current "missing-evidence goal=<id> criterion=<id>" --ref
  goal:<goal>/<criterion> [--run-id R]`.
- Supported: exit 0 and `answers.evidence_supports.p >= 0.5`.
- On mode output: supported ids leave the "Missing evidence for:" line (left
  out when none remain) and are listed on `Supported by recorded evidence
  (System One; not a verdict): <ids>`. The cut to 5 ids happens after the
  filter. When nothing else is reported, stdout is `{"decision":"approve",
  "reason":"FLOW_GOAL_EVIDENCE_RECORDED — stop ALLOWED; recorded evidence
  supports <ids> (System One, not a verdict); run /flow:goal evaluate <goal>"}`
  and stderr is empty.
- Off, shadow, no provider and no answer: stdout and stderr byte-equal to a
  run with no System One settings.
- The stop is allowed in every mode.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Direction of the noul answer | confidence alone decides, so p=0.02 removes the criterion | Stub p=0.02: still under Missing evidence, no Supported line |
| Which criteria are asked | incomplete_acs used, so an untrusted command criterion is asked and removed | One command-less and one untrusted criterion, both with sidecars: one request, its state names the command-less one |
| Shadow changes output | flow-s1's stderr reaches the user, or shadow acts as on | Shadow output byte-equal to off; one request, one record with mode shadow |
| Judge-only and no evidence | A criterion with no deterministic sidecar is sent and removed | Stub p=0.99: 0 requests, still reported |
| Partial answers and the cut to 5 | Cut before filtering, or one call for all criteria | 7 criteria, first 2 supported: criteria 6 and 7 appear; one delayed past timeoutMs, only the other removed |
| Lifecycle untouched | Goal file or verdict written when all are supported | Goal sha256 equal before and after; no last-verdict.json |

## Notes

- Threshold `goal.warn-evidence.evidence_supports` default 0.9 (needs p >=
  0.95), provisional: a wrong removal hides a real gap, so the starting value
  is strict.

## Shadow comparison (2026-10-07)

- Written from the replay records only (user's decision, 2026-10-07): 167
  items (the 11 with no evidence are not asked, as live), TypeSafe
  jev-1.13.0, sent 2026-10-07 06:13-06:18 UTC. No live records.
- 146 of 167 agree with the label. Precision and coverage of "supported" at
  the spec's thresholds: 0.6 removes 24, none wrongly (24 of 72 covered);
  0.8 removes 5, none wrongly; 0.9 and 0.95 remove nothing, because the
  highest p the model gave was 0.94.
- Chosen: 0.6 for jev-1.13.0 (models entry); the default for other models
  stays 0.9. Rule from the spec: precision first, coverage between equally
  precise thresholds. Caveats stated in the comparison: every negative is
  constructed, the one wrong yes sits at confidence 0.56, and 5 of the 24
  removals rest on the least reliable labels. The site stays off.
- The warn no-answer scenario's below-threshold case now sends p=0.75
  (confidence 0.5), below the new 0.6, instead of p=0.9.
- The comparison is in references/system-one.md, "Shadow comparisons".
