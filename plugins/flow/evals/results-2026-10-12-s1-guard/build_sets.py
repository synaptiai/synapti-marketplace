#!/usr/bin/env python3
"""Build the real-command candidates of issue #297's measurement from Claude
Code session transcripts.

Reads every *.jsonl under each --transcripts directory (subagent transcripts
included) and collects each Bash tool call's command, the cwd of its line, and
whether a Flow pattern hook refused it (a tool_result with is_error whose text
names hooks/scripts/block-<name>.sh). Then:

- the home path (--home) becomes /home/dev, in the command and the cwd;
- distinct commands of at most 2000 characters are kept;
- the shipped cheap check (ruled_out.sh) is applied to every one of them, and
  the share it rules out is written to ruledout.json;
- real-sent: commands no pattern hook refused and the cheap check does not
  rule out, in sha256 order of their text, skipping any that block-secrets.sh
  refuses or that still name the user (--drop-word), until --real-sent are
  kept;
- real-blocked: for each hook in --quota (name=count), the commands that hook
  refused, in sha256 order, with the same skips, until its count is kept.

Writes candidates.jsonl: {id, command, cwd, class, source}, unlabelled. The
labels are added by hand (labels-real.jsonl) and merged by merge_sets.py.

Usage:
  build_sets.py --transcripts <dir> [--transcripts <dir> ...] --out <dir>
                [--home <path>] [--real-sent N] [--quota hook=N ...]
                [--drop-word <word> ...]
"""

# Keep the working directory off sys.path before any other import.
import os, sys  # noqa: E401
try:
    _cwd = os.path.realpath(os.getcwd())
except OSError:
    _cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _cwd]

import argparse  # noqa: E402
import glob  # noqa: E402
import hashlib  # noqa: E402
import json  # noqa: E402
import re  # noqa: E402
import subprocess  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.dirname(os.path.dirname(HERE))
HOOKS = os.path.join(PLUGIN, "hooks", "scripts")
BLOCK_RE = re.compile(r"PreToolUse:Bash hook error: \[[^\]]*/hooks/scripts/(block-[a-z-]+)\.sh\]")
MAX_LEN = 2000


def sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def read_transcripts(dirs):
    """{command: cwd} for every Bash call, and {command: hook} for the refused."""
    uses, refused = {}, {}
    for d in dirs:
        for path in sorted(glob.glob(os.path.join(d, "**", "*.jsonl"), recursive=True)):
            with open(path, encoding="utf-8", errors="replace") as f:
                for line in f:
                    if '"Bash"' not in line and "hook error" not in line:
                        continue
                    try:
                        rec = json.loads(line)
                    except ValueError:
                        continue
                    content = (rec.get("message") or {}).get("content")
                    if not isinstance(content, list):
                        continue
                    for b in content:
                        if not isinstance(b, dict):
                            continue
                        if b.get("type") == "tool_use" and b.get("name") == "Bash":
                            cmd = (b.get("input") or {}).get("command")
                            if isinstance(cmd, str):
                                uses[b.get("id")] = (cmd, rec.get("cwd") or "")
                        elif b.get("type") == "tool_result" and b.get("is_error"):
                            text = b.get("content")
                            text = text if isinstance(text, str) else json.dumps(text)
                            m = BLOCK_RE.search(text)
                            if m:
                                refused[b.get("tool_use_id")] = m.group(1)
    calls = {}
    for tid, (cmd, cwd) in uses.items():
        calls.setdefault(cmd, {"cwd": cwd, "hook": None})
        if tid in refused:
            calls[cmd]["hook"] = refused[tid]
    return calls


def normalise(text, home):
    if home:
        text = text.replace(home, "/home/dev")
        slug = re.sub(r"[^A-Za-z0-9]", "-", home)
        text = text.replace(slug, "-home-dev")
    return text


def ruled_out(commands):
    data = b"".join(c.encode("utf-8") + b"\0" for c in commands)
    out = subprocess.run(["bash", os.path.join(HERE, "ruled_out.sh")], input=data,
                         capture_output=True, check=True).stdout.decode().split()
    if len(out) != len(commands):
        raise SystemExit("build_sets.py: ruled_out.sh answered %d of %d commands" % (len(out), len(commands)))
    return [o == "1" for o in out]


def secrets_flag(command, cwd):
    payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": command}, "cwd": cwd})
    r = subprocess.run([os.path.join(HOOKS, "block-secrets.sh")], input=payload.encode(),
                       capture_output=True)
    return r.returncode != 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--transcripts", action="append", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--home", default="")
    ap.add_argument("--real-sent", type=int, default=120)
    ap.add_argument("--quota", action="append", default=[])
    ap.add_argument("--drop-word", action="append", default=[])
    a = ap.parse_args()
    quota = {}
    for q in a.quota:
        name, _, n = q.partition("=")
        quota[name] = int(n)

    calls = read_transcripts(a.transcripts)
    rows = {}
    for cmd, info in calls.items():
        c = normalise(cmd, a.home)
        if not c.strip() or len(c) > MAX_LEN:
            continue
        r = rows.setdefault(c, {"cwd": normalise(info["cwd"], a.home), "hook": None})
        r["hook"] = r["hook"] or info["hook"]
    commands = sorted(rows)
    flags = ruled_out(commands)
    for c, f in zip(commands, flags):
        rows[c]["ruled_out"] = f
    os.makedirs(a.out, exist_ok=True)
    n_out = sum(flags)
    with open(os.path.join(a.out, "ruledout.json"), "w", encoding="utf-8") as f:
        json.dump({"commands": len(commands), "ruled_out": n_out,
                   "share": round(n_out / len(commands), 4) if commands else None}, f, sort_keys=True)
        f.write("\n")

    def usable(c):
        return not any(w in c for w in a.drop_word) and not secrets_flag(c, rows[c]["cwd"])

    picked = []
    pool = sorted((c for c in commands if not rows[c]["hook"] and not rows[c]["ruled_out"]), key=sha)
    n = 0
    for c in pool:
        if n >= a.real_sent:
            break
        if usable(c):
            picked.append((c, "real-sent", "transcript"))
            n += 1
    for hook, count in sorted(quota.items()):
        n = 0
        for c in sorted((c for c in commands if rows[c]["hook"] == hook), key=sha):
            if n >= count:
                break
            if usable(c):
                picked.append((c, "real-blocked", "transcript, refused by %s" % hook))
                n += 1
    with open(os.path.join(a.out, "candidates.jsonl"), "w", encoding="utf-8") as f:
        for i, (c, cls, src) in enumerate(picked, 1):
            f.write(json.dumps({"id": "r%03d" % i, "command": c, "cwd": rows[c]["cwd"],
                                "class": cls, "source": src}, sort_keys=True) + "\n")
    print("COMMANDS=%d RULED_OUT=%d PICKED=%d" % (len(commands), n_out, len(picked)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
