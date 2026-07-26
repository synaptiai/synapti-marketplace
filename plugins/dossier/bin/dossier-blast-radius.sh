#!/usr/bin/env bash
# dossier-blast-radius.sh — map a changed-file set to the canonical documents
# that have to be regenerated.
#
# This is the single biggest lever on the cost and the reviewability of a
# refresh. Regenerating all twenty-three documents for a dependency bump burns a
# run's budget and produces a diff nobody reads carefully; regenerating none of
# the downstream views produces a package that contradicts itself. The matrix
# below is the middle: a change event implies a set of documents, and a document
# whose triggering event did not fire is left exactly as it was, including its
# `last verified` date.
#
# The same matrix is documented for humans in
# `references/change-triggers-and-blast-radius.md`. The two must agree; the
# reference is the explanation, this file is the behaviour.
#
# Usage:
#   dossier-blast-radius.sh --changed-files <file> --out <file>
#
# Flags:
#   --changed-files <file>  newline-separated repository-relative paths
#   --out <file>            write the JSON result here
#
# Output (stdout): `key=value` lines — events, document_count, documents,
#   matched_files, unmatched_files.
#
# Exit:
#   0 — mapping written
#   1 — jq unavailable, or the result could not be written
#   2 — missing or invalid argument

set -uo pipefail

CHANGED=""
OUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --changed-files) [ $# -lt 2 ] && { echo "dossier-blast-radius: --changed-files requires a value" >&2; exit 2; }; CHANGED="$2"; shift 2 ;;
    --out)           [ $# -lt 2 ] && { echo "dossier-blast-radius: --out requires a value" >&2; exit 2; }; OUT="$2"; shift 2 ;;
    -h|--help)       sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "dossier-blast-radius: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$CHANGED" ] || { echo "dossier-blast-radius: --changed-files is required" >&2; exit 2; }
[ -n "$OUT" ]     || { echo "dossier-blast-radius: --out is required" >&2; exit 2; }
[ -f "$CHANGED" ] || { echo "dossier-blast-radius: changed-files list not found: $CHANGED" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "dossier-blast-radius: jq is not installed." >&2; exit 1; }

TMPD=$(mktemp -d -t dossier-blast.XXXXXX) || {
  echo "dossier-blast-radius: cannot create a temporary file or directory" >&2; exit 2;
}
mkdir -p "$TMPD" 2>/dev/null
cleanup() { rm -rf "$TMPD" 2>/dev/null; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# The matrix.
#
# Each event emits its path pattern on the first line and the documents it
# reaches on the lines after. Keeping both in one place is deliberate: split
# across two tables they drift, and a blast radius that silently stops covering
# a document is indistinguishable from one that never covered it.
#
# Events are evaluated independently and a file may fire several of them; a
# migration under `api/` is both a schema change and an interface change, and
# both sets of documents are correct.
# ---------------------------------------------------------------------------
EVENTS='dependency
interface
data-and-schema
ai-model
security-control
infrastructure
ci-delivery
testing
observability
operations
public-claim
release
decision
onboarding
configuration
product-capability'

event_row() {
  case "$1" in
    dependency) cat <<'ROW'
(^|/)(package\.json|package-lock\.json|npm-shrinkwrap\.json|yarn\.lock|pnpm-lock\.yaml|bun\.lockb|pyproject\.toml|poetry\.lock|uv\.lock|Pipfile|Pipfile\.lock|requirements[^/]*\.txt|setup\.py|setup\.cfg|go\.mod|go\.sum|Cargo\.toml|Cargo\.lock|Gemfile|Gemfile\.lock|composer\.json|composer\.lock|pom\.xml|build\.gradle|build\.gradle\.kts|gradle\.lockfile|packages\.lock\.json|[^/]+\.csproj|Package\.swift|Package\.resolved|Podfile|Podfile\.lock|mix\.exs|mix\.lock|pubspec\.yaml|pubspec\.lock|dependabot\.yml|renovate\.json)$
05-due-diligence/assets-dependencies-and-licenses.md
02-architecture/components-and-codebase.md
03-assurance/security-privacy-and-compliance.md
04-operating/onboarding-and-local-development.md
ROW
      ;;
    interface) cat <<'ROW'
