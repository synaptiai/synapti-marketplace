#!/usr/bin/env bash
# dossier-rotation-check.sh — telemetry-only: report whether the rolling
# documentation branch would currently warrant rotation. Never takes any
# action.
#
# Usage:
#   dossier-rotation-check.sh [--github-output <file>] [--summary <file>]
#
# Flags:
#   --github-output <file>  append `key=value` lines here as well as to stdout
#   --summary <file>        append a human-readable markdown block here
#
# Untrusted inputs arrive through the environment, never as arguments:
#   BASE_REF   base branch name (falls back to the origin default branch)
#   GH_TOKEN   passed through to `gh`, never interpolated into a command
#
# Output (stdout, and --github-output when given):
#   would_rotate  reason  age_days  age_source
#   accumulated_files  accumulated_lines  docs_branch  rotation_policy
#
# Exit:
#   0 — a decision was reached (would_rotate may be true, false, or unknown)
#   1 — infrastructure failure (missing git/jq, not inside a git repository)
#   2 — bad arguments

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# The cascade reads ${CLAUDE_PLUGIN_ROOT}/settings.json for plugin defaults. In
# CI the plugin is checked out to an arbitrary path, so point the variable at
# this script's own plugin unless the harness already set a usable one.
if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] || [ ! -f "${CLAUDE_PLUGIN_ROOT:-}/settings.json" ]; then
  CLAUDE_PLUGIN_ROOT=$(dirname "$SCRIPT_DIR")
  export CLAUDE_PLUGIN_ROOT
fi
# Config is read through the resolver, not the raw cascade, so the documented
# DOSSIER_* environment layer applies — the same reasoning dossier-policy.sh
# gives for its own CASCADE variable. This script is telemetry-only and runs
# unconditionally in the policy job, so the same "safe here, before any agent
# runs" argument applies.
CASCADE="$SCRIPT_DIR/dossier-resolve-config.sh"

GITHUB_OUTPUT_FILE=""
SUMMARY_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --github-output)
      [ $# -lt 2 ] && { echo "dossier-rotation-check: --github-output requires a value" >&2; exit 2; }
      GITHUB_OUTPUT_FILE="$2"; shift 2 ;;
    --summary)
      [ $# -lt 2 ] && { echo "dossier-rotation-check: --summary requires a value" >&2; exit 2; }
      SUMMARY_FILE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,24p' "$0"; exit 0 ;;
    *)
      echo "dossier-rotation-check: unknown argument: $1" >&2; exit 2 ;;
  esac
done

BASE_REF="${BASE_REF:-}"

WOULD_ROTATE="unknown"
REASON="undecided"
AGE_DAYS=""
AGE_SOURCE="unknown"
ACC_FILES=""
ACC_LINES=""
DOCS_BRANCH=""
ROTATION_POLICY=""
NOTES=""

# Markdown-table and bullet-list cells are plain text interpolated with no
# escaping, so a config/event-derived value (DOCS_BRANCH, BASE_REF) carrying
# a backtick, pipe, or newline can break a table cell or inject a spoofed
# extra row into the rendered job summary an operator reads to decide
# whether rotation is warranted. Applied at every point a value reaches
# $SUMMARY_FILE — note()'s bullet text and write_summary()'s table cells —
# never to the working values themselves, which git commands need exact.
sanitize_md() {
  printf '%s' "$1" | LC_ALL=C tr -d '\000-\037' | tr -d '|`' | tr '\n' ' '
}

