#!/usr/bin/env bash
# dossier-package-check.sh — mechanical integrity check for a dossier package.
#
# Checks five things that can be verified without judgment, so that human and
# agent review effort goes to the things that cannot:
#
#   1. All 23 canonical files exist under <output-root>.
#   2. Every file carries a parseable header (internal-v1 or public-v1) with all
#      required fields present and non-empty. `{fill}` counts as EMPTY — an
#      unfilled placeholder is a missing field, not a value.
#   3. Every internal markdown link resolves, including `related:` entries.
#   4. Every `<!-- contract: -->` pointer on body line 2 resolves to an existing
#      anchor in an existing reference file.
#   5. Every document carries a well-formed last-verified (or last-updated) date.
#
# It does NOT check whether the content is true. That is what the verification
# passes are for.
#
# Usage:
#   dossier-package-check.sh --output-root <path> [--references <dir>] [--quiet]
#
# Flags:
#   --output-root <path>   REQUIRED. Root of the package to check.
#   --references <dir>     Plugin root holding `references/`. Defaults to
#                          CLAUDE_PLUGIN_ROOT, then this script's parent.
#   --quiet                Emit KEY=value lines only; suppress the findings list.
#
# Output (stdout): KEY=value lines, then `FINDING <code> <path> — <detail>` lines.
#
# Finding codes:
#   MISSING-FILE        a canonical file is absent
#   NO-HEADER           file does not start with a `---` frontmatter fence
#   BAD-HEADER-KIND     `dossier-header` missing or not internal-v1 / public-v1
#   MISSING-FIELD       a required header field is absent
#   EMPTY-FIELD         a required header field is empty or still `{fill}`
#   BAD-ENUM            status or confidentiality outside its enum
#   BAD-DATE            last-verified / last-updated not YYYY-MM-DD
#   LEAKED-FIELD        an internal-only key present in a public-v1 header
#   TITLE-MISMATCH      frontmatter title does not match the H1
#   NO-H1               body line 1 is not an H1
#   NO-CONTRACT         body line 2 is not a `<!-- contract: -->` pointer
#   CONTRACT-FILE       the referenced contract file does not exist
#   CONTRACT-ANCHOR     the referenced anchor is not a heading in that file
#   DEAD-LINK           an internal markdown link target does not exist
#   DEAD-RELATED        a `related:` entry does not exist
#
# Exit:
#   0 — no findings
#   1 — findings present
#   2 — infrastructure error (missing argument, unreadable root or references)

set -uo pipefail

OUTPUT_ROOT=""
REF_ROOT=""
QUIET=0

CANONICAL_FILES="
00-control/documentation-index.md
00-control/evidence-ledger.md
00-control/assumptions-questions-and-contradictions.md
00-control/claim-and-disclosure-register.md
00-control/terminology-and-ownership.md
01-project/executive-project-brief.md
01-project/product-and-domain.md
02-architecture/system-architecture.md
02-architecture/components-and-codebase.md
02-architecture/data-and-ai.md
02-architecture/interfaces-and-integrations.md
02-architecture/infrastructure-and-deployment.md
03-assurance/security-privacy-and-compliance.md
03-assurance/reliability-performance-and-observability.md
03-assurance/testing-quality-and-delivery.md
04-operating/onboarding-and-local-development.md
04-operating/operations-and-incident-response.md
04-operating/decisions-technical-debt-and-risks.md
05-due-diligence/technical-due-diligence-report.md
05-due-diligence/assets-dependencies-and-licenses.md
06-public/technical-partner-guide.md
06-public/customer-product-and-trust-guide.md
07-verification/documentation-verification-report.md
"

INTERNAL_FIELDS="dossier-header title purpose audience confidentiality owner status project-version last-verified review-trigger related"
PUBLIC_FIELDS="dossier-header title audience product-version last-updated"
INTERNAL_ONLY_FIELDS="purpose confidentiality owner status project-version last-verified review-trigger related"

