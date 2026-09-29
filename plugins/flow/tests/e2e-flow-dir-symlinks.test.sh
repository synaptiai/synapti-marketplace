# shellcheck shell=bash
# End-to-end: flow never creates or writes a file through a symlinked
# directory under .flow/ or the decision journal, never reads a goal through
# one, and never writes the journal outside the repository because the
# repository's own settings say so.
#
# A repository can commit .flow, .flow/runs, .flow/goals or .decisions as a
# symlink to a directory outside the checkout. Each writer refused a symlink at
# the file it writes, but followed one at a directory above it, so the run
# state, goals, evidence and journal entries landed in the link's target; the
# readers of .flow/goals followed it too, so the Stop hook and the gates acted
# on a goal that belongs elsewhere. Each scenario plants such a link to
# $E2E_DIR/outside in a scratch repository, runs the writer or reader the way
# flow reaches it (the shipped command block or hook when one runs as
# committed; otherwise the helper, with the arguments the command or skill
# passes it), and checks that the target is left exactly as it was, that the
# refusal is on stderr, and the exit status the code's header gives for it.
#
# journal.dir is the other way out of the repository: .claude/settings.flow.json
# is committed, so a repository chooses where its journal is written. A value
# from the repository's settings must resolve inside the repository and falls
# back to .decisions with a warning otherwise; a value from the user's own
# settings may point anywhere. The artifact for each scenario is written to
# $FLOW_E2E_ARTIFACT_DIR.
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
#
# Reads of .flow/goals:
#   L16 the Stop hook reads the active goal through a symlinked .flow or
#      .flow/goals, or reads a goal file that is itself a symlink, and blocks
#      or approves the stop on a goal that belongs elsewhere: its own scan
#      refused none of them
#   L17 flow-active-goal.sh, which the /flow:merge, /flow:pr and /flow:status
#      gates ask, answers with a goal read through a symlinked .flow: it
#      refused only a symlinked .flow/goals
#   L18 the /flow:goal status scan names an active goal read through a
#      symlinked .flow
#   L19 /flow:learn lists the goal files it finds through a symlinked .flow
#   L20 /flow:start resumes a goal it read through a symlinked .flow
#   L21 a refused read is silent, or the Stop hook blocks on it instead of
#      treating the goal as absent
#   L22 the read check refuses what it should not: an ordinary repository's
#      goal is no longer read
#
# journal.dir set in the repository's own settings:
#   L23 a journal.dir in .claude/settings.flow.json that leaves the repository
#      (`..`, or a directory under a symlink) is written by journal-record.sh
#      or journal-append.sh
#   L24 the same value in .claude/settings.flow.local.json, which a pull
#      request can commit as well, is not checked
#   L25 inside is decided on the string: an absolute path that only shares
#      the repository's path as a prefix (<repo>-outside) passes, or a
#      component that is a symlink passes because its name is under the
#      repository
#   L26 the refusal is silent, does not name the value and the file it came
#      from, or stops the writer instead of falling back to .decisions
#   L27 the writers and readers disagree: the /flow:setup strip refuses a
#      value journal-record.sh and journal-append.sh write to, or /flow:learn
#      or /flow:explain reads a directory the writers no longer use
#   L28 a journal.dir in the user's own settings that points outside the
#      repository is refused, warned about, or not stripped: the strip refused
#      `..` and absolute paths outside the repository, and journal-record.sh
#      warned on `..`, whichever file the value came from
#   L29 a journal.dir in the repository's settings inside the repository
#      (docs/decisions) is refused
#   L30 a file other than bin/journal-dir.sh resolves journal.dir itself, so a
#      writer or reader added later skips the rule
#   L31 a repository journal.dir that is refused falls back to .decisions even
#      when the user's own settings set a journal.dir, so the user's journal
#      is split across two directories
#   L32 the /flow:start journal block and the /flow:pr journal section use
#      .decisions whatever journal.dir says: /flow:start creates a directory no
#      writer uses, and /flow:pr reads a journal nobody wrote
#   L33 /flow:resume counts a change to the configured journal as unlinked
#      human work
#
# Reads of .flow/runs:
#   L34 a reader of .flow/runs — the /flow:learn listing, the /flow:resume
#      pre-flight, scan and run read, the /flow:status recent runs, the
#      judge's evidence bundle — reads a run through a symlinked .flow,
#      .flow/runs or run directory
#   L35 a refused run is silent, or is reported as unreadable instead of as
#      absent
#   L36 the run-read check refuses what it should not: an ordinary
#      repository's runs are no longer read
#
# Refusals the gates report:
#   L37 the /flow:merge and /flow:pr goal gates, /flow:status and the
#      gh issue create hook show a refused goal read only as
#      "flow-active-goal.sh exited 2", without the path that was refused
#
# A check that cannot run:
#   L38 when the directory check cannot run (python3 missing or failing), a
#      reader reports what a refusal or an empty directory reports:
#      /flow:status and /flow:learn show no runs or goal files, /flow:resume
#      says no runs exist or blames a symlink, /flow:start treats the goal as
#      absent, and the /flow:start journal block, the /flow:trigger and
#      /flow:watch pre-flights, run creation and the /flow:setup strip say
#      "refusing"; journal-dir.sh calls a repository journal.dir it could not
#      check refused
#
# Operands that look like options:
#   L39 a journal.dir that starts with '-' is read by flow-mkdir.sh as an
#      option: `--check` makes the /flow:start journal block fail with a usage
#      message, and `-h` prints the help and exits 0 without checking, so a
#      repository that commits `-h` as a symlink is written through
#
# Paths spelled through a symlink above the repository:
#   L40 an absolute path to the repository spelled through a symlink above it
#      (macOS /var for /private/var) counts as outside the rule, so a
#      directory the repository committed as a symlink is written through

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

# _local_settings <json> — the repository's .claude/settings.flow.local.json.
# The artifact does not print it, so a value naming a scratch path goes here.
_local_settings() {
  mkdir -p "$E2E_REPO/.claude"
  printf '%s\n' "$1" > "$E2E_REPO/.claude/settings.flow.local.json"
}

# _user_settings <json> — the user's settings file, ~/.claude/settings.flow.json
# under the scenario's HOME, which the harness runs every step with.
_user_settings() {
  mkdir -p "$E2E_HOME/.claude"
  printf '%s\n' "$1" > "$E2E_HOME/.claude/settings.flow.json"
}

# _outside_empty — an empty $E2E_DIR/outside, and BEFORE its state.
_outside_empty() {
  mkdir -p "$E2E_DIR/outside"
  BEFORE=$(_outside_state)
}

