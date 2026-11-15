"""A stand-in for gh against one sandbox repository, for the factory's GitHub
write probe scenarios. It keeps the pull requests, reviews, issue comments and
workflow runs it is told about in gh-state.json beside itself, so a review or
comment posted through it can be listed again, as GitHub would.

It answers only the calls the probe makes, each naming the repository:
  gh --version
  gh auth status
  gh repo view <repo> --json ...
  gh pr create --draft --repo <repo> --head <branch> --base <branch> ...
  gh pr ready <n> [--undo] --repo <repo>
  gh api --include --method POST repos/<repo>/pulls/<n>/reviews -f event=E -f body=B
  gh api --include --method POST repos/<repo>/issues/<n>/comments -f body=B
  gh api repos/<repo>/pulls/<n>/reviews?per_page=100
  gh api repos/<repo>/issues/<n>/comments?per_page=100
  gh api repos/<repo>/actions/runs?branch=<b>&per_page=100
Any other call is logged to gh-unhandled.log and exits 99. Every call but
--version is logged to gh-calls.jsonl.

gh-config.json beside it (every key optional):
  repo                  the sandbox's owner/repo (default probe-fixture/sandbox)
  default_branch        (default main)
  association           author_association of what is posted (default OWNER)
  auth_fails            gh auth status exits 1
  repo_view_fails       gh repo view exits 1, as for a repository not found
  pr_number             the number pr create gives (default 7)
  status_COMMENT, status_APPROVE, status_REQUEST_CHANGES
                        the HTTP status of each review event (defaults 200,
                        422, 422); a review is stored only on a 2xx
  message_APPROVE, message_REQUEST_CHANGES
                        GitHub's message for an answer other than 2xx or
                        422 (default error)
  errors_APPROVE, errors_REQUEST_CHANGES
                        the errors list of a 422 (default GitHub's refusal of
                        a review of one's own pull request); null leaves the
                        list out
  status_comment        the HTTP status of an issue comment (default 201)
  lookup_loses          the GET lists return no items
  list_fails            the GET lists exit 1 with GitHub's 502, as gh does
                        when the list call fails
  no_answer             a list of argument prefixes ("pr ready", "api
                        --include --method POST"): a call that starts with
                        one gets no answer, it sleeps as gh does waiting on a
                        network that never answers
  ready_fails           gh pr ready (and --undo) exits 1
  ready_starts_run      gh pr ready adds a queued workflow run
  undo_cancels          gh pr ready --undo marks queued runs cancelled
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REASONS = {200: "OK", 201: "Created", 403: "Forbidden", 404: "Not Found", 422: "Unprocessable Entity",
           502: "Bad Gateway"}

# GitHub's text for a review of one's own pull request.
OWN_PR_ERRORS = {"APPROVE": "Can not approve your own pull request",
                 "REQUEST_CHANGES": "Can not request changes on your own pull request"}


def load(name, default):
    try:
        with open(os.path.join(HERE, name), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def save_state(state):
    with open(os.path.join(HERE, "gh-state.json"), "w", encoding="utf-8") as f:
        json.dump(state, f)


def unhandled(args):
    with open(os.path.join(HERE, "gh-unhandled.log"), "a", encoding="utf-8") as f:
        f.write(" ".join(args) + "\n")
    print(f"gh stand-in: unhandled call: {' '.join(args)}", file=sys.stderr)
    return 99


def http(status, body):
    """gh api --include: the status line and headers, a blank line, the body;
    on an error status gh also prints its message and exits 1."""
    text = json.dumps(body)
    sys.stdout.write(f"HTTP/2.0 {status} {REASONS.get(status, 'Status')}\r\nContent-Type: application/json\r\n\r\n{text}")
    if status >= 400:
        print(f"gh: {body.get('message', 'error')} (HTTP {status})", file=sys.stderr)
        return 1
    return 0


def fields(args):
    out = {}
    for i, a in enumerate(args):
        if a in ("-f", "--raw-field", "-F", "--field") and i + 1 < len(args):
            k, _, v = args[i + 1].partition("=")
            out[k] = v
    return out


def option(args, name):
    return args[args.index(name) + 1] if name in args and args.index(name) + 1 < len(args) else None


def main(args):
    if args[:1] == ["--version"]:
        print("gh version 2.80.0 (2026-10-01)\nhttps://github.com/cli/cli/releases/tag/v2.80.0")
        return 0
    with open(os.path.join(HERE, "gh-calls.jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps(args) + "\n")
    cfg = load("gh-config.json", {})
    repo = cfg.get("repo", "probe-fixture/sandbox")
    assoc = cfg.get("association", "OWNER")
    state = load("gh-state.json", {"next_id": 1, "reviews": [], "comments": [], "runs": [], "prs": []})
    words = [a for a in args if not a.startswith("-")]
    for prefix in cfg.get("no_answer") or []:
        if args[:len(prefix.split())] == prefix.split():
            sys.stdout.flush()
            os.execvp("sleep", ["sleep", "600"])

    if args[:2] == ["auth", "status"]:
        if cfg.get("auth_fails"):
            print("You are not logged into any GitHub hosts. To log in, run: gh auth login", file=sys.stderr)
            return 1
        print("github.com\n  Logged in to github.com account probe-owner (keyring)")
        return 0
    if args[:2] == ["repo", "view"] and len(args) > 2:
        if args[2] != repo or cfg.get("repo_view_fails"):
            print(f"GraphQL: Could not resolve to a Repository with the name '{args[2]}'. (repository)",
                  file=sys.stderr)
            return 1
        print(json.dumps({"nameWithOwner": repo, "defaultBranchRef": {"name": cfg.get("default_branch", "main")},
                          "url": f"https://github.com/{repo}", "visibility": "PUBLIC"}))
        return 0
    if args[:2] == ["pr", "create"] and option(args, "--repo") == repo and "--draft" in args:
        n = cfg.get("pr_number", 7)
        state["prs"].append({"number": n, "head": option(args, "--head"), "base": option(args, "--base"),
                             "draft": True})
        save_state(state)
        print(f"https://github.com/{repo}/pull/{n}")
        return 0
    if args[:2] == ["pr", "ready"] and option(args, "--repo") == repo:
        if cfg.get("ready_fails"):
            print("GraphQL: Resource not accessible (markPullRequestReadyForReview)", file=sys.stderr)
            return 1
        if "--undo" in args:
            if cfg.get("undo_cancels"):
                for r in state["runs"]:
                    if r["status"] == "queued":
                        r.update(status="completed", conclusion="cancelled")
        elif cfg.get("ready_starts_run"):
            state["runs"].append({"id": 9000 + len(state["runs"]), "event": "pull_request", "status": "queued",
                                  "conclusion": None})
        save_state(state)
        print(f"✓ Pull request {repo}#{args[2]} is {'converted to draft' if '--undo' in args else 'marked as ready'}")
        return 0
    if args[:1] == ["api"]:
        endpoint = next((w for w in words[1:] if w.startswith("repos/")), "")
        method = (option(args, "--method") or "GET").upper()
        m = re.fullmatch(rf"repos/{re.escape(repo)}/(pulls|issues)/(\d+)/(reviews|comments)(\?per_page=100)?",
                         endpoint)
        if m and method == "POST" and "--include" in args and not m.group(4):
            kind, f = m.group(1, 3), fields(args)
            if kind == ("pulls", "reviews"):
                event = f.get("event", "")
                status = cfg.get(f"status_{event}", 200 if event == "COMMENT" else 422)
                if 200 <= status < 300:
                    item = {"id": state["next_id"], "body": f.get("body", ""), "state": event,
                            "author_association": assoc, "user": {"login": "probe-owner"}}
                    state["next_id"] += 1
                    state["reviews"].append(item)
                    save_state(state)
                    return http(status, item)
                if status != 422:
                    return http(status, {"message": cfg.get(f"message_{event}", "error")})
                body = {"message": "Unprocessable Entity"}
                errors = cfg.get(f"errors_{event}", [OWN_PR_ERRORS.get(event, "error")])
                if errors is not None:
                    body["errors"] = errors
                return http(status, body)
            if kind == ("issues", "comments"):
                status = cfg.get("status_comment", 201)
                if 200 <= status < 300:
                    item = {"id": state["next_id"], "body": f.get("body", ""), "author_association": assoc,
                            "user": {"login": "probe-owner"}}
                    state["next_id"] += 1
                    state["comments"].append(item)
                    save_state(state)
                    return http(status, item)
                return http(status, {"message": "Validation Failed"})
        if m and method == "GET" and m.group(4):
            if cfg.get("list_fails"):
                print("gh: Bad Gateway (HTTP 502)", file=sys.stderr)
                return 1
            if cfg.get("lookup_loses"):
                print("[]")
                return 0
            print(json.dumps(state["reviews"] if m.group(1, 3) == ("pulls", "reviews") else state["comments"]))
            return 0
        if re.fullmatch(rf"repos/{re.escape(repo)}/actions/runs\?branch=[^&]+&per_page=100", endpoint) \
                and method == "GET":
            print(json.dumps({"total_count": len(state["runs"]), "workflow_runs": state["runs"]}))
            return 0
    return unhandled(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
