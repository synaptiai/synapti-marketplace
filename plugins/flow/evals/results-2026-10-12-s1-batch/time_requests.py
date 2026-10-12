#!/usr/bin/env python3
"""Time each System One request of issue #295's comparison on its own: every
item alone, and the requests ask-many would make for each group with
items-in-state and with items-in-questions. run.sh times whole client calls,
which include starting bash and Python; this times only the HTTP request,
from sending it to reading the whole reply.

It sends the bodies the client builds, through the client's own functions
(check_settings, load_site, load_item, pack, build_request, encode_body,
post), from the plugin this file is in. Answers are not kept: the comparison's
answers are in records-*.jsonl.

Usage:
  time_requests.py --set goal|review --out <dir> [--goal-items <file>]
                   [--review-dir <dir>] [--base-url <url>] [--model <id>]
                   [--key-env <name>] [--timeout-ms <ms>] [--cap <tokens>]

Defaults: TypeSafe's address, model jev-1.13.0, key in TYPESAFE_API_KEY,
the shipped timeout of 3000 ms and TypeSafe's cap of 28000 tokens. The
three sends of each group run one after another, their order rotating from
group to group (alone, S, Q, then S, Q, alone, ...).

Writes timing-<set>.jsonl, one line per request: {group, send, items, ms,
result}, where send is alone, items-in-state or items-in-questions and result
is ok or the reason the request failed; and timing-run-<set>.json when every
group was sent. Exit 0 when every group was sent, 1 on a setup error.
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
import subprocess  # noqa: E402
import time  # noqa: E402
from datetime import datetime, timezone  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(1, os.path.join(PLUGIN, "bin"))
import items as items_mod  # noqa: E402
import _flow_s1 as s1  # noqa: E402

SITES = {"goal": "goal.judge", "review": "review.confidence"}
SENDS = ("alone", "items-in-state", "items-in-questions")


def die(msg):
    sys.stderr.write("time_requests.py: %s\n" % msg)
    sys.exit(1)


def timed_post(cfg, body):
    t0 = time.monotonic()
    try:
        s1.post(cfg, s1.encode_body(body))
        result = "ok"
    except s1.NoAnswer as e:
        result = e.reason
    return int((time.monotonic() - t0) * 1000), result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", required=True, choices=sorted(SITES))
    ap.add_argument("--out", required=True)
    ap.add_argument("--goal-items", default=os.path.expanduser("~/flow-s1-work/replay/A/items.jsonl"))
    ap.add_argument("--review-dir", default=os.path.join(HERE, "..", "results-2026-09-25-review", "replay", "shadow", "base"))
    ap.add_argument("--base-url", default="")
    ap.add_argument("--model", default="jev-1.13.0")
    ap.add_argument("--key-env", default="TYPESAFE_API_KEY")
    ap.add_argument("--timeout-ms", default="3000")
    ap.add_argument("--cap", default="0")
    a = ap.parse_args()
    provider = "custom" if a.base_url else "typesafe"
    try:
        cfg = s1.check_settings(argparse.Namespace(
            provider=provider, base_url=a.base_url, model=a.model, api_key_env=a.key_env,
            timeout_ms=a.timeout_ms, max_timeout_ms="", state_token_cap=a.cap))
        questions, _ = s1.load_site(os.path.join(PLUGIN, "system-one", "questions.yaml"), SITES[a.set])
    except s1.NoAnswer as e:
        die("cannot ask: %s" % e.reason)
    qid, question = next(iter(questions.items()))
    try:
        all_items = items_mod.list_items(a.set, a.goal_items, a.review_dir)
    except (OSError, ValueError, KeyError) as e:
        die("cannot read the %s items: %s" % (a.set, e))
    if not all_items:
        die("no %s items" % a.set)
    for it in all_items:
        try:
            it["state"], it["digest"] = s1.load_item(it["state_file"])
        except s1.NoAnswer as e:
            die("item %s: %s" % (it["ref"], e.reason))
    # Every item of a group, in file order, in the order each group first
    # appears: the grouping run.sh uses. A group's items need not be next to
    # each other in the file (the goal replay lists constructed items after
    # the natural ones).
    groups, index = [], {}
    for it in all_items:
        if it["group"] not in index:
            index[it["group"]] = len(groups)
            groups.append((it["group"], []))
        groups[index[it["group"]]][1].append(it)
    os.makedirs(a.out, exist_ok=True)
    out_path = os.path.join(a.out, "timing-%s.jsonl" % a.set)
    run_path = os.path.join(a.out, "timing-run-%s.json" % a.set)
    for p in (out_path, run_path):
        if os.path.exists(p):
            os.unlink(p)
    started = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    rows = []
    for g, (name, group) in enumerate(groups):
        for k in range(3):
            send = SENDS[(g + k) % 3]
            requests = []
            if send == "alone":
                requests = [(it["state"], {qid: question}, 1) for it in group]
            else:
                packed, alone = s1.pack(send, question, group, cfg["cap"] * 4)
                for grp in packed:
                    state, qs = s1.build_request(send, question, grp)
                    requests.append((state, qs, len(grp)))
                requests += [(it["state"], {qid: question}, 1) for it in alone]
            for state, qs, n in requests:
                body = {"state": state, "questions": qs}
                if cfg["model"]:
                    body["model"] = cfg["model"]
                ms, result = timed_post(cfg, body)
                rows.append({"group": name, "send": send, "items": n, "ms": ms, "result": result})
    with open(out_path + ".tmp", "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, sort_keys=True) + "\n")
    os.replace(out_path + ".tmp", out_path)
    try:
        commit = subprocess.run(["git", "-C", PLUGIN, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip() or "unknown"
    except OSError:
        commit = "unknown"
    with open(run_path, "w", encoding="utf-8") as f:
        json.dump({"set": a.set, "site": SITES[a.set], "model": a.model, "timeout_ms": int(cfg["timeout"] * 1000),
                   "commit": commit, "started": started,
                   "ended": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                   "requests": len(rows)}, f, sort_keys=True)
        f.write("\n")
    print("REQUESTS=%d" % len(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
