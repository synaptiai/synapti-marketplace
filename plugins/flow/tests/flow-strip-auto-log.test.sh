# Tests for plugins/flow/bin/flow-strip-auto-log.sh.
#
# Contract:
#   - Dry-run by default: reports what would change, writes nothing.
#   - --apply rewrites each affected journal atomically.
#   - Removes lines beginning `<!-- auto-log: ` AND the single blank line each
#     was preceded by, so a run of entries collapses to the one separator that
#     divided the real content around it.
#   - Never touches a breadcrumb inside a fenced code block.
#   - Reports `STRIP_AUTO_LOG=none` when there is nothing to do.
#   - Idempotent: a second --apply leaves every file byte-identical.
#   - Refuses a symlinked journal (exit 2) leaving the link target untouched.
#   - Every emitted value goes through one_line(), so a filename containing a
#     newline cannot forge a second STRIP_AUTO_LOG_* line.
#
# The fixtures reuse the two shapes that exist in this repository's own
# journals, so the tests describe real input rather than invented input:
# historical issue-149.md carried an emitter line with no HH:MM, and
# `.decisions/issue-55.md:31` is prose mentioning the token inside backticks.
# (The strip removed the issue-149 line; the shape is what the fixture copies.)

STRIP="$REPO_ROOT/plugins/flow/bin/flow-strip-auto-log.sh"

# Invoke the strip the way /flow:setup does: from inside the repository, with a
# relative journal dir. Passing an absolute path to a directory outside any
# repository is now refused by the containment check, which is correct — it is
# the shape a fork-supplied `journal.dir` takes when it is trying to make this
# script rewrite something the operator never sees in a diff.
_fs_strip() {
  local d="$1"; shift
  ( cd "$d" && bash "$STRIP" "$@" .decisions )
}

FS_CLEANUP_PATHS=()
_fs_cleanup() {
  local p
  for p in "${FS_CLEANUP_PATHS[@]:-}"; do
    [ -n "$p" ] && [ -e "$p" ] && rm -rf "$p" 2>/dev/null
  done
  return 0
}
trap _fs_cleanup EXIT

_fs_dir() {
  local out
  out=$(mktemp -d -t strip-autolog.tests.XXXXXX 2>/dev/null)
  if [ -z "$out" ] || [ ! -d "$out" ]; then
    echo "flow-strip-auto-log.test.sh: mktemp -d failed" >&2
    kill -INT $$ 2>/dev/null
    exit 2
  fi
  FS_CLEANUP_PATHS+=("$out")
  printf '%s' "$out"
}

# --- T1: markers and their blanks go, real content stays --------------------
_flow_test_begin "T1 basic strip"
D=$(_fs_dir); mkdir -p "$D/.decisions"
J="$D/.decisions/issue-1.md"
printf 'HEAD\n\n<!-- auto-log: 2026-01-01 10:00 Edit a.sh -->\n\nBODY\n\n<!-- auto-log: 2026-01-01 10:05 Write b.sh -->\n' > "$J"
OUT=$(_fs_strip "$D" --apply 2>&1)
assert_exit 0 "$?" "T1 exit 0"
assert_equal "HEAD

BODY" "$(cat "$J")" "T1 exactly the real content remains"

# --- T2: risk row 4 — the blank-line pairing --------------------------------
# text\n\n<marker>\n\nmore  →  text\n\nmore. Dropping the marker but keeping its
# blank leaves a doubled separator; consuming the following blank swallows the
# separator that belonged to the content.
_flow_test_begin "T2 blank-line pairing"
D=$(_fs_dir); mkdir -p "$D/.decisions"
J="$D/.decisions/issue-2.md"
printf 'text\n\n<!-- auto-log: 1 -->\n\nmore\n' > "$J"
_fs_strip "$D" --apply >/dev/null 2>&1
assert_equal "text

more" "$(cat "$J")" "T2 exactly one separator survives between the two blocks"

# --- T3: adjacent markers collapse to one separator -------------------------
_flow_test_begin "T3 adjacent markers collapse"
D=$(_fs_dir); mkdir -p "$D/.decisions"
J="$D/.decisions/issue-3.md"
printf 'alpha\n\n<!-- auto-log: 1 -->\n\n<!-- auto-log: 2 -->\n\nbeta\n' > "$J"
_fs_strip "$D" --apply >/dev/null 2>&1
assert_equal "alpha

