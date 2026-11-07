# shellcheck shell=bash
# End-to-end: what the e2e harness itself leaves on disk. A test file run
# through tests/lib/e2e.sh copies the plugin for some scenarios and keeps its
# scratch root when an expectation fails; with the whole plugin copied (38 MB,
# most of it recorded eval runs) and every scenario kept, one failing file
# left gigabytes behind on each run.
#
# Each scenario writes a small test file into its scratch directory and runs
# it the way tests/run.sh runs a file (assert.sh sourced, then the file), with
# TMPDIR pointing at a directory of the scenario, so the inner file's scratch
# root lands where this file can look at it. The hs-runner scenarios run
# tests/run.sh itself on a small file, for what the runner removes when a file
# ends. The artifact for each scenario is written to $FLOW_E2E_ARTIFACT_DIR.
#
# Ways it can be wrong, written down before the scenarios:
#   H1 the plugin copy lacks code the plugin runs (its digest differs from the
#      plugin's, or .claude-plugin, references, templates or an eval case is
#      missing)
#   H2 the plugin copy still holds tests/ or a recorded eval run
#      (evals/results-*)
#   H3 a copy onto a directory that exists nests the plugin inside it instead
#      of failing
#   H4 after a failure the artifacts are removed, or their path is not printed
#   H5 after a failure a scenario's repository, home or plugin copy is kept
#   H6 FLOW_E2E_KEEP_SCRATCH=1 does not keep the scenario scratch
#   H7 after a clean run anything of the scratch root is left
#   H8 clearing the scratch follows a symlink and removes or changes what it
#      points at
#   H9 a second e2e_plugin_copy in one scenario does not replace its file in
#      the copy the scenario runs (a test that swaps the file per case runs
#      every case against the first one)
#   H10 a path named to e2e_copy_plugin (a recorded eval run whose scripts a
#      scenario runs from the copy) is missing from the copy
#   H11 tests/run.sh lets a test file leave the temporary directories it
#      made (most files that are not e2e files never remove theirs)
#   H12 run.sh removes the artifacts the e2e harness keeps for a failed file,
#      or a file sees the run's own TMPDIR instead of a directory of its own
#   H13 a run.sh started by a test file and killed with SIGKILL (as
#      run-parallel.test.sh does) leaves its directories in the outer run's
#      TMPDIR, where nothing removes them

{ [ -n "${REPO_ROOT:-}" ] && declare -F _flow_assert_fail >/dev/null \
    && source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh"; } || {
  printf '%s\n' "cannot load tests/lib/e2e.sh; run this file with plugins/flow/tests/run.sh" >&2
  return 1 2>/dev/null; exit 1
}

# _hs_case <name> <purpose> — a scenario with an empty TMPDIR for the inner run.
_hs_case() {
  _flow_test_begin "$1"
  e2e_new "$1"
  e2e_describe "$2"
  mkdir -p "$E2E_DIR/tmp" "$E2E_DIR/outside"
}

# _hs_inner <expectation: pass|fail> <extra body> — the inner test file: one
# scenario that copies the plugin with one file replaced, lists the copy into
# $HS_OUT, runs the extra body, and then meets or fails one expectation.
_hs_inner() {
  local verdict='e2e_expect_equal same same "an expectation that holds"'
  [ "$1" = fail ] && verdict='e2e_expect_equal expected actual "an expectation that fails"'
  cat > "$E2E_DIR/inner.test.sh" <<INNER
source "\$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || exit 97
_flow_test_begin inner
e2e_new inner
e2e_repo main
e2e_plugin_copy bin/flow-e2e-marker.sh 'echo marker'
( cd "\$E2E_ACTIVE_PLUGIN" && find . -mindepth 1 -maxdepth 2 ! -path './bin/*' ! -path './hooks/*' ! -path './commands/*' ! -path './skills/*' ! -path './agents/*' ! -path './references/*' ! -path './system-one/*' ! -path './templates/*' ! -path './schemas/*' ! -path './workflows/*' ! -path './triggers/*' | LC_ALL=C sort ) > "\$HS_OUT/copy-list"
du -sk "\$E2E_ACTIVE_PLUGIN" | cut -f1 > "\$HS_OUT/copy-kb"
_e2e_plugin_digest "\$E2E_ACTIVE_PLUGIN" > "\$HS_OUT/copy-digest"
rm -f "\$E2E_ACTIVE_PLUGIN/bin/flow-e2e-marker.sh"
_e2e_plugin_digest "\$E2E_ACTIVE_PLUGIN" > "\$HS_OUT/copy-digest-without-marker"
printf '%s\n' "\$E2E_ROOT" > "\$HS_OUT/root"
printf '%s\n' "\$E2E_DIR" > "\$HS_OUT/dir"
$2
$verdict
INNER
}

