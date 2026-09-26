# Tests for #213 AC3 — the blast radius of a contract change.
#
# Contract under test:
#   - `bin/flow-contract-files.sh` classifies a changed path as a contract file
#     by path and extension alone (no per-format parsing), naming the kind.
#     Cross-repository consumers are out of scope (#213 non-goal).
#   - Every finding category that code-reviewer.md or review.md instructs by
#     name exists in both finding vocabularies (the markdown table and the
#     row schema).
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

_flow_test_begin "contract-file detection: every extension and directory the helper claims"
# The seven fixtures above cover one spelling per kind. The helper advertises
# more, and each alternative that no input distinguishes can be deleted with
# every assertion still passing — verified by mutation for the migration
# extensions and the openapi directory block. These are strings, not files:
# what is under test is the classifier, not the filesystem.
BR_SPELLINGS=0
for PAIR in \
  "api/openapi.yml|openapi" \
  "api/openapi.json|openapi" \
  "api/swagger.yaml|openapi" \
  "api/swagger.yml|openapi" \
  "spec/openapi/users.yaml|openapi" \
  "spec/openapi/users.json|openapi" \
  "spec/swagger/users.yml|openapi" \
  "api/queries.gql|graphql" \
  "schemas/order.schema.yaml|schema" \
  "schemas/order.schema.yml|schema" \
  "schemas/order.avsc|schema" \
  "schemas/order.xsd|schema" \
  "db/migrations/002_users.rb|migration" \
  "db/migrations/003_users.py|migration" \
  "db/migrations/004_users.js|migration" \
  "db/migrations/005_users.ts|migration" \
  "db/migrations/006_users.go|migration" \
  "db/migrate/007_users.sql|migration"; do
  BR_PATH=${PAIR%%|*}
  BR_WANT=${PAIR#*|}
  BR_OUT=$(printf '%s\n' "$BR_PATH" | "$HELPER")
  assert_equal "CONTRACT_FILE=$BR_PATH|$BR_WANT" "$BR_OUT" "$BR_PATH is a $BR_WANT contract file"
  BR_SPELLINGS=$((BR_SPELLINGS + 1))
done
assert_equal "18" "$BR_SPELLINGS" "all eighteen further spellings examined"

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
assert_contains 'CLAUDE_PLUGIN_ROOT' "$BR_REVIEWER_SRC" \
  "and the helper is found by resolving the plugin root, not by assuming the working directory"
assert_contains 'A listing that fails is not the same as a diff with no contract in it' "$BR_REVIEWER_SRC" \
  "and a failed listing is not reported as no contract change"
assert_match 'git (-C "[$][{]REVIEW_TREE:-[.][}]" )?-c core\.quotePath=off diff' "$BR_REVIEWER_SRC" "with the flag written out"

_flow_test_begin "contract-file detection: paths as arguments work like paths on stdin"
# The header documents both. Deleting the whole argv branch left every assertion
# passing, because every case piped its paths in.
BR_ARGV=$("$HELPER" "src/app.ts" "api/service.proto" "db/migrations/001_add_users.sql")
assert_equal "2" "$(printf '%s\n' "$BR_ARGV" | grep -c '^CONTRACT_FILE=')" "two of three arguments are contracts"
assert_contains "api/service.proto|protobuf" "$BR_ARGV" "the proto is named"
assert_contains "db/migrations/001_add_users.sql|migration" "$BR_ARGV" "and the migration"
"$HELPER" "api/service.proto" >/dev/null 2>&1
assert_exit 0 "$?" "a contract among the arguments is exit 0"
"$HELPER" "src/app.ts" "README.md" >/dev/null 2>&1
assert_exit 1 "$?" "no contract among the arguments is exit 1"

_flow_test_begin "contract-file detection: a crafted path cannot forge a row"
# The path comes from the pull request. A newline in it would print a second
# CONTRACT_FILE line the reviewer reads as another contract; a literal pipe
# would split the kind field. The goal reader encodes both, and so does this.
BR_FORGE=$(printf '%s\n' '"api/x\nCONTRACT_FILE=forged|openapi\ny.graphql"' | "$HELPER")
assert_equal "1" "$(printf '%s\n' "$BR_FORGE" | grep -c '^CONTRACT_FILE=')" \
  "a newline in a path does not become a second row"
assert_not_contains "CONTRACT_FILE=forged|openapi" "$BR_FORGE" "and the forged row is not produced"
BR_PIPE=$(printf '%s\n' 'api/a|b.graphql' | "$HELPER")
assert_equal "CONTRACT_FILE=api/a%7Cb.graphql|graphql" "$BR_PIPE" \
  "a pipe in a path is escaped, so the kind field stays the kind field"

_flow_test_begin "contract-file detection: no input is a usage error, not a wait"
# With no arguments and a terminal on stdin the script would block on read with
# no prompt. A tty cannot be allocated portably in CI, so this asserts the guard
# is present in the source; the exit-2 contract itself is exercised via --help.
assert_contains '[ -t 0 ]' "$(cat "$HELPER")" "the terminal-stdin guard exists"
"$HELPER" --help >/dev/null 2>&1
assert_exit 2 "$?" "a usage error is exit 2"
printf '' | "$HELPER" >/dev/null 2>&1
assert_exit 1 "$?" "empty input on a pipe is 'no contract files', not a usage error"

_flow_test_begin "every category the review instructs exists in both vocabularies"
# A rule that says "report it as `x` P2" invents a category unless `x` is in the
# vocabulary the ledger is searched by. Two were invented alongside the one that
# was added properly, which is how they went unnoticed.
BR_SCHEMA=$(cat "$REPO_ROOT/plugins/flow/references/finding-schema.md")
BR_VOCAB=$(printf '%s\n' "$BR_SCHEMA" | awk -F'|' '/^\| `[a-z-]+` \|/ { gsub(/[ `]/, "", $2); print $2 }' | sort -u)
assert_match '[^[:space:]]' "$BR_VOCAB" "the vocabulary table was read"
BR_JSON_CATS=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['properties']['category']['description'])" \
  "$REPO_ROOT/tests/finding-schema/row-schema.json")
