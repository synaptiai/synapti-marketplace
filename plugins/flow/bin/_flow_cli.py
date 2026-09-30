"""What a flow helper prints when it refuses, and which refusals are the caller's.

Shared by bin/flow-record-evidence.sh, bin/flow-record-activity.sh,
bin/flow-goal-record.sh and bin/flow-record-verdict.sh, so that each prints a
value the same way and sorts a failure to open its input the same way.

A message is one line of text. It can hold a value from outside: an
argument, a path, a value from the file the helper reads, an error's text.
escaped() writes each control character (category Cc: C0, DEL and C1),
U+2028, U+2029 and each byte that is not UTF-8 (as python3 decodes an
argument or a file name) as \\n, \\r, \\t, \\xNN or \\uNNNN, and changes nothing
else, so runs of spaces and a no-break space survive and the value can be
read back. shown() cuts a value no earlier check has bounded at MAX_SHOWN
characters. Messages(prog).say() escapes the whole message and prints it on
stderr after the helper's name.
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

import errno
import os
import stat
import sys
import unicodedata

MAX_SHOWN = 500
_ESCAPES = {"\n": "\\n", "\r": "\\r", "\t": "\\t"}

# The errors of an open, or of a look at a name, that describe the path the
# caller gave: it is not there, not reachable, not readable, not a file that
# can be read, or not a name at all. Any other error (too many open files, no
# memory, an I/O error, an interrupted call) says nothing about the caller's
# file, and is the environment's.
INPUT_ERRNOS = frozenset(
    getattr(errno, name) for name in (
        "ENOENT", "ENOTDIR", "EACCES", "EPERM", "EISDIR", "ENXIO", "ENODEV",
        "EOPNOTSUPP", "ENAMETOOLONG", "EINVAL",
    ) if hasattr(errno, name)
)


# O_NOFOLLOW and O_NONBLOCK are Unix-only, and O_BINARY Windows-only: a
# native Windows python3 opens a file in text mode unless O_BINARY is asked
# for, and would read a raw output's "\x1a" as its end and write "\n" as
# "\r\n". Each is asked for where the platform has it.
O_NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)
O_NONBLOCK = getattr(os, "O_NONBLOCK", 0)
O_BINARY = getattr(os, "O_BINARY", 0)


def open_regular(path, encoding="utf-8", errors="strict"):
    """`path` opened to be read as text, and only if it is a regular file.

    The open never waits: with O_NONBLOCK, where the platform has it, a FIFO
    is opened at once, and fstat then refuses it, as it refuses a directory,
    a device or a socket, with OSError(EINVAL, "not a regular file"). EINVAL
    is in INPUT_ERRNOS, so Messages.cannot() calls it the caller's input, and
    a reader that takes any OSError for a file it cannot read takes this one
    too. A symlink is followed, as open() follows it; a caller that refuses
    symlinks looks at the name first."""
    fd = os.open(path, os.O_RDONLY | O_NONBLOCK | O_BINARY)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise OSError(errno.EINVAL, "not a regular file", path)
        return os.fdopen(fd, "r", encoding=encoding, errors=errors)
    except BaseException:
        os.close(fd)
        raise


def escaped(text):
    out = []
    for ch in str(text):
        code = ord(ch)
        if ch in _ESCAPES:
            out.append(_ESCAPES[ch])
        elif 0xDC80 <= code <= 0xDCFF:
            # A byte that is not UTF-8, as python3 decodes an argument or a
            # file name: written as the byte it was.
            out.append("\\x%02x" % (code - 0xDC00))
        elif unicodedata.category(ch) in ("Cc", "Cs") or code in (0x2028, 0x2029):
            out.append("\\x%02x" % code if code < 0x100 else "\\u%04x" % code)
        else:
            out.append(ch)
    return "".join(out)


def shown(value, limit=MAX_SHOWN):
    text = str(value)
    return text if len(text) <= limit else text[:limit] + "…"


def name_max(path="."):
    """The longest file name, in bytes, the file system at `path` takes; 255
    where it cannot be asked (Windows has no os.pathconf)."""
    try:
        return os.pathconf(path, "PC_NAME_MAX")
    except (AttributeError, OSError, ValueError):
        return 255


def yaml_problem(e):
    """A YAML error on one line: PyYAML's reason, cut, then where it is. The
    line and column, or the position of a character the reader refuses, are
    kept whatever the cut takes, and no snippet of the file is quoted."""
    import yaml
    if isinstance(e, yaml.reader.ReaderError):
        code = e.character if isinstance(e.character, int) else ord(e.character)
        return f"unacceptable character #x{code:04x}: {shown(e.reason)} (position {e.position})"
    if isinstance(e, yaml.MarkedYAMLError):
        reason = ", ".join(part for part in (e.context, e.problem) if part) or type(e).__name__
        mark = e.problem_mark or e.context_mark
        where = f" (line {mark.line + 1}, column {mark.column + 1})" if mark is not None else ""
        return shown(reason) + where
    return shown(e)


def schema_problem(e):
    """Where a jsonschema refusal is, and which rule: the schema's own value,
    never e.message, which quotes the whole value that failed."""
    import json
    where = getattr(e, "json_path", None) or "$" + "".join(
        f".{part}" if isinstance(part, str) else f"[{part}]" for part in e.absolute_path
    )
    return f"at {shown(where)} ({e.validator}: {shown(json.dumps(e.validator_value))})"


class Messages:
    """say() and refuse() for one helper."""

    def __init__(self, prog):
        self.prog = prog

    def say(self, message):
        print(f"{self.prog}: {escaped(message)}", file=sys.stderr)

    def refuse(self, message, status=1):
        self.say(message)
        sys.exit(status)

    def cannot(self, verb, flag, path, e):
        """An input the helper could not open or read: exit 1 when the error
        describes the path (INPUT_ERRNOS), 2 when it is the environment's."""
        reason = e.strerror or shown(e)
        if e.errno in INPUT_ERRNOS:
            self.refuse(f"cannot read {flag} {shown(path)}: {reason}")
        self.refuse(f"cannot {verb} {flag} {shown(path)}: {reason}", 2)

    def open_input(self, path, flag, symlink_what):
        """Open a file the caller names, to read it. It is looked at by name
        first: not there, a symlink, or not a regular file is refused before
        anything is opened. The open then refuses a symlink put in its place
        meanwhile (O_NOFOLLOW, where there is one: Windows has none, and makes
        symlinks without elevation in Developer Mode, so there the look by
        name is the only check), never waits (O_NONBLOCK: a FIFO put in its
        place is opened, then refused), and what was opened is refused unless
        fstat says a regular file. Returns the descriptor, or exits: 2 for a
        symlink; 1 for a path that is not there, cannot be read or is not a
        regular file; 2 for a failure that says nothing about the path (too
        many open files, an I/O error)."""
        try:
            st = os.lstat(path)
        except FileNotFoundError:
            self.refuse(f"{flag} {shown(path)} does not exist")
        except OSError as e:
            self.cannot("open", flag, path, e)
        if stat.S_ISLNK(st.st_mode):
            self.refuse(f"refusing — {symlink_what} {shown(path)} is a symlink", 2)
        if not stat.S_ISREG(st.st_mode):
            self.refuse(f"{flag} {shown(path)} is not a regular file")
        try:
            fd = os.open(path, os.O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_BINARY)
        except OSError as e:
            if e.errno in (errno.ELOOP, errno.EMLINK):
                self.refuse(f"refusing — {symlink_what} {shown(path)} is a symlink", 2)
            # Not readable, gone, or not a file that can be opened (a Unix
            # socket put in its place) is the caller's input, 1; anything else
            # is 2.
            self.cannot("open", flag, path, e)
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            os.close(fd)
            self.refuse(f"{flag} {shown(path)} is not a regular file")
        return fd

    def read_arguments(self, argv, valued, flags=()):
        """The arguments, as the shell passed them: {option: value} for each
        option in `valued` (value "" when not given) and {flag: True} for each
        flag given. Refuses, exit 1, an argument that is neither, and a valued
        option given last with no value."""
        options = {name: "" for name in valued}
        options.update({name: False for name in flags})
        args = list(argv)
        while args:
            if args[0] in flags:
                options[args[0]] = True
                args = args[1:]
                continue
            if args[0] not in valued:
                self.refuse(f"unknown argument: {shown(args[0])}")
            if len(args) < 2:
                self.refuse(f"{args[0]} needs a value")
            options[args[0]] = args[1]
            args = args[2:]
        return options
