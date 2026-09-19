---
issue: 235
created: '2026-09-19T16:40:00Z'
artifacts:
- type: specification
  captured_at: '2026-09-19T16:38:54Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: stranger-test
  captured_at: '2026-09-19T16:38:54Z'
  result: PASS
  task_count: 6
- type: workflow-run
  captured_at: '2026-09-19T16:39:46Z'
  workflow: start-issue
  run_id: 2026-09-19T163209Z-issue-235
  status: active
---

# Issue 235 — an interpreting builtin rewrites printed values

## Specification

_Captured by specification-capture skill on 2026-09-19. Source: extracted-from-issue._

### Non-goals

- Not a change to any command's decisions, thresholds, ordering, or output grammar. Every `KEY=` name, every line's meaning, and every value's content for values without escapes stays what it was.
- Not an encoding layer consumers must decode. The fix removes the interpretation rather than introducing an escape syntax for consumers to unescape. The one place a producer already promises a one-line scalar keeps its declared, documented collapse.
- Not input validation. No value is refused or rejected for carrying a backslash or a control character; the same bytes are printed literally instead of being rewritten.
- Not a general shell-portability pass over the plugin. Constructs unrelated to printing — arrays, `[[ ]]`, process substitution, GNU-versus-BSD flag drift — are untouched.

### Failure modes

- **Timeouts** — none. Nothing in this change makes a network or subprocess call whose latency it affects; a fence that already blocks on `gh` blocks identically before and after.
- **Partial failures** — a fence that fails partway (`gh` returns non-zero, a helper is absent) prints the same bytes before and after. The conversion never reorders statements and never moves a value's computation across the print that consumes it.
- **Invalid input** — a value carrying a backslash, a real newline, a carriage return, or a tab is printed literally, neither rewritten nor refused. The command's exit code and control flow are unchanged.
- **Missing context** — an unset variable or an absent helper prints exactly what it printed before. The conversion must not introduce `set -u` sensitivity where a fence did not have it: `printf '%s\n' "$V"` and `echo "$V"` fail together under `-u` and are equally quiet without it.

### Interface contracts

- Every fence-emitted diagnostic line keeps the form `KEY=value` on exactly one physical line; the set of keys is unchanged by this work.
- `plugins/flow/tests/run.sh <file.test.sh>` is the plugin's test entry point; a new `.test.sh` under `plugins/flow/tests/` is discovered automatically and must report through `_flow_test_summary` as `SUMMARY pass=N fail=N`.
- The producers named in the issue keep their existing CLI surfaces: `flow-active-goal.sh --id|--status|--path|--json|--ac-summary`, `flow-review-exceptions.sh --pr|--ref`, `flow-mine-corrections.sh`, and any other `bin/*.sh` that prints a `KEY=value` scalar.
- A value handed to `jq`, `grep`, or another parser arrives byte-identical; no filter is re-quoted or re-escaped to compensate for a print builtin. The delivered form for a piped value is `printf '%s\n' "$X" | CMD`, and the here-string alternative was reverted for the reason recorded under Verification.
- `printf '%s\n'` is the only print builtin used for an interpolated value, and its format string is a literal, so a `%` inside a value is inert.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| argument splitting | `echo`'s unquoted expansion is mechanically rewritten to `printf '%s\n' $V`, which prints one line per word where `echo` printed them space-joined on one line | `V="a b"` → right: one line `a b`; wrong: two lines `a`, `b` |
| empty and bare echo | `echo ""` is rewritten to a `printf` whose format is the empty string, emitting zero bytes where a blank separator line is expected | `echo "" \| wc -c` → right: `1` (one newline); wrong: `0` |
| where a piped value enters the consuming command | the value is relocated into a here-string on the pipeline's first command; when that command is a loop condition the redirect belongs to `read`, so the here-string is re-created every iteration and the loop reads its first line forever | a list of three elements piped into a `while read` loop → right: three iterations then exit 0; wrong: the first element repeats and the loop never returns. Measured: this hung a fence in `status.md` |
| the inline plugin-root resolver | the `;`-separated `{ … }` group loses a separator or a candidate when its `echo` becomes a `printf`, so the resolver stops printing `plugins/flow` first | `CLAUDE_PLUGIN_ROOT` unset, run the rewritten snippet in `bash` and `zsh` → right: first candidate is `plugins/flow`; wrong: syntax error or an empty first candidate |
| fence-boundary detection in the guard | the scanner's closing-marker match is too strict (or too loose), so it silently skips blocks and reports a clean tree it never read | a fixture with a ```` ```bash ```` block followed by a ```` ```! ```` block, each carrying an offender, and a closing marker with trailing whitespace → right: both offenders reported; wrong: the second block is never scanned |

