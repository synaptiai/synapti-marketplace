"""Every bypass the two reviewers constructed against the merge gate.

The stub logs its argv, so an assertion can say WHICH pull request was probed —
the discriminating input the first test suite could not see, because its stub
matched on "$1 $2" and ignored everything after.
"""
import json
import os
import subprocess
import sys
import tempfile

HOOK = sys.argv[1]
# One directory for every stub, removed when the run ends. A mkdtemp per case
# left dozens behind on every run.
_ROOT = tempfile.TemporaryDirectory(prefix="flow-bum-matrix.")

GREEN = {"number": 7, "baseRefName": "main", "statusCheckRollup": [
    {"__typename": "CheckRun", "name": "test", "status": "COMPLETED", "conclusion": "SUCCESS"}]}
QUEUED = {"number": 9, "baseRefName": "main", "statusCheckRollup": [
    {"__typename": "CheckRun", "name": "build", "status": "QUEUED", "conclusion": None}]}
ACTION_REQ = {"number": 7, "baseRefName": "main", "statusCheckRollup": [
    {"__typename": "CheckRun", "name": "sign", "status": "COMPLETED", "conclusion": "ACTION_REQUIRED"}]}
STALE = {"number": 7, "baseRefName": "main", "statusCheckRollup": [
    {"__typename": "CheckRun", "name": "old", "status": "COMPLETED", "conclusion": "STALE"}]}
NOTYPE = {"number": 7, "baseRefName": "main", "statusCheckRollup": [
    {"name": "mystery", "status": "COMPLETED", "conclusion": "SUCCESS"}]}
EMPTY = {"number": 7, "baseRefName": "main", "statusCheckRollup": []}


def stub(default, by_selector=None, prot=None, rules=None, gh_rc=0, raw=None):
    d = tempfile.mkdtemp(dir=_ROOT.name)
    json.dump({"default": default, "by_selector": by_selector or {}}, open(d + "/data.json", "w"))
    open(d + "/prot.json", "w").write(json.dumps(prot) if prot else "")
    open(d + "/rules.json", "w").write(json.dumps(rules) if rules else "")
    open(d + "/rc", "w").write(str(gh_rc))
    open(d + "/raw", "w").write(raw or "")
    open(d + "/gh", "w").write(f'''#!/usr/bin/env bash
D="{d}"
printf '%s\\n' "${{GH_HOST:+[host=$GH_HOST] }}$*" >> "$D/calls.log"
if [ "$1 $2" = "repo view" ]; then echo "acme/widgets"; exit 0; fi
if [ "$1 $2" = "pr view" ]; then
  rc=$(cat "$D/rc")
  if [ -s "$D/raw" ]; then cat "$D/raw"; exit "$rc"; fi
  sel=""
  for a in "$@"; do
    case "$a" in pr|view|--repo|--json|-R) continue ;; --*) continue ;; esac
    case "$a" in number,*) continue ;; esac
    case "$a" in http*://*) : ;; */*) continue ;; esac
    [ -z "$sel" ] && sel="$a"
  done
  python3 -c "
import json,sys
d=json.load(open('$D/data.json'))
print(json.dumps(d['by_selector'].get('$sel', d['default'])))"
  exit "$rc"
fi
if [ "$1" = "api" ]; then
  case "$2" in
    *protection/required_status_checks) [ -s "$D/prot.json" ] && cat "$D/prot.json" && exit 0; echo "gh: Branch not protected (HTTP 404)" >&2; exit 1 ;;
    *rules/branches/*) [ -s "$D/rules.json" ] && cat "$D/rules.json" && exit 0; echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  esac
fi
exit 1
''')
    os.chmod(d + "/gh", 0o755)
    return d


def run(d, cmd):
    env = dict(os.environ, PATH=d + os.pathsep + os.environ["PATH"])
    try:
        r = subprocess.run(["bash", HOOK], input=json.dumps({"tool_input": {"command": cmd}}),
                           capture_output=True, text=True, env=env, timeout=60)
    except subprocess.TimeoutExpired:
        # A hook that hangs is a hook whose timeout lets the command run.
        return -1, "hook timed out after 60s", ""
    log = ""
    if os.path.exists(d + "/calls.log"):
        log = open(d + "/calls.log").read()
    return r.returncode, r.stderr.strip(), log


