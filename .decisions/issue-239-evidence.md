# Evidence Bundle — Issue #239

**Branch:** fix/issue-239-force-push-guard-scope
**Generated:** 2026-09-19
**Acceptance criteria source:** issue #239 body, `## Acceptance Criteria` — the five
criteria below reproduce that section's text.
**Total criteria:** 5

The hook under test is `plugins/flow/hooks/scripts/block-force-push.sh`; every case
runs against the file as it stands on this branch. The suite is
`plugins/flow/tests/run.sh block-force-push.test.sh`: **85 assertions, 47 of them
asserting a block and 21 asserting an allow**, the rest asserting exit codes and the
refusal message. Its baseline before any mutation is **0 cases red**.

---

## Criterion 1: A push followed on the same line by an unrelated command carrying `-f` or `--force` is allowed.

### Type

behavioral

### Verification command

```bash
bash plugins/flow/tests/run.sh block-force-push.test.sh
```

### Output

```
allowed: git push origin main && pgrep -f 'dossier/tests/run.sh'
allowed: git push && grep -f patterns.txt file
allowed: pgrep -f 'something' && git push origin main
allowed: git status && pgrep -f x
allowed: rm -f /tmp/scratch
allowed: git branch -f other main
SUMMARY pass=85 fail=0
```

The first case is the reported defect verbatim: it was refused by the previous
implementation and is allowed by this one.

### Visual analysis

none — criterion type behavioral has no visual surface

### Does NOT promise

- No change of policy: a force flag that really belongs to the push is still blocked (criterion 2).
- No relaxation for a push whose own arguments end before a later command's flag: `git push origin main && pgrep -f x` is one push and one other command.

### What was tested

That the hook's exit code is 0 for a command holding a push and a later command
that carries a force flag.

### What was NOT tested

The hook is exercised by feeding it stdin directly, so this establishes the hook's
own decision and not the harness's use of it.

### Known limitations of this evidence

The cases are the shapes the reporter observed plus their neighbours. A launcher
or keyword combination not listed may still over-block; the guard is built to fail
closed, so that risk is a refused command rather than a missed one.

### Negative/adversarial cases covered

Both orders are covered — the flag-bearing command before and after the push — and
the flag belongs to a real command (`pgrep -f`, `grep -f`, `rm -f`, `git branch -f`),
not a contrived token.

### Test inputs and expected values

| Input | Expected | Source of expected |
|---|---|---|
| `git push origin main && pgrep -f 'dossier/tests/run.sh'` | allowed | the issue's Current State names this command as the one wrongly refused |
| `git push && grep -f patterns.txt file` | allowed | a `-f` belonging to grep |
| `pgrep -f 'something' && git push origin main` | allowed | the same, with the flag before the push |
| `git status && pgrep -f x` | allowed | no push at all on the line |
| `rm -f /tmp/scratch` | allowed | a force flag on a command that is not a push |
| `git branch -f other main` | allowed | a force flag on a different git subcommand |

### Risk map coverage

- `-f` as another command's flag → the six cases above
- where a push's own arguments end → `git push origin main # -f` (a comment is prose)
- splitting the line into commands → `grep -q 'x ; git push --force' file` (criterion 4)

---

## Criterion 2: A push that itself carries `-f` or `--force` is still blocked — including after a separator (`cmd && git push --force`), inside a compound command, and with the flag written as its own word.

### Type

behavioral

### Verification command

```bash
bash plugins/flow/tests/run.sh block-force-push.test.sh
```

### Output

```
blocked: git push --force origin main
blocked: git status && git push --force
blocked: { git push --force; }
blocked: git push origin main -f
blocked: git push --force-with-lease --force
blocked: git push -f
blocked: sudo git push --force origin main
blocked: if git push --force; then :; fi
blocked: git -C repo push --force
blocked: GIT_DIR=x git push --force
blocked: git push '--force'
blocked: git push "-f"
blocked: git push --forc''e
blocked: git push $'--force' origin main
blocked: git push origin +main:main
SUMMARY pass=85 fail=0
```

### Visual analysis

none — criterion type behavioral has no visual surface

### Does NOT promise

- No claim to parse shell syntax. Expansion, aliases and functions are out of scope; a force flag reaching git through a variable (`F=--force; git push $F`) is not detected, and is named under Known limitations.
- No change to the refusal message, which keeps its three lines verbatim (asserted under its own group).

