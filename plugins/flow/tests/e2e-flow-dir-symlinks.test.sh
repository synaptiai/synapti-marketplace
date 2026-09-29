# shellcheck shell=bash
# End-to-end: flow never creates or writes a file through a symlinked
# directory under .flow/ or the decision journal.
#
# A repository can commit .flow, .flow/runs, .flow/goals or .decisions as a
# symlink to a directory outside the checkout. Each writer refused a symlink at
# the file it writes, but followed one at a directory above it, so the run
# state, goals, evidence and journal entries landed in the link's target. Each
# scenario plants such a link to $E2E_DIR/outside in a scratch repository,
# runs the writer the way flow reaches it (the shipped command block or hook
# when one runs as committed; otherwise the helper, with the arguments the
# command or skill passes it), and checks that the target is left exactly as
# it was, that the refusal is on stderr, and the exit status the writer's
# header gives for a refused symlink. The artifact for each scenario is
# written to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the scenarios:
#   L1 flow-record-verdict.sh (/flow:goal evaluate) creates the run directory
#      and writes last-verdict.json and its lock in the target of a symlinked
#      .flow or .flow/runs: it refused only a run directory that is itself a
#      symlink
#   L2 flow-record-activity.sh (run-state-management, at every phase boundary)
#      creates activities/ and evidence/, the activity, its lock and
#      events.jsonl there
#   L3 flow-record-evidence.sh (goal-evidence-ledger) creates evidence/ and the
#      sidecar there
#   L4 flow-goal-record.sh --create (goal-contract-capture) creates .flow/goals
#      and the goal in the target of a symlinked .flow or .flow/goals
#   L5 flow-goal-record.sh --update-lifecycle, which the Stop hook runs on
#      every turn it blocks, rewrites a goal reached through a symlinked .flow
#      and leaves its lock in the link's target
#   L5b the same update run by /flow:goal's lifecycle block exits 1 with a
#      traceback instead of the 2 its header gives for a refused symlink
#   L6 journal-record.sh (the /flow:start Stranger Test block) writes the
#      journal manifest and its lock through a symlinked .decisions, or
#      creates a configured journal.dir under a symlinked parent directory
#   L7 journal-append.sh (the /flow:brainstorm decision block) does the same
#   L8 the SessionEnd hook appends a session_end event, and creates its lock,
#      in every active run it finds through a symlinked .flow, .flow/runs or
#      run directory, and says nothing about it
#   L9 the /flow:setup strip block rewrites journals under a configured
#      journal.dir whose parent directory is a symlink: it refused only a
#      journal directory that is itself one
#   L10 the /flow:trigger and /flow:watch pre-flights create .flow/triggers in
#      the target of a symlinked .flow, where the trigger is then written
#   L11 the /flow:goal pre-flight creates .flow/goals in the target of a
#      symlinked .flow
#   L12 the /flow:start journal block accepts a symlinked .decisions, and the
#      journal header is then written into its target
#   L13 run-state-management creates a run's directory through a symlinked
#      .flow or .flow/runs before it writes run.yaml there
#   L14 a path whose name climbs out of a symlinked directory with `..` is
#      accepted because its components, read without the link, are real
#   L15 the check refuses what it should not: a writer in an ordinary
#      repository, reached through macOS's /var -> /private/var, stops
#      writing

source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || return 0

# FLOW_E2E_SCENARIOS=a,b runs only the scenarios whose artifacts are named a
# and b.
_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

RID="2026-05-20T143000Z-issue-42"
FIXTURES="$REPO_ROOT/plugins/flow/tests/fixtures"
STOP_HOOK="hooks/scripts/flow-goal-stop.sh"
SESSION_END_HOOK="hooks/scripts/session-end-state.sh"

# _plant <path under the repository> — replace <path> with a symlink to
# $E2E_DIR/outside. What the path held moves there first, so a writer that
# follows the link finds what it would have found in the repository. BEFORE is
# what the target holds once the link is in place.
_plant() {
  local p="$E2E_REPO/$1"
  if [ -e "$p" ]; then
    mv "$p" "$E2E_DIR/outside"
  else
    mkdir -p "$E2E_DIR/outside" "$(dirname "$p")"
  fi || { _flow_assert_fail "$E2E_NAME: could not move $1 outside the repository"; return 0; }
  ln -s "$E2E_DIR/outside" "$p" || _flow_assert_fail "$E2E_NAME: could not plant the $1 symlink"
  printf 'planted: %s -> <scratch>/%s/outside\n' "$1" "$E2E_NAME" >> "$E2E_ARTIFACT"
  BEFORE=$(_outside_state)
}

