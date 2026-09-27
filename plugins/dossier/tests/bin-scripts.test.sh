#!/usr/bin/env bash
# Bin script hygiene, plus THE ANTI-THEATER ASSERTION.
#
# The gate's whole credibility rests on one property: it must not emit PASS from
# mechanical checks alone. Twelve mechanical conditions can prove a package is not
# releasable; they can never prove it is, because the judgment set includes the
# scorecard and three of the four "must never appear" rules. A gate that passed
# on mechanics would certify a package whose planned features are documented as
# shipped, having read none of it.

# Refuse to run without the shared library: its fixture guard is what keeps
# this file's git commands inside its own fixtures (issue #252).
declare -F _dossier_in_fixture >/dev/null 2>&1 || { echo "FATAL: ${BASH_SOURCE[0]##*/} must be run through plugins/dossier/tests/run.sh, which loads the fixture guard" >&2; exit 2; }

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
dossier-prose-lint.sh
dossier-resolve-config.sh
dossier-rotation-check.sh
dossier-scaffold.sh
dossier-scan-quality.sh
dossier-scan-security.sh
dossier-staleness-check.sh
dossier-validate-config.sh
dossier-validate-patch.sh
dossier-vuln-evidence.sh"

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
  if grep -v '^[[:space:]]*#' "$f" | grep -E '\$\{[A-Za-z_][A-Za-z0-9_]*,,\}|\$\{[A-Za-z_][A-Za-z0-9_]*\^\^\}' >/dev/null; then
    _dossier_assert_fail "$s uses bash 4 case conversion"
  else
    _dossier_assert_pass "$s avoids bash 4 case conversion"
  fi
done <<EOF
$EXPECTED_SCRIPTS
EOF

# --- Usage errors exit 2, not 0 or 1 -----------------------------------------
for s in dossier-ledger-lint.sh dossier-claim-scan.sh dossier-gate.sh dossier-validate-config.sh dossier-vuln-evidence.sh dossier-scan-security.sh dossier-scan-quality.sh; do
  "$BIN/$s" --nonexistent-flag >/dev/null 2>&1
  assert_equal "2" "$?" "$s exits 2 on an unknown flag"
done

# dossier-vuln-evidence.sh has three further usage-error paths beyond an
# unknown flag, none previously exercised anywhere in this suite: a value-
# taking flag given with nothing after it, and the required --scan flag
# omitted entirely. Each must exit 2 (a caller-error), never 0 or the 1 this
# script otherwise reserves for a scan-artifact parse/read failure.
"$BIN/dossier-vuln-evidence.sh" --scan >/dev/null 2>&1
assert_equal "2" "$?" "dossier-vuln-evidence.sh exits 2 when --scan is given with no path"
"$BIN/dossier-vuln-evidence.sh" --scan x.json --out >/dev/null 2>&1
assert_equal "2" "$?" "dossier-vuln-evidence.sh exits 2 when --out is given with no path"
"$BIN/dossier-vuln-evidence.sh" >/dev/null 2>&1
assert_equal "2" "$?" "dossier-vuln-evidence.sh exits 2 when the required --scan flag is omitted entirely"

"$BIN/dossier-scan-security.sh" --target >/dev/null 2>&1
assert_equal "2" "$?" "dossier-scan-security.sh exits 2 when --target is given with no path"
"$BIN/dossier-scan-security.sh" >/dev/null 2>&1
assert_equal "2" "$?" "dossier-scan-security.sh exits 2 when the required --target flag is omitted entirely"

"$BIN/dossier-scan-quality.sh" --target >/dev/null 2>&1
assert_equal "2" "$?" "dossier-scan-quality.sh exits 2 when --target is given with no path"
"$BIN/dossier-scan-quality.sh" >/dev/null 2>&1
assert_equal "2" "$?" "dossier-scan-quality.sh exits 2 when the required --target flag is omitted entirely"

# =============================================================================
# THE ANTI-THEATER ASSERTION
# =============================================================================
# Build a package that passes every mechanical check it can, then assert the
# gate still refuses to say PASS because no scorer verdict exists.

_dossier_require_mktemp_dir WORK "bin-scripts-work"
mkdir -p "$WORK" 2>/dev/null
REPO_ROOT=$(pwd)

(
  _dossier_in_fixture WORK || exit 1
  mkdir -p docs/dossier/00-control docs/dossier/07-verification docs/dossier/04-operating

  printf '| Evidence ID | Claim |\n|---|---|\n' > docs/dossier/00-control/evidence-ledger.md
  printf 'not executed; inaccessible\n' >> docs/dossier/00-control/evidence-ledger.md
  printf '| ID |\n|---|\n| AQ-0001 | open |\n' > docs/dossier/00-control/assumptions-questions-and-contradictions.md
  printf '| ID |\n|---|\n' > docs/dossier/00-control/claim-and-disclosure-register.md
  printf '# Verification\n\nNo open findings.\n' > docs/dossier/07-verification/documentation-verification-report.md
  printf '# Onboarding\n\nverified on 2026-07-25\n' > docs/dossier/04-operating/onboarding-and-local-development.md
) 2>/dev/null

OUT=$(_dossier_in_fixture WORK && "$REPO_ROOT/$BIN/dossier-gate.sh" --output-root docs/dossier 2>&1)
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
  if grep -qE "^$gid .*(INCONCLUSIVE|FAIL)" <<<"$OUT"; then
    _dossier_assert_pass "$gid is reported without a verdict file"
  else
    _dossier_assert_fail "$gid silently omitted when the verdict file is absent"
  fi
