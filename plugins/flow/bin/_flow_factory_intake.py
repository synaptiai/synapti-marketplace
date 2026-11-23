"""The factory's intake judge (plan 1b, B11; design stages L37-L44,
trust_and_untrusted_text L28-L30): what the judge is given, how its reply is
read, and the effects of the rows that act on it.

The judge is bin/flow-judge.sh --judge intake, started by the launcher
(bin/_flow_factory_launch.py). It reads issue.md (written by row 66i from the
spec-input set) and an engine fact sheet on stdin, and prints the claude
CLI's --output-format json reply, with its schema object in
.structured_output.

API:
  fact_sheet(job) -> {job, issue, intake_round, open_questions, labels, vouch_at}
  intake_stdin(issue_md: str, sheet: dict) -> bytes
  map_result(stdout: bytes) -> (event, judge or None)
  reply_envelope(stdout: bytes) -> the reply object, or None
  next_question_id(paths) -> "NI-<k>"
  effect_accept(paths, job, result, *, repo) -> {intake_inputs, intake}   (row 6)
  effect_needs_info(paths, job, result, now, *, repo) -> needs_info       (row 4)
  effect_reject(paths, job, result, *, repo) -> intent id                 (row 5)
  effect_revouch_notice(paths, job, comment_id, *, repo) -> intent id     (row 8u)
  effect_answer(paths, job, qid, text) -> None                            (rows 8a, 9a, ...)
  effect_needs_human(paths, job, *, repo, row) -> intent id
  effect_tier_confirm(paths, job, keys, *, repo, row) -> intent id

Every effect needs the job's lock (the caller holds it) and checks it before
it changes anything. A notice is one comment intent recorded through
_flow_factory_github.record_job_intent (kind comment, key [issueUpdate], not
blocking), which adds the engine marker and passes the whole body, judge text
included, through clean_post. The effects change job["write_seq"] (and
effect_accept the intake fields); the caller writes job.json.
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

import json
import re

import _flow_factory as ff
import _flow_factory_github as G
import _flow_factory_jobs as jobs
import _flow_factory_schema as schema
from _flow_factory import Refused
from _journal_atomic import JournalAtomicError, _atomic_write, _read_with_no_follow, acquire_lock

DECISION_EVENTS = {"ACCEPT": "judge_accept", "NEEDS_INFO": "judge_needs_info", "REJECT": "judge_reject"}
FAILED = "stage_failed"
QID = re.compile(r"^NI-[1-9][0-9]*$")
NOTICE_KEY = ["issueUpdate"]
TEMPLATES = os.path.join(ff.PLUGIN_ROOT, "templates", "factory")
QUESTION_LOCK_SECONDS = 30
# The fence lines of issue.md that name what intake read (plan 5.3 issue.md).
_COMMENT_FENCE = re.compile(r"^<<<UNTRUSTED_ISSUE_COMMENT id=([0-9]+)>>>$")
_ANSWER_FENCE = re.compile(r"^<<<UNTRUSTED_ISSUE_ANSWER qid=(NI-[0-9]+)>>>$")
_PLACEHOLDER = re.compile(r"\{([a-z_]+)\}")


# ---------------------------------------------------------------- the judge's input

def fact_sheet(job):
    """The engine fact sheet the judge reads after issue.md (plan 5.3). The
    open questions are the current needs-info round's; labels are the ones
    the engine set on the issue (labels_set), the only labels job.json
    holds."""
    ni = job.get("needs_info") if isinstance(job.get("needs_info"), dict) else {}
    rnd = job.get("intake_round")
    return {"job": job.get("key"), "issue": job.get("issue"),
            "intake_round": rnd if isinstance(rnd, int) and not isinstance(rnd, bool) else 0,
            "open_questions": [q for q in (ni.get("questions") or []) if isinstance(q, str)],
            "labels": [x for x in (job.get("labels_set") or []) if isinstance(x, str)],
            "vouch_at": job.get("vouch_at")}


def intake_stdin(issue_md, sheet):
    """issue.md, then the fact sheet between its fence lines (plan 5.3)."""
    return (issue_md.encode("utf-8") + b"\n<<<ENGINE_FACT_SHEET>>>\n"
            + json.dumps(sheet, sort_keys=True).encode("utf-8") + b"\n<<<END_ENGINE_FACT_SHEET>>>\n")


# ---------------------------------------------------------------- the judge's reply

def reply_envelope(stdout):
    """The CLI reply: stdout parsed as one JSON object, or None."""
    try:
        data = json.loads(stdout.decode("utf-8"))
    except (UnicodeDecodeError, ValueError, AttributeError):
        return None
    return data if isinstance(data, dict) else None


def map_result(stdout):
    """(judge_accept | judge_needs_info | judge_reject, the judge object) for
    a reply whose is_error is not true and whose structured_output passes the
    intake schema ($defs.judge of the directive schema) with proposed_criteria
    non-empty for ACCEPT and questions non-empty for NEEDS_INFO (R20); else
    (stage_failed, None)."""
    env = reply_envelope(stdout)
    if env is None or env.get("is_error") is True:
        return FAILED, None
    judge = env.get("structured_output")
    if not isinstance(judge, dict) or schema.validate(judge, jobs.DIRECTIVE_SCHEMA, "judge"):
        return FAILED, None
    decision = judge["decision"]
    if decision == "ACCEPT" and not judge["proposed_criteria"]:
        return FAILED, None
    if decision == "NEEDS_INFO" and not judge["questions"]:
        return FAILED, None
    return DECISION_EVENTS[decision], judge


# ---------------------------------------------------------------- question ids

def _questions_refused(path, why):
    return Refused(f"questions_unreadable {path}: {' '.join(str(why).split())}")


def next_question_id(paths):
    """The next factory-wide NI-<k> (plan 2.2): F/questions.json {"next": k}
    read, incremented and written while an exclusive lock on
    F/questions.lock is held. No file starts at 1; a file that cannot be
    read, is not JSON, or whose next is not a whole number of at least 1
    refuses (questions_unreadable) and is left as it is."""
    path = os.path.join(paths.fdir, "questions.json")
    try:
        fd = acquire_lock(os.path.join(paths.fdir, "questions.lock"), timeout=QUESTION_LOCK_SECONDS)
    except JournalAtomicError as e:
        raise _questions_refused(path, e.summary)
    try:
        if os.path.lexists(path):
            try:
                data = json.loads(_read_with_no_follow(path))
            except (JournalAtomicError, UnicodeDecodeError, ValueError) as e:
                raise _questions_refused(path, e)
            k = data.get("next") if isinstance(data, dict) else None
            if not isinstance(k, int) or isinstance(k, bool) or k < 1:
                raise _questions_refused(path, f"next is {k!r}")
        else:
            k = 1
        try:
            _atomic_write(path, json.dumps({"next": k + 1}, sort_keys=True) + "\n")
        except JournalAtomicError as e:
            raise _questions_refused(path, e.summary)
        return f"NI-{k}"
    finally:
        os.close(fd)


# ---------------------------------------------------------------- notices

def _load_template(name):
    """The text of templates/factory/<name>.comment.md. A file that is
    missing, cannot be read or is not UTF-8 is refused as the command
    module's _render refuses it (template_unreadable), so the rows' callers,
    which catch Refused, report it. Each effect loads its template before it
    changes anything."""
    path = os.path.join(TEMPLATES, name + ".comment.md")
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except (OSError, UnicodeDecodeError) as e:
        raise Refused(f"template_unreadable {path}: {' '.join(str(e).split())}")


def _fill(text, values):
    """Each {placeholder} of a loaded template filled in one pass, so a
    value that holds a placeholder is not filled again. The judge effects
    escape their values' backticks (G.escape_ticks) before they call it;
    engine values and the template's own backticks are kept."""
    return _PLACEHOLDER.sub(lambda m: values.get(m.group(1), m.group(0)), text)