note() { NOTES="${NOTES}- $(sanitize_md "$1")
"; }

# $GITHUB_OUTPUT is parsed line by line as key=value, so a value carrying a
# newline does not merely render wrong — it forges additional output pairs for
# the next job to read. Every value written here is stripped of newlines and
# control characters first, whatever cascade layer it came from.
emit() {
  _v=$(printf '%s' "$2" | LC_ALL=C tr -d '\000-\037')
  printf '%s=%s\n' "$1" "$_v"
  if [ -n "$GITHUB_OUTPUT_FILE" ]; then
    printf '%s=%s\n' "$1" "$_v" >>"$GITHUB_OUTPUT_FILE"
  fi
  return 0
}

# An infrastructure failure is never reported as a reached decision — a silent
# "unknown" is indistinguishable from a healthy degraded read and would hide a
# broken runner from whoever reads the job summary.
die_infra() {
  echo "::error title=dossier rotation-check::$1" >&2
  emit would_rotate "unknown"
  emit reason "infrastructure-error"
  if [ -n "$SUMMARY_FILE" ]; then
    {
      printf '### Dossier rotation check: infrastructure error\n\n'
      printf '%s\n\n' "$(sanitize_md "$1")"
      printf 'The rotation determination could not be computed. This is a hard failure\n'
      printf 'rather than an "unknown" telemetry read.\n'
    } >>"$SUMMARY_FILE"
  fi
  exit 1
}

command -v git >/dev/null 2>&1 || die_infra "git is not installed on this runner."
command -v jq  >/dev/null 2>&1 || die_infra "jq is not installed; dossier configuration cannot be read."
git rev-parse --git-dir >/dev/null 2>&1 || die_infra "not inside a git repository (checkout step missing or failed)."

# $CASCADE exits 2 on infrastructure failure (missing jq, unreadable temp
# dir, etc; see dossier-resolve-config.sh's own documented exit codes) and 0
# for "resolved a value or returned the default" -- cfg() alone can't tell
# those apart from its caller's side, and every call site below checks the
# assignment's exit status with `|| die_infra ...` so a genuine resolver
# crash is never silently treated as a deliberate empty/default read. This
# check MUST happen in the same shell that calls cfg(), never inside a
# helper invoked as `X=$(helper ...)` -- die_infra()'s `exit 1` would then
# only terminate the command-substitution subshell, not the script.
cfg() { "$CASCADE" --default "$2" "${1#.}" 2>/dev/null; }

write_summary() {
  [ -n "$SUMMARY_FILE" ] || return 0
  {
    printf '### Dossier rolling-branch rotation check\n\n'
    printf 'Telemetry only — this step never rotates, closes, or deletes anything.\n\n'
    printf '| Field | Value |\n|---|---|\n'
    printf '| Would rotate | `%s` |\n' "$(sanitize_md "$WOULD_ROTATE")"
    printf '| Reason | `%s` |\n' "$(sanitize_md "$REASON")"
    printf '| Age (days) | `%s` |\n' "$(sanitize_md "${AGE_DAYS:-unknown}")"
    printf '| Age source | `%s` |\n' "$(sanitize_md "$AGE_SOURCE")"
    printf '| Accumulated files | `%s` |\n' "$(sanitize_md "${ACC_FILES:-unknown}")"
    printf '| Accumulated lines | `%s` |\n' "$(sanitize_md "${ACC_LINES:-unknown}")"
    printf '| Docs branch | `%s` |\n' "$(sanitize_md "$DOCS_BRANCH")"
    printf '| Rotation policy | `%s` |\n' "$(sanitize_md "$ROTATION_POLICY")"
    printf '\n'
    if [ -n "$NOTES" ]; then
      printf 'Notes:\n\n%s\n' "$NOTES"
    fi
  } >>"$SUMMARY_FILE"
  return 0
}

finish() {
  emit would_rotate        "$WOULD_ROTATE"
  emit reason               "$REASON"
  emit age_days              "$AGE_DAYS"
  emit age_source            "$AGE_SOURCE"
  emit accumulated_files     "$ACC_FILES"
  emit accumulated_lines     "$ACC_LINES"
  emit docs_branch           "$DOCS_BRANCH"
  emit rotation_policy       "$ROTATION_POLICY"
  write_summary
  exit 0
}

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DOCS_BRANCH=$(cfg '.dossier.ci.rollingBranch' 'docs/dossier') || die_infra "could not resolve dossier.ci.rollingBranch (configuration resolver failed)."
# An explicitly-empty override (DOSSIER_CI_ROLLING_BRANCH="" or
# "rollingBranch": "" in any settings file) beats every cascade layer by
# design (dossier-resolve-config.sh/cascade-resolve.sh both treat set-but-
# empty as a deliberate value, not "fall through to default"). Left
# unguarded, an empty DOCS_BRANCH reaches `git ls-remote --exit-code --heads
# origin ""`, which returns exit code 2 -- the SAME code this script uses to
# mean "the branch genuinely doesn't exist" -- producing a confidently wrong
# no-branch result even when the real docs branch exists and would
# otherwise warrant rotation. Verified live: exit code 2 either way.
case "$DOCS_BRANCH" in
  '')
    DOCS_BRANCH='docs/dossier'
    note "dossier.ci.rollingBranch resolved to an empty value; falling back to the documented default (docs/dossier)."
    ;;
esac
ROTATION_POLICY=$(cfg '.dossier.ci.rollingBranchRotation' 'none') || die_infra "could not resolve dossier.ci.rollingBranchRotation (configuration resolver failed)."
case "$ROTATION_POLICY" in
  '')
    ROTATION_POLICY='none'
    note "dossier.ci.rollingBranchRotation resolved to an empty value; falling back to the documented default (none)."
    ;;
