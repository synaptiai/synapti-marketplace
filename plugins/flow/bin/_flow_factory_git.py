"""The factory engine's git: every git command the engine runs in a job clone
or in the main checkout (plan 1a, section 2.15; design
worktrees_ports_bootstrap_auth L43 and L49-L50, execution_model L90-L92).

A worker can run git in its job clone, and git reads its configuration from
the repository it runs in, so a key such as core.fsmonitor, core.hooksPath or
filter.<x>.clean would make the engine's own git run the worker's program.
So every command here:
- is the real git (which_real: never flow's git wrapper), run with
  `-c core.hooksPath=<F>/git/empty-hooks -c core.fsmonitor=false`;
- runs with git_env(F): the caller's environment without FLOW_TIER_DIR,
  FLOW_TIER_CALL and the variables that point git at another repository or
  config, plus GIT_CONFIG_NOSYSTEM=1, GIT_CONFIG_GLOBAL=<F>/git/global.config
  (the engine's own, empty) and GIT_TERMINAL_PROMPT=0;
- when it runs in a job clone, first compares the clone's .git/config, and
  .git/config.worktree when present, with the copy prepare took
  (J/clone-config/). Any difference, a missing copy, or a file that cannot
  be read raises CloneConfigChanged(file, key), and no git command runs in
  the clone. The comparison itself reads each file with `git config --file`
  run outside the clone.

Every git step whose exit status is not 0, or that gets no answer, raises
GitFailed: a failed status is never read as a clean tree, and a failed
snapshot never returns a ref (the caller would then reset the edits away).

API:
  git_env(fdir) -> dict
  git_argv(fdir, args) -> list            the argv git() runs
  real_git() -> path                      raises GitFailed("git_missing")
  git(fdir, args, cwd, clone=None, copy_dir=None, timeout=60, extra_env=None)
      -> (rc, out, err)
  config_changed(clone, copy_dir) -> (file, key) or None
  tree_dirty(fdir, clone, copy_dir, n, goal_id) -> bool
  nested_repositories(fdir, clone) -> [clone-relative path, ...]
  snapshot(fdir, clone, copy_dir, n, reason) -> ref
  reset_and_clean(fdir, clone, copy_dir)
  copy_refs_to_main(fdir, clone, main, n) -> [main ref written, ...]
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

import _flow_factory as p0
from _journal_atomic import JournalAtomicError, _atomic_write

BIN = os.path.dirname(os.path.abspath(__file__))
SNAPSHOT_IDENTITY = {"GIT_AUTHOR_NAME": "flow-factory", "GIT_AUTHOR_EMAIL": "engine@flow-factory.invalid",
                     "GIT_COMMITTER_NAME": "flow-factory", "GIT_COMMITTER_EMAIL": "engine@flow-factory.invalid"}
# Variables dropped from the environment git runs with: flow's tier
# variables (design worktrees L43), and every variable that would point git
# at another repository, index, attribute source or config than the ones its
# working directory and git_env name.
DROPPED_VARS = (("FLOW_TIER_DIR", "FLOW_TIER_CALL", "GIT_ATTR_SOURCE", "GIT_CONFIG", "GIT_CONFIG_SYSTEM",
                 "GIT_CONFIG_GLOBAL") + tuple(p0.GIT_LOCATION_VARS))
NO_COPY = "<no prepare copy>"
# The bounds of nested_repositories' walk of one untracked folder: levels
# (the folder itself is level 1) and directory entries read in all.
NESTED_SCAN_MAX_DEPTH = 20
NESTED_SCAN_MAX_ENTRIES = 10000


class CloneConfigChanged(Exception):
    """The job clone's config differs from the prepare copy (or the copy is
    missing, or a file cannot be read). file is "config" or
    "config.worktree"; key is the lowercased key, or a <...> reason."""

    def __init__(self, file, key):
        super().__init__(f"{file} {key}")
        self.file = file
        self.key = key


class GitFailed(Exception):
    """A git step exited non-zero or got no answer; the message names the
    step and git's first line on stderr."""


