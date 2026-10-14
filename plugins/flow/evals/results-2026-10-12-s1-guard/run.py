#!/usr/bin/env python3
"""Send issue #297's labelled texts to System One, one request per row, in
shadow mode, through the screen hook's own state builder: each row of
texts.jsonl is sent at site guard.planted-instructions with the state
_g_text_state builds. (The command set was sent at site guard.command-intent,
which is not shipped; evals/results-2026-10-12-s1-guard/README.md names the
commit whose run.py sends it.)

It runs from a copy of the plugin outside any repository, with a HOME of its
own whose user settings name the provider: TypeSafe, model jev-1.13.0, key in
TYPESAFE_API_KEY, the shipped timeout, the site in shadow. --settings
replaces those settings (the tests point them at a stub); a baseUrl on
127.0.0.1:8765 is refused. The key is read by the client from the
environment and never printed or written here.

Writes into --out: records-<set>.jsonl (the client's records),
meta-<set>.jsonl ({id, sent, current, rc, ms}) and run-<set>.json, once
every row was handled. Until then they are written to a partial-<set>.*
folder in --out: a run that stops before they are moved leaves the last
complete run's files as they were and its own answers in that folder. The
run file is moved last, so a stop while they are being moved leaves files of
two runs, which summarize.py refuses, and the message names the files
already replaced. Exit 0 when every row was handled, 1 on a setup error or a
run that stopped; a TERM or HUP exits 128 plus the signal number, and an
interrupt keeps Python's own status.

Usage: run.py --set texts --out <dir> [--settings <file>] [--sets-dir <dir>]
"""

# Keep the working directory off sys.path before any other import.
import os, sys  # noqa: E401
try:
    _cwd = os.path.realpath(os.getcwd())
except OSError:
    _cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _cwd]

import argparse  # noqa: E402
import importlib.util  # noqa: E402
import json  # noqa: E402
import shutil  # noqa: E402
import signal  # noqa: E402
import subprocess  # noqa: E402
import tempfile  # noqa: E402
import time  # noqa: E402
from datetime import datetime, timezone  # noqa: E402
from urllib.parse import urlsplit  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.dirname(os.path.dirname(HERE))
SITES = {"texts": "guard.planted-instructions"}


