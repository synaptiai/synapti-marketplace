"""What the System One review sites share: bin/_flow_s1_confidence.py
(review.confidence), bin/_flow_s1_challenge.py (review.challenge) and
bin/_flow_s1_dedup.py (review.dedup), and the git call bin/_flow_finding_state.py
makes. One copy, so a change to a reason list, the git environment or the
request reaches every site.

Each site asks through bin/flow-s1.sh, the client, which reads the provider
settings, applies the threshold in system-one/questions.yaml and writes the
records; nothing here reads a setting.

The state of each request is written to a file in a directory this process
makes once (tempfile.mkdtemp) and removes when it exits, also on SIGTERM:
stop_on_sigterm() turns the signal into SystemExit, so subprocess.run stops
the client it is waiting on and the cleanup runs.
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

import atexit
import hashlib
import json
import re
import shutil
import signal
import subprocess
import tempfile
import time
from typing import NamedTuple

# Stop asking after this many timeout or connection results in a row (the
# provider is down, and every further call would wait for its timeout), or
# this many client-error or internal-error results in a row (the client
# fails before it can ask, and would fail the same way for every item).
MAX_CONSECUTIVE_DOWN = 2
# Total time for asking, in seconds. No call starts after it, and each call
# is given what is left of it: the client is told to end its request by then
# (--max-timeout-ms) and is stopped CALL_MARGIN_S later if it has not, so
# asking ends within 95 s, before the 120 s a command's Bash call gets by
# default, whatever timeoutMs a local model needs. The FLOW_S1_*_BUDGET_S
# variables may lower it, never raise it: a repository's
# .claude/settings.json can set environment variables.
MAX_BUDGET_S = 90
CALL_MARGIN_S = 5

ID_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*$")
REF_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/#@+-]*$")
RUN_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
MODEL_UNSAFE = re.compile(r"[^A-Za-z0-9._:/@+-]")
# The non-security categories of references/finding-schema.md, and the
# grounding pass's security categories (commands/review.md). The rule
# DROPPED_FINDING_BLOCK applies; review.dedup also accepts the error-handling
# sub-types (bin/_flow_s1_dedup.py).
NON_SECURITY = ("correctness", "edge-case", "error-handling", "performance", "tests", "runtime",
                "visual", "breaking-change", "duplication", "scope", "conventions",
                "claim-verification")
SECURITY = ("security", "dependency", "auth", "injection", "xss", "idor", "secrets")
# Reasons that send nothing and would be the same for every item.
STOP_REASONS = ("settings-refused", "provider-none", "python-missing", "mode-off",
                "invalid-settings", "insecure-url", "no-api-key", "unknown-site",
                "no-threshold", "questions-invalid")
DOWN_REASONS = ("timeout", "connection")
BROKEN_REASONS = ("client-error", "internal-error")
# Reasons for which a request reached the provider, so the state is kept.
SENT_REASONS = ("shadow", "below-threshold", "timeout", "connection", "redirect", "malformed",
                "missing-answer", "abstained")
NO_ANSWER_RE = re.compile(r"^flow-s1: no answer: ([a-z0-9-]+)", re.M)


class Blocked(Exception):
    pass


def ascii_match(rx, s):
    return isinstance(s, str) and s.isascii() and rx.match(s) is not None


def encodable(*values):
    """True when every string among the values (and inside lists of them) can
    be written as UTF-8. A JSON file can hold a lone surrogate (\\ud800),
    which json.load accepts and no UTF-8 writer can encode."""
    for v in values:
        if isinstance(v, list):
            if not encodable(*v):
                return False
        elif isinstance(v, str):
            try:
                v.encode("utf-8")
            except UnicodeEncodeError:
                return False
    return True


def stop_on_sigterm():
    """SIGTERM ends this process through SystemExit, so the finally blocks,
    the stop of a running client and the atexit cleanup all run."""
    def _stop(signum, _frame):
        raise SystemExit(128 + signum)
    signal.signal(signal.SIGTERM, _stop)


_PRIVATE = []


def private_dir():
    """A directory only this user can read, made once per process and
    removed when the process exits."""
    if not _PRIVATE:
        d = tempfile.mkdtemp(prefix="flow-s1-")
        _PRIVATE.append(d)
        atexit.register(shutil.rmtree, d, True)
    return _PRIVATE[0]


_EMPTY_TREE = {}


def git(tree, *args):
    """git -C <tree> <args>, stdout or None. The tree may be someone else's
    pull request: no repository it commits is loaded (safe.bareRepository)
    and none of its attributes apply (GIT_ATTR_SOURCE is the empty tree, in
    the tree's own object format), so no textconv or filter driver runs.
    Pathspecs are literal (GIT_LITERAL_PATHSPECS), so a path is never read as
    a pattern."""
    env = dict(os.environ)
    env.update({"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "safe.bareRepository",
                "GIT_CONFIG_VALUE_0": "explicit", "GIT_LITERAL_PATHSPECS": "1"})
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


def write_private(path, data):
    """Write data (bytes) to path through a temporary file in the same
    directory, never through a symlink."""
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


def keep_state(bin_dir, run_dir, name, data, what):
    """Copy the state sent beside the run as <name>.json, never through a
    symlink; `what` names it in the warning when it cannot be saved."""
    keep = os.path.join(run_dir, "system-one-state")
    try:
        r = subprocess.run([os.path.join(bin_dir, "flow-mkdir.sh"), "--", keep],
                           capture_output=True, timeout=30)
        if r.returncode != 0:
            raise OSError("flow-mkdir.sh refused")
        write_private(os.path.join(keep, name + ".json"), data)
    except (OSError, subprocess.SubprocessError):
        sys.stderr.write("flow: WARN: the state for %s could not be saved beside the run\n" % what)


def finding_ref(prefix, fid):
    """<prefix>/<id>, or <prefix>/id:<16 hex of its sha256> when that would
    pass the 200 characters flow-s1.sh takes."""
    ref = "%s/%s" % (prefix, fid)
    if len(ref) > 200:
        ref = "%s/id:%s" % (prefix, hashlib.sha256(fid.encode("ascii")).hexdigest()[:16])
    return ref


def run_dir_of(run_id):
    """(.flow/runs/<run id> of the repository the process runs in, whether
    the state is kept there): kept only when that run directory exists and is
    not a symlink."""
    top = (git(".", "rev-parse", "--show-toplevel") or b"").decode("utf-8", "replace").strip()
    run_dir = os.path.join(top, ".flow", "runs", run_id) if (run_id and top) else ""
    return run_dir, bool(run_dir) and os.path.isdir(run_dir) and not os.path.islink(run_dir)


def budget(raw):
    """The budget in whole seconds, 1 to MAX_BUDGET_S; any other value is
    MAX_BUDGET_S."""
    if raw.isascii() and raw.isdigit() and len(raw) <= 9:
        return min(max(int(raw), 1), MAX_BUDGET_S)
    return MAX_BUDGET_S


class Reply(NamedTuple):
    """An answer the client accepted (exit 0)."""
    p: float
    confidence: float
    model: str
    truncated: bool


def ask(run_id, bin_dir, state_bytes, current, ref, deadline, site, question):
    """(exit status, Reply or None, reason or None): exit 0 comes with a
    Reply and no reason, any other with None and a reason. deadline is the
    time.monotonic() value the budget ends at: the client is told to end its
    request by then, and is stopped CALL_MARGIN_S later if it has not."""
    left = max(deadline - time.monotonic(), 0)
    fd, path = tempfile.mkstemp(prefix="state.", suffix=".json", dir=private_dir())
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(state_bytes)
        cmd = [os.path.join(bin_dir, "flow-s1.sh"), "ask", "--site", site, "--state-file", path,
               "--state-format", "json", "--current", current, "--ref", ref,
               "--max-timeout-ms", str(int(left * 1000))]
        if run_id:
            cmd += ["--run-id", run_id]
        try:
            r = subprocess.run(cmd, capture_output=True, timeout=left + CALL_MARGIN_S)
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
        return 0, Reply(float(p), float(conf),
                        MODEL_UNSAFE.sub("?", str(reply.get("model") or ""))[:200] or "unknown",
                        reply.get("truncated") is True), None
    m = NO_ANSWER_RE.search(err)
    return 3, None, (m.group(1) if (r.returncode == 3 and m) else "client-error")


class Asking:
    """The stop rules every site applies while it asks: MAX_ASKED calls, the
    budget, MAX_CONSECUTIVE_DOWN timeout or connection results in a row
    (provider-down), the same number of client-error or internal-error
    results in a row (client-broken), and a reason that sends nothing for any
    item (STOP_REASONS). It also counts the reasons of the calls that gave no
    answer."""

    def __init__(self, max_asked, limit):
        self.max_asked = max_asked
        self.limit = limit
        self.started = time.monotonic()
        self.asked = 0
        self.down = 0
        self.broken = 0
        self.stop_reason = None
        self.stopped = None
        self.no_answer = {}

    @property
    def deadline(self):
        return self.started + self.limit

    def check(self):
        """The reason no further call may start, or None."""
        if not self.stopped:
            if self.asked >= self.max_asked:
                self.stopped = "cap"
            elif time.monotonic() - self.started >= self.limit:
                self.stopped = "budget"
        return self.stopped

    def record(self, reason):
        """Count one call's result. False when the reason sends nothing for
        any item: the call is not counted as asked, and nothing more is."""
        if reason in STOP_REASONS:
            self.stop_reason = reason
            return False
        self.asked += 1
        self.down = self.down + 1 if reason in DOWN_REASONS else 0
        self.broken = self.broken + 1 if reason in BROKEN_REASONS else 0
        if reason is not None:
            self.no_answer[reason] = self.no_answer.get(reason, 0) + 1
        if self.down >= MAX_CONSECUTIVE_DOWN:
            self.stopped = "provider-down"
        elif self.broken >= MAX_CONSECUTIVE_DOWN:
            self.stopped = "client-broken"
        return True

    def no_answer_lines(self, prefix):
        """<prefix><REASON>=<n> for each reason a call gave no answer for."""
        return ["%s%s=%d" % (prefix, r.upper().replace("-", "_"), n) for r, n in sorted(self.no_answer.items())]


def sent(rc, reason):
    """Whether a request reached the provider, so its state is kept."""
    return rc == 0 or reason in SENT_REASONS or (reason or "").startswith("http-")


def main(run, names):
    """Parse --<name> options into run(a); print STATE=blocked and exit 2 on
    Blocked or any other error, never a traceback."""
    import argparse
    stop_on_sigterm()
    ap = argparse.ArgumentParser()
    for name in names:
        ap.add_argument("--" + name, default="")
    a = ap.parse_args()
    try:
        return run(a)
    except Blocked as e:
        sys.stdout.write("STATE=blocked\nERROR=%s\n" % e)
        return 2
    except Exception as e:  # noqa: BLE001 - the caller keeps what it had, never a traceback
        sys.stdout.write("STATE=blocked\nERROR=internal error (%s)\n" % type(e).__name__)
        return 2