done

# --strict must not turn INCONCLUSIVE into success.
(_dossier_in_fixture WORK && "$REPO_ROOT/$BIN/dossier-gate.sh" --output-root docs/dossier --strict --quiet >/dev/null 2>&1)
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
OUT2=$(_dossier_in_fixture WORK && "$REPO_ROOT/$BIN/dossier-gate.sh" --output-root docs/dossier 2>&1)
assert_not_contains "GATE_RESULT=PASS" "$OUT2" "a verdict silent on G04/G07/G13-G15 does not yield PASS"
assert_contains "silent on" "$OUT2" "gate names the condition the verdict omitted"

rm -rf "$WORK" 2>/dev/null

# =============================================================================
# G18 fails safe when dossier-prose-lint.sh is missing
# =============================================================================
# Same shape as the G06/G08/G09 missing-dependency guards: a mechanical
# condition whose script is absent must FAIL, never PASS and never vanish from
# the report. G18 is a purely mechanical condition — it never reads the scorer
# verdict file — so it cannot inherit the dual-predicate bug class that lived
# in the judgment-verdict parsing loop; this test instead pins the one failure
# mode specific to G18's own design: a missing linter.
_dossier_require_mktemp_dir PLW "bin-scripts-plw"
cp -a "$BIN" "$PLW/bin"
rm -f "$PLW/bin/dossier-prose-lint.sh"
mkdir -p "$PLW/pkg/00-control" "$PLW/pkg/07-verification" "$PLW/pkg/04-operating"
printf '| Evidence ID | Claim |\n|---|---|\n' > "$PLW/pkg/00-control/evidence-ledger.md"
printf 'not executed; inaccessible\n' >> "$PLW/pkg/00-control/evidence-ledger.md"
printf '| ID |\n|---|\n| AQ-0001 | open |\n' > "$PLW/pkg/00-control/assumptions-questions-and-contradictions.md"
printf '| ID |\n|---|\n' > "$PLW/pkg/00-control/claim-and-disclosure-register.md"
printf '# Verification\n\nNo open findings.\n' > "$PLW/pkg/07-verification/documentation-verification-report.md"
printf '# Onboarding\n\nverified on 2026-07-25\n' > "$PLW/pkg/04-operating/onboarding-and-local-development.md"

PLOUT=$("$PLW/bin/dossier-gate.sh" --output-root "$PLW/pkg" 2>&1)
if grep -qE '^G18 +mechanical +FAIL' <<<"$PLOUT"; then
  _dossier_assert_pass "G18 fails when dossier-prose-lint.sh is missing"
else
  _dossier_assert_fail "G18 did not fail with dossier-prose-lint.sh missing"
fi
if grep -qE '^G18 .*PASS' <<<"$PLOUT"; then
  _dossier_assert_fail "G18 reported PASS with the linter missing"
else
  _dossier_assert_pass "G18 never reports PASS with the linter missing"
fi
assert_contains "missing" "$PLOUT" "G18's evidence names the missing script"
rm -rf "$PLW" 2>/dev/null

# G18 must read the JSON object's TOP-LEVEL blocking_violations, not the last
# file's — the object also carries one blocking_violations per entry in its
# files[] array, and an unanchored greedy sed match silently reads whichever
# occurrence sorts last, which in a real multi-document package is rarely the
# total. Reproduced here with a package where the LAST file by sort order is
# clean but an EARLIER file carries real violations.
_dossier_require_mktemp_dir PVW "bin-scripts-pvw"
mkdir -p "$PVW/pkg/00-control" "$PVW/pkg/07-verification" "$PVW/pkg/04-operating"
printf '| Evidence ID | Claim |\n|---|---|\n' > "$PVW/pkg/00-control/evidence-ledger.md"
printf '| ID |\n|---|\n| AQ-0001 | open |\n' > "$PVW/pkg/00-control/assumptions-questions-and-contradictions.md"
printf '| ID |\n|---|\n' > "$PVW/pkg/00-control/claim-and-disclosure-register.md"
printf '# Verification\n\nNo open findings.\n' > "$PVW/pkg/07-verification/documentation-verification-report.md"
# Sorts AFTER 04-operating's file and is deliberately clean, so a match on the
# last occurrence in the JSON (rather than the top-level total) would read 0.
printf '# Onboarding\n\nThis seamless, robust platform utilizes cutting-edge technology to reach out and unlock revolutionary capabilities.\n\nverified on 2026-07-25\n' > "$PVW/pkg/04-operating/onboarding-and-local-development.md"
PVOUT=$("$BIN/dossier-gate.sh" --output-root "$PVW/pkg" 2>&1)
if grep -qE '^G18 +mechanical +FAIL +script +[1-9][0-9]* hard-category' <<<"$PVOUT"; then
  _dossier_assert_pass "G18 reads the top-level violation total, not an arbitrary file's count"
else
  _dossier_assert_fail "G18 did not report the real nonzero violation total: $(printf '%s' "$PVOUT" | grep '^G18')"
fi
rm -rf "$PVW" 2>/dev/null

