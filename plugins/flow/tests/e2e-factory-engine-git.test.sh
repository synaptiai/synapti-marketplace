# shellcheck shell=bash
# The factory engine's hardened git (bin/_flow_factory_git.py): tree_dirty,
# the snapshot of a dirty job clone (untracked files included), the reset and
# clean, the comparison of the clone's git config with its prepare copy, and
# the copy of the job's refs into the main checkout. Driven through fe_py on
# job clones made by fe_job_clone, every git command inside the scratch root
# with the scratch HOME.
#
# Ways it can be wrong, written down before the checks:
#   G1 the snapshot leaves out untracked files (plain `git stash create`, or
#      `add -u`), which the clean step then deletes; or it takes ignored
#      files; or the reset leaves the tree dirty; or the snapshot's parent is
#      not HEAD
#   G2 k does not increase: a second snapshot overwrites snapshot-1
#   G3 tree_dirty counts flow lock files, runs/, watch/, auto-log/ or the
#      finalize paths (the issue's journal and the job's goal file); or the
#      excludes are so wide that a nested lock (.claude/sub/y.lock) or another
#      issue's journal no longer counts
#   G4 a core.fsmonitor or core.hooksPath planted in the clone's config runs
#   G5 a filter added to the clone's config after prepare runs on `add -A`,
#      or on any other git command in the clone (status, reset, clean, the
#      fetch of its refs)
#   G6 a missing prepare copy lets git run
#   G7 the person's global config, or FLOW_TIER_DIR and FLOW_TIER_CALL, reach
#      git
#   G8 a flow wrapper git (hooks/shims beside scripts/lib/tier-runtime.sh) is
#      used instead of the real git
#   G9 the refs do not reach the main checkout; or copy_refs_to_main runs git
#      for a job with no worktree
#   G10 a git step that fails is read as success: a failed status as a clean
#      tree, or a failed snapshot as a snapshot taken
#   G11 the engine's own git folder (F/git) is followed through a symlink,
#      or its empty-hooks/ holds a hook, or its global.config holds keys
#   G12 nested_repositories (amendment A.11) misses an untracked nested
#      repository (one with no commit, one below a tracked folder, or one
#      inside an untracked plain folder, which status lists only as that
#      folder); or lists every untracked folder, a folder named like a
#      repository without a .git entry included; or follows a symlink to a
#      repository; or runs git inside the nested repository to find out; or
#      walks an untracked folder without bound, or past its bound without
#      failing; or runs git for a job with no worktree, or without the
#      clone-config comparison

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}
source "$REPO_ROOT/plugins/flow/tests/lib/factory-e2e.sh" || {
  printf '%s\n' "cannot load tests/lib/factory-e2e.sh" >&2
  return 1 2>/dev/null; exit 1
}

# fg_setup <name> — a scenario: a main checkout holding a.txt (one),
# .gitignore (build/) and the issue's journal .decisions/issue-7.md; job
# issue-7 in build with its clone. Sets FG_F (the factory directory), FG_C
# (the clone), FG_CD (the prepare copy of the clone's config) and FG_MAIN.
fg_setup() {
  fe_new "$1"
  e2e_repo main
  _fe_in_scratch sh -c 'printf "one\n" > a.txt && printf "build/\n" > .gitignore && mkdir -p .decisions \
    && printf "journal\n" > .decisions/issue-7.md && git add -A && git commit -q -m base' \
    || _e2e_result fail "fg_setup: the base commit"
  FG_F=$(fe_factory_dir)
  mkdir -p "$FG_F" && printf '*\n' > "$FG_F/.gitignore"
  fe_job 7 build
  fe_job_clone 7
  FG_MAIN=$(cd "$E2E_REPO" && pwd -P)
  FG_C=$(jq -r .worktree "$FG_F/jobs/issue-7/job.json")
  FG_CD="$FG_F/jobs/issue-7/clone-config"
}

# fg_py <statements> — fe_py with the git module imported as g, run_cmd and
# which_real from phase 0, and F, C, CD and MAIN set.
fg_py() {
  fe_py "import json, os, shutil, subprocess, tempfile
import _flow_factory_git as g
from _flow_factory import run_cmd
F, C, CD, MAIN = '$FG_F', '$FG_C', '$FG_CD', '$FG_MAIN'
def refused(fn, *a):
    try:
        r = fn(*a)
    except g.CloneConfigChanged as e:
        return 'refused %s %s' % (e.file, e.key)
    except g.GitFailed as e:
        return 'failed %s' % e
    return 'ran %r' % (r,)
$1"
}

# fg_mask_refs — write every commit id a ref of the clone or the main
# checkout names into the artifact as <commit REF> (the first ref naming it),
# so two runs write the same artifact. Read outside the artifact.
fg_mask_refs() {
  local id ref
  { _fe_in_scratch git -C "$FG_C" for-each-ref --format='%(objectname) %(refname)'
    _fe_in_scratch git -C "$FG_MAIN" for-each-ref --format='%(objectname) %(refname)'; } 2>/dev/null |
  while read -r id ref; do
    grep -q "^$id	" "$E2E_DIR/masks" 2>/dev/null || fe_mask_text "$id" "<commit $ref>"
  done
}

