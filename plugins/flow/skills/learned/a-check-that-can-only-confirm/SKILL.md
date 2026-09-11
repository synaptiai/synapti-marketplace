---
name: a-check-that-can-only-confirm
description: '[flow-learned] A guard has two failure modes and only one is loud: reporting
  the wrong answer, and reaching nothing. Every guard needs a mutant that must NOT
  fire and a mutant that removes its input.'
source-sessions:
- '2026-09-01 issue #730'
- '2026-09-08 issue #743'
- '2026-09-09 issue #729'
evidence-count: 4
status: promoted
proposed: '2026-09-10'
promoted: '2026-09-11'
---

# A Check That Can Only Confirm

## Pattern Detected

Four times in three weeks, a guard passed while the thing it was written to check was
never examined. In each case every surface signal was green.

- A seeding check read post-truncation counts and reported two channels empty that had
  done real work; an earlier version missed two channels that really were empty.
- An identity walk handled two of the four spellings a package is imported under, stopped
  early, and reported nothing missing — including when a required file was deliberately
  removed from the roster.
- A figure guard matched a number only when a unit followed it, so a block containing only
  rates and confidence bounds was checked against nothing. An invented hit rate passed.
- A repo-wide guard asserting "the vector search is not approximate" would have failed a
  true sentence in the second, genuinely approximate substrate. Three rounds of mutants all
  asked "does this catch a false claim"; none asked "does this stay silent on a true one".

## Knowledge

### When This Applies

Whenever you write or change a check that walks, greps, or scans — a repo test, an
identity roster, a claim guard, a seeding verification, a lint rule.

### What To Do

- Write two mutants, always. One that must make it fire. One that must NOT: a correct
  input that resembles the incorrect one closely enough to be mistaken for it.
- Write a third mutant that removes the check's input — delete an entry from the roster,
  empty the directory it walks, rename the symbol it starts from. If the check still
  passes, it is reaching nothing.
- Make a check that finds nothing say so out loud: a count of what it examined, asserted
  to be greater than zero.
- Run the check against a real full-scale artifact, not a fixture. Two of these defects
  were only visible in what a production-sized run produced.

### What To Avoid

- Inferring intent from neighbouring words. A guard that excludes hits because a nearby
  line contains a denial will keep excluding the wrong ones.
- Accepting a stand-in type in the test. A list supports `len` and indexing, so a suite
  that passes lists where the code takes a flat buffer never constructs the type under
  test.
- Reading a number that exists as a number that answers the question.

## Evidence

### Journal Citations

- `.decisions/issue-730.md`: "A check that can only confirm is not a check"; "Then the check itself was wrong, and only the real artifact showed it"; "A test that accepts a stand-in for the type under test can pass without exercising it"
- `.decisions/issue-743.md`: "A guard can pass by finding nothing"; "The figure guard was reading past every number without a unit"
- `.decisions/issue-729.md`: "A guard's mutants have to include one that must NOT fire"; "The first version of that guard passed on both defects"

### Example

```
Before: assert not offending_files          # passes when the walk reached zero files
After:  assert examined_files, "guard reached no files"
        assert not offending_files
        # plus a mutant: delete one required entry from the roster; the guard must fail
```

## Verification

- [ ] Every new guard's journal has a mutant row that must NOT fire.
- [ ] Every new guard's journal has a mutant row that removes its input.
- [ ] The guard asserts a non-zero count of what it examined.

## Promotion Checklist

- [ ] Reviewed by human
- [ ] Evidence is compelling (not coincidental)
- [ ] Knowledge is general (not issue-specific)
- [ ] Doesn't duplicate existing skills
- [ ] Fits within context window budget
- [ ] Copied to `plugins/flow/skills/learned/a-check-that-can-only-confirm/SKILL.md`
- [ ] Committed and PR created
