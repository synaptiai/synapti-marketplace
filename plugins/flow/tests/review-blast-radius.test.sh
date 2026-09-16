# Tests for #213 AC3 — the blast radius of a contract change.
#
# Contract under test:
#   - `bin/flow-contract-files.sh` classifies a changed path as a contract file
#     by path and extension alone (no per-format parsing), naming the kind.
#     Cross-repository consumers are out of scope (#213 non-goal).
#   - `agents/code-reviewer.md` Step 2b reports `callers examined: N (<tool>)`
#     per modified public symbol, and treats N=0 from an available LSP beside a
#     Grep hit as a failed trace rather than as "no callers".
#   - `templates/review-comment.md` carries the `### Blast radius` section and
#     `references/finding-schema.md` carries `breaking-change`.
#
# Expected values come from #213's Resolution section and the fixtures below,
# read by hand; none is taken from the helper's own output.

HELPER="$REPO_ROOT/plugins/flow/bin/flow-contract-files.sh"
FIXTURES="$REPO_ROOT/plugins/flow/tests/fixtures/blast-radius"

_flow_test_begin "contract-file detection: every pattern #213 names is classified"
assert_file_exists "$HELPER" "the helper exists"
[ -x "$HELPER" ] && _flow_assert_pass "and is executable" || _flow_assert_fail "not executable"

# One fixture per pattern the issue enumerates. The expected kind is the
# issue's own vocabulary, not the helper's output.
BR_EXAMINED=0
for PAIR in \
  "api/openapi.yaml|openapi" \
  "api/swagger.json|openapi" \
  "api/schema.graphql|graphql" \
  "api/service.proto|protobuf" \
  "db/migrations/001_add_users.sql|migration" \
  "schemas/v1/order.schema.json|schema" \
  ".flow/goals/issue-9.goal.yaml|goal-contract"; do
  BR_PATH=${PAIR%%|*}
  BR_WANT=${PAIR#*|}
  assert_file_exists "$FIXTURES/$BR_PATH" "fixture for $BR_WANT exists"
  BR_OUT=$(printf '%s\n' "$BR_PATH" | "$HELPER")
  assert_equal "CONTRACT_FILE=$BR_PATH|$BR_WANT" "$BR_OUT" "$BR_PATH is a $BR_WANT contract file"
  BR_EXAMINED=$((BR_EXAMINED + 1))
done
assert_equal "7" "$BR_EXAMINED" "all seven patterns examined"

_flow_test_begin "contract-file detection: ordinary source is not a contract change"
# A file that merely lives near a contract, or shares a word with one, must not
# trigger a blast-radius section — that would make the section noise.
BR_QUIET=0
for BR_PATH in \
  "src/app.ts" \
  "README.md" \
  "docs/openapi-guide.md" \
  "src/migrations_helper.go" \
  "test/protobuf_test_helper.py" \
  "plugins/flow/commands/review.md"; do
  BR_OUT=$(printf '%s\n' "$BR_PATH" | "$HELPER")
  assert_equal "" "$BR_OUT" "$BR_PATH is not reported as a contract file"
  BR_QUIET=$((BR_QUIET + 1))
done
assert_equal "6" "$BR_QUIET" "all six look-alikes examined"

_flow_test_begin "contract-file detection: a whole changed-file list is classified in one pass"
BR_LIST=$(printf '%s\n' "src/app.ts" "api/service.proto" "README.md" "db/migrations/001_add_users.sql" | "$HELPER")
assert_equal "2" "$(printf '%s\n' "$BR_LIST" | grep -c '^CONTRACT_FILE=')" "two of four are contract files"
assert_contains "api/service.proto|protobuf" "$BR_LIST" "the proto is named"
assert_contains "db/migrations/001_add_users.sql|migration" "$BR_LIST" "the migration is named"
# Exit status says whether anything matched, so a caller can branch on it.
printf '%s\n' "src/app.ts" | "$HELPER" >/dev/null 2>&1
assert_exit 1 "$?" "no contract file in the list is exit 1"
printf '%s\n' "api/service.proto" | "$HELPER" >/dev/null 2>&1
assert_exit 0 "$?" "a contract file in the list is exit 0"

_flow_test_begin "code-reviewer reports how many callers it examined, and with which tool"
BR_REVIEWER=$(cat "$REPO_ROOT/plugins/flow/agents/code-reviewer.md")
assert_contains 'callers examined:' "$BR_REVIEWER" "the Summary line is required"
assert_match 'callers examined: N \(.*findReferences.*incomingCalls.*grep' "$BR_REVIEWER" "and names which tool produced it"
# A trace that found nothing and a trace that failed look identical unless the
# reviewer is told to tell them apart.
assert_contains 'Grep' "$BR_REVIEWER" "the Grep fallback is named"
BR_STEP2B=$(printf '%s\n' "$BR_REVIEWER" | awk '/^### Step 2b/ { f = 1; next } f && /^### Step [0-9]/ { f = 0 } f')
assert_match '[^[:space:]]' "$BR_STEP2B" "Step 2b extracted"
assert_contains 'N=0' "$BR_STEP2B" "zero callers from an available LSP is called out"
assert_contains 'flow-contract-files.sh' "$BR_STEP2B" "the contract-file patterns come from the helper"
assert_contains 'Blast radius' "$BR_STEP2B" "and trigger the section"
assert_contains 'breaking-change' "$BR_STEP2B" "with the finding category to use"
# #213's non-goal, stated where a reviewer would otherwise go looking.
assert_contains 'Cross-repository' "$BR_STEP2B" "cross-repository consumers are out of scope"

_flow_test_begin "the review body and the finding vocabulary carry the new section and category"
assert_contains '### Blast radius' "$(cat "$REPO_ROOT/plugins/flow/templates/review-comment.md")" \
  "the external template carries the section"
BR_SCHEMA=$(cat "$REPO_ROOT/plugins/flow/references/finding-schema.md")
assert_contains 'breaking-change' "$BR_SCHEMA" "breaking-change is in the category vocabulary"
