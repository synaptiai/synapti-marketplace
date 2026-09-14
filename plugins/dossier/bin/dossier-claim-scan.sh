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
# Exit: 0 clean · 1 registration gaps only · 2 leakage detected · 3 infra error
#
# 2 and 3 are separate because the gate turns this exit code into published
# evidence. Reporting "leakage detected" for a package that simply has no
# public directory yet names a security incident that did not happen.

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
    exit 3
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
  local out grepflags="-nE"
  # Prohibited vocabulary is prose a drafter capitalizes without thinking
  # about it — a heading, a bolded lead, title case in a bullet — and the
  # pattern list itself is written all-lowercase, so "Zero Downtime" or
  # "Bank-Grade" must still match. Leak patterns stay case-sensitive: two are
  # case-sensitive by construction (`AKIA[0-9A-Z]{16}`, the PEM armour), and
  # folding them would themselves start matching unrelated lowercase text.
  [ "$sev" = "prohibited" ] && grepflags="-inE"
  # `--` terminates option parsing: several patterns below start with a hyphen
  # (the PEM armour), and without it grep reads the pattern as flags.
  out=$(grep $grepflags -- "$re" "$f" 2>/dev/null | cut -d: -f1) || return 0
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

# Line classes this scan actually examines for registration (issue #176):
# paragraph prose, bullets, blockquotes, and table DATA cells specifically —
# a confirmed table header row is deliberately excluded (see scan loop below),
# so "table-cell" alone would overstate this scanner's own coverage exactly
# the way the pre-fix scanner overstated it: a claim-shaped header would read
# as "examined" when it structurally never reaches scan_text. Headings and
# fenced code stay structurally exempt too — they are markup, not claims.
# Reported alongside CLAIM_SCAN_UNREGISTERED_SENTENCES so a `0` cannot be
# misread as "every line class was checked" when it only means "every line
# class this scanner is capable of checking was checked" — the exact
# ambiguity the issue reports, discovered when identical claim text scored 0
# as a table row and non-zero as a paragraph with no way to tell from the
# output alone.
LINE_CLASSES_EXAMINED="paragraph,bullet,blockquote,table-data-cell"

# One sentence per check. Declarative only: a heading or a fragment is not a
# claim, and flagging them would drown the real findings. Shared by paragraph,
# bullet, blockquote, and table-cell text alike (issue #176) — all four are
# prose, just with different structural markers to strip before this point.
scan_text() {
  local text="$1"
  local SPLITTABLE
  # Code spans come out BEFORE the split. A bare `tr '.' '\n'` cuts inside
  # `SKILL.md`, `plugin.json`, and `3.2.2`, producing fragments like
  # "md` is not a skill" — reported as unregistered claims that no drafter
  # could resolve, because they are not sentences.
  SPLITTABLE=$(printf '%s' "$text" | sed 's/`[^`]*`/ /g')
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
}

# Placeholder bytes standing in for characters that must survive the cell
# split: a `|` that came from inside a code span (already-stripped below) or
# an explicit `\|` escape, and a `\` that was itself escaped (`\\`). SOH
# (0x01) and STX (0x02) never appear in real markdown prose. Known, accepted
# limitation (security review, issue #176 PR): a document whose raw bytes
# already contain a literal 0x01/0x02 would have that byte silently swapped
# for `|`/`\` in the printed excerpt — cosmetic corruption of the quoted
# text, not a security bypass (redaction and leak detection are unaffected;
# both run on the original bytes, not the placeholder-substituted copy).
# Such a byte cannot occur from normal markdown authoring, so this is not
# hardened against further.
PIPE_ESCAPE_MARK=$(printf '\001')
BACKSLASH_ESCAPE_MARK=$(printf '\002')

# Table rows split into cells on this file's declared markdown pipe syntax:
# an unescaped `|` outside a code span. Splitting on every raw `|` first and
# only stripping code spans later (inside scan_text, per already-broken
# fragments) can silently drop a claim — `Zero downtime \`x|y\` guaranteed
# system.` splits into two halves, each short enough afterward to fall under
# the four-word floor, so the whole sentence is never checked. Code spans are
# stripped and `\|` escapes are protected on the FULL row, before the split.
#
# `\\` (an escaped backslash) is marked BEFORE `\|` is matched, and in that
# order: `\\|` is GFM for "a literal backslash, then an ordinary delimiter
# pipe" — matching `\|` first would misread the second backslash of that
# pair as escaping the pipe, merging two cells that should stay separate.
strip_table_row_delimiters() {
  printf '%s' "$1" | sed -e 's/`[^`]*`/ /g' \
    -e "s/\\\\\\\\/${BACKSLASH_ESCAPE_MARK}/g" \
    -e "s/\\\\|/${PIPE_ESCAPE_MARK}/g"
}

