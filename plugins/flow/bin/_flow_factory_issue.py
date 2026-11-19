"""[flow] The factory's issue reads and issue facts (plan 1b B4; design
trust_and_untrusted_text item 1, person_channels item 5, T:creation row 1,
T:facts).

Every reader takes gh, a callable with Pass.gh's contract,
gh(args) -> (ok, parsed JSON), and repo, "owner/name". Every list that GitHub
pages is read with `gh api --paginate --slurp`, which prints one outer array
of pages. A read that fails gives None for the whole issue, and the caller
then computes no fact for it (plan 3.1). A permission read that fails is not
a failed issue read: it makes that login untrusted (person_channels L54).

  Permissions(gh, repo, settings=None)
      .of(login) -> "none"|"read"|"triage"|"write"|"maintain"|"admin"
      .trusted(login, type) -> bool   write or higher, raised by
                                      trustedPermission, never lowered
      .write(login, type) -> bool     write or higher, whatever
                                      trustedPermission says
      .triage(login, type) -> bool    triage or higher
      .open_pulls() -> [pull] or None the repository's open pulls
      A login ending in [bot], or of type Bot, is none of trusted, write or
      triage unless trustedBots lists it; for a listed bot its role decides.
      A type other than User or Bot (an Organization, a Mannequin, the
      reads' "Unknown") is none of the three whatever the role or
      trustedBots says (plan AC2: an unknown account fails closed); a
      missing type (None) counts as User (plan 5.3 Issue module).
      One read per login per object, and one read of the open pulls, a
      failed read included (a role counts as none, the pulls as None); the
      sync makes one object per pass.
  read_issue(gh, repo, n, job, perms) -> snapshot or None
  read_unjobbed(gh, repo, n, perms, settings=None) -> dict or None
  latest_label_event(events, label) -> event or None
  creation_conditions(unjobbed, local, settings=None) -> bool
      local is {"open_job": bool, "terminal_vouch_at": [time or None]}: the
      issue's jobs on this machine
  needs_info_answers(snapshot, job) -> (trusted ids, untrusted ids)
  untrusted_edit(snapshot, job) -> bool
  facts(snapshot, job, settings=None) -> {fact: bool} for untrusted_edit,
      needs_info_answer, untrusted_needs_info_answer, cancel_signal,
      untrusted_close and dependency_open

settings is a callable setting(key, default) (jobs.setting when None).

A snapshot is the text module's shape, {title, body, comments: [{id, author,
author_type, created_at, body, trusted}]}, with no answers key (the caller
adds the answers file), plus:
  state, labels      the issue's state and label names
  closed_by          {login, type, trusted} or None
  events             the labeled, unlabeled, closed, reopened and renamed
                     events in GitHub's order: {id, event, label, actor,
                     actor_type, created_at, rename, trusted}
  edits              {"issue" | "comment:<id>": [{editor, editor_type,
                     edited_at, trusted}]}, newest first
  dependencies       {"<m>": state} of the issues a queued job's body names
                     on Depends on and Blocked by lines ({} otherwise)
  pr_merged          whether the job's PR is merged (False with no PR)
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
from urllib.parse import quote

import _flow_factory_jobs as jobs
import _flow_factory_text as text

ROLES = ("none", "read", "triage", "write", "maintain", "admin")
RANK = {r: i for i, r in enumerate(ROLES)}
# The legacy permission field has no triage or maintain: a triage user shows
# as read there (person_channels L54: without role_name triage counts as read).
LEGACY = {"admin": "admin", "write": "write", "triage": "read", "read": "read", "none": "none"}
EVENT_KINDS = ("labeled", "unlabeled", "closed", "reopened", "renamed")
# GitHub's closing keywords, followed by the issue's own #N.
CLOSING = r"(?i)(?<![A-Za-z0-9_])(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?\s+#%d(?![0-9A-Za-z_])"
DEP_LINE = re.compile(r"^(?:Depends on|Blocked by)\b(.*)$", re.MULTILINE)
DEP_REF = re.compile(r"(?<![A-Za-z0-9_./-])#([0-9]{1,9})(?![0-9A-Za-z_])")
GRAPHQL_PAGES = 100
EDITS = ("lastEditedAt editor { login __typename } "
         "userContentEdits(first: 100) { nodes { editedAt editor { login __typename } } "
         "pageInfo { hasNextPage endCursor } }")
QUERY = ("query($owner: String!, $name: String!, $number: Int!, $after: String) { "
         "repository(owner: $owner, name: $name) { issue(number: $number) { " + EDITS + " "
         "comments(first: 100, after: $after) { nodes { databaseId " + EDITS + " } "
         "pageInfo { hasNextPage endCursor } } } } }")


def _setting(settings):
    return settings if callable(settings) else jobs.setting


# The actor types the trust tests know: a person, and a Bot or App actor
# (design person_channels L54). A missing type counts as User (plan 5.3
# Issue module); the reads give every other type as UNKNOWN, which no trust
# test passes (plan AC2: an unknown account fails closed).
TYPES = ("User", "Bot")
UNKNOWN = "Unknown"


def _type(value):
    if value is None:
        return "User"
    return value if value in TYPES else UNKNOWN


def _is_bot(login, typ):
    return login.endswith("[bot]") or typ == "Bot"


class Permissions:
    """Repository roles from the collaborator permission endpoint, for one
    sync. trusted and triage are the only trust tests; of is the role only."""

    def __init__(self, gh, repo, settings=None):
        self.gh, self.repo = gh, repo
        setting = _setting(settings)
        bots = setting("flow.factory.trustedBots", [])
        self.bots = {b for b in bots if isinstance(b, str)} if isinstance(bots, list) else set()
        bar = setting("flow.factory.trustedPermission", "write")
        self.bar = max(RANK["write"], RANK.get(bar, RANK["write"]) if isinstance(bar, str) else RANK["write"])
        self._roles = {}
        self._pulls = False

    def of(self, login):
        if not isinstance(login, str) or not login:
            return "none"
        if login not in self._roles:
            self._roles[login] = self._read(login)
        return self._roles[login]

    def _read(self, login):
        ok, data = self.gh(["api", f"repos/{self.repo}/collaborators/{quote(login, safe='')}/permission"])
        if not ok or not isinstance(data, dict):
            return "none"
        role = data.get("role_name")
        if isinstance(role, str):
            # A custom role, or any name not in ROLES, is none: the design
            # reads role_name only (person_channels item 5).
            return role if role in RANK else "none"
        # No role_name: the legacy field, whose triage shows as read (R55).
        legacy = data.get("permission")
        return LEGACY.get(legacy, "none") if isinstance(legacy, str) else "none"

    def _counts(self, login, typ):
        if not isinstance(login, str) or not login or (typ is not None and typ not in TYPES):
            return False
        return not _is_bot(login, typ) or login in self.bots

    def trusted(self, login, typ):
        return self._counts(login, typ) and RANK[self.of(login)] >= self.bar

    def write(self, login, typ):
        return self._counts(login, typ) and RANK[self.of(login)] >= RANK["write"]

    def triage(self, login, typ):
        return self._counts(login, typ) and RANK[self.of(login)] >= RANK["triage"]

    def open_pulls(self):
        """The open pulls of the repository, all pages, read once for this
        object; None when that read failed."""
        if self._pulls is False:
            self._pulls = _pages(self.gh, f"repos/{self.repo}/pulls?state=open&per_page=100")
        return self._pulls


# reads ---------------------------------------------------------------------
def _api(gh, path):
    ok, data = gh(["api", path])
    return data if ok and isinstance(data, dict) else None


def _pages(gh, path):
    ok, pages = gh(["api", "--paginate", "--slurp", path])
    if not ok or not isinstance(pages, list) or not all(isinstance(p, list) for p in pages):
        return None
    return [x for p in pages for x in p]


def _who(obj):
    """(login, type) of a REST user object, the type User, Bot or UNKNOWN;
    (None, None) for a deleted one."""
    if not isinstance(obj, dict) or not isinstance(obj.get("login"), str) or not obj.get("login"):
        return None, None
    return obj["login"], _type(obj.get("type"))


def _events(raw, perms):
    out = []
    for e in raw:
        if not isinstance(e, dict) or e.get("event") not in EVENT_KINDS:
            continue
        login, typ = _who(e.get("actor"))
        label = e.get("label")
        out.append({"id": e.get("id"), "event": e["event"],
                    "label": label.get("name") if isinstance(label, dict) else None,
                    "actor": login, "actor_type": typ, "created_at": e.get("created_at"),
                    "rename": e.get("rename") if isinstance(e.get("rename"), dict) else None,
                    "trusted": perms.trusted(login, typ)})
    return out


def _edit_list(node, perms):
    """The edits of one GraphQL node, newest first. A history with a next
    page adds an unknown editor at the node's last edit time (lastEditedAt,
    or a later edit read), since the edits not read may be as late as that
    whatever order GitHub lists them in; with no readable last edit time
    its time is None, which counts as after any vouch_at."""
    out = []

    def add(editor, at):
        login = editor.get("login") if isinstance(editor, dict) else None
        login = login if isinstance(login, str) and login else None
        typ = _type(editor.get("__typename")) if login else None
        out.append({"editor": login, "editor_type": typ, "edited_at": at, "trusted": perms.trusted(login, typ)})

    hist = node.get("userContentEdits")
    if not isinstance(hist, dict) or not isinstance(hist.get("nodes"), list):
        return None
    for e in hist["nodes"]:
        if not isinstance(e, dict):
            return None
        add(e.get("editor"), e.get("editedAt"))
    if node.get("lastEditedAt") is not None:
        add(node.get("editor"), node.get("lastEditedAt"))
    info = hist.get("pageInfo")
    if not (isinstance(info, dict) and info.get("hasNextPage") is False):
        last = node.get("lastEditedAt")
        if jobs.epoch(last) is None:
            add(None, None)
        else:
            seen = [x["edited_at"] for x in out if jobs.epoch(x["edited_at"]) is not None]
            add(None, max(seen, key=jobs.epoch))
    out.sort(key=lambda x: x["edited_at"] if isinstance(x["edited_at"], str) else "~", reverse=True)
    return out


def _edits(gh, repo, n, perms):
    owner, name = repo.split("/", 1)
    edits, after = {}, None
    for _ in range(GRAPHQL_PAGES):
        args = ["api", "graphql", "-f", "query=" + QUERY, "-f", "owner=" + owner, "-f", "name=" + name,
                "-F", f"number={n}"]
        if after is not None:
            args += ["-f", "after=" + after]
        ok, data = gh(args)
        if not ok or not isinstance(data, dict) or data.get("errors"):
            return None
        issue = ((data.get("data") or {}).get("repository") or {}).get("issue")
        if not isinstance(issue, dict) or not isinstance(issue.get("comments"), dict):
            return None
        if "issue" not in edits:
            edits["issue"] = _edit_list(issue, perms)
            if edits["issue"] is None:
                return None
        page = issue["comments"]
        if not isinstance(page.get("nodes"), list):
            return None
        for node in page["nodes"]:
            if not isinstance(node, dict) or type(node.get("databaseId")) is not int:
                return None
            got = _edit_list(node, perms)
            if got is None:
                return None
            edits[f"comment:{node['databaseId']}"] = got
        info = page.get("pageInfo")
        more = info.get("hasNextPage") if isinstance(info, dict) else None
        if more is False:
            return edits
        if more is not True:
            return None
        after = info.get("endCursor")
        if not isinstance(after, str):
            return None
    return None


def _dep_numbers(body, n):
    out = []
    for m in DEP_LINE.finditer(body or ""):
        for ref in DEP_REF.findall(m.group(1)):
            k = int(ref)
            if k != n and k not in out:
                out.append(k)
    return out


def read_issue(gh, repo, n, job, perms):
    """The snapshot of issue n for a job, or None when any read failed."""
    issue = _api(gh, f"repos/{repo}/issues/{n}")
    if issue is None:
        return None
    raw_events = _pages(gh, f"repos/{repo}/issues/{n}/events?per_page=100")
    if raw_events is None:
        return None
    raw_comments = _pages(gh, f"repos/{repo}/issues/{n}/comments?per_page=100")
    if raw_comments is None:
        return None
    comments = []
    for c in raw_comments:
        if not isinstance(c, dict) or type(c.get("id")) is not int or c["id"] < 0:
            return None
        login, typ = _who(c.get("user"))
        body = c.get("body")
        comments.append({"id": c["id"], "author": login, "author_type": typ, "created_at": c.get("created_at"),
                         "body": body if isinstance(body, str) else "", "trusted": perms.trusted(login, typ)})
    edits = _edits(gh, repo, n, perms)
    if edits is None:
        return None
    # A comment the GraphQL read did not list has edits that cannot be shown;
    # its editor is unknown, so the read fails (trust_and_untrusted_text L5).
    if any(f"comment:{c['id']}" not in edits for c in comments):
        return None
    closer = issue.get("closed_by")
    login, typ = _who(closer)
    snap = {"title": issue.get("title") if isinstance(issue.get("title"), str) else "",
            "body": issue.get("body") if isinstance(issue.get("body"), str) else "",
            "comments": comments,
            "state": issue.get("state"),
            "labels": [x.get("name") if isinstance(x, dict) else x for x in issue.get("labels") or []],
            "closed_by": {"login": login, "type": typ, "trusted": perms.trusted(login, typ)} if login else None,
            "events": _events(raw_events, perms),
            "edits": edits,
            "dependencies": {},
            "pr_merged": False}
    if isinstance(job, dict) and job.get("state") == "queued":
        for k in _dep_numbers(snap["body"], n):
            dep = _api(gh, f"repos/{repo}/issues/{k}")
            if dep is None:
                return None
            snap["dependencies"][str(k)] = dep.get("state")
    pr = job.get("pr") if isinstance(job, dict) else None
    if type(pr) is int and pr >= 1:
        data = _api(gh, f"repos/{repo}/pulls/{pr}")
        if data is None:
            return None
        snap["pr_merged"] = data.get("merged") is True or bool(data.get("merged_at"))
    return snap


def latest_label_event(events, label):
    """The last labeled event of label, in GitHub's order, or None."""
    found = None
    for e in events or []:
        if isinstance(e, dict) and e.get("event") == "labeled" and e.get("label") == label:
            found = e
    return found


