#!/usr/bin/env bash
# dossier-managed-file.sh — the managed-file contract.
#
# Setup writes into `.github/`, which is a directory people edit by hand. A
# generator that rewrites those files on every run eventually destroys someone's
# work; a generator that refuses to touch anything it did not create is useless
# after the first upgrade. The stamp resolves that: it records the hash of the
# body as generated, so a later run can tell the difference between a file it
# wrote and still owns, a file it wrote that a human has since edited, and a
# file it never wrote at all.
#
# The stamp is the first line of the file:
#
#   # dossier:managed v1 sha256=<sha256 of everything below this line>
#   <!-- dossier:managed v1 sha256=<...> -->
#
# Usage:
#   dossier-managed-file.sh --verify <path>
#   dossier-managed-file.sh --stamp  <path> [--comment hash|html]
#
# Flags:
#   --verify <path>    print MANAGED=absent|clean|dirty|foreign and exit 0
#   --stamp <path>     (re)write the stamp so it matches the current body
#   --comment <style>  force the comment syntax instead of inferring it from the
#                      file extension. `hash` for YAML and shell, `html` for
#                      Markdown and HTML.
#
# Output:
#   --verify: MANAGED=<state>  BODY_SHA256=<hash>  STAMP_SHA256=<hash>
#   --stamp:  STAMPED=<path>   BODY_SHA256=<hash>  COMMENT_STYLE=<style>
#
# Exit:
#   0 — the state was determined, or the stamp was written
#   1 — the file could not be read or written, or no sha256 tool exists
#   2 — missing or invalid argument

set -uo pipefail

MODE=""
TARGET=""
COMMENT_STYLE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --verify)
      [ $# -lt 2 ] && { echo "dossier-managed-file: --verify requires a path" >&2; exit 2; }
      [ -n "$MODE" ] && { echo "dossier-managed-file: --verify and --stamp are mutually exclusive" >&2; exit 2; }
      MODE="verify"; TARGET="$2"; shift 2 ;;
    --stamp)
      [ $# -lt 2 ] && { echo "dossier-managed-file: --stamp requires a path" >&2; exit 2; }
      [ -n "$MODE" ] && { echo "dossier-managed-file: --verify and --stamp are mutually exclusive" >&2; exit 2; }
      MODE="stamp"; TARGET="$2"; shift 2 ;;
    --comment)
      [ $# -lt 2 ] && { echo "dossier-managed-file: --comment requires a value" >&2; exit 2; }
      COMMENT_STYLE="$2"; shift 2 ;;
    -h|--help) sed -n '2,38p' "$0"; exit 0 ;;
    *) echo "dossier-managed-file: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$MODE" ] || { echo "dossier-managed-file: one of --verify or --stamp is required" >&2; exit 2; }
case "${COMMENT_STYLE:-hash}" in
  hash|html) : ;;
  *) echo "dossier-managed-file: --comment must be 'hash' or 'html'" >&2; exit 2 ;;
esac

STAMP_VERSION="v1"
STAMP_MARKER="dossier:managed"

sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum 2>/dev/null | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 2>/dev/null | awk '{print $1}'
  else
    printf ''
  fi
}

# Inferred from the extension rather than sniffed from the content: a Markdown
# file whose first line happens to start with `#` is a heading, not a comment,
# and guessing wrong would corrupt the document it is meant to protect.
infer_comment_style() {
  case "$1" in
    *.md|*.markdown|*.mdx|*.html|*.htm) printf 'html' ;;
    *.json|*.jsonc)                     printf 'json' ;;
    *)                                  printf 'hash' ;;
  esac
}

if [ -z "$COMMENT_STYLE" ]; then
  COMMENT_STYLE=$(infer_comment_style "$TARGET")
fi
if [ "$COMMENT_STYLE" = "json" ]; then
  echo "dossier-managed-file: '$TARGET' looks like JSON, which has no comment syntax that can carry the stamp. Track its provenance elsewhere, or pass --comment explicitly if the format tolerates one." >&2
  exit 2
