#!/usr/bin/env bash
# [flow] Promote a learned-skill proposal to an active skill via a draft PR.
#
# Validates a proposal file in `~/.claude/flow-proposals/` (or anywhere) against
# the skill-proposal template, copies it to `plugins/flow/skills/learned/{name}/`,
# updates the status from `proposal` → `promoted`, and opens a **draft** PR for
# human review. The PR is intentionally a draft — this script is Tier 2
# (journal-and-proceed) and **never auto-merges**. A human reviewer must mark
# the PR ready and merge it explicitly.
#
# Usage:
#   promote-proposal.sh --proposal <path> [--dry-run]
#
# Validation rules (see plugins/flow/templates/skill-proposal.md):
# - Frontmatter MUST include: name, description, source-sessions, evidence-count,
#   status, proposed
# - status MUST equal "proposal" (the script will rewrite to "promoted")
# - name MUST match kebab-case pattern `^[a-z][a-z0-9-]*$`
# - Body MUST include sections: Pattern Detected, Knowledge, Evidence,
#   Verification, Promotion Checklist
# - Target `plugins/flow/skills/learned/<name>/SKILL.md` MUST NOT already exist
#
# Exits:
#   0 — promotion succeeded (or dry-run completed without errors)
#   1 — validation failed (proposal malformed, refused to overwrite, etc.)
#   2 — infrastructure error (file not found, repo not detected, gh failure)

set -euo pipefail

PROPOSAL=""
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --proposal) PROPOSAL="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "promote-proposal.sh: unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -z "$PROPOSAL" ] && { echo "promote-proposal.sh: --proposal is required" >&2; exit 1; }
[ ! -f "$PROPOSAL" ] && { echo "promote-proposal.sh: proposal file not found: $PROPOSAL" >&2; exit 2; }

# Reject newline-bearing paths upfront. The PR-body sed substitution at the
# end of this script cannot escape literal newlines in `$PROPOSAL` cleanly,
# and by the time we reach that step we have already pushed a remote branch.
# A failed sed there would strand the remote branch with no PR. Catch it now.
case "$PROPOSAL" in
  *$'\n'*|*$'\r'*)
    echo "promote-proposal.sh: --proposal path contains a newline/carriage-return; refusing for safety" >&2
    exit 1
    ;;
esac

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "promote-proposal.sh: not inside a git repository" >&2
  exit 2
}
LEARNED_DIR="$REPO_ROOT/plugins/flow/skills/learned"

if ! python3 -c "import yaml" >/dev/null 2>&1; then
  echo "promote-proposal.sh: PyYAML not installed (apt install python3-yaml / pip install pyyaml)" >&2
  exit 2
fi

# Validate the proposal AND extract its name in one Python pass. The script
# emits the validated name on stdout (for bash to consume) and any errors on
# stderr. Validation failure exits 1; infra failure exits 2.
PROPOSAL_NAME=$(python3 - "$PROPOSAL" <<'PYTHON'
import sys
import yaml

proposal = sys.argv[1]
with open(proposal, "r", encoding="utf-8") as f:
    content = f.read()

if not content.startswith("---\n"):
    print("ERROR: proposal missing YAML frontmatter (expected leading `---`)", file=sys.stderr)
    sys.exit(1)

end = content.find("\n---\n", 4)
if end == -1:
    print("ERROR: proposal frontmatter not closed (no trailing `---`)", file=sys.stderr)
    sys.exit(1)

try:
    fm = yaml.safe_load(content[4:end])
except yaml.YAMLError as e:
    print(f"ERROR: malformed YAML frontmatter: {e}", file=sys.stderr)
    sys.exit(1)

if not isinstance(fm, dict):
    print("ERROR: frontmatter must be a YAML mapping", file=sys.stderr)
    sys.exit(1)

required_fields = ["name", "description", "source-sessions", "evidence-count", "status", "proposed"]
missing_fields = [f for f in required_fields if f not in fm]
if missing_fields:
    print(f"ERROR: proposal missing required frontmatter fields: {missing_fields}", file=sys.stderr)
    sys.exit(1)

if fm.get("status") != "proposal":
    print(f"ERROR: proposal status must be 'proposal' (got: {fm.get('status')!r})", file=sys.stderr)
    sys.exit(1)

# Body section requirements per templates/skill-proposal.md
body = content[end + 5:]
required_sections = [
    "## Pattern Detected",
    "## Knowledge",
    "## Evidence",
    "## Verification",
    "## Promotion Checklist",
]
missing_sections = [s for s in required_sections if s not in body]
if missing_sections:
    print(f"ERROR: proposal missing required body sections: {missing_sections}", file=sys.stderr)
    sys.exit(1)

import re
name = fm["name"]
if not re.match(r"^[a-z][a-z0-9-]*$", name):
    print(f"ERROR: proposal name '{name}' must be kebab-case (^[a-z][a-z0-9-]*$)", file=sys.stderr)
    sys.exit(1)

print(name)
PYTHON
) || exit $?

