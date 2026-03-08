---
name: runtime-verification
description: "[flow] Verifies implementation works at runtime by discovering and executing dev server startup, API smoke tests, E2E tests, and browser checks. Use after quality checks pass to confirm the code actually runs."
allowed-tools: Bash, Read, Glob, Grep, TaskCreate, TaskList, TaskUpdate
context: fork
agent: Explore
---

# Runtime Verification

Domain skill for verifying code works at runtime, beyond static analysis and unit tests.

## Iron Law

**NO COMPLETION UNTIL THE CODE BUILDS, RUNS, AND BEHAVES CORRECTLY. If you cannot verify it yourself, build the infrastructure to verify it.**

A green test suite is necessary but not sufficient. Runtime verification proves code actually works. "No test framework" is a problem to solve, not a reason to skip.

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
4. **No tools available** → skip visual verification, note limitation in output

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

# If not applicable (no UI files, no UI criteria):
TaskUpdate(visualVerificationTaskId, status: "completed", result: "SKIP — no UI-relevant changes")
TaskUpdate(responsiveTaskId, status: "completed", result: "SKIP")

# Screenshot-analyze-verify loop
TaskUpdate(visualVerificationTaskId, status: "in_progress")
# ... for each page: screenshot → analyze → record findings ...
TaskUpdate(visualVerificationTaskId, status: "completed", result: "PASS/FAIL — {pages} checked, P1:{n} P2:{n} P3:{n}")

# Responsive verification
TaskUpdate(responsiveTaskId, status: "in_progress")
# ... for each viewport: resize → screenshot → analyze ...
TaskUpdate(responsiveTaskId, status: "completed", result: "PASS/FAIL — {viewports} tested, findings: {summary}")
```

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
| No browser tools at all | Skip visual verification, note in output |
| Non-UI project | Skip visual verification (no UI files or criteria detected) |
