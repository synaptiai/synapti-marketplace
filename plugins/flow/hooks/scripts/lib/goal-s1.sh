# shellcheck shell=bash
# plugins/flow/hooks/scripts/lib/goal-s1.sh
#
# What the two goal Stop hooks share when they ask System One about the
# criteria that have no verification command: flow-goal-evaluator.sh asks
# goal.judge (evaluator-loop), flow-goal-stop.sh asks goal.warn-evidence (warn
# mode). Sourced by both. See references/system-one.md.
#
# Contract for callers:
#   _goal_s1_mode <plugin root> <site>
#       prints off, shadow or on: the site's mode as bin/flow-s1-mode.sh
#       decides it, which is the mode bin/flow-s1.sh uses. A repository's
#       settings can only lower the user's mode. No provider, or any failure,
#       is off.
#   _goal_s1_prepare <plugin root> <goal file> <report json> <run dir or ''>
#       makes the work directory (_GOAL_S1_DIR) and writes one state per
#       criterion in the report's no_command list, with the manifest
#       (_flow_evidence_bundle.py --criterion-states). A manifest row's <n> is
#       the criterion's index in that list. Returns 1, with nothing to ask,
#       when either step fails, which includes an id in the list that is not a
#       string.
#   _goal_s1_ask_all <plugin root> <site> <run id or ''> <n>...
#       asks flow-s1.sh about each state <n>, at most 5 at a time, with the
#       --current and --ref the caller wrote to <n>.current and <n>.ref. Each
#       call's stdout goes to <n>.out and its exit status to <n>.rc; its stderr
#       is discarded in every mode, so nothing it says reaches the user. Only
#       the first _GOAL_S1_MAX states (10) are asked about; the rest are not
#       asked and have no answer.
#   _goal_s1_rows
#       prints how many rows the manifest has.
#   _goal_s1_results <question>
#       prints a JSON array, one entry per manifest row in order:
#       {n, coverage, id, ref, answer}, where answer is {p, confidence} when
#       the call exited 0 with exactly one noul answer to <question> in its
#       output, and null otherwise (not asked, no answer, or output that is
#       not one JSON object).
#   _goal_s1_cleanup
#       stops calls still running, waits for them, and removes the work
#       directory. Callers run it from their EXIT trap.
#
# Raw criterion ids never pass through here: a goal can hold an id with a
# newline, which a line-based read would split. The manifest carries each id
# twice, sanitized: with ? for messages and --current, and with _ for --ref,
# whose character set has no ?.

_GOAL_S1_DIR=""
_GOAL_S1_PIDS=""
# The most criteria asked about in one Stop. Each call can take up to the
# provider's timeoutMs, and they run 5 at a time, so the cap bounds how long a
# stop can wait: at most 2 x timeoutMs.
_GOAL_S1_MAX=10

_goal_s1_mode() {
  local mode
  mode=$("${BASH:-bash}" "$1/bin/flow-s1-mode.sh" "$2" 2>/dev/null) || mode=off
  case "$mode" in shadow|on) ;; *) mode=off ;; esac
  printf '%s' "$mode"
}

_goal_s1_cleanup() {
  local pid
  for pid in $_GOAL_S1_PIDS; do
    kill "$pid" 2>/dev/null
  done
  # Each call stopped is waited for, so none is left running when the hook
  # exits.
  for pid in $_GOAL_S1_PIDS; do
    wait "$pid" 2>/dev/null
  done
  _GOAL_S1_PIDS=""
  if [ -n "$_GOAL_S1_DIR" ] && [ -d "$_GOAL_S1_DIR" ]; then
    rm -r -f "$_GOAL_S1_DIR" 2>/dev/null
  fi
  _GOAL_S1_DIR=""
}

