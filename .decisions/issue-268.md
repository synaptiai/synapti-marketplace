## Specification

Issue #268: /flow:learn orders the transcript correction candidates by a System One answer (site `learn.correction`, question `is_correction`). Taken from the accepted spec for #268 and corrected for the code on main at 85b63bc4 (after #278).

### Corrections to the spec against current code

- The Transcript Corrections section is learn.md lines 197-261 at 85b63bc4 (the spec cited 172-217). It is wrapped in `# TRANSCRIPT_CORRECTIONS_BLOCK_BEGIN` / `_END`.
- #278 added `--ref` and made every call site pass one. A transcript path does not fit the `--ref` shape, so the ref is `transcript:<file stem>/<line_no>`, or `transcript:sha256-<16 hex of the path>/<line_no>` when the stem does not fit `[A-Za-z0-9][A-Za-z0-9._-]{0,150}`.
- The spec's separate screening index (`learn-correction-index.jsonl`) is not built. Each System One record already carries `ref` and `state_sha256`, so the verdict writer joins on the records. A second file would hold the same pairs.
- The block takes the mode from `bin/flow-s1-mode.sh learn.correction` (from #283), the one place that applies the mode rule: the lower of the user's mode (user settings or plugin default) and the full cascade's, so a repository can lower the mode but never raise it, and with no provider the site is off. It runs nothing unless that mode is shadow or on.
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

- Site off for the user, provider none, settings-refused, python-missing, unknown-site: no request; the section prints what it printed before, byte for byte. With the mode off the second miner run does not happen.
- Timeout, connection, http-<status>, redirect, malformed, abstained, missing-answer, below-threshold for one candidate: that candidate is unanswered (middle band, miner order); the others keep their answers. All unanswered: output identical to before.
- Slow provider: screening starts no call after 60 s have passed and asks at most 100 candidates; a call already started may run to its own timeout (at most 30 s from flow-s1.sh), so screening ends within 60 s plus one call. The rest are unanswered, and on mode prints S1_STATE=partial. Shadow mode prints nothing either way, so a cut shadow run is not reported.
- A transcript path longer than 200 characters: the miner's Line cell cuts it and ends it with an ellipsis. Phase 2 passes the full path it re-read; the verdict writer refuses a cut path with exit 2 rather than writing nothing silently.
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
- Verdict writer `bin/flow-learn-verdict.sh --line <full transcript_path>:<line_no> --verdict kept|dropped`: the ref names the transcript by its file name only (the Claude Code session id), so the same file name in another directory joins the same record; finds the last `learn.correction` record written with that ref in the last 24 hours in the per-user state directory and appends `{ts, site, ref, state_sha256, verdict}` to `learn-correction-verdicts.jsonl` there. Without such a record it writes nothing and exits 0. It never prints transcript text.
- questions.yaml gains `learn.correction` with question `is_correction` (noul), threshold default 0.8, provisional.
- tests/lib/s1_stub.py gains `by_state: [{contains, status?, body?}]`, first match wins, falling back to `status`/`body`.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Ordering key | sort by confidence, not p, so a confident "no" (p 0.03) sorts first | on scenario with p 0.95, a 500 and p 0.03 in a miner order that differs from the expected order |
| Off and no-answer identity | S1_ lines, a blank line or a reordered table leak when nothing answered; second miner pass with the site off | off, no-provider, http-500, abstained and below-threshold scenarios compare stdout with the off run; off logs 0 requests |
| Shadow purity | shadow reorders or prints S1_ lines, or skips records | shadow stdout equals off stdout; records carry mode shadow, current keyword-candidate, the ref and the digest of the state built from the fixture |
| Repository raising the mode | a repository's shadow or on sends the user's transcript text | repo shadow and repo on with no user uses: 0 requests; user on with repository shadow: shadow (records, output unchanged); the mutant that reads the mode from every tier instead of flow-s1-mode.sh fails the repo-shadow scenario |
| Row join | rows matched by position, so a grown transcript moves an answer to another row | mismatch scenario: the jsonl run sees one extra candidate; S1_STATE=mismatch and miner order |
| Verdict join | keyed on row number or text, so unscreened rows get verdicts | writer for an unscreened line writes nothing; for a screened line the digest equals the record digest |
