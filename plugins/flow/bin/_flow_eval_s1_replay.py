"""The Python half of bin/flow-eval-s1-replay.sh: the review-precision eval's
replay of the System One sites review.dedup and review.confidence over the
findings a review run reported (references/review-precision-eval.md, "System
One filters").

Every decision is made by the shipped scripts: flow-s1-dedup.sh,
flow-s1-confidence.sh and the client flow-s1.sh they call, run from a copy of
this plugin outside every scratch tree. This file builds the trees, converts
the findings, runs the passes, serves the recorded answers back, and scores.

Subcommands (each prints KEY=value lines):
  export-recovered  findings files from the 2026-09-25 session transcripts,
                    each finding credited to every subagent that cites its
                    exact line, and whether they can test review.dedup
  convert           one session findings list to the site scripts' input
  score             score-review on one findings file, with the replay flags
  trees             build each case and trap's scratch tree with pinned
                    commit dates, record or check its HEAD
  shadow            one pass against a real provider in shadow mode: every
                    pair and finding asked once, records and states kept
  table             the recorded answer of every kept state, keyed by the
                    state as the provider received it
  serve             the replay server alone (the on pass starts its own)
  on                one pass in on mode (or off) at one threshold point,
                    answered by the replay server
  inspect           merged-pairs.json: one row per merged pair, for a label
  aggregate         the checks, the score tables and the verdict

Layout: findings in <findings>/<model>/<arm>/<case>/<trap>/<n>.json; scratch
trees and plugin copies in <work>; everything kept in <replay>: trees.json,
shadow/<set>/..., table.json, on/<point>/..., merged-pairs.json, report.json,
report.md.
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
import glob
import hashlib
import json
import re
import shutil
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

BIN_DIR = os.path.dirname(os.path.abspath(__file__))
PLUGIN_ROOT = os.path.dirname(BIN_DIR)
sys.path.insert(0, BIN_DIR)
import _flow_eval as fe
import _flow_s1_dedup as s1_dedup

PINNED = "jev-1.13.0"
DEDUP, CONFIDENCE = "review.dedup", "review.confidence"
QUESTION = {DEDUP: "same_defect", CONFIDENCE: "claim_supported"}
# The commit date every scratch tree is built with, so a rebuild has the same
# HEAD and the same state bytes.
FIXED_DATE = "2026-10-03T00:00:00+0000"
# Far above any state the two sites build (a dedup state is at most two 2000-
# character texts and a 16 KB window; a confidence state three 16 KB
# windows), so the client never shortens one and the replay server always
# receives the state that was kept.
STATE_TOKEN_CAP = 1000000
# The reasons that send nothing and would be the same for every pair or
# finding (the scripts' STOP_REASONS).
STOP_REASONS = ("settings-refused", "provider-none", "python-missing", "mode-off",
                "invalid-settings", "insecure-url", "no-api-key", "unknown-site",
                "no-threshold", "questions-invalid")
UNASKED_REASONS = ("cap", "budget", "provider-down")
ID_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*$")
# The check statuses that let a verdict stand. Any other (flagged, or a check
# that did not run) holds it.
CHECK_PASSES = ("ok", "not-exercised")


class Failed(Exception):
    pass


def out(key, value):
    sys.stdout.write("%s=%s\n" % (key, value))


def read_json(path, default=None):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def write_json(path, obj):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    fe.write_json(path, obj)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def state_key(state):
    """The key of a state as the provider receives it: the client parses the
    kept file and sends the value, so the file's own bytes (the record's
    state_sha256) cannot be recomputed from a request. Both sides serialize
    the value the same way instead."""
    return hashlib.sha256(canonical(state).encode("utf-8")).hexdigest()


def fmt_t(value):
    return "%g" % float(value)


# ----------------------------------------------------------------- runs

class Run:
    def __init__(self, model, arm, case, trap, n, path):
        self.model, self.arm, self.case, self.trap, self.n, self.path = model, arm, case, trap, n, path

    @property
    def key(self):
        return "/".join((self.model, self.arm, self.case, self.trap, str(self.n)))

    @property
    def run_id(self):
        rid = re.sub(r"[^A-Za-z0-9._-]", "_", "-".join((self.model, self.arm, self.case, self.trap, str(self.n))))
        rid = rid.replace("..", "_")
        return rid if rid[:1].isalnum() else "r" + rid

    @property
    def ref(self):
        ref = "eval:%s/%s/%s/%d" % (self.model, self.case, self.trap, self.n)
        ref = re.sub(r"[^A-Za-z0-9._:/#@+-]", "_", ref)
        if len(ref) > 140:
            ref = "eval:" + hashlib.sha256(self.key.encode("utf-8")).hexdigest()[:16]
        return ref


def iter_runs(findings_dir):
    runs = []
    for path in glob.glob(os.path.join(findings_dir, "*", "*", "*", "*", "*.json")):
        rel = os.path.relpath(path, findings_dir).split(os.sep)
        name = rel[-1][:-5]
        if len(rel) != 5 or not name.isdigit():
            continue
        runs.append(Run(rel[0], rel[1], rel[2], rel[3], int(name), path))
    runs.sort(key=lambda r: (r.model, r.arm, r.case, r.trap, r.n))
    return runs


def case_dir(evals, case):
    return os.path.join(evals, case)


# ----------------------------------------------------------------- conversion

def convert(findings):
    """(schema findings, dropped). Each finding the session reported becomes
    the shape the site scripts take: location <file>:<line>, reviewers
    without the plugin prefix, and a value for every field they require. An
    entry that is not an object, or has no priority P1 to P3, is dropped: the
    scorer ignores both."""
    result, used, dropped = [], set(), 0
    if not isinstance(findings, list):
        return result, 0
    for n, f in enumerate(findings, 1):
        if not isinstance(f, dict):
            dropped += 1
            continue
        priority = str(f.get("priority", "")).strip().upper()
        if priority not in ("P1", "P2", "P3"):
            dropped += 1
            continue
        fid = f.get("id") if isinstance(f.get("id"), str) else ""
        if not ID_RE.match(fid or ""):
            fid = "F%d" % n
        base, k = fid, 2
        while fid in used:
            fid = "%s-%d" % (base, k)
            k += 1
        used.add(fid)
        raw_location = f.get("location")
        location = raw_location if isinstance(raw_location, str) else ""
        if not location.strip():
            path = str(f.get("file") or "").strip()
            raw = f.get("line")
            line = fe.finding_line(raw)
            rng = re.match(r"^\s*(\d+)\s*-\s*(\d+)\s*$", raw) if isinstance(raw, str) else None
            if not path:
                location = "unknown"
            elif rng:
                location = "%s:%s-%s" % (path, rng.group(1), rng.group(2))
            elif line:
                location = "%s:%d" % (path, line)
            else:
                location = path
        reviewers = [fe.agent_name(r) for r in (f.get("reviewers") or []) if isinstance(r, str) and r.strip()]
        confidence = str(f.get("confidence") or "").strip().upper()
        result.append({
            "id": fid,
            "priority": priority,
            "category": str(f.get("category") or "").strip() or "uncategorized",
            "location": location.strip(),
            "problem": str(f.get("problem") or ""),
            "suggested_fix": str(f.get("suggested_fix") or ""),
            "confidence": confidence if confidence in ("HIGH", "MEDIUM", "LOW") else "",
            "disposition": "unchallenged",
            "reviewers": reviewers or ["unattributed"],
        })
    return result, dropped


def cmd_convert(a):
    findings = read_json(a.input)
    result, dropped = convert(findings)
    write_json(a.out, result)
    out("CONVERT_IN", len(findings) if isinstance(findings, list) else 0)
    out("CONVERT_OUT", len(result))
    out("CONVERT_DROPPED", dropped)
    return 0


def cmd_score(a):
    record = fe.score_review(case_dir(a.evals, a.case), a.trap, fe.read_text(a.findings),
                             any_location=a.any_location, exclude_low=a.exclude_low,
                             demoted=fe.read_demoted(a.demoted))
    sys.stdout.write(json.dumps(record, sort_keys=True) + "\n")
    return 0


# ----------------------------------------------------------------- export of the recovered runs

def assistant_texts(path):
    """The text of every assistant message in a transcript, in order."""
    texts = []
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return texts
    with fh:
        for line in fh:
            try:
                event = json.loads(line)
            except ValueError:
                continue
            if not isinstance(event, dict) or event.get("type") != "assistant":
                continue
            message = event.get("message")
            content = message.get("content") if isinstance(message, dict) else None
            if isinstance(content, str):
                parts = [content]
            elif isinstance(content, list):
                parts = [b.get("text") for b in content if isinstance(b, dict) and b.get("type") == "text"]
            else:
                parts = []
            text = "\n".join(p for p in parts if isinstance(p, str))
            if text.strip():
                texts.append(text)
    return texts


def cited_lines(text, module):
    """The lines of the module a subagent's report cites by an explicit
    <module>.py:<line> (or <module>:<line>, with any directory before it).
    A range (<module>.py:46-48) cites no line, and neither does prose such as
    "line 47": a finding is credited only to the subagents that name its exact
    line. A column after the line (<module>.py:47:5) still cites line 47."""
    pat = re.compile(r"(?<![\w./-])(?:[\w.-]+/)*%s(?:\.py)?:(\d+)(?!\d)(?!\s*[-\u2013]\s*\d)" % re.escape(module))
    return {int(m.group(1)) for m in pat.finditer(text)}


# More than half the findings carrying four or more reviewers, or more than
# half the runs without a candidate pair, means the recovered findings cannot
# exercise review.dedup: its candidate rule pairs only findings whose
# reviewers are all schema reviewers, with reviewer lists that differ.
MANY_REVIEWERS = 4


def dedup_half(per_finding, runs_without_pairs, runs):
    """("exercised" or "not-exercised", reason) for the recovered findings."""
    total = sum(per_finding.values())
    many = sum(v for k, v in per_finding.items() if k >= MANY_REVIEWERS)
    reasons = []
    if total and many * 2 > total:
        reasons.append("%d of %d findings carry %d or more reviewers" % (many, total, MANY_REVIEWERS))
    if runs and runs_without_pairs * 2 > runs:
        reasons.append("%d of %d runs have no dedup candidate pair" % (runs_without_pairs, runs))
    if reasons:
        return "not-exercised", "; ".join(reasons)
    return "exercised", ""


def cmd_export_recovered(a):
    records = read_json(a.runs_json)
    if not isinstance(records, list):
        raise Failed("--runs-json is not a JSON list")
    exported = findings_n = attributed = unattributed = mismatch = missing = unparsed = 0
    per_finding, per_scored = {}, {}
    pairs_total = runs_without_pairs = 0
    report = []
    for r in records:
        if not isinstance(r, dict) or r.get("arm") != a.arm:
            continue
        sid = str(r.get("session_id") or "")
        hits = glob.glob(os.path.join(a.transcripts, "*", glob.escape(sid) + ".jsonl")) if sid else []
        if not hits:
            missing += 1
            continue
        transcript = hits[0]
        texts = assistant_texts(transcript)
        final = texts[-1] if texts else ""
        findings, _reason = fe.extract_findings(final)
        cdir = case_dir(a.evals, r["case"])
        rescored = fe.score_review(cdir, r["trap"], final)
        recorded = r.get("review") or {}
        if any(rescored.get(k) != recorded.get(k)
               for k in ("hit", "false_findings", "scored_findings", "findings_total", "incomplete")):
            mismatch += 1
        if findings is None:
            unparsed += 1
            continue
        module = fe.variant_paths(cdir, r["trap"])[2]
        agents = []
        sub = os.path.join(os.path.dirname(transcript), sid, "subagents")
        for meta_path in sorted(glob.glob(os.path.join(sub, "*.meta.json"))):
            meta = read_json(meta_path, {})
            kind = str(meta.get("agentType") or "") if isinstance(meta, dict) else ""
            if not kind or fe.agent_name(kind) == "finding-critic":
                continue
            body = "\n".join(assistant_texts(meta_path[:-len(".meta.json")] + ".jsonl"))
            agents.append((kind, cited_lines(body, module)))
        n_attr = n_un = 0
        for f in findings:
            if not isinstance(f, dict):
                continue
            findings_n += 1
            if not (isinstance(f.get("reviewers"), list) and f["reviewers"]):
                # Every subagent that cites the finding's exact line, never
                # only the nearest one.
                line = fe.finding_line(f.get("line"))
                names = []
                for kind, lines in agents:
                    if line is not None and line in lines and kind not in names:
                        names.append(kind)
                f["reviewers"] = names or ["unattributed"]
            n = 0 if f["reviewers"] == ["unattributed"] else len(f["reviewers"])
            per_finding[n] = per_finding.get(n, 0) + 1
            if str(f.get("priority", "")).strip().upper() in ("P1", "P2"):
                per_scored[n] = per_scored.get(n, 0) + 1
            if n:
                n_attr += 1
            else:
                n_un += 1
        attributed += n_attr
        unattributed += n_un
        # The candidate pairs review.dedup would ask about, by its own rule.
        pairs = len(s1_dedup.candidates(convert(findings)[0]))
        pairs_total += pairs
        runs_without_pairs += 0 if pairs else 1
        model = str(r.get("model") or "default").replace("/", "_")
        dest = os.path.join(a.out, model, a.arm, r["case"], r["trap"], "%d.json" % int(r["run"]))
        write_json(dest, findings)
        exported += 1
        report.append({"run": "/".join((model, a.arm, r["case"], r["trap"], str(r["run"]))),
                       "session_id": sid, "attributed": n_attr, "unattributed": n_un, "pairs_candidate": pairs})
    half, why = dedup_half(per_finding, runs_without_pairs, exported)
    write_json(os.path.join(a.out, "export-report.json"),
               {"runs": report, "missing_transcripts": missing, "rescore_mismatch": mismatch,
                "attribution": "exact-line",
                "reviewers_per_finding": {str(k): v for k, v in sorted(per_finding.items())},
                "reviewers_per_p1_p2_finding": {str(k): v for k, v in sorted(per_scored.items())},
                "pairs_candidate": pairs_total, "runs_without_pairs": runs_without_pairs,
                "dedup_half": half, "dedup_half_reason": why})
    out("EXPORTED", exported)
    out("FINDINGS", findings_n)
    out("ATTRIBUTED", attributed)
    out("UNATTRIBUTED", unattributed)
    out("RESCORE_MISMATCH", mismatch)
    out("MISSING_TRANSCRIPTS", missing)
    out("UNPARSED", unparsed)
    # 0 is the reviewer "unattributed".
    out("REVIEWERS_PER_FINDING", ",".join("%d:%d" % kv_ for kv_ in sorted(per_finding.items())))
    out("REVIEWERS_PER_P1_P2_FINDING", ",".join("%d:%d" % kv_ for kv_ in sorted(per_scored.items())))
    out("PAIRS_CANDIDATE_TOTAL", pairs_total)
    out("RUNS_WITHOUT_PAIRS", runs_without_pairs)
    out("DEDUP_HALF", half)
    if why:
        out("DEDUP_HALF_REASON", why)
    return 0


# ----------------------------------------------------------------- trees

def clean_git_env():
    env = dict(os.environ)
    for k in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_ATTR_SOURCE", "GIT_CONFIG_COUNT",
              "GIT_CONFIG_PARAMETERS", "GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL", "GIT_COMMITTER_NAME",
              "GIT_COMMITTER_EMAIL"):
        env.pop(k, None)
    # No setting of the operator's (commit signing, hooks) may change a commit.
    env["GIT_CONFIG_GLOBAL"] = os.devnull
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    return env


def tree_head(tree):
    r = subprocess.run(["git", "-C", tree, "rev-parse", "HEAD"], capture_output=True, env=clean_git_env())
    return r.stdout.decode("ascii", "replace").strip() if r.returncode == 0 else ""


def tree_dir(work, case, trap):
    return os.path.join(work, "trees", case, trap)


def cmd_trees(a):
    runs = iter_runs(a.findings_dir)
    path = os.path.join(a.replay, "trees.json")
    recorded = read_json(path, {}) or {}
    date = recorded.get("date") or a.date or FIXED_DATE
    trees = dict(recorded.get("trees") or {})
    built = checked = 0
    mismatches = []
    for case, trap in sorted({(r.case, r.trap) for r in runs}):
        d = tree_dir(a.work, case, trap)
        if not os.path.isdir(os.path.join(d, ".git")):
            env = clean_git_env()
            env["GIT_AUTHOR_DATE"] = date
            env["GIT_COMMITTER_DATE"] = date
            os.makedirs(os.path.dirname(d), exist_ok=True)
            r = subprocess.run(["bash", os.path.join(BIN_DIR, "flow-eval-run.sh"), "--mode", "review",
                                "--case", case, "--trap", trap, "--build-review-repo", d],
                               capture_output=True, env=env)
            if r.returncode != 0:
                raise Failed("could not build %s/%s: %s" % (case, trap, r.stderr.decode("utf-8", "replace").strip()[:300]))
            built += 1
        head = tree_head(d)
        name = "%s/%s" % (case, trap)
        if name in trees:
            checked += 1
            if trees[name].get("head") != head:
                mismatches.append(name)
        else:
            trees[name] = {"head": head}
    out("TREES_BUILT", built)
    out("TREES_CHECKED", checked)
    for name in mismatches:
        out("TREE_MISMATCH", name)
    if mismatches:
        out("TREES_STATE", "refused")
        return 1
    write_json(path, {"date": date, "trees": trees})
    out("TREES_STATE", "ok")
    return 0


def check_trees(a, runs):
    recorded = (read_json(os.path.join(a.replay, "trees.json"), {}) or {}).get("trees") or {}
    for case, trap in sorted({(r.case, r.trap) for r in runs}):
        name = "%s/%s" % (case, trap)
        head = tree_head(tree_dir(a.work, case, trap))
        if not head or name not in recorded:
            raise Failed("no tree for %s: run trees first" % name)
        if recorded[name].get("head") != head:
            raise Failed("the tree for %s is not at its recorded HEAD" % name)


# ----------------------------------------------------------------- the plugin copy and its settings

def set_threshold(questions_path, site, question, value):
    """Set one question's threshold in a copy of questions.yaml, by its
    lines: the default becomes the sweep value and any per-model entries
    (models:) are removed, so the client applies the sweep value whatever
    model answers. The result is checked as the client reads it."""
    import yaml
    with open(questions_path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    i = lines.index("  %s:" % site)
    j = next(k for k in range(i + 1, len(lines)) if lines[k] == "    thresholds:")
    k = next(k for k in range(j + 1, len(lines)) if lines[k] == "      %s:" % question)
    end = next((e for e in range(k + 1, len(lines))
                if lines[e].strip() and not lines[e].startswith("       ")), len(lines))
    block = []
    skipping = False
    for line in lines[k + 1:end]:
        if line.startswith("        models:"):
            skipping = True
            continue
        if skipping and (line.startswith("         ") or not line.strip()):
            continue
        skipping = False
        if line.startswith("        default: "):
            line = "        default: %s" % fmt_t(value)
        block.append(line)
    lines[k + 1:end] = block
    with open(questions_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    with open(questions_path, encoding="utf-8") as fh:
        t = yaml.safe_load(fh)["sites"][site]["thresholds"][question]
    if float(t["default"]) != float(value) or t.get("models"):
        raise Failed("could not set the %s threshold of %s" % (question, site))


def plugin_copy(work, name, thresholds):
    dest = os.path.join(work, "plugins", name)
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    ignore = shutil.ignore_patterns("__pycache__")
    shutil.copytree(os.path.join(PLUGIN_ROOT, "bin"), os.path.join(dest, "bin"), ignore=ignore)
    shutil.copytree(os.path.join(PLUGIN_ROOT, "system-one"), os.path.join(dest, "system-one"), ignore=ignore)
    shutil.copy2(os.path.join(PLUGIN_ROOT, "settings.json"), os.path.join(dest, "settings.json"))
    for site, value in thresholds.items():
        set_threshold(os.path.join(dest, "system-one", "questions.yaml"), site, QUESTION[site], value)
    return dest


def write_settings(work, name, system_one):
    path = os.path.join(work, "settings", name + ".json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump({"systemOne": system_one}, fh)
    return path


def site_env(work, plugin, settings):
    env = clean_git_env()
    env.pop("GIT_CONFIG_GLOBAL", None)
    env.pop("GIT_CONFIG_NOSYSTEM", None)
    env["FLOW_USER_SETTINGS"] = settings
    env["FLOW_STATE_DIR"] = os.path.join(work, "state")
    env["CLAUDE_PLUGIN_ROOT"] = plugin
    for k in ("HTTP_PROXY", "http_proxy", "HTTPS_PROXY", "https_proxy", "ALL_PROXY", "all_proxy"):
        env.pop(k, None)
    os.makedirs(env["FLOW_STATE_DIR"], exist_ok=True)
    return env


def run_site(plugin, script, args, cwd, env, save):
    r = subprocess.run([os.path.join(plugin, "bin", script)] + args, cwd=cwd, env=env, capture_output=True)
    stdout = r.stdout.decode("utf-8", "replace")
    with open(save + ".out", "w", encoding="utf-8") as fh:
        fh.write(stdout)
    with open(save + ".err", "w", encoding="utf-8") as fh:
        fh.write(r.stderr.decode("utf-8", "replace"))
    return r.returncode, stdout


def kv(stdout):
    values = {}
    for line in stdout.splitlines():
        key, sep, value = line.partition("=")
        if sep and key not in values:
            values[key] = value
    return values


def lines_of(stdout, key):
    return [line[len(key) + 1:] for line in stdout.splitlines() if line.startswith(key + "=")]


def intval(values, key):
    try:
        return int(values.get(key, "0"))
    except ValueError:
        return 0


def dedup_problems(stdout, rc):
    """Why one dedup run fails a pass, as a list."""
    problems = []
    v = kv(stdout)
    if rc != 0:
        problems.append("blocked")
    total = sum(intval(v, k) for k in ("PAIRS_SAME", "PAIRS_DIFFERENT", "PAIRS_RELATED", "PAIRS_NO_ANSWER"))
    if intval(v, "PAIRS_ASKED") != total:
        problems.append("partition")
    return problems


def unasked_items(dedup_out, conf_out):
    """What one run of the sites left unasked: the dedup script's UNASKED and
    STOPPED, and each finding the confidence script did not ask because of
    its cap, its budget or a provider that stopped answering."""
    items = []
    if dedup_out is not None:
        v = kv(dedup_out)
        # A reason that stops every pair (mode-off, settings-refused) is
        # reported by stop_reasons, not here.
        why = v.get("STOPPED") or v.get("REASON")
        if (intval(v, "UNASKED") or v.get("STOPPED")) and why not in STOP_REASONS:
            items.append("dedup:UNASKED=%s STOPPED=%s" % (v.get("UNASKED"), v.get("STOPPED", "")))
    if conf_out is not None:
        items += ["confidence:%s" % r for r in confidence_reasons(conf_out) if r in UNASKED_REASONS]
    return items


def capped(item):
    """Whether an unasked_items entry was left unasked by the cap alone."""
    return item == "confidence:cap" or (item.startswith("dedup:") and item.endswith(" STOPPED="))


def confidence_reasons(stdout):
    return [m.group(1) for m in re.finditer(r"^S1_CONFIDENCE_RESULT=\S+ STATE=\S+ REASON=([a-z0-9-]+)", stdout, re.M)]


def stop_reasons(dedup_out, conf_out, allowed=()):
    found = []
    v = kv(dedup_out) if dedup_out is not None else {}
    for reason in (v.get("REASON"), v.get("STOPPED")):
        if reason in STOP_REASONS and reason not in allowed:
            found.append(reason)
    if conf_out is not None:
        found += [r for r in confidence_reasons(conf_out) if r in STOP_REASONS and r not in allowed]
    return found


# ----------------------------------------------------------------- shadow

def rep_variants(replay, run):
    """The merged findings of the dedup on passes for one run, each distinct
    one once, in buckets with unique ids (the confidence script refuses a
    repeated id)."""
    seen, buckets = set(), []
    for path in sorted(glob.glob(os.path.join(replay, "on", "dedup-*", run.key, "out.json"))):
        for f in read_json(path, []) or []:
            if not isinstance(f, dict) or not f.get("locations"):
                continue
            c = canonical(f)
            if c in seen:
                continue
            seen.add(c)
            for bucket in buckets:
                if f["id"] not in {x["id"] for x in bucket}:
                    bucket.append(f)
                    break
            else:
                buckets.append([f])
    return buckets


def cmd_shadow(a):
    runs = iter_runs(a.findings_dir)
    check_trees(a, runs)
    pinned = a.model
    plugin = plugin_copy(a.work, "shadow-" + a.set, {})
    system_one = {"provider": a.provider, "model": pinned, "timeoutMs": a.timeout_ms,
                  "stateTokenCap": STATE_TOKEN_CAP,
                  "uses": {DEDUP: "shadow" if a.set == "base" else "off", CONFIDENCE: "shadow",
                           "review.challenge": "off"}}
    if a.base_url:
        system_one["baseUrl"] = a.base_url
    if a.api_key_env:
        system_one["apiKeyEnv"] = a.api_key_env
    env = site_env(a.work, plugin, write_settings(a.work, "shadow-" + a.set, system_one))
    root = os.path.join(a.replay, "shadow", a.set)
    fails, per_run = set(), {}
    totals = {"candidate": 0, "asked": 0, "conf": 0, "zero": 0, "unasked": 0}
    for run in runs:
        tree = tree_dir(a.work, run.case, run.trap)
        rdir = os.path.join(root, run.key)
        if os.path.isdir(rdir):
            shutil.rmtree(rdir)
        os.makedirs(rdir)
        flow_run = os.path.join(tree, ".flow", "runs", run.run_id)
        info: dict[str, Any] = {"unasked": []}
        if a.set == "base":
            batches = [("", convert(read_json(run.path, []))[0])]
        else:
            batches = [("-%d" % (i + 1), b) for i, b in enumerate(rep_variants(a.replay, run))]
        for suffix, findings in batches:
            if os.path.isdir(flow_run):
                shutil.rmtree(flow_run)
            os.makedirs(flow_run)
            inp = os.path.join(rdir, "in%s.json" % suffix)
            write_json(inp, findings)
            dedup_out = None
            if a.set == "base":
                rc, dedup_out = run_site(plugin, "flow-s1-dedup.sh",
                                         ["--findings", inp, "--out", os.path.join(rdir, "dedup-out.json"),
                                          "--tree", tree, "--ref-prefix", run.ref, "--run-id", run.run_id],
                                         tree, env, os.path.join(rdir, "dedup"))
                fails.update(dedup_problems(dedup_out, rc))
                v = kv(dedup_out)
                totals["candidate"] += intval(v, "PAIRS_CANDIDATE")
                totals["asked"] += intval(v, "PAIRS_ASKED")
                if intval(v, "PAIRS_CANDIDATE") == 0:
                    totals["zero"] += 1
                info["pairs_candidate"] = intval(v, "PAIRS_CANDIDATE")
                info["pairs_asked"] = intval(v, "PAIRS_ASKED")
            rc, conf_out = run_site(plugin, "flow-s1-confidence.sh",
                                    ["--findings", inp, "--tree", tree, "--ref-prefix", run.ref + ("/reps" if suffix else ""),
                                     "--run-id", run.run_id, "--demoted-out", os.path.join(rdir, "demoted%s.txt" % suffix)],
                                    tree, env, os.path.join(rdir, "confidence%s" % suffix))
            if rc != 0:
                fails.add("blocked")
            totals["conf"] += intval(kv(conf_out), "S1_ASKED")
            info["unasked"] += unasked_items(dedup_out, conf_out)
            for reason in stop_reasons(dedup_out, conf_out):
                fails.add("stop-reason:" + reason)
            for rec in read_jsonl(os.path.join(flow_run, "system-one.jsonl")):
                if rec.get("model") != pinned:
                    fails.add("model-not-pinned")
            shutil.copytree(flow_run, os.path.join(rdir, "run%s" % suffix))
            shutil.rmtree(flow_run)
        if info["unasked"]:
            totals["unasked"] += 1
            # --allow-unasked waives only the cap, which leaves the same
            # items unasked on every on pass. Items a time budget or a
            # provider that stopped answering left unasked are asked by the
            # on passes, and the table has no answer for them.
            if not a.allow_unasked or not all(capped(i) for i in info["unasked"]):
                fails.add("unasked")
        per_run[run.key] = info
    state = "failed" if fails else "ok"
    write_json(os.path.join(root, "pass.json"),
               {"set": a.set, "provider": a.provider, "model": pinned, "state": state, "fails": sorted(fails),
                "totals": totals, "runs": per_run})
    out("SHADOW_RUNS", len(runs))
    out("PAIRS_CANDIDATE_TOTAL", totals["candidate"])
    out("PAIRS_ASKED_TOTAL", totals["asked"])
    out("CONFIDENCE_ASKED_TOTAL", totals["conf"])
    out("RUNS_PAIRS_CANDIDATE_ZERO", totals["zero"])
    out("RUNS_UNASKED", totals["unasked"])
    for f in sorted(fails):
        out("FAIL", f)
    out("PASS_STATE", state)
    return 1 if fails else 0


def read_jsonl(path):
    recs = []
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if isinstance(rec, dict):
                    recs.append(rec)
    except OSError:
        pass
    return recs


# ----------------------------------------------------------------- table

def cmd_table(a):
    """The answer table: each kept state once, with the p every run that sent
    it was given. A state two runs sent can carry two answers (the provider
    does not answer identical requests identically), so the replay gives each
    run back its own. One run that sent a state twice (two findings with the
    same state, or the same state in two of its run directories) and was
    given two answers cannot be replayed: which answer goes with which
    request is not known."""
    entries, unmatched, largest = {}, 0, 0
    wrong_model = 0
    conflicts, same_run = [], set()
    shadow_root = os.path.join(a.replay, "shadow")
    for rundir in sorted(glob.glob(os.path.join(shadow_root, "*", "**", "run*", ""), recursive=True)):
        if not os.path.isfile(os.path.join(rundir, "system-one.jsonl")):
            continue
        # shadow/<set>/<run key>/run[-<n>]/
        run_key = "/".join(os.path.relpath(os.path.dirname(os.path.normpath(rundir)), shadow_root).split(os.sep)[1:])
        by_digest: dict[tuple[Any, Any], list[dict[str, Any]]] = {}
        for rec in read_jsonl(os.path.join(rundir, "system-one.jsonl")):
            by_digest.setdefault((rec.get("site"), rec.get("state_sha256")), []).append(rec)
        for path in sorted(glob.glob(os.path.join(rundir, "system-one-state", "*.json"))):
            name = os.path.basename(path)
            site = DEDUP if name.startswith("dedup-") else CONFIDENCE if name.startswith("confidence-") else None
            if site is None:
                continue
            with open(path, "rb") as fh:
                raw = fh.read()
            recs = by_digest.get((site, hashlib.sha256(raw).hexdigest()))
            if not recs:
                unmatched += 1
                continue
            rec = recs[0]
            state = json.loads(raw.decode("utf-8"))
            largest = max(largest, len(json.dumps(state, ensure_ascii=False)))
            p = answer_p(rec)
            if rec.get("model") != a.model:
                wrong_model += 1
            key = state_key(state)
            if len({canonical(answer_p(r)) for r in recs}) > 1:
                same_run.add("%s %s" % (run_key, key))
            entry = entries.get(key)
            if entry is None:
                entries[key] = {"site": site, "question": QUESTION[site], "p": p, "model": rec.get("model"),
                                "result": rec.get("result"), "runs": {run_key: p}}
                continue
            if run_key in entry["runs"]:
                if entry["runs"][run_key] != p:
                    same_run.add("%s %s" % (run_key, key))
                continue
            entry["runs"][run_key] = p
            if p != entry["p"]:
                conflicts.append("%s %s" % (run_key, key))
    unanswered = unanswered_by_site(entries.values())
    same_run_list = sorted(same_run)
    write_json(os.path.join(a.replay, "table.json"),
               {"model": a.model, "entries": entries, "conflicts": conflicts, "same_run_conflicts": same_run_list})
    out("TABLE_ENTRIES", len(entries))
    # States two runs were given different answers for: each run is replayed
    # its own.
    out("TABLE_CONFLICTS", len(conflicts))
    out("TABLE_SAME_RUN_CONFLICTS", len(same_run_list))
    for item in same_run_list:
        out("SAME_RUN_CONFLICT", item)
    # Answers a run was sent no p for (an HTTP error such as rate limiting, a
    # timeout, a malformed reply): the on passes give that run no answer
    # either, so its pair is not merged and its finding not demoted.
    out("TABLE_UNANSWERED", sum(v[0] for v in unanswered.values()))
    for site, (none, total) in sorted(unanswered.items()):
        out("UNANSWERED_SITE", "%s %d of %d" % (site, none, total))
    out("TABLE_UNMATCHED", unmatched)
    out("TABLE_WRONG_MODEL", wrong_model)
    out("LARGEST_STATE_CHARS", largest)
    out("STATE_LIMIT_CHARS", STATE_TOKEN_CAP * 4)
    bad = (same_run_list or unmatched or wrong_model or largest > STATE_TOKEN_CAP * 4
           or any(v[0] for v in unanswered.values()))
    out("TABLE_STATE", "failed" if bad else "ok")
    return 1 if bad else 0


def answer_p(rec):
    """The p a record holds, or None when it holds no answer."""
    answer = rec.get("answer") if isinstance(rec.get("answer"), dict) else None
    return answer.get("p") if answer else None


def unanswered_by_site(entries):
    """site -> (run answers without a p, run answers), over every run each
    kept state was sent by."""
    counts: dict[str, list[int]] = {}
    for e in entries:
        if not isinstance(e, dict):
            continue
        runs_p = e.get("runs")
        if not isinstance(runs_p, dict):
            runs_p = {"": e.get("p")}
        c = counts.setdefault(str(e.get("site")), [0, 0])
        for p in runs_p.values():
            c[1] += 1
            if not isinstance(p, (int, float)):
                c[0] += 1
    return {k: (v[0], v[1]) for k, v in counts.items()}


# ----------------------------------------------------------------- the replay server

class Replay:
    def __init__(self, table):
        self.entries = table.get("entries") or {}
        self.lock = threading.Lock()
        self.requests = self.hits = self.misses = self.unanswered = 0
        self.log = []
        # The run whose requests are being answered (on passes); None
        # answers any run's record (serve).
        self.run = None

    def set_run(self, run_key):
        with self.lock:
            self.run = run_key

    def answer(self, body):
        """(status, reply). With a run set, the answer that run was given;
        a state only other runs sent is not answered."""
        state = body.get("state") if isinstance(body, dict) else None
        questions = body.get("questions") if isinstance(body, dict) else None
        qid = next(iter(questions)) if isinstance(questions, dict) and len(questions) == 1 else None
        key = state_key(state) if state is not None else ""
        entry = self.entries.get(key)
        with self.lock:
            self.requests += 1
            runs = entry.get("runs") if isinstance(entry, dict) else None
            if self.run is not None and isinstance(runs, dict):
                known, p = self.run in runs, runs.get(self.run)
            else:
                known, p = entry is not None, (entry or {}).get("p")
            if entry is None or not known or entry.get("question") != qid:
                self.misses += 1
                self.log.append({"key": key, "question": qid, "run": self.run, "hit": False})
                return 500, {"detail": "no recorded answer for this state"}
            self.hits += 1
            self.log.append({"key": key, "question": qid, "run": self.run, "hit": True, "p": p})
            if p is None:
                # Recorded without an answer: no answer again.
                self.unanswered += 1
                return 503, {"detail": "recorded without an answer (%s)" % entry.get("result")}
        return 200, {"model": entry.get("model"), "answers": {qid: {"type": "noul", "noul": p}}}


def served_answers(log):
    """[run, state key, p] of every answer the replay server gave, each once,
    sorted."""
    seen = {canonical([e.get("run"), e.get("key"), e.get("p")]): [e.get("run"), e.get("key"), e.get("p")]
            for e in log if e.get("hit")}
    return [seen[k] for k in sorted(seen)]


def table_identity(pts, table):
    """(point -> served answers the current table does not hold) for every on
    pass. A pass that kept no record of its answers is listed too."""
    entries = (table or {}).get("entries") or {}
    stale = {}
    for p in pts:
        served = p.get("served")
        if not isinstance(served, list):
            stale[p["point"]] = ["no record of the answers served"]
            continue
        bad = []
        for item in served:
            if not (isinstance(item, list) and len(item) == 3):
                bad.append(canonical(item))
                continue
            run, key, value = item
            entry = entries.get(key) if isinstance(key, str) else None
            runs = entry.get("runs") if isinstance(entry, dict) else None
            if not isinstance(runs, dict) or run not in runs or runs[run] != value:
                bad.append("%s %s" % (run, key))
        if bad:
            stale[p["point"]] = bad
    return stale


def start_server(replay):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, format, *args):
            pass

        def do_POST(self):
            length = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(length) if length else b""
            try:
                body = json.loads(raw.decode("utf-8"))
            except ValueError:
                body = None
            status, reply = replay.answer(body)
            data = json.dumps(reply).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    server = None
    for _ in range(5):
        candidate = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        # Never the port a local imajev server listens on.
        if candidate.server_address[1] != 8765:
            server = candidate
            break
        candidate.server_close()
    if server is None:
        raise Failed("the replay server got port 8765 five times")
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server


def cmd_serve(a):
    replay = Replay(read_json(a.table, {}) or {})
    server = start_server(replay)
    tmp = a.port_file + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(str(server.server_address[1]))
    os.replace(tmp, a.port_file)
    threading.Event().wait(a.lifetime)
    server.shutdown()
    if a.log:
        write_json(a.log, {"requests": replay.requests, "hits": replay.hits, "misses": replay.misses,
                           "log": replay.log})
    return 0


# ----------------------------------------------------------------- on

def point_name(filt, sd, cs):
    if filt == "off":
        return "off"
    if filt == "dedup":
        return "dedup-" + fmt_t(sd)
    if filt == "confidence":
        return "confidence-" + fmt_t(cs)
    return "dedup-%s-confidence-%s" % (fmt_t(sd), fmt_t(cs))


def cmd_on(a):
    filt = a.filter
    uses_dedup = filt in ("dedup", "dedup-confidence")
    uses_conf = filt in ("confidence", "dedup-confidence")
    if uses_dedup and a.same_defect is None:
        raise Failed("--same-defect is required for filter %s" % filt)
    if uses_conf and a.claim_supported is None:
        raise Failed("--claim-supported is required for filter %s" % filt)
    runs = iter_runs(a.findings_dir)
    check_trees(a, runs)
    point = point_name(filt, a.same_defect, a.claim_supported)
    thresholds = {}
    if uses_dedup:
        thresholds[DEDUP] = a.same_defect
    if uses_conf:
        thresholds[CONFIDENCE] = a.claim_supported
    plugin = plugin_copy(a.work, "on-" + point, thresholds)
    table = read_json(os.path.join(a.replay, "table.json"))
    if not isinstance(table, dict):
        raise Failed("no table.json: run table first")
    replay = Replay(table)
    server = start_server(replay)
    try:
        system_one = {"provider": "custom", "baseUrl": "http://127.0.0.1:%d" % server.server_address[1],
                      "model": a.model, "timeoutMs": a.timeout_ms, "stateTokenCap": STATE_TOKEN_CAP,
                      "uses": {DEDUP: "on" if uses_dedup else "off", CONFIDENCE: "on" if uses_conf else "off",
                               "review.challenge": "off"}}
        env = site_env(a.work, plugin, write_settings(a.work, "on-" + point, system_one))
        root = os.path.join(a.replay, "on", point)
        fails, per_run = set(), {}
        merged_total = demoted_total = 0
        # The runs the shadow pass left items unasked in (--allow-unasked).
        shadow_runs = (read_json(os.path.join(a.replay, "shadow", "base", "pass.json"), {}) or {}).get("runs") or {}
        allowed = ("mode-off",) if filt == "off" else ()
        for run in runs:
            tree = tree_dir(a.work, run.case, run.trap)
            rdir = os.path.join(root, run.key)
            if os.path.isdir(rdir):
                shutil.rmtree(rdir)
            os.makedirs(rdir)
            inp = os.path.join(rdir, "in.json")
            outp = os.path.join(rdir, "out.json")
            demoted = os.path.join(rdir, "demoted.txt")
            write_json(inp, convert(read_json(run.path, []))[0])
            replay.set_run(run.key)
            dedup_out = conf_out = None
            if uses_dedup or filt == "off":
                rc, dedup_out = run_site(plugin, "flow-s1-dedup.sh",
                                         ["--findings", inp, "--out", outp, "--tree", tree, "--ref-prefix", run.ref],
                                         tree, env, os.path.join(rdir, "dedup"))
                fails.update(dedup_problems(dedup_out, rc))
                if intval(kv(dedup_out), "NO_ANSWER_HTTP_500"):
                    fails.add("server-miss")
                merged_total += len(lines_of(dedup_out, "MERGED"))
            else:
                shutil.copy2(inp, outp)
            if uses_conf or filt == "off":
                rc, conf_out = run_site(plugin, "flow-s1-confidence.sh",
                                        ["--findings", outp, "--tree", tree, "--ref-prefix", run.ref,
                                         "--demoted-out", demoted], tree, env, os.path.join(rdir, "confidence"))
                if rc != 0:
                    fails.add("blocked")
                if "http-500" in confidence_reasons(conf_out):
                    fails.add("server-miss")
                demoted_total += len(fe.read_demoted(demoted))
            for reason in stop_reasons(dedup_out, conf_out, allowed):
                fails.add("stop-reason:" + reason)
            unasked = unasked_items(dedup_out, conf_out)
            if unasked and not (shadow_runs.get(run.key) or {}).get("unasked"):
                fails.add("unasked")
            per_run[run.key] = {"merged": lines_of(dedup_out or "", "MERGED"),
                                "demoted": sorted(fe.read_demoted(demoted)), "unasked": unasked}
        if replay.misses:
            fails.add("server-miss")
    finally:
        server.shutdown()
        server.server_close()
    state = "failed" if fails else "ok"
    write_json(os.path.join(root, "pass.json"),
               {"point": point, "filter": filt, "same_defect": a.same_defect if uses_dedup else None,
                "claim_supported": a.claim_supported if uses_conf else None, "model": a.model,
                "state": state, "fails": sorted(fails),
                "server": {"requests": replay.requests, "hits": replay.hits, "misses": replay.misses,
                           "unanswered": replay.unanswered},
                # Each answer this pass was served, so aggregate can tell a
                # point answered from an earlier table.
                "served": served_answers(replay.log),
                "runs": per_run})
    out("POINT", point)
    out("ON_RUNS", len(runs))
    out("SERVER_REQUESTS", replay.requests)
    out("SERVER_HITS", replay.hits)
    out("SERVER_MISSES", replay.misses)
    out("SERVER_UNANSWERED", replay.unanswered)
    out("MERGED_TOTAL", merged_total)
    out("DEMOTED_TOTAL", demoted_total)
    for f in sorted(fails):
        out("FAIL", f)
    out("PASS_STATE", state)
    return 1 if fails else 0


# ----------------------------------------------------------------- inspect

def points(replay):
    result = []
    for path in sorted(glob.glob(os.path.join(replay, "on", "*", "pass.json"))):
        p = read_json(path)
        if isinstance(p, dict):
            result.append(p)
    return result


def hunk_of(location, hunks, module):
    path, line = fe.location_site(location)
    if os.path.basename(path) not in (module + ".py", module) or line is None:
        return "outside"
    for i, (lo, hi) in enumerate(hunks, 1):
        if lo <= line <= hi:
            return "hunk %d (%d-%d)" % (i, lo, hi)
    return "outside"


def collect_pairs(replay, evals):
    """Every merged pair of every dedup point: (run, representative, absorbed)."""
    pairs = {}
    for p in points(replay):
        if p.get("same_defect") is None:
            continue
        for key, info in (p.get("runs") or {}).items():
            for line in info.get("merged") or []:
                ids = line.split("+")
                for m in ids[1:]:
                    entry = pairs.setdefault((key, ids[0], m), {"points": []})
                    entry["points"].append(p["point"])
    rows = []
    for (key, rep, m), entry in sorted(pairs.items()):
        model, arm, case, trap, n = key.split("/")
        inp = {f["id"]: f for f in read_json(os.path.join(replay, "on", entry["points"][0], key, "in.json"), []) or []}
        hunks, _src = fe.hunks_for_trap(case_dir(evals, case), trap)
        module = fe.variant_paths(case_dir(evals, case), trap)[2]
        a, b = inp.get(rep, {}), inp.get(m, {})
        state = ""
        for x, y in ((rep, m), (m, rep)):
            cand = os.path.join(replay, "shadow", "base", key, "run", "system-one-state", "dedup-%s+%s.json" % (x, y))
            if os.path.isfile(cand):
                state = os.path.relpath(cand, replay)
        rows.append({"run": key, "a": rep, "b": m, "points": entry["points"],
                     "a_location": a.get("location"), "b_location": b.get("location"),
                     "a_hunk": hunk_of(a.get("location") or "", hunks, module),
                     "b_hunk": hunk_of(b.get("location") or "", hunks, module),
                     "a_problem": a.get("problem"), "b_problem": b.get("problem"),
                     "state": state, "label": None, "reason": ""})
    return rows


def labels_digest(labels):
    """sha256 of the labels and reasons, not of the file's formatting."""
    rows = sorted([list(k) + list(v) for k, v in labels.items()], key=lambda r: [str(x) for x in r])
    return hashlib.sha256(canonical(rows).encode("utf-8")).hexdigest()


