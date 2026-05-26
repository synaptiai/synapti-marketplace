# Tests for plugins/flow/bin/cascade-resolve.sh.
#
# Contract under test (from cascade-resolve.sh header):
#   - Resolves a jq expression against four settings sources in precedence
#     order: local > project > user > plugin.
#   - --default fallback when no source resolves a non-empty value.
#   - --compact preserves JSON quoting (uses jq -c instead of jq -r).
#   - Exit 2 on infrastructure errors (jq missing without --default, missing
#     expression, unknown flag).
#   - Per-source jq parse error → stderr WARN + skip + continue (not abort).
#
# Each test sets up an isolated scratch dir, runs assertions, and relies on
# the file-level cleanup trap to remove temp resources. Cleanup paths are
# registered in CLEANUP_PATHS; a single trap removes everything. Previously
# the trap was rewritten mid-file to cover newly-allocated SHADOW dirs, which
# was fragile — any third resource would have been silently leaked.

HELPER="$REPO_ROOT/plugins/flow/bin/cascade-resolve.sh"

# Cleanup contract: every mktemp dir/file allocated by this test file is
# appended to CLEANUP_PATHS; the EXIT trap removes them all at file end.
# `${VAR:-}` guards each entry so an interrupted mid-allocation leaves a
# coherent state for the trap.
CLEANUP_PATHS=()
_cleanup_all() {
  local p
  for p in "${CLEANUP_PATHS[@]:-}"; do
    [ -n "$p" ] && rm -rf "$p" 2>/dev/null
  done
}
trap _cleanup_all EXIT

# Defensive mktemp wrapper: empty SCRATCH_ROOT would later cascade into
# `mkdir -p "/.claude"` at filesystem root, which is exactly the kind of
# pathological failure the harness should never produce. Fail fast instead.
#
# Important: callers invoke this via `DIR=$(_mktemp_or_die ...)` — command
# substitution runs the function in a SUBSHELL. A bare `exit 2` from inside
# would only kill the subshell, leaving the caller with DIR="" and the test
# continuing against the wrong paths. We `kill -INT $$` to deliver SIGINT to
# the OUTER shell process (the sourced test), which run.sh's per-file
# subshell will then propagate as a non-zero exit, surfaced as "no SUMMARY
# line" by the runner. The `exit 2` after `kill` is belt-and-suspenders for
# the unlikely case where SIGINT is masked.
_mktemp_or_die() {
  local kind="$1"; shift
  local out
  out=$(mktemp "$@" 2>/dev/null)
  if [ -z "$out" ] || [ ! -e "$out" ]; then
    echo "cascade-resolve.test.sh: mktemp failed for $kind" >&2
    kill -INT $$ 2>/dev/null
    exit 2
  fi
  CLEANUP_PATHS+=("$out")
  printf '%s' "$out"
}

SCRATCH_ROOT=$(_mktemp_or_die "SCRATCH_ROOT" -d -t cascade-resolve.tests.XXXXXX)

# Each test creates its own subdirectory inside SCRATCH_ROOT. Per-test dirs
# don't need separate CLEANUP_PATHS entries — they're under SCRATCH_ROOT,
# which the trap recursively removes.
_make_scratch() {
  local name="$1"
  local dir="$SCRATCH_ROOT/$name"
  # Pre-build the four-tier layout. HOME points to "$dir/home" (not "$dir")
  # so user-tier settings resolve to a path distinct from project-tier.
  # Previously HOME=. plus pwd=$dir made USER_SETTINGS=./.claude/settings.flow.json
  # which is the SAME path as PROJECT_SETTINGS — the precedence test silently
  # tested "local > project > (project again, masquerading as user) > plugin"
  # rather than the real 4-tier chain.
  mkdir -p "$dir/.claude" "$dir/plugins/flow" "$dir/home/.claude"
  printf '%s\n' "$dir"
}

# --- Test 1: precedence — local beats project beats user beats plugin
_flow_test_begin "precedence: local > project > user > plugin"
DIR=$(_make_scratch precedence)
echo '{"journal": {"dir": "from-plugin"}}'  > "$DIR/plugins/flow/settings.json"
echo '{"journal": {"dir": "from-user"}}'    > "$DIR/home/.claude/settings.flow.json"
echo '{"journal": {"dir": "from-project"}}' > "$DIR/.claude/settings.flow.json"
echo '{"journal": {"dir": "from-local"}}'   > "$DIR/.claude/settings.flow.local.json"

