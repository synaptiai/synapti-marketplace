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
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ printf '%s\n' plugins/flow;ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/cascade-resolve.sh"
```

For readability, the same logic in expanded form (functionally identical):

```bash
__fr="${CLAUDE_PLUGIN_ROOT:-}"
if [ ! -x "$__fr/bin/cascade-resolve.sh" ]; then
  __fr=$(
    { printf '%s\n' plugins/flow
      ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null | sort -Vr
      printf '%s\n' "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"
    } | while read -r __p; do
      [ -x "${__p%/}/bin/cascade-resolve.sh" ] && { printf '%s\n' "${__p%/}"; break; }
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

## The post-checkout form (copy verbatim)

Candidate 2 above — the working-directory-relative `plugins/flow` — is what lets
flow run from a bare checkout of its own repository. After `gh pr checkout` it is
something else: the working tree belongs to the pull request, including a fork's,
so a branch that ships `plugins/flow/bin/cascade-resolve.sh` supplies the helper
that answers the settings query judging it. Verified: such a branch's own
`cascade-resolve.sh`, `flow-clone-scan.sh` and `flow-dep-diff.sh` all executed,
and the last printed a forged clean dependency verdict.

**Placement rule.** Every resolver that runs after a `gh pr checkout`, and every
resolver in an agent dispatched by `/flow:review` or `/flow:address`, uses the
form below. Everything else keeps the form above: a developer running
`/flow:start` in the flow repository is working on their own tree, and the
in-repo candidate winning there is the point.

"After" means execution order, not line order. A ```` ```! ```` fence is
expanded before the command body runs, so every `!` fence in a command runs
before every inline ```` ```bash ```` fence, whatever their line numbers. Both
`/flow:review` and `/flow:address` put their `gh pr checkout` in an inline
fence and say so in as many words, which makes every `!` fence in them author
context — the working tree is still the user's own. Classifying by line number
instead put the post-checkout form in three `!` fences, and in a bare checkout
of flow with no marketplace install that resolves to nothing and blocks the
run, which is the case the author-context form exists to serve.

The post-checkout form drops the working-directory-relative `plugins/flow`
candidate outright. That candidate is the working tree by construction, so after
a checkout it can only ever be the branch's own copy; keeping it and skipping it
conditionally left the defence resting on `git rev-parse --show-toplevel`
succeeding, and it does not always. On the Linux CI runner a work tree that does
not exist makes rev-parse fail rather than report the path, `$__t` is then empty,
nothing is skipped, and the branch's copy wins — while macOS printed the path and
the same check passed. Removing the candidate makes the branch's tree unreachable
whatever git says.

The remaining candidates are all absolute — `$CLAUDE_PLUGIN_ROOT`, the cache
installs, the marketplaces checkout — and any of those can still be made to point
inside the repository under review, so the form also skips a candidate whose
physical path lies inside it and tries the next one rather than giving up: flow's
own repository is such a checkout, so refusing outright made every self-review of
flow report unavailable while an installed copy sat unused.

```bash
"$(__t=$(git rev-parse --show-toplevel 2>/dev/null);__x=0;[ -z "$__t" ]||{ __t=$(cd "$__t" 2>/dev/null&&pwd -P);[ -n "$__t" ]||__x=1; };[ "$__x" = 1 ]||{ printf '%s\n' "${CLAUDE_PLUGIN_ROOT:-}";ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow"; }|while read -r __p;do __p=${__p%/};[ -n "$__p" ]&&[ -x "$__p/bin/cascade-resolve.sh" ]||continue;__r=$(cd "$__p" 2>/dev/null&&pwd -P)||continue;[ -n "$__r" ]||continue;[ -z "$__t" ]||case "$__r/" in ("$__t"/*) continue;; esac;printf '%s\n' "$__r";break;done)/bin/cascade-resolve.sh"
```

Three details are load-bearing:

- The leading `(` in `case "$__r/" in ("$__t"/*)`. Inside `$( )`, bash reads an
  unparenthesised case pattern's `)` as the end of the substitution and fails to
  parse.
- `[ -z "$__t" ]||{ ...; }` around the `cd`. On bash 3.2, `cd ""` returns 0 and
  leaves the working directory alone, so running the `cd` unconditionally turned
  "not a git repository" into "every candidate under the working directory is
  in-repository" — and a resolver run from `$HOME` then refused the install
  sitting under it.
- `__x=1` when the repository root resolves but cannot be entered, and the
  `[ "$__x" = 1 ]||{ ... }` that then produces no candidates at all. This was
  first written as `__t=/`, relying on the skip pattern to match every absolute
  path — twice wrongly. Unstripped it read `//*`, which needs two leading
  slashes and matched nothing. Stripped to `""/*` it matched everything on bash
  3.2 and nothing on the bash the Linux runner ships, so the same source was
  fail-closed on one platform and fail-open on the other. A flag has no such
  reading: when it is set the candidate list is never generated, so nothing can
  be selected.

An agent whose output is a three-state contract wraps the same expression and
turns the empty result into its own `STATE=unavailable` line, between the
`# FLOW_ROOT_BEGIN` and `# FLOW_ROOT_END` sentinels that
`tests/duplication-contract.test.sh` walks.

## The install-preferring form, for the two commands that review a pull request

`/flow:review` and `/flow:address` put their `gh pr checkout` in an inline fence, so their
`!` fences run before it and the working tree is still the user's own — the first time. It
is not the only time. A session that has already run one of them, or a user who ran
`gh pr checkout` themselves, leaves a pull request's tree in place, and the `!` fences then
execute helpers out of it: `flow-load-skills.sh`, which loads the skills that govern the
review, `flow-pr-linked-issue.sh`, `flow-review-exceptions.sh`, `cascade-resolve.sh`.

Those eight fences use the form below. It is the author-context form with the
working-directory-relative `plugins/flow` moved to LAST, so an installed copy is preferred
and the bare checkout of flow still works when nothing else exists:

```bash
"$(__fr="${CLAUDE_PLUGIN_ROOT:-}";[ -x "$__fr/bin/cascade-resolve.sh" ]||__fr=$({ ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/flow/*/ 2>/dev/null|sort -Vr;printf '%s\n' "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/flow" plugins/flow; }|while read -r __p;do [ -x "${__p%/}/bin/cascade-resolve.sh" ]&&{ printf '%s\n' "${__p%/}";break;};done);printf '%s\n' "$__fr")/bin/cascade-resolve.sh"
```

The cost is that a developer editing `plugins/flow` in this repository, with flow also
installed, has `/flow:review` and `/flow:address` run the installed copy rather than their
edits. That is the same consequence the post-checkout form already has, and these two
commands are the ones whose whole job is to act on someone else's branch.

## Loud-fail contract

A command block MUST NOT silently degrade when the root cannot be found. When
nothing resolves, the inline resolver yields an empty string, so the helper path
becomes `/bin/cascade-resolve.sh` (not executable) — the block's existing
`[ ! -x "$CASCADE" ]`-style guard then fires its `*_STATE=blocked` sentinel:

```bash
CASCADE="$(...resolver...)/bin/cascade-resolve.sh"
if [ ! -x "$CASCADE" ]; then
  printf '%s\n' "FLOW_GOAL_STATE=blocked"
  printf '%s\n' "FLOW_GOAL_ERROR=cascade-resolve.sh missing or non-executable at $CASCADE — reinstall or upgrade the flow plugin"
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
