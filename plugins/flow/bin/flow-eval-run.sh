#!/usr/bin/env bash
# flow-eval-run.sh — correctness eval for the flow plugin's testing gates.
#
# Runs headless `claude -p` sessions on the seeded-bug cases under
# plugins/flow/evals/<case>/ across configuration arms, then scores each run
# with the case's hidden unittest suite (never the agent's own tests). See
# plugins/flow/references/correctness-eval.md for what is measured and how to
# read the output.
#
# Usage:
#   flow-eval-run.sh [--mode correctness|review]
#                    [--arm <name>|all] [--case <name>|all] [--runs N]
#                    [--model <m> | --models <a,b>] [--effort <level>] [--max-turns N] [--max-budget-usd X]
#                    [--max-total-usd X] [--timeout-seconds S] [--out <dir>]
#                    [--permission-mode acceptEdits|bypassPermissions]
#                    [--dry-run] [--keep-temp] [--aggregate-only] [--check-cases]
#                    [--build-review-repo <dir> --case <name> --trap <name>]
#                    [--trap <name>]  with --mode review and one --case: plan that variant only
#
# Modes:
#   correctness  (default) the seeded-bug implementation eval described above
#   review       the review-precision eval: per case and trap, a scratch git
#                repository whose default branch holds hidden/reference_impl.py
#                as the module and whose feature branch holds the trap variant
#                as the same module, reviewed by the Path B fan-out and scored
#                against the reference->variant diff. See
#                plugins/flow/references/review-precision-eval.md.
#
# Arms (settings written to <temp>/.claude/settings.flow.json):
#   baseline        no --plugin-dir, no settings file, flow-only prompt block removed
#   enforce-risk    testing.tddMode=enforce, tddModeOptOut=false, specFirst.riskMap=true
#   enforce-norisk  testing.tddMode=enforce, tddModeOptOut=false, specFirst.riskMap=false
#   suggest-risk    testing.tddMode=suggest, tddModeOptOut=true,  specFirst.riskMap=true
#   suggest-norisk  testing.tddMode=suggest, tddModeOptOut=true,  specFirst.riskMap=false
#   off-risk        testing.tddMode=off,     tddModeOptOut=true,  specFirst.riskMap=true
#   off-norisk      testing.tddMode=off,     tddModeOptOut=true,  specFirst.riskMap=false
#
# Review-mode arms:
#   review-b        the Path B fan-out as shipped (review.groundingCritic=off)
#   review-b-critic the same with review.groundingCritic=on
#
# Defaults: --arm all, --case all, --runs 3 (or the case's prompt.md `runs`),
# --max-turns 60 (or prompt.md `max_turns`), --max-budget-usd 4 per run,
# --max-total-usd 250, --timeout-seconds 1800 (or prompt.md `timeout_seconds`),
# --out plugins/flow/evals/results/<UTC timestamp>/. --model is passed through
# only when given; otherwise the CLI default model is used. --effort is passed
# through only when given (low|medium|high|xhigh|max); otherwise the child
# inherits the operator's saved effort setting, which result.json cannot see,
# so pin it whenever runs will be compared. --models a,b runs
# the whole plan once per model, sequentially; results are keyed by model.
#
# Permissions: the child runs headless with `--permission-mode acceptEdits
# --allowedTools <prompt.md allowed_tools> --permission-prompts none` (verified
# to work as root, where the CLI refuses --dangerously-skip-permissions).
# --permission-mode bypassPermissions adds --dangerously-skip-permissions and
# drops --allowedTools; it only works for non-root users. Tools outside the
# grant are denied, and every denial is recorded in result.json
# (`permission_denials`).
#
# Resumable: a run whose result.json already exists under --out is skipped, so
# re-running with the same --out continues where an aborted run stopped and
# re-aggregates. The running cost total (sum of cost_usd over every completed
# run in --out) is checked before each run: when total + --max-budget-usd would
# exceed --max-total-usd the runner stops with exit 3 and still aggregates.
#
# Output layout under --out (<model> is the --model/--models value with "/"
# replaced by "_", or "default" when none was given; result.json records the
# model actually billed, from the claude result event's modelUsage keys):
# Review mode adds the trap to the path and replaces the hidden-suite records:
#   runs/<model>/<arm>/<case>/<trap>/<n>/result.json      per-run record (mode=review)
#   runs/<model>/<arm>/<case>/<trap>/<n>/review-score.json hit / false findings / reason
#   runs/<model>/<arm>/<case>/<trap>/<n>/findings.txt      the session's final message
#   runs/<model>/<arm>/<case>/<trap>/<n>/repo/             the scratch repository (--keep-temp)
#
# Correctness output layout under --out:
#   runs/<model>/<arm>/<case>/<n>/result.json    composite per-run record
#   runs/<model>/<arm>/<case>/<n>/claude.json    the claude result event (cost, turns, session_id)
#   runs/<model>/<arm>/<case>/<n>/stream.jsonl   full stream-json transcript of the run
#   runs/<model>/<arm>/<case>/<n>/hidden.txt     raw hidden-suite output
#   runs/<model>/<arm>/<case>/<n>/own-test-traps.json  the agent's own suite vs each trap variant
#   runs/<model>/<arm>/<case>/<n>/project/       snapshot of the agent's module and tests
#   runs/<model>/<arm>/<case>/<n>/agent-tests-summary.json
#   runs/<model>/<arm>/<case>/<n>/settings.json  the arm's settings.flow.json (plugin arms)
#   runs/<model>/<arm>/<case>/<n>/prompt.txt, command.txt
#   summary.json, summary.md
# Results written by earlier versions under runs/<arm>/<case>/<n>/ are still
# read by --aggregate-only; move them into the model layout once with
#   python3 plugins/flow/bin/_flow_eval.py migrate-layout --out <dir>
#
# Child-session hygiene: the parent Claude Code session exports CLAUDE* variables
# that would make the nested `claude` believe it is a sub-session of this one.
# The runner unsets the ones in STRIP_ENV below (session identity, messaging
# sockets, transcript sync, subagent depth, additional directories) and sets a
# per-run FLOW_STATE_DIR so flow hooks never share ledgers across runs. It does
# not touch credentials, proxy or provider variables.
#
# Exit codes: 0 all planned runs completed; 1 usage error; 2 prerequisite
# missing or case check failed; 3 stopped by --max-total-usd; 4 at least one
# run errored (claude non-zero, timeout, no result event).
#
# Requires: bash, python3, git, claude and GNU timeout (on PATH). jq is not
# needed. macOS has no timeout of its own: `brew install coreutils` and put
# /opt/homebrew/opt/coreutils/libexec/gnubin on PATH, or the runner refuses
# to start.

