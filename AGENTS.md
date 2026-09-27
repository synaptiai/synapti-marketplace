# Agent rules

## Testing

- Never write unit tests after you write code.
- Highly prefer E2E tests as the sole testing mechanism. Use them to verify complex features work. At the end of E2E tests, produce a verifiable and repeatable artifact.
- If you must test a system in isolation, first write down all the ways it could fail, then write the code.

For the flow plugin, write E2E tests with `plugins/flow/tests/lib/e2e.sh`; the `plugins/flow/tests/e2e-*.test.sh` files are examples. It runs the shipped command block or hook in a scratch repository the way Claude Code runs it, and writes one artifact file per scenario. Set `FLOW_E2E_ARTIFACT_DIR` to keep the artifacts; without it they are kept only when an expectation fails, and the run prints where.
