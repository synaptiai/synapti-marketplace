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
#
# The pattern matches the hyphenated attributive form ("7-directory package") as
# well as the spaced one. An earlier version required a space and so reported a
# pass on a file whose very first description line said `7-directory` — a green
# assertion certifying the defect it was written to pin, which is worse than no
# assertion at all. The scan set is every file that states the count, not the
# subset that happened to state it when the check was written.
STALE_DIR_RE='\b(7|seven)[- ](director(y|ies)|dirs)\b'
while IFS= read -r f; do
  [ -f "$f" ] || continue
  if grep -qE "$STALE_DIR_RE" "$f"; then
    _dossier_assert_fail "$f: says 7 directories; the package has $DIR_COUNT"
  else
    _dossier_assert_pass "$(basename "$f"): no stale directory count"
  fi
done <<EOF
plugins/dossier/skills/doc-package-contract/SKILL.md
plugins/dossier/skills/engagement-scoping/SKILL.md
plugins/dossier/references/project-type-adaptation.md
plugins/dossier/README.md
plugins/dossier/CHANGELOG.md
plugins/dossier/bin/dossier-scaffold.sh
EOF

# The release gate's condition count and its mechanical/judgment split are
# stated in prose across the plugin and implemented once, in the gate script.
# Both numbers are derived from the condition table rather than written down
# here, so adding G18 moves the expectation automatically and any prose that
# still says "seventeen" fails.
GATE_REF="$REFS/release-gate-conditions.md"
if [ -f "$GATE_REF" ]; then
  COND_TOTAL=$(grep -cE '^\| G[0-9]+ \|' "$GATE_REF" | tr -d ' ')
  COND_MECH=$(grep -E '^\| G[0-9]+ \|' "$GATE_REF" | grep -c 'mechanical' | tr -d ' ')
  COND_JUDG=$(grep -E '^\| G[0-9]+ \|' "$GATE_REF" | grep -c 'judgment' | tr -d ' ')
  assert_equal "$COND_TOTAL" "$((COND_MECH + COND_JUDG))" "every gate condition is tagged mechanical or judgment"

  # Number words for the counts the prose actually uses.
  # Wide enough that a plausible change stays inside it, and loud rather than
  # silent when it does not: an unmapped count used to blank the variable and
  # skip every assertion below with no pass and no fail recorded.
  number_word() { # n -> lowercase english number word, empty if unmapped
    case "$1" in
      1) echo one ;;     2) echo two ;;      3) echo three ;;    4) echo four ;;
      5) echo five ;;    6) echo six ;;      7) echo seven ;;    8) echo eight ;;
      9) echo nine ;;   10) echo ten ;;     11) echo eleven ;;  12) echo twelve ;;
     13) echo thirteen ;; 14) echo fourteen ;; 15) echo fifteen ;; 16) echo sixteen ;;
     17) echo seventeen ;; 18) echo eighteen ;; 19) echo nineteen ;; 20) echo twenty ;;
     21) echo twenty-one ;; 22) echo twenty-two ;; 23) echo twenty-three ;;
     24) echo twenty-four ;; 25) echo twenty-five ;;
      *) echo "" ;;
    esac
  }
  TOTAL_WORD=$(number_word "$COND_TOTAL")
  MECH_WORD=$(number_word "$COND_MECH")
  [ -n "$TOTAL_WORD" ] \
    && _dossier_assert_pass "the condition count ($COND_TOTAL) maps to a number word" \
    || _dossier_assert_fail "condition count $COND_TOTAL is outside the mapped range; the prose cross-check would be skipped"
  [ -n "$MECH_WORD" ] \
    && _dossier_assert_pass "the mechanical count ($COND_MECH) maps to a number word" \
    || _dossier_assert_fail "mechanical count $COND_MECH is outside the mapped range; the prose cross-check would be skipped"

  if [ -n "$TOTAL_WORD" ]; then
    for f in plugins/dossier/README.md \
             plugins/dossier/CHANGELOG.md \
             plugins/dossier/commands/gate.md \
             plugins/dossier/agents/dossier-scorer.md \
             plugins/dossier/skills/scoring-and-release-gate/SKILL.md \
             plugins/dossier/references/scorecard-rubric.md \
             "$GATE_REF"; do
      [ -f "$f" ] || continue
      # Any condition-count word other than the derived one is stale.
      BAD=$(grep -oiE "\b(fifteen|sixteen|seventeen|eighteen) conditions\b" "$f" \
              | grep -ivE "^${TOTAL_WORD} conditions$" | head -1)
      if [ -n "$BAD" ]; then
        _dossier_assert_fail "$f: says '$BAD'; the gate has $COND_TOTAL conditions"
      else
        _dossier_assert_pass "$(basename "$f"): condition count agrees with the table"
      fi
    done
  fi

  if [ -n "$MECH_WORD" ]; then
    for f in plugins/dossier/README.md \
             plugins/dossier/commands/gate.md \
             plugins/dossier/tests/bin-scripts.test.sh \
             "$GATE_REF"; do
      [ -f "$f" ] || continue
      BAD=$(grep -oiE "\b(nine|ten|eleven) mechanical\b" "$f" \
              | grep -ivE "^${MECH_WORD} mechanical$" | head -1)
      if [ -n "$BAD" ]; then
        _dossier_assert_fail "$f: says '$BAD'; the table tags $COND_MECH conditions mechanical"
      else
        _dossier_assert_pass "$(basename "$f"): mechanical count agrees with the table"
      fi
    done
  fi
fi

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

# --- The gate's G17 strings must exist in the template it grades -------------
# G17 greps the verification report for a heading and a line. If the shipped
# template does not carry them, a drafter who follows the template verbatim
# fails the gate every time with nothing in the template to explain why.
VR="$PKG/07-verification/documentation-verification-report.md"
GATE="plugins/dossier/bin/dossier-gate.sh"
assert_file_exists "$VR" "verification report template exists"
assert_file_exists "$GATE" "gate script exists"

# Read the heading out of the gate rather than restating it here, so renaming
# one without the other fails instead of drifting silently.
G17_HEAD=$(grep -o "'\^## [A-Za-z -]*independence method'" "$GATE" | head -1 | tr -d "'^")
if [ -n "$G17_HEAD" ]; then
  _dossier_assert_pass "G17's expected heading was recovered from the gate ($G17_HEAD)"
  if grep -qF "$G17_HEAD" "$VR"; then
    _dossier_assert_pass "template carries the heading G17 greps for"
  else
    _dossier_assert_fail "template lacks G17's heading '$G17_HEAD' — every drafted report fails G17"
  fi
else
  _dossier_assert_fail "could not recover G17's heading from the gate — the test cannot verify the pair"
fi

if grep -q 'Model diversity:' "$VR"; then
  _dossier_assert_pass "template prompts for the 'Model diversity:' line G17 requires"
else
  _dossier_assert_fail "template does not prompt for 'Model diversity:' — G17 fails on a faithful report"
fi

_dossier_test_summary