def read_unjobbed(gh, repo, n, perms, settings=None):
    """What creation row 1 reads for issue n with no open job, or None. The
    open pulls come from perms, read once per sync. Each closing PR carries
    write: whether its author has write access or higher (row 1 condition
    5), which trustedPermission does not raise."""
    setting = _setting(settings)
    issue = _api(gh, f"repos/{repo}/issues/{n}")
    if issue is None:
        return None
    raw_events = _pages(gh, f"repos/{repo}/issues/{n}/events?per_page=100")
    if raw_events is None:
        return None
    pulls = perms.open_pulls()
    if pulls is None:
        return None
    ev = latest_label_event(_events(raw_events, perms), setting("flow.factory.label", "flow:factory"))
    label_event = None
    if ev is not None:
        label_event = {"id": ev["id"], "actor": ev["actor"], "actor_type": ev["actor_type"],
                       "created_at": ev["created_at"], "triage": perms.triage(ev["actor"], ev["actor_type"])}
    closes = re.compile(CLOSING % n)
    closing = []
    for p in pulls:
        if not isinstance(p, dict) or p.get("state", "open") != "open":
            continue
        if not closes.search(p.get("body") if isinstance(p.get("body"), str) else ""):
            continue
        head = p.get("head") if isinstance(p.get("head"), dict) else {}
        head_repo = (head.get("repo") or {}).get("full_name") if isinstance(head.get("repo"), dict) else None
        login, typ = _who(p.get("user"))
        closing.append({"number": p.get("number"), "head_ref": head.get("ref"),
                        "cross": not isinstance(head_repo, str) or head_repo.lower() != repo.lower(),
                        "author": login, "author_type": typ, "write": perms.write(login, typ)})
    return {"number": n, "state": issue.get("state"),
            "labels": [x.get("name") if isinstance(x, dict) else x for x in issue.get("labels") or []],
            "label_event": label_event, "closing_prs": closing}


