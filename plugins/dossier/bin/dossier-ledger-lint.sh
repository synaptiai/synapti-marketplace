#!/usr/bin/env bash
# dossier-ledger-lint.sh — mechanical checks on the evidence ledger.
#
# Checks:
#   1. Every row has 13 columns.
#   2. Every Evidence ID matches EV-[0-9]{4,} and is unique.
#   3. Every State is one of V C R I U N/A.
#   4. Every Authority is 1-7; every Retrievable is yes|no; Observed is ISO.
#   5. Retrievable=no at authority 1-3 is a contradiction (the level claims a
#      source inside the inspection boundary, so it must be reachable).
#   6. Retrievable=no at authority 4-7 requires a non-empty Notes cell saying
#      what a reader would need in order to check it.
#   7. Source ref resolves — ONLY for authority levels 1-3. Levels 4-7 point at
#      contracts, interviews, and dashboards the linter cannot reach; failing
#      them would train everyone to ignore this script.
#   8. Every [EV-####] citation in the package resolves to a ledger row.
#   9. Public use=yes requires State in {V,C} (a reported or inferred claim may
#      never be published) and a matching approved row in the claim register.
#  10. Orphan rows (no consuming document) are reported as warnings, not errors.
#
# Usage:
#   dossier-ledger-lint.sh [--output-root <path>] [--json] [--quiet]
#
# Exit: 0 clean · 1 findings · 2 infrastructure error

set -uo pipefail

SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
RESOLVER="$SELF_DIR/dossier-resolve-config.sh"

OUTPUT_ROOT=""
WANT_JSON=0
QUIET=0

while [ $# -gt 0 ]; do
  case "${1:-}" in
    --output-root)
      [ $# -lt 2 ] && { echo "dossier-ledger-lint: --output-root requires a path" >&2; exit 2; }
      OUTPUT_ROOT="$2"; shift 2 ;;
    --json) WANT_JSON=1; shift ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "dossier-ledger-lint: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$OUTPUT_ROOT" ]; then
  if [ -x "$RESOLVER" ]; then
    OUTPUT_ROOT=$("$RESOLVER" --default "docs/dossier" dossier.project.outputRoot)
  else
    OUTPUT_ROOT="docs/dossier"
  fi
fi

LEDGER="$OUTPUT_ROOT/00-control/evidence-ledger.md"
CLAIMS="$OUTPUT_ROOT/00-control/claim-and-disclosure-register.md"

if [ ! -f "$LEDGER" ]; then
  echo "LEDGER_LINT=blocked"
  echo "LEDGER_ERROR=no evidence ledger at $LEDGER — run /dossier:init to scaffold the package"
  exit 2
fi

ERRORS=0
WARNINGS=0
FINDINGS_FILE=$(mktemp -t dossier-ledger-lint.XXXXXX) || {
  echo "dossier-ledger-lint: cannot create temp file" >&2; exit 2; }
IDS_FILE=$(mktemp -t dossier-ledger-ids.XXXXXX) || {
  rm -f "$FINDINGS_FILE"; echo "dossier-ledger-lint: cannot create temp file" >&2; exit 2; }
cleanup() { rm -f "$FINDINGS_FILE" "$IDS_FILE" "$IDS_FILE.sorted" 2>/dev/null; }
trap cleanup EXIT

emit() { # severity | line | message
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$FINDINGS_FILE"
  case "$1" in
    error) ERRORS=$((ERRORS + 1)) ;;
    warn)  WARNINGS=$((WARNINGS + 1)) ;;
  esac
}