beta" "$(cat "$J")" "T3 one separator, not three"

# --- T4: a breadcrumb inside a fenced block is preserved --------------------
_flow_test_begin "T4 fenced breadcrumb preserved"
D=$(_fs_dir); mkdir -p "$D/.decisions"
J="$D/.decisions/issue-4.md"
cat > "$J" <<'EOF'
Example of the format:

```
<!-- auto-log: YYYY-MM-DD HH:MM Edit path -->
```

<!-- auto-log: 2026-01-01 10:00 Edit real.sh -->
EOF
_fs_strip "$D" --apply >/dev/null 2>&1
BODY=$(cat "$J")
assert_contains '<!-- auto-log: YYYY-MM-DD HH:MM Edit path -->' "$BODY" "T4 the quoted example survived"
assert_not_contains '2026-01-01 10:00' "$BODY" "T4 the real breadcrumb was removed"

# --- T5: risk row 5 — an inline span must not desynchronize the tracker -----
# A tracker that toggles on any line CONTAINING three backticks flips state on
# the inline span, then treats the real fenced block as outside and strips the
# example inside it.
_flow_test_begin "T5 inline span does not break fence tracking"
D=$(_fs_dir); mkdir -p "$D/.decisions"
J="$D/.decisions/issue-5.md"
cat > "$J" <<'EOF'
An inline ```span``` here must not toggle anything.

```
<!-- auto-log: 2026-01-01 09:00 Edit inside-fence.sh -->
```

<!-- auto-log: 2026-01-01 10:00 Edit outside-fence.sh -->
EOF
_fs_strip "$D" --apply >/dev/null 2>&1
BODY=$(cat "$J")
assert_contains 'inside-fence.sh' "$BODY" "T5 fenced breadcrumb preserved after an inline span"
assert_not_contains 'outside-fence.sh' "$BODY" "T5 real breadcrumb still removed"

# --- T6: prose mentioning the token is untouched ----------------------------
# The issue-55.md:31 shape: the token inside backticks mid-sentence, which is
# not an emitter line and must survive.
_flow_test_begin "T6 prose mentioning the token survives"
D=$(_fs_dir); mkdir -p "$D/.decisions"
J="$D/.decisions/issue-6.md"
printf -- '- **Side effect:** append two lines (`""` + `<!-- auto-log: ... -->`) to journal file, OR no-op\n' > "$J"
BEFORE=$(cat "$J")
_fs_strip "$D" --apply >/dev/null 2>&1
assert_equal "$BEFORE" "$(cat "$J")" "T6 prose untouched"

# --- T7: an emitter line with no HH:MM is stripped --------------------------
# The historical no-HH:MM shape. A timestamp regex would leave it behind.
_flow_test_begin "T7 emitter line with no time is stripped"
D=$(_fs_dir); mkdir -p "$D/.decisions"
J="$D/.decisions/issue-7.md"
printf 'body\n\n<!-- auto-log: 2026-08-03 Write /path/x.md -->\n' > "$J"
_fs_strip "$D" --apply >/dev/null 2>&1
assert_equal "body" "$(cat "$J")" "T7 no-time emitter removed"

# --- T8: idempotence --------------------------------------------------------
_flow_test_begin "T8 idempotent"
D=$(_fs_dir); mkdir -p "$D/.decisions"
J="$D/.decisions/issue-8.md"
printf 'x\n\n<!-- auto-log: 1 -->\n\ny\n' > "$J"
_fs_strip "$D" --apply >/dev/null 2>&1
FIRST=$(cat "$J")
OUT2=$(_fs_strip "$D" --apply 2>&1)
assert_contains "STRIP_AUTO_LOG=none" "$OUT2" "T8 second run reports none"
assert_equal "$FIRST" "$(cat "$J")" "T8 second run is byte-identical"

