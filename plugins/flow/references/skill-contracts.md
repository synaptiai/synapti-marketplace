# Skill Contracts (machine-checkable input schemas)

Reference document. The canonical source of truth for what JSON shape each skill expects on its inputs, and how the validator (`plugins/flow/bin/validate-skill-input.sh`) and per-skill test fixtures (`tests/skills/<name>/`) enforce those shapes.

This document exists because pre-Landing-3 the skills documented their inputs in prose ("the skill receives self-review findings, evidence bundle, and file list") with no machine-checkable shape. Producers and consumers had to agree by convention; silent format mismatches produced silent skill failures. With JSON Schemas + a validator + test fixtures, drift becomes detectable at PR-review time rather than at runtime in someone's workflow.

## Scope

Not every skill has an input contract — many skills (`brainstorming`, `architecture-patterns`, `tdd-patterns`, `debugging-patterns`, etc.) operate on conversational context rather than structured payloads. The skills with contracts are the ones whose inputs come from another part of the workflow as a structured payload, where the producer/consumer split benefits from machine-checked agreement:

| Skill | Why a contract matters |
|---|---|
| `holdout-validation` | Receives self-review findings + evidence bundle + file list from the orchestrator. Three different upstream surfaces; each has its own format risk. |
| `criterion-verification-map` | Receives parsed acceptance criteria from `commands/start.md` Phase 1. The criterion structure flows through PLAN, CODE, and VERIFY phases; a malformed input here corrupts the entire downstream chain. |
| `specification-capture` | Receives issue context, journal path, and invocation reason from start/design/brainstorm. The invocation reason controls per-invoker scope (start needs all three elements; design needs two; brainstorm needs one) — a wrong reason produces wrong-scope captures. |

Other skills may add contracts in future landings as integration points solidify.

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

## Compatibility with the canonical references

The skill input schemas reference the row shape from `references/finding-schema.md` (e.g., `selfReviewFindings` items are findings with the canonical 6-field structure). When `finding-schema.md` evolves, the JSON Schemas here MUST be updated to match. The `tests/finding-schema/validate.sh` test exercises the row shape independently as a sanity check.

Similarly, `evidence-bundle-format.md` defines the `evidenceBundle` shape; `escalation-format.md` defines the format `bin/flow-escalate.sh` outputs. The contracts here are downstream consumers of those reference docs.
