#!/usr/bin/env bash
# [flow] Ask System One whether one uncertain change serves the issue
# (decision point classify.serves-issue), for the prompt that sends uncertain
# files to the user, or record the user's choice next to the answer.
#
# Called by S1_CLASSIFY_BLOCK and S1_RECORD_BLOCK in commands/commit.md
# (Phase 3) and commands/start.md (CODE step 8), once per uncertain file. The
# answer never changes a classification: an uncertain file stays uncertain
# and the user still chooses. See references/system-one.md.
#
# Usage:
#   flow-classify-s1.sh ask    --file <path> --issue <N> --signals <text>
#                              [--run-id <id>] [--issue-cache <dir>]
#   flow-classify-s1.sh record --file <path> --issue <N> --signals <text>
#                              --decision include|exclude [--run-id <id>]
#                              [--issue-cache <dir>]
#
#   --file      the changed file, relative to the top of the repository
#   --issue     the issue number; empty, "(none)" or anything that is not a
#               number means there is no issue, and nothing is asked
#   --signals   the classification signals that matched the file, separated
#               by ";"
#   --decision  the user's choice, written into the record as `current`
#   --run-id    records go to .flow/runs/<id>/system-one.jsonl when that run
#               exists; empty means none
#   --issue-cache  a directory the caller made for one prompt: the issue is
#               fetched once for every file of that prompt, and a failed fetch
#               is not tried again; empty means fetch for each file
#
# ask runs only when the site is `on`, and record only when it is `shadow`,
# so the provider is asked at most once per file per prompt. The mode is read
# as bin/flow-s1.sh reads it, from the top of the repository: a repository's
# settings cannot switch it on, and can set it to shadow.
#
# ask prints KEY=value lines and exits 0:
#   S1_FILE=<path>
#   S1_ESTIMATE=<p, the probability the change serves the issue, 2 decimals>
#   S1_MODEL=<model>  S1_TRUNCATED=true|false        (answered)
# or
#   S1_FILE=<path>
#   S1_ESTIMATE=none
#   S1_REASON=<reason>                                (no answer)
# The reason is bin/flow-s1.sh's, or one of not-on, provider-none,
# settings-refused, red-flag, no-issue, no-repository, no-diff,
# python-missing, internal-error.
# record prints nothing and exits 0. Both exit 2 on wrong arguments.
#
# What is sent: the issue's number, title and body, the file's path, its git
# status and its uncommitted diff (the whole file when untracked, "(binary)"
# for a binary file, at most the first 400 lines and 64 KiB of a longer diff),
# and the signals. At most 512 KiB of the diff is read.
# A file whose path matches a red-flag pattern is never read or sent.

set -uo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH
# Keep the repository out of PYTHONPATH before python3 starts; see
# bin/flow-s1.sh and tests/syspath-guard.test.sh.
[ -n "${FLOW_USER_PYTHONPATH+x}" ] || export FLOW_USER_PYTHONPATH="${PYTHONPATH-}"
_flow_pp=""; if [ -n "${PYTHONPATH-}" ]; then _flow_pp=$(python3 -I -c 'exec("import os, sys\ndef ids(p):\n    out = set()\n    while True:\n        try:\n            st = os.stat(p)\n        except OSError:\n            return out\n        out.add((st.st_dev, st.st_ino))\n        q = os.path.dirname(p)\n        if q == p:\n            return out\n        p = q\ntry:\n    cwd = os.getcwd()\nexcept OSError:\n    sys.exit(0)\ntop = d = cwd\nwhile True:\n    if os.path.lexists(os.path.join(d, \".git\")):\n        top = d\n        break\n    q = os.path.dirname(d)\n    if q == d:\n        break\n    d = q\nst = os.stat(top)\ntop_id = (st.st_dev, st.st_ino)\nup = ids(cwd)\nkeep = []\nfor e in os.environ.get(\"PYTHONPATH\", \"\").split(\":\"):\n    if not e.startswith(\"/\"):\n        continue\n    r = os.path.realpath(e)\n    if \":\" in r or chr(10) in r or not os.path.isdir(r):\n        continue\n    try:\n        st = os.stat(r)\n    except OSError:\n        continue\n    if (st.st_dev, st.st_ino) in up or top_id in ids(r):\n        continue\n    keep.append(r)\nsys.stdout.buffer.write(os.fsencode(\":\".join(keep)))")' 2>/dev/null) || _flow_pp=""; fi
if [ -n "$_flow_pp" ]; then export PYTHONPATH="$_flow_pp"; else unset PYTHONPATH; fi
export PYTHONSAFEPATH=1

