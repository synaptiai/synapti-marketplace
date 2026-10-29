"""Check .github/workflows/flow-tests.yml as parsed YAML.

Used by flow-ci-workflow.test.sh. Each check is a way for CI to stay green
while it tests less than it should, or to cancel runs that are still passing.
The workflow is read as YAML, not as lines of text: a commented-out line, a
matrix row in another layout or a value set in a second place passes a text
match.

Usage: python3 flow-workflow-check.py <workflow file>
Prints one BAD line per problem, or one OK line, then LINUX_N=<parts> when the
matrix names Linux parts.
"""
import re
import sys

import yaml

WANT_SHARD = "${{ matrix.shard }}/${{ matrix.shards }}"
WANT_ARTIFACT = "flow-e2e-${{ matrix.os }}-${{ matrix.shard }}-of-${{ matrix.shards }}"
WANT_UPLOAD_IF = "${{ !cancelled() && steps.flow-tests.outcome != 'skipped' }}"
# The limit each part's row must reach. The comment above the matrix in
# flow-tests.yml gives the times these were set from.
FLOOR = {"ubuntu-latest": 20, "macos-latest": 45}
INSTALL = re.compile(r"^python3 -m pip install .*-r plugins/flow/requirements\.txt$")
RUN_CALLS = ("plugins/flow/tests/run.sh", 'plugins/flow/tests/run.sh "${files[@]}"')

out = []


def bad(msg):
    out.append("BAD " + msg)


def lines(script):
    """The script's command lines: stripped, without blanks and comments."""
    if not isinstance(script, str):
        return []
    return [l.strip() for l in script.splitlines() if l.strip() and not l.strip().startswith("#")]


def as_dict(v):
    return v if isinstance(v, dict) else {}


wf = as_dict(yaml.safe_load(open(sys.argv[1])))
# PyYAML reads the key `on` as the boolean True.
on = as_dict(wf.get(True, wf.get("on")))
for event in ("pull_request", "push"):
    paths = as_dict(on.get(event)).get("paths")
    if not isinstance(paths, list):
        bad("on.%s has no paths list, so the workflow does not run on %s" % (event, event))
        continue
    for p in ("tests/**", "plugins/flow/hooks/**", "plugins/flow/tests/**"):
        if p not in paths:
            bad("on.%s.paths lacks %s, so a change there does not run the suite" % (event, p))
if "main" not in (as_dict(on.get("push")).get("branches") or []):
    bad("on.push.branches lacks main")

jobs = as_dict(wf.get("jobs"))
for name in ("test", "root-tests"):
    job = as_dict(jobs.get(name))
    if not job:
        bad("there is no %s job" % name)
        continue
    # A condition or continue-on-error on a job or a step can skip the tests,
    # or keep the job green when they fail. The upload step's condition is the
    # one allowed.
    for key in ("if", "continue-on-error"):
        if key in job:
            bad("jobs.%s sets %s" % (name, key))
    if job.get("runs-on") != "${{ matrix.os }}":
        bad("jobs.%s runs on %r, not ${{ matrix.os }}" % (name, job.get("runs-on")))
    steps = [s for s in job.get("steps") or [] if isinstance(s, dict)]
    for s in steps:
        if "continue-on-error" in s:
            bad("step %r of %s sets continue-on-error" % (s.get("name"), name))
        if "if" in s and not (s.get("name") == "Upload end-to-end artifacts" and s["if"] == WANT_UPLOAD_IF):
            bad("step %r of %s has the condition %r" % (s.get("name"), name, s["if"]))
        if "GITHUB_ENV" in str(s.get("run") or ""):
            bad("step %r of %s writes GITHUB_ENV, which can change what later steps run" % (s.get("name"), name))
    # A job that does not install PyYAML fails on a runner image without it.
    if not any(INSTALL.match(l) for s in steps for l in lines(s.get("run"))):
        bad("jobs.%s does not install from plugins/flow/requirements.txt" % name)

root = as_dict(jobs.get("root-tests"))
if not any(l == "tests/run-all.sh" for s in root.get("steps") or [] if isinstance(s, dict) for l in lines(s.get("run"))):
    bad("no step of root-tests runs tests/run-all.sh")
if sorted(as_dict(as_dict(root.get("strategy")).get("matrix")).get("os") or []) != sorted(FLOOR):
    bad("root-tests does not run on both %s" % " and ".join(sorted(FLOOR)))

job = as_dict(jobs.get("test"))
matrix = as_dict(as_dict(job.get("strategy")).get("matrix"))
rows = matrix.get("include")
if not isinstance(rows, list) or not rows:
    bad("jobs.test.strategy.matrix.include is not a list of rows")
    rows = []
