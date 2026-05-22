---
name: runtime-verification
description: "Verify code works at runtime through build verification (mandatory), LSP diagnostics, ad-hoc verification for projects without frameworks, E2E and smoke tests, and visual verification (screenshot-analyze-verify for UI changes). Skip whitelist strictly enforced (markdown-only, config-only, dependency-bump-only with evidence); all other skips require Proactive-Autonomy escalation. Use after quality checks pass to confirm the code actually runs. This skill MUST be consulted because no test framework is not an excuse to skip; build failure IS a finding and must be fixed."
allowed-tools: Bash, Read, Glob, Grep, LSP, TaskCreate, TaskList, TaskUpdate
agent: Explore
---

# Runtime Verification

Domain skill for verifying code works at runtime, beyond static analysis and unit tests.

## Iron Law

**NO COMPLETION UNTIL THE CODE BUILDS, RUNS, AND BEHAVES CORRECTLY. If you cannot verify it yourself, build the infrastructure to verify it.**

A green test suite is necessary but not sufficient. Runtime verification proves code actually works. "No test framework" is a problem to solve, not a reason to skip.

## Skip Whitelist (Enumerated — No Subjective Exemptions)

Runtime verification is **MANDATORY** for every change. The only permitted skips are the three categories below. Any skip outside this whitelist is forbidden and must be escalated via the Proactive-Autonomy protocol (see below).

| Skip Category | Definition | Required Evidence to Claim |
|---------------|------------|----------------------------|
| `markdown-only` | The diff touches **only** `.md`, `.markdown`, `.txt`, or `.rst` files. Zero code, config, or data files. | `git diff --name-only origin/$DEFAULT_BRANCH..HEAD` output showing only doc extensions. |
| `config-only` | The diff touches **only** configuration files (`.json`, `.yaml`, `.yml`, `.toml`, `.ini`, `.env.example`, dotfiles) with no executable code path changes. Config syntax must still be validated (lint/schema check, dry-run apply). | Full file list plus syntax validation output. |
| `dependency-bump-only` | The diff touches **only** lockfiles and manifest version strings (e.g., `package.json` version fields, `package-lock.json`, `poetry.lock`, `Gemfile.lock`, `go.sum`, `Cargo.lock`) with no source code, no config semantics, and no new dependencies. Build must still succeed. | Full file list plus successful build output. |

**If the diff mixes any whitelisted category with anything else (a single `.py` or `.ts` file, a new dependency, a config value change that alters behavior), the skip is disallowed. Run full runtime verification.**

### If In Doubt, Run It

**If you are uncertain whether the change qualifies for a whitelist skip — run runtime verification.** Uncertainty is never a reason to skip. The cost of an extra verification run is small; the cost of shipping unverified code is large.

Forbidden reasoning patterns include "small change", "CI-only edit", "tests already cover this", "I read the diff and it looks safe", "just a refactor", and similar. None of those are whitelist categories. If your reasoning does not map cleanly to `markdown-only`, `config-only`, or `dependency-bump-only` with the explicit evidence shown in the table above, you MUST run verification.

### Escalation Protocol for Out-of-Whitelist Skips

If you genuinely believe a skip outside the whitelist is warranted (e.g., infrastructure-only change, generated-code-only change, or something the whitelist does not yet cover), you MUST NOT proceed silently. Raise a Proactive-Autonomy escalation per [`references/escalation-format.md`](../../references/escalation-format.md) using `AskUserQuestion` and receive an explicit approval before proceeding. The Situation field MUST cite the specific change and why the whitelist does not cover it; the Tried field MUST list the standard paths attempted (fast-path verify script, build, smoke tests). Blanket "always skip for this repo" authorization is never valid — each out-of-whitelist skip requires its own escalation.

## Fast-Path Verification

Check for a project-level verify script first:

```bash
[ -x "verify.sh" ] && echo "FAST_PATH: verify.sh found"
[ -x "scripts/verify.sh" ] && echo "FAST_PATH: scripts/verify.sh found"
```

If found, run it and return results. Skip remaining steps.

## Build Verification

**Mandatory build step for all project types.** Build failure IS the finding — do NOT skip to runtime checks.

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

If build fails → iterate: read errors, fix, rebuild (up to `closedLoop.maxBuildIterations`, default 5). Do NOT proceed until the build passes.

## LSP Diagnostics Verification

**Pre-check**: Read `lsp.enabled` from settings (default `true`). If `false`, skip this section entirely.

When LSP is available and `lsp.diagnosticsAsQuality` is enabled in settings, collect language server diagnostics as an additional quality signal. This complements — never replaces — CLI-based quality commands.

### Process

1. Identify all files changed on the branch:
   ```bash
   git diff --name-only origin/$DEFAULT_BRANCH..HEAD
   ```

2. For each changed source file, use `LSP(documentSymbol)` to confirm the language server recognizes the file, then collect any diagnostics reported.

3. Map diagnostics to findings:

   | LSP Severity | Finding Priority | Action |
   |-------------|-----------------|--------|
   | Error | P1 | Must fix before proceeding |
   | Warning | P2 | Should fix |
   | Information/Hint | P3 | Consider |

4. Deduplicate against CLI tool output — if the same issue is reported by both LSP and a CLI tool (e.g., `tsc` and TypeScript LSP), keep only one entry.

### Timeout Handling

Each LSP operation must complete within `lsp.timeout` (default 5000ms from settings). If an operation times out:
- Mark that file's LSP check as "Timeout — skipped"
- Continue with remaining files
- Note timeout in output table
- Never block the workflow on a slow LSP server

