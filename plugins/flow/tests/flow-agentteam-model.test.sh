# Tests for the configurable Path A agent-team review model.
#
# Contract under test:
#   - settings.json carries a top-level `agentTeamModel` defaulting to "sonnet".
#   - schema.json constrains it to enum [haiku,sonnet,opus,inherit], default sonnet.
#   - commands/review.md Path A gate resolves the key via cascade-resolve.sh into
#     AGENT_TEAM_MODEL, validates it against the enum (rejecting invalid values
#     with a WARN + sonnet fallback — NOT silent), and the A.1/A.3 dispatches
#     pass it as the per-invocation model. Path B is left unchanged.
#   - Docs (README.md, references/gate-configuration.md) mention the key.
#   - Functional: cascade-resolve returns sonnet by default and honors a local
#     override; the extracted gate block rejects a bogus value and accepts inherit.
#
# Prereq: jq (used by cascade-resolve.sh and the static enum assertions).
# SKIPS gracefully if jq is unavailable.

if ! command -v jq >/dev/null 2>&1; then
  _flow_test_begin "jq prerequisite"
  _flow_assert_pass "SKIP: jq not installed"
  return 0
fi

PLUGIN_DIR="$REPO_ROOT/plugins/flow"
SETTINGS="$PLUGIN_DIR/settings.json"
SCHEMA="$PLUGIN_DIR/schema.json"
REVIEW_MD="$PLUGIN_DIR/commands/review.md"
README="$PLUGIN_DIR/README.md"
GATE_DOC="$PLUGIN_DIR/references/gate-configuration.md"
CASCADE="$PLUGIN_DIR/bin/cascade-resolve.sh"

CLEANUP_PATHS=()
_cleanup_all() {
  local p
  for p in "${CLEANUP_PATHS[@]:-}"; do
    [ -n "$p" ] && rm -rf "$p" 2>/dev/null
  done
}
trap _cleanup_all EXIT

# --- settings.json: default value
_flow_test_begin "settings.json has agentTeamModel=sonnet"
VAL=$(jq -r '.agentTeamModel // empty' "$SETTINGS" 2>/dev/null)
assert_equal "sonnet" "$VAL" "settings.json agentTeamModel default is sonnet"

# --- schema.json: enum + default
_flow_test_begin "schema.json constrains agentTeamModel enum + default"
ENUM=$(jq -r '.properties.agentTeamModel.enum | join(",")' "$SCHEMA" 2>/dev/null)
assert_equal "haiku,sonnet,opus,inherit" "$ENUM" "schema enum is haiku,sonnet,opus,inherit"
DEF=$(jq -r '.properties.agentTeamModel.default // empty' "$SCHEMA" 2>/dev/null)
assert_equal "sonnet" "$DEF" "schema default is sonnet"

# --- settings value is a member of the schema enum
_flow_test_begin "settings agentTeamModel is within schema enum"
INDEX=$(jq -r --arg v "$VAL" '.properties.agentTeamModel.enum | index($v)' "$SCHEMA" 2>/dev/null)
assert_match '^[0-9]+$' "$INDEX" "settings value '$VAL' is a valid enum member"

# --- review.md wiring (static)
_flow_test_begin "review.md Path A gate wires the model resolution"
REVIEW_CONTENT=$(cat "$REVIEW_MD")
assert_contains "AGENTTEAM_MODEL_BEGIN" "$REVIEW_CONTENT" "model-resolution block markers present"
assert_contains "cascade-resolve.sh" "$REVIEW_CONTENT" "gate uses cascade-resolve.sh"
assert_contains ".agentTeamModel" "$REVIEW_CONTENT" "gate resolves the agentTeamModel key"
assert_contains "AGENT_TEAM_MODEL=" "$REVIEW_CONTENT" "gate emits AGENT_TEAM_MODEL"
# Bind to the actual case-allowlist construct, not just any prose mention of
# the model names (which appear throughout the file).
assert_contains "haiku|sonnet|opus|inherit) ;;" "$REVIEW_CONTENT" "gate validates against the enum allowlist case arm"

_flow_test_begin "review.md fenced dispatches carry the resolved model"
# The param must travel with the copy-ready Agent(...) examples, not live only
# in adjacent prose — otherwise an agent copying the fenced block silently
# drops it and regresses to inherited-model behavior. Count fenced dispatches
# that carry model=$AGENT_TEAM_MODEL: A.1 has 10 paired reviewers, A.3 shows 2
# challenge-mode examples = 12 expected.
DISPATCH_WITH_MODEL=$(printf '%s\n' "$REVIEW_CONTENT" | grep -cE 'Agent\([a-z-]+(-skeptic|-verifier).*model=\$AGENT_TEAM_MODEL')
assert_match '^(1[0-9]|[2-9])$' "$DISPATCH_WITH_MODEL" "at least several fenced Agent(...) dispatches carry model=\$AGENT_TEAM_MODEL (found $DISPATCH_WITH_MODEL)"
# The model param must travel with the copy-ready fenced examples, not live
# only in adjacent prose: no paired-reviewer dispatch line may omit it.
DISPATCH_WITHOUT_MODEL=$(printf '%s\n' "$REVIEW_CONTENT" | grep -E 'Agent\([a-z-]+(-skeptic|-verifier)[):]' | grep -vc 'model=\$AGENT_TEAM_MODEL')
assert_equal "0" "$DISPATCH_WITHOUT_MODEL" "no paired-reviewer dispatch omits the model param"