### What was tested

That the hook exits 2 for each shape a force flag can take on a push: as its own
word, attached to a ref list, after a separator, inside a compound command, behind
a launcher word, behind a shell keyword, behind `git`'s own global options, and
written through four kinds of quoting.

### What was NOT tested

A force flag assembled at run time is invisible to the guard. The previous
implementation did not detect it either, so this is unchanged behaviour rather
than a regression, and it is the boundary the non-goals name.

### Known limitations of this evidence

The word reader models quotes and backslash escapes but not command substitution
or variable expansion, so a flag built at run time is not seen.

### Negative/adversarial cases covered

The flag appears as a separate word, attached to a ref list, after a separator,
inside a compound command, behind a launcher, behind a shell keyword, behind
`git`'s global options, and quoted four ways — including ANSI-C quoting, where the
shell's own expansion is what turns `$'--force'` into a flag.

### Test inputs and expected values

| Input | Expected | Source of expected |
|---|---|---|
| `git push --force origin main` | blocked | the criterion |
| `git status && git push --force` | blocked | "after a separator" |
| `{ git push --force; }` | blocked | "inside a compound command" |
| `git push origin main -f` | blocked | "the flag written as its own word" |
| `git -C repo push --force` | blocked | a real force-push; `git` takes global options before its subcommand |
| `if git push --force; then :; fi` | blocked | "inside a compound command" |
| `git push '--force'`, `git push "-f"`, `git push --forc''e` | blocked | a quoted flag is still a flag |
| `git push $'--force' origin main` | blocked | ANSI-C quoting yields the same word |
| `git push origin +main:main` | blocked | a `+refspec` is git's other spelling of a forced update |

### Risk map coverage

- where a push's own arguments end → `git push origin main` (allowed) beside `git push origin main -f` (blocked)
- the `-f` word boundary → `git push origin --force-with-lease` under criterion 3
- finding the command word → `/usr/bin/git push --force`, `bash -c "git push --force"`, `eval "git push --force"`
- a launcher's own options → `sudo -u root git push --force`, `timeout 10 git push --force`
- advancing past a separator → `true;git push --force` and its four siblings

---

## Criterion 3: `--force-with-lease` alone stays allowed; `--force-with-lease --force` stays blocked.

### Type

behavioral

### Verification command

```bash
bash plugins/flow/tests/run.sh block-force-push.test.sh
```

### Output

```
allowed: git push --force-with-lease origin main
allowed: git push origin --force-with-lease
blocked: git push --force-with-lease --force
SUMMARY pass=85 fail=0
```

The flag is compared as a whole word rather than as a pattern prefix. The previous
implementation deleted every `--force-with-lease` from the line first, because its
`--force\b` pattern matched that flag's own prefix — a workaround a word comparison
does not need.

### Visual analysis

none — criterion type behavioral has no visual surface

### Does NOT promise

- No claim about `--force-if-includes` or other lease-adjacent flags; they are not recognised as force flags and are not the safe alternative the message names.

### What was tested

That the lease form is allowed alone, in either position a push accepts it, and
blocked when a plain force flag also appears.

### What was NOT tested

Combinations beyond those three.

### Known limitations of this evidence

None beyond the general non-goals.

### Negative/adversarial cases covered

The blocked case puts the plain flag *after* the lease form, which is the order a
prefix-matching guard would let through.

### Test inputs and expected values

| Input | Expected | Source of expected |
|---|---|---|
| `git push --force-with-lease origin main` | allowed | the criterion |
| `git push origin --force-with-lease` | allowed | the same flag in the other position a push accepts it |
| `git push --force-with-lease --force` | blocked | the criterion; a plain force flag is present |

### Risk map coverage

- the `-f` word boundary → all three cases above

---

## Criterion 4: A command whose *text* mentions the flags but which invokes neither is allowed, so writing documentation or an issue about them is not blocked.

### Type

behavioral

### Verification command

```bash
bash plugins/flow/tests/run.sh block-force-push.test.sh
```

### Output

