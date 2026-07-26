#!/usr/bin/env bash
# dossier-claim-scan.sh — disclosure safety scan for the public documents.
#
# Two independent checks over 06-public/ (or a supplied file):
#
#   A. LEAKAGE — content that must never cross the disclosure boundary:
#      credentials, internal locators, evidence and register IDs, internal
#      hostnames, plus any project-specific disclosure.redactionPatterns.
#   B. REGISTRATION — every declarative sentence must map to an approved
#      CL-#### row in the claim and disclosure register.
#
# Check B is intentionally recall-oriented. It reports sentences it cannot
# match, and a human or the disclosure-gating skill adjudicates. A scanner that
# only flagged certain violations would miss the ones that matter, and the cost
# of a false positive here is one review; the cost of a false negative is an
# unretractable public claim.
#
# A matched secret value is NEVER printed. Only the file, line, and pattern
# class — printing the value would copy the leak into the log that gets shared.
#
# Usage:
#   dossier-claim-scan.sh [--output-root <path>] [--file <path>] [--json] [--quiet]
#
# Exit: 0 clean · 1 registration gaps only · 2 leakage detected or infra error

set -uo pipefail

SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
RESOLVER="$SELF_DIR/dossier-resolve-config.sh"

OUTPUT_ROOT=""
SINGLE_FILE=""
WANT_JSON=0
QUIET=0

while [ $# -gt 0 ]; do
  case "${1:-}" in
    --output-root)
      [ $# -lt 2 ] && { echo "dossier-claim-scan: --output-root requires a path" >&2; exit 2; }
      OUTPUT_ROOT="$2"; shift 2 ;;
    --file)
      [ $# -lt 2 ] && { echo "dossier-claim-scan: --file requires a path" >&2; exit 2; }
      SINGLE_FILE="$2"; shift 2 ;;
    --json) WANT_JSON=1; shift ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "dossier-claim-scan: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$OUTPUT_ROOT" ]; then
  if [ -x "$RESOLVER" ]; then
    OUTPUT_ROOT=$("$RESOLVER" --default "docs/dossier" dossier.project.outputRoot)
  else
    OUTPUT_ROOT="docs/dossier"
  fi
fi

CLAIMS="$OUTPUT_ROOT/00-control/claim-and-disclosure-register.md"

if [ -n "$SINGLE_FILE" ]; then
  [ -f "$SINGLE_FILE" ] || { echo "dossier-claim-scan: no such file: $SINGLE_FILE" >&2; exit 2; }
  TARGETS="$SINGLE_FILE"
else
  PUBDIR="$OUTPUT_ROOT/06-public"
  if [ ! -d "$PUBDIR" ]; then
    echo "CLAIM_SCAN=blocked"
    echo "CLAIM_SCAN_ERROR=no public directory at $PUBDIR"
    exit 2
  fi
  TARGETS=$(find "$PUBDIR" -name '*.md' -type f | sort)
fi

LEAKS=0
UNREGISTERED=0
PROHIBITED=0
HITS_FILE=$(mktemp -t dossier-claim-scan.XXXXXX) || {
  echo "dossier-claim-scan: cannot create temp file" >&2; exit 2; }
trap 'rm -f "$HITS_FILE" 2>/dev/null' EXIT

hit() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$HITS_FILE"; }

# --- Pattern classes ---------------------------------------------------------
# Named so a finding can identify the class without echoing the match.
# Baseline aligned with the flow plugin's block-secrets hook, extended with
# provider-specific prefixes.
scan_class() { # file | class | severity | regex
  local f="$1" class="$2" sev="$3" re="$4"
  local out
  # `--` terminates option parsing: several patterns below start with a hyphen
  # (the PEM armour), and without it grep reads the pattern as flags.
  out=$(grep -nE -- "$re" "$f" 2>/dev/null | cut -d: -f1) || return 0
  local ln
  for ln in $out; do
    hit "$sev" "$f" "$ln" "$class"
    case "$sev" in
      leak) LEAKS=$((LEAKS + 1)) ;;
      prohibited) PROHIBITED=$((PROHIBITED + 1)) ;;
    esac
  done
}