## Stranger Test

PASS — 6 tasks reviewed.

## Verification

### What changed

Every fenced block in every markdown file of both plugins now prints with
`printf '%s\n'`. The change is 1199 lines across 49 files, and every one is a
token swap: `echo ARG` becomes `printf '%s\n' ARG` with the arguments re-emitted
verbatim, and one bare `echo` with no argument becomes `printf '\n'`. Nothing is
relocated, so no command's execution context changes.

A value piped into a parser keeps its pipe. The alternative — relocating the
value into a here-string on the pipeline's first command — was implemented
first and then reverted: when the first command is a loop condition, the
redirect belongs to `read` rather than to the loop, so the here-string is
re-created on every iteration and the loop reads its first line forever. In
`commands/status.md` that turned a loop over three runs into one that never
terminated. The full suite caught it by hanging, which is also why the
regression test added for it executes a loop rather than inspecting one.

### Criterion 1 — every print site safe by construction

`bash plugins/flow/tests/run.sh no-interpreting-print.test.sh` — the scan
reached 156 files, 435 fenced blocks and 7505 lines of them, and found 0
offenders. `bash plugins/dossier/tests/run.sh no-interpreting-print.test.sh` —
75 files, 98 blocks, 1024 lines, 0 offenders. Each scan reports the counts it
actually read, so a scan that matched nothing cannot be confused with a scan
that read nothing.

One deviation from the criterion's wording, since adjudicated in favour of what
shipped — see "Two criteria adjudicated by the issue's author" above. The
criterion says a value handed to a parser is "passed as arguments or through a
here-string, never echoed into a pipe". The prohibition is met — nothing is
echoed into a pipe. The form used for a piped value is a third one:
`printf '%s\n' "$X" | CMD`. The here-string form was implemented first and
reverted, because relocating the value changes where it enters the command and
hung a loop; see "What changed" above. The purpose the criterion exists for — the
value reaching the parser byte-identical — holds in both forms; only the
here-string form also changed execution context.

### Criterion 2 — the guard is demonstrated failing

The flow scan reports 952 offending lines on the pre-conversion tree and 0
after. The dossier scan reports 190 and 0.

The first version of the guard recognised only punctuation as a command opener,
and so read 53 real sites as arguments while reporting the tree clean: `case
"$x" in *) echo`, `if …; then echo`, `else echo`, `if echo … | jq`. Because the
same predicate drove the rewrite, guard and converter confirmed each other's
blind spot. With the predicate corrected, the same scan reports 952 where it
had reported 907 — 45 command sites the guard would have certified as clean.
Each opener now has its own fixture and turns the scan red.

Four offending shapes are injected and each is reported by line: settings-derived,
inlined-heredoc, helper-output, and JSON piped to a parser. A closing marker with
trailing whitespace, and a `bash`-tagged block immediately followed by a
`!`-tagged block, are both read; an unterminated block is reported rather than
truncated; a comment, a longer word and a quoted string are not offenders.

### Criterion 3 — producers emit exactly one line

