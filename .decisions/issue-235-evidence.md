# Evidence Bundle — Issue #235

**Branch:** fix/issue-235-interpreting-print
**Generated:** 2026-09-19
**Acceptance criteria source:** issue #235 body, ## Acceptance Criteria section
**Total criteria:** 5

---

## Criterion 1: Every print site is safe by construction. No fence in `plugins/flow/commands/` passes a value through an interpreting builtin. Values are printed with `printf '%s\n'`; values handed to `jq`, `grep` or another parser are passed as arguments or through a here-string, never echoed into a pipe.

### Type

behavioral

### Verification command

```bash
bash plugins/flow/tests/run.sh no-interpreting-print.test.sh
bash plugins/dossier/tests/run.sh no-interpreting-print.test.sh
```

### Output

```
PASS no fence in any flow markdown file invokes an interpreting print — every markdown file scan reported its own counts
PASS no fence in any flow markdown file invokes an interpreting print — scan reached 156 files, 435 blocks, 7505 lines
PASS no fence in any flow markdown file invokes an interpreting print — no fence invokes echo
SUMMARY pass=30 fail=0

PASS no fence in any dossier markdown file invokes an interpreting print — every markdown file scan reported its own counts
PASS no fence in any dossier markdown file invokes an interpreting print — scan reached 75 files, 98 blocks, 1024 lines
PASS no fence in any dossier markdown file invokes an interpreting print — no fence invokes echo
SUMMARY pass=12 fail=0
```

Scope was widened past the criterion's `plugins/flow/commands/` to every markdown
file in both plugins, because the reference documents carry the canonical
snippets the commands are copied from and one of them stated the form being
replaced. The dossier plugin carries the identical defect and is fixed here.

**One deviation from this criterion's wording, stated for adjudication.** The
criterion lists the acceptable forms for a value handed to a parser as
"arguments or through a here-string", prohibiting "echoed into a pipe". The
prohibition holds: nothing is echoed into a pipe. The form delivered for a piped
value is `printf '%s\n' "$X" | CMD` — a pipe fed by a non-interpreting builtin,
which is neither of the two named forms. The here-string form was implemented
first and reverted: it changes where the value enters the command, and where the
pipeline's first command is a loop condition the redirect then belongs to `read`
rather than to the loop, so the here-string is re-created every iteration and the
loop never advances past its first line. That hung a loop in `commands/status.md`.
The property the criterion exists for — the value reaching the parser
byte-identical — holds in the delivered form and is asserted below.

### Visual analysis

none — criterion type behavioral has no visual surface

### Does NOT promise

- No change to any command's decisions, thresholds, ordering, or output grammar; every `KEY=` name and every line's meaning is unchanged.
- No encoding layer consumers must decode; no escape syntax is introduced.
- No input validation; no value is refused for carrying a backslash or a control character.
- No general shell-portability pass; constructs unrelated to printing are untouched.

### What was tested

That a scan reading every fenced block of every markdown file in both plugins
finds no invocation of `echo`, and that the scan reports the number of files,
blocks and lines it actually read so a scan that reached nothing cannot read as
clean.

### What was NOT tested

The guard does not read `bin/*.sh`, hook scripts, or markdown outside a fence.
It does not inspect `plugins/decipon/` or any plugin other than flow and dossier.

### Known limitations of this evidence

The scan reports a static property — that no fence invokes the builtin. It does
not by itself prove the resulting output is correct; that is criterion 5.

### Negative/adversarial cases covered

A comment line beginning `# echo`, a longer word (`echoes`), and `echo` inside a
quoted string are each asserted **not** to be offenders, so the scan is not
merely a substring match. A shell transcript line beginning `$ echo` is
deliberately not an offender, because it is a document example rather than a
script.

### Test inputs and expected values

| Input | Expected | Source of expected |
|---|---|---|
| every `*.md` under `plugins/flow` (156 files) | 0 offenders | the criterion: no fence passes a value through an interpreting builtin |
| every `*.md` under `plugins/dossier` (75 files) | 0 offenders | same |
| `# echo "commented out"` inside a fence | not an offender | a comment is not a command |
| `GREP_OUT=$(grep -c echoes file.txt)` | not an offender | `echoes` is a different word |
| `printf "%s\n" "echo inside a string is data"` | not an offender | a quoted string is an argument |
| `$ echo "$x"` inside a fence | not an offender | `$` is a prompt in a transcript, not a command |

