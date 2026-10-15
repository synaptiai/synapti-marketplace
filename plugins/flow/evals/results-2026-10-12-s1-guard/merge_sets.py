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
    rows = []
    try:
        with open(os.path.join(d, name), encoding="utf-8") as f:
            lines = list(f)
    except (OSError, UnicodeDecodeError) as e:
        sys.exit("merge_sets.py: cannot read %s: %s" % (name, e))
    for n, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            r = json.loads(line)
        except ValueError as e:
            sys.exit("merge_sets.py: %s line %d is not JSON: %s" % (name, n, e))
        if not isinstance(r, dict) or not isinstance(r.get("id"), str):
            sys.exit("merge_sets.py: %s line %d has no id" % (name, n))
        rows.append(r)
    return rows


def check(name, rows):
    seen = set()
    for r in rows:
        if r["id"] in seen:
            sys.exit("merge_sets.py: id %s repeats in %s" % (r["id"], name))
        seen.add(r["id"])


def write_all(d, sets):
    """Write each set to a temporary file, and replace the sets only when
    every one was written, so a failure leaves them all as they were."""
    tmps, olds, done = [], {}, []
    try:
        for name, rows in sets:
            tmp = os.path.join(d, "." + name + ".tmp")
            tmps.append(tmp)
            with open(tmp, "w", encoding="utf-8") as f:
                for r in rows:
                    f.write(json.dumps(r, sort_keys=True) + "\n")
        for name, _ in sets:
            path = os.path.join(d, name)
            # A regular file is kept to put back; anything else in its place
            # makes the replace fail below.
            if os.path.isfile(path) and not os.path.islink(path):
                with open(path, "rb") as f:
                    olds[name] = f.read()
        for (name, _), tmp in zip(sets, tmps):
            os.replace(tmp, os.path.join(d, name))
            done.append(name)
    except OSError as e:
        # Put back the sets already replaced, and remove the temporary files.
        for name in done:
            try:
                if name in olds:
                    with open(os.path.join(d, name), "wb") as f:
                        f.write(olds[name])
                else:
                    os.unlink(os.path.join(d, name))
            except OSError:
                pass
        for tmp in tmps:
            try:
                os.unlink(tmp)
            except OSError:
                pass
        sys.exit("merge_sets.py: cannot write %s: %s" % (", ".join(n for n, _ in sets), e))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=HERE)
    d = ap.parse_args().dir
    cands = read(d, "candidates.jsonl")
    labels = {}
    for x in read(d, "labels-real.jsonl"):
        if x["id"] in labels:
            sys.exit("merge_sets.py: label id %s repeats in labels-real.jsonl" % x["id"])
        labels[x["id"]] = x
    ids = {c["id"] for c in cands}
    extra = sorted(set(labels) - ids)
    if extra:
        sys.exit("merge_sets.py: labels for unknown ids: %s" % ", ".join(extra))
    out = []
    for c in cands:
        lab = labels.get(c["id"])
        if not lab or lab.get("label") not in ("destructive", "harmless") or not isinstance(lab.get("reason"), str) or not lab["reason"].strip():
            sys.exit("merge_sets.py: candidate %s has no valid label and reason" % c["id"])
        out.append(dict(c, label=lab["label"], reason=lab["reason"]))
    commands = out + read(d, "constructed-commands.jsonl")
    texts = read(d, "texts-real.jsonl") + read(d, "texts-constructed.jsonl")
    # Both sets are checked before either is written.
    check("commands.jsonl", commands)
    check("texts.jsonl", texts)
    write_all(d, [("commands.jsonl", commands), ("texts.jsonl", texts)])
    print("COMMANDS=%d TEXTS=%d" % (len(commands), len(texts)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
