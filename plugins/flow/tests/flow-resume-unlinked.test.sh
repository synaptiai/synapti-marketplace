# Tests for /flow:resume conservatism on unlinked working-tree changes.
#
# Source-presence lints for the Step 3.5 contract, plus behavioral coverage:
# extract the unlinked-detection bash block and run it in throwaway git repos.

RESUME_CMD="$REPO_ROOT/plugins/flow/commands/resume.md"

# --- Source-presence -----------------------------------------------------------
_flow_test_begin "resume.md documents unlinked-change detection + ask-first"
if [ ! -f "$RESUME_CMD" ]; then
  _flow_assert_fail "resume.md missing"
else
  CONTENT=$(cat "$RESUME_CMD")
  assert_contains "FLOW_RESUME_UNLINKED" "$CONTENT" "unlinked sentinel documented"
  assert_contains "git status --porcelain" "$CONTENT" "uses porcelain to detect changes"
  assert_contains "ask before suggesting continuation" "$CONTENT" "ask-first contract stated"
  assert_contains "unrelated work" "$CONTENT" "AskUserQuestion offers the unrelated-work path"
fi

# --- Behavioral: extract and run the Step 3.5 detection block ------------------
RESUME_CLEANUP=()
_resume_cleanup() { local p; for p in "${RESUME_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf "$p" 2>/dev/null; done; }
trap _resume_cleanup EXIT

if ! command -v git >/dev/null 2>&1; then
  _flow_test_begin "unlinked-detection behavioral prerequisites"
  _flow_assert_pass "SKIP: git not installed"
  return 0
fi

UNLINKED_BLOCK=$(python3 - "$RESUME_CMD" <<'PY'
import sys, re
src = open(sys.argv[1]).read()
after = src.split("### Step 3.5", 1)[1]
m = re.search(r"```!\n(.*?)\n```", after, re.S)
sys.stdout.write(m.group(1) if m else "")
PY
)

_new_repo() {
  local d
  d=$(mktemp -d -t flow-resume.XXXXXX)
  RESUME_CLEANUP+=("$d")
  ( cd "$d" && git init -q && git config user.email t@t.t && git config user.name t \
      && mkdir -p .flow/runs .decisions src \
      && echo base > src/keep.txt && git add src/keep.txt && git commit -qm base )
  printf '%s' "$d"
}

_flow_test_begin "only .flow/.decisions changes -> UNLINKED=0"
D=$(_new_repo)
( cd "$D" && echo "run: x" > .flow/runs/r.yaml && echo "j" > .decisions/issue-1.md )
OUT=$(cd "$D" && bash -c "$UNLINKED_BLOCK")
assert_contains "FLOW_RESUME_UNLINKED=0" "$OUT" "flow-owned changes are not unlinked"

_flow_test_begin "an unrelated tracked change -> UNLINKED=1 and lists the path"
D=$(_new_repo)
( cd "$D" && echo "edit" >> src/keep.txt && echo "new" > src/other.txt && echo "run" > .flow/runs/r.yaml )
OUT=$(cd "$D" && bash -c "$UNLINKED_BLOCK")
assert_contains "FLOW_RESUME_UNLINKED=1" "$OUT" "unrelated change flagged"
assert_contains "src/keep.txt" "$OUT" "modified unrelated file listed"
assert_contains "src/other.txt" "$OUT" "untracked unrelated file listed"
assert_not_contains ".flow/runs/r.yaml" "$OUT" "flow-owned change excluded from the unlinked list"

_flow_test_begin "clean tree -> UNLINKED=0"
D=$(_new_repo)
OUT=$(cd "$D" && bash -c "$UNLINKED_BLOCK")
assert_contains "FLOW_RESUME_UNLINKED=0" "$OUT" "clean tree is not unlinked"

_flow_test_begin "special-char/non-ASCII .flow path is still excluded (quotePath robustness)"
D=$(_new_repo)
# git quotes non-ASCII paths under default core.quotePath; the detector must
# still recognize the .flow/ prefix (core.quotePath=false + unquote) and a
# matching unrelated path must still be flagged.
( cd "$D" && mkdir -p ".flow/runs" && echo run > ".flow/runs/café.yaml" && echo x > "src/café.txt" )
OUT=$(cd "$D" && bash -c "$UNLINKED_BLOCK")
assert_contains "FLOW_RESUME_UNLINKED=1" "$OUT" "the unrelated non-ASCII file is flagged"
assert_contains "src/café.txt" "$OUT" "unrelated non-ASCII path listed"
assert_not_contains ".flow/runs/café.yaml" "$OUT" "non-ASCII .flow path excluded despite git quoting"

_flow_test_begin "rename is evaluated by its destination path (R/C-gated arrow strip)"
D=$(_new_repo)
# A staged rename shows as 'R  old -> new' in porcelain; the arrow strip (gated
# to R/C status lines) must extract the DESTINATION. Renaming an unrelated file
# keeps it flagged as unlinked under its new path, not the raw 'old -> new'.
( cd "$D" && git mv src/keep.txt src/moved.txt )
OUT=$(cd "$D" && bash -c "$UNLINKED_BLOCK")
assert_contains "FLOW_RESUME_UNLINKED=1" "$OUT" "renamed unrelated file is flagged"
assert_contains "src/moved.txt" "$OUT" "rename destination is listed"
assert_not_contains "src/keep.txt -> " "$OUT" "the raw arrow form is not emitted as a path"

_flow_test_begin "git failure surfaces UNLINKED=unknown (never a false 'clean')"
NOREPO=$(mktemp -d -t flow-resume-norepo.XXXXXX)
RESUME_CLEANUP+=("$NOREPO")
OUT=$(cd "$NOREPO" && bash -c "$UNLINKED_BLOCK")
assert_contains "FLOW_RESUME_UNLINKED=unknown" "$OUT" "git status failure -> unknown, not 0"
assert_contains "FLOW_RESUME_UNLINKED_REASON" "$OUT" "reason surfaced for the unknown state"