A goal YAML whose `metadata.id` is a double-quoted scalar carrying `\n`, `\r`,
`\t` and a literal `\\n` is written to a fixture and read back through
`bin/flow-active-goal.sh --id`: one line in every case, with the forged key never
beginning a line of its own, and the real value surviving the collapse.

An earlier version of this test forged `lifecycle.status` instead. Selection
requires the status to be exactly `active`, so the fixture was never selected
and the test exercised nothing while appearing to pass.

### Criterion 4 — the three named instances

- The merge gate's extraction, taken verbatim from `commands/merge.md`, reports
  `LEDGER_GATE_STATE=blocked` for a review body whose finding location carries a
  backslash, and names the finding it is blocking on; the same body reports `ok`
  once the finding is resolved. The previous extraction form applied to the same
  body yields no findings at all, so the repro is a change in behaviour and not a
  coincidence of the fixture.
- A JSON payload carrying an escaped newline inside a string is read by `jq`
  through the here-string, and the interpreting route is shown losing the same
  payload.
- The goal-id forge is covered under criterion 3.

### Criterion 5 — normal output unchanged

Every changed line was compared against its pre-image from `origin/main`. The
residue — the line with the print token removed from each side — is identical
for all 1199, with 0 unproved. Every one is an exact byte comparison, because
no rewrite moves anything: removing `printf '%s\n'` from the new line and
putting `echo` back reproduces the original exactly.

The plugin-root resolver was run in `bash` and `zsh` in both trees: 12 of 12
expressions resolve to the same value before and after.

A matrix of values — empty, spaces, glob characters, leading dashes, a percent
sign, non-ASCII — prints byte-identically through the replaced and replacement
forms. A backslash-bearing value is deliberately excluded from that matrix and
asserted separately, because it is the one class that is meant to differ.

Every fenced block in the 50 changed files was also parse-checked with `bash -n`
in both trees: 349 blocks compared, 0 changed from parsing to failing or the
reverse. Bodies are fragments, so a failure is not by itself a defect — what the
comparison rules out is the rewrite introducing one.

### Two criteria adjudicated by the issue's author

An independent verdict pass returned PASS on criteria 2, 3 and 4, and referred
two to the issue's author as questions about the criteria rather than the code.
Both were put as explicit choices on 2026-09-19 and both were settled in favour
of what shipped:

- **Criterion 1** names "arguments or through a here-string" as the acceptable
  forms for a value handed to a parser. 170 sites ship a third form,
  `printf '%s\n' "$X" | CMD`. Adjudicated: accepted. The prohibition is met —
  nothing is echoed into a pipe — and the property the criterion exists for, the
  value reaching the parser byte-identical, holds and is asserted. The two named
  forms are examples, not an exhaustive list. The here-string form remains
  rejected on evidence: relocating the value hangs a loop whose condition reads
  from it, which is measured, not argued.
- **Criterion 5** is written as a universal over values with no escape and no
  control character, and a bare argument beginning with a dash breaks it: the
  replaced builtin read `-n` as its own flag and printed nothing, the replacement
  prints it. Adjudicated: accepted as a repair, not a change to normal output —
  the criterion's "unchanged" protects output that was correct, and a value that
  never reached the output was not. The divergence is also unreachable at every
  shipped site: all 15 bare-print sites print helper output beginning with a
  `KEY=` line.

Both decisions are recorded in the evidence bundle at the point the question
arises, so neither reads as an open question for the next reader.

### Found by executing the producers the criterion names

Criterion 3 asks that a helper emitting a scalar for embedding emit exactly one
line, and names three producers. This section previously said the two besides
`flow-active-goal.sh` "already emit one line each" — a claim made by reading
their source. Running them found the defect still live in both, and in a third
helper besides:

