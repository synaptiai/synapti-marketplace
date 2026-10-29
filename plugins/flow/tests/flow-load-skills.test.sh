# Tests for bin/flow-load-skills.sh and the command loader convention.
#
# Contract under test:
#   - ambient skills (no context: fork / agent:) are inlined whole
#   - dispatched skills (context: fork or agent:) inline only `## Contract`
#   - a dispatched skill without `## Contract` is a SKILL_LOAD_ERROR
#   - missing / invalid names are SKILL_LOAD_ERROR, exit stays 0 in load mode
#   - --check exits 1 on any problem, 0 when clean
#   - every command's `## Required Skills` bullets match its loader block
#   - every dispatched skill any command requires has a `## Contract` section
#     of at most 120 words

LOADER="$REPO_ROOT/plugins/flow/bin/flow-load-skills.sh"
COMMANDS_DIR="$REPO_ROOT/plugins/flow/commands"
SKILLS_DIR="$REPO_ROOT/plugins/flow/skills"

FIX=$(mktemp -d -t flow-load-skills.XXXXXX)
trap 'rm -rf "$FIX"' EXIT

mkdir -p "$FIX/ambient-one" "$FIX/forked-one" "$FIX/forked-nocontract" "$FIX/agent-one"
cat > "$FIX/ambient-one/SKILL.md" <<'EOF'
---
name: ambient-one
description: "Ambient fixture."
allowed-tools: Read
---

# Ambient One

## Iron Law

Always cite file:line.

## Contract

This section must NOT be treated specially for ambient skills.
EOF
cat > "$FIX/forked-one/SKILL.md" <<'EOF'
---
name: forked-one
description: "Forked fixture."
context: fork
agent: general-purpose
---

# Forked One

## Contract

Invoke at Phase 4. Returns PASS or findings. No skips.

## Process

Long process text that must not be inlined.
EOF
cat > "$FIX/forked-nocontract/SKILL.md" <<'EOF'
---
name: forked-nocontract
description: "Forked fixture without a contract."
context: fork
---

# Forked No Contract

## Process

Body only.
EOF
cat > "$FIX/agent-one/SKILL.md" <<'EOF'
---
name: agent-one
description: "Agent fixture."
agent: Explore
---

# Agent One

## Contract

Runs as Explore. Returns a table.
EOF

# --- ambient skill: whole body inlined, Contract heading not special
_flow_test_begin "ambient skill is inlined whole"
OUT=$(FLOW_SKILLS_DIR="$FIX" bash "$LOADER" ambient-one 2>&1); RC=$?
assert_exit 0 "$RC" "load mode exits 0"
assert_contains "### Loaded Skills" "$OUT" "section heading present"
assert_match '^SKILL_LOADED=ambient-one mode=ambient words=[0-9]+$' "$OUT" "record line for ambient skill"
assert_contains "#### Skill: ambient-one (ambient" "$OUT" "ambient sub-heading"
assert_contains "Always cite file:line." "$OUT" "body content inlined"
assert_contains "must NOT be treated specially" "$OUT" "ambient body keeps its own Contract text"
assert_not_contains "name: ambient-one" "$OUT" "frontmatter stripped"

# --- dispatched skill: only the Contract section
_flow_test_begin "dispatched skill inlines only its Contract section"
OUT=$(FLOW_SKILLS_DIR="$FIX" bash "$LOADER" forked-one agent-one 2>&1)
assert_match 'SKILL_LOADED=forked-one mode=contract words=[0-9]+' "$OUT" "forked record"
assert_match 'SKILL_LOADED=agent-one mode=contract words=[0-9]+' "$OUT" "agent: record"
assert_contains "Invoke at Phase 4. Returns PASS or findings. No skips." "$OUT" "contract text inlined"
assert_not_contains "Long process text" "$OUT" "process body NOT inlined"
assert_contains "Skill(forked-one)" "$OUT" "sub-heading names the Skill() dispatch"

# --- dispatched skill without Contract → error, exit 0 in load mode
_flow_test_begin "dispatched skill without Contract is an error record"
OUT=$(FLOW_SKILLS_DIR="$FIX" bash "$LOADER" forked-nocontract 2>&1); RC=$?
assert_exit 0 "$RC" "load mode still exits 0"
assert_contains "SKILL_LOAD_ERROR=forked-nocontract reason=no-contract-section" "$OUT" "error record"
assert_not_contains "Body only." "$OUT" "body not inlined as fallback"

