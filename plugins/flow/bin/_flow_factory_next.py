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

import hashlib
import json
import re
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
import _flow_factory_issue as fissue
import _flow_factory_text as ftext
import _flow_factory_tiers as ftiers
import _flow_factory_github as fgithub
import _flow_factory_intake as fintake
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
# The 1b caller handlers next runs in JobPass.apply (plan B13 table, B14 step 7).
CALLER_1B = ("pr_close", "answer", "notice", "refuse_note", "issue_md", "intake_record", "hold_intent", "write")
# Rows whose handlers change a spec-input source outside the sync, so
# J/sync/issue-set.json is deleted with them (plan 2.2, B14 step 7).
ANSWER_FILE_ROWS = ("8a", "9a", "44v", "44u", "44w", "44x", "44q", "44")
# The parked states whose entry and exit move a label (B14 step 8).
LABELLED_PARKS = {"needs_info": "needsInfo", "needs_human": "needsHuman"}
LABEL_DEFAULTS = {"inProgress": "flow:in-progress", "needsInfo": "flow:needs-info", "needsHuman": "flow:needs-human",
                  "ready": "flow:ready", "specReview": "flow:spec-review", "priorityHigh": "flow:priority-high"}
NOTICE_KEY = ["issueUpdate"]
ASSIGN_KEY = ["issueAssign", "issueUpdate"]

# The status line groups, in the order `next` prints them (plan 2.6, T11
# Output): the probe lines first, then the rest.
GROUPS = ("probe", "sync", "unreadable", "usage", "budget", "orphan", "blocked", "clone", "refused", "other")


class FactFailed(Exception):
    """A built fact could not be computed this pass (a git command in the
    clone failed); the event is left for the next pass."""


class IntentUnknown(Refused):
    """The pending intent's outbox item is not found: J/outbox is a link, or
    the item does not read or validate (plan 2.3, INTENT_UNKNOWN=<id>)."""

    def __init__(self, iid):
        self.line = f"INTENT_UNKNOWN={iid}"
        super().__init__(f"intent_unknown {iid}")


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
    None when there is no such file or it cannot be read or parsed, and when
    the folder that holds it is a symbolic link or not a folder (a linked
    J/directives, J/sync or J/results is never read through: journal wave 4,
    linked job folders)."""
    if not os.path.lexists(path) or _linked_dir(os.path.dirname(path)):
        return None
    try:
        return json.loads(_read_with_no_follow(path))
    except (JournalAtomicError, UnicodeDecodeError, ValueError):
        return None


def _linked_dir(path):
    """Whether the job folder entry at path is a symbolic link, or something
    other than a folder: such a J/sync, J/results or J/archive (or an entry
    of J/archive) is never read through or written through (journal wave 4,
    linked job folders)."""
    return os.path.islink(path) or (os.path.lexists(path) and not os.path.isdir(path))


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
    start (the launcher's ps failed), a live group whose leader still runs
    cannot be told apart from a new one: it is not signalled and not taken as
    gone. A live group with no leader can only be the recorded one (its
    number is not reused while a member lives), so it is signalled."""
    if not isinstance(pgid, int) or isinstance(pgid, bool) or pgid <= 1:
        return True
    if not _group_exists(pgid):
        return True
    leader = fcaller.lstart(pgid)
    if not isinstance(start, str) and leader is not None:
        return False
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