for f in $TARGETS; do
  # --- A. Leakage ---
  scan_class "$f" "anthropic-key"      leak 'sk-ant-[A-Za-z0-9_-]{8,}'
  scan_class "$f" "github-token"       leak '(ghp_|gho_|ghu_|ghs_|ghr_|github_pat_)[A-Za-z0-9_]{16,}'
  scan_class "$f" "aws-access-key"     leak 'AKIA[0-9A-Z]{16}'
  scan_class "$f" "slack-token"        leak 'xox[baprs]-[A-Za-z0-9-]{10,}'
  scan_class "$f" "private-key-block"  leak '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  scan_class "$f" "generic-secret-assignment" leak \
    '(api[_-]?key|secret|password|passwd|token|credential)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9/_+=-]{12,}'
  scan_class "$f" "bearer-token"       leak 'Bearer[[:space:]]+[A-Za-z0-9._-]{20,}'
  scan_class "$f" "connection-string"  leak '(postgres|postgresql|mysql|mongodb\+srv|redis|amqp)://[^[:space:]/]+:[^[:space:]@]+@'
  # Internal locators: evidence and register IDs must never appear publicly —
  # they expose the internal register structure and are useless to a reader.
  scan_class "$f" "internal-evidence-id"  leak '\b(EV|AQ|CT|CL|TM)-[0-9]{4,}\b'
  scan_class "$f" "internal-path"      leak '(^|[[:space:](`])(src|internal|lib|app|infra|terraform|\.github)/[A-Za-z0-9_./-]+'
  scan_class "$f" "internal-hostname"  leak '\b[a-z0-9-]+\.(internal|local|corp|intranet|svc\.cluster\.local)\b'
  scan_class "$f" "private-ip"         leak '\b(10\.[0-9]{1,3}|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}\b'

  # --- Prohibited vocabulary ---
  # A claim, not an adjective. Each needs defined scope and evidence, so each
  # occurrence is surfaced for adjudication rather than auto-failed.
  scan_class "$f" "prohibited-vocabulary" prohibited \
    '\b(bank-grade|military-grade|enterprise-ready|fully automated|zero[- ]downtime|unlimited|100% (secure|reliable|uptime)|never been (compromised|breached)|completely (secure|private|anonymous))\b'
done

# --- Project-specific redaction patterns -------------------------------------
if [ -x "$RESOLVER" ]; then
  PATTERNS=$("$RESOLVER" --compact --default '[]' dossier.disclosure.redactionPatterns 2>/dev/null)
  if [ -n "$PATTERNS" ] && [ "$PATTERNS" != "[]" ] && command -v jq >/dev/null 2>&1; then
    while IFS= read -r pat; do
      [ -z "$pat" ] && continue
      for f in $TARGETS; do
        scan_class "$f" "configured-redaction" leak "$pat"
      done
    done <<EOF
$(printf '%s' "$PATTERNS" | jq -r '.[]' 2>/dev/null)
EOF
  fi
fi

# --- B. Registration ---------------------------------------------------------
# Approved wordings from the claim register. Column 2 is the proposed wording;
# the Status column must be `approved`.
APPROVED_FILE=$(mktemp -t dossier-approved.XXXXXX) || {
  echo "dossier-claim-scan: cannot create temp file" >&2; exit 2; }
trap 'rm -f "$HITS_FILE" "$APPROVED_FILE" 2>/dev/null' EXIT

normalize() { # strip markdown emphasis/code/links, collapse space, lowercase
  sed -e 's/`[^`]*`/ /g' -e 's/\[\([^]]*\)\]([^)]*)/\1/g' \
      -e 's/[*_#>]//g' -e 's/[[:space:]]\{1,\}/ /g' \
      -e 's/^ //' -e 's/ $//' | tr '[:upper:]' '[:lower:]'
}