# --- missing and invalid names
_flow_test_begin "missing and invalid skill names"
OUT=$(FLOW_SKILLS_DIR="$FIX" bash "$LOADER" nope "../etc" 2>&1)
assert_contains "SKILL_LOAD_ERROR=nope reason=not-found" "$OUT" "missing skill"
assert_contains "SKILL_LOAD_ERROR=../etc reason=invalid-name" "$OUT" "path traversal rejected"

# --- --check mode
_flow_test_begin "--check exits 1 on problems and 0 when clean"
FLOW_SKILLS_DIR="$FIX" bash "$LOADER" --check ambient-one forked-one >/dev/null 2>&1
assert_exit 0 "$?" "clean set → 0"
FLOW_SKILLS_DIR="$FIX" bash "$LOADER" --check ambient-one forked-nocontract >/dev/null 2>&1
assert_exit 1 "$?" "no-contract → 1"
FLOW_SKILLS_DIR="$FIX" bash "$LOADER" --check nope >/dev/null 2>&1
assert_exit 1 "$?" "missing → 1"
OUT=$(FLOW_SKILLS_DIR="$FIX" bash "$LOADER" --list forked-one 2>&1)
assert_not_contains "Invoke at Phase 4" "$OUT" "--list prints no bodies"

# --- no args → usage error
_flow_test_begin "no arguments is a usage error"
bash "$LOADER" >/dev/null 2>&1
assert_exit 2 "$?" "exit 2 without names"

# --- Convention over the real plugin: every command's Required Skills list
# matches its loader block, and every dispatched required skill has a Contract.
_flow_test_begin "commands load exactly their Required Skills"
CHECKED=0
for FILE in "$COMMANDS_DIR"/*.md; do
  CMD=$(basename "$FILE" .md)
  # Bullets under ## Required Skills: `- \`skill-name\` — ...`
  REQUIRED=$(awk '
    /^## Required Skills/ { in_section=1; next }
    in_section && /^## / { in_section=0 }
    in_section && /^- `[a-z0-9-]+`/ { s=$0; sub(/^- `/, "", s); sub(/`.*$/, "", s); print s }
  ' "$FILE" | sort -u)
  # Skills named in the loader block: the flow-load-skills.sh invocation line(s)
  # The invocation line ends in `/bin/flow-load-skills.sh" name name ...`;
  # comment lines mention the script without the closing quote and are ignored.
  LOADED=$(grep -E 'flow-load-skills\.sh" ' "$FILE" \
    | sed -E 's/.*flow-load-skills\.sh" *//' \
    | tr ' ' '\n' | grep -E '^[a-z0-9-]+$' | sort -u)
  if [ -z "$REQUIRED" ]; then
    # Commands with the `_None — ...` marker must not carry a loader block.
    if [ -n "$LOADED" ]; then
      _flow_assert_fail "$CMD.md has no Required Skills bullets but loads: $LOADED"
    fi
    continue
  fi
  CHECKED=$((CHECKED + 1))
  if [ "$REQUIRED" != "$LOADED" ]; then
    _flow_assert_fail "$CMD.md Required Skills != loader block. required=[$(echo $REQUIRED)] loaded=[$(echo $LOADED)]"
    continue
  fi
  # shellcheck disable=SC2086
  if ! OUT=$(bash "$LOADER" --check $REQUIRED 2>&1); then
    _flow_assert_fail "$CMD.md loader --check failed: $(echo "$OUT" | grep SKILL_LOAD_ERROR | tr '\n' ' ')"
    continue
  fi
  _flow_assert_pass "$CMD.md loads its $(echo $REQUIRED | wc -w | tr -d ' ') required skills"
done
if [ "$CHECKED" -lt 15 ]; then
  _flow_assert_fail "only $CHECKED commands had Required Skills bullets (expected most of them)"
fi

