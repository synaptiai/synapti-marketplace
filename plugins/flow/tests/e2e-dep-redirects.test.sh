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
#   R10 a gem call without parentheses whose options continue on the next
#      lines (a trailing comma or backslash) is read from its first line only,
#      so its git:/github: source is dropped; or a continuation that never
#      ends, or runs into another statement, is read as if it were whole
#   R11 the end of an if/unless/case (or another keyword block) inside a git
#      block closes the git block, so the gems after it read as from the
#      registry; or a modifier `gem "x" if c` opens a block that swallows the
#      git block's end; or an end that closes nothing is skipped silently
#   R12 the project's own gem in Gemfile.lock (PATH remote: ., what a gemspec
#      line resolves to) is reported as a redirect, and a version bump of any
#      PATH gem reads as a new redirect
#   R13 a statement continued with a backslash onto a line holding a modifier
#      if/unless is misread: a gem call so continued makes the file
#      unreadable, and any other statement so continued opens a block that
#      swallows the git block's end
#   R14 a =begin ... =end block comment is read as code: =begin opens a block
#      and the gems written in the comment are reported
#   R15 a # inside a string is read as a comment, so the rest of the line
#      (the end of a one-line def) is not seen; or, once strings are kept, an
#      interpolated gem name or source is read as if it were a literal
#   R16 a setter or operator method (def mode=(v), def []=(k, v)) is read as
#      an endless def and opens nothing, so its end closes the git block
#   R17 only #{...} is taken for interpolation, so a double-quoted gem name,
#      source option or git/path block target interpolating #@ivar, #@@cvar
#      or #$gvar is reported as a literal target; or a single-quoted string,
#      which Ruby does not interpolate, is refused as if it did; or a # inside
#      a backtick command is read as a comment, cutting off its git block's do

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

# --- Ruby (R1-R4, R10-R12) ------------------------------------------------------------
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

_dep dep-gem-multiline-comma "a gem call continued with trailing commas keeps its git: source and branch (R10)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem "devise",\n  git: "https://github.com/attacker/devise",\n  branch: "main"\ngem "rspec", "3.12.0"\n' \
'STATE=ok
DEP_ADDED=devise@(unpinned) manifest=Gemfile:2
DEP_ADDED=rspec@3.12.0 manifest=Gemfile:5
DEP_REPLACED=devise -> https://github.com/attacker/devise@main manifest=Gemfile:2'

_dep dep-gem-multiline-backslash "a gem call continued with a backslash keeps its github: source (R10)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem "rack", "3.0.0", \\\n  github: "evil/rack" # a fork\n' \
'STATE=ok
DEP_ADDED=rack@3.0.0 manifest=Gemfile:2
DEP_REPLACED=rack -> github:evil/rack@3.0.0 manifest=Gemfile:2'

_dep dep-gem-multiline-eof "a gem call whose continuation runs past the end of the file makes it unreadable (R10)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem "devise",\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the gem call on line 2 continues past the end of the file at head'

_dep dep-gem-multiline-into-gem "a gem call whose continuation runs into another gem line makes it unreadable (R10)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem "devise",\ngem "rack", git: "https://github.com/evil/rack"\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the gem call on line 2 continues into line 3, which is not part of it at head'

_dep dep-gem-keyword-block "if, unless and case inside a git block do not close it; a modifier if opens nothing (R11)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngit "https://github.com/evil/rails.git" do\n  if ENV["EDGE"]\n    gem "actionpack"\n  end\n  gem "railties" if ENV["CI"]\n  unless ENV["SLIM"]\n    gem "actionview"\n  end\n  case RUBY_VERSION\n  when /^3/\n    gem "actioncable"\n  end\n  gem "activesupport"\nend\ngem "rspec", "3.12.0"\n' \
'STATE=ok
DEP_ADDED=actioncable@(unpinned) manifest=Gemfile:12
DEP_ADDED=actionpack@(unpinned) manifest=Gemfile:4
DEP_ADDED=actionview@(unpinned) manifest=Gemfile:8
DEP_ADDED=activesupport@(unpinned) manifest=Gemfile:14
DEP_ADDED=railties@(unpinned) manifest=Gemfile:6
DEP_ADDED=rspec@3.12.0 manifest=Gemfile:16
DEP_REPLACED=actioncable -> https://github.com/evil/rails.git@(unpinned) manifest=Gemfile:12
DEP_REPLACED=actionpack -> https://github.com/evil/rails.git@(unpinned) manifest=Gemfile:4
DEP_REPLACED=actionview -> https://github.com/evil/rails.git@(unpinned) manifest=Gemfile:8
DEP_REPLACED=activesupport -> https://github.com/evil/rails.git@(unpinned) manifest=Gemfile:14
DEP_REPLACED=railties -> https://github.com/evil/rails.git@(unpinned) manifest=Gemfile:6'

