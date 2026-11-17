"""Who is calling the factory engine: a person, or a worker (plan 1a, section
2.8; design person_channels L19, execution_model L66; amendment B.7).

A caller is a worker when one of the three worker variables of design
person_channels L19 (FLOW_FACTORY_JOB, FLOW_FACTORY_DIRECTIVE,
FLOW_FACTORY_IO) is set and not empty, or when a live lease's launcher or
claude process is among its ancestors. A lease is live when its revoked_at is
null and its launcher_pid runs with the start time the lease records, so a
pid the system has given to another process is not a launcher.

Start times are in one form everywhere (plan 2.4): the output of
`LC_ALL=C /bin/ps -o lstart= -p <pid>` with outer white space removed and inner
spaces kept. macOS pads the field with trailing spaces, which the shell keeps
and a plain read does not, so every reader and writer trims it.

The ancestry is read with /bin/ps by its full path (never a ps on PATH), with
-ww so no width limit cuts a command line, one pid at a time up to pid 1. An
ancestry that cannot be read fails closed: the caller is refused.

The launcher's command line is a marker (plan 2.9):
  <interpreter> -E <plugin>/bin/_flow_factory_launch.py --factory-dir <F> <directive-id>
ps joins the arguments with single spaces and does not quote them, so the
factory directory is recovered by one rule, shared with flow-factory.sh's
ff_marker_dir: the text after the FIRST "/bin/_flow_factory_launch.py
--factory-dir " must end with " <directive-id>", and the directory is the
non-empty text between. A directory that holds spaces still parses.

This module is loaded by the early check at the top of _flow_factory.py,
before that file's imports that need Python 3.11, so it must load under the
macOS system Python 3.9 (plan 2.17): standard library only, no syntax newer
than 3.9, and no import of _flow_factory or of any module that imports it.

API:
  lstart(pid) -> str or None
  ancestry(pid=None) -> [(pid, ppid, start, command)]   raises AncestryUnreadable
  marker_factory_dir(command) -> str or None
  live_leases(factory_dir) -> [lease dict]
  find_factory_dir(cwd=None) -> (abs F, "launcher" | "cwd") or (None, None)
  in_session(env=None) -> bool
  check(subcommand, env=None) -> None or "worker_env" | "lease_ancestor" | "ancestry_unreadable"
  early_exit(argv)    prints PERSON_ONLY_REFUSED=<reason> and exits 4 on a refusal
"""

# The guard below must stay verbatim (tests/syspath-guard.test.sh matches it)
# and must run before the other imports, so ruff's rules on one import per
# line and imports at the top do not apply to this file.
# ruff: noqa: E401, E402
# Keep the working directory (the repository) off sys.path before any other
# import; tests/syspath-guard.test.sh has the reasons.
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]

import glob
import json
import re
import subprocess

PS = "/bin/ps"
BIN_DIR = os.path.dirname(os.path.realpath(__file__))
WORKER_VARS = ("FLOW_FACTORY_JOB", "FLOW_FACTORY_DIRECTIVE", "FLOW_FACTORY_IO")  # design person_channels L19
PERSON = ("answer", "approve-spec", "confirm", "feedback", "rework", "retry", "reject", "cancel", "rebuild")
ENGINE_GUARDED = ("run", "next", "probe")  # refused like the person subcommands
INTERNAL = ("launch", "report")  # refused on a live lease's launcher or claude ancestor only
DIRECTIVE_ID = re.compile(r"^issue-[1-9][0-9]*-j[1-9][0-9]*-(intake|prepare|spec|build|open_pr|gate|review|rework"
                          r"|sync|resolve|approve|merging)-[1-9][0-9]*$")
MARKER_ANCHOR = "/bin/_flow_factory_launch.py --factory-dir "
# The longest ancestry walked; a longer one is read as a loop and fails closed.
MAX_DEPTH = 4096
PS_TIMEOUT = 10


class AncestryUnreadable(Exception):
    pass


def _ps(args):
    """stdout of /bin/ps with these arguments under LC_ALL=C, decoded so any
    byte survives, or None when it cannot run or exits non-zero."""
    try:
        r = subprocess.run([PS] + args, env={"LC_ALL": "C"}, stdin=subprocess.DEVNULL,
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=PS_TIMEOUT, check=False)
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    if r.returncode != 0:
        return None
    return r.stdout.decode("utf-8", "surrogateescape")


def lstart(pid):
    """The 2.4 start-time form of pid, or None when ps prints nothing for it."""
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0:
        return None
    out = _ps(["-o", "lstart=", "-p", str(pid)])
    return (out or "").strip() or None