def creation_conditions(unjobbed, local, settings=None):
    """T:creation row 1's six conditions over read_unjobbed's result."""
    if not isinstance(unjobbed, dict):
        return False
    setting = _setting(settings)
    local = local if isinstance(local, dict) else {}
    labels = unjobbed.get("labels") or []
    if unjobbed.get("state") != "open" or setting("flow.factory.label", "flow:factory") not in labels:
        return False
    ev = unjobbed.get("label_event")
    at = jobs.epoch(ev.get("created_at")) if isinstance(ev, dict) else None
    if at is None or ev.get("triage") is not True:
        return False
    if local.get("open_job"):
        return False
    terminal = local.get("terminal_vouch_at") or []
    for v in terminal:
        t = jobs.epoch(v)
        # A vouch_at that cannot be read may be at or after the label event.
        if t is None or t >= at:
            return False
    n = unjobbed.get("number")
    for p in unjobbed.get("closing_prs") or []:
        ref = p.get("head_ref")
        factory = p.get("cross") is False and isinstance(ref, str) and ref.startswith(f"feature/issue-{n}-")
        if not factory and p.get("write") is not False:
            return False
    in_progress = setting("flow.factory.labels.inProgress", "flow:in-progress")
    if in_progress in labels and not (local.get("open_job") or terminal):
        return False
    return True


