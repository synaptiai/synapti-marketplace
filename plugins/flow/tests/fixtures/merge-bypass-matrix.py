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
    d = tempfile.mkdtemp()
    json.dump({"default": default, "by_selector": by_selector or {}}, open(d + "/data.json", "w"))
    open(d + "/prot.json", "w").write(json.dumps(prot) if prot else "")
    open(d + "/rules.json", "w").write(json.dumps(rules) if rules else "")
    open(d + "/rc", "w").write(str(gh_rc))
    open(d + "/raw", "w").write(raw or "")
    open(d + "/gh", "w").write(f'''#!/usr/bin/env bash
D="{d}"
printf '%s\\n' "$*" >> "$D/calls.log"
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
    r = subprocess.run(["bash", HOOK], input=json.dumps({"tool_input": {"command": cmd}}),
                       capture_output=True, text=True, env=env)
    log = ""
    if os.path.exists(d + "/calls.log"):
        log = open(d + "/calls.log").read()
    return r.returncode, r.stderr.strip(), log


CASES = []
# The four P1 selector bypasses. #9 is queued; a hook that probes the wrong PR
# sees the green default and allows.
CASES.append(("root --repo before the subcommand",
              stub(GREEN, {"3": QUEUED}), "gh --repo other/repo pr merge 3", 2))
CASES.append(("-R before the subcommand",
              stub(GREEN, {"3": QUEUED}), "gh -R other/repo pr merge 3", 2))
CASES.append(("branch name as the selector",
              stub(GREEN, {"some-red-branch": QUEUED}), "gh pr merge some-red-branch --squash", 2))
CASES.append(("URL as the selector",
              stub(GREEN, {"https://github.com/o/r/pull/9": QUEUED}),
              "gh pr merge https://github.com/o/r/pull/9", 2))
CASES.append(("value-taking option before the number",
              stub(GREEN, {"3": QUEUED}), "gh pr merge -t 'subject here' 3", 2))
CASES.append(("--repo on the merge subcommand",
              stub(GREEN, {"3": QUEUED}), "gh pr merge 3 --repo other/repo", 2))
CASES.append(("second merge in one command",
              stub(GREEN, {"5": QUEUED}), "gh pr merge 3 && gh pr merge 5", 2))
# Conclusions that are not success.
CASES.append(("ACTION_REQUIRED is not green", stub(ACTION_REQ), "gh pr merge 7", 2))
CASES.append(("STALE is not green", stub(STALE), "gh pr merge 7", 2))
CASES.append(("an entry with no __typename", stub(NOTYPE), "gh pr merge 7", 2))
# --auto spellings.
CASES.append(("--auto=true", stub(GREEN), "gh pr merge 7 --auto=true", 2))
CASES.append(("--auto=1", stub(GREEN), "gh pr merge 7 --auto=1", 2))
CASES.append(("--auto=false is not --auto", stub(GREEN), "gh pr merge 7 --auto=false", 0))
CASES.append(("--auto with a ruleset requiring checks",
              stub(GREEN, rules=[{"type": "required_status_checks",
                                  "parameters": {"required_status_checks": [{"context": "test"}]}}]),
              "gh pr merge 7 --auto", 0))
# Malformed and unreadable output.
CASES.append(("truncated JSON", stub(GREEN, raw='{"number":7,"statusCheck'), "gh pr merge 7", 2))
CASES.append(("an error body on stdout", stub(GREEN, raw='{"message":"Not Found"}'), "gh pr merge 7", 2))
CASES.append(("gh exits non-zero", stub(GREEN, gh_rc=1), "gh pr merge 7", 2))
# Empty rollup: fine with nothing required, not fine when the base requires.
CASES.append(("empty rollup, nothing required", stub(EMPTY), "gh pr merge 7", 0))
CASES.append(("empty rollup, base requires checks",
              stub(EMPTY, prot={"contexts": ["test"]}), "gh pr merge 7", 2))
# Command-word spellings.
CASES.append(("quote-split command word", stub(QUEUED), 'g""h pr merge 9', 2))
CASES.append(("uppercase GH", stub(QUEUED), "GH pr merge 9", 2))
CASES.append(("absolute path", stub(QUEUED), "/usr/local/bin/gh pr merge 9", 2))
# Must stay allowed.
CASES.append(("green merges", stub(GREEN), "gh pr merge 7 --squash", 0))
CASES.append(("green merge, no selector", stub(GREEN), "gh pr merge --squash", 0))
CASES.append(("quoted text is not a merge", stub(QUEUED), 'echo "gh pr merge 9"', 0))
CASES.append(("git merge is a different command", stub(QUEUED), "git merge --no-ff x", 0))
CASES.append(("another gh subcommand", stub(QUEUED), "gh pr view 9", 0))

bad = 0
for label, d, cmd, want in CASES:
    rc, err, log = run(d, cmd)
    ok = rc == want
    if not ok:
        bad += 1
    print(f"  {'ok ' if ok else 'BAD'} {label:44s} exit={rc} want={want}")
    if not ok:
        print(f"        cmd: {cmd}")
        print(f"        gh calls: {log.strip().splitlines()[:3]}")
        if err:
            print(f"        stderr: {err.splitlines()[0][:120]}")
print(f"\n{len(CASES)} bypass cases, {bad} wrong")
sys.exit(1 if bad else 0)
