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
# /snap resolves its target in two ways, and the scenarios drive both exactly
# as the command does: with no argument, the `!` block of commands/snap.md
# runs bin/snap-target.sh; with an argument, Claude runs the script with the
# argument as one single-quoted word, built by the rule in step 1 of
# commands/snap.md. Both run under bash and, when it is installed, zsh.
#
# Ways the target resolution could fail, written down before the scenarios:
#   T1 assumes `main`, so a repo whose default branch is `trunk` reviews nothing
#      or the wrong diff; or takes a stale remote HEAD, or the wrong source first
#   T2 an empty diff is handed to the reviewer instead of stopping in one line
#   T3 uncommitted or untracked changes are left out of the default review,
#      including untracked files outside the current directory
#   T4 a Markdown file is reviewed as code, or a code path as a design doc
#   T5 a ref range, commit SHA or merge commit is not recognised or reviewed
#      wrongly, or a missing path or unknown ref is treated as something to review
#   T6 an argument starting with `-` reaches git as an option (git diff
#      --output=<file> writes to disk); shell syntax in the argument runs,
#      including a multi-line argument; or the git command handed to the
#      reviewer carries the argument's own text
#   T7 any run changes the repository (read-only must hold)
#   T8 a git failure (no work tree, no commits, a broken index, git missing)
#      is reported as something to review
#
# The live scenarios check review quality against the plugin README ("What
# you get" and the example). A model's wording varies, so they assert on
# structure and on the specific facts each fixture is built to surface; read
# the saved reviews too.

set -uo pipefail
unset CDPATH

HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN_DIR=$(cd "$HERE/.." && pwd)
SNAP_MD="$PLUGIN_DIR/commands/snap.md"
RETHINK_MD="$PLUGIN_DIR/commands/rethink.md"
SCRIPT="$PLUGIN_DIR/bin/snap-target.sh"
FIXTURES="$HERE/fixtures"
LIVE=0
[ "${1:-}" = "--live" ] && LIVE=1

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/thanos-e2e.XXXXXX") || { printf 'cannot make a temporary directory\n' >&2; exit 1; }
ROOT=$(cd "$ROOT" && pwd -P)
ART_DIR="${THANOS_E2E_ARTIFACT_DIR:-$ROOT/artifacts}"
mkdir -p "$ART_DIR" || exit 1
trap 'printf "interrupted; scratch files are in %s\n" "$ROOT" >&2; exit 130' INT TERM
PASS=0
FAIL=0

SHELLS=bash
if command -v zsh >/dev/null 2>&1; then SHELLS="bash zsh"
else printf 'SKIP: zsh is not installed, so outputs are checked under bash only\n' >&2; fi

# --- scaffolding -----------------------------------------------------------

export GIT_AUTHOR_NAME=e2e GIT_AUTHOR_EMAIL=e2e@example.com
export GIT_COMMITTER_NAME=e2e GIT_COMMITTER_EMAIL=e2e@example.com
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# new_repo <name>: a repository with one commit on `trunk`, cloned so that
# origin/HEAD points at trunk the way a real clone does. Prints its path;
# fails when any step fails.
new_repo() {
  local seed="$ROOT/$1-seed" repo="$ROOT/$1"
  git init -q -b trunk "$seed" &&
    printf 'seed\n' > "$seed/README" &&
    git -C "$seed" add README && git -C "$seed" commit -qm "seed" &&
    git clone -q --bare "$seed" "$ROOT/$1-origin.git" &&
    git clone -q "$ROOT/$1-origin.git" "$repo" || return 1
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

# Everything a run could change: the work tree (ignored files included), every
# ref, the stash, and the repository's config.
repo_state() {
  git -C "$1" status --porcelain=v1 --untracked-files=all --ignored 2>&1
  git -C "$1" for-each-ref --format='%(refname) %(objectname)' 2>&1
  git -C "$1" stash list 2>&1
  cksum < "$1/.git/config" 2>&1
}

# The `!` block of snap.md as Claude Code runs it: ${CLAUDE_PLUGIN_ROOT}
# replaced by the plugin's path as literal text.
snap_block() {
  awk '/^```!$/{on=1; next} on && /^```$/{exit} on{print}' "$SNAP_MD" |
    ROOTDIR="$PLUGIN_DIR" awk '{
      out = ""; s = $0; k = "${CLAUDE_PLUGIN_ROOT}"
      while ((i = index(s, k)) > 0) { out = out substr(s, 1, i - 1) ENVIRON["ROOTDIR"]; s = substr(s, i + length(k)) }
      print out s }'
}