_dep dep-gem-keyword-block-forms "while ... do opens one block, an assigned if opens one, a one-line def opens none (R11)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngit "https://github.com/evil/rails.git" do\n  def self.edge?; false; end\n  while false do\n  end\n  pin = if ENV["PIN"]\n    "1"\n  end\n  gem "activesupport"\nend\ngem "rspec", "3.12.0"\n' \
'STATE=ok
DEP_ADDED=activesupport@(unpinned) manifest=Gemfile:9
DEP_ADDED=rspec@3.12.0 manifest=Gemfile:11
DEP_REPLACED=activesupport -> https://github.com/evil/rails.git@(unpinned) manifest=Gemfile:9'

_dep dep-gem-stray-end "an end that closes no block makes the file unreadable (R11)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\nENV["X"] && begin_edge\ngem "rack", "3.0.0"\nend\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the end on line 4 closes no block this can see at head'

_dep dep-gemfile-lock-own-gemspec "the project's own gem (PATH remote: .) is not a redirect when its version moves (R12)" Gemfile.lock \
$'PATH\n  remote: .\n  specs:\n    mygem (0.1.0)\n\nGEM\n  remote: https://rubygems.org/\n  specs:\n    rails (7.0.0)\n' \
$'PATH\n  remote: .\n  specs:\n    mygem (0.2.0)\n\nGEM\n  remote: https://rubygems.org/\n  specs:\n    rails (7.0.0)\n' \
'STATE=ok
DEP_CHANGED=mygem 0.1.0->0.2.0 manifest=Gemfile.lock:4'

_dep dep-gemfile-lock-path-bump "a PATH gem elsewhere is a redirect when it arrives, not again when its version moves (R12)" Gemfile.lock \
$'PATH\n  remote: ./\n  specs:\n    mygem (0.1.0)\n\nPATH\n  remote: ../shared\n  specs:\n    shared (1.0.0)\n' \
$'PATH\n  remote: ./\n  specs:\n    mygem (0.1.0)\n\nPATH\n  remote: ../shared\n  specs:\n    shared (1.1.0)\n\nPATH\n  remote: ../vendored\n  specs:\n    vendored (2.0.0)\n' \
'STATE=ok
DEP_ADDED=vendored@2.0.0 manifest=Gemfile.lock:14
DEP_CHANGED=shared 1.0.0->1.1.0 manifest=Gemfile.lock:9
DEP_REPLACED=vendored -> ../vendored@(unpinned) manifest=Gemfile.lock:14'

_dep dep-gem-backslash-modifier "a gem call continued with a backslash onto a modifier if or unless is read; one inside a git block keeps its end (R13)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem "rb-fsevent", require: false \\\n  if RUBY_PLATFORM =~ /darwin/\ngit "https://github.com/evil/rails.git" do\n  gem "listen" \\\n    unless ENV["CI"]\n  gem "activesupport"\nend\ngem "rspec", "3.12.0"\n' \
'STATE=ok
DEP_ADDED=activesupport@(unpinned) manifest=Gemfile:7
DEP_ADDED=listen@(unpinned) manifest=Gemfile:5
DEP_ADDED=rb-fsevent@(unpinned) manifest=Gemfile:2
DEP_ADDED=rspec@3.12.0 manifest=Gemfile:9
DEP_REPLACED=activesupport -> https://github.com/evil/rails.git@(unpinned) manifest=Gemfile:7
DEP_REPLACED=listen -> https://github.com/evil/rails.git@(unpinned) manifest=Gemfile:5'

_dep dep-gem-backslash-comma-if "a gem call whose comma and backslash continue into an if makes the file unreadable (R13)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem "devise", \\\n  if ENV["EDGE"]\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the gem call on line 2 continues into line 3, which is not part of it at head'

_dep dep-statement-backslash-modifier "a statement continued with a backslash onto a modifier if opens no block inside a git block (R13)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngit "https://github.com/evil/rails.git" do\n  eval_gemfile "Gemfile.local" \\\n    if File.exist?("Gemfile.local")\n  gem "activesupport"\nend\ngem "rspec", "3.12.0"\n' \
'STATE=ok
DEP_ADDED=activesupport@(unpinned) manifest=Gemfile:5
DEP_ADDED=rspec@3.12.0 manifest=Gemfile:7
DEP_REPLACED=activesupport -> https://github.com/evil/rails.git@(unpinned) manifest=Gemfile:5'

_dep dep-gem-block-comment "a =begin ... =end block comment opens no block and its gems are not read (R14)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngit "https://github.com/evil/rails.git" do\n=begin\n  if ENV["EDGE"]\n  gem "actionpack"\n=end\n  gem "activesupport"\nend\ngem "rspec", "3.12.0"\n' \
'STATE=ok
DEP_ADDED=activesupport@(unpinned) manifest=Gemfile:7
DEP_ADDED=rspec@3.12.0 manifest=Gemfile:9
DEP_REPLACED=activesupport -> https://github.com/evil/rails.git@(unpinned) manifest=Gemfile:7'

