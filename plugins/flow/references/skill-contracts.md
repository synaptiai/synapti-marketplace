# Skill Contracts (machine-checkable input schemas)

Reference document. The canonical source of truth for what JSON shape each skill expects on its inputs, and how the validator (`plugins/flow/bin/validate-skill-input.sh`) and per-skill test fixtures (`tests/skills/<name>/`) enforce those shapes. JSON Schemas + the validator + the test fixtures make producer/consumer drift detectable at PR-review time rather than at runtime in someone's workflow.

## Scope

Not every skill has an input contract — many skills (`brainstorming`, `architecture-patterns`, `tdd-patterns`, `debugging-patterns`, etc.) operate on conversational context rather than structured payloads. The skills with contracts are the ones whose inputs come from another part of the workflow as a structured payload, where the producer/consumer split benefits from machine-checked agreement:

| Skill | Why a contract matters |
|---|---|
| `holdout-validation` | Receives self-review findings + evidence bundle + file list from the orchestrator. Three different upstream surfaces; each has its own format risk. |
| `criterion-verification-map` | Receives parsed acceptance criteria from `commands/start.md` Phase 1. The criterion structure flows through PLAN, CODE, and VERIFY phases; a malformed input here corrupts the entire downstream chain. |
| `specification-capture` | Receives issue context, journal path, and invocation reason from start/design/brainstorm. The invocation reason controls per-invoker scope (start needs all three elements; design needs two; brainstorm needs one) — a wrong reason produces wrong-scope captures. |

Other skills may add contracts as integration points solidify.

## Schema location

Each contract lives at `tests/skills/<skill-name>/input-schema.json`. Schemas use JSON Schema Draft-07. The relevant subset of the spec the validator enforces:

- `type` (object, array, string, integer, boolean) — required at every level
- `required` (object) — list of required field names
- `properties` (object) — sub-schemas for each property
- `items` (array) — sub-schema for array elements
- `minItems` (array)
- `minLength` (string)
- `enum` (any) — closed value list
- `pattern` (string) — regex applied via `re.search` (anchor with `^`/`$` for full-match)

Schemas may declare other Draft-07 keywords (`oneOf`, `allOf`, `format`, `additionalProperties`, etc.); those are honored when `jsonschema` is installed but ignored by the fallback validator. Use them only when full validation in CI is set up.

### Fallback caveat: `type` declared as a list

When a schema declares `type` as an array of allowed types (e.g. `"type": ["string", "null"]`), the fallback validator currently checks only that the data matches *one* of the allowed types — it does NOT then re-enter constraint validation for the matched subtype. Concretely, this schema:

```json
{ "type": ["string", "null"], "minLength": 5, "enum": ["alpha", "beta"] }
```

Fallback accepts `"X"` (matches `string`, but `minLength` and `enum` skipped). Full `jsonschema` correctly rejects it.

None of the current contracts use `type: [...]`, so the gap is latent today. If you author a contract that needs nullable-with-constraints, install `jsonschema` in CI and document the dependency in the test, OR refactor the schema to use single-type sub-schemas wrapped in `oneOf` (also requires full `jsonschema`). Avoid `type: [...]` in fallback-only deployments.

## The validator

`plugins/flow/bin/validate-skill-input.sh <skill-name> '<json-input>'` validates the input against the skill's schema. Exit codes:

| Exit | Meaning |
|---|---|
| 0 | Input validates against the schema |
| 1 | Input fails validation; rationale on stderr (path + reason) |
| 2 | Schema not found, input is not valid JSON, or other infrastructure error |

The script tries `import jsonschema` first for full Draft-07 validation. If the package is not installed, it falls back to a shape-check implemented with the standard `json` and `re` modules — covers the keywords listed above. The fallback prints a stderr NOTE so callers (and CI) can see when stricter validation was skipped.

Producers MUST validate inputs **before** invoking a skill. The pattern:

```bash
PAYLOAD='{"selfReviewFindings": [...], "evidenceBundle": [...], "fileList": [...]}'
if ! "${CLAUDE_PLUGIN_ROOT:-plugins/flow}/bin/validate-skill-input.sh" holdout-validation "$PAYLOAD" >&2; then
  echo "ERROR: holdout-validation input failed validation; refusing to invoke skill" >&2
  exit 1
fi
# Now safe to invoke Skill(holdout-validation) with $PAYLOAD
```

Skills that read their input via the prompt (LLM-side) cannot run the validator at the bash layer — the producer is responsible. The validator is a contract for orchestration code that builds payloads, not for the skill's own runtime.

## Test fixtures

Each skill's test directory contains:

```
tests/skills/<name>/
├── input-schema.json   # the contract (Draft-07 JSON Schema)
├── valid-input.json    # canonical example that MUST validate
├── invalid-input.json  # canonical counter-example that MUST fail
└── test.sh             # asserts {valid → exit 0, invalid → exit 1, edge cases}
```