_flow_test_begin "review.md omits the model override when inherit (dispatch enum is sonnet|opus|haiku)"
# The Agent tool's per-invocation model override accepts only sonnet|opus|haiku;
# 'inherit' must be expressed by dropping the override, never by passing
# model=inherit (which would be an invalid dispatch and break the inherit case).
assert_contains "OMIT the \`model\` argument" "$REVIEW_CONTENT" "directive instructs omitting the override on inherit"
assert_not_contains "model=inherit\` is itself valid" "$REVIEW_CONTENT" "no false 'model=inherit is valid' claim"

_flow_test_begin "review.md documents Path B as unchanged"
# A line stating Path B leaves the model inherited / unchanged.
assert_match 'Path B.*(unchanged|inherit|not modified|NOT modified)' "$REVIEW_CONTENT" "Path B explicitly noted as unchanged"

# --- docs mention the key
_flow_test_begin "README documents agentTeamModel"
assert_contains "agentTeamModel" "$(cat "$README")" "README mentions agentTeamModel"

_flow_test_begin "gate-configuration documents agentTeamModel"
assert_contains "agentTeamModel" "$(cat "$GATE_DOC")" "gate-configuration.md mentions agentTeamModel"

# --- functional: cascade-resolve default resolves to sonnet (from plugin settings.json)
_flow_test_begin "cascade-resolve returns sonnet by default"
RESOLVED=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" "$CASCADE" --default sonnet '.agentTeamModel // empty' 2>/dev/null)
assert_equal "sonnet" "$RESOLVED" "plugin-tier default resolves to sonnet"

# --- functional: a project-local override wins
_flow_test_begin "cascade-resolve honors a local override (opus)"
SCRATCH=$(mktemp -d -t flow-atm.XXXXXX)
CLEANUP_PATHS+=("$SCRATCH")
mkdir -p "$SCRATCH/.claude"
printf '%s\n' '{"agentTeamModel":"opus"}' > "$SCRATCH/.claude/settings.flow.local.json"
RESOLVED_LOCAL=$( cd "$SCRATCH" && CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" "$CASCADE" --default sonnet '.agentTeamModel // empty' 2>/dev/null )
assert_equal "opus" "$RESOLVED_LOCAL" "local settings.flow.local.json override resolves to opus"

# --- functional: extract the gate's model block and exercise validation
# Stub cascade-resolve so we control the returned value, then source the
# extracted block with USE_PATH_A=1 and read the emitted AGENT_TEAM_MODEL / WARN.
_run_model_block() {
  # $1 = value the stubbed cascade-resolve should echo
  local stub_value="$1"
  local work; work=$(mktemp -d -t flow-atm-blk.XXXXXX)
  CLEANUP_PATHS+=("$work")
  mkdir -p "$work/bin"
  # Stub cascade-resolve.sh: ignore args, echo the controlled value.
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\n' "$stub_value" > "$work/bin/cascade-resolve.sh"
  chmod +x "$work/bin/cascade-resolve.sh"
  # Extract the block between the sentinels (exclusive of the sentinel lines).
  awk '/AGENTTEAM_MODEL_BEGIN/{f=1;next} /AGENTTEAM_MODEL_END/{f=0} f' "$REVIEW_MD" > "$work/block.sh"
  ( set +u; USE_PATH_A=1; CLAUDE_PLUGIN_ROOT="$work"; . "$work/block.sh" ) 2>"$work/err"
  # Return combined stdout already captured by caller via command sub; emit err marker.
  cat "$work/err" >&2
}

_flow_test_begin "gate block accepts a valid override (opus)"
OUT=$(_run_model_block "opus" 2>/dev/null)
assert_contains "AGENT_TEAM_MODEL=opus" "$OUT" "valid value opus passes through"

_flow_test_begin "gate block accepts inherit"
OUT=$(_run_model_block "inherit" 2>/dev/null)
assert_contains "AGENT_TEAM_MODEL=inherit" "$OUT" "inherit passes the allowlist"

_flow_test_begin "gate block rejects a bogus value with WARN + sonnet fallback"
OUT=$(_run_model_block "gpt-9000" 2>/dev/null)
ERR=$(_run_model_block "gpt-9000" 2>&1 >/dev/null)
assert_contains "AGENT_TEAM_MODEL=sonnet" "$OUT" "bogus value falls back to sonnet"
assert_contains "WARN" "$ERR" "bogus value is rejected with a clear WARN (not silent)"

_flow_test_begin "gate block treats an empty resolution as invalid -> sonnet + WARN"
# Defends the path where cascade-resolve yields nothing (e.g. jq missing and no
# default reached the case): the allowlist's catchall must still produce sonnet.
OUT=$(_run_model_block "" 2>/dev/null)
ERR=$(_run_model_block "" 2>&1 >/dev/null)
assert_contains "AGENT_TEAM_MODEL=sonnet" "$OUT" "empty value falls back to sonnet"
assert_contains "WARN" "$ERR" "empty value is rejected with a clear WARN (not silent)"
