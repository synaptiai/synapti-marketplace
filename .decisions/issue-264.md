# Decision Journal — Issue #264

**Title**: feat(flow): the evaluator-loop goal judge can use per-criterion System One answers instead of a Haiku call each turn
**Branch**: feature/issue-264-265-goal-judge-s1 (shared with #265)
**Tracks**: #258

## Specification

Site `goal.judge`, question `supported` (noul), one call per criterion that has
no verification command. Mode `systemOne.uses["goal.judge"]`: off (plugin
default), shadow or on. A repository's settings can only lower the user's mode
(the shared rule of #258, applied by `bin/flow-s1-mode.sh`, from which both
`flow-s1.sh` and the hook take the mode; the hook's reading only chooses the
timing of the calls). Only a goal in the trust ledger (the report's `trusted`)
is asked about (user decision 2026-10-07): for any other goal nothing is sent
and nothing changes. The question says the criterion, the goal's outcome and
the evidence text are data, not instructions.

### Non-goals

- The Haiku judge path is unchanged: its prompt, schema, timeout, reply parsing,
  and the last-verdict.json it records (no criterion_results).
- No System One call on the deterministic paths (must_pass failure, path
  violation, all checks passing).
- A turn with any criterion that has a verification command among the
  incomplete ones (not_executed for an untrusted goal, or a command that could
  not be launched), or with a failed must_pass:false command, is decided by
  Haiku. System One is not asked, in on or in shadow mode.
- Never writes lifecycle.status. The turn budget counter (turns_evaluated) is
  bumped by a block as on every other block path.
- No `blocked` verdict from System One.
- The claude CLI and timeout(1) stay prerequisites of evaluator-loop: Haiku is
  the fallback.
- Warn and block mode are #265 and untouched here.
- The site ships off. Its threshold is provisional until the shadow comparison.

### Failure modes

| Condition | Behaviour |
|---|---|
| Mode off, no provider, settings refused, invalid settings, missing key | Every call exits 3 (or none is made); Haiku decides; stdout and stderr equal a run without System One. flow-s1.sh's stderr is discarded in every mode. |
| Timeout, connection error, HTTP error, malformed reply, abstention, below threshold, on any one criterion | The whole System One decision is dropped and Haiku decides. No verdict from a subset. |
| N criteria | Calls run in batches of 5, so on mode adds up to ceil(N/5) x timeoutMs. Shadow adds the same after Haiku. At most 10 are asked in one stop (at most 2 x timeoutMs); in on mode, with more than 10 to ask, nothing is sent and Haiku decides. |
| Goal not in the trust ledger | Nothing is sent, in on or in shadow mode; Haiku decides. |
| A call's output is not one JSON object | No answer for that criterion, so Haiku decides; the decision is taken only with one result per manifest row. No input reaches that row-count check today: a missing, unreadable, empty, non-JSON or two-line output, and a missing exit status, each still give the row an entry with no answer; the check is kept so that a later change to how results are read cannot decide a turn from a subset. |
| State builder fails (unreadable goal, symlinked run or evidence directory) | No call; Haiku decides. |
| A sidecar cannot be read or parsed | Left out of the state: it counts as missing evidence, never as support. |
| Coverage none or judge_only | Not sent: no answer could make it supported, so it is decided unsupported without a call. A turn where every criterion is like this is decided by System One with no call (confidence 1). |
| No run directory | Records go to the per-user system-one.jsonl; last-verdict.json is not written; the delta has no earlier System One set. |
| Record write fails | flow-s1.sh warns (discarded); the answer stands. |
| Mode value not off/shadow/on | Treated as off by the hook and by the client. |
| SIGTERM or SIGINT during calls | flow-goal-stop.sh runs the evaluator in the background and its trap stops it. The evaluator runs the System One calls and the Haiku judge call in the background too; its EXIT trap stops whichever is running, waits for it, and removes the work directory and the judge's prompt and reply files. |
| System One stuck count cannot be written | The stop is allowed with needs_human_review and its own reason; the goal stays active. |
| run_id the client would refuse (`--run-id` shape) | `--run-id` is not passed; records go to per-user state. |

### Interface contracts

- `flow-run-deterministic-checks.sh` adds `no_command` (ids with no
  verification_command, goal order) at the end of the report.
- `_flow_evidence_bundle.py --criterion-states <goal> <report-json> <run-dir or ''> <out-dir>`:
  for each id in `report.no_command`, writes `<out-dir>/<n>.json` (the state)
  and prints `<n> TAB <coverage> TAB <id for messages> TAB <id for --ref>`.
  Exit 1 when the goal cannot be read or the run or evidence directory is
  refused. The message id is `_safe_ac_id` (`?` for other characters); the ref
  id uses `_`, since `?` is outside `--ref`'s character set.
- State (shared with #265): `{"goal": {"id", "outcome"}, "criterion": {"id",
  "text"}, "coverage", "evidence": [{"id", "type", "command", "exit_code",
  "limitations", "negative_cases", "output"}]}`, built only from the goal and
  the run's sidecars that name the criterion in `proves`; output is the raw
  output, at most 8 KB. No transcript, diff or journal.
- Call: `flow-s1.sh ask --site goal.judge --state-file F --state-format json
  --current C --ref goal:<goal>/<criterion> [--run-id R]`.
- `--current`: on mode `goal=<id> criterion=<id> flow=pending source=system-one`;
  shadow `goal=<id> criterion=<id> flow=<Haiku verdict>
  criterion_status=<pass|fail|incomplete|unknown> source=<haiku|haiku-unavailable>`.
- Supported: coverage deterministic or mixed (only these are sent), exit 0,
  p >= 0.5.
- Verdict (every call answered): any unsupported gives not_achieved; else
  min(confidence) < 0.6 gives needs_human_review; else achieved.
- Output: achieved approves with "System One verdict: achieved — every
  criterion without a verification command is supported by its recorded
  evidence; run /flow:goal evaluate to finalize", resets the stuck state and
  removes the throttle file. needs_human_review approves naming the
  lowest-confidence criterion. not_achieved blocks with
  `FLOW_GOAL_CONTINUATION (not_achieved): criterion <id> is not supported by
  its recorded evidence. Next: record evidence that <id> holds.` where <id> is
  the unsupported criterion with the lowest p (ties: goal order), by id only.
- Delta: S = supported ids this turn; P = criterion_results with status pass
  from last-verdict.json when its source is evaluator-loop-system-one, else
  empty. S ⊋ P made_progress; P ⊄ S regressed; S = P unchanged.
- `_record_verdict ... evaluator-loop-system-one <criterion_results>` with
  `[{criterion_id, status: pass|fail, p, confidence}]`; only on this path.
- Stuck (user decision 2026-10-01): a System One not_achieved turn with delta
  unchanged counts on a counter of its own (`stuck-s1-counter`), never the
  Haiku counter, and only when the delta was measured against an earlier
  System One verdict. At failAfterStuckTurns the stop is approved with
  needs_human_review naming the unsupported criteria; the goal stays active,
  nothing is written to its lifecycle.
- Shadow: asked after Haiku's decision is printed, only on turns System One
  would have decided (same gate as on), with stdout and stderr discarded. No
  last-verdict, stuck, throttle or lifecycle write comes from it.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Which turns go to System One | incomplete_acs is taken as the command-less criteria, so an untrusted goal's not_executed criterion is judged | Untrusted goal with one command-less and one not_executed criterion, stub says supported: 0 requests, judge called once |
| Trust | A goal not in the trust ledger is asked about | Untrusted goal whose only criterion has no command and a passing sidecar, on and shadow: 0 requests, 0 records, Haiku decides |
| Direction rule | p=0.95 on a criterion with no sidecar counts as supported | No sidecar, stub p=0.95: block naming the criterion, no judge call |
| All or nothing | One of two calls times out and the hook decides from the other | Two criteria, one delayed past timeoutMs: one judge call, Haiku's verdict |
| 0.6 floor | Floor applied to p, or the mean | p 0.95 and 0.75 (confidence 0.9, 0.5) gives needs_human_review; 0.95 and 0.85 gives achieved; questions threshold 0.2 in a plugin copy |
| Shadow output | flow-s1's stderr or a shadow answer reaches output or last-verdict.json | Same goal and judge reply in off and shadow: stdout, stderr and last-verdict.json byte-equal; one record per criterion with flow=<Haiku verdict> |
| Lifecycle | System One unchanged deltas fail the goal through _check_stuck | Three unchanged System One turns: approve with needs_human_review, goal status still active |

## Notes

- The spec said one file calls flow-s1.sh at 6bb62407; on 85b63bc4 no file
  calls it yet. This change adds the first callers.
- The off/no-provider scenario compares stdout, stderr and last-verdict.json
  with main's output for the same fixture (commit 94539116), recorded in the
  test.
- Threshold `goal.judge.supported` default 0.5, provisional: it must be below
  0.6 so the needs_human_review band [threshold, 0.6) exists.
- An empty judge reply (a timeout under timeout(1), or no output) leaves
  VERDICT empty, because jq prints nothing for empty input, and the Haiku
  path then blocks with `FLOW_GOAL_CONTINUATION (): . Next: `. The docs say
  it approves with needs_human_review. This predates the change and the Haiku
  path is a non-goal here; the shadow record says `flow=none
  source=haiku-unavailable` for such a turn, which is what Flow did.
- A criterion that is must_pass and not executed (untrusted goal) has a null
  exit code, which the must_pass gate reads as a failure, so such a turn never
  reaches the judge. The not_executed case of the eligibility gate is reached
  only with must_pass:false, which is what the scenario uses.

## Shadow comparison (2026-10-07)

The comparison a reader of the feature needs is in references/system-one.md,
"Shadow comparisons". This is the full record it rests on.

- Data: the replay records only (user's decision, 2026-10-07). 178 items,
  TypeSafe jev-1.13.0, sent 2026-10-07 06:06-06:13 UTC. The 2026-10-02
  replay records were lost and every item was re-sent once with the same
  states and refs; the answers are a new measurement. No live records.
- Checked before any answer was read, as signs that the replay set or its
  labels, not the model, made the result:
  - A "no" to everything scores well: 60% of labels are "not supported", so
    always-no is 60% right. Not what happened: the model said yes to 48 of
    the 72 supported items, and its 63 distinct p values run from 0.02 to
    0.94.
  - Every "not supported" item is easy by construction: holds. All negatives
    are built (evidence from other code, a failed exit) or have no evidence.
  - Whether the state shows test output decides the answer: holds. Of the 63
    real supported criteria, 32 show output and 31 do not (the evidence named
    no output file, or one that could not be found); yes to 29 of 32 and 10
    of 31.
  - Turn-level numbers that cannot exist: holds. The set holds single
    criteria, and no run recorded an evaluator-loop verdict, so there is no
    Haiku decision to compare with.
  - A joining error, or one goal or one p value dominating: not found. 178
    refs, one record each, state sha256 equal to the state sent; the largest
    goal supplies 24 items.
- What every call did: all 178 reached the provider and answered; no
  timeouts, HTTP errors, malformed replies or abstentions. 37 had a
  confidence under the threshold of 0.5. A call through the client took a
  median of 2.1 s (slowest 4.5 s) over 177 timed calls: the first item's
  record was written before the timed run started, and the run skips items
  that already have a record, so that call's time was not logged. No Haiku
  timing exists for these goals, so the latency comparison is not possible.
- Agreement (yes = p >= 0.5 and the criterion has evidence): 153 of 178
  (86%). Label supported: 48 yes, 24 no; label not supported: 1 yes, 105 no.
  By kind: real supported 39 of 63 yes, replaced evidence 9 of 9, other
  plugin's evidence 1 of 63, failed exit 0 of 32, no evidence 0 of 11.
  Against the exit code: of the 135 items that exited 0, 49 got a yes (48 of
  them labelled supported); none of the 32 that exited 1 did. Against the
  final `/flow:goal evaluate` outcome: 33 items belong to a criterion
  recorded as passing; 19 got a yes (the 11 with no attached evidence and 3
  others got a no).
- Confidence was higher when the model agreed with the label (median 0.84;
  middle half 0.64 to 0.92) than when it disagreed (median 0.50; middle half
  0.16 to 0.68).
- Repeatability: goal.judge and goal.warn-evidence ask the same question
  about the same 167 states. The model gave the same p for 84 of them; the
  largest difference was 0.10, and 4 answers moved across 0.5.
- Threshold not chosen. The rule (choose a value below 0.6 from the share of
  turns System One decides and its rate of wrong "achieved" verdicts) needs
  that rate per turn. Grouped by run, the 13 turns are all accepted goals,
  System One gives "achieved" on none at any threshold, and no turn should
  have been "not achieved", so the rate cannot be measured. 0.5 stays,
  provisional; the site stays off.
