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
#       --metadata elements=non-goals,failure-modes,interface-contracts
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
      sed -n '2,28p' "$0" | sed 's/^# \?//'
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

python3 - "$JOURNAL" "$LOCKFILE" "$ISSUE" "$TYPE" "${METADATA[@]:-}" <<'PYTHON'
import errno
import fcntl
import os
import sys
import tempfile
import datetime

# Defensive sys.path filter for Python <3.11 where PYTHONSAFEPATH is ignored.
# Removes the empty-string entry (CWD) and any "." entries so a hostile fork's
# `./yaml.py` cannot shadow the real PyYAML on `import yaml` below.
sys.path[:] = [p for p in sys.path if p not in ("", ".")]

import yaml

journal = sys.argv[1]
lockfile = sys.argv[2]
issue = int(sys.argv[3])
artifact_type = sys.argv[4]
metadata_args = sys.argv[5:]

# Acquire an exclusive lock atomically without TOCTOU. O_NOFOLLOW makes
# os.open fail with ELOOP if `lockfile` is a symlink; O_CREAT creates the
# file if it does not exist; the open is a single syscall so an attacker
# cannot win a race between a check and a follow-up open. Mode 0o600 keeps
# the lockfile owner-only on shared hosts.
try:
    lock_fd = os.open(lockfile, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
except OSError as e:
    if e.errno in (errno.ELOOP, errno.EMLINK):
        print(f"journal-record.sh: refusing — lockfile {lockfile} is a symlink", file=sys.stderr)
        sys.exit(2)
    print(f"journal-record.sh: cannot open lockfile {lockfile}: {e}", file=sys.stderr)
    sys.exit(2)

# fcntl.flock is advisory but cooperative; all our writers go through this
# script so cooperation is guaranteed. LOCK_EX serializes same-issue writes
# while letting different-issue writes proceed in parallel.
try:
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
except OSError as e:
    print(f"journal-record.sh: cannot acquire flock on {lockfile}: {e}", file=sys.stderr)
    sys.exit(2)

# Parse metadata key=value pairs. The empty-string sentinel from the bash
# `${METADATA[@]:-}` substitution is filtered out.
metadata = {}
for pair in metadata_args:
    if not pair:
        continue
    if "=" not in pair:
        print(f"journal-record.sh: invalid metadata '{pair}' — must be key=value", file=sys.stderr)
        sys.exit(1)
    key, raw = pair.split("=", 1)
    key = key.strip()
    if not key:
        print(f"journal-record.sh: metadata key cannot be empty (in '{pair}')", file=sys.stderr)
        sys.exit(1)
    # Type-coerce known shapes: int, bool, comma-list, otherwise string.
    if "," in raw:
        value = [v.strip() for v in raw.split(",") if v.strip()]
    elif raw.isdigit():
        value = int(raw)
    elif raw.lower() in ("true", "false"):
        value = raw.lower() == "true"
    else:
        value = raw
    metadata[key] = value

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# Read existing journal, parse frontmatter if present. Use O_NOFOLLOW so a
# pre-staged symlink at `$JOURNAL_DIR/issue-N.md` (e.g., pointing at
# `~/.ssh/id_rsa` or `~/.aws/credentials`) cannot be read into the journal
# body and exfiltrated via a later commit/push. Python's `open()` follows
# symlinks; only `os.open(O_NOFOLLOW)` rejects them atomically.
manifest = None
body = ""
if os.path.lexists(journal):
    try:
        journal_fd = os.open(journal, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as e:
        if e.errno in (errno.ELOOP, errno.EMLINK):
            print(f"journal-record.sh: refusing — journal {journal} is a symlink", file=sys.stderr)
            sys.exit(2)
        print(f"journal-record.sh: cannot read journal {journal}: {e}", file=sys.stderr)
        sys.exit(2)
    with os.fdopen(journal_fd, "r", encoding="utf-8") as f:
        content = f.read()
    if content.startswith("---\n"):
        end_marker = content.find("\n---\n", 4)
        if end_marker == -1:
            # Opening `---` with no closing fence. Refusing here is consistent with
            # the YAMLError branch below: a fresh-render fallback would prepend a
            # new frontmatter to a body that itself starts with `---`, producing
            # a doubly-fenced file that parses correctly but ships the old
            # malformed content into the new body — silent corruption.
            print("journal-record.sh: existing journal has unclosed frontmatter "
                  "(opening `---` with no closing fence)", file=sys.stderr)
            print("journal-record.sh: refusing to overwrite — fix manually", file=sys.stderr)
            sys.exit(2)
        try:
            manifest = yaml.safe_load(content[4:end_marker])
        except yaml.YAMLError as e:
            print(f"journal-record.sh: existing frontmatter is invalid YAML: {e}", file=sys.stderr)
            print("journal-record.sh: refusing to overwrite — fix manually", file=sys.stderr)
            sys.exit(2)
        body = content[end_marker + 5:]
        if not isinstance(manifest, dict):
            print("journal-record.sh: existing frontmatter is not a YAML mapping",
                  file=sys.stderr)
            print("journal-record.sh: refusing to overwrite — fix manually", file=sys.stderr)
            sys.exit(2)
    else:
        body = content

if manifest is None:
    manifest = {
        "issue": issue,
        "created": now,
        "artifacts": [],
    }

# Make sure the manifest has the required top-level fields even if a partial
# manifest existed (e.g., a hand-edited file with just `issue:` declared).
manifest.setdefault("issue", issue)
manifest.setdefault("created", now)
manifest.setdefault("artifacts", [])

# Build the new artifact entry. captured_at goes second so it's the obvious
# field after type when reading top-down; per-type fields follow.
artifact = {"type": artifact_type, "captured_at": now}
artifact.update(metadata)
manifest["artifacts"].append(artifact)

# Render. sort_keys=False preserves the order we set above so manifests are
# diff-friendly across runs.
front = yaml.safe_dump(manifest, sort_keys=False, default_flow_style=False, allow_unicode=True)
new_content = f"---\n{front}---\n{body}"

# Atomic write via temp file + rename. The temp file lives in the same
# directory so the rename is on the same filesystem (POSIX-atomic). fsync
# the file before rename so a power loss between rename and durable-write
# cannot leave a zero-length journal behind; fsync the directory after so
# the rename itself is durable. If the write fails partway, the original
# journal is untouched.
journal_dir = os.path.dirname(journal) or "."
fd, tmp = tempfile.mkstemp(
    dir=journal_dir,
    prefix=os.path.basename(journal) + ".",
    suffix=".tmp",
)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(new_content)
        f.flush()
        os.fsync(f.fileno())
    os.rename(tmp, journal)
    # Durably persist the rename (best-effort — not all filesystems require it,
    # and EINVAL on platforms that disallow fsync of directory FDs is benign).
    try:
        dir_fd = os.open(journal_dir, os.O_RDONLY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    except OSError:
        pass
except Exception as e:
    if os.path.exists(tmp):
        os.unlink(tmp)
    print(f"journal-record.sh: write failed: {e}", file=sys.stderr)
    sys.exit(2)

print(f"journal-record.sh: recorded {artifact_type} in {journal}", file=sys.stderr)
PYTHON
