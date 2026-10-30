# shellcheck shell=bash
# End-to-end: the version files /flow:release bumps, and the release.md blocks
# that open the release pull request and tag its merge commit.
#
# bin/flow-release-versions.sh runs in a scratch repository holding fixture
# version files, as /flow:release runs it at the root of the user's
# repository. The release.md blocks are extracted and run too: Phase 1's
# context, Phase 2's release state, and Phase 4's release pull request and tag
# blocks. One artifact per scenario is
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
#   V12 a plugin release leaves the marketplace's metadata.version, which the
#      tag carries, unbumped, or bumps it by the wrong type
#   V13 a version read from a file, or a value given on the command line,
#      holds a line break and its text is printed as output lines of its own
#      (VERSIONS_STATE=planned, TAG_VERSION=6.6.6) that the caller reads
#   V14 a write that fails on the second file leaves the first one bumped
#      while the state says refused
#
# release.md Phase 2: which run this is
#   S1 the plan runs without the plugin name or marketplace type the
#      arguments carry
#   S2 the release branch ignores conventions.branchPatterns.release
#   S3 an open release pull request is taken for "no pull request", and a
#      second one is opened
#   S4 a merged release pull request is tagged at the default branch's head
#      rather than its merge commit, or the run plans the next version
#      instead of tagging the merged one
#   S5 a version nobody tagged and no release pull request explains is
#      tagged or bumped without asking
#   S6 a repository with no version file cannot release at all
#   S7 the plan runs off the default branch or behind origin
#   S8 the current version counts as released when its tag is only in this
#      clone (a tag push that failed), or when the tag is on origin but the
#      GitHub release was never created (a release create that failed), so
#      the run plans the next version and that release is never published
#   S9 gh failing to answer whether the release exists is taken for "no
#      release", and the run re-creates one
#   S10 the release branch name is built from a version or a branch pattern
#      that does not make a valid branch name
#   S11 a tag whose only release is a draft counts as having no release
#      (GitHub's lookup by tag name returns published releases only), so the
#      run creates a second release beside the draft
#   S13 a draft release for the tag a run is about to create (a merged
#      release pull request's version, an untagged version, or the next tag
#      with no version file) goes unseen, and the run creates a second
#      release beside it
#   S14 the skip fence, as written, finds no release.md, cuts the wrong lines
#      out of it, or loses the arguments, so the plan it prints is not the
#      one the skip asked for; or it runs with no TAG, or with no Phase 2
#      block to run, and prints nothing that says so
#   S12 a repository that pushes tags without GitHub releases lands in
#      publish on every run and can never plan its next version; or the
#      skip that lets it applies to another tag, or to a tag only in this
#      clone
#
# release.md Phase 1
#   C1 a merged pull request's title holding a quote or a line break prints
#      output lines of its own
#
# release.md Phase 4
#   P1 the release pull request's commit carries files the script did not
#      bump (anything else staged) or leaves out the changelog file
#   P2 anything is pushed to the default branch
#   P3 a refused bump leaves the release branch behind
#   P4 a new changelog file, not yet known to git, makes the commit fail
#   P5 a failed commit or push leaves the run on the release branch with the
#      versions bumped, or its cleanup loses the changelog edit or unstages
#      what was staged before the run
#   P6 a release branch left by an earlier failed run is reported as "cannot
#      create the branch" with no way forward
#   P7 a version file with changes of its own is bumped and committed with
#      them, or restored over them on a failure
#   P8 a failed run started on another branch, or on a detached commit,
#      ends on the default branch instead of where it started
#   P9 a failed run unstages a changelog the user had staged before it, or
#      leaves the release's version of it staged in place of the user's
#   T1 the tag is lightweight, or on a commit other than TAG_COMMIT
#   T2 a commit that is not on the default branch, or an existing tag, is
#      tagged anyway
#   T3 a failed tag push leaves a tag in this clone with no word on how to
#      push or delete it
#   T4 a release that is not created after the tag push is reported as a
#      success, or with no way to create it later

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

_flow_test_begin "marketplace plugin: plugin.json, its own entry, and metadata.version, one line each (V2, V3, V4, V12)"
e2e_new versions-marketplace-plugin
e2e_describe "a marketplace at 4.17.0 holding alpha 1.5.0 and beta 3.10.0; release beta minor"
e2e_repo main
_marketplace_fixture 3.10.0
_commit_all
e2e_run_bin "$VERSIONS" --write --bump minor --plugin beta
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "VERSION_FILE=bump path=plugins/beta/.claude-plugin/plugin.json current=3.10.0 new=3.11.0"
e2e_expect_line "VERSION_FILE=bump path=.claude-plugin/marketplace.json entry=beta current=3.10.0 new=3.11.0"
e2e_expect_line "VERSION_FILE=bump path=.claude-plugin/marketplace.json field=metadata.version current=4.17.0 new=4.18.0"
e2e_expect_line "MARKETPLACE_VERSION=4.17.0"
e2e_expect_line "NEW_MARKETPLACE_VERSION=4.18.0"
e2e_expect_line "CURRENT_TAG_VERSION=4.17.0"
e2e_expect_line "TAG_VERSION=4.18.0"
e2e_expect_line "VERSIONS_STATE=written"
e2e_expect_equal 4 "$(_changed_lines .claude-plugin/marketplace.json)" "lines changed in marketplace.json (two versions)"
e2e_expect_file_has .claude-plugin/marketplace.json '"version": "3.11.0",'
e2e_expect_file_has .claude-plugin/marketplace.json '"metadata": { "description": "m", "version": "4.18.0" },'
e2e_expect_file_has .claude-plugin/marketplace.json '"version": "1.5.0", "keywords": ["a", "b"] },'
e2e_expect_equal "" "$(_changed_lines plugins/alpha/.claude-plugin/plugin.json)" "lines changed in alpha's plugin.json"

_flow_test_begin "marketplace version bump: patch for a plugin patch, minor for major, or the type named (V12)"
e2e_new versions-marketplace-bumps
e2e_describe "the marketplace fixture planned with each plugin bump type, and with --market-bump and --market-to"
e2e_repo main
_marketplace_fixture 3.10.0
_commit_all
e2e_run_bin "$VERSIONS" --plan --bump patch --plugin beta
e2e_expect_line "NEW_MARKETPLACE_VERSION=4.17.1"
e2e_run_bin "$VERSIONS" --plan --bump major --plugin beta
e2e_expect_line "NEW_VERSION=4.0.0"
e2e_expect_line "NEW_MARKETPLACE_VERSION=4.18.0"
e2e_run_bin "$VERSIONS" --plan --bump patch --plugin beta --market-bump major
e2e_expect_line "NEW_MARKETPLACE_VERSION=5.0.0"
e2e_run_bin "$VERSIONS" --write --to 3.10.1 --plugin beta
e2e_expect_equal 1 "$E2E_RC" "the exit status of --to without --market-to"
e2e_expect_line "VERSIONS_STATE=refused"
e2e_expect_equal "" "$(_status)" "the working tree after the refusal"
e2e_run_bin "$VERSIONS" --write --to 3.10.1 --plugin beta --market-to 4.17.1
e2e_expect_line "VERSIONS_STATE=written"
e2e_expect_line "TAG_VERSION=4.17.1"
e2e_run_bin "$VERSIONS" --write --to 3.10.1 --plugin beta --market-to 4.17.1
e2e_expect_line "VERSIONS_STATE=unchanged"

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

