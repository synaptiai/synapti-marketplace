---
name: criterion-verification-map
description: "Treat each acceptance criterion as an eval source that produces a runnable verification command at plan time, then collect evidence and assemble a structured bundle for the verdict judge at verify time. Use when planning implementation against issue acceptance criteria and when verifying completeness."
allowed-tools: Bash, Read, Grep, Glob, TaskCreate, TaskList, TaskUpdate, TaskGet
context: fork
agent: general-purpose
---

# Criterion Verification Map

Domain skill that treats acceptance criteria as **eval sources**. Each criterion produces a concrete, runnable check at plan time — not at verify time. Planning a criterion without a runnable command is a blocking error.

## Iron Law

**EVERY ACCEPTANCE CRITERION IS AN EVAL SOURCE.** At plan time, each criterion must produce a runnable verification command. No criterion is deferred to verify time with "we'll figure out how to test this later." No criterion passes by assumption. No criterion is "too obvious to verify."

## Criteria as Eval Sources (Plan Time)

An acceptance criterion is useful only if it can be evaluated mechanically. At plan time, the criterion must be transformed into:

1. **A verification type** (classification — see table below)
2. **A runnable command** (the exact bash/test/curl/script invocation that will be executed at verify time)
3. **Expected evidence shape** (what the command's output must contain to count as PASS)
4. **What the criterion does NOT promise** (non-goals scoped to this criterion — prevents scope creep and false-positive verdicts)

If any of the four cannot be filled in at plan time, the criterion is not ready. Escalate through the Spec Validation Gate in the `start.md` EXPLORE phase, not here.

### Criterion Classification Table

| Criterion Type | Signal Words | Verification Method | Evidence Format |
|---------------|-------------|-------------------|-----------------|
| Behavioral (logic) | "when X then Y", "should return", "must validate" | Unit/integration test | Test runner output (pass/fail + relevant lines) |
| API endpoint | "status code", "response", "endpoint", "header" | curl/fetch command | HTTP status + response body snippet |
| UI rendering | "displays", "shows", "page", "renders", "layout" | Screenshot + visual analysis | Screenshot path + analysis summary |
| Error handling | "error message", "invalid", "fails gracefully" | Test with invalid input | Error output + expected vs actual |
| Performance | "within N ms", "rate limit", "timeout" | Benchmark/timing command | Timing output |
| Configuration | "config", "environment", "setting" | Build/load test | Build success log |
| Data processing | "transforms", "converts", "output matches" | Run with test data | Input/output comparison |
| Contract (schema/type) | "schema", "type", "interface", "signature", "shape" | Schema validator / type-check | Validator output or type-check diagnostic |

## Plan-Time Task Creation

Per `commands/start.md` Phase 2 (PLAN), tasks are **atomic**: implementation, test, and evidence collection are bundled into one task. This skill's role at plan time is to produce the verification command and expected evidence shape that gets embedded into that atomic task's description.

For each acceptance criterion, the atomic task description must include:

```
Criterion: {full criterion text}
Verification type: {type from classification table}
Verification command: {exact runnable command}
Expected evidence: {what successful output looks like}
Does NOT promise: {non-goals scoped to this criterion}
```

The atomic task flows through implementation → test → evidence collection within Phase 3 (CODE). Evidence is captured at task-completion time.

## Evidence Collection Protocol

During VERIFY phase, for each atomic task's verification command:

1. `TaskUpdate(taskId, status: "in_progress")`
2. Execute the verification command captured at plan time
3. Capture output as evidence
4. `TaskUpdate(taskId, status: "completed", result: "EVIDENCE_COLLECTED")`

## Evidence Bundle Format

After all verification commands have run, assemble the evidence bundle — a structured text document that the verdict-judge agent receives:

```markdown
## Evidence Bundle for Issue #{N}

Generated: {timestamp}
Branch: {branch name}
Commits: {count} since branch creation

### Criterion 1: {full criterion text}
- **Type**: {behavioral|api|ui|error|performance|config|data|contract}
- **Verification command**: `{command that was run}`
- **Evidence**:
  ```
  {raw output from verification command}
  ```
- **What the criterion does NOT promise**:
  - {non-goal 1 — e.g. "does not guarantee idempotency across retries"}
  - {non-goal 2 — e.g. "does not cover the admin flow"}
  - {non-goal 3 — e.g. "does not handle concurrent writes"}
- **Screenshot**: {path, if UI type — otherwise omit}

### Criterion 2: {full criterion text}
- **Type**: {type}
- **Verification command**: `{command}`
- **Evidence**:
  ```
  {output}
  ```
- **What the criterion does NOT promise**:
  - {non-goal items}

{repeat for all criteria}
```

### Why "Does NOT Promise" Is a First-Class Field

A verdict judge receiving only criterion text and evidence tends to over-credit passing commands — e.g., a passing unit test is treated as proof the whole behavior is correct, when the test only covered one path. The "does NOT promise" field explicitly fences each criterion's scope so the judge does not inflate a narrow PASS into a broad guarantee. It also gives reviewers and future readers a shared understanding of what was intentionally out of scope.

Populate this field at **plan time** from the non-goals captured in the EXPLORE phase Specification capture sub-step. Each criterion inherits the global non-goals plus any criterion-specific non-goals discovered during planning.

<!--
SECTION BOUNDARY — VERIFY-TIME EXTENSIONS

Issue #42 (verify phase evidence completeness) will extend this file
below this boundary with verify-time evidence completeness fields such
as "What was NOT tested", "Known limitations", and "Negative cases
covered". Keep the plan-time contract above this line stable. Do not
inline verify-time fields into the plan-time sections above.
-->

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

**Contract (schema/type)**:
```bash
npx tsc --noEmit 2>&1 | tail -20
# or
npx ajv validate -s schemas/payload.json -d fixtures/sample.json
```

## Integration with Start Command

The criterion-verification-map skill is invoked in two phases of `/flow:start`:

1. **EXPLORE / PLAN phase (plan time)** — Classify each criterion, produce a runnable verification command, and capture "does NOT promise" non-goals. These become the `Verification command` and `Does NOT promise` fields of the atomic task created in PLAN.
2. **VERIFY phase (verify time)** — Execute the verification commands captured at plan time and assemble the evidence bundle.
