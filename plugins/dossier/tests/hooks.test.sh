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

# --- Traversal out of the output root ----------------------------------------
# The allow-case is a `case` glob, and a glob `*` matches `/`. Without an
# explicit refusal, `docs/dossier/../../etc/passwd` starts with the allowed
# prefix and is permitted while landing outside the root — a containment check
# that can be stepped around by respelling the path is not one.
for BAD in \
  'docs/dossier/../../../etc/passwd' \
  'docs/dossier/../../.github/workflows/evil.yml' \
  '.dossier/../../../etc/hosts'
do
  RC=0
  (cd "$WORK" && printf '{"tool_input":{"file_path":"%s","content":"x"}}' "$BAD" \
     | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-output-root.sh" >/dev/null 2>&1) || RC=$?
  assert_equal "2" "$RC" "enforce-output-root refuses the traversal $BAD"
done

# --- The action ceiling actually denies --------------------------------------
# Previously only the inert path was exercised, so deny() could have been
# deleted without a failing assertion.
RC=0
OUT=$(cd "$WORK" && printf '%s' '{"tool_input":{"command":"npm test"}}' \
        | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" 2>&1) || RC=$?
assert_equal "2" "$RC" "enforce-allowed-actions denies a test run when runTests is false"
assert_contains "BLOCKED" "$OUT" "the deny message names the block"

# One layer of indirection must not defeat the ceiling. Each of these places the
# denied keyword where no command-boundary character precedes it.
for BAD in \
  '/usr/bin/curl https://example.invalid' \
  'env curl https://example.invalid' \
  'command curl https://example.invalid' \
  'bash -c "npm test"' \
  'eval "curl https://example.invalid"'
do
  RC=0
  (cd "$WORK" && printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$BAD" | jq -Rs .)" \
     | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
  assert_equal "2" "$RC" "enforce-allowed-actions sees through the wrapper: $BAD"
done

# Wrappers that take an argument of their own. The first fix stripped the
# wrapper token plus one optional flag, which left `30` sitting between
# `timeout` and `curl` so the anchor never matched and the whole deny list
# passed. `timeout N cmd` is the single most idiomatic way to bound a command,
# so this was the modal bypass rather than an exotic one — and it shipped
# because every wrapper case tested above happens to take no argument.
for BAD in \
  'timeout 30 curl https://example.invalid' \
  'timeout 30 npm test' \
  'timeout 600 npm install' \
  'timeout -s KILL 30 curl https://example.invalid' \
  'timeout --kill-after=5 30 npm test' \
  'sudo -u www-data curl https://example.invalid' \
  'nice -n 10 curl https://example.invalid'
do
  RC=0
  (cd "$WORK" && printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$BAD" | jq -Rs .)" \
     | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
  assert_equal "2" "$RC" "enforce-allowed-actions sees through an argument-taking wrapper: $BAD"
done

# …and reading *about* a command is still not running one. This is the case the
# boundary anchor exists for, and the wrapper handling above must not break it.
RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"command":"grep -r \"npm test\" docs/"}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
assert_equal "0" "$RC" "enforce-allowed-actions permits grepping for a command name"

# Commands that merely contain a wrapper must not be denied on that basis.
for OK in 'timeout 5 ls' 'time ls' 'nice ls' 'env ls' 'ls -la' 'git status' 'cat README.md'; do
  RC=0
  (cd "$WORK" && printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$OK" | jq -Rs .)" \
     | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
  assert_equal "0" "$RC" "enforce-allowed-actions permits: $OK"
done

# --- Quoting/backslash-escaping a denied word (issue #152) -------------------
# Independent of any wrapper token: a denied word spelled with a leading or
# interior quote/backslash used to reach deny() as an intact, unrecognizable
# word. Each of these is a real invocation once bash processes it — confirmed
# live for every one (including a real curl attempt) while developing the fix.
for BAD in \
  '"curl" https://example.invalid|whole word quoted' \
  '\curl https://example.invalid|leading backslash' \
  'c\url https://example.invalid|mid-word backslash split'
do
  CASE_CMD="${BAD%%|*}"
  CASE_LABEL="${BAD##*|}"
  RC=0
  (cd "$WORK" && printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$CASE_CMD" | jq -Rs .)" \
     | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
  assert_equal "2" "$RC" "enforce-allowed-actions closes the quote/backslash bypass ($CASE_LABEL): $CASE_CMD"
done

# Adjacent quote fragments: bash joins these into ONE word at execution time
# (cu''rl -> curl), the same way `r''m` is two tokens to a naive matcher but
# one to bash after quote removal.
RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"command":"cu'"''"'rl https://example.invalid"}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
assert_equal "2" "$RC" "enforce-allowed-actions closes the adjacent-single-quote-fragment bypass: cu''rl"

RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"command":"cu\"r\"l https://example.invalid"}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
assert_equal "2" "$RC" 'enforce-allowed-actions closes the adjacent-double-quote-fragment bypass: cu"r"l'

# A backslash immediately followed by a real newline (bash's own line
# continuation) splits a keyword across two lines. This one needed its own
# ordering fix during development: joining the pair AFTER stripping lone
# backslashes leaves the newline behind as a still-valid separator, silently
# reopening the bypass.
NL_CMD=$(printf 'cur\\\nl https://example.invalid')
RC=0
(cd "$WORK" && printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$NL_CMD" | jq -Rs .)" \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
assert_equal "2" "$RC" "enforce-allowed-actions closes the backslash-newline line-continuation bypass"

# The exact third reproduction from issue #152 itself: a leading backslash on
# `find` combines the #152 backslash bypass with the #143 find/-exec bypass —
# DEQUOTED must restore `find` before FIND_EXEC is tested, not just restore
# bare denied words like `curl` on their own.
RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"command":"\\find . -exec curl https://example.invalid {} \\;"}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
assert_equal "2" "$RC" 'enforce-allowed-actions closes the backslash-escaped find+-exec bypass: \find . -exec curl {} \;'

# Bash's own ANSI-C quoting ($'...') decodes octal/hex escapes independently
# of ordinary quote removal — confirmed to execute a real curl call.
for BAD in \
  '$'"'"'\143url'"'"' https://example.invalid|ansi-c octal' \
  '$'"'"'\x63url'"'"' https://example.invalid|ansi-c hex'
do
  CASE_CMD="${BAD%%|*}"
  CASE_LABEL="${BAD##*|}"
  RC=0
  (cd "$WORK" && printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$CASE_CMD" | jq -Rs .)" \
     | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
  assert_equal "2" "$RC" "enforce-allowed-actions closes the $CASE_LABEL bypass: $CASE_CMD"
done

# Known, accepted trade-off from the fix above: deleting a quote mark can
# bring a boundary character and a denied word directly together when nothing
# else separated them (a quote mark is the ENTIRE gap between the two). This
# is a genuinely new effect of this fix, not pre-existing behavior — confirmed
# by running this exact case against the pre-fix script, which permitted it
# (rc=0); it must stay blocked now, proving the trade-off is deliberate
# (documented in enforce-allowed-actions.sh), not a silent surprise.
RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"command":"echo hi;\"curl\" https://example.invalid"}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
assert_equal "2" "$RC" 'enforce-allowed-actions accepts the documented over-block: echo hi;"curl" ... refused, a quote mark was the entire gap to the boundary char'

# --- DEQUOTE_PLACEHOLDER collision and pathological-size guard (found reviewing this PR) ---
# ansi_c_decode can manufacture a literal 0x01 byte from a plain $'\001'
# escape in the ORIGINAL command -- the exact byte DEQUOTE_PLACEHOLDER uses
# internally. Without a guard, that byte is indistinguishable from a
# backslash this script marks itself, and gets deleted alongside a real
# newline it happens to precede, splicing two statements into one with no
# boundary character left to anchor on.
SOH_CMD=$(printf 'echo done\001\ncurl https://example.invalid')
RC=0
(cd "$WORK" && printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$SOH_CMD" | jq -Rs .)" \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
assert_equal "2" "$RC" "enforce-allowed-actions closes the DEQUOTE_PLACEHOLDER (0x01) collision bypass"

# A real two-statement command with no stray 0x01 byte must still be denied
# for its own actual reason (proves the fix above isn't over-blocking every
# multi-line command, just the byte-collision case).
NL_ONLY_CMD=$(printf 'echo done\ncurl https://example.invalid')
RC=0
(cd "$WORK" && printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$NL_ONLY_CMD" | jq -Rs .)" \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
assert_equal "2" "$RC" "enforce-allowed-actions still denies an ordinary two-line command (network access), unrelated to the 0x01 guard"

# ansi_c_decode's span-boundary search and the backslash-to-placeholder pass
# are both quadratic in bash for large operands (confirmed empirically: a
# 100KB command with ANSI-C content took ~20s to normalize before this
# guard existed). A command over the length guard must be denied instantly,
# not hang.
LARGE_BODY=$(printf 'A%.0s' $(seq 1 9000))
RC=0
START_TS=$(date +%s)
(cd "$WORK" && printf '{"tool_input":{"command":%s}}' "$(printf 'echo $'"'"'%s'"'"' https://example.invalid' "$LARGE_BODY" | jq -Rs .)" \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
END_TS=$(date +%s)
assert_equal "2" "$RC" "enforce-allowed-actions denies a command over the pathological-size guard (9000 bytes)"
assert_equal "1" "$([ "$((END_TS - START_TS))" -le 3 ] && echo 1 || echo 0)" "the size guard rejects instantly rather than attempting the super-linear normalization"

# --- find -exec/-execdir/-ok/-okdir and xargs -I{} indirection (issue #143) ---
# -exec/-execdir/-ok/-okdir glue the sub-command execution position to a flag
# rather than spelling it as a standalone token, so neither BOUND nor the prior
# WRAPPER token list ever fired for the denied command sitting inside them.
# One representative command per existing deny-block, so the fix (adding
# "find" to WRAPPER) is proven to apply uniformly to every block rather than
# just the block it happened to be developed against.
for CASE in \
  'find . -exec npm test {} \;|runTests' \
  'find . -exec curl https://example.invalid {} \;|networkAccess' \
  'find . -execdir curl https://example.invalid {} \;|networkAccess' \
  'find . -ok curl https://example.invalid {} \;|networkAccess' \
  'find . -okdir curl https://example.invalid {} \;|networkAccess' \
  'find . -exec osv-scanner {} \;|runSecurityScan' \
  'find . -exec pyscn {} \;|runCodeQualityScan'
do
  BAD="${CASE%%|*}"
  CLASS="${CASE##*|}"
  RC=0
  (cd "$WORK" && printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$BAD" | jq -Rs .)" \
     | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
  assert_equal "2" "$RC" "enforce-allowed-actions sees through find's exec position ($CLASS): $BAD"
done

# runBuild's own denied tokens (make/cargo build/...) require a bare command
# word, unlike npm/osv-scanner/curl above, so this needs its own case rather
# than reusing the loop's single-word BAD strings.
RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"command":"find . -exec make {} \\;"}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
assert_equal "2" "$RC" "enforce-allowed-actions sees through find's exec position (runBuild): find . -exec make {} \\;"

# xargs -I{} was already covered by the pre-existing WRAPPER token list (xargs
# itself is a standalone token there), but AC1 names it explicitly, so it gets
# its own direct assertion rather than relying on the general wrapper-loop
# above to stand in for it.
RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"command":"xargs -I{} curl {}"}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
assert_equal "2" "$RC" "enforce-allowed-actions denies xargs -I{} <denied-command> {} (networkAccess)"

# A find invocation with no -exec/-execdir/-ok/-okdir must never trip
# boundary-widening at all, even when it merely searches for a denied phrase
# as a -name argument -- this was an accepted over-block under the original
# bare-"find"-in-WRAPPER fix, and is now correctly resolved by requiring
# find to actually co-occur with one of its own sub-command-execution
# primaries (FIND_EXEC) rather than triggering on the bare token. Also
# covers a broader real-shape false positive a code-review pass demonstrated
# live: an ordinary commit-message-shaped string that merely contains both
# "find" and a denied phrase as separate words, with no find invocation at
# all.
RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"command":"find . -name \"npm test\""}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
assert_equal "0" "$RC" "find . -name \"npm test\" (no -exec) is correctly NOT over-blocked -- find alone never widens boundary mode"

RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"command":"git commit -m \"docs: find and document the npm test workflow\""}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
assert_equal "0" "$RC" "a command whose text merely contains both \"find\" and a denied phrase as separate words (no find invocation) is not over-blocked"

# Ordinary find usage with no embedded denied command must still pass — the
# fix must not turn every find invocation into a denial.
RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"command":"find . -type f -name \"*.md\""}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
assert_equal "0" "$RC" "ordinary find usage with no denied command embedded is still permitted"

# -execdir/-ok/-okdir coverage (not just -exec) is already proven above by
# the "sees through find's exec position" loop -- no separate FIND_EXEC-
# specific assertion needed here.

# --- Scanner deny-blocks (issue #137): a defense-in-depth backstop for the
# two new runSecurityScan/runCodeQualityScan flags, on top of the primary
# architectural containment (the scanners run as an isolated CI step, never
# from inside this agent's own Bash tool). ------------------------------------
RC=0
OUT=$(cd "$WORK" && printf '%s' '{"tool_input":{"command":"osv-scanner scan source -r ."}}' \
        | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" 2>&1) || RC=$?
assert_equal "2" "$RC" "enforce-allowed-actions denies a direct osv-scanner invocation when runSecurityScan is false"
assert_contains "BLOCKED" "$OUT" "the osv-scanner deny message names the block"

RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"command":"pyscn analyze --json ."}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
assert_equal "2" "$RC" "enforce-allowed-actions denies a direct pyscn invocation when runCodeQualityScan is false"

# Wrapper-indirection bypass, same technique proven above for curl/npm.
# python/python3 are proven bypasses specifically for pyscn (holdout finding
# on issue #137's PR review): pyscn is pip-installed, so `python3 -m pyscn`
# is an ordinary invocation shape for it, not an exotic one.
for BAD in \
  'bash -c "osv-scanner scan source -r ."' \
  'env pyscn analyze --json .' \
  'timeout 30 osv-scanner scan source -r .' \
  'sudo -u www-data pyscn analyze --json .' \
  'python3 -m pyscn analyze --json .' \
  'python -m pyscn analyze --json .'
do
  RC=0
  (cd "$WORK" && printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$BAD" | jq -Rs .)" \
     | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
  assert_equal "2" "$RC" "enforce-allowed-actions sees through the wrapper: $BAD"
done

# Reading about the tool is not running it.
RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"command":"grep -r \"osv-scanner\" docs/"}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
assert_equal "0" "$RC" "enforce-allowed-actions permits grepping for osv-scanner by name"

# The wrapper scripts' own names are never denied by these blocks — they
# contain neither literal "osv-scanner" nor "pyscn" as a command token.
RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"command":"dossier-scan-security.sh --target ."}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
assert_equal "0" "$RC" "enforce-allowed-actions never denies dossier-scan-security.sh by its own name"

# The flag-true permit path — not demonstrated anywhere above for any
# capability. Env var name traced by hand through dossier-resolve-config.sh's
# own sed pipeline: dossier.engagement.allowedActions.runSecurityScan ->
# DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN. Also proves AC3 at
# the hook layer: enabling runSecurityScan alone must not also permit pyscn.
RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"command":"osv-scanner scan source -r ."}}' \
   | DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" \
     "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
