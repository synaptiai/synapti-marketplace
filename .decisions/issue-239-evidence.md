# Evidence Bundle — Issue #239

**Branch:** fix/issue-239-force-push-guard-scope
**Generated:** 2026-09-19
**Acceptance criteria source:** issue #239 body, `## Acceptance Criteria` — the five
criteria below reproduce that section's text.
**Total criteria:** 5

The hook under test is `plugins/flow/hooks/scripts/block-force-push.sh`; every case
runs against the file as it stands on this branch. The suite is
`plugins/flow/tests/run.sh block-force-push.test.sh`: **119 assertions, 75 of them
asserting a block and 27 asserting an allow**, the rest asserting exit codes and the
refusal message. Its baseline before any mutation is **0 cases red**.

The guard blocks by default and allows only what it can positively account for. The
accounting is what the criteria below test; the design, and the two earlier designs
that this one replaces, are recorded in `.decisions/issue-239.md`.

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
SUMMARY pass=103 fail=0
```

The first case is the reported defect verbatim: it was refused by the whole-line scan
this branch replaces and is allowed here.

### Visual analysis

none — criterion type behavioral has no visual surface

### Does NOT promise

- No change of policy: a force flag that really belongs to the push is still blocked (criterion 2).
- No claim that any `-f` anywhere is fine. The flag is allowed because the command carrying it cannot execute its arguments; `git push origin main && timeout 10 git push --force` is still blocked, via the second push.

### What was tested

That the hook's exit code is 0 for a command holding a push and a later command that
carries a force flag, for four different flag-bearing commands.

### What was NOT tested

The hook is exercised by feeding it stdin directly, so this establishes the hook's own
decision and not the harness's use of it.

### Known limitations of this evidence

The cases are the shapes the reporter observed plus their neighbours. A command the
cannot-execute list does not name blocks rather than allows, so the residual risk in
this direction is a refused command, not a missed force-push.

### Negative/adversarial cases covered

Both orders are covered — the flag-bearing command before and after the push — and the
flag belongs to a real command (`pgrep -f`, `grep -f`, `rm -f`, `git branch -f`), not a
contrived token. `git branch -f other main` is covered specifically because `git` is not
on the cannot-execute list: the command is allowed only because it runs no push.

### Test inputs and expected values

| Input | Expected | Source of expected |
|---|---|---|
| `git push origin main && pgrep -f 'dossier/tests/run.sh'` | allowed | the issue's Current State names this command as the one wrongly refused |
| `git push && grep -f patterns.txt file` | allowed | a `-f` belonging to grep, which cannot run a command |
| `pgrep -f 'something' && git push origin main` | allowed | the same, with the flag before the push |
| `git status && pgrep -f x` | allowed | no push at all on the line |
| `rm -f /tmp/scratch` | allowed | a force flag on a command that is not a push |
| `git branch -f other main` | allowed | a force flag on a git subcommand that is not `push` |

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
SUMMARY pass=103 fail=0
```

### Visual analysis

none — criterion type behavioral has no visual surface

### Does NOT promise

- No claim to have decoded every spelling a flag can be written in. ANSI-C escapes that change the command word, and brace expansion, are not decoded; a line carrying them blocks rather than being guessed at.
- No change to the refusal message, which keeps its three lines verbatim (asserted under its own group).

### What was tested

That the hook exits 2 for each shape a force flag can take on a push: as its own word,
attached to a ref list, after a separator, inside a compound command, behind a launcher,
behind a shell keyword, behind `git`'s own global options, quoted four ways, and as a
`+` refspec.

### What was NOT tested

A command word assembled from an expansion — `eval $'\x67it push --force'` — is not
decoded. It blocks, because the line carries a substitution, but it is not recognised:
the refusal comes from the guard refusing to vouch for the line, not from reading the
command.

### Known limitations of this evidence

The guard does not model expansion. Where an expansion could produce a command, the line
is refused rather than interpreted.

### Negative/adversarial cases covered

The flag appears as a separate word, attached to a ref list, after a separator, inside a
compound command, behind a launcher, behind a shell keyword, behind `git`'s global
options, and quoted four ways.

### Test inputs and expected values