def label_map(replay):
    labels = {}
    for row in read_json(os.path.join(replay, "merged-pairs.json"), []) or []:
        if isinstance(row, dict):
            labels[(row.get("run"), row.get("a"), row.get("b"))] = (row.get("label"), row.get("reason") or "")
    return labels


# What the labelling sheet shows. The threshold points a pair merged at (how
# sure the model was) and the hunk each finding sits in (whether the merge
# changes the score) are left out, so a label rests on the two findings and
# the state alone; report.json lists them once every pair is labelled.
SHEET_FIELDS = ("run", "a", "b", "a_location", "b_location", "a_problem", "b_problem", "state",
                "label", "reason")


def cmd_inspect(a):
    rows = collect_pairs(a.replay, a.evals)
    labels = label_map(a.replay)
    unlabelled = 0
    sheet = []
    for row in rows:
        label, reason = labels.get((row["run"], row["a"], row["b"]), (None, ""))
        row["label"], row["reason"] = label, reason
        if label not in ("same", "different"):
            unlabelled += 1
        if row["state"]:
            # A copy away from the shadow run, whose records beside the
            # state hold the answer the provider gave.
            copy = os.path.join("label-states", row["run"], os.path.basename(row["state"]))
            os.makedirs(os.path.dirname(os.path.join(a.replay, copy)), exist_ok=True)
            shutil.copyfile(os.path.join(a.replay, row["state"]), os.path.join(a.replay, copy))
            row["state"] = copy
        sheet.append({k: row[k] for k in SHEET_FIELDS})
    write_json(os.path.join(a.replay, "merged-pairs.json"), sheet)
    out("MERGED_PAIRS", len(rows))
    out("UNLABELLED", unlabelled)
    return 0


