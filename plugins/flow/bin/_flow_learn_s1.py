"""System One screening of the /flow:learn correction candidates (site
learn.correction), and the writer of the session's verdict on each screened
candidate. See references/system-one.md and commands/learn.md.

  _flow_learn_s1.py screen --table <file> --miner <path> --flow-s1 <path>
                           [--transcript-dir <dir>]
  _flow_learn_s1.py verdict --line <full transcript path>:<line_no>
                            --verdict kept|dropped --state-dir <dir>

screen: the Transcript Corrections block of commands/learn.md calls it when
bin/flow-s1-mode.sh gives shadow or on for learn.correction (a repository can
lower the user's mode there, never raise it). --table holds the markdown output of flow-mine-corrections.sh from the
run the section already makes. This runs the miner again with --format jsonl and
the same flags, asks bin/flow-s1.sh about each candidate (one call each, at
most BUDGET_CALLS calls, none started after BUDGET_SECONDS seconds), and, when at least one
call answered, prints the markdown output again with the table rows reordered
and four S1_ lines added. When no call answered (shadow mode, no provider, every
call failed), it prints nothing, and the caller prints the table as it was.
No row is added, removed or changed: rows are moved whole. The miner is not
changed and makes no network call; the calls are made here.

verdict: Phase 2 of /flow:learn calls it (through bin/flow-learn-verdict.sh)
for each row it re-read, with kept or dropped and the full path of the
transcript it re-read (the miner's Line cell cuts a path over 200 characters;
a cut path is refused). It writes one line to
learn-correction-verdicts.jsonl in the per-user state directory, but only
when a learn.correction record for that transcript line from the last 24
hours is in system-one.jsonl there; otherwise it writes nothing. It never
prints transcript text. Exit 0 in both cases; 2 for a usage error, a cut
path included.
"""

# The guard below is the canonical form tests/syspath-guard.test.sh checks for,
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
import stat
import subprocess
import tempfile
import time
from datetime import datetime, timedelta, timezone

SITE = "learn.correction"
QUESTION = "is_correction"
# How long screening may take in all, and how many candidates it asks about.
# The candidates left when either runs out are not asked and stay unanswered.
# No call starts after BUDGET_SECONDS; one already started may still run to
# its own timeout, so screening ends within BUDGET_SECONDS plus one call.
BUDGET_SECONDS = 60
BUDGET_CALLS = 100
# flow-s1.sh ends its own request at timeoutMs (at most 30 s); this bounds the
# whole call, settings reads included, in case something else hangs.
CALL_TIMEOUT_SECONDS = 45
MINER_TIMEOUT_SECONDS = 300
VERDICT_WINDOW = timedelta(hours=24)

ROW = re.compile(r"\| (\d+) \| ")
STEM = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,150}", re.ASCII)


def ref_for(path, line_no):
    """The --ref of one candidate: transcript:<file stem>/<line>. A stem that
    does not fit the ref shape is named by the start of its path digest."""
    base = os.path.basename(path)
    stem = base[:-len(".jsonl")] if base.endswith(".jsonl") else base
    if not STEM.fullmatch(stem):
        stem = "sha256-" + hashlib.sha256(path.encode("utf-8", "surrogateescape")).hexdigest()[:16]
    return "transcript:%s/%d" % (stem, int(line_no))


# The miner renders each row with these two functions (bin/flow-mine-
# corrections.sh, cell and truncate). A row is matched to its candidate by
# rendering the candidate again and comparing the whole line, so a change in
# the miner rendering shows as a mismatch, never as a row given another row
# answer.
def _truncate(s, n):
    s = s.replace("\r", "")
    if len(s) <= n:
        return s
    return s[: n - 1] + "…"


def _cell(s, n):
    s = " ".join(str(s).split())
    s = s.replace("|", "\\|")
    return _truncate(s, n)


def render_row(i, c):
    return (f"| {i} | {_cell(c['session_id'], 40)} | {_cell(c['timestamp'], 24)} | "
            f"{_cell(c['transcript_path'], 200)}:{c['line_no']} | {_cell(c['text'], 240)} | "
            f"{_cell(c['preceded_by'], 120)} |")


def run_miner(miner, transcript_dir):
    cmd = [miner, "--format", "jsonl", "--max-sessions", "50"]
    if transcript_dir:
        cmd += ["--transcript-dir", transcript_dir]
    try:
        r = subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, timeout=MINER_TIMEOUT_SECONDS)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    out = []
    for line in r.stdout.decode("utf-8", "surrogateescape").splitlines():
        if not line.strip():
            continue
        try:
            c = json.loads(line)
        except ValueError:
            return None
        if not isinstance(c, dict) or not isinstance(c.get("transcript_path"), str) \
                or not isinstance(c.get("line_no"), int) or isinstance(c.get("line_no"), bool) \
                or not isinstance(c.get("text"), str) or not isinstance(c.get("preceded_by"), str):
            return None
        out.append(c)
    return out


def ask(flow_s1, work, k, c):
    """p for one candidate, or None for no answer."""
    state = {"assistant_before": c["preceded_by"], "user_turn": c["text"]}
    try:
        data = json.dumps(state, ensure_ascii=False, sort_keys=True).encode("utf-8")
        path = os.path.join(work, "state-%d.json" % k)
        with open(path, "xb") as f:
            f.write(data)
    except (OSError, ValueError):
        return None
    cmd = [flow_s1, "ask", "--site", SITE, "--state-file", path, "--state-format", "json",
           "--current", "keyword-candidate", "--ref", ref_for(c["transcript_path"], c["line_no"])]
    try:
        r = subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, timeout=CALL_TIMEOUT_SECONDS)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    try:
        a = json.loads(r.stdout.decode("utf-8"))["answers"][QUESTION]
        p = a["p"]
    except (ValueError, KeyError, TypeError, UnicodeDecodeError):
        return None
    if isinstance(p, bool) or not isinstance(p, (int, float)) or not 0 <= p <= 1:
        return None
    return float(p)


