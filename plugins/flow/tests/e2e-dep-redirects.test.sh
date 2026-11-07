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
#   R18 a requirements.txt line that is only a URL (git+https://...#egg=x, a
#      wheel URL) or a local path, or an -e editable install, is skipped, so
#      the package it installs from outside the index is neither added nor
#      a redirect and the run says STATE=ok; or one that names no package is
#      skipped instead of making the file unreadable; or `-e .`, the project
#      itself, is refused as a URL with no name
#   R19 a second gem call after a ; on a gem line is dropped, and its git:
#      option is read as the first gem's
#   R20 a gem source option keyed by a string ("git" => url, "git": url) is
#      read as the version "git", so the gem reads as from the registry
#   R21 a source option passed through a **splat or a hash variable, or a
#      custom git_source option (mine: "r"), reads as a gem from the registry
#   R22 a git/github/path block whose opening call runs over several lines
#      (a trailing comma, a label, an open parenthesis) is read from its first
#      line only: the do on a later line opens an anonymous block, and every
#      gem inside reads as from the registry with STATE=ok; or a continued
#      opener that runs into another statement or past the end of the file is
#      read as if it were whole
#   R23 gist:, one of Bundler's built-in git sources beside github:, is read
#      as an ordinary option, so the gem reads as from the registry
#   R24 a git/path block written with braces (`path("x") {` ... `}`) is not
#      tracked, so its gems read as from the registry; or the } of a hash
#      literal inside it closes it; or an end that closes a { block, or a }
#      that closes a do block inside a { block, is read instead of making the
#      file unreadable
#   R25 a package.json spec npm installs from outside the registry is missed:
#      a relative, home or absolute path without file: (../a/b, ~/x, /abs,
#      C:/x, ./c.tgz) or an scp-style git spec (git@host:path); or a semver
#      range (~1.2.3, ^2.0.0) or a dist-tag is taken for one
#   R26 a version bump of a Gemfile path: or git: gem (option or block),
#      whose source stays the same, is reported as a new redirect; or a git
#      gem whose branch or tag moves is not
#   R27 a quoted editable target (-e ".[dev]", --editable "git+...#egg=x"),
#      which pip reads with shell quoting, keeps its quotes, so the project
#      itself makes the file unreadable and a quoted VCS target is misnamed;
#      or an unclosed quote is skipped instead of making the file unreadable
#   R28 a } or { inside a character literal, a regex, a %-literal, a heredoc
#      or a string interpolation, inside a git/path block written with
#      braces, is counted as a brace: a } closes the block early, a later {
#      in such a literal keeps the count balanced, and the gems between read
#      as from the registry with STATE=ok; the same on a gem line in the
#      block, whose %-literal runs over a line holding a }
#   R29 a package.json tarball file name in upper or mixed case (x.TGZ,
#      X.TAR.GZ, x.Tar), which npm-package-arg reads as a file, is not a
#      redirect
#   R30 a Gemfile Bundler reads, and this parser read before brace blocks
#      were tracked, becomes unreadable: a git block whose options are a
#      hash literal (`git "u", { branch: "x" } do`), or a lone { or } in a
#      regex or character literal inside a do block or at the top level
#   R31 an -e line continued with a trailing backslash, which pip joins with
#      the next line before splitting it, is refused as an unclosed quote
#      instead of read

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

_dep dep-gem-path "path: in the hash-rocket syntax, with no version: a path names no revision (R1, R26)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem "local", "0.1.0", :path => "../local"\n' \
'STATE=ok
DEP_ADDED=local@0.1.0 manifest=Gemfile:2
DEP_REPLACED=local -> ../local@(unpinned) manifest=Gemfile:2'

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

_dep dep-gem-multiline-backslash "a gem call continued with a backslash keeps its github: source; its version constraint is not a ref (R10, R26)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem "rack", "3.0.0", \\\n  github: "evil/rack" # a fork\n' \
'STATE=ok
DEP_ADDED=rack@3.0.0 manifest=Gemfile:2
DEP_REPLACED=rack -> github:evil/rack@(unpinned) manifest=Gemfile:2'

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

