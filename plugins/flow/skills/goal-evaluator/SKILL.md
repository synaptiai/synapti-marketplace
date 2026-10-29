---
name: goal-evaluator
description: "Evaluate a FlowGoal against its evidence ledger: run every deterministic verification command first, dispatch the goal-evaluator-judge only for fuzzy criteria, then return a structured verdict and write non-terminal lifecycle updates. Use when /flow:goal evaluate runs, when the Stop hook fires in evaluator-loop mode, or when /flow:start Phase 4 or /flow:debug converts AC evidence into a verdict. A lifecycle transition without deterministic evidence is silent premature completion."
allowed-tools: Bash, Read, Edit, Agent
agent: general-purpose
---

# Goal Evaluator

## Contract

Iron law: deterministic checks beat LLM judgment: run every `verification_command` first and never substitute judge output for a runnable command's exit code. Invoked by `/flow:goal evaluate <id>` and `/flow:debug` step 6 (`trigger=command`), and by `hooks/scripts/flow-goal-evaluator.sh` in evaluator-loop mode (`trigger=stop-hook`), with goal id, run id, and trigger. Returns `{verdict, confidence, delta, reason, next_step_hint, criterion_results}` plus, for terminal outcomes, a `proposed_transition`; writes evidence sidecars and non-terminal lifecycle updates, never `last-verdict.json` and never a terminal status. Permitted skips: the judge when no fuzzy criteria remain; the path-boundary check when `constraints.allowed_paths` is unset.

## Inputs

1. **Goal id**: `.flow/goals/<id>.goal.yaml` with status `active` (or resumable `waiting_for_user`, `waiting_for_ci`, `blocked`). Never read through a symlink: when `bin/flow-mkdir.sh --check .flow/goals` refuses, or the goal file is a symlink, there is no goal to evaluate — it belongs to the link's target.
2. **Run id**: for `.flow/runs/<run-id>/evidence/`; defaults to the goal's `scope.run_id`.
3. **Trigger**: `manual | stop-hook | command`.

## Outputs

1. Updated goal: AC `status` (`pending → evidence_collected → pass | fail`), `evidence_ref`, `last_evaluated_at`, `last_result`; `lifecycle.last_evaluation`; non-terminal `lifecycle.status`.
2. `*.evidence.yaml` sidecars via `bin/flow-record-evidence.sh` (the `goal-evidence-ledger` skill).
3. A `goal-evaluation` journal artifact.
4. The structured verdict, returned to the caller.

## Workflow

### Step 1: Load

Read the goal, confirm it matches `schemas/v1/goal.schema.json`, and read existing sidecars for ACs that already carry `evidence_ref`.

### Step 2: Deterministic checks

