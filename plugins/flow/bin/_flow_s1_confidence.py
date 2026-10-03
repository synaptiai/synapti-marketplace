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
At most MAX_ASKED findings are asked; asking also stops after
MAX_CONSECUTIVE_DOWN timeout or connection results in a row, and once the
budget (MAX_BUDGET_S seconds, or fewer with --budget) has passed; a call
still running then is stopped CALL_MARGIN_S later. A finding not asked for
these reasons is skipped with REASON=cap, provider-down or budget.

What an answer does, in on mode only (the mode flow-s1-mode.sh --all reports):
  exit 0, p < 0.5    unsupported: the finding is demoted to LOW
  exit 0, p >= 0.5   supported: nothing changes; an answer never raises a
                     confidence
  exit 3             no answer: nothing changes
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

import argparse
import hashlib
import json
import re
import subprocess
import tempfile
import time
from typing import TypedDict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _flow_finding_state as finding_state

SITE = "review.confidence"
QUESTION = "claim_supported"
MAX_ASKED = 25
MAX_CONSECUTIVE_DOWN = 2
# Total time for asking, in seconds. No call starts after it, and a call
# still running when it ends is stopped CALL_MARGIN_S later, so asking ends
# within 95 s, before the 120 s a command's Bash call gets by default,
# whatever timeoutMs a local model needs. FLOW_S1_CONFIDENCE_BUDGET_S (and
# FLOW_S1_CHALLENGE_BUDGET_S for review.challenge) may lower it, never raise
# it: a repository's .claude/settings.json can set environment variables.
MAX_BUDGET_S = 90
CALL_MARGIN_S = 5

ID_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*$")
REF_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/#@+-]*$")
RUN_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
MODEL_UNSAFE = re.compile(r"[^A-Za-z0-9._:/@+-]")
# The non-security categories of references/finding-schema.md, and the
# grounding pass's security categories (commands/review.md). The same rule
# DROPPED_FINDING_BLOCK and review.dedup apply.
NON_SECURITY = ("correctness", "edge-case", "error-handling", "performance", "tests", "runtime",
                "visual", "breaking-change", "duplication", "scope", "conventions",
                "claim-verification")
SECURITY = ("security", "dependency", "auth", "injection", "xss", "idor", "secrets")
# Reasons that send nothing and would be the same for every finding.
STOP_REASONS = ("settings-refused", "provider-none", "python-missing", "mode-off",
                "invalid-settings", "insecure-url", "no-api-key", "unknown-site",
                "no-threshold", "questions-invalid")
DOWN_REASONS = ("timeout", "connection")
# Reasons for which a request reached the provider, so the state is kept.
SENT_REASONS = ("shadow", "below-threshold", "timeout", "connection", "redirect", "malformed",
                "missing-answer", "abstained")
NO_ANSWER_RE = re.compile(r"^flow-s1: no answer: ([a-z0-9-]+)", re.M)


class Blocked(Exception):
    pass


def ascii_match(rx, s):
    return isinstance(s, str) and s.isascii() and rx.match(s) is not None


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


