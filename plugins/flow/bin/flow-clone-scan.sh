#!/usr/bin/env bash
# [flow] Print the verbatim duplication this branch INTRODUCED, from a real
# clone detector.
#
# Answers one question for the review commands and the task-time gate: does a
# block this change added already exist somewhere else. Pre-existing
# duplication is not the answer — a repository accumulates it, and reporting it
# on every review trains the reader to skip the section. The comparison is
# therefore against the merge base, through `jscpd --baseline-from-ref`.
#
# The detector is `jscpd` and there is no fallback. A second, hand-rolled
# detector would be measured against nothing and maintained forever; when jscpd
# is absent this prints STATE=unavailable with the install command and the
# caller proceeds. It is never installed from here: an install during a review
# is exactly what this feature promised not to do.
#
# Usage:
#   flow-clone-scan.sh --base <ref> --head <ref>
#   flow-clone-scan.sh <base>..<head>
#
# Options (each overrides the settings cascade for this run):
#   --min-lines <n>        duplication.minLines
#   --min-tokens <n>       duplication.minTokens
#   --exclude-paths <csv>  duplication.excludePaths
#   --format <csv>         restrict to these jscpd formats
#   --print-scan-set       print the enumerated file count and stop
#
# Output (per references/command-output-format.md):
#   STATE=ok|none|unavailable
#   REASON=<why>                                   (none and unavailable)
#   INSTALL=<command>                              (unavailable: no detector)
#   SCAN_BASE=<sha>                                (the merge base compared)
#   FILES_SCANNED=<n>                              (files handed to the detector)
#   FILES_ANALYZED=<n>                             (files the detector parsed, across
#     BOTH the head scan and the baseline scan of the merge base, so it is normally
#     larger than FILES_SCANNED and is not a subset of it)
#   MIN_LINES=<n> MIN_TOKENS=<n>
#   CLONE=added <file>:<a>-<b> existing <file>:<c>-<d> lines=<N> tokens=<T>
#   CLONE_WITHIN_DIFF=<file>:<a>-<b> <file>:<c>-<d> lines=<N> tokens=<T>
#
# CLONE=added is a block this change introduced that duplicates code already in
# the repository: the location is the ADDED side, because that is the side the
# author can do something about, and the existing block is named after it.
# CLONE_WITHIN_DIFF is a block duplicated twice inside this change itself —
# the same defect, but nothing pre-existing is involved.
#
# A pair whose two sides are both outside this change is NOT reported even when
# the detector marks it new. Measured on the #218 branch: 8 of the 10 pairs it
# flagged new touched no file the branch changed.
#
# FILES_SCANNED=0 is STATE=unavailable, never STATE=none. A scan that reached
# nothing and a scan that found nothing produce the same silence, and only one
# of them is a clean bill of health.
#
# A scan turned off by `duplication.enabled` is STATE=unavailable, not none:
# nobody looked, and the difference is the whole point of the three states. It
# exits 0, because a deliberate setting is not a failure.
#
# Exits 0 for ok, none, and a scan disabled by settings; 1 on a usage error; and
# 2 when the scan could not be performed — in which case STATE=unavailable is
# still printed, so a caller reading only stdout is not left to infer it.

set -uo pipefail

PROG="flow-clone-scan.sh"
JSCPD_PIN="jscpd@5.3.1"

usage() {
  printf '%s\n' "usage: $PROG --base <ref> --head <ref>" >&2
  printf '%s\n' "       $PROG <base>..<head>" >&2
}

unavailable() {
  printf '%s\n' "STATE=unavailable"
  printf '%s\n' "REASON=$1"
  [ $# -ge 2 ] && printf '%s\n' "INSTALL=$2"
  exit 2
}

# The shared range helpers. A helper that cannot load them does NOT fall back to
# an inline copy — two copies of a reference check is exactly what this removed
# — and it does not exit silently either: a caller reading only stdout would be
# left to infer the difference between a clean scan and a helper that never ran.
FLOW_LIB_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib"
# shellcheck source=lib/range-args.sh
if ! . "$FLOW_LIB_DIR/range-args.sh" 2>/dev/null; then
  unavailable "the shared range helpers could not be loaded from $FLOW_LIB_DIR"
fi

OPT_MIN_LINES=""
OPT_MIN_TOKENS=""
OPT_EXCLUDES=""
OPT_FORMAT=""
PRINT_SCAN_SET=0

# The shared part of the command line — the range and --help — is parsed by the
# library; what it does not recognise comes back in FLOW_RANGE_REST for the
# options only this helper has.
flow_range_parse_args "$@"
BASE="$FLOW_RANGE_BASE"
HEAD_REF="$FLOW_RANGE_HEAD"

set -- ${FLOW_RANGE_REST[@]+"${FLOW_RANGE_REST[@]}"}
while [ $# -gt 0 ]; do
  case "$1" in
    --min-lines) [ $# -ge 2 ] || { usage; exit 1; }; OPT_MIN_LINES="$2"; shift 2 ;;
    --min-tokens) [ $# -ge 2 ] || { usage; exit 1; }; OPT_MIN_TOKENS="$2"; shift 2 ;;
    --exclude-paths) [ $# -ge 2 ] || { usage; exit 1; }; OPT_EXCLUDES="$2"; shift 2 ;;
    --format) [ $# -ge 2 ] || { usage; exit 1; }; OPT_FORMAT="$2"; shift 2 ;;
    --print-scan-set) PRINT_SCAN_SET=1; shift ;;
    *) printf '%s\n' "$PROG: unknown option '$1'" >&2; usage; exit 1 ;;
  esac