class GitTimedOut(GitFailed):
    """A git step stopped at its timeout, or was not started because the
    deadline set by set_deadline had passed: no answer, not a refusal."""


# The wall-clock time (time.time()) after which no bounded git command runs
# and by which every one ends: the next pass sets its own deadline, so the
# read-only commands that compute its facts (tree_dirty, nested_repositories)
# cannot run past nextBudgetSeconds (AC4). Commands that change the clone or
# the main checkout (snapshot, reset, clean, fetch) are never bounded by it:
# cut off part way they would leave a lock file or a half-applied effect.
# None: only each call's timeout.
_DEADLINE = [None]


def set_deadline(at):
    """Bound every later read-only fact command to end by at (time.time()),
    or clear the bound with None."""
    _DEADLINE[0] = at


def real_git():
    """The real git: the first on PATH outside a flow wrapper directory."""
    path = p0.which_real("git")
    if not path:
        raise GitFailed("git_missing: no git on PATH outside a flow wrapper directory")
    return os.path.abspath(path)


def _git_dir(fdir):
    """<F>/git, with an empty global.config and an empty empty-hooks/,
    created when missing (F itself must exist). A
    global.config that is not an empty regular file is written empty again;
    an empty-hooks that holds anything is refused."""
    gdir = os.path.join(fdir, "git")
    hooks = os.path.join(gdir, "empty-hooks")
    conf = os.path.join(gdir, "global.config")
    try:
        # Not ensure_repo_dir: its per-user check runs cascade-resolve.sh,
        # which runs the first git on PATH, flow's wrapper in a session. F
        # was checked when it was made; below it, each name must be a real
        # directory, never a symlink.
        for d in (gdir, hooks):
            if os.path.islink(d) or (os.path.lexists(d) and not os.path.isdir(d)):
                raise GitFailed(f"engine_git_dir: {d} is not a directory")
            if not os.path.lexists(d):
                os.mkdir(d)
        if os.path.islink(conf) or not os.path.isfile(conf) or os.path.getsize(conf) != 0:
            if os.path.islink(conf):
                os.unlink(conf)
            _atomic_write(conf, "")
        if os.listdir(hooks):
            raise GitFailed(f"empty_hooks_not_empty: {hooks} holds files")
    except (JournalAtomicError, OSError) as e:
        raise GitFailed(f"engine_git_dir: {gdir}: {e}")
    return gdir


def git_env(fdir):
    """The environment for every engine git command (see the module doc)."""
    gdir = _git_dir(fdir)
    env = {k: v for k, v in os.environ.items() if k not in DROPPED_VARS}
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.path.join(gdir, "global.config"),
               GIT_TERMINAL_PROMPT="0")
    return env


def git_argv(fdir, args):
    """The argv git() runs: the real git, the two -c flags, then args."""
    hooks = os.path.join(fdir, "git", "empty-hooks")
    return [real_git(), "-c", f"core.hooksPath={hooks}", "-c", "core.fsmonitor=false"] + list(args)


def _read_copy(git, copy_dir):
    """{file: pairs or None} of the prepare copy, or raise
    CloneConfigChanged naming the file that is missing or unreadable."""
    readings = {}
    for name in p0.CLONE_CONFIG_FILES:
        path = os.path.join(copy_dir, name)
        if not os.path.isfile(path) or os.path.islink(path):
            if name == "config":
                raise CloneConfigChanged("config", NO_COPY)
            readings[name] = None
            continue
        pairs, why = p0.read_config_file(git, path, copy_dir)
        if why is not None:
            raise CloneConfigChanged(name, "<prepare copy unreadable>")
        readings[name] = pairs
    return readings


