#!/usr/bin/env bash
# dossier-policy.sh — decide whether a documentation refresh should run, and
# resolve the commit range it would document.
#
# This script is the single source of policy truth. The workflow YAML carries
# only the guards GitHub must evaluate before a runner exists (the job-level
# `if:`); everything expressible at runtime lives here, so a policy change needs
# no workflow edit and behaves identically for a local `/dossier:refresh`.
#
# Usage:
#   dossier-policy.sh [--github-output <file>] [--summary <file>] [--base <sha>]
#
# Flags:
#   --github-output <file>  append `key=value` lines here as well as to stdout
#   --summary <file>        append a human-readable markdown block here
#   --base <sha>            override the resolved watermark (highest precedence)
#
# Untrusted inputs arrive through the environment, never as arguments, so that
# no attacker-controlled string is ever word-split into this script's argv:
#   EVT             triggering event name (pull_request, schedule, …)
#   PR_NUMBER       triggering pull request number
#   PR_MERGE_SHA    pull_request.merge_commit_sha — the real merge commit on the
#                   base branch. NOT github.sha, which for pull_request events
#                   is a throwaway test-merge commit that is not on any branch.
#   PR_HEAD_REF     head branch name of the triggering pull request
#   PR_BASE_REF     base branch name of the triggering pull request
#   PR_IS_FORK      "true" when the PR came from a fork
#   PR_LABELS       label names, one per line or comma-separated
#   PR_ACTOR        login that opened/merged the PR
#   DISPATCH_FORCE  "true" to bypass the advisory rules
#   DISPATCH_BASE   explicit base sha supplied via workflow_dispatch
#
# Output (stdout, and --github-output when given):
#   should_run  base_sha  head_sha  base_source  docs_branch
#   reason      existing_pr  max_turns  model  model_arg
#
# Exit:
#   0 — a decision was reached (should_run may be true or false)
#   1 — infrastructure failure; the decision is unknown and must not be guessed
#   2 — missing or invalid argument

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
# DOSSIER_* environment layer applies. schema.json calls that layer "what lets a
# CI job run with zero interaction", and this script is one of the two that run
# in the unattended `policy` job — reading the file cascade directly made the
# documented escape hatch dead code for the surface it exists for. Safe here
# because this job runs before any agent does; the patch validator deliberately
# does NOT do this, for the opposite reason.
CASCADE="$SCRIPT_DIR/dossier-resolve-config.sh"

GITHUB_OUTPUT_FILE=""
SUMMARY_FILE=""
BASE_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --github-output)
      [ $# -lt 2 ] && { echo "dossier-policy: --github-output requires a value" >&2; exit 2; }
      GITHUB_OUTPUT_FILE="$2"; shift 2 ;;
    --summary)
      [ $# -lt 2 ] && { echo "dossier-policy: --summary requires a value" >&2; exit 2; }
      SUMMARY_FILE="$2"; shift 2 ;;
    --base)
      [ $# -lt 2 ] && { echo "dossier-policy: --base requires a value" >&2; exit 2; }
      BASE_OVERRIDE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,40p' "$0"; exit 0 ;;
    *)
      echo "dossier-policy: unknown argument: $1" >&2; exit 2 ;;
  esac
done

EVT="${EVT:-}"
PR_NUMBER="${PR_NUMBER:-}"
PR_MERGE_SHA="${PR_MERGE_SHA:-}"
PR_HEAD_REF="${PR_HEAD_REF:-}"
PR_BASE_REF="${PR_BASE_REF:-}"
PR_IS_FORK="${PR_IS_FORK:-}"
PR_LABELS="${PR_LABELS:-}"
PR_ACTOR="${PR_ACTOR:-}"
DISPATCH_FORCE="${DISPATCH_FORCE:-}"
DISPATCH_BASE="${DISPATCH_BASE:-}"

