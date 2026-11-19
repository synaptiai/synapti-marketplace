"""The factory engine's GitHub writes (plan 1b, B6; design stages L7-L17,
person_channels L42, interactive_executor L8).

Every write the engine makes follows four steps: look first (for the
engine's marker, or for the effect itself), record the intent, resolve its
tier keys, and run it with the real gh. An intent is an outbox item,
J/outbox/<id>.json (schemas/v1/factory-outbox.schema.json), plus an
intent_recorded line in J/events.jsonl written before the item and before
anything runs. The line holds the sha256 and the item's job, row,
state_at_write, ref, kind, blocking and key; every later check compares the
item with the line, never with the item's own sha256 field, so an edit to
the item or its body file after it was recorded is refused with
INTENT_CHANGED (with field=<name> when a field differs). The body that is
hashed is the file gh posts, the one the argv's -F body=@ names; since the
argv is hashed too, only the J/outbox/<id>.body.md the record wrote can
match, and body_file must name that file. A confirmed item runs only when it
is a notice and an intent_confirmed line names its id.

The literals are fixed forms (see the literal_* builders): gh api calls for
comments, labels and the PR close, and gh issue edit for the assignment and
the in-progress label together (assign_label). A comment's body is stored in
J/outbox/<id>.body.md, cleaned with clean_post and with the engine marker
<!-- FLOW_FACTORY job=<job key> event=<id> --> as its first line, and the
literal ends with -F body=@<that file's absolute path> (design stages L13).
record_job_intent adds the marker and that argument itself, since both need
the id it makes.

API:
  intent_digest(argv, body: bytes) -> hex
  marker(job_key, intent_id) -> the marker line
  clean_post(text) -> text
  literal_comment(repo, n), literal_label_add(repo, n, label),
  literal_label_remove(repo, n, label),
  literal_assign_label(repo, n, login, label), literal_pr_close(repo, pr)
      -> argv (a comment's body argument is added when it is recorded)
  record_job_intent(paths, job, row, kind, argv, body, key, blocking, ref=None,
                    state=None) -> id, or None for a pr_close on a job with no PR
  record_probe_intent(folder, n, argv, body) -> "probe-p9-<n>"
  drain(paths, job, gh_real, tiers, login, enough=None) -> [status line]
  run_literal(paths, job, id, gh_real, login, tiers=None, lines=None) -> effect
  lookup(gh_real, job, id, login, paths=None) -> effect or None
  check_item(events_path, item) -> None or IntentChanged
  IntentNotPending, IntentChanged (both jobs.Refused, with .line), ReadFailed

record_job_intent, drain and run_literal need the job's lock (the caller
holds it); record_probe_intent takes no lock. An effect is one of
{comment_id}, {label} or {pr}: the label for label_add, label_remove and
assign_label, the PR number for pr_close.
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

import hashlib
import json
import re
from urllib.parse import quote, unquote

import _flow_factory as ff
import _flow_factory_jobs as jobs
import _flow_factory_schema as schema
from _flow_factory import Refused
from _journal_atomic import JournalAtomicError, _atomic_write

OUTBOX_SCHEMA = os.path.join(ff.PLUGIN_ROOT, "schemas", "v1", "factory-outbox.schema.json")
KINDS = ("comment", "label_add", "label_remove", "assign_label", "pr_close")
TIER_KEYS = ("push", "prCreate", "issueAssign", "issueCreate", "issueUpdate", "merge", "release")
# The terminal states of references/factory-transitions.json.
TERMINAL = ("merged", "rejected", "cancelled")
# The probe intent's marker names the probes' job key (_flow_factory.py
# PROBE_JOB_MARKER).
PROBE_JOB = "issue-0-j1"
POST_LIMIT = 60000
CRUMB = os.path.join(ff.PLUGIN_ROOT, "bin", "flow-tier-crumb.sh")
# Per gh call, as Pass.gh bounds its own calls.
GH_TIMEOUT = 15
# The item fields the intent_recorded line holds besides the hash; the drain,
# run_literal and lookup act on none of them until they equal the line's.
RECORD_FIELDS = ("job", "row", "state_at_write", "ref", "kind", "blocking", "key")

_ROW = re.compile(r"^[0-9]+[a-z]*$")
_REPO = r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+"
_ISSUE_PATH = re.compile(r"^repos/(" + _REPO + r")/issues/([1-9][0-9]*)/(comments|labels)$")
_LABEL_PATH = re.compile(r"^repos/(" + _REPO + r")/issues/([1-9][0-9]*)/labels/([^/]+)$")
_PULL_PATH = re.compile(r"^repos/(" + _REPO + r")/pulls/([1-9][0-9]*)$")
# A GitHub login or team after @, not right after a word character (an
# address such as a@b.com) or a backtick.
_MENTION = re.compile(r"(?<![A-Za-z0-9_`])@[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})(?:/[A-Za-z0-9_.-]+)?(?![A-Za-z0-9_`-])")
_TICKS = re.compile(r"`+")


class IntentNotPending(Refused):
    """run_literal of an id that is not the job's pending intent (R68)."""

    def __init__(self, iid, pending):
        self.line = f"INTENT_NOT_PENDING={iid} pending={pending or 'none'}"
        super().__init__(f"intent_not_pending {iid} pending={pending or 'none'}")


