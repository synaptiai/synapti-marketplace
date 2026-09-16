# Look-alikes the sweep must not count

```bash
journal-record.sh --issue 1 --type review-cycle --metadata path="$REVIEW_PATH"
journal-record.sh --issue 1 --type escalation-resolved --metadata "outcome=$OUTCOME"
journal-record.sh --issue 1 --type dropped-finding --metadata reason=self-review-refuted
```

Prose may still name the values a reviewer chooses between, such as {A|B}, outside a command.
