#!/usr/bin/env bash
# dossier-validate-patch.sh — the prompt-injection backstop.
#
# This script is what makes a fully-suborned agent's output worthless: the agent
# can produce a patch, and this refuses it if anything escapes the write
# allowlist or looks like a credential. It had no functional test at all, which
# is the wrong shape for a control whose entire job is to say no — every
# assertion here is a rejection case, because a control that only ever gets
# handed compliant input has never been shown to reject anything.

_dossier_test_begin "validate-patch"

BIN="plugins/dossier/bin"
VP="$BIN/dossier-validate-patch.sh"
REPO=$(pwd)

WORK=$(mktemp -d) || { _dossier_assert_fail "cannot create temp dir"; _dossier_test_summary; return 0 2>/dev/null || exit 0; }

# A real repository, because the script refuses to run outside one.
(
  cd "$WORK" || exit 1
  git init -q .
  git config user.email t@example.invalid
  git config user.name  T
  mkdir -p docs/dossier/00-control
  printf '# seed\n' > docs/dossier/00-control/documentation-index.md
  git add -A && git commit -qm seed
) >/dev/null 2>&1

# The summary and patch artifacts live outside the repository under test: the
# staging mode reads `git status`, so an artifact written inside the worktree
# would itself register as an allowlist escape and the test would be measuring
# its own scaffolding.
ART=$(mktemp -d) || ART="$WORK.artifacts"
mkdir -p "$ART" 2>/dev/null

run_vp() { # args… -> sets VP_RC / VP_OUT / VP_SUMMARY
  : >"$ART/summary.md"
  VP_OUT=$(cd "$WORK" && CLAUDE_PLUGIN_ROOT="$REPO/plugins/dossier" \
             "$REPO/$VP" --summary "$ART/summary.md" "$@" 2>&1)
  VP_RC=$?
  VP_SUMMARY=$(cat "$ART/summary.md" 2>/dev/null)
}

# --- The compliant case must pass, or every rejection below proves nothing ----
printf '\nadded line\n' >> "$WORK/docs/dossier/00-control/documentation-index.md"
run_vp --out "$ART/clean.patch" --allowlist 'docs/dossier/**'
assert_equal "0" "$VP_RC" "a patch confined to the allowlist is accepted"
if [ -s "$ART/clean.patch" ]; then
  _dossier_assert_pass "the accepted patch was written"
else
  _dossier_assert_fail "no patch written for a compliant change"
fi
(cd "$WORK" && git checkout -q -- . && git clean -qfd) >/dev/null 2>&1

# --- Allowlist escape ---------------------------------------------------------
mkdir -p "$WORK/src"
printf 'x\n' > "$WORK/src/app.ts"
run_vp --out "$ART/escape.patch" --allowlist 'docs/dossier/**'
if [ "$VP_RC" -ne 0 ]; then
  _dossier_assert_pass "a working-tree file outside the allowlist is refused (exit $VP_RC)"
else
  _dossier_assert_fail "an allowlist escape was accepted"
fi
assert_contains "src/app.ts" "$VP_SUMMARY" "the refusal names the escaping path"
if [ -s "$ART/escape.patch" ]; then
  _dossier_assert_fail "a patch was written despite the refusal"
else
  _dossier_assert_pass "no patch is written when the allowlist is escaped"
fi
(cd "$WORK" && git clean -qfd) >/dev/null 2>&1

# --- Symlink escape -----------------------------------------------------------
# The path is inside the allowlist; the content is a pointer out of it. Path
# checking alone cannot see this, which is why the mode is refused outright.
(cd "$WORK" && ln -s ../../../etc/passwd docs/dossier/00-control/leak.md) >/dev/null 2>&1
run_vp --out "$ART/symlink.patch" --allowlist 'docs/dossier/**'
if [ "$VP_RC" -ne 0 ]; then
  _dossier_assert_pass "a symlink inside the allowlist is refused (exit $VP_RC)"