# fg_git <git arguments> — git in the scratch environment, cwd the clone.
fg_git() { _e2e_exec git -C "$FG_C" "$@"; }

# fg_marker <path> <name> — write an executable script at path that touches
# $E2E_DIR/<name> and then copies stdin to stdout (a usable clean filter).
fg_marker() {
  printf '#!/bin/sh\ntouch "%s/%s"\ncat\n' "$E2E_DIR" "$2" > "$1"
  chmod +x "$1"
}

# fg_expect_absent <name> / fg_expect_present <name> — a marker file.
fg_expect_absent() {
  if [ -e "$E2E_DIR/$1" ]; then _e2e_result fail "marker $1 is absent"; else _e2e_result pass "marker $1 is absent"; fi
}
fg_expect_present() {
  if [ -e "$E2E_DIR/$1" ]; then _e2e_result pass "marker $1 is present"; else _e2e_result fail "marker $1 is present"; fi
}

_flow_test_begin "factory git: the snapshot keeps a changed tracked file and a new untracked file, then reset and clean leave a clean tree (G1, RM3, R8)"
fg_setup fg-snapshot
e2e_describe "a.txt changed from one to two, untracked new.txt (fresh), ignored build/x.log; snapshot(7, stage_failed), then reset_and_clean"
printf 'two\n' > "$FG_C/a.txt"; printf 'fresh\n' > "$FG_C/new.txt"; mkdir -p "$FG_C/build"; printf 'log\n' > "$FG_C/build/x.log"
fg_py "print('config_changed=%r' % (g.config_changed(C, CD),))
print('dirty=%s' % g.tree_dirty(F, C, CD, 7, 'issue-7-f2'))
print('ref=' + g.snapshot(F, C, CD, 7, 'stage_failed'))
g.reset_and_clean(F, C, CD)
print('dirty after=%s' % g.tree_dirty(F, C, CD, 7, 'issue-7-f2'))"
e2e_expect_equal 0 "$E2E_RC" "the driver's exit status"
e2e_expect_line "config_changed=None"
e2e_expect_line "dirty=True"
e2e_expect_line "ref=refs/flow-factory/issue-7/snapshot-1"
e2e_expect_line "dirty after=False"
fg_mask_refs
fg_git show refs/flow-factory/issue-7/snapshot-1:a.txt
e2e_expect_equal two "$E2E_OUT" "snapshot-1:a.txt"
printf 'snapshot-1:a.txt=%s\n' "$E2E_OUT" | _e2e_art
fg_git show refs/flow-factory/issue-7/snapshot-1:new.txt
e2e_expect_equal fresh "$E2E_OUT" "snapshot-1:new.txt"
printf 'snapshot-1:new.txt=%s\n' "$E2E_OUT" | _e2e_art
fg_git ls-tree -r --name-only refs/flow-factory/issue-7/snapshot-1
e2e_expect_no_line "build/x.log"
e2e_expect_line ".gitignore"
fg_git status --porcelain=v1 --untracked-files=all
e2e_expect_equal "" "$E2E_OUT" "git status after reset and clean"
[ -z "$E2E_OUT" ] && printf 'tree after reset: clean\n' | _e2e_art
if [ -f "$FG_C/build/x.log" ]; then e2e_expect_equal present present "build/x.log on disk"; printf 'build/x.log present\n' | _e2e_art
else e2e_expect_equal present absent "build/x.log on disk"; fi
fg_git rev-parse --verify -q HEAD; FG_HEAD=$E2E_OUT
fg_git rev-parse --verify -q refs/flow-factory/issue-7/snapshot-1^1
e2e_expect_equal "$FG_HEAD" "$E2E_OUT" "the snapshot's parent (HEAD)"
fg_git show -s --format=%an%n%s refs/flow-factory/issue-7/snapshot-1
e2e_expect_line "flow-factory"
e2e_expect_line "flow-factory snapshot 1: stage_failed"
fg_git cat-file -p HEAD:a.txt
e2e_expect_equal one "$E2E_OUT" "a.txt at HEAD (the reset kept HEAD)"

_flow_test_begin "factory git: a second snapshot is snapshot-2 and keeps snapshot-1 (G2)"
fg_setup fg-snapshot-k
e2e_describe "snapshot, reset, a new edit, snapshot again"
printf 'two\n' > "$FG_C/a.txt"
fg_py "print('ref=' + g.snapshot(F, C, CD, 7, 'stage_failed'))
g.reset_and_clean(F, C, CD)
open(os.path.join(C, 'a.txt'), 'w').write('three\n')
print('ref=' + g.snapshot(F, C, CD, 7, 'lease_expired'))"
e2e_expect_equal 0 "$E2E_RC" "the driver's exit status"
e2e_expect_line "ref=refs/flow-factory/issue-7/snapshot-1"
e2e_expect_line "ref=refs/flow-factory/issue-7/snapshot-2"
fg_git show refs/flow-factory/issue-7/snapshot-1:a.txt
e2e_expect_equal two "$E2E_OUT" "snapshot-1:a.txt"
fg_git show refs/flow-factory/issue-7/snapshot-2:a.txt
e2e_expect_equal three "$E2E_OUT" "snapshot-2:a.txt"

