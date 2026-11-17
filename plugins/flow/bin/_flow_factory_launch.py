"""[flow] The factory launcher: `launch` claims a worker directive and starts
a detached launcher, which runs one `claude -p` worker, keeps its lease,
stops it at the stage timeout, charges the run and stores its result.

Two entry points:

  cmd_launch(argv)   `flow-factory.sh launch <directive-id>`, reached through
                     _flow_factory.py main. Under the job lock it checks the
                     directive and the launch conditions, and for a fresh
                     launch snapshots and resets a dirty job clone; for every
                     launch it rewrites the io directory's in/ from the job
                     folder's own copies. It then claims the directive
                     (started_at, max_budget_usd, model), double-forks, and
                     prints LAUNCHED directive=<id>. The grandchild execs the
                     launcher marker:
                       <recorded interpreter> -E <plugin>/bin/_flow_factory_launch.py
                         --factory-dir <F> <directive-id>
  cmd_report(argv)   `flow-factory.sh report`: the engine form refuses every
                     caller with PERSON_ONLY_REFUSED=not_launcher, because the
                     launcher applies its own report in its own process.

The launcher (this file run as a script) writes the lease, starts claude in
a session of its own, renews heartbeat_at every heartbeatSeconds under the
job lock, and at the directive's timeout_seconds sends SIGTERM to claude's
process group, then SIGKILL 30 s later. It waits until the whole group is
gone, not only claude, then parses the stream's top-level events, charges
the run (charge_run), and, under the job lock, writes results/<id>.json, the
job's cost and session, a charge event and a pending stage_succeeded or
stage_failed event (channel launcher). A usage limit stores no event and
sets state.json paused_until. When the recorded interpreter is no longer an
executable file at that point, it runs `flow-factory.sh report <id>` as its
direct child with the result record on stdin instead, and the wrapper
answers in shell. The launcher never sets revoked_at: only the engine
revokes a lease.

Refusals print one line and exit 5 (plan 1a, 2.6), or exit 4 for report.
Refusals from the probe gate, a missing prompt template, the stage budget
and a judge or directive kind also set the directive's not_started_reason
and append a launch_not_started event; no attempt is counted.
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

if __name__ == "__main__":
    # The engine modules import this one by name (plan 2.7 identity rule).
    sys.modules["_flow_factory_launch"] = sys.modules["__main__"]

import json
import re
import shutil
import signal
import socket
import stat
import subprocess
import time
import traceback
from datetime import UTC, datetime, timedelta
from decimal import Decimal

_BIN_DIR = os.path.dirname(os.path.realpath(__file__))
if _BIN_DIR not in sys.path:
    sys.path.append(_BIN_DIR)

# Every module the launcher uses is imported here, before claude starts, so
# removing the interpreter during the run cannot break a later import.
import _flow_factory as ff
from _flow_factory import Refused
import _flow_factory_jobs as jobs
import _flow_factory_git as fgit
import _flow_factory_schema as schema
import _flow_stream  # noqa: F401  (ff.result_event and ff.stream_events import it lazily)
from _journal_atomic import JournalAtomicError, _atomic_write, _read_with_no_follow

DIRECTIVE_ID = re.compile(r"^(issue-([1-9][0-9]*)-j[1-9][0-9]*)-(intake|prepare|spec|build|open_pr|gate|review"
                          r"|rework|sync|resolve|approve|merging)-[1-9][0-9]*$")
# The worker environment (plan 2.10; design execution_model L106-L112):
# phase 0's keep list (ported from flow-eval-run.sh), GH_HOST, GNUPGHOME and
# GPG_TTY, plus the worker.extraEnv names; never the names below, whatever
# the keep list or extraEnv says.
KEEP_ENV_NAMES = tuple(ff.KEEP_ENV_NAMES) + ("GH_HOST", "GNUPGHOME", "GPG_TTY")
KEEP_ENV_PATTERN = ff.KEEP_ENV_PATTERN
NEVER_PASSED = ("CLAUDECODE", "FLOW_TIER_DIR", "FLOW_TIER_CALL", "CLAUDE_HOOK_GOAL_JUDGE_MODE",
                "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS", "GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN",
                "GITHUB_ENTERPRISE_TOKEN", "SSH_AUTH_SOCK", "GIT_ASKPASS", "GIT_SSH", "GIT_SSH_COMMAND")
ENV_NAME = re.compile(r"^[A-Z_][A-Z0-9_]*$")
# --disallowedTools: the Bash prefixes of design execution_model L78. The
# protected-path Edit and Write rules come in phase 1e.
DISALLOWED_BASH = ("git push", "gh api", "gh issue create", "gh issue comment", "gh issue edit", "gh issue close",
                   "gh pr create", "gh pr comment", "gh pr review", "gh pr edit", "gh pr ready", "gh pr close",
                   "gh pr merge", "gh pr checkout")
DISALLOWED_TOOLS = tuple(f"Bash({p}:*)" for p in DISALLOWED_BASH)
NO_MCP = '{"mcpServers":{}}'
KILL_AFTER_SECONDS = 30
# How long the launcher waits for the group after SIGKILL before it gives
# up on it and reports anyway.
GONE_AFTER_KILL_SECONDS = 30
HEARTBEAT_LOCK_SECONDS = 5
POLL_SECONDS = 0.2
USAGE_LIMIT_PAUSE_SECONDS = 3600
# The {reason} of resume.prompt.md, by the row that relaunched the stage
# (the only rows that resume: 39, 39l, 44, 44r).
RESUME_REASONS = {
    "39": "the stage's last run failed",
    "39l": "the stage's last run stopped when its launcher stopped",
    "44": "a question the stage was blocked on was answered",
    "44r": "a person asked for the stage to be retried",
}
RESUME_REASON_OTHER = "the stage's earlier run stopped"


# ---------------------------------------------------------------- helpers

def _utc(dt=None):
    return (dt or datetime.now(UTC)).strftime("%Y-%m-%dT%H:%M:%SZ")


def lstart(pid):
    """The pid's start time in the plan 2.4 form (LC_ALL=C `ps -o lstart=`,
    outer white space removed), or None when ps prints nothing for it."""
    try:
        out = subprocess.run(["/bin/ps", "-o", "lstart=", "-p", str(pid)], env={"LC_ALL": "C"},
                             capture_output=True, text=True, check=False, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    return out.strip() or None


def ancestry_pids(pid):
    """[pid, its parent, ..., 1], read with /bin/ps one process at a time;
    the walk stops where ps prints nothing."""
    out, seen = [], set()
    while pid and pid not in seen:
        seen.add(pid)
        out.append(pid)
        if pid == 1:
            break
        try:
            text = subprocess.run(["/bin/ps", "-o", "ppid=", "-p", str(pid)], env={"LC_ALL": "C"},
                                  capture_output=True, text=True, check=False, timeout=10).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            break
        if not text.isdigit():
            break
        pid = int(text)
    return out


def _num(value):
    """A Decimal (or None) as the JSON number it is written as."""
    return None if value is None else ff.as_number(jobs.usd(value))


def _read_json(path):
    """The JSON value of a regular file read without following a symlink, or
    None when there is no such file. Raises ValueError for a file that
    cannot be read or parsed."""
    if not os.path.lexists(path):
        return None
    try:
        return json.loads(_read_with_no_follow(path))
    except (JournalAtomicError, UnicodeDecodeError, ValueError) as e:
        raise ValueError(str(e))


def _write_checked(path, data, def_name):
    """Validate data against the directive schema (its $defs entry def_name,
    or the top level for None), then replace the file atomically."""
    errors = schema.validate(data, jobs.DIRECTIVE_SCHEMA, def_name)
    if errors:
        raise Refused(f"{def_name or 'directive'}_invalid {errors[0]}")
    try:
        _atomic_write(path, json.dumps(data, sort_keys=True, indent=2) + "\n")
    except JournalAtomicError as e:
        raise Refused(f"{def_name or 'directive'}_unwritable {e.summary}")


def _real_dir(path):
    """Make path a real directory, never through a symlink: a symlink or a
    file there is removed first. The parent must exist. Plain os calls, as
    the engine's git module does: ensure_repo_dir runs flow's git wrapper
    in a Claude Code session."""
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        st = None
    if st is not None and not stat.S_ISDIR(st.st_mode):
        os.unlink(path)
        st = None
    if st is None:
        os.mkdir(path, 0o700)


def _job_dir(paths, n):
    return jobs.job_dir(paths, n)


def _directive_path(paths, n, did):
    return os.path.join(_job_dir(paths, n), "directives", did + ".json")


def _lease_path(paths, n, did):
    return os.path.join(_job_dir(paths, n), "directives", did + ".lease.json")


def _results_dir(paths, n):
    return os.path.join(_job_dir(paths, n), "results")


def _record(paths):
    return ff.read_record(os.path.join(paths.fdir, "probes.json"))


def _model(directive, record):
    """directive.model, else worker.model, else the probe record's platform
    model (plan 2.10 Model)."""
    if directive.get("model"):
        return directive["model"]
    m = jobs.setting("flow.factory.worker.model")
    if isinstance(m, str) and m:
        return m
    keyed = ((record.get("groups") or {}).get("platform") or {}).get("keyed_on") or {}
    m = keyed.get("model")
    return m if isinstance(m, str) and m else None


def _inside(path, folder):
    if not folder:
        return False
    p, f = os.path.realpath(path), os.path.realpath(folder)
    return p == f or p.startswith(f.rstrip(os.sep) + os.sep)


def job_env_text(job):
    """in/job.env: the four job values, one NAME=value line each."""
    vals = (("FLOW_FACTORY_JOB_KEY", job.get("key")), ("FLOW_FACTORY_ISSUE", job.get("issue")),
            ("FLOW_FACTORY_BRANCH", job.get("branch")), ("FLOW_FACTORY_GOAL_ID", job.get("goal_id")))
    return "".join(f"{k}={'' if v is None else v}\n" for k, v in vals)


def rewrite_in(paths, n, job):
    """Write J/in-copies/job.env from job.json, then make <io_dir>/in hold
    exactly the files of J/in-copies: every other entry is removed (a
    symlink is unlinked, never followed)."""
    jdir = _job_dir(paths, n)
    copies = os.path.join(jdir, "in-copies")
    _real_dir(copies)
    _atomic_write(os.path.join(copies, "job.env"), job_env_text(job))
    names = sorted(x for x in os.listdir(copies) if os.path.isfile(os.path.join(copies, x))
                   and not os.path.islink(os.path.join(copies, x)))
    in_dir = os.path.join(job["io_dir"], "in")
    _real_dir(in_dir)
    for entry in os.listdir(in_dir):
        p = os.path.join(in_dir, entry)
        if entry in names and os.path.isfile(p) and not os.path.islink(p):
            continue
        if os.path.isdir(p) and not os.path.islink(p):
            shutil.rmtree(p)
        else:
            os.unlink(p)
    for name in names:
        with open(os.path.join(copies, name), encoding="utf-8") as f:
            _atomic_write(os.path.join(in_dir, name), f.read())


def worker_path(record_interpreter, path):
    """The recorded interpreter's directory, then the caller's PATH without
    any directory that has ../scripts/lib/tier-runtime.sh beside it (flow's
    shims; the which_real rule)."""
    keep = [os.path.dirname(record_interpreter)]
    for d in (path or "").split(os.pathsep):
        if not d:
            continue
        if os.path.isfile(os.path.join(d, "..", "scripts", "lib", "tier-runtime.sh")):
            continue
        keep.append(d)
    return os.pathsep.join(keep)


def worker_env(base, *, record_interpreter, install, job, directive, paths, extra_names, gh_repo):
    """The worker environment, built from nothing (plan 2.10)."""
    env = {k: base[k] for k in KEEP_ENV_NAMES if k in base}
    for k, v in base.items():
        if KEEP_ENV_PATTERN.match(k):
            env[k] = v
    for k in extra_names:
        if k in base:
            env[k] = base[k]
    for k in NEVER_PASSED:
        env.pop(k, None)
    io_dir = job["io_dir"]
    env.update({
        "PATH": worker_path(record_interpreter, base.get("PATH", "")),
        "CLAUDE_PLUGIN_ROOT": install,
        "FLOW_STATE_DIR": os.path.join(os.path.dirname(io_dir), "state"),
        "FLOW_FACTORY_JOB": job["key"],
        "FLOW_FACTORY_DIRECTIVE": directive["id"],
        "FLOW_FACTORY_IO": io_dir,
        "FLOW_FACTORY_MAIN": paths.main,
        "FLOW_FACTORY_JOB_KEY": job["key"],
        "FLOW_FACTORY_ISSUE": str(job["issue"]),
        "FLOW_FACTORY_BRANCH": job.get("branch") or "",
        "FLOW_FACTORY_GOAL_ID": job.get("goal_id") or "",
        "GH_PROMPT_DISABLED": "1",
    })
    if gh_repo:
        env["GH_REPO"] = gh_repo
    else:
        env.pop("GH_REPO", None)
    return env


def worker_command(claude, *, install, job, directive, model):
    """The worker's claude -p argv (plan 2.10; no --max-turns, amendments
    A.6). The prompt goes on stdin."""
    mcp = jobs.setting("flow.factory.worker.mcpConfig")
    cmd = [claude, "-p", "--plugin-dir", install, "--add-dir", job["io_dir"],
           "--setting-sources", "project,local", "--strict-mcp-config",
           "--mcp-config", mcp if isinstance(mcp, str) and mcp.strip() else NO_MCP,
           "--output-format", "stream-json", "--verbose", "--permission-mode", "acceptEdits",
           "--allowedTools", ",".join(directive.get("allowed_tools") or []),
           "--permission-prompts", "none",
           "--disallowedTools", *DISALLOWED_TOOLS,
           "--max-budget-usd", jobs.usd_arg(directive["max_budget_usd"]),
           "--model", model]
    if directive["start_mode"] == "resume":
        cmd += ["--resume", job["sessions"][directive["stage"]], "--fork-session"]
    else:
        cmd += ["--session-id", directive["session_id"]]
    return cmd


def render_prompt(plugin, directive):
    """The prompt text: the stage template for a fresh launch, with a line
    naming the snapshot ref when one was made; resume.prompt.md for a
    resume, its placeholders filled and the lines they emptied removed."""
    snap = directive.get("snapshot_ref")
    snapshot_line = f"Edits from an earlier session are kept in {snap}." if snap else ""
    if directive["start_mode"] == "resume":
        with open(os.path.join(plugin, "templates", "factory", "resume.prompt.md"), encoding="utf-8") as f:
            text = f.read()
        fills = {"{reason}": RESUME_REASONS.get(directive.get("cause_row"), RESUME_REASON_OTHER),
                 "{snapshot_line}": snapshot_line,
                 # Questions arrive in phase 1c; 1a has none to name.
                 "{question_line}": ""}
        out = []
        for line in text.splitlines():
            filled = line
            for k, v in fills.items():
                filled = filled.replace(k, v)
            if filled.strip() == "" and line.strip() != "":
                continue
            out.append(filled)
        return "\n".join(out) + "\n"
    with open(os.path.join(plugin, "templates", "factory", f"{directive['stage']}.prompt.md"),
              encoding="utf-8") as f:
        text = f.read()
    if snapshot_line:
        text = text + ("" if text.endswith("\n") or not text else "\n") + snapshot_line + "\n"
    return text


def template_path(plugin, directive):
    name = "resume" if directive["start_mode"] == "resume" else directive["stage"]
    return os.path.join(plugin, "templates", "factory", f"{name}.prompt.md")


# ---------------------------------------------------------------- launch

def _print(line):
    print(line)
    sys.stdout.flush()


def _not_started(paths, n, job_key, directive, reason, line):
    """Record a refused launch (not_started_reason and a launch_not_started
    event) and print its line; exit status 5. Under the job lock."""
    if reason is not None:
        directive["not_started_reason"] = reason
        _write_checked(_directive_path(paths, n, directive["id"]), directive, None)
    jobs.append_event(paths, n, {"type": "launch_not_started", "job": job_key, "directive": directive["id"],
                                 "reason": reason or line})
    _print(line)
    return 5


def cmd_launch(argv):
    if len(argv) != 1 or argv[0].startswith("-"):
        print("flow-factory.sh launch: usage: flow-factory.sh launch <directive-id>", file=sys.stderr)
        return 2
    did = argv[0]
    m = DIRECTIVE_ID.match(did)
    if not m:
        raise Refused("directive_id_invalid")
    job_key, n, stage = m.group(1), int(m.group(2)), m.group(3)
    paths = jobs.resolve(create=False)
    record = _record(paths)
    interpreter = record.get("interpreter")
    if not isinstance(interpreter, str) or not os.path.isabs(interpreter):
        raise Refused("interpreter_missing recorded=none next: flow-factory.sh probe --environment")
    with jobs.job_lock(paths, n):
        try:
            directive = _read_json(_directive_path(paths, n, did))
        except ValueError:
            directive = None
        if not isinstance(directive, dict) or schema.validate(directive, jobs.DIRECTIVE_SCHEMA):
            raise Refused(f"directive_unknown directive={did}")
        job = jobs.read_job(paths, n)
        if (not isinstance(job, dict) or directive.get("id") != did or directive.get("job") != job_key
                or job.get("key") != job_key or job.get("directive") != did):
            raise Refused(f"directive_unknown directive={did}")
        if directive.get("started_at") is not None:
            raise Refused(f"directive_started directive={did}")
        kind = directive["kind"]
        if kind != "worker":
            return _not_started(paths, n, job_key, directive, "kind_not_built",
                                f"FACTORY_REFUSED=kind_not_built directive={did} kind={kind}")
        if not directive.get("session_id"):
            raise Refused(f"directive_unknown directive={did}")
        # The probe gate (T10, plan 2.12). A missing module refuses: an
        # unchecked record never launches.
        try:
            import _flow_factory_staleness as staleness
        except ModuleNotFoundError as e:
            if e.name != "_flow_factory_staleness":
                raise
            raise Refused("probes_unchecked (the staleness module is missing)")
        # claude is looked up before the gate, which runs `claude --version`
        # and would report a missing claude as a stale platform.
        claude = shutil.which("claude")
        if not claude:
            raise Refused(f"claude_missing directive={did}")
        line = staleness.launch_gate(paths.fdir, kind, jobs.setting)
        if line:
            return _not_started(paths, n, job_key, directive, "probes_stale", line)
        plugin = ff.PLUGIN_ROOT
        if not os.path.isfile(template_path(plugin, directive)):
            return _not_started(paths, n, job_key, directive, "prompt_missing",
                                f"FACTORY_REFUSED=prompt_missing stage={stage}")
        if _inside(plugin, paths.main) or _inside(plugin, job.get("worktree")):
            raise Refused("plugin_inside_repository")
        io_dir = job.get("io_dir")
        if not isinstance(io_dir, str) or not os.path.isabs(io_dir) or os.path.islink(io_dir) \
                or not os.path.isdir(io_dir):
            raise Refused(f"io_dir_missing directive={did}")
        worktree = job.get("worktree")
        if not isinstance(worktree, str) or not os.path.isabs(worktree) or os.path.islink(worktree) \
                or not os.path.isdir(worktree):
            raise Refused(f"worktree_missing directive={did}")
        if directive["start_mode"] == "resume" and not (job.get("sessions") or {}).get(stage):
            raise Refused(f"resume_session_missing directive={did} stage={stage}")
        budget = jobs.setting(f"flow.factory.worker.stages.{stage}.maxBudgetUsd")
        if isinstance(budget, bool) or not isinstance(budget, (int, float)) or budget <= 0:
            raise Refused(f"stage_budget_unset stage={stage}")
        spent = (job.get("cost") or {}).get("stage_usd", {}).get(stage, 0)
        allowance = jobs.turn_allowance(job)
        limit = jobs.launch_limit(budget, spent, allowance)
        if limit is None:
            return _not_started(paths, n, job_key, directive, "stage_budget_exhausted",
                                jobs.stage_budget_line(stage, budget, spent, allowance))
        model = _model(directive, record)
        if not model:
            raise Refused(f"model_unknown directive={did} next: set flow.factory.worker.model or "
                          "run flow-factory.sh probe --platform")
        # in/ first: a refusal there leaves the tree as it was, so a retry
        # still finds the dirty tree and snapshots it.
        try:
            rewrite_in(paths, n, job)
        except (OSError, JournalAtomicError) as e:
            raise Refused(f"io_dir_unwritable directive={did} {getattr(e, 'strerror', None) or e}")
        if directive["start_mode"] == "fresh":
            snap = _fresh_tree(paths, n, job, did)
            if snap:
                directive["snapshot_ref"] = snap
        directive["started_at"] = _utc()
        directive["max_budget_usd"] = _num(limit)
        directive["model"] = model
        _write_checked(_directive_path(paths, n, did), directive, None)
    _spawn(interpreter, paths.fdir, did)
    _print(f"LAUNCHED directive={did}")
    return 0


def _fresh_tree(paths, n, job, did):
    """Before a fresh launch: refuse a clone whose config changed or that
    holds an untracked nested repository (amendments A.11: no snapshot, no
    reset); snapshot a dirty tree, untracked files included, then reset and
    clean it. The snapshot is added to job.json snapshots, with a snapshot
    event carrying the whole list, before the reset: a write that fails
    leaves the edits in the tree as well as in the ref. Returns the snapshot
    ref, or None for a clean tree. Under the job lock."""
    clone = job["worktree"]
    copy_dir = os.path.join(_job_dir(paths, n), "clone-config")
    try:
        nested = fgit.nested_repositories(paths.fdir, clone)
        if nested:
            jobs.append_event(paths, n, {"type": "clone_config_changed", "job": job["key"], "directive": did,
                                         "nested_repository": nested[0]})
            raise Refused(f"nested_repository directive={did} path={nested[0]}")
        if not fgit.tree_dirty(paths.fdir, clone, copy_dir, n, job.get("goal_id")):
            return None
        reason = f"fresh launch of {did}"
        ref = fgit.snapshot(paths.fdir, clone, copy_dir, n, reason)
        at = _utc()
        entry = {"ref": ref, "k": int(ref.rsplit("-", 1)[1]), "reason": reason, "at": at}
        job["snapshots"] = list(job.get("snapshots") or []) + [entry]
        job["updated_at"] = at
        jobs.write_job(paths, job)
        jobs.append_event(paths, n, dict({"type": "snapshot", "job": job["key"], "directive": did},
                                         **entry, snapshots=job["snapshots"]))
        fgit.reset_and_clean(paths.fdir, clone, copy_dir)
        return ref
    except fgit.CloneConfigChanged as e:
        jobs.append_event(paths, n, {"type": "clone_config_changed", "job": job["key"], "directive": did,
                                     "file": e.file, "key": e.key})
        raise Refused(f"clone_config_changed directive={did} file={e.file} key={e.key}")
    except fgit.GitFailed as e:
        raise Refused(f"git_failed directive={did} {e}")


def _spawn(interpreter, fdir, did):
    """Double fork with os.setsid; the grandchild points 0, 1 and 2 at
    /dev/null and execs the launcher marker. Returns once the intermediate
    child has ended."""
    sys.stdout.flush()
    sys.stderr.flush()
    argv = [interpreter, "-E", os.path.join(ff.BIN_DIR, "_flow_factory_launch.py"), "--factory-dir",
            os.path.abspath(fdir), did]
    pid = os.fork()
    if pid == 0:
        # The intermediate child: a new session, one more fork, then gone,
        # so the launcher's parent is pid 1 and it has no terminal.
        status = 0
        try:
            os.setsid()
            if os.fork() == 0:
                status = 127
                null = os.open(os.devnull, os.O_RDWR)
                for fd in (0, 1, 2):
                    os.dup2(null, fd)
                if null > 2:
                    os.close(null)
                os.execv(interpreter, argv)
        except BaseException:  # noqa: BLE001 - a forked child must never return into main()
            status = status or 1
        os._exit(status)
    os.waitpid(pid, 0)


def cmd_report(argv):
    """The engine form of report accepts no caller: the launcher applies its
    own report in its own process (plan 2.4). A live lease's launcher or
    claude ancestor is refused earlier, by the early check."""
    print("PERSON_ONLY_REFUSED=not_launcher")
    return 4


# ---------------------------------------------------------------- launcher

class Launcher:
    def __init__(self, fdir, did):
        m = DIRECTIVE_ID.match(did)
        if not m:
            raise Refused("directive_id_invalid")
        self.did = did
        self.n = int(m.group(2))
        # The marker's F names where the log goes, so a failure before the
        # paths are resolved is still recorded.
        self.rdir = os.path.join(os.path.abspath(fdir), "jobs", f"issue-{self.n}", "results")
        self.pid = os.getpid()
        self.start = lstart(self.pid)
        self.paths = None
        self.proc = None
        self.pgid = None
        self.lease = None
        self.directive = self.job = None
        self.stream = None
        self.interpreter = ""
        self.paths = jobs.resolve(create=False)
        if os.path.realpath(self.paths.fdir) != os.path.realpath(fdir):
            raise Refused(f"factory_dir_mismatch marker={fdir} current={self.paths.fdir}")
        self.rdir = _results_dir(self.paths, self.n)

    def log(self, text):
        try:
            _real_dir(self.rdir)
            with open(os.path.join(self.rdir, self.did + ".launcher.log"), "a", encoding="utf-8") as f:
                f.write(f"{_utc()} {text}\n")
        except OSError:
            pass

    # The lease ---------------------------------------------------------
    def write_lease(self, **fields):
        path = _lease_path(self.paths, self.n, self.did)
        if self.lease is None:
            now = _utc()
            self.lease = {"directive": self.did, "kind": "worker", "host": socket.gethostname(),
                          "launcher_pid": self.pid, "launcher_start": self.start, "started_at": now,
                          "heartbeat_at": now, "child_pid": None, "child_pgid": None, "child_start": None,
                          "revoked_at": None}
        else:
            # Keep what the engine wrote (revoked_at) and change only these
            # fields.
            try:
                on_disk = _read_json(path)
            except ValueError:
                on_disk = None
            if isinstance(on_disk, dict):
                self.lease = on_disk
        self.lease.update(fields)
        _write_checked(path, self.lease, "lease")

    def beat(self):
        try:
            with jobs.job_lock(self.paths, self.n, timeout=HEARTBEAT_LOCK_SECONDS):
                self.write_lease(heartbeat_at=_utc())
        except Refused as r:
            self.log(f"heartbeat skipped: {r}")

    # The run -----------------------------------------------------------
    def group_alive(self):
        try:
            os.killpg(self.pgid, 0)
        except ProcessLookupError:
            return False
        except PermissionError:
            return True
        return True

    def signal_group(self, sig):
        try:
            os.killpg(self.pgid, sig)
        except OSError:
            pass

    def run(self):
        with jobs.job_lock(self.paths, self.n):
            directive = _read_json(_directive_path(self.paths, self.n, self.did))
            job = jobs.read_job(self.paths, self.n)
            if not isinstance(directive, dict) or not isinstance(job, dict) or not directive.get("started_at"):
                raise Refused(f"directive_unknown directive={self.did}")
            self.write_lease()
        self.directive, self.job = directive, job
        record = _record(self.paths)
        self.interpreter = record.get("interpreter") or ""
        plugin = ff.PLUGIN_ROOT
        stage = directive["stage"]
        extra = jobs.setting("flow.factory.worker.extraEnv") or []
        extra = [x for x in extra if isinstance(x, str) and ENV_NAME.match(x)] if isinstance(extra, list) else []
        heartbeat = jobs.setting("flow.factory.heartbeatSeconds")
        heartbeat = heartbeat if isinstance(heartbeat, int) and not isinstance(heartbeat, bool) and heartbeat > 0 \
            else 60
        timeout = directive.get("timeout_seconds") or 1800
        real_git = ff.which_real("git")
        gh_repo = ff.gh_default_repo(real_git) if real_git else None
        claude = shutil.which("claude")
        if not claude:
            raise Refused(f"claude_missing directive={self.did}")
        env = worker_env(dict(os.environ), record_interpreter=self.interpreter, install=plugin, job=job,
                         directive=directive, paths=self.paths, extra_names=extra, gh_repo=gh_repo)
        cmd = worker_command(claude, install=plugin, job=job, directive=directive, model=directive["model"])
        _real_dir(self.rdir)
        prompt_path = os.path.join(self.rdir, self.did + ".prompt.md")
        _atomic_write(prompt_path, render_prompt(plugin, directive))
        self.stream = os.path.join(self.rdir, self.did + ".stream.jsonl")
        flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW
        with open(prompt_path, "rb") as pin, \
                os.fdopen(os.open(self.stream, flags, 0o600), "wb") as sout, \
                os.fdopen(os.open(os.path.join(self.rdir, self.did + ".stderr.log"), flags, 0o600), "wb") as serr:
            self.proc = subprocess.Popen(cmd, stdin=pin, stdout=sout, stderr=serr, cwd=job["worktree"], env=env,
                                         start_new_session=True)
        self.pgid = self.proc.pid
        with jobs.job_lock(self.paths, self.n):
            self.write_lease(child_pid=self.proc.pid, child_pgid=self.pgid, child_start=lstart(self.proc.pid),
                             heartbeat_at=_utc())
        timed_out = self.watch(timeout, heartbeat, stage)
        self.finish(timed_out)

    def watch(self, timeout, heartbeat, stage):
        """Wait until claude has ended and its whole process group is gone,
        renewing the heartbeat; at the timeout send SIGTERM to the group,
        then SIGKILL 30 s later. Returns whether the timeout fired."""
        began = time.monotonic()
        next_beat = began + heartbeat
        term_at = kill_at = None
        while True:
            self.proc.poll()
            if self.proc.returncode is not None and not self.group_alive():
                break
            now = time.monotonic()
            if term_at is None and now >= began + timeout:
                self.log(f"stage timeout after {timeout} s: SIGTERM to group {self.pgid}")
                self.signal_group(signal.SIGTERM)
                term_at = now
            if term_at is not None and kill_at is None and now >= term_at + KILL_AFTER_SECONDS:
                self.log(f"group {self.pgid} still there {KILL_AFTER_SECONDS} s after SIGTERM: SIGKILL")
                self.signal_group(signal.SIGKILL)
                kill_at = now
            if kill_at is not None and now >= kill_at + GONE_AFTER_KILL_SECONDS:
                self.log(f"group {self.pgid} still there {GONE_AFTER_KILL_SECONDS} s after SIGKILL; reporting")
                break
            if now >= next_beat:
                self.beat()
                next_beat = time.monotonic() + heartbeat
            time.sleep(POLL_SECONDS)
        if self.proc.returncode is None:
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
        return term_at is not None

    def outcome(self, result, timed_out):
        """(outcome, event) of the run (plan T7 step 2.6)."""
        if timed_out:
            return "timeout", "stage_failed"
        if not isinstance(result, dict):
            rc = self.proc.returncode
            return ("killed" if isinstance(rc, int) and rc < 0 else "no_result"), "stage_failed"
        status, kind = result.get("api_error_status"), result.get("api_error")
        if status == 429 or (isinstance(kind, str) and "usage_limit" in kind):
            return "usage_limit", None
        if kind is not None or status is not None or result.get("terminal_reason") == "api_error":
            return "api_error", "stage_failed"
        if result.get("is_error") is True:
            return "error", "stage_failed"
        return "completed", "stage_succeeded"

    def finish(self, timed_out):
        directive, job = self.directive, self.job
        stage, mode = directive["stage"], directive["start_mode"]
        events = ff.stream_events(self.stream)
        result = ff.result_event(self.stream)
        init = ff.init_event(events)
        outcome, event = self.outcome(result, timed_out)
        resumed = (job.get("sessions") or {}).get(stage) if mode == "resume" else None
        sid = (init or {}).get("session_id") if isinstance((init or {}).get("session_id"), str) else None
        sid = sid or (resumed if mode == "resume" else directive.get("session_id"))
        allowance = jobs.turn_allowance(job)
        previous = (job.get("last_session_total") or {}).get(resumed) if resumed else None
        charge = jobs.charge_run(result, mode, previous, directive["max_budget_usd"], allowance)
        dearest = jobs.dearest_turn(self.stream)
        r = result if isinstance(result, dict) else {}

        def typed(key, kinds):
            v = r.get(key)
            return v if isinstance(v, kinds) and not (kinds is not bool and isinstance(v, bool)) else None

        record = {"directive": self.did, "outcome": outcome, "written_at": _utc(), "event": event,
                  "session_id": sid, "num_turns": typed("num_turns", int),
                  "api_error_status": typed("api_error_status", int), "is_error": typed("is_error", bool),
                  "permission_denials": typed("permission_denials", list),
                  "terminal_reason": typed("terminal_reason", str),
                  "charged_usd": _num(charge["charged_usd"]), "charge_basis": charge["basis"],
                  "total_cost_usd": _num(charge["total_cost_usd"]),
                  "since_last_usd": _num(charge["since_last_usd"])}
        if record["num_turns"] is not None and record["num_turns"] < 0:
            record["num_turns"] = None
        if not (os.path.isfile(self.interpreter) and os.access(self.interpreter, os.X_OK)):
            self.shell_report(record)
            return
        self.apply(record, charge, dearest, sid, event, outcome)
        if outcome == "usage_limit":
            self.pause()

    def apply(self, record, charge, dearest, sid, event, outcome):
        """Under the job lock: the result file, the job's cost and session,
        the charge event and the pending stage event (plan 2.4)."""
        deadline = time.monotonic() + 300
        while True:
            try:
                with jobs.job_lock(self.paths, self.n):
                    self._apply_locked(record, charge, dearest, sid, event, outcome)
                return
            except Refused as r:
                if not str(r).startswith("lock_timeout") or time.monotonic() > deadline:
                    raise
                self.log(f"report waiting for the job lock: {r}")

    def _apply_locked(self, record, charge, dearest, sid, event, outcome):
        stage = self.directive["stage"]
        job = jobs.read_job(self.paths, self.n)
        if not isinstance(job, dict):
            raise Refused(f"job_unreadable job=issue-{self.n}")
        _write_checked(os.path.join(self.rdir, self.did + ".json"), record, "result")
        cost = job["cost"]
        charged = charge["charged_usd"]
        cost["usd_total"] = jobs.usd(cost.get("usd_total", 0)) + charged
        cost.setdefault("stage_usd", {})
        cost["stage_usd"][stage] = jobs.usd(cost["stage_usd"].get(stage, 0)) + charged
        cost.setdefault("runs", []).append({"directive": self.did, "session_id": sid, "charged_usd": charged,
                                            "basis": charge["basis"], "total_cost_usd": charge["total_cost_usd"],
                                            "since_last_usd": charge["since_last_usd"]})
        if dearest is not None:
            cost["dearest_turn_usd"] = max(jobs.usd(cost.get("dearest_turn_usd", 0)), dearest)
        if sid and charge["total_cost_usd"] is not None:
            totals = job.get("last_session_total") or {}
            totals[sid] = charge["total_cost_usd"]
            job["last_session_total"] = totals
        if sid:
            job.setdefault("sessions", {})[stage] = sid
        job["updated_at"] = _utc()
        jobs.write_job(self.paths, job)
        jobs.append_event(self.paths, self.n, {
            "type": "charge", "job": job["key"], "directive": self.did, "stage": stage, "session_id": sid,
            "charged_usd": charged, "basis": charge["basis"], "total_cost_usd": charge["total_cost_usd"],
            "since_last_usd": charge["since_last_usd"], "dearest_turn_usd": cost["dearest_turn_usd"]})
        if event:
            caller = {"pid": self.pid, "start": self.start or "", "ancestry": ancestry_pids(self.pid)}
            jobs.store_pending(self.paths, self.n, event, {"directive": self.did, "outcome": outcome},
                               "launcher", caller, {})

    def pause(self):
        """A usage limit: state.json paused_until, now + 3600 s (no result
        field gives a reset time; amendments A.8), never earlier than a pause
        already set. The global lock, after the job lock is released."""
        until = _utc(datetime.now(UTC) + timedelta(seconds=USAGE_LIMIT_PAUSE_SECONDS))
        with jobs.global_lock(self.paths):
            state = jobs.read_state(self.paths)
            old = state.get("paused_until")
            if not (isinstance(old, str) and old > until):
                state["paused_until"] = until
            jobs.write_state(self.paths, state)

    def shell_report(self, record):
        """The recorded interpreter is gone: `flow-factory.sh report <id>` as
        this process's direct child, from the main checkout, with the result
        record on stdin. The wrapper appends a pending-report line naming
        this process; the engine applies it once the interpreter is back."""
        wrapper = os.path.join(ff.BIN_DIR, "flow-factory.sh")
        p = subprocess.run([wrapper, "report", self.did], input=json.dumps(record), text=True,
                           capture_output=True, cwd=self.paths.main, timeout=120, check=False)
        self.log(f"shell report: exit {p.returncode} {p.stdout.strip()} {p.stderr.strip()}")

    def fail_closed(self, exc):
        """After an exception. A run that started is stopped (SIGKILL to its
        group) and then finished as usual, so it is charged (its limit plus
        the allowance when the stream has no result event) and leaves a
        pending stage_failed. When that fails too, or claude never started,
        a result is written without touching job.json: not_started (no event,
        no charge) before claude started; after it, no_result with the
        limit_plus_turn charge and a pending stage_failed, for the engine to
        apply."""
        self.log("launcher failed:\n" + "".join(traceback.format_exception(exc)))
        if self.paths is None:
            return
        if self.pgid is not None:
            if self.group_alive():
                self.signal_group(signal.SIGKILL)
            end = time.monotonic() + 10
            while self.group_alive() and time.monotonic() < end:
                if self.proc is not None:
                    self.proc.poll()
                time.sleep(POLL_SECONDS)
            if self.directive is not None and self.stream is not None:
                try:
                    self.finish(False)
                    return
                except BaseException as e:  # noqa: BLE001 - fall back to the bare record below
                    self.log("finishing after the failure failed:\n" + "".join(traceback.format_exception(e)))
        try:
            self._bare_result()
        except BaseException as e:  # noqa: BLE001 - the last record of a launcher that already failed
            self.log(f"no result written: {e}")

    def _bare_result(self):
        started = self.proc is not None
        charge = {"charged_usd": None, "basis": None}
        if started:
            job = jobs.read_job(self.paths, self.n)
            allowance = jobs.turn_allowance(job if isinstance(job, dict) else {})
            charge = jobs.charge_run(None, self.directive["start_mode"], None, self.directive["max_budget_usd"],
                                     allowance)
        with jobs.job_lock(self.paths, self.n):
            path = os.path.join(self.rdir, self.did + ".json")
            if os.path.lexists(path):
                return
            _real_dir(self.rdir)
            _write_checked(path, {
                "directive": self.did, "outcome": "no_result" if started else "not_started",
                "written_at": _utc(), "event": "stage_failed" if started else None,
                "session_id": (self.directive or {}).get("session_id") if started else None,
                "num_turns": None, "api_error_status": None, "is_error": None, "permission_denials": None,
                "terminal_reason": None, "charged_usd": _num(charge["charged_usd"]),
                "charge_basis": charge["basis"], "total_cost_usd": None, "since_last_usd": None}, "result")
            if started:
                caller = {"pid": self.pid, "start": self.start or "", "ancestry": ancestry_pids(self.pid)}
                jobs.store_pending(self.paths, self.n, "stage_failed",
                                   {"directive": self.did, "outcome": "no_result"}, "launcher", caller, {})


def launcher_main(argv):
    if len(argv) != 3 or argv[0] != "--factory-dir" or not DIRECTIVE_ID.match(argv[2]):
        return 2
    launcher = None
    try:
        launcher = Launcher(argv[1], argv[2])
        launcher.run()
        return 0
    except BaseException as e:  # noqa: BLE001 - nothing reads this process's output
        if launcher is not None:
            launcher.fail_closed(e)
        return 1


if __name__ == "__main__":
    sys.exit(launcher_main(sys.argv[1:]))
