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
END { print "SUMMARY\t" semi "\t" emdash }
AWKEOF

count_matches() { # <text> <ERE pattern> — occurrence count, not line count
  local n
  n=$(printf '%s\n' "$1" | grep -oiE "$2" 2>/dev/null | wc -l | tr -d ' ')
  printf '%s' "${n:-0}"
}

H_MARKETING=0; H_PHRASAL=0; H_FILLER=0; H_LATINATE=0; H_SEMICOLON=0
H_LONG_SENT=0; H_LONG_PARA=0
A_PASSIVE=0; A_NOMINALIZE=0; A_EMDASH=0
FILES_JSON=""
FIRST_FILE=1
FINDINGS=""

lint_file() { # <path>
  local f="$1"
  local awk_out sent_buf summary_line semi emdash
  local f_marketing f_phrasal f_filler f_latinate f_semicolon
  local f_long_sent f_long_para f_passive f_nominalize f_emdash f_blocking

  awk_out=$(awk -f "$AWK_PROG" "$f")

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
    FILES_JSON="$FILES_JSON{\"file\":\"$f\",\"blocking_violations\":$f_blocking,\"hard\":{\"marketing_adjective\":$f_marketing,\"phrasal_verb\":$f_phrasal,\"filler_hedge\":$f_filler,\"latinate_word\":$f_latinate,\"semicolon\":$f_semicolon,\"long_sentence\":$f_long_sent,\"long_paragraph\":$f_long_para},\"advisory\":{\"passive_voice\":$f_passive,\"nominalization\":$f_nominalize,\"em_dash\":$f_emdash}}"
  fi
}

for f in $TARGETS; do
  [ -f "$f" ] || continue
  lint_file "$f"
done

BLOCKING=$((H_MARKETING + H_PHRASAL + H_FILLER + H_LATINATE + H_SEMICOLON + H_LONG_SENT + H_LONG_PARA))

if [ "$WANT_JSON" -eq 1 ]; then
  printf '{"blocking_violations":%s,"hard":{"marketing_adjective":%s,"phrasal_verb":%s,"filler_hedge":%s,"latinate_word":%s,"semicolon":%s,"long_sentence":%s,"long_paragraph":%s},"advisory":{"passive_voice":%s,"nominalization":%s,"em_dash":%s},"files":[%s]}\n' \
    "$BLOCKING" "$H_MARKETING" "$H_PHRASAL" "$H_FILLER" "$H_LATINATE" "$H_SEMICOLON" "$H_LONG_SENT" "$H_LONG_PARA" \
    "$A_PASSIVE" "$A_NOMINALIZE" "$A_EMDASH" "$FILES_JSON"
elif [ "$QUIET" -eq 0 ]; then
  echo "PROSE_LINT_BLOCKING_VIOLATIONS=$BLOCKING"
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
