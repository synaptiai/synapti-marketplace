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
#   EXCEPTION_MALFORMED=<line>         (a row with fewer than four columns)
#   EXCEPTIONS_TRUNCATED=<n> row(s) not printed   (over the row cap)
#
# Exits 0 in every reported state: the section is the contract, not the exit
# code. Exits 2 only on a usage error.

set -uo pipefail

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
    -h|--help) sed -n '2,28p' "$0" | sed 's/^# \?//'; exit 0 ;;
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

echo "ENCODING=a literal | inside a value is written %7C"
echo "EXCEPTIONS_PATH=$EXC_PATH"

if [ -n "$PR_NUM" ]; then
  BASE_SHA=$(gh pr view "$PR_NUM" --repo "$REPO" --json baseRefOid --jq '.baseRefOid' 2>/dev/null)
else
  # A branch name resolves to the commit it points at, so the section reports a
  # commit rather than a moving name and two runs can be compared.
  BASE_SHA=$(gh api "repos/$REPO/commits/$REF" --jq '.sha' 2>/dev/null)
fi
if [ -z "$BASE_SHA" ]; then
  echo "STATE=unavailable"
  echo "REASON=the base commit could not be resolved, so there is no trusted ref to read the exceptions at"
  exit 0
fi
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

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:                      # pragma: no cover - Python without it
    pass

MAX_VALUE = 1000                       # characters kept from any one cell
MAX_ROWS = 100                         # rows printed


def one_line(v):
    s = "" if v is None else str(v)
    s = " ".join(s.splitlines()).replace("|", "%7C").strip()
    return s[:MAX_VALUE] + "…" if len(s) > MAX_VALUE else s


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
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        # Neither the header nor its separator is a rule.
        if not cells or set("".join(cells)) <= set("-: "):
            continue
        if cells[0].lower() == "rule":
            continue
        if len(cells) < 4:
            # A short row is a row nobody can act on: the glob is what bounds
            # which files the rule may ever apply to, and without it the rule is
            # unscoped. Name it rather than dropping it.
            out.append("EXCEPTION_MALFORMED=%s" % one_line(line))
            continue
        rows += 1
        if rows > MAX_ROWS:
            continue
        out.append("EXCEPTION=%s|%s|%s|%s" % (one_line(cells[0]), one_line(cells[1]),
                                              one_line(cells[2]), one_line(cells[3])))
    if rows > MAX_ROWS:
        out.append("EXCEPTIONS_TRUNCATED=%d row(s) not printed; read the whole file at "
                   "EXCEPTIONS_PATH as of EXCEPTIONS_REF above" % (rows - MAX_ROWS))
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
