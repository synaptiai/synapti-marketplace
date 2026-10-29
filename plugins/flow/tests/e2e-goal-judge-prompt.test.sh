# shellcheck shell=bash
# End-to-end: the goal judge gets the same instructions, the same input and the
# same model whether the Stop hook runs it (evaluator-loop mode, claude --print)
# or the goal-evaluator skill dispatches it (/flow:goal evaluate).
#
# The hook scenarios run the hook Claude Code registers for Stop
# (hooks/scripts/flow-goal-stop.sh), which delegates to flow-goal-evaluator.sh,
# in a scratch repository with stopHookEnforcement=evaluator-loop and a goal
# whose AC2 has no verification command, so the judge runs. The claude CLI is
# tests/lib/mock-claude.sh with FLOW_TEST_CLAUDE_ARGS_DIR set, which keeps the
# --system-prompt value, the --model value and the prompt on stdin, one file
# each. The skill scenarios run the block between GOAL_JUDGE_INPUT_BLOCK_BEGIN
# and GOAL_JUDGE_INPUT_BLOCK_END of skills/goal-evaluator/SKILL.md under zsh
# and bash. One artifact per scenario is written to $FLOW_E2E_ARTIFACT_DIR.
# FLOW_E2E_SCENARIOS=a,b runs only the named scenarios.
#
# Ways it can be wrong, written down before the scenarios:
#   P1 the hook passes the agent file with its YAML frontmatter (name, tools,
#      model), or a fixed string, instead of the file's body
#   P2 a missing, unreadable or empty agent file leaves the judge with an
#      empty system prompt, or stops the judge from running, instead of the
#      built-in prompt with one line on stderr
#   P3 a body that is only frontmatter counts as present, so the judge gets
#      an empty prompt
#   P4 the skill's block does not run the assembler, or prints its output
#      without the <<<UNTRUSTED_*>>> fences
#   P5 the skill's block and the hook give the judge different input for the
#      same goal and evidence
#   P6 the skill reads another settings key, another default or another
#      allowlist for the model than the hook, so the two judges run on
#      different models
#   P7 the skill's block runs with no plugin root found and prints a model and
#      no bundle, instead of saying it is blocked

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

STOP_HOOK="hooks/scripts/flow-goal-stop.sh"
SKILL="skills/goal-evaluator/SKILL.md"
AGENT="agents/goal-evaluator-judge.md"
FIRST='{"session_id":"e2e-session","stop_hook_active":false}'
RUN_REL=".flow/runs/run-e2e"
JUDGE_REPLY='{"structured_output":{"verdict":"not_achieved","confidence":0.7,"delta":"made_progress","next_step_hint":"judge hint","reason":"judge says AC2 lacks proof"}}'
CRIT='[{"id":"AC1","text":"The search runs.","cmd":"true"},{"id":"AC2","text":"The search results read well."}]'
# The prompt the hook carries for when the agent file cannot be used. Copied
# from the hook by hand: the scenario must notice if the fallback changes.
BUILTIN_PREFIX="You are flow goal-evaluator-judge. Apply the Independence Protocol: judge based ONLY on the goal contract"

# _body <agent file> — the file's body as the agent definition defines it:
# everything after the closing --- of a frontmatter that opens on line 1,
# without the blank lines at either end. Computed here in Python, not with
# the hook's code, so the expectation does not come from the code under test.
_body() {
  python3 - "$1" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
if lines and lines[0].rstrip() == "---":
    end = next(i for i in range(1, len(lines)) if lines[i].rstrip() == "---")
    lines = lines[end + 1:]
sys.stdout.write("\n".join(lines).strip("\n"))
PY
}

# _setup <scenario> <purpose> [goals settings json] — scratch repo with
# evaluator-loop on, the run directory present, and the claude stub replaced
# by mock-claude.sh, which records what it was given.
_setup() {
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo feature/e2e
  mkdir -p "$E2E_REPO/.claude" "$E2E_REPO/$RUN_REL" "$E2E_DIR/args"
  local extra="${3:-}"
  [ -n "$extra" ] || extra='{}'
  jq -nc --argjson extra "$extra" '{flow:{goals:({stopHookEnforcement:"evaluator-loop"} + $extra)}}' \
    > "$E2E_REPO/.claude/settings.flow.json"
  cp "$REPO_ROOT/plugins/flow/tests/lib/mock-claude.sh" "$E2E_BIN/claude" && chmod +x "$E2E_BIN/claude"
  printf '%s\n' "$JUDGE_REPLY" > "$E2E_DIR/judge-reply.json"
  printf 'claude: tests/lib/mock-claude.sh, replying %s\n' "$JUDGE_REPLY" | _e2e_art
}

