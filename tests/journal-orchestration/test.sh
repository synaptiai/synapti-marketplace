#!/usr/bin/env bash
# SEC-1 regression test for bin/journal-record.sh: the helper must export
# PYTHONSAFEPATH so its inline `import yaml` never loads a `yaml.py` from the
# working directory. After `gh pr checkout` of a hostile pull request, the
# working directory is the attacker's tree, and a shadowing `yaml.py` there
# would run arbitrary code.

set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HELPER="$REPO_ROOT/plugins/flow/bin/journal-record.sh"
SANDBOX=$(mktemp -d -t flow-journal-test.XXXXXX)
trap 'rm -rf "$SANDBOX"' EXIT

if [ ! -x "$HELPER" ]; then
  echo "FATAL: $HELPER not executable" >&2
  exit 2
fi

cd "$SANDBOX"
PASS=0
FAIL=0

assert() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

# SEC-1: PYTHONSAFEPATH must be exported, preventing CWD-shadow imports.
# Without this, an attacker-shipped `./yaml.py` at the repo root after
# `gh pr checkout` would be loaded by the inline `import yaml` (full RCE).
SEC1_DIR=$(mktemp -d -t flow-sec1.XXXXXX)
cat > "$SEC1_DIR/yaml.py" <<'PYEOF'
import sys
print("ATTACKER-YAML-LOADED", file=sys.stderr)
sys.exit(99)
PYEOF
( cd "$SEC1_DIR" && "$HELPER" --issue 780 --type specification --metadata by=test 2>"$SEC1_DIR/stderr.log" )
SEC1_RC=$?
# `grep -c` exits 1 when 0 matches found; capture stdout count without the
# error path so the assertion compares a single integer.
SEC1_LEAK=$(grep -c "ATTACKER-YAML-LOADED" "$SEC1_DIR/stderr.log" 2>/dev/null) || SEC1_LEAK=0
assert "SEC-1: attacker yaml.py NOT loaded via sys.path" 0 "$SEC1_LEAK"
assert "SEC-1: journal-record completed normally despite attacker yaml.py" 0 "$SEC1_RC"
rm -rf "$SEC1_DIR"

echo ""
echo "============================================"
echo "RESULT: $PASS passed, $FAIL failed"
echo "============================================"
[ "$PASS" -eq 0 ] && { echo "FAIL: no assertions ran — harness regression" >&2; exit 1; }
[ "$FAIL" -gt 0 ] && exit 1
exit 0