def _template(name, values):
    """templates/factory/<name>.comment.md loaded and filled."""
    return _fill(_load_template(name), values)


def _notice(paths, job, row, body, state, repo, ref=None):
    return G.record_job_intent(paths, job, row, "comment", G.literal_comment(repo, job["issue"]), body,
                               list(NOTICE_KEY), False, ref=ref, state=state, repo=repo)


def _bullets(values):
    return "\n".join(f"- {v}" for v in values) if values else "- none given"


def _locked(job):
    jobs._need_job_lock(job.get("issue"))


def _write(path, data):
    try:
        _atomic_write(path, json.dumps(data, sort_keys=True, indent=1, ensure_ascii=False) + "\n")
    except JournalAtomicError as e:
        raise Refused(f"job_file_unwritable {path}: {e.summary}")


def _intake_inputs(paths, job):
    """The comment ids and answer ids of J/in-copies/issue.md, the file the
    judge read: its fence lines (quoted text starts '> ', so a fence line
    inside a comment does not count)."""
    path = os.path.join(jobs.job_dir(paths, job["issue"]), "in-copies", "issue.md")
    try:
        text = _read_with_no_follow(path) if os.path.lexists(path) else None
    except (JournalAtomicError, UnicodeDecodeError) as e:
        raise Refused(f"issue_md_unreadable {path}: {' '.join(str(e).split())}")
    if text is None:
        raise Refused(f"issue_md_missing {path}")
    comments, answers = [], []
    for line in text.splitlines():
        m = _COMMENT_FENCE.match(line)
        if m and int(m.group(1)) >= 1 and int(m.group(1)) not in comments:
            comments.append(int(m.group(1)))
        m = _ANSWER_FENCE.match(line)
        if m and m.group(1) not in answers:
            answers.append(m.group(1))
    return {"comments": comments, "answers": answers}


