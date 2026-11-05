# shellcheck shell=bash
# End-to-end: the description check (issue #328). DESCRIPTION_CHECK_BLOCK
# runs in a scratch repository, the way Claude Code runs it, on a pull request
# body written for an earlier version of the change and on one written from
# the final diff, and on a commit message against the staged change. The block
# is the same in commands/pr.md, address.md, merge.md and commit.md; a
# scenario below checks that it is.
#
# The scratch change, written below, is the source of every expected value:
# against main the branch adds three lines to src/route.sh and deletes one,
# adds docs/guide.md (two lines), and deletes src/old.sh (one line). So: 3
# files changed; src 2 files, +3, -2; docs 1 file, +2, -0; Total 3 files,
# +5, -2. src/route.sh has 5 lines after the change.
#
# Ways it can be wrong, written down before the scenarios:
#   D1 a stale files-changed row, a stale "N files changed", a path the
#      change no longer has, or a line past the end of a file passes
#   D2 an accurate body is reported stale: a deleted file the body names, a
#      placeholder path (<id>), a glob, or a URL counted as a stale path
#   D3 the check compares the wrong range (two dots, or the working tree)
#      so a branch whose base moved on reads differently
#   D4 a check that could not run reads as STATE=ok
#   D5 the four commands carry different copies of the block
#   D6 a bare base name is compared as the local branch, which /flow:start
#      never updates, so commits merged upstream are counted
#   D7 a rename is counted as a delete and an add, unlike git diff --stat
#   D8 a backticked ref, branch, MIME type or host:port is reported as a
#      stale path, or a package-relative path that exists below a directory
#   D9 the last line of a file with no final newline is reported past the end
#   D10 --head is ignored, so /flow:merge checks the local HEAD instead of the
#      head GitHub will merge
#   D11 files at the top of the repository have no area a row can name
#
# One artifact per scenario goes to $FLOW_E2E_ARTIFACT_DIR.
# FLOW_E2E_SCENARIOS=a,b runs only the named scenarios.

# Only tests/run.sh runs this file: it sets REPO_ROOT and loads assert.sh. Run
# any other way, the file stops here with a non-zero exit, because `return`
# alone does not stop a script that is executed rather than sourced, and the
# scenarios below would then run git in the current directory.
{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

_want() {
  case ",${FLOW_E2E_SCENARIOS:-}," in
    ",,") return 0 ;;
    *",$1,"*) return 0 ;;
  esac
  return 1
}

# _dc_setup <scenario> <purpose> — main with src/route.sh (3 lines) and
# src/old.sh, then the branch's change, then one more commit on main after
# the branch left it, which a two-dot range would wrongly count.
_dc_setup() {
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo main-start
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    git checkout -q -b main
    mkdir -p src docs
    printf 'a\nb\nc\n' > src/route.sh
    printf 'old\n' > src/old.sh
    git add src && git commit -q -m 'feat: route'
    git checkout -q -b feature/issue-328-x
    printf 'a\nb2\nc\nd\ne\n' > src/route.sh
    printf 'one\ntwo\n' > docs/guide.md
    git rm -q src/old.sh
    git add src docs && git commit -q -m 'feat: route more'
    git checkout -q main
    printf 'later\n' > LATER.md
    git add LATER.md && git commit -q -m 'docs: a later change on main'
    git checkout -q feature/issue-328-x
  ) || _flow_assert_fail "$1: could not write the change"
}

_dc_body() {
  printf '%s\n' "$1" > "$E2E_DIR/body.md"
  printf 'description:\n%s\n' "$1" | _e2e_art
}

_dc_run() { e2e_run_block "$@" commands/pr.md DESCRIPTION_CHECK_BLOCK; }

if _want stale-body; then
  _flow_test_begin "stale-body"
  _dc_setup stale-body "a body written for an earlier version: its src row, its file count, a path the change removed and a line past the end are each reported, and the state is stale (D1, D3)"
  _dc_body '## Summary

Routes more requests. 2 files changed. The new branch is at `src/route.sh:12`; the helper lives in `src/helper.sh`.

## Files Changed

| Area | Files | Additions | Deletions |
|------|-------|-----------|-----------|
| `src/` | 1 | +2 | -1 |
| docs | 1 | +2 | -0 |
| Total | 2 | +4 | -1 |'
  _dc_run DESC_FILE="$E2E_DIR/body.md" DESC_BASE=main
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "### Description check"
  e2e_expect_line "STATE=stale"
  e2e_expect_line "CHECKED_ROWS=3"
  e2e_expect_line "MISMATCH=files-changed row src|1 files, +2, -1|2 files, +3, -2"
  e2e_expect_line "MISMATCH=files-changed row Total|2 files, +4, -1|3 files, +5, -2"
  e2e_expect_line "MISMATCH=2 files changed|2|3"
  e2e_expect_line "STALE_PATH=src/helper.sh|not in the tree the change produces"
  e2e_expect_line "STALE_PATH=src/route.sh:12|src/route.sh has 5 lines"
  e2e_expect_no_out "files-changed row docs"
  e2e_expect_clean_edges
fi

