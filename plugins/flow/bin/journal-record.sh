#!/usr/bin/env bash
# [flow] Record an artifact in the decision-journal manifest.
#
# Updates the YAML frontmatter on `.decisions/issue-{N}.md` (or the configured
# journal directory) with a new artifact entry. Append-only: re-running with
# identical args produces a duplicate `artifacts[]` entry rather than a no-op
# (callers that need uniqueness MUST dedupe before invoking). Atomic per-record
# via temp file + rename so a crash mid-write cannot corrupt the journal, and
# concurrency-safe via a per-journal `flock` so two concurrent invocations
# (e.g. parallel reviewer dispatch under Path A) cannot read+rename in a way
# that loses one writer's append.
#
# Usage:
#   journal-record.sh \
#     --issue <N> \
#     --type <artifact-type> \
#     [--metadata key=value ...] \
#     [--metadata key=value ...]
#
# Examples:
#   journal-record.sh --issue 142 --type specification \
#       --metadata by=specification-capture \
#       --metadata elements=non-goals,failure-modes,interface-contracts,risk-map
#
#   journal-record.sh --issue 142 --type stranger-test \
#       --metadata result=PASS --metadata task_count=5
#
#   journal-record.sh --issue 142 --type review-cycle \
#       --metadata cycle=1 --metadata path=A --metadata findings_count=3
#
# The journal directory is bin/journal-dir.sh's: journal.dir, where a value
# from the repository's own settings must resolve inside the repository and
# falls back to .decisions with a warning otherwise. It is created if it is
# missing, and never through a symlink: when it, or a directory above it in
# the repository, is one (a repository can commit `.decisions` as a link to a
# directory outside the checkout), nothing is written and the helper exits 2.
# The exception is an absolute journal.dir with no `..` component from the
# user's own settings (journal-dir.sh --user-owned): it is created and written
# as configured, and the journal itself is still opened without following a
# link.
#
# Exits:
#   0 — artifact recorded
#   1 — missing required argument or invalid metadata
#   2 — infrastructure error (settings unreadable, disk full, symlink
#       rejected — including a symlinked journal directory, etc.)

set -euo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH

# Disable adding the current working directory to sys.path inside every
# python3 invocation below. After `gh pr checkout` of a hostile fork, an
# attacker-shipped `./yaml.py` at the repo root would shadow the real
# PyYAML on the `import yaml` probe and the inline heredoc — full RCE
# under the user's UID before any of our defenses run. PYTHONSAFEPATH=1
# (Python 3.11+) covers this; older Pythons rely on the inline heredoc's
# defensive `sys.path` filter as a fallback.
export PYTHONSAFEPATH=1

ISSUE=""
TYPE=""
METADATA=()

while [ $# -gt 0 ]; do
  case "$1" in
    --issue)    ISSUE="$2"; shift 2 ;;
    --type)     TYPE="$2"; shift 2 ;;
    --metadata)
      # Reject newline/CR in metadata pairs upfront. A value containing a
      # literal newline would let `yaml.safe_dump` emit a multi-line block
      # scalar that downstream readers (markdown renderers, future schema
      # validators) would surprise on; worse, a crafted key containing `:`
      # and a newline could collide with a sibling artifact field by
      # re-parsing as multiple keys. (Bash strings cannot contain NUL, so
      # there is no NUL case to handle.)
      case "$2" in
        *$'\n'*|*$'\r'*)
          echo "journal-record.sh: metadata pair contains a newline/CR — refusing for safety" >&2
          exit 1
          ;;
      esac
      METADATA+=("$2"); shift 2 ;;
    -h|--help)
      awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"
      exit 0
      ;;
    *) echo "journal-record.sh: unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -z "$ISSUE" ] && { echo "journal-record.sh: --issue is required" >&2; exit 1; }
[ -z "$TYPE" ]  && { echo "journal-record.sh: --type is required" >&2; exit 1; }

