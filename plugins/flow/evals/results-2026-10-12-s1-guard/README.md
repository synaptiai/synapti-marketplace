# System One guard sites: comparison data (2026-10-12)

The measurement behind `guard.command-intent` and `guard.planted-instructions`. The bars, labelling rules and sets were fixed in `.decisions/issue-297.md` before any request was sent. The results are in `summary.md`, and `references/system-one.md` reports them.

| File | What it is |
|---|---|
| `commands.jsonl` | Labelled commands: `{id, command, cwd, label, class, source, reason}`. The classes are `real-sent`, `real-blocked`, `constructed-missed`, `constructed-caught` and `constructed-false-block`. |
| `constructed-commands.jsonl` | The constructed rows of `commands.jsonl`, each with its label and reason. |
| `texts.jsonl` | Labelled texts: `{id, command, output, label, form, source}`. It holds `texts-real.jsonl` and `texts-constructed.jsonl`. |
| `texts-real.jsonl` | 60 real issue and pull request texts of this repository, labelled plain. |
| `texts-constructed.jsonl` | 20 hard-plain texts, and the 60 real texts each with one planted instruction (12 per form). |
| `ruledout.json` | How many distinct real commands from this repository's transcripts the cheap check rules out. |
| `records-<set>.jsonl`, `meta-<set>.jsonl`, `run-<set>.json` | What each send recorded, what happened to each row, and the run's commit, model and times. |
| `timing.jsonl`, `timing-run.json` | Per command, the time taken by the pattern checks and by the new hook off, in shadow and on. |
| `summary.md`, `summary.json` | Results against the bars. |

## Scripts

- `build_sets.py`: collects the real commands from the transcripts.
- `ruled_out.sh`: applies the hooks' cheap check.
- `fetch_texts.py`: reads the real texts with `gh`.
- `make_texts.py`: builds the constructed texts.
- `run.py`: sends one request per row, in shadow mode, through the hooks' own state builders.
- `time_hooks.py`: measures the timings.
- `summarize.py`: writes the summary with `--write` and runs the acceptance checks with `--check ac2|ac3|ac4`; `ac3` and `ac4` also check that every row was sent with the state the shipped hooks build for it now.

`tests/e2e-s1-guard.test.sh` tests each script against a stub server.
