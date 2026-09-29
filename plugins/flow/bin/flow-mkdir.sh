#!/usr/bin/env bash
# [flow] Create a directory in the repository, never through a symlink.
#
# A repository can commit a directory flow writes under — .flow, .flow/runs,
# .flow/goals, .decisions — as a symlink to a directory outside the checkout,
# and `mkdir -p` follows it, so whatever is written next lands in the link's
# target. This creates each directory one component at a time below the
# current directory (the repository's working-tree top when a command block
# runs) and refuses when a component that exists is a symlink or not a
# directory. The rule is ensure_repo_dir() in bin/_repo_dir.py, which every
# flow writer applies; this is its form for command blocks and skills. It
# needs python3 and nothing else: the check imports no PyYAML.
#
# Usage:
#   flow-mkdir.sh [--] <dir>...           create each directory and its missing parents
#   flow-mkdir.sh --check [--] <dir>...   create nothing; refuse the same way
#
# Options come first; `--` ends them, and every caller passes it, because a
# directory name can come from a settings file (journal.dir) and may start
# with `-`: without it `--check` or `-h` would be read as an option.
#
# A path that does not end under the current directory (absolute elsewhere, or
# climbing out with `..`) is outside the rule and is created as mkdir -p would.
#
# Exits:
#   0 — every directory exists (for --check: none is refused)
#   1 — usage error
#   2 — refused: a component is a symlink or not a directory; the reason is
#       on stderr
#   3 — could not check or create: python3 is missing or the check did not
#       run, or a component could not be inspected or created; the reason is
#       on stderr. Nothing is known about the directory, so a caller reports
#       it as unavailable, never as refused and never as absent.

set -euo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH
# The CWD is the repository being checked; a module file there must not
# shadow the one this imports.
export PYTHONSAFEPATH=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CREATE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CREATE=0; shift ;;
    --) shift; break ;;
    -h|--help)
      awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
      exit 0 ;;
    -*)
      echo "flow-mkdir.sh: unknown option: $(printf '%s' "$1" | LC_ALL=C tr '\000-\037\177' ' ') (end the options with -- before a directory named with a leading -)" >&2
      exit 1 ;;
    *) break ;;
  esac
done
if [ $# -eq 0 ]; then
  echo "flow-mkdir.sh: usage: flow-mkdir.sh [--check] [--] <dir>..." >&2
  exit 1
fi

for d in "$@"; do
  if [ -z "$d" ]; then
    echo "flow-mkdir.sh: an empty directory name is not a directory" >&2
    exit 1
  fi
done

# The Python part answers 0 (every directory passed), 12 (refused) or 13
# (could not check or create). Anything else — no python3 at all (127), a
# python3 that does not run, an import that fails — is a check that did not
# happen, so it is 3 as well:
# never the 2 of a refusal, and never the 1 of a usage error a python3 that
# exits 1 would otherwise look like.
RC=0
python3 - "$SCRIPT_DIR" "$CREATE" "$@" <<'PYTHON' || RC=$?
import sys

sys.path[:] = [p for p in sys.path if p not in ("", ".")]
sys.path.insert(0, sys.argv[1])

from _repo_dir import JournalAtomicError, RepoDirRefused, ensure_repo_dir  # noqa: E402

create = sys.argv[2] == "1"
for d in sys.argv[3:]:
    try:
        ensure_repo_dir(d, create=create)
    except JournalAtomicError as e:
        # One line: a directory name can come from a tracked settings file.
        msg = "".join(" " if ord(c) < 32 or ord(c) == 127 else c for c in str(e))
        if isinstance(e, RepoDirRefused):
            print("flow-mkdir.sh: %s" % msg, file=sys.stderr)
            sys.exit(12)
        print("flow-mkdir.sh: cannot check %s: %s" % (d, msg), file=sys.stderr)
        sys.exit(13)
PYTHON
case "$RC" in
  0) exit 0 ;;
  12) exit 2 ;;
  13) exit 3 ;;
  *)
    echo "flow-mkdir.sh: cannot check $(printf '%s' "$*" | LC_ALL=C tr '\000-\037\177' ' '): the check did not run (python3 exited $RC; 127 is python3 not installed)" >&2
    exit 3 ;;
esac
