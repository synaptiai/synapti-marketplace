# LSP Capability Probes

Reference for Step 7 of the `capability-discovery` skill: how to probe which LSP code-intelligence features are available in the current project, and how each result feeds later phases.

## Pre-check

Read `lsp.enabled` from settings (cascade-resolved; default `true`). If `false`, skip probing and report every LSP feature as `Disabled` in the output table.

## Probe target

Find one representative source file with Glob, matching the detected tech stack: `**/*.ts`, `**/*.py`, `**/*.go`, `**/*.rs`, or `**/*.rb`. Use the first result. If no source file exists (markdown-only project) or no LSP server is configured, report "No LSP server available — using CLI-only analysis" and skip. This is not an error.

## Feature probes

Run each probe against the target file and catch failures individually:

| Operation | Test | Capability | Consumed by |
|-----------|------|------------|-------------|
| `documentSymbol` | List symbols in the file | Symbol navigation | All phases |
| `hover` | Hover on first symbol (line 1, char 1) | Type info / docs | CODE |
| `goToDefinition` | Definition lookup on an import or reference | Definition tracing | EXPLORE |
| `findReferences` | Find references to a symbol | Impact analysis | EXPLORE, REVIEW (caller verification) |
| `goToImplementation` | Find implementations | Interface resolution | EXPLORE |

Result recording:

- Success → `Available`
- Error "no LSP server" → LSP not configured for this file type → `Unavailable`
- Any other error, or no response within `lsp.timeout` (settings; default 5000 ms) → `Unavailable`

## Diagnostics inference

LSP diagnostics are not a discrete operation to probe — the language server reports them when it processes a file. Record `diagnostics` as `Available` when `documentSymbol` succeeds and `Unavailable` otherwise. When available and `lsp.diagnosticsAsQuality` is `true`, VERIFY treats diagnostics as a quality signal: errors → P1, warnings → P2. They complement, never replace, CLI-based quality commands.