# _goal — goal g-judge on this branch with run run-e2e and the criteria in
# CRIT, created through flow-goal-record.sh --create so it is trusted.
_goal() {
  local src="$E2E_DIR/goal.src.yaml"
  python3 - "$REPO_ROOT/plugins/flow/tests/fixtures/goal/valid.yaml" "$src" "$CRIT" <<'PY' ||
import json, sys, yaml
fixture, dst, crit = sys.argv[1:4]
with open(fixture, encoding="utf-8") as f:
    g = yaml.safe_load(f)
g["metadata"]["id"] = "g-judge"
g["scope"]["branch"] = "feature/e2e"
g["scope"]["run_id"] = "run-e2e"
acs = []
for c in json.loads(crit):
    ac = {"id": c["id"], "text": c["text"], "must_pass": True, "status": "pending",
          "evidence_ref": None, "last_evaluated_at": None, "last_result": None}
    if c.get("cmd"):
        ac["verification_command"] = c["cmd"]
    acs.append(ac)
g["objective"]["acceptance_criteria"] = acs
with open(dst, "w", encoding="utf-8") as f:
    yaml.safe_dump(g, f, sort_keys=False)
PY
  { _flow_assert_fail "$E2E_NAME: could not write the goal source"; return 0; }
  if ! (_e2e_git_env; cd "$E2E_REPO" && CLAUDE_PLUGIN_ROOT="$E2E_ACTIVE_PLUGIN" \
        "$E2E_ACTIVE_PLUGIN/bin/flow-goal-record.sh" --create --goal-file "$src" >/dev/null 2>"$E2E_DIR/create.err"); then
    _flow_assert_fail "$E2E_NAME: flow-goal-record.sh --create failed: $(cat "$E2E_DIR/create.err")"
  fi
  printf 'goal criteria: %s\n' "$CRIT" | _e2e_art
}

# _evidence — a passing command_result sidecar for AC2, recorded with
# flow-record-evidence.sh, with a raw output naming the criterion.
_evidence() {
  local f="$E2E_DIR/ev-ac2.evidence.yaml"
  cat > "$f" <<YAML
apiVersion: flow.synapti.ai/v1
kind: FlowEvidence
metadata:
  id: ev-ac2
  goal: g-judge
  run_id: run-e2e
  created_at: '2026-10-01T10:00:00Z'
evidence:
  type: command_result
  command: 'bash tests/check-AC2.sh'
  exit_code: 0
  proves:
    - AC2
  limitations:
    - 'checks only the default locale'
YAML
  printf 'ok: AC2 holds in every case checked\n' > "$E2E_DIR/ev-ac2.out"
  if ! (_e2e_git_env; cd "$E2E_REPO" && CLAUDE_PLUGIN_ROOT="$E2E_ACTIVE_PLUGIN" \
        "$E2E_ACTIVE_PLUGIN/bin/flow-record-evidence.sh" --run-id run-e2e --evidence-file "$f" \
        --raw-output "$E2E_DIR/ev-ac2.out" >/dev/null 2>"$E2E_DIR/evidence.err"); then
    _flow_assert_fail "$E2E_NAME: flow-record-evidence.sh failed: $(cat "$E2E_DIR/evidence.err")"
  fi
  printf 'evidence ev-ac2: command_result proves AC2, exit 0\n' | _e2e_art
}

# _hook — one Stop turn, with the claude stub recording into args/.
_hook() {
  rm -f "$E2E_DIR/args/"*
  e2e_run_hook FLOW_TEST_CLAUDE_RESPONSE="$E2E_DIR/judge-reply.json" FLOW_TEST_CLAUDE_ARGS_DIR="$E2E_DIR/args" \
    "$STOP_HOOK" "$FIRST"
}
_got() { if [ -f "$E2E_DIR/args/$1" ]; then cat "$E2E_DIR/args/$1"; else printf '(not called)'; fi; }

# _edges_judged — for a scenario that runs the hook: every gh call had a
# fixture, and the judge was called. The judge here is mock-claude.sh, which
# does not write the harness's claude-calls.log, so e2e_expect_clean_edges
# would record "the claude CLI was not called", which is untrue.
_edges_judged() {
  if [ -s "$E2E_GH/unhandled.log" ]; then
    _e2e_result fail "every gh call had a fixture ($(tr '\n' ';' < "$E2E_GH/unhandled.log"))"
  else
    _e2e_result pass "every gh call had a fixture"
  fi
  if [ -f "$E2E_DIR/args/model.txt" ]; then _e2e_result pass "the judge was called"
  else _e2e_result fail "the judge was called"; fi
}

# _skill — the skill's judge-input block for goal g-judge and run run-e2e.
_skill() { e2e_run_block GOAL_ID=g-judge RUN_ID=run-e2e "$SKILL" GOAL_JUDGE_INPUT; }

