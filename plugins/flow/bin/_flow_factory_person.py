"""[flow] The factory's person subcommands, rebuild, status and context --mode
(plan 1a T12, 1b B12; design person_channels, factory_mode_in_commands).

  cmd_person(sub, argv)   answer, approve-spec, confirm, feedback, rework,
                          retry, reject, cancel: look the job up, check that
                          the event occurs in the job's state (exit 3), get
                          the person's confirmation (exit 4), then store the
                          event in J/pending for the next pass to apply
  cmd_rebuild(argv)       rebuild <job>: row 68, applied here; job.json is
                          rebuilt from events.jsonl and the directive files,
                          the old bytes kept in job.json.bak
  cmd_status(argv)        status [--brief|--json], status --intent <id>
  cmd_context(argv)       context --mode: FACTORY_MODE=off|on|invalid

An outbox intent (plan 1b 2.2) is shown and checked through the write
module's check: its argv and body are hashed and compared with the
intent_recorded line in the events file beside it, never with the item's own
sha256 field, and its status is read from the events lines. status --intent
prints the INTENT line and the literal and body in <<<UNTRUSTED_INTENT>>>
fences, every shown line starting "> ", every control character but tab
shown as \\xNN and every format character (Cf), U+2028 and U+2029 as
\\u{xxxx} (_show; status's text status lines are shown the same way).
confirm <intent> shows the same on the terminal with its prompt (on stdout
for the probe intent, which is refused without one), then acts by the job's
state (plan 2.3): it releases a waiting_operator park on its pending intent
(INTENT_NOT_PENDING for any other item of the job), or, for a notice waiting
for a confirm outside waiting_operator, appends the intent_confirmed line and
only then saves the item confirmed (Q16). A probe-p9-<n> id is looked up only
in the P9 probe folder the interactive state names, and confirm refuses it
with INTENT_PROBE before the session check.

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
import stat
import tempfile
import time
import unicodedata
from decimal import Decimal

_BIN_DIR = os.path.dirname(os.path.realpath(__file__))
if _BIN_DIR not in sys.path:
    sys.path.append(_BIN_DIR)

import _flow_factory as ff
from _flow_factory import Refused
import _flow_factory_jobs as jobs
import _flow_factory_caller as fcaller
import _flow_factory_github as fgh
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
PROBE_ID = re.compile(r"^probe-p9-([0-9]+)$")
NI_ID = re.compile(r"^NI-[0-9]+$")
# The states whose person_answer rows take a needs-info answer (qid NI-<k>
# and its text): 8a and 9a in needs_info, 44v, 44u, 44w, 44x and 44q in
# needs_human (plan 5.3 Context answer; Inferred over plan 2.3's "needs_info
# only", which would leave rows 44v-44q no terminal answer).
NI_STATES = ("needs_info", "needs_human")
SHA = re.compile(r"^[0-9a-f]{40}$")
FENCE, END_FENCE = "<<<UNTRUSTED_INTENT>>>", "<<<END_UNTRUSTED_INTENT>>>"
# The outbox statuses status counts as not yet sent (plan 2.3).
UNSENT = ("recorded", "pending_confirm", "confirmed")


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


def _real_folder(path):
    """True when path is a folder and not a symbolic link to one. This
    module reads J/outbox, J/questions and J/directives only through this
    check and treats a linked folder as absent, as plan 2.2's lookup rule
    treats a linked J/outbox (journal wave 3)."""
    try:
        return stat.S_ISDIR(os.lstat(path).st_mode)
    except OSError:
        return False


def _lookup_items(paths, folder, item):
    """[(n, job)] of every job whose J/<folder>/<item>.json names it in its
    job field, by issue number. A J/<folder> that is a symbolic link is not
    read, as the drain does not read a linked J/outbox (journal wave 2,
    OUTBOX_UNREADABLE reason=symlink): its items are not found. A job folder
    that is a symbolic link is refused by read_job (job_unreadable)."""
    if not ITEM_ID.match(item):
        return []
    pattern = os.path.join(glob.escape(paths.fdir), "jobs", "issue-*", folder, glob.escape(item) + ".json")
    out = []
    for path in glob.glob(pattern):
        if not _real_folder(os.path.dirname(path)):
            continue
        data = _read_item(path)
        key = data.get("job") if data else None
        m = JOB_KEY.match(key) if isinstance(key, str) else None
        if not m or os.path.basename(os.path.dirname(os.path.dirname(path))) != f"issue-{m.group(1)}":
            continue
        try:
            out.append(_lookup_job(paths, key))
        except Refused as r:
            if str(r).startswith("job_unknown"):
                continue
            raise
    return sorted(out, key=lambda x: x[0])


def _lookup_item(paths, folder, item, refusal):
    """The job that J/<folder>/<item>.json names in its job field: answer's
    question (J/questions) and confirm's intent (J/outbox). A question id
    that two jobs hold is refused with QUESTION_AMBIGUOUS (plan 2.3; the
    factory-wide NI-<k> counter prevents it unless a file was made by
    hand)."""
    found = _lookup_items(paths, folder, item)
    if not found:
        raise Refused(refusal)
    if folder == "questions" and len(found) > 1:
        raise _Ambiguous(f"QUESTION_AMBIGUOUS={item} jobs={','.join(job['key'] for _n, job in found)}")
    return found[0]


class _Ambiguous(Exception):
    pass


class _Intent(object):
    """Where an outbox intent lives: its item file, the events file that
    records it, and its job (n and the job dict), or n None for the probe
    intent."""

    def __init__(self, iid, path, events, n=None, job=None):
        self.iid, self.path, self.events, self.n, self.job = iid, path, events, n, job

    @property
    def label(self):
        return "probe" if self.n is None else self.job["key"]


def _probe_folder(fdir, number):
    """The P9 probe folder F/<INTERACTIVE_STATE>'s plugin path names, when
    its name is P9-<number> and it is a folder, not a symbolic link; else
    None (plan 2.2 lookup rule)."""
    state = ff.interactive_state(fdir, required=False)
    plugin = state.get("plugin")
    if not isinstance(plugin, str) or not os.path.isabs(plugin):
        return None
    folder = os.path.dirname(os.path.normpath(plugin))
    if os.path.basename(folder) != f"P9-{number}":
        return None
    for path in (folder, os.path.join(folder, "outbox")):
        try:
            if not stat.S_ISDIR(os.lstat(path).st_mode):
                return None
        except OSError:
            return None
    return folder


def _find_intent(paths, iid):
    """The _Intent for an id, by the lookup rule of plan 2.2: a
    probe-p9-<n> id only in the P9 probe folder, never in a job's outbox;
    every other id in J/outbox of every job. Raises Refused(intent_unknown
    intent=<id>)."""
    unknown = Refused(f"intent_unknown intent={iid}")
    m = PROBE_ID.match(iid)
    if m:
        folder = _probe_folder(paths.fdir, m.group(1))
        path = os.path.join(folder, "outbox", iid + ".json") if folder else None
        if path is None or not os.path.lexists(path):
            raise unknown
        return _Intent(iid, path, os.path.join(folder, "events.jsonl"))
    n, job = _lookup_item(paths, "outbox", iid, str(unknown))
    jdir = jobs.job_dir(paths, n)
    return _Intent(iid, os.path.join(jdir, "outbox", iid + ".json"), os.path.join(jdir, "events.jsonl"), n, job)


def _check_intent(where):
    """(IntentChanged or None, item, recorded sha256, body bytes, history)
    for an intent, through the write module's check (its hash and fields
    against the intent_recorded line, its status against the events lines).
    An item that does not read, or whose own id is not the one asked for,
    is changed (field=id for the latter)."""
    iid = where.iid
    item = fgh._read_json(where.path)
    if item is None or item.get("id") != iid:
        h = fgh._history(where.events, iid)
        rec = h["rec"].get("sha256") if h["rec"] and isinstance(h["rec"].get("sha256"), str) else None
        return fgh.IntentChanged(iid, rec, None, field=None if item is None else "id"), item, rec, None, h
    changed, body, h = fgh._checked(where.events, item)
    return changed, item, (h["rec"] or {}).get("sha256"), body, h


def _show(text):
    """text with every control character but tab shown as \\xNN, and every
    format character (Unicode category Cf: the bidi controls, zero-width
    characters, the byte order mark) and the line and paragraph separators
    U+2028 and U+2029 shown as \\u{xxxx}, so a carriage return, an escape
    sequence, a reordering or an unseen character cannot hide or redraw
    what a person is asked to approve."""
    out = []
    for c in text:
        o = ord(c)
        if (o < 32 and c != "\t") or 127 <= o < 160:
            out.append("\\x%02x" % o)
        elif unicodedata.category(c) == "Cf" or c in "\u2028\u2029":
            out.append("\\u{%04x}" % o)
        else:
            out.append(c)
    return "".join(out)


def intent_block(where, item, recorded, body):
    """The INTENT line, then the literal (one argv element per line) and the
    body, each inside <<<UNTRUSTED_INTENT>>> fences, every shown line
    starting "> " so none can close a fence (plan 2.3)."""
    out = [f"INTENT id={where.iid} job={where.label} key={','.join(item['key'])} sha256={recorded}", FENCE]
    out += ["> " + _show(a) for a in item["argv"]] + [END_FENCE, FENCE]
    if body:
        out += ["> " + _show(x) for x in body.decode("utf-8", "backslashreplace").split("\n")]
    return out + [END_FENCE]


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


def confirm(sub, argv, job, session_ok=False, shown=()):
    """The channel the person confirmed on ("terminal", or "session:<id>" for
    answer --choice from a session), or None after printing
    PERSON_CONFIRM_REQUIRED. The shown lines (confirm's literal, body and
    hashes) are written to the terminal just before the prompt, where the
    person reads it, so stdout keeps one outcome line. Holds no lock."""
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
        command = " ".join(shlex.quote(x) for x in ["flow-factory.sh", sub] + list(argv))
        text = "".join(line + "\n" for line in shown)
        os.write(fd, (f"{text}job {job['key']} state={job['state']}\ncommand: {command}\n{PROMPT}").encode("utf-8"))
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
        # A needs-info question (NI-<k>) is answered by its text; --choice is
        # not required (plan 2.3, 7.2 item 8), and --text is (Inferred: rows
        # 8a, 9a and 44v-44q take the qid and the text, plan 5.3 Context).
        (qid,), o = _parse(argv, ["qid"], {"choice": "int", "text": "text"})
        need = "text" if NI_ID.match(qid) else "choice"
        if need not in o:
            raise _Usage(f"--{need} is required")
        args = {"qid": qid}
        for name in ("choice", "text"):
            if name in o:
                args[name] = o[name]
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
    if sub == "confirm":
        return _cmd_confirm(argv, args["intent"], paths, table)
    ni = sub == "answer" and bool(NI_ID.match(args["qid"]))
    if item is not None:
        folder, ident = item
        what = "question_unknown qid" if folder == "questions" else "intent_unknown intent"
        try:
            n, job = _lookup_item(paths, folder, ident, f"{what}={ident}")
        except _Ambiguous as a:
            print(str(a))
            return 3
    else:
        n, job = _lookup_job(paths, job_arg)
    if not _occurs(table, event, job["state"]) or (ni and job["state"] not in NI_STATES):
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
        if not _occurs(table, event, again["state"]) or (ni and again["state"] not in NI_STATES):
            print(f"EVENT_REFUSED={event} state={again['state']}")
            return 3
        jobs.store_pending(paths, n, event, args, channel, caller, {"unvouched_session_action": False})
    print(f"RAISED {event} job={job['key']}")
    return 0


def _confirm_case(table, job, iid, item, h):
    """What confirm <iid> does in the job's state (plan 2.3, in this order):
    "release" (person_confirm: the job waits on this pending intent, or is
    parked tier_confirm with none), "not_pending" (it waits on another
    intent, R68), "notice" (a notice the drain made wait for a confirm, read
    from the events lines, in a state that is not terminal, Q16), else
    None."""
    state = job.get("state")
    pending = job.get("pending_intent")
    if state == "waiting_operator" and isinstance(pending, dict) and pending.get("id"):
        return "release" if pending["id"] == iid else "not_pending"
    if state == "waiting_operator" and job.get("reason") == "tier_confirm" and not pending:
        return "release"
    if table.kind(state) != "terminal" and item.get("blocking") is False and h["parked"] \
            and not (h["confirmed"] or h["sent"] or h["dropped"]):
        return "notice"
    return None


def _confirm_refusal(case, iid, job):
    if case == "not_pending":
        return f"INTENT_NOT_PENDING={iid} pending={job['pending_intent']['id']}"
    return f"EVENT_REFUSED=person_confirm state={job.get('state')}"


def _cmd_confirm(argv, iid, paths, table):
    """confirm <intent> (plan 2.3): look the intent up (a probe id only in
    the P9 probe folder), refuse INTENT_CHANGED before anything is shown or
    asked, print the literal, the body and both hashes and refuse a probe
    intent with INTENT_PROBE before the session check, refuse by the job's
    state (_confirm_case) before the prompt, then show the literal, the body
    and both hashes on the terminal with the prompt and act once the job key
    is typed back. Every check runs again under the job lock before anything
    is written."""
    where = _find_intent(paths, iid)
    changed, item, recorded, body, h = _check_intent(where)
    if changed is not None:
        print(changed.line)
        return 3
    shown = intent_block(where, item, recorded, body)
    shown.append(f"SHA256 recorded={recorded} current={fgh.intent_digest(item['argv'], body)}")
    if where.n is None:
        # No prompt follows: the probe intent is shown on stdout and refused.
        for line in shown:
            print(line)
        print(f"INTENT_PROBE={iid}")
        return 3
    n, job = where.n, where.job
    case = _confirm_case(table, job, iid, item, h)
    if case not in ("release", "notice"):
        print(_confirm_refusal(case, iid, job))
        return 3
    channel = confirm("confirm", argv, job, shown=shown)
    if channel is None:
        return 4
    caller = _caller()
    with jobs.job_lock(paths, n):
        again = jobs.read_job(paths, n)
        if isinstance(again, jobs.Unreadable):
            raise Refused(f"job_unreadable job={again.folder}")
        if not isinstance(again, dict) or again.get("key") != job["key"]:
            raise Refused(f"job_unknown job={job['key']}")
        # J/outbox may have been swapped for a link while the prompt waited;
        # the save below would follow it out of the job folder.
        if not _real_folder(os.path.dirname(where.path)):
            raise Refused(f"intent_unknown intent={iid}")
        changed, item, _rec, _body, h = _check_intent(_Intent(iid, where.path, where.events, n, again))
        if changed is not None:
            print(changed.line)
            return 3
        now = _confirm_case(table, again, iid, item, h)
        if now != case:
            print(_confirm_refusal(now, iid, again))
            return 3
        if case == "notice":
            # The events line is the record (journal wave 2): it is appended
            # before the item is saved, so a process that dies between the
            # two leaves a line the drain acts on, never a confirmed item with
            # no line, which check_item refuses.
            jobs.append_event(paths, n, {"type": "intent_confirmed", "job": again["key"], "time": ff.utc_now(),
                                         "id": iid})
            fgh._save(where.path, dict(item, status="confirmed"))
        else:
            jobs.store_pending(paths, n, "person_confirm", {"intent": iid}, channel, caller,
                               {"unvouched_session_action": False})
    print(f"CONFIRMED intent={iid} job={job['key']}" if case == "notice" else f"RAISED person_confirm job={job['key']}")
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
    """[(stage, k, created_in_pass number or -1)] of J/directives/<key>-<stage>-<k>.json.
    A J/directives that is a symbolic link is read as empty: next's launch
    refuses that folder, so nothing behind it is the job's."""
    pat = re.compile(r"^" + re.escape(key) + r"-([a-z_]+)-([1-9][0-9]*)\.json$")
    out = []
    if not _real_folder(os.path.join(jdir, "directives")):
        return out
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


