#!/bin/bash
# [dossier] PreToolUse hook: enforce the run's action ceiling on Bash commands.
#
# engagement.allowedActions decides whether a run may build, test, or reach the
# network. Unenforced, those flags describe an intention; enforced, a claim
# marked "not executed" is a claim that genuinely could not be executed.
#
# Inert unless a dossier run is active (the frozen scope file is the signal).

set -uo pipefail

# Fails closed, for the same reason as enforce-output-root.sh: an action ceiling
# that switches itself off when a dependency is missing lets a run report
# "not executed" for a command that was never actually prevented.
if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED: dossier cannot enforce its action ceiling without jq on PATH." >&2
  exit 2
fi

INPUT=$(cat)

# A missing resolver means the ceiling cannot be read, not that it is absent.
# Keep the restrictive defaults and go on enforcing, matching what
# enforce-output-root.sh does in the same situation.
RESOLVER="${CLAUDE_PLUGIN_ROOT:-plugins/dossier}/bin/dossier-resolve-config.sh"
OUTPUT_ROOT="docs/dossier"
RUN_TESTS="false"
RUN_BUILD="false"
NETWORK="false"
RUN_SECURITY_SCAN="false"
RUN_CODE_QUALITY_SCAN="false"
if [ -x "$RESOLVER" ]; then
  OUTPUT_ROOT=$("$RESOLVER" --default "docs/dossier" dossier.project.outputRoot 2>/dev/null)
  # A resolver call that fails (subshell exit != 0) or returns empty stdout
  # must not be read as "output root is the empty string" -- $OUTPUT_ROOT
  # feeds directly into the scope-file existence check below, and an empty
  # value there resolves to an absolute-root path check that is essentially
  # always false, silently disabling the entire action ceiling for this run
  # with no error surfaced anywhere. Restrictive default, not an empty one.
  [ -n "$OUTPUT_ROOT" ] || OUTPUT_ROOT="docs/dossier"
  RUN_TESTS=$("$RESOLVER" --default "false" dossier.engagement.allowedActions.runTests 2>/dev/null)
  RUN_BUILD=$("$RESOLVER" --default "false" dossier.engagement.allowedActions.runBuild 2>/dev/null)
  NETWORK=$("$RESOLVER"   --default "false" dossier.engagement.allowedActions.networkAccess 2>/dev/null)
  RUN_SECURITY_SCAN=$("$RESOLVER" --default "false" dossier.engagement.allowedActions.runSecurityScan 2>/dev/null)
  RUN_CODE_QUALITY_SCAN=$("$RESOLVER" --default "false" dossier.engagement.allowedActions.runCodeQualityScan 2>/dev/null)
fi

# Inertness is decided entirely by OUTPUT_ROOT/the scope file, never by
# $INPUT's own shape -- checked before any JSON parsing so that a malformed
# hook payload on an ordinary, non-dossier command (no active run at all)
# stays inert rather than blocking it, matching this file's own header
# contract ("Inert unless a dossier run is active").
[ -f "$OUTPUT_ROOT/00-control/.scope.json" ] || exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
JQ_RC=$?
# A jq parse failure (malformed/truncated hook payload) is a different
# failure than "no tool_input.command field present" -- both produce an
# empty $COMMAND, but only the latter means "nothing to enforce". Checked
# separately so a parse failure fails closed rather than silently taking the
# same exit-0 path as a genuinely inert command, matching this file's own
# declared fail-closed posture (see the jq-availability check above). Only
# reachable once a run is confirmed active (see the scope-file check above).
if [ "$JQ_RC" -ne 0 ]; then
  echo "BLOCKED: dossier could not parse the tool input JSON to enforce its action ceiling." >&2
  exit 2
fi
[ -z "$COMMAND" ] && exit 0

deny() { # capability | setting | matched-class
  cat >&2 <<EOF
BLOCKED: the run's action ceiling forbids this command.

  command class: $3
  capability:    $1
  setting:       dossier.engagement.allowedActions.$2 = false

Claims that depend on this check are recorded as "not executed" with this as
the reason — which is the honest outcome, not a gap. If the check is genuinely
required, record the ceiling change as a deliberate decision and re-run
/dossier:init; a run that widens its own ceiling mid-flight is not auditable.
EOF
  exit 2
}

# Anchored on a command boundary (start of line, pipe, semicolon, &&, subshell)
# so that `grep -r "npm test" docs/` — reading about a command — is not mistaken
# for running one. The optional trailing path run also catches `/usr/bin/curl`,
# which is the same command spelled absolutely.
BOUND='(^|[;&|(]|^[[:space:]]*)[[:space:]]*([A-Za-z0-9_.-]*/)*'