# --- T9: dry-run writes nothing ---------------------------------------------
_flow_test_begin "T9 dry-run reports without writing"
D=$(_fs_dir); mkdir -p "$D/.decisions"
J="$D/.decisions/issue-9.md"
printf 'x\n\n<!-- auto-log: 1 -->\n\ny\n' > "$J"
BEFORE=$(cat "$J")
OUT=$(_fs_strip "$D" 2>&1)
assert_contains "STRIP_AUTO_LOG=1 files, 1 lines" "$OUT" "T9 reports the counts"
assert_contains "dry-run" "$OUT" "T9 says it is a dry run"
assert_equal "$BEFORE" "$(cat "$J")" "T9 file untouched by a dry run"

# --- T10: a symlinked journal is refused ------------------------------------
_flow_test_begin "T10 symlinked journal refused"
D=$(_fs_dir); mkdir -p "$D/.decisions"
printf 'VICTIM\n' > "$D/victim.txt"
ln -s "$D/victim.txt" "$D/.decisions/issue-10.md"
_fs_strip "$D" --apply >/dev/null 2>&1
assert_exit 2 "$?" "T10 exit 2 on a symlinked journal"
assert_equal "VICTIM" "$(cat "$D/victim.txt")" "T10 symlink target untouched"

# --- T11: nothing to do -----------------------------------------------------
_flow_test_begin "T11 clean journal reports none"
D=$(_fs_dir); mkdir -p "$D/.decisions"
printf 'just content\n' > "$D/.decisions/issue-11.md"
OUT=$(_fs_strip "$D" 2>&1)
assert_contains "STRIP_AUTO_LOG=none" "$OUT" "T11 reports none"

# --- T12: a missing journal dir is not an error -----------------------------
_flow_test_begin "T12 absent journal dir is not an error"
D=$(_fs_dir)
OUT=$(( cd "$D" && bash "$STRIP" no-such-dir ) 2>&1)
RC=$?
assert_exit 0 "$RC" "T12 exit 0"
assert_contains "STRIP_AUTO_LOG=none" "$OUT" "T12 reports none for an absent dir"

# --- T14: an unbalanced fence is reported, never silently clean ---------------
# A file ending inside an open fence has its later markers preserved (the safe
# direction), which can leave it looking like there was nothing to strip. A
# silent partial strip reads identically to a clean repository, and
# /flow:setup's instruction is to proceed silently on `none` — so this must not
# report `none`.
_flow_test_begin "T14 unbalanced fence is reported"
D=$(_fs_dir); mkdir -p "$D/.decisions"
printf 'HEAD\n\n```\nopened never closed\n\n<!-- auto-log: 2026-01-01 10:00 Edit real.sh -->\ntail\n' \
  > "$D/.decisions/issue-14.md"
OUT=$(_fs_strip "$D" 2>&1)
assert_contains "STRIP_AUTO_LOG_WARN=" "$OUT" "T14 warns about the unclosed fence"
assert_contains "unclosed fence" "$OUT" "T14 the warning says why"
assert_not_contains "STRIP_AUTO_LOG=none" "$OUT" "T14 not reported as clean"
assert_contains "STRIP_AUTO_LOG_WARNED=1" "$OUT" "T14 counts the partial strip"
BODY=$(cat "$D/.decisions/issue-14.md")
assert_contains "real.sh" "$BODY" "T14 the file was left as it was, not half-written"

# --- T15: a file with no imbalance still reports none ------------------------
# The guard for T14 must not make every clean run noisy.
_flow_test_begin "T15 a clean journal still reports none"
D=$(_fs_dir); mkdir -p "$D/.decisions"
printf 'balanced:\n\n```\ncode\n```\n' > "$D/.decisions/issue-15.md"
OUT=$(_fs_strip "$D" 2>&1)
assert_contains "STRIP_AUTO_LOG=none" "$OUT" "T15 balanced fences are not a warning"