# _outside_state — every entry under the link's target: a directory by name,
# a file by name and sha256. Equal before and after means nothing was created,
# removed or changed there.
_outside_state() {
  (
    cd "$E2E_DIR/outside" 2>/dev/null || exit 0
    find . -mindepth 1 | LC_ALL=C sort | while IFS= read -r p; do
      if [ -d "$p" ] && [ ! -L "$p" ]; then printf '%s/\n' "$p"
      else printf '%s %s\n' "$p" "$(_e2e_sha256 "$p")"; fi
    done
  )
}

# _expect_untouched — the link's target holds what it held before the run.
_expect_untouched() {
  e2e_expect_equal "$BEFORE" "$(_outside_state)" "what the symlink's target holds"
}

# _expect_refused <exit status> <text> — the writer refused: its exit status,
# the refusal on stderr, and nothing written through the link.
_expect_refused() {
  e2e_expect_equal "$1" "$E2E_RC" "the exit status"
  e2e_expect_err "$2"
  _expect_untouched
}

# _expect_err_lacks <text> — stderr does not contain text.
_expect_err_lacks() {
  case "$E2E_ERR" in
    *"$1"*) _e2e_result fail "stderr lacks: $1" ;;
    *) _e2e_result pass "stderr lacks: $1" ;;
  esac
}

# _run_bin <file under the plugin> [arguments] — run a helper in the scratch
# repository as a command block or skill runs it. Sets E2E_OUT, E2E_ERR,
# E2E_RC. Arguments are paths inside the repository, so the artifact names no
# scratch directory.
_run_bin() {
  local rel="$1"; shift
  {
    printf 'code: %s\n' "$rel"
    printf 'code sha256: %s\n' "$(_e2e_sha256 "$E2E_ACTIVE_PLUGIN/$rel")"
    printf 'arguments: %s\n' "$*"
  } >> "$E2E_ARTIFACT"
  _e2e_exec "$E2E_ACTIVE_PLUGIN/$rel" "$@"
  printf -- '--- expectations\n' >> "$E2E_ARTIFACT"
}

# _run_with_env <NAME=value ...> -- <e2e_run_fence arguments> — run a fence
# with the variables an earlier step of the command set. They are exported
# for the fence's shell only, and named in the artifact.
_run_with_env() {
  local assignments=() a
  while [ "$1" != "--" ]; do assignments+=("$1"); shift; done
  shift
  printf 'environment: %s\n' "${assignments[*]}" >> "$E2E_ARTIFACT"
  for a in "${assignments[@]}"; do export "${a?}"; done
  e2e_run_fence "$@"
  for a in "${assignments[@]}"; do unset "${a%%=*}"; done
}

# _run_yaml — a FlowRun with state.status active, at .flow/runs/$RID.
_run_yaml() {
  mkdir -p "$E2E_REPO/.flow/runs/$RID"
  cp "$FIXTURES/run/valid.yaml" "$E2E_REPO/.flow/runs/$RID/run.yaml"
}

# _verdict_file / _activity_file / _evidence_file — the inputs the command or
# skill composes, written into the repository and passed by relative path.
_verdict_file() {
  printf '%s\n' '{"verdict":"not_achieved","confidence":0.4,"delta":"unchanged","reason":"AC1 still fails","source":"command"}' \
    > "$E2E_REPO/verdict.json"
}
_activity_file() { cp "$FIXTURES/activity/valid.yaml" "$E2E_REPO/activity.yaml"; }
_evidence_file() { cp "$FIXTURES/evidence/valid.yaml" "$E2E_REPO/evidence.yaml"; }

# _goal_source <id> <branch> — a goal whose must_pass criterion always fails.
_goal_source() {
  python3 - "$FIXTURES/goal/valid.yaml" "$E2E_REPO/goal-source.yaml" "$1" "$2" <<'PY' ||
import sys, yaml
src, dst, gid, branch = sys.argv[1:5]
with open(src, encoding="utf-8") as f:
    g = yaml.safe_load(f)
g["metadata"]["id"] = gid
g["scope"]["branch"] = branch
g["objective"]["acceptance_criteria"][0]["verification_command"] = "false"
with open(dst, "w", encoding="utf-8") as f:
    yaml.safe_dump(g, f, sort_keys=False)
PY
  _flow_assert_fail "$E2E_NAME: could not write the goal source"
}

