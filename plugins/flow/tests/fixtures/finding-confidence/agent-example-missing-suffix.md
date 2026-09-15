## Example Findings

### P1 — Critical (Blocks Merge)
| Finding | Suggested Fix |
|---------|---------------|
| **F1 · security · `src/auth.ts:42`**<br>SQL injection via string interpolation. _(HIGH)_ | Use parameterized query. |
| **F2 · correctness · `src/api.ts:88`**<br>Off-by-one in the page cursor. | Use `<` not `<=`. |