SITE="classify.serves-issue"
ASK_LIMIT_LINES=400
ASK_LIMIT_BYTES=65536

usage() {
  local LC_ALL=C
  printf 'flow-classify-s1: %s\n' "${1//[^[:print:]]/?}" >&2
  printf 'usage: flow-classify-s1.sh ask|record --file <path> --issue <N> --signals <text> [--decision include|exclude] [--run-id <id>] [--issue-cache <dir>]\n' >&2
  exit 2
}

# This script's own directory, through symlinks: cascade-resolve.sh and
# flow-s1.sh are found next to it, never through the working directory.
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
SELF_DIR="$(cd "$(dirname "$_self")" 2>/dev/null && pwd -P)" || SELF_DIR=""

SUB="${1:-}"
case "$SUB" in
  ask|record) shift ;;
  *) usage "the first argument must be ask or record" ;;
esac

FILE=""; ISSUE=""; SIGNALS=""; DECISION=""; RUN_ID=""; ISSUE_CACHE=""
HAVE_FILE=0; HAVE_DECISION=0
while [ $# -gt 0 ]; do
  case "$1" in
    --file|--issue|--signals|--decision|--run-id|--issue-cache)
      [ $# -ge 2 ] || usage "$1 needs a value"
      case "$1" in
        --file) FILE="$2"; HAVE_FILE=1 ;;
        --issue) ISSUE="$2" ;;
        --signals) SIGNALS="$2" ;;
        --decision) DECISION="$2"; HAVE_DECISION=1 ;;
        --run-id) RUN_ID="$2" ;;
        --issue-cache) ISSUE_CACHE="$2" ;;
      esac
      shift 2 ;;
    *) usage "unknown argument: $1" ;;
  esac
done
[ "$HAVE_FILE" = 1 ] && [ -n "$FILE" ] || usage "--file is required"
if [ "$SUB" = record ]; then
  case "$DECISION" in include|exclude) ;; *) usage "--decision must be include or exclude" ;; esac
else
  [ "$HAVE_DECISION" = 0 ] || usage "--decision is for record only"
fi
if [ -n "$RUN_ID" ]; then
  case "$RUN_ID" in *..*|*/*) usage "--run-id contains '..' or '/'" ;; esac
  (LC_ALL=C; [[ "$RUN_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]) || usage "--run-id must start with a letter or digit and use only [A-Za-z0-9._-]"
fi

# none <reason>: ask prints that there is no estimate, and why; record prints
# nothing. Either way the caller does what it did before.
none() {
  if [ "$SUB" = ask ]; then
    printf 'S1_FILE=%s\nS1_ESTIMATE=none\nS1_REASON=%s\n' "$FILE" "$1"
  fi
  exit 0
}

[ -n "$SELF_DIR" ] || none internal-error
CR="$SELF_DIR/cascade-resolve.sh"
[ -x "$CR" ] || none settings-refused

# Settings are read from the top of the repository, the directory bin/flow-s1.sh
# runs in below: the repository's settings files are found relative to the
# working directory, and a session in a subdirectory would otherwise read a
# different mode than flow-s1.sh. Outside a repository the working directory
# stays, and no-repository is given further down.
TOP=$(git rev-parse --show-toplevel 2>/dev/null </dev/null) && cd "$TOP" 2>/dev/null || TOP=""

# The mode, read as bin/flow-s1.sh reads it: from every tier, and `on` only
# when the user's settings or the plugin default set it. This is a copy of
# the mode rule in bin/flow-s1.sh; a change to that rule is made in both
# files. The warning is flow-s1.sh's, so a user sees one wording for one rule.
# The user's own mode is read only when the mode is `on`. When the resolver
# refuses to read it (the plugin is inside the repository), the answer is
# settings-refused, as flow-s1.sh gives for the provider: a refusal is never
# taken to mean that the user's mode is off.
MODE=$("$CR" --default off ".systemOne.uses[\"$SITE\"]" 2>/dev/null) || MODE=off
if [ "$MODE" = on ]; then
  USER_MODE=$("$CR" --no-repo-settings --default off ".systemOne.uses[\"$SITE\"]" 2>/dev/null) || none settings-refused
  if [ "$USER_MODE" != on ]; then
    case "$USER_MODE" in off|shadow) ;; *) USER_MODE=off ;; esac
    printf 'flow-s1: WARN: systemOne.uses["%s"] is on only in this repository'"'"'s settings, which cannot switch a site on; using %s\n' "$SITE" "$USER_MODE" >&2
    MODE=$USER_MODE
  fi
fi
if [ "$SUB" = ask ]; then
  [ "$MODE" = on ] || none not-on
  CURRENT=uncertain
else
  [ "$MODE" = shadow ] || exit 0
  CURRENT="$DECISION"
fi

# No provider, or provider settings that cannot be read: nothing else is
# read, fetched or sent.
PROVIDER=$("$CR" --no-repo-settings --default none ".systemOne.provider" 2>/dev/null) || none settings-refused
[ "$PROVIDER" = none ] && none provider-none

# Red flags: the file is never read or sent, whatever its classification
# says. The list holds every BLOCK pattern of references/
# classification-signals.md and more key and password files than that table
# names, since refusing here costs only an estimate. Matched without regard
# to case, on the whole path and on its last component; .env.example is
# refused too.
_red_flag() {
  # LC_ALL=C on tr itself: under a UTF-8 locale macOS tr stops at the first
  # byte that is not valid UTF-8, and the rest of the path would go unchecked.
  local p base
  p=$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]')
  base="${p##*/}"
  case "$base" in
    .env|.env.*|credentials*|.netrc|.npmrc|.pgpass|.htpasswd) return 0 ;;
    id_rsa*|id_dsa*|id_ecdsa*|id_ed25519*|*.pub) return 0 ;;
    *.pem|*.key|*.p12|*.pfx|*.jks|*.keystore|*.ppk|*.asc|*.gpg) return 0 ;;
  esac
  case "$p" in
    *secret*|*password*|*credentials*) return 0 ;;
  esac
  return 1
}
_red_flag "$FILE" && none red-flag