_flow_test_begin "factory git: tree_dirty leaves out flow's lock files, runs/, watch/, auto-log/ and the finalize paths, and nothing else (G3, R12, A+2)"
fg_setup fg-tree-dirty
e2e_describe "(i) only lock files, runs/, watch/, auto-log/, the issue's journal and the job's goal file changed: clean; (ii) plus src/x.py: dirty; (iii) another issue's journal: dirty; (iv) a lock file one level down in .claude/: dirty; with no goal id (null in job.json), (v) the goal file counts, (vi) the lock files alone do not"
fg_py "def w(p, t='x\n'):
    p = os.path.join(C, p)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'w').write(t)
for p in ('.decisions/issue-7.md.lock', '.flow/goals/issue-7.goal.yaml.lock', '.claude/x.lock', '.flow/runs/r.json',
          '.flow/watch/w', '.decisions/auto-log/a', '.flow/goals/issue-7-f2.goal.yaml'):
    w(p)
w('.decisions/issue-7.md', 'journal, edited\n')
print('(i) %s' % g.tree_dirty(F, C, CD, 7, 'issue-7-f2'))
for case, p in (('(ii)', 'src/x.py'), ('(iii)', '.decisions/issue-8.md'), ('(iv)', '.claude/sub/y.lock')):
    w(p)
    print('%s %s' % (case, g.tree_dirty(F, C, CD, 7, 'issue-7-f2')))
    os.remove(os.path.join(C, p))
print('(v) %s' % g.tree_dirty(F, C, CD, 7, None))
os.remove(os.path.join(C, '.flow/goals/issue-7-f2.goal.yaml'))
print('(vi) %s' % g.tree_dirty(F, C, CD, 7, None))"
e2e_expect_equal 0 "$E2E_RC" "the driver's exit status"
e2e_expect_line "(i) False"
e2e_expect_line "(v) True"
e2e_expect_line "(vi) False"
e2e_expect_line "(ii) True"
e2e_expect_line "(iii) True"
e2e_expect_line "(iv) True"

_flow_test_begin "factory git: a core.fsmonitor and a core.hooksPath in the clone's config do not run (G4)"
fg_setup fg-planted-hooks
e2e_describe "the clone's config gets core.fsmonitor (a script touching fsmonitor-ran) and core.hooksPath (a reference-transaction hook touching hook-ran), and the prepare copy is taken again after that; the raw runner shows both run, then tree_dirty, snapshot and reset_and_clean"
mkdir -p "$E2E_DIR/planted-hooks"
fg_marker "$E2E_DIR/fsmonitor.sh" fsmonitor-ran
fg_marker "$E2E_DIR/planted-hooks/reference-transaction" hook-ran
fg_git config core.fsmonitor "$E2E_DIR/fsmonitor.sh"
fg_git config core.hooksPath "$E2E_DIR/planted-hooks"
cp "$FG_C/.git/config" "$FG_CD/config"
printf 'two\n' > "$FG_C/a.txt"
# Control: the same git without the module's -c flags runs both.
fg_py "e = g.git_env(F)
git = g.real_git()
print('control status rc=%s' % run_cmd([git, 'status', '--porcelain'], C, e)[0])
print('control update-ref rc=%s' % run_cmd([git, 'update-ref', 'refs/control/x', 'HEAD'], C, e)[0])"
fg_expect_present fsmonitor-ran
fg_expect_present hook-ran
rm -f "$E2E_DIR/fsmonitor-ran" "$E2E_DIR/hook-ran"
fg_py "print('dirty=%s' % g.tree_dirty(F, C, CD, 7, 'issue-7-f2'))
print('ref=' + g.snapshot(F, C, CD, 7, 'stage_failed'))
g.reset_and_clean(F, C, CD)"
e2e_expect_equal 0 "$E2E_RC" "the driver's exit status"
e2e_expect_line "dirty=True"
e2e_expect_line "ref=refs/flow-factory/issue-7/snapshot-1"
fg_expect_absent fsmonitor-ran
fg_expect_absent hook-ran

