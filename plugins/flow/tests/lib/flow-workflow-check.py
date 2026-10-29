"""Check .github/workflows/flow-tests.yml as parsed YAML.

Used by flow-ci-workflow.test.sh. The workflow is read as YAML, not as lines of
text: a commented-out line, a matrix row in another layout or a value set in a
second place passes a text match. What decides which tests run, and whether a
failure turns a job red, is compared with the exact value expected here: the
top-level keys, the triggers, the jobs and the keys each carries, and every
step of both jobs (name, action, settings, environment, condition and command
lines, in order). The matrix is checked by its meaning: for each OS, parts 1
to N once each, and a limit no lower than the floor for that OS.

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
CHECKOUT = {"name": "Checkout repository", "uses": "actions/checkout@v4", "with": {"fetch-depth": 0}}
INSTALL = {"name": "Install Python prerequisites",
           "run": ["python3 --version",
                   "python3 -m pip install --quiet --break-system-packages -r plugins/flow/requirements.txt"]}
# Each step with its command lines ("run"): stripped, without blank lines and
# comments. On Linux the flow step runs the whole list, of which run.sh takes
# the part FLOW_TEST_SHARD names; macOS leaves out the suites that start the
# System One stub, chosen by content.
STEPS = {
    "test": [
        CHECKOUT,
        INSTALL,
        {"name": "Install jscpd", "run": ["npm install -g --ignore-scripts jscpd@5.3.1"]},
        {"name": "Verify test prerequisites",
         "run": ["bash --version | head -1",
                 "jq --version",
                 "jscpd --version",
                 'awk --version 2>/dev/null | head -1 || echo "awk: BSD/POSIX (no --version)"',
                 """python3 -c "import yaml; print('PyYAML', yaml.__version__)\"""",
                 """python3 -c "import jsonschema; print('jsonschema', jsonschema.__version__)\"""",
                 "python3 -m pip list --format=freeze"]},
        {"name": "Report the shell the suite will run under",
         "run": ["/bin/bash --version | head -1",
                 'echo "checkout root length: ${#GITHUB_WORKSPACE}"']},
        {"name": "Run flow tests",
         "id": "flow-tests",
         "env": {"FLOW_E2E_ARTIFACT_DIR": "${{ runner.temp }}/flow-e2e",
                 "FLOW_TEST_SHARD": "${{ matrix.shard }}/${{ matrix.shards }}"},
         "run": ['if [ "$RUNNER_OS" = macOS ]; then',
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
                 "fi"]},
        {"name": "Upload end-to-end artifacts",
         "if": "${{ !cancelled() && steps.flow-tests.outcome != 'skipped' }}",
         "uses": "actions/upload-artifact@v4",
         "with": {"name": "flow-e2e-${{ matrix.os }}-${{ matrix.shard }}-of-${{ matrix.shards }}",
                  "path": "${{ runner.temp }}/flow-e2e",
                  "if-no-files-found": "error"}},
    ],
    "root-tests": [
        CHECKOUT,
        INSTALL,
        {"name": "Verify prerequisites",
         "run": ["/bin/bash --version | head -1",
                 "jq --version",
                 "git --version",
                 """python3 -c "import yaml; print('PyYAML', yaml.__version__)\"""",
                 "python3 -m pip list --format=freeze"]},
        {"name": "Run root tests", "run": ["tests/run-all.sh"]},
    ],
}
# A job key outside these (if, needs, continue-on-error, defaults, env...) can
# skip the tests or keep a failing job green.
JOB_KEYS = {"test": {"name", "strategy", "runs-on", "timeout-minutes", "steps"},
            "root-tests": {"strategy", "runs-on", "timeout-minutes", "steps"}}
# The limit each part's row must reach. The comment above the matrix in
# flow-tests.yml gives the times these were set from.
FLOOR = {"ubuntu-latest": 20, "macos-latest": 45}

out = []


def bad(msg):
    out.append("BAD " + msg)


def lines(script, where):
    """A run script's command lines: stripped, without blanks and comments.

    Split at newlines only and strip spaces and tabs only, as bash does. A
    character Python treats as a line break or as space, and bash does not,
    could otherwise hide a command after what looks like a comment; and a line
    ending in a backslash joins the next one in bash. Both are refused.
    """
    if not isinstance(script, str):
        bad("the run of %s is not text" % where)
        return []
    if any(ord(c) > 127 for c in script):
        bad("the run of %s holds a character outside ASCII" % where)
    if any(l.rstrip(" \t").endswith("\\") for l in script.split("\n")):
        bad("the run of %s continues a line with a backslash" % where)
    return [l.strip(" \t") for l in script.split("\n") if l.strip(" \t") and not l.strip(" \t").startswith("#")]


