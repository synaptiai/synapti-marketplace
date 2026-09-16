## Example Findings

### P1 — Critical (Blocks Merge)
| Finding | Suggested Fix |
|---------|---------------|
| **F1 · security · `src/auth.ts:42`**<br>SQL injection via string interpolation. _(HIGH)_ | Use parameterized query. |
| **F2 · correctness · `src/api.sh:88`**<br>`grep \| head` exits early and the pipeline status is lost. _(MEDIUM)_ | Use a here-string. |
| **F3 · edge-case · `src/job.ts:17`**<br>Looks like a race on the retry counter. _(LOW)_ | Confirm with a concurrent test. |

### Scope
| Scope | Description | Priority |
|---|---|---|
| **Introduced** | Code added on this branch | Natural P1/P2/P3 |