# One layer of indirection defeats a boundary anchor: `bash -c "npm test"`,
# `env curl ...`, `timeout 30 curl ...`, and `sudo -u www-data curl ...` all
# place the keyword where no boundary character precedes it.
#
# The obvious repair — strip the wrapper token and its flags — is the wrong
# shape, because it requires knowing which flags take a value. `timeout 30 curl`
# and `sudo -u www-data curl` each leave a non-flag argument sitting between the
# wrapper and the payload, and any enumeration of value-taking flags is a list
# that goes stale the first time a wrapper grows an option.
#
# So this does not try to find where the real command starts. When a wrapper is
# present anywhere in the command, whitespace itself becomes a boundary for the
# deny scan — every token position is checked, so no argument shape can hide a
# keyword behind a wrapper. The cost is a narrow over-block: with a wrapper in
# play, `timeout 5 grep -r "npm test" docs/` is refused although it only reads
# about a command. That is the correct direction to fail for a containment
# check, the message says exactly what happened, and dropping the wrapper
# re-runs it. Without a wrapper, the strict anchor below is unchanged and that
# case still passes.
# python/python3 close a proven bypass on the pyscn deny check specifically:
# pyscn is installed as a pip package (see templates/ci's own install step),
# so `python3 -m pyscn ...` / `python -m pyscn ...` are ordinary invocation
# shapes for it, not exotic ones — confirmed live that the pyscn deny check
# below permits them while correctly blocking bare pyscn/osv-scanner and
# env/sudo-wrapped forms.
# xargs -I{} curl {} needed no change at all for issue #143: `xargs` was
# already a WRAPPER token before that fix, so it already flips the whole
# command into whitespace-boundary mode — confirmed live for the plain-text
# case. A quoted/backslash-escaped denied word (`\xargs ...`, `"curl" ...`)
# still bypasses this entirely, including for tokens already listed here —
# see the Known limitation note below, tracked as issue #152.
WRAPPER='(^|[;&|(]|[[:space:]])[[:space:]]*([A-Za-z0-9_.-]*/)*(bash|sh|zsh|dash|ksh|env|command|exec|eval|xargs|nohup|setsid|stdbuf|script|time|timeout|nice|ionice|sudo|doas|su|python|python3)([[:space:]]|$)'

# find closes the issue #143 gap on its own regex, not by joining WRAPPER:
# `find . -exec curl https://evil {} \;` (and -execdir/-ok/-okdir) glue the
# sub-command execution position to a flag rather than spelling it as its own
# token, so neither WRAPPER nor the strict BOUND anchor used to fire for the
# command sitting inside them. This is classification by structure, not
# enumeration: `find` combined with ANY of its four sub-command-execution
# primaries (-exec/-execdir/-ok/-okdir) is what triggers boundary-widening —
# no per-denied-command matching, and no per-flag matching beyond the fixed,
# stable set find(1) itself defines. Requiring the co-occurrence (rather than
# putting bare `find` in WRAPPER) is deliberately more precise than the
# original fix: a bare `find . -name "npm test"` (or any other command that
# merely contains the word "find" elsewhere, e.g. a commit message like
# "docs: find and document the test workflow") is no longer swept into
# boundary-widening mode at all, closing a broader false-positive class a
# code-review pass demonstrated live on real-shaped input, not just this
# file's own already-accepted narrow "npm test" tradeoff.
FIND_EXEC='(^|[;&|(]|[[:space:]])[[:space:]]*([A-Za-z0-9_.-]*/)*find([[:space:]]|$).*[[:space:]]-(exec|execdir|ok|okdir)([[:space:]]|$)'

# Known limitation, deliberately not fixed here: this file's mechanism is
# "does this command name introduce an arbitrary sub-command execution
# position, regardless of which flag spells that out" — but only for the
# finite set of command names actually listed above. Genuinely different
# tools with the same shape (GNU `parallel`, `awk 'system(...)'`, `perl -e
# "exec(...)"`, `watch -x`, and others) are not covered and have no WRAPPER
# entry. This is not tracked as a separate issue: unlike `find`/`xargs`
# above, which came from an actual review finding on real PR traffic, this
# residual class has no concrete trigger yet.
#
# Second known limitation, tracked as issue #152 (not fixed here): quoting or
# backslash-escaping a denied word defeats BOUND/WRAPPER entirely, for ANY
# token listed anywhere in this file, not just `find`/`xargs` — confirmed
# live (`"curl" https://evil`, `\curl https://evil`, and `\find . -exec curl
# ... {} \;` all exit 0/permitted). This is broader and predates issue #143:
# the SCAN/BOUND_ACTIVE quote-stripping normalization only runs after a
# WRAPPER match is found, so a denied word spelled with a leading quote/
# backslash never triggers that normalization in the first place. Fixing it
# means normalizing unconditionally before any WRAPPER/FIND_EXEC/deny test,
# not something scoped to this file's find/xargs change.
#
# Real-world exposure stays low regardless of either limitation above — this
# hook is a local/interactive backstop only; the CI refresh
# job's own --allowedTools allowlist doesn't include `find`, `xargs`,
# `parallel`, `awk`, `perl`, or a bare shell at all, so the automated
# pipeline has no reach here.
SCAN="$COMMAND"
BOUND_ACTIVE="$BOUND"
if printf '%s' "$COMMAND" | grep -qE "$WRAPPER" || printf '%s' "$COMMAND" | grep -qE "$FIND_EXEC"; then
  # Quotes and command-substitution openers stop hiding a boundary, and every
  # whitespace run becomes one.
  SCAN=$(printf '%s' "$COMMAND" | sed -E -e 's,["'"'"'`],;,g' -e 's,\$\(,;,g')
  BOUND_ACTIVE='(^|[;&|(]|[[:space:]])[[:space:]]*([A-Za-z0-9_.-]*/)*'