(^|/)(openapi[^/]*\.(ya?ml|json)|swagger[^/]*\.(ya?ml|json)|asyncapi[^/]*\.(ya?ml|json)|[^/]+\.proto|[^/]+\.graphqls?)$|^(api|apis|routes|controllers|handlers|endpoints|graphql|proto|rpc|sdk|sdks)/|(^|/)(api|routes|controllers|handlers|endpoints|graphql|proto)/
02-architecture/interfaces-and-integrations.md
02-architecture/system-architecture.md
06-public/technical-partner-guide.md
00-control/claim-and-disclosure-register.md
00-control/terminology-and-ownership.md
ROW
      ;;
    data-and-schema) cat <<'ROW'
^(migrations?|db|database|prisma|schemas?|models?|entities|datastore)/|(^|/)migrations?/|(^|/)(schema\.(sql|prisma|rb|graphql)|[^/]+\.sql|alembic\.ini)$
02-architecture/data-and-ai.md
03-assurance/security-privacy-and-compliance.md
05-due-diligence/technical-due-diligence-report.md
02-architecture/system-architecture.md
ROW
      ;;
    ai-model) cat <<'ROW'
^(prompts?|models?|agents?|evals?|embeddings|rag|inference)/|(^|/)(prompts?|evals?)/|(^|/)[^/]*(prompt|llm|openai|anthropic|bedrock|vertex|embedding|inference)[^/]*\.(py|ts|tsx|js|jsx|go|rb|rs|java|kt|cs)$
02-architecture/data-and-ai.md
03-assurance/security-privacy-and-compliance.md
06-public/customer-product-and-trust-guide.md
00-control/claim-and-disclosure-register.md
ROW
      ;;
    security-control) cat <<'ROW'
^(auth|authn|authz|security|iam|rbac|permissions|crypto|secrets|policies)/|(^|/)(auth|authn|authz|security|iam|rbac|permissions|crypto)/|(^|/)(SECURITY\.md|\.trivyignore|\.snyk|codeql[^/]*\.ya?ml)$|(^|/)[^/]*(auth|oauth|oidc|jwt|session|password|encrypt|tls|cert)[^/]*\.(py|ts|tsx|js|jsx|go|rb|rs|java|kt|cs)$
03-assurance/security-privacy-and-compliance.md
02-architecture/system-architecture.md
05-due-diligence/technical-due-diligence-report.md
06-public/customer-product-and-trust-guide.md
00-control/claim-and-disclosure-register.md
ROW
      ;;
    infrastructure) cat <<'ROW'
^(infra|infrastructure|terraform|deploy|deployment|k8s|kubernetes|helm|charts|ansible|pulumi|cdk)/|(^|/)(Dockerfile[^/]*|docker-compose[^/]*\.ya?ml|[^/]+\.tf|[^/]+\.tfvars|Chart\.yaml|values[^/]*\.ya?ml|serverless\.ya?ml|fly\.toml|vercel\.json|netlify\.toml|Procfile|wrangler\.(toml|jsonc?)|app\.yaml|cloudbuild\.ya?ml)$
02-architecture/infrastructure-and-deployment.md
04-operating/operations-and-incident-response.md
03-assurance/reliability-performance-and-observability.md
05-due-diligence/technical-due-diligence-report.md
ROW
      ;;
    ci-delivery) cat <<'ROW'
^\.github/(workflows|actions)/|(^|/)(\.gitlab-ci\.yml|Jenkinsfile|azure-pipelines\.ya?ml|\.circleci|\.buildkite|\.travis\.yml|\.pre-commit-config\.yaml)
03-assurance/testing-quality-and-delivery.md
02-architecture/infrastructure-and-deployment.md
04-operating/onboarding-and-local-development.md
ROW
      ;;
    testing) cat <<'ROW'
^(tests?|spec|specs|e2e|__tests__|testdata|fixtures)/|(^|/)(tests?|spec|specs|e2e|__tests__)/|(^|/)[^/]*\.(test|spec)\.[^/]+$|(^|/)(jest\.config[^/]*|vitest\.config[^/]*|pytest\.ini|tox\.ini|playwright\.config[^/]*|cypress\.config[^/]*|karma\.conf[^/]*)$
03-assurance/testing-quality-and-delivery.md
ROW
      ;;
    observability) cat <<'ROW'
^(monitoring|observability|dashboards|alerting|telemetry)/|(^|/)(prometheus[^/]*\.ya?ml|alerts?[^/]*\.ya?ml|otel[^/]*\.ya?ml|opentelemetry[^/]*\.ya?ml|datadog[^/]*\.ya?ml|grafana)/?
03-assurance/reliability-performance-and-observability.md
04-operating/operations-and-incident-response.md
ROW
      ;;
    operations) cat <<'ROW'