```
allowed: gh issue create --body 'git push --force is blocked'
allowed: printf '%s\n' 'never run git push -f'
allowed: echo 'git push --force'
allowed: cat > notes.md <<'EOF' (writing git push --force into a file)
allowed: grep -q 'x ; git push --force' file
allowed: git push origin main # -f
allowed: echo 'git push'
allowed: printf '%s\n' "git push -f"
allowed: echo git push --force
allowed: grep -q 'git push --force' notes.md
allowed: gh issue create --body "notes (a quoted string spanning three lines)
SUMMARY pass=85 fail=0
```

The first case is the second reported occurrence: filing this issue was itself
refused as a force-push, because the body described the flags.

### Visual analysis

none — criterion type behavioral has no visual surface

### Does NOT promise

- No claim to distinguish a heredoc whose delimiter is generated rather than literal.

### What was tested

That text naming the flags is allowed across five routes: quoted arguments, a
heredoc body, a comment, a separator inside a quoted string, and a quoted string
that spans lines.

### What was NOT tested

A heredoc whose terminator creates a desync it survives; that shape is covered
from the other direction under criterion 5's heredoc group, where it must block.

### Known limitations of this evidence

Heredoc handling is line-based and does not model a delimiter appearing inside a
nested heredoc.

### Negative/adversarial cases covered

The reverse direction is asserted too — `echo 'git push'`, `echo git push --force`,
`printf '%s\n' "git push -f"` — which is what stops the guard from growing a
wrapper-tolerance by scanning for `git` anywhere on the line.

### Test inputs and expected values

| Input | Expected | Source of expected |
|---|---|---|
| `gh issue create --body 'git push --force is blocked'` | allowed | the issue's second reported occurrence |
| `printf '%s\n' 'never run git push -f'` | allowed | text, not a command |
| `echo 'git push --force'` | allowed | text, not a command |
| `cat > notes.md <<'EOF' … EOF` | allowed | a heredoc body is written to a file, not run |
| `grep -q 'x ; git push --force' file` | allowed | a separator inside a quoted string starts nothing |
| `git push origin main # -f` | allowed | a comment is prose about the command |
| `echo 'git push'`, `echo git push --force` | allowed | the command word is `echo`; `git` is its argument |
| `gh issue create --body "notes … end"` | allowed | a quoted string spanning lines is one argument to one command |

### Risk map coverage

- a heredoc body → the heredoc case here, and the desync cases under criterion 5
- splitting the line into commands → the quoted-separator case
- command position → the four `echo`/`grep` cases

---

## Criterion 5: A test covers each case above, and its coverage is demonstrated by reverting the detection to the current pattern and confirming each case turns red.

### Type

behavioral

### Verification command

```bash
bash plugins/flow/tests/run.sh block-force-push.test.sh   # with each mutation applied
```

### Output

Six mutations, each applied to the hook in place with the suite re-run against
it. Baseline before each: **0 cases red.**

**A — the detection reverted to the whole-line pattern the issue quotes.** 17 cases
red, including the two reported occurrences and `echo git push --force`. Nine are
false positives. Two are **under-blocks**, which cuts against the issue's own
framing: the issue calls the old pattern "safe — it over-blocks rather than
under-blocks", but `git -C repo push --force` and `git push --forc''e` both pass
it, because it requires `push` immediately after `git` and needs a word boundary
after `--force`. Both are real force-pushes. The assessment holds for the two
occurrences the issue reports, not for the pattern in general.

**B — a separator advances two characters.** 6 cases red — the one-character
separators (`;`, `|`, `&`, `(`, `)`) and `echo $(git push --force)`. This was a
defect in this fix's own first attempt, found by probing the direction its tests
did not cover; it is now pinned by its own test group.

**C — `git`'s global options not stepped over.** 1 case red: `git -C repo push --force`.
`git --git-dir=.git push -f` stays green under this mutant, because that option's
value is attached and one skip reaches `push`; only the separate-value form needs
the two-word step.

**D — a launcher's options not stepped over.** 1 case red: `timeout 10 git push --force`.

**E — the heredoc delimiter keeps its metacharacter and `<<<` opens a body.** 1 case
red: a command the shell would refuse to run, where the mutant reads a later line
as a terminator and reports the body as text. Before the case was added, this
mutation passed the suite unchanged — which is the finding that the "pathological
command" group asserts only the exit code, and so cannot see a heredoc desync.