def _summarize():
    """summarize.py, loaded by its path: its hook_screens is the one copy of
    the hook's conditions before the grammar."""
    spec = importlib.util.spec_from_file_location("s1_guard_summarize", os.path.join(HERE, "summarize.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


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
    a = ap.parse_args()
    site = SITES[a.set]
    set_path = os.path.join(a.sets_dir, "%s.jsonl" % a.set)
    try:
        rows = [json.loads(line) for line in open(set_path, encoding="utf-8") if line.strip()]
    except (OSError, ValueError) as e:
        die("cannot read %s: %s" % (set_path, e))
    # Every row's state is built, with the shipped library, before anything
    # under --out is replaced: a row the loop below cannot send would
    # otherwise leave empty result files in place of the last run's. A row
    # whose command the hook does not screen is not one the hook would send.
    if not rows:
        die("%s has no rows" % os.path.basename(set_path))
    states, seen = [], set()
    try:
        summary_mod = _summarize()
        # Stops here, with the message below, if either name is missing.
        summary_mod.hook_screens, summary_mod.ToolFailed
    except Exception as e:
        die("cannot load summarize.py: %s" % e)
    for n, row in enumerate(rows, 1):
        if not (isinstance(row, dict) and all(isinstance(row.get(k), str) for k in ("id", "command", "output"))):
            die("%s row %d is not an object with string id, command and output" % (os.path.basename(set_path), n))
        if row["id"] in seen:
            die("%s has two rows with id %s" % (os.path.basename(set_path), row["id"]))
        seen.add(row["id"])
        try:
            screens = summary_mod.hook_screens(row)
        except summary_mod.ToolFailed as e:
            die(str(e))
        if not screens:
            die("row %s: the shipped hook does not screen it (blank output or a command over 20,000 bytes)" % row["id"])
        payload = json.dumps({"tool_response": {"stdout": row["output"]}})
        try:
            rc, state = lib_call(PLUGIN, '_g_gh_read "$1" || exit 8; _g_text_state', [row["command"]], stdin=payload)
        except (OSError, ValueError) as e:
            die("row %s: the state could not be built: %s" % (row["id"], e))
        if rc == 8:
            die("row %s: the shipped hook does not screen its command" % row["id"])
        if rc != 0:
            die("row %s: the state could not be built" % row["id"])
        if not state.strip():
            die("row %s: the shipped hook sends nothing for its output (none of the read's own title or body text)" % row["id"])
        states.append(state)
    if a.settings:
        try:
            settings = json.load(open(a.settings, encoding="utf-8"))
        except (OSError, ValueError) as e:
            die("cannot read --settings: %s" % e)
        if not isinstance(settings, dict) or not isinstance(settings.get("systemOne", {}), dict):
            die("--settings must be an object, and its systemOne an object")
    else:
        if not os.environ.get("TYPESAFE_API_KEY"):
            die("TYPESAFE_API_KEY is not set")
        settings = {"systemOne": {"provider": "typesafe", "model": "jev-1.13.0",
                                  "apiKeyEnv": "TYPESAFE_API_KEY"}}
    s1 = settings.setdefault("systemOne", {})
    if refused_url(s1):
        die("refusing a baseUrl on port 8765")
    s1["uses"] = {site: "shadow"}

    # A TERM or HUP (a timeout, a closed terminal) takes the same path as an
    # interrupt: this run's answers are saved, the folder named and the work
    # folder removed. Once that path starts, further signals are ignored, so
    # a second one cannot stop it halfway.
    def stop(sig, frame):
        raise SystemExit(128 + sig)

    def hold():
        for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
            signal.signal(sig, signal.SIG_IGN)

    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, stop)
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
        os.makedirs(a.out, exist_ok=True)
        stage = tempfile.mkdtemp(prefix="partial-%s." % a.set, dir=a.out)
        meta_path = os.path.join(stage, "meta-%s.jsonl" % a.set)
        rec_path = os.path.join(stage, "records-%s.jsonl" % a.set)
        run_path = os.path.join(stage, "run-%s.json" % a.set)
        started = now()
        moving = False
        metas = []
        src = os.path.join(home, ".claude", "flow-state", "system-one.jsonl")

        def save():
            with open(meta_path, "w", encoding="utf-8") as f:
                for m in metas:
                    f.write(json.dumps(m, sort_keys=True) + "\n")
            if os.path.exists(src):
                shutil.copyfile(src, rec_path)
            else:
                open(rec_path, "w").close()

        try:
            send_rows(a, rows, states, metas, env, repo, work, client, site)
            save()
            # A client that stopped before asking (no Python, no PyYAML,
            # settings or questions it refuses, no provider) measured
            # nothing: the run is not complete, so no run file is written.
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
            # The run file last: until it is moved, --out holds the last
            # run's file, whose times the moved records fall outside, so
            # summarize.py refuses what a stop between the moves leaves.
            moving = True
            for p in (rec_path, meta_path, run_path):
                os.replace(p, os.path.join(a.out, os.path.basename(p)))
            # The run is complete: a signal from here on changes nothing.
            hold()
        except BaseException:
            hold()
            # What was moved is read from the folder, so a stop just after a
            # move is reported too.
            moved = [os.path.basename(p) for p in (rec_path, meta_path, run_path) if not os.path.exists(p)] if moving else []
            # The answers already paid for are kept whatever happens next.
            if len(moved) == 3:
                sys.stderr.write("run.py: stopped after the run was complete; its empty folder %s was left\n" % stage)
            elif not moved:
                save()
                sys.stderr.write("run.py: this run's files are in %s; the last complete run's files are unchanged\n" % stage)
            else:
                sys.stderr.write("run.py: stopped while replacing the last run's files: %s were replaced, the rest are in %s; move them into %s to finish\n"
                                 % (", ".join(moved), stage, a.out))
            raise
        try:
            os.rmdir(stage)
        except OSError as e:
            sys.stderr.write("run.py: the run is complete, but its empty folder %s was left: %s\n" % (stage, e))
        print("ROWS=%d SENT=%d" % (len(rows), sum(1 for m in metas if m["sent"])))
        return 0
    finally:
        hold()
        shutil.rmtree(work, ignore_errors=True)


def send_rows(a, rows, states, metas, env, repo, work, client, site):
    """Send each row with the state built for it, appending its meta row to
    metas as it goes."""
    for row, state in zip(rows, states):
        m = {"id": row["id"], "sent": False}
        current = "unmarked"
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
