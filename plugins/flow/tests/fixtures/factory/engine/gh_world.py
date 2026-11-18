"""The stateful half of the factory gh stub (engine/gh beside it).

engine/gh runs this file, with the interpreter named in fe-gh-python beside
it and -I, when FE_WORLD names a world file and no fe-gh fixture answers the
call first:

    <python> -I gh_world.py <world file> <gh arguments...>

It answers from the world file and writes the file back after every write,
so what the engine posts can be listed again, as GitHub would. The world is
one JSON object (tests/lib/factory-e2e.sh writes it with the fe_world_*
helpers):

  engine_login    the login `gh api user` names, type User
  actor_types     {login: "User" | "Bot"}: the type every actor and author of
                  that login is given in an answer (default: the stored type,
                  else User)
  repo            "owner/name"; every repos/... path must name it (else 404)
  default_branch  default "main"
  issues          {"<n>": {state, state_reason, title, body, labels: [name],
                  assignees: [login], author, created_at, updated_at,
                  closed_by: {login, type} | null}}
  events          {"<n>": [{id, event, label, actor: {login, type} | null,
                  created_at, rename: {from, to}}]}; label is a name, rename
                  only on a renamed event
  comments        {"<n>": [{id, author: {login, type}, created_at,
                  updated_at, body}]}, in id order
  edits           {"issue:<n>" | "comment:<id>": [{editor: login | null,
                  edited_at, diff}]}, newest first
  permissions     {login: {role_name, permission} | {status: <http code>}}
  pulls           [{number, head_ref, body, state, author, isCrossRepository,
                  merged, head_sha}]; the last two optional
  next_id         the id the next posted comment gets (raised past every
                  comment id the world holds)
  now             optional: the time every write is stamped with, in place
                  of the clock
  knobs           {die_after_post, list_fails: [path prefix],
                  permission_fails: [login], post_fails}
  posts           every write received, in order: {method, path, fields,
                  body}

Reads (GET unless said; a GET path that starts with a list_fails prefix
exits 1 with GitHub's 502, `user` and `graphql` included):
  api user                                     {login, type}
  api repos/O/R                                {full_name, name, owner, default_branch}
  api repos/O/R/issues?labels=&state=          open by default; every label named
  api repos/O/R/issues/N                       the issue, 404 when there is none
  api repos/O/R/issues/N/events | /timeline    the issue's events
  api repos/O/R/issues/N/comments              the issue's comments
  api repos/O/R/issues/comments/ID             one comment
  api repos/O/R/collaborators/L/permission     {permission, role_name, user};
                                               a login with no entry is 404, a
                                               {status} entry answers that
                                               status, a permission_fails login 502
  api repos/O/R/pulls?state=                   open by default
  api repos/O/R/pulls/N                        one pull request
  api graphql -f query=... -F number=N         the edit fields of issue N and of
                                               its comments (shape in graphql())
Every list read takes per_page (default 30, at most 100) and page (default
1). --include prints the status line and headers first, with a Link header
naming the next and last pages when there are more. --paginate reads every
page from the one asked for; with --slurp it prints one outer array of the
pages, as gh 2.101.0 does, and without it the pages one after another.

Writes (each appended to posts; post_fails answers 502 and stores nothing;
die_after_post stores, saves and answers, then exits 86, on which engine/gh
kills its own parent):
  api --method POST   repos/O/R/issues/N/comments  -F body=@file | -f body=text
  api --method PATCH  repos/O/R/issues/comments/ID -F body=@file | -f body=text
  api --method POST   repos/O/R/issues/N/labels    -f labels[]=X ...
  api --method DELETE repos/O/R/issues/N/labels/X  (X may be percent-encoded)
  api --method POST   repos/O/R/issues/N/assignees -f assignees[]=L ...
  api --method PATCH  repos/O/R/pulls/N            -f state=closed
  issue edit N --repo O/R [--add-assignee L] [--add-label X] [--remove-label X]
               [--remove-assignee L]
As gh does, a call with fields and no --method is a POST.

Any other call is appended to fe-gh-unhandled.log beside this file and exits
99, as the stub does without a world.
"""
import fcntl
import json
import os
import re
import sys
import time
from urllib.parse import parse_qs, quote, unquote, urlsplit