# _physical <path> — the path as the kernel resolves it (macOS reaches the
# scratch root through /var -> /private/var).
_physical() { (cd "$1" 2>/dev/null && pwd -P); }

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
  _flow_test_begin "Stop hook: a goal reached through a symlinked .flow is not rewritten there (L5, L16)"
  e2e_new goal-lifecycle-flow-link
  e2e_describe "evaluator-loop; an active goal whose check fails is created, then .flow is moved outside the repository and replaced by a symlink to it; one stop"
  e2e_repo feature/issue-42-e2e
  _settings '{"flow":{"goals":{"stopHookEnforcement":"evaluator-loop"}}}'
  _create_goal g-link feature/issue-42-e2e
  _plant .flow
  e2e_run_hook "$STOP_HOOK" '{"session_id":"e2e-session","stop_hook_active":false}'
  # The hook used to read the goal through the link, block on its failing
  # check, and have its lifecycle update refused. It no longer reads a goal
  # through a symlinked .flow (L16), so the stop is approved as if no goal were
  # active. What L5 is about holds either way: nothing is written in the
  # link's target.
  e2e_expect_out '"decision":"approve"'
  e2e_expect_out 'no active flow goal'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "refusing — .flow is a symlink; goals are not read through it"
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
  e2e_describe "journal.dir is docs/decisions, set in the user's settings; docs is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  # Set in the user's settings, which may point anywhere, so the value reaches
  # the writer and its own check is what refuses. The same value in the
  # repository's settings is refused before any writer sees it (L23), and the
  # journal then goes to .decisions: journal-append-repo-parent-link.
  _user_settings '{"journal":{"dir":"docs/decisions"}}'
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
  e2e_describe "journal.dir is docs/decisions, set in the user's settings; docs is a symlink to an empty directory outside the repository; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  # The user's settings, as in journal-record-parent-link: a repository's own
  # value under a symlink never reaches the writer.
  _user_settings '{"journal":{"dir":"docs/decisions"}}'
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
  e2e_describe "journal.dir is docs/decisions, set in the user's settings; docs is moved outside the repository and replaced by a symlink to it; its journal carries one breadcrumb"
  e2e_repo feature/issue-42-e2e
  # The user's settings, as in journal-record-parent-link: a repository's own
  # value under a symlink never reaches the strip.
  _user_settings '{"journal":{"dir":"docs/decisions"}}'
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
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" 'JOURNAL_INIT_BLOCK_BEGIN'
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
  e2e_describe "journal.dir is shared/../escaped, set in the user's settings; shared is a symlink to outside/inner, so the name reaches outside/escaped, while read without the link it names escaped in the repository; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  # The user's settings, as in journal-record-parent-link: a repository's own
  # value that climbs out of a symlink never reaches the writer.
  _user_settings '{"journal":{"dir":"shared/../escaped"}}'
  mkdir -p "$E2E_DIR/outside/inner" "$E2E_DIR/outside/escaped"
  ln -s "$E2E_DIR/outside/inner" "$E2E_REPO/shared"
  printf 'planted: shared -> <scratch>/%s/outside/inner\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
  BEFORE=$(_outside_state)
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" '## Brainstorm Decision: {topic}'
  _expect_refused 2 "refusing — shared is a symlink"
fi

# --- reads of .flow/goals (L16-L22) -----------------------------------------
# A goal read through a symlinked .flow belongs to whatever directory the link
# names. Goal trust is keyed on the repository where the check runs, so no
# verification command runs from it, but the Stop hook blocked or approved on
# it and the gates answered with it. Every reader now refuses a symlink below
# the repository's top on the way to a goal, says so on stderr, and treats the
# goal as absent: the Stop hook approves, a command block reports no goal, and
# flow-active-goal.sh exits 2, the status its header gives for a refused
# symlink, which the gates read as blocked.

READ_NOTE="goals are not read through it"
GOAL_SCAN_MARK='GOAL_SCAN_BLOCK_BEGIN'
MERGE_GOAL_FENCE='### FlowGoal Gate'
BLOCK='{"flow":{"goals":{"stopHookEnforcement":"block"}}}'

if _want stop-block-flow-link; then
  _flow_test_begin "Stop hook (block): a goal under a symlinked .flow is not read, and the stop is approved (L16, L21)"
  e2e_new stop-block-flow-link
  e2e_describe "stopHookEnforcement block; a trusted goal owning this branch whose check fails is created, then .flow is moved outside the repository and replaced by a symlink to it; one stop"
  e2e_repo feature/issue-42-e2e
  _settings "$BLOCK"
  _create_goal g-link feature/issue-42-e2e
  _plant .flow
  e2e_run_hook "$STOP_HOOK" '{"session_id":"e2e-session","stop_hook_active":false}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out '"decision":"approve"'
  e2e_expect_out 'no active flow goal'
  e2e_expect_err "refusing — .flow is a symlink; $READ_NOTE"
  _expect_untouched
  e2e_expect_clean_edges
fi

if _want stop-block-goals-link; then
  _flow_test_begin "Stop hook (block): a goal under a symlinked .flow/goals is not read, and the stop is approved (L16, L21)"
  e2e_new stop-block-goals-link
  e2e_describe "stopHookEnforcement block; a trusted goal whose check fails is created, then .flow/goals is moved outside the repository and replaced by a symlink to it; one stop"
  e2e_repo feature/issue-42-e2e
  _settings "$BLOCK"
  _create_goal g-link feature/issue-42-e2e
  _plant .flow/goals
  e2e_run_hook "$STOP_HOOK" '{"session_id":"e2e-session","stop_hook_active":false}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out '"decision":"approve"'
  e2e_expect_out 'no active flow goal'
  e2e_expect_no_out 'Active goal: g-link'
  e2e_expect_err "refusing — .flow/goals is a symlink; $READ_NOTE"
  _expect_untouched
  e2e_expect_clean_edges
fi

if _want stop-block-goal-file-link; then
  _flow_test_begin "Stop hook (block): a goal file that is a symlink is not read, and the stop is approved (L16, L21)"
  e2e_new stop-block-goal-file-link
  e2e_describe "stopHookEnforcement block; a trusted goal whose check fails is created, then its file is moved outside the repository and replaced by a symlink to it; one stop"
  e2e_repo feature/issue-42-e2e
  _settings "$BLOCK"
  _create_goal g-link feature/issue-42-e2e
  mkdir -p "$E2E_DIR/outside"
  mv "$E2E_REPO/.flow/goals/g-link.goal.yaml" "$E2E_DIR/outside/g-link.goal.yaml" &&
    ln -s "$E2E_DIR/outside/g-link.goal.yaml" "$E2E_REPO/.flow/goals/g-link.goal.yaml" ||
    _flow_assert_fail "$E2E_NAME: could not plant the goal file symlink"
  printf 'planted: .flow/goals/g-link.goal.yaml -> <scratch>/%s/outside/g-link.goal.yaml\n' "$E2E_NAME" >> "$E2E_ARTIFACT"
  BEFORE=$(_outside_state)
  e2e_run_hook "$STOP_HOOK" '{"session_id":"e2e-session","stop_hook_active":false}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out '"decision":"approve"'
  e2e_expect_out 'no active flow goal'
  e2e_expect_no_out 'Active goal: g-link'
  e2e_expect_err "refusing — .flow/goals/g-link.goal.yaml is a symlink; $READ_NOTE"
  _expect_untouched
  e2e_expect_clean_edges
fi

if _want stop-block-real; then
  _flow_test_begin "Stop hook (block): an ordinary repository's goal is still read and blocks the stop (L22)"
  e2e_new stop-block-real
  e2e_describe "stopHookEnforcement block; a trusted goal owning this branch whose check fails; no symlink under the repository; one stop"
  e2e_repo feature/issue-42-e2e
  _settings "$BLOCK"
  _create_goal g-link feature/issue-42-e2e
  e2e_run_hook "$STOP_HOOK" '{"session_id":"e2e-session","stop_hook_active":false}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out '"decision":"block"'
  e2e_expect_out 'Active goal: g-link'
  _expect_err_lacks "$READ_NOTE"
  e2e_expect_clean_edges
fi

if _want merge-gate-flow-link; then
  _flow_test_begin "flow-active-goal.sh (/flow:merge goal gate): an achieved goal under a symlinked .flow does not pass the gate, and the gate names the path (L17, L37)"
  e2e_new merge-gate-flow-link
  e2e_describe "an achieved goal owning this branch is written, then .flow is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e achieved true
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/merge.md" "$MERGE_GOAL_FENCE"
  e2e_expect_line "FLOW_GOAL_GATE_STATE=blocked"
  # The gate says which path was refused, not only the exit status (L37).
  e2e_expect_line "FLOW_GOAL_BLOCK_REASON=flow-active-goal.sh exited 2: refusing — .flow is a symlink; $READ_NOTE"
  e2e_expect_no_line "FLOW_GOAL_ID=g-link"
  _expect_untouched
  e2e_expect_clean_edges
fi

if _want active-goal-flow-link; then
  _flow_test_begin "flow-active-goal.sh: a goal under a symlinked .flow is refused with exit 2 and a note (L17, L21)"
  e2e_new active-goal-flow-link
  e2e_describe "an active goal owning this branch is written, then .flow is moved outside the repository and replaced by a symlink to it; the helper is asked as /flow:status asks it"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _plant .flow
  _run_bin bin/flow-active-goal.sh --status
  _expect_refused 2 "refusing — .flow is a symlink; $READ_NOTE"
fi

