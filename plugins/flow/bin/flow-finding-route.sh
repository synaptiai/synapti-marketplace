#!/usr/bin/env bash
# [flow] Route a review's consolidated findings by confidence and review mode.
#
# Confidence decides what a finding may demand. A finding nobody verified
# (LOW) may ask for investigation; on someone else's pull request it does not
# count toward the review decision and is not written to the
# FLOW_REVIEW_CYCLE marker, so the merge finding-ledger gate never blocks on
# it. On the author's own pull request every LOW finding must first be
# confirmed (fixed, re-recorded HIGH), refuted (dropped-finding), or escalated
# (re-recorded MEDIUM); a LOW row reaching this script there is an error.
#
# Callers: commands/review.md Phase 4 steps 5-7. The rule this script applies
# is the decision table in skills/code-review-methodology/SKILL.md; the row
# and marker shapes are in references/finding-schema.md.
#
# Usage:
#   flow-finding-route.sh --mode external|self --pr <N> [--input <file>] [--allow-empty]
#                         [--s1-demoted <file>]
#
# Input: one finding per line, on stdin unless --input is given. Blank lines
# are skipped.
#   ID|PRIORITY|category|location|CONFIDENCE|disposition|agent
# A literal pipe inside a field is written `\|`. Fields are trimmed.
#   - ID must match [A-Za-z][A-Za-z0-9_-]* and be unique; PRIORITY is P1|P2|P3;
#     category and location are non-empty. Anything else rejects the input.
#   - CONFIDENCE is HIGH|MEDIUM|LOW in any letter case. Empty or anything else
#     is MEDIUM — never LOW, never HIGH — with a LEDGER_WARN naming the agent.
#   - disposition is consensus|validated|refined|kept|unchallenged; empty is
#     unchallenged, anything else is unchallenged with a LEDGER_WARN.
#   - agent names the reviewer that raised the finding; empty is `unknown`.
#
# Output (stdout, one KEY=value per line, in this order):
#   ROWS_READ  COUNT_P1  COUNT_P2  COUNT_P3  COUNT_NEEDS_INVESTIGATION
#   NEEDS_INVESTIGATION  NEEDS_INVESTIGATION_PRIORITIES  DECISION  MARKER_ROWS
#   [UNRESOLVED_LOW, self mode]  [S1_DEMOTED_APPLIED and S1_KEPT_P1, with --s1-demoted]
# NEEDS_INVESTIGATION lists the LOW ids in input order, comma-joined;
# NEEDS_INVESTIGATION_PRIORITIES lists the same findings as ID:PRIORITY, so a
# rendered entry can be checked against the priority it was routed with.
# MARKER_ROWS holds 7-field rows `ID|PRIORITY|category|location|open|CONFIDENCE|disposition`
# joined by commas, ready for `FINDINGS:[...]`. In category and location every
# byte outside [A-Za-z0-9._~/:@+= -] is percent-encoded, so a comma, a `]`,
# a pipe or a `>` cannot split a row or end the marker. Parsers read only ID
# and PRIORITY; the rendered review body keeps the original text.
#
# --mode external: LOW rows go to NEEDS_INVESTIGATION and are excluded from
#   the counts, DECISION and MARKER_ROWS. DECISION is REQUEST_CHANGES when a
#   counted P1 or P2 exists, else COMMENT when a counted P3 exists, else
#   APPROVE.
# --mode self: any LOW row → exit 3 with only ROWS_READ and UNRESOLVED_LOW on
#   stdout, so there is no marker to post. Otherwise every row is counted and
#   DECISION is COMMENT (a self-review posts as a comment).
#
# --s1-demoted <file> (external mode only; with --mode self it is a usage
#   error): the findings System One's review.confidence demoted, one id per
#   line (bin/flow-s1-confidence.sh writes it). A listed P1 whose row is HIGH
#   or MEDIUM stays counted at that confidence, in the decision and in
#   MARKER_ROWS: on someone else's pull request an answer alone may not take
#   a P1 out of the review. S1_KEPT_P1 lists those ids, and the review shows
#   the System One answer as a note beside each. Every other listed id
#   present in the rows (a P2 or P3, or a P1 whose row is already LOW) is
#   routed LOW, whatever confidence its row carries; a listed id not in the
#   rows gets one LEDGER_WARN. A listed row that is a security finding (a
#   category outside the non-security list of references/finding-schema.md,
#   an agent whose name contains "security", or an id starting SEC- or DEP-)
#   stops the script with exit 1 and nothing routed: System One is never asked
#   about one, so a listed one is a caller error. When a P1 or P2 is routed
#   LOW this way the decision is at least COMMENT, never APPROVE: an answer
#   alone may not approve a pull request, and the code it judged came from
#   the pull request. S1_DEMOTED_APPLIED lists the ids routed LOW, after
#   MARKER_ROWS, and S1_KEPT_P1 follows it. Without the flag the output is
#   what it was before the flag existed.
#
# Zero rows read is an error (exit 1) unless --allow-empty says the review
# genuinely raised no findings; a caller that lost its input must not post an
# empty marker that reads as a clean review.
#
# Exits:
#   0 — routed
#   1 — usage error, rejected row, or zero rows without --allow-empty
#   2 — infrastructure error (input file unreadable)
#   3 — self mode with unresolved LOW rows

