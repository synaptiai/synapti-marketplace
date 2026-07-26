#!/usr/bin/env bash
# Bin script hygiene, plus THE ANTI-THEATER ASSERTION.
#
# The gate's whole credibility rests on one property: it must not emit PASS from
# mechanical checks alone. Ten mechanical conditions can prove a package is not
# releasable; they can never prove it is, because the judgment set includes the
# scorecard and three of the four "must never appear" rules. A gate that passed
# on mechanics would certify a package whose planned features are documented as
# shipped, having read none of it.

_dossier_test_begin "bin-scripts"

BIN="plugins/dossier/bin"

EXPECTED_SCRIPTS="cascade-resolve.sh
dossier-blast-radius.sh
dossier-claim-scan.sh
dossier-evidence.sh
dossier-gate.sh
dossier-ledger-lint.sh
dossier-managed-file.sh
dossier-package-check.sh
dossier-policy.sh
dossier-pr-body.sh
dossier-resolve-config.sh
dossier-scaffold.sh
dossier-validate-config.sh
dossier-validate-patch.sh"

while IFS= read -r s; do
  [ -z "$s" ] && continue
  f="$BIN/$s"
  if [ -f "$f" ]; then
    _dossier_assert_pass "$s exists"
  else
    _dossier_assert_fail "$s missing"
    continue
  fi

  [ -x "$f" ] && _dossier_assert_pass "$s is executable" \
               || _dossier_assert_fail "$s is not executable"

  bash -n "$f" 2>/dev/null && _dossier_assert_pass "$s passes bash -n" \
                           || _dossier_assert_fail "$s has a syntax error"

  # A usage header is how a maintainer learns the interface without reading the
  # implementation. Searched across the whole leading comment block, since some
  # scripts carry a long design rationale before the interface.
  if head -60 "$f" | grep -qE '^# *Usage:'; then
    _dossier_assert_pass "$s has a usage header"
  else
    _dossier_assert_fail "$s has no '# Usage:' header"
  fi

  # set -u catches the unbound-variable class that silently produces empty
  # paths, which in a script that writes files is how you get surprises.
  if grep -qE '^set -[a-z]*u' "$f"; then
    _dossier_assert_pass "$s sets -u"
  else
    _dossier_assert_fail "$s does not set -u"
  fi

  # Portability: these scripts run on macOS bash 3.2 and ubuntu-latest bash 5.
  for construct in 'declare -A' 'readarray' 'mapfile'; do
    if grep -qF "$construct" "$f"; then
      _dossier_assert_fail "$s uses '$construct' which is unavailable on bash 3.2"
    else
      _dossier_assert_pass "$s avoids $construct"
    fi
  done
  # Comments are stripped first: a script explaining why it avoids ${var^^} is
  # doing the right thing, and flagging it would train people to delete the
  # explanation rather than keep the portability.
  if grep -v '^[[:space:]]*#' "$f" | grep -qE '\$\{[A-Za-z_][A-Za-z0-9_]*,,\}|\$\{[A-Za-z_][A-Za-z0-9_]*\^\^\}'; then
    _dossier_assert_fail "$s uses bash 4 case conversion"
  else
    _dossier_assert_pass "$s avoids bash 4 case conversion"
  fi
done <<EOF
$EXPECTED_SCRIPTS
EOF

# --- Usage errors exit 2, not 0 or 1 -----------------------------------------
for s in dossier-ledger-lint.sh dossier-claim-scan.sh dossier-gate.sh dossier-validate-config.sh; do
  "$BIN/$s" --nonexistent-flag >/dev/null 2>&1
  assert_equal "2" "$?" "$s exits 2 on an unknown flag"
done

# =============================================================================
# THE ANTI-THEATER ASSERTION
# =============================================================================
# Build a package that passes every mechanical check it can, then assert the
# gate still refuses to say PASS because no scorer verdict exists.

WORK=$(mktemp -d 2>/dev/null) || WORK="/tmp/dossier-gate-test.$$"
mkdir -p "$WORK" 2>/dev/null
REPO_ROOT=$(pwd)

(
  cd "$WORK" || exit 1
  mkdir -p docs/dossier/00-control docs/dossier/07-verification docs/dossier/04-operating

  printf '| Evidence ID | Claim |\n|---|---|\n' > docs/dossier/00-control/evidence-ledger.md
  printf 'not executed; inaccessible\n' >> docs/dossier/00-control/evidence-ledger.md
  printf '| ID |\n|---|\n| AQ-0001 | open |\n' > docs/dossier/00-control/assumptions-questions-and-contradictions.md
  printf '| ID |\n|---|\n' > docs/dossier/00-control/claim-and-disclosure-register.md
  printf '# Verification\n\nNo open findings.\n' > docs/dossier/07-verification/documentation-verification-report.md
  printf '# Onboarding\n\nverified on 2026-07-25\n' > docs/dossier/04-operating/onboarding-and-local-development.md
) 2>/dev/null

