# Tests for the fourth review cycle on the dependency judgment — issue #217.
#
# Cycle 4 found seventeen defects, and three of its five P1s were in code the
# previous commit had added. The cause was narrower than the count suggests:
# that commit introduced two new helper functions and neither was mutation
# tested. A mutation proved it — replacing the TOML line lookup with
# `return None` changed no assertion in any of the four suites, so an entire
# function shipped with nothing pinning it.
#
# Two decisions came out of that:
#   - TOML entries carry no line number. The lookup pointed at the wrong
#     package for most entries in a lockfile, and a location that is
#     confidently wrong is worse than one that is merely coarse.
#     references/finding-schema.md permits a file-level location.
#   - Every branch added here has a fixture that fails without it.
#
# Prereq: git, python3, and a TOML parser. SKIPS gracefully if absent.

if ! command -v git >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  _flow_test_begin "git and python3 prerequisite"
  _flow_assert_pass "SKIP: git or python3 not installed"
  return 0
fi
if ! python3 -c "
try:
    import tomllib
except ImportError:
    import tomli
" >/dev/null 2>&1; then
  _flow_test_begin "TOML parser prerequisite"
  _flow_assert_pass "SKIP: neither tomllib nor tomli is importable"
  return 0
fi

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
DEP_DIFF="$PLUGIN_DIR/bin/flow-dep-diff.sh"

