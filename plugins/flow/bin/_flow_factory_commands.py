"""[flow] The factory's /flow-factory comment commands (plan 1b B5; design
person_channels item 5, L54-L58 and L66; runner L14; L15 for the status
note).

A command is line 1 of an issue comment, read by the text module's
command_of, the one parser the text and issue modules also use. It counts
only when:
  - it is not spec (spec is spec input, read by the text module, never an
    event);
  - it was created strictly after the floor: the later of the job's vouch_at
    and the newest engine marker comment posted by the engine login (L57;
    with no marker the floor is vouch_at, R58). A marker line posted by any
    other login does not move the floor. A marker's time is the time the
    engine decided it, as the needs-info floor is asked_at (plan 3.1, R96):
    the newest comment of the last issue read whose commands were all
    judged before its intent was recorded (a commands_scanned events line),
    less one second, since GitHub gives whole seconds and a comment of that
    same second may have come after the read; never later than the
    marker's own created_at. A command posted between that read and the
    notice was never judged, so the notice does not drop it. A marker
    whose intent the job's events file does not bind to such a line (an
    earlier job's, or one recorded before this rule) counts at its
    created_at;
  - its author passes Permissions.trusted, or, for retry only,
    Permissions.triage (L54, L55); both apply the bot rule.
A counted command whose event does not occur in the job's state, or whose
arguments do not have the form of runner L14 (and Q17 for an answer to a
needs-info question), is refused with one status note instead of an event.
An answer to a needs-info question NI-<k> applies in the person module's
NI_STATES, needs_info and needs_human (rows 8a, 9a, 44v, 44u, 44w, 44x and
44q), the same states as the terminal answer, and only for a question the
job asked.
An untrusted command raises nothing, posts nothing, and is listed by author,
date and length only (L66), once per comment and job: an untrusted_command
events line records the listing. It is not marked seen, because trust is the
permission read of each sync (L54: cached for one sync, a failed read
untrusted), so a later sync that reads the author at the bar raises it.

  scan(snapshot, job, perms, engine_login, table=None, reads=None)
      -> [command]
      snapshot is the issue module's read_issue result, perms its
      Permissions; table defaults to the plugin's transition table; reads
      is marker_reads' answer (None: every marker counts at its
      created_at). Only reads. Each command is {comment_id, name, event,
      args, trusted, triage_only, raise, note, author, author_type,
      created_at, length, permission}: trusted means the command counts (retry from triage
      included, with triage_only true); raise means it becomes a pending
      event; note is the refusal's reason, or None. ValueError when
      engine_login is not a login.
  store(paths, job, command, *, repo, caller=None) -> [status line]
      under the job's lock: a counted command is stored as a pending event
      (unless J/pending already holds one from that comment) or noted, then
      its id joins commands_seen, first in a commands_seen events line with
      the whole list, then in job.json; an untrusted one is not marked seen,
      and gives one UNTRUSTED_COMMAND line the first time only, after its
      {type: untrusted_command, job, comment} events line is written. job is
      changed in place.
  marker_reads(paths, n, key) -> {intent id: time text or None}
      for each intent of job key in J/events.jsonl, the through of the
      last commands_scanned line before its last intent_recorded line
      (None: no comment was read); an intent with no such line is left
      out, and so is every intent when the file cannot be read
  record_scan(paths, job, snapshot, pass_id=None)
      under the job's lock, after every command of the snapshot is stored:
      a {type: commands_scanned, job, through} events line, through the
      newest created_at among the snapshot's comments (None with none);
      not written when the last such line has the same through. The engine
      also writes one with through None when it creates a job, since no
      comment has been read for it
  label_notes(snapshot, job, label) -> [{event_id, actor, label}]
      removals of the queue label after vouch_at by an actor that is not
      trusted (L56: a triage user or a bot), which get a status note
  store_label_note(paths, job, note, *, repo) -> intent id
      under the job's lock

Each status note is an outbox intent through the GitHub write module's
record_job_intent, row note, ref the comment id (or the label event's id),
so one comment or removal gets one note across passes and rebuilds (plan 2.2
dedupe). Its text is built from fixed words, the command name, the job's key
and state, and ids; none of the comment's text is copied into it.
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

import re

import _flow_factory as ff
import _flow_factory_caller as fcaller
import _flow_factory_github as github
import _flow_factory_jobs as jobs
import _flow_factory_person as person
import _flow_factory_table as ftable
import _flow_factory_text as text

# The comment forms of runner L14; feedback, confirm and rebuild have none
# (L57), and spec is never an event.
EVENTS = {"answer": "person_answer", "approve-spec": "person_approve_spec", "rework": "person_rework",
          "retry": "person_retry", "reject": "person_reject", "cancel": "person_cancel"}
HEX = re.compile(r"[0-9a-f]{12,64}")
NI_ID = re.compile(r"NI-[1-9][0-9]{0,8}")
SPEC_ID = re.compile(r"SPEC-[1-9][0-9]{0,8}")
QID = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}")
CHOICE = re.compile(r"[1-9][0-9]{0,8}")
FORMS = {"answer": "`/flow-factory answer NI-<k> <text>` for a needs-info question, or "
                   "`/flow-factory answer <question id> <option number> [<text>]`",
         "approve-spec": "`/flow-factory approve-spec <spec hash> [<head>]`, each at least 12 lower-case hex digits",
         "rework": "`/flow-factory rework <text>`",
         "retry": "`/flow-factory retry`, with nothing after it",
         "reject": "`/flow-factory reject`, with nothing after it",
         "cancel": "`/flow-factory cancel`, with nothing after it"}
NOTE_KEY = ("issueUpdate",)
TEMPLATE = os.path.join(ff.PLUGIN_ROOT, "templates", "factory", "status-note.comment.md")
PLACEHOLDER = re.compile(r"\{(what|reason)\}")


def _line1(body):
    return body.split("\n", 1)[0] if isinstance(body, str) else ""


SCANNED = "commands_scanned"
MARKER_EVENT = re.compile(r" event=([^ ]+) -->$")


def _floor(snapshot, job, engine_login, reads=None):
    """The later of vouch_at and the newest engine marker by the engine
    login, as epoch seconds; None (nothing counts) when vouch_at, or a
    marker's time, cannot be read. A marker whose intent reads binds
    counts at its decision time (the module docstring)."""
    floor = jobs.epoch(job.get("vouch_at"))
    if floor is None:
        return None
    reads = reads if isinstance(reads, dict) else {}
    for c in snapshot.get("comments") or []:
        line = _line1(c.get("body"))
        if c.get("author") != engine_login or not text.is_engine_marker(line):
            continue
        at = jobs.epoch(c.get("created_at"))
        if at is None:
            return None
        m = MARKER_EVENT.search(line)
        iid = m.group(1) if m else None
        if iid in reads:
            through = reads[iid]
            if through is None:
                # Decided before any comment was read: it moves nothing.
                continue
            at = min(at, jobs.epoch(through) - 1)
        floor = max(floor, at)
    return floor


def _through(snapshot):
    """The created_at text of the newest comment of the snapshot whose time
    can be read, or None."""
    best, out = None, None
    for c in snapshot.get("comments") or []:
        at = jobs.epoch(c.get("created_at"))
        if at is not None and (best is None or at > best):
            best, out = at, c.get("created_at")
    return out


def _scan_lines(paths, n, key):
    """(marker_reads' answer, the last commands_scanned line's through or
    False with none) from J/events.jsonl; ({}, False) when it cannot be
    read."""
    try:
        lines = ff.read_jsonl(os.path.join(jobs.job_dir(paths, n), "events.jsonl"))
    except (OSError, UnicodeError, ValueError):
        return {}, False
    reads, last = {}, False
    for d in lines:
        if not isinstance(d, dict) or d.get("job") != key:
            continue
        if d.get("type") == SCANNED:
            t = d.get("through")
            last = t if t is None or jobs.epoch(t) is not None else False
        elif d.get("type") == "intent_recorded" and isinstance(d.get("id"), str):
            if last is False:
                reads.pop(d["id"], None)
            else:
                reads[d["id"]] = last
    return reads, last


def marker_reads(paths, n, key):
    return _scan_lines(paths, n, key)[0]


def record_scan(paths, job, snapshot, pass_id=None):
    through = _through(snapshot)
    if _scan_lines(paths, job["issue"], job["key"])[1] == through:
        return
    jobs.append_event(paths, job["issue"], {"type": SCANNED, "job": job["key"], "through": through,
                                            "pass": pass_id})


def _words(rest):
    """The rest of line 1 without the blanks at its two ends, or None when a
    word is glued to the command name (cancel-now)."""
    if rest and rest[0] not in " \t":
        return None
    return rest.strip(" \t")


def _questions(job):
    """Every needs-info question id the job has asked, in any round."""
    ni = job.get("needs_info") if isinstance(job.get("needs_info"), dict) else {}
    out = set(q for q in ni.get("questions") or [] if isinstance(q, str))
    for rnd in ni.get("earlier") or []:
        if isinstance(rnd, dict):
            out.update(q for q in rnd.get("questions") or [] if isinstance(q, str))
    return out


def _args(name, rest):
    """The event arguments of one command, or None when its form is wrong."""
    words = _words(rest)
    if words is None:
        return None
    if name in ("retry", "reject", "cancel"):
        return {} if words == "" else None
    if name == "rework":
        return {"text": words} if words else None
    if name == "approve-spec":
        parts = words.split()
        if not 1 <= len(parts) <= 2 or not all(HEX.fullmatch(p) for p in parts):
            return None
        args = {"spec_hash": parts[0]}
        if len(parts) == 2:
            args["head"] = parts[1]
        return args
    # answer
    parts = words.split(None, 1)
    if not parts:
        return None
    qid = parts[0]
    if qid.startswith("NI-"):
        answer = parts[1].strip() if len(parts) == 2 else ""
        return {"qid": qid, "text": answer} if NI_ID.fullmatch(qid) and answer else None
    if not QID.fullmatch(qid) or len(parts) < 2:
        return None
    more = parts[1].split(None, 1)
    if not CHOICE.fullmatch(more[0]):
        return None
    args = {"qid": qid, "choice": int(more[0])}
    if len(more) == 2 and more[1].strip():
        args["text"] = more[1].strip()
    return args


def _answer_states(qid):
    """The states an answer to this question id applies in: the person
    module's NI_STATES for NI-<k>, the states the terminal answer takes it
    in (transitions.json rows 8a, 9a, 44v, 44u, 44w, 44x and 44q; plan 2.3
    says needs_info only, and the journal records the conflict);
    needs_spec_approval for SPEC-<k> (design person_channels L11); None for
    a worker question."""
    if NI_ID.fullmatch(qid):
        return person.NI_STATES
    if SPEC_ID.fullmatch(qid):
        return ("needs_spec_approval",)
    return None


def _refusal(name, args, job, table):
    """The reason a counted command is refused, or None."""
    state, key = job.get("state"), job.get("key")
    where = f"Job {key} is in state {state}, where this command does not apply."
    if state not in table.events.get(EVENTS[name], {}).get("occurs_in", []):
        return where
    if args is None:
        return github.EngineText(f"The form is {FORMS[name]}.")
    if name == "answer":
        only = _answer_states(args["qid"])
        if only is not None and state not in only:
            return where
        if only is None and state in ("needs_info", "needs_spec_approval"):
            return where
        if NI_ID.fullmatch(args["qid"]) and args["qid"] not in _questions(job):
            return f"Job {key} has no question {args['qid']}."
    return None


def scan(snapshot, job, perms, engine_login, table=None, reads=None):
    if not isinstance(engine_login, str) or not engine_login:
        raise ValueError("engine login unknown")
    table = table or ftable.load_table()
    seen = set(x for x in job.get("commands_seen") or [] if type(x) is int)
    floor = _floor(snapshot, job, engine_login, reads)
    if floor is None:
        return []
    out = []
    for c in sorted(snapshot.get("comments") or [], key=lambda c: c.get("id") or 0):
        cid, body = c.get("id"), c.get("body")
        if type(cid) is not int or cid < 1 or cid in seen or not isinstance(body, str):
            continue
        parsed = text.command_of(body)
        if parsed is None or parsed[0] == "spec":
            continue
        at = jobs.epoch(c.get("created_at"))
        if at is None or at <= floor:
            continue
        name, rest = parsed
        author, typ = c.get("author"), c.get("author_type")
        full = perms.trusted(author, typ)
        triage_only = name == "retry" and not full and perms.triage(author, typ)
        counts = full or triage_only
        cmd = {"comment_id": cid, "name": name, "event": EVENTS[name], "args": {}, "trusted": counts,
               "triage_only": triage_only, "raise": False, "note": None, "author": author, "author_type": typ,
               "created_at": c.get("created_at"), "length": len(body),
               "permission": perms.of(author) if isinstance(author, str) and author else "none"}
        if counts:
            args = _args(name, rest)
            reason = _refusal(name, args, job, table)
            if reason is None:
                cmd.update(args=args, **{"raise": True})
            else:
                cmd["note"] = reason
        out.append(cmd)
    return out


def _caller():
    pid = os.getpid()
    try:
        pids = [p for p, _ppid, _start, _cmd in fcaller.ancestry()]
    except fcaller.AncestryUnreadable:
        pids = [pid, os.getppid()]
    return {"pid": pid, "start": fcaller.lstart(pid) or "", "ancestry": pids or [pid]}


def _pending_from(paths, n, cid):
    """Whether J/pending already holds an event from comment cid. A file
    that cannot be read may be that event, so it is refused rather than
    guessed."""
    channel = f"comment:{cid}"
    for name, rec in jobs.pending_events(paths, n):
        if not isinstance(rec, dict):
            raise jobs.Refused(f"pending_unreadable job=issue-{n} file={name}")
        if rec.get("channel") == channel:
            return True
    return False


def _listed(paths, n, key, cid):
    """Whether J/events.jsonl already has the untrusted_command line of this
    job and comment. A file that cannot be read counts as not listed, so the
    line is printed again rather than lost."""
    try:
        lines = ff.read_jsonl(os.path.join(jobs.job_dir(paths, n), "events.jsonl"))
    except (OSError, UnicodeError):
        return False
    return any(d.get("type") == "untrusted_command" and d.get("job") == key and d.get("comment") == cid
               for d in lines)


def _render(what, reason):
    """The status note's text. A template that is missing, cannot be read
    or is not UTF-8 is refused (template_unreadable), as the intake module
    refuses its own templates, so the rows' callers, which catch Refused,
    report it. Each caller renders before it records anything. The text is
    a github.EngineText, so clean_post keeps the template's code spans; what
    and reason keep theirs only when they are EngineText themselves (the
    command name and the forms are fixed, a label is in a _code span), and
    any other value has its backticks escaped."""
    try:
        with open(TEMPLATE, encoding="utf-8") as f:
            template = f.read()
    except (OSError, UnicodeDecodeError) as e:
        raise jobs.Refused(f"template_unreadable {TEMPLATE}: {' '.join(str(e).split())}")
    values = {k: v if isinstance(v, github.EngineText) else github.escape_ticks(v)
              for k, v in (("what", what), ("reason", reason))}
    return github.EngineText(PLACEHOLDER.sub(lambda m: values[m.group(1)], template))


def _note(paths, job, ref, what, reason, repo):
    return github.record_job_intent(paths, job, "note", "comment", github.literal_comment(repo, job["issue"]),
                                    _render(what, reason), list(NOTE_KEY), False, ref=ref, repo=repo)


def store(paths, job, command, *, repo, caller=None):
    n, key = job["issue"], job["key"]
    cid = command["comment_id"]
    seen = [x for x in job.get("commands_seen") or [] if type(x) is int]
    if cid in seen:
        return []
    if not command["trusted"]:
        if _listed(paths, n, key, cid):
            return []
        jobs.append_event(paths, n, {"type": "untrusted_command", "job": key, "comment": cid})
        author = command.get("author") or "-"
        at = command.get("created_at") if isinstance(command.get("created_at"), str) else "-"
        return [f"UNTRUSTED_COMMAND job={key} comment={cid} author={author} at={at} length={command['length']}"]
    if command["raise"]:
        if not _pending_from(paths, n, cid):
            facts = {"unvouched_session_action": False, "via_comment": True,
                     "retry_by_triage_only": bool(command["triage_only"])}
            comment = {"id": cid, "author": command["author"], "permission": command["permission"],
                       "created_at": command["created_at"]}
            jobs.store_pending(paths, n, command["event"], command["args"], f"comment:{cid}",
                               caller or _caller(), facts, comment=comment)
    elif command["note"]:
        _note(paths, job, cid, github.EngineText(f"the `/flow-factory {command['name']}` command in comment {cid}"),
              command["note"], repo)
    seen.append(cid)
    jobs.append_event(paths, n, {"type": "commands_seen", "job": key, "commands_seen": list(seen)})
    job["commands_seen"] = seen
    job["updated_at"] = ff.utc_now()
    jobs.write_job(paths, job)
    return []


def label_notes(snapshot, job, label):
    floor = jobs.epoch(job.get("vouch_at"))
    if floor is None:
        return []
    out = []
    for e in snapshot.get("events") or []:
        eid, at = e.get("id"), jobs.epoch(e.get("created_at"))
        if e.get("event") == "unlabeled" and e.get("label") == label and e.get("trusted") is not True \
                and type(eid) is int and eid > 0 and at is not None and at > floor:
            out.append({"event_id": eid, "actor": e.get("actor"), "label": label})
    return out


def store_label_note(paths, job, note, *, repo):
    before = job.get("write_seq")
    actor = note.get("actor") or "an account that no longer exists"
    what = github.EngineText(f"the removal of the label {github._code(note['label'])} by {github.escape_ticks(actor)}")
    iid = _note(paths, job, note["event_id"], what,
                f"Only a person with write access or higher cancels a job by removing that label, "
                f"so job {job['key']} keeps running.", repo)
    if job.get("write_seq") != before:
        job["updated_at"] = ff.utc_now()
        jobs.write_job(paths, job)
    return iid
