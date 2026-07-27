# Prose Style and Vocabulary

Reference document for `prose-clarity`. The word lists, replacement table, and the epistemic-hedge allow-list that `bin/dossier-prose-lint.sh` checks mechanically. Split out of the skill because a 900-item dictionary does not fit a 170-line skill budget, and every drafting agent that loads the skill pays for every line in it.

Derived from ASD-STE100 (Simplified Technical English), distilled to the subset that is machine-checkable and free of the standard's own copyrighted 900-word dictionary — this is a style list, not a reproduction of ASD-STE100 itself.

## Marketing adjectives (hard category, blocks in every mode)

`seamless` · `robust` · `powerful` · `cutting-edge` · `effortless` · `world-class` · `next-generation` · `revolutionary` · `blazing` · `blazing-fast` · `lightning-fast` · `elegant` · `delightful` · `turnkey` · `best-in-class` · `state-of-the-art` · `game-changing` · `first-class` · `battle-tested` · `enterprise-grade` · `supercharge` · `supercharged` · `unlock` · `unleash` · `empower` · `empowering` · `innovative` · `industry-leading` · `transformative`

These are a claim about quality, not a description of it — "seamless" says nothing a reader can check; "returns within 400 ms" does.

### Explicit non-overlap with `disclosure-gating`

`disclosure-gating/SKILL.md` prohibits a **different** set as unscoped claims, not style: `secure` · `compliant` · `encrypted` · `anonymous` · `private` · `real time` · `unlimited` · `always` · `never` · `guaranteed` · `fully automated` · `zero downtime` · `bank-grade` · `enterprise-ready` (plus `military-grade`, checked only by `bin/dossier-claim-scan.sh`). None of those terms appear in this document's marketing-adjective list. `disclosure-gating`'s list is about claim scope and evidence, gated to public documents; this list is about style, applied everywhere. Where a word could plausibly belong to both (`enterprise-ready` vs. `enterprise-grade`), it is assigned to exactly one list — `tests/prose-lint.test.sh` asserts the two lists never intersect.

## Phrasal verbs (hard category, blocks in every mode)

`spin up` · `spin down` · `spun up` · `reach out` · `reaching out` · `dive into` · `diving into` · `kick off` · `roll out` · `tear down` · `ramp up` · `circle back` · `drill down` · `drill into` · `sync up` · `touch base` · `zero in on`

Name the action instead: not "let's spin up a new service", but "create a new service".

## Banned filler and hedge phrases (hard category, blocks in every mode, subject to the carve-out below)

`it is important to note that` · `it should be noted that` · `it is worth noting that` · `please note that` · `as previously mentioned` · `as mentioned above` · `as noted above` · `needless to say` · `at this point in time` · `due to the fact that` · `in the event that` · `for all intents and purposes`

Each stacks helper verbs around zero content. "It is important to note that this may potentially help improve performance" is five verbs and no work; "this improves performance" is the sentence.

## Latinate-over-short-word (hard category — the long form is a banned word)

| Long form | Short form |
|---|---|
| `utilize` | `use` |
| `leverage` (verb) | `use` |
| `facilitate` | `help` |
| `ensure` | `make sure` |
| `commence` | `start` |
| `initiate` | `start` |
| `originate` | `start` |
| `prior to` | `before` |
| `subsequent to` | `after` |
| `regarding` | `about` |
| `concerning` | `about` |
| `obtain` | `get` |
| `acquire` | `get` |
| `demonstrate` | `show` |
| `additionally` | `also` |
| `furthermore` | `also` |
| `moreover` | `also` |
| `henceforth` | `from here` |
| `therein` | `there` |
| `whilst` | `while` |
| `amongst` | `among` |
| `numerous` | `many` |
| `myriad` | `many` |
| `plethora` | `many` |
| `in order to` | `to` |
| `a variety of` | `several` |
| `endeavor` (verb) | `try` |
| `ascertain` | `find out` |

## The epistemic-hedge carve-out (never a violation, in any mode)

Sourced verbatim from `references/source-authority-and-claim-states.md:121-126`. A line opening with any of these is exempt from the hedge-phrase and sentence-length rules entirely:

- `This suggests …`
- `The most likely reading is …`
- `Inferred from …`
- `Inferred:`
- `Unknown:`
- `Recommendation:`

A drafter or the linter treating one of these as slop has confused the plugin's epistemic-honesty mechanism with the thing it exists to prevent. When in doubt, the carve-out wins — recheck this list before editing a flagged hedge.

## Advisory-only patterns (never block, reported for judgment context)

- **Passive voice**: a be-verb (`am|is|are|was|were|be|been|being`) followed by a past participle, with the actor unstated.
- **Nominalization**: a verb turned into a noun and paired with a light verb — `perform an analysis` instead of `analyze`, `make use of` instead of `use`, `carry out a review` instead of `review`.
- **Em-dash** (`—` or `--`): a diagnostic count only. This plugin's own reference documents use em-dashes constitutively, so em-dash is never a hard-category violation.

## Sentence and paragraph caps

| Mode | Sentence cap | Paragraph cap |
|---|---|---|
| Strict (numbered/bulleted steps, runbooks, command captions) | 20 words | 6 sentences |
| STE-flavored (narrative prose) | 25 words | 6 sentences |

Semicolons are banned outright in both modes — write two sentences.
