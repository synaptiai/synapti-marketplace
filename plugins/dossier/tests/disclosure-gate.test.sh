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

# Prohibited vocabulary is prose a drafter capitalizes without thinking about
# it — a heading, a bolded lead sentence, title case in a bullet. The pattern
# list is written in all-lowercase; matching only the exact case lets "Zero
# Downtime" or "Bank-Grade" through a check whose entire purpose is to catch
# this vocabulary regardless of how it's cased (self-review finding, issue
# #176 PR — pre-existing, found incidentally while reviewing this file).
T="$W/vocab-case"; mkpkg "$T"
reg "$T" ''
pub "$T" "This offering provides Bank-Grade encryption for every customer."
OUT=$(scanout "$T")
# CLAIM_SCAN_PROHIBITED_VOCABULARY=0 would itself satisfy a bare
# assert_contains "VOCABULARY" check (the field name contains the word) —
# pinned to =1 and to the bracketed finding line specifically so a
# regression back to case-sensitive matching fails this assertion.
assert_contains "CLAIM_SCAN_PROHIBITED_VOCABULARY=1" "$OUT" \
  "prohibited vocabulary is flagged regardless of capitalization"
assert_contains "[VOCABULARY]" "$OUT" "the case-insensitive match is reported as a finding"

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

# --- headings and code fences are not claims; tables and bullets now are -----
# Only headings and fenced code stay structurally exempt (issue #176). This
# fixture's table cells are all under the four-word floor on their own merits,
# so it stays a green regression check for the exemption boundary even though
# table cells are no longer blanket-skipped.
T="$W/structure"; mkpkg "$T"
reg "$T" ''
{
  printf '# Partner Guide\n\n'
  printf '## Getting started\n\n'
  printf '| Field | Value |\n|---|---|\n| Region | eu-west-1 |\n\n'
  printf '```bash\ncurl https://api.example.com/v1/ping\n```\n'
} > "$T/docs/dossier/06-public/technical-partner-guide.md"
scan "$T"
assert_equal "0" "$?" "short table cells under the word floor still pass clean"

# --- headings and fenced code stay exempt even with claim-shaped text --------
# The regression this issue's fix must not introduce: widening the selector to
# cover bullets/tables/blockquotes must not also widen it to headings or fences.
T="$W/heading-fence-exempt"; mkpkg "$T"
reg "$T" ''
{
  printf '# This product guarantees 9999 percent uptime annually\n\n'
  printf '```text\nThis product guarantees 9999 percent uptime annually\n```\n'
} > "$T/docs/dossier/06-public/technical-partner-guide.md"
scan "$T"
assert_equal "0" "$?" "claim-shaped text in a heading or fenced code block is still exempt"

# --- issue #176: a bullet is prose with a marker, not structural markup ------
# The exact shape reported in the issue: a claim written as a `- ` bullet
# scored 0 while the identical sentence as a paragraph scored non-zero.
T="$W/bullet-claim"; mkpkg "$T"
reg "$T" ''
pub "$T" '- There are no binaries and no bundles; you can read every hook before you install it.'
scan "$T"
assert_equal "1" "$?" "an unregistered claim written as a - bullet is now detected"
assert_contains "UNREGISTERED" "$(scanout "$T")" "the bullet claim is labelled"

# The `* ` bullet marker must be handled too, not just `- `.
T="$W/bullet-star-claim"; mkpkg "$T"
reg "$T" ''
pub "$T" '* This vendor performs full formal verification on every release.'
scan "$T"
assert_equal "1" "$?" "an unregistered claim written with a * bullet marker is detected"

# A REGISTERED bullet claim must pass, not just an unregistered one score
# non-zero. With no register present, an unregistered-only assertion cannot
# tell "the marker was stripped" apart from "the marker was left in place" —
# both produce a non-zero hit either way. `normalize()` incidentally strips a
# stray `*` (it removes `[*_#>]` unconditionally) but never strips `-`, so a
# `- ` marker left un-stripped survives into the normalized sentence as
# "- the api supports..." — a string the approved wording "the api
# supports..." does not contain as a substring, and the literal-substring
# match at :grep -qF would then wrongly report an approved claim as
# unregistered. This is the fixture that catches that specific failure.
T="$W/bullet-registered"; mkpkg "$T"
reg "$T" '| CL-0001 | the api supports oauth 20 device flow | capability | EV-0001 | 1.0 | all | none | VP Eng | Public | 06-public/technical-partner-guide.md | approved | verified |'
pub "$T" '- The API supports OAuth 20 device flow'
scan "$T"
assert_equal "0" "$?" "a registered claim written as a bullet still matches its approved wording"