HERE = os.path.dirname(os.path.abspath(__file__))
KILL_PARENT = 86
REASONS = {200: "OK", 201: "Created", 204: "No Content", 403: "Forbidden", 404: "Not Found",
           410: "Gone", 422: "Unprocessable Entity", 500: "Internal Server Error", 502: "Bad Gateway",
           503: "Service Unavailable"}


class Answer(Exception):
    """The call's answer: an HTTP status and a JSON body, or a plain exit."""

    def __init__(self, status, body):
        super().__init__(status)
        self.status = status
        self.body = body


def unhandled(args, why=""):
    with open(os.path.join(HERE, "fe-gh-unhandled.log"), "a", encoding="utf-8") as f:
        f.write(" ".join(args) + "\n")
    print(f"factory gh world: unhandled call{': ' + why if why else ''}: gh {' '.join(args)}", file=sys.stderr)
    return 99


def now(world):
    return world.get("now") or time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def actor(world, who):
    """{login, type} for a stored actor (a login or {login, type}), or None."""
    if who is None:
        return None
    if isinstance(who, str):
        login, stored = who, None
    else:
        login, stored = who.get("login"), who.get("type")
    return {"login": login, "type": (world.get("actor_types") or {}).get(login) or stored or "User"}


def issue_out(world, n, d):
    return {"number": int(n), "title": d.get("title", ""), "body": d.get("body", ""),
            "state": d.get("state", "open"), "state_reason": d.get("state_reason"),
            "labels": [{"name": x} for x in d.get("labels", [])],
            "assignees": [actor(world, a) for a in d.get("assignees", [])],
            "user": actor(world, d.get("author")), "created_at": d.get("created_at"),
            "updated_at": d.get("updated_at"), "closed_by": actor(world, d.get("closed_by")),
            "html_url": f"https://github.com/{world['repo']}/issues/{n}"}


def event_out(world, e):
    out = {"id": e.get("id"), "event": e.get("event"), "actor": actor(world, e.get("actor")),
           "created_at": e.get("created_at")}
    if e.get("label") is not None:
        out["label"] = {"name": e["label"]}
    if "rename" in e:
        out["rename"] = e["rename"]
    return out


def comment_out(world, n, c):
    return {"id": c["id"], "user": actor(world, c.get("author")), "created_at": c.get("created_at"),
            "updated_at": c.get("updated_at"), "body": c.get("body", ""),
            "html_url": f"https://github.com/{world['repo']}/issues/{n}#issuecomment-{c['id']}"}


def pull_out(world, p):
    head_repo = "outside-fork/" + world["repo"].split("/")[1] if p.get("isCrossRepository") else world["repo"]
    return {"number": p["number"], "state": p.get("state", "open"), "body": p.get("body", ""),
            "user": actor(world, p.get("author")),
            "head": {"ref": p.get("head_ref"), "sha": p.get("head_sha"), "repo": {"full_name": head_repo}},
            "base": {"ref": world.get("default_branch", "main"), "repo": {"full_name": world["repo"]}},
            "merged": p.get("merged") is True, "merged_at": "2026-11-16T00:00:00Z" if p.get("merged") else None}


def edits_out(world, key):
    nodes = [{"editor": None if e.get("editor") is None else
              {"login": e["editor"], "__typename": actor(world, e["editor"])["type"]},
              "editedAt": e.get("edited_at"), "diff": e.get("diff", "")}
             for e in (world.get("edits") or {}).get(key, [])]
    return {"lastEditedAt": nodes[0]["editedAt"] if nodes else None,
            "editor": nodes[0]["editor"] if nodes else None,
            "userContentEdits": {"nodes": nodes, "pageInfo": {"hasNextPage": False, "endCursor": None}}}


