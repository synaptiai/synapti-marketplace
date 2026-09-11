#!/bin/bash
# [flow] PreToolUse hook: refuse a merge while its checks are unfinished.
#
# `/flow:merge` reads statusCheckRollup and will not proceed on a red or
# unfinished pull request. That gate only covers merges that go through the
# command. A `gh pr merge` typed straight into Bash consults nothing, and that
# is how a pull request came to be merged with twelve jobs still queued
# (issue #170).
#
# Two things are refused:
#
#   1. Any `gh pr merge` while a check is queued, running, or failed. The
#      checks are named, so the message says what to wait for.
#
#   2. `--auto` on a base branch with no required status checks. GitHub's
#      auto-merge waits for REQUIRED checks; where none are required it merges
#      at once. Reaching for `--auto` means "wait for CI", and on such a
#      repository it does the opposite of what the person asking for it wants.
#      Requiring branch protection is not this hook's business — issue #170
#      says so explicitly — but neither is letting its absence read as a
#      passing gate.
#
# What is NOT refused: a merge of a fully green pull request, by any route.
# `/flow:merge` on a green PR passes through untouched.
#
# The command is parsed, not matched. `echo "gh pr merge 3"` runs no merge, and
# a hook that reads text rather than commands refuses the bug report that
# describes it — the lesson of issues #167 and #142, whose parser this shares.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED: jq not available — cannot verify merge readiness. Install jq to proceed." >&2
  exit 2
fi
if ! command -v awk >/dev/null 2>&1; then
  echo "BLOCKED: awk not available — cannot verify merge readiness. Install awk to proceed." >&2
  exit 2
fi

_BD_LIB="$HOOK_DIR/lib/command-parse.sh"
if [ ! -r "$_BD_LIB" ]; then
  echo "BLOCKED: cannot read $_BD_LIB — the command parser is missing, so merge readiness cannot be verified." >&2
  exit 2
fi
# shellcheck source=lib/command-parse.sh
. "$_BD_LIB"

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && exit 0

# Cheap reject before any parsing: this hook runs before every Bash call.
case "$COMMAND" in *merge*) ;; *) exit 0 ;; esac

_bd_strip_noncode "$COMMAND"

# --- find a `gh pr merge`, in command position -------------------------------
MERGE_FOUND=0
PR_ARG=""
HAS_AUTO=0

while IFS= read -r SEG; do
  [ -z "$SEG" ] && continue
  case "$SEG" in *gh*) ;; *) continue ;; esac
  TOK=()
  _rm_tokenise "$SEG"
  n=${#TOK[@]}
  idx=-1
  for ((i = 0; i < n; i++)); do
    [ "${#TOK[i]}" -le 4096 ] || continue
    base="${TOK[i]##*/}"
    base="${base#\\}"
    if [ "$base" = "gh" ]; then idx=$i; break; fi
  done
  [ "$idx" -lt 0 ] && continue
  # gh pr merge — the two words must follow, options aside.
  sub1=""; sub2=""
  for ((i = idx + 1; i < n; i++)); do
    case "${TOK[i]}" in -*) continue ;; esac
    if [ -z "$sub1" ]; then sub1="${TOK[i]}"; continue; fi
    sub2="${TOK[i]}"; break
  done
  [ "$sub1" = "pr" ] || continue
  [ "$sub2" = "merge" ] || continue
  MERGE_FOUND=1
  seen_merge=0
  for ((i = idx + 1; i < n; i++)); do
    tok="${TOK[i]}"
    case "$tok" in
      --auto) HAS_AUTO=1; continue ;;
      -*) continue ;;
    esac
    if [ "$seen_merge" = "0" ]; then
      case "$tok" in
        pr) continue ;;
        merge) seen_merge=1; continue ;;
      esac
      continue
    fi
    _bd_is_redirection "$tok" && continue
    [ -z "$PR_ARG" ] && PR_ARG="$tok"
  done
  break
done < <(printf '%s\n' "$BD_CODE" | tr ';|&()`' '\n')

[ "$MERGE_FOUND" = "1" ] || exit 0

if ! command -v gh >/dev/null 2>&1; then
  echo "BLOCKED: gh pr merge, but the gh CLI is not on PATH — merge readiness cannot be checked." >&2
  exit 2
fi

