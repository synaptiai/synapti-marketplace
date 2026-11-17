"""[flow] The factory's person subcommands, rebuild, status and context --mode
(plan 1a T12; design person_channels, factory_mode_in_commands).

  cmd_person(sub, argv)   answer, approve-spec, confirm, feedback, rework,
                          retry, reject, cancel: look the job up, check that
                          the event occurs in the job's state (exit 3), get
                          the person's confirmation (exit 4), then store the
                          event in J/pending for the next pass to apply
  cmd_rebuild(argv)       rebuild <job>: row 68, applied here; job.json is
                          rebuilt from events.jsonl, the directive files and
                          the clone, the old bytes kept in job.json.bak
  cmd_status(argv)        status [--brief|--json]
  cmd_context(argv)       context --mode: FACTORY_MODE=off|on|invalid

The worker refusal (PERSON_ONLY_REFUSED, exit 4) has already run in
_flow_factory.py's early check before any of these, and main has applied the
enabled gate and the factory path check (plan 2.7).

The confirmation holds no lock while it waits at the terminal (amendment
A+7). Inside a Claude session (CLAUDECODE set, or an ancestor whose program is
named claude) phase 1a has no heartbeat record to show the session's
permission mode, so every always-ask subcommand, rebuild, and answer with
--text are refused with PERSON_CONFIRM_REQUIRED (person_channels L38; rows
69a-69h); answer with --choice only is taken as the session's answer
(person_channels L40). Outside a session the subcommand opens /dev/tty,
prints what it is about to do, and acts only when the job key is typed back
(person_channels L42).
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

import copy
import glob
import json
import re
import select
import shlex
import tempfile
import time
from decimal import Decimal

_BIN_DIR = os.path.dirname(os.path.realpath(__file__))
if _BIN_DIR not in sys.path:
    sys.path.append(_BIN_DIR)

import _flow_factory as ff
from _flow_factory import Refused
import _flow_factory_jobs as jobs
import _flow_factory_caller as fcaller
import _flow_factory_git as fgit
import _flow_factory_schema as fschema
import _flow_factory_staleness as staleness
import _flow_factory_table as ftable
from _journal_atomic import JournalAtomicError, _read_with_no_follow

EVENTS = {"answer": "person_answer", "approve-spec": "person_approve_spec", "confirm": "person_confirm",
          "feedback": "person_feedback", "rework": "person_rework", "retry": "person_retry",
          "reject": "person_reject", "cancel": "person_cancel", "rebuild": "person_rebuild"}
PROMPT = "type the job key to confirm: "
# How long the terminal prompt waits for the typed key before it gives up.
TTY_WAIT_SECONDS = 600
JOB_KEY = re.compile(r"^issue-([1-9][0-9]*)-j[1-9][0-9]*$")
ISSUE_NUMBER = re.compile(r"^[1-9][0-9]*$")
ITEM_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")
HEX = re.compile(r"^[0-9a-f]{12,64}$")
PASS_ID = re.compile(r"^p([0-9]+)$")
WORKER_VARS = ("FLOW_FACTORY_JOB", "FLOW_FACTORY_DIRECTIVE")


class _Usage(Exception):
    pass


def _usage(sub, message):
    sys.stderr.write(f"flow-factory.sh {sub}: {message}\n")
    return 2


def _parse(argv, positional, options, required=()):
    """(positional values, {option: value}) from argv: exactly the named
    positional arguments, and --name value or --name=value for each option in
    options ({name: "int" | "text"}). Raises _Usage."""
    pos, opts = [], {}
    args = list(argv)
    while args:
        a = args.pop(0)
        if a.startswith("--"):
            name, eq, value = a[2:].partition("=")
            if name not in options:
                raise _Usage(f"unknown option {a}")
            if not eq:
                if not args:
                    raise _Usage(f"--{name} needs a value")
                value = args.pop(0)
            if name in opts:
                raise _Usage(f"--{name} given twice")
            if options[name] == "int":
                if not ISSUE_NUMBER.match(value):
                    raise _Usage(f"--{name} must be a whole number of 1 or more, not {value!r}")
                value = int(value)
            elif value == "":
                raise _Usage(f"--{name} must not be empty")
            opts[name] = value
        else:
            pos.append(a)
    if len(pos) != len(positional):
        raise _Usage(f"needs {' '.join('<' + p + '>' for p in positional)}" if len(pos) < len(positional)
                     else f"unexpected argument {pos[len(positional)]!r}")
    for name in required:
        if name not in opts:
            raise _Usage(f"--{name} is required")
    return pos, opts


# ---------------------------------------------------------------- lookups

def _job_arg(arg):
    """(issue number, job key or None) from a job key or an issue number."""
    m = JOB_KEY.match(arg or "")
    if m:
        return int(m.group(1)), arg
    if ISSUE_NUMBER.match(arg or ""):
        return int(arg), None
    raise Refused(f"job_unknown job={arg}")


def _lookup_job(paths, arg):
    n, key = _job_arg(arg)
    job = jobs.read_job(paths, n)
    if job is None:
        raise Refused(f"job_unknown job={arg}")
    if isinstance(job, jobs.Unreadable):
        raise Refused(f"job_unreadable job={job.folder}")
    if key is not None and job.get("key") != key:
        raise Refused(f"job_unknown job={arg}")
    return n, job


def _read_item(path):
    try:
        data = json.loads(_read_with_no_follow(path))
    except (JournalAtomicError, UnicodeDecodeError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def _lookup_item(paths, folder, item, refusal):
    """The job that J/<folder>/<item>.json names in its job field: answer's
    question (J/questions) and confirm's intent (J/outbox)."""
    if not ITEM_ID.match(item):
        raise Refused(refusal)
    pattern = os.path.join(glob.escape(paths.fdir), "jobs", "issue-*", folder, glob.escape(item) + ".json")
    for path in sorted(glob.glob(pattern)):
        data = _read_item(path)
        key = data.get("job") if data else None
        m = JOB_KEY.match(key) if isinstance(key, str) else None
        if not m or os.path.basename(os.path.dirname(os.path.dirname(path))) != f"issue-{m.group(1)}":
            continue
        try:
            return _lookup_job(paths, key)
        except Refused as r:
            if str(r).startswith("job_unknown"):
                continue
            raise
    raise Refused(refusal)