```
flow-mine-corrections.sh --format markdown --file $'probe\nFORGED=1'
  TRANSCRIPT_DIR=probe
  FORGED=1                          <- a forged field on stdout

flow-review-exceptions.sh --path $'probe\nFORGED=1' --repo x/y --ref main
  EXCEPTIONS_PATH=probe
  FORGED=1

flow-migrate-settings.sh, against a settings file holding a newline
  MIGRATE_FROM=requireGoalForStart=yes
  FORGED=1
```

The third is the closest to this issue's own premise: that value comes from a
tracked settings file, which a pull request author chooses. The miner also
forged from `HOME`, on both the roots list and the success path.

Each now folds the value onto one line with the treatment its sibling already
had — `flow-finding-route.sh` has carried a `safe()` for this since the class was
first fixed, and the Python half of `flow-review-exceptions.sh` already used one,
so the hole was only ever in the bash half. A control character becomes a space
rather than being deleted, so the halves stay visibly separate; nothing is
length-capped, because a truncated path would be the same fault, quieter.

Caught while making that change: the folding helper was placed below the argument
loop that first calls it, so an unknown argument reported `command not found`
instead of the message. Bash resolves function definitions in the order it reads
them. There is now an assertion for that too.

Each script has a regression test in its own suite and each was mutation-tested
by turning the folding back into a pass-through, which turns every forged-line
assertion red.

Census of the rest, since the criterion's catch-all names "any other `bin/*.sh`
printing metadata": five flow helpers emit `KEY=value` scalars and three are
covered above. `flow-finding-route.sh` builds its lists from input lines — which
cannot contain a newline — and from ids it validates against a literal character
class; `flow-quality-ledger.sh` emits a count; `flow-pr-linked-issue.sh` prints
through a parameter expansion that cannot introduce a newline; and
`flow-contract-files.sh` already routes values through its own `one_line`.

### Found by review, fixed here

