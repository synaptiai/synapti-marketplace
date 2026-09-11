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
# - Body MUST include sections: Contract, Pattern Detected, Knowledge, Evidence,
#   Verification, Promotion Checklist
# - Pattern Detected, Evidence, Enforcement point and Promotion Checklist are
#   written for the promotion reviewer, so they are stripped from the promoted
#   skill and published in the pull request body instead, together with the
#   source-sessions / evidence-count / proposed frontmatter that names the
#   project the pattern was mined in. The PR body stays editable until merge;
#   a commit message would need a history rewrite.
# - --dry-run runs the real transform against a throwaway copy and prints what
#   the pull request would publish
# - The promoted body MUST be skill-shaped: Contract first, <=120 contract
#   words, <=600 body words
# - Target `plugins/flow/skills/learned/<name>/SKILL.md` MUST NOT already exist
#
# Exits:
#   0 — promotion succeeded (or dry-run completed without errors)
#   1 — validation failed (proposal malformed, refused to overwrite, etc.)
#   2 — infrastructure error (file not found, no flow checkout to promote into,
#       an unreadable checkout, gh failure)

set -euo pipefail

# Disable adding the current working directory to sys.path inside every
# python3 invocation below — see bin/validate-skill-input.sh for the
# threat-model rationale. Without this, an attacker-shipped `./yaml.py`
# at the repo root would shadow the real PyYAML on `import yaml` below.
export PYTHONSAFEPATH=1

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

# ---------------------------------------------------------------------------
# Where does the promotion land?
#
# In flow's own repository, or nowhere. /flow:learn writes proposals to a
# user-scoped directory, so they accumulate from whichever project the user
# happened to be in, and flow is almost always used from a consuming project
# rather than from the marketplace checkout. Resolving the target against the
# current repository therefore aimed the common case at the wrong place: it
# would add a plugins/flow/ tree to a project that never had one, commit, push a
# branch and open a pull request whose reviewers have no context for it, while
# the proposal never reached flow at all.
#
# Nothing caught it, because every guard in this script fires on OVERWRITING an
# existing skill and none on the target being in the wrong repository — and a
# fresh proposal name always passes that (issue #169).
#
# Resolution order, first hit wins:
#   1. FLOW_REPO_ROOT, for a checkout in a place this cannot guess.
#   2. The current repository, but only when it already contains
#      plugins/flow/skills — that is what makes it the marketplace rather than
#      a project that merely uses flow.
#   3. The repository containing this script, found by walking up from it. A
#      marketplace clone reaches its own root this way even when the user is
#      standing somewhere else entirely.
#
# A plugin installed under ~/.claude/plugins is a cache, not a checkout: it has
# no git remote to open a pull request against, so it is refused with the
# reason rather than written into.
# A checkout of flow: it holds the skills tree and git recognises it. `.git` is
# tested with -e rather than -d because a worktree and a submodule both use a
# .git FILE, and this repository has a worktree — requiring a directory rejected
# a legitimate flow checkout on all three resolution paths.
_pp_is_flow_repo() {
  [ -n "$1" ] || return 1
  [ -d "$1/plugins/flow/skills" ] || return 1
  [ -e "$1/.git" ] || return 1
  return 0
}

# Which half failed? A refusal that names the wrong cause sends the reader to
# the wrong fix: the first version reported "it has no plugins/flow/skills" for
# a worktree that plainly had one.
_pp_why_not() {
  if [ -z "$1" ]; then printf 'no path'; return; fi
  if [ ! -d "$1/plugins/flow/skills" ]; then printf 'it has no plugins/flow/skills'; return; fi
  if [ ! -e "$1/.git" ]; then printf 'it is not a git checkout (no .git)'; return; fi
  printf 'unknown'
}

FLOW_ROOT=""
PROMOTE_SOURCE=""

