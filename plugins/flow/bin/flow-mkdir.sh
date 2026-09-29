#!/usr/bin/env bash
# [flow] Create a directory in the repository, never through a symlink.
#
# A repository can commit a directory flow writes under — .flow, .flow/runs,
# .flow/goals, .decisions — as a symlink to a directory outside the checkout,
# and `mkdir -p` follows it, so whatever is written next lands in the link's
# target. This creates each directory one component at a time below the
# current directory (the repository's working-tree top when a command block
# runs) and refuses when a component that exists is a symlink or not a
# directory. The rule is ensure_repo_dir() in bin/_journal_atomic.py, which
# every flow writer applies; this is its form for command blocks and skills.
#
# Usage:
#   flow-mkdir.sh <dir>...           create each directory and its missing parents
#   flow-mkdir.sh --check <dir>...   create nothing; refuse the same way
#
# A path that does not end under the current directory (absolute elsewhere, or
# climbing out with `..`) is outside the rule and is created as mkdir -p would.
#
# Exits:
#   0 — every directory exists (for --check: none is refused)
#   1 — usage error
#   2 — refused (a component is a symlink or not a directory), cannot create,
#       or python3/PyYAML missing; the reason is on stderr

set -euo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH
# The CWD is the repository being checked; a ./yaml.py there must not shadow
# PyYAML when the module is imported.
export PYTHONSAFEPATH=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CREATE=1
if [ "${1:-}" = "--check" ]; then
  CREATE=0
  shift
fi
case "${1:-}" in
  -h|--help)
    awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
    exit 0 ;;
  "")
    echo "flow-mkdir.sh: usage: flow-mkdir.sh [--check] <dir>..." >&2
    exit 1 ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
  echo "flow-mkdir.sh: python3 required but not installed" >&2
  exit 2
fi
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  echo "flow-mkdir.sh: PyYAML required (apt install python3-yaml / pip install pyyaml)" >&2
  exit 2
fi

python3 - "$SCRIPT_DIR" "$CREATE" "$@" <<'PYTHON'
import sys

sys.path[:] = [p for p in sys.path if p not in ("", ".")]
sys.path.insert(0, sys.argv[1])

from _journal_atomic import JournalAtomicError, ensure_repo_dir  # noqa: E402

create = sys.argv[2] == "1"
for d in sys.argv[3:]:
    if not d:
        print("flow-mkdir.sh: an empty directory name is not a directory", file=sys.stderr)
        sys.exit(1)
    try:
        ensure_repo_dir(d, create=create)
    except JournalAtomicError as e:
        # One line: a directory name can come from a tracked settings file.
        msg = "".join(" " if ord(c) < 32 or ord(c) == 127 else c for c in str(e))
        print("flow-mkdir.sh: %s" % msg, file=sys.stderr)
        sys.exit(e.exit_code)
PYTHON
