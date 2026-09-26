# Review-precision eval: does the grounding critic make the review fan-out better?

Reference document for `plugins/flow/bin/flow-eval-run.sh --mode review`. The
correctness eval (`references/correctness-eval.md`) measures what an implementer
ships. This one measures what a reviewer finds: it puts the default review
fan-out in front of a diff whose defect is already known and scores the findings
that come back.

It exists because `review.groundingCritic` (issue #215) ships off by default and
rests on one result from one model family. The repository's rule is that a gate
is measured before it is trusted, and the setting's default changes only on the
numbers this eval produces.

## What is measured

| Arm | `review.groundingCritic` | Plugin loaded |
|---|---|---|
| `review-b` | `off` | yes |
| `review-b-critic` | `on` | yes |

Both arms load the plugin. There is no no-plugin arm here: the thing under test
is the critic pass, not the plugin.

## What the session receives

Everything a session under test is handed, where it comes from, and what keeps it
from carrying the answer or the operator's own setup:

| Input | Value | Why it is safe |
|---|---|---|
| Working directory | a scratch git repository in a new temporary directory | named at random with a neutral prefix, so the path does not say it is an eval; holds the module on two branches and nothing else |
| `--plugin-dir` | a copy of the plugin without `evals/`, `tests/` and the two eval references, in a neutrally named temporary directory | refused if the plugin holds a symlink; checked afterwards for any file or directory, or any text in a file, that names a trap |
| `CLAUDE_PLUGIN_ROOT` | the same copy | a session's Bash tool does not set it, and without it the commands' lookups find the operator's installed flow, whose own files include `evals/` |
| `FLOW_USER_SETTINGS` | `<n>/settings.json` in a neutrally named temporary directory outside `--out`, `<n>` being the arm's position in the plan | holds only the arm's value; the path names neither the arm, the case nor the trap, and does not lead to earlier runs' records |
| `FLOW_STATE_DIR` | `.flow-state` inside the scratch repository | per run, deleted with it |
| `--setting-sources project,local` | the user's Claude Code settings are not read | installed plugins, hooks and permissions live there |
| `--strict-mcp-config`, empty `--mcp-config` | no MCP server | |
| The rest of the environment | built from nothing: only `PATH`, `HOME`, `USER`, `LOGNAME`, `SHELL`, `TMPDIR`, `TERM`, `LANG`, `TZ`, `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_OAUTH_TOKEN`, proxy and CA-certificate variables, `LC_*`, `ANTHROPIC_*`, `CLAUDE_CODE_USE_*`, `CLAUDE_CODE_SKIP_*_AUTH` and the cloud providers' own variables are passed on, when set | a variable nobody listed never arrives: a parent session's id, a path to its transcript, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` (which would send every run down Path A and past the grounding pass). `HOME` and `CLAUDE_CONFIG_DIR` are kept because the login lives there |
| Claude Code's own memory file under the config directory | not tested whether a session reads it | not something the runner controls: keep it free of eval material on a machine that runs the eval |

`/flow:review` reads `review.groundingCritic` from the user settings and the plugin
default only, which is why the arm's value is handed over as the user settings. A
keychain or OAuth login carries over; an `apiKeyHelper`, or `env` entries such as
`ANTHROPIC_BASE_URL`, in the user's `settings.json` do not, so export those in the
shell that starts the runner. The session is not a sandbox: one that searches the
disk can still find the repository and any installed copy of flow.

One cell of the matrix is a model, an arm, a case and a trap. Each cell runs N
times (default 3).

## The scratch repository

Per case and trap, the runner builds a git repository outside the plugin tree:

    reference_impl.py   only when this variant still calls into it, on both
                        branches, carrying the same docstring-stripped text
                        the module is built from
    <module>.py         on main: the reference implementation
                        on review-candidate: the materialized trap variant

`flow-eval-run.sh --mode review --case <name> --trap <name> --build-review-repo
<dir>` builds one of these and stops, which is how to see what a review run is
actually handed without spending anything.

A trap variant as it is stored is a few lines that import the reference and
redefine one name, or subclass one of its classes and override one method.
Committed as the module it would replace the whole file, and every finding that
named the file would land inside a hunk — precision and recall of 1.0 for a
reviewer that read nothing. So the variant is **materialized** first: its
redefinitions are written into the reference's own source, an overridden method
is written into the reference's class where that method is defined, and the
wiring that only existed to install the subclass is dropped. Across the 34
shipped variants this leaves between 1 and 15 changed lines, four or fewer for
20 of them, and 5% of the module inside a hunk.

Two safeguards:

- `--check-cases --mode review` runs the hidden suite against the materialized
  module and requires it to fail exactly the tests the stored variant fails.
  Folding the defect in must not change what the defect does.
- The module docstring is stripped from both branches. Every case's reference
  opens by naming the hidden suite and the trap variants, which would tell the
  reviewer it is being tested and where to look. It is removed from the
  reference and the variant alike, so the branch diff is unchanged.

`reference_impl.py` is committed only for the 15 variants that still call into
it, and then on both branches unchanged, so the branch diff is the module file
alone either way. The other 19 do not get it: a pristine correct copy of the
module under review locates the defect by diff alone. The copy is written
through `reference-module`, so it carries the same stripped text as the module
rather than the shipped docstring naming the hidden suite.

The session is asked to review `main...review-candidate` by dispatching the same
five reviewer agents `/flow:pr` Phase 3 dispatches, and to end with its
consolidated findings as one fenced JSON block:

    [{"id": "F1", "priority": "P1", "category": "correctness",
      "file": "<module>.py", "line": 12, "problem": "…", "confidence": "HIGH"}]

The scorer reads the last fenced block tagged `json` or `jsonc`, or the last
untagged block when no block carries either tag, so an example block shown
earlier, or a `python`, `bash` or bare block holding a suggested fix or a repro,
is never read as the answer. A fence opener may carry an info string after the
tag (`python title="r.py"`); only its leading word is the tag.

There is no GitHub remote, so `/flow:review`'s `gh pr` steps are not exercised.
Review runs are granted `Bash,Read,Glob,Grep,Skill,Agent` and the task tools;
`Write` and `Edit` are withheld, and any attempt to use them is recorded in the
run's `permission_denials`. That grant is what `--permission-mode acceptEdits`,
the default, passes. `--permission-mode bypassPermissions` passes no tool grant
at all, so `Write` and `Edit` are available and nothing is denied.

Withholding `Write` and `Edit` does not make a run read-only. `Bash` is granted
without restriction, because the reviewer agents run commands, so a session can
still change files with it (`sed -i`, `git checkout`, `git commit`). What it is
handed is a scratch repository and, as `--plugin-dir`, a copy of the plugin
without `evals/`, `tests/` and the two eval references, made once per plan and
removed at the end (kept and named under `--keep-temp`): the hidden suites, the
trap variants, the recorded `changed_lines` and the prose that names the traps
are not in it, and scoring reads them from this repository. A plugin that
holds a symlink is refused, since a link could carry them in. That keeps the
answer key out of what the session is given; it is not a sandbox, and a session that searches the disk for
the repository can still find it. GitHub tokens in the operator's environment
are not passed on, but a `gh` login stored under `HOME` stays reachable; the
prompt tells the session not to run `gh`, and the runner does not enforce that.

## Scoring

`python3 bin/_flow_eval.py score-review --case <dir> --trap <name> --findings <file|json>`
scores one run offline and is what the runner calls when a run finishes.

A **changed hunk** is a variant-side line range of the reference-to-variant
diff. `--check-cases --mode review` computes them and records them per variant
in `hidden/traps.json` as `changed_lines`, a list of inclusive `[first, last]`
pairs, beside `changed_lines_digest`, a digest of the reference and variant
sources they were computed from. Scoring always computes the hunks itself and
uses the recorded ranges only when they are exactly the computed ones and the
digest still matches, so a record can confirm the diff but never replace it.
`changed_lines_source` says which happened: `traps.json` when the record was
used, `computed` when nothing was recorded, and otherwise `computed:` followed
by why the record was not used — `traps.json-malformed` (not a list of
`[first, last]` integer pairs), `traps.json-unpinned` (no digest, so nothing
says what it was computed from), `traps.json-stale` (the sources have moved
since) or `traps.json-mismatch` (the digest matches but the ranges are not the
diff's).

A change that only deletes lines is anchored to the variant lines that flank
the removal, because a deleted line has no line number a reviewer could cite.

- A run is a **hit** when at least one P1 or P2 finding cites the case's module
  and a line inside a changed hunk.
- Every other P1/P2 finding is a **false finding** — a finding on another file,
  on a line outside every hunk, with no usable line number, and also a second
  finding that lands on a hunk the run already hit. The run was asked for the
  defect, not for a list of remarks about the changed lines.
- P3 findings are neither. They never reach the critic and they do not enter
  precision.
- No findings at all is a miss with no false findings: the run answered, and the
  answer was wrong.
- A run whose findings block is missing, is not JSON, or is not a list, and a
  run that timed out, is **incomplete**: it is scored as a miss, it carries a
  `reason`, and it is left out of precision, recall and F1 and counted on its
  own. A broken run must never read as a clean miss.
- Each arm must run what it is named for. A critic-arm run that reports a P1 or
  P2 finding and never ran `finding-critic` is incomplete, with the reason
  `critic-not-dispatched`; a plain-arm run that ran it is incomplete, with the
  reason `critic-dispatched-in-plain-arm`. Either would make the two arms look
  alike. A call whose result came back as an error ran nothing, and a name that
  only contains `finding-critic` is not the critic. A critic-arm run with no P1
  or P2 finding gave the critic nothing to audit and is scored.

Each finding's confidence is kept, so the summary can show whether LOW-confidence
findings are the ones that land outside the hunks.

Per model and arm:

- **recall** — hits over scored runs. Higher is better.
- **precision** — hits over hits plus false findings. Higher is better.
- **F1** — the harmonic mean of the two. Higher is better.
- **findings per run** — P1/P2 findings per scored run.
- cost, turns, output tokens and cache hits, as in the correctness summary.

## Spread

Run 1 of every case and trap is one replication of the matrix, run 2 is the
next, and so on. Each replication gets its own F1; an arm's spread is the
largest of those minus the smallest, and a model's spread is the mean over its
arms. A single run is not a replication: a matrix run once has no spread, and
the adoption rule cannot be applied to it.

A per-run F1 is not used for this. One run either hit the defect or did not, so
its recall is 1 or 0 and its F1 swings between extremes whatever the arm does.

## Adoption rule

`review.groundingCritic` becomes the default only when the critic arm's F1 beats
the plain arm's by more than that model's run-to-run spread, on every model that
ran, with at least two models. Everything else is recorded as a no-change
outcome — `keep-off` when the models ran and the gain did not clear the spread,
`insufficient-models` when fewer than two ran. No improvement is a result, not a
failed run.

Incomplete runs are left out of F1, so an arm whose misses time out reads better
than it is. A result record that cannot be read is left out the same way, so
the summary says how many there were, and any such record makes a result that
would adopt the critic `inconclusive-unreadable-records`. The reading states
each arm's incomplete count on every model, and
when the critic arm's share of incomplete runs exceeds the plain arm's by more
than one run's worth on any model, a result that would adopt the critic is
recorded as `inconclusive-incomplete-runs-differ` instead.

`summary.md` carries the rule, the per-model reading that applies it, and the
verdict line.

## The recorded run

[`evals/results-2026-09-25-review/`](../evals/results-2026-09-25-review/summary.md) holds
the run #216 asks for: `claude-opus-5-5` and `claude-sonnet-5`, both arms, every case and trap
(34), twice, 272 runs against `d7d8fc4`, $297.65. No run was incomplete: every critic-arm run
dispatched the critic and no plain-arm run did.

| Model | Arm | Precision | Recall | F1 | P1/P2 findings per run | Arm spread |
|---|---|---|---|---|---|---|
| `claude-opus-5-5` | plain | 28% | 100% | 0.440 | 3.5 | 0.009 |
| `claude-opus-5-5` | critic | 20% | 100% | 0.335 | 5.0 | 0.033 |
| `claude-sonnet-5` | plain | 34% | 99% | 0.510 | 2.9 | 0.012 |
| `claude-sonnet-5` | critic | 31% | 100% | 0.471 | 3.2 | 0.016 |

Higher is better for precision, recall and F1. The adoption rule compares each model's change in
F1 with that model's spread, the mean of its two arms' (Opus 0.021, Sonnet 0.014). With the
critic, F1 falls on both models by more than that, so the verdict is `keep-off` and
`review.groundingCritic` stays off. `summary.md`'s "does not clear the spread" refers to the
improvement the rule asks for.

Read the drop as the effect of turning the setting on, not of the critic's verdicts alone. The
grounding pass can only remove findings, yet the critic arm scores more P1/P2 findings per run.
Counting every priority (P3 findings are recorded in `runs.json` as `ignored_findings` but not
scored), the arms raise about as many findings in total: Sonnet 3.90 per run without the critic
and 3.87 with it, Opus 5.34 and 5.94. What changes is their priority: with the critic fewer are
P3 (Sonnet 1.03 to 0.62, Opus 1.79 to 0.97), so more are scored as P1 or P2. On Sonnet this shift
is the whole rise in scored findings; on Opus it is most of it. Why the priorities move is not
measured here. In one pair of sessions compared by hand (Opus, `four-stream-codec`,
`big_endian_table`, run 1: `0f1239d1-59e0-4f31-8da1-eac110eab043` plain,
`d2b3260a-fd7f-4d14-a7b5-8a23adc52331` critic), the plain session merged the reviewers'
findings by location and the critic session kept them apart to hand them to the critic; one pair
shows that this can happen, not how often.

## How to run

```bash
# check every case offline: each variant must differ from its reference, and
# the changed hunks are recorded into traps.json
plugins/flow/bin/flow-eval-run.sh --mode review --check-cases

# print the plan — per case and trap, the scratch-repo layout and the exact
# command — without calling any model
plugins/flow/bin/flow-eval-run.sh --mode review --dry-run

# score one saved findings block against one trap
python3 plugins/flow/bin/_flow_eval.py score-review \
  --case plugins/flow/evals/interval-algebra --trap point_dropped \
  --findings findings.json

# re-aggregate a results directory
plugins/flow/bin/flow-eval-run.sh --mode review --aggregate-only --out <dir>
```

A full matrix is large: two arms times 34 trap variants times N runs times the
number of models. `--case` and `--runs` narrow it, `--trap <name>` with a single
`--case` narrows it to one variant, and `--max-total-usd` stops it. Resuming works as in `correctness-eval.md`, `--abandon-unfinished` included. The plan's run count is printed by `--dry-run` before anything is spent.

## What the shipped cases can and cannot measure

The issue this eval comes from says the reference-to-variant diff is the seeded
defect. As the variants are stored it is not — it is a whole-file replacement —
which is why the runner materializes them. After materialization the diff is
the defect, and 5% of the module is inside a hunk.

One tell survives for 15 of the 34 variants: they call back into the reference
(`import reference_impl as _ref`), so the module under review says it is part of
an eval and `reference_impl.py` has to be committed beside it. The other 19 get
no such file — a correct copy of the module under review would locate the
defect by diff alone — and the one the 15 do get carries the same stripped text
as the module, not the shipped docstring naming the hidden suite.

`--check-cases --mode review` records which variants delegate, in `traps.json`
and in its report, as `delegates_to_reference`. There is no filter that
excludes them: `--case` selects whole cases, and every case has both kinds, so
a run either includes the delegating variants or discards clean ones with them.
`--trap` selects one variant of one case, which is enough for a pilot but not a
way to run every clean variant in one plan.
Read the flag when reading the results, and treat those 15 runs as the weaker
evidence. Rewriting the variants to stand alone is case content, not harness
work, and has not been done.

## Limitations

- One repository's reviewer agents, one prompt, four cases of small pure-Python
  modules. Nothing here says how the fan-out behaves on a large diff across
  several files.
- The seeded defect is the only defect. A finding that is correct about
  something else the variant does is scored as a false finding, which understates
  precision for a thorough reviewer.
- The line a reviewer cites is matched by basename, so a finding that names the
  right file in another directory would count.