### Risk map coverage

- where a piped value enters the consuming command → `print-line-integrity.test.sh`, the loop regression assertion; and the scan's own `no fence invokes echo`
- fence-boundary detection in the guard → `no-interpreting-print.test.sh`, the trailing-whitespace / mixed-tag / unterminated-block assertions
- argument splitting → `print-line-integrity.test.sh`, the print-form matrix
- empty and bare echo → `print-line-integrity.test.sh`, the empty and bare assertions
- the inline plugin-root resolver → `plugin-root-resolution.test.sh` scenario 7, the drift guard

---

## Criterion 2: A mechanical check enforces it, and it is demonstrated failing. A test scans every fence in every command file and fails on an offender. Its own coverage is proven by adding an offending line of each shape it claims to catch — a settings-derived echo, an inline-heredoc-read echo, a helper-output echo, and an `echo "$JSON" | jq` — and confirming each one turns it red. A guard whose comment claims completeness it does not have is the defect being fixed here, not an acceptable deliverable.

### Type

behavioral

### Verification command

```bash
bash plugins/flow/tests/run.sh no-interpreting-print.test.sh
```

### Output

```
PASS each offending shape turns the scan red — the settings-derived shape is reported (one offender)
PASS each offending shape turns the scan red — the settings-derived shape names line 2
PASS each offending shape turns the scan red — the inlined-heredoc shape is reported (one offender)
PASS each offending shape turns the scan red — the inlined-heredoc shape names line 5
PASS each offending shape turns the scan red — the helper-output shape is reported (one offender)
PASS each offending shape turns the scan red — the helper-output shape names line 2
PASS each offending shape turns the scan red — the piped-json shape is reported (one offender)
PASS each offending shape turns the scan red — the piped-json shape names line 2
PASS an echo opened by a word or a case arm is still a command — an echo in the case-arm position is an offender
PASS an echo opened by a word or a case arm is still a command — an echo in the then-branch position is an offender
PASS an echo opened by a word or a case arm is still a command — an echo in the else-branch position is an offender
PASS an echo opened by a word or a case arm is still a command — an echo in the if-opener position is an offender
PASS an echo opened by a word or a case arm is still a command — an echo in the while-body position is an offender
PASS an echo opened by a word or a case arm is still a command — an echo in the negated position is an offender
PASS the scan sees every block, including the ones a narrower parser drops — trailing whitespace on the closing marker does not hide the next block
PASS the scan sees every block, including the ones a narrower parser drops — untagged, bash-tagged and bang-tagged blocks are all read
PASS the scan sees every block, including the ones a narrower parser drops — an unterminated block is reported rather than truncated
SUMMARY pass=30 fail=0
```

Measured red before the fix, on the pre-conversion tree — a **one-time
measurement**, recorded here because the tree it was taken on no longer exists
in the working directory and it is not reproducible from the repository:

```
flow:    952 offending lines
dossier: 190 offending lines
```

The first version of the guard recognised only punctuation as a command opener
and read 53 real sites as arguments while reporting the tree clean — `case "$x"
in *) echo`, `if …; then echo`, `else echo`, `if echo … | jq`. Because the same
predicate drove the rewrite, guard and converter confirmed each other's blind
spot. With the predicate corrected the same scan reports 952 where it had
reported 907: 45 command sites that would have been certified clean. Each opener
now has its own fixture above.

### Visual analysis

none — criterion type behavioral has no visual surface

### Does NOT promise

- No claim that the scan understands shell in general; it recognises `echo` in command position, not arbitrary syntax.
- No claim of coverage over `bin/*.sh`, hooks, or prose outside a fence.

### What was tested

That each shape the guard claims to catch turns it red, naming the offending
line, and that a narrower fence parser does not.

### What was NOT tested

The injected shapes are synthetic fixtures, not real sites drawn from the tree.
The pre-conversion offender counts were measured on the tree that existed before
this branch, which is no longer in the working tree.