# _create_goal <id> <branch> — the goal, recorded in the repository through
# the shipped create path, so its trust record is real.
_create_goal() {
  _goal_source "$1" "$2"
  if ! (_e2e_git_env; cd "$E2E_REPO" && CLAUDE_PLUGIN_ROOT="$E2E_ACTIVE_PLUGIN" \
        "$E2E_ACTIVE_PLUGIN/bin/flow-goal-record.sh" --create --goal-file goal-source.yaml >/dev/null 2>"$E2E_DIR/create.err"); then
    _flow_assert_fail "$E2E_NAME: flow-goal-record.sh --create failed: $(cat "$E2E_DIR/create.err")"
  fi
}

# _settings <json> — the repository's .claude/settings.flow.json.
_settings() {
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' "$1" > "$E2E_REPO/.claude/settings.flow.json"
}

# --- flow-record-verdict.sh (L1) --------------------------------------------
# The Stop hook never reaches this helper with a symlinked run directory: it
# refuses the run directory itself first. /flow:goal evaluate is the caller
# that reaches it; its block carries the verdict as placeholders the model
# fills, so the helper runs here with the arguments that block passes.

if _want verdict-flow-link; then
  _flow_test_begin "flow-record-verdict.sh: a symlinked .flow gets no run directory or verdict (L1)"
  e2e_new verdict-flow-link
  e2e_describe ".flow is a symlink to an empty directory outside the repository; the verdict is recorded as /flow:goal evaluate records it"
  e2e_repo feature/issue-42-e2e
  _verdict_file
  _plant .flow
  _run_bin bin/flow-record-verdict.sh --run-id "$RID" --verdict-file verdict.json
  _expect_refused 2 "refusing — .flow is a symlink"
fi

if _want verdict-runs-link; then
  _flow_test_begin "flow-record-verdict.sh: a symlinked .flow/runs gets no run directory or verdict (L1)"
  e2e_new verdict-runs-link
  e2e_describe ".flow/runs is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _verdict_file
  _plant .flow/runs
  _run_bin bin/flow-record-verdict.sh --run-id "$RID" --verdict-file verdict.json
  _expect_refused 2 "refusing — .flow/runs is a symlink"
fi

if _want verdict-real; then
  _flow_test_begin "flow-record-verdict.sh: an ordinary repository still gets its verdict (L15)"
  e2e_new verdict-real
  e2e_describe "no symlink under the repository; the scratch repository is reached through its logical path, which on macOS is itself under a symlink (/var)"
  e2e_repo feature/issue-42-e2e
  _verdict_file
  _run_bin bin/flow-record-verdict.sh --run-id "$RID" --verdict-file verdict.json
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_file_has ".flow/runs/$RID/last-verdict.json" '"verdict": "not_achieved"'
fi

# --- flow-record-activity.sh (L2) -------------------------------------------

if _want activity-flow-link; then
  _flow_test_begin "flow-record-activity.sh: a symlinked .flow gets no activity (L2)"
  e2e_new activity-flow-link
  e2e_describe ".flow is a symlink to an empty directory outside the repository; the activity is recorded as run-state-management records one"
  e2e_repo feature/issue-42-e2e
  _activity_file
  _plant .flow
  _run_bin bin/flow-record-activity.sh --run-id "$RID" --activity-file activity.yaml
  _expect_refused 2 "refusing — .flow is a symlink"
fi

if _want activity-runs-link; then
  _flow_test_begin "flow-record-activity.sh: a symlinked .flow/runs gets no activity (L2)"
  e2e_new activity-runs-link
  e2e_describe ".flow/runs is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _activity_file
  _plant .flow/runs
  _run_bin bin/flow-record-activity.sh --run-id "$RID" --activity-file activity.yaml
  _expect_refused 2 "refusing — .flow/runs is a symlink"
fi

# --- flow-record-evidence.sh (L3) -------------------------------------------

if _want evidence-flow-link; then
  _flow_test_begin "flow-record-evidence.sh: a symlinked .flow gets no evidence (L3)"
  e2e_new evidence-flow-link
  e2e_describe ".flow is a symlink to an empty directory outside the repository; the evidence is recorded as goal-evidence-ledger records it"
  e2e_repo feature/issue-42-e2e
  _evidence_file
  _plant .flow
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml
  _expect_refused 2 "refusing — .flow is a symlink"