# facts ---------------------------------------------------------------------
def _since(at, floor):
    """at is at or after floor. Fail closed: with no readable floor, or no
    readable time, the edit counts."""
    f, a = jobs.epoch(floor), jobs.epoch(at)
    return f is None or a is None or a >= f


def _after(at, floor):
    """at is strictly after floor; an unreadable time is not after; with no
    readable floor every readable time is."""
    a, f = jobs.epoch(at), jobs.epoch(floor)
    return a is not None and (f is None or a > f)


def _dict(v):
    return v if isinstance(v, dict) else {}


def needs_info_answers(snapshot, job):
    """The comment ids of trusted and of untrusted replies to the current
    needs-info round (text.is_reply_to: names one of its ids, created after
    its asked_at, not a marker or non-spec command). An untrusted reply a
    retry re-vouched is not waiting."""
    rnd = _dict(job).get("needs_info")
    if not isinstance(rnd, dict):
        return [], []
    revouched = _dict(_dict(job).get("revouched_replies"))
    trusted, untrusted = [], []
    for c in snapshot.get("comments") or []:
        if not text.is_reply_to(c, rnd):
            continue
        if c.get("trusted") is True:
            trusted.append(c["id"])
        elif str(c["id"]) not in revouched:
            untrusted.append(c["id"])
    return trusted, untrusted


