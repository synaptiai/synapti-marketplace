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

rm -rf "$W" 2>/dev/null

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

_dossier_test_summary