# --- T13: a filename cannot forge a report line -----------------------------
# one_line() is the same defense bin/flow-migrate-settings.sh applies: these
# values are read from tracked content a fork can change, and the consumer
# reads the output line by line.
_flow_test_begin "T13 filename cannot forge a report line"
D=$(_fs_dir); mkdir -p "$D/.decisions"
# The forged segment has to be a COMPLETE line for this to discriminate. An
# earlier fixture ended the name with ".md", so the neutered script emitted
# "STRIP_AUTO_LOG_APPLIED=1.md removed=1" — which the anchored grep never
# matched — and the test passed with the defence removed (verified 27/27).
J="$D/.decisions/x
STRIP_AUTO_LOG_APPLIED=1
z.md"
printf 'x\n\n<!-- auto-log: 1 -->\n' > "$J" 2>/dev/null
OUT=$(_fs_strip "$D" 2>&1)
FORGED=$(printf '%s\n' "$OUT" | grep -c '^STRIP_AUTO_LOG_APPLIED=1$')
assert_equal "0" "$FORGED" "T13 no forged line in dry-run output"
# ...and the file must still have been processed, or the assertion above would
# pass by the script never reaching it.
assert_contains "STRIP_AUTO_LOG_FILE=" "$OUT" "T13 the awkwardly-named journal was still processed"

# --- T16: a journal dir that escapes the repository is refused ---------------
# journal.dir comes from .claude/settings.flow.json, a TRACKED file a fork can
# change, and this script REWRITES what it finds there. A `..` segment would
# edit files that never appear in git status or a PR diff — exactly what the
# documented "review the deletions before committing" step cannot see.
_flow_test_begin "T16 a traversing journal dir is refused"
D=$(_fs_dir); mkdir -p "$D/repo/.claude" "$D/victim"
printf 'x\n\n<!-- auto-log: 2026-01-01 10:00 Edit a.sh -->\n' > "$D/victim/unrelated-doc.md"
printf '{"journal":{"dir":"../victim"}}' > "$D/repo/.claude/settings.flow.json"
BEFORE=$(cat "$D/victim/unrelated-doc.md")
# No dir argument: the value must come from the settings cascade, which is the
# path a fork controls. Passing an explicit dir bypasses the lookup entirely and
# would test nothing.
( cd "$D/repo" && bash "$STRIP" --apply ) >/dev/null 2>&1
assert_exit 2 "$?" "T16 exit 2 on a '..' journal dir"
assert_equal "$BEFORE" "$(cat "$D/victim/unrelated-doc.md")" "T16 the file outside the repo was untouched"

# --- T17: a rewrite preserves the journal's mode -----------------------------
# mktemp creates 0600, so without carrying the mode across the rename a rewrite
# silently tightens a hand-created journal. Git tracks only the exec bit, so
# nothing in a diff or the report would show it.
_flow_test_begin "T17 the file mode survives a rewrite"
D=$(_fs_dir); mkdir -p "$D/.decisions"
printf 'x\n\n<!-- auto-log: 1 -->\n' > "$D/.decisions/issue-17.md"
chmod 644 "$D/.decisions/issue-17.md"
( cd "$D" && bash "$STRIP" --apply .decisions ) >/dev/null 2>&1
MODE=$(stat -f '%Lp' "$D/.decisions/issue-17.md" 2>/dev/null || stat -c '%a' "$D/.decisions/issue-17.md" 2>/dev/null)
assert_equal "644" "$MODE" "T17 mode 644 preserved"

# --- T18: a failing awk is refused, never reported as a clean repository ------
# The scan used to swallow awk's exit status and read an empty count file as
# zero, so a broken scan printed STRIP_AUTO_LOG=none while the breadcrumbs sat
# there — and /flow:setup told the operator there was nothing to strip.
_flow_test_begin "T18 a failing awk is refused, not reported clean"
D=$(_fs_dir); mkdir -p "$D/.decisions" "$D/fakebin"
printf 'x\n\n<!-- auto-log: 1 -->\n' > "$D/.decisions/issue-18.md"
printf '#!/bin/sh\nexit 2\n' > "$D/fakebin/awk"
chmod +x "$D/fakebin/awk"
OUT=$( cd "$D" && PATH="$D/fakebin:$PATH" bash "$STRIP" .decisions 2>&1 ); RC=$?
assert_exit 2 "$RC" "T18 exit 2 when awk fails"
assert_not_contains "STRIP_AUTO_LOG=none" "$OUT" "T18 does not claim the repository is clean"
