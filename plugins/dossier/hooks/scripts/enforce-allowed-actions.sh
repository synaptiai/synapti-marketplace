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
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

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
  RUN_TESTS=$("$RESOLVER" --default "false" dossier.engagement.allowedActions.runTests 2>/dev/null)
  RUN_BUILD=$("$RESOLVER" --default "false" dossier.engagement.allowedActions.runBuild 2>/dev/null)
  NETWORK=$("$RESOLVER"   --default "false" dossier.engagement.allowedActions.networkAccess 2>/dev/null)
  RUN_SECURITY_SCAN=$("$RESOLVER" --default "false" dossier.engagement.allowedActions.runSecurityScan 2>/dev/null)
  RUN_CODE_QUALITY_SCAN=$("$RESOLVER" --default "false" dossier.engagement.allowedActions.runCodeQualityScan 2>/dev/null)
fi

[ -f "$OUTPUT_ROOT/00-control/.scope.json" ] || exit 0

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
WRAPPER='(^|[;&|(]|[[:space:]])[[:space:]]*([A-Za-z0-9_.-]*/)*(bash|sh|zsh|dash|ksh|env|command|exec|eval|xargs|nohup|setsid|stdbuf|script|time|timeout|nice|ionice|sudo|doas|su)([[:space:]]|$)'

# Known limitation, not fixed here (issue synaptiai/synapti-marketplace#143):
# a command-embedded indirection that never spells one of the WRAPPER tokens
# as its own word still bypasses the boundary anchor — `find . -exec curl
# https://evil {} \;` and `xargs -I{} curl {}` are the confirmed cases:
# `-exec`/`-I{}` are glued to a flag, not a standalone token, so neither
# WRAPPER nor the strict BOUND anchor ever fires for the command inside
# them. This does not widen the token list further (see
# [[feedback_matcher_narrowing_vs_grammar_parsing]] — the WRAPPER list has
# already been narrowed/widened several times and each round just moves the
# hole); a real fix needs to parse the actual shell grammar rather than
# pattern-match tokens, tracked separately. Low real-world exposure: this
# hook is a local/interactive backstop only — the CI refresh job's own
# --allowedTools allowlist doesn't include `find`, `xargs`, or a bare shell
# at all, so the automated pipeline has no reach here regardless.
SCAN="$COMMAND"
BOUND_ACTIVE="$BOUND"
if printf '%s' "$COMMAND" | grep -qE "$WRAPPER"; then
  # Quotes and command-substitution openers stop hiding a boundary, and every
  # whitespace run becomes one.
  SCAN=$(printf '%s' "$COMMAND" | sed -E -e 's,["'"'"'`],;,g' -e 's,\$\(,;,g')
  BOUND_ACTIVE='(^|[;&|(]|[[:space:]])[[:space:]]*([A-Za-z0-9_.-]*/)*'
fi

# Every check below tests $SCAN with $BOUND_ACTIVE, which are $COMMAND and the
# strict anchor unless a wrapper was found.

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
