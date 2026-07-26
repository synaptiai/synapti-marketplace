#!/usr/bin/env bash
# Behavioural coverage for the bin scripts that previously had only hygiene
# checks (exists / executable / `bash -n` / usage header).
#
# Hygiene checks prove a script parses. They do not prove it computes anything,
# and five of the fourteen had nothing beyond them — including
# dossier-blast-radius.sh, whose own header calls its mapping "the single
# biggest lever on the cost and reviewability of a refresh". A lever with no
# test is a lever nobody has pulled.

_dossier_test_begin "bin-behaviour"

BIN="plugins/dossier/bin"

WORK=$(mktemp -d) || { _dossier_assert_fail "cannot create temp dir"; _dossier_test_summary; return 0 2>/dev/null || exit 0; }

# --- dossier-blast-radius.sh -------------------------------------------------
# A changed-file set maps to the documents that describe those files. The
# mapping is what decides how much a refresh rewrites, so both directions
# matter: a source change must reach architecture, and an unrelated change must
# not drag the whole package in behind it.
CF="$WORK/changed.txt"
printf '%s\n' \
  'src/api/routes.ts' \
  'infra/terraform/main.tf' \
  '.github/workflows/ci.yml' > "$CF"

BR_OUT=$("$BIN/dossier-blast-radius.sh" --changed-files "$CF" --out "$WORK/br.json" 2>&1)
BR_RC=$?
assert_equal "0" "$BR_RC" "blast-radius exits 0 on a well-formed input"
assert_contains "document_count=" "$BR_OUT" "blast-radius reports a document count"

if [ -s "$WORK/br.json" ]; then
  _dossier_assert_pass "blast-radius wrote its JSON result"
else
  _dossier_assert_fail "blast-radius wrote no JSON result"
fi

if command -v jq >/dev/null 2>&1 && [ -s "$WORK/br.json" ]; then
  if jq -e . "$WORK/br.json" >/dev/null 2>&1; then
    _dossier_assert_pass "blast-radius emits valid JSON"
  else
    _dossier_assert_fail "blast-radius emitted malformed JSON"
  fi

  DOC_N=$(printf '%s' "$BR_OUT" | sed -n 's/^document_count=//p' | head -1)
  case "$DOC_N" in
    ''|*[!0-9]*) _dossier_assert_fail "document_count is not a number: '$DOC_N'" ;;
    *)           _dossier_assert_pass "document_count is numeric ($DOC_N)" ;;
  esac
  if [ "${DOC_N:-0}" -gt 0 ] 2>/dev/null; then
    _dossier_assert_pass "an infrastructure and API change maps to at least one document"
  else
    _dossier_assert_fail "a source change mapped to no document at all"
  fi
fi

# An empty change set maps to the four always-regenerated control documents and
# nothing else. `references/change-triggers-and-blast-radius.md` §"Always
# regenerated" names exactly those four, so this asserts the floor is the floor:
# a no-op merge must not drag architecture or assurance in behind it.
: > "$WORK/empty.txt"
BR_OUT2=$("$BIN/dossier-blast-radius.sh" --changed-files "$WORK/empty.txt" --out "$WORK/br2.json" 2>&1)
assert_contains "document_count=4" "$BR_OUT2" "an empty change set maps to the four always-regenerated documents"
for D in 00-control/documentation-index.md \
         00-control/evidence-ledger.md \
         00-control/assumptions-questions-and-contradictions.md \
         07-verification/documentation-verification-report.md; do
  assert_contains "$D" "$BR_OUT2" "the always-regenerated set includes $D"
done
assert_not_contains "02-architecture/" "$BR_OUT2" "an empty change set does not reach architecture"
assert_not_contains "03-assurance/" "$BR_OUT2" "an empty change set does not reach assurance"

# …and the mapped set for a real change is strictly larger than that floor,
# or the mapping is returning the constant and nothing else.
assert_contains "02-architecture/" "$BR_OUT" "a source and infrastructure change does reach architecture"

# A missing input file is an error, not an empty result: they are the same
# downstream and mean opposite things.
"$BIN/dossier-blast-radius.sh" --changed-files "$WORK/nope.txt" --out "$WORK/br3.json" >/dev/null 2>&1
BR_RC3=$?
if [ "$BR_RC3" -ne 0 ]; then
  _dossier_assert_pass "blast-radius fails on a missing input file (exit $BR_RC3)"
else
  _dossier_assert_fail "blast-radius treated a missing input file as an empty change set"
fi

# --- dossier-managed-file.sh -------------------------------------------------
# The stamp is what lets a refresh tell "we wrote this" from "a human edited
# it". Confusing the two either overwrites human work or refuses to update.
MF="$WORK/managed.md"
printf '# Managed\n\nBody line one.\n' > "$MF"

# The four states are distinct and mean different things: `absent` is "no such
# file", `foreign` is "exists, but nothing here wrote it". Collapsing them would
# make a refresh either clobber a hand-authored file or refuse to create one.
MF_OUT=$("$BIN/dossier-managed-file.sh" --verify "$WORK/no-such-file.md" 2>&1)
assert_contains "MANAGED=absent" "$MF_OUT" "a nonexistent path verifies as absent"

MF_OUT=$("$BIN/dossier-managed-file.sh" --verify "$MF" 2>&1)
assert_contains "MANAGED=foreign" "$MF_OUT" "an existing unstamped file verifies as foreign, not absent"

"$BIN/dossier-managed-file.sh" --stamp "$MF" >/dev/null 2>&1
MF_OUT=$("$BIN/dossier-managed-file.sh" --verify "$MF" 2>&1)
assert_contains "MANAGED=clean" "$MF_OUT" "a freshly stamped file verifies as clean"

printf 'A human added this line.\n' >> "$MF"
MF_OUT=$("$BIN/dossier-managed-file.sh" --verify "$MF" 2>&1)
assert_contains "MANAGED=dirty" "$MF_OUT" "a hand-edited stamped file verifies as dirty"

# Re-stamping must reconcile, or the state is unrecoverable without deleting.
"$BIN/dossier-managed-file.sh" --stamp "$MF" >/dev/null 2>&1
MF_OUT=$("$BIN/dossier-managed-file.sh" --verify "$MF" 2>&1)
assert_contains "MANAGED=clean" "$MF_OUT" "re-stamping returns a dirty file to clean"

# --- dossier-pr-body.sh ------------------------------------------------------
# Untrusted text reaches this renderer from pull request titles.
PB="$WORK/body.md"
PR_TITLE='Fix](https://evil.example "x") [ and | a pipe `tick`' \
PR_NUMBER='42' \
  "$BIN/dossier-pr-body.sh" --out "$PB" >/dev/null 2>&1
if [ -s "$PB" ]; then
  _dossier_assert_pass "pr-body rendered a body"
  BODY=$(cat "$PB")
  # An unescaped bracket rewrites the table cell into a link that says something
  # the title did not; an unescaped pipe silently reshapes the table.
  assert_not_contains "Fix](https://evil.example" "$BODY" \
    "a markdown link injected through the PR title is neutralised"
else
  _dossier_assert_fail "pr-body wrote no output"
fi

rm -rf "$WORK" 2>/dev/null

_dossier_test_summary