fi

if _want evidence-runs-link; then
  _flow_test_begin "flow-record-evidence.sh: a symlinked .flow/runs gets no evidence (L3)"
  e2e_new evidence-runs-link
  e2e_describe ".flow/runs is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _evidence_file
  _plant .flow/runs
  _run_bin bin/flow-record-evidence.sh --run-id "$RID" --evidence-file evidence.yaml
  _expect_refused 2 "refusing — .flow/runs is a symlink"
fi

# --- flow-goal-record.sh (L4, L5) -------------------------------------------

if _want goal-create-flow-link; then
  _flow_test_begin "flow-goal-record.sh --create: a symlinked .flow gets no goal (L4)"
  e2e_new goal-create-flow-link
  e2e_describe ".flow is a symlink to an empty directory outside the repository; the goal is created as goal-contract-capture creates it"
  e2e_repo feature/issue-42-e2e
  _goal_source g-link feature/issue-42-e2e
  _plant .flow
  _run_bin bin/flow-goal-record.sh --create --goal-file goal-source.yaml
  _expect_refused 2 "refusing — .flow is a symlink"
fi

if _want goal-create-goals-link; then
  _flow_test_begin "flow-goal-record.sh --create: a symlinked .flow/goals gets no goal (L4)"
  e2e_new goal-create-goals-link
  e2e_describe ".flow/goals is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _goal_source g-link feature/issue-42-e2e
  _plant .flow/goals
  _run_bin bin/flow-goal-record.sh --create --goal-file goal-source.yaml
  _expect_refused 2 "refusing — .flow/goals is a symlink"
fi

if _want goal-lifecycle-flow-link; then
  _flow_test_begin "Stop hook: a goal reached through a symlinked .flow is not rewritten there (L5)"
  e2e_new goal-lifecycle-flow-link
  e2e_describe "evaluator-loop; an active goal whose check fails is created, then .flow is moved outside the repository and replaced by a symlink to it; one stop"
  e2e_repo feature/issue-42-e2e
  _settings '{"flow":{"goals":{"stopHookEnforcement":"evaluator-loop"}}}'
  _create_goal g-link feature/issue-42-e2e
  _plant .flow
  e2e_run_hook "$STOP_HOOK" '{"session_id":"e2e-session","stop_hook_active":false}'
  e2e_expect_out '"decision":"block"'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "refusing — .flow is a symlink"
  _expect_untouched
  e2e_expect_clean_edges
fi

if _want goal-update-flow-link; then
  _flow_test_begin "flow-goal-record.sh --update-lifecycle: a goal reached through a symlinked .flow is refused with exit 2 (L5, L5b)"
  e2e_new goal-update-flow-link
  e2e_describe "an active goal is created, then .flow is moved outside the repository and replaced by a symlink to it; the lifecycle is updated with the arguments /flow:goal's lifecycle block passes"
  e2e_repo feature/issue-42-e2e
  _create_goal g-link feature/issue-42-e2e
  printf '%s\n' '{"lifecycle":{"status":"waiting_for_user"}}' > "$E2E_REPO/lifecycle.yaml"
  _plant .flow
  _run_bin bin/flow-goal-record.sh --update-lifecycle --goal-id g-link --lifecycle-file lifecycle.yaml --from-status active
  _expect_refused 2 "refusing — .flow is a symlink"
  _expect_err_lacks "Traceback"
fi

# --- journal-record.sh and journal-append.sh (L6, L7) -----------------------

if _want journal-record-decisions-link; then
  _flow_test_begin "journal-record.sh (/flow:start Stranger Test block): a symlinked .decisions is not written (L6)"
  e2e_new journal-record-decisions-link
  e2e_describe ".decisions is a symlink to a directory outside the repository that holds another checkout's issue-42.md; the block runs with the gate result the command computed"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/.decisions"
  printf '# Another checkout'\''s journal\n' > "$E2E_REPO/.decisions/issue-42.md"
  _plant .decisions
  _run_with_env GATE_RESULT=PASS TASK_COUNT=3 ISSUE_NUM=42 -- \
    "$E2E_ACTIVE_PLUGIN/commands/start.md" 'STRANGER_TEST_EMIT_BLOCK_BEGIN'
  _expect_refused 2 "refusing — .decisions is a symlink"
fi