if set(matrix) - {"include"}:
    bad("the matrix has keys besides include, which multiply the rows")
parts = {}
for r in rows:
    if not isinstance(r, dict) or set(r) != {"os", "shard", "shards", "timeout"} \
       or not all(type(r[k]) is int for k in ("shard", "shards", "timeout")):
        bad("a matrix row is not {os, shard, shards, timeout} with whole numbers: %r" % (r,))
        continue
    if r["os"] not in FLOOR:
        bad("a matrix row names an unknown OS: %r" % (r["os"],))
        continue
    if r["timeout"] < FLOOR[r["os"]]:
        bad("%s part %d has a %d-minute limit, below %d" % (r["os"], r["shard"], r["timeout"], FLOOR[r["os"]]))
    parts.setdefault(r["os"], []).append((r["shard"], r["shards"]))
for os_ in FLOOR:
    p = parts.get(os_, [])
    counts = {n for _, n in p}
    if len(counts) != 1:
        bad("%s rows give part counts %s, not one count" % (os_, sorted(counts) or "none"))
        continue
    n = counts.pop()
    if sorted(k for k, _ in p) != list(range(1, n + 1)):
        bad("%s rows list parts %s of %d, not 1 to %d once each" % (os_, sorted(k for k, _ in p), n, n))
if job.get("timeout-minutes") != "${{ matrix.timeout }}":
    bad("jobs.test.timeout-minutes is %r, not ${{ matrix.timeout }}" % (job.get("timeout-minutes"),))

steps = [s for s in job.get("steps") or [] if isinstance(s, dict)]
named = {s.get("name"): s for s in steps}
for s in steps:
    if "timeout-minutes" in s:
        bad("step %r sets its own timeout-minutes" % (s.get("name"),))
runners = [s.get("name") for s in steps if any("tests/run.sh" in l for l in lines(s.get("run")))]
if runners != ["Run flow tests"]:
    bad("the steps that call run.sh are %r, not the Run flow tests step alone" % (runners,))
run = as_dict(named.get("Run flow tests"))
if run.get("id") != "flow-tests":
    bad("the Run flow tests step's id is %r; the upload step's condition reads flow-tests" % (run.get("id"),))
if as_dict(run.get("env")).get("FLOW_TEST_SHARD") != WANT_SHARD:
    bad("the Run flow tests step does not set FLOW_TEST_SHARD to %s" % WANT_SHARD)
for where, env in [("the workflow", wf.get("env")), ("jobs.test", job.get("env"))] + \
        [("step %r" % s.get("name"), s.get("env")) for s in steps if s is not run]:
    if isinstance(env, dict) and "FLOW_TEST_SHARD" in env:
        bad("%s also sets FLOW_TEST_SHARD" % where)
script = lines(run.get("run"))
if any("FLOW_TEST_SHARD" in l for l in script):
    bad("the Run flow tests script names FLOW_TEST_SHARD, which could override the part")
calls = [l for l in script if "tests/run.sh" in l]
if "plugins/flow/tests/run.sh" not in calls or any(c not in RUN_CALLS for c in calls):
    bad("the Run flow tests script calls run.sh as %r, not with the whole list" % (calls,))
# Only macOS takes the filtered list; the stub suites are chosen by content.
for need in ('if [ "$RUNNER_OS" = macOS ]; then',
             """if grep -qE '^[[:space:]]*e2e_stub_start[[:space:]]' "$f"; then"""):
    if need not in script:
        bad("the Run flow tests script lacks the line %r" % need)
for l in script:
    if re.match(r"(exit|return)\b", l) or "||" in l or re.match(r"set\s+\+", l):
        bad("the Run flow tests script has the line %r, which can end it early or hide a failure" % l)
up = as_dict(named.get("Upload end-to-end artifacts"))
w = as_dict(up.get("with"))
if w.get("name") != WANT_ARTIFACT:
    bad("the upload step's artifact name %r is not unique per part" % (w.get("name"),))
if w.get("if-no-files-found") != "error":
    bad("the upload step does not fail when a part wrote no artifact (if-no-files-found is %r)" % (w.get("if-no-files-found"),))

if not out:
    out.append("OK " + "; ".join("%s %d part(s)" % (o, len(p)) for o, p in sorted(parts.items())))
lin = parts.get("ubuntu-latest") or []
if lin:
    out.append("LINUX_N=%d" % lin[0][1])
print("\n".join(out))
