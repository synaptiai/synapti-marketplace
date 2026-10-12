#!/usr/bin/env python3
"""Merge the labelled sets of issue #297's measurement.

commands.jsonl = candidates.jsonl (real commands) with the label and reason
from labels-real.jsonl, then constructed-commands.jsonl. texts.jsonl =
texts-real.jsonl, then texts-constructed.jsonl. Refuses a candidate with no
label, a label that is not destructive or harmless, a label for an unknown
id, and a repeated id.

Usage: merge_sets.py [--dir <dir>]
"""

# Keep the working directory off sys.path before any other import.
import os, sys  # noqa: E401
try:
    _cwd = os.path.realpath(os.getcwd())
except OSError:
    _cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _cwd]

import argparse  # noqa: E402
import json  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


def read(d, name):
    with open(os.path.join(d, name), encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def write(d, name, rows):
    seen = set()
    for r in rows:
        if r["id"] in seen:
            sys.exit("merge_sets.py: id %s repeats in %s" % (r["id"], name))
        seen.add(r["id"])
    with open(os.path.join(d, name), "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, sort_keys=True) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=HERE)
    d = ap.parse_args().dir
    cands = read(d, "candidates.jsonl")
    labels = {x["id"]: x for x in read(d, "labels-real.jsonl")}
    ids = {c["id"] for c in cands}
    extra = sorted(set(labels) - ids)
    if extra:
        sys.exit("merge_sets.py: labels for unknown ids: %s" % ", ".join(extra))
    out = []
    for c in cands:
        lab = labels.get(c["id"])
        if not lab or lab.get("label") not in ("destructive", "harmless") or not lab.get("reason"):
            sys.exit("merge_sets.py: candidate %s has no valid label and reason" % c["id"])
        out.append(dict(c, label=lab["label"], reason=lab["reason"]))
    write(d, "commands.jsonl", out + read(d, "constructed-commands.jsonl"))
    write(d, "texts.jsonl", read(d, "texts-real.jsonl") + read(d, "texts-constructed.jsonl"))
    print("COMMANDS=%d TEXTS=%d" % (len(out) + len(read(d, "constructed-commands.jsonl")),
                                    len(read(d, "texts-real.jsonl")) + len(read(d, "texts-constructed.jsonl"))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
