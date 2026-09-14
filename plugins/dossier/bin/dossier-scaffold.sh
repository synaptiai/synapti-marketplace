#!/usr/bin/env bash
# dossier-scaffold.sh — create the canonical 8-directory / 23-file documentation
# package under an output root by copying the plugin's templates.
#
# Idempotent, but overwrite-safety is conditional, not absolute: an existing file
# whose first line is exactly "---" (frontmatter-fenced) is left untouched and
# reported SKIPPED. An existing file that is empty, or lacks that fence, is
# treated as damaged — a process killed mid-write, or content placed at a
# canonical path by hand — and is overwritten, reported REPAIRED (never
# CREATED). Re-running after a partial scaffold fills gaps and repairs damage;
# it does not preserve arbitrary non-fenced content at a canonical path.
#
# A README.md signpost is written at the output root alongside the canonical 23.
# It is supplemental, not canonical: it asserts no fact about the project, so it
# cannot go stale, and it exists only because a reader who browses the output
# root otherwise lands on eight numbered directories with no entry point. The
# index remains the control plane; the README points at it.
#
# Usage:
#   dossier-scaffold.sh --output-root <path> [--dry-run] [--templates <dir>]
#                       [--readme-template <path>]
#
# Flags:
#   --output-root <path>   REQUIRED. Directory the package is created under.
#                          Created if absent.
#   --dry-run              Report what would be created; write nothing.
#   --templates <dir>      Override the template source directory. Defaults to
#                          <plugin-root>/templates/package. Used by tests.
#   --readme-template <p>  Override the output-root README source. Defaults to
#                          <plugin-root>/templates/package-readme.md.
#
# Output (stdout): KEY=value lines, then a per-file action list.
#   SCAFFOLD_ROOT=<path>
#   SCAFFOLD_DRY_RUN=0|1
#   SCAFFOLD_EXPECTED=23
#   SCAFFOLD_CREATED=<n>          (canonical files newly created; excludes repairs)
#   SCAFFOLD_REPAIRED=<n>         (canonical files that existed but were damaged —
#                                  empty, or missing the frontmatter fence — and
#                                  were overwritten)
#   SCAFFOLD_SKIPPED=<n>          (canonical files only)
#   SCAFFOLD_FAILED=<n>
#   SCAFFOLD_README=created|skipped|failed
#   CREATED <relative-path>   (one line per newly created file)
#   REPAIRED <relative-path>  (one line per damaged file that was overwritten)
#   SKIPPED <relative-path>   (one line per pre-existing, intact file)
#   FAILED  <relative-path>   (one line per file that could not be created:
#                              symlink refusal, wrong type, missing template,
#                              or copy failure)
#
# Exit:
#   0 — every canonical file is present (created, repaired, or already there)
#   1 — one or more files could not be created
#   2 — infrastructure error (missing argument, template dir unreadable)

set -uo pipefail

OUTPUT_ROOT=""
DRY_RUN=0
TEMPLATE_DIR=""
README_TEMPLATE=""
README_REL="README.md"

# The canonical package. Order is the reading order, not alphabetical.
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

CANONICAL_DIRS="00-control 01-project 02-architecture 03-assurance 04-operating 05-due-diligence 06-public 07-verification"

while [ $# -gt 0 ]; do
  case "${1:-}" in
    --output-root)
      [ $# -lt 2 ] && { echo "dossier-scaffold: --output-root requires a value" >&2; exit 2; }
      OUTPUT_ROOT="$2"; shift 2 ;;
    --templates)
      [ $# -lt 2 ] && { echo "dossier-scaffold: --templates requires a value" >&2; exit 2; }
      TEMPLATE_DIR="$2"; shift 2 ;;
    --readme-template)
      [ $# -lt 2 ] && { echo "dossier-scaffold: --readme-template requires a value" >&2; exit 2; }
      README_TEMPLATE="$2"; shift 2 ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    --) shift; break ;;
    *)
      echo "dossier-scaffold: unknown argument: $1" >&2
      echo "Usage: $0 --output-root <path> [--dry-run] [--templates <dir>] [--readme-template <path>]" >&2
      exit 2 ;;
  esac
done

if [ -z "$OUTPUT_ROOT" ]; then
  echo "dossier-scaffold: missing --output-root. Usage: $0 --output-root <path> [--dry-run] [--templates <dir>] [--readme-template <path>]" >&2
  exit 2
fi

# CLAUDE_PLUGIN_ROOT is not reliably set inside slash-command bash blocks, so
# every template lookup below falls back to this script's own location, which is
# always <plugin-root>/bin.
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)

# Resolve the template directory.
if [ -z "$TEMPLATE_DIR" ]; then
  for CANDIDATE in \
    "${CLAUDE_PLUGIN_ROOT:-}/templates/package" \
    "${SCRIPT_DIR:-}/../templates/package" \
    "plugins/dossier/templates/package"
  do
    case "$CANDIDATE" in /templates/package|"") continue ;; esac
    if [ -d "$CANDIDATE" ]; then TEMPLATE_DIR="$CANDIDATE"; break; fi
  done
