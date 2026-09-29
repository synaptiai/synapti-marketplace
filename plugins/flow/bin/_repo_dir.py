"""Directories under the repository, never reached through a symlink.

The rule every flow writer and reader applies to a directory below the
repository: ensure_repo_dir() refuses (or creates) a directory reached through
a symlink, and ensure_inside_repo() also refuses one that is not under the
repository top at all. Per-user state — the user's Claude config directory
and flow's state directory — is never subject to it, whatever the top. The top is the nearest directory at or above the
working directory that holds a .git entry, or the working directory when none
does. bin/_journal_atomic.py re-exports both for its writers;
bin/flow-mkdir.sh is the same rule for command blocks and skills.

This module imports nothing but the standard library, so the check runs where
PyYAML is missing: a reader that cannot import PyYAML can still tell a
symlinked .flow from a real one, and one whose check cannot run at all says
so instead of reporting a refusal.

Errors:
  - RepoDirRefused (a JournalAtomicError): a component is a symlink or not a
    directory, or the path is not in the repository. The directory is refused.
  - JournalAtomicError: the check or the creation could not be done (the
    current directory was removed, a component could not be inspected or
    created). Nothing is known about the directory.
"""

import os
import stat
import sys

# Defense-in-depth for Python <3.11 where PYTHONSAFEPATH is ignored: no module
# is imported from the working directory, which a pull request controls.
sys.path[:] = [p for p in sys.path if p not in ("", ".")]


class JournalAtomicError(RuntimeError):
    """Raised on any atomicity / symlink / parse error.

    Attributes:
      exit_code: 1 for user-input errors, 2 for infrastructure / refusal.
      refuse: when True, the caller should append the canonical
              "refusing to overwrite — fix manually" line to stderr.
              Matches the original journal-record.sh:217-232 behavior.
    """

    def __init__(self, message, exit_code=2, refuse=False):
        super().__init__(message)
        self.exit_code = exit_code
        self.refuse = refuse


class RepoDirRefused(JournalAtomicError):
    """A directory refused by the rule: a component is a symlink or not a
    directory, or the path is not in the repository. Distinct from a check
    that could not be done, which raises JournalAtomicError itself."""


# ---------------------------------------------------------------------------
# Directories under the repository.

def _below_same_dir(raw, anchor):
    """The part of absolute path `raw` below its shortest prefix that is the
    same directory as `anchor`, or None when no prefix is.

    An absolute path can name the working directory through a symlink above
    it — macOS spells /private/var as /var — which a string comparison with
    the physical anchor misses, and the path would then be outside the rule
    while every component below the anchor is still one the repository
    chose. Each prefix is stat()ed, following links, from the shortest up;
    the shortest that is the anchor's directory wins, so a symlink below the
    anchor that points back at it is still a component to walk, not a way
    past it. A prefix that cannot be stat()ed ends the search.
    """
    try:
        anchor_st = os.stat(anchor)
    except OSError:
        return None
    drive, tail = os.path.splitdrive(raw)
    comps = tail.split(os.sep)
    cur = drive + os.sep
    for i, comp in enumerate(comps):
        if comp in ("", "."):
            continue
        cur = os.path.join(cur, comp)
        try:
            st = os.stat(cur)
        except OSError:
            return None
        if os.path.samestat(st, anchor_st):
            return os.sep.join(comps[i + 1:])
    return None