_flow_test_begin "factory git: a filter added to the clone's config after prepare stops every git command in the clone (G5, amendment C scope 1)"
fg_setup fg-planted-filter
e2e_describe "after the prepare copy, filter.evil.clean (a script touching filter-ran) and .gitattributes '* filter=evil'; the raw runner's add -A runs it; then tree_dirty, snapshot, reset_and_clean and copy_refs_to_main each refuse, and HEAD, the refs and the files stay as they were"
fg_marker "$E2E_DIR/filter.sh" filter-ran
fg_git config filter.evil.clean "$E2E_DIR/filter.sh"
printf '* filter=evil\n' > "$FG_C/.gitattributes"
printf 'two\n' > "$FG_C/a.txt"
# Control: the module's own argv, -c flags, cwd and environment, through
# phase 0's run_cmd without the config comparison, on a temporary index.
fg_py "e = dict(g.git_env(F))
e['GIT_INDEX_FILE'] = os.path.join(tempfile.mkdtemp(), 'index')
print('control read-tree rc=%s' % run_cmd(g.git_argv(F, ['read-tree', 'HEAD']), C, e)[0])
print('control add rc=%s' % run_cmd(g.git_argv(F, ['add', '-A']), C, e)[0])"
fg_expect_present filter-ran
printf 'control: the raw runner ran the planted filter (filter-ran written)\n' | _e2e_art
rm -f "$E2E_DIR/filter-ran"
fg_mask_refs
fg_git for-each-ref --format='%(refname) %(objectname)'; FG_REFS_BEFORE=$E2E_OUT
fg_git rev-parse --verify -q HEAD; FG_HEAD=$E2E_OUT
rm -f "$E2E_DIR/filter-ran"
fg_py "print('config_changed=%r' % (g.config_changed(C, CD),))
print('tree_dirty: ' + refused(g.tree_dirty, F, C, CD, 7, 'issue-7-f2'))
print('snapshot: ' + refused(g.snapshot, F, C, CD, 7, 'stage_failed'))
print('reset_and_clean: ' + refused(g.reset_and_clean, F, C, CD))
print('copy_refs_to_main: ' + refused(g.copy_refs_to_main, F, C, MAIN, 7))
print('nested_repositories: ' + refused(g.nested_repositories, F, C))
print('git: ' + refused(g.git, F, ['status'], C, C, CD))"
e2e_expect_equal 0 "$E2E_RC" "the driver's exit status"
e2e_expect_line "config_changed=('config', 'filter.evil.clean')"
e2e_expect_line "tree_dirty: refused config filter.evil.clean"
e2e_expect_line "snapshot: refused config filter.evil.clean"
e2e_expect_line "reset_and_clean: refused config filter.evil.clean"
e2e_expect_line "copy_refs_to_main: refused config filter.evil.clean"
e2e_expect_line "nested_repositories: refused config filter.evil.clean"
e2e_expect_line "git: refused config filter.evil.clean"
fg_expect_absent filter-ran
e2e_expect_equal two "$(cat "$FG_C/a.txt")" "a.txt on disk (no reset ran)"
if [ -f "$FG_C/.gitattributes" ]; then e2e_expect_equal kept kept ".gitattributes on disk (no clean ran)"
else e2e_expect_equal kept removed ".gitattributes on disk (no clean ran)"; fi
# Read with the filter's attributes out of the way, so this check cannot run it.
mv "$FG_C/.gitattributes" "$E2E_DIR/gitattributes.aside"
fg_git for-each-ref --format='%(refname) %(objectname)'
e2e_expect_equal "$FG_REFS_BEFORE" "$E2E_OUT" "the clone's refs"
fg_git rev-parse --verify -q HEAD
e2e_expect_equal "$FG_HEAD" "$E2E_OUT" "the clone's HEAD"
_e2e_exec git -C "$FG_MAIN" for-each-ref refs/flow-factory
e2e_expect_equal "" "$E2E_OUT" "refs/flow-factory in the main checkout"
fg_expect_absent filter-ran

_flow_test_begin "factory git: with no prepare copy of the clone's config, no git runs (G6)"
fg_setup fg-no-copy
e2e_describe "J/clone-config/config deleted, then tree_dirty"
rm -f "$FG_CD/config"
fg_py "print('config_changed=%r' % (g.config_changed(C, CD),))
print('tree_dirty: ' + refused(g.tree_dirty, F, C, CD, 7, 'issue-7-f2'))"
e2e_expect_equal 0 "$E2E_RC" "the driver's exit status"
e2e_expect_line "config_changed=('config', '<no prepare copy>')"
e2e_expect_line "tree_dirty: refused config <no prepare copy>"

_flow_test_begin "factory git: git_env drops FLOW_TIER_DIR and FLOW_TIER_CALL and names the engine's own global config (G7a)"
fg_setup fg-env
e2e_describe "FLOW_TIER_DIR and FLOW_TIER_CALL set in the calling environment; git_env(F)"
fg_py "os.environ['FLOW_TIER_DIR'] = '/tmp/tier'; os.environ['FLOW_TIER_CALL'] = '1'
os.environ['GIT_DIR'] = '/elsewhere'
e = g.git_env(F)
for k in ('FLOW_TIER_DIR', 'FLOW_TIER_CALL', 'GIT_DIR'):
    print('%s %s' % (k, 'present' if k in e else 'absent'))
