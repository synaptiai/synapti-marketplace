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

# Scenario 7 (drift guard): every resolver embedded in the command/agent files
# must be byte-identical to the canonical form in the reference doc. Catches a
# future edit that hand-tweaks one site out of sync.
_flow_test_begin "all embedded resolver sites match the canonical doc form (no drift)"
# Anchored on the expression's stable ends, not on the print builtin inside it:
# a pattern pinned to one builtin stops matching the moment the canonical form
# changes, and an empty extraction is only caught because the count below is
# asserted to be exactly one.
UNIQ=$(grep -rhoE '\$[(]__fr=.*"\$__fr"[)]' \
  "$REPO_ROOT/plugins/flow/commands" "$REPO_ROOT/plugins/flow/agents" \
  "$REPO_ROOT/plugins/flow/references" 2>/dev/null | sort -u)
NFORMS=$(printf '%s\n' "$UNIQ" | grep -c .)
assert_equal "1" "$NFORMS" "exactly one unique resolver form across all embedded sites"
assert_equal "$RESOLVER" "$UNIQ" "embedded resolver is byte-identical to the reference-doc canonical form"

# The reference doc defines a SECOND canonical form for sites that run after a
# `gh pr checkout`, where the working tree belongs to the pull request. The
# assertions above see only the author-context form, so this file reported
# "exactly one unique resolver form" while thirteen sites carried a second form
# with opposite security semantics and nothing noticed.
SKIP_LINE=$(grep -m1 '^"\$(__t=' "$DOC")
SKIP_FORM=${SKIP_LINE#\"}
SKIP_FORM=${SKIP_FORM%/bin/cascade-resolve.sh\"}

_flow_test_begin "post-checkout resolver form is extractable from the reference doc"
if [ -n "$SKIP_FORM" ] && [ "$SKIP_FORM" != "$SKIP_LINE" ]; then
  _flow_assert_pass "extracted the post-checkout \$(...) root expression"
else
  _flow_assert_fail "could not extract the post-checkout form from $DOC"
fi

_flow_test_begin "all post-checkout sites match the canonical doc form (no drift)"
UNIQ_SKIP=$(grep -rhoE '\$[(]__t=.*done[)]' \
  "$REPO_ROOT/plugins/flow/commands" "$REPO_ROOT/plugins/flow/agents" \
  "$REPO_ROOT/plugins/flow/references" 2>/dev/null | sort -u)
NFORMS_SKIP=$(printf '%s\n' "$UNIQ_SKIP" | grep -c .)
assert_equal "1" "$NFORMS_SKIP" "exactly one unique post-checkout form across all embedded sites"
assert_equal "$SKIP_FORM" "$UNIQ_SKIP" "embedded post-checkout resolver is byte-identical to the reference-doc form"

# The two forms must differ in exactly the way the doc says: the author form
# takes the in-repository candidate, the post-checkout form skips it.
_flow_test_begin "the two forms differ on the in-repository candidate"
SKIPREPO="$BASE/skiprepo"; mkdir -p "$SKIPREPO"; _stub_root "$SKIPREPO/plugins/flow"
( cd "$SKIPREPO" && git init -q . >/dev/null 2>&1 )
SKIPHOME="$BASE/skiphome"; _stub_root "$SKIPHOME/.claude/plugins/cache/synapti-marketplace/flow/9.9.9"
# The post-checkout form compares physical paths and returns one, so the
# expectation is the physical path too — on macOS the temp root is reached
# through a symlink, and comparing the logical spelling would fail for a reason
# that has nothing to do with the resolver.
SKIPHOME_P=$(cd "$SKIPHOME" && pwd -P)
AUTHOR_PICK=$( cd "$SKIPREPO" && env -u CLAUDE_PLUGIN_ROOT HOME="$SKIPHOME" \
  bash -c "eval \"printf '%s' $RESOLVER\"" )
SKIP_PICK=$( cd "$SKIPREPO" && env -u CLAUDE_PLUGIN_ROOT HOME="$SKIPHOME" \
  bash -c "eval \"printf '%s' $SKIP_FORM\"" )
assert_equal "plugins/flow" "$AUTHOR_PICK" "the author-context form takes the in-repo checkout, which is what lets flow run from one"
assert_equal "$SKIPHOME_P/.claude/plugins/cache/synapti-marketplace/flow/9.9.9" "$SKIP_PICK" \
  "the post-checkout form skips it and takes the installed copy"

# Outside a git repository the post-checkout form must skip nothing. `cd ""`
# returns 0 on bash 3.2 and leaves the working directory alone, so running the
# cd unconditionally made every candidate below the working directory look
# in-repository and refused an install sitting above it.
_flow_test_begin "outside a repository the post-checkout form skips nothing"
NOREPO="$BASE/norepo"; mkdir -p "$NOREPO"
NOREPO_PICK=$( cd "$NOREPO" && env -u CLAUDE_PLUGIN_ROOT HOME="$SKIPHOME" \
  bash -c "eval \"printf '%s' $SKIP_FORM\"" )
assert_equal "$SKIPHOME_P/.claude/plugins/cache/synapti-marketplace/flow/9.9.9" "$NOREPO_PICK" \
  "the install is found, not refused for sitting under the working directory"