# _forged_lines — no output line the forged values would add, and exactly one
# VERSIONS_STATE line.
_forged_lines() {
  e2e_expect_no_line "VERSIONS_STATE=planned"
  e2e_expect_no_line "TAG_VERSION=6.6.6"
  e2e_expect_equal 1 "$(printf '%s\n' "$E2E_OUT" | grep -c '^VERSIONS_STATE=')" "VERSIONS_STATE lines"
}

_flow_test_begin "a version that is not a semantic version is refused before anything is printed (V13)"
e2e_new versions-forged-current
e2e_describe "package.json whose version holds line breaks and two output lines"
e2e_repo main
printf '{\n  "name": "x",\n  "version": "1.2.3\\nVERSIONS_STATE=planned\\nTAG_VERSION=6.6.6"\n}\n' > "$E2E_REPO/package.json"
_commit_all
e2e_run_bin "$VERSIONS" --plan --bump patch
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_line "VERSIONS_STATE=refused"
e2e_expect_out "package.json"
_forged_lines

e2e_new versions-forged-current-mismatch
e2e_describe "the same package.json beside a pyproject.toml at 1.2.4, so the files disagree"
e2e_repo main
printf '{\n  "name": "x",\n  "version": "1.2.3\\nVERSIONS_STATE=planned\\nTAG_VERSION=6.6.6"\n}\n' > "$E2E_REPO/package.json"
printf '[project]\nname = "demo"\nversion = "1.2.4"\n' > "$E2E_REPO/pyproject.toml"
_commit_all
e2e_run_bin "$VERSIONS" --plan --bump patch
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_line "VERSIONS_STATE=refused"
_forged_lines

e2e_new versions-forged-market
e2e_describe "a marketplace whose metadata.version holds a line break and an output line"
e2e_repo main
_marketplace_fixture 3.10.0
sed 's/"version": "4.17.0"/"version": "4.17.0\\nTAG_VERSION=6.6.6"/' "$E2E_REPO/.claude-plugin/marketplace.json" > "$E2E_DIR/m.json" \
  && mv "$E2E_DIR/m.json" "$E2E_REPO/.claude-plugin/marketplace.json"
_commit_all
e2e_run_bin "$VERSIONS" --plan --bump minor --plugin beta
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_line "VERSIONS_STATE=refused"
_forged_lines

e2e_new versions-forged-source
e2e_describe "a marketplace entry whose source holds a line break and an output line"
e2e_repo main
_marketplace_fixture 3.10.0
sed 's|"source": "./plugins/beta"|"source": "./plugins/beta\\nVERSIONS_STATE=planned"|' "$E2E_REPO/.claude-plugin/marketplace.json" > "$E2E_DIR/m.json" \
  && mv "$E2E_DIR/m.json" "$E2E_REPO/.claude-plugin/marketplace.json"
_commit_all
e2e_run_bin "$VERSIONS" --plan --bump minor --plugin beta
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_line "VERSIONS_STATE=refused"
_forged_lines

e2e_new versions-forged-to
e2e_describe "--to given a version followed by a line break"
e2e_repo main
_npm_fixture
_commit_all
e2e_run_bin "$VERSIONS" --write --to "1.3.0
"
e2e_expect_equal 2 "$E2E_RC" "the exit status (a usage error)"
e2e_expect_equal "" "$(_status)" "the working tree"

_flow_test_begin "a write that fails on one file leaves every file as it was (V14)"
e2e_new versions-write-fails
e2e_describe "the marketplace fixture with .claude-plugin read-only, so marketplace.json, written after beta's plugin.json, cannot be replaced"
e2e_repo main
_marketplace_fixture 3.10.0
_commit_all
chmod 555 "$E2E_REPO/.claude-plugin"
if [ -w "$E2E_REPO/.claude-plugin" ]; then
  # Root ignores the mode bits, so the write cannot be made to fail this way.
  _flow_assert_pass "SKIP: the directory stays writable for this user (root)"
else
  e2e_run_bin "$VERSIONS" --write --bump minor --plugin beta
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_line "VERSIONS_STATE=refused"
  e2e_expect_out "writing failed"
  e2e_expect_no_out "WRITTEN_PATH="
  e2e_expect_equal "" "$(_status)" "the working tree (beta's plugin.json not bumped)"
  e2e_expect_equal "" "$(find "$E2E_REPO" -name '.flow-version.*' -not -path '*/.git/*')" "temporary files left behind"
fi
chmod 755 "$E2E_REPO/.claude-plugin"

# --- release.md blocks -------------------------------------------------------
# The repository gets a bare origin inside the scratch directory, so git fetch
# and git push run for real; gh answers from fixtures.

# _origin — a bare origin with main pushed, and origin/main fetched.
_origin() {
  ( _e2e_git_env; cd "$E2E_REPO" \
      && git init -q --bare "$E2E_DIR/origin.git" \
      && git remote add origin "$E2E_DIR/origin.git" \
      && git push -q -u origin main --tags ) \
    || _flow_assert_fail "$E2E_NAME: could not create the origin"
}
_git() { ( _e2e_git_env; cd "$E2E_REPO" && git "$@" ); }
_repo_gh() { e2e_gh_fixture repo '{"nameWithOwner":"octo/market","defaultBranchRef":{"name":"main"}}'; }

# A marketplace released as v4.17.0 (beta 3.10.0), pushed to origin.
_released_marketplace() {
  e2e_repo main
  _marketplace_fixture 3.10.0
  _commit_all
  _git tag -a v4.17.0 -m "v4.17.0"
  _origin
  _repo_gh
  e2e_gh_fixture release-v4.17.0 '{"tag_name":"v4.17.0"}'
}

_flow_test_begin "Phase 2: the current version is tagged, so this run opens a release pull request (S1, S2)"
e2e_new release-plan-pr
e2e_describe "marketplace at v4.17.0 (tagged), beta 3.10.0; run as /flow:release minor beta; no release pull request yet"
_released_marketplace
e2e_gh_fixture prs-all-chore_release-4.18.0-main '[]'
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "RELEASE_TYPE=minor"
e2e_expect_line "RELEASE_PLUGIN=beta"
e2e_expect_line "DEFAULT_BRANCH=main"
e2e_expect_line "VERSION_FILE=bump path=.claude-plugin/marketplace.json entry=beta current=3.10.0 new=3.11.0"
e2e_expect_line "NEW_VERSION=3.11.0"
e2e_expect_line "NEW_MARKETPLACE_VERSION=4.18.0"
e2e_expect_line "TAG=v4.18.0"
e2e_expect_line "RELEASE_BRANCH=chore/release-4.18.0"
e2e_expect_line "RELEASE_RUN=pr"
e2e_expect_equal "" "$(_status)" "the working tree"
e2e_expect_clean_edges

