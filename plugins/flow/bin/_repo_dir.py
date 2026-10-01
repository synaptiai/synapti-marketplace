"""Directories under the repository, never reached through a symlink.

The rule every flow writer and reader applies to a directory below the
repository: ensure_repo_dir() refuses (or creates) a directory reached through
a symlink, and ensure_inside_repo() also refuses one that is not under the
repository top at all. A path is followed one name at a time, as the kernel
follows it (_walk), never split by its text. Per-user state — an absolute path under the user's home's .claude
or flow's state directory — is never subject to it, whatever the top. The top is the nearest directory at or above the
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

import ntpath
import os
import stat
import sys



class JournalAtomicError(RuntimeError):
    """Raised on any atomicity / symlink / parse error.

    Attributes:
      exit_code: 1 for user-input errors, 2 for infrastructure / refusal.
      refuse: when True, the caller should append the canonical
              "refusing to overwrite — fix manually" line to stderr: the
              journal exists but cannot be parsed, so it is left as it is
              for a person to repair rather than overwritten.
      reason: what went wrong, set where the error is raised; the message
              itself unless given. A reader names it from here, never by
              cutting the message at a "; ", which a name can hold.
      summary: what a reader names before its own note ("<summary>; goals
              are not read through it"): the reason, or for a refusal
              "refusing — <reason>".
    """

    def __init__(self, message, exit_code=2, refuse=False, reason=None):
        super().__init__(message)
        self.exit_code = exit_code
        self.refuse = refuse
        self.reason = message if reason is None else reason

    @property
    def summary(self):
        return self.reason


# The note every refusal ends with. flow-mkdir.sh prints a refusal as one
# line ending in it, so a shell caller takes the reason by removing it.
REFUSAL_NOTE = "nothing is written under it"


class RepoDirRefused(JournalAtomicError):
    """A directory refused by the rule: a component is a symlink or not a
    directory, or the path is not in the repository. Distinct from a check
    that could not be done, which raises JournalAtomicError itself.

    Raised with the reason alone ("sub is a symlink"); the message is
    "refusing — <reason>; nothing is written under it"."""

    def __init__(self, reason, exit_code=2):
        super().__init__(f"refusing — {reason}; {REFUSAL_NOTE}", exit_code=exit_code, reason=reason)

    @property
    def summary(self):
        return f"refusing — {self.reason}"


# ---------------------------------------------------------------------------
# Directories under the repository.

def _within(path, top_st):
    """The ancestor of the physical directory `path`, spelled as in `path`,
    that is the repository top, or None when `path` is not at or below the
    top. Decided by identity: the ancestor is the same directory (st_dev,
    st_ino) as the top, so a path that names the top by another spelling (a
    case the file system ignores) is still inside; a path whose ancestors
    cannot be stat()ed is not.
    """
    p = path
    while True:
        try:
            if os.path.samestat(os.stat(p), top_st):
                return p
        except OSError:
            return None
        parent = os.path.dirname(p)
        if parent == p:
            return None
        p = parent


def _components(path, pathmod=os.path):
    """The names in `path`, split on the separator, without the empty ones
    (a doubled or trailing separator) and without `.`: the kernel skips both."""
    if pathmod.altsep:
        path = path.replace(pathmod.altsep, pathmod.sep)
    return [c for c in path.split(pathmod.sep) if c and c != "."]


# A Windows path with this prefix is passed to the file system as written:
# Win32 cleans nothing in it.
_WIN_VERBATIM = "\\\\?\\"


def _win_clean(path):
    r"""`path`, absolute, as Win32 cleans it by its text before it resolves
    anything, `.` and `..` taken away (ntpath.normpath). Microsoft's rule is
    that a path is normalized unless it starts exactly with `\\?\`, with the
    canonical backslashes: such a path, which _spelled() has let through as
    written, is passed on unchanged; every other device spelling (`\\.\`,
    `//?/`, `\??\`) was refused there, before a `/` was made a `\`.

    Win32 also drops characters from the end of a name: a single trailing
    period from a name in the middle, and every trailing period and space
    from the last name. A walk that dropped them too would have to follow
    that rule exactly (what of `sub..`?), and one that dropped more would
    check `sub` while Win32 opens a middle `sub ` the repository committed as
    a link. So a name, other than `.` and `..`, that ends in a period or a
    space is refused: Windows may open a different name.
    """
    if path.startswith(_WIN_VERBATIM):
        return path
    path = ntpath.normpath(path)
    for name in ntpath.splitdrive(path)[1].split(ntpath.sep):
        if name not in ("", ".", "..") and name[-1] in ". ":
            raise RepoDirRefused(
                f"'{name}' ends in a period or a space, and Windows may open a different name"
            )
    return path


def _spelled(raw, pathmod=os.path):
    r"""`raw` with the platform's own separator, for the walk to split.

    On Windows the spelling is judged first, before a `/` is made a `\`: a
    path is passed to the file system as written only when it starts exactly
    with `\\?\`, the canonical backslashes, and is kept so. Any other device
    spelling (two separators and then `.` or `?`, as `\\.\`, `//./` or
    `//?/`, or `\??\`) is refused: what it names depends on how the device
    namespace resolves it, which the walk does not follow, so the caller is
    told to use a drive path, or `\\?\` to name a path as written.
    """
    if pathmod is ntpath:
        if raw.startswith(_WIN_VERBATIM):
            return raw
        seps = "\\/"
        if (len(raw) >= 3 and raw[0] in seps and raw[1] in seps and raw[2] in ".?") or (
            len(raw) >= 4 and raw[0] in seps and raw[1:3] == "??" and raw[3] in seps
        ):
            raise RepoDirRefused(
                f"'{raw}' is a Windows device path; use a drive path, or "
                f"\\\\?\\ to name a path as written"
            )
    if pathmod.altsep:
        raw = raw.replace(pathmod.altsep, pathmod.sep)
    return raw


def _begin(path, cwd, top, pathmod=os.path):
    """(directory, names) where _walk() starts and what it walks, or None
    for per-user state, which the rule does not cover.

    The path is spelled first (_spelled: on Windows a device path is refused
    and `/` made `\\`), then an absolute path under a per-user root is left
    out (_is_per_user), then the start is _start()'s.
    """
    raw = _spelled(os.fspath(path), pathmod)
    # Only an absolute path can be per-user state: every per-user writer names
    # its file from the user's home or FLOW_STATE_DIR, and a relative path is always the
    # repository's own content, which a committed symlink must not escape.
    if pathmod.isabs(raw) and _is_per_user(raw, top):
        return None
    return _start(raw, cwd, pathmod)


def _start(raw, cwd, pathmod=os.path):
    """(directory, names): where a walk of the path `raw` starts, and the
    names it walks from there, as the platform resolves a path.

    POSIX resolves a path one name at a time, `..` included: a relative path
    starts at the working directory, an absolute one at the root, and each
    `..` is taken where the walk has got to. Windows first makes the path
    absolute and cleans it by its text (GetFullPathName; _win_clean), then
    follows what is left: so there the text is cleaned first, as the system
    does, a name Win32 may open under another name is refused, and the walk
    starts at the drive's root.
    """
    if pathmod is ntpath:
        full = _win_clean(ntpath.join(cwd, raw))
        drive, tail = ntpath.splitdrive(full)
        return drive + ntpath.sep, _components(tail, ntpath)
    if pathmod.isabs(raw):
        drive, tail = pathmod.splitdrive(raw)
        return drive + pathmod.sep, _components(tail, pathmod)
    return cwd, _components(raw, pathmod)


def _link_names(link, target, names, pathmod=os.path):
    """(directory or None, names): where the walk goes on after the symlink
    `link`, whose target is `target`, with `names` still to walk.

    On POSIX the target's names are walked in place of the link, from the
    root for an absolute target, or from the link's directory (None: stay
    where the walk is) for a relative one. On Windows the target is joined to
    the link's directory and cleaned by its text, as the system does
    (_win_clean); a target rooted without a drive (`\\a\\b`) is on the
    link's drive.
    """
    if pathmod is ntpath:
        full = _win_clean(ntpath.join(ntpath.dirname(link), _spelled(target, ntpath)))
        drive, tail = ntpath.splitdrive(full)
        return drive + ntpath.sep, _components(tail, ntpath) + names
    if pathmod.altsep:
        target = target.replace(pathmod.altsep, pathmod.sep)
    if pathmod.isabs(target):
        drive, tail = pathmod.splitdrive(target)
        return drive + pathmod.sep, _components(tail, pathmod) + names
    return None, _components(target, pathmod) + names


def _shown(path, base):
    """`path`, a directory entry inside the repository, named from `base`,
    the top as the walk spelled it."""
    return os.path.relpath(path, base).replace(os.sep, "/")


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


# Directories the user chose outright: an absolute journal.dir from the user's
# own settings (journal-dir.sh --user-owned). A writer registers it from its
# arguments, never from the environment, which a repository's settings can set.
_USER_OWNED = []


def register_user_owned(dir_path):
    """Treat `dir_path`, an absolute directory the user chose, as per-user for
    the rest of this process: a path under it, as written, is outside the
    rule, so a symlink the user made on the way to it (a ~/Dropbox under a
    home kept in git) is not refused. The file itself is still opened without
    following a link. A relative or empty path is ignored: a relative user
    value keeps the rule, and so does every repository value.
    """
    p = os.fspath(dir_path) if dir_path else ""
    if p and os.path.isabs(p):
        _USER_OWNED.append(os.path.normpath(p))


_STATE_DIR = []


def _state_dir():
    """The per-user state directory as cascade-resolve.sh --state-dir decides
    it: FLOW_STATE_DIR only when the user chose it, never a value inside the
    repository or one the repository's own settings set. Asked once per
    process; its warning is the caller's to print, not this module's. None
    when the helper cannot answer, which leaves only <home>/.claude."""
    if not _STATE_DIR:
        answer = None
        if os.environ.get("FLOW_STATE_DIR"):
            import subprocess
            helper = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cascade-resolve.sh")
            try:
                out = subprocess.run([helper, "--state-dir"], stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, timeout=30).stdout
                answer = os.fsdecode(out).strip() or None
            except (OSError, subprocess.SubprocessError):
                answer = None
        _STATE_DIR.append(answer)
    return _STATE_DIR[0]


_USER_HOME = []


def _user_home():
    """The user's home as cascade-resolve.sh --user-home decides it: HOME when
    it is absolute and the repository's own settings did not set it, otherwise
    the home the user database gives. A HOME equal to the user database's home
    needs no helper. Without a user database module (Windows) HOME is taken
    as it is, as before; a user the user database has no entry for (a
    container run under a bare uid) asks the helper, as bash does. Asked once
    per process; None when nothing answers."""
    if not _USER_HOME:
        home = os.environ.get("HOME")
        try:
            import pwd
        except ImportError:
            pwd = None
        if pwd is None or not hasattr(os, "getuid"):
            answer = home
        else:
            try:
                db = pwd.getpwuid(os.getuid()).pw_dir
            except KeyError:
                db = None
            answer = None
            if home and home == db:
                answer = home
            else:
                import subprocess
                helper = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cascade-resolve.sh")
                try:
                    out = subprocess.run([helper, "--user-home"], stdout=subprocess.PIPE,
                                         stderr=subprocess.DEVNULL, timeout=30).stdout
                    answer = os.fsdecode(out).strip() or None
                except (OSError, subprocess.SubprocessError):
                    answer = None
                if answer == "/nonexistent":
                    answer = None
        _USER_HOME.append(answer)
    return _USER_HOME[0]


def _per_user_roots():
    """The user's own directories: <home>/.claude, where Flow keeps its own
    files (settings.flow.json, flow-state/, flow-proposals/) whatever
    CLAUDE_CONFIG_DIR says, and the state directory _state_dir() names.
    The home is _user_home()'s, so a HOME the repository sets does not make
    a directory inside it per-user. Absolute values only."""
    home = _user_home()
    roots = []
    for root in (os.path.join(home, ".claude") if home else None, _state_dir()):
        if root and os.path.isabs(root):
            roots.append(os.path.normpath(root))
    return roots + _USER_OWNED


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


# More symlinks than this on one path is a loop, as the kernel's ELOOP.
_MAX_LINKS = 40


class _Walk:
    """Where _walk() ended: `top`, the repository top; `outside_rule`, true
    for per-user state, which the rule does not cover; `entered`, whether the
    walk was ever at or below the top; `inside`, whether it ended there;
    `end`, the physical directory it ended in, `pending`, the missing names
    below it, and `missing`, whether any name on the way was missing, which
    a creating walk makes (a `..` after a missing name needs it made, though
    it is no longer pending where the walk ends)."""

    __slots__ = ("top", "outside_rule", "entered", "inside", "end", "pending", "missing", "base")

    def __init__(self, top, outside_rule=False, entered=False, inside=False, end=None, pending=(),
                 missing=False, base=None):
        self.top = top
        self.base = base
        self.outside_rule = outside_rule
        self.entered = entered
        self.inside = inside
        self.end = end
        self.pending = list(pending)
        self.missing = missing or bool(self.pending)

    def below_top(self):
        """The end relative to the top, `/`-separated (`.` for the top), or
        None when the walk did not end inside the repository."""
        if self.outside_rule or not self.inside:
            return None
        rel = os.path.relpath(os.path.join(self.end, *self.pending), self.base or self.top)
        return rel.replace(os.sep, "/")


def _walk(path, create=False):
    """Follow `path` the way the kernel resolves it, one name at a time, and
    apply the rule to each name the repository controls.

    The top is _repo_top() of the physical working directory. Where the walk
    starts, and the names it walks, are _start()'s: on POSIX a relative
    `path` starts at the working directory, which is at or below the top, an
    absolute one at the root; on Windows the path is first made absolute and
    cleaned by its text, as the system does. The names are split on the
    separator, skipping empty ones and `.`, and each is taken from the
    physical directory the walk is in:

      - `..` moves to that directory's physical parent;
      - a name that does not exist is made with os.mkdir when `create` is
        set, and the walk goes on in it; otherwise it is pending, as is every
        name below it, and a `..` takes a pending name back off first;
      - a symlink is refused when the directory it is in is inside the
        repository (_within), and followed otherwise: its target's names are
        walked in its place (_link_names), from the root for an absolute
        target, so a
        symlink above the repository, such as macOS's /var, still reaches it,
        and a repository symlink reached through one is still refused;
      - a name that is not a directory is refused inside the repository;
        outside it the walk cannot go on, and a creating walk fails.

    So the name that decides where a write lands is the one checked: a
    doubled separator after the top, or a symlink below it followed by
    enough `..` to climb out, reaches the symlink first, as the kernel does.

    An absolute path that is per-user state (_is_per_user) is outside the
    rule and is not walked.

    Returns a _Walk. Raises RepoDirRefused naming, from the top, the name
    that is a symlink or not a directory, and JournalAtomicError for a name
    that cannot be inspected or created, or too many symlinks.
    """
    cwd = os.getcwd()
    top = _repo_top(cwd)
    top_st = os.stat(top)
    raw = os.fspath(path)
    begun = _begin(raw, cwd, top)
    if begun is None:
        return _Walk(top, outside_rule=True)
    cur, names = begun
    # base is the top as this walk spells it, None while the walk is outside.
    base = _within(cur, top_st)
    entered = base is not None
    pending = []
    missing = False
    links = 0
    while names:
        name = names.pop(0)
        if name == "..":
            if pending:
                pending.pop()
            else:
                cur = os.path.dirname(cur)
                base = _within(cur, top_st)
            continue
        if pending:
            pending.append(name)
            continue
        nxt = os.path.join(cur, name)
        shown = _shown(nxt, base) if base is not None else nxt
        try:
            st = os.lstat(nxt)
        except FileNotFoundError:
            if not create:
                pending.append(name)
                missing = True
                continue
            try:
                os.mkdir(nxt)
            except FileExistsError:
                pass
            except OSError as e:
                raise JournalAtomicError(f"cannot create {shown}: {e}", exit_code=2)
            try:
                st = os.lstat(nxt)
            except OSError as e:
                raise JournalAtomicError(f"cannot inspect {shown}: {e}", exit_code=2)
        except OSError as e:
            raise JournalAtomicError(f"cannot inspect {shown}: {e}", exit_code=2)
        if stat.S_ISLNK(st.st_mode):
            if base is not None:
                raise RepoDirRefused(f"{shown} is a symlink")
            links += 1
            if links > _MAX_LINKS:
                raise JournalAtomicError(f"cannot resolve {raw}: too many levels of symbolic links", exit_code=2)
            try:
                target = os.readlink(nxt)
            except OSError as e:
                raise JournalAtomicError(f"cannot inspect {nxt}: {e}", exit_code=2)
            root, names = _link_names(nxt, target, names)
            if root is not None:
                cur = root
                base = _within(cur, top_st)
                entered = entered or base is not None
            continue
        if not stat.S_ISDIR(st.st_mode):
            if base is not None:
                raise RepoDirRefused(f"{shown} is not a directory")
            if create:
                raise JournalAtomicError(f"cannot create {raw}: {nxt} is not a directory", exit_code=2)
            # Nothing can be written below it: the walk ends here.
            return _Walk(top, entered=entered, inside=False, end=cur, pending=[name] + names)
        cur = nxt
        if base is None:
            base = _within(cur, top_st)
            entered = entered or base is not None
    return _Walk(top, entered=entered, inside=base is not None, end=cur, pending=pending,
                 missing=missing, base=base)


def _walk_checked(path, create=False):
    """_walk(), with a current directory that was removed reported as a check
    that could not be done."""
    try:
        return _walk(path, create=create)
    except JournalAtomicError:
        raise
    except OSError as e:  # the current directory, or the top, was removed
        raise JournalAtomicError(f"cannot resolve the current directory: {e}", exit_code=2)


def ensure_repo_dir(dir_path, create=False, contained=False):
    """Refuse a directory that is reached through a symlink below the repository top.

    The top is the nearest directory at or above the physical working
    directory that holds a .git entry, or the working directory when none
    does. Flow writers name their files relative to the working directory
    (`.flow/runs/<id>`, `.decisions`), which is usually the top, but a Flow
    block can run with the working directory in a subdirectory, since the
    Bash tool keeps its working directory between calls, and a path that
    climbs back to the top (`../.decisions`) is then still the repository's.
    `dir_path` is followed as the kernel follows it (_walk): what lies above
    the top, such as macOS's /var -> /private/var, is how the repository is
    reached, not something the repository controls; inside it, no name may be
    a symlink, even one pointing inside the repository, or anything but a
    directory. A repository can commit `.flow`, `.flow/runs`, `.flow/goals`
    or `.decisions` as a symlink to a directory outside the checkout, and a
    write under it would land in the link's target.

    With create=True, the path is walked once without creating anything, and
    only when that passes is it walked again, each missing directory made
    with os.mkdir after the one above it passed; os.makedirs would create the
    whole chain through a link before anything could look at it. A path that
    is refused leaves nothing created. Without create, the names below a
    missing one are followed as the kernel would once they are made, so a
    `..` that climbs back from a missing directory to a symlink still
    reaches it.

    A path that never enters the repository — per-user state under the home, a
    scratch file, a configured journal directory elsewhere — is outside this
    rule and is created as os.makedirs would, following the links there.
    With contained=True, a path that enters the repository and ends outside
    it (`../j` from the top, `<top>/../j` however the top is spelled) is
    refused instead. The auto-log hooks ask for this: they write a trail
    inside the repository, by this rule, or where the path never enters it.

    Not covered: a directory replaced by a symlink between this check and the
    open that follows it. The threat here is content a repository commits,
    which is in place before flow runs, not a concurrent local process.

    Raises RepoDirRefused naming, from the top, the name that is a symlink or
    not a directory (or, with contained=True, the path that leaves the
    repository), and JournalAtomicError for one that cannot be created or
    inspected.
    """
    walked = _walk_checked(dir_path)
    if walked.outside_rule:
        if create:
            try:
                os.makedirs(dir_path, exist_ok=True)
            except OSError as e:
                raise JournalAtomicError(f"cannot create {dir_path}: {e}", exit_code=2)
        return
    if contained and walked.entered and not walked.inside:
        raise RepoDirRefused(f"{os.fspath(dir_path)} leaves the repository")
    if create and walked.missing:
        _walk_checked(dir_path, create=True)


def repo_relative(dir_path):
    """`dir_path` below the repository top, as the kernel reaches it, or None.

    The directory _walk() ends in, relative to the top, `/`-separated (`.`
    for the top itself), whether `dir_path` is relative or names the top as
    written or through a symlink above it. None for a path that does not end
    inside the repository or is outside the rule. A caller compares the
    answer with the paths git reports, which are relative to the top.
    Raises what ensure_repo_dir() raises for a refused path.
    """
    return _walk_checked(dir_path).below_top()


def ensure_inside_repo(dir_path):
    """Refuse a directory that is not in the repository, by ensure_repo_dir()'s rule.

    For a path the repository chose, such as a journal.dir in its own
    settings, where ensure_repo_dir()'s "outside the rule" is not an answer:
    dir_path, followed as the kernel follows it, must end inside the
    repository, and no name on the way inside it may be a symlink, even one
    pointing inside the repository, or anything but a directory. Then the
    physical path is the one written, and it is in the repository. Creates
    nothing.

    Raises RepoDirRefused naming dir_path when it does not end inside the
    repository — an absolute path elsewhere, including one that only shares
    the repository's path as a string prefix, per-user state, or a name that
    climbs out with `..` — and otherwise whatever ensure_repo_dir() raises.
    """
    walked = _walk_checked(dir_path)
    if walked.outside_rule or not walked.inside:
        raise RepoDirRefused(f"{os.fspath(dir_path)} is outside the repository")