done

[ -n "$BASE" ] && [ -n "$HEAD_REF" ] || { usage; exit 1; }
flow_range_validate "$BASE" "$HEAD_REF" || { printf '%s\n' "$PROG: invalid ref" >&2; exit 1; }

# Numeric options are validated here rather than passed through: a non-numeric
# value reaching jscpd is a silently different threshold, which is the failure
# this feature exists to prevent.
for _pair in "min-lines:$OPT_MIN_LINES" "min-tokens:$OPT_MIN_TOKENS"; do
  _name="${_pair%%:*}"; _val="${_pair#*:}"
  [ -z "$_val" ] && continue
  case "$_val" in
    ''|*[!0-9]*) printf '%s\n' "$PROG: --$_name must be a non-negative integer" >&2; exit 1 ;;
  esac
done

command -v git >/dev/null 2>&1 || unavailable "git is not available, so no scan set could be enumerated"
command -v python3 >/dev/null 2>&1 || unavailable "python3 is not available, so the detector's report could not be read"

# The settings cascade. Flags win over it; it wins over the built-in defaults.
# Resolved through the same helper every other command uses, so a project that
# overrides these keys gets the same answer here as everywhere else.
FLOW_ROOT="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")"

_resolve() {
  # $1 jq path, $2 default. A cascade that cannot be reached is not fatal: the
  # documented defaults are the contract, and they are printed below either way.
  if [ -n "$FLOW_ROOT" ] && [ -x "$FLOW_ROOT/bin/cascade-resolve.sh" ]; then
    "$FLOW_ROOT/bin/cascade-resolve.sh" --default "$2" "$1" 2>/dev/null || printf '%s\n' "$2"
  else
    printf '%s\n' "$2"
  fi
}

DEFAULT_EXCLUDES='**/test/**,**/tests/**,**/test*/**,**/vendor/**,**/node_modules/**,**/dist/**,**/*.generated.*,.decisions/**,.flow/**'

ENABLED=$(_resolve '.duplication.enabled' 'true')
MIN_LINES="${OPT_MIN_LINES:-$(_resolve '.duplication.minLines' '5')}"
MIN_TOKENS="${OPT_MIN_TOKENS:-$(_resolve '.duplication.minTokens' '20')}"
if [ -n "$OPT_EXCLUDES" ]; then
  EXCLUDES="$OPT_EXCLUDES"
else
  # `// []` matters: a source that does not carry the key would otherwise make
  # jq fail on the join, and cascade-resolve would report that whole file
  # unparseable and warn about it on every run.
  EXCLUDES=$(_resolve '(.duplication.excludePaths // []) | join(",")' "$DEFAULT_EXCLUDES")
  [ -n "$EXCLUDES" ] || EXCLUDES="$DEFAULT_EXCLUDES"
fi

case "$MIN_LINES" in ''|*[!0-9]*) MIN_LINES=5 ;; esac
case "$MIN_TOKENS" in ''|*[!0-9]*) MIN_TOKENS=20 ;; esac

if [ "$ENABLED" = "false" ]; then
  # Not `none`. A team that turned the layer off has not learned that there is
  # no duplication — nobody looked — and a caller reading STATE alone would
  # report a clean duplication review it never performed. Exit 0, because a
  # deliberate setting is not a failure and must not read as one.
  printf '%s\n' "STATE=unavailable"
  printf '%s\n' "REASON=duplication.enabled is false, so no scan was performed"
  printf '%s\n' "FILES_SCANNED=0"
  exit 0
fi

# No detector, and none is fetched. `npx`-style resolution would download and
# run a package mid-review, which is an install by another name.
if ! command -v jscpd >/dev/null 2>&1; then
  unavailable "jscpd is not installed, so no clone scan was performed" \
    "npm install -g $JSCPD_PIN"
