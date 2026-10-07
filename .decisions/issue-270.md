# Decision Journal — Issue #270

**Title**: feat(flow): uncertain change-classification prompts show whether the change serves the issue
**Branch**: feature/issue-270-classification-s1
**Epic**: #258

## Specification

For each file that change classification puts in the uncertain band, Flow asks
the System One provider one yes/no question: does this change serve the
issue's objective? The site is `classify.serves-issue`, question
`serves_issue`. With the site `on` and a confident answer, the prompt for
uncertain files shows the model's estimate beside the existing signals. The
file stays uncertain, the user still chooses include or exclude, and
red-flag files are never sent. In `shadow` mode the user sees nothing new,
and the answer is recorded next to the user's choice: include,
include-cleanup (included as cleanup) or exclude. The site ships `off`.

The call is made by `bin/flow-classify-s1.sh`, run from two marker blocks,
`S1_CLASSIFY_BLOCK` and `S1_RECORD_BLOCK`, in `/flow:commit` Phase 3 and in
`/flow:start` CODE step 8.

### Non-goals

- The answer never changes a file's classification. An uncertain file stays
  uncertain and still needs the user's choice. A red-flag file is never asked
  about, sent or relabelled.
- Out-of-context, in-context and boy-scout files are not asked about.
- The Recommendation, the options and the "Blocking?" field of the
  escalation are not changed by the estimate.
- No change to `bin/flow-s1.sh`, `bin/_flow_s1.py`, `settings.json` or
  `schema.json`. `systemOne.uses` already accepts any site id, and an absent
  site is `off`.
- `/flow:address`, `/flow:debug` and `/flow:pr` pre-flight do not call the
  site, although they load change-classification.
- The site is not switched on by default. A later change may do that, citing
  the written comparison of shadow records.
- No change to the keyword signal or the signal weights.
- No comparison script in this change. The comparison is written from the
  shadow records before the PR closes (decisions file, shared rules).

### Failure modes

| Condition | Behavior |
|---|---|
| Mode off or shadow (ask) | Only the provider and the mode are read, no gh call, no request. `S1_ESTIMATE=none`, `S1_REASON=not-on`. The prompt is today's. |
| A repository sets the site above the user's mode (`on`, or `shadow` when the user's is `off`) | The user's own mode is used, as `bin/flow-s1-mode.sh` decides it for the client too (PR #283). One warning on stderr from the classify block; the record block discards the helper's stderr. This warning is the one exception to AC4 ("identical to today's" with the site off): it tells the user that a repository tried to switch the site on, and the prompt itself is unchanged. |
| No provider | `S1_REASON=provider-none` before any gh call or request. |
| Provider settings refused (plugin inside the repository) | `S1_REASON=settings-refused`. |
| Timeout | Each file's call is bounded by `systemOne.timeoutMs` (the client allows at most 30 s). `S1_REASON=timeout`, no note. At most 8 files are asked per prompt; files after the eighth get `S1_REASON=not-asked-limit`. |
| A call times out, cannot connect or gets a 5xx status | The helper marks the prompt's cache directory, and every later file of that prompt gets `S1_REASON=provider-unavailable` with no request, so one prompt waits out at most one timeout. |
| Slow answers across files | No file is started after 60 s from the start of the block (`S1_REASON=not-asked-time`). With one call (at most 30 s) and the issue fetch (at most 10 s) after that, a block ends within about 100 s, under the Bash tool's 120 s default. |
| `gh issue view` stalls (a dead connection, a credential prompt) | The fetch is stopped after 10 s, with anything it started: `S1_REASON=no-issue`, and the fetch is marked failed for the rest of the prompt. |
| The block is stopped (Bash tool timeout, the user) | INT and TERM end it through its EXIT trap, which removes the prompt's cache directory and its copy of the issue. |
| A path or a signal holds a quote, `$(...)` or a newline | Paths and signals never reach a shell line: the session writes them to a JSON file from `mktemp` with the Write tool, and the block reads it with jq. A file not made by mktemp directly in `$TMPDIR` (outside it, a symlink, a hard link, another owner), input that is not one object of files, or a path or signal with a control character gives `S1_INPUT=refused` and no request. |
| A shadow record is not written (a decision in another spelling, no issue, a red flag, a client error before the request, a file past the 8th) | One warning line on stderr for that file, with the reason (`not-asked-limit` past the 8th). A call that reached the provider is recorded whatever its result. |
| Record block with the site in any mode but shadow, or a mode that cannot be read | The block asks the helper for the mode before it reads anything else. It removes its input file and prints nothing, whatever the input holds: no warning for a missing jq, input it would refuse, or a decision in another spelling. |
| A rename or copy of a red-flag file (`git mv .env notes.md`, `cp .env notes.md`, or `mv .env notes.md` without git) | `S1_REASON=red-flag`: the source of a rename that git reports for the file is checked like the path, and so is every path in the last commit or the index whose content is the same as the file's. A copy of a red-flag file that was never committed or staged is not recognised. |
| One file fails, another answers | Each file is a separate call. The failure of one never hides another's estimate. |
| Below threshold, abstained, malformed, missing answer, http-* | `S1_REASON` is the client's reason, no note. In on mode the record keeps the answer and its result. |
| No issue (`--issue` empty, `(none)` or not a number), or `gh issue view` fails | `S1_REASON=no-issue`, no request. The blocks pass `--issue-cache`, a directory of their own, so the issue is fetched once per prompt and a failed fetch is not tried again for the other files. |
| No uncommitted change to the file | `S1_REASON=no-diff`, no request. |
| Binary file | The diff is sent as `(binary)`. |
| Large diff | The diff is cut to its first 400 lines and at most 64 KiB, then the client shortens strings to the token cap. `S1_TRUNCATED=true`. |
| `--file` names a directory, `.`, a deleted directory, or more than one file's diff would be read | `S1_REASON=no-diff`, no request: only the one named file is ever read. |
| The plugin is inside the repository | `S1_REASON=settings-refused`, no warning, whatever the site's mode: the user's own settings are read first and cannot be read there, so the user's mode is unknown and is not taken to be off. |
| Red-flag path reaches the helper | Refused before any state is built: `S1_REASON=red-flag`, no request. |
| Secret inside an uncertain file's body | Path patterns do not catch it, so its diff is sent to the configured provider. Documented in `references/system-one.md`. |
| Shadow outcome block never runs (session ends after the prompt) | No record for that file. The comparison counts these. |
| A path the `--ref` grammar does not take (a space, a parenthesis, over 200 characters) | The ref names the path's sha256 prefix instead, so the call and its record still happen. |
| gh, git or python3 missing | `S1_ESTIMATE=none` with a reason; the helper never fails the commit. |

