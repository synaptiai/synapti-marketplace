"""[flow] The factory's trusted issue text (design trust_and_untrusted_text
item 2; plan 1b 5.3 Text module). No network code: the trust flags on a
snapshot's comments come from the issue module.

  command_of(body) -> (name, rest) or None
                          the one first-line parser for /flow-factory comment
                          commands; the issue and command modules import it
  is_command_line(body)   line 1 starts "/flow-factory ", known command or not
  is_engine_marker(line)  the engine's marker line, whoever posted it
  body_sha256(body)       the hash a re-vouch keeps for a reply's body
  is_reply_to(comment, round)
                          names one of the round's question ids, is created
                          strictly after its asked_at, and its first line is
                          neither an engine marker nor a command other than
                          spec (trust is the caller's part)
  spec_input_set(snapshot, needs_info, revouched) -> items
  other_comments(snapshot, items) -> [{author, created_at, length}]
  digest(items)           issue_digest: sha256 over the canonical JSON
  render_issue_md(items, others) -> str
  issue_set(snapshot, needs_info, revouched) -> {items, others, digest}

A snapshot is {title, body, comments: [{id, author, author_type, created_at,
body, trusted}], answers: [{qid, text}]}; answers may be missing. Items are
[["title", t], ["body", b], ["comment", id, body]..., ["answer", qid, text]...]
with comments in id order and answers in file order. Items hold the raw
texts; only issue.md is neutralised.
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

import _flow_factory_jobs as jobs

COMMAND = re.compile(r"/flow-factory (answer|approve-spec|rework|reject|cancel|spec|retry)\b(.*)")
COMMAND_PREFIX = "/flow-factory "
# The event value takes every id form the engine posts: an intent id
# (issue-N-j<seq>-<row>-<k>) and the probes' probe-p9-<n>, probe-review-<hex>
# and probe-comment-<hex>.
MARKER = re.compile(r"<!-- FLOW_FACTORY job=issue-[0-9]+-j[0-9]+ event=[A-Za-z0-9][A-Za-z0-9_.-]{0,127} -->")
# The digits run is greedy, so NI-1 is never found inside NI-10.
QUESTION = re.compile(r"(?<![A-Za-z0-9_-])(NI-[0-9]+)")
QID = re.compile(r"NI-[0-9]+")
RUN_LT = re.compile(r"<{3,}")
RUN_GT = re.compile(r">{3,}")


def _line1(text):
    """Line 1 of a body, split at LF only, with one trailing CR removed."""
    line = text.split("\n", 1)[0] if isinstance(text, str) else ""
    return line[:-1] if line.endswith("\r") else line


def command_of(body):
    """(name, rest of line 1) for a /flow-factory command, else None."""
    m = COMMAND.fullmatch(_line1(body))
    return (m.group(1), m.group(2)) if m else None


def is_command_line(body):
    return _line1(body).startswith(COMMAND_PREFIX)


def is_engine_marker(line):
    if not isinstance(line, str):
        return False
    if line.endswith("\r"):
        line = line[:-1]
    return MARKER.fullmatch(line) is not None


def body_sha256(body):
    return hashlib.sha256(body.encode("utf-8")).hexdigest()


def _never_reply(body):
    """An engine marker or a command other than spec on line 1 (an unknown
    /flow-factory line included): metadata only, never a needs-info reply."""
    if is_engine_marker(_line1(body)):
        return True
    if is_command_line(body):
        cmd = command_of(body)
        return cmd is None or cmd[0] != "spec"
    return False


def _after(at, floor):
    """at is strictly later than floor; an unreadable time is not later."""
    a, f = jobs.epoch(at), jobs.epoch(floor)
    return a is not None and f is not None and a > f


def is_reply_to(comment, rnd):
    body = comment.get("body")
    if not isinstance(body, str) or not isinstance(rnd, dict) or _never_reply(body):
        return False
    questions = rnd.get("questions") or []
    if not set(QUESTION.findall(body)) & set(questions):
        return False
    return _after(comment.get("created_at"), rnd.get("asked_at"))


def _rounds(needs_info):
    if not isinstance(needs_info, dict):
        return []
    # An earlier round that is not an object is passed on as it is:
    # is_reply_to, the only reader of these rounds, gives False for it.
    return [needs_info] + list(needs_info.get("earlier") or [])


def _comments(snapshot):
    """The snapshot's comments in id order, each id once (the first seen)."""
    seen, out = set(), []
    for com in snapshot.get("comments") or []:
        i = com.get("id")
        if type(i) is not int or i < 0:
            raise ValueError("comment id is not a non-negative integer: %r" % (i,))
        if not isinstance(com.get("body"), str):
            raise ValueError("comment %d has no text body" % i)
        if i not in seen:
            seen.add(i)
            out.append(com)
    return sorted(out, key=lambda com: com["id"])


