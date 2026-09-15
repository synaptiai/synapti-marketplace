#!/usr/bin/env bash
# [flow] Print the issue a pull request is linked to, as GitHub records it.
#
# The linked issue is one GitHub lists in the pull request's
# closingIssuesReferences: the issues it closes on merge, however the body
# phrases them (`Closes #N`, `Fixes owner/repo#N`, an issue URL, or a link made
# in the sidebar). The body text is never parsed, so a mention before the
# closing keyword, a word such as `hotfix #210`, or a keyword quoted in a code
# span cannot choose the journal a record is written to. When GitHub lists no
# issue, this prints nothing and the caller skips its record; GitHub's own
# documentation says a closing keyword links an issue only in a pull request
# into the default branch, so that is one case where nothing is listed.
#
# Only issues in --repo count. When several are listed, the lowest number is
# printed and a NOTE on stderr names them all, so every caller that records
# against the pull request's issue picks the same one.
#
# Callers: commands/review.md (Phase 1, A.4, Phase 4 steps 5 and 7, the
# workflow-run record) and commands/merge.md (escalation-resolved record).
#
# Usage:
#   flow-pr-linked-issue.sh --pr <N> --repo <owner/name>
#
# Output: the issue number on stdout, or nothing when no issue in the
# repository is listed.
#
# Exits:
#   0 — printed the issue, or nothing when none is listed
#   1 — usage error
#   2 — gh could not read the pull request (nothing on stdout)

set -uo pipefail

PROG="flow-pr-linked-issue.sh"

usage() {
  echo "usage: $PROG --pr <N> --repo <owner/name>" >&2
}

PR=""
REPO=""
PR_SET=0
REPO_SET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --pr) [ $# -ge 2 ] || { usage; exit 1; }; PR="$2"; PR_SET=1; shift 2 ;;
    --repo) [ $# -ge 2 ] || { usage; exit 1; }; REPO="$2"; REPO_SET=1; shift 2 ;;
    *) echo "$PROG: unknown argument" >&2; usage; exit 1 ;;
  esac
done

[ "$PR_SET" = 1 ] && [ "$REPO_SET" = 1 ] || { usage; exit 1; }
case "$PR" in
  ''|0*|*[!0-9]*) echo "$PROG: --pr must be a positive integer" >&2; exit 1 ;;
esac
# The repository is written into the jq filter below, so only the characters
# GitHub allows in an owner and a repository name are accepted.
if ! LC_ALL=C printf '%s' "$REPO" | grep -Eqx '[A-Za-z0-9._-]+/[A-Za-z0-9._-]+'; then
  echo "$PROG: --repo must be owner/name" >&2
  exit 1
fi

FILTER='[.closingIssuesReferences[]
  | select(((.repository.owner.login + "/" + .repository.name) | ascii_downcase) == ("'"$REPO"'" | ascii_downcase))
  | .number] | sort | map(tostring) | join(",")'

if ! LIST=$(gh pr view "$PR" --repo "$REPO" --json closingIssuesReferences --jq "$FILTER"); then
  echo "$PROG: cannot read the closing issues of pull request $PR in $REPO" >&2
  exit 2
fi

case "$LIST" in
  '') exit 0 ;;
  *[!0-9,]*) echo "$PROG: unexpected closing-issue list for pull request $PR" >&2; exit 2 ;;
esac
case "$LIST" in
  *,*) echo "NOTE: pull request $PR closes issues ${LIST//,/, }; recording against #${LIST%%,*}" >&2 ;;
esac
printf '%s\n' "${LIST%%,*}"