# ------------------------------------------------------------ the hook

if _want hook-agent-body; then
  _flow_test_begin "Stop hook: the judge's system prompt is the agent file's body, without its frontmatter (P1)"
  _setup hook-agent-body "AC1 passes its command; AC2 has none, so the judge runs; the agent file is the shipped one"
  _goal
  _evidence
  _hook
  e2e_expect_line '{"decision":"block","reason":"FLOW_GOAL_CONTINUATION (not_achieved): judge says AC2 lacks proof. Next: judge hint"}'
  e2e_expect_equal "$(_body "$E2E_ACTIVE_PLUGIN/$AGENT" | _e2e_sha256_stdin)" "$(_got system-prompt.txt | _e2e_sha256_stdin)" "sha256 of the system prompt against the agent body"
  sp=$(_got system-prompt.txt)
  case "$sp" in *"name: goal-evaluator-judge"*|*"tools: []"*|*"model: inherit"*) e2e_expect_equal "no frontmatter" "frontmatter present" "frontmatter in the system prompt" ;;
    *) e2e_expect_equal ok ok "no frontmatter line in the system prompt" ;; esac
  case "$sp" in *"## Independence Protocol"*) e2e_expect_equal ok ok "the system prompt has the Independence Protocol" ;;
    *) e2e_expect_equal "has it" "lacks it" "the Independence Protocol in the system prompt" ;; esac
  e2e_expect_equal haiku "$(_got model.txt)" "the judge's model"
  e2e_expect_equal "" "$E2E_ERR" "stderr"
  _edges_judged
fi

# _fallback <scenario> <purpose> <how to break the agent file>
_fallback() {
  _setup "$1" "$2"
  e2e_plugin_copy "$AGENT" "$3"
  case "$4" in
    absent) rm -f "$E2E_ACTIVE_PLUGIN/$AGENT" ;;
    unreadable) chmod 000 "$E2E_ACTIVE_PLUGIN/$AGENT" ;;
  esac
  _goal
  _evidence
  _hook
  e2e_expect_line '{"decision":"block","reason":"FLOW_GOAL_CONTINUATION (not_achieved): judge says AC2 lacks proof. Next: judge hint"}'
  case "$(_got system-prompt.txt)" in
    "$BUILTIN_PREFIX"*) e2e_expect_equal ok ok "the system prompt is the built-in one" ;;
    *) e2e_expect_equal "the built-in prompt" "$(_got system-prompt.txt | head -c 120)" "the system prompt" ;;
  esac
  e2e_expect_err "flow-goal-evaluator: no judge instructions in $E2E_ACTIVE_PLUGIN/$AGENT (missing, unreadable or empty); using the built-in judge prompt"
  e2e_expect_equal 1 "$(printf '%s\n' "$E2E_ERR" | grep -c .)" "stderr lines"
  e2e_expect_equal haiku "$(_got model.txt)" "the judge's model"
  [ "$4" = unreadable ] && chmod 644 "$E2E_ACTIVE_PLUGIN/$AGENT"
  _edges_judged
}

if _want hook-agent-absent; then
  _flow_test_begin "Stop hook: with no agent file, the judge runs on the built-in prompt and stderr says so (P2)"
  _fallback hook-agent-absent "the plugin copy has no agents/goal-evaluator-judge.md" "" absent
fi

if _want hook-agent-empty; then
  _flow_test_begin "Stop hook: an empty agent file gives the built-in prompt (P2)"
  _fallback hook-agent-empty "agents/goal-evaluator-judge.md is a blank line" "" keep
fi

if _want hook-agent-frontmatter-only; then
  _flow_test_begin "Stop hook: an agent file that is only frontmatter gives the built-in prompt (P3)"
  _fallback hook-agent-frontmatter-only "agents/goal-evaluator-judge.md holds a frontmatter and nothing after it" "$(printf -- '---\nname: goal-evaluator-judge\ntools: []\n---\n\n')" keep
fi

if _want hook-agent-unreadable && [ "$(id -u)" != 0 ]; then
  _flow_test_begin "Stop hook: an unreadable agent file gives the built-in prompt (P2)"
  _fallback hook-agent-unreadable "agents/goal-evaluator-judge.md has mode 000" "body that cannot be read" unreadable
fi

# ------------------------------------------------------------ the skill