set -uo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH

PROG="flow-finding-route.sh"

usage() {
  echo "usage: $PROG --mode external|self --pr <N> [--input <file>] [--allow-empty] [--s1-demoted <file>]" >&2
}

# Strip control characters and cap length before echoing input back.
safe() {
  local s
  s=$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177')
  printf '%s' "${s:0:80}"
}

# An id is ASCII [A-Za-z][A-Za-z0-9_-]*. Bracket ranges follow the caller's
# locale, where [A-Za-z] can match a letter such as é, so match under C.
valid_id() {
  local LC_ALL=C
  case "$1" in
    [A-Za-z]*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *[!A-Za-z0-9_-]*) return 1 ;;
  esac
  return 0
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Percent-encode every byte outside the marker-safe set.
encode() {
  local LC_ALL=C s="$1" out="" c i
  for (( i = 0; i < ${#s}; i++ )); do
    c=${s:i:1}
    case "$c" in
      [A-Za-z0-9._~/:@+=\ -]) out+="$c" ;;
      *) out+=$(printf '%%%02X' $(( $(printf '%d' "'$c") & 255 ))) ;;
    esac
  done
  printf '%s' "$out"
}

MODE=""
PR=""
INPUT=""
INPUT_SET=0
ALLOW_EMPTY=0
S1_DEMOTED_SET=0
S1_DEMOTED_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --pr) PR="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --input) INPUT="${2:-}"; INPUT_SET=1; shift 2 || { usage; exit 1; } ;;
    --allow-empty) ALLOW_EMPTY=1; shift ;;
    --s1-demoted) S1_DEMOTED_FILE="${2:-}"; S1_DEMOTED_SET=1; shift 2 || { usage; exit 1; } ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$PROG: unknown argument '$(safe "$1")'" >&2; usage; exit 1 ;;
  esac
done

case "$MODE" in
  external|self) ;;
  "") echo "$PROG: --mode is required" >&2; usage; exit 1 ;;
  *) echo "$PROG: --mode must be external or self, got '$(safe "$MODE")'" >&2; exit 1 ;;
esac

case "$PR" in
  ""|0*|*[!0-9]*) echo "$PROG: --pr must be a positive integer, got '$(safe "$PR")'" >&2; exit 1 ;;
esac

# The demotions System One's review.confidence made. On the author's own pull
# request a demoted finding reaches routing only as the LOW row the session
# wrote, which stops routing until step 5 has resolved it, so the flag there
# is a caller error.
S1_DEMOTED=","
if [ "$S1_DEMOTED_SET" = 1 ]; then
  if [ "$MODE" != external ]; then
    echo "$PROG: --s1-demoted is for --mode external only" >&2
    exit 1
  fi
  if [ -z "$S1_DEMOTED_FILE" ] || [ ! -f "$S1_DEMOTED_FILE" ] || [ ! -r "$S1_DEMOTED_FILE" ]; then
    echo "$PROG: cannot read --s1-demoted '$(safe "$S1_DEMOTED_FILE")'" >&2
    exit 2
  fi
  while IFS= read -r s1_id || [ -n "$s1_id" ]; do
    s1_id=$(trim "${s1_id%$'\r'}")
    [ -n "$s1_id" ] || continue
    if ! valid_id "$s1_id"; then
      echo "$PROG: --s1-demoted: id '$(safe "$s1_id")' must match [A-Za-z][A-Za-z0-9_-]*" >&2
      exit 1
    fi
    S1_DEMOTED="$S1_DEMOTED$s1_id,"
  done < "$S1_DEMOTED_FILE"
fi
S1_APPLIED=""
S1_KEPT=""
S1_FLOOR=0

