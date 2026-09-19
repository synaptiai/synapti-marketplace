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
  case "$FINAL" in *"body-$i"*) ;; *) LOST=$((LOST + 1)) ;; esac
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
  case "$FINAL" in *"bare-$i"*) ;; *) BARE_LOST=$((BARE_LOST + 1)) ;; esac
  case "$FINAL" in *"locked-$i"*) ;; *) LOCKED_LOST=$((LOCKED_LOST + 1)) ;; esac
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
