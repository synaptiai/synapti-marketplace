#!/usr/bin/env bash
# [flow] Record an artifact in the decision-journal manifest.
#
# Updates the YAML frontmatter on `.decisions/issue-{N}.md` (or the configured
# journal directory) with a new artifact entry. Idempotent and atomic — uses
# a temp file + rename so a crash mid-write cannot corrupt the journal.
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

ISSUE=""
TYPE=""
METADATA=()

while [ $# -gt 0 ]; do
  case "$1" in
    --issue)    ISSUE="$2"; shift 2 ;;
    --type)     TYPE="$2"; shift 2 ;;
    --metadata) METADATA+=("$2"); shift 2 ;;
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

# Discover journal directory via the settings cascade (matches log-commits.sh)
JOURNAL_DIR=".decisions"
if command -v jq >/dev/null 2>&1; then
  for SETTINGS in ".claude/settings.flow.local.json" ".claude/settings.flow.json" "$HOME/.claude/settings.flow.json" "${CLAUDE_PLUGIN_ROOT:-plugins/flow}/settings.json"; do
    if [ -f "$SETTINGS" ]; then
      DIR=$(jq -r '.journal.dir // empty' "$SETTINGS" 2>/dev/null || true)
      [ -n "$DIR" ] && JOURNAL_DIR="$DIR" && break
    fi
  done
fi

mkdir -p "$JOURNAL_DIR" || { echo "journal-record.sh: cannot create $JOURNAL_DIR" >&2; exit 2; }
JOURNAL="$JOURNAL_DIR/issue-$ISSUE.md"

# Hand off to Python for YAML frontmatter parsing + atomic write.
# PyYAML is checked at the top — if absent, fail clearly so the caller can
# install it rather than silently producing malformed manifests.
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  echo "journal-record.sh: PyYAML not installed (apt install python3-yaml / pip install pyyaml)" >&2
  exit 2
fi

python3 - "$JOURNAL" "$ISSUE" "$TYPE" "${METADATA[@]:-}" <<'PYTHON'
import os
import sys
import tempfile
import datetime

import yaml

journal = sys.argv[1]
issue = int(sys.argv[2])
artifact_type = sys.argv[3]

# Parse metadata key=value pairs (sys.argv[4:]). The empty-string sentinel from
# the bash `${METADATA[@]:-}` substitution is filtered out.
metadata = {}
for pair in sys.argv[4:]:
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

# Read existing journal, parse frontmatter if present
manifest = None
body = ""
if os.path.exists(journal):
    with open(journal, "r", encoding="utf-8") as f:
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
# directory so the rename is on the same filesystem (POSIX-atomic). If the
# write fails partway, the original journal is untouched.
journal_dir = os.path.dirname(journal) or "."
fd, tmp = tempfile.mkstemp(
    dir=journal_dir,
    prefix=os.path.basename(journal) + ".",
    suffix=".tmp",
)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(new_content)
    os.rename(tmp, journal)
except Exception as e:
    if os.path.exists(tmp):
        os.unlink(tmp)
    print(f"journal-record.sh: write failed: {e}", file=sys.stderr)
    sys.exit(2)

print(f"journal-record.sh: recorded {artifact_type} in {journal}", file=sys.stderr)
PYTHON