CASES = []
R = "--repo acme/widgets --squash"
# The four P1 selector bypasses. #9 is queued; a hook that probes the wrong PR
# sees the green default and allows. The fifth element, when present, is text
# the probe log must contain: an exit code alone cannot tell a probe of the
# right pull request from a probe of the wrong one.
CASES.append(("root --repo before the subcommand",
              stub(GREEN, {"3": QUEUED}), "gh --repo other/repo pr merge 3 --squash", 2, "pr view 3 --repo other/repo"))
CASES.append(("--repo on the merge subcommand",
              stub(GREEN, {"3": QUEUED}), "gh pr merge 3 --repo other/repo --squash", 2, "pr view 3 --repo other/repo"))
CASES.append(("value-taking option before the number",
              stub(GREEN, {"3": QUEUED}), f"gh pr merge --subject 'subject here' 3 {R}", 2, "pr view 3 --repo acme/widgets"))
CASES.append(("second merge in one command",
              stub(GREEN, {"5": QUEUED}), f"gh pr merge 3 {R} && gh pr merge 5 {R}", 2, "pr view 5"))
# Conclusions that are not success.
CASES.append(("ACTION_REQUIRED is not green", stub(ACTION_REQ), f"gh pr merge 7 {R}", 2))
CASES.append(("STALE is not green", stub(STALE), f"gh pr merge 7 {R}", 2))
CASES.append(("an entry with no __typename", stub(NOTYPE), f"gh pr merge 7 {R}", 2))
# --auto.
CASES.append(("--auto with a ruleset requiring checks",
              stub(GREEN, rules=[{"type": "required_status_checks",
                                  "parameters": {"required_status_checks": [{"context": "test"}]}}]),
              f"gh pr merge 7 {R} --auto", 0))
CASES.append(("--auto with nothing required", stub(GREEN), f"gh pr merge 7 {R} --auto", 2))
# Malformed and unreadable output.
CASES.append(("truncated JSON", stub(GREEN, raw='{"number":7,"statusCheck'), f"gh pr merge 7 {R}", 2))
CASES.append(("an error body on stdout", stub(GREEN, raw='{"message":"Not Found"}'), f"gh pr merge 7 {R}", 2))
CASES.append(("gh exits non-zero", stub(GREEN, gh_rc=1), f"gh pr merge 7 {R}", 2))
# Empty rollup: fine with nothing required, not fine when the base requires.
CASES.append(("empty rollup, nothing required", stub(EMPTY), f"gh pr merge 7 {R}", 0))
CASES.append(("empty rollup, base requires checks",
              stub(EMPTY, prot={"contexts": ["test"]}), f"gh pr merge 7 {R}", 2))
# Command-word spellings.
CASES.append(("quote-split command word", stub(QUEUED), f'g""h pr merge 9 {R}', 2, "pr view 9"))
CASES.append(("quote-split subcommand", stub(QUEUED), f'gh pr me""rge 9 {R}', 2, "pr view 9"))
CASES.append(("uppercase GH", stub(QUEUED), f"GH pr merge 9 {R}", 2, "pr view 9"))
CASES.append(("absolute path", stub(QUEUED), f"/usr/local/bin/gh pr merge 9 {R}", 2, "pr view 9"))
# Separators inside a substitution or a quoted argument once tore the command.
CASES.append(("a semicolon inside a quoted body",
              stub(GREEN, {"42": QUEUED}), f'gh pr merge --subject merge --body "some; merge body" 42 {R}', 2, "pr view 42"))
CASES.append(("a pipe inside a quoted body",
              stub(GREEN, {"42": QUEUED}), f'gh pr merge --body "a | b" 42 {R}', 2, "pr view 42"))
# Lines: a newline inside quotes, a backslash continuation, a heredoc body.
CASES.append(("a multi-line --body before the number",
              stub(GREEN, {"9": QUEUED}), 'gh pr merge --squash --body "Summary\n\nDetails" 9 --repo acme/widgets', 2, "pr view 9"))
CASES.append(("a # inside a multi-line string before the merge",
              stub(GREEN, {"9": QUEUED}), f'gh pr comment 9 --body "Ready.\nCloses #12" && gh pr merge 9 {R}', 2, "pr view 9"))
CASES.append(("backslash continuation between pr and merge",
              stub(GREEN, {"9": QUEUED}), f"gh pr \\\nmerge 9 {R}", 2, "pr view 9"))
