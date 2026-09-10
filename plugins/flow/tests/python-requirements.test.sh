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

# Cleanup is an EXIT trap, matching cascade-resolve.test.sh and
# commit-journal-churn.test.sh. A trailing `rm` only runs when the file reaches
# its last line, which is exactly not the case on the path that matters.
PYREQ_CLEANUP=()
_pyreq_cleanup() {
  local p
  for p in "${PYREQ_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done
}
trap _pyreq_cleanup EXIT

REQ="$REPO_ROOT/plugins/flow/requirements.txt"
FLOW_WF="$REPO_ROOT/.github/workflows/flow-tests.yml"
DOSSIER_WF="$REPO_ROOT/.github/workflows/dossier-tests.yml"

_flow_test_begin "requirements manifest exists"
if [ -f "$REQ" ]; then
  _flow_assert_pass "plugins/flow/requirements.txt is present"
else
  _flow_assert_fail "no dependency manifest at $REQ — the PyYAML requirement is undeclared again"
  return 0
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

# Quote-agnostic on purpose. An earlier version anchored on single quotes, so a
# pin written the ordinary way — `pip install pyyaml==9.9.9` — was invisible to
# it, and the must-fire mutant below appended a QUOTED pin, which proved only
# that the regex saw quoted pins.
_flow_test_begin "flow-tests.yml carries no second copy of a version"
INLINE=$(grep -oE "(pyyaml|jsonschema)==[0-9][0-9A-Za-z.]*" "$FLOW_WF" || true)
if [ -z "$INLINE" ]; then
  _flow_assert_pass "no inline pins in flow-tests.yml"
else
  _flow_assert_fail "flow-tests.yml pins versions inline as well as reading the manifest: $(printf '%s' "$INLINE" | tr '\n' ' ')"
fi

# --- Nothing here asserts anything about another plugin ----------------------
# An earlier version compared dossier-tests.yml against this manifest. That made
# a PyYAML bump in flow turn the flow suite red for a reason living entirely in
# another plugin, fixable only by editing dossier — the coupling this repository
# forbids at run time, imposed through a test instead. dossier owns its own
# pins; if they need guarding, the guard belongs in dossier.

# --- Mutant that must fire ---------------------------------------------------
# Both checks above pass trivially if their greps match nothing: an empty grep
# reads exactly like agreement. Prove each can see the thing it looks for.
_flow_test_begin "the inline-pin check detects a reintroduced copy"
MUT_FLOW=$(mktemp -t requirements-inline-mutant.XXXXXX 2>/dev/null) || MUT_FLOW=""
if [ -z "$MUT_FLOW" ]; then
  _flow_assert_fail "mktemp failed; cannot build the comparison file"
  return 0
fi
PYREQ_CLEANUP+=("$MUT_FLOW")
cp "$FLOW_WF" "$MUT_FLOW"
# Unquoted, which is how someone would actually type it back in.
printf "%s\n" "          python3 -m pip install pyyaml==9.9.9" >> "$MUT_FLOW"
MUT_INLINE=$(grep -oE "(pyyaml|jsonschema)==[0-9][0-9A-Za-z.]*" "$MUT_FLOW" || true)
if [ -n "$MUT_INLINE" ]; then
  _flow_assert_pass "a reintroduced inline pin is seen as $MUT_INLINE"
else
  _flow_assert_fail "the inline-pin check cannot see an unquoted inline pin, so its silence on the real file means nothing"
fi

_flow_test_begin "the install-line check detects a job that installs nothing"
MUT_JOB=$(mktemp -t requirements-job-mutant.XXXXXX 2>/dev/null) || MUT_JOB=""
if [ -z "$MUT_JOB" ]; then
  _flow_assert_fail "mktemp failed; cannot build the comparison file"
  return 0
fi
PYREQ_CLEANUP+=("$MUT_JOB")
# Strip the install line from the second job only, which is exactly the shape
# that passed on Ubuntu and failed on macOS the first time the job ran.
awk '/pip install .*-r plugins\/flow\/requirements\.txt/ { n++; if (n == 2) next } { print }' \
  "$FLOW_WF" > "$MUT_JOB"
MUT_INSTALLS=$(grep -cE 'pip install .*-r plugins/flow/requirements\.txt' "$MUT_JOB" || true)
if [ "${MUT_INSTALLS:-0}" -eq 1 ]; then
  _flow_assert_pass "a job missing its install is visible as $MUT_INSTALLS install line(s)"
else
  _flow_assert_fail "the mutant did not reduce the install count (got ${MUT_INSTALLS:-0}); the per-job check cannot detect a job that installs nothing"
fi

# --- The guards in the Python entry points stay in place ---------------------
for PY in "$REPO_ROOT/plugins/flow/bin/_journal_atomic.py" "$REPO_ROOT/plugins/flow/bin/_flow_evidence_bundle.py"; do
  _flow_test_begin "$(basename "$PY") guards its yaml import and names the install command"
  # Tied to the yaml import specifically. Two independent greps would pass on a
  # file whose guarded import was something else entirely and whose `pip
  # install` sat in an unrelated comment.
  GUARD_BLOCK=$(awk '
    /^try:/ { buf = ""; depth = 1 }
    depth { buf = buf "\n" $0 }
    depth && /^except ImportError/ { seen = 1 }
    depth && seen && /pip install/ { print buf; exit }
    /^[^[:space:]#]/ && depth && !/^try:/ && !/^except/ { if (!seen) depth = 0 }
  ' "$PY")
  if printf '%s' "$GUARD_BLOCK" | grep -q 'import yaml'; then
    _flow_assert_pass "the guarded import is yaml and its message carries an install command"
  else
    _flow_assert_fail "$(basename "$PY") has no try/except ImportError around 'import yaml' whose message names an install command"
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