| Input | Expected | Source of expected |
|---|---|---|
| `git push --force origin main` | blocked | the criterion |
| `git status && git push --force` | blocked | "after a separator" |
| `{ git push --force; }` | blocked | "inside a compound command" |
| `git push origin main -f` | blocked | "the flag written as its own word" |
| `git -C repo push --force` | blocked | a real force-push; the guard looks for `push` among the words, so `git`'s global options do not hide it |
| `if git push --force; then :; fi` | blocked | "inside a compound command" |
| `git push '--force'`, `git push "-f"`, `git push --forc''e` | blocked | a quoted flag is still a flag |
| `git push $'--force' origin main` | blocked | ANSI-C quoting is not decoded, so the line is refused |
| `git push origin +main:main` | blocked | a `+` refspec is the other spelling of a forced update |

### Risk map coverage

- the `-f` word boundary → `git push origin --force-with-lease` under criterion 3
- a force flag inside a quoted span → `gh issue create --body 'git push --force'` (allowed) beside `git push '--force'` (blocked)
- which commands can execute their arguments → `caffeinate git push --force`, `timeout 10 git push --force`

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
SUMMARY pass=103 fail=0
```

The flag is compared as a whole word rather than as a pattern prefix, so no workaround
is needed to stop it matching its own prefix — the whole-line scan it replaces had to
delete every `--force-with-lease` from the line first, for exactly that reason.

### Visual analysis

none — criterion type behavioral has no visual surface

### Does NOT promise

- No claim about `--force-if-includes` or other lease-adjacent flags; they are not recognised as force flags and are not the safe alternative the message names.

### What was tested

That the lease form is allowed alone, in either position a push accepts it, and blocked
when a plain force flag also appears.

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
allowed: cat > notes.md <<'EOF' (writing the flags into a file)
allowed: grep -q 'x ; git push --force' file
allowed: git push origin main # -f
allowed: echo 'git push'
allowed: printf '%s\n' "git push -f"
allowed: echo git push --force
allowed: grep -q 'git push --force' notes.md
allowed: gh issue create --body "notes (a quoted string spanning three lines)
SUMMARY pass=103 fail=0
```

The first case is the second reported occurrence: filing this issue was itself refused
as a force-push, because the body described the flags.

### Visual analysis

none — criterion type behavioral has no visual surface

### Does NOT promise

- No claim to know which heredoc bodies are text and which are scripts by syntax. The consumer decides: `cat > f <<EOF` writes text, `bash <<EOF` runs a script, and the second blocks.

### What was tested

That text naming the flags is allowed across five routes: a quoted argument, a heredoc
body written by a non-interpreting command, a comment, a separator inside a quoted
string, and a quoted string spanning lines.

### What was NOT tested

A heredoc whose consumer is on the cannot-execute list but whose body is nonetheless
executed. None is known; the list is drawn to contain no such command.

### Known limitations of this evidence

The guard decides by command word, so a command it does not name is treated as one that
might execute its input. That is the safe direction, and it is why the two reported
shapes are covered by names rather than by parsing.

### Negative/adversarial cases covered

The reverse direction is asserted too — `echo 'git push'`, `echo git push --force`,
`printf '%s\n' "git push -f"` — which stops the guard from allowing a line by treating
`git` as a name like any other.

### Test inputs and expected values

| Input | Expected | Source of expected |
|---|---|---|
| `gh issue create --body 'git push --force is blocked'` | allowed | the issue's second reported occurrence |
| `printf '%s\n' 'never run git push -f'` | allowed | text, not a command |
| `echo 'git push --force'` | allowed | text, not a command |
| `cat > notes.md <<'EOF' … EOF` | allowed | a heredoc body written by `cat` is text |
| `grep -q 'x ; git push --force' file` | allowed | a separator inside a quoted string starts nothing |
| `git push origin main # -f` | allowed | a comment is prose about the command |
| `echo 'git push'`, `echo git push --force` | allowed | `echo` cannot execute its arguments, so the push is text |
| `gh issue create --body "notes … end"` | allowed | a quoted string spanning lines is one argument to one command |

### Risk map coverage