# ----------------------------------------------------------------- aggregate

def undo_different(findings, inputs, run_key, labels):
    """The finding set with every merge hand-labelled different undone: the
    absorbed finding comes back as the session reported it."""
    result = []
    for f in findings:
        g = dict(f)
        restored = []
        for m in f.get("also_reported_as") or []:
            if labels.get((run_key, f.get("id"), m.get("id")), (None,))[0] == "different" and m.get("id") in inputs:
                restored.append(inputs[m["id"]])
        if restored:
            gone = {r["location"] for r in restored}
            g["locations"] = [loc for loc in g.get("locations") or [] if loc not in gone or loc == g.get("location")]
        result.append(g)
        result.extend(restored)
    return result


def scored(f):
    """Whether the scorer, LOW left out, scores the finding."""
    return (str(f.get("priority", "")).strip().upper() in fe.SCORED_PRIORITIES
            and str(f.get("confidence", "")).strip().upper() != "LOW")


def in_hunk(f, hunks, module):
    """Whether the scorer counts the finding as inside a hunk, at its own
    location."""
    wanted = module + ".py"
    return any(os.path.basename(cited) in (wanted, module) and line is not None and fe.in_any_hunk(line, hunks)
               for cited, line in fe.finding_sites(f))


def hit_id(findings, hunks, module):
    """The id of the finding the scorer takes as the run's hit (the first
    scored finding inside a hunk), or None."""
    return next((f.get("id") for f in findings if scored(f) and in_hunk(f, hunks, module)), None)


