---
name: runtime-verification
description: >-
  WHEN: After quality checks pass (lint/test/typecheck) in gh-start Phase 7 or gh-pr Phase 3 Step 3.5,
  to verify the implementation actually works at runtime. Discovers and executes dev server startup,
  API smoke tests, E2E tests, and browser checks.
  WHEN NOT: Do not use for static analysis (lint/test/typecheck) -- those are handled by test-runner agent
  or inline quality commands. Do not use if no dev server or E2E framework exists (skill handles this gracefully).
allowed-tools: Bash, Read, Glob, Grep
context: fork
agent: Explore
---

# Runtime Verification

This skill verifies that an implementation actually works at runtime, not just that it compiles and passes lint/tests.

## Purpose

Quality checks (lint, test, typecheck) answer "does it compile?" This skill answers "does it work?" by:
- Starting dev servers and verifying they respond
- Running smoke tests against new/modified endpoints
- Executing E2E test suites if available
- Verifying acceptance criteria programmatically

## Discovery Process

### Step 1: Check CLAUDE.md for Verification Commands

```bash
grep -E "^(dev-server|verify|e2e|smoke|acceptance|integration):" .claude/CLAUDE.md 2>/dev/null
grep -E "(npm run (dev|start|e2e|verify)|python.*manage\.py.*runserver|go run|cargo run)" .claude/CLAUDE.md 2>/dev/null
```

### Step 2: Check for Verification Scripts

```bash
ls verify.sh test-e2e.sh smoke-test.sh scripts/verify* 2>/dev/null
```

### Step 3: Check for E2E Test Frameworks

```bash
# Playwright
ls playwright.config.* 2>/dev/null
grep -l "playwright" package.json 2>/dev/null

# Cypress
ls cypress.config.* cypress/ 2>/dev/null

# Selenium
grep -l "selenium" requirements.txt pyproject.toml 2>/dev/null
```

### Step 4: Check for Dev Server Commands

```bash
cat package.json 2>/dev/null | grep -E '"(dev|start|serve)"'
grep -E "^(dev|serve|run|start):" Makefile 2>/dev/null
ls manage.py 2>/dev/null && echo "django: python manage.py runserver"
```

### Step 5: Check for Health/Readiness Endpoints

```bash
grep -rn "health\|ready\|alive\|ping" --include="*.ts" --include="*.py" --include="*.go" . 2>/dev/null | head -10
```

## Runtime Verification Protocol

### Step 1: Service Startup (if applicable)

If a dev server command is discovered:
1. Start server in background: `{dev_cmd} &`
2. Wait for ready signal (poll health endpoint or port availability):
   ```bash
   for i in {1..30}; do
     curl -s http://localhost:{port}/health > /dev/null 2>&1 && break
     sleep 1
   done
   ```
3. If server doesn't start within 30s → report as verification failure

### Step 2: Smoke Tests

For each new/modified API endpoint in the diff:
1. Send a basic request and verify non-error response
2. Verify response structure matches expected schema
3. Test with invalid input and verify error handling

### Step 3: E2E Tests (if framework detected)

Run discovered E2E test command:
```bash
npx playwright test 2>&1  # or
npx cypress run 2>&1       # or
pytest tests/e2e/ 2>&1     # etc.
```

### Step 4: Acceptance Criteria Verification

For each acceptance criterion from the linked issue:
1. Identify how to verify it (API call, UI check, CLI command)
2. Execute the verification
3. Record pass/fail with evidence

### Step 5: Cleanup

Kill any background services started in Step 1:
```bash
kill %1 2>/dev/null  # or specific PID
```

## Output Format

```markdown
## Runtime Verification Results

### Service Status
| Service | Command | Status | Notes |
|---------|---------|--------|-------|
| Dev server | npm run dev | Started on :3000 | Healthy after 3s |

### Smoke Tests
| Endpoint/Feature | Test | Status | Evidence |
|-----------------|------|--------|----------|
| POST /api/users | Create user with valid data | Pass | 201 Created |
| POST /api/users | Create user with invalid email | Pass | 400 Bad Request |

### E2E Tests
| Suite | Status | Passed | Failed |
|-------|--------|--------|--------|
| Playwright | Pass | 12 | 0 |

### Acceptance Criteria
| Criterion | Verification Method | Status | Evidence |
|-----------|-------------------|--------|----------|
| Users can filter by date | GET /api/users?date=2024-01-01 | Pass | Returns filtered results |

### Not Verified (Requires Manual Check)
| Item | Reason |
|------|--------|
| Visual styling matches mockup | No browser automation available |
```

## Graceful Degradation

| Missing Capability | Fallback |
|-------------------|----------|
| No dev server command | Skip service startup, run only static checks |
| No E2E framework | Skip E2E, note as unverified |
| No health endpoint | Poll port availability instead |
| No verification commands in CLAUDE.md | Infer from tech stack, ask user if ambiguous |
| Server won't start | Report failure with logs, don't block workflow |

## Integration Points

This skill is invoked by:
- `gh-start` — Phase 7 (after quality checks, before code review)
- `gh-pr` — Phase 3 Step 3.5 (pre-PR runtime verification)

**IMPORTANT**: Runtime verification is additive, not blocking. If a project has no dev server or E2E framework, this skill completes with "skipped" status and the workflow continues.