# A GFM separator row (`|---|---|`, optionally with `:` alignment markers) —
# every cell, once trimmed, is nothing but colons and dashes with at least one
# dash. This is structure, not prose, and must never become a "claim" even
# though its dashes are stable across cells (they'd otherwise clear no bar
# because they contain no words at all — this check exists for correctness
# and intent, not because the word floor leaves a gap here).
is_table_separator() {
  local row=$1 body OLD_IFS sepcell trimmed
  local -a sepcells
  body=$(strip_table_row_delimiters "$row")
  body=${body#|}
  body=${body%|}
  OLD_IFS=$IFS
  IFS='|'
  set -f          # a bare glob in a cell must stay literal, not expand
  # shellcheck disable=SC2206
  sepcells=($body)
  set +f
  IFS=$OLD_IFS
  # A row that splits to zero cells (e.g. a bare `|` or `||`) is not a valid
  # separator. Checked via ${#arr[@]}, not "${arr[@]}" directly: on bash 3.2,
  # an empty `arr=($empty)` leaves the array UNSET, and under this script's
  # `set -u` a bare "${arr[@]}" expansion on an unset array is a fatal
  # unbound-variable error that kills the whole scan mid-run — silently
  # dropping every remaining file, including any leak already found earlier.
  [ "${#sepcells[@]}" -eq 0 ] && return 1
  for sepcell in "${sepcells[@]}"; do
    trimmed=$(printf '%s' "$sepcell" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    case "$trimmed" in
      *[!:-]*) return 1 ;;   # contains something other than ':' or '-'
      *-*) ;;                # must contain at least one '-'
      *) return 1 ;;
    esac
  done
  return 0
}