e2e_new release-plan-market-type
e2e_describe "the same, run as /flow:release patch beta major"
_released_marketplace
e2e_gh_fixture prs-all-chore_release-5.0.0-main '[]'
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'patch beta major'
e2e_expect_line "NEW_VERSION=3.10.1"
e2e_expect_line "TAG=v5.0.0"
e2e_expect_line "RELEASE_RUN=pr"
e2e_expect_clean_edges

e2e_new release-plan-branch-pattern
e2e_describe "the same, with conventions.branchPatterns.release set to release/v{version}"
_released_marketplace
mkdir -p "$E2E_REPO/.claude"
printf '%s\n' '{"conventions":{"branchPatterns":{"release":"release/v{version}"}}}' > "$E2E_REPO/.claude/settings.flow.json"
e2e_gh_fixture prs-all-release_v4.18.0-main '[]'
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_line "RELEASE_BRANCH=release/v4.18.0"
e2e_expect_line "RELEASE_RUN=pr"
e2e_expect_clean_edges

_flow_test_begin "Phase 2: an open release pull request means waiting (S3)"
e2e_new release-plan-waiting
e2e_describe "the release pull request for 4.18.0 is open"
_released_marketplace
e2e_gh_fixture prs-all-chore_release-4.18.0-main '[{"number":9,"state":"OPEN","url":"https://github.com/octo/market/pull/9","mergeCommit":null}]'
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_line "RELEASE_RUN=waiting"
e2e_expect_line "RELEASE_PR=https://github.com/octo/market/pull/9"
e2e_expect_no_line "RELEASE_RUN=pr"
e2e_expect_clean_edges

# _merged_release_pr — main carries 4.18.0 from a merged release pull
# request (#9, merge commit MERGE_SHA), then one more commit; no v4.18.0 tag.
_merged_release_pr() {
  _released_marketplace
  _marketplace_fixture 3.11.0
  printf '{\n  "name": "beta",\n  "version": "3.11.0"\n}\n' > "$E2E_REPO/plugins/beta/.claude-plugin/plugin.json"
  sed 's/"version": "4.17.0"/"version": "4.18.0"/' "$E2E_REPO/.claude-plugin/marketplace.json" > "$E2E_DIR/m.json" && mv "$E2E_DIR/m.json" "$E2E_REPO/.claude-plugin/marketplace.json"
  _git commit -q -am "chore(release): beta 3.11.0, marketplace 4.18.0 (#9)"
  MERGE_SHA=$(_git rev-parse HEAD)
  printf 'later\n' > "$E2E_REPO/later.txt"
  _git add later.txt
  _git commit -q -m "docs: a later change"
  _git push -q origin main
  e2e_gh_fixture prs-all-chore_release-4.18.0-main "[{\"number\":9,\"state\":\"MERGED\",\"url\":\"https://github.com/octo/market/pull/9\",\"mergeCommit\":{\"oid\":\"$MERGE_SHA\"}}]"
}

_flow_test_begin "Phase 2: the merged release pull request is tagged at its merge commit (S4)"
e2e_new release-plan-tag
e2e_describe "main carries 4.18.0 from a merged release pull request, then one more commit; v4.18.0 does not exist; GitHub has a draft for v4.18.0-rc.1 only"
_merged_release_pr
e2e_gh_fixture releases '[{"tag_name":"v4.18.0-rc.1","draft":true}]'
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_line "RELEASE_RUN=tag"
e2e_expect_line "TAG=v4.18.0"
e2e_expect_line "TAG_COMMIT=$MERGE_SHA"
e2e_expect_no_out "NEW_VERSION="
e2e_expect_clean_edges

_flow_test_begin "Phase 2: an untagged version with no merged release pull request asks (S5)"
e2e_new release-plan-untagged
e2e_describe "package.json at 1.2.3, never tagged, no release pull request"
e2e_repo main
_npm_fixture
_commit_all
_origin
_repo_gh
e2e_gh_fixture prs-all-chore_release-1.2.3-main '[]'
e2e_gh_fixture releases '[]'
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'patch'
e2e_expect_line "RELEASE_RUN=untagged"
e2e_expect_line "TAG=v1.2.3"
e2e_expect_line "TAG_COMMIT=$(_git rev-parse HEAD)"
e2e_expect_clean_edges

_flow_test_begin "Phase 2: no version file tags the default branch with the last tag bumped (S6)"
e2e_new release-plan-no-files
e2e_describe "no version file; last tag v2.4.9; run as /flow:release patch"
e2e_repo main
_git tag -a v2.4.9 -m v2.4.9
_origin
_repo_gh
e2e_gh_fixture release-v2.4.9 '{"tag_name":"v2.4.9"}'
e2e_gh_fixture releases '[{"tag_name":"v2.4.1","draft":true}]'
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'patch'
e2e_expect_line "VERSIONS_STATE=none"
e2e_expect_line "RELEASE_RUN=tag"
e2e_expect_line "TAG=v2.4.10"
e2e_expect_line "TAG_COMMIT=$(_git rev-parse HEAD)"
e2e_expect_clean_edges

# The tag a run is about to create can already have a draft release on
# GitHub (drafted ahead, for a tag that does not exist yet); creating the
# release would make a second one.
_flow_test_begin "Phase 2: a draft release for the tag this run would create stops it (S13)"
e2e_new release-plan-tag-draft
e2e_describe "the merged release pull request for 4.18.0; GitHub has a draft release for v4.18.0, whose tag does not exist yet"
_merged_release_pr
e2e_gh_pages releases '[{"tag_name":"v4.17.0","draft":false}]' '[{"tag_name":"v4.18.0","draft":true}]'
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "STATE=blocked"
e2e_expect_line "DRAFT_RELEASE=v4.18.0"
e2e_expect_out "only a draft release for v4.18.0"
e2e_expect_no_out "RELEASE_RUN="
e2e_expect_no_out "TAG_COMMIT="
e2e_expect_clean_edges

e2e_new release-plan-tag-draft-list-fails
e2e_describe "the same, but gh fails when listing the releases"
_merged_release_pr
e2e_gh_fail releases
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_line "STATE=unavailable"
e2e_expect_no_out "RELEASE_RUN="
e2e_expect_clean_edges

e2e_new release-plan-untagged-draft
e2e_describe "package.json at 1.2.3, never tagged, no release pull request; GitHub has a draft release for v1.2.3"
e2e_repo main
_npm_fixture
_commit_all
_origin
_repo_gh
e2e_gh_fixture prs-all-chore_release-1.2.3-main '[]'
e2e_gh_fixture releases '[{"tag_name":"v1.2.3","draft":true}]'
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'patch'
e2e_expect_line "STATE=blocked"
e2e_expect_line "DRAFT_RELEASE=v1.2.3"
e2e_expect_no_out "RELEASE_RUN="
e2e_expect_clean_edges

