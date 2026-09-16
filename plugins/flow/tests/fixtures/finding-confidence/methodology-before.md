## Confidence and signal

High (verified by running code/test, or LSP diagnostic / find-references): always include. Medium (verified by reading the code path): include for P1/P2. Low (pattern match only): include only as P1 marked "needs investigation". Style preferences are P3 at most. Only High-confidence P1s block merge. A finding with no `file:line` and no concrete harm scenario is noise; drop it.

## Boy Scout recognition

APPROVE `improve:` commits that pass the proximity test (file already modified, self-evidently correct, <10 lines, no API change); P2 "scope creep" only when it fails.

## Review cycle awareness

Count prior `FLOW_REVIEW_CYCLE` markers for the cycle number; review only the delta, verify each claimed resolution against `git diff`, and on the 3rd+ cycle raise only new P1s. Parsing commands and the Previous Feedback Status table: `references/review-cycle-parsing.md`.

## Stop conditions

- Stage 1 finds >3 unmet acceptance criteria: REQUEST_CHANGES immediately, skip Stage 2
- PR modifies files unrelated to the issue: flag as out-of-context, ask for a split (`improve:` commits in already-modified files are in context)
- Diff >500 lines with no test changes: P1 "untested large change"

## Review decision

| Findings | Decision |
|---|---|
| Any P1 | REQUEST_CHANGES |
| Any P2 | REQUEST_CHANGES |
| P3 only | COMMENT; author fixes every P3 in-PR, not "approve with nits" |
| None | APPROVE |
