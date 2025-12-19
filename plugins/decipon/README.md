# Decipon - NCI Manipulation Detection Plugin

A Claude Code plugin implementing the NCI (Narrative Credibility Index) Protocol for detecting manipulation, propaganda, and disinformation patterns in content.

## Overview

Decipon analyzes content (text or URLs) across 20 manipulation indicators grouped into 5 composite factors:

| Factor | Weight | Categories |
|--------|--------|------------|
| Emotional Manipulation | 25% | Base emotional triggers, urgency, novelty, repetition, manufactured outrage |
| Suspicious Timing | 20% | Timing correlation, beneficiary analysis, historical parallels |
| Uniform Messaging | 20% | Message uniformity, bandwagon effects, rapid shifts |
| Tribal Division | 15% | Us-vs-them framing, simplistic narratives, false dilemmas |
| Missing Information | 20% | Context gaps, authority issues, dissent suppression, cherry-picking, fallacies, framing |

## Installation

```bash
claude plugin install /path/to/decipon
```

Or from GitHub:
```bash
claude plugin install github:danielbentes/decipon
```

## Commands

### `/decipon:analyze <content>`

Full NCI analysis with 20-category scoring and dual perspectives.

```bash
/decipon:analyze https://example.com/article
/decipon:analyze "BREAKING: Shocking report reveals what they don't want you to know!"
```

### `/decipon:score <content>`

Quick manipulation score (0-100) for rapid triage.

```bash
/decipon:score https://example.com/article
```

### `/decipon:verify <content>`

Verify factual claims using deep research methodology. Fact-checks key assertions and can update NCI scores.

```bash
/decipon:verify https://example.com/article
/decipon:verify --claims "90% of experts agree" "Studies show..."
```

### `/decipon:report <content> [--format json|markdown] [--output filename]`

Generate formal report for sharing/archiving.

```bash
/decipon:report https://example.com/article --format json --output analysis.json
```

### `/decipon:deep-research <topic>`

Conduct comprehensive research using Time-Tested Diffusion methodology.

```bash
/decipon:deep-research "Current state of nuclear fusion energy"
```

### `/decipon:quick-research <question>`

Quick research with source verification (2-3 searches, lighter than deep-research).

```bash
/decipon:quick-research "When did NIF achieve fusion ignition?"
```

### `/decipon:critique <content>`

Red team adversarial critique of a document or claim.

```bash
/decipon:critique /path/to/document.md
/decipon:critique "90% of experts agree that..."
```

## Recommended Workflow

1. **Quick triage**: `/decipon:score` - Get initial manipulation score
2. **Full analysis**: `/decipon:analyze` - If score > 25 (Moderate or higher)
3. **Fact-check**: `/decipon:verify` - If score > 50 (High or higher)
4. **Document**: `/decipon:report` - For formal records

## Severity Scale

| Score | Indicator | Risk Level |
|-------|-----------|------------|
| 0-25 | [·] | Low - Normal consumption |
| 26-50 | [!] | Moderate - Verify claims |
| 51-75 | [!!] | High - Cross-reference, strong skepticism |
| 76-100 | [!!!] | Severe - Likely manipulation |

## Key Features

- **Pattern-based detection**: Identifies manipulation techniques regardless of truth value
- **Dual perspectives**: Generates both manipulative and legitimate interpretations
- **Evidence-grounded**: Every score backed by specific quotes/patterns
- **URL support**: Fetches and analyzes web content via WebFetch
- **Deep research integration**: Built-in fact-checking with source evaluation and claim verification

## Agents

The plugin includes specialized agents that can be invoked for specific tasks:

| Agent | Purpose |
|-------|---------|
| `nci-analyzer` | Performs full NCI content analysis |
| `perspective-generator` | Generates balanced dual perspectives |
| `claim-verifier` | Verifies claims using deep research |
| `deep-researcher` | Comprehensive research using TTD methodology |
| `fact-checker` | Verification specialist for claims |

## Deep Research Integration

Decipon includes a complete deep research skill for fact-checking claims discovered during NCI analysis. Deep research is **built into the NCI workflow as Step 5**.

### Analysis Workflow (7 Steps)

```
1. Input Processing (text or URL)
2. Score all 20 categories (1-5 scale)
3. Calculate 5 composite factors
4. Calculate overall score (0-100)
5. Check deep research triggers ← Automatic verification
6. Generate perspectives (manipulative + legitimate)
7. Output report (includes verification results)
```

### Automatic Triggers

Deep research is automatically triggered when ANY condition is met:

| Trigger | Threshold | Verification Focus |
|---------|-----------|-------------------|
| Overall NCI Score | > 40 | Verify key claims |
| Suspicious Timing | > 3 | Correlate events, timeline |
| Authority Issues (Cat 16) | > 3 | Verify credentials |
| Cherry-Picking (Cat 18) | > 3 | Find omitted context |
| Historical Parallels | > 2 | Research precedent campaigns |

### When Triggers Met

1. Extract 3-5 key factual claims
2. Invoke `fact-checker` agent
3. Apply deep research methodology
4. Track verification results
5. Adjust NCI scores based on findings

### Verification Capabilities

- **Claim extraction**: Identifies key factual assertions
- **Source evaluation**: Scores source confidence (1-100)
- **Contradiction handling**: Tracks and resolves conflicting sources
- **Score adjustment**: Updates NCI scores based on verification findings

### Output Includes Verification

When deep research is triggered, the report includes:

```markdown
## Claim Verification
| Claim | Status | Confidence | Source |
|-------|--------|------------|--------|
| "90% of experts..." | CONTRADICTED | 85% | reuters.com |
| "Studies show..." | VERIFIED | 90% | nature.com |

**Score Adjustment**: 55 → 62 (+7 due to verification)
```

### Source Confidence Scale

| Source Type | Confidence |
|-------------|------------|
| Peer-reviewed research | 85-100 |
| Official documentation | 85-95 |
| Government/institutional | 75-90 |
| Major news (Reuters, AP) | 70-85 |
| Industry publications | 50-75 |
| Blogs/forums | 20-50 |

## The 20 Categories

### Emotional Manipulation
1. Base Emotional Triggers - Fear, anger, hope exploitation
2. Urgency Creation - Artificial time pressure
3. Novelty/Exclusivity - "Only we know" framing
4. Strategic Repetition - Key phrase hammering
5. Manufactured Outrage - Anger amplification

### Suspicious Timing
6. Timing Correlation - Convenient narrative emergence
7. Beneficiary Analysis - Who gains from belief
8. Historical Parallels - Matches known campaigns

### Uniform Messaging
9. Message Uniformity - Identical talking points
10. Bandwagon Effects - Social proof manipulation
11. Rapid Narrative Shifts - Coordinated pivots

### Tribal Division
12. Us-vs-Them Framing - Enemy creation
13. Simplistic Narratives - False simplicity
14. False Dilemmas - Binary choice forcing

### Missing Information
15. Context Gaps - Strategic omissions
16. Authority Issues - Credential manipulation
17. Dissent Suppression - Alternative silencing
18. Cherry-Picking - Selective evidence
19. Logical Fallacies - Reasoning errors
20. Framing/Priming - Perspective manipulation

## Methodology

The NCI Protocol uses pattern recognition rather than truth evaluation:
- Scores indicate manipulation risk, not accuracy
- Low scores don't mean "true"
- High scores don't mean "false"
- Focus is on HOW content persuades, not WHAT it claims

## License

MIT License - See LICENSE file for details.

## Author

Daniel Bentes

## Repository

https://github.com/danielbentes/decipon
