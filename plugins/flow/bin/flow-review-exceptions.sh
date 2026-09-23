#!/usr/bin/env bash
# [flow] Print the team's review exceptions, read at a pull request's BASE commit.
#
# A review exception is a rule the team has already rejected a finding over.
# Reviewers are handed these so they do not raise the same finding again.
#
# The read is pinned to the base commit on purpose. The head is the author side
# of the pull request under review: a file read from there would let a pull
# request grant itself an exemption in the same diff a reviewer is supposed to
# be judging. The base is what the change merges into, and what somebody else
# already approved.
#
# Usage:
#   flow-review-exceptions.sh --repo <owner/name> --pr <number>
#   flow-review-exceptions.sh --repo <owner/name> --ref <branch-or-sha>
#
# --pr resolves the pull request base commit. --ref is for callers with no pull
# request yet: /flow:pr runs before the pull request exists, so its base is the
# default branch rather than a baseRefOid. Either way the ref is a commit the
# author of the change under review does not control.
#
# Output (per references/command-output-format.md):
#   ENCODING=a literal | inside a value is written %7C
#   EXCEPTIONS_PATH=.flow/review-exceptions.md
#   EXCEPTIONS_REF=<base commit sha>
#   STATE=ok|none|unavailable
#   REASON=<why>                       (unavailable and none)
#   EXCEPTION=<rule>|<glob>|<why>|<source>        (one per row, STATE=ok)
#     A cell longer than 1000 characters is cut and ends in an ellipsis; a
#     literal pipe inside a cell is written %7C, and the GFM escape \| is
#     read as one pipe rather than a column break.
#   EXCEPTION_MALFORMED=<line>         (a row with fewer than four columns)
#   EXCEPTIONS_TRUNCATED=<n> row(s) not printed   (over the row cap)
#
# Exits 0 in every reported state: the section is the contract, not the exit
# code. Exits 2 only on a usage error.

set -uo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH

# Fold a value onto one line before printing it back, matching the Python
# one_line() below that the row renderer already uses. Everything a caller
# reads is read by line, so a value carrying a real newline forges a field
# nobody wrote: `--path $'probe\nFORGED=1'` printed `EXCEPTIONS_PATH=probe`
# followed by a forged `FORGED=1` line of its own. Defined here rather than
# beside its first use because the argument loop above the first emission runs
# before anything further down is read.
one_line() {
  printf '%s' "$1" | LC_ALL=C tr '\000-\037\177' ' '
}

REPO=""
PR_NUM=""
REF=""
EXC_PATH=".flow/review-exceptions.md"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -lt 2 ] && { echo "flow-review-exceptions.sh: --repo requires a value" >&2; exit 2; }; REPO="$2"; shift 2 ;;
    --pr)   [ $# -lt 2 ] && { echo "flow-review-exceptions.sh: --pr requires a value" >&2; exit 2; };   PR_NUM="$2"; shift 2 ;;
    --ref)  [ $# -lt 2 ] && { echo "flow-review-exceptions.sh: --ref requires a value" >&2; exit 2; };  REF="$2"; shift 2 ;;
    --path) [ $# -lt 2 ] && { echo "flow-review-exceptions.sh: --path requires a value" >&2; exit 2; }; EXC_PATH="$2"; shift 2 ;;
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "flow-review-exceptions.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$REPO" ] || { echo "flow-review-exceptions.sh: --repo is required" >&2; exit 2; }
if [ -n "$PR_NUM" ] && [ -n "$REF" ]; then
  echo "flow-review-exceptions.sh: pass --pr or --ref, not both" >&2; exit 2
fi
if [ -z "$PR_NUM" ] && [ -z "$REF" ]; then
  echo "flow-review-exceptions.sh: --pr or --ref is required" >&2; exit 2
fi
if [ -n "$PR_NUM" ]; then
  case "$PR_NUM" in
    *[!0-9]*) echo "flow-review-exceptions.sh: --pr must be an all-digit pull request number" >&2; exit 2 ;;
  esac
fi

