---
description: "Classify changes and create atomic commits with conventional messages. Flags out-of-context modifications and red-flag patterns before committing."
argument-hint: [message]
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion, Skill, Grep, Glob
---

# Context-Aware Commit

Classify changes, flag anomalies, and create atomic conventional commits. Follows the Explore > Verify pattern (lightweight — no plan/code phases needed).

## Required Skills

- `llm-operator-principles` — operator stance (inlined above): convergence is zero findings, fix in this PR, no calendar-time estimates, escalate only for true decisions
- `change-classification` — signal-based change analysis
- `convention-enforcement` — commit message validation

```!
# Inline the Required Skills above so their rules are in context before the
# first phase runs (commands cannot preload skills from frontmatter). Ambient
# skills load whole; dispatched skills (context: fork / agent:) load their
# `## Contract` section and run in full when this command invokes
# Skill(<name>). Output per `references/command-output-format.md`.
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-load-skills.sh" llm-operator-principles change-classification convention-enforcement

true
```

## References

- [`references/escalation-format.md`](../references/escalation-format.md) — canonical six-field structure used by Phase 3's uncertain/out-of-context-files escalation

## Phase 1: EXPLORE

```!
# Output: `###`-headed sections + KEY=value per
# `references/command-output-format.md`.

printf '%s\n' "### Branch Context"
BRANCH=$(git branch --show-current 2>/dev/null)
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || printf '%s\n' "main")
printf '%s\n' "BRANCH=$BRANCH"
printf '%s\n' "DEFAULT_BRANCH=$DEFAULT_BRANCH"

printf '%s\n' ""
printf '%s\n' "### Uncommitted Changes"
UNCOMMITTED_COUNT=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
printf '%s\n' "UNCOMMITTED_COUNT=$UNCOMMITTED_COUNT"
if [ "$UNCOMMITTED_COUNT" = "0" ]; then
  printf '%s\n' "STATE=empty"
else
  git status --porcelain 2>/dev/null | sed 's/^/UNCOMMITTED_LINE=/'
fi

printf '%s\n' ""
printf '%s\n' "### Branch Files (vs default)"
BRANCH_FILES=$(git diff --name-only "$DEFAULT_BRANCH"...HEAD 2>/dev/null)
# `grep -c '.' || echo 0` produces multi-line `0\n0` on empty input (grep
# exits 1, the `||` ALSO fires). Use explicit empty-check.
if [ -z "$BRANCH_FILES" ]; then
  BRANCH_FILE_COUNT=0
else
  BRANCH_FILE_COUNT=$(printf '%s\n' "$BRANCH_FILES" | wc -l | tr -d ' ')
fi
printf '%s\n' "BRANCH_FILE_COUNT=$BRANCH_FILE_COUNT"
if [ "$BRANCH_FILE_COUNT" = "0" ]; then
  printf '%s\n' "STATE=empty"
else
  printf '%s\n' "$BRANCH_FILES" | sed 's/^/BRANCH_FILE=/'
fi