# --- issue #176: a table cell is prose with a delimiter, not structural markup
T="$W/table-claim"; mkpkg "$T"
reg "$T" ''
{
  printf '| Property | Description |\n'
  printf '|---|---|\n'
  printf '| Availability | This service guarantees 9999 percent uptime annually |\n'
} > "$T/docs/dossier/06-public/technical-partner-guide.md"
scan "$T"
assert_equal "1" "$?" "an unregistered claim written as a table cell is detected"
assert_contains "UNREGISTERED" "$(scanout "$T")" "the table-cell claim is labelled"

# The table's own header row and separator row must never become "claims"
# themselves, even when the header wording clears the four-word floor.
T="$W/table-header-not-claim"; mkpkg "$T"
reg "$T" ''
{
  printf '| What the reader should expect | What this guarantees today |\n'
  printf '|---|---|\n'
  printf '| Region availability details | Nothing is promised beyond the current region |\n'
} > "$T/docs/dossier/06-public/technical-partner-guide.md"
OUT=$(scanout "$T")
assert_not_contains "what the reader should expect" "$OUT" "the table header row is not treated as a claim"
assert_contains "CLAIM_SCAN_UNREGISTERED_SENTENCES=1" "$OUT" "only the data cell is an unregistered claim, not the header"

# A separator row using alignment colons (`:---`, `---:`, `:---:`) must be
# recognized too, not just a bare `---` — is_table_separator explicitly
# special-cases `:` alongside `-`, and this is the only fixture exercising it.
T="$W/table-separator-alignment"; mkpkg "$T"
reg "$T" ''
{
  printf '| What the reader should expect | What this guarantees today |\n'
  printf '|:---|---:|\n'
  printf '| Region availability details | Nothing is promised beyond the current region |\n'
} > "$T/docs/dossier/06-public/technical-partner-guide.md"
OUT=$(scanout "$T")
assert_not_contains "what the reader should expect" "$OUT" \
  "the header row is exempt even when the separator uses alignment colons"
assert_contains "CLAIM_SCAN_UNREGISTERED_SENTENCES=1" "$OUT" \
  "only the data cell is unregistered when the separator uses alignment colons"

# A REGISTERED table-cell claim must pass — proves cell splitting/trimming
# produces text that round-trips through the literal-substring match, not
# just that cell text is detected at all.
T="$W/table-registered"; mkpkg "$T"
reg "$T" '| CL-0001 | the api supports oauth 20 device flow | capability | EV-0001 | 1.0 | all | none | VP Eng | Public | 06-public/technical-partner-guide.md | approved | verified |'
{
  printf '| Claim | Detail |\n'
  printf '|---|---|\n'
  printf '| Availability | The API supports OAuth 20 device flow |\n'
} > "$T/docs/dossier/06-public/technical-partner-guide.md"
scan "$T"
assert_equal "0" "$?" "a registered claim written as a table cell still matches its approved wording"

# A held row's finding must be attributed to the line it actually appeared on,
# not the line where the hold happened to resolve. Row 1 of a `|`-prefixed
# run is held pending row 2's separator check; when row 2 turns out NOT to be
# a separator (this fixture: two genuine data rows, no separator ever), row 1
# is flushed and scored from inside the code path handling row 2 — a `$LN`
# read at that point would attribute row 1's finding to row 2's line number.
T="$W/table-line-attribution"; mkpkg "$T"
reg "$T" ''
{
  printf 'This is the first row and it carries a genuine unregistered claim' | sed 's/^/| /; s/$/ |/'
  printf '\n'
  printf 'This is the second row and it also carries a genuine unregistered claim' | sed 's/^/| /; s/$/ |/'
  printf '\n'
} > "$T/docs/dossier/06-public/technical-partner-guide.md"
OUT=$(scanout "$T")
assert_contains "technical-partner-guide.md:1 \"this is the first row" "$OUT" \
  "row 1's finding is attributed to line 1, the line it actually appeared on"
