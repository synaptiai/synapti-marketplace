# Runtime Verification Probes

Supporting reference for `skills/runtime-verification/SKILL.md`. The skill states the rules (skip whitelist, sequence, ceilings, output format); this file holds the per-project-type commands and tables the skill points at. Loaded on demand — read the section you need.

## Fast path

```bash
[ -x "verify.sh" ] && echo "FAST_PATH: verify.sh found"
[ -x "scripts/verify.sh" ] && echo "FAST_PATH: scripts/verify.sh found"
```

If found, run it and return its results; the remaining steps are skipped.

## Build commands by stack

Build is mandatory for every project type. Build failure IS the finding — fix and rebuild (up to `closedLoop.maxBuildIterations`, default 5) before any runtime check.

```bash
# Node.js / TypeScript
[ -f "package.json" ] && npm run build 2>&1

# Python
[ -f "setup.py" ] || [ -f "pyproject.toml" ] && pip install -e . 2>&1

# Go
[ -f "go.mod" ] && go build ./... 2>&1

# Rust
[ -f "Cargo.toml" ] && cargo build 2>&1

# Ruby
[ -f "Gemfile" ] && bundle install 2>&1
```

## LSP diagnostics

Runs when `lsp.enabled` (default `true`) and `lsp.diagnosticsAsQuality` (default `true`) are set. Complements CLI quality commands; never replaces them.

1. Changed files: `git diff --name-only origin/$DEFAULT_BRANCH..HEAD`
2. For each changed source file: `LSP(documentSymbol)` to confirm the server recognizes the file, then collect diagnostics.
3. Map severity to finding priority:

   | LSP severity | Priority | Action |
   |-------------|----------|--------|
   | Error | P1 | Must fix before proceeding |
   | Warning | P2 | Should fix |
   | Information / Hint | P3 | Consider |

4. Deduplicate against CLI output (e.g. the same issue from `tsc` and the TypeScript LSP counts once).

Timeouts: each operation is bounded by `lsp.timeout` (default 5000 ms). On timeout mark the file "Timeout — skipped", continue with the rest, and note it in the output table. No language server at all → "LSP diagnostics: N/A — no language server configured"; this is not an error and does not affect the verification outcome.

## Standalone discovery probes

`capability-discovery` already detects the tech stack, dev-server scripts, and E2E frameworks at the start of every verify-relevant command — consume its output instead of re-running discovery. Use these probes only when running standalone:

```bash
# Dev server: CLAUDE.md hints, package.json scripts, framework config files
[ -f ".claude/CLAUDE.md" ] && grep -iE "(dev|server|start|serve):" .claude/CLAUDE.md
[ -f "package.json" ] && python3 -c "import json; d=json.load(open('package.json')); [print(f'{k}: {v}') for k,v in d.get('scripts',{}).items() if k in ('dev','start','serve')]"

# Port: running listeners on common ports
lsof -i -P -n 2>/dev/null | grep LISTEN | grep -E ':(3000|4000|5000|8000|8080)' | head -5

# E2E framework: config files
[ -f "playwright.config.ts" ] || [ -f "playwright.config.js" ] && echo "Playwright"
[ -f "cypress.config.ts" ] || [ -f "cypress.config.js" ] && echo "Cypress"
```

## Smoke tests

With a dev server running:

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/health
curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/
```

A non-200 response is a P1 finding in the canonical schema (`references/finding-schema.md`, `category=runtime`).

## Ad-hoc verification by project type

For projects without a formal test framework, verify by running the code:

| Project type | Verification approach |
|-------------|----------------------|
| Backend/API | Start server, curl endpoints, verify responses, check logs |
| CLI tools | Build, run with `--help`, run with sample input, check exit codes |
| Libraries | Write a temporary script that exercises the public API, verify outputs, delete the script |
| Static sites | Build, serve locally, verify pages load |
| Config-only | Validate config syntax, apply dry-run if supported |

## Acceptance criterion → verification method

| Criterion type | Verification |
|---------------|-------------|
| API behavior | curl/fetch the endpoint, check the response |
| UI rendering | Screenshot-analyze-verify loop (`skills/visual-verification/SKILL.md`) |
| UI responsive | Multi-viewport screenshot verification (same skill) |
| Data processing | Run with test data, check output |
| Configuration | Verify config loads without error |

## Active problem solving

| Problem | Action |
|---|---|
| No dev server | Attempt to start one. P1 if no start command exists and no alternative verification is possible. |
| No E2E framework | Ad-hoc smoke tests (curl endpoints, run the CLI, exercise the API) |
| Server won't start | Read the error, fix the code, retry (up to `closedLoop.maxServerRetries`, default 3) |
| Port already in use | Try alternative ports |
| LSP unavailable or slow | Skip LSP diagnostics; note "LSP diagnostics: N/A — {reason}" in the output table. Never block on it. |

Browser-tool problems (no Playwright, no Chrome DevTools, no npx) belong to `skills/visual-verification/SKILL.md`.