if _want goal-status-flow-link; then
  _flow_test_begin "/flow:goal status scan: an active goal under a symlinked .flow is not named (L18, L21)"
  e2e_new goal-status-flow-link
  e2e_describe "an active goal is written, then .flow is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/goal.md" "$GOAL_SCAN_MARK"
  e2e_expect_line "STATE=none"
  e2e_expect_no_line "ACTIVE_GOAL=.flow/goals/g-link.goal.yaml"
  e2e_expect_err "refusing — .flow is a symlink; $READ_NOTE"
  _expect_untouched
  e2e_expect_clean_edges
fi

if _want goal-status-real; then
  _flow_test_begin "/flow:goal status scan: an ordinary repository's active goal is named (L22)"
  e2e_new goal-status-real
  e2e_describe "an active goal, no symlink under the repository"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/goal.md" "$GOAL_SCAN_MARK"
  e2e_expect_line "STATE=ok"
  e2e_expect_line "ACTIVE_GOAL=.flow/goals/g-link.goal.yaml"
  e2e_expect_clean_edges
fi

if _want learn-goals-flow-link; then
  _flow_test_begin "/flow:learn: goal files under a symlinked .flow are not listed (L19, L21)"
  e2e_new learn-goals-flow-link
  e2e_describe "a goal is written, then .flow is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/learn.md" 'GOAL_FILE_COUNT='
  e2e_expect_line "GOAL_FILE_COUNT=0"
  e2e_expect_no_line "GOAL_FILE=.flow/goals/g-link.goal.yaml"
  e2e_expect_err "refusing — .flow is a symlink; $READ_NOTE"
  _expect_untouched
  e2e_expect_clean_edges
fi

if _want learn-goals-real; then
  _flow_test_begin "/flow:learn: an ordinary repository's goal files are listed (L22)"
  e2e_new learn-goals-real
  e2e_describe "a goal, no symlink under the repository"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/learn.md" 'GOAL_FILE_COUNT='
  e2e_expect_line "GOAL_FILE_COUNT=1"
  e2e_expect_line "GOAL_FILE=.flow/goals/g-link.goal.yaml"
  e2e_expect_clean_edges
fi

if _want start-goal-flow-link; then
  _flow_test_begin "/flow:start goal block: a goal under a symlinked .flow is not resumed (L20, L21)"
  e2e_new start-goal-flow-link
  e2e_describe "an active goal issue-42 is written, then .flow is moved outside the repository and replaced by a symlink to it; /flow:start 42"
  e2e_repo feature/issue-42-e2e
  e2e_goal issue-42 feature/issue-42-e2e active true
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" 'GOAL_PATH=".flow/goals/${GOAL_ID}.goal.yaml"' 42
  e2e_expect_line "FLOW_GOAL_STATE=create"
  e2e_expect_no_line "FLOW_GOAL_STATE=exists"
  e2e_expect_err "refusing — .flow is a symlink; $READ_NOTE"
  _expect_untouched
  e2e_expect_clean_edges
fi

if _want start-goal-real; then
  _flow_test_begin "/flow:start goal block: an ordinary repository's goal is resumed (L22)"
  e2e_new start-goal-real
  e2e_describe "an active goal issue-42, no symlink under the repository; /flow:start 42"
  e2e_repo feature/issue-42-e2e
  e2e_goal issue-42 feature/issue-42-e2e active true
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" 'GOAL_PATH=".flow/goals/${GOAL_ID}.goal.yaml"' 42
  e2e_expect_line "FLOW_GOAL_STATE=exists"
  e2e_expect_line "GOAL_STATUS=active"
  e2e_expect_clean_edges
fi

# --- journal.dir from the repository's settings (L23-L30) --------------------
# A journal.dir in .claude/settings.flow.json or .claude/settings.flow.local.json
# must resolve inside the repository, by ensure_repo_dir()'s rule: it ends under
# the repository's physical path, and no component of it that exists is a
# symlink. Otherwise the writers warn, naming the value and the file, and use
# .decisions. A journal.dir in the user's own settings is used as configured.

REPO_REFUSED="refusing journal.dir"
STRANGER='STRANGER_TEST_EMIT_BLOCK_BEGIN'
BRAINSTORM='## Brainstorm Decision: {topic}'
STRIP='/bin/flow-strip-auto-log.sh" --apply'
CRUMB='<!-- auto-log: 2026-05-20 10:00 Edit src/search.ts -->'

if _want journal-record-repo-dotdot; then
  _flow_test_begin "journal-record.sh (/flow:start Stranger Test block): a repository journal.dir that climbs out with .. is refused, and the journal goes to .decisions (L23, L26)"
  e2e_new journal-record-repo-dotdot
  e2e_describe "journal.dir is ../outside in .claude/settings.flow.json; outside is an empty directory beside the repository"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"../outside"}}'
  _outside_empty
  _run_with_env GATE_RESULT=PASS TASK_COUNT=3 ISSUE_NUM=42 -- \
    "$E2E_ACTIVE_PLUGIN/commands/start.md" "$STRANGER"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "$REPO_REFUSED '../outside' from .claude/settings.flow.json"
  e2e_expect_file_has ".decisions/issue-42.md" "type: stranger-test"
  _expect_untouched
fi

if _want journal-append-repo-parent-link; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): a repository journal.dir under a symlinked directory is refused, and the entry goes to .decisions (L23, L25, L26)"
  e2e_new journal-append-repo-parent-link
  e2e_describe "journal.dir is docs/decisions in .claude/settings.flow.json; docs is a symlink to an empty directory outside the repository; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"docs/decisions"}}'
  _plant docs
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" "$BRAINSTORM"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "$REPO_REFUSED 'docs/decisions' from .claude/settings.flow.json: docs is a symlink"
  e2e_expect_file_has ".decisions/issue-42.md" "$BRAINSTORM"
  _expect_untouched
fi

if _want journal-append-local-absolute; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): an absolute journal.dir outside the repository in the local settings file is refused (L24, L26)"
  e2e_new journal-append-local-absolute
  e2e_describe "journal.dir in .claude/settings.flow.local.json is the physical path of an empty directory beside the repository; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _outside_empty
  _local_settings "{\"journal\":{\"dir\":\"$(_physical "$E2E_DIR/outside")\"}}"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" "$BRAINSTORM"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "from .claude/settings.flow.local.json: "
  e2e_expect_err "$REPO_REFUSED"
  e2e_expect_file_has ".decisions/issue-42.md" "$BRAINSTORM"
  _expect_untouched
fi

if _want journal-record-local-prefix; then
  _flow_test_begin "journal-record.sh (/flow:start Stranger Test block): an absolute journal.dir that only shares the repository's path as a prefix is refused (L25)"
  e2e_new journal-record-local-prefix
  e2e_describe "journal.dir in .claude/settings.flow.local.json is <physical repository path>-outside, a directory that does not exist beside the repository"
  e2e_repo feature/issue-42-e2e
  _local_settings "{\"journal\":{\"dir\":\"$(_physical "$E2E_REPO")-outside\"}}"
  _run_with_env GATE_RESULT=PASS TASK_COUNT=3 ISSUE_NUM=42 -- \
    "$E2E_ACTIVE_PLUGIN/commands/start.md" "$STRANGER"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "$REPO_REFUSED"
  e2e_expect_file_has ".decisions/issue-42.md" "type: stranger-test"
  e2e_expect_equal no "$([ -e "$E2E_DIR/repo-outside" ] && echo yes || echo no)" "a directory was created beside the repository"
fi

if _want strip-repo-dotdot; then
  _flow_test_begin "flow-strip-auto-log.sh (/flow:setup strip block): a repository journal.dir that climbs out with .. is refused, and .decisions is stripped instead (L23, L27)"
  e2e_new strip-repo-dotdot
  e2e_describe "journal.dir is ../outside in .claude/settings.flow.json; outside, beside the repository, holds a journal carrying one breadcrumb"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"../outside"}}'
  mkdir -p "$E2E_DIR/outside"
  printf '# Journal\n\nA decision.\n\n%s\n' "$CRUMB" > "$E2E_DIR/outside/issue-42.md"
  BEFORE=$(_outside_state)
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/setup.md" "$STRIP"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "$REPO_REFUSED '../outside' from .claude/settings.flow.json"
  e2e_expect_line "STRIP_AUTO_LOG=none"
  _expect_untouched
