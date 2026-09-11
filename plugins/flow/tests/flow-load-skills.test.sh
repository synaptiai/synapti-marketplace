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
# learned/<name>/SKILL.md one level deeper. A promoted skill is loaded by name
# like any other, so it gets the same Contract-first, 120-word, 600-word budget
# — and none of the proposal scaffolding, which belongs in the promotion PR.
_flow_test_begin "promoted learned skills carry skill shape, not proposal shape"
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
  FIRST_H2=$(printf '%s\n' "$BODY" | awk '/^## / {print; exit}')
  [ "$FIRST_H2" = "## Contract" ] || PROBLEMS="$PROBLEMS; first H2 is '$FIRST_H2', expected '## Contract'"
  CWORDS=$(printf '%s\n' "$BODY" | awk '/^## Contract[[:space:]]*$/ {on=1; next} on && /^## / {exit} on {print}' | wc -w | tr -d ' ')
  [ "$CWORDS" -le 120 ] || PROBLEMS="$PROBLEMS; Contract is $CWORDS words (max 120)"
  BWORDS=$(printf '%s\n' "$BODY" | wc -w | tr -d ' ')
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
  _flow_assert_fail "scanned $LEARNED_SCANNED learned skills but $LEARNED_FOUND exist on disk"
fi

# --- every skill body stays within the 600-word budget
_flow_test_begin "skill bodies stay within 600 words"
for FILE in "$SKILLS_DIR"/*/SKILL.md; do
  NAME=$(basename "$(dirname "$FILE")")
  # No `learned` skip here: this glob stops one level above
  # learned/<name>/SKILL.md and cannot reach a promoted skill. Those are
  # scanned by the learned-skill block above, which applies the same budget.
  WORDS=$(awk 'BEGIN{fm=0} NR==1 && /^---$/ {fm=1; next} fm==1 { if (/^---$/) {fm=2}; next } {print}' "$FILE" | wc -w | tr -d ' ')
  if [ "$WORDS" -gt 600 ]; then
    _flow_assert_fail "$NAME: body is $WORDS words (max 600)"
  else
    _flow_assert_pass "$NAME: $WORDS words"
  fi
done
