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
BR_REVIEWER_SRC=$(cat "$REPO_ROOT/plugins/flow/agents/code-reviewer.md")
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
  "plugins/flow/commands/review.md" \
  "docs/examples/sample.goal.yaml" \
  "db/migrations/README.md"; do
  BR_OUT=$(printf '%s\n' "$BR_PATH" | "$HELPER")
  assert_equal "" "$BR_OUT" "$BR_PATH is not reported as a contract file"
  BR_QUIET=$((BR_QUIET + 1))
done
assert_equal "8" "$BR_QUIET" "all eight look-alikes examined"
# The last two carry the weight: a goal file is a contract because of where it
# lives, and a migration directory holds files that are not migrations. Without
# them both location guards could be deleted with every assertion still passing.

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

_flow_test_begin "contract-file detection: a path git had to quote still classifies"
# The documented pipeline is `git diff --name-only | flow-contract-files.sh`, and
# git renders a non-ASCII path as "api/sch\303\251ma.graphql" under its default
# core.quotePath. The basename then ends in a quote and matches no pattern, so a
# pull request whose only contract change is that file reports none at all.
# The strings are fed in directly: committing a non-ASCII FILENAME would decompose
# differently on macOS and Linux and test the filesystem instead of the helper.
BR_QUOTED=$(printf '%s\n' '"api/sch\303\251ma.graphql"' | "$HELPER")
assert_equal 'CONTRACT_FILE=api/schéma.graphql|graphql' "$BR_QUOTED" \
  "the quoted form is unquoted, decoded and classified"
BR_PLAIN=$(printf '%s\n' 'api/schéma.graphql' | "$HELPER")
assert_equal 'CONTRACT_FILE=api/schéma.graphql|graphql' "$BR_PLAIN" \
  "and the unquoted form is unchanged"
BR_QUOTED_TAB=$(printf '%s\n' '"db/migrations/001\tadd.sql"' | "$HELPER")
assert_contains 'migration' "$BR_QUOTED_TAB" "a quoted tab is decoded too"
# The reliable fix is at the caller, so the instruction has to be there as well.
assert_contains 'core.quotePath' "$BR_REVIEWER_SRC" "the documented pipeline turns path quoting off"
assert_match 'git -c core\.quotePath=off diff' "$BR_REVIEWER_SRC" "with the flag written out"

_flow_test_begin "contract-file detection: no input is a usage error, not a wait"
# With no arguments and a terminal on stdin the script would block on read with
# no prompt. A tty cannot be allocated portably in CI, so this asserts the guard
# is present in the source; the exit-2 contract itself is exercised via --help.
assert_contains '[ -t 0 ]' "$(cat "$HELPER")" "the terminal-stdin guard exists"
"$HELPER" --help >/dev/null 2>&1
assert_exit 2 "$?" "a usage error is exit 2"
printf '' | "$HELPER" >/dev/null 2>&1
assert_exit 1 "$?" "empty input on a pipe is 'no contract files', not a usage error"

_flow_test_begin "code-reviewer reports how many callers it examined, and with which tool"
BR_REVIEWER=$(cat "$REPO_ROOT/plugins/flow/agents/code-reviewer.md")
assert_contains 'callers examined:' "$BR_REVIEWER" "the Summary line is required"
assert_match 'callers examined: N \(.*findReferences.*incomingCalls.*grep' "$BR_REVIEWER" "and names which tool produced it"
# A trace that found nothing and a trace that failed look identical unless the
# reviewer is told to tell them apart.
assert_contains 'Grep' "$BR_REVIEWER" "the Grep fallback is named"
BR_STEP2B=$(printf '%s\n' "$BR_REVIEWER" | awk '/^### Step 2b/ { f = 1; next } f && /^### Step [0-9]/ { f = 0 } f')
assert_match '[^[:space:]]' "$BR_STEP2B" "Step 2b extracted"
# The token `N=0` survives the row's plausible wrong version being written into
# the doc verbatim, so assert the clause that carries the rule.
assert_contains 'N=0' "$BR_STEP2B" "zero callers from an available LSP is called out"
assert_match 'N=0.*is a finding, not' "$BR_STEP2B" "as a finding rather than a clean result"
assert_contains 'whenever `Grep` finds the symbol referenced outside the diff' "$BR_STEP2B" \
  "and the condition that distinguishes a failed trace from no callers"
assert_contains 'flow-contract-files.sh' "$BR_STEP2B" "the contract-file patterns come from the helper"
assert_contains 'Blast radius' "$BR_STEP2B" "and trigger the section"
assert_contains 'breaking-change' "$BR_STEP2B" "with the finding category to use"
# #213's non-goal, stated where a reviewer would otherwise go looking.
assert_contains 'Cross-repository' "$BR_STEP2B" "cross-repository consumers are out of scope"

_flow_test_begin "the review body and the finding vocabulary carry the new section and category"
BR_TPL=$(cat "$REPO_ROOT/plugins/flow/templates/review-comment.md")
# `assert_contains '### Blast radius'` also passes on `###### Blast radius`, so
# pin the whole line: the siblings in this template are all `####`.
assert_match '^#### Blast radius$' "$BR_TPL" "the external template carries the section at the sibling level"
assert_equal "1" "$(printf '%s\n' "$BR_TPL" | grep -c '^#\{1,6\} Blast radius$')" "exactly one such heading"
# `#### Blast radius` contains `### Blast radius`, so match the backticked form
# the prose actually writes.
assert_equal "0" "$(grep -c '`### Blast radius`' "$REPO_ROOT/plugins/flow/agents/code-reviewer.md" "$HELPER" | awk -F: '{t+=$2} END {print t+0}')" \
  "no prose names a heading level the template does not render"
assert_equal "2" "$(grep -c '`#### Blast radius`' "$REPO_ROOT/plugins/flow/agents/code-reviewer.md" "$HELPER" | awk -F: '{t+=$2} END {print t+0}')" \
  "both prose sites name the one the template renders"
BR_SCHEMA=$(cat "$REPO_ROOT/plugins/flow/references/finding-schema.md")
assert_contains 'breaking-change' "$BR_SCHEMA" "breaking-change is in the category vocabulary"
