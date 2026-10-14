#!/usr/bin/env bash
# plugins/thanos/tests/e2e.sh — end-to-end checks for the thanos plugin.
#
# Usage:
#   plugins/thanos/tests/e2e.sh           # target resolution only (no model calls)
#   plugins/thanos/tests/e2e.sh --live    # also runs real reviews with `claude -p`
#
# Every scenario runs in a scratch git repository whose default branch is
# `trunk`, never `main`, and writes one artifact file: its inputs, the output,
# and each expectation with PASS or FAIL. Artifacts go to
# THANOS_E2E_ARTIFACT_DIR when it is set, otherwise to a temporary directory
# whose path is printed at the end.
#
# Ways the target resolution in commands/snap.md could fail, written down
# before the scenarios:
#   T1 assumes `main`, so a repo whose default branch is `trunk` reviews nothing
#      or the wrong diff
#   T2 an empty diff is handed to the reviewer instead of stopping in one line
#   T3 uncommitted or untracked changes are left out of the default review
#   T4 a Markdown file is reviewed as code, or a code path as a design doc
#   T5 a ref range or commit SHA is not recognised, or a missing path is
#      treated as something to review
#   T6 an argument starting with `-` reaches git as an option (git diff
#      --output=<file> writes to disk), or shell syntax in the argument runs
#   T7 any run changes the repository (read-only must hold)
#
# The live scenarios check review quality against the acceptance criteria in
# the plugin README. A model's wording varies, so they assert on structure and
# on the specific facts each fixture is built to surface; read the saved
# reviews too.

set -uo pipefail
unset CDPATH

HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN_DIR=$(cd "$HERE/.." && pwd)
SNAP_MD="$PLUGIN_DIR/commands/snap.md"
FIXTURES="$HERE/fixtures"
LIVE=0
[ "${1:-}" = "--live" ] && LIVE=1

ROOT=$(mktemp -d -t thanos-e2e.XXXXXX)
ART_DIR="${THANOS_E2E_ARTIFACT_DIR:-$ROOT/artifacts}"
mkdir -p "$ART_DIR"
PASS=0
FAIL=0

SHELLS=bash
command -v zsh >/dev/null 2>&1 && SHELLS="bash zsh"

# --- scaffolding -----------------------------------------------------------

export GIT_AUTHOR_NAME=e2e GIT_AUTHOR_EMAIL=e2e@example.com
export GIT_COMMITTER_NAME=e2e GIT_COMMITTER_EMAIL=e2e@example.com
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# new_repo <name>: a repository with one commit on `trunk`, cloned so that
# origin/HEAD points at trunk the way a real clone does. Prints its path.
new_repo() {
  local seed="$ROOT/$1-seed" repo="$ROOT/$1"
  git init -q -b trunk "$seed"
  printf 'seed\n' > "$seed/README"
  git -C "$seed" add README && git -C "$seed" commit -qm "seed"
  git clone -q --bare "$seed" "$ROOT/$1-origin.git"
  git clone -q "$ROOT/$1-origin.git" "$repo"
  printf '%s' "$repo"
}

# load_fixture <repo> <fixture>: commits fixture/before on trunk, then commits
# fixture/after on branch `feature`.
load_fixture() {
  local repo=$1 fx="$FIXTURES/$2"
  if [ -d "$fx/before" ]; then
    cp -R "$fx/before/." "$repo/"
    git -C "$repo" add -A && git -C "$repo" commit -qm "before"
    git -C "$repo" push -q origin trunk
  fi
  git -C "$repo" checkout -qb feature
  cp -R "$fx/after/." "$repo/"
  git -C "$repo" add -A && git -C "$repo" commit -qm "change"
}

repo_state() { git -C "$1" status --porcelain=v1 --untracked-files=all; git -C "$1" rev-parse HEAD; git -C "$1" stash list; }

# The `!` fence from snap.md with the arguments substituted as Claude Code does;
# it runs bin/snap-target.sh from CLAUDE_PLUGIN_ROOT.
snap_block() {
  awk '/^```!$/{on=1; next} on && /^```$/{exit} on{print}' "$SNAP_MD" |
    ARGS="$1" awk '{gsub(/\$ARGUMENTS/, ENVIRON["ARGS"]); print}'
}

ART=""
art() { printf '%s\n' "$*" >> "$ART"; }
begin() { ART="$ART_DIR/$1.txt"; : > "$ART"; art "scenario: $1"; art "purpose: $2"; }
check() { # check <description> <command...>
  local d=$1; shift
  if "$@"; then PASS=$((PASS + 1)); art "PASS $d"
  else FAIL=$((FAIL + 1)); art "FAIL $d"; printf 'FAIL %s: %s\n' "$(basename "$ART" .txt)" "$d" >&2; fi
}
has_line() { printf '%s\n' "$OUT" | grep -qxF -- "$1"; }
has() { printf '%s\n' "$OUT" | grep -qE -- "$1"; }
lacks() { ! printf '%s\n' "$OUT" | grep -qE -- "$1"; }
has_i() { printf '%s\n' "$OUT" | grep -qiE -- "$1"; }
lacks_i() { ! printf '%s\n' "$OUT" | grep -qiE -- "$1"; }
absent() { local f; for f in "$@"; do [ ! -e "$f" ] || return 1; done; }

