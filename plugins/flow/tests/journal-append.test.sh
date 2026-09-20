# Tests for plugins/flow/bin/journal-append.sh.
#
# Contract (from the helper's header and the issue-244 specification):
#   - --issue <N> selects <journal.dir>/issue-<N>.md (cascade-resolved).
#   - --file <path> selects an explicit target (used by the auto-log hooks).
#   - --replace-heading <H> replaces H's section, or appends it when absent.
#   - '-' reads the entry text from stdin.
#   - Exit 0 appended; 1 bad arguments; 2 infrastructure error.
#   - Symlinked target or lockfile → exit 2, link target untouched (O_NOFOLLOW).
#   - Lock is <target>.lock — the SAME lock the manifest writer takes, so body
#     appends and manifest writes serialize against each other.
#
# The concurrency tests are the reason this file exists. journal-record.test.sh
# already has a "flock concurrency contract" test, but both of its writers call
# journal-record.sh, so both take the lock and it cannot fail for the reason
# issue-244 fixes: an UNLOCKED writer losing to a locked writer's rename. No
# test in this repository raced a locked writer against an appender before this
# one, which is why the lost-update defect survived.
#
# Prerequisites: python3 + PyYAML. Skipped (PASS-with-skip-message) if missing.

HELPER="$REPO_ROOT/plugins/flow/bin/journal-append.sh"
RECORDER="$REPO_ROOT/plugins/flow/bin/journal-record.sh"

JA_CLEANUP_PATHS=()
_ja_cleanup() {
  local p
  for p in "${JA_CLEANUP_PATHS[@]:-}"; do
    [ -n "$p" ] && [ -e "$p" ] && rm -rf "$p" 2>/dev/null
  done
  return 0
}
trap _ja_cleanup EXIT

_ja_mktemp_dir() {
  local out
  out=$(mktemp -d -t journal-append.tests.XXXXXX 2>/dev/null)
  if [ -z "$out" ] || [ ! -d "$out" ]; then
    echo "journal-append.test.sh: mktemp -d failed" >&2
    kill -INT $$ 2>/dev/null
    exit 2
  fi
  JA_CLEANUP_PATHS+=("$out")
  printf '%s' "$out"
}

