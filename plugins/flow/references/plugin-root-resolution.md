# Plugin-Root Resolution (command bash blocks)

## Why this exists

Flow's slash-command `!` bash blocks invoke bundled helpers under `bin/`
(e.g. `cascade-resolve.sh`, `journal-record.sh`, `flow-active-goal.sh`). They
used to locate them with:

```bash
"${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/cascade-resolve.sh"
```

This is unsafe for **marketplace installs**:

- `CLAUDE_PLUGIN_ROOT` is documented as available in **hooks, MCP servers, LSP
  servers, monitor commands, and skill/agent content substitution** — but the
  Claude Code docs are **silent on slash-command `!` bash blocks**. It is also
  empirically **unset** when an agent runs these steps through its own Bash
  tool rather than as a first-class command invocation.
- The `:-plugins/flow` fallback only resolves when flow is checked out **in-repo**
  at `plugins/flow/` (i.e. the `synapti-marketplace` repo itself). In a consumer
  repo the plugin lives under `~/.claude/plugins/...`, so the fallback points at
  a path that does not exist and every bundled helper becomes unreachable.

Observed failure: `/flow:start` in a consumer repo with goal creation active
(`flow.goals.goalCreation: auto` or `always`) could not find `cascade-resolve.sh`,
so the FlowGoal was never created and the `/flow:merge` goal gate had nothing to
check.

Hooks are unaffected (they get `CLAUDE_PLUGIN_ROOT` per the docs), so
`hooks/scripts/*` and `bin/journal-record.sh`'s `SCRIPT_DIR` sibling resolution
need no change. This document covers **command `!` bash blocks only**.

## Canonical resolver (copy verbatim)

Command blocks use an **inline** resolver in place of the old
`${CLAUDE_PLUGIN_ROOT:-plugins/flow}` root token. It is inlined (rather than a
shared `FLOW_ROOT=` line) on purpose: each `!`/`bash` block is its own subshell
so a variable could not be shared across blocks, and substituting in place — vs.
inserting a statement — cannot disturb the surrounding statement/continuation
structure of these dense command files. Use it as the directory prefix:

```bash
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ echo plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ echo "${__p%/}";break;};done);echo "$__fr")/bin/cascade-resolve.sh"
```

For readability, the same logic in expanded form (functionally identical):

```bash
__fr="${CLAUDE_PLUGIN_ROOT:-}"
if [ ! -x "$__fr/bin/cascade-resolve.sh" ]; then
  __fr=$(
    { echo plugins/flow
      ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null | sort -Vr
      echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"
    } | while read -r __p; do
      [ -x "${__p%/}/bin/cascade-resolve.sh" ] && { echo "${__p%/}"; break; }
    done)
fi
# "$__fr" is now the plugin root (empty if nothing resolved — guard before use).
```

Resolution order (first match with an executable `bin/cascade-resolve.sh` wins):

1. `$CLAUDE_PLUGIN_ROOT` — authoritative when a real command context sets it.
2. `plugins/flow` — in-repo checkout (developing flow inside `synapti-marketplace`).
3. highest-semver marketplace **cache** install
   (`~/.claude/plugins/cache/synapti-marketplace/flow/<version>/`), newest via `sort -Vr`.
4. `~/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow` — marketplaces checkout.

## Loud-fail contract

A command block MUST NOT silently degrade when the root cannot be found. When
nothing resolves, the inline resolver yields an empty string, so the helper path
becomes `/bin/cascade-resolve.sh` (not executable) — the block's existing
`[ ! -x "$CASCADE" ]`-style guard then fires its `*_STATE=blocked` sentinel:

```bash
CASCADE="$(...resolver...)/bin/cascade-resolve.sh"
if [ ! -x "$CASCADE" ]; then
  echo "FLOW_GOAL_STATE=blocked"
  echo "FLOW_GOAL_ERROR=cascade-resolve.sh missing or non-executable at $CASCADE — reinstall or upgrade the flow plugin"
  true; exit 0
fi
```

Any block that assigns the resolved helper to a variable and guards
`[ -x "$VAR" ]` before use inherits this loud-fail behavior automatically.

## Known tradeoffs

- The cache-glob heuristic (step 3) picks the **highest installed version**,
  which may differ from the version Claude Code would load when
  `CLAUDE_PLUGIN_ROOT` is set. It only fires as a fallback, and "newest
  installed" is strictly better than "unreachable."
- The marketplace slug `synapti-marketplace` is hardcoded — flow ships from it.
- Unquoted command substitution word-splits on whitespace; `$HOME` cache paths
  under `~/.claude/plugins/` do not contain spaces in practice.