print('GIT_CONFIG_GLOBAL=' + os.path.relpath(e['GIT_CONFIG_GLOBAL'], F))
print('GIT_CONFIG_NOSYSTEM=' + e['GIT_CONFIG_NOSYSTEM'])
print('GIT_TERMINAL_PROMPT=' + e['GIT_TERMINAL_PROMPT'])
print('global config size=%d' % os.path.getsize(e['GIT_CONFIG_GLOBAL']))
print('empty hooks=%r' % os.listdir(os.path.join(F, 'git', 'empty-hooks')))"
e2e_expect_equal 0 "$E2E_RC" "the driver's exit status"
e2e_expect_line "FLOW_TIER_DIR absent"
e2e_expect_line "FLOW_TIER_CALL absent"
e2e_expect_line "GIT_DIR absent"
e2e_expect_line "GIT_CONFIG_GLOBAL=git/global.config"
e2e_expect_line "GIT_CONFIG_NOSYSTEM=1"
e2e_expect_line "GIT_TERMINAL_PROMPT=0"
e2e_expect_line "global config size=0"
e2e_expect_line "empty hooks=[]"

_flow_test_begin "factory git: the person's global config does not reach git (G7b)"
fg_setup fg-global-config
e2e_describe "HOME/.gitconfig with core.fsmonitor (touching fsmonitor-ran), core.attributesFile ('* filter=evil') and filter.evil.clean (touching filter-ran); the raw runner without GIT_CONFIG_GLOBAL runs the filter; then tree_dirty and snapshot"
printf 'two\n' > "$FG_C/a.txt"
fg_marker "$E2E_DIR/fsmonitor.sh" fsmonitor-ran
fg_marker "$E2E_DIR/filter.sh" filter-ran
printf '* filter=evil\n' > "$E2E_DIR/global.attributes"
printf '[core]\n\tfsmonitor = %s\n\tattributesFile = %s\n[filter "evil"]\n\tclean = %s\n' \
  "$E2E_DIR/fsmonitor.sh" "$E2E_DIR/global.attributes" "$E2E_DIR/filter.sh" > "$E2E_HOME/.gitconfig"
# Control: the module's argv without GIT_CONFIG_GLOBAL reads HOME/.gitconfig
# and runs the filter on add -A (the -c flags do not cover a filter).
fg_py "e = dict(g.git_env(F)); del e['GIT_CONFIG_GLOBAL']
e['GIT_INDEX_FILE'] = os.path.join(tempfile.mkdtemp(), 'index')
run_cmd(g.git_argv(F, ['read-tree', 'HEAD']), C, e)
print('control add rc=%s' % run_cmd(g.git_argv(F, ['add', '-A']), C, e)[0])"
fg_expect_present filter-ran
rm -f "$E2E_DIR/filter-ran" "$E2E_DIR/fsmonitor-ran"
fg_py "print('dirty=%s' % g.tree_dirty(F, C, CD, 7, 'issue-7-f2'))
print('ref=' + g.snapshot(F, C, CD, 7, 'stage_failed'))"
e2e_expect_equal 0 "$E2E_RC" "the driver's exit status"
e2e_expect_line "dirty=True"
e2e_expect_line "ref=refs/flow-factory/issue-7/snapshot-1"
fg_expect_absent filter-ran
fg_expect_absent fsmonitor-ran
rm -f "$E2E_HOME/.gitconfig"

_flow_test_begin "factory git: a flow wrapper git first on PATH is not used (G8)"
fg_setup fg-wrapper-git
e2e_describe "PATH first holds w/hooks/shims/git (touching wrapper-ran), with w/hooks/scripts/lib/tier-runtime.sh present; then tree_dirty and snapshot"
mkdir -p "$E2E_DIR/w/hooks/shims" "$E2E_DIR/w/hooks/scripts/lib"
: > "$E2E_DIR/w/hooks/scripts/lib/tier-runtime.sh"
printf '#!/bin/sh\ntouch "%s/wrapper-ran"\nexit 1\n' "$E2E_DIR" > "$E2E_DIR/w/hooks/shims/git"
chmod +x "$E2E_DIR/w/hooks/shims/git"
printf 'two\n' > "$FG_C/a.txt"
fg_py "os.environ['PATH'] = '$E2E_DIR/w/hooks/shims' + os.pathsep + os.environ['PATH']
print('first git on PATH: ' + os.path.relpath(shutil.which('git'), '$E2E_DIR'))
print('dirty=%s' % g.tree_dirty(F, C, CD, 7, 'issue-7-f2'))
print('ref=' + g.snapshot(F, C, CD, 7, 'stage_failed'))"
e2e_expect_equal 0 "$E2E_RC" "the driver's exit status"
e2e_expect_line "first git on PATH: w/hooks/shims/git"
e2e_expect_line "dirty=True"
e2e_expect_line "ref=refs/flow-factory/issue-7/snapshot-1"
fg_expect_absent wrapper-ran

_flow_test_begin "factory git: copy_refs_to_main brings the snapshot refs and the job branch into the main checkout (G9)"
fg_setup fg-copy-refs
e2e_describe "a commit on the job branch and a snapshot in the clone, then copy_refs_to_main"
printf 'committed\n' > "$FG_C/b.txt"
fg_git add b.txt; fg_git commit -q -m 'job work'
printf 'two\n' > "$FG_C/a.txt"; printf 'fresh\n' > "$FG_C/new.txt"
fg_py "print('ref=' + g.snapshot(F, C, CD, 7, 'stage_failed'))
for r in g.copy_refs_to_main(F, C, MAIN, 7):
    print('copied ' + r)"