# --- requirements.txt URL, path and editable lines (R18) ----------------------
_dep dep-req-url-lines "a VCS URL with #egg= and a wheel URL are added and are redirects (R18)" requirements.txt \
$'flask==2.0\n' \
$'flask==2.0\ngit+https://evil.example/requests2.git#egg=requests2\nhttps://files.example/pkgs/Fastjson-1.0-py3-none-any.whl ; python_version>"3.8"\n' \
'STATE=ok
DEP_ADDED=fastjson@(unpinned) manifest=requirements.txt:3
DEP_ADDED=requests2@(unpinned) manifest=requirements.txt:2
DEP_REPLACED=fastjson -> https://files.example/pkgs/Fastjson-1.0-py3-none-any.whl@(unpinned) manifest=requirements.txt:3
DEP_REPLACED=requests2 -> git+https://evil.example/requests2.git#egg=requests2@(unpinned) manifest=requirements.txt:2'

_dep dep-req-editable "editable installs and a local wheel are redirects; -e . is the project itself (R18)" requirements.txt \
$'flask==2.0\n-e .\n' \
$'flask==2.0\n-e .\n-e ../localpkg#egg=localpkg\n--editable=git+https://evil.example/x.git#egg=xpkg\n./wheels/zz-2.0-py3-none-any.whl\n-r other.txt\n' \
'STATE=ok
DEP_ADDED=localpkg@(unpinned) manifest=requirements.txt:3
DEP_ADDED=xpkg@(unpinned) manifest=requirements.txt:4
DEP_ADDED=zz@(unpinned) manifest=requirements.txt:5
DEP_REPLACED=localpkg -> ../localpkg#egg=localpkg@(unpinned) manifest=requirements.txt:3
DEP_REPLACED=xpkg -> git+https://evil.example/x.git#egg=xpkg@(unpinned) manifest=requirements.txt:4
DEP_REPLACED=zz -> ./wheels/zz-2.0-py3-none-any.whl@(unpinned) manifest=requirements.txt:5'

_dep dep-req-editable-no-name "an editable path that names no package makes the file unreadable (R18)" requirements.txt \
$'flask==2.0\n' \
$'flask==2.0\n-e ../localpkg\n' \
'STATE=unavailable
MANIFEST_UNPARSED=requirements.txt reason=the requirement on line 2 is a URL or path that names no package (no egg fragment and no wheel file name) at head'

_dep dep-req-url-no-name "a URL to an sdist names no package and makes the file unreadable (R18)" requirements.txt \
$'flask==2.0\n' \
$'flask==2.0\nhttps://files.example/pkgs/fast-json-1.0.tar.gz\n' \
'STATE=unavailable
MANIFEST_UNPARSED=requirements.txt reason=the requirement on line 2 is a URL or path that names no package (no egg fragment and no wheel file name) at head'

# --- Gemfile forms that read as a gem from the registry (R19-R21) ------------
_dep dep-gem-semicolon "a second gem call after a ; on a gem line makes the file unreadable (R19)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"; gem "evil", git: "https://evil.example/evil.git"\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the gem call on line 1 is followed by another statement after a ; at head'

_dep dep-gem-semicolon-trailing "a ; that ends a gem line, or sits in a string, is not a second statement (R19)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0";\ngem "rack", git: "https://evil.example/r;ack"\n' \
'STATE=ok
DEP_ADDED=rack@(unpinned) manifest=Gemfile:2
DEP_REPLACED=rack -> https://evil.example/r;ack@(unpinned) manifest=Gemfile:2'

_dep dep-gem-string-key "a source option keyed by a string is a redirect, not a version (R20)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem "rack", "git" => "https://evil.example/rack"\ngem "rake", "13.0", "github": "evil/rake", \'branch\' => "main"\n' \
'STATE=ok
DEP_ADDED=rack@(unpinned) manifest=Gemfile:2
DEP_ADDED=rake@13.0 manifest=Gemfile:3
DEP_REPLACED=rack -> https://evil.example/rack@(unpinned) manifest=Gemfile:2
DEP_REPLACED=rake -> github:evil/rake@main manifest=Gemfile:3'

_dep dep-gem-double-splat "options passed through a **splat make the file unreadable (R21)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\nopts = { git: "https://evil.example/rack" }\ngem "rack", **opts\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the gem call on line 3 passes arguments through a splat at head'

_dep dep-gem-hash-variable "a gem argument that is a variable makes the file unreadable (R21)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem "rack", RACK_OPTS\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the gem call on line 2 passes an argument that is not a string literal or an option at head'

_dep dep-gem-git-source "a custom git_source option is a redirect (R21)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngit_source(:mine) { |repo| "https://evil.example/#{repo}.git" }\ngem "rack", mine: "rack", tag: "v1"\n' \
'STATE=ok
DEP_ADDED=rack@(unpinned) manifest=Gemfile:3
DEP_REPLACED=rack -> mine:rack@v1 manifest=Gemfile:3'