fi

if _want strip-user-absolute; then
  _flow_test_begin "flow-strip-auto-log.sh (/flow:setup strip block): a journal.dir outside the repository set in the user's settings is stripped where it points (L27, L28)"
  e2e_new strip-user-absolute
  e2e_describe "journal.dir in the user's settings is the physical path of a directory beside the repository holding a journal with one breadcrumb"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_DIR/outside"
  printf '# Journal\n\nA decision.\n\n%s\n' "$CRUMB" > "$E2E_DIR/outside/issue-42.md"
  _user_settings "{\"journal\":{\"dir\":\"$(_physical "$E2E_DIR/outside")\"}}"
  # One shell only: the block rewrites the journal, so a second run finds
  # nothing left to strip and prints a different report.
  E2E_FENCE_SHELLS="${E2E_FENCE_SHELLS%% *}" e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/setup.md" "$STRIP"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "STRIP_AUTO_LOG_APPLIED=1 files=1 removed=1 warned=0"
  e2e_expect_equal "$(printf '# Journal\n\nA decision.')" "$(cat "$E2E_DIR/outside/issue-42.md")" "the journal the user's journal.dir names, stripped"
  _expect_err_lacks "refusing"
fi

if _want journal-append-user-absolute; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): a journal.dir outside the repository set in the user's settings is written as configured (L28)"
  e2e_new journal-append-user-absolute
  e2e_describe "journal.dir in the user's settings is the physical path of an empty directory beside the repository; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_DIR/outside"
  _user_settings "{\"journal\":{\"dir\":\"$(_physical "$E2E_DIR/outside")\"}}"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" "$BRAINSTORM"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal yes "$(grep -qF "$BRAINSTORM" "$E2E_DIR/outside/issue-42.md" 2>/dev/null && echo yes || echo no)" "the entry is in the journal the user's journal.dir names"
  e2e_expect_equal no "$([ -e "$E2E_REPO/.decisions" ] && echo yes || echo no)" ".decisions was created"
  _expect_err_lacks "refusing"
fi

if _want journal-record-user-dotdot; then
  _flow_test_begin "journal-record.sh (/flow:start Stranger Test block): a journal.dir that climbs out with .. set in the user's settings is written without a warning (L28)"
  e2e_new journal-record-user-dotdot
  e2e_describe "journal.dir is ../outside in the user's settings; outside is an empty directory beside the repository"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_DIR/outside"
  _user_settings '{"journal":{"dir":"../outside"}}'
  _run_with_env GATE_RESULT=PASS TASK_COUNT=3 ISSUE_NUM=42 -- \
    "$E2E_ACTIVE_PLUGIN/commands/start.md" "$STRANGER"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_equal yes "$(grep -qF 'type: stranger-test' "$E2E_DIR/outside/issue-42.md" 2>/dev/null && echo yes || echo no)" "the manifest is in the journal the user's journal.dir names"
  _expect_err_lacks "WARN"
  _expect_err_lacks "refusing"
fi

if _want journal-append-repo-inside; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): a repository journal.dir inside the repository is used (L29)"
  e2e_new journal-append-repo-inside
  e2e_describe "journal.dir is docs/decisions in .claude/settings.flow.json; no symlink under the repository; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"docs/decisions"}}'
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" "$BRAINSTORM"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_file_has "docs/decisions/issue-42.md" "$BRAINSTORM"
  _expect_err_lacks "refusing"
fi

if _want learn-journal-repo-dotdot; then
  _flow_test_begin "/flow:learn: a repository journal.dir that climbs out with .. is not read; .decisions is (L27)"
  e2e_new learn-journal-repo-dotdot
  e2e_describe "journal.dir is ../outside in .claude/settings.flow.json; outside, beside the repository, holds a journal"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"../outside"}}'
  mkdir -p "$E2E_DIR/outside"
  printf '# Another journal\n' > "$E2E_DIR/outside/issue-7.md"
  BEFORE=$(_outside_state)
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/learn.md" 'GOAL_FILE_COUNT='
  e2e_expect_line "JOURNAL_DIR=.decisions"
  e2e_expect_no_line "JOURNAL_FILE=../outside/issue-7.md"
  e2e_expect_err "$REPO_REFUSED '../outside' from .claude/settings.flow.json"
  _expect_untouched
  e2e_expect_clean_edges
fi

if _want explain-journal-repo-dotdot; then
  _flow_test_begin "/flow:explain: a repository journal.dir that climbs out with .. is not read; .decisions is (L27)"
  e2e_new explain-journal-repo-dotdot
  e2e_describe "journal.dir is ../outside in .claude/settings.flow.json; outside, beside the repository, holds issue-42.md; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"../outside"}}'
  mkdir -p "$E2E_DIR/outside"
  printf '# The journal outside the repository\n' > "$E2E_DIR/outside/issue-42.md"
  BEFORE=$(_outside_state)
  e2e_gh_fixture issue-42 '{"title":"Search","body":"Find things."}'
  e2e_gh_fixture repo '{"defaultBranchRef":{"name":"main"}}'
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/explain.md" '### Decision Journal'
  e2e_expect_line "JOURNAL_DIR=.decisions"
  e2e_expect_no_line "# The journal outside the repository"
  e2e_expect_err "$REPO_REFUSED '../outside' from .claude/settings.flow.json"
  _expect_untouched
  e2e_expect_clean_edges
fi

if _want journal-dir-one-place; then
  _flow_test_begin "journal.dir is resolved in one place: no other shipped file reads it from the settings (L30)"
  # A writer or reader that asks cascade-resolve.sh for journal.dir itself skips
  # the rule for the repository's settings, which is how the three writers came
  # to disagree. Every expression that selects the key names it as
  # '.journal.dir; the only file allowed to is the resolver. cascade-resolve.sh
  # is the generic settings reader the resolver calls, and names the key only in
  # a comment's example.
  JOURNAL_DIR_READERS=$(cd "$E2E_PLUGIN_DIR" && grep -rlF "'.journal.dir" bin hooks commands skills agents 2>/dev/null | grep -vxF bin/cascade-resolve.sh | LC_ALL=C sort | tr '\n' ' ')
  assert_equal "bin/journal-dir.sh " "$JOURNAL_DIR_READERS" "the files that resolve journal.dir from the settings"
fi

# --- the user's journal.dir behind a refused one (L31) -----------------------

if _want journal-append-repo-refused-user-set; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): a refused repository journal.dir leaves the user's journal.dir in effect (L31)"
  e2e_new journal-append-repo-refused-user-set
  e2e_describe "journal.dir is ../outside in .claude/settings.flow.json and the physical path of a directory beside the repository in the user's settings; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"../outside"}}'
  _outside_empty
  mkdir -p "$E2E_DIR/userjournal"
  _user_settings "{\"journal\":{\"dir\":\"$(_physical "$E2E_DIR/userjournal")\"}}"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" "$BRAINSTORM"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "$REPO_REFUSED '../outside' from .claude/settings.flow.json"
  e2e_expect_err "userjournal"
  e2e_expect_equal yes "$(grep -qF "$BRAINSTORM" "$E2E_DIR/userjournal/issue-42.md" 2>/dev/null && echo yes || echo no)" "the entry is in the journal the user's journal.dir names"
  e2e_expect_equal no "$([ -e "$E2E_REPO/.decisions" ] && echo yes || echo no)" ".decisions was created"
  _expect_untouched
fi

# --- journal readers and writers that named .decisions themselves (L32, L33) --

# _section <heading> — the lines of stdout under "### <heading>", up to the
# next "### " heading.
_section() {
  printf '%s\n' "$E2E_OUT" | awk -v h="### $1" '$0 == h { f = 1; next } /^### / { f = 0 } f'
}

