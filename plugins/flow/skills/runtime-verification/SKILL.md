---
name: runtime-verification
description: "Verify code works at runtime through build verification (mandatory), LSP diagnostics, ad-hoc verification for projects without frameworks, E2E and smoke tests, and visual verification (screenshot-analyze-verify for UI changes). Skip whitelist strictly enforced (markdown-only, config-only, dependency-bump-only with evidence); all other skips require Proactive-Autonomy escalation. Use after quality checks pass to confirm the code actually runs. This skill MUST be consulted because no test framework is not an excuse to skip; build failure IS a finding and must be fixed."
allowed-tools: Bash, Read, Glob, Grep, LSP, TaskCreate, TaskList, TaskUpdate
context: fork
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

**If you are uncertain whether the change qualifies for a whitelist skip — run runtime verification.** Uncertainty is never a reason to skip. The cost of an extra verification run is small; the cost of shipping unverified code is large. When the category is unclear, default to running.

Explicitly forbidden reasoning patterns (do NOT use these to justify skipping):
- "This is a small change."
- "This only touches the CI workflow, it won't affect runtime."
- "The tests already cover this."
- "I read the diff and it looks safe."
- "This is just a refactor."
- "The markdown includes a code snippet but the snippet isn't executed."
- "The config change is obvious."

None of those are whitelist categories. If your reasoning for skipping does not map cleanly to `markdown-only`, `config-only`, or `dependency-bump-only` with the evidence shown above, you MUST run verification.

### Escalation Protocol for Out-of-Whitelist Skips

If you genuinely believe a skip outside the whitelist is warranted (e.g., infrastructure-only change, generated-code-only change, or something the whitelist does not yet cover), you MUST NOT proceed silently. Raise a Proactive-Autonomy escalation to the user using this six-field structure:

```markdown
### Proactive-Autonomy Escalation: Runtime Verification Skip Request

**Situation**
{What the change is, which files changed, why the standard whitelist does not cover it.}

**Tried**
{What you already attempted to verify the change through the standard paths — fast-path verify script, build, smoke tests — and why each was insufficient or inapplicable.}

**Options**
1. {Option A — e.g., run a custom ad-hoc verification despite no framework. Reasoning.}
2. {Option B — e.g., skip with explicit user approval. Reasoning.}
3. {Option C — e.g., block and ask for a new whitelist category. Reasoning.}

**Recommendation**
{Your preferred option and why. Be specific.}

**Time sensitivity**
{Is this blocking a release? How long will verification take? How long will a skip review take?}

**Risk**
{What breaks if the skip is wrong? What is the blast radius of shipping unverified?}
```

The escalation MUST be presented via `AskUserQuestion` and MUST receive an explicit approval before proceeding. Blanket "always skip for this repo" authorization is never valid — each out-of-whitelist skip requires its own escalation.

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

## Dev Server Discovery

```bash
# Check CLAUDE.md for dev server command
CLAUDE_MD=""
[ -f ".claude/CLAUDE.md" ] && CLAUDE_MD=".claude/CLAUDE.md"
[ -z "$CLAUDE_MD" ] && [ -f "CLAUDE.md" ] && CLAUDE_MD="CLAUDE.md"
[ -n "$CLAUDE_MD" ] && grep -iE "(dev|server|start|serve):" "$CLAUDE_MD" 2>/dev/null

# Check package.json scripts
[ -f "package.json" ] && python3 -c "import json; d=json.load(open('package.json')); [print(f'{k}: {v}') for k,v in d.get('scripts',{}).items() if k in ('dev','start','serve')]" 2>/dev/null

# Check for common framework files
[ -f "next.config.js" ] || [ -f "next.config.ts" ] && echo "Next.js detected"
[ -f "vite.config.ts" ] || [ -f "vite.config.js" ] && echo "Vite detected"
[ -f "config/routes.rb" ] && echo "Rails detected"
```

## Port Detection