**F — the command word compared whole rather than by basename.** 2 cases red:
`/usr/bin/git push --force` and `sudo /usr/bin/git push --force`, both of which the
mutant allows. This is the risk-map row for finding the command word; the first
attempt at this mutation also rewrote the helper's own definition, which made awk
bail out — and an awk that bails exits 2, so the broken mutant looked like a
working block. Re-applied to the call sites only, it behaves as the row predicts.

### Visual analysis

none — criterion type behavioral has no visual surface

### Does NOT promise

- No claim that the suite enumerates every shape; it covers both directions and the shapes each mutation exposes.

### What was tested

That the suite goes red under each of six mutations, in both directions: A turns
allow-cases red, B through F turn block-cases red.

### What was NOT tested

The mutations were applied by hand; there is no permanent mutation-testing harness
for this hook, so the counts are not reproducible by a command in the repository.

### Known limitations of this evidence

All six mutation results are one-time measurements taken on 2026-09-19 against the
hook as it stands on this branch. The scripts that produced them are not in the
repository.

### Negative/adversarial cases covered

The suite asserts both directions — 47 cases expecting a block and 21 expecting an
allow — so a hook that always blocks and a hook that always allows each fail it.
Mutation A confirms this empirically: the same mutant turns both an allow-case and
a block-case red. A 3000-input fuzz sample (seeded, mixing tokens from a shell
vocabulary with random punctuation) produced only exits 0 and 2, so no input makes
the hook exit with a code the harness would read as an allow.

### Test inputs and expected values

| Input | Expected | Source of expected |
|---|---|---|
| the suite with the detection reverted to the whole-line pattern | at least 17 failures | each case names the behaviour it expects |
| the suite with a two-character separator advance | at least 6 failures | the separator group names the behaviour |
| the suite with the global-option step removed | at least 1 failure | the `git -C repo push` case names it |
| the suite with the launcher-option step removed | at least 1 failure | the `timeout 10 git push` case names it |
| the suite with the heredoc delimiter keeping its metacharacter | at least 1 failure | the fail-closed heredoc case names it |
| the suite with the command word compared whole rather than by basename | at least 2 failures | the path-qualified cases name it |

### Risk map coverage

Every row of the risk map has at least one assertion, and the six mutations
demonstrate that those assertions can fail:

- splitting the line into commands → `grep -q 'x ; git push --force' file`
- where a push's own arguments end → `git push origin main # -f`
- the `-f` word boundary → `git push origin --force-with-lease`
- a heredoc body → the write-a-file case, and the desync cases
- `-f` as another command's flag → the six cases under criterion 1
- advancing past a separator → the separator group (mutation B)
- a launcher's own options → the launcher group (mutation D)
- finding the command word → the path-qualified cases (mutation F), plus `sh -c` and `eval`
- command position → `echo git push --force` and its three siblings

---

## Runtime verification

The hook is a shell script a hook runner invokes per tool call, so its runtime
surface is the process: exit code, and what it writes to each stream.

| Step | Command | Result |
|---|---|---|
| Suite | `bash plugins/flow/tests/run.sh block-force-push.test.sh` | 85 pass, 0 fail |
| Whole flow suite | `bash plugins/flow/tests/run.sh` | 4727 pass, 0 fail, 69 files |
| Windows hook smoke | `bash plugins/flow/tests/windows-hooks-smoke.sh` | 56 passed, 0 failed |
| Fuzz | 3000 generated commands | exits 0 and 2 only |
| Pathological set | unterminated heredoc, 999 backslashes, invalid UTF-8, CRLF, 20 000-character token | no crash, no hang |
| Cost | 100 KB command / 128 KB (the cap) | 0.70 s / 1.04 s; over the cap, blocks in ~70 ms |

Every line above is from the tree as it stands on this branch: the whole-suite run
is the one taken after the last change to the hook and its test.

## Out-of-scope finding, filed separately

`block-secrets.sh` shares this defect class: it scans the whole command line, so it
refuses `gh issue create --body "the token=X was committed"`, `grep -rn "secret=X"
docs/` and `git commit -m "rotate password=X"`. All five such cases were measured
returning exit 2, alongside three real inline secrets it correctly blocks. It is
not fixed here: narrowing a security guard's false-positive policy is a decision
with a different blast radius from a push-flag fix, and the guard has no test file
of its own to hold a change to. It is filed as issue #241.
