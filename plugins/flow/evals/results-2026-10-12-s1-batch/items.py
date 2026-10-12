"""The items of issue #295's comparison, one JSON object per line on stdout:
{group, key, ref, state_file, sha256} and, for the goal set, label and kind.
run.sh and time_requests.py both read the items through this file, so they
send the same items in the same groups.

Usage: items.py goal|review <goal items.jsonl> <review directory>
"""

# Keep the working directory off sys.path before any other import.
import os, sys  # noqa: E401
try:
    _cwd = os.path.realpath(os.getcwd())
except OSError:
    _cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _cwd]

import hashlib  # noqa: E402
import json  # noqa: E402
import re  # noqa: E402


def sha(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def list_items(which, goal_items, review_dir):
    """The items in send order. Goal: the goal replay's items.jsonl, grouped by
    goal, key c<n> within the goal. Review: every confidence-<id>.json under a
    system-one-state directory, grouped by run, key <id>."""
    out, counts = [], {}
    if which == "goal":
        base = os.path.dirname(os.path.abspath(goal_items))
        with open(goal_items, encoding="utf-8") as f:
            for line in f:
                if not line.strip():
                    continue
                it = json.loads(line)
                path = it["state_file"] if os.path.isabs(it["state_file"]) else os.path.join(base, it["state_file"])
                g = it["goal"]
                n = counts.get(g, 0)
                counts[g] = n + 1
                out.append({"group": g, "key": "c%d" % n, "ref": it["ref"], "state_file": path, "sha256": sha(path),
                            "label": it["label"], "kind": it["kind"]})
    else:
        def refuse(e):
            raise e
        # An unreadable directory stops the listing: skipping it would drop
        # its findings from every send without a word.
        for root, _, files in sorted(os.walk(review_dir, onerror=refuse)):
            if os.path.basename(root) != "system-one-state":
                continue
            run = os.path.relpath(os.path.dirname(os.path.dirname(root)), review_dir)
            for name in sorted(files):
                m = re.fullmatch(r"confidence-([A-Za-z][A-Za-z0-9_-]*)\.json", name)
                if not m:
                    continue
                path = os.path.join(root, name)
                out.append({"group": run, "key": m.group(1), "ref": "batch:%s/%s" % (run, m.group(1)),
                            "state_file": path, "sha256": sha(path)})
    return out


if __name__ == "__main__":
    for item in list_items(*sys.argv[1:4]):
        print(json.dumps(item, sort_keys=True))