# Extract data rows: lines starting with `| EV-`. Deliberately anchored on the
# ID prefix rather than on position so the ledger's other tables (executed
# checks, stale evidence) are skipped without needing a section parser.
LINENO_=0
while IFS= read -r line; do
  LINENO_=$((LINENO_ + 1))
  case "$line" in
    "| EV-"*) ;;
    *) continue ;;
  esac

  # Strip leading/trailing pipe, then split on |. Cells may contain no pipes;
  # that is a documented ledger constraint (one row per line, no wrapped cells).
  body=${line#|}
  body=${body%|}
  OLD_IFS=$IFS
  IFS='|'
  # shellcheck disable=SC2206
  cells=($body)
  IFS=$OLD_IFS

  ncells=${#cells[@]}
  if [ "$ncells" -ne 13 ]; then
    emit error "$LINENO_" "row has $ncells columns, expected 13"
    continue
  fi

  trim() { printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
  EVID=$(trim "${cells[0]}")
  STATE=$(trim "${cells[2]}")
  SRCREF=$(trim "${cells[3]}")
  RETR=$(trim "${cells[4]}")
  AUTH=$(trim "${cells[5]}")
  OBSERVED=$(trim "${cells[7]}")
  PUBUSE=$(trim "${cells[10]}")
  CONSUMING=$(trim "${cells[11]}")
  NOTES=$(trim "${cells[12]}")

  # 2. ID grammar and uniqueness
  case "$EVID" in
    EV-[0-9][0-9][0-9][0-9]*) printf '%s\n' "$EVID" >> "$IDS_FILE" ;;
    *) emit error "$LINENO_" "'$EVID' does not match EV-[0-9]{4,}" ;;
  esac

  # 3. State
  case "$STATE" in
    V|C|R|I|U|N/A) ;;
    *) emit error "$LINENO_" "$EVID: State '$STATE' is not one of V C R I U N/A" ;;
  esac

  # 4. Authority, retrievable, observed date
  case "$AUTH" in
    [1-7]) ;;
    *) emit error "$LINENO_" "$EVID: Authority '$AUTH' is not 1-7" ;;
  esac
  case "$RETR" in
    yes|no) ;;
    *) emit error "$LINENO_" "$EVID: Retrievable '$RETR' is not yes|no" ;;
  esac
  case "$OBSERVED" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) emit error "$LINENO_" "$EVID: Observed '$OBSERVED' is not an ISO YYYY-MM-DD date" ;;
  esac

  # 5/6. Retrievability coherence
  if [ "$RETR" = "no" ]; then
    case "$AUTH" in
      [1-3])
        emit error "$LINENO_" "$EVID: Retrievable=no at authority $AUTH — levels 1-3 are sources inside the inspection boundary, so either the locator is wrong or the authority level is inflated" ;;
      [4-7])
        if [ -z "$NOTES" ] || [ "$NOTES" = "—" ] || [ "$NOTES" = "-" ]; then
          emit error "$LINENO_" "$EVID: Retrievable=no at authority $AUTH requires Notes stating what a reader would need in order to check it"
        fi ;;
    esac
  fi

  # 7. Locator resolution, levels 1-3 only
  #
  # A locator is written as a Markdown code span — `references/evidence-ledger-schema.md`
  # writes every one of its own examples that way, and a drafter reading it will
  # copy the form. Comparing the raw cell against the filesystem therefore fails
  # on the documented style, so the backticks come off before anything is tested.
  # A cell may carry several spans; each is a locator in its own right, and the
  # row is sound only if all of them resolve.
  case "$AUTH" in
    [1-3])
      LOCATORS=$(printf '%s\n' "$SRCREF" | tr '`' '\n' | awk 'NR % 2 == 0')
      [ -z "$LOCATORS" ] && LOCATORS=$SRCREF
      # Iterated without a pipe: `emit` increments the error counter, and a
      # subshell would discard every increment while still printing the finding
      # — a linter that reports findings and a zero error count.
      OLD_IFS=$IFS
      IFS='
'
      for loc in $LOCATORS; do
        IFS=$OLD_IFS
        loc=$(trim "$loc")
        [ -z "$loc" ] && { IFS='
'; continue; }
        case "$loc" in
          cmd:*|dashboard:*|git:*|release:*|pr:*|incident:*|inference*|contract:*|interview:*|derived:*)
            IFS='
