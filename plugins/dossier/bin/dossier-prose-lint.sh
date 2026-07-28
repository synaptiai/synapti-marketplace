#!/usr/bin/env bash
# dossier-prose-lint.sh — mechanical prose-clarity check (ASD-STE100-derived).
#
# Checks drafted prose for the mechanically checkable subset of AI slop: banned
# marketing adjectives, banned phrasal verbs, banned filler/hedge phrases,
# Latinate long-form words, semicolons, over-length sentences, and over-length
# paragraphs. These are HARD categories: any hit blocks (exit 1).
#
# Also reports, but never blocks on: passive voice, nominalization, and
# em-dash count. These are ADVISORY — grammar-heuristic and false-positive-
# prone, backstopped by dossier-pass-c-audience's judgment rather than gated
# here. This plugin's own reference documents use em-dashes constitutively, so
# em-dash must never be a hard category.
#
# The one property that must never be violated: a required epistemic-hedge
# marker on an Interpreted-state claim ("This suggests …", "Inferred from …",
# "Inferred:", "Unknown:", "Recommendation:") is exempt from the hedge-phrase
# and sentence-length rules, unconditionally, in every mode. See
# references/source-authority-and-claim-states.md and
# references/prose-style-and-vocabulary.md.
#
# Mode resolution is per line, not per document: a line opening a numbered or
# bulleted step is STRICT (20-word sentence cap). Everything else is
# STE-FLAVORED (25-word cap). Both modes ban the same marketing adjectives,
# phrasal verbs, and semicolons.
#
# PERFORMANCE: structural parsing (skip-filtering, code-span stripping, mode
# detection, sentence splitting, the carve-out check, and the two carve-out-
# sensitive categories) runs in a single awk pass per file — not a bash loop
# forking a process per sentence per category, which does not finish in
# reasonable time across a real package. The five word-boundary-sensitive
# categories (marketing/phrasal/latinate/passive/nominalization) run as one
# grep pass each against the file's already-split sentence buffer, because
# portable awk has no `\b` word-boundary support and GNU/BSD grep -E does.
#
# STATED LIMITATION: sentence and paragraph segmentation here is regex-based,
# not a tokenizer. It will misfire near abbreviations, decimals, and unusual
# punctuation. The dictionary-based hard categories are low-false-positive and
# gate release; the grammar-heuristic advisory categories are diagnostic only
# and backstopped by pass C's judgment — exactly as G06's own regex-secret-scan
# limitation is backstopped by pass C's disclosure lens.
#
# Usage:
#   dossier-prose-lint.sh --file <path> [--json] [--quiet]
#   dossier-prose-lint.sh --output-root <path> [--json] [--quiet]
#
# Exit: 0 clean · 1 hard-category violations found · 2 usage error

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
      [ $# -lt 2 ] && { echo "dossier-prose-lint: --output-root requires a path" >&2; exit 2; }
      OUTPUT_ROOT="$2"; shift 2 ;;
    --file)
      [ $# -lt 2 ] && { echo "dossier-prose-lint: --file requires a path" >&2; exit 2; }
      SINGLE_FILE="$2"; shift 2 ;;
    --json) WANT_JSON=1; shift ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "dossier-prose-lint: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -n "$SINGLE_FILE" ]; then
  [ -f "$SINGLE_FILE" ] || { echo "dossier-prose-lint: no such file: $SINGLE_FILE" >&2; exit 2; }
  TARGETS="$SINGLE_FILE"
else
  if [ -z "$OUTPUT_ROOT" ]; then
    if [ -x "$RESOLVER" ]; then
      OUTPUT_ROOT=$("$RESOLVER" --default "docs/dossier" dossier.project.outputRoot)
    else
      OUTPUT_ROOT="docs/dossier"
    fi
  fi
  TARGETS=$(find "$OUTPUT_ROOT" -name '*.md' -type f 2>/dev/null | sort)
fi