# Validate issue is an integer
if ! echo "$ISSUE" | grep -qE '^[0-9]+$'; then
  echo "journal-record.sh: --issue must be a positive integer (got: $ISSUE)" >&2
  exit 1
fi

# The journal directory, as every journal reader and writer resolves it:
# journal.dir, where a value from the repository's own settings that leaves
# the repository is refused on stderr and .decisions used instead, and a value
# from the user's settings is used as configured.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JOURNAL_DIR=$("$SCRIPT_DIR/journal-dir.sh")
[ -n "$JOURNAL_DIR" ] || JOURNAL_DIR=".decisions"
# An absolute journal.dir from the user's own settings is the user's choice:
# it is written as configured, without the repository symlink walk (the
# journal itself is still opened without following a link).
USER_JOURNAL_DIR=$("$SCRIPT_DIR/journal-dir.sh" --user-owned 2>/dev/null) || USER_JOURNAL_DIR=""

# The directory is created in Python, through ensure_repo_dir(): mkdir -p
# would follow a symlinked journal directory, or one above it.
JOURNAL="$JOURNAL_DIR/issue-$ISSUE.md"

# Hand off to Python for YAML frontmatter parsing + atomic write.
# PyYAML is checked at the top — if absent, fail clearly so the caller can
# install it rather than silently producing malformed manifests.
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  echo "journal-record.sh: PyYAML not installed (apt install python3-yaml / pip install pyyaml)" >&2
  exit 2
fi

# Lock acquisition + journal read + write are all done in Python so we can
# use O_NOFOLLOW for atomic symlink rejection. Bash-level [ -L ] + exec 9>
# had a TOCTOU window where an attacker (or fork PR after `gh pr checkout`)
# could plant a symlink between the check and the redirect; Python's
# os.open(O_NOFOLLOW) refuses with ELOOP atomically. Same defense applies
# to the journal file itself — a pre-staged `.decisions/issue-N.md` symlink
# to `~/.ssh/id_rsa` (or any user-readable file) would otherwise be read
# into the new journal body and committed.
LOCKFILE="$JOURNAL.lock"

# Hand off to Python — the atomicity primitives (O_NOFOLLOW, flock, atomic
# rename, fsync) live in bin/_journal_atomic.py so they can be shared by
# flow-record-activity.sh / flow-record-evidence.sh / flow-goal-record.sh
# without triplicating ~180 lines of security-sensitive code.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

python3 - "$SCRIPT_DIR" "$JOURNAL" "$LOCKFILE" "$ISSUE" "$TYPE" "$USER_JOURNAL_DIR" "${METADATA[@]:-}" <<'PYTHON'
import sys

# Defense-in-depth: harden sys.path before importing the module, in case
# PYTHONSAFEPATH is ignored (Python <3.11). The module re-runs this filter
# but doing it here too prevents `./yaml.py` shadowing on the module import.
sys.path[:] = [p for p in sys.path if p not in ("", ".")]

script_dir = sys.argv[1]
sys.path.insert(0, script_dir)

import datetime
import os
from _journal_atomic import (
    JournalAtomicError, ensure_repo_dir, record_artifact, register_user_owned,
)

journal = sys.argv[2]
lockfile = sys.argv[3]
issue = int(sys.argv[4])
artifact_type = sys.argv[5]
register_user_owned(sys.argv[6])
metadata_args = sys.argv[7:]

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

try:
    ensure_repo_dir(os.path.dirname(journal), create=True)
    record_artifact(journal, lockfile, issue, artifact_type, metadata_args, now)
except JournalAtomicError as e:
    print(f"journal-record.sh: {e}", file=sys.stderr)
    if e.refuse:
        # Match the original two-line stderr shape on frontmatter-class refusals
        # (unclosed fence, invalid YAML, non-mapping). Single-line for symlink
        # and write-failure errors — consistent with the original code.
        print("journal-record.sh: refusing to overwrite — fix manually", file=sys.stderr)
    sys.exit(e.exit_code)

print(f"journal-record.sh: recorded {artifact_type} in {journal}", file=sys.stderr)
PYTHON
