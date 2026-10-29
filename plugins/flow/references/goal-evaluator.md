# Goal Evaluator

Detail for `skills/goal-evaluator/SKILL.md`.

## Outputs

1. Updated goal: AC `status` (`pending → evidence_collected → pass | fail`), `evidence_ref`, `last_evaluated_at`, `last_result`; `lifecycle.last_evaluation`; non-terminal `lifecycle.status`.
2. `*.evidence.yaml` sidecars via `bin/flow-record-evidence.sh` (the `goal-evidence-ledger` skill).
3. A `goal-evaluation` journal artifact.
4. The structured verdict, returned to the caller.

## Callers

The Stop hook in evaluator-loop mode does not run the skill: `hooks/scripts/flow-goal-evaluator.sh` runs the same deterministic checks and the same judge itself, records the verdict, and counts stuck turns. The skill's verdict is written to `last-verdict.json` by its caller with `bin/flow-record-verdict.sh`: `commands/goal.md` (`source: "command"`) or `flow-goal-evaluator.sh` (`source: "evaluator-loop"`).

## The goal judge

What the goal judge is given, in Step 5 of `skills/goal-evaluator/SKILL.md` (`/flow:goal evaluate`) and in the Stop hook in evaluator-loop mode (`hooks/scripts/flow-goal-evaluator.sh`). Both run it through `bin/flow-judge.sh --judge goal`, the claude CLI with every tool disallowed, so both give it the same:

- **Input** (stdin): the text `bin/_flow_evidence_bundle.py` assembles: the goal contract, the deterministic check report, the run's evidence sidecars with their raw output, the previous verdict and the turn budget, each in its own `<<<UNTRUSTED_*>>>` fence. Nothing else: no diff, no journal, no reasoning from this session, and no paths for the judge to open.
- **Instructions** (`--system-prompt`): the body of `agents/goal-evaluator-judge.md`, without its frontmatter.
- **Model** (`--model`): `flow.goals.judge.model`, default `haiku`; any value other than `haiku`, `sonnet` or `opus` is replaced by `haiku` with one line on stderr.
- **Limits**: `--disallowedTools '*'`, the verdict schema as `--json-schema`, `flow.goals.judge.timeoutSeconds` (default 60), and `CLAUDE_HOOK_GOAL_JUDGE_MODE=true` so flow's hooks do nothing inside the judge's session.

## The skill's run

`bin/flow-goal-judge-run.sh <goal-id> [<run-id>]` runs the deterministic checks the way the Stop hook does (`hooks/scripts/flow-run-deterministic-checks.sh`), so for a trusted goal the verification commands run again, after the skill's Step 2: the report the judge reads is the one the hook would produce for the same tree. For a goal that is not trusted, with `flow.goals.executeVerificationCommands` off, the report lists its commands under `not_executed` even though Step 2 ran them; the judge reads the exit codes from the `command_result` sidecars Step 2 wrote, which are in the evidence ledger.

It prints `JUDGE_STATE=done` and `JUDGE_VERDICT=<one line of JSON>`, or `JUDGE_STATE=blocked` or `unavailable` and `JUDGE_ERROR=<why>`:

| State | When |
|---|---|
| `blocked` | the goal id or run id holds `/` or `..`; no plugin root; the goal file is missing or reached through a symlink; the run directory is reached through a symlink; the deterministic checks did not run; the evidence bundle could not be assembled |
| `unavailable` | the judge ran past its time limit (exit 124), the CLI exited non-zero, or the reply has no verdict in the schema |
| `done` | the judge replied with `achieved`, `not_achieved`, `blocked` or `needs_human_review` |

`JUDGE_VERDICT` carries verdict, confidence, delta, next_step_hint, reason, and, when the judge gave them, blocker_type and criterion_results.

## Related

- `plugins/flow/agents/goal-evaluator-judge.md`: the judge; inherits verdict-judge's Independence Protocol.
- `plugins/flow/references/goal-lifecycle-transitions.md`: verdict-to-status table.
- `plugins/flow/bin/flow-record-verdict.sh`: the caller-owned `last-verdict.json` writer.