# The events.jsonl line types whose list replaces a job.json field in rebuild
# (written by the next pass: _flow_factory_next module docstring).
LOGGED_LISTS = {"orphan_group": "orphan_groups", "snapshot": "snapshots", "pending_changes": "pending_changes",
                "commands_seen": "commands_seen", "labels_set": "labels_set"}
# The job.json fields a transition or replayed line's fields object may set
# in rebuild (plan 2.2 "How rebuild restores the 1b fields"): the 1b fields a
# handler sets from the sync or the clock. A line naming any other field
# (state, key, cost) changes nothing (Inferred: only the writers of these
# fields put them in a line).
REPLAYED_FIELDS = ("vouch_at", "vouch_event_id", "base", "revouched_replies", "baseline_digest", "baseline_pending",
                   "intake_inputs", "intake", "needs_info", "pending_keys", "pending_intent", "held_result",
                   "confirmed_intent")


def _apply_fields(job, line):
    fields = line.get("fields")
    if isinstance(fields, dict):
        for name, value in fields.items():
            if name in REPLAYED_FIELDS:
                job[name] = copy.deepcopy(value)


def _write_seq(jdir, key, lines):
    """The largest k of the job's intent ids issue-N-j<seq>-<row>-<k>, from
    its intent_recorded lines and its J/outbox item names, or None (plan
    2.2 write_seq). The items of a J/outbox that is a symbolic link do not
    count: the drain does not read that folder (OUTBOX_UNREADABLE)."""
    name = re.compile("^" + re.escape(key) + r"-[0-9a-z]+-([0-9]+)$")
    ks = []
    for line in lines:
        m = name.match(line.get("id") or "") if line.get("type") == "intent_recorded" else None
        if m and isinstance(line.get("id"), str):
            ks.append(int(m.group(1)))
    files = []
    if _real_folder(os.path.join(jdir, "outbox")):
        try:
            files = os.listdir(os.path.join(jdir, "outbox"))
        except OSError:
            pass
    for f in files:
        m = name.match(f[:-len(".json")]) if f.endswith(".json") else None
        if m:
            ks.append(int(m.group(1)))
    return max(ks) if ks else None