SHOULD_RUN="false"
REASON="undecided"
BASE_SHA=""
HEAD_SHA=""
BASE_SOURCE="none"
DOCS_BRANCH=""
EXISTING_PR=""
MAX_TURNS=""
MODEL=""
MODEL_ARG=""
NOTES=""

TMPDIR_POLICY=$(mktemp -d -t dossier-policy.XXXXXX) || {
  echo "dossier-policy: cannot create a temporary file or directory" >&2; exit 1;
}
mkdir -p "$TMPDIR_POLICY" 2>/dev/null
cleanup() { rm -rf "$TMPDIR_POLICY" 2>/dev/null; }
trap cleanup EXIT

note() { NOTES="${NOTES}- $1
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

# An infrastructure failure is never reported as "no refresh needed" — a silent
# skip is indistinguishable from a healthy no-op and lets documentation rot while
# the workflow stays green.
die_infra() {
  echo "::error title=dossier policy::$1" >&2
  emit should_run "false"
  emit reason "infrastructure-error"
  if [ -n "$SUMMARY_FILE" ]; then
    {
      printf '### Dossier policy: infrastructure error\n\n'
      printf '%s\n\n' "$1"
      printf 'The refresh decision could not be computed. This is a hard failure rather\n'
      printf 'than a skip: a skipped run and a healthy no-op look identical afterwards.\n'
    } >>"$SUMMARY_FILE"
  fi
  exit 1
}

command -v git >/dev/null 2>&1 || die_infra "git is not installed on this runner."
command -v jq  >/dev/null 2>&1 || die_infra "jq is not installed; dossier configuration cannot be read."
git rev-parse --git-dir >/dev/null 2>&1 || die_infra "not inside a git repository (checkout step missing or failed)."

cfg()     { "$CASCADE" --default "$2" "${1#.}" 2>/dev/null; }
cfg_arr() { "$CASCADE" --compact --default '[]' "${1#.}" 2>/dev/null | jq -r '.[]? // empty' 2>/dev/null; }

# Translate a glob (`**`, `*`, `?`, `{a,b}`) into an anchored POSIX ERE.
# Hand-rolled rather than delegated to bash pathname expansion because the
# candidate paths come from `git diff --name-only`, not from the filesystem —
# they routinely name files that no longer exist in the working tree.
glob_to_ere() {
  awk -v g="$1" '
    BEGIN {
      n = length(g); out = ""; inbrace = 0;
      for (i = 1; i <= n; i++) {
        ch = substr(g, i, 1);
        if (ch == "*") {
          if (substr(g, i + 1, 1) == "*") {
            if (substr(g, i + 2, 1) == "/") { out = out "(.*/)?"; i += 2 }
            else { out = out ".*"; i += 1 }
          } else { out = out "[^/]*" }
        }
        else if (ch == "?")                    { out = out "[^/]" }
        else if (ch == "{")                    { out = out "("; inbrace = 1 }
        else if (ch == "}")                    { out = out ")"; inbrace = 0 }
        else if (ch == "," && inbrace)         { out = out "|" }
        else if (index(".[]^$()|+\\", ch) > 0) { out = out "\\" ch }
        else                                   { out = out ch }
      }
      print "^" out "$";
    }'
}

build_ere_file() {
  DEST="$1"; JQ_PATH="$2"
  : >"$DEST"
  cfg_arr "$JQ_PATH" | while IFS= read -r G; do
    [ -n "$G" ] || continue
    glob_to_ere "$G" >>"$DEST"
  done
}

# Case-insensitive membership test over the newline/comma separated label list.
has_label() {
  WANT=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  [ -n "$WANT" ] || return 1
  printf '%s' "$PR_LABELS" \
    | tr ',' '\n' \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | grep -qxF "$WANT"
}

iso_24h_ago() {
  date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -v-24H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || printf ''
}

write_summary() {
  [ -n "$SUMMARY_FILE" ] || return 0
  {
    printf '### Dossier refresh policy\n\n'
    printf '| Field | Value |\n|---|---|\n'
    printf '| Decision | `%s` |\n' "$SHOULD_RUN"
    printf '| Reason | `%s` |\n' "$REASON"
    printf '| Event | `%s` |\n' "${EVT:-unknown}"
    printf '| Base | `%s` |\n' "${BASE_SHA:-unresolved}"
    printf '| Base source | `%s` |\n' "$BASE_SOURCE"
    printf '| Head | `%s` |\n' "${HEAD_SHA:-unresolved}"
    printf '| Docs branch | `%s` |\n' "$DOCS_BRANCH"
    printf '| Existing docs PR | `%s` |\n' "${EXISTING_PR:-none}"
    printf '\n'
    if [ -n "$NOTES" ]; then
      printf 'Notes:\n\n%s\n' "$NOTES"
    fi
  } >>"$SUMMARY_FILE"
  return 0
}

finish() {
  emit should_run  "$SHOULD_RUN"
  emit reason      "$REASON"
  emit base_sha    "$BASE_SHA"
  emit head_sha    "$HEAD_SHA"
  emit base_source "$BASE_SOURCE"
  emit docs_branch "$DOCS_BRANCH"
  emit existing_pr "$EXISTING_PR"
  emit max_turns   "$MAX_TURNS"
  emit model       "$MODEL"
  emit model_arg   "$MODEL_ARG"
  write_summary
  exit 0
}

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

CI_ENABLED=$(cfg '.dossier.ci.enabled' 'true')
OUTPUT_ROOT=$(cfg '.dossier.project.outputRoot' 'docs/dossier')
DOCS_BRANCH=$(cfg '.dossier.ci.rollingBranch' 'docs/dossier')
LABEL_GENERATED=$(cfg '.dossier.ci.labels.generated' 'dossier:generated')
LABEL_FORCE=$(cfg '.dossier.ci.labels.force' 'docs:refresh')
LABEL_SKIP=$(cfg '.dossier.ci.labels.skip' 'docs:skip')
MIN_CHANGED_FILES=$(cfg '.dossier.ci.thresholds.minChangedFiles' '1')
MAX_DIFF_LINES=$(cfg '.dossier.ci.thresholds.maxSourceDiffLines' '50000')
MAX_PRS_24H=$(cfg '.dossier.ci.circuitBreaker.maxDocPrsPer24h' '6')
SCHEDULE_MIN_COMMITS=$(cfg '.dossier.ci.schedule.minCommits' '1')
MAX_TURNS=$(cfg '.dossier.ci.agent.maxTurns' '60')
MODEL=$(cfg '.dossier.ci.agent.model' '')
# schema.json constrains this to a single bare token because the value is
# interpolated into the workflow's claude_args block, where whitespace would
# split into stray arguments ahead of the --allowedTools/--disallowedTools flags
# that bound the agent. dossier-validate-config.sh enforces that pattern, but it
# does not run in the workflow — so the constraint is re-checked at the point of
# use rather than trusted to have been checked somewhere upstream.
if [ -n "$MODEL" ]; then
  case "$MODEL" in
    *[!A-Za-z0-9._-]*)
      die_infra "dossier.ci.agent.model must be a single bare token matching [A-Za-z0-9._-]+; got a value containing whitespace or a shell metacharacter."
      ;;
  esac
  MODEL_ARG="--model $MODEL"