def spec_input_set(snapshot, needs_info, revouched):
    """The spec-input set (design trust_and_untrusted_text L10-L15): title,
    body, trusted /flow-factory spec comments at any time, trusted needs-info
    replies of the current or any earlier round, re-vouched replies whose body
    still has the hash taken at the re-vouch, then the answers file."""
    rounds = _rounds(needs_info)
    revouched = revouched or {}
    items = [["title", snapshot.get("title") or ""], ["body", snapshot.get("body") or ""]]
    for com in _comments(snapshot):
        body = com["body"]
        if _never_reply(body):
            continue
        trusted = com.get("trusted") is True
        cmd = command_of(body)
        if trusted and cmd is not None and cmd[0] == "spec":
            keep = True
        elif trusted and any(is_reply_to(com, r) for r in rounds):
            keep = True
        else:
            # A re-vouched reply counts only at the body it had at the
            # re-vouch; the hash is all that is kept, so a changed body is
            # left out (the issue module reports the edit).
            keep = revouched.get(str(com["id"])) == body_sha256(body)
        if keep:
            items.append(["comment", com["id"], body])
    for ans in snapshot.get("answers") or []:
        qid, text = ans.get("qid"), ans.get("text")
        if not isinstance(qid, str) or not QID.fullmatch(qid) or not isinstance(text, str):
            raise ValueError("answers entry is not {qid: NI-<k>, text}: %r" % (ans,))
        items.append(["answer", qid, text])
    return items


def other_comments(snapshot, items):
    """Every comment that is not a comment item of the set, by author, date
    and length only (design trust_and_untrusted_text L21)."""
    inset = {x[1] for x in items if x[0] == "comment"}
    return [{"author": com.get("author"), "created_at": com.get("created_at"), "length": len(com["body"])}
            for com in _comments(snapshot) if com["id"] not in inset]


def digest(items):
    data = json.dumps(items, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(data.encode("utf-8")).hexdigest()


def _neutralise(text):
    text = RUN_LT.sub(lambda m: "‹" * len(m.group()), text)
    return RUN_GT.sub(lambda m: "›" * len(m.group()), text)


def _one_line(text):
    return " ".join(str(text).splitlines())


def _quote(text):
    return ["> " + line for line in (_neutralise(text).splitlines() or [""])]


def _fence(name, lines):
    return ["<<<UNTRUSTED_ISSUE_%s>>>" % name] + lines + ["<<<END_UNTRUSTED_ISSUE_%s>>>" % name, ""]


def render_issue_md(items, others):
    """issue.md: each item of the set quoted and fenced, then the other
    comments listed by author, date and length."""
    out = []
    for item in items:
        kind = item[0] if isinstance(item, list) and item else None
        if kind == "title" and len(item) == 2:
            out += _fence("TITLE", ["> " + _neutralise(_one_line(item[1]))])
        elif kind == "body" and len(item) == 2:
            out += _fence("BODY", _quote(item[1]))
        elif kind == "comment" and len(item) == 3:
            i = item[1]
            if type(i) is not int or i < 0:
                raise ValueError("comment id is not a non-negative integer: %r" % (i,))
            out += _fence("COMMENT id=%d" % i, _quote(item[2]))
        elif kind == "answer" and len(item) == 3:
            if not isinstance(item[1], str) or not QID.fullmatch(item[1]):
                raise ValueError("answer qid is not NI-<k>: %r" % (item[1],))
            out += _fence("ANSWER qid=%s" % item[1], _quote(item[2]))
        else:
            raise ValueError("unknown spec-input item: %r" % (item,))
    if not others:
        out.append("Other comments: none")
    else:
        out.append("Other comments:")
        for o in others:
            out.append("- %s %s %d chars" % (_neutralise(_one_line(o.get("author"))),
                                             _neutralise(_one_line(o.get("created_at"))), int(o.get("length"))))
    return "\n".join(out) + "\n"


def issue_set(snapshot, needs_info, revouched):
    """The set, its Other comments list and its digest from one read, the
    form J/sync/issue-set.json keeps."""
    items = spec_input_set(snapshot, needs_info, revouched)
    return {"items": items, "others": other_comments(snapshot, items), "digest": digest(items)}