case "$ISSUE" in
  ''|*[!0-9]*) none no-issue ;;
esac
command -v python3 >/dev/null 2>&1 || none python-missing
[ -n "$TOP" ] || none no-repository

TMP=$(mktemp -d "${TMPDIR:-/tmp}/flow-classify-s1.XXXXXX") || none internal-error
trap 'rm -rf -- "$TMP"' EXIT

# The file's status and its uncommitted change. A literal pathspec, so a path
# holding * or : is the path itself. A pathspec still matches every path under
# a directory it names, so the first entry git reports must be the path
# itself: a directory, ".", a deleted directory or a path with a trailing
# slash gets no-diff, and only that one file is ever read.
git status --porcelain=v1 -z --untracked-files=all -- ":(literal)$FILE" </dev/null > "$TMP/status" 2>/dev/null
ENTRY=""
IFS= read -r -d '' ENTRY < "$TMP/status"
[ "${ENTRY:3}" = "$FILE" ] || none no-diff
STATUS="${ENTRY:0:2}"
STATUS="${STATUS// /}"
[ -n "$STATUS" ] || none no-diff
# At most eight times the bytes sent are kept: a large file is not copied
# whole into TMPDIR. The checks below read this capped copy. A second diff
# header that starts inside the part sent is inside it, and a capped copy
# longer than the part sent marks the diff cut.
SCAN_BYTES=$((ASK_LIMIT_BYTES * 8))
if [ "$STATUS" = "??" ]; then
  git diff --no-index --no-ext-diff --no-textconv --no-color -- /dev/null "$FILE" </dev/null 2>/dev/null | head -c "$SCAN_BYTES" > "$TMP/diff.full"
else
  BASE=HEAD
  git rev-parse --verify -q HEAD >/dev/null 2>&1 </dev/null || BASE=$(git hash-object -t tree /dev/null 2>/dev/null </dev/null)
  git diff --no-ext-diff --no-textconv --no-color "$BASE" -- ":(literal)$FILE" </dev/null 2>/dev/null | head -c "$SCAN_BYTES" > "$TMP/diff.full"
fi
[ -s "$TMP/diff.full" ] || none no-diff
# One file, one diff: a tracked file replaced by a directory of staged files
# would otherwise bring their diffs along.
[ "$(grep -c '^diff --git ' "$TMP/diff.full")" = 1 ] || none no-diff
CUT=false
if grep -q '^Binary files ' "$TMP/diff.full"; then
  printf '(binary)\n' > "$TMP/diff"
else
  head -n "$ASK_LIMIT_LINES" "$TMP/diff.full" | head -c "$ASK_LIMIT_BYTES" > "$TMP/diff"
  cmp -s "$TMP/diff" "$TMP/diff.full" || CUT=true
fi

