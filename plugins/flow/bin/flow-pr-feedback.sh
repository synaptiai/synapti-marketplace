#!/usr/bin/env bash
# [flow] Print a pull request's review feedback, one JSON object per line.
#
# Usage:
#   flow-pr-feedback.sh <pr-number>
#
# The Collect step of skills/feedback-resolution/SKILL.md. Prints, in order:
#   - each inline review comment: {id, path, line, body, author}
#   - each review: {state, body, author}
#   - each conversation comment, on the pull request itself rather than on a
#     line: {id, kind: "conversation", body, author}
# Every page of each list: GitHub returns 30 items a page, and gh api
# --paginate prints one JSON array per page, which jq -s 'add' joins (the
# reads /flow:address makes, in commands/address.md).
#
# Exits: 0 when all three lists were read; 1 when a gh call failed, with
# nothing read after it; 2 on usage error (no PR number, or one that is not a
# positive whole number).

set -uo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH

PR_NUM="${1-}"
case "$PR_NUM" in
  ''|*[!0-9]*|0*) printf '%s\n' "usage: flow-pr-feedback.sh <pr-number>" >&2; exit 2 ;;
esac

REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner') || exit 1

# _all <api path> <jq filter> — every page of a list endpoint, joined, then
# one object per line through the filter. A failed gh call or a reply that is
# not JSON exits 1.
_all() {
  local pages joined
  pages=$(gh api --paginate "repos/$REPO/$1") || exit 1
  joined=$(printf '%s\n' "$pages" | jq -c -s 'add // []') || exit 1
  printf '%s\n' "$joined" | jq -c ".[] | $2" || exit 1
}
_all "pulls/$PR_NUM/comments" '{id: .id, path: .path, line: .line, body: .body, author: .user.login}'
_all "pulls/$PR_NUM/reviews" '{state: .state, body: .body, author: .user.login}'
_all "issues/$PR_NUM/comments" '{id: .id, kind: "conversation", body: .body, author: .user.login}'