fi

INC_ERE="$TMPDIR_POLICY/include.ere"
EXC_ERE="$TMPDIR_POLICY/exclude.ere"
build_ere_file "$INC_ERE" '.dossier.ci.pathFilters.include'
build_ere_file "$EXC_ERE" '.dossier.ci.pathFilters.exclude'

# ---------------------------------------------------------------------------
# Rule 1 — disabled. Checked before any git work so the master switch is the
# cheapest possible exit.
# ---------------------------------------------------------------------------
if [ "$CI_ENABLED" = "false" ]; then
  SHOULD_RUN="false"; REASON="disabled"
  note 'dossier.ci.enabled is false. Set it to true in .claude/settings.dossier.json to re-enable.'
  finish
fi

# ---------------------------------------------------------------------------
# Head resolution
# ---------------------------------------------------------------------------
if [ "$EVT" = "pull_request" ] || [ "$EVT" = "pull_request_target" ]; then
  if [ -n "$PR_MERGE_SHA" ] && git cat-file -e "${PR_MERGE_SHA}^{commit}" 2>/dev/null; then
    HEAD_SHA="$PR_MERGE_SHA"
  else
    # The merge commit can be momentarily unfetchable right after a merge, and
    # is absent entirely when a PR is closed without merging. The checked-out
    # base branch tip is the correct, always-reachable substitute.
    HEAD_SHA=$(git rev-parse HEAD 2>/dev/null)
    [ -n "$PR_MERGE_SHA" ] && note "merge_commit_sha ${PR_MERGE_SHA} is not reachable in this checkout; using the checked-out tip instead."
  fi