assert_contains "technical-partner-guide.md:2 \"this is the second row" "$OUT" \
  "row 2's finding is attributed to line 2"

# --- issue #176 self-review: a degenerate table row must not crash the scan -
# `|` alone (or `||`) as a table row splits to a zero-cell body. Under bash
# 3.2's `set -u`, `arr=($empty_body)` leaves the array variable UNSET rather
# than a zero-length array, and a later `"${arr[@]}"` expansion is then a
# fatal unbound-variable error that kills the entire script mid-run — before
# the report is ever printed and before leakage already detected earlier in
# the same file is ever surfaced. This is exactly the "malformed table row
# ... must not crash" failure mode the issue's own specification calls out.
T="$W/table-degenerate-row"; mkpkg "$T"
reg "$T" ''
printf 'A real claim about our uptime that clears the word floor easily.\n|\n' \
  > "$T/docs/dossier/06-public/technical-partner-guide.md"
OUT=$(scanout "$T")
assert_not_contains "unbound variable" "$OUT" "a bare | table row does not crash the scan"
assert_contains "CLAIM_SCAN_UNREGISTERED_SENTENCES=" "$OUT" \
  "the script still completes and prints its report after a degenerate table row"

# A leak already detected earlier in the file must not be swallowed by a
# later crash — verified separately from the generic no-crash check above,
# since "the script didn't crash" and "the leak is still reported" are two
# different properties that could fail independently.
T="$W/table-degenerate-row-with-leak"; mkpkg "$T"
printf 'Use sk-ant-api03-abcdefghijklmnop to begin.\n||\n' \
  > "$T/docs/dossier/06-public/technical-partner-guide.md"
scan "$T"
assert_equal "2" "$?" "a leak earlier in the file is still reported (exit 2) despite a later degenerate table row"

# --- error-handler-inspector review (issue #176 PR): table state must not --
# leak across a fenced code block. The fence-toggle and in-fence-skip
# branches both `continue` BEFORE the "leave the table" cleanup
# (flush_held_table_row + reset) runs, so a held row from before the fence
# survives, uncleared, into whatever `|`-shaped line appears after the fence
# closes. If that later line independently looks like a GFM separator, the
# held row is discarded as "the header this separator confirms" — even
# though the two were never part of the same table — and the genuine claim
# is silently dropped: this issue's own core failure mode, reintroduced by
# its own fix's table-state machine.
T="$W/table-state-across-fence"; mkpkg "$T"
reg "$T" ''
{
  printf '| A genuine claim held pending its own separator right here |\n'
  printf '```text\nsome code\n```\n'
  printf '|---|---|\n'
} > "$T/docs/dossier/06-public/technical-partner-guide.md"
OUT=$(scanout "$T")
assert_contains "CLAIM_SCAN_UNREGISTERED_SENTENCES=1" "$OUT" \
  "a claim held before a fence is not silently discarded by an unrelated separator-shaped line after the fence"

# The same defect's mirror effect: a genuine table header row landing right
# after a fence gets misread as data (scored) instead of exempted, because
# the stale TABLE_ROWS_SEEN=1 makes it look like "row 2, deciding the
# earlier held line was a header" instead of "row 1 of a fresh table".
T="$W/table-header-after-fence"; mkpkg "$T"
reg "$T" ''
{
  printf '| A genuine claim held pending its own separator right here |\n'
  printf '```text\nsome code\n```\n'
  printf '| Supported Since Version Column | Another Header Cell Here |\n'
  printf '|---|---|\n'
  printf '| Row | Cell |\n'
} > "$T/docs/dossier/06-public/technical-partner-guide.md"
OUT=$(scanout "$T")
assert_not_contains "supported since version column" "$OUT" \
  "a genuine header row right after a fence is still exempted, not scored as data"

