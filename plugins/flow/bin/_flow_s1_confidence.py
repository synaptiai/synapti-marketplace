"""The Python half of bin/flow-s1-confidence.sh: the System One decision point
review.confidence, which asks, for each eligible P1 or P2 review finding,
whether the code it cites shows the defect it describes, and re-records the
finding LOW when a confident answer says it does not.

flow-s1-confidence.sh resolves the mode and hands everything over as
arguments; this file reads no settings itself. Each finding is asked through
bin/flow-s1.sh, the client, which reads the provider settings, applies the
threshold in system-one/questions.yaml and writes the records. This file
holds no threshold of its own. The state is built by bin/_flow_finding_state.py,
the code behind bin/flow-finding-state.sh, so a replay builds the same bytes.

Which findings are asked (the eligibility rule, decided here from the
finding, never by the model), in this order:
  not-eligible-security  a reviewer whose name contains "security", an id
                         starting SEC- or DEP-, or a category in the grounding
                         pass's security list (SECURITY)
  not-eligible-category  any other category outside the non-security list
                         of references/finding-schema.md (NON_SECURITY)
  not-eligible-priority  P3
  not-eligible-low       confidence LOW (a missing confidence is MEDIUM, as
                         the router reads it)
  then the state helper's reasons: no-line, path-refused, file-missing,
  line-out-of-range, not-text.
The agent that raised a finding plays no part beyond the security rule:
findings from holdout-validation, convention-checker and test-runner are
asked when they meet the rule above.
At most MAX_ASKED findings are asked; asking also stops after
MAX_CONSECUTIVE_DOWN timeout or connection results in a row, after as many
client-error or internal-error results in a row, and once the budget
(MAX_BUDGET_S seconds, or fewer with --budget) has passed; the client is
told to end a request by then and is stopped CALL_MARGIN_S later if it has
not. A finding not asked for these reasons is skipped with REASON=cap,
provider-down, client-broken or budget. The stop rules, the request and the
record of the state are in bin/_flow_s1_common.py, shared with review.dedup
and review.challenge.

What an answer does, in on mode only (the mode flow-s1-mode.sh --all reports):
  exit 0, p < 0.5    unsupported: the finding is listed as demoted. The
                     session re-records it LOW, except a P1 on someone else's
                     pull request, which stays counted with the answer shown
                     as a note (bin/flow-finding-route.sh --s1-demoted)
  exit 0, p >= 0.5   supported: nothing changes; an answer never raises a
                     confidence
  exit 3             no answer: nothing changes
After the result lines: S1_CONFIDENCE_MODE, S1_ASKED, one
S1_NO_ANSWER_<REASON>=<n> line per reason a call gave no answer for,
S1_DEMOTED, and S1_DEMOTED_FILE, which is empty when nothing was demoted.
A --demoted-out that is a symlink, an existing file that is not a regular
file, or a path in a directory that does not exist is refused before any
finding is asked.
In shadow and off mode nothing changes, whatever the answer: the client checks
the threshold before the mode, so a shadow answer below the threshold exits 3
with below-threshold, and only the mode says no demotion may follow.
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

import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _flow_finding_state as finding_state
import _flow_s1_common as common
from _flow_s1_common import NON_SECURITY, SECURITY

SITE = "review.confidence"
QUESTION = "claim_supported"
MAX_ASKED = 25


def valid_entry(f):
    """True when the entry has what the eligibility rule and the state need."""
    try:
        finding_state.check_finding(f)
    except finding_state.Skip:
        return False
    revs = f.get("reviewers")
    if not isinstance(revs, list) or not revs or not all(isinstance(r, str) and r for r in revs):
        return False
    return f.get("confidence", "") in ("HIGH", "MEDIUM", "LOW", "", None)


def is_security(f):
    if any("security" in r.lower() for r in f["reviewers"]):
        return True
    if f["id"].lower().startswith(("sec-", "dep-")):
        return True
    return f["category"].strip().lower() in SECURITY


def ineligible(f):
    if is_security(f):
        return "not-eligible-security"
    if f["category"].strip().lower() not in NON_SECURITY:
        return "not-eligible-category"
    if f["priority"] == "P3":
        return "not-eligible-priority"
    if f.get("confidence") == "LOW":
        return "not-eligible-low"
    return None


def run(a):
    try:
        with open(a.findings, encoding="utf-8") as f:
            findings = json.load(f)
    except (OSError, ValueError, RecursionError) as e:
        raise common.Blocked("the findings file is not readable JSON (%s)" % type(e).__name__)
    if not isinstance(findings, list):
        raise common.Blocked("the findings file is not a JSON list")
    if not common.ascii_match(common.REF_RE, a.ref_prefix) or len(a.ref_prefix) > 150:
        raise common.Blocked("--ref-prefix must start with a letter or digit, use only letters, digits and . _ : / # @ + -, and be at most 150 characters")
    if a.run_id and (not common.ascii_match(common.RUN_ID_RE, a.run_id) or ".." in a.run_id):
        raise common.Blocked("--run-id must start with a letter or digit and use only letters, digits, dot, underscore and dash, without ..")
    if not os.path.isdir(a.tree):
        raise common.Blocked("--tree is not a directory")
    if a.demoted_out:
        common.check_out(a.demoted_out, "--demoted-out")
    mode = a.mode if a.mode in ("off", "shadow", "on") else "off"
    bin_dir = os.path.dirname(os.path.abspath(__file__))
    head = (common.git(a.tree, "rev-parse", "--verify", "-q", "HEAD^{commit}") or b"").decode("ascii", "replace").strip()
    run_dir, keep = common.run_dir_of(a.run_id)

    lines, demoted, seen = [], [], set()
    asking = common.Asking(MAX_ASKED, common.budget(a.budget))
    for n, f in enumerate(findings, 1):
        fid = f.get("id") if isinstance(f, dict) else None
        label = fid if common.ascii_match(common.ID_RE, fid) else "#%d" % n
        if not common.ascii_match(common.ID_RE, fid) or fid in seen or not valid_entry(f):
            lines.append("S1_CONFIDENCE_RESULT=%s STATE=skipped REASON=invalid-finding" % label)
            continue
        seen.add(fid)
        reason = ineligible(f)
        if reason:
            lines.append("S1_CONFIDENCE_RESULT=%s STATE=skipped REASON=%s" % (fid, reason))
            continue
        try:
            data, more = finding_state.build(a.tree, f, head)
        except finding_state.Skip as e:
            lines.append("S1_CONFIDENCE_RESULT=%s STATE=skipped REASON=%s" % (fid, e.reason))
            continue
        extra = " TRUNCATED_LOCATIONS=1" if more else ""
        if asking.stop_reason:
            lines.append("S1_CONFIDENCE_RESULT=%s STATE=no-answer REASON=%s%s" % (fid, asking.stop_reason, extra))
            continue
        stopped = asking.check()
        if stopped:
            lines.append("S1_CONFIDENCE_RESULT=%s STATE=skipped REASON=%s%s" % (fid, stopped, extra))
            continue
        current = f.get("confidence") or "MEDIUM"
        rc, reply, reason = common.ask(a.run_id, bin_dir, data, current, common.finding_ref(a.ref_prefix, fid),
                                       asking.deadline, SITE, QUESTION)
        if not asking.record(reason):
            lines.append("S1_CONFIDENCE_RESULT=%s STATE=no-answer REASON=%s%s" % (fid, reason, extra))
            continue
        if keep and common.sent(rc, reason):
            common.keep_state(bin_dir, run_dir, "confidence-%s" % fid, data, fid)
        if reply is not None:
            verdict = "unsupported" if reply.p < 0.5 else "supported"
            if verdict == "unsupported" and mode == "on":
                demoted.append(fid)
            lines.append("S1_CONFIDENCE_RESULT=%s STATE=answered VERDICT=%s P=%r CONFIDENCE=%r MODEL=%s TRUNCATED=%d%s"
                         % (fid, verdict, reply.p, reply.confidence, reply.model,
                            1 if reply.truncated else 0, extra))
        else:
            lines.append("S1_CONFIDENCE_RESULT=%s STATE=no-answer REASON=%s%s" % (fid, reason, extra))

    lines += ["S1_CONFIDENCE_MODE=" + mode, "S1_ASKED=%d" % asking.asked]
    lines += asking.no_answer_lines("S1_NO_ANSWER_")
    lines.append("S1_DEMOTED=" + ",".join(demoted))
    # S1_DEMOTED_FILE is printed every time, empty when nothing was demoted,
    # so a path a session kept from an earlier review cycle is replaced.
    demoted_file = ""
    if a.demoted_out:
        if demoted:
            common.write_private(a.demoted_out, "".join(i + "\n" for i in demoted).encode("ascii"))
            demoted_file = a.demoted_out
        elif os.path.isfile(a.demoted_out) and not os.path.islink(a.demoted_out):
            # A file left by an earlier run must not be read as this run's.
            os.unlink(a.demoted_out)
    lines.append("S1_DEMOTED_FILE=" + demoted_file)
    sys.stdout.write("".join(line + "\n" for line in lines))
    return 0


if __name__ == "__main__":
    sys.exit(common.main(run, ("findings", "tree", "ref-prefix", "run-id", "mode", "demoted-out", "budget")))