# Defense in depth: the python pass already validates name against
# `^[a-z][a-z0-9-]*$`, but a contributor adding a stray `print(...)` to that
# script would let a multi-line value flow through. Re-checking in bash keeps
# path-construction below safe under that drift.
if ! printf '%s' "$PROPOSAL_NAME" | grep -qE '^[a-z][a-z0-9-]*$'; then
  echo "promote-proposal.sh: invariant violated: PROPOSAL_NAME='$PROPOSAL_NAME' " \
       "failed bash-level kebab-case re-check after Python validation" >&2
  exit 2
fi

TARGET_DIR="$LEARNED_DIR/$PROPOSAL_NAME"
TARGET="$TARGET_DIR/SKILL.md"
if [ -e "$TARGET" ]; then
  echo "promote-proposal.sh: refusing to overwrite existing learned skill at $TARGET" >&2
  echo "promote-proposal.sh: resolve by editing the existing skill OR renaming the proposal" >&2
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY-RUN: validation passed for '$PROPOSAL_NAME'"
  echo "DRY-RUN: would copy $PROPOSAL → $TARGET"
  echo "DRY-RUN: would create branch feature/learn-promote-$PROPOSAL_NAME"
  echo "DRY-RUN: would commit + push + open draft PR"
  exit 0
fi

# Pre-flight: clean working tree (otherwise checkout -b will mix changes in)
if [ -n "$(git status --porcelain)" ]; then
  echo "promote-proposal.sh: working tree is not clean — commit or stash before promoting" >&2
  exit 1
fi

# Pre-flight: gh authenticated
if ! gh auth status >/dev/null 2>&1; then
  echo "promote-proposal.sh: gh CLI not authenticated — run \`gh auth login\`" >&2
  exit 2
fi

# Register cleanup BEFORE the first mutating step. Three partial-state windows
# can leak otherwise:
#   1. mkdir+cp+python rewrite (TARGET_DIR populated, no branch yet) — without
#      cleanup, a python failure leaves an orphan SKILL.md in the working tree.
#   2. After `git checkout -b` and before `git push` — push failure (network,
#      auth, branch protection) strands the user on a new branch with a
#      committed change and no automatic recovery.
#   3. After `mktemp` — TMP_BODY and (post-sed) TMP_BODY.bak can survive an
#      abort mid-substitution.
# The trap fires on any non-zero exit. We capture rc first so cleanup commands
# don't mask the original failure code propagated to the caller.
TARGET_WRITTEN=0
BRANCH_CREATED=0
TMP_BODY=""
cleanup_promote() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ "$TARGET_WRITTEN" -eq 1 ] && [ "$BRANCH_CREATED" -eq 0 ]; then
    # Pre-branch failure — drop the orphan target so a retry sees a clean tree.
    echo "promote-proposal.sh: cleanup — removing orphan $TARGET_DIR (pre-branch failure)" >&2
    rm -rf "$TARGET_DIR" 2>/dev/null || true
  fi
  if [ "$rc" -ne 0 ] && [ "$BRANCH_CREATED" -eq 1 ]; then
    echo "promote-proposal.sh: cleanup — restoring '$ORIGINAL_BRANCH', dropping partial branch '$BRANCH'" >&2
    git checkout "$ORIGINAL_BRANCH" >/dev/null 2>&1 || true
    git branch -D "$BRANCH" >/dev/null 2>&1 || true
  fi
  if [ -n "$TMP_BODY" ]; then
    rm -f "$TMP_BODY" "$TMP_BODY.bak" 2>/dev/null || true
  fi
  exit "$rc"
}
ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)
BRANCH="feature/learn-promote-$PROPOSAL_NAME"
trap cleanup_promote EXIT

# Copy the proposal into the learned/ directory
mkdir -p "$TARGET_DIR"
cp "$PROPOSAL" "$TARGET"
TARGET_WRITTEN=1

# Rewrite frontmatter status: proposal → promoted, add `promoted: <date>`
python3 - "$TARGET" <<'PYTHON'
import datetime
import sys

import yaml

target = sys.argv[1]
with open(target, "r", encoding="utf-8") as f:
    content = f.read()

end = content.find("\n---\n", 4)
fm = yaml.safe_load(content[4:end])
body = content[end + 5:]