fi

SCAN_BASE=$(git merge-base "$BASE" "$HEAD_REF" 2>/dev/null)
[ -n "$SCAN_BASE" ] || SCAN_BASE=$(git rev-parse --verify "$BASE" 2>/dev/null)
[ -n "$SCAN_BASE" ] || unavailable "neither a merge base nor the base ref itself could be resolved"

REPORT_DIR=$(mktemp -d -t flow-clone-scan.XXXXXX 2>/dev/null)
[ -n "$REPORT_DIR" ] && [ -d "$REPORT_DIR" ] || unavailable "mktemp -d failed, so the detector had nowhere to write its report"
trap 'rm -rf "$REPORT_DIR"' EXIT

PYTHONSAFEPATH=1 \
FCS_BASE="$SCAN_BASE" FCS_HEAD="$HEAD_REF" FCS_MIN_LINES="$MIN_LINES" \
FCS_MIN_TOKENS="$MIN_TOKENS" FCS_EXCLUDES="$EXCLUDES" FCS_FORMAT="$OPT_FORMAT" \
FCS_REPORT_DIR="$REPORT_DIR" FCS_PRINT_SCAN_SET="$PRINT_SCAN_SET" \
python3 - <<'PYEOF'
import json
import os
import re
import subprocess
import sys

# During a review the working directory is the repository under review, so an
# empty or "." entry on sys.path would make its files importable.
sys.path[:] = [p for p in sys.path if p not in ("", ".")]


def out(line):
    sys.stdout.write(line + "\n")


def unavailable(reason, code=2):
    out("STATE=unavailable")
    out("REASON=" + reason)
    sys.exit(code)


# Every git call after the root is known runs FROM the root. `git ls-files` is
# limited to the working directory, so a scan started in a subdirectory would
# enumerate only that subtree and report the smaller number as the whole scan
# set — a partial scan presented as a complete one.
GIT_CWD = None


def git(*args):
    try:
        r = subprocess.run(
            ["git"] + list(args), capture_output=True, text=True, cwd=GIT_CWD
        )
    except OSError as exc:
        return None, str(exc)
    if r.returncode != 0:
        return None, (r.stderr or "").strip()
    return r.stdout, None


BASE = os.environ["FCS_BASE"]
HEAD = os.environ["FCS_HEAD"]
MIN_LINES = int(os.environ["FCS_MIN_LINES"])
MIN_TOKENS = int(os.environ["FCS_MIN_TOKENS"])
REPORT_DIR = os.environ["FCS_REPORT_DIR"]
FMT = os.environ.get("FCS_FORMAT", "").strip()
EXCLUDES = [p for p in os.environ.get("FCS_EXCLUDES", "").split(",") if p.strip()]


def glob_to_re(pat):
    """Translate one exclude glob to a regex over a repo-relative path.

    `**/` matches any number of leading directories including none, `*` stops
    at a separator and `?` takes one non-separator character. Written out
    rather than taken from fnmatch, whose `*` crosses separators and would make
    `**/tests/**` and `*/tests/*` the same pattern.
    """
    i, n, out_re = 0, len(pat), ["^"]
    while i < n:
        c = pat[i]
        if pat.startswith("**/", i):
            out_re.append("(?:[^/]+/)*")
            i += 3
        elif pat.startswith("**", i):
            out_re.append(".*")
            i += 2
        elif c == "*":
            out_re.append("[^/]*")
            i += 1
        elif c == "?":
            out_re.append("[^/]")
            i += 1
        else:
            out_re.append(re.escape(c))
            i += 1
    out_re.append("$")
    return re.compile("".join(out_re))


EXCLUDE_RES = [glob_to_re(p.strip()) for p in EXCLUDES]


def excluded(path):
    return any(rx.match(path) for rx in EXCLUDE_RES)


root_out, err = git("rev-parse", "--show-toplevel")
if root_out is None:
    unavailable("not inside a git repository: " + (err or "git rev-parse failed"))
ROOT = os.path.realpath(root_out.strip())
GIT_CWD = ROOT

# The scan set is what git tracks, never a walk of the working tree. Measured:
# letting the detector walk this repository reported 1370 sources against 841
# tracked files, having picked up .git/hooks samples among other things.
listing, err = git("ls-files", "-z")
if listing is None:
    unavailable("git ls-files failed: " + (err or "unknown error"))
tracked = [p for p in listing.split("\0") if p]
scan_set = [p for p in tracked if not excluded(p)]

if os.environ.get("FCS_PRINT_SCAN_SET") == "1":
    out("STATE=ok")
    out("FILES_SCANNED=%d" % len(scan_set))
    out("FILES_TRACKED=%d" % len(tracked))
    sys.exit(0)