esac
SIZE_THRESHOLD=$(cfg '.dossier.ci.thresholds.rotationMaxAccumulatedLines' '5000') || die_infra "could not resolve dossier.ci.thresholds.rotationMaxAccumulatedLines (configuration resolver failed)."
case "$SIZE_THRESHOLD" in
  ''|*[!0-9]*)
    SIZE_THRESHOLD=5000
    ;;
  0)
    SIZE_THRESHOLD=5000
    note "dossier.ci.thresholds.rotationMaxAccumulatedLines resolved to 0, which would make the size signal trigger unconditionally; falling back to the documented default (5000)."
    ;;
esac

if [ -z "$BASE_REF" ]; then
  BASE_REF=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
fi

NOW_EPOCH=$(date -u +%s)

# ---------------------------------------------------------------------------
# Step 1 — does the rolling branch exist at all?
# ---------------------------------------------------------------------------
git ls-remote --exit-code --heads origin "$DOCS_BRANCH" >/dev/null 2>&1
LS_REMOTE_RC=$?

if [ "$LS_REMOTE_RC" -eq 2 ]; then
  WOULD_ROTATE="false"
  REASON="the rolling branch does not exist yet; nothing to rotate"
  AGE_SOURCE="no-branch"
  AGE_DAYS=""
  ACC_FILES=""
  ACC_LINES=""
  finish
fi

if [ "$LS_REMOTE_RC" -ne 0 ]; then
  # Transport/auth failure — genuinely cannot tell. "rotation is disabled" is
  # a categorical fact independent of being able to measure the branch, so it
  # stays false even here; but when rotation IS enabled and we truly can't
  # tell, that must never look like a confident "false".
  AGE_SOURCE="unknown"
  AGE_DAYS=""
  ACC_FILES=""
  ACC_LINES=""
  note "could not reach the remote to check for ${DOCS_BRANCH} (git ls-remote exited ${LS_REMOTE_RC}); treating this as a transport failure, not a missing branch."
  if [ "$ROTATION_POLICY" = "none" ]; then
    WOULD_ROTATE="false"
    REASON="rotation is disabled (dossier.ci.rollingBranchRotation=none); the remote was also unreachable, so no metrics could be gathered"
  else
    WOULD_ROTATE="unknown"
    REASON="could not reach the remote to check ${DOCS_BRANCH} (transport failure); rotation status is unknown, not false"
  fi
  finish
fi

# ---------------------------------------------------------------------------
# Step 2 — branch exists. Fetch both refs explicitly: actions/checkout with
# fetch-depth:0 does not create origin/<branch> remote-tracking refs for
# branches other than the one checked out, so this script fetches them itself
# to stay standalone and locally callable.
# ---------------------------------------------------------------------------
FETCH_OK=1
if [ -z "$BASE_REF" ]; then
  FETCH_OK=0
  note "BASE_REF could not be resolved (no env var and no origin/HEAD symbolic ref); age and size cannot be measured against a base."
else
  git fetch --no-tags --prune origin "+refs/heads/${BASE_REF}:refs/remotes/origin/${BASE_REF}" >/dev/null 2>&1
  FETCH_BASE_RC=$?
  git fetch --no-tags origin "+refs/heads/${DOCS_BRANCH}:refs/remotes/origin/${DOCS_BRANCH}" >/dev/null 2>&1
  FETCH_DOCS_RC=$?
  if [ "$FETCH_BASE_RC" -ne 0 ] || [ "$FETCH_DOCS_RC" -ne 0 ]; then
    FETCH_OK=0
    note "could not fetch ${BASE_REF} and/or ${DOCS_BRANCH} from origin (base rc=${FETCH_BASE_RC}, docs rc=${FETCH_DOCS_RC}); treating this as a transport failure."
  fi
fi

if [ "$FETCH_OK" -eq 0 ]; then
  # Existence was already confirmed by step 1, so this is a transport failure,
  # not a no-branch state. Same "unknown, not zero" treatment as above.
  AGE_SOURCE="unknown"
  AGE_DAYS=""
  ACC_FILES=""
  ACC_LINES=""
  if [ "$ROTATION_POLICY" = "none" ]; then
    WOULD_ROTATE="false"
    REASON="rotation is disabled (dossier.ci.rollingBranchRotation=none); the base/docs refs could also not be fetched, so no metrics could be gathered"
  else
    WOULD_ROTATE="unknown"
    REASON="could not fetch the base and/or documentation refs (transport failure); rotation status is unknown, not false"
  fi
  finish