# --- issue #176 self-review: a `|` inside a code span must not split a cell -
# Splitting on every raw `|` before code-span stripping (which normally
# happens inside scan_text, per-cell, too late to undo an already-wrong
# split) can silently drop a claim: `Zero downtime `x|y` guaranteed system.`
# splits into two halves, each short enough after the split to fall under
# the four-word floor — reproducing the exact "0 doesn't mean it was
# checked" failure this issue exists to fix, just moved one level down (a
# claim hidden inside a single cell instead of hidden by line class).
T="$W/table-cell-code-span-pipe"; mkpkg "$T"
reg "$T" ''
{
  printf '| Guarantee |\n'
  printf '|---|\n'
  printf '| Zero downtime `x|y` guaranteed system. |\n'
} > "$T/docs/dossier/06-public/technical-partner-guide.md"
OUT=$(scanout "$T")
assert_contains "CLAIM_SCAN_UNREGISTERED_SENTENCES=1" "$OUT" \
  "a claim is still detected whole even when a code span inside the cell contains a pipe"

# --- security review (issue #176 PR): an escaped backslash before a real ---
# delimiter must not be misread as an escaped pipe. `\\|` is GFM for "a
# literal backslash" (`\\`) followed by an ordinary cell delimiter (`|`), not
# an escaped pipe — but a naive `s/\\|/MARK/` match on the raw two-character
# sequence `\|` fires on the SECOND backslash of `\\|` too, mistaking the
# real delimiter for an escape and merging two cells into one.
T="$W/table-cell-escaped-backslash"; mkpkg "$T"
reg "$T" ''
printf '| This cell has content today \\\\| And this is a separate cell over here |\n' \
  > "$T/docs/dossier/06-public/technical-partner-guide.md"
OUT=$(scanout "$T")
assert_contains "CLAIM_SCAN_UNREGISTERED_SENTENCES=2" "$OUT" \
  "an escaped backslash before a real delimiter still splits into two cells, not one merged cell"

# The primary case the escape mechanism exists for: a lone `\|` must keep the
# cell whole, not split (holdout-validation finding — the sibling test above
# only proved the counter-case; nothing pinned the single-backslash case a
# future refactor of the two-pass sed logic could silently break).
T="$W/table-cell-escaped-pipe"; mkpkg "$T"
reg "$T" ''
printf '| cell one text here \\| cell two text here |\n' \
  > "$T/docs/dossier/06-public/technical-partner-guide.md"
OUT=$(scanout "$T")
assert_contains "CLAIM_SCAN_UNREGISTERED_SENTENCES=1" "$OUT" \
  "an escaped pipe keeps the cell whole, not split into two"

# --- issue #176: a blockquote is prose with a marker, not structural markup --
T="$W/blockquote-claim"; mkpkg "$T"
reg "$T" ''
pub "$T" '> This product has completed a formal third-party security audit.'
scan "$T"
assert_equal "1" "$?" "an unregistered claim written as a blockquote is detected"

# A REGISTERED blockquote claim must pass, for the same marker-stripping-
# residue reason as the bullet case above (`>` is stripped by normalize()
# incidentally, but only after the `-`-equivalent leading-space concern is
# ruled out by explicit marker removal, not relied upon).
T="$W/blockquote-registered"; mkpkg "$T"
reg "$T" '| CL-0001 | the api supports oauth 20 device flow | capability | EV-0001 | 1.0 | all | none | VP Eng | Public | 06-public/technical-partner-guide.md | approved | verified |'
pub "$T" '> The API supports OAuth 20 device flow'
scan "$T"
assert_equal "0" "$?" "a registered claim written as a blockquote still matches its approved wording"