if _want accurate-body; then
  _flow_test_begin "accurate-body"
  _dc_setup accurate-body "a body written from the final diff: it names the deleted src/old.sh, a placeholder path, a glob and a URL, none of which is a stale path, and the state is ok (D2, D3)"
  _dc_body '## Summary

Routes more requests and removes `src/old.sh`. 3 files changed. The new branch is at `src/route.sh:4-5`, documented in `docs/guide.md`; goals live in `.flow/goals/<id>.goal.yaml`, tests in `tests/*.sh`, see `https://example.invalid/a/b`.

## Files Changed

| Area | Files | Additions | Deletions |
|------|-------|-----------|-----------|
| `src/` | 2 | +3 | -2 |
| docs | 1 | +2 | -0 |
| **Total** | 3 | +5 | -2 |'
  _dc_run DESC_FILE="$E2E_DIR/body.md" DESC_BASE=main
  e2e_expect_equal 0 "$E2E_RC" "exit status"
  e2e_expect_line "STATE=ok"
  e2e_expect_line "CHECKED_ROWS=3"
  e2e_expect_line "CHECKED_COUNTS=1"
  # src/old.sh, src/route.sh:4-5 and docs/guide.md; the table's `src/` is a
  # directory, which is not checked.
  e2e_expect_line "CHECKED_PATHS=3"
  e2e_expect_no_out "MISMATCH="
  e2e_expect_no_out "STALE_PATH="
  e2e_expect_clean_edges
fi

if _want commit-message; then
  _flow_test_begin "commit-message"
  _dc_setup commit-message "a commit message checked against the staged change from commands/commit.md: a staged path passes; a path that is neither staged nor committed is stale (D1)"
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    printf 'x\n' > src/new.sh && git add src/new.sh
  ) || _flow_assert_fail "commit-message: could not stage"
  _dc_body 'feat(src): add `src/new.sh`

Leaves `src/route.sh` as it is.'
  e2e_run_block DESC_FILE="$E2E_DIR/body.md" DESC_STAGED=1 commands/commit.md DESCRIPTION_CHECK_BLOCK
  e2e_expect_line "STATE=ok"
  e2e_expect_line "CHECKED_PATHS=2"
  _dc_body 'feat(src): add `src/newer.sh`'
  e2e_run_block DESC_FILE="$E2E_DIR/body.md" DESC_STAGED=1 commands/commit.md DESCRIPTION_CHECK_BLOCK
  e2e_expect_line "STATE=stale"
  e2e_expect_line "STALE_PATH=src/newer.sh|not in the tree the change produces"
  e2e_expect_clean_edges
fi

if _want not-run; then
  _flow_test_begin "not-run"
  _dc_setup not-run "a check that could not run says so and never reads as ok: no DESC_FILE, no base, and a base that is not a commit (D4)"
  _dc_body 'nothing'
  _dc_run
  e2e_expect_line "STATE=unavailable"
  e2e_expect_line "REASON=DESC_FILE is not set"
  _dc_run DESC_FILE="$E2E_DIR/body.md"
  e2e_expect_line "STATE=unavailable"
  _dc_run DESC_FILE="$E2E_DIR/body.md" DESC_BASE=no-such-branch
  e2e_expect_line "STATE=unavailable"
  e2e_expect_line "REASON=no commit 'no-such-branch'"
  e2e_expect_no_out "STATE=ok"
  e2e_expect_clean_edges
fi

if _want same-block; then
  _flow_test_begin "same-block"
  _dc_setup same-block "commands/pr.md, address.md, merge.md and commit.md carry the same DESCRIPTION_CHECK_BLOCK, compared without each line's indentation, which follows the list the block sits in, and without its plugin-root line, which follows where the command may run (D5)"
  # The plugin-root line is left out: /flow:address may run on someone else's
  # pull request, so it resolves the plugin with the install-preferring form
  # (references/plugin-root-resolution.md), and the others with the
  # author-context form.
  _dc_block() { (cd "$E2E_ACTIVE_PLUGIN" && flow_block "commands/$1.md" DESCRIPTION_CHECK_BLOCK) | sed 's/^[[:space:]]*//' | grep -v '^FLOW_ROOT=' | _e2e_sha256_stdin; }
  PR_SHA=$(_dc_block pr)
  for c in address merge commit; do
    e2e_expect_equal "$PR_SHA" "$(_dc_block "$c")" "sha256 of the block in commands/$c.md"
  done
  e2e_expect_clean_edges
fi

if _want stale-local-base; then
  _flow_test_begin "stale-local-base"
  _dc_setup stale-local-base "the local main is behind origin/main, as /flow:start leaves it (it branches from origin/main and never updates main): DESC_BASE=main is compared as origin/main, so an accurate body is ok and COMPARED names the range (D6)"
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    # origin/main is where the branch started; the local main stays one
    # commit behind it, before src/route.sh existed.
    git update-ref refs/remotes/origin/main "$(git merge-base main feature/issue-328-x)"
    git branch -f main "$(git rev-list --max-parents=0 HEAD)"
  ) || _flow_assert_fail "stale-local-base: could not set up the refs"
  _dc_body '3 files changed.

