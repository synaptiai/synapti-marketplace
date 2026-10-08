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
#                              --decision include|include-cleanup|exclude
#                              [--run-id <id>] [--issue-cache <dir>]
#   flow-classify-s1.sh mode
#
#   --file      the changed file, relative to the top of the repository
#   --issue     the issue number; empty, "(none)" or anything that is not a
#               number means there is no issue, and nothing is asked
#   --signals   the classification signals that matched the file, separated
#               by ";"
#   --decision  the user's choice, written into the record as `current`:
#               include (the change is part of the issue's work),
#               include-cleanup (included as cleanup, in a separate improve:
#               or chore: commit) or exclude (left out)
#   --run-id    records go to .flow/runs/<id>/system-one.jsonl when that run
#               exists; empty means none
#   --issue-cache  a directory the caller made for one prompt: the issue is
#               fetched once for every file of that prompt, and a failed fetch
#               is not tried again; after a call that timed out, could not
#               connect or got a 5xx status, the provider is not asked again
#               in that prompt (provider-unavailable). Empty means each file
#               is on its own
#
# ask runs only when the site is `on`, and record only when it is `shadow`,
# so the provider is asked at most once per file per prompt. The mode is the
# one bin/flow-s1-mode.sh gives, read from the top of the repository: a
# repository's settings can lower the user's mode but never raise it.
#
# mode prints that mode (off, shadow, on, or a value the client treats as
# off) and exits 0; it prints nothing when the user's settings cannot be
# read. The record block asks it first and prints nothing unless it is
# shadow.
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
# provider-unavailable, python-missing, internal-error.
# record prints nothing and exits 0 when it wrote the record, or when the
# site is not in shadow mode and there is nothing to record. In shadow mode
# with no record written it prints S1_REASON=<reason> (one of the reasons
# above, or record-write-failed) and exits 3. Both exit 2 on wrong arguments.
#
# What is sent: the issue's number, title and body, the file's path, its git
# status and its uncommitted diff (the whole file when untracked, "(binary)"
# for a binary file, at most the first 400 lines and 64 KiB of a longer diff),
# and the signals. At most 512 KiB of the diff is kept; git reads the whole
# file to diff it and to hash it.
# A file whose path matches a red-flag pattern is never read or sent, nor is
# a file git reports as renamed from such a path, nor a file whose content is
# the same as a red-flag file's in the last commit or the index (a copy, or a
# move git does not report as one). An empty file is checked by its path
# alone: it has no content to protect. A copy of a red-flag file that was
# never committed or staged is not recognised. The issue fetch is given at
# most 10 seconds.

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
  printf 'usage: flow-classify-s1.sh mode | ask|record --file <path> --issue <N> --signals <text> [--decision include|include-cleanup|exclude] [--run-id <id>] [--issue-cache <dir>]\n' >&2
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
  ask|record|mode) shift ;;
  *) usage "the first argument must be ask, record or mode" ;;
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
if [ "$SUB" = mode ]; then
  [ "$HAVE_FILE" = 0 ] && [ "$HAVE_DECISION" = 0 ] && [ -z "$ISSUE$SIGNALS$RUN_ID$ISSUE_CACHE" ] || usage "mode takes no arguments"
else
  [ "$HAVE_FILE" = 1 ] && [ -n "$FILE" ] || usage "--file is required"
fi
if [ "$SUB" = record ]; then
  case "$DECISION" in include|include-cleanup|exclude) ;; *) usage "--decision must be include, include-cleanup or exclude" ;; esac
else
  [ "$HAVE_DECISION" = 0 ] || usage "--decision is for record only"
