# Asking about several items at once: the comparison (2026-10-12)

Whether System One gives the same answers about the criteria of one goal stop, or the findings of one review, when they are asked together in one request (`flow-s1.sh ask-many`) as when each is asked alone. The bars and the default rule were written in the issue's decision journal before any request was sent. The result is in `references/system-one.md`, "Asking about several items at once (TypeSafe jev-1.13.0, 2026-10-12)", and in `summary.md`: neither layout met the bars, so `systemOne.batch` ships `off`.

## Files

- `run.sh`: sends one set. For each group (one goal, or one review run) it asks every item alone twice (A1, A2), then together with `items-in-state` (S) and with `items-in-questions` (Q), from a copy of the plugin outside any repository, in `shadow` mode, the order of the four rotating from group to group. `run.sh --set goal|review --out <dir>` with `TYPESAFE_API_KEY` set; `--settings` names another provider.
- `summarize.py`: the figures, the five bars and the default from what `run.sh` wrote. `--write` writes `summary.md` and `summary.json`; `--check ac1`, `ac2` and `ac4` check the issue's acceptance criteria. It refuses a set whose run did not finish, and a record whose state digest is not its input's.
- `inputs-<set>.jsonl`: each item's group, key, ref and the sha256 of its state file, and for the goal set its label and kind. The review states are in `../results-2026-09-25-review/replay/shadow/base/`; the goal states are the 2026-10-07 goal replay's, kept outside the repository and named here by digest.
- `records-<set>-<send>.jsonl`: the client's records for each send, one per item.
- `meta-<set>.jsonl`: one line per client call: the send, the items, the exit status and the wall time in milliseconds.
- `run-<set>.json`: the commit, the model, the timeout and when the set ran.

The records come from commit e711abf6, named in each `run-<set>.json`. The fixes made after it change how `ask-many` handles an item it cannot send, how it names a request (`batch.id`), and how early it exits when `systemOne.batch` is off; none changes the state or the questions sent for a readable item, so the records stand for the code that ships.

The harness and the summary are tested in `tests/e2e-s1-batch.test.sh` against a stub server.