def ceiling_findings(findings, hunks, module):
    """The finding set a perfect review.dedup could at best leave: the scored
    findings it may pair (same file, both with a line or both without, not a
    security finding, by its own rule) collapsed to one per file, an in-hunk
    one kept where there is one. The reviewer rule is left out, so this is a
    bound, never less than what a merge can reach: a merge group keeps one
    scored member, never gains a hit, and never joins findings of two files."""
    groups = {}
    for i, f in enumerate(findings):
        if not scored(f) or s1_dedup.is_security(f):
            continue
        path, line = s1_dedup.parse_location(f["location"])
        groups.setdefault((s1_dedup.norm_file(path), line > 0), []).append(i)
    drop = set()
    for members in groups.values():
        keep = next((i for i in members if in_hunk(findings[i], hunks, module)), members[0])
        drop.update(i for i in members if i != keep)
    return [f for i, f in enumerate(findings) if i not in drop]


def summarize(records):
    scored = [r for r in records if not r.get("incomplete")]
    hits = sum(1 for r in scored if r.get("hit"))
    false = sum(r.get("false_findings") or 0 for r in scored)
    recall = hits / float(len(scored)) if scored else None
    precision = hits / float(hits + false) if (hits + false) else (0.0 if scored else None)
    return {"runs": len(records), "scored_runs": len(scored), "hits": hits, "false_findings": false,
            "scored_findings": sum(r.get("scored_findings") or 0 for r in scored),
            "recall": recall, "precision": precision, "f1": fe.f1(precision, recall)}