def screen(args):
    try:
        with open(args.table, encoding="utf-8", errors="surrogateescape") as f:
            table = f.read()
    except OSError:
        return 0
    lines = table.split("\n")
    header = next((i for i, text in enumerate(lines) if text.startswith("| # | Session |")), None)
    if header is None:
        return 0
    rows = [i for i in range(header + 2, len(lines)) if ROW.match(lines[i])]
    if not rows:
        return 0
    cands = run_miner(args.miner, args.transcript_dir)
    if not cands:
        return 0
    joined = len(cands) == len(rows) and all(
        lines[r] == render_row(k + 1, c) for k, (r, c) in enumerate(zip(rows, cands)))

    answers = {}
    screened = 0
    partial = False
    start = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="flow-learn-s1.") as work:
        for k, c in enumerate(cands):
            if screened >= BUDGET_CALLS or time.monotonic() - start >= BUDGET_SECONDS:
                partial = True
                break
            screened += 1
            p = ask(args.flow_s1, work, k, c)
            if p is not None:
                answers[k] = p
    # Shadow mode never answers, and neither does any failure: the table is
    # then printed as the miner printed it.
    if not answers:
        return 0
    state = "mismatch" if not joined else ("partial" if partial else "ordered")
    if joined:
        first = sorted((k for k in answers if answers[k] >= 0.5), key=lambda k: (-answers[k], k))
        middle = [k for k in range(len(rows)) if k not in answers]
        last = [k for k in range(len(rows)) if k in answers and answers[k] < 0.5]
        moved = [lines[rows[k]] for k in first + middle + last]
        for r, text in zip(rows, moved):
            lines[r] = text
    s1 = ["S1_STATE=" + state, "S1_SCREENED=%d" % screened, "S1_ANSWERED=%d" % len(answers),
          "S1_RATED_CORRECTION=%d" % sum(1 for p in answers.values() if p >= 0.5)]
    at = header - 1 if header > 0 and lines[header - 1] == "" else header
    lines[at:at] = s1
    # The bytes the miner printed are written back as they were, a byte that
    # is not UTF-8 included.
    sys.stdout.buffer.write("\n".join(lines).encode("utf-8", "surrogateescape"))
    return 0


def _records(path):
    """The lines of a records file, read only when it is a regular file and
    not a symlink."""
    try:
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
    except OSError:
        return
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            os.close(fd)
            return
    except OSError:
        os.close(fd)
        return
    with os.fdopen(fd, "rb") as f:
        for raw in f:
            try:
                rec = json.loads(raw.decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                continue
            if isinstance(rec, dict):
                yield rec


def verdict(args):
    path, sep, line_no = args.line.rpartition(":")
    if not sep or not path or not line_no.isdigit() or not line_no.isascii():
        sys.stderr.write("flow-learn-verdict: --line must be <transcript_path>:<line_no>\n")
        return 2
    # The miner's Line cell ends a path longer than 200 characters with an
    # ellipsis. That cut path names no file and no record, so it is refused
    # rather than recorded as a line that was not screened.
    if path.endswith("\u2026"):
        sys.stderr.write("flow-learn-verdict: --line holds a cut path; pass the full path of the transcript\n")
        return 2
    if args.verdict not in ("kept", "dropped"):
        sys.stderr.write("flow-learn-verdict: --verdict must be kept or dropped\n")
        return 2
    d = args.state_dir
    if not d or not os.path.isabs(d) or os.path.islink(d) or not os.path.isdir(d):
        return 0
    ref = ref_for(path, int(line_no))
    now = datetime.now(timezone.utc)
    digest = None
    for rec in _records(os.path.join(d, "system-one.jsonl")):
        if rec.get("site") != SITE or rec.get("ref") != ref or not isinstance(rec.get("state_sha256"), str):
            continue
        try:
            ts = datetime.strptime(rec.get("ts", ""), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        except (TypeError, ValueError):
            continue
        if now - ts <= VERDICT_WINDOW:
            digest = rec["state_sha256"]
    if digest is None:
        return 0
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    try:
        from _journal_atomic import append_jsonl, JournalAtomicError
    except ImportError:
        return 0
    out = {"ts": now.strftime("%Y-%m-%dT%H:%M:%SZ"), "site": SITE, "ref": ref,
           "state_sha256": digest, "verdict": args.verdict}
    try:
        append_jsonl(os.path.join(d, "learn-correction-verdicts.jsonl"), out, lock_timeout=1.0)
    except (JournalAtomicError, OSError, ValueError) as e:
        sys.stderr.write("flow-learn-verdict: WARN: not writing the verdict: %s\n" % type(e).__name__)
    return 0


def main():
    ap = argparse.ArgumentParser(prog="_flow_learn_s1.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("screen")
    s.add_argument("--table", required=True)
    s.add_argument("--miner", required=True)
    s.add_argument("--flow-s1", required=True)
    s.add_argument("--transcript-dir", default="")
    v = sub.add_parser("verdict")
    v.add_argument("--line", required=True)
    v.add_argument("--verdict", required=True)
    v.add_argument("--state-dir", default="")
    a = ap.parse_args()
    if a.cmd == "screen":
        try:
            return screen(a)
        except Exception:  # noqa: BLE001 — the caller prints the table as it was
            return 0
    return verdict(a)


if __name__ == "__main__":
    sys.exit(main())