# --- every dispatched skill has a Contract of at most 120 words, placed first
_flow_test_begin "dispatched skills carry a short Contract as their first H2"
SCANNED=0
for FILE in "$SKILLS_DIR"/*/SKILL.md; do
  NAME=$(basename "$(dirname "$FILE")")
  FM=$(awk 'NR==1 && /^---$/ {fm=1; next} fm==1 { if (/^---$/) exit; print }' "$FILE")
  printf '%s\n' "$FM" | grep -qE '^(context:[[:space:]]*fork|agent:[[:space:]]*[^[:space:]])' || continue
  SCANNED=$((SCANNED + 1))
  FIRST_H2=$(awk 'BEGIN{fm=0} NR==1 && /^---$/ {fm=1; next} fm==1 { if (/^---$/) {fm=2}; next } /^## / {print; exit}' "$FILE")
  if [ "$FIRST_H2" != "## Contract" ]; then
    _flow_assert_fail "$NAME: first H2 is '$FIRST_H2', expected '## Contract'"
    continue
  fi
  WORDS=$(awk 'BEGIN{fm=0} NR==1 && /^---$/ {fm=1; next} fm==1 { if (/^---$/) {fm=2}; next } /^## Contract[[:space:]]*$/ {on=1; next} on && /^## / {exit} on {print}' "$FILE" | wc -w | tr -d ' ')
  if [ "$WORDS" -gt 120 ]; then
    _flow_assert_fail "$NAME: Contract is $WORDS words (max 120)"
    continue
  fi
  _flow_assert_pass "$NAME: Contract first, $WORDS words"
done
if [ "$SCANNED" -lt 20 ]; then
  _flow_assert_fail "only $SCANNED dispatched skills scanned (expected 20+)"
fi

# --- promoted learned skills are held to the same shape as hand-written ones
# The two loops above glob "$SKILLS_DIR"/*/SKILL.md, which never reaches
# learned/<name>/SKILL.md one level deeper, so nothing here saw a promoted
# skill at all. Two separate load paths reach one: Claude Code's own plugin
# discovery, and this repo's flow-load-skills.sh via its learned/ fallback
# (asserted below — without it the budget enforced here would apply to a load
# path that does not exist). Both mean the same budgets apply, and none of the
# proposal scaffolding, which belongs in the promotion PR.
# Count words the way bin/promote-proposal.sh does. `wc -w` and python
# str.split() split differently on unicode whitespace — U+180E splits under BSD
# wc but not under python, so a body the promoter measured at 600 came to 850
# here. The budget a promotion is accepted against has to be the budget CI
# applies, so this defers to python and falls back to wc only without it.
_fls_wordcount() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys; print(len(sys.stdin.read().split()))'
  else
    wc -w | tr -d ' '
  fi
}

# --- every shipped skill: body at most 600 words, Contract at most 120
# The budget references/skill-manifests.md states for every skill, counted the
# way the learned-skill check below counts: frontmatter stripped, words by
# _fls_wordcount. _fls_size_problems prints what is over, or nothing.
FLS_MAX_BODY=600
FLS_MAX_CONTRACT=120
_fls_size_problems() {
  local body bw cw p=""
  body=$(awk 'BEGIN{fm=0} NR==1 && /^---$/ {fm=1; next} fm==1 { if (/^---$/) {fm=2}; next } {print}' "$1")
  bw=$(printf '%s\n' "$body" | _fls_wordcount)
  cw=$(printf '%s\n' "$body" | awk '/^## Contract[[:space:]]*$/ {on=1; next} on && /^## / {exit} on {print}' | _fls_wordcount)
  [ "$bw" -le "$FLS_MAX_BODY" ] || p="$p; body is $bw words (max $FLS_MAX_BODY)"
  [ "$cw" -le "$FLS_MAX_CONTRACT" ] || p="$p; Contract is $cw words (max $FLS_MAX_CONTRACT)"
  printf '%s' "${p#; }"
}

