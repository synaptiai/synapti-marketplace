# Tests for the third review cycle on the dependency judgment — issue #217.
#
# Cycle 3 found twelve defects and all three P1s were in code cycle 2 had just
# added. The counts across the three cycles were 14, 9, 12 — not converging —
# and the reason was one decision, not twelve mistakes: the TOML formats were
# read by a hand-rolled scanner, and each fix revealed the next construct it
# did not know. Tri-quoted strings, backslash escapes, inline-table keys,
# multi-clause constraints.
#
# The scanner is gone. pyproject.toml, Cargo.toml, poetry.lock and Cargo.lock
# are parsed with `tomllib` (or `tomli` below 3.11), which has none of those
# gaps to find. These fixtures are the cycle-3 inputs, kept so the decision
# cannot be quietly reversed: each one FAILED against the scanner.
#
# Prereq: git, python3, and a TOML parser. SKIPS gracefully if absent.

if ! command -v git >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  _flow_test_begin "git and python3 prerequisite"
  _flow_assert_pass "SKIP: git or python3 not installed"
  return 0
fi
if ! python3 -c "
import sys
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

DT_CLEANUP=()
_dt_cleanup() { local p; for p in "${DT_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _dt_cleanup EXIT

_dt_repo() {
  local d
  d=$(mktemp -d -t "flow-dt.XXXXXX") || return 1
  DT_CLEANUP+=("$d")
  git -C "$d" init --quiet 2>/dev/null
  git -C "$d" config user.email "test@example.invalid"
  git -C "$d" config user.name "flow test"
  git -C "$d" config commit.gpgsign false
  printf '%s\n' "$d"
}
_dt_commit() {
  git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" commit --quiet --allow-empty -m "$2" >/dev/null 2>&1
}
_dt_case() {
  local R
  R=$(_dt_repo)
  mkdir -p "$(dirname "$R/$1")"
  printf '%s' "$2" > "$R/$1"; _dt_commit "$R" "base"
  printf '%s' "$3" > "$R/$1"; _dt_commit "$R" "head"
  ( cd "$R" && "$DEP_DIFF" --base HEAD~1 --head HEAD 2>&1 )
}

# =============================================================================
# The TOML string grammar — the gap that made a whole manifest invisible
# =============================================================================

_flow_test_begin "a tri-quoted string does not hide the dependencies after it"
# The worst defect of the three cycles. A section-shaped line inside a
# multi-line string became the current section, so everything declared after
# the readme was attributed elsewhere: the parser returned an EMPTY dependency
# set and the helper still reported ok. A readme or changelog in pyproject.toml
# is entirely ordinary.
OUT=$(_dt_case "pyproject.toml" \
'[project]
name = "demo"
readme_text = """
Changelog

[1.2.0]
  - things
"""
dependencies = ["flask>=2.0"]
' \
'[project]
name = "demo"
readme_text = """
Changelog

[1.2.0]
  - things
"""
dependencies = ["flask>=2.0", "reqeusts==1.0.0"]
')
assert_contains "DEP_ADDED=reqeusts@1.0.0" "$OUT" \
  "a package declared after a tri-quoted string is reported"
assert_contains "DEP_BASELINE=flask" "$OUT" \
  "and the existing one still reaches the baseline"

_flow_test_begin "an unbalanced bracket in a tri-quoted string does not swallow the file"
OUT=$(_dt_case "Cargo.toml" \
'[package]
name = "demo"
description = """
usage: foo[bar
"""

[dependencies]
serde = "1.0"
' \
'[package]
name = "demo"
description = """
usage: foo[bar
"""

[dependencies]
serde = "1.0"
evil = "6.6.6"
')
assert_contains "DEP_ADDED=evil@6.6.6" "$OUT" "the dependency section is still read"
assert_contains "DEP_BASELINE=serde" "$OUT" "and so is the baseline"

_flow_test_begin "an escaped quote inside a string does not end it"
OUT=$(_dt_case "Cargo.toml" \
'[package]
description = "Handles \"[\" tokens"

[dependencies]
serde = "1.0"
' \
'[package]
description = "Handles \"[\" tokens"

[dependencies]
serde = "1.0"
evil = "6.6.6"
')
assert_contains "DEP_ADDED=evil@6.6.6" "$OUT" "the escape is not a string terminator"

_flow_test_begin "a literal tri-quoted string is handled too"
OUT=$(_dt_case "pyproject.toml" \
"[project]
notes = '''
[not-a-section]
'''
dependencies = ['flask>=2.0']
" \
"[project]
notes = '''
[not-a-section]
'''
dependencies = ['flask>=2.0', 'reqeusts==1.0.0']
")
assert_contains "DEP_ADDED=reqeusts@1.0.0" "$OUT" "a single-quoted tri-quote behaves the same"

# =============================================================================
# Constraints — the whole constraint, and only what it means
# =============================================================================

_flow_test_begin "widening a version ceiling is reported"
# The constraint was truncated at the first comma, so a change to the second
# clause produced nothing at all. Widening a ceiling is the same pin-loosening
# move that keeping the operator was added to catch.
OUT=$(_dt_case "pyproject.toml" \
'[project]
dependencies = ["flask>=1.0,<2.0"]
' \
'[project]
dependencies = ["flask>=1.0,<3.0"]
')
assert_contains "DEP_CHANGED=flask" "$OUT" "the ceiling change is reported"
assert_not_contains "STATE=none" "$OUT" "not reported as touching nothing"

_flow_test_begin "reformatting a constraint is not a dependency change"
# Whitespace inside a constraint carried meaning, so a formatter run produced
# a DEP_CHANGED and a full five-check judgment for an edit that changed
# nothing. The two Python formats also disagreed with each other on it.
OUT=$(_dt_case "pyproject.toml" \
'[project]
dependencies = ["requests>=2.0"]
' \
'[project]
dependencies = ["requests >= 2.0"]
')
assert_not_contains "DEP_CHANGED=requests" "$OUT" "whitespace alone is not a change"

_flow_test_begin "the same requirement spelled two ways stores one value"
OUT=$(_dt_case "requirements.txt" \
'flask>=1.0,<2.0
' \
'flask>=1.0, <2.0
')
assert_not_contains "DEP_CHANGED=flask" "$OUT" "a space after the comma is not a change"

_flow_test_begin "a real requirements change is still reported"
# The complement of the two above: normalising must not silence a change.
OUT=$(_dt_case "requirements.txt" \
'flask>=1.0,<2.0
' \
'flask>=1.0,<3.0
')
assert_contains "DEP_CHANGED=flask" "$OUT" "a changed clause is still a change"

# =============================================================================
# Dependency tables recognised by shape, not by a list of tool names
# =============================================================================

_flow_test_begin "an include-group reference is not a package"
# `_toml_items` yielded the quoted strings, so `{include-group = "test"}`
# produced a phantom package named test — which then cost a full per-package
# judgment AND emitted a fabricated near-name finding against pytest, because
# the edit distance between them is 2.
OUT=$(_dt_case "pyproject.toml" \
'[dependency-groups]
test = ["pytest"]
' \
'[dependency-groups]
test = ["pytest"]
dev = [{include-group = "test"}]
')
assert_not_contains "DEP_ADDED=test@" "$OUT" "the group reference is not a package"
assert_not_contains "DEP_NEAR_NAME=test" "$OUT" "and raises no fabricated typosquat"

_flow_test_begin "an inline-table group key is not a package"
OUT=$(_dt_case "pyproject.toml" \
'[project]
dependencies = ["flask"]
' \
'[project]
dependencies = ["flask"]
optional-dependencies = {dev-tools = ["black"]}
')
assert_contains "DEP_ADDED=black" "$OUT" "the dependency inside the group is reported"
assert_not_contains "DEP_ADDED=dev-tools" "$OUT" "the group name is not"

_flow_test_begin "a tool nobody anticipated still has its dependencies read"
# pdm, then uv, then rye, then pixi were each added by hand after a review
# found them missing. Recognising the table by shape ends that sequence.
for TOOLSEC in "tool.rye" "tool.pixi" "tool.whatever"; do
  OUT=$(_dt_case "pyproject.toml" \
"[$TOOLSEC.dev-dependencies]
group = [\"pytest>=8\"]
" \
"[$TOOLSEC.dev-dependencies]
group = [\"pytest>=8\", \"reqeusts==0.1.0\"]
")
  assert_contains "DEP_ADDED=reqeusts@0.1.0" "$OUT" "$TOOLSEC: the added package is reported"
  assert_not_contains "STATE=unavailable" "$OUT" "$TOOLSEC: and the manifest is not refused"
done

# =============================================================================
# A redirect is reported and its target compared
# =============================================================================

_flow_test_begin "a replacement target is compared for a near-name"
OUT=$(_dt_case "go.mod" \
'module example.com/demo

require github.com/sirupsen/logrus v1.9.0
' \
'module example.com/demo

require github.com/sirupsen/logrus v1.9.0

replace github.com/sirupsen/logrus => github.com/sirupsen/logrvs v1.9.0
')
assert_contains "DEP_REPLACED=github.com/sirupsen/logrus" "$OUT" "the redirect is reported"
assert_contains "DEP_NEAR_NAME=" "$OUT" \
  "and a target imitating the module it replaces is flagged"

_flow_test_begin "a Python source redirect is reported like a go.mod replace"
# tool.uv.sources and a poetry `git =` entry are the same supply-chain move as
# a go.mod replace; only Go had a record for it.
OUT=$(_dt_case "pyproject.toml" \
'[project]
dependencies = ["flask"]
' \
'[project]
dependencies = ["flask"]

[tool.uv.sources]
flask = { git = "https://evil.example/flask" }
')
assert_contains "DEP_REPLACED=flask" "$OUT" "the redirected package is named"
assert_contains "evil.example" "$OUT" "along with where it now comes from"
