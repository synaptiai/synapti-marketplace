"""[flow] The factory's `next` pass (plan 1a T11): sync with GitHub, apply
every job's stored events in the table's order, check the leases, and start
the launches that are due.

  cmd_next(argv)   `flow-factory.sh next --executor interactive|headless`

One pass, within flow.factory.nextBudgetSeconds. Before each step and each
job it compares the time left with MIN_LEFT seconds, and when less is left it
starts nothing more and prints its output.

Phase A (global lock): state.json pass_seq + 1, the job scan, the slot
counts, and whether the sync and the environment re-run are due.

Sync: the real gh, every call bounded by the time left. A job with a PR is
read with `gh api repos/<o>/<r>/pulls/<pr>`; a merge, a close or a head the
factory did not push adds its fact name to job.json pending_changes. The
creation scan reads the labelled open issues and asks the table's creation
row; a job it creates waits for the next pass. A call that times out or
exits non-zero gives no facts and leaves last_sync_at unchanged.

Environment re-run (_flow_factory_staleness.environment_recheck) when due.
While it fails, no launch_due is raised for any job.

Phase B (each job under its job lock): the events, in the table's
event_order: pass_first's github_change, the stored person events,
github_change while pending_changes is not empty, judge results, stage
results, the shell's pending-report lines (only from the lease's own
launcher), lease expiry, worker_parked and question_stored, sync_tick. A job
whose state changed ignores its later events of the pass; their files stay.

Phase C (global lock, then the job lock): launch_due for every job in a
state a worker, judge or directive runs, with no open directive, unless the
pass is paused (usage limit) or the environment re-run failed. A launching
row allocates the slot, creates the directive and sets job.directive under
both locks, so a second `next` sees it; the launcher
(`flow-factory.sh launch <id>`) is started after the locks are released.

Output: {"status": ...} JSON lines, then one of wait, idle or done. Exit 0,
or 3 when the table refused a move in the pass.

The facts 1a computes come from this module (Context.built): probes_stale,
clone_config_changed and tree_dirty (in that order: tree_dirty is not run
and reads false when the clone's config changed or it holds a nested
repository), attempts_exhausted, slot_free, slot_available,
orphan_group_alive, group_gone, unvouched_session_action and the sync's
pr_* facts. A pr_* fact other than pr_exists reads true while its name is in
job.json pending_changes, so a pass whose gh call failed reads the last
change the sync saw, not "false".

Every change the pass makes to job.json orphan_groups, snapshots or
pending_changes writes an events.jsonl line in the same job-lock hold, so
`rebuild` restores the field from the log. Each line carries the field's
whole new list, and the last line of a type gives the value:
  {"type":"orphan_group","directive":…,"pgid":…,"start":…,"stage":…,
   "recorded_at":…,"orphan_groups":[…]}        a group not confirmed gone
  {"type":"snapshot","ref":…,"k":…,"reason":…,"at":…,"snapshots":[…]}
  {"type":"pending_changes","added":[…],"pending_changes":[…]}
                                                the sync's new changes
A row that clears a pending change writes no such line: rebuild replays that
clear from the row's transition line, as apply() does.
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
import signal
import subprocess
import time
import uuid
from datetime import UTC, datetime
from urllib.parse import quote

_BIN_DIR = os.path.dirname(os.path.realpath(__file__))
if _BIN_DIR not in sys.path:
    sys.path.append(_BIN_DIR)

import _flow_factory as ff
from _flow_factory import Refused
import _flow_factory_jobs as jobs
import _flow_factory_schema as schema
import _flow_factory_git as fgit
import _flow_factory_caller as fcaller
import _flow_factory_staleness as staleness
# Through the module, never a from-import: the test entry point wraps
# choose and choose_creation on the module.
import _flow_factory_table as ftable
from _journal_atomic import JournalAtomicError, _atomic_write, _read_with_no_follow

PROG = "flow-factory.sh next"
MIN_LEFT = 2.0
# The rows after which a worker stage may resume its session (row 66b's
# launch effect; T11 Phase C step 3).
RESUME_ROWS = ("39", "39l", "44", "44r")
# The rows whose relaunch follows a snapshot of the tree (39d, 39ld).
SNAPSHOT_ROWS = ("39d", "39ld")
PERSON_EVENTS_PREFIX = "person_"
STAGE_EVENTS = ("stage_succeeded", "stage_failed")
PENDING_LATE_EVENTS = ("worker_parked", "question_stored")
CLONE_FACTS = ("clone_config_changed", "tree_dirty")
# The seam's bodies outcomes (plan 2.11 kind 4): (result outcome, result
# event, pending event).
BODY_OUTCOMES = {
    "succeeded": ("completed", "stage_succeeded", "stage_succeeded"),
    "failed": ("error", "stage_failed", "stage_failed"),
    "judge_accept": ("completed", None, "judge_accept"),
    "judge_reject": ("completed", None, "judge_reject"),
    "judge_needs_info": ("completed", None, "judge_needs_info"),
    "judge_approve": ("completed", None, "judge_approve"),
    "judge_escalate": ("completed", None, "judge_escalate"),
}
DEFAULT_TIMEOUT_SECONDS = 1800

# The status line groups, in the order `next` prints them (plan 2.6, T11
# Output): the probe lines first, then the rest.
GROUPS = ("probe", "sync", "unreadable", "usage", "budget", "orphan", "blocked", "clone", "refused", "other")


class FactFailed(Exception):
    """A built fact could not be computed this pass (a git command in the
    clone failed); the event is left for the next pass."""


# ---------------------------------------------------------------- small helpers

_epoch = jobs.epoch


def _utc_at(epoch):
    return datetime.fromtimestamp(epoch, UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def _number(value, default, minimum=0):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value < minimum:
        return default
    return value


def _read_json(path):
    """The JSON value of a regular file read without following a symlink;
    None when there is no such file or it cannot be read or parsed."""
    if not os.path.lexists(path):
        return None
    try:
        return json.loads(_read_with_no_follow(path))
    except (JournalAtomicError, UnicodeDecodeError, ValueError):
        return None


def _write_json(path, data, def_name):
    """Validate against the directive schema (def_name, or the top level
    for None) and replace the file atomically."""
    data = jobs._jsonable(data)
    errors = schema.validate(data, jobs.DIRECTIVE_SCHEMA, def_name)
    if errors:
        raise Refused(f"{def_name or 'directive'}_invalid {errors[0]}")
    try:
        _atomic_write(path, json.dumps(data, sort_keys=True, indent=2) + "\n")
    except JournalAtomicError as e:
        raise Refused(f"{def_name or 'directive'}_unwritable {e.summary}") from e


def _group_exists(pgid):
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False
    return True


def _wait_gone(pgid, seconds):
    end = time.monotonic() + max(0.0, seconds)
    while True:
        if not _group_exists(pgid):
            return True
        if time.monotonic() >= end:
            return False
        time.sleep(0.05)


def kill_group(pgid, start, wait):
    """SIGTERM to the process group, up to wait seconds for it to go, then
    SIGKILL and up to one more second; whether the group is confirmed gone
    (os.killpg(pgid, 0) gives ESRCH). A process group id is not given to a
    new process while any member of the group lives, so a group whose number
    now belongs to a leader with another start time is a new group, and the
    recorded one is gone: it is left alone (amendment A+8). With no recorded
    start (the launcher's ps failed) a live group cannot be told apart from
    a new one: it is not signalled and not taken as gone."""
    if not isinstance(pgid, int) or isinstance(pgid, bool) or pgid <= 1:
        return True
    if not _group_exists(pgid):
        return True
    if not isinstance(start, str):
        return False
    leader = fcaller.lstart(pgid)
    if leader is not None and leader != start:
        return True
    try:
        os.killpg(pgid, signal.SIGTERM)
    except OSError:
        pass
    if _wait_gone(pgid, wait):
        return True
    try:
        os.killpg(pgid, signal.SIGKILL)
    except OSError:
        pass
    return _wait_gone(pgid, 1.0)


def orphan_alive(entry):
    """An orphan_groups entry whose pgid is alive and whose leader runs with
    the recorded start time (A+8): a reused number is not this group."""
    pgid = entry.get("pgid") if isinstance(entry, dict) else None
    if not isinstance(pgid, int) or isinstance(pgid, bool) or pgid <= 1:
        return False
    return _group_exists(pgid) and fcaller.lstart(pgid) == entry.get("start")


def launcher_running(pid, start):
    """(alive, running): the pid runs with this start time, and it is not
    stopped (ps stat does not start with T)."""
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 1 or not isinstance(start, str):
        return False, False
    if fcaller.lstart(pid) != start:
        return False, False
    try:
        stat = subprocess.run(["/bin/ps", "-o", "stat=", "-p", str(pid)], env={"LC_ALL": "C"},
                              capture_output=True, text=True, timeout=10, check=False).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        stat = ""
    if not stat or stat.startswith("Z"):
        return False, False
    return True, not stat.startswith("T")


def _me():
    pid = os.getpid()
    return {"pid": pid, "start": fcaller.lstart(pid) or "", "ancestry": [pid, os.getppid()]}


# ---------------------------------------------------------------- the pass

class Pass:
    def __init__(self, paths, executor, started):
        self.paths = paths
        self.executor = executor
        self.started = started
        self.deadline = started + _number(jobs.setting("flow.factory.nextBudgetSeconds", 60), 60, 1)
        self.table = ftable.load_table()
        self.lines = {g: [] for g in GROUPS}
        self.refused = False
        self.pass_id = None
        self.state = None
        self.scanned = []
        self.sync_error = None
        self.moved = set()
        self.skipped = set()
        self.fresh_changes = {}
        self.env_failed = False
        self._platform = None
        self._record = None
        self._settings = {}
        self.me = _me()
        # A usage limit a shell report brought in: state.json paused_until,
        # written under the global lock after Phase B.
        self.pending_pause = None

    # time and settings ---------------------------------------------------
    def left(self):
        return self.deadline - time.time()

    def enough(self):
        return self.left() >= MIN_LEFT

    def lock_wait(self):
        return max(0.1, min(jobs.LOCK_TIMEOUT, self.left() - 1))

    def setting(self, key, default=None):
        return jobs.setting(key, default)

    def num(self, key, default, minimum=0):
        return _number(self.setting(f"flow.factory.{key}", default), default, minimum)

    def status(self, group, line):
        if line not in self.lines[group]:
            self.lines[group].append(line)

    def platform(self):
        if self._platform is None:
            self._platform = staleness.platform_state(self.paths.fdir, jobs.setting)
        return self._platform

    def record(self):
        if self._record is None:
            self._record = ff.read_record(os.path.join(self.paths.fdir, "probes.json"))
        return self._record

    # phase A ---------------------------------------------------------------
    def phase_a(self):
        with jobs.global_lock(self.paths, timeout=self.lock_wait()):
            state = jobs.read_state(self.paths)
            seq = state.get("pass_seq")
            state["pass_seq"] = (seq if isinstance(seq, int) and not isinstance(seq, bool) and seq >= 0 else 0) + 1
            jobs.write_state(self.paths, state)
            self.scanned = jobs.jobs(self.paths)
        self.state = state
        self.pass_id = f"p{state['pass_seq']}"
        now = time.time()
        interval = self.num("syncIntervalSeconds", 60)
        last = _epoch(state.get("last_sync_at"))
        self.sync_due = last is None or now - last >= interval
        self.env_due = staleness.environment_due(state, jobs.setting, now)
        until = _epoch(state.get("paused_until"))
        self.paused_until = state.get("paused_until") if until is not None and until > now else None

    def counts(self, job_list):
        holds = sum(1 for _, j in job_list if isinstance(j, dict) and j.get("holds_slot") is True)
        open_jobs = sum(1 for _, j in job_list if isinstance(j, dict)
                        and self.table.kind(j.get("state")) != "terminal" and j.get("state") != "queued")
        return holds, open_jobs

    # sync ------------------------------------------------------------------
    def gh(self, args):
        """(ok, parsed JSON) of one gh call within the time left. The first
        call that fails for a reason other than the time left is kept in
        sync_error, for the sync_failed status line."""
        gh = ff.which_real("gh")
        timeout = min(15, self.left() - 2)
        if timeout < 1:
            return False, None
        if not gh:
            self.sync_error = self.sync_error or "gh not found on PATH"
            return False, None
        env = {k: v for k, v in os.environ.items() if k not in ("FLOW_TIER_DIR", "FLOW_TIER_CALL")}
        env["GH_PROMPT_DISABLED"] = "1"
        rc, out, err = ff.run_cmd([gh] + args, self.paths.main, env, timeout=timeout)
        if rc != 0:
            first = next((x.strip() for x in (err or "").splitlines() if x.strip()), "")
            self.sync_error = self.sync_error or " ".join(f"gh exited {rc}: {first}".split())[:300]
            return False, None
        try:
            return True, json.loads(out)
        except ValueError:
            self.sync_error = self.sync_error or "gh printed output that is not JSON"
            return False, None

    def sync(self):
        if not self.sync_due or not self.enough():
            return
        git = ff.which_real("git")
        repo = ff.gh_default_repo(git) if git else None
        if not repo:
            self.status("sync", f"PAUSED sync_repo_unknown next: run gh repo set-default in {self.paths.main}")
            return
        complete = True
        self.sync_error = None
        for n, job in self.scanned:
            if not isinstance(job, dict) or self.table.kind(job.get("state")) == "terminal":
                continue
            pr = job.get("pr")
            if not isinstance(pr, int) or isinstance(pr, bool) or pr < 1:
                continue
            if not self.enough():
                complete = False
                break
            ok, data = self.gh(["api", f"repos/{repo}/pulls/{pr}"])
            if not ok or not isinstance(data, dict):
                complete = False
                continue
            merged = data.get("merged") is True or bool(data.get("merged_at"))
            closed = data.get("state") == "closed" and not merged
            head = (data.get("head") or {}).get("sha") if isinstance(data.get("head"), dict) else None
            known = job.get("head_sha")
            foreign = isinstance(head, str) and isinstance(known, str) and head != known
            self.fresh_changes[n] = [f for f, v in (("pr_merged_by_person", merged), ("pr_closed_by_person", closed),
                                                    ("foreign_head_change", foreign)) if v]
        if complete and self.enough():
            label = quote(str(self.setting("flow.factory.label", "flow:factory")), safe=":")
            # --paginate --slurp: every page, as a list of pages.
            ok, pages = self.gh(["api", "--paginate", "--slurp",
                                 f"repos/{repo}/issues?labels={label}&state=open&per_page=100"])
            if ok and isinstance(pages, list) and all(isinstance(pg, list) for pg in pages):
                self.create_jobs([i for pg in pages for i in pg])
            else:
                complete = False
        else:
            complete = False
        if not complete and self.sync_error:
            # A sync that ran out of time says nothing; one that GitHub
            # refused says why, every pass, until it completes.
            self.status("sync", f"PAUSED sync_failed {self.sync_error} next: check gh auth status in "
                                f"{self.paths.main}")
        if complete:
            with jobs.global_lock(self.paths, timeout=self.lock_wait()):
                state = jobs.read_state(self.paths)
                state["last_sync_at"] = ff.utc_now()
                jobs.write_state(self.paths, state)

    # creation (row 1) ------------------------------------------------------
    def create_jobs(self, issues):
        for item in issues:
            if not self.enough():
                return
            if not isinstance(item, dict) or "pull_request" in item:
                continue
            n = item.get("number")
            if not isinstance(n, int) or isinstance(n, bool) or n < 1:
                continue
            try:
                self.create_one(n, item)
            except Refused as r:
                self.status("other", f"FACTORY_REFUSED={r} job=issue-{n}")

    def _archive_seq(self, n):
        adir = os.path.join(jobs.job_dir(self.paths, n), "archive")
        try:
            names = os.listdir(adir)
        except OSError:
            return 0
        seqs = [int(x[1:]) for x in names if x.startswith("j") and x[1:].isdigit()]
        return max(seqs, default=0)

    def _key_seq(self, key):
        try:
            return int(key.rsplit("-j", 1)[1])
        except (AttributeError, IndexError, ValueError):
            return 0

    def create_one(self, n, item):
        existing = jobs.read_job(self.paths, n)
        if isinstance(existing, jobs.Unreadable):
            return
        if isinstance(existing, dict) and self.table.kind(existing.get("state")) != "terminal":
            return
        seq = max(self._archive_seq(n), self._key_seq(existing.get("key")) if isinstance(existing, dict) else 0) + 1
        key = f"issue-{n}-j{seq}"
        ctx = ftable.Context(built={}, setting=jobs.setting, pass_id=self.pass_id, channel="engine", caller=self.me,
                             now=ff.utc_now())
        d = ftable.choose_creation(self.table, key, ctx)
        if isinstance(d, ftable.Blocked):
            self.status("blocked", f"BLOCKED_UNBUILT job={key} state=none event=issue_labelled fact={d.fact} "
                                   f"phase={d.phase}")
            return
        if not isinstance(d, ftable.Winner):
            return
        updated = item.get("updated_at") if _epoch(item.get("updated_at")) is not None else None
        with jobs.global_lock(self.paths, timeout=self.lock_wait()):
            with jobs.job_lock(self.paths, n, timeout=self.lock_wait()):
                again = jobs.read_job(self.paths, n)
                if isinstance(again, jobs.Unreadable):
                    return
                if isinstance(again, dict):
                    if self.table.kind(again.get("state")) != "terminal" or again.get("key") != (
                            existing or {}).get("key"):
                        return
                    self._archive(n, again)
                now = ff.utc_now()
                job = {"apiVersion": "flow.synapti.ai/v1", "kind": "FlowFactoryJob", "key": key, "issue": n,
                       "state": d.to, "attempt": 0, "stage_launches": {}, "sessions": {}, "holds_slot": False,
                       "directive": None, "cost": {"usd_total": 0, "runs": [], "stage_usd": {}, "dearest_turn_usd": 0},
                       "created_at": now, "updated_at": now, "vouch_at": updated}
                jobs.write_job(self.paths, job)
                jobs.append_event(self.paths, n, {
                    "type": "created", "job": key, "pass": self.pass_id, "row": d.row, "event": d.event,
                    "from": None, "to": d.to, "stay": False, "effects_applied": list(d.effects),
                    "effects_deferred": [], "attempt": 0, "channel": "engine", "caller": self.me, "record": job})

    def _archive(self, n, old):
        """Move the terminal job's job.json, events.jsonl and pending/ into
        J/archive/j<seq>/ before a new job of the issue is written."""
        jdir = jobs.job_dir(self.paths, n)
        dest = os.path.join(jdir, "archive", f"j{self._key_seq(old.get('key')) or 1}")
        jobs._ensure(self.paths, dest)
        for name in ("job.json", "events.jsonl", "pending"):
            src = os.path.join(jdir, name)
            if os.path.lexists(src) and not os.path.lexists(os.path.join(dest, name)):
                os.rename(src, os.path.join(dest, name))

    # environment re-run ----------------------------------------------------
    def environment(self):
        if self.env_due and self.enough():
            res = staleness.environment_recheck(self.paths.fdir, self.deadline)
            self.env_failed = not res.get("ok")
        else:
            self.env_failed = bool(self.state.get("env_failed_check"))

    # phase B ---------------------------------------------------------------
    def phase_b(self):
        self.holds, self.open_jobs = self.counts(self.scanned)
        for n, job in self.scanned:
            if isinstance(job, jobs.Unreadable):
                self.status("unreadable", f"UNREADABLE job={job.folder} next: flow-factory.sh rebuild {n}")
                continue
            if self.table.kind(job.get("state")) == "terminal":
                continue
            if not self.enough():
                self.skipped.add(n)
                continue
            try:
                with jobs.job_lock(self.paths, n, timeout=self.lock_wait()):
                    current = jobs.read_job(self.paths, n)
                    if not isinstance(current, dict):
                        continue
                    jp = JobPass(self, n, current)
                    jp.events()
                    if jp.moved:
                        self.moved.add(n)
            except Refused as r:
                self.skipped.add(n)
                if not str(r).startswith("lock_timeout"):
                    self.status("other", f"FACTORY_REFUSED={r} job=issue-{n}")

    # phase C ---------------------------------------------------------------
    def phase_c(self):
        if self.paused_until:
            self.status("usage", f"PAUSED usage_limit until={self.paused_until}")
            return
        if self.env_failed:
            return
        due_states = self.table.events.get("launch_due", {}).get("occurs_in", [])
        for n, job in self.scanned:
            if not isinstance(job, dict) or n in self.moved or n in self.skipped:
                continue
            if job.get("state") not in due_states:
                continue
            if not self.enough():
                return
            try:
                with jobs.global_lock(self.paths, timeout=self.lock_wait()):
                    all_jobs = jobs.jobs(self.paths)
                    holds, open_jobs = self.counts(all_jobs)
                    with jobs.job_lock(self.paths, n, timeout=self.lock_wait()):
                        current = jobs.read_job(self.paths, n)
                        if not isinstance(current, dict) or current.get("state") not in due_states:
                            continue
                        jp = JobPass(self, n, current, holds=holds, open_jobs=open_jobs)
                        did = jp.launch_due()
                if did:
                    self.spawn_launch(did)
            except Refused as r:
                if not str(r).startswith("lock_timeout"):
                    self.status("other", f"FACTORY_REFUSED={r} job=issue-{n}")

    def spawn_launch(self, did):
        """`flow-factory.sh launch <id>`, cwd the main checkout, in a session
        of its own with the standard streams on /dev/null; not waited for
        (it double-forks the launcher and ends)."""
        wrapper = os.path.join(ff.BIN_DIR, "flow-factory.sh")
        try:
            subprocess.Popen([wrapper, "launch", did], cwd=self.paths.main, stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
                             close_fds=True)
        except OSError as e:
            self.status("other", f"LAUNCH_NOT_STARTED directive={did} {e.strerror or e}")

    # output ----------------------------------------------------------------
    def final_word(self):
        found = jobs.jobs(self.paths)
        if not any(isinstance(j, jobs.Unreadable) or self.table.kind(j.get("state")) != "terminal"
                   for _, j in found):
            return "done"
        if fcaller.live_leases(self.paths.fdir):
            return "wait"
        for n, job in found:
            if not isinstance(job, dict) or self.table.kind(job.get("state")) == "terminal":
                continue
            jdir = jobs.job_dir(self.paths, n)
            pdir = os.path.join(jdir, "pending")
            if os.path.isdir(pdir) and any(jobs.PENDING_NAME.match(x) for x in os.listdir(pdir)):
                return "wait"
            did = job.get("directive")
            if did:
                if os.path.lexists(os.path.join(jdir, "directives", did + ".pending-report.jsonl")):
                    return "wait"
                if directive_open(self.paths, n, did):
                    return "wait"
        return "idle"

    def orphan_and_outbox_lines(self):
        for n, job in jobs.jobs(self.paths):
            if not isinstance(job, dict):
                continue
            for entry in job.get("orphan_groups") or []:
                if orphan_alive(entry):
                    self.status("orphan", f"ORPHAN_GROUP job={job['key']} pgid={entry['pgid']} stage={entry['stage']}")
            odir = os.path.join(jobs.job_dir(self.paths, n), "outbox")
            try:
                items = [x for x in os.listdir(odir) if x.endswith(".json")]
            except OSError:
                items = []
            if items:
                self.status("other", f"OUTBOX_PENDING job={job['key']} items={len(items)}")

    def output(self):
        try:
            self.lines["probe"] = staleness.status_lines(self.paths.fdir, jobs.setting) + self.lines["probe"]
        except Refused as r:
            self.status("probe", f"FACTORY_REFUSED={r}")
        self.orphan_and_outbox_lines()
        word = self.final_word()
        for g in GROUPS:
            for line in self.lines[g]:
                print(json.dumps({"status": line}, separators=(",", ":")))
        print(word)
        sys.stdout.flush()
        return 3 if self.refused else 0


_directive_path = jobs.directive_path
_lease_path = jobs.lease_path
_result_path = jobs.result_path
_report_path = jobs.report_path


def directive_open(paths, n, did):
    """Whether the job's current directive is still running or about to: it
    exists, has no result, its lease (when there is one) is not revoked, and
    no launch refusal is recorded on it. A finished directive is any other."""
    if not did:
        return False
    directive = _read_json(_directive_path(paths, n, did))
    if not isinstance(directive, dict):
        return False
    if directive.get("not_started_reason"):
        return False
    if os.path.lexists(_result_path(paths, n, did)):
        return False
    lease = _read_json(_lease_path(paths, n, did))
    if isinstance(lease, dict) and lease.get("revoked_at") is not None:
        return False
    return True


# ---------------------------------------------------------------- one job

class JobPass:
    """One job's share of the pass, under its job lock."""

    def __init__(self, p, n, job, holds=None, open_jobs=None):
        self.p = p
        self.paths = p.paths
        self.n = n
        self.job = job
        self.key = job["key"]
        self.jdir = jobs.job_dir(p.paths, n)
        self.moved = False
        self.holds = p.holds if holds is None else holds
        self.open_jobs = p.open_jobs if open_jobs is None else open_jobs
        self._clone = None
        self._clone_event = False
        self.group_gone = True
        self.unvouched = True
        self.blocked = set()

    # facts -------------------------------------------------------------
    def clone_facts(self):
        """(clone_config_changed, tree_dirty), computed once per pass (and
        again after the tree changed): the config comparison first, then the
        nested repositories, then tree_dirty only when neither found one."""
        if self._clone is not None:
            return self._clone
        wt = self.job.get("worktree")
        if not isinstance(wt, str) or not os.path.isdir(wt):
            self._clone = (False, False)
            return self._clone
        copy_dir = os.path.join(self.jdir, "clone-config")
        found = None
        try:
            c = fgit.config_changed(wt, copy_dir)
            if c is not None:
                found = ("config", c[0], c[1])
            else:
                nested = fgit.nested_repositories(self.paths.fdir, wt)
                if nested:
                    found = ("nested", nested[0])
        except fgit.CloneConfigChanged as e:
            found = ("config", e.file, e.key)
        except fgit.GitTimedOut as e:
            # Out of the pass's time: not an answer either way, and no reason
            # to park; the event waits for the next pass.
            self.p.status("other", f"GIT_TIMED_OUT job={self.key} {e}")
            raise FactFailed(str(e)) from e
        except fgit.GitFailed as e:
            # Never read a failed scan as "no nested repository": park.
            found = ("failed", str(e))
        dirty = False
        if found is None:
            try:
                dirty = fgit.tree_dirty(self.paths.fdir, wt, copy_dir, self.n, self.job.get("goal_id"))
            except fgit.CloneConfigChanged as e:
                found = ("config", e.file, e.key)
            except fgit.GitFailed as e:
                self.p.status("other", f"GIT_FAILED job={self.key} {e}")
                raise FactFailed(str(e)) from e
        if found is not None:
            self.clone_changed_line(wt, found)
        self._clone = (found is not None, dirty)
        return self._clone

    def clone_changed_line(self, wt, found):
        if found[0] == "config":
            _, f, k = found
            self.p.status("clone", f"CLONE_CONFIG_CHANGED job={self.key} file={f} key={k} next: restore "
                                   f"{wt}/.git/{f} from {self.jdir}/clone-config/{f}")
            ev = {"file": f, "key": k}
        elif found[0] == "nested":
            self.p.status("clone", f"NESTED_REPOSITORY job={self.key} path={found[1]}")
            ev = {"nested_repository": found[1]}
        else:
            msg = found[1]
            if msg.startswith("nested_repository_scan_limit"):
                self.p.status("clone", f"NESTED_REPOSITORY_SCAN_LIMIT job={self.key} dir={msg.split(': ', 1)[-1]}")
            else:
                self.p.status("clone", f"GIT_FAILED job={self.key} {msg}")
            ev = {"git_failed": msg}
        if not self._clone_event:
            self._clone_event = True
            jobs.append_event(self.paths, self.n, dict({"type": "clone_config_changed", "job": self.key,
                                                        "pass": self.p.pass_id}, **ev))

    def built(self):
        job = self.job
        concurrency = self.p.num("concurrency", 1, 1)
        max_open = self.p.num("maxOpenJobs", 5, 1)
        changes = job.get("pending_changes") or []
        return {
            "probes_stale": lambda: bool(self.p.platform()["stale"]),
            "clone_config_changed": lambda: self.clone_facts()[0],
            "tree_dirty": lambda: self.clone_facts()[1],
            "slot_free": lambda: self.holds < concurrency and self.open_jobs < max_open,
            "slot_available": lambda: job.get("holds_slot") is True or self.holds < concurrency,
            "orphan_group_alive": lambda: any(orphan_alive(e) for e in job.get("orphan_groups") or []),
            "group_gone": lambda: bool(self.group_gone),
            "unvouched_session_action": lambda: bool(self.unvouched),
            "pr_exists": lambda: isinstance(job.get("pr"), int) and not isinstance(job.get("pr"), bool),
            "pr_merged_by_person": lambda: "pr_merged_by_person" in changes,
            "pr_closed_by_person": lambda: "pr_closed_by_person" in changes,
            "foreign_head_change": lambda: "foreign_head_change" in changes,
        }

    def ctx(self, channel, caller):
        return ftable.Context(built=self.built(), setting=jobs.setting, pass_id=self.p.pass_id, channel=channel,
                              caller=caller, now=ff.utc_now())

    # deciding and applying -----------------------------------------------
    def decide(self, event, channel="engine", caller=None):
        """Choose and apply one event. Returns "applied", "nomove", "blocked",
        "refused" or "failed" (a fact or an effect could not be run; nothing
        changed)."""
        state = self.job["state"]
        ctx = self.ctx(channel, caller)
        try:
            d = ftable.choose(self.p.table, self.job, event, ctx)
        except FactFailed:
            return "failed"
        if isinstance(d, ftable.Blocked):
            if (state, event) not in self.blocked:
                self.blocked.add((state, event))
                jobs.append_event(self.paths, self.n, {"type": "blocked_unbuilt", "job": self.key,
                                                       "pass": self.p.pass_id, "state": state, "event": event,
                                                       "fact": d.fact, "phase": d.phase})
            self.p.status("blocked", f"BLOCKED_UNBUILT job={self.key} state={state} event={event} fact={d.fact} "
                                     f"phase={d.phase}")
            return "blocked"
        if isinstance(d, ftable.Refusal):
            self.refuse(d.line)
            return "refused"
        if isinstance(d, ftable.NoMove):
            return "nomove"
        return self.apply(d, ctx)

    def refuse(self, line):
        jobs.append_event(self.paths, self.n, {"type": "refused", "job": self.key, "pass": self.p.pass_id,
                                               "line": line})
        self.p.status("refused", line)
        self.p.refused = True

    def apply(self, d, ctx, launch=None):
        try:
            new, line, to_run, _ = ftable.apply(self.p.table, self.job, d, ctx)
        except ftable.TransitionRefused as e:
            self.refuse(e.line)
            return "refused"
        handlers = [h for h, _ in to_run]
        leaving = new["state"] != self.job["state"]
        try:
            if "kill" in handlers or leaving:
                self.kill_current(new)
            for h, _ in to_run:
                if h == "snapshot":
                    self.snapshot(new, d.row)
                elif h == "reset":
                    self.reset()
        except (fgit.GitFailed, fgit.CloneConfigChanged) as e:
            self.p.status("other", f"EFFECT_FAILED job={self.key} row={d.row} {e}")
            return "failed"
        if launch is not None:
            launch(new)
        if "terminal" in handlers:
            self.terminal(new)
        if leaving:
            new["lease_grace"] = None
        new["updated_at"] = ff.utc_now()
        jobs.write_job(self.paths, new)
        jobs.append_event(self.paths, self.n, line)
        if self.job.get("holds_slot") is True and new.get("holds_slot") is not True:
            jobs.append_event(self.paths, self.n, {"type": "slot", "job": self.key, "pass": self.p.pass_id,
                                                   "freed": True})
        if "status_line" in handlers:
            self.row_status_lines(new, d.row)
        self.job = new
        if leaving:
            self.moved = True
        return "applied"

    def row_status_lines(self, job, row):
        if row == "43g":
            for entry in job.get("orphan_groups") or []:
                if orphan_alive(entry):
                    self.p.status("orphan", f"ORPHAN_GROUP job={self.key} pgid={entry['pgid']} stage={entry['stage']}")

    # effects -------------------------------------------------------------
    def snapshot(self, new, row):
        wt = self.job.get("worktree")
        if not isinstance(wt, str) or not os.path.isdir(wt):
            return
        ref = fgit.snapshot(self.paths.fdir, wt, os.path.join(self.jdir, "clone-config"), self.n, f"row {row}")
        k = int(ref.rsplit("-", 1)[1])
        entry = {"ref": ref, "k": k, "reason": f"row {row}", "at": ff.utc_now()}
        new["snapshots"] = list(new.get("snapshots") or []) + [entry]
        jobs.append_event(self.paths, self.n, dict({"type": "snapshot", "job": self.key, "pass": self.p.pass_id},
                                                   **entry, snapshots=new["snapshots"]))
        self._clone = None

    def reset(self):
        wt = self.job.get("worktree")
        if not isinstance(wt, str) or not os.path.isdir(wt):
            return
        fgit.reset_and_clean(self.paths.fdir, wt, os.path.join(self.jdir, "clone-config"))
        self._clone = None

    def terminal(self, new):
        try:
            fgit.copy_refs_to_main(self.paths.fdir, self.job.get("worktree"), self.paths.main, self.n)
        except (fgit.GitFailed, fgit.CloneConfigChanged) as e:
            self.p.status("other", f"TERMINAL_CLEANUP_FAILED job={self.key} {e}")

    def kill_current(self, new):
        """Revoke the current directive's live lease, SIGKILL its launcher and
        kill claude's group; charge the run the launcher can no longer
        charge; record a group not confirmed gone in orphan_groups. Nothing
        for a lease already revoked (liveness did it) or no lease."""
        did = self.job.get("directive")
        if not did:
            return
        lease = _read_json(_lease_path(self.paths, self.n, did))
        if not isinstance(lease, dict) or lease.get("revoked_at") is not None:
            return
        gone = self.revoke_and_kill(did, lease, new)
        self.charge_lost_run(did, lease, new)
        self.group_gone = gone
        self._clone = None

    def revoke_and_kill(self, did, lease, new):
        lease["revoked_at"] = ff.utc_now()
        _write_json(_lease_path(self.paths, self.n, did), lease, "lease")
        lp, ls = lease.get("launcher_pid"), lease.get("launcher_start")
        if isinstance(lp, int) and not isinstance(lp, bool) and lp > 1 and fcaller.lstart(lp) == ls:
            try:
                os.kill(lp, signal.SIGKILL)
            except OSError:
                pass
        pgid, cstart = lease.get("child_pgid"), lease.get("child_start")
        gone = kill_group(pgid, cstart, min(2.0, max(0.0, self.p.left())))
        if not gone and isinstance(pgid, int) and not isinstance(cstart, str):
            # No start was recorded: the group is recorded with its leader's
            # start now, so orphan_alive follows it from here on.
            cstart = fcaller.lstart(pgid)
        if not gone and isinstance(pgid, int) and isinstance(cstart, str):
            directive = _read_json(_directive_path(self.paths, self.n, did)) or {}
            entry = {"pgid": pgid, "start": cstart, "stage": directive.get("stage") or self.job["state"],
                     "recorded_at": ff.utc_now()}
            new["orphan_groups"] = list(new.get("orphan_groups") or []) + [entry]
            jobs.append_event(self.paths, self.n, dict({"type": "orphan_group", "job": self.key,
                                                        "pass": self.p.pass_id, "directive": did},
                                                       **entry, orphan_groups=new["orphan_groups"]))
        return gone

    def charged(self, job, did):
        return any(isinstance(r, dict) and r.get("directive") == did for r in (job.get("cost") or {}).get("runs") or [])

    def add_charge(self, new, did, stage, sid, charge, dearest):
        """Add one run's charge to new (cost.usd_total, stage_usd, runs,
        dearest_turn_usd, sessions) and append the charge event, as the
        launcher's own report does."""
        cost = new.setdefault("cost", {"usd_total": 0, "runs": [], "stage_usd": {}, "dearest_turn_usd": 0})
        charged = jobs.usd(charge["charged_usd"])
        cost["usd_total"] = jobs.usd(cost.get("usd_total", 0)) + charged
        cost.setdefault("stage_usd", {})
        cost["stage_usd"][stage] = jobs.usd(cost["stage_usd"].get(stage, 0)) + charged
        cost.setdefault("runs", []).append({"directive": did, "session_id": sid, "charged_usd": charged,
                                            "basis": charge["basis"],
                                            "total_cost_usd": jobs.usd(charge.get("total_cost_usd")),
                                            "since_last_usd": jobs.usd(charge.get("since_last_usd"))})
        if dearest is not None:
            cost["dearest_turn_usd"] = max(jobs.usd(cost.get("dearest_turn_usd", 0)), dearest)
        if sid and charge.get("total_cost_usd") is not None:
            totals = dict(new.get("last_session_total") or {})
            totals[sid] = jobs.usd(charge["total_cost_usd"])
            new["last_session_total"] = totals
        if sid and stage in self.p.table.states:
            new.setdefault("sessions", {})[stage] = sid
        jobs.append_event(self.paths, self.n, {
            "type": "charge", "job": self.key, "pass": self.p.pass_id, "directive": did, "stage": stage,
            "session_id": sid, "charged_usd": charged, "basis": charge["basis"],
            "total_cost_usd": jobs.usd(charge.get("total_cost_usd")),
            "since_last_usd": jobs.usd(charge.get("since_last_usd")),
            "dearest_turn_usd": cost.get("dearest_turn_usd", 0)})

    def stream_session(self, did, directive):
        stream = os.path.join(self.jdir, "results", did + ".stream.jsonl")
        init = ff.init_event(ff.stream_events(stream)) or {}
        sid = init.get("session_id") if isinstance(init.get("session_id"), str) else None
        if directive.get("kind") != "worker":
            return None
        return sid or directive.get("session_id")

    def charge_lost_run(self, did, lease, new):
        """Charge a run whose launcher died or was killed (limit plus the
        allowance, basis limit_plus_turn), once: only when no result file
        exists, no pending-report line from this lease's launcher holds the
        launcher's own report, no charge for the directive is recorded, and
        claude was started (the lease names a child)."""
        if self.charged(new, did) or os.path.lexists(_result_path(self.paths, self.n, did)):
            return
        if lease.get("child_pid") is None:
            return
        for line in self.report_lines(did):
            if isinstance(line, dict) and line.get("caller_pid") == lease.get("launcher_pid") \
                    and line.get("caller_start") == lease.get("launcher_start"):
                return
        directive = _read_json(_directive_path(self.paths, self.n, did)) or {}
        limit = directive.get("max_budget_usd")
        if limit is None:
            return
        charge = jobs.charge_run(None, directive.get("start_mode") or "fresh", None, limit,
                                 jobs.turn_allowance(new))
        stage = directive.get("stage") or self.job["state"]
        self.add_charge(new, did, stage, self.stream_session(did, directive), charge, None)

    # the events ----------------------------------------------------------
    def events(self):
        p = self.p
        # The sync's new changes join pending_changes first.
        fresh = p.fresh_changes.get(self.n) or []
        changes = list(self.job.get("pending_changes") or [])
        added = [f for f in fresh if f not in changes]
        if added:
            self.job = dict(self.job, pending_changes=changes + added, updated_at=ff.utc_now())
            jobs.write_job(self.paths, self.job)
            jobs.append_event(self.paths, self.n, {"type": "pending_changes", "job": self.key, "pass": self.p.pass_id,
                                                   "added": added, "pending_changes": changes + added})
        pending = self.load_pending()
        order = self.p.table.data["event_order"]
        github_raised = False
        pf = p.table.pass_first
        if pf.get("event") == "github_change" and all(
                (f in (self.job.get("pending_changes") or [])) == v for f, v in pf.get("when", {}).items()):
            github_raised = True
            self.run_engine_event("github_change")
        for event in order:
            if self.moved:
                return
            if event == "github_change":
                if not github_raised and self.job.get("pending_changes"):
                    github_raised = True
                    self.run_engine_event("github_change")
            elif event == "lease_expired":
                self.apply_reports()
                if not self.moved:
                    self.liveness()
            elif event == "sync_tick":
                if self.job["state"] in p.table.events.get("sync_tick", {}).get("occurs_in", []):
                    self.run_engine_event("sync_tick")
            elif event == "launch_due":
                continue
            for name, rec in pending.get(event, []):
                if self.moved:
                    return
                self.apply_pending(event, name, rec)

    def run_engine_event(self, event):
        self.unvouched = True
        self.decide(event, "engine", None)

    def load_pending(self):
        """{event: [(name, record)]} of J/pending, seq order; a file that
        cannot be read, or names no event of the table, is refused and
        removed."""
        out = {}
        for name, rec in jobs.pending_events(self.paths, self.n):
            event = name.split("-", 1)[1][:-len(".json")]
            if isinstance(rec, jobs.Unreadable) or event not in self.p.table.events or rec.get("event") != event:
                self.refuse(f"EVENT_REFUSED={event} state={self.job['state']}")
                jobs.drop_pending(self.paths, self.n, name)
                continue
            out.setdefault(event, []).append((name, rec))
        return out

    def report_refused(self, did, reason, source):
        jobs.append_event(self.paths, self.n, {"type": "report_refused", "job": self.key, "pass": self.p.pass_id,
                                               "directive": did, "reason": reason, "source": source})

    def directive_check(self, did):
        """None when a result for did may be applied: did is the job's
        current directive and its lease, when there is one, is not revoked.
        Else the reason it is refused."""
        if not isinstance(did, str) or did != self.job.get("directive"):
            return "not_current"
        lease = _read_json(_lease_path(self.paths, self.n, did))
        if isinstance(lease, dict) and lease.get("revoked_at") is not None:
            return "lease_revoked"
        return None

    def apply_pending(self, event, name, rec):
        args = rec.get("args") or {}
        is_result = event in STAGE_EVENTS or event.startswith("judge_")
        if is_result:
            did = args.get("directive")
            why = self.directive_check(did)
            if why is None and not os.path.lexists(_result_path(self.paths, self.n, did)):
                why = "no_result"
            if why is not None:
                self.report_refused(did, why, name)
                jobs.drop_pending(self.paths, self.n, name)
                return
            self.charge_from_result(did)
        facts = rec.get("facts") or {}
        v = facts.get("unvouched_session_action")
        self.unvouched = v if isinstance(v, bool) else True
        outcome = self.decide(event, rec.get("channel"), rec.get("caller"))
        if outcome in ("applied", "nomove", "refused"):
            jobs.drop_pending(self.paths, self.n, name)

    def charge_from_result(self, did):
        """A result the launcher wrote without charging the job (its bare
        result after a failure): charge it now from the result's own charge,
        once."""
        if self.charged(self.job, did):
            return
        result = _read_json(_result_path(self.paths, self.n, did))
        if not isinstance(result, dict) or result.get("charged_usd") is None or not result.get("charge_basis"):
            return
        directive = _read_json(_directive_path(self.paths, self.n, did)) or {}
        stage = directive.get("stage") or self.job["state"]
        sid = result.get("session_id") if isinstance(result.get("session_id"), str) else None
        new = dict(self.job)
        new["cost"] = json.loads(json.dumps(jobs._jsonable(self.job.get("cost") or {})))
        self.add_charge(new, did, stage, sid, {"charged_usd": result["charged_usd"], "basis": result["charge_basis"],
                                               "total_cost_usd": result.get("total_cost_usd"),
                                               "since_last_usd": result.get("since_last_usd")}, None)
        new["updated_at"] = ff.utc_now()
        jobs.write_job(self.paths, new)
        self.job = new

    # pending-report lines --------------------------------------------------
    def report_lines(self, did):
        path = _report_path(self.paths, self.n, did)
        if not os.path.lexists(path):
            return []
        try:
            text = _read_with_no_follow(path)
        except (JournalAtomicError, UnicodeDecodeError):
            return [None]
        out = []
        for raw in text.splitlines():
            if not raw.strip():
                continue
            try:
                out.append(json.loads(raw))
            except ValueError:
                out.append(None)
        return out

    def apply_reports(self):
        """The shell's pending-report lines of every directive of the job. A
        line is applied only when it is for the current directive, its lease
        is not revoked, and caller_pid and caller_start are the lease's
        launcher_pid and launcher_start; every other line is recorded as
        report_refused. The file is removed once its lines are handled."""
        ddir = os.path.join(self.jdir, "directives")
        try:
            names = sorted(x for x in os.listdir(ddir) if x.endswith(".pending-report.jsonl"))
        except OSError:
            return
        for fname in names:
            if self.moved:
                return
            did = fname[:-len(".pending-report.jsonl")]
            path = os.path.join(ddir, fname)
            if os.path.islink(path) or not os.path.isfile(path):
                self.report_refused(did, "not_a_regular_file", fname)
                os.unlink(path)
                continue
            lease = _read_json(_lease_path(self.paths, self.n, did))
            keep = False
            for line in self.report_lines(did):
                why = self.directive_check(did)
                if why is None and not isinstance(lease, dict):
                    why = "no_lease"
                if why is None and not (isinstance(line, dict) and isinstance(line.get("report"), dict)
                                        and line.get("directive") == did):
                    why = "malformed"
                if why is None and (line.get("caller_pid") != lease.get("launcher_pid")
                                    or line.get("caller_start") != lease.get("launcher_start")):
                    why = "not_launcher"
                if why is None and os.path.lexists(_result_path(self.paths, self.n, did)):
                    why = "result_exists"
                if why is not None:
                    self.report_refused(did, why, "pending-report")
                    continue
                if self.apply_report(did, line["report"], line) == "keep":
                    keep = True
            if not keep:
                try:
                    os.unlink(path)
                except FileNotFoundError:
                    pass

    def apply_report(self, did, report, line):
        """In the engine, what the launcher's in-process report does: the
        result file, the charge from the run's own stream, the charge and
        result_applied events, then the stage event. A stage event that cannot
        be decided now (a fact failed, or one is unbuilt) is stored as the
        launcher's pending event, as the launcher's own report stores it, so
        apply_pending keeps it until it can be; dropped with the line, the
        next pass would launch the stage afresh."""
        directive = _read_json(_directive_path(self.paths, self.n, did)) or {}
        stage = directive.get("stage") or self.job["state"]
        mode = directive.get("start_mode") or "fresh"
        stream = os.path.join(self.jdir, "results", did + ".stream.jsonl")
        result_event = ff.result_event(stream)
        resumed = (self.job.get("sessions") or {}).get(stage) if mode == "resume" else None
        previous = (self.job.get("last_session_total") or {}).get(resumed) if resumed else None
        limit = directive.get("max_budget_usd")
        if limit is None:
            self.report_refused(did, "unclaimed", "pending-report")
            return "drop"
        new = json.loads(json.dumps(jobs._jsonable(self.job)))
        charge = jobs.charge_run(result_event, mode, previous, limit, jobs.turn_allowance(new))
        record = dict(report)
        record["directive"] = did
        record["charged_usd"] = jobs.usd(charge["charged_usd"])
        record["charge_basis"] = charge["basis"]
        record["total_cost_usd"] = jobs.usd(charge["total_cost_usd"])
        record["since_last_usd"] = jobs.usd(charge["since_last_usd"])
        try:
            _write_json(_result_path(self.paths, self.n, did), record, "result")
        except Refused as r:
            self.report_refused(did, f"result_invalid {r}", "pending-report")
            return "drop"
        sid = record.get("session_id") if isinstance(record.get("session_id"), str) else None
        if not self.charged(new, did):
            self.add_charge(new, did, stage, sid, charge, jobs.dearest_turn(stream))
        new["updated_at"] = ff.utc_now()
        jobs.write_job(self.paths, new)
        self.job = new
        jobs.append_event(self.paths, self.n, {"type": "result_applied", "job": self.key, "pass": self.p.pass_id,
                                               "directive": did, "outcome": record.get("outcome"),
                                               "event": record.get("event")})
        event = record.get("event")
        if event in STAGE_EVENTS:
            self.unvouched = True
            if self.decide(event, "launcher", None) in ("failed", "blocked"):
                caller = {"pid": line["caller_pid"], "start": line["caller_start"], "ancestry": []}
                jobs.store_pending(self.paths, self.n, event, {"directive": did, "outcome": record.get("outcome")},
                                   "launcher", caller, {})
        elif record.get("outcome") == "usage_limit":
            self.pause_usage()
        return "drop"

    def pause_usage(self):
        # The global lock cannot be taken under a job lock: cmd_next writes
        # the pause after Phase B (3600 s, amendments A.8).
        self.p.pending_pause = _utc_at(time.time() + 3600)

    # liveness --------------------------------------------------------------
    def liveness(self):
        """Lease expiry of the current directive (T11 Liveness): a lease
        whose heartbeat is older than leaseSeconds is revoked, its launcher
        and claude's group killed, and its run charged, unless the launcher
        is alive and running, which first gets one heartbeat interval of
        grace (A+11). A claimed directive whose launcher never wrote a lease
        within leaseSeconds expires the same way, with nothing to kill."""
        did = self.job.get("directive")
        if not did or not directive_open(self.paths, self.n, did):
            if self.job.get("lease_grace"):
                self.write_grace(None)
            return
        directive = _read_json(_directive_path(self.paths, self.n, did)) or {}
        lease = _read_json(_lease_path(self.paths, self.n, did))
        lease_seconds = self.p.num("leaseSeconds", 180, 1)
        now = time.time()
        new = json.loads(json.dumps(jobs._jsonable(self.job)))
        if not isinstance(lease, dict):
            since = _epoch(directive.get("started_at")) or _epoch(directive.get("created_at"))
            if since is None or now - since < lease_seconds:
                return
            self.group_gone = True
        else:
            beat = _epoch(lease.get("heartbeat_at"))
            if beat is not None and now - beat < lease_seconds:
                if self.job.get("lease_grace"):
                    self.write_grace(None)
                return
            alive, running = launcher_running(lease.get("launcher_pid"), lease.get("launcher_start"))
            if alive and running:
                grace = _epoch(self.job.get("lease_grace"))
                if grace is None:
                    self.write_grace(_utc_at(now + self.p.num("heartbeatSeconds", 60, 1)))
                    return
                if now < grace:
                    return
            self.group_gone = self.revoke_and_kill(did, lease, new)
            self.charge_lost_run(did, lease, new)
        new["lease_grace"] = None
        self.job = new
        self._clone = None
        outcome = self.decide("lease_expired", "engine", None)
        if outcome != "applied":
            # The revocation, the kill and the charge stand either way.
            self.job["updated_at"] = ff.utc_now()
            jobs.write_job(self.paths, self.job)

    def write_grace(self, value):
        self.job = dict(self.job, lease_grace=value, updated_at=ff.utc_now())
        jobs.write_job(self.paths, self.job)

    # phase C ---------------------------------------------------------------
    def launch_due(self):
        """launch_due for this job, under the global and the job lock. Returns
        the directive id to start once the locks are released, or None."""
        did = self.job.get("directive")
        if did and directive_open(self.paths, self.n, did):
            return None
        if self.unapplied_results():
            return None
        state = self.job["state"]
        kind = self.p.table.states.get(state, {}).get("run_by")
        seam = ftable.current_seam()
        body = None
        if kind != "worker":
            body = (seam or {}).get("bodies", {}).get(f"{kind}:{state}")
        self.unvouched = True
        ctx = self.ctx("engine", None)
        try:
            d = ftable.choose(self.p.table, self.job, "launch_due", ctx)
        except FactFailed:
            return None
        if not isinstance(d, ftable.Winner):
            self.record_decision(d, state)
            return None
        launching = any(ftable.EFFECTS.get(e) == ("handled", "launch") for e in d.effects)
        if not launching:
            self.apply(d, ctx)
            return None
        if kind == "worker":
            line = self.worker_precheck(state)
            if line:
                return None
        elif body is None:
            sys.stderr.write(f"SEAM_MISSING=bodies:{kind}:{state} state={state} event=launch_due\n")
            return None
        made = {}

        def launch(new):
            made["id"] = self.create_directive(new, state, kind, body)

        if self.apply(d, ctx, launch=launch) != "applied":
            return None
        return made.get("id") if body is None else None

    def record_decision(self, d, state):
        """A launch_due that did not win a row: Blocked is recorded (one
        blocked_unbuilt event, the job's only launch_due of the pass) and
        printed; a refusal is recorded and printed; NoMove is nothing."""
        if isinstance(d, ftable.Blocked):
            jobs.append_event(self.paths, self.n, {"type": "blocked_unbuilt", "job": self.key, "pass": self.p.pass_id,
                                                   "state": state, "event": "launch_due", "fact": d.fact,
                                                   "phase": d.phase})
            self.p.status("blocked", f"BLOCKED_UNBUILT job={self.key} state={state} event=launch_due fact={d.fact} "
                                     f"phase={d.phase}")
        elif isinstance(d, ftable.Refusal):
            self.refuse(d.line)

    def unapplied_results(self):
        """Whether a stage or judge result of the job waits in pending/."""
        pdir = os.path.join(self.jdir, "pending")
        try:
            names = os.listdir(pdir)
        except OSError:
            return False
        for x in names:
            if not jobs.PENDING_NAME.match(x):
                continue
            event = x.split("-", 1)[1][:-len(".json")]
            if event in STAGE_EVENTS or event.startswith("judge_"):
                return True
        return False

    def worker_precheck(self, stage):
        """A status line when a worker launch would only be refused: the stage
        budget is unset (missing or not positive) or has no room for another
        run, or the prompt template is missing. None when the launch may go
        ahead."""
        budget = self.p.setting(f"flow.factory.worker.stages.{stage}.maxBudgetUsd")
        line = jobs.worker_budget_paused(self.key, stage, budget, self.job)
        if line:
            self.p.status("budget", line)
            return line
        template = "resume" if self.start_mode(stage) == "resume" else stage
        if not os.path.isfile(os.path.join(ff.PLUGIN_ROOT, "templates", "factory", f"{template}.prompt.md")):
            line = (f"PAUSED prompt_missing job={self.key} stage={stage} next: add templates/factory/"
                    f"{template}.prompt.md to the plugin")
            self.p.status("other", line)
            return line
        return None

    def start_mode(self, stage, job=None):
        job = job or self.job
        cause = (job.get("relaunch") or {}).get("cause_row") or "first"
        kind = self.p.table.states.get(stage, {}).get("run_by")
        if cause in RESUME_ROWS and kind == "worker" and (job.get("sessions") or {}).get(stage):
            try:
                if staleness.resume_allowed(self.p.record()):
                    return "resume"
            except Refused:
                return "fresh"
        return "fresh"

    def create_directive(self, new, stage, kind, body):
        """Write the stage's next directive and make it the job's current one
        (on new, which the caller writes). With a seam body (the test entry
        point only), the body's result and event are written at once and no
        process starts."""
        mode = self.start_mode(stage, new)
        relaunch = new.get("relaunch") or {}
        cause = relaunch.get("cause_row") or "first"
        k = int((new.get("stage_launches") or {}).get(stage, 0)) + 1
        ddir = os.path.join(self.jdir, "directives")
        jobs._ensure(self.paths, ddir)
        while os.path.lexists(os.path.join(ddir, f"{self.key}-{stage}-{k}.json")):
            k += 1
        did = f"{self.key}-{stage}-{k}"
        worker = kind == "worker"
        snapshot_ref = None
        if worker and mode == "fresh" and cause in SNAPSHOT_ROWS and new.get("snapshots"):
            snapshot_ref = new["snapshots"][-1]["ref"]
        tools = self.p.setting(f"flow.factory.worker.stages.{stage}.allowedTools") if worker else None
        timeout = self.p.setting(f"flow.factory.worker.stages.{stage}.timeoutSeconds") if worker else None
        directive = {
            "id": did, "job": self.key, "issue": self.n, "kind": kind, "stage": stage,
            "start_mode": mode if worker else "fresh", "cause_row": cause, "created_in_pass": self.p.pass_id,
            "created_at": ff.utc_now(),
            "session_id": ((new.get("sessions") or {}).get(stage) if mode == "resume" else str(uuid.uuid4()))
            if worker else None,
            "prompt_template": (f"templates/factory/{'resume' if mode == 'resume' else stage}.prompt.md"
                                if worker else None),
            "model": None,
            "timeout_seconds": int(_number(timeout, DEFAULT_TIMEOUT_SECONDS, 1)) if worker else None,
            "allowed_tools": ([t for t in tools if isinstance(t, str)] if isinstance(tools, list) else [])
            if worker else None,
            "max_budget_usd": None, "snapshot_ref": snapshot_ref, "started_at": None, "not_started_reason": None}
        if body is not None:
            directive["started_at"] = ff.utc_now()
        _write_json(os.path.join(ddir, did + ".json"), directive, None)
        new.setdefault("stage_launches", {})[stage] = k
        new["directive"] = did
        new["relaunch"] = None
        new["lease_grace"] = None
        if new.get("holds_slot") is not True:
            new["holds_slot"] = True
            jobs.append_event(self.paths, self.n, {"type": "slot", "job": self.key, "pass": self.p.pass_id,
                                                   "taken": True})
        if body is not None:
            self.inline_body(did, body)
        return did

    def inline_body(self, did, body):
        """Under the test entry point's seam only: the outcome of a judge or
        engine directive whose body a later phase builds (plan 2.11 kind 4)."""
        outcome, result_event, pending_event = BODY_OUTCOMES.get(body, (None, None, None))
        if outcome is None:
            raise Refused(f"seam_body_unknown {body}")
        rdir = os.path.join(self.jdir, "results")
        jobs._ensure(self.paths, rdir)
        _write_json(os.path.join(rdir, did + ".json"), {
            "directive": did, "outcome": outcome, "written_at": ff.utc_now(), "event": result_event,
            "session_id": None, "num_turns": None, "api_error_status": None, "is_error": None,
            "permission_denials": None, "terminal_reason": None, "charged_usd": None, "charge_basis": None,
            "total_cost_usd": None, "since_last_usd": None}, "result")
        jobs.store_pending(self.paths, self.n, pending_event, {"directive": did, "outcome": outcome}, "launcher",
                           self.p.me, {})


# ---------------------------------------------------------------- entry

def _usage(message):
    sys.stderr.write(f"{PROG}: {message}\n")
    return 2


def cmd_next(argv):
    executor = None
    args = list(argv)
    while args:
        a = args.pop(0)
        if a == "--executor":
            if not args:
                return _usage("--executor needs interactive or headless")
            executor = args.pop(0)
        elif a.startswith("--executor="):
            executor = a.split("=", 1)[1]
        else:
            return _usage(f"unknown argument {a}")
    if executor is None:
        return _usage("--executor interactive|headless is required")
    if executor not in ("interactive", "headless"):
        return _usage(f"--executor must be interactive or headless, not {executor}")
    started = time.time()
    paths = jobs.resolve()
    p = Pass(paths, executor, started)
    # Every engine git command of this pass ends by the pass's deadline.
    fgit.set_deadline(p.deadline)
    p.phase_a()
    # The platform check runs once per pass; an unreadable record refuses
    # here, before any job is touched.
    p.platform()
    p.sync()
    p.environment()
    p.phase_b()
    if p.pending_pause:
        with jobs.global_lock(paths, timeout=p.lock_wait()):
            state = jobs.read_state(paths)
            old = state.get("paused_until")
            if not (isinstance(old, str) and old > p.pending_pause):
                state["paused_until"] = p.pending_pause
            jobs.write_state(paths, state)
        p.paused_until = p.pending_pause
    p.phase_c()
    return p.output()
