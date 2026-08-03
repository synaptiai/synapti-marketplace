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

# Fail closed rather than let bash's own glob-based parameter expansion pay a
# super-linear cost: ansi_c_decode's span-boundary search (`${rest%%\'*}`,
# re-scanning a shrinking-but-still-large remainder every loop iteration) and
# the backslash-to-placeholder pass further below (a single global
# substitution over the whole command) are both quadratic in bash for large
# operands -- confirmed empirically: a 100KB command containing ANSI-C
# content took ~20s to normalize here, ~200KB took over a minute, and the
# same blowup reproduces from backslash volume alone with no `$'...'`
# involved at all. A command this large is never a legitimate interactive
# Bash-tool call this hook needs to support, so refusing it outright costs
# nothing real while closing an easy, no-malice-required hang -- and this
# hook blocks the whole Bash tool call while it runs, not just itself.
COMMAND_LEN=${#COMMAND}
if [ "$COMMAND_LEN" -gt 8192 ]; then
  echo "BLOCKED: dossier cannot safely enforce its action ceiling on a command this large (${COMMAND_LEN} bytes, limit 8192) -- bash's own quote/escape normalization is super-linear at this size. Split the command into smaller steps." >&2
  exit 2
fi

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
# Second limitation, issue #152 (closed here): quoting or backslash-escaping a
# denied word defeats BOUND/WRAPPER entirely, for ANY token listed anywhere in
# this file, not just find/xargs — confirmed live for every one of these,
# including a real curl invocation in each case:
#   "curl" https://evil                  (whole word quoted)
#   \curl https://evil                   (leading backslash)
#   c\url https://evil                   (mid-word backslash split)
#   cu''rl https://evil / cu"r"l https://evil   (adjacent quote fragments —
#                                                bash joins these into one word)
#   cur\<a real newline>l https://evil   (backslash-newline line continuation)
#   $'\143url' https://evil              (bash's own ANSI-C octal/hex quoting —
#   $'\x63url' https://evil               \nnn and \xHH are both decoded)
# The last two were found investigating this issue, not in the original
# report: this file's SCAN/BOUND_ACTIVE quote-stripping only ran after a
# WRAPPER match, so a denied word spelled with a leading quote/backslash never
# triggered it, and every variant above reduces to a plain, unrecognizable
# spelling of the same word bash actually executes. What is closed above is
# specifically bash's quote/backslash/ANSI-C *removal* — not bash's own
# *expansion* mechanisms; see the third limitation below for that residual.
#
# Third limitation, issue #160 (not fixed here, found while reviewing this
# PR): brace expansion (`cu{rl,} https://evil`), parameter-expansion defaults
# (`${x:-curl} https://evil`), and command substitution (`$(echo curl)
# https://evil`) all defeat DEQUOTED just as completely — confirmed live,
# real curl invoked, permitted (exit 0) in every case, on both this branch
# and pre-#152 main (a pre-existing gap, not a regression here). DEQUOTED
# only reverses quote/backslash/ANSI-C removal; it never performs actual
# bash expansion, so none of these three are touched by it. Deliberately not
# folded into #152's fix: resolving what a command substitution evaluates to
# requires either executing attacker-controlled shell content inside this
# hook (worse than the gap it would close) or full static shell-expansion
# analysis (not tractable in general). That is a different-shaped problem
# than DEQUOTED solves and needs its own design, not a rushed extension here.
#
# DEQUOTED undoes exactly what bash's own quote/escape/ANSI-C removal would
# do, so the anchor below tests the word bash actually runs rather than its
# disguised spelling. Order matters:
#
# 1. $'...' content is decoded first — it has its own escape grammar
#    (octal/hex), independent of ordinary quoting, and must not be treated as
#    a plain literal string by step 4.
#
# 2. A backslash immediately followed by a real newline is removed as a PAIR
#    before any lone backslash is stripped. Stripping the backslash alone
#    first leaves the newline behind as a still-valid whitespace separator,
#    silently reopening the exact bypass this closes.
#
# 3. Remaining lone backslashes (the escape character) are deleted, keeping
#    the character they protected.
#
# 4. Quote and backtick characters are deleted outright, not turned into a
#    boundary/separator the way the WRAPPER-triggered widening below does.
#    Bash's own quote removal deletes the marks and leaves adjacent fragments
#    joined into one word (cu''rl -> curl); turning them into a separator
#    would instead split the word into pieces that never reassemble.
#
# Done in bash parameter expansion (not sed/tr) for steps 2-4: sed and grep
# are line-oriented by default, which would silently ignore the
# backslash-newline case — the join needs to see the newline and the
# character after it as one operation, not two independent lines — and this
# also sidesteps the GNU/BSD sed divergence this suite has hit before. The
# ANSI-C helper below still shells out to sed/printf for its own narrow,
# already-isolated substring (the content between $' and '), where that
# divergence risk does not apply.
#
# Known, accepted trade-off: deleting a quote mark can bring a boundary
# character and a denied word directly together when nothing else separated
# them — `echo hi;"curl" https://evil` has a boundary-char/keyword gap of
# exactly one quote mark, so deleting it produces `;curl`, indistinguishable
# from a real `;curl ...` invocation. (A quote mark elsewhere in the same
# command, with other text between it and the keyword, is not this case: the
# keyword's own preceding character is unchanged either way, which is why an
# ordinary `"..."` argument containing a stray `|` or `(` earlier in a prose
# string is not a NEW effect of this fix — the strict anchor already reads
# raw command text without understanding quoting at all.) This is the same
# direction of trade this file already accepts for the WRAPPER scan
# (`timeout 5 grep -r "npm test" docs/` is refused too): over-block, name the
# match, let a human drop the false trigger and re-run. See hooks.test.sh for
# the assertion that proves this is deliberate, not a surprise.
#
# Real-world exposure stays low regardless of the remaining find/xargs-shaped
# limitation noted above — this hook is a local/interactive backstop only;
# the CI refresh job's own --allowedTools allowlist doesn't include `find`,
# `xargs`, `parallel`, `awk`, `perl`, or a bare shell at all, so the automated
# pipeline has no reach here.
ansi_c_decode() { # $1: command string -> stdout: with every $'...' span decoded
  # Bash's $'...' decodes \nnn (octal), \xHH (hex), and the usual \n/\t/...
  # single-letter escapes. printf '%b' understands the same set, EXCEPT its
  # octal form requires the leading zero bash's own \nnn does not (\143 vs
  # \0143) — normalized below before handing the body to printf.
  local s="$1" out="" pre body rest norm
  while [[ "$s" == *\$\'*\'* ]]; do
    pre="${s%%\$\'*}"
    rest="${s#*\$\'}"
    body="${rest%%\'*}"
    rest="${rest#"$body"\'}"
    norm=$(printf '%s' "$body" | sed -E 's/\\([0-7]{1,3})/\\0\1/g')
    out+="$pre$(printf '%b' "$norm")"
    s="$rest"
  done
  printf '%s' "$out$s"
}

# ansi_c_decode forks a sed+printf subprocess pair for every $'...' occurrence
# it finds. The byte-length guard above bounds the quadratic glob-matching
# cost, but not this one: an attacker can still pack many tiny $'x' spans
# into that same byte budget, and fork/exec overhead is paid per span
# regardless of how small each one is -- confirmed live, ~2000 minimal spans
# in an 8KB command took over 10 seconds from subprocess overhead alone, with
# no `$'...'`-external content large enough to trip the length guard. A
# legitimate interactive command needs at most a handful of ANSI-C-quoted
# segments, so this is capped separately from the overall length.
#
# Counted with `grep -oF`, not bash's own `${var//pattern/replacement}`:
# bash's global substitution has the exact same super-linear-for-many-matches
# behavior this guard exists to bound -- confirmed live, counting via pure
# bash parameter expansion on the same 2000-span input took ~7 seconds by
# itself, which would have defeated the point of counting fast before
# deciding whether to run the expensive decode. `-F` matches the 2-character
# literal `$'` identically on GNU and BSD, so this doesn't reopen the
# GNU/BSD divergence risk the newline-join logic above avoids sed/grep for.
ANSIC_SPAN_COUNT=$(printf '%s' "$COMMAND" | grep -oF "\$'" | wc -l | tr -d '[:space:]')
if [ "$ANSIC_SPAN_COUNT" -gt 64 ]; then
  echo "BLOCKED: dossier cannot safely enforce its action ceiling on a command with this many \$'...' segments (${ANSIC_SPAN_COUNT}, limit 64) -- each one forks a subprocess to decode." >&2
  exit 2
fi

COMMAND_ANSIC=$(ansi_c_decode "$COMMAND")

# The placeholder byte chosen below (0x01) is assumed to never legitimately
# appear in a Bash-tool command string -- but that assumption is checked
# here, not trusted, because ansi_c_decode above can manufacture that exact
# byte itself from a plain, valid `$'\001'` (or `\x01`) escape in the
# original command. An already-present 0x01 byte at this point is
# indistinguishable from a backslash this script marks itself a few lines
# down: if it happens to sit immediately before a real newline, the join
# step below deletes both, splicing two separate statements together with no
# boundary character left for BOUND/BOUND_ACTIVE to anchor on. Confirmed
# live: `echo done$'\001'` followed by a real `curl ...` on the next line was
# permitted outright before this guard existed. Failing closed costs
# nothing real -- a raw 0x01 byte is not a legitimate case this hook needs
# to support -- and covers both this manufactured case and a literal 0x01
# typed directly into the command, since ansi_c_decode passes untouched
# bytes through unchanged.
case "$COMMAND_ANSIC" in
  *$'\x01'*)
    echo "BLOCKED: dossier cannot safely enforce its action ceiling on a command containing a raw 0x01 byte -- that byte is reserved for this script's own internal quote/escape normalization." >&2
    exit 2
    ;;
esac

# bash 3.2 (macOS's system /bin/bash) cannot match a pattern-substitution
# pattern that is itself a literal backslash followed by a real newline: the
# 2-character pattern's own length checks out, but the replacement silently
# never fires -- confirmed empirically, and NOT reproducible under zsh or
# newer bash, which both do fire. A backslash is a glob escape character
# inside `${var//pattern/}`, and bash 3.2 mishandles escaping a newline
# specifically. Every backslash is swapped for a placeholder byte first (one
# that never legitimately appears in a Bash-tool command string) so the
# join pattern below is placeholder+newline, never backslash+newline; the
# remaining lone placeholders are then deleted, which is step 3 (the escape
# character removed, the character it protected kept) applied via the same
# placeholder rather than a second backslash-pattern substitution.
DEQUOTE_PLACEHOLDER=$'\x01'
COMMAND_MARKED="${COMMAND_ANSIC//\\/$DEQUOTE_PLACEHOLDER}"
COMMAND_JOINED="${COMMAND_MARKED//$DEQUOTE_PLACEHOLDER$'\n'/}"
DEQUOTED="${COMMAND_JOINED//$DEQUOTE_PLACEHOLDER/}"
DEQUOTED="${DEQUOTED//\'/}"
DEQUOTED="${DEQUOTED//\"/}"
DEQUOTED="${DEQUOTED//\`/}"

SCAN="$DEQUOTED"
BOUND_ACTIVE="$BOUND"
if printf '%s' "$DEQUOTED" | grep -qE "$WRAPPER" || printf '%s' "$DEQUOTED" | grep -qE "$FIND_EXEC"; then
  BOUND_ACTIVE='(^|[;&|(]|[[:space:]])[[:space:]]*([A-Za-z0-9_.-]*/)*'
fi

# Every check below tests $SCAN with $BOUND_ACTIVE: $SCAN is always DEQUOTED
# (quote/backslash/ANSI-C removed, so a disguised command-start is restored to
# its plain spelling); $BOUND_ACTIVE is the strict anchor unless a wrapper (or
# find's own exec-family primaries) was found in DEQUOTED, in which case
# whitespace itself becomes a boundary too.

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