# =============================================================================
# --help renders the whole header, not a stale prefix of it
# =============================================================================
# `-h|--help` extracts its text with a hardcoded `sed -n '<start>,<end>p'`
# line range. Growing the header comment (as issue #178 did, adding the
# SCAFFOLD_REPAIRED docs) without updating that range truncates the output
# silently — no error, just a help text that stops mid-sentence and drops
# the Exit codes section. This pins the range against the actual header.
SCAFFOLD_HELP=$("$BIN/dossier-scaffold.sh" --help 2>&1)
assert_contains "Exit:" "$SCAFFOLD_HELP" "scaffold --help renders through the Exit codes section, not a stale truncated range"
assert_contains "SCAFFOLD_REPAIRED" "$SCAFFOLD_HELP" "scaffold --help documents the SCAFFOLD_REPAIRED output line"

# --- Same fix, sixteen more scripts (issue #206) -----------------------------
# `dossier-scaffold.sh` and `dossier-prose-lint.sh` were fixed first (issues
# #178/#180) by replacing the hardcoded `sed -n '2,Np'` range with a
# self-terminating `sed -n '2,/^$/p'` one that always reads to the header's
# first blank line. The other sixteen `bin/` scripts still carried the
# hardcoded-range bug at the time this was written. For each, this pins the
# header's actual LAST documented line — not an early one a stale-but-still-
# reaching bound would also pass — in that script's own `--help` output.
h206_line="" h206_script="" h206_needle="" h206_out=""
while IFS= read -r h206_line; do
  [ -z "$h206_line" ] && continue
  h206_script="${h206_line%% :: *}"
  h206_needle="${h206_line#* :: }"
  h206_out=$("$BIN/$h206_script" --help 2>&1)
  assert_contains "$h206_needle" "$h206_out" "$h206_script --help reaches its header's last documented line (issue #206)"
done <<'EOF'
dossier-blast-radius.sh :: #   2 — missing or invalid argument
dossier-claim-scan.sh :: # exit code (2 or 1) even on a truncated file.
dossier-evidence.sh :: #   2 — missing or invalid argument
dossier-gate.sh :: # Exit: 0 PASS · 1 FAIL · 2 usage error · 3 INCONCLUSIVE (--strict maps 3 -> 1)
dossier-ledger-lint.sh :: # Exit: 0 clean · 1 findings · 2 infrastructure error
dossier-managed-file.sh :: #   2 — missing or invalid argument
dossier-package-check.sh :: 2 — infrastructure error (missing argument, unreadable root or references)
dossier-policy.sh :: #   2 — missing or invalid argument
dossier-pr-body.sh :: #   2 — missing or invalid argument
dossier-rotation-check.sh :: #   2 — bad arguments
dossier-scan-quality.sh :: # test fixtures — not part of the dossier.* config surface).
dossier-scan-security.sh :: # test fixtures — not part of the dossier.* config surface).
dossier-staleness-check.sh :: #   2 — infrastructure error (missing prerequisite tool, bad argument)
dossier-validate-config.sh :: #   2 — infrastructure error (jq missing, config unreadable)
dossier-validate-patch.sh :: #   2 — missing or invalid argument
dossier-vuln-evidence.sh :: #       · 2 missing or invalid argument
EOF

# =============================================================================
# The output-root signpost
# =============================================================================
# The index is the control plane, but a reader who browses the output root lands
# on eight numbered directories and never reaches it. The scaffold writes a
# README that points there. It is supplemental, so the assertions below pin two
# things: that it appears, and that it never disturbs the canonical count.

README_TPL="plugins/dossier/templates/package-readme.md"
assert_file_exists "$README_TPL" "output-root README template exists"

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

_dossier_require_mktemp_dir SWORK "bin-scripts-swork"
mkdir -p "$SWORK" 2>/dev/null

SOUT=$("$BIN/dossier-scaffold.sh" --output-root "$SWORK/docs" 2>&1)
assert_contains "SCAFFOLD_README=created" "$SOUT" "scaffold reports the README as created"
assert_contains "SCAFFOLD_CREATED=23" "$SOUT" "the README does not inflate the canonical count"
assert_contains "SCAFFOLD_REPAIRED=0" "$SOUT" "a clean first scaffold repairs nothing (issue #178)"
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

# --- The gate cannot lose a judgment condition -------------------------------
# The anti-theater assertion above proves the gate will not PASS without a
# verdict. This proves the subtler thing: it will not pass *over* a condition.
#
# The silence check and the extraction used to run two different greps. The
# silence check demanded a PASS/FAIL token anywhere in the file; extraction took
# the first line merely naming the id. A verdict naming an id twice — a summary
# row with an empty Result cell, then a detail row carrying the real word —
# satisfied the first on line two and parsed line one. Neither token matched, so
# `record` was never called and the condition vanished from the output and from
# BOTH counters. Worse than silence: silence is at least counted inconclusive.
_dossier_require_mktemp_dir GW "bin-scripts-gw"
cp -a docs/dossier "$GW/pkg"
mkdir -p "$GW/.dossier/runs/r1"

verdict_rows() { # emit a full judgment set, overriding one id with $1/$2
  for g in G01 G02 G04 G07 G13 G14 G15; do
    if [ "$g" = "$1" ]; then printf '| %s | %s |\n' "$g" "$2"
    else                     printf '| %s | PASS |\n' "$g"
    fi
  done
}

# An id whose FIRST mention has an empty result and whose SECOND carries PASS.
{
  printf '# Scorer verdict\n\n'
  verdict_rows G04 ''
  printf '| 1 | 10 |\n'
  printf '\n## Appendix\n| G04 | PASS | detail row |\n'
} > "$GW/.dossier/runs/r1/scorer-verdict.md"

