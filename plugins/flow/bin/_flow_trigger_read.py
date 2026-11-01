"""Read a FlowTrigger, or a FlowRun's run.yaml, as a YAML mapping.

The trigger checks (bin/flow-trigger-tier3-check.sh,
bin/flow-trigger-recursion-check.sh) and the concurrency check
(bin/flow-trigger-concurrency.sh) read files that come with the repository,
so a file is never read through a symbolic link: O_NOFOLLOW refuses a link at
the open itself, O_NONBLOCK opens a FIFO put in the file's place at once, and
fstat refuses anything but a regular file. The text is decoded as UTF-8 and
parsed with yaml.safe_load, and only a mapping is returned.

read_yaml_mapping(path) raises ReadError with one of these kinds, and each
caller words its own message (and picks its own exit status) for it:
  link         the file is a symbolic link
  missing      there is no such file (reason: the OS's words)
  unreadable   the file cannot be opened or read (reason: the OS's words)
  not-regular  the file is not a regular file
  not-yaml     the text is not UTF-8 or not valid YAML
  not-mapping  the YAML is not a mapping

The caller imports PyYAML first and says so when it is missing; this module
imports it only inside read_yaml_mapping.
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
import stat


class ReadError(Exception):
    """A file read_yaml_mapping would not, or could not, return."""

    def __init__(self, kind, reason=""):
        Exception.__init__(self, kind, reason)
        self.kind = kind
        self.reason = reason


def read_yaml_mapping(path):
    import yaml

    nofollow = getattr(os, "O_NOFOLLOW", 0)
    if not nofollow and os.path.islink(path):
        raise ReadError("link")
    try:
        fd = os.open(path, os.O_RDONLY | nofollow | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_BINARY", 0))
    except OSError as e:
        if e.errno == errno.ELOOP:
            raise ReadError("link")
        if e.errno == errno.ENOENT:
            raise ReadError("missing", e.strerror or str(e))
        raise ReadError("unreadable", e.strerror or str(e))
    try:
        with os.fdopen(fd, "rb") as f:
            if not stat.S_ISREG(os.fstat(f.fileno()).st_mode):
                raise ReadError("not-regular")
            raw = f.read()
    except OSError as e:
        raise ReadError("unreadable", e.strerror or str(e))
    try:
        doc = yaml.safe_load(raw.decode("utf-8"))
    except (yaml.YAMLError, UnicodeDecodeError):
        raise ReadError("not-yaml")
    if not isinstance(doc, dict):
        raise ReadError("not-mapping")
    return doc


if __name__ == "__main__":
    sys.stderr.write("_flow_trigger_read.py is a module; the trigger checks import it\n")
    sys.exit(2)
