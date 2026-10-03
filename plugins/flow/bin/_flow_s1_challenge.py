"""The Python half of bin/flow-s1-challenge.sh: the System One decision point
review.challenge, which asks, on a Path A run of /flow:review, whether the
code a challenged finding cites contradicts it. The answer is a third voice
next to the challenger's: in on mode it is printed as a note to show with the
finding. It never changes a confidence, a disposition, routing or the review
decision, never drops a finding, and is never one of the two DISAGREE answers
that drop one.

flow-s1-challenge.sh resolves the mode and hands everything over as
arguments; this file reads no settings itself. Each finding is asked through
bin/flow-s1.sh, the client, which reads the provider settings, applies the
threshold in system-one/questions.yaml and writes the records. This file
holds no threshold of its own. The state is built by
bin/_flow_finding_state.py, the code behind bin/flow-finding-state.sh, so a
replay builds the same bytes. The request, the record of the state and the
security rule are those of bin/_flow_s1_confidence.py.

Which findings are asked (decided here from the finding, never by the
model), in this order:
  invalid-finding   not an object, a missing field, an id outside
                    ^[A-Za-z][A-Za-z0-9_-]*$, a repeated id, no reviewers, or
                    a disposition outside the controlled set
  consensus         both variants raised it (A.2): it skipped the challenge
  not-challenged    a reviewer that is not a Path A variant (a facet with
                    -skeptic or -verifier): holdout-validation, or a facet
                    re-dispatched on Path B
  then the state helper's reasons: no-line, path-refused, file-missing,
  line-out-of-range, not-text.
The same cap, budget and provider-down stop as review.confidence.

The challenger's answer is read from the disposition A.4 assigned:
validated AGREE, refined REFINE, kept DISAGREE, unchallenged none. The record's
`current` is <challenger answer>:<confidence>:<disposition>. Nothing of it is
in the state sent: the third voice is independent of the other two.

What an answer prints, in on mode only (the mode flow-s1-mode.sh --all
reports):
  exit 0, p < 0.5    ANSWER=dispute and a note saying the cited code
                     contradicts the finding
  exit 0, p >= 0.5   ANSWER=support and a note saying nothing in the cited
                     code contradicts it
  exit 3             no answer, no note
A security finding (the rule of review.confidence) is asked and recorded, but
its note is withheld. In shadow and off mode no note is printed, whatever the
answer. Every result line ends with the finding's own CONFIDENCE and
DISPOSITION, unchanged.
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
import json
import re
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _flow_finding_state as finding_state
import _flow_s1_confidence as s1

SITE = "review.challenge"
QUESTION = "finding_holds"
CHALLENGED = {"validated": "AGREE", "refined": "REFINE", "kept": "DISAGREE", "unchallenged": "none"}
DISPOSITIONS = tuple(CHALLENGED) + ("consensus",)
CONFIDENCES = ("HIGH", "MEDIUM", "LOW")
# The five agent facets of Path A; each runs as a skeptic and a verifier.
FACETS = ("code-reviewer", "convention-checker", "error-handler-inspector", "security-reviewer",
          "test-runner")
VARIANTS = frozenset(f + s for f in FACETS for s in ("-skeptic", "-verifier"))
CHECKED_UNSAFE = re.compile(r"[^A-Za-z0-9._/@+-]")


def echo(f):
    """The finding's own confidence and disposition, as they go in: only
    values of the controlled sets are printed."""
    conf = f.get("confidence") if isinstance(f, dict) else None
    disp = f.get("disposition") if isinstance(f, dict) else None
    return " CONFIDENCE=%s DISPOSITION=%s" % (conf if conf in CONFIDENCES else "",
                                              disp if disp in DISPOSITIONS else "")


def valid_entry(f):
    try:
        finding_state.check_finding(f)
    except finding_state.Skip:
        return False
    revs = f.get("reviewers")
    if not isinstance(revs, list) or not revs or not all(isinstance(r, str) and r for r in revs):
        return False
    return f.get("confidence") in CONFIDENCES and f.get("disposition") in DISPOSITIONS


def ineligible(f):
    if f["disposition"] == "consensus":
        return "consensus"
    if not all(r in VARIANTS for r in f["reviewers"]):
        return "not-challenged"
    return None


def checked(state_bytes):
    """<path>:<start>-<end>@<7-character head> for each window sent."""
    out = []
    for c in json.loads(state_bytes.decode("utf-8"))["code"]:
        out.append("%s:%d-%d@%s" % (CHECKED_UNSAFE.sub("?", c["path"])[:200], c["start"], c["end"],
                                    CHECKED_UNSAFE.sub("?", c["head"])[:7]))
    return ",".join(out)


def note(answer, where, reply):
    if answer == "dispute":
        text = "the cited code (%s) contradicts this finding" % where
    else:
        text = "nothing in the cited code (%s) contradicts this finding" % where
    return "System One: %s (confidence %r, %s)." % (text, reply["confidence"], reply["model"])


def run(a):
    try:
        with open(a.findings, encoding="utf-8") as f:
            findings = json.load(f)
    except (OSError, ValueError, RecursionError) as e:
        raise s1.Blocked("the findings file is not readable JSON (%s)" % type(e).__name__)
    if not isinstance(findings, list):
        raise s1.Blocked("the findings file is not a JSON list")
    if not s1.ascii_match(s1.REF_RE, a.ref_prefix) or len(a.ref_prefix) > 150:
        raise s1.Blocked("--ref-prefix must start with a letter or digit, use only letters, digits and . _ : / # @ + -, and be at most 150 characters")
    if a.run_id and (not s1.ascii_match(s1.RUN_ID_RE, a.run_id) or ".." in a.run_id):
        raise s1.Blocked("--run-id must start with a letter or digit and use only letters, digits, dot, underscore and dash, without ..")
    if not os.path.isdir(a.tree):
        raise s1.Blocked("--tree is not a directory")
    mode = a.mode if a.mode in ("off", "shadow", "on") else "off"
    limit = s1.budget(a.budget)
    bin_dir = os.path.dirname(os.path.abspath(__file__))
    head = (s1.git(a.tree, "rev-parse", "--verify", "-q", "HEAD^{commit}") or b"").decode("ascii", "replace").strip()
    top = (s1.git(".", "rev-parse", "--show-toplevel") or b"").decode("utf-8", "replace").strip()
    run_dir = os.path.join(top, ".flow", "runs", a.run_id) if (a.run_id and top) else ""
    keep = bool(run_dir) and os.path.isdir(run_dir) and not os.path.islink(run_dir)

    lines, seen = [], set()
    counts = {"answered": 0, "no-answer": 0, "skipped": 0}
    asked = 0
    down = 0
    stop_reason = None
    stopped = None
    started = time.monotonic()

    def result(label, state, rest, f):
        counts[state] += 1
        lines.append("S1_CHALLENGE_RESULT=%s STATE=%s %s%s" % (label, state, rest, echo(f)))

    for n, f in enumerate(findings, 1):
        fid = f.get("id") if isinstance(f, dict) else None
        label = fid if s1.ascii_match(s1.ID_RE, fid) else "#%d" % n
        if not s1.ascii_match(s1.ID_RE, fid) or fid in seen or not valid_entry(f):
            result(label, "skipped", "REASON=invalid-finding", f)
            continue
        seen.add(fid)
        reason = ineligible(f)
        if reason:
            result(fid, "skipped", "REASON=" + reason, f)
            continue
        try:
            data, more = finding_state.build(a.tree, f, head)
        except finding_state.Skip as e:
            result(fid, "skipped", "REASON=" + e.reason, f)
            continue
        extra = " TRUNCATED_LOCATIONS=1" if more else ""
        if stop_reason:
            result(fid, "no-answer", "REASON=" + stop_reason + extra, f)
            continue
        if not stopped:
            if asked >= s1.MAX_ASKED:
                stopped = "cap"
            elif time.monotonic() - started >= limit:
                stopped = "budget"
        if stopped:
            result(fid, "skipped", "REASON=" + stopped + extra, f)
            continue
        current = "%s:%s:%s" % (CHALLENGED[f["disposition"]], f["confidence"], f["disposition"])
        rc, reply, reason = s1.ask(a, bin_dir, data, current, s1.finding_ref(a.ref_prefix, fid),
                                   started + limit, site=SITE, question=QUESTION)
        if reason in s1.STOP_REASONS:
            stop_reason = reason
            result(fid, "no-answer", "REASON=" + reason + extra, f)
            continue
        asked += 1
        if keep and (rc == 0 or reason in s1.SENT_REASONS or (reason or "").startswith("http-")):
            s1.keep_state(bin_dir, run_dir, fid, data, prefix="challenge")
        down = down + 1 if reason in s1.DOWN_REASONS else 0
        if rc == 0:
            answer = "dispute" if reply["p"] < 0.5 else "support"
            where = checked(data)
            shown = mode == "on" and not s1.is_security(f)
            withheld = " NOTE=withheld" if (mode == "on" and not shown) else ""
            result(fid, "answered", "ANSWER=%s P=%r ANSWER_CONFIDENCE=%r MODEL=%s CHECKED=%s TRUNCATED=%d%s%s"
                   % (answer, reply["p"], reply["confidence"], reply["model"], where,
                      1 if reply["truncated"] else 0, extra, withheld), f)
            if shown:
                lines.append("S1_NOTE=%s %s" % (fid, note(answer, where, reply)))
        else:
            result(fid, "no-answer", "REASON=" + reason + extra, f)
        if down >= s1.MAX_CONSECUTIVE_DOWN:
            stopped = "provider-down"

    lines += ["S1_CHALLENGE_MODE=" + mode, "S1_ASKED=%d" % asked,
              "S1_CHALLENGE_SUMMARY=answered:%d no-answer:%d skipped:%d"
              % (counts["answered"], counts["no-answer"], counts["skipped"])]
    sys.stdout.write("".join(line + "\n" for line in lines))
    return 0


def main():
    ap = argparse.ArgumentParser()
    for name in ("findings", "tree", "ref-prefix", "run-id", "mode", "budget"):
        ap.add_argument("--" + name, default="")
    a = ap.parse_args()
    try:
        return run(a)
    except s1.Blocked as e:
        sys.stdout.write("STATE=blocked\nERROR=%s\n" % e)
        return 2
    except Exception as e:  # noqa: BLE001 - the review stays as it was, never a traceback
        sys.stdout.write("STATE=blocked\nERROR=internal error (%s)\n" % type(e).__name__)
        return 2


if __name__ == "__main__":
    sys.exit(main())
