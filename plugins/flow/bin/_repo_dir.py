"""Directories under the repository, never reached through a symlink.

The rule every flow writer and reader applies to a directory below the
repository: ensure_repo_dir() refuses (or creates) a directory reached through
a symlink, and ensure_inside_repo() also refuses one that is not under the
current directory at all. bin/_journal_atomic.py re-exports both for its
writers; bin/flow-mkdir.sh is the same rule for command blocks and skills.

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


def _repo_parts(path):
    """Return (anchor, parts): `path` as components below the current directory.

    parts is None when `path` does not end under the current directory — an
    absolute path elsewhere, or a name that climbs out with `..` — which puts
    it outside ensure_repo_dir()'s rule. An absolute path that names the
    current directory through a symlink above it is under it
    (_below_same_dir). parts keeps every `..` as written: read without the
    links, `shared/../x` is `x`, but the kernel resolves `shared` first, so it
    is walked as written.
    """
    anchor = os.getcwd()
    raw = os.fspath(path)
    if os.path.altsep:
        raw = raw.replace(os.path.altsep, os.sep)
    prefix = anchor if anchor.endswith(os.sep) else anchor + os.sep
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
    """Refuse a directory that is reached through a symlink below the current directory.

    Every flow writer runs from the repository's working-tree top, where
    Claude Code runs commands and hooks, and names its files relative to it
    (`.flow/runs/<id>`, `.decisions`) — so the current directory stands for
    the top. Its physical path (os.getcwd) is the anchor: what lies above it,
    such as macOS's /var -> /private/var, is how the repository is reached,
    not something the repository controls. Below it, each component of
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

    A path that does not end under the current directory (see _repo_parts) is
    outside this rule — per-user state under $HOME, a scratch file, a
    configured journal directory elsewhere — and is created as os.makedirs
    would. A writer run from a subdirectory of the repository is checked
    from that subdirectory down.

    Not covered: a directory replaced by a symlink between this check and the
    open that follows it. The threat here is content a repository commits,
    which is in place before flow runs, not a concurrent local process.

    Raises JournalAtomicError(exit_code=2) naming the component, relative to
    the current directory, that is a symlink or not a directory, or that
    cannot be created or inspected.
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
        name = "/".join(shown)
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
    dir_path must end under the current directory (_repo_parts), and each of
    its components that exists must be a directory and not a symlink, even one
    pointing inside the repository. Then the physical path is the one written,
    and it is under the repository. Creates nothing.

    Raises JournalAtomicError(exit_code=2) naming dir_path when it does not end
    under the current directory — an absolute path elsewhere, including one
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
