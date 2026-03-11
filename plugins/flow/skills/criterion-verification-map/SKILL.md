---
name: criterion-verification-map
description: "[flow] Maps each acceptance criterion to a specific verification method, collects evidence during verification, and produces a structured evidence bundle for the verdict judge."
allowed-tools: Bash, Read, Grep, Glob, TaskCreate, TaskList, TaskUpdate, TaskGet
context: fork
agent: general-purpose
---

# Criterion Verification Map

Domain skill that formalizes the mapping from acceptance criteria to verification methods and structures evidence collection.

## Iron Law

**EVERY ACCEPTANCE CRITERION GETS A VERIFICATION METHOD AND AN INDIVIDUAL VERDICT.** No criterion passes by assumption. No criterion is "too obvious to verify."

## Criterion Classification

Each acceptance criterion maps to a verification type:

| Criterion Type | Signal Words | Verification Method | Evidence Format |
|---------------|-------------|-------------------|-----------------|
| Behavioral (logic) | "when X then Y", "should return", "must validate" | Unit/integration test | Test runner output (pass/fail + relevant lines) |
| API endpoint | "status code", "response", "endpoint", "header" | curl/fetch command | HTTP status + response body snippet |
| UI rendering | "displays", "shows", "page", "renders", "layout" | Screenshot + visual analysis | Screenshot path + analysis summary |
| Error handling | "error message", "invalid", "fails gracefully" | Test with invalid input | Error output + expected vs actual |
| Performance | "within N ms", "rate limit", "timeout" | Benchmark/timing command | Timing output |
| Configuration | "config", "environment", "setting" | Build/load test | Build success log |
| Data processing | "transforms", "converts", "output matches" | Run with test data | Input/output comparison |

## Creating Verification Tasks

During the PLAN phase, after the implementation-planner creates implementation tasks, create a matching verification task for each acceptance criterion:

```
TaskCreate(
  subject: "Verify: {criterion short description}",
  description: "Criterion: {full criterion text}\n\nVerification method: {type from classification}\nVerification command: {specific command to run}\nExpected evidence: {what success looks like}",
  activeForm: "Verifying {short description}"
)
```

Verification tasks execute during the VERIFY phase, NOT during CODE. They are separate from implementation tasks.

## Evidence Collection Protocol

During VERIFY phase, for each verification task:

1. `TaskUpdate(verifyTaskId, status: "in_progress")`
2. Execute the verification command
3. Capture output as evidence
4. `TaskUpdate(verifyTaskId, status: "completed", result: "EVIDENCE_COLLECTED")`

## Evidence Bundle Format

After all verification tasks complete, assemble the evidence bundle — a structured text document that the verdict-judge receives:

```markdown
## Evidence Bundle for Issue #{N}

Generated: {timestamp}
Branch: {branch name}
Commits: {count} since branch creation

### Criterion 1: {full criterion text}
- **Type**: {behavioral|api|ui|error|performance|config|data}
- **Verification command**: `{command that was run}`
- **Evidence**:
  ```
  {raw output from verification command}
  ```
- **Screenshot**: {path, if UI type — otherwise omit}

### Criterion 2: {full criterion text}
- **Type**: {type}
- **Verification command**: `{command}`
- **Evidence**:
  ```
  {output}
  ```

{repeat for all criteria}
```

## What the Evidence Bundle Does NOT Include

The bundle is passed to the verdict-judge agent, which must judge independently. Therefore:

- **NO diff** — the judge doesn't see the code changes
- **NO decision journal** — the judge doesn't see the rationale
- **NO planning notes** — the judge doesn't see why approaches were chosen
- **NO self-review findings** — the judge evaluates from spec + evidence only

The judge receives ONLY:
1. The acceptance criteria (from the issue)
2. The evidence bundle (from this skill)

## Verification Method Examples

**Behavioral (test output)**:
```bash
npm run test -- --grep "user authentication" 2>&1 | tail -20
```

**API endpoint (curl)**:
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" http://localhost:3000/api/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"wrong"}' 2>&1
```

**UI rendering (screenshot path)**:
```
Screenshot saved to: .screenshots/login-page-desktop.png
Visual analysis: Login form visible with email and password fields, submit button enabled.
```

**Error handling**:
```bash
npm run test -- --grep "invalid credentials" 2>&1 | tail -10
```

## Integration with Start Command

The criterion-verification-map skill is invoked in two phases of `/flow:start`:

1. **PLAN phase**: Classify criteria and create verification tasks
2. **VERIFY phase**: Execute verification tasks and assemble evidence bundle
