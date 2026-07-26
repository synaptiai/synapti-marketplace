---
description: "Adjudicate whether a single statement may be said publicly. Traces the claim to its evidence, checks the claim state and disclosure approval, and returns approved, needs-evidence, or blocked with the exact qualification required."
argument-hint: <claim-text|file-path> [--register] [--audience partner|customer]
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Skill
---

# Adjudicate Claim: $ARGUMENTS

One question: can this sentence be said externally, and if so, in exactly what words?

## Required Skills

- `disclosure-gating` — the claim register, the approval boundary, and the derivation rules
- `evidence-ledger` — trace the claim to its rows and read the claim state

## References

- [`disclosure-policy-levels.md`](../references/disclosure-policy-levels.md)
- [`register-schemas.md`](../references/register-schemas.md)
- [`source-authority-and-claim-states.md`](../references/source-authority-and-claim-states.md)

## Phase 0 — Resolve

```!
_RAW="$ARGUMENTS"
echo "### Claim Arguments"
echo "ARGS=$_RAW"

__dr="${CLAUDE_PLUGIN_ROOT:-}"
[ -x "$__dr/bin/dossier-claim-scan.sh" ] || __dr=$({ echo plugins/dossier; ls -d "$HOME"/.claude/plugins/cache/synapti-marketplace/dossier/*/ 2>/dev/null | sort -Vr; echo "$HOME/.claude/plugins/marketplaces/synapti-marketplace/plugins/dossier"; } | while read -r __p; do [ -x "${__p%/}/bin/dossier-claim-scan.sh" ] && { echo "${__p%/}"; break; }; done)

echo "### Preflight"
if [ ! -x "$__dr/bin/dossier-claim-scan.sh" ]; then
  echo "CLAIM_STATE=blocked"
  echo "CLAIM_ERROR=dossier plugin scripts not found — reinstall or upgrade the plugin"
  true; exit 0
fi

OUTPUT_ROOT=$("$__dr/bin/dossier-resolve-config.sh" --default "docs/dossier" dossier.project.outputRoot 2>/dev/null)
echo "OUTPUT_ROOT=$OUTPUT_ROOT"
echo "DISCLOSURE_POLICY=$("$__dr/bin/dossier-resolve-config.sh" --default internal-only dossier.disclosure.policy 2>/dev/null)"
echo "APPROVAL_REQUIRED=$("$__dr/bin/dossier-resolve-config.sh" --default required dossier.disclosure.publicClaimApproval 2>/dev/null)"
echo "REGISTER_EXISTS=$([ -f "$OUTPUT_ROOT/00-control/claim-and-disclosure-register.md" ] && echo true || echo false)"
echo "LEDGER_EXISTS=$([ -f "$OUTPUT_ROOT/00-control/evidence-ledger.md" ] && echo true || echo false)"
true
```

A file path adjudicates every declarative sentence in the file. Bare text adjudicates that one sentence.

`--audience partner|customer` selects which destination the claim is judged against, because the same sentence can be approved for one and not the other. A partner guide may carry interface detail, rate limits, and sandbox mechanics that a customer guide may not; a customer guide is held to a plainer standard on capability and trust language. Absent the flag, judge against the stricter of the two and say which standard was applied.

## Phase 1 — Match the register

Invoke `Skill(disclosure-gating)`.

Look for an existing `CL-####` row whose **exact wording** matches. Approval attaches to a sentence, not to a topic: "we encrypt data at rest" and "all customer data is encrypted at rest" are different claims with different truth conditions, and approving the first does not approve the second.

| Register state | Verdict |
|---|---|
| Exact match, `approved` | **APPROVED** — publish as written |
| Exact match, `pending` | **BLOCKED** — approval is a human act; name who must give it |
| Exact match, `rejected` | **BLOCKED** — restate the rejection reason; check whether another sentence implies it indirectly |
| Near match, different scope or qualification | **NEEDS-EVIDENCE** — show the approved wording and the delta |
| No match | Continue to Phase 2 |

## Phase 2 — Trace to evidence

Invoke `Skill(evidence-ledger)`. Find the rows that would support the claim and check, in order:

1. Does a row exist at all?
2. Is its state `V` or `C`? Only those may go public — `R`, `I`, and `U` never can, not qualified, not softened.
3. **Does the evidence actually entail this claim, or a neighbouring one?** This is where most rejections come from.
4. Is the row current for its type, with a stated version and environment?
5. Would the claim survive stripping — does it need a limitation that a public reader will not have?

| Evidence shows | Claim says | Verdict |
|---|---|---|
| The IaC specifies three replicas | Three replicas are running | NEEDS-EVIDENCE — a claim about a file, not a deployment |
| The policy requires quarterly rotation | Keys are rotated quarterly | NEEDS-EVIDENCE — a policy is not an implemented control |
| The SLO document targets 99.9% | Availability is 99.9% | NEEDS-EVIDENCE — a target is not a measurement |
| The primary store is encrypted | All data is encrypted at rest | BLOCKED — simplification inverted a material fact |

## Phase 3 — Prohibited vocabulary

Flag any of `secure` · `compliant` · `encrypted` · `anonymous` · `private` · `real time` · `unlimited` · `always` · `never` · `guaranteed` · `fully automated` · `zero downtime` · `bank-grade` · `enterprise-ready`.

Each is a claim, not an adjective. Propose the specific replacement rather than deleting the sentence: not "real time" but "typically under 400 ms, not guaranteed"; not "anonymous" but "pseudonymized — we retain a reversible identifier". The specific version is both truer and more useful.

## Phase 4 — Leakage

```bash
bin/dossier-claim-scan.sh --file <path>   # when adjudicating a file
```

Credentials, internal locators, register IDs, internal hostnames, and configured redaction patterns are BLOCKED outright, not qualified.

## Phase 5 — Verdict

```markdown
### Claim verdict

CLAIM={verbatim}
AUDIENCE={partner|customer}
VERDICT={APPROVED|NEEDS-EVIDENCE|BLOCKED}
REGISTER_ROW={CL-####|none}
EVIDENCE={EV-####,…|none}  STATE={V|C|R|I|U|none}
APPROVAL={approved|pending|rejected|not-required}

### Publishable wording
{the exact sentence, with every limitation that keeps it true — or `none`}

### What is missing
| Gap | What would settle it | Owner |
|---|---|---|
```

The publishable wording is the useful output. A verdict of NEEDS-EVIDENCE that does not say what a *publishable* version would look like has answered the easy half of the question.

With `--register`, append a `pending` row for a claim that traces to `V`/`C` evidence. **Never write `approved`** — that is Tier 3 and a human act.

## Tier Classification

| Action | Tier | Behavior |
|---|---|---|
| Read the registers, ledger, and package | 1 | Autonomous, read-only |
| Trace a claim to its evidence and judge entailment | 1 | Autonomous |
| Run the leakage scan | 1 | Autonomous |
| Propose publishable wording | 1 | Autonomous — a proposal, not an approval |
| Append a `pending` row with `--register` | 2 | Journal — modifies the claim register |
| Mark a row `approved` | 3 | **Never automated.** The run may apply a policy; it may never act as the business, legal, security, or communications approver |
| Publish or export a claim outside the output root | 3 | **Never automated** |