# _commit_all — commit everything in the scratch repository, so only what a
# scenario changes afterwards shows in git status.
_commit_all() {
  (_e2e_git_env; cd "$E2E_REPO" && git add -A && git commit -q -m setup) ||
    _flow_assert_fail "$E2E_NAME: could not commit the setup"
}

JOURNAL_INIT='JOURNAL_INIT_BLOCK_BEGIN'
PR_CONTEXT='### Decision Journal'

if _want start-journal-configured; then
  _flow_test_begin "/flow:start journal block: the configured journal.dir is created, not .decisions (L32)"
  e2e_new start-journal-configured
  e2e_describe "journal.dir is docs/decisions in .claude/settings.flow.json; no journal directory exists yet"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"docs/decisions"}}'
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" "$JOURNAL_INIT"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "JOURNAL_DIR=docs/decisions"
  e2e_expect_equal yes "$([ -d "$E2E_REPO/docs/decisions" ] && [ ! -L "$E2E_REPO/docs/decisions" ] && echo yes || echo no)" "docs/decisions is a real directory"
  e2e_expect_equal no "$([ -e "$E2E_REPO/.decisions" ] && echo yes || echo no)" ".decisions was created"
fi

if _want start-journal-repo-dotdot; then
  _flow_test_begin "/flow:start journal block: a refused repository journal.dir falls back to .decisions and the command goes on (L32)"
  e2e_new start-journal-repo-dotdot
  e2e_describe "journal.dir is ../outside in .claude/settings.flow.json; outside is an empty directory beside the repository"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"../outside"}}'
  _outside_empty
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" "$JOURNAL_INIT"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "JOURNAL_DIR=.decisions"
  e2e_expect_err "$REPO_REFUSED '../outside' from .claude/settings.flow.json"
  e2e_expect_equal yes "$([ -d "$E2E_REPO/.decisions" ] && echo yes || echo no)" ".decisions exists"
  _expect_untouched
fi

if _want pr-journal-configured; then
  _flow_test_begin "/flow:pr context block: the journal is read from the configured journal.dir (L32)"
  e2e_new pr-journal-configured
  e2e_describe "journal.dir is docs/decisions in .claude/settings.flow.json, holding issue-42.md; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"docs/decisions"}}'
  mkdir -p "$E2E_REPO/docs/decisions"
  printf '# The configured journal\n' > "$E2E_REPO/docs/decisions/issue-42.md"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/pr.md" "$PR_CONTEXT"
  e2e_expect_equal "yes" "$(_section 'Decision Journal' | grep -qxF 'JOURNAL_FILE=docs/decisions/issue-42.md' && echo yes || echo no)" "the Decision Journal section names docs/decisions/issue-42.md"
  e2e_expect_equal "yes" "$(_section 'Decision Journal' | grep -qxF '# The configured journal' && echo yes || echo no)" "the Decision Journal section carries its contents"
fi

if _want resume-unlinked-journal-dir; then
  _flow_test_begin "/flow:resume unlinked-change check: a change to the configured journal is flow's own (L33)"
  e2e_new resume-unlinked-journal-dir
  e2e_describe "journal.dir is docs/decisions in .claude/settings.flow.json; its issue-42.md is committed, then changed"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"docs/decisions"}}'
  mkdir -p "$E2E_REPO/docs/decisions"
  printf '# Journal\n' > "$E2E_REPO/docs/decisions/issue-42.md"
  _commit_all
  printf 'A decision.\n' >> "$E2E_REPO/docs/decisions/issue-42.md"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'FLOW_RESUME_UNLINKED=unknown'
  e2e_expect_line "FLOW_RESUME_UNLINKED=0"
  e2e_expect_no_line "  docs/decisions/issue-42.md"
fi

if _want resume-unlinked-real; then
  _flow_test_begin "/flow:resume unlinked-change check: a change outside flow's directories is still unlinked (L33)"
  e2e_new resume-unlinked-real
  e2e_describe "journal.dir is docs/decisions in .claude/settings.flow.json; src/search.ts is committed, then changed"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"docs/decisions"}}'
  mkdir -p "$E2E_REPO/src"
  printf 'x\n' > "$E2E_REPO/src/search.ts"
  _commit_all
  printf 'y\n' >> "$E2E_REPO/src/search.ts"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'FLOW_RESUME_UNLINKED=unknown'
  e2e_expect_line "FLOW_RESUME_UNLINKED=1"
  e2e_expect_line "  src/search.ts"
fi

# --- reads of .flow/runs (L34-L36) -------------------------------------------
# A run read through a symlinked .flow, .flow/runs or run directory belongs to
# the link's target. Every reader refuses it by the writers' rule, says so on
# stderr, and treats the run as absent.

RUNS_NOTE="runs are not read through it"

# _run_with_events — the active run at .flow/runs/$RID, with one event.
_run_with_events() {
  _run_yaml
  printf '%s\n' '{"type":"phase","phase":"code"}' > "$E2E_REPO/.flow/runs/$RID/events.jsonl"
}

if _want learn-runs-flow-link; then
  _flow_test_begin "/flow:learn: run events under a symlinked .flow are not listed (L34, L35)"
  e2e_new learn-runs-flow-link
  e2e_describe "an active run with one event is created, then .flow is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  _run_with_events
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/learn.md" 'GOAL_FILE_COUNT='
  e2e_expect_line "RUN_EVENT_FILE_COUNT=0"
  e2e_expect_no_line "RUN_EVENTS=.flow/runs/$RID/events.jsonl"
  e2e_expect_err "refusing — .flow is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want learn-runs-run-dir-link; then
  _flow_test_begin "/flow:learn: a run directory that is a symlink is not listed, and is named (L34, L35)"
  e2e_new learn-runs-run-dir-link
  e2e_describe "an active run with one event is created, then its directory is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  _run_with_events
  _plant ".flow/runs/$RID"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/learn.md" 'GOAL_FILE_COUNT='
  e2e_expect_line "RUN_EVENT_FILE_COUNT=0"
  e2e_expect_err "refusing — .flow/runs/$RID is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want learn-runs-real; then
  _flow_test_begin "/flow:learn: an ordinary repository's run events are listed (L36)"
  e2e_new learn-runs-real
  e2e_describe "an active run with one event, no symlink under the repository"
  e2e_repo feature/issue-42-e2e
  _run_with_events
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/learn.md" 'GOAL_FILE_COUNT='
  e2e_expect_line "RUN_EVENT_FILE_COUNT=1"
  e2e_expect_line "RUN_EVENTS=.flow/runs/$RID/events.jsonl"
fi

if _want resume-preflight-flow-link; then
  _flow_test_begin "/flow:resume pre-flight: runs under a symlinked .flow are treated as absent (L34, L35)"
  e2e_new resume-preflight-flow-link
  e2e_describe "an active run is created, then .flow is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'No FlowRuns exist'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out "No FlowRuns exist"
  e2e_expect_err "refusing — .flow is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want resume-scan-flow-link; then
  _flow_test_begin "/flow:resume scan: an active run under a symlinked .flow is not found (L34, L35)"
  e2e_new resume-scan-flow-link
  e2e_describe "an active run is created, then .flow is moved outside the repository and replaced by a symlink to it; /flow:resume with no run id"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'RESUME_SCAN_BLOCK_BEGIN'
  e2e_expect_line "STATE=none"
  e2e_expect_no_line "RUN_ID=$RID"
  e2e_expect_err "refusing — .flow is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want resume-scan-run-dir-link; then
  _flow_test_begin "/flow:resume scan: an active run whose directory is a symlink is not found, and is named (L34, L35)"
  e2e_new resume-scan-run-dir-link
  e2e_describe "an active run is created, then its directory is moved outside the repository and replaced by a symlink to it; /flow:resume with no run id"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _plant ".flow/runs/$RID"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'RESUME_SCAN_BLOCK_BEGIN'
  e2e_expect_line "STATE=none"
  e2e_expect_no_line "RUN_ID=$RID"
  e2e_expect_err "refusing — .flow/runs/$RID is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want resume-scan-real; then
  _flow_test_begin "/flow:resume scan: an ordinary repository's active run is found (L36)"
  e2e_new resume-scan-real
  e2e_describe "an active run, no symlink under the repository; /flow:resume with no run id"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'RESUME_SCAN_BLOCK_BEGIN'
  e2e_expect_line "STATE=ok"
  e2e_expect_line "RUN_ID=$RID"