def _occurs(table, event, state):
    return state in table.events.get(event, {}).get("occurs_in", [])


def _caller():
    pid = os.getpid()
    try:
        pids = [p for p, _ppid, _start, _cmd in fcaller.ancestry()]
    except fcaller.AncestryUnreadable:
        pids = [pid, os.getppid()]
    return {"pid": pid, "start": fcaller.lstart(pid) or "", "ancestry": pids or [pid]}


# ---------------------------------------------------------------- confirmation

def _required_line(sub, argv):
    command = " ".join(shlex.quote(x) for x in ["flow-factory.sh", sub] + list(argv))
    return f"PERSON_CONFIRM_REQUIRED next: run {command} in a terminal"


def _read_typed(fd, seconds):
    """One line typed at the terminal, or None at the time limit or EOF."""
    end = time.monotonic() + seconds
    got = b""
    while b"\n" not in got and b"\r" not in got:
        left = end - time.monotonic()
        if left <= 0:
            return None
        ready, _, _ = select.select([fd], [], [], left)
        if not ready:
            continue
        try:
            data = os.read(fd, 1024)
        except OSError:
            return None
        if not data:
            return None
        got += data
    return got.splitlines()[0].decode("utf-8", "replace") if got.splitlines() else ""


def confirm(sub, argv, job, session_ok=False):
    """The channel the person confirmed on ("terminal", or "session:<id>" for
    answer --choice from a session), or None after printing
    PERSON_CONFIRM_REQUIRED. Holds no lock."""
    required = _required_line(sub, argv)
    try:
        inside = fcaller.in_session()
    except fcaller.AncestryUnreadable:
        inside = True
    if inside:
        # Phase 1a has no heartbeat record that could show the session's
        # permission mode (person_channels L38): only answer --choice is taken
        # from a session (L40). For answer --text this check sits outside the
        # table (amendment C conflicts 2); for the always-ask subcommands it is
        # rows 69a-69h with unvouched_session_action true.
        if session_ok:
            return "session:" + (os.environ.get("CLAUDE_SESSION_ID") or "unknown")
        print(required)
        return None
    try:
        fd = os.open("/dev/tty", os.O_RDWR | os.O_NOCTTY)
    except OSError:
        print(required)
        return None
    try:
        shown = " ".join(shlex.quote(x) for x in ["flow-factory.sh", sub] + list(argv))
        os.write(fd, (f"job {job['key']} state={job['state']}\ncommand: {shown}\n{PROMPT}").encode("utf-8"))
        typed = _read_typed(fd, TTY_WAIT_SECONDS)
        if typed is None:
            # End the prompt line on the terminal, not on stdout: a refusal
            # is exactly one stdout line (plan 2.6).
            os.write(fd, b"\n")
    except OSError:
        typed = None
    finally:
        os.close(fd)
    if typed is None or typed.strip() != job["key"]:
        print(required)
        return None
    return "terminal"