fi

# ---------------------------------------------------------------------------
# Step 2a/2b/2c — age. Prefer the open pull request's createdAt; fall back to
# walking the docs branch for the oldest Dossier-Generated commit.
# ---------------------------------------------------------------------------
if command -v gh >/dev/null 2>&1; then
  # --head matches by branch name only, across every fork with an open PR
  # against this repo -- an external fork could open a same-named decoy
  # branch to spoof the age lookup. isCrossRepository==false restricts the
  # match to PRs whose head lives in this repo (gh has no owner:branch
  # syntax for --head to scope this directly).
  PR_JSON=$(gh pr list --head "$DOCS_BRANCH" --state open --json number,createdAt,isCrossRepository --jq '[.[] | select(.isCrossRepository == false)][0]' 2>/dev/null)
  PR_LIST_RC=$?
  if [ "$PR_LIST_RC" -ne 0 ]; then
    # Distinct from "gh ran fine, no open PR found" (PR_JSON empty/null with
    # PR_LIST_RC=0) -- a nonzero exit means the lookup itself failed (auth,
    # rate limit, transient API error), which the summary should be able to
    # tell apart from a genuine "no PR open" outcome.
    note "gh pr list failed (exit ${PR_LIST_RC}); could not check for an open pull request on ${DOCS_BRANCH}."
  fi
  if [ -n "$PR_JSON" ] && [ "$PR_JSON" != "null" ]; then
    CREATED_AT=$(printf '%s' "$PR_JSON" | jq -r '.createdAt // empty' 2>/dev/null)
    if [ -n "$CREATED_AT" ]; then
      EPOCH=$(date -u -d "$CREATED_AT" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$CREATED_AT" +%s 2>/dev/null || echo "")
      if [ -n "$EPOCH" ]; then
        AGE_SOURCE="pr_created_at"
        AGE_DAYS=$(( (NOW_EPOCH - EPOCH) / 86400 ))
      fi
    fi
  fi
else
  note "gh CLI unavailable; falling back to walking ${DOCS_BRANCH} for the oldest Dossier-Generated commit."
fi

if [ "$AGE_SOURCE" != "pr_created_at" ]; then
  OLDEST_COMMIT=$(git rev-list --reverse "origin/${BASE_REF}..origin/${DOCS_BRANCH}" 2>/dev/null | while IFS= read -r C; do
    if git show -s --format=%B "$C" | grep -qiE '^Dossier-Generated:[[:space:]]*true[[:space:]]*$'; then
      printf '%s\n' "$C"
      break
    fi
  done)
  OLDEST_COMMIT=$(printf '%s\n' "$OLDEST_COMMIT" | head -1)
  if [ -n "$OLDEST_COMMIT" ]; then
    COMMIT_EPOCH=$(git show -s --format=%ct "$OLDEST_COMMIT" 2>/dev/null)
    if [ -n "$COMMIT_EPOCH" ]; then
      AGE_SOURCE="branch_commits"
      AGE_DAYS=$(( (NOW_EPOCH - COMMIT_EPOCH) / 86400 ))
    fi
  fi
  if [ "$AGE_SOURCE" != "branch_commits" ]; then
    AGE_SOURCE="unknown"
    AGE_DAYS=""
  fi
fi

# ---------------------------------------------------------------------------
# Step 2d — diff size, always computed once both refs are fetched. Parsed by
# keyword, not position: `git diff --shortstat` omits the insertions or
# deletions clause entirely when that count is zero, so a positional split
# would misread an insertions-only or deletions-only diff.
# ---------------------------------------------------------------------------
STAT=$(git diff --shortstat "origin/${BASE_REF}...origin/${DOCS_BRANCH}" 2>/dev/null)
DIFF_RC=$?
if [ "$DIFF_RC" -ne 0 ]; then
  ACC_FILES=""
  ACC_LINES=""
  note "git diff --shortstat origin/${BASE_REF}...origin/${DOCS_BRANCH} failed; accumulated size could not be measured."
else
  FILES=$(printf '%s' "$STAT" | grep -oE '[0-9]+ files? changed' | grep -oE '[0-9]+')
  INS=$(printf '%s'  "$STAT" | grep -oE '[0-9]+ insertions?\(\+\)' | grep -oE '[0-9]+')
  DEL=$(printf '%s'  "$STAT" | grep -oE '[0-9]+ deletions?\(-\)' | grep -oE '[0-9]+')
  # ${FILES:-0} defaults to 0 here ONLY because DIFF_RC==0 guarantees a
  # genuine empty-diff case, not a failure being papered over.
  ACC_FILES="${FILES:-0}"
  ACC_LINES=$(( ${INS:-0} + ${DEL:-0} ))
fi

# ---------------------------------------------------------------------------
# Step 3 — would_rotate determination.
# ---------------------------------------------------------------------------
if [ "$ROTATION_POLICY" = "none" ]; then
  WOULD_ROTATE="false"
  REASON="rotation is disabled (dossier.ci.rollingBranchRotation=none); reporting metrics only"
  finish
fi

case "$ROTATION_POLICY" in
  weekly)  THRESHOLD_DAYS=7 ;;
  monthly) THRESHOLD_DAYS=30 ;;
  *)
    note "dossier.ci.rollingBranchRotation is '${ROTATION_POLICY}', which is not one of none/weekly/monthly; treating it as if rotation were disabled."
    WOULD_ROTATE="false"
    REASON="rotation policy '${ROTATION_POLICY}' is not recognised (expected none, weekly, or monthly); reporting metrics only"
    finish
    ;;