# The check on skills built to sit exactly at and one word over each limit, so
# a raised limit or a miscount fails here even when every shipped skill fits.
# Each fixture body is "# T", a "## Contract" heading, the contract words, a
# "## Body" heading and the body words: 6 words of headings.
_flow_test_begin "the size check: 600/120 pass, 601 body or 121 Contract fail"
SIZE_FIX="$FIX/size"
_fls_size_fixture() {  # <name> <contract words> <other body words>
  mkdir -p "$SIZE_FIX/$1"
  python3 - "$SIZE_FIX/$1/SKILL.md" "$1" "$2" "$3" <<'PY'
import sys
path, name, c, b = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
with open(path, "w", encoding="utf-8") as f:
    f.write("---\nname: %s\ndescription: \"fixture words that are not counted\"\nagent: Explore\n---\n\n" % name)
    f.write("# T\n\n## Contract\n\n%s\n\n## Body\n\n%s\n" % (" ".join(["c"] * c), " ".join(["w"] * b)))
PY
}
_fls_size_fixture at-limit 120 474        # 6 + 120 + 474 = 600
_fls_size_fixture body-over 120 475       # 601
_fls_size_fixture contract-over 121 10    # Contract 121, body 137
assert_equal "" "$(_fls_size_problems "$SIZE_FIX/at-limit/SKILL.md")" "a 600-word body with a 120-word Contract passes"
assert_equal "body is 601 words (max 600)" "$(_fls_size_problems "$SIZE_FIX/body-over/SKILL.md")" "a 601-word body fails"
assert_equal "Contract is 121 words (max 120)" "$(_fls_size_problems "$SIZE_FIX/contract-over/SKILL.md")" "a 121-word Contract fails"

_flow_test_begin "every shipped skill: body at most 600 words, Contract at most 120"
SIZE_SCANNED=0
SIZE_OVER=""
for FILE in "$SKILLS_DIR"/*/SKILL.md; do
  [ -f "$FILE" ] || continue
  SIZE_SCANNED=$((SIZE_SCANNED + 1))
  NAME=$(basename "$(dirname "$FILE")")
  P=$(_fls_size_problems "$FILE")
  if [ -n "$P" ]; then
    SIZE_OVER="$SIZE_OVER $NAME"
    _flow_assert_fail "$NAME: $P"
  else
    _flow_assert_pass "$NAME: within $FLS_MAX_BODY / $FLS_MAX_CONTRACT words"
  fi
done
# Every skill on disk one level under skills/ was checked: a loop that skipped
# one, or a glob that reached none, would otherwise pass.
SIZE_FOUND=$(find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | wc -l | tr -d ' ')
if [ "$SIZE_SCANNED" -eq "$SIZE_FOUND" ] && [ "$SIZE_FOUND" -gt 0 ]; then
  _flow_assert_pass "checked $SIZE_SCANNED of $SIZE_FOUND shipped skills"
else
  _flow_assert_fail "checked $SIZE_SCANNED shipped skills but $SIZE_FOUND are on disk"
fi
[ -z "$SIZE_OVER" ] || printf 'over the limit:%s\n' "$SIZE_OVER" >&2

_flow_test_begin "promoted learned skills carry skill shape, not proposal shape"
if [ -d "$SKILLS_DIR/learned" ]; then
  _flow_assert_pass "$SKILLS_DIR/learned exists — the walk below has somewhere to go"
else
  _flow_assert_fail "$SKILLS_DIR/learned is missing; the counts below would both be 0 and pass vacuously"
fi
LEARNED_FOUND=$(find "$SKILLS_DIR/learned" -name SKILL.md -type f 2>/dev/null | wc -l | tr -d ' ')
LEARNED_SCANNED=0
for FILE in "$SKILLS_DIR"/learned/*/SKILL.md; do
  [ -f "$FILE" ] || continue
  LEARNED_SCANNED=$((LEARNED_SCANNED + 1))
  NAME=$(basename "$(dirname "$FILE")")
  BODY=$(awk 'BEGIN{fm=0} NR==1 && /^---$/ {fm=1; next} fm==1 { if (/^---$/) {fm=2}; next } {print}' "$FILE")
  # Every property is evaluated and reported together. Short-circuiting on the
  # first failure lets one assertion mask another: a leftover "## Promotion
  # Checklist" also pushes the body over the word budget, so a word-count
  # failure reported first would hide the scaffolding that caused it.
  PROBLEMS=""
  # Title only, trailing whitespace stripped: bin/promote-proposal.sh matches on
  # the stripped title, so comparing the raw line here made a `## Contract `
  # heading promote cleanly and then fail CI. Two gates, one definition.
  FIRST_H2=$(printf '%s\n' "$BODY" | awk '/^## /{sub(/^##[ \t]+/,""); sub(/[ \t]+$/,""); print; exit}')
  [ "$FIRST_H2" = "Contract" ] || PROBLEMS="$PROBLEMS; first H2 is '$FIRST_H2', expected 'Contract'"
  CWORDS=$(printf '%s\n' "$BODY" | awk '/^## Contract[[:space:]]*$/ {on=1; next} on && /^## / {exit} on {print}' | _fls_wordcount)
  [ "$CWORDS" -le 120 ] || PROBLEMS="$PROBLEMS; Contract is $CWORDS words (max 120)"
  BWORDS=$(printf '%s\n' "$BODY" | _fls_wordcount)
  [ "$BWORDS" -le 600 ] || PROBLEMS="$PROBLEMS; body is $BWORDS words (max 600)"
  LEFTOVER=$(printf '%s\n' "$BODY" | grep -E '^## (Promotion Checklist|Evidence|Pattern Detected)$' | tr '\n' ' ')
  [ -z "$LEFTOVER" ] || PROBLEMS="$PROBLEMS; proposal scaffolding survived promotion: $LEFTOVER"
  if [ -n "$PROBLEMS" ]; then
    _flow_assert_fail "learned/$NAME:${PROBLEMS#;}"
  else
    _flow_assert_pass "learned/$NAME: Contract first ($CWORDS w), body $BWORDS w, no proposal sections"
  fi
