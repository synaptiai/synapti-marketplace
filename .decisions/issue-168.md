# Issue #168 — /flow:learn looked for its evidence in one place and said nothing when it was elsewhere

Branch: `fix/issue-168-learn-sources`
Closes #168, #169.

Grouped because they are the same defect twice: a path resolved against one
assumption, with no signal when the assumption is wrong. One loses an evidence
source; the other writes into the wrong repository.

## Specification

### Non-goals

- Changing the correction-phrase filter or the clustering threshold. What counts
  as a correction, and how many instances make a pattern, are untouched.
- Discovering transcripts outside a `projects/<slug>` layout.
- Changing the draft-PR posture of promotion. It stays Tier 2 and never
  auto-merges.
- Changing the proposal template or its validation.
- Making promotion work from a plugin cache under `~/.claude/plugins`. A cache
  has no remote to open a pull request against; it is refused with the reason.

### Failure modes

- **Transcripts under the second known root.** Found. The first root is probed
  first and wins when it matches.
- **An explicit `--transcript-dir` or `CLAUDE_TRANSCRIPT_DIR`.** Overrides the
  list outright, unchanged.
- **No root matches.** Reported as missing, naming every root that was tried.
  "Never found" and "found and empty" are different findings and must not read
  alike — that is the whole issue.
- **A directory the caller named that is absent.** Says that directory is not
  there, in its own words. Borrowing the roots-list wording would be wrong: no
  roots were searched.
- **Promotion from a project that merely uses flow.** Resolves to flow's own
  checkout, or exits non-zero saying why. It never creates a `plugins/flow` tree
  in a repository that did not have one.
- **`FLOW_REPO_ROOT` pointing somewhere that is not a flow checkout.** Refused
  with the reason, rather than trusted.

### Interface contracts

- The miner keeps emitting `TRANSCRIPT_DIR`, `TRANSCRIPT_DIR_STATE`,
  `CANDIDATE_COUNT`, `SESSION_COUNT` and `SESSIONS_WITH_CANDIDATES`, and adds
  `TRANSCRIPT_ROOTS_TRIED` only in the missing state.
- Both scripts keep exiting 0 on a missing input, because callers sit in `!`
  blocks and a SessionEnd hook. Promotion is the exception: a wrong-repository
  target exits 2, since writing to the wrong place is worse than not writing.
- `promote-proposal.sh --dry-run` prints the same resolved target the real run
  would use, and says how it was chosen.

### Risk map

| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Root probing | Append the second root but keep returning the first path regardless, so the report names a directory that was not read | A tree where only the second root holds the transcript must report `STATE=ok` and a path under that root |
| Root probing | Probe the second root even when the first matched, and report the last one tried | A tree where both roots hold the transcript must report the first |
| Missing-state message | Name only the path that was ultimately used, which is what made "not found" and "found and empty" look alike | The missing report must contain both root names |
| Missing-state message | Use the roots-list wording for an explicit `--transcript-dir`, which never searched any roots | The explicit-override case must say "transcript dir not found" and must not say "any known root" |
| Promotion target | Resolve to the script's checkout even when the user is standing in a flow checkout of their own, silently promoting into the wrong clone | A consuming project must not be targeted, and the marketplace checkout must be when the user is in it |
| Promotion target | Accept any repository containing a `plugins/` directory as flow, which is exactly the shape that hid the original defect | The consuming project fixture has its own `plugins/someother` and must still be refused |

## Stranger Test

PASS — 6 tasks reviewed.