fi

# The stamp line matched loosely enough to survive a reformat that changes
# spacing, and strictly enough that a line merely mentioning the marker in prose
# is not mistaken for one.
STAMP_RE="^([[:space:]]*#|<!--)[[:space:]]*${STAMP_MARKER}[[:space:]]+v[0-9]+[[:space:]]+sha256=[0-9a-f]{64}"

render_stamp() {
  # $1 = hash
  case "$COMMENT_STYLE" in
    html) printf '<!-- %s %s sha256=%s -->\n' "$STAMP_MARKER" "$STAMP_VERSION" "$1" ;;
    *)    printf '# %s %s sha256=%s\n' "$STAMP_MARKER" "$STAMP_VERSION" "$1" ;;
  esac
}

if [ "$MODE" = "verify" ]; then
  if [ ! -f "$TARGET" ]; then
    printf 'MANAGED=absent\n'
    printf 'BODY_SHA256=\n'
    printf 'STAMP_SHA256=\n'
    exit 0
  fi

  FIRST_LINE=$(head -n 1 "$TARGET" 2>/dev/null)
  if ! printf '%s\n' "$FIRST_LINE" | grep -qE "$STAMP_RE"; then
    printf 'MANAGED=foreign\n'
    printf 'BODY_SHA256=\n'
    printf 'STAMP_SHA256=\n'
    exit 0
  fi

  STAMP_SHA=$(printf '%s\n' "$FIRST_LINE" | grep -oE 'sha256=[0-9a-f]{64}' | head -1 | cut -d= -f2)
  BODY_SHA=$(tail -n +2 "$TARGET" 2>/dev/null | sha256_stdin)
  if [ -z "$BODY_SHA" ]; then
    echo "dossier-managed-file: no sha256 tool available (sha256sum or shasum)." >&2
    exit 1
  fi

  if [ "$STAMP_SHA" = "$BODY_SHA" ]; then
    printf 'MANAGED=clean\n'
  else
    printf 'MANAGED=dirty\n'
  fi
  printf 'BODY_SHA256=%s\n' "$BODY_SHA"
  printf 'STAMP_SHA256=%s\n' "$STAMP_SHA"
  exit 0
fi

# ---------------------------------------------------------------------------
# Stamp mode
# ---------------------------------------------------------------------------
[ -f "$TARGET" ] || { echo "dossier-managed-file: file not found: $TARGET" >&2; exit 1; }

TMPF=$(mktemp -t dossier-managed.XXXXXX 2>/dev/null) || TMPF="/tmp/dossier-managed.$$"
cleanup() { rm -f "$TMPF" "$TMPF.body" 2>/dev/null; }
trap cleanup EXIT

# A file that is already stamped is re-stamped over its existing body, so
# repeated runs converge instead of accumulating stamp lines.
FIRST_LINE=$(head -n 1 "$TARGET" 2>/dev/null)
if printf '%s\n' "$FIRST_LINE" | grep -qE "$STAMP_RE"; then
  tail -n +2 "$TARGET" >"$TMPF.body" 2>/dev/null
else
  cat "$TARGET" >"$TMPF.body" 2>/dev/null
fi

BODY_SHA=$(sha256_stdin <"$TMPF.body")
if [ -z "$BODY_SHA" ]; then
  echo "dossier-managed-file: no sha256 tool available (sha256sum or shasum)." >&2
  exit 1
fi

render_stamp "$BODY_SHA" >"$TMPF" || { echo "dossier-managed-file: could not render the stamp." >&2; exit 1; }
cat "$TMPF.body" >>"$TMPF" || { echo "dossier-managed-file: could not assemble the stamped file." >&2; exit 1; }
cat "$TMPF" >"$TARGET" || { echo "dossier-managed-file: could not write $TARGET" >&2; exit 1; }

printf 'STAMPED=%s\n' "$TARGET"
printf 'BODY_SHA256=%s\n' "$BODY_SHA"
printf 'COMMENT_STYLE=%s\n' "$COMMENT_STYLE"
exit 0