def effect_accept(paths, job, result, *, repo):
    """Row 6: intake_inputs (from what the judge read), intake {risk,
    surfaces, scope}, J/in-copies/intake.json (the judge reply, which the
    spec stage reads) and the accept notice, recorded for prepare, the
    state the row moves to (plan 2.2). Returns the two job fields for the
    transition line's fields."""
    _locked(job)
    template = _load_template("intake-accept")
    inputs = _intake_inputs(paths, job)
    intake = {"risk": result["risk"], "surfaces": list(result["surfaces"]), "scope": result["scope"]}
    copies = os.path.join(jobs.job_dir(paths, job["issue"]), "in-copies")
    jobs._ensure(paths, copies)
    _write(os.path.join(copies, "intake.json"), result)
    E = G.escape_ticks
    body = _fill(template, {"scope": E(result["scope"]), "risk": E(result["risk"]),
                            "surfaces": E(", ".join(result["surfaces"])) or "none named",
                            "criteria": _bullets([E(c) for c in result["proposed_criteria"]])})
    _notice(paths, job, "6", body, "prepare", repo)
    job["intake_inputs"] = inputs
    job["intake"] = intake
    return {"intake_inputs": inputs, "intake": intake}


def effect_needs_info(paths, job, result, now, *, repo):
    """Row 4: one NI id and question file per judge question, then the
    needs-info notice, recorded for needs_info. Returns the new needs_info
    {asked_at: now, questions, round, earlier}: the job's previous round is
    appended to earlier. job["needs_info"] is left to the caller."""
    _locked(job)
    questions = [q for q in result["questions"] if isinstance(q, str)]
    if not questions:
        raise ValueError("a needs-info result has no questions")
    old = job.get("needs_info") if isinstance(job.get("needs_info"), dict) else None
    earlier = list(old.get("earlier") or []) if old else []
    if old:
        earlier.append({"asked_at": old.get("asked_at"), "questions": list(old.get("questions") or []),
                        "round": old.get("round")})
    prev = old.get("round") if old else 0
    rnd = (prev if isinstance(prev, int) and not isinstance(prev, bool) and prev > 0 else 0) + 1
    template = _load_template("intake-needs-info")
    qdir = os.path.join(jobs.job_dir(paths, job["issue"]), "questions")
    ids = []
    for text in questions:
        qid = next_question_id(paths)
        jobs._ensure(paths, qdir)
        _write(os.path.join(qdir, qid + ".json"), {"job": job["key"], "id": qid, "text": text, "round": rnd})
        ids.append((qid, text))
    body = _fill(template, {"questions": "\n".join(f"- {q}: {G.escape_ticks(t)}" for q, t in ids)})
    _notice(paths, job, "4", body, "needs_info", repo)
    return {"asked_at": now, "questions": [q for q, _ in ids], "round": rnd, "earlier": earlier}


