#!/usr/bin/env bash
# Hooks: manifest validity, script resolution, and — the part that matters —
# that each hook is INERT when no run is active and ACTIVE when one is.
#
# A hook that fires unconditionally makes the plugin hostile to install: it
# would block ordinary editing in any repo that merely has dossier available.
# A hook that never fires is decoration.

_dossier_test_begin "hooks"

PLUGIN="plugins/dossier"
HOOKS_JSON="$PLUGIN/hooks/hooks.json"

assert_file_exists "$HOOKS_JSON" "hooks.json exists"

if command -v jq >/dev/null 2>&1; then
  if jq -e . "$HOOKS_JSON" >/dev/null 2>&1; then
    _dossier_assert_pass "hooks.json is valid JSON"
  else
    _dossier_assert_fail "hooks.json is not valid JSON"
  fi

  for ev in PreToolUse PostToolUse; do
    if jq -e ".hooks.$ev" "$HOOKS_JSON" >/dev/null 2>&1; then
      _dossier_assert_pass "hooks.json binds $ev"
    else
      _dossier_assert_fail "hooks.json does not bind $ev"
    fi
  done

  # Every referenced script must exist and be executable, or the hook fails at
  # runtime with a message that points at the harness rather than at us.
  while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue
    rel=${cmd#\$\{CLAUDE_PLUGIN_ROOT\}/}
    path="$PLUGIN/$rel"
    if [ -f "$path" ]; then
      _dossier_assert_pass "hook script $rel exists"
    else
      _dossier_assert_fail "hook script $rel does not exist"
      continue
    fi
    [ -x "$path" ] && _dossier_assert_pass "hook script $rel is executable" \
                   || _dossier_assert_fail "hook script $rel is not executable"
    bash -n "$path" 2>/dev/null && _dossier_assert_pass "hook script $rel passes bash -n" \
                                || _dossier_assert_fail "hook script $rel has a syntax error"
    case "$cmd" in
      '${CLAUDE_PLUGIN_ROOT}/'*) _dossier_assert_pass "hook $rel uses CLAUDE_PLUGIN_ROOT" ;;
      *) _dossier_assert_fail "hook command is not rooted at CLAUDE_PLUGIN_ROOT: $cmd" ;;
    esac
  done <<EOF
$(jq -r '.hooks | to_entries[] | .value[] | .hooks[] | .command' "$HOOKS_JSON" 2>/dev/null)
EOF
else
  _dossier_assert_fail "jq unavailable — cannot validate hooks.json"
fi

HS="$PLUGIN/hooks/scripts"
REPO=$(pwd)

# --- Inert with no active run ------------------------------------------------
# The frozen scope file is the signal that a dossier run owns the session.
WORK=$(mktemp -d 2>/dev/null) || WORK="/tmp/dossier-hooks.$$"
mkdir -p "$WORK" 2>/dev/null

OUT=$(cd "$WORK" && printf '%s' '{"tool_input":{"file_path":"/tmp/unrelated.md","content":"hello"}}' \
        | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-output-root.sh" 2>&1)
RC=$?
assert_equal "0" "$RC" "enforce-output-root is inert with no active run"

OUT=$(cd "$WORK" && printf '%s' '{"tool_input":{"command":"npm test"}}' \
        | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" 2>&1)
RC=$?
assert_equal "0" "$RC" "enforce-allowed-actions is inert with no active run"

# --- Active once a run is frozen ---------------------------------------------
mkdir -p "$WORK/docs/dossier/00-control" 2>/dev/null
printf '{"schema_version":1}\n' > "$WORK/docs/dossier/00-control/.scope.json" 2>/dev/null

RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"file_path":"src/app.ts","content":"x"}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-output-root.sh" >/dev/null 2>&1) || RC=$?
assert_equal "2" "$RC" "enforce-output-root blocks a write outside the output root during a run"

RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"file_path":"docs/dossier/01-project/x.md","content":"x"}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-output-root.sh" >/dev/null 2>&1) || RC=$?
assert_equal "0" "$RC" "enforce-output-root permits a write inside the output root"

RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"file_path":".dossier/evidence/manifest.json","content":"x"}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-output-root.sh" >/dev/null 2>&1) || RC=$?
assert_equal "0" "$RC" "enforce-output-root permits the evidence working directory"

# --- Disclosure hook is unconditional ----------------------------------------
# Leakage into a public document is blocked whether or not a run is "active",
# because the cost of a miss is unretractable.
RC=0
OUT=$(printf '%s' '{"tool_input":{"file_path":"docs/dossier/06-public/guide.md","content":"token sk-ant-abcd12345678"}}' \
        | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/block-unregistered-claim.sh" 2>&1) || RC=$?
assert_equal "2" "$RC" "block-unregistered-claim blocks a credential bound for 06-public"

# The matched value must never be echoed — printing it copies the leak into a
# transcript that is itself shared.
assert_not_contains "sk-ant-abcd12345678" "$OUT" "the matched secret value is never printed"
assert_contains "anthropic-key" "$OUT" "the pattern class is named instead"

RC=0
(printf '%s' '{"tool_input":{"file_path":"docs/dossier/06-public/guide.md","content":"The API supports OAuth 2.0."}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/block-unregistered-claim.sh" >/dev/null 2>&1) || RC=$?
assert_equal "0" "$RC" "block-unregistered-claim permits clean public content"

# Internal register IDs must not reach a public document.
RC=0
(printf '%s' '{"tool_input":{"file_path":"docs/dossier/06-public/guide.md","content":"See EV-0042 for details."}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/block-unregistered-claim.sh" >/dev/null 2>&1) || RC=$?
assert_equal "2" "$RC" "block-unregistered-claim blocks an internal evidence ID"

# Internal documents are not the disclosure hook's business.
RC=0
(printf '%s' '{"tool_input":{"file_path":"docs/dossier/02-architecture/system.md","content":"See EV-0042."}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/block-unregistered-claim.sh" >/dev/null 2>&1) || RC=$?
assert_equal "0" "$RC" "block-unregistered-claim ignores internal documents"

# --- The stamp hook warns, never blocks --------------------------------------
mkdir -p "$WORK/docs/dossier/01-project" 2>/dev/null
printf -- '---\ndossier-header: internal-v1\nlast-verified: 2020-01-01\n---\n# X\n' \
  > "$WORK/docs/dossier/01-project/brief.md" 2>/dev/null
RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"file_path":"docs/dossier/01-project/brief.md"}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/stale-header-stamp.sh" >/dev/null 2>&1) || RC=$?
assert_equal "0" "$RC" "stale-header-stamp warns without blocking"

rm -rf "$WORK" 2>/dev/null

_dossier_test_summary