- a heredoc body → the write-a-file case here, and `bash <<EOF` under the blocks below
- splitting the line into commands → the quoted-separator case
- a force flag inside a quoted span → the `gh` and `grep` cases

---

## Criterion 5: A test covers each case above, and its coverage is demonstrated by reverting the detection to the current pattern and confirming each case turns red.

### Type

behavioral

### Verification command

```bash
bash plugins/flow/tests/run.sh block-force-push.test.sh   # with each mutation applied
```

### Output

Six mutations, each applied to the hook in place with the suite re-run against it.
Baseline before each: **0 cases red.**

| Mutation | Cases red |
|---|---|
| A — no decision at all (allow everything) | 80 |
| B — every command word treated as able to execute | 29 |
| C — the `risky` term dropped from the floor | 27 |
| D — the raw-text force-flag check dropped | 6 |
| E — the quoted-substitution check dropped | 1 |
| F — detection reverted to the previous whole-line pattern | 27 |

**A** is the degenerate case: a guard that always allows fails 80 assertions, so the
suite is not passing by accident.

**B** and **C** are the design's two central decisions — the cannot-execute list, and
the catch-all that blocks an unattributable flag when the floor has fired. Each is
load-bearing: removing either turns over 25 cases red.

**D** is the check that finds a force flag grouped inside a quoted argument. Without it
the `gh issue create --body '…'` shape is not seen, and six cases that require the guard
to have noticed the flag turn red.

**E** turns exactly one case red, which is the honest result: before that case existed,
the mutation passed the whole suite. It was found by running the mutation, not by
reading the code, and the case was added because of it.

**F** reverts to the whole-line scan this branch replaces and turns 18 red — the two
reported shapes among them.

### Visual analysis

none — criterion type behavioral has no visual surface

### Does NOT promise

- No claim that the suite enumerates every shape; it covers both directions and the shapes each mutation exposes.
- No claim that mutation E is well covered: one case is a thin margin, and it is reported as such.

### What was tested

That the suite goes red under each of six mutations, in both directions.

### What was NOT tested

The mutations were applied by hand; there is no permanent mutation-testing harness for
this hook, so the counts are not reproducible by a command in the repository.

### Known limitations of this evidence

All six mutation results are one-time measurements taken on 2026-09-19 against the hook
as it stands on this branch. The scripts that produced them are not in the repository,
and two of them (E and F) initially failed to apply at all — a reminder that a mutation
report is only as good as the mutant.

### Negative/adversarial cases covered

The suite asserts both directions — 75 cases expecting a block and 27 expecting an allow
— so a hook that always blocks and a hook that always allows each fail it. A 3000-input
fuzz sample produced only exits 0 and 2, so no input makes the hook exit with a code the
harness would read as an allow.

### Test inputs and expected values

| Input | Expected | Source of expected |
|---|---|---|
| no decision at all | at least 80 failures | each case names the behaviour it expects |
| every command word treated as executing | at least 29 failures | the accounted-for cases name it |
| the `risky` term dropped | at least 27 failures | the wrapper and heredoc groups name it |
| the raw-text check dropped | at least 6 failures | the quoted-text cases name it |
| the quoted-substitution check dropped | at least 1 failure | the quoted-backtick case names it |
| detection reverted to the whole-line pattern | at least 27 failures | the two reported shapes name it |

### Risk map coverage

Every row of the risk map has at least one assertion, and the six mutations demonstrate
that those assertions can fail:

- splitting the line into commands → `grep -q 'x ; git push --force' file`
- where a push's own arguments end → `git push origin main # -f`
- the `-f` word boundary → `git push origin --force-with-lease`
- a heredoc body → the write-a-file case beside `bash <<EOF`
- `-f` as another command's flag → the six cases under criterion 1
- which commands can execute their arguments → the wrapper group (mutation C),
  including `sort --compress-program`, which runs the program it names
- a substitution inside double quotes → the substitution group (mutation E)
- a force flag inside a quoted span → the quoted-text cases (mutation D)
- detecting the floor → the arithmetic `<<` case, and mutation B
- the exit contract → the pathological group, and the stubbed-`awk` check below

---

## Runtime verification

The hook is a shell script a hook runner invokes per tool call, so its runtime surface is
the process: exit code, and what it writes to each stream.