# _hs_run [env assignments...] — runs the inner file as run.sh runs a file.
_hs_run() {
  HS_OUT="$E2E_DIR/out-inner"
  mkdir -p "$HS_OUT"
  ( cd "$E2E_DIR" && env HOME="$E2E_HOME" TMPDIR="$E2E_DIR/tmp" FLOW_E2E_TMPDIR="$E2E_DIR/tmp" REPO_ROOT="$REPO_ROOT" \
      FLOW_E2E_ARTIFACT_DIR= FLOW_E2E_KEEP_SCRATCH= HS_OUT="$HS_OUT" "$@" \
      bash -c 'source "$1" || exit 98; source "$2"' _ "$REPO_ROOT/plugins/flow/tests/lib/assert.sh" "$E2E_DIR/inner.test.sh" ) \
    > "$E2E_DIR/inner.out" 2> "$E2E_DIR/inner.err"
  HS_ROOT=$(cat "$HS_OUT/root" 2>/dev/null)
  HS_DIR=$(cat "$HS_OUT/dir" 2>/dev/null)
  { printf -- '--- inner stdout\n'; sed "s#$E2E_ROOT_REAL#<scratch>#g; s#$E2E_ROOT#<scratch>#g" "$E2E_DIR/inner.out"
    printf -- '--- inner stderr\n'; sed "s#$E2E_ROOT_REAL#<scratch>#g; s#$E2E_ROOT#<scratch>#g" "$E2E_DIR/inner.err"
    printf -- '--- what the inner run left in TMPDIR\n'
    ( cd "$E2E_DIR/tmp" && find . -mindepth 1 -maxdepth 3 | sed 's#flow-e2e\.[A-Za-z0-9]*#flow-e2e.<id>#' | LC_ALL=C sort ); } | _e2e_art
  [ -n "$HS_ROOT" ] || _e2e_result fail "the inner run reported its scratch root"
}

_hs_ok() { if eval "$1"; then _e2e_result pass "$2"; else _e2e_result fail "$2"; fi; }

# FLOW_E2E_SCENARIOS=a,b runs only the named scenarios.
_want() { [ -z "${FLOW_E2E_SCENARIOS:-}" ] || [[ ",$FLOW_E2E_SCENARIOS," == *",$1,"* ]]; }

PLUGIN_DIGEST=$(_e2e_plugin_digest "$E2E_PLUGIN_DIR")
PLUGIN_KB=$(du -sk "$E2E_PLUGIN_DIR" | cut -f1)

if _want hs-copy; then
  _hs_case hs-copy "H1 H2: a scenario's plugin copy holds all the code the plugin runs (the same code digest once the replaced file is gone, the manifest, references, templates and the eval cases) and neither tests/ nor a recorded eval run"
  _hs_inner pass ''
  _hs_run
  { printf 'plugin: %s KB; copy: %s KB\n' "$PLUGIN_KB" "$(cat "$HS_OUT/copy-kb")"
    printf -- '--- the copy, outside its code directories\n'; cat "$HS_OUT/copy-list"; } | _e2e_art
  e2e_expect_equal "$PLUGIN_DIGEST" "$(cat "$HS_OUT/copy-digest-without-marker")" "code digest of the copy without the replaced file"
  _hs_ok '[ "$(cat "$HS_OUT/copy-digest")" != "$PLUGIN_DIGEST" ]' "the replaced file is in the copy (its digest differs while the file is there)"
  for want in ./.claude-plugin ./.claude-plugin/plugin.json ./references ./templates ./evals ./evals/README.md ./settings.json ./README.md; do
    _hs_ok 'grep -qxF -- "$want" "$HS_OUT/copy-list"' "the copy has $want"
  done
  for d in "$E2E_PLUGIN_DIR"/evals/*/; do
    d=${d%/}; d=${d##*/}
    case "$d" in results-*) continue ;; esac
    _hs_ok 'grep -qxF -- "./evals/$d" "$HS_OUT/copy-list"' "the copy has the eval case evals/$d"
  done
  _hs_ok '! grep -q "^./tests" "$HS_OUT/copy-list"' "the copy has no tests/"
  _hs_ok '! grep -q "^./evals/results-" "$HS_OUT/copy-list"' "the copy has no recorded eval run"
  _hs_ok '[ "$(cat "$HS_OUT/copy-kb")" -lt $((PLUGIN_KB / 2)) ]' "the copy is under half the plugin's size"
  _hs_ok '! grep -q "^FAIL" "$E2E_DIR/inner.out" && grep -q "^PASS .*an expectation that holds" "$E2E_DIR/inner.out"' "the inner run passed"