def _compare(clone, copy_dir):
    """None when the clone's config files equal the prepare copy; else
    (file, key) of the first difference. Runs no git in the clone: each file
    is read with `git config --file`, cwd the copy's folder.

    Before the config files: the clone's .git must be a real folder (not a
    symlink or a gitdir file) and must hold no commondir file. Git takes its
    repository config from the folder a commondir file names, so with one
    the clone's own .git/config can stay byte-identical while git reads a
    config the worker wrote (a filter it then runs)."""
    gitdir = os.path.join(clone, ".git")
    if os.path.islink(gitdir) or not os.path.isdir(gitdir):
        return (".git", "<not a directory>")
    if os.path.lexists(os.path.join(gitdir, "commondir")):
        return ("commondir", "<present>")
    git = real_git()
    try:
        before = _read_copy(git, copy_dir)
    except CloneConfigChanged as e:
        return (e.file, e.key)
    after, why = p0.read_clone_config(git, clone, copy_dir)
    if why is not None:
        name = "config.worktree" if "config.worktree" in why else "config"
        return (name, "<unreadable>")
    diffs = p0.config_differences(before, after)
    if not diffs:
        return None
    name, _, key = diffs[0].partition(" ")
    return (name, key)


def config_changed(clone, copy_dir):
    """(file, key) when the clone's config differs from the prepare copy (or
    the copy is missing), else None. The provider of the clone_config_changed
    fact; runs no git in the clone."""
    return _compare(clone, copy_dir)


def _run(argv, cwd, env, timeout, bounded=False):
    """(rc, stdout, stderr) like p0.run_cmd, but decoding bytes that are not
    UTF-8 (a file name a worker chose) without failing. bounded: also end by
    the deadline set_deadline set (read-only fact commands only)."""
    timeout = p0.CALL_TIMEOUT["seconds"] or timeout
    if bounded and _DEADLINE[0] is not None:
        left = _DEADLINE[0] - time.time()
        if left < 1:
            return None, "", f"{p0.TIMED_OUT} 0 s (the deadline had passed; not started)"
        timeout = min(timeout, left)
    try:
        proc = subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, encoding="utf-8", errors="surrogateescape",
                                start_new_session=True)
    except OSError as e:
        return None, "", type(e).__name__
    with proc:
        try:
            out, err = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            p0.kill_group(proc)
            return None, "", f"{p0.TIMED_OUT} {timeout} s"
        except BaseException:
            p0.kill_group(proc)
            raise
    return proc.returncode, out, err


def git(fdir, args, cwd, clone=None, copy_dir=None, timeout=60, extra_env=None, bounded=False):
    """Run the real git with the engine's flags and environment. With clone,
    compare its config with copy_dir first and raise CloneConfigChanged on
    any difference, running nothing. extra_env is added after git_env (the
    snapshot's temporary index and identity)."""
    if clone is not None:
        changed = _compare(clone, copy_dir)
        if changed is not None:
            raise CloneConfigChanged(*changed)
    env = git_env(fdir)
    if clone is not None and os.path.realpath(cwd) == os.path.realpath(clone):
        # Pin the repository to the clone's own .git, so nothing in the clone
        # (a commondir or gitdir file written after the check above) can send
        # git to another folder's config.
        gitdir = os.path.join(os.path.abspath(clone), ".git")
        env.update(GIT_DIR=gitdir, GIT_COMMON_DIR=gitdir, GIT_WORK_TREE=os.path.abspath(clone))
    if extra_env:
        env.update(extra_env)
    return _run(git_argv(fdir, args), cwd, env, timeout, bounded)


def _must(fdir, args, clone, copy_dir, extra_env=None, cwd=None, bounded=False):
    """git() in the clone (or cwd), raising GitFailed unless it exits 0."""
    rc, out, err = git(fdir, args, cwd or clone, clone=clone, copy_dir=copy_dir, extra_env=extra_env,
                       bounded=bounded)
    if rc != 0:
        cls = GitTimedOut if rc is None and str(err).startswith(p0.TIMED_OUT) else GitFailed
        raise cls(f"git {args[0]} {p0.exit_text(rc, p0.first_text(err))}")
    return out


def _main_of(fdir):
    """The main checkout F belongs to: the nearest folder at or above F with
    a .git entry."""
    d = os.path.abspath(fdir)
    while True:
        if os.path.lexists(os.path.join(d, ".git")):
            return d
        up = os.path.dirname(d)
        if up == d:
            raise GitFailed(f"main_checkout_unknown: no .git at or above {fdir}")
        d = up


