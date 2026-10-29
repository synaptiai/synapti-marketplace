#!/usr/bin/env bash
# [flow] Print a pull request's review feedback, one JSON object per line.
#
# Usage:
#   flow-pr-feedback.sh <pr-number>
#
# The Collect step of skills/feedback-resolution/SKILL.md. Prints, in order:
#   - each inline review comment: {id, path, line, body, author}
#   - each review: {state, body, author}
#
# Exits: 0 when both lists were read; 1 when a gh call failed; 2 on usage
# error (no PR number, or one that is not a positive whole number).

set -uo pipefail
# An exported CDPATH makes cd print the directory it found, which turns a
# captured `cd X && pwd` into two lines.
unset CDPATH

PR_NUM="${1-}"
case "$PR_NUM" in
  ''|*[!0-9]*|0*) printf '%s\n' "usage: flow-pr-feedback.sh <pr-number>" >&2; exit 2 ;;
esac

REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner') || exit 1
gh api "repos/$REPO/pulls/$PR_NUM/comments" --jq '.[] | {id: .id, path: .path, line: .line, body: .body, author: .user.login}' || exit 1
gh pr view "$PR_NUM" --json reviews --jq '.reviews[] | {state: .state, body: .body, author: .author.login}' || exit 1
