#!/bin/bash
# [dossier] PreToolUse hook: stop leakage into the public documents.
#
# A public document is an unretractable commitment. This hook scans pending
# content bound for 06-public/ and blocks credentials, internal locators, and
# register IDs before the write lands — the one place in the pipeline where
# the leak has not yet happened.
#
# Registration completeness (every sentence maps to an approved CL-#### row) is
# NOT enforced here. That check needs the whole rendered document and belongs to
# dossier-claim-scan.sh and verification pass C. This hook covers only what is
# decidable from the pending content alone, so it never blocks a legitimate
# in-progress draft.

set -uo pipefail

# Fails closed. A public document is unretractable, so the one place the leak
# has not yet happened is not a place to no-op on a missing dependency.
if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED: dossier cannot scan a public document for leakage without jq on PATH." >&2
  exit 2
fi

INPUT=$(cat)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

case "$FILE_PATH" in
  */06-public/*) ;;
  *) exit 0 ;;
esac

CONTENT=$(printf '%s' "$INPUT" | jq -r '
  (.tool_input.content // empty),
  (.tool_input.new_string // empty),
  ((.tool_input.edits // []) | map(.new_string // empty) | join("\n"))
' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0

HITS=""
check() { # class | regex
  # `--` is required, not decorative: private-key-block's own pattern starts
  # with a literal '-----BEGIN...', and without `--` grep parses it as an
  # (unrecognized) option instead of a pattern, exits 2, and the `if` reads
  # that as "no match" -- silently never blocking a private key. Mirrors
  # dossier-claim-scan.sh's cred_match_class(), which documents the same
  # requirement for the same reason.
  if printf '%s' "$CONTENT" | grep -qE -- "$2" 2>/dev/null; then
    HITS="$HITS
  - $1"
  fi
}

# aws-access-key, private-key-block, and connection-string are kept
# pattern-identical to dossier-claim-scan.sh's CRED_PATTERNS entries of the
# same name (issues #198, #210), not just tolerance-equivalent. A prior,
# documented bug (see the CRED_PATTERNS comment in dossier-claim-scan.sh)
# came from this exact kind of drift: this live pre-write hook and the batch
# scanner disagreeing on the same credential's shape, so one path redacted a
# match the other never even flagged. Do not hand-tune these three here --
# copy the fix from dossier-claim-scan.sh's CRED_PATTERNS array verbatim.
check "anthropic-key"        'sk-ant-[A-Za-z0-9_-]{8,}'
check "github-token"         '(ghp_|gho_|ghu_|ghs_|ghr_|github_pat_)[A-Za-z0-9_]{16,}'
check "aws-access-key"       'AKIA[ |,]?([0-9A-Z][ |,]?){16}'
check "slack-token"          'xox[baprs]-[A-Za-z0-9-]{10,}'
check "private-key-block"    '-----BEGIN[ |,]?[A-Z ,|]*P[ |,]?R[ |,]?I[ |,]?V[ |,]?A[ |,]?T[ |,]?E[ |,]?[[:space:]][ |,]?K[ |,]?E[ |,]?Y[ |,]?-----'
check "bearer-token"         '(Bearer|bearer)[[:space:]]+[A-Za-z0-9._-]{20,}'
check "connection-string"    '(postgres|postgresql|mysql|mongodb\+srv|redis|amqp)://[^[:space:]/]+:[ |,]?([^[:space:]@|,][ |,]?)+@'
check "secret-assignment"    '(api[_-]?key|secret|password|passwd|token|credential)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9/_+=-]{12,}'
check "internal-register-id" '\b(EV|AQ|CT|CL|TM)-[0-9]{4,}\b'
# disclosure-policy-levels.md names internal repository paths alongside register
# IDs as prohibited in 06-public/, and says this hook enforces it with
# dossier-claim-scan.sh. The pattern is the scanner's, so the live block and the
# batch scan agree rather than the hook deferring a class it never documented.
check "internal-path"        '(^|[[:space:](`])(src|internal|lib|app|infra|terraform|\.github)/[A-Za-z0-9_./-]+'
check "internal-hostname"    '\b[a-z0-9-]+\.(internal|local|corp|intranet|svc\.cluster\.local)\b'
check "private-ip"           '\b(10\.[0-9]{1,3}|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}\b'

# Project-specific patterns from disclosure.redactionPatterns.
RESOLVER="${CLAUDE_PLUGIN_ROOT:-plugins/dossier}/bin/dossier-resolve-config.sh"
if [ -x "$RESOLVER" ]; then
  PATTERNS=$("$RESOLVER" --compact --default '[]' dossier.disclosure.redactionPatterns 2>/dev/null)
  if [ -n "$PATTERNS" ] && [ "$PATTERNS" != "[]" ]; then
    while IFS= read -r pat; do
      [ -z "$pat" ] && continue
      check "configured-redaction" "$pat"
    done <<EOF
$(printf '%s' "$PATTERNS" | jq -r '.[]' 2>/dev/null)
EOF
  fi
fi

[ -z "$HITS" ] && exit 0

# The matched value is deliberately never printed — echoing it would copy the
# leak into a transcript that is itself shared.
cat >&2 <<EOF
BLOCKED: content bound for a public document matched a disclosure pattern.

  file: $FILE_PATH
  pattern classes:$HITS

Matched values are not shown; printing one would copy the leak into this log.

Public documents are derived from APPROVED rows of the claim and disclosure
register, then stripped of evidence IDs, internal locators, internal ownership,
and security-sensitive detail. Fix the source sentence rather than the symptom:
if a credential reached a draft, it is also in whatever the draft was copied from.
EOF
exit 2
