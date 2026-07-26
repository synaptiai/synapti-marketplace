# Configuration Resolution

How every dossier command, script, and skill finds its settings. Read this before adding a config key or debugging a "why did it use that value" question.

## Precedence chain

Six layers, highest first. The first layer that produces a non-empty, non-`null` value wins.

| # | Layer | Path | Committed? | Purpose |
|---|-------|------|-----------|---------|
| 0 | Environment | `DOSSIER_<UPPER_SNAKE>` | n/a | **What makes a CI job zero-interaction.** Overrides everything. |
| 1 | Explicit file | `$DOSSIER_CONFIG` | n/a | A named config for one-off runs against a project you do not own. |
| 2 | Project-local | `.claude/settings.dossier.local.json` | No — gitignored, and **ignored if tracked** | Personal overrides. Never shared. |
| 3 | Project-shared | `.claude/settings.dossier.json` | Yes | The team's answer. What `/dossier:setup` writes. |
| 4 | User-global | `$HOME/.claude/settings.dossier.json` | n/a | Your defaults across every project. |
| 5 | Plugin default | `${CLAUDE_PLUGIN_ROOT}/settings.json` | Yes (in the plugin) | The shipped baseline. Every key has one. |

**The project-local layer is admitted on evidence that it is untracked, not that it exists.** It outranks every other source, and it earns that rank by being one operator's machine-specific file. Committing it inverts the reasoning: a tracked `.local.json` reaching an unattended run is the highest-precedence layer of the settings a pull request can change, silently outranking `ci.writeAllowlist`, `disclosure.policy`, and `engagement.allowedActions` for every run afterwards. `cascade-resolve.sh` therefore checks `git ls-files` and skips the layer with a warning when it is tracked, rather than trusting the `.gitignore` entry `/dossier:init` writes to still be there.

Layers 2–5 are read by `bin/cascade-resolve.sh`, which is a behavioural twin of the flow plugin's script of the same name — a fix to cascade semantics in either plugin ports directly to the other. Layers 0 and 1 are added by `bin/dossier-resolve-config.sh`, which wraps it.

## Reading a value

```bash
# Single key, with a fallback when no layer has it
bin/dossier-resolve-config.sh --default "docs/dossier" dossier.project.outputRoot

# Preserve JSON quoting (arrays, objects)
bin/dossier-resolve-config.sh --compact dossier.ci.pathFilters.include

# The whole merged object, lowest-to-highest precedence
bin/dossier-resolve-config.sh --json
```

`--json` merges layers 1–5 with jq's `*` operator so a project file that sets one key does not erase its siblings. Environment overrides are **not** folded into `--json` output: they are scalar by nature, and a caller that needs one should ask for that key directly.

## Environment variable naming

Drop the leading `dossier.`, replace dots with underscores, split camelCase on the case boundary, upper-case, prefix `DOSSIER_`.

| Config key | Environment variable |
|---|---|
| `dossier.ci.enabled` | `DOSSIER_CI_ENABLED` |
| `dossier.project.outputRoot` | `DOSSIER_PROJECT_OUTPUT_ROOT` |
| `dossier.engagement.deliveryMode` | `DOSSIER_ENGAGEMENT_DELIVERY_MODE` |
| `dossier.ci.agent.maxTurns` | `DOSSIER_CI_AGENT_MAX_TURNS` |
| `dossier.gate.minScore` | `DOSSIER_GATE_MIN_SCORE` |

Scalars only. There is deliberately no environment syntax for arrays and objects — a `pathFilters.include` list smuggled through an environment variable would be unreviewable, and the whole point of the CI design is that policy lives in a file a human can read in a diff.

## Why the resolver passes a bare jq path

`bin/dossier-resolve-config.sh` resolves `.dossier.ci.enabled` — with **no** `//` alternative operator appended. This is deliberate and easy to "fix" wrongly.

jq's `//` is **falsy**-triggered, not null-triggered:

```bash
$ echo '{"a":false}' | jq -r '.a // null'
null              # WRONG — an explicit false reports as not-found
$ echo '{"a":false}' | jq -r '.a // empty'
                  # WRONG — same defect, now indistinguishable from absent
$ echo '{"a":false}' | jq -r '.a'
false             # correct
$ echo '{}' | jq -r '.a'
null              # correct — cascade-resolve.sh treats "null" as not-found
```

