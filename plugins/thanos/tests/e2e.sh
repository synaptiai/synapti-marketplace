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
# fixture/after on branch `feature`. Fails when any step fails.
load_fixture() {
  local repo=$1 fx="$FIXTURES/$2"
  [ -d "$fx/after" ] || return 1
  if [ -d "$fx/before" ]; then
    cp -R "$fx/before/." "$repo/" &&
      git -C "$repo" add -A && git -C "$repo" commit -qm "before" &&
      git -C "$repo" push -q origin trunk || return 1
  fi
  git -C "$repo" checkout -qb feature &&
    cp -R "$fx/after/." "$repo/" &&
    git -C "$repo" add -A && git -C "$repo" commit -qm "change"
}

# A scenario whose setup failed stops the run and says which one, rather than
# letting its checks run against a half-built repository.
setup_failed() {
  printf 'setup failed in scenario %s; scratch files are in %s\n' "$(basename "$ART" .txt)" "$ROOT" >&2
  printf '%s passed, %s failed before the setup failure. Artifacts: %s\n' "$PASS" "$FAIL" "$ART_DIR" >&2
  exit 1
}

# Everything a run could change: the work tree (ignored files included), where
# HEAD points, every ref, the stash, and the repository's config.
repo_state() {
  git -C "$1" status --porcelain=v1 --untracked-files=all --ignored 2>&1
  git -C "$1" symbolic-ref -q HEAD 2>&1; git -C "$1" rev-parse HEAD 2>&1
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
R=$(new_repo trunk) || setup_failed
load_fixture "$R" overengineered || setup_failed
printf '# extra\n' >> "$R/app.py"
printf 'x\n' > "$R/scratch.txt"
run_snap "$R" ""
check "diff target" has_line "THANOS_TARGET=diff"
check "names trunk as the base and counts the untracked file" \
  has '^THANOS_WHAT=feature vs origin/trunk, committed and uncommitted changes \(.*changed.*, 1 untracked file\(s\)\)$'
check "reads against the merge-base" has_line "THANOS_READ=git diff $(git -C "$R" merge-base origin/trunk HEAD)"
check "lists the untracked file by absolute path" has_line "THANOS_UNTRACKED=$(real "$R")/scratch.txt"
check "prints the script path as invoked" has_line "THANOS_SCRIPT=$PLUGIN_DIR/bin/snap-target.sh"

begin no-remote-default "no argument, no remote, default branch from init.defaultBranch (T1)"
R="$ROOT/noremote"; git init -q -b trunk "$R"
printf 'a\n' > "$R/a"; git -C "$R" add a; git -C "$R" commit -qm a
git -C "$R" checkout -qb work; printf 'b\n' > "$R/b"; git -C "$R" add b; git -C "$R" commit -qm b
git -C "$R" config init.defaultBranch trunk
run_snap "$R" ""
check "diff target against trunk" has "^THANOS_WHAT=work vs trunk, "

begin default-order "the remote's HEAD wins over init.defaultBranch (T1)"
R=$(new_repo order) || setup_failed
git -C "$R" branch other
git -C "$R" config init.defaultBranch other
load_fixture "$R" small || setup_failed
run_snap "$R" ""
check "base is origin/trunk" has "^THANOS_WHAT=feature vs origin/trunk, "

begin stale-remote-head "a remote HEAD naming a branch that is gone is skipped (T1)"
R=$(new_repo stale) || setup_failed
load_fixture "$R" small || setup_failed
git -C "$R" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/gone
git -C "$R" config init.defaultBranch trunk
run_snap "$R" ""
check "falls through to origin/trunk" has "^THANOS_WHAT=feature vs origin/trunk, "

begin empty-diff "no argument, nothing changed since trunk (T2)"
R=$(new_repo empty) || setup_failed
run_snap "$R" ""
check "stops" has_line "THANOS_TARGET=none"
check "one-line reason" has_line "THANOS_NOTHING=Nothing to review: no changes against origin/trunk."
check "nothing to read" lacks "^THANOS_READ="

begin untracked-from-subdir "only an untracked file outside the current directory (T3)"
R=$(new_repo subdir) || setup_failed
mkdir -p "$R/sub"; printf 'k\n' > "$R/sub/keep"
git -C "$R" add sub/keep; git -C "$R" commit -qm keep; git -C "$R" push -q origin trunk
git -C "$R" checkout -qb feature
printf 'n\n' > "$R/new_root.py"
run_snap "$R" "" sub
check "diff target" has_line "THANOS_TARGET=diff"
check "lists the file outside the directory" has_line "THANOS_UNTRACKED=$(real "$R")/new_root.py"
check "describes the untracked file, no empty stat" has "^THANOS_WHAT=feature vs origin/trunk, committed and uncommitted changes \(1 untracked file\(s\)\)$"

begin design-doc "a Markdown file is a design document (T4)"
R=$(new_repo design) || setup_failed
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
R=$(new_repo codepath) || setup_failed
load_fixture "$R" overengineered || setup_failed
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
R=$(new_repo refs) || setup_failed
load_fixture "$R" clean || setup_failed
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
BEFORE=$(git -C "$R" rev-parse HEAD~1)
run_snap "$R" ":/change"
check "a :/<text> commit resolves" has_line "THANOS_READ=git show $SHA"
run_snap "$R" "HEAD~1..:/change"
check "a :/<text> range end resolves" has_line "THANOS_READ=git diff $BEFORE $SHA"
run_snap "$R" "HEAD^{/before}..HEAD"
check "a ^{/<text>} range end resolves" has_line "THANOS_READ=git diff $BEFORE $SHA"
run_snap "$R" "trunk...$(git -C "$R" rev-parse trunk)"
check "an empty three-dot range stops" has_line "THANOS_NOTHING=Nothing to review: trunk...$(git -C "$R" rev-parse trunk) has no changes."

begin merge-commit "a merge commit is reviewed against its first parent (T5)"
R=$(new_repo merge) || setup_failed
{ git -C "$R" checkout -qb side && printf 'b\n' > "$R/b" && git -C "$R" add b && git -C "$R" commit -qm side &&
  git -C "$R" checkout -q trunk && printf 'c\n' > "$R/c" && git -C "$R" add c && git -C "$R" commit -qm main-change &&
  git -C "$R" merge -q --no-ff --no-edit side; } || setup_failed
M=$(git -C "$R" rev-parse HEAD); P1=$(git -C "$R" rev-parse HEAD^1)
run_snap "$R" "$M"
check "merge is a diff" has_line "THANOS_TARGET=diff"
check "reads the first-parent diff" has_line "THANOS_READ=git diff $P1 $M"
check "says it is a merge" has "^THANOS_WHAT=merge commit [0-9a-f]+ .*, against its first parent \(1 file changed.*\)$"
{ git -C "$R" checkout -qb quiet && git -C "$R" commit -q --allow-empty -m quiet &&
  git -C "$R" checkout -q trunk && git -C "$R" merge -q --no-ff --no-edit quiet; } || setup_failed
Q=$(git -C "$R" rev-parse HEAD)
run_snap "$R" "$Q"
check "a merge that brought in nothing stops" has_line "THANOS_NOTHING=Nothing to review: merge commit $Q brought in no changes."

begin empty-commit "a commit with no changes stops (T2, T5)"
R=$(new_repo emptycommit) || setup_failed
git -C "$R" commit -q --allow-empty -m nothing || setup_failed
E=$(git -C "$R" rev-parse HEAD)
run_snap "$R" "$E"
check "stops with a reason" has_line "THANOS_NOTHING=Nothing to review: commit $E has no changes."

begin bad-arguments "missing paths, options and shell syntax are not reviewed or run (T5, T6)"
R=$(new_repo bad) || setup_failed
load_fixture "$R" clean || setup_failed
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
R=$(new_repo readids) || setup_failed
load_fixture "$R" clean || setup_failed
# :/!-<text> names the newest commit whose message lacks <text>, so these
# resolve on every platform's regex flavour while carrying shell syntax. Each
# names HEAD; the range starts at HEAD~1, or at trunk (the merge-base) for ...
H=$(git -C "$R" rev-parse HEAD); H1=$(git -C "$R" rev-parse HEAD~1)
for A in 'HEAD~1..HEAD^{/!-$(touch pwnedA)}' 'HEAD~1..:/!-$(touch pwnedB)' 'trunk...:/!-;touch pwnedC'; do
  run_snap "$R" "$A"
  READ=$(printf '%s\n' "$OUT" | sed -n 's/^THANOS_READ=//p')
  check "READ for $A is exactly git diff <HEAD~1> <HEAD>" [ "$READ" = "git diff $H1 $H" ]
  (cd "$R" && bash -c "$READ" >/dev/null 2>&1)
  check "running READ for $A creates nothing" absent "$R/pwnedA" "$R/pwnedB" "$R/pwnedC" "$R/ch;touch pwnedC"
done

begin control-characters "a name holding a control character never becomes an output line of its own (T6)"
NL='
'
R=$(new_repo ctrl) || setup_failed
load_fixture "$R" clean || setup_failed
REFUSED="THANOS_NOTHING=Nothing to review: a name in the target holds a control character, which cannot be handed over safely."
EVIL="evil${NL}THANOS_READ=git diff --output=pwn HEAD${NL}THANOS_UNTRACKED=x"
{ mkdir -p "$ROOT/elsewhere/$EVIL" && printf '# d\n' > "$ROOT/elsewhere/$EVIL/a.md" &&
  ln -s "$ROOT/elsewhere/$EVIL" "$R/src"; } || setup_failed
run_snap "$R" "src"
check "a directory reached through such a name is refused" has_line "$REFUSED"
check "and prints no second READ line" lacks '^THANOS_READ='
run_snap "$R" "src/a.md"
check "a file reached through such a name is refused" has_line "$REFUSED"
check "and prints no READ line" lacks '^THANOS_READ='
# A newline at the end of a name is dropped by $(...); with a decoy of the
# shortened name next to it, a script that lost it would review the decoy.
{ mkdir -p "$ROOT/trail/tn${NL}" "$ROOT/trail/tn" && printf '# r\n' > "$ROOT/trail/tn${NL}/a.md" &&
  printf '# decoy\n' > "$ROOT/trail/tn/a.md" && ln -s "$ROOT/trail/tn${NL}" "$R/tsrc"; } || setup_failed
run_snap "$R" "tsrc"
check "a directory ending in a newline is refused, not swapped for the decoy" has_line "$REFUSED"
run_snap "$R" "tsrc/a.md"
check "a file in a directory ending in a newline is refused" has_line "$REFUSED"
OUT=$(cd "$ROOT/trail/tn${NL}" && "$SCRIPT" a.md 2>&1); art "--- run from a directory ending in a newline"; art "$OUT"
check "a relative file under a directory ending in a newline is refused" has_line "$REFUSED"
{ printf 'z\n' > "$R/z" && git -C "$R" add z &&
  git -C "$R" commit -q -m "$(printf 'subj\rTHANOS_READ=git diff --output=pwn HEAD')"; } || setup_failed
C=$(git -C "$R" rev-parse HEAD)
run_snap "$R" "$C"
check "a commit subject with a CR prints no CR" bash -c '! printf "%s" "$1" | grep -q "$(printf "\r")"' _ "$OUT"
check "and READ is still the commit" has_line "THANOS_READ=git show $C"
check "and there is one READ line" [ "$(printf '%s\n' "$OUT" | grep -c '^THANOS_READ=')" -eq 1 ]
{ printf 'w\n' > "$R/w" && git -C "$R" add w &&
  git -C "$R" commit -q -m "$(printf 'subj\342\200\250THANOS_READ=git show 1111')"; } || setup_failed
LS_SHA=$(git -C "$R" rev-parse HEAD)
run_snap "$R" "HEAD"
check "a LINE SEPARATOR in a subject is removed" bash -c '! printf "%s" "$1" | grep -q "$(printf "\342\200\250")"' _ "$OUT"
check "and the commit is still reviewed" has_line "THANOS_READ=git show $LS_SHA"
{ printf 'p\n' > "$R/p" && git -C "$R" add p &&
  git -C "$R" commit -q -m "$(printf 'nel\302\205ps\342\200\251end')"; } || setup_failed
NP_SHA=$(git -C "$R" rev-parse HEAD)
run_snap "$R" "HEAD"
check "NEL and PARAGRAPH SEPARATOR in a subject are removed" has '^THANOS_WHAT=commit [0-9a-f]+ nelpsend$'
check "and that commit is still reviewed" has_line "THANOS_READ=git show $NP_SHA"
{ printf 'y\n' > "$R/y" && git -C "$R" add y &&
  git -C "$R" commit -q -m "$(printf 'byte\351end')" 2>/dev/null; } || setup_failed
BY_SHA=$(git -C "$R" rev-parse HEAD)
run_snap "$R" "HEAD"
check "a subject with a byte that is not UTF-8 is still reviewed" has_line "THANOS_READ=git show $BY_SHA"
check "and prints only THANOS lines" [ "$(printf '%s\n' "$OUT" | grep -avc '^THANOS_')" -eq 0 ]
# git cuts the subject: 98 characters and "..". The exact text ties the check
# to git's cut, which counts characters, on every platform.
LONG=$(printf '%099d' 0)é-tail-past-the-limit
{ printf 'l\n' > "$R/l" && git -C "$R" add l && git -C "$R" commit -q -m "$LONG"; } || setup_failed
run_snap "$R" "HEAD"
check "a long subject is cut by characters to 98 and .." has "^THANOS_WHAT=commit [0-9a-f]+ $(printf '%098d' 0)\.\.$"
check "and is valid UTF-8" bash -c 'printf "%s" "$1" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1' _ "$OUT"
UNTRACKED_REFUSED="THANOS_NOTHING=Nothing to review: an untracked file name holds a control character, which cannot be handed over safely; rename it or pass a ref range."
for SEP in tab:'	' ls:$'\342\200\250' ps:$'\342\200\251' nel:$'\302\205'; do
  R=$(new_repo "untracked-${SEP%%:*}") || setup_failed
  git -C "$R" checkout -qb feature || setup_failed
  printf 'u\n' > "$R/a${SEP#*:}name.txt" || setup_failed
  run_snap "$R" ""
  check "an untracked name with ${SEP%%:*} is refused" has_line "$UNTRACKED_REFUSED"
done
R=$(new_repo "nl${NL}top") || setup_failed
git -C "$R" checkout -qb feature || setup_failed
printf 'u\n' > "$R/u.txt" || setup_failed
run_snap "$R" ""
check "a repository path with a newline is refused" has_line "THANOS_NOTHING=Nothing to review: the path of this repository holds a control character, which cannot be handed over safely."
check "and lists nothing" lacks '^THANOS_UNTRACKED='
# $(...) would drop the name's last newline, so the path comes back with an x after it.
R=$(new_repo "nltrail${NL}" && printf x) || setup_failed
R=${R%x}
git -C "$R" checkout -qb feature || setup_failed
printf 'u\n' > "$R/u.txt" || setup_failed
run_snap "$R" ""
check "a repository path ending in a newline is refused" has_line "THANOS_NOTHING=Nothing to review: the path of this repository holds a control character, which cannot be handed over safely."
# In a repository with a branch to review, so an argument lost while being
# trimmed would show up as a review of the branch.
R=$(new_repo bytes) || setup_failed
load_fixture "$R" small || setup_failed
OUT=$(cd "$R" && "$SCRIPT" "$(printf 'nope\351')" 2>&1); art "--- argument that is not UTF-8"; art "$OUT"
check "an argument that is not UTF-8 is not reviewed as the branch" has_line "THANOS_TARGET=none"
# Compared as bytes: grep in a UTF-8 locale refuses the byte itself.
check "and is refused as itself, untrimmed and unchanged" \
  bash -c 'printf "%s\n" "$1" | LC_ALL=C grep -qxF -- "$2"' _ "$OUT" "THANOS_NOTHING=Nothing to review: '$(printf 'nope\351')' is not a path or a git ref."
check "and prints only THANOS lines" [ "$(printf '%s\n' "$OUT" | grep -avc '^THANOS_')" -eq 0 ]
# The script run by a relative path, from inside a directory whose name ends
# in a newline, next to a decoy of the shortened name.
{ mkdir -p "$ROOT/rel/sd${NL}" "$ROOT/rel/sd" && cp "$SCRIPT" "$ROOT/rel/sd${NL}/snap-target.sh" &&
  cp "$SCRIPT" "$ROOT/rel/sd/snap-target.sh"; } || setup_failed
OUT=$(cd "$ROOT/rel/sd${NL}" && ./snap-target.sh 2>&1); art "--- run as ./snap-target.sh"; art "$OUT"
check "a relative script path under a name ending in a newline stops" has_line "THANOS_NOTHING=Nothing to review: the path of this script holds a control character."
OUT=$(cd "$ROOT/rel" && "sd${NL}/snap-target.sh" 2>&1); art "--- run as sd<newline>/snap-target.sh"; art "$OUT"
check "a relative script path with a directory part stops too" has_line "THANOS_NOTHING=Nothing to review: the path of this script holds a control character."
# A git that fails only for the untracked listing: the end marker must be
# missing, so the run stops instead of reading as "no untracked files".
R=$(new_repo lsfail) || setup_failed
load_fixture "$R" small || setup_failed
REALGIT=$(command -v git)
{ mkdir -p "$ROOT/failgit" && printf '%s\n' '#!/bin/sh' \
    'for a in "$@"; do [ "$a" = --others ] && exit 128; done' \
    "exec '$REALGIT' \"\$@\"" > "$ROOT/failgit/git" && chmod +x "$ROOT/failgit/git"; } || setup_failed
OUT=$(cd "$R" && PATH="$ROOT/failgit:$PATH" "$SCRIPT" 2>&1); art "--- untracked listing fails"; art "$OUT"
check "a failing untracked listing stops" has_line "THANOS_NOTHING=Nothing to review: git could not list untracked files."

begin odd-names "quotes, backslashes, & and | in names and in the repository path (T3)"
R=$(new_repo 'r&x|y\z') || setup_failed
git -C "$R" checkout -qb feature
printf 'q\n' > "$R/q\"uote.txt"; printf 'b\n' > "$R/back\\slash.txt"
run_snap "$R" ""
check "lists a name with a quote exactly" has_line "THANOS_UNTRACKED=$(real "$R")/q\"uote.txt"
check "lists a name with a backslash exactly" has_line "THANOS_UNTRACKED=$(real "$R")/back\\slash.txt"
check "counts both" has '2 untracked file\(s\)\)$'
printf 's\n' > "$R/ sp.py"
run_snap "$R" " sp.py"
check "a file name with a leading space is taken as given" has_line "THANOS_READ=$(real "$R")/ sp.py"
run_snap "$R" "   "
check "a blank argument reviews the branch" has_line "THANOS_TARGET=diff"

begin paths-from-environment "CDPATH and an unreadable directory do not redirect or blank the path (T4)"
R=$(new_repo cdpath) || setup_failed
mkdir -p "$R/src" "$ROOT/cdp/src"; printf 'x\n' > "$R/src/app.py"; printf 'y\n' > "$ROOT/cdp/src/app.py"
OUT=$(cd "$R" && CDPATH="$ROOT/cdp" "$SCRIPT" src/app.py 2>&1); art "--- CDPATH set"; art "$OUT"
check "CDPATH does not move the file path" has_line "THANOS_READ=$(real "$R")/src/app.py"
OUT=$(cd "$R" && CDPATH="$ROOT/cdp" "$SCRIPT" src 2>&1); art "--- CDPATH set, directory"; art "$OUT"
check "CDPATH does not move the directory path" has_line "THANOS_READ=$(real "$R")/src"
check "and prints nothing extra" [ "$(printf '%s\n' "$OUT" | grep -vc '^THANOS_')" -eq 0 ]
if [ "$(id -u)" = 0 ]; then
  # root can enter a mode-000 directory, so the check would test nothing.
  art "SKIP an unreadable directory stops (running as root)"; printf 'SKIP: unreadable-directory check, running as root\n' >&2
else
  { mkdir -p "$R/locked" && chmod 000 "$R/locked"; } || setup_failed
  run_snap "$R" "locked"
  chmod 755 "$R/locked"
  check "an unreadable directory stops" has_line "THANOS_NOTHING=Nothing to review: cannot read 'locked'."
fi

begin default-branch-edges "the default branch falls back to main, or stops when there is none (T1)"
R="$ROOT/mainonly"
{ git init -q -b main "$R" && printf 'a\n' > "$R/a" && git -C "$R" add a && git -C "$R" commit -qm a &&
  git -C "$R" checkout -qb work && printf 'b\n' > "$R/b" && git -C "$R" add b && git -C "$R" commit -qm b; } || setup_failed
run_snap "$R" ""
check "falls back to main" has "^THANOS_WHAT=work vs main, "
R="$ROOT/nodefault"
{ git init -q -b work "$R" && printf 'a\n' > "$R/a" && git -C "$R" add a && git -C "$R" commit -qm a; } || setup_failed
run_snap "$R" ""
check "stops when no default branch exists" has_line "THANOS_NOTHING=Nothing to review: cannot detect the default branch; pass a ref range such as <base>..HEAD."

begin shallow-clone "a shallow clone missing the shared history says so (T8)"
S="$ROOT/shallow-src"
git init -q -b trunk "$S" || setup_failed
for n in 1 2 3; do
  { printf '%s\n' "$n" > "$S/f$n" && git -C "$S" add "f$n" && git -C "$S" commit -qm "c$n"; } || setup_failed
done
{ git -C "$S" checkout -q -b feature HEAD~2 && printf 'x\n' > "$S/x" && git -C "$S" add x && git -C "$S" commit -qm feat &&
  git -C "$S" checkout -q trunk &&
  git clone -q --depth 1 --no-single-branch "file://$S" "$ROOT/shallow" && git -C "$ROOT/shallow" checkout -q feature; } || setup_failed
R="$ROOT/shallow"
run_snap "$R" ""
check "says the clone is shallow" has_line "THANOS_NOTHING=Nothing to review: this is a shallow clone without the history shared with origin/trunk; fetch more history or pass a ref range."
run_snap "$R" "HEAD"
check "the oldest fetched commit is not reviewed as adding every file" has '^THANOS_NOTHING=Nothing to review: commit [0-9a-f]+ is the oldest commit in this shallow clone and its parent is missing; fetch more history\.$'
run_snap "$R" "HEAD~1..HEAD"
check "a range past the history says so" has_line "THANOS_NOTHING=Nothing to review: 'HEAD~1..HEAD' is not a path or a git ref in this shallow clone; fetch more history if it should be."
run_snap "$R" "origin/trunk...HEAD"
check "a three-dot range past the history says so" has_line "THANOS_NOTHING=Nothing to review: this is a shallow clone without the history shared by both sides of 'origin/trunk...HEAD'; fetch more history."

begin git-failures "git failures stop with a reason (T8)"
NR="$ROOT/notrepo"; mkdir -p "$NR"
run_snap "$NR" ""
check "outside a repository" has_line "THANOS_NOTHING=Nothing to review: not inside a git work tree."
run_snap "$NR" "HEAD"
check "a ref outside a repository" has_line "THANOS_NOTHING=Nothing to review: 'HEAD' is not a path, and this is not a git work tree."
R=$(new_repo bare) || setup_failed
run_snap "$ROOT/bare-origin.git" ""
check "in a bare repository" has_line "THANOS_NOTHING=Nothing to review: not inside a git work tree."
run_snap "$R" "" .git
check "inside .git" has_line "THANOS_NOTHING=Nothing to review: not inside a git work tree."
E="$ROOT/nocommits"; git init -q -b trunk "$E"
run_snap "$E" ""
check "no commits" has_line "THANOS_NOTHING=Nothing to review: this repository has no commits yet."
R=$(new_repo orphan) || setup_failed
git -C "$R" checkout -q --orphan alone; printf 'o\n' > "$R/o"; git -C "$R" add o; git -C "$R" commit -qm alone
run_snap "$R" ""
check "unrelated history" has_line "THANOS_NOTHING=Nothing to review: HEAD shares no history with origin/trunk."
run_snap "$R" "trunk...alone"
check "a three-dot range without shared history" has_line "THANOS_NOTHING=Nothing to review: the two sides of 'trunk...alone' share no history."
R=$(new_repo broken) || setup_failed
load_fixture "$R" small || setup_failed
printf 'garbage' > "$R/.git/index"
run_snap "$R" ""
check "a broken index is not a diff" has_line "THANOS_TARGET=none"
check "and says the listing failed" has_line "THANOS_NOTHING=Nothing to review: git could not list untracked files."
# A missing tree object breaks git diff while the index, and so the listing
# of untracked files, still works.
R=$(new_repo notree) || setup_failed
load_fixture "$R" small || setup_failed
T=$(git -C "$R" rev-parse "$(git -C "$R" merge-base origin/trunk HEAD)^{tree}")
rm -f "$R/.git/objects/${T:0:2}/${T:2}"
run_snap "$R" ""
check "a failing git diff is not a diff" has_line "THANOS_TARGET=none"
check "and says git diff failed" has_line "THANOS_NOTHING=Nothing to review: git diff failed on this repository."
FAKEBIN="$ROOT/fakebin"; mkdir -p "$FAKEBIN"
for T in sed dirname basename wc tr cat; do ln -s "$(command -v "$T")" "$FAKEBIN/$T"; done
OUT=$(cd "$NR" && PATH="$FAKEBIN" "$(command -v bash)" "$SCRIPT" 2>&1); art "--- git missing"; art "$OUT"
check "git missing" has_line "THANOS_NOTHING=Nothing to review: git is not installed."
ln -s "$PLUGIN_DIR/bin" "$ROOT/linked-bin"
OUT=$(cd "$NR" && "$ROOT/linked-bin/snap-target.sh" 2>&1); art "--- run through a symlink"; art "$OUT"
check "the script path is printed as invoked, so it matches the permission rule" \
  has_line "THANOS_SCRIPT=$ROOT/linked-bin/snap-target.sh"
mkdir -p "$ROOT/odd${NL}bin"; cp "$SCRIPT" "$ROOT/odd${NL}bin/snap-target.sh"
OUT=$(cd "$NR" && "$ROOT/odd${NL}bin/snap-target.sh" 2>&1); art "--- script under a name with a newline"; art "$OUT"
check "a script path with a control character stops" has_line "THANOS_NOTHING=Nothing to review: the path of this script holds a control character."
check "and prints no THANOS_SCRIPT line" lacks '^THANOS_SCRIPT='
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
  R=$(new_repo live-over) || setup_failed; load_fixture "$R" overengineered || setup_failed
  review overengineered "$R" "/thanos:snap"
  check "unused abstraction is the top Snap item" \
    bash -c 'printf "%s\n" "$1" | awk "/^## The Snap/{on=1;next} on&&/^2\\. |^## /{exit} on" | grep -qiE "Notifier|interface|factory|abstract"' _ "$OUT"

  R=$(new_repo live-clean) || setup_failed; load_fixture "$R" clean || setup_failed
  review clean "$R" "/thanos:snap"
  check "verdict is INEVITABLE" has '^## Verdict: INEVITABLE'
  check "no invented cuts" bash -c '! printf "%s\n" "$1" | awk "/^## The Snap/{on=1;next} /^## /{on=0} on" | grep -qE "^[0-9]+\\. "' _ "$OUT"

  R=$(new_repo live-small) || setup_failed; load_fixture "$R" small || setup_failed
  review small "$R" "/thanos:snap"
  check "review is short (40 lines or fewer)" [ "$(printf '%s\n' "$OUT" | grep -c .)" -le 40 ]
  check "no architecture change proposed" lacks_i '^\*\*space\*\*|^## Out of scope'

  R=$(new_repo live-guard) || setup_failed; load_fixture "$R" guardrail || setup_failed
  review guardrail "$R" "/thanos:snap"
  check "validation, error handling and tests are not cut" \
    bash -c '! printf "%s\n" "$1" | awk "/^## The Snap/{on=1;next} /^## /{on=0} on" | grep -qiE "^[0-9]+\\. .*(remove|drop|delete|cut).*(validat|check|TransferError|raise|test)"' _ "$OUT"

  R=$(new_repo live-design) || setup_failed; cp "$FIXTURES/design/search-design.md" "$R/"
  review design "$R" "/thanos:snap search-design.md"
  check "missing non-goals is flagged" \
    has_i '(no|missing|lacks( an?)?|without( an?)?|absent)[^.]{0,30}non-?goals|non-?goals( section)? (is|are) (missing|absent)'

  R=$(new_repo live-rethink) || setup_failed; load_fixture "$R" overengineered || setup_failed
  review rethink "$R" "/thanos:rethink the notifications subsystem (notifications.py)"
  # A rethink's path from here to the target is a numbered list outside The
  # Snap; a numbered Snap alone is an ordinary review.
  check "describes a stepwise path outside The Snap" \
    bash -c '[ "$(printf "%s\n" "$1" | awk "/^## The Snap/{on=1;next} /^## /{on=0} !on" | grep -cE "^ *[0-9]+\\. ")" -ge 2 ]' _ "$OUT"
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