fi

if _want resume-read-run-dir-link; then
  _flow_test_begin "/flow:resume run read: a run whose directory is a symlink is not read (L34, L35)"
  e2e_new resume-read-run-dir-link
  e2e_describe "an active run is created, then its directory is moved outside the repository and replaced by a symlink to it; the block runs with the run id step 1 chose"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _plant ".flow/runs/$RID"
  _run_with_env RUN_ID="$RID" -- "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'RUN_YAML="$RUN_DIR/run.yaml"'
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "refusing — .flow/runs/$RID is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want resume-read-real; then
  _flow_test_begin "/flow:resume run read: an ordinary repository's run is read (L36)"
  e2e_new resume-read-real
  e2e_describe "an active run, no symlink under the repository; the block runs with the run id step 1 chose"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _run_with_env RUN_ID="$RID" -- "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'RUN_YAML="$RUN_DIR/run.yaml"'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  _expect_err_lacks "$RUNS_NOTE"
fi

STATUS_MD_MARK='# RECENT_RUNS_BLOCK_BEGIN'

if _want status-runs-flow-link; then
  _flow_test_begin "/flow:status recent runs: runs under a symlinked .flow are not listed (L34, L35)"
  e2e_new status-runs-flow-link
  e2e_describe "an active run with one event is created, then .flow is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  _run_with_events
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/status.md" "$STATUS_MD_MARK"
  e2e_expect_equal "STATE=empty" "$(_section 'Recent Runs')" "the Recent Runs section"
  e2e_expect_err "refusing — .flow is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want status-runs-run-dir-link; then
  _flow_test_begin "/flow:status recent runs: a run directory that is a symlink is not listed, and is named (L34, L35)"
  e2e_new status-runs-run-dir-link
  e2e_describe "an active run with one event is created, then its directory is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  _run_with_events
  _plant ".flow/runs/$RID"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/status.md" "$STATUS_MD_MARK"
  e2e_expect_equal "STATE=empty" "$(_section 'Recent Runs')" "the Recent Runs section"
  e2e_expect_err "refusing — .flow/runs/$RID is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want status-runs-real; then
  _flow_test_begin "/flow:status recent runs: an ordinary repository's runs are listed (L36)"
  e2e_new status-runs-real
  e2e_describe "an active run with one event, no symlink under the repository"
  e2e_repo feature/issue-42-e2e
  _run_with_events
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/status.md" "$STATUS_MD_MARK"
  e2e_expect_equal "$(printf 'STATE=ok\nRUN=id=%s verdict=- activities=1' "$RID")" "$(_section 'Recent Runs')" "the Recent Runs section"
fi

# _run_bundle — the judge's evidence bundle for goal g-link and run $RID,
# assembled as the evaluator loop assembles it.
_run_bundle() {
  local code="bin/_flow_evidence_bundle.py"
  {
    printf 'code: %s\n' "$code"
    printf 'code sha256: %s\n' "$(_e2e_sha256 "$E2E_ACTIVE_PLUGIN/$code")"
    printf 'arguments: .flow/goals/g-link.goal.yaml {} .flow/runs/%s\n' "$RID"
  } >> "$E2E_ARTIFACT"
  _e2e_exec env PYTHONSAFEPATH=1 python3 "$E2E_ACTIVE_PLUGIN/$code" \
    .flow/goals/g-link.goal.yaml '{}' ".flow/runs/$RID"
  printf -- '--- expectations\n' >> "$E2E_ARTIFACT"
}

# _run_with_evidence — the run at .flow/runs/$RID with one evidence sidecar
# and a previous verdict.
_run_with_evidence() {
  _run_yaml
  mkdir -p "$E2E_REPO/.flow/runs/$RID/evidence"
  cp "$FIXTURES/evidence/valid.yaml" "$E2E_REPO/.flow/runs/$RID/evidence/evidence-ac1-test.evidence.yaml"
  printf '%s\n' '{"verdict":"not_achieved","confidence":0.4,"delta":"unchanged","reason":"PREVIOUS-VERDICT-MARK"}' \
    > "$E2E_REPO/.flow/runs/$RID/last-verdict.json"
}

if _want bundle-runs-link; then
  _flow_test_begin "evidence bundle (evaluator loop): a run under a symlinked .flow/runs is not read into the judge's prompt (L34, L35)"
  e2e_new bundle-runs-link
  e2e_describe "a goal, and a run with one evidence sidecar and a previous verdict; .flow/runs is then moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _run_with_evidence
  _plant .flow/runs
  _run_bundle
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out "(no run directory; evidence ledger unavailable)"
  e2e_expect_no_out "evidence-ac1-test"
  e2e_expect_no_out "PREVIOUS-VERDICT-MARK"
  e2e_expect_err "refusing — .flow/runs is a symlink; $RUNS_NOTE"
  _expect_untouched
fi

if _want bundle-real; then
  _flow_test_begin "evidence bundle (evaluator loop): an ordinary repository's run is read into the judge's prompt (L36)"
  e2e_new bundle-real
  e2e_describe "a goal, and a run with one evidence sidecar and a previous verdict; no symlink under the repository"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _run_with_evidence
  _run_bundle
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out "evidence-ac1-test"
  e2e_expect_out "PREVIOUS-VERDICT-MARK"
  _expect_err_lacks "$RUNS_NOTE"
fi

# --- refusals the gates report (L37) -----------------------------------------

if _want pr-gate-flow-link; then
  _flow_test_begin "/flow:pr goal gate: a goal under a symlinked .flow blocks, and the gate names the path (L17, L37)"
  e2e_new pr-gate-flow-link
  e2e_describe "an achieved goal owning this branch is written, then .flow is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e achieved true
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/pr.md" "$PR_CONTEXT"
  e2e_expect_equal "$(printf 'STATE=unavailable\nGATE=block\nREASON=flow-active-goal.sh exited 2: refusing — .flow is a symlink; %s' "$READ_NOTE")" "$(_section 'FlowGoal State')" "the FlowGoal State section"
  _expect_untouched
fi

if _want status-goal-flow-link; then
  _flow_test_begin "/flow:status goal section: a goal under a symlinked .flow is reported with the path refused (L37)"
  e2e_new status-goal-flow-link
  e2e_describe "an active goal owning this branch is written, then .flow is moved outside the repository and replaced by a symlink to it"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _plant .flow
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/status.md" "$STATUS_MD_MARK"
  e2e_expect_equal "$(printf 'STATE=unavailable\nREASON=flow-active-goal.sh exited 2: refusing — .flow is a symlink; %s' "$READ_NOTE")" "$(_section 'FlowGoal State')" "the FlowGoal State section"
  _expect_untouched
fi

if _want issue-hook-flow-link; then
  _flow_test_begin "gh issue create hook: a goal under a symlinked .flow is reported with the path refused (L37)"
  e2e_new issue-hook-flow-link
  e2e_describe "an active goal owning this branch is written, then .flow is moved outside the repository and replaced by a symlink to it; the agent runs gh issue create"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _plant .flow
  e2e_run_hook hooks/scripts/ask-issue-create.sh '{"tool_name":"Bash","tool_input":{"command":"gh issue create --title later"}}'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_err "flow-active-goal.sh exit 2: refusing — .flow is a symlink; $READ_NOTE"
  e2e_expect_no_out "permissionDecision"
  _expect_untouched
fi

# --- a check that cannot run (L38) -------------------------------------------
# python3 is replaced by a stub that exits 1, for the code the scenario runs
# only: the harness's own python3 calls do not look in $E2E_BIN.

# _python_dead — every python3 the code under test runs exits 1.
_python_dead() {
  printf '#!/bin/sh\nexit 1\n' > "$E2E_BIN/python3"
  chmod +x "$E2E_BIN/python3"
  printf 'python3: a stub that exits 1\n' >> "$E2E_ARTIFACT"
}