# --- resolve the pull request ------------------------------------------------
# A merge with no explicit number targets the current branch. Say which pull
# request was judged, so a wrong-PR case is visible rather than silent.
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
if [ -z "$REPO" ]; then
  echo "BLOCKED: gh pr merge, but the repository could not be resolved — the checks cannot be read, so the merge is refused rather than guessed at." >&2
  exit 2
fi

PR_SEL=()
case "$PR_ARG" in
  ''|*[!0-9]*) ;;                       # no number, or a branch/URL: let gh resolve it
  *) PR_SEL=("$PR_ARG") ;;
esac

ROLLUP=$(gh pr view "${PR_SEL[@]:-}" --repo "$REPO" \
  --json number,baseRefName,statusCheckRollup 2>/dev/null)
if [ -z "$ROLLUP" ]; then
  echo "BLOCKED: gh pr merge, but the checks for that pull request could not be read (gh returned nothing). A gate that cannot see must not open." >&2
  exit 2
fi

PR_NUMBER=$(printf '%s' "$ROLLUP" | jq -r '.number // empty')
BASE=$(printf '%s' "$ROLLUP" | jq -r '.baseRefName // empty')

# Every entry, not only CheckRun. A legacy StatusContext carries `state`
# instead of `status`/`conclusion`, and counting only CheckRun made a pending
# StatusContext invisible.
UNFINISHED=$(printf '%s' "$ROLLUP" | jq -r '
  [ .statusCheckRollup[]?
    | if .__typename == "CheckRun"
      then select(.status != "COMPLETED") | "\(.name) [\(.status | ascii_downcase)]"
      else select(.state == "PENDING" or .state == "EXPECTED") | "\(.context) [pending]"
      end ]
  | join(", ")' 2>/dev/null)

FAILED=$(printf '%s' "$ROLLUP" | jq -r '
  [ .statusCheckRollup[]?
    | if .__typename == "CheckRun"
      then select(.conclusion == "FAILURE" or .conclusion == "TIMED_OUT" or .conclusion == "CANCELLED" or .conclusion == "STARTUP_FAILURE") | .name
      else select(.state == "FAILURE" or .state == "ERROR") | .context
      end ]
  | join(", ")' 2>/dev/null)

TOTAL=$(printf '%s' "$ROLLUP" | jq -r '[.statusCheckRollup[]?] | length' 2>/dev/null)
[ -z "$TOTAL" ] && TOTAL=0

if [ -n "$UNFINISHED" ]; then
  echo "BLOCKED: PR #$PR_NUMBER has checks that have not finished: $UNFINISHED" >&2
  echo "Wait for them (gh pr checks $PR_NUMBER --watch) and merge after they report." >&2
  exit 2
fi

if [ -n "$FAILED" ]; then
  echo "BLOCKED: PR #$PR_NUMBER has failing checks: $FAILED" >&2
  exit 2
fi

# --- --auto on a repository where it cannot wait ------------------------------
if [ "$HAS_AUTO" = "1" ]; then
  REQUIRED=""
  PROT=$(gh api "repos/$REPO/branches/$BASE/protection/required_status_checks" 2>/dev/null)
  if [ -n "$PROT" ]; then
    REQUIRED=$(printf '%s' "$PROT" | jq -r '[.contexts[]?] | join(", ")' 2>/dev/null)
  fi
  if [ -z "$REQUIRED" ]; then
    # Branch protection is not the only way to require a check; a ruleset can
    # too. Asking only the protection endpoint would report "none required" on
    # a repository that requires plenty.
    RULES=$(gh api "repos/$REPO/rules/branches/$BASE" 2>/dev/null)
    if [ -n "$RULES" ]; then
      REQUIRED=$(printf '%s' "$RULES" | jq -r '
        [ .[]? | select(.type == "required_status_checks")
          | .parameters.required_status_checks[]?.context ] | join(", ")' 2>/dev/null)
    fi
  fi
  if [ -z "$REQUIRED" ]; then
    echo "BLOCKED: --auto on PR #$PR_NUMBER, but '$BASE' requires no status checks." >&2
    echo "Auto-merge waits for REQUIRED checks. With none required it merges immediately, which is the opposite of what --auto is usually reached for." >&2
    echo "Every check on this PR has already passed ($TOTAL of $TOTAL), so merge without --auto if that is what you want." >&2
    exit 2
  fi
fi

exit 0