# ---------------------------------------------------------------- person subcommands

def _person_args(sub, argv):
    """(job argument or None, item kind and id or None, event args)."""
    if sub == "answer":
        (qid,), o = _parse(argv, ["qid"], {"choice": "int", "text": "text"}, required=("choice",))
        args = {"qid": qid, "choice": o["choice"]}
        if "text" in o:
            args["text"] = o["text"]
        return None, ("questions", qid), args
    if sub == "approve-spec":
        (job,), o = _parse(argv, ["job"], {"spec-hash": "text", "head": "text"}, required=("spec-hash",))
        for name in ("spec-hash", "head"):
            if name in o and not HEX.match(o[name]):
                raise _Usage(f"--{name} must be 12 to 64 lower-case hex digits")
        args = {"spec_hash": o["spec-hash"]}
        if "head" in o:
            args["head"] = o["head"]
        return job, None, args
    if sub == "confirm":
        (intent,), _ = _parse(argv, ["intent"], {})
        return None, ("outbox", intent), {"intent": intent}
    if sub in ("feedback", "rework"):
        (job, text), _ = _parse(argv, ["job", "text"], {})
        if not text.strip():
            raise _Usage("the text must not be empty")
        return job, None, {"text": text}
    (job,), _ = _parse(argv, ["job"], {})
    return job, None, {}


def cmd_person(sub, argv):
    event = EVENTS.get(sub)
    if event is None or sub == "rebuild":
        return _usage(sub, "not a person subcommand")
    try:
        job_arg, item, args = _person_args(sub, argv)
    except _Usage as u:
        return _usage(sub, str(u))
    paths = jobs.resolve(create=False)
    table = ftable.load_table()
    if item is not None:
        folder, ident = item
        what = "question_unknown qid" if folder == "questions" else "intent_unknown intent"
        n, job = _lookup_item(paths, folder, ident, f"{what}={ident}")
    else:
        n, job = _lookup_job(paths, job_arg)
    if not _occurs(table, event, job["state"]):
        print(f"EVENT_REFUSED={event} state={job['state']}")
        return 3
    channel = confirm(sub, argv, job, session_ok=(sub == "answer" and "text" not in args))
    if channel is None:
        return 4
    caller = _caller()
    with jobs.job_lock(paths, n):
        again = jobs.read_job(paths, n)
        if isinstance(again, jobs.Unreadable):
            raise Refused(f"job_unreadable job={again.folder}")
        if not isinstance(again, dict) or again.get("key") != job["key"]:
            raise Refused(f"job_unknown job={job['key']}")
        if not _occurs(table, event, again["state"]):
            print(f"EVENT_REFUSED={event} state={again['state']}")
            return 3
        jobs.store_pending(paths, n, event, args, channel, caller, {"unvouched_session_action": False})
    print(f"RAISED {event} job={job['key']}")
    return 0


# ---------------------------------------------------------------- rebuild

