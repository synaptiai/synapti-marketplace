"""[flow] The factory engine's job store, locks, settings and per-run charge.

Every engine module reads and writes job state through this module:

  resolve(cwd=None, create=True) -> Paths     the main checkout, F and the plugin root; changes into the
                                              main checkout, and creates F (with F/.gitignore) when create
  factory_path_check(paths) -> str or None    the factory_path_changed refusal line when the pointer
                                              <git common dir>/flow-factory-path names another folder
  global_lock(paths, timeout) / job_lock(paths, n, timeout)
                                              context managers; Refused("lock_timeout lock=<global|issue-N>")
                                              at the timeout, Refused("lock_order") for the global lock
                                              while this process holds a job lock
  read_job(paths, n) -> dict, Unreadable or None (no job folder, or a folder with neither job.json
                                              nor events.jsonl)
  write_job(paths, job), append_event(paths, n, line)   only while this process holds job n's lock
  store_pending(paths, n, event, args, channel, caller, facts) -> file name
  pending_events(paths, n) -> [(name, dict or Unreadable)], oldest first; drop_pending(paths, n, name)
  read_state(paths), write_state(paths, state)          write only while this process holds the global lock
  jobs(paths) -> [(n, dict or Unreadable)], by issue number
  setting(key, default=None)                  one cascade-resolve.sh call per key and default, cached
  charge_run, launch_limit, turn_allowance, dearest_turn, usd_arg, stage_budget_line

Every amount this module returns is a Decimal. Values written to job.json and
events.jsonl may hold Decimals: they are written as JSON numbers.

Lock order: the global lock (F/.lock) is always taken before a job lock
(J/.lock), never while a job lock is held. job.json's own lock
(job.json.lock) is taken only by write_json_file, under the job lock, so it
never waits; events.jsonl is appended through append_jsonl, which locks
events.jsonl.lock, not the job lock, so a write under the job lock cannot
wait on itself.
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

import collections
import contextlib
import json
import re
import subprocess
import time
from datetime import UTC, datetime
from decimal import ROUND_DOWN, ROUND_UP, Decimal

_BIN_DIR = os.path.dirname(os.path.realpath(__file__))
if _BIN_DIR not in sys.path:
    sys.path.append(_BIN_DIR)

# When bin/_flow_factory.py runs as a script it is __main__, and its
# __main__ block makes `_flow_factory` name that same module, so Refused here
# is the class main() catches.
import _flow_factory as ff
from _flow_factory import Refused
import _flow_factory_schema as schema
from _journal_atomic import (JournalAtomicError, TargetExists, _atomic_write, _read_with_no_follow,
                             acquire_lock, append_jsonl, ensure_repo_dir, write_json_file)

LOCK_TIMEOUT = 10
JOB_SCHEMA = os.path.join(ff.PLUGIN_ROOT, "schemas", "v1", "factory-job.schema.json")
DIRECTIVE_SCHEMA = os.path.join(ff.PLUGIN_ROOT, "schemas", "v1", "factory-directive.schema.json")
JOB_FOLDER = re.compile(r"^issue-([1-9][0-9]*)$")
EVENT_NAME = re.compile(r"^[a-z][a-z0-9_]*$")
PENDING_NAME = re.compile(r"^[0-9]{20}-[a-z][a-z0-9_]*\.json$")
CENT = Decimal("0.01")
MIN_ALLOWANCE = Decimal("0.50")
# The runs a stage may make: each failed run adds 1 to attempt, rows 39,
# 39d, 39l and 39ld relaunch while attempt < 2, and rows 43a and 43l park a
# failure at attempt 2 (amendments.md A.10).
RUNS_PER_STAGE = 3

Paths = collections.namedtuple("Paths", "main fdir plugin")
Unreadable = collections.namedtuple("Unreadable", "folder reason")

# The job locks this process holds (issue numbers), and how many global
# locks: the lock order and the writers' checks read them.
_held_jobs = set()
_held_global = [0]
_settings_cache = {}


def _refuse_dir(e):
    return Refused(f"factory_dir_refused {e.summary}")


def resolve(cwd=None, create=True):
    """Paths(main checkout, F, plugin root), with the process changed into
    the main checkout, as p0 factory_dir. F is created (with F/.gitignore)
    only when create is true, so a refusal or a read-only check leaves no
    new factory folder."""
    main = ff.main_checkout(cwd)
    rel = ff.factory_rel(main)
    os.chdir(main)
    if create:
        try:
            ensure_repo_dir(rel, create=True)
            ignore = os.path.join(rel, ".gitignore")
            if not os.path.isfile(ignore):
                _atomic_write(ignore, "*\n")
        except JournalAtomicError as e:
            raise _refuse_dir(e)
    return Paths(main, os.path.join(main, rel), ff.PLUGIN_ROOT)


def factory_path_check(paths):
    """The factory_path_changed refusal line when the pointer
    <git common dir>/flow-factory-path exists and names a folder other than
    F; else None. A pointer that exists but cannot be read counts as naming
    another folder (recorded=unreadable)."""
    try:
        common = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                capture_output=True, text=True, check=True, cwd=paths.main,
                                timeout=30).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        raise Refused("not_in_repository")
    pointer = os.path.join(common, "flow-factory-path")
    if not os.path.lexists(pointer):
        return None
    try:
        recorded = _read_with_no_follow(pointer).strip()
    except (JournalAtomicError, UnicodeDecodeError):
        recorded = "unreadable"
    if recorded and os.path.realpath(recorded) == os.path.realpath(paths.fdir):
        return None
    return f"FACTORY_REFUSED=factory_path_changed recorded={recorded or 'unreadable'} current={paths.fdir}"


def _rel(paths, path):
    return os.path.relpath(path, paths.main)


def _ensure(paths, path):
    """Create a directory under F with the repository directory rule (no
    symlink, nothing but directories below the main checkout)."""
    try:
        ensure_repo_dir(_rel(paths, path), create=True)
    except JournalAtomicError as e:
        raise _refuse_dir(e)


def _check_dir(paths, path):
    """The same rule without creating anything."""
    try:
        ensure_repo_dir(_rel(paths, path))
    except JournalAtomicError as e:
        raise _refuse_dir(e)


def _issue(n):
    if isinstance(n, bool) or not isinstance(n, int) or n < 1:
        raise Refused(f"job_unknown job={n}")
    return n


def job_dir(paths, n):
    return os.path.join(paths.fdir, "jobs", f"issue-{_issue(n)}")


def directive_path(paths, n, did):
    """J/directives/<did>.json."""
    return os.path.join(job_dir(paths, n), "directives", did + ".json")


def lease_path(paths, n, did):
    """J/directives/<did>.lease.json."""
    return os.path.join(job_dir(paths, n), "directives", did + ".lease.json")


def report_path(paths, n, did):
    """J/directives/<did>.pending-report.jsonl (the shell report's lines)."""
    return os.path.join(job_dir(paths, n), "directives", did + ".pending-report.jsonl")


def results_dir(paths, n):
    """J/results."""
    return os.path.join(job_dir(paths, n), "results")


def result_path(paths, n, did):
    """J/results/<did>.json."""
    return os.path.join(results_dir(paths, n), did + ".json")


def epoch(text):
    """Seconds since the epoch of a UTC text as utc_now writes it
    (2026-11-16T00:00:00Z), with or without fractions of a second; None for
    anything else."""
    if not isinstance(text, str):
        return None
    for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S.%fZ"):
        try:
            return datetime.strptime(text, fmt).replace(tzinfo=UTC).timestamp()
        except ValueError:
            continue
    return None


def _acquire(path, timeout, name):
    try:
        return acquire_lock(path, timeout=timeout)
    except JournalAtomicError as e:
        if str(e).startswith("timed out after"):
            raise Refused(f"lock_timeout lock={name}")
        raise Refused(f"lock_unusable lock={name} {e.summary}")


@contextlib.contextmanager
def global_lock(paths, timeout=LOCK_TIMEOUT):
    """F/.lock, held for the with block. Refused("lock_order") while this
    process holds a job lock."""
    if _held_jobs:
        raise Refused("lock_order")
    _ensure(paths, paths.fdir)
    fd = _acquire(os.path.join(paths.fdir, ".lock"), timeout, "global")
    _held_global[0] += 1
    try:
        yield
    finally:
        _held_global[0] -= 1
        os.close(fd)


@contextlib.contextmanager
def job_lock(paths, n, timeout=LOCK_TIMEOUT):
    """J/.lock of issue n, held for the with block. A second hold of the same
    job's lock in this process is refused at once (flock locks per open file,
    so it would wait on itself until the timeout)."""
    jdir = job_dir(paths, n)
    if n in _held_jobs:
        raise Refused(f"lock_reentered lock=issue-{n}")
    _ensure(paths, jdir)
    fd = _acquire(os.path.join(jdir, ".lock"), timeout, f"issue-{n}")
    _held_jobs.add(n)
    try:
        yield
    finally:
        _held_jobs.discard(n)
        os.close(fd)


def _need_job_lock(n):
    if n not in _held_jobs:
        raise Refused(f"lock_not_held lock=issue-{n}")


def _jsonable(value):
    """value with every Decimal made the int or float JSON keeps."""
    if isinstance(value, Decimal):
        return ff.as_number(value)
    if isinstance(value, dict):
        return {k: _jsonable(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_jsonable(v) for v in value]
    return value


def _first_error_path(errors):
    return errors[0].split(": ", 1)[0]


def read_job(paths, n):
    """Job n's job.json, validated against the job schema: the dict, an
    Unreadable(folder, reason) with reason invalid_json, schema: <path of
    the first error>, unreadable (a symlink, not a regular file, or a read
    error) or missing (no job.json beside an event log); or None when there
    is no such job (no folder, or a folder with neither file)."""
    jdir = job_dir(paths, n)
    folder = os.path.basename(jdir)
    _check_dir(paths, os.path.dirname(jdir))
    if not os.path.isdir(jdir) or os.path.islink(jdir):
        if os.path.islink(jdir):
            return Unreadable(folder, "unreadable")
        return None
    path = os.path.join(jdir, "job.json")
    if not os.path.lexists(path):
        return Unreadable(folder, "missing") if os.path.lexists(os.path.join(jdir, "events.jsonl")) else None
    try:
        text = _read_with_no_follow(path)
    except (JournalAtomicError, UnicodeDecodeError):
        return Unreadable(folder, "unreadable")
    try:
        job = json.loads(text)
    except ValueError:
        return Unreadable(folder, "invalid_json")
    errors = schema.validate(job, JOB_SCHEMA)
    if errors:
        return Unreadable(folder, "schema: " + _first_error_path(errors))
    return job


def write_job(paths, job):
    """Replace job.json of the job's issue, under J/job.json.lock, after
    validating it. Only while this process holds that job's lock."""
    n = job.get("issue") if isinstance(job, dict) else None
    _issue(n)
    _need_job_lock(n)
    data = _jsonable(job)
    errors = schema.validate(data, JOB_SCHEMA)
    if errors:
        raise Refused(f"job_invalid {errors[0]}")
    jdir = job_dir(paths, n)
    _ensure(paths, jdir)
    try:
        write_json_file(os.path.join(jdir, "job.json"), os.path.join(jdir, "job.json.lock"), data)
    except JournalAtomicError as e:
        raise Refused(f"job_unwritable job=issue-{n} {e.summary}")


def append_event(paths, n, line):
    """Append one line to J/events.jsonl through append_jsonl. The line needs
    type and job; time defaults to now and pass to null. Only while this
    process holds job n's lock."""
    _need_job_lock(_issue(n))
    if not isinstance(line, dict) or not isinstance(line.get("type"), str) or not isinstance(line.get("job"), str):
        raise Refused("event_invalid (needs type and job)")
    data = dict(_jsonable(line))
    data.setdefault("time", ff.utc_now())
    data.setdefault("pass", None)
    jdir = job_dir(paths, n)
    _ensure(paths, jdir)
    try:
        append_jsonl(os.path.join(jdir, "events.jsonl"), data, lock_timeout=LOCK_TIMEOUT)
    except JournalAtomicError as e:
        raise Refused(f"events_unwritable job=issue-{n} {e.summary}")


def store_pending(paths, n, event, args, channel, caller, facts):
    """Write J/pending/<time_ns, 20 digits>-<event>.json, validated against
    the pending_event shape; return its file name. Never replaces a file."""
    if not isinstance(event, str) or not EVENT_NAME.match(event):
        raise Refused(f"event_invalid {event!r}")
    record = _jsonable({"event": event, "args": args, "channel": channel, "caller": caller, "facts": facts,
                        "raised_at": ff.utc_now()})
    errors = schema.validate(record, DIRECTIVE_SCHEMA, "pending_event")
    if errors:
        raise Refused(f"pending_invalid {errors[0]}")
    pdir = os.path.join(job_dir(paths, n), "pending")
    _ensure(paths, pdir)
    while True:
        name = f"{time.time_ns():020d}-{event}.json"
        try:
            _atomic_write(os.path.join(pdir, name), json.dumps(record, sort_keys=True, indent=2) + "\n",
                          exclusive=True)
            return name
        except TargetExists:
            continue
        except JournalAtomicError as e:
            raise Refused(f"pending_unwritable job=issue-{n} {e.summary}")


def pending_events(paths, n):
    """[(file name, record or Unreadable)] of J/pending, oldest first. A file
    whose name is not <20 digits>-<event>.json is not listed."""
    pdir = os.path.join(job_dir(paths, n), "pending")
    _check_dir(paths, pdir)
    if not os.path.isdir(pdir):
        return []
    out = []
    for name in sorted(os.listdir(pdir)):
        if not PENDING_NAME.match(name):
            continue
        try:
            record = json.loads(_read_with_no_follow(os.path.join(pdir, name)))
        except (JournalAtomicError, UnicodeDecodeError):
            out.append((name, Unreadable(name, "unreadable")))
            continue
        except ValueError:
            out.append((name, Unreadable(name, "invalid_json")))
            continue
        errors = schema.validate(record, DIRECTIVE_SCHEMA, "pending_event")
        out.append((name, Unreadable(name, "schema: " + _first_error_path(errors)) if errors else record))
    return out


def drop_pending(paths, n, name):
    """Remove one pending file by its name; a name already gone is fine."""
    if not isinstance(name, str) or not PENDING_NAME.match(name):
        raise Refused(f"pending_name_invalid {name!r}")
    pdir = os.path.join(job_dir(paths, n), "pending")
    _check_dir(paths, pdir)
    try:
        os.unlink(os.path.join(pdir, name))
    except FileNotFoundError:
        pass
    except OSError as e:
        raise Refused(f"pending_unwritable job=issue-{n} {e.strerror or e}")


def _new_state():
    return {"apiVersion": "flow.synapti.ai/v1", "kind": "FlowFactoryState", "last_sync_at": None,
            "env_recheck_at": None, "env_failed_check": None, "paused_until": None, "pass_seq": 0}


def read_state(paths):
    """F/state.json, or a new state when there is none. One that exists but
    cannot be read is refused (state_unreadable), never replaced, so a pause
    it records is not lost."""
    _check_dir(paths, paths.fdir)
    path = os.path.join(paths.fdir, "state.json")
    try:
        text = _read_with_no_follow(path)
    except (JournalAtomicError, UnicodeDecodeError):
        raise Refused("state_unreadable")
    if not text:
        return _new_state()
    try:
        state = json.loads(text)
    except ValueError:
        raise Refused("state_unreadable")
    if not isinstance(state, dict) or state.get("kind") != "FlowFactoryState":
        raise Refused("state_unreadable")
    return state


def write_state(paths, state):
    """Replace F/state.json. Only while this process holds the global lock."""
    if not _held_global[0]:
        raise Refused("lock_not_held lock=global")
    _ensure(paths, paths.fdir)
    try:
        write_json_file(os.path.join(paths.fdir, "state.json"), os.path.join(paths.fdir, "state.json.lock"),
                        _jsonable(state))
    except JournalAtomicError as e:
        raise Refused(f"state_unwritable {e.summary}")


def jobs(paths):
    """[(n, job dict or Unreadable)] for every folder F/jobs/issue-<n>, by n.
    A folder with neither job.json nor events.jsonl is not a job yet and is
    left out."""
    jroot = os.path.join(paths.fdir, "jobs")
    _check_dir(paths, jroot)
    if not os.path.isdir(jroot):
        return []
    found = []
    for name in os.listdir(jroot):
        m = JOB_FOLDER.match(name)
        if m:
            found.append(int(m.group(1)))
    out = []
    for n in sorted(found):
        rec = read_job(paths, n)
        if rec is not None:
            out.append((n, rec))
    return out


def setting(key, default=None):
    """The value of one settings key (dotted, e.g. flow.factory.leaseSeconds)
    from the user's settings, else the plugin's own settings.json, else
    default; read with cascade-resolve.sh --no-repo-settings, so no file in
    the repository can set it and the answer does not depend on the working
    directory. JSON values (numbers as int or float); None when nothing gives
    one. Cached per key and default for the life of the process."""
    if not isinstance(key, str) or not re.match(r"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)*$", key):
        raise ValueError(f"setting key {key!r}")
    cache_key = (key, json.dumps(default, sort_keys=True))
    if cache_key in _settings_cache:
        return _settings_cache[cache_key]
    cmd = [os.path.join(ff.BIN_DIR, "cascade-resolve.sh"), "--no-repo-settings", "--compact"]
    if default is not None:
        cmd += ["--default", json.dumps(default)]
    cmd.append("." + key)
    env = dict(os.environ, CLAUDE_PLUGIN_ROOT=ff.PLUGIN_ROOT)
    value = default
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=30, env=env, stdin=subprocess.DEVNULL)
        if p.stderr:
            sys.stderr.write(p.stderr)
        out = p.stdout.strip()
        if p.returncode == 0 and out:
            value = json.loads(out)
    except (OSError, subprocess.SubprocessError, ValueError):
        value = default
    _settings_cache[cache_key] = value
    return value


def usd(value):
    """A dollar amount as a Decimal (through its text, so 4.4 is 4.4, not
    4.4000000000000003552713678800500929355621337890625); None stays None."""
    if value is None or isinstance(value, Decimal):
        return value
    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        raise ValueError(f"not an amount: {value!r}")
    return Decimal(str(value))


def charge_run(result_event, kind, previous_session_total, limit_usd, allowance_usd):
    """What one run is charged: {"charged_usd", "basis", "total_cost_usd",
    "since_last_usd"}, every amount a Decimal or None.

    kind is the directive's start_mode, fresh or resume. basis is
      since_last        the sum of costUSD over every model in the result's
                        model_usage_since_last_result (every model gives one)
      session_increase  a resumed run without that sum: total_cost_usd less
                        previous_session_total (0 when none), never below 0
      first_total       a fresh run without that sum: total_cost_usd
      limit_plus_turn   no result event, or one with no cost at all:
                        limit_usd + allowance_usd
    A resumed run's total_cost_usd is the whole session's, so it is never
    charged as such (plan R10)."""
    if kind not in ("fresh", "resume"):
        raise ValueError(f"charge_run kind {kind!r}")
    if isinstance(result_event, dict):
        _, total, since = ff.run_costs(result_event)
        total = usd(total)
        if since is not None:
            return {"charged_usd": since, "basis": "since_last", "total_cost_usd": total, "since_last_usd": since}
        if total is not None:
            if kind == "resume":
                charged = max(total - (usd(previous_session_total) or Decimal(0)), Decimal(0))
                return {"charged_usd": charged, "basis": "session_increase", "total_cost_usd": total,
                        "since_last_usd": None}
            return {"charged_usd": total, "basis": "first_total", "total_cost_usd": total, "since_last_usd": None}
    return {"charged_usd": usd(limit_usd) + usd(allowance_usd), "basis": "limit_plus_turn",
            "total_cost_usd": None, "since_last_usd": None}


def launch_limit(stage_budget_usd, stage_spent_usd, allowance_usd):
    """The --max-budget-usd of the stage's next run, or None when there is
    no room for one (stage_budget_exhausted): min(a third of the budget
    rounded down to the cent, budget - spent) - allowance, rounded down to
    the cent, and None when that is 0 or less (amendments.md A.10)."""
    budget, spent, allowance = usd(stage_budget_usd), usd(stage_spent_usd), usd(allowance_usd)
    third = (budget / RUNS_PER_STAGE).quantize(CENT, rounding=ROUND_DOWN)
    limit = (min(third, budget - spent) - allowance).quantize(CENT, rounding=ROUND_DOWN)
    return limit if limit > 0 else None


def stage_budget_line(stage, stage_budget_usd, stage_spent_usd, allowance_usd):
    """The stage_budget_exhausted refusal line: remaining is the most one run
    may use before the allowance, needed the allowance, both to the cent."""
    budget, spent = usd(stage_budget_usd), usd(stage_spent_usd)
    third = (budget / RUNS_PER_STAGE).quantize(CENT, rounding=ROUND_DOWN)
    remaining = min(third, budget - spent).quantize(CENT, rounding=ROUND_DOWN)
    needed = usd(allowance_usd).quantize(CENT)
    return f"FACTORY_REFUSED=stage_budget_exhausted stage={stage} remaining={remaining} needed={needed}"


def worker_budget_paused(key, stage, budget, job):
    """The PAUSED status line when a worker launch of stage would only be
    refused for its budget, or None: stage_budget_unset when budget (the
    stage's maxBudgetUsd setting) is missing or not positive, which launch
    refuses; stage_budget_exhausted when launch_limit leaves no room. The
    one rule next's worker_precheck and status both print."""
    if isinstance(budget, bool) or not isinstance(budget, (int, float)) or budget <= 0:
        return (f"PAUSED stage_budget_unset job={key} stage={stage} next: set "
                f"flow.factory.worker.stages.{stage}.maxBudgetUsd to a positive amount")
    spent = (job.get("cost") or {}).get("stage_usd", {}).get(stage, 0)
    if launch_limit(budget, spent, turn_allowance(job)) is None:
        return (f"PAUSED stage_budget_exhausted job={key} stage={stage} next: raise "
                f"flow.factory.worker.stages.{stage}.maxBudgetUsd or cancel the job")
    return None


def usd_arg(limit):
    """A limit as the --max-budget-usd argument: 0.50 -> 0.5, 6.16 -> 6.16."""
    return format(usd(limit).normalize(), "f")


def turn_allowance(job):
    """How far one run may pass its limit: twice the dearest single turn seen
    in the job so far, at least $0.50 (amendments.md A.7), rounded up to the
    cent, so the rounding only ever makes the next limit smaller."""
    cost = job.get("cost") if isinstance(job, dict) else None
    dearest = cost.get("dearest_turn_usd") if isinstance(cost, dict) else None
    dearest = usd(dearest) if dearest is not None else Decimal(0)
    return max(MIN_ALLOWANCE, 2 * dearest).quantize(CENT, rounding=ROUND_UP)


def dearest_turn(stream_path):
    """The largest single main-thread assistant turn's cost in a run's
    stream-json, priced from the run's model (the init event's) with
    MODEL_PRICES. Decimal 0 when the stream has no assistant turn (decided
    before the model is looked up); None when a turn has no usage or the
    model has no price."""
    events = ff.read_jsonl(stream_path)
    usages = ff.turn_usages(events)
    if not usages:
        return Decimal(0)
    prices = ff.MODEL_PRICES.get(ff.run_model(events))
    if prices is None:
        return None
    dearest = Decimal(0)
    for u in usages:
        cost = ff.price_usage(u, prices)
        if cost is None:
            return None
        dearest = max(dearest, cost)
    return dearest
