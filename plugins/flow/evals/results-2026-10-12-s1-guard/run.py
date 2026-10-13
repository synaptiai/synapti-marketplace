#!/usr/bin/env python3
"""Send issue #297's labelled sets to System One, one request per row, in
shadow mode, through the hooks' own state builders.

--set commands: each row of commands.jsonl that the cheap check
(ruled_out.sh) does not rule out and the secrets check does not refuse is
sent at site guard.command-intent, with the state _g_command_state builds
and, as current, what the pattern hooks (block-destructive.sh,
block-force-push.sh, block-unchecked-merge.sh) decide for it in a scratch
repository. --set texts: each row of texts.jsonl is sent at site
guard.planted-instructions with the state _g_text_state builds.

It runs from a copy of the plugin outside any repository, with a HOME of its
own whose user settings name the provider: TypeSafe, model jev-1.13.0, key in
TYPESAFE_API_KEY, the shipped timeout, both sites in shadow. --settings
replaces those settings (the tests point them at a stub); a baseUrl on
127.0.0.1:8765 is refused. The key is read by the client from the
environment and never printed or written here.

Writes into --out: records-<set>.jsonl (the client's records), meta-<set>.jsonl
({id, sent, ruled_out, secret, current, rc, ms}) and, once every row was
handled, run-<set>.json. Exit 0 when every row was handled, 1 on a setup
error.

Usage: run.py --set commands|texts --out <dir> [--settings <file>]
              [--sets-dir <dir>] [--temp-dir <path>]
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
from urllib.parse import urlsplit  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.dirname(os.path.dirname(HERE))
SITES = {"commands": "guard.command-intent", "texts": "guard.planted-instructions"}
PATTERN_HOOKS = ("block-destructive", "block-force-push", "block-unchecked-merge")
# The temporary directory the transcripts' commands ran with on this machine.
TEMP_DIR = "/var/folders/76/jxm7d66n7p55shsbjng7777r0000gn/T"
REPO_ROOT = "/home/dev/synapti-marketplace"


def die(msg):
    sys.stderr.write("run.py: %s\n" % msg)
    sys.exit(1)


# The client's reasons for no answer that belong to one row. Any other reason
# (provider-none, invalid-settings, python-missing, ...) means the client
# stopped before asking, so the run measured nothing.
ROW_REASONS = {"shadow", "below-threshold", "timeout", "connection", "redirect", "malformed",
               "abstained", "missing-answer", "state-too-large"}


# The client's imajev preset sends to this address when baseUrl is unset.
IMAJEV_DEFAULT = "http://127.0.0.1:8765"
# Reasons for no answer that mean the provider was not reached or not read.
UNANSWERED = {"timeout", "connection", "redirect", "malformed", "missing-answer", "abstained"}


def port_8765(url):
    """True when the URL names port 8765, on any host spelling."""
    try:
        return urlsplit(str(url)).port == 8765
    except ValueError:
        return ":8765" in str(url)


def refused_url(s1):
    """True when the settings would send to port 8765: their baseUrl, or the
    imajev preset's default when no baseUrl is given."""
    url = s1.get("baseUrl") or (IMAJEV_DEFAULT if s1.get("provider") == "imajev" else "")
    return port_8765(url)


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def git_head(path):
    r = subprocess.run(["git", "-C", path, "rev-parse", "HEAD"], capture_output=True, text=True)
    return r.stdout.strip() or "unknown"


def sets_commit(path):
    r = subprocess.run(["git", "-C", os.path.dirname(path), "log", "-1", "--format=%H", "--", os.path.basename(path)],
                       capture_output=True, text=True)
    return r.stdout.strip() or "uncommitted"