# The issue, fetched only now: off, shadow for ask, no provider and red flags
# never reach here.
# With --issue-cache the first file of a prompt fetches it and the others
# read that copy, or give up at once when that fetch failed.
[ -d "$ISSUE_CACHE" ] || ISSUE_CACHE=""
if [ -n "$ISSUE_CACHE" ] && [ -f "$ISSUE_CACHE/issue.json" ]; then
  cp -- "$ISSUE_CACHE/issue.json" "$TMP/issue.json" 2>/dev/null || none no-issue
elif [ -n "$ISSUE_CACHE" ] && [ -e "$ISSUE_CACHE/issue.failed" ]; then
  none no-issue
elif gh issue view "$ISSUE" --json number,title,body </dev/null > "$TMP/issue.json" 2>/dev/null; then
  [ -z "$ISSUE_CACHE" ] || cp -- "$TMP/issue.json" "$ISSUE_CACHE/issue.json" 2>/dev/null
else
  [ -z "$ISSUE_CACHE" ] || { : > "$ISSUE_CACHE/issue.failed"; } 2>/dev/null
  none no-issue
fi

# The state, as sorted JSON with no timestamp, so the same inputs give the
# same bytes and one state_sha256; and the record reference, which names the
# path when the --ref grammar takes it and its digest when it does not.
python3 - "$TMP" "$ISSUE" "$FILE" "$STATUS" "$SIGNALS" > "$TMP/ref" <<'PY'
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]
import hashlib
import json
import re

tmp, number, path, status, signals = sys.argv[1:6]
try:
    with open(os.path.join(tmp, "issue.json"), encoding="utf-8", errors="replace") as f:
        issue = json.load(f)
except ValueError:
    sys.exit(4)
if not isinstance(issue, dict) or not isinstance(issue.get("title"), str) \
        or not isinstance(issue.get("body") or "", str):
    sys.exit(4)
with open(os.path.join(tmp, "diff"), encoding="utf-8", errors="replace") as f:
    diff = f.read()
state = {
    "issue": {"number": int(number), "title": issue["title"], "body": issue.get("body") or ""},
    "file": {"path": path, "status": status, "diff": diff},
    "signals": [s.strip() for s in signals.split(";") if s.strip()],
}
with open(os.path.join(tmp, "state.json"), "w", encoding="utf-8") as f:
    json.dump(state, f, sort_keys=True, ensure_ascii=True)
ref = "classify:issue-%s/%s" % (int(number), path)
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:/#@+-]*", ref, re.ASCII) or len(ref) > 200:
    ref = "classify:issue-%s/sha256:%s" % (int(number), hashlib.sha256(path.encode("utf-8", "surrogateescape")).hexdigest()[:16])
sys.stdout.write(ref)
PY
case $? in
  0) ;;
  4) none no-issue ;;
  *) none internal-error ;;
esac
REF=$(cat "$TMP/ref")

S1="$SELF_DIR/flow-s1.sh"
[ -x "$S1" ] || none internal-error
"$S1" ask --site "$SITE" --state-format json --state-file "$TMP/state.json" \
  --current "$CURRENT" --ref "$REF" --run-id "$RUN_ID" </dev/null > "$TMP/out" 2> "$TMP/err"
RC=$?
[ "$SUB" = record ] && exit 0

# Warnings from the client reach the caller; its "no answer" line becomes
# S1_REASON.
grep -v '^flow-s1: no answer: ' "$TMP/err" >&2
case "$RC" in
  0) ;;
  3)
    REASON=$(sed -n 's/^flow-s1: no answer: \([A-Za-z0-9-]*\).*/\1/p' "$TMP/err" | tail -n 1)
    none "${REASON:-internal-error}" ;;
  *) none internal-error ;;
esac

if ! python3 - "$TMP/out" "$CUT" > "$TMP/answer" <<'PY'
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]
import json

try:
    with open(sys.argv[1], encoding="utf-8") as f:
        reply = json.load(f)
    p = float(reply["answers"]["serves_issue"]["p"])
    model = reply["model"]
    truncated = bool(reply.get("truncated")) or sys.argv[2] == "true"
except (ValueError, KeyError, TypeError):
    sys.exit(4)
if not isinstance(model, str) or not model.isprintable() or not 0 <= p <= 1:
    sys.exit(4)
sys.stdout.write("S1_ESTIMATE=%.2f\nS1_MODEL=%s\nS1_TRUNCATED=%s\n" % (p, model, "true" if truncated else "false"))
PY
then
  none internal-error
fi
printf 'S1_FILE=%s\n' "$FILE"
cat "$TMP/answer"
exit 0