else
  HEAD_SHA=$(git rev-parse HEAD 2>/dev/null)
fi
[ -n "$HEAD_SHA" ] || die_infra "could not resolve HEAD."

# ---------------------------------------------------------------------------
# Watermark resolution
#
# Two independent sources, deliberately: the state file advances only when a
# docs PR actually merges (durable, survives ref pruning), while the cursor ref
# advances on every successful run including no-ops (fine-grained, avoids
# re-reading a range whose refresh produced nothing). They are combined by
# ancestry rather than by preference so neither can silently rewind the other.
# ---------------------------------------------------------------------------
STATE_SHA=""
STATE_FILE="$OUTPUT_ROOT/.dossier-state.json"
if [ -f "$STATE_FILE" ]; then
  STATE_SHA=$(jq -r '.last_documented_sha // empty' "$STATE_FILE" 2>/dev/null)
  if [ -n "$STATE_SHA" ] && ! git cat-file -e "${STATE_SHA}^{commit}" 2>/dev/null; then
    note "last_documented_sha ${STATE_SHA} in ${STATE_FILE} is not a reachable commit; ignoring it."
    STATE_SHA=""
  fi
fi

CURSOR_SHA=$(git rev-parse --verify --quiet 'refs/dossier/cursor^{commit}' 2>/dev/null)
if [ -n "$CURSOR_SHA" ] && ! git cat-file -e "${CURSOR_SHA}^{commit}" 2>/dev/null; then
  CURSOR_SHA=""
fi

if [ -n "$BASE_OVERRIDE" ]; then
  BASE_SHA="$BASE_OVERRIDE"; BASE_SOURCE="flag-override"
elif [ -n "$DISPATCH_BASE" ]; then
  BASE_SHA="$DISPATCH_BASE"; BASE_SOURCE="dispatch-input"
elif [ -n "$STATE_SHA" ] && [ -n "$CURSOR_SHA" ]; then
  if [ "$STATE_SHA" = "$CURSOR_SHA" ]; then
    BASE_SHA="$STATE_SHA"; BASE_SOURCE="state-file+cursor-ref"
  elif git merge-base --is-ancestor "$STATE_SHA" "$CURSOR_SHA" 2>/dev/null; then
    BASE_SHA="$CURSOR_SHA"; BASE_SOURCE="cursor-ref"
  elif git merge-base --is-ancestor "$CURSOR_SHA" "$STATE_SHA" 2>/dev/null; then
    BASE_SHA="$STATE_SHA"; BASE_SOURCE="state-file"
  else
    # Divergent watermarks (history rewrite, or a docs PR merged from a rebased
    # branch). Their merge base is the newest commit both agree is documented;
    # anything newer is re-examined. Widening the range can only cost tokens,
    # while narrowing it would silently drop changes.
    BASE_SHA=$(git merge-base "$STATE_SHA" "$CURSOR_SHA" 2>/dev/null)
    BASE_SOURCE="merge-base-of-divergent-watermarks"
    note "state file and cursor ref have diverged; documenting from their merge base."
  fi
