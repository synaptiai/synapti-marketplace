# shellcheck shell=bash
# End-to-end: the version files /flow:release bumps before it tags.
#
# bin/flow-release-versions.sh runs in a scratch repository holding fixture
# version files, as /flow:release runs it at the root of the user's
# repository. The release.md blocks that call it are extracted and run too: the
# Phase 2 plan and the Phase 4 bump-and-commit. One artifact per scenario is
# written to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the script:
#   V1 a set whose versions disagree is partly written: the first file is
#      bumped before the disagreement is found
#   V2 marketplace.json is rewritten from the parsed object, so every line of
#      it changes rather than the one version
#   V3 a plugin release bumps the wrong entry of marketplace.json (the first
#      "version" in the file, or another plugin's)
#   V4 a plugin release compares the plugin's version with the marketplace's
#      own metadata.version, which differ by design, and refuses
#   V5 a dynamic pyproject version, or a Cargo package that inherits its
#      workspace version, is reported as bumped
#   V6 Cargo.toml's dependency `version = ` line, or package.json's nested
#      "version" key, is bumped instead of the package's own
#   V7 a file the script does not know (setup.py, VERSION, a lockfile) is left
#      out of the report rather than listed as skipped with a reason
#   V8 --plan writes
#   V9 a version file that is a symbolic link is written through
#   V10 --bump on a version that is not MAJOR.MINOR.PATCH guesses a result
#   V11 a repository with no version file is an error rather than "none"
#
# release.md blocks
#   R1 the Phase 2 plan runs without the plugin name the arguments carry, so a
#      plugin release plans root files
#   R2 the Phase 4 block commits nothing, commits files the script did not
#      bump, or commits when the script refused

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

VERSIONS=bin/flow-release-versions.sh
RELEASE_MD="$E2E_PLUGIN_DIR/commands/release.md"