| Area | Files | Additions | Deletions |
|------|-------|-----------|-----------|
| Total | 3 | +5 | -2 |'
  _dc_run DESC_FILE="$E2E_DIR/body.md" DESC_BASE=main
  e2e_expect_line "STATE=ok"
  e2e_expect_line "COMPARED=origin/main...HEAD"
  e2e_expect_clean_edges
fi

if _want rename; then
  _flow_test_begin "rename"
  _dc_setup rename "a branch whose only change renames docs/keep.md, a file main has, to docs/kept.md unchanged: it is one file with +0 -0, as git diff --stat counts it, and the old path may still be named (D7)"
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    git checkout -q main
    mkdir -p docs && printf 'one\ntwo\n' > docs/keep.md && git add docs/keep.md && git commit -q -m 'docs: keep'
    git checkout -q -b feature/issue-328-rename
    git mv docs/keep.md docs/kept.md && git commit -q -m 'docs: rename'
  ) || _flow_assert_fail "rename: could not rename"
  _dc_body 'Renames `docs/keep.md` to `docs/kept.md`. 1 file changed.

| Area | Files | Additions | Deletions |
|------|-------|-----------|-----------|
| docs | 1 | +0 | -0 |'
  _dc_run DESC_FILE="$E2E_DIR/body.md" DESC_BASE=main
  e2e_expect_line "STATE=ok"
  e2e_expect_line "CHECKED_PATHS=2"
  e2e_expect_no_out "MISMATCH="
  e2e_expect_no_out "STALE_PATH="
  e2e_expect_clean_edges
fi

if _want not-paths; then
  _flow_test_begin "not-paths"
  _dc_setup not-paths "backticked text that is not a file path is not checked, and a path written relative to a package directory is found below it; a file that is nowhere is still stale (D8)"
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    mkdir -p packages/web/lib && printf 'x\n' > packages/web/lib/util.js
    git add packages && git commit -q -m 'feat: web util'
  ) || _flow_assert_fail "not-paths: could not commit"
  _dc_body 'Branched from `origin/main` on `feature/issue-328-x`; sends `application/json` to `owner/repo` at `localhost:8080/api` and `www.example.com/docs`, and/or reads `lib/util.js`. Not `lib/missing.js`.'
  _dc_run DESC_FILE="$E2E_DIR/body.md" DESC_BASE=main
  e2e_expect_line "STATE=stale"
  e2e_expect_line "CHECKED_PATHS=2"
  e2e_expect_line "STALE_PATH=lib/missing.js|not in the tree the change produces"
  e2e_expect_no_out "STALE_PATH=origin/main"
  e2e_expect_no_out "STALE_PATH=lib/util.js"
  e2e_expect_clean_edges
fi

if _want no-final-newline; then
  _flow_test_begin "no-final-newline"
  _dc_setup no-final-newline "the last line of a file with no final newline exists: src/end.sh has 3 lines and its third is cited (D9)"
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    printf 'one\ntwo\nthree' > src/end.sh && git add src/end.sh && git commit -q -m 'feat: end'
  ) || _flow_assert_fail "no-final-newline: could not commit"
  _dc_body 'The third line is `src/end.sh:3`; there is no `src/end.sh:4`.'
  _dc_run DESC_FILE="$E2E_DIR/body.md" DESC_BASE=main
  e2e_expect_line "STALE_PATH=src/end.sh:4|src/end.sh has 3 lines"
  e2e_expect_no_out "STALE_PATH=src/end.sh:3"
  e2e_expect_clean_edges
fi

if _want head-ref; then
  _flow_test_begin "head-ref"
  _dc_setup head-ref "DESC_HEAD names the commit to check, not the checked-out branch, as /flow:merge passes the pull request's headRefOid: from main, the body of the branch is ok against its head and stale against HEAD (D10)"
  HEAD_SHA=$(cd "$E2E_REPO" && git rev-parse feature/issue-328-x)
  (cd "$E2E_REPO" && _e2e_git_env && git checkout -q main) || _flow_assert_fail "head-ref: checkout"
  _dc_body '3 files changed.'
  _dc_run DESC_FILE="$E2E_DIR/body.md" DESC_BASE=main DESC_HEAD="$HEAD_SHA"
  e2e_expect_line "STATE=ok"
  _dc_run DESC_FILE="$E2E_DIR/body.md" DESC_BASE=main
  e2e_expect_line "STATE=stale"
  e2e_expect_clean_edges
fi

if _want root-row; then
  _flow_test_begin "root-row"
  _dc_setup root-row "a (root) row counts the files at the top of the repository (D11)"
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    printf 'readme\n' >> README.md && git add README.md && git commit -q -m 'docs: readme'
  ) || _flow_assert_fail "root-row: could not commit"
  _dc_body '| Area | Files | Additions | Deletions |
|------|-------|-----------|-----------|
| (root) | 1 | +1 | -0 |
| src | 2 | +3 | -2 |'
  _dc_run DESC_FILE="$E2E_DIR/body.md" DESC_BASE=main
  e2e_expect_line "STATE=ok"
  e2e_expect_line "CHECKED_ROWS=2"
  e2e_expect_clean_edges
fi