# run_snap <repo> <args>: runs the block under every shell; outputs must match.
run_snap() {
  local repo=$1 args=$2 sh first="" before after
  before=$(repo_state "$repo")
  art "args: $args"
  for sh in $SHELLS; do
    OUT=$(cd "$repo" && snap_block "$args" | CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" "$sh" 2>&1)
    art "--- output ($sh)"; art "$OUT"
    if [ -z "$first" ]; then first=$OUT
    else check "bash and $sh print the same output" [ "$first" = "$OUT" ]; fi
  done
  after=$(repo_state "$repo")
  check "repository unchanged (T7)" [ "$before" = "$after" ]
}

# --- target resolution (no model calls) -------------------------------------

begin default-branch-trunk "no argument on a branch of a repo whose default is trunk (T1, T3)"
R=$(new_repo trunk)
load_fixture "$R" overengineered
printf '# extra\n' >> "$R/app.py"
printf 'x\n' > "$R/scratch.txt"
run_snap "$R" ""
check "diff target" has_line "THANOS_TARGET=diff"
check "names trunk as the base" has "^THANOS_WHAT=feature vs origin/trunk"
check "reads against the merge-base" has_line "THANOS_READ=git diff $(git -C "$R" merge-base origin/trunk HEAD)"
check "lists the untracked file" has_line "THANOS_UNTRACKED=scratch.txt"

begin no-remote-default "no argument, no remote, default branch from init.defaultBranch (T1)"
R="$ROOT/noremote"; git init -q -b trunk "$R"
printf 'a\n' > "$R/a"; git -C "$R" add a; git -C "$R" commit -qm a
git -C "$R" checkout -qb work; printf 'b\n' > "$R/b"; git -C "$R" add b; git -C "$R" commit -qm b
git -C "$R" config init.defaultBranch trunk
run_snap "$R" ""
check "diff target against trunk" has "^THANOS_WHAT=work vs trunk"

begin empty-diff "no argument, nothing changed since trunk (T2)"
R=$(new_repo empty)
run_snap "$R" ""
check "stops" has_line "THANOS_TARGET=none"
check "one-line reason" has_line "THANOS_NOTHING=Nothing to review: no changes against origin/trunk."
check "nothing to read" lacks "^THANOS_READ="

begin design-doc "a Markdown file is a design document (T4)"
R=$(new_repo design)
cp "$FIXTURES/design/search-design.md" "$R/"
run_snap "$R" "search-design.md"
check "design target" has_line "THANOS_TARGET=design"
check "reads the file" has_line "THANOS_READ=search-design.md"

begin code-path "a code file and a directory are reviewed as they stand (T4)"
R=$(new_repo codepath)
load_fixture "$R" overengineered
mkdir -p "$R/pkg"; cp "$R/app.py" "$R/pkg/"
run_snap "$R" "notifications.py"
check "file is files target" has_line "THANOS_TARGET=files"
run_snap "$R" "pkg"
check "directory is files target" has_line "THANOS_READ=pkg"

begin ref-range "a ref range and a commit SHA (T5)"
R=$(new_repo refs)
load_fixture "$R" clean
SHA=$(git -C "$R" rev-parse HEAD)
run_snap "$R" "trunk..feature"
check "range is a diff" has_line "THANOS_READ=git diff trunk..feature"
run_snap "$R" "$SHA"
check "commit is shown" has_line "THANOS_READ=git show $SHA"
run_snap "$R" "feature..feature"
check "empty range stops" has_line "THANOS_NOTHING=Nothing to review: feature..feature has no changes."

begin bad-arguments "missing paths, options and shell syntax are not reviewed or run (T5, T6)"
R=$(new_repo bad)
load_fixture "$R" clean
run_snap "$R" "no/such/file.md"
check "missing path stops" has_line "THANOS_NOTHING=Nothing to review: 'no/such/file.md' is not a path or a git ref."
run_snap "$R" "--output=pwned.txt"
check "option is refused" has_line "THANOS_TARGET=none"
check "option wrote nothing" [ ! -e "$R/pwned.txt" ]
run_snap "$R" '$(touch pwned2) `touch pwned3`; touch pwned4'
check "shell syntax did not run" absent "$R/pwned2" "$R/pwned3" "$R/pwned4"
check "and is not reviewed" has_line "THANOS_TARGET=none"

# --- live reviews (model calls) ---------------------------------------------

# review <name> <repo> <prompt>: runs a real review with the plugin loaded and
# only read-only tools allowed, and keeps the review in the artifact.
review() {
  local name=$1 repo=$2 prompt=$3 before after
  begin "live-$name" "$prompt in fixture $name"
  before=$(repo_state "$repo")
  OUT=$(cd "$repo" && claude -p "$prompt" --plugin-dir "$PLUGIN_DIR" </dev/null \
    --allowedTools "Read" "Grep" "Glob" "Agent" "Bash(git diff:*)" "Bash(git log:*)" \
      "Bash(git show:*)" "Bash(git status:*)" "Bash(git merge-base:*)" "Bash(ls:*)" "Bash(wc:*)" 2>&1 |
    sed 's/^  //')  # Claude Code indents a subagent's hand-back by two spaces
  after=$(repo_state "$repo")
  art "--- review"; art "$OUT"
  check "repository unchanged (read-only)" [ "$before" = "$after" ]
  check "output format: title" has "^ *# Thanos review: "
  check "output format: essence" has '^\*\*Essence:\*\* '
  check "output format: verdict" has '^## Verdict: (INEVITABLE|UNBALANCED|SNAP)'
  check "every Snap item has a confidence" snap_items_have_confidence
  check "every stone is one of the six and has a confidence" stones_have_confidence
  check "no film quotes or role-play" lacks_i '(perfectly balanced|I am inevitable|dread it|snap (of )?my fingers|infinity gauntlet)'
}
section() { printf '%s\n' "$OUT" | awk -v h="$1" '$0 ~ "^## "{on=($0 ~ "^## "h)} on'; }
snap_items_have_confidence() {
  local items conf
  items=$(section "The Snap" | grep -cE '^[0-9]+\. ')
  conf=$(section "The Snap" | grep -ciE 'Confidence: *(high|medium|low)')
  [ "$items" -eq "$conf" ]
}
stones_have_confidence() {
  local stones named
  stones=$(section "Stones" | grep -cE '^\*\*')
  named=$(section "Stones" | grep -ciE '^\*\*(SOUL|MIND|REALITY|SPACE|POWER|TIME)\*\* *\((high|medium|low)\b')
  [ "$stones" -eq "$named" ]
}

if [ "$LIVE" = 1 ]; then
  R=$(new_repo live-over); load_fixture "$R" overengineered
  review overengineered "$R" "/thanos:snap"
  check "unused abstraction is the top Snap item" \
    bash -c 'printf "%s\n" "$1" | awk "/^## The Snap/{on=1;next} on&&/^2\\. |^## /{exit} on" | grep -qiE "Notifier|interface|factory|abstract"' _ "$OUT"

  R=$(new_repo live-clean); load_fixture "$R" clean
  review clean "$R" "/thanos:snap"
  check "verdict is INEVITABLE" has '^## Verdict: INEVITABLE'
  check "no invented cuts" bash -c '! printf "%s\n" "$1" | awk "/^## The Snap/{on=1;next} /^## /{on=0} on" | grep -qE "^[0-9]+\\. "' _ "$OUT"

  R=$(new_repo live-small); load_fixture "$R" small
  review small "$R" "/thanos:snap"
  check "review is short (40 lines or fewer)" [ "$(printf '%s\n' "$OUT" | grep -c .)" -le 40 ]
  check "no architecture change proposed" lacks '^\*\*Space\*\*|^## Out of scope'

  R=$(new_repo live-guard); load_fixture "$R" guardrail
  review guardrail "$R" "/thanos:snap"
  check "validation, error handling and tests are not cut" \
    bash -c '! printf "%s\n" "$1" | awk "/^## The Snap/{on=1;next} /^## /{on=0} on" | grep -qiE "^[0-9]+\\. .*(remove|drop|delete|cut).*(validat|check|TransferError|raise|test)"' _ "$OUT"

  R=$(new_repo live-design); cp "$FIXTURES/design/search-design.md" "$R/"
  review design "$R" "/thanos:snap search-design.md"
  check "missing non-goals is flagged" has_i 'non-goals|non goals'

  R=$(new_repo live-rethink); load_fixture "$R" overengineered
  review rethink "$R" "/thanos:rethink the notifications subsystem (notifications.py)"
  check "describes a stepwise path" has_i 'step|path'
fi

# Keep only the artifacts.
find "$ROOT" -mindepth 1 -maxdepth 1 ! -name artifacts -exec rm -rf {} +
[ -n "${THANOS_E2E_ARTIFACT_DIR:-}" ] && rmdir "$ROOT" 2>/dev/null
printf '%s passed, %s failed. Artifacts: %s\n' "$PASS" "$FAIL" "$ART_DIR"
[ "$FAIL" -eq 0 ]