def label_name(name):
    """flow.factory.labels.<name>, read user-only, else its default."""
    v = jobs.setting(f"flow.factory.labels.{name}", LABEL_DEFAULTS[name])
    return v if isinstance(v, str) and v else LABEL_DEFAULTS[name]


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
        # The 1b sync's reads, kept in memory for this pass only (plan 3.2):
        # {n: {"snapshot": B4's snapshot}} for each job whose reads all
        # answered. A job with no entry has no issue facts this pass.
        self.issue_sync = {}
        self.perms = None
        self.default_branch = None
        # Per-pass values read the first time they are needed (plan 3.2
        # item 1): False until read, then the value or None.
        self._login = False
        self._repo = False
        # The tier resolver of each job, after its base fetch (B14 step 3).
        self.tier_memo = {}

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

    # per-pass values ------------------------------------------------------
    def repo(self):
        """The owner/name the sync and the writes name, read once per pass."""
        if self._repo is False:
            git = ff.which_real("git")
            self._repo = ff.gh_default_repo(git) if git else None
        return self._repo

    def engine_login(self):
        """The engine's own login, read with `gh api user` the first time
        anything in the pass needs it and kept for the rest of the pass only;
        None when the read failed (plan 3.2 item 1)."""
        if self._login is False:
            ok, data = self.gh(["api", "user"])
            login = data.get("login") if ok and isinstance(data, dict) else None
            self._login = login if isinstance(login, str) and login else None
        return self._login

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
        repo = self.repo()
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
        # The 1b issue reads (plan 3.2 items 4 and 5): read only, kept in
        # memory, written per job in phase B under its lock. A job whose
        # reads do not all answer gets no entry, so its issue facts wait for
        # a later pass (plan 3.1); the sync then counts as incomplete.
        self.perms = fissue.Permissions(self.gh, repo, jobs.setting)
        issues_complete = self.read_issues(repo)
        if complete and self.enough():
            label = quote(str(self.setting("flow.factory.label", "flow:factory")), safe=":")
            # --paginate --slurp: every page, as a list of pages.
            ok, pages = self.gh(["api", "--paginate", "--slurp",
                                 f"repos/{repo}/issues?labels={label}&state=open&per_page=100"])
            if ok and isinstance(pages, list) and all(isinstance(pg, list) for pg in pages):
                if not self.create_jobs(repo, [i for pg in pages for i in pg]):
                    complete = False
            else:
                complete = False
        else:
            complete = False
        complete = complete and issues_complete
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

    def read_issues(self, repo):
        """B4's reads for every non-terminal job, kept in self.issue_sync.
        False when the engine login could not be read (no job gets an entry,
        plan 3.2 item 1) or the time ran out before a job (later jobs wait
        for the next pass). A job whose own reads failed gets no entry, so
        its issue facts wait (plan 3.1), and the failure is reported by the
        sync_failed line; it does not hold back last_sync_at, so one job's
        unreadable issue does not make every pass sync again (Inferred)."""
        login = self.engine_login()
        if login is None:
            return False
        for n, job in self.scanned:
            if not isinstance(job, dict) or self.table.kind(job.get("state")) == "terminal":
                continue
            if not self.enough():
                return False
            first, self.sync_error = self.sync_error, None
            snap = fissue.read_issue(self.gh, repo, n, job, self.perms)
            why, self.sync_error = self.sync_error, first
            if snap is not None:
                self.issue_sync[n] = {"snapshot": snap}
            else:
                self.status("sync", f"ISSUE_READ_FAILED job={job.get('key')} {why or 'the answer was not usable'}")
        return True

    # creation (row 1) ------------------------------------------------------
    def create_jobs(self, repo, issues):
        """Creation row 1 for each labelled open issue; False when a read
        it needed did not answer (the issue waits for the next sync)."""
        complete = True
        for item in issues:
            if not self.enough():
                return False
            if not isinstance(item, dict) or "pull_request" in item:
                continue
            n = item.get("number")
            if not isinstance(n, int) or isinstance(n, bool) or n < 1:
                continue
            try:
                if self.create_one(repo, n, item) is False:
                    complete = False
            except Refused as r:
                self.status("other", f"FACTORY_REFUSED={r} job=issue-{n}")
        return complete

    def base_branch(self, repo):
        """default_branch of `gh api repos/O/R`, read once per sync (the base
        of a job created in this pass); None when the read failed."""
        if self.default_branch is None:
            ok, data = self.gh(["api", f"repos/{repo}"])
            b = data.get("default_branch") if ok and isinstance(data, dict) else None
            self.default_branch = b if ftiers.base_ref({"base": b}) else None
        return self.default_branch

    def terminal_vouches(self, n, existing):
        """The vouch_at of every terminal job of issue n: the current
        job.json when it is terminal, and each archived one (creation row 1's
        fifth condition). An unreadable archived job gives None, which the
        condition reads as a vouch at or after the label. A linked J/archive,
        or a linked archive/jN, is read as one unreadable job: nothing is read
        through the link, and creation waits."""
        out = []
        if isinstance(existing, dict) and self.table.kind(existing.get("state")) == "terminal":
            out.append(existing.get("vouch_at"))
        names = self._archive_names(n)
        if names is None:
            return out + [None]
        adir = os.path.join(jobs.job_dir(self.paths, n), "archive")
        for name in sorted(names):
            if not (name.startswith("j") and name[1:].isdigit()):
                continue
            if _linked_dir(os.path.join(adir, name)):
                out.append(None)
                continue
            old = _read_json(os.path.join(adir, name, "job.json"))
            out.append(old.get("vouch_at") if isinstance(old, dict) else None)
        return out

    def _archive_names(self, n):
        """The names in J/archive ([] when there is none); None when J/archive
        is a link or not a folder."""
        adir = os.path.join(jobs.job_dir(self.paths, n), "archive")
        if _linked_dir(adir):
            return None
        try:
            return os.listdir(adir)
        except OSError:
            return []

    def _archive_seq(self, n):
        names = self._archive_names(n) or []
        seqs = [int(x[1:]) for x in names if x.startswith("j") and x[1:].isdigit()]
        return max(seqs, default=0)

    def _key_seq(self, key):
        try:
            return int(key.rsplit("-j", 1)[1])
        except (AttributeError, IndexError, ValueError):
            return 0

    def create_one(self, repo, n, item):
        existing = jobs.read_job(self.paths, n)
        if isinstance(existing, jobs.Unreadable):
            return None
        if isinstance(existing, dict) and self.table.kind(existing.get("state")) != "terminal":
            return None
        seq = max(self._archive_seq(n), self._key_seq(existing.get("key")) if isinstance(existing, dict) else 0) + 1
        key = f"issue-{n}-j{seq}"
        unjobbed = fissue.read_unjobbed(self.gh, repo, n, self.perms, jobs.setting)
        if unjobbed is None:
            return False
        local = {"open_job": False, "terminal_vouch_at": self.terminal_vouches(n, existing)}
        ctx = ftable.Context(built={ftable.CREATION_FACT: lambda: fissue.creation_conditions(unjobbed, local,
                                                                                               jobs.setting)},
                             setting=jobs.setting, pass_id=self.pass_id, channel="engine", caller=self.me,
                             now=ff.utc_now())
        d = ftable.choose_creation(self.table, key, ctx)
        if isinstance(d, ftable.Blocked):
            self.status("blocked", f"BLOCKED_UNBUILT job={key} state=none event=issue_labelled fact={d.fact} "
                                   f"phase={d.phase}")
            return None
        if not isinstance(d, ftable.Winner):
            return None
        base = self.base_branch(repo)
        if base is None:
            return False
        label = unjobbed["label_event"]
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
                       "created_at": now, "updated_at": now, "vouch_at": label["created_at"],
                       "vouch_event_id": label["id"], "base": base}
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
    def order(self):
        """scanned sorted once per pass, after the sync: labels.priorityHigh
        first, then issue number (design stages L35, plan 3.2). The label is
        this pass's sync's where the job has an entry, else job.json's
        priority_high, which the last completed sync wrote."""
        high = label_name("priorityHigh")

        def key(item):
            n, job = item
            entry = self.issue_sync.get(n)
            if entry is not None:
                prio = high in (entry["snapshot"].get("labels") or [])
            else:
                prio = isinstance(job, dict) and job.get("priority_high") is True
            return (0 if prio else 1, n)
        self.scanned = sorted(self.scanned, key=key)

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
                    jp.sync_writes()
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
                        if isinstance(current.get("held_result"), dict) and current.get("confirmed_intent"):
                            # A held result whose replay failed or was blocked
                            # waits for the next pass's replay (B14 step 10):
                            # the stage it finished is not launched again.
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
        if _live_lease_found(self.paths):
            return "wait"
        for n, job in found:
            if not isinstance(job, dict) or self.table.kind(job.get("state")) == "terminal":
                continue
            jdir = jobs.job_dir(self.paths, n)
            pdir = os.path.join(jdir, "pending")
            # A linked J/pending is never listed: the pass refuses the job
            # (factory_dir_refused), so nothing behind the link waits. A
            # real J/pending that cannot be listed is refused the same way
            # (pending_unlisted) and waits for a person.
            if not _linked_dir(pdir) and os.path.isdir(pdir):
                try:
                    names = os.listdir(pdir)
                except OSError:
                    names = []
                if any(jobs.PENDING_NAME.match(x) for x in names):
                    return "wait"
            did = job.get("directive")
            if did:
                # A linked J/directives is never read through: the pass
                # refuses the job, and nothing handles a pending-report file
                # behind the link.
                ddir = os.path.join(jdir, "directives")
                if not _linked_dir(ddir) and os.path.lexists(os.path.join(ddir, did + ".pending-report.jsonl")):
                    return "wait"
                if directive_open(self.paths, n, did):
                    return "wait"
        return "idle"

    def orphan_lines(self):
        for n, job in jobs.jobs(self.paths):
            if not isinstance(job, dict):
                continue
            for entry in job.get("orphan_groups") or []:
                if orphan_alive(entry):
                    self.status("orphan", f"ORPHAN_GROUP job={job['key']} pgid={entry['pgid']} stage={entry['stage']}")

    # the outbox drain (B14 step 5) -----------------------------------------
    def drain(self):
        """Between phase B and phase C: each job with an outbox, terminal
        jobs included, under its own job lock (never the global lock), runs
        B6's drain with the pass's engine login and the job's tier memo. A
        job left when the time runs out is drained in the next pass. Then
        the park lines of plan 2.3 for each job in waiting_operator."""
        gh_real = ff.which_real("gh")
        login = None
        for n, job in jobs.jobs(self.paths):
            if not isinstance(job, dict):
                continue
            odir = os.path.join(jobs.job_dir(self.paths, n), "outbox")
            if not os.path.lexists(odir):
                continue
            if _linked_dir(odir):
                # A link or something other than a folder is never listed
                # here; the drain says why the job's writes wait
                # (OUTBOX_UNREADABLE) without reading through it.
                has = True
            else:
                try:
                    has = any(x.endswith(".json") for x in os.listdir(odir))
                except OSError:
                    # A folder that cannot be listed: the drain gives its
                    # OUTBOX_UNREADABLE reason=unlisted line.
                    has = True
            if not has:
                continue
            if not self.enough():
                break
            if login is None:
                login = self.engine_login()
                if login is None or not gh_real:
                    self.status("other", "ENGINE_LOGIN_UNKNOWN next: check gh auth status in "
                                         f"{self.paths.main}" if login is None else "PAUSED gh_not_found")
                    break
            try:
                with jobs.job_lock(self.paths, n, timeout=self.lock_wait()):
                    current = jobs.read_job(self.paths, n)
                    if not isinstance(current, dict):
                        continue
                    jp = JobPass(self, n, current)
                    for line in fgithub.drain(self.paths, current, gh_real, lambda k, jp=jp: jp.tiers()(k), login,
                                              enough=self.enough):
                        self.status("other", line)
            except Refused as r:
                if not str(r).startswith("lock_timeout"):
                    self.status("other", f"FACTORY_REFUSED={r} job=issue-{n}")
        if self._login is None:
            # The pass read the login and the read failed (a row's write
            # needed it): say so even when no job had an item to drain
            # (plan R95, Inferred: the line names the pass, not an item).
            self.status("other", f"ENGINE_LOGIN_UNKNOWN next: check gh auth status in {self.paths.main}")
        for n, job in jobs.jobs(self.paths):
            if not isinstance(job, dict) or job.get("state") != "waiting_operator":
                continue
            pi = job.get("pending_intent")
            if isinstance(pi, dict):
                self.status("other", f"WAITING_OPERATOR job={job['key']} intent={pi.get('id')} kind={pi.get('kind')} "
                                     f"keys={','.join(pi.get('key') or [])} next: flow-factory.sh confirm "
                                     f"{pi.get('id')} in a terminal, or change the key")
            elif job.get("reason") == "tier_confirm":
                self.status("other", f"WAITING_OPERATOR job={job['key']} reason=tier_confirm "
                                     f"keys={','.join(job.get('pending_keys') or [])} next: change the key, or "
                                     f"confirm from an interactive executor in default mode")

    def output(self):
        try:
            self.lines["probe"] = staleness.status_lines(self.paths.fdir, jobs.setting) + self.lines["probe"]
        except Refused as r:
            self.status("probe", f"FACTORY_REFUSED={r}")
        self.orphan_lines()
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