def _read_events(path):
    """The lines of events.jsonl, each a dict. A line that is not a JSON
    object is refused: replaying around it could give a wrong state."""
    try:
        text = _read_with_no_follow(path)
    except (JournalAtomicError, UnicodeDecodeError):
        raise Refused(f"events_unreadable file={path}")
    out = []
    for i, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        try:
            data = json.loads(line)
        except ValueError:
            data = None
        if not isinstance(data, dict):
            raise Refused(f"events_unreadable file={path} line={i}")
        out.append(data)
    return out


def _new_job(n):
    return {"apiVersion": "flow.synapti.ai/v1", "kind": "FlowFactoryJob", "key": f"issue-{n}-j1", "issue": n,
            "state": "queued", "attempt": 0, "stage_launches": {}, "sessions": {}, "holds_slot": False,
            "directive": None, "cost": {"usd_total": 0, "runs": [], "stage_usd": {}, "dearest_turn_usd": 0},
            "created_at": None, "updated_at": None, "vouch_at": None}


def _start(n, lines):
    """(starting job, index of the first line after the created line): the
    last created line's record, else a new job."""
    idx = None
    for i, line in enumerate(lines):
        if line.get("type") == "created" and isinstance(line.get("record"), dict):
            idx = i
    if idx is None:
        job = _new_job(n)
        job["created_at"] = lines[0].get("time") if lines else ff.utc_now()
        return job, 0
    created = lines[idx]
    job = copy.deepcopy(created["record"])
    if isinstance(created.get("to"), str):
        job["state"] = created["to"]
    if not job.get("created_at"):
        job["created_at"] = created.get("time")
    return job, idx + 1


def _recorded_state(n, lines):
    """The state the log records: the to of the last move, else the created
    state."""
    job, first = _start(n, lines)
    state = job.get("state")
    for line in lines[first:]:
        if line.get("type") == "transition" and not line.get("stay") and isinstance(line.get("to"), str):
            state = line["to"]
    return job.get("key"), state


def _pass_no(pid):
    m = PASS_ID.match(pid) if isinstance(pid, str) else None
    return int(m.group(1)) if m else None


class _Replayed(object):
    """What _run_job_handler reads of a decision: the row id."""

    def __init__(self, row):
        self.row = row


def _directives(jdir, key):
    """[(stage, k, created_in_pass number or -1)] of J/directives/<key>-<stage>-<k>.json."""
    pat = re.compile(r"^" + re.escape(key) + r"-([a-z_]+)-([1-9][0-9]*)\.json$")
    out = []
    try:
        names = os.listdir(os.path.join(jdir, "directives"))
    except OSError:
        return out
    for name in names:
        m = pat.match(name)
        if not m:
            continue
        d = _read_item(os.path.join(jdir, "directives", name)) or {}
        p = _pass_no(d.get("created_in_pass"))
        out.append((m.group(1), int(m.group(2)), -1 if p is None else p))
    return out


