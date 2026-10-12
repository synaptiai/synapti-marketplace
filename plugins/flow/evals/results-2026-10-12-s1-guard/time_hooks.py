#!/usr/bin/env python3
"""Time what guard.command-intent adds to a Bash call (issue #297, AC2).

For --sent commands taken from commands.jsonl (class real-sent, in file
order) and --ruled-out real commands from the transcripts that the cheap
check rules out (in sha256 order of their text), it measures the wall time
of:

  patterns  the four pattern hooks (block-destructive, block-force-push,
            block-unchecked-merge, block-secrets) started together and all
            waited for, as Claude Code runs matching hooks in parallel
  off       hooks/scripts/s1-command-intent.sh with the site off
  shadow    the same hook in shadow mode (the call is detached)
  on        the same hook in on mode (it waits for the provider)

from a copy of the plugin outside any repository, with its own HOME whose
settings name TypeSafe, model jev-1.13.0, key in TYPESAFE_API_KEY (or the
--settings given). Writes timing.jsonl ({id, kind, patterns_ms, off_ms,
shadow_ms, on_ms}) and timing-run.json into --out.

Usage: time_hooks.py --out <dir> [--sets-dir <dir>] [--transcripts <dir> ...]
                     [--home <path>] [--sent N] [--ruled-out N] [--settings <file>]
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
import shutil  # noqa: E402
import subprocess  # noqa: E402
import tempfile  # noqa: E402
import time  # noqa: E402
from datetime import datetime, timezone  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import build_sets  # noqa: E402

PATTERNS = ("block-destructive", "block-force-push", "block-unchecked-merge", "block-secrets")


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def die(msg):
    sys.stderr.write("time_hooks.py: %s\n" % msg)
    sys.exit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--sets-dir", default=HERE)
    ap.add_argument("--transcripts", action="append", default=[])
    ap.add_argument("--home", default="")
    ap.add_argument("--sent", type=int, default=20)
    ap.add_argument("--ruled-out", type=int, default=20)
    ap.add_argument("--settings", default="")
    a = ap.parse_args()
    rows = [json.loads(line) for line in open(os.path.join(a.sets_dir, "commands.jsonl"), encoding="utf-8") if line.strip()]
    sent = [r for r in rows if r["class"] == "real-sent"][:a.sent]
    ruled = []
    if a.transcripts:
        calls = build_sets.read_transcripts(a.transcripts)
        cands = sorted({build_sets.normalise(c, a.home) for c, i in calls.items() if not i["hook"]}, key=build_sets.sha)
        for c in cands:
            if len(ruled) >= a.ruled_out:
                break
            if not c.strip() or len(c) > build_sets.MAX_LEN or any(w in c for w in ("danielbentes", "daniel")):
                continue
            if build_sets.ruled_out([c])[0]:
                ruled.append({"id": "ro%02d" % (len(ruled) + 1), "command": c})
    if a.settings:
        settings = json.load(open(a.settings, encoding="utf-8"))
    else:
        if not os.environ.get("TYPESAFE_API_KEY"):
            die("TYPESAFE_API_KEY is not set")
        settings = {"systemOne": {"provider": "typesafe", "model": "jev-1.13.0", "apiKeyEnv": "TYPESAFE_API_KEY"}}
    if "8765" in str(settings.get("systemOne", {}).get("baseUrl", "")):
        die("refusing a baseUrl on port 8765")
    work = tempfile.mkdtemp(prefix="flow-s1-guard-time.")
    try:
        plugin = os.path.join(work, "plugin")
        shutil.copytree(PLUGIN, plugin, ignore=shutil.ignore_patterns("evals", "tests", ".git"))
        home = os.path.join(work, "home")
        os.makedirs(os.path.join(home, ".claude"))
        repo = os.path.join(work, "repo")
        os.makedirs(repo)
        env = dict(os.environ, HOME=home)
        # PyYAML may live in the user's site-packages, which Python finds
        # through HOME; with HOME changed the client would report
        # python-missing. Name the real directory instead.
        import site as pysite
        user_site = pysite.getusersitepackages()
        if os.path.isdir(user_site):
            env["PYTHONPATH"] = ":".join(x for x in (user_site, os.environ.get("PYTHONPATH", "")) if x)
        for k in ("CLAUDE_CONFIG_DIR", "FLOW_USER_SETTINGS", "FLOW_STATE_DIR"):
            env.pop(k, None)
        subprocess.run(["git", "init", "-q", repo], check=True, env=env)
        subprocess.run(["git", "-C", repo, "-c", "user.email=e@x.invalid", "-c", "user.name=e",
                        "commit", "-q", "--allow-empty", "-m", "init"], check=True, env=env)
        hooks = os.path.join(plugin, "hooks", "scripts")

        def set_mode(mode):
            s = json.loads(json.dumps(settings))
            s.setdefault("systemOne", {})["uses"] = {"guard.command-intent": mode}
            with open(os.path.join(home, ".claude", "settings.flow.json"), "w", encoding="utf-8") as f:
                json.dump(s, f)

        def timed(procs_args, payload):
            t0 = time.monotonic()
            ps = [subprocess.Popen(p, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   cwd=repo, env=env) for p in procs_args]
            for p in ps:
                p.communicate(payload)
            return int((time.monotonic() - t0) * 1000)

        out = []
        items = [(r, "sent") for r in sent] + [(r, "ruled_out") for r in ruled]
        for n, (r, kind) in enumerate(items):
            payload = json.dumps({"session_id": "timing", "cwd": repo, "hook_event_name": "PreToolUse",
                                  "tool_name": "Bash", "tool_use_id": "toolu_timing%03d" % n,
                                  "tool_input": {"command": r["command"]}}).encode()
            row = {"id": r["id"], "kind": kind,
                   "patterns_ms": timed([[os.path.join(hooks, h + ".sh")] for h in PATTERNS], payload)}
            for mode in ("off", "shadow", "on"):
                set_mode(mode)
                row["%s_ms" % mode] = timed([[os.path.join(hooks, "s1-command-intent.sh")]], payload)
            out.append(row)
        os.makedirs(a.out, exist_ok=True)
        with open(os.path.join(a.out, "timing.jsonl"), "w", encoding="utf-8") as f:
            for row in out:
                f.write(json.dumps(row, sort_keys=True) + "\n")
        with open(os.path.join(a.out, "timing-run.json"), "w", encoding="utf-8") as f:
            json.dump({"ended": now(), "sent": len(sent), "ruled_out": len(ruled),
                       "ruled_out_commands": [r["command"] for r in ruled],
                       "model": settings.get("systemOne", {}).get("model", "")}, f, sort_keys=True)
            f.write("\n")
        print("TIMED=%d" % len(out))
        return 0
    finally:
        # Detached shadow calls may still be running; give them time to end
        # before their HOME goes away.
        time.sleep(5)
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