def _repo_top(cwd):
    """The repository top for the physical working directory `cwd`.

    The nearest directory at or above `cwd` that holds a .git entry — a
    directory, or a file in a git worktree or submodule — so a repository
    nested inside another has its own top. `cwd` itself when no directory
    above it has one.
    """
    d = cwd
    while True:
        if os.path.lexists(os.path.join(d, ".git")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return cwd
        d = parent


def _per_user_roots():
    """The user's own directories, as the environment names them: the Claude
    config directory (${CLAUDE_CONFIG_DIR}, and $HOME/.claude, where flow keeps
    per-user state when FLOW_STATE_DIR is unset) and ${FLOW_STATE_DIR}.
    Absolute values only."""
    home = os.environ.get("HOME")
    roots = []
    for root in (os.environ.get("CLAUDE_CONFIG_DIR"),
                 os.path.join(home, ".claude") if home else None,
                 os.environ.get("FLOW_STATE_DIR")):
        if root and os.path.isabs(root):
            roots.append(os.path.normpath(root))
    return roots


def _is_per_user(path_abs, top):
    """True when `path_abs` is per-user state: under one of _per_user_roots(),
    and the repository top is not inside that directory.

    The rule refuses symlinks a repository commits, not ones the user made: a
    home directory kept in git with ~/.claude a symlink to a dotfiles
    directory (as GNU stow makes it) is a repository top whose own ~/.claude
    must still be written. The path is compared as written, with no `..` and
    never through a link, so a repository that commits a symlink into the
    user's config directory does not make its own paths per-user by it. A
    repository that itself lives in the config directory (a plugin
    marketplace clone) keeps the rule for its paths.
    """
    if ".." in path_abs.split(os.sep):
        return False
    p = os.path.normcase(os.path.normpath(path_abs))
    t = os.path.normcase(top)
    for root in _per_user_roots():
        r = os.path.normcase(root)
        if p != r and not p.startswith(r + os.sep):
            continue
        top_inside = False
        for spelled in (root, os.path.realpath(root)):
            s_ = os.path.normcase(spelled)
            if t == s_ or t.startswith(s_ + os.sep):
                top_inside = True
        if not top_inside:
            return True
    return False


def _repo_parts(path):
    """Return (anchor, parts): `path` as components below the repository top.

    The anchor is _repo_top() of the physical working directory. A relative
    `path` is taken from the working directory, as the kernel takes it, and
    its components start at the anchor; the ones between the anchor and the
    working directory are real directories, since the working directory's
    path is physical.

    parts is None when `path` does not end under the anchor — an absolute path
    elsewhere, or a name that climbs out with `..` — or is per-user state
    (_is_per_user), which puts it outside ensure_repo_dir()'s rule. An absolute path that names the anchor through a
    symlink above it is under it (_below_same_dir). parts keeps every `..` as
    written: read without the links, `shared/../x` is `x`, but the kernel
    resolves `shared` first, so it is walked as written.
    """
    cwd = os.getcwd()
    anchor = _repo_top(cwd)
    raw = os.fspath(path)
    if os.path.altsep:
        raw = raw.replace(os.path.altsep, os.sep)
    if _is_per_user(raw if os.path.isabs(raw) else os.path.join(cwd, raw), anchor):
        return anchor, None
    prefix = anchor if anchor.endswith(os.sep) else anchor + os.sep
    if not os.path.isabs(raw) and cwd != anchor:
        raw = os.path.join(os.path.relpath(cwd, anchor), raw)
    if os.path.isabs(raw):
        if os.path.normcase(raw.rstrip(os.sep)) == os.path.normcase(anchor.rstrip(os.sep)):
            return anchor, []
        if os.path.normcase(raw).startswith(os.path.normcase(prefix)):
            raw = raw[len(prefix):]
        else:
            raw = _below_same_dir(raw, anchor)
            if raw is None:
                return anchor, None
    end = os.path.normcase(os.path.normpath(os.path.join(anchor, raw)))
    if end != os.path.normcase(anchor) and not end.startswith(os.path.normcase(prefix)):
        return anchor, None
    return anchor, [p for p in raw.split(os.sep) if p not in ("", ".")]


def ensure_repo_dir(dir_path, create=False):
    """Refuse a directory that is reached through a symlink below the repository top.

    The anchor is the repository top (_repo_top): the nearest directory at or
    above the physical working directory that holds a .git entry, or the
    working directory when none does. Flow writers name their files relative
    to the working directory (`.flow/runs/<id>`, `.decisions`), which is
    usually the top, but a Flow block can run with the working directory in a
    subdirectory, since the Bash tool keeps its working directory between
    calls, and a path that climbs back to the top (`../.decisions`) is then
    still the repository's. What lies above the anchor, such as macOS's
    /var -> /private/var, is how the repository is reached, not something the
    repository controls. Below it, each component of
    `dir_path` that exists must be a directory and not a symlink: a
    repository can commit `.flow`, `.flow/runs`, `.flow/goals` or
    `.decisions` as a symlink to a directory outside the checkout, and a
    write under it lands in the link's target. When every component is a
    real directory, the physical path is the lexical one: `cd <dir> &&
    pwd -P` equals `$(pwd -P)/<dir>`.

    With create=True, a missing component is made with os.mkdir, one at a
    time and only after the component above it passed, then checked like the
    rest; os.makedirs would create the whole chain through a link before
    anything could look at it. Without create, a missing component ends the
    walk: nothing below it exists to be written through.

    A path that does not end under the repository top (see _repo_parts) is
    outside this rule — per-user state under $HOME, a scratch file, a
    configured journal directory elsewhere — and is created as os.makedirs
    would.

    Not covered: a directory replaced by a symlink between this check and the
    open that follows it. The threat here is content a repository commits,
    which is in place before flow runs, not a concurrent local process.

    Raises RepoDirRefused naming the component, relative to the repository
    top, that is a symlink or not a directory, and JournalAtomicError for one
    that cannot be created or inspected.
    """
    try:
        anchor, parts = _repo_parts(dir_path)
    except OSError as e:  # the current directory was removed
        raise JournalAtomicError(f"cannot resolve the current directory: {e}", exit_code=2)
    if parts is None:
        if create:
            try:
                os.makedirs(dir_path, exist_ok=True)
            except OSError as e:
                raise JournalAtomicError(f"cannot create {dir_path}: {e}", exit_code=2)
        return
    cur = anchor
    shown = []
    for part in parts:
        cur = os.path.join(cur, part)
        shown.append(part)
        # Named from the repository top. Every component before this one was
        # a real directory, so a `..` among them is the parent it reads as,
        # and the name can be shown without it.
        name = os.path.normpath(os.sep.join(shown)).replace(os.sep, "/")
        try:
            st = os.lstat(cur)
        except FileNotFoundError:
            if not create:
                return
            try:
                os.mkdir(cur)
            except FileExistsError:
                pass
            except OSError as e:
                raise JournalAtomicError(f"cannot create {name}: {e}", exit_code=2)
            try:
                st = os.lstat(cur)
            except OSError as e:
                raise JournalAtomicError(f"cannot inspect {name}: {e}", exit_code=2)
        except OSError as e:
            raise JournalAtomicError(f"cannot inspect {name}: {e}", exit_code=2)
        if stat.S_ISLNK(st.st_mode):
            raise RepoDirRefused(
                f"refusing — {name} is a symlink; nothing is written under it",
                exit_code=2,
            )
        if not stat.S_ISDIR(st.st_mode):
            raise RepoDirRefused(
                f"refusing — {name} is not a directory",
                exit_code=2,
            )


def ensure_inside_repo(dir_path):
    """Refuse a directory that is not in the repository, by ensure_repo_dir()'s rule.

    For a path the repository chose, such as a journal.dir in its own
    settings, where ensure_repo_dir()'s "outside the rule" is not an answer:
    dir_path must end under the repository top (_repo_parts), and each of
    its components that exists must be a directory and not a symlink, even one
    pointing inside the repository. Then the physical path is the one written,
    and it is under the repository. Creates nothing.

    Raises RepoDirRefused naming dir_path when it does not end under the
    repository top — an absolute path elsewhere, including one
    that only shares the repository's path as a string prefix, or a name that
    climbs out with `..` — and otherwise whatever ensure_repo_dir() raises.
    """
    try:
        _anchor, parts = _repo_parts(dir_path)
    except OSError as e:  # the current directory was removed
        raise JournalAtomicError(f"cannot resolve the current directory: {e}", exit_code=2)
    if parts is None:
        raise RepoDirRefused(
            f"refusing — {os.fspath(dir_path)} is outside the repository",
            exit_code=2,
        )
    ensure_repo_dir(dir_path)