fi

# Every check below tests $SCAN with $BOUND_ACTIVE, which are $COMMAND and the
# strict anchor unless a wrapper (or find's own exec-family primaries) was
# found.

if [ "$RUN_TESTS" != "true" ]; then
  if printf '%s' "$SCAN" | grep -qE "${BOUND_ACTIVE}(npm|yarn|pnpm|bun)[[:space:]]+(run[[:space:]]+)?test\b"; then
    deny "run tests" runTests "package-manager test"
  fi
  if printf '%s' "$SCAN" | grep -qE "${BOUND_ACTIVE}(pytest|jest|vitest|mocha|rspec|phpunit)\b"; then
    deny "run tests" runTests "test runner"
  fi
  if printf '%s' "$SCAN" | grep -qE "${BOUND_ACTIVE}(go|cargo|dotnet|mvn|gradle)[[:space:]]+test\b"; then
    deny "run tests" runTests "toolchain test"
  fi
fi

if [ "$RUN_BUILD" != "true" ]; then
  if printf '%s' "$SCAN" | grep -qE "${BOUND_ACTIVE}(npm|yarn|pnpm|bun)[[:space:]]+(run[[:space:]]+)?build\b"; then
    deny "run builds" runBuild "package-manager build"
  fi
  if printf '%s' "$SCAN" | grep -qE "${BOUND_ACTIVE}(make|cargo[[:space:]]+build|go[[:space:]]+build|mvn[[:space:]]+package|gradle[[:space:]]+build|docker[[:space:]]+build|tsc)\b"; then
    deny "run builds" runBuild "build tool"
  fi
  if printf '%s' "$SCAN" | grep -qE "${BOUND_ACTIVE}(npm|yarn|pnpm|bun|pip|pip3|poetry|bundle|cargo)[[:space:]]+(install|add|ci|fetch)\b"; then
    deny "run builds" runBuild "dependency install"
  fi
fi

if [ "$NETWORK" != "true" ]; then
  if printf '%s' "$SCAN" | grep -qE "${BOUND_ACTIVE}(curl|wget|nc|ncat|telnet|ssh|scp|rsync)\b"; then
    deny "network access" networkAccess "network client"
  fi
  # Read-only gh and git commands are permitted: they are how a run inspects
  # its own repository, and blocking them would make the plugin unusable
  # without buying any containment the sandbox does not already provide.
  if printf '%s' "$SCAN" | grep -qE "${BOUND_ACTIVE}git[[:space:]]+(push|remote[[:space:]]+add|clone)\b"; then
    deny "network access" networkAccess "git network operation"
  fi
  if printf '%s' "$SCAN" | grep -qE "${BOUND_ACTIVE}gh[[:space:]]+(pr[[:space:]]+(create|merge|edit|close)|issue[[:space:]]+(create|edit|close)|release[[:space:]]+create|api[[:space:]]+-X[[:space:]]*(POST|PUT|PATCH|DELETE))"; then
    deny "network access" networkAccess "GitHub mutation"
  fi
fi

# Defense-in-depth backstop: the primary containment for both scanners is
# architectural (dossier-scan-security.sh / dossier-scan-quality.sh run as
# an isolated pre-agent CI step, never from inside this agent's own Bash
# tool — see templates/ci/dossier-docs-refresh.yml). These two blocks still
# deny a direct invocation that bypasses the wrapper, so the ceiling holds
# even if that architectural boundary is ever circumvented. Neither block
# matches the wrapper scripts' own names (dossier-scan-security.sh /
# dossier-scan-quality.sh), only the underlying tool binaries.
if [ "$RUN_SECURITY_SCAN" != "true" ]; then
  if printf '%s' "$SCAN" | grep -qE "${BOUND_ACTIVE}osv-scanner\b"; then
    deny "run a security scan" runSecurityScan "osv-scanner invocation"
  fi
fi

if [ "$RUN_CODE_QUALITY_SCAN" != "true" ]; then
  if printf '%s' "$SCAN" | grep -qE "${BOUND_ACTIVE}pyscn\b"; then
    deny "run a code-quality scan" runCodeQualityScan "pyscn invocation"
  fi
fi

exit 0
