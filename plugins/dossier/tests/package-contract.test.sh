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

# =============================================================================
# Contract/template bijection and metadata coherence
# =============================================================================
# The claim "contract and skeleton cannot drift" is only worth making if it is
# checked. Each assertion below closes one drift vector that the anchor check
# above does not reach.

CONTRACT_SECTIONS=$(grep -h '^## ' "$REFS"/package-contract-0*.md | sed 's/^## //' | sort)
SECTION_COUNT=$(printf '%s\n' "$CONTRACT_SECTIONS" | grep -c .)
assert_equal "23" "$SECTION_COUNT" "the 8 contracts declare exactly 23 document sections"

# Bijection: no orphan section, no duplicate. A section with no template is a
# requirement nothing implements.
DUPES=$(printf '%s\n' "$CONTRACT_SECTIONS" | uniq -d)
if [ -z "$DUPES" ]; then
  _dossier_assert_pass "no duplicate contract sections"
else
  _dossier_assert_fail "duplicate contract sections: $(printf '%s' "$DUPES" | tr '\n' ' ')"
fi

TEMPLATE_SLUGS=$(find "$PKG" -name '*.md' -type f 2>/dev/null | sed -E 's|.*/||; s|\.md$||' | sort)
if [ "$CONTRACT_SECTIONS" = "$TEMPLATE_SLUGS" ]; then
  _dossier_assert_pass "contract sections and template basenames are a 1:1 bijection"
else
  _dossier_assert_fail "contract sections and template basenames differ: $(diff <(printf '%s\n' "$CONTRACT_SECTIONS") <(printf '%s\n' "$TEMPLATE_SLUGS") | tr '\n' ' ')"
fi

# Per-section metadata. Each contract section declares Path, Template, Header
# style and Audience in its metadata table.
for field in "Path" "Template" "Header style" "Audience"; do
  n=$(grep -h "^| $field |" "$REFS"/package-contract-0*.md | wc -l | tr -d ' ')
  assert_equal "23" "$n" "every section declares $field"
done

# Declared Path and Template must resolve, and the declared header style must
# match what the template actually carries.
#
# THAT LAST ONE IS THE DRIFT VECTOR NOTHING ELSE CATCHES. The check further up
# validates each template's own discriminator against a rule derived from its
# directory. It never compares the template against what the CONTRACT says the
# template should be — so a contract declaring `internal-v1` for a public
# document would sail through while instructing a drafter to stamp the wrong
# header and leak internal fields into a published file.
for cf in "$REFS"/package-contract-0*.md; do
  # Split on section headings, then read the metadata rows of each block.
  # Values are backtick-delimited; split on the backtick and take field 2
  # rather than using gsub, whose greedy `.*` consumes both delimiters and
  # leaves the trailing table pipe.
  awk -F'`' '
    /^## / { slug=$0; sub(/^## /,"",slug); path=""; tpl=""; hdr=""; next }
    slug != "" && /^\| Path \| / { path=$2; next }
    slug != "" && /^\| Template \| / { tpl=$2; next }
    slug != "" && /^\| Header style \| / {
      hdr=$2
      print slug "\t" path "\t" tpl "\t" hdr
      slug=""
      next
    }
  ' "$cf" > /tmp/dossier-contract-meta.$$ 2>/dev/null

  while IFS=$'\t' read -r slug path tpl hdr; do
    [ -z "$slug" ] && continue

    # Declared package-relative path must name this slug.
    base=$(basename "$path" .md)
    if [ "$base" = "$slug" ]; then
      _dossier_assert_pass "$slug: declared Path names the same document"
    else
      _dossier_assert_fail "$slug: declared Path '$path' does not match the section slug"

    fi

    # Declared template must exist. The contract paths are plugin-relative.
    tpl_abs="plugins/dossier/$tpl"
    [ -f "$tpl" ] && tpl_abs="$tpl"
    if [ -f "$tpl_abs" ]; then
      _dossier_assert_pass "$slug: declared Template resolves"
    else
      _dossier_assert_fail "$slug: declared Template '$tpl' does not resolve"

      continue
    fi

    actual=$(awk -F': ' '/^dossier-header:/{print $2; exit}' "$tpl_abs" 2>/dev/null)
    if [ "$actual" = "$hdr" ]; then
      _dossier_assert_pass "$slug: declared header style matches the template"
    else
      _dossier_assert_fail "$slug: contract declares header '$hdr' but the template carries '$actual'"

    fi
  done < /tmp/dossier-contract-meta.$$
  rm -f /tmp/dossier-contract-meta.$$ 2>/dev/null
done

# Required subsections. All three are mandatory in every section; the third is
# where source principle 7 ("optimize for decisions and tasks") lives, since it
# is a quality attribute with no invocation point and therefore owns no skill.
for sub in "Required content" "Hard rules" "Decision-usefulness test"; do
  n=$(grep -h "^### $sub" "$REFS"/package-contract-0*.md | wc -l | tr -d ' ')
  assert_equal "23" "$n" "every section carries a '$sub' subsection"
done

# Project-type adaptation is required everywhere EXCEPT 00-control, and that
# exception is deliberate rather than an omission: register mechanics are
# project-type-invariant. An EV- row has the same columns for a firmware
# project and a SaaS; what varies is what fills them, and that variation is
# already carried by the per-project-type table in
# source-authority-and-claim-states.md. Duplicating it here would create
# exactly the drift surface the package format exists to prevent.
#
# Encoded as an explicit exception so a future maintainer does not "fix" the
# gap by adding the duplicate.
for cf in "$REFS"/package-contract-0*.md; do
  name=$(basename "$cf")
  sections=$(grep -c '^## ' "$cf")
  adapt=$(grep -c '^### Project-type adaptation' "$cf")
  case "$name" in
    package-contract-00-control.md)
      assert_equal "0" "$adapt" "$name: no project-type adaptation, by design (register mechanics are invariant)" ;;
    *)
      assert_equal "$sections" "$adapt" "$name: every section carries project-type adaptation" ;;
  esac
done

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
