#!/usr/bin/env bash
# Evidence-ledger lint, driven by fixtures. Each case below is a way a ledger
# can look fine and be wrong; the lint exists because none of them are visible
# on a read-through of a hundred-row table.

_dossier_test_begin "ledger-lint"

LINT="$(pwd)/plugins/dossier/bin/dossier-ledger-lint.sh"
PLUGIN_ABS="$(pwd)/plugins/dossier"
HDR='| Evidence ID | Claim | State | Source ref | Retrievable | Authority | Version/env | Observed | Freshness | Confidentiality | Public use | Consuming docs | Notes |'
SEP='|---|---|---|---|---|---|---|---|---|---|---|---|---|'

mk() { # <workdir> — build a package skeleton with a ledger header
  mkdir -p "$1/docs/dossier/00-control" 2>/dev/null
  printf '%s\n%s\n' "$HDR" "$SEP" > "$1/docs/dossier/00-control/evidence-ledger.md"
}
row() { printf '%s\n' "$1" >> "$2/docs/dossier/00-control/evidence-ledger.md"; }
runlint() { (cd "$1" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" "$LINT" --output-root docs/dossier --quiet >/dev/null 2>&1); }
lintout() { (cd "$1" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" "$LINT" --output-root docs/dossier 2>&1); }

W=$(mktemp -d 2>/dev/null) || W="/tmp/dossier-ledger.$$"

# --- clean ledger passes -----------------------------------------------------
C="$W/clean"; mk "$C"
printf 'x\n' > "$C/real-source.ts"
row '| EV-0001 | The API requires a bearer token | V | real-source.ts::handler | yes | 2 | abc123 | 2026-07-25 | none | Internal | no | 02-architecture/interfaces-and-integrations.md | — |' "$C"
runlint "$C"
assert_equal "0" "$?" "a clean ledger passes"

# --- malformed ID ------------------------------------------------------------
B="$W/badid"; mk "$B"
row '| EV-1 | Something | V | x | yes | 2 | abc | 2026-07-25 | none | Internal | no | a.md | — |' "$B"
runlint "$B"
assert_equal "1" "$?" "an ID not matching EV-[0-9]{4,} fails"
assert_contains "does not match" "$(lintout "$B")" "the malformed ID is named"

# --- duplicate IDs -----------------------------------------------------------
# IDs are never reused, even for withdrawn rows: a reused ID silently
# re-points every citation that referenced the original claim.
D="$W/dupe"; mk "$D"
printf 'x\n' > "$D/f.ts"
row '| EV-0001 | First claim | V | f.ts | yes | 2 | abc | 2026-07-25 | none | Internal | no | a.md | — |' "$D"
row '| EV-0001 | Second claim | V | f.ts | yes | 2 | abc | 2026-07-25 | none | Internal | no | a.md | — |' "$D"
runlint "$D"
assert_equal "1" "$?" "a duplicate Evidence ID fails"
assert_contains "duplicate" "$(lintout "$D")" "the duplicate is named"

# --- invalid claim state -----------------------------------------------------
S="$W/badstate"; mk "$S"
printf 'x\n' > "$S/f.ts"
row '| EV-0001 | Claim | MAYBE | f.ts | yes | 2 | abc | 2026-07-25 | none | Internal | no | a.md | — |' "$S"
runlint "$S"
assert_equal "1" "$?" "an invalid claim state fails"

# --- dangling citation -------------------------------------------------------
# A citation with no row is the exact failure the ledger exists to prevent:
# prose that looks sourced and is not.
G="$W/dangling"; mk "$G"
printf 'x\n' > "$G/f.ts"
row '| EV-0001 | Claim | V | f.ts | yes | 2 | abc | 2026-07-25 | none | Internal | no | a.md | — |' "$G"
mkdir -p "$G/docs/dossier/02-architecture" 2>/dev/null
printf 'Deployments are blue-green. [EV-9999]\n' > "$G/docs/dossier/02-architecture/system-architecture.md"
runlint "$G"
assert_equal "1" "$?" "a dangling [EV-####] citation fails"
assert_contains "EV-9999" "$(lintout "$G")" "the dangling citation is named"

# --- retrievability coherence ------------------------------------------------
# Authority 1-3 are sources inside the inspection boundary. Retrievable=no
# there means either the locator is wrong or the level is inflated.
R="$W/retr"; mk "$R"
row '| EV-0001 | Claim | V | somewhere | no | 2 | abc | 2026-07-25 | none | Internal | no | a.md | — |' "$R"
runlint "$R"
assert_equal "1" "$?" "Retrievable=no at authority 2 fails"
assert_contains "inflated" "$(lintout "$R")" "the finding explains the contradiction"

# Authority 4-7 legitimately point outside the boundary, but must say what a
# reader would need.
R2="$W/retr2"; mk "$R2"
row '| EV-0001 | Claim | R | interview:SRE lead, 2026-07-20 | no | 6 | unknown | 2026-07-25 | none | Internal | no | a.md | — |' "$R2"
runlint "$R2"
assert_equal "1" "$?" "Retrievable=no at authority 6 with an empty Notes cell fails"

R3="$W/retr3"; mk "$R3"
row '| EV-0001 | Claim | R | interview:SRE lead, 2026-07-20 | no | 6 | unknown | 2026-07-25 | none | Internal | no | a.md | requires re-confirmation with the current on-call owner |' "$R3"
runlint "$R3"
assert_equal "0" "$?" "Retrievable=no at authority 6 with an explanatory Notes cell passes"

# --- locator resolution, levels 1-3 only -------------------------------------
L="$W/locator"; mk "$L"
row '| EV-0001 | Claim | V | src/does-not-exist.ts::sym | yes | 2 | abc | 2026-07-25 | none | Internal | no | a.md | — |' "$L"
runlint "$L"
assert_equal "1" "$?" "an unresolvable locator at authority 2 fails"

L2="$W/locator2"; mk "$L2"
row '| EV-0001 | Claim | R | contract:AcmeCorp MSA section 7.2 | no | 4 | unknown | 2026-07-25 | none | Internal | no | a.md | requires access to the contracts drive |' "$L2"
runlint "$L2"
assert_equal "0" "$?" "a contract locator at authority 4 is not resolution-checked"

# --- public use gating -------------------------------------------------------
# Only V and C may go public. An R or I row marked public is the single most
# consequential ledger error.
P="$W/public"; mk "$P"
printf 'x\n' > "$P/f.ts"
row '| EV-0001 | Claim | R | f.ts | yes | 2 | abc | 2026-07-25 | none | Public | yes | 06-public/x.md | — |' "$P"
runlint "$P"
assert_equal "1" "$?" "Public use=yes on a Reported claim fails"
assert_contains "only V and C" "$(lintout "$P")" "the finding states the rule"

# --- orphan rows warn, do not fail -------------------------------------------
# An unconsumed V row is often just a claim nothing needed yet.
O="$W/orphan"; mk "$O"
printf 'x\n' > "$O/f.ts"
row '| EV-0001 | Claim | V | f.ts | yes | 2 | abc | 2026-07-25 | none | Internal | no |  | — |' "$O"
runlint "$O"
assert_equal "0" "$?" "an orphan row warns rather than failing"
assert_contains "no consuming document" "$(lintout "$O")" "the orphan is reported"

# --- wrong column count ------------------------------------------------------
X="$W/cols"; mk "$X"
row '| EV-0001 | Claim | V | f.ts |' "$X"
runlint "$X"
assert_equal "1" "$?" "a row with the wrong column count fails"

# --- missing ledger is infrastructure, not a finding -------------------------
M="$W/missing"; mkdir -p "$M/docs/dossier" 2>/dev/null
runlint "$M"
assert_equal "2" "$?" "a missing ledger exits 2 (infrastructure), not 1"

# --- JSON output parses ------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  J=$(cd "$C" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" "$LINT" --output-root docs/dossier --json 2>/dev/null)
  if printf '%s' "$J" | jq -e . >/dev/null 2>&1; then
    _dossier_assert_pass "--json emits valid JSON"
  else
    _dossier_assert_fail "--json output is not valid JSON"
  fi
fi

rm -rf "$W" 2>/dev/null

# --- Locators are written as code spans --------------------------------------
# `references/evidence-ledger-schema.md` writes every one of its own Source ref
# examples inside backticks, so a drafter copying the documented form produced a
# cell the linter compared against the filesystem verbatim, and every authority
# 1-3 row failed. The reference and the tool have to agree on one form.
B="$W/backtick"; mk "$B"; printf 'x\n' > "$B/real-source.ts"
row '| EV-0001 | The handler validates the token | V | `real-source.ts` | yes | 2 | abc123 | 2026-07-25 | none | Internal | no | 02-architecture/interfaces-and-integrations.md | — |' "$B"
assert_contains "LEDGER_ERRORS=0" "$(lintout "$B")" "a backticked path locator resolves"

# Several spans in one cell are several locators, and all must resolve.
M="$W/multi"; mk "$M"; printf 'x\n' > "$M/a.ts"; printf 'y\n' > "$M/b.ts"
row '| EV-0001 | Two sources agree | C | `a.ts`, `b.ts` | yes | 2 | abc123 | 2026-07-25 | none | Internal | no | 02-architecture/interfaces-and-integrations.md | — |' "$M"
assert_contains "LEDGER_ERRORS=0" "$(lintout "$M")" "every span in a multi-locator cell is resolved"

MB="$W/multibad"; mk "$MB"; printf 'x\n' > "$MB/a.ts"
row '| EV-0001 | One source is missing | C | `a.ts`, `no/such/file.ts` | yes | 2 | abc123 | 2026-07-25 | none | Internal | no | 02-architecture/interfaces-and-integrations.md | — |' "$MB"
OUT=$(lintout "$MB")
assert_not_contains "LEDGER_ERRORS=0" "$OUT" "an unresolvable span in a multi-locator cell is an error"

# The counter must move with the findings. Iterating locators through a pipe put
# `emit` in a subshell, which printed findings under LEDGER_ERRORS=0 — a linter
# reporting problems and simultaneously reporting none.
if printf '%s' "$OUT" | grep -q '\[error\]'; then
  N=$(printf '%s' "$OUT" | sed -nE 's/^LEDGER_ERRORS=([0-9]+)$/\1/p')
  if [ "${N:-0}" -ge 1 ]; then
    _dossier_assert_pass "the error count moves with the findings it prints"
  else
    _dossier_assert_fail "findings printed while LEDGER_ERRORS=$N — the counter is in a subshell"
  fi
else
  _dossier_assert_fail "expected an error finding for the unresolvable locator"
fi

# A row supported by other ledger rows needs a locator form of its own.
D="$W/derived"; mk "$D"; printf 'x\n' > "$D/a.ts"
row '| EV-0001 | This follows from the two rows below | V | `derived: EV-0002 + EV-0003` | yes | 1 | abc123 | 2026-07-25 | none | Internal | no | 02-architecture/interfaces-and-integrations.md | — |' "$D"
row '| EV-0002 | A directly observed fact | V | `a.ts` | yes | 2 | abc123 | 2026-07-25 | none | Internal | no | 02-architecture/interfaces-and-integrations.md | — |' "$D"
row '| EV-0003 | Another directly observed fact | V | `a.ts` | yes | 2 | abc123 | 2026-07-25 | none | Internal | no | 02-architecture/interfaces-and-integrations.md | — |' "$D"
assert_contains "LEDGER_ERRORS=0" "$(lintout "$D")" "derived: is a recognized non-path locator form"

_dossier_test_summary
