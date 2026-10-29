"""Check .github/workflows/flow-tests.yml as parsed YAML.

Used by flow-ci-workflow.test.sh. The workflow is read as YAML, not as lines of
text: a commented-out line, a matrix row in another layout or a value set in a
second place passes a text match. What decides which tests run, and whether a
failure turns a job red, is compared with the exact value expected here: the
triggers, the jobs and their steps in order, the keys each may carry, the two
scripts that run the tests, the install line, the part variable and the
upload. A list of forbidden spellings would let the next spelling through.

An intended change to any of these is made here as well as in the workflow.
This check protects against a mistake; a pull request that edits the workflow
can edit this file too, so it does not stop a deliberate change.

Usage: python3 flow-workflow-check.py <workflow file>
Prints one BAD line per problem, or one OK line, then LINUX_N=<parts> when the
matrix names Linux parts.
"""
import sys

import yaml

PATHS = [
    "plugins/flow/bin/**",
    "plugins/flow/hooks/**",
    "plugins/flow/commands/**",
    "plugins/flow/references/**",
    "plugins/flow/skills/**",
    "plugins/flow/tests/**",
    "tests/**",
    ".github/workflows/flow-tests.yml",
]
ON = {"pull_request": {"paths": PATHS}, "push": {"branches": ["main"], "paths": PATHS}}
INSTALL = ["python3 --version",
           "python3 -m pip install --quiet --break-system-packages -r plugins/flow/requirements.txt"]
IMPORT_YAML = """python3 -c "import yaml; print('PyYAML', yaml.__version__)\""""
TEST_STEPS = ["Checkout repository", "Install Python prerequisites", "Install jscpd",
              "Verify test prerequisites", "Report the shell the suite will run under",
              "Run flow tests", "Upload end-to-end artifacts"]
ROOT_STEPS = ["Checkout repository", "Install Python prerequisites", "Verify prerequisites",
              "Run root tests"]
# The flow suite's step: macOS leaves out the suites that start the System One
# stub, chosen by content; Linux runs the whole list, of which run.sh takes
# the part FLOW_TEST_SHARD names.
RUN_FLOW = [
    'if [ "$RUNNER_OS" = macOS ]; then',
    "files=()",
    "linux_only=()",
    "for f in plugins/flow/tests/*.test.sh; do",
    """if grep -qE '^[[:space:]]*e2e_stub_start[[:space:]]' "$f"; then""",
    'linux_only+=("${f##*/}")',
    "else",
    'files+=("$f")',
    "fi",
    "done",
    'if [ "${#linux_only[@]}" -gt 0 ]; then',
    'echo "Linux only (they start the System One stub server): ${linux_only[*]}"',
    "fi",
    'plugins/flow/tests/run.sh "${files[@]}"',
    "else",
    "plugins/flow/tests/run.sh",
    "fi",
]
RUN_ENV = {"FLOW_E2E_ARTIFACT_DIR": "${{ runner.temp }}/flow-e2e",
           "FLOW_TEST_SHARD": "${{ matrix.shard }}/${{ matrix.shards }}"}
UPLOAD_IF = "${{ !cancelled() && steps.flow-tests.outcome != 'skipped' }}"
UPLOAD_WITH = {"name": "flow-e2e-${{ matrix.os }}-${{ matrix.shard }}-of-${{ matrix.shards }}",
               "path": "${{ runner.temp }}/flow-e2e", "if-no-files-found": "error"}
# A job or step key outside these (if, needs, continue-on-error, shell,
# defaults, env, working-directory, timeout-minutes on a step...) can skip the
# tests, keep a failing job green or change what a step runs.
JOB_KEYS = {"name", "strategy", "runs-on", "timeout-minutes", "steps"}
STEP_KEYS = {"name", "id", "uses", "with", "run"}
# The limit each part's row must reach. The comment above the matrix in
# flow-tests.yml gives the times these were set from.
FLOOR = {"ubuntu-latest": 20, "macos-latest": 45}

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
if set(wf) != {"name", True, "permissions", "jobs"}:
    bad("the workflow's top-level keys are %r, not name, on, permissions and jobs" % (sorted(map(str, wf)),))
if wf.get("permissions") != {"contents": "read"}:
    bad("permissions are %r, not contents: read" % (wf.get("permissions"),))
