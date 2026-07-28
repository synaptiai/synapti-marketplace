#!/usr/bin/env bash
# dossier-vuln-evidence.sh — normalize a project's EXISTING vulnerability-scan
# output into cited evidence. Never executes a scanner and makes no network
# call; it only reads and parses a scan-artifact file already present in the
# working tree. Executing a scanner is out of scope (issue #137).
#
# Supports three input shapes, detected by JSON structure rather than file
# extension:
#   sarif        - top-level `runs[]`, each with `tool.driver.name` and
#                   `results[]` (severity via the `security-severity`
#                   property, a CVSS score).
#   osv-scanner  - top-level `results[]`, each with `packages[]`, each with
#                   `vulnerabilities[]` (severity via `severity[].score`, a
#                   CVSS score). NOTE: assumes a plain numeric score string —
#                   verified against this script's own test fixtures, not
#                   against live osv-scanner output. If real output encodes
#                   severity as a CVSS vector string instead of a bare score,
#                   that finding will correctly fall through to
#                   `unresolved_severity` rather than being mis-bucketed; the
#                   assumption should be re-verified against real tool output
#                   when issue #137 (isolated scanner execution) lands.
#   dependabot   - top-level JSON array of alert objects, each with
#                   `security_advisory.severity` (already dossier's own
#                   Critical/High/Medium/Low vocabulary, case-insensitive).
#
# Severity is bucketed by CVSS v3 ranges (Critical 9.0-10.0, High 7.0-8.9,
# Medium 4.0-6.9, Low 0.1-3.9). A finding with no derivable severity is NEVER
# defaulted to Low — it is reported separately under `unresolved_severity`, a
# parse-completeness issue rather than a low-risk finding.
#
# Only Critical/High findings are itemized individually in `findings` (one
# dossier evidence-ledger row per material finding, per
# references/finding-schema.md's severity definitions and this issue's own
# design). Medium/Low findings are counted in `aggregate`, never itemized.
#
# A parse failure (malformed JSON, or valid JSON matching none of the three
# known shapes) is reported as an explicit `error` field and a non-zero exit
# — never as a clean zero-findings scan. Mirrors the ERR-3 delegate-failure
# pattern already shipped in dossier-policy.sh / dossier-evidence.sh.
#
# Usage:
#   dossier-vuln-evidence.sh --scan <path> [--out <dir>]
#
# Output (stdout): one JSON object, schema `dossier.vuln-evidence/v1`:
#   {
#     "schema": "dossier.vuln-evidence/v1",
#     "scan": {"format", "tool", "scope", "retrieved", "source_path"},
#     "findings": [{"id","package","version","severity","summary","source_ref"}],
#     "aggregate": {"Medium": <n>, "Low": <n>},
#     "unresolved_severity": [{"id","package","version","summary"}]
#   }
# On parse failure: {"schema", "scan": {"source_path","format": null}, "error": "parse-error: ..."}
#
# --out <dir> additionally writes the same JSON to <dir>/vuln-evidence.json.
#
# Exit: 0 parsed successfully (including zero findings) · 1 parse/read failure
#       · 2 missing or invalid argument

set -uo pipefail

SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

SCAN=""
OUT=""

while [ $# -gt 0 ]; do
  case "${1:-}" in
    --scan) [ $# -lt 2 ] && { echo "dossier-vuln-evidence: --scan requires a path" >&2; exit 2; }
            SCAN="$2"; shift 2 ;;
    --out)  [ $# -lt 2 ] && { echo "dossier-vuln-evidence: --out requires a path" >&2; exit 2; }
            OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,42p' "$0"; exit 0 ;;
    *) echo "dossier-vuln-evidence: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$SCAN" ] || { echo "dossier-vuln-evidence: --scan is required" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "dossier-vuln-evidence: jq is not installed" >&2; exit 1; }

emit_error() {
  jq -cn --arg path "$SCAN" --arg err "parse-error: $1" \
    '{schema: "dossier.vuln-evidence/v1", scan: {source_path: $path, format: null}, error: $err}'
  exit 1
}

[ -f "$SCAN" ] || emit_error "no scan artifact at $SCAN"

if ! jq -e . "$SCAN" >/dev/null 2>&1; then
  emit_error "$SCAN is not valid JSON"
fi

# --- Format detection, by structure, not file extension ---------------------
FORMAT=""
if jq -e 'type == "array"' "$SCAN" >/dev/null 2>&1; then
  if jq -e 'length > 0 and (.[0].security_advisory != null)' "$SCAN" >/dev/null 2>&1; then
    FORMAT="dependabot"
  fi