fi

if _want hs-copy-onto-existing; then
  _hs_case hs-copy-onto-existing "H3: copying the plugin onto a directory that exists fails and leaves that directory as it was"
  mkdir -p "$E2E_DIR/there"
  printf 'x\n' > "$E2E_DIR/there/keep"
  if e2e_copy_plugin "$E2E_PLUGIN_DIR" "$E2E_DIR/there"; then rc=0; else rc=$?; fi
  printf 'exit status: %s\ncontents after: %s\n' "$rc" "$(cd "$E2E_DIR/there" && ls -A | tr '\n' ' ')" | _e2e_art
  _hs_ok '[ "$rc" != 0 ]' "the copy failed"
  e2e_expect_equal "keep" "$(cd "$E2E_DIR/there" && ls -A)" "the directory holds only what it held"
fi

if _want hs-failure-keeps-artifacts-only; then
  _hs_case hs-failure-keeps-artifacts-only "H4 H5 H8: after an expectation fails, the scratch root holds only the artifacts, their path is printed, and a symlink in a scenario to a directory outside is removed without touching that directory"
  printf 'outside\n' > "$E2E_DIR/outside/file"
  chmod 0555 "$E2E_DIR/outside"
  _hs_inner fail "ln -s \"$E2E_DIR/outside\" \"\$E2E_ROOT/link-out\"; ln -s \"$E2E_DIR/outside\" \"\$E2E_DIR/link-out\"; mkdir -p \"\$E2E_DIR/ro/sub\" && chmod 0555 \"\$E2E_DIR/ro\""
  _hs_run
  _hs_ok 'grep -q "artifacts kept in $HS_ROOT/artifacts" "$E2E_DIR/inner.err"' "stderr names the artifacts directory"
  _hs_ok '[ -s "$HS_ROOT/artifacts/inner.txt" ]' "the scenario's artifact is kept"
  _hs_ok 'grep -q "^FAIL expected .*an expectation that fails\|FAIL .*an expectation that fails" "$HS_ROOT/artifacts/inner.txt"' "the artifact records the failed expectation"
  e2e_expect_equal "artifacts" "$(cd "$HS_ROOT" && ls -A)" "what the scratch root holds"
  _hs_ok '[ ! -e "$HS_DIR" ]' "the scenario's repository, home and plugin copy are removed"
  e2e_expect_equal "outside" "$(cat "$E2E_DIR/outside/file" 2>/dev/null)" "the directory a symlink pointed at keeps its file"
  e2e_expect_equal "555" "$(stat -c %a "$E2E_DIR/outside" 2>/dev/null || stat -f %Lp "$E2E_DIR/outside")" "the directory a symlink pointed at keeps its mode"
  chmod 0755 "$E2E_DIR/outside"
fi

if _want hs-failure-keep-scratch; then
  _hs_case hs-failure-keep-scratch "H6: with FLOW_E2E_KEEP_SCRATCH=1 a failed run keeps the whole scratch root, and says where"
  _hs_inner fail ''
  _hs_run FLOW_E2E_KEEP_SCRATCH=1
  _hs_ok 'grep -q "scratch kept in $HS_ROOT" "$E2E_DIR/inner.err"' "stderr names the scratch root"
  _hs_ok '[ -d "$HS_DIR/repo/.git" ] && [ -d "$HS_DIR/plugin/bin" ]' "the scenario's repository and plugin copy are kept"
  _hs_ok '[ -s "$HS_ROOT/artifacts/inner.txt" ]' "the artifact is kept"
fi