_dep dep-gem-git-source-unnamed "a git_source whose name is not a literal makes the file unreadable (R21)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngit_source(SOURCE_NAME) { |repo| "https://evil.example/#{repo}.git" }\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the git_source on line 2 does not name a literal symbol or string at head'

# --- Gemfile blocks and sources Bundler reads that the parser missed (R22-R24, R26)
_dep dep-gem-block-continued "a git, github or git( block whose opening call runs over several lines keeps its gems redirected (R22)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngit "https://example.invalid/fork/rails.git",\n    branch: "main" do\n  gem "activesupport"\nend\ngithub "evil/rails",\n  branch: "edge" do\n  gem "railties"\nend\ngit(\n  "https://evil.example/r.git",\n  tag: "v1"\n) do\n  gem "actionpack"\nend\ngem "rspec", "3.12.0"\n' \
'STATE=ok
DEP_ADDED=actionpack@(unpinned) manifest=Gemfile:14
DEP_ADDED=activesupport@(unpinned) manifest=Gemfile:4
DEP_ADDED=railties@(unpinned) manifest=Gemfile:8
DEP_ADDED=rspec@3.12.0 manifest=Gemfile:16
DEP_REPLACED=actionpack -> https://evil.example/r.git@v1 manifest=Gemfile:14
DEP_REPLACED=activesupport -> https://example.invalid/fork/rails.git@main manifest=Gemfile:4
DEP_REPLACED=railties -> github:evil/rails@edge manifest=Gemfile:8'

_dep dep-gem-block-continued-into-gem "a continued git block opener that runs into a gem line makes the file unreadable (R22)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngit "https://evil.example/r.git",\ngem "activesupport"\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the git block on line 2 continues into line 3, which is not part of it at head'

_dep dep-gem-block-continued-eof "a continued path block opener that runs past the end of the file makes it unreadable (R22)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\npath "vendor/engines",\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the path block on line 2 continues past the end of the file at head'

_dep dep-gem-gist "gist:, a built-in Bundler git source, is a redirect in either hash syntax (R23)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngem "nokogiri", gist: "deadbeef"\ngem "rake", :gist => "cafe01", ref: "abc"\n' \
'STATE=ok
DEP_ADDED=nokogiri@(unpinned) manifest=Gemfile:2
DEP_ADDED=rake@(unpinned) manifest=Gemfile:3
DEP_REPLACED=nokogiri -> gist:deadbeef@(unpinned) manifest=Gemfile:2
DEP_REPLACED=rake -> gist:cafe01@abc manifest=Gemfile:3'

_dep dep-gem-brace-block "a path or git block written with braces redirects its gems; a hash literal inside it does not close it (R24)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\npath("vendor/engines") {\n  SETTINGS = {\n    a: 1,\n  }\n  gem "engine"\n}\ngit("https://evil.example/r.git", branch: "x") { |g|\n  gem "activesupport"\n}\ngem "rspec", "3.12.0"\n' \
'STATE=ok
DEP_ADDED=activesupport@(unpinned) manifest=Gemfile:9
DEP_ADDED=engine@(unpinned) manifest=Gemfile:6
DEP_ADDED=rspec@3.12.0 manifest=Gemfile:11
DEP_REPLACED=activesupport -> https://evil.example/r.git@x manifest=Gemfile:9
DEP_REPLACED=engine -> vendor/engines@(unpinned) manifest=Gemfile:6'

_dep dep-gem-brace-end "an end that closes a { block makes the file unreadable (R24)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngit("https://evil.example/r.git") {\n  gem "activesupport"\nend\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the end on line 4 closes the { on line 2 at head'

_dep dep-gem-brace-closes-do "a } that closes a do block inside a { block makes the file unreadable (R24)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\npath("vendor/x") {\n  git "https://evil.example/r.git" do\n    gem "activesupport"\n  }\n}\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=the } on line 5 closes the do on line 3 at head'