def _parse_line(out):
    """(ppid, start, command) from one `ps -o ppid=,lstart=,command=` line:
    the ppid, white space, the start (always 24 characters), padding, then
    the command. None when the line has no such shape."""
    line = out.rstrip("\n").lstrip()
    m = re.match(r"[0-9]+", line)
    if not m:
        return None
    rest = line[m.end():].lstrip()
    start = rest[:24].rstrip()
    if len(start) < 20:
        return None
    return int(m.group(0)), start, rest[24:].lstrip()


def ancestry(pid=None):
    """[(pid, ppid, start, command)] from pid (default this process) up to pid
    1, each read with /bin/ps -ww -o ppid=,lstart=,command= under LC_ALL=C.
    Raises AncestryUnreadable when /bin/ps is missing or fails, or prints
    nothing or no readable line for a pid that is not 1, or when the walk
    does not end."""
    p = os.getpid() if pid is None else pid
    out = []
    while True:
        if not isinstance(p, int) or p <= 0:
            break
        if len(out) >= MAX_DEPTH:
            raise AncestryUnreadable("the ancestry is longer than %d" % MAX_DEPTH)
        text = _ps(["-ww", "-o", "ppid=,lstart=,command=", "-p", str(p)])
        parsed = _parse_line(text) if text else None
        if parsed is None:
            if p == 1:
                break
            raise AncestryUnreadable("ps printed nothing readable for pid %d" % p)
        ppid, start, command = parsed
        out.append((p, ppid, start, command))
        if p == 1 or ppid == p:
            break
        p = ppid
    return out


def marker_factory_dir(command):
    """The factory directory a launcher marker names, or None. The rule shared
    with flow-factory.sh's ff_marker_dir: the command contains
    "/bin/_flow_factory_launch.py --factory-dir "; the text after its first
    occurrence ends with " <id>" where <id> is the text after the last space
    and matches DIRECTIVE_ID; the factory directory is the non-empty text
    between them."""
    if not isinstance(command, str) or MARKER_ANCHOR not in command:
        return None
    rest = command.split(MARKER_ANCHOR, 1)[1]
    did = rest.rsplit(" ", 1)[-1]
    # fullmatch: bash's =~ with $ does not accept a trailing newline; re's $ does.
    if not DIRECTIVE_ID.fullmatch(did):
        return None
    suffix = " " + did
    if not rest.endswith(suffix):
        return None
    fdir = rest[:-len(suffix)]
    return fdir or None


def _alive(pid, start):
    """Whether pid runs with this start time (2.4 form). A copy of the shape of
    _flow_factory.process_alive, which this module cannot import, with the
    start time compared, so a reused pid is not alive."""
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0 or not isinstance(start, str):
        return False
    try:
        os.kill(pid, 0)
    except PermissionError:
        pass
    except OSError:
        return False
    return lstart(pid) == start


def live_leases(factory_dir):
    """[lease dict] for every <F>/jobs/*/directives/*.lease.json whose
    revoked_at is null and whose launcher_pid runs with the launcher_start the
    lease records. A file that cannot be read as a JSON object is not a live
    lease."""
    if not factory_dir:
        return []
    out = []
    for path in sorted(glob.glob(os.path.join(glob.escape(factory_dir), "jobs", "*", "directives", "*.lease.json"))):
        try:
            with open(path, encoding="utf-8") as f:
                lease = json.load(f)
        except (OSError, ValueError):
            continue
        if not isinstance(lease, dict) or lease.get("revoked_at") is not None:
            continue
        if _alive(lease.get("launcher_pid"), lease.get("launcher_start")):
            out.append(lease)
    return out


def _which_git():
    """The first git on PATH outside a flow wrapper directory (hooks/shims
    beside scripts/lib/tier-runtime.sh), as _flow_factory.which_real finds it."""
    for d in os.environ.get("PATH", "").split(os.pathsep):
        d = d or "."
        path = os.path.join(d, "git")
        if not (os.path.isfile(path) and os.access(path, os.X_OK)):
            continue
        if os.path.isfile(os.path.join(d, "..", "scripts", "lib", "tier-runtime.sh")):
            continue
        return path
    return None


