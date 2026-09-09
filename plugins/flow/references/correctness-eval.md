# Correctness eval: does `testing.tddMode` / `specFirst.riskMap` change what ships?

Reference document for `plugins/flow/bin/flow-eval-run.sh` and the cases under
`plugins/flow/evals/`. Reproduces, at small scale, the method of Dan Luu's
"Agentic testing" study (https://danluu.com/agentic-testing/): give agents a
task with known subtle traps, score each run against a **hidden** test suite
the agent never sees, and compare instruction conditions. The study found
that naming a testing technique ("use TDD") made agents mimic its surface —
twice as many tests, fed with identical or palindromic inputs whose expected
values were copied from the implementation — while lowering correctness, and
that a short instruction about risky areas and independent checks scored best.
Flow ships `tddMode: enforce` by default and a `specFirst.riskMap` element; this
eval measures both.

## What is measured

Seven arms, four cases, N runs each (default 3), on one or more models:

| Arm | `testing.tddMode` | `testing.tddModeOptOut` | `specFirst.riskMap` | Plugin loaded |
|---|---|---|---|---|
| `baseline` | — | — | — | no (prompt's flow-only block removed) |
| `enforce-risk` | `enforce` | `false` | `true` | yes |
| `enforce-norisk` | `enforce` | `false` | `false` | yes |
| `suggest-risk` | `suggest` | `true` | `true` | yes |
| `suggest-norisk` | `suggest` | `true` | `false` | yes |
| `off-risk` | `off` | `true` | `true` | yes |
| `off-norisk` | `off` | `true` | `false` | yes |

`suggest`/`off` set `tddModeOptOut: true` because the skill's two-field rule
keeps `tddMode` at `enforce` while the opt-out is `false`.

Cases (`plugins/flow/evals/<case>/expected.md` has the trap tables):

| Case | Module | Hidden tests | Traps (wrong variants) |
|---|---|---|---|
| `four-stream-codec` | `fourstream.py` — split/pack/unpack with a jump table and per-stream reversal | 25 | transposed stream order, no reversal, whole-body reversal, big-endian table, ceil split, no validation |
| `sliding-window-limiter` | `ratelimit.py` — per-key sliding window with `(now-window, now]` semantics | 23 | inclusive boundary, fixed buckets, counting denied requests, shared counter, limit off-by-one, retry from newest, no monotonic check |
| `money-allocator` | `allocate.py` — largest-remainder split with index-order ties | 25 | round-half-up, ties last-first, ties by weight, sorted output, float arithmetic, divide-first, hardcoded places, accepts non-positive weights |
| `interval-algebra` | `intervals.py` — union/intersection/difference with independently open/closed ends, canonical output | 30 | merge only overlapping, merge any touching, point dropped, half-open point kept, intersection closed-or, difference keeps closedness, intersection not normalized, unsorted output, sort by lower only, equal lower takes farther flag, shorthand half-open, no validation, float endpoints |

The first three cases were solved by every arm on the first full run (see
Results below). A case added for the second run has to clear a bar first:
the no-plugin baseline (Sonnet 5, 3 runs) must fail at least one hidden
test in at least one run, recorded in its `expected.md`. `interval-algebra`
cleared it (100%, 93.3%, 96.7%): two of three runs sorted the sweep by lower
bound only and mis-merged a closed point listed after the open-ended
interval it should join, and one of them kept the wrong closed flag at an
equal lower bound. Four other candidates, 30 hidden tests and 9-18 trap
variants each, were built, calibrated and retired because Sonnet 5 solved
them three times out of three (each got the one revision the bar allows):

- a line-based changeset applier (original-text coordinates, id-ordered
  same-line inserts, overlap error with a canonical message, per-line
  CRLF/LF inheritance, a trailing-terminator invariant): 3/3 at 100%
  before and after a revision that removed the worked example and added
  two interaction rules; own tests caught 90-100% of the variants;
- a canonical line diff (minimal edit script with a lexicographic
  tie-break under `=` < `-` < `+`, unified hunks with the `2*context` join
  rule and zero-length range numbering): 3/3 at 100% once a `context=True`
  assertion that relied on `bool` being an `int` was dropped as unfair;
  every run implemented the suffix-cost tie-break correctly;
- an RFC 5545 recurrence expander (DAILY/WEEKLY/MONTHLY/YEARLY, `interval`,
  `wkst`, `bymonth`/`bymonthday`/`byday` with ordinals, `bysetpos`,
  `count`/`until`; reference cross-checked against python-dateutil on 2,229
  random rules): 3/3 at 100% before and after a revision that probed
  `interval` counting calendar periods rather than matching ones; own tests
  caught 82-90% of the variants;
- a single-room booking resolver (`resolve`/`conflicts`/`free_windows`
  over half-open `[start, end)` bookings with priority preemption, a
  segment-ends-only-when-the-winner-changes rule, id-ordered conflict pairs
  and clipped free windows; 17-18 variants): 3/3 at 100% ($0.22-0.26, 8
  turns) with the stateless winner key `(-priority, start, id)` that every
  run evaluated per elementary interval between breakpoints, and 3/3 at
  100% again ($0.23-0.26, 7 turns) after the one revision made the tie
  order state-dependent (a holder is never interrupted by an equal
  priority; a freed room goes to the waiting booking with the earliest
  `end`, then the smaller `id`, so the stateless key is wrong in both
  directions and the first calibration's three modules score 25/30 on the
  revised suite): every run kept the same breakpoint sweep and added a
  `current_holder` check in front of `min(candidates, key=(end, id))`,
  because the spec states each half of the rule in its own sentence and
  the worked example exercises both, while own tests caught 16/18 variants
  (all but the two free-window ones) — an order-sensitive rule that is
  spelled out is not the `interval-algebra` pattern, whose winning trap was
  an input shape the spec never named.

The pattern: rules that can be read are implemented, however many there
are; what beat the baseline was an order-sensitive sweep on an input shape
the agent never constructed (its own tests fed sorted intervals only). The
retired cases live in the branch history of this file's commits (the
booking resolver, never committed, only in the calibration records), not in
`evals/`. The booking resolver tested the "order-sensitive sweep" reading of
that pattern and did not clear: an order rule that the spec spells out gets
implemented like any other rule. What discriminated on `interval-algebra` was
an input shape the spec never named (unsorted input with a point after the
open-ended interval it joins), so the agent's own tests never fed it. A future
case should be built around an unnamed input shape the rules quietly depend
on, not around rule count and not around order-sensitivity as such.

Every trap passes the degenerate inputs agents reach for first (identical
streams, palindromes, equal weights, a single request, `len % 4 == 0`, a
single edit, sorted intervals) and fails on the hand-derived inputs in
`hidden/test_hidden.py`. The suites were
written from the spec, checked against `hidden/reference_impl.py`, and run
against each variant in `hidden/traps/`; `hidden/traps.json` records which
tests each variant fails and `flow-eval-run.sh --check-cases` re-verifies all
of it offline.

Per run, the harness records (`runs/<model>/<arm>/<case>/<n>/result.json`;
`<model>` is the `--model`/`--models` value or `default`):

- **hidden pass rate** — fraction of hidden tests passing. The score. Never
  the agent's own tests.
- **all_pass** — the run passed 100% of hidden tests.
- **traps** — per trap, whether the run fails every test that trap's variant
  fails (a signature match; some signatures nest, so a run can match several).
- **own_test_trap_catch_rate** — the share of trap variants the agent's OWN
  suite rejects (details in `own-test-traps.json`, method below). The
  secondary signal.
- **agent_tests** — files and `test_*` functions the agent wrote, literal
  inputs it fed to code, and the share that are degenerate.
- **model, models_used, model_requested** — `model` is the billed model with
  the largest cost among the `modelUsage` keys of the claude result event
  (a subagent on another model appears as a second key in `models_used`);
  `model_requested` is what `--model` asked for.
- **cost_usd, num_turns, session_id, is_error, error, permission_denials,
  tool_counts, skills_invoked** — from the `stream-json` transcript
  (`stream.jsonl`, final event saved as `claude.json`). `skills_invoked` empty
  on a plugin arm means the plugin was loaded but its skills never entered
  context.
- **project/** — a snapshot of the agent's module and `tests/` (without
  `.git`, plugin state and caches), so a run can be re-scored later with
  `_flow_eval.py rescore-own-tests`.

Own-test trap scoring (`bin/_flow_eval.py own-test-traps`, written to
`own-test-traps.json`): the run's project is copied to a scratch directory
and the agent's suite is run exactly as the agent ran it, `python3 -m
unittest discover -s tests -t . -v`, first against the agent's own module
and then once per variant in `hidden/traps/`, with the variant swapped in
under the case's module name, and once against `hidden/reference_impl.py`.
A trap is **caught by own tests** when at least one *oracle* test fails or
errors against that variant, where an oracle test is one that passes on
both the agent's module and the reference; the catch rate is caught / traps.
The reference run matters: every variant inherits the reference's behaviour
on the rules it does not override, so a test that already disagrees with the
reference (an input-validation edge the agent read differently, say) would
otherwise count as catching every variant. Such tests are recorded under
`disagree_with_reference` and ignored (the first calibration showed 100%
catch rates across the board before this filter existed, all from one
validation test). The suite is only used as an oracle when it can be one:
`catch_rate` is `null` with a `reason` when `tests/` is missing, discovery
finds no tests, the tests never import the module (or import it under
another name), no test passes on both implementations, or the tests use
names the variants do not define (a private helper the agent added, which
would make every variant "fail" on an AttributeError rather than on
behaviour). Unscored runs are excluded from the mean, and their reasons are
listed per cell in `summary.json`.

Degenerate-input heuristic (`bin/_flow_eval.py agent-tests`): an input is a
literal sequence — bytes constant, list/tuple of constants, or `literal * n` —
passed directly to a non-assert call or assigned to a variable inside a
`test_*` function. It is degenerate when empty, single-element, all elements
identical, or a palindrome. Expected values inside `assertEqual` and computed
inputs (`bytes(range(10))`) are not counted. It is a proxy, not a judgment of
any single test.

## How to run

```bash
# verify cases offline (no API calls): reference passes, every trap variant fails its tests
plugins/flow/bin/flow-eval-run.sh --check-cases

# print the plan (model × arm × case × run) and the exact command line per run, no API calls
plugins/flow/bin/flow-eval-run.sh --dry-run --models claude-sonnet-5,claude-opus-5

# full comparison on two models: 2 × 7 arms × 4 cases × 3 runs = 168 runs (see Cost expectations for the caps)
plugins/flow/bin/flow-eval-run.sh --models claude-sonnet-5,claude-opus-5 --arm all --case all --runs 3 \
  --max-budget-usd 12 --max-total-usd 600 --out plugins/flow/evals/results/full-2

# one arm on one case, resuming an interrupted run (completed result.json files are skipped, per model)
plugins/flow/bin/flow-eval-run.sh --model claude-sonnet-5 --arm enforce-risk --case interval-algebra --out plugins/flow/evals/results/full-2

# re-aggregate an existing results directory
plugins/flow/bin/flow-eval-run.sh --aggregate-only --out plugins/flow/evals/results/full-2

# re-score own tests against the traps for every run that kept a project/ snapshot, then re-aggregate
python3 plugins/flow/bin/_flow_eval.py rescore-own-tests --out plugins/flow/evals/results/full-2 --evals-dir plugins/flow/evals
plugins/flow/bin/flow-eval-run.sh --aggregate-only --out plugins/flow/evals/results/full-2

# one-off: move results written by the first version (runs/<arm>/<case>/<n>) under their model
python3 plugins/flow/bin/_flow_eval.py migrate-layout --out plugins/flow/evals/results/full
```

Flags: `--arm <name|all>` (comma lists allowed), `--case <name|all>`, `--runs N`
(default 3 or prompt.md `runs`), `--model <m>` (default: the CLI default; no
model is hardcoded) or `--models <a,b>` (the whole plan once per model, in
order; results keyed by model), `--max-turns N` (default 60),
`--max-budget-usd X` per run (default 4), `--max-total-usd X` (default 250,
summed over every model in `--out`; the runner stops with exit 3 before a run
that could exceed it), `--timeout-seconds S` per run (default 1800), `--out
<dir>` (default `plugins/flow/evals/results/<UTC timestamp>/`),
`--permission-mode acceptEdits|bypassPermissions`, `--dry-run`, `--keep-temp`,
`--aggregate-only`, `--check-cases`.

Results land under `runs/<model>/<arm>/<case>/<n>/`. Directories written by
the first version (`runs/<arm>/<case>/<n>/`) are still read by
`--aggregate-only`, grouped under the model recorded in their `claude.json`,
and `summary.md` says how many were read that way; `migrate-layout` moves
them into the model layout once (idempotent, stamps `model` into each
`result.json`). Resume only recognises the model layout, so migrate before
continuing an old results directory.

Each run copies `scaffold/` to a fresh temp dir, `git init`s it, writes the
arm's `.claude/settings.flow.json`, and invokes `claude -p` from that
directory with `--plugin-dir plugins/flow` (absolute) on plugin arms. The
prompt is `prompt.md`'s body; the `<!-- flow-only -->` block is removed for
`baseline`. Permissions are `--permission-mode acceptEdits --allowedTools
<prompt.md allowed_tools> --permission-prompts none`, which works as root
(the CLI refuses `--dangerously-skip-permissions` for root; `bypassPermissions`
is available for non-root users). The child environment drops the parent
session's identity variables (`CLAUDECODE`, `CLAUDE_CODE_SESSION_ID`,
`CLAUDE_SESSION_ID`, `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_CHILD_SESSION`,
`CLAUDE_PID`, `CLAUDE_CODE_REMOTE_SESSION_ID`, messaging socket/token,
diagnostics and SDK tee files, `CLAUDE_AFTER_LAST_COMPACT`,
`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, `CLAUDE_CODE_SYNC_SESSION_REFS`,
session-ingress variables, `CLAUDE_ADDITIONAL_DIRECTORIES` and its CLAUDE_MD
twin, `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`, `CLAUDE_EFFORT`,
`CLAUDE_AUTO_BACKGROUND_TASKS`, `CLAUDE_CODE_HOLD_UNANSWERED_PARKED_PERMISSION`, and
`PYTHONSAFEPATH`, which the runner sets for its own helpers and which would
otherwise stop the child's `python3 -m unittest tests.x` from importing from
the project root)
and sets a per-run `FLOW_STATE_DIR`, so a nested run is neither mistaken for
the parent session nor shares flow ledgers with other runs. Credentials,
proxy and provider variables are left alone. User-global
`~/.claude/settings.flow.json` still sits below the arm's project file in the
cascade; keep it free of `testing.*`/`specFirst.*` keys while running.

`claude plugin eval plugins/flow` reads the same `prompt.md`/`graders/`
layout (the `file_exists` and `regex` graders are there for it) but on
Claude Code 2.1.266 it prints "currently in early access" and runs nothing,
and its grader types cannot run a hidden suite; the runner is the scoring
path.

## How to read summary.md

`summary.md` (and `summary.json`) under `--out`:

1. **Reading** — one paragraph per model, plain sentences: the decision-rule
   verdict and which signal decided it, the risk-map difference, the baseline
   comparison (hidden pass rate and own-test catch rate), and a provisional
   flag when any arm has fewer than 3 runs on any case.
2. **Per model × arm** — mean hidden pass rate, share of all-pass runs,
   **own tests catch traps** (mean own-test trap catch rate, with how many
   runs were scorable, e.g. `67% (8/9)`), mean own-test count, mean
   degenerate share, mean cost, mean turns, error count (timeouts,
   `is_error`, non-zero exit, `error_max_turns`).
3. **Per model × arm × case** — the same with min–max of the hidden pass rate
   across runs.
4. **Trap catch rate** — per model and case, per arm, the share of runs whose
   implementation matched each trap's failure signature. Lower is better.
   Compare `enforce-*` against `off-*` on the order/position traps
   (`transposed_order`, `ties_last_first`, `sorted_output`,
   `same_line_by_position`, `unsorted_output`): those are the ones degenerate
   inputs mask.
5. **Own-test trap catch rate** — per model and case, per arm and per trap,
   the share of scored runs whose own suite failed that variant. Higher is
   better: it says whether the tests an arm produces would have rejected the
   plausible wrong implementation, independently of whether the run's own
   implementation happened to be right. A trap that hidden tests never see
   tripped but own tests rarely catch (the first run's pattern) is one the
   agent got right without a test that guards it.

`summary.json` mirrors all of it under `per_model.<model>` (`per_arm`,
`per_cell`, `decision`, `run_to_run_spread`, `own_test_trap_spread`), with
`decision.verdicts` at the top level.

Read own-test count together with hidden pass rate. The study's failure mode
is "more tests, lower correctness": if `enforce-*` has the highest own-test
mean and degenerate share but not the highest hidden pass rate, the gate is
producing tests, not correctness.

## Decision rule

Applied per model. Let `enforce` be the mean hidden pass rate over
`enforce-risk` and `enforce-norisk`, `alt` the higher of the `suggest-*` mean
and the `off-*` mean, and the **run-to-run spread** the mean, over every
arm × case cell, of (max − min hidden pass rate across that cell's runs).

- **Primary signal.** If `alt − enforce > spread`, `testing.tddMode`'s default
  flips to `suggest` (`tddModeOptOut` stays a two-field opt-out for teams
  that want `enforce`). Verdict `flip-to-suggest`, `decided_by: primary`.
- If `enforce` is ahead of `alt` by more than the spread, the default stays
  `enforce`. Verdict `keep-enforce`, `decided_by: primary`.
- **Secondary signal.** When the two tie within the spread
  (`|alt − enforce| ≤ spread`, the first run's situation at ceiling), the
  own-test trap catch rate decides: let `enforce_own` and `alt_own` be the
  mean `own_test_trap_catch_rate` of the same arms and the **own-test
  spread** the mean per-cell (max − min) of that rate. If `alt_own −
  enforce_own > own-test spread`, verdict `flip-to-suggest` (`decided_by:
  secondary`, `secondary.verdict: alt-ahead`): the gate is not producing
  tests that guard against the traps any better than the alternative, at
  several times the cost. Otherwise `keep-enforce` (`secondary.verdict:
  enforce-ahead` or `tie`). If either side has no scorable own-test runs,
  the primary signal stands (`decided_by: primary`) and the reading says so.
- With fewer than 3 runs per cell for every arm the verdict is provisional;
  the runner still prints it and marks the summary incomplete.
- Two models can disagree; `summary.json` carries a verdict per model and the
  default is only flipped when the model the plugin is used with says so.

`specFirst.riskMap` is reported the same way (`*-risk` mean vs `*-norisk`
mean, "beyond"/"within the spread"); it stays `true` unless the `norisk` arms
win by more than the spread.

## Cost expectations

Measured (all Claude Code 2.1.266, sandbox proxy, list prices):

- First full run, 2026-09-09, Sonnet 5, 63 runs on the three original cases:
  **$68.12**, i.e. $0.17 per baseline run and $1.23 per plugin-arm run on
  average (`enforce-*` $1.6-1.8, `suggest-*` $1.3-1.4, `off-*` $0.6).
- `interval-algebra` calibration, Sonnet 5, baseline: $0.61, $0.50, $0.47
  (mean **$0.53**, 3.1x the original cases' baseline; 8-21 turns, 33-39 own
  tests). The retired candidates cost $0.22-0.93 per baseline run.

Estimate for the second full comparison (7 arms x 4 cases x 3 runs = 84
runs per model), derived from those figures:

| Model | Original three cases (measured) | `interval-algebra` (21 runs) | Total |
|---|---|---|---|
| `claude-sonnet-5` ($2/$10 per MTok) | $68 | baseline 3 x $0.53 = $1.6; plugin arms 18 x $1.6-$3.8 = $29-$69 (lower bound: plugin overhead fixed, task work 3.1x; upper: everything 3.1x) | **$100-$140** |
| `claude-opus-5` ($5/$25 per MTok, 2.5x Sonnet at equal token use) | $170 | $75-$175 | **$250-$350** |

Both models together: **$350-$490**; the `--max-total-usd` cap must be
raised above the default 250 (600 leaves headroom for re-runs after
session-limit errors, which cost eight runs on the first comparison). The
per-run cap must rise too: `enforce-*` runs already reach $1.8 on Sonnet, so
Opus `enforce-*` runs on the harder case can pass $4 (`--max-budget-usd 12`
keeps a runaway run bounded without cutting normal ones short). The unittest
gate fix shipped in 3.3.0 should lower the enforce arms' turn counts (40 on
the first run) and with them the plugin-arm costs, so the lower bounds are
the better guess. `--dry-run` prints every command line without spending
anything, and `summary.md` reports the actual total per model.

## Results: 2026-09-09, flow 3.3.0, Claude Code 2.1.266, CLI default model

Full comparison, 63 runs (7 arms × 3 cases × 3 runs), $68.12, zero errors after
discarding eight runs that hit the account's session limit and re-running them.
Records: `evals/results-2026-09-09/` (`summary.md`, `summary.json`, `runs.json`
with every session id). Every plugin-arm run invoked both
`flow:specification-capture` and `flow:tdd-patterns`; the baseline invoked
nothing from the plugin.

| Arm | Hidden pass rate | Own tests (mean) | Degenerate share | Cost (mean) | Turns (mean) |
|---|---|---|---|---|---|
| baseline | 100% | 24.3 | 38% | $0.17 | 7.9 |
| enforce-risk | 100% | 18.8 | 28% | $1.59 | 40.0 |
| enforce-norisk | 100% | 15.7 | 11% | $1.84 | 26.3 |
| suggest-risk | 100% | 18.0 | 34% | $1.40 | 19.1 |
| suggest-norisk | 100% | 18.8 | 33% | $1.31 | 15.4 |
| off-risk | 100% | 20.6 | 36% | $0.64 | 15.3 |
| off-norisk | 100% | 19.7 | 30% | $0.61 | 16.7 |

Verdict by the decision rule: `keep-enforce` (spread 0.0, no arm below any other).
What the numbers actually say:

- **Correctness is at ceiling.** Every run in every arm passed every hidden test
  and fell into no trap, including the no-plugin baseline in about eight turns.
  These three tasks do not discriminate correctness for this model, so the rule
  cannot flip the default on correctness grounds and does not. The study's
  failure mode (more tests, lower correctness) did not appear; the enforce arms
  wrote fewer own tests than the baseline, not more.
- **The gates cost turns and money for no measured correctness gain here.** The
  enforce arms spent about nine times the baseline and two and a half times the
  off arms per run. Reading the transcripts explains part of it: with
  `testing.taskCompletionGate: block` active, the agents' `python3 -m unittest`
  runs were not recognised as quality runs by `record-quality-run.sh`, so the
  TaskCompleted gate refused task completion until the agent worked around it
  (one run tried to add the pattern to settings and was denied). That is a
  plugin defect the eval surfaced, fixed in the same release by adding
  `unittest` to the built-in patterns; re-run before reading the enforce turn
  counts as the cost of TDD itself.
- **The oracle and discriminating-input rules change the tests written.**
  `enforce-norisk` produced the lowest share of degenerate literal inputs (11%
  against 38% for the baseline). With the risk map on, the share rose back to
  28%, which suggests the extra planning rows pushed agents toward the same
  simple literals they would reach for anyway; the risk map did not move the
  correctness score either way.
- **Decision.** `testing.tddMode` stays `enforce` and `specFirst.riskMap` stays
  `true`, by the rule and not by the ceiling: a result that cannot distinguish
  the arms is not evidence for flipping a default. The next run needs tasks that
  the baseline fails at least some of the time (larger modules, a second
  language, or traps that require reading a spec the agent cannot infer from the
  function signature), and it should run after the `unittest` fix so the enforce
  arms' turn counts reflect TDD rather than the gate.

## Results, round two: 2026-09-09, flow 3.3.0, Sonnet 5 full grid and Opus 5 on interval-algebra

105 runs, $184.65, zero errors after discarding and re-running every run
that hit the account's usage limit. Sonnet 5: 7 arms × 4 cases × 3 runs
(84 runs, $95.95). Opus 5: 7 arms × `interval-algebra` × 3 runs (21 runs,
$88.70), the one case whose Sonnet baseline fails. Every plugin-arm run
invoked both `flow:specification-capture` and `flow:tdd-patterns` (90 of
90). Records: `evals/results-2026-09-09-round2/` (`summary.md`,
`summary.json`, `runs.json` with every session id).

| Model | Arm | Hidden pass | All-pass runs | Own tests catch traps | Own tests | Degenerate share | Cost/run | Turns |
|---|---|---|---|---|---|---|---|---|
| Sonnet 5 | baseline | 99% | 75% | 90% | 26.3 | 56% | $0.27 | 9.3 |
| Sonnet 5 | enforce-risk | 99% | 92% | 92% | 19.5 | 44% | $1.89 | 28.9 |
| Sonnet 5 | enforce-norisk | 99% | 83% | 91% | 19.0 | 41% | $1.55 | 28.8 |
| Sonnet 5 | suggest-risk | 99% | 83% | 89% | 21.5 | 45% | $1.62 | 26.6 |
| Sonnet 5 | suggest-norisk | 99% | 75% | 93% | 19.3 | 38% | $1.15 | 21.5 |
| Sonnet 5 | off-risk | 100% | 92% | 91% | 22.2 | 45% | $0.79 | 16.2 |
| Sonnet 5 | off-norisk | 99% | 83% | 91% | 22.6 | 42% | $0.73 | 15.7 |
| Opus 5 | baseline | 100% | 100% | 97% | 57.7 | 73% | $1.13 | 11.7 |
| Opus 5 | enforce-risk | 100% | 100% | 95% | 56.0 | 69% | $5.61 | 25.7 |
| Opus 5 | enforce-norisk | 100% | 100% | 95% | 44.3 | 69% | $5.03 | 28.7 |
| Opus 5 | suggest-risk | 100% | 100% | 97% | 45.3 | 69% | $5.31 | 33.3 |
| Opus 5 | suggest-norisk | 100% | 100% | 92% | 47.3 | 71% | $5.30 | 36.7 |
| Opus 5 | off-risk | 100% | 100% | 95% | 50.3 | 72% | $4.46 | 31.3 |
| Opus 5 | off-norisk | 100% | 100% | 95% | 47.7 | 75% | $2.72 | 23.7 |

On `interval-algebra` alone (Sonnet 5, 3 runs per arm): baseline 97% with no
all-pass run; enforce-risk 96% (one run at 87%, two at 100%); enforce-norisk
98%; suggest-risk 98%; suggest-norisk 94%; off-risk 99%; off-norisk 97%.
Opus 5 passed every hidden test in every arm on that case.

Verdict by the decision rule, both models: `keep-enforce`, decided by the
secondary signal because the primary tied within the spread (Sonnet spread
1.3 points, own-test spread 5.7; Opus spread 0, own-test spread 8.8). What
the numbers say:

- **No flow setting moved correctness on either model.** Sonnet's plugin
  arms and baseline all sit at 99%, with all-pass rates from 75% to 92% that
  lie inside the run-to-run spread on the one discriminating case. Opus is
  at ceiling everywhere, including on the case Sonnet misses. The study's
  "more tests, lower correctness" failure did not appear: the enforce arms
  wrote fewer tests than the baseline, not more.
- **Own tests catch the same share of traps with or without flow.** Sonnet
  89% to 93% against a 90% baseline; Opus 92% to 97% against 97%. The oracle
  and discriminating-input rules did not make the agent's tests stronger
  against the seeded traps.
- **The rules do change which inputs get written, on Sonnet.** Degenerate
  literal inputs fell from 56% (baseline) to 38% to 45% on the plugin arms.
  On Opus the share stayed near 70% in every arm; Opus writes about 50 tests
  per run and the extra ones are mostly simple literals.
- **The cost is real and the gate defect is gone.** With `python -m
  unittest` recognised, the enforce arms still spend about six times the
  Sonnet baseline and three times the off arms per run, and about five times
  the Opus baseline. Turn counts roughly triple. That is the price of the
  RED/GREEN/REFACTOR loop itself now, not of a misfiring gate.
- **The risk map did nothing measurable.** Risk-on and risk-off arms differ
  by 0.3 points on Sonnet and 0 on Opus, within the spread, at similar cost.
- **Decision.** `testing.tddMode` stays `enforce` and `specFirst.riskMap`
  stays `true` by the rule as written: neither round produced evidence that a
  different default is more correct. The rule cannot see cost, and cost is
  where the arms differ; whether a default that costs three to six times more
  for the same measured correctness should stay the default is a product
  decision the eval informs but does not make.

## Limitations

- **Four tasks, one language.** All cases are small, single-module,
  standard-library Python. Effects on multi-file or typed-language work are
  not measured.
- **Own-test scoring needs the spec's public surface.** A suite that reaches
  into private helpers, or that renames the module, is not scored (null with
  a reason) rather than mis-scored; a suite that only exercises degenerate
  inputs scores 0%, which is the point. A trap counts as caught on any
  FAIL or ERROR, so a variant that raises where the agent's implementation
  did not is a catch even when the agent never asserted on that behaviour.
- **Model- and version-specific.** Results hold for the model and Claude Code
  version used; re-run after either changes. Record the `session_id`s from
  `result.json` when citing a result.
- **Small N.** 3 runs per cell puts the spread around one test's worth of
  pass rate; a gap inside the spread is noise, not evidence. Increase `--runs`
  before acting on a close call.
- **Trap attribution is by signature.** Nested signatures (a tie-order test
  also fails under round-half-up) make some runs match several traps; the
  hidden pass rate is the primary score.
- **The degenerate heuristic only sees literals.** Generated inputs are
  neither credited nor penalised.
- **Headless sessions are not interactive sessions.** `AskUserQuestion` is
  unavailable, so skills that would escalate take their recommended option.
  A denied tool shows up in `permission_denials`.
- **The eval measures the plugin as shipped.** Hooks, gates and skills other
  than the two under test are active on plugin arms; the baseline has none of
  them. Differences between `baseline` and plugin arms therefore include the
  whole plugin, while differences among plugin arms isolate the two settings.