^(runbooks?|ops|operations|playbooks?|oncall)/|(^|/)(RUNBOOK[^/]*\.md|INCIDENT[^/]*\.md|ONCALL[^/]*\.md|DISASTER[^/]*\.md)$
04-operating/operations-and-incident-response.md
03-assurance/reliability-performance-and-observability.md
ROW
      ;;
    public-claim) cat <<'ROW'
(^|/)(README(\.[a-z]+)?|CONTRIBUTING\.md|CODE_OF_CONDUCT\.md|SUPPORT\.md|LICENSE[^/]*|NOTICE[^/]*|PRIVACY[^/]*\.md|TERMS[^/]*\.md)$|^(website|site|www|marketing|landing|public|docs/public)/
06-public/customer-product-and-trust-guide.md
06-public/technical-partner-guide.md
00-control/claim-and-disclosure-register.md
01-project/executive-project-brief.md
05-due-diligence/assets-dependencies-and-licenses.md
ROW
      ;;
    release) cat <<'ROW'
(^|/)(CHANGELOG(\.md)?|HISTORY\.md|RELEASES?\.md|VERSION|version\.txt|\.release-please-manifest\.json|release-please-config\.json)$
01-project/executive-project-brief.md
03-assurance/testing-quality-and-delivery.md
06-public/customer-product-and-trust-guide.md
ROW
      ;;
    decision) cat <<'ROW'
^(docs/)?(adrs?|decisions|architecture-decisions|rfcs?)/|(^|/)(adrs?|decisions|rfcs?)/|(^|/)ADR-[0-9]+[^/]*\.md$
04-operating/decisions-technical-debt-and-risks.md
02-architecture/system-architecture.md
00-control/terminology-and-ownership.md
ROW
      ;;
    onboarding) cat <<'ROW'
^(scripts|tools|bin|hack|\.devcontainer)/|(^|/)(Makefile|justfile|Justfile|Taskfile\.ya?ml|\.tool-versions|\.nvmrc|\.python-version|\.ruby-version|docker-compose\.(dev|local)[^/]*\.ya?ml|\.env\.example|\.env\.sample)$
04-operating/onboarding-and-local-development.md
02-architecture/components-and-codebase.md
ROW
      ;;
    configuration) cat <<'ROW'
^(config|configs|settings|conf)/|(^|/)(config|configs|settings)/|(^|/)(config[^/]*\.(ya?ml|json|toml|ini)|settings[^/]*\.(ya?ml|json|toml|ini)|[^/]*\.env\.[^/]+)$
02-architecture/components-and-codebase.md
02-architecture/infrastructure-and-deployment.md
ROW
      ;;
    product-capability) cat <<'ROW'
^(src|lib|app|apps|packages|internal|cmd|pkg|components|features|pages|server|services|core|domain|web|client|frontend|backend|ui)/
01-project/product-and-domain.md
01-project/executive-project-brief.md
02-architecture/components-and-codebase.md
02-architecture/system-architecture.md
06-public/customer-product-and-trust-guide.md
05-due-diligence/technical-due-diligence-report.md
00-control/terminology-and-ownership.md
ROW
      ;;
  esac
}

# The control plane and the verification report are regenerated on every
# refresh, whatever the event. They are not views over the project — they are
# views over the package itself, so any change to any document changes them by
# definition.
ALWAYS_DOCS='00-control/documentation-index.md
00-control/evidence-ledger.md
00-control/assumptions-questions-and-contradictions.md
07-verification/documentation-verification-report.md'

PAIRS="$TMPD/pairs.tsv"
EVENT_JSON="$TMPD/events.json"
MATCHED_ALL="$TMPD/matched.txt"
: >"$PAIRS"
: >"$MATCHED_ALL"
echo '[]' >"$EVENT_JSON"

for E in $EVENTS; do
  ERE=$(event_row "$E" | head -1)
  [ -n "$ERE" ] || continue
  MATCHES=$(grep -E -e "$ERE" "$CHANGED" 2>/dev/null)
  [ -n "$MATCHES" ] || continue

  printf '%s\n' "$MATCHES" >>"$MATCHED_ALL"
  MATCH_COUNT=$(printf '%s\n' "$MATCHES" | grep -c . | tr -d ' ')

  event_row "$E" | tail -n +2 | while IFS= read -r D; do
    [ -n "$D" ] || continue
    printf '%s\t%s\n' "$D" "$E" >>"$PAIRS"
  done

  # Only a sample of matched paths is carried into the result. The complete set
  # is already in changed-files.txt; repeating it here would make the mapping
  # the largest file in the bundle for no added signal.
  SAMPLE=$(printf '%s\n' "$MATCHES" | head -25 | jq -R . | jq -sc .)
  if jq -c --arg e "$E" --argjson n "${MATCH_COUNT:-0}" --argjson s "$SAMPLE" \
       '. + [{event: $e, match_count: $n, matched_files: $s}]' "$EVENT_JSON" >"$EVENT_JSON.next"; then
    mv "$EVENT_JSON.next" "$EVENT_JSON"
  else
    rm -f "$EVENT_JSON.next" 2>/dev/null
    echo "dossier-blast-radius: could not record event '$E' in the report." >&2
    exit 1
  fi
