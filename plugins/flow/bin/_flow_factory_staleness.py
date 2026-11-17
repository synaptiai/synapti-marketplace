"""[flow] Whether the factory's probe record still holds for the installed tools.

The engine reads the probe record (F/probes.json) before it starts workers.
This module compares the record with the tools installed now and gives the
engine its answers (plan 2.12, design phasing L27-L32):

  platform_state(fdir, settings) -> {"stale", "line", "recorded", "current"}
      stale when the installed claude --version differs from the platform
      group's, when any platform entry (P1, P2, P4, P5, P10, P16) or one of
      its parts was not recorded under it, or when flow.factory.worker.model
      is set and differs from the recorded model
  resume_allowed(record) -> bool
      P5's session parts (session_id, kill, turn_limit, budget_limit,
      no_block_rerun) are all go and P5 was recorded under its group's claude
  environment_due(state, settings, now) -> bool
      state.json's env_recheck_at is older than syncIntervalSeconds
  environment_recheck(fdir, deadline) -> {"ok", "check", "recorded"}
      the automatic environment re-run: no model call, no GitHub call
  launch_gate(fdir, kind, settings) -> "PROBES_STALE=platform",
      "PROBES_STALE=environment" or None
  status_lines(fdir, settings) -> [the platform, interactive, environment
      and GitHub-write status lines of plan 2.6 that hold now]

Every settings argument is a reader with the signature of
_flow_factory_jobs.setting(key, default=None).
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

import calendar
import json
import re
import shutil
import subprocess
import tempfile
import time

_BIN_DIR = os.path.dirname(os.path.realpath(__file__))
if _BIN_DIR not in sys.path:
    sys.path.append(_BIN_DIR)

import _flow_factory as ff
from _flow_factory import Refused
import _flow_factory_jobs as jobs

RESUME_PARTS = ("session_id", "kill", "turn_limit", "budget_limit", "no_block_rerun")
LAUNCH_KINDS_PLATFORM = ("worker", "judge")
SYNC_INTERVAL_KEY = "flow.factory.syncIntervalSeconds"
WORKER_MODEL_KEY = "flow.factory.worker.model"
VERSION_TIMEOUT = 30
UNREADABLE = "unreadable"
ENV_NEXT = "next: flow-factory.sh probe --environment (from a terminal when check=signing)"

# claude --version and gh --version, read once per process for the status
# answers (plan T10 step 1). environment_recheck reads gh and git afresh.
_versions = {}


def first_version_line(program, timeout=VERSION_TIMEOUT):
    """The first line of `<program> --version` that is not blank, stripped as
    phase 0's tool_versions strips it, or None when the program is missing,
    fails, or prints nothing in time."""
    if not program:
        return None
    try:
        out = subprocess.run([program, "--version"], capture_output=True, text=True, timeout=timeout,
                             stdin=subprocess.DEVNULL).stdout
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    return next((ln.strip() for ln in out.splitlines() if ln.strip()), None)


def _cached(name, find):
    if name not in _versions:
        _versions[name] = first_version_line(find(name))
    return _versions[name]


def installed_claude():
    """The installed claude's version line (claude found with shutil.which on
    the engine's PATH), or None."""
    return _cached("claude", shutil.which)


def installed_gh():
    return _cached("gh", ff.which_real)


def _record(fdir):
    return ff.read_record(os.path.join(fdir, "probes.json"))


def _keyed(record, group):
    groups = record.get("groups") if isinstance(record.get("groups"), dict) else {}
    g = groups.get(group) if isinstance(groups.get(group), dict) else {}
    return g.get("keyed_on") if isinstance(g.get("keyed_on"), dict) else None


def _probes(record):
    return record.get("probes") if isinstance(record.get("probes"), dict) else {}


def _stamp_version(keyed):
    return keyed.get("claude_version") if isinstance(keyed, dict) else None


def _first_stale_version(probes, current):
    """The claude version the first platform entry not recorded under current
    carries, in probe-id order: the entry's own when it differs, else that of
    its first part (by name) that differs or has none. "none" when the entry,
    or the part, carries no version."""
    for pid in ff.PLATFORM_PROBES:
        entry = probes.get(pid)
        if ff.recorded_under(pid, entry, {"claude_version": current}):
            continue
        if not isinstance(entry, dict):
            return "none"
        own = _stamp_version(entry.get("keyed_on"))
        if own != current:
            return own or "none"
        parts = entry.get("parts") if isinstance(entry.get("parts"), dict) else {}
        for _, p in sorted(parts.items()):
            v = _stamp_version(p.get("keyed_on")) if isinstance(p, dict) else None
            if v != current:
                return v or "none"
        return "none"
    return None


