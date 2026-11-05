# Review Scope

Reference document. What a review finding may rest on. `/flow:review` and `/flow:pr` hand these
rules to every reviewer with the team's review exceptions, and `bin/flow-finding-route.sh` routes a
finding that names no trigger LOW, where it can ask for investigation but never decides the review.

A repository extends the out-of-scope list with rows in its review exceptions file
(`<runtime dir>/review-exceptions.md`, read at the pull request's base commit by
`bin/flow-review-exceptions.sh`), so a pull request cannot widen the scope it is judged by.

## Why

Reviewers told to flag whatever they could not prove correct produced findings without end. On
#251 the count per cycle never fell over 14 cycles (19 to 31 findings each), and in a hand-picked sample of
51 findings from #250, #251, #307 and #301 about a quarter were defects a user could hit; 18 defended
against inputs no supported setup produces, and 14 were wording or count nits. A finding that has to
name what makes it happen, inside a declared scope, is one a fix can close.

## A trigger

The trigger is the concrete input or condition, produced by a setup this scope covers, that makes
the defect happen, and what then goes wrong. One line:

- `a caller passes an empty --input path → the router reads stdin and posts an empty marker`
- `the issue body has no acceptance criteria → start plans with no tasks and reports success`

These are not triggers: "this is not validated", "this could fail", "I cannot prove this is handled",
"an attacker could…" with no way for the attacker to reach the code. A finding with none of its own is
a pattern match.

## In scope

- Inputs the change's users and callers produce in normal use, including the mistakes they plausibly
  make: a typo, an empty value, a missing file, a tool that is not installed, a command run twice.
- The supported platforms in the plugin README's requirements: macOS, Linux and Windows with Git
  Bash; bash 3.2 or newer; zsh where a command fence runs, because Claude Code runs fences with the
  user's shell.
- Content the user does not control, where it reaches a decision flow makes: someone else's pull
  request under review, issue and comment text written by others, and a repository's committed files
  when they choose settings that widen what runs, paths flow writes, or commands it runs or publishes.
- Loss of the user's work, and publication of their credentials or private data.
- Text flow publishes (a pull request body, a commit message, an issue, a review) that states
  something the change does not do: it misleads the next reader.

## Out of scope, unless the change is about it

- The user's own environment working against them: shell variables, aliases and options the user set
  (an exported `CDPATH`, `GREP_OPTIONS`, a `cd` function).
- Someone who already has the user's account, or write access to their home directory or `TMPDIR`.
- Races against the user's own processes.
- Values the producer never emits: `NaN` or infinity from a source that writes integers, malformed
  output from a tool flow itself runs and pins.
- Control characters, line separators or invalid UTF-8 in file names of the user's own repository,
  unless the name comes from content the user does not control and reaches a decision (above).
- Platforms, shells and tool versions the README does not list as supported.
- Wording, formatting and style that misleads no reader and breaks no tool. It is not a finding at
  any priority.

A finding whose only trigger is in this list is not raised. One that is raised anyway is dropped at
synthesis and recorded as a `dropped-finding` with `reason=out-of-scope`
(`references/decision-journal-schema.md`).

## Priority

Priority is what the trigger breaks, weighed by how likely the trigger is.

| Priority | The trigger… |
|---|---|
| P1 | breaks what the change is for, loses or publishes the user's data, or opens a security hole in scope |
| P2 | gives a wrong result, or a failure the user cannot get past without reading the code |
| P3 | gives a degraded result with an obvious way around it, or published text misleads its reader |

A likely trigger keeps its priority; one that needs several unlikely conditions at once drops a level.
A finding never rises above the priority its trigger supports because the reviewer is sure of it:
certainty is confidence, which is a separate field (`references/finding-schema.md`).

## Later cycles

A later cycle reviews what the fixes changed. From cycle 2 a P3, and from cycle 3 a P2, is listed
under "Not counted in this cycle" and decides nothing; it is fixed in the same batch as the P3s, and
that batch starts no new cycle (`skills/code-review-methodology/SKILL.md` § Review cycle awareness).