out_lines = []

if not scan_set:
    out("FILES_SCANNED=0")
    unavailable(
        "every tracked file was excluded, so the detector was handed nothing to read"
    )

cmd = [
    "jscpd",
    "--reporters", "json",
    "--output", REPORT_DIR,
    "--absolute",
    "--min-lines", str(MIN_LINES),
    "--min-tokens", str(MIN_TOKENS),
    "--baseline-from-ref", BASE,
    "--fail-on-empty",
    "--no-colors",
]
for pat in EXCLUDES:
    cmd += ["--ignore", pat.strip()]
if FMT:
    cmd += ["--format", FMT]
cmd += scan_set

try:
    proc = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
except OSError as exc:
    out("FILES_SCANNED=%d" % len(scan_set))
    unavailable("jscpd could not be executed: %s" % exc)

report_path = os.path.join(REPORT_DIR, "jscpd-report.json")
if not os.path.exists(report_path):
    out("FILES_SCANNED=%d" % len(scan_set))
    detail = (proc.stderr or proc.stdout or "").strip().splitlines()
    unavailable(
        "jscpd wrote no report (exit %d)%s"
        % (proc.returncode, ": " + detail[-1] if detail else "")
    )

try:
    with open(report_path) as fh:
        report = json.load(fh)
except (OSError, ValueError) as exc:
    out("FILES_SCANNED=%d" % len(scan_set))
    unavailable("jscpd's report could not be read: %s" % exc)

analyzed = int(report.get("statistics", {}).get("total", {}).get("sources", 0) or 0)
if analyzed == 0:
    out("FILES_SCANNED=%d" % len(scan_set))
    out("FILES_ANALYZED=0")
    unavailable(
        "the detector parsed none of the %d files handed to it, so nothing was "
        "examined" % len(scan_set)
    )

# Which side of a pair is the one this change added. The detector does not know
# and its ordering is not a signal: in a verified fixture it printed the
# PRE-EXISTING file first.
diff_out, err = git("diff", "--name-only", BASE + "..." + HEAD)
if diff_out is None:
    out("FILES_SCANNED=%d" % len(scan_set))
    unavailable("git diff against the merge base failed: " + (err or "unknown error"))
changed = set(p for p in diff_out.splitlines() if p)


def rel(name):
    """A report path as git spells it. --absolute makes this exact."""
    name = (name or "").split(":")[0]
    if os.path.isabs(name):
        try:
            return os.path.relpath(os.path.realpath(name), ROOT)
        except ValueError:
            return name
    return name


def field(value):
    """A literal pipe would split a downstream marker row."""
    return str(value).replace("|", "%7C")


pairs = []
for dup in report.get("duplicates", []):
    if not dup.get("isNew"):
        continue
    first, second = dup.get("firstFile", {}), dup.get("secondFile", {})
    a, b = rel(first.get("name")), rel(second.get("name"))
    a_new, b_new = a in changed, b in changed
    if not a_new and not b_new:
        # The detector's new-clone flag alone over-reports: on the #218 branch
        # 8 of 10 flagged pairs touched no changed file.
        continue
    span = (dup.get("lines", 0), dup.get("tokens", 0))
    if a_new and b_new:
        pairs.append(("within", a, first, b, second, span))
    elif a_new:
        pairs.append(("added", a, first, b, second, span))
    else:
        pairs.append(("added", b, second, a, first, span))

pairs.sort(key=lambda p: (p[0], p[1], p[2].get("start", 0), p[3]))

for kind, added, added_loc, other, other_loc, span in pairs:
    lo = "%s:%s-%s" % (field(added), added_loc.get("start", "?"), added_loc.get("end", "?"))
    ro = "%s:%s-%s" % (field(other), other_loc.get("start", "?"), other_loc.get("end", "?"))
    if kind == "added":
        out_lines.append("CLONE=added %s existing %s lines=%d tokens=%d" % (lo, ro, span[0], span[1]))
    else:
        out_lines.append("CLONE_WITHIN_DIFF=%s %s lines=%d tokens=%d" % (lo, ro, span[0], span[1]))

out("STATE=ok" if out_lines else "STATE=none")
if not out_lines:
    out("REASON=the scan completed and this change introduced no duplicated block")
out("SCAN_BASE=" + BASE)
out("FILES_SCANNED=%d" % len(scan_set))
out("FILES_ANALYZED=%d" % analyzed)
out("MIN_LINES=%d" % MIN_LINES)
out("MIN_TOKENS=%d" % MIN_TOKENS)
for line in out_lines:
    out(line)
PYEOF
exit $?