OUT=$(cd "$WORK" && "$REPO_ROOT/$BIN/dossier-gate.sh" --output-root docs/dossier 2>&1)
RC=$?

# Whatever the mechanical result, PASS is not reachable without a verdict.
assert_not_contains "GATE_RESULT=PASS" "$OUT" "gate never emits PASS without a scorer verdict"
assert_contains "SCORER_VERDICT_PRESENT=no" "$OUT" "gate reports the missing verdict explicitly"

if [ "$RC" -eq 0 ]; then
  _dossier_assert_fail "gate exited 0 (PASS) with no scorer verdict — the judgment set was never evaluated"
else
  _dossier_assert_pass "gate exit $RC is not PASS without a verdict"
fi

# G17 exists and is mechanical. The independence disclosure the protocol calls
# required was previously enforced by nothing, so a package could pass every
# other condition while omitting the sentence that says how much the
# verification is worth.
assert_contains "G17" "$OUT" "gate evaluates G17 (independence method disclosed)"

# Every judgment condition must be reported INCONCLUSIVE, not silently omitted.
for gid in G01 G02 G04 G07 G13 G14 G15; do
  if printf '%s' "$OUT" | grep -qE "^$gid .*(INCONCLUSIVE|FAIL)"; then
    _dossier_assert_pass "$gid is reported without a verdict file"
  else
    _dossier_assert_fail "$gid silently omitted when the verdict file is absent"
  fi
done

# --strict must not turn INCONCLUSIVE into success.
(cd "$WORK" && "$REPO_ROOT/$BIN/dossier-gate.sh" --output-root docs/dossier --strict --quiet >/dev/null 2>&1)
STRICT_RC=$?
if [ "$STRICT_RC" -eq 0 ]; then
  _dossier_assert_fail "--strict exited 0 with no scorer verdict"
else
  _dossier_assert_pass "--strict exit $STRICT_RC is non-zero without a verdict"
fi

# A verdict that is silent on a judgment condition must be rejected, not
# treated as assent.
mkdir -p "$WORK/.dossier/runs/r1" 2>/dev/null
printf '# Verdict\n\n| 1 | Evidence | 18 | 16 |\n\nG01 PASS\nG02 PASS\n' \
  > "$WORK/.dossier/runs/r1/scorer-verdict.md" 2>/dev/null
OUT2=$(cd "$WORK" && "$REPO_ROOT/$BIN/dossier-gate.sh" --output-root docs/dossier 2>&1)
assert_not_contains "GATE_RESULT=PASS" "$OUT2" "a verdict silent on G04/G07/G13-G15 does not yield PASS"
assert_contains "silent on" "$OUT2" "gate names the condition the verdict omitted"

rm -rf "$WORK" 2>/dev/null

# --- The runner owns the temp directory --------------------------------------
# Test files are *sourced*, so an EXIT trap set by one is replaced by the next
# file's, and a trailing cleanup line gets stranded above whatever the next
# contributor appends below it. Both happened in this suite. The runner creates
# one directory, points TMPDIR at it, and removes it — so cleanup no longer
# depends on every file remembering.
RUNNER="plugins/dossier/tests/run.sh"
assert_file_exists "$RUNNER" "runner exists"
if grep -q 'export TMPDIR=' "$RUNNER"; then
  _dossier_assert_pass "runner scopes TMPDIR to a directory it owns"
else
  _dossier_assert_fail "runner does not scope TMPDIR — every mktemp in the suite leaks"
fi
if grep -qE "^trap .*RUN_TMPDIR.* EXIT" "$RUNNER"; then
  _dossier_assert_pass "runner removes its temp directory on exit"
else
  _dossier_assert_fail "runner creates a temp directory it never removes"
fi

