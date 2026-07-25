#!/usr/bin/env bash
# The package contract: exactly 23 templates on exactly the expected paths, each
# pointing at a contract anchor that resolves, and the eight contract references
# collectively covering all 23 slugs — no more, no fewer.
#
# A template without a contract is an unspecified document. A contract without a
# template is a requirement nothing implements. Both drift silently.

_dossier_test_begin "package-contract"

PKG="plugins/dossier/templates/package"
REFS="plugins/dossier/references"

EXPECTED="00-control/documentation-index
00-control/evidence-ledger
00-control/assumptions-questions-and-contradictions
00-control/claim-and-disclosure-register
00-control/terminology-and-ownership
01-project/executive-project-brief
01-project/product-and-domain
02-architecture/system-architecture
02-architecture/components-and-codebase
02-architecture/data-and-ai
02-architecture/interfaces-and-integrations
02-architecture/infrastructure-and-deployment
03-assurance/security-privacy-and-compliance
03-assurance/reliability-performance-and-observability
03-assurance/testing-quality-and-delivery
04-operating/onboarding-and-local-development
04-operating/operations-and-incident-response
04-operating/decisions-technical-debt-and-risks
05-due-diligence/technical-due-diligence-report
05-due-diligence/assets-dependencies-and-licenses
06-public/technical-partner-guide
06-public/customer-product-and-trust-guide
07-verification/documentation-verification-report"

# Exactly 23, no extras. An extra template is a document the contract does not
# describe and the verification passes will not audit.
ACTUAL_COUNT=$(find "$PKG" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
assert_equal "23" "$ACTUAL_COUNT" "template count is exactly 23"

EXPECTED_COUNT=$(printf '%s\n' "$EXPECTED" | grep -c .)
assert_equal "23" "$EXPECTED_COUNT" "expected list itself has 23 entries"

while IFS= read -r slug; do
  [ -z "$slug" ] && continue
  assert_file_exists "$PKG/$slug.md" "template $slug.md"
done <<EOF
$EXPECTED
EOF

# No template outside the expected set.
while IFS= read -r f; do
  rel=${f#"$PKG"/}
  rel=${rel%.md}
  if printf '%s\n' "$EXPECTED" | grep -qxF "$rel"; then
    _dossier_assert_pass "template $rel is expected"
  else
    _dossier_assert_fail "unexpected template: $rel"
  fi
done <<EOF
$(find "$PKG" -name '*.md' -type f 2>/dev/null | sort)
EOF

# The eight numbered directories.
for d in 00-control 01-project 02-architecture 03-assurance 04-operating 05-due-diligence 06-public 07-verification; do
  if [ -d "$PKG/$d" ]; then
    _dossier_assert_pass "directory $d exists"
  else
    _dossier_assert_fail "directory $d missing"
  fi
done

DIR_COUNT=$(find "$PKG" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
assert_equal "8" "$DIR_COUNT" "exactly 8 numbered directories on disk"

# Prose must agree with the filesystem. The package structure is stated in an
# Iron Law and in two other places; an off-by-one there is the plugin telling
# users something its own scaffold contradicts, which is the precise defect the
# cross-document consistency dimension exists to catch.
for f in plugins/dossier/skills/doc-package-contract/SKILL.md \
         plugins/dossier/skills/engagement-scoping/SKILL.md \
         plugins/dossier/references/project-type-adaptation.md \
         plugins/dossier/README.md; do
  [ -f "$f" ] || continue
  if grep -qE '\b7 (directories|dirs)\b|\bseven directories\b' "$f"; then
    _dossier_assert_fail "$(basename "$f"): says 7 directories; the package has $DIR_COUNT"
  else
    _dossier_assert_pass "$(basename "$f"): no stale directory count"
  fi
done

# The eight contract references.
for d in 00-control 01-project 02-architecture 03-assurance 04-operating 05-due-diligence 06-public 07-verification; do
  assert_file_exists "$REFS/package-contract-$d.md" "contract for $d"
done

# Every template's header must carry the schema discriminator, and every
# contract pointer must resolve to a heading that exists in a file that exists.
# The pointer is positional and mechanically parsed, so a broken one is not a
# cosmetic problem.
while IFS= read -r f; do
  rel=${f#"$PKG"/}

  hdr=$(awk -F': ' '/^dossier-header:/{print $2; exit}' "$f")
  case "$rel" in
    06-public/*) expected_hdr="public-v1" ;;
    *)           expected_hdr="internal-v1" ;;
  esac
  assert_equal "$expected_hdr" "$hdr" "$rel: header discriminator"

  ptr=$(grep -m1 -oE '<!-- contract: [^ ]+ -->' "$f" | sed -E 's/<!-- contract: (.*) -->/\1/')
  if [ -z "$ptr" ]; then
    _dossier_assert_fail "$rel: no contract pointer"
    continue
  fi

  ref_file="plugins/dossier/${ptr%%#*}"
  anchor="${ptr#*#}"

  if [ -f "$ref_file" ]; then
    _dossier_assert_pass "$rel: contract file $ref_file exists"
  else
    _dossier_assert_fail "$rel: contract pointer targets missing file $ref_file"
    continue
  fi

  # GitHub anchors: lowercase, spaces to hyphens, punctuation dropped.
  if grep -qiE "^#{2,4} .*" "$ref_file" && \
     awk '/^#{2,4} /{
            h=tolower($0); sub(/^#+ /,"",h);
            gsub(/[^a-z0-9 -]/,"",h); gsub(/ /,"-",h);
            print h
          }' "$ref_file" | grep -qxF "$anchor"; then
    _dossier_assert_pass "$rel: anchor #$anchor resolves"
  else
    _dossier_assert_fail "$rel: anchor #$anchor not found in $ref_file"
  fi
done <<EOF
$(find "$PKG" -name '*.md' -type f 2>/dev/null | sort)
EOF

# Every slug is documented by exactly one contract, and no contract documents a
# slug that has no template.
ALL_ANCHORS=$(for d in 00-control 01-project 02-architecture 03-assurance 04-operating 05-due-diligence 06-public 07-verification; do
  awk '/^#{2,3} /{h=tolower($0); sub(/^#+ /,"",h); gsub(/[^a-z0-9 -]/,"",h); gsub(/ /,"-",h); print h}' \
    "$REFS/package-contract-$d.md" 2>/dev/null
done)

while IFS= read -r slug; do
  [ -z "$slug" ] && continue
  doc=${slug#*/}
  if printf '%s\n' "$ALL_ANCHORS" | grep -qxF "$doc"; then
    _dossier_assert_pass "contract documents $doc"
  else
    _dossier_assert_fail "no contract section for $doc"
  fi
done <<EOF
$EXPECTED
EOF

# The four control registers ARE the empty tables — a separate registers/ dir
# would duplicate them and immediately drift.
for r in evidence-ledger assumptions-questions-and-contradictions claim-and-disclosure-register terminology-and-ownership; do
  if grep -qE '^\|.*\|.*\|' "$PKG/00-control/$r.md" 2>/dev/null; then
    _dossier_assert_pass "$r template carries its register table"
  else
    _dossier_assert_fail "$r template has no table — the register schema must be in the template"
  fi
done

_dossier_test_summary