_DIRS = {}


def _flow_dirs(fdir):
    """(journal dir, runtime dir), each relative to the main checkout's top,
    or None for a journal dir outside it. Resolved once per F, in the main
    checkout, never in the clone. The runtime dir is the one F was made in
    (F is <main>/<runtime dir>/factory); the journal dir is
    bin/journal-dir.sh's answer there."""
    key = os.path.abspath(fdir)
    if key in _DIRS:
        return _DIRS[key]
    main = _main_of(fdir)
    runtime = os.path.relpath(os.path.dirname(key), main)
    # The script runs git itself: flow's wrapper directories are left off
    # its PATH, so that is the real git, never flow's tier wrapper.
    env = {k: v for k, v in os.environ.items() if k not in ("FLOW_TIER_DIR", "FLOW_TIER_CALL")}
    env["PATH"] = os.pathsep.join(d for d in env.get("PATH", "").split(os.pathsep)
                                  if not os.path.isfile(os.path.join(d or ".", "..", "scripts", "lib",
                                                                     "tier-runtime.sh")))
    rc, out, err = _run(["bash", os.path.join(BIN, "journal-dir.sh")], main, env, 30)
    journal = p0.first_text(out or "")
    if rc != 0 or not journal:
        raise GitFailed(f"journal_dir_unresolved: journal-dir.sh {p0.exit_text(rc, p0.first_text(err))}")
    if os.path.isabs(journal):
        rel = os.path.relpath(os.path.realpath(journal), os.path.realpath(main))
        journal = None if rel == ".." or rel.startswith("../") else rel
    else:
        journal = os.path.normpath(journal)
    _DIRS[key] = (journal, runtime)
    return _DIRS[key]


def _glob_escape(path):
    return re.sub(r"([*?\[\\])", r"\\\1", path)


def _excludes(fdir, n, goal_id):
    """The pathspecs tree_dirty leaves out: the prepare ignore list (design
    stages L52-L58: journal and goal lock files, auto-log/, watch/,
    .claude/*.lock, and runs/) and the finalize paths (stages L96: the
    issue's journal and the job's goal file, when the job has a goal id).
    glob magic, so `*` does not
    match `/`, as in an info/exclude line."""
    journal, runtime = _flow_dirs(fdir)
    j = _glob_escape(journal) if journal else None
    r = _glob_escape(runtime)
    pats = [f"{r}/goals/*.lock", f"{r}/watch/**", ".claude/*.lock", f"{r}/runs/**"]
    if goal_id:
        pats.append(f"{r}/goals/{_glob_escape(goal_id)}.goal.yaml")
    if j:
        pats += [f"{j}/*.lock", f"{j}/auto-log/**", f"{j}/issue-{int(n)}.md"]
    return [f":(exclude,glob){p}" for p in pats]


def tree_dirty(fdir, clone, copy_dir, n, goal_id):
    """Whether the clone has any change, untracked files included, other
    than the paths _excludes leaves out."""
    out = _must(fdir, ["--no-optional-locks", "status", "--porcelain=v1", "-z", "--untracked-files=all",
                       "--", "."] + _excludes(fdir, n, goal_id), clone, copy_dir, bounded=True)
    return out != ""


def _copy_dir_of(fdir, clone):
    """J/clone-config of the job whose job.json names clone as its worktree
    (both sides resolved), or None when no job does."""
    want = os.path.realpath(clone)
    jobs = os.path.join(fdir, "jobs")
    try:
        names = sorted(os.listdir(jobs))
    except OSError:
        return None
    for name in names:
        if not re.fullmatch(r"issue-[1-9][0-9]*", name):
            continue
        try:
            with open(os.path.join(jobs, name, "job.json"), encoding="utf-8") as f:
                worktree = json.load(f).get("worktree")
        except (OSError, ValueError, AttributeError):
            continue
        if isinstance(worktree, str) and worktree and os.path.realpath(worktree) == want:
            return os.path.join(jobs, name, "clone-config")
    return None