e2e_expect_equal 0 "$E2E_RC" "the driver's exit status"
e2e_expect_line "copied refs/flow-factory/issue-7/branch"
e2e_expect_line "copied refs/flow-factory/issue-7/snapshot-1"
fg_mask_refs
fg_git rev-parse --verify -q refs/flow-factory/issue-7/snapshot-1; FG_SNAP=$E2E_OUT
fg_git rev-parse --verify -q HEAD; FG_BRANCH=$E2E_OUT
case "$FG_SNAP" in [0-9a-f]*) e2e_expect_equal yes yes "snapshot-1 resolves in the clone" ;; *) e2e_expect_equal yes "no ($FG_SNAP)" "snapshot-1 resolves in the clone" ;; esac
_e2e_exec git -C "$FG_MAIN" rev-parse --verify -q refs/flow-factory/issue-7/snapshot-1
e2e_expect_equal "$FG_SNAP" "$E2E_OUT" "refs/flow-factory/issue-7/snapshot-1 in the main checkout"
_e2e_exec git -C "$FG_MAIN" rev-parse --verify -q refs/flow-factory/issue-7/branch
e2e_expect_equal "$FG_BRANCH" "$E2E_OUT" "refs/flow-factory/issue-7/branch in the main checkout"
_e2e_exec git -C "$FG_MAIN" show refs/flow-factory/issue-7/snapshot-1:new.txt
e2e_expect_equal fresh "$E2E_OUT" "new.txt read from the main checkout's copy of the snapshot"
_e2e_exec git -C "$FG_MAIN" symbolic-ref HEAD
e2e_expect_equal refs/heads/main "$E2E_OUT" "the main checkout's branch"
_e2e_exec git -C "$FG_MAIN" status --porcelain
e2e_expect_equal "" "$E2E_OUT" "the main checkout's status"

_flow_test_begin "factory git: copy_refs_to_main runs no git for a job with no worktree (G9)"
fg_setup fg-copy-no-worktree
e2e_describe "a git that touches git-ran first on PATH (not a wrapper directory); copy_refs_to_main with clone None and with a folder that does not exist; control: the module's git() then picks that git"
mkdir -p "$E2E_DIR/fakegit"
printf '#!/bin/sh\ntouch "%s/git-ran"\nexit 0\n' "$E2E_DIR" > "$E2E_DIR/fakegit/git"
chmod +x "$E2E_DIR/fakegit/git"
fg_py "os.environ['PATH'] = '$E2E_DIR/fakegit' + os.pathsep + os.environ['PATH']
print('none: %r' % (g.copy_refs_to_main(F, None, MAIN, 7),))
print('missing: %r' % (g.copy_refs_to_main(F, '$E2E_DIR/area/worktrees/issue-9', MAIN, 7),))"
e2e_expect_equal 0 "$E2E_RC" "the driver's exit status"
e2e_expect_line "none: []"
e2e_expect_line "missing: []"
fg_expect_absent git-ran
fg_py "os.environ['PATH'] = '$E2E_DIR/fakegit' + os.pathsep + os.environ['PATH']
print('control rc=%s' % g.git(F, ['--version'], MAIN)[0])"
fg_expect_present git-ran

_flow_test_begin "factory git: a git step that fails raises, and leaves no snapshot (G10)"
fg_setup fg-git-fails
e2e_describe "the clone's .git/HEAD made unreadable to git (garbage), the config unchanged; tree_dirty and snapshot"
printf 'two\n' > "$FG_C/a.txt"
printf 'garbage\n' > "$FG_C/.git/HEAD"
fg_py "print('tree_dirty: ' + refused(g.tree_dirty, F, C, CD, 7, 'issue-7-f2').split(':')[0])
print('snapshot: ' + refused(g.snapshot, F, C, CD, 7, 'stage_failed').split(':')[0])
print('reset_and_clean: ' + refused(g.reset_and_clean, F, C, CD).split(':')[0])"
e2e_expect_equal 0 "$E2E_RC" "the driver's exit status"
e2e_expect_out "tree_dirty: failed"
e2e_expect_out "snapshot: failed"
e2e_expect_out "reset_and_clean: failed"
e2e_expect_equal two "$(cat "$FG_C/a.txt")" "a.txt on disk"
if [ -d "$FG_C/.git/refs/flow-factory" ]; then e2e_expect_equal none present "refs/flow-factory in the clone"
else e2e_expect_equal none none "refs/flow-factory in the clone"; fi