set -uo pipefail
export PYTHONSAFEPATH=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVALS_DIR="$PLUGIN_ROOT/evals"
HELPER="$SCRIPT_DIR/_flow_eval.py"
CORRECTNESS_ARMS="baseline enforce-risk enforce-norisk suggest-risk suggest-norisk off-risk off-norisk"
REVIEW_ARMS="review-b review-b-critic"
ALL_ARMS="$CORRECTNESS_ARMS"

STRIP_ENV=(
  CLAUDECODE CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_ENTRYPOINT
  CLAUDE_CODE_CHILD_SESSION CLAUDE_PID CLAUDE_CODE_REMOTE_SESSION_ID
  CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN
  CLAUDE_CODE_DIAGNOSTICS_FILE CLAUDE_CODE_TEE_SDK_STDOUT
  CLAUDE_AFTER_LAST_COMPACT CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH
  CLAUDE_CODE_SYNC_SESSION_REFS CLAUDE_SESSION_INGRESS_TOKEN_FILE
  CLAUDE_CODE_POST_FOR_SESSION_INGRESS_V2 CLAUDE_ADDITIONAL_DIRECTORIES
  CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD CLAUDE_AUTOCOMPACT_PCT_OVERRIDE
  CLAUDE_EFFORT CLAUDE_AUTO_BACKGROUND_TASKS CLAUDE_CODE_HOLD_UNANSWERED_PARKED_PERMISSION
  FLOW_STATE_DIR
  # This runner exports PYTHONSAFEPATH=1 for its own helper calls; inherited by
  # the child it makes `python3 -m unittest tests.x` fail to import from the
  # project root, which every arm then has to debug (seen on the first full
  # run). The child gets a clean Python environment.
  PYTHONSAFEPATH
)

MODE="correctness"
ARM_FILTER="all"
CASE_FILTER="all"
RUNS=""
MODEL=""
MODELS_LIST=""
MODELS_GIVEN=0
EFFORT=""
MAX_TURNS=""
MAX_BUDGET="4"
MAX_TOTAL="250"
TIMEOUT_SECONDS=""
OUT_DIR=""
PERMISSION_MODE="acceptEdits"
DEFAULT_ALLOWED_TOOLS="Bash,Read,Write,Edit,Glob,Grep,Skill,Agent,TodoWrite,TaskCreate,TaskList,TaskUpdate,TaskGet"
# Review runs dispatch the reviewer agents and read the diff; they do not edit
# the repository, so Write and Edit stay out of the grant and any attempt to
# use them is recorded as a permission denial in result.json.
REVIEW_ALLOWED_TOOLS="Bash,Read,Glob,Grep,Skill,Agent,TodoWrite,TaskCreate,TaskList,TaskUpdate,TaskGet"
DRY_RUN=0
KEEP_TEMP=0
AGGREGATE_ONLY=0
CHECK_CASES=0
BUILD_REPO_DIR=""
TRAP_NAME=""

usage() {
  # Print the whole header comment, however long it grows — a fixed line
  # window silently truncates --help the next time a flag is documented.
  sed -n '2,$p' "$0" | sed -n '/^[^#]/q;p' | sed 's/^# \{0,1\}//'
}

need_value() {
  # An empty value is refused like a missing one: every guard downstream tests
  # a value with -n, so "" would pass as "not given" and be ignored.
  [ $# -ge 2 ] && [ -n "${2:-}" ] || { echo "flow-eval-run: $1 requires a non-empty value" >&2; exit 1; }
}

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) need_value "$@"; MODE="$2"; shift 2 ;;
    --arm) need_value "$@"; ARM_FILTER="$2"; shift 2 ;;
    --case) need_value "$@"; CASE_FILTER="$2"; shift 2 ;;
    --runs) need_value "$@"; RUNS="$2"; shift 2 ;;
    --model) need_value "$@"; MODEL="$2"; shift 2 ;;
    --models) need_value "$@"; MODELS_LIST="$2"; MODELS_GIVEN=1; shift 2 ;;
    --effort) need_value "$@"; EFFORT="$2"; shift 2 ;;
    --max-turns) need_value "$@"; MAX_TURNS="$2"; shift 2 ;;
    --max-budget-usd) need_value "$@"; MAX_BUDGET="$2"; shift 2 ;;
    --max-total-usd) need_value "$@"; MAX_TOTAL="$2"; shift 2 ;;
    --timeout-seconds) need_value "$@"; TIMEOUT_SECONDS="$2"; shift 2 ;;
    --out) need_value "$@"; OUT_DIR="$2"; shift 2 ;;
    --permission-mode) need_value "$@"; PERMISSION_MODE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --keep-temp) KEEP_TEMP=1; shift ;;
    --aggregate-only) AGGREGATE_ONLY=1; shift ;;
    --check-cases) CHECK_CASES=1; shift ;;
    --trap) need_value "$@"; TRAP_NAME="$2"; shift 2 ;;
    --build-review-repo) need_value "$@"; BUILD_REPO_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "flow-eval-run: unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

case "$MODE" in
  correctness) ALL_ARMS="$CORRECTNESS_ARMS" ;;
  review)      ALL_ARMS="$REVIEW_ARMS" ;;
  *) echo "flow-eval-run: --mode must be correctness or review, got '$MODE'" >&2; exit 1 ;;
esac

if [ -n "$MODEL" ] && [ "$MODELS_GIVEN" = "1" ]; then
  echo "flow-eval-run: use either --model or --models, not both" >&2; exit 1
fi
# MODELS holds one entry per model to run; the empty string means "CLI default".
MODELS=()
if [ "$MODELS_GIVEN" = "1" ]; then
  IFS=',' read -r -a REQUESTED_MODELS <<<"$MODELS_LIST"
  for m in "${REQUESTED_MODELS[@]}"; do
    m="${m// /}"
    [ -n "$m" ] && MODELS+=("$m")
  done
  [ "${#MODELS[@]}" -gt 0 ] || { echo "flow-eval-run: --models needs at least one model name" >&2; exit 1; }
