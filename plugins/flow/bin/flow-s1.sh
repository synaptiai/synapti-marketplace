#!/usr/bin/env bash
# [flow] Ask a configured System One provider the questions of one decision
# point, and print the answers — or say "no answer", so the caller keeps doing
# what Flow did before System One existed.
#
# A System One model (TypeSafe's Jev, or the open-weight imajev served
# locally) takes a state and typed questions and returns calibrated
# probabilities: noul (yes/no), choice (one of a set) and score (ordered
# levels). The questions and their thresholds live in
# system-one/questions.yaml, keyed by decision point ("site"). See
# references/system-one.md.
#
# Usage:
#   flow-s1.sh ask --site <id> --state-file <path>
#              [--state-format text|json] [--current <decision>] [--run-id <id>]
#
#   --site          the decision point, e.g. review.dedup: lowercase words
#                   joined by dots
#   --state-file    what the questions are about. text (the default) is sent
#                   as a string; json is parsed and sent as a JSON value
#   --current       the decision Flow makes without System One, written into
#                   the records so shadow mode can be compared against it
#   --run-id        records go to .flow/runs/<id>/system-one.jsonl when that
#                   run exists
#
# Exit:
#   0 — answered: stdout is one JSON line
#       {"site","provider","model","truncated","answers":{<question id>:{...}}}
#   3 — no answer: stdout is empty and stderr says
#       "flow-s1: no answer: <reason>". The caller does what it did before.
#   2 — usage error
#
# Settings: systemOne.provider, baseUrl, model, apiKeyEnv, timeoutMs and
# stateTokenCap are read from the user's settings and the plugin default only
# (cascade-resolve.sh --no-repo-settings). A repository's settings files come
# with the checkout, and a checkout must not choose where Flow sends its diffs
# or which environment variable it sends as a key. systemOne.uses.<site>
# (off | shadow | on) is read from every tier: a repository may switch a
# decision point on, but only toward the server the user chose.
#
# shadow asks, records the answers and exits 3; on asks, records and exits 0
# when every question answered with enough confidence.

