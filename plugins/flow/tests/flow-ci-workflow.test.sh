# shellcheck shell=bash
# Tests that the flow CI workflow reaches everything it is meant to test.
#
# Each of these is a way for coverage to disappear without anything turning
# red: a workflow that no longer runs tests/run-all.sh, a path filter that no
# longer matches tests/ or plugins/flow/hooks/, so a change there does not
# trigger the suite, or a job that does not install the Python dependencies.
# The suites that need PyYAML skip with a pass on a runner image that does not
# ship it.

WF="$REPO_ROOT/.github/workflows/flow-tests.yml"

_flow_test_begin "flow-tests.yml installs from the manifest in every job"
INSTALL_LINES=$(grep -cE 'pip install .*-r plugins/flow/requirements\.txt' "$WF" || true)
[ -z "$INSTALL_LINES" ] && INSTALL_LINES=0
# Job keys are the two-space-indented mapping keys under the top-level `jobs:`
# block. Counting every two-space key in the file would also count pull_request
# and push under `on:`, which is how the first version of this assertion
# reported three jobs for a two-job workflow.
JOB_COUNT=$(awk '
  /^jobs:/ { in_jobs = 1; next }
  /^[^[:space:]#]/ { in_jobs = 0 }
  in_jobs && /^  [A-Za-z_][A-Za-z0-9_-]*:[[:space:]]*$/ { n++ }
  END { print n + 0 }
' "$WF")
[ -z "$JOB_COUNT" ] && JOB_COUNT=0
if [ "$INSTALL_LINES" -ge 2 ] && [ "$INSTALL_LINES" -eq "$JOB_COUNT" ]; then
  _flow_assert_pass "$INSTALL_LINES of $JOB_COUNT jobs install from the manifest"
else
  _flow_assert_fail "$INSTALL_LINES install-from-manifest lines for $JOB_COUNT jobs — a job that does not install PyYAML fails on any runner image that does not ship it, which is how the root-tests job first went red on macOS and green on Ubuntu"
fi

_flow_test_begin "the workflow invokes the runner"
if grep -q 'tests/run-all.sh' "$WF"; then
  _flow_assert_pass "flow-tests.yml runs tests/run-all.sh"
else
  _flow_assert_fail "no workflow step runs tests/run-all.sh — the root tests are unreached again"
fi

_flow_test_begin "the workflow path filter matches the root tests directory"
FILTER_HITS=$(grep -c "^      - 'tests/\*\*'" "$WF" || true)
[ -z "$FILTER_HITS" ] && FILTER_HITS=0
if [ "$FILTER_HITS" -eq 2 ]; then
  _flow_assert_pass "tests/** is filtered on both pull_request and push"
else
  _flow_assert_fail "expected tests/** in 2 path-filter lists, found $FILTER_HITS — a change under tests/ would not trigger the workflow"
fi

_flow_test_begin "the workflow path filter matches the flow hooks directory"
HOOK_HITS=$(grep -c "^      - 'plugins/flow/hooks/\*\*'" "$WF" || true)
[ -z "$HOOK_HITS" ] && HOOK_HITS=0
if [ "$HOOK_HITS" -eq 2 ]; then
  _flow_assert_pass "plugins/flow/hooks/** is filtered on both pull_request and push"
else
  _flow_assert_fail "expected plugins/flow/hooks/** in 2 path-filter lists, found $HOOK_HITS — a hook change would not run the flow suite"
fi

_flow_test_begin "the macOS flow job leaves out the suites that start the System One stub, by content"
# On the macOS runner a stub scenario takes 13 s or more and stubs can fail to
# start in time, so those suites run on Linux only. The selection is by a line
# that calls e2e_stub_start; this keeps it from being renamed away or matching
# nothing, which would leave CI green while the rule did nothing.
STUB_RE='^[[:space:]]*e2e_stub_start[[:space:]]'
if grep -qF "grep -qE '$STUB_RE'" "$WF"; then
  _flow_assert_pass "the flow-tests step selects suites with the e2e_stub_start pattern"
else
  _flow_assert_fail "the flow-tests step no longer selects suites by a line that calls e2e_stub_start"
fi
STUB_SUITES=$(grep -lE "$STUB_RE" "$REPO_ROOT"/plugins/flow/tests/*.test.sh 2>/dev/null | wc -l | tr -d ' ')
if [ "${STUB_SUITES:-0}" -ge 1 ] && grep -qE "$STUB_RE" "$REPO_ROOT/plugins/flow/tests/e2e-system-one.test.sh"; then
  _flow_assert_pass "the pattern matches $STUB_SUITES suite(s), e2e-system-one.test.sh among them"
else
  _flow_assert_fail "the pattern matches no suite, or not e2e-system-one.test.sh: the macOS job would run the stub suites again"
fi

_flow_test_begin "the split suite: every part has a matrix row and a long enough limit, and each job runs its own part"
# The flow suite runs in parts (run.sh, FLOW_TEST_SHARD=K/N). The workflow is
# read as YAML, not as lines of text: a commented-out line, a row written in
# another layout or a value set in a second place would pass a text match.
# Each of these would leave CI green while it tested less than the suite, or
# cancel runs that were still passing:
# - a matrix that lists parts 1, 2 and 4 of 4, or part 1 twice;
# - FLOW_TEST_SHARD not reaching run.sh, set again elsewhere, or overridden
#   on the run.sh command line;
# - one artifact name for every part (upload-artifact refuses a second
#   upload of a name);
# - a fixed limit in the job, a step-level limit, or a row below the floor.
#   The comment above the matrix in flow-tests.yml gives the times these
#   floors (20 minutes for a Linux part, 45 for macOS) were set from.
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_assert_pass "SKIP: PyYAML not installed (apt install python3-yaml / pip install pyyaml)"
  WF_LINUX_N=""
else
  WF_CHECK=$(python3 - "$WF" <<'PY' 2>&1
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
out = []
def bad(m): out.append("BAD " + m)
job = (wf.get("jobs") or {}).get("test") or {}
rows = ((job.get("strategy") or {}).get("matrix") or {}).get("include")
if not isinstance(rows, list) or not rows:
    bad("jobs.test.strategy.matrix.include is not a list of rows")
    rows = []
if set((job.get("strategy") or {}).get("matrix") or {}) - {"include"}:
    bad("the matrix has keys besides include, which multiply the rows")
floor = {"ubuntu-latest": 20, "macos-latest": 45}
parts = {}
for r in rows:
    if not isinstance(r, dict) or set(r) != {"os", "shard", "shards", "timeout"} \
       or not all(isinstance(r[k], int) and not isinstance(r[k], bool) for k in ("shard", "shards", "timeout")):
        bad("a matrix row is not {os, shard, shards, timeout} with whole numbers: %r" % (r,))
        continue
    if r["os"] not in floor:
        bad("a matrix row names an unknown OS: %r" % (r["os"],))
        continue
    if r["timeout"] < floor[r["os"]]:
        bad("%s part %d has a %d-minute limit, below %d" % (r["os"], r["shard"], r["timeout"], floor[r["os"]]))
    parts.setdefault(r["os"], []).append((r["shard"], r["shards"]))
for os_ in floor:
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
steps = job.get("steps") or []
named = {s.get("name"): s for s in steps if isinstance(s, dict)}
for s in steps:
    if isinstance(s, dict) and "timeout-minutes" in s:
        bad("step %r sets its own timeout-minutes" % (s.get("name"),))
want = "${{ matrix.shard }}/${{ matrix.shards }}"
run = named.get("Run flow tests") or {}
if (run.get("env") or {}).get("FLOW_TEST_SHARD") != want:
    bad("the Run flow tests step does not set FLOW_TEST_SHARD to %s" % want)
places = [("the workflow", wf.get("env")), ("jobs.test", job.get("env"))]
places += [("step %r" % s.get("name"), s.get("env")) for s in steps if isinstance(s, dict) and s is not run]
for where, env in places:
    if isinstance(env, dict) and "FLOW_TEST_SHARD" in env:
        bad("%s also sets FLOW_TEST_SHARD" % where)
script = run.get("run") or ""
if "FLOW_TEST_SHARD" in script:
    bad("the Run flow tests script names FLOW_TEST_SHARD, which could override the part")
calls = [l.strip() for l in script.splitlines() if "tests/run.sh" in l]
if "plugins/flow/tests/run.sh" not in calls \
   or any(c not in ("plugins/flow/tests/run.sh", 'plugins/flow/tests/run.sh "${files[@]}"') for c in calls):
    bad("the Run flow tests script calls run.sh as %r, not as plugins/flow/tests/run.sh with the whole list" % (calls,))
up = (named.get("Upload end-to-end artifacts") or {}).get("with") or {}
if up.get("name") != "flow-e2e-${{ matrix.os }}-${{ matrix.shard }}-of-${{ matrix.shards }}":
    bad("the upload step's artifact name %r is not unique per part" % (up.get("name"),))
if not out:
    out.append("OK " + "; ".join("%s %d part(s)" % (o, len(p)) for o, p in sorted(parts.items())))
lin = parts.get("ubuntu-latest") or []
if lin:
    out.append("LINUX_N=%d" % lin[0][1])
print("\n".join(out))
PY
)
  WF_LINUX_N=$(printf '%s\n' "$WF_CHECK" | sed -n 's/^LINUX_N=\([0-9][0-9]*\)$/\1/p')
  if printf '%s\n' "$WF_CHECK" | grep -q '^OK '; then
    _flow_assert_pass "the matrix, the limits, FLOW_TEST_SHARD and the artifact name hold: $(printf '%s\n' "$WF_CHECK" | sed -n 's/^OK //p')"
  else
    _flow_assert_fail "the split suite is misconfigured in flow-tests.yml: $(printf '%s\n' "$WF_CHECK" | grep -v '^LINUX_N=' | tr '\n' ';')"
  fi
fi

_flow_test_begin "every Linux part runs a suite that writes end-to-end artifacts"
# The upload step fails when a part wrote no artifact. A suite that loads
# tests/lib/e2e.sh writes one file per scenario; each Linux part, taken as
# run.sh takes it (this file runs under run.sh, after the same locale pin),
# must hold one. Only the line that loads the library counts: a comment, a
# message or a quoted pattern naming the file does not.
WF_E2E_RE='^[[:space:]]*(&&[[:space:]]*)?source "\$REPO_ROOT/plugins/flow/tests/lib/e2e\.sh"'
WF_EMPTY=""
if [ -n "${WF_LINUX_N:-}" ]; then
  _wf_k=1
  while [ "$_wf_k" -le "$WF_LINUX_N" ]; do
    _wf_i=0 _wf_hit=0
    for _wf_f in "$REPO_ROOT"/plugins/flow/tests/*.test.sh; do
      if [ $((_wf_i % WF_LINUX_N)) -eq $((_wf_k - 1)) ] && grep -qE "$WF_E2E_RE" "$_wf_f"; then
        _wf_hit=1
      fi
      _wf_i=$((_wf_i + 1))
    done
    [ "$_wf_hit" = 1 ] || WF_EMPTY="$WF_EMPTY $_wf_k/$WF_LINUX_N"
    _wf_k=$((_wf_k + 1))
  done
  if [ -z "$WF_EMPTY" ]; then
    _flow_assert_pass "each of the $WF_LINUX_N Linux parts holds a suite that loads tests/lib/e2e.sh"
  else
    _flow_assert_fail "Linux parts with no end-to-end suite, whose artifact upload would fail:$WF_EMPTY"
  fi
elif python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_assert_fail "no Linux part count was read from the matrix"
else
  _flow_assert_pass "SKIP: PyYAML not installed, so the Linux part count was not read"
fi
