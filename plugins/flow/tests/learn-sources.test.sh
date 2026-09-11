# Tests for where /flow:learn looks for its evidence (issues #168, #169).
#
# Both are the same shape of defect: a path resolved against one assumption,
# with no signal when the assumption is wrong. The miner probed a single
# transcript root and reported "missing" on a machine using the other layout, so
# /flow:learn ran its whole correction phase against zero rows and said nothing
# was wrong. The promoter resolved its target against the current repository, so
# promoting from a project that merely uses flow would have added a plugins/flow
# tree to it and opened a pull request its reviewers had no context for.
#
# What makes both dangerous is that the failure is silent and the output looks
# healthy. So the assertions here are as much about what gets SAID as about
# where the paths land.

MINER="$REPO_ROOT/plugins/flow/bin/flow-mine-corrections.sh"
PROMOTER="$REPO_ROOT/plugins/flow/bin/promote-proposal.sh"

LS_CLEANUP=()
_ls_cleanup() {
  local p
  for p in "${LS_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done
}
trap _ls_cleanup EXIT

_ls_tmp() {
  local d
  d=$(mktemp -d -t flow-learn-src.XXXXXX 2>/dev/null) || { printf ''; return 1; }
  LS_CLEANUP+=("$d")
  printf '%s' "$d"
}

# A project dir plus a transcript for it under <root>/<slug>.
_ls_seed() {
  local root="$1" proj="$2" slug
  slug=$(printf '%s' "$proj" | sed 's/[^A-Za-z0-9]/-/g')
  mkdir -p "$root/$slug"
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"no, that is wrong, do it the other way instead"},"timestamp":"2026-09-01T10:00:00Z"}' \
    > "$root/$slug/session.jsonl"
}

# ---------------------------------------------------------------------------
# #168 — the transcript root is a list
# ---------------------------------------------------------------------------
_flow_test_begin "transcripts under the second known root are found"
BASE=$(_ls_tmp)
if [ -z "$BASE" ]; then
  _flow_assert_fail "mktemp failed"
  return 0
fi
PROJ="$BASE/proj"; mkdir -p "$PROJ"
mkdir -p "$BASE/home/.claude/projects"          # first root: exists, holds nothing
_ls_seed "$BASE/home/.claude-work/projects" "$PROJ"   # second root: holds the transcript
OUT=$(HOME="$BASE/home" "$MINER" --project-dir "$PROJ" --format markdown 2>/dev/null)
if printf '%s' "$OUT" | grep -q 'TRANSCRIPT_DIR_STATE=ok'; then
  _flow_assert_pass "the second root is probed, not just the first"
else
  _flow_assert_fail "the transcript under .claude-work was not found:
$OUT"
fi
assert_contains ".claude-work/projects" "$OUT" "and the resolved path is reported"

# The production shape, and the one the shipped -d probe got wrong: the first
# root's slug directory EXISTS but holds no transcripts (on the machine that
# reported #168 it holds only a memory/ subdirectory), while the second root
# holds them. A directory-existence probe picks the first and reports
# TRANSCRIPT_STATE=ok with zero sessions, which reads as "found and empty" —
# the exact confusion the issue is about. This test fails on that probe.
_flow_test_begin "an existing but transcript-less first root does not win"
BASE1B=$(_ls_tmp)
PROJ1B="$BASE1B/proj"; mkdir -p "$PROJ1B"
SLUG1B=$(printf '%s' "$PROJ1B" | sed 's/[^A-Za-z0-9]/-/g')
mkdir -p "$BASE1B/home/.claude/projects/$SLUG1B/memory"   # exists, no .jsonl
_ls_seed "$BASE1B/home/.claude-work/projects" "$PROJ1B"
OUT=$(HOME="$BASE1B/home" "$MINER" --project-dir "$PROJ1B" --format markdown 2>/dev/null)
assert_contains "TRANSCRIPT_DIR_STATE=ok" "$OUT" "the transcripts are found"
if printf '%s' "$OUT" | grep -q '\.claude-work/projects'; then
  _flow_assert_pass "the root holding transcripts wins over one that merely exists"
else
  _flow_assert_fail "picked a root with no transcripts in it:
$OUT"
fi
if printf '%s' "$OUT" | grep -q 'SESSION_COUNT=0'; then
  _flow_assert_fail "reported zero sessions while a root held transcripts — the silent-loss shape"
else
  _flow_assert_pass "sessions are counted"
