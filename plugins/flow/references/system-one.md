# System One (optional)

Flow makes many narrow judgments whose answer comes from a closed set. Examples: whether two review findings describe the same defect, whether a comment still applies, whether a user turn is a correction. A System One model answers that kind of question directly. It takes a **state** (text or JSON) and typed **questions**, and returns calibrated probabilities:

| Type | Answers | Example |
|---|---|---|
| `noul` | the probability that a statement is true | "The cited code does what the finding claims." |
| `choice` | one option from a set you define, with a probability for each | "Which consolidated finding reports the same defect, or none?" |
| `score` | a position on 2 to 10 ordered levels | "How urgent is this ticket?" |

It does not generate text or use tools.

Flow can use one when you configure a provider. With no provider, the default, Flow behaves exactly as it does without this feature.

## Status

The client is in place. Each decision point is added, with its questions and thresholds, by the change that wires it in. Each ships `off`; you can set it to `shadow` to collect records, and it is switched on by default only after a written comparison of shadow records with the decisions Flow took supports it.

| Site | Where | What it decides | Default | Threshold |
|---|---|---|---|---|
| `address.category` | `/flow:address` Phase 2 | The priority of one feedback item (P1, P2, P3 or Question), asked after the session has chosen its own. On: the item is handled at the higher of the two, ranked P1 > P2 > P3 > Question; an answer never lowers an item, and a Resolved item is not asked about | `off` | `0.8`, provisional: no threshold is set; on this model the question over-raises to P1 (see [below](#addresscategory)) |
| `address.still_applies` | `/flow:address` Phase 1 | Whether an inline review comment that starts a thread still applies to the code at the place it refers to now; a comment on a removed line, on the whole file or on a file that no longer exists is not asked about. A comment whose lines a later commit changed is asked about with its diff hunk (the lines as they were) and the code now around its original line number, and the state says those lines are gone. On: a comment found already addressed gets no Explore check and no fix, and is listed with the path, lines and commit checked and the confidence; any other result falls back to the Explore check. A comment on a file with uncommitted changes is not asked about. The state sent (comment body, diff hunk, code window) is kept in the run directory, see [Records](#records) | `off` | `0.9`, provisional: the shadow comparison does not support choosing one (see [below](#addressstill_applies)) |

### address.category

The threshold is 0.8, provisional, for every model. The shadow comparison for TypeSafe jev-1.13.0, made on 2026-10-07, could not choose one. The rule for choosing it needs a ruling, for each item the model would raise, on whether the higher priority was right. The comparison has no such rulings, and it shows the model raising about half of all items, most of them to P1.

**What it was measured on.** There are no records from real use: no `/flow:address` run has recorded this site. The comparison uses a replay only. 200 finding rows that Flow's review sessions posted on pull requests 150 to 255 (2026-08-03 to 2026-09-27) were sent through the site's own block in shadow mode, with the plugin copy at b5bc8541. Each row's label is the priority the reviewing session gave it: 27 P1, 75 P2, 98 P3 and no Question. A session addressing that finding takes the same priority, so the label and the decision Flow took are one and the same, and agreement with either is one figure. The 200 records were written on 2026-10-07 between 06:06 and 06:19 UTC. Every request got an answer from the provider; 128 cleared 0.8 and 72 fell below it. No request timed out or failed.

**Where the replay differs from real use.** The priority marker was removed from each row before it was sent, so the model could not copy it. In real use the session sends the row as posted, which usually includes the priority. Every replayed item is therefore one without a reviewer severity label, and the comparison says nothing about items that carry one. The replay has no Question items and no inline comments (none on this repository carries a priority), and every row comes from Flow's own review sessions. It meets the minimum planned for these comparisons (40 judged items, at least 10 of each outcome) for P1, P2 and P3, and not for Question.

**Could the set have produced this result?** An answer that copied the label, or a constant answer, would show up as follows. The label is not in the text sent: no item contains P1, P2 or P3. A constant "P3" would agree with the reviewer on 98 of 200 items (49%) and a constant "P1" on 27 (14%). The 200 states sent are all different, and the model's answers are neither constant nor a copy of the label.

**The model's choice against the reviewer's priority**, all 200 answers (rows: the reviewer's priority; columns: the model's choice):

| Reviewer | P1 | P2 | P3 | Question |
|---|---|---|---|---|
| P1 | 26 | 1 | 0 | 0 |
| P2 | 57 | 17 | 1 | 0 |
| P3 | 51 | 45 | 1 | 1 |

The model agrees with the reviewer on 44 of 200 items (22%; higher is closer to the reviewer), less often than a constant "P3" would. It chose P1 for 134 of the 200. It chose a higher priority than the reviewer's for 153 items and a lower one for 3, which the site never acts on.

**How confident the answers are.** Confidence runs from 0 to 1; higher means the model's answer leaned harder to one option. The 44 agreeing answers have a median confidence of 0.99 (lowest 0.31). The 153 higher answers have a median of 0.93 (lowest 0.19). Confidence does not separate the answers that agree with the reviewer from the ones that raise, so a higher threshold cuts raises only in proportion.

**Raises by threshold.** In on mode a raise means the item is handled at the higher priority, so it gets a fix rather than a reply, or a fix earlier. Fewer raises is better unless the raises are right, and how many are right is not known. Two rules are shown. *Highest option*: raise when the answer's confidence clears the threshold and its chosen option ranks above the session's (the shipped rule). *Summed*: raise when the probabilities of all options ranked above the session's add up to the threshold or more.

| Threshold | Answers clearing it | Of those, agreeing | Raises, highest option | Raises, summed |
|---|---|---|---|---|
| 0.5 | 177 (88%) | 41 | 135 (68%) | 153 (76%) |
| 0.6 | 162 (81%) | 38 | 123 (62%) | 151 (76%) |
| 0.7 | 144 (72%) | 37 | 106 (53%) | 145 (72%) |
| 0.8 | 128 (64%) | 31 | 96 (48%) | 139 (70%) |
| 0.9 | 114 (57%) | 30 | 83 (42%) | 130 (65%) |
| 0.95 | 98 (49%) | 28 | 69 (34%) | 123 (62%) |

At 0.8 the 96 raises are 49 from P2 to P1, 29 from P3 to P1 and 18 from P3 to P2.

**The reviewer's confidence note.** Many rows end with the reviewing session's own confidence, such as `_(HIGH · unchallenged)_`, which a model could read as severity. The share of items the model put at P1 is similar with and without the note for P2 items (29 of 35 with HIGH, 10 of 16 with MEDIUM, 18 of 24 with none) and somewhat higher with a note for P3 items (20 of 34, 16 of 26, 15 of 38). The note is not the main reason for the lean towards P1.

**Result.** On this model the question over-raises items to P1: the model agrees with the reviewer's priority on 22% of items, and at 0.8 it would raise 48% of all items, most of them to P1. No threshold is set for jev-1.13.0: 0.8 stays the provisional default, and the site ships `off`, with shadow collection. Choosing a threshold needs a ruling on each raise. These numbers hold for the question as worded now; a reworded question needs a new measurement before any threshold is set for it. Each of the 200 items, with its text, both priorities and the answer's probabilities, is in [`evals/results-2026-10-07-address-s1/address-category.jsonl`](../evals/results-2026-10-07-address-s1/address-category.jsonl), with a `ruling` field left empty for that.

### address.still_applies

The threshold is 0.9, provisional, for every model. The shadow comparison for TypeSafe jev-1.13.0, made on 2026-10-07, does not support choosing one. The rule is the lowest threshold at which no "already addressed" answer is wrong. On this data that rule gives 0.5, but the set is too small to rely on it (see [The threshold rule](#the-threshold-rule-for-addressstill_applies) below).

**What it was measured on.** There are no records from real use and no Explore verdicts to compare with. The comparison uses a replay only. The 12 inline review comments on this repository's pull requests that start a thread were used: 9 written by the repository owner on two pull requests and 3 code-scanning alerts, posted between 2026-05-06 and 2026-09-30. Each was checked twice, against the code it was written on and against the pull request's final code. That gives 24 items. The label of each says whether the concern was still present. It is present in 15: 12 by construction, because the code is the code the comment was written on, and 3 whose lines never changed. It was addressed in 9: for each, a reply named the fixing commit and the commented lines changed after the commented commit. The 22 records were written on 2026-10-07 between 08:39 and 08:41 UTC, with the plugin at 5cccb68f.

**What was asked.** 22 of the 24 items: 14 still present and 8 addressed. The other 2 are one comment on a whole file, checked at both commits; the site never asks about a comment on a whole file, and that comment was addressed. In all 8 addressed items asked, the fix had changed the commented lines, so GitHub marks the comment outdated and its line is no longer in the file. The site asks about these anyway: the state holds the comment's diff hunk (the lines as they were), the code now around the line number they had, and a marker saying the lines are gone. The set is short of the minimum planned for these comparisons (40 judged items, at least 10 of each outcome): it has 22 items and 8 addressed.

**Could the set have produced this result?** In this set the marker "the commented lines are gone" is set on exactly the 8 addressed items and on none of the 14 still present, so a model that read only the marker would separate them perfectly. To check this, all 22 states were sent again with only the marker reversed. The answers hardly moved: p changed by 0.03 on average and by 0.10 at most. Of the 8 addressed items, 7 leaned towards "already addressed" both times; of the 14 still present, 3 did with the true marker and 4 with the reversed one. The answers come from the comment and the code, not from the marker. These check answers are kept apart from the replay records. The set has a second split it cannot rule out: in all 8 addressed items the commented lines are missing from the code shown, and in all 14 still present they are there. A model that answered "already addressed" whenever the commented lines had changed would score 8 of 8 and 14 of 14; this one scored 7 of 8 and 11 of 14, so it is not doing only that, but the set cannot tell recognising a fix from noticing that the lines changed. That needs comments fixed without changing their lines, or outdated comments whose concern survived the change, and the set has neither.

**Answers.** Every request got an answer from the provider; 6 cleared 0.9 and 16 fell below it. No request timed out or failed. Confidence is |2p − 1|, where p is the model's probability that the concern is still present. A high confidence means p is close to 0 (addressed) or to 1 (still present).

- Of the 8 addressed items, 7 lean towards "already addressed", with confidences from 0.04 to 0.82, and 1 leans towards "still applies" (confidence 0.44).
- Of the 14 items still present, 11 lean towards "still applies" and 3 lean towards "already addressed". Those 3 are wrong, with confidences 0.20, 0.20 and 0.32: a code-scanning alert on a regular expression that was still open, checked at the code it was raised on and at the final code, and the owner's question whether a passage was worth keeping, checked at the code it was written on.

| Threshold | Answers clearing it, of 22 (more is better) | Agreeing with the label | Addressed comments recognised, of 8 (more is better) | Wrong "already addressed" (the costly kind: a comment would go unfixed) | Wrong "still applies" (costs a needless Explore check) |
|---|---|---|---|---|---|
| 0.5 | 12 | 12 | 3 | 0 | 0 |
| 0.6 | 8 | 8 | 2 | 0 | 0 |
| 0.7 | 8 | 8 | 2 | 0 | 0 |
| 0.8 | 7 | 7 | 1 | 0 | 0 |
| 0.9 | 6 | 6 | 0 | 0 | 0 |
| 0.95 | 0 | 0 | 0 | 0 | 0 |

#### The threshold rule for address.still_applies

The lowest threshold measured with no wrong "already addressed" answer is 0.5. There the site would answer 12 of the 22 items, all correctly, and recognise 3 of the 8 addressed comments. The data do not support adopting it:

- it rests on 8 addressed items and 22 items in all, below the planned minimum;
- the gap between the most confident wrong "already addressed" answer (0.32) and 0.5 comes from 3 answers;
- sending the same comment and code with only the marker changed moved p by up to 0.10, so one more wrong answer near 0.3 to 0.4 would move the rule's result.

At the provisional 0.9 the site recognises none of the 8 addressed comments, so in on mode it would only ever confirm that a comment still applies.

**Result.** The site stays `off`, with shadow collection, and 0.9 is not replaced; questions.yaml has no entry for jev-1.13.0. Each of the 24 items, with its label, the reason it was skipped or the answer's p and confidence, whether the commented lines were still there, and p with the marker reversed, is in [`evals/results-2026-10-07-address-s1/address-still-applies.jsonl`](../evals/results-2026-10-07-address-s1/address-still-applies.jsonl).

## Providers

Both providers serve the same contract, `POST <baseUrl>/v1/systemone` with `{state, questions, model}`, so one client works with either.

| | TypeSafe (Jev) | imajev |
|---|---|---|
| Where it runs | TypeSafe's hosted API, `https://api.typesafe.ai` | your machine; default `http://127.0.0.1:8765` |
| Key | required, read from `TYPESAFE_API_KEY` | none |
| Model | `jev-1.13.0` by default, a pinned version | whichever model the server loaded |
| State limit | 32k tokens for the state plus the longest question | about 8k tokens (32 KB) |
| **What leaves this machine** | **everything Flow sends: diffs, review comments, transcript excerpts** | **nothing** |

Sources: [TypeSafe API](https://docs.typesafe.ai/api) and [models](https://docs.typesafe.ai/models); the imajev [README](https://github.com/mohit67890/imajev).

`custom` is any other server with the same contract, at the `baseUrl` you give.

A server on this machine is reached directly, never through `HTTP_PROXY` or `ALL_PROXY`: through a proxy, the key and the state would leave the machine in plain text. A remote server is reached the way your environment's proxy settings say, over https. Whether the host is this machine is judged as urllib decodes it, since that is the host the request goes to: `[::ffff:127%2e0.0.1]` is this machine, and `[::1%3a1]` (`::1:1`) is not.

## Configure it

Put the provider in **your user settings**, `~/.claude/settings.flow.json`. Flow reads the provider, address, model and key variable from that file and from the plugin default only. A repository's `.claude/settings.flow.json` or `.claude/settings.flow.local.json` comes with the checkout. If Flow read the provider from there, a cloned repository could send your diffs, and the key in any environment variable it names, to its own server. Values set there are ignored, with a warning.

TypeSafe:

```json
{
  "systemOne": {
    "provider": "typesafe",
    "uses": { "review.dedup": "shadow" }
  }
}
```

with `export TYPESAFE_API_KEY=...` in your shell. The key never goes in a settings file.

imajev, after starting its server as its README describes:

```json
{
  "systemOne": {
    "provider": "imajev",
    "timeoutMs": 20000,
    "uses": { "review.dedup": "shadow" }
  }
}
```

A local model is slower than the 3-second default allows. On an M1 Mac mini with 16 GB, imajev-4b answered three questions in about 5.8 s with the README's settings (four option orders averaged, `--rotations 4`) and in about 2.0 s with `--rotations 1`. TypeSafe answered the same three in about 1.5 s. A request that runs past `timeoutMs` gets no answer, so Flow keeps its current behavior.

| Setting | Default | Meaning |
|---|---|---|
| `provider` | `none` | `none`, `typesafe`, `imajev` or `custom` |
| `baseUrl` | the provider's | Must be `https://` unless the host is this machine (`localhost`, `127.0.0.0/8`, `::1`, or an IPv4-mapped `::ffff:127.0.0.0/104`) |
| `model` | the provider's | Sent with each request. Keep TypeSafe on a pinned version: `jev-latest` moves between releases, and thresholds are measured per version |
| `apiKeyEnv` | the provider's | Name of the environment variable that holds the key, sent as `Authorization: Bearer` |
| `timeoutMs` | `3000` | Limit for the request, from connecting to the last byte of the reply, clamped to 200-30000. Reading and shortening the state happen before it and are not counted. A whole number of up to 9 digits (`20000.0` counts as `20000`); anything else is warned about and `3000` is used, except a value longer than 4096 characters, which is `invalid-settings` |
| `stateTokenCap` | `0` | Longest state sent, in tokens estimated as 4 characters each. `0` uses the provider's default (TypeSafe 28000, imajev and custom 7000). A whole number of up to 9 digits; anything else is warned about and the provider's default is used, except a value longer than 4096 characters, which is `invalid-settings` |
| `uses.<site>` | `off` | `off`, `shadow` or `on` per decision point. The one setting a repository may set, and it can only lower your own mode (`on` > `shadow` > `off`): the mode used is the lower of your user settings (or the plugin default) and the repository's. So a repository can turn a site down or off, but can neither switch it `on` nor start `shadow`, which would send the request, and so the state from your checkout, to your provider. A repository value above yours gets your own mode, with one warning |

**Working inside the Flow repository itself.** When the plugin being run sits inside the repository you are working in, as it does in synapti-marketplace, `cascade-resolve.sh --no-repo-settings` refuses to answer. A call made through that copy of the plugin is then "no answer" with the reason `settings-refused`. This is deliberate: it is the same rule that keeps a pull request from supplying its own review settings. `/flow:address` does not use that copy: it finds `flow-s1-mode.sh` and `flow-s1.sh` with a lookup that skips any copy inside the repository, so it uses an install outside the repository when there is one, and with none both of its decision points stay off. To try a provider here, install Flow outside the repository.

## Modes

- **off**: the decision point is not asked. Nothing is sent.
- **shadow**: the question is asked and the answers are recorded next to the decision Flow made without them. The caller still gets "no answer", so Flow's behavior does not change. Use it to collect the data a threshold is chosen from.
- **on**: Flow uses the answers when every question at the decision point answered with enough confidence.

## The rule every decision point follows

An answer may add caution: demote a finding's confidence, send a decision to the user, move a criterion from PASS to NEEDS-HUMAN-REVIEW, add a warning. It may not, by itself, drop a finding, lift a block, or move a verdict toward done. Security findings are never demoted or merged. A decision point that needs an exception, such as merging duplicate findings, is switched on by default only after a measurement shows a gain.

## Calling the client

```bash
plugins/flow/bin/flow-s1.sh ask --site review.dedup --state-file "$STATE" \
  [--state-format text|json] [--current "$TODAYS_DECISION"] [--run-id "$RUN_ID"] [--ref "$ITEM"]
```

Always call `flow-s1.sh`, never `_flow_s1.py` directly: the wrapper reads the settings from the right tiers and removes the working directory from `PYTHONPATH` before Python starts, which Python cannot do for itself.

A call site that needs the mode before it asks, for example to skip its System One step entirely when the site is off, takes it from `bin/flow-s1-mode.sh`, the one place that applies the mode rule (`uses.<site>` above). `flow-s1-mode.sh <site>` prints `shadow` or `on` when a provider is configured and the site is in one of those modes, and nothing otherwise. `flow-s1-mode.sh --all <site>` prints the mode the client itself uses, `off` included, with a warning when a repository value was lowered, and `off` with a warning when your own settings cannot be read (the plugin loaded from inside the repository). It sends nothing and writes nothing. Never read `systemOne.uses` directly: a second copy of the rule can disagree with the client.

| Exit | Meaning |
|---|---|
| `0` | Answered. stdout is one JSON line: `{"site","provider","model","truncated","answers":{<question id>:{...}}}` |
| `3` | No answer. stdout is empty; stderr says `flow-s1: no answer: <reason>` on one line, sometimes followed by a detail in parentheses, whose line breaks become spaces and whose other control characters are escaped. **Do what Flow did before.** |
| `2` | Usage error: a missing or malformed argument. `--site` is lowercase words joined by dots; `--ref` starts with a letter or digit, uses only letters, digits and `.` `_` `:` `/` `#` `@` `+` `-`, and is at most 200 characters; `--run-id` starts with a letter or digit, uses only letters, digits, `.`, `_` and `-`, and does not contain `..` |

Each answer in `answers`:

| Type | Fields |
|---|---|
| noul | `type`, `p` (probability of yes), `confidence` = \|2p − 1\| |
| choice | `type`, `choice`, `probabilities`, `confidence` |
| score | `type`, `score`, `probabilities`, `confidence` |

`unknown_probability` is copied when the provider sends it (imajev does); like a confidence, it must be a number from 0 to 1 or the call is `malformed`. For a choice or a score, confidence is the provider's own, and it must be a number from 0 to 1 or the call is `malformed`. When it is missing (`null` counts as missing), it is TypeSafe's documented formula: with n options and the largest probability m, it is (n·m − 1)/(n − 1). For a noul that formula is \|2p − 1\|, so p = 0.95 and p = 0.05 are equally confident.

A choice or a score must agree with itself as the [TypeSafe API](https://docs.typesafe.ai/primitives/choice.md) defines it, or the call is `malformed`:

- `probabilities` has an entry for every option (for a score, every level, keyed `"0"`, `"1"`, ...), and they sum to 1;
- the choice is the most probable option;
- the score is each level times its probability, added up ([Score](https://docs.typesafe.ai/primitives/score.md)).

TypeSafe sends each value rounded to two decimals, so the sum and the score allow 0.005 for every rounded value they combine: for n options the sum may be off by 0.005·n, and the score by 0.005·(1 + n(n − 1)/2). The choice gets no allowance, because rounding keeps the order of the values: the chosen option's probability must be the largest, or tied with it.

A call is all-or-nothing. If any question abstains, is missing, is malformed, or is below its threshold, the whole call is "no answer". Ask independent judgments in separate calls if one may fail without the others.

With `--state-format json` the state is sent as a JSON value, so questions can refer to its fields by name (`` `finding.location` ``). When it is over the limit, every string longer than one common length is cut to that length, the largest at which the state fits; shorter strings keep their full text. A text state is cut at the limit. Either way `truncated` is `true`.

### Reasons for "no answer"

| Reason | When |
|---|---|
| `provider-none` | No provider is configured (the default) |
| `mode-off` | The decision point is `off`, or its mode is not one of `off`, `shadow`, `on` (with a warning) |
| `shadow` | The decision point is in `shadow` mode and every question answered |
| `settings-refused` | `cascade-resolve.sh` refused to read the provider settings, for example because the plugin is inside the repository |
| `invalid-settings` | Unknown provider; a `baseUrl` that is not an http(s) URL, cannot be parsed, or holds a space, a control character, a character outside ASCII (write a host outside ASCII in its `xn--` form, since the request carries the host as written), a user (with or without a password), a query or a fragment, even an empty one (the request goes to `<baseUrl>/v1/systemone`), a port that is not 1 to 5 ASCII digits from 0 to 65535, brackets that hold anything but an IPv6 address, as written and as urllib decodes it, or a percent sign in the host or port outside an IPv6 zone id; a provider setting (`provider`, `baseUrl`, `model`, `apiKeyEnv`, `timeoutMs`, `stateTokenCap`) longer than 4096 characters; a missing `baseUrl` for `custom`; an `apiKeyEnv` that is not a variable name; a key a request header cannot carry (a line break, or a character outside Latin-1), which is never printed; or a model id that is not plain text (a control character, a lone surrogate, a line separator). A warning names the rule and never prints the baseUrl, since a URL can carry a password or a key in any part |
| `insecure-url` | A plain `http://` address for a host other than this machine |
| `no-api-key` | TypeSafe with its key variable unset or empty |
| `unknown-site` | The questions file has no entry for the site |
| `no-threshold` | A question has no threshold |
| `questions-invalid` | The questions file is not a regular file (a FIFO is not waited on), or cannot be read or parsed (any error while reading it: a byte that is not UTF-8, a merge key (`<<`), an integer of more than 4300 digits, a value YAML cannot build, nesting too deep to parse), or has the wrong shape: a question id or a threshold's model id that is not a string; instructions that are not text, an object or a list; a choice without its options, with option names that are not strings, or with an option described by something other than text, an object, a list or null; a score without 2 to 10 levels, or with a level that is not text, an object or a list; noul criteria that do not describe exactly `"true"` and `"false"`; anywhere in a question, a key that is not a string or a value JSON has no form for (a date, a set, a YAML ordered map or pairs); questions that would be more than 1 MiB when sent, escapes included (YAML aliases repeat what they name, so a short file can stand for a large body); or questions this interpreter cannot encode for the request (`.inf`, a lone surrogate, nesting deeper than its JSON encoder goes). Quote `yes`, `no`, `on`, `off`, `~`, numbers and dates wherever text is meant |
| `python-missing` | python3 or PyYAML is not available |
| `state-invalid` | The state file cannot be opened or is not a regular file, such as a directory, a device or a FIFO, which is not waited on (flow-s1.sh passes only a readable regular file, so this is seen when the client is run directly); or `--state-format json` and the file cannot be read as JSON (not JSON, or an integer of more than 4300 digits), is nested too deeply to process, or cannot be encoded for the request (a lone surrogate, `NaN`, `Infinity`, a number too large for a float such as `1e400`). How deep is too deep depends on the interpreter and on whether the state must be shortened: Python 3.14.6 takes more than 5000 levels, or about 990 when shortening. The exact limit moves by a level with what the innermost level holds |
| `state-too-large` | A text state file larger than 64 MiB, or a JSON state file larger than 8 MiB (parsing JSON takes many times the file's size; any format other than text is read as JSON), before it is read; or a JSON state that no shortening of its strings brings under the limit |
| `timeout` | The request took longer than `timeoutMs` |
| `connection` | The server could not be reached |
| `redirect` | The server answered with a redirect. Redirects are never followed, so a key cannot be carried to another host |
| `http-<status>` | Any status other than 200, for example `http-429`, `http-500`, `http-529` |
| `malformed` | The reply is larger than 4 MiB (only that much is read), is not JSON (or holds an integer of more than 4300 digits, or is nested deeper than this interpreter's JSON parser goes), has no `answers`, an answer has the wrong type or fields, a choice is not one of the question's options, a score is outside its levels, a choice or a score contradicts its own probabilities (see above), a choice's or a score's confidence is not a number from 0 to 1 (`null` counts as absent), an `unknown_probability` is not a number from 0 to 1 (`null` counts as absent), an `abstained` is not true or false (`null` counts as absent), its model id is not a string (`null` counts as absent), or a string in it (the model id, an option name) contains a control character, a lone surrogate or a line separator. A reply with no model id is taken as answered by the configured model |
| `missing-answer` | The reply has no answer for a question |
| `abstained` | The provider declined to answer a question (imajev's `abstained: true`) |
| `below-threshold` | An answer's confidence is below the question's threshold |
| `internal-error` | A defect in the client's own code, including its checks of the settings and the questions once they are read; stderr names the error type. No traceback is printed. Writing records never causes it: a failure there is a warning, and the call's answer or reason stands |

## Questions and thresholds

Every question Flow asks, and the confidence each answer needs, is in [`system-one/questions.yaml`](../system-one/questions.yaml), so a reviewer can read all of them in one place. An entry looks like this:

```yaml
sites:
  review.dedup:
    questions:
      same_defect:
        type: choice
        instructions: "Which consolidated finding reports the same defect as `new`?"
        criteria: {F1: null, F2: null, none: "no consolidated finding reports it"}
    thresholds:
      same_defect:
        default: 0.8
        models: {jev-1.13.0: 0.75}
```

`questions` is sent to the provider as YAML reads it, in the shapes TypeSafe's API documents: instructions are text, an object or a list; a choice maps each option to a description (text, an object, a list or null); a score lists 2 to 10 levels (each text, an object or a list); a noul's optional criteria describe `"true"` and `"false"`. YAML reads unquoted `yes`, `no`, `on`, `off`, `~`, numbers and dates as other types, so Flow refuses the file (`questions-invalid`) where one of these fields, an id or an option name would not be sent as written, or where a value cannot be sent as JSON. Inside an object or a list, values are sent as YAML reads them. The question id is not sent to the model, so the instructions must carry the whole meaning. A threshold is looked up by the model id the reply names, then `default`. A threshold is set from measurements on that model version, and a new version needs its own measurement before its entry is added.

## Records

In `shadow` and `on` mode, every request writes one JSON line per question:

```json
{"ts": "...", "site": "review.dedup", "question": "same_defect", "mode": "shadow",
 "provider": "typesafe", "model": "jev-1.13.0", "result": "answered",
 "answer": {...}, "current": "keep-separate", "ref": "pr:275/inline:12345",
 "state_sha256": "..."}
```

`result` is `answered` or the reason the question failed. `current` is the decision Flow made without System One, passed with `--current`. `ref` names the item the questions were about, passed with `--ref` (null without it), so a shadow record can be matched to that item when shadow records are compared with the decisions taken; it is never sent to the provider. The client never records the state; its sha256 identifies it. One decision point keeps the state it sent: `address.still_applies`, when a run directory exists, writes the state of each comment it asked about to `.flow/runs/<run-id>/system-one-state/<comment id>.json`, in shadow and in on mode, so a shadow record can be judged later against what the model saw. That file holds the comment body, its diff hunk, and up to 81 lines of the pull request's code around the place the comment refers to.

Records go to `.flow/runs/<run-id>/system-one.jsonl` when `--run-id` names an existing run. Otherwise they go to `system-one.jsonl` in the per-user state directory (`~/.claude/flow-state`, or a `FLOW_STATE_DIR` you set; one the repository chose is ignored, see [README: Per-user locations](../README.md#per-user-locations)). Nothing is written through a symlink or to anything but a regular file, and no run directory is created. A record that cannot be written, including one whose lock another process holds for more than a second, is a warning and does not change the answer.