else
  _dossier_assert_fail "a symlink inside the allowlist was accepted"
fi
(cd "$WORK" && git clean -qfd) >/dev/null 2>&1

# --- Verification mode: allowlist escape in a supplied patch ------------------
# The publish job must not trust the refresh job's verdict, only its bytes.
cat > "$ART/evil.patch" <<'PATCH'
diff --git a/.github/workflows/evil.yml b/.github/workflows/evil.yml
new file mode 100644
--- /dev/null
+++ b/.github/workflows/evil.yml
@@ -0,0 +1 @@
+on: push
PATCH
run_vp --verify-patch "$ART/evil.patch" --allowlist 'docs/dossier/**'
if [ "$VP_RC" -ne 0 ]; then
  _dossier_assert_pass "verify mode refuses a patch touching a path outside the allowlist"
else
  _dossier_assert_fail "verify mode accepted an allowlist escape"
fi
assert_contains ".github/workflows/evil.yml" "$VP_SUMMARY" "verify mode names the escaping path"

# --- Verification mode: traversal spelled inside the allowlist ----------------
cat > "$ART/traverse.patch" <<'PATCH'
diff --git a/docs/dossier/../../.env b/docs/dossier/../../.env
new file mode 100644
--- /dev/null
+++ b/docs/dossier/../../.env
@@ -0,0 +1 @@
+SECRET=1
PATCH
run_vp --verify-patch "$ART/traverse.patch" --allowlist 'docs/dossier/**'
if [ "$VP_RC" -ne 0 ]; then
  _dossier_assert_pass "verify mode refuses a traversal path"
else
  _dossier_assert_fail "verify mode accepted a traversal path"
fi

# --- Verification mode: symlink mode -----------------------------------------
cat > "$ART/symlink-mode.patch" <<'PATCH'
diff --git a/docs/dossier/00-control/link.md b/docs/dossier/00-control/link.md
new file mode 120000
--- /dev/null
+++ b/docs/dossier/00-control/link.md
@@ -0,0 +1 @@
+../../../.env
\ No newline at end of file
PATCH
run_vp --verify-patch "$ART/symlink-mode.patch" --allowlist 'docs/dossier/**'
if [ "$VP_RC" -ne 0 ]; then
  _dossier_assert_pass "verify mode refuses mode 120000 inside the allowlist"
else
  _dossier_assert_fail "verify mode accepted a symlink whose path was allowlisted"
fi

# --- Verification mode: credential in an allowlisted hunk ---------------------
cat > "$ART/secret.patch" <<'PATCH'
diff --git a/docs/dossier/00-control/documentation-index.md b/docs/dossier/00-control/documentation-index.md
--- a/docs/dossier/00-control/documentation-index.md
+++ b/docs/dossier/00-control/documentation-index.md
@@ -1 +1,2 @@
 # seed
+key sk-ant-abcdefgh12345678
PATCH
run_vp --verify-patch "$ART/secret.patch" --allowlist 'docs/dossier/**'
if [ "$VP_RC" -ne 0 ]; then
  _dossier_assert_pass "verify mode refuses a credential in an allowlisted path"
else
  _dossier_assert_fail "verify mode accepted a credential"
fi
# Echoing the match would copy the leak into the CI log the finding is bound for.
assert_not_contains "sk-ant-abcdefgh12345678" "$VP_OUT" "the matched credential is never echoed to stderr"
assert_not_contains "sk-ant-abcdefgh12345678" "$VP_SUMMARY" "the matched credential is never echoed to the job summary"

# --- An empty allowlist must not mean "everything" ---------------------------
run_vp --verify-patch "$ART/secret.patch" --allowlist ''
if [ "$VP_RC" -ne 0 ]; then
  _dossier_assert_pass "an empty allowlist is refused rather than treated as open"
else
  _dossier_assert_fail "an empty allowlist permitted the patch"
fi

rm -rf "$WORK" "$ART" 2>/dev/null

_dossier_test_summary