GOUT=$( _dossier_in_fixture GW && CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/dossier" \
  "$REPO_ROOT/plugins/dossier/bin/dossier-gate.sh" --output-root "$GW/pkg" 2>&1 )
GCOUNT=$(grep -cE '^G[0-9]+ ' <<<"$GOUT")
assert_equal "19" "$GCOUNT" "every one of the 19 conditions is reported, none dropped"
if grep -qE '^G04 ' <<<"$GOUT"; then
  _dossier_assert_pass "a condition named twice is still evaluated"
else
  _dossier_assert_fail "a condition named twice vanished from the results"
fi
# …and evaluated from the line that actually carries a verdict. The row-count
# guard below would catch a dropped condition and mark it INCONCLUSIVE, so
# presence alone does not prove extraction picked the right line — only the
# resulting PASS does. Without this the two guards mask each other and neither
# is pinned.
if grep -qE '^G04 +judgment +PASS' <<<"$GOUT"; then
  _dossier_assert_pass "the verdict is read from the line carrying PASS, not the empty one"
else
  _dossier_assert_fail "extraction read the empty row; G04 resolved to something other than PASS"
fi

# An id mentioned but never decided must be INCONCLUSIVE, never absent.
{
  printf '# Scorer verdict\n\n'
  verdict_rows G04 ''
  printf '| 1 | 10 |\n'
} > "$GW/.dossier/runs/r1/scorer-verdict.md"
GOUT2=$( _dossier_in_fixture GW && CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/dossier" \
  "$REPO_ROOT/plugins/dossier/bin/dossier-gate.sh" --output-root "$GW/pkg" 2>&1 )
assert_contains "G04" "$GOUT2" "an undecided condition still appears in the results"
if grep -qE '^G04 .*INCONCLUSIVE' <<<"$GOUT2"; then
  _dossier_assert_pass "an undecided condition is INCONCLUSIVE"
else
  _dossier_assert_fail "an undecided condition was not marked INCONCLUSIVE"
fi
if grep -q 'GATE_RESULT=PASS' <<<"$GOUT2"; then
  _dossier_assert_fail "the gate emitted PASS with a condition it never decided"
else
  _dossier_assert_pass "the gate refuses PASS with an undecided condition"
fi

# --- --round is implemented, and enforced ------------------------------------
# It was advertised in three commands' argument-hints and invoked verbatim in
# the documented Phase 2 command, while the parser rejected it outright.
ROUT=$( _dossier_in_fixture GW && CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/dossier" \
  "$REPO_ROOT/plugins/dossier/bin/dossier-gate.sh" --output-root "$GW/pkg" --round 1 2>&1 )
assert_not_contains "unknown argument" "$ROUT" "--round is accepted by the parser"
assert_contains "round 1" "$ROUT" "a verdict that does not name the round is refused"

rm -rf "$GW" 2>/dev/null

# --- The scaffold treats a truncated file as absent ---------------------------
# `-e` cannot tell a killed mid-write from a completed one, so the retry that
# exists to "fill only the gaps" reported SKIPPED and FAILED=0 over a package
# with an empty canonical file — a clean bill of health on a broken package.
_dossier_require_mktemp_dir SW "bin-scripts-sw"
"$BIN/dossier-scaffold.sh" --output-root "$SW/pkg" >/dev/null 2>&1
: > "$SW/pkg/00-control/evidence-ledger.md"
printf 'no frontmatter here\n' > "$SW/pkg/01-project/product-and-domain.md"
LEDGER_BYTES=$(wc -c < "$SW/pkg/00-control/evidence-ledger.md" | tr -d '[:space:]')
DOMAIN_BYTES=$(wc -c < "$SW/pkg/01-project/product-and-domain.md" | tr -d '[:space:]')
SOUT=$("$BIN/dossier-scaffold.sh" --output-root "$SW/pkg" 2>"$SW/stderr.log")
SERR=$(cat "$SW/stderr.log" 2>/dev/null)
assert_contains "REPAIRED 00-control/evidence-ledger.md" "$SOUT" "an empty canonical file is repaired, not skipped"
assert_contains "REPAIRED 01-project/product-and-domain.md" "$SOUT" "a headerless canonical file is repaired, not skipped"
if [ -s "$SW/pkg/00-control/evidence-ledger.md" ]; then
  _dossier_assert_pass "the repaired file has content"
else
  _dossier_assert_fail "the repaired file is still empty"
fi

# --- A repair is counted as REPAIRED, never also as CREATED (issue #178) ------
# The repair branch fell through into the same copy logic untouched files use,
# so a damaged file was reported REPAIRED *and* CREATED, and counted in
# SCAFFOLD_CREATED — indistinguishable from a clean first scaffold in the
# machine-readable summary.
assert_contains "SCAFFOLD_REPAIRED=2" "$SOUT" "both damaged files are counted in the new REPAIRED total"
assert_contains "SCAFFOLD_CREATED=0" "$SOUT" "repairs are excluded from CREATED — the other 21 files are already intact and report SKIPPED, not CREATED"
assert_not_contains "CREATED 00-control/evidence-ledger.md" "$SOUT" "a repaired file produces no CREATED line"
assert_not_contains "CREATED 01-project/product-and-domain.md" "$SOUT" "a repaired file produces no CREATED line"

# --- The repair path reports what it replaced, on stderr (issue #178) --------
# The overwrite was invisible: nothing on stderr said a file had content before
# it was destroyed. Two different byte counts (0 and a real one) rule out an
# implementation that reports a fixed placeholder instead of the true size —
# but only if path and count are checked together: an unscoped "0 bytes"
# substring check would also match inside "20 bytes", passing even if the
# ledger's own line reported the wrong count.
assert_contains "repairing 00-control/evidence-ledger.md (replacing $LEDGER_BYTES bytes)" "$SERR" "stderr reports the empty file's name and true byte count together"
assert_contains "repairing 01-project/product-and-domain.md (replacing $DOMAIN_BYTES bytes)" "$SERR" "stderr reports the headerless file's name and true byte count together"
rm -rf "$SW" 2>/dev/null

# --- A frontmatter-fenced canonical file is never touched by a repair (issue #178) ---
# The fix changes what happens after a file is judged damaged; it must not
# also change what happens to a file judged intact.
_dossier_require_mktemp_dir SK "bin-scripts-sk"
"$BIN/dossier-scaffold.sh" --output-root "$SK/pkg" >/dev/null 2>&1
BEFORE_CONTENT=$(cat "$SK/pkg/00-control/evidence-ledger.md" 2>/dev/null)
SOUT4=$("$BIN/dossier-scaffold.sh" --output-root "$SK/pkg" 2>&1)
AFTER_CONTENT=$(cat "$SK/pkg/00-control/evidence-ledger.md" 2>/dev/null)
assert_contains "SCAFFOLD_SKIPPED=23" "$SOUT4" "an already-intact package is fully skipped, nothing repaired"
assert_contains "SCAFFOLD_REPAIRED=0" "$SOUT4" "an intact frontmatter-fenced file is never counted as repaired"
assert_not_contains "REPAIRED 00-control/evidence-ledger.md" "$SOUT4" "an intact file produces no REPAIRED line"
assert_not_contains "CREATED 00-control/evidence-ledger.md" "$SOUT4" "an intact file produces no CREATED line"
assert_equal "$BEFORE_CONTENT" "$AFTER_CONTENT" "an intact canonical file is byte-identical after a second scaffold run"
rm -rf "$SK" 2>/dev/null

# --- --dry-run counts a repair without writing, and never claims present tense (issue #178) ---
# The repair branch's counters and stderr message are shared with the real
# run; --dry-run must report the same REPAIRED total without touching the
# file, and must not say "repairing" (present tense, implies it happened)
# about a file it left alone.
_dossier_require_mktemp_dir SD "bin-scripts-sd"
"$BIN/dossier-scaffold.sh" --output-root "$SD/pkg" >/dev/null 2>&1
: > "$SD/pkg/00-control/evidence-ledger.md"
DRY_BEFORE=$(wc -c < "$SD/pkg/00-control/evidence-ledger.md" | tr -d '[:space:]')
DOUT=$("$BIN/dossier-scaffold.sh" --output-root "$SD/pkg" --dry-run 2>"$SD/stderr.log")
DERR=$(cat "$SD/stderr.log" 2>/dev/null)
DRY_AFTER=$(wc -c < "$SD/pkg/00-control/evidence-ledger.md" | tr -d '[:space:]')
assert_contains "SCAFFOLD_REPAIRED=1" "$DOUT" "--dry-run still counts the damaged file as a would-be repair"
assert_not_contains "CREATED 00-control/evidence-ledger.md" "$DOUT" "--dry-run does not report a repair as a create"
assert_equal "$DRY_BEFORE" "$DRY_AFTER" "--dry-run never writes to the damaged file"
assert_contains "would repair 00-control/evidence-ledger.md" "$DERR" "--dry-run's stderr message is conditional, not a claim the write happened"
assert_not_contains "dossier-scaffold: repairing 00-control/evidence-ledger.md" "$DERR" "--dry-run never uses the present-tense repairing message"
rm -rf "$SD" 2>/dev/null

# --- A repair that fails to copy never also claims REPAIRED (issue #178) ----
# The REPAIRED action line was appended as soon as damage was detected, before
# the template lookup / copy that can still fail for the same path — so a
# failed repair produced both a false REPAIRED line and the correct FAILED
# line for the same file.
_dossier_require_mktemp_dir SF "bin-scripts-sf"
"$BIN/dossier-scaffold.sh" --output-root "$SF/pkg" >/dev/null 2>&1
: > "$SF/pkg/00-control/evidence-ledger.md"
_dossier_require_mktemp_dir BROKEN_TPL "bin-scripts-broken_tpl"
cp -a plugins/dossier/templates/package/. "$BROKEN_TPL/"
rm -f "$BROKEN_TPL/00-control/evidence-ledger.md"
FOUT=$("$BIN/dossier-scaffold.sh" --output-root "$SF/pkg" --templates "$BROKEN_TPL" 2>"$SF/stderr.log")
FERR=$(cat "$SF/stderr.log" 2>/dev/null)
assert_contains "FAILED  00-control/evidence-ledger.md (template missing" "$FOUT" "a repair whose template is missing is reported FAILED"
assert_not_contains "REPAIRED 00-control/evidence-ledger.md" "$FOUT" "a failed repair does not also claim REPAIRED for the same path"
assert_not_contains "repairing" "$FERR" "a failed repair attempt never announces on stderr — the message is deferred to confirmed success (issue #178)"
rm -rf "$SF" "$BROKEN_TPL" 2>/dev/null

# --- A symlink at a canonical path is never written through (issue #178) ----
# cp follows symlinks, so a "repair" or "create" at a canonical path could
# silently write outside $OUTPUT_ROOT through a link a poisoned source
# planted at a public, predictable canonical path. Live and dangling links
# are both refused, not followed — a dangling link fails -e (looks absent)
# but must still be caught, or it falls into the ordinary CREATE path.
_dossier_require_mktemp_dir SL "bin-scripts-sl"
OUTSIDE_LIVE="$SL/outside-live.txt"
printf 'do not touch me\n' > "$OUTSIDE_LIVE"
mkdir -p "$SL/pkg/00-control"
ln -s "$OUTSIDE_LIVE" "$SL/pkg/00-control/evidence-ledger.md"
LOUT=$("$BIN/dossier-scaffold.sh" --output-root "$SL/pkg" 2>/dev/null)
assert_contains "FAILED  00-control/evidence-ledger.md" "$LOUT" "a live symlink at a canonical path is refused, not repaired"
assert_not_contains "REPAIRED 00-control/evidence-ledger.md" "$LOUT" "a symlink is never reported REPAIRED"
assert_equal "do not touch me" "$(cat "$OUTSIDE_LIVE" 2>/dev/null)" "the symlink's target outside the package is never overwritten"

DANGLE_TARGET="$SL/outside-dangling.txt"
mkdir -p "$SL/pkg2/01-project"
ln -s "$DANGLE_TARGET" "$SL/pkg2/01-project/product-and-domain.md"
DOUT2=$("$BIN/dossier-scaffold.sh" --output-root "$SL/pkg2" 2>/dev/null)
assert_contains "FAILED  01-project/product-and-domain.md" "$DOUT2" "a dangling symlink at a canonical path is refused, not created-through"
assert_not_contains "CREATED 01-project/product-and-domain.md" "$DOUT2" "a dangling symlink is never reported CREATED"
if [ -e "$DANGLE_TARGET" ]; then
  _dossier_assert_fail "the dangling symlink's target was created outside the package"
else
  _dossier_assert_pass "the dangling symlink's target is never materialized outside the package"
fi

DANGLE_README="$SL/outside-readme.md"
mkdir -p "$SL/pkg3"
ln -s "$DANGLE_README" "$SL/pkg3/README.md"
ROUT2=$("$BIN/dossier-scaffold.sh" --output-root "$SL/pkg3" 2>/dev/null)
assert_contains "SCAFFOLD_README=failed" "$ROUT2" "a dangling symlink at the README path is refused, not created-through"
if [ -e "$DANGLE_README" ]; then
  _dossier_assert_fail "the README symlink's target was created outside the package"
else
  _dossier_assert_pass "the README symlink's target is never materialized outside the package"
fi
rm -rf "$SL" 2>/dev/null

# --- A non-regular file (e.g. a directory) at a canonical path is never
# --- treated as a damaged file to repair (issue #178) -----------------------
# -s is true for a directory too, so without a regular-file check a
# directory at a canonical path would be misclassified as "damaged" and the
# template copied INTO it, rather than the type mismatch being reported.
_dossier_require_mktemp_dir SDIR "bin-scripts-sdir"
mkdir -p "$SDIR/pkg/00-control/evidence-ledger.md"
DIROUT=$("$BIN/dossier-scaffold.sh" --output-root "$SDIR/pkg" 2>/dev/null)
assert_contains "FAILED  00-control/evidence-ledger.md" "$DIROUT" "a directory at a canonical path is reported FAILED, not repaired"
assert_not_contains "REPAIRED 00-control/evidence-ledger.md" "$DIROUT" "a directory is never reported REPAIRED"
if [ -d "$SDIR/pkg/00-control/evidence-ledger.md" ]; then
  _dossier_assert_pass "the directory at the canonical path is left alone, not copied into"
else
  _dossier_assert_fail "the directory at the canonical path was replaced or written into"
fi
rm -rf "$SDIR" 2>/dev/null

# --- A symlinked directory segment is refused, not just a symlinked leaf file
# --- (issue #178) -------------------------------------------------------------
# `mkdir -p` on a directory reached through a symlink succeeds silently
# (nothing new is created), and a leaf-only `-L "$DEST"` check inspects only
# the final path component — so a symlinked *directory* segment bypassed the
# leaf-level guard entirely, landing every file under it outside
# $OUTPUT_ROOT undetected. Both --dry-run and a real run must refuse it.
_dossier_require_mktemp_dir SDIRSYM "bin-scripts-sdirsym"
mkdir -p "$SDIRSYM/outside-dir" "$SDIRSYM/pkg"
ln -s "$SDIRSYM/outside-dir" "$SDIRSYM/pkg/00-control"
DSOUT=$("$BIN/dossier-scaffold.sh" --output-root "$SDIRSYM/pkg" 2>/dev/null)
assert_contains "FAILED  00-control/documentation-index.md" "$DSOUT" "a file under a symlinked directory segment is refused, not created-through"
assert_not_contains "CREATED 00-control/documentation-index.md" "$DSOUT" "a file under a symlinked directory segment is never reported CREATED"
if [ -e "$SDIRSYM/outside-dir/documentation-index.md" ]; then
  _dossier_assert_fail "the symlinked directory's outside target was written into"
else
  _dossier_assert_pass "the symlinked directory's outside target is never written into"
fi

_dossier_require_mktemp_dir DSDRY "bin-scripts-dsdry"
mkdir -p "$DSDRY/outside-dir2" "$DSDRY/pkg2"
ln -s "$DSDRY/outside-dir2" "$DSDRY/pkg2/00-control"
DSDRYOUT=$("$BIN/dossier-scaffold.sh" --output-root "$DSDRY/pkg2" --dry-run 2>/dev/null)
assert_contains "FAILED  00-control/documentation-index.md" "$DSDRYOUT" "--dry-run also refuses a file under a symlinked directory segment"
rm -rf "$SDIRSYM" "$DSDRY" 2>/dev/null

# --- Writes go through a temp file + atomic rename, so no temp files are ever
# --- left behind (issue #178) --------------------------------------------------
# Canonical files and the README are now written via a same-directory temp
# file plus an atomic rename rather than a direct cp onto the destination,
# so a rename() replaces whatever is at the destination outright (including
# a symlink planted there after the earlier -L check ran) instead of `cp`
# writing through it. A leaked *.dossier-scaffold.tmp.* file would mean the
# cleanup path never ran.
_dossier_require_mktemp_dir STMP "bin-scripts-stmp"
"$BIN/dossier-scaffold.sh" --output-root "$STMP/pkg" >/dev/null 2>&1
TMP_LEFTOVERS=$(find "$STMP/pkg" -name '*.dossier-scaffold.tmp.*' 2>/dev/null | wc -l | tr -d '[:space:]')
assert_equal "0" "$TMP_LEFTOVERS" "a successful scaffold leaves no .dossier-scaffold.tmp.* files behind"
rm -rf "$STMP" 2>/dev/null

_dossier_require_mktemp_dir SPERM "bin-scripts-sperm"
mkdir -p "$SPERM/pkg/00-control"
chmod 555 "$SPERM/pkg/00-control"
PERMOUT=$("$BIN/dossier-scaffold.sh" --output-root "$SPERM/pkg" 2>/dev/null)
chmod 755 "$SPERM/pkg/00-control"
assert_contains "FAILED  00-control/documentation-index.md (copy failed)" "$PERMOUT" "a write that cannot create its temp file is reported FAILED"
TMP_LEFTOVERS2=$(find "$SPERM/pkg" -name '*.dossier-scaffold.tmp.*' 2>/dev/null | wc -l | tr -d '[:space:]')
assert_equal "0" "$TMP_LEFTOVERS2" "a failed write leaves no .dossier-scaffold.tmp.* file behind"
rm -rf "$SPERM" 2>/dev/null

# --- A symlinked template source is never read through (issue #178) ---------
# `-f "$SRC"` follows a symlink, so a symlinked template would have its
# target's content silently copied into a canonical document — the read-side
# mirror of the write-side symlink guard on $DEST.
_dossier_require_mktemp_dir SSRC "bin-scripts-ssrc"
mkdir -p "$SSRC/templates"
cp -a plugins/dossier/templates/package/. "$SSRC/templates/"
OUTSIDE_TPL="$SSRC/outside-template.md"
printf 'attacker content\n' > "$OUTSIDE_TPL"
ln -sf "$OUTSIDE_TPL" "$SSRC/templates/00-control/documentation-index.md"
SRCOUT=$("$BIN/dossier-scaffold.sh" --output-root "$SSRC/pkg" --templates "$SSRC/templates" 2>/dev/null)
assert_contains "FAILED  00-control/documentation-index.md (refusing to read a symlinked template)" "$SRCOUT" "a symlinked template source is refused, not read through"
assert_not_contains "CREATED 00-control/documentation-index.md" "$SRCOUT" "a symlinked template source is never reported CREATED"
if [ -e "$SSRC/pkg/00-control/documentation-index.md" ]; then
  _dossier_assert_fail "content from the symlinked template was copied into the package"
else
  _dossier_assert_pass "no content from the symlinked template is copied into the package"
fi
rm -rf "$SSRC" 2>/dev/null

# --- A live symlink at the README path is refused, target untouched (issue #178) ---
# The dangling-symlink case was already tested; this pins the live-symlink
# case too, with content-preservation verification mirroring the canonical-
# file live-symlink test above.
_dossier_require_mktemp_dir SLR "bin-scripts-slr"
OUTSIDE_README_LIVE="$SLR/outside-readme-live.txt"
printf 'do not touch my readme either\n' > "$OUTSIDE_README_LIVE"
mkdir -p "$SLR/pkg"
ln -s "$OUTSIDE_README_LIVE" "$SLR/pkg/README.md"
LRO=$("$BIN/dossier-scaffold.sh" --output-root "$SLR/pkg" 2>/dev/null)
assert_contains "SCAFFOLD_README=failed" "$LRO" "a live symlink at the README path is refused, not written through"
assert_equal "do not touch my readme either" "$(cat "$OUTSIDE_README_LIVE" 2>/dev/null)" "the README symlink's live target outside the package is never overwritten"
rm -rf "$SLR" 2>/dev/null

# --- A directory at the README path is never treated as an intact README
# --- (issue #178) --------------------------------------------------------------
# -e is true for a directory too; without a regular-file check, a directory
# at the README path would be misreported SKIPPED — a clean bill of health
# with no README signpost actually present.
_dossier_require_mktemp_dir SRDIR "bin-scripts-srdir"
mkdir -p "$SRDIR/pkg/README.md"
RDIROUT=$("$BIN/dossier-scaffold.sh" --output-root "$SRDIR/pkg" 2>/dev/null)
assert_contains "SCAFFOLD_README=failed" "$RDIROUT" "a directory at the README path is reported failed, not skipped"
assert_contains "FAILED  README.md (not a regular file)" "$RDIROUT" "the README type-confusion failure is named in ACTIONS"
if [ -d "$SRDIR/pkg/README.md" ]; then
  _dossier_assert_pass "the directory at the README path is left alone"
else
  _dossier_assert_fail "the directory at the README path was replaced or written into"
fi
rm -rf "$SRDIR" 2>/dev/null

# --- Every README failure path is named in ACTIONS, matching every other
# --- FAILED path in the script (issue #178, closes #203) ----------------------
# The symlink, missing-template, and copy-failed README branches previously
# incremented SCAFFOLD_FAILED with no ACTIONS line and (for copy-failed) no
# stderr diagnostic either — unlike every other FAILED path in the script.
_dossier_require_mktemp_dir SRMISS "bin-scripts-srmiss"
MOUT=$("$BIN/dossier-scaffold.sh" --output-root "$SRMISS/pkg" --readme-template "$SRMISS/nonexistent.md" 2>/dev/null)
assert_contains "FAILED  README.md (template missing)" "$MOUT" "a missing README template is named in ACTIONS"
rm -rf "$SRMISS" 2>/dev/null

# A read-only $OUTPUT_ROOT would also fail the mkdir loop for the 8
# canonical directories, aborting before the README is ever reached — so
# the fixture scaffolds normally first (creating everything, including the
# 8 directories the mkdir loop no-ops on when they already exist), removes
# only the README, then locks the root down. The 23 canonical files stay
# SKIPPED (no write needed); only the missing README's temp-file create
# needs write access to the now-read-only root.
_dossier_require_mktemp_dir SRPERM "bin-scripts-srperm"
"$BIN/dossier-scaffold.sh" --output-root "$SRPERM/pkg" >/dev/null 2>&1
rm -f "$SRPERM/pkg/README.md"
chmod 555 "$SRPERM/pkg"
COUT=$("$BIN/dossier-scaffold.sh" --output-root "$SRPERM/pkg" 2>/dev/null)
chmod 755 "$SRPERM/pkg"
assert_contains "FAILED  README.md (copy failed)" "$COUT" "a README copy failure is named in ACTIONS"
rm -rf "$SRPERM" 2>/dev/null

# --- The CWD-relative template/README fallback is never trusted (issue #205) --
# When CLAUDE_PLUGIN_ROOT is unset and the script's own location cannot
# resolve a templates dir alongside it (e.g. it was invoked from a copy with
# no ../templates next to it — the shape a corrupted/partial install, or an
# unusual invocation, would produce), the scaffolder used to fall back to a
# bare CWD-relative "plugins/dossier/templates/..." path with no check that
# it actually belongs to the plugin's own install. The scaffolder's normal
# CWD is the project repository being documented — a repository this tool
# otherwise treats as untrusted input (see the symlink guards above, issue
# #178) — so a repo that happens to contain a tree at that exact path (by
# coincidence or by design) had its content silently substituted for the
# real plugin templates. Fixture: an isolated copy of the script (no
# sibling templates dir, so the $SCRIPT_DIR-relative candidate cannot
# resolve either) run with CLAUDE_PLUGIN_ROOT unset from a CWD that plants
# an unrelated plugins/dossier/templates/package tree at the predictable
# path.
_dossier_require_mktemp_dir SCWD "bin-scripts-scwd"
mkdir -p "$SCWD/isolated-bin"
cp "$BIN/dossier-scaffold.sh" "$SCWD/isolated-bin/dossier-scaffold.sh"
chmod +x "$SCWD/isolated-bin/dossier-scaffold.sh"
mkdir -p "$SCWD/attacker-repo/plugins/dossier/templates/package/00-control"
printf -- '---\nATTACKER CONTENT: should never be read\n' \
  > "$SCWD/attacker-repo/plugins/dossier/templates/package/00-control/documentation-index.md"
printf 'ATTACKER README CONTENT: should never be read\n' \
  > "$SCWD/attacker-repo/plugins/dossier/templates/package-readme.md"
CWDOUT=$(cd "$SCWD/attacker-repo" && env -u CLAUDE_PLUGIN_ROOT \
  "$SCWD/isolated-bin/dossier-scaffold.sh" --output-root "$SCWD/attacker-repo/out" 2>&1)
CWDRC=$?
assert_exit "2" "$CWDRC" "no CLAUDE_PLUGIN_ROOT + no resolvable \$SCRIPT_DIR templates + a CWD-local attacker tree fails closed, not silently succeeds (issue #205)"
assert_contains "template directory not found" "$CWDOUT" "the scaffolder reports the standard infra-error message rather than silently using CWD-local content"
assert_not_contains "ATTACKER CONTENT" "$CWDOUT" "attacker-controlled CWD-local template content never appears in scaffold output"
if [ -e "$SCWD/attacker-repo/out/00-control/documentation-index.md" ]; then
  CWDFILE=$(cat "$SCWD/attacker-repo/out/00-control/documentation-index.md" 2>/dev/null)
  assert_not_contains "ATTACKER CONTENT" "$CWDFILE" "no file in the scaffolded output was sourced from the CWD-local attacker tree"
else
  _dossier_assert_pass "no output file was created from the CWD-local attacker tree"
fi
rm -rf "$SCWD" 2>/dev/null

_dossier_test_summary