def rebuild_job(paths, table, n, lines, now):
    """job.json rebuilt from the event log (plan T12 rebuild table). Raises
    ftable.TransitionRefused at the first recorded move no row makes.

    - The created line's record is the starting job (a new job without one).
    - Each transition line is checked with check_move, then its state, its
      records, the job-field effects it applied (reason, paused_reason, the
      counters, round_limit, build_started, attempt, relaunch) and its attempt
      are replayed in order, and pending_changes loses the facts its row read
      as true, as apply() does.
    - orphan_groups, snapshots and pending_changes are the whole list the
      last orphan_group, snapshot or pending_changes line before that point
      carries (LOGGED_LISTS), so a later line replaces an earlier one and a
      later transition still clears pending changes.
    - The slot is the last slot line (taken or freed).
    - cost, last_session_total and sessions come from the charge lines.
    - stage_launches is the largest k per stage of the directive files, and
      directive the newest of them (the live engine never clears it).
    - relaunch is kept only when no directive was made at or after the pass
      that set it; lease_grace is null.
    - Each transition line's fields object is applied after that line's
      handlers, and each replayed line's (REPLAYED_FIELDS only), so the 1b
      values a handler took from the sync or the clock come back as written
      and a replayed line clears held_result and confirmed_intent;
      commands_seen and labels_set are LOGGED_LISTS too.
    - write_seq is the largest k of the job's intent ids (_write_seq).
    - head_sha is the last pushed line's sha or pr_recorded line's head
      (with its pr), else null; never the clone's HEAD (carry item 1)."""
    job, first = _start(n, lines)
    key = job["key"]
    setting_ctx = ftable.Context(setting=jobs.setting)
    relaunch_pass = None
    job["relaunch"] = None
    runs, total, by_stage, dearest = [], Decimal(0), {}, Decimal(0)
    totals = dict(job.get("last_session_total") or {})
    sessions = dict(job.get("sessions") or {})
    head = None
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
            _apply_fields(job, line)
            if isinstance(line.get("attempt"), int) and not isinstance(line.get("attempt"), bool):
                job["attempt"] = line["attempt"]
            pending = job.get("pending_changes")
            if isinstance(pending, list) and row is not None:
                cleared = set(f for f, v in row.get("guard", {}).items() if v is True)
                job["pending_changes"] = [f for f in pending if f not in cleared]
        elif kind == "replayed":
            _apply_fields(job, line)
        elif kind == "pushed" and isinstance(line.get("sha"), str) and SHA.match(line["sha"]):
            head = line["sha"]
        elif kind == "pr_recorded" and isinstance(line.get("head"), str) and SHA.match(line["head"]):
            head = line["head"]
            if isinstance(line.get("pr"), int) and not isinstance(line["pr"], bool) and line["pr"] > 0:
                job["pr"] = line["pr"]
        elif kind in LOGGED_LISTS:
            field = LOGGED_LISTS[kind]
            if isinstance(line.get(field), list):
                job[field] = copy.deepcopy(line[field])
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
    # Carry item 1 (amendments.md:79): the head the engine itself pushed or
    # recorded with the PR, never the clone's HEAD, which may hold a commit
    # nobody pushed.
    job["head_sha"] = head
    seq = _write_seq(jdir, key, lines)
    if seq is not None:
        job["write_seq"] = seq
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
    # As read_job, before the log is read or the person asked: F/jobs reached
    # through a symbolic link is refused (factory_dir_refused), and a job
    # folder that is one is unreadable, the line the other person
    # subcommands give and the one status's UNREADABLE line leads to.
    jobs._check_dir(paths, os.path.dirname(jdir))
    if os.path.islink(jdir):
        raise Refused(f"job_unreadable job=issue-{n}")
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
        # A directive behind a J/directives that is a symbolic link is not
        # running: next's launch refuses that folder.
        if table.states.get(st, {}).get("run_by") == "worker" and not (
                _real_folder(os.path.join(jdir, "directives"))
                and fnext.directive_open(paths, n, job.get("directive"))):
            line = jobs.worker_budget_paused(key, st, jobs.setting(f"flow.factory.worker.stages.{st}.maxBudgetUsd"),
                                             job)
            if line:
                groups["budget"].append(line)
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
                    groups["clone"].append(jobs.clone_changed_line(key, job.get("worktree"), jdir, f, c.get("key")))
        pending = job.get("pending_intent")
        if st == "waiting_operator" and isinstance(pending, dict) and isinstance(pending.get("id"), str):
            keys = ",".join(k for k in pending.get("key") or [] if isinstance(k, str))
            groups["outbox"].append(f"PENDING_INTENT job={key} intent={pending['id']} kind={pending.get('kind')} "
                                    f"keys={keys}")
        unsent = 0
        for iid, kind, status in _outbox_items(jdir):
            if status == "pending_confirm":
                groups["outbox"].append(f"PENDING_CONFIRM job={key} intent={iid} kind={kind}")
            unsent += status in UNSENT
        if unsent:
            groups["outbox"].append(f"OUTBOX_PENDING job={key} items={unsent}")
            outbox.append({"job": key, "items": unsent})
    git = ff.which_real("git")
    if not (ff.gh_default_repo(git) if git else None):
        groups["sync"].append(f"PAUSED sync_repo_unknown next: run gh repo set-default in {paths.main}")
    return groups, orphans, outbox