# A test file must not carry its own EXIT trap: sourced files share one trap
# slot, so the last one registered silently disables all the others.
TRAPPED=""
for tf in plugins/dossier/tests/*.test.sh; do
  grep -qE "^[[:space:]]*trap .* EXIT" "$tf" && TRAPPED="$TRAPPED $(basename "$tf")"
done
if [ -z "$TRAPPED" ]; then
  _dossier_assert_pass "no test file registers an EXIT trap the next file would replace"
else
  _dossier_assert_fail "EXIT trap(s) in sourced test file(s):$TRAPPED — only the last survives"
fi

# =============================================================================
# The output-root signpost
# =============================================================================
# The index is the control plane, but a reader who browses the output root lands
# on eight numbered directories and never reaches it. The scaffold writes a
# README that points there. It is supplemental, so the assertions below pin two
# things: that it appears, and that it never disturbs the canonical count.

README_TPL="plugins/dossier/templates/package-readme.md"
assert_file_exists "$README_TPL" "output-root README template exists"

# It asserts no fact, so it carries no evidence identifiers to leak or to rot.
if grep -qE '\b(EV|AQ|CT|CL|TM)-[0-9]{4}\b' "$README_TPL"; then
  _dossier_assert_fail "README template cites register identifiers — a signpost must assert nothing"
else
  _dossier_assert_pass "README template cites no register identifiers"
fi

if grep -qF '00-control/documentation-index.md' "$README_TPL"; then
  _dossier_assert_pass "README template routes to the index"
else
  _dossier_assert_fail "README template does not link the index — the signpost points nowhere"
fi

# The directory table is the one thing in the signpost that CAN drift: it names
# the canonical directories, and the scaffold owns that list. Compare the pair
# rather than restating either — the lesson from every finding in this suite
# where a constant silently disagreed with the artifact it described.
SCAFFOLD_DIRS=$(grep -m1 '^CANONICAL_DIRS=' "$BIN/dossier-scaffold.sh" \
  | sed 's/^CANONICAL_DIRS="//; s/"$//' | tr ' ' '\n' | grep . | sort)
README_DIRS=$(grep -oE '^\| `[0-9]{2}-[a-z-]+/`' "$README_TPL" \
  | tr -d '|` ' | sed 's|/$||' | sort)
if [ "$SCAFFOLD_DIRS" = "$README_DIRS" ]; then
  _dossier_assert_pass "README directory table matches the scaffold's canonical directories"
else
  _dossier_assert_fail "README table and scaffold directories differ: $(diff <(printf '%s\n' "$SCAFFOLD_DIRS") <(printf '%s\n' "$README_DIRS") | tr '\n' ' ')"
fi

SWORK=$(mktemp -d 2>/dev/null) || SWORK="/tmp/dossier-scaffold-test.$$"
mkdir -p "$SWORK" 2>/dev/null

SOUT=$("$BIN/dossier-scaffold.sh" --output-root "$SWORK/docs" 2>&1)
assert_contains "SCAFFOLD_README=created" "$SOUT" "scaffold reports the README as created"
assert_contains "SCAFFOLD_CREATED=23" "$SOUT" "the README does not inflate the canonical count"
assert_file_exists "$SWORK/docs/README.md" "README lands at the output root"

# Never overwritten, the same guarantee the canonical files carry. A signpost a
# maintainer has edited must survive the next scaffold.
printf 'hand-edited\n' > "$SWORK/docs/README.md"
SOUT2=$("$BIN/dossier-scaffold.sh" --output-root "$SWORK/docs" 2>&1)
assert_contains "SCAFFOLD_README=skipped" "$SOUT2" "an existing README is reported as skipped"
assert_equal "hand-edited" "$(cat "$SWORK/docs/README.md" 2>/dev/null)" \
  "an existing README is never overwritten"

# The supplement must not make the canonical package check see a 24th document.
PCOUT=$("$BIN/dossier-package-check.sh" --output-root "$SWORK/docs" --quiet 2>&1)
assert_contains "CHECK_FILES_PRESENT=23" "$PCOUT" \
  "package check still counts 23 canonical files with the README present"

# --- Diagram coverage --------------------------------------------------------
# A template that opens a mermaid fence is asking for a diagram. Counting the
# fences that exist grades the diagrams somebody drew and says nothing about the
# prompts they skipped — so the request is compared against the answer. A fresh
# scaffold carries the templates' own fences; the finding path is exercised by
# removing one.
assert_contains "CHECK_DIAGRAMS_EXPECTED=6" "$PCOUT" \
  "package check counts the diagrams the templates ask for"

DAI="$SWORK/docs/02-architecture/data-and-ai.md"
awk '/^```mermaid/ { skip = 1; next } skip && /^```/ { skip = 0; next } !skip' \
  "$DAI" > "$DAI.stripped" 2>/dev/null && mv "$DAI.stripped" "$DAI"
PCOUT2=$("$BIN/dossier-package-check.sh" --output-root "$SWORK/docs" 2>&1)
assert_contains "DIAGRAM_MISSING 02-architecture/data-and-ai.md" "$PCOUT2" \
  "a document shipped without the diagram its template asks for is a finding"
assert_contains "CHECK_DIAGRAMS_PRESENT=5" "$PCOUT2" \
  "the present-count moves with the document, not with the template"

# A missing template is a loud failure, not a silent omission — the failure mode
# every other check in this plugin was written to avoid.
SOUT3=$("$BIN/dossier-scaffold.sh" --output-root "$SWORK/other" \
  --readme-template "$SWORK/nonexistent.md" 2>&1)
SRC3=$?
assert_contains "SCAFFOLD_README=failed" "$SOUT3" "a missing README template is reported"
if [ "$SRC3" -eq 0 ]; then
  _dossier_assert_fail "scaffold exited 0 with the README template missing"
else
  _dossier_assert_pass "scaffold exit $SRC3 is non-zero with the README template missing"
fi

rm -rf "$SWORK" 2>/dev/null

_dossier_test_summary
