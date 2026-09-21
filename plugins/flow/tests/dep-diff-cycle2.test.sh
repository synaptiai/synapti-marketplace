# Tests for the second review cycle on the dependency judgment — issue #217.
#
# Nine findings, all reproduced before they were fixed. Three were regressions
# introduced by the FIRST cycle's own fixes, which is why each one here has a
# fixture rather than a note: the pattern on a sister issue was that a fix
# without a must-fail test is lost by the next rework.
#
# Two failure directions appear here and they are not symmetric:
#   - `STATE=ok` with a package missing is the defect this issue exists to
#     remove. A typosquat nobody reports is the whole problem.
#   - `STATE=unavailable` on a valid, common manifest is the other direction:
#     a gate that blocks every pull request in an ecosystem teaches the reader
#     to wave it through, which agents/security-reviewer.md itself warns about.
#
# Prereq: git and python3. SKIPS gracefully if absent.

if ! command -v git >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  _flow_test_begin "git and python3 prerequisite"
  _flow_assert_pass "SKIP: git or python3 not installed"
  return 0
fi

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
DEP_DIFF="$PLUGIN_DIR/bin/flow-dep-diff.sh"

DC_CLEANUP=()
_dc_cleanup() { local p; for p in "${DC_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _dc_cleanup EXIT

_dc_repo() {
  local d
  d=$(mktemp -d -t "flow-dc.XXXXXX") || return 1
  DC_CLEANUP+=("$d")
  git -C "$d" init --quiet 2>/dev/null
  git -C "$d" config user.email "test@example.invalid"
  git -C "$d" config user.name "flow test"
  git -C "$d" config commit.gpgsign false
  printf '%s\n' "$d"
}
_dc_commit() {
  git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" commit --quiet --allow-empty -m "$2" >/dev/null 2>&1
}
# _dc_case <file> <base> <head> — commits both, echoes the helper output.
_dc_case() {
  local R
  R=$(_dc_repo)
  mkdir -p "$(dirname "$R/$1")"
  printf '%s' "$2" > "$R/$1"; _dc_commit "$R" "base"
  printf '%s' "$3" > "$R/$1"; _dc_commit "$R" "head"
  ( cd "$R" && "$DEP_DIFF" --base HEAD~1 --head HEAD 2>&1 )
}

# =============================================================================
# F1 — a PEP 508 extras marker closed the array, dropping everything after it
# =============================================================================

_flow_test_begin "an extras marker does not truncate the dependency array"
# `requests[security]>=2.31.0` carries a `]` that belongs to the dependency's
# own text. Treated as the array's closing bracket, every dependency declared
# after it was dropped and the run still said ok.
OUT=$(_dc_case "pyproject.toml" \
'[project]
name = "demo"
dependencies = [
  "requests[security]>=2.31.0",
  "flask>=3.0",
]
' \
'[project]
name = "demo"
dependencies = [
  "requests[security]>=2.31.0",
  "flask>=3.0",
  "reqeusts==0.1.0",
]
')
assert_contains "DEP_ADDED=reqeusts@0.1.0" "$OUT" \
  "a package declared after an extras marker is still reported"
assert_contains "DEP_BASELINE=flask" "$OUT" \
  "and one declared after it at the base still reaches the baseline"

_flow_test_begin "an unbalanced bracket inside a dependency string is not a closer"
# A `]` inside a quoted item is part of the dependency's own text. Counted as
# array nesting it ends the array early, and every dependency after it is
# dropped with the run still reporting ok. A balanced pair inside a string
# nets to zero and hides this, so the discriminating case is an UNBALANCED
# bracket — an environment marker comparing against a string holding one.
OUT=$(_dc_case "pyproject.toml" \
'[project]
dependencies = [
  "pkg; extra == '"'"'a]b'"'"'",
]
' \
'[project]
dependencies = [
  "pkg; extra == '"'"'a]b'"'"'",
  "reqeusts==0.1.0",
]
')
assert_contains "DEP_ADDED=reqeusts@0.1.0" "$OUT" \
  "the dependency after the bracket-carrying item is still reported"

_flow_test_begin "a single-quoted dependency item is read"
# TOML allows either quote. Scanning only for double quotes dropped the item
# entirely, with no parse error to show for it.
OUT=$(_dc_case "pyproject.toml" \
"[project]
dependencies = [
  'flask>=3.0',
]
" \
"[project]
dependencies = [
  'flask>=3.0',
  'reqeusts==0.1.0',
]
")
assert_contains "DEP_ADDED=reqeusts@0.1.0" "$OUT" "a single-quoted item is a dependency"

# =============================================================================
# F2 / F5 — regressions: valid manifests became a permanent `unavailable`
# =============================================================================

_flow_test_begin "a Cargo feature list spanning lines is readable"
# REGRESSION from cycle 1. The new "fail loudly" raise fired on every
# continuation line, so a repository whose Cargo.toml writes a long feature
# list got STATE=unavailable on every pull request — and the package added
# alongside it was never reported.
OUT=$(_dc_case "Cargo.toml" \
'[dependencies]
serde = { version = "1.0", features = [
  "derive",
] }
' \
'[dependencies]
serde = { version = "1.0", features = [
  "derive",
  "rc",
] }
evil = "6.6.6"
')
assert_contains "STATE=ok" "$OUT" "a multi-line value is not a parse failure"
assert_not_contains "STATE=unavailable" "$OUT" "the manifest is readable"
assert_contains "DEP_ADDED=evil@6.6.6" "$OUT" "and the package added beside it is reported"

_flow_test_begin "a poetry multiple-constraints dependency is readable"
# REGRESSION from cycle 1, same root cause as the Cargo case above.
OUT=$(_dc_case "pyproject.toml" \
'[tool.poetry.dependencies]
python = "^3.11"
' \
'[tool.poetry.dependencies]
python = "^3.11"
foo = [
  {version = "<=1.9", python = ">=3.6,<3.8"},
]
')
assert_contains "STATE=ok" "$OUT" "documented poetry syntax is not a parse failure"
assert_contains "DEP_ADDED=foo@" "$OUT" "and the dependency is reported"

# =============================================================================
# F3 — dependency sections that were silently ignored
# =============================================================================

_flow_test_begin "a typosquat in any supported Python dependency section is reported"
# Each of these is a real way a Python project declares dependencies. Skipped,
# a package added there produced STATE=ok and no finding at all.
_dc_section() {
  local label="$1" base="$2" head="$3" OUT
  OUT=$(_dc_case "pyproject.toml" "$base" "$head")
  assert_contains "DEP_ADDED=reqeusts@0.1.0" "$OUT" "$label: the added package is reported"
  assert_not_contains "STATE=none" "$OUT" "$label: the section is not invisible"
}

_dc_section "PEP 735 dependency-groups" \
'[dependency-groups]
dev = ["pytest>=8"]
' \
'[dependency-groups]
dev = ["pytest>=8", "reqeusts==0.1.0"]
'

_dc_section "pdm dev-dependencies" \
'[tool.pdm.dev-dependencies]
test = ["pytest>=8"]
' \
'[tool.pdm.dev-dependencies]
test = ["pytest>=8", "reqeusts==0.1.0"]
'

_dc_section "uv dev-dependencies" \
'[tool.uv]
dev-dependencies = ["pytest>=8"]
' \
'[tool.uv]
dev-dependencies = ["pytest>=8", "reqeusts==0.1.0"]
'

_dc_section "hatch env dependencies" \
'[tool.hatch.envs.default]
dependencies = ["pytest>=8"]
' \
'[tool.hatch.envs.default]
dependencies = ["pytest>=8", "reqeusts==0.1.0"]
'

_dc_section "PEP 621 inline optional-dependencies" \
'[project]
dependencies = ["flask"]
optional-dependencies = {dev = ["pytest>=8"]}
' \
'[project]
dependencies = ["flask"]
optional-dependencies = {dev = ["pytest>=8", "reqeusts==0.1.0"]}
'

_flow_test_begin "an unknown tool's dependency section is read, not skipped"
# Recognising a dependency table by its SHAPE rather than by a list of known
# tool names is what makes a tool nobody anticipated readable. Three cycles
# were lost adding pdm, then uv, then rye, then pixi one at a time — each
# absence reported as ok with the packages missing, or as a blanket
# unavailable that would have blocked every pull request in that repository.
OUT=$(_dc_case "pyproject.toml" \
'[project]
dependencies = ["flask"]
' \
'[project]
dependencies = ["flask"]

[tool.somethingnew.dependencies]
mystery = "1.0"
')
assert_contains "DEP_ADDED=mystery@1.0" "$OUT" \
  "a dependency under an unheard-of tool is still a dependency"
assert_contains "STATE=ok" "$OUT" "and a readable manifest is not refused"

_flow_test_begin "a pixi dependency table is read rather than refused"
# [tool.pixi.dependencies] lives in a real pyproject.toml. An earlier cycle
# raised on it, which would have made every pull request in a pixi project
# report unavailable.
OUT=$(_dc_case "pyproject.toml" \
'[tool.pixi.dependencies]
python = "3.11"
' \
'[tool.pixi.dependencies]
python = "3.11"
reqeusts = "0.1.0"
')
assert_contains "DEP_ADDED=reqeusts@0.1.0" "$OUT" "the added package is reported"
assert_not_contains "STATE=unavailable" "$OUT" "a valid manifest is not a blocked gate"

_flow_test_begin "a manifest that is not valid TOML is still refused"
# The honest boundary moved but did not disappear: an unreadable FILE is
# still unavailable. What changed is that an unfamiliar SHAPE inside a
# readable file no longer counts as unreadable.
OUT=$(_dc_case "pyproject.toml" \
'[project]
dependencies = ["flask"]
' \
'[project
dependencies = ["flask"
')
assert_contains "STATE=unavailable" "$OUT" "invalid TOML is reported unreadable"
assert_contains "MANIFEST_UNPARSED=pyproject.toml" "$OUT" "and the file is named"

# =============================================================================
# F4 — regression: a package in two sections turned a bump into add + remove
# =============================================================================

_flow_test_begin "bumping a package declared in two sections is one change"
# REGRESSION from cycle 1's multi-version model. typescript in dependencies
# and devDependencies collapsed into one name with two versions, so the bump
# case never fired and a routine bump produced a false DEP_ADDED and a false
# DEP_REMOVED — each false add costing a full per-package judgment downstream.
OUT=$(_dc_case "package.json" \
'{
  "dependencies": { "typescript": "5.0.0" },
  "devDependencies": { "typescript": "5.1.0" }
}
' \
'{
  "dependencies": { "typescript": "5.4.0" },
  "devDependencies": { "typescript": "5.1.0" }
}
')
assert_contains "DEP_CHANGED=typescript 5.0.0->5.4.0" "$OUT" "the bump reads as a bump"
assert_not_contains "DEP_ADDED=typescript" "$OUT" "the package was not added"
assert_not_contains "DEP_REMOVED=typescript" "$OUT" "and it was not removed"

# =============================================================================
# F6 — a go.mod replace must name the module that stopped coming from upstream
# =============================================================================

_flow_test_begin "a go.mod replace names the module it redirects"
# Reporting only the target said a package was added whose name is a path,
# while the module actually redirected still read as untouched.
OUT=$(_dc_case "go.mod" \
'module example.com/demo

require github.com/sirupsen/logrus v1.9.0
' \
'module example.com/demo

require github.com/sirupsen/logrus v1.9.0

replace github.com/sirupsen/logrus => ../vendor/logrus
')
assert_contains "DEP_REPLACED=github.com/sirupsen/logrus" "$OUT" \
  "the redirected module is named"
assert_contains "../vendor/logrus" "$OUT" "along with what it now points at"
assert_not_contains "DEP_ADDED=../vendor/logrus" "$OUT" \
  "a filesystem path is not reported as an added package"

_flow_test_begin "a replace to a forked module is reported"
OUT=$(_dc_case "go.mod" \
'module example.com/demo

require github.com/a/b v1.0.0
' \
'module example.com/demo

require github.com/a/b v1.0.0

replace github.com/a/b => github.com/evil/fork v6.6.6
')
assert_contains "DEP_REPLACED=github.com/a/b" "$OUT" "the module is named"
assert_contains "github.com/evil/fork" "$OUT" "and the fork it now resolves to"

# =============================================================================
# F7 — loosening a pin is a dependency change
# =============================================================================

_flow_test_begin "loosening an exact pin to a range is reported"
# Storing only the number made `==2.31.0` and `>=2.31.0` identical, so the
# change produced nothing. Constraint loosening is a standard supply-chain
# move and the helper's contract covers a bump.
OUT=$(_dc_case "requirements.txt" \
'requests==2.31.0
' \
'requests>=2.31.0
')
assert_contains "DEP_CHANGED=requests" "$OUT" "the constraint change is reported"
assert_not_contains "STATE=none" "$OUT" "the range is not reported as touching nothing"

_flow_test_begin "an exact pin still reads as a bare version"
OUT=$(_dc_case "requirements.txt" \
'requests==2.31.0
' \
'requests==2.32.0
')
assert_contains "DEP_CHANGED=requests 2.31.0->2.32.0" "$OUT" \
  "an ordinary pin bump keeps its plain shape"

# =============================================================================
# F9 — invisible characters must not reach the reviewer's prompt
# =============================================================================

_flow_test_begin "a name carrying a bidi override is refused"
# U+202E can visually reorder the printed record, and a zero-width character
# defeats the near-name comparison while looking identical to a reader.
R=$(_dc_repo)
printf '{"dependencies":{}}\n' > "$R/package.json"; _dc_commit "$R" "base"
python3 - "$R/package.json" <<'PYEOF'
import json, sys
json.dump({"dependencies": {"ev‮il": "1.0.0"}}, open(sys.argv[1], "w"), indent=1)
PYEOF
_dc_commit "$R" "head"
OUT=$( cd "$R" && "$DEP_DIFF" --base HEAD~1 --head HEAD 2>&1 )
assert_contains "STATE=unavailable" "$OUT" "a bidi override makes the manifest unreadable"
assert_not_contains "DEP_ADDED=ev" "$OUT" "the name is not printed"

_flow_test_begin "a name carrying a zero-width space is refused"
R=$(_dc_repo)
printf '{"dependencies":{}}\n' > "$R/package.json"; _dc_commit "$R" "base"
python3 - "$R/package.json" <<'PYEOF'
import json, sys
json.dump({"dependencies": {"req​uests": "1.0.0"}}, open(sys.argv[1], "w"), indent=1)
PYEOF
_dc_commit "$R" "head"
OUT=$( cd "$R" && "$DEP_DIFF" --base HEAD~1 --head HEAD 2>&1 )
assert_contains "STATE=unavailable" "$OUT" "a zero-width character makes the manifest unreadable"
assert_not_contains "DEP_ADDED=requests" "$OUT" \
  "it never prints as the name it is imitating"