def incompletes(a):
    """run key -> True for an incomplete run, from --results or --runs-json."""
    result, source = {}, None
    if a.results:
        source = "results"
        for r in fe.load_results(a.results):
            rel = os.path.relpath(r["_run_dir"], os.path.join(a.results, "runs")).split(os.sep)
            result["/".join(rel)] = bool((r.get("review") or {}).get("incomplete"))
    elif a.runs_json:
        source = "runs-json"
        for r in read_json(a.runs_json, []) or []:
            key = "/".join((str(r.get("model") or "default").replace("/", "_"), r.get("arm"), r.get("case"),
                            r.get("trap"), str(r.get("run"))))
            result[key] = bool((r.get("review") or {}).get("incomplete"))
    return result, source


def rescore_check(a, runs):
    """(status, runs whose raw findings re-score differently, runs whose
    converted findings score differently). Re-scoring each kept findings
    file with the unchanged scorer gives the run's recorded score, and so
    does scoring it as converted, LOW kept: every score the bar reads is
    taken after the conversion."""
    records = {}
    if a.results:
        for r in fe.load_results(a.results):
            rel = os.path.relpath(r["_run_dir"], os.path.join(a.results, "runs")).split(os.sep)
            records["/".join(rel)] = r.get("review") or {}
    elif a.runs_json:
        for r in read_json(a.runs_json, []) or []:
            key = "/".join((str(r.get("model") or "default").replace("/", "_"), r.get("arm"), r.get("case"),
                            r.get("trap"), str(r.get("run"))))
            records[key] = r.get("review") or {}
    else:
        return "not-checked", [], []
    fields = ("hit", "false_findings", "scored_findings")
    raw_bad, converted_bad = [], []
    for run in runs:
        rec = records.get(run.key)
        findings = read_json(run.path, [])
        got = fe.score_review(case_dir(a.evals, run.case), run.trap, "```json\n%s\n```" % json.dumps(findings))
        if rec is None or any(got.get(k) != rec.get(k) for k in fields):
            raw_bad.append(run.key)
        conv = score(a, run, convert(findings)[0], exclude_low=False)
        if rec is None or any(conv.get(k) != rec.get(k) for k in fields):
            converted_bad.append(run.key)
    return ("flagged" if raw_bad or converted_bad else "ok"), raw_bad, converted_bad


