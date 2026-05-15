# Flow command authoring patterns

Canonical patterns established by PR #103 (`feat(flow): extract findings-ledger
aggregation to bin/ helper` + 7 `!`-prefix refactors + cycle-1/cycle-2/audit
hardening). Read this before modifying any flow command — these patterns
solved real regressions, and the regressions will come back if the patterns
are dropped.

The PR-103 test suite (`plugins/flow/tests/*.test.sh`) enforces patterns 1-4
mechanically. Pattern 5 is a render-rule contract checked by `/flow:status`
itself.

---

## Pattern 1: `!` block end-of-block discipline

Every `!` block in a command's body MUST end with an explicit `true` statement
(optionally followed by a comment).

### Why

Claude Code surfaces a non-zero exit from a `!` block as "command failed" and
suppresses the captured stdout — context the LLM needs disappears. A trailing
pipeline like `grep -c '<<<<<<<' "$f" || echo 0` looks innocuous, but on an
empty match `grep` exits 1 and the shell propagates that as the block's exit
code. The block's stdout, which downstream phases depend on, never reaches
the prompt.

The mitigation is a trailing `true`: it always succeeds, so the block's exit
code is deterministic regardless of the upstream pipeline.

### How to apply

```!
# ... bash that may end in a pipeline, conditional, or grep ...
git diff --name-only --diff-filter=U | while IFS= read -r f; do
  [ -f "$f" ] && echo "$f: $(grep -c '<<<<<<<' "$f" || echo 0) hunks" || true
done

true  # explicit success — block exit reflects intent, not the trailing pipeline
```

### Source incident

F3 (cycle-1) and F3-follow-up (audit pass) — both caught only because we
re-verified `!` block exits after the first review missed a Phase 1 block in
`commands/start.md`. The audit pass uncovered that even with `F3` documented,
a single block on the second-most-touched file still didn't have the trailing
`true`. Without automation, this class of bug returns on every refactor.

### Enforcement

`plugins/flow/tests/command-frontmatter.test.sh` test 1 lints every `!` block
in every PR-103-touched command for `^true([[:space:]]*#.*)?$` as the last
non-blank, non-comment line.

---

## Pattern 2: `$ARGUMENTS` validation and pinning

Before substituting `$ARGUMENTS` into any bash, validate it with a `case`
statement and pin it to a sanitized variable.

### Why

Claude Code's `$ARGUMENTS` substitution model in `!` blocks is empirically
env-var-style (word-splitting only, not template substitution), but the model
is undocumented and the defensive pattern handles both possibilities. Without
validation, a hostile `$ARGUMENTS` value can either:

- Inject extra shell words via word-splitting (env-var model), or
- Inject arbitrary characters via direct template substitution (template
  model, if Claude Code ever changes)

Pinning to `PR_NUM` / `ISSUE_NUM` after the case validation gives downstream
blocks a guaranteed-safe value to reference.

### How to apply

For numeric arguments (PR or issue numbers):

```!
case "${ARGUMENTS:-}" in
  '')        echo "ERROR: PR number required. Usage: /flow:address <pr-number>"; exit 1 ;;
  *[!0-9]*)  echo "ERROR: PR number must be numeric"; exit 1 ;;
esac
PR_NUM="$ARGUMENTS"
echo "PR_NUM=$PR_NUM"
```

For more permissive arguments (branch names, refs):

```!
case "$ARGUMENTS" in
  '') echo "ERROR: branch name required"; exit 1 ;;
  *[!A-Za-z0-9._/-]*) echo "ERROR: invalid characters in branch name"; exit 1 ;;
esac
```

After validation, downstream `bash` blocks reference the pinned variable —
NOT `$ARGUMENTS` directly — since `!` blocks don't share shell state and
re-deriving validation in every block is a maintenance burden.

### Source incidents

F2, F6 (cycle-1). The original security agent report on PR #103 flagged
`$ARGUMENTS` as a P1 injection vector based on a misread of Claude Code's
substitution model. Empirical testing showed env-var-style word-splitting,
not template substitution, but the defensive pattern remains because:
(a) the substitution model is undocumented, (b) word-splitting alone is
still a risk for unvalidated inputs.

### Enforcement

`plugins/flow/tests/command-frontmatter.test.sh` test 2 verifies every `!`
block using `$ARGUMENTS` contains a `case "${ARGUMENTS` validation.

---

## Pattern 3: `KEY=VALUE` echo for cross-block state

When a `!` block needs to pass state to a later `!` block or to an inline
`bash` block, emit literal `KEY=value` lines. The LLM substitutes them into
subsequent blocks as it composes its tool calls.

### Why

`!` blocks run in independent subshells. Shell variables set in one block
do not propagate to another, and Claude Code does not provide a mechanism
to share environment between `!` invocations. Without an explicit
inter-block contract, the LLM has to re-derive every value (re-running `git
branch --show-current`, re-fetching the issue), which is slow and produces
inconsistent results when state changes between calls.

The `KEY=value` echo pattern is the lightest possible IPC: the LLM reads
the values from the `!` block's captured stdout and substitutes them as
literals into later blocks.

### How to apply

In an early `!` block:

```!
BRANCH=$(git branch --show-current)
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
ISSUE_NUM=$(echo "$BRANCH" | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+')
echo "BRANCH=$BRANCH"
echo "DEFAULT_BRANCH=$DEFAULT_BRANCH"
echo "ISSUE_NUM=$ISSUE_NUM"
true
```

In a later inline block, the LLM literally substitutes the values:

```bash
git checkout $BRANCH   # becomes: git checkout claude/flow-plugin-exclamation-prefix-m2Ye5
```

### Sentinel KEY=VALUE conventions established by this PR

- `BRANCH=<name>` / `DEFAULT_BRANCH=<name>` — git context (start.md, pr.md)
- `ISSUE_NUM=<n>` / `PR_NUM=<n>` — validated numeric arguments
- `JOURNAL_DIR=<path>` / `PROPOSAL_DIR=<path>` — resolved settings paths (learn.md)
- `COMMITS_AHEAD=unknown` — explicit absence sentinel (status.md, when
  `rev-parse` can't verify the default branch ref)
- `ISSUES_UNAVAILABLE=1` — gh-failure sentinel (status.md, when `gh issue
  list` exits non-zero)
- `LEDGER: unavailable` / `LEDGER: partial` — helper-emit sentinels
  (aggregate-findings-ledger.sh, consumed by status.md render rules)

### Source

Established in `commit.md`, then generalized across the 8 modified commands
during cycle-2 hardening (commits `7f6e50c` and `bf144b8`).

---

## Pattern 4: `allowed-tools` literal-text matching

Every helper invocation in a command's body must have a matching
`allowed-tools` frontmatter entry in the exact form:

```yaml
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/<script>.sh:*)
```

The body must invoke the helper using the **same** literal string:

```bash
"${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/<script>.sh"
```

### Why

Claude Code's `allowed-tools` permission system matches the literal markdown
text of the `Bash(...)` invocation, NOT the runtime-resolved command. When
a plugin is installed to `~/.claude/plugins/synapti/flow/`,
`${CLAUDE_PLUGIN_ROOT}` resolves to that absolute path — but the
`allowed-tools` pattern is parsed at command-load time from the markdown,
before substitution. The literal text must match.

The pre-fix form `Bash(bash plugins/flow/bin/<script>.sh:*)` (with a literal
`bash` prefix and no `${CLAUDE_PLUGIN_ROOT}` reference) works in dev when
the user runs from the repo root but fails as a marketplace install — the
literal path `plugins/flow/...` doesn't exist under
`~/.claude/plugins/.../`. The permission system rejects the invocation as
unmatched, and the command errors out for every marketplace user.

Verified empirically against the official `ralph-loop` plugin
(`plugins/ralph-loop/commands/ralph-loop.md`), which uses the
`Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh:*)` form for the
same reason.

### How to apply

```yaml
---
allowed-tools: ... Bash(${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/aggregate-findings-ledger.sh:*) ...
---
```

```bash
# In the body:
"${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/aggregate-findings-ledger.sh"
```

The `:-plugins/flow` default keeps dev-from-repo-root invocations working;
the brace form `${CLAUDE_PLUGIN_ROOT:-plugins/flow}` is critical — without
braces, bash parses the `:-` as part of the variable name.

### Source incident

C1 (cycle-2) and C1-follow-up (audit pass). C1 was discovered only because
adversarial review compared `status.md`'s helper invocation against
ralph-loop's working pattern. Without that side-by-side, the C1 regression
would have shipped and broken `/flow:status` for every marketplace install.

C1-follow-up caught three additional commands (`start.md`, `pr.md`,
`learn.md`) that had updated their helper invocations to the correct form
but kept the dead `Bash(bash plugins/flow/bin/*)` pattern in
`allowed-tools` — silent landmines for the next refactor.

### Enforcement

- `plugins/flow/tests/command-frontmatter.test.sh` test 3 verifies every
  `Bash(${CLAUDE_PLUGIN_ROOT...}/bin/...)` `allowed-tools` entry has a
  matching script-name reference in the body.
- Test 4 explicitly rejects the dead `Bash(bash plugins/flow/bin/...)` form.

---

## Pattern 5: LEDGER render-rule contract

`plugins/flow/bin/aggregate-findings-ledger.sh` emits structured output
that `commands/status.md` consumes via documented render rules. The
contract is:

| Helper stdout line | Renderer (status.md) interpretation |
|---|---|
| `<count> P<n>\|<state>` | Tally row for `<state>` findings at priority `P<n>` |
| `LEDGER: unavailable (<reason>)` | Skip the section, render the reason verbatim |
| `LEDGER: partial (<reason>)` | Render available rows + caveat |
| `LEDGER_WARN: <msg>` (stderr) | Captured into a footnote; not user-facing in the table |

### Why

The helper is invoked from `status.md` as a single `!` block:

```!
"${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/aggregate-findings-ledger.sh"
true
```

The LLM sees both stdout and stderr in the captured output. Without an
explicit contract for what each line shape means, the renderer would have
to re-parse the output every time the helper changes. The `LEDGER:` /
`LEDGER_WARN:` prefixes are stable; downstream consumers grep for them.

### How to apply

When extending the helper to emit a new control state:
1. Use the `LEDGER:` stdout prefix or `LEDGER_WARN:` stderr prefix
2. Add the new line shape to status.md's render-rule documentation block
3. Add a fixture + test case to
   `plugins/flow/tests/aggregate-findings-ledger.test.sh`

### Source

Established during the helper extraction in commit `63f8e91` and refined
through cycles 1 and 2.

---

## Decision: `disable-model-invocation` for Tier 3 commands

`commands/release.md` and `commands/merge.md` are classified as Tier 3
(confirm-required, never autonomous). Both rely on `AskUserQuestion` at
execution time as the human-confirmation gate.

**Decision (PR-103 audit pass)**: Set `disable-model-invocation: true` on
both files.

### Why

`AskUserQuestion` is sufficient when a human types `/flow:merge 123` in the
terminal — the prompt blocks until the user answers. But it does NOT block
the Claude Code `SlashCommand` tool, which an autonomous agent could use
to programmatically invoke a slash command. In a fully-autonomous loop, the
agent could call `SlashCommand` with `/flow:merge 123`, and the
`AskUserQuestion` prompt would itself become an LLM-handled interaction —
defeating the human-gate.

Setting `disable-model-invocation: true` prevents `SlashCommand` from
calling the command at all. The command stays invocable by humans typing
`/flow:merge` in the prompt; it just cannot be invoked programmatically by
the LLM. Tier 3 should be Tier 3 against autonomous agents too.

### What if we don't want this?

If you ever need an agent to run `/flow:release` autonomously (e.g., a
release-cutting bot), build a separate command (`/flow:release-bot`) with
its own narrower safety guarantees rather than weakening the Tier 3 gate.

---

## Cross-references

The 8 PR-103-modified commands (`address.md`, `commit.md`, `learn.md`,
`pr.md`, `release.md`, `resolve.md`, `start.md`, `status.md`) each follow
patterns 1-4 in their bodies. Cross-reference comments near the top of
each file point here. When writing a new flow command, copy from one of
these as a starting template.

Test suite: `plugins/flow/tests/` — pure-bash, no external framework,
runs in CI on every PR that touches the helper scripts or the commands.