echo "ENCODING=a literal | inside a value is written %7C; a value that ends … was cut at 1000 characters"
echo "EXCEPTIONS_PATH=$(one_line "$EXC_PATH")"

if [ -n "$PR_NUM" ]; then
  # The base branch is chosen by whoever opened the pull request
  # (`gh pr create --base <branch>`), so baseRefOid alone is NOT outside the
  # author control this design rests on: push a branch carrying your own
  # exceptions, target it, collect the exemptions, then retarget to the default
  # branch. The ref is trusted only when the base IS the repository default.
  BASE_INFO=$(gh pr view "$PR_NUM" --repo "$REPO" --json baseRefOid,baseRefName --jq '"\(.baseRefOid) \(.baseRefName)"' 2>/dev/null)
  if [ -z "$BASE_INFO" ]; then
    # Distinct from an untrusted base: nothing was read, so nothing is known
    # about what the author chose.
    echo "STATE=unavailable"
    echo "REASON=the pull request could not be read, so the base it targets is unknown"
    exit 0
  fi
  BASE_SHA=${BASE_INFO%% *}
  BASE_NAME=${BASE_INFO#* }
  DEFAULT_NAME=$(gh repo view "$REPO" --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null)
  if [ -z "$DEFAULT_NAME" ]; then
    echo "STATE=unavailable"
    echo "REASON=the default branch could not be resolved, so whether the pull request base is a trusted source of exceptions is unknown"
    exit 0
  fi
  if [ "$BASE_NAME" != "$DEFAULT_NAME" ]; then
    echo "EXCEPTIONS_BASE=$(one_line "$BASE_NAME")"
    echo "STATE=unavailable"
    echo "REASON=the pull request targets $(one_line "$BASE_NAME"), not the default branch $(one_line "$DEFAULT_NAME"); a base the author chose is not a trusted source of exceptions"
    exit 0
  fi
else
  # A branch name resolves to the commit it points at, so the section reports a
  # commit rather than a moving name and two runs can be compared.
  BASE_SHA=$(gh api "repos/$REPO/commits/$REF" --jq '.sha' 2>/dev/null)
fi
# `gh api --jq` does not apply the filter on a non-2xx: it prints the raw error
# body, which would otherwise be announced as the commit the rules were read at.
case "$BASE_SHA" in
  ''|*[!0-9a-fA-F]*)
    echo "STATE=unavailable"
    echo "REASON=the base commit could not be resolved to a commit id, so there is no trusted ref to read the exceptions at"
    exit 0 ;;
esac
echo "EXCEPTIONS_REF=$BASE_SHA"

# `-i` keeps the response status, so an absent file and an unreadable one are
# told apart by the protocol rather than by the wording of an error message,
# which changes with the gh version and the locale. A 404 is the only absent;
# 403, 5xx and a dead network are unreadable.
RESP=$(gh api -i "repos/$REPO/contents/$EXC_PATH?ref=$BASE_SHA" 2>/dev/null)