esac

case "$AGE_DAYS" in ''|*[!0-9]*) AGE_KNOWN=0; AGE_DAYS="" ;; *) AGE_KNOWN=1 ;; esac
case "$ACC_LINES" in ''|*[!0-9]*) SIZE_KNOWN=0 ;; *) SIZE_KNOWN=1 ;; esac

AGE_TRIGGERED=0
[ "$AGE_KNOWN" -eq 1 ] && [ "$AGE_DAYS" -ge "$THRESHOLD_DAYS" ] && AGE_TRIGGERED=1
SIZE_TRIGGERED=0
[ "$SIZE_KNOWN" -eq 1 ] && [ "$ACC_LINES" -ge "$SIZE_THRESHOLD" ] && SIZE_TRIGGERED=1

# A confident "false" requires BOTH dimensions to have been measured and
# neither to have crossed its threshold. Whenever a dimension triggers, that
# alone is decisive regardless of the other dimension's state. But when
# NEITHER known dimension triggered and at least one dimension is unknown,
# the unmeasured dimension could still be over threshold — that must report
# "unknown", never a "false" that only happens to be right about the
# dimension it could measure.
if [ "$AGE_TRIGGERED" -eq 1 ] || [ "$SIZE_TRIGGERED" -eq 1 ]; then
  WOULD_ROTATE="true"
  PARTS=""
  if [ "$AGE_TRIGGERED" -eq 1 ]; then
    PARTS="age is ${AGE_DAYS} days (>= ${THRESHOLD_DAYS}-day ${ROTATION_POLICY} threshold)"
  fi
  if [ "$SIZE_TRIGGERED" -eq 1 ]; then
    if [ -n "$PARTS" ]; then
      PARTS="${PARTS}; accumulated size is ${ACC_LINES} lines (>= ${SIZE_THRESHOLD}-line threshold)"
    else
      PARTS="accumulated size is ${ACC_LINES} lines (>= ${SIZE_THRESHOLD}-line threshold)"
    fi
  fi
  REASON="would rotate: ${PARTS}"
elif [ "$AGE_KNOWN" -eq 0 ] || [ "$SIZE_KNOWN" -eq 0 ]; then
  WOULD_ROTATE="unknown"
  if [ "$AGE_KNOWN" -eq 0 ] && [ "$SIZE_KNOWN" -eq 0 ]; then
    REASON="rotation status could not be determined: age and accumulated size are both unavailable"
  elif [ "$AGE_KNOWN" -eq 0 ]; then
    REASON="rotation status could not be determined: age is unavailable; accumulated size is ${ACC_LINES} lines (< ${SIZE_THRESHOLD}-line threshold), but that alone cannot rule out rotation"
  else
    REASON="rotation status could not be determined: accumulated size is unavailable; age is ${AGE_DAYS} days (< ${THRESHOLD_DAYS}-day ${ROTATION_POLICY} threshold), but that alone cannot rule out rotation"
  fi
else
  WOULD_ROTATE="false"
  REASON="within threshold: age is ${AGE_DAYS} days (< ${THRESHOLD_DAYS}-day ${ROTATION_POLICY} threshold); accumulated size is ${ACC_LINES} lines (< ${SIZE_THRESHOLD}-line threshold)"
fi
finish
