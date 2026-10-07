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
timing of the calls).

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
| N criteria | Calls run at the same time (at most 5 at once), so on mode adds about one timeoutMs. Shadow adds the same after Haiku. |
| State builder fails (unreadable goal, symlinked run or evidence directory) | No call; Haiku decides. |
| A sidecar cannot be read or parsed | Left out of the state: it counts as missing evidence, never as support. |
| Coverage none or judge_only | Unsupported whatever the answer; still asked so the record exists. |
| No run directory | Records go to the per-user system-one.jsonl; last-verdict.json is not written; the delta has no earlier System One set. |
| Record write fails | flow-s1.sh warns (discarded); the answer stands. |
| Mode value not off/shadow/on | Treated as off by the hook and by the client. |
| SIGTERM or SIGINT during calls | The EXIT trap kills the background calls and removes the work directory. |
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
- Supported: exit 0, p >= 0.5, coverage deterministic or mixed.
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
  Haiku counter. At failAfterStuckTurns the stop is approved with
  needs_human_review naming the unsupported criteria; the goal stays active,
  nothing is written to its lifecycle.
- Shadow: asked after Haiku's decision is printed, only on turns System One
  would have decided (same gate as on), with stdout and stderr discarded. No
  last-verdict, stuck, throttle or lifecycle write comes from it.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Which turns go to System One | incomplete_acs is taken as the command-less criteria, so an untrusted goal's not_executed criterion is judged | Untrusted goal with one command-less and one not_executed criterion, stub says supported: 0 requests, judge called once |
| Direction rule | p=0.95 on a criterion with no sidecar counts as supported | No sidecar, stub p=0.95: block naming the criterion, no judge call |
| All or nothing | One of two calls times out and the hook decides from the other | Two criteria, one delayed past timeoutMs: one judge call, Haiku's verdict |
| 0.6 floor | Floor applied to p, or the mean | p 0.95 and 0.75 (confidence 0.9, 0.5) gives needs_human_review; 0.95 and 0.85 gives achieved; questions threshold 0.2 in a plugin copy |
| Shadow output | flow-s1's stderr or a shadow answer reaches output or last-verdict.json | Same goal and judge reply in off and shadow: stdout, stderr and last-verdict.json byte-equal; one record per criterion with flow=<Haiku verdict> |
| Lifecycle | System One unchanged deltas fail the goal through _check_stuck | Three unchanged System One turns: approve with needs_human_review, goal status still active |

## Notes

- The spec said one file calls flow-s1.sh at 6bb62407; on 85b63bc4 no file
  calls it yet. This change adds the first callers.
- The spec's off/no-provider scenario compared against main's code; the e2e
  scenario compares against a run of the same code with no user settings,
  which needs no other checkout.
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

- Written from the replay records only (user's decision, 2026-10-07): 178
  items, TypeSafe jev-1.13.0, sent 2026-10-07 06:06-06:13 UTC. The 2026-10-02
  replay records were lost and every item was re-sent once with the same
  states and refs; the answers are a new measurement. No live records.
- Before reading answers, the checks for a result made by the set or labels
  were written down. Two hold: every negative is constructed or has no
  evidence, and whether the state shows command output drives the yes rate
  (29 of 32 with output, 10 of 31 without). The join is exact (178 refs, one
  record each, state sha256 equal).
- Per criterion: 153 of 178 agree with the label; 1 wrong yes (a constructed
  mismatch, confidence 0.56); at 0.5, 141 answered, 31 yes, 30 of 72
  supported items covered.
- Threshold not chosen. The spec's rule needs the wrong-"achieved" rate per
  turn; grouped by run, the 13 turns are all accepted goals, System One gives
  "achieved" on none at any threshold, and no turn should have been "not
  achieved", so the rate cannot be measured. No evaluator-loop Haiku verdict
  or timing exists for these runs, so the Haiku comparison and latency
  comparison are not possible. 0.5 stays, provisional; the site stays off.
- The comparison is in references/system-one.md, "Shadow comparisons".