def _result_present(paths, n, did):
    """Whether the directive's result file is there: a regular file in a
    J/results that is not a symbolic link. A linked J/results, or a result
    that is itself a link, is treated as absent, so a link cannot mark a
    directive finished (journal wave 4, linked job folders)."""
    path = _result_path(paths, n, did)
    rdir = os.path.dirname(path)
    if os.path.islink(rdir) or os.path.islink(path):
        return False
    return os.path.lexists(path)


def _live_lease_found(paths):
    """Whether a job folder's own J/directives holds a live lease: one that
    is not revoked and whose launcher runs with the start time it records
    (the rule of the caller module's live_leases). A job folder or a
    J/directives that is a link or not a folder is not read through, and a
    lease file that is itself a link is not read (journal wave 4, linked job
    folders): a lease found that way is not the job's. A folder that cannot
    be listed holds no lease that can be read."""
    jroot = os.path.join(paths.fdir, "jobs")
    if _linked_dir(jroot):
        return False
    try:
        folders = sorted(os.listdir(jroot))
    except OSError:
        return False
    for name in folders:
        jdir = os.path.join(jroot, name)
        ddir = os.path.join(jdir, "directives")
        if _linked_dir(jdir) or _linked_dir(ddir):
            continue
        try:
            files = sorted(os.listdir(ddir))
        except OSError:
            continue
        for x in files:
            if not x.endswith(".lease.json"):
                continue
            lease = _read_json(os.path.join(ddir, x))
            if isinstance(lease, dict) and lease.get("revoked_at") is None \
                    and fcaller._alive(lease.get("launcher_pid"), lease.get("launcher_start")):
                return True
    return False


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
    if _result_present(paths, n, did):
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
        # The stored pending event's facts and raise time, for the
        # via_comment and retry_by_triage_only callables and the re-vouch
        # input (B14 step 4); empty for an engine event.
        self.pending_facts = {}
        self.event_at = None
        self.ctx_args = {}
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
            self.p.status("clone", jobs.clone_changed_line(self.key, wt, self.jdir, f, k))
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

    # 1b fact inputs (plan 5.3 Fact inputs, B14 steps 0 and 3) ----------------
    def tiers(self):
        """The job's tier resolver for this pass: the first call fetches
        origin/<base> into the main checkout (design worker_github_access
        L10), then reads the four sources once. A job with no base, a failed
        fetch or a ref that does not resolve reads the project source as
        confirm (plan 3.1), with one status line."""
        memo = self.p.tier_memo
        if self.n not in memo:
            base = self.job.get("base")
            ref = ftiers.base_ref(self.job)
            shown = base if isinstance(base, str) and base else "-"
            if ref is None:
                self.p.status("other", f"BASE_REF_UNRESOLVED job={self.key} ref=origin/{shown}")
            else:
                ok, why = ftiers.fetch_base(self.paths.main, base, self.paths.fdir)
                if not ok:
                    self.p.status("other", f"BASE_FETCH_FAILED job={self.key} ref=origin/{base} {why}")
                    ref = None
            t = ftiers.resolver(self.paths.main, ref, self.paths.fdir)
            if ref is not None and str(t.base_problem or "").startswith("ref_unresolved"):
                self.p.status("other", f"BASE_REF_UNRESOLVED job={self.key} ref=origin/{base}")
            memo[self.n] = t
        return memo[self.n]

    def outbox_linked(self):
        """Whether J/outbox is a symbolic link or something other than a
        folder. Such an outbox is treated as not found at every read and
        write of the row paths, as the drain and the person commands treat
        it (journal wave 4, linked folders): its items are never read,
        run, saved or listed. A linked item file inside a real folder is
        already not found by the GitHub writes module's reader."""
        return _linked_dir(os.path.join(self.jdir, "outbox"))

    def pending_item(self, iid):
        """The job's outbox item iid as recorded. Raises IntentUnknown when
        J/outbox is a link or the item does not read or validate, and the
        GitHub writes module's IntentChanged when it is not the item its
        intent_recorded line records (check_item)."""
        if self.outbox_linked():
            raise IntentUnknown(iid)
        item = fgithub._valid(os.path.join(self.jdir, "outbox", f"{iid}.json"), iid, self.key) \
            if isinstance(iid, str) and "/" not in iid else None
        if item is None:
            raise IntentUnknown(iid)
        changed = fgithub.check_item(os.path.join(self.jdir, "events.jsonl"), item)
        if changed:
            raise changed
        return item

    def confirm_writes(self, writes):
        """Context.confirm_writes: B7's confirm keys of the winner's writes,
        through the job's tier memo. A confirmed intent behind a linked
        J/outbox covers no write kind."""
        job = dict(self.job, confirmed_intent=None) if self.outbox_linked() else self.job
        return ftiers.confirm_writes(list(writes), job, self.tiers(), fdir=self.paths.fdir)

    def issue_facts(self):
        entry = self.p.issue_sync.get(self.n)
        if entry is None:
            raise FactFailed(f"no issue sync for {self.key} in this pass")
        return fissue.facts(entry["snapshot"], self.job, jobs.setting)

    def revouch_input(self, snapshot, waiting):
        """ctx.sync["revouch"]: the sha256 of each waiting untrusted reply
        (plan 5.3 Context), less a reply edited at or after the time of the
        event being applied, or edited at a time that cannot be read (R7:
        the person vouched for the text as it was when they asked)."""
        floor = _epoch(self.event_at) if self.event_at else None
        edits = snapshot.get("edits") if isinstance(snapshot.get("edits"), dict) else {}
        bodies = {c.get("id"): c.get("body") for c in snapshot.get("comments") or []}
        created = {c.get("id"): c.get("created_at") for c in snapshot.get("comments") or []}
        out = {}
        for cid in waiting:
            body = bodies.get(cid)
            if not isinstance(body, str):
                continue
            if self.event_at is not None:
                # A reply posted at or after the retry was not seen by the
                # person who retried, so it is not re-vouched either
                # (Inferred, the same reading as R7).
                at = _epoch(created.get(cid))
                late = floor is None or at is None or at >= floor
                for e in edits.get(f"comment:{cid}") or []:
                    at = _epoch(e.get("edited_at")) if isinstance(e, dict) else None
                    if floor is None or at is None or at >= floor:
                        late = True
                if late:
                    continue
            out[str(cid)] = ftext.body_sha256(body)
        return out

    def sync_values(self):
        """ctx.sync for one decision (plan 5.3 Context): a dict in every
        decision; revouch, answers and untrusted_replies only when the job
        has a complete issue-sync entry this pass."""
        sync = {"pending_keys": None}
        entry = self.p.issue_sync.get(self.n)
        if entry is not None:
            trusted, untrusted = fissue.needs_info_answers(entry["snapshot"], self.job)
            sync["answers"] = list(trusted)
            sync["untrusted_replies"] = list(untrusted)
            sync["revouch"] = self.revouch_input(entry["snapshot"], untrusted)
        return sync

    def built_1b(self, sync):
        job = self.job

        def issue_fact(name):
            return lambda: bool(self.issue_facts()[name])

        def pending_bool(name):
            def f():
                v = self.pending_facts.get(name) if isinstance(self.pending_facts, dict) else None
                return v if isinstance(v, bool) else False
            return f

        def tier_confirm_blocking():
            try:
                keys = ftiers.confirm_path_keys(self.paths.main, None, self.job, tiers=self.tiers())
            except ValueError as e:
                raise FactFailed(str(e)) from e
            # Row 40b's pending_keys handler reads the keys found in this
            # decision (plan 5.3 Context).
            sync["pending_keys"] = list(keys)
            return bool(keys)

        def intent_key_not_confirm():
            if not isinstance(self.job.get("pending_intent"), dict):
                return False
            return ftiers.intent_key_not_confirm(self.paths.main, None, self.job, tiers=self.tiers())

        def intent_effect_observed():
            pi = self.job.get("pending_intent")
            if not isinstance(pi, dict):
                return False
            # An item that is not found, or is not the one recorded, has no
            # effect of its own to observe (T:facts.intent_effect_observed:
            # the pending intent's effect). It is false, with a status line
            # in every pass, so the job's other exits still apply and the
            # park is not silent (plan 5.2, "Outbox file edited").
            try:
                self.pending_item(pi.get("id"))
            except (IntentUnknown, fgithub.IntentChanged) as e:
                head, _, tail = e.line.partition(" ")
                self.p.status("other", f"{head} job={self.key}" + (f" {tail}" if tail else ""))
                return False
            login = self.p.engine_login()
            gh_real = ff.which_real("gh")
            if login is None or not gh_real:
                raise FactFailed("engine login unknown" if login is None else "gh not found")
            try:
                return fgithub.lookup(gh_real, self.job, pi.get("id"), login, paths=self.paths) is not None
            except fgithub.ReadFailed as e:
                raise FactFailed(f"lookup {e}") from e

        out = {f: issue_fact(f) for f in ("untrusted_edit", "needs_info_answer", "untrusted_needs_info_answer",
                                           "cancel_signal", "untrusted_close", "dependency_open")}
        out.update({"via_comment": pending_bool("via_comment"),
                    "retry_by_triage_only": pending_bool("retry_by_triage_only"),
                    "tier_confirm_blocking": tier_confirm_blocking,
                    "intent_key_not_confirm": intent_key_not_confirm,
                    "intent_effect_observed": intent_effect_observed})
        del job
        return out

    def built(self, sync=None):
        job = self.job
        concurrency = self.p.num("concurrency", 1, 1)
        max_open = self.p.num("maxOpenJobs", 5, 1)
        changes = job.get("pending_changes") or []
        return dict(self.built_1b(sync if sync is not None else {"pending_keys": None}), **{
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
        })

    def ctx(self, channel, caller, args=None, facts=None, result=None):
        """The one place next builds a job's Context: every 1b callable,
        confirm_writes and ctx.sync in every decision (plan 5.3)."""
        sync = self.sync_values()
        return ftable.Context(built=self.built(sync), setting=jobs.setting, pass_id=self.p.pass_id,
                              channel=channel, caller=caller, now=ff.utc_now(), confirm_writes=self.confirm_writes,
                              sync=sync, args=dict(args or {}), facts=dict(facts or {}), result=result)

    # deciding and applying -----------------------------------------------
    def decide(self, event, channel="engine", caller=None, args=None, facts=None, result=None):
        """Choose and apply one event. Returns "applied", "nomove", "blocked",
        "refused" or "failed" (a fact or an effect could not be run; nothing
        changed)."""
        state = self.job["state"]
        if facts is None:
            # An engine event: no stored record, so no comment facts and no
            # event time.
            self.event_at = None
        self.pending_facts = facts if isinstance(facts, dict) else {}
        self.ctx_args = dict(args or {})
        ctx = self.ctx(channel, caller, args, facts, result)
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
        killed = False
        before = self.outbox_ids()
        try:
            if "kill" in handlers or leaving:
                self.kill_current(new)
                killed = True
            for h, e in to_run:
                if h == "snapshot":
                    self.snapshot(new, d.row)
                elif h == "reset":
                    self.reset()
            # Carry item 2: the handled caller effects run inside the same
            # try, after kill_current, so a failure keeps what the kill did.
            self.caller_effects(d, ctx, new, line, to_run)
        except (fgit.GitFailed, fgit.CloneConfigChanged, Refused, ValueError, OSError) as e:
            # No write of a decision that did not apply may be sent: every
            # outbox item this decision recorded is dropped, and what the
            # kill did is kept (B14 steps 7 and 9).
            self.drop_recorded(before)
            self.keep_kill(new, killed or "snapshot" in handlers)
            if isinstance(e, fgithub.IntentNotPending) or \
                    (d.row == "41" and isinstance(e, (fgithub.IntentChanged, IntentUnknown))):
                # R68, R32: a confirm that names another intent, or an
                # intent whose item is not found or not the one recorded,
                # is refused with its line and runs nothing; its stored
                # event is dropped, so it is not tried again every pass
                # (plan 2.3, 5.2). Rows 41e and 41k, which a pass raises
                # again by itself, report EFFECT_FAILED instead.
                self.refuse(e.line)
                return "refused"
            self.p.status("other", f"EFFECT_FAILED job={self.key} row={d.row} {' '.join(str(e).split())}")
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
        if "replay" in handlers:
            self.replay()
        return "applied"

    def keep_kill(self, new, kept_any):
        """After a decision that did not apply: write job.json with the
        fields kill_current and the snapshot set (cost, last_session_total,
        sessions, orphan_groups, snapshots), not the move (B14 step 9)."""
        if not kept_any:
            return
        kept = dict(self.job)
        for f in ("cost", "last_session_total", "sessions", "orphan_groups", "snapshots"):
            if f in new:
                kept[f] = new[f]
        kept["updated_at"] = ff.utc_now()
        jobs.write_job(self.paths, kept)
        self.job = kept

    def outbox_ids(self):
        """The intent ids of the items in J/outbox now (none when there is
        no readable outbox folder, or J/outbox is a link)."""
        odir = os.path.join(self.jdir, "outbox")
        if self.outbox_linked():
            return set()
        try:
            return {x[:-len(".json")] for x in os.listdir(odir) if x.endswith(".json")}
        except OSError:
            return set()

    def drop_recorded(self, before):
        """Drop every outbox item recorded since `before` (the ids there when
        the decision started), the caller handlers' and the intake module's
        alike: the decision did not apply, so its writes must never run."""
        for iid in sorted(self.outbox_ids() - before):
            try:
                self.drop_intent(self.job, iid)
            except (Refused, ValueError, OSError) as e:
                self.p.status("other", f"WRITE_NOT_DROPPED job={self.key} intent={iid} {' '.join(str(e).split())}")

    def drop_intent(self, job, iid):
        """B6's drop_intent, except that behind a linked J/outbox the item
        is not found: the intent_dropped line is written as drop_intent
        writes it for an item that does not read, and nothing is saved
        through the link."""
        if not self.outbox_linked():
            fgithub.drop_intent(self.paths, job, iid)
            return
        jobs._need_job_lock(self.n)
        if not (isinstance(iid, str) and re.fullmatch(r"[0-9a-z-]+", iid) and iid.startswith(self.key + "-")):
            raise ValueError(f"intent {iid!r}")
        h = fgithub._history(os.path.join(self.jdir, "events.jsonl"), iid)
        if h["rec"] is None or h["sent"] or h["dropped"]:
            return
        fgithub._drop(self.paths, self.n, self.key, iid, None, None)

    # 1b caller handlers (plan B13 table, B14 steps 6 to 8) ---------------------
    def repo(self):
        repo = self.p.repo()
        if not repo:
            raise Refused("repository_unknown")
        return repo

    def login(self):
        login = self.p.engine_login()
        if login is None:
            raise Refused("engine_login_unknown")
        return login

    def record(self, new, row, kind, argv, body, key, blocking, ref=None, state=None):
        return fgithub.record_job_intent(self.paths, new, row, kind, argv, body, list(key), blocking, ref=ref,
                                         state=state, repo=self.repo())

    def caller_effects(self, d, ctx, new, line, to_run):
        """Run the 1b caller handlers of the decision on new, under the job
        lock, before job.json and the transition line are written; each
        field a handler sets goes into the line's fields (plan 2.2)."""
        fields = line.setdefault("fields", {})
        frm, to = d.state, new["state"]
        # The parked-state notices first: they only record outbox items, and
        # a failure there must come before any step that cannot be undone
        # (the answers file, a write run, a dropped intent, the labels_set
        # line), so a decision that fails leaves nothing but items
        # drop_recorded drops. The dropped intent and the labels_set line come
        # last, after every handler ran.
        labels_line = self.parked_notices(d, new, frm, to) if frm != to else None
        names = set(h for h, _ in to_run) | set(ftable.EFFECTS[e][1] for e in d.effects
                                               if ftable.EFFECTS[e][0] == "handled")
        args = ctx.args or {}
        # Row 44 (needs_human, person_answer, no guard) records no answer in
        # its effects; an NI answer given there must still reach the answers
        # file before the job resumes (journal wave 3, open for B14).
        row44 = d.row == "44" and d.event == "person_answer" and "answer" not in names \
            and isinstance(args.get("qid"), str) and args["qid"].startswith("NI-") and isinstance(args.get("text"), str)
        answers = "answer" in names or row44
        if "revouch" in names or (answers and (d.row in ANSWER_FILE_ROWS or d.event == "person_answer")):
            # A spec-input source changes outside the sync, so the issue set
            # goes (plan 2.2). Before the answers file is written: deleting
            # it early only makes row 66i wait for the next sync. Never
            # through a linked J/sync: the file there is not the job's, and
            # row 66i refuses a linked J/sync anyway.
            sdir = os.path.join(self.jdir, "sync")
            path = os.path.join(sdir, "issue-set.json")
            if not _linked_dir(sdir) and os.path.lexists(path):
                os.unlink(path)
        for h, effect in to_run:
            if h not in CALLER_1B:
                continue
            if h == "pr_close":
                pr = new.get("pr")
                if isinstance(pr, int) and not isinstance(pr, bool) and pr >= 1:
                    self.record(new, d.row, "pr_close", fgithub.literal_pr_close(self.repo(), pr), None,
                                NOTICE_KEY, False, state=to)
            elif h == "answer":
                self.effect_answer(d, ctx, new)
            elif h == "notice":
                self.effect_notice(d, ctx, new, fields)
            elif h == "intake_record":
                judge = self.judge(ctx)
                fields.update(fintake.effect_accept(self.paths, new, judge, repo=self.repo()))
            elif h == "refuse_note":
                self.effect_refuse_note(d, ctx, new, effect)
            elif h == "issue_md":
                self.effect_issue_md(new, fields)
            elif h == "hold_intent":
                self.effect_hold(d, ctx, new, fields)
            elif h == "write":
                self.effect_write(d, new, fields)
        if row44:
            fintake.effect_answer(self.paths, new, args["qid"], args["text"])
        old_pi = self.job.get("pending_intent")
        if "intent_clear" in names and isinstance(old_pi, dict) and new.get("pending_intent") is None:
            self.drop_intent(new, old_pi.get("id"))
        if labels_line is not None:
            jobs.append_event(self.paths, self.n, labels_line)

    def judge(self, ctx):
        judge = (ctx.result or {}).get("judge") if isinstance(ctx.result, dict) else None
        if not isinstance(judge, dict):
            raise Refused("judge_result_missing")
        return judge

    def effect_answer(self, d, ctx, new):
        if d.row == "8":
            ids = list((ctx.sync or {}).get("answers") or [])
            jobs.append_event(self.paths, self.n, {"type": "answer_comments", "job": self.key, "pass": self.p.pass_id,
                                                   "comments": ids})
            return
        args = ctx.args or {}
        fintake.effect_answer(self.paths, new, args.get("qid"), args.get("text") if isinstance(args.get("text"), str)
                              else "")

    def effect_notice(self, d, ctx, new, fields):
        repo = self.repo()
        if d.row == "4":
            needs_info = fintake.effect_needs_info(self.paths, new, self.judge(ctx), ctx.now, repo=repo)
            new["needs_info"] = needs_info
            fields["needs_info"] = needs_info
        elif d.row == "5":
            fintake.effect_reject(self.paths, new, self.judge(ctx), repo=repo)
        elif d.row == "8u":
            for cid in (ctx.sync or {}).get("untrusted_replies") or []:
                fintake.effect_revouch_notice(self.paths, new, cid, repo=repo)
                self.p.status("other", f"REVOUCH_NEEDED job={self.key} comment={cid}")
        # Row 6's notice is posted by effect_accept with its record.

    def effect_refuse_note(self, d, ctx, new, effect):
        ch = ctx.channel if isinstance(ctx.channel, str) else ""
        ref = int(ch.split(":", 1)[1]) if ch.startswith("comment:") and ch.split(":", 1)[1].isdigit() else None
        text = effect[len("refuse: "):] if effect.startswith("refuse: ") else effect
        self.p.status("refused", f"EVENT_REFUSED={d.event} job={self.key} row={d.row} {text}")
        body = f"Job {self.key} did not act on {d.event.replace('_', ' ')}: {text}"
        self.record(new, d.row, "comment", fgithub.literal_comment(self.repo(), self.n), body, NOTICE_KEY, False,
                    ref=ref, state=new["state"])

    def effect_issue_md(self, new, fields):
        """Row 66i (B14 step 6): issue.md and baseline_digest from the
        persisted issue set, never from the sync's memory; a missing set, or
        one whose digest is not its items' or job.json's issue_digest, is
        issue_set_stale, and so is a J/sync that is a link or not a folder."""
        sdir = os.path.join(self.jdir, "sync")
        if _linked_dir(sdir):
            raise Refused("issue_set_stale")
        data = _read_json(os.path.join(sdir, "issue-set.json"))
        if not isinstance(data, dict) or not isinstance(data.get("items"), list):
            raise Refused("issue_set_stale")
        dig = data.get("digest")
        try:
            ok = dig == ftext.digest(data["items"]) and dig == new.get("issue_digest")
            text = ftext.render_issue_md(data["items"], data.get("others") or [])
        except (ValueError, TypeError):
            ok = False
        if not ok:
            raise Refused("issue_set_stale")
        copies = os.path.join(self.jdir, "in-copies")
        jobs._ensure(self.paths, copies)
        try:
            _atomic_write(os.path.join(copies, "issue.md"), text)
        except JournalAtomicError as e:
            raise Refused(f"issue_md_unwritable {e.summary}") from e
        new["baseline_digest"] = dig
        fields["baseline_digest"] = dig

    def assign_literal(self):
        return fgithub.literal_assign_label(self.repo(), self.n, self.login(), label_name("inProgress"))

    def effect_hold(self, d, ctx, new, fields):
        """Row 40: the blocking write of the row that would have applied,
        as one pending intent, and the held event (plan 2.2). In 1b the only
        such write is prepare's assignment and in-progress label."""
        facts = dict(d.facts, **{ftable.BWC: False})
        under = ftable._decide(self.p.table, d.state, d.event, facts)
        writes = list(under.writes) if isinstance(under, ftable.Winner) else []
        if not set(writes) & {"assignment", "in-progress label"}:
            raise Refused(f"intent_kind_not_built writes={','.join(writes) or 'none'}")
        iid = self.record(new, "40", "assign_label", self.assign_literal(), None, ASSIGN_KEY, True,
                          state=new["state"])
        pi = {"id": iid, "kind": "assign_label", "key": list(ASSIGN_KEY)}
        held = {"event": d.event, "args": dict(ctx.args or {}), "channel": ctx.channel, "caller": ctx.caller,
                "facts": dict(ctx.facts or {})}
        for f, v in (("pending_intent", pi), ("held_result", held)):
            new[f] = v
            fields[f] = v

    def effect_write(self, d, new, fields):
        gh_real = ff.which_real("gh")
        if d.row == "11":
            ci = new.get("confirmed_intent")
            if ci:
                # A confirmed item behind a linked J/outbox is not found.
                item = None if self.outbox_linked() else fgithub.sent_item(self.jdir, ci, self.key)
                if isinstance(item, dict) and item.get("kind") == "assign_label":
                    return
            self.record(new, "11", "assign_label", self.assign_literal(), None, ASSIGN_KEY, True, state=new["state"])
            return
        if d.row not in ("41", "41e", "41k"):
            raise Refused(f"write_row_not_built row={d.row}")
        pi = self.job.get("pending_intent")
        iid = (self.ctx_args.get("intent") if d.row == "41" else (pi or {}).get("id"))
        lines = []
        if d.row == "41e":
            # T:41e records the observed effect; it never runs the write,
            # whose keys may still resolve to confirm.
            self.observe_intent(iid, gh_real, lines)
        else:
            # Behind a linked J/outbox, or when the item does not read, the
            # pending item is not found; a confirm naming another intent is
            # still IntentNotPending, which run_literal raises first.
            if isinstance(pi, dict) and iid == pi.get("id") and \
                    (self.outbox_linked() or fgithub._valid(os.path.join(self.jdir, "outbox", f"{iid}.json"),
                                                            iid, self.key) is None):
                raise IntentUnknown(iid)
            fgithub.run_literal(self.paths, dict(self.job, write_seq=new.get("write_seq")), iid, gh_real,
                                self.login(), tiers=lambda k: self.tiers()(k), lines=lines)
        for line in lines:
            self.p.status("other", line)
        for f, v in (("confirmed_intent", iid), ("pending_intent", None), ("pending_keys", None)):
            new[f] = v
            fields[f] = v

    def observe_intent(self, iid, gh_real, lines):
        """Row 41e: record the pending intent's effect as found on GitHub,
        as run_literal records a found effect, and run nothing. An item a
        write_recorded line names is taken as sent; an effect no longer seen
        raises Refused("effect_not_observed"), so the decision fails and the
        job stays parked."""
        pi = self.job.get("pending_intent")
        if not isinstance(pi, dict) or iid != pi.get("id"):
            raise fgithub.IntentNotPending(iid, pi.get("id") if isinstance(pi, dict) else None)
        if self.outbox_linked():
            raise Refused(f"intent_unknown {iid}")
        path = os.path.join(self.jdir, "outbox", f"{iid}.json")
        item = fgithub._valid(path, iid, self.key)
        if item is None:
            raise Refused(f"intent_unknown {iid}")
        changed, _, h = fgithub._checked(os.path.join(self.jdir, "events.jsonl"), item)
        if changed:
            raise changed
        if h["sent"]:
            fgithub._resent(path, item, h)
            return
        if h["dropped"]:
            raise Refused(f"intent_dropped {iid}")
        try:
            effect = fgithub._look(gh_real, item, self.login(), self.paths.main)
        except fgithub.ReadFailed as e:
            raise Refused(f"write_failed {iid}: lookup: {e}") from e
        if not effect:
            raise Refused(f"effect_not_observed {iid}")
        fgithub._sent(self.paths, self.n, path, item, effect)
        lines.append(f"WRITE_SKIPPED job={self.key} intent={iid} found={fgithub._found_text(effect)}")

    def parked_notices(self, d, new, frm, to):
        """B14 step 8: on entry to needs_info a label_add of labels.needsInfo;
        on entry to needs_human the needs-human notice and a label_add of
        labels.needsHuman; on entry to waiting_operator with reason
        tier_confirm the tier-confirm notice; on leaving needs_info or
        needs_human a label_remove of each label in labels_set. Notices,
        never blocking, under issueUpdate, recorded for the row. Returns the
        labels_set line when the list changed, else None."""
        repo = self.repo()
        labels = [x for x in new.get("labels_set") or [] if isinstance(x, str)]
        changed = False
        if frm in LABELLED_PARKS:
            for label in labels:
                self.record(new, d.row, "label_remove", fgithub.literal_label_remove(repo, self.n, label), None,
                            NOTICE_KEY, False, state=to)
            changed = bool(labels)
            labels = []
        if to == "needs_human":
            fintake.effect_needs_human(self.paths, new, repo=repo, row=d.row)
        elif to == "waiting_operator" and new.get("reason") == "tier_confirm" and new.get("pending_keys"):
            fintake.effect_tier_confirm(self.paths, new, list(new["pending_keys"]), repo=repo, row=d.row)
        if to in LABELLED_PARKS:
            label = label_name(LABELLED_PARKS[to])
            self.record(new, d.row, "label_add", fgithub.literal_label_add(repo, self.n, label), None, NOTICE_KEY,
                        False, state=to)
            if label not in labels:
                labels.append(label)
            changed = True
        if changed:
            new["labels_set"] = labels
            # Appended by caller_effects once every other effect ran.
            return {"type": "labels_set", "job": self.key, "time": ff.utc_now(), "labels_set": list(labels)}
        return None

    def replay(self):
        """B14 step 10: decide held_result's event once in the resume state,
        with the held channel, caller and facts, without the directive,
        result-file and charge checks (they ran when it first arrived); on
        applied, nomove or refused clear held_result and confirmed_intent
        with a replayed line; on failed or blocked keep both for the next
        pass."""
        held = self.job.get("held_result")
        intent = self.job.get("confirmed_intent")
        if not isinstance(held, dict) or not intent or not isinstance(held.get("event"), str):
            return None
        args = held.get("args") if isinstance(held.get("args"), dict) else {}
        facts = held.get("facts") if isinstance(held.get("facts"), dict) else {}
        v = facts.get("unvouched_session_action")
        self.unvouched = v if isinstance(v, bool) else True
        did = args.get("directive")
        # Never through a linked J/results (_result_present): a missing or
        # linked result gives None.
        result = _read_json(_result_path(self.paths, self.n, did)) \
            if isinstance(did, str) and did and _result_present(self.paths, self.n, did) else None
        # moved, after the replay, says whether this job moved in the pass:
        # by the row that released the park (the replay inside apply), or by
        # the replayed decision itself.
        moved_before, self.moved = self.moved, False
        outcome = self.decide(held["event"], held.get("channel"), held.get("caller"), args=args, facts=facts,
                              result=result if isinstance(result, dict) else None)
        if outcome in ("applied", "nomove", "refused"):
            new = dict(self.job, held_result=None, confirmed_intent=None, updated_at=ff.utc_now())
            jobs.write_job(self.paths, new)
            jobs.append_event(self.paths, self.n, {
                "type": "replayed", "job": self.key, "time": ff.utc_now(), "intent": intent, "event": held["event"],
                "args": args, "outcome": outcome, "fields": {"held_result": None, "confirmed_intent": None}})
            self.job = new
        self.moved = moved_before or self.moved
        return outcome

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
        rdir = os.path.join(self.jdir, "results")
        stream = os.path.join(rdir, did + ".stream.jsonl")
        # Never through a linked J/results, or a linked stream file.
        linked = _linked_dir(rdir) or os.path.islink(stream)
        init = {} if linked else ff.init_event(ff.stream_events(stream)) or {}
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
        if self.charged(new, did) or _result_present(self.paths, self.n, did):
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

    # the sync's writes (B14 step 1, plan 3.2) ---------------------------------
    def sync_writes(self):
        """Under the job lock, before load_pending, for a job with a complete
        issue-sync entry: B5's commands stored (and commands_seen), the
        label-removal notes, then J/sync/issue-set.json and job.json's
        issue_digest and priority_high, from the snapshot with the answers
        file read now."""
        entry = self.p.issue_sync.get(self.n)
        if entry is None:
            return
        import _flow_factory_commands as fcommands
        snap = entry["snapshot"]
        try:
            repo, login = self.repo(), self.login()
            for cmd in fcommands.scan(snap, self.job, self.p.perms, login, self.p.table):
                for line in fcommands.store(self.paths, self.job, cmd, repo=repo, caller=self.p.me):
                    self.p.status("sync", line)
            label = jobs.setting("flow.factory.label", "flow:factory")
            for note in fcommands.label_notes(snap, self.job, label):
                fcommands.store_label_note(self.paths, self.job, note, repo=repo)
            answers = _read_json(os.path.join(self.jdir, "answers.json")) \
                if os.path.lexists(os.path.join(self.jdir, "answers.json")) else []
            if not isinstance(answers, list):
                raise Refused(f"answers_unreadable {os.path.join(self.jdir, 'answers.json')}")
            data = ftext.issue_set(dict(snap, answers=[{"qid": a.get("qid"), "text": a.get("text")}
                                                       for a in answers if isinstance(a, dict)]),
                                   self.job.get("needs_info"), self.job.get("revouched_replies"))
            sdir = os.path.join(self.jdir, "sync")
            jobs._ensure(self.paths, sdir)
            _atomic_write(os.path.join(sdir, "issue-set.json"),
                          json.dumps(dict(data, synced_at=ff.utc_now()), sort_keys=True, ensure_ascii=False) + "\n")
        except (Refused, ValueError, JournalAtomicError) as e:
            self.p.status("sync", f"SYNC_WRITE_FAILED job={self.key} {' '.join(str(e).split())}")
            return
        high = label_name("priorityHigh") in (snap.get("labels") or [])
        if self.job.get("issue_digest") != data["digest"] or self.job.get("priority_high") is not high:
            self.job = dict(self.job, issue_digest=data["digest"], priority_high=high, updated_at=ff.utc_now())
            jobs.write_job(self.paths, self.job)

    def sync_fingerprint(self):
        """sync_seen's value (plan 3.1, the github_change raise rule): a
        sha256 over the job's state, the 1b issue facts, issue_digest and the
        ids of the comments and events observed; None with no entry."""
        entry = self.p.issue_sync.get(self.n)
        if entry is None:
            return None
        snap = entry["snapshot"]
        data = {"state": self.job.get("state"), "facts": self.issue_facts(), "issue_digest": self.job.get("issue_digest"),
                "comments": sorted(c.get("id") for c in snap.get("comments") or [] if isinstance(c.get("id"), int)),
                "events": sorted(e.get("id") for e in snap.get("events") or [] if isinstance(e.get("id"), int))}
        return hashlib.sha256(json.dumps(data, sort_keys=True).encode("utf-8")).hexdigest()

    # the events ----------------------------------------------------------
    def events(self):
        p = self.p
        # A release whose replay did not finish (the process died between
        # the release and the replayed line, or the replay failed or was
        # blocked): replay first, then the events of event_order unless the
        # replay moved the job (B14 step 10).
        if self.job.get("state") != "waiting_operator" and isinstance(self.job.get("held_result"), dict) \
                and self.job.get("confirmed_intent"):
            self.replay()
            if self.moved:
                return
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
        seen = self.sync_fingerprint()
        live = seen is not None and seen != self.job.get("sync_seen") and \
            self.job["state"] in p.table.events.get("github_change", {}).get("occurs_in", [])
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
                if not github_raised and (self.job.get("pending_changes") or live):
                    github_raised = True
                    outcome = self.run_engine_event("github_change")
                    if outcome in ("applied", "nomove") and seen is not None:
                        # Stored only once github_change was evaluated
                        # (plan 3.1); a moved job re-raises in its new state.
                        self.job = dict(self.job, sync_seen=seen, updated_at=ff.utc_now())
                        jobs.write_job(self.paths, self.job)
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
        self.event_at = None
        return self.decide(event, "engine", None)

    def load_pending(self):
        """{event: [(name, record)]} of J/pending, seq order; a file that
        cannot be read, or names no event of the table, is refused and
        removed."""
        out = {}
        try:
            found = jobs.pending_events(self.paths, self.n)
        except OSError:
            # A real J/pending that cannot be listed or read: the job is
            # refused for this pass, as a linked one is (factory_dir_refused),
            # and its events wait for a person.
            raise Refused(f"pending_unlisted {os.path.relpath(os.path.join(self.jdir, 'pending'), self.paths.main)}")
        for name, rec in found:
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
            if why is None and not _result_present(self.paths, self.n, did):
                why = "no_result"
            if why is not None:
                self.report_refused(did, why, name)
                jobs.drop_pending(self.paths, self.n, name)
                return
            self.charge_from_result(did)
        facts = rec.get("facts") if isinstance(rec.get("facts"), dict) else {}
        v = facts.get("unvouched_session_action")
        self.unvouched = v if isinstance(v, bool) else True
        # The event's own time, for the re-vouch input (R7): the comment's
        # creation for a comment command, else when it was stored.
        comment = rec.get("comment") if isinstance(rec.get("comment"), dict) else {}
        self.event_at = comment.get("created_at") or rec.get("raised_at")
        result = _read_json(_result_path(self.paths, self.n, args.get("directive"))) if is_result else None
        outcome = self.decide(event, rec.get("channel"), rec.get("caller"), args=args, facts=facts,
                              result=result if isinstance(result, dict) else None)
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
        if _linked_dir(ddir):
            # Never listed, read or removed through a link.
            return
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
                if why is None and (_linked_dir(os.path.join(self.jdir, "results")) or os.path.islink(
                        os.path.join(self.jdir, "results", did + ".stream.jsonl"))):
                    # The result and the stream would be read and written
                    # through the link.
                    why = "results_linked"
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
            if self.decide(event, "launcher", None, args={"directive": did, "outcome": record.get("outcome")},
                           facts={}, result=record) in ("failed", "blocked"):
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
        self.pending_facts = {}
        self.event_at = None
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
        elif body is None and not (kind == "judge" and state == "intake"):
            # The intake judge is launched for real (B14 step 11); other
            # judges and engine directives keep the seam body until their
            # phase.
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
        """Whether a stage or judge result of the job waits in pending/. A
        J/pending that is a link, or a real one that cannot be listed, is
        never listed here: the job's results are not known, so the stage is
        not launched again. These two branches are a backstop that no test
        reaches: phase B refuses such a job first (factory_dir_refused or
        pending_unlisted) and phase C skips every job phase B refused, so
        within one pass they matter only if J/pending is replaced between
        phase B and phase C."""
        pdir = os.path.join(self.jdir, "pending")
        if _linked_dir(pdir):
            return True
        if not os.path.lexists(pdir):
            return False
        try:
            names = os.listdir(pdir)
        except OSError:
            return True
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
    # The read-only git commands that compute this pass's facts end by the
    # pass's deadline; commands that change a clone are not cut off.
    fgit.set_deadline(p.deadline)
    p.phase_a()
    # The platform check runs once per pass; an unreadable record refuses
    # here, before any job is touched.
    p.platform()
    p.sync()
    p.order()
    p.environment()
    p.phase_b()
    p.drain()
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