fi
if [ -n "$RUN_ID" ]; then
  case "$RUN_ID" in *..*|*/*) usage "--run-id contains '..' or '/'" ;; esac
  (LC_ALL=C; [[ "$RUN_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]) || usage "--run-id must start with a letter or digit and use only [A-Za-z0-9._-]"
fi

# none <reason>: ask prints that there is no estimate, and why. record
# prints the reason and exits 3 once the mode is known to be shadow, since a
# record was due and none is written; before that it prints nothing. Either
# way the caller does what it did before.
SHADOW=0
none() {
  if [ "$SUB" = ask ]; then
    printf 'S1_FILE=%s\nS1_ESTIMATE=none\nS1_REASON=%s\n' "$FILE" "$1"
  elif [ "$SHADOW" = 1 ]; then
    printf 'S1_REASON=%s\n' "$1"
    exit 3
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

# The user's own settings are read first, as bin/flow-s1.sh reads them: when
# the resolver refuses (the plugin is inside the repository), the user's mode
# is unknown and the answer is settings-refused, never a mode taken to be off.
PROVIDER=$("$CR" --no-repo-settings --default none ".systemOne.provider" 2>/dev/null) || none settings-refused

# The mode comes from bin/flow-s1-mode.sh, the one place that decides it, so
# it is the mode the client uses: a repository's settings can lower the
# user's mode but never raise it. Only its own warnings (flow-s1: WARN:, for
# a repository value it lowered) reach the caller: the resolver's warnings
# about a settings file it could not parse are shown by bin/flow-s1.sh when
# it runs, so passing them on here would show each one twice. Any failure
# means off. Its stdout goes to fd 3, the capture; its stderr to the filter.
MODE_HELPER="$SELF_DIR/flow-s1-mode.sh"
MODE=off
[ -x "$MODE_HELPER" ] && { MODE=$( { "$MODE_HELPER" --all "$SITE" </dev/null 2>&1 1>&3 3>&- | { grep '^flow-s1: WARN: ' >&2 || :; }; } 3>&1 ) || MODE=off; }
if [ "$SUB" = mode ]; then
  printf '%s\n' "$MODE"
  exit 0
elif [ "$SUB" = ask ]; then
  [ "$MODE" = on ] || none not-on
  CURRENT=uncertain
else
  [ "$MODE" = shadow ] || exit 0
  SHADOW=1
  CURRENT="$DECISION"
fi

# No provider: nothing else is read, fetched or sent.
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
  _red_flag_lc "$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
}
# _red_flag_lc <path already in lower case>: the match itself, with no
# command started, for the copy check's loop over many paths.
_red_flag_lc() {
  local p="$1" base
  base="${p##*/}"
  case "$base" in
    .env|.env.*|*.env|.envrc|credentials*|.netrc|.npmrc|.pgpass|.htpasswd) return 0 ;;
    .pypirc|.dockercfg|*.tfvars|*.tfstate|*.tfstate.*|*kubeconfig*|*.ovpn) return 0 ;;
    service-account*.json) return 0 ;;
    id_rsa*|id_dsa*|id_ecdsa*|id_ed25519*|*.pub) return 0 ;;
    *.pem|*.key|*.p12|*.pfx|*.jks|*.keystore|*.ppk|*.asc|*.gpg) return 0 ;;
  esac
  case "$p" in
    *secret*|*password*|*credentials*) return 0 ;;
    .docker/config.json|*/.docker/config.json|.kube/config|*/.kube/config) return 0 ;;
  esac
  return 1
}
_red_flag "$FILE" && none red-flag

case "$ISSUE" in
  ''|*[!0-9]*) none no-issue ;;
esac
command -v python3 >/dev/null 2>&1 || none python-missing
[ -n "$TOP" ] || none no-repository
[ -d "$ISSUE_CACHE" ] || ISSUE_CACHE=""
# An earlier file of this prompt found the provider unreachable or failing.
[ -n "$ISSUE_CACHE" ] && [ -e "$ISSUE_CACHE/provider.failed" ] && none provider-unavailable

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
BASE=HEAD
git rev-parse --verify -q HEAD >/dev/null 2>&1 </dev/null || BASE=$(git hash-object -t tree /dev/null 2>/dev/null </dev/null)
# The file's size, read only for a regular file. An empty file has no
# content to protect, and every empty file has the same blob, which git also
# pairs as a rename: an empty file is checked by its path alone, so a
# tracked secrets/.gitkeep does not refuse every new __init__.py.
FILE_SIZE=""
[ -f "$FILE" ] && FILE_SIZE=$(wc -c < "$FILE" 2>/dev/null | tr -d ' ')
case "$FILE_SIZE" in ''|*[!0-9]*) FILE_SIZE="" ;; esac
# A file git reports as renamed or copied from a red-flag path (git mv .env
# notes.md) carries that file's content: refused like the path itself. The
# whole tree is compared, since a pathspec would hide the source.
if [ "$STATUS" != "??" ] && [ "$FILE_SIZE" != 0 ]; then
  git diff --no-ext-diff -M -C -z --name-status "$BASE" </dev/null > "$TMP/moves" 2>/dev/null || none internal-error
  while IFS= read -r -d '' MV_ST; do
    case "$MV_ST" in
      R*|C*)
        IFS= read -r -d '' MV_SRC || break
        IFS= read -r -d '' MV_DST || break
        [ "$MV_DST" = "$FILE" ] && _red_flag "$MV_SRC" && none red-flag ;;
      *) IFS= read -r -d '' MV_SRC || break ;;
    esac
  done < "$TMP/moves"