while [ $# -gt 0 ]; do
  case "${1:-}" in
    --output-root)
      [ $# -lt 2 ] && { echo "dossier-package-check: --output-root requires a value" >&2; exit 2; }
      OUTPUT_ROOT="$2"; shift 2 ;;
    --references)
      [ $# -lt 2 ] && { echo "dossier-package-check: --references requires a value" >&2; exit 2; }
      REF_ROOT="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help)
      sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    --) shift; break ;;
    *)
      echo "dossier-package-check: unknown argument: $1" >&2
      echo "Usage: $0 --output-root <path> [--references <dir>] [--quiet]" >&2
      exit 2 ;;
  esac
done

if [ -z "$OUTPUT_ROOT" ]; then
  echo "dossier-package-check: missing --output-root. Usage: $0 --output-root <path> [--references <dir>] [--quiet]" >&2
  exit 2
fi

if [ ! -d "$OUTPUT_ROOT" ]; then
  echo "dossier-package-check: output root not found or not a directory: $OUTPUT_ROOT" >&2
  exit 2
fi

if [ -z "$REF_ROOT" ]; then
  SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
  for CANDIDATE in \
    "${CLAUDE_PLUGIN_ROOT:-}" \
    "${SCRIPT_DIR:-}/.." \
    "plugins/dossier"
  do
    [ -z "$CANDIDATE" ] && continue
    if [ -d "$CANDIDATE/references" ]; then
      REF_ROOT=$(cd -- "$CANDIDATE" 2>/dev/null && pwd)
      break
    fi
  done
fi

if [ -z "$REF_ROOT" ] || [ ! -d "$REF_ROOT/references" ]; then
  echo "dossier-package-check: references directory not found (looked at CLAUDE_PLUGIN_ROOT, script dir, and plugins/dossier)" >&2
  exit 2
fi

FINDINGS_FILE=$(mktemp -t dossier-check.XXXXXX) || {
  echo "dossier-package-check: cannot create temp file" >&2; exit 2;
}
: >"$FINDINGS_FILE"
trap 'rm -f "$FINDINGS_FILE" 2>/dev/null' EXIT

FILES_PRESENT=0
FILES_MISSING=0
HEADERS_OK=0
LINKS_CHECKED=0
POINTERS_CHECKED=0

record() {
  # record <code> <path> <detail>
  printf 'FINDING %s %s — %s\n' "$1" "$2" "$3" >>"$FINDINGS_FILE"
}

# Emit `key<TAB>value` for each frontmatter key. Block-list items are folded into
# the preceding key's value, comma-separated, so `related` parses the same way in
# both YAML list forms.
parse_frontmatter() {
  awk '
    NR == 1 { if ($0 != "---") exit 0; infm = 1; next }
    infm && $0 == "---" { exit 0 }
    infm {
      if ($0 ~ /^[ \t]*-[ \t]+/) {
        item = $0
        sub(/^[ \t]*-[ \t]+/, "", item)
        if (lastkey != "") vals[lastkey] = (vals[lastkey] == "" ? item : vals[lastkey] ", " item)
        next
      }
      if ($0 ~ /^[A-Za-z][A-Za-z0-9-]*:/) {
        key = $0; sub(/:.*/, "", key)
        val = $0; sub(/^[A-Za-z][A-Za-z0-9-]*:[ \t]*/, "", val)
        gsub(/[ \t]+$/, "", val)
        order[++n] = key
        vals[key] = val
        lastkey = key
      }
    }
    END { for (i = 1; i <= n; i++) printf "%s\t%s\n", order[i], vals[order[i]] }
  ' "$1"
}

fm_get() {
  # fm_get <parsed-frontmatter> <key>
  printf '%s\n' "$1" | awk -F'\t' -v k="$2" '$1 == k { print $2; found = 1; exit } END { if (!found) print "__DOSSIER_ABSENT__" }'
}

is_empty_value() {
  # A value is empty when blank, an unfilled placeholder, or an empty YAML list.
  case "$1" in
    ""|"{fill}"|"[]"|"''"|'""') return 0 ;;
  esac
  case "$1" in
    *"{fill}"*) return 0 ;;
  esac
  return 1
}

