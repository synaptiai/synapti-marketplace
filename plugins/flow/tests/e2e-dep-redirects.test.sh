# shellcheck shell=bash
# End-to-end: a dependency redirected away from its registry is reported the
# same way in every ecosystem bin/flow-dep-diff.sh reads, and a manifest it
# cannot parse says so (#248, following #217).
#
# Each scenario commits a base and a head of one manifest in a scratch
# repository and runs bin/flow-dep-diff.sh over the range. Following the test
# convention #217 ended with, each fixture asserts the complete set of
# STATE, DEP_ (but DEP_BASELINE) and MANIFEST_UNPARSED records, not the
# presence or absence of one spelling. The artifact for each scenario is
# written to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the scenarios:
#   R1 a Gemfile gem with git:, github: or path: (either hash syntax), or one
#      inside a git block, reads as an ordinary unpinned gem from rubygems.org
#   R2 a gem resolved in a Gemfile.lock GIT section reads the same way
#   R3 a parenthesised gem("x") call is skipped silently with STATE=ok
#   R4 a gem line the parser cannot read is skipped instead of making the
#      file unreadable
#   R5 tool.uv.sources my_pkg does not redirect the dependency my-pkg
#   R6 near-names between Python names are measured as written, so
#      django_rest_framewrk is not reported against django-rest-framework,
#      and my_pkg is reported as a near-name of the project my-pkg
#   R7 the same normalisation is applied to npm, where my_pkg and my-pkg are
#      two packages
#   R8 a direct reference with a scheme outside a fixed list becomes a
#      version string; an environment marker becomes part of the target
#   R9 a package.json spec that fetches from git or a path is not a redirect

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

if ! python3 -c "
try:
    import tomllib
except ImportError:
    import tomli
" >/dev/null 2>&1; then
  _flow_test_begin "dependency redirects: TOML parser prerequisite"
  _flow_assert_pass "SKIP: neither tomllib nor tomli is importable"
  return 0
fi

# _dep <name> <purpose> <manifest path> <base content> <head content> <expected records>
_dep() {
  _flow_test_begin "$1"
  e2e_new "$1"
  e2e_describe "$2"
  e2e_repo feature/issue-248-e2e
  (
    _e2e_git_env
    cd "$E2E_REPO" || exit 1
    mkdir -p "$(dirname "$3")"
    printf '%s' "$4" > "$3"
    git add -A && git commit -q -m base
    printf '%s' "$5" > "$3"
    git add -A && git commit -q -m head
  ) || _flow_assert_fail "$1: could not commit the fixture"
  { printf 'manifest: %s\n--- base\n%s\n--- head\n%s\n' "$3" "$4" "$5"; } | _e2e_art
  e2e_run_bin bin/flow-dep-diff.sh --base HEAD~1 --head HEAD
  e2e_expect_equal "$6" "$(printf '%s\n' "$E2E_OUT" | grep -E '^(STATE=|DEP_|MANIFEST_UNPARSED=)' | grep -v '^DEP_BASELINE')" "the records"
  e2e_expect_clean_edges
}

# --- Ruby (R1-R4) ------------------------------------------------------------
_dep dep-gem-git "a gem built from a fork with git: is a redirect (R1)" Gemfile \
$'source "https://rubygems.org"\ngem "rails", "7.0.0"\n' \
$'source "https://rubygems.org"\ngem "rails", "7.0.0"\ngem "nokogiri", git: "https://github.com/evil/nokogiri"\n' \
'STATE=ok
DEP_ADDED=nokogiri@(unpinned) manifest=Gemfile:3
DEP_REPLACED=nokogiri -> https://github.com/evil/nokogiri@(unpinned) manifest=Gemfile:3'

_dep dep-gem-github "github: with a branch, in the hash-rocket syntax too (R1)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem "rack", github: "evil/rack", branch: "main"\ngem "rake", :github => "evil/rake"\n' \
'STATE=ok
DEP_ADDED=rack@(unpinned) manifest=Gemfile:2
DEP_ADDED=rake@(unpinned) manifest=Gemfile:3
DEP_REPLACED=rack -> github:evil/rack@main manifest=Gemfile:2
DEP_REPLACED=rake -> github:evil/rake@(unpinned) manifest=Gemfile:3'

_dep dep-gem-path "path: in the hash-rocket syntax (R1)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem "local", "0.1.0", :path => "../local"\n' \
'STATE=ok
DEP_ADDED=local@0.1.0 manifest=Gemfile:2
DEP_REPLACED=local -> ../local@0.1.0 manifest=Gemfile:2'

_dep dep-gem-git-block "a gem inside a git block; a gem in a group block after it is not redirected (R1)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngit "https://github.com/evil/rails.git" do\n  gem "activesupport"\nend\ngroup :test do\n  gem "rspec", "3.12.0"\nend\n' \
'STATE=ok
DEP_ADDED=activesupport@(unpinned) manifest=Gemfile:3
DEP_ADDED=rspec@3.12.0 manifest=Gemfile:6
DEP_REPLACED=activesupport -> https://github.com/evil/rails.git@(unpinned) manifest=Gemfile:3'