fi
# A file with the same content as a red-flag file in the last commit or the
# index carries that content, whatever git calls it: cp .env notes.md, or mv
# .env notes.md without git mv, which git reports as untracked. An empty file
# is not hashed. grep keeps the entries that hold the file's blob id, so the
# shell loop reads only those and not every tracked path; when grep fails,
# the loop reads the whole listing. The entries are put in lower case once,
# so no command is started per entry.
if [ -n "$FILE_SIZE" ] && [ "$FILE_SIZE" -gt 0 ] \
   && FILE_BLOB=$(git hash-object -- "$FILE" 2>/dev/null </dev/null) && [ -n "$FILE_BLOB" ]; then
  { git ls-tree -r -z "$BASE" </dev/null 2>/dev/null; git ls-files -s -z </dev/null 2>/dev/null; } > "$TMP/blobs"
  LC_ALL=C grep -azF -- "$FILE_BLOB" "$TMP/blobs" > "$TMP/blob-hits" 2>/dev/null
  [ $? -le 1 ] || cp -- "$TMP/blobs" "$TMP/blob-hits" 2>/dev/null || none internal-error
  LC_ALL=C tr '[:upper:]' '[:lower:]' < "$TMP/blob-hits" > "$TMP/blob-hits.lc" 2>/dev/null || none internal-error
  while IFS= read -r -d '' BL_ENTRY; do
    BL_META="${BL_ENTRY%%$'\t'*}"
    case " $BL_META " in
      *" $FILE_BLOB "*) _red_flag_lc "${BL_ENTRY#*$'\t'}" && none red-flag ;;
    esac
  done < "$TMP/blob-hits.lc"
fi
# At most eight times the bytes sent are kept: a large file is not copied
# whole into TMPDIR. The checks below read this capped copy. A second diff
# header that starts inside the part sent is inside it, and a capped copy
# longer than the part sent marks the diff cut.
SCAN_BYTES=$((ASK_LIMIT_BYTES * 8))
if [ "$STATUS" = "??" ]; then
  git diff --no-index --no-ext-diff --no-textconv --no-color -- /dev/null "$FILE" </dev/null 2>/dev/null | head -c "$SCAN_BYTES" > "$TMP/diff.full"
else
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
# read that copy, or give up at once when that fetch failed. gh is given
# GH_LIMIT_S seconds, it and anything it started are then stopped: a stalled
# connection or a credential prompt is a failed fetch.
GH_LIMIT_S=10
_gh_issue() {
  python3 -I -c '
import os, signal, subprocess, sys
try:
    p = subprocess.Popen(["gh", "issue", "view", sys.argv[1], "--json", "number,title,body"],
                         stdin=subprocess.DEVNULL, stdout=sys.stdout, stderr=subprocess.DEVNULL,
                         start_new_session=True)
except OSError:
    sys.exit(127)
try:
    sys.exit(p.wait(timeout=float(sys.argv[2])))
except subprocess.TimeoutExpired:
    try:
        os.killpg(p.pid, signal.SIGKILL)
    except OSError:
        pass
    p.wait()
    sys.exit(124)
' "$ISSUE" "$GH_LIMIT_S"
}
if [ -n "$ISSUE_CACHE" ] && [ -f "$ISSUE_CACHE/issue.json" ]; then
  cp -- "$ISSUE_CACHE/issue.json" "$TMP/issue.json" 2>/dev/null || none no-issue
elif [ -n "$ISSUE_CACHE" ] && [ -e "$ISSUE_CACHE/issue.failed" ]; then
  none no-issue
elif _gh_issue </dev/null > "$TMP/issue.json" 2>/dev/null; then
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
REASON=""
[ "$RC" != 3 ] || REASON=$(sed -n 's/^flow-s1: no answer: \([A-Za-z0-9-]*\).*/\1/p' "$TMP/err" | tail -n 1)
# A provider that timed out, could not be reached or failed with a 5xx
# status is not asked again in this prompt: each further call would wait as
# long.
case "$REASON" in
  timeout|connection|http-5[0-9][0-9])
    [ -z "$ISSUE_CACHE" ] || { : > "$ISSUE_CACHE/provider.failed"; } 2>/dev/null ;;
esac

if [ "$SUB" = record ]; then
  # The client writes a record for every call that reached the provider,
  # answered or not; any other reason means it stopped before that.
  case "$RC:$REASON" in
    0:|3:shadow|3:timeout|3:connection|3:redirect|3:http-*|3:malformed|3:missing-answer|3:abstained|3:below-threshold) ;;
    3:?*) none "$REASON" ;;
    *) none internal-error ;;
  esac
  grep -q '^flow-s1: WARN: not writing records' "$TMP/err" && none record-write-failed
  exit 0
fi

# Warnings from the client reach the caller; its "no answer" line becomes
# S1_REASON.
grep -v '^flow-s1: no answer: ' "$TMP/err" >&2
case "$RC" in
  0) ;;
  3) none "${REASON:-internal-error}" ;;
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
