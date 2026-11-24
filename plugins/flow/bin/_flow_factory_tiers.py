"""The factory engine's tier keys (plan 1b, B7; design github_writes_and_tiers
L48, execution_model L46-L53).

The engine resolves a tier key as the strictest value of four sources: the
project file (.claude/settings.flow.json) as it is on the job's base branch
in the main checkout (refs/remotes/origin/<base>, after the engine's own
fetch), the main checkout's local file (.claude/settings.flow.local.json),
the user file, and the plugin default (tiers.<key> in the plugin's
settings.json). Order: confirm > journal > autonomous. tier-gate's cascade
takes the first source with a value instead; with project=confirm and
local=autonomous the engine still reads confirm.

Fail closed: a base ref that does not resolve, a job with no base, a source
that cannot be read, or a value that is none of the three names counts as
confirm. A source with no file, or with no value for the key, gives none.
The reads of the project file are not bounded by the pass's deadline (as
fetches are not): a read cut off by it would count as confirm and park a job
that has none. Nothing is kept between reads: every resolver reads the four sources again,
so a key changed between two passes is seen by the second (R40). A caller
that needs one read per pass builds one resolver and passes it on.

API:
  VALUES, WRITE_KINDS
  base_ref(job) -> "refs/remotes/origin/<base>" or None
  fetch_base(main, base, fdir=None) -> (ok, reason)
  resolver(main, base_ref, fdir=None) -> Tiers, a callable tiers(key) with
      .base_problem: None, "no_base", "ref_unresolved <ref>" or
      "project_unreadable <reason>" (the caller prints BASE_REF_UNRESOLVED or
      BASE_FETCH_FAILED); .problems: every source that counted as confirm
  resolve(main, base_ref, key, fdir=None) -> "autonomous"|"journal"|"confirm"
  path_keys(state) -> [key]
  confirm_path_keys(main, base_ref, job, tiers=None, fdir=None) -> [key]
  tier_confirm_blocking(main, base_ref, job, tiers=None, fdir=None) -> bool
  intent_key_not_confirm(main, base_ref, job, tiers=None, fdir=None) -> bool
  confirm_writes(writes, job, tiers, fdir=None) -> [key]

main is the main checkout's top; fdir is the factory directory F (default:
<main>/<runtime dir>/factory, which must exist, since the engine's git keeps
its empty config there; confirm_writes, which takes no main, finds the main
checkout from the working directory). Where a function takes tiers, a
callable tiers(key) -> value, it is used in place of a new resolver.
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
import re
import shutil
import subprocess
import tempfile
import time
import unicodedata

import _flow_factory as ff
import _flow_factory_git as fgit

VALUES = ("autonomous", "journal", "confirm")
_RANK = {v: i for i, v in enumerate(VALUES)}
PROJECT_PATH = ".claude/settings.flow.json"

# The keys of the blocking writes left on the path to ready, by state (design
# execution_model L46-L53; T:facts.tier_confirm_blocking). The design lists
# each stage's own writes; a job parks before it spends anything when any
# write still ahead of it is confirm (github_writes_and_tiers L68: with
# tiers.push confirm a job no longer spends its spec and build budget only to
# park at the push), so a state's keys are those of its own stage and every
# later one, each key once at its first use, in the design's stage order:
# prepare, open_pr, review/rework/sync/resolve, ready, approve. push and
# prCreate stay on the path though phase 1e builds those writes.
_FROM_PREPARE = ("issueAssign", "issueUpdate", "push", "prCreate")
_FROM_OPEN_PR = ("push", "prCreate", "issueUpdate")
_FROM_REVIEW = ("push", "issueUpdate")
_FROM_READY = ("issueUpdate",)
PATH_KEYS = {
    "intake": _FROM_PREPARE, "prepare": _FROM_PREPARE,
    "spec": _FROM_OPEN_PR, "build": _FROM_OPEN_PR, "open_pr": _FROM_OPEN_PR,
    "gate": _FROM_REVIEW, "review": _FROM_REVIEW, "rework": _FROM_REVIEW,
    "sync": _FROM_REVIEW, "resolve": _FROM_REVIEW,
    "ready": _FROM_READY, "approve": _FROM_READY,
}

# The write kinds of rules.blocking_write.kinds and their tier keys (plan
# 5.3, design github_writes_and_tiers L58-L64). "PR create or edit" is
# prCreate for a job with no PR and issueUpdate for one with a PR (T:21).
WRITE_KINDS = {
    "assignment": "issueAssign",
    "in-progress label": "issueUpdate",
    "push": "push",
    "PR create or edit": None,
    "review marker": "issueUpdate",
    "resolution marker": "issueUpdate",
    "replies": "issueUpdate",
    "ready mark": "issueUpdate",
    "undo of ready": "issueUpdate",
}

# A branch name the engine fetches and reads: letters, digits, '.', '_',
# '-' and '/', not starting with '-' or '/', with no '..', '//' or '@{', not
# ending in '/' or '.', no part starting with '.', and no part ending in
# '.lock'. A name git would allow beyond this is refused, which reads as
# confirm.
_BRANCH = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9._/-]*$")


# git's refusal when another process holds a ref's lock file.
_LOCK_HELD = re.compile(r"cannot lock ref|\.lock'?: File exists|Unable to create '[^']*\.lock'")


def _branch_ok(base):
    # git refuses a ref with any slash-separated part ending in .lock, not
    # only the last one.
    return (isinstance(base, str) and bool(_BRANCH.match(base)) and ".." not in base and "//" not in base
            and not base.endswith(("/", ".")) and "/." not in base and len(base) <= 200
            and not any(part.endswith(".lock") for part in base.split("/")))


def base_ref(job):
    """refs/remotes/origin/<base> for the job's recorded base branch, or None
    when it has none or the name is not one the engine reads."""
    base = job.get("base") if isinstance(job, dict) else None
    return f"refs/remotes/origin/{base}" if _branch_ok(base) else None


def _fdir(main, fdir):
    return fdir if fdir is not None else os.path.join(main, ff.factory_rel(main))


def fetch_base(main, base, fdir=None):
    """Fetch origin's <base> into refs/remotes/origin/<base> of the main
    checkout with the engine's git (design worker_github_access L10).
    (True, "") or (False, reason); a name that is not a branch name is
    refused with no git run."""
    if not _branch_ok(base):
        return False, f"base_invalid {base!r}"
    args = ["fetch", "-q", "--no-write-fetch-head", "--no-tags", "--no-recurse-submodules", "--no-auto-gc",
            "origin", f"+refs/heads/{base}:refs/remotes/origin/{base}"]
    try:
        F = _fdir(main, fdir)
        rc, _, err = fgit.git(F, args, main)
        if rc != 0 and _LOCK_HELD.search(err or ""):
            # Another fetch holds the ref's lock: try once more after a
            # second (design worker_github_access L10).
            time.sleep(1)
            rc, _, err = fgit.git(F, args, main)
    except (fgit.GitFailed, ff.Refused) as e:
        return False, f"fetch_failed {e}"
    if rc != 0:
        why = ff.first_text(err)
        return False, f"fetch_failed git fetch {ff.exit_text(rc)}" + (f": {why}" if why else "")
    return True, ""


class _Unreadable(Exception):
    pass


def _tiers_of(text, name):
    """The tiers object of a settings file's text: a dict, or {} when the
    file has none; _Unreadable when the text is not a JSON object or its
    tiers is not an object."""
    try:
        doc = json.loads(text)
    except ValueError as e:
        raise _Unreadable(f"{name}: not JSON ({e.msg})")
    if not isinstance(doc, dict):
        raise _Unreadable(f"{name}: not a JSON object")
    tiers = doc.get("tiers")
    if tiers is None:
        return {}
    if not isinstance(tiers, dict):
        raise _Unreadable(f"{name}: tiers is not an object")
    return tiers


def _read_file(path, name):
    """The tiers of the file at path; {} when there is none."""
    if not path or not os.path.lexists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except (OSError, UnicodeDecodeError) as e:
        raise _Unreadable(f"{name}: {type(e).__name__}")
    return _tiers_of(text, name)


def _cascade(main, flag):
    """The stdout of cascade-resolve.sh <flag>, run in the main checkout as
    jobs.setting runs it; _Unreadable when it fails."""
    cmd = [os.path.join(ff.BIN_DIR, "cascade-resolve.sh"), flag]
    env = dict(os.environ, CLAUDE_PLUGIN_ROOT=ff.PLUGIN_ROOT)
    try:
        p = subprocess.run(cmd, cwd=main, capture_output=True, text=True, timeout=30, env=env,
                           stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError) as e:
        raise _Unreadable(f"cascade-resolve.sh {flag}: {type(e).__name__}")
    if p.returncode != 0:
        raise _Unreadable(f"cascade-resolve.sh {flag}: exited {p.returncode}")
    return p.stdout


def _local_path(main):
    out = _cascade(main, "--repo-settings-paths")
    parts = out.split("\0")
    if len(parts) < 2 or not parts[0]:
        raise _Unreadable("cascade-resolve.sh --repo-settings-paths: no local path")
    return parts[0] if os.path.isabs(parts[0]) else os.path.join(main, parts[0])


def _user_path(main):
    out = _cascade(main, "--user-settings-path").strip("\n")
    return out or None


def _folded(name):
    """name as a file system that ignores case and normalisation compares
    it: full Unicode case folding, so the long s (U+017F) reads as s and the
    ligature U+FB02 as fl, as APFS was found to do."""
    return unicodedata.normalize("NFD", unicodedata.normalize("NFD", name).casefold())


def _checkout_paths(F, main, commit, ref):
    """The [mode, id, stage, path] of every path a checkout of commit writes,
    from git read-tree into a temporary index (removed afterwards) and git
    ls-files. A walk of the commit's trees by name could miss what a checkout
    still writes: a top-level entry whose own name is
    '.claude/settings.flow.json', or two '.claude' trees in one tree, which a
    checkout merges (both probed with git 2.55.0, 2026-11-19). A commit
    read-tree refuses ('..' or '.git' as a name) is refused here too. fgit
    runs git with no hooks and no fsmonitor; split and sparse index are off,
    so the index is one plain file in the temporary directory."""
    tmp = tempfile.mkdtemp(prefix="flow-tiers-index-")
    try:
        env = {"GIT_INDEX_FILE": os.path.join(tmp, "index")}
        cfg = ["-c", "core.splitIndex=false", "-c", "index.sparse=false", "-c", "core.sparseCheckout=false"]
        rc, _, err = fgit.git(F, cfg + ["read-tree", commit], main, extra_env=env)
        if rc != 0:
            raise _Unreadable(f"project: git read-tree {ff.exit_text(rc, ff.first_text(err))} at {ref}")
        # ls-files lists only the paths under its working directory, so it
        # runs at the checkout's top, wherever in the checkout main is.
        rc, out, err = fgit.git(F, ["rev-parse", "--show-toplevel"], main)
        top = out.rstrip("\n")
        if rc != 0 or not os.path.isabs(top):
            raise _Unreadable(f"project: git rev-parse --show-toplevel {ff.exit_text(rc, ff.first_text(err))}")
        rc, out, err = fgit.git(F, cfg + ["ls-files", "-s", "-z"], top, extra_env=env)
        if rc != 0:
            raise _Unreadable(f"project: git ls-files {ff.exit_text(rc, ff.first_text(err))}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    entries = []
    for entry in out.split("\0"):
        if not entry:
            continue
        meta, tab, path = entry.partition("\t")
        fields = meta.split(" ")
        if not tab or len(fields) != 3 or not re.fullmatch(r"[0-9a-f]{40,64}", fields[1]):
            raise _Unreadable(f"project: git ls-files printed an entry it should not at {ref}")
        entries.append(fields + [path])
    return entries


def _project_at(main, ref, fdir):
    """The tiers of the project file in commit ref, through the engine's git
    in the main checkout; {} when the commit has no such file. Returns
    (tiers, problem): problem "ref_unresolved <ref>" when ref does not
    resolve to a commit; _Unreadable for anything else that fails."""
    try:
        F = _fdir(main, fdir)
        rc, out, err = fgit.git(F, ["rev-parse", "--verify", "-q", f"{ref}^{{commit}}"], main)
        if rc is None:
            raise _Unreadable(f"project: git rev-parse {ff.exit_text(rc, ff.first_text(err))}")
        commit = out.strip()
        if rc != 0 or not re.fullmatch(r"[0-9a-f]{40,64}", commit):
            return {}, f"ref_unresolved {ref}"
        # The project file is the entry a checkout writes at exactly
        # .claude/settings.flow.json (_checkout_paths), and only a regular
        # file (mode 100644 or 100755) is read: a symbolic link would be read
        # as its target's text, a submodule as no file. Refused instead:
        # - an entry at .claude itself (a symbolic link, file or submodule):
        #   git lists nothing under it, while a checkout can find the file
        #   through a link;
        # - an entry below .claude/settings.flow.json (a directory there);
        # - any other entry whose first two names fold to .claude and
        #   settings.flow.json, or whose only name folds to .claude: a
        #   checkout on a file system that ignores case (macOS by default)
        #   finds it under the expected name. The expected names are ASCII,
        #   so a difference in Unicode normalisation alone cannot match them;
        #   _folded normalises anyway.
        # read-tree of one commit lists each path once, at stage 0: two
        # entries at one path (two '.claude' trees that both hold the file,
        # or the slash-named entry beside a '.claude' tree) leave the one a
        # checkout writes.
        top, name = PROJECT_PATH.split("/")
        found = None
        for mode, oid, _stage, path in _checkout_paths(F, main, commit, ref):
            parts = path.split("/")
            if _folded(parts[0]) != top:
                continue
            if len(parts) == 1:
                if parts[0] == top:
                    raise _Unreadable(f"project: {top} at {ref} is not a directory")
                raise _Unreadable(f"project: an entry at {ref} is named {top} only on a case-insensitive file system")
            if _folded(parts[1]) != name:
                continue
            if parts[0] != top or parts[1] != name:
                raise _Unreadable(f"project: an entry at {ref} is named {PROJECT_PATH} only on a case-insensitive "
                                  "file system")
            if len(parts) > 2:
                raise _Unreadable(f"project: {PROJECT_PATH} at {ref} is not a regular file")
            found = (mode, oid)
        if found is None:
            return {}, None
        mode, oid = found
        if mode not in ("100644", "100755"):
            raise _Unreadable(f"project: {PROJECT_PATH} at {ref} is not a regular file")
        rc, out, err = fgit.git(F, ["cat-file", "blob", oid], main)
        if rc != 0:
            raise _Unreadable(f"project: git cat-file {ff.exit_text(rc, ff.first_text(err))}")
    except (fgit.GitFailed, ff.Refused) as e:
        raise _Unreadable(f"project: {e}")
    return _tiers_of(out, f"{ref}:{PROJECT_PATH}"), None


class Tiers:
    """The four sources, read once when made. Call it with a key."""

    def __init__(self, main, base_ref, fdir=None):
        self.base_problem = None
        self.problems = []
        self.sources = {}
        if base_ref is None:
            self.base_problem = "no_base"
            self.sources["project"] = None
        else:
            try:
                tiers, problem = _project_at(main, base_ref, fdir)
                self.base_problem = problem
                self.sources["project"] = None if problem else tiers
            except _Unreadable as e:
                self.base_problem = f"project_unreadable {e}"
                self.sources["project"] = None
        if self.sources["project"] is None:
            self.problems.append(f"project {self.base_problem}")
        for name, path_of in (("local", _local_path), ("user", _user_path),
                              ("plugin", lambda _m: os.path.join(ff.PLUGIN_ROOT, "settings.json"))):
            try:
                self.sources[name] = _read_file(path_of(main), name)
            except _Unreadable as e:
                self.sources[name] = None
                self.problems.append(str(e))

    def __call__(self, key):
        found = []
        for name in ("project", "local", "user", "plugin"):
            tiers = self.sources[name]
            if tiers is None:
                found.append("confirm")
                continue
            value = tiers.get(key)
            if value is None:
                continue
            found.append(value if isinstance(value, str) and value in _RANK else "confirm")
        if not found:
            return "confirm"
        return max(found, key=_RANK.__getitem__)


def resolver(main, base_ref, fdir=None):
    """A Tiers over the four sources as they are now."""
    return Tiers(main, base_ref, fdir)


def resolve(main, base_ref, key, fdir=None):
    """The strictest value of key over the four sources, read now."""
    return Tiers(main, base_ref, fdir)(key)


def path_keys(state):
    """The tier keys of the blocking writes left on the path to ready from
    state; ValueError for a state with no such path."""
    if state not in PATH_KEYS:
        raise ValueError(f"no tier path for state {state!r}")
    return list(PATH_KEYS[state])


def _job_path_keys(job):
    state = job.get("state")
    if state == "waiting_operator":
        # A parked job resumes into resume_state; rows 41b and 41p read the
        # keys left on that path. Every park row records a resume state that
        # has one (T: records.resume_state of the rows into waiting_operator);
        # a job.json without one, or with another, reads every key any path
        # has, so the park is kept rather than the pass failing on the fact.
        state = job.get("resume_state")
        return list(PATH_KEYS.get(state, _FROM_PREPARE))
    return path_keys(state)


def confirm_path_keys(main, base_ref, job, tiers=None, fdir=None):
    """The keys on the job's path that resolve to confirm, in path order
    (the list row 40b records as pending_keys)."""
    keys = _job_path_keys(job)
    tiers = tiers or Tiers(main, base_ref, fdir)
    return [k for k in keys if tiers(k) == "confirm"]


def tier_confirm_blocking(main, base_ref, job, tiers=None, fdir=None):
    """True exactly when confirm_path_keys is not empty."""
    return bool(confirm_path_keys(main, base_ref, job, tiers, fdir))


def intent_key_not_confirm(main, base_ref, job, tiers=None, fdir=None):
    """True when the job has a pending intent with at least one key and none
    of its keys resolves to confirm; False otherwise, with nothing read when
    there is no pending intent."""
    intent = job.get("pending_intent")
    if not isinstance(intent, dict):
        return False
    keys = intent.get("key")
    if not isinstance(keys, list) or not keys:
        return False
    tiers = tiers or Tiers(main, base_ref, fdir)
    return all(tiers(k) != "confirm" for k in keys)


def _covered(job, fdir):
    """The write kinds the sent outbox item named by job.confirmed_intent
    covers: assign_label the assignment and the in-progress label; label_add
    of labels.inProgress the in-progress label. Nothing when there is no such
    item, it belongs to another job, it cannot be read, no write_recorded
    line names it, or it is not the item its intent_recorded line records
    (an edited kind or argv): sent, kind and argv are read through the
    GitHub writes module's sent_item, never from the editable item alone."""
    iid = job.get("confirmed_intent")
    if not iid or not isinstance(job.get("issue"), int):
        return set()
    if not re.fullmatch(r"issue-[0-9]+-j[0-9]+-[0-9a-z]+-[0-9]+", str(iid)):
        return set()
    try:
        # The default is the main checkout's factory directory, found from
        # the working directory; when it cannot be found nothing is covered.
        if fdir is None:
            fdir = _fdir(ff.main_checkout(), None)
    except ff.Refused:
        return set()
    # Imported here, as jobs is below: no import cycle (the GitHub writes
    # module does not import this one), and only this reader needs it.
    import _flow_factory_github as github
    item = github.sent_item(os.path.join(fdir, "jobs", f"issue-{job['issue']}"), iid, job.get("key"))
    if item is None:
        return set()
    kind = item.get("kind")
    if kind == "assign_label":
        return {"assignment", "in-progress label"}
    if kind == "label_add":
        import _flow_factory_jobs as jobs
        label = jobs.setting("flow.factory.labels.inProgress")
        argv = item.get("argv") if isinstance(item.get("argv"), list) else []
        if isinstance(label, str) and label and any(a == label or (isinstance(a, str) and a.endswith("=" + label))
                                                    for a in argv):
            return {"in-progress label"}
    return set()


def confirm_writes(writes, job, tiers, fdir=None):
    """The keys of the given write kinds that resolve to confirm, each once,
    in the order of first use; the kinds the job's confirmed intent covers
    are left out. ValueError for a kind the map does not hold. fdir None
    reads the confirmed intent from the main checkout's factory directory."""
    for w in writes:
        if w not in WRITE_KINDS:
            raise ValueError(f"no tier key for write kind {w!r}")
    covered = _covered(job, fdir) if writes else set()
    out = []
    for w in writes:
        if w in covered:
            continue
        key = WRITE_KINDS[w] or ("issueUpdate" if job.get("pr") else "prCreate")
        if key not in out and tiers(key) == "confirm":
            out.append(key)
    return out