def score(a, run, findings, demoted=None, any_location=False, exclude_low=True):
    return fe.score_review(case_dir(a.evals, run.case), run.trap, "```json\n%s\n```" % json.dumps(findings),
                           any_location=any_location, exclude_low=exclude_low, demoted=demoted or set())


def cmd_aggregate(a):
    runs = iter_runs(a.findings_dir)
    pts = points(a.replay)
    labels = label_map(a.replay)
    pairs = collect_pairs(a.replay, a.evals)
    unlabelled = [p for p in pairs if labels.get((p["run"], p["a"], p["b"]), (None,))[0] not in ("same", "different")]
    if unlabelled:
        out("AGGREGATE_STATE", "refused")
        out("REASON", "unlabelled-merged-pairs")
        out("UNLABELLED", len(unlabelled))
        return 1
    choose = a.choose
    try:
        judge = [int(x) for x in a.judge.split(",") if x.strip()]
    except ValueError:
        raise Failed("--judge is not a comma-separated list of replication numbers")
    if choose in judge:
        # The threshold would be chosen and judged on the same runs.
        out("AGGREGATE_STATE", "refused")
        out("REASON", "choose-in-judge")
        return 1
    # The labels a report was written with. A label changed after a report
    # exists could follow the scores, so it needs --relabel, and the report
    # keeps the record of it.
    labels_sha = labels_digest(labels)
    prior = read_json(os.path.join(a.replay, "report.json"))
    prior_labels = (prior.get("labels") or {}) if isinstance(prior, dict) else {}
    relabelled = list(prior_labels.get("relabelled_from") or [])
    if isinstance(prior, dict) and prior_labels.get("sha256") != labels_sha:
        if not a.relabel:
            out("AGGREGATE_STATE", "refused")
            out("REASON", "labels-changed-after-report")
            return 1
        relabelled.append(prior_labels.get("sha256") or "none")
    incomplete, inc_source = incompletes(a)
    models = sorted({r.model for r in runs})

    # Scores per run: plain (LOW excluded and kept), ceiling, and per point.
    # A point without an output for a run, or whose input for it is not the
    # run's findings file as it is now, is listed by the coverage check.
    rows = {}
    uncovered = {}
    for run in runs:
        inputs = convert(read_json(run.path, []))[0]
        by_id = {f["id"]: f for f in inputs}
        cdir = case_dir(a.evals, run.case)
        hunks, _src = fe.hunks_for_trap(cdir, run.trap)
        module = fe.variant_paths(cdir, run.trap)[2]
        inc = incomplete.get(run.key, False)
        row: dict[str, Any] = {"plain": score(a, run, inputs), "plain_low_kept": score(a, run, inputs, exclude_low=False),
               "ceiling": score(a, run, ceiling_findings(inputs, hunks, module)), "points": {}}
        for p in pts:
            rdir = os.path.join(a.replay, "on", p["point"], run.key)
            outs = read_json(os.path.join(rdir, "out.json"))
            if not isinstance(outs, list):
                uncovered.setdefault(p["point"], []).append(run.key + " (no output)")
                continue
            if canonical(read_json(os.path.join(rdir, "in.json"))) != canonical(inputs):
                uncovered.setdefault(p["point"], []).append(run.key + " (findings changed)")
            demoted = fe.read_demoted(os.path.join(rdir, "demoted.txt"))
            guarded = undo_different(outs, by_id, run.key, labels)
            row["points"][p["point"]] = {
                "guarded": score(a, run, guarded, demoted),
                "raw": score(a, run, outs, demoted),
                "any_location": score(a, run, guarded, demoted, any_location=True),
                "low_kept": score(a, run, guarded, demoted, exclude_low=False),
                "demoted": len(demoted),
                # 1 when the finding the scorer would take as the run's hit,
                # before any demotion, is demoted.
                "demoted_hits": 1 if hit_id(outs, hunks, module) in demoted else 0,
                "identity": canonical(outs) + "|" + ",".join(sorted(demoted)),
                "off_same": canonical(outs) == canonical(inputs) and not demoted,
            }
        for rec in [row["plain"], row["plain_low_kept"], row["ceiling"]] + \
                [v for pt in row["points"].values() for k, v in pt.items() if isinstance(v, dict)]:
            if inc:
                rec["incomplete"] = True
        rows[run.key] = (run, row)

    def pick(model, reps, getter):
        recs = []
        for run, row in rows.values():
            if run.model == model and run.n in reps:
                rec = getter(row)
                if rec is not None:
                    recs.append(rec)
        return summarize(recs)

    report: dict[str, Any] = {"model": a.model, "choose_replication": choose, "judge_replications": judge,
              "incomplete_source": inc_source or "not known", "models": {}, "sites": {}, "checks": {},
              "labels": {"sha256": labels_sha, "relabelled_from": relabelled}}
    all_reps = sorted({run.n for run, _ in rows.values()})
    for m in models:
        entry: dict[str, Any] = {"runs": sum(1 for run, _ in rows.values() if run.model == m),
                 "incomplete": sum(1 for run, _ in rows.values() if run.model == m and incomplete.get(run.key)),
                 "plain": {"replications": {str(r): pick(m, [r], lambda row: row["plain"]) for r in all_reps},
                           "judged": pick(m, judge, lambda row: row["plain"]),
                           "judged_low_kept": pick(m, judge, lambda row: row["plain_low_kept"])},
                 "ceiling": {"judged": pick(m, judge, lambda row: row["ceiling"])},
                 "filters": {}}
        for p in pts:
            name = p["point"]

            def get(kind, name=name):
                return lambda row: row["points"].get(name, {}).get(kind)
            f: dict[str, Any] = {"filter": p["filter"], "same_defect": p.get("same_defect"), "claim_supported": p.get("claim_supported"),
                 "replications": {str(r): pick(m, [r], get("guarded")) for r in all_reps},
                 "judged": pick(m, judge, get("guarded")), "judged_raw": pick(m, judge, get("raw")),
                 "judged_any_location": pick(m, judge, get("any_location")),
                 "judged_low_kept": pick(m, judge, get("low_kept")),
                 "demoted": sum(row["points"].get(name, {}).get("demoted", 0) for run, row in rows.values() if run.model == m),
                 "demoted_hits": sum(row["points"].get(name, {}).get("demoted_hits", 0) for run, row in rows.values() if run.model == m)}
            plain_reps = [entry["plain"]["replications"][str(r)]["f1"] for r in judge if str(r) in entry["plain"]["replications"]]
            filt_reps = [f["replications"][str(r)]["f1"] for r in judge if str(r) in f["replications"]]
            plain_reps = [v for v in plain_reps if v is not None]
            filt_reps = [v for v in filt_reps if v is not None]
            spreads = [max(v) - min(v) for v in (plain_reps, filt_reps) if len(v) >= 2]
            f["spread"] = sum(spreads) / len(spreads) if len(spreads) == 2 else None
            entry["filters"][name] = f
        report["models"][m] = entry

    for site, filt, tkey in ((DEDUP, "dedup", "same_defect"), (CONFIDENCE, "confidence", "claim_supported")):
        report["sites"][site] = decide(report, models, [p for p in pts if p["filter"] == filt], tkey, choose)

    exported = read_json(os.path.join(a.findings_dir, "export-report.json"))
    if not isinstance(exported, dict):
        exported = {}
    half = exported.get("dedup_half")
    if half in ("exercised", "not-exercised"):
        report["dedup_half"] = {"state": half, "reason": exported.get("dedup_half_reason") or "",
                                "reviewers_per_finding": exported.get("reviewers_per_finding") or {}}
    checks = run_checks(a, runs, rows, pts, report, labels)
    checks["coverage"] = {"status": "flagged" if uncovered else "ok",
                          "points": {k: v for k, v in sorted(uncovered.items())}}
    if half == "not-exercised":
        checks["pairs-candidate"] = {"status": "not-exercised", "reason": report["dedup_half"]["reason"]}
    report["checks"] = checks
    # Every check of a site must have run and passed: a check that did not
    # run holds the verdict as a flagged one does.
    for site in (DEDUP, CONFIDENCE):
        s = report["sites"][site]
        s["held_by"] = [k for k, v in sorted(checks.items())
                        if v["status"] not in CHECK_PASSES and site in check_sites(k, v)]
        s["verdict"] = "held-by-checks" if s["held_by"] else s["rule"]
    if half == "not-exercised":
        report["sites"][DEDUP]["verdict"] = "not-exercised"
    report["merged_pairs"] = [dict(row, label=labels[(row["run"], row["a"], row["b"])][0],
                                   reason=labels[(row["run"], row["a"], row["b"])][1]) for row in pairs]
    write_json(os.path.join(a.replay, "report.json"), report)
    with open(os.path.join(a.replay, "report.md"), "w", encoding="utf-8") as fh:
        fh.write(render(report))
    for name in sorted(checks):
        out("CHECK_" + name.upper().replace("-", "_"), checks[name]["status"])
    out("DIFFERENT_MERGES", checks["different-merges"]["count"])
    if half in ("exercised", "not-exercised"):
        out("DEDUP_HALF", half)
    out("JUDGED_REPLICATIONS", ",".join(str(r) for r in judge))
    for site in (DEDUP, CONFIDENCE):
        s = report["sites"][site]
        tag = site.upper().replace(".", "_")
        if s.get("chosen") is not None and s["verdict"] != "not-exercised":
            out("CHOSEN_" + tag, fmt_t(s["chosen"]))
        out("RULE_" + tag, s["rule"])
        out("VERDICT_" + tag, s["verdict"])
    out("AGGREGATE_STATE", "ok")
    return 0