done
# The loops above could pass by reaching nothing. Assert the walk saw every file
# that is actually there rather than asserting a non-zero count, because an empty
# learned/ is a legitimate state.
if [ "$LEARNED_SCANNED" -eq "$LEARNED_FOUND" ]; then
  _flow_assert_pass "scanned $LEARNED_SCANNED of $LEARNED_FOUND learned skills on disk"
else
  # Name the paths, not just the counts: "1 of 4" does not tell anyone which
  # three the glob could not reach. Reachable means exactly
  # learned/<name>/SKILL.md, so anything at another depth is what is missing.
  MISSED=$(find "$SKILLS_DIR/learned" -name SKILL.md -type f 2>/dev/null \
    | sed "s#^$SKILLS_DIR/##" \
    | awk -F/ 'NF != 3 { printf "%s ", $0 }')
  _flow_assert_fail "scanned $LEARNED_SCANNED learned skills but $LEARNED_FOUND exist on disk; unreachable: ${MISSED:-(could not determine)}"
fi

# --- the loader reaches a promoted skill by its plain name
# flow-load-skills.sh resolves ${SKILLS_DIR}/${NAME}/SKILL.md and rejects any
# name containing a slash, so before the learned/ fallback neither
# `a-check-that-can-only-confirm` nor `learned/a-check-that-can-only-confirm`
# could resolve: not-found and invalid-name respectively.
_flow_test_begin "flow-load-skills.sh resolves a promoted learned skill"
LOADER="$REPO_ROOT/plugins/flow/bin/flow-load-skills.sh"
if [ ! -x "$LOADER" ] && [ ! -f "$LOADER" ]; then
  _flow_assert_fail "missing $LOADER"
else
  FIRST_LEARNED=$(find "$SKILLS_DIR/learned" -name SKILL.md -type f 2>/dev/null | head -1)
  if [ -z "$FIRST_LEARNED" ]; then
    _flow_assert_pass "SKIP: no promoted skill to resolve"
  else
    LNAME=$(basename "$(dirname "$FIRST_LEARNED")")
    LOUT=$(bash "$LOADER" --check "$LNAME" 2>&1)
    assert_contains "SKILL_LOADED=$LNAME" "$LOUT" "resolves by plain name"
    # Must-stay-silent: the fallback must not become a traversal.
    TOUT=$(bash "$LOADER" --check "../../../etc/passwd" 2>&1)
    assert_contains "reason=invalid-name" "$TOUT" "a traversing name is still refused"
    # Input removal: a name that exists nowhere must still be not-found, or the
    # fallback would be resolving something it invented.
    NOUT=$(bash "$LOADER" --check "definitely-not-a-skill-$$" 2>&1)
    assert_contains "reason=not-found" "$NOUT" "an absent name is still not-found"
  fi
fi

