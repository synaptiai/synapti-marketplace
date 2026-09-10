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

- Changing which whole-tree operations count as destructive. `git checkout -- .`,
  `git restore .`, `git reset --hard` and `git clean -f` block before and after.
  Nothing that was allowed becomes blocked.
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

<!-- auto-log: 2026-09-10 22:34 Write /Users/danielbentes/synapti-marketplace/.decisions/issue-167.md -->

<!-- auto-log: 2026-09-10 22:35 Write /Users/danielbentes/synapti-marketplace/plugins/flow/tests/block-destructive-git.test.sh -->
