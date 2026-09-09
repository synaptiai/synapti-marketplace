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

Seven arms, three cases, N runs each (default 3):

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

Every trap passes the degenerate inputs agents reach for first (identical
streams, palindromes, equal weights, a single request, `len % 4 == 0`) and
fails on the hand-derived inputs in `hidden/test_hidden.py`. The suites were
written from the spec, checked against `hidden/reference_impl.py`, and run
against each variant in `hidden/traps/`; `hidden/traps.json` records which
tests each variant fails and `flow-eval-run.sh --check-cases` re-verifies all
of it offline.

Per run, the harness records (`runs/<arm>/<case>/<n>/result.json`):

- **hidden pass rate** — fraction of hidden tests passing. The score. Never
  the agent's own tests.
- **all_pass** — the run passed 100% of hidden tests.
- **traps** — per trap, whether the run fails every test that trap's variant
  fails (a signature match; some signatures nest, so a run can match several).
- **agent_tests** — files and `test_*` functions the agent wrote, literal
  inputs it fed to code, and the share that are degenerate.
- **cost_usd, num_turns, session_id, is_error, error, permission_denials,
  tool_counts, skills_invoked** — from the `stream-json` transcript
  (`stream.jsonl`, final event saved as `claude.json`). `skills_invoked` empty
  on a plugin arm means the plugin was loaded but its skills never entered
  context.

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

# print the plan and the exact command line per run, no API calls
plugins/flow/bin/flow-eval-run.sh --dry-run

# full comparison: 7 arms × 3 cases × 3 runs = 63 runs
plugins/flow/bin/flow-eval-run.sh --arm all --case all --runs 3 --out plugins/flow/evals/results/full

# one arm on one case, resuming an interrupted run (completed result.json files are skipped)
plugins/flow/bin/flow-eval-run.sh --arm enforce-risk --case money-allocator --out plugins/flow/evals/results/full

# re-aggregate an existing results directory
plugins/flow/bin/flow-eval-run.sh --aggregate-only --out plugins/flow/evals/results/full
```

Flags: `--arm <name|all>` (comma lists allowed), `--case <name|all>`, `--runs N`
(default 3 or prompt.md `runs`), `--model <m>` (default: the CLI default; no
model is hardcoded), `--max-turns N` (default 60), `--max-budget-usd X` per
run (default 4), `--max-total-usd X` (default 250; the runner stops with exit
3 before a run that could exceed it), `--timeout-seconds S` per run (default
1800), `--out <dir>` (default `plugins/flow/evals/results/<UTC timestamp>/`),
`--permission-mode acceptEdits|bypassPermissions`, `--dry-run`, `--keep-temp`,
`--aggregate-only`, `--check-cases`.

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

1. **Reading** — plain sentences: the decision-rule verdict, the risk-map
   difference, the baseline comparison, and a provisional flag when any arm
   has fewer than 3 runs on any case.
2. **Per arm** — mean hidden pass rate, share of all-pass runs, mean own-test
   count, mean degenerate share, mean cost, mean turns, error count (timeouts,
   `is_error`, non-zero exit, `error_max_turns`).
3. **Per arm × case** — the same with min–max of the hidden pass rate across
   runs.
4. **Trap catch rate** — per case, per arm, the share of runs whose
   implementation matched each trap's failure signature. Lower is better.
   Compare `enforce-*` against `off-*` on the order/position traps
   (`transposed_order`, `ties_last_first`, `sorted_output`): those are the
   ones degenerate inputs mask.

Read own-test count together with hidden pass rate. The study's failure mode
is "more tests, lower correctness": if `enforce-*` has the highest own-test
mean and degenerate share but not the highest hidden pass rate, the gate is
producing tests, not correctness.

## Decision rule

Let `enforce` be the mean hidden pass rate over `enforce-risk` and
`enforce-norisk`, `alt` the higher of the `suggest-*` mean and the `off-*`
mean, and the **run-to-run spread** the mean, over every arm × case cell, of
(max − min hidden pass rate across that cell's runs).

- If `alt − enforce > spread`, `testing.tddMode`'s default flips to `suggest`
  (`tddModeOptOut` stays a two-field opt-out for teams that want `enforce`).
  Verdict `flip-to-suggest`.
- Otherwise the default stays `enforce`. Verdict `keep-enforce`.
- With fewer than 3 runs per cell for every arm the verdict is provisional;
  the runner still prints it and marks the summary incomplete.

`specFirst.riskMap` is reported the same way (`*-risk` mean vs `*-norisk`
mean, "beyond"/"within the spread"); it stays `true` unless the `norisk` arms
win by more than the spread.

## Cost expectations

Smoke run on 2026-09-09 (Claude Code 2.1.266, CLI default model, sandbox
proxy): `--arm baseline --case money-allocator --runs 1 --max-turns 3` cost
**$0.078** and took 31 s for 4 turns; the agent wrote a correct `allocate.py`
in its first Write and the hidden suite scored 25/25 before `--max-turns`
stopped it (recorded as `error_max_turns`, which the full run's 60-turn cap
avoids). A one-turn probe that ran one Bash command cost $0.12. A complete
run that loads two skills, writes tests and iterates should land well under
the $4 per-run cap; with 63 runs the default `--max-total-usd 250` is the hard
ceiling, and the expected total for the full comparison is in the low tens of
dollars. `--dry-run` prints every command line without spending anything.

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

## Limitations

- **Three tasks, one language.** All cases are small, single-module,
  standard-library Python. Effects on multi-file or typed-language work are
  not measured.
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