```bash
# Check for running servers
lsof -i -P -n 2>/dev/null | grep LISTEN | grep -E ':(3000|4000|5000|8000|8080)' | head -5

# Check for port configuration
grep -rE 'port.*[0-9]{4}' .env* package.json 2>/dev/null | head -5
```

## E2E Framework Detection

```bash
# Playwright
[ -f "playwright.config.ts" ] || [ -f "playwright.config.js" ] && echo "Playwright detected"

# Cypress
[ -f "cypress.config.ts" ] || [ -f "cypress.config.js" ] && echo "Cypress detected"

# Check for E2E scripts
[ -f "package.json" ] && python3 -c "import json; d=json.load(open('package.json')); [print(f'{k}: {v}') for k,v in d.get('scripts',{}).items() if 'e2e' in k.lower() or 'playwright' in k.lower() or 'cypress' in k.lower()]" 2>/dev/null
```

## Smoke Tests

If dev server is running, perform basic health checks:

```bash
# Health endpoint check
curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/health 2>/dev/null
curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/ 2>/dev/null
```

## Visual Verification

Screenshot-analyze-verify workflow for UI-facing changes. Conditional — only activates when relevant.

### UI Relevance Detection

Check whether visual verification applies:

```bash
# Check diff for UI file extensions
git diff --name-only HEAD~1..HEAD | grep -iE '\.(tsx|jsx|vue|html|css|scss|svelte)$'
```

Also check acceptance criteria text for UI keywords: `UI`, `page`, `display`, `render`, `visual`, `layout`, `responsive`, `component`, `style`.

If neither signal fires → skip visual verification with note: "No UI-relevant changes detected."

### Browser Tool Discovery

Priority cascade — use the first available:

1. **Playwright MCP** (`browser_navigate`, `browser_take_screenshot`) — full capability: navigation, screenshots, console logs, DOM inspection
2. **Chrome DevTools MCP** — screenshot + console + DOM inspection
3. **CLI fallback**: `npx playwright screenshot http://localhost:$PORT/ $SCREENSHOT_DIR/page.png`
4. **Skill fallback**: `Skill(compound-engineering:test-browser)` — if available in environment
5. **Skill fallback**: `Skill(compound-engineering:agent-browser)` — if available in environment
6. **No tools available** → SKIP_WARN or BLOCKED based on `visualVerification.requireVisualVerification` setting (see below)

### Screenshot-Analyze-Verify Loop

Bounded by `settings.json` → `visualVerification.maxIterations` (default: 3).

```
For each page URL (dev server root + key pages from routes):
  1. Navigate to page URL
  2. Take screenshot → save to $SCREENSHOT_DIR/{page}-{viewport}-{timestamp}.png
  3. Read screenshot with Read tool (Claude analyzes visually)
  4. Check for:
     - Blank page (P1 — blocks completion)
     - Layout breaks / broken grid (P2)
     - Missing content that should be visible (P2)
     - Console errors blocking render (P1)
     - Minor styling issues (P3)
  5. If MCP available: also check browser_console_logs for JS errors
  6. Record screenshot path as evidence
```

### Responsive Verification

For each viewport in `settings.json` → `visualVerification.viewports`, resize browser and repeat screenshot analysis:

- Desktop (1280×720), Tablet (768×1024), Mobile (375×812) by default
- Check for: content cut off, nav broken at breakpoint, horizontal scroll on mobile

### Task Tracking

Create tasks before starting, update status throughout:

```
# Setup — create all visual verification tasks upfront
TaskCreate("Visual verification", "Screenshot-analyze-verify for UI-facing changes")
TaskCreate("Browser tool discovery", "Detect available browser automation (Playwright MCP, Chrome DevTools, CLI)")
TaskCreate("Responsive check", "Verify UI across configured viewports (desktop, tablet, mobile)")

# Browser tool discovery
TaskUpdate(browserToolTaskId, status: "in_progress")
# ... detect tools ...
TaskUpdate(browserToolTaskId, status: "completed", result: "{tool} detected")

# If not applicable (no UI files, no UI criteria) — legitimate skip:
TaskUpdate(visualVerificationTaskId, status: "completed", result: "SKIP — no UI-relevant changes")
TaskUpdate(responsiveTaskId, status: "completed", result: "SKIP")

# If no browser tools found — check requireVisualVerification setting:
#   requireVisualVerification: false (default) → SKIP_WARN
TaskUpdate(visualVerificationTaskId, status: "completed", result: "SKIP_WARN — no browser tools. Install Playwright MCP or use /flow:setup.")
TaskUpdate(responsiveTaskId, status: "completed", result: "SKIP_WARN — no browser tools")

#   requireVisualVerification: true → BLOCKED (command-level escalation)
TaskUpdate(visualVerificationTaskId, status: "completed", result: "BLOCKED — requireVisualVerification is true but no browser tools available")
TaskUpdate(responsiveTaskId, status: "completed", result: "BLOCKED")

# Screenshot-analyze-verify loop (when tools ARE available)
TaskUpdate(visualVerificationTaskId, status: "in_progress")
# ... for each page: screenshot → analyze → record findings ...
TaskUpdate(visualVerificationTaskId, status: "completed", result: "PASS/FAIL — {pages} checked, P1:{n} P2:{n} P3:{n}")

# Responsive verification
TaskUpdate(responsiveTaskId, status: "in_progress")
# ... for each viewport: resize → screenshot → analyze ...
TaskUpdate(responsiveTaskId, status: "completed", result: "PASS/FAIL — {viewports} tested, findings: {summary}")
```

### Result Vocabulary

| Result | Meaning | Passes Completion Gate? |
|--------|---------|------------------------|
| `PASS` | Ran and passed | Yes |
| `FAIL` | Ran and found P1 issues | No |
| `SKIP` | No UI files changed (legitimate) | Yes |
| `SKIP_WARN` | UI files changed, no tools, `requireVisualVerification` is false | Yes (with warning) |
| `SKIP_USER_APPROVED` | User explicitly chose to skip | Yes |
| `MANUAL` | User committed to manual verification | Yes |
| `BLOCKED` | Awaiting user decision (`requireVisualVerification` is true) | No — requires command-level escalation |

Use `TaskList` after all visual verification completes to confirm all sub-tasks resolved.

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
| Visual check | {Pass/Fail/Skip/N/A} | {pages checked, findings} |
| Responsive | {Pass/Fail/Skip/N/A} | {viewports tested} |
| Console errors | {Pass/Fail/Skip/N/A} | {error count} |

### Visual Evidence
| Page | Viewport | Screenshot | Status | Findings |
|------|----------|------------|--------|----------|

### Acceptance Criteria Verification
| # | Criterion | Verified | Method |
|---|-----------|----------|--------|
```

## Timeout Configuration

From `settings.json`:
- `timeouts.devServerStartup`: Max seconds to wait for dev server (default: 30)
- `timeouts.e2eTest`: Max seconds for E2E suite (default: 120)
- `visualVerification.maxIterations`: Max screenshot-analyze-fix cycles (default: 3)

## Active Problem Solving

Do NOT silently skip verification. Actively solve problems:

| Problem | Action |
|---------|--------|
| No dev server | Attempt to start one. Report P1 if no start command exists and no alternative verification is possible. |
| No E2E framework | Run ad-hoc smoke tests (curl endpoints, run CLI, exercise API) |
| Server won't start | Read the error, fix the code, retry (up to `closedLoop.maxServerRetries`, default 3) |
| Port already in use | Try alternative ports |
| No Playwright MCP | Try Chrome DevTools MCP |
| No Chrome DevTools MCP | Try `npx playwright install chromium && npx playwright screenshot` |
| No npx playwright | Try `Skill(compound-engineering:test-browser)` or `Skill(compound-engineering:agent-browser)` |
| No browser tools at all | If `requireVisualVerification` is true, return BLOCKED for command-level escalation. Otherwise, SKIP_WARN with tool installation guidance. |
| Non-UI project | Skip visual verification (no UI files or criteria detected) |
