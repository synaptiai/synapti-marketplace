# Command `!` block output format

Reference document. The canonical shape every `!`-prefixed bash block in `commands/*.md` should emit to stdout. The output is the **agent-readable context**: Claude Code pre-executes the block at command load and injects its stdout into the prompt where the fence was. There is no other reader — no downstream bash parses this output, and the source of the block is not visible to the agent. The shape below optimizes for one job: a fresh-session agent reading the rendered prompt top-to-bottom should know what every line is without re-reading the command file.

## Why this format

The first cycle of the `!`-prefix refactor emitted bare command output — `git branch --show-current` produced just `feature/flow-bang-prefix-context`, with no label. The agent had to map unlabeled lines to the right Display-template cell by inference from section ordering. With two `[]` lines from different `gh pr list` queries, the inference is brittle and silently breaks if the bash order drifts.

The format here trades 1-2 lines of extra stdout per block for a deterministic agent-readable contract:

- Section headings (`###`) match the Display template the agent will render into, so the mapping is name-to-name, not position-to-position.
- `KEY=value` lines turn every scalar into a named field. Bash-order drift becomes harmless.
- One labeled record per line (`PR=104 state=OPEN review=(none) ...`) replaces multi-line JSON the agent would otherwise have to mentally parse.
- Empty list-sections emit `STATE=empty` so the agent matches a closed vocabulary instead of inferring meaning from silence.

The pattern follows the same house style as `references/evidence-bundle-format.md` (markdown `###` headings nesting structured fields) and `references/finding-schema.md` (named fields, controlled vocabulary, enums).

## Shape

```markdown
### {Section name}
KEY=value
KEY=value
RECORD_LABEL=key1=val1 key2=val2 key3="quoted string"

### {Next section}
STATE=ok|empty|blocked|unavailable
ERROR=human-readable message     # only when STATE=blocked
KEY=value                        # only when STATE=ok
```

### Rules

1. **Each logical section gets a `###` heading.** Heading text matches the Display-template heading where one exists (e.g., `### Current Branch`, `### My PRs`). For commands without a Display template, use a semantic name (`### Branch Context`, `### Issue Reference`).

2. **Scalars use `KEY=value`.** No quoting required for single-token values. Use `KEY="value with spaces"` only when the value contains whitespace or shell metacharacters that would confuse a future bash consumer.

3. **Records use one labeled line per entity.** A PR row becomes `PR=104 state=OPEN review=APPROVED checks=2/2-SUCCESS title="refactor: ..."`. The agent reads multiple records by reading multiple lines under the same heading. Field order within a record SHOULD be stable across runs.

4. **Empty list-sections emit a positive sentinel.** Use `STATE=empty` (not silence, not `(none)`). The agent matches against the closed vocabulary `ok | empty | blocked | unavailable` — never against the empty string.

5. **Error paths emit `STATE=blocked` + `ERROR=<message>`.** Replace inline `ERROR: ...` prefixes with the two-field form. The agent halts on `STATE=blocked` without parsing the message.

6. **Unavailable states emit `STATE=unavailable` (or `<SECTION>_STATE=unavailable` when the section name is part of the contract, e.g., `LEDGER_STATE=unavailable`).** Reserved for transient infrastructure failures (gh API down, network unreachable). Distinct from `empty` — `unavailable` means "we don't know," `empty` means "we know there are zero."

7. **Sections are separated by a blank `echo ""`.** Improves visual scanability in the rendered prompt without adding meaningful tokens.

8. **The block always ends with `true`.** Inherited from the `!`-prefix discipline — guarantees exit 0 regardless of trailing pipeline behavior. See `references/finding-ledger-parser.md` for the same convention applied to marker blocks.

### Sentinels — closed vocabulary