OUT=$(FLOW_RX_RESP="$RESP" PYTHONSAFEPATH=1 python3 - <<'PYEOF'
import sys
# The pull request is checked out around this call, so the author controls what
# sits in the working directory. Drop it from the import path before importing
# anything that is not built in.
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
import base64
import json
import os
import re

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:                      # pragma: no cover - Python without it
    pass

MAX_VALUE = 1000                       # characters kept from any one cell
MAX_ROWS = 100                         # rules printed
MAX_MALFORMED = 20                     # malformed rows named before they are capped


def split_cells(line):
    """Split a table row on unescaped pipes.

    GFM escapes a literal pipe inside a cell as a backslash-pipe, which this
    project's own `references/finding-schema.md` mandates. Splitting on every
    pipe shifted every column right of the escape: the scope glob became a
    fragment of the rule, and the rule then matched no file and silently never
    applied, while the promoter wrote the shifted row into the contract.
    """
    parts = re.split(r"(?<!\\)\|", line)
    return [q.replace("\\|", "|").strip() for q in parts]


def one_line(v):
    s = "" if v is None else str(v)
    s = " ".join(s.splitlines()).strip()
    # Truncate before escaping. A cell of literal pipes would otherwise be cut
    # at a third of the documented length, because each pipe becomes three
    # characters first.
    if len(s) > MAX_VALUE:
        s = s[:MAX_VALUE] + "…"
    return s.replace("|", "%7C")


# Nothing is printed until the whole file has been read. Announcing STATE=ok and
# then failing partway reads exactly like a project with no exceptions, and a
# reviewer would raise findings the team has already rejected.
out = []
try:
    resp = os.environ["FLOW_RX_RESP"]
    head, _, body = resp.partition("\r\n\r\n")
    if not body:
        head, _, body = resp.partition("\n\n")
    status = head.split()[1] if len(head.split()) > 1 else ""
    if status == "404":
        print("STATE=none")
        print("REASON=the base commit carries no exceptions file at that path")
        sys.exit(0)
    if status != "200":
        print("STATE=unavailable")
        print("REASON=the exceptions file could not be read from the API (HTTP %s)" % one_line(status or "no status"))
        sys.exit(0)
    content = json.loads(body).get("content") or ""
    if not content.strip():
        print("STATE=unavailable")
        print("REASON=the API served no content for the exceptions file: it is empty, or too large to serve inline")
        sys.exit(0)
    text = base64.b64decode(content).decode("utf-8", errors="replace")
    rows = 0
    malformed = 0
    nonblank = 0
    table_lines = 0
    for line in text.splitlines():
        line = line.strip()
        if line:
            nonblank += 1
        if not line.startswith("|"):
            continue
        table_lines += 1
        cells = split_cells(line.strip("|"))
        # Neither the header nor its separator is a rule.
        if not cells or set("".join(cells)) <= set("-: "):
            continue
        if cells[0].lower() == "rule":
            continue
        if len(cells) < 4 or not cells[1]:
            # A row nobody can act on. The glob bounds which files the rule may
            # ever apply to, so a row without one — missing entirely or written
            # empty — is unscoped, and an unscoped rule read as matching
            # everything is the highest-leverage row an attacker or a careless
            # promotion can produce. Name it rather than dropping it, but do not
            # let a file of them bury the rest of the section.
            malformed += 1
            if malformed <= MAX_MALFORMED:
                out.append("EXCEPTION_MALFORMED=%s" % one_line(line))
            continue
        rows += 1
        if rows > MAX_ROWS:
            continue
        out.append("EXCEPTION=%s|%s|%s|%s" % (one_line(cells[0]), one_line(cells[1]),
                                              one_line(cells[2]), one_line(cells[3])))
    if rows > MAX_ROWS or malformed > MAX_MALFORMED:
        out.append("EXCEPTIONS_TRUNCATED=%d rule(s) and %d malformed row(s) not printed; read the "
                   "whole file at EXCEPTIONS_PATH as of EXCEPTIONS_REF above"
                   % (max(0, rows - MAX_ROWS), max(0, malformed - MAX_MALFORMED)))
    if nonblank and not table_lines:
        # Content that is not a table at all. Reporting STATE=ok with no rows
        # would tell every reviewer the team has rejected nothing, which is the
        # answer that lets an argued-down finding be raised again.
        print("STATE=unavailable")
        print("REASON=the file at the base commit has content but no table rows, so it could not be read as an exceptions table")
        sys.exit(0)
except Exception as exc:
    print("STATE=unavailable")
    print("REASON=the exceptions file at the base commit did not read as a table: %s" % one_line(exc))
    sys.exit(0)

print("STATE=ok")
for line in out:
    print(line)
PYEOF
)
READ_EXIT=$?

# A reader that died mutely would leave the section with no STATE line at all,
# and every rule keyed on it silently does not fire.
if [ "$READ_EXIT" -ne 0 ] || [ "$(printf '%s\n' "$OUT" | grep -c '^STATE=')" != "1" ]; then
  echo "STATE=unavailable"
  echo "REASON=the exceptions reader did not complete (exit $READ_EXIT), so whether the team has recorded any exception is unknown"
  exit 0
fi

printf '%s\n' "$OUT"