def graphql(world, fields):
    """{"data": {"repository": {"issue": {lastEditedAt, editor, userContentEdits,
    comments: {nodes: [{databaseId, lastEditedAt, editor, userContentEdits}],
    pageInfo}}}}} for the issue the number variable (or `number: N` in the
    query) names. An editor is {login, __typename} or null; a node list is
    newest first and never has a next page."""
    number = fields.get("number")
    if number is None:
        m = re.search(r"number:\s*(\d+)", str(fields.get("query", "")))
        number = m.group(1) if m else None
    owner, name = fields.get("owner"), fields.get("name")
    if owner is not None and name is not None and f"{owner}/{name}" != world["repo"]:
        raise Answer(200, {"data": {"repository": None},
                           "errors": [{"type": "NOT_FOUND", "message": "Could not resolve to a Repository"}]})
    if number is None or str(number) not in world.get("issues", {}):
        raise Answer(200, {"data": {"repository": {"issue": None}},
                           "errors": [{"type": "NOT_FOUND", "message": "Could not resolve to an Issue"}]})
    n = str(number)
    issue = edits_out(world, f"issue:{n}")
    nodes = []
    for c in world.get("comments", {}).get(n, []):
        node = {"databaseId": c["id"]}
        node.update(edits_out(world, f"comment:{c['id']}"))
        nodes.append(node)
    issue["comments"] = {"nodes": nodes, "pageInfo": {"hasNextPage": False, "endCursor": None}}
    return {"data": {"repository": {"issue": issue}}}


# arguments -------------------------------------------------------------------
def parse_api(args):
    """(endpoint, method or None, fields, raw fields, flags) of `gh api ...`."""
    endpoint, method, fields, raw, flags = None, None, {}, {}, set()
    i = 1
    while i < len(args):
        a = args[i]
        if a in ("--paginate", "--slurp", "--include", "-i", "--silent", "--verbose"):
            flags.add({"-i": "--include"}.get(a, a))
        elif a in ("-X", "--method"):
            i += 1
            method = args[i].upper()
        elif a.startswith("--method="):
            method = a.split("=", 1)[1].upper()
        elif a in ("-f", "--raw-field", "-F", "--field"):
            i += 1
            k, _, v = args[i].partition("=")
            raw.setdefault(k, []).append(v)
            val = v
            if a in ("-F", "--field"):
                val = typed(v)
            if k.endswith("[]"):
                fields.setdefault(k[:-2], []).append(val)
            else:
                fields[k] = val
        elif a in ("-H", "--header", "--hostname", "-p", "--preview", "--cache"):
            i += 1
        elif a in ("--input",):
            i += 1
            src = sys.stdin.read() if args[i] == "-" else open(args[i], encoding="utf-8").read()
            try:
                fields.update(json.loads(src))
            except ValueError:
                raise Answer(400, {"message": "Problems parsing JSON"})
            raw["--input"] = [args[i]]
        elif a.startswith("-"):
            raise ValueError(f"option {a}")
        elif endpoint is None:
            endpoint = a
        else:
            raise ValueError(f"second endpoint {a}")
        i += 1
    if endpoint is None:
        raise ValueError("no endpoint")
    return endpoint.lstrip("/"), method, fields, raw, flags


def typed(v):
    """A -F value as gh sends it: @file (or @- for stdin) as the file's text,
    true, false, null and integers as JSON, anything else as a string."""
    if v.startswith("@"):
        src = v[1:]
        if src == "-":
            return sys.stdin.read()
        with open(src, encoding="utf-8") as f:
            return f.read()
    if v in ("true", "false", "null"):
        return json.loads(v)
    if re.fullmatch(r"-?[0-9]+", v):
        return int(v)
    return v


def flat(raw):
    """The fields as written on the command line: one value, or a list for a
    repeated or [] key."""
    return {k: (v if k.endswith("[]") or len(v) > 1 else v[0]) for k, v in raw.items()}


# answers ---------------------------------------------------------------------
def emit(status, body, flags, headers=None):
    """Print one answer as gh api does; return gh's exit status."""
    if "--include" in flags:
        sys.stdout.write(f"HTTP/2.0 {status} {REASONS.get(status, 'Status')}\r\n")
        sys.stdout.write("Content-Type: application/json; charset=utf-8\r\n")
        for k, v in (headers or {}).items():
            sys.stdout.write(f"{k}: {v}\r\n")
        sys.stdout.write("\r\n")
    if body is not None and "--silent" not in flags:
        sys.stdout.write(json.dumps(body, ensure_ascii=False))
        if "--include" not in flags:
            sys.stdout.write("\n")
    if status >= 400:
        msg = body.get("message", "error") if isinstance(body, dict) else "error"
        print(f"gh: {msg} (HTTP {status})", file=sys.stderr)
        return 1
    return 0