_goal_s1_prepare() {
  # A template with a path, not -t: mktemp -t on macOS (Darwin 27) ignored
  # TMPDIR, and a path template uses it on macOS and Linux alike.
  _GOAL_S1_DIR=$(mktemp -d "${TMPDIR:-/tmp}/flow-goal-s1.XXXXXX" 2>/dev/null) || { _GOAL_S1_DIR=""; return 1; }
  chmod 0700 "$_GOAL_S1_DIR" 2>/dev/null
  PYTHONSAFEPATH=1 python3 "$1/bin/_flow_evidence_bundle.py" --criterion-states "$2" "$3" "$4" "$_GOAL_S1_DIR" \
    > "$_GOAL_S1_DIR/manifest" 2>/dev/null || return 1
  [ -s "$_GOAL_S1_DIR/manifest" ]
}

# _goal_s1_reap — wait for the calls of the current batch and keep each one's
# exit status. Reads the caller's batch array (bash's dynamic scope). The batch
# holds every call still running, and right after each wait _GOAL_S1_PIDS keeps
# only the calls of the batch not yet waited for, before anything else runs: a
# PID kept after its wait could by then be another process's, which
# _goal_s1_cleanup would stop.
_goal_s1_reap() {
  local i j rc pids
  for ((i = 0; i < ${#batch[@]}; i++)); do
    pids=""
    for ((j = i + 1; j < ${#batch[@]}; j++)); do pids="$pids ${batch[j]%%:*}"; done
    wait "${batch[i]%%:*}"
    rc=$?
    _GOAL_S1_PIDS="$pids"
    printf '%s' "$rc" > "$_GOAL_S1_DIR/${batch[i]#*:}.rc"
  done
  batch=()
  _GOAL_S1_PIDS=""
}

_goal_s1_ask_all() {
  local root="$1" site="$2" rid="$3" n w="$_GOAL_S1_DIR" asked=0
  local batch=() run=()
  shift 3
  [ -z "$rid" ] || run=(--run-id "$rid")
  for n in "$@"; do
    [ "$asked" -lt "$_GOAL_S1_MAX" ] || break
    asked=$((asked + 1))
    "$root/bin/flow-s1.sh" ask --site "$site" --state-file "$w/$n.json" --state-format json \
      --current "$(cat "$w/$n.current")" --ref "$(cat "$w/$n.ref")" ${run[@]+"${run[@]}"} \
      > "$w/$n.out" 2>/dev/null &
    _GOAL_S1_PIDS="$_GOAL_S1_PIDS $!"
    batch+=("$!:$n")
    [ "${#batch[@]}" -lt 5 ] || _goal_s1_reap
  done
  _goal_s1_reap
}

_goal_s1_rows() {
  local n _rest rows=0
  while IFS=$'\t' read -r n _rest; do
    case "$n" in ''|*[!0-9]*) continue ;; esac
    rows=$((rows + 1))
  done < "$_GOAL_S1_DIR/manifest"
  printf '%s' "$rows"
}

# Every manifest row prints one entry, whatever its call wrote: the answer is
# read from the whole output as one JSON value (-s), and passed on as text that
# the row's own jq parses, so an output of two JSON lines, or of text that is
# not JSON, gives a null answer, never a row left out.
_goal_s1_results() {
  local q="$1" w="$_GOAL_S1_DIR" n cov id ref rc ans
  while IFS=$'\t' read -r n cov id ref; do
    case "$n" in ''|*[!0-9]*) continue ;; esac
    ans=""
    rc=$(cat "$w/$n.rc" 2>/dev/null)
    if [ "$rc" = 0 ]; then
      ans=$(jq -cs --arg q "$q" 'if length == 1 then .[0].answers[$q] | select(type == "object" and (.p | type) == "number" and (.confidence | type) == "number") | {p, confidence} else empty end' "$w/$n.out" 2>/dev/null)
    fi
    jq -nc --argjson n "$n" --arg c "$cov" --arg id "$id" --arg ref "$ref" --arg a "$ans" \
      '{n: $n, coverage: $c, id: $id, ref: $ref, answer: ($a | fromjson? // null)}' 2>/dev/null
  done < "$w/manifest" | jq -sc .
}