_dep dep-gem-block-comment-open "a =begin with no =end makes the file unreadable (R14)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\n=begin\ngem "rack", "3.0.0"\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the =begin on line 2 has no =end at head'

_dep dep-gem-string-hash "a # inside a string is not a comment, so a one-line def ends on its line (R15)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngit "https://github.com/evil/rails.git" do\n  def self.gh(r) "https://github.com/#{r}" end\n  gem "activesupport" # the fork\nend\ngem "rspec", "3.12.0"\n' \
'STATE=ok
DEP_ADDED=activesupport@(unpinned) manifest=Gemfile:4
DEP_ADDED=rspec@3.12.0 manifest=Gemfile:6
DEP_REPLACED=activesupport -> https://github.com/evil/rails.git@(unpinned) manifest=Gemfile:4'

_dep dep-gem-interpolated-name "an interpolated gem name is not a literal and makes the file unreadable (R15)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem "rails-#{ENV["FLAVOUR"]}"\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=gem name on line 2 is not a string literal at head'

_dep dep-gem-interpolated-source "an interpolated git: source is not a literal and makes the file unreadable (R15)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem "rack", git: "https://github.com/#{ORG}/rack"\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the git: of gem rack on line 2 is not a string literal at head'

_dep dep-gem-ivar-source "a git: source interpolating an instance variable is not a literal (R17)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem "rack", git: "https://github.com/#@org/rack"\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the git: of gem rack on line 2 is not a string literal at head'

_dep dep-gem-cvar-path "a :path => source interpolating a class variable is not a literal (R17)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem "local", :path => "#@@root/local"\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the path: of gem local on line 2 is not a string literal at head'

_dep dep-gem-gvar-block "a git block target interpolating a global variable is not a literal (R17)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngit "https://github.com/#$FORK/rails.git" do\n  gem "activesupport"\nend\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the git block on line 2 does not name a string literal at head'

_dep dep-gem-ivar-name "a gem name interpolating an instance variable is not a literal (R17)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem "#@name"\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=gem name on line 2 is not a string literal at head'

_dep dep-gem-single-quoted-hash "a single-quoted source is not interpolated, so it is a literal reported as written (R17)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem "rack", git: \'https://github.com/#@org/rack\'\ngem "rake", github: \'evil/#{rake}\'\npath \'../#$vendor\' do\n  gem "local"\nend\n' \
'STATE=ok
DEP_ADDED=local@(unpinned) manifest=Gemfile:5
DEP_ADDED=rack@(unpinned) manifest=Gemfile:2
DEP_ADDED=rake@(unpinned) manifest=Gemfile:3
DEP_REPLACED=local -> ../#$vendor@(unpinned) manifest=Gemfile:5
DEP_REPLACED=rack -> https://github.com/#@org/rack@(unpinned) manifest=Gemfile:2
DEP_REPLACED=rake -> github:evil/#{rake}@(unpinned) manifest=Gemfile:3'

_dep dep-gem-backtick-block "a backtick command is a string whose # is not a comment, and not a literal (R17)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngit `echo https://github.com/#{ENV["FORK"]}/rails.git` do\n  gem "activesupport"\nend\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the git block on line 2 does not name a string literal at head'

_dep dep-gem-setter-def "a setter or operator def opens a block; only an endless def does not (R16)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngit "https://github.com/evil/rails.git" do\n  def mode=(v)\n    @mode = v\n  end\n  def ==(o)\n    true\n  end\n  def []=(k, v)\n    nil\n  end\n  def label = "edge"\n  def pin(v) = v\n  gem "activesupport"\nend\ngem "rspec", "3.12.0"\n' \
'STATE=ok
DEP_ADDED=activesupport@(unpinned) manifest=Gemfile:14
DEP_ADDED=rspec@3.12.0 manifest=Gemfile:16
DEP_REPLACED=activesupport -> https://github.com/evil/rails.git@(unpinned) manifest=Gemfile:14'

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

# --- a gem call that does not start its statement (R4) ------------------------
_dep dep-gem-in-block-expr "a gem call inside an each block on one line is read as unreadable, not as no dependency (R4)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\n%w(rack puma).each { |g| gem g }\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the gem call on line 2 is not at the start of its statement at head'

_dep dep-gem-one-line-group "a one-line group block holding a gem call is unreadable, not skipped (R4)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngroup :test do gem "rspec" end\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the gem call on line 2 is not at the start of its statement at head'

_dep dep-gem-word-in-string "the word gem inside a string or in gemspec is not a gem call (R4)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngemspec\nputs "install the gem rack"\n' \
'STATE=ok'
