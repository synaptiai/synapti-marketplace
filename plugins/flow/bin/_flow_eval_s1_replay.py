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
                    reviewers attributed by the line their subagents cited
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

BIN_DIR = os.path.dirname(os.path.abspath(__file__))
PLUGIN_ROOT = os.path.dirname(BIN_DIR)
sys.path.insert(0, BIN_DIR)
import _flow_eval as fe

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
# The non-security categories of references/finding-schema.md, as both sites
# accept them.
NON_SECURITY = ("correctness", "edge-case", "error-handling", "performance", "tests", "runtime",
                "visual", "breaking-change", "duplication", "scope", "conventions",
                "claim-verification")


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
        location = f.get("location") if isinstance(f.get("location"), str) else ""
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


def cited_ranges(text, module):
    ranges = []
    pats = [re.compile(r"\b%s(?:\.py)?:(\d+)(?:\s*[-–]\s*(\d+))?" % re.escape(module)),
            re.compile(r"\blines?\s+(\d+)(?:\s*(?:-|–|to)\s*(\d+))?", re.I)]
    for pat in pats:
        for m in pat.finditer(text):
            lo = int(m.group(1))
            hi = int(m.group(2)) if m.group(2) else lo
            ranges.append((min(lo, hi), max(lo, hi)))
    return ranges


