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
#              [--ref <id>]
#
#   --site          the decision point, e.g. review.dedup: lowercase words
#                   joined by dots
#   --state-file    what the questions are about. text (the default) is sent
#                   as a string; json is parsed and sent as a JSON value
#   --current       the decision Flow makes without System One, written into
#                   the records so shadow mode can be compared against it
#   --run-id        records go to .flow/runs/<id>/system-one.jsonl when that
#                   run exists
#   --ref           what the questions were about, as the caller names it
#                   (e.g. pr:275/inline:12345, goal:issue-274/AC2): written
#                   into the records, never sent to the provider, so a shadow
#                   record can be matched to the item it judged. Letters,
#                   digits and . _ : / # @ + -, starting with a letter or
#                   digit, at most 200 characters
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
# (off | shadow | on) is read from every tier, but a repository can only lower
# it: the mode used is the lower of the user's (user settings or the plugin
# default) and the repository's, on > shadow > off. A repository can neither
# switch a site on nor start shadow, which would send the request (the state,
# from the user's checkout) to the user's provider; a repository value above
# the user's gets the user's mode, and one warning says so.
#
# shadow asks, records the answers and exits 3; on asks, records and exits 0
# when every question answered with enough confidence.

set -uo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH
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
# The client runs with the repository as its working directory, and a
# planted ./yaml.py or ./json.py there must never run in place of the real
# module. PYTHONSAFEPATH keeps the directory off sys.path on Python 3.11 and
# later; older Pythons ignore it (macOS /usr/bin/python3 is 3.9), and an
# empty element in PYTHONPATH adds it on every version, as an absolute path.
# So every python3 call below also removes, before any other import, each
# sys.path entry that is relative or that resolves to the working directory.
export PYTHONSAFEPATH=1

usage() {
  # An argument value is shown with every byte that is not printable ASCII
  # as ?, so no newline, line separator (U+2028) or next-line character
  # (U+0085) in it can start another line.
  local LC_ALL=C
  printf 'flow-s1: %s\n' "${1//[^[:print:]]/?}" >&2
  printf 'usage: flow-s1.sh ask --site <id> --state-file <path> [--state-format text|json] [--current <decision>] [--run-id <id>] [--ref <id>]\n' >&2
  exit 2
}

# _ascii_shape <value> <regex> [max]: the value matches <regex> in the C locale,
# where [A-Za-z0-9] is ASCII only (in a UTF-8 locale glibc's ranges take
# thousands of other characters), and is at most [max] bytes.
_ascii_shape() {
  local LC_ALL=C
  [[ "$1" =~ $2 ]] || return 1
  [ -z "${3:-}" ] || [ "${#1}" -le "$3" ]
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

SITE=""; STATE_FILE=""; STATE_FORMAT=text; CURRENT=""; RUN_ID=""; REF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --site|--state-file|--state-format|--current|--run-id|--ref)
      [ $# -ge 2 ] || usage "$1 needs a value"
      case "$1" in
        --site) SITE="$2" ;;
        --state-file) STATE_FILE="$2" ;;
        --state-format) STATE_FORMAT="$2" ;;
        --current) CURRENT="$2" ;;
        --run-id) RUN_ID="$2" ;;
        --ref) REF="$2" ;;
      esac
      shift 2 ;;
    *) usage "unknown argument: $1" ;;
  esac
done