elif [ -n "$STATE_SHA" ]; then
  BASE_SHA="$STATE_SHA"; BASE_SOURCE="state-file"
elif [ -n "$CURSOR_SHA" ]; then
  BASE_SHA="$CURSOR_SHA"; BASE_SOURCE="cursor-ref"
else
  BASE_SHA=$(git rev-list --max-parents=0 "$HEAD_SHA" 2>/dev/null | tail -1)
  BASE_SOURCE="cold-start"
  note 'No watermark found. Treating this as a cold start: the range spans the whole reachable history.'
fi

# Guard the base regardless of how it was chosen — an operator-supplied
# --base/DISPATCH_BASE typo would otherwise surface as an opaque git error
# several steps later.
if [ -z "$BASE_SHA" ] || ! git cat-file -e "${BASE_SHA}^{commit}" 2>/dev/null; then
  if [ "$BASE_SOURCE" = "flag-override" ] || [ "$BASE_SOURCE" = "dispatch-input" ]; then
    die_infra "supplied base '${BASE_SHA}' is not a commit in this repository."
  fi
  note "resolved base '${BASE_SHA}' (${BASE_SOURCE}) is unreachable; falling back to the repository root commit."
  BASE_SHA=$(git rev-list --max-parents=0 "$HEAD_SHA" 2>/dev/null | tail -1)
  BASE_SOURCE="cold-start-after-unreachable-watermark"
fi
[ -n "$BASE_SHA" ] || die_infra "could not resolve any usable base commit."

case "$BASE_SOURCE" in
  cold-start*) IS_COLD_START=1 ;;
  *)           IS_COLD_START=0 ;;
esac

# ---------------------------------------------------------------------------
# Existing docs PR (advisory; drives the publish job's create-vs-update path).
# Absent gh is a degradation, not a failure: publish rediscovers the PR with a
# privileged token anyway.
# ---------------------------------------------------------------------------
if command -v gh >/dev/null 2>&1; then
  EXISTING_PR=$(gh pr list --head "$DOCS_BRANCH" --state open --json number --jq '.[0].number // empty' 2>/dev/null)
else
  note 'gh CLI unavailable; existing-PR lookup and the circuit-breaker count were skipped.'
fi

# ---------------------------------------------------------------------------
# Rule 2 — forced. A deliberate human override short-circuits the advisory
# rules below it, but never the base/head resolution above it.
# ---------------------------------------------------------------------------
FORCED=0
[ "$DISPATCH_FORCE" = "true" ] && FORCED=1
has_label "$LABEL_FORCE" && FORCED=1

# ---------------------------------------------------------------------------
# Rule 3 — opted out.
# ---------------------------------------------------------------------------
if [ $FORCED -eq 0 ]; then
  if has_label "$LABEL_SKIP"; then
    SHOULD_RUN="false"; REASON="opted-out"
    note "The triggering pull request carries the '${LABEL_SKIP}' label."
    finish
  fi
  if git log --format='%s%n%b' "$BASE_SHA..$HEAD_SHA" 2>/dev/null \
       | grep -qiE '\[(skip docs|docs skip|no docs)\]'; then
    SHOULD_RUN="false"; REASON="opted-out"
    note 'A commit in the range carries a [skip docs] marker.'
    finish
  fi
fi