fm["status"] = "promoted"
fm["promoted"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")

front = yaml.safe_dump(fm, sort_keys=False, default_flow_style=False, allow_unicode=True)
with open(target, "w", encoding="utf-8") as f:
    f.write(f"---\n{front}---\n{body}")
PYTHON

echo "OK: promoted '$PROPOSAL_NAME' → $TARGET"

cd "$REPO_ROOT"
DEFAULT=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")

if git show-ref --quiet "refs/heads/$BRANCH"; then
  echo "promote-proposal.sh: branch $BRANCH already exists locally — refusing to clobber" >&2
  exit 1
fi

# Keep stderr surfaced — a failed fetch otherwise produces a confusing
# "pathspec 'origin/main' did not match" error from the next command instead
# of the actual root cause.
if ! git fetch origin "$DEFAULT" >/dev/null; then
  echo "promote-proposal.sh: cannot fetch origin/$DEFAULT — check remote and network" >&2
  exit 2
fi
git checkout -b "$BRANCH" "origin/$DEFAULT"
BRANCH_CREATED=1

git add "$TARGET"
git commit -m "feat(flow): promote learned skill — $PROPOSAL_NAME

Promoted from proposal: $PROPOSAL
Status: proposal → promoted ($(date -u +%Y-%m-%d))

Validation passed by bin/promote-proposal.sh:
- Frontmatter: required fields present, status=proposal
- Body sections: Pattern Detected, Knowledge, Evidence, Verification, Promotion Checklist all present
- Name: matches kebab-case pattern ^[a-z][a-z0-9-]*\$
- Target: plugins/flow/skills/learned/$PROPOSAL_NAME/SKILL.md did not exist before promotion"

git push -u origin "$BRANCH"

# Render the PR body via a temp file. Heredoc-inside-$() with both backticks
# and apostrophes triggered bash parser ambiguity in earlier iterations; the
# temp-file approach (with sed substitution for placeholders) is unambiguous
# and matches gh's recommended `--body-file` pattern for multi-line bodies.
TMP_BODY=$(mktemp -t flow-promote-body.XXXXXX)
# (TMP_BODY cleanup is handled by the cleanup_promote trap registered above
#  alongside branch rollback — a single trap covers both partial-state windows.)

cat > "$TMP_BODY" <<'BODYEOF'
Auto-generated draft PR by `bin/promote-proposal.sh` for the learned-skill promotion of **__NAME__**.

## Source proposal
`__PATH__`

## Validation passed
- Frontmatter: required fields present (`name`, `description`, `source-sessions`, `evidence-count`, `status`, `proposed`); status was `proposal`
- Body sections: `## Pattern Detected`, `## Knowledge`, `## Evidence`, `## Verification`, `## Promotion Checklist` all present
- Name: matches kebab-case pattern `^[a-z][a-z0-9-]*$`
- Target: `plugins/flow/skills/learned/__NAME__/SKILL.md` did not exist before promotion

## Reviewer checklist
- [ ] Pattern is general (not issue-specific) and applies to future sessions, not just the source ones
- [ ] Evidence is compelling — multiple journal entries cite the same pattern, not coincidental
- [ ] Knowledge does not duplicate an existing skill (search `plugins/flow/skills/` for overlap)
- [ ] Skill body fits within context window budget (target <500 lines for the SKILL.md, supporting material in `references/`)
- [ ] Frontmatter description leads with the artifact and includes either a "MUST be consulted" or "Use when..." trigger clause

## Tier classification
This PR is **draft** by design. `bin/promote-proposal.sh` is **Tier 2** (journal-and-proceed): the script opens the PR, but never marks it ready and never merges. A human reviewer must do both explicitly. Promoting an unreviewed pattern to an active skill would let `/flow:learn` reshape Claude behavior without explicit consent — `bin/promote-proposal.sh` enforces the human review by construction.

Generated by /flow:learn promotion script.
BODYEOF

# Substitute placeholders. The `|` delimiter would be broken by a literal `|`
# in either value; `&` and `\` carry sed-replacement semantics. PROPOSAL_NAME
# is kebab-case (charset-checked twice above), so it cannot trigger any of
# these — but PROPOSAL is a user-supplied path that legally contains any of
# `| & \`. Escape defensively before the substitution; the alternative
# (Python rewrite) adds another fork+exec for a 2-line transform.
sed_escape() { printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'; }
NAME_ESC=$(sed_escape "$PROPOSAL_NAME")
PATH_ESC=$(sed_escape "$PROPOSAL")

sed -i.bak \
    -e "s|__NAME__|$NAME_ESC|g" \
    -e "s|__PATH__|$PATH_ESC|g" \
    "$TMP_BODY"
rm -f "$TMP_BODY.bak"

gh pr create --draft \
  --title "feat(flow): promote learned skill — $PROPOSAL_NAME" \
  --body-file "$TMP_BODY"

echo "OK: draft PR created — review and mark ready when satisfied"
