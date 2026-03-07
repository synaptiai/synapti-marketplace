---
name: runtime-verification
description: "[flow] Verifies implementation works at runtime by discovering and executing dev server startup, API smoke tests, E2E tests, and browser checks. Use after quality checks pass to confirm the code actually runs."
allowed-tools: Bash, Read, Glob
context: fork
agent: Explore
---

# Runtime Verification

Domain skill for verifying code works at runtime, beyond static analysis and unit tests.

## Fast-Path Verification

Check for a project-level verify script first:

```bash
[ -x "verify.sh" ] && echo "FAST_PATH: verify.sh found"
[ -x "scripts/verify.sh" ] && echo "FAST_PATH: scripts/verify.sh found"
```

If found, run it and return results. Skip remaining steps.

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

## Acceptance Criteria Verification

Map each acceptance criterion to a verification method:

| Criterion Type | Verification |
|---------------|-------------|
| API behavior | curl/fetch endpoint, check response |
| UI rendering | Dev server + browser check |
| Data processing | Run with test data, check output |
| Configuration | Verify config loads without error |

## Output Format

```markdown
### Runtime Verification Results

| Check | Status | Details |
|-------|--------|---------|
| Dev server | {Running/Not found} | Port {N} |
| Health check | {Pass/Fail/N/A} | HTTP {status} |
| E2E tests | {Pass/Fail/N/A} | {framework} |
| Smoke tests | {Pass/Fail/N/A} | {details} |

### Acceptance Criteria Verification
| # | Criterion | Verified | Method |
|---|-----------|----------|--------|
```

## Timeout Configuration

From `settings.json`:
- `timeouts.devServerStartup`: Max seconds to wait for dev server (default: 30)
- `timeouts.e2eTest`: Max seconds for E2E suite (default: 120)

## Graceful Degradation

| Missing | Fallback |
|---------|----------|
| No dev server | Skip runtime checks, note in output |
| No E2E framework | Skip E2E, rely on unit tests |
| Server won't start | Report error, don't block workflow |
| Port already in use | Try alternative ports |