_dep dep-gem-redirect-version-bump "a path or git gem whose version moves is not a new redirect; a git gem whose tag moves is (R26)" Gemfile \
$'gem "engine", "~> 1.0", path: "engines/engine"\ngem "fork", "~> 2.0", git: "https://evil.example/fork.git", tag: "v2"\ngem "pinned", git: "https://evil.example/pinned.git", tag: "v1"\npath "vendor" do\n  gem "inner", "1.0"\nend\n' \
$'gem "engine", "~> 1.1", path: "engines/engine"\ngem "fork", "~> 2.1", git: "https://evil.example/fork.git", tag: "v2"\ngem "pinned", git: "https://evil.example/pinned.git", tag: "v2"\npath "vendor" do\n  gem "inner", "1.1"\nend\n' \
'STATE=ok
DEP_CHANGED=engine "~> 1.0"->"~> 1.1" manifest=Gemfile:1
DEP_CHANGED=fork "~> 2.0"->"~> 2.1" manifest=Gemfile:2
DEP_CHANGED=inner 1.0->1.1 manifest=Gemfile:5
DEP_REPLACED=pinned -> https://evil.example/pinned.git@v2 manifest=Gemfile:3'

# --- package.json paths and scp-style git (R25) -------------------------------
_dep dep-npm-paths "package.json paths without file: and scp-style git specs are redirects; ranges and tags are not (R25)" package.json \
'{"dependencies":{"express":"4.18.0"}}' \
'{"dependencies":{"express":"4.18.0","rel-path":"../foo/bar","home-path":"~/x/y","abs-path":"/abs/p","tarball":"./vendor/c.tgz","drive-path":"C:/x/y","scp-host":"git@host.example:team/r.git","tilde-range":"~1.2.3","caret-range":"^2.0.0","dist-tag":"latest"}}' \
'STATE=ok
DEP_ADDED=abs-path@/abs/p manifest=package.json
DEP_ADDED=caret-range@^2.0.0 manifest=package.json
DEP_ADDED=dist-tag@latest manifest=package.json
DEP_ADDED=drive-path@C:/x/y manifest=package.json
DEP_ADDED=home-path@~/x/y manifest=package.json
DEP_ADDED=rel-path@../foo/bar manifest=package.json
DEP_ADDED=scp-host@git@host.example:team/r.git manifest=package.json
DEP_ADDED=tarball@./vendor/c.tgz manifest=package.json
DEP_ADDED=tilde-range@~1.2.3 manifest=package.json
DEP_REPLACED=abs-path -> /abs/p@(unpinned) manifest=package.json
DEP_REPLACED=drive-path -> C:/x/y@(unpinned) manifest=package.json
DEP_REPLACED=home-path -> ~/x/y@(unpinned) manifest=package.json
DEP_REPLACED=rel-path -> ../foo/bar@(unpinned) manifest=package.json
DEP_REPLACED=scp-host -> git@host.example:team/r.git@(unpinned) manifest=package.json
DEP_REPLACED=tarball -> ./vendor/c.tgz@(unpinned) manifest=package.json'

# --- quoted editable targets (R27) ---------------------------------------------
_dep dep-req-editable-quoted "a quoted -e target is read as pip reads it: -e \".[dev]\" is the project, a quoted VCS target is a redirect (R27)" requirements.txt \
$'flask==2.0\n' \
$'flask==2.0\n-e ".[dev]"\n--editable \'git+https://evil.example/x.git#egg=xpkg\'\n' \
'STATE=ok
DEP_ADDED=xpkg@(unpinned) manifest=requirements.txt:3
DEP_REPLACED=xpkg -> git+https://evil.example/x.git#egg=xpkg@(unpinned) manifest=requirements.txt:3'

_dep dep-req-editable-unclosed-quote "an -e line with an unclosed quote makes the file unreadable (R27)" requirements.txt \
$'flask==2.0\n' \
$'flask==2.0\n-e "../x#egg=x\n' \
'STATE=unavailable
MANIFEST_UNPARSED=requirements.txt reason=the option on line 2 has an unclosed quote at head'

# --- braces inside literals in a brace-form block (R28) ------------------------
_dep dep-gem-brace-char-literal "a } and a { in character literals inside a path { block make the file unreadable, not a lost redirect (R28)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\npath("vendor/x") {\n  x = ?}\n  gem "activesupport"\n  y = ?{\n}\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=line 3, inside the { block on line 2, holds a regex, %-literal, character literal, heredoc, interpolation or unclosed string, whose braces this cannot count at head'

_dep dep-gem-brace-regex "a } and a { in regexes inside a path { block make the file unreadable (R28)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\npath("vendor/x") {\n  x = /}/\n  gem "activesupport"\n  y = /{/\n}\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=line 3, inside the { block on line 2, holds a regex, %-literal, character literal, heredoc, interpolation or unclosed string, whose braces this cannot count at head'