# All four tiers present → local wins.
OUT=$(cd "$DIR" && HOME="$DIR/home" CLAUDE_PLUGIN_ROOT="plugins/flow" \
  "$HELPER" '.journal.dir // empty' 2>/dev/null)
assert_equal "from-local" "$OUT" "local wins"

# Remove local → project wins.
rm "$DIR/.claude/settings.flow.local.json"
OUT=$(cd "$DIR" && HOME="$DIR/home" CLAUDE_PLUGIN_ROOT="plugins/flow" \
  "$HELPER" '.journal.dir // empty' 2>/dev/null)
assert_equal "from-project" "$OUT" "project wins after local removed"

# Remove project → user wins (now reading a genuinely distinct file at
# $DIR/home/.claude/settings.flow.json, not the project path).
rm "$DIR/.claude/settings.flow.json"
OUT=$(cd "$DIR" && HOME="$DIR/home" CLAUDE_PLUGIN_ROOT="plugins/flow" \
  "$HELPER" '.journal.dir // empty' 2>/dev/null)
assert_equal "from-user" "$OUT" "user wins after project removed"

# Remove user → plugin wins.
rm "$DIR/home/.claude/settings.flow.json"
OUT=$(cd "$DIR" && HOME="$DIR/home" CLAUDE_PLUGIN_ROOT="plugins/flow" \
  "$HELPER" '.journal.dir // empty' 2>/dev/null)
assert_equal "from-plugin" "$OUT" "plugin wins after user removed"

# --- Test 2: --default fallback when nothing resolves
_flow_test_begin "default fallback when no source has key"
DIR=$(_make_scratch default)
echo '{"unrelated": true}' > "$DIR/plugins/flow/settings.json"
OUT=$(cd "$DIR" && HOME="$DIR/home" CLAUDE_PLUGIN_ROOT="plugins/flow" \
  "$HELPER" --default ".decisions" '.journal.dir // empty' 2>/dev/null)
EXIT=$?
assert_equal ".decisions" "$OUT" "default emitted"
assert_exit 0 "$EXIT" "default exits 0"

# --- Test 3: no default + no resolution → empty stdout + exit 0
_flow_test_begin "no default, no resolution → empty stdout exit 0"
DIR=$(_make_scratch nodefault)
echo '{}' > "$DIR/plugins/flow/settings.json"
OUT=$(cd "$DIR" && HOME="$DIR/home" CLAUDE_PLUGIN_ROOT="plugins/flow" \
  "$HELPER" '.journal.dir // empty' 2>/dev/null)
EXIT=$?
assert_equal "" "$OUT" "empty stdout"
assert_exit 0 "$EXIT" "exit 0"

# --- Test 4: --compact preserves JSON quoting
_flow_test_begin "--compact preserves JSON quoting"
DIR=$(_make_scratch compact)
echo '{"k": "v"}' > "$DIR/plugins/flow/settings.json"
RAW=$(cd "$DIR" && HOME="$DIR/home" CLAUDE_PLUGIN_ROOT="plugins/flow" "$HELPER" '.k' 2>/dev/null)
CMP=$(cd "$DIR" && HOME="$DIR/home" CLAUDE_PLUGIN_ROOT="plugins/flow" "$HELPER" --compact '.k' 2>/dev/null)
# jq -r drops the surrounding double-quotes; jq -c preserves them.
assert_equal "v" "$RAW" "raw mode strips quotes"
assert_equal '"v"' "$CMP" "compact mode preserves quotes"

# --- Test 5: missing expression → exit 2
_flow_test_begin "missing expression → exit 2"
OUT=$(cd "$SCRATCH_ROOT" && HOME="$SCRATCH_ROOT" "$HELPER" 2>&1)
EXIT=$?
assert_exit 2 "$EXIT" "exit 2"
assert_contains "missing <jq-expression>" "$OUT" "stderr names the problem"

# --- Test 6: unknown flag → exit 2
_flow_test_begin "unknown flag → exit 2"
OUT=$(cd "$SCRATCH_ROOT" && HOME="$SCRATCH_ROOT" "$HELPER" --bogus '.x' 2>&1)
EXIT=$?
assert_exit 2 "$EXIT" "exit 2"
assert_contains "unknown flag" "$OUT" "stderr names the unknown flag"