# ---------------------------------------------------------------------------
# Rule 4 — loop guard. The workflow's job-level `if:` already blocks this before
# a runner is allocated; this is the runtime backstop for the paths that `if:`
# cannot see (schedule sweeps, workflow_dispatch, a hand-edited workflow).
# ---------------------------------------------------------------------------
if [ $FORCED -eq 0 ]; then
  LOOPED=0
  case "$PR_HEAD_REF" in
    "$DOCS_BRANCH"|"$DOCS_BRANCH"/*) LOOPED=1 ;;
  esac
  has_label "$LABEL_GENERATED" && LOOPED=1
  case "$PR_ACTOR" in
    'github-actions[bot]'|*'[bot]') LOOPED=1 ;;
  esac
  if [ $LOOPED -eq 1 ]; then
    SHOULD_RUN="false"; REASON="loop-guard"
    note 'The trigger originated from a dossier-generated pull request. Refusing to document our own documentation.'
    finish
  fi
fi

# ---------------------------------------------------------------------------
# Rule 5 — circuit open. Bounds runaway loops, not per-run cost: GitHub Actions
# has no spend cap for third-party API calls.
# ---------------------------------------------------------------------------
if [ $FORCED -eq 0 ] && command -v gh >/dev/null 2>&1; then
  SINCE=$(iso_24h_ago)
  if [ -n "$SINCE" ]; then
    RECENT=$(gh pr list --state all --limit 100 --label "$LABEL_GENERATED" \
               --json createdAt --jq "[.[] | select(.createdAt > \"$SINCE\")] | length" 2>/dev/null)
    case "$RECENT" in
      ''|*[!0-9]*) note 'Circuit-breaker count could not be read from the GitHub API; the breaker was not evaluated.' ;;
      *)
        if [ "$RECENT" -ge "$MAX_PRS_24H" ]; then
          SHOULD_RUN="false"; REASON="circuit-open"
          note "${RECENT} documentation pull requests were opened in the last 24 hours (limit ${MAX_PRS_24H}). Investigate before raising dossier.ci.circuitBreaker.maxDocPrsPer24h."
          finish
        fi
        ;;
    esac
  else
    note 'Could not compute a 24-hour cutoff on this platform; the circuit breaker was not evaluated.'
  fi
fi

# ---------------------------------------------------------------------------
# Rule 6 — up to date.
# ---------------------------------------------------------------------------
if [ "$BASE_SHA" = "$HEAD_SHA" ]; then
  SHOULD_RUN="false"; REASON="up-to-date"
  note 'The watermark already equals the head commit; there is nothing undocumented.'
  finish
fi

# Changed-file set. Three-dot semantics answer "what arrived on the way to
# HEAD", which is what documentation cares about; two-dot would additionally
# report base-side commits as reversals when the watermark has diverged.
ALL_FILES="$TMPDIR_POLICY/all-files.txt"
if ! git diff --name-only --no-renames "$BASE_SHA...$HEAD_SHA" >"$ALL_FILES" 2>/dev/null; then
  git diff --name-only --no-renames "$BASE_SHA" "$HEAD_SHA" >"$ALL_FILES" 2>/dev/null \
    || die_infra "could not diff ${BASE_SHA}..${HEAD_SHA}."
  note 'Histories are unrelated; fell back to a two-dot diff.'
fi

INCLUDED="$TMPDIR_POLICY/included.txt"
RELEVANT="$TMPDIR_POLICY/relevant.txt"
if [ -s "$INC_ERE" ]; then
  grep -E -f "$INC_ERE" "$ALL_FILES" >"$INCLUDED" 2>/dev/null
  [ -f "$INCLUDED" ] || : >"$INCLUDED"
else
  cp "$ALL_FILES" "$INCLUDED"
fi
if [ -s "$EXC_ERE" ]; then
  grep -E -v -f "$EXC_ERE" "$INCLUDED" >"$RELEVANT" 2>/dev/null
  [ -f "$RELEVANT" ] || : >"$RELEVANT"
else
  cp "$INCLUDED" "$RELEVANT"
fi

RELEVANT_COUNT=$(grep -c . "$RELEVANT" 2>/dev/null | tr -d ' ')
[ -n "$RELEVANT_COUNT" ] || RELEVANT_COUNT=0
COMMIT_COUNT=$(git rev-list --count "$BASE_SHA..$HEAD_SHA" 2>/dev/null | tr -d ' ')
[ -n "$COMMIT_COUNT" ] || COMMIT_COUNT=0

# ---------------------------------------------------------------------------
# Rule 7 — no relevant paths. Rules 7 to 9 are what make the scheduled sweep
# nearly free on a quiet repository: roughly forty seconds of runner time and
# zero tokens.
# ---------------------------------------------------------------------------
if [ $FORCED -eq 0 ] && [ "$RELEVANT_COUNT" -eq 0 ]; then
  SHOULD_RUN="false"; REASON="no-relevant-paths"
  note "The range touches $(grep -c . "$ALL_FILES" 2>/dev/null | tr -d ' ') files, none of which survive dossier.ci.pathFilters."
  finish
fi

# ---------------------------------------------------------------------------
# Rule 8 — below threshold.
# ---------------------------------------------------------------------------
if [ $FORCED -eq 0 ]; then
  if [ "$RELEVANT_COUNT" -lt "$MIN_CHANGED_FILES" ]; then
    SHOULD_RUN="false"; REASON="below-threshold"
    note "${RELEVANT_COUNT} relevant files changed, below dossier.ci.thresholds.minChangedFiles (${MIN_CHANGED_FILES})."
    finish
  fi
  if [ "$EVT" = "schedule" ] && [ "$COMMIT_COUNT" -lt "$SCHEDULE_MIN_COMMITS" ]; then
    SHOULD_RUN="false"; REASON="below-threshold"
    note "${COMMIT_COUNT} commits since the watermark, below dossier.ci.schedule.minCommits (${SCHEDULE_MIN_COMMITS})."
    finish
  fi
fi

# ---------------------------------------------------------------------------
# Rule 9 — range too large. Catches vendored-dependency drops that would spend
# a whole run's budget on noise. Deliberately not applied to a cold start: a
# cold start has no incremental interpretation, so refusing it would leave the
# plugin permanently unable to bootstrap in CI. Cost there stays bounded by the
# evidence bundle's byte cap and by --max-turns.
# ---------------------------------------------------------------------------
DIFF_LINES=$(git diff --no-renames --numstat "$BASE_SHA...$HEAD_SHA" 2>/dev/null \
  | awk '{ a = ($1 == "-" ? 0 : $1); d = ($2 == "-" ? 0 : $2); s += a + d } END { print s + 0 }')
[ -n "$DIFF_LINES" ] || DIFF_LINES=0
if [ $FORCED -eq 0 ] && [ $IS_COLD_START -eq 0 ] && [ "$DIFF_LINES" -gt "$MAX_DIFF_LINES" ]; then
  SHOULD_RUN="false"; REASON="range-too-large"
  note "The range spans ${DIFF_LINES} changed lines, above dossier.ci.thresholds.maxSourceDiffLines (${MAX_DIFF_LINES}). Re-run with workflow_dispatch force=true once you have confirmed the range is real."
  finish
fi
if [ $IS_COLD_START -eq 1 ] && [ "$DIFF_LINES" -gt "$MAX_DIFF_LINES" ]; then
  note "Cold start spans ${DIFF_LINES} changed lines, above the usual ceiling. The size gate does not apply to a cold start."
fi

# ---------------------------------------------------------------------------
# Rule 10 — proceed.
# ---------------------------------------------------------------------------
SHOULD_RUN="true"
if [ $FORCED -eq 1 ]; then
  REASON="forced"
  note 'Advisory rules were bypassed by an explicit force (workflow_dispatch input or force label).'
else
  REASON="ok"
fi
note "${RELEVANT_COUNT} relevant files across ${COMMIT_COUNT} commits, ${DIFF_LINES} changed lines."
finish
