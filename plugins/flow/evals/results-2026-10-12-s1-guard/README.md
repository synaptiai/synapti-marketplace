# System One guard sites: comparison data (2026-10-12)

The measurement behind `guard.planted-instructions`, which ships, and `guard.command-intent`, which was measured and is not shipped. The bars, labelling rules and sets were fixed in `.decisions/issue-297.md` before any request was sent. The results are in `summary.md`, and `references/system-one.md` reports them.

| File | What it is |
|---|---|
| `texts.jsonl` | Labelled texts: `{id, command, output, label, form, source}`. It holds `texts-real.jsonl` and `texts-constructed.jsonl`. |
| `texts-real.jsonl` | 60 real issue and pull request texts of this repository, labelled plain. |
| `texts-constructed.jsonl` | 20 hard-plain texts, and the 60 real texts each with one planted instruction (12 per form). |
| `commands.jsonl` | Labelled commands: `{id, command, cwd, label, class, source, reason}`. The classes are `real-sent`, `real-blocked`, `constructed-missed`, `constructed-caught` and `constructed-false-block`. |
| `candidates.jsonl`, `labels-real.jsonl`, `constructed-commands.jsonl` | The real commands drawn from this repository's transcripts, their labels, and the constructed commands, which `merge_sets.py` joins into `commands.jsonl`. |
| `ruledout.json` | How many distinct real commands from the transcripts the command hook's cheap check ruled out. |
| `credentialskip.json` | Of the commands the cheap check did not rule out, how many the command hook did not send: `unreadable` for a command outside the plain form its masking read, `skipped` for one that might hold a credential. |
| `records-<set>.jsonl`, `meta-<set>.jsonl`, `run-<set>.json` | What each send recorded, what happened to each row, and the run's commit, model and times. |
| `timing.jsonl`, `timing-run.json` | Per command, the time taken by the pattern checks and by the command hook off, in shadow and on. |
| `summary.md`, `summary.json` | Results against the bars. |

The command files are the record of a hook that is not shipped: the commands were sent at plugin commit 8ac3d572, the shares were counted at 99ce7f28 and the timing was taken at 93765538, all on this change's branch and reachable through its pull request. The sets were last changed only to replace session ids in temporary paths with `session-id`, after the sample was drawn. The scripts that sent, counted and timed them (`run.py --set commands`, `build_sets.py`, `credential_share.py`, `ruled_out.sh`, `time_hooks.py`) and the hook they drive are at 93765538.

## Scripts

- `fetch_texts.py`: reads the real texts with `gh`.
- `make_texts.py`: builds the constructed texts.
- `merge_sets.py`: joins the labelled sets.
- `run.py --set texts`: sends one request per text, in shadow mode, through the screen hook's own state builder. It stops before sending anything when the set is empty, two rows share an id, a row's output is blank or its command is over 20,000 bytes, the settings are not an object, a text's command is one the hook does not screen, or its state cannot be built. It writes into a `partial-texts.*` folder and replaces the last complete run's files only when the run is complete, so a run that stops before then leaves them as they were and its own answers in that folder; a stop while they are being replaced can leave files of two runs, which `summarize.py` refuses.
- `summarize.py`: writes the summary with `--write` and runs the acceptance checks with `--check ac1|ac2|ac3`; `ac3` also checks that every text was sent, that the shipped hook screens its command, and that it was sent with the state the hook builds for it now. It refuses files that are not one run's: a set file, meta file and run file whose rows differ, two lines or two records for a row, a record written outside the run file's times, an answer for a row not sent, or a sent count other than the run file's; and `ac3` reports a text whose output is blank or whose command is over 20,000 bytes. A stopped run's `partial-texts.*` folder is ignored by git.

`tests/e2e-s1-guard.test.sh` tests each script against a stub server.