For each AC with a `verification_command`: run `bash -c "<command>"`, capture stdout/stderr and the exit code, write a `command_result` FlowEvidence with `proves: [<AC.id>]` and `limitations` (criterion-verification-map's "Does NOT promise" field when present), then update the AC entry (`status: evidence_collected`, `evidence_ref`, `last_evaluated_at`, `last_result`).

### Step 3: Deterministic verdict

All `must_pass` ACs exit 0 → `pass`; any `must_pass` AC non-zero → `fail`; any AC without a command → `incomplete` (judge required).

### Step 4: Path boundary

When `constraints.allowed_paths` is set, run `git diff --name-only`; any file outside the globs → write a `path_boundary_check` sidecar (`proves: []`, violating filenames) and set the candidate to `blocked` with reason `path_boundary_violation`.

### Step 5: Judge (conditional)

Dispatch `Agent(goal-evaluator-judge)` only when `evaluator.type == hybrid` and fuzzy criteria remain, or when `evaluator.type == flow_verdict_judge` and the user invoked `/flow:goal evaluate`. The judge gets the same input, the same instructions and the same model as the judge the Stop hook runs in evaluator-loop mode:

- **Input**: the text `bin/_flow_evidence_bundle.py` assembles, the assembler the Stop hook uses: the goal contract, the deterministic check report, the run's evidence sidecars with their raw output, the previous verdict and the turn budget, each in its own `<<<UNTRUSTED_*>>>` fence. Nothing else goes in the prompt: no diff, no journal, no reasoning from this session, and no paths for the judge to open.
- **Instructions**: the body of `agents/goal-evaluator-judge.md`, which the agent definition supplies; the Stop hook passes the same body as its system prompt.
- **Model**: `flow.goals.judge.model`, resolved through the settings cascade with the hook's default (`haiku`) and the hook's allowed values (`haiku`, `sonnet`, `opus`); any other value is replaced by `haiku` with one line on stderr.

Run this block with `GOAL_ID` set to the goal id and `RUN_ID` to the run id (empty for a goal without a run). It runs the deterministic checks the way the Stop hook does, so for a trusted goal the verification commands run again here, after Step 2: the report the judge reads is the one the hook would produce for the same tree.

```bash
# GOAL_JUDGE_INPUT_BEGIN
# Keep the repository out of PYTHONPATH before python3 starts: the interpreter
# imports sitecustomize from each element at startup. An isolated python3 (-I:
# it reads neither PYTHONPATH nor the working directory) keeps only elements
# that are directories outside the repository and not at or above the working
# directory, comparing directories by identity, not by how the path is spelled;
# tests/syspath-guard.test.sh has the reasons. FLOW_USER_PYTHONPATH keeps the
# original for commands run for the user.
[ -n "${FLOW_USER_PYTHONPATH+x}" ] || export FLOW_USER_PYTHONPATH="${PYTHONPATH-}"
_flow_pp=""; if [ -n "${PYTHONPATH-}" ]; then _flow_pp=$(python3 -I -c 'exec("import os, sys\ndef ids(p):\n    out = set()\n    while True:\n        try:\n            st = os.stat(p)\n        except OSError:\n            return out\n        out.add((st.st_dev, st.st_ino))\n        q = os.path.dirname(p)\n        if q == p:\n            return out\n        p = q\ntry:\n    cwd = os.getcwd()\nexcept OSError:\n    sys.exit(0)\ntop = d = cwd\nwhile True:\n    if os.path.lexists(os.path.join(d, \".git\")):\n        top = d\n        break\n    q = os.path.dirname(d)\n    if q == d:\n        break\n    d = q\nst = os.stat(top)\ntop_id = (st.st_dev, st.st_ino)\nup = ids(cwd)\nkeep = []\nfor e in os.environ.get(\"PYTHONPATH\", \"\").split(\":\"):\n    if not e.startswith(\"/\"):\n        continue\n    r = os.path.realpath(e)\n    if \":\" in r or chr(10) in r or not os.path.isdir(r):\n        continue\n    try:\n        st = os.stat(r)\n    except OSError:\n        continue\n    if (st.st_dev, st.st_ino) in up or top_id in ids(r):\n        continue\n    keep.append(r)\nsys.stdout.buffer.write(os.fsencode(\":\".join(keep)))")' 2>/dev/null) || _flow_pp=""; fi
if [ -n "$_flow_pp" ]; then export PYTHONPATH="$_flow_pp"; else unset PYTHONPATH; fi
case "${GOAL_ID:-}" in
  ''|.|..|*/*|*..*) printf '%s\n' "JUDGE_STATE=blocked" "JUDGE_ERROR=GOAL_ID must be a goal id without '/' or '..'"; exit 1 ;;
esac
case "${RUN_ID:-}" in
  .|..|*/*|*..*) printf '%s\n' "JUDGE_STATE=blocked" "JUDGE_ERROR=RUN_ID must be a run id without '/' or '..'"; exit 1 ;;
esac
FLOW_ROOT="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")"
if [ ! -x "$FLOW_ROOT/bin/cascade-resolve.sh" ]; then
  printf '%s\n' "JUDGE_STATE=blocked" "JUDGE_ERROR=flow plugin root not found (cascade-resolve.sh missing) — reinstall or upgrade the flow plugin"
  exit 1
fi
# Never through a symlink: a goal or run reached through a link belongs to its
# target, not to this repository.
GOAL_FILE=".flow/goals/$GOAL_ID.goal.yaml"
if ! "$FLOW_ROOT/bin/flow-mkdir.sh" --check -- .flow/goals >/dev/null 2>&1 || [ -L "$GOAL_FILE" ] || [ ! -f "$GOAL_FILE" ]; then
  printf '%s\n' "JUDGE_STATE=blocked" "JUDGE_ERROR=no goal file to read at .flow/goals/<GOAL_ID>.goal.yaml (missing, or reached through a symlink)"
  exit 1
fi
RUN_DIR=""
if [ -n "${RUN_ID:-}" ]; then
  if ! "$FLOW_ROOT/bin/flow-mkdir.sh" --check -- ".flow/runs/$RUN_ID" >/dev/null 2>&1; then
    printf '%s\n' "JUDGE_STATE=blocked" "JUDGE_ERROR=the run directory is reached through a symlink or cannot be checked"
    exit 1
  fi
  RUN_DIR=".flow/runs/$RUN_ID"
fi
# The model: the key, default and allowed values the Stop hook uses.
JUDGE_MODEL=$("$FLOW_ROOT/bin/cascade-resolve.sh" --default "haiku" '.flow.goals.judge.model // empty' 2>/dev/null)
[ -n "$JUDGE_MODEL" ] || JUDGE_MODEL="haiku"
case "$JUDGE_MODEL" in
  haiku|sonnet|opus) ;;
  *) printf '%s\n' "goal-evaluator: unknown flow.goals.judge.model; using haiku" >&2; JUDGE_MODEL="haiku" ;;
esac
# The report, from the producer the Stop hook runs. No "checked" key, or a
# non-zero exit, means the checks did not run.
REPORT=$(CLAUDE_PLUGIN_ROOT="$FLOW_ROOT" "$FLOW_ROOT/hooks/scripts/flow-run-deterministic-checks.sh" "$GOAL_FILE" 2>/dev/null)
CHECKS_RC=$?
if [ "$CHECKS_RC" -ne 0 ] || ! printf '%s' "$REPORT" | jq -e 'has("checked")' >/dev/null 2>&1; then
  printf '%s\n' "JUDGE_STATE=blocked" "JUDGE_ERROR=the deterministic checks did not run (exit $CHECKS_RC)"
  exit 1
fi
BUNDLE_FILE=$(mktemp -t flow-judge-input.XXXXXX) || { printf '%s\n' "JUDGE_STATE=blocked" "JUDGE_ERROR=mktemp failed"; exit 1; }
if ! PYTHONSAFEPATH=1 python3 "$FLOW_ROOT/bin/_flow_evidence_bundle.py" "$GOAL_FILE" "$REPORT" "$RUN_DIR" > "$BUNDLE_FILE" 2>/dev/null; then
  rm -f "$BUNDLE_FILE"
  printf '%s\n' "JUDGE_STATE=blocked" "JUDGE_ERROR=the evidence bundle could not be assembled (python3 or PyYAML missing, or a goal or sidecar the assembler refused)"
  exit 1
fi
printf '%s\n' "JUDGE_STATE=ready" "JUDGE_MODEL=$JUDGE_MODEL" "JUDGE_AGENT=goal-evaluator-judge"
cat "$BUNDLE_FILE"
rm -f "$BUNDLE_FILE"
# GOAL_JUDGE_INPUT_END
```

On `JUDGE_STATE=blocked`, do not dispatch the judge: report `JUDGE_ERROR` and return `needs_human_review`. On `JUDGE_STATE=ready`, dispatch `Agent(subagent_type: goal-evaluator-judge, model: <JUDGE_MODEL>)` with a prompt that is everything after the `JUDGE_AGENT=` line, verbatim: do not summarise it, add to it or wrap it. The judge returns verdict, confidence, delta, next_step_hint, criterion_results and reason.

### Step 6: Lifecycle update

Map the candidate and judge verdict to a status with the table in `references/goal-lifecycle-transitions.md`.

**Non-terminal transitions** (`active`, `blocked`, `waiting_for_user`, `waiting_for_ci`): set `lifecycle.status`, increment `turns_evaluated`, set `last_evaluation = {result, reason, at}`, and write immediately via `bin/flow-goal-record.sh --update-lifecycle`.

**Terminal transitions** (`achieved`, `failed`, `cancelled`): the skill does NOT write them. Return `proposed_transition: {to, reason, turns_evaluated}` and leave the persisted status non-terminal; the caller is responsible for invoking AskUserQuestion and, on confirmation, calling `bin/flow-goal-record.sh --update-lifecycle`. The Stop-hook evaluator-loop cannot ask: it records the verdict and approves the stop with a hint to run `/flow:goal evaluate <id>`. It writes one terminal status itself, `failed`, on stuck detection and when the turn budget is used up on a turn that would block again (`references/goal-lifecycle-transitions.md`).

### Step 7: Journal

`bin/journal-record.sh --issue {N} --type goal-evaluation --metadata goal_id=<id> --metadata result=<status> --metadata evidence_bundle=<run-dir> --metadata failures=<comma-list or none>`.

### Step 8: Return the verdict (the skill does NOT write `last-verdict.json`)

Return verdict, confidence, delta, reason, and next_step_hint. The caller, `commands/goal.md` (`source: "command"`) or `flow-goal-evaluator.sh` (`source: "evaluator-loop"`), invokes `bin/flow-record-verdict.sh` and treats a helper failure as non-fatal. One owner per write; two writers race and the last one wins.

### Step 9: Stuck detection (stop-hook only)

When `trigger == stop-hook` and the pass-set is unchanged for `flow.goals.failAfterStuckTurns` consecutive turns (default 3), propose `failed` with reason `stuck_no_progress`.

## Rules

- No AC reaches `pass` without an `evidence_ref`.
- No lifecycle write without a `goal-evaluation` artifact.
- Never run the judge when deterministic checks suffice; never skip the path-boundary check when `allowed_paths` is set.

## References

- `plugins/flow/agents/goal-evaluator-judge.md`: the judge; inherits verdict-judge's Independence Protocol.
- `plugins/flow/references/goal-lifecycle-transitions.md`: verdict-to-status table.
- `plugins/flow/bin/flow-record-verdict.sh`: the caller-owned `last-verdict.json` writer.