# --- references/skill-manifests.md is what bin/flow-skill-manifests.sh prints
# The tables there were hand-maintained and drifted (one skill listed at 598
# words was 1618). The generator rewrites only its marked regions, so the
# committed file must equal its output byte for byte. An empty output, or a
# generator that failed, would compare equal to nothing useful, so the exit
# status and the row counts are checked first.
GEN="$REPO_ROOT/plugins/flow/bin/flow-skill-manifests.sh"
MANIFEST="$REPO_ROOT/plugins/flow/references/skill-manifests.md"
_flow_test_begin "references/skill-manifests.md equals bin/flow-skill-manifests.sh output"
"$GEN" > "$FIX/manifests.out" 2> "$FIX/manifests.err"
GEN_RC=$?
assert_exit 0 "$GEN_RC" "the generator exits 0 ($(tr '\n' ' ' < "$FIX/manifests.err"))"
CMD_FILES=$(find "$COMMANDS_DIR" -maxdepth 1 -name '*.md' -type f | wc -l | tr -d ' ')
CMD_ROWS=$(grep -c '^| `/flow:' "$FIX/manifests.out" || true)
assert_equal "$CMD_FILES" "$CMD_ROWS" "one command row per commands/*.md"
SKILL_ROWS=$(awk '/BEGIN GENERATED: skills/{on=1; next} /END GENERATED: skills/{on=0} on && /^\| [a-z0-9-]+ \|/' "$FIX/manifests.out" | wc -l | tr -d ' ')
assert_equal "$SIZE_FOUND" "$SKILL_ROWS" "one skill row per skills/<name>/SKILL.md"
if [ "$GEN_RC" -eq 0 ] && cmp -s "$FIX/manifests.out" "$MANIFEST"; then
  _flow_assert_pass "the committed file is the generator's output"
else
  _flow_assert_fail "references/skill-manifests.md differs from bin/flow-skill-manifests.sh output; run it with --write. First differences: $(diff "$MANIFEST" "$FIX/manifests.out" 2>&1 | head -6 | tr '\n' ' ')"
fi

# The generator's refusals, on a copy of the plugin's bin, commands, skills
# and references: a region without its markers, and a command whose Required
# Skills name a skill that does not load, each exit 1 with no output.
_flow_test_begin "bin/flow-skill-manifests.sh refuses a missing region and a skill that does not load"
_fls_gen_copy() {
  rm -rf "$FIX/gen"; mkdir -p "$FIX/gen"
  cp -R "$REPO_ROOT/plugins/flow/bin" "$REPO_ROOT/plugins/flow/commands" \
        "$REPO_ROOT/plugins/flow/skills" "$REPO_ROOT/plugins/flow/references" "$FIX/gen/"
}
_fls_gen_copy
"$FIX/gen/bin/flow-skill-manifests.sh" > "$FIX/gen.out" 2> "$FIX/gen.err"
assert_exit 0 "$?" "an unchanged copy generates"
assert_equal "" "$(diff "$FIX/gen.out" "$FIX/manifests.out")" "an unchanged copy gives the same output"
python3 - "$FIX/gen/references/skill-manifests.md" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(t.replace("<!-- END GENERATED: skills -->\n", ""))
PY
"$FIX/gen/bin/flow-skill-manifests.sh" > "$FIX/gen.out" 2> "$FIX/gen.err"
assert_exit 1 "$?" "a region with no END marker exits 1"
assert_equal "" "$(cat "$FIX/gen.out")" "and prints nothing on stdout"
assert_contains "the skills region must have one BEGIN marker followed by one END marker" "$(cat "$FIX/gen.err")" "and says which region"
_fls_gen_copy
python3 - "$FIX/gen/commands/issue.md" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
t = t.replace("## Required Skills\n\n", "## Required Skills\n\n- `no-such-skill` — a skill that does not exist\n", 1)
open(p, "w", encoding="utf-8").write(t)
PY
"$FIX/gen/bin/flow-skill-manifests.sh" > "$FIX/gen.out" 2> "$FIX/gen.err"
assert_exit 1 "$?" "a required skill that does not load exits 1"
assert_contains "SKILL_LOAD_ERROR=no-such-skill reason=not-found" "$(cat "$FIX/gen.err")" "and names the skill"
assert_equal "" "$(cat "$FIX/gen.out")" "and prints nothing on stdout"