# --- Test 7: per-source parse error → stderr WARN + skip + continue
# Project has a syntax-broken JSON; plugin has the correct value. Helper
# should WARN about the project, skip it, and resolve from plugin.
_flow_test_begin "parse error per-source → WARN + skip + continue"
DIR=$(_make_scratch parse_err)
echo '{not valid json' > "$DIR/.claude/settings.flow.json"
echo '{"journal": {"dir": "from-plugin"}}' > "$DIR/plugins/flow/settings.json"
STDOUT_TMP=$(_mktemp_or_die "STDOUT_TMP" -t cascade.so.XXXXXX)
STDERR_TMP=$(_mktemp_or_die "STDERR_TMP" -t cascade.se.XXXXXX)
(cd "$DIR" && HOME="$DIR/home" CLAUDE_PLUGIN_ROOT="plugins/flow" \
  "$HELPER" '.journal.dir // empty' >"$STDOUT_TMP" 2>"$STDERR_TMP")
EXIT=$?
OUT=$(cat "$STDOUT_TMP"); ERR=$(cat "$STDERR_TMP")
assert_equal "from-plugin" "$OUT" "fell through to plugin"
assert_exit 0 "$EXIT" "exit 0 despite bad JSON"
assert_contains "WARN: failed to parse" "$ERR" "stderr WARN was emitted"
assert_contains "settings.flow.json" "$ERR" "WARN names the failing source"

# --- Tests 8 + 9: jq-missing graceful degrade
# Construct a shadow PATH containing every needed tool EXCEPT jq. macOS
# Sequoia ships jq in /usr/bin and Homebrew puts it in /opt/homebrew/bin or
# /usr/local/bin, so neither /bin nor /usr/bin is safe to pass through.
# Symlinks are created under a mktemp dir (0700 mode by default — a
# co-tenant cannot inject a fake jq).
SHADOW=$(_mktemp_or_die "SHADOW" -d -t cascade.shadow.XXXXXX)
for tool in bash mktemp tr cut rm sh env cat; do
  T=$(command -v "$tool" 2>/dev/null) || continue
  ln -s "$T" "$SHADOW/$tool"
done
# Sanity-check the shadow was built. If `command -v bash` somehow returned
# nothing, the helper invocations below would error opaquely.
if [ ! -L "$SHADOW/bash" ]; then
  echo "cascade-resolve.test.sh: shadow PATH missing bash symlink" >&2
  exit 2
fi

_flow_test_begin "jq missing + --default → emit default, exit 0"
DIR=$(_make_scratch nojq)
echo '{"k": "v"}' > "$DIR/plugins/flow/settings.json"
STDOUT_TMP=$(_mktemp_or_die "STDOUT_TMP_NOJQ1" -t cascade.nojq.so.XXXXXX)
STDERR_TMP=$(_mktemp_or_die "STDERR_TMP_NOJQ1" -t cascade.nojq.se.XXXXXX)
(cd "$DIR" && HOME="$DIR/home" CLAUDE_PLUGIN_ROOT="plugins/flow" PATH="$SHADOW" \
  "$SHADOW/bash" "$HELPER" --default "fallback" '.k' \
  >"$STDOUT_TMP" 2>"$STDERR_TMP")
EXIT=$?
OUT=$(cat "$STDOUT_TMP"); ERR=$(cat "$STDERR_TMP")
assert_equal "fallback" "$OUT" "default emitted on stdout"
assert_exit 0 "$EXIT" "exit 0 with --default"
assert_contains "jq not installed" "$ERR" "stderr WARN about missing jq"

_flow_test_begin "jq missing + no default → exit 2"
DIR=$(_make_scratch nojq2)
echo '{"k": "v"}' > "$DIR/plugins/flow/settings.json"
STDERR_TMP=$(_mktemp_or_die "STDERR_TMP_NOJQ2" -t cascade.nojq2.se.XXXXXX)
(cd "$DIR" && HOME="$DIR/home" CLAUDE_PLUGIN_ROOT="plugins/flow" PATH="$SHADOW" \
  "$SHADOW/bash" "$HELPER" '.k' 2>"$STDERR_TMP")
EXIT=$?
ERR=$(cat "$STDERR_TMP")
assert_exit 2 "$EXIT" "exit 2 without --default"
assert_contains "jq not installed" "$ERR" "stderr WARN about missing jq"