_dep dep-gem-brace-percent "a } and a { in %-literals inside a git { block make the file unreadable (R28)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\ngit("https://evil.example/r.git") {\n  x = %q(})\n  gem "activesupport"\n  y = %q({)\n}\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=line 3, inside the { block on line 2, holds a regex, %-literal, character literal, heredoc, interpolation or unclosed string, whose braces this cannot count at head'

_dep dep-gem-brace-heredoc "a heredoc whose body holds a } inside a path { block makes the file unreadable (R28)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\npath("vendor/x") {\n  x = <<~E\n}\nE\n  gem "activesupport"\n  y = <<~E\n{\nE\n}\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=line 3, inside the { block on line 2, holds a regex, %-literal, character literal, heredoc, interpolation or unclosed string, whose braces this cannot count at head'

_dep dep-gem-brace-interpolation "a } and a { in string interpolations inside a path { block make the file unreadable (R28)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\npath("vendor/x") {\n  x = "#{"}"}"\n  gem "activesupport"\n  y = "#{"{"}"\n}\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=line 3, inside the { block on line 2, holds a regex, %-literal, character literal, heredoc, interpolation or unclosed string, whose braces this cannot count at head'

_dep dep-gem-brace-gem-literal "a gem line inside a path { block whose %-literal runs over a } makes the file unreadable (R28)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\npath("vendor/x") {\n  gem "a", require: %q<\n}\n>\n  gem "activesupport"\n  gem "b", require: %q<\n{\n>\n}\n' \
'STATE=unavailable
MANIFEST_UNPARSED=Gemfile reason=line 3, inside the { block on line 2, holds a regex, %-literal, character literal, heredoc, interpolation or unclosed string, whose braces this cannot count at head'

# --- npm tarball names in any case (R29) ---------------------------------------
_dep dep-npm-tarball-case "a tarball file name is a redirect in upper or mixed case, as npm-package-arg reads it (R29)" package.json \
'{"dependencies":{"express":"4.18.0"}}' \
'{"dependencies":{"express":"4.18.0","evil":"evil-1.0.0.TGZ","big":"X.TAR.GZ","mixed":"foo.Tar"}}' \
'STATE=ok
DEP_ADDED=big@X.TAR.GZ manifest=package.json
DEP_ADDED=evil@evil-1.0.0.TGZ manifest=package.json
DEP_ADDED=mixed@foo.Tar manifest=package.json
DEP_REPLACED=big -> X.TAR.GZ@(unpinned) manifest=package.json
DEP_REPLACED=evil -> evil-1.0.0.TGZ@(unpinned) manifest=package.json
DEP_REPLACED=mixed -> foo.Tar@(unpinned) manifest=package.json'

# --- Gemfiles Bundler reads that stay readable (R30) ---------------------------
_dep dep-gem-do-block-literals "a git block with a hash of options, and lone braces in literals around do blocks, are read (R30)" Gemfile \
$'gem "rails", "7.0.0"\n' \
$'gem "rails", "7.0.0"\nx = ?}\ngit "https://evil.example/r.git", { branch: "x" } do\n  gem "activesupport"\n  y = /\\{/\n  gem "actionpack"\nend\ngroup :test do\n  z = ?{\n  gem "rspec", "3.12.0"\nend\n' \
'STATE=ok
DEP_ADDED=actionpack@(unpinned) manifest=Gemfile:6
DEP_ADDED=activesupport@(unpinned) manifest=Gemfile:4
DEP_ADDED=rspec@3.12.0 manifest=Gemfile:10
DEP_REPLACED=actionpack -> https://evil.example/r.git@x manifest=Gemfile:6
DEP_REPLACED=activesupport -> https://evil.example/r.git@x manifest=Gemfile:4'

# --- a continued editable line (R31) -------------------------------------------
_dep dep-req-editable-continued "an -e line continued with a backslash is joined with the next line, as pip joins it (R31)" requirements.txt \
$'flask==2.0\n' \
$'flask==2.0\n-e git+https://evil.example/x.git#egg=b \\\n    --config-settings editable_mode=compat\n-e ../y#egg=y \\\n' \
'STATE=ok
DEP_ADDED=b@(unpinned) manifest=requirements.txt:2
DEP_ADDED=y@(unpinned) manifest=requirements.txt:4
DEP_REPLACED=b -> git+https://evil.example/x.git#egg=b@(unpinned) manifest=requirements.txt:2
DEP_REPLACED=y -> ../y#egg=y@(unpinned) manifest=requirements.txt:4'