**The dossier config resolver had the hole this issue is about.** An independent
pass found that `plugins/dossier/bin/cascade-resolve.sh` printed a resolved
settings value with no control-character check, while its flow twin has refused
those values since the class was first fixed. A tracked, pull-request-modifiable
`.claude/settings.dossier.json` carrying `"deliveryMode": "a\nFORGED=1"` produced
two lines — the value and a forged `FORGED=1` field. Reproduced before fixing
(2 lines), then fixed by porting the twin's refusal, which the file's own header
already claims it mirrors ("a byte-for-byte behavioural twin ... so a fix to the
cascade semantics in either plugin ports directly to the other"). Verified after:
refused with a named warning and the declared default, one line, exit 0; exit 2
with no default; `--allow-control-chars` still passes a multi-line value through;
an ordinary value unchanged. The escape hatch is now also forwarded by the
wrapper, which builds its own argument list and previously dropped it. A
regression test covers all four branches and was mutation-tested: disabling the
refusal turns it red on three assertions.

**Three defects in the new guards' own tests**, each found by mutation rather
than by reading:

- The consumer assertion wrote its fixture into one temp directory and read it
  back from another, so the read always failed on a missing file and the
  assertion could not fail. With the path fixed it failed immediately, on an
  assertion that was itself wrong: the forged text is present, collapsed onto
  one line. It now asserts the property that matters — the forged key never
  begins a line.
- The trailing-whitespace fixture did not discriminate: removing the tolerance
  from the scanner left the first block open, swallowed the rest of the file,
  and still counted two offenders. The block count and the absence of an anomaly
  are now asserted alongside it.
- The loop regression check passed vacuously if the path were wrong, because a
  scan that reads nothing reports the same zero an empty result does. It now
  asserts the file count it searched first, and joins continuation lines so a
  loop condition split across two lines is still matched.

**Two predicate gaps in the scanner**, both wider than the punctuation-only
version it started as: launcher words (`command`, `env`, `sudo`, `xargs`, `nice`
`nohup`, `exec`, `eval`, `time`) and assignment prefixes (`V=x echo`). Each has
its own fixture. Quoted spans are now blanked before the scan, so `echo` inside a
string is no longer a false positive; the one remaining false positive — a line
inside a heredoc body — is documented in the guard rather than left unstated.

**One divergence the equivalence claim must carry.** For a bare argument
beginning with a dash, the two forms genuinely differ: the replaced builtin reads
`-n` as its own flag and prints nothing, the replacement prints the value. The
direction is safe, and it is now pinned by an assertion in both directions rather
than left for a reader to discover.

### Residual risk

The guard does not inspect `bin/*.sh`, hooks, or markdown outside a fence. A
producer's own one-line contract is covered by `print-line-integrity.test.sh`
for the producers it names, not for every helper in the tree.

<!-- auto-log: 2026-09-19 18:38 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-235.md -->

<!-- auto-log: 2026-09-19 18:38 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235.md -->

<!-- auto-log: 2026-09-19 18:39 Write /Users/danielbentes/synapti-marketplace/.flow/goals/issue-235.goal.yaml -->

<!-- auto-log: 2026-09-19 18:39 Edit /Users/danielbentes/synapti-marketplace/.flow/goals/issue-235.goal.yaml -->

<!-- auto-log: 2026-09-19 18:39 Edit /Users/danielbentes/synapti-marketplace/.flow/goals/issue-235.goal.yaml -->

<!-- auto-log: 2026-09-19 18:40 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 18:40 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 18:40 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 18:40 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 18:41 Write /tmp/convert2.py -->

<!-- auto-log: 2026-09-19 18:42 Write /tmp/equiv.py -->

<!-- auto-log: 2026-09-19 18:42 Write /tmp/equiv2.py -->

<!-- auto-log: 2026-09-19 18:43 Write /tmp/equiv3.py -->

<!-- auto-log: 2026-09-19 18:53 Write /tmp/dip_header.txt -->

<!-- auto-log: 2026-09-19 18:53 Write /tmp/dip_mid.txt -->

<!-- auto-log: 2026-09-19 18:55 Write /tmp/print-line-integrity.test.sh -->

<!-- auto-log: 2026-09-19 18:57 Write /tmp/new_predicate.txt -->

<!-- auto-log: 2026-09-19 18:58 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 18:58 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 18:58 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 18:58 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 18:59 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/print-line-integrity.test.sh -->

<!-- auto-log: 2026-09-19 18:59 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/print-line-integrity.test.sh -->

<!-- auto-log: 2026-09-19 18:59 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/print-line-integrity.test.sh -->

<!-- auto-log: 2026-09-19 18:59 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/print-line-integrity.test.sh -->

<!-- auto-log: 2026-09-19 18:59 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/print-line-integrity.test.sh -->

<!-- auto-log: 2026-09-19 18:59 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/print-line-integrity.test.sh -->

<!-- auto-log: 2026-09-19 18:59 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/print-line-integrity.test.sh -->

<!-- auto-log: 2026-09-19 18:59 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/print-line-integrity.test.sh -->

<!-- auto-log: 2026-09-19 19:00 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235.md -->

<!-- auto-log: 2026-09-19 19:00 commit "fix(flow): print fence values with a builtin that does not interpret them" -->

<!-- auto-log: 2026-09-19 19:00 commit "fix(dossier): print fence values with a builtin that does not interpret them" -->

<!-- auto-log: 2026-09-19 19:01 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 19:01 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 19:01 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 19:01 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 19:01 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 19:01 Write /tmp/pr-body.md -->

<!-- auto-log: 2026-09-19 19:03 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235.md -->

<!-- auto-log: 2026-09-19 19:14 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/plugin-root-resolution.test.sh -->

<!-- auto-log: 2026-09-19 19:14 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/plugin-root-resolution.test.sh -->

<!-- auto-log: 2026-09-19 19:15 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/plugin-root-resolution.test.sh -->

<!-- auto-log: 2026-09-19 19:15 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235.md -->

<!-- auto-log: 2026-09-19 19:15 Edit /tmp/pr-body.md -->

<!-- auto-log: 2026-09-19 19:16 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/print-line-integrity.test.sh -->

<!-- auto-log: 2026-09-19 19:16 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/print-line-integrity.test.sh -->

<!-- auto-log: 2026-09-19 19:18 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/print-line-integrity.test.sh -->

<!-- auto-log: 2026-09-19 19:18 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235.md -->

<!-- auto-log: 2026-09-19 19:18 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235.md -->

<!-- auto-log: 2026-09-19 19:18 Write /tmp/pr-body.md -->

<!-- auto-log: 2026-09-19 19:19 Edit /Users/danielbentes/synapti-marketplace/.flow/goals/issue-235.goal.yaml -->

<!-- auto-log: 2026-09-19 19:19 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235.md -->

<!-- auto-log: 2026-09-19 19:19 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 19:19 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235.md -->

<!-- auto-log: 2026-09-19 19:21 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-235-evidence.md -->

<!-- auto-log: 2026-09-19 19:21 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235.md -->

<!-- auto-log: 2026-09-19 19:32 Write /tmp/patch_traps.py -->

<!-- auto-log: 2026-09-19 19:32 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 19:34 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/cascade-resolve.sh -->

<!-- auto-log: 2026-09-19 19:34 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/cascade-resolve.sh -->

<!-- auto-log: 2026-09-19 19:35 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/cascade-resolve.sh -->

<!-- auto-log: 2026-09-19 19:35 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/cascade-resolve.sh -->

<!-- auto-log: 2026-09-19 19:35 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/bin/dossier-resolve-config.sh -->

<!-- auto-log: 2026-09-19 19:35 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 19:36 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/print-line-integrity.test.sh -->

<!-- auto-log: 2026-09-19 19:36 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/print-line-integrity.test.sh -->

<!-- auto-log: 2026-09-19 19:36 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/print-line-integrity.test.sh -->

<!-- auto-log: 2026-09-19 19:36 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 19:36 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 19:36 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 19:36 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 19:37 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 19:37 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 19:37 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 19:37 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 19:37 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/print-line-integrity.test.sh -->

<!-- auto-log: 2026-09-19 19:37 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235.md -->

<!-- auto-log: 2026-09-19 19:37 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235-evidence.md -->

<!-- auto-log: 2026-09-19 19:39 Write /tmp/pr-body.md -->

<!-- auto-log: 2026-09-19 19:39 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235-evidence.md -->

<!-- auto-log: 2026-09-19 19:40 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235-evidence.md -->

<!-- auto-log: 2026-09-19 19:45 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 19:45 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 19:45 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 19:46 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 19:46 commit "test: state accurate opener counts in the guard comments" -->

<!-- auto-log: 2026-09-19 19:48 Write /tmp/hook-issue.md -->

<!-- auto-log: 2026-09-19 19:51 Edit /tmp/pr-body.md -->

<!-- auto-log: 2026-09-19 19:52 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235-evidence.md -->

<!-- auto-log: 2026-09-19 19:52 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235-evidence.md -->

<!-- auto-log: 2026-09-19 19:52 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235-evidence.md -->

<!-- auto-log: 2026-09-19 19:53 commit "docs(decisions): correct the evidence bundle's quoted test totals" -->

<!-- auto-log: 2026-09-19 19:56 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/print-line-integrity.test.sh -->

<!-- auto-log: 2026-09-19 19:56 Write /tmp/rep_before_after.py -->

<!-- auto-log: 2026-09-19 19:57 Write /tmp/rep2.py -->

<!-- auto-log: 2026-09-19 19:57 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235-evidence.md -->

<!-- auto-log: 2026-09-19 19:57 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235-evidence.md -->

<!-- auto-log: 2026-09-19 19:57 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235-evidence.md -->

<!-- auto-log: 2026-09-19 19:57 Edit /tmp/pr-body.md -->

<!-- auto-log: 2026-09-19 19:57 Edit /tmp/pr-body.md -->

<!-- auto-log: 2026-09-19 19:57 Edit /tmp/pr-body.md -->

<!-- auto-log: 2026-09-19 19:58 commit "test(flow): execute the goal-status forge instead of asserting it" -->

<!-- auto-log: 2026-09-19 19:58 Write /tmp/pr240-synapti-print-body.md -->

<!-- auto-log: 2026-09-19 19:59 Write /Users/danielbentes/.claude/projects/-Users-danielbentes-synapti-marketplace/memory/project_shared_tmp_collisions.md -->

<!-- auto-log: 2026-09-19 19:59 Edit /Users/danielbentes/.claude/projects/-Users-danielbentes-synapti-marketplace/memory/MEMORY.md -->

<!-- auto-log: 2026-09-19 20:02 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-mine-corrections.sh -->

<!-- auto-log: 2026-09-19 20:02 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-mine-corrections.sh -->

<!-- auto-log: 2026-09-19 20:02 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-mine-corrections.sh -->

<!-- auto-log: 2026-09-19 20:02 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-mine-corrections.sh -->

<!-- auto-log: 2026-09-19 20:03 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-mine-corrections.test.sh -->

<!-- auto-log: 2026-09-19 20:04 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-review-exceptions.sh -->

<!-- auto-log: 2026-09-19 20:04 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-migrate-settings.sh -->

<!-- auto-log: 2026-09-19 20:05 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/bin/flow-migrate-settings.sh -->

<!-- auto-log: 2026-09-19 20:05 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-migrate-settings.test.sh -->

<!-- auto-log: 2026-09-19 20:05 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/flow-migrate-settings.test.sh -->

<!-- auto-log: 2026-09-19 20:05 Edit /Users/danielbentes/synapti-marketplace/plugins/flow/tests/review-exceptions.test.sh -->

<!-- auto-log: 2026-09-19 20:06 commit "fix(flow): fold a caller-supplied value onto one line in every producer" -->

<!-- auto-log: 2026-09-19 20:06 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235-evidence.md -->

<!-- auto-log: 2026-09-19 20:06 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235-evidence.md -->

<!-- auto-log: 2026-09-19 20:06 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235-evidence.md -->

<!-- auto-log: 2026-09-19 20:07 Edit /Users/danielbentes/synapti-marketplace/plugins/dossier/tests/no-interpreting-print.test.sh -->

<!-- auto-log: 2026-09-19 20:08 commit "test(dossier): give the guard a shebang so shellcheck accepts it" -->

<!-- auto-log: 2026-09-19 20:09 Edit /tmp/pr240-synapti-print-body.md -->

<!-- auto-log: 2026-09-19 20:13 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235.md -->

<!-- auto-log: 2026-09-19 20:13 Edit /Users/danielbentes/synapti-marketplace/.flow/goals/issue-235.goal.yaml -->

<!-- auto-log: 2026-09-19 20:19 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235-evidence.md -->

<!-- auto-log: 2026-09-19 20:19 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235-evidence.md -->

<!-- auto-log: 2026-09-19 20:20 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235-evidence.md -->

<!-- auto-log: 2026-09-19 20:20 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235-evidence.md -->

<!-- auto-log: 2026-09-19 20:21 commit "docs(decisions): display the assertions the verdict judge found missing" -->

<!-- auto-log: 2026-09-19 20:52 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235-evidence.md -->

<!-- auto-log: 2026-09-19 20:52 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235-evidence.md -->

<!-- auto-log: 2026-09-19 20:52 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235.md -->

<!-- auto-log: 2026-09-19 20:53 commit "docs(decisions): record the two adjudicated criteria" -->

<!-- auto-log: 2026-09-19 20:53 Edit /Users/danielbentes/synapti-marketplace/.decisions/issue-235.md -->
