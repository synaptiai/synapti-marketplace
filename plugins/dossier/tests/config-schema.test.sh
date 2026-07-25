#!/usr/bin/env bash
# Configuration: schema validity, cascade precedence proven with real fixtures,
# and the semantic rules the schema deliberately does not express.

_dossier_test_begin "config-schema"

PLUGIN="plugins/dossier"
SCHEMA="$PLUGIN/schema.json"
SETTINGS="$PLUGIN/settings.json"
EXAMPLE="$PLUGIN/templates/config.example.json"
RESOLVE="$PLUGIN/bin/dossier-resolve-config.sh"
VALIDATE="$PLUGIN/bin/dossier-validate-config.sh"

for f in "$SCHEMA" "$SETTINGS" "$EXAMPLE"; do
  assert_file_exists "$f" "$(basename "$f") exists"
done

if ! command -v jq >/dev/null 2>&1; then
  _dossier_assert_fail "jq unavailable — cannot validate configuration"
  _dossier_test_summary
  return 0 2>/dev/null || exit 0
fi

for f in "$SCHEMA" "$SETTINGS" "$EXAMPLE"; do
  if jq -e . "$f" >/dev/null 2>&1; then
    _dossier_assert_pass "$(basename "$f") is valid JSON"
  else
    _dossier_assert_fail "$(basename "$f") is not valid JSON"
  fi
done

assert_equal "https://json-schema.org/draft-07/schema#" \
  "$(jq -r '."$schema"' "$SCHEMA")" "schema declares draft-07"
assert_equal "Dossier Plugin Settings" "$(jq -r '.title' "$SCHEMA")" "schema title"

# --- The deliberate absence of conditionals ----------------------------------
# The documented fallback validator ignores if/then and oneOf when jsonschema is
# absent, so a conditional there would report success and enforce nothing on
# exactly the machines that need it. Those rules live in the validator script.
for kw in '"if"' '"then"' '"oneOf"' '"anyOf"'; do
  if grep -q "$kw" "$SCHEMA"; then
    _dossier_assert_fail "schema uses $kw — conditionals belong in dossier-validate-config.sh"
  else
    _dossier_assert_pass "schema avoids $kw"
  fi
done