def rebuild_job(paths, table, n, lines, now):
    """job.json rebuilt from the event log (plan T12 rebuild table). Raises
    ftable.TransitionRefused at the first recorded move no row makes.

    - The created line's record is the starting job (a new job without one).
    - Each transition line is checked with check_move, then its state, its
      records, the job-field effects it applied (reason, paused_reason, the
      counters, round_limit, build_started, attempt, relaunch) and its attempt
      are replayed in order, and pending_changes loses the facts its row read
      as true, as apply() does.
    - The slot is the last slot line (taken or freed).
    - cost, last_session_total and sessions come from the charge lines.
    - stage_launches is the largest k per stage of the directive files, and
      directive the newest of them (the live engine never clears it).
    - relaunch is kept only when no directive was made at or after the pass
      that set it; lease_grace is null.
    - head_sha is the clone's HEAD when the clone exists."""
    job, first = _start(n, lines)
    key = job["key"]
    setting_ctx = ftable.Context(setting=jobs.setting)
    relaunch_pass = None
    job["relaunch"] = None
    runs, total, by_stage, dearest = [], Decimal(0), {}, Decimal(0)
    totals = dict(job.get("last_session_total") or {})
    sessions = dict(job.get("sessions") or {})
    for line in lines[first:]:
        kind = line.get("type")
        if kind == "transition":
            frm, to, stay = line.get("from"), line.get("to"), bool(line.get("stay"))
            ftable.check_move(table, frm, None if stay else to, line.get("event"))
            before = copy.deepcopy(job)
            if not stay:
                job["state"] = to
            for k, v in (line.get("records") or {}).items():
                job[k] = v
            row = table.by_id.get(line.get("row"))
            for e in line.get("effects_applied") or []:
                ekind, name = ftable.EFFECTS.get(e, (None, None))
                if ekind != "handled" or name not in ftable.JOB_HANDLERS:
                    continue
                if name in ("relaunch_fresh", "relaunch_resume"):
                    relaunch_pass = _pass_no(line.get("pass"))
                ftable._run_job_handler(name, e, job, before, _Replayed(line.get("row")), setting_ctx)
            if isinstance(line.get("attempt"), int) and not isinstance(line.get("attempt"), bool):
                job["attempt"] = line["attempt"]
            pending = job.get("pending_changes")
            if isinstance(pending, list) and row is not None:
                cleared = set(f for f, v in row.get("guard", {}).items() if v is True)
                job["pending_changes"] = [f for f in pending if f not in cleared]
        elif kind == "slot":
            if line.get("taken") is True:
                job["holds_slot"] = True
            elif line.get("freed") is True:
                job["holds_slot"] = False
        elif kind == "charge":
            charged = jobs.usd(line.get("charged_usd")) or Decimal(0)
            stage = line.get("stage")
            sid = line.get("session_id") if isinstance(line.get("session_id"), str) else None
            runs.append({"directive": line.get("directive"), "session_id": sid, "charged_usd": charged,
                         "basis": line.get("basis"), "total_cost_usd": jobs.usd(line.get("total_cost_usd")),
                         "since_last_usd": jobs.usd(line.get("since_last_usd"))})
            total += charged
            by_stage[stage] = by_stage.get(stage, Decimal(0)) + charged
            if line.get("dearest_turn_usd") is not None:
                dearest = jobs.usd(line["dearest_turn_usd"])
            if sid and line.get("total_cost_usd") is not None:
                totals[sid] = jobs.usd(line["total_cost_usd"])
            if sid and stage in table.states:
                sessions[stage] = sid
    job["cost"] = {"usd_total": total, "runs": runs, "stage_usd": by_stage, "dearest_turn_usd": dearest}
    if totals:
        job["last_session_total"] = totals
    job["sessions"] = sessions
    jdir = jobs.job_dir(paths, n)
    made = _directives(jdir, key)
    launches = {}
    for stage, k, _p in made:
        launches[stage] = max(launches.get(stage, 0), k)
    job["stage_launches"] = launches
    newest = max(made, key=lambda x: (x[2], x[1]), default=None)
    job["directive"] = f"{key}-{newest[0]}-{newest[1]}" if newest else None
    if job.get("relaunch") is not None and relaunch_pass is not None and any(p >= relaunch_pass for _s, _k, p in made):
        job["relaunch"] = None
    job["lease_grace"] = None
    wt = job.get("worktree")
    if isinstance(wt, str) and os.path.isdir(wt):
        try:
            rc, out, _err = fgit.git(paths.fdir, ["rev-parse", "--verify", "-q", "HEAD^{commit}"], wt, clone=wt,
                                     copy_dir=os.path.join(jdir, "clone-config"))
            if rc == 0 and out.strip():
                job["head_sha"] = out.strip()
        except fgit.CloneConfigChanged:
            pass
    job["updated_at"] = now
    return job


def _write_bak(jdir):
    """job.json's old bytes to job.json.bak, when job.json is a regular
    file; nothing otherwise."""
    path = os.path.join(jdir, "job.json")
    try:
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    except OSError:
        return False
    try:
        chunks = []
        while True:
            b = os.read(fd, 65536)
            if not b:
                break
            chunks.append(b)
    finally:
        os.close(fd)
    tfd, tmp = tempfile.mkstemp(dir=jdir, prefix="job.json.bak.", suffix=".tmp")
    try:
        with os.fdopen(tfd, "wb") as f:
            f.write(b"".join(chunks))
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, os.path.join(jdir, "job.json.bak"))
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return True