'; continue ;;  # non-path locator forms; shape is checked, existence is not
        esac
        # Path form, optionally with ::symbol or #heading
        p=${loc%%::*}
        p=${p%%#*}
        p=$(trim "$p")
        if [ -n "$p" ] && [ ! -e "$p" ] && [ ! -e "$OUTPUT_ROOT/$p" ]; then
          emit error "$LINENO_" "$EVID: Source ref '$p' does not resolve (authority $AUTH requires a reachable locator)"
        fi
        IFS='
'
      done
      IFS=$OLD_IFS ;;
  esac

  # 9. Public use gating
  if [ "$PUBUSE" = "yes" ]; then
    case "$STATE" in
      V|C) ;;
      *) emit error "$LINENO_" "$EVID: Public use=yes with State=$STATE — only V and C claims may go public" ;;
    esac
    if [ -f "$CLAIMS" ]; then
      grep -q "$EVID" "$CLAIMS" || \
        emit error "$LINENO_" "$EVID: Public use=yes but no row in the claim and disclosure register cites it"
    fi
  fi

  # 10. Orphans — a warning. An unconsumed V row is often just a claim nothing
  # needed yet, and it is the first thing to look at when pruning.
  if [ -z "$CONSUMING" ] || [ "$CONSUMING" = "—" ] || [ "$CONSUMING" = "-" ]; then
    emit warn "$LINENO_" "$EVID: no consuming document"
  fi
done < "$LEDGER"

# 2b. Duplicate IDs
if [ -s "$IDS_FILE" ]; then
  sort "$IDS_FILE" > "$IDS_FILE.sorted"
  DUPES=$(uniq -d "$IDS_FILE.sorted")
  if [ -n "$DUPES" ]; then
    for d in $DUPES; do
      emit error "0" "$d: duplicate Evidence ID — IDs are never reused, even for withdrawn rows"
    done
  fi
fi

# 8. Dangling citations across the package
DANGLING=0
if [ -d "$OUTPUT_ROOT" ] && [ -s "$IDS_FILE" ]; then
  CITED=$(grep -rhoE 'EV-[0-9]{4,}' "$OUTPUT_ROOT" 2>/dev/null | sort -u)
  for c in $CITED; do
    grep -qx "$c" "$IDS_FILE.sorted" 2>/dev/null || {
      emit error "0" "$c: cited in the package but has no ledger row"
      DANGLING=$((DANGLING + 1))
    }
  done
fi

TOTAL_ROWS=$(wc -l < "$IDS_FILE" 2>/dev/null | tr -d ' ')
[ -z "$TOTAL_ROWS" ] && TOTAL_ROWS=0

if [ "$WANT_JSON" -eq 1 ]; then
  printf '{"ledger":"%s","rows":%s,"errors":%s,"warnings":%s,"dangling_citations":%s,"findings":[' \
    "$LEDGER" "$TOTAL_ROWS" "$ERRORS" "$WARNINGS" "$DANGLING"
  first=1
  while IFS=$'\t' read -r sev ln msg; do
    [ $first -eq 0 ] && printf ','
    first=0
    esc=$(printf '%s' "$msg" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    printf '{"severity":"%s","line":%s,"message":"%s"}' "$sev" "$ln" "$esc"
  done < "$FINDINGS_FILE"
  printf ']}\n'
elif [ "$QUIET" -eq 0 ]; then
  echo "LEDGER_PATH=$LEDGER"
  echo "LEDGER_ROWS=$TOTAL_ROWS"
  echo "LEDGER_ERRORS=$ERRORS"
  echo "LEDGER_WARNINGS=$WARNINGS"
  echo "LEDGER_DANGLING_CITATIONS=$DANGLING"
  if [ -s "$FINDINGS_FILE" ]; then
    echo ""
    echo "Findings:"
    while IFS=$'\t' read -r sev ln msg; do
      if [ "$ln" = "0" ]; then printf '  [%s] %s\n' "$sev" "$msg"
      else printf '  [%s] %s:%s %s\n' "$sev" "$LEDGER" "$ln" "$msg"; fi
    done < "$FINDINGS_FILE"
  fi
fi

[ "$ERRORS" -gt 0 ] && exit 1
exit 0