e2e_new release-plan-no-files-draft-next
e2e_describe "no version file; v2.4.9 released; GitHub has a draft release for v2.4.10"
e2e_repo main
_git tag -a v2.4.9 -m v2.4.9
_origin
_repo_gh
e2e_gh_fixture release-v2.4.9 '{"tag_name":"v2.4.9"}'
e2e_gh_fixture releases '[{"tag_name":"v2.4.10","draft":true}]'
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'patch'
e2e_expect_line "STATE=blocked"
e2e_expect_line "DRAFT_RELEASE=v2.4.10"
e2e_expect_no_out "RELEASE_RUN="
e2e_expect_clean_edges

_flow_test_begin "Phase 2: a tag on origin with no GitHub release publishes that tag; a tag only in this clone stops (S8, S9)"
e2e_new release-plan-publish
e2e_describe "marketplace at v4.17.0, tagged and pushed, but GitHub has no release for v4.17.0"
_released_marketplace
e2e_gh_not_found release-v4.17.0
e2e_gh_fixture releases '[{"tag_name":"v4.17.0-rc.1","draft":true},{"tag_name":"v4.16.0","draft":false}]'
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "RELEASE_RUN=publish"
e2e_expect_line "TAG=v4.17.0"
e2e_expect_no_out "RELEASE_BRANCH="
e2e_expect_no_out "NEW_VERSION="
e2e_expect_no_out "DRAFT_RELEASE="
e2e_expect_clean_edges

_flow_test_begin "Phase 2: a draft release for the tag stops the run rather than creating a second release (S11)"
e2e_new release-plan-draft
e2e_describe "v4.17.0 on origin; GitHub's published-release lookup says 404, and the draft for v4.17.0 is on the second page of releases"
_released_marketplace
e2e_gh_not_found release-v4.17.0
e2e_gh_pages releases '[{"tag_name":"v4.16.0","draft":false}]' '[{"tag_name":"v4.17.0","draft":true}]'
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "STATE=blocked"
e2e_expect_line "DRAFT_RELEASE=v4.17.0"
e2e_expect_out "only a draft release for v4.17.0"
e2e_expect_no_out "RELEASE_RUN="
e2e_expect_clean_edges

e2e_new release-plan-draft-list-fails
e2e_describe "the same, but gh fails when listing the releases"
_released_marketplace
e2e_gh_not_found release-v4.17.0
e2e_gh_fail releases
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_line "STATE=unavailable"
e2e_expect_no_out "RELEASE_RUN="
e2e_expect_clean_edges

e2e_new release-plan-no-files-draft
e2e_describe "no version file; v2.4.9 on origin with only a draft release"
e2e_repo main
_git tag -a v2.4.9 -m v2.4.9
_origin
_repo_gh
e2e_gh_not_found release-v2.4.9
e2e_gh_fixture releases '[{"tag_name":"v2.4.9","draft":true}]'
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'patch'
e2e_expect_line "STATE=blocked"
e2e_expect_line "DRAFT_RELEASE=v2.4.9"
e2e_expect_no_out "RELEASE_RUN="
e2e_expect_no_out "TAG=v2.4.10"
e2e_expect_clean_edges

e2e_new release-plan-release-unknown
e2e_describe "the same, but gh fails when asked for the release"
_released_marketplace
e2e_gh_fail release-v4.17.0
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_line "STATE=unavailable"
e2e_expect_no_out "RELEASE_RUN="
e2e_expect_clean_edges

e2e_new release-plan-local-tag
e2e_describe "marketplace at 4.17.0, pushed, tagged v4.17.0 in this clone only"
e2e_repo main
_marketplace_fixture 3.10.0
_commit_all
_origin
_git tag -a v4.17.0 -m "v4.17.0"
_repo_gh
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_line "STATE=blocked"
e2e_expect_line "LOCAL_TAG=v4.17.0"
e2e_expect_no_out "RELEASE_RUN="
e2e_expect_clean_edges

e2e_new release-plan-no-files-publish
e2e_describe "no version file; v2.4.9 pushed with no GitHub release"
e2e_repo main
_git tag -a v2.4.9 -m v2.4.9
_origin
_repo_gh
e2e_gh_not_found release-v2.4.9
e2e_gh_fixture releases '[]'
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'patch'
e2e_expect_line "RELEASE_RUN=publish"
e2e_expect_line "TAG=v2.4.9"
e2e_expect_no_out "TAG=v2.4.10"
e2e_expect_clean_edges

e2e_new release-plan-no-files-local-tag
e2e_describe "no version file; v2.4.9 in this clone only"
e2e_repo main
_origin
_git tag -a v2.4.9 -m v2.4.9
_repo_gh
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'patch'
e2e_expect_line "STATE=blocked"
e2e_expect_line "LOCAL_TAG=v2.4.9"
e2e_expect_no_out "RELEASE_RUN="
e2e_expect_clean_edges

# A repository that pushes tags but never makes GitHub releases would land in
# publish on every run. The skip treats the tag as released. gh fails when
# asked for the tag's release, so a run that still asks shows
# STATE=unavailable rather than the plan.
_flow_test_begin "Phase 2: skipping the GitHub release for a tag on origin plans the next version (S12)"
e2e_new release-plan-skip-publish
e2e_describe "v4.17.0 on origin with no release; Phase 2 run with FLOW_RELEASE_SKIP_PUBLISH=v4.17.0"
_released_marketplace
e2e_gh_fail release-v4.17.0
e2e_gh_fixture prs-all-chore_release-4.18.0-main '[]'
e2e_run_block FLOW_RELEASE_SKIP_PUBLISH=v4.17.0 "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "RELEASE_RUN=pr"
e2e_expect_line "TAG=v4.18.0"
e2e_expect_line "RELEASE_BRANCH=chore/release-4.18.0"
e2e_expect_no_out "STATE=unavailable"
e2e_expect_clean_edges

e2e_new release-plan-skip-other-tag
e2e_describe "the same, but the skip names v4.16.0, not the current tag"
_released_marketplace
e2e_gh_not_found release-v4.17.0
e2e_gh_fixture releases '[]'
e2e_run_block FLOW_RELEASE_SKIP_PUBLISH=v4.16.0 "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_line "RELEASE_RUN=publish"
e2e_expect_line "TAG=v4.17.0"
e2e_expect_clean_edges

e2e_new release-plan-skip-local-tag
e2e_describe "v4.17.0 in this clone only, with the skip naming it"
e2e_repo main
_marketplace_fixture 3.10.0
_commit_all
_origin
_git tag -a v4.17.0 -m "v4.17.0"
_repo_gh
e2e_run_block FLOW_RELEASE_SKIP_PUBLISH=v4.17.0 "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_line "STATE=blocked"
e2e_expect_line "LOCAL_TAG=v4.17.0"
e2e_expect_no_out "RELEASE_RUN="
e2e_expect_clean_edges