def platform_state(fdir, settings):
    """{"stale", "line", "recorded", "current"} for the platform group.

    recorded is the group's claude version when it differs from current, else
    the version the first stale entry or part carries (probe-id order), else
    the group's. line is the version PAUSED line when the version is stale,
    else the model PAUSED line when worker.model differs from the recorded
    model, else None."""
    record = _record(fdir)
    keyed = _keyed(record, "platform") or {}
    group_v = keyed.get("claude_version")
    current = installed_claude() or UNREADABLE
    recorded = group_v or "none"
    version_stale = group_v != current
    if not version_stale:
        entry_v = _first_stale_version(_probes(record), current)
        if entry_v is not None:
            version_stale, recorded = True, entry_v
    line = None
    if version_stale:
        line = (f"PAUSED probes_stale=platform recorded={recorded} current={current} "
                "next: flow-factory.sh probe --platform")
    else:
        wanted = settings(WORKER_MODEL_KEY)
        recorded_model = keyed.get(ff.MODEL_KEY)
        if isinstance(wanted, str) and wanted and wanted != recorded_model:
            line = (f"PAUSED probes_stale=platform recorded_model={recorded_model or 'none'} worker_model={wanted} "
                    f"next: flow-factory.sh probe --platform --model {wanted}")
    return {"stale": line is not None, "line": line, "recorded": recorded, "current": current}


def resume_allowed(record):
    """Whether a worker may be resumed: P5's five session parts are go and P5,
    with each part, was recorded under its group's claude version (amendment
    A.2). P5's own result, which cost_scope also decides, is not read."""
    record = record if isinstance(record, dict) else {}
    p5 = _probes(record).get("P5")
    if not isinstance(p5, dict) or not isinstance(p5.get("parts"), dict):
        return False
    parts = p5["parts"]
    if not all(isinstance(parts.get(n), dict) and parts[n].get("result") == "go" for n in RESUME_PARTS):
        return False
    group_v = _stamp_version(_keyed(record, "platform"))
    return bool(group_v) and ff.recorded_under("P5", p5, {"claude_version": group_v})


def _epoch(text):
    """A UTC time written as utc_now writes it, as seconds since the epoch, or
    None."""
    if not isinstance(text, str):
        return None
    try:
        return calendar.timegm(time.strptime(text, "%Y-%m-%dT%H:%M:%SZ"))
    except ValueError:
        return None


def environment_due(state, settings, now):
    """Whether the environment re-run is due: state.json's env_recheck_at is
    missing, unreadable, or at least syncIntervalSeconds before now (seconds
    since the epoch)."""
    interval = settings(SYNC_INTERVAL_KEY, 60)
    if isinstance(interval, bool) or not isinstance(interval, (int, float)) or interval < 0:
        interval = 60
    last = _epoch((state or {}).get("env_recheck_at"))
    return last is None or now - last >= interval


def _left(deadline):
    return deadline - time.time()


def _interpreter_check(record, keyed, deadline):
    """None when the recorded interpreter's realpath and version are the ones
    the environment group recorded, else "interpreter"."""
    named, want, want_v = record.get("interpreter"), keyed.get("interpreter"), keyed.get("interpreter_version")
    if not (isinstance(named, str) and named and isinstance(want, str) and want and isinstance(want_v, str)):
        return "interpreter"
    try:
        named, want = ff.expand_home(named), ff.expand_home(want)
    except Refused:
        return "interpreter"
    if os.path.realpath(named) != os.path.realpath(want):
        return "interpreter"
    try:
        out = subprocess.run([named, "-E", "-c", "import platform; print(platform.python_version())"],
                             capture_output=True, text=True, stdin=subprocess.DEVNULL,
                             timeout=max(1, min(10, _left(deadline) - 2))).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return "interpreter"
    return None if out == want_v else "interpreter"


def _signing_check(fdir, deadline):
    """None when phase 0's signing check is go here (signing not set up, or a
    signed commit made with no terminal and no SSH agent), else "signing".
    Every git call it makes is held to max(1, min(10, left - 2)) seconds
    through CALL_TIMEOUT, which is restored afterwards."""
    git = ff.which_real("git")
    if not git:
        return "signing"
    try:
        main_top = ff.main_checkout(cwd=fdir)
    except Refused:
        return "signing"
    env = ff.without_git_location(dict(os.environ))
    env["GIT_TERMINAL_PROMPT"] = "0"
    scratch = os.path.realpath(tempfile.mkdtemp(prefix="flow-factory-recheck-"))
    saved = ff.CALL_TIMEOUT["seconds"]
    ff.CALL_TIMEOUT["seconds"] = max(1, min(10, _left(deadline) - 2))
    try:
        result = ff.signing_part(git, env, scratch, main_top, {})
    except Exception:
        result = {"result": "not_run"}
    finally:
        ff.CALL_TIMEOUT["seconds"] = saved
        shutil.rmtree(scratch, ignore_errors=True)
    return None if result.get("result") == "go" else "signing"


def _record_versions(fdir, changed, deadline):
    """Write the changed gh and git versions into groups.environment.keyed_on
    under F/probes.lock, waiting for it at most min(2, left - 1) seconds.
    Returns "locked" when the lock was not taken, "interpreter" when the
    record could not be written (jsonschema missing, the record invalid or
    unreadable), else None."""
    wait = max(0.0, min(2.0, _left(deadline) - 1))
    try:
        with ff.factory_lock(fdir, timeout=wait):
            path = os.path.join(fdir, "probes.json")
            record = ff.read_record(path)
            keyed = _keyed(record, "environment")
            if keyed is None:
                return "interpreter"
            keyed.update(changed)
            ff.write_record(path, record)
    except Refused as r:
        return "locked" if str(r) == "record_locked" else "interpreter"
    return None