done

printf '%s\n' "$ALWAYS_DOCS" | while IFS= read -r D; do
  [ -n "$D" ] || continue
  printf '%s\t%s\n' "$D" "always" >>"$PAIRS"
done

DOCS_JSON=$(jq -Rn '
  [inputs | select(length > 0) | split("\t") | {doc: .[0], event: .[1]}]
  | group_by(.doc)
  | map({
      path: .[0].doc,
      reasons: ([.[].event] | unique),
      class: (if ([.[].event] | any(. == "always")) and ([.[].event] | length) == 1
              then "always" else "matched" end)
    })
  | sort_by(.path)
' <"$PAIRS" 2>/dev/null)
[ -n "$DOCS_JSON" ] || DOCS_JSON='[]'

sort -u "$MATCHED_ALL" >"$TMPD/matched-sorted.txt" 2>/dev/null
sort -u "$CHANGED"     >"$TMPD/changed-sorted.txt" 2>/dev/null
comm -23 "$TMPD/changed-sorted.txt" "$TMPD/matched-sorted.txt" >"$TMPD/unmatched.txt" 2>/dev/null
[ -f "$TMPD/unmatched.txt" ] || : >"$TMPD/unmatched.txt"

CHANGED_COUNT=$(grep -c . "$CHANGED" 2>/dev/null | tr -d ' ');                    [ -n "$CHANGED_COUNT" ] || CHANGED_COUNT=0
MATCHED_COUNT=$(grep -c . "$TMPD/matched-sorted.txt" 2>/dev/null | tr -d ' ');    [ -n "$MATCHED_COUNT" ] || MATCHED_COUNT=0
UNMATCHED_COUNT=$(grep -c . "$TMPD/unmatched.txt" 2>/dev/null | tr -d ' ');       [ -n "$UNMATCHED_COUNT" ] || UNMATCHED_COUNT=0

UNMATCHED_JSON=$(head -50 "$TMPD/unmatched.txt" 2>/dev/null | jq -R . | jq -sc .)
[ -n "$UNMATCHED_JSON" ] || UNMATCHED_JSON='[]'

mkdir -p "$(dirname "$OUT")" 2>/dev/null
jq -n \
  --arg schema 'dossier.blast-radius/v1' \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson changed_files "$CHANGED_COUNT" \
  --argjson matched_files "$MATCHED_COUNT" \
  --argjson unmatched_files "$UNMATCHED_COUNT" \
  --slurpfile events "$EVENT_JSON" \
  --argjson documents "$DOCS_JSON" \
  --argjson unmatched_sample "$UNMATCHED_JSON" \
  '{
    schema: $schema,
    generated_at: $generated_at,
    counts: {
      changed_files: $changed_files,
      matched_files: $matched_files,
      unmatched_files: $unmatched_files,
      documents: ($documents | length)
    },
    events: $events[0],
    documents: $documents,
    unmatched_sample: $unmatched_sample,
    note: "A file that matched no event still belongs in the range. Read the unmatched sample before concluding that nothing else needs to change: an unmatched path means the matrix has no rule for it, not that it is documentation-irrelevant."
  }' >"$OUT" || { echo "dossier-blast-radius: could not write $OUT" >&2; exit 1; }

FIRED=$(printf '%s' "$(jq -r '.events[].event' "$OUT" 2>/dev/null | tr '\n' ',' | sed -e 's/,$//')")
DOC_LIST=$(jq -r '.documents[].path' "$OUT" 2>/dev/null | tr '\n' ',' | sed -e 's/,$//')
DOC_COUNT=$(jq -r '.documents | length' "$OUT" 2>/dev/null)

printf 'events=%s\n' "${FIRED:-none}"
printf 'document_count=%s\n' "${DOC_COUNT:-0}"
printf 'documents=%s\n' "${DOC_LIST:-}"
printf 'matched_files=%s\n' "$MATCHED_COUNT"
printf 'unmatched_files=%s\n' "$UNMATCHED_COUNT"
exit 0