UNCHECKED="cannot check"

if _want status-runs-unchecked; then
  _flow_test_begin "/flow:status recent runs: a check that cannot run is reported as unavailable, not as no runs (L38)"
  e2e_new status-runs-unchecked
  e2e_describe "an active run with one event, no symlink; python3 exits 1"
  e2e_repo feature/issue-42-e2e
  _run_with_events
  _python_dead
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/status.md" "$STATUS_MD_MARK"
  e2e_expect_equal "STATE=unavailable" "$(_section 'Recent Runs' | head -1)" "the first line of the Recent Runs section"
  e2e_expect_equal yes "$(_section 'Recent Runs' | grep -q '^REASON=.*cannot check' && echo yes || echo no)" "the Recent Runs section says the check could not run"
  _expect_err_lacks "runs are not read through it"
fi

if _want learn-unchecked; then
  _flow_test_begin "/flow:learn: a check that cannot run is reported as unavailable, not as no goal files or runs (L38)"
  e2e_new learn-unchecked
  e2e_describe "a goal and an active run with one event, no symlink; python3 exits 1"
  e2e_repo feature/issue-42-e2e
  e2e_goal g-link feature/issue-42-e2e active true
  _run_with_events
  _python_dead
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/learn.md" 'GOAL_FILE_COUNT='
  e2e_expect_equal yes "$(_section 'FlowRun Events' | grep -qx 'STATE=unavailable' && echo yes || echo no)" "the FlowRun Events section is unavailable"
  e2e_expect_equal no "$(_section 'FlowRun Events' | grep -qx 'GOAL_FILE_COUNT=0' && echo yes || echo no)" "the section counts no goal files"
  e2e_expect_equal no "$(_section 'FlowRun Events' | grep -qx 'RUN_EVENT_FILE_COUNT=0' && echo yes || echo no)" "the section counts no run events"
  _expect_err_lacks "not read through it"
fi

if _want learn-journal-dir-unchecked; then
  _flow_test_begin "journal-dir.sh (/flow:learn): a repository journal.dir it cannot check is withheld and said so, not called refused (L38)"
  e2e_new learn-journal-dir-unchecked
  e2e_describe "journal.dir is docs/decisions in .claude/settings.flow.json; python3 exits 1"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"docs/decisions"}}'
  _python_dead
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/learn.md" 'GOAL_FILE_COUNT='
  e2e_expect_line "JOURNAL_DIR=.decisions"
  e2e_expect_err "$UNCHECKED journal.dir 'docs/decisions' from .claude/settings.flow.json"
  _expect_err_lacks "$REPO_REFUSED"
fi

if _want resume-preflight-unchecked; then
  _flow_test_begin "/flow:resume pre-flight: a check that cannot run is not reported as no runs (L38)"
  e2e_new resume-preflight-unchecked
  e2e_describe "an active run, no symlink; python3 exits 1"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _python_dead
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'No FlowRuns exist'
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_out "Cannot tell whether FlowRuns exist"
  e2e_expect_no_out "No FlowRuns exist"
  _expect_err_lacks "not read through"
fi

if _want resume-read-unchecked; then
  _flow_test_begin "/flow:resume run read: a check that cannot run is not reported as a symlink (L38)"
  e2e_new resume-read-unchecked
  e2e_describe "an active run, no symlink; python3 exits 1; the block runs with the run id step 1 chose"
  e2e_repo feature/issue-42-e2e
  _run_yaml
  _python_dead
  _run_with_env RUN_ID="$RID" -- "$E2E_ACTIVE_PLUGIN/commands/resume.md" 'RUN_YAML="$RUN_DIR/run.yaml"'
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_err "$UNCHECKED"
  _expect_err_lacks "refusing"
fi

if _want start-goal-unchecked; then
  _flow_test_begin "/flow:start goal block: a check that cannot run blocks, and the goal is not treated as absent (L38)"
  e2e_new start-goal-unchecked
  e2e_describe "an active goal issue-42, no symlink; python3 exits 1; /flow:start 42"
  e2e_repo feature/issue-42-e2e
  e2e_goal issue-42 feature/issue-42-e2e active true
  _python_dead
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" 'GOAL_PATH=".flow/goals/${GOAL_ID}.goal.yaml"' 42
  e2e_expect_line "FLOW_GOAL_STATE=blocked"
  e2e_expect_out "FLOW_GOAL_ERROR=$UNCHECKED"
  e2e_expect_no_line "FLOW_GOAL_STATE=create"
fi

if _want start-journal-unchecked; then
  _flow_test_begin "/flow:start journal block: a check that cannot run exits 3, not the 1 of a refused symlink (L38)"
  e2e_new start-journal-unchecked
  e2e_describe "no journal directory, no symlink; python3 exits 1"
  e2e_repo feature/issue-42-e2e
  _python_dead
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" "$JOURNAL_INIT"
  e2e_expect_equal 3 "$E2E_RC" "the exit status"
  e2e_expect_err "$UNCHECKED"
  _expect_err_lacks "refusing"
  e2e_expect_equal no "$([ -e "$E2E_REPO/.decisions" ] && echo yes || echo no)" ".decisions was created"
fi

if _want trigger-preflight-unchecked; then
  _flow_test_begin "/flow:trigger pre-flight: a check that cannot run exits 3, not the 1 of a refused symlink (L38)"
  e2e_new trigger-preflight-unchecked
  e2e_describe "flow.triggers.enabled is true; no symlink; python3 exits 1"
  e2e_repo feature/issue-42-e2e
  _settings '{"flow":{"triggers":{"enabled":true}}}'
  _python_dead
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/trigger.md" '.flow/triggers'
  e2e_expect_equal 3 "$E2E_RC" "the exit status"
  e2e_expect_err "$UNCHECKED"
  _expect_err_lacks "refusing"
  e2e_expect_equal no "$([ -e "$E2E_REPO/.flow/triggers" ] && echo yes || echo no)" ".flow/triggers was created"
fi

if _want watch-preflight-unchecked; then
  _flow_test_begin "/flow:watch pre-flight: a check that cannot run exits 3, not the 1 of a refused symlink (L38)"
  e2e_new watch-preflight-unchecked
  e2e_describe "flow.triggers.enabled is true; no symlink; python3 exits 1"
  e2e_repo feature/issue-42-e2e
  _settings '{"flow":{"triggers":{"enabled":true}}}'
  _python_dead
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/watch.md" '.flow/triggers'
  e2e_expect_equal 3 "$E2E_RC" "the exit status"
  e2e_expect_err "$UNCHECKED"
  _expect_err_lacks "refusing"
fi

if _want run-create-unchecked; then
  _flow_test_begin "run-state-management: a check that cannot run exits 3, not the 1 of a refused symlink (L38)"
  e2e_new run-create-unchecked
  e2e_describe "no symlink; python3 exits 1; the block runs with the run id the command chose"
  e2e_repo feature/issue-42-e2e
  _python_dead
  _run_with_env RUN_ID="$RID" -- "$E2E_ACTIVE_PLUGIN/$RUN_SKILL" 'RUN_DIR_CREATE_BLOCK_BEGIN'
  e2e_expect_equal 3 "$E2E_RC" "the exit status"
  e2e_expect_err "$UNCHECKED"
  _expect_err_lacks "refusing"
  e2e_expect_no_line "RUN_DIR=.flow/runs/$RID"
fi

if _want strip-unchecked; then
  _flow_test_begin "flow-strip-auto-log.sh (/flow:setup strip block): a check that cannot run is not reported as a refused symlink (L38)"
  e2e_new strip-unchecked
  e2e_describe ".decisions holds a journal with one breadcrumb; no symlink; python3 exits 1"
  e2e_repo feature/issue-42-e2e
  mkdir -p "$E2E_REPO/.decisions"
  printf '# Journal\n\nA decision.\n\n%s\n' "$CRUMB" > "$E2E_REPO/.decisions/issue-42.md"
  _python_dead
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/setup.md" "$STRIP"
  e2e_expect_equal 2 "$E2E_RC" "the exit status"
  e2e_expect_err "$UNCHECKED"
  _expect_err_lacks "refusing"
  e2e_expect_file_has ".decisions/issue-42.md" "$CRUMB"
