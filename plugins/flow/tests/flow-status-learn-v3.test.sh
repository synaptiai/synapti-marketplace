# Tests for the Mode block of plugins/flow/commands/status.md: extract it and
# run it with no argument, --full, --json, --evidence and an unknown argument.

STATUS_CMD="$REPO_ROOT/plugins/flow/commands/status.md"

# Behavioral: extract the Mode !-block and confirm arg parsing + unknown fallback.
MODE_BLOCK=$(python3 - "$STATUS_CMD" <<'PY'
import sys, re
src = open(sys.argv[1]).read()
# The first ```! fenced block after the "## Mode" heading.
after = src.split("## Mode", 1)[1]
m = re.search(r"```!\n(.*?)\n```", after, re.S)
sys.stdout.write(m.group(1) if m else "")
PY
)
_run_mode() {  # $1 = ARGUMENTS value
  local raw="$1"
  local blk="${MODE_BLOCK//\$\{ARGUMENTS\}/$raw}"
  blk="${blk//\$ARGUMENTS/$raw}"
  bash -c "$blk"
}

_flow_test_begin "mode parse — no arg -> compact"
assert_contains "STATUS_MODE=compact" "$(_run_mode '')" "default (no arg) is compact"

_flow_test_begin "mode parse — --full/--json/--evidence map to their modes"
assert_contains "STATUS_MODE=full" "$(_run_mode '--full')" "--full -> full"
assert_contains "STATUS_MODE=json" "$(_run_mode '--json')" "--json -> json"
assert_contains "STATUS_MODE=evidence" "$(_run_mode '--evidence')" "--evidence -> evidence"

_flow_test_begin "mode parse — unknown arg falls back to compact (no error)"
OUT=$(_run_mode '--bogus')
assert_contains "STATUS_MODE=compact" "$OUT" "unknown arg -> compact"
assert_contains "STATUS_MODE_NOTE=unknown arg" "$OUT" "unknown arg surfaces a note"
