"""A launcher-shaped process for tests that need a live lease and a launcher
marker without the real launcher (bin/_flow_factory_launch.py).

tests/lib/factory-e2e.sh fe_fake_launcher starts it as

    <python> fake_launcher.py <plugin>/bin/_flow_factory_launch.py --factory-dir <F> <directive-id>

so its command line ends the way the real launcher's marker does (plan 2.9).
The first argument is only there for that shape; nothing is run from it.

It starts a "claude" child, `bash <worker script>` (the script named by the
FE_WORKER_SCRIPT variable) in a new session, then writes
<F>/jobs/<job folder>/directives/<directive-id>.lease.json with its own pid and
start time as the launcher and the child's pid, process group and start time,
each start time in the trimmed `ps -o lstart=` form (plan 2.4). It then waits
for the child, renewing heartbeat_at every second: each renewal reads the
lease and rewrites only that field, so a test may edit the others. It exits
with the child's exit status. On SIGTERM or SIGINT it kills the child's group
first.
"""
import json
import os
import signal
import socket
import subprocess
import sys
import time


def lstart(pid):
    r = subprocess.run(["/bin/ps", "-o", "lstart=", "-p", str(pid)], env={"LC_ALL": "C"},
                       capture_output=True, text=True, check=False)
    return r.stdout.strip() or None


def utc():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def write(path, data):
    tmp = "%s.tmp-%d" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1)
        f.write("\n")
    os.replace(tmp, path)


def main(argv):
    if len(argv) != 5 or argv[2] != "--factory-dir":
        print("usage: fake_launcher.py <launch.py path> --factory-dir <F> <directive-id>", file=sys.stderr)
        return 2
    fdir, directive = argv[3], argv[4]
    script = os.environ.get("FE_WORKER_SCRIPT", "")
    if not script:
        print("fake_launcher.py: FE_WORKER_SCRIPT is not set", file=sys.stderr)
        return 2
    folder = directive.split("-j", 1)[0]
    ddir = os.path.join(fdir, "jobs", folder, "directives")
    os.makedirs(ddir, exist_ok=True)
    path = os.path.join(ddir, directive + ".lease.json")

    child = subprocess.Popen(["bash", script], start_new_session=True, stdin=subprocess.DEVNULL)

    def stop(signum, _frame):
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except OSError:
            pass
        os._exit(128 + signum)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    now = utc()
    write(path, {
        "directive": directive, "kind": "worker", "host": socket.gethostname(),
        "launcher_pid": os.getpid(), "launcher_start": lstart(os.getpid()),
        "started_at": now, "heartbeat_at": now,
        # A new session: the child's group is its own pid.
        "child_pid": child.pid, "child_pgid": child.pid, "child_start": lstart(child.pid),
        "revoked_at": None,
    })
    while True:
        try:
            rc = child.wait(timeout=1)
            break
        except subprocess.TimeoutExpired:
            pass
        try:
            with open(path, encoding="utf-8") as f:
                lease = json.load(f)
            lease["heartbeat_at"] = utc()
            write(path, lease)
        except (OSError, ValueError):
            pass
    return rc if rc >= 0 else 128 - rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
