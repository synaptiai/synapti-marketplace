# Tests for the inline plugin-root resolver used by command !-bash blocks.
#
# Contract (see references/plugin-root-resolution.md): the inline resolver
# yields the flow plugin root, probing in order — $CLAUDE_PLUGIN_ROOT, in-repo
# plugins/flow, highest-semver marketplace cache install, marketplaces checkout
# — and yields empty when none has an executable bin/cascade-resolve.sh.
#
# The resolver is extracted from the reference doc (the single source of truth)
# so this test fails if the documented form drifts from a working resolver.

CLEANUP_PATHS=()
_clean() { local p; for p in "${CLEANUP_PATHS[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _clean EXIT

DOC="$REPO_ROOT/plugins/flow/references/plugin-root-resolution.md"

# Extract the canonical inline form: "$(...)/bin/cascade-resolve.sh"
RLINE=$(grep -m1 '^"\$(__fr=' "$DOC" 2>/dev/null)
RESOLVER=${RLINE#\"}
RESOLVER=${RESOLVER%/bin/cascade-resolve.sh\"}

_flow_test_begin "resolver expression is extractable from the reference doc"
if [ -n "$RESOLVER" ] && [ "$RESOLVER" != "$RLINE" ]; then
  _flow_assert_pass "extracted \$(...) root expression"
else
  _flow_assert_fail "could not extract resolver from $DOC"
fi

# Helper: run the extracted resolver under a controlled cwd + HOME + env.
# Usage: _resolve <cwd> <home> <cpr-or-empty>
_resolve() {
  local cwd="$1" home="$2" cpr="$3"
  (
    cd "$cwd" || exit 1
    export HOME="$home"
    if [ -n "$cpr" ]; then export CLAUDE_PLUGIN_ROOT="$cpr"; else unset CLAUDE_PLUGIN_ROOT; fi
    eval "printf '%s' $RESOLVER"
  )
}

# Make an executable stub bin/cascade-resolve.sh under <dir>.
_stub_root() {
  mkdir -p "$1/bin"
  printf '#!/bin/sh\nexit 0\n' > "$1/bin/cascade-resolve.sh"
  chmod +x "$1/bin/cascade-resolve.sh"
}

BASE=$(mktemp -d -t plugin-root.tests.XXXXXX)
CLEANUP_PATHS+=("$BASE")

# Scenario 1: CLAUDE_PLUGIN_ROOT set to a valid root → wins outright.
_flow_test_begin "env CLAUDE_PLUGIN_ROOT wins when it has bin/cascade-resolve.sh"
ENVROOT="$BASE/envroot"; _stub_root "$ENVROOT"
CLEAN="$BASE/cwd-empty-1"; mkdir -p "$CLEAN"
ROOT=$(_resolve "$CLEAN" "$BASE/home-empty" "$ENVROOT")
assert_equal "$ENVROOT" "$ROOT" "env root selected"

# Scenario 2: env unset, in-repo plugins/flow present (cwd-relative) → wins.
_flow_test_begin "in-repo plugins/flow wins when env unset"
INREPO="$BASE/repo"; mkdir -p "$INREPO"; _stub_root "$INREPO/plugins/flow"
ROOT=$(_resolve "$INREPO" "$BASE/home-empty" "")
assert_equal "plugins/flow" "$ROOT" "in-repo relative path selected"

# Scenario 3: env unset, no in-repo, marketplace cache has 2.4.0 + 3.1.0 →
# highest semver wins.
_flow_test_begin "highest-semver marketplace cache install wins"
H3="$BASE/home-cache"
_stub_root "$H3/.claude/plugins/cache/synapti-marketplace/flow/2.4.0"
_stub_root "$H3/.claude/plugins/cache/synapti-marketplace/flow/3.1.0"
_stub_root "$H3/.claude/plugins/cache/synapti-marketplace/flow/2.10.0"
CLEAN3="$BASE/cwd-empty-3"; mkdir -p "$CLEAN3"
ROOT=$(_resolve "$CLEAN3" "$H3" "")
assert_equal "$H3/.claude/plugins/cache/synapti-marketplace/flow/3.1.0" "$ROOT" "newest cache version selected (3.1.0 > 2.10.0 > 2.4.0)"

# Scenario 4: env unset, no in-repo, no cache, marketplaces checkout present.
_flow_test_begin "marketplaces checkout is the last-resort fallback"
H4="$BASE/home-mkt"
_stub_root "$H4/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"
CLEAN4="$BASE/cwd-empty-4"; mkdir -p "$CLEAN4"
ROOT=$(_resolve "$CLEAN4" "$H4" "")
assert_equal "$H4/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow" "$ROOT" "marketplaces path selected"

# Scenario 5: nothing resolvable → empty (drives the caller's loud-fail guard).
_flow_test_begin "no candidate → empty result (loud-fail contract)"
CLEAN5="$BASE/cwd-empty-5"; mkdir -p "$CLEAN5"
ROOT=$(_resolve "$CLEAN5" "$BASE/home-empty" "")
assert_equal "" "$ROOT" "empty when no root has bin/cascade-resolve.sh"
# And the helper path a caller builds is non-executable → guard fires.
_flow_test_begin "empty root yields a non-executable helper path"
if [ ! -x "$ROOT/bin/cascade-resolve.sh" ]; then
  _flow_assert_pass "/bin/cascade-resolve.sh is not executable when root empty"
else
  _flow_assert_fail "unexpectedly executable"
fi

# Scenario 6: env set but INVALID (no bin) falls through to other candidates.
_flow_test_begin "invalid env root falls through to cache"
H6="$BASE/home-cache6"
_stub_root "$H6/.claude/plugins/cache/synapti-marketplace/flow/3.1.0"
CLEAN6="$BASE/cwd-empty-6"; mkdir -p "$CLEAN6"
ROOT=$(_resolve "$CLEAN6" "$H6" "$BASE/does-not-exist")
assert_equal "$H6/.claude/plugins/cache/synapti-marketplace/flow/3.1.0" "$ROOT" "fell through invalid env to cache"
