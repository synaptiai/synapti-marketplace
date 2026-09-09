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
#   flow-eval-run.sh [--arm <name>|all] [--case <name>|all] [--runs N]
#                    [--model <m>] [--max-turns N] [--max-budget-usd X]
#                    [--max-total-usd X] [--timeout-seconds S] [--out <dir>]
#                    [--permission-mode acceptEdits|bypassPermissions]
#                    [--dry-run] [--keep-temp] [--aggregate-only] [--check-cases]
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
# Defaults: --arm all, --case all, --runs 3 (or the case's prompt.md `runs`),
# --max-turns 60 (or prompt.md `max_turns`), --max-budget-usd 4 per run,
# --max-total-usd 250, --timeout-seconds 1800 (or prompt.md `timeout_seconds`),
# --out plugins/flow/evals/results/<UTC timestamp>/. --model is passed through
# only when given; otherwise the CLI default model is used.
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
# Output layout under --out:
#   runs/<arm>/<case>/<n>/result.json            composite per-run record
#   runs/<arm>/<case>/<n>/claude.json            the claude result event (cost, turns, session_id)
#   runs/<arm>/<case>/<n>/stream.jsonl           full stream-json transcript of the run
#   runs/<arm>/<case>/<n>/hidden.txt             raw hidden-suite output
#   runs/<arm>/<case>/<n>/agent-tests-summary.json
#   runs/<arm>/<case>/<n>/settings.json          the arm's settings.flow.json (plugin arms)
#   runs/<arm>/<case>/<n>/prompt.txt, command.txt
#   summary.json, summary.md
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
# Requires: bash, python3, git, claude (on PATH). jq is not needed.

set -uo pipefail
export PYTHONSAFEPATH=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVALS_DIR="$PLUGIN_ROOT/evals"
HELPER="$SCRIPT_DIR/_flow_eval.py"
ALL_ARMS="baseline enforce-risk enforce-norisk suggest-risk suggest-norisk off-risk off-norisk"

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
)

ARM_FILTER="all"
CASE_FILTER="all"
RUNS=""
MODEL=""
MAX_TURNS=""
MAX_BUDGET="4"
MAX_TOTAL="250"
TIMEOUT_SECONDS=""
OUT_DIR=""
PERMISSION_MODE="acceptEdits"
DEFAULT_ALLOWED_TOOLS="Bash,Read,Write,Edit,Glob,Grep,Skill,Agent,TodoWrite,TaskCreate,TaskList,TaskUpdate,TaskGet"
DRY_RUN=0
KEEP_TEMP=0
AGGREGATE_ONLY=0
CHECK_CASES=0

usage() {
  sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'
}

need_value() {
  [ $# -ge 2 ] || { echo "flow-eval-run: $1 requires a value" >&2; exit 1; }
}

while [ $# -gt 0 ]; do
  case "$1" in
    --arm) need_value "$@"; ARM_FILTER="$2"; shift 2 ;;
    --case) need_value "$@"; CASE_FILTER="$2"; shift 2 ;;
    --runs) need_value "$@"; RUNS="$2"; shift 2 ;;
    --model) need_value "$@"; MODEL="$2"; shift 2 ;;
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
    -h|--help) usage; exit 0 ;;
    *) echo "flow-eval-run: unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

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

if [ "$CHECK_CASES" = "1" ]; then
  if [ "$CASE_FILTER" = "all" ]; then
    python3 "$HELPER" check-cases --evals-dir "$EVALS_DIR"
  else
    python3 "$HELPER" check-cases --evals-dir "$EVALS_DIR" --case "$CASE_FILTER"
  fi
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

if [ -z "$OUT_DIR" ]; then
  OUT_DIR="$EVALS_DIR/results/$(date -u +%Y%m%dT%H%M%SZ)"
fi

if [ "$AGGREGATE_ONLY" = "1" ]; then
  python3 "$HELPER" aggregate --out "$OUT_DIR" || exit 2
  echo "flow-eval-run: wrote $OUT_DIR/summary.md"
  exit 0
fi

if [ "$DRY_RUN" != "1" ]; then
  for tool in claude git timeout; do
    command -v "$tool" >/dev/null 2>&1 || { echo "flow-eval-run: $tool is required" >&2; exit 2; }
  done
fi

# --- helpers -----------------------------------------------------------------
arm_settings() {
  # Prints the settings.flow.json body for a plugin arm (nothing for baseline).
  case "$1" in
    baseline) return 0 ;;
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
  [ "$arm" != "baseline" ] && CLAUDE_CMD+=(--plugin-dir "$PLUGIN_ROOT")
  return 0
}

RUN_ERRORS=0
BUDGET_STOP=0
PLANNED=0
EXECUTED=0
SKIPPED=0

