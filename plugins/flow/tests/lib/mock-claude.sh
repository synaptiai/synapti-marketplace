#!/usr/bin/env bash
# Test shim for `claude --print`. Used by flow-goal-evaluator.test.sh to
# stub the judge subprocess without hitting the real Claude API.
#
# Usage (test harness):
#   export FLOW_TEST_CLAUDE_RESPONSE=/path/to/fixture.json
#   export PATH="${tmpdir}/mock-bin:$PATH"      # mock-bin/claude → this script
#   ./flow-goal-evaluator.sh < event.json
#
# Contract:
#   - Accepts and ignores ALL flags so it survives hook arg drift.
#   - Reads stdin to /dev/null so the producer's `<` redirect doesn't SIGPIPE.
#   - Emits the fixture file's contents on stdout, byte-for-byte.
#   - Exits 0 if fixture is readable; 1 if env var unset or fixture unreadable.
#
# Why a separate file (not inline in the test): symlinking/copying this as
# `claude` in a per-test mock-bin keeps PATH manipulation simple and lets
# multiple tests reuse the same shim with different fixtures via env var.

set -u

if [ -z "${FLOW_TEST_CLAUDE_RESPONSE:-}" ]; then
  echo "mock-claude: FLOW_TEST_CLAUDE_RESPONSE unset" >&2
  exit 1
fi
if [ ! -r "$FLOW_TEST_CLAUDE_RESPONSE" ]; then
  echo "mock-claude: fixture unreadable: $FLOW_TEST_CLAUDE_RESPONSE" >&2
  exit 1
fi

cat > /dev/null
cat "$FLOW_TEST_CLAUDE_RESPONSE"