# Both word orders appear in the instructions: "`scope` P2" and "P2 `scope`".
BR_INSTRUCTED=$( { grep -rhoE '`[a-z][a-z-]+` P[123]' \
    "$REPO_ROOT/plugins/flow/agents/code-reviewer.md" \
    "$REPO_ROOT/plugins/flow/commands/review.md" | sed -E 's/`([a-z-]+)` P[123]/\1/'
  grep -rhoE 'P[123] `[a-z][a-z-]+`' \
    "$REPO_ROOT/plugins/flow/agents/code-reviewer.md" \
    "$REPO_ROOT/plugins/flow/commands/review.md" | sed -E 's/P[123] `([a-z-]+)`/\1/'
  } | sort -u)
assert_match '[^[:space:]]' "$BR_INSTRUCTED" "at least one category is instructed by name"
BR_MISSING=""
BR_CHECKED=0
for BR_CAT in $BR_INSTRUCTED; do
  BR_CHECKED=$((BR_CHECKED + 1))
  printf '%s\n' "$BR_VOCAB" | grep -qx "$BR_CAT" || BR_MISSING="$BR_MISSING md:$BR_CAT"
  case "$BR_JSON_CATS" in *"$BR_CAT"*) ;; *) BR_MISSING="$BR_MISSING json:$BR_CAT" ;; esac
done
assert_equal "" "$BR_MISSING" "every instructed category ($BR_CHECKED checked) is in both vocabularies"
# The check has to be able to fail, on BOTH halves: a negative control that only
# re-implements the markdown lookup says nothing about the JSON one.
BR_FAKE=""
printf '%s\n' "$BR_VOCAB" | grep -qx "not-a-category" || BR_FAKE="${BR_FAKE}md:not-a-category "
case "$BR_JSON_CATS" in *"not-a-category"*) ;; *) BR_FAKE="${BR_FAKE}json:not-a-category" ;; esac
assert_equal "md:not-a-category json:not-a-category" "$BR_FAKE" \
  "an unknown category is reported missing by both vocabularies, not just one"
# The JSON half matches a substring, so a category that is a fragment of another
# word would pass without being listed. Pin the boundary.
case "$BR_JSON_CATS" in *"breaking-change"*) _flow_assert_pass "the JSON list names breaking-change" ;;
  *) _flow_assert_fail "the JSON list does not name breaking-change" ;; esac
case "$BR_JSON_CATS" in *"breaking-chang, "*|*" breaking-chang,"*) _flow_assert_fail "a fragment matched as if it were a category" ;;
  *) _flow_assert_pass "and a fragment of it is not itself a listed category" ;; esac