if wf.get(True) != ON:
    bad("the triggers are %r, not pull_request and push to main on the flow paths" % (wf.get(True),))
jobs = as_dict(wf.get("jobs"))
if set(jobs) != {"test", "root-tests"}:
    bad("the jobs are %r, not test and root-tests" % (sorted(jobs),))

steps_of = {}
for name, want_steps in (("test", TEST_STEPS), ("root-tests", ROOT_STEPS)):
    job = as_dict(jobs.get(name))
    if set(job) - JOB_KEYS:
        bad("jobs.%s sets %s" % (name, ", ".join(sorted(set(job) - JOB_KEYS))))
    if job.get("runs-on") != "${{ matrix.os }}":
        bad("jobs.%s runs on %r, not ${{ matrix.os }}" % (name, job.get("runs-on")))
    steps = [s for s in job.get("steps") or [] if isinstance(s, dict)]
    if [s.get("name") for s in steps] != want_steps:
        bad("jobs.%s has the steps %r, not %r in that order" % (name, [s.get("name") for s in steps], want_steps))
    named = {s.get("name"): s for s in steps}
    steps_of[name] = named
    for s in steps:
        allowed = set(STEP_KEYS)
        if name == "test" and s.get("name") == "Run flow tests":
            allowed.add("env")
        if name == "test" and s.get("name") == "Upload end-to-end artifacts":
            allowed.add("if")
        if set(s) - allowed:
            bad("step %r of %s sets %s" % (s.get("name"), name, ", ".join(sorted(set(s) - allowed))))
        for var in ("GITHUB_ENV", "GITHUB_PATH"):
            if var in str(s.get("run") or ""):
                bad("step %r of %s writes %s, which changes what later steps run" % (s.get("name"), name, var))
    # A job that does not install PyYAML fails on a runner image without it,
    # and the PyYAML suites skip with a pass if the verify step stops checking.
    if lines(as_dict(named.get("Install Python prerequisites")).get("run")) != INSTALL:
        bad("jobs.%s does not install exactly from plugins/flow/requirements.txt" % name)
    verify = "Verify test prerequisites" if name == "test" else "Verify prerequisites"
    if IMPORT_YAML not in lines(as_dict(named.get(verify)).get("run")):
        bad("the %r step of %s does not import yaml" % (verify, name))

root = as_dict(jobs.get("root-tests"))
if root.get("strategy") != {"fail-fast": False, "matrix": {"os": sorted(FLOOR, reverse=True)}}:
    bad("root-tests' strategy is %r, not both OSes without fail-fast" % (root.get("strategy"),))
if lines(as_dict(steps_of.get("root-tests", {}).get("Run root tests")).get("run")) != ["tests/run-all.sh"]:
    bad("the Run root tests step does not run exactly tests/run-all.sh")

job = as_dict(jobs.get("test"))
strategy = as_dict(job.get("strategy"))
if set(strategy) != {"fail-fast", "matrix"} or strategy.get("fail-fast") is not False:
    bad("the test job's strategy is %r; it needs fail-fast: false and a matrix only" % (sorted(strategy),))
matrix = as_dict(strategy.get("matrix"))
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

named = steps_of.get("test", {})
run = as_dict(named.get("Run flow tests"))
if run.get("id") != "flow-tests":
    bad("the Run flow tests step's id is %r; the upload step's condition reads flow-tests" % (run.get("id"),))
if run.get("env") != RUN_ENV:
    bad("the Run flow tests step's env is %r, not %r" % (run.get("env"), RUN_ENV))
if lines(run.get("run")) != RUN_FLOW:
    bad("the Run flow tests script differs from the expected one; change both together if that is intended")
up = as_dict(named.get("Upload end-to-end artifacts"))
if up.get("if") != UPLOAD_IF or up.get("uses") != "actions/upload-artifact@v4" or up.get("with") != UPLOAD_WITH:
    bad("the upload step is %r, not one upload per part that fails when a part wrote no artifact" % (
        {k: up.get(k) for k in ("if", "uses", "with")},))

if not out:
    out.append("OK " + "; ".join("%s %d part(s)" % (o, len(p)) for o, p in sorted(parts.items())))
lin = parts.get("ubuntu-latest") or []
if lin:
    out.append("LINUX_N=%d" % lin[0][1])
print("\n".join(out))