# GitHub heading-anchor transform: lowercase, drop everything but word chars,
# spaces and hyphens, then spaces to hyphens.
slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9 _-]//g; s/ /-/g'
}

for REL in $CANONICAL_FILES; do
  FILE="$OUTPUT_ROOT/$REL"

  if [ ! -f "$FILE" ]; then
    FILES_MISSING=$((FILES_MISSING + 1))
    record "MISSING-FILE" "$REL" "canonical file absent from the package"
    continue
  fi
  FILES_PRESENT=$((FILES_PRESENT + 1))

  FIRST_LINE=$(head -n 1 "$FILE")
  if [ "$FIRST_LINE" != "---" ]; then
    record "NO-HEADER" "$REL" "file does not begin with a '---' frontmatter fence"
    continue
  fi

  FM=$(parse_frontmatter "$FILE")
  KIND=$(fm_get "$FM" "dossier-header")

  case "$KIND" in
    internal-v1) REQUIRED="$INTERNAL_FIELDS"; DATE_KEY="last-verified" ;;
    public-v1)   REQUIRED="$PUBLIC_FIELDS";   DATE_KEY="last-updated" ;;
    *)
      record "BAD-HEADER-KIND" "$REL" "dossier-header is '$KIND' — expected internal-v1 or public-v1"
      continue ;;
  esac

  HEADER_CLEAN=1

  for FIELD in $REQUIRED; do
    VALUE=$(fm_get "$FM" "$FIELD")
    if [ "$VALUE" = "__DOSSIER_ABSENT__" ]; then
      record "MISSING-FIELD" "$REL" "required header field '$FIELD' is absent"
      HEADER_CLEAN=0
      continue
    fi
    # `related: []` is the documented legitimate empty for the index only.
    if [ "$FIELD" = "related" ] && [ "$VALUE" = "[]" ] && [ "$REL" = "00-control/documentation-index.md" ]; then
      continue
    fi
    if is_empty_value "$VALUE"; then
      record "EMPTY-FIELD" "$REL" "header field '$FIELD' is empty or still an unfilled {fill} placeholder"
      HEADER_CLEAN=0
    fi
  done

  if [ "$KIND" = "public-v1" ]; then
    for FIELD in $INTERNAL_ONLY_FIELDS; do
      VALUE=$(fm_get "$FM" "$FIELD")
      if [ "$VALUE" != "__DOSSIER_ABSENT__" ]; then
        record "LEAKED-FIELD" "$REL" "internal-only header field '$FIELD' present in a public document"
        HEADER_CLEAN=0
      fi
    done
  fi

  if [ "$KIND" = "internal-v1" ]; then
    STATUS=$(fm_get "$FM" "status")
    case "$STATUS" in
      verified|"partially verified"|draft|"N/A"|__DOSSIER_ABSENT__) ;;
      *) record "BAD-ENUM" "$REL" "status '$STATUS' is not one of: verified, partially verified, draft, N/A"
         HEADER_CLEAN=0 ;;
    esac
    CONF=$(fm_get "$FM" "confidentiality")
    case "$CONF" in
      Public|Partner-Confidential|Internal|Restricted|__DOSSIER_ABSENT__) ;;
      *) record "BAD-ENUM" "$REL" "confidentiality '$CONF' is not one of: Public, Partner-Confidential, Internal, Restricted"
         HEADER_CLEAN=0 ;;
    esac
  fi

  DATE_VALUE=$(fm_get "$FM" "$DATE_KEY")
  if [ "$DATE_VALUE" != "__DOSSIER_ABSENT__" ] && ! is_empty_value "$DATE_VALUE"; then
    case "$DATE_VALUE" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
      *) record "BAD-DATE" "$REL" "$DATE_KEY '$DATE_VALUE' is not an ISO YYYY-MM-DD date"
         HEADER_CLEAN=0 ;;
    esac
  fi

  [ "$HEADER_CLEAN" -eq 1 ] && HEADERS_OK=$((HEADERS_OK + 1))

  # --- body: line 1 is the H1, line 2 is the contract pointer ---
  FM_END=$(awk 'NR > 1 && $0 == "---" { print NR; exit }' "$FILE")
  if [ -z "$FM_END" ]; then
    record "NO-HEADER" "$REL" "frontmatter has no closing '---' fence"
    continue
  fi

  BODY1=$(sed -n "$((FM_END + 1))p" "$FILE")
  BODY2=$(sed -n "$((FM_END + 2))p" "$FILE")

  case "$BODY1" in
    "# "*)
      H1_TEXT=${BODY1#\# }
      TITLE=$(fm_get "$FM" "title")
      if [ "$TITLE" != "__DOSSIER_ABSENT__" ] && ! is_empty_value "$TITLE" && [ "$TITLE" != "$H1_TEXT" ]; then
        record "TITLE-MISMATCH" "$REL" "frontmatter title '$TITLE' does not match H1 '$H1_TEXT'"
      fi ;;
    *) record "NO-H1" "$REL" "body line 1 is not an H1 heading" ;;
  esac

  case "$BODY2" in
    "<!-- contract: "*" -->")
      POINTERS_CHECKED=$((POINTERS_CHECKED + 1))
      POINTER=${BODY2#<!-- contract: }
      POINTER=${POINTER% -->}
      CONTRACT_PATH=${POINTER%%#*}
      CONTRACT_ANCHOR=${POINTER#*#}
      if [ ! -f "$REF_ROOT/$CONTRACT_PATH" ]; then
        record "CONTRACT-FILE" "$REL" "contract pointer targets '$CONTRACT_PATH', which does not exist under $REF_ROOT"
      elif [ "$CONTRACT_ANCHOR" = "$POINTER" ]; then
        record "CONTRACT-ANCHOR" "$REL" "contract pointer '$POINTER' carries no #anchor"
      else
        ANCHOR_FOUND=0
        while IFS= read -r HEADING; do
          HEADING=${HEADING#\#\# }
          [ "$(slugify "$HEADING")" = "$CONTRACT_ANCHOR" ] && { ANCHOR_FOUND=1; break; }
        done <<EOF
$(grep '^## ' "$REF_ROOT/$CONTRACT_PATH" 2>/dev/null)
EOF
        [ "$ANCHOR_FOUND" -eq 0 ] && record "CONTRACT-ANCHOR" "$REL" "anchor '#$CONTRACT_ANCHOR' has no matching '## ' heading in $CONTRACT_PATH"
      fi ;;
    *) record "NO-CONTRACT" "$REL" "body line 2 is not a '<!-- contract: ... -->' pointer" ;;
  esac

  # --- related: entries must resolve inside the package ---
  RELATED=$(fm_get "$FM" "related")
  if [ "$RELATED" != "__DOSSIER_ABSENT__" ]; then
    RELATED=${RELATED#[}
    RELATED=${RELATED%]}
    OLD_IFS=$IFS
    IFS=','
    set -f            # same reason as the ledger cell split: no globbing
    for ENTRY in $RELATED; do
      ENTRY=$(printf '%s' "$ENTRY" | sed 's/^[ \t]*//; s/[ \t]*$//; s/^["'"'"']//; s/["'"'"']$//')
      [ -z "$ENTRY" ] && continue
      case "$ENTRY" in "{fill}"*) continue ;; esac
      if [ ! -e "$OUTPUT_ROOT/$ENTRY" ]; then
        record "DEAD-RELATED" "$REL" "related entry '$ENTRY' does not exist under the output root"
      fi
    done
    set +f            # restore globbing; leaving it off leaks to the whole script
    IFS=$OLD_IFS
  fi

  # --- internal markdown links, outside fenced code blocks ---
  DIR=$(dirname "$REL")
  while IFS= read -r TARGET; do
    [ -z "$TARGET" ] && continue
    LINKS_CHECKED=$((LINKS_CHECKED + 1))
    TARGET_PATH=${TARGET%%#*}
    [ -z "$TARGET_PATH" ] && continue
    if [ "$DIR" = "." ]; then
      RESOLVED="$OUTPUT_ROOT/$TARGET_PATH"
    else
      RESOLVED="$OUTPUT_ROOT/$DIR/$TARGET_PATH"
    fi
    [ -e "$RESOLVED" ] || record "DEAD-LINK" "$REL" "link target '$TARGET_PATH' does not resolve"
  done <<EOF
$(awk '
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    {
      line = $0
      while (match(line, /\]\([^)]*\)/)) {
        target = substr(line, RSTART + 2, RLENGTH - 3)
        line = substr(line, RSTART + RLENGTH)
        if (target ~ /^https?:/) continue
        if (target ~ /^mailto:/) continue
        if (target ~ /^#/) continue
        if (target ~ /\{fill\}/) continue
        print target
      }
    }
  ' "$FILE")
EOF
done

# --- Diagram coverage --------------------------------------------------------
# A template that opens a ```mermaid fence is asking for a diagram at that point
# in that document. Nothing else compares the request against the answer: the
# gate counts fences and checks the ones present are balanced, which grades the
# diagrams that were drawn and is silent about the ones that were not. A drafter
# can skip every prompt and the package still reports a clean diagram check.
#
# Equality is not required — a drafter may merge two views or add one the
# template never asked for. What is required is that a document the contract
# wants illustrated is not shipped with nothing.
DIAGRAMS_EXPECTED=0
DIAGRAMS_PRESENT=0
TPL_ROOT="$REF_ROOT/templates/package"

if [ -d "$TPL_ROOT" ]; then
  for REL in $CANONICAL_FILES; do
    TPL="$TPL_ROOT/$REL"
    DOC="$OUTPUT_ROOT/$REL"
    [ -f "$TPL" ] || continue
    WANT=$(grep -c '^```mermaid' "$TPL" 2>/dev/null || true)
    [ -z "$WANT" ] && WANT=0
    [ "$WANT" -eq 0 ] && continue
    DIAGRAMS_EXPECTED=$((DIAGRAMS_EXPECTED + WANT))

    [ -f "$DOC" ] || continue
    HAVE=$(grep -c '^```mermaid' "$DOC" 2>/dev/null || true)
    [ -z "$HAVE" ] && HAVE=0
    DIAGRAMS_PRESENT=$((DIAGRAMS_PRESENT + HAVE))
    if [ "$HAVE" -eq 0 ]; then
      record DIAGRAM_MISSING "$REL" \
        "template asks for $WANT diagram(s); the document has none"
    fi
  done
else
  DIAGRAMS_EXPECTED="unknown"
  DIAGRAMS_PRESENT="unknown"
fi

TOTAL=$(wc -l <"$FINDINGS_FILE" | tr -d ' ')

printf 'CHECK_ROOT=%s\n' "$OUTPUT_ROOT"
printf 'CHECK_REFERENCES=%s\n' "$REF_ROOT"
printf 'CHECK_FILES_EXPECTED=23\n'
printf 'CHECK_FILES_PRESENT=%s\n' "$FILES_PRESENT"
printf 'CHECK_FILES_MISSING=%s\n' "$FILES_MISSING"
printf 'CHECK_HEADERS_OK=%s\n' "$HEADERS_OK"
printf 'CHECK_POINTERS_CHECKED=%s\n' "$POINTERS_CHECKED"
printf 'CHECK_LINKS_CHECKED=%s\n' "$LINKS_CHECKED"
printf 'CHECK_DIAGRAMS_EXPECTED=%s\n' "$DIAGRAMS_EXPECTED"
printf 'CHECK_DIAGRAMS_PRESENT=%s\n' "$DIAGRAMS_PRESENT"
printf 'CHECK_FINDINGS=%s\n' "$TOTAL"

if [ "$TOTAL" -eq 0 ]; then
  printf 'CHECK_RESULT=CLEAN\n'
  rm -f "$FINDINGS_FILE" 2>/dev/null
  exit 0
fi

printf 'CHECK_RESULT=FINDINGS\n'
[ "$QUIET" -eq 0 ] && cat "$FINDINGS_FILE"
rm -f "$FINDINGS_FILE" 2>/dev/null
exit 1