def cmd_rebuild(argv):
    try:
        (job_arg,), _ = _parse(argv, ["job"], {})
    except _Usage as u:
        return _usage("rebuild", str(u))
    n, key_arg = _job_arg(job_arg)
    paths = jobs.resolve(create=False)
    table = ftable.load_table()
    jdir = jobs.job_dir(paths, n)
    events_path = os.path.join(jdir, "events.jsonl")
    if not os.path.isdir(jdir) or not (os.path.lexists(events_path) or os.path.lexists(os.path.join(jdir, "job.json"))):
        raise Refused(f"job_unknown job={job_arg}")
    lines = _read_events(events_path) if os.path.lexists(events_path) else []
    key, state = _recorded_state(n, lines)
    if key_arg is not None and key != key_arg:
        raise Refused(f"job_unknown job={job_arg}")
    if not _occurs(table, "person_rebuild", state):
        print(f"EVENT_REFUSED=person_rebuild state={state}")
        return 3
    channel = confirm("rebuild", argv, {"key": key, "state": state})
    if channel is None:
        return 4
    caller = _caller()
    with jobs.job_lock(paths, n):
        lines = _read_events(events_path) if os.path.lexists(events_path) else []
        try:
            new = rebuild_job(paths, table, n, lines, ff.utc_now())
        except ftable.TransitionRefused as e:
            print(e.line)
            return 3
        errors = fschema.validate(jobs._jsonable(new), jobs.JOB_SCHEMA)
        if errors:
            raise Refused(f"job_invalid {errors[0]}")
        bak = _write_bak(jdir)
        jobs.write_job(paths, new)
        row = table.by_id["68"]
        jobs.append_event(paths, n, {
            "type": "rebuilt", "job": new["key"], "row": "68", "event": "person_rebuild", "from": new["state"],
            "to": None, "stay": True, "effects_applied": list(row.get("effects", [])), "effects_deferred": [],
            "attempt": new.get("attempt"), "channel": channel, "caller": caller, "records": {},
            "bak": "job.json.bak" if bak else None})
    print(f"REBUILT job={new['key']} state={new['state']}")
    return 0


# ---------------------------------------------------------------- status

def _status_paths():
    """Paths for the factory folder find_factory_dir names (a worker's
    launcher's, else the cwd's), with the process in its main checkout."""
    try:
        fdir, how = fcaller.find_factory_dir()
    except fcaller.AncestryUnreadable:
        fdir, how = None, None
    if how == "launcher" and os.path.isdir(fdir):
        paths = jobs.resolve(cwd=fdir, create=False)
        return jobs.Paths(paths.main, fdir, paths.plugin)
    return jobs.resolve(create=False)


def _after_last_move(lines):
    last = -1
    for i, line in enumerate(lines):
        if line.get("type") in ("transition", "created") and not line.get("stay"):
            last = i
    return lines[last + 1:]


def _job_events(paths, n):
    path = os.path.join(jobs.job_dir(paths, n), "events.jsonl")
    if not os.path.lexists(path):
        return []
    try:
        return _read_events(path)
    except Refused:
        return []


