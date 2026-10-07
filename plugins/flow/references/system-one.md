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

The client is in place. Each decision point is added, with its questions and thresholds, by the change that wires it in, and ships `off` until a written comparison of its shadow records against the decisions Flow took supports a threshold and switching it on. The decision points that use it:

- **`classify.serves-issue`** (off; threshold 0.6, provisional: the replay comparison did not have the data to set it, see [Shadow comparisons](#shadow-comparisons)). In `/flow:commit` Phase 3 and `/flow:start` CODE step 8, through `bin/flow-classify-s1.sh`, for each file classified uncertain: does this change serve the issue's objective? In `on` mode, each uncertain file's row in the prompt gets `serves issue: <p> (<model>)` in its Notes, where p is the model's probability that the change serves the issue (0 to 1, higher means more likely). The file stays uncertain and you still choose include or exclude. Red-flag files are never asked about or sent, and at most 8 files are asked per prompt. In `shadow` mode nothing new is shown; after you choose, your choice is recorded next to the model's answer (`current` is `include` or `exclude`). A repository's settings can lower this site's mode below your own, but never raise it (see `uses.<site>`). In `shadow` mode the record block sends each uncertain file's diff, with the issue, to the provider configured in your user settings. With no issue on the branch, no uncommitted change to the file, or no answer, the prompt is what it would be without System One. What is sent for each file: the issue's number, title and body, the file's path and git status, its uncommitted diff (the whole file when it is untracked, `(binary)` for a binary file, at most the first 400 lines and 64 KiB), and the signals that matched it. The issue is fetched once per prompt. Only a single file is read: a path that names a directory gets no estimate. Path patterns keep files such as `.env` from being sent, but a secret written into the body of an ordinary file is in its diff, and that diff goes to the provider you configured, which for TypeSafe is off this machine. Shadow records keep every answer, below the threshold or not.
- **`goal.judge`** (off; threshold 0.5, provisional: the replay comparison could not set it, see [Shadow comparisons](#shadow-comparisons)). In `evaluator-loop` mode, on a turn where every incomplete criterion has no verification command and no command failed or went unexecuted, the Stop hook asks one question per criterion: does its recorded evidence show it holds? Nothing is asked about a goal that is not in the trust ledger; Haiku decides its turns. A criterion with no evidence, or only another model's report, is not sent: no answer could make it supported, so it is decided unsupported without a call. At most 10 criteria are asked about in one stop: in `on` mode, with more than 10 to ask about, nothing is sent and Haiku decides; in `shadow` mode the first 10 are asked about. In `on` mode the answers decide the turn when every call answered: all supported approves the stop with the instruction to finalize through `/flow:goal evaluate`; a criterion is supported when its call answered with a confidence at or above the site threshold and p >= 0.5 (with the shipped threshold of 0.5, p >= 0.75); an unsupported criterion keeps the agent working and is named by id; a lowest confidence under 0.6 gives needs-human-review. Any call without an answer hands the whole turn to the Haiku judge, as without System One. The answer never changes the goal's lifecycle: when the supported set stays the same for `flow.goals.failAfterStuckTurns` turns, the stop is allowed with needs-human-review and the goal stays active. `shadow` asks after Haiku's decision and records the answers beside it. Sends the goal's id and outcome, the criterion's id and text, the evidence coverage Flow computed, and for each evidence sidecar that names the criterion its id, type, command, exit code, limitations, tested cases and up to 8 KB of its output. See [stop-hook-goal-enforcement.md](stop-hook-goal-enforcement.md).
- **`goal.warn-evidence`** (off; threshold 0.6 on jev-1.13.0, set from the replay comparison in [Shadow comparisons](#shadow-comparisons); 0.9 on other models). In `warn` mode, for each criterion with no verification command whose evidence includes a deterministic sidecar, the Stop hook asks the same question. Nothing is asked about a goal that is not in the trust ledger. A criterion with no evidence, or only another model's report, is not asked about and stays under "Missing evidence for:". At most 10 criteria are asked about in one stop, the first 10; the rest stay under "Missing evidence for:". In `on` mode a criterion whose call answered with a confidence at or above the site threshold and p >= 0.5 (on jev-1.13.0, threshold 0.6, p >= 0.8; on other models, threshold 0.9, p >= 0.95) leaves "Missing evidence for:" and is listed on its own line, "Supported by recorded evidence (System One; not a verdict)". When nothing else is reported, the stop is allowed with `FLOW_GOAL_EVIDENCE_RECORDED`, never "complete". The goal file is never written. `shadow` records the answers and changes nothing the user sees. Sends the same state as `goal.judge`.

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

**Working inside the Flow repository itself.** When the plugin being run sits inside the repository you are working in, as it does in synapti-marketplace, `cascade-resolve.sh --no-repo-settings` refuses to answer. Every call is then "no answer" with the reason `settings-refused`. This is deliberate: it is the same rule that keeps a pull request from supplying its own review settings. To try a provider here, run Flow from an installed copy of the plugin.

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

Every question Flow asks, and the confidence each answer needs, is in [`system-one/questions.yaml`](../system-one/questions.yaml), so a reviewer can read all of them in one place. It holds one entry per decision point listed above. An entry looks like this:

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

## Shadow comparisons

### `classify.serves-issue` (TypeSafe jev-1.13.0, 2026-10-07)

There are no records from live use yet. This comparison uses 180 replayed records: each one was sent to TypeSafe, model `jev-1.13.0`, in shadow mode on 2026-10-07 between 06:05 and 06:16 UTC, through the branch's code at commit `b5bc8541`, which has the same question, helper and client as this release. Each record was matched to its label by the item it judged, and the state the label was built from matched the state sent on all 180. No label was set from an answer.

**What the items are.** From 90 merged pull requests that close an issue (merged between 2026-01-15 and 2026-10-01), two items each: a file the pull request changed, labelled include (90), and a file changed by a different pull request merged close in time, which the issue's own pull request never touched, labelled exclude (90). The label stands in for the user's include or exclude choice, so agreement below means how often the model matches that label, not whether either is correct. For every file this site asks about, Flow's own classification is "uncertain", so there is no Flow decision to compare the answer with. Every item has a record, so no record is missing.

**How this set differs from what the site sees in use.** The site is asked only about files classified uncertain. By the classification signals, 5 of the 180 items fall in that band (3 include, 2 exclude). The others are files a pull request changed on purpose, mostly with strong signals. In 52 items the issue names the file's path or file name (43 include, 9 exclude); on its own, the rule "include when the issue names the file" matches 124 of 180 labels (69%). The exclude labels are less certain than the include labels: 61 of the 90 come from the same plugin as the issue's own change, and 24 from a pull request that shares files with it.

**Checks that the measurement is not broken, made before the results were read.**

| What a broken result would look like | Found |
|---|---|
| Answers bunched near p = 0.5 | 5 of 180 answers have p between 0.4 and 0.6 |
| Only one answer given | 81 answers say the change serves the issue (p above 0.5), 99 say it does not |
| Agreement no better than always answering include (50% here) | 89% of all answers agree with the label (161 of 180) |
| The easy items carry the result | On the 128 items whose issue does not name the file, 85% of answers agree (109); always answering exclude would agree on 63% of them |
| No examples of the band the site is for | 5 items: 3 agree; the 2 include files the model got wrong were answered with p 0.03 and 0.05 |

**Results.** Every request was answered: no timeouts, transport errors or malformed answers. 23 answers fell below the provisional 0.6 (11 include, 12 exclude); shadow records keep them, and they are counted in the table below. By label, 76 of 90 include files (84%) and 85 of 90 exclude files (94%) agree: the model misses a file that served the issue more often than it calls an unrelated file related.

Confidence is |2p − 1|, from 0 (no lean either way) to 1 (certain). Answers that agree with the label have a median confidence of 0.88 (middle half 0.80 to 0.92); answers that disagree have a median of 0.52 (middle half 0.26 to 0.80). Disagreements are mostly less confident, but 5 of the 19 have confidence 0.80 or more.

For each threshold, coverage is the share of files that would get an estimate, and agreement is the share of those estimates whose lean (p above or below 0.5) matches the label. Higher is better for both. The range is the 95% Wilson interval for agreement.

| Threshold | Coverage | Agreement | 95% range |
|---|---|---|---|
| 0.50 | 88% (159) | 94% (149) | 89% to 97% |
| 0.55 | 88% (158) | 94% (149) | 90% to 97% |
| 0.60 | 87% (157) | 94% (148) | 90% to 97% |
| 0.65 | 84% (151) | 95% (144) | 91% to 98% |
| 0.70 | 82% (147) | 95% (140) | 91% to 98% |
| 0.75 | 77% (139) | 96% (133) | 91% to 98% |
| 0.80 | 72% (130) | 96% (125) | 91% to 98% |
| 0.85 | 57% (102) | 96% (98) | 90% to 99% |
| 0.90 | 42% (75) | 95% (71) | 87% to 98% |
| 0.95 | 4% (8) | 100% (8) | 68% to 100% |

**Threshold: kept at 0.6, provisional.** The minimum this site needs before a threshold is chosen is 40 judged uncertain files, with at least 10 included and 10 excluded. The replayed set has 5 such files (3 and 2) and live use has none, and no rule for picking a value from the table has been set. On this easier set the model separates related from unrelated changes well, and between 0.6 and 0.85 agreement changes by less than the width of its 95% range, so the table gives no reason to move from 0.6 either. The threshold has no entry for `jev-1.13.0`, and the site stays `off`.

### `goal.judge` and `goal.warn-evidence` (TypeSafe jev-1.13.0, 2026-10-07)

**Result.** `goal.warn-evidence` uses a threshold of 0.6 on jev-1.13.0 (a criterion leaves "Missing evidence for:" when p >= 0.8); other models keep 0.9. `goal.judge` keeps its provisional threshold of 0.5, because this data cannot apply its rule. Both sites stay `off`.

**The data.** There are no live records yet. Every number below comes from a replay: past goal evidence from this repository, recorded between 2026-05-25 and 2026-09-25, sent once to TypeSafe model jev-1.13.0 in `shadow` mode on 2026-10-07 between 06:06 and 06:18 UTC. The items come from 13 goals (7 dossier, 6 Flow); no goal supplies more than 24. Each item carries a label set before its answer was read, from something other than the model:

| Kind of item | Label | `goal.judge` items | `goal.warn-evidence` items | How the label was set |
|---|---|---|---|---|
| Real criterion with evidence | supported | 63 | 63 | Every attached evidence item exited 0 and the goal was accepted. Exit 0 does not prove the evidence covers the whole criterion |
| Real criterion with no evidence attached | not supported | 11 | not asked | The state has no evidence |
| Evidence later replaced | supported | 9 | 9 | Exited 0; why it was replaced was not recorded (least reliable label) |
| Evidence moved to a criterion of the other plugin | not supported | 63 | 63 | Built for the test: the evidence is about different code |
| Real evidence changed to exit 1 with no output | not supported | 32 | 32 | Built for the test |
| **Total** | | **178** (72 supported, 106 not) | **167** (72, 95) | |

**Caveats.**

- *The replay is a proxy.* Live, both sites ask only about criteria with no verification command. Every replayed criterion has one, so the replay measures the model on evidence from commands (command lines, exit codes, limitations, test output), not on the prose, reviews and reports a command-less criterion usually carries. Live shadow records are the measurement of that case.
- *Every "not supported" item is easy.* All of them are built (evidence from other code, a failed exit) or have no evidence. No item is a real criterion whose evidence was present but not enough, so the share of wrong "yes" answers here is a lower bound for live use.
- *Test output drives the answer.* Of the 63 real supported criteria, 32 show their command's output and 31 show only the command, exit code and limitations. `goal.judge` said yes to 29 of the 32 and 10 of the 31; `goal.warn-evidence` to 30 of 32 and 13 of 31. Evidence recorded without its output is often not counted as support.
- *An answer near a threshold can change between runs.* The two sites asked the same question about the same 167 states; p differed by up to 0.10, and 4 answers moved across 0.5.

#### `goal.judge`

The rule for its threshold: choose a value below 0.6 from, for each candidate, the share of turns System One would decide and its rate of wrong "achieved" verdicts (lower is better). Per criterion, the sweep is:

| Threshold | Criteria answered (higher decides more) | Yes: answered with p >= 0.5 | Wrong yes (lower is better) | Supported items given a yes (higher is better) |
|---|---|---|---|---|
| 0.3 | 161 of 178 (90%) | 41 | 1 | 40 of 72 |
| 0.4 | 151 (85%) | 36 | 1 | 35 of 72 |
| 0.5 | 141 (79%) | 31 | 1 | 30 of 72 |
| 0.55 | 134 (75%) | 27 | 1 | 26 of 72 |

The 11 items with no evidence are counted as asked here; live, `goal.judge` does not send such a criterion and decides it unsupported without a call.

The one wrong yes (p 0.78, confidence 0.56) paired "the full dossier test suite passes" with a passing run of Flow's full suite. Its confidence is under 0.6, so in a turn it would have given needs-human-review, not "achieved".

Grouping each goal's real criteria into one turn (13 turns, every goal accepted in the end): at 0.5 System One would have decided 1 turn, saying "not achieved"; at 0.3, 5 turns (4 "not achieved", 1 needs-human-review). It gave "achieved" on no turn at any threshold, and no turn in the set should have been "not achieved". So the rate of wrong "achieved" verdicts cannot be measured here, and the rule cannot choose a threshold. **0.5 stays, provisional, until live records exist.** On this evidence, in `on` mode the site would hand most turns to Haiku and keep the agent working on goals that were in fact met.

#### `goal.warn-evidence`

The rule for its threshold: the precision of "supported" (the share of removed criteria whose label is supported) comes first, because a wrong removal hides a real gap; coverage (the share of supported criteria that would be removed) decides between equally precise thresholds. Higher is better for both.

| Threshold (p needed) | Removed | Wrongly removed (lower is better) | Precision | Coverage |
|---|---|---|---|---|
| 0.6 (p >= 0.8) | 24 | 0 | 24 of 24 | 24 of 72 (33%) |
| 0.8 (p >= 0.9) | 5 | 0 | 5 of 5 | 5 of 72 (7%) |
| 0.9 (p >= 0.95) | 0 | 0 | none removed | 0 of 72 |
| 0.95 (p >= 0.975) | 0 | 0 | none removed | 0 of 72 |

The highest p the model gave any item was 0.94, so at 0.9 or above nothing is ever removed. 0.6 and 0.8 are equally precise on this set, and 0.6 removes 24 criteria instead of 5, so **0.6 is the threshold for jev-1.13.0**. Of its 24 removals, 19 are real criteria labelled supported because their evidence exited 0 in a goal that was accepted, and 5 are criteria whose evidence was later replaced (the least reliable label). The margin is narrow: the one wrong yes in the set, the same item as for `goal.judge`, had confidence 0.56, just under 0.6. Every negative here is built for the test, so live precision may be lower; the site stays `off` until live shadow records confirm it.

## Records

In `shadow` and `on` mode, every request writes one JSON line per question:

```json
{"ts": "...", "site": "review.dedup", "question": "same_defect", "mode": "shadow",
 "provider": "typesafe", "model": "jev-1.13.0", "result": "answered",
 "answer": {...}, "current": "keep-separate", "ref": "pr:275/inline:12345",
 "state_sha256": "..."}
```

`result` is `answered` or the reason the question failed. `current` is the decision Flow made without System One, passed with `--current`. `ref` names the item the questions were about, passed with `--ref` (null without it), so a shadow record can be matched to that item when shadow records are compared with the decisions taken; it is never sent to the provider. The state itself is never recorded; its sha256 identifies it.

Records go to `.flow/runs/<run-id>/system-one.jsonl` when `--run-id` names an existing run. Otherwise they go to `system-one.jsonl` in the per-user state directory (`~/.claude/flow-state`, or a `FLOW_STATE_DIR` you set; one the repository chose is ignored, see [README: Per-user locations](../README.md#per-user-locations)). Nothing is written through a symlink or to anything but a regular file, and no run directory is created. A record that cannot be written, including one whose lock another process holds for more than a second, is a warning and does not change the answer.