assert_equal "0" "$RC" "enforce-allowed-actions permits osv-scanner once runSecurityScan resolves true"

RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"command":"pyscn analyze --json ."}}' \
   | DOSSIER_ENGAGEMENT_ALLOWED_ACTIONS_RUN_SECURITY_SCAN=true CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" \
     "$REPO/$HS/enforce-allowed-actions.sh" >/dev/null 2>&1) || RC=$?
assert_equal "2" "$RC" "AC3 at the hook layer: runSecurityScan=true alone does not also permit pyscn"

# --- Security hooks fail closed ----------------------------------------------
# A boundary that switches itself off when a dependency is missing is
# indistinguishable from one that was never there. Simulated by giving the hook
# a PATH with no jq on it.
for H in enforce-output-root enforce-allowed-actions block-unregistered-claim; do
  RC=0
  (cd "$WORK" && printf '%s' '{"tool_input":{"file_path":"src/x.ts","content":"x","command":"curl https://example.invalid"}}' \
     | PATH=/nonexistent CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" \
       /bin/bash "$REPO/$HS/$H.sh" >/dev/null 2>&1) || RC=$?
  assert_equal "2" "$RC" "$H fails closed when jq is unavailable"
done

# A distinct failure class from "jq unavailable": jq present but given input
# it cannot parse (a malformed/truncated hook payload). Before the fix, this
# produced an empty $COMMAND indistinguishable from "no command field present"
# -- both took the same `[ -z "$COMMAND" ] && exit 0` path, silently allowing
# the run to proceed with its action ceiling entirely unenforced for that
# command, contradicting the file's own declared fail-closed posture.
# Exercised here with an active run ($WORK's .scope.json is still in place
# from earlier in this file), and a more specific assertion than a bare
# "BLOCKED" substring so this case is distinguishable from the jq-unavailable
# case tested just above -- both emit "BLOCKED", only this one names parsing.
RC=0
OUT=$(cd "$WORK" && printf '%s' '{not valid json' \
        | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" 2>&1) || RC=$?
assert_equal "2" "$RC" "enforce-allowed-actions fails closed on malformed JSON input during an active run, not silently allowed"
assert_contains "could not parse" "$OUT" "the malformed-input failure specifically names parsing, distinct from the jq-unavailable failure"

# But with NO active run at all (no .scope.json anywhere under the cwd), the
# same malformed payload must stay inert -- matching this file's own header
# contract ("Inert unless a dossier run is active") for the ordinary case of
# a non-dossier repository that merely has the hook installed. This is the
# regression test for the reordering fix: inertness is decided before any
# JSON parsing is attempted, not after.
NORUN=$(mktemp -d 2>/dev/null) || NORUN="/tmp/dossier-hooks-norun.$$"
mkdir -p "$NORUN" 2>/dev/null
RC=0
OUT=$(cd "$NORUN" && printf '%s' '{not valid json' \
        | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/enforce-allowed-actions.sh" 2>&1) || RC=$?
assert_equal "0" "$RC" "malformed JSON with no active dossier run stays inert, matching the header contract"
rm -rf "$NORUN" 2>/dev/null

# stale-header-stamp and detect-local-merge are advisory, so they correctly
# do the reverse.
RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"file_path":"docs/dossier/01-project/brief.md"}}' \
   | PATH=/nonexistent CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" \
     /bin/bash "$REPO/$HS/stale-header-stamp.sh" >/dev/null 2>&1) || RC=$?
assert_equal "0" "$RC" "stale-header-stamp stays advisory when jq is unavailable"

RC=0
(cd "$WORK" && printf '%s' '{"tool_input":{"command":"git merge feature"}}' \
   | PATH=/nonexistent CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" \
     /bin/bash "$REPO/$HS/detect-local-merge.sh" >/dev/null 2>&1) || RC=$?
assert_equal "0" "$RC" "detect-local-merge stays advisory when jq is unavailable"

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

# disclosure-policy-levels.md names internal repository paths alongside register
# IDs, and says this hook enforces the rule together with dossier-claim-scan.sh.
# The scanner had the pattern and the hook did not, so the live block deferred a
# class it never documented as deferred.
RC=0
(printf '%s' '{"tool_input":{"file_path":"docs/dossier/06-public/guide.md","content":"See src/internal/billing/config.rb for the derivation."}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/block-unregistered-claim.sh" >/dev/null 2>&1) || RC=$?
assert_equal "2" "$RC" "block-unregistered-claim blocks an internal repository path"

# The hook and the batch scanner must agree on the class, or one of them is
# certifying a document the other would reject.
if grep -q 'check "internal-path"' "$HS/block-unregistered-claim.sh" \
   && grep -q '"internal-path"' "$PLUGIN/bin/dossier-claim-scan.sh"; then
  _dossier_assert_pass "hook and batch scanner both implement internal-path"
else
  _dossier_assert_fail "internal-path is implemented in only one of the hook and the scanner"
fi

# --- The stamp hook warns, never blocks --------------------------------------
mkdir -p "$WORK/docs/dossier/01-project" 2>/dev/null
printf -- '---\ndossier-header: internal-v1\nlast-verified: 2020-01-01\n---\n# X\n' \
  > "$WORK/docs/dossier/01-project/brief.md" 2>/dev/null
RC=0
OUT=$(cd "$WORK" && printf '%s' '{"tool_input":{"file_path":"docs/dossier/01-project/brief.md"}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/stale-header-stamp.sh" 2>&1) || RC=$?
assert_equal "0" "$RC" "stale-header-stamp warns without blocking"
# Exit 0 is this script's only outcome by design, so asserting it alone would
# still pass with the warning logic deleted. The message is the behaviour.
assert_contains "last-verified" "$OUT" "stale-header-stamp names the stale field"

# A freshly verified document must not warn, or the signal is noise.
TODAY=$(date -u +%Y-%m-%d)
printf -- '---\ndossier-header: internal-v1\nlast-verified: %s\n---\n# X\n' "$TODAY" \
  > "$WORK/docs/dossier/01-project/fresh.md" 2>/dev/null
OUT=$(cd "$WORK" && printf '%s' '{"tool_input":{"file_path":"docs/dossier/01-project/fresh.md"}}' \
   | CLAUDE_PLUGIN_ROOT="$REPO/$PLUGIN" "$REPO/$HS/stale-header-stamp.sh" 2>&1)
assert_not_contains "last-verified" "$OUT" "stale-header-stamp is silent on a same-day document"

rm -rf "$WORK" 2>/dev/null

_dossier_test_summary