REGISTER_PRESENT=0
if [ -f "$CLAIMS" ]; then
  REGISTER_PRESENT=1
  # Approved wordings go through the SAME normalization as document sentences.
  # Lowercasing alone left the register's markdown intact while the document side
  # had it stripped, so any claim containing a code span, bold, or a link could
  # never match its own approved row — the check could not pass for a realistic
  # claim, and every such sentence was reported as unregistered.
  # Every CL- row except those in a rejected/withdrawn section. That table has a
  # different column layout, and the approval test below is a literal substring
  # match with no column awareness — a free-text cell there containing
  # "| approved |" would be read as an approved claim. Excluding the section
  # that cannot hold approvals is robust to a register that names its inventory
  # heading differently; requiring a specific inventory heading would silently
  # stop recognising approvals in any register that did.
  awk '
    /^## / { skip = ($0 ~ /^## *(Rejected|Withdrawn)/) ? 1 : 0 }
    !skip && /^\| *CL-/ { print }
  ' "$CLAIMS" 2>/dev/null | while IFS= read -r row; do
    case "$row" in
      *"| approved |"*|*"|approved|"*) ;;
      *) continue ;;
    esac
    printf '%s' "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$3); print $3}' | normalize
  done >> "$APPROVED_FILE"

  # Required qualifications are approved text too, and the contract *mandates*
  # that they appear in the public document beside the claim they qualify. They
  # carry no `approved` cell of their own, so matching only claim rows made every
  # mandated qualification an unregistered sentence — the register requiring a
  # sentence the scan then reported. Column 2 of that table is the qualification.
  awk '
    /^## Required qualifications/ { inq = 1; next }
    inq && /^## / { inq = 0 }
    inq && /^\| *CL-/ {
      n = split($0, f, "|")
      if (n >= 3) { gsub(/^[ \t]+|[ \t]+$/, "", f[3]); print f[3] }
    }
  ' "$CLAIMS" 2>/dev/null | normalize >> "$APPROVED_FILE"
fi

# Redact credential-shaped substrings before any sentence text is echoed.
#
# The unregistered-sentence report quotes the document, and a sentence can
# contain both an unregistered claim AND a credential. Without this, the tool
# that exists to stop leaks would copy the leak into its own output — which is
# then pasted into a CI log, an issue, or a review comment.
redact() {
  sed -E \
    -e 's/sk-ant-[A-Za-z0-9_-]{8,}/[REDACTED:anthropic-key]/g' \
    -e 's/(ghp_|gho_|ghu_|ghs_|ghr_|github_pat_)[A-Za-z0-9_]{16,}/[REDACTED:github-token]/g' \
    -e 's/AKIA[0-9A-Z]{16}/[REDACTED:aws-access-key]/g' \
    -e 's/xox[baprs]-[A-Za-z0-9-]{10,}/[REDACTED:slack-token]/g' \
    -e 's/(Bearer|bearer)[[:space:]]+[A-Za-z0-9._-]{20,}/[REDACTED:bearer-token]/g' \
    -e 's#(postgres|postgresql|mysql|mongodb\+srv|redis|amqp)://[^[:space:]/]+:[^[:space:]@]+@#[REDACTED:connection-string]@#g' \
    -e 's/(api[_-]?key|secret|password|passwd|token|credential)([[:space:]]*[:=][[:space:]]*)["'"'"']?[A-Za-z0-9\/_+=-]{12,}/\1\2[REDACTED:secret-assignment]/g' \
    -e 's/-----BEGIN [A-Z ]*PRIVATE KEY-----/[REDACTED:private-key-block]/g'
}