# sq <text>: <text> as one single-quoted shell word, each ' written as '\''.
sq() { local s=$1; s=${s//"'"/"'\\''"}; printf "'%s'" "$s"; }

# The command step 1 of snap.md tells Claude to run for an argument.
snap_command() { printf '%s %s' "$(sq "$SCRIPT")" "$(sq "$1")"; }

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
one_target() { [ "$(printf '%s\n' "$OUT" | grep -c '^THANOS_TARGET=')" -eq 1 ]; }
real() { (cd "$1" && pwd -P); }

# run_snap <dir> <args> [subdir]: resolves the target from <dir>/<subdir> as
# /snap does, under every shell; outputs must match. <dir> may be a work tree
# or not a repository at all.
run_snap() {
  local dir=$1 args=$2 sub=${3:-} sh first="" before="" after="" cmd isrepo=0
  [ -e "$dir/.git" ] && isrepo=1
  [ "$isrepo" = 0 ] || before=$(repo_state "$dir")
  art "args: $args"
  if [ -z "$args" ]; then cmd=$(snap_block); else cmd=$(snap_command "$args"); fi
  art "command: $cmd"
  for sh in $SHELLS; do
    OUT=$(cd "$dir/$sub" && "$sh" -c "$cmd" 2>&1)
    art "--- output ($sh)"; art "$OUT"
    if [ -z "$first" ]; then first=$OUT
    else check "bash and $sh print the same output" [ "$first" = "$OUT" ]; fi
  done
  check "exactly one THANOS_TARGET line" one_target
  check "no git message in the output" lacks '^(fatal|error|warning):'
  if [ "$isrepo" = 1 ]; then
    after=$(repo_state "$dir")
    check "repository unchanged (T7)" [ "$before" = "$after" ]
  fi
}

# --- the command files -------------------------------------------------------

begin command-files "the argument never reaches shell text the command file runs (T6)"
OUT=$(snap_block); art "--- snap.md block"; art "$OUT"
check "the block is one command" [ "$(printf '%s\n' "$OUT" | grep -c .)" -eq 1 ]
check "the block runs only the script" has_line "\"$SCRIPT\""
check "snap.md never places \$ARGUMENTS" bash -c '! grep -qF "\$ARGUMENTS" "$1"' _ "$SNAP_MD"
check "rethink.md never places \$ARGUMENTS" bash -c '! grep -qF "\$ARGUMENTS" "$1"' _ "$RETHINK_MD"
check "snap.md allows only the script and Agent" \
  grep -qxF 'allowed-tools: Agent, Bash(${CLAUDE_PLUGIN_ROOT}/bin/snap-target.sh:*)' "$SNAP_MD"
check "rethink.md allows only Agent" grep -qxF 'allowed-tools: Agent' "$RETHINK_MD"

# --- target resolution (no model calls) -------------------------------------

begin default-branch-trunk "no argument on a branch of a repo whose default is trunk (T1, T3)"
R=$(new_repo trunk) || exit 1
load_fixture "$R" overengineered
printf '# extra\n' >> "$R/app.py"
printf 'x\n' > "$R/scratch.txt"
run_snap "$R" ""
check "diff target" has_line "THANOS_TARGET=diff"
check "names trunk as the base and counts the untracked file" \
  has '^THANOS_WHAT=feature vs origin/trunk, committed and uncommitted changes \(.*changed.*, 1 untracked file\(s\)\)$'
check "reads against the merge-base" has_line "THANOS_READ=git diff $(git -C "$R" merge-base origin/trunk HEAD)"
check "lists the untracked file by absolute path" has_line "THANOS_UNTRACKED=$(real "$R")/scratch.txt"
check "prints the script path" has_line "THANOS_SCRIPT=$(real "$PLUGIN_DIR/bin")/snap-target.sh"

begin no-remote-default "no argument, no remote, default branch from init.defaultBranch (T1)"
R="$ROOT/noremote"; git init -q -b trunk "$R"
printf 'a\n' > "$R/a"; git -C "$R" add a; git -C "$R" commit -qm a
git -C "$R" checkout -qb work; printf 'b\n' > "$R/b"; git -C "$R" add b; git -C "$R" commit -qm b
git -C "$R" config init.defaultBranch trunk
run_snap "$R" ""
check "diff target against trunk" has "^THANOS_WHAT=work vs trunk, "

begin default-order "the remote's HEAD wins over init.defaultBranch (T1)"
R=$(new_repo order) || exit 1
git -C "$R" branch other
git -C "$R" config init.defaultBranch other
load_fixture "$R" small
run_snap "$R" ""
check "base is origin/trunk" has "^THANOS_WHAT=feature vs origin/trunk, "

begin stale-remote-head "a remote HEAD naming a branch that is gone is skipped (T1)"
R=$(new_repo stale) || exit 1
load_fixture "$R" small
git -C "$R" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/gone
git -C "$R" config init.defaultBranch trunk
run_snap "$R" ""
check "falls through to origin/trunk" has "^THANOS_WHAT=feature vs origin/trunk, "

begin empty-diff "no argument, nothing changed since trunk (T2)"
R=$(new_repo empty) || exit 1
run_snap "$R" ""
check "stops" has_line "THANOS_TARGET=none"
check "one-line reason" has_line "THANOS_NOTHING=Nothing to review: no changes against origin/trunk."
check "nothing to read" lacks "^THANOS_READ="

begin untracked-from-subdir "only an untracked file outside the current directory (T3)"
R=$(new_repo subdir) || exit 1
mkdir -p "$R/sub"; printf 'k\n' > "$R/sub/keep"
git -C "$R" add sub/keep; git -C "$R" commit -qm keep; git -C "$R" push -q origin trunk
git -C "$R" checkout -qb feature
printf 'n\n' > "$R/new_root.py"
run_snap "$R" "" sub
check "diff target" has_line "THANOS_TARGET=diff"
check "lists the file outside the directory" has_line "THANOS_UNTRACKED=$(real "$R")/new_root.py"
check "describes the untracked file, no empty stat" has "^THANOS_WHAT=feature vs origin/trunk, committed and uncommitted changes \(1 untracked file\(s\)\)$"

begin design-doc "a Markdown file is a design document (T4)"
R=$(new_repo design) || exit 1
cp "$FIXTURES/design/search-design.md" "$R/"
cp "$FIXTURES/design/search-design.md" "$R/NOTES.MD"
cp "$FIXTURES/design/search-design.md" "$R/plan.markdown"
run_snap "$R" "search-design.md"
check "design target" has_line "THANOS_TARGET=design"
check "describes it" has_line "THANOS_WHAT=design document search-design.md"
check "reads the file by absolute path" has_line "THANOS_READ=$(real "$R")/search-design.md"
run_snap "$R" "NOTES.MD"
check ".MD is a design document" has_line "THANOS_TARGET=design"
run_snap "$R" "plan.markdown"
check ".markdown is a design document" has_line "THANOS_TARGET=design"

begin code-path "a code file and a directory are reviewed as they stand (T4)"
R=$(new_repo codepath) || exit 1
load_fixture "$R" overengineered
mkdir -p "$R/pkg"; cp "$R/app.py" "$R/pkg/"
run_snap "$R" "notifications.py"
check "file is files target" has_line "THANOS_TARGET=files"
check "file description" has_line "THANOS_WHAT=notifications.py as it stands"
check "file read path" has_line "THANOS_READ=$(real "$R")/notifications.py"
run_snap "$R" "pkg"
check "directory is files target" has_line "THANOS_TARGET=files"
check "directory description" has_line "THANOS_WHAT=pkg as it stands"
check "directory read path" has_line "THANOS_READ=$(real "$R")/pkg"

begin ref-range "ref ranges and a commit SHA (T5)"
R=$(new_repo refs) || exit 1
load_fixture "$R" clean
SHA=$(git -C "$R" rev-parse HEAD); TRUNK=$(git -C "$R" rev-parse trunk)
run_snap "$R" "trunk..feature"
check "range is a diff" has_line "THANOS_TARGET=diff"
check "range reads commit ids" has_line "THANOS_READ=git diff $TRUNK $SHA"
check "range is described" has "^THANOS_WHAT=trunk\.\.feature \(.*changed.*\)$"
run_snap "$R" "trunk...feature"
check "three-dot range reads from the merge-base" has_line "THANOS_READ=git diff $(git -C "$R" merge-base trunk feature) $SHA"
run_snap "$R" "$SHA"
check "commit is a diff" has_line "THANOS_TARGET=diff"
check "commit is shown" has_line "THANOS_READ=git show $SHA"
check "commit is described" has "^THANOS_WHAT=commit [0-9a-f]+ change$"
run_snap "$R" "feature..feature"
check "empty range stops" has_line "THANOS_NOTHING=Nothing to review: feature..feature has no changes."
run_snap "$R" "nope..HEAD"
check "unknown range stops" has_line "THANOS_NOTHING=Nothing to review: 'nope..HEAD' is not a path or a git ref."

begin merge-commit "a merge commit is reviewed against its first parent (T5)"
R=$(new_repo merge) || exit 1
git -C "$R" checkout -qb side; printf 'b\n' > "$R/b"; git -C "$R" add b; git -C "$R" commit -qm side
git -C "$R" checkout -q trunk; printf 'c\n' > "$R/c"; git -C "$R" add c; git -C "$R" commit -qm main-change
git -C "$R" merge -q --no-ff --no-edit side
M=$(git -C "$R" rev-parse HEAD); P1=$(git -C "$R" rev-parse HEAD^1)
run_snap "$R" "$M"
check "merge is a diff" has_line "THANOS_TARGET=diff"
check "reads the first-parent diff" has_line "THANOS_READ=git diff $P1 $M"
check "says it is a merge" has "^THANOS_WHAT=merge commit [0-9a-f]+ .*, against its first parent \(1 file changed.*\)$"

begin empty-commit "a commit with no changes stops (T2, T5)"
R=$(new_repo emptycommit) || exit 1
git -C "$R" commit -q --allow-empty -m nothing
E=$(git -C "$R" rev-parse HEAD)
run_snap "$R" "$E"
check "stops with a reason" has_line "THANOS_NOTHING=Nothing to review: commit $E has no changes."

begin bad-arguments "missing paths, options and shell syntax are not reviewed or run (T5, T6)"
R=$(new_repo bad) || exit 1
load_fixture "$R" clean
run_snap "$R" "no/such/file.md"
check "missing path stops" has_line "THANOS_NOTHING=Nothing to review: 'no/such/file.md' is not a path or a git ref."
run_snap "$R" "--output=pwned.txt"
check "option is refused" has_line "THANOS_TARGET=none"
check "option wrote nothing" absent "$R/pwned.txt"
run_snap "$R" "HEAD..--output=pwned1.txt"
check "option after .. is refused" has_line "THANOS_TARGET=none"
check "and wrote nothing" absent "$R/pwned1.txt"
run_snap "$R" '$(touch pwned2) `touch pwned3`; touch pwned4'
check "shell syntax did not run" absent "$R/pwned2" "$R/pwned3" "$R/pwned4"
check "and is not reviewed" has_line "THANOS_TARGET=none"
run_snap "$R" "x'; touch pwned5; echo 'y & touch pwned6"
check "quotes and & did not run" absent "$R/pwned5" "$R/pwned6"
check "and are not reviewed" has_line "THANOS_TARGET=none"
NL='
'
run_snap "$R" "HEAD${NL}THANOS_ARGUMENTS${NL}touch pwned7${NL}: <<'THANOS_ARGUMENTS'"
check "a multi-line argument did not run" absent "$R/pwned7"
check "and is refused" has_line "THANOS_NOTHING=Nothing to review: pass one target on one line."

begin read-is-commit-ids "the git command handed to the reviewer holds only commit ids (T6)"
R=$(new_repo readids) || exit 1
load_fixture "$R" clean
# :/!-<text> names the newest commit whose message lacks <text>, so these
# resolve on every platform's regex flavour while carrying shell syntax.
for A in 'HEAD~1..HEAD^{/!-$(touch pwnedA)}' 'HEAD~1..:/!-$(touch pwnedB)' 'trunk...:/!-;touch pwnedC'; do
  run_snap "$R" "$A"
  READ=$(printf '%s\n' "$OUT" | sed -n 's/^THANOS_READ=//p')
  check "READ for $A is git diff <id> <id>" bash -c '[[ "$1" =~ ^git\ diff\ [0-9a-f]{40}\ [0-9a-f]{40}$ ]]' _ "$READ"
  (cd "$R" && bash -c "$READ" >/dev/null 2>&1)
  check "running READ for $A creates nothing" absent "$R/pwnedA" "$R/pwnedB" "$R/pwnedC" "$R/ch;touch pwnedC"
done

begin git-failures "git failures stop with a reason (T8)"
NR="$ROOT/notrepo"; mkdir -p "$NR"
run_snap "$NR" ""
check "outside a repository" has_line "THANOS_NOTHING=Nothing to review: not inside a git work tree."
run_snap "$NR" "HEAD"
check "a ref outside a repository" has_line "THANOS_NOTHING=Nothing to review: 'HEAD' is not a path, and this is not a git work tree."
R=$(new_repo bare) || exit 1
run_snap "$ROOT/bare-origin.git" ""
check "in a bare repository" has_line "THANOS_NOTHING=Nothing to review: not inside a git work tree."
run_snap "$R" "" .git
check "inside .git" has_line "THANOS_NOTHING=Nothing to review: not inside a git work tree."
E="$ROOT/nocommits"; git init -q -b trunk "$E"
run_snap "$E" ""
check "no commits" has_line "THANOS_NOTHING=Nothing to review: this repository has no commits yet."
R=$(new_repo orphan) || exit 1
git -C "$R" checkout -q --orphan alone; printf 'o\n' > "$R/o"; git -C "$R" add o; git -C "$R" commit -qm alone
run_snap "$R" ""
check "unrelated history" has_line "THANOS_NOTHING=Nothing to review: HEAD shares no history with origin/trunk."
R=$(new_repo broken) || exit 1
load_fixture "$R" small
printf 'garbage' > "$R/.git/index"
run_snap "$R" ""
check "a broken index is not a diff" has_line "THANOS_TARGET=none"
check "and says git failed" has '^THANOS_NOTHING=Nothing to review: git (diff failed|could not list)'
FAKEBIN="$ROOT/fakebin"; mkdir -p "$FAKEBIN"
for T in sed dirname basename wc tr cat; do ln -s "$(command -v "$T")" "$FAKEBIN/$T"; done
OUT=$(cd "$NR" && PATH="$FAKEBIN" "$(command -v bash)" "$SCRIPT" 2>&1); art "--- git missing"; art "$OUT"
check "git missing" has_line "THANOS_NOTHING=Nothing to review: git is not installed."
OUT=$(cd "$NR" && "$SCRIPT" a b 2>&1); art "--- two arguments"; art "$OUT"
check "two arguments are refused" has_line "THANOS_NOTHING=Nothing to review: pass one target (a ref range, a commit or a path) as one argument."

# --- live reviews (model calls) ---------------------------------------------

# review <name> <repo> <prompt>: runs a real review with the plugin loaded and
# only read-only tools allowed, and keeps the review in the artifact.
review() {
  local name=$1 repo=$2 prompt=$3 before after
  begin "live-$name" "$prompt in fixture $name"
  before=$(repo_state "$repo")
  OUT=$(cd "$repo" && claude -p "$prompt" --plugin-dir "$PLUGIN_DIR" </dev/null \
    --allowedTools "Read" "Grep" "Glob" "Agent" "Bash(git diff:*)" "Bash(git log:*)" \
      "Bash(git show:*)" "Bash(git status:*)" "Bash(git merge-base:*)" 2>&1 |
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
# The Snap section is always present (an empty Snap says so); every numbered
# item carries a confidence.
snap_items_have_confidence() {
  local items conf
  has '^## The Snap' || return 1
  items=$(section "The Snap" | grep -cE '^[0-9]+\. ')
  conf=$(section "The Snap" | grep -ciE 'Confidence: *(high|medium|low)')
  [ "$items" -eq "$conf" ]
}
# Stones are reported only when there are findings; when the section is there
# it holds at least one stone, and each is one of the six with a confidence.
stones_have_confidence() {
  local stones named
  has '^## Stones' || return 0
  stones=$(section "Stones" | grep -cE '^\*\*')
  named=$(section "Stones" | grep -ciE '^\*\*(SOUL|MIND|REALITY|SPACE|POWER|TIME)\*\* *\((high|medium|low)\b')
  [ "$stones" -gt 0 ] && [ "$stones" -eq "$named" ]
}

if [ "$LIVE" = 1 ]; then
  R=$(new_repo live-over) || exit 1; load_fixture "$R" overengineered
  review overengineered "$R" "/thanos:snap"
  check "unused abstraction is the top Snap item" \
    bash -c 'printf "%s\n" "$1" | awk "/^## The Snap/{on=1;next} on&&/^2\\. |^## /{exit} on" | grep -qiE "Notifier|interface|factory|abstract"' _ "$OUT"

  R=$(new_repo live-clean) || exit 1; load_fixture "$R" clean
  review clean "$R" "/thanos:snap"
  check "verdict is INEVITABLE" has '^## Verdict: INEVITABLE'
  check "no invented cuts" bash -c '! printf "%s\n" "$1" | awk "/^## The Snap/{on=1;next} /^## /{on=0} on" | grep -qE "^[0-9]+\\. "' _ "$OUT"

  R=$(new_repo live-small) || exit 1; load_fixture "$R" small
  review small "$R" "/thanos:snap"
  check "review is short (40 lines or fewer)" [ "$(printf '%s\n' "$OUT" | grep -c .)" -le 40 ]
  check "no architecture change proposed" lacks_i '^\*\*space\*\*|^## Out of scope'

  R=$(new_repo live-guard) || exit 1; load_fixture "$R" guardrail
  review guardrail "$R" "/thanos:snap"
  check "validation, error handling and tests are not cut" \
    bash -c '! printf "%s\n" "$1" | awk "/^## The Snap/{on=1;next} /^## /{on=0} on" | grep -qiE "^[0-9]+\\. .*(remove|drop|delete|cut).*(validat|check|TransferError|raise|test)"' _ "$OUT"

  R=$(new_repo live-design) || exit 1; cp "$FIXTURES/design/search-design.md" "$R/"
  review design "$R" "/thanos:snap search-design.md"
  check "missing non-goals is flagged" \
    has_i '(no|missing|lacks( an?)?|without( an?)?|absent)[^.]{0,30}non-?goals|non-?goals( section)? (is|are) (missing|absent)'

  R=$(new_repo live-rethink) || exit 1; load_fixture "$R" overengineered
  review rethink "$R" "/thanos:rethink the notifications subsystem (notifications.py)"
  check "describes a stepwise path as a numbered list" has '^ *[0-9]+\. '
  check "names steps" has_i '\bsteps?\b'
fi

# Keep only the artifacts, and keep everything when a check failed.
if [ "$FAIL" -eq 0 ]; then
  find "$ROOT" -mindepth 1 -maxdepth 1 ! -name artifacts -exec rm -rf {} +
  [ -n "${THANOS_E2E_ARTIFACT_DIR:-}" ] && rmdir "$ROOT" 2>/dev/null
else
  printf 'scratch repositories kept in %s\n' "$ROOT" >&2
fi
printf '%s passed, %s failed. Artifacts: %s\n' "$PASS" "$FAIL" "$ART_DIR"
[ "$FAIL" -eq 0 ]
