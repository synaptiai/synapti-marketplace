You are reviewing a pull request in this repository.

The default branch `{{BASE_BRANCH}}` holds `{{MODULE_FILE}}` as it was before the change.
The branch `{{HEAD_BRANCH}}` is checked out and holds the proposed replacement of the same
file. Review that branch's diff against `{{BASE_BRANCH}}`.

Run the same review fan-out `/flow:pr` Phase 3 runs: dispatch the five reviewer agents in
parallel over the diff, then consolidate their findings and deduplicate by `file:line`.
There is no GitHub remote here, so do not run any `gh` command and do not try to post
anything; the review ends in this session.

Useful commands:

    git diff {{BASE_BRANCH}}...{{HEAD_BRANCH}}
    git show {{BASE_BRANCH}}:{{MODULE_FILE}}

Then resolve the setting `review.groundingCritic` the way flow resolves any setting, with
`bin/cascade-resolve.sh` from the plugin directory. When it resolves to `on`, run the
grounding pass over the consolidated P1/P2 findings before you write them down, exactly as
`commands/review.md` describes it for Path B: the `finding-critic` agent answers each
finding with `AGREE`, `DISAGREE_EVIDENCE` or `DISAGREE_CONCERN`, the originating reviewer
answers a disagreement with a `file:line` citation or drops its own finding, and a reply
without a citation drops it. When it resolves to `off`, skip the pass and report the
consolidated findings as they stand. Say which of the two you did.

End your final message with your consolidated findings as a single fenced JSON block, and
nothing after it:

```json
[
  {"id": "F1", "priority": "P1", "category": "correctness", "file": "{{MODULE_FILE}}",
   "line": 12, "problem": "one sentence", "confidence": "HIGH"}
]
```

`priority` is `P1`, `P2` or `P3`. `line` is a line number in `{{MODULE_FILE}}` as the branch
has it. `confidence` is `HIGH`, `MEDIUM` or `LOW`. An empty list is a valid answer when the
diff has no defect worth a P1 or P2.