if _want hs-pass-leaves-nothing; then
  _hs_case hs-pass-leaves-nothing "H7: a run whose expectations all hold leaves nothing of its scratch root"
  _hs_inner pass ''
  _hs_run
  _hs_ok '[ ! -e "$HS_ROOT" ]' "the scratch root is removed"
  e2e_expect_equal "" "$(cd "$E2E_DIR/tmp" && ls -A)" "what the inner run left in TMPDIR"
  _hs_ok '! grep -q "artifacts kept" "$E2E_DIR/inner.err"' "nothing is reported as kept"
fi

if _want hs-copy-twice; then
  _hs_case hs-copy-twice "H9: a second e2e_plugin_copy in the same scenario replaces its file in the copy the first one made, and nests no second copy inside it"
  _hs_inner pass 'e2e_plugin_copy bin/flow-e2e-marker-2.sh "echo second"
e2e_plugin_copy bin/flow-e2e-marker-3.sh "echo third"
printf "%s\n" "$E2E_ACTIVE_PLUGIN" > "$HS_OUT/active"
cat "$E2E_ACTIVE_PLUGIN/bin/flow-e2e-marker-2.sh" "$E2E_ACTIVE_PLUGIN/bin/flow-e2e-marker-3.sh" > "$HS_OUT/markers"
( cd "$E2E_ACTIVE_PLUGIN" && ls -A ) > "$HS_OUT/top"'
  _hs_run
  { printf -- '--- marker files in the copy\n'; cat "$HS_OUT/markers"; printf -- '--- top of the copy\n'; cat "$HS_OUT/top"; } | _e2e_art
  e2e_expect_equal "$HS_DIR/plugin" "$(cat "$HS_OUT/active")" "the plugin the scenario runs"
  e2e_expect_equal "echo second
echo third" "$(cat "$HS_OUT/markers")" "both replaced files in that copy"
  _hs_ok '! grep -qx plugin "$HS_OUT/top" && ! grep -qx flow "$HS_OUT/top"' "no copy nested inside the copy"
  _hs_ok '! grep -q "cannot copy the plugin" "$E2E_DIR/inner.out"' "no copy failed"
fi

if _want hs-copy-keeps-named; then
  _hs_case hs-copy-keeps-named "H10: a recorded eval run named to e2e_copy_plugin is in the copy, byte for byte, and the other recorded runs are not"
  keep=$(cd "$E2E_PLUGIN_DIR" && ls -d evals/results-* | head -n 1)
  other=$(cd "$E2E_PLUGIN_DIR" && ls -d evals/results-* | sed -n 2p)
  if e2e_copy_plugin "$E2E_PLUGIN_DIR" "$E2E_DIR/copy" "$keep"; then rc=0; else rc=$?; fi
  printf 'named: %s\nexit status: %s\n' "$keep" "$rc" | _e2e_art
  e2e_expect_equal 0 "$rc" "exit status"
  _hs_ok 'diff -r "$E2E_PLUGIN_DIR/$keep" "$E2E_DIR/copy/$keep" >/dev/null' "the named run is copied whole"
  _hs_ok '[ ! -e "$E2E_DIR/copy/$other" ]' "another recorded run is not copied"
  if e2e_copy_plugin "$E2E_PLUGIN_DIR" "$E2E_DIR/copy2" ../outside; then rc=0; else rc=$?; fi
  _hs_ok '[ "$rc" != 0 ]' "a path that leaves the plugin is refused"
fi

# _hs_runner <name of the inner file> — runs tests/run.sh on one file, alone
# (FLOW_TEST_JOBS=1), with TMPDIR at the scenario's tmp directory and no
# FLOW_E2E_TMPDIR, as a run started from a shell has.
_hs_runner() {
  HS_OUT="$E2E_DIR/out-inner"
  mkdir -p "$HS_OUT"
  ( cd "$E2E_DIR" && env -u FLOW_E2E_TMPDIR HOME="$E2E_HOME" TMPDIR="$E2E_DIR/tmp" FLOW_TEST_JOBS=1 \
      FLOW_TEST_TIMES="$E2E_DIR/times" FLOW_E2E_ARTIFACT_DIR= FLOW_E2E_KEEP_SCRATCH= HS_OUT="$HS_OUT" \
      "$REPO_ROOT/plugins/flow/tests/run.sh" "$E2E_DIR/$1" ) > "$E2E_DIR/inner.out" 2> "$E2E_DIR/inner.err"
  HS_RC=$?
  { printf -- '--- run.sh exit status: %s\n' "$HS_RC"
    printf -- '--- run.sh output\n'; sed "s#$E2E_ROOT_REAL#<scratch>#g; s#$E2E_ROOT#<scratch>#g" "$E2E_DIR/inner.out" "$E2E_DIR/inner.err"
    printf -- '--- what the run left in TMPDIR\n'
    ( cd "$E2E_DIR/tmp" && find . -mindepth 1 -maxdepth 3 | sed -E 's#\.[A-Za-z0-9]{6}#.<id>#g' | LC_ALL=C sort ); } | _e2e_art
}