e2e_new release-plan-no-files-skip
e2e_describe "no version file; v2.4.9 on origin with no release; the skip names v2.4.9"
e2e_repo main
_git tag -a v2.4.9 -m v2.4.9
_origin
_repo_gh
e2e_gh_fail release-v2.4.9
e2e_gh_fixture releases '[]'
e2e_run_block FLOW_RELEASE_SKIP_PUBLISH=v2.4.9 "$RELEASE_MD" RELEASE_PLAN_BLOCK 'patch'
e2e_expect_line "RELEASE_RUN=tag"
e2e_expect_line "TAG=v2.4.10"
e2e_expect_clean_edges

# The fence the skip answer runs, whole and as written: it finds release.md
# through the plugin root (CLAUDE_PLUGIN_ROOT, as Claude Code sets it), cuts
# the Phase 2 block out of it, and runs that with the skip set and the
# arguments Claude Code fills in for $ARGUMENTS. gh fails when asked for
# v4.17.0's release, so a run where the skip did not reach the block shows
# STATE=unavailable rather than the plan.
_flow_test_begin "Phase 2 skip fence: runs Phase 2 again with the tag counted as released (S14)"
e2e_new release-skip-fence
e2e_describe "v4.17.0 on origin with no release; the skip fence with TAG=v4.17.0, run as /flow:release minor beta"
_released_marketplace
e2e_gh_fail release-v4.17.0
e2e_gh_fixture prs-all-chore_release-4.18.0-main '[]'
e2e_run_fence TAG=v4.17.0 "$RELEASE_MD" 'RELEASE_SKIP_BLOCK_BEGIN' 'minor beta'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "RELEASE_TYPE=minor"
e2e_expect_line "RELEASE_PLUGIN=beta"
e2e_expect_line "RELEASE_RUN=pr"
e2e_expect_line "TAG=v4.18.0"
e2e_expect_line "RELEASE_BRANCH=chore/release-4.18.0"
e2e_expect_no_out "STATE=unavailable"
e2e_expect_no_out "RELEASE_RUN=publish"
e2e_expect_clean_edges

e2e_new release-skip-fence-no-tag
e2e_describe "the skip fence run without TAG"
_released_marketplace
e2e_run_fence "$RELEASE_MD" 'RELEASE_SKIP_BLOCK_BEGIN' 'minor beta'
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_line "STATE=blocked"
e2e_expect_out "set TAG to the tag whose release is skipped"
e2e_expect_no_out "RELEASE_RUN="
e2e_expect_clean_edges

e2e_new release-skip-fence-no-block
e2e_describe "the skip fence with TAG=v4.17.0, where the plugin root's release.md has no Phase 2 block"
_released_marketplace
e2e_plugin_copy commands/release.md '# Create Release (no Phase 2 block in this copy)'
e2e_run_fence TAG=v4.17.0 "$RELEASE_MD" 'RELEASE_SKIP_BLOCK_BEGIN' 'minor beta'
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_line "STATE=blocked"
e2e_expect_out "cannot read the Phase 2 block"
e2e_expect_no_out "RELEASE_RUN="
e2e_expect_clean_edges

_flow_test_begin "Phase 2: a release branch name that is not a valid branch name stops the run (S10)"
e2e_new release-plan-bad-pattern
e2e_describe "conventions.branchPatterns.release set to 'release {version}', with a space"
_released_marketplace
mkdir -p "$E2E_REPO/.claude"
printf '%s\n' '{"conventions":{"branchPatterns":{"release":"release {version}"}}}' > "$E2E_REPO/.claude/settings.flow.json"
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_line "STATE=blocked"
e2e_expect_out "not a valid branch name"
e2e_expect_no_out "RELEASE_BRANCH="
e2e_expect_no_out "RELEASE_RUN="
e2e_expect_clean_edges

e2e_new release-plan-bad-next-version
e2e_describe "a version script that answers with a next version holding a slash"
_released_marketplace
e2e_plugin_copy bin/flow-release-versions.sh '#!/bin/sh
case " $* " in *" --bump "*) printf "%s\n" "CURRENT_TAG_VERSION=4.17.0" "TAG_VERSION=4.18.0/x" "VERSIONS_STATE=planned" ;;
  *) printf "%s\n" "CURRENT_TAG_VERSION=4.17.0" "VERSIONS_STATE=planned" ;; esac'
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_line "STATE=blocked"
e2e_expect_no_out "RELEASE_BRANCH="
e2e_expect_no_out "RELEASE_RUN="
e2e_expect_clean_edges

e2e_new release-plan-bad-current-version
e2e_describe "a version script that answers with a current version holding a slash"
_released_marketplace
e2e_plugin_copy bin/flow-release-versions.sh '#!/bin/sh
printf "%s\n" "CURRENT_TAG_VERSION=4.17.0/x" "VERSIONS_STATE=planned"'
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_line "STATE=blocked"
e2e_expect_no_out "RELEASE_RUN="
e2e_expect_clean_edges

_flow_test_begin "Phase 2: a local release branch left by an earlier run is named, with both ways forward (P6)"
e2e_new release-plan-local-branch
e2e_describe "the released marketplace with a local chore/release-4.18.0 branch and no pull request or branch on origin"
_released_marketplace
_git branch chore/release-4.18.0
e2e_gh_fixture prs-all-chore_release-4.18.0-main '[]'
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_line "STATE=blocked"
e2e_expect_line "LOCAL_BRANCH=chore/release-4.18.0"
e2e_expect_no_out "RELEASE_RUN="
e2e_expect_clean_edges

_flow_test_begin "Phase 2: refused off the default branch, behind origin, or with a bad argument (S7)"
e2e_new release-plan-off-default
e2e_describe "on a feature branch"
_released_marketplace
_git switch -q -c feature/x
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_line "STATE=blocked"
e2e_expect_out "check out main at origin/main"
e2e_expect_no_out "RELEASE_RUN="

e2e_new release-plan-behind
e2e_describe "on main, one commit behind origin/main"
_released_marketplace
_git commit -q --allow-empty -m "ahead"
_git push -q origin main
_git reset -q --hard HEAD~1
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'minor beta'
e2e_expect_line "STATE=blocked"
e2e_expect_no_out "RELEASE_RUN="

e2e_new release-plan-bad-type
e2e_describe "run as /flow:release sideways"
e2e_repo main
e2e_run_block "$RELEASE_MD" RELEASE_PLAN_BLOCK 'sideways'
e2e_expect_line "STATE=blocked"
e2e_expect_out "patch, minor or major"
e2e_expect_clean_edges

# The Phase 4 blocks write, so a second shell run in the same repository would
# find the work already done. Each shell gets a fresh repository instead.
ALL_SHELLS="$E2E_FENCE_SHELLS"

