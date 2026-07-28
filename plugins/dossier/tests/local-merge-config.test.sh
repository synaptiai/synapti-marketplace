#!/usr/bin/env bash
# dossier.local.onFlowMerge -> dossier.local.onLocalMerge (issue #135 part B).
# onFlowMerge was dead configuration coupling dossier to a specific other
# plugin's presence; onLocalMerge replaces it with the same suggest/run/off
# semantics, implemented entirely inside dossier (tested in
# local-merge-hook.test.sh).

_dossier_test_begin "local-merge-config"

RESOLVER="plugins/dossier/bin/dossier-resolve-config.sh"

for f in plugins/dossier/schema.json plugins/dossier/settings.json plugins/dossier/templates/config.example.json .claude/settings.dossier.json; do
  if [ -f "$f" ]; then
    if grep -q "onFlowMerge" "$f"; then
      _dossier_assert_fail "$f still references onFlowMerge"
    else
      _dossier_assert_pass "$f has no remaining onFlowMerge reference"
    fi
    if grep -q "onLocalMerge" "$f"; then
      _dossier_assert_pass "$f declares onLocalMerge"
    else
      _dossier_assert_fail "$f does not declare onLocalMerge"
    fi
  else
    _dossier_assert_fail "$f missing"
  fi
done

if [ -x "$RESOLVER" ]; then
  RESOLVED=$(CLAUDE_PLUGIN_ROOT="$(pwd)/plugins/dossier" "$RESOLVER" --default "off" dossier.local.onLocalMerge 2>/dev/null)
  assert_equal "suggest" "$RESOLVED" "dossier.local.onLocalMerge resolves to the plugin default 'suggest'"
else
  _dossier_assert_fail "$RESOLVER missing or not executable"
fi

# Zero repo-wide runtime references (settings/schema/templates are config
# declarations, not consumers; the assertion above already checked those).
# A stray reference in bin/, hooks/, agents/, or commands/ would mean the
# rename missed a consumer.
STRAY=$(grep -rl "onFlowMerge" plugins/dossier/bin plugins/dossier/hooks plugins/dossier/agents plugins/dossier/commands 2>/dev/null)
if [ -z "$STRAY" ]; then
  _dossier_assert_pass "no runtime consumer under bin/hooks/agents/commands references onFlowMerge"
else
  _dossier_assert_fail "stray onFlowMerge reference(s): $STRAY"
fi

_dossier_test_summary
