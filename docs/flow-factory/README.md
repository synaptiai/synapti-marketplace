# Flow factory design inputs

These files are the inputs to the flow factory design. The factory takes GitHub issues that carry a queue label and drives each one to a ready pull request without a person starting each step. The plan is in `plan.md`.

| File | What it holds |
|---|---|
| `plan.md` | The approved plan: decisions, design summary, probes, phases and verification |
| `design.json` | The full design, one section per key. `__open_before_fix` lists the items that were still open before the last revision |
| `design-check-2026-11-11.json` | The last check of `design.json`: which of those items the final text closes, and the contradictions the check found |
| `design-critic.json` | The critic's findings on the first synthesized design |
| `gaps.md` | The 24 gaps between flow 3.16.0 and an unattended factory, each checked against flow's code |
| `research-zazen-factory-v2.md` | Analysis of the ZazenCodes software factory v2 (GPLv3: ideas only, no code or prompt text is reused) |
| `research-aidlc-v2.md` | Analysis of AWS AI-DLC v2 |
| `research-flow-lifecycle.md`, `research-flow-runtime.md` | How flow's commands, state and safety checks work today, read at aab0d132 |

`design.json` is not final. `/flow:design` reworks it before any phase is built: the job state table becomes data that a script checks, and the open defects listed in `plan.md` Step 1 are closed.