class IntentChanged(Refused):
    """The item is not the one recorded: its hash differs, or, with field,
    that field differs from the intent_recorded line (or the item says
    confirmed with no intent_confirmed line, field status)."""

    def __init__(self, iid, recorded, current, field=None):
        tail = f" recorded={recorded or 'none'} current={current or 'none'}" + (f" field={field}" if field else "")
        self.line = f"INTENT_CHANGED={iid}{tail}"
        super().__init__(f"intent_changed {iid}{tail}")


class ReadFailed(Exception):
    """A look-first read that did not answer: never the same as not found."""


# hashes, markers and cleaning ------------------------------------------------
def intent_digest(argv, body):
    """sha256 over the argv elements, each followed by a NUL byte, and then
    the body bytes (b"" for a write with no body) (plan 2.2)."""
    data = b"\0".join(a.encode("utf-8") for a in argv) + b"\0" + (body or b"")
    return hashlib.sha256(data).hexdigest()


def marker(job_key, iid):
    return f"<!-- FLOW_FACTORY job={job_key} event={iid} -->"


def _line1(text):
    """Line 1 split at LF only, one trailing CR removed (as the text module
    reads a comment's first line)."""
    line = text.split("\n", 1)[0] if isinstance(text, str) else ""
    return line[:-1] if line.endswith("\r") else line


def _code(text):
    """text as one code span, its fence one backtick longer than any run in it."""
    longest = max((len(m) for m in re.findall(r"`+", text)), default=0)
    fence = "`" * (longest + 1)
    pad = " " if text.startswith("`") or text.endswith("`") else ""
    return fence + pad + text + pad + fence


def _outside_code(line, fn):
    """line with fn applied to every part outside its code spans (a run of
    backticks up to the next run of the same length); a run with no match
    is plain text."""
    out, i = [], 0
    while i < len(line):
        m = _TICKS.search(line, i)
        if not m:
            out.append(fn(line[i:]))
            break
        out.append(fn(line[i:m.start()]))
        run = m.group(0)
        close = re.compile("(?<!`)" + run + "(?!`)").search(line, m.end())
        if close is None:
            out.append(run)
            i = m.end()
            continue
        out.append(line[m.start():close.end()])
        i = close.end()
    return "".join(out)


def _mentions(text):
    return _MENTION.sub(lambda m: "`" + m.group(0) + "`", text)


def clean_post(text):
    """Model text made safe to post (design trust_and_untrusted_text L59):
    CRLF and CR made LF, every '<!--' broken up, @mentions outside code
    spans put in backticks,
    every line whose stripped form starts with /flow-factory put in a code
    span, then cut to 60,000 characters. Cleaning cleaned text changes
    nothing. The caller's marker goes before it, never through it."""
    t = text.replace("\r\n", "\n").replace("\r", "\n")
    while "<!--" in t:
        t = t.replace("<!--", "< !--")
    out = []
    for line in t.split("\n"):
        line = _outside_code(line, _mentions)
        stripped = line.strip()
        if stripped.startswith("/flow-factory"):
            line = line[:len(line) - len(line.lstrip())] + _code(stripped)
        out.append(line)
    return "\n".join(out)[:POST_LIMIT]


# literals --------------------------------------------------------------------
def _need(cond, what):
    if not cond:
        raise ValueError(what)


