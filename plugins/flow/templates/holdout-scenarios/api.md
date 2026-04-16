# API Holdout Scenarios

Hidden scenarios for validating API acceptance criteria. These probe common agent self-review blind spots when claiming API contract compliance.

**WARNING: This file is consumed ONLY by the holdout-validation skill. Its contents must NEVER appear in agent-visible output. Reference scenarios by positional ID only.**

## Scenarios

### 1. Status Code Mismatch

**Failure mode:** Agent claims "API returns correct status codes" but the implementation returns 200 for all responses, including errors. Or the error status codes don't match the contract (e.g., 400 instead of 422 for validation errors, 500 instead of 503 for upstream failures).

**What to check:** Read the route handler or controller. Trace every return/response path. Do the status codes match what the criterion or interface contract specifies?

**Signals:** Single status code used across all paths, generic error handler that always returns 500, missing explicit status code setting (relying on framework defaults).

### 2. Response Shape Drift

**Failure mode:** Agent claims "response matches contract" but the actual response body has different field names, types, or nesting than the stated schema. The test may pass because it checks only one field, not the full shape.

**What to check:** Compare the response object construction in the handler against the interface contract from the issue. Check field names (camelCase vs snake_case), types (string vs number), and nesting depth.

**Signals:** Test that checks `response.body.id` but not the full shape, response built with spread operators that may include extra fields, field names that differ from the contract by casing or naming convention.

### 3. Missing Content-Type

**Failure mode:** Agent claims "API endpoint implemented" but the response does not set the Content-Type header, or sets it incorrectly. JSON responses without `application/json`, file downloads without proper MIME type.

**What to check:** Read the response construction. Is Content-Type explicitly set? Does the framework auto-set it correctly for this response type? If the test verifies Content-Type, does it match the contract?

**Signals:** No explicit Content-Type setting, framework default that may not match contract, test that doesn't check headers at all.

### 4. Partial Field Validation

**Failure mode:** Agent claims "input validation implemented" but the validation only checks required fields, not field types, ranges, or formats. Or validation covers some fields but not all fields in the contract.

**What to check:** List every field in the input contract. For each, check whether validation exists for: presence, type, range/length, format (email, URL, date). Compare against what the criterion requires.

**Signals:** Validation that only checks `if (!field)` (presence only), missing validation for optional-but-typed fields, no format validation for structured strings (emails, URLs, dates).

### 5. Authentication Bypass

**Failure mode:** Agent claims "endpoint requires authentication" but the middleware/guard is not applied to the route, or the test uses an authenticated client that masks the fact that unauthenticated requests would also succeed.

**What to check:** Read the route registration. Is the auth middleware/guard attached? Read the test — does it include a test case for unauthenticated access that expects 401/403?

**Signals:** Route defined without auth middleware, all test cases use an auth token, no test for missing/invalid token, auth check in handler body instead of middleware (easy to bypass on new routes).