fi

if [ -z "$TEMPLATE_DIR" ] || [ ! -d "$TEMPLATE_DIR" ]; then
  echo "dossier-scaffold: template directory not found (looked at CLAUDE_PLUGIN_ROOT, script dir, and plugins/dossier)" >&2
  exit 2
fi

# The README template is resolved independently of --templates: a caller
# pointing --templates at a fixture still gets the real signpost, and a caller
# who wants a different one says so explicitly.
if [ -z "$README_TEMPLATE" ]; then
  for CANDIDATE in \
    "$TEMPLATE_DIR/../package-readme.md" \
    "${CLAUDE_PLUGIN_ROOT:-}/templates/package-readme.md" \
    "${SCRIPT_DIR:-}/../templates/package-readme.md" \
    "plugins/dossier/templates/package-readme.md"
  do
    case "$CANDIDATE" in /templates/package-readme.md|"") continue ;; esac
    if [ -f "$CANDIDATE" ]; then README_TEMPLATE="$CANDIDATE"; break; fi
  done
fi

CREATED=0
REPAIRED=0
SKIPPED=0
FAILED=0
ACTIONS=""

if [ "$DRY_RUN" -eq 0 ]; then
  for DIR in $CANONICAL_DIRS; do
    mkdir -p "$OUTPUT_ROOT/$DIR" 2>/dev/null || {
      echo "dossier-scaffold: cannot create $OUTPUT_ROOT/$DIR" >&2
      exit 2
    }
  done
fi

for REL in $CANONICAL_FILES; do
  SRC="$TEMPLATE_DIR/$REL"
  DEST="$OUTPUT_ROOT/$REL"
  DIR_PART="${REL%/*}"
  IS_REPAIR=0

  # A symlink anywhere on a canonical path — the leaf file itself, or the
  # single directory segment above it — is never trusted. `cp`/`mkdir -p`
  # both follow symlinks transparently: `mkdir -p` on a directory reached
  # through a symlink succeeds silently (nothing new is created), and a
  # leaf-only `-L "$DEST"` check inspects just the final path component, so
  # a file underneath a symlinked directory still reads as an ordinary
  # regular file — a repair could silently overwrite a file outside
  # $OUTPUT_ROOT, and a dangling link fails `-e` (looks absent), so an
  # unguarded create would silently write through it too. The 23 canonical
  # paths, and their 8 directory segments, are public in the plugin source,
  # so a poisoned source repo can plant either kind of link at a
  # predictable path and wait for a victim to scaffold against it. Checked
  # with `-L` before `-e`, since `-e` follows the link and reports false
  # for a dangling one; checked unconditionally (not gated on --dry-run,
  # since --dry-run must report what a real run would refuse, not silently
  # skip the check because the write itself doesn't happen).
  if [ -L "$OUTPUT_ROOT/$DIR_PART" ] || [ -L "$DEST" ]; then
    FAILED=$((FAILED + 1))
    ACTIONS="${ACTIONS}FAILED  $REL (refusing to write through a symlink)
"
    continue
  fi

  # Presence is not completeness. A process killed mid-write leaves a file that
  # exists and holds nothing, and `-e` alone cannot tell that from a correctly
  # scaffolded one — so the retry that exists to "fill only the gaps" reported
  # SKIPPED and FAILED=0, a clean bill of health over a truncated package. An
  # empty file, or one with no frontmatter fence on its first line, is treated
  # as absent and rewritten.
  if [ -e "$DEST" ]; then
    if [ ! -f "$DEST" ]; then
      FAILED=$((FAILED + 1))
      ACTIONS="${ACTIONS}FAILED  $REL (not a regular file at canonical path)
"
      continue
    fi
    DEST_INTACT=1
    [ -s "$DEST" ] || DEST_INTACT=0
    if [ "$DEST_INTACT" -eq 1 ]; then
      head -n 1 "$DEST" 2>/dev/null | grep -q '^---$' || DEST_INTACT=0
    fi
    if [ "$DEST_INTACT" -eq 1 ]; then
      SKIPPED=$((SKIPPED + 1))
      ACTIONS="${ACTIONS}SKIPPED $REL
"
      continue
    fi
    IS_REPAIR=1
    # Captured now (before any overwrite) so it stays accurate even though
    # the announcement itself is deferred below to the confirmed-success
    # branches — the same discipline the REPAIRED action line already
    # follows, so an attempt that turns out FAILED never claims it happened.
    REPAIR_BYTES=$(wc -c 2>/dev/null < "$DEST" | tr -d '[:space:]')
  fi

  # The read side gets the same treatment as the write side: `-f` follows a
  # symlink, so a symlinked template would be silently accepted and its
  # target's content copied into a canonical document. Templates are
  # normally the plugin's own trusted install, but --templates is a
  # supported override pointing wherever the caller names.
  if [ -L "$SRC" ]; then
    FAILED=$((FAILED + 1))
    ACTIONS="${ACTIONS}FAILED  $REL (refusing to read a symlinked template)
