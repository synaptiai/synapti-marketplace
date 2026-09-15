## Confidence and signal

HIGH and MEDIUM findings enter the review decision at their priority. LOW findings, at any priority, go to Needs investigation and are excluded from the decision and the marker on someone else's pull request. A finding with no confidence counts as MEDIUM.

## Review decision

| Findings | Decision |
|---|---|
| Any HIGH or MEDIUM P1 | REQUEST_CHANGES |
| Any HIGH or MEDIUM P2 | REQUEST_CHANGES |
| HIGH or MEDIUM P3 only | COMMENT |
| None, or LOW only | APPROVE |