def _repo_n(repo, n):
    _need(isinstance(repo, str) and re.fullmatch(_REPO, repo), f"repository {repo!r}")
    _need(isinstance(n, int) and not isinstance(n, bool) and n > 0, f"number {n!r}")


def _label_ok(label):
    _need(isinstance(label, str) and label and "," not in label and "\n" not in label, f"label {label!r}")


def literal_comment(repo, n):
    _repo_n(repo, n)
    return ["gh", "api", "--method", "POST", f"repos/{repo}/issues/{n}/comments"]


def literal_label_add(repo, n, label):
    _repo_n(repo, n)
    _label_ok(label)
    return ["gh", "api", "--method", "POST", f"repos/{repo}/issues/{n}/labels", "-f", f"labels[]={label}"]


def literal_label_remove(repo, n, label):
    _repo_n(repo, n)
    _label_ok(label)
    return ["gh", "api", "--method", "DELETE", f"repos/{repo}/issues/{n}/labels/{quote(label, safe='')}"]


def literal_assign_label(repo, n, login, label):
    _repo_n(repo, n)
    _label_ok(label)
    _need(isinstance(login, str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?", login), f"login {login!r}")
    return ["gh", "issue", "edit", str(n), "--repo", repo, "--add-assignee", login, "--add-label", label]


def literal_pr_close(repo, pr):
    _repo_n(repo, pr)
    return ["gh", "api", "--method", "PATCH", f"repos/{repo}/pulls/{pr}", "-f", "state=closed"]


def _target(kind, argv):
    """What the literal acts on, from its exact form: {repo, n} plus label,
    login or the body path; ValueError for any other form."""
    _need(isinstance(argv, list) and all(isinstance(a, str) for a in argv) and argv[:1] == ["gh"],
          f"literal {argv!r}")
    if kind == "assign_label":
        _need(len(argv) == 10 and argv[1:3] == ["issue", "edit"] and argv[4] == "--repo"
              and argv[6] == "--add-assignee" and argv[8] == "--add-label", f"literal {argv!r}")
        _need(re.fullmatch(r"[1-9][0-9]*", argv[3]) and re.fullmatch(_REPO, argv[5]), f"literal {argv!r}")
        return {"repo": argv[5], "n": int(argv[3]), "login": argv[7], "label": argv[9]}
    _need(argv[1:3] == ["api", "--method"] and len(argv) >= 5, f"literal {argv!r}")
    method, path, rest = argv[3], argv[4], argv[5:]
    if kind == "comment":
        m = _ISSUE_PATH.match(path)
        _need(method == "POST" and m and m.group(3) == "comments" and len(rest) == 2 and rest[0] == "-F"
              and rest[1].startswith("body=@"), f"literal {argv!r}")
        return {"repo": m.group(1), "n": int(m.group(2)), "body": rest[1][len("body=@"):]}
    if kind == "label_add":
        m = _ISSUE_PATH.match(path)
        _need(method == "POST" and m and m.group(3) == "labels" and len(rest) == 2 and rest[0] == "-f"
              and rest[1].startswith("labels[]="), f"literal {argv!r}")
        return {"repo": m.group(1), "n": int(m.group(2)), "label": rest[1][len("labels[]="):]}
    if kind == "label_remove":
        m = _LABEL_PATH.match(path)
        _need(method == "DELETE" and m and not rest, f"literal {argv!r}")
        return {"repo": m.group(1), "n": int(m.group(2)), "label": unquote(m.group(3))}
    if kind == "pr_close":
        m = _PULL_PATH.match(path)
        _need(method == "PATCH" and m and rest == ["-f", "state=closed"], f"literal {argv!r}")
        return {"repo": m.group(1), "n": int(m.group(2))}
    raise ValueError(f"kind {kind!r}")


# outbox files ----------------------------------------------------------------
def _unwritable(path, e):
    return Refused(f"outbox_unwritable {path}: {' '.join(str(e).split())}")


def _item_name(job_key):
    return re.compile("^" + re.escape(job_key) + r"-[0-9a-z]+-([0-9]+)\.json$")


def _read_json(path):
    try:
        if os.path.islink(path):
            return None
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError, UnicodeDecodeError):
        return None
    return data if isinstance(data, dict) else None


def _job_items(outbox, job_key):
    """[(k, path, item or None)] of the job's items, by k. Body files and
    other jobs' items are left out by their names."""
    name = _item_name(job_key)
    out = []
    for f in os.listdir(outbox):
        m = name.match(f)
        if m:
            path = os.path.join(outbox, f)
            out.append((int(m.group(1)), path, _read_json(path)))
    return sorted(out, key=lambda x: x[0])


def _save(path, item):
    errors = schema.validate(item, OUTBOX_SCHEMA)
    if errors:
        raise Refused(f"outbox_item_invalid {item.get('id')}: {errors[0]}")
    try:
        _atomic_write(path, json.dumps(item, indent=1, sort_keys=True) + "\n")
    except JournalAtomicError as e:
        raise _unwritable(path, e)


def _write_intent(outbox, events_path, iid, mark, fields, argv, body, append):
    """Write the body file, the intent_recorded line and the item, in that
    order, so a process that dies part way leaves a record with no item
    (which nothing reads, and the same write is recorded again) and never an
    item with no record (which would stop the same write being recorded
    again and could never run). A failure removes the body file and raises
    outbox_unwritable naming the file that could not be written."""
    text, body_bytes, body_file, body_path = None, b"", None, None
    if fields["kind"] == "comment":
        _need(isinstance(body, str), "a comment needs its text")
        text = (mark + "\n" + clean_post(body))[:POST_LIMIT]
        body_bytes = text.encode("utf-8")
        body_file = iid + ".body.md"
        body_path = os.path.join(outbox, body_file)
        argv = list(argv) + ["-F", "body=@" + body_path]
    else:
        _need(body is None, f"a {fields['kind']} write has no body")
    _target(fields["kind"], argv)
    sha = intent_digest(argv, body_bytes)
    item = dict(fields, id=iid, argv=list(argv), body_file=body_file, sha256=sha, status="recorded", effect=None)
    errors = schema.validate(item, OUTBOX_SCHEMA)
    _need(not errors, f"outbox item {errors[:1]}")
    item_path = os.path.join(outbox, iid + ".json")
    made, where = [], outbox
    try:
        if text is not None:
            where = body_path
            _atomic_write(body_path, text)
            made.append(body_path)
        where = events_path
        line = {"type": "intent_recorded", "job": fields["job"], "time": ff.utc_now(), "id": iid, "sha256": sha}
        line.update({f: fields[f] for f in RECORD_FIELDS if f != "job"})
        append(line)
        where = item_path
        _atomic_write(item_path, json.dumps(item, indent=1, sort_keys=True) + "\n", exclusive=True)
        return item
    except (OSError, JournalAtomicError, Refused) as e:
        for p in made:
            try:
                os.remove(p)
            except OSError:
                pass
        raise _unwritable(where, e)


def _check_fields(kind, key, blocking, ref):
    _need(kind in KINDS, f"kind {kind!r}")
    _need(isinstance(key, list) and key and all(k in TIER_KEYS for k in key) and len(set(key)) == len(key),
          f"key {key!r}")
    _need(isinstance(blocking, bool), "blocking")
    _need(ref is None or (isinstance(ref, int) and not isinstance(ref, bool) and ref > 0), f"ref {ref!r}")


def record_job_intent(paths, job, row, kind, argv, body, key, blocking, ref=None, state=None):
    """Record one write of the job and return its intent id (plan 2.2): k is
    1 + the larger of job.json write_seq and the largest k of the job's items
    in J/outbox, and job["write_seq"] is set to it (the caller writes
    job.json). row is the row id, or "note" (or None) for a write no row
    makes; state is the state the write belongs to (default the job's).
    With a ref, an item of the same kind, row and ref is found and its id
    returned, recording nothing. A pr_close on a job with no PR records
    nothing and returns None. Raises Refused("outbox_unwritable ...") for
    any failure to write, the job lock not held included."""
    _check_fields(kind, key, blocking, ref)
    n, job_key = job.get("issue"), job.get("key")
    _need(isinstance(job_key, str) and re.fullmatch(r"issue-[1-9][0-9]*-j[1-9][0-9]*", job_key)
          and job_key.startswith(f"issue-{n}-"), f"job {job_key!r}")
    word = "note" if row in (None, "note") else row
    _need(word == "note" or (isinstance(word, str) and _ROW.match(word)), f"row {row!r}")
    item_row = None if word == "note" else word
    if kind == "pr_close":
        pr = job.get("pr")
        if not isinstance(pr, int) or isinstance(pr, bool) or pr < 1:
            return None
    jdir = jobs.job_dir(paths, n)
    outbox = os.path.join(jdir, "outbox")
    try:
        jobs._need_job_lock(n)
    except Refused as e:
        raise _unwritable(os.path.join(jdir, "events.jsonl"), e)
    try:
        jobs._ensure(paths, outbox)
        found = _job_items(outbox, job_key)
    except (Refused, OSError) as e:
        raise _unwritable(outbox, e)
    if ref is not None:
        for _, _, it in found:
            if it and it.get("kind") == kind and it.get("row") == item_row and it.get("ref") == ref:
                return it["id"]
    seq = job.get("write_seq")
    seq = seq if isinstance(seq, int) and not isinstance(seq, bool) and seq > 0 else 0
    k = 1 + max([seq] + [x[0] for x in found])
    iid = f"{job_key}-{word}-{k}"
    fields = {"job": job_key, "row": item_row, "state_at_write": state or job.get("state"), "ref": ref,
              "kind": kind, "blocking": blocking, "key": list(key)}
    _write_intent(outbox, os.path.join(jdir, "events.jsonl"), iid, marker(job_key, iid), fields, argv, body,
                  lambda line: jobs.append_event(paths, n, line))
    job["write_seq"] = k
    return iid


def record_probe_intent(folder, n, argv, body):
    """Record the P9 probe's comment intent probe-p9-<n> in
    <folder>/outbox, with its intent_recorded line in <folder>/events.jsonl
    (no lock). An item already there is refused as outbox_unwritable."""
    _need(isinstance(n, int) and not isinstance(n, bool) and n > 0, f"probe number {n!r}")
    iid = f"probe-p9-{n}"
    outbox = os.path.join(folder, "outbox")
    try:
        os.makedirs(outbox, exist_ok=True)
    except OSError as e:
        raise _unwritable(outbox, e)
    fields = {"job": None, "row": None, "state_at_write": None, "ref": None, "kind": "comment",
              "blocking": False, "key": ["issueUpdate"]}
    events_path = os.path.join(folder, "events.jsonl")
    _write_intent(outbox, events_path, iid, marker(PROBE_JOB, iid), fields, argv, body,
                  lambda line: ff.append_jsonl(events_path, line))
    return iid


# the hash check --------------------------------------------------------------
def _recorded(events_path, iid):
    """(the last intent_recorded line for iid or None, whether an
    intent_confirmed line names iid)."""
    rec, confirmed = None, False
    try:
        with open(events_path, encoding="utf-8") as f:
            for ln in f:
                try:
                    d = json.loads(ln)
                except ValueError:
                    continue
                if not isinstance(d, dict) or d.get("id") != iid:
                    continue
                if d.get("type") == "intent_recorded":
                    rec = d
                elif d.get("type") == "intent_confirmed":
                    confirmed = True
    except (OSError, UnicodeDecodeError):
        return None, False
    return rec, confirmed


def _body(item):
    """The bytes the literal posts: b"" for a write with no body. A
    comment's body is read from the file its argv names after -F body=@,
    the file gh posts; body_file must be <id>.body.md, and the argv path
    is part of the hash, so a recorded hash matches only when that path is
    the J/outbox/<id>.body.md the record wrote. None when body_file is
    another name, the file is a symbolic link or cannot be read."""
    bf = item.get("body_file")
    if item.get("kind") != "comment":
        return b"" if bf is None else None
    try:
        path = _target("comment", item.get("argv"))["body"]
    except ValueError:
        return None
    if bf != f"{item.get('id')}.body.md" or os.path.islink(path):
        return None
    try:
        with open(path, "rb") as f:
            return f.read()
    except OSError:
        return None


def _current_sha(item):
    """The hash of the item's argv and of the body gh would post, or None."""
    argv = item.get("argv")
    if not isinstance(argv, list) or not all(isinstance(a, str) for a in argv):
        return None
    body = _body(item)
    return None if body is None else intent_digest(argv, body)


def _same(a, b):
    return json.dumps(a, sort_keys=True) == json.dumps(b, sort_keys=True)


def check_item(events_path, item):
    """None when the item is the one its intent_recorded line records and may
    be acted on, else the IntentChanged to report: the hash of the argv and
    the posted body differs from the line's (or either is missing); a field
    of RECORD_FIELDS differs from the line's (field=<name>); or the status is
    confirmed on a blocking item, or with no intent_confirmed line (Q16
    confirms notices only, field=status)."""
    iid = item.get("id")
    rec, confirmed = _recorded(events_path, iid)
    recorded = rec.get("sha256") if rec is not None and isinstance(rec.get("sha256"), str) else None
    current = _current_sha(item)
    if recorded is None or current is None or recorded != current:
        return IntentChanged(iid, recorded, current)
    for f in RECORD_FIELDS:
        if f not in rec or not _same(rec[f], item.get(f)):
            return IntentChanged(iid, recorded, current, field=f)
    if item.get("status") == "confirmed" and (item.get("blocking") is not False or not confirmed):
        return IntentChanged(iid, recorded, current, field="status")
    return None


def _valid(path, iid, job_key):
    """The item at path when it reads, validates, is named by its own id and
    belongs to job_key; else None."""
    item = _read_json(path)
    if item is None or item.get("id") != iid or item.get("job") != job_key or schema.validate(item, OUTBOX_SCHEMA):
        return None
    return item


# gh --------------------------------------------------------------------------
def _gh(gh_real, args, cwd):
    """(exit status, stdout, stderr) of gh_real with these arguments, run
    without a shell, with FLOW_TIER_* removed and prompts off."""
    if not isinstance(gh_real, str) or not os.path.isabs(gh_real):
        return None, "", "no gh"
    env = {k: v for k, v in os.environ.items() if not k.startswith("FLOW_TIER_")}
    env["GH_PROMPT_DISABLED"] = "1"
    return ff.run_cmd([gh_real] + list(args), cwd, env, timeout=GH_TIMEOUT)


def _why(rc, err):
    first = next((x.strip() for x in (err or "").splitlines() if x.strip()), "")
    return " ".join(f"gh exited {rc}: {first}".split())[:300]


def _read(gh_real, args, cwd):
    rc, out, err = _gh(gh_real, args, cwd)
    if rc != 0:
        raise ReadFailed(_why(rc, err))
    try:
        return json.loads(out)
    except ValueError:
        raise ReadFailed("gh printed output that is not JSON")


def _look(gh_real, item, login, cwd):
    """The write's effect when it is already on GitHub, else None; ReadFailed
    when a read does not answer or there is no engine login."""
    if not isinstance(login, str) or not login:
        raise ReadFailed("engine_login_unknown")
    kind = item["kind"]
    t = _target(kind, item["argv"])
    repo, n = t["repo"], t["n"]
    if kind == "comment":
        mark = marker(item.get("job") or PROBE_JOB, item["id"])
        pages = _read(gh_real, ["api", "--paginate", "--slurp", f"repos/{repo}/issues/{n}/comments?per_page=100"], cwd)
        if not isinstance(pages, list) or not all(isinstance(p, list) for p in pages):
            raise ReadFailed("the comment list is not a list of pages")
        for page in pages:
            for c in page:
                user = c.get("user") if isinstance(c, dict) else None
                cid = c.get("id") if isinstance(c, dict) else None
                if isinstance(user, dict) and user.get("login") == login and isinstance(cid, int) \
                        and _line1(c.get("body")) == mark:
                    return {"comment_id": cid}
        return None
    if kind == "pr_close":
        pull = _read(gh_real, ["api", f"repos/{repo}/pulls/{n}"], cwd)
        if not isinstance(pull, dict):
            raise ReadFailed("the pull request is not an object")
        return {"pr": n} if pull.get("state") == "closed" else None
    issue = _read(gh_real, ["api", f"repos/{repo}/issues/{n}"], cwd)
    if not isinstance(issue, dict):
        raise ReadFailed("the issue is not an object")
    labels = {x.get("name") for x in issue.get("labels") or [] if isinstance(x, dict)}
    if kind == "label_add":
        return {"label": t["label"]} if t["label"] in labels else None
    if kind == "label_remove":
        return {"label": t["label"]} if t["label"] not in labels else None
    assignees = {x.get("login") for x in issue.get("assignees") or [] if isinstance(x, dict)}
    return {"label": t["label"]} if t["login"] in assignees and t["label"] in labels else None


def _run(gh_real, item, cwd):
    """(effect, None) once the literal ran, or (None, why not)."""
    kind = item["kind"]
    t = _target(kind, item["argv"])
    rc, out, err = _gh(gh_real, item["argv"][1:], cwd)
    if rc != 0:
        return None, _why(rc, err)
    if kind == "comment":
        try:
            cid = json.loads(out).get("id")
        except (ValueError, AttributeError):
            cid = None
        if not isinstance(cid, int) or isinstance(cid, bool) or cid < 1:
            return None, "gh printed no comment id"
        return {"comment_id": cid}, None
    if kind == "pr_close":
        return {"pr": t["n"]}, None
    return {"label": t["label"]}, None


def _found_text(effect):
    return str(next(iter(effect.values())))


def _crumbs(main, n, item, tiers):
    """One breadcrumb per key of the item that resolves to journal. A
    breadcrumb that cannot be written does not undo the write."""
    summary = item["id"] + " " + " ".join(item["argv"])
    env = {k: v for k, v in os.environ.items() if not k.startswith("FLOW_TIER_")}
    for key in item["key"]:
        if tiers(key) == "journal":
            ff.run_cmd(["/bin/bash", CRUMB, "--issue", str(n), "--main", main, key, summary], main, env, timeout=30)


def _sent(paths, n, path, item, effect):
    item = dict(item, status="sent", effect=effect)
    _save(path, item)
    jobs.append_event(paths, n, {"type": "write_recorded", "job": item["job"], "time": ff.utc_now(),
                                 "id": item["id"], "effect": effect})
    return item


# drain, run_literal, lookup --------------------------------------------------
def drain(paths, job, gh_real, tiers, login, enough=None):
    """Run the job's unsent outbox items (plan 2.2 'Who runs an item', B6
    step 3) and return the status lines. Never touches the job's pending
    intent. Every unsent item is first checked against its intent_recorded
    line (check_item), so every later decision reads recorded values. On a
    terminal job only the items of that state run and every other unsent
    item is dropped; a pending_confirm notice whose job has left its state
    is dropped. Then the effect is looked for, and a write found is recorded
    with no run and no breadcrumb (design github_writes_and_tiers L50: the
    breadcrumb goes with the run). Then the keys decide: all autonomous or
    journal runs it (one breadcrumb per journal key), any confirm leaves a
    blocking item recorded and makes a notice pending_confirm. A confirmed
    notice runs whatever its keys say. enough, when given, is asked before
    every gh call; when it says no the drain prints WRITE_DEFERRED for the
    item it stopped at and stops, and the rest waits for the next pass
    (plan 3.2)."""
    n, job_key, state = job["issue"], job["key"], job.get("state")
    jobs._need_job_lock(n)
    if not isinstance(login, str) or not login:
        return [f"ENGINE_LOGIN_UNKNOWN job={job_key}"]
    jdir = jobs.job_dir(paths, n)
    outbox = os.path.join(jdir, "outbox")
    events_path = os.path.join(jdir, "events.jsonl")
    if not os.path.isdir(outbox) or os.path.islink(outbox):
        return []
    pending = job.get("pending_intent")
    pending_id = pending.get("id") if isinstance(pending, dict) else None
    lines = []
    for _, path, _ in _job_items(outbox, job_key):
        name = os.path.basename(path)
        item = _valid(path, name[:-len(".json")], job_key)
        if item is None:
            lines.append(f"OUTBOX_ITEM_INVALID job={job_key} file={name}")
            continue
        status, iid = item["status"], item["id"]
        if status not in ("recorded", "pending_confirm", "confirmed") or iid == pending_id:
            continue
        changed = check_item(events_path, item)
        if changed:
            lines.append(changed.line)
            continue
        at = item["state_at_write"]
        if (state in TERMINAL and at != state) or (status == "pending_confirm" and at != state):
            _save(path, dict(item, status="dropped"))
            lines.append(f"WRITE_DROPPED job={job_key} intent={iid} state_at_write={at} state={state}")
            continue
        deferred = f"WRITE_DEFERRED job={job_key} intent={iid} reason=budget"
        if enough is not None and not enough():
            lines.append(deferred)
            break
        try:
            effect = _look(gh_real, item, login, paths.main)
        except ReadFailed as e:
            lines.append(f"WRITE_FAILED job={job_key} intent={iid} lookup: {e}")
            continue
        if effect:
            _sent(paths, n, path, item, effect)
            lines.append(f"WRITE_SKIPPED job={job_key} intent={iid} found={_found_text(effect)}")
            continue
        if status != "confirmed" and any(tiers(k) == "confirm" for k in item["key"]):
            if not item["blocking"] and status == "recorded":
                _save(path, dict(item, status="pending_confirm"))
                lines.append(f"PENDING_CONFIRM job={job_key} intent={iid} kind={item['kind']}")
            continue
        if enough is not None and not enough():
            lines.append(deferred)
            break
        effect, why = _run(gh_real, item, paths.main)
        if effect is None:
            lines.append(f"WRITE_FAILED job={job_key} intent={iid} {why}")
            continue
        _sent(paths, n, path, item, effect)
        _crumbs(paths.main, n, item, tiers)
        lines.append(f"WRITE_SENT job={job_key} intent={iid} kind={item['kind']}")
    return lines


def run_literal(paths, job, iid, gh_real, login, tiers=None, lines=None):
    """Run the job's pending intent (rows 41 and 41k) and return its effect.
    Raises IntentNotPending unless iid is job.pending_intent.id, and
    IntentChanged when the item's hash is not the recorded one; then looks
    first, and an effect found is recorded (a WRITE_SKIPPED line appended to
    lines) with nothing run. With tiers, one breadcrumb per journal key
    after a run. A failed lookup or run raises Refused("write_failed ...");
    no engine login raises Refused("engine_login_unknown")."""
    n, job_key = job["issue"], job["key"]
    jobs._need_job_lock(n)
    pending = job.get("pending_intent")
    pending_id = pending.get("id") if isinstance(pending, dict) else None
    if iid != pending_id:
        raise IntentNotPending(iid, pending_id)
    jdir = jobs.job_dir(paths, n)
    outbox = os.path.join(jdir, "outbox")
    path = os.path.join(outbox, f"{iid}.json")
    item = _valid(path, iid, job_key)
    if item is None:
        raise Refused(f"intent_unknown {iid}")
    changed = check_item(os.path.join(jdir, "events.jsonl"), item)
    if changed:
        raise changed
    if not isinstance(login, str) or not login:
        raise Refused("engine_login_unknown")
    try:
        effect = _look(gh_real, item, login, paths.main)
    except ReadFailed as e:
        raise Refused(f"write_failed {iid}: lookup: {e}")
    if effect:
        _sent(paths, n, path, item, effect)
        if lines is not None:
            lines.append(f"WRITE_SKIPPED job={job_key} intent={iid} found={_found_text(effect)}")
        return effect
    effect, why = _run(gh_real, item, paths.main)
    if effect is None:
        raise Refused(f"write_failed {iid}: {why}")
    _sent(paths, n, path, item, effect)
    if tiers is not None:
        _crumbs(paths.main, n, item, tiers)
    return effect


def lookup(gh_real, job, iid, login, paths=None):
    """The effect of the job's intent iid when it is on GitHub, else None.
    Raises ReadFailed when a read does not answer, the item cannot be read,
    the item is not the one recorded ('intent_changed ...', check_item), or
    login is not a login. paths defaults to the main checkout found from the
    working directory."""
    if paths is not None:
        fdir, cwd = paths.fdir, paths.main
    else:
        try:
            cwd = ff.main_checkout()
            fdir = os.path.join(cwd, ff.factory_rel(cwd))
        except Refused as e:
            raise ReadFailed(f"no factory directory: {e}")
    n = job.get("issue")
    if not isinstance(n, int) or isinstance(n, bool) or n < 1 or not isinstance(iid, str) or "/" in iid:
        raise ReadFailed("item_unreadable")
    jdir = os.path.join(fdir, "jobs", f"issue-{n}")
    outbox = os.path.join(jdir, "outbox")
    item = _valid(os.path.join(outbox, f"{iid}.json"), iid, job.get("key"))
    if item is None:
        raise ReadFailed("item_unreadable")
    changed = check_item(os.path.join(jdir, "events.jsonl"), item)
    if changed:
        raise ReadFailed(str(changed))
    return _look(gh_real, item, login, cwd)