_flow_test_begin "Phase 4 pr: a release branch with only the bump and changelog, pushed; main untouched (P1, P2)"
for E2E_FENCE_SHELLS in $ALL_SHELLS; do
  e2e_new "release-pr-marketplace-$E2E_FENCE_SHELLS"
  e2e_describe "released marketplace; beta's CHANGELOG.md edited; an unrelated file staged; block under $E2E_FENCE_SHELLS"
  _released_marketplace
  printf '# beta\n' > "$E2E_REPO/plugins/beta/CHANGELOG.md"
  _commit_all
  _git push -q origin main
  ORIGIN_MAIN=$(_git rev-parse origin/main)
  printf '# beta\n\n## 3.11.0\n- new\n' > "$E2E_REPO/plugins/beta/CHANGELOG.md"
  printf 'staged\n' > "$E2E_REPO/staged.txt"
  _git add staged.txt
  e2e_run_block RELEASE_BRANCH=chore/release-4.18.0 DEFAULT_BRANCH=main VERSION=3.11.0 PLUGIN=beta \
    MARKET_VERSION=4.18.0 TAG_PREFIX=v CHANGELOG_FILE=plugins/beta/CHANGELOG.md "$RELEASE_MD" RELEASE_PR_BLOCK
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "PR_STATE=pushed"
  e2e_expect_line 'PR_TITLE="chore(release): beta 3.11.0, marketplace 4.18.0"'
  e2e_expect_equal "chore/release-4.18.0" "$(_git branch --show-current)" "the branch afterwards"
  e2e_expect_equal "chore(release): beta 3.11.0, marketplace 4.18.0" "$(_head_subject)" "the bump commit's subject"
  e2e_expect_equal ".claude-plugin/marketplace.json plugins/beta/.claude-plugin/plugin.json plugins/beta/CHANGELOG.md" "$(_head_files)" "the files in the bump commit"
  e2e_expect_equal "A  staged.txt" "$(_status)" "the working tree (the staged file stays staged)"
  e2e_expect_equal "$(_git rev-parse HEAD)" "$(_git ls-remote origin refs/heads/chore/release-4.18.0 | cut -f1)" "origin's release branch"
  e2e_expect_equal "$ORIGIN_MAIN" "$(_git ls-remote origin refs/heads/main | cut -f1)" "origin's main (unchanged)"
done

for E2E_FENCE_SHELLS in $ALL_SHELLS; do
  e2e_new "release-pr-root-$E2E_FENCE_SHELLS"
  e2e_describe "npm package released as v1.2.3; block under $E2E_FENCE_SHELLS with VERSION=1.3.0"
  e2e_repo main
  _npm_fixture
  _commit_all
  _git tag -a v1.2.3 -m v1.2.3
  _origin
  e2e_run_block RELEASE_BRANCH=chore/release-1.3.0 DEFAULT_BRANCH=main VERSION=1.3.0 TAG_PREFIX=v "$RELEASE_MD" RELEASE_PR_BLOCK
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line 'PR_TITLE="chore(release): v1.3.0"'
  e2e_expect_equal "package.json" "$(_head_files)" "the files in the bump commit"
done

for E2E_FENCE_SHELLS in $ALL_SHELLS; do
  e2e_new "release-pr-refused-$E2E_FENCE_SHELLS"
  e2e_describe "beta's versions disagree; block under $E2E_FENCE_SHELLS"
  e2e_repo main
  _marketplace_fixture 3.9.0
  _commit_all
  _origin
  e2e_run_block RELEASE_BRANCH=chore/release-4.18.0 DEFAULT_BRANCH=main VERSION=3.10.1 PLUGIN=beta \
    MARKET_VERSION=4.18.0 TAG_PREFIX=v "$RELEASE_MD" RELEASE_PR_BLOCK
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_line "PR_STATE=blocked"
  e2e_expect_equal "main" "$(_git branch --show-current)" "the branch afterwards"
  e2e_expect_equal "" "$(_git branch --list chore/release-4.18.0)" "the release branch (removed)"
  e2e_expect_equal "fixtures" "$(_head_subject)" "HEAD's subject"
  e2e_expect_equal "" "$(_status)" "the working tree"
done

# An npm package released as v1.2.3 and pushed, for the release pull request
# block run with VERSION=1.3.0.
_released_npm() {
  e2e_repo main
  _npm_fixture
  _commit_all
  _git tag -a v1.2.3 -m v1.2.3
  _origin
}
_pr_block() {
  e2e_run_block RELEASE_BRANCH=chore/release-1.3.0 DEFAULT_BRANCH=main VERSION=1.3.0 TAG_PREFIX=v "$@" "$RELEASE_MD" RELEASE_PR_BLOCK
}
# _left_as_before — the state the block found: on main, no release branch,
# package.json at 1.2.3, the changelog edit and the staged file kept.
_left_as_before() {
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_line "PR_STATE=blocked"
  e2e_expect_out "PR_CLEANUP="
  e2e_expect_equal "main" "$(_git branch --show-current)" "the branch afterwards"
  e2e_expect_equal "" "$(_git branch --list chore/release-1.3.0)" "the local release branch (removed)"
  e2e_expect_equal "fixtures" "$(_head_subject)" "HEAD's subject"
  e2e_expect_file_has package.json '"version": "1.2.3"'
  e2e_expect_file_has CHANGELOG.md '## 1.3.0'
  e2e_expect_equal "$(printf ' M CHANGELOG.md\nA  staged.txt')" "$(_status)" "the working tree (changelog edit kept, staged file still staged)"
}

_flow_test_begin "Phase 4 pr: a new changelog file is committed with the bump (P4)"
for E2E_FENCE_SHELLS in $ALL_SHELLS; do
  e2e_new "release-pr-new-changelog-$E2E_FENCE_SHELLS"
  e2e_describe "npm package released as v1.2.3; CHANGELOG.md written for the first time, not yet known to git; block under $E2E_FENCE_SHELLS"
  _released_npm
  printf '# Changelog\n\n## 1.3.0\n- new\n' > "$E2E_REPO/CHANGELOG.md"
  _pr_block CHANGELOG_FILE=CHANGELOG.md
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "PR_STATE=pushed"
  e2e_expect_equal "CHANGELOG.md package.json" "$(_head_files)" "the files in the bump commit"
  e2e_expect_equal "" "$(_status)" "the working tree"
done

_flow_test_begin "Phase 4 pr: a failed commit or push puts everything back as it was (P5)"
for E2E_FENCE_SHELLS in $ALL_SHELLS; do
  e2e_new "release-pr-commit-fails-$E2E_FENCE_SHELLS"
  e2e_describe "a pre-commit hook that fails; CHANGELOG.md edited; an unrelated file staged; block under $E2E_FENCE_SHELLS"
  e2e_repo main
  _npm_fixture
  printf '# Changelog\n' > "$E2E_REPO/CHANGELOG.md"
  _commit_all
  _git tag -a v1.2.3 -m v1.2.3
  _origin
  printf '# Changelog\n\n## 1.3.0\n- new\n' > "$E2E_REPO/CHANGELOG.md"
  printf 'staged\n' > "$E2E_REPO/staged.txt"
  _git add staged.txt
  mkdir -p "$E2E_REPO/.git/hooks"
  printf '#!/bin/sh\nexit 1\n' > "$E2E_REPO/.git/hooks/pre-commit"
  chmod +x "$E2E_REPO/.git/hooks/pre-commit"
  _pr_block CHANGELOG_FILE=CHANGELOG.md
  _left_as_before
  e2e_expect_out "git commit failed"