else
  MODELS=("$MODEL")
fi
case "$EFFORT" in
  ''|low|medium|high|xhigh|max) ;;
  *) echo "flow-eval-run: --effort must be one of low, medium, high, xhigh, max; got '$EFFORT'" >&2; exit 1 ;;
esac
for n in "$MAX_BUDGET" "$MAX_TOTAL"; do
  [[ "$n" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "flow-eval-run: budget values must be numbers, got '$n'" >&2; exit 1; }
done
for n in "$RUNS" "$MAX_TURNS" "$TIMEOUT_SECONDS"; do
  [ -z "$n" ] || [[ "$n" =~ ^[0-9]+$ ]] || { echo "flow-eval-run: --runs/--max-turns/--timeout-seconds must be integers, got '$n'" >&2; exit 1; }
done
case "$PERMISSION_MODE" in
  acceptEdits|bypassPermissions) ;;
  *) echo "flow-eval-run: --permission-mode must be acceptEdits or bypassPermissions" >&2; exit 1 ;;
esac
if [ "$PERMISSION_MODE" = "bypassPermissions" ] && [ "$(id -u 2>/dev/null)" = "0" ]; then
  echo "flow-eval-run: bypassPermissions cannot be used as root (the CLI refuses --dangerously-skip-permissions); use acceptEdits" >&2
  exit 1
fi

command -v python3 >/dev/null 2>&1 || { echo "flow-eval-run: python3 is required" >&2; exit 2; }
[ -f "$HELPER" ] || { echo "flow-eval-run: missing helper $HELPER" >&2; exit 2; }

# --trap narrows a review plan (or names the variant --build-review-repo builds).
# Anywhere else it would be accepted and ignored, and an ignored narrowing
# flag is a wider spend than the one that was asked for.
if [ -n "$TRAP_NAME" ] && { [ "$CHECK_CASES" = "1" ] || [ "$AGGREGATE_ONLY" = "1" ]; }; then
  echo "flow-eval-run: --trap does not apply to --check-cases or --aggregate-only" >&2
  exit 1
fi

if [ "$CHECK_CASES" = "1" ]; then
  CHECK_ARGS=(check-cases --evals-dir "$EVALS_DIR" --mode "$MODE")
  [ "$CASE_FILTER" = "all" ] || CHECK_ARGS+=(--case "$CASE_FILTER")
  python3 "$HELPER" "${CHECK_ARGS[@]}"
  exit $?
fi

# --- resolve arms and cases -------------------------------------------------
if [ "$ARM_FILTER" = "all" ]; then
  ARMS="$ALL_ARMS"
else
  ARMS=""
  IFS=',' read -r -a REQUESTED <<<"$ARM_FILTER"
  for a in "${REQUESTED[@]}"; do
    case " $ALL_ARMS " in
      *" $a "*) ARMS="$ARMS $a" ;;
      *) echo "flow-eval-run: unknown arm '$a' (valid: $ALL_ARMS)" >&2; exit 1 ;;
    esac
  done
fi