def _outbox_items(jdir):
    """[(id, kind, status)] of the job's outbox items, by id, where the
    status is what the events file says (journal wave 2: the line, not the
    item, is the record): sent with a write_recorded line, dropped with an
    intent_dropped line, confirmed or pending_confirm with that line after
    the last intent_recorded line, else recorded. An item that does not
    read, is not named by its own id, or has no intent_recorded line is
    left out: nothing can run it. So is every item of a J/outbox that is a
    symbolic link, which the drain refuses (OUTBOX_UNREADABLE)."""
    outbox = os.path.join(jdir, "outbox")
    events = os.path.join(jdir, "events.jsonl")
    if not _real_folder(outbox):
        return []
    try:
        names = sorted(x for x in os.listdir(outbox) if x.endswith(".json"))
    except OSError:
        return []
    out = []
    for name in names:
        item = fgh._read_json(os.path.join(outbox, name))
        iid = name[:-len(".json")]
        if item is None or item.get("id") != iid:
            continue
        h = fgh._history(events, iid)
        if h["rec"] is None:
            continue
        status = ("sent" if h["sent"] else "dropped" if h["dropped"] else "confirmed" if h["confirmed"]
                  else "pending_confirm" if h["parked"] else "recorded")
        out.append((iid, h["rec"].get("kind"), status))
    return out