for f in $TARGETS; do
  IN_FENCE=0
  # The header is structured metadata, not prose. `title:` and `audience:` are
  # long enough to clear the word floor and match no approved wording, so every
  # public document would report two unregistered "sentences" that no drafter
  # could ever resolve — noise that trains a reader to ignore the real findings.
  # A document opening with `---` is in its header until the closing fence.
  IN_HEADER=0
  FIRST_LINE=1
  LN=0
  while IFS= read -r line; do
    LN=$((LN + 1))
    if [ "$FIRST_LINE" -eq 1 ]; then
      FIRST_LINE=0
      if [ "$line" = "---" ]; then IN_HEADER=1; continue; fi
    elif [ "$IN_HEADER" -eq 1 ]; then
      [ "$line" = "---" ] && IN_HEADER=0
      continue
    fi
    case "$line" in
      '```'*) IN_FENCE=$((1 - IN_FENCE)); continue ;;
    esac
    [ "$IN_FENCE" -eq 1 ] && continue
    case "$line" in
      ''|'#'*|'|'*|'---'*|'<!--'*|'- '*|'* '*|'> '*) continue ;;
    esac

    # One sentence per check. Declarative only: a heading or a fragment is not
    # a claim, and flagging them would drown the real findings.
    #
    # Code spans come out BEFORE the split. A bare `tr '.' '\n'` cuts inside
    # `SKILL.md`, `plugin.json`, and `3.2.2`, producing fragments like
    # "md` is not a skill" — reported as unregistered claims that no drafter
    # could resolve, because they are not sentences.
    SPLITTABLE=$(printf '%s' "$line" | sed 's/`[^`]*`/ /g')
    printf '%s\n' "$SPLITTABLE" | tr '.' '\n' | while IFS= read -r sentence; do
      norm=$(printf '%s' "$sentence" | normalize)
      [ -z "$norm" ] && continue
      words=$(printf '%s' "$norm" | wc -w | tr -d ' ')
      [ "$words" -lt 4 ] && continue

      if [ "$REGISTER_PRESENT" -eq 1 ] && [ -s "$APPROVED_FILE" ]; then
        if grep -qF "$norm" "$APPROVED_FILE" 2>/dev/null; then
          continue
        fi
      fi
      # Redact the ORIGINAL sentence, not the normalized one. `normalize`
      # lowercases, and two of the credential patterns are case-sensitive by
      # construction — `AKIA[0-9A-Z]{16}` and the PEM header cannot match text
      # that has already been folded to lower case. Redacting after normalizing
      # therefore printed AWS keys and private-key headers into the findings
      # output verbatim-but-lowercased: still recognisable, still reconstructable,
      # and destined for a CI log. This is the exact failure the redactor exists
      # to prevent, so the excerpt is built from the raw sentence.
      printf 'unregistered\t%s\t%s\t%s\n' "$f" "$LN" \
        "$(printf '%s' "$sentence" | redact | normalize | cut -c1-80)" >> "$HITS_FILE"
    done
  done < "$f"
done

UNREGISTERED=$(grep -c '^unregistered' "$HITS_FILE" 2>/dev/null || true)
[ -z "$UNREGISTERED" ] && UNREGISTERED=0

# --- Report ------------------------------------------------------------------
if [ "$WANT_JSON" -eq 1 ]; then
  printf '{"leaks":%s,"prohibited":%s,"unregistered":%s,"register_present":%s,"hits":[' \
    "$LEAKS" "$PROHIBITED" "$UNREGISTERED" "$REGISTER_PRESENT"
  first=1
  while IFS=$'\t' read -r sev file ln detail; do
    [ $first -eq 0 ] && printf ','
    first=0
    esc=$(printf '%s' "$detail" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    printf '{"severity":"%s","file":"%s","line":%s,"detail":"%s"}' "$sev" "$file" "$ln" "$esc"
  done < "$HITS_FILE"
  printf ']}\n'
elif [ "$QUIET" -eq 0 ]; then
  echo "CLAIM_SCAN_LEAKS=$LEAKS"
  echo "CLAIM_SCAN_PROHIBITED_VOCABULARY=$PROHIBITED"
  echo "CLAIM_SCAN_UNREGISTERED_SENTENCES=$UNREGISTERED"
  echo "CLAIM_SCAN_REGISTER_PRESENT=$REGISTER_PRESENT"
  if [ -s "$HITS_FILE" ]; then
    echo ""
    echo "Findings (matched values are never printed):"
    while IFS=$'\t' read -r sev file ln detail; do
      case "$sev" in
        leak)         printf '  [LEAK]         %s:%s pattern class: %s\n' "$file" "$ln" "$detail" ;;
        prohibited)   printf '  [VOCABULARY]   %s:%s %s — needs defined scope and evidence\n' "$file" "$ln" "$detail" ;;
        unregistered) printf '  [UNREGISTERED] %s:%s "%s..."\n' "$file" "$ln" "$detail" ;;
      esac
    done < "$HITS_FILE"
  fi
  if [ "$REGISTER_PRESENT" -eq 0 ]; then
    echo ""
    echo "NOTE: no claim register at $CLAIMS — every public sentence is unregistered by definition."
  fi
fi

[ "$LEAKS" -gt 0 ] && exit 2
[ "$UNREGISTERED" -gt 0 ] && exit 1
[ "$PROHIBITED" -gt 0 ] && exit 1
exit 0