printf '%s\n' ""
printf '%s\n' "### Issue Context"
ISSUE_NUM=$(printf '%s\n' "$BRANCH" | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+')
# Quote parenthesized fallback per command-output-format.md rule 2.
printf '%s\n' "ISSUE_NUM=${ISSUE_NUM:-\"(none)\"}"
if [ -n "$ISSUE_NUM" ]; then
  gh issue view "$ISSUE_NUM" --json title,body --jq '"ISSUE_TITLE=\"\(.title)\"\nISSUE_BODY_LENGTH=\(.body | length)"' 2>/dev/null
fi

printf '%s\n' ""
printf '%s\n' "### Recent Commits (for style)"
# Capture so an empty log (new repo) emits STATE=empty rather than silent
# heading.
RECENT_COMMITS=$(git log --oneline -10 2>/dev/null)
if [ -z "$RECENT_COMMITS" ]; then
  printf '%s\n' "STATE=empty"
else
  printf '%s\n' "$RECENT_COMMITS" | sed 's/^/COMMIT=/'
fi

true
```

**Grep** — search branch diff and issue body for task-related context.

## Phase 2: CLASSIFY (cross-check)

**Note**: When running after `/flow:start`, per-task change classification already happened during the CODE phase (step 8 of the per-task verification gate). Commit-time classification is a **final cross-check**, not the primary gate. Out-of-context files should have been flagged and resolved during CODE. If new out-of-context files appear here, it indicates a gap in the per-task gate that should be investigated.

Apply change-classification skill knowledge:

For each changed file, evaluate:
1. **Red flags** — block secrets, warn on lock files and large binaries
2. **Primary signals** — branch diff, issue keywords, task match
3. **Secondary signals** — sibling files, test companions
4. **First-touch detection** — new files with large additions
5. **Boy Scout detection** — if changes are cleanup-only (lint, format, typo, obvious bug fix) in files already on the branch diff, classify as `boy-scout` subtype of in-context

## Phase 3: DISPLAY (Finding-First)

Show classification table BEFORE any action:

```markdown
| File | Status | Classification | Signal | Notes |
|------|--------|---------------|--------|-------|
| src/auth/login.rb | M | in-context | branch diff | |
| src/utils/helper.rb | M | uncertain | sibling only | first-touch; serves issue: 0.93 (jev-1.13.0) |
| .env.local | M | RED FLAG | secret pattern | BLOCKED |
```

**System One estimate for uncertain files.** Before asking about uncertain files, run this block once with every uncertain file. Never list a RED FLAG file in it. Out-of-context files are not listed: only the uncertain band is asked about. First run `mktemp` and note the path it prints. Write to that path, with the Write tool, one JSON object listing the uncertain files in table order, each with the signals that matched it separated by `;`: `{"files": [{"path": "src/utils/helper.rb", "signals": "sibling only; first-touch"}]}`. Set `S1_INPUT` to the path and `ISSUE_NUM` to the number from Phase 1 (empty when there is none). Never put a path or a signal on the command line: a file name such as `a'$(cmd)'.md` ends the quotes and runs `cmd`, and a signal quoting the issue can do the same. They go in the JSON file, which no shell parses. Never write the file with a here-document either: a line equal to the delimiter ends it, and every line after it runs as shell. The block reads only a file directly in `$TMPDIR` (or `/tmp`) that `mktemp` made, and removes it once read; any other file is refused (`S1_INPUT=refused`) and left as it is.

```bash
S1_INPUT='{the path mktemp printed}'
ISSUE_NUM='{ISSUE_NUM from Phase 1, or empty}'
RUN_ID=''
# S1_CLASSIFY_BLOCK_BEGIN
# Reads the uncertain files from S1_INPUT, a JSON file the session wrote:
# {"files": [{"path": "<path>", "signals": "<signals, separated by ;>"}]}.
# Paths and signals come from the working tree and the issue, so they are
# read with jq and passed to the helper as arguments, never as shell text.
# Only a file made by mktemp directly in TMPDIR is read: a regular file, not
# a symlink, owned by this user, with one link. It is removed once read.
# At most 8 files are asked, and none is started after 60 seconds; the rest
# print S1_ESTIMATE=none, as every file does when the decision point is not
# on. The issue is fetched once for all of them.
S1C="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-classify-s1.sh"
__s1_refused() { printf 'S1_INPUT=refused\nS1_REASON=%s\n' "$__why"; exit 0; }
__in=""
__tmpd=$(cd -P -- "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P)
__dir=""
case "${S1_INPUT:-}" in /*) __dir=$(cd -P -- "$(dirname -- "$S1_INPUT")" 2>/dev/null && pwd -P) ;; esac
if [ -z "${S1_INPUT:-}" ] || [ ! -e "$S1_INPUT" ]; then
  __why=input-missing; __s1_refused
elif [ -z "$__tmpd" ] || [ "$__dir" != "$__tmpd" ] || [ ! -f "$S1_INPUT" ] || [ -L "$S1_INPUT" ] \
     || [ -z "$(find "$S1_INPUT" -prune -type f -user "$(id -u)" -links 1 2>/dev/null)" ]; then
  __why=input-not-from-mktemp; __s1_refused
fi
# The trailing x keeps a final newline that $(...) would strip.
__in=$(cat -- "$S1_INPUT"; printf x)
__in=${__in%x}
rm -f -- "$S1_INPUT"
command -v jq >/dev/null 2>&1 || { __why=jq-missing; __s1_refused; }
# One JSON value, an object whose files are objects with a non-empty path,
# and signals and a decision that are strings when given, none of them
# holding a control character. -s reads every value in the file: without it
# jq -e takes its exit status from the last value only.
printf '%s' "$__in" | jq -s -e 'length == 1 and (.[0] | type == "object" and (.files | type == "array")
    and all(.files[]; type == "object"
      and (.path | type == "string" and length > 0 and (test("[[:cntrl:]]") | not))
      and ((.signals // "") | type == "string" and (test("[[:cntrl:]]") | not))
      and ((.decision // "") | type == "string")))' >/dev/null 2>&1 \
  || { __why=input-invalid; __s1_refused; }
__cnt=$(printf '%s' "$__in" | jq '.files | length')
# The issue cache, removed when the block ends or is stopped.
__ic=$(mktemp -d "${TMPDIR:-/tmp}/flow-classify-issue.XXXXXX" 2>/dev/null) || __ic=""
trap '[ -z "$__ic" ] || { rm -f -- "$__ic/issue.json" "$__ic/issue.failed" "$__ic/provider.failed"; rmdir -- "$__ic"; } 2>/dev/null' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# No file after the first is started after this many seconds (whole
# seconds, so the first is always asked). A call is bounded by
# systemOne.timeoutMs (at most 30 s) and the issue fetch by 10 s, so the
# block ends within about 100 s, before the Bash tool's 120 s.
__budget=60
case "${FLOW_S1_CLASSIFY_BUDGET_S:-}" in ''|*[!0-9]*|???*) ;; *) __budget=$FLOW_S1_CLASSIFY_BUDGET_S ;; esac
[ "$__budget" -le 60 ] || __budget=60
__t0=$(date +%s)
__i=0
while [ "$__i" -lt "$__cnt" ]; do
  __f=$(printf '%s' "$__in" | jq -r --argjson i "$__i" '.files[$i].path')
  __sig=$(printf '%s' "$__in" | jq -r --argjson i "$__i" '.files[$i].signals // ""')
  __i=$((__i + 1))
  if [ "$__i" -gt 8 ]; then
    printf 'S1_FILE=%s\nS1_ESTIMATE=none\nS1_REASON=not-asked-limit\n' "$__f"
    continue
  fi
  if [ ! -x "$S1C" ]; then
    printf 'S1_FILE=%s\nS1_ESTIMATE=none\nS1_REASON=helper-missing\n' "$__f"
    continue
  fi
  if [ "$__i" -gt 1 ] && [ $(( $(date +%s) - __t0 )) -ge "$__budget" ]; then
    printf 'S1_FILE=%s\nS1_ESTIMATE=none\nS1_REASON=not-asked-time\n' "$__f"
    continue
  fi
  "$S1C" ask --file "$__f" --issue "${ISSUE_NUM:-}" --signals "$__sig" --run-id "${RUN_ID:-}" --issue-cache "$__ic" < /dev/null
done
[ -z "$__ic" ] || { rm -f -- "$__ic/issue.json" "$__ic/issue.failed" "$__ic/provider.failed"; rmdir -- "$__ic"; } 2>/dev/null
__ic=""
# S1_CLASSIFY_BLOCK_END
true
```

For each file the block prints `S1_FILE=`, then `S1_ESTIMATE=`. A number is the model's estimate of how likely the change is to serve the issue (0 to 1, higher means more likely). Add `serves issue: <S1_ESTIMATE> (<S1_MODEL>)` to that file's Notes cell, followed by ` (on a shortened diff)` when `S1_TRUNCATED=true`. `S1_ESTIMATE=none` adds nothing: the table and the question are then exactly what they would be without this block, whatever `S1_REASON` says. `S1_INPUT=refused` means no file was asked: add nothing to any file. After a call that times out or cannot reach the provider, the other files of the prompt are not asked (`S1_REASON=provider-unavailable`), and no file is started after 60 seconds (`not-asked-time`). The estimate never changes the classification, the Recommendation, the options or the "Blocking?" field. The decision point `classify.serves-issue` is off unless your user settings switch it on. A repository's settings can lower its mode below yours but never raise it; in `shadow` mode the record block sends each uncertain file's diff, with the issue, to the provider configured in your user settings. See `references/system-one.md`.

**If uncertain or out-of-context files exist:**

Use the AskUserQuestion tool with a Proactive-Autonomy escalation:

> **Situation** — {N} files are classified as uncertain or out-of-context for this branch.
>
> **What I tried** — Applied change-classification signals (branch diff, issue keywords, sibling detection). These files did not match any primary signal. {When any file got an estimate: A System One model estimated how likely each uncertain file is to serve the issue; the estimate does not change the classification.}
>
> **Options**:
> 1. Include in this commit with a separate `improve:` or `chore:` commit (Recommended if changes are Boy Scout cleanup)
> 2. Exclude from this commit — leave unstaged for a separate branch
>
> **Recommendation** — Option {1|2} based on whether the changes are cleanup (include) or genuinely unrelated (exclude).
>
> **Blocking?** — Soft. The commit cannot proceed until these files are classified, but no external state depends on the outcome.
>
> **Risk** — Including out-of-context changes clutters the branch history. Excluding them leaves the work unstaged on the worktree until you address it.

**After the user answers**, run this block with the same files. The first block removed its input file, so run `mktemp` again and write, with the Write tool, the same JSON with a `decision` for each file: `{"files": [{"path": "src/utils/helper.rb", "signals": "sibling only; first-touch", "decision": "include-cleanup"}]}`. `decision` is `include` when the file is committed as part of the issue's work, `include-cleanup` when it is included as cleanup (option 1 for a Boy Scout change, in its own `improve:` or `chore:` commit), and `exclude` when it is left out. The question asks whether the change serves the issue, and cleanup does not, so `include-cleanup` records are kept apart in the comparison. Set `S1_INPUT` to the new path and `ISSUE_NUM` as before; the same rules apply. In `shadow` mode the block records each choice next to the model's answer, for the comparison that decides whether the decision point is switched on. In `shadow` mode it prints nothing, except one warning line for each file whose record could not be written, with the reason; a file past the 8th says `not-asked-limit`. In every other mode it prints nothing, whatever the input holds, and removes an input file it accepts; a file it refuses (not made by `mktemp` directly in `$TMPDIR`) is left as it was.

```bash
S1_INPUT='{the path the second mktemp printed}'
ISSUE_NUM='{the same ISSUE_NUM}'
RUN_ID=''
# S1_RECORD_BLOCK_BEGIN
# Reads the uncertain files and the user's choices from S1_INPUT, a JSON file
# the session wrote: {"files": [{"path": "<path>", "signals": "<signals>",
# "decision": "include|include-cleanup|exclude"}]}, under the same rules as
# the classify block. It asks the helper for the site's mode first. In
# shadow mode it records each choice next to the model's answer, for the
# first 8 files, none started after 60 seconds, and prints nothing except
# one warning line on stderr for each file whose record was not written, and
# why (a file past the 8th says not-asked-limit). In any other mode, or when
# the mode cannot be read, it prints nothing, whatever the input holds, and
# removes an input file it accepts.
S1C="$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/flow-classify-s1.sh"
__mode=""
[ ! -x "$S1C" ] || __mode=$("$S1C" mode </dev/null 2>/dev/null) || __mode=""
__s1_refused() { [ "$__mode" != shadow ] || printf 'flow: WARN: no System One records were written: %s\n' "$__why" >&2; exit 0; }
__in=""
__tmpd=$(cd -P -- "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P)
__dir=""
case "${S1_INPUT:-}" in /*) __dir=$(cd -P -- "$(dirname -- "$S1_INPUT")" 2>/dev/null && pwd -P) ;; esac
if [ -z "${S1_INPUT:-}" ] || [ ! -e "$S1_INPUT" ]; then
  __why=input-missing; __s1_refused
elif [ -z "$__tmpd" ] || [ "$__dir" != "$__tmpd" ] || [ ! -f "$S1_INPUT" ] || [ -L "$S1_INPUT" ] \
     || [ -z "$(find "$S1_INPUT" -prune -type f -user "$(id -u)" -links 1 2>/dev/null)" ]; then
  __why=input-not-from-mktemp; __s1_refused
fi
# The trailing x keeps a final newline that $(...) would strip.
__in=$(cat -- "$S1_INPUT"; printf x)
__in=${__in%x}
rm -f -- "$S1_INPUT"
[ "$__mode" = shadow ] || exit 0
command -v jq >/dev/null 2>&1 || { __why=jq-missing; __s1_refused; }
# One JSON value, an object whose files are objects with a non-empty path,
# and signals and a decision that are strings when given, none of them
# holding a control character. -s reads every value in the file: without it
# jq -e takes its exit status from the last value only.
printf '%s' "$__in" | jq -s -e 'length == 1 and (.[0] | type == "object" and (.files | type == "array")
    and all(.files[]; type == "object"
      and (.path | type == "string" and length > 0 and (test("[[:cntrl:]]") | not))
      and ((.signals // "") | type == "string" and (test("[[:cntrl:]]") | not))
      and ((.decision // "") | type == "string")))' >/dev/null 2>&1 \
  || { __why=input-invalid; __s1_refused; }
__cnt=$(printf '%s' "$__in" | jq '.files | length')
# The issue cache, removed when the block ends or is stopped.
__ic=$(mktemp -d "${TMPDIR:-/tmp}/flow-classify-issue.XXXXXX" 2>/dev/null) || __ic=""
trap '[ -z "$__ic" ] || { rm -f -- "$__ic/issue.json" "$__ic/issue.failed" "$__ic/provider.failed"; rmdir -- "$__ic"; } 2>/dev/null' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# No file after the first is started after this many seconds (whole
# seconds, so the first is always asked). A call is bounded by
# systemOne.timeoutMs (at most 30 s) and the issue fetch by 10 s, so the
# block ends within about 100 s, before the Bash tool's 120 s.
__budget=60
case "${FLOW_S1_CLASSIFY_BUDGET_S:-}" in ''|*[!0-9]*|???*) ;; *) __budget=$FLOW_S1_CLASSIFY_BUDGET_S ;; esac
[ "$__budget" -le 60 ] || __budget=60
__t0=$(date +%s)
__i=0
while [ "$__i" -lt "$__cnt" ]; do
  __f=$(printf '%s' "$__in" | jq -r --argjson i "$__i" '.files[$i].path')
  __sig=$(printf '%s' "$__in" | jq -r --argjson i "$__i" '.files[$i].signals // ""')
  __dec=$(printf '%s' "$__in" | jq -r --argjson i "$__i" '.files[$i].decision // ""')
  __i=$((__i + 1))
  if [ "$__i" -gt 8 ]; then
    printf 'flow: WARN: no System One record for %s: not-asked-limit\n' "$__f" >&2
    continue
  fi
  case "$__dec" in
    include|include-cleanup|exclude) ;;
    *) printf 'flow: WARN: no System One record for %s: decision-invalid (include, include-cleanup or exclude)\n' "$__f" >&2; continue ;;
  esac
  if [ "$__i" -gt 1 ] && [ $(( $(date +%s) - __t0 )) -ge "$__budget" ]; then
    printf 'flow: WARN: no System One record for %s: not-asked-time\n' "$__f" >&2
    continue
  fi
  __r=$("$S1C" record --file "$__f" --issue "${ISSUE_NUM:-}" --signals "$__sig" --decision "$__dec" --run-id "${RUN_ID:-}" --issue-cache "$__ic" < /dev/null 2>/dev/null)
  case "$?" in
    0) ;;
    2) printf 'flow: WARN: no System One record for %s: arguments-refused\n' "$__f" >&2 ;;
    *) __why=$(printf '%s\n' "$__r" | sed -n 's/^S1_REASON=//p' | head -n 1)
       printf 'flow: WARN: no System One record for %s: %s\n' "$__f" "${__why:-internal-error}" >&2 ;;
  esac
done
[ -z "$__ic" ] || { rm -f -- "$__ic/issue.json" "$__ic/issue.failed" "$__ic/provider.failed"; rmdir -- "$__ic"; } 2>/dev/null
__ic=""
# S1_RECORD_BLOCK_END
true
```

## Phase 4: COMMIT

**Group in-context files** into atomic commits by logical unit.

For each commit group:

1. **Generate commit message** following conventional format:
   - Type: inferred from changes (feat, fix, refactor, test, docs, chore, improve)
   - For Boy Scout cleanup changes, use `improve(<scope>): <summary>`
   - Scope: top-level directory or module
   - Subject: imperative, describes what and why
   - If `$ARGUMENTS` provided, use as message (validate format first)

2. **Stage and commit** (Tier 1 — autonomous):
   ```bash
   git add <specific-files>
   git commit -m "<type>(<scope>): <subject>"
   ```

3. **Verify** — the PostToolUse hook logs the commit to the decision journal.

## Phase 5: SUMMARY

Display:
- Commits created (hash + message)
- Files committed per group
- Any excluded files and why
- Suggested next step: `/flow:pr` if ready, or continue working

## Edge Cases

- **No changes**: Report "Working tree clean" and exit
- **Only untracked files**: Ask whether to include
- **All out-of-context**: Warn and require explicit confirmation
- **Mixed types**: Create separate commits per type (feat + test)

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read git status / branch / changed files | 1 | Autonomous, read-only |
| Classify changes via `change-classification` skill | 1 | Autonomous |
| `AskUserQuestion` for uncertain/out-of-context files | n/a | User-driven escalation per `references/escalation-format.md` |
| `git add <specific-files>` (per-group atomic staging) | 1 | Autonomous |
| `git commit -m "<conventional-message>"` | 1 | Autonomous, logged by `log-commits.sh` PostToolUse hook |