def _job_line(job):
    return (f"JOB {job['key']} state={job['state']} attempt={job.get('attempt', 0)} "
            f"reason={job.get('reason') or '-'} paused_reason={job.get('paused_reason') or '-'} "
            f"slot={'yes' if job.get('holds_slot') is True else 'no'}")


def cmd_status_intent(argv):
    """status --intent <id> (plan 2.3): read only. 0 with the INTENT line,
    the literal and the body; 3 INTENT_UNKNOWN=<id>; 3 INTENT_CHANGED=<id>
    recorded=<hex> current=<hex>[ field=<name>]."""
    if len(argv) != 1 or argv[0].startswith("--"):
        return _usage("status", "--intent takes one intent id")
    iid = argv[0]
    paths = _status_paths()
    try:
        where = _find_intent(paths, iid)
    except Refused as r:
        if not str(r).startswith("intent_unknown"):
            raise
        print(f"INTENT_UNKNOWN={iid}")
        return 3
    changed, item, recorded, body, _h = _check_intent(where)
    if changed is not None:
        print(changed.line)
        return 3
    for line in intent_block(where, item, recorded, body):
        print(line)
    return 0


def cmd_status(argv):
    if argv[:1] == ["--intent"]:
        return cmd_status_intent(argv[1:])
    if argv[:1] and argv[0].startswith("--intent="):
        return cmd_status_intent([argv[0][len("--intent="):]] + list(argv[1:]))
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
    # The status lines carry text the engine read from a worker's clone (a
    # nested repository's path); they are shown by the rule status --intent
    # uses.
    for job in readable:
        print(_job_line(job))
    for line in lines:
        print(_show(line))
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
    ddir = os.path.join(jobs.job_dir(paths, n), "directives")
    lease = _read_item(os.path.join(ddir, did + ".lease.json")) if _real_folder(ddir) else None
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
