---
issue: 261
created: '2026-10-03T03:00:00Z'
artifacts:
- type: specification
  captured_at: '2026-10-03T03:00:00Z'
  by: specification-capture
  elements:
  - non-goals
  - failure-modes
  - interface-contracts
  - risk-map
---

## Specification

System One decision point `review.confidence`: after the consolidated finding set of `/flow:review` (Path B) and `/flow:pr` is final (the file:line merge, `review.dedup` and the grounding pass), each P1 or P2 finding that is not a security finding, is not LOW, has a category from the non-security vocabulary and cites a line is asked one yes/no question: does the cited code show the defect the finding describes? A confident "no" in on mode re-records the finding LOW, which then follows today's rule for LOW findings in each mode. Ships `off`. With it off, with no provider, or with no answer, the review prints and posts what it does today.

Decisions (epic #258, 2026-10-03): a demoted P1 or P2 finding goes to Needs investigation with a decision floor, so the review decision on someone else's pull request is at least COMMENT, never APPROVE; findings the reviewer rated HIGH and MEDIUM are both eligible, and the shadow comparison reports them separately; the order inside one review is deduplication (#260), then this demotion, then the challenge voice (#271, Path A only); `review.confidence` asks about Path B and `/flow:pr` findings only; #261 and #271 build their state with one shared script, `bin/flow-finding-state.sh`, which this change ships.

Corrections to the accepted spec, made against the code at 56c2a1fd (main 5496f00c plus #260):
- The mode probe is #260's `S1_REVIEW_MODES_BLOCK`, which prints one line per active site of the review synthesis; it gains `S1_CONFIDENCE=shadow|on`. There is no separate `S1_CONFIDENCE_MODE_BLOCK`.
- The client checks the threshold before the mode, so in shadow mode an unsure answer exits 3 with `below-threshold`, not `shadow`. The loop takes the mode from `bin/flow-s1-mode.sh --all review.confidence`, prints it as `S1_CONFIDENCE_MODE=`, and demotes only when it is `on` and the client exited 0 with p < 0.5.
- The loop is a script, `bin/flow-s1-confidence.sh` (Python half `_flow_s1_confidence.py`), as #260 did for its merge rule, so #262's replay runs the same code. `S1_CONFIDENCE_BLOCK` in each command is a thin wrapper around it.
- Input follows #260's convention: `CONFIDENCE_DIR` is a directory from `mktemp -d` holding `findings.json`, a JSON list (not JSONL). The reviewer field is `reviewers` (a list), as #260 defined it; a merged finding carries `locations`. The demoted ids are written to `demoted.txt` in the same directory (`S1_DEMOTED_FILE`), which is private to the user.
- `REVIEW_CHECKOUT_BLOCK` prints `REVIEW_TREE` but no head commit. The script reads the head with `git rev-parse` under the same safe environment #260 uses (`safe.bareRepository=explicit`, `GIT_ATTR_SOURCE` the empty tree) and passes it to the state helper as `--head`. The state helper reads the cited files from the tree and runs one git command, `git ls-files` under the same environment, only to refuse a file git does not track; that never changes the bytes, so a replay with the same `--head` gives the same bytes.
- Ref prefix: `pr:<N>/review-cycle:<C>` in `/flow:review`, matching `review.dedup`; each finding adds `/<id>`. In `/flow:pr`: `branch:<branch>@<12-character head>`, or `head:<12-character head>` when the branch is outside the ref grammar. `/flow:pr` passes no run id (as `review.dedup` does there); its records go to the per-user state directory.
- Security rule: the one `DROPPED_FINDING_BLOCK` and `review.dedup` apply: a reviewer whose name contains `security`, an id starting `SEC-` or `DEP-`, or a category in the grounding pass's security list is `not-eligible-security`; any other category outside the non-security vocabulary is `not-eligible-category`. The router refuses a demotion of a row that either rule would exclude.
- Cost: besides the cap of 25 findings, asking stops after two `timeout` or `connection` results in a row (`provider-down`) and when 90 seconds have passed (`budget`), as `review.dedup` does, so a slow local model cannot hold the review past the Bash call's two minutes. The findings not asked carry `REASON=cap`, `provider-down` or `budget`. These two reasons are added to the spec's closed list.
- Reasons that send nothing and would repeat for every finding (settings-refused, provider-none, python-missing, mode-off, invalid-settings, insecure-url, no-api-key, unknown-site, no-threshold, questions-invalid) are asked once; every later eligible finding carries the same reason with no request.
- A finding whose `reviewers` list is missing or empty is `invalid-finding`: the security rule needs it.
- The kept state file is `.flow/runs/<RUN_ID>/system-one-state/confidence-<id>.json` (with a prefix, because #260 and #271 write to the same directory).
- In the router, the decision floor applies to every listed id present in the rows at P1 or P2, whatever confidence the row carried: a session that writes the demoted row LOW and also passes the file must not get APPROVE.

### Non-goals
- Never raises a confidence: a "supported" answer leaves HIGH and MEDIUM as they were.
- Never removes, merges or re-prioritizes a finding; only confidence changes, and only to LOW.
- Never asks about a security finding, a P3 finding, a LOW finding, a file-level finding, or a finding whose category is outside the non-security vocabulary.
- Does not change the grounding pass, its default, or its record steps; it runs after it.
- Does not ask about Path A findings (`USE_PATH_A=1`); that is #271.
- Does not change how duplicates are merged (#260); it reads the merged finding.
- Does not run the measurement that decides the default (#262) or switch the site on.
- Does not run anything from the tree under review or apply its git attributes: the cited code is read as files.
- Does not change the `FLOW_REVIEW_CYCLE` marker's seven fields.
- Does not change `flow-s1.sh`'s request, threshold handling or record format.
- Python 3.12 to 3.14 only.

### Failure modes
- Timeout, HTTP error, redirect, connection failure, malformed reply, missing answer, abstention, below threshold: `STATE=no-answer REASON=<reason>`; the confidence is unchanged.
- Provider slow or down: two `timeout`/`connection` results in a row stop the asking (`provider-down`); 90 s stops it (`budget`); at most 25 findings are asked (`cap`).
- Configuration reasons: asked once, then repeated for each eligible finding with no request.
- Cited path escapes the tree (absolute, `..`, a symlink at any component, a real path outside the tree, not a regular file): `REASON=path-refused`, no request.
- Cited file missing, or the cited line past the end: `file-missing`, `line-out-of-range`. Non-UTF-8 or a NUL byte in the window: `not-text`.
- Malformed entry (not an object, missing field, bad id, duplicate id, no reviewers list): `invalid-finding`, and the loop continues. A findings file that is not a JSON list, a missing tree, or a bad ref prefix or run id: exit 2 with `STATE=blocked`, nothing asked.
- Prompt injection through the cited code: security findings are never sent; on someone else's pull request a demoted P1/P2 finding cannot turn the decision into APPROVE (the floor).
- Shell injection: finding text and paths are read by Python from JSON, never interpolated into shell code.
- No run id or no run directory: records go to the per-user state directory and the state is not kept.
- The plugin only inside the repository: the probe prints nothing; the block prints `REASON=plugin-missing`; the script run from that copy reports `settings-refused`.
- python3 missing: every eligible finding `no-answer REASON=python-missing`.
- External review where the session forgot to apply a demotion: the router applies every id in `S1_DEMOTED_FILE`. On your own pull request and in `/flow:pr` only the prose requires it.

### Interface contracts
- `S1_REVIEW_MODES_BLOCK` (both commands): adds `S1_CONFIDENCE=shadow` or `S1_CONFIDENCE=on` when `flow-s1-mode.sh review.confidence` prints that; nothing otherwise. Sends nothing, writes nothing.
- `S1_CONFIDENCE_BLOCK` (review.md): env `S1_CONFIDENCE`, `CONFIDENCE_DIR`, `PR_NUM`, `CYCLE_NUMBER`, `REVIEW_TREE`, `USE_PATH_A` (0 or 1), `RUN_ID` (optional). Skips with `S1_CONFIDENCE_STATE=skipped REASON=not-active|path-a|plugin-missing`; refuses a bad input with `STATE=blocked`, exit 2. (pr.md): env `S1_CONFIDENCE`, `CONFIDENCE_DIR`; the tree is the checkout.
- `bin/flow-s1-confidence.sh --findings <file> --tree <dir> --ref-prefix <ref> [--run-id <id>] [--demoted-out <file>]`: one `S1_CONFIDENCE_RESULT=<id> STATE=answered|no-answer|skipped ...` line per finding in input order (answered: `VERDICT=supported|unsupported P= CONFIDENCE= MODEL= TRUNCATED=0|1`; otherwise `REASON=`; `TRUNCATED_LOCATIONS=1` when more than three locations were cut), then `S1_CONFIDENCE_MODE=`, `S1_ASKED=`, `S1_DEMOTED=<ids>` (empty unless on mode), `S1_DEMOTED_FILE=<path>` when non-empty. Exit 0, or 2 with `STATE=blocked` and `ERROR=`.
- `bin/flow-finding-state.sh --tree <dir> --finding <json file> [--head <sha>]`: the state JSON on stdout, exit 0; `SKIP=<reason>`, exit 4; usage error exit 2. Deterministic (sorted keys, no clock).
- State: `{"finding": {"priority","category","problem"}, "code": [{"path","head","start","end","cited_start","cited_end","text"}]}`, at most three code entries; the window is the cited lines plus 30 either side, a cited range over 120 lines cut to its first 120; no id, reviewer, confidence or fix.
- Call per finding: `flow-s1.sh ask --site review.confidence --state-format json --state-file <f> --current <HIGH|MEDIUM> --ref <prefix>/<id> [--run-id <id>]`.
- `bin/flow-finding-route.sh --s1-demoted <file>`: external mode only (self mode exit 1); each listed id present is routed LOW; an absent id gets one `LEDGER_WARN`; a listed security row exits 1 with nothing routed; when a listed id is present at P1 or P2 the decision is at least COMMENT; `S1_DEMOTED_APPLIED=<ids>` after `MARKER_ROWS`. Without the flag the output is byte-identical to before.
- `FINDING_ROUTE_BLOCK` and `FINDING_POST_BLOCK` pass `--s1-demoted "$S1_DEMOTED_FILE"` under one condition: `REVIEW_MODE=external` and `S1_DEMOTED_FILE` is a non-empty regular file that is not a symlink.
- questions.yaml holds the only threshold (provisional 0.9).

### Risk map
| Area | Plausible wrong version | Discriminating check |
|---|---|---|
| Direction of the answer | demotes when p >= 0.5 | on mode: p=0.03 gives `VERDICT=unsupported` and the id in `S1_DEMOTED`; p=0.97 gives `supported` and an empty `S1_DEMOTED` |
| Shadow changes output | follows the exit reason or demotes on a shadow answer | shadow with p=0.03: `S1_DEMOTED=` empty, no file, router output equal to the off case, record mode shadow |
| Security exemption | checks only `category == security` | category auth; SEC-2 with category correctness; DEP-1; reviewers [code-reviewer, security-reviewer]: each `not-eligible-security`, 0 requests; category weird-new: `not-eligible-category`; router refuses a listed injection row |
| Demotion approves someone else's pull request | the floor is computed from rows whose confidence changed, or is missing | external, the only P1 demoted: `DECISION=COMMENT`; the same with the row already written LOW plus the flag: `COMMENT` |
| Off is not identical | routing blocks always pass the flag, or the probe prints an off line | off, provider none, plugin in the repository: probe prints nothing, 0 requests, no records; router without the flag byte-identical to the router at 5496f00c on the same rows, in both modes |
| Path containment | the tree and the reviewer path are joined without checks | `../outside.txt:1`, `/etc/hosts:1`, `link/a.py:1` through a symlinked directory, a FIFO: `path-refused`, 0 requests, the outside text in no request |