# --- Word and phrase lists ---------------------------------------------------
# Kept disjoint from disclosure-gating's prohibited-vocabulary list (a claim-
# scope concern, public documents only) by design: tests/prose-lint.test.sh
# asserts the two never intersect. See references/prose-style-and-vocabulary.md
# for the human-readable source of truth these patterns mirror.
MARKETING_RE='\b(seamless|robust|powerful|cutting-edge|effortless|world-class|next-generation|revolutionary|blazing(-fast)?|lightning-fast|elegant|delightful|turnkey|best-in-class|state-of-the-art|game-changing|first-class|battle-tested|enterprise-grade|supercharge[d]?|unlock|unleash|empower(ing)?|innovative|industry-leading|transformative)\b'
PHRASAL_RE='\b(spin(ning)?[[:space:]]up|spin[[:space:]]down|spun[[:space:]]up|reach(ing)?[[:space:]]out|div(e|ing)[[:space:]]into|kick(ing)?[[:space:]]off|roll(ing)?[[:space:]]out|tear(ing)?[[:space:]]down|ramp(ing)?[[:space:]]up|circle[[:space:]]back|drill(ing)?[[:space:]](down|into)|sync[[:space:]]up|touch[[:space:]]base|zero[[:space:]]in[[:space:]]on)\b'
LATINATE_RE='\b(utilize|leverage|facilitate|ensure|commence|initiate|originate|prior to|subsequent to|regarding|concerning|obtain|acquire|demonstrate|additionally|furthermore|moreover|henceforth|therein|whilst|amongst|numerous|myriad|plethora|in order to|a variety of|endeavor|ascertain)\b'
PASSIVE_RE='\b(am|is|are|was|were|be|been|being)[[:space:]]+[a-z]+ed\b'
NOMINALIZE_RE='\b(perform(s|ed)?|conduct(s|ed)?|provide(s|d)?|carry[[:space:]]out|carries[[:space:]]out|carried[[:space:]]out|make[[:space:]]use[[:space:]]of|makes[[:space:]]use[[:space:]]of)[[:space:]]+(an?[[:space:]]+)?[a-z]+(tion|ment|ance|ence)\b'

WORK=$(mktemp -d -t dossier-prose-lint.XXXXXX) || {
  echo "dossier-prose-lint: cannot create temp directory" >&2; exit 2; }
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

