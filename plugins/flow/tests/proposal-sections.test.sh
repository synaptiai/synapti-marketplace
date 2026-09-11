# Tests for plugins/flow/bin/lib/proposal_sections.py.
#
# The module exists because bin/promote-proposal.sh validated a proposal with a
# substring search and transformed it with a line regex. A `## ` line inside a
# fenced example block looked like a section boundary to the transform, which
# split there, shipped a skill with an unterminated fence, and exited 0.
#
# So the properties under test are not "does it find the headings" but "does it
# refuse to find the ones that are not there", and "do both callers see the
# same answer".
#
# Prerequisites: python3. Skipped gracefully if absent.

PS_LIB="$REPO_ROOT/plugins/flow/bin/lib"

if ! command -v python3 >/dev/null 2>&1; then
  _flow_test_begin "proposal_sections prerequisites"
  _flow_assert_pass "SKIP: python3 not available"
  return 0 2>/dev/null || exit 0
fi

if [ ! -f "$PS_LIB/proposal_sections.py" ]; then
  _flow_test_begin "proposal_sections module present"
  _flow_assert_fail "missing $PS_LIB/proposal_sections.py"
  return 0 2>/dev/null || exit 0
fi

# Run a python snippet with the module importable. Sets PS_OUT and PS_RC as
# globals: a command substitution would discard the exit code the assertions
# need.
_ps_py() {
  PS_OUT=$(PYTHONSAFEPATH=1 PYTHONPATH="$PS_LIB" python3 -c "$1" 2>&1)
  PS_RC=$?
}

# --- the headings that are really there, and only those
_flow_test_begin "H2 titles are found, and fenced lookalikes are not"
_ps_py '
import proposal_sections as ps
body = """# Title

## Contract

x

## Knowledge

```markdown
## Evidence

not a real heading
```

after the fence

## Evidence

real
"""
print("|".join(ps.titles(body)))
'
assert_exit 0 "$PS_RC" "module imports and runs"
assert_equal "Contract|Knowledge|Evidence" "$PS_OUT" "three real headings; the fenced one is not one of them"

# --- must-stay-silent: a tilde fence is not closed by backticks, and a longer
# closing run is legal. Both are CommonMark rules a naive matcher gets wrong in
# opposite directions.
_flow_test_begin "fence delimiters follow the open/close rules"
_ps_py '
import proposal_sections as ps
tilde = """# T

## Contract

~~~
## Evidence
```
still inside the tilde fence
~~~

## Knowledge

x
"""
longer = """# T

## Contract

````
## Evidence
`````

## Knowledge

x
"""
print("|".join(ps.titles(tilde)), "/", "|".join(ps.titles(longer)))
'
assert_equal "Contract|Knowledge / Contract|Knowledge" "$PS_OUT" "backticks do not close a tilde fence; a longer run does close"

# --- round-trip: the split must not lose or invent text
_flow_test_begin "splitting and reassembling reproduces the body exactly"
_ps_py '
import proposal_sections as ps
body = open("'"$REPO_ROOT"'/tests/skills/promote-proposal-fixture.md").read().split("\n---\n", 1)[1]
pre, secs = ps.split(body)
rebuilt = ps.render(pre, secs)
print("ROUNDTRIP", "ok" if rebuilt == body else "LOST")
if rebuilt != body:
    import difflib
    print("".join(list(difflib.unified_diff(body.splitlines(1), rebuilt.splitlines(1)))[:20]))
'
assert_contains "ROUNDTRIP ok" "$PS_OUT" "the real fixture round-trips byte for byte"

# --- input-removal: a body with no H2 at all must report none, not crash and
# not invent one.
_flow_test_begin "a body with no H2 yields no sections"
_ps_py '
import proposal_sections as ps
pre, secs = ps.split("# Only a title\n\nsome prose\n")
print("SECTIONS", len(secs), "PREAMBLE", "kept" if "some prose" in pre else "LOST")
'
assert_exit 0 "$PS_RC" "no crash on a section-less body"
assert_contains "SECTIONS 0 PREAMBLE kept" "$PS_OUT" "nothing invented, nothing dropped"

# --- H3 is not H2, and a trailing-space heading is still a heading
_flow_test_begin "heading recognition is exact"
_ps_py '
import proposal_sections as ps
print("|".join(ps.titles("# T\n\n### Evidence\n\nx\n\n##  Spaced  \n\ny\n\n#Nope\n")))
'
assert_equal "Spaced" "$PS_OUT" "H3 is not a section; a padded H2 is, and its title is trimmed"

# --- the unclosed-fence detector, with a case that must fire and one that must not
_flow_test_begin "an unterminated fence is reported, a terminated one is not"
_ps_py '
import proposal_sections as ps
print(ps.unclosed_fence("# T\n\n```\nopen forever\n"), ps.unclosed_fence("# T\n\n```\nclosed\n```\n"))
'
assert_equal "True False" "$PS_OUT" "fires on the unterminated body, silent on the terminated one"

# --- the whole point: both callers get the same section set
_flow_test_begin "the promoter's two passes agree on the same file"
_ps_py '
import proposal_sections as ps
body = open("'"$REPO_ROOT"'/tests/skills/promote-proposal-fixture.md").read().split("\n---\n", 1)[1]
titles = ps.titles(body)
required = ["Contract", "Pattern Detected", "Knowledge", "Evidence", "Verification", "Promotion Checklist"]
missing = [r for r in required if r not in titles]
print("MISSING", missing)
'
assert_contains "MISSING []" "$PS_OUT" "the canonical fixture satisfies the required set by exact title"
