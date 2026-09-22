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
# Two forms share the $(__fr= opening: the author-context form and the
# install-preferring one the two pull-request commands use, which is the same
# text with the working-directory-relative candidate moved last. Both come from
# the reference doc; the assertion is that the embedded set is exactly those
# two and nothing else.
PREF_LINE=$(grep -m1 '^"\$(__fr=.*plugins/flow; }' "$DOC")
PREF_FORM=${PREF_LINE#\"}
PREF_FORM=${PREF_FORM%/bin/cascade-resolve.sh\"}
UNIQ=$(grep -rhoE '\$[(]__fr=.*"\$__fr"[)]' \
  "$REPO_ROOT/plugins/flow/commands" "$REPO_ROOT/plugins/flow/agents" \
  "$REPO_ROOT/plugins/flow/references" 2>/dev/null | sort -u)
NFORMS=$(printf '%s\n' "$UNIQ" | grep -c .)
assert_equal "2" "$NFORMS" "exactly two unique __fr resolver forms across all embedded sites"
EXPECTED_TWO=$(printf '%s\n%s\n' "$RESOLVER" "$PREF_FORM" | sort -u)
assert_equal "$EXPECTED_TWO" "$UNIQ" "both embedded forms are byte-identical to the reference-doc ones"

# Placement: the two commands that act on someone else's branch use the
# install-preferring form in every ! fence; no other command may use it.
_flow_test_begin "the install-preferring form is used where a pull request's tree may be present"
# -F: the form is full of regex metacharacters, and as a pattern it matches
# nothing, which reads as "no file carries it".
PREF_FILES=$(grep -rlF -- "$PREF_FORM" "$REPO_ROOT/plugins/flow/commands" "$REPO_ROOT/plugins/flow/agents" 2>/dev/null | sed 's#.*/##' | sort -u | tr '\n' ' ')
assert_equal "address.md review.md " "$PREF_FILES" \
  "only /flow:review and /flow:address carry it"
assert_equal "0" "$(grep -cF -- "$RESOLVER" "$REPO_ROOT/plugins/flow/commands/review.md" || true)" \
  "review.md has no author-context resolver left"
assert_equal "0" "$(grep -cF -- "$RESOLVER" "$REPO_ROOT/plugins/flow/commands/address.md" || true)" \
  "and neither has address.md"

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
  bash -c "printf '%s' \"$SKIP_FORM\"" )
assert_equal "plugins/flow" "$AUTHOR_PICK" "the author-context form takes the in-repo checkout, which is what lets flow run from one"
assert_equal "$SKIPHOME_P/.claude/plugins/cache/synapti-marketplace/flow/9.9.9" "$SKIP_PICK" \
  "the post-checkout form skips it and takes the installed copy"

# The post-checkout form re-implements the WHOLE candidate list, not only the
# skip. With one cache version and no marketplaces entry stocked, a mutant that
# picks the oldest install, drops the `break`, or deletes the last-resort
# candidate produces identical output, so none of them was pinned.
# The substitution is QUOTED here, the way every real caller writes it
# ("$(...)/bin/cascade-resolve.sh"). Evaluating it unquoted word-splits a
# multi-line result and runs the extra lines as commands, so a resolver that
# returned three candidates still printed one and a missing `break` survived
# every assertion.
_flow_test_begin "the post-checkout form picks the highest installed version"
MULTI="$BASE/multi"; mkdir -p "$MULTI"
( cd "$MULTI" && git init -q . >/dev/null 2>&1 )
MULTIHOME="$BASE/multihome"
_stub_root "$MULTIHOME/.claude/plugins/cache/synapti-marketplace/flow/2.4.0"
_stub_root "$MULTIHOME/.claude/plugins/cache/synapti-marketplace/flow/3.1.0"
_stub_root "$MULTIHOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"
MULTIHOME_P=$(cd "$MULTIHOME" && pwd -P)
MULTI_PICK=$( cd "$MULTI" && env -u CLAUDE_PLUGIN_ROOT HOME="$MULTIHOME" \
  bash -c "printf '%s' \"$SKIP_FORM\"" )
# assert_equal on the WHOLE value, not a substring: a missing `break` makes the
# resolver return every candidate, and a contains-check would still pass.
assert_equal "$MULTIHOME_P/.claude/plugins/cache/synapti-marketplace/flow/3.1.0" "$MULTI_PICK" \
  "the newest cache install wins, and exactly one line is returned"

_flow_test_begin "the post-checkout form falls back to the marketplaces checkout"
ONLYMKT="$BASE/onlymkt"
_stub_root "$ONLYMKT/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"
ONLYMKT_P=$(cd "$ONLYMKT" && pwd -P)
MKT_PICK=$( cd "$MULTI" && env -u CLAUDE_PLUGIN_ROOT HOME="$ONLYMKT" \
  bash -c "printf '%s' \"$SKIP_FORM\"" )
assert_equal "$ONLYMKT_P/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow" "$MKT_PICK" \
  "with no cache install the last-resort candidate is used"

# The working tree is unreachable by construction, not by a check that has to
# succeed. The form carries no working-directory-relative candidate at all: the
# conditional skip rested on `git rev-parse --show-toplevel` reporting the root,
# and it does not always - on the Linux runner a work tree that does not exist
# makes rev-parse FAIL rather than report, $__t is empty, nothing is skipped and
# the branch's own copy wins. macOS printed the path and the same check passed
# there, which is how this shipped green locally and red on CI.
_flow_test_begin "the post-checkout form carries no working-directory-relative candidate"
# The candidate as it is actually written in each form: the author form lists
# it after a single-quoted printf format, the post-checkout form after the
# CLAUDE_PLUGIN_ROOT expansion. Matching the wrong quoting made this assertion
# pass with the candidate present.
assert_not_contains " plugins/flow;" "$SKIP_FORM" "no bare plugins/flow candidate in the list"
assert_contains " plugins/flow;" "$RESOLVER" \
  "while the author-context form still has one, which is the difference between them"

# Whatever git says about the root, nothing inside the working tree may be
# selected. Driven with a work tree that does not exist, which makes rev-parse
# report an unenterable path on one platform and fail outright on the other:
# the assertion is the property, not either platform's output.
_flow_test_begin "a root git cannot report still never yields the working tree"
UNREADABLE="$BASE/unreadable"; mkdir -p "$UNREADABLE"
( cd "$UNREADABLE" && git init -q . >/dev/null 2>&1 )
_stub_root "$UNREADABLE/plugins/flow"
UNREADABLE_P=$(cd "$UNREADABLE" && pwd -P)
UNREADABLE_PICK=$( cd "$UNREADABLE" && env -u CLAUDE_PLUGIN_ROOT HOME="$MULTIHOME" \
  GIT_DIR="$UNREADABLE/.git" GIT_WORK_TREE="$BASE/no-such-tree" \
  bash -c "printf '%s' \"$SKIP_FORM\"" )
case "${UNREADABLE_PICK:-}/" in
  "$UNREADABLE_P"/*) _flow_assert_fail "selected the working tree's own copy: $UNREADABLE_PICK" ;;
  *) _flow_assert_pass "selected ${UNREADABLE_PICK:-nothing}, which is outside the working tree" ;;
esac

# The same property with git removed entirely, which is the condition the Linux
# runner reached by another route: $__t empty, so the skip does nothing.
_flow_test_begin "with no git at all the working tree is still unreachable"
# A git that cannot answer, rather than an empty PATH: the resolver still needs
# ls and sort, and both runners ship git in /usr/bin, so dropping a directory
# from PATH left the real git reachable and the fixture proved nothing.
NOGIT="$BASE/nogitbin"; mkdir -p "$NOGIT"
printf '#!/bin/sh\nexit 1\n' > "$NOGIT/git"
chmod +x "$NOGIT/git"
NOGIT_PICK=$( cd "$UNREADABLE" && env -u CLAUDE_PLUGIN_ROOT HOME="$MULTIHOME" \
  PATH="$NOGIT:$PATH" bash -c "printf '%s' \"$SKIP_FORM\"" )
case "${NOGIT_PICK:-}/" in
  "$UNREADABLE_P"/*) _flow_assert_fail "selected the working tree's own copy: $NOGIT_PICK" ;;
  *) _flow_assert_pass "selected ${NOGIT_PICK:-nothing}, which is outside the working tree" ;;
esac

# The fail-closed sentinel, driven deterministically on both platforms. A git
# stub reports a root that exists nowhere, so rev-parse SUCCEEDS and the cd to
# it fails, which is the only route to __t=/. The fixtures above cannot pin
# this: they assert the pick is outside the working tree, and with the sentinel
# broken the pick is a cache install, which is also outside it - right and
# wrong code give the same verdict. Reverting ${__t%/} to $__t left all 621
# assertions in four suites green.
_flow_test_begin "a root that resolves but cannot be entered selects nothing"
SENTINEL="$BASE/sentinel"; mkdir -p "$SENTINEL"
SENTINEL_GIT="$BASE/sentinelgit"; mkdir -p "$SENTINEL_GIT"
printf '#!/bin/sh\nprintf "%%s\\n" "%s/no-such-root"\n' "$BASE" > "$SENTINEL_GIT/git"
chmod +x "$SENTINEL_GIT/git"
SENTINEL_PICK=$( cd "$SENTINEL" && env -u CLAUDE_PLUGIN_ROOT HOME="$MULTIHOME" \
  PATH="$SENTINEL_GIT:$PATH" bash -c "printf '%s' \"$SKIP_FORM\"" )
# $MULTIHOME holds two cache installs and a marketplaces entry, so a sentinel
# that skips nothing has something to wrongly return.
assert_equal "" "$SENTINEL_PICK" \
  "with the root reported but unenterable, every absolute candidate is skipped"

# And the absolute candidates are still skipped when they point inside a
# repository git CAN report, which is the case the skip exists for.
_flow_test_begin "an absolute candidate inside the repository under review is skipped"
INSIDE="$BASE/insidehome"; mkdir -p "$INSIDE"
( cd "$INSIDE" && git init -q . >/dev/null 2>&1 )
_stub_root "$INSIDE/.claude/plugins/cache/synapti-marketplace/flow/9.9.9"
INSIDE_PICK=$( cd "$INSIDE" && env -u CLAUDE_PLUGIN_ROOT HOME="$INSIDE" \
  bash -c "printf '%s' \"$SKIP_FORM\"" )
assert_equal "" "$INSIDE_PICK" "a cache install sitting inside the repository under review is not used"

# Outside a git repository the post-checkout form must skip nothing. `cd ""`
# returns 0 on bash 3.2 and leaves the working directory alone, so running the
# cd unconditionally made every candidate below the working directory look
# in-repository and refused an install sitting above it.
_flow_test_begin "outside a repository the post-checkout form skips nothing"
# The working directory must be an ANCESTOR of the install for this to
# discriminate: with the install in a sibling directory the faulty form finds it
# anyway and the assertion passes either way. $BASE contains skiphome/ and is
# not a git repository.
NOREPO_PICK=$( cd "$BASE" && env -u CLAUDE_PLUGIN_ROOT HOME="$SKIPHOME" \
  bash -c "printf '%s' \"$SKIP_FORM\"" )
assert_equal "$SKIPHOME_P/.claude/plugins/cache/synapti-marketplace/flow/9.9.9" "$NOREPO_PICK" \
  "the install is found, not refused for sitting under the working directory"