_flow_test_begin "factory git: the engine's git folder is refused through a symlink or with a hook in it, and its global config is kept empty (G11)"
fg_setup fg-git-dir
e2e_describe "(a) F/git a symlink to another folder; (b) F/git/empty-hooks holding a hook; (c) F/git/global.config holding a key"
mkdir -p "$E2E_DIR/elsewhere"
ln -s "$E2E_DIR/elsewhere" "$FG_F/git"
fg_py "print('(a) ' + refused(g.git_env, F).split(':')[0])"
e2e_expect_line "(a) failed engine_git_dir"
e2e_expect_equal "" "$(ls -A "$E2E_DIR/elsewhere")" "the symlink's target folder"
rm "$FG_F/git"
mkdir -p "$FG_F/git/empty-hooks"
printf '#!/bin/sh\n' > "$FG_F/git/empty-hooks/post-checkout"
fg_py "print('(b) ' + refused(g.git_env, F).split(':')[0])"
e2e_expect_line "(b) failed empty_hooks_not_empty"
rm "$FG_F/git/empty-hooks/post-checkout"
printf '[core]\n\tfsmonitor = /bin/true\n' > "$FG_F/git/global.config"
fg_py "e = g.git_env(F)
print('(c) global config size=%d' % os.path.getsize(e['GIT_CONFIG_GLOBAL']))"
e2e_expect_line "(c) global config size=0"

# fg_nested_driver — the G12 driver: put a recording git (it logs its working
# directory and arguments to rec/calls.log, then runs the real git) first on
# PATH, call nested_repositories on the clone, and print what it returned,
# how many git calls it made, and how many of them ran in or named a nested
# folder. Then (d) clone None and a missing folder, with the log emptied
# first, and (f) a folder no job names as its worktree.
fg_nested_driver() {
  fg_py "real = g.real_git()
rec = os.path.join('$E2E_DIR', 'rec')
os.makedirs(rec, exist_ok=True)
log = os.path.join(rec, 'calls.log')
with open(os.path.join(rec, 'git'), 'w') as f:
    f.write('#!/bin/sh\nprintf \"%%s\\\\t%%s\\\\n\" \"\$PWD\" \"\$*\" >> \"%s\"\nexec \"%s\" \"\$@\"\n' % (log, real))
os.chmod(os.path.join(rec, 'git'), 0o755)
open(log, 'w').close()
os.environ['PATH'] = rec + os.pathsep + os.environ['PATH']
print('git used: ' + os.path.relpath(g.real_git(), '$E2E_DIR'))
print('nested=%r' % (g.nested_repositories(F, C),))
calls = open(log).read().splitlines()
print('git calls made: %s' % (len(calls) > 0))
inside = [c for c in calls if any(('/' + d) in c for d in ('withcommit', 'nocommit', 'lib.git', 'src/vendored', 'deep'))]
print('git calls in or naming a nested folder: %d' % len(inside))
for c in inside:
    print('  call: ' + c)
open(log, 'w').close()
print('(d) none: %r' % (g.nested_repositories(F, None),))
print('(d) missing: %r' % (g.nested_repositories(F, os.path.join('$E2E_DIR', 'area', 'worktrees', 'issue-9')),))
print('(d) git calls: %d' % len(open(log).read().splitlines()))
os.makedirs(os.path.join('$E2E_DIR', 'stray'), exist_ok=True)
print('(f) ' + refused(g.nested_repositories, F, os.path.join('$E2E_DIR', 'stray')))"
}

_flow_test_begin "factory git: nested_repositories lists the clone's untracked nested repositories, with or without a commit, at any depth of an untracked folder, and runs no git inside them (G12, amendment A.11)"
fg_setup fg-nested
e2e_describe "in the clone: (a) withcommit/, a repository with one commit; (b) nocommit/, a repository with no commit; (c) lib.git/, a folder named like a repository holding a file but no .git; (e) src/vendored/, a repository with no commit inside the tracked folder src/; (g) deep/inner/r2/, a repository with no commit inside the untracked plain folder deep/ (status lists only deep/); (h) deep2/link, a symlink to withcommit/ (not listed through the link); plus an untracked file loose.txt. Then (d) clone None and a missing folder, and (f) a folder no job names"
mkdir -p "$FG_C/src"; printf 'kept\n' > "$FG_C/src/keep.txt"
fg_git add src/keep.txt; fg_git -c user.name=e2e -c user.email=e2e@example.invalid commit -q -m 'src'
fg_git init -q withcommit
printf 'inner\n' > "$FG_C/withcommit/inner.txt"
_e2e_exec git -C "$FG_C/withcommit" add inner.txt
_e2e_exec git -C "$FG_C/withcommit" -c user.name=e2e -c user.email=e2e@example.invalid -c commit.gpgsign=false commit -q -m inner
e2e_expect_equal 0 "$E2E_RC" "the nested repository's commit"
fg_git init -q nocommit
fg_git init -q src/vendored
mkdir -p "$FG_C/lib.git"; printf 'not a repository\n' > "$FG_C/lib.git/HEAD"
printf 'loose\n' > "$FG_C/loose.txt"
fg_git init -q deep/inner/r2
mkdir -p "$FG_C/deep2"; ln -s ../withcommit "$FG_C/deep2/link"
fg_git status --porcelain=v1 --untracked-files=normal
e2e_expect_line "?? lib.git/"
e2e_expect_line "?? nocommit/"
e2e_expect_line "?? src/vendored/"
e2e_expect_line "?? withcommit/"
e2e_expect_line "?? deep/"
e2e_expect_line "?? deep2/"
e2e_expect_no_line "?? deep/inner/r2/"
fg_nested_driver
e2e_expect_equal 0 "$E2E_RC" "the driver's exit status"
e2e_expect_line "git used: rec/git"
e2e_expect_line "nested=['deep/inner/r2', 'nocommit', 'src/vendored', 'withcommit']"
e2e_expect_line "git calls made: True"
e2e_expect_line "git calls in or naming a nested folder: 0"
e2e_expect_line "(d) none: []"
e2e_expect_line "(d) missing: []"
e2e_expect_line "(d) git calls: 0"
e2e_expect_line "(f) refused config <no prepare copy>"