### Interface contracts

- `flow-classify-s1.sh ask --file <path> --issue <N> --signals <text> [--run-id <id>] [--issue-cache <dir>]`:
  exit 0, or 2 for wrong arguments. stdout is KEY=value lines: `S1_FILE`,
  `S1_ESTIMATE` (p, the probability that the change serves the issue, to 2
  decimals, or `none`), then `S1_MODEL` and `S1_TRUNCATED` when answered, or
  `S1_REASON` when not (the client's reason, or `not-on`, `provider-none`,
  `settings-refused`, `red-flag`, `no-issue`, `no-repository`, `no-diff`,
  `python-missing`, `internal-error`). The classify block adds
  `not-asked-limit` for files after the eighth and `helper-missing` when the
  helper cannot be found.
- `flow-classify-s1.sh record --file <path> --issue <N> --signals <text> --decision include|include-cleanup|exclude [--run-id <id>] [--issue-cache <dir>]`:
  asks only in shadow mode, with `--current <decision>`. Exit 0 and no
  stdout when the record was written or the site is not in shadow mode;
  exit 3 and `S1_REASON=<reason>` when in shadow mode no record was written;
  exit 2 for wrong arguments. `ask` and `record` give
  `provider-unavailable` after an earlier file of the prompt timed out,
  could not connect or got a 5xx status.
- State JSON: `{"file":{"diff","path","status"},"issue":{"body","number","title"},"signals":[...]}`,
  keys sorted, no timestamps, so the same inputs give the same
  `state_sha256`. `--signals` is split on `;`.
- `--ref classify:issue-<N>/<path>`, or `classify:issue-<N>/sha256:<16 hex>`
  when the path does not fit the ref grammar.
- Records follow `references/system-one.md` § Records unchanged: current is
  `uncertain` for an on-mode ask, and `include`, `include-cleanup` or
  `exclude` for a shadow record. `include-cleanup` is a file the user
  included as cleanup (option 1 for a Boy Scout change). The question counts
  cleanup as not serving the issue, so these records are left out of the
  agreement count of every comparison; `include` and `exclude` are counted.
  With `--run-id` naming an existing run they go to
  `.flow/runs/<id>/system-one.jsonl`, otherwise to the per-user state
  directory.
- Settings: `systemOne.uses["classify.serves-issue"]` = off (default) |
  shadow | on. The mode used is the lower of the user's (user settings or
  plugin default) and the full cascade's: a repository can lower it, never
  raise it. `bin/flow-s1-mode.sh --all` decides it.
- The marker blocks read `S1_INPUT`, `ISSUE_NUM` and `RUN_ID`. `S1_INPUT`
  names a JSON file the session made with `mktemp` and wrote with the Write
  tool: `{"files": [{"path", "signals", "decision"}]}` (`decision` for the
  record block only). The block removes it once read. The classify block
  prints `S1_INPUT=refused` and `S1_REASON=<reason>` for input it refuses,
  and `not-asked-time` for files not started within 60 s.
