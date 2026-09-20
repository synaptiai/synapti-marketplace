---
issue: 244
created: '2026-09-19T23:38:47Z'
artifacts:
- type: specification
  captured_at: '2026-09-19T23:38:47Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
- type: workflow-run
  captured_at: '2026-09-19T23:39:45Z'
  workflow: start-issue
  run_id: 2026-09-19T233805Z-issue-244
  status: active
---
# Decision Journal — Issue #244

**Title:** flow: machine breadcrumbs churn the tracked decision journal, and concurrent writers lose each other's writes
**Branch:** feature/issue-244-auto-log-out-of-journal
**Started:** 2026-09-20

## Specification

_Captured by specification-capture skill on 2026-09-20. Source: user-confirmed._

### Non-goals

- Not changing the journal's YAML frontmatter manifest schema or the shape of `artifacts[]` entries.
- Not changing how the journal file is selected for deliberate entries — the branch-to-`issue-N` mapping stays.
- Not removing the audit trail. It moves to a gitignored location; it is not deleted.
- Not making the `yaml` import lazy. `journal-record.sh` and `windows-hooks-smoke.sh` depend on the current preflight contract, so that is a separate change with its own blast radius.
- Not rewriting historical journal prose. `.decisions/issue-55.md` keeps its three mentions of the token, including an interface contract that accurately described the hook when it was written.
- Not migrating the dated workshop material (`docs/flow-team-session/slides*.md`, `walkthrough-script.md`). Only the reference-shaped files in that directory are corrected.

### Failure modes

- **Missing context** — `jq` absent: the hook exits 0 without logging. Plugin root unresolved via `CLAUDE_PLUGIN_ROOT`: fall back to the script's own location, the pattern `log-file-changes.sh` already uses for its ledger. Payload carries no `cwd`: fall back to `$PWD`. Payload `cwd` names a directory that no longer exists: exit 0.
- **Invalid input** — a resolved file path outside the repository, or in no repository at all: skipped silently, no entry, exit 0. An empty or absent `file_path`/`notebook_path`: exit 0. A journal path that is a symlink: refused, exit 0, nothing written.
- **Partial failures** — the append helper fails for any reason (unwritable directory, missing PyYAML, refused symlink, lock contention): the hook swallows it and exits 0. A hook must never fail the tool call it runs after. The strip script rewrites each journal atomically or not at all; a file that ends inside an unbalanced fence is left partially stripped and reported, never half-written.
- **Timeouts** — none — no hook or helper in this change performs a network call or an unbounded wait. The only blocking primitive is `flock`, whose wait is bounded by the current holder's own file I/O.

### Interface contracts

- **Hook stdin payload** (PostToolUse): `tool_name`, `tool_input.file_path` or `tool_input.notebook_path`, `cwd`, `session_id`, and — only when the hook fires inside a subagent — `agent_id` and `agent_type`.
- **Auto-log file naming**: `auto-log/issue-<N>.<YYYY-MM>.md` when the branch matches `issue-<N>`; otherwise `auto-log/session-<YYYY-MM-DD>.md`.
- **Entry line**: `<!-- auto-log: YYYY-MM-DD HH:MM <Tool> <repo-relative-path>[ agent=<type>] -->` for edits, and `<!-- auto-log: YYYY-MM-DD HH:MM commit "<subject>"[ agent=<type>] -->` for commits. Main-thread entries are byte-identical to today's shape; `agent=` appears only when `agent_type` is present.
- **`journal-append.sh`**: `--issue <N>` or `--file <path>` selects the target; `--replace-heading <H>` switches from append to section replacement; `-` reads the entry from stdin. Exit 0 appended, 1 bad arguments, 2 infrastructure error.
- **Lockfile**: `<target>.lock` — the same lockfile path the manifest writer uses, so body appends and manifest writes serialize against each other.
- **`flow-strip-auto-log.sh`**: dry-run by default, reporting `STRIP_AUTO_LOG=none` or `STRIP_AUTO_LOG=<files> files, <lines> lines`; `--apply` writes. Exit 0 success, 2 infrastructure error. Matches the `flow-migrate-settings.sh` output vocabulary.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| cwd normalization | compares the payload `cwd` to the repo root without resolving symlinks, so on macOS `/var/...` never prefix-matches `/private/var/...` and every in-repo file looks out-of-tree | repo under `mktemp -d` on macOS, edit a repo file → right: one entry written; wrong: nothing written |
| in-repo boundary comparison | prefix-matches without the trailing separator, so a sibling directory sharing a name prefix counts as inside | repo at `/tmp/x/repo`, edit `/tmp/x/repo-backup/f.md` → right: skipped; wrong: logged as in-repo |
| lock ordering | opens the target with `O_APPEND` before acquiring the lock, so a concurrent rename leaves the fd on an unlinked inode and the append vanishes without error | append concurrently with a manifest write, with a delay between open and lock → right: both survive; wrong: the append is lost |
| blank-line pairing in the strip | removes the breadcrumb but keeps the blank line it introduced, or consumes a blank that separated real content | journal body `text\n\n<!-- auto-log: 1 -->\n\nmore` → right: `text\n\nmore`; wrong: a doubled blank or a swallowed separator |
| fence state tracking | toggles fence state on any line containing three backticks, including an inline code span, desynchronizing so a later breadcrumb inside a real fence is stripped | inline triple-backtick span, then a fenced block containing a breadcrumb → right: preserved; wrong: stripped |
| branchless fallback naming | applies the monthly rotation to the session file too, so the local trail no longer corresponds to the tracked journal's daily name | run on a branch with no issue number → right: `session-<YYYY-MM-DD>.md`; wrong: `session-<YYYY-MM>.md` |

