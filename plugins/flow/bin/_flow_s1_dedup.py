"""The Python half of bin/flow-s1-dedup.sh: the System One decision point
review.dedup, which asks whether two consolidated review findings describe
the same defect, and merges the pairs a confident answer says are one.

flow-s1-dedup.sh resolves the mode and hands everything over as arguments;
this file reads no settings itself. Each pair is asked through bin/flow-s1.sh,
the client, which reads the provider settings, applies the threshold in
system-one/questions.yaml and writes the records. This file holds no threshold
of its own.

Which pairs are asked (the candidate rule): two findings in the same file,
both cited at a line or both about the whole file, whose reviewer sets are not
the same set (at least one reviewer raised one and not the other), each raised
only by schema reviewers (code-reviewer, error-handler-inspector,
integration-verifier, or one of them with -skeptic or -verifier), and neither a
security finding: no reviewer whose name contains "security", no id starting
SEC- or DEP-, and a category from the non-security list of
references/finding-schema.md or one of the error-handling sub-types
agents/error-handler-inspector.md tells that agent it may write. Synthesis
merges findings at one file:line and lists every reviewer, so most remaining
findings share a reviewer with the others; only an identical set is left out.
Pairs are asked in the order (file, line distance, id of a, id of b), a being
the finding earlier in the input. At most MAX_PAIRS are asked; the rest are
counted as unasked.

What an answer does, in on mode only (the mode flow-s1-mode.sh --all reports):
  exit 0, p >= 0.5   same. The pair may join a merge group, except a pair of
                     one LOW and one HIGH or MEDIUM finding, which is marked
                     related with why=mixed-confidence instead.
  exit 0, p < 0.5    different. Nothing changes.
  exit 3, below-threshold
                     unsure. Both findings are marked related, why=unsure.
  exit 3, any other  no answer. Nothing changes.
In shadow and off mode nothing changes, whatever the answer: the client checks
the threshold before the mode, so a shadow answer below the threshold exits 3
with below-threshold, and only the mode tells it apart from an unsure answer
in on mode.

Merge groups are formed after every answer is in, by complete linkage: the
"same" pairs are taken in the order they were asked, and two groups join only
when every pair across them answered "same". So a chain A~B, B~C with A~C
answered "different", not asked, or not answered never becomes one finding,
and two findings with the same reviewer set never end up in one group.
A group's representative is the member with the highest priority, then the
highest confidence (HIGH > MEDIUM > none), then the first in the input.

Counters partition the pairs asked: PAIRS_ASKED = PAIRS_SAME + PAIRS_DIFFERENT
+ PAIRS_RELATED + PAIRS_NO_ANSWER. PAIRS_RELATED counts unsure answers in on
mode; a mixed-confidence "same" counts in PAIRS_SAME and also prints a RELATED
line.
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
import posixpath
import re
import subprocess
import tempfile
import time

SITE = "review.dedup"
# At most this many pairs are asked in one review, in file order and nearest
# first within a file.
MAX_PAIRS = 24
# Stop asking after this many timeout or connection results in a row: the
# provider is down, and every further pair would wait for its timeout.
MAX_CONSECUTIVE_DOWN = 2
# Total time for asking, in seconds. 24 pairs at the default 3 s timeout fit
# inside it. No pair is asked after it, and a call still running when it ends
# is stopped CALL_MARGIN_S later, so asking ends within 95 s, before the 120 s
# a command's Bash call gets by default, whatever timeoutMs a local model
# needs. FLOW_S1_DEDUP_BUDGET_S may lower it, never raise it: a repository's
# .claude/settings.json can set environment variables.
MAX_BUDGET_S = 90
CALL_MARGIN_S = 5
# State limits, so a pair stays inside imajev's 32 KB without shortening.
MAX_TEXT = 2000
WINDOW_MARGIN = 20
WINDOW_MAX_LINES = 120
WINDOW_MAX_BYTES = 16384
# A cited file larger than this is not read, and its pairs get no code.
MAX_BLOB_BYTES = 8 * 1024 * 1024

ID_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*$")
REF_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/#@+-]*$")
LOCATION_RE = re.compile(r"^(.*):([0-9]+)(?:-[0-9]+)?$")
PRIORITY_RANK = {"P1": 3, "P2": 2, "P3": 1}
CONFIDENCE_RANK = {"HIGH": 2, "MEDIUM": 1, "": 0}
SCHEMA_REVIEWERS = ("code-reviewer", "error-handler-inspector", "integration-verifier")
# The non-security categories of references/finding-schema.md. A finding with
# any other category is treated as a security finding, as the record steps
# treat a grounding-pass drop (DROPPED_FINDING_BLOCK in commands/review.md).
NON_SECURITY = ("correctness", "edge-case", "error-handling", "performance", "tests", "runtime",
                "visual", "breaking-change", "duplication", "scope", "conventions",
                "claim-verification")
# The sub-types of error-handling that agents/error-handler-inspector.md tells
# that agent it may carry in the category. The dedup site accepts them as
# non-security; tests/e2e-review-dedup.test.sh reads the list from the agent
# definition and checks each one.
ERROR_SUBTYPES = ("unhandled-exception", "silent-failure", "swallowed-rescue", "missing-fallback")
ACCEPTED_CATEGORIES = NON_SECURITY + ERROR_SUBTYPES
# Reasons that send nothing and would be the same for every pair.
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


def load_findings(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError, RecursionError) as e:
        raise Blocked("the findings file is not readable JSON (%s)" % type(e).__name__)
    if not isinstance(data, list):
        raise Blocked("the findings file is not a JSON list")
    seen = set()
    for n, f in enumerate(data, 1):
        if not isinstance(f, dict):
            raise Blocked("entry %d is not an object" % n)
        fid = f.get("id")
        if not ascii_match(ID_RE, fid):
            raise Blocked("entry %d has no id matching ^[A-Za-z][A-Za-z0-9_-]*$" % n)
        if fid in seen:
            raise Blocked("id %s appears twice" % fid)
        seen.add(fid)
        if f.get("priority") not in PRIORITY_RANK:
            raise Blocked("%s has no priority P1, P2 or P3" % fid)
        for key in ("category", "location"):
            if not isinstance(f.get(key), str) or not f[key].strip():
                raise Blocked("%s has no %s" % (fid, key))
        if f.get("confidence", "") not in ("HIGH", "MEDIUM", "LOW", "", None):
            raise Blocked("%s has a confidence that is not HIGH, MEDIUM, LOW or empty" % fid)
        revs = f.get("reviewers")
        if not isinstance(revs, list) or not revs or not all(isinstance(r, str) and r for r in revs):
            raise Blocked("%s has no reviewers list" % fid)
        for key in ("problem", "suggested_fix"):
            if f.get(key) is not None and not isinstance(f[key], str):
                raise Blocked("%s has a %s that is not text" % (fid, key))
    return data


def confidence(f):
    return f.get("confidence") or ""


def parse_location(loc):
    """(file, line): line is the low end of a range, 0 for a whole file."""
    m = LOCATION_RE.match(loc)
    if m:
        return m.group(1), int(m.group(2))
    return loc, 0


def norm_file(path):
    p = path.replace("//", "/")
    while p.startswith("./"):
        p = p[2:]
    p = posixpath.normpath(p) if p else p
    return p


def safe_path(path):
    """The path may be read from the tree: relative, no .. segment, no
    backslash, no control character."""
    if not path or path.startswith("/") or "\\" in path:
        return False
    if any(ord(c) < 32 or ord(c) == 127 for c in path):
        return False
    return ".." not in path.split("/")


def is_security(f):
    if any("security" in r.lower() for r in f["reviewers"]):
        return True
    if f["id"].lower().startswith(("sec-", "dep-")):
        return True
    return f["category"].strip().lower() not in ACCEPTED_CATEGORIES


SCHEMA_NAMES = frozenset(base + suffix for base in SCHEMA_REVIEWERS for suffix in ("", "-skeptic", "-verifier"))


def schema_only(f):
    return all(r in SCHEMA_NAMES for r in f["reviewers"])


def candidates(findings):
    info = []
    for i, f in enumerate(findings):
        path, line = parse_location(f["location"])
        info.append((i, norm_file(path), line))
    pairs = []
    for ia, fa_path, la in info:
        fa = findings[ia]
        if is_security(fa) or not schema_only(fa):
            continue
        for ib, fb_path, lb in info[ia + 1:]:
            fb = findings[ib]
            if fa_path != fb_path or (la > 0) != (lb > 0):
                continue
            if set(fa["reviewers"]) == set(fb["reviewers"]):
                continue
            if is_security(fb) or not schema_only(fb):
                continue
            pairs.append((fa_path, abs(la - lb), fa["id"], fb["id"], ia, ib, la, lb))
    pairs.sort(key=lambda p: p[:4])
    return pairs


_EMPTY_TREE = {}


def git(tree, *args):
    """git -C <tree> <args>, stdout or None. The tree may be someone else's
    pull request: no repository it commits is loaded (safe.bareRepository)
    and none of its attributes apply (GIT_ATTR_SOURCE is the empty tree, in
    the tree's own object format), so no textconv or filter driver runs."""
    env = dict(os.environ)
    env.update({"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "safe.bareRepository",
                "GIT_CONFIG_VALUE_0": "explicit"})
    env.pop("GIT_ATTR_SOURCE", None)
    try:
        if tree not in _EMPTY_TREE:
            r = subprocess.run(["git", "-C", tree, "hash-object", "-t", "tree", os.devnull],
                               capture_output=True, env=env, timeout=30)
            _EMPTY_TREE[tree] = r.stdout.decode("ascii", "replace").strip() if r.returncode == 0 else ""
        if not _EMPTY_TREE[tree]:
            return None
        env["GIT_ATTR_SOURCE"] = _EMPTY_TREE[tree]
        r = subprocess.run(["git", "-C", tree, *args], capture_output=True, env=env, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout if r.returncode == 0 else None


# The last file read, as (tree, path, lines): pairs are asked in file order,
# so every pair of one file reads it once, and only one file is held.
_BLOB_CACHE: list[tuple[str, str, list[bytes] | None] | None] = [None]


def blob_lines(tree, path):
    """The lines of HEAD:<path> in the tree as bytes, split at newlines only,
    or None: not a blob, or larger than MAX_BLOB_BYTES."""
    cached = _BLOB_CACHE[0]
    if cached is not None and cached[0] == tree and cached[1] == path:
        return cached[2]
    lines = None
    spec = "HEAD:" + path
    kind = git(tree, "cat-file", "-t", spec)
    size = git(tree, "cat-file", "-s", spec) if kind is not None and kind.strip() == b"blob" else None
    if size is not None and size.strip().isdigit() and int(size) <= MAX_BLOB_BYTES:
        # cat-file prints the blob as stored: no textconv, no filter, and a
        # symlink is its target text, never the file it points to.
        blob = git(tree, "cat-file", "blob", spec)
        if blob is not None:
            lines = blob.split(b"\n")
            if lines and lines[-1] == b"":
                lines.pop()
    _BLOB_CACHE[0] = (tree, path, lines)
    return lines


def code_window(tree, head, path, la, lb):
    """The code sent with a pair. Empty for a path that is not safe, a file
    that is not a blob at HEAD, larger than MAX_BLOB_BYTES, or empty, and for
    a window holding a NUL byte or bytes that are not UTF-8, as the shared
    builder (bin/_flow_finding_state.py) refuses such a file with not-text.
    Lines are counted at newlines only, as git and the shared builder count
    them."""
    empty = {"head": head, "start": 0, "end": 0, "text": ""}
    if not head or not safe_path(path):
        return empty
    lines = blob_lines(tree, path)
    if not lines:
        return empty
    lo, hi = min(la, lb), max(la, lb)
    if lo <= 0:
        start, end = 1, WINDOW_MAX_LINES
    else:
        start = max(1, lo - WINDOW_MARGIN)
        end = hi + WINDOW_MARGIN
        if end - start + 1 > WINDOW_MAX_LINES:
            start = max(1, min(start, lo))
            end = start + WINDOW_MAX_LINES - 1
    end = min(end, len(lines))
    start = min(start, end)
    raw = lines[start - 1:end]
    if any(b"\0" in r for r in raw):
        return empty
    try:
        for r in raw:
            r.decode("utf-8")
    except UnicodeDecodeError:
        return empty
    # Keep the lines from the top that fit in WINDOW_MAX_BYTES, at least one;
    # a first line longer than that is cut at that size.
    kept, total = 1, len(raw[0])
    while kept < len(raw) and total + 1 + len(raw[kept]) <= WINDOW_MAX_BYTES:
        total += 1 + len(raw[kept])
        kept += 1
    end = start + kept - 1
    text = b"\n".join(raw[:kept])[:WINDOW_MAX_BYTES].decode("utf-8", "ignore")
    return {"head": head, "start": start, "end": end, "text": text}


def side(f):
    return {"location": f["location"], "category": f["category"],
            "problem": (f.get("problem") or "")[:MAX_TEXT],
            "suggested_fix": (f.get("suggested_fix") or "")[:MAX_TEXT]}


def pair_ref(prefix, a, b):
    ref = "%s/pair:%s+%s" % (prefix, a, b)
    if len(ref) > 200:
        digest = hashlib.sha256(("%s+%s" % (a, b)).encode("ascii")).hexdigest()[:16]
        ref = "%s/pair:%s" % (prefix, digest)
    return ref


def keep_state(bin_dir, run_dir, a, b, data):
    """Copy the state sent beside the run, never through a symlink."""
    keep = os.path.join(run_dir, "system-one-state")
    dest = os.path.join(keep, "dedup-%s+%s.json" % (a, b))
    try:
        r = subprocess.run([os.path.join(bin_dir, "flow-mkdir.sh"), "--", keep],
                           capture_output=True, timeout=30)
        if r.returncode != 0:
            raise OSError("flow-mkdir.sh refused")
        if os.path.islink(dest) or (os.path.exists(dest) and not os.path.isfile(dest)):
            raise OSError("not a regular file")
        fd, part = tempfile.mkstemp(prefix=".state.", dir=keep)
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(data)
            os.replace(part, dest)
        except BaseException:
            try:
                os.unlink(part)
            except OSError:
                pass
            raise
    except (OSError, subprocess.SubprocessError):
        sys.stderr.write("flow: WARN: the state for pair %s+%s could not be saved beside the run\n" % (a, b))


def ask(a, bin_dir, state_bytes, ref, deadline):
    """(exit status, p or None, reason or None). deadline is the
    time.monotonic() value the budget ends at: the call is stopped
    CALL_MARGIN_S after it."""
    fd, path = tempfile.mkstemp(prefix="flow-s1-dedup.", suffix=".json")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(state_bytes)
        cmd = [os.path.join(bin_dir, "flow-s1.sh"), "ask", "--site", SITE, "--state-file", path,
               "--state-format", "json", "--current", "separate", "--ref", ref]
        if a.run_id:
            cmd += ["--run-id", a.run_id]
        try:
            r = subprocess.run(cmd, capture_output=True,
                               timeout=max(deadline - time.monotonic(), 0) + CALL_MARGIN_S)
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
            p = json.loads(r.stdout.decode("utf-8"))["answers"]["same_defect"]["p"]
        except (ValueError, KeyError, TypeError):
            return 3, None, "client-error"
        if isinstance(p, bool) or not isinstance(p, (int, float)):
            return 3, None, "client-error"
        return 0, float(p), None
    m = NO_ANSWER_RE.search(err)
    return 3, None, (m.group(1) if (r.returncode == 3 and m) else "client-error")


def budget(raw):
    if raw.isascii() and raw.isdigit() and len(raw) <= 9:
        return min(max(int(raw), 1), MAX_BUDGET_S)
    return MAX_BUDGET_S


def merge(findings, pairs_same, mixed, unsure):
    """The finding set after merges and related marks (on mode)."""
    index = {f["id"]: i for i, f in enumerate(findings)}
    same_set = {frozenset(p) for p in pairs_same}
    group_of = {f["id"]: [f["id"]] for f in findings}
    for x, y in pairs_same:
        gx, gy = group_of[x], group_of[y]
        if gx is gy:
            continue
        # Every pair across the two groups answered "same", so every pair was
        # a candidate: no two members share a reviewer set or a security
        # finding.
        if not all(frozenset((u, v)) in same_set for u in gx for v in gy):
            continue
        joined = sorted(gx + gy, key=lambda m: index[m])
        for m in joined:
            group_of[m] = joined
    related = {}
    for (x, y), why in [(p, "unsure") for p in unsure] + [(p, "mixed-confidence") for p in mixed]:
        related.setdefault(x, []).append({"id": y, "why": why})
        related.setdefault(y, []).append({"id": x, "why": why})

    def rank(fid):
        f = findings[index[fid]]
        return (-PRIORITY_RANK[f["priority"]], -CONFIDENCE_RANK.get(confidence(f), 0), index[fid])

    rep_of, groups = {}, []
    for f in findings:
        g = group_of[f["id"]]
        if g[0] != f["id"]:
            continue
        rep = min(g, key=rank)
        for m in g:
            rep_of[m] = rep
        if len(g) > 1:
            groups.append((rep, [m for m in g if m != rep]))
    out = []
    for f in findings:
        fid = f["id"]
        if rep_of[fid] != fid:
            continue
        g = group_of[fid]
        new = dict(f)
        if len(g) > 1:
            members = [findings[index[m]] for m in g]
            locs = [f["location"]]
            for m in members:
                if m["location"] not in locs:
                    locs.append(m["location"])
            revs = list(f["reviewers"])
            for m in members:
                for r in m["reviewers"]:
                    if r not in revs:
                        revs.append(r)
            new["locations"] = locs
            new["reviewers"] = revs
            new["also_reported_as"] = [
                {"id": m["id"], "reviewers": m["reviewers"], "location": m["location"],
                 "priority": m["priority"], "problem": m.get("problem") or ""}
                for m in members if m["id"] != fid]
            # A caution mark on any member stays on what represents it.
            for m in members:
                if m["id"] != fid and m.get("disputed") and not new.get("disputed"):
                    new["disputed"] = m["disputed"]
        marks = []
        for m in g:
            for entry in related.get(m, []):
                target = rep_of[entry["id"]]
                if target == fid:
                    continue
                e = {"id": target, "why": entry["why"]}
                if e not in marks:
                    marks.append(e)
        if marks:
            new["related"] = list(f.get("related") or []) + [e for e in marks if e not in (f.get("related") or [])]
        out.append(new)
    return out, groups


def run(a):
    findings = load_findings(a.findings)
    if not ascii_match(REF_RE, a.ref_prefix) or len(a.ref_prefix) > 178:
        # 178: the prefix with /pair:<16 hex> stays within the 200 characters
        # flow-s1.sh takes.
        raise Blocked("--ref-prefix must start with a letter or digit, use only letters, digits and . _ : / # @ + -, and be at most 178 characters")
    if a.run_id and (not ascii_match(re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$"), a.run_id) or ".." in a.run_id):
        raise Blocked("--run-id must start with a letter or digit and use only letters, digits, dot, underscore and dash, without ..")
    if not os.path.isdir(a.tree):
        raise Blocked("--tree is not a directory")
    mode = a.mode if a.mode in ("off", "shadow", "on") else "off"
    limit = budget(a.budget)
    bin_dir = os.path.dirname(os.path.abspath(__file__))
    pairs = candidates(findings)
    lines = []
    counts = {"same": 0, "different": 0, "related": 0, "none": 0}
    reasons = {}
    asked = 0
    stop_reason = None
    stopped = None
    pairs_same, mixed, unsure, merged_lines, related_lines = [], [], [], [], []

    if not pairs:
        lines += ["DEDUP_STATE=skipped", "REASON=no-candidates"]
    else:
        head = (git(a.tree, "rev-parse", "--verify", "-q", "HEAD^{commit}") or b"").decode("ascii", "replace").strip()
        top = (git(".", "rev-parse", "--show-toplevel") or b"").decode("utf-8", "replace").strip()
        run_dir = os.path.join(top, ".flow", "runs", a.run_id) if (a.run_id and top) else ""
        keep = bool(run_dir) and os.path.isdir(run_dir) and not os.path.islink(run_dir)
        started = time.monotonic()
        down = 0
        for n, (path, _dist, ida, idb, ia, ib, la, lb) in enumerate(pairs):
            if n >= MAX_PAIRS:
                stopped = stopped or "max-pairs"
                break
            if time.monotonic() - started >= limit:
                stopped = "budget"
                break
            fa, fb = findings[ia], findings[ib]
            state = {"file": path, "a": side(fa), "b": side(fb),
                     "code": code_window(a.tree, head, path, la, lb)}
            data = json.dumps(state, ensure_ascii=False, sort_keys=True).encode("utf-8")
            rc, p, reason = ask(a, bin_dir, data, pair_ref(a.ref_prefix, ida, idb), started + limit)
            if reason in STOP_REASONS:
                stop_reason = reason
                break
            asked += 1
            if keep and (rc == 0 or reason in SENT_REASONS or (reason or "").startswith("http-")):
                keep_state(bin_dir, run_dir, ida, idb, data)
            down = down + 1 if reason in DOWN_REASONS else 0
            low_a, low_b = confidence(fa) == "LOW", confidence(fb) == "LOW"
            if p is not None and p >= 0.5:
                counts["same"] += 1
                if mode == "on":
                    if low_a != low_b:
                        mixed.append((ida, idb))
                    else:
                        pairs_same.append((ida, idb))
            elif p is not None:
                counts["different"] += 1
            elif reason == "below-threshold" and mode == "on":
                counts["related"] += 1
                unsure.append((ida, idb))
            else:
                counts["none"] += 1
                reasons[reason] = reasons.get(reason, 0) + 1
            if down >= MAX_CONSECUTIVE_DOWN:
                stopped = "provider-down"
                break
        if asked == 0 and stop_reason:
            lines += ["DEDUP_STATE=no-answer", "REASON=" + stop_reason]
        else:
            lines.append("DEDUP_STATE=answered")
            if stop_reason:
                stopped = stop_reason

    out = findings
    groups = []
    if mode == "on" and (pairs_same or mixed or unsure):
        out, groups = merge(findings, pairs_same, mixed, unsure)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
        f.write("\n")

    lines += ["MODE=" + mode, "BUDGET_S=%d" % limit,
              "FINDINGS_IN=%d" % len(findings), "FINDINGS_OUT=%d" % len(out),
              "PAIRS_CANDIDATE=%d" % len(pairs), "PAIRS_ASKED=%d" % asked,
              "PAIRS_SAME=%d" % counts["same"], "PAIRS_DIFFERENT=%d" % counts["different"],
              "PAIRS_RELATED=%d" % counts["related"], "PAIRS_NO_ANSWER=%d" % counts["none"]]
    for reason in sorted(reasons):
        lines.append("NO_ANSWER_%s=%d" % (reason.upper().replace("-", "_"), reasons[reason]))
    lines.append("UNASKED=%d" % (len(pairs) - asked))
    if stopped:
        lines.append("STOPPED=" + stopped)
    for rep, absorbed in groups:
        merged_lines.append("MERGED=" + "+".join([rep] + absorbed))
    for x, y in unsure + mixed:
        related_lines.append("RELATED=%s+%s" % (x, y))
    lines += merged_lines + related_lines
    lines.append("DEDUP_OUT=" + a.out)
    sys.stdout.write("".join(line + "\n" for line in lines))
    return 0


def main():
    ap = argparse.ArgumentParser()
    for name in ("findings", "out", "tree", "ref-prefix", "run-id", "mode", "budget"):
        ap.add_argument("--" + name, default="")
    a = ap.parse_args()
    try:
        return run(a)
    except Blocked as e:
        sys.stdout.write("STATE=blocked\nERROR=%s\n" % e)
        return 2
    except Exception as e:  # noqa: BLE001 - the caller keeps its finding set, never a traceback
        sys.stdout.write("STATE=blocked\nERROR=internal error (%s)\n" % type(e).__name__)
        return 2


if __name__ == "__main__":
    sys.exit(main())