def _write_state(fdir, check, deadline):
    """Write env_recheck_at and env_failed_check into state.json. Under the
    global lock when this process holds it, else taking it for the write
    (waiting at most min(2, left - 1) seconds). Returns whether it wrote."""
    paths = jobs.resolve(cwd=fdir, create=False)

    def write():
        state = jobs.read_state(paths)
        state["env_recheck_at"] = ff.utc_now()
        state["env_failed_check"] = check
        jobs.write_state(paths, state)

    try:
        write()
        return True
    except Refused as r:
        if not str(r).startswith("lock_not_held"):
            raise
    try:
        with jobs.global_lock(paths, timeout=max(0.0, min(2.0, _left(deadline) - 1))):
            write()
    except Refused as r:
        if str(r).startswith("lock_timeout"):
            return False
        raise
    return True


def environment_recheck(fdir, deadline):
    """The automatic environment re-run (design phasing L29), within deadline
    (seconds since the epoch). It makes no model call and no GitHub call.

    In order, it compares the recorded interpreter's realpath and version
    with the environment group's record, runs phase 0's signing check, and
    reads the first line of `gh --version` and `git --version`. The first
    check that fails is the result's check (an unreadable gh or git is
    gh_version or git_version). When every check passes and gh or git moved,
    the new versions are recorded into groups.environment.keyed_on under
    F/probes.lock; with no change neither the lock nor the record is touched.

    It then writes state.json env_recheck_at and env_failed_check, and
    recorded is true. When the probe lock (or the global lock, if this
    process does not already hold it) cannot be had within min(2, left - 1)
    seconds, nothing is written, so the next pass tries again: ok is still
    the checks' answer and recorded is false."""
    try:
        record = _record(fdir)
    except Refused:
        record = {}
    keyed = _keyed(record, "environment") or {}
    check = _interpreter_check(record, keyed, deadline)
    if check is None:
        check = _signing_check(fdir, deadline)
    if check is None:
        timeout = max(1, min(10, _left(deadline) - 1))
        found = {"gh_version": first_version_line(ff.which_real("gh"), timeout),
                 "git_version": first_version_line(ff.which_real("git"), timeout)}
        for key in ("gh_version", "git_version"):
            if not found[key]:
                check = key
                break
        changed = {k: v for k, v in found.items() if keyed.get(k) != v}
        if check is None and changed:
            why = _record_versions(fdir, changed, deadline)
            if why == "locked":
                return {"ok": True, "check": None, "recorded": False}
            check = why
    written = _write_state(fdir, check, deadline)
    return {"ok": check is None, "check": check, "recorded": written}


def _state(fdir):
    """state.json read without a lock, or {} when there is none or it cannot
    be read (the pass that reads it under the lock refuses an unreadable one)."""
    try:
        with open(os.path.join(fdir, "state.json"), encoding="utf-8") as f:
            state = json.load(f)
    except (OSError, ValueError):
        return {}
    return state if isinstance(state, dict) else {}


def launch_gate(fdir, kind, settings):
    """PROBES_STALE=platform for a worker or judge launch while the platform
    group is stale; PROBES_STALE=environment for any launch (worker, judge or
    engine directive) while the last environment re-run failed; else None.
    Engine directives (prepare, gate, sync) do not wait for the platform
    (row 66c, design phasing L27)."""
    if kind in LAUNCH_KINDS_PLATFORM and platform_state(fdir, settings)["stale"]:
        return "PROBES_STALE=platform"
    if _state(fdir).get("env_failed_check"):
        return "PROBES_STALE=environment"
    return None


def _gh_major(line):
    m = re.match(r"gh version (\d+)\.", line or "")
    return m.group(1) if m else None


def status_lines(fdir, settings):
    """The probe status lines that hold now, in plan 2.6's order: the
    platform PAUSED line, the interactive DEGRADED line (the interactive
    group's claude version differs from the installed one, or the group was
    never recorded), the environment PAUSED line (the last re-run failed),
    and the GitHub-write REMINDER (gh's major version differs from the one
    that group recorded)."""
    lines = []
    platform = platform_state(fdir, settings)
    if platform["line"]:
        lines.append(platform["line"])
    record = _record(fdir)
    interactive = _keyed(record, "interactive")
    if interactive is None or interactive.get("claude_version") != (installed_claude() or UNREADABLE):
        lines.append("DEGRADED probes_stale=interactive next: /flow:factory probe")
    failed = _state(fdir).get("env_failed_check")
    if failed:
        lines.append(f"PAUSED probes_failed=environment check={failed} {ENV_NEXT}")
    github = _keyed(record, "github_write")
    if github and github.get("gh_version") and _gh_major(github["gh_version"]) != _gh_major(installed_gh()):
        sandbox = github.get("sandbox") or "<owner/repo>"
        lines.append(f"REMINDER probes_stale=github_write next: flow-factory.sh probe --github-write --sandbox "
                     f"{sandbox} (asks for sandbox approval)")
    return lines