def as_dict(v):
    return v if isinstance(v, dict) else {}


def check(text):
    # The top-level keys as written: PyYAML loads `on`, `On`, `yes` and `1`
    # alike as True, and GitHub reads only `on`.
    node = yaml.compose(text)
    keys = sorted(repr(k.value) for k, _ in getattr(node, "value", []) if isinstance(k, yaml.ScalarNode))
    if keys != sorted(repr(k) for k in ("name", "on", "permissions", "jobs")):
        bad("the workflow's top-level keys are %s, not name, on, permissions and jobs" % ", ".join(keys))
    wf = as_dict(yaml.safe_load(text))
    if wf.get("permissions") != {"contents": "read"}:
        bad("permissions are %r, not contents: read" % (wf.get("permissions"),))
    if wf.get(True) != ON:
        bad("the triggers are %r, not pull_request and push to main on the flow paths" % (wf.get(True),))
    jobs = as_dict(wf.get("jobs"))
    if sorted(map(repr, jobs)) != sorted(map(repr, STEPS)):
        bad("the jobs are %s, not test and root-tests" % ", ".join(sorted(map(repr, jobs))))

    for name, want in STEPS.items():
        job = as_dict(jobs.get(name))
        if set(map(repr, job)) != set(map(repr, JOB_KEYS[name])):
            bad("jobs.%s has the keys %s, not %s" % (name, ", ".join(sorted(map(repr, job))),
                                                     ", ".join(sorted(JOB_KEYS[name]))))
        if job.get("runs-on") != "${{ matrix.os }}":
            bad("jobs.%s runs on %r, not ${{ matrix.os }}" % (name, job.get("runs-on")))
        steps = job.get("steps")
        if not isinstance(steps, list):
            bad("jobs.%s has no list of steps" % name)
            continue
        got = []
        for i, s in enumerate(steps):
            if not isinstance(s, dict):
                bad("step %d of %s is not a mapping" % (i + 1, name))
                got.append(None)
                continue
            got.append({k: (lines(v, "step %d of %s" % (i + 1, name)) if k == "run" else v) for k, v in s.items()})
        if len(got) != len(want):
            bad("jobs.%s has %d steps, not %d" % (name, len(got), len(want)))
        for i, (g, w) in enumerate(zip(got, want)):
            if g != w:
                bad("step %d of %s differs from the expected %r; change both together if that is intended" % (
                    i + 1, name, w["name"]))

    root = as_dict(jobs.get("root-tests"))
    if root.get("strategy") != {"fail-fast": False, "matrix": {"os": ["ubuntu-latest", "macos-latest"]}}:
        bad("root-tests' strategy is %r, not both OSes without fail-fast" % (root.get("strategy"),))
    if root.get("timeout-minutes") != 10:
        bad("root-tests' limit is %r, not 10 minutes" % (root.get("timeout-minutes"),))

    job = as_dict(jobs.get("test"))
    strategy = as_dict(job.get("strategy"))
    if sorted(map(repr, strategy)) != sorted(map(repr, ("fail-fast", "matrix"))) or strategy.get("fail-fast") is not False:
        bad("the test job's strategy has %s; it needs fail-fast: false and a matrix only" % (
            ", ".join(sorted(map(repr, strategy))),))
    matrix = as_dict(strategy.get("matrix"))
    rows = matrix.get("include")
    if not isinstance(rows, list) or not rows:
        bad("jobs.test.strategy.matrix.include is not a list of rows")
        rows = []
    if set(map(repr, matrix)) - {repr("include")}:
        bad("the matrix has keys besides include, which multiply the rows")
    parts = {}
    for r in rows:
        if not isinstance(r, dict) or set(map(repr, r)) != set(map(repr, ("os", "shard", "shards", "timeout"))) \
           or not isinstance(r.get("os"), str) \
           or not all(type(r[k]) is int for k in ("shard", "shards", "timeout")):
            bad("a matrix row is not {os, shard, shards, timeout} with an OS name and whole numbers: %r" % (r,))
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
    return parts


try:
    parts = check(open(sys.argv[1], encoding="utf-8").read())
except Exception as e:  # an unreadable workflow is a failed check, never a pass
    bad("the workflow could not be checked: %s: %s" % (type(e).__name__, e))
    parts = {}
if not out:
    out.append("OK " + "; ".join("%s %d part(s)" % (o, len(p)) for o, p in sorted(parts.items())))
lin = parts.get("ubuntu-latest") or []
if lin and not any(l.startswith("BAD ") for l in out):
    out.append("LINUX_N=%d" % lin[0][1])
print("\n".join(out))