# An empty --input is a caller that lost its path, not a request for stdin:
# falling back here would read an empty stdin and post a clean-looking review.
if [ "$INPUT_SET" = 1 ]; then
  if [ -z "$INPUT" ] || [ ! -r "$INPUT" ] || [ -d "$INPUT" ]; then
    echo "$PROG: cannot read --input '$(safe "$INPUT")'" >&2
    exit 2
  fi
  exec < "$INPUT"
fi

# The unit separator stands in for an escaped pipe while a row is split.
US=$'\037'

ROWS_READ=0
COUNT_P1=0
COUNT_P2=0
COUNT_P3=0
NEEDS=""
NEEDS_PRIORITIES=""
NEEDS_COUNT=0
UNRESOLVED=""
MARKER=""
SEEN=","
LINE_NO=0

while IFS= read -r line || [ -n "$line" ]; do
  LINE_NO=$((LINE_NO + 1))
  line="${line%$'\r'}"
  case "$line" in *[![:space:]]*) ;; *) continue ;; esac

  line="${line//\\|/$US}"
  pipes="${line//[^|]/}"
  if [ "${#pipes}" -ne 6 ]; then
    echo "$PROG: line $LINE_NO: expected 7 fields separated by '|', got $(( ${#pipes} + 1 )) (write a literal pipe as '\\|')" >&2
    exit 1
  fi

  IFS='|' read -r f_id f_pri f_cat f_loc f_conf f_disp f_agent <<<"$line"
  f_id=$(trim "${f_id//$US/|}")
  f_pri=$(trim "${f_pri//$US/|}")
  f_cat=$(trim "${f_cat//$US/|}")
  f_loc=$(trim "${f_loc//$US/|}")
  f_conf=$(trim "${f_conf//$US/|}")
  f_disp=$(trim "${f_disp//$US/|}")
  f_agent=$(trim "${f_agent//$US/|}")

  if ! valid_id "$f_id"; then
    echo "$PROG: line $LINE_NO: finding id '$(safe "$f_id")' must match [A-Za-z][A-Za-z0-9_-]*" >&2
    exit 1
  fi
  case "$SEEN" in
    *",$f_id,"*) echo "$PROG: line $LINE_NO: duplicate finding id '$f_id'" >&2; exit 1 ;;
  esac
  SEEN="$SEEN$f_id,"

  case "$f_pri" in
    P1|P2|P3) ;;
    *) echo "$PROG: line $LINE_NO: finding '$f_id' has priority '$(safe "$f_pri")', expected P1, P2 or P3" >&2; exit 1 ;;
  esac
  if [ -z "$f_cat" ]; then
    echo "$PROG: line $LINE_NO: finding '$f_id' has an empty category" >&2
    exit 1
  fi
  if [ -z "$f_loc" ]; then
    echo "$PROG: line $LINE_NO: finding '$f_id' has an empty location" >&2
    exit 1
  fi

  [ -n "$f_agent" ] || f_agent="unknown"
  agent_shown=$(safe "$f_agent")

  conf_upper=$(printf '%s' "$f_conf" | tr '[:lower:]' '[:upper:]')
  case "$conf_upper" in
    HIGH|MEDIUM|LOW) conf="$conf_upper" ;;
    "")
      conf="MEDIUM"
      echo "LEDGER_WARN: PR#$PR finding '$f_id' from $agent_shown has no confidence — treated as MEDIUM" >&2
      ;;
    *)
      conf="MEDIUM"
      echo "LEDGER_WARN: PR#$PR finding '$f_id' from $agent_shown has invalid confidence '$(safe "$f_conf")' — treated as MEDIUM" >&2
      ;;
  esac

  disp=$(printf '%s' "$f_disp" | tr '[:upper:]' '[:lower:]')
  case "$disp" in
    consensus|validated|refined|kept|unchallenged) ;;
    "") disp="unchallenged" ;;
    *)
      echo "LEDGER_WARN: PR#$PR finding '$f_id' from $agent_shown has invalid disposition '$(safe "$f_disp")' — treated as unchallenged" >&2
      disp="unchallenged"
      ;;
  esac

  ROWS_READ=$((ROWS_READ + 1))

  case "$S1_DEMOTED" in
    *",$f_id,"*)
      s1_cat=$(printf '%s' "$f_cat" | tr '[:upper:]' '[:lower:]')
      s1_agent=$(printf '%s' "$f_agent" | tr '[:upper:]' '[:lower:]')
      s1_lid=$(printf '%s' "$f_id" | tr '[:upper:]' '[:lower:]')
      s1_sec=0
      case "$s1_cat" in
        correctness|edge-case|error-handling|performance|tests|runtime|visual|breaking-change|duplication|scope|conventions|claim-verification) ;;
        *) s1_sec=1 ;;
      esac
      case "$s1_agent" in *security*) s1_sec=1 ;; esac
      case "$s1_lid" in sec-*|dep-*) s1_sec=1 ;; esac
      if [ "$s1_sec" = 1 ]; then
        echo "$PROG: line $LINE_NO: '$f_id' is listed in --s1-demoted but is a security finding or has a category outside the non-security list, which System One is never asked about; nothing routed" >&2
        exit 1
      fi
      if [ "$f_pri" = P1 ] && [ "$conf" != LOW ]; then
        S1_KEPT="${S1_KEPT:+$S1_KEPT,}$f_id"
      else
        conf="LOW"
        S1_APPLIED="${S1_APPLIED:+$S1_APPLIED,}$f_id"
        case "$f_pri" in P1|P2) S1_FLOOR=1 ;; esac
      fi
      ;;
  esac

  if [ "$conf" = "LOW" ]; then
    if [ "$MODE" = "self" ]; then
      UNRESOLVED="${UNRESOLVED:+$UNRESOLVED,}$f_id"
    else
      NEEDS="${NEEDS:+$NEEDS,}$f_id"
      NEEDS_PRIORITIES="${NEEDS_PRIORITIES:+$NEEDS_PRIORITIES,}$f_id:$f_pri"
      NEEDS_COUNT=$((NEEDS_COUNT + 1))
    fi
    continue
  fi

  case "$f_pri" in
    P1) COUNT_P1=$((COUNT_P1 + 1)) ;;
    P2) COUNT_P2=$((COUNT_P2 + 1)) ;;
    P3) COUNT_P3=$((COUNT_P3 + 1)) ;;
  esac
  row="$f_id|$f_pri|$(encode "$f_cat")|$(encode "$f_loc")|open|$conf|$disp"
  MARKER="${MARKER:+$MARKER,}$row"
