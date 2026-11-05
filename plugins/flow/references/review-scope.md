# Review Scope

Reference document. What a review finding may rest on, in whatever project flow is reviewing.
`/flow:review`, `/flow:pr`, `/flow:address` and `/flow:start` hand these rules to every reviewer with
the project's review exceptions, and `bin/flow-finding-route.sh` routes a finding that names no
trigger LOW, where it can ask for investigation but never decides the review.

The rules below are written about **the project under review**: its users, its callers, the
platforms it supports and the input it treats as untrusted, all as the project itself states them.
A project narrows them with rows in its review exceptions file
(`<runtime dir>/review-exceptions.md`, read at the pull request's base commit by
`bin/flow-review-exceptions.sh`), so a pull request cannot change the scope it is judged by. An exception row can only take a finding out; a project that wants more in scope says so in its own documentation of what it supports and trusts.

## Why

A reviewer told to flag whatever it cannot prove correct never runs out of findings: every fix opens
a new input to doubt, and review rounds stop only when someone calls a halt. A finding that has to
name what makes it happen, inside a declared scope, is one a fix can close.

## A trigger

The trigger is the concrete input or condition, produced by a setup this scope covers, that makes
the defect happen, and what then goes wrong. One line:

- `a user submits the form with the optional email left empty → the handler raises and returns 500`
- `the upstream API answers 429 → the client retries without delay and the job never ends`

These are not triggers: "this is not validated", "this could fail", "I cannot prove this is handled",
"an attacker could…" with no way for the attacker to reach the code. A finding with none of its own is
a pattern match.

## In scope

- Input the project's users and callers produce in normal use, including the mistakes they plausibly
  make: an empty or missing value, a typo, a file that is not there, a dependency not installed, an
  action repeated. Ordinary configuration is normal use too: the user's locale, shell, common
  environment variables and tool configuration, for a project that runs where users configure them.
- The platforms, runtimes and versions the project says it supports: its README, its package
  manifest (an `engines` field, `python_requires`, a toolchain file) or, when it states none, what its
  CI runs on.
- Input from outside the project's trust boundary, as the project defines it, wherever it reaches code
  that acts on it: network requests, uploaded files, third-party API responses, content written by
  other users, or files and configuration from sources the project does not control.
- Loss or corruption of users' data, and exposure of credentials or private data.
- Text the project publishes (documentation, messages, a pull request or commit description) that
  states something the code does not do: it misleads the next reader.

## Out of scope, unless the change is about it

- The operator's own environment set to defeat the tool: a value no one sets for any other reason.
- Someone who already has the access the defect would give: the user's account, write access to their
  machine, their home or their own temp directory (a shared `/tmp` is not theirs alone), the database
  the code writes to.
- Races against the user's own processes, in a tool one user runs.
- Values the producer never emits under its contract: `NaN` from a source that writes integers, a
  field the API documents as always present arriving absent.
- Platforms, runtimes and versions the project does not support.
- Wording, formatting and style that misleads no reader and breaks no tool. It is not a finding at
  any priority.

A finding whose only trigger is in this list is not raised. One that is raised anyway is dropped at
synthesis and recorded as a `dropped-finding` with `reason=out-of-scope`
(`references/decision-journal-schema.md`).

## Priority

Priority is what the trigger breaks, weighed by how likely the trigger is.

| Priority | The trigger… |
|---|---|
| P1 | breaks what the change is for, loses or exposes users' data, or opens a security hole in scope |
| P2 | gives a wrong result, or a failure the user cannot get past without reading the code |
| P3 | gives a degraded result with an obvious way around it, or published text misleads its reader |

A likely trigger keeps its priority; one that needs several unlikely conditions at once drops a level.
A finding never rises above the priority its trigger supports because the reviewer is sure of it:
certainty is confidence, which is a separate field (`references/finding-schema.md`).

## Later cycles

A later cycle reviews what the fixes changed. From cycle 2 a P3, and from cycle 3 a P2, is listed
under "Not counted in this cycle" and decides nothing; it is fixed in the same batch as the P3s, and
that batch starts no new cycle (`skills/code-review-methodology/SKILL.md` § Review cycle awareness).
