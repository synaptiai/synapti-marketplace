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

Each decision point is added, with its questions and thresholds, by the change that wires it in. Each ships `off`: you switch it to `shadow` or `on` in your user settings. A repository's settings can only lower the mode you set (see `uses.<site>` below). Its default changes only after a written comparison of shadow records against the decisions Flow actually took.

| Site | Where it is asked | What `on` does | Status |
|---|---|---|---|
| `quality.tests-ran` | After a Bash call that Flow records as a passing built-in test run | Records the run as not passing when the output shows that no test ran or every test was skipped | off; threshold 0.9, provisional (compared on constructed test runs only) |

### `quality.tests-ran`

`hooks/scripts/record-quality-run.sh` records test, lint, typecheck and build runs for the task-completion gate, and takes a run's result from its exit code. A runner that finds no tests, or skips all of them, can still exit 0. When this site is `shadow` or `on`, the hook asks one choice question about a run that passed: did at least one test execute (`executed`), did the runner find or run none (`none_ran`), was every test skipped (`all_skipped`), or does the output not say (`unclear`)?

- **When it asks**: only for a PostToolUse call whose command matched a built-in `test` pattern, that finished, and that was not masked (`|| true`), interrupted or a failure event. Claude Code sends no exit code for a Bash call that succeeds, so a PostToolUse call counts as exit 0 unless it was moved to the background, timed out, or carries Claude Code's reading of a non-zero exit as informational (grep's "No matches found"); those are not asked. Claude Code reports one status for the whole Bash call, so the call counts as exit 0 only when that status can only be the test command's: the test command is the whole command, or follows nothing but `cd <dir> &&`, variable assignments such as `FOO=1` (where the directory and the value may hold only letters, digits and `. _ / ~ + - : @ % , =` (a leading `~` only in the directory), and only space and tab separate the words), and one leading line holding only `set` with the options `-e`, `-u`, `-x`, `-v` and `-o pipefail`, `errexit`, `nounset` or `xtrace` (`set -euo pipefail`). Redirections such as `2>&1` are allowed. Any other shape records no exit code and is not asked: a pipe, `;`, `&&` or `||` after the test command, a subshell, group or substitution, a heredoc or here-string anywhere, a background `&`, a command over more than one line, and prefixes such as `env`, `time` or `timeout`. A `|` or `;` inside a quoted argument counts too. Such a run does not pass the task-completion gate, which asks for the test command to be run on its own. Lint, typecheck, build and the `project` kind (`verify.sh`, `check.sh` and `testing.qualityCommandPatterns`) are never asked, so a repository's own pattern cannot widen what is sent. The hook takes the site's mode from `bin/flow-s1-mode.sh`, the same rule the client applies, so with the site off, or with no provider, no process starts and the ledger entry carries no `s1_state_sha256`.
- **What is sent**: the command (first 2000 characters), the exit code, and the output as lists of lines: the first 40 and the last 200 lines of stdout and the last 40 of stderr, each line cut to 400 characters. When the state is over `stateTokenCap`, the client cuts every long line to one common length and keeps every line, so the runner's summary at the end is still sent. At a very small cap the summary line itself is cut too. The output of every asked run goes to your provider, in `shadow` as well as `on`. A repository's settings can turn this site down or off, but cannot set it to `shadow` or `on` above your own mode, so a repository cannot start sending its test output to your provider.
- **What `on` does**: a `none_ran` or `all_skipped` answer at or above the threshold adds `output_check` (the verdict, the site, the model and the confidence) to the ledger entry. The run then does not count as passing, and the gate says "the last quality run exited 0 but its output showed no tests ran" (or "every test was skipped"). `executed`, `unclear`, a lower confidence and every kind of no answer leave the run passing. A failed run is never asked, so no answer can turn a failure into a pass.
- **Records**: each request writes a record with `current: "pass"` and `ref: "quality-run:<tool_use_id>"` (`quality-run:session:<session id>` when the tool call's id cannot be used as a ref). The ledger entry carries `s1_state_sha256`, equal to the record's `state_sha256`, so records and ledger entries can be matched.
- **Threshold**: 0.9 for every model, provisional. It was set before any measurement, high because a wrong downgrade blocks a run that really passed. The comparison below, on TypeSafe jev-1.13.0, kept it: it found no wrong downgrade at any threshold, but it had no runs from real use to show that, so no model has a value of its own.
- **Time**: the hook waits for the answer, at most `timeoutMs` plus the client's start-up. Claude Code allows a PostToolUse command hook 600 seconds by default (the hooks reference at code.claude.com/docs/en/hooks, read 2026-10-01), so the hook is not cut off before it records the run. The output is written to a temporary file for the client; if the hook is stopped while it waits, the file is removed once the client exits.

#### Comparison with the decisions Flow took (TypeSafe jev-1.13.0, 2026-10-07)

**What was measured.** 49 test runs, each sent once to TypeSafe with model jev-1.13.0 in `shadow` mode on 2026-10-07 between 06:06 and 06:09 UTC. None comes from real use: on 2026-10-07 Flow's state directory held no live record of this site. Each run is a small project built for this measurement, in which a real test command ran on macOS and exited 0: pytest (also as `python3 -m pytest` and through `make test`), unittest, doctest, Node's test runner through `npm test`, `go test` (also through `make test`), and bash test scripts that print their own counts or TAP output. The captured output went through the shipped hook as a successful Bash call, so each request had the shape a live one would. Flow records all 49 runs as passing.

Each run was labelled from how its project was built, before any answer was read:

| Label | Runs | Meaning |
|---|---|---|
| `executed` | 18 | at least one test ran (some projects also have skipped or expected-failure tests, or a filter) |
| `none_ran` | 17 | no test was executed: no test files, a filter that matched nothing, a benchmark only, `pytest --collect-only`, or a test script that found no files |
| `all_skipped` | 14 | tests were found and every selected one was skipped |

The set therefore holds 31 runs the site should catch (17 `none_ran` and 14 `all_skipped`) and 18 it must leave passing, all of them constructed.

Two labels are judgment calls: `pytest --collect-only` is `none_ran` because nothing executed, although the question's wording ("found, collected or ran zero tests") does not plainly cover it; and a test expected to fail that did fail counts as `executed`.

**Checks on the measurement, made before the answers were read.** A result produced by the set or the labels rather than by the model would show up as one of these:

- Labels influenced by the answers. Checked: each label was written into the case list on 2026-10-06, the day before any request, and the label file is identical to a copy saved before the first answer was recorded.
- A class with no examples. Checked: each label has at least 14 runs.
- A constant answer scoring well. Answering `executed` every time would catch nothing; answering `none_ran` every time would wrongly downgrade all 18 runs that ran tests. The results below therefore report wrong downgrades and catches separately and give no single accuracy figure.
- Agreement that comes from the summary line spelling the answer out. This one holds. On the 45 runs whose output shows how many tests ran, the model's leading choice matched the label 45 times. On the 4 whose output does not (`go test` without `-v` when every test is skipped prints only `ok <package>`; `python3 -m doctest` on a file with no examples prints nothing; a Node suite skipped with `describe.skip` reports "tests 0, skipped 0"; a `make test` that only prints "No tests yet"), it matched once. This set therefore measures how well the model reads a runner's summary. It does not measure real output, which can be long, noisy or coloured, or shortened before the hook sees it.

**Answers.** All 49 requests got a reply; none failed in transport. 41 replies had a confidence of 0.9 or more (recorded as `answered`) and 8 had less (`below-threshold`, the only no-answer reason seen). Each of the 41 answered replies matched its label. Higher confidence meant a right answer more often:

- The 46 leading choices that matched the label had a median confidence of 1.0; 41 were at 0.9 or more, and the others were 0.81, 0.74, 0.68, 0.46 and 0.45.
- The 3 that did not match were at 0.79, 0.69 and 0.53, all below 0.8, and all among the 4 runs whose output does not show the count: the quiet `go test` with every test skipped (`executed`), the silent doctest (`unclear`), and the `describe.skip` suite (`none_ran` instead of `all_skipped`).
- On the 18 runs that ran tests, the model chose `executed` every time. The least sure was a plain `go test`, which prints only `ok <package>`: `executed` at confidence 0.81, with a probability of 0.01 on the two downgrade answers together.

**Threshold sweep.** A run is downgraded when the answer is `none_ran` or `all_skipped` at or above the threshold. Fewer wrong downgrades is better; more catches is better.

| Threshold | Runs that ran tests, wrongly downgraded (of 18) | `none_ran` runs caught (of 17) | `all_skipped` runs caught (of 14) | All caught (of 31) |
|---|---|---|---|---|
| 0.5 | 0 | 14 | 13, one of them with the reason "no tests ran" | 27 |
| 0.7 | 0 | 13 | 12 | 25 |
| 0.8 | 0 | 12 | 12 | 24 |
| 0.9 | 0 | 12 | 12 | 24 |
| 0.95 | 0 | 10 | 11 | 21 |

The next table counts the model's choice against the label at each threshold. "Below the threshold" means the reply's confidence was under that threshold, so Flow would take it as no answer and leave the run passing.

| Label | Model's choice | 0.5 | 0.7 | 0.8 | 0.9 | 0.95 |
|---|---|---|---|---|---|---|
| `executed` (18) | `executed` | 18 | 18 | 18 | 17 | 17 |
| | below the threshold | 0 | 0 | 0 | 1 | 1 |
| `none_ran` (17) | `none_ran` | 14 | 13 | 12 | 12 | 10 |
| | `unclear` | 1 | 0 | 0 | 0 | 0 |
| | below the threshold | 2 | 4 | 5 | 5 | 7 |
| `all_skipped` (14) | `all_skipped` | 12 | 12 | 12 | 12 | 11 |
| | `none_ran` | 1 | 0 | 0 | 0 | 0 |
| | `executed` | 1 | 1 | 0 | 0 | 0 |
| | below the threshold | 0 | 1 | 2 | 2 | 3 |

Every run that is not caught stays passing; no run that ran tests is downgraded at any of these thresholds, and every catch except the one at 0.5 gives the reason that matches the label. At 0.9 the site would change Flow's decision on 24 of the 49 runs, each of them a run in which no test executed. The 7 it misses at 0.9 are the two `pytest --collect-only` runs (0.46 and 0.45), `go test` on a package with no test files (0.74), `make test` running Go with no test files (0.68), and the three runs whose output does not show the count. A unittest run in which every test was skipped sits at exactly 0.90 and is lost at 0.95.

**Time.** No request ended as a timeout at the default `timeoutMs` of 3000 ms. The hook's whole run, including its start-up, the mode check and the client, took 2.9 s at the median and 6.2 s at the 95th percentile (longest 6.9 s). The client on its own was timed on 2026-10-07 by sending the same 49 states once more, one at a time, through `flow-s1.sh` to jev-1.13.0, and measuring each call from start to exit (lower is better). All 49 calls got a reply from the provider and none failed or timed out. A call took 1.36 s at the median and 1.66 s at the 95th percentile (the 47th of the 49 times in order); the longest took 1.80 s and the shortest 1.19 s. The client's records do not carry the length of the request, so these times also include the client's own start-up (reading settings, the mode check, starting Python); the request alone took no longer than they show. The hook times above come from the earlier send, about three hours before, and also include the hook's own work, so the two sets of times are not a like-for-like comparison.

**Threshold chosen: none; 0.9 stays provisional.** The rule for this site is that no run that really passed may be downgraded at the chosen threshold. Here none is downgraded at any threshold from 0.5 to 0.95, so the rule does not pick a value. More importantly, the runs it was checked on are 18 short, clean, constructed runs, not passes from real use, and those are what this rule is about. With 0 wrong downgrades out of 18, the true rate on runs like these could still be as high as about 18.5% (the upper end of the exact 95% range). The number of runs is not the shortfall: the minimum set for these comparisons, at least 40 labelled runs and at least 10 of each outcome, is met with 49 runs (18, 17 and 14). The shortfall is that none of the runs comes from real use. The data is consistent with 0.9, and 0.8 would catch the same 24 runs, but it cannot confirm either value.

**What the set does not cover.** No Jest, Vitest, Mocha, cargo, RSpec or bats runs; no colour codes or progress bars; only one output longer than 200 lines; and no pytest or unittest run on an empty project, because both exit 5 when nothing ran, and a failed call is never asked.

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

`result` is `answered` or the reason the question failed. `current` is the decision Flow made without System One, passed with `--current`. `ref` names the item the questions were about, passed with `--ref` (null without it), so a shadow record can be matched to that item when shadow records are compared with the decisions taken; it is never sent to the provider. The state itself is never recorded; its sha256 identifies it.

Records go to `.flow/runs/<run-id>/system-one.jsonl` when `--run-id` names an existing run. Otherwise they go to `system-one.jsonl` in the per-user state directory (`~/.claude/flow-state`, or a `FLOW_STATE_DIR` you set; one the repository chose is ignored, see [README: Per-user locations](../README.md#per-user-locations)). Nothing is written through a symlink or to anything but a regular file, and no run directory is created. A record that cannot be written, including one whose lock another process holds for more than a second, is a warning and does not change the answer.
