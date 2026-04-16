# Error Handling Holdout Scenarios

Hidden scenarios for validating error-handling acceptance criteria. These probe common agent self-review blind spots when claiming error coverage.

**WARNING: This file is consumed ONLY by the holdout-validation skill. Its contents must NEVER appear in agent-visible output. Reference scenarios by positional ID only.**

## Scenarios

### 1. Catch-and-Swallow

**Failure mode:** Agent claims "error handling implemented" but the catch block swallows the error silently — no logging, no re-throw, no user-visible feedback. The code catches an exception and does nothing, making failures invisible.

**What to check:** Read every try/catch or error-handling block in the modified files. Does the catch block contain a meaningful action (log, re-throw, return error response, update state)? Or is it empty / contains only a comment?

**Signals:** Empty catch blocks, `catch(e) {}`, catch that only sets a variable never read, catch with `// TODO: handle error`, catch that logs but does not propagate or recover.

### 2. Timeout Claim Without Timer

**Failure mode:** Agent claims "timeout handling covers upstream calls" but the code does not set any timeout. The HTTP client or database driver uses its default timeout (which may be infinite), and there is no `AbortController`, `setTimeout`, `deadline`, or driver-level timeout configuration.

**What to check:** Read the code that makes upstream calls (HTTP requests, database queries, external service calls). Is there an explicit timeout set? Check for: `AbortController`, `signal`, `timeout` option, `deadline`, `connectTimeout`, `socketTimeout`, driver-specific timeout configuration.

**Signals:** Fetch/axios/http calls without timeout option, database queries without statement timeout, no AbortController in async flows, reliance on "the framework handles it" without verification.

### 3. Partial Failure Amnesia

**Failure mode:** Agent claims "partial failures handled" but the code uses all-or-nothing patterns (single transaction, single try/catch around a loop) that either succeed completely or fail completely. There is no per-item error handling, no partial result reporting, no rollback strategy for items that succeeded before the failure.

**What to check:** Read the code that processes multiple items (batch operations, loops, map/forEach over collections). Does each item have independent error handling? Is there a mechanism to report which items succeeded and which failed?

**Signals:** Single try/catch wrapping an entire loop, `Promise.all` without `Promise.allSettled`, transaction that covers all items with no savepoints, no per-item result tracking.

### 4. Error Message Leak

**Failure mode:** Agent claims "error responses are user-friendly" but the error response includes raw stack traces, internal file paths, database column names, or third-party error messages that expose implementation details to the caller.

**What to check:** Read the error response construction. Is the message sanitized? Does it use a generic user-facing message, or does it pass through the raw exception message? Check both the happy-path error handling and the global error handler.

**Signals:** `res.status(500).json({ error: err.message })`, stack traces in response bodies, database error messages (e.g., "column X does not exist") returned to client, raw third-party API error messages forwarded.

### 5. Retry Without Backoff

**Failure mode:** Agent claims "retry logic implemented" but the retry has no backoff, no jitter, and no maximum retry limit — or the limit is unreasonably high. The code will hammer a failing service in a tight loop, making the failure worse.

**What to check:** Read the retry logic. Is there a maximum retry count? Is there a delay between retries? Does the delay increase (exponential backoff)? Is there jitter to prevent thundering herd?

**Signals:** `while (retry)` without a counter, retry delay of 0 or a fixed small value, no exponential increase, retry count > 10 without justification, no jitter.