done

for E2E_FENCE_SHELLS in $ALL_SHELLS; do
  e2e_new "release-pr-push-fails-$E2E_FENCE_SHELLS"
  e2e_describe "origin unreachable when the branch is pushed; CHANGELOG.md edited; an unrelated file staged; block under $E2E_FENCE_SHELLS"
  e2e_repo main
  _npm_fixture
  printf '# Changelog\n' > "$E2E_REPO/CHANGELOG.md"
  _commit_all
  _git tag -a v1.2.3 -m v1.2.3
  _origin
  printf '# Changelog\n\n## 1.3.0\n- new\n' > "$E2E_REPO/CHANGELOG.md"
  printf 'staged\n' > "$E2E_REPO/staged.txt"
  _git add staged.txt
  _git remote set-url origin "$E2E_DIR/missing.git"
  _pr_block CHANGELOG_FILE=CHANGELOG.md
  _left_as_before
  e2e_expect_out "git push"
done

# _released_with_changelog <commit|push> — the npm package released as
# v1.2.3 with a committed CHANGELOG.md, then made to fail at that step: a
# pre-commit hook that fails, or origin unreachable.
_released_with_changelog() {
  e2e_repo main
  _npm_fixture
  printf '# Changelog\n' > "$E2E_REPO/CHANGELOG.md"
  _commit_all
  _git tag -a v1.2.3 -m v1.2.3
  _origin
  case "$1" in
    commit)
      mkdir -p "$E2E_REPO/.git/hooks"
      printf '#!/bin/sh\nexit 1\n' > "$E2E_REPO/.git/hooks/pre-commit"
      chmod +x "$E2E_REPO/.git/hooks/pre-commit" ;;
    push) _git remote set-url origin "$E2E_DIR/missing.git" ;;
  esac
}

_flow_test_begin "Phase 4 pr: a failed run returns to what was checked out, and keeps a changelog staged before (P8, P9)"
for E2E_FENCE_SHELLS in $ALL_SHELLS; do
  e2e_new "release-pr-undo-branch-$E2E_FENCE_SHELLS"
  e2e_describe "the block run from the branch release-base, not main; origin unreachable at the push; block under $E2E_FENCE_SHELLS"
  _released_with_changelog push
  _git switch -q -c release-base
  _pr_block
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_equal "release-base" "$(_git branch --show-current)" "the branch afterwards (the one the block started on)"
  e2e_expect_equal "" "$(_git branch --list chore/release-1.3.0)" "the local release branch (removed)"
  e2e_expect_out "release-base is checked out"

  e2e_new "release-pr-undo-detached-$E2E_FENCE_SHELLS"
  e2e_describe "the block run on a detached HEAD at main's commit; origin unreachable at the push; block under $E2E_FENCE_SHELLS"
  _released_with_changelog push
  START=$(_git rev-parse HEAD)
  _git switch -q --detach "$START"
  _pr_block
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_equal "" "$(_git symbolic-ref -q --short HEAD)" "the branch afterwards (still detached)"
  e2e_expect_equal "$START" "$(_git rev-parse HEAD)" "the detached commit afterwards"
  e2e_expect_equal "" "$(_git branch --list chore/release-1.3.0)" "the local release branch (removed)"

  for STEP in commit push; do
    e2e_new "release-pr-undo-staged-changelog-$STEP-$E2E_FENCE_SHELLS"
    e2e_describe "a draft changelog entry staged, the final one in the working tree; the $STEP fails; block under $E2E_FENCE_SHELLS"
    _released_with_changelog "$STEP"
    printf '# Changelog\n\n## 1.3.0\n- draft\n' > "$E2E_REPO/CHANGELOG.md"
    _git add CHANGELOG.md
    printf '# Changelog\n\n## 1.3.0\n- final\n' > "$E2E_REPO/CHANGELOG.md"
    _pr_block CHANGELOG_FILE=CHANGELOG.md
    e2e_expect_equal 1 "$E2E_RC" "the exit status"
    e2e_expect_equal "main" "$(_git branch --show-current)" "the branch afterwards"
    e2e_expect_equal "MM CHANGELOG.md" "$(_status)" "the working tree (the staged draft is still staged, the final edit still unstaged)"
    e2e_expect_equal "$(printf '# Changelog\n\n## 1.3.0\n- draft')" "$(_git show :CHANGELOG.md)" "the staged changelog (the draft)"
    e2e_expect_file_has CHANGELOG.md '- final'
  done
done
E2E_FENCE_SHELLS="$ALL_SHELLS"

_flow_test_begin "Phase 4 pr: a release branch left by an earlier run is named, with both ways forward (P6)"
for E2E_FENCE_SHELLS in $ALL_SHELLS; do
  e2e_new "release-pr-branch-exists-$E2E_FENCE_SHELLS"
  e2e_describe "the local branch chore/release-1.3.0 already exists; block under $E2E_FENCE_SHELLS"
  _released_npm
  _git branch chore/release-1.3.0
  _pr_block
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_line "PR_STATE=blocked"
  e2e_expect_out "git push -u origin chore/release-1.3.0"
  e2e_expect_out "git branch -D chore/release-1.3.0"
  e2e_expect_equal "main" "$(_git branch --show-current)" "the branch afterwards"
  e2e_expect_equal "fixtures" "$(_git log -1 --format=%s chore/release-1.3.0)" "the existing branch (untouched)"
  e2e_expect_equal "" "$(_status)" "the working tree"
done

_flow_test_begin "Phase 4 pr: a version file with changes of its own stops the run before anything is written (P7)"
for E2E_FENCE_SHELLS in $ALL_SHELLS; do
  e2e_new "release-pr-dirty-version-file-$E2E_FENCE_SHELLS"
  e2e_describe "package.json has an uncommitted change of its own; block under $E2E_FENCE_SHELLS"
  _released_npm
  sed 's/"test": "true"/"test": "make test"/' "$E2E_REPO/package.json" > "$E2E_DIR/p.json" && mv "$E2E_DIR/p.json" "$E2E_REPO/package.json"
  _pr_block
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_line "PR_STATE=blocked"
  e2e_expect_out "package.json"
  e2e_expect_equal "main" "$(_git branch --show-current)" "the branch afterwards"
  e2e_expect_equal "" "$(_git branch --list chore/release-1.3.0)" "the release branch (never created)"
  e2e_expect_file_has package.json '"test": "make test"'
  e2e_expect_file_has package.json '"version": "1.2.3"'
done