With either alternative operator, a feature a user explicitly disabled in a project file resolves as not-found, the cascade falls through to the next layer, and the plugin silently re-enables it. The bare path distinguishes "set to false" from "not set" correctly, because `cascade-resolve.sh` already treats the literal string `null` as not-found and prints `false` as a real value.

Do not add `// null` or `// empty` to a cascade lookup.

## Why the schema does not express conditional requirements

`schema.json` contains no `oneOf`, `anyOf`, or `if`/`then`. This is deliberate.

The repo's documented fallback validator silently ignores those keywords when the `jsonschema` package is absent. A rule like "`sources` is required unless `deliveryMode` is `verification-only`" expressed in the schema would therefore validate as passing on any machine without that package installed — which describes most CI runners and every clean checkout. That is enforcement theater: the check appears to exist, reports success, and enforces nothing, precisely where it matters most.

Conditional and cross-field rules live in `bin/dossier-validate-config.sh` instead, which always runs and needs only `jq`. It performs two layers:

1. **Schema validation** against `schema.json` when a validator is available — reported honestly as `CONFIG_SCHEMA_VALIDATION=skipped (python3 jsonschema not installed)` when it is not, never as a pass.
2. **Semantic checks** that always run.

## What the semantic layer enforces

| Check | Why it is not in the schema | Consequence if violated |
|---|---|---|
| `project.outputRoot` is relative and does not traverse upward | A `pattern` catches absolute paths, but not `../` | An absolute or traversing root makes `allowedActions.writeOutsideOutputRoot` unenforceable — the containment check has nothing to contain |
| `project.sources` and `project.name` required unless `deliveryMode` is `verification-only` | Conditional on another field | A baseline with no sources can only produce unevidenced prose; an unresolved name propagates into every header and into public documents |
| `disclosure.policy: public` with `publicClaimApproval: not-required` | Cross-field | The run would approve its own external claims. It may apply a policy; it may never act as the business, legal, security, or communications approver |
| `ci.writeAllowlist` covers `project.outputRoot` | Cross-field | Every CI run's patch is rejected by the publish job's allowlist check — the automation silently never works |
| `ci.pathFilters.exclude` contains `<outputRoot>/**` | Cross-field | A merged documentation PR is itself a documentation-relevant change, and the refresh loops |
| `ci.rollingBranch` non-empty when CI is enabled | Cross-field | Its prefix is the head-ref loop guard rendered into the workflow's `if:` expression |
| `gate.minScore` ≤ 100 | Range is expressible, but the message matters | A gate that can never pass reads as a broken package rather than a broken config |
| `allowedActions.readSecrets` enabled | Not invalid, but worth surfacing | A secret's value is never required to document its type, location category, or rotation story. Flagged so it is a decision, not an accident |

Exit codes: `0` valid · `1` findings · `2` infrastructure error (missing `jq`, unreadable config).

## Recipes

```bash
# Validate what a run would actually see
bin/dossier-validate-config.sh

# Validate a candidate file before committing it
bin/dossier-validate-config.sh --config .claude/settings.dossier.json

# Reproduce a CI run's configuration locally
DOSSIER_ENGAGEMENT_DELIVERY_MODE=targeted \
DOSSIER_CI_AGENT_MAX_TURNS=60 \
  bin/dossier-validate-config.sh

# Find out which layer supplied a value: remove them from the top down
bin/dossier-resolve-config.sh dossier.project.outputRoot            # effective
CLAUDE_PLUGIN_ROOT=plugins/dossier \
  jq -r '.dossier.project.outputRoot' plugins/dossier/settings.json  # plugin default
```

## Adding a key

1. Add it to `settings.json` with a real default.
2. Add it to `schema.json` with `type`/`enum`, `default`, and a `description` that explains **why the default is what it is** — not what the key does, which the name already says.
3. If it has a conditional or cross-field rule, add the check to `bin/dossier-validate-config.sh`. Do not put it in the schema.
4. If a command or script reads it, resolve it through `bin/dossier-resolve-config.sh` — never by reading a settings file directly, which would skip four layers of the cascade.
5. If `/dossier:setup` should write it, add it to the setup merge and to `templates/config.example.json`.
