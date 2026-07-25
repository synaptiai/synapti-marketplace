#!/usr/bin/env bash
# Plugin identity: manifest fields, and version agreement across the three
# places a version is written. Drift here is silent — the plugin installs and
# behaves, it just reports the wrong version — so it is checked mechanically.

_dossier_test_begin "plugin-manifest"

PLUGIN_JSON="plugins/dossier/.claude-plugin/plugin.json"
MARKETPLACE=".claude-plugin/marketplace.json"
CHANGELOG="plugins/dossier/CHANGELOG.md"

assert_file_exists "$PLUGIN_JSON" "plugin.json exists"
assert_file_exists "plugins/dossier/README.md" "README.md exists"
assert_file_exists "$CHANGELOG" "CHANGELOG.md exists"

if command -v jq >/dev/null 2>&1; then
  for field in name version description author repository homepage license keywords; do
    v=$(jq -r ".$field // empty" "$PLUGIN_JSON" 2>/dev/null)
    if [ -n "$v" ]; then
      _dossier_assert_pass "plugin.json has $field"
    else
      _dossier_assert_fail "plugin.json missing required field: $field"
    fi
  done

  assert_equal "dossier" "$(jq -r '.name' "$PLUGIN_JSON")" "plugin name is dossier"

  # The declared licence is checked against the repository's LICENSE file rather
  # than a constant. A hard-coded identifier passes happily while the file it
  # refers to says something else — which is exactly how this repository came to
  # advertise a licence it did not carry.
  REPO_LICENSE="LICENSE"
  if [ -f "$REPO_LICENSE" ]; then
    _dossier_assert_pass "repository carries a LICENSE file"
    EXPECTED_SPDX=""
    if grep -q 'Apache License' "$REPO_LICENSE" && grep -q 'Version 2\.0' "$REPO_LICENSE"; then
      EXPECTED_SPDX="Apache-2.0"
    elif grep -q 'MIT License' "$REPO_LICENSE"; then
      EXPECTED_SPDX="MIT"
    fi
    if [ -n "$EXPECTED_SPDX" ]; then
      assert_equal "$EXPECTED_SPDX" "$(jq -r '.license' "$PLUGIN_JSON")" \
        "plugin.json license matches the LICENSE file ($EXPECTED_SPDX)"
    else
      _dossier_assert_fail "LICENSE file text matches no SPDX identifier this test recognizes"
    fi
  else
    _dossier_assert_fail "no LICENSE file at the repository root — the declared licence grants nothing"
  fi

  # author is an object with name and url, matching the sibling plugins.
  assert_match '^[A-Za-z]' "$(jq -r '.author.name // empty' "$PLUGIN_JSON")" "author.name present"
  assert_match '^https://' "$(jq -r '.author.url // empty' "$PLUGIN_JSON")" "author.url is a URL"

  # homepage is the deep link in plugin.json (marketplace.json uses the bare repo URL).
  assert_match 'tree/main/plugins/dossier$' "$(jq -r '.homepage' "$PLUGIN_JSON")" \
    "plugin.json homepage deep-links to the plugin"

  PV=$(jq -r '.version' "$PLUGIN_JSON")
  assert_match '^[0-9]+\.[0-9]+\.[0-9]+$' "$PV" "version is semver"

  # marketplace.json entry
  ENTRY=$(jq -c '.plugins[] | select(.name == "dossier")' "$MARKETPLACE" 2>/dev/null)
  if [ -n "$ENTRY" ]; then
    _dossier_assert_pass "dossier registered in marketplace.json"
    assert_equal "$PV" "$(printf '%s' "$ENTRY" | jq -r '.version')" \
      "marketplace version matches plugin.json"
    assert_equal "./plugins/dossier" "$(printf '%s' "$ENTRY" | jq -r '.source')" \
      "marketplace source path is correct"
    for f in description category keywords tags license; do
      v=$(printf '%s' "$ENTRY" | jq -r ".$f // empty")
      if [ -n "$v" ]; then
        _dossier_assert_pass "marketplace entry has $f"
      else
        _dossier_assert_fail "marketplace entry missing $f"
      fi
    done
  else
    _dossier_assert_fail "dossier not registered in marketplace.json"
  fi

  # settings.json declares the version the rendered workflow was generated
  # against; a mismatch tells the user to re-run /dossier:setup.
  SV=$(jq -r '.dossier.ci.expectedPluginVersion // empty' plugins/dossier/settings.json 2>/dev/null)
  assert_equal "$PV" "$SV" "settings.json ci.expectedPluginVersion matches plugin.json"
else
  _dossier_assert_fail "jq not available — cannot validate manifests"
fi

# The top CHANGELOG heading must name the current version.
CL_VERSION=$(grep -m1 -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$CHANGELOG" 2>/dev/null | tr -d '#[] ')
assert_equal "$PV" "$CL_VERSION" "CHANGELOG top entry matches plugin.json version"

_dossier_test_summary