"
    continue
  fi

  if [ ! -f "$SRC" ]; then
    FAILED=$((FAILED + 1))
    ACTIONS="${ACTIONS}FAILED  $REL (template missing at $SRC)
"
    continue
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$IS_REPAIR" -eq 1 ]; then
      REPAIRED=$((REPAIRED + 1))
      ACTIONS="${ACTIONS}REPAIRED $REL
"
      printf 'dossier-scaffold: would repair %s (replacing %s bytes)\n' "$REL" "${REPAIR_BYTES:-unknown}" >&2
    else
      CREATED=$((CREATED + 1))
      ACTIONS="${ACTIONS}CREATED $REL
"
    fi
    continue
  fi

  # Written via a same-directory temp file and an atomic rename rather than
  # a direct `cp` onto $DEST. `cp` follows a destination symlink and writes
  # through it; a rename() on the same filesystem replaces whatever is at
  # $DEST outright — including a symlink planted there after the `-L` check
  # above ran — without ever dereferencing it, closing that check/write
  # race rather than merely narrowing it. The temp name includes $$ so two
  # concurrent scaffold runs cannot collide on it.
  TMP_DEST="$DEST.dossier-scaffold.tmp.$$"
  if cp "$SRC" "$TMP_DEST" 2>/dev/null && mv -f "$TMP_DEST" "$DEST" 2>/dev/null; then
    if [ "$IS_REPAIR" -eq 1 ]; then
      REPAIRED=$((REPAIRED + 1))
      ACTIONS="${ACTIONS}REPAIRED $REL
"
      printf 'dossier-scaffold: repairing %s (replacing %s bytes)\n' "$REL" "${REPAIR_BYTES:-unknown}" >&2
    else
      CREATED=$((CREATED + 1))
      ACTIONS="${ACTIONS}CREATED $REL
"
    fi
  else
    rm -f "$TMP_DEST" 2>/dev/null
    FAILED=$((FAILED + 1))
    ACTIONS="${ACTIONS}FAILED  $REL (copy failed)
"
  fi
done

# The output-root signpost. Counted separately from the canonical 23 so that
# SCAFFOLD_CREATED keeps meaning "canonical documents" — a consumer asserting 23
# must not start seeing 24 because a supplement was added.
README_STATE="created"
README_DEST="$OUTPUT_ROOT/$README_REL"

if [ -L "$README_DEST" ]; then
  README_STATE="failed"
  FAILED=$((FAILED + 1))
  ACTIONS="${ACTIONS}FAILED  $README_REL (refusing to write through a symlink)
"
  echo "dossier-scaffold: refusing to write the README through a symlink at $README_DEST" >&2
elif [ -e "$README_DEST" ]; then
  if [ -f "$README_DEST" ]; then
    README_STATE="skipped"
  else
    # Same type-confusion guard the canonical-file loop applies: -e is true
    # for a directory too, and treating one as an intact README would be a
    # silent no-op over a broken package, the exact failure mode this whole
    # fix exists to close.
    README_STATE="failed"
    FAILED=$((FAILED + 1))
    ACTIONS="${ACTIONS}FAILED  $README_REL (not a regular file)
"
    echo "dossier-scaffold: $README_DEST exists but is not a regular file" >&2
  fi
elif [ -z "$README_TEMPLATE" ] || [ ! -f "$README_TEMPLATE" ]; then
  README_STATE="failed"
  FAILED=$((FAILED + 1))
  ACTIONS="${ACTIONS}FAILED  $README_REL (template missing)
"
  echo "dossier-scaffold: README template not found (looked at --readme-template, CLAUDE_PLUGIN_ROOT, script dir, and plugins/dossier)" >&2
elif [ "$DRY_RUN" -eq 0 ]; then
  README_TMP_DEST="$README_DEST.dossier-scaffold.tmp.$$"
  if cp "$README_TEMPLATE" "$README_TMP_DEST" 2>/dev/null && mv -f "$README_TMP_DEST" "$README_DEST" 2>/dev/null; then
    :
  else
    rm -f "$README_TMP_DEST" 2>/dev/null
    README_STATE="failed"
    FAILED=$((FAILED + 1))
    ACTIONS="${ACTIONS}FAILED  $README_REL (copy failed)
"
    echo "dossier-scaffold: failed to write README at $README_DEST" >&2
  fi
fi

printf 'SCAFFOLD_ROOT=%s\n' "$OUTPUT_ROOT"
printf 'SCAFFOLD_DRY_RUN=%s\n' "$DRY_RUN"
printf 'SCAFFOLD_EXPECTED=23\n'
printf 'SCAFFOLD_CREATED=%s\n' "$CREATED"
printf 'SCAFFOLD_REPAIRED=%s\n' "$REPAIRED"
printf 'SCAFFOLD_SKIPPED=%s\n' "$SKIPPED"
printf 'SCAFFOLD_FAILED=%s\n' "$FAILED"
printf 'SCAFFOLD_README=%s\n' "$README_STATE"
printf '%s' "$ACTIONS"

[ "$FAILED" -gt 0 ] && exit 1
exit 0