run_one() {
  local arm="$1" case="$2" n="$3"
  local run_dir="$OUT_DIR/runs/$arm/$case/$n"
  local case_dir="$EVALS_DIR/$case"
  local run_max_turns run_model run_timeout run_allowed_tools
  run_max_turns="${MAX_TURNS:-$(case_meta "$case" max_turns)}"; run_max_turns="${run_max_turns:-60}"
  # prompt.md allowed_tools is a JSON list; the CLI wants a comma-separated string.
  run_allowed_tools="$(case_meta "$case" allowed_tools | tr -d '[]" ' )"; run_allowed_tools="${run_allowed_tools:-$DEFAULT_ALLOWED_TOOLS}"
  run_timeout="${TIMEOUT_SECONDS:-$(case_meta "$case" timeout_seconds)}"; run_timeout="${run_timeout:-1800}"
  run_model="${MODEL:-$(case_meta "$case" model)}"
  build_command

  PLANNED=$((PLANNED + 1))
  if [ -f "$run_dir/result.json" ]; then
    SKIPPED=$((SKIPPED + 1))
    [ "$DRY_RUN" = "1" ] && echo "SKIP  $arm/$case/$n (result.json exists)"
    return 0
  fi

  if [ "$DRY_RUN" = "1" ]; then
    local plugin_note="(no plugin)"
    [ "$arm" != "baseline" ] && plugin_note="settings=$(arm_settings "$arm")"
    echo "RUN   $arm/$case/$n  timeout=${run_timeout}s  $plugin_note"
    local unset_list=""
    for v in "${STRIP_ENV[@]}"; do unset_list="$unset_list -u $v"; done
    printf '      cd <temp copy of %s> && env%s FLOW_STATE_DIR=<temp>/.flow-state timeout %s %s < prompt.txt > %s/stream.jsonl\n' \
      "evals/$case/scaffold" "$unset_list" "$run_timeout" "${CLAUDE_CMD[*]}" "runs/$arm/$case/$n"
    return 0
  fi

  local total
  total=$(running_total)
  if would_exceed "$total" "$MAX_BUDGET" "$MAX_TOTAL"; then
    echo "flow-eval-run: stopping before $arm/$case/$n — running total \$$total + per-run cap \$$MAX_BUDGET would exceed --max-total-usd \$$MAX_TOTAL" >&2
    BUDGET_STOP=1
    return 1
  fi

  mkdir -p "$run_dir"
  local tmp
  tmp=$(mktemp -d -t flow-eval.XXXXXX) || { echo "flow-eval-run: mktemp failed" >&2; return 1; }
  cp -R "$case_dir/scaffold/." "$tmp/"
  mkdir -p "$tmp/.claude" "$tmp/.flow-state"
  if [ "$arm" != "baseline" ]; then
    arm_settings "$arm" > "$tmp/.claude/settings.flow.json"
    cp "$tmp/.claude/settings.flow.json" "$run_dir/settings.json"
  fi
  ( cd "$tmp" && git init -q && git add -A && git -c user.name=flow-eval -c user.email=flow-eval@localhost commit -q -m "scaffold" ) \
    || { echo "flow-eval-run: git init failed in $tmp" >&2; rm -rf "$tmp"; return 1; }
  python3 "$HELPER" case-prompt "$case_dir" --arm "$arm" > "$run_dir/prompt.txt"
  printf '%s\n' "${CLAUDE_CMD[*]}" > "$run_dir/command.txt"

  echo "flow-eval-run: [$arm/$case/$n] starting (total so far \$$total; max-turns $run_max_turns; timeout ${run_timeout}s)"
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
  [ "$timed_out" = "1" ] && finalize_args+=(--timed-out)
  [ "$KEEP_TEMP" = "1" ] && finalize_args+=(--temp-dir "$tmp")
  local grade
  grade=$(python3 "$HELPER" "${finalize_args[@]}") || { echo "flow-eval-run: grading failed for $arm/$case/$n" >&2; RUN_ERRORS=$((RUN_ERRORS + 1)); }
  echo "flow-eval-run: [$arm/$case/$n] done exit=$exit_code $grade"
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

# --- plan and execute ---------------------------------------------------------
[ "$DRY_RUN" = "1" ] && echo "PLAN  out=$OUT_DIR  per-run cap=\$$MAX_BUDGET  total cap=\$$MAX_TOTAL  plugin=$PLUGIN_ROOT"
mkdir -p "$OUT_DIR"
for case in $CASES; do
  case_runs="${RUNS:-$(case_meta "$case" runs)}"; case_runs="${case_runs:-3}"
  for arm in $ARMS; do
    n=1
    while [ "$n" -le "$case_runs" ]; do
      run_one "$arm" "$case" "$n" || break 2
      n=$((n + 1))
    done
  done
done

if [ "$DRY_RUN" = "1" ]; then
  echo "PLAN  $PLANNED run(s): $(echo "$ARMS" | wc -w | tr -d ' ') arm(s) × $(echo "$CASES" | wc -w | tr -d ' ') case(s); $SKIPPED already complete"
  rmdir "$OUT_DIR" 2>/dev/null
  exit 0
fi

python3 "$HELPER" aggregate --out "$OUT_DIR" || { echo "flow-eval-run: aggregation failed" >&2; exit 2; }
echo "flow-eval-run: planned=$PLANNED executed=$EXECUTED skipped=$SKIPPED errors=$RUN_ERRORS -> $OUT_DIR/summary.md"
[ "$BUDGET_STOP" = "1" ] && exit 3
[ "$RUN_ERRORS" -gt 0 ] && exit 4
exit 0