### Graceful Fallback

If no LSP server is available, skip this section entirely with note: "LSP diagnostics: N/A — no language server configured." This is not an error and does not affect the verification outcome.

## Ad-Hoc Verification

For projects without formal test frameworks, verify by running the code:

| Project Type | Verification Approach |
|-------------|----------------------|
| Backend/API | Start server, curl endpoints, verify responses, check logs |
| CLI tools | Build, run with --help, run with sample input, check exit codes |
| Libraries | Write temporary test script, exercise public API, verify outputs, delete script |
| Static sites | Build, serve locally, verify pages load |
| Config-only | Validate config syntax, apply dry-run if supported |

"No test framework" is a problem to solve, not a reason to skip verification.

## Iterative Debug Loop

When any verification fails:
1. Read the FULL error message and stack trace — don't skim
2. Identify root cause (not just the symptom)
3. Fix the root cause
4. Re-verify

If the same error persists after a fix attempt: re-read code paths, try a different approach. Max `closedLoop.maxDebugIterations` (default 5) iterations, then escalate to user.

**The user should NEVER have to provide logs or tell you what went wrong.** You have access to the same errors — read them yourself.

## Discovery (dev server, port, E2E framework)

The `capability-discovery` skill (invoked at the start of every verify-relevant command) already detects tech stack, dev server scripts, and E2E frameworks. Re-running discovery here is redundant; consume the existing output.

When operating standalone (no prior `capability-discovery` invocation), use these probes:

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

## Smoke Tests

If a dev server is running, perform basic health checks:

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/health
curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/
```

A non-200 response is a P1 finding emitted via the canonical schema in [`references/finding-schema.md`](../../references/finding-schema.md) with `category=runtime`.

## Visual Verification (extracted to its own skill)

Visual verification has been extracted to [`skills/visual-verification/SKILL.md`](../visual-verification/SKILL.md). That skill owns the screenshot-analyze-verify loop, the browser-tool priority cascade (Playwright MCP → Chrome DevTools MCP → CLI → external skill fallback), the responsive viewport checks, and the result vocabulary (PASS / FAIL / SKIP / SKIP_WARN / SKIP_USER_APPROVED / MANUAL / BLOCKED).

When a diff is UI-relevant (UI file extensions OR acceptance criteria with UI keywords — see the visual-verification skill for the detection rules), the consumer (`commands/start.md` Phase 4, `commands/pr.md` Phase 4) invokes BOTH skills in parallel:

```
Skill(runtime-verification)  # build + server + smoke + E2E + LSP diagnostics
Skill(visual-verification)   # browser-rendered UI loop
```

The two skills coordinate via the dev server URL: if `runtime-verification` cannot start the dev server, `visual-verification` returns SKIP with reason "dev server unavailable" and the completion gate treats the dev-server failure as the primary finding rather than emitting a SKIP_WARN that obscures the root cause.

## Acceptance Criteria Verification

Map each acceptance criterion to a verification method:

| Criterion Type | Verification |
|---------------|-------------|
| API behavior | curl/fetch endpoint, check response |
| UI rendering | Screenshot-analyze-verify loop (see Visual Verification) |
| UI responsive | Multi-viewport screenshot verification |
| Data processing | Run with test data, check output |
| Configuration | Verify config loads without error |

## Completion Gate

Runtime verification is complete only when:

- Every testable acceptance criterion has a verification result (Pass/Fail/N/A with reason)
- "N/A" is justified (e.g., no dev server for a CLI tool), never used as a shortcut
- Failed checks are reported as P1 findings, not silently noted

If the dev server won't start, that IS the finding. Report it.

## Output Format

```markdown
### Runtime Verification Results

| Check | Status | Details |
|-------|--------|---------|
| Dev server | {Running/Not found} | Port {N} |
| Health check | {Pass/Fail/N/A} | HTTP {status} |
| E2E tests | {Pass/Fail/N/A} | {framework} |
| Smoke tests | {Pass/Fail/N/A} | {details} |
| LSP diagnostics | {Pass/Fail/Skip/N/A} | {errors: N, warnings: N, files checked: N} |

### Acceptance Criteria Verification
| # | Criterion | Verified | Method |
|---|-----------|----------|--------|
```

When the consumer also invokes `Skill(visual-verification)`, the visual rows (Visual check, Responsive, Console errors, Visual Evidence table) are produced by that skill — see its Output Format section. The consumer renders the runtime-verification table and the visual-verification table side by side rather than merging them, so each skill's output remains attributable.

## Timeout Configuration

From `settings.json`:
- `timeouts.devServerStartup`: Max seconds to wait for dev server (default: 30)
- `timeouts.e2eTest`: Max seconds for E2E suite (default: 120)

`visualVerification.*` settings (including `maxIterations`) are owned by `Skill(visual-verification)`; see that skill's documentation when both run together.

## Active Problem Solving

Do NOT silently skip verification. Actively solve problems:

| Problem | Action |
|---|---|
| No dev server | Attempt to start one. Report P1 if no start command exists and no alternative verification is possible. |
| No E2E framework | Run ad-hoc smoke tests (curl endpoints, run CLI, exercise API) |
| Server won't start | Read the error, fix the code, retry (up to `closedLoop.maxServerRetries`, default 3) |
| Port already in use | Try alternative ports |
| LSP server unavailable / times out | Skip LSP diagnostics; do NOT block on them. Note "LSP diagnostics: N/A — {reason}" in the output table. |

Browser-tool problems (no Playwright, no Chrome DevTools, no npx) are handled by the `visual-verification` skill — see its "Active Problem Solving" section.