elif jq -e '(.runs != null) and (.runs | type) == "array"' "$SCAN" >/dev/null 2>&1; then
  FORMAT="sarif"
elif jq -e '(.results != null) and (.results | type) == "array" and (.results[0].packages != null)' "$SCAN" >/dev/null 2>&1; then
  FORMAT="osv-scanner"
fi

[ -n "$FORMAT" ] || emit_error "$SCAN did not match any known format (sarif, osv-scanner, dependabot)"

RETRIEVED=$(date -u +%Y-%m-%d)

JQ_PROGRAM=$(cat <<'JQEOF'
def bucket_severity(score):
  if score == null then null
  else
    (try (score | tostring | tonumber) catch null) as $n
    | if $n == null then null
      elif $n >= 9.0 then "Critical"
      elif $n >= 7.0 then "High"
      elif $n >= 4.0 then "Medium"
      elif $n > 0 then "Low"
      else null end
  end;

def sev_from_string(s):
  if s == null then null
  else
    (s | ascii_downcase) as $ls
    | if $ls == "critical" then "Critical"
      elif $ls == "high" then "High"
      elif $ls == "medium" or $ls == "moderate" then "Medium"
      elif $ls == "low" then "Low"
      else null end
  end;

(
  if $format == "sarif" then
    {
      tool: (.runs[0].tool.driver.name // "unknown"),
      scope: ([.runs[]?.results[]?.locations[0]?.physicalLocation?.artifactLocation?.uri]
              | map(select(. != null)) | unique | join(", ")),
      raw: [ .runs[]?.results[]? | {
        id: (.ruleId // "UNKNOWN"),
        package: (.locations[0]?.physicalLocation?.artifactLocation?.uri // "unknown"),
        version: null,
        summary: (.message.text // ""),
        severity: bucket_severity(.properties["security-severity"])
      } ]
    }
  elif $format == "osv-scanner" then
    {
      tool: "osv-scanner",
      scope: ([.results[]?.source.path] | map(select(. != null)) | unique | join(", ")),
      raw: [ .results[]? as $r | ($r.packages // [])[]? as $p | ($p.vulnerabilities // [])[]? | {
        id: (.id // "UNKNOWN"),
        package: ($p.package.name // "unknown"),
        version: ($p.package.version // null),
        summary: (.summary // ""),
        severity: bucket_severity(.severity[0]?.score)
      } ]
    }
  elif $format == "dependabot" then
    {
      tool: "dependabot",
      scope: ([.[].dependency.manifest_path] | map(select(. != null)) | unique | join(", ")),
      raw: [ .[] | {
        id: (.security_advisory.ghsa_id // "UNKNOWN"),
        package: (.dependency.package.name // "unknown"),
        version: null,
        summary: (.security_advisory.summary // ""),
        severity: sev_from_string(.security_advisory.severity)
      } ]
    }
  else
    {tool: "unknown", scope: "", raw: []}
  end
) as $extracted
| ($extracted.raw
   | map(select(.severity == "Critical" or .severity == "High"))
   | map(. + {source_ref: ("`" + $scan_path + "` — " + $extracted.tool + ", " + .id + ", retrieved " + $retrieved)})
  ) as $material
| ($extracted.raw
   | map(select(.severity == "Medium" or .severity == "Low"))
   | group_by(.severity)
   | map({key: .[0].severity, value: length})
   | from_entries
  ) as $agg
| ($extracted.raw | map(select(.severity == null))) as $unresolved
| {
    schema: "dossier.vuln-evidence/v1",
    scan: {
      format: $format,
      tool: $extracted.tool,
      scope: $extracted.scope,
      retrieved: $retrieved,
      source_path: $scan_path
    },
    findings: $material,
    aggregate: ($agg // {}),
    unresolved_severity: $unresolved
  }
JQEOF
)

RESULT=$(jq -c --arg format "$FORMAT" --arg scan_path "$SCAN" --arg retrieved "$RETRIEVED" "$JQ_PROGRAM" "$SCAN" 2>&1)
JQ_RC=$?
if [ "$JQ_RC" -ne 0 ]; then
  emit_error "could not normalize $SCAN ($FORMAT shape matched, but extraction failed): $RESULT"
fi

printf '%s\n' "$RESULT"

if [ -n "$OUT" ]; then
  mkdir -p "$OUT" 2>/dev/null || { echo "dossier-vuln-evidence: could not create --out directory $OUT" >&2; exit 1; }
  printf '%s\n' "$RESULT" >"$OUT/vuln-evidence.json"
fi

exit 0
