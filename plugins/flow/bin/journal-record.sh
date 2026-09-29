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
# Exits:
#   0 — artifact recorded
#   1 — missing required argument or invalid metadata
#   2 — infrastructure error (settings unreadable, disk full, etc.)

set -euo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH
# Keep the repository out of PYTHONPATH before python3 starts: the interpreter
# imports sitecustomize from each element at startup. An isolated python3 (-I:
# it reads neither PYTHONPATH nor the working directory) keeps only elements
# that are directories outside the repository and not at or above the working
# directory, comparing directories by identity, not by how the path is spelled;
# tests/syspath-guard.test.sh has the reasons. FLOW_USER_PYTHONPATH keeps the
# original for commands run for the user.
[ -n "${FLOW_USER_PYTHONPATH+x}" ] || export FLOW_USER_PYTHONPATH="${PYTHONPATH-}"
_flow_pp=""; if [ -n "${PYTHONPATH-}" ]; then _flow_pp=$(python3 -I -c 'exec("import os, sys\ndef ids(p):\n    out = set()\n    while True:\n        try:\n            st = os.stat(p)\n        except OSError:\n            return out\n        out.add((st.st_dev, st.st_ino))\n        q = os.path.dirname(p)\n        if q == p:\n            return out\n        p = q\ntry:\n    cwd = os.getcwd()\nexcept OSError:\n    sys.exit(0)\ntop = d = cwd\nwhile True:\n    if os.path.lexists(os.path.join(d, \".git\")):\n        top = d\n        break\n    q = os.path.dirname(d)\n    if q == d:\n        break\n    d = q\nst = os.stat(top)\ntop_id = (st.st_dev, st.st_ino)\nup = ids(cwd)\nkeep = []\nfor e in os.environ.get(\"PYTHONPATH\", \"\").split(\":\"):\n    if not e.startswith(\"/\"):\n        continue\n    r = os.path.realpath(e)\n    if \":\" in r or chr(10) in r or not os.path.isdir(r):\n        continue\n    try:\n        st = os.stat(r)\n    except OSError:\n        continue\n    if (st.st_dev, st.st_ino) in up or top_id in ids(r):\n        continue\n    keep.append(r)\nsys.stdout.write(\":\".join(keep))")' 2>/dev/null) || _flow_pp=""; fi
if [ -n "$_flow_pp" ]; then export PYTHONPATH="$_flow_pp"; else unset PYTHONPATH; fi

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

# Discover journal directory via bin/cascade-resolve.sh.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JOURNAL_DIR=$("$SCRIPT_DIR/cascade-resolve.sh" --default ".decisions" '.journal.dir // empty')

# Defense-in-depth: warn (not block) when journal.dir contains ".." path
# segments. The cascade visibility is the primary defense (settings changes
# appear in PR diffs), but a path-traversal value would cause writes to
# attacker-chosen locations outside the repo.
case "$JOURNAL_DIR" in
  *..*) echo "journal-record.sh: WARN: journal.dir='$JOURNAL_DIR' contains '..' path segment — writes will land outside the repo. Verify this is intentional." >&2 ;;
esac

mkdir -p "$JOURNAL_DIR" || { echo "journal-record.sh: cannot create $JOURNAL_DIR" >&2; exit 2; }
JOURNAL="$JOURNAL_DIR/issue-$ISSUE.md"

# Hand off to Python for YAML frontmatter parsing + atomic write.
# PyYAML is checked at the top — if absent, fail clearly so the caller can
# install it rather than silently producing malformed manifests.
if ! python3 -c "import os, sys; _flow_cwd = os.path.realpath(os.getcwd()); sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]; import yaml" >/dev/null 2>&1; then
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

python3 - "$SCRIPT_DIR" "$JOURNAL" "$LOCKFILE" "$ISSUE" "$TYPE" "${METADATA[@]:-}" <<'PYTHON'
# Keep the working directory (the repository) off sys.path before any other
# import; tests/syspath-guard.test.sh has the reasons.
import os, sys
try:
    _flow_cwd = os.path.realpath(os.getcwd())
except OSError:
    _flow_cwd = None
sys.path[:] = [p for p in sys.path if p and os.path.isabs(p) and os.path.realpath(p) != _flow_cwd]
import sys

script_dir = sys.argv[1]
sys.path.insert(0, script_dir)

import datetime
from _journal_atomic import record_artifact, JournalAtomicError

journal = sys.argv[2]
lockfile = sys.argv[3]
issue = int(sys.argv[4])
artifact_type = sys.argv[5]
metadata_args = sys.argv[6:]

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

try:
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
