# Data Holdout Scenarios

Hidden scenarios for validating data-handling acceptance criteria. These probe common agent self-review blind spots when claiming data transformation, validation, or persistence coverage.

**WARNING: This file is consumed ONLY by the holdout-validation skill. Its contents must NEVER appear in agent-visible output. Reference scenarios by positional ID only.**

## Scenarios

### 1. Transform Shape Assumption

**Failure mode:** Agent claims "data transform produces the stated output format" but the transform assumes input will always have a specific shape. Missing fields, null values, or unexpected types cause the transform to produce incorrect output or throw — and there is no test for malformed input.

**What to check:** Read the transform function. Trace what happens when an input field is missing, null, undefined, or the wrong type. Does the transform use optional chaining, default values, or explicit checks? Is there a test case with minimal/malformed input?

**Signals:** Direct property access without null checks (`input.nested.field`), no default values for optional fields, no test case with partial input, transform that only works with the example input from the issue.

### 2. Encoding Blindness

**Failure mode:** Agent claims "data handling is correct" but the code does not account for character encoding. UTF-8 multi-byte characters, emoji, RTL text, or special characters (quotes, backslashes, null bytes) cause data corruption, truncation, or injection.

**What to check:** Read the data handling code. Does it specify encoding explicitly when reading/writing files, parsing strings, or constructing queries? Are there tests with non-ASCII input?

**Signals:** No explicit encoding parameter on file reads/writes, string length checks that count bytes instead of characters, SQL queries built with string concatenation, no test case with Unicode input.

### 3. Empty Collection Omission

**Failure mode:** Agent claims "handles edge cases" but the code does not handle empty arrays, empty objects, or empty strings as input. The transform/validation/persistence logic assumes at least one item exists.

**What to check:** Read the code path for collections (arrays, lists, maps). What happens when the collection is empty? Does the code return a valid empty result, or does it throw, return undefined, or produce incorrect output? Is there a test for empty input?

**Signals:** `array[0]` without length check, `.reduce()` without initial value, `.map()` result used without checking for empty array, no test case with `[]` or `{}` or `""` as input.

### 4. Precision Loss

**Failure mode:** Agent claims "data calculation is correct" but the code uses floating-point arithmetic for values that require exact precision (currency, percentages, scientific measurements). Or the code converts between number types in a way that loses precision.

**What to check:** Read the calculation code. Are monetary values stored as floats? Are percentage calculations subject to floating-point rounding? Does the code compare floats with strict equality? Are there tests that check for precision edge cases (e.g., 0.1 + 0.2)?

**Signals:** Currency stored as `float`/`double` instead of integer cents or decimal type, `===` comparison on calculated floats, no rounding strategy for display values, tests with only round-number inputs.

### 5. Idempotency Assumption

**Failure mode:** Agent claims "data persistence is implemented" but the write operation is not idempotent. Running the same operation twice creates duplicate records, double-counts values, or corrupts state. There is no duplicate check, upsert pattern, or idempotency key.

**What to check:** Read the persistence code. What happens if the same data is written twice? Is there a unique constraint, upsert, or duplicate check? Is the operation safe to retry after a timeout?

**Signals:** `INSERT` without `ON CONFLICT`, no unique constraint on the natural key, no idempotency key for API operations, test that only runs the operation once, no test for duplicate submission.