def decide(report, models, site_points, tkey, choose):
    """The bar of references/review-precision-eval.md for one site."""
    result: dict[str, Any] = {"points": [p["point"] for p in site_points], "chosen": None, "rule": None,
                              "reading": []}
    if len(models) < 2:
        result["rule"] = "insufficient-models"
        result["reading"].append("The bar needs two review models; %d ran." % len(models))
        return result
    if not site_points:
        result["rule"] = "not-run"
        return result
    best = None
    scored_points = 0
    for p in site_points:
        gains, recall_ok, unscored = [], True, []
        for m in models:
            plain = report["models"][m]["plain"]["replications"].get(str(choose))
            filt = report["models"][m]["filters"][p["point"]]["replications"].get(str(choose))
            if not plain or not filt or plain["f1"] is None or filt["f1"] is None or not plain["scored_runs"]:
                unscored.append(m)
                continue
            gains.append(filt["f1"] - plain["f1"])
            if filt["recall"] < plain["recall"] - 1.0 / plain["scored_runs"] - 1e-9:
                recall_ok = False
        if unscored:
            result["reading"].append("%s has no score on replication %d for %s." % (p["point"], choose, ", ".join(unscored)))
            continue
        scored_points += 1
        if not recall_ok:
            result["reading"].append("%s loses more than one run's worth of recall on replication %d." % (p["point"], choose))
            continue
        mean = sum(gains) / len(gains)
        if best is None or mean > best[0] + 1e-9 or (abs(mean - best[0]) <= 1e-9 and p[tkey] > best[1][tkey]):
            best = (mean, p)
    if best is None:
        if not scored_points:
            # Missing data, not a result.
            result["rule"] = "no-score-on-choose"
            result["reading"].append("No threshold point has a score on replication %d for every model." % choose)
        else:
            result["rule"] = "keep-off"
            result["reading"].append("No threshold point keeps recall on replication %d." % choose)
        return result
    point = best[1]
    result["chosen"] = point[tkey]
    result["chosen_point"] = point["point"]
    adopt = True
    for m in models:
        plain = report["models"][m]["plain"]["judged"]
        filt = report["models"][m]["filters"][point["point"]]
        spread = filt["spread"]
        if spread is None or plain["f1"] is None or filt["judged"]["f1"] is None:
            result["rule"] = "insufficient-replications"
            result["reading"].append("[%s] the judged replications give no spread." % m)
            return result
        delta = filt["judged"]["f1"] - plain["f1"]
        beats = delta > spread + 1e-9
        recall_ok = filt["judged"]["recall"] >= plain["recall"] - 1.0 / max(plain["scored_runs"], 1) - 1e-9
        result["reading"].append("[%s] F1 %.3f with the filter against %.3f without, a change of %+.3f against a spread of %.3f, which %s; recall %.3f against %.3f, %s." % (
            m, filt["judged"]["f1"], plain["f1"], delta, spread, "clears it" if beats else "does not clear it",
            filt["judged"]["recall"], plain["recall"], "within one run" if recall_ok else "more than one run lower"))
        adopt = adopt and beats and recall_ok
    result["rule"] = "adopt" if adopt else "keep-off"
    return result


# The site whose verdict a check holds. A check not listed holds both.
CHECK_SITE = {"pairs-candidate": DEDUP, "ceiling": DEDUP, "different-merges": DEDUP,
              "demotions": CONFIDENCE}
FILTER_SITE = {"dedup": DEDUP, "confidence": CONFIDENCE}


def check_sites(name, check):
    """The sites whose verdict a check that did not pass holds."""
    if name in CHECK_SITE:
        return (CHECK_SITE[name],)
    if name == "thresholds":
        filters = list(check.get("filters") or []) + list(check.get("fewer_than_two_points") or [])
        return tuple(FILTER_SITE[f] for f in filters if f in FILTER_SITE) or (DEDUP, CONFIDENCE)
    return (DEDUP, CONFIDENCE)