def page_of(items, query, page):
    per = query.get("per_page", ["30"])[0]
    per = max(1, min(100, int(per))) if per.isdigit() else 30
    last = max(1, -(-len(items) // per))
    return items[(page - 1) * per:page * per], per, last


def link(path, query, per, page, last):
    def url(p):
        q = {k: v[0] for k, v in query.items()}
        q.update(per_page=str(per), page=str(p))
        return "<https://api.github.com/%s?%s>" % (path, "&".join(f"{k}={quote(v, safe=':,')}" for k, v in q.items()))
    rels = []
    if page < last:
        rels += [f'{url(page + 1)}; rel="next"', f'{url(last)}; rel="last"']
    if page > 1:
        rels += [f'{url(1)}; rel="first"', f'{url(page - 1)}; rel="prev"']
    return ", ".join(rels)


def listing(items, path, query, flags):
    page = query.get("page", ["1"])[0]
    page = int(page) if page.isdigit() and int(page) > 0 else 1
    if "--paginate" not in flags:
        chunk, per, last = page_of(items, query, page)
        lk = link(path, query, per, page, last)
        return emit(200, chunk, flags, {"Link": lk} if lk else None)
    pages = []
    while True:
        chunk, per, last = page_of(items, query, page)
        pages.append((chunk, link(path, query, per, page, last)))
        if page >= last:
            break
        page += 1
    if "--slurp" in flags:
        return emit(200, [c for c, _ in pages], flags)
    rc = 0
    for chunk, lk in pages:
        rc = emit(200, chunk, flags, {"Link": lk} if lk else None) or rc
    return rc


def need_issue(world, n):
    d = world.get("issues", {}).get(n)
    if d is None:
        raise Answer(404, {"message": "Not Found"})
    return d


def read(world, path, query, fields, flags):
    """Answer a read; return the exit status."""
    repo = world["repo"]
    knobs = world.get("knobs") or {}
    if any(path.startswith(p) for p in knobs.get("list_fails") or []):
        raise Answer(502, {"message": "Bad Gateway"})
    if path == "user":
        return emit(200, {"login": world.get("engine_login", "flow-e2e-engine"), "type": "User"}, flags)
    if path == "graphql":
        out = graphql(world, fields)
        return emit(200, out, flags)
    m = re.fullmatch(r"repos/([^/]+/[^/]+)(/.*)?", path)
    if not m:
        return None
    if m.group(1) != repo:
        raise Answer(404, {"message": "Not Found"})
    rest = m.group(2) or ""
    if rest == "":
        owner, name = repo.split("/")
        return emit(200, {"full_name": repo, "name": name, "owner": {"login": owner},
                          "default_branch": world.get("default_branch", "main")}, flags)
    if rest == "/issues":
        state = query.get("state", ["open"])[0]
        want = [x for x in query.get("labels", [""])[0].split(",") if x]
        items = [issue_out(world, n, d) for n, d in sorted(world.get("issues", {}).items(), key=lambda kv: -int(kv[0]))
                 if (state == "all" or d.get("state", "open") == state)
                 and all(x in d.get("labels", []) for x in want)]
        return listing(items, path, query, flags)
    m2 = re.fullmatch(r"/issues/(\d+)", rest)
    if m2:
        return emit(200, issue_out(world, m2.group(1), need_issue(world, m2.group(1))), flags)
    m2 = re.fullmatch(r"/issues/(\d+)/(events|timeline)", rest)
    if m2:
        need_issue(world, m2.group(1))
        items = [event_out(world, e) for e in world.get("events", {}).get(m2.group(1), [])]
        return listing(items, path, query, flags)
    m2 = re.fullmatch(r"/issues/(\d+)/comments", rest)
    if m2:
        need_issue(world, m2.group(1))
        items = [comment_out(world, m2.group(1), c) for c in world.get("comments", {}).get(m2.group(1), [])]
        return listing(items, path, query, flags)
    m2 = re.fullmatch(r"/issues/comments/(\d+)", rest)
    if m2:
        n, c = find_comment(world, int(m2.group(1)))
        return emit(200, comment_out(world, n, c), flags)
    m2 = re.fullmatch(r"/collaborators/([^/]+)/permission", rest)
    if m2:
        login = unquote(m2.group(1))
        if login in (knobs.get("permission_fails") or []):
            raise Answer(502, {"message": "Bad Gateway"})
        p = (world.get("permissions") or {}).get(login)
        if p is None:
            raise Answer(404, {"message": "Not Found"})
        if "status" in p:
            raise Answer(int(p["status"]), {"message": REASONS.get(int(p["status"]), "error")})
        out = {k: p[k] for k in ("permission", "role_name") if k in p}
        out["user"] = actor(world, login)
        return emit(200, out, flags)
    if rest == "/pulls":
        state = query.get("state", ["open"])[0]
        items = [pull_out(world, p) for p in world.get("pulls", [])
                 if state == "all" or p.get("state", "open") == state]
        return listing(items, path, query, flags)
    m2 = re.fullmatch(r"/pulls/(\d+)", rest)
    if m2:
        return emit(200, pull_out(world, need_pull(world, int(m2.group(1)))), flags)
    return None


def find_comment(world, cid):
    for n, cs in (world.get("comments") or {}).items():
        for c in cs:
            if c["id"] == cid:
                return n, c
    raise Answer(404, {"message": "Not Found"})


def need_pull(world, number):
    for p in world.get("pulls", []):
        if p["number"] == number:
            return p
    raise Answer(404, {"message": "Not Found"})


def text_field(fields, name):
    v = fields.get(name)
    if not isinstance(v, str):
        raise Answer(422, {"message": f"Invalid request: {name} is required"})
    return v


def as_list(v):
    return v if isinstance(v, list) else [] if v is None else [v]


def write(world, method, path, fields):
    """Store one write; return (status, answer body, posts body) or None when
    the path is not a write this stand-in knows."""
    repo = world["repo"]
    m = re.fullmatch(r"repos/([^/]+/[^/]+)(/.*)", path)
    if not m:
        return None
    if m.group(1) != repo:
        raise Answer(404, {"message": "Not Found"})
    rest, at = m.group(2), now(world)
    m2 = re.fullmatch(r"/issues/(\d+)/comments", rest)
    if m2 and method == "POST":
        n = m2.group(1)
        need_issue(world, n)
        body = text_field(fields, "body")
        ids = [c["id"] for cs in (world.get("comments") or {}).values() for c in cs]
        cid = max([int(world.get("next_id") or 1)] + [i + 1 for i in ids])
        world["next_id"] = cid + 1
        c = {"id": cid, "author": {"login": world.get("engine_login", "flow-e2e-engine"), "type": "User"},
             "created_at": at, "updated_at": at, "body": body}
        world.setdefault("comments", {}).setdefault(n, []).append(c)
        return 201, comment_out(world, n, c), body
    m2 = re.fullmatch(r"/issues/comments/(\d+)", rest)
    if m2 and method == "PATCH":
        n, c = find_comment(world, int(m2.group(1)))
        body = text_field(fields, "body")
        c["body"], c["updated_at"] = body, at
        return 200, comment_out(world, n, c), body
    m2 = re.fullmatch(r"/issues/(\d+)/labels", rest)
    if m2 and method == "POST":
        d = need_issue(world, m2.group(1))
        for x in as_list(fields.get("labels")):
            if x not in d.setdefault("labels", []):
                d["labels"].append(x)
        d["updated_at"] = at
        return 200, [{"name": x} for x in d["labels"]], None
    m2 = re.fullmatch(r"/issues/(\d+)/labels/(.+)", rest)
    if m2 and method == "DELETE":
        d = need_issue(world, m2.group(1))
        name = unquote(m2.group(2))
        if name not in d.get("labels", []):
            raise Answer(404, {"message": "Label does not exist"})
        d["labels"].remove(name)
        d["updated_at"] = at
        return 200, [{"name": x} for x in d["labels"]], None
    m2 = re.fullmatch(r"/issues/(\d+)/assignees", rest)
    if m2 and method == "POST":
        d = need_issue(world, m2.group(1))
        for x in as_list(fields.get("assignees")):
            if x not in d.setdefault("assignees", []):
                d["assignees"].append(x)
        d["updated_at"] = at
        return 201, issue_out(world, m2.group(1), d), None
    m2 = re.fullmatch(r"/pulls/(\d+)", rest)
    if m2 and method == "PATCH":
        p = need_pull(world, int(m2.group(1)))
        if "state" in fields:
            p["state"] = fields["state"]
        if "body" in fields:
            p["body"] = fields["body"]
        return 200, pull_out(world, p), fields.get("body")
    return None


def issue_edit(world, args):
    """gh issue edit N --repo O/R with add and remove flags: (path, fields)."""
    n, repo, fields = None, None, {}
    i = 2
    while i < len(args):
        a = args[i]
        if a in ("--repo", "-R"):
            i += 1
            repo = args[i]
        elif a in ("--add-assignee", "--add-label", "--remove-label", "--remove-assignee"):
            i += 1
            fields.setdefault(a[2:], []).extend(x for x in args[i].split(",") if x)
        elif a.startswith("-"):
            raise ValueError(f"option {a}")
        elif n is None and a.isdigit():
            n = a
        else:
            raise ValueError(f"argument {a}")
        i += 1
    if n is None or repo is None:
        raise ValueError("issue edit needs a number and --repo")
    if repo != world["repo"]:
        raise Answer(404, {"message": "Could not resolve to a Repository"})
    return n, fields


def apply_issue_edit(world, n, fields):
    d = need_issue(world, n)
    for x in fields.get("add-assignee", []):
        if x not in d.setdefault("assignees", []):
            d["assignees"].append(x)
    for x in fields.get("remove-assignee", []):
        if x in d.get("assignees", []):
            d["assignees"].remove(x)
    for x in fields.get("add-label", []):
        if x not in d.setdefault("labels", []):
            d["labels"].append(x)
    for x in fields.get("remove-label", []):
        if x in d.get("labels", []):
            d["labels"].remove(x)
    d["updated_at"] = now(world)


def save(path, world):
    tmp = f"{path}.t{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(world, f, indent=1, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)


def main(world_path, args):
    with open(world_path + ".lock", "a", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with open(world_path, encoding="utf-8") as f:
            world = json.load(f)
        knobs = world.get("knobs") or {}
        try:
            if args[:2] == ["issue", "edit"]:
                n, fields = issue_edit(world, args)
                if knobs.get("post_fails"):
                    print("HTTP 502: Bad Gateway (https://api.github.com/graphql)", file=sys.stderr)
                    return 1
                apply_issue_edit(world, n, fields)
                world.setdefault("posts", []).append({"method": "issue edit", "path": f"repos/{world['repo']}/issues/{n}",
                                                      "fields": fields, "body": None})
                save(world_path, world)
                print(f"https://github.com/{world['repo']}/issues/{n}")
                return KILL_PARENT if knobs.get("die_after_post") else 0
            if args[:1] != ["api"]:
                return unhandled(args)
            endpoint, method, fields, raw, flags = parse_api(args)
            parts = urlsplit(endpoint)
            path, query = parts.path, parse_qs(parts.query)
            if method is None:
                method = "POST" if fields and path != "graphql" else "GET"
            if method == "GET" and path != "graphql":
                # gh sends the fields of a GET as query parameters.
                for k, v in fields.items():
                    query.setdefault(k, [str(x) for x in as_list(v)])
            if method == "GET" or path == "graphql":
                rc = read(world, path, query, fields, flags)
                return unhandled(args) if rc is None else rc
            if knobs.get("post_fails"):
                raise Answer(502, {"message": "Bad Gateway"})
            done = write(world, method, path, fields)
            if done is None:
                return unhandled(args)
            status, body, text = done
            world.setdefault("posts", []).append({"method": method, "path": path, "fields": flat(raw),
                                                  "body": text})
            save(world_path, world)
            rc = emit(status, body, flags)
            sys.stdout.flush()
            return KILL_PARENT if knobs.get("die_after_post") else rc
        except Answer as a:
            rc = emit(a.status, a.body, flags if "flags" in locals() else set())
            if isinstance(a.body, dict) and a.body.get("errors") and a.status < 400:
                # gh api graphql exits 1 when GitHub answers with errors.
                print("gh: " + a.body["errors"][0]["message"], file=sys.stderr)
                return 1
            return rc
        except OSError as e:
            print(f"factory gh world: {e}", file=sys.stderr)
            return 1
        except (ValueError, IndexError) as e:
            return unhandled(args, str(e))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: gh_world.py <world file> <gh arguments...>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2:]))