set -uo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH
# Keep the working directory out of PYTHONPATH before python3 starts: the
# interpreter imports sitecustomize from each element at startup, and an
# empty element is the working directory. tests/syspath-guard.test.sh has the
# reasons; FLOW_USER_PYTHONPATH keeps the original for the user's commands.
[ -n "${FLOW_USER_PYTHONPATH+x}" ] || export FLOW_USER_PYTHONPATH="${PYTHONPATH-}"
_flow_pp=""; _flow_rest="${PYTHONPATH-}:"; _flow_wd=$(pwd -P 2>/dev/null) || _flow_wd=""
while [ -n "$_flow_rest" ]; do _flow_e=${_flow_rest%%:*}; _flow_rest=${_flow_rest#*:}; case "$_flow_e" in /*) [ "$(command cd -P -- "$_flow_e" >/dev/null 2>&1 && pwd -P)" = "$_flow_wd" ] || _flow_pp="${_flow_pp:+$_flow_pp:}$_flow_e" ;; esac; done
if [ -n "$_flow_pp" ]; then export PYTHONPATH="$_flow_pp"; else unset PYTHONPATH; fi
# The client runs with the repository as its working directory, and a
# planted ./yaml.py or ./json.py there must never run in place of the real
# module. PYTHONSAFEPATH keeps the directory off sys.path on Python 3.11 and
# later; older Pythons ignore it (macOS /usr/bin/python3 is 3.9), and an
# empty element in PYTHONPATH adds it on every version, as an absolute path.
# So every python3 call below also removes, before any other import, each
# sys.path entry that is relative or that resolves to the working directory.
export PYTHONSAFEPATH=1

usage() {
  printf 'flow-s1: %s\n' "$1" >&2
  printf 'usage: flow-s1.sh ask --site <id> --state-file <path> [--state-format text|json] [--current <decision>] [--run-id <id>]\n' >&2
  exit 2
}
no_answer() {
  printf 'flow-s1: no answer: %s\n' "$1" >&2
  exit 3
}

# This script's own directory, through symlinks. The questions file and the
# Python half are found next to it, never through the working directory, which
# during a review is the pull request under review.
_self="$0"
_hops=0
while [ -L "$_self" ] && [ "$_hops" -lt 40 ]; do
  _link=$(readlink "$_self") || break
  case "$_link" in
    /*) _self="$_link" ;;
    *)  _self="$(dirname "$_self")/$_link" ;;
  esac
  _hops=$((_hops + 1))
done
SELF_DIR="$(cd "$(dirname "$_self")" 2>/dev/null && pwd -P)" || no_answer "internal-error"

[ "${1:-}" = ask ] || usage "the first argument must be 'ask'"
shift

SITE=""; STATE_FILE=""; STATE_FORMAT=text; CURRENT=""; RUN_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --site|--state-file|--state-format|--current|--run-id)
      [ $# -ge 2 ] || usage "$1 needs a value"
      case "$1" in
        --site) SITE="$2" ;;
        --state-file) STATE_FILE="$2" ;;
        --state-format) STATE_FORMAT="$2" ;;
        --current) CURRENT="$2" ;;
        --run-id) RUN_ID="$2" ;;
      esac
      shift 2 ;;
    *) usage "unknown argument: $1" ;;
  esac
done

# The site id goes into a settings expression, so its shape is checked before
# anything is built from it.
[ -n "$SITE" ] || usage "--site is required"
[[ "$SITE" =~ ^[a-z][a-z0-9_-]*(\.[a-z0-9_-]+)*$ ]] || usage "--site must be lowercase words joined by dots (got: $SITE)"
[ -n "$STATE_FILE" ] || usage "--state-file is required"
[ -f "$STATE_FILE" ] && [ -r "$STATE_FILE" ] || usage "--state-file is not a readable file: $STATE_FILE"
case "$STATE_FORMAT" in text|json) ;; *) usage "--state-format must be text or json" ;; esac
if [ -n "$RUN_ID" ]; then
  case "$RUN_ID" in
    *..*|*/*) usage "--run-id contains '..' or '/' (got: $RUN_ID)" ;;
  esac
  [[ "$RUN_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || usage "--run-id must start with a letter or digit and use only [A-Za-z0-9._-] (got: $RUN_ID)"
fi

# A working directory that no longer exists cannot be kept off sys.path.
pwd -P >/dev/null 2>&1 || no_answer "internal-error"
command -v python3 >/dev/null 2>&1 || no_answer "python-missing"
python3 -c 'import os, sys; _flow_cwd = os.path.realpath(os.getcwd()); sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]; import yaml' >/dev/null 2>&1 \
  || no_answer "python-missing"

CR="$SELF_DIR/cascade-resolve.sh"
[ -x "$CR" ] || no_answer "settings-refused"

# _user <key> <default> — a provider setting from the user tier or the plugin
# default. Any failure of the resolver, including its refusal to answer when
# this script sits inside the repository, is "no answer": a failure never
# widens what is read, and never falls back to a preset.
_user() {
  local v
  v=$("$CR" --no-repo-settings --default "$2" ".systemOne.$1") || no_answer "settings-refused"
  printf '%s' "$v"
}

PROVIDER=$(_user provider none) || exit $?
[ "$PROVIDER" = none ] && no_answer "provider-none"
BASE_URL=$(_user baseUrl "") || exit $?
MODEL=$(_user model "") || exit $?
KEY_ENV=$(_user apiKeyEnv "") || exit $?
TIMEOUT_MS=$(_user timeoutMs 3000) || exit $?
CAP=$(_user stateTokenCap 0) || exit $?
# The mode may come from the repository. The site id was checked above, so it
# is safe inside the quoted key.
MODE=$("$CR" --default off ".systemOne.uses[\"$SITE\"]") || MODE=off

TOP=$(git rev-parse --show-toplevel 2>/dev/null) || TOP=$(pwd -P)

# Every value is passed as --name=value: a separate word that starts with a
# dash (--current -keep, a settings value) would be read as an option.
exec python3 "$SELF_DIR/_flow_s1.py" \
  --site="$SITE" --state-file="$STATE_FILE" --state-format="$STATE_FORMAT" \
  --current="$CURRENT" --run-id="$RUN_ID" \
  --provider="$PROVIDER" --base-url="$BASE_URL" --model="$MODEL" --api-key-env="$KEY_ENV" \
  --timeout-ms="$TIMEOUT_MS" --state-token-cap="$CAP" --mode="$MODE" \
  --questions="$SELF_DIR/../system-one/questions.yaml" \
  --repo-top="$TOP" --state-dir="${FLOW_STATE_DIR:-${HOME:-/nonexistent}/.claude/flow-state}"