DF_CLEANUP=()
_df_cleanup() { local p; for p in "${DF_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _df_cleanup EXIT

_df_repo() {
  local d
  d=$(mktemp -d -t "flow-df.XXXXXX") || return 1
  DF_CLEANUP+=("$d")
  git -C "$d" init --quiet 2>/dev/null
  git -C "$d" config user.email "test@example.invalid"
  git -C "$d" config user.name "flow test"
  git -C "$d" config commit.gpgsign false
  printf '%s\n' "$d"
}
_df_case() {
  local R
  R=$(_df_repo)
  mkdir -p "$(dirname "$R/$1")"
  printf '%s' "$2" > "$R/$1"
  git -C "$R" add -A >/dev/null 2>&1
  git -C "$R" commit --quiet -m base >/dev/null 2>&1
  printf '%s' "$3" > "$R/$1"
  git -C "$R" add -A >/dev/null 2>&1
  git -C "$R" commit --quiet -m head >/dev/null 2>&1
  ( cd "$R" && "$DEP_DIFF" --base HEAD~1 --head HEAD 2>&1 )
}

# =============================================================================
# Locations: coarse where the line is a reconstruction, exact where it is a fact
# =============================================================================

_flow_test_begin "a TOML entry is cited at file level, never at a guessed line"
# The lookup this replaces scanned the whole file for the first quoted
# occurrence of the name, so memchr — declared on line 11 — was cited at line
# 7, inside aho-corasick's dependency array. On a 40-package lockfile it was
# wrong for 26 of them. Nothing asserted a TOML line, which is why it shipped.
OUT=$(_df_case "Cargo.lock" \
'version = 3

[[package]]
name = "aho-corasick"
version = "1.1.2"
dependencies = [
 "memchr",
]

[[package]]
name = "memchr"
version = "2.6.4"
' \
'version = 3

[[package]]
name = "aho-corasick"
version = "1.1.2"
dependencies = [
 "memchr",
]

[[package]]
name = "memchr"
version = "2.7.1"
')
assert_contains "DEP_CHANGED=memchr 2.6.4->2.7.1 manifest=Cargo.lock" "$OUT" \
  "the change is reported against the file"
assert_not_contains "manifest=Cargo.lock:7" "$OUT" \
  "never at another package's dependency-array line"
assert_not_contains "manifest=Cargo.lock:" "$OUT" \
  "and no line is invented for a TOML entry at all"

_flow_test_begin "a line-oriented manifest still carries its real line"
# The complement: where the parser reads line by line, the number is a fact
# and dropping it would lose real information.
OUT=$(_df_case "requirements.txt" \
'# a header
flask==2.0.0
' \
'# a header
flask==2.0.0
redis==5.0.1
')
assert_contains "DEP_ADDED=redis@5.0.1 manifest=requirements.txt:3" "$OUT" \
  "requirements.txt keeps its line"

_flow_test_begin "a go.mod entry keeps its real line too"
OUT=$(_df_case "go.mod" \
'module example.com/demo

require github.com/pkg/errors v0.9.0
' \
'module example.com/demo

require github.com/pkg/errors v0.9.0

require github.com/stretchr/testify v1.9.0
')
assert_contains "manifest=go.mod:5" "$OUT" "go.mod keeps its line"

# =============================================================================
# A dependency table that yielded nothing while reporting ok
# =============================================================================

_flow_test_begin "a poetry group using multiple constraints is not read as empty"
# The group-vs-name test asked whether every value was a LIST. Poetry's
# multiple-constraints form makes every value a list of tables, so the whole
# table was read as groups, the tables were dropped, and the run reported ok
# with no dependency at all — not even a baseline. A dev group has no python
# key by convention, so this is the normal shape there.
OUT=$(_df_case "pyproject.toml" \
'[tool.poetry.group.dev.dependencies]
pytest = [{version = "^7.0", python = "<3.8"},]
' \
'[tool.poetry.group.dev.dependencies]
pytest = [{version = "^7.0", python = "<3.8"},]
reqeusts = [{version = "^1.0", python = ">=3.8"},]
')
assert_contains "DEP_ADDED=reqeusts@^1.0" "$OUT" "the added package is reported"
assert_contains "DEP_BASELINE=pytest" "$OUT" "and the existing one reaches the baseline"

_flow_test_begin "a group of plain strings is still read as groups"
# The complement, so the fix cannot be "treat every table as name->version".
OUT=$(_df_case "pyproject.toml" \
'[dependency-groups]
dev = ["pytest>=8"]
' \
'[dependency-groups]
dev = ["pytest>=8", "reqeusts==0.1.0"]
')
assert_contains "DEP_ADDED=reqeusts@0.1.0" "$OUT" "a string group still yields its items"
assert_not_contains "DEP_ADDED=dev@" "$OUT" "and the group name is not a package"

# =============================================================================
# The build backend, which runs code at install time
# =============================================================================

_flow_test_begin "build-system.requires is judged"
# The key is `requires`, not `*dependencies`, so it never matched. A build
# backend executes its own code during install, which makes these the
# highest-consequence packages in the file.
OUT=$(_df_case "pyproject.toml" \
'[build-system]
requires = ["setuptools>=61"]

[project]
dependencies = ["flask"]
' \
'[build-system]
requires = ["setuptools>=61", "setuptoolz-evil==1.0"]

[project]
dependencies = ["flask"]
')
assert_contains "DEP_ADDED=setuptoolz-evil@1.0" "$OUT" "a build requirement is a dependency"
assert_contains "DEP_BASELINE=setuptools" "$OUT" "and the existing one is in the baseline"

# =============================================================================
# Redirects, in every ecosystem rather than one
# =============================================================================

_flow_test_begin "a Cargo patch redirect is reported"
# [patch.crates-io] redirects every crate in the tree, including transitive
# ones. It was completely silent.
OUT=$(_df_case "Cargo.toml" \
'[dependencies]
serde = "1.0"
' \
'[dependencies]
serde = "1.0"

[patch.crates-io]
serde = { git = "https://github.com/evil/serde" }
')
assert_contains "DEP_REPLACED=serde" "$OUT" "the patched crate is named"
assert_contains "github.com/evil/serde" "$OUT" "along with what it now builds against"

_flow_test_begin "the deprecated Cargo replace table is reported"
OUT=$(_df_case "Cargo.toml" \
'[dependencies]
serde = "1.0"
' \
'[dependencies]
serde = "1.0"

[replace]
"serde:1.0.0" = { git = "https://github.com/evil/serde" }
')
assert_contains "DEP_REPLACED=serde" "$OUT" "the version suffix is stripped from the key"

_flow_test_begin "a PEP 508 direct reference is reported as a redirect"
# `requests @ https://...` is the standard way to point a Python dependency
# away from PyPI. The url was cut at the `@` and vanished, so the reviewer
# judged an ordinary unpinned requests from the index.
OUT=$(_df_case "pyproject.toml" \
'[project]
dependencies = ["flask"]
' \
'[project]
dependencies = ["flask", "requests @ https://evil.example.com/requests.whl"]
')
assert_contains "DEP_REPLACED=requests" "$OUT" "the redirected package is named"
assert_contains "evil.example.com" "$OUT" "and the url it now comes from"

_flow_test_begin "requirements.txt treats a direct reference the same way"
# The two Python formats disagreed: one dropped the url, the other stored it
# as the version. One requirement, one meaning.
OUT=$(_df_case "requirements.txt" \
'flask==2.0.0
' \
'flask==2.0.0
requests @ https://evil.example.com/requests.whl
')
assert_contains "DEP_REPLACED=requests" "$OUT" "the redirect is reported"
assert_contains "evil.example.com" "$OUT" "with its url"
assert_not_contains "DEP_ADDED=requests@@" "$OUT" "the url is not stored as a version"

_flow_test_begin "a multi-clause constraint is not mistaken for a direct reference"
# The complement: splitting on `@` must not fire on an ordinary constraint.
OUT=$(_df_case "requirements.txt" \
'flask>=1.0,<2.0
' \
'flask>=1.0,<3.0
')
assert_contains "DEP_CHANGED=flask" "$OUT" "an ordinary constraint change is still reported"
assert_not_contains "DEP_REPLACED=flask" "$OUT" "and is not a redirect"

_flow_test_begin "a yarn npm alias reports the package that installs"
# package.json already defended this; yarn was the one parser where the
# near-name check ran against a name the project already trusts.
OUT=$(_df_case "yarn.lock" \
'left-pad@^1.0.0:
  version "1.0.0"
' \
'left-pad@^1.0.0:
  version "1.0.0"

react@npm:evil-react@^1.0.0:
  version "1.0.0"
')
assert_contains "DEP_ADDED=evil-react@1.0.0" "$OUT" "the aliased package is reported by its real name"
assert_contains "DEP_ADDED=react@1.0.0" "$OUT" "and the alias key is kept too"

_flow_test_begin "a sources table for a package nothing depends on is not a redirect"
# `sources` is a common word. Firing on any table with that name produced a
# redirect finding for a package that does not exist in the project.
OUT=$(_df_case "pyproject.toml" \
'[project]
dependencies = ["flask"]
' \
'[project]
dependencies = ["flask"]

[tool.mytool.sources]
mirror = { url = "https://internal.example" }
')
assert_not_contains "DEP_REPLACED=mirror" "$OUT" \
  "a source override for a non-dependency redirects nothing"

_flow_test_begin "a sources table for a package that IS a dependency is a redirect"
# The complement, so the fix is not "ignore sources entirely".
OUT=$(_df_case "pyproject.toml" \
'[project]
dependencies = ["flask"]
' \
'[project]
dependencies = ["flask"]

[tool.uv.sources]
flask = { git = "https://evil.example/flask" }
')
assert_contains "DEP_REPLACED=flask" "$OUT" "a redirect of a real dependency is reported"

# =============================================================================
# Consumer documents agree with what the helper emits
# =============================================================================

_flow_test_begin "every place the agent decides what to act on names DEP_REPLACED"
# The record was added to the per-package section and the priority table but
# not to the DEP_STATE decision table, which is what tells the agent what to
# judge per state — the same "named in no consumer document" defect, fixed in
# two of its three places.
SEC=$(cat "$PLUGIN_DIR/agents/security-reviewer.md")
assert_match 'DEP_ADDED=.*DEP_CHANGED=.*DEP_REPLACED|DEP_REPLACED.*DEP_ADDED' "$SEC" \
  "the state table lists the record alongside the others"
COUNT=$(printf '%s\n' "$SEC" | grep -c "DEP_REPLACED")
[ "$COUNT" -ge 4 ] && _flow_assert_pass "the record appears in every decision surface ($COUNT)" \
  || _flow_assert_fail "the record appears only $COUNT time(s); expected 4 or more"

_flow_test_begin "the agent doc spells the record the way the helper emits it"
assert_contains 'DEP_REPLACED=<module> -> <target>@<version>' "$SEC" \
  "including the version suffix every redirect carries"

_flow_test_begin "both agent-team lenses judge dependencies"
# The skeptic was given the dependency judgment and the verifier was not, so
# in the paired path the surface got one pass rather than two.
REVIEW=$(cat "$PLUGIN_DIR/commands/review.md")
SKEPTIC=$(printf '%s\n' "$REVIEW" | grep -c "dependency judgment")
[ "$SKEPTIC" -ge 2 ] && _flow_assert_pass "both lenses carry it ($SKEPTIC)" \
  || _flow_assert_fail "only $SKEPTIC dispatch carries the dependency judgment"

_flow_test_begin "the goal contract lists every record the helper emits"
# Two records shipped uncontracted; the goal evaluator reads this list.
GOAL=$(cat "$REPO_ROOT/.flow/goals/issue-217.goal.yaml")
for REC in DEP_REPLACED DEP_BASELINE_TRUNCATED; do
  assert_contains "$REC" "$GOAL" "the contract names $REC"
done

# =============================================================================
# Cycle 5: the record set, not one spelling of one record
# =============================================================================

# _df_records <output> — the DEP_ADDED/CHANGED/REMOVED lines, sorted, one per
# line, with locations stripped. Asserting the whole set is what catches a
# phantom package: cycle 3 asserted `not_contains "DEP_ADDED=test@"` and
# stayed green while the code emitted `DEP_ADDED=dev@(unpinned)` — the same
# defect under a name nobody thought to exclude.
_df_records() {
  printf '%s\n' "$1" \
    | grep -E '^DEP_(ADDED|CHANGED|REMOVED)=' \
    | sed 's/ manifest=.*//' \
    | sort
}

_flow_test_begin "a PEP 735 group holding an include-group yields exactly its packages"
# REGRESSION from cycle 4. The group-vs-name test asked whether every value
# was a list of strings; an include-group table made that false, so the table
# was read as name->constraint. Result: a phantom package named after the
# group, mypy reported as REMOVED while still declared, and an added package
# fetched from a URL reported nowhere at all.
OUT=$(_df_case "pyproject.toml" \
'[dependency-groups]
test = ["pytest>=7"]
dev = [{include-group = "test"}, "mypy==1.5.0"]
' \
'[dependency-groups]
test = ["pytest>=7"]
dev = [{include-group = "test"}, "mypy==1.5.0", "evil-pkg @ https://evil.example/e.whl"]
')
assert_equal "DEP_ADDED=evil-pkg@(unpinned)" "$(_df_records "$OUT")" \
  "exactly one record: the package the change added"
assert_contains "DEP_REPLACED=evil-pkg" "$OUT" "and its url is reported as a redirect"
assert_contains "DEP_BASELINE=mypy" "$OUT" "mypy is still a dependency"

_flow_test_begin "a poetry multiple-constraints group yields exactly its packages"
# The other direction, from cycle 4. Both shapes must hold at once, which is
# why they live in one test file: a fix for either that breaks the other is a
# failure here rather than three cycles later.
OUT=$(_df_case "pyproject.toml" \
'[tool.poetry.group.dev.dependencies]
pytest = [{version = "^7.0", python = "<3.8"},]
' \
'[tool.poetry.group.dev.dependencies]
pytest = [{version = "^7.0", python = "<3.8"},]
reqeusts = [{version = "^1.0", python = ">=3.8"},]
')
assert_equal "DEP_ADDED=reqeusts@^1.0" "$(_df_records "$OUT")" \
  "exactly one record, and the group name is not among them"

_flow_test_begin "a yarn alias under a scoped key names the package that installs"
# The cycle-4 fixture used an unscoped key, so it could not discriminate a
# split on the scope's own @. Mutation proved the branch was load-bearing,
# not that it was right.
OUT=$(_df_case "yarn.lock" \
'left-pad@^1.0.0:
  version "1.0.0"
' \
'left-pad@^1.0.0:
  version "1.0.0"

"@scope/react@npm:evil-scoped@^2.0.0":
  version "2.0.0"
')
assert_equal "DEP_ADDED=@scope/react@2.0.0
DEP_ADDED=evil-scoped@2.0.0" "$(_df_records "$OUT")" \
  "both the alias key and the package that installs, and nothing else"

_flow_test_begin "an ordinary scoped package is not read as an alias"
OUT=$(_df_case "yarn.lock" \
'left-pad@^1.0.0:
  version "1.0.0"
' \
'left-pad@^1.0.0:
  version "1.0.0"

"@babel/core@^7.0.0":
  version "7.1.0"
')
assert_equal "DEP_ADDED=@babel/core@7.1.0" "$(_df_records "$OUT")" \
  "exactly one record for a plain scoped package"

_flow_test_begin "the docs no longer promise a line number every finding carries"
# TOML findings are cited at file level. Four places still told the agent the
# location was always `file:line`, so it would invent one.
for F in agents/security-reviewer.md commands/pr.md commands/review.md references/finding-schema.md; do
  C=$(cat "$PLUGIN_DIR/$F")
  # The needle must be the shortest thing that marks the old claim. Matching
  # the whole sentence let a broken replacement pass: the duplicated "located
  # at" pushed the rest onto the next line, so the long needle stopped
  # matching and the assertion went green on garbled prose.
  assert_not_contains "located at" "$C" \
    "$F does not promise a line unconditionally"
done
assert_contains "Do not invent a line number" "$(cat "$PLUGIN_DIR/agents/security-reviewer.md")" \
  "and the agent is told not to invent one"