done

if [ "$S1_DEMOTED_SET" = 1 ]; then
  s1_rest="${S1_DEMOTED#,}"
  while [ -n "$s1_rest" ]; do
    s1_id="${s1_rest%%,*}"
    s1_rest="${s1_rest#*,}"
    case "$SEEN" in
      *",$s1_id,"*) ;;
      *) echo "LEDGER_WARN: PR#$PR --s1-demoted names '$s1_id', which is not in the rows" >&2 ;;
    esac
  done
fi

if [ "$ROWS_READ" -eq 0 ] && [ "$ALLOW_EMPTY" -ne 1 ]; then
  echo "ROWS_READ=0"
  echo "$PROG: no finding rows read; pass --allow-empty for a review that raised no findings" >&2
  exit 1
fi

if [ -n "$UNRESOLVED" ]; then
  echo "ROWS_READ=$ROWS_READ"
  echo "UNRESOLVED_LOW=$UNRESOLVED"
  echo "$PROG: LOW-confidence findings on the author's own pull request are unresolved: $UNRESOLVED — confirm each (fix it, re-record HIGH), refute it (record dropped-finding), or escalate it (re-record MEDIUM) before routing" >&2
  exit 3
fi

if [ "$MODE" = "self" ]; then
  DECISION="COMMENT"
elif [ $((COUNT_P1 + COUNT_P2)) -gt 0 ]; then
  DECISION="REQUEST_CHANGES"
elif [ "$COUNT_P3" -gt 0 ]; then
  DECISION="COMMENT"
else
  DECISION="APPROVE"
fi
# A System One demotion alone never approves: when it moved a P1 or P2 out of
# the counts, the review comments instead. A kept P1 is counted, so the
# decision is REQUEST_CHANGES already.
if [ "$S1_FLOOR" = 1 ] && [ "$DECISION" = "APPROVE" ]; then
  DECISION="COMMENT"
fi

echo "ROWS_READ=$ROWS_READ"
echo "COUNT_P1=$COUNT_P1"
echo "COUNT_P2=$COUNT_P2"
echo "COUNT_P3=$COUNT_P3"
echo "COUNT_NEEDS_INVESTIGATION=$NEEDS_COUNT"
echo "NEEDS_INVESTIGATION=$NEEDS"
echo "NEEDS_INVESTIGATION_PRIORITIES=$NEEDS_PRIORITIES"
echo "DECISION=$DECISION"
echo "MARKER_ROWS=$MARKER"
if [ "$S1_DEMOTED_SET" = 1 ]; then
  echo "S1_DEMOTED_APPLIED=$S1_APPLIED"
  echo "S1_KEPT_P1=$S1_KEPT"
fi
if [ "$MODE" = "self" ]; then
  echo "UNRESOLVED_LOW="
fi
exit 0