# Run the appender inside a scratch dir with $CLAUDE_PLUGIN_ROOT set, so
# cascade-resolve.sh discovers `.decisions` as the journal dir (no settings file
# present → the --default applies). Mirrors journal-record.test.sh's _run_journal.
_run_append() {
  local dir="$1"; shift
  (cd "$dir" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" "$HELPER" "$@")
}

_run_record() {
  local dir="$1"; shift
  (cd "$dir" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/flow" "$RECORDER" "$@")
}

if ! command -v python3 >/dev/null 2>&1; then
  _flow_test_begin "python3 prerequisite"
  _flow_assert_pass "SKIP: python3 not installed"
  return 0
fi
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_test_begin "PyYAML prerequisite"
  _flow_assert_pass "SKIP: PyYAML not installed (apt install python3-yaml / pip install pyyaml)"
  return 0
fi

# --- Test 1: --file appends the given text to the named target ---------------
_flow_test_begin "T1 --file appends"
DIR=$(_ja_mktemp_dir)
mkdir -p "$DIR/.decisions"
printf 'existing\n' > "$DIR/.decisions/issue-1.md"
_run_append "$DIR" --file ".decisions/issue-1.md" --text "appended-entry" >/dev/null 2>&1
RC=$?
assert_exit 0 "$RC" "T1 exit 0"
BODY=$(cat "$DIR/.decisions/issue-1.md" 2>/dev/null)
assert_contains "existing" "$BODY" "T1 original content preserved"
assert_contains "appended-entry" "$BODY" "T1 appended text present"

# --- Test 2: --issue resolves <journal.dir>/issue-<N>.md ---------------------
_flow_test_begin "T2 --issue resolves the journal path"
DIR=$(_ja_mktemp_dir)
mkdir -p "$DIR/.decisions"
printf 'seed\n' > "$DIR/.decisions/issue-42.md"
_run_append "$DIR" --issue 42 --text "via-issue" >/dev/null 2>&1
RC=$?
assert_exit 0 "$RC" "T2 exit 0"
assert_contains "via-issue" "$(cat "$DIR/.decisions/issue-42.md" 2>/dev/null)" "T2 wrote to issue-42.md"

# --- Test 3: '-' reads the entry from stdin ---------------------------------
_flow_test_begin "T3 stdin input"
DIR=$(_ja_mktemp_dir)
mkdir -p "$DIR/.decisions"
printf 'seed\n' > "$DIR/.decisions/issue-7.md"
printf 'from-stdin\n' | _run_append "$DIR" --file ".decisions/issue-7.md" - >/dev/null 2>&1
RC=$?
assert_exit 0 "$RC" "T3 exit 0"
assert_contains "from-stdin" "$(cat "$DIR/.decisions/issue-7.md" 2>/dev/null)" "T3 stdin content appended"

# --- Test 4: neither --issue nor --file → exit 1 -----------------------------
_flow_test_begin "T4 missing target selector"
DIR=$(_ja_mktemp_dir)
_run_append "$DIR" --text "orphan" >/dev/null 2>&1
assert_exit 1 "$?" "T4 exit 1 with no --issue/--file"

# --- Test 5: symlinked target → exit 2, link target untouched ---------------
_flow_test_begin "T5 symlinked target refused"
DIR=$(_ja_mktemp_dir)
mkdir -p "$DIR/.decisions"
printf 'VICTIM\n' > "$DIR/victim.txt"
ln -s "$DIR/victim.txt" "$DIR/.decisions/issue-9.md"
_run_append "$DIR" --file ".decisions/issue-9.md" --text "should-not-land" >/dev/null 2>&1
assert_exit 2 "$?" "T5 exit 2 on symlink"
assert_equal "VICTIM" "$(cat "$DIR/victim.txt")" "T5 symlink target untouched"

# --- Test 6: --replace-heading replaces an existing section, no duplicate ----
_flow_test_begin "T6 replace existing section"
DIR=$(_ja_mktemp_dir)
mkdir -p "$DIR/.decisions"
cat > "$DIR/.decisions/issue-3.md" <<'EOF'
# Journal

## Specification

OLD-BODY

## Other

keep-me
EOF
_run_append "$DIR" --file ".decisions/issue-3.md" --replace-heading "## Specification" --text "NEW-BODY" >/dev/null 2>&1
RC=$?
assert_exit 0 "$RC" "T6 exit 0"
BODY=$(cat "$DIR/.decisions/issue-3.md" 2>/dev/null)
assert_contains "NEW-BODY" "$BODY" "T6 new body present"
assert_not_contains "OLD-BODY" "$BODY" "T6 old body replaced"
assert_contains "keep-me" "$BODY" "T6 following section preserved"
assert_equal "1" "$(grep -c '^## Specification$' "$DIR/.decisions/issue-3.md")" "T6 heading not duplicated"

# --- Test 7: --replace-heading appends when the heading is absent -----------
_flow_test_begin "T7 append absent section"
DIR=$(_ja_mktemp_dir)
mkdir -p "$DIR/.decisions"
printf '# Journal\n\nbody\n' > "$DIR/.decisions/issue-4.md"
_run_append "$DIR" --file ".decisions/issue-4.md" --replace-heading "## Specification" --text "FRESH" >/dev/null 2>&1
RC=$?
assert_exit 0 "$RC" "T7 exit 0"
BODY=$(cat "$DIR/.decisions/issue-4.md" 2>/dev/null)
assert_contains "FRESH" "$BODY" "T7 section appended"
assert_contains "body" "$BODY" "T7 original content preserved"

# --- Test 8: the lockfile is <target>.lock, matching the manifest writer -----
_flow_test_begin "T8 lockfile path"
DIR=$(_ja_mktemp_dir)
mkdir -p "$DIR/.decisions"
printf 'seed\n' > "$DIR/.decisions/issue-5.md"
_run_append "$DIR" --file ".decisions/issue-5.md" --text "x" >/dev/null 2>&1
assert_file_exists "$DIR/.decisions/issue-5.md.lock" "T8 lockfile is <target>.lock"

# --- Test 9: THE RACE — a locked appender and a locked manifest writer -------
# Both must survive. Before issue-244 the appender took no lock at all, so
# record_artifact()'s read→rename published over it.
_flow_test_begin "T9 appender vs manifest writer"
DIR=$(_ja_mktemp_dir)
mkdir -p "$DIR/.decisions"
LOST=0
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  _run_append "$DIR" --file ".decisions/issue-9.md" --text "body-$i" >/dev/null 2>&1 &
  APID=$!
  _run_record "$DIR" --issue 9 --type review-cycle --metadata cycle="$i" >/dev/null 2>&1
  wait "$APID" 2>/dev/null
done
FINAL=$(cat "$DIR/.decisions/issue-9.md" 2>/dev/null)
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  # Whole-line match. The substring form hid a lost entry: "body-1" is a
  # substring of "body-10", so dropping body-1 entirely left LOST=0 and the
  # suite green (verified by mutation).
  printf '%s\n' "$FINAL" | grep -qx "body-$i" || LOST=$((LOST + 1))
done
assert_equal "0" "$LOST" "T9 every appended body survived"
# Each manifest artifact must be present too — a lost append is one failure
# mode, a lost artifact is the other.
# yaml.safe_dump with default_flow_style=False puts the first key of each list
# item on the dash line ("- type: review-cycle"), not indented below it.
# grep -c prints 0 and exits 1 on no match; the exit code must not be
# "handled" with `|| echo 0`, which appends a second line to the count. `-e`
# keeps the leading dash of the pattern from being read as an option.
ARTS=$(grep -c -e '^- type: review-cycle$' "$DIR/.decisions/issue-9.md" 2>/dev/null)
assert_equal "12" "$ARTS" "T9 every manifest artifact survived"

# --- Test 10: concurrent appends lose nothing and truncate nothing -----------
# Scope note, because it is easy to overclaim here: this test does NOT prove
# that append_body uses O_APPEND. It was written believing it did, and a
# mutation replacing the O_APPEND write with a locked read-modify-write left it
# green — as did the same mutation against a 380 KB journal over 40 iterations.
# The window it would need to hit is the span between the appender's read and
# its rename, microseconds wide, inside a process that takes tens of
# milliseconds to start; a bash background write cannot land there reliably.
#
# The property O_APPEND actually buys — that a NON-COOPERATING writer (an
# editor, an older plugin version, a bare `>>`) is never reverted — is not
# assertable from here at all, because an in-process test cannot schedule a
# non-cooperating writer inside a held lock. It remains a reasoned design
# choice, not a tested one, and it is documented as such in append_body().
#
# What this test does verify, deterministically: the appender never truncates
# the file, never drops an entry, and never loses the content that was already
# there. A plausible wrong implementation — opening with "w" instead of append,
# or rewriting from a snapshot that was not read back — fails immediately.
_flow_test_begin "T10 concurrent appends lose and truncate nothing"
DIR=$(_ja_mktemp_dir)
mkdir -p "$DIR/.decisions"
printf 'SEED-CONTENT\n' > "$DIR/.decisions/issue-11.md"
SIZE_BEFORE=$(wc -c < "$DIR/.decisions/issue-11.md" | tr -d ' ')
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  printf 'bare-%s\n' "$i" >> "$DIR/.decisions/issue-11.md" &
  BPID=$!
  _run_append "$DIR" --file ".decisions/issue-11.md" --text "locked-$i" >/dev/null 2>&1
  wait "$BPID" 2>/dev/null
done
FINAL=$(cat "$DIR/.decisions/issue-11.md" 2>/dev/null)
BARE_LOST=0
LOCKED_LOST=0
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  # Whole-line match — see T9.
  printf '%s\n' "$FINAL" | grep -qx "bare-$i" || BARE_LOST=$((BARE_LOST + 1))
  printf '%s\n' "$FINAL" | grep -qx "locked-$i" || LOCKED_LOST=$((LOCKED_LOST + 1))
done
assert_equal "0" "$BARE_LOST" "T10 unlocked bare appends all survived"
assert_equal "0" "$LOCKED_LOST" "T10 locked appends all survived"
assert_contains "SEED-CONTENT" "$FINAL" "T10 pre-existing content never truncated"
SIZE_AFTER=$(wc -c < "$DIR/.decisions/issue-11.md" | tr -d ' ')
if [ "$SIZE_AFTER" -gt "$SIZE_BEFORE" ]; then
  _flow_assert_pass "T10 file grew (was $SIZE_BEFORE, now $SIZE_AFTER)"
else
  _flow_assert_fail "T10 file did not grow: was $SIZE_BEFORE, now $SIZE_AFTER"
fi

# --- Test 11: a partial line is never interleaved ---------------------------
# One logical entry is one write(2): a reader must never observe a torn entry.
_flow_test_begin "T11 entries are not interleaved"
DIR=$(_ja_mktemp_dir)
mkdir -p "$DIR/.decisions"
printf 'seed\n' > "$DIR/.decisions/issue-12.md"
for i in 1 2 3 4 5 6 7 8 9 10; do
  _run_append "$DIR" --file ".decisions/issue-12.md" --text "ENTRY-$i-END" >/dev/null 2>&1 &
done
wait 2>/dev/null
TORN=$(grep -c 'ENTRY-.*-END' "$DIR/.decisions/issue-12.md" 2>/dev/null)
assert_equal "10" "$TORN" "T11 all ten entries intact, none torn"

# --- Test 12: the lock-ordering invariant (risk map row 3) -------------------
# Deterministic, unlike T9/T10. A blocker holds <target>.lock, reads the file,
# publishes a stale copy over it, and releases — while the appender is already
# running. Two distinct wrong implementations lose the entry here:
#
#   * no shared lock      — the appender writes immediately, then the blocker's
#                           rename replaces the file with its stale snapshot;
#   * lock AFTER open     — the appender's fd points at the pre-rename inode,
#                           so its write lands in an unlinked file.
#
# Only "lock, then open" survives. This is why the ordering is an invariant and
# not a style preference. T9/T10 could not reach this: a bash background write
# finishes in microseconds while the helper takes tens of milliseconds to spawn,
# so the append almost always lands before the blocker's read.
_flow_test_begin "T12 lock ordering: lock before open"
DIR=$(_ja_mktemp_dir)
mkdir -p "$DIR/.decisions"
TARGET="$DIR/.decisions/issue-13.md"
printf 'SEED\n' > "$TARGET"
READY="$DIR/blocker.ready"

python3 - "$TARGET.lock" "$TARGET" "$READY" <<'PY' &
import fcntl, os, sys, time
lockfile, target, ready = sys.argv[1], sys.argv[2], sys.argv[3]
fd = os.open(lockfile, os.O_RDWR | os.O_CREAT, 0o600)
fcntl.flock(fd, fcntl.LOCK_EX)
with open(target, "r", encoding="utf-8") as fh:
    stale = fh.read()          # the snapshot the appender must not be lost to
open(ready, "w").write("1")
time.sleep(1.0)                # a window no timing-based bash race can hit
tmp = target + ".blocker.tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    fh.write(stale)
os.rename(tmp, target)         # publish the stale copy over the file
fcntl.flock(fd, fcntl.LOCK_UN)
os.close(fd)
PY
BLOCKER=$!

# Wait for the blocker to hold the lock before starting the appender.
i=0
while [ ! -f "$READY" ] && [ "$i" -lt 200 ]; do
  i=$((i + 1))
  sleep 0.05
done
if [ ! -f "$READY" ]; then
  _flow_assert_fail "T12 blocker never signalled readiness"
else
  _run_append "$DIR" --file ".decisions/issue-13.md" --text "SURVIVOR" >/dev/null 2>&1
  wait "$BLOCKER" 2>/dev/null
  if grep -q "SURVIVOR" "$TARGET" 2>/dev/null; then
    _flow_assert_pass "T12 the append survived a concurrent stale-copy publish"
  else
    _flow_assert_fail "T12 the append was lost — the target was opened before the lock was taken, or taken at all"
  fi
fi

# --- Test 13: AC4 — a section write survives concurrent manifest writes -------
# This is the failure specification-capture reports as SPEC_CAPTURE_BLOCK: it
# writes the section, re-reads it with the Step 1 awk, and finds it gone
# because a manifest writer's rename published over it. The section is written
# here through replace_section() under the shared lock, so it must survive.
# Uses the same controlled blocker as T12. Backgrounded manifest writers do NOT
# reach this window — eight of them against an unlocked replace_section left
# this test green on three consecutive runs — because they finish before or
# after the section write rather than inside it.
_flow_test_begin "T13 section survives a concurrent stale-copy publish"
DIR=$(_ja_mktemp_dir)
mkdir -p "$DIR/.decisions"
J="$DIR/.decisions/issue-14.md"
cat > "$J" <<'EOF'
# Journal

## Specification

OLD

## Other

keep-me
EOF
READY13="$DIR/blocker13.ready"
python3 - "$J.lock" "$J" "$READY13" <<'PY' &
import fcntl, os, sys, time
lockfile, target, ready = sys.argv[1], sys.argv[2], sys.argv[3]
fd = os.open(lockfile, os.O_RDWR | os.O_CREAT, 0o600)
fcntl.flock(fd, fcntl.LOCK_EX)
with open(target, "r", encoding="utf-8") as fh:
    stale = fh.read()
open(ready, "w").write("1")
time.sleep(1.0)
tmp = target + ".blocker.tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    fh.write(stale)
os.rename(tmp, target)
fcntl.flock(fd, fcntl.LOCK_UN)
os.close(fd)
PY
BLOCKER13=$!
i=0
while [ ! -f "$READY13" ] && [ "$i" -lt 200 ]; do i=$((i + 1)); sleep 0.05; done
if [ ! -f "$READY13" ]; then
  _flow_assert_fail "T13 blocker never signalled readiness"
else
  printf '### Non-goals\n- the new body\n' | \
    _run_append "$DIR" --file ".decisions/issue-14.md" --replace-heading "## Specification" - >/dev/null 2>&1
  wait "$BLOCKER13" 2>/dev/null
  SECTION=$(awk '/^## Specification$/{f=1;print;next} /^## /{f=0} f' "$J" 2>/dev/null)
  assert_contains "the new body" "$SECTION" "T13 the section is still readable by the Step 1 awk"
  assert_not_contains "OLD" "$SECTION" "T13 the old body was replaced, not duplicated"
  assert_equal "1" "$(grep -c '^## Specification$' "$J")" "T13 exactly one Specification heading"
  assert_contains "keep-me" "$(cat "$J")" "T13 the following section survived"
fi

# --- Test 14: the call sites actually route through the helper ---------------
# Static, and deliberately so: without it, AC4's implementation could regress
# to an unlocked `cat >>` with every runtime test above still green, because
# those tests exercise the helper rather than the commands that call it.
_flow_test_begin "T14 journal body writers use the locked helper"
for f in commands/design.md commands/brainstorm.md; do
  if grep -q 'cat >> "$JOURNAL_DIR/issue-' "$REPO_ROOT/plugins/flow/$f" 2>/dev/null; then
    _flow_assert_fail "T14 $f still appends to the journal without the lock"
  else
    _flow_assert_pass "T14 $f has no unlocked journal append"
  fi
  if grep -q 'bin/journal-append.sh' "$REPO_ROOT/plugins/flow/$f" 2>/dev/null; then
    _flow_assert_pass "T14 $f routes through journal-append.sh"
  else
    _flow_assert_fail "T14 $f does not call journal-append.sh"
  fi
done
if grep -q 'bin/journal-append.sh' "$REPO_ROOT/plugins/flow/skills/specification-capture/SKILL.md" 2>/dev/null; then
  _flow_assert_pass "T14 specification-capture routes through journal-append.sh"
else
  _flow_assert_fail "T14 specification-capture does not call journal-append.sh"
fi

# --- Test 15: --replace-heading is fence-aware -------------------------------
# A journal may quote the section heading inside a fenced example — the schema
# reference documents the specification shape that way. A fence-blind splice
# matches the QUOTED heading first, replaces it, then replaces the real section
# too, leaving the fence unbalanced and a heading duplicated. Found by probing
# the helper rather than by a test, which is why this test exists now.
_flow_test_begin "T15 a quoted heading inside a fence is not spliced"
DIR=$(_ja_mktemp_dir)
mkdir -p "$DIR/.decisions"
J="$DIR/.decisions/issue-15.md"
cat > "$J" <<'EOF'
# Journal

The schema documents the section heading:

```
## Specification

### Non-goals
```

## Specification

real body

## Other

keep
EOF
printf 'REPLACED\n' | \
  _run_append "$DIR" --file ".decisions/issue-15.md" --replace-heading "## Specification" - >/dev/null 2>&1
RC=$?
assert_exit 0 "$RC" "T15 exit 0"
BODY=$(cat "$J")
assert_equal "1" "$(printf '%s\n' "$BODY" | grep -c '^### Non-goals$')" \
  "T15 the fenced example's contents survive"
assert_equal "2" "$(printf '%s\n' "$BODY" | grep -c '^## Specification$')" \
  "T15 exactly two headings: the quoted one and the real one"
assert_equal "1" "$(printf '%s\n' "$BODY" | grep -c '^REPLACED$')" \
  "T15 only the real section was replaced"
assert_contains "keep" "$BODY" "T15 the following section survived"
# The fence must still be balanced — an odd count means the splice landed inside
# the example.
FENCES=$(printf '%s\n' "$BODY" | grep -c '^```$')
assert_equal "2" "$FENCES" "T15 the code fence is still balanced"

# --- Test 16: the section reader and the writer agree about fences -----------
# The writer became fence-aware; the reader the spec-capture skill used was a
# plain awk one-liner, so the two disagreed about where the section ended. A
# `## ` line quoted inside a fence ended the reader's section early: it reported
# `### Risk map` missing while the file held it, the skill re-prompted for a
# risk map the journal already had, and the writer then rewrote the section from
# the reader's truncated view.
_flow_test_begin "T16 reader and writer agree on where a section ends"
DIR=$(_ja_mktemp_dir)
mkdir -p "$DIR/.decisions"
J="$DIR/.decisions/issue-16.md"
cat > "$J" <<'EOF'
# Journal

## Specification

### Non-goals
value

```yaml
## a comment inside the example
```

### Risk map

| a | b | c |

## Other

keep-me
EOF
READER="$REPO_ROOT/plugins/flow/bin/journal-read-section.sh"
SECTION=$(bash "$READER" --file "$J" --heading "## Specification" 2>/dev/null)
assert_equal "1" "$(printf '%s\n' "$SECTION" | grep -c '^### Risk map$')" \
  "T16 the reader sees the subsection past the quoted heading"
assert_equal "1" "$(printf '%s\n' "$SECTION" | grep -c '^### Non-goals$')" \
  "T16 the reader sees the earlier subsection"
# The writer must agree: replacing the section keeps everything the reader saw.
printf '### Non-goals\nreplaced\n' | \
  _run_append "$DIR" --file ".decisions/issue-16.md" --replace-heading "## Specification" - >/dev/null 2>&1
SECTION2=$(bash "$READER" --file "$J" --heading "## Specification" 2>/dev/null)
assert_equal "1" "$(printf '%s\n' "$SECTION2" | grep -c '^replaced$')" \
  "T16 the writer's replacement is what the reader reads back"
# The writer replaces heading-to-next-heading, so the whole old body goes,
# fenced example included. That is the agreement being asserted: the reader
# returned exactly the region the writer then replaced.
assert_equal "0" "$(printf '%s\n' "$SECTION2" | grep -c "value")" \
  "T16 the old body is gone"
assert_equal "0" "$(printf '%s\n' "$SECTION2" | grep -c '^### Risk map$')" \
  "T16 the old section's subsections went with it"
assert_equal "1" "$(grep -c '^keep-me$' "$J")" \
  "T16 the section AFTER the replaced one survived"
assert_equal "1" "$(grep -c '^## Other$' "$J")" \
  "T16 the following heading survived"

# --- Test 17: --replace-heading preserves the frontmatter byte-for-byte -------
# The docstring claims the manifest prefix is preserved because the writer only
# touches the body. Nothing tested it: treating the whole file as body left the
# suite green. specification-capture uses this path on journals that carry a
# manifest, so a lost prefix would drop the whole artifact record.
_flow_test_begin "T17 frontmatter survives a section write"
DIR=$(_ja_mktemp_dir)
mkdir -p "$DIR/.decisions"
J="$DIR/.decisions/issue-17.md"
cat > "$J" <<'EOF'
---
issue: 17
created: '2026-01-01T00:00:00Z'
artifacts:
- type: specification
  captured_at: '2026-01-01T00:00:00Z'
---
# Journal

## Specification

old
EOF
FRONT_BEFORE=$(awk 'NR==1,/^---$/ && NR>1' "$J" | head -n -1)
_run_append "$DIR" --file ".decisions/issue-17.md" --replace-heading "## Specification" --text "new" >/dev/null 2>&1
assert_exit 0 "$?" "T17 exit 0"
FRONT_AFTER=$(awk 'NR==1,/^---$/ && NR>1' "$J" | head -n -1)
assert_equal "$FRONT_BEFORE" "$FRONT_AFTER" "T17 the frontmatter block is byte-identical"
assert_equal "1" "$(grep -c '^- type: specification$' "$J")" "T17 the artifact entry survived"
assert_contains "new" "$(cat "$J")" "T17 the body was replaced"

# --- Test 18: only the FIRST matching heading is the section -----------------
# A journal can carry the heading twice — a hand-edit, or an append by a writer
# that predates this one. Replacing every match duplicates the new text and
# destroys the second copy and its body.
_flow_test_begin "T18 only the first heading is replaced"
DIR=$(_ja_mktemp_dir)
mkdir -p "$DIR/.decisions"
J="$DIR/.decisions/issue-18.md"
cat > "$J" <<'EOF'
# Journal

## Specification

first-body

## Other

keep

## Specification

second-body
EOF
_run_append "$DIR" --file ".decisions/issue-18.md" --replace-heading "## Specification" --text "NEW" >/dev/null 2>&1
assert_exit 0 "$?" "T18 exit 0"
assert_equal "1" "$(grep -c '^NEW$' "$J")" "T18 the new body appears exactly once"
assert_contains "second-body" "$(cat "$J")" "T18 the second section's body survived"
assert_contains "keep" "$(cat "$J")" "T18 the middle section survived"

# --- Test 19: the argument combinations that must be refused -----------------
_flow_test_begin "T19 mutual exclusion"
DIR=$(_ja_mktemp_dir)
mkdir -p "$DIR/.decisions"
printf 'seed\n' > "$DIR/.decisions/issue-19.md"
_run_append "$DIR" --issue 19 --file ".decisions/issue-19.md" --text "x" >/dev/null 2>&1
assert_exit 1 "$?" "T19 --issue and --file together"
_run_append "$DIR" --file ".decisions/issue-19.md" --text "a" - >/dev/null 2>&1
assert_exit 1 "$?" "T19 --text and - together"
before=$(cat "$DIR/.decisions/issue-19.md")
assert_equal "seed" "$before" "T19 neither refusal wrote anything"

# --- Test 20: a 4-backtick block is not closed by an inner 3-backtick line ---
# The writer and the reader must agree on where a section ends, and both now
# track the fence's run LENGTH: a closing run must be at least as long as the
# opener. Keying on the character alone closed the outer block at the inner
# ``` line, so the `## Specification` QUOTED inside the example became the
# section, and replacing it destroyed the quoted example and left the real
# section untouched.
_flow_test_begin "T20 nested fences"
DIR=$(_ja_mktemp_dir)
mkdir -p "$DIR/.decisions"
J="$DIR/.decisions/issue-20.md"
cat > "$J" <<'EOF'
# Journal

````
```
## Specification
quoted-body
```
````

## Specification

real-body
EOF
_run_append "$DIR" --file ".decisions/issue-20.md" --replace-heading "## Specification" --text "NEW" >/dev/null 2>&1
assert_exit 0 "$?" "T20 exit 0"
assert_contains "quoted-body" "$(cat "$J")" "T20 the quoted section inside the fence survives"
assert_not_contains "real-body" "$(cat "$J")" "T20 the real section's old body is gone"
assert_contains "NEW" "$(cat "$J")" "T20 the real section was replaced"

# --- Test 21: an unclosed fence in the replaced section is refused -----------
# The skip loop ends a section at the next `## ` line, but not while a fence is
# open. An unclosed fence therefore ran the loop to EOF, deleting that heading
# and every section after it — silently, on a journal a person reads. Refusing
# is the safe direction: the file is left exactly as it was.
_flow_test_begin "T21 unclosed fence in the replaced section"
DIR=$(_ja_mktemp_dir)
mkdir -p "$DIR/.decisions"
J="$DIR/.decisions/issue-21.md"
printf '## Specification\n\nbody\n\n```\nunclosed\n\n## Other\n\nprecious\n' > "$J"
BEFORE=$(cat "$J")
_run_append "$DIR" --file ".decisions/issue-21.md" --replace-heading "## Specification" --text "NEW" >/dev/null 2>&1
assert_exit 2 "$?" "T21 exit 2 rather than deleting the tail"
assert_equal "$BEFORE" "$(cat "$J")" "T21 the journal is byte-identical afterwards"

# Control. An unclosed fence with no heading after it cannot over-delete: the
# section really does run to EOF. Without this, refusing EVERY unclosed fence
# would satisfy the assertion above while breaking legitimate replacements.
J2="$DIR/.decisions/issue-21b.md"
printf '## Specification\n\nseed\n\n```\nunclosed tail\n' > "$J2"
_run_append "$DIR" --file ".decisions/issue-21b.md" --replace-heading "## Specification" --text "NEW" >/dev/null 2>&1
assert_exit 0 "$?" "T21b a tail fence with no heading after it still replaces"
assert_contains "NEW" "$(cat "$J2")" "T21b the replacement landed"

# --- Test 22: the heading match is exact, not a prefix -----------------------
# Both the writer and the reader test `line == heading`. A prefix test would
# make `--replace-heading "## Specification"` land on `## Specification
# Extended` when that section comes first — replacing a different section than
# the caller named, and leaving the named one intact. `## Spec` is the same
# hazard from the other direction.
_flow_test_begin "T22 the heading match is exact"
DIR=$(_ja_mktemp_dir)
mkdir -p "$DIR/.decisions"
J="$DIR/.decisions/issue-22.md"
# The longer heading is placed FIRST deliberately. With the exact heading
# first, a prefix test would still land on the right section and every
# assertion below would pass — the ordering is what makes this discriminating.
cat > "$J" <<'EOF'
## Specification Extended

a-different-section

## Specification

the-real-one

## Spec

a-third-section
EOF
_run_append "$DIR" --file ".decisions/issue-22.md" --replace-heading "## Specification" --text "NEW" >/dev/null 2>&1
assert_exit 0 "$?" "T22 exit 0"
BODY=$(cat "$J")
assert_contains "NEW" "$BODY" "T22 the named section was replaced"
assert_not_contains "the-real-one" "$BODY" "T22 the named section's old body is gone"
assert_contains "a-different-section" "$BODY" "T22 the longer heading's section is untouched"
assert_contains "a-third-section" "$BODY" "T22 the shorter heading's section is untouched"

# The reader must agree: it returns the named section only.
SECTION=$(bash "$REPO_ROOT/plugins/flow/bin/journal-read-section.sh" \
  --file "$J" --heading "## Specification" 2>/dev/null)
assert_not_contains "a-different-section" "$SECTION" "T22 the reader stops at the exact heading"