# The walk's bounds (amendment A.11, the coordinator's bound of 20 levels and
# 10000 entries per untracked folder), lowered in the driver: wide/ holds 5
# files (5 entries) and chain/a/b/c/f is 4 folders deep (4 entries). At the
# bound the walk passes; one under it, the walk raises naming the folder.
mkdir -p "$FG_C/wide" "$FG_C/chain/a/b/c"
for f in 1 2 3 4 5; do printf 'w\n' > "$FG_C/wide/f$f"; done
printf 'c\n' > "$FG_C/chain/a/b/c/f"
fg_py "print('defaults: depth %d entries %d' % (g.NESTED_SCAN_MAX_DEPTH, g.NESTED_SCAN_MAX_ENTRIES))
g.NESTED_SCAN_MAX_DEPTH, g.NESTED_SCAN_MAX_ENTRIES = 4, 5
print('at the bounds: %r' % (g.nested_repositories(F, C),))
g.NESTED_SCAN_MAX_DEPTH, g.NESTED_SCAN_MAX_ENTRIES = 4, 4
print('entries over: ' + refused(g.nested_repositories, F, C))
g.NESTED_SCAN_MAX_DEPTH, g.NESTED_SCAN_MAX_ENTRIES = 3, 5
print('depth over: ' + refused(g.nested_repositories, F, C))"
e2e_expect_equal 0 "$E2E_RC" "the driver's exit status (scan bounds)"
e2e_expect_line "defaults: depth 20 entries 10000"
e2e_expect_line "at the bounds: ['deep/inner/r2', 'nocommit', 'src/vendored', 'withcommit']"
e2e_expect_line "entries over: failed nested_repository_scan_limit: wide"
e2e_expect_line "depth over: failed nested_repository_scan_limit: chain"
rm -r "$FG_C/wide" "$FG_C/chain"

# The three plausible wrong versions, each a copy of the module with one
# line changed, must each fail a check above.
FG_GIT_SRC=$(cat "$E2E_PLUGIN_DIR/bin/_flow_factory_git.py")
FG_LINE='        if not _has_git_entry(clone, rel):'
case "$FG_GIT_SRC" in *"$FG_LINE"*) e2e_expect_equal found found "the line the mutants change" ;;
  *) e2e_expect_equal found missing "the line the mutants change" ;; esac
e2e_plugin_copy bin/_flow_factory_git.py "${FG_GIT_SRC/"$FG_LINE"/        if False:}"
fg_nested_driver
e2e_expect_equal 0 "$E2E_RC" "the driver's exit status (mutant: every untracked folder)"
e2e_expect_no_line "nested=['deep/inner/r2', 'nocommit', 'src/vendored', 'withcommit']"
e2e_expect_line "nested=['deep', 'deep2', 'lib.git', 'nocommit', 'src/vendored', 'withcommit']"
e2e_plugin_copy bin/_flow_factory_git.py "${FG_GIT_SRC/"$FG_LINE"/        if git(fdir, ['-C', os.path.join(clone, rel), 'rev-parse', '--show-toplevel'], clone, clone, copy_dir)[1].strip() != os.path.realpath(os.path.join(clone, rel)):}"
fg_nested_driver
e2e_expect_equal 0 "$E2E_RC" "the driver's exit status (mutant: git rev-parse in the nested folder)"
e2e_expect_line "nested=['deep/inner/r2', 'nocommit', 'src/vendored', 'withcommit']"
e2e_expect_no_line "git calls in or naming a nested folder: 0"
FG_WALK='            found.extend(_walk_untracked(clone, rel))'
case "$FG_GIT_SRC" in *"$FG_WALK"*) e2e_expect_equal found found "the line the walk mutant changes" ;;
  *) e2e_expect_equal found missing "the line the walk mutant changes" ;; esac
e2e_plugin_copy bin/_flow_factory_git.py "${FG_GIT_SRC/"$FG_WALK"/            pass}"
fg_nested_driver
e2e_expect_equal 0 "$E2E_RC" "the driver's exit status (mutant: untracked folders not walked)"
e2e_expect_no_line "nested=['deep/inner/r2', 'nocommit', 'src/vendored', 'withcommit']"
e2e_expect_line "nested=['nocommit', 'src/vendored', 'withcommit']"