CASES=""
if [ "$CASE_FILTER" = "all" ]; then
  for d in "$EVALS_DIR"/*/; do
    [ -f "$d/prompt.md" ] && CASES="$CASES $(basename "$d")"
  done
else
  IFS=',' read -r -a REQUESTED <<<"$CASE_FILTER"
  for c in "${REQUESTED[@]}"; do
    [ -f "$EVALS_DIR/$c/prompt.md" ] || { echo "flow-eval-run: no such case '$c' under $EVALS_DIR" >&2; exit 1; }
    CASES="$CASES $c"
  done
fi
[ -n "$CASES" ] || { echo "flow-eval-run: no cases found under $EVALS_DIR" >&2; exit 2; }

# --build-review-repo validates its own arguments further down.
if [ -n "$TRAP_NAME" ] && [ -z "$BUILD_REPO_DIR" ]; then
  if [ "$MODE" != "review" ]; then
    echo "flow-eval-run: --trap applies only to --mode review" >&2; exit 1
  fi
  if [ "$CASE_FILTER" = "all" ] || [ "${CASE_FILTER#*,}" != "$CASE_FILTER" ]; then
    echo "flow-eval-run: --trap needs exactly one --case, because trap names belong to a case" >&2; exit 1
  fi
  python3 "$HELPER" list-traps "$EVALS_DIR/$CASE_FILTER" | grep -Fxq -- "$TRAP_NAME" || {
    echo "flow-eval-run: case '$CASE_FILTER' has no trap '$TRAP_NAME' (list them with: python3 $HELPER list-traps $EVALS_DIR/$CASE_FILTER)" >&2
    exit 1
  }
fi

if [ -z "$OUT_DIR" ]; then
  OUT_DIR="$EVALS_DIR/results/$(date -u +%Y%m%dT%H%M%SZ)"
fi

if [ "$AGGREGATE_ONLY" = "1" ]; then
  python3 "$HELPER" aggregate --out "$OUT_DIR" --mode "$MODE" || exit 2
  echo "flow-eval-run: wrote $OUT_DIR/summary.md"
  exit 0
fi

# --build-review-repo makes no model call, so it needs git and python3 and
# nothing else. Requiring the model runner here failed on every machine that
# has none - which is every CI runner, and CI is where this path is tested.
if [ -n "$BUILD_REPO_DIR" ]; then
  command -v git >/dev/null 2>&1 || { echo "flow-eval-run: git is required" >&2; exit 2; }
elif [ "$DRY_RUN" != "1" ]; then
  for tool in claude git timeout; do
    command -v "$tool" >/dev/null 2>&1 || { echo "flow-eval-run: $tool is required" >&2; exit 2; }
  done
  # Fail the whole plan here rather than one run at a time: an unknown flag
  # kills every child session identically, and each failure costs a full
  # timeout before it is recorded as "no result event". The help text is
  # captured rather than piped so a claude that fails (unauthenticated, say)
  # is reported as itself instead of as a missing flag.
  if [ -n "$EFFORT" ]; then
    CLAUDE_HELP=$(timeout 30 claude --help 2>&1); HELP_RC=$?
    if [ "$HELP_RC" != "0" ]; then
      echo "flow-eval-run: 'claude --help' failed (exit $HELP_RC) — cannot confirm --effort is supported:" >&2
      printf '%s\n' "$CLAUDE_HELP" | head -5 >&2
      exit 2
    fi
    case "$CLAUDE_HELP" in
      *--effort*) ;;
      *) echo "flow-eval-run: this Claude Code CLI has no --effort flag; drop --effort or upgrade the CLI" >&2; exit 2 ;;
    esac
  fi
fi

# --- helpers -----------------------------------------------------------------
arm_settings() {
  # Prints the settings.flow.json body for a plugin arm (nothing for baseline).
  case "$1" in
    baseline) return 0 ;;
    review-b)        printf '{"review":{"groundingCritic":"off"}}\n' ;;
    review-b-critic) printf '{"review":{"groundingCritic":"on"}}\n' ;;
    enforce-risk)   printf '{"testing":{"tddMode":"enforce","tddModeOptOut":false},"specFirst":{"riskMap":true}}\n' ;;
    enforce-norisk) printf '{"testing":{"tddMode":"enforce","tddModeOptOut":false},"specFirst":{"riskMap":false}}\n' ;;
    suggest-risk)   printf '{"testing":{"tddMode":"suggest","tddModeOptOut":true},"specFirst":{"riskMap":true}}\n' ;;
    suggest-norisk) printf '{"testing":{"tddMode":"suggest","tddModeOptOut":true},"specFirst":{"riskMap":false}}\n' ;;
    off-risk)       printf '{"testing":{"tddMode":"off","tddModeOptOut":true},"specFirst":{"riskMap":true}}\n' ;;
    off-norisk)     printf '{"testing":{"tddMode":"off","tddModeOptOut":true},"specFirst":{"riskMap":false}}\n' ;;
    *) return 1 ;;
  esac
}

case_meta() {
  # case_meta <case> <key> — value from prompt.md frontmatter or empty
  python3 "$HELPER" case-meta "$EVALS_DIR/$1" | sed -n "s/^$2=//p" | head -1
}

case_module() {
  # case_module <case> — the module name the hidden suite imports
  python3 - "$EVALS_DIR/$1/hidden/traps.json" <<'EOF'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    print(json.load(fh)["module"])
EOF
}

case_traps() {
  # case_traps <case> — trap names, one per line. bash 3.2 has no associative
  # arrays, so the list comes from the helper rather than from the shell.
  # --trap narrows it to one name; the plan, the resume check and the dry-run
  # count all read the list from here, so they narrow together. The name was
  # checked against this case above, so the filter cannot come back empty.
  if [ -n "$TRAP_NAME" ]; then
    python3 "$HELPER" list-traps "$EVALS_DIR/$1" | grep -Fx -- "$TRAP_NAME"
  else
    python3 "$HELPER" list-traps "$EVALS_DIR/$1"
  fi
}

BASE_BRANCH="main"
HEAD_BRANCH="review-candidate"

build_review_repo() {
  # build_review_repo <dir> <case> <trap> — a git repository whose default
  # branch holds the reference implementation as the module and whose feature
  # branch holds the materialized trap variant as the same module, so the
  # branch diff is the module file alone.
  #
  # reference_impl.py is committed on both branches ONLY when this variant
  # still calls into it. Giving it to a variant that does not need it hands the
  # reviewer a pristine correct copy of the module under review, which locates
  # the defect by diff alone. When it is needed it is written through
  # `reference-module`, the same stripped text the module gets: the shipped
  # file opens by naming the hidden suite and the trap variants, which tells
  # the reviewer it is being tested and where to look.
  local dir="$1" case="$2" trap="$3" module delegates
  module="$(case_module "$case")" || return 1
  local case_dir="$EVALS_DIR/$case"
  mkdir -p "$dir" || return 1
  # Building on top of an existing repository fails halfway through with a bare
  # "a branch named main already exists" and leaves the tree inconsistent.
  if [ -e "$dir/.git" ]; then
    printf 'flow-eval-run: %s already holds a git repository; refusing to build over it\n' "$dir" >&2
    return 1
  fi
  delegates="$(python3 "$HELPER" variant-delegates --case "$case_dir" --trap "$trap")" || return 1
  if [ "$delegates" = "yes" ]; then
    python3 "$HELPER" reference-module --case "$case_dir" --out "$dir/reference_impl.py" || return 1
  else
    rm -f "$dir/reference_impl.py" || return 1
  fi
  python3 "$HELPER" reference-module --case "$case_dir" --out "$dir/$module.py" || return 1
  (
    cd "$dir" || exit 1
    # `git init -b` needs git >= 2.28; correctness mode uses plain `git init`,
    # and the default branch is named here instead so both modes share a floor.
    git init -q . || exit 1
    git checkout -q -b "$BASE_BRANCH" 2>/dev/null || git branch -q -m "$BASE_BRANCH" || exit 1
    # Only the files this function wrote. `git add -A` also committed the
    # arm's .claude/settings.flow.json, which run_one_review writes into this
    # same directory before calling here: the repository handed to the
    # reviewer then carried the harness's own configuration in its history.
    git add -- "$module.py" || exit 1
    if [ "$delegates" = "yes" ]; then git add -- reference_impl.py || exit 1; fi
    git -c user.name=flow-eval -c user.email=flow-eval@localhost commit -q -m "$module: initial implementation" || exit 1
    git checkout -q -b "$HEAD_BRANCH" || exit 1
    python3 "$HELPER" materialize-variant --case "$case_dir" --trap "$trap" --out "$module.py" || exit 1
    git add -- "$module.py" || exit 1
    git -c user.name=flow-eval -c user.email=flow-eval@localhost commit -q -m "$module: rework the implementation" || exit 1
  ) || return 1
  return 0
}

# Every review case's trap list and module name are read once, here, before
# anything is planned. The plan reads them again inside $(...), where a
# traps.json that does not parse yields an empty list: the case would drop out
# of the plan silently and the run would spend on, and report, what was left.
if [ "$MODE" = "review" ] && [ "$AGGREGATE_ONLY" != "1" ] && [ -z "$BUILD_REPO_DIR" ]; then
  for c in $CASES; do
    c_traps=$(python3 "$HELPER" list-traps "$EVALS_DIR/$c") && [ -n "$c_traps" ] || {
      echo "flow-eval-run: cannot read the trap variants of case '$c' from $EVALS_DIR/$c/hidden/traps.json; refusing to plan without them" >&2
      exit 2
    }
    case_module "$c" >/dev/null || {
      echo "flow-eval-run: cannot read the module name of case '$c' from $EVALS_DIR/$c/hidden/traps.json; refusing to plan without it" >&2
      exit 2
    }
  done
fi

# --build-review-repo builds one review-mode scratch repository and stops, so
# what the reviewer is actually handed can be inspected — and tested — without
# a claude call.
if [ -n "$BUILD_REPO_DIR" ]; then
  if [ "$MODE" != "review" ] || [ "$CASE_FILTER" = "all" ] || [ -z "$TRAP_NAME" ] \
     || [ "${CASE_FILTER#*,}" != "$CASE_FILTER" ]; then
    echo "flow-eval-run: --build-review-repo needs --mode review --case <one name> --trap <name>" >&2
    exit 1
  fi
  # The directory is the operator's: build only into a new or empty one. The
  # builder deletes and overwrites files by name and runs git init, so any
  # other directory would lose whatever it held. The runner's own calls pass a
  # fresh temp directory and never come through here.
  # .claude/ and .flow-state/ are what the runner itself puts beside the repo
  # before building it, so they do not count; a .git is refused by the builder
  # with its own message.
  if [ -d "$BUILD_REPO_DIR" ] && [ ! -e "$BUILD_REPO_DIR/.git" ] \
     && [ -n "$(ls -A "$BUILD_REPO_DIR" 2>/dev/null | grep -vxE '\.claude|\.flow-state')" ]; then
    echo "flow-eval-run: $BUILD_REPO_DIR is not empty; refusing to build over it (pass a new or empty directory)" >&2
    exit 1
  fi
  build_review_repo "$BUILD_REPO_DIR" "$CASE_FILTER" "$TRAP_NAME" || exit 1
  echo "flow-eval-run: built $CASE_FILTER/$TRAP_NAME in $BUILD_REPO_DIR"
  exit 0
fi

running_total() {
  python3 - "$OUT_DIR" <<'EOF'
import json, os, sys
root = os.path.join(sys.argv[1], "runs")
total = 0.0
for dirpath, _, names in os.walk(root) if os.path.isdir(root) else []:
    if "result.json" in names:
        try:
            with open(os.path.join(dirpath, "result.json")) as fh:
                total += float(json.load(fh).get("cost_usd") or 0)
        except (ValueError, OSError):
            pass
print("%.4f" % total)
EOF
}

recorded_effort() {
  # recorded_effort <result.json> — the run's effort_requested; empty when the
  # run was not pinned, __unreadable__ when the record cannot be parsed (so a
  # corrupt record is never reported as an effort mismatch).
  python3 - "$1" <<'EOF'
import json, sys
try:
    with open(sys.argv[1]) as fh:
        print(json.load(fh).get("effort_requested") or "")
except Exception:
    print("__unreadable__")
EOF
}

check_resume_effort() {
  # Every planned run that already has a result.json must carry the effort this
  # plan asks for. Checked once, before anything executes: discovering a
  # mismatch mid-plan would mean runs already paid for against a matrix that
  # cannot be aggregated. Reports every mismatch, not just the first.
  local bad=0 model label case arm n run_dir recorded case_runs cells cell
  for model in "${MODELS[@]}"; do
    label="$(model_label "$model")"
    for case in $CASES; do
      case_runs="${RUNS:-$(case_meta "$case" runs)}"; case_runs="${case_runs:-3}"
      cells="."
      [ "$MODE" = "review" ] && cells="$(case_traps "$case")"
      for arm in $ARMS; do
       for cell in $cells; do
        n=1
        while [ "$n" -le "$case_runs" ]; do
          run_dir="$OUT_DIR/runs/$label/$arm/$case/$n"
          [ "$MODE" = "review" ] && run_dir="$OUT_DIR/runs/$label/$arm/$case/$cell/$n"
          if [ -f "$run_dir/result.json" ]; then
            recorded=$(recorded_effort "$run_dir/result.json")
            if [ "$recorded" = "__unreadable__" ]; then
              echo "flow-eval-run: $label/$arm/$case/$n has an unreadable result.json ($run_dir/result.json) — delete that run directory or use a fresh --out" >&2
              bad=$((bad + 1))
            elif [ "$recorded" != "$EFFORT" ]; then
              echo "flow-eval-run: $label/$arm/$case/$n was recorded at effort '${recorded:-unpinned}' but this plan asks for '${EFFORT:-unpinned}'" >&2
              bad=$((bad + 1))
            fi
          fi
          n=$((n + 1))
        done
       done
      done
    done
  done
  if [ "$bad" != "0" ]; then
    echo "flow-eval-run: refusing to resume — $bad recorded run(s) do not match --effort '${EFFORT:-unpinned}'; resume with the same --effort, or use a fresh --out" >&2
    exit 1
  fi
}

would_exceed() {
  # would_exceed <total> <per-run> <cap> -> exit 0 when total + per-run > cap
  python3 - "$1" "$2" "$3" <<'EOF'
import sys
total, per_run, cap = (float(x) for x in sys.argv[1:4])
sys.exit(0 if total + per_run > cap else 1)
EOF
}

build_command() {
  # Sets CLAUDE_CMD (array) for the current run. The prompt arrives on stdin
  # (run_one redirects prompt.txt); here only flags.
  CLAUDE_CMD=(claude -p --output-format stream-json --verbose
    --max-turns "$run_max_turns" --max-budget-usd "$MAX_BUDGET" --permission-prompts none)
  if [ "$PERMISSION_MODE" = "bypassPermissions" ]; then
    CLAUDE_CMD+=(--permission-mode bypassPermissions --dangerously-skip-permissions)
  else
    CLAUDE_CMD+=(--permission-mode acceptEdits --allowedTools "$run_allowed_tools")
  fi
  [ -n "$run_model" ] && CLAUDE_CMD+=(--model "$run_model")
  [ -n "$EFFORT" ] && CLAUDE_CMD+=(--effort "$EFFORT")
  [ "$arm" != "baseline" ] && CLAUDE_CMD+=(--plugin-dir "$PLUGIN_ROOT")
  return 0
}

RUN_ERRORS=0
BUDGET_STOP=0
PLANNED=0
EXECUTED=0
SKIPPED=0

model_label() {
  # model_label <model> — directory name for a model ("default" when empty)
  local m="${1:-default}"
  printf '%s' "${m//\//_}"
}

run_one() {
  local model="$1" arm="$2" case="$3" n="$4"
  local label run_dir
  label="$(model_label "$model")"
  run_dir="$OUT_DIR/runs/$label/$arm/$case/$n"
  local case_dir="$EVALS_DIR/$case"
  local run_max_turns run_model run_timeout run_allowed_tools
  run_max_turns="${MAX_TURNS:-$(case_meta "$case" max_turns)}"; run_max_turns="${run_max_turns:-60}"
  # prompt.md allowed_tools is a JSON list; the CLI wants a comma-separated string.
  run_allowed_tools="$(case_meta "$case" allowed_tools | tr -d '[]" ' )"; run_allowed_tools="${run_allowed_tools:-$DEFAULT_ALLOWED_TOOLS}"
  run_timeout="${TIMEOUT_SECONDS:-$(case_meta "$case" timeout_seconds)}"; run_timeout="${run_timeout:-1800}"
  run_model="${model:-$(case_meta "$case" model)}"
  build_command

  PLANNED=$((PLANNED + 1))
  if [ -f "$run_dir/result.json" ]; then
    # Effort comparability is enforced by check_resume_effort before the plan
    # starts, so by here an existing record is known to match.
    SKIPPED=$((SKIPPED + 1))
    [ "$DRY_RUN" = "1" ] && echo "SKIP  $label/$arm/$case/$n (result.json exists)"
    return 0
  fi

  if [ "$DRY_RUN" = "1" ]; then
    local plugin_note="(no plugin)"
    [ "$arm" != "baseline" ] && plugin_note="settings=$(arm_settings "$arm")"
    echo "RUN   $label/$arm/$case/$n  model=${run_model:-<cli default>}  effort=${EFFORT:-<cli default>}  timeout=${run_timeout}s  $plugin_note"
    local unset_list=""
    for v in "${STRIP_ENV[@]}"; do unset_list="$unset_list -u $v"; done
    printf '      cd <temp copy of %s> && env%s FLOW_STATE_DIR=<temp>/.flow-state timeout %s %s < prompt.txt > %s/stream.jsonl\n' \
      "evals/$case/scaffold" "$unset_list" "$run_timeout" "${CLAUDE_CMD[*]}" "runs/$label/$arm/$case/$n"
    return 0
  fi

  local total
  total=$(running_total)
  if would_exceed "$total" "$MAX_BUDGET" "$MAX_TOTAL"; then
    echo "flow-eval-run: stopping before $label/$arm/$case/$n — running total \$$total + per-run cap \$$MAX_BUDGET would exceed --max-total-usd \$$MAX_TOTAL" >&2
    BUDGET_STOP=1
    return 1
  fi

  mkdir -p "$run_dir"
  local tmp
  tmp=$(mktemp -d -t flow-eval.XXXXXX) || { echo "flow-eval-run: mktemp failed" >&2; RUN_ERRORS=$((RUN_ERRORS + 1)); return 1; }
  cp -R "$case_dir/scaffold/." "$tmp/"
  mkdir -p "$tmp/.claude" "$tmp/.flow-state"
  if [ "$arm" != "baseline" ]; then
    arm_settings "$arm" > "$tmp/.claude/settings.flow.json"
    cp "$tmp/.claude/settings.flow.json" "$run_dir/settings.json"
  fi
  ( cd "$tmp" && git init -q && git add -A && git -c user.name=flow-eval -c user.email=flow-eval@localhost commit -q -m "scaffold" ) \
    || { echo "flow-eval-run: git init failed in $tmp" >&2; rm -rf "$tmp"; RUN_ERRORS=$((RUN_ERRORS + 1)); return 1; }
  # An unwritten prompt is an error, never an empty prompt handed to a paid run.
  if ! python3 "$HELPER" case-prompt "$case_dir" --arm "$arm" > "$run_dir/prompt.txt" \
     || [ ! -s "$run_dir/prompt.txt" ]; then
    printf 'flow-eval-run: could not write the case prompt for %s; the run was not started\n' "$case" >&2
    rm -rf "$tmp"
    RUN_ERRORS=$((RUN_ERRORS + 1))
    return 1
  fi
  # %q, not a space-join: command.txt is the operator's record of what ran, and
  # a space-joined line re-executes as a different command when pasted back.
  { printf '%q ' "${CLAUDE_CMD[@]}"; printf '\n'; } > "$run_dir/command.txt"

  echo "flow-eval-run: [$label/$arm/$case/$n] starting (model ${run_model:-<cli default>}; effort ${EFFORT:-<cli default>}; total so far \$$total; max-turns $run_max_turns; timeout ${run_timeout}s)"
  local start end exit_code timed_out=0
  start=$(date +%s)
  local unset_args=()
  for v in "${STRIP_ENV[@]}"; do unset_args+=(-u "$v"); done
  ( cd "$tmp" && env "${unset_args[@]}" FLOW_STATE_DIR="$tmp/.flow-state" \
      timeout --kill-after=30 "$run_timeout" "${CLAUDE_CMD[@]}" < "$run_dir/prompt.txt" \
      > "$run_dir/stream.jsonl" 2> "$run_dir/stderr.log" )
  exit_code=$?
  end=$(date +%s)
  [ "$exit_code" = "124" ] || [ "$exit_code" = "137" ] && timed_out=1

  local finalize_args=(finalize-run --run-dir "$run_dir" --case-dir "$case_dir" --project-dir "$tmp"
    --arm "$arm" --case "$case" --run "$n" --exit-code "$exit_code" --duration "$((end - start))")
  [ -n "$run_model" ] && finalize_args+=(--model-requested "$run_model")
  [ -n "$EFFORT" ] && finalize_args+=(--effort-requested "$EFFORT")
  [ "$timed_out" = "1" ] && finalize_args+=(--timed-out)
  [ "$KEEP_TEMP" = "1" ] && finalize_args+=(--temp-dir "$tmp")
  local grade
  grade=$(python3 "$HELPER" "${finalize_args[@]}") || { echo "flow-eval-run: grading failed for $label/$arm/$case/$n" >&2; RUN_ERRORS=$((RUN_ERRORS + 1)); }
  echo "flow-eval-run: [$label/$arm/$case/$n] done exit=$exit_code $grade"
  EXECUTED=$((EXECUTED + 1))
  if grep -q '"error": "' "$run_dir/result.json" 2>/dev/null && ! grep -q '"error": null' "$run_dir/result.json"; then
    RUN_ERRORS=$((RUN_ERRORS + 1))
  fi
  if [ "$KEEP_TEMP" = "1" ]; then
    echo "flow-eval-run: kept $tmp"
  else
    rm -rf "$tmp"
  fi
  return 0
}

run_one_review() {
  local model="$1" arm="$2" case="$3" trap="$4" n="$5"
  local label run_dir case_dir module
  label="$(model_label "$model")"
  run_dir="$OUT_DIR/runs/$label/$arm/$case/$trap/$n"
  case_dir="$EVALS_DIR/$case"
  module="$(case_module "$case")" || { printf 'flow-eval-run: cannot read the module name of case %s\n' "$case" >&2; RUN_ERRORS=$((RUN_ERRORS + 1)); return 1; }
  local run_max_turns run_model run_timeout run_allowed_tools
  run_max_turns="${MAX_TURNS:-$(case_meta "$case" max_turns)}"; run_max_turns="${run_max_turns:-60}"
  run_allowed_tools="$REVIEW_ALLOWED_TOOLS"
  run_timeout="${TIMEOUT_SECONDS:-$(case_meta "$case" timeout_seconds)}"; run_timeout="${run_timeout:-1800}"
  run_model="${model:-$(case_meta "$case" model)}"
  build_command

  PLANNED=$((PLANNED + 1))
  if [ -f "$run_dir/result.json" ]; then
    SKIPPED=$((SKIPPED + 1))
    [ "$DRY_RUN" = "1" ] && printf 'SKIP  %s (result.json exists)\n' "$label/$arm/$case/$trap/$n"
    return 0
  fi

  if [ "$DRY_RUN" = "1" ]; then
    printf 'RUN   %s  model=%s  effort=%s  timeout=%ss  settings=%s\n' \
      "$label/$arm/$case/$trap/$n" "${run_model:-<cli default>}" "${EFFORT:-<cli default>}" "$run_timeout" "$(arm_settings "$arm")"
    local plan_ref=""
    if [ "$(python3 "$HELPER" variant-delegates --case "$EVALS_DIR/$case" --trap "$trap" 2>/dev/null)" = "yes" ]; then
      plan_ref="; reference_impl.py <- the same stripped text, because this variant still calls into it"
    fi
    printf '      repo <scratch>: git init; git checkout -b %s; %s.py <- evals/%s/hidden/reference_impl.py (module docstring stripped)%s\n' \
      "$BASE_BRANCH" "$module" "$case" "$plan_ref"
    printf '      repo <scratch>: git checkout -b %s; %s.py <- evals/%s/hidden/traps/%s.py materialized into the reference source (the branch diff is %s.py alone)\n' \
      "$HEAD_BRANCH" "$module" "$case" "$trap" "$module"
    local unset_list=""
    for v in "${STRIP_ENV[@]}"; do unset_list="$unset_list -u $v"; done
    printf '      cd <scratch repo> && env%s FLOW_STATE_DIR=<temp>/.flow-state timeout %s %s < prompt.txt > %s/stream.jsonl\n' \
      "$unset_list" "$run_timeout" "${CLAUDE_CMD[*]}" "runs/$label/$arm/$case/$trap/$n"
    return 0
  fi

  local total
  total=$(running_total)
  if would_exceed "$total" "$MAX_BUDGET" "$MAX_TOTAL"; then
    printf 'flow-eval-run: stopping before %s — running total $%s + per-run cap $%s would exceed --max-total-usd $%s\n' \
      "$label/$arm/$case/$trap/$n" "$total" "$MAX_BUDGET" "$MAX_TOTAL" >&2
    BUDGET_STOP=1
    return 1
  fi

  mkdir -p "$run_dir"
  local tmp
  tmp=$(mktemp -d -t flow-eval-review.XXXXXX) || { printf 'flow-eval-run: mktemp failed\n' >&2; RUN_ERRORS=$((RUN_ERRORS + 1)); return 1; }
  mkdir -p "$tmp/.claude" "$tmp/.flow-state"
  arm_settings "$arm" > "$tmp/.claude/settings.flow.json"
  cp "$tmp/.claude/settings.flow.json" "$run_dir/settings.json"
  if ! build_review_repo "$tmp" "$case" "$trap"; then
    printf 'flow-eval-run: could not build the scratch repository in %s\n' "$tmp" >&2
    rm -rf "$tmp"
    RUN_ERRORS=$((RUN_ERRORS + 1))
    return 1
  fi
  # An unwritten prompt is an error, never an empty prompt handed to a paid run.
  if ! python3 "$HELPER" review-prompt "$case_dir" --base-branch "$BASE_BRANCH" --head-branch "$HEAD_BRANCH" > "$run_dir/prompt.txt" \
     || [ ! -s "$run_dir/prompt.txt" ]; then
    printf 'flow-eval-run: could not write the review prompt for %s; the run was not started\n' "$case" >&2
    rm -rf "$tmp"
    RUN_ERRORS=$((RUN_ERRORS + 1))
    return 1
  fi
  { printf '%q ' "${CLAUDE_CMD[@]}"; printf '\n'; } > "$run_dir/command.txt"

  printf 'flow-eval-run: [%s] starting (model %s; effort %s; total so far $%s; timeout %ss)\n' \
    "$label/$arm/$case/$trap/$n" "${run_model:-<cli default>}" "${EFFORT:-<cli default>}" "$total" "$run_timeout"
  local start end exit_code timed_out=0
  start=$(date +%s)
  local unset_args=()
  for v in "${STRIP_ENV[@]}"; do unset_args+=(-u "$v"); done
  ( cd "$tmp" && env "${unset_args[@]}" FLOW_STATE_DIR="$tmp/.flow-state" \
      timeout --kill-after=30 "$run_timeout" "${CLAUDE_CMD[@]}" < "$run_dir/prompt.txt" \
      > "$run_dir/stream.jsonl" 2> "$run_dir/stderr.log" )
  exit_code=$?
  end=$(date +%s)
  [ "$exit_code" = "124" ] || [ "$exit_code" = "137" ] && timed_out=1

  local finalize_args=(finalize-review-run --run-dir "$run_dir" --case-dir "$case_dir"
    --arm "$arm" --case "$case" --trap "$trap" --run "$n" --exit-code "$exit_code" --duration "$((end - start))")
  [ -n "$run_model" ] && finalize_args+=(--model-requested "$run_model")
  [ -n "$EFFORT" ] && finalize_args+=(--effort-requested "$EFFORT")
  [ "$timed_out" = "1" ] && finalize_args+=(--timed-out)
  local grade
  grade=$(python3 "$HELPER" "${finalize_args[@]}") || { printf 'flow-eval-run: scoring failed for %s\n' "$label/$arm/$case/$trap/$n" >&2; RUN_ERRORS=$((RUN_ERRORS + 1)); }
  printf 'flow-eval-run: [%s] done exit=%s %s\n' "$label/$arm/$case/$trap/$n" "$exit_code" "$grade"
  EXECUTED=$((EXECUTED + 1))
  if grep -q '"error": "' "$run_dir/result.json" 2>/dev/null && ! grep -q '"error": null' "$run_dir/result.json"; then
    RUN_ERRORS=$((RUN_ERRORS + 1))
  fi
  if [ "$KEEP_TEMP" = "1" ]; then
    cp -R "$tmp" "$run_dir/repo" \
      || printf 'flow-eval-run: WARN: could not copy %s into %s/repo; the temp directory itself is kept\n' "$tmp" "$run_dir" >&2
    printf 'flow-eval-run: kept %s\n' "$tmp"
  else
    rm -rf "$tmp"
  fi
  return 0
}

# --- plan and execute ---------------------------------------------------------
mkdir -p "$OUT_DIR"
# Resolve --out to an absolute path: run_one cds into the per-run temp copy
# and then references $run_dir/prompt.txt, so a relative --out would point
# nowhere from there. (Seen on the first full run: every run died with
# "prompt.txt: No such file or directory" before claude started.)
OUT_DIR=$(cd "$OUT_DIR" && pwd -P) || { echo "flow-eval-run: cannot resolve --out $OUT_DIR" >&2; exit 2; }
[ "$DRY_RUN" = "1" ] && echo "PLAN  out=$OUT_DIR  per-run cap=\$$MAX_BUDGET  total cap=\$$MAX_TOTAL  plugin=$PLUGIN_ROOT  models=$(for m in "${MODELS[@]}"; do printf '%s ' "$(model_label "$m")"; done)"
check_resume_effort

for model in "${MODELS[@]}"; do
  for case in $CASES; do
    case_runs="${RUNS:-$(case_meta "$case" runs)}"; case_runs="${case_runs:-3}"
    for arm in $ARMS; do
      if [ "$MODE" = "review" ]; then
        for trap_name in $(case_traps "$case"); do
          if [ "$DRY_RUN" = "1" ]; then
            printf 'CASE  %s/%s  module=%s.py\n' "$case" "$trap_name" "$(case_module "$case")"
          fi
          n=1
          while [ "$n" -le "$case_runs" ]; do
            # A budget stop ends the whole plan, across every model: the
            # cap is on the total, so continuing under another model would
            # spend past it. break 5 is what reaches the model loop — break 4
            # left it running. Anything else — a scratch repository that would
            # not build, an mktemp failure — abandons this trap's remaining
            # runs only. A claude error is not a failure here at all:
            # run_one_review records it and returns 0, so the run loop goes on.
            run_one_review "$model" "$arm" "$case" "$trap_name" "$n" \
              || { [ "$BUDGET_STOP" = "1" ] && break 5; break; }
            n=$((n + 1))
          done
        done
      else
        n=1
        while [ "$n" -le "$case_runs" ]; do
          # Same rule as review mode, one loop shallower: a budget stop ends
          # the plan across every model — break 4 is what reaches the model
          # loop here. Anything else — an mktemp failure, a scratch copy whose
          # git init failed — abandons this case and arm's remaining runs only,
          # and the failure is counted in RUN_ERRORS so the plan exits 4.
          run_one "$model" "$arm" "$case" "$n" \
            || { [ "$BUDGET_STOP" = "1" ] && break 4; break; }
          n=$((n + 1))
        done
      fi
    done
  done
done

if [ "$DRY_RUN" = "1" ]; then
  TRAP_NOTE=""
  if [ "$MODE" = "review" ]; then
    TRAP_TOTAL=0
    for case in $CASES; do
      TRAP_TOTAL=$((TRAP_TOTAL + $(case_traps "$case" | wc -l | tr -d ' ')))
    done
    TRAP_NOTE=" × $TRAP_TOTAL trap(s) over those cases"
  fi
  printf 'PLAN  %s run(s): %s model(s) × %s arm(s) × %s case(s)%s; %s already complete\n' \
    "$PLANNED" "${#MODELS[@]}" "$(echo "$ARMS" | wc -w | tr -d ' ')" "$(echo "$CASES" | wc -w | tr -d ' ')" "$TRAP_NOTE" "$SKIPPED"
  printf 'PLAN  mode=%s\n' "$MODE"
  rmdir "$OUT_DIR" 2>/dev/null
  exit 0
fi

python3 "$HELPER" aggregate --out "$OUT_DIR" --mode "$MODE" || { echo "flow-eval-run: aggregation failed" >&2; exit 2; }
echo "flow-eval-run: planned=$PLANNED executed=$EXECUTED skipped=$SKIPPED errors=$RUN_ERRORS -> $OUT_DIR/summary.md"
[ "$BUDGET_STOP" = "1" ] && exit 3
[ "$RUN_ERRORS" -gt 0 ] && exit 4
exit 0