# Split a table row into cells and feed each non-empty cell through the same
# candidate-sentence check as prose (issue #176). Table-cell splitting follows
# the shell-native `IFS='|'` + `set -f` + array-split idiom already used by
# dossier-ledger-lint.sh for the same "split a markdown table row" problem.
scan_table_row() {
  local row=$1 body OLD_IFS rowcell trimmed
  local -a rowcells
  body=$(strip_table_row_delimiters "$row")
  body=${body#|}
  body=${body%|}
  OLD_IFS=$IFS
  IFS='|'
  set -f
  # shellcheck disable=SC2206
  rowcells=($body)
  set +f
  IFS=$OLD_IFS
  # See is_table_separator for why this is ${#arr[@]}, not a direct "${arr[@]}".
  [ "${#rowcells[@]}" -eq 0 ] && return 0
  for rowcell in "${rowcells[@]}"; do
    trimmed=$(printf '%s' "$rowcell" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
      -e "s/${PIPE_ESCAPE_MARK}/|/g" -e "s/${BACKSLASH_ESCAPE_MARK}/\\\\/g")
    [ -n "$trimmed" ] && scan_text "$trimmed"
  done
}

# A held row (see TABLE_HELD_LINE below) is scored later than the line it
# came from — sometimes many lines later, if a fence opens before the hold
# resolves. `scan_text` reports findings against the CURRENT `$LN`, so
# flushing a held row without first restoring `$LN` to the line it was held
# from would attribute its findings to wherever the flush happens to occur,
# not to the line a reader would need to open to find the claim.
flush_held_table_row() {
  local RESUME_LN
  [ -n "$TABLE_HELD_LINE" ] || return 0
  RESUME_LN=$LN
  LN=$TABLE_HELD_LN
  scan_table_row "$TABLE_HELD_LINE"
  LN=$RESUME_LN
  TABLE_HELD_LINE=""
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
  # Table state (issue #176): a GFM table's header row is only distinguishable
  # from a data row by what follows it — the separator row. Since this loop
  # has no lookahead, the first row of a run of `|`-prefixed lines is held
  # rather than scored immediately; row 2 then decides whether row 1 was a
  # header (discarded) or plain data (flushed alongside row 2). Once that
  # determination is made, every further `|`-prefixed row is scored directly.
  TABLE_HELD_LINE=""
  TABLE_HELD_LN=0
  TABLE_ROWS_SEEN=0
  # `|| [ -n "$line" ]` picks up a final line with no trailing newline: `read`
  # still populates $line with its content but returns non-zero at EOF, and a
  # bare `while read` loop condition treats that as "nothing left," silently
  # dropping the last line of any file that isn't newline-terminated.
  while IFS= read -r line || [ -n "$line" ]; do
    LN=$((LN + 1))
    # `read` splits on the actual newline byte only, so a CRLF-terminated
    # file leaves a trailing \r on every line. Left in place, it defeats
    # every exact-string and pattern match downstream: the frontmatter
    # opener/closer compare (`"$line" = "---"`), the fence toggle, and the
    # table separator check all silently fail to match, and — for the
    # frontmatter closer specifically — IN_HEADER then never clears, so
    # every subsequent line in the file is silently skipped via `continue`
    # with no error and exit 0 (issue #176 PR review: found via a
    # mixed-CRLF/LF fixture, the same "clean result whose true coverage
    # doesn't match" failure this whole issue exists to fix).
    line=${line%$'\r'}
    if [ "$FIRST_LINE" -eq 1 ]; then
      FIRST_LINE=0
      # `${line%%[[:space:]]*}` drops everything from the first whitespace
      # character onward, so a closer with trailing spaces or tabs (e.g. a
      # trailing-whitespace-on-save editor artifact) still matches — the
      # \r-strip above already handles CRLF, this handles ordinary trailing
      # whitespace the same way.
      if [ "${line%%[[:space:]]*}" = "---" ]; then IN_HEADER=1; continue; fi
    elif [ "$IN_HEADER" -eq 1 ]; then
      [ "${line%%[[:space:]]*}" = "---" ] && IN_HEADER=0
      continue
    fi
    case "$line" in
      '```'*)
        # A fence line is never a table row, so it leaves any open table
        # exactly like the non-fence "left the table" branch below does.
        # Skipping this flush (issue #176 PR review) let TABLE_HELD_LINE and
        # TABLE_ROWS_SEEN survive across the fence: the first `|`-line after
        # the fence then resumed counting from the stale TABLE_ROWS_SEEN
        # instead of starting a fresh table, so an unrelated later separator-
        # shaped line could discard a genuine claim held from BEFORE the
        # fence as if it were that later "table"'s own header — silently
        # dropping a claim, the exact failure mode this issue exists to fix.
        flush_held_table_row
        TABLE_ROWS_SEEN=0
        IN_FENCE=$((1 - IN_FENCE))
        continue
        ;;
    esac
    if [ "$IN_FENCE" -eq 1 ]; then
      flush_held_table_row
      TABLE_ROWS_SEEN=0
      continue
    fi

    # Every marker match below is column-0 only. Left un-stripped, an
    # indented bullet or an indented table (e.g. nested under a list item)
    # falls through to scan_text/table-splitting with its leading
    # whitespace still attached, which defeats the literal-substring
    # registration match the same way an un-stripped `- ` marker does
    # (code review, issue #176 PR) — the whitespace is content-irrelevant
    # for every classification below, so it's dropped once, here, rather
    # than in each branch. Fenced-code detection above is deliberately NOT
    # given this treatment: an indented fence is a different, unimplemented
    # CommonMark construct (4-space indented code blocks), not a stray-
    # whitespace variant of the backtick fence this script already detects.
    line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//')

    case "$line" in
      '|'*)
        TABLE_ROWS_SEEN=$((TABLE_ROWS_SEEN + 1))
        case "$TABLE_ROWS_SEEN" in
          1)
            TABLE_HELD_LINE="$line"
            TABLE_HELD_LN=$LN
            ;;
          2)
            if is_table_separator "$line"; then
              TABLE_HELD_LINE=""
            else
              flush_held_table_row
              scan_table_row "$line"
            fi
            ;;
          *)
            scan_table_row "$line"
            ;;
        esac
        continue
        ;;
    esac
    # Left the table, if one was open: flush any row still held (it was never
    # followed by a separator, so it was data all along, not a header).
    flush_held_table_row
    TABLE_ROWS_SEEN=0

    case "$line" in
      ''|'#'*|'---'*|'<!--'*) continue ;;
      '- '*) scan_text "${line#- }"; continue ;;
      '* '*) scan_text "${line#\* }"; continue ;;
      '> '*)
        # A bullet nested inside a blockquote (`> - claim text`) must have
        # BOTH markers stripped, not just the blockquote's — piping the
        # stripped body straight into scan_text left the `- `/`* ` prefix
        # in place, defeating the registration match the same way an
        # un-stripped top-level bullet marker does (code review, issue
        # #176 PR). New in this PR: on main, blockquotes were skipped
        # entirely, so this specific false positive could not occur before.
        BQ_BODY="${line#> }"
        case "$BQ_BODY" in
          '- '*) scan_text "${BQ_BODY#- }" ;;
          '* '*) scan_text "${BQ_BODY#\* }" ;;
          *) scan_text "$BQ_BODY" ;;
        esac
        continue
        ;;
    esac

    scan_text "$line"
  done < "$f"
  # A file can end mid-table (its last line is still-held row 1, never
  # confirmed a header because there was no row 2 to check).
  flush_held_table_row
done

UNREGISTERED=$(grep -c '^unregistered' "$HITS_FILE" 2>/dev/null || true)
[ -z "$UNREGISTERED" ] && UNREGISTERED=0

# --- Report ------------------------------------------------------------------
if [ "$WANT_JSON" -eq 1 ]; then
  CLASSES_JSON=$(printf '%s' "$LINE_CLASSES_EXAMINED" | awk -F',' '{
    out = "["
    for (i = 1; i <= NF; i++) { if (i > 1) out = out ","; out = out "\"" $i "\"" }
    print out "]"
  }')
  printf '{"leaks":%s,"prohibited":%s,"unregistered":%s,"register_present":%s,"line_classes_examined":%s,"hits":[' \
    "$LEAKS" "$PROHIBITED" "$UNREGISTERED" "$REGISTER_PRESENT" "$CLASSES_JSON"
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
  echo "CLAIM_SCAN_LINE_CLASSES_EXAMINED=$LINE_CLASSES_EXAMINED"
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