| Sentinel | Meaning | When |
|---|---|---|
| `STATE=ok` | section's primary call succeeded; data follows | optional — agents may default to `ok` when no `STATE=` line is emitted under a section that has data |
| `STATE=empty` | section's call succeeded; result set is empty | use for `gh pr list` returning `[]`, `git status --porcelain` with no output, etc. |
| `STATE=blocked` | input validation failed; section cannot proceed | use after permissive-arg-extraction rejects a non-digit `$PR_NUM`, missing required positional, etc. |
| `STATE=unavailable` | infrastructure failure; cannot determine state | use when `gh` exits non-zero, the network is unreachable, or a required helper is missing |

Per-section state variables (e.g., `LEDGER_STATE=`, `PREFLIGHT_STATE=`) follow the same vocabulary when they signal the same conditions (`ok`, `empty`, `blocked`, `unavailable`). The bare `STATE=` variable is always restricted to the four sentinels above. For richer domain-specific state machines, see "Domain-specific state vocabularies" below.

### Domain-specific state vocabularies

A section MAY define a richer state vocabulary by introducing a `<DOMAIN>_STATE=` variable distinct from `STATE=`. This is allowed when the domain has more than four mutually exclusive outcomes that downstream rendering rules need to distinguish. The domain vocabulary MUST be:

- Closed (enumerated explicitly at the consumer site — no free-text values).
- Documented inline next to the consumer's Render Rules so the agent knows which values are valid.
- Distinct from the bare `STATE=` sentinel — never shadow or extend `STATE=`'s four-value set.

The canonical example is `LEDGER_STATE=`, defined by `/flow:status`'s Findings-Ledger section: `{findings, no_markers, no_open_prs, unavailable}`. The Render Rules in `commands/status.md` enumerate the four values and the per-value template. Without this extension the section would have to collapse "no markers yet" and "no open PRs" into the same `empty` sentinel, losing useful diagnostic information.

When in doubt, prefer the four-value `STATE=` and add diagnostic detail in a separate `ERROR=` / `<KEY>=` line rather than extending the closed vocabulary.

## Worked example — `/flow:status` ! block #1

Before (cycle-1 raw output — 8 unlabeled lines):

```
feature/flow-bang-prefix-context
?? .handoff-pr103.md
29
[]
[{"number":104,"reviewDecision":"","state":"OPEN","statusCheckRollup":[{"__typename":"CheckRun",...long JSON...}]}]
[]
       6
LEARNING PENDING: 2026-05-15
```

After:

```
### Current Branch
BRANCH=feature/flow-bang-prefix-context
DEFAULT_BRANCH=main
COMMITS_AHEAD=29
UNCOMMITTED_COUNT=1
UNCOMMITTED_LINE=?? .handoff-pr103.md

### My Issues (Open)
ASSIGNED_COUNT=0
STATE=empty

### My PRs
AUTHORED_COUNT=1
PR=104 state=OPEN review=(none) checks=2/2-SUCCESS title="refactor(flow): pre-execute read-only context via `!` prefix"

### Awaiting My Review
REVIEW_REQUESTED_COUNT=0
STATE=empty

### Decision Journal
JOURNAL_DIR=.decisions
JOURNAL_FILES=6
LEARNING_PENDING=2026-05-15
```

The agent renders the Display template by reading section-by-section. Section names line up 1:1; field names are explicit; the JSON blob has been pre-parsed via `--jq` into a single labeled line.

## Worked example — `/flow:merge` ledger gate (state machine)

The ledger gate has four mutually exclusive outcomes. With the format above, each is a single line:

```
### Findings Ledger
LEDGER_STATE=findings
TALLY_P1_in_fix_forward=2
TALLY_P2_escalated=1
TALLY_P3_in_fix_forward=3
```

```
### Findings Ledger
LEDGER_STATE=no_markers
```

```
### Findings Ledger
LEDGER_STATE=no_open_prs
```

```
### Findings Ledger
LEDGER_STATE=unavailable
```

The agent matches against the closed vocabulary `{findings, no_markers, no_open_prs, unavailable}` to choose the right Render Rule branch, then (for `findings` only) reads the `TALLY_<PRIORITY>_<STATE>` lines.