fi

# .flow with no permissions: a component below it cannot be inspected, which
# is a check that could not be done, not a refusal. Skipped as root, which
# chmod does not stop.
_flow_is_root() { [ "$(id -u)" = 0 ]; }

if _want stop-block-goals-uninspectable; then
  _flow_test_begin "Stop hook (block): a .flow/goals that cannot be inspected leaves the goal unknown, not absent (L38)"
  if _flow_is_root; then
    _flow_assert_pass "SKIP: running as root, which permissions do not stop"
  else
    e2e_new stop-block-goals-uninspectable
    e2e_describe "stopHookEnforcement block; a trusted goal whose check fails; .flow is then made unreadable (mode 000); one stop"
    e2e_repo feature/issue-42-e2e
    _settings "$BLOCK"
    _create_goal g-link feature/issue-42-e2e
    chmod 000 "$E2E_REPO/.flow"
    e2e_run_hook "$STOP_HOOK" '{"session_id":"e2e-session","stop_hook_active":false}'
    chmod 755 "$E2E_REPO/.flow"
    e2e_expect_equal 0 "$E2E_RC" "the exit status"
    e2e_expect_out '"decision":"approve"'
    e2e_expect_out 'FLOW_GOAL_UNCHECKED'
    e2e_expect_no_out 'no active flow goal'
  fi
fi

if _want goal-status-uninspectable; then
  _flow_test_begin "/flow:goal status scan: a .flow/goals that cannot be inspected is unavailable, not none (L38)"
  if _flow_is_root; then
    _flow_assert_pass "SKIP: running as root, which permissions do not stop"
  else
    e2e_new goal-status-uninspectable
    e2e_describe "an active goal; .flow is then made unreadable (mode 000)"
    e2e_repo feature/issue-42-e2e
    e2e_goal g-link feature/issue-42-e2e active true
    chmod 000 "$E2E_REPO/.flow"
    e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/goal.md" "$GOAL_SCAN_MARK"
    chmod 755 "$E2E_REPO/.flow"
    e2e_expect_line "STATE=unavailable"
    e2e_expect_no_line "STATE=none"
  fi
fi

# --- operands that look like options (L39) ----------------------------------

FLOW_MKDIR_HELP="Create a directory in the repository"

if _want start-journal-dir-check-named; then
  _flow_test_begin "/flow:start journal block: a journal.dir named --check is a directory, not an option (L39)"
  e2e_new start-journal-dir-check-named
  e2e_describe "journal.dir is --check in .claude/settings.flow.json"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"--check"}}'
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" "$JOURNAL_INIT"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "JOURNAL_DIR=./--check"
  e2e_expect_equal yes "$([ -d "$E2E_REPO/--check" ] && [ ! -L "$E2E_REPO/--check" ] && echo yes || echo no)" "--check is a real directory"
  _expect_err_lacks "usage"
fi

if _want start-journal-dir-h-named; then
  _flow_test_begin "/flow:start journal block: a journal.dir named -h is a directory, not a request for help (L39)"
  e2e_new start-journal-dir-h-named
  e2e_describe "journal.dir is -h in .claude/settings.flow.json"
  e2e_repo feature/issue-42-e2e
  _settings '{"journal":{"dir":"-h"}}'
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" "$JOURNAL_INIT"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "JOURNAL_DIR=./-h"
  e2e_expect_no_out "$FLOW_MKDIR_HELP"
  e2e_expect_equal yes "$([ -d "$E2E_REPO/-h" ] && [ ! -L "$E2E_REPO/-h" ] && echo yes || echo no)" "-h is a real directory"
fi

if _want start-journal-user-h-link; then
  _flow_test_begin "/flow:start journal block: a journal.dir named -h that the repository commits as a symlink is refused (L39)"
  e2e_new start-journal-user-h-link
  e2e_describe "journal.dir is -h in the user's settings; -h is a symlink to an empty directory outside the repository"
  e2e_repo feature/issue-42-e2e
  _user_settings '{"journal":{"dir":"-h"}}'
  _plant -h
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/start.md" "$JOURNAL_INIT"
  _expect_refused 1 "refusing — -h is a symlink"
  e2e_expect_no_out "$FLOW_MKDIR_HELP"
fi

if _want strip-user-h-link; then
  _flow_test_begin "flow-strip-auto-log.sh (/flow:setup strip block): a journal.dir named -h that the repository commits as a symlink is not rewritten (L39)"
  e2e_new strip-user-h-link
  e2e_describe "journal.dir is -h in the user's settings; -h is moved outside the repository and replaced by a symlink to it; its journal carries one breadcrumb"
  e2e_repo feature/issue-42-e2e
  _user_settings '{"journal":{"dir":"-h"}}'
  mkdir -p "$E2E_REPO/-h"
  printf '# Journal\n\nA decision.\n\n%s\n' "$CRUMB" > "$E2E_REPO/-h/issue-42.md"
  _plant -h
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/setup.md" "$STRIP"
  _expect_refused 2 "-h is a symlink"
fi

# --- paths spelled through a symlink above the repository (L40) --------------
# $E2E_REPO is the path mktemp gave, which on macOS runs through /var, a
# symlink to /private/var, while the working directory the code sees is the
# physical one. These scenarios discriminate where the two spellings differ
# (macOS); where they do not (most Linux runners), they are the string-prefix
# case and pass either way.

if _want journal-append-user-logical-link; then
  _flow_test_begin "journal-append.sh (/flow:brainstorm decision block): a user journal.dir naming the repository through a symlink above it is still checked (L40)"
  e2e_new journal-append-user-logical-link
  e2e_describe "journal.dir in the user's settings is <repository path as mktemp spelled it>/docs/j; docs is a symlink to an empty directory outside the repository; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _user_settings "{\"journal\":{\"dir\":\"$E2E_REPO/docs/j\"}}"
  _plant docs
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" "$BRAINSTORM"
  _expect_refused 2 "refusing — docs is a symlink"
fi

if _want journal-append-file-logical-link; then
  _flow_test_begin "journal-append.sh --file: a journal named through a symlink above the repository is not written through a symlinked .decisions (L40)"
  e2e_new journal-append-file-logical-link
  e2e_describe ".decisions is a symlink to an empty directory outside the repository; journal-append.sh runs from the repository top with --file <repository path as mktemp spelled it>/.decisions/issue-42.md"
  e2e_repo feature/issue-42-e2e
  _plant .decisions
  {
    printf 'code: bin/journal-append.sh\n'
    printf 'code sha256: %s\n' "$(_e2e_sha256 "$E2E_ACTIVE_PLUGIN/bin/journal-append.sh")"
    printf 'arguments: --file <scratch>/%s/repo/.decisions/issue-42.md --text entry\n' "$E2E_NAME"
  } >> "$E2E_ARTIFACT"
  _e2e_exec "$E2E_ACTIVE_PLUGIN/bin/journal-append.sh" --file "$E2E_REPO/.decisions/issue-42.md" --text entry
  printf -- '--- expectations\n' >> "$E2E_ARTIFACT"
  _expect_refused 2 "refusing — .decisions is a symlink"
fi

if _want journal-append-local-logical-inside; then
  _flow_test_begin "journal-dir.sh (/flow:brainstorm decision block): a repository journal.dir naming the repository through a symlink above it is inside (L40)"
  e2e_new journal-append-local-logical-inside
  e2e_describe "journal.dir in .claude/settings.flow.local.json is <repository path as mktemp spelled it>/docs/decisions; no symlink under the repository; branch feature/issue-42-e2e"
  e2e_repo feature/issue-42-e2e
  _local_settings "{\"journal\":{\"dir\":\"$E2E_REPO/docs/decisions\"}}"
  e2e_run_fence "$E2E_ACTIVE_PLUGIN/commands/brainstorm.md" "$BRAINSTORM"
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_file_has "docs/decisions/issue-42.md" "$BRAINSTORM"
  _expect_err_lacks "$REPO_REFUSED"
fi
