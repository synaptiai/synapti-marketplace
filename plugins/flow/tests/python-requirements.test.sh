# Tests for the declared Python dependency of the flow plugin (issue #175).
#
# The version was written down in exactly two places, both of them CI workflows,
# and neither reaches an operator installing the plugin. plugins/flow/requirements.txt
# is now the declaration; the workflows install from the same pins. The failure
# this guards against is drift: someone bumps one workflow, the manifest keeps
# saying something else, and the version an operator installs stops being the
# version anything was tested against.
#
# Each of the three files is parsed on its own terms rather than compared to a
# single variable read twice, because two readings of the same source can never
# disagree and would make this check unable to fail.

REQ="$REPO_ROOT/plugins/flow/requirements.txt"
FLOW_WF="$REPO_ROOT/.github/workflows/flow-tests.yml"
DOSSIER_WF="$REPO_ROOT/.github/workflows/dossier-tests.yml"

_flow_test_begin "requirements manifest exists"
if [ -f "$REQ" ]; then
  _flow_assert_pass "plugins/flow/requirements.txt is present"
else
  _flow_assert_fail "no dependency manifest at $REQ — the PyYAML requirement is undeclared again"
  return 0 2>/dev/null || true
fi

# Parse the manifest: non-comment, non-blank lines of the form name==version.
_manifest_pins() {
  grep -vE '^[[:space:]]*(#|$)' "$REQ" | tr -d ' \r'
}

_flow_test_begin "manifest declares pyyaml with a pinned version"
PYYAML_PIN=$(_manifest_pins | grep -iE '^pyyaml==' || true)
if [ -n "$PYYAML_PIN" ]; then
  _flow_assert_pass "manifest pins $PYYAML_PIN"
else
  _flow_assert_fail "manifest does not pin pyyaml; found: $(_manifest_pins | tr '\n' ' ')"
fi

_flow_test_begin "manifest states that pyyaml is required at run time"
if grep -qiE '^#.*pyyaml.*REQUIRED' "$REQ"; then
  _flow_assert_pass "manifest marks pyyaml as required"
else
  _flow_assert_fail "manifest does not say pyyaml is required at run time — an operator reading it cannot tell which lines are optional"
fi

# --- Pin agreement across the three files ------------------------------------
# Each workflow is read with its own grep against its own file. A package named
# in the manifest but installed at a different version in either workflow is the
# defect; a package named in the manifest and absent from a workflow is not
# (dossier does not have to install everything flow needs).
_wf_pin() {
  # $1 = workflow path, $2 = package name
  grep -oE "'${2}==[0-9][0-9A-Za-z.]*'" "$1" 2>/dev/null | head -1 | tr -d "'"
}

for PKG_LINE in $(_manifest_pins); do
  PKG="${PKG_LINE%%==*}"
  _flow_test_begin "pin for $PKG agrees between the manifest and both workflows"
  FLOW_PIN=$(_wf_pin "$FLOW_WF" "$PKG")
  DOSSIER_PIN=$(_wf_pin "$DOSSIER_WF" "$PKG")
  MISMATCH=""
  [ -n "$FLOW_PIN" ] && [ "$FLOW_PIN" != "$PKG_LINE" ] && MISMATCH="$MISMATCH flow-tests.yml=$FLOW_PIN"
  [ -n "$DOSSIER_PIN" ] && [ "$DOSSIER_PIN" != "$PKG_LINE" ] && MISMATCH="$MISMATCH dossier-tests.yml=$DOSSIER_PIN"
  if [ -z "$MISMATCH" ]; then
    _flow_assert_pass "manifest=$PKG_LINE, flow-tests.yml=${FLOW_PIN:-not installed}, dossier-tests.yml=${DOSSIER_PIN:-not installed}"
  else
    _flow_assert_fail "manifest says $PKG_LINE but$MISMATCH"
  fi
done

# --- Mutant that must fire ---------------------------------------------------
# The comparison above passes trivially if _wf_pin returns empty for every
# package, which is what a changed workflow quoting style would produce. Prove
# the comparison can see a real disagreement.
_flow_test_begin "pin comparison detects a drifted workflow pin"
MUT_WF=$(mktemp -t requirements-mutant.XXXXXX)
sed "s/'pyyaml==[0-9.]*'/'pyyaml==0.0.1'/" "$FLOW_WF" > "$MUT_WF"
MUT_PIN=$(grep -oE "'pyyaml==[0-9][0-9A-Za-z.]*'" "$MUT_WF" | head -1 | tr -d "'")
if [ "$MUT_PIN" = "pyyaml==0.0.1" ] && [ "$MUT_PIN" != "$PYYAML_PIN" ]; then
  _flow_assert_pass "a drifted pin is read as $MUT_PIN and differs from the manifest"
else
  _flow_assert_fail "the workflow parser did not read the mutated pin (got '$MUT_PIN') — it cannot detect drift"
fi
rm -f "$MUT_WF"

_flow_test_begin "workflow pin parser actually found something in the real workflow"
# The counterpart guard: if _wf_pin returns empty on the unmutated file, every
# agreement assertion above was vacuous.
REAL_FLOW_PIN=$(_wf_pin "$FLOW_WF" "pyyaml")
if [ -n "$REAL_FLOW_PIN" ]; then
  _flow_assert_pass "flow-tests.yml installs $REAL_FLOW_PIN"
else
  _flow_assert_fail "no pyyaml pin found in flow-tests.yml — either CI stopped installing it or the parser no longer matches the file"
fi

# --- The guards in the Python entry points stay in place ---------------------
for PY in "$REPO_ROOT/plugins/flow/bin/_journal_atomic.py" "$REPO_ROOT/plugins/flow/bin/_flow_evidence_bundle.py"; do
  _flow_test_begin "$(basename "$PY") guards its yaml import and names the install command"
  if grep -q 'except ImportError' "$PY" && grep -q 'pip install' "$PY"; then
    _flow_assert_pass "import is guarded and the message carries an install command"
  else
    _flow_assert_fail "$(basename "$PY") imports yaml without a guard naming the package and install command"
  fi
done

# --- The README tells the operator ------------------------------------------
_flow_test_begin "README states the PyYAML runtime requirement"
README="$REPO_ROOT/plugins/flow/README.md"
if grep -qi 'PyYAML' "$README" && grep -q 'requirements.txt' "$README"; then
  _flow_assert_pass "README names PyYAML and points at the manifest"
else
  _flow_assert_fail "README does not state the PyYAML requirement or does not point at requirements.txt"
fi