def _has_git_entry(clone, rel):
    """Whether <clone>/<rel>/.git exists (a folder, a file or a symlink),
    read with lstat: nothing inside the folder is followed or run."""
    try:
        os.lstat(os.path.join(clone, rel, ".git"))
    except (FileNotFoundError, NotADirectoryError):
        return False
    except OSError as e:
        raise GitFailed(f"nested_repository_unreadable: {rel}: {e}")
    return True


def _walk_untracked(clone, rel):
    """The folders below the untracked folder <clone>/<rel> that hold a .git
    entry, as clone-relative paths. Read with os.scandir and lstat only: no
    git runs, no symlink is followed (a symlinked folder is skipped), and the
    walk does not descend into a folder once it has a .git entry. Past
    NESTED_SCAN_MAX_DEPTH levels (rel itself is level 1) or
    NESTED_SCAN_MAX_ENTRIES entries in all, it raises GitFailed, so the
    engine parks rather than misses a repository."""
    found = []
    seen = 0
    stack = [(rel, 1)]
    while stack:
        d, depth = stack.pop()
        if depth > NESTED_SCAN_MAX_DEPTH:
            raise GitFailed(f"nested_repository_scan_limit: {rel}")
        try:
            with os.scandir(os.path.join(clone, d)) as it:
                entries = list(it)
        except OSError as e:
            raise GitFailed(f"nested_repository_unreadable: {d}: {e}")
        seen += len(entries)
        if seen > NESTED_SCAN_MAX_ENTRIES:
            raise GitFailed(f"nested_repository_scan_limit: {rel}")
        for entry in entries:
            try:
                is_dir = entry.is_dir(follow_symlinks=False)
            except OSError as e:
                raise GitFailed(f"nested_repository_unreadable: {d}/{entry.name}: {e}")
            if not is_dir:
                continue
            sub = f"{d}/{entry.name}"
            if _has_git_entry(clone, sub):
                found.append(sub)
            else:
                stack.append((sub, depth + 1))
    return found


def nested_repositories(fdir, clone):
    """The clone's untracked folders that hold a .git entry, as
    clone-relative paths without the trailing slash, sorted (amendment
    A.11). `status --untracked-files=normal` lists an untracked nested
    repository as one folder entry, at the top level or below a tracked
    folder; each such entry is checked for .git with lstat, and no git
    command runs inside it. An untracked folder without its own .git is
    walked (_walk_untracked) for repositories further down, which status
    lists only as that folder. The clone's config is compared with its prepare
    copy (the job whose worktree is clone) first, as for every command in a
    clone: a difference, or no job naming the clone, raises
    CloneConfigChanged. Returns [] and runs no git when clone is None or not
    a directory."""
    if clone is None or not os.path.isdir(clone):
        return []
    copy_dir = _copy_dir_of(fdir, clone)
    if copy_dir is None:
        raise CloneConfigChanged("config", NO_COPY)
    out = _must(fdir, ["--no-optional-locks", "status", "--porcelain=v1", "-z", "--untracked-files=normal"],
                clone, copy_dir, bounded=True)
    fields = out.split("\0")
    found = []
    i = 0
    while i < len(fields):
        entry = fields[i]
        i += 1
        if len(entry) < 4:
            continue
        xy, path = entry[:2], entry[3:]
        if "R" in xy or "C" in xy:
            # A rename or copy is followed by its old path as a field of its
            # own, with no status in front: skip it, so a file name cannot
            # pose as an entry.
            i += 1
            continue
        if xy != "??" or not path.endswith("/"):
            continue
        rel = path.rstrip("/")
        if not _has_git_entry(clone, rel):
            found.extend(_walk_untracked(clone, rel))
            continue
        found.append(rel)
    return sorted(found)


