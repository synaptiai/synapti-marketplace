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
#       prints off, shadow or on: the site's mode as bin/flow-s1.sh reads it.
#       A repository's settings cannot make it on; anything else is off.
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
#       is discarded in every mode, so nothing it says reaches the user.
#   _goal_s1_results <question>
#       prints a JSON array, one entry per manifest row in order:
#       {n, coverage, id, ref, answer}, where answer is {p, confidence} when
#       the call exited 0 with a noul answer to <question>, and null otherwise.
#   _goal_s1_cleanup
#       stops calls still running and removes the work directory. Callers run
#       it from their EXIT trap.
#
# Raw criterion ids never pass through here: a goal can hold an id with a
# newline, which a line-based read would split. The manifest carries each id
# twice, sanitized: with ? for messages and --current, and with _ for --ref,
# whose character set has no ?.

_GOAL_S1_DIR=""
_GOAL_S1_PIDS=""

_goal_s1_mode() {
  local cr="$1/bin/cascade-resolve.sh" site="$2" mode user
  mode=$("$cr" --default off ".systemOne.uses[\"$site\"]" 2>/dev/null) || mode=off
  if [ "$mode" = on ]; then
    # The same rule as flow-s1.sh: on counts only when the user's settings or
    # the plugin default set it; otherwise the user's own mode applies.
    user=$("$cr" --no-repo-settings --default off ".systemOne.uses[\"$site\"]" 2>/dev/null) || user=off
    [ "$user" = on ] || mode="$user"
  fi
  case "$mode" in off|shadow|on) ;; *) mode=off ;; esac
  printf '%s' "$mode"
}

_goal_s1_cleanup() {
  local pid
  for pid in $_GOAL_S1_PIDS; do
    kill "$pid" 2>/dev/null
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
# exit status. Reads the caller's batch array (bash's dynamic scope).
_goal_s1_reap() {
  local entry rc
  for entry in ${batch[@]+"${batch[@]}"}; do
    wait "${entry%%:*}"
    rc=$?
    printf '%s' "$rc" > "$_GOAL_S1_DIR/${entry#*:}.rc"
  done
  batch=()
}

_goal_s1_ask_all() {
  local root="$1" site="$2" rid="$3" n w="$_GOAL_S1_DIR"
  local batch=() run=()
  shift 3
  [ -z "$rid" ] || run=(--run-id "$rid")
  for n in "$@"; do
    "$root/bin/flow-s1.sh" ask --site "$site" --state-file "$w/$n.json" --state-format json \
      --current "$(cat "$w/$n.current")" --ref "$(cat "$w/$n.ref")" ${run[@]+"${run[@]}"} \
      > "$w/$n.out" 2>/dev/null &
    _GOAL_S1_PIDS="$_GOAL_S1_PIDS $!"
    batch+=("$!:$n")
    [ "${#batch[@]}" -lt 5 ] || _goal_s1_reap
  done
  _goal_s1_reap
  _GOAL_S1_PIDS=""
}

_goal_s1_results() {
  local q="$1" w="$_GOAL_S1_DIR" n cov id ref rc ans
  while IFS=$'\t' read -r n cov id ref; do
    case "$n" in ''|*[!0-9]*) continue ;; esac
    ans=""
    rc=$(cat "$w/$n.rc" 2>/dev/null)
    if [ "$rc" = 0 ]; then
      ans=$(jq -c --arg q "$q" '.answers[$q] | select(type == "object" and (.p | type) == "number" and (.confidence | type) == "number") | {p, confidence}' "$w/$n.out" 2>/dev/null)
    fi
    [ -n "$ans" ] || ans=null
    jq -nc --argjson n "$n" --arg c "$cov" --arg id "$id" --arg ref "$ref" --argjson a "$ans" \
      '{n: $n, coverage: $c, id: $id, ref: $ref, answer: $a}'
  done < "$w/manifest" | jq -sc .
}