# _commit_all — commit the fixture files so a later diff shows only what the
# script changed.
_commit_all() {
  ( _e2e_git_env; cd "$E2E_REPO" && git add -A && git commit -q -m fixtures ) \
    || _flow_assert_fail "$E2E_NAME: could not commit the fixtures"
}
# _changed_lines <path> — how many lines git counts as changed in that file.
_changed_lines() {
  ( _e2e_git_env; cd "$E2E_REPO" && git diff --numstat -- "$1" | awk '{print $1 + $2}' )
}
_head_subject() { ( _e2e_git_env; cd "$E2E_REPO" && git log -1 --format=%s ); }
_head_files() { ( _e2e_git_env; cd "$E2E_REPO" && git show --name-only --format= HEAD | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//' ); }
_status() { ( _e2e_git_env; cd "$E2E_REPO" && git status --porcelain ); }

# The npm package carries a nested "version" key before its own, and a
# lockfile that also holds the version (V6, V7).
_npm_fixture() {
  cat > "$E2E_REPO/package.json" <<'EOF'
{
  "name": "demo",
  "engines": { "version": "9.9.9" },
  "version": "1.2.3",
  "scripts": { "test": "true" }
}
EOF
  printf '{\n  "name": "demo",\n  "version": "1.2.3",\n  "lockfileVersion": 3\n}\n' > "$E2E_REPO/package-lock.json"
}

_flow_test_begin "npm: the package's own version is bumped, the nested key and the lockfile are not (V6, V7)"
e2e_new versions-npm
e2e_describe "package.json with a nested engines.version before its version; a package-lock.json"
e2e_repo main
_npm_fixture
_commit_all
e2e_run_bin "$VERSIONS" --write --bump minor
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "VERSION_FILE=bump path=package.json current=1.2.3 new=1.3.0"
e2e_expect_out "VERSION_FILE=skip path=package-lock.json reason="
e2e_expect_line "CURRENT_VERSION=1.2.3"
e2e_expect_line "NEW_VERSION=1.3.0"
e2e_expect_line "VERSIONS_STATE=written"
e2e_expect_file_has package.json '"version": "1.3.0"'
e2e_expect_file_has package.json '"engines": { "version": "9.9.9" }'
e2e_expect_equal 2 "$(_changed_lines package.json)" "lines changed in package.json (one removed, one added)"
e2e_expect_equal "" "$(_changed_lines package-lock.json)" "lines changed in package-lock.json"

_flow_test_begin "pyproject: [project] version is bumped; a dynamic version is skipped (V5)"
e2e_new versions-pyproject
e2e_describe "pyproject.toml with a [tool.other] version line before [project]"
e2e_repo main
cat > "$E2E_REPO/pyproject.toml" <<'EOF'
[build-system]
requires = ["hatchling"]

[tool.other]
version = "0.0.1"

[project]
name = "demo"
version = "2.0.9"  # the release version
EOF
_commit_all
e2e_run_bin "$VERSIONS" --write --bump patch
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "VERSION_FILE=bump path=pyproject.toml current=2.0.9 new=2.0.10"
e2e_expect_file_has pyproject.toml 'version = "2.0.10"  # the release version'
e2e_expect_file_has pyproject.toml 'version = "0.0.1"'
e2e_expect_equal 2 "$(_changed_lines pyproject.toml)" "lines changed in pyproject.toml"

e2e_new versions-pyproject-dynamic
e2e_describe "pyproject.toml whose version is dynamic"
e2e_repo main
printf '[project]\nname = "demo"\ndynamic = ["version"]\n' > "$E2E_REPO/pyproject.toml"
_commit_all
e2e_run_bin "$VERSIONS" --plan --bump patch
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_out "VERSION_FILE=skip path=pyproject.toml reason="
e2e_expect_out "dynamic"
e2e_expect_line "VERSIONS_STATE=none"

_flow_test_begin "Cargo: [package] version is bumped, not a dependency's (V5, V6)"
e2e_new versions-cargo
e2e_describe "Cargo.toml with an inline-table dependency version and a [dependencies.x] table version"
e2e_repo main
cat > "$E2E_REPO/Cargo.toml" <<'EOF'
[package]
name = "demo"
version = "0.4.1"
edition = "2021"

[dependencies]
serde = { version = "1.0" }

[dependencies.rand]
version = "0.8.5"
EOF
_commit_all
e2e_run_bin "$VERSIONS" --write --bump major
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "VERSION_FILE=bump path=Cargo.toml current=0.4.1 new=1.0.0"
e2e_expect_file_has Cargo.toml 'version = "1.0.0"'
e2e_expect_file_has Cargo.toml 'version = "0.8.5"'
e2e_expect_file_has Cargo.toml 'serde = { version = "1.0" }'
e2e_expect_equal 2 "$(_changed_lines Cargo.toml)" "lines changed in Cargo.toml"

e2e_new versions-cargo-workspace
e2e_describe "a Cargo package that inherits its version from the workspace"
e2e_repo main
printf '[package]\nname = "demo"\nversion.workspace = true\n' > "$E2E_REPO/Cargo.toml"
_commit_all
e2e_run_bin "$VERSIONS" --plan --bump patch
e2e_expect_out "VERSION_FILE=skip path=Cargo.toml reason="
e2e_expect_out "inherits its version from the workspace"
e2e_expect_line "VERSIONS_STATE=none"

_flow_test_begin "plugin: .claude-plugin/plugin.json at the root is bumped; --plan writes nothing (V8)"
e2e_new versions-plugin
e2e_describe "a single-plugin repository; the plan is run first, then the write"
e2e_repo main
mkdir -p "$E2E_REPO/.claude-plugin"
printf '{\n  "name": "demo",\n  "version": "3.1.0",\n  "description": "d"\n}\n' > "$E2E_REPO/.claude-plugin/plugin.json"
_commit_all
e2e_run_bin "$VERSIONS" --plan --bump minor
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "VERSION_FILE=bump path=.claude-plugin/plugin.json current=3.1.0 new=3.2.0"
e2e_expect_line "VERSIONS_STATE=planned"
e2e_expect_equal "" "$(_status)" "the working tree after --plan"
e2e_run_bin "$VERSIONS" --write --to 3.2.0
e2e_expect_line "VERSIONS_STATE=written"
e2e_expect_file_has .claude-plugin/plugin.json '"version": "3.2.0"'

# A marketplace like this repository's: its own version differs from each
# plugin's, and another plugin's entry comes first (V3, V4). The file uses
# one-line arrays that json.dumps would expand (V2).
_marketplace_fixture() {
  mkdir -p "$E2E_REPO/.claude-plugin" "$E2E_REPO/plugins/alpha/.claude-plugin" "$E2E_REPO/plugins/beta/.claude-plugin"
  cat > "$E2E_REPO/.claude-plugin/marketplace.json" <<EOF
{
  "name": "market",
  "metadata": { "description": "m", "version": "4.17.0" },
  "plugins": [
    { "name": "alpha", "source": "./plugins/alpha", "version": "1.5.0", "keywords": ["a", "b"] },
    {
      "name": "beta",
      "source": "./plugins/beta",
      "version": "$1",
      "keywords": ["c", "d"]
    }
  ]
}
EOF
  printf '{\n  "name": "alpha",\n  "version": "1.5.0"\n}\n' > "$E2E_REPO/plugins/alpha/.claude-plugin/plugin.json"
  printf '{\n  "name": "beta",\n  "version": "3.10.0"\n}\n' > "$E2E_REPO/plugins/beta/.claude-plugin/plugin.json"
}

_flow_test_begin "marketplace plugin: the plugin's plugin.json and its own entry, one line each (V2, V3, V4)"
e2e_new versions-marketplace-plugin
e2e_describe "a marketplace at 4.17.0 holding alpha 1.5.0 and beta 3.10.0; release beta minor"
e2e_repo main
_marketplace_fixture 3.10.0
_commit_all
e2e_run_bin "$VERSIONS" --write --bump minor --plugin beta
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "VERSION_FILE=bump path=plugins/beta/.claude-plugin/plugin.json current=3.10.0 new=3.11.0"
e2e_expect_line "VERSION_FILE=bump path=.claude-plugin/marketplace.json entry=beta current=3.10.0 new=3.11.0"
e2e_expect_line "VERSIONS_STATE=written"
e2e_expect_equal 2 "$(_changed_lines .claude-plugin/marketplace.json)" "lines changed in marketplace.json"
e2e_expect_file_has .claude-plugin/marketplace.json '"version": "3.11.0",'
e2e_expect_file_has .claude-plugin/marketplace.json '"metadata": { "description": "m", "version": "4.17.0" },'
e2e_expect_file_has .claude-plugin/marketplace.json '"version": "1.5.0", "keywords": ["a", "b"] },'
e2e_expect_equal "" "$(_changed_lines plugins/alpha/.claude-plugin/plugin.json)" "lines changed in alpha's plugin.json"

_flow_test_begin "marketplace at the root without a plugin name: listed as skipped with the reason"
e2e_new versions-marketplace-root
e2e_describe "the same marketplace, released without naming a plugin"
e2e_repo main
_marketplace_fixture 3.10.0
_commit_all
e2e_run_bin "$VERSIONS" --plan --bump patch
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_out "VERSION_FILE=skip path=.claude-plugin/marketplace.json reason="
e2e_expect_line "VERSIONS_STATE=none"

_flow_test_begin "mismatched versions: refused, and nothing is written (V1)"
e2e_new versions-mismatch-marketplace
e2e_describe "beta's plugin.json says 3.10.0 and its marketplace entry says 3.9.0"
e2e_repo main
_marketplace_fixture 3.9.0
_commit_all
e2e_run_bin "$VERSIONS" --write --bump patch --plugin beta
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_line "VERSIONS_STATE=mismatch"
e2e_expect_out "path=plugins/beta/.claude-plugin/plugin.json current=3.10.0"
e2e_expect_out "path=.claude-plugin/marketplace.json entry=beta current=3.9.0"
e2e_expect_equal "" "$(_status)" "the working tree"

e2e_new versions-mismatch-root
e2e_describe "package.json says 1.2.3 and pyproject.toml says 1.2.4; package.json sorts first"
e2e_repo main
_npm_fixture
printf '[project]\nname = "demo"\nversion = "1.2.4"\n' > "$E2E_REPO/pyproject.toml"
_commit_all
e2e_run_bin "$VERSIONS" --write --to 1.3.0
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_line "VERSIONS_STATE=mismatch"
e2e_expect_equal "" "$(_status)" "the working tree"

_flow_test_begin "unknown files are listed as skipped; no version file is 'none' (V7, V11)"
e2e_new versions-unknown
e2e_describe "setup.py and VERSION only"
e2e_repo main
printf 'from setuptools import setup\nsetup(version="1.0.0")\n' > "$E2E_REPO/setup.py"
printf '1.0.0\n' > "$E2E_REPO/VERSION"
_commit_all
e2e_run_bin "$VERSIONS" --write --bump patch
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_out "VERSION_FILE=skip path=setup.py reason="
e2e_expect_out "VERSION_FILE=skip path=VERSION reason="
e2e_expect_line "CURRENT_VERSION=none"
e2e_expect_line "VERSIONS_STATE=none"
e2e_expect_equal "" "$(_status)" "the working tree"

_flow_test_begin "a symlinked version file is refused, not written through (V9)"
e2e_new versions-symlink
e2e_describe "package.json is a link to a file outside the repository"
e2e_repo main
printf '{\n  "name": "x",\n  "version": "1.0.0"\n}\n' > "$E2E_DIR/outside.json"
ln -s "$E2E_DIR/outside.json" "$E2E_REPO/package.json"
e2e_run_bin "$VERSIONS" --write --bump patch
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_line "VERSIONS_STATE=refused"
e2e_expect_equal '"version": "1.0.0"' "$(grep -o '"version": "[^"]*"' "$E2E_DIR/outside.json")" "the link's target"

e2e_new versions-symlink-inside
e2e_describe "package.json is a link to another file inside the repository"
e2e_repo main
printf '{\n  "name": "x",\n  "version": "1.0.0"\n}\n' > "$E2E_REPO/real-package.json"
ln -s real-package.json "$E2E_REPO/package.json"
e2e_run_bin "$VERSIONS" --write --bump patch
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_line "VERSIONS_STATE=refused"
e2e_expect_out "symbolic link"
e2e_expect_equal "link" "$( [ -L "$E2E_REPO/package.json" ] && printf link )" "package.json afterwards"
e2e_expect_file_has real-package.json '"version": "1.0.0"'

_flow_test_begin "--bump on a pre-release version is refused; --to still works (V10)"
e2e_new versions-prerelease
e2e_describe "package.json at 2.0.0-rc.1"
e2e_repo main
printf '{\n  "name": "x",\n  "version": "2.0.0-rc.1"\n}\n' > "$E2E_REPO/package.json"
_commit_all
e2e_run_bin "$VERSIONS" --write --bump patch
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_line "VERSIONS_STATE=refused"
e2e_expect_equal "" "$(_status)" "the working tree"
e2e_run_bin "$VERSIONS" --write --to 2.0.0
e2e_expect_equal 0 "$E2E_RC" "the exit status with --to"
e2e_expect_file_has package.json '"version": "2.0.0"'

_flow_test_begin "release.md Phase 2 plan names the plugin from the arguments (R1)"
e2e_new release-plan-plugin
e2e_describe "run as /flow:release minor beta in the marketplace fixture"
e2e_repo main
_marketplace_fixture 3.10.0
_commit_all
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "RELEASE_TYPE=minor"
e2e_expect_line "RELEASE_PLUGIN=beta"
e2e_expect_line "VERSION_FILE=bump path=.claude-plugin/marketplace.json entry=beta current=3.10.0 new=3.11.0"
e2e_expect_line "NEW_VERSION=3.11.0"
e2e_expect_equal "" "$(_status)" "the working tree"
e2e_expect_clean_edges

e2e_new release-plan-bad-type
e2e_describe "run as /flow:release sideways"
e2e_repo main
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'sideways'
e2e_expect_line "STATE=blocked"
e2e_expect_out "patch, minor or major"

# The Phase 4 block commits, so a second shell run in the same repository would
# find the bump already made. Each shell gets a fresh repository instead.
ALL_SHELLS="$E2E_FENCE_SHELLS"

_flow_test_begin "release.md Phase 4 commits exactly the bumped files (R2)"
for E2E_FENCE_SHELLS in $ALL_SHELLS; do
  e2e_new "release-bump-commit-$E2E_FENCE_SHELLS"
  e2e_describe "the marketplace fixture and an untracked notes.txt; the block runs under $E2E_FENCE_SHELLS with VERSION=3.11.0 PLUGIN=beta"
  e2e_repo main
  _marketplace_fixture 3.10.0
  _commit_all
  printf 'unrelated\n' > "$E2E_REPO/notes.txt"
  ( _e2e_git_env; cd "$E2E_REPO" && printf 'staged\n' > staged.txt && git add staged.txt )
  e2e_run_block VERSION=3.11.0 PLUGIN=beta TAG_PREFIX=v "$RELEASE_MD" RELEASE_BUMP_BLOCK
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "BUMP_STATE=committed"
  e2e_expect_equal "chore(release): v3.11.0" "$(_head_subject)" "the bump commit's subject"
  e2e_expect_equal ".claude-plugin/marketplace.json plugins/beta/.claude-plugin/plugin.json" "$(_head_files)" "the files in the bump commit"
  e2e_expect_equal "A  staged.txt
?? notes.txt" "$(_status)" "the working tree after the commit (the staged file stays staged)"
  # A re-run with the same version: nothing to bump, nothing committed.
  e2e_run_block VERSION=3.11.0 PLUGIN=beta TAG_PREFIX=v "$RELEASE_MD" RELEASE_BUMP_BLOCK
  e2e_expect_equal 0 "$E2E_RC" "the exit status of the re-run"
  e2e_expect_line "BUMP_STATE=unchanged"
  e2e_expect_line "VERSIONS_STATE=unchanged"
  e2e_expect_equal "chore(release): v3.11.0" "$(_head_subject)" "HEAD's subject after the re-run"
done

for E2E_FENCE_SHELLS in $ALL_SHELLS; do
  e2e_new "release-bump-refused-$E2E_FENCE_SHELLS"
  e2e_describe "the mismatched marketplace fixture; the block runs under $E2E_FENCE_SHELLS with VERSION=3.10.1 PLUGIN=beta"
  e2e_repo main
  _marketplace_fixture 3.9.0
  _commit_all
  e2e_run_block VERSION=3.10.1 PLUGIN=beta TAG_PREFIX=v "$RELEASE_MD" RELEASE_BUMP_BLOCK
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_line "BUMP_STATE=blocked"
  e2e_expect_equal "fixtures" "$(_head_subject)" "HEAD's subject (no bump commit)"
  e2e_expect_equal "" "$(_status)" "the working tree"
done
E2E_FENCE_SHELLS="$ALL_SHELLS"

e2e_new release-bump-none
e2e_describe "a repository with no version file; the block runs with VERSION=1.0.0"
e2e_repo main
e2e_run_block VERSION=1.0.0 TAG_PREFIX=v "$RELEASE_MD" RELEASE_BUMP_BLOCK
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "BUMP_STATE=none"
e2e_expect_equal "init" "$(_head_subject)" "HEAD's subject (no bump commit)"

e2e_new release-bump-no-version
e2e_describe "VERSION is not set"
e2e_repo main
e2e_run_block "$RELEASE_MD" RELEASE_BUMP_BLOCK
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_line "BUMP_STATE=blocked"

# The Phase 1 context fence. The gh stub keys `gh pr list --state merged` on
# its --head and --base values; this call passes neither, so the stub names
# its fixture merged-prs-pr-pr.
_flow_test_begin "release.md Phase 1 context fence runs: merged PRs and commits since the last tag"
e2e_new release-context
e2e_describe "a repository tagged v1.0.0 with one commit after the tag; gh lists one merged PR"
e2e_repo main
( _e2e_git_env; cd "$E2E_REPO" && git tag v1.0.0 && printf 'x\n' > a.txt && git add a.txt && git commit -q -m 'feat: add a' )
e2e_gh_fixture merged-prs-pr-pr '[{"number":7,"title":"feat: add a","labels":[{"name":"enhancement"}]}]'
e2e_run_fence "$RELEASE_MD" '### Merged PRs Since Last Release'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "LAST_TAG=v1.0.0"
e2e_expect_line "MERGED_PR_COUNT=1"
e2e_expect_line 'MERGED_PR=number=7 labels="enhancement" title="feat: add a"'
e2e_expect_out "COMMIT="
e2e_expect_out "feat: add a"
e2e_expect_clean_edges

e2e_new release-context-gh-down
e2e_describe "no tag; gh fails"
e2e_repo main
e2e_gh_fail merged-prs-pr-pr
e2e_run_fence "$RELEASE_MD" '### Merged PRs Since Last Release'
e2e_expect_line "LAST_TAG=none"
e2e_expect_line "STATE=unavailable"