if _want skill-bundle; then
  _flow_test_begin "goal-evaluator skill: the judge-input block runs the assembler and prints the fenced input (P4)"
  _setup skill-bundle "AC1 passes its command; AC2 has a passing command_result sidecar; no model setting"
  _goal
  _evidence
  _skill
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "JUDGE_STATE=ready"
  e2e_expect_line "JUDGE_MODEL=haiku"
  e2e_expect_line "JUDGE_AGENT=goal-evaluator-judge"
  e2e_expect_line "<<<UNTRUSTED_GOAL_CONTRACT>>>"
  e2e_expect_line "<<<UNTRUSTED_DETERMINISTIC_REPORT>>>"
  e2e_expect_line "<<<UNTRUSTED_EVIDENCE_LEDGER>>>"
  e2e_expect_line "<<<UNTRUSTED_BUDGET>>>"
  e2e_expect_out "ok: AC2 holds in every case checked"
  e2e_expect_out "The search results read well."
  e2e_expect_equal "" "$E2E_ERR" "stderr"
  e2e_expect_clean_edges
fi

if _want skill-same-input; then
  _flow_test_begin "goal-evaluator skill and Stop hook: the same goal and evidence give the judge the same input and model (P5, P6)"
  _setup skill-same-input "the skill's block runs first, then one Stop turn, on the same goal and evidence"
  _goal
  _evidence
  _skill
  # The bundle is everything after the three header lines.
  printf '%s\n' "$E2E_OUT" | sed '1,3d' > "$E2E_DIR/skill-bundle.txt"
  skill_model=$(printf '%s\n' "$E2E_OUT" | sed -n 's/^JUDGE_MODEL=//p')
  _hook
  e2e_expect_equal "$(_e2e_sha256 "$E2E_DIR/args/stdin.txt" 2>/dev/null)" "$(_e2e_sha256 "$E2E_DIR/skill-bundle.txt")" "sha256 of the skill's bundle against the hook's judge prompt"
  e2e_expect_equal "$(_got model.txt)" "$skill_model" "the skill's model against the hook's"
  _edges_judged
fi

# _models <scenario> <judge.model value> <expected model> <stderr expected: yes|no>
_models() {
  _setup "$1" "flow.goals.judge.model is $2 in the repository settings; the skill's block runs, then one Stop turn" "{\"judge\":{\"model\":$2}}"
  _goal
  _evidence
  _skill
  e2e_expect_line "JUDGE_MODEL=$3"
  if [ "$4" = yes ]; then e2e_expect_err "unknown flow.goals.judge.model; using haiku"
  else e2e_expect_equal "" "$E2E_ERR" "skill stderr"; fi
  _hook
  e2e_expect_equal "$3" "$(_got model.txt)" "the hook's model"
  _edges_judged
}

if _want model-sonnet; then
  _flow_test_begin "goal-evaluator skill and Stop hook: judge.model sonnet reaches both judges (P6)"
  _models model-sonnet '"sonnet"' sonnet no
fi

if _want model-unknown; then
  _flow_test_begin "goal-evaluator skill and Stop hook: an unknown judge.model falls back to haiku in both (P6)"
  _models model-unknown '"gpt-4o"' haiku yes
fi

if _want skill-no-root; then
  _flow_test_begin "goal-evaluator skill: no plugin root found means blocked, with no model and no bundle (P7)"
  _setup skill-no-root "CLAUDE_PLUGIN_ROOT names a directory with no flow in it, the repository has no plugins/flow and HOME has no install"
  _goal
  e2e_run_block CLAUDE_PLUGIN_ROOT="$E2E_DIR/nowhere" GOAL_ID=g-judge RUN_ID=run-e2e "$SKILL" GOAL_JUDGE_INPUT
  e2e_expect_line "JUDGE_STATE=blocked"
  # The reason names the missing root; a later check failing for its own
  # reason would also say blocked.
  e2e_expect_line "JUDGE_ERROR=flow plugin root not found (cascade-resolve.sh missing) — reinstall or upgrade the flow plugin"
  e2e_expect_no_line "JUDGE_MODEL=haiku"
  e2e_expect_no_out "<<<UNTRUSTED_GOAL_CONTRACT>>>"
  e2e_expect_clean_edges
fi

if _want skill-bad-id; then
  _flow_test_begin "goal-evaluator skill: a goal id with a path in it is refused"
  _setup skill-bad-id "GOAL_ID is ../g-judge, and a goal file sits at .flow/g-judge.goal.yaml, where that id leads"
  _goal
  # Without the check, .flow/goals/../g-judge.goal.yaml is a readable goal.
  cp "$E2E_REPO/.flow/goals/g-judge.goal.yaml" "$E2E_REPO/.flow/g-judge.goal.yaml"
  e2e_run_block GOAL_ID=../g-judge RUN_ID=run-e2e "$SKILL" GOAL_JUDGE_INPUT
  e2e_expect_line "JUDGE_STATE=blocked"
  e2e_expect_line "JUDGE_ERROR=GOAL_ID must be a goal id without '/' or '..'"
  e2e_expect_no_out "<<<UNTRUSTED_GOAL_CONTRACT>>>"
  e2e_expect_clean_edges
fi