def _engine_lines(paths, table, found, state):
    """The engine's own status lines that hold now, by group (plan 2.6
    order), and the live orphan groups and outbox counts."""
    import _flow_factory_next as fnext
    groups = {g: [] for g in ("usage", "budget", "orphan", "blocked", "clone", "outbox", "sync")}
    orphans, outbox = [], []
    until = state.get("paused_until")
    if isinstance(until, str) and until > ff.utc_now():
        groups["usage"].append(f"PAUSED usage_limit until={until}")
    for n, job in found:
        if not isinstance(job, dict) or table.kind(job.get("state")) == "terminal":
            continue
        key, st = job["key"], job["state"]
        jdir = jobs.job_dir(paths, n)
        if table.states.get(st, {}).get("run_by") == "worker" and not fnext.directive_open(paths, n, job.get("directive")):
            budget = jobs.setting(f"flow.factory.worker.stages.{st}.maxBudgetUsd")
            if not isinstance(budget, bool) and isinstance(budget, (int, float)) and budget > 0:
                spent = (job.get("cost") or {}).get("stage_usd", {}).get(st, 0)
                if jobs.launch_limit(budget, spent, jobs.turn_allowance(job)) is None:
                    groups["budget"].append(f"PAUSED stage_budget_exhausted job={key} stage={st} next: raise "
                                            f"flow.factory.worker.stages.{st}.maxBudgetUsd or cancel the job")
        for entry in job.get("orphan_groups") or []:
            if fnext.orphan_alive(entry):
                groups["orphan"].append(f"ORPHAN_GROUP job={key} pgid={entry['pgid']} stage={entry['stage']}")
                orphans.append({"job": key, "pgid": entry["pgid"], "stage": entry["stage"]})
        lines = _job_events(paths, n)
        for line in _after_last_move(lines):
            if line.get("type") == "blocked_unbuilt" and line.get("state") == st:
                text = (f"BLOCKED_UNBUILT job={key} state={st} event={line.get('event')} fact={line.get('fact')} "
                        f"phase={line.get('phase')}")
                if text not in groups["blocked"]:
                    groups["blocked"].append(text)
        if job.get("reason") == "protected" and table.kind(st) == "parked":
            clone = [x for x in lines if x.get("type") == "clone_config_changed"]
            if clone:
                c = clone[-1]
                if c.get("nested_repository"):
                    groups["clone"].append(f"NESTED_REPOSITORY job={key} path={c['nested_repository']}")
                elif c.get("git_failed"):
                    msg = c["git_failed"]
                    if msg.startswith("nested_repository_scan_limit"):
                        groups["clone"].append(f"NESTED_REPOSITORY_SCAN_LIMIT job={key} dir={msg.split(': ', 1)[-1]}")
                    else:
                        groups["clone"].append(f"GIT_FAILED job={key} {msg}")
                elif c.get("file"):
                    f = c["file"]
                    groups["clone"].append(f"CLONE_CONFIG_CHANGED job={key} file={f} key={c.get('key')} next: "
                                           f"restore {job.get('worktree')}/.git/{f} from {jdir}/clone-config/{f}")
        try:
            items = [x for x in os.listdir(os.path.join(jdir, "outbox")) if x.endswith(".json")]
        except OSError:
            items = []
        if items:
            groups["outbox"].append(f"OUTBOX_PENDING job={key} items={len(items)}")
            outbox.append({"job": key, "items": len(items)})
    git = ff.which_real("git")
    if not (ff.gh_default_repo(git) if git else None):
        groups["sync"].append(f"PAUSED sync_repo_unknown next: run gh repo set-default in {paths.main}")
    return groups, orphans, outbox


def _job_line(job):
    return (f"JOB {job['key']} state={job['state']} attempt={job.get('attempt', 0)} "
            f"reason={job.get('reason') or '-'} paused_reason={job.get('paused_reason') or '-'} "
            f"slot={'yes' if job.get('holds_slot') is True else 'no'}")