| Step | Command | Result |
|---|---|---|
| Suite | `bash plugins/flow/tests/run.sh block-force-push.test.sh` | 119 pass, 0 fail |
| Whole flow suite | `bash plugins/flow/tests/run.sh` | 4745 pass, 0 fail, 69 files |
| Windows hook smoke | `bash plugins/flow/tests/windows-hooks-smoke.sh` | 56 passed, 0 failed |
| Fuzz | 3000 generated commands | exits 0 and 2 only |
| Pathological set | unterminated heredoc, 999 backslashes, invalid UTF-8, CRLF, 20 000-character token | no crash, no hang |
| Cost | 100 KB / 131 KB (the cap) | 0.70 s / 1.04 s; over the cap, blocks in ~55 ms |
| Cost, worst measured | 130 000-character chain of `eval` words | 1.1 s |
| Cost, multi-byte | 131 072 CJK characters (393 KB) | refused in 73 ms, by the byte cap |

Every line is from the tree as it stands on this branch. The stub-`awk` check below is
the one runtime path a passing suite would not otherwise exercise.

| Hostile runtime step | Result |
|---|---|
| `awk` stubbed to exit 1 while the command force-pushes | blocked, exit 2 |
| `awk` stubbed to print nothing (empty verdict) | blocked, exit 2 |
| payload carrying no command string (`{}`, null, a number) | blocked, exit 2 |
| `jq` absent, `awk` absent, `cat` absent, `grep` absent | blocked, exit 2 |

## What was tried before this design

Two earlier versions of this fix were reviewed and rejected, and both failures are worth
recording because they are the reason the shipped design looks the way it does.

**The whole-line scan** is what the issue reports: it reads any `-f` after a push as the
push's own. It is safe in the sense the issue gives it — it over-blocks — but that is
not true in general. Reverting to it turns up two *under*-blocks as well: it requires
`push` immediately after `git`, so `git -C repo push --force` escapes it, and it needs a
word boundary after `--force`, so `git push --forc''e` escapes it too.

**A parser that decided on the invocation's own arguments** replaced it, and was found
by security review to under-block in sixteen measured shapes — command substitution
inside quotes and backticks, wrappers that were not on its launcher list, a path-qualified
launcher, clustered `-c`, an interpreter heredoc, and arithmetic `<<` confusing the
heredoc tracker. Each was a real force-push that `main` blocked. The design's fault was
structural: it tried to decide *is this a force push?*, which requires knowing whether
the enclosing command interprets its argument as a command, and `gh issue create --body
'…'` and `bash -lc '…'` are the same shape needing opposite answers.

**A second review then found the first version of the inverted design had made the
same mistake in a subtler place.** The accounting was gated behind the floor, so it was
inert exactly when it was needed — on a line where the floor's pattern did not match,
which is what an expansion or a redirect produces. `$(echo git) push --force origin
main` really force-pushes and both this branch and `main` allowed it. The same review
found a heredoc whose opener piped into a shell, a redirect glued to a word
(`push>log`), and a `gh alias set --shell` that runs its argument through a shell. Each
is now closed and each has a case. The gate is now "does a push appear at all" rather
than "did the floor match", and a flag the line itself assigns (`F=--force; git push
$F`) is read rather than missed.

**The shipped design inverts the question.** It asks what it can *account for*, blocks
everything else, and keeps the whole-line scan as the floor for whatever the accounting
does not explain. A differential probe against `main` over the review's whole finding set
now shows no remaining case where `main` blocks a real force-push and this allows it; the
only differences are the two shapes this issue exists to fix, and one case
(`eval $'\x67it push --force'`) where the branch is stricter than `main`.

## Out-of-scope finding, filed separately

`block-secrets.sh` shares this defect class: it scans the whole command line, so it
refuses `gh issue create --body "the token=X was committed"`, `grep -rn "secret=X" docs/`
and `git commit -m "rotate password=X"`. All five such cases were measured returning exit
2, alongside three real inline secrets it correctly blocks. It is not fixed here:
narrowing a security guard's false-positive policy is a decision with a different blast
radius from a push-flag fix, and the guard has no test file of its own to hold a change
to. It is filed as issue #241.