def _cwd_factory_dir(cwd=None):
    """<main checkout>/<runtime dir>/factory for the cwd's repository, or None
    outside a repository or when the runtime directory cannot be read."""
    git = _which_git()
    if not git:
        return None
    try:
        r = subprocess.run([git, "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd=cwd,
                           stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           universal_newlines=True, timeout=30, check=False)
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    common = r.stdout.strip()
    if r.returncode != 0 or not common:
        return None
    main_top = os.path.dirname(common)
    env = dict(os.environ)
    env.pop("PYTHONPATH", None)
    try:
        r = subprocess.run([os.path.join(BIN_DIR, "flow-runtime-dir.sh")], cwd=main_top, env=env,
                           stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           universal_newlines=True, timeout=30, check=False)
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    rel = r.stdout.strip()
    if r.returncode != 0 or not rel:
        return None
    return os.path.join(main_top, rel, "factory")


def _launcher_dir(anc):
    """The factory directory of the outermost entry of anc whose command is a
    marker naming a directory that holds a live lease of that entry (its pid
    and start time), or None."""
    found = None
    for pid, _ppid, start, command in anc:
        fdir = marker_factory_dir(command)
        if not fdir:
            continue
        if any(lease.get("launcher_pid") == pid and lease.get("launcher_start") == start
               for lease in live_leases(fdir)):
            found = fdir
    return found


def find_factory_dir(cwd=None):
    """(abs factory dir, "launcher") from the OUTERMOST ancestor (this process
    included) whose command is a marker naming a directory that holds a live
    lease with that ancestor's pid and start time as its launcher; else
    (abs factory dir, "cwd") from the cwd's main checkout; else (None, None).
    Raises AncestryUnreadable when the ancestry cannot be read."""
    fdir = _launcher_dir(ancestry())
    if fdir:
        return os.path.abspath(fdir), "launcher"
    fdir = _cwd_factory_dir(cwd)
    if fdir:
        return os.path.abspath(fdir), "cwd"
    return None, None


def in_session(env=None):
    """Whether this process runs inside a Claude session (design
    person_channels L37): CLAUDECODE is set and not empty, or an ancestor's
    command starts with a program whose name is exactly `claude`. ps does not
    quote the arguments, so a program path holding a space is read only up to
    that space. Raises AncestryUnreadable when the ancestry cannot be read."""
    env = os.environ if env is None else env
    if env.get("CLAUDECODE"):
        return True
    for _pid, _ppid, _start, command in ancestry()[1:]:
        program = command.split(" ", 1)[0]
        if os.path.basename(program) == "claude":
            return True
    return False


def check(subcommand, env=None):
    """None, or why the caller is refused:
    - "worker_env": the subcommand is a person subcommand, run, next or probe,
      and a worker variable is set and not empty;
    - "lease_ancestor": the subcommand is one of those, or launch or report,
      and an ancestor (pid and start time) is a live lease's launcher or claude
      process, in the factory directory a marker ancestor names or in the
      cwd's;
    - "ancestry_unreadable": the ancestry walk failed (fail closed).
    Every other subcommand (context, status, wait, question, runner, await)
    is never refused here and reads no ancestry. The variables are read
    first, then the ancestry, and only then the repository."""
    env = os.environ if env is None else env
    guarded = PERSON + ENGINE_GUARDED
    if subcommand not in guarded + INTERNAL:
        return None
    if subcommand in guarded and any(env.get(name) for name in WORKER_VARS):
        return "worker_env"
    try:
        anc = ancestry()
    except AncestryUnreadable:
        return "ancestry_unreadable"
    dirs = []
    for _pid, _ppid, _start, command in anc:
        fdir = marker_factory_dir(command)
        if fdir and fdir not in dirs:
            dirs.append(fdir)
    fdir = _cwd_factory_dir()
    if fdir and fdir not in dirs:
        dirs.append(fdir)
    # Ancestors only: the launcher applies its own report in its own process
    # (amendment B.7), so this process is never matched against a lease.
    above = set((pid, start) for pid, _ppid, start, _command in anc[1:])
    above_pids = set(pid for pid, _start in above)
    for fdir in dirs:
        for lease in live_leases(fdir):
            if (lease.get("launcher_pid"), lease.get("launcher_start")) in above:
                return "lease_ancestor"
            child, child_start = lease.get("child_pid"), lease.get("child_start")
            if child is None:
                continue
            if (child, child_start) in above or (child_start is None and child in above_pids):
                return "lease_ancestor"
    return None


def early_exit(argv):
    """Called from _flow_factory.py before its other imports, only when it runs
    as __main__: on a refusal print PERSON_ONLY_REFUSED=<reason>, flush stdout
    and leave with status 4 at once; otherwise return."""
    reason = check(argv[0] if argv else None)
    if reason is None:
        return
    sys.stdout.write("PERSON_ONLY_REFUSED=%s\n" % reason)
    sys.stdout.flush()
    os._exit(4)
