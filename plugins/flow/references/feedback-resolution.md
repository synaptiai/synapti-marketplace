# Feedback Resolution Detail

Detail for `skills/feedback-resolution/SKILL.md`, which `/flow:address` applies.

## System One checks

When the System One decision point `address.category` is on, `/flow:address` asks it for each item after the category is chosen; a confident answer can raise the item (P1 > P2 > P3 > Question), never lower it. When `address.still_applies` is on, an inline comment it finds already addressed is listed as "Already addressed", with the path, lines and commit checked and the confidence, in its reply, the Thread Status table and the summary.

## Findings outside the feedback

A finding in a touched file is never out-of-scope. P1/P2 anywhere: fix in this PR. Cosmetic P3 in an untouched file: fix in this PR with an `improve:` commit; a follow-up issue only under `minimalScope` mode.

## Escalation

A genuine product or architecture judgment beyond the three pushback grounds is a six-field escalation per `references/escalation-format.md`. Finding triage (the P1/P2/P3 disposition) is never an escalation trigger (`skills/llm-operator-principles/SKILL.md`).

## Why the resolution comment comes with the re-request

A push without the resolution comment is incomplete: the reviewer cannot see what was addressed.

## Collecting

`bin/flow-pr-feedback.sh <pr-number>` prints each inline review comment as `{id, path, line, body, author}` and then each review as `{state, body, author}`, one JSON object per line. It exits 1 when a gh call fails and 2 when the PR number is missing or not a positive whole number.
