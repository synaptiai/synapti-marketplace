#!/usr/bin/env bash
# dossier-validate-config.sh — validate a dossier configuration.
#
# Runs two layers:
#
#   1. JSON Schema validation against schema.json, when a validator is available.
#   2. Semantic checks that schema.json deliberately does not express.
#
# Layer 2 exists because the repo's documented fallback validator silently
# ignores `oneOf` and `if/then` when the `jsonschema` package is absent. A
# mode-conditional requirement expressed in the schema would therefore be
# enforcement theater in exactly the environments that need it most — CI runners
# and clean checkouts. These checks always run, with or without a validator.
#
# Usage:
#   dossier-validate-config.sh [--config <path>] [--quiet]
#
# With no --config, validates the merged cascade via dossier-resolve-config.sh.
#
# Output:
#   KEY=value lines, then a findings list when there are findings.
#
# Exit:
#   0 — valid
#   1 — validation findings
#   2 — infrastructure error (jq missing, config unreadable)

set -uo pipefail

SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
PLUGIN_ROOT=$(CDPATH='' cd -- "$SELF_DIR/.." && pwd)
RESOLVER="$SELF_DIR/dossier-resolve-config.sh"
SCHEMA="$PLUGIN_ROOT/schema.json"

CONFIG_PATH=""
QUIET=0

while [ $# -gt 0 ]; do
  case "${1:-}" in
    --config)
      [ $# -lt 2 ] && { echo "dossier-validate-config: --config requires a path" >&2; exit 2; }
      CONFIG_PATH="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help)
      sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "dossier-validate-config: unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || {
  echo "dossier-validate-config: jq is required" >&2
  exit 2
}

# --- load the config ---------------------------------------------------------
if [ -n "$CONFIG_PATH" ]; then
  [ -f "$CONFIG_PATH" ] || { echo "dossier-validate-config: no such file: $CONFIG_PATH" >&2; exit 2; }
  CONFIG=$(jq -c '.' "$CONFIG_PATH" 2>/dev/null) || {
    echo "CONFIG_VALID=false"
    echo "CONFIG_ERROR=not valid JSON: $CONFIG_PATH"
    exit 1
  }
else
  [ -x "$RESOLVER" ] || { echo "dossier-validate-config: resolver missing at $RESOLVER" >&2; exit 2; }
  CONFIG=$("$RESOLVER" --json) || { echo "dossier-validate-config: could not resolve config" >&2; exit 2; }
  CONFIG_PATH="(merged cascade)"
fi

FINDINGS=""
add_finding() {
  FINDINGS="${FINDINGS}${1}
"
}

# `//` is falsy-triggered, not absence-triggered: `false // empty` yields empty,
# so an explicitly-disabled boolean reads as unset and every guard that tests
# `!= "false"` fires against a config that turned the feature off. The cascade
# resolvers were corrected for this; this validator's own helper had the same
# defect. Absence is decided by jq, and only absence.
get() {
  printf '%s' "$CONFIG" | jq -r "if ($1) != null then ($1) else empty end" 2>/dev/null
}

# --- layer 1: schema validation ----------------------------------------------
SCHEMA_RESULT="skipped"
if [ -f "$SCHEMA" ]; then
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' 2>/dev/null; then
    SCHEMA_ERR=$(printf '%s' "$CONFIG" | python3 -c '
import json, sys, jsonschema
schema = json.load(open(sys.argv[1]))
try:
    jsonschema.validate(json.load(sys.stdin), schema)
except jsonschema.ValidationError as e:
    path = "/".join(str(p) for p in e.absolute_path) or "(root)"
    print("%s: %s" % (path, e.message))
    sys.exit(1)
' "$SCHEMA" 2>&1) && SCHEMA_RESULT="pass" || {
      SCHEMA_RESULT="fail"
      add_finding "schema: $SCHEMA_ERR"
    }
  else
    # Not an error. The semantic checks below are the load-bearing ones and they
    # always run; announce the gap rather than implying full validation happened.
    SCHEMA_RESULT="skipped (python3 jsonschema not installed)"
  fi
fi

# --- layer 2: semantic checks ------------------------------------------------

MODE=$(get '.dossier.engagement.deliveryMode')
[ -z "$MODE" ] && MODE="full"
case "$MODE" in
  full|targeted|verification-only) ;;
  *) add_finding "engagement.deliveryMode: '$MODE' is not one of full|targeted|verification-only" ;;
esac

OUTPUT_ROOT=$(get '.dossier.project.outputRoot')
if [ -z "$OUTPUT_ROOT" ]; then
  add_finding "project.outputRoot: required in every delivery mode; the package has nowhere to go"