fi

# A project with no transcripts anywhere still reports a path someone can look
# at, rather than inventing one.
_flow_test_begin "a genuinely empty project reports the directory that exists"
BASE1C=$(_ls_tmp)
PROJ1C="$BASE1C/proj"; mkdir -p "$PROJ1C"
SLUG1C=$(printf '%s' "$PROJ1C" | sed 's/[^A-Za-z0-9]/-/g')
mkdir -p "$BASE1C/home/.claude-work/projects/$SLUG1C"
OUT=$(HOME="$BASE1C/home" "$MINER" --project-dir "$PROJ1C" --format markdown 2>/dev/null)
assert_contains ".claude-work/projects" "$OUT" "the existing directory is the one reported"

_flow_test_begin "the first root still wins when it has the transcript"
BASE2=$(_ls_tmp)
PROJ2="$BASE2/proj"; mkdir -p "$PROJ2"
_ls_seed "$BASE2/home/.claude/projects" "$PROJ2"
_ls_seed "$BASE2/home/.claude-work/projects" "$PROJ2"
OUT=$(HOME="$BASE2/home" "$MINER" --project-dir "$PROJ2" --format markdown 2>/dev/null)
assert_contains "/.claude/projects/" "$OUT" "the first matching root is used"
if printf '%s' "$OUT" | grep -q '\.claude-work'; then
  _flow_assert_fail "the second root was used while the first matched"
else
  _flow_assert_pass "the second root is not consulted once the first matches"
fi

_flow_test_begin "an explicit override still wins outright"
BASE3=$(_ls_tmp)
PROJ3="$BASE3/proj"; mkdir -p "$PROJ3"
_ls_seed "$BASE3/home/.claude/projects" "$PROJ3"
_ls_seed "$BASE3/elsewhere" "$PROJ3"
OUT=$(HOME="$BASE3/home" CLAUDE_TRANSCRIPT_DIR="$BASE3/elsewhere" "$MINER" --project-dir "$PROJ3" --format markdown 2>/dev/null)
assert_contains "$BASE3/elsewhere" "$OUT" "CLAUDE_TRANSCRIPT_DIR overrides the list"
SLUG3=$(printf '%s' "$PROJ3" | sed 's/[^A-Za-z0-9]/-/g')
OUT=$(HOME="$BASE3/home" "$MINER" --project-dir "$PROJ3" --transcript-dir "$BASE3/elsewhere/$SLUG3" --format markdown 2>/dev/null)
assert_contains "$BASE3/elsewhere" "$OUT" "--transcript-dir overrides the list"

# The point of the issue: a directory that was never found must not read the
# same as a directory that was found and is empty.
_flow_test_begin "when nothing matches, every root that was tried is named"
BASE4=$(_ls_tmp)
PROJ4="$BASE4/proj"; mkdir -p "$PROJ4"
ERRF="$BASE4/err"
OUT=$(HOME="$BASE4/home" "$MINER" --project-dir "$PROJ4" --format markdown 2>"$ERRF")
ERR=$(cat "$ERRF")
assert_contains "TRANSCRIPT_DIR_STATE=missing" "$OUT" "state is missing"
assert_contains "TRANSCRIPT_ROOTS_TRIED=" "$OUT" "the roots tried are reported as a field"
assert_contains ".claude/projects" "$OUT" "the first root is named"
assert_contains ".claude-work/projects" "$OUT" "the second root is named"
assert_contains "any known root" "$ERR" "and stderr says no root matched"

_flow_test_begin "a named directory that is absent says so in its own words"
BASE5=$(_ls_tmp)
ERRF5="$BASE5/err"
OUT=$("$MINER" --transcript-dir "$BASE5/nope" --format markdown 2>"$ERRF5")
assert_contains "transcript dir not found" "$(cat "$ERRF5")" "the caller named it, so the message names it back"
if printf '%s' "$(cat "$ERRF5")" | grep -q "any known root"; then
  _flow_assert_fail "the roots-list wording leaked into the explicit-override case"
else
  _flow_assert_pass "the roots-list wording is not used when no roots were searched"
fi

# ---------------------------------------------------------------------------
# #169 — promotion lands in flow's repository, or refuses
# ---------------------------------------------------------------------------
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c "import yaml" >/dev/null 2>&1; then
  _flow_test_begin "promote-proposal prerequisites"
  _flow_assert_pass "SKIP: python3 with PyYAML not available"
  return 0
fi