- Prompt: with no answer, the Notes cell and "What I tried" are today's. With
  an answer, the Notes cell gets `serves issue: <p> (<model>)` and "What I
  tried" gets one sentence saying the estimate does not change the
  classification.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Mode gating between ask and record | Both blocks call the provider in every mode, so shadow asks twice and records `current=uncertain` | Requests are exactly one per file per shell in on (classify block) and shadow (record block); zero for the other block; every shadow record's current is include, include-cleanup or exclude |
| Shadow changes output | The helper prints an estimate or note in shadow | Classify block stdout under shadow equals off; no `S1_ESTIMATE` other than none |
| Red flags | `.env.local` is sent or gets an estimate, in on mode or on the shadow record path | The input lists `.env.local` and `docs/notes.md`: requests only for `docs/notes.md`, none whose body names `.env.local`, `S1_REASON=red-flag`; the same in shadow mode through the record block, with a warning line for `.env.local` |
| Confidence shown as the estimate | `S1_ESTIMATE` is \|2p-1\|, so p=0.05 shows as 0.90 | Stub p=0.05 gives `S1_ESTIMATE=0.05`; p=0.93 gives 0.93 (confidences 0.90 and 0.86 both clear 0.6) |
| Scenario passes for the wrong reason | The stub reply is malformed, so "no note" passes | The stub reply uses the client's noul shape (`{"type":"noul","noul":p}`); every no-answer scenario asserts its exact reason |
| start.md step 8 | Step 8 still sends only out-of-context files to the user | Step 8 names uncertain files and both blocks; the start.md record block with RUN_ID writes into that run's records |

## Corrections to the accepted spec

- The spec's stub reply `{answers:{serves_issue:{p:0.93}}}` is malformed for
  the client, which reads a noul's probability from `noul` and requires
  `type`. One risk row asserted `S1_ESTIMATE=0.86` (the confidence); the
  interface contract and the next row say the estimate is p. The tests
  assert p.
- After PR #278 a repository cannot switch a site on. The spec's
  provider-none scenario (repository settings `on`, no user settings) now
  gives `not-on`. The provider-none scenario sets `on` in the user's settings
  with no provider; a separate scenario checks that a repository's `on` is
  not honored.
- The diff is the uncommitted change (`git diff HEAD`, or the whole file when
  untracked), not the diff against the merge base. A file the branch already
  changed is in-context by the first primary signal, so it never reaches the
  uncertain band, and the uncommitted change is what is being classified.
  This also avoids a `gh repo view` call per file.
- The helper reads the provider (user tier) before fetching the issue, so
  off, shadow, provider-none and settings-refused make no gh call and send
  nothing.

## Threshold

`serves_issue` default 0.6, provisional. It satisfies the stated
constraints: p=0.93 (confidence 0.86) and p=0.05 (0.90) clear it, p=0.6
(0.20) does not. Shadow records keep every answer, below-threshold ones
included, so the value does not affect the data collected. The written
comparison (2026-10-07) did not replace it: there is no `models:` entry for
jev-1.13.0.

## Shadow comparison (2026-10-07)

Decision (user, 2026-10-07): write the comparison now from the replayed
records only, set the threshold from it or state the shortfall, and ship the
site off.

- Data: 180 replayed records, TypeSafe jev-1.13.0, shadow mode, sent
  2026-10-07 06:05-06:16 UTC through the integration copy at b5bc8541 (same
  `serves_issue` question, helper and client as this branch). Labels: 90
  include (a file the issue's merged PR changed), 90 exclude (a file from a
  nearby PR closing a different issue). These labels are proxies taken from
  merged pull requests, not choices any user made. No live records. Joined by ref;
  state_sha256 matched on all 180; no label set from an answer.
- Checked before reading answers: what a label-made result would look like.
  The set is balanced (always-include scores 50%). A trivial rule, "include
  when the issue names the file", matches 124/180 (69%), so the set is easier
  than live. Only 5 items are in the uncertain band (3 include, 2 exclude).
  Exclude labels are noisier: 61 same plugin as the positive, 24 from a PR
  sharing files with the issue's PR (labels.jsonl; method.md says 29).
- Broken-measurement checks: 5/180 answers with p in 0.4-0.6; 81 answers
  above 0.5 and 99 below; overall agreement 161/180 (89%) against a 50% base
  rate; on the 128 items whose issue does not name the file, 109 agree (85%)
  against 63% for always-exclude. Not degenerate.
- Results: every request answered; 23 below 0.6 (11 include, 12 exclude).
  Agreement by label: include 76/90, exclude 85/90. Confidence median 0.88
  agreeing, 0.52 disagreeing; 5 of 19 disagreements at 0.80 or more. Sweep:
  0.6 gives coverage 157/180 and agreement 148/157 (94%, Wilson 90-97%);
  0.8 gives 130 and 125 (96%, 91-98%); 0.95 gives 8 and 8.
- Threshold: kept at 0.6, provisional. The spec's minimum (40 judged
  uncertain files, at least 10 of each outcome) is not met: 5 uncertain-band
  items and no live records. The spec names no rule for picking a value from
  the sweep, so none was invented. The site ships off. The comparison is in
  references/system-one.md under classify.serves-issue.
