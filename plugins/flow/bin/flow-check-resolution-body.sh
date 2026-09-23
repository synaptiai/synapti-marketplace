#!/usr/bin/env bash
# Refuse a resolution-comment body the merge finding-ledger gate would misread.
#
# Usage: flow-check-resolution-body.sh --cycle <N> < body
#        exit 0 — safe to post
#        exit 1 — refused, reason on stderr
#        exit 2 — called wrong
#
# Both emitters of FLOW_RESOLUTION_CYCLE call this: commands/review.md
# (RESOLUTION_COMMENT_BLOCK, self-review) and commands/address.md step 9
# (two-actor flow). The rule lived in review.md only, and address.md posted
# whatever it had composed. That asymmetry is the bug this file exists to end:
# the two are the same emitter wearing different hats, and a rule enforced in
# one of them is a rule an attacker routes around by choosing the other.
#
# Why any of it matters. references/finding-ledger-parser.md §3 extracts the
# arrays with `grep -o 'RESOLVED:\[[^]]*\]'` over the WHOLE comment body and
# unions every rendering it finds. templates/resolution-comment.md invites
# verbatim reviewer text into that body (`> {Quoted reviewer comment needing
# discussion}`), and per the Trust Boundary section of the same reference any
# GitHub user with comment access can supply that text. So a drive-by commenter
# writes a second RESOLVED array, the pull request author's /flow:address
# quotes it, and the marker is posted by a TRUSTED author — ids nobody resolved
# read as resolved and the merge gate opens. The innocent version needs no
# attacker at all: an author writing "Resolved F1 and F2, so RESOLVED:[F1,F2]
# below." ships the same wrong answer.

set -u
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH

CYCLE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --cycle)
      [ $# -ge 2 ] || { echo "ERROR: --cycle needs a value" >&2; exit 2; }
      CYCLE="$2"; shift 2 ;;
    --cycle=*) CYCLE="${1#--cycle=}"; shift ;;
    -h|--help)
      echo "usage: $(basename "$0") --cycle <N> < body" >&2; exit 2 ;;
    *) echo "ERROR: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

case "$CYCLE" in
  '') echo "ERROR: --cycle is required" >&2; exit 2 ;;
  *[!0-9]*) echo "ERROR: --cycle must be all digits, got '$CYCLE'" >&2; exit 2 ;;
esac

# `read -d ''`, NOT `$(cat)`. With fd 0 closed, command substitution allocates
# the pipe read end AS fd 0 and the parent then blocks on the substitution that
# holds the write end — a deadlock, reproduced here with `0<&-` (rc=124 under a
# 6s timeout). `read` reports EBADF and returns immediately, leaving BODY empty
# so the empty-body refusal below fires.
#
# The two readers are NOT byte-identical, measured. `$(cat)` strips every
# trailing newline and DROPS an embedded NUL, keeping the text after it;
# `read -d ''` keeps trailing newlines and STOPS at the first NUL. Neither
# difference is reachable from the callers: a bash variable cannot hold a NUL at
# all, and every check below reads tokens rather than counting newlines. The
# here-string appends one newline to whatever the value already ends with, which
# is why nothing here depends on the exact trailing count.
BODY=""
IFS= read -r -d '' BODY || true

if [ -z "$BODY" ]; then
  echo "ERROR: the resolution body is empty; refusing to post a marker-less comment" >&2
  exit 1
fi

# Match with the predicate the CONSUMER uses, not a looser one. The merge gate
# selects this comment with `test("<!-- FLOW_RESOLUTION_CYCLE:[0-9]+ ")`, so a
# body carrying the bare token, or the marker without the HTML comment around
# it, is invisible to the gate and leaves every resolved finding reading
# unresolved. The gate selects on that prefix only, so this must not demand more
# than it does around the arrays: the whitespace before `-->` is optional, or a
# marker the gate accepts would be refused here.
MARKERS=$(grep -oE "<!-- FLOW_RESOLUTION_CYCLE:$CYCLE RESOLVED:\[[^]]*\] ESCALATED:\[[^]]*\] DISPUTED:\[[^]]*\] *-->" <<<"$BODY" | wc -l | tr -d ' ')
if [ "$MARKERS" != 1 ]; then
  echo "ERROR: the resolution body carries $MARKERS markers of the shape the merge gate selects; it needs exactly one: <!-- FLOW_RESOLUTION_CYCLE:$CYCLE RESOLVED:[...] ESCALATED:[...] DISPUTED:[...] -->" >&2
  exit 1
fi

# The gate greps the arrays out of the whole comment and unions what it finds,
# so a second rendering anywhere — including later on the same line — adds ids
# nobody resolved. Count occurrences, not lines.
for __array in 'RESOLVED:[' 'ESCALATED:[' 'DISPUTED:['; do
  # The marker matched above already carries each array once, so this counts the
  # renderings beside it rather than their presence.
  __rendered=$(grep -oF "$__array" <<<"$BODY" | wc -l | tr -d ' ')
  if [ "$__rendered" != 1 ]; then
    echo "ERROR: the resolution body renders $__array $__rendered times; the merge gate unions every rendering, so ids nobody resolved would read as resolved — reword the prose (for example with a space before the bracket)" >&2
    exit 1
  fi
done

exit 0
