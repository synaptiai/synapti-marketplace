
## Specification

## Specification

Issue #268: /flow:learn orders the transcript correction candidates by a System One answer (site `learn.correction`, question `is_correction`). Taken from the accepted spec for #268 and corrected for the code on main at 85b63bc4 (after #278).

### Corrections to the spec against current code

- The Transcript Corrections section is learn.md lines 197-261 at 85b63bc4 (the spec cited 172-217). It is wrapped in `# TRANSCRIPT_CORRECTIONS_BLOCK_BEGIN` / `_END`.
- #278 added `--ref` and made every call site pass one. A transcript path does not fit the `--ref` shape, so the ref is `transcript:<file stem>/<line_no>`, or `transcript:sha256-<16 hex of the path>/<line_no>` when the stem does not fit `[A-Za-z0-9][A-Za-z0-9._-]{0,150}`.
- The spec's separate screening index (`learn-correction-index.jsonl`) is not built. Each System One record already carries `ref` and `state_sha256`, so the verdict writer joins on the records. A second file would hold the same pairs.
- #278 makes flow-s1.sh ignore a repository's `on`. A repository's `shadow` is still taken as is by the client. For this site the state is the user's own transcript text, so the block also reads the mode from the user tier and the plugin default only (`cascade-resolve.sh --no-repo-settings`) and runs nothing unless that mode is shadow or on. A repository can lower the mode (flow-s1.sh applies its off or shadow), never raise it. This follows the shared rule "a repository's settings may only lower a site's mode".
- flow-s1.sh and the verdict writer are taken from the copy of the plugin outside the repository (the USER_FILES resolver), as the transcript directory already is. Inside synapti-marketplace the in-tree copy refuses provider settings (settings-refused), so this is also the copy that can write records here.

### Non-goals

- No change to bin/flow-mine-corrections.sh (phrase list, formats, flags; it still makes no network call).
- No candidate is removed, hidden, merged or marked verified. Phase 2 step 1 (re-read before counting) applies to every cited row.
- No change to the SessionEnd hook.
- No recall widening: screening only reorders what the miner returns.
- No change to bin/flow-s1.sh or bin/_flow_s1.py, and no new setting.
- Not switched on by default: the site ships off; the threshold is provisional until the written shadow comparison.
- No change to clustering, the 3-instances-across-2-sessions threshold, or Phases 3 and 4.

### Failure modes

- Site off for the user, provider none, settings-refused, python-missing, unknown-site: no request; the section prints what it printed before, byte for byte. With the user-tier mode off the second miner run does not happen.
- Timeout, connection, http-<status>, redirect, malformed, abstained, missing-answer, below-threshold for one candidate: that candidate is unanswered (middle band, miner order); the others keep their answers. All unanswered: output identical to before.
- Slow provider: screening stops when 60 s have passed or 100 candidates were asked, whichever comes first; the rest are unanswered, and on mode prints S1_STATE=partial.
- The two miner runs disagree (a transcript grew between them): rows are checked one by one against the jsonl candidates; any difference keeps miner order and on mode prints S1_STATE=mismatch.
- The jsonl miner run fails or prints nothing: no screening.
- A state file cannot be written: that candidate is unanswered; the temporary directory is removed.
- A record cannot be written: flow-s1 warns on stderr, which the block discards.
- Transcript text with `|`, a newline or a forged `KEY=value`: the block only moves whole lines the miner printed that start with `| <n> |`; it prints no candidate text itself.
- A repository setting the site to shadow or on while the user tier says nothing: nothing is sent.

### Interface contracts

- `flow-s1.sh ask --site learn.correction --state-file <f> --state-format json --current keyword-candidate --ref <ref>`, one call per candidate. Exit 0: `answers.is_correction` = `{type: noul, p, confidence}`. Any other exit: unanswered.
- State file: UTF-8 JSON `{"assistant_before": <miner preceded_by>, "user_turn": <miner text>}`, keys sorted, no trailing newline. The record's `state_sha256` is the sha256 of these bytes.
- Ordering (on mode, at least one answer): band 1 answered with p >= 0.5, p descending, ties in miner order; band 2 unanswered, miner order; band 3 answered with p < 0.5, miner order. The `#` cell keeps the miner number; header, separator, KEY lines and CANDIDATE_COUNT are unchanged; the multiset of rows is unchanged.
- New lines, only when at least one candidate was answered (which happens only in on mode), after the miner KEY lines and before the table: `S1_STATE=ordered|partial|mismatch`, `S1_SCREENED=<n>`, `S1_ANSWERED=<n>`, `S1_RATED_CORRECTION=<n>`.
- Verdict writer `bin/flow-learn-verdict.sh --line <transcript_path>:<line_no> --verdict kept|dropped`: finds the newest `learn.correction` record with that ref from the last 24 hours in the per-user state directory and appends `{ts, site, ref, state_sha256, verdict}` to `learn-correction-verdicts.jsonl` there. Without such a record it writes nothing and exits 0. It never prints transcript text.
- questions.yaml gains `learn.correction` with question `is_correction` (noul), threshold default 0.8, provisional.
- tests/lib/s1_stub.py gains `by_state: [{contains, status?, body?}]`, first match wins, falling back to `status`/`body`.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Ordering key | sort by confidence, not p, so a confident "no" (p 0.03) sorts first | on scenario with p 0.95, a 500 and p 0.03 in a miner order that differs from the expected order |
| Off and no-answer identity | S1_ lines, a blank line or a reordered table leak when nothing answered; second miner pass with the site off | off, no-provider, http-500, abstained and below-threshold scenarios compare stdout with the off run; off logs 0 requests |
| Shadow purity | shadow reorders or prints S1_ lines, or skips records | shadow stdout equals off stdout; records carry mode shadow, current keyword-candidate, the ref and the digest of the state built from the fixture |
| Repository raising the mode | a repository's shadow or on sends the user's transcript text | repo shadow and repo on with no user uses: 0 requests; the mutant that drops --no-repo-settings from the gate fails the repo-shadow scenario |
| Row join | rows matched by position, so a grown transcript moves an answer to another row | mismatch scenario: the jsonl run sees one extra candidate; S1_STATE=mismatch and miner order |
| Verdict join | keyed on row number or text, so unscreened rows get verdicts | writer for an unscreened line writes nothing; for a screened line the digest equals the record digest |