def git(tree, *args):
    """git -C <tree> <args>, stdout or None. The tree may be someone else's
    pull request: no repository it commits is loaded (safe.bareRepository)
    and none of its attributes apply (GIT_ATTR_SOURCE is the empty tree, in
    the tree's own object format). The same environment review.dedup uses."""
    env = dict(os.environ)
    env.update({"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "safe.bareRepository",
                "GIT_CONFIG_VALUE_0": "explicit"})
    env.pop("GIT_ATTR_SOURCE", None)
    try:
        r = subprocess.run(["git", "-C", tree, "hash-object", "-t", "tree", os.devnull],
                           capture_output=True, env=env, timeout=30)
        empty = r.stdout.decode("ascii", "replace").strip() if r.returncode == 0 else ""
        if not empty:
            return None
        env["GIT_ATTR_SOURCE"] = empty
        r = subprocess.run(["git", "-C", tree, *args], capture_output=True, env=env, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout if r.returncode == 0 else None


def finding_ref(prefix, fid):
    ref = "%s/%s" % (prefix, fid)
    if len(ref) > 200:
        ref = "%s/id:%s" % (prefix, hashlib.sha256(fid.encode("ascii")).hexdigest()[:16])
    return ref


def write_private(path, data):
    """Write data to path through a temporary file in the same directory,
    never through a symlink."""
    d = os.path.dirname(os.path.abspath(path))
    if os.path.islink(path) or (os.path.exists(path) and not os.path.isfile(path)):
        raise OSError("not a regular file")
    fd, part = tempfile.mkstemp(prefix=".part.", dir=d)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.replace(part, path)
    except BaseException:
        try:
            os.unlink(part)
        except OSError:
            pass
        raise


def keep_state(bin_dir, run_dir, fid, data, prefix="confidence"):
    """Copy the state sent beside the run, never through a symlink, as
    <prefix>-<id>.json (review.challenge passes its own prefix)."""
    keep = os.path.join(run_dir, "system-one-state")
    try:
        r = subprocess.run([os.path.join(bin_dir, "flow-mkdir.sh"), "--", keep],
                           capture_output=True, timeout=30)
        if r.returncode != 0:
            raise OSError("flow-mkdir.sh refused")
        write_private(os.path.join(keep, "%s-%s.json" % (prefix, fid)), data)
    except (OSError, subprocess.SubprocessError):
        sys.stderr.write("flow: WARN: the state for %s could not be saved beside the run\n" % fid)


def budget(raw):
    """The budget in whole seconds, 1 to MAX_BUDGET_S; any other value is
    MAX_BUDGET_S."""
    if raw.isascii() and raw.isdigit() and len(raw) <= 9:
        return min(max(int(raw), 1), MAX_BUDGET_S)
    return MAX_BUDGET_S


def call_timeout(deadline):
    """Seconds one flow-s1.sh call may take: what is left of the budget plus
    CALL_MARGIN_S, so the last call cannot run past the budget by more."""
    return max(deadline - time.monotonic(), 0) + CALL_MARGIN_S


class Reply(TypedDict):
    p: float
    confidence: float
    model: str
    truncated: bool


def ask(a, bin_dir, state_bytes, current, ref, deadline, site=SITE,
        question=QUESTION) -> tuple[int, Reply | None, str | None]:
    """(exit status, reply or None, reason or None). deadline is the
    time.monotonic() value the budget ends at. review.challenge passes its
    own site and question."""
    fd, path = tempfile.mkstemp(prefix="flow-s1-%s." % site.split(".")[-1], suffix=".json")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(state_bytes)
        cmd = [os.path.join(bin_dir, "flow-s1.sh"), "ask", "--site", site, "--state-file", path,
               "--state-format", "json", "--current", current, "--ref", ref]
        if a.run_id:
            cmd += ["--run-id", a.run_id]
        try:
            r = subprocess.run(cmd, capture_output=True, timeout=call_timeout(deadline))
        except subprocess.TimeoutExpired:
            return 3, None, "timeout"
        except OSError:
            return 3, None, "internal-error"
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass
    err = r.stderr.decode("utf-8", "replace")
    if err:
        sys.stderr.write(err)
    if r.returncode == 0:
        try:
            reply = json.loads(r.stdout.decode("utf-8"))
            p = reply["answers"][question]["p"]
            conf = reply["answers"][question]["confidence"]
        except (ValueError, KeyError, TypeError):
            return 3, None, "client-error"
        if isinstance(p, bool) or not isinstance(p, (int, float)) \
                or isinstance(conf, bool) or not isinstance(conf, (int, float)):
            return 3, None, "client-error"
        answer: Reply = {"p": float(p), "confidence": float(conf),
                         "model": MODEL_UNSAFE.sub("?", str(reply.get("model") or ""))[:200] or "unknown",
                         "truncated": reply.get("truncated") is True}
        return 0, answer, None
    m = NO_ANSWER_RE.search(err)
    return 3, None, (m.group(1) if (r.returncode == 3 and m) else "client-error")


def run(a):
    try:
        with open(a.findings, encoding="utf-8") as f:
            findings = json.load(f)
    except (OSError, ValueError, RecursionError) as e:
        raise Blocked("the findings file is not readable JSON (%s)" % type(e).__name__)
    if not isinstance(findings, list):
        raise Blocked("the findings file is not a JSON list")
    if not ascii_match(REF_RE, a.ref_prefix) or len(a.ref_prefix) > 150:
        raise Blocked("--ref-prefix must start with a letter or digit, use only letters, digits and . _ : / # @ + -, and be at most 150 characters")
    if a.run_id and (not ascii_match(RUN_ID_RE, a.run_id) or ".." in a.run_id):
        raise Blocked("--run-id must start with a letter or digit and use only letters, digits, dot, underscore and dash, without ..")
    if not os.path.isdir(a.tree):
        raise Blocked("--tree is not a directory")
    mode = a.mode if a.mode in ("off", "shadow", "on") else "off"
    limit = budget(a.budget)
    bin_dir = os.path.dirname(os.path.abspath(__file__))
    head = (git(a.tree, "rev-parse", "--verify", "-q", "HEAD^{commit}") or b"").decode("ascii", "replace").strip()
    top = (git(".", "rev-parse", "--show-toplevel") or b"").decode("utf-8", "replace").strip()
    run_dir = os.path.join(top, ".flow", "runs", a.run_id) if (a.run_id and top) else ""
    keep = bool(run_dir) and os.path.isdir(run_dir) and not os.path.islink(run_dir)

    lines, demoted, seen = [], [], set()
    asked = 0
    down = 0
    stop_reason = None
    stopped = None
    started = time.monotonic()
    for n, f in enumerate(findings, 1):
        fid = f.get("id") if isinstance(f, dict) else None
        label = fid if ascii_match(ID_RE, fid) else "#%d" % n
        if not ascii_match(ID_RE, fid) or fid in seen or not valid_entry(f):
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
        if stop_reason:
            lines.append("S1_CONFIDENCE_RESULT=%s STATE=no-answer REASON=%s%s" % (fid, stop_reason, extra))
            continue
        if not stopped:
            if asked >= MAX_ASKED:
                stopped = "cap"
            elif time.monotonic() - started >= limit:
                stopped = "budget"
        if stopped:
            lines.append("S1_CONFIDENCE_RESULT=%s STATE=skipped REASON=%s%s" % (fid, stopped, extra))
            continue
        current = f.get("confidence") or "MEDIUM"
        rc, reply, reason = ask(a, bin_dir, data, current, finding_ref(a.ref_prefix, fid), started + limit)
        if reason in STOP_REASONS:
            stop_reason = reason
            lines.append("S1_CONFIDENCE_RESULT=%s STATE=no-answer REASON=%s%s" % (fid, reason, extra))
            continue
        asked += 1
        if keep and (rc == 0 or reason in SENT_REASONS or (reason or "").startswith("http-")):
            keep_state(bin_dir, run_dir, fid, data)
        down = down + 1 if reason in DOWN_REASONS else 0
        if rc == 0 and reply is not None:
            verdict = "unsupported" if reply["p"] < 0.5 else "supported"
            if verdict == "unsupported" and mode == "on":
                demoted.append(fid)
            lines.append("S1_CONFIDENCE_RESULT=%s STATE=answered VERDICT=%s P=%r CONFIDENCE=%r MODEL=%s TRUNCATED=%d%s"
                         % (fid, verdict, reply["p"], reply["confidence"], reply["model"],
                            1 if reply["truncated"] else 0, extra))
        else:
            lines.append("S1_CONFIDENCE_RESULT=%s STATE=no-answer REASON=%s%s" % (fid, reason, extra))
        if down >= MAX_CONSECUTIVE_DOWN:
            stopped = "provider-down"

    lines += ["S1_CONFIDENCE_MODE=" + mode, "S1_ASKED=%d" % asked, "S1_DEMOTED=" + ",".join(demoted)]
    if a.demoted_out:
        if demoted:
            write_private(a.demoted_out, "".join(i + "\n" for i in demoted).encode("ascii"))
            lines.append("S1_DEMOTED_FILE=" + a.demoted_out)
        elif os.path.isfile(a.demoted_out) and not os.path.islink(a.demoted_out):
            # A file left by an earlier run must not be read as this run's.
            os.unlink(a.demoted_out)
    sys.stdout.write("".join(line + "\n" for line in lines))
    return 0


def main():
    ap = argparse.ArgumentParser()
    for name in ("findings", "tree", "ref-prefix", "run-id", "mode", "demoted-out", "budget"):
        ap.add_argument("--" + name, default="")
    a = ap.parse_args()
    try:
        return run(a)
    except Blocked as e:
        sys.stdout.write("STATE=blocked\nERROR=%s\n" % e)
        return 2
    except Exception as e:  # noqa: BLE001 - the caller keeps its confidences, never a traceback
        sys.stdout.write("STATE=blocked\nERROR=internal error (%s)\n" % type(e).__name__)
        return 2


if __name__ == "__main__":
    sys.exit(main())
