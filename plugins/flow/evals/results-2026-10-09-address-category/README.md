# address.category wording comparison (2026-10-09)

The 2026-10-07 replay found that the `address.category` question over-raises review feedback to P1 on TypeSafe jev-1.13.0. This directory measures one alternative wording, in which each priority is described by what happens if the pull request is merged as it is, against the current wording, on the same 200 labelled items. The wording, the rules and bars 1 to 3 were written in `.decisions/issue-296.md` before any provider call; bar 4, a blind ruled sample, was added while the alternative was running, before any result was read. The result and its reading are in `references/system-one.md`, under the `address.category` wording comparison.

## Files

| File | What it holds |
|---|---|
| `current.yaml` | The shipped `address.category` site at commit b3866e96: the control wording |
| `alternative.yaml` | The registered alternative wording; option ids, type and threshold unchanged |
| `run.sh` | Runs the shipped `COMMENT_CATEGORY_BLOCK` of `commands/address.md` once per item, from a copy of the plugin outside any repository with the form's wording patched in, the site in shadow mode |
| `summarize.py` | Turns the records into the figures; `--write` writes `summary.md` and `summary.json`; `--check ac1\|ac2\|ac3` checks the issue's acceptance criteria |
| `records-<form>.jsonl` | The client's shadow records, one per item asked |
| `meta-<form>.jsonl` | Per item: refused or not, the block's output, the sha256 of the state sent and whether it was truncated |
| `run-<form>.json` | The sent wording's sha256, the model, the plugin commit and the run's start and end |
| `summary.md`, `summary.json` | The figures for both forms and the bars |
| `rulings.jsonl` | The user's blind rulings for bar 4, when asked for (`summarize.py --sample` lists the items) |

The items are `../results-2026-10-07-address-s1/address-category.jsonl`: 200 finding rows from Flow's review sessions on pull requests 150 to 255, with the priority marker removed from the text. Their label is the priority the reviewing session gave.

## How to run it again

```bash
export TYPESAFE_API_KEY=...        # never printed or written by the scripts
E=plugins/flow/evals/results-2026-10-09-address-category
$E/run.sh --form current --out "$E"
$E/run.sh --form alternative --out "$E"
python3 $E/summarize.py --write
for c in ac1 ac2 ac3; do python3 $E/summarize.py --check $c; done
```

`TMPDIR` must be outside every git repository: the client refuses the user's settings when the plugin runs from inside one, and `run.sh` stops with a message if it is not. Records go to a state directory under `TMPDIR`, never to `~/.claude/flow-state`. The test `tests/e2e-address-category-replay.test.sh` runs the same scripts against a stub server.
