# Planted unquoted placeholders

Each metadata argument below carries an alternation inside braces, so the `|` is a shell pipe.

```bash
journal-record.sh --issue 1 --type review-cycle --metadata path={A|B}
journal-record.sh --issue 1 --type stranger-test --metadata result={PASS|BLOCK}
```