def run_checks(a, runs, rows, pts, report, labels):
    checks = {}
    shadow = read_json(os.path.join(a.replay, "shadow", "base", "pass.json"))
    if isinstance(shadow, dict):
        per = shadow.get("runs") or {}
        zero = sum(1 for v in per.values() if not v.get("pairs_candidate"))
        checks["pairs-candidate"] = {"status": "flagged" if per and zero * 2 > len(per) else "ok",
                                     "runs_without_candidates": zero, "runs": len(per)}
        # Items left unasked in the shadow pass (--allow-unasked) or in any
        # on pass.
        unasked = shadow.get("totals", {}).get("unasked", 0)
        on_unasked = sorted("%s %s" % (p["point"], key) for p in pts
                            for key, info in (p.get("runs") or {}).items() if (info or {}).get("unasked"))
        checks["unasked"] = {"status": "flagged" if unasked or on_unasked else "ok", "runs": unasked,
                             "on_passes": on_unasked}
    else:
        checks["pairs-candidate"] = {"status": "not-run"}
        checks["unasked"] = {"status": "not-run"}
    table = read_json(os.path.join(a.replay, "table.json"))
    entries = list(((table or {}).get("entries") or {}).values())
    # Every answer a run was given: (site, p).
    answered = []
    for e in entries:
        runs_p = e.get("runs") if isinstance(e.get("runs"), dict) else {"": e.get("p")}
        answered.extend((e.get("site"), p) for p in runs_p.values() if isinstance(p, (int, float)))
    if not entries:
        checks["answers"] = {"status": "not-run"}
    else:
        near = all(0.4 <= p <= 0.6 for _site, p in answered) if answered else True
        wrong = sum(1 for e in entries if e.get("model") != a.model)
        same_run = list((table or {}).get("same_run_conflicts") or [])
        # A state a run was sent no answer for is replayed without one, so
        # it is neither merged nor demoted at any point: the filter reads as
        # doing nothing. jev-1.13.0 does not abstain, so any is a fault.
        unanswered = unanswered_by_site(entries)
        none = sum(v[0] for v in unanswered.values())
        checks["answers"] = {"status": "flagged" if near or wrong or same_run or none else "ok",
                             "answered": len(answered), "unanswered": none,
                             "unanswered_by_site": {k: {"unanswered": v[0], "sent": v[1]}
                                                    for k, v in sorted(unanswered.items())},
                             "wrong_model": wrong,
                             "runs_answered_differently": len((table or {}).get("conflicts") or []),
                             "same_run_conflicts": same_run}
    # The ceiling, the merge labels, the demotions.
    over = []
    for m, entry in report["models"].items():
        ceiling_gain = (entry["ceiling"]["judged"]["f1"] or 0) - (entry["plain"]["judged"]["f1"] or 0)
        for name, f in entry["filters"].items():
            if f["filter"] == "dedup" and f["judged_raw"]["f1"] is not None and entry["plain"]["judged"]["f1"] is not None:
                if f["judged_raw"]["f1"] - entry["plain"]["judged"]["f1"] > ceiling_gain + 1e-9:
                    over.append("%s %s" % (m, name))
    checks["ceiling"] = {"status": "flagged" if over else "ok", "over": over}
    different = sum(1 for v in labels.values() if v[0] == "different")
    checks["different-merges"] = {"status": "ok", "count": different}
    odd = []
    for m, entry in report["models"].items():
        for name, f in entry["filters"].items():
            if f["filter"] == "confidence" and f["demoted"] == 0 and f["judged"]["f1"] != entry["plain"]["judged"]["f1"]:
                odd.append("%s %s" % (m, name))
    checks["demotions"] = {"status": "flagged" if odd else "ok", "changed_without_demotion": odd}
    # Identical outputs at every point of a filter while a recorded answer
    # falls between its lowest and highest threshold.
    flagged, untested = [], []
    for filt, site, tkey in (("dedup", DEDUP, "same_defect"), ("confidence", CONFIDENCE, "claim_supported")):
        fp = [p for p in pts if p["filter"] == filt]
        if len(fp) < 2:
            untested.append(filt)
            continue
        same = all(len({row["points"].get(p["point"], {}).get("identity") for p in fp}) == 1 for _run, row in rows.values())
        lo, hi = min(p[tkey] for p in fp), max(p[tkey] for p in fp)
        # An answer changes an output between two points only when its
        # confidence (|2p - 1|) falls between them and its direction is one
        # the site acts on. review.dedup acts on both: a same answer merges
        # above the threshold, and any answer below it marks the pair
        # related. review.confidence acts only on p below 0.5: a supported
        # answer demotes nothing at any threshold.
        between = any(lo <= abs(2 * p - 1) < hi and (site == DEDUP or p < 0.5)
                      for s, p in answered if s == site)
        if same and between:
            flagged.append(filt)
    checks["thresholds"] = {"status": "flagged" if flagged else ("not-run" if untested else "ok"), "filters": flagged,
                            "fewer_than_two_points": untested}
    off = [p for p in pts if p["filter"] == "off"]
    if off:
        bad = [run.key for run, row in rows.values() if not row["points"].get("off", {}).get("off_same")]
        checks["off-identity"] = {"status": "flagged" if bad else "ok", "runs": bad}
    else:
        checks["off-identity"] = {"status": "not-run"}
    failed = [p["point"] for p in pts if p.get("state") != "ok"]
    if isinstance(shadow, dict) and shadow.get("state") != "ok":
        failed.append("shadow")
    checks["partition"] = {"status": "flagged" if failed else "ok", "failed_passes": failed}
    # Every point must have been answered from the table as it is now: a
    # point left from before a shadow and table re-run holds older answers.
    if pts and isinstance(table, dict):
        stale = table_identity(pts, table)
        checks["table-identity"] = {"status": "flagged" if stale else "ok",
                                    "points": {k: v for k, v in sorted(stale.items())}}
    else:
        checks["table-identity"] = {"status": "not-run"}
    status, raw_bad, converted_bad = rescore_check(a, runs)
    checks["rescore"] = {"status": status, "mismatch": len(raw_bad), "runs": raw_bad,
                         "converted_mismatch": len(converted_bad), "converted_runs": converted_bad}
    return checks


def pct(v):
    return "-" if v is None else "%.0f%%" % (100 * v)


def num(v):
    return "-" if v is None else "%.3f" % v


def render(report):
    lines = ["# System One filters: replay report", "",
             "Provider model `%s`. The threshold is chosen on replication %s and judged on replications %s. "
             "Precision, recall and F1: higher is better. LOW findings are left out of scoring in every row "
             "except the LOW-kept columns." % (report["model"], report["choose_replication"],
                                              ", ".join(str(r) for r in report["judge_replications"])), "",
             "## Checks before the bar", "", "| Check | Status |", "|---|---|"]
    half = report.get("dedup_half") or {}
    if half.get("state") == "not-exercised":
        lines[4:4] = ["These findings were recovered from earlier review sessions, with each finding's "
                      "reviewers taken from the subagents that cite its exact line. They do not exercise "
                      "review.dedup (%s): this replay tests the conversion, review.confidence, the answer "
                      "table and the replay server only. review.dedup is first tested on the fresh "
                      "re-run, and its row here is not a verdict." % half.get("reason", ""), ""]
    for name in sorted(report["checks"]):
        lines.append("| %s | %s |" % (name, report["checks"][name]["status"]))
    lines += ["", "## Judged replications", "",
              "| Model | Filter | Precision | Recall | F1 | Raw F1 | Any-location F1 | LOW-kept F1 | Spread | Demoted (hits) |",
              "|---|---|---|---|---|---|---|---|---|---|"]
    for m, entry in sorted(report["models"].items()):
        p = entry["plain"]["judged"]
        lines.append("| %s | plain | %s | %s | %s | - | - | %s | - | - |" % (
            m, pct(p["precision"]), pct(p["recall"]), num(p["f1"]), num(entry["plain"]["judged_low_kept"]["f1"])))
        for name, f in sorted(entry["filters"].items()):
            j = f["judged"]
            lines.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %d (%d) |" % (
                m, name, pct(j["precision"]), pct(j["recall"]), num(j["f1"]), num(f["judged_raw"]["f1"]),
                num(f["judged_any_location"]["f1"]), num(f["judged_low_kept"]["f1"]), num(f["spread"]),
                f["demoted"], f["demoted_hits"]))
    lines += ["", "## Verdict", ""]
    for site, s in sorted(report["sites"].items()):
        chosen = "" if s.get("chosen") is None or s["verdict"] == "not-exercised" else " at %s" % fmt_t(s["chosen"])
        held = " (held by: %s)" % ", ".join(s["held_by"]) if s.get("held_by") and s["verdict"] == "held-by-checks" else ""
        lines.append("- `%s`: %s%s%s. %s" % (site, s["verdict"], held, chosen, " ".join(s["reading"])))
    relabelled = (report.get("labels") or {}).get("relabelled_from") or []
    if relabelled:
        lines += ["", "Times the merge labels were changed after a report had been written (--relabel): %d."
                  % len(relabelled)]
    return "\n".join(lines) + "\n"


# ----------------------------------------------------------------- main

def main(argv):
    ap = argparse.ArgumentParser(prog="flow-eval-s1-replay.sh")
    sub = ap.add_subparsers(dest="cmd", required=True)
    evals_default = os.path.join(PLUGIN_ROOT, "evals")

    p = sub.add_parser("export-recovered")
    p.add_argument("--runs-json", required=True)
    p.add_argument("--transcripts", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--arm", default="review-b")
    p.add_argument("--evals", default=evals_default)

    p = sub.add_parser("convert")
    p.add_argument("--in", dest="input", required=True)
    p.add_argument("--out", required=True)

    p = sub.add_parser("score")
    p.add_argument("--evals", default=evals_default)
    p.add_argument("--case", required=True)
    p.add_argument("--trap", required=True)
    p.add_argument("--findings", required=True)
    p.add_argument("--any-location", action="store_true")
    p.add_argument("--exclude-low", action="store_true")
    p.add_argument("--demoted", default="")

    for name in ("trees", "shadow", "on"):
        p = sub.add_parser(name)
        p.add_argument("--findings-dir", required=True)
        p.add_argument("--work", required=True)
        p.add_argument("--replay", required=True)
        if name == "trees":
            p.add_argument("--date", default="")
        else:
            p.add_argument("--model", default=PINNED)
            p.add_argument("--timeout-ms", type=int, default=3000)
        if name == "shadow":
            p.add_argument("--provider", required=True, choices=("typesafe", "custom"))
            p.add_argument("--base-url", default="")
            p.add_argument("--api-key-env", default="")
            p.add_argument("--set", default="base", choices=("base", "reps"))
            p.add_argument("--allow-unasked", action="store_true")
        if name == "on":
            p.add_argument("--filter", required=True, choices=("off", "dedup", "confidence", "dedup-confidence"))
            p.add_argument("--same-defect", type=float, default=None)
            p.add_argument("--claim-supported", type=float, default=None)

    p = sub.add_parser("table")
    p.add_argument("--replay", required=True)
    p.add_argument("--model", default=PINNED)

    p = sub.add_parser("serve")
    p.add_argument("--table", required=True)
    p.add_argument("--port-file", required=True)
    p.add_argument("--log", default="")
    p.add_argument("--lifetime", type=float, default=60.0)

    p = sub.add_parser("inspect")
    p.add_argument("--replay", required=True)
    p.add_argument("--evals", default=evals_default)

    p = sub.add_parser("aggregate")
    p.add_argument("--replay", required=True)
    p.add_argument("--findings-dir", required=True)
    p.add_argument("--evals", default=evals_default)
    p.add_argument("--model", default=PINNED)
    p.add_argument("--results", default="")
    p.add_argument("--runs-json", default="")
    p.add_argument("--choose", type=int, default=1)
    p.add_argument("--judge", default="2,3")
    p.add_argument("--relabel", action="store_true")

    a = ap.parse_args(argv)
    handlers = {"export-recovered": cmd_export_recovered, "convert": cmd_convert, "score": cmd_score,
                "trees": cmd_trees, "shadow": cmd_shadow, "table": cmd_table, "serve": cmd_serve,
                "on": cmd_on, "inspect": cmd_inspect, "aggregate": cmd_aggregate}
    try:
        return handlers[a.cmd](a)
    except Failed as e:
        out("STATE", "failed")
        out("ERROR", str(e).replace("\n", " "))
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