`test.sh` is the regression tape for the contract. When a schema changes, update both fixtures; when a new edge case is discovered, add an `assert_exit` line. The test is the contract; the schema is the format; the doc (this file + the skill's SKILL.md) is the prose.

Run all skill IO tests:

```bash
for t in tests/skills/*/test.sh; do
  echo "=== $t ==="
  bash "$t" || exit 1
done
```

A regression in any contract fails the loop with the offending test's name in the output.

## Adding a contract for a new skill

1. Create `tests/skills/<name>/input-schema.json` with the Draft-07 schema. Document every property (`description` field). Mark required fields explicitly. Use enums for closed value lists (do NOT use free-form strings where the skill only accepts a fixed set).
2. Create `valid-input.json` with a canonical example. This doubles as documentation — the example shows the shape the skill expects.
3. Create `invalid-input.json` that violates at least three different rules (missing required field, type mismatch, out-of-enum value). The validator should reject it with one of the three errors; which one doesn't matter as long as it rejects.
4. Create `test.sh` that asserts: valid → exit 0, invalid → exit 1, missing required → exit 1, non-JSON → exit 2, plus any skill-specific edge cases.
5. Add the skill to the table in this document.
6. Update the consuming command(s) to call `bin/validate-skill-input.sh` before invoking the skill.

## Why fallback validation, not vendored jsonschema?

The plugin runs in environments where `pip install jsonschema` is not always practical (corporate Python sandboxes, slim CI images, untrusted-network installs). The fallback validator uses only the standard library — guaranteed to work on any Python 3.x install. The trade-off is that it covers only the Draft-07 subset listed above, not the full spec.

Schema authors should write contracts that the fallback can enforce. If a contract requires `oneOf` or `format: email` validation, document that fallback validation will skip those checks and recommend installing `jsonschema` in CI.

## SKILL.md frontmatter schema

The contracts above govern *runtime payloads* a skill receives. The skill itself is a markdown file with YAML frontmatter, and that frontmatter has its own (Claude-Code-native) schema. Documenting it here so contributors editing skills know which keys are recognized and which are accidental drift.

| Key | Type | Required | Purpose |
|---|---|---|---|
| `name` | string | yes | Stable skill identifier. Kebab-case by convention. Used by orchestration code (`Skill(<name>)`) and by `tests/skills/<name>/`. |
| `description` | string | yes | One-line trigger description. The string Claude sees when deciding whether to invoke. Lead with the artifact and include either a "MUST be consulted" or "Use when…" clause (per the description-trigger memory at `feedback_skill_descriptions`). |
| `allowed-tools` | string list | no | Tool whitelist. When present, restricts the skill to a specific tool set (e.g. `[Read, Grep, Bash(grep:*), Bash(rg:*)]`). Omit to inherit the parent's tool budget. Narrowing is preferred over expanding. |
| `disable-model-invocation` | boolean | no | When `true`, Claude Code will NOT autonomously invoke this skill — only an orchestrator (a command's prompt) can call it via `Skill(<name>)`. Use for reference docs that are not standalone entry points (e.g. `pr-lifecycle`, `preflight-checks`). |
| `paths` | string list | no | Restricts the skill's *automatic* invocation to files matching one or more glob patterns. Skills with `paths:` only fire when the conversation context references a matching file. Use when a skill applies only to a specific subsystem (e.g. `tdd-patterns: paths: ["**/*test*", "**/spec/**"]`). |

### Schema rules

- `name` and `description` are required. A SKILL.md without both will not register.
- `disable-model-invocation: true` and `paths: [...]` are mutually compatible: `disable-model-invocation` blocks model-side invocation entirely, `paths` narrows the *file context* under which it would otherwise fire.
- Unknown frontmatter keys are silently ignored by Claude Code. They do not error — but they also have no effect. Contributors adding fields should either document them here or remove them.
- The `description` field is matched by the trigger model character-for-character; cosmetic edits (rewording, capitalization) materially change invocation rate. The `feedback_skill_descriptions` memory entry captures the empirical impact.

### Conventional fields not in this schema

These appear in some plugins but are NOT recognized by Claude Code itself — they are documentation-only for human contributors:

- `version`, `last-updated`, `author`, `tags` — all unrecognized; either inline them in the body or delete.
- `agent: <name>` — used by some compound-engineering skills to declare a preferred sub-agent. Honored by orchestration code that reads it; not by Claude Code's native skill resolver.

When in doubt: if the key isn't in the table above, it's probably unrecognized. Document it inline if it carries meaning to the orchestrator that uses the skill.

## Compatibility with the canonical references

The skill input schemas reference the row shape from `references/finding-schema.md` (e.g., `selfReviewFindings` items are findings with the canonical 6-field structure). When `finding-schema.md` evolves, the JSON Schemas here MUST be updated to match. The `tests/finding-schema/validate.sh` test exercises the row shape independently as a sanity check.

Similarly, `evidence-bundle-format.md` defines the `evidenceBundle` shape; `escalation-format.md` defines the format `bin/flow-escalate.sh` outputs. The contracts here are downstream consumers of those reference docs.

`bin/flow-escalate.sh` itself is a CLI utility for ad-hoc human use — it lets a reviewer or maintainer render the canonical escalation shape from the terminal. Commands continue to inline the escalation prose so each command's escalation paths stay inspectable in the command body rather than hidden behind a helper invocation.