# --- Compound migration expression ────────────────────────────────────────
# cascade-resolve passes any jq through, but the 3-state goalCreation migration
# relies on a compound if/elif/else-null expression that was previously untested.
# The `else null` (not "auto") is load-bearing: a source carrying NEITHER key
# must yield null so the cascade falls through instead of short-circuiting.
MIG='.flow.goals.goalCreation // (if .flow.goals.requireGoalForStart == true then "always" elif .flow.goals.requireGoalForStart == false then "off" else null end)'

_flow_test_begin "migration expr: requireGoalForStart:true -> always"
DIR=$(_make_scratch mig-true)
echo '{}' > "$DIR/plugins/flow/settings.json"
echo '{"flow":{"goals":{"requireGoalForStart":true}}}' > "$DIR/.claude/settings.flow.json"
OUT=$(cd "$DIR" && HOME="$DIR/home" CLAUDE_PLUGIN_ROOT="plugins/flow" "$HELPER" --default auto "$MIG" 2>/dev/null)
assert_equal "always" "$OUT" "legacy true maps to always"

_flow_test_begin "migration expr: requireGoalForStart:false -> off"
DIR=$(_make_scratch mig-false)
echo '{}' > "$DIR/plugins/flow/settings.json"
echo '{"flow":{"goals":{"requireGoalForStart":false}}}' > "$DIR/.claude/settings.flow.json"
OUT=$(cd "$DIR" && HOME="$DIR/home" CLAUDE_PLUGIN_ROOT="plugins/flow" "$HELPER" --default auto "$MIG" 2>/dev/null)
assert_equal "off" "$OUT" "legacy false maps to off"

_flow_test_begin "migration expr: no key anywhere -> auto (cascade default)"
DIR=$(_make_scratch mig-none)
echo '{}' > "$DIR/plugins/flow/settings.json"
OUT=$(cd "$DIR" && HOME="$DIR/home" CLAUDE_PLUGIN_ROOT="plugins/flow" "$HELPER" --default auto "$MIG" 2>/dev/null)
assert_equal "auto" "$OUT" "absent everywhere -> auto"

_flow_test_begin "migration expr: explicit goalCreation wins"
DIR=$(_make_scratch mig-explicit)
echo '{}' > "$DIR/plugins/flow/settings.json"
echo '{"flow":{"goals":{"goalCreation":"always","requireGoalForStart":false}}}' > "$DIR/.claude/settings.flow.json"
OUT=$(cd "$DIR" && HOME="$DIR/home" CLAUDE_PLUGIN_ROOT="plugins/flow" "$HELPER" --default auto "$MIG" 2>/dev/null)
assert_equal "always" "$OUT" "goalCreation overrides legacy key in same source"

_flow_test_begin "migration expr: PRECEDENCE-LEAK GUARD — unrelated local file does not mask project requireGoalForStart"
DIR=$(_make_scratch mig-leak)
echo '{}' > "$DIR/plugins/flow/settings.json"
echo '{"flow":{"goals":{"requireGoalForStart":true}}}' > "$DIR/.claude/settings.flow.json"
# Highest-precedence local file with NO goals key (e.g. an unrelated agentTeams override).
echo '{"agentTeams":false}' > "$DIR/.claude/settings.flow.local.json"
OUT=$(cd "$DIR" && HOME="$DIR/home" CLAUDE_PLUGIN_ROOT="plugins/flow" "$HELPER" --default auto "$MIG" 2>/dev/null)
assert_equal "always" "$OUT" "else-null lets the neither-key local file fall through to project (a buggy else-\"auto\" would mask it as auto)"

_flow_test_begin "migration expr: explicit local goalCreation:off correctly wins over project legacy true"
DIR=$(_make_scratch mig-localwins)
echo '{}' > "$DIR/plugins/flow/settings.json"
echo '{"flow":{"goals":{"requireGoalForStart":true}}}' > "$DIR/.claude/settings.flow.json"
echo '{"flow":{"goals":{"goalCreation":"off"}}}' > "$DIR/.claude/settings.flow.local.json"
OUT=$(cd "$DIR" && HOME="$DIR/home" CLAUDE_PLUGIN_ROOT="plugins/flow" "$HELPER" --default auto "$MIG" 2>/dev/null)
assert_equal "off" "$OUT" "a real local goalCreation still wins (precedence preserved)"
