#!/usr/bin/env bash
# Disclosure safety: the scan that stands between an internal truth and an
# unretractable public claim. Exit 2 means leakage and is never advisory.

_dossier_test_begin "disclosure-gate"

SCAN="$(pwd)/plugins/dossier/bin/dossier-claim-scan.sh"
PLUGIN_ABS="$(pwd)/plugins/dossier"

W=$(mktemp -d 2>/dev/null) || W="/tmp/dossier-disclosure.$$"

mkpkg() { mkdir -p "$1/docs/dossier/06-public" "$1/docs/dossier/00-control" 2>/dev/null; }
pub() { printf '%s\n' "$2" > "$1/docs/dossier/06-public/technical-partner-guide.md"; }
scan() { (cd "$1" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" "$SCAN" --output-root docs/dossier --quiet >/dev/null 2>&1); }
scanout() { (cd "$1" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" "$SCAN" --output-root docs/dossier 2>&1); }

reg() { # workdir | rows
  printf '| ID | Proposed wording | Claim type | Evidence | Applicable version | Scope | Limitations | Approver | Classification | Destination | Status | Decision basis |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n%s\n' \
    "$2" > "$1/docs/dossier/00-control/claim-and-disclosure-register.md"
}

# --- credentials are blocked outright ----------------------------------------
for pair in \
  "anthropic:sk-ant-api03-abcdefghijklmnop" \
  "github:ghp_abcdefghijklmnopqrstuvwxyz012345" \
  "aws:AKIAIOSFODNN7EXAMPLE" \
  "slack:xoxb-123456789012-abcdefghijkl"
do
  label=${pair%%:*}; secret=${pair#*:}
  T="$W/cred-$label"; mkpkg "$T"
  pub "$T" "Authenticate with $secret to begin."
  scan "$T"
  assert_equal "2" "$?" "leakage exit 2 for a $label credential"
  OUT=$(scanout "$T")
  assert_not_contains "$secret" "$OUT" "$label: the matched value is never printed"
done

# --- private key block -------------------------------------------------------
T="$W/pk"; mkpkg "$T"
pub "$T" "-----BEGIN RSA PRIVATE KEY-----"
scan "$T"
assert_equal "2" "$?" "leakage exit 2 for a private key block"

# --- internal locators -------------------------------------------------------
T="$W/evid"; mkpkg "$T"
pub "$T" "The gateway validates every request. See EV-0042 for the supporting evidence."
scan "$T"
assert_equal "2" "$?" "leakage exit 2 for an internal evidence ID"

T="$W/host"; mkpkg "$T"
pub "$T" "Requests route through gateway.internal before reaching the service."
scan "$T"
assert_equal "2" "$?" "leakage exit 2 for an internal hostname"

T="$W/ip"; mkpkg "$T"
pub "$T" "The service listens on 10.0.4.12 within the cluster."
scan "$T"
assert_equal "2" "$?" "leakage exit 2 for a private IP"

T="$W/path"; mkpkg "$T"
pub "$T" "The handler lives in src/api/gateway/auth.ts and validates tokens."
scan "$T"
assert_equal "2" "$?" "leakage exit 2 for an internal repository path"

# --- connection strings ------------------------------------------------------
T="$W/conn"; mkpkg "$T"
pub "$T" "Connect with postgres://admin:hunter2@db.example.com:5432/main to begin."
scan "$T"
assert_equal "2" "$?" "leakage exit 2 for a connection string with credentials"

# --- prohibited vocabulary is a finding, not leakage -------------------------
# Each of these is a claim requiring defined scope and evidence. They block the
# gate (exit 1) but are not a disclosure emergency (exit 2).
T="$W/vocab"; mkpkg "$T"
reg "$T" '| CL-0001 | our platform has never been compromised | security | EV-0001 | 1.0 | all | none | Head of Security | Public | 06-public/technical-partner-guide.md | approved | verified |'
pub "$T" "Our platform has never been compromised."
scan "$T"
RC=$?
if [ "$RC" -eq 1 ] || [ "$RC" -eq 2 ]; then
  _dossier_assert_pass "prohibited vocabulary is flagged (exit $RC)"
else
  _dossier_assert_fail "prohibited vocabulary passed silently (exit $RC)"
fi
assert_contains "VOCABULARY" "$(scanout "$T")" "the vocabulary finding is labelled"

# --- registration ------------------------------------------------------------
# An approved row whose wording matches exactly.
T="$W/registered"; mkpkg "$T"
reg "$T" '| CL-0001 | the api supports oauth 20 device flow | capability | EV-0001 | 1.0 | all | none | VP Eng | Public | 06-public/technical-partner-guide.md | approved | verified |'
pub "$T" "The API supports OAuth 20 device flow."
scan "$T"
assert_equal "0" "$?" "an exactly-registered approved sentence passes"

# The same sentence with no register row must be reported.
T="$W/unregistered"; mkpkg "$T"
reg "$T" ''
pub "$T" "The API supports OAuth 20 device flow."
scan "$T"
assert_equal "1" "$?" "an unregistered public sentence exits 1"
assert_contains "UNREGISTERED" "$(scanout "$T")" "the unregistered sentence is labelled"

# A pending row is not an approved row.
T="$W/pending"; mkpkg "$T"
reg "$T" '| CL-0001 | the api supports oauth 20 device flow | capability | EV-0001 | 1.0 | all | none |  | Public | 06-public/technical-partner-guide.md | pending | verified |'
pub "$T" "The API supports OAuth 20 device flow."
scan "$T"
assert_equal "1" "$?" "a pending claim does not count as registered"

# --- no register at all ------------------------------------------------------
T="$W/noreg"; mkpkg "$T"
pub "$T" "The service handles multi-region failover automatically."
OUT=$(scanout "$T")
assert_contains "no claim register" "$OUT" "a missing register is called out explicitly"

# --- headings, code fences, and tables are not claims ------------------------
# Flagging them would drown the real findings.
T="$W/structure"; mkpkg "$T"
reg "$T" ''
{
  printf '# Partner Guide\n\n'
  printf '## Getting started\n\n'
  printf '| Field | Value |\n|---|---|\n| Region | eu-west-1 |\n\n'
  printf '```bash\ncurl https://api.example.com/v1/ping\n```\n'
} > "$T/docs/dossier/06-public/technical-partner-guide.md"
scan "$T"
assert_equal "0" "$?" "headings, tables, and code fences are not treated as claims"

# --- single-file mode --------------------------------------------------------
T="$W/single"; mkpkg "$T"
pub "$T" "Use sk-ant-api03-zzzzzzzzzzzzzzzz for access."
(cd "$T" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" "$SCAN" --file docs/dossier/06-public/technical-partner-guide.md --quiet >/dev/null 2>&1)
assert_equal "2" "$?" "--file mode detects leakage in one file"

# --- JSON output -------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  J=$(cd "$T" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" "$SCAN" --output-root docs/dossier --json 2>/dev/null)
  if printf '%s' "$J" | jq -e . >/dev/null 2>&1; then
    _dossier_assert_pass "--json emits valid JSON"
    assert_not_contains "sk-ant-api03-zzzzzzzzzzzzzzzz" "$J" "--json never carries the matched value"
  else
    _dossier_assert_fail "--json output is not valid JSON"
  fi
fi

# --- missing public directory is infrastructure ------------------------------
T="$W/nopub"; mkdir -p "$T/docs/dossier" 2>/dev/null
scan "$T"
assert_equal "2" "$?" "a missing public directory exits 2"

# --- the header is metadata, not prose ---------------------------------------
# `title:` and `audience:` clear the four-word floor and match no approved
# wording, so scanning the header reports unregistered "sentences" that no
# drafter can resolve — noise that trains a reader to skip the real findings.
T="$W/header"; mkdir -p "$T/docs/dossier/06-public" 2>/dev/null
printf -- '---\ndossier-header: public-v1\ntitle: A Guide For Evaluating Partners\naudience: Partners and integrators evaluating the product\nproduct-version: abc1234\nlast-updated: 2026-07-26\n---\n# A Guide For Evaluating Partners\n' \
  > "$T/docs/dossier/06-public/g.md" 2>/dev/null
OUT=$(scanout "$T")
assert_contains "CLAIM_SCAN_UNREGISTERED_SENTENCES=0" "$OUT" \
  "header fields are not reported as unregistered claims"

# The same document with one unregistered body sentence must still report it,
# so the skip above cannot be widened into skipping the document.
printf -- '\nThe product supports every integration pattern a partner needs.\n' \
  >> "$T/docs/dossier/06-public/g.md" 2>/dev/null
OUT=$(scanout "$T")
assert_contains "CLAIM_SCAN_UNREGISTERED_SENTENCES=1" "$OUT" \
  "an unregistered body sentence is still reported after the header skip"

# A document that does not open with a header fence must be scanned in full.
T="$W/noheader"; mkdir -p "$T/docs/dossier/06-public" 2>/dev/null
printf -- '# Guide\n\nThe product supports every integration pattern a partner needs.\n' \
  > "$T/docs/dossier/06-public/g.md" 2>/dev/null
OUT=$(scanout "$T")
assert_contains "CLAIM_SCAN_UNREGISTERED_SENTENCES=1" "$OUT" \
  "a headerless document is scanned from its first line"


# --- An approved wording containing markdown must be matchable ---------------
# Document sentences are normalized (code spans, emphasis, and links stripped)
# before comparison. Lowercasing the register row without normalizing it left the
# markdown in place on one side only, so any claim containing a code span could
# never match its own approved row — the check could not pass for a realistic
# claim, and every such sentence was reported as unregistered.
T="$W/md-claim"; mkpkg "$T"
reg "$T" '| CL-0001 | The only declared dependency is `pyyaml`, required by one plugin. | capability | EV-0001 | 1.0 | all | none | VP Eng | Public | 06-public/technical-partner-guide.md | approved | verified |'
pub "$T" 'The only declared dependency is `pyyaml`, required by one plugin.'
scan "$T"
assert_equal "0" "$?" "an approved wording containing a code span matches its document sentence"

# Emphasis on one side only must not defeat the match either.
T="$W/md-emph"; mkpkg "$T"
reg "$T" '| CL-0001 | Hooks execute without you invoking them. | security | EV-0001 | 1.0 | all | none | VP Eng | Public | 06-public/technical-partner-guide.md | approved | verified |'
pub "$T" '**Hooks execute without you invoking them.**'
scan "$T"
assert_equal "0" "$?" "emphasis in the document does not defeat the match"

# --- A period inside a code span is not a sentence boundary ------------------
# `tr '.' '\n'` cuts inside SKILL.md, plugin.json, and 3.2.2, producing fragments
# like "md is not a skill" that are reported as unregistered claims no drafter
# can resolve, because they are not sentences.
T="$W/dotted"; mkpkg "$T"
reg "$T" '| CL-0001 | A directory without a `SKILL.md` is not a skill. | capability | EV-0001 | 1.0 | all | none | VP Eng | Public | 06-public/technical-partner-guide.md | approved | verified |'
pub "$T" 'A directory without a `SKILL.md` is not a skill.'
scan "$T"
assert_equal "0" "$?" "a filename inside a code span is not split into fragments"

OUT=$(scanout "$T")
assert_not_contains "md is not a skill" "$OUT" "no fragment is reported from a split filename"

# The split must still happen at real sentence boundaries.
T="$W/twosent"; mkpkg "$T"
reg "$T" '| CL-0001 | The first claim is registered. | capability | EV-0001 | 1.0 | all | none | VP Eng | Public | 06-public/technical-partner-guide.md | approved | verified |'
pub "$T" 'The first claim is registered. The second claim is not registered anywhere.'
scan "$T"
assert_equal "1" "$?" "a second unregistered sentence on the same line is still found"

# --- A required qualification is approved text ------------------------------
# The contract mandates that a qualification appear in the public document beside
# the claim it qualifies. Qualification rows carry no `approved` cell of their
# own, so matching only claim rows made every mandated qualification an
# unregistered sentence: the register required a sentence the scan then reported.
T="$W/qualification"; mkpkg "$T"
{
  printf '| ID | Proposed wording | Claim type | Evidence | Applicable version | Scope | Limitations | Approver | Classification | Destination | Status | Decision basis |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|---|---|\n'
  printf '| CL-0001 | The scan found no credential in any tracked file. | security | EV-0001 | 1.0 | all | qualified | VP Eng | Public | 06-public/technical-partner-guide.md | approved | verified |\n'
  printf '\n## Required qualifications\n\n'
  printf '| Claim ID | Qualification that must accompany it | Where it appears |\n|---|---|---|\n'
  printf '| CL-0001 | The scan covers an enumerated pattern set and proves only that none of those formats appears. | adjacent to the claim |\n'
} > "$T/docs/dossier/00-control/claim-and-disclosure-register.md"
pub "$T" 'The scan found no credential in any tracked file. The scan covers an enumerated pattern set and proves only that none of those formats appears.'
scan "$T"
assert_equal "0" "$?" "a mandated qualification is treated as approved text"

# The qualifications table must not become a way to approve arbitrary prose:
# only rows inside that section count, and only its qualification column.
T="$W/qual-scope"; mkpkg "$T"
{
  printf '| ID | Proposed wording | Claim type | Evidence | Applicable version | Scope | Limitations | Approver | Classification | Destination | Status | Decision basis |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|---|---|\n'
  printf '| CL-0001 | The scan found no credential in any tracked file. | security | EV-0001 | 1.0 | all | none | VP Eng | Public | 06-public/technical-partner-guide.md | approved | verified |\n'
  printf '\n## Required qualifications\n\n'
  printf '| Claim ID | Qualification that must accompany it | Where it appears |\n|---|---|---|\n'
  printf '| CL-0001 | A qualification that is genuinely required here. | adjacent to the claim |\n'
  printf '\n## Rejected and withdrawn claims\n\n'
  printf '| CL-R01 | This rejected wording must never count as approved. | reason | 2026-07-26 | nothing |\n'
} > "$T/docs/dossier/00-control/claim-and-disclosure-register.md"
pub "$T" 'This rejected wording must never count as approved.'
scan "$T"
assert_equal "1" "$?" "a rejected wording is not approved by sitting in a later table"

rm -rf "$W" 2>/dev/null

# --- The redactor runs before the lowercasing, not after ----------------------
# `normalize` folds case, and two credential patterns are case-sensitive by
# construction: `AKIA[0-9A-Z]{16}` and the PEM armour. Redacting after
# normalizing meant those two classes printed into the findings excerpt
# verbatim-but-lowercased — recognisable, reconstructable, and bound for a CI
# log. That is precisely what the redactor exists to prevent, so each class is
# checked against the real output rather than against the pattern list.
T="$W/redact"; mkpkg "$T"
pub "$T" "The staging key AKIAIOSFODNN7EXAMPLE was rotated by the team last week."
OUT=$(scanout "$T")
assert_not_contains "AKIAIOSFODNN7EXAMPLE" "$OUT" "an AWS key never reaches the findings output"
assert_not_contains "akiaiosfodnn7example" "$OUT" "nor does its lowercased form"
assert_contains "aws-access-key" "$OUT" "the class is named instead"

T="$W/redact-pem"; mkpkg "$T"
pub "$T" "Our certificate begins with -----BEGIN RSA PRIVATE KEY----- and continues onward."
OUT=$(scanout "$T")
assert_not_contains "BEGIN RSA PRIVATE KEY" "$OUT" "a PEM header never reaches the findings output"
assert_not_contains "begin rsa private key" "$OUT" "nor does its lowercased form"

T="$W/redact-ant"; mkpkg "$T"
pub "$T" "The token sk-ant-abcdefgh12345678 is stored in the vault for safekeeping."
OUT=$(scanout "$T")
assert_not_contains "sk-ant-abcdefgh12345678" "$OUT" "an anthropic key never reaches the findings output"

# --- A rejected row must not be read as an approved claim ---------------------
# `CL-` rows appear in two tables with different column layouts, and the
# approval test is a literal substring match. A rejected row whose free-text
# cell happens to contain the approved marker would otherwise be honoured.
T="$W/rejected"; mkpkg "$T"
cat >> "$T/00-control/claim-and-disclosure-register.md" <<'REGEOF'

## Rejected and withdrawn claims

| ID | Wording | Reason declined | Date | What would make it publishable |
|---|---|---|---|---|
| CL-9001 | our service is completely secure | the reviewer noted this was not "| approved |" by security | 2026-07-26 | evidence |
REGEOF
pub "$T" "Our service is completely secure."
scan "$T"
RC=$?
if [ "$RC" -eq 0 ]; then
  _dossier_assert_fail "a rejected row was honoured as an approved claim"
else
  _dossier_assert_pass "a rejected row is not honoured as an approved claim (exit $RC)"
fi

_dossier_test_summary