if _want journal-record-parent-link; then
  _flow_test_begin "journal-record.sh (/flow:start Stranger Test block): a journal.dir under a symlinked parent is not created there (L6)"
  e2e_new journal-record-parent-link
  e2e_describe "journal.dir is docs/decisions; docs is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"docs/decisions"}}'
  _plant docs
  _run_with_env GATE_RESULT=PASS TASK_COUNT=3 ISSUE_NUM=42 -- \
    "$E2E_ACTIVE_PLUGIN/commands/start.md" 'STRANGER_TEST_EMIT_BLOCK_BEGIN'
  _expect_refused 2 "refusing — docs is a symlink"
fi

if _want journal-append-decisions-link; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): a symlinked .decisions is not appended to (L7)"
  e2e_new journal-append-decisions-link
  e2e_describe ".decisions is a symlink to a directory outside the repository that holds another checkout's issue-42.md; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/.decisions"
  printf '# Another checkout'\''s journal\n' > "$E2E_REPO/.decisions/issue-42.md"
  _plant .decisions
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" '## Brainstorm Decision: {topic}'
  _expect_refused 2 "refusing — .decisions is a symlink"
fi

if _want journal-append-parent-link; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): a journal.dir under a symlinked parent is not created there (L7)"
  e2e_new journal-append-parent-link
  e2e_describe "journal.dir is docs/decisions; docs is a symlink to an empty directory outside the repository; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"docs/decisions"}}'
  _plant docs
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" '## Brainstorm Decision: {topic}'
  _expect_refused 2 "refusing — docs is a symlink"
fi

if _want journal-append-real; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): an ordinary repository still gets its entry (L15)"
  e2e_new journal-append-real
  e2e_describe "no symlink under the repository; branch feature/issue-42-e2e, no journal yet"
  e2e_repo feature/issue-42-e2e
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" '## Brainstorm Decision: {topic}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_file_has ".decisions/issue-42.md" "## Brainstorm Decision: {topic}"
fi

# --- session-end-state.sh (L8) ----------------------------------------------

SESSION_END='{"session_id":"e2e-session"}'

if _want session-end-flow-link; then
  _flow_test_begin "SessionEnd hook: an active run under a symlinked .flow gets no event (L8)"
  e2e_new session-end-flow-link
  e2e_describe "an active run is created, then .flow is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _plant .flow
  e2e_run_hook "$SESSION_END_HOOK" "$SESSION_END"
  _expect_refused 0 "refusing — .flow is a symlink"
fi

if _want session-end-runs-link; then
  _flow_test_begin "SessionEnd hook: an active run under a symlinked .flow/runs gets no event (L8)"
  e2e_new session-end-runs-link
  e2e_describe "an active run is created, then .flow/runs is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _plant .flow/runs
  e2e_run_hook "$SESSION_END_HOOK" "$SESSION_END"
  _expect_refused 0 "refusing — .flow/runs is a symlink"
fi

if _want session-end-run-dir-link; then
  _flow_test_begin "SessionEnd hook: an active run whose directory is a symlink gets no event (L8)"
  e2e_new session-end-run-dir-link
  e2e_describe "an active run is created, then its directory is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _plant ".flow/runs/$RID"
  e2e_run_hook "$SESSION_END_HOOK" "$SESSION_END"
  _expect_refused 0 "refusing — .flow/runs/$RID is a symlink"
fi

if _want session-end-real; then
  _flow_test_begin "SessionEnd hook: an active run in an ordinary repository still gets its event (L15)"
  e2e_new session-end-real
  e2e_describe "an active run, no symlink under the repository"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  e2e_run_hook "$SESSION_END_HOOK" "$SESSION_END"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_file_has ".flow/runs/$RID/events.jsonl" '"type": "session_end"'
fi

# --- flow-strip-auto-log.sh (L9) --------------------------------------------

if _want strip-parent-link; then
  _flow_test_begin "flow-strip-auto-log.sh (/flow:setup strip block): a journal dir under a symlinked parent is not rewritten (L9)"
  e2e_new strip-parent-link
  e2e_describe "journal.dir is docs/decisions; docs is moved outside the repository and replaced by a symlink to it; its journal carries one breadcrumb"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"docs/decisions"}}'
  mkdir -p "$E2E_REPO/docs/decisions"
  printf '# Journal\n\nA decision.\n\n<!-- auto-log: 2026-05-20 10:00 Edit src/search.ts -->\n' \
    > "$E2E_REPO/docs/decisions/issue-42.md"
  _plant docs
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/setup.md" '/bin/flow-strip-auto-log.sh" --apply'
  _expect_refused 2 "refusing — journal dir docs/decisions"