def cmd_status(argv):
    mode = None
    for a in argv:
        if a in ("--brief", "--json") and mode is None:
            mode = a
        else:
            return _usage("status", f"unexpected argument {a!r} (takes --brief or --json)")
    paths = _status_paths()
    table = ftable.load_table()
    found = jobs.jobs(paths)
    readable = sorted((j for _n, j in found if isinstance(j, dict)), key=lambda j: j["key"])
    unreadable = [(n, j) for n, j in found if isinstance(j, jobs.Unreadable)]
    if mode == "--brief":
        for job in readable:
            print(_job_line(job))
        return 0
    try:
        state = jobs.read_state(paths)
    except Refused:
        state = {}
    lines = [f"UNREADABLE job={j.folder} next: flow-factory.sh rebuild {n}" for n, j in unreadable]
    try:
        lines += staleness.status_lines(paths.fdir, jobs.setting)
    except Refused as r:
        lines.append(f"FACTORY_REFUSED={r}")
    groups, orphans, outbox = _engine_lines(paths, table, found, state)
    for g in ("usage", "budget", "orphan", "blocked", "clone", "outbox", "sync"):
        lines += groups[g]
    if mode == "--json":
        until = state.get("paused_until")
        out = {"jobs": [{"key": j["key"], "issue": j["issue"], "state": j["state"], "attempt": j.get("attempt", 0),
                         "reason": j.get("reason"), "paused_reason": j.get("paused_reason"),
                         "slot": j.get("holds_slot") is True} for j in readable],
               "unreadable": [{"folder": j.folder, "issue": n, "reason": j.reason} for n, j in unreadable],
               "status_lines": lines, "orphan_groups": orphans, "outbox": outbox,
               "paused_until": until if isinstance(until, str) and until > ff.utc_now() else None}
        print(json.dumps(out, sort_keys=True))
        return 0
    for job in readable:
        print(_job_line(job))
    for line in lines:
        print(line)
    return 0


# ---------------------------------------------------------------- context --mode

def _context_check():
    """None when every Detection check of design factory_mode_in_commands
    L5-L10 holds for this process, else the name of the first that fails."""
    env = os.environ
    # jobs.resolve below changes into the main checkout; the toplevel check
    # is about the caller's own folder.
    here = os.getcwd()
    key, did, main = env.get("FLOW_FACTORY_JOB"), env.get("FLOW_FACTORY_DIRECTIVE"), env.get("FLOW_FACTORY_MAIN")
    if not (key and did and main):
        return "variables"
    m = JOB_KEY.match(key)
    if not m:
        return "job_key"
    n = int(m.group(1))
    fdir, _how = fcaller.find_factory_dir()
    if not fdir or not os.path.isdir(main):
        return "factory_dir"
    main_paths = jobs.resolve(cwd=main, create=False)
    if os.path.realpath(main_paths.fdir) != os.path.realpath(fdir):
        return "main"
    paths = jobs.Paths(main_paths.main, fdir, main_paths.plugin)
    job = jobs.read_job(paths, n)
    if not isinstance(job, dict) or job.get("key") != key:
        return "job"
    wt = job.get("worktree")
    git = ff.which_real("git")
    if not isinstance(wt, str) or not git:
        return "worktree"
    top = ff.git_out(git, here, ["rev-parse", "--show-toplevel"])
    if not top or os.path.realpath(top[0]) != os.path.realpath(wt):
        return "toplevel"
    lease = _read_item(os.path.join(jobs.job_dir(paths, n), "directives", did + ".lease.json"))
    if not lease or lease.get("directive") != did or lease.get("revoked_at") is not None:
        return "lease"
    child, child_start = lease.get("child_pid"), lease.get("child_start")
    above = [(p, s) for p, _pp, s, _c in fcaller.ancestry()[1:]]
    if not isinstance(child, int) or not any(p == child and (child_start is None or s == child_start) for p, s in above):
        return "claude_ancestor"
    want = (("FLOW_FACTORY_JOB_KEY", job.get("key")), ("FLOW_FACTORY_ISSUE", str(job.get("issue"))),
            ("FLOW_FACTORY_BRANCH", job.get("branch") or ""), ("FLOW_FACTORY_GOAL_ID", job.get("goal_id") or ""))
    for name, value in want:
        if env.get(name) != value:
            return name
    return None


def cmd_context(argv):
    if list(argv) != ["--mode"]:
        return _usage("context", "takes --mode")
    if not any(os.environ.get(v) for v in WORKER_VARS):
        print("FACTORY_MODE=off")
        return 0
    try:
        failed = _context_check()
    except (Refused, fcaller.AncestryUnreadable, OSError, ValueError) as e:
        failed = f"error {e}"
    if failed:
        sys.stderr.write(f"flow-factory.sh context: check failed: {failed}\n")
    print("FACTORY_MODE=invalid" if failed else "FACTORY_MODE=on")
    return 0
