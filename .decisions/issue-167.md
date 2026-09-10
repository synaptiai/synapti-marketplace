# Issue #167 — the git matchers in block-destructive.sh read a string, not a command

Branch: `fix/issue-167-destructive-matchers`
Closes #167, #142.

Grouped because both reports are the same defect in the same file, seen from two
sides: a matcher written as a regex over the raw command text rather than over
the command actually being run. The `rm` half of #142 was repaired in a previous
change; what is left of it is the quoted-text clause, which is exactly what #167
describes for the git matchers.

## Specification

### Non-goals

- Changing which whole-tree operations count as destructive. The four rules
  cover the same operations before and after. Two spellings do move, and both are
  recorded under Decisions below rather than left as a surprise.
- Widening the checkout matcher to the separator-less `git checkout .`. It is not
  blocked today and this change is about precision, not reach.
- Touching the `rm` rule or the force-branch-delete rule's merge logic.
- Parsing shell grammar in general. The tokeniser reads words the way the shell
  reads words; it does not implement expansion, control flow, or aliasing.

### Failure modes

- **A path that begins with a dot.** Allowed. `.decisions/x.md` and
  `.github/workflows/ci.yml` are ordinary paths in this repository, not the whole
  tree.
- **The whole tree with more arguments after it.** Blocked. `git checkout -- . src/a`
  still discards everything under `.`.
- **The pattern inside quoted text, a heredoc body, or a comment.** Allowed, when
  no git actually runs. Writing the issue was refused three times by this exact
  failure.
- **A command substitution that really runs git.** Blocked. `$(git restore .)`
  runs git; text inside quotes does not.
- **An unterminated quote.** The partial word stays a token and the segment is
  still examined. Ambiguity does not become permission.
- **`git restore --staged .`** touches only the index and leaves the working tree
  alone. Allowed today by accident of the regex, and allowed deliberately after.
- **`git restore --staged --worktree .`** writes the working tree. Blocked.
- **A heredoc opened inside a double-quoted command substitution** —
  `gh pr create --body "$(cat <<EOF ... EOF)"` — is content. This is the shape
  nearly every long body takes, and it is the shape that refused the issue three
  times while it was being written.
- **A heredoc handed to something that runs it** — `bash <<EOF`, `sh <<EOF`
  through an assignment, `ssh host <<EOF` — is code and is examined.
- **A long command.** The hook runs before every Bash call, so reading one has to
  be linear in its length.

## Decisions taken during implementation

- **The compound force-branch-delete refusal is kept, and stated.** The old
  target parser blocked `git branch -D merged && anything` because it could not
  tell branch names from the rest of the line. The new parser can, which would
  have turned that block into an allow. The refusal is worth keeping — the
  merged-branch proof covers the branch, not the chain — so it is now its own
  rule with its own message rather than a side effect.
- **One form moves from allowed to blocked.** `git checkout <options> -- .` was
  missed by a regex that required `--` to follow `checkout` immediately. It is
  the same whole-tree discard the rule already names.
- **A pre-existing quadratic cost is fixed here.** The word tokeniser walked
  characters in bash and appended one at a time. On `main`, a 40KB quoted
  argument containing the letters `rm` — the word "perform" is enough — took 59
  seconds before the command it guarded could start. Reading the command now
  takes 0.2 seconds. Two changes: the scanner and the tokeniser run as one awk
  pass each over substring slices, and a greedy `${tok##*/}` is skipped for
  tokens longer than PATH_MAX, which no command word ever is.

### Interface contracts

- The hook keeps reading `{"tool_input":{"command":...}}` on stdin and keeps
  exiting 0 to allow and 2 to block, with the reason on stderr.
- Every existing block message keeps its wording; the tests assert on the
  `BLOCKED:` prefix and the remedy phrase.
- The tokeniser (`_rm_tokenise`) is reused verbatim rather than duplicated, so the
  quoting rules the `rm` rule already documents govern the git rules too.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Whole-tree detection | Treat any pathspec starting with `.` as the whole tree — the original defect, restated in tokens instead of a regex | `git checkout -- .decisions/issue-749.md` must be allowed and `git checkout -- .` blocked in the same run |
| Whole-tree detection | Match only a pathspec that is the last word, so `git checkout -- . src/a.py` slips through | A case with the whole-tree pathspec followed by another path |
| Heredoc stripping | Strip from `<<EOF` to the end of the command, swallowing a real destructive command written after the terminator | A heredoc whose body holds the pattern followed by a real `git reset --hard` after `EOF`, which must still block |
| Heredoc stripping | Treat `<<` inside quotes as a heredoc introducer and drop the rest of a legitimate command | A command containing the literal text `<<EOF` inside a quoted string, with a real destructive command after it |
| Comment stripping | Strip everything after any `#`, including a `#` inside a quoted path or a URL fragment | A destructive command whose argument contains `#` must still block |
| restore semantics | Treat `--staged` as making every restore safe, so `--staged --worktree .` is allowed | Both spellings in the same run, with opposite expected verdicts |

## Stranger Test

PASS — 6 tasks reviewed.