fi

# --- command pre-flights and the run's creation (L10-L13) -------------------

if _want trigger-preflight-flow-link; then
  _flow_test_begin "/flow:trigger pre-flight: a symlinked .flow gets no triggers directory (L10)"
  e2e_new trigger-preflight-flow-link
  e2e_describe "flow.triggers.enabled is true; .flow is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _settings '{"flow":{"triggers":{"enabled":true}}}'
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/trigger.md" '.flow/triggers'
  _expect_refused 1 "refusing — .flow is a symlink"
fi

if _want watch-preflight-flow-link; then
  _flow_test_begin "/flow:watch pre-flight: a symlinked .flow gets no triggers directory (L10)"
  e2e_new watch-preflight-flow-link
  e2e_describe "flow.triggers.enabled is true; .flow is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _settings '{"flow":{"triggers":{"enabled":true}}}'
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/watch.md" '.flow/triggers'
  _expect_refused 1 "refusing — .flow is a symlink"
fi

if _want goal-preflight-flow-link; then
  _flow_test_begin "/flow:goal pre-flight: a symlinked .flow gets no goals directory (L11)"
  e2e_new goal-preflight-flow-link
  e2e_describe ".flow is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/goal.md" 'Resolve stopHookEnforcement'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _expect_untouched
fi

if _want start-journal-link; then
  _flow_test_begin "/flow:start journal block: a symlinked .decisions is refused (L12)"
  e2e_new start-journal-link
  e2e_describe ".decisions is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _plant .decisions
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" '.decisions'
  _expect_refused 1 "refusing — .decisions is a symlink"
fi

RUN_SKILL="skills/run-state-management/SKILL.md"

if _want run-create-flow-link; then
  _flow_test_begin "run-state-management: a symlinked .flow gets no run directory (L13)"
  e2e_new run-create-flow-link
  e2e_describe ".flow is a symlink to an empty directory outside the repository; the block runs with the run id the command chose"
  e2e_repo feature/issue-42-e2e
  _plant .flow
  _run_with_env RUN_ID="$RID" -- "$E2E_ACTIVE_PLUGIN/$RUN_SKILL" 'RUN_DIR_CREATE_BLOCK_BEGIN'
  _expect_refused 1 "refusing — .flow is a symlink"
  e2e_expect_no_line "RUN_DIR=.flow/runs/$RID"
fi

if _want run-create-runs-link; then
  _flow_test_begin "run-state-management: a symlinked .flow/runs gets no run directory (L13)"
  e2e_new run-create-runs-link
  e2e_describe ".flow/runs is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _plant .flow/runs
  _run_with_env RUN_ID="$RID" -- "$E2E_ACTIVE_PLUGIN/$RUN_SKILL" 'RUN_DIR_CREATE_BLOCK_BEGIN'
  _expect_refused 1 "refusing — .flow/runs is a symlink"
fi

if _want run-create-real; then
  _flow_test_begin "run-state-management: an ordinary repository gets its run directory (L15)"
  e2e_new run-create-real
  e2e_describe "no symlink under the repository"
  e2e_repo feature/issue-42-e2e
  _run_with_env RUN_ID="$RID" -- "$E2E_ACTIVE_PLUGIN/$RUN_SKILL" 'RUN_DIR_CREATE_BLOCK_BEGIN'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "RUN_DIR=.flow/runs/$RID"
  e2e_expect_equal yes "$([ -d "$E2E_REPO/.flow/runs/$RID" ] && [ ! -L "$E2E_REPO/.flow/runs/$RID" ] && echo yes || echo no)" "a real run directory exists"
fi

if _want journal-dotdot-link; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): a journal.dir that climbs out of a symlinked directory with .. is refused (L14)"
  e2e_new journal-dotdot-link
  e2e_describe "journal.dir is shared/../escaped; shared is a symlink to outside/inner, so the name reaches outside/escaped, while read without the link it names escaped in the repository; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"shared/../escaped"}}'
  mkdir -p "$E2E_DIR/outside/inner" "$E2E_DIR/outside/escaped"
  ln -s "$E2E_DIR/outside/inner" "$E2E_REPO/shared"
  printf 'planted: shared -> <scratch>/%s/outside/inner\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
  BEFORE=$(_outside_state)
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" '## Brainstorm Decision: {topic}'
  _expect_refused 2 "refusing — shared is a symlink"
fi