CASES.append(("backslash continuation before --repo",
              stub(GREEN), "gh pr merge 9 \\\n  --repo other/repo \\\n  --squash", 0, "pr view 9 --repo other/repo"))
CASES.append(("a comment ending in a backslash, then a merge",
              stub(GREEN, {"9": QUEUED}), f"# tidy up \\\ngh pr merge 9 {R}", 2, "pr view 9"))
CASES.append(("a quoted # after a kept heredoc with an apostrophe, then a merge",
              stub(GREEN, {"9": QUEUED}),
              f"git commit -F - <<EOF\nDon't ship yet\nEOF\ngit commit --amend -m 'Refs #12' && gh pr merge 9 {R}", 2, "pr view 9"))
CASES.append(("a kept heredoc body with an apostrophe, then a merge",
              stub(GREEN, {"9": QUEUED}), f"cat > notes.md <<'EOF'\ndon't\nEOF\ngh pr merge 9 {R}", 2, "pr view 9"))

# Refused on the shape: each of these once reached GitHub checked against a
# pull request other than the one merged, or not checked at all (#195). The
# stubs are green, so only a refusal gets exit 2.
for label, cmd in [
    ("no --repo", "gh pr merge 7 --squash"),
    ("no selector", "gh pr merge --repo acme/widgets --squash"),
    ("branch name as the selector", "gh pr merge some-red-branch --repo acme/widgets --squash"),
    ("URL as the selector", "gh pr merge https://github.com/o/r/pull/9 --squash"),
    ("-R before the subcommand", "gh -R other/repo pr merge 3 --squash"),
    ("attached -R", "gh pr merge 7 -Rother/repo --squash"),
    ("grouped short flags", "gh pr merge 7 --repo acme/widgets -sdR other/repo"),
    ("-t before the number", "gh pr merge -t 'subject here' 3 --repo acme/widgets --squash"),
    ("--auto=true", "gh pr merge 7 --repo acme/widgets --squash --auto=true"),
    ("--auto=false", "gh pr merge 7 --repo acme/widgets --squash --auto=false"),
    ("no strategy", "gh pr merge 7 --repo acme/widgets"),
    ("GH_REPO on the merge", "GH_REPO=other/repo gh pr merge 7 --squash"),
    ("env GH_REPO on the merge", "env GH_REPO=other/repo gh pr merge 7 --repo acme/widgets --squash"),
    ("GH_HOST on the merge", "GH_HOST=ghe.example.com gh pr merge 7 --repo o/r --squash"),
    ("wrapper before gh", "timeout 60 env GH_REPO=other/repo gh pr merge 7 --repo acme/widgets --squash"),
    ("GH_REPO exported, merge names no repository", "export GH_REPO=other/repo; gh pr merge 7 --squash"),
    ("GH_REPO in a subshell, merge names no repository", "(export GH_REPO=green/repo); gh pr merge 7 --squash"),
    ("cd, merge names no repository", "cd /tmp/otherrepo && gh pr merge 7 --squash"),
    ("GH_REPO before bash -c", "GH_REPO=a/b bash -c 'gh pr merge 7 --squash'"),
    ("selector via xargs", "echo 42 | xargs gh pr merge --repo acme/widgets --squash"),
    ("--repo from a command substitution",
     "gh --repo $(gh repo view --json nameWithOwner -q .nameWithOwner) pr merge 42 --squash"),
    ("merge under a variable command name", "G=gh; $G pr merge 7 --repo acme/widgets --squash"),
    ("merge under a substituted command name", "$(which gh) pr merge 7 --repo acme/widgets --squash"),
    ("REST merge endpoint", "gh api -X PUT repos/o/r/pulls/9/merge"),
    ("REST merge endpoint, -X=PUT", "gh api -X=PUT repos/o/r/pulls/9/merge"),
    ("REST merge endpoint, full URL", "gh api --method PUT https://api.github.com/repos/o/r/pulls/9/merge"),
    ("REST merge endpoint, placeholders", "gh api --method PUT /repos/{owner}/{repo}/pulls/9/merge"),
    ("REST merge endpoint, even as a GET", "gh api repos/o/r/pulls/9/merge"),
    ("REST branch merge", "gh api -X POST repos/o/r/merges -f base=main -f head=x"),
    ("GraphQL merge mutation",
     "gh api graphql -f query='mutation { mergePullRequest(input: {pullRequestId: \"x\"}) { clientMutationId } }'"),
    ("GraphQL at /graphql",
     "gh api /graphql -f query='mutation { mergePullRequest(input: {pullRequestId: \"x\"}) { clientMutationId } }'"),
    ("GraphQL auto-merge mutation",
     "gh api graphql -f query='mutation { enablePullRequestAutoMerge(input: {pullRequestId: \"x\"}) { clientMutationId } }'"),
    ("GraphQL query from a file", "gh api graphql -F query=@merge.graphql"),
    ("gh alias for a merge", "gh alias set m 'pr merge' && gh m 9"),
    ("host/owner/name, whose required checks cannot be read", "gh pr merge 7 --repo github.com/o/r --squash"),
    ("whole endpoint in a variable", 'EP=repos/o/r/pulls/9/merge; gh api -X PUT "$EP"'),
    ("a merge after a heredoc whose apostrophe unbalances the command, beside one in the shape",
     "cat > notes.md <<'X'\nit's done\nX\ngh pr merge 7 --repo o/r --squash\ngh pr merge 8 --repo o/r --squash --body \"Summary"),
]:
    CASES.append((label, stub(GREEN), cmd, 2))