PROPOSAL_FIXTURE="$REPO_ROOT/tests/skills/promote-proposal-fixture.md"
if [ ! -f "$PROPOSAL_FIXTURE" ]; then
  PROPOSAL_FIXTURE=$(find "$REPO_ROOT/tests" "$REPO_ROOT/plugins/flow/tests" -name 'promote-proposal-fixture.md' 2>/dev/null | head -1)
fi
if [ -z "$PROPOSAL_FIXTURE" ] || [ ! -f "$PROPOSAL_FIXTURE" ]; then
  _flow_test_begin "promote-proposal fixture"
  _flow_assert_pass "SKIP: no proposal fixture found"
  return 0
fi

# A repository that uses flow but is not flow: it even has its own plugins/
# directory, which is the shape that made the original defect invisible.
_ls_consumer() {
  local d="$1"
  mkdir -p "$d/plugins/someother"
  ( cd "$d" && git init -q . && git config user.email t@t.test && git config user.name tester \
    && : > f && git add f && git commit -qm init ) >/dev/null 2>&1
}

_flow_test_begin "promoting from a consuming project does not target that project"
CONS=$(_ls_tmp)/consumer
mkdir -p "$CONS"
_ls_consumer "$CONS"
OUT=$( cd "$CONS" && "$PROMOTER" --proposal "$PROPOSAL_FIXTURE" --dry-run 2>&1 )
RC=$?
# rc=0 is the only correct outcome: the promoter lives inside $REPO_ROOT, so
# resolution path 3 must find it. An earlier version of this assertion also
# accepted rc=2, which meant it passed both when the walk-up worked and when it
# was broken — including the worktree case, where requiring a .git DIRECTORY
# rejected a legitimate checkout.
if printf '%s' "$OUT" | grep -q "$CONS/plugins/flow"; then
  _flow_assert_fail "the promotion targeted the consuming project:
$OUT"
elif [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "$REPO_ROOT/plugins/flow/skills/learned"; then
  _flow_assert_pass "it resolved to the flow checkout holding the script"
else
  _flow_assert_fail "expected exit 0 targeting $REPO_ROOT, got exit $RC:
$OUT"
fi

_flow_test_begin "the dry run says which checkout it resolved and how"
OUT=$( cd "$CONS" && "$PROMOTER" --proposal "$PROPOSAL_FIXTURE" --dry-run 2>&1 )
if printf '%s' "$OUT" | grep -q "flow checkout:"; then
  _flow_assert_pass "the resolved checkout is printed"
else
  _flow_assert_fail "a dry run that does not name its target cannot answer the question it is asked:
$OUT"
fi

_flow_test_begin "no plugins/flow tree is created in a repository that had none"
if [ -e "$CONS/plugins/flow" ]; then
  _flow_assert_fail "a plugins/flow tree appeared in the consuming project"
else
  _flow_assert_pass "the consuming project is untouched"
fi

_flow_test_begin "FLOW_REPO_ROOT overrides, and is validated"
OUT=$( cd "$CONS" && FLOW_REPO_ROOT="$REPO_ROOT" "$PROMOTER" --proposal "$PROPOSAL_FIXTURE" --dry-run 2>&1 )
assert_contains "FLOW_REPO_ROOT" "$OUT" "an explicit root is reported as the source"
OUT=$( cd "$CONS" && FLOW_REPO_ROOT="$CONS" "$PROMOTER" --proposal "$PROPOSAL_FIXTURE" --dry-run 2>&1 )
RC=$?
if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q "not a flow checkout"; then
  _flow_assert_pass "a FLOW_REPO_ROOT that is not a flow checkout is refused"
else
  _flow_assert_fail "an invalid FLOW_REPO_ROOT was accepted (exit $RC):
$OUT"
fi

_flow_test_begin "a copy of the script outside any flow checkout refuses"
ISO=$(_ls_tmp)
cp -R "$REPO_ROOT/plugins/flow/bin" "$ISO/bin" 2>/dev/null
_ls_consumer "$ISO"
OUT=$( cd "$ISO" && "$ISO/bin/promote-proposal.sh" --proposal "$PROPOSAL_FIXTURE" --dry-run 2>&1 )
RC=$?
if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q "could not find a flow checkout"; then
  _flow_assert_pass "exit 2 with the reason, rather than writing somewhere wrong"
else
  _flow_assert_fail "expected a refusal with exit 2, got $RC:
$OUT"
fi
