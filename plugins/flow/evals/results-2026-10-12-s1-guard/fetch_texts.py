#!/usr/bin/env python3
"""Fetch the real plain texts of issue #297's measurement from GitHub, read-only.

Reads issue and pull request bodies, issue and pull request conversation
comments, and pull request review comments of --repo with gh, keeps those with
at least 40 characters of text and at most 8000, and takes them in sha256
order of the text: --bodies bodies, --comments conversation comments and
--reviews review comments. Each row gets the gh command that reads it, as the
hook would see it run, and its text as that command's output.

Writes texts-real.jsonl: {id, command, output, label: "plain", form: "none",
source}.

Usage: fetch_texts.py --repo owner/name --out <file> [--bodies N]
                      [--comments N] [--reviews N]
"""

# Keep the working directory off sys.path before any other import.
import os, sys  # noqa: E401
try:
    _cwd = os.path.realpath(os.getcwd())
except OSError:
    _cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _cwd]

import argparse  # noqa: E402
import hashlib  # noqa: E402
import json  # noqa: E402
import subprocess  # noqa: E402


def gh_pages(path):
    try:
        r = subprocess.run(["gh", "api", "--paginate", path], capture_output=True, text=True)
    except OSError as e:
        sys.exit("fetch_texts.py: cannot run gh: %s" % e)
    if r.returncode != 0:
        sys.exit("fetch_texts.py: gh api %s failed (exit %d): %s" % (path, r.returncode, r.stderr.strip()[:500]))
    out = r.stdout
    items = []
    dec = json.JSONDecoder()
    i = 0
    while i < len(out):
        while i < len(out) and out[i].isspace():
            i += 1
        if i >= len(out):
            break
        try:
            v, i = dec.raw_decode(out, i)
        except ValueError as e:
            sys.exit("fetch_texts.py: gh api %s printed something that is not JSON: %s" % (path, e))
        items.extend(v if isinstance(v, list) else [v])
    return items


def sha(t):
    return hashlib.sha256(t.encode("utf-8")).hexdigest()


def pick(items, n):
    ok = [x for x in items if 40 <= len((x["output"] or "").strip()) and len(x["output"]) <= 8000]
    return sorted(ok, key=lambda x: sha(x["output"]))[:n]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--bodies", type=int, default=25)
    ap.add_argument("--comments", type=int, default=20)
    ap.add_argument("--reviews", type=int, default=15)
    a = ap.parse_args()
    r = a.repo
    bodies = [{"command": "gh %s view %d --repo %s --json body --jq .body" % ("pr" if "pull_request" in x else "issue", x["number"], r),
               "output": x.get("body") or "", "source": "%s #%d body" % ("pr" if "pull_request" in x else "issue", x["number"])}
              for x in gh_pages("repos/%s/issues?state=all&per_page=100" % r)]
    comments = [{"command": "gh api repos/%s/issues/comments/%d --jq .body" % (r, x["id"]),
                 "output": x.get("body") or "", "source": "conversation comment %d" % x["id"]}
                for x in gh_pages("repos/%s/issues/comments?per_page=100" % r)]
    reviews = [{"command": "gh api repos/%s/pulls/comments/%d --jq .body" % (r, x["id"]),
                "output": x.get("body") or "", "source": "review comment %d" % x["id"]}
               for x in gh_pages("repos/%s/pulls/comments?per_page=100" % r)]
    rows = pick(bodies, a.bodies) + pick(comments, a.comments) + pick(reviews, a.reviews)
    with open(a.out, "w", encoding="utf-8") as f:
        for i, x in enumerate(rows, 1):
            f.write(json.dumps({"id": "p%03d" % i, "command": x["command"], "output": x["output"],
                                "label": "plain", "form": "none", "source": x["source"]}, sort_keys=True) + "\n")
    print("BODIES=%d COMMENTS=%d REVIEWS=%d ROWS=%d" % (len(bodies), len(comments), len(reviews), len(rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
