"""The Python half of bin/flow-finding-state.sh: the state a System One
question about one review finding is asked with, built from the finding and
the code it cites.

Used by bin/_flow_s1_confidence.py (review.confidence) and by any replay over
recorded findings, so a replayed state is byte for byte the state sent live:
the same tree, finding and head give the same bytes (keys sorted, no clock),
and so the same state_sha256 in the System One records.

The state:
  {"finding": {"priority", "category", "problem"},
   "code": [{"path", "head", "start", "end", "cited_start", "cited_end",
             "text"}]}
One code entry per location that cites a line, at most MAX_LOCATIONS, in the
finding's order (`locations` when the finding has it, as a merged finding
does, otherwise `location`). Each window is the cited lines and WINDOW_MARGIN
lines either side, clipped to the file; a cited range longer than MAX_CITED
lines is cut to its first MAX_CITED. Nothing names the finding's id, its
reviewers, its confidence or its suggested fix.

The cited code is read as files under the tree, never through git and never
by running anything from it: the tree may be someone else's pull request.
A location is refused (path-refused) when it is absolute, has a `..`
segment, a backslash or a control character, passes through a symlink at
any component, or is not a regular file. The walk starts at the tree's real
path and refuses every `..` segment and every symlink on the way, so it
cannot leave the tree. The file is opened without following a symlink and
without waiting on a FIFO.

Skip reasons: invalid-finding, no-line, path-refused, file-missing,
line-out-of-range, not-text.
"""

# The guard below must stay verbatim (tests/syspath-guard.test.sh matches it)
# and must run before the other imports, so ruff's rules on one import per
# line and imports at the top do not apply to this file.
# ruff: noqa: E401, E402
# Keep the working directory (the repository) off sys.path before any other
# import; tests/syspath-guard.test.sh has the reasons.
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]

import argparse
import json
import re
import stat

MAX_LOCATIONS = 3
WINDOW_MARGIN = 30
MAX_CITED = 120
MAX_PROBLEM = 2000
PRIORITIES = ("P1", "P2", "P3")
LOCATION_RE = re.compile(r"^(.+):([0-9]{1,9})(?:-([0-9]{1,9}))?$")
HEAD_RE = re.compile(r"^[0-9a-f]{7,64}$")


class Skip(Exception):
    def __init__(self, reason):
        Exception.__init__(self, reason)
        self.reason = reason


def _text(v):
    return isinstance(v, str) and v.strip() != ""


def locations_of(finding):
    """The finding's locations in order: `locations` when it is a list,
    otherwise `location`."""
    locs = finding.get("locations")
    if isinstance(locs, list) and locs:
        if not all(_text(x) for x in locs):
            raise Skip("invalid-finding")
        return locs
    return [finding["location"]]


def check_finding(finding):
    if not isinstance(finding, dict):
        raise Skip("invalid-finding")
    if finding.get("priority") not in PRIORITIES:
        raise Skip("invalid-finding")
    for key in ("category", "problem", "location"):
        if not _text(finding.get(key)):
            raise Skip("invalid-finding")
    if "locations" in finding and not isinstance(finding["locations"], list):
        raise Skip("invalid-finding")


def cited(finding):
    """[(path, first line, last line)] for the locations that cite a line,
    and whether more than MAX_LOCATIONS did."""
    out = []
    for loc in locations_of(finding):
        m = LOCATION_RE.match(loc)
        if not m:
            continue
        first = int(m.group(2))
        last = int(m.group(3)) if m.group(3) else first
        if last < first:
            last = first
        out.append((m.group(1), first, last))
    if not out:
        raise Skip("no-line")
    return out[:MAX_LOCATIONS], len(out) > MAX_LOCATIONS


def segments(path):
    """The path's segments without empty and "." ones."""
    return [p for p in path.split("/") if p and p != "."]


def open_cited(tree, path):
    """An open binary file for `path` under `tree`, or Skip."""
    if path.startswith("/") or "\\" in path or any(ord(c) < 32 or ord(c) == 127 for c in path):
        raise Skip("path-refused")
    parts = segments(path)
    if not parts or ".." in parts:
        raise Skip("path-refused")
    cur = tree
    for n, part in enumerate(parts):
        cur = os.path.join(cur, part)
        try:
            st = os.lstat(cur)
        except FileNotFoundError:
            raise Skip("file-missing")
        except NotADirectoryError:
            raise Skip("file-missing")
        except OSError:
            raise Skip("path-refused")
        if stat.S_ISLNK(st.st_mode):
            raise Skip("path-refused")
        if n < len(parts) - 1 and not stat.S_ISDIR(st.st_mode):
            raise Skip("file-missing")
    if not stat.S_ISREG(st.st_mode):
        raise Skip("path-refused")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
    try:
        fd = os.open(cur, flags)
    except OSError:
        raise Skip("path-refused")
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise Skip("path-refused")
    except BaseException:
        os.close(fd)
        raise
    return os.fdopen(fd, "rb")


def window(tree, head, path, first, last):
    if last - first + 1 > MAX_CITED:
        last = first + MAX_CITED - 1
    start = max(1, first - WINDOW_MARGIN)
    end = last + WINDOW_MARGIN
    lines = []
    total = 0
    with open_cited(tree, path) as f:
        for n, raw in enumerate(f, 1):
            total = n
            if n >= start:
                lines.append(raw)
            if n >= end:
                break
    if first < 1 or first > total:
        raise Skip("line-out-of-range")
    end = min(end, total)
    last = min(last, total)
    text = []
    for raw in lines:
        if raw.endswith(b"\n"):
            raw = raw[:-1]
        if b"\0" in raw:
            raise Skip("not-text")
        try:
            text.append(raw.decode("utf-8"))
        except UnicodeDecodeError:
            raise Skip("not-text")
    return {"path": "/".join(segments(path)), "head": head,
            "start": start, "end": end, "cited_start": first, "cited_end": last,
            "text": "\n".join(text)}


def build(tree, finding, head):
    """(state bytes, more than MAX_LOCATIONS cited). Raises Skip."""
    check_finding(finding)
    locs, more = cited(finding)
    tree = os.path.realpath(tree)
    head = head if isinstance(head, str) and HEAD_RE.match(head) else "worktree"
    code = [window(tree, head, p, a, b) for p, a, b in locs]
    state = {"finding": {"priority": finding["priority"], "category": finding["category"],
                         "problem": finding["problem"][:MAX_PROBLEM]},
             "code": code}
    data = json.dumps(state, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return data.encode("utf-8"), more


def main():
    ap = argparse.ArgumentParser()
    for name in ("tree", "finding", "head"):
        ap.add_argument("--" + name, default="")
    a = ap.parse_args()
    if not a.tree or not os.path.isdir(a.tree):
        sys.stderr.write("flow-finding-state: --tree is not a directory\n")
        return 2
    try:
        with open(a.finding, encoding="utf-8") as f:
            finding = json.load(f)
    except (OSError, ValueError, RecursionError):
        sys.stdout.write("SKIP=invalid-finding\n")
        return 4
    try:
        data, _more = build(a.tree, finding, a.head)
    except Skip as e:
        sys.stdout.write("SKIP=%s\n" % e.reason)
        return 4
    sys.stdout.buffer.write(data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
