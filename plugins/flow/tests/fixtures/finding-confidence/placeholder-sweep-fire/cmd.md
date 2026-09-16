# Planted unquoted placeholders

Each metadata argument below carries an alternation inside braces, so the `|` is a shell pipe.

```bash
journal-record.sh --issue 1 --type review-cycle --metadata path={A|B}
journal-record.sh --issue 1 --type stranger-test --metadata result={PASS|BLOCK}
```

An unquoted variable word-splits, and the recorder takes the last `--issue` it is given:

```bash
journal-record.sh --issue 1 --type stranger-test --metadata task_count=$N
journal-record.sh --issue 1 --type verdict --metadata pr=$PR_NUMBER
```