## Implementation Decision: the locked body-append protocol

**Date**: 2026-09-20 | **Category**: implementation

**Decision**: `append_body()` and `replace_section()` live in `bin/_journal_atomic.py`, take the same `<target>.lock` the manifest writer uses, and are driven by a new `bin/journal-append.sh`. `append_body` uses `O_APPEND` acquired after the lock; `replace_section` uses read-modify-write because a mid-file replacement cannot be an append.

**Rationale**: The defect was two writer classes on one file with one lock between them. `record_artifact()` reads the whole file, and the unlocked appenders extended it while it did; its rename then published the pre-append snapshot. Sharing the lockfile is what removes the class, not just the two hooks that happened to be loudest.

**Evidence — what the tests actually discriminate.** Mutations applied and reverted:
- removing the shared lock from `append_body` → T8 (lockfile existence) and T12 (lock ordering) fail. **T9 is not the discriminator it was written to be**: an independent pass ran it eight times against that mutation and it passed every time, and a later replay here measured T8/T12 failing while T9 stayed green. It reached the window once and I recorded that as its behaviour; one observation was not enough to name it the test for this. T12 is the deterministic one; T9 is a flaky extra.
- replacing the locked read-modify-write with a truncating open (`O_TRUNC`) → T10 fails on all four assertions;
- opening the target *before* acquiring the lock → **T12** fails.

**A note on how T12 came to exist, because the first measurement was wrong.** The claim was made, and briefly recorded here, that the lock-ordering row had no discriminating test because its window is sub-millisecond and unreachable from bash. That was a bad measurement, not a fact. Timing-based races (T9, T10) genuinely cannot reach the window — a background `>>` completes in microseconds while the helper's `python3` spawn takes tens of milliseconds — and T9 is *flaky* for the same reason: the same no-lock defect produced `fail=2` on one run and `fail=0` on another. T12 replaces timing with control: a blocker takes the lock, reads the file, signals readiness, holds for one second, publishes its stale snapshot, and only then releases, while the appender has already started. Both wrong implementations lose the entry deterministically — no lock at all, and lock-taken-after-open. Three consecutive runs each way agree.

**Residual coverage gap, stated precisely.** The choice of `O_APPEND` over a locked read-modify-write is still *not* separately pinned: under the shared lock both produce correct results against cooperating writers, and the property `O_APPEND` buys — that a writer which cannot see `flock` (an editor, an older plugin version, a bare `>>`) is never reverted — is not schedulable from inside the test process. It remains a reasoned design choice. T10 says so in its own header rather than implying otherwise: an earlier draft of that test claimed to pin it, was believed, and stayed green under the exact mutation it was written to catch.

**Alternatives considered**:
- A read-modify-write body append under the lock — correct against cooperating writers, but it publishes a stale snapshot over any writer that cannot see `flock` (an editor, a session on an older plugin version, a bare `>>` from an un-migrated consumer).
- A separate lockfile for the body — rejected: it would serialize nothing, since the whole defect is that two writer classes must contend on ONE lock.

**Test coverage**: `plugins/flow/tests/journal-append.test.sh` (42 assertions at the time of writing) and `plugins/flow/tests/auto-log-relocation.test.sh` (37).