_dep dep-gemfile-lock-git "a gem resolved in a Gemfile.lock GIT section is a redirect at its revision (R2)" Gemfile.lock \
$'GEM\n  remote: https://rubygems.org/\n  specs:\n    rails (7.0.0)\n' \
$'GIT\n  remote: https://github.com/evil/nokogiri\n  revision: abc123\n  specs:\n    nokogiri (1.15.0)\n\nGEM\n  remote: https://rubygems.org/\n  specs:\n    rails (7.0.0)\n' \
'STATE=ok
DEP_ADDED=nokogiri@1.15.0 manifest=Gemfile.lock:5
DEP_REPLACED=nokogiri -> https://github.com/evil/nokogiri@abc123 manifest=Gemfile.lock:5'

_dep dep-gem-paren "the parenthesised gem(...) call is read (R3)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem("rack", "3.0.0")\n' \
'STATE=ok
DEP_ADDED=rack@3.0.0 manifest=Gemfile:2'

_dep dep-gem-unreadable "a gem line whose name is not a literal makes the file unreadable (R4)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem name_from_elsewhere\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=gem name on line 2 is not a string literal at head'

_dep dep-gem-paren-open "a gem( call that does not close on its line makes the file unreadable (R4)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem("rack",\n    "3.0.0")\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the gem call on line 2 does not close on its line at head'

# --- Python names, PEP 503 (R5-R7) --------------------------------------------
_dep dep-uv-source-normalised "tool.uv.sources my_pkg redirects the dependency my-pkg (R5)" pyproject.toml \
$'[project]\ndependencies = ["my-pkg"]\n' \
$'[project]\ndependencies = ["my-pkg"]\n[tool.uv.sources]\nmy_pkg = { git = "https://git.example/my-pkg" }\n' \
'STATE=ok
DEP_REPLACED=my-pkg -> https://git.example/my-pkg@(unpinned) manifest=pyproject.toml'

_dep dep-near-name-normalised "django_rest_framewrk is one edit from django-rest-framework as PyPI compares names (R6)" requirements.txt \
$'django-rest-framework==3.14\n' \
$'django-rest-framework==3.14\ndjango_rest_framewrk==3.14\n' \
'STATE=ok
DEP_ADDED=django_rest_framewrk@3.14 manifest=requirements.txt:2
DEP_NEAR_NAME=django_rest_framewrk ~ django-rest-framework distance=1'

_dep dep-same-project "my_pkg is the project my-pkg, not a near-name of it (R6)" requirements.txt \
$'my-pkg==1.0\n' \
$'my-pkg==1.0\nmy_pkg==1.0\n' \
'STATE=ok
DEP_ADDED=my_pkg@1.0 manifest=requirements.txt:2'

_dep dep-npm-not-normalised "in npm my_pkg and my-pkg are two packages, and the near-name is reported (R7)" package.json \
'{"dependencies":{"my-pkg":"1.0.0"}}' \
'{"dependencies":{"my-pkg":"1.0.0","my_pkg":"1.0.0"}}' \
'STATE=ok
DEP_ADDED=my_pkg@1.0.0 manifest=package.json
DEP_NEAR_NAME=my_pkg ~ my-pkg distance=1'

# --- direct references (R8) --------------------------------------------------
_dep dep-direct-ref-scheme "any URL scheme is a direct reference, and an environment marker is not part of the target (R8)" requirements.txt \
$'flask==2.0\n' \
$'flask==2.0\npkg @ sftp://ex.com/p.whl\nq @ https://ex.com/a.whl ; python_version<"3.9"\n' \
'STATE=ok
DEP_ADDED=pkg@(unpinned) manifest=requirements.txt:2
DEP_ADDED=q@(unpinned) manifest=requirements.txt:3
DEP_REPLACED=pkg -> sftp://ex.com/p.whl@(unpinned) manifest=requirements.txt:2
DEP_REPLACED=q -> https://ex.com/a.whl@(unpinned) manifest=requirements.txt:3'

# --- npm (R9) ----------------------------------------------------------------
_dep dep-npm-git "package.json specs that fetch from git, a GitHub shorthand or a path are redirects (R9)" package.json \
'{"dependencies":{"express":"4.18.0"}}' \
'{"dependencies":{"express":"4.18.0","left":"git+https://git.example/left.git","right":"evil/right#main","local":"file:../local"}}' \
'STATE=ok
DEP_ADDED=left@git+https://git.example/left.git manifest=package.json
DEP_ADDED=local@file:../local manifest=package.json
DEP_ADDED=right@evil/right#main manifest=package.json
DEP_REPLACED=left -> git+https://git.example/left.git@(unpinned) manifest=package.json
DEP_REPLACED=local -> file:../local@(unpinned) manifest=package.json
DEP_REPLACED=right -> evil/right#main@(unpinned) manifest=package.json'
