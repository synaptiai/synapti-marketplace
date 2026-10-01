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
and the answer is recorded next to the include or exclude choice the user
made. The site ships `off`.

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
| Mode off or shadow (ask) | No settings beyond the mode are read, no gh call, no request. `S1_ESTIMATE=none`, `S1_REASON=not-on`. The prompt is today's. |
| A repository sets the site `on` and the user did not | The user's own mode is used (the PR #278 rule), copied from `flow-s1.sh`. One warning on stderr. |
| No provider | `S1_REASON=provider-none` before any gh call or request. |
| Provider settings refused (plugin inside the repository) | `S1_REASON=settings-refused`. |
| Timeout | Each file's call is bounded by `systemOne.timeoutMs`. `S1_REASON=timeout`, no note. At most 8 files are asked per prompt; files after the eighth get `S1_REASON=not-asked-limit`. |
| One file fails, another answers | Each file is a separate call. The failure of one never hides another's estimate. |
| Below threshold, abstained, malformed, missing answer, http-* | `S1_REASON` is the client's reason, no note. In on mode the record keeps the answer and its result. |
| No issue (`--issue` empty, `(none)` or not a number), or `gh issue view` fails | `S1_REASON=no-issue`, no request. |
| No uncommitted change to the file | `S1_REASON=no-diff`, no request. |
| Binary file | The diff is sent as `(binary)`. |
| Large diff | The diff is cut to its first 400 lines, then the client shortens strings to the token cap. `S1_TRUNCATED=true`. |
| Red-flag path reaches the helper | Refused before any state is built: `S1_REASON=red-flag`, no request. |
| Secret inside an uncertain file's body | Path patterns do not catch it, so its diff is sent to the configured provider. Documented in `references/system-one.md`. |
| Shadow outcome block never runs (session ends after the prompt) | No record for that file. The comparison counts these. |
| A path the `--ref` grammar does not take (a space, a parenthesis, over 200 characters) | The ref names the path's sha256 prefix instead, so the call and its record still happen. |
| gh, git or python3 missing | `S1_ESTIMATE=none` with a reason; the helper never fails the commit. |

### Interface contracts

- `flow-classify-s1.sh ask --file <path> --issue <N> --signals <text> [--run-id <id>]`:
  exit 0, or 2 for wrong arguments. stdout is KEY=value lines: `S1_FILE`,
  `S1_ESTIMATE` (p, the probability that the change serves the issue, to 2
  decimals, or `none`), then `S1_MODEL` and `S1_TRUNCATED` when answered, or
  `S1_REASON` when not (the client's reason, or `not-on`, `no-issue`,
  `no-diff`, `red-flag`, `internal-error`).
- `flow-classify-s1.sh record --file <path> --issue <N> --signals <text> --decision include|exclude [--run-id <id>]`:
  exit 0 (2 for wrong arguments) and no stdout. It asks only in shadow mode,
  with `--current <decision>`.
- State JSON: `{"file":{"diff","path","status"},"issue":{"body","number","title"},"signals":[...]}`,
  keys sorted, no timestamps, so the same inputs give the same
  `state_sha256`. `--signals` is split on `;`.
- `--ref classify:issue-<N>/<path>`, or `classify:issue-<N>/sha256:<16 hex>`
  when the path does not fit the ref grammar.
- Records follow `references/system-one.md` § Records unchanged: current is
  `uncertain` for an on-mode ask, `include` or `exclude` for a shadow record.
  With `--run-id` naming an existing run they go to
  `.flow/runs/<id>/system-one.jsonl`, otherwise to the per-user state
  directory.
- Settings: `systemOne.uses["classify.serves-issue"]` = off (default) |
  shadow | on. A repository may set off or shadow; `on` counts only from the
  user's settings or the plugin default.
- The marker blocks read `FILES` (newline-separated uncertain paths),
  `ISSUE_NUM`, `SIGNALS_<n>`, `DECISION_<n>` and, in start.md, `RUN_ID`.
- Prompt: with no answer, the Notes cell and "What I tried" are today's. With
  an answer, the Notes cell gets `serves issue: <p> (<model>)` and "What I
  tried" gets one sentence saying the estimate does not change the
  classification.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Mode gating between ask and record | Both blocks call the provider in every mode, so shadow asks twice and records `current=uncertain` | Requests are exactly one per file per shell in on (classify block) and shadow (record block); zero for the other block; every shadow record's current is include or exclude |
| Shadow changes output | The helper prints an estimate or note in shadow | Classify block stdout under shadow equals off; no `S1_ESTIMATE` other than none |
| Red flags | `.env.local` is sent or gets an estimate | FILES holds `.env.local` and `docs/notes.md`: requests only for `docs/notes.md`, none whose body names `.env.local`, `S1_REASON=red-flag` |
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
included, so the value does not affect the data collected. It is replaced,
with a `models:` entry for jev-1.13.0, from the written comparison.