# The site id goes into a settings expression, so its shape is checked before
# anything is built from it.
[ -n "$SITE" ] || usage "--site is required"
_ascii_shape "$SITE" '^[a-z][a-z0-9_-]*(\.[a-z0-9_-]+)*$' || usage "--site must be lowercase words joined by dots (got: $SITE)"
[ -n "$STATE_FILE" ] || usage "--state-file is required"
[ -f "$STATE_FILE" ] && [ -r "$STATE_FILE" ] || usage "--state-file is not a readable file: $STATE_FILE"
case "$STATE_FORMAT" in text|json) ;; *) usage "--state-format must be text or json" ;; esac
if [ -n "$RUN_ID" ]; then
  case "$RUN_ID" in
    *..*|*/*) usage "--run-id contains '..' or '/' (got: $RUN_ID)" ;;
  esac
  _ascii_shape "$RUN_ID" '^[A-Za-z0-9][A-Za-z0-9._-]*$' || usage "--run-id must start with a letter or digit and use only [A-Za-z0-9._-] (got: $RUN_ID)"
fi
if [ -n "$REF" ]; then
  _ascii_shape "$REF" '^[A-Za-z0-9][A-Za-z0-9._:/#@+-]*$' 200 \
    || usage "--ref must start with a letter or digit, use only letters, digits and . _ : / # @ + -, and be at most 200 characters"
fi

# A working directory that no longer exists cannot be kept off sys.path.
pwd -P >/dev/null 2>&1 || no_answer "internal-error"
command -v python3 >/dev/null 2>&1 || no_answer "python-missing"
python3 -c 'import os, sys; sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and not (os.path.isdir(p) and os.access(os.curdir, os.X_OK) and os.path.samefile(p, os.curdir))]; import yaml' >/dev/null 2>&1 \
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
# The mode is read from every tier, and from the user's settings and the plugin
# default alone, and the lower of the two is used (on > shadow > off): a
# repository can lower the user's mode but never raise it, so it can neither
# switch a site on nor start sending to the user's provider (see the header).
# The site id was checked above, so it is safe inside the quoted key.
MODE=$("$CR" --default off ".systemOne.uses[\"$SITE\"]") || MODE=off
USER_MODE=$("$CR" --no-repo-settings --default off ".systemOne.uses[\"$SITE\"]" 2>/dev/null) || USER_MODE=off
_mode_rank() { case "$1" in off) printf 0 ;; shadow) printf 1 ;; on) printf 2 ;; esac; }
case "$USER_MODE" in off|shadow|on) ;; *) USER_MODE=off ;; esac
_r=$(_mode_rank "$MODE")
if [ -n "$_r" ] && [ "$_r" -gt "$(_mode_rank "$USER_MODE")" ]; then
  printf 'flow-s1: WARN: systemOne.uses["%s"] is %s in this repository'"'"'s settings, which can only lower your own mode; using %s\n' "$SITE" "$MODE" "$USER_MODE" >&2
  MODE=$USER_MODE
fi
# The mode may come from the repository, so a value that is not a mode is cut
# before it reaches python3's command line, where one over the system's
# argument limit would fail with an exit status the client never gives.
case "$MODE" in off|shadow|on) ;; *) MODE="${MODE:0:200}" ;; esac
# A settings value longer than any valid one would reach python3's command
# line whole, where one over the system's argument limit fails with an exit
# status the client never gives.
for _v in "$PROVIDER" "$BASE_URL" "$MODEL" "$KEY_ENV" "$TIMEOUT_MS" "$CAP"; do
  if [ "${#_v}" -gt 4096 ]; then
    printf 'flow-s1: WARN: a systemOne setting is longer than 4096 characters\n' >&2
    no_answer invalid-settings
  fi
done

TOP=$(git rev-parse --show-toplevel 2>/dev/null) || TOP=$(pwd -P)

# Every value is passed as --name=value: a separate word that starts with a
# dash (--current -keep, a settings value) would be read as an option.
# Per-user state is kept where cascade-resolve.sh --state-dir says: FLOW_STATE_DIR
# only when the user, not the repository, chose it.
STATE_DIR=$("${BASH:-bash}" "$SELF_DIR/cascade-resolve.sh" --state-dir) || STATE_DIR=""
# When the resolver gives nothing, keep no state rather than guess from HOME,
# which a repository can set.
[ -n "$STATE_DIR" ] || STATE_DIR="/nonexistent/.claude/flow-state"
exec python3 "$SELF_DIR/_flow_s1.py" \
  --site="$SITE" --state-file="$STATE_FILE" --state-format="$STATE_FORMAT" \
  --current="$CURRENT" --run-id="$RUN_ID" --ref="$REF" \
  --provider="$PROVIDER" --base-url="$BASE_URL" --model="$MODEL" --api-key-env="$KEY_ENV" \
  --timeout-ms="$TIMEOUT_MS" --state-token-cap="$CAP" --mode="$MODE" \
  --questions="$SELF_DIR/../system-one/questions.yaml" \
  --repo-top="$TOP" --state-dir="$STATE_DIR"