def effect_reject(paths, job, result, *, repo):
    """Row 5: the reject notice, recorded for rejected (the row's target)."""
    _locked(job)
    return _notice(paths, job, "5", _template("intake-reject", {"reason": G.escape_ticks(result["reason"])}), "rejected", repo)


def effect_revouch_notice(paths, job, comment_id, *, repo):
    """Row 8u (a stay row): the notice that an untrusted reply needs a
    retry, keyed by the reply id, so a second call records nothing."""
    _locked(job)
    if not isinstance(comment_id, int) or isinstance(comment_id, bool) or comment_id < 1:
        raise ValueError(f"comment id {comment_id!r}")
    body = _template("revouch-needed", {"comment": str(comment_id)})
    return _notice(paths, job, "8u", body, job.get("state"), repo, ref=comment_id)


def effect_answer(paths, job, qid, text):
    """Rows 8a, 9a, 44v, 44u, 44w, 44x, 44q: append {qid, text, at} to
    J/answers.json. The question must be this job's: J/questions/<qid>.json
    naming the job; else ValueError."""
    _locked(job)
    if not isinstance(qid, str) or not QID.match(qid) or not isinstance(text, str):
        raise ValueError(f"answer {qid!r}")
    jdir = jobs.job_dir(paths, job["issue"])
    qpath = os.path.join(jdir, "questions", qid + ".json")
    try:
        q = json.loads(_read_with_no_follow(qpath)) if os.path.lexists(qpath) else None
    except (JournalAtomicError, UnicodeDecodeError, ValueError):
        q = None
    if not isinstance(q, dict) or q.get("job") != job.get("key") or q.get("id") != qid:
        raise ValueError(f"{qid} is not a question of {job.get('key')}")
    path = os.path.join(jdir, "answers.json")
    try:
        answers = json.loads(_read_with_no_follow(path)) if os.path.lexists(path) else []
    except (JournalAtomicError, UnicodeDecodeError, ValueError) as e:
        raise Refused(f"answers_unreadable {path}: {' '.join(str(e).split())}")
    if not isinstance(answers, list):
        raise Refused(f"answers_unreadable {path}: not a list")
    answers.append({"qid": qid, "text": text, "at": ff.utc_now()})
    _write(path, answers)


def effect_needs_human(paths, job, *, repo, row):
    """The needs-human notice on entry to needs_human, recorded for the row
    that made the entry (plan B14 step 8)."""
    _locked(job)
    reason = job.get("reason") if isinstance(job.get("reason"), str) and job.get("reason") else "not recorded"
    return _notice(paths, job, row, _template("needs-human", {"reason": reason}), "needs_human", repo)


def effect_tier_confirm(paths, job, keys, *, repo, row):
    """The tier-confirm notice on entry to waiting_operator with reason
    tier_confirm, naming each key, recorded for the row that parked."""
    _locked(job)
    if not isinstance(keys, list) or not keys or any(k not in G.TIER_KEYS for k in keys):
        raise ValueError(f"keys {keys!r}")
    body = _template("tier-confirm", {"keys": ", ".join(f"tiers.{k}" for k in keys)})
    return _notice(paths, job, row, body, "waiting_operator", repo)