## Pre-shaping JSON for the agent

When a block calls `gh ... --json ...`, the raw JSON is rarely the right shape for agent consumption. Use `--jq` to reduce it to one labeled record per line.

Bad:

```bash
gh pr list --author @me --state open --json number,title,state,reviewDecision,statusCheckRollup
```

Good:

```bash
gh pr list --author @me --state open --json number,title,state,reviewDecision,statusCheckRollup --jq '
  .[] | (
    [.statusCheckRollup[]? | select(.__typename == "CheckRun")] as $checks |
    "PR=\(.number) state=\(.state) review=\(.reviewDecision // "(none)") checks=\($checks | map(select(.conclusion == "SUCCESS")) | length)/\($checks | length) title=\"\(.title)\""
  )'
```

Trade-off: shifts JSON-parsing work from the agent (token-expensive, error-prone) into bash (cheap, deterministic). Field selection happens once in bash; agent reads the labeled record directly. For richer record shapes that don't fit one line cleanly, fall back to a `### Sub-heading` per record:

```
### My PRs

#### PR 104
PR=104
state=OPEN
review=(none)
checks=2/2-SUCCESS
title=refactor(flow): pre-execute read-only context via `!` prefix
review_count=1
comment_count=4
```

Use the per-record subheading form sparingly — it's verbose. Single-line records cover most cases.

## Quoting conventions

- Scalars without whitespace or shell metacharacters: bare. `BRANCH=feature/foo-bar.v2`
- Scalars with whitespace: double-quoted. `TITLE="refactor: pre-execute via ! prefix"`
- Backticks inside titles: pass through unescaped if double-quoted. Agents read them as literal characters.
- Newlines in values: AVOID. If a value naturally contains newlines (a multi-paragraph PR body, a multi-line diff), use the per-record subheading form and let the value occupy multiple unlabeled lines beneath a `BODY=` or `DIFF=` marker line.

## Bash patterns

### Function wrap for nested case-in-substitution

Bash's `$(...)` paren-matching collides with `*)` case-arm patterns. When you need a `case` statement inside a captured pipeline:

```bash
# Wrong — bash sees the case `*)` as closing the substitution
TALLY=$(for x in $items; do
  case "$x" in
    valid) ;;
    *) echo "WARN: bad $x" >&2; continue ;;
  esac
  echo "$x"
done | sort | uniq -c)
```

```bash
# Right — function isolates the case from outer paren counting
_collect_tally() {
  for x in $items; do
    case "$x" in
      valid) ;;
      *) echo "WARN: bad $x" >&2; continue ;;
    esac
    echo "$x"
  done | sort | uniq -c
}
TALLY=$(_collect_tally)
```

### Cross-block state via stdout echo

When a Phase 1 `!` block extracts state (e.g., `PR_NUM` from `$ARGUMENTS`) that subsequent inline `bash` blocks need, echo it explicitly:

```bash
echo "PR_NUM=$PR_NUM"
```

The agent reads the echoed value from the prompt context and substitutes it into later Bash tool calls. This is how the rendered prompt carries state between blocks — bash variables do NOT persist across separate Bash tool invocations.

### Stderr suppression discipline

Every `gh` call that returns stdout the agent will consume should use `2>/dev/null`. Network errors, auth failures, and rate-limit messages otherwise leak into prompt context as `command failed`-style noise where the agent expects structured data.

## When to deviate

This format is the default. Deviate only when:

1. The block is a marker-emitting helper called from inside the bash (not directly read by the agent). Those use pipe-separated forms documented in `references/finding-ledger-parser.md` and `references/finding-schema.md`.

2. The output is a verbatim user-visible diagnostic that the agent should echo unchanged (e.g., a `PREFLIGHT: BLOCKED` banner). In that case, keep the verbatim diagnostic AND add the structured form alongside, so the agent has both presentations available.

3. A downstream bash consumer parses the output (none exist today across the flow plugin; if one is added, document the contract here and at the consumer site).

In all other cases, follow the rules above.