def _untrusted_after(entries, floor):
    return any(_since(x.get("edited_at"), floor) and x.get("trusted") is not True for x in entries or [])


def untrusted_edit(snapshot, job):
    """T:facts.untrusted_edit: since vouch_at, a rename, a body edit or an
    edit of a spec-input comment by an editor that is not trusted (a deleted
    one included), or a re-vouched reply whose body no longer has the hash
    taken at the re-vouch."""
    job = _dict(job)
    floor = job.get("vouch_at")
    for e in snapshot.get("events") or []:
        if e.get("event") == "renamed" and _since(e.get("created_at"), floor) and e.get("trusted") is not True:
            return True
    edits = _dict(snapshot.get("edits"))
    if _untrusted_after(edits.get("issue"), floor):
        return True
    revouched = _dict(job.get("revouched_replies"))
    base = {"title": snapshot.get("title"), "body": snapshot.get("body"), "comments": snapshot.get("comments")}
    for item in text.spec_input_set(base, job.get("needs_info"), revouched):
        if item[0] == "comment" and _untrusted_after(edits.get(f"comment:{item[1]}"), floor):
            return True
    bodies = {c["id"]: c.get("body") for c in snapshot.get("comments") or []}
    for key, frozen in revouched.items():
        body = bodies.get(int(key)) if isinstance(key, str) and key.isdigit() else None
        if isinstance(body, str) and text.body_sha256(body) != frozen:
            return True
    return False


def cancel_signal(snapshot, job, label):
    """The latest removal of the queue label or close after vouch_at was made
    by a trusted actor."""
    floor = _dict(job).get("vouch_at")
    last = None
    for e in snapshot.get("events") or []:
        if (e.get("event") == "closed" or (e.get("event") == "unlabeled" and e.get("label") == label)) \
                and _after(e.get("created_at"), floor):
            last = e
    return last is not None and last.get("trusted") is True


def untrusted_close(snapshot):
    """Closed now, by a closer that is not trusted (or unknown), with the
    job's PR, if any, not merged."""
    closer = snapshot.get("closed_by")
    return (snapshot.get("state") == "closed" and not (isinstance(closer, dict) and closer.get("trusted") is True)
            and snapshot.get("pr_merged") is not True)


def dependency_open(snapshot, job):
    if _dict(job).get("state") != "queued":
        return False
    return any(s == "open" for s in _dict(snapshot.get("dependencies")).values())


def facts(snapshot, job, settings=None):
    setting = _setting(settings)
    trusted, untrusted = needs_info_answers(snapshot, job)
    return {"untrusted_edit": untrusted_edit(snapshot, job),
            "needs_info_answer": bool(trusted),
            "untrusted_needs_info_answer": bool(untrusted),
            "cancel_signal": cancel_signal(snapshot, job, setting("flow.factory.label", "flow:factory")),
            "untrusted_close": untrusted_close(snapshot),
            "dependency_open": dependency_open(snapshot, job)}