def lib_call(plugin, fn, args, stdin=None):
    lib = os.path.join(plugin, "hooks", "scripts", "lib", "s1-guard.sh")
    r = subprocess.run(["bash", "-c", '. "$0" || exit 9; %s "$@"' % fn, lib] + list(args),
                       input=stdin, capture_output=True, text=True)
    return r.returncode, r.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", required=True, choices=sorted(SITES))
    ap.add_argument("--out", required=True)
    ap.add_argument("--settings", default="")
    ap.add_argument("--sets-dir", default=HERE)
    ap.add_argument("--temp-dir", default=TEMP_DIR)
    a = ap.parse_args()
    site = SITES[a.set]
    set_path = os.path.join(a.sets_dir, "%s.jsonl" % a.set)
    try:
        rows = [json.loads(line) for line in open(set_path, encoding="utf-8") if line.strip()]
    except (OSError, ValueError) as e:
        die("cannot read %s: %s" % (set_path, e))
    if a.settings:
        try:
            settings = json.load(open(a.settings, encoding="utf-8"))
        except (OSError, ValueError) as e:
            die("cannot read --settings: %s" % e)
    else:
        if not os.environ.get("TYPESAFE_API_KEY"):
            die("TYPESAFE_API_KEY is not set")
        settings = {"systemOne": {"provider": "typesafe", "model": "jev-1.13.0",
                                  "apiKeyEnv": "TYPESAFE_API_KEY"}}
    s1 = settings.setdefault("systemOne", {})
    if refused_url(s1):
        die("refusing a baseUrl on port 8765")
    s1["uses"] = {SITES["commands"]: "shadow", SITES["texts"]: "shadow"}

    work = tempfile.mkdtemp(prefix="flow-s1-guard-eval.")
    try:
        plugin = os.path.join(work, "plugin")
        shutil.copytree(PLUGIN, plugin, ignore=shutil.ignore_patterns("evals", "tests", ".git"))
        home = os.path.join(work, "home")
        os.makedirs(os.path.join(home, ".claude"))
        with open(os.path.join(home, ".claude", "settings.flow.json"), "w", encoding="utf-8") as f:
            json.dump(settings, f)
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
        client = os.path.join(plugin, "bin", "flow-s1.sh")
        hooks = os.path.join(plugin, "hooks", "scripts")
        os.makedirs(a.out, exist_ok=True)
        meta_path = os.path.join(a.out, "meta-%s.jsonl" % a.set)
        rec_path = os.path.join(a.out, "records-%s.jsonl" % a.set)
        run_path = os.path.join(a.out, "run-%s.json" % a.set)
        for p in (meta_path, rec_path, run_path):
            if os.path.exists(p):
                os.unlink(p)
        started = now()
        metas = []
        src = os.path.join(home, ".claude", "flow-state", "system-one.jsonl")

        def save():
            # The answers already paid for are kept whatever happens next.
            with open(meta_path, "w", encoding="utf-8") as f:
                for m in metas:
                    f.write(json.dumps(m, sort_keys=True) + "\n")
            if os.path.exists(src):
                shutil.copyfile(src, rec_path)
            else:
                open(rec_path, "w").close()

        try:
            send_rows(a, rows, metas, env, hooks, plugin, repo, work, client, site)
        except BaseException:
            save()
            raise
        save()
        # A client that stopped before asking (no Python, no PyYAML, settings
        # or questions it refuses, no provider) measured nothing: the run is
        # not complete, so no run file is written.
        setup = [m for m in metas if m.get("sent") and m.get("rc") != 0 and m.get("reason") not in ROW_REASONS]
        if setup:
            die("%d sent rows stopped before asking (first: %s, %s)" % (len(setup), setup[0]["id"], setup[0]["stderr"]))
        sent = [m for m in metas if m.get("sent")]
        if sent and all(m.get("rc") != 0 and m.get("reason") in UNANSWERED for m in sent):
            die("no sent row was answered (first: %s, %s)" % (sent[0]["id"], sent[0]["stderr"]))
        with open(run_path, "w", encoding="utf-8") as f:
            json.dump({"set": a.set, "site": site, "model": s1.get("model", ""),
                       "timeout_ms": s1.get("timeoutMs", "shipped"), "commit": git_head(PLUGIN),
                       "sets_commit": sets_commit(set_path), "started": started, "ended": now(),
                       "rows": len(rows), "sent": sum(1 for m in metas if m["sent"])}, f, sort_keys=True)
            f.write("\n")
        print("ROWS=%d SENT=%d" % (len(rows), sum(1 for m in metas if m["sent"])))
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