_flow_test_begin "Phase 4 tag: an annotated tag on the merge commit, not pushed by the block (T1, T2)"
for E2E_FENCE_SHELLS in $ALL_SHELLS; do
  e2e_new "release-tag-$E2E_FENCE_SHELLS"
  e2e_describe "a released marketplace with one more commit; tag the earlier commit; block under $E2E_FENCE_SHELLS"
  _released_marketplace
  TARGET=$(_git rev-parse HEAD)
  _git commit -q --allow-empty -m "later"
  _git push -q origin main
  e2e_run_block TAG=v4.18.0 TAG_COMMIT="$TARGET" DEFAULT_BRANCH=main "TITLE=v4.18.0 — beta 3.11.0: faster" "$RELEASE_MD" RELEASE_TAG_BLOCK
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "TAG_STATE=created"
  e2e_expect_equal "tag" "$(_git cat-file -t v4.18.0)" "the tag's type (annotated)"
  e2e_expect_equal "$TARGET" "$(_git rev-parse 'v4.18.0^{commit}')" "the tagged commit"
  e2e_expect_equal "v4.18.0 — beta 3.11.0: faster" "$(_git tag -l --format='%(contents:subject)' v4.18.0)" "the tag message"
  e2e_expect_equal "" "$(_git ls-remote origin refs/tags/v4.18.0)" "the tag on origin (pushed only after the block)"
done
E2E_FENCE_SHELLS="$ALL_SHELLS"

e2e_new release-tag-off-branch
e2e_describe "TAG_COMMIT is a commit that is not on origin/main"
_released_marketplace
_git switch -q -c side
_git commit -q --allow-empty -m "side"
SIDE=$(_git rev-parse HEAD)
_git switch -q main
e2e_run_block TAG=v4.18.0 TAG_COMMIT="$SIDE" DEFAULT_BRANCH=main "$RELEASE_MD" RELEASE_TAG_BLOCK
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_line "TAG_STATE=blocked"
e2e_expect_equal "" "$(_git tag -l v4.18.0)" "the tag"

e2e_new release-tag-exists
e2e_describe "the tag v4.17.0 already exists"
_released_marketplace
e2e_run_block TAG=v4.17.0 TAG_COMMIT="$(_git rev-parse HEAD)" DEFAULT_BRANCH=main "$RELEASE_MD" RELEASE_TAG_BLOCK
e2e_expect_equal 1 "$E2E_RC" "the exit status"
e2e_expect_line "TAG_STATE=blocked"
e2e_expect_out "already exists"

# The whole tag fence: the block, the push and the release, as one call.
_flow_test_begin "Phase 4 tag fence: tag, push and release; a failed push or release names the way forward (T3, T4)"
for E2E_FENCE_SHELLS in $ALL_SHELLS; do
  e2e_new "release-tag-fence-$E2E_FENCE_SHELLS"
  e2e_describe "a released marketplace; tag its head as v4.18.0 and publish; block under $E2E_FENCE_SHELLS"
  _released_marketplace
  e2e_gh_fixture release-create-v4.18.0 'https://github.com/octo/market/releases/tag/v4.18.0'
  e2e_run_fence TAG=v4.18.0 TAG_COMMIT="$(_git rev-parse HEAD)" DEFAULT_BRANCH=main CHANGELOG=notes "$RELEASE_MD" RELEASE_TAG_BLOCK_BEGIN
  e2e_expect_equal 0 "$E2E_RC" "the exit status"
  e2e_expect_line "TAG_STATE=created"
  e2e_expect_line "https://github.com/octo/market/releases/tag/v4.18.0"
  e2e_expect_equal "$(_git rev-parse v4.18.0)" "$(_git ls-remote origin refs/tags/v4.18.0 | cut -f1)" "the tag on origin"
  e2e_expect_clean_edges

  e2e_new "release-tag-fence-push-fails-$E2E_FENCE_SHELLS"
  e2e_describe "the same, with origin unreachable when the tag is pushed; block under $E2E_FENCE_SHELLS"
  _released_marketplace
  _git remote set-url origin "$E2E_DIR/missing.git"
  e2e_run_fence TAG=v4.18.0 TAG_COMMIT="$(_git rev-parse HEAD)" DEFAULT_BRANCH=main CHANGELOG=notes "$RELEASE_MD" RELEASE_TAG_BLOCK_BEGIN
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_out "git push origin v4.18.0"
  e2e_expect_out "git tag -d v4.18.0"
  e2e_expect_clean_edges

  e2e_new "release-tag-fence-release-fails-$E2E_FENCE_SHELLS"
  e2e_describe "the same, with gh failing to create the release after the push; block under $E2E_FENCE_SHELLS"
  _released_marketplace
  e2e_gh_fail release-create-v4.18.0
  e2e_run_fence TAG=v4.18.0 TAG_COMMIT="$(_git rev-parse HEAD)" DEFAULT_BRANCH=main CHANGELOG=notes "$RELEASE_MD" RELEASE_TAG_BLOCK_BEGIN
  e2e_expect_equal 1 "$E2E_RC" "the exit status"
  e2e_expect_out "run /flow:release again"
  e2e_expect_equal "$(_git rev-parse v4.18.0)" "$(_git ls-remote origin refs/tags/v4.18.0 | cut -f1)" "the tag on origin"
done
E2E_FENCE_SHELLS="$ALL_SHELLS"

_flow_test_begin "Phase 4 publish fence: the release is created for the tag already on origin"
e2e_new release-publish-fence
e2e_describe "v4.17.0 on origin with no release; the publish fence with TAG=v4.17.0"
_released_marketplace
e2e_gh_fixture release-create-v4.17.0 'https://github.com/octo/market/releases/tag/v4.17.0'
e2e_run_fence TAG=v4.17.0 CHANGELOG=notes "$RELEASE_MD" 'set TAG from Phase 2'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "https://github.com/octo/market/releases/tag/v4.17.0"
e2e_expect_clean_edges

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

e2e_new release-context-title-lines
e2e_describe "a merged PR whose title holds a double quote and a line break followed by MERGED_PR_COUNT=99 (C1)"
e2e_repo main
( _e2e_git_env; cd "$E2E_REPO" && git tag v1.0.0 && printf 'x\n' > a.txt && git add a.txt && git commit -q -m 'feat: add a' )
e2e_gh_fixture merged-prs-pr-pr '[{"number":7,"title":"feat: say \"hi\"\nMERGED_PR_COUNT=99\nx","labels":[{"name":"x\ny"}]}]'
e2e_run_fence "$RELEASE_MD" '### Merged PRs Since Last Release'
e2e_expect_equal 0 "$E2E_RC" "the exit status"
e2e_expect_line "MERGED_PR_COUNT=1"
e2e_expect_no_line "MERGED_PR_COUNT=99"
e2e_expect_line 'MERGED_PR=number=7 labels="x\ny" title="feat: say \"hi\"\nMERGED_PR_COUNT=99\nx"'
e2e_expect_clean_edges

e2e_new release-context-gh-down
e2e_describe "no tag; gh fails"
e2e_repo main
e2e_gh_fail merged-prs-pr-pr
e2e_run_fence "$RELEASE_MD" '### Merged PRs Since Last Release'
e2e_expect_line "LAST_TAG=none"
e2e_expect_line "STATE=unavailable"