# --- issue #176: the scan's own coverage scope must be legible in its output -
# A `0` result must not be misreadable as "every line class was checked" when
# it only ever meant "every paragraph was checked" (the exact failure mode the
# issue reports — three separate measurements of this scanner's own output
# disagreed on how much of the document it covered).
T="$W/line-classes-field"; mkpkg "$T"
reg "$T" ''
pub "$T" "A simple paragraph sentence with no claims at all here."
OUT=$(scanout "$T")
assert_contains "CLAIM_SCAN_LINE_CLASSES_EXAMINED=" "$OUT" "the scan reports which line classes it examined"
assert_contains "bullet" "$OUT" "bullets are listed among the examined line classes"
assert_contains "table-data-cell" "$OUT" "table data cells are listed among the examined line classes"
if command -v jq >/dev/null 2>&1; then
  J=$(cd "$T" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" "$SCAN" --output-root docs/dossier --json 2>/dev/null)
  CLASSES=$(printf '%s' "$J" | jq -r '(.line_classes_examined // []) | join(",")' 2>/dev/null)
  assert_contains "table-data-cell" "$CLASSES" "the json output reports table-data-cell among examined line classes"
fi

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

# --- missing public directory is infrastructure, NOT leakage ------------------
# 2 and 3 must stay distinct. The gate turns this exit code straight into
# published evidence, so collapsing them made an incomplete package read as a
# disclosure incident — a security claim in the record that never happened.
T="$W/nopub"; mkdir -p "$T/docs/dossier" 2>/dev/null
scan "$T"
assert_equal "3" "$?" "a missing public directory exits 3 (infrastructure), not 2 (leakage)"

# A real leak must still be 2, or the distinction is one-sided.
T="$W/reallеak"; mkpkg "$T"
pub "$T" "The key sk-ant-abcdefgh12345678 is stored in the vault for safekeeping."
scan "$T"
assert_equal "2" "$?" "an actual credential still exits 2 (leakage)"

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

# A document whose last line has no trailing newline must still be scanned to
# its end. `while read` returns failure on a final line with no newline but
# still populates the variable with its content; a loop that treats that
# failure as "nothing left to read" silently drops exactly one line — always
# the last one — matching this issue's own theme of a scan whose true
# coverage does not match what its clean result implies.
T="$W/no-trailing-newline"; mkdir -p "$T/docs/dossier/06-public" 2>/dev/null
printf -- 'This is the only line and it carries a real unregistered claim.' \
  > "$T/docs/dossier/06-public/g.md" 2>/dev/null
OUT=$(scanout "$T")
assert_contains "CLAIM_SCAN_UNREGISTERED_SENTENCES=1" "$OUT" \
  "the last line is still scanned even with no trailing newline"


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
# The probe sentence is deliberately mundane, NOT "our service is completely
# secure": that wording independently trips the prohibited-vocabulary scanner
# (section A, run over the raw document regardless of registration), which
# forces exit 1 whether or not the rejected row is honoured as approved —
# confirmed by running both the pass and fail cases below through the real
# scanner. A sentence with no leak/vocabulary match is required for exit 0 vs.
# exit 1 to actually distinguish "wrongly approved" from "correctly rejected".
T="$W/rejected"; mkpkg "$T"
cat >> "$T/docs/dossier/00-control/claim-and-disclosure-register.md" <<'REGEOF'

## Rejected and withdrawn claims

| ID | Wording | Reason declined | Date | What would make it publishable |
|---|---|---|---|---|
| CL-9001 | our onboarding process takes one business day | the reviewer noted this was not "| approved |" by security | 2026-07-26 | evidence |
REGEOF
# A silent failure here is exactly the bug this block was rewritten to fix: a
# wrong or missing parent directory makes the heredoc redirect fail with the
# register file never written at all, and the scan below would still exit
# non-zero (via the unrelated "no register present" path) — passing the
# assertion for the wrong reason all over again. Checked directly rather than
# trusted, since that is precisely how the original bug hid.
assert_file_exists "$T/docs/dossier/00-control/claim-and-disclosure-register.md" \
  "the rejected-row register was actually written"
pub "$T" "Our onboarding process takes one business day."
OUT=$(scanout "$T")
RC=$?
assert_equal "1" "$RC" "a rejected row is not honoured as an approved claim"
# Pinned individually, not just via the aggregate exit code: exit 1 alone
# cannot tell "correctly rejected" apart from a handful of other ways this
# same fixture could produce a non-zero exit for the wrong reason — a
# register silently absent again (the exact #151 failure shape), a `cd`/mkdir
# break inside scan()/scanout(), or the probe sentence drifting back toward
# vocabulary-flagged wording. Each assertion below names exactly one of those
# and fails on it specifically, rather than letting exit 1 paper over it.
assert_contains "CLAIM_SCAN_REGISTER_PRESENT=1" "$OUT" "the register was read, not silently absent"
assert_contains "CLAIM_SCAN_UNREGISTERED_SENTENCES=1" "$OUT" "exactly the rejected-row sentence is unregistered"
assert_contains "CLAIM_SCAN_PROHIBITED_VOCABULARY=0" "$OUT" "the probe sentence still trips no vocabulary pattern"

_dossier_test_summary