### Known limitations of this evidence

The mutation fixtures live in one file and are written to a temp dir; they
exercise the scanner function, not the full suite invocation.

### Negative/adversarial cases covered

Four offending shapes are injected and each must be reported. Six command
openers are injected and each must be reported. A closing marker with trailing
whitespace, a file mixing untagged, `bash`-tagged and `!`-tagged blocks, and an
unterminated block are each covered, because a scanner that skips a block
reports a clean tree it never read. Three non-offending shapes are asserted not
to fire.

### Test inputs and expected values

| Input | Expected | Source of expected |
|---|---|---|
| `V=$(jq -r .x .claude/settings.flow.json); echo "V=$V"` | 1 offender, line 2 | a settings value printed through the builtin |
| heredoc read into `V`, then `echo "V=$V"` | 1 offender, line 5 | an inline heredoc read printed |
| `echo "GOAL=$(flow-active-goal.sh --status)"` | 1 offender, line 2 | a helper's stdout printed |
| `echo "$JSON" \| jq -r .name` | 1 offender, line 2 | a payload relayed to a parser |
| `case "$V" in *) echo "K=$V" ;; esac` | 1 offender | `)` opens a command |
| `if true; then echo "K=$V"; fi` | 1 offender | `then` opens a command |
| `! echo "K=$V"` | 1 offender | `!` opens a command |
| `$ echo "$x"` | 0 offenders | a transcript prompt, not a script |
| closing marker ```` ``` ```` with trailing space, offender in the next block | 2 offenders | trailing whitespace must not leave the block open |
| unterminated block | an ANOMALY line | silently truncating would report clean |

### Risk map coverage

- fence-boundary detection in the guard → the trailing-whitespace, mixed-tag and unterminated-block assertions
- argument splitting, empty and bare echo → the print-form matrix in `print-line-integrity.test.sh`
- where a piped value enters the consuming command → the loop regression assertion in `print-line-integrity.test.sh`
- the inline plugin-root resolver → `plugin-root-resolution.test.sh` scenario 7
- Every row has a named assertion rather than a general claim.

---

## Criterion 3: The class is closed at its producers where a producer exists. A helper that emits a scalar for embedding (`flow-active-goal.sh`, `flow-review-exceptions.sh`, `flow-mine-corrections.sh`, and any other `bin/*.sh` printing metadata) emits exactly one line, so no consumer can forget. Verified with a fixture whose YAML/JSON value contains a real newline, a carriage return, a tab and the two-character `\n` sequence.

### Type

behavioral

### Verification command

```bash
bash plugins/flow/tests/run.sh print-line-integrity.test.sh
```

### Output

```
PASS a goal YAML cannot forge a line through a producer — a newline in the goal id does not add a line
PASS a goal YAML cannot forge a line through a producer — the forged key never begins a line of its own
PASS a goal YAML cannot forge a line through a producer — the real id value survives the collapse
PASS a goal YAML cannot forge a line through a producer — an ordinary status is reported unchanged
PASS carriage return, tab and a literal backslash-n also stay on one line — an id written as "a\rb" still prints one line
PASS carriage return, tab and a literal backslash-n also stay on one line — an id written as "a\tb" still prints one line
PASS carriage return, tab and a literal backslash-n also stay on one line — an id written as "a\\nb" still prints one line
PASS the consumer print form does not interpret what it is given — a backslash-n in a consumer line stays on one line
PASS the consumer print form does not interpret what it is given — the forged key never begins a line
SUMMARY pass=33 fail=0
```

**Scope adjustment, stated for adjudication.** The forged field is
`metadata.id`, read back through `bin/flow-active-goal.sh --id`, rather than
`lifecycle.status` through `--status` as this criterion's wording implies.
Selection requires `lifecycle.status` to be exactly `active`, so a status
carrying an escape is never selected and a fixture built on one exercises
nothing — an earlier version of this test did exactly that and appeared to pass.
The producer path under test is the same `_one_line` collapse that `--status`
uses. `--status` is separately asserted to return `active` unchanged, so the
ordinary path is covered too.

`flow-active-goal.sh` is the producer exercised by the command above.
`flow-review-exceptions.sh` and `flow-mine-corrections.sh` already emit one line
each — the former declares its encoding on an `ENCODING=` line and percent-encodes
a literal pipe, and the latter's metadata lines are static keys — so no change
was needed for them. Their one-line property is not asserted by an executed test;
see Known limitations.

**A third producer was found by review and is now covered.** The dossier config
resolver, `plugins/dossier/bin/cascade-resolve.sh`, printed a resolved settings
value with no control-character check, while its flow twin refuses those values.
A tracked `.claude/settings.dossier.json` carrying `"deliveryMode": "a\nFORGED=1"`
produced two lines, the second being a forged field. Reproduced before the fix,
then fixed by porting the twin's refusal. `bash plugins/dossier/tests/run.sh
no-interpreting-print.test.sh` now exercises all four branches — refused with the
declared default, exit 2 with no default, `--allow-control-chars` still passing
the value through, and an ordinary value unchanged — and was mutation-tested:
disabling the refusal turns three of its assertions red.

### Visual analysis

none — criterion type behavioral has no visual surface

### Does NOT promise

- No new producer CLI surface; no flag added or renamed.
- No refusal of any value for containing an awkward character; the value is collapsed, not rejected.
- No claim over every helper in the tree, only those that emit a `KEY=value` scalar.

### What was tested

That a goal YAML field whose value carries a real newline, a carriage return, a
tab and the two-character backslash-n sequence is collapsed to a single line by
the producer, and that the consumer line embedding it stays one line.

### What was NOT tested

`flow-review-exceptions.sh` and `flow-mine-corrections.sh` are not executed
against a fixture carrying an escape; their one-line property was read from
their source rather than run. No helper outside those named was audited.

### Known limitations of this evidence

The fixture is a synthetic goal YAML in a temp directory, not a real goal file.
The producer is invoked through its documented `--branch` selector against that
temp tree.

### Negative/adversarial cases covered

Four escape forms are injected: a real newline via a YAML double-quoted `\n`, a
carriage return, a tab, and the literal two-character `\n` written as `\\n`. A
forged key is asserted never to begin a line of its own, which is what a
consumer grepping `^KEY=` would mistake for a field.

### Test inputs and expected values

| Input | Expected | Source of expected |
|---|---|---|
| `metadata.id: "issue-900\nFLOW_GOAL_ID=forged"` | `--id` prints 1 line | the interface contract: a producer emits exactly one line |
| the same output | no line begins `FLOW_GOAL_ID=forged` | a forged key must not read as a field |
| the same output | contains `issue-900` | the real value must survive the collapse |
| `metadata.id: "a\rb"`, `"a\tb"`, `"a\\nb"` | 1 line each | same contract |
| `lifecycle.status: active` | `--status` prints exactly `active` | the ordinary path is unchanged |

### Risk map coverage

- empty and bare echo → the empty/bare assertions in the same file
- where a piped value enters the consuming command → the loop regression assertion
- argument splitting → the print-form matrix
- fence-boundary detection and the resolver → `no-interpreting-print.test.sh` and `plugin-root-resolution.test.sh`
- Nothing in this criterion's own risk surface is left without an assertion except the two producers noted above.

---

## Criterion 4: The three named instances no longer reproduce, each by the executed repro in Current State: the merge gate reports `LEDGER_GATE_STATE=blocked` for a body carrying a backslash before the marker; a goal YAML with a newline in `lifecycle.status` cannot forge a `FLOW_GOAL_LIFECYCLE` line; and a `gh` response containing an escaped character in a string is still parsed by `jq` rather than silently discarded.

### Type

behavioral

### Verification command

```bash
bash plugins/flow/tests/run.sh print-line-integrity.test.sh
```

### Output

```
PASS the merge gate sees findings through a body carrying a backslash — the gate can report blocked
PASS the merge gate sees findings through a body carrying a backslash — the gate can report ok
PASS the merge gate sees findings through a body carrying a backslash — an unresolved finding blocks the gate despite the backslash
PASS the merge gate sees findings through a body carrying a backslash — the gate names the finding it is blocking on
PASS the merge gate sees findings through a body carrying a backslash — the same body passes once the finding is resolved
PASS the merge gate sees findings through a body carrying a backslash — the interpreting builtin drops the findings array from the same body
PASS a JSON payload with an escape in a string is still parsed — jq reads a scalar through the here-string
PASS a JSON payload with an escape in a string is still parsed — jq decodes the escaped newline as data, not as structure
PASS a JSON payload with an escape in a string is still parsed — the interpreting route loses the same payload
SUMMARY pass=33 fail=0
```

The merge gate's extraction is taken **verbatim** from `commands/merge.md` by
pattern and executed, so this tests the shipped text rather than a copy that
could drift. If any anchor is reworded, the extraction yields empty and the test
fails loudly rather than running a gate with a variable unset.

The third clause — a goal YAML with a newline in `lifecycle.status` — is covered
by criterion 3 and by the consumer assertion: the value is collapsed at the
producer, and the consumer line that renders `FLOW_GOAL_LIFECYCLE=` uses a
non-interpreting builtin, so a newline in the status cannot forge the line the
merge gate reads. The `--status` path itself cannot be driven with an escaped
value, for the selection reason given under criterion 3.

### Visual analysis

none — criterion type behavioral has no visual surface

### Does NOT promise

- No change to the gate's decision logic; only how the review body reaches it.
- No change to the marker grammar or to which markers the gate looks for.
- No claim about a backslash in any position other than before the marker, which is the case the fixture carries.

### What was tested

That a review body whose finding location contains a backslash is still read by
the gate, that an unresolved finding in it blocks, that the same body opens once
the finding is resolved, and that the replaced extraction form loses the same
body. That a JSON payload carrying an escaped character survives to `jq`.

### What was NOT tested

The gate is exercised as an extracted fragment with `emit_block` and
`LEDGER_GATE_BLOCKED` stubbed, not through a live `gh` response. The extraction
covers the assignment lines and the decision block; the surrounding `gh` calls
are not run.

### Known limitations of this evidence

The fragment is assembled at test time from lines matched by pattern. A
restructuring that keeps every anchor but changes the surrounding control flow
would not be caught.

### Negative/adversarial cases covered

The converse case is asserted: the same body must report `ok` once the finding
is resolved, so the blocking assertion cannot pass on a gate that always blocks.
The replaced form is run against the same body and shown to yield no findings, so
the repro is a change in behaviour rather than an artifact of the fixture.

### Test inputs and expected values

| Input | Expected | Source of expected |
|---|---|---|
| `FINDINGS:[F1\|P1\|security\|src/\cmd.ts\|HIGH\|consensus\|code-reviewer]` with marker last | gate reports `blocked` | an unresolved finding must block |
| the same output | contains `Unresolved findings: F1` | the gate names what it blocks on |
| the same body with `RESOLVED:[F1]` | gate reports `ok` | a resolved finding must not block |
| the same body through the replaced extraction in `zsh` | 0 `FINDINGS:` matches | the interpreting route truncates at the backslash |
| `{"name":"a\nb","n":1}` | `.n` is `1`, `.name` is two lines | JSON escapes are data, not structure |
| the same payload through the interpreting route | the payload is lost | the replaced route corrupts it |

### Risk map coverage

- where a piped value enters the consuming command → the loop regression assertion
- argument splitting → the print-form matrix
- empty and bare echo → the empty/bare assertions
- fence-boundary detection → `no-interpreting-print.test.sh`
- the inline plugin-root resolver → `plugin-root-resolution.test.sh` scenario 7
- Every row mapped.

---

## Criterion 5: Normal output is unchanged. For a value with no escape and no control character, every converted site produces byte-identical output to its previous form, checked by diffing a run before and after on a representative settings file, PR and goal.

### Type

behavioral

### Verification command

```bash
bash plugins/flow/tests/run.sh print-line-integrity.test.sh
```

### Output

```
PASS replaced and replacement print forms agree byte for byte — the plain value prints identically through both forms
PASS replaced and replacement print forms agree byte for byte — the empty value prints identically through both forms
PASS replaced and replacement print forms agree byte for byte — the spaces value prints identically through both forms
PASS replaced and replacement print forms agree byte for byte — the glob-chars value prints identically through both forms
PASS replaced and replacement print forms agree byte for byte — the dashes value prints identically through both forms
PASS replaced and replacement print forms agree byte for byte — the percent value prints identically through both forms
PASS replaced and replacement print forms agree byte for byte — the unicode value prints identically through both forms
PASS replaced and replacement print forms agree byte for byte — an empty value is still one newline
PASS replaced and replacement print forms agree byte for byte — a bare print is still exactly one newline
PASS replaced and replacement print forms agree byte for byte — a value containing a space stays a single argument
PASS the replacement prints a backslash value byte for byte
PASS the backslash itself survives
PASS under a shell whose echo interprets, the two forms differ — which is the defect this work removes
SUMMARY pass=33 fail=0
```

Three further whole-tree checks were run, each comparing the branch against
`origin/main`:

| Check | Result |
|---|---|
| residue identity: each changed line with the print token removed from both sides | 1199 lines compared, 1199 identical, 0 unproved. Every one an exact byte comparison — no rewrite relocates anything, so removing `printf '%s\n'` and restoring `echo` reproduces the original line exactly. |
| syntax differential: every fenced block parse-checked with `bash -n` in both trees | 349 blocks in 50 files compared, 0 changed from parsing to failing or the reverse |
| plugin-root resolver: each embedded resolver executed in `bash` and `zsh` in both trees | 12 of 12 expressions resolve to the same value before and after |

The criterion asks for a diff of a run on a representative settings file, PR and
goal. The residue and syntax checks cover every changed line rather than one
representative run, which subsumes it; the instance repros under criterion 4 are
the executed before/after runs on a PR body and on a goal file.

### Visual analysis

none — criterion type behavioral has no visual surface

### Does NOT promise

- No claim for values **with** an escape or a control character — those are the class that is meant to differ, and the difference is asserted separately rather than hidden.
- No claim about output ordering or about commands whose behaviour depends on a network response.

### What was tested

That each replaced form and its replacement produce identical bytes for values
without escapes, and that the inverse transform reproduces every changed line
exactly.

### What was NOT tested

No end-to-end command run against a live `gh`. The residue check is textual; the
merged gate and producer checks are the executed behavioural evidence.

### Known limitations of this evidence

The residue check compares the branch against `origin/main` as it stood when this
bundle was produced; it is a one-time measurement, not a standing test. The
standing protection is the guard, which fails if the builtin returns.

### Negative/adversarial cases covered

A backslash-bearing value is deliberately excluded from the equivalence matrix
and asserted separately, because it is the one class that must differ. The test
fails if the two forms happen to agree on it, so the assertion cannot silently
become vacuous. Values with glob characters, leading dashes, a percent sign and
non-ASCII are included, since those are the shapes a careless rewrite would
mangle.

### Test inputs and expected values

| Input | Expected | Source of expected |
|---|---|---|
| `KEY=value` | both forms print identical bytes | the criterion: no-escape values are unchanged |
| `` (empty) | both forms print identical bytes | same |
| `a  b`, `*.ts {a,b}`, `-n -e`, `100% done`, `café — ünïcode` | both forms print identical bytes | same |
| `a\b` | the replacement preserves all bytes; the two forms differ under an interpreting shell | the defect being removed |
| `-n` as a bare argument | the replacement prints it; the replaced form swallows it | the one value class the two forms genuinely differ on |

The three whole-tree checks above are **one-time measurements**, not committed
tests: they compare this branch against the default branch as it stood when the
branch was cut, and they were run from a scratch directory. They are recorded as
evidence of the migration and are not reproducible from the repository, which is
why they are described here rather than listed as test rows. What stands in for
them going forward is the guard, which fails if the builtin returns.

### Risk map coverage

- argument splitting → the `spaces` matrix row, plus the single-argument assertion
- empty and bare echo → the empty and bare assertions
- where a piped value enters the consuming command → the loop regression assertion; the revert is recorded in `What changed` above
- the inline plugin-root resolver → the 12-of-12 resolver comparison, and `plugin-root-resolution.test.sh` scenario 7
- fence-boundary detection in the guard → `no-interpreting-print.test.sh`
- Every row mapped.