def cmd_export_recovered(a):
    records = read_json(a.runs_json)
    if not isinstance(records, list):
        raise Failed("--runs-json is not a JSON list")
    exported = findings_n = attributed = unattributed = mismatch = missing = unparsed = 0
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
        findings, reason = fe.extract_findings(final)
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
            agents.append((kind, cited_ranges(body, module)))
        n_attr = n_un = 0
        for f in findings:
            if not isinstance(f, dict):
                continue
            findings_n += 1
            if isinstance(f.get("reviewers"), list) and f["reviewers"]:
                n_attr += 1
                continue
            line = fe.finding_line(f.get("line"))
            names = []
            for kind, ranges in agents:
                if line is not None and any(lo <= line <= hi for lo, hi in ranges) and kind not in names:
                    names.append(kind)
            if names:
                f["reviewers"] = names
                n_attr += 1
            else:
                f["reviewers"] = ["unattributed"]
                n_un += 1
        attributed += n_attr
        unattributed += n_un
        model = str(r.get("model") or "default").replace("/", "_")
        dest = os.path.join(a.out, model, a.arm, r["case"], r["trap"], "%d.json" % int(r["run"]))
        write_json(dest, findings)
        exported += 1
        report.append({"run": "/".join((model, a.arm, r["case"], r["trap"], str(r["run"]))),
                       "session_id": sid, "attributed": n_attr, "unattributed": n_un})
    write_json(os.path.join(a.out, "export-report.json"),
               {"runs": report, "missing_transcripts": missing, "rescore_mismatch": mismatch})
    out("EXPORTED", exported)
    out("FINDINGS", findings_n)
    out("ATTRIBUTED", attributed)
    out("UNATTRIBUTED", unattributed)
    out("RESCORE_MISMATCH", mismatch)
    out("MISSING_TRANSCRIPTS", missing)
    out("UNPARSED", unparsed)
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
    """Set one question's default threshold in a copy of questions.yaml, by
    its line, and check the result as the client reads it."""
    import yaml
    with open(questions_path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    i = lines.index("  %s:" % site)
    j = next(k for k in range(i + 1, len(lines)) if lines[k] == "    thresholds:")
    k = next(k for k in range(j + 1, len(lines)) if lines[k] == "      %s:" % question)
    m = next(m for m in range(k + 1, len(lines)) if lines[m].startswith("        default: "))
    lines[m] = "        default: %s" % fmt_t(value)
    with open(questions_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    with open(questions_path, encoding="utf-8") as fh:
        t = yaml.safe_load(fh)["sites"][site]["thresholds"][question]
    if float(t["default"]) != float(value) or (t.get("models") or {}):
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
        info = {"unasked": []}
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
                if intval(v, "UNASKED") or v.get("STOPPED"):
                    info["unasked"].append("dedup:UNASKED=%s STOPPED=%s" % (v.get("UNASKED"), v.get("STOPPED", "")))
            rc, conf_out = run_site(plugin, "flow-s1-confidence.sh",
                                    ["--findings", inp, "--tree", tree, "--ref-prefix", run.ref + ("/reps" if suffix else ""),
                                     "--run-id", run.run_id, "--demoted-out", os.path.join(rdir, "demoted%s.txt" % suffix)],
                                    tree, env, os.path.join(rdir, "confidence%s" % suffix))
            if rc != 0:
                fails.add("blocked")
            totals["conf"] += intval(kv(conf_out), "S1_ASKED")
            info["unasked"] += ["confidence:%s" % r for r in confidence_reasons(conf_out) if r in UNASKED_REASONS]
            for reason in stop_reasons(dedup_out, conf_out):
                fails.add("stop-reason:" + reason)
            for rec in read_jsonl(os.path.join(flow_run, "system-one.jsonl")):
                if rec.get("model") != pinned:
                    fails.add("model-not-pinned")
            shutil.copytree(flow_run, os.path.join(rdir, "run%s" % suffix))
            shutil.rmtree(flow_run)
        if info["unasked"]:
            totals["unasked"] += 1
            if not a.allow_unasked:
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
    entries, conflicts, unanswered, unmatched, largest = {}, 0, 0, 0, 0
    wrong_model = 0
    for rundir in sorted(glob.glob(os.path.join(a.replay, "shadow", "*", "**", "run*", ""), recursive=True)):
        if not os.path.isfile(os.path.join(rundir, "system-one.jsonl")):
            continue
        by_digest = {}
        for rec in read_jsonl(os.path.join(rundir, "system-one.jsonl")):
            by_digest.setdefault((rec.get("site"), rec.get("state_sha256")), rec)
        for path in sorted(glob.glob(os.path.join(rundir, "system-one-state", "*.json"))):
            name = os.path.basename(path)
            site = DEDUP if name.startswith("dedup-") else CONFIDENCE if name.startswith("confidence-") else None
            if site is None:
                continue
            with open(path, "rb") as fh:
                raw = fh.read()
            rec = by_digest.get((site, hashlib.sha256(raw).hexdigest()))
            if rec is None:
                unmatched += 1
                continue
            state = json.loads(raw.decode("utf-8"))
            largest = max(largest, len(json.dumps(state, ensure_ascii=False)))
            answer = rec.get("answer") if isinstance(rec.get("answer"), dict) else None
            p = answer.get("p") if answer else None
            if rec.get("model") != a.model:
                wrong_model += 1
            entry = {"site": site, "question": QUESTION[site], "p": p, "model": rec.get("model"),
                     "result": rec.get("result")}
            key = state_key(state)
            if key in entries:
                if entries[key]["p"] != p:
                    conflicts += 1
                continue
            entries[key] = entry
            if p is None:
                unanswered += 1
    write_json(os.path.join(a.replay, "table.json"), {"model": a.model, "entries": entries})
    out("TABLE_ENTRIES", len(entries))
    out("TABLE_CONFLICTS", conflicts)
    out("TABLE_UNANSWERED", unanswered)
    out("TABLE_UNMATCHED", unmatched)
    out("TABLE_WRONG_MODEL", wrong_model)
    out("LARGEST_STATE_CHARS", largest)
    out("STATE_LIMIT_CHARS", STATE_TOKEN_CAP * 4)
    bad = unmatched or wrong_model or largest > STATE_TOKEN_CAP * 4
    out("TABLE_STATE", "failed" if bad else "ok")
    return 1 if bad else 0


# ----------------------------------------------------------------- the replay server

class Replay:
    def __init__(self, table):
        self.entries = table.get("entries") or {}
        self.lock = threading.Lock()
        self.requests = self.hits = self.misses = self.unanswered = 0
        self.log = []

    def answer(self, body):
        """(status, reply)."""
        state = body.get("state") if isinstance(body, dict) else None
        questions = body.get("questions") if isinstance(body, dict) else None
        qid = next(iter(questions)) if isinstance(questions, dict) and len(questions) == 1 else None
        key = state_key(state) if state is not None else ""
        entry = self.entries.get(key)
        with self.lock:
            self.requests += 1
            if entry is None or entry.get("question") != qid:
                self.misses += 1
                self.log.append({"key": key, "question": qid, "hit": False})
                return 500, {"detail": "no recorded answer for this state"}
            self.hits += 1
            self.log.append({"key": key, "question": qid, "hit": True})
            if entry.get("p") is None:
                # Recorded without an answer: no answer again.
                self.unanswered += 1
                return 503, {"detail": "recorded without an answer (%s)" % entry.get("result")}
        return 200, {"model": entry.get("model"), "answers": {qid: {"type": "noul", "noul": entry["p"]}}}


def start_server(replay):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *args):
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

    for _ in range(5):
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        # Never the port a local imajev server listens on.
        if server.server_address[1] != 8765:
            break
        server.server_close()
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
            per_run[run.key] = {"merged": lines_of(dedup_out or "", "MERGED"),
                                "demoted": sorted(fe.read_demoted(demoted))}
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


def label_map(replay):
    labels = {}
    for row in read_json(os.path.join(replay, "merged-pairs.json"), []) or []:
        if isinstance(row, dict):
            labels[(row.get("run"), row.get("a"), row.get("b"))] = (row.get("label"), row.get("reason") or "")
    return labels


def cmd_inspect(a):
    rows = collect_pairs(a.replay, a.evals)
    labels = label_map(a.replay)
    unlabelled = 0
    for row in rows:
        label, reason = labels.get((row["run"], row["a"], row["b"]), (None, ""))
        row["label"], row["reason"] = label, reason
        if label not in ("same", "different"):
            unlabelled += 1
    write_json(os.path.join(a.replay, "merged-pairs.json"), rows)
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


def ceiling_findings(findings, hunks, module):
    """The finding set with every second P1/P2 finding on the hit hunk whose
    category the sites accept taken out: what a perfect merge could remove."""
    hit_hunk = None
    keep = []
    for f in findings:
        priority = str(f.get("priority", "")).upper()
        if priority not in ("P1", "P2") or str(f.get("confidence", "")).upper() == "LOW":
            keep.append(f)
            continue
        h = hunk_of(f.get("location") or "", hunks, module)
        if h != "outside" and hit_hunk is None:
            hit_hunk = h
            keep.append(f)
        elif h != "outside" and h == hit_hunk and str(f.get("category", "")).strip().lower() in NON_SECURITY:
            continue
        else:
            keep.append(f)
    return keep


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
    """Re-scoring each kept findings file with the unchanged scorer gives the
    run's recorded score."""
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
        return "not-checked", 0
    mismatch = 0
    for run in runs:
        rec = records.get(run.key)
        text = "```json\n%s\n```" % json.dumps(read_json(run.path, []))
        got = fe.score_review(case_dir(a.evals, run.case), run.trap, text)
        if rec is None or any(got.get(k) != rec.get(k) for k in ("hit", "false_findings", "scored_findings")):
            mismatch += 1
    return ("flagged" if mismatch else "ok"), mismatch


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
    incomplete, inc_source = incompletes(a)
    choose = a.choose
    judge = [int(x) for x in a.judge.split(",") if x.strip()]
    models = sorted({r.model for r in runs})

    # Scores per run: plain (LOW excluded and kept), ceiling, and per point.
    rows = {}
    for run in runs:
        inputs = convert(read_json(run.path, []))[0]
        by_id = {f["id"]: f for f in inputs}
        cdir = case_dir(a.evals, run.case)
        hunks, _src = fe.hunks_for_trap(cdir, run.trap)
        module = fe.variant_paths(cdir, run.trap)[2]
        inc = incomplete.get(run.key, False)
        row = {"plain": score(a, run, inputs), "plain_low_kept": score(a, run, inputs, exclude_low=False),
               "ceiling": score(a, run, ceiling_findings(inputs, hunks, module)), "points": {}}
        for p in pts:
            rdir = os.path.join(a.replay, "on", p["point"], run.key)
            outs = read_json(os.path.join(rdir, "out.json"))
            if not isinstance(outs, list):
                continue
            demoted = fe.read_demoted(os.path.join(rdir, "demoted.txt"))
            guarded = undo_different(outs, by_id, run.key, labels)
            row["points"][p["point"]] = {
                "guarded": score(a, run, guarded, demoted),
                "raw": score(a, run, outs, demoted),
                "any_location": score(a, run, guarded, demoted, any_location=True),
                "low_kept": score(a, run, guarded, demoted, exclude_low=False),
                "demoted": len(demoted),
                "demoted_hits": sum(1 for f in inputs if f["id"] in demoted
                                    and hunk_of(f["location"], hunks, module) != "outside"),
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

    report = {"model": a.model, "choose_replication": choose, "judge_replications": judge,
              "incomplete_source": inc_source or "not known", "models": {}, "sites": {}, "checks": {}}
    all_reps = sorted({run.n for run, _ in rows.values()})
    for m in models:
        entry = {"runs": sum(1 for run, _ in rows.values() if run.model == m),
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
            f = {"filter": p["filter"], "same_defect": p.get("same_defect"), "claim_supported": p.get("claim_supported"),
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

    checks = run_checks(a, runs, rows, pts, report, labels)
    report["checks"] = checks
    flagged = [k for k, v in checks.items() if v["status"] == "flagged"]
    for site in (DEDUP, CONFIDENCE):
        s = report["sites"][site]
        s["verdict"] = "held-by-checks" if flagged else s["rule"]
    write_json(os.path.join(a.replay, "report.json"), report)
    with open(os.path.join(a.replay, "report.md"), "w", encoding="utf-8") as fh:
        fh.write(render(report))
    for name in sorted(checks):
        out("CHECK_" + name.upper().replace("-", "_"), checks[name]["status"])
    out("DIFFERENT_MERGES", checks["different-merges"]["count"])
    out("JUDGED_REPLICATIONS", ",".join(str(r) for r in judge))
    for site in (DEDUP, CONFIDENCE):
        s = report["sites"][site]
        tag = site.upper().replace(".", "_")
        if s.get("chosen") is not None:
            out("CHOSEN_" + tag, fmt_t(s["chosen"]))
        out("RULE_" + tag, s["rule"])
        out("VERDICT_" + tag, s["verdict"])
    out("AGGREGATE_STATE", "ok")
    return 0


def decide(report, models, site_points, tkey, choose):
    """The bar of references/review-precision-eval.md for one site."""
    result = {"points": [p["point"] for p in site_points], "chosen": None, "rule": None, "reading": []}
    if len(models) < 2:
        result["rule"] = "insufficient-models"
        result["reading"].append("The bar needs two review models; %d ran." % len(models))
        return result
    if not site_points:
        result["rule"] = "not-run"
        return result
    best = None
    for p in site_points:
        gains, recall_ok = [], True
        for m in models:
            plain = report["models"][m]["plain"]["replications"].get(str(choose))
            filt = report["models"][m]["filters"][p["point"]]["replications"].get(str(choose))
            if not plain or not filt or plain["f1"] is None or filt["f1"] is None or not plain["scored_runs"]:
                recall_ok = False
                break
            gains.append(filt["f1"] - plain["f1"])
            if filt["recall"] < plain["recall"] - 1.0 / plain["scored_runs"] - 1e-9:
                recall_ok = False
        if not recall_ok:
            result["reading"].append("%s loses more than one run's worth of recall on replication %d, or has no score there." % (p["point"], choose))
            continue
        mean = sum(gains) / len(gains)
        if best is None or mean > best[0] + 1e-9 or (abs(mean - best[0]) <= 1e-9 and p[tkey] > best[1][tkey]):
            best = (mean, p)
    if best is None:
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


def run_checks(a, runs, rows, pts, report, labels):
    checks = {}
    shadow = read_json(os.path.join(a.replay, "shadow", "base", "pass.json"))
    if isinstance(shadow, dict):
        per = shadow.get("runs") or {}
        zero = sum(1 for v in per.values() if not v.get("pairs_candidate"))
        checks["pairs-candidate"] = {"status": "flagged" if per and zero * 2 > len(per) else "ok",
                                     "runs_without_candidates": zero, "runs": len(per)}
        unasked = shadow.get("totals", {}).get("unasked", 0)
        checks["unasked"] = {"status": "flagged" if unasked else "ok", "runs": unasked}
    else:
        checks["pairs-candidate"] = {"status": "not-run"}
        checks["unasked"] = {"status": "not-run"}
    table = read_json(os.path.join(a.replay, "table.json"))
    entries = list(((table or {}).get("entries") or {}).values())
    answered = [e for e in entries if e.get("p") is not None]
    if not entries:
        checks["answers"] = {"status": "not-run"}
    else:
        near = all(0.4 <= e["p"] <= 0.6 for e in answered) if answered else True
        wrong = sum(1 for e in entries if e.get("model") != a.model)
        checks["answers"] = {"status": "flagged" if near or wrong else "ok", "answered": len(answered),
                             "unanswered": len(entries) - len(answered), "wrong_model": wrong}
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
    flagged, tested = [], False
    for filt, site, tkey in (("dedup", DEDUP, "same_defect"), ("confidence", CONFIDENCE, "claim_supported")):
        fp = [p for p in pts if p["filter"] == filt]
        if len(fp) < 2:
            continue
        tested = True
        same = all(len({row["points"].get(p["point"], {}).get("identity") for p in fp}) == 1 for _run, row in rows.values())
        lo, hi = min(p[tkey] for p in fp), max(p[tkey] for p in fp)
        between = any(lo <= abs(2 * e["p"] - 1) < hi for e in answered if e.get("site") == site)
        if same and between:
            flagged.append(filt)
    checks["thresholds"] = {"status": "flagged" if flagged else ("ok" if tested else "not-run"), "filters": flagged}
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
    status, mismatch = rescore_check(a, runs)
    checks["rescore"] = {"status": status, "mismatch": mismatch}
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
        chosen = "" if s.get("chosen") is None else " at %s" % fmt_t(s["chosen"])
        lines.append("- `%s`: %s%s. %s" % (site, s["verdict"], chosen, " ".join(s["reading"])))
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
