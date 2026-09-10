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

# --- flow's own workflow installs from the manifest, not from its own copy ---
# Drift between a manifest and a workflow is only possible while both write the
# version down. flow-tests.yml no longer does: it installs -r the manifest, so
# there is one string and nothing to drift. The assertion is therefore about the
# absence of a second copy, not about two copies agreeing.
_flow_test_begin "flow-tests.yml installs from the manifest in every job"
INSTALL_LINES=$(grep -cE 'pip install .*-r plugins/flow/requirements\.txt' "$FLOW_WF" || true)
[ -z "$INSTALL_LINES" ] && INSTALL_LINES=0
# Job keys are the two-space-indented mapping keys under the top-level `jobs:`
# block. Counting every two-space key in the file would also count pull_request
# and push under `on:`, which is how the first version of this assertion
# reported three jobs for a two-job workflow.
JOB_COUNT=$(awk '
  /^jobs:/ { in_jobs = 1; next }
  /^[^[:space:]#]/ { in_jobs = 0 }
  in_jobs && /^  [A-Za-z_][A-Za-z0-9_-]*:[[:space:]]*$/ { n++ }
  END { print n + 0 }
' "$FLOW_WF")
[ -z "$JOB_COUNT" ] && JOB_COUNT=0
if [ "$INSTALL_LINES" -ge 2 ] && [ "$INSTALL_LINES" -eq "$JOB_COUNT" ]; then
  _flow_assert_pass "$INSTALL_LINES of $JOB_COUNT jobs install from the manifest"
else
  _flow_assert_fail "$INSTALL_LINES install-from-manifest lines for $JOB_COUNT jobs — a job that does not install PyYAML fails on any runner image that does not ship it, which is how the root-tests job first went red on macOS and green on Ubuntu"
fi

_flow_test_begin "flow-tests.yml carries no second copy of a version"
INLINE=$(grep -oE "'(pyyaml|jsonschema)==[0-9][0-9A-Za-z.]*'" "$FLOW_WF" || true)
if [ -z "$INLINE" ]; then
  _flow_assert_pass "no inline pins in flow-tests.yml"
else
  _flow_assert_fail "flow-tests.yml pins versions inline as well as reading the manifest: $(printf '%s' "$INLINE" | tr '\n' ' ')"
fi

# --- the dossier workflow keeps its own pins, so those are checked for drift ---
# Pointing the dossier suite at the flow plugin manifest would couple two
# plugins that are otherwise independent. It keeps its own copy, and a copy is
# exactly the thing that drifts, so it is compared.
_wf_pin() {
  grep -oE "'${2}==[0-9][0-9A-Za-z.]*'" "$1" 2>/dev/null | head -1 | tr -d "'"
}

for PKG_LINE in $(_manifest_pins); do
  PKG="${PKG_LINE%%==*}"
  DOSSIER_PIN=$(_wf_pin "$DOSSIER_WF" "$PKG")
  [ -z "$DOSSIER_PIN" ] && continue
  _flow_test_begin "dossier-tests.yml pins $PKG at the version the manifest declares"
  if [ "$DOSSIER_PIN" = "$PKG_LINE" ]; then
    _flow_assert_pass "manifest=$PKG_LINE, dossier-tests.yml=$DOSSIER_PIN"
  else
    _flow_assert_fail "manifest says $PKG_LINE but dossier-tests.yml installs $DOSSIER_PIN"
  fi
done

# --- Mutant that must fire ---------------------------------------------------
# Both checks above pass trivially if the parsers match nothing — an empty grep
# is indistinguishable from agreement. Prove each can see a real disagreement.
_flow_test_begin "the drift check detects a mutated dossier pin"
MUT_WF=$(mktemp -t requirements-mutant.XXXXXX)
sed "s/'pyyaml==[0-9.]*'/'pyyaml==0.0.1'/" "$DOSSIER_WF" > "$MUT_WF"
MUT_PIN=$(_wf_pin "$MUT_WF" "pyyaml")
if [ "$MUT_PIN" = "pyyaml==0.0.1" ] && [ "$MUT_PIN" != "$PYYAML_PIN" ]; then
  _flow_assert_pass "a drifted pin is read as $MUT_PIN and differs from the manifest"
else
  _flow_assert_fail "the workflow parser did not read the mutated pin (got '$MUT_PIN') — it cannot detect drift"
fi
rm -f "$MUT_WF"

_flow_test_begin "the drift check found a real pin to compare against"
REAL_DOSSIER_PIN=$(_wf_pin "$DOSSIER_WF" "pyyaml")
if [ -n "$REAL_DOSSIER_PIN" ]; then
  _flow_assert_pass "dossier-tests.yml installs $REAL_DOSSIER_PIN"
else
  _flow_assert_fail "no pyyaml pin found in dossier-tests.yml — either it stopped installing PyYAML or the parser no longer matches the file, and the comparison above was vacuous"
fi

_flow_test_begin "the inline-pin check detects a reintroduced copy"
MUT_FLOW=$(mktemp -t requirements-inline-mutant.XXXXXX)
cp "$FLOW_WF" "$MUT_FLOW"
printf "%s\n" "            'pyyaml==6.0.2' \\" >> "$MUT_FLOW"
MUT_INLINE=$(grep -oE "'(pyyaml|jsonschema)==[0-9][0-9A-Za-z.]*'" "$MUT_FLOW" || true)
if [ -n "$MUT_INLINE" ]; then
  _flow_assert_pass "a reintroduced inline pin is seen as $MUT_INLINE"
else
  _flow_assert_fail "the inline-pin check cannot see an inline pin, so its silence on the real file means nothing"
fi
rm -f "$MUT_FLOW"

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
