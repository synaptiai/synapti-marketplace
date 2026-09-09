# Flow correctness evals

Seeded-bug tasks that measure whether flow's testing gates change how often an
agent ships a *correct* implementation. Each case directory follows the
`claude plugin eval` layout (`prompt.md` with frontmatter + `graders/*.md`)
and adds what that tool cannot express: a hidden `unittest` suite derived from
the spec and checked against a reference implementation, plus deliberately
wrong variants that prove each hidden test discriminates a real trap.

```
evals/<case>/
  prompt.md            frontmatter (name, tags, runs, max_turns, timeout_seconds, allowed_tools) + task prompt
  graders/             official grader types (file_exists, regex) for `claude plugin eval`
  scaffold/            starting repo state: ISSUE.md, skeleton module, empty tests/ package
  hidden/test_hidden.py   the scoring suite; the agent never sees it
  hidden/reference_impl.py   known-good implementation the suite was verified against
  hidden/traps/*.py    one wrong variant per seeded trap
  hidden/traps.json    trap -> tests that fail under its variant (generated, verified by --check-cases)
  expected.md          human-readable trap table
```

Run with `plugins/flow/bin/flow-eval-run.sh` (see
[`../references/correctness-eval.md`](../references/correctness-eval.md)).
`claude plugin eval plugins/flow` reads the same cases but scores only the
official graders; it reported "currently in early access" and ran nothing on
Claude Code 2.1.266, which is why the runner exists.
