#!/usr/bin/env bash
# dossier-package-check.sh finding codes.
#
# The script documents fifteen finding codes as its contract and only the two
# newest (the diagram-coverage pair) were exercised. A finding code with no test
# is a check nobody has seen fire: it can be deleted, misspelled, or made
# unreachable and the suite stays green.
#
# LEAKED-FIELD matters most. It is the check that stops an internal-only header
# key reaching a `public-v1` document, which is the same disclosure boundary the
# claim scanner and the PreToolUse hook defend — and it was the one of the three
# with no coverage at all.

_dossier_test_begin "package-check-findings"

BIN="plugins/dossier/bin"
PC="$BIN/dossier-package-check.sh"
REPO=$(pwd)

WORK=$(mktemp -d) || { _dossier_assert_fail "cannot create temp dir"; _dossier_test_summary; return 0 2>/dev/null || exit 0; }
PKG="$WORK/docs"

# A scaffolded package is the baseline: every fixture below is one mutation away
# from it, so a finding proves the mutation was detected rather than that the
# fixture was malformed to begin with.
"$BIN/dossier-scaffold.sh" --output-root "$PKG" >/dev/null 2>&1

check() { # -> CK_OUT / CK_RC
  CK_OUT=$("$PC" --output-root "$PKG" 2>&1)
  CK_RC=$?
}

# --- Baseline: a freshly scaffolded package has no structural finding ---------
# Templates ship unfilled, so content findings are expected; the codes below
# must each be ABSENT before their mutation, or the assertion proves nothing.
check
for CODE in MISSING-FILE NO-HEADER BAD-HEADER-KIND LEAKED-FIELD NO-H1 NO-CONTRACT CONTRACT-FILE; do
  assert_not_contains "FINDING $CODE" "$CK_OUT" "scaffolded package is clean of $CODE"
done

expect_code() { # code | file | mutation-description
  check
  if printf '%s' "$CK_OUT" | grep -q "FINDING $1"; then
    _dossier_assert_pass "$3 produces $1"
  else
    _dossier_assert_fail "$3 did not produce $1"
  fi
  if [ "$CK_RC" -eq 0 ]; then
    _dossier_assert_fail "$1 present but the script exited 0"
  else
    _dossier_assert_pass "$1 exits non-zero ($CK_RC)"
  fi
}

TARGET="$PKG/01-project/executive-project-brief.md"
BACKUP="$WORK/brief.orig"
cp "$TARGET" "$BACKUP"
restore() { cp "$BACKUP" "$TARGET"; }

# --- MISSING-FILE ------------------------------------------------------------
MOVED="$WORK/moved.md"
mv "$TARGET" "$MOVED"
expect_code "MISSING-FILE" "$TARGET" "a deleted canonical file"
mv "$MOVED" "$TARGET"

# --- NO-HEADER ---------------------------------------------------------------
printf '# Executive Project Brief\n\nNo frontmatter at all.\n' > "$TARGET"
expect_code "NO-HEADER" "$TARGET" "a file with no frontmatter fence"
restore

# --- BAD-HEADER-KIND ---------------------------------------------------------
python3 - "$TARGET" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
open(p, 'w').write(s.replace('dossier-header: internal-v1', 'dossier-header: bogus-v9', 1))
PY
expect_code "BAD-HEADER-KIND" "$TARGET" "an unrecognised dossier-header value"
restore

# --- NO-H1 -------------------------------------------------------------------
python3 - "$TARGET" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().split('\n')
end = next(i for i, l in enumerate(lines[1:], 1) if l.strip() == '---')
for i in range(end + 1, len(lines)):
    if lines[i].startswith('# '):
        lines[i] = 'Not a heading at all.'
        break
open(p, 'w').write('\n'.join(lines))
PY
expect_code "NO-H1" "$TARGET" "a body whose first line is not an H1"
restore

# --- NO-CONTRACT / CONTRACT-FILE --------------------------------------------
python3 - "$TARGET" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
open(p, 'w').write(re.sub(r'<!-- contract: [^>]*-->',
                          '<!-- contract: references/does-not-exist.md#nope -->', s, count=1))
PY
expect_code "CONTRACT-FILE" "$TARGET" "a contract pointer to a missing file"
restore

# --- LEAKED-FIELD ------------------------------------------------------------
# The disclosure boundary: an internal-only key in a public-v1 header.
PUB="$PKG/06-public/technical-partner-guide.md"
PUB_BACKUP="$WORK/pub.orig"
cp "$PUB" "$PUB_BACKUP"
# `owner` is on the script's internal-only list: it names a person and a
# reporting line, which is exactly the kind of internal detail a partner-facing
# document must not carry.
python3 - "$PUB" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().split('\n')
end = next(i for i, l in enumerate(lines[1:], 1) if l.strip() == '---')
lines.insert(end, 'owner: Internal Platform Team')
open(p, 'w').write('\n'.join(lines))
PY
expect_code "LEAKED-FIELD" "$PUB" "an internal-only key in a public-v1 header"
cp "$PUB_BACKUP" "$PUB"

# Every field the script calls internal-only must actually be refused, or the
# list is longer than the behaviour and the extra entries are decoration.
for FIELD in purpose confidentiality owner status project-version last-verified review-trigger related; do
  cp "$PUB_BACKUP" "$PUB"
  python3 - "$PUB" "$FIELD" <<'PY'
import sys
p, field = sys.argv[1], sys.argv[2]
lines = open(p).read().split('\n')
end = next(i for i, l in enumerate(lines[1:], 1) if l.strip() == '---')
lines.insert(end, f'{field}: placeholder')
open(p, 'w').write('\n'.join(lines))
PY
  check
  if printf '%s' "$CK_OUT" | grep -q "LEAKED-FIELD.*'$FIELD'"; then
    _dossier_assert_pass "internal-only field '$FIELD' is refused in a public document"
  else
    _dossier_assert_fail "internal-only field '$FIELD' reached a public document unflagged"
  fi
done
cp "$PUB_BACKUP" "$PUB"

# --- Restored baseline -------------------------------------------------------
check
for CODE in MISSING-FILE NO-HEADER BAD-HEADER-KIND LEAKED-FIELD NO-H1 CONTRACT-FILE; do
  assert_not_contains "FINDING $CODE" "$CK_OUT" "package is clean of $CODE again after restore"
done

rm -rf "$WORK" 2>/dev/null

_dossier_test_summary