if _want hs-runner-file-tmp; then
  _hs_case hs-runner-file-tmp "H11 H12: a test file run by run.sh gets a TMPDIR of its own inside the run's, and what it leaves there is removed when the file ends"
  cat > "$E2E_DIR/leaky.test.sh" <<'LEAKY'
d=$(mktemp -d "${TMPDIR:-/tmp}/leaky.XXXXXX") && printf 'x\n' > "$d/f"
mktemp "${TMPDIR:-/tmp}/leaky-file.XXXXXX" >/dev/null
printf '%s\n' "$TMPDIR" > "$HS_OUT/file-tmpdir"
_flow_test_begin leaky
_flow_assert_pass "made a directory and a file in TMPDIR and left them"
LEAKY
  _hs_runner leaky.test.sh
  e2e_expect_equal 0 "$HS_RC" "run.sh exit status"
  ft=$(cat "$HS_OUT/file-tmpdir" 2>/dev/null)
  _hs_ok 'case "$ft" in "$E2E_DIR/tmp/flow-test-tmp."*) true ;; *) false ;; esac' "the file saw a TMPDIR of its own inside the run's ($ft)"
  e2e_expect_equal "" "$(cd "$E2E_DIR/tmp" && ls -A)" "what the run left in TMPDIR"
fi

if _want hs-runner-failed-artifacts; then
  _hs_case hs-runner-failed-artifacts "H12: a failed e2e file run by run.sh keeps its artifacts in the run's TMPDIR, at the path it prints, while what the file left in its own TMPDIR is removed"
  cat > "$E2E_DIR/failing.test.sh" <<'FAILING'
source "$REPO_ROOT/plugins/flow/tests/lib/e2e.sh" || exit 97
mktemp -d "${TMPDIR:-/tmp}/leaky.XXXXXX" >/dev/null
_flow_test_begin failing
e2e_new failing
e2e_expect_equal expected actual "an expectation that fails"
FAILING
  _hs_runner failing.test.sh
  e2e_expect_equal 1 "$HS_RC" "run.sh exit status"
  kept=$(sed -n 's/^e2e: an expectation failed; artifacts kept in \([^ ]*\).*/\1/p' "$E2E_DIR/inner.err" "$E2E_DIR/inner.out" | head -n 1)
  _hs_ok 'case "$kept" in "$E2E_DIR/tmp/flow-e2e."*/artifacts) true ;; *) false ;; esac' "the printed artifacts path is in the run's TMPDIR ($kept)"
  _hs_ok '[ -s "$kept/failing.txt" ]' "the artifact is there"
  e2e_expect_equal "flow-e2e" "$(cd "$E2E_DIR/tmp" && ls -A | sed 's/\..*//')" "what the run left in TMPDIR"
fi

if _want hs-runner-nested-killed; then
  _hs_case hs-runner-nested-killed "H13: a test file that starts run.sh on a file which kills that run.sh with SIGKILL leaves nothing in the outer run's TMPDIR"
  printf '%s\n' 'kill -9 $$' > "$E2E_DIR/killer.test.sh"
  cat > "$E2E_DIR/outer.test.sh" <<OUTER
"\$REPO_ROOT/plugins/flow/tests/run.sh" "$E2E_DIR/killer.test.sh" >/dev/null 2>&1
_flow_test_begin outer
_flow_assert_pass "started run.sh on a file that kills it"
OUTER
  _hs_runner outer.test.sh
  e2e_expect_equal 0 "$HS_RC" "run.sh exit status"
  e2e_expect_equal "" "$(cd "$E2E_DIR/tmp" && ls -A)" "what the run left in TMPDIR"
fi
