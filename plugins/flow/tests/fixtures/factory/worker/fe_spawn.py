"""Start a command with no ancestor of the test, for tests/lib/factory-e2e.sh.

    fe_spawn.py detached <out dir> <timeout s> <procs file> -- <command...>
    fe_spawn.py terminal <out file> <rc file> <word> <delay s> <timeout s> <procs file> -- <command...>

Both double-fork, the first child calling os.setsid(), so what runs is
re-parented to pid 1 and is in a session of its own. CLAUDECODE is removed
from the command's environment. Every process started is appended to the
procs file as `<pid>\t<start>` (the trimmed `ps -o lstart=` form of plan 2.4),
so the helpers' cleanup can kill what is left.

detached: the command itself is the re-parented process, with stdin
/dev/null and no controlling terminal; its stdout and stderr go to out/err in
the out dir. On macOS its exit status is read through kqueue (NOTE_EXITSTATUS
reports it for a process that is not a child), and this process waits for it
and writes rc. On a system without kqueue the command runs as the child of a
re-parented waiter, which writes rc. At the timeout the command's group is
killed and rc is 124.

terminal: the re-parented process runs the command under pty.fork(), so the
command has a controlling terminal. The command's output is appended to the
out file as it arrives. When the text after the last newline starts with
`type ` and ends in `:` or `: `, it waits <delay> seconds, types <word> and a
newline, once. When the command ends, its exit status goes to the rc file; at
the timeout its group is killed and the status is 124. This process waits for
the rc file and exits 0; the shell helper reads the two files.
"""
import os
import re
import select
import signal
import subprocess
import sys
import time

PROMPT = re.compile(r"^type .*: ?$")


def lstart(pid):
    r = subprocess.run(["/bin/ps", "-o", "lstart=", "-p", str(pid)], env={"LC_ALL": "C"},
                       capture_output=True, text=True, check=False)
    return r.stdout.strip()


def register(procs, pid):
    with open(procs, "a", encoding="utf-8") as f:
        f.write("%d\t%s\n" % (pid, lstart(pid)))


def command_env():
    env = dict(os.environ)
    env.pop("CLAUDECODE", None)
    return env


def write_text(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def detached(outdir, timeout, procs, cmd):
    os.makedirs(outdir, exist_ok=True)
    pid_r, pid_w = os.pipe()
    go_r, go_w = os.pipe()
    kq = getattr(select, "kqueue", None)
    first = os.fork()
    if first == 0:
        os.setsid()
        second = os.fork()
        if second == 0:
            os.close(go_w)
            os.read(go_r, 1)
            fd = os.open(os.devnull, os.O_RDONLY)
            os.dup2(fd, 0)
            os.dup2(os.open(os.path.join(outdir, "out"), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644), 1)
            os.dup2(os.open(os.path.join(outdir, "err"), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644), 2)
            env = command_env()
            if kq is not None:
                try:
                    os.execvpe(cmd[0], cmd, env)
                except OSError as e:
                    os.write(2, ("fe_spawn: %s: %s\n" % (cmd[0], e)).encode())
                    os._exit(127)
            # No kqueue: the command runs as this waiter's child.
            p = subprocess.Popen(cmd, env=env)
            register(procs, p.pid)
            rc = p.wait()
            write_text(os.path.join(outdir, "rc.t"), "%d\n" % (rc if rc >= 0 else 128 - rc))
            os.replace(os.path.join(outdir, "rc.t"), os.path.join(outdir, "rc"))
            os._exit(0)
        os.write(pid_w, str(second).encode())
        os._exit(0)
    os.waitpid(first, 0)
    os.close(pid_w)
    os.close(go_r)
    target = int(os.read(pid_r, 32))
    register(procs, target)
    if kq is not None:
        q = select.kqueue()
        ev = select.kevent(target, filter=select.KQ_FILTER_PROC,
                           flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT,
                           fflags=select.KQ_NOTE_EXIT | getattr(select, "KQ_NOTE_EXITSTATUS", 0x04000000))
        q.control([ev], 0, 0)
        os.write(go_w, b"g")
        got = q.control(None, 1, timeout)
        if got:
            rc = os.waitstatus_to_exitcode(got[0].data)
            rc = rc if rc >= 0 else 128 - rc
        else:
            try:
                os.killpg(first, signal.SIGKILL)
            except OSError:
                pass
            rc = 124
        write_text(os.path.join(outdir, "rc"), "%d\n" % rc)
        return 0
    os.write(go_w, b"g")
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.exists(os.path.join(outdir, "rc")):
            return 0
        time.sleep(0.1)
    try:
        os.killpg(first, signal.SIGKILL)
    except OSError:
        pass
    write_text(os.path.join(outdir, "rc"), "124\n")
    return 0


def terminal(outfile, rcfile, word, delay, timeout, procs, cmd):
    import pty
    open(outfile, "a").close()
    first = os.fork()
    if first == 0:
        os.setsid()
        if os.fork() != 0:
            os._exit(0)
        rc = 124
        try:
            register(procs, os.getpid())
            child, fd = pty.fork()
            if child == 0:
                env = command_env()
                try:
                    os.execvpe(cmd[0], cmd, env)
                except OSError as e:
                    os.write(2, ("fe_spawn: %s: %s\n" % (cmd[0], e)).encode())
                    os._exit(127)
            register(procs, child)
            tail = ""
            answered = False
            deadline = time.time() + timeout
            with open(outfile, "ab", buffering=0) as out:
                while time.time() < deadline:
                    ready, _, _ = select.select([fd], [], [], 0.1)
                    if not ready:
                        continue
                    try:
                        data = os.read(fd, 4096)
                    except OSError:
                        data = b""
                    if not data:
                        break
                    out.write(data)
                    tail = (tail + data.decode("utf-8", "replace")).replace("\r", "").rsplit("\n", 1)[-1]
                    if not answered and PROMPT.match(tail):
                        time.sleep(delay)
                        os.write(fd, (word + "\n").encode())
                        answered = True
            if time.time() >= deadline:
                try:
                    os.killpg(child, signal.SIGKILL)
                except OSError:
                    pass
            _, status = os.waitpid(child, 0)
            code = os.waitstatus_to_exitcode(status)
            rc = 124 if time.time() >= deadline else (code if code >= 0 else 128 - code)
        finally:
            write_text(rcfile + ".t", "%d\n" % rc)
            os.replace(rcfile + ".t", rcfile)
            os._exit(0)
    os.waitpid(first, 0)
    deadline = time.time() + timeout + 10
    while time.time() < deadline:
        if os.path.exists(rcfile):
            return 0
        time.sleep(0.1)
    write_text(rcfile, "124\n")
    return 0


def main(argv):
    if "--" not in argv:
        print(__doc__, file=sys.stderr)
        return 2
    i = argv.index("--")
    head, cmd = argv[1:i], argv[i + 1:]
    if not cmd:
        print("fe_spawn.py: no command", file=sys.stderr)
        return 2
    if head and head[0] == "detached" and len(head) == 4:
        return detached(head[1], float(head[2]), head[3], cmd)
    if head and head[0] == "terminal" and len(head) == 7:
        return terminal(head[1], head[2], head[3], float(head[4]), float(head[5]), head[6], cmd)
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