# Must stay allowed, and checked against the right pull request.
CASES.append(("green merges", stub(GREEN), f"gh pr merge 7 {R}", 0, "pr view 7 --repo acme/widgets"))
CASES.append(("eval of a merge in the shape",
              stub(GREEN, {"9": QUEUED}), "eval 'gh pr merge 9 --repo o/r --squash'", 2, "pr view 9 --repo o/r"))
CASES.append(("bash -c of a merge in the shape, green",
              stub(GREEN), "bash -c 'gh pr merge 7 --repo o/r --squash'", 0, "pr view 7 --repo o/r"))
CASES.append(("sh -c of a merge in the shape, queued",
              stub(GREEN, {"9": QUEUED}), 'sh -c "gh pr merge 9 --repo o/r --squash"', 2, "pr view 9 --repo o/r"))
CASES.append(("cd before a merge that names its repository",
              stub(GREEN), f"cd /tmp/x && gh pr merge 7 {R}", 0, "pr view 7 --repo acme/widgets"))
CASES.append(("GH_REPO exported, merge names its own repository",
              stub(GREEN), f"export GH_REPO=x/y; gh pr merge 7 {R}", 0, "pr view 7 --repo acme/widgets"))
CASES.append(("a redirect target is not a selector",
              stub(GREEN), f"gh pr merge 7 {R} > merge.log 2>&1", 0, "pr view 7 --repo acme/widgets"))
CASES.append(("quoted text is not a merge", stub(QUEUED), 'echo "gh pr merge 9"', 0))
CASES.append(("git merge is a different command", stub(QUEUED), "git merge --no-ff x", 0))
CASES.append(("another gh subcommand", stub(QUEUED), "gh pr view 9", 0))
CASES.append(("an api read naming a merge field", stub(QUEUED), "gh api repos/o/r/pulls/9 --jq .mergeable_state", 0))
CASES.append(("an api read with variables in its path", stub(QUEUED), 'gh api "repos/$REPO/pulls/$PR" --jq .mergeable', 0))
CASES.append(("a multi-line commit message naming a merge", stub(QUEUED),
              'git commit -m "fix\n\nThe hook now reads gh pr merge 9 --squash.\nCloses #195"', 0))
CASES.append(("gh pr merge --help", stub(QUEUED), "gh pr merge --help", 0))

bad = 0
for case in CASES:
    label, d, cmd, want = case[:4]
    probe = case[4] if len(case) > 4 else None
    rc, err, log = run(d, cmd)
    ok = rc == want and (probe is None or probe in log)
    if not ok:
        bad += 1
    print(f"  {'ok ' if ok else 'BAD'} {label:44s} exit={rc} want={want}")
    if not ok:
        print(f"        cmd: {cmd}")
        if probe is not None:
            print(f"        probe log must contain: {probe}")
        print(f"        gh calls: {log.strip().splitlines()[:3]}")
        if err:
            print(f"        stderr: {err.splitlines()[0][:120]}")
print(f"\n{len(CASES)} bypass cases, {bad} wrong")
sys.exit(1 if bad else 0)
