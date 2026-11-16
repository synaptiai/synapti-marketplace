"""Read the JSON values of a stream-json log, the format Claude Code prints
with --output-format stream-json.

json_values(path) yields each line's decoded JSON value, in order. It skips a
line that does not start with { after its surrounding whitespace is removed,
and a line that does not decode; bytes that are not UTF-8 are replaced, so a
torn or binary line never stops the read. A value need not be an object:
each caller keeps or drops what is not. A missing file raises
FileNotFoundError, which each caller handles in its own way.
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


def json_values(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        for ln in f:
            ln = ln.strip()
            if not ln.startswith("{"):
                continue
            try:
                yield json.loads(ln)
            except ValueError:
                continue