def send_rows(a, rows, metas, env, hooks, plugin, repo, work, client, site):
    """Send each row, appending its meta row to metas as it goes."""
    for row in rows:
        m = {"id": row["id"], "sent": False, "ruled_out": False, "secret": False}
        if a.set == "commands":
            cmd = row["command"]
            r = subprocess.run(["bash", os.path.join(HERE, "ruled_out.sh")], input=(cmd + "\0").encode(),
                               capture_output=True, env=dict(env, FLOW_GUARD_LIB=os.path.join(hooks, "lib", "s1-guard.sh")))
            answer = r.stdout.decode().strip()
            if r.returncode != 0 or answer not in ("0", "1"):
                die("row %s: the cheap check did not answer (exit %d)" % (row["id"], r.returncode))
            if answer == "1":
                m["ruled_out"] = True
                metas.append(m)
                continue
            payload = json.dumps({"tool_name": "Bash", "hook_event_name": "PreToolUse",
                                  "tool_input": {"command": cmd}, "cwd": repo})
            if subprocess.run([os.path.join(hooks, "block-secrets.sh")], input=payload.encode(),
                              capture_output=True, cwd=repo, env=env).returncode != 0:
                m["secret"] = True
                metas.append(m)
                continue
            # The hook does not send a command whose shell forms the masking
            # does not read (a substitution, a heredoc, a line continuation,
            # an open quote: _g_words fails), nor one that may hold a
            # credential the masking cannot place (_g_skip_credential).
            if lib_call(plugin, "_g_words", [cmd])[0] != 0:
                m["unmasked"] = True
                metas.append(m)
                continue
            if lib_call(plugin, "_g_skip_credential", [cmd])[0] == 0:
                m["credential"] = True
                metas.append(m)
                continue
            rcs = [subprocess.run([os.path.join(hooks, h + ".sh")], input=payload.encode(),
                                  capture_output=True, cwd=repo, env=env).returncode for h in PATTERN_HOOKS]
            current = "block" if 2 in rcs else ("allow" if all(c == 0 for c in rcs) else "unknown")
            cwd = row.get("cwd", REPO_ROOT)
            root = REPO_ROOT if (cwd + "/").startswith(REPO_ROOT + "/") else ""
            rc, state = lib_call(plugin, "_g_command_state", [cmd, cwd, a.temp_dir, root])
        else:
            current = "unmarked"
            payload = json.dumps({"tool_response": {"stdout": row["output"]}})
            rc, state = lib_call(plugin, "_g_text_state", [row["command"]], stdin=payload)
        if rc != 0 or not state.strip():
            die("row %s: the state could not be built" % row["id"])
        st = os.path.join(work, "state.json")
        with open(st, "w", encoding="utf-8") as f:
            f.write(state)
        t0 = time.monotonic()
        r = subprocess.run([client, "ask", "--site", site, "--state-file", st, "--state-format", "json",
                            "--current", current, "--ref", "eval:%s:%s" % (a.set, row["id"])],
                           capture_output=True, text=True, cwd=repo, env=env)
        first = (r.stderr.strip().splitlines() or [""])[0][:300]
        reason = first.split("no answer: ", 1)[1].split()[0] if "no answer: " in first else None
        m.update({"sent": True, "current": current, "rc": r.returncode,
                  "ms": int((time.monotonic() - t0) * 1000),
                  "stderr": first, "reason": reason})
        metas.append(m)


if __name__ == "__main__":
    sys.exit(main())
