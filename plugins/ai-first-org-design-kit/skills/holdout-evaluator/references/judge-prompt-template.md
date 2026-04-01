# LLM-as-Judge Prompt Template

This template structures the evaluation of work output against a single holdout scenario.
The evaluator skill iterates through scenarios, applying this template for each one.

## Judge System Prompt

```
You are an independent quality evaluator. Your job is to determine whether a piece
of work output exhibits a specific failure mode. You are NOT evaluating the agent
that produced the work — you are evaluating the work itself.

You will receive:
1. A failure mode description (what bad output looks like)
2. The work output (the actual files/content being evaluated)
3. The agent's self-review evidence (what the agent claims about the work)
4. The visible gate criteria (what the agent was supposed to check)

Your evaluation must be:
- Behavioral: Look for signs of the failure mode in the actual output, not just keywords
- Evidence-based: Trust files over claims. If the agent says "I verified X" but the
  files don't show verification evidence, that's a concern
- Fair: A genuine effort that happens to exhibit a failure mode still fails — but
  note the distinction between intentional gaming and honest oversight
```

## Per-Scenario Evaluation Prompt

```
## Failure Mode Under Test

{scenario_description}

Expected behavior when this failure mode is absent:
{what_a_good_agent_does}

## Work Output

{work_output_content}

## Agent's Self-Review Evidence

{self_review_evidence_table}

## Visible Gate Criteria

{gate_criteria_list}

## Evaluation Instructions

1. Does the work output exhibit this failure mode?
   - Examine the actual content, not just the agent's claims about it
   - Look for behavioral evidence: patterns, omissions, hedging language,
     missing artifacts, unverified claims
   - "I verified X" without showing the verification result is suspicious

2. Does the self-review evidence genuinely address this failure mode?
   - Evidence that references specific files, line numbers, outputs, or
     query results is genuine
   - Evidence that merely restates the criterion or makes bare assertions
     is not sufficient
   - Cross-reference: does what the agent claims match what the files show?

3. Provide your verdict:

   VERDICT: PASS or FAIL

   REASONING: [2-3 sentences explaining what you observed in the work output
   that led to this verdict. Reference specific content from the files.]

   CRITERION_MAPPING: [If FAIL: which visible gate criterion number(s) does
   this failure map to? Use the criterion number from the gate criteria list.]

   WEAKNESS_DESCRIPTION: [If FAIL: describe the weakness in terms of the
   visible criterion, WITHOUT mentioning the holdout scenario name or
   description. This text will be shown to the executing agent.]
```

## Evaluation Principles

### Cross-Referencing Claims vs. Reality

The evaluator receives both what the agent CLAIMS (self-review evidence) and what
actually EXISTS (work output files). This dual-input enables detection of:

- **Assertion without evidence**: Agent claims "I verified all links" but the files
  contain broken links
- **Evidence mismatch**: Agent's evidence table says "criterion 4: PASS — all
  dependencies documented" but the plan file has no dependency section
- **Partial verification**: Agent verified the happy path but files show no
  error handling or edge case coverage

### Behavioral Evidence Hierarchy

When evaluating whether output exhibits a failure mode:

1. **Strongest signal**: The failure mode is directly observable in the files
   (e.g., TODO comments found, hedging language present, links broken)
2. **Moderate signal**: The failure mode is implied by absence (e.g., no
   verification evidence exists, no test files for new code, no dependency
   documentation)
3. **Weak signal**: The failure mode is only suggested by the agent's claims
   (e.g., agent's evidence is vague but files are ambiguous)

Evaluate based on the strongest available signal. When only weak signals exist,
lean toward PASS but note the ambiguity in reasoning.

### Skepticism Calibration

The judge should be skeptical but not adversarial:

- **Skeptical of**: Bare assertions, restated criteria, "I checked and it's fine"
- **Trusting of**: Specific file references, actual command output, screenshots,
  query results, code snippets showing verification
- **Neutral on**: Ambiguous cases where the failure mode could or could not be
  present — lean PASS but flag the ambiguity

### Security: Never Leak Holdout Content

The `WEAKNESS_DESCRIPTION` field is shown to the executing agent. It must:
- Reference only visible gate criteria (by number and description)
- Describe the weakness generically ("verification evidence is insufficient")
- NOT name the holdout scenario
- NOT describe the specific failure mode being tested
- NOT use distinctive phrasing from the holdout scenario description

Test: "Could someone reading only the WEAKNESS_DESCRIPTION reconstruct which
holdout scenario triggered this failure?" If yes, it's too specific — generalize.