# --- Every leaf carries a description ----------------------------------------
# A default with no stated reason becomes a value nobody dares change.
NO_DESC=$(jq -r '
  [paths(type == "object" and has("type") and (.type | type) == "string" and (has("properties") | not))
   as $p | getpath($p) | select(has("description") | not)] | length
' "$SCHEMA" 2>/dev/null)
if [ "${NO_DESC:-0}" -eq 0 ]; then
  _dossier_assert_pass "every schema leaf has a description"
else
  _dossier_assert_fail "$NO_DESC schema leaves have no description"
fi

# --- outputRoot must be relative ---------------------------------------------
assert_equal '^[^/].*' "$(jq -r '.properties.dossier.properties.project.properties.outputRoot.pattern' "$SCHEMA")" \
  "outputRoot pattern rejects absolute paths"

# --- settings.json defaults --------------------------------------------------
assert_equal "docs/dossier" "$(jq -r '.dossier.project.outputRoot' "$SETTINGS")" "default outputRoot"
assert_equal "internal-only" "$(jq -r '.dossier.disclosure.policy' "$SETTINGS")" \
  "default disclosure policy is the conservative one"
assert_equal "required" "$(jq -r '.dossier.disclosure.publicClaimApproval' "$SETTINGS")" \
  "public claims require approval by default"
assert_equal "path-filtered" "$(jq -r '.dossier.ci.triggerPolicy' "$SETTINGS")" "default trigger policy"
assert_equal "rolling" "$(jq -r '.dossier.ci.branchStrategy' "$SETTINGS")" "default branch strategy"

# Restrictive action ceiling: the safe failure is an honestly-labelled
# unverified claim, not an unauthorized action.
for cap in readSecrets runBuild runTests networkAccess writeOutsideOutputRoot contactHumans; do
  assert_equal "false" "$(jq -r ".dossier.engagement.allowedActions.$cap" "$SETTINGS")" \
    "allowedActions.$cap defaults to false"
done

# The containment guarantee the CI design rests on.
ALLOW=$(jq -r '.dossier.ci.writeAllowlist | join(",")' "$SETTINGS")
assert_contains "docs/dossier/**" "$ALLOW" "writeAllowlist covers the output root"
EXCL=$(jq -r '.dossier.ci.pathFilters.exclude | join(",")' "$SETTINGS")
assert_contains "docs/dossier/**" "$EXCL" "path exclusions cover the output root (loop prevention)"

# --- Cascade precedence, proven with fixtures --------------------------------
WORK=$(mktemp -d 2>/dev/null) || WORK="/tmp/dossier-cascade.$$"
mkdir -p "$WORK/.claude" 2>/dev/null
REPO=$(pwd)
PLUGIN_ABS="$REPO/$PLUGIN"

# Plugin default only.
V=$(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" HOME="$WORK" \
      "$PLUGIN_ABS/bin/dossier-resolve-config.sh" dossier.project.outputRoot 2>/dev/null)
assert_equal "docs/dossier" "$V" "cascade: plugin default resolves"

# Project file beats plugin default.
printf '{"dossier":{"project":{"outputRoot":"docs/from-project"}}}\n' > "$WORK/.claude/settings.dossier.json"
V=$(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" HOME="$WORK" \
      "$PLUGIN_ABS/bin/dossier-resolve-config.sh" dossier.project.outputRoot 2>/dev/null)
assert_equal "docs/from-project" "$V" "cascade: project beats plugin"

# Local file beats project.
printf '{"dossier":{"project":{"outputRoot":"docs/from-local"}}}\n' > "$WORK/.claude/settings.dossier.local.json"
V=$(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" HOME="$WORK" \
      "$PLUGIN_ABS/bin/dossier-resolve-config.sh" dossier.project.outputRoot 2>/dev/null)
assert_equal "docs/from-local" "$V" "cascade: local beats project"

# Environment beats everything — this is what makes CI zero-interaction.
V=$(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" HOME="$WORK" \
      DOSSIER_PROJECT_OUTPUT_ROOT="docs/from-env" \
      "$PLUGIN_ABS/bin/dossier-resolve-config.sh" dossier.project.outputRoot 2>/dev/null)
assert_equal "docs/from-env" "$V" "cascade: environment beats every file"

# An explicit EMPTY STRING must resolve, not fall through. `project.name: ""`
# and `ci.agent.model: ""` are documented sentinels meaning "deliberately
# unresolved" and "inherit the action default" — treating them as absence let a
# stale user-global value win, which in a serial-engagement tool means a prior
# client's name propagating into a new project's document headers.
mkdir -p "$WORK/home/.claude" 2>/dev/null
printf '{"dossier":{"project":{"name":"PRIOR-CLIENT"}}}\n' > "$WORK/home/.claude/settings.dossier.json"
printf '{"dossier":{"project":{"name":""}}}\n' > "$WORK/.claude/settings.dossier.json"
printf '{}\n' > "$WORK/.claude/settings.dossier.local.json"
V=$(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" HOME="$WORK/home" \
      "$PLUGIN_ABS/bin/dossier-resolve-config.sh" dossier.project.name 2>/dev/null)
assert_equal "" "$V" "cascade: an explicit empty string is not treated as absence"

# An explicit false must resolve, not fall through to the next layer.
printf '{"dossier":{"ci":{"enabled":false}}}\n' > "$WORK/.claude/settings.dossier.local.json"
V=$(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" HOME="$WORK" \
      "$PLUGIN_ABS/bin/dossier-resolve-config.sh" dossier.ci.enabled 2>/dev/null)
assert_equal "false" "$V" "cascade: an explicit false is not swallowed"

# Default applies only when nothing resolves.
V=$(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" HOME="$WORK" \
      "$PLUGIN_ABS/bin/dossier-resolve-config.sh" --default sentinel dossier.no.such.key 2>/dev/null)
assert_equal "sentinel" "$V" "cascade: --default on a missing key"

# --- Semantic validation -----------------------------------------------------
# verification-only needs only outputRoot; full needs name and sources.
printf '{"dossier":{"project":{"outputRoot":"docs/dossier"},"engagement":{"deliveryMode":"verification-only"}}}\n' \
  > "$WORK/vo.json"
(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" "$PLUGIN_ABS/bin/dossier-validate-config.sh" --config vo.json --quiet >/dev/null 2>&1)
assert_equal "0" "$?" "verification-only validates without project.sources"

printf '{"dossier":{"project":{"outputRoot":"docs/dossier"},"engagement":{"deliveryMode":"full"}}}\n' \
  > "$WORK/full.json"
(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" "$PLUGIN_ABS/bin/dossier-validate-config.sh" --config full.json --quiet >/dev/null 2>&1)
assert_equal "1" "$?" "full mode without name/sources is rejected"

# An absolute outputRoot makes the containment check unenforceable.
printf '{"dossier":{"project":{"name":"x","sources":["./"],"outputRoot":"/tmp/docs"}}}\n' > "$WORK/abs.json"
OUT=$(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" "$PLUGIN_ABS/bin/dossier-validate-config.sh" --config abs.json 2>&1)
assert_contains "repo-relative" "$OUT" "an absolute outputRoot is rejected with a reason"

# A run may apply a disclosure policy; it may never approve its own claims.
printf '{"dossier":{"project":{"name":"x","sources":["./"],"outputRoot":"docs/d"},"disclosure":{"policy":"public","publicClaimApproval":"not-required"}}}\n' \
  > "$WORK/selfapprove.json"
OUT=$(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" "$PLUGIN_ABS/bin/dossier-validate-config.sh" --config selfapprove.json 2>&1)
assert_contains "approver" "$OUT" "self-approving public claims is flagged"

# Malformed JSON is a finding, not a crash.
printf '{ not json\n' > "$WORK/bad.json"
(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" "$PLUGIN_ABS/bin/dossier-validate-config.sh" --config bad.json --quiet >/dev/null 2>&1)
RC=$?
if [ "$RC" -eq 1 ] || [ "$RC" -eq 2 ]; then
  _dossier_assert_pass "malformed JSON exits non-zero ($RC)"
else
  _dossier_assert_fail "malformed JSON exited $RC"
fi

# --- The example validates ---------------------------------------------------
(cd "$REPO" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ABS" "$VALIDATE" --config "$EXAMPLE" --quiet >/dev/null 2>&1)
assert_equal "0" "$?" "config.example.json validates cleanly"

rm -rf "$WORK" 2>/dev/null

_dossier_test_summary