def _next_k(fdir, clone, copy_dir, n):
    out = _must(fdir, ["for-each-ref", "--format=%(refname)", f"refs/flow-factory/issue-{int(n)}/"],
                clone, copy_dir)
    ks = [int(m.group(1)) for m in re.finditer(r"/snapshot-([1-9][0-9]*)$", out, re.MULTILINE)]
    return max(ks, default=0) + 1


def snapshot(fdir, clone, copy_dir, n, reason):
    """Commit the clone's whole working tree, untracked (not ignored) files
    included, with HEAD as parent, to refs/flow-factory/issue-<n>/snapshot-<k>
    (k one more than the largest there), through a temporary index, so the
    clone's own index and HEAD do not change. Returns the ref."""
    k = _next_k(fdir, clone, copy_dir, n)
    ref = f"refs/flow-factory/issue-{int(n)}/snapshot-{k}"
    tmp = tempfile.mkdtemp(prefix="snapshot-", dir=_git_dir(fdir))
    try:
        env = dict(SNAPSHOT_IDENTITY, GIT_INDEX_FILE=os.path.join(tmp, "index"))
        _must(fdir, ["read-tree", "HEAD"], clone, copy_dir, env)
        _must(fdir, ["add", "-A"], clone, copy_dir, env)
        tree = _must(fdir, ["write-tree"], clone, copy_dir, env).strip()
        head = _must(fdir, ["rev-parse", "--verify", "-q", "HEAD^{commit}"], clone, copy_dir, env).strip()
        commit = _must(fdir, ["-c", "user.name=flow-factory", "-c", "user.email=engine@flow-factory.invalid",
                              "commit-tree", "--no-gpg-sign", tree, "-p", head, "-m",
                              f"flow-factory snapshot {k}: {reason}"], clone, copy_dir, env).strip()
        # An empty old value: the ref must not exist yet.
        _must(fdir, ["update-ref", "-m", f"flow-factory snapshot {k}", ref, commit, ""], clone, copy_dir, env)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return ref


def reset_and_clean(fdir, clone, copy_dir):
    """`git reset --hard HEAD`, then `git clean -fd` (ignored files stay):
    design execution_model L92."""
    _must(fdir, ["reset", "-q", "--hard", "HEAD"], clone, copy_dir)
    _must(fdir, ["clean", "-q", "-fd"], clone, copy_dir)


def _job_branch(fdir, n):
    try:
        with open(os.path.join(fdir, "jobs", f"issue-{int(n)}", "job.json"), encoding="utf-8") as f:
            branch = json.load(f).get("branch")
    except (OSError, ValueError):
        return None
    return branch if isinstance(branch, str) and branch else None


def copy_refs_to_main(fdir, clone, main, n):
    """Fetch the clone's job branch (to refs/flow-factory/issue-<n>/branch)
    and its refs/flow-factory/issue-<n>/snapshot-* refs into the main
    checkout, with the clone's config compared with J/clone-config first.
    Does nothing, and runs no git, when clone is None or not a directory.
    Returns the main checkout's refs that the fetch wrote or kept."""
    if clone is None or not os.path.isdir(clone):
        return []
    n = int(n)
    copy_dir = os.path.join(fdir, "jobs", f"issue-{n}", "clone-config")
    ns = f"refs/flow-factory/issue-{n}"
    src = os.path.abspath(clone)
    specs = [f"+{ns}/snapshot-*:{ns}/snapshot-*"]
    branch = _job_branch(fdir, n)
    if branch:
        listed = _must(fdir, ["ls-remote", "--", src, f"refs/heads/{branch}"], clone, copy_dir, cwd=main)
        if any(line.split("\t", 1)[-1] == f"refs/heads/{branch}" for line in listed.splitlines()):
            specs.append(f"+refs/heads/{branch}:{ns}/branch")
    _must(fdir, ["fetch", "-q", "--no-tags", "--no-write-fetch-head", "--no-recurse-submodules", "--no-auto-gc",
                 "--", src] + specs, clone, copy_dir, cwd=main)
    out = _must(fdir, ["for-each-ref", "--format=%(refname)", f"{ns}/"], None, None, cwd=main)
    return sorted(line for line in out.splitlines() if line)