else
  case "$OUTPUT_ROOT" in
    /*) add_finding "project.outputRoot: must be repo-relative, got absolute path '$OUTPUT_ROOT' — an absolute path makes the writeOutsideOutputRoot containment check unenforceable" ;;
    *..*) add_finding "project.outputRoot: must not traverse upward ('$OUTPUT_ROOT')" ;;
  esac
fi

# The mode-conditional requirement the schema deliberately omits.
if [ "$MODE" != "verification-only" ]; then
  SOURCE_COUNT=$(printf '%s' "$CONFIG" | jq -r '(.dossier.project.sources // []) | length' 2>/dev/null)
  [ -z "$SOURCE_COUNT" ] && SOURCE_COUNT=0
  if [ "$SOURCE_COUNT" -eq 0 ]; then
    add_finding "project.sources: required when deliveryMode is '$MODE' — a baseline or targeted run with no sources can only produce unevidenced prose"
  fi
  PROJECT_NAME=$(get '.dossier.project.name')
  if [ -z "$PROJECT_NAME" ]; then
    add_finding "project.name: required when deliveryMode is '$MODE' — an unresolved name propagates into every document header and into public documents"
  fi
fi

# Public claims cannot be self-approved.
POLICY=$(get '.dossier.disclosure.policy')
APPROVAL=$(get '.dossier.disclosure.publicClaimApproval')
if [ "$POLICY" = "public" ] && [ "$APPROVAL" = "not-required" ]; then
  add_finding "disclosure: policy='public' with publicClaimApproval='not-required' lets the run approve its own external claims — the run may apply a policy but may never act as the business, legal, security, or communications approver"
fi

# The containment guarantee the CI design rests on.
#
# These checks only apply when the config being validated actually carries a
# `ci` block. Validating a partial file (a fragment a user is about to merge, or
# a verification-only engagement that never touches CI) must not fail on keys
# the file was never meant to contain — the merged cascade is where those keys
# are guaranteed to exist, and `--config` deliberately validates one layer.
HAS_CI=$(printf '%s' "$CONFIG" | jq -r 'if (.dossier | type == "object") and (.dossier | has("ci")) then "yes" else "no" end' 2>/dev/null)
ALLOWLIST=$(printf '%s' "$CONFIG" | jq -r '(.dossier.ci.writeAllowlist // []) | join(" ")' 2>/dev/null)
CI_ENABLED=$(get '.dossier.ci.enabled')
if [ "$HAS_CI" = "yes" ] && [ "$CI_ENABLED" != "false" ] && [ -n "$OUTPUT_ROOT" ]; then
  case " $ALLOWLIST " in
    *" $OUTPUT_ROOT/** "*) ;;
    *" $OUTPUT_ROOT "*) ;;
    *) add_finding "ci.writeAllowlist: does not cover project.outputRoot ('$OUTPUT_ROOT/**') — every CI run would be rejected by the publish job's allowlist check" ;;
  esac
fi

# The docs branch must be excluded, or a merged docs PR retriggers the workflow.
EXCLUDES=$(printf '%s' "$CONFIG" | jq -r '(.dossier.ci.pathFilters.exclude // []) | join(" ")' 2>/dev/null)
if [ "$HAS_CI" = "yes" ] && [ "$CI_ENABLED" != "false" ] && [ -n "$OUTPUT_ROOT" ]; then
  case " $EXCLUDES " in
    *" $OUTPUT_ROOT/** "*) ;;
    *) add_finding "ci.pathFilters.exclude: missing '$OUTPUT_ROOT/**' — without it a merged documentation PR is itself a documentation-relevant change and the refresh loops" ;;
  esac
fi

# The branch prefix is the strongest loop guard; it is rendered into the
# workflow's if: expression, so it cannot be empty.
BRANCH=$(get '.dossier.ci.rollingBranch')
if [ "$HAS_CI" = "yes" ] && [ "$CI_ENABLED" != "false" ] && [ -z "$BRANCH" ]; then
  add_finding "ci.rollingBranch: required — its prefix is the head-ref loop guard rendered into the workflow"
fi

# Gate thresholds must be internally coherent.
MIN_SCORE=$(get '.dossier.gate.minScore')
if [ -n "$MIN_SCORE" ]; then
  case "$MIN_SCORE" in
    ''|*[!0-9]*) add_finding "gate.minScore: '$MIN_SCORE' is not an integer" ;;
    *) [ "$MIN_SCORE" -gt 100 ] && add_finding "gate.minScore: $MIN_SCORE exceeds the 100-point scorecard" ;;
  esac
fi

MAX_ROUNDS=$(get '.dossier.verification.maxRounds')
case "${MAX_ROUNDS:-3}" in
  ''|*[!0-9]*) add_finding "verification.maxRounds: '${MAX_ROUNDS}' is not an integer" ;;
  0) add_finding "verification.maxRounds: 0 disables verification entirely; use verification.passes: [] and say so explicitly instead" ;;
esac

# Reading secrets is never needed to document that a secret exists.
READ_SECRETS=$(get '.dossier.engagement.allowedActions.readSecrets')
if [ "$READ_SECRETS" = "true" ]; then
  add_finding "engagement.allowedActions.readSecrets: enabled — a secret's value is never required to document its type, location category, or rotation story; confirm this is deliberate"
fi

# --- report ------------------------------------------------------------------
FINDING_COUNT=$(printf '%s' "$FINDINGS" | grep -c . 2>/dev/null || true)
[ -z "$FINDING_COUNT" ] && FINDING_COUNT=0

if [ "$QUIET" -eq 0 ]; then
  echo "CONFIG_SOURCE=$CONFIG_PATH"
  echo "CONFIG_DELIVERY_MODE=$MODE"
  echo "CONFIG_OUTPUT_ROOT=${OUTPUT_ROOT:-unset}"
  echo "CONFIG_SCHEMA_VALIDATION=$SCHEMA_RESULT"
  echo "CONFIG_FINDINGS=$FINDING_COUNT"
fi

if [ "$FINDING_COUNT" -gt 0 ]; then
  [ "$QUIET" -eq 0 ] && {
    echo ""
    echo "Findings:"
    printf '%s' "$FINDINGS" | grep . | sed 's/^/  - /'
  }
  exit 1
fi

[ "$QUIET" -eq 0 ] && echo "CONFIG_VALID=true"
exit 0