if [ -n "${FLOW_REPO_ROOT:-}" ]; then
  if _pp_is_flow_repo "$FLOW_REPO_ROOT"; then
    FLOW_ROOT="$FLOW_REPO_ROOT"; PROMOTE_SOURCE="FLOW_REPO_ROOT"
  else
    echo "promote-proposal.sh: FLOW_REPO_ROOT=$FLOW_REPO_ROOT is not a flow checkout — $(_pp_why_not "$FLOW_REPO_ROOT")" >&2
    exit 2
  fi
fi

CWD_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$FLOW_ROOT" ] && _pp_is_flow_repo "$CWD_ROOT"; then
  FLOW_ROOT="$CWD_ROOT"; PROMOTE_SOURCE="current repository"
fi

if [ -z "$FLOW_ROOT" ]; then
  # Resolve symlinks first. `~/bin/promote-proposal.sh -> .../plugins/flow/bin/`
  # is an ordinary install shape, and walking up from the link's own directory
  # loses this resolution path entirely. bash 3.2 has no `readlink -f`.
  _pp_src="${BASH_SOURCE[0]}"
  _pp_hops=0
  while [ -L "$_pp_src" ] && [ "$_pp_hops" -lt 32 ]; do
    _pp_target="$(readlink "$_pp_src")"
    case "$_pp_target" in
      /*) _pp_src="$_pp_target" ;;
      *)  _pp_src="$(dirname "$_pp_src")/$_pp_target" ;;
    esac
    _pp_hops=$((_pp_hops + 1))
  done
  _pp_dir="$(cd "$(dirname "$_pp_src")" && pwd)" || {
    echo "promote-proposal.sh: cannot resolve the directory of this script" >&2
    exit 2
  }
  while [ -n "$_pp_dir" ] && [ "$_pp_dir" != "/" ]; do
    if _pp_is_flow_repo "$_pp_dir"; then
      FLOW_ROOT="$_pp_dir"; PROMOTE_SOURCE="the checkout containing this script"; break
    fi
    _pp_dir="$(dirname "$_pp_dir")"
  done
  unset _pp_dir _pp_src _pp_target _pp_hops
fi

if [ -z "$FLOW_ROOT" ]; then
  echo "promote-proposal.sh: could not find a flow checkout to promote into." >&2
  if [ -n "$CWD_ROOT" ]; then
    echo "promote-proposal.sh: the current repository ($CWD_ROOT) is not one — $(_pp_why_not "$CWD_ROOT")." >&2
    echo "promote-proposal.sh: promoting here would add a plugins/flow/ tree it never had and open a pull request on it." >&2
  fi
  echo "promote-proposal.sh: clone the marketplace and re-run from there, or set FLOW_REPO_ROOT to an existing clone." >&2
  exit 2
fi

REPO_ROOT="$FLOW_ROOT"
LEARNED_DIR="$REPO_ROOT/plugins/flow/skills/learned"

if ! python3 -c "import yaml" >/dev/null 2>&1; then
  echo "promote-proposal.sh: PyYAML not installed (apt install python3-yaml / pip install pyyaml)" >&2
  exit 2
fi

# Validate the proposal AND extract its name in one Python pass. The script
# emits the validated name on stdout (for bash to consume) and any errors on
# stderr. Validation failure exits 1; infra failure exits 2.
# Both python passes below import bin/lib/proposal_sections.py so the validator
# and the transform cannot disagree about what a section is. FLOW_BIN_LIB is
# passed explicitly rather than derived inside python, because the defensive
# sys.path filter strips the script-directory entry.
# Prefer the lib beside this script — an installed copy promotes into a
# separate checkout, and the parser that validates must be the one that
# transforms. Fall back to the target checkout's copy when this script was
# invoked through a path whose sibling lib is absent.
_pp_lib_src="${BASH_SOURCE[0]}"
_pp_lib_hops=0
while [ -L "$_pp_lib_src" ] && [ "$_pp_lib_hops" -lt 32 ]; do
  _pp_lib_target="$(readlink "$_pp_lib_src")"
  case "$_pp_lib_target" in
    /*) _pp_lib_src="$_pp_lib_target" ;;
    *)  _pp_lib_src="$(dirname "$_pp_lib_src")/$_pp_lib_target" ;;
  esac
  _pp_lib_hops=$((_pp_lib_hops + 1))
done
FLOW_BIN_LIB="$(cd "$(dirname "$_pp_lib_src")" && pwd)/lib"
if [ ! -f "$FLOW_BIN_LIB/proposal_sections.py" ]; then
  FLOW_BIN_LIB="$REPO_ROOT/plugins/flow/bin/lib"
fi
unset _pp_lib_src _pp_lib_target _pp_lib_hops
if [ ! -f "$FLOW_BIN_LIB/proposal_sections.py" ]; then
  echo "promote-proposal.sh: cannot find proposal_sections.py (looked beside this script and in $REPO_ROOT/plugins/flow/bin/lib)" >&2
  exit 2
fi
export FLOW_BIN_LIB

PROPOSAL_NAME=$(python3 - "$PROPOSAL" <<'PYTHON'
import os
import sys

# Defensive sys.path filter — see bin/validate-skill-input.sh for rationale.
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
sys.path.insert(0, os.environ["FLOW_BIN_LIB"])

import proposal_sections
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

# Body section requirements per templates/skill-proposal.md.
#
# Matched as exact H2 titles through the shared parser, not as substrings. A
# substring scan accepted "## Evidence (journal citations)" and "### Evidence",
# neither of which the transform would recognise as the section to remove — so
# the proposal passed validation and shipped its journal paths inside the skill.
body = content[end + 5:]
required_sections = [
    "Contract",
    "Pattern Detected",
    "Knowledge",
    "Evidence",
    "Verification",
    "Promotion Checklist",
]
present = proposal_sections.titles(body)
missing_sections = [s for s in required_sections if s not in present]
if missing_sections:
    print(f"ERROR: proposal missing required body sections: {missing_sections}", file=sys.stderr)
    print(f"  found: {present}", file=sys.stderr)
    sys.exit(1)

if proposal_sections.unclosed_fence(body):
    print("ERROR: proposal ends inside an unterminated code fence", file=sys.stderr)
    sys.exit(1)

import re
name = fm["name"]
if not isinstance(name, str):
    print(f"ERROR: proposal name must be a string (got {type(name).__name__}: {name!r})", file=sys.stderr)
    sys.exit(1)
# fullmatch, not match: `$` also matches before a trailing newline, so
# re.match accepted "foo\n" as kebab-case. Harmless today only because command
# substitution strips it — two accidents deep for a path-construction guard.
if not re.fullmatch(r"[a-z][a-z0-9-]*", name):
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
# `[ -e ]` follows symlinks: a *dangling* attacker-pre-staged symlink at
# $TARGET would pass `[ -e ]` (false) but the subsequent `cp "$PROPOSAL"
# "$TARGET"` would write through the symlink to an arbitrary user-writable
# path. Refuse if $TARGET is a symlink in either state. Same defense
# pattern as the lockfile check in bin/journal-record.sh.
if [ -L "$TARGET" ]; then
  echo "promote-proposal.sh: refusing — $TARGET is a symlink (potential redirect attack)" >&2
  exit 1
fi
if [ -e "$TARGET" ]; then
  echo "promote-proposal.sh: refusing to overwrite existing learned skill at $TARGET" >&2
  echo "promote-proposal.sh: resolve by editing the existing skill OR renaming the proposal" >&2
  exit 1
fi
# If the target directory already exists with ANY content (even without
# SKILL.md), refuse rather than mkdir-into-it. The cleanup trap below
# `rm -rf`s `$TARGET_DIR` on pre-branch failure to roll back this run's
# partial state — without this guard, a contributor's half-finished
# hand-promotion (e.g., `references/foo.md` placed manually before
# adding SKILL.md) would be silently wiped on a python rewrite failure.
if [ -d "$TARGET_DIR" ] && [ -n "$(ls -A "$TARGET_DIR" 2>/dev/null)" ]; then
  echo "promote-proposal.sh: $TARGET_DIR exists and is non-empty — refusing to clobber" >&2
  echo "promote-proposal.sh: clear the directory or rename the proposal before retrying" >&2
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY-RUN: validation passed for '$PROPOSAL_NAME'"
  # Name the repository and how it was chosen. A dry run whose output does not
  # say where the promotion lands cannot answer the question it is asked.
  echo "DRY-RUN: flow checkout: $REPO_ROOT (resolved from $PROMOTE_SOURCE)"
  echo "DRY-RUN: would transform $PROPOSAL → $TARGET"

  # Run the real transform against a throwaway copy. Without this the dry run
  # could not detect any of the ways promotion refuses — a proposal with no
  # leading Contract or an over-budget body printed "validation passed" and
  # failed only on the real run. It also prints what the pull request will
  # publish, which is the last point before it is public.
  DR_DIR=$(mktemp -d -t flow-promote-dryrun.XXXXXX) || {
    echo "promote-proposal.sh: mktemp -d failed" >&2
    exit 2
  }
  _dr_clean() { [ -n "${DR_DIR:-}" ] && rm -r "$DR_DIR" 2>/dev/null; }
  cp "$PROPOSAL" "$DR_DIR/SKILL.md" || {
    echo "promote-proposal.sh: cannot copy the proposal for the dry run" >&2
    _dr_clean
    exit 2
  }
  if python3 "$FLOW_BIN_LIB/promote_transform.py" "$DR_DIR/SKILL.md" "$DR_DIR/evidence.md"; then
    echo "DRY-RUN: the promoted skill is well-formed"
    if [ -s "$DR_DIR/evidence.md" ]; then
      echo "DRY-RUN: this would be published in the pull request body ---"
      sed 's/^/DRY-RUN: | /' "$DR_DIR/evidence.md"
      echo "DRY-RUN: --- end of removed material"
    else
      echo "DRY-RUN: nothing would be removed from the proposal"
    fi
  else
    DR_RC=$?
    _dr_clean
    echo "DRY-RUN: the proposal would NOT promote to a well-formed skill (see above)" >&2
    exit "$DR_RC"
  fi
  _dr_clean

  echo "DRY-RUN: would create branch feature/learn-promote-$PROPOSAL_NAME"
  echo "DRY-RUN: would commit + push + open draft PR"
  exit 0
fi

# Pre-flight: clean working tree (otherwise checkout -b will mix changes in).
# -C "$REPO_ROOT" because that is now the repository being written to, which is
# not necessarily the one the caller is standing in. Without it the gate
# inspected the caller's tree: a dirty flow checkout passed and its changes were
# swept into the promotion commit, while a dirty consuming project blocked a
# promotion that had nothing to do with it.
PP_STATUS=$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null) || {
  echo "promote-proposal.sh: cannot read the working tree of $REPO_ROOT" >&2
  exit 2
}
if [ -n "$PP_STATUS" ]; then
  echo "promote-proposal.sh: the working tree of $REPO_ROOT is not clean — commit or stash before promoting" >&2
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
BRANCH_PUSHED=0
TMP_BODY=""
EVIDENCE_FILE=""
cleanup_promote() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ "$TARGET_WRITTEN" -eq 1 ] && [ "$BRANCH_CREATED" -eq 0 ]; then
    # Pre-branch failure — drop the orphan target so a retry sees a clean tree.
    echo "promote-proposal.sh: cleanup — removing orphan $TARGET_DIR (pre-branch failure)" >&2
    rm -rf "$TARGET_DIR" 2>/dev/null || true
  fi
  if [ "$rc" -ne 0 ] && [ "$BRANCH_PUSHED" -eq 1 ]; then
    # The local branch is about to be deleted, but the pushed one is not ours
    # to remove (deleting a remote branch is Tier 3). Name the recovery.
    echo "promote-proposal.sh: cleanup — '$BRANCH' was already pushed and no PR was opened." >&2
    echo "promote-proposal.sh: remove it with: git push origin --delete $BRANCH" >&2
  fi
  if [ "$rc" -ne 0 ] && [ "$BRANCH_CREATED" -eq 1 ]; then
    echo "promote-proposal.sh: cleanup — restoring '$ORIGINAL_BRANCH', dropping partial branch '$BRANCH'" >&2
    git -C "$REPO_ROOT" checkout "$ORIGINAL_BRANCH" >/dev/null 2>&1 || true
    git -C "$REPO_ROOT" branch -D "$BRANCH" >/dev/null 2>&1 || true
  fi
  if [ -n "$TMP_BODY" ]; then
    rm -f "$TMP_BODY" "$TMP_BODY.bak" 2>/dev/null || true
  fi
  if [ -n "$EVIDENCE_FILE" ]; then
    rm -f "$EVIDENCE_FILE" 2>/dev/null || true
  fi
  exit "$rc"
}
# --abbrev-ref prints the literal string HEAD on a detached checkout, which is a
# plausible state for the worktree this now supports. Restoring "HEAD" restores
# nothing, so the commit is recorded instead.
ORIGINAL_BRANCH=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD) || {
  echo "promote-proposal.sh: cannot read HEAD in $REPO_ROOT" >&2
  exit 2
}
if [ "$ORIGINAL_BRANCH" = "HEAD" ]; then
  ORIGINAL_BRANCH=$(git -C "$REPO_ROOT" rev-parse HEAD) || {
    echo "promote-proposal.sh: cannot read the detached HEAD commit in $REPO_ROOT" >&2
    exit 2
  }
fi
BRANCH="feature/learn-promote-$PROPOSAL_NAME"
trap cleanup_promote EXIT

# Copy the proposal into the learned/ directory
mkdir -p "$TARGET_DIR"
cp "$PROPOSAL" "$TARGET"
TARGET_WRITTEN=1

# Transform the proposal into a skill. Frontmatter status proposal → promoted,
# and the proposal-only sections come out: they address a reviewer deciding
# whether to promote, while the file they land in addresses an agent about to
# act. The evidence is not discarded — it is written to $EVIDENCE_FILE and goes
# into the commit message, where the audit trail belongs.
EVIDENCE_FILE=$(mktemp -t flow-promote-evidence.XXXXXX) || {
  echo "promote-proposal.sh: mktemp failed — cannot stage the removed material" >&2
  exit 2
}
[ -n "$EVIDENCE_FILE" ] || {
  echo "promote-proposal.sh: mktemp returned an empty path" >&2
  exit 2
}
python3 "$FLOW_BIN_LIB/promote_transform.py" "$TARGET" "$EVIDENCE_FILE"

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

# Read the commit message from stdin via `git commit -F -` instead of `-m`.
# `-m` interpolates `$PROPOSAL` (a user-supplied path) into a double-quoted
# bash string, which means a path containing backticks or `$(...)` would be
# evaluated as a command substitution at message-construction time. The
# upfront newline/CR rejection earlier in this script does not cover those
# metacharacters; switching to `-F -` removes the risk by construction —
# the heredoc is single-quoted-delimited (`'COMMITMSG'` would also work,
# but a here-string with `printf` keeps the substitution explicit) and git
# reads the message from stdin without re-evaluating it.
COMMIT_DATE=$(date -u +%Y-%m-%d)
{
  printf 'feat(flow): promote learned skill — %s\n\n' "$PROPOSAL_NAME"
  # basename only: the absolute path discloses the OS account name and local
  # layout in a public commit, and tells a reviewer nothing.
  printf 'Promoted from proposal: %s\n' "$(basename "$PROPOSAL")"
  printf 'Status: proposal → promoted (%s)\n\n' "$COMMIT_DATE"
  printf 'Validation passed by bin/promote-proposal.sh:\n'
  printf '%s\n' \
    '- Frontmatter: required fields present, status=proposal' \
    '- Body sections: Contract, Pattern Detected, Knowledge, Evidence, Verification, Promotion Checklist all present' \
    '- Promoted body: Contract first, <=120 contract words, <=600 body words' \
    '- Name: matches kebab-case pattern ^[a-z][a-z0-9-]*$' \
    "- Target: plugins/flow/skills/learned/$PROPOSAL_NAME/SKILL.md did not exist before promotion"
  printf '\nThe material removed from the skill is in the pull request body,\n'
  printf 'where it can still be edited before merge.\n'
} | git commit --cleanup=whitespace -F -

git push -u origin "$BRANCH"
BRANCH_PUSHED=1

# Render the PR body via a temp file. Heredoc-inside-$() with both backticks
# and apostrophes triggered bash parser ambiguity in earlier iterations; the
# temp-file approach (with sed substitution for placeholders) is unambiguous
# and matches gh's recommended `--body-file` pattern for multi-line bodies.
TMP_BODY=$(mktemp -t flow-promote-body.XXXXXX) || {
  echo "promote-proposal.sh: mktemp failed while building the PR body" >&2
  exit 2
}
# (TMP_BODY cleanup is handled by the cleanup_promote trap registered above
#  alongside branch rollback — a single trap covers both partial-state windows.)

cat > "$TMP_BODY" <<'BODYEOF'
Auto-generated draft PR by `bin/promote-proposal.sh` for the learned-skill promotion of **__NAME__**.

## Source proposal
`__PATH__`

## Validation passed
- Frontmatter: required fields present (`name`, `description`, `source-sessions`, `evidence-count`, `status`, `proposed`); status was `proposal`
- Body sections: `## Contract`, `## Pattern Detected`, `## Knowledge`, `## Evidence`, `## Verification`, `## Promotion Checklist` all present
- Promoted body is skill-shaped: `## Contract` first, at most 120 contract words and 600 body words
- Name: matches kebab-case pattern `^[a-z][a-z0-9-]*$`
- Target: `plugins/flow/skills/learned/__NAME__/SKILL.md` did not exist before promotion

## Reviewer checklist
- [ ] Pattern is general (not issue-specific) and applies to future sessions, not just the source ones
- [ ] Evidence is compelling — multiple journal entries cite the same pattern, not coincidental
- [ ] Knowledge does not duplicate an existing skill (search `plugins/flow/skills/` for overlap)
- [ ] Skill body fits within context window budget (checked mechanically at 600 words; supporting material goes in `references/`)
- [ ] The promoted body reads as instructions to an agent, not as a case for promotion. `## Pattern Detected`, `## Evidence`, `## Enforcement point` and `## Promotion Checklist` were removed by the script and appear in the commit message instead
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

# The removed material goes here rather than into the commit message. A
# proposal is mined from whatever project the author was standing in, which may
# be private, and this repository is public. In the PR body a mistake is a text
# edit; in a commit message it is a history rewrite.
if [ -s "$EVIDENCE_FILE" ]; then
  {
    printf '\n## Removed from the skill, kept for review\n\n'
    printf 'The transform removed the sections below, and the frontmatter that names\n'
    printf 'the project this pattern was mined in. Read them before marking this ready:\n'
    printf 'if any of it should not be published, edit this PR body now.\n\n'
    cat "$EVIDENCE_FILE"
  } >> "$TMP_BODY"
fi

gh pr create --draft \
  --title "feat(flow): promote learned skill — $PROPOSAL_NAME" \
  --body-file "$TMP_BODY"

echo "OK: draft PR created — review and mark ready when satisfied"