# --- The structural pass: one awk program, one invocation per file ----------
# Handles frontmatter/fence/skip-line filtering, code-span stripping, per-line
# mode resolution, sentence splitting, the epistemic-hedge carve-out, and the
# two carve-out-sensitive categories (long_sentence, filler_hedge). Emits:
#   S\t<sentence>              — every sentence, for the word-boundary greps
#   E\tlong_sentence\t<file>
#   E\tfiller_hedge\t<file>
#   E\tlong_paragraph\t<file>
#   SUMMARY\t<semicolons>\t<em-dashes>
AWK_PROG="$WORK/lint.awk"
cat > "$AWK_PROG" <<'AWKEOF'
BEGIN {
  in_header = 0; first_line = 1; in_fence = 0; para_sentences = 0
  semi = 0; emdash = 0
}
{
  line = $0
  if (first_line) {
    first_line = 0
    if (line == "---") { in_header = 1; next }
  } else if (in_header) {
    if (line == "---") in_header = 0
    next
  }
  if (substr(line, 1, 3) == "```") { in_fence = !in_fence; next }
  if (in_fence) next
  if (line == "") { para_sentences = 0; next }
  c1 = substr(line, 1, 1)
  if (c1 == "#" || c1 == "|") next
  if (substr(line, 1, 3) == "---") next
  if (substr(line, 1, 4) == "<!--") next
  if (substr(line, 1, 2) == "> ") next

  stripped = line
  gsub(/`[^`]*`/, " ", stripped)

  mode = "flavored"
  if (stripped ~ /^[ \t]*[-*][ \t]/ || stripped ~ /^[ \t]*[0-9]+[.)][ \t]/) mode = "strict"

  semitmp = stripped
  semi += gsub(/;/, ";", semitmp)
  edtmp = stripped
  emdash += gsub(/—/, "—", edtmp)

  splitline = stripped
  gsub(/[.!?][ \t]+/, "&\x01", splitline)
  nsent = split(splitline, sarr, "\x01")
  for (i = 1; i <= nsent; i++) {
    s = sarr[i]
    gsub(/^[ \t]+/, "", s); gsub(/[ \t]+$/, "", s)
    if (s == "") continue
    wc = split(s, warr, /[ \t]+/)
    if (wc < 2) continue
    para_sentences++
    ls = tolower(s)

    carve = 0
    if (ls ~ /^this suggests/) carve = 1
    else if (ls ~ /^the most likely reading is/) carve = 1
    else if (ls ~ /^inferred from/) carve = 1
    else if (ls ~ /^inferred:/) carve = 1
    else if (ls ~ /^unknown:/) carve = 1
    else if (ls ~ /^recommendation:/) carve = 1

    if (!carve) {
      cap = (mode == "strict") ? 20 : 25
      if (wc > cap) print "E\tlong_sentence\t" FILENAME
      if (ls ~ /it is important to note that|it should be noted that|it is worth noting that|please note that|as previously mentioned|as mentioned above|as noted above|needless to say|at this point in time|due to the fact that|in the event that|for all intents and purposes/) print "E\tfiller_hedge\t" FILENAME
    }
    if (para_sentences == 7) print "E\tlong_paragraph\t" FILENAME

    print "S\t" s
  }
}
END {
  # A frontmatter fence opened but never closed means every remaining line
  # was silently skipped as "still in the header" — the rest of the document
  # was never scanned. Report it rather than let that read as a clean file.
  if (in_header) print "UNCLOSED_HEADER\t1"
  print "SUMMARY\t" semi "\t" emdash
}
AWKEOF

# A write failure here (unwritable temp dir) must not be discovered later as
# an awk-can't-open-file error on every single file — fail loudly once, now.
[ -s "$AWK_PROG" ] || {
  echo "dossier-prose-lint: cannot write the structural-pass program to $AWK_PROG" >&2
  exit 2
}

count_matches() { # <text> <ERE pattern> — occurrence count, not line count
  local n
  n=$(printf '%s\n' "$1" | grep -oiE "$2" 2>/dev/null | wc -l | tr -d ' ')
  printf '%s' "${n:-0}"
}

H_MARKETING=0; H_PHRASAL=0; H_FILLER=0; H_LATINATE=0; H_SEMICOLON=0
H_LONG_SENT=0; H_LONG_PARA=0; H_SCAN_ERROR=0
A_PASSIVE=0; A_NOMINALIZE=0; A_EMDASH=0
FILES_JSON=""
FIRST_FILE=1
FINDINGS=""
FILES_SCANNED=0

# A file that could not be genuinely scanned must never render as "0
# violations" — that is indistinguishable from a file that was scanned and
# found clean, and a gate condition reading this JSON would record PASS on a
# file it never actually read.
scan_error_hit() { # <path> <reason>
  local ef="$1" reason ef_esc reason_esc
  # The reason string can come from awk's own diagnostic, which echoes the
  # offending bytes verbatim on a multibyte-conversion failure — exactly the
  # kind of content that triggered this path in the first place. Restricting
  # to printable ASCII guarantees the JSON this produces is valid regardless
  # of what was in the file that could not be scanned.
  reason=$(printf '%s' "$2" | LC_ALL=C tr -cd '\40-\176')
  H_SCAN_ERROR=$((H_SCAN_ERROR + 1))
  FINDINGS="$FINDINGS
  $ef: scan_error ($reason)"
  if [ "$WANT_JSON" -eq 1 ]; then
    [ "$FIRST_FILE" -eq 0 ] && FILES_JSON="$FILES_JSON,"
    FIRST_FILE=0
    ef_esc=$(printf '%s' "$ef" | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    reason_esc=$(printf '%s' "$reason" | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    FILES_JSON="$FILES_JSON{\"file\":\"$ef_esc\",\"scan_error\":\"$reason_esc\",\"blocking_violations\":1}"
  fi
}

lint_file() { # <path>
  local f="$1"
  local awk_out awk_err awk_rc sent_buf summary_line semi emdash errmsg
  local f_marketing f_phrasal f_filler f_latinate f_semicolon
  local f_long_sent f_long_para f_passive f_nominalize f_emdash f_blocking

  FILES_SCANNED=$((FILES_SCANNED + 1))

  awk_err=$(mktemp -t dossier-prose-lint-awkerr.XXXXXX 2>/dev/null) || awk_err=/dev/null
  awk_out=$(awk -f "$AWK_PROG" "$f" 2>"$awk_err")
  awk_rc=$?
  if [ "$awk_rc" -ne 0 ]; then
    # A binary file, or one that turned unreadable mid-run, is the case this
    # guards against.
    errmsg=$(head -1 "$awk_err" 2>/dev/null)
    scan_error_hit "$f" "awk exit $awk_rc: ${errmsg:-no diagnostic}"
    rm -f "$awk_err" 2>/dev/null
    return
  fi
  rm -f "$awk_err" 2>/dev/null

  if printf '%s\n' "$awk_out" | grep -q $'^UNCLOSED_HEADER\t'; then
    # A frontmatter fence opened but never closed means every remaining line
    # was silently treated as "still in the header" and never reached the
    # rest of the checks — the document was not actually scanned past line 1.
    scan_error_hit "$f" "frontmatter fence opened but never closed"
    return
  fi

  sent_buf=$(printf '%s\n' "$awk_out" | grep $'^S\t' | cut -f2-)
  f_long_sent=$(printf '%s\n' "$awk_out" | grep -c $'^E\tlong_sentence\t')
  f_filler=$(printf '%s\n' "$awk_out" | grep -c $'^E\tfiller_hedge\t')
  f_long_para=$(printf '%s\n' "$awk_out" | grep -c $'^E\tlong_paragraph\t')
  summary_line=$(printf '%s\n' "$awk_out" | grep $'^SUMMARY\t')
  semi=$(printf '%s' "$summary_line" | cut -f2)
  emdash=$(printf '%s' "$summary_line" | cut -f3)
  f_semicolon=${semi:-0}
  f_emdash=${emdash:-0}

  f_marketing=$(count_matches "$sent_buf" "$MARKETING_RE")
  f_phrasal=$(count_matches "$sent_buf" "$PHRASAL_RE")
  f_latinate=$(count_matches "$sent_buf" "$LATINATE_RE")
  f_passive=$(count_matches "$sent_buf" "$PASSIVE_RE")
  f_nominalize=$(count_matches "$sent_buf" "$NOMINALIZE_RE")

  H_MARKETING=$((H_MARKETING + f_marketing)); H_PHRASAL=$((H_PHRASAL + f_phrasal))
  H_FILLER=$((H_FILLER + f_filler)); H_LATINATE=$((H_LATINATE + f_latinate))
  H_SEMICOLON=$((H_SEMICOLON + f_semicolon)); H_LONG_SENT=$((H_LONG_SENT + f_long_sent))
  H_LONG_PARA=$((H_LONG_PARA + f_long_para))
  A_PASSIVE=$((A_PASSIVE + f_passive)); A_NOMINALIZE=$((A_NOMINALIZE + f_nominalize))
  A_EMDASH=$((A_EMDASH + f_emdash))

  f_blocking=$((f_marketing + f_phrasal + f_filler + f_latinate + f_semicolon + f_long_sent + f_long_para))

  if [ "$f_blocking" -gt 0 ]; then
    FINDINGS="$FINDINGS
  $f: marketing=$f_marketing phrasal=$f_phrasal filler_hedge=$f_filler latinate=$f_latinate semicolon=$f_semicolon long_sentence=$f_long_sent long_paragraph=$f_long_para"
  fi

  if [ "$WANT_JSON" -eq 1 ]; then
    [ "$FIRST_FILE" -eq 0 ] && FILES_JSON="$FILES_JSON,"
    FIRST_FILE=0
    # Escaped: an unescaped path containing a double quote or backslash would
    # otherwise emit malformed JSON.
    f_esc=$(printf '%s' "$f" | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    FILES_JSON="$FILES_JSON{\"file\":\"$f_esc\",\"blocking_violations\":$f_blocking,\"hard\":{\"marketing_adjective\":$f_marketing,\"phrasal_verb\":$f_phrasal,\"filler_hedge\":$f_filler,\"latinate_word\":$f_latinate,\"semicolon\":$f_semicolon,\"long_sentence\":$f_long_sent,\"long_paragraph\":$f_long_para},\"advisory\":{\"passive_voice\":$f_passive,\"nominalization\":$f_nominalize,\"em_dash\":$f_emdash}}"
  fi
}

# Newline-delimited read, not `for f in $TARGETS`: an unquoted for-loop word-
# splits on any IFS whitespace in a path (a doc titled with a space) and
# glob-expands any literal *, ?, or [ it contains. Process substitution keeps
# this out of a subshell, so lint_file's mutations to the H_*/FILES_JSON
# globals still land in the caller.
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  lint_file "$f"
done < <(printf '%s\n' "$TARGETS")

# In --output-root mode, zero files scanned (an empty directory, a directory
# with no .md files, a path typo) reports as "0 violations, clean" exactly
# like a package that was genuinely scanned and found spotless. Those are not
# the same claim, and a gate condition reading this JSON cannot tell them
# apart without this signal — mirrors G16's own "zero implausible unknowns is
# a finding, not a pass" reasoning elsewhere in this plugin's gate.
if [ -z "$SINGLE_FILE" ] && [ "$FILES_SCANNED" -eq 0 ]; then
  H_SCAN_ERROR=$((H_SCAN_ERROR + 1))
  FINDINGS="$FINDINGS
  $OUTPUT_ROOT: scan_error (0 .md files found under this root)"
fi

BLOCKING=$((H_MARKETING + H_PHRASAL + H_FILLER + H_LATINATE + H_SEMICOLON + H_LONG_SENT + H_LONG_PARA + H_SCAN_ERROR))

if [ "$WANT_JSON" -eq 1 ]; then
  printf '{"blocking_violations":%s,"files_scanned":%s,"scan_errors":%s,"hard":{"marketing_adjective":%s,"phrasal_verb":%s,"filler_hedge":%s,"latinate_word":%s,"semicolon":%s,"long_sentence":%s,"long_paragraph":%s},"advisory":{"passive_voice":%s,"nominalization":%s,"em_dash":%s},"files":[%s]}\n' \
    "$BLOCKING" "$FILES_SCANNED" "$H_SCAN_ERROR" "$H_MARKETING" "$H_PHRASAL" "$H_FILLER" "$H_LATINATE" "$H_SEMICOLON" "$H_LONG_SENT" "$H_LONG_PARA" \
    "$A_PASSIVE" "$A_NOMINALIZE" "$A_EMDASH" "$FILES_JSON"
elif [ "$QUIET" -eq 0 ]; then
  echo "PROSE_LINT_BLOCKING_VIOLATIONS=$BLOCKING"
  echo "PROSE_LINT_FILES_SCANNED=$FILES_SCANNED"
  echo "PROSE_LINT_SCAN_ERRORS=$H_SCAN_ERROR"
  echo "PROSE_LINT_HARD_MARKETING=$H_MARKETING"
  echo "PROSE_LINT_HARD_PHRASAL=$H_PHRASAL"
  echo "PROSE_LINT_HARD_FILLER_HEDGE=$H_FILLER"
  echo "PROSE_LINT_HARD_LATINATE=$H_LATINATE"
  echo "PROSE_LINT_HARD_SEMICOLON=$H_SEMICOLON"
  echo "PROSE_LINT_HARD_LONG_SENTENCE=$H_LONG_SENT"
  echo "PROSE_LINT_HARD_LONG_PARAGRAPH=$H_LONG_PARA"
  echo "PROSE_LINT_ADVISORY_PASSIVE=$A_PASSIVE"
  echo "PROSE_LINT_ADVISORY_NOMINALIZATION=$A_NOMINALIZE"
  echo "PROSE_LINT_ADVISORY_EM_DASH=$A_EMDASH"
  if [ -n "$FINDINGS" ]; then
    echo ""
    echo "Findings (per-file hard-category counts):"
    printf '%s\n' "$FINDINGS"
  fi
fi
# --quiet prints nothing, matching dossier-claim-scan.sh's convention — a
# caller that needs the count uses --json instead.

[ "$BLOCKING" -gt 0 ] && exit 1
exit 0
